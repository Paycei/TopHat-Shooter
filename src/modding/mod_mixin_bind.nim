## Binds the game's {.moddable.} procs to the mixin runtime (mod_mixin).
##
## `bindModdables()` is called where every module with moddable procs has
## been compiled (main.nim, after its imports, and again at its end for its
## own procs). It imports those modules and, for each proc mod_patch_core
## registered, generates from its typed signature:
##   * the dispatcher the public proc calls while a mod wraps it (mixFn_*),
##   * `orig`, the native that runs the original body with arguments from a
##     script (the innermost link of a chain),
##   * `call`, the native engine.call uses (the public proc, defaults filled
##     in by Nim when a script passes fewer arguments).
## A proc whose parameters or result scripts cannot hold (raw pointers,
## procs, GPU resources...) is registered as such and cannot be wrapped.

import std/[macros, strutils]
import lua_bridge, mod_hooks, mod_deep, mod_patch_core, mod_mixin
export lua_bridge, mod_hooks, mod_deep, mod_patch_core, mod_mixin

var bound {.compileTime.}: seq[bool]   ## per moddableRegistry entry: generated already

proc normPath(p: string): string =
  ## A path with forward slashes and no "dir/../" (for comparisons).
  var parts: seq[string]
  for part in p.replace('\\', '/').split('/'):
    if part == "..":
      if parts.len > 0: parts.setLen(parts.len - 1)
    elif part != ".": parts.add part
  parts.join("/").toLowerAscii

proc stemOfPath(path: string): string =
  var a = 0
  for i in 0 ..< path.len:
    if path[i] in {'/', '\\'}: a = i + 1
  result = path[a .. ^1]
  if result.len > 4 and result[^4 .. ^1] == ".nim":
    result.setLen(result.len - 4)

type ParamInfo = object
  name: string
  typ: NimNode      ## the type (without `var` / `sink`)
  isVar: bool
  isOut: bool       ## an `out` parameter: engine.call returns its value too
  isSink: bool      ## a `sink` parameter: the argument is moved in
  isOpen: bool      ## openArray / varargs: travels as (first element, length)
  elem: NimNode     ## an openArray's element type

proc outParams(sym: NimNode): seq[string] =
  ## Names of the `out` parameters (a typed signature shows them as `var`).
  let impl = sym.getImpl
  if impl.kind notin {nnkProcDef, nnkFuncDef}: return
  for i in 1 ..< impl[3].len:
    let d = impl[3][i]
    if d[^2].kind == nnkOutTy or d[^2].repr.startsWith("out "):
      for j in 0 ..< d.len - 2: result.add $d[j]

proc paramsOf(van: NimNode): tuple[params: seq[ParamInfo], ret: NimNode] =
  let t = getTypeImpl(van)
  expectKind t, nnkProcTy
  let fp = t[0]
  result.ret = fp[0]
  let outs = outParams(van)
  for i in 1 ..< fp.len:
    let d = fp[i]
    var typ = d[^2]
    var isVar = false
    var isSink = false
    if typ.kind == nnkVarTy:
      isVar = true
      typ = typ[0]
    elif typ.kind == nnkBracketExpr and typ[0].kind == nnkSym and $typ[0] == "sink":
      isSink = true
      typ = typ[1]
    var isOpen = false
    var elem: NimNode = nil
    if typ.kind == nnkBracketExpr and typ[0].kind == nnkSym and
       ($typ[0] == "openArray" or $typ[0] == "varargs"):
      isOpen = true
      elem = typ[1]
    for j in 0 ..< d.len - 2:
      result.params.add(ParamInfo(name: $d[j], typ: typ, isVar: isVar, isOut: $d[j] in outs,
                                  isSink: isSink, isOpen: isOpen, elem: elem))

proc isVoid(t: NimNode): bool =
  t.kind == nnkEmpty or (t.kind == nnkSym and $t == "void")

const ResourceViews = ["raylib.getFontDefault", "raylib.getShapesTexture"]
  ## raylib getters of resources raylib keeps: the result is a view, never unloaded.

proc nativeParams(): array[4, NimNode] =
  [newEmptyNode(), newIdentDefs(ident"vm", bindSym"VM"),
   newIdentDefs(ident"sargs", nnkBracketExpr.newTree(ident"openArray", bindSym"ScriptValue")),
   newIdentDefs(ident"ret", nnkVarTy.newTree(bindSym"RetVals"))]

const TextOnlyPaths = ["ui_helpers.fitPathTail"]
  ## procs whose path parameter is only text (never opened)

proc isPathParam(p: ParamInfo): bool =
  ## A string parameter that names a file or folder (raylib's fileName,
  ## vsFileName...; the game's path, dir, file...).
  if p.isVar or p.isOpen or p.typ.kind != nnkSym or $p.typ != "string": return false
  let n = p.name.toLowerAscii
  n in ["path", "dir", "file", "folder", "dest", "destdir"] or
    n.endsWith("filename") or n.endsWith("filepath") or n.endsWith("dirpath")

proc writesFiles(name: string): bool =
  ## Whether a proc's path arguments are written to (by its name, after the
  ## module's): those may only point into the mod's mod.dataDir().
  let n = name[name.rfind('.') + 1 .. ^1].toLowerAscii
  for verb in ["save", "export", "write", "delete", "remove", "make", "create", "rename",
               "move", "copy", "take", "dump", "extract", "install", "forget"]:
    if n.startsWith(verb): return true

proc callNative(params: seq[ParamInfo], ret: NimNode, required: int, name: string,
                target: NimNode): NimNode =
  ## The native engine.call runs: `target` (a proc, or a symbol of one) with
  ## a script's arguments, the missing trailing ones left to their defaults.
  ## `out` parameters take no argument: they come back after the result.
  ## Path arguments go through the mod file sandbox (gatedPath).
  var scriptIdx: seq[int]   # per parameter: the script argument it reads (-1: an out one)
  var n = 0
  var required = required
  for i, p in params:
    if p.isOut and not p.isOpen:
      scriptIdx.add -1
      if i < required: dec required
    else:
      scriptIdx.add n
      inc n
  let void = isVoid(ret)
  let vmP = ident"vm"
  let sargs = ident"sargs"
  let retP = ident"ret"
  var callBody = newStmtList()
  callBody.add quote do:
    if `sargs`.len < `required` or `sargs`.len > `n`:
      mixArgCount(`name`, `required`, `n`, `sargs`.len)
  var argExprs: seq[NimNode]
  for i, p in params:
    let si = scriptIdx[i]
    let path = newLit(name & " argument " & $(si + 1))
    if si < 0:   # an out parameter: a local the call fills
      let t = genSym(nskVar, "t" & $i)
      callBody.add nnkVarSection.newTree(newIdentDefs(t, p.typ))
      argExprs.add t
    elif p.isOpen:
      let s = genSym(nskVar, "s" & $i)
      callBody.add nnkVarSection.newTree(newIdentDefs(s, nnkBracketExpr.newTree(ident"seq", p.elem)))
      callBody.add newIfStmt((infix(newDotExpr(sargs, ident"len"), ">", newLit(si)),
        newCall(bindSym"mixTakeSeq", vmP, newCall(bindSym"arg", sargs, newLit(si)), s, path)))
      argExprs.add s
    else:
      let t = genSym(nskVar, "t" & $i)
      let pv = genSym(nskVar, "p" & $i)
      callBody.add nnkVarSection.newTree(newIdentDefs(t, p.typ))
      callBody.add nnkVarSection.newTree(newIdentDefs(pv, nnkPtrTy.newTree(p.typ), newCall(ident"addr", t)))
      callBody.add newIfStmt((infix(newDotExpr(sargs, ident"len"), ">", newLit(si)),
        newAssignment(pv, newCall(bindSym"mixTake", vmP, newCall(bindSym"arg", sargs, newLit(si)),
                                  newNilLit(), newLit(si), t, newLit(p.isVar), path))))
      if isPathParam(p) and name notin TextOnlyPaths:
        callBody.add newIfStmt((infix(newDotExpr(sargs, ident"len"), ">", newLit(si)),
          newAssignment(nnkBracketExpr.newTree(pv), newCall(bindSym"gatedPath", vmP,
            nnkBracketExpr.newTree(pv), newLit(writesFiles(name)), path))))
      argExprs.add (if p.isSink: newCall(ident"move", nnkBracketExpr.newTree(pv))
                    else: nnkBracketExpr.newTree(pv))
  var outVals: seq[NimNode]   # `out` parameters come back after the result
  for i, p in params:
    if p.isOut and not p.isOpen:
      outVals.add newCall(bindSym"nimToScript", argExprs[i], newLit(name & " " & p.name))
  let resultFn = (if name in ResourceViews: bindSym"resultView" else: bindSym"mixResult")
  var caseStmt = nnkCaseStmt.newTree(newDotExpr(sargs, ident"len"))
  for k in required .. n:
    var c = newCall(target)
    var cut = 0   # parameters passed by position: through the k-th script argument
    for i in 0 ..< params.len:
      if scriptIdx[i] >= 0 and scriptIdx[i] < k: cut = i + 1
    for i in 0 ..< cut: c.add argExprs[i]
    for i in cut ..< params.len:   # out ones after it: by name (defaults in between)
      if scriptIdx[i] < 0: c.add nnkExprEqExpr.newTree(ident(params[i].name), argExprs[i])
    var branch: NimNode
    if outVals.len == 0:
      branch =
        if void: newStmtList(c, newCall(bindSym"setRet", retP, newCall(bindSym"NilValue")))
        else: newStmtList(newCall(bindSym"setRet", retP, newCall(resultFn, c, newLit(name))))
    else:
      let rv = genSym(nskLet, "r")
      var vals = newNimNode(nnkBracket)
      if void: branch = newStmtList(c)
      else:
        branch = newStmtList(newLetStmt(rv, c))
        vals.add newCall(resultFn, rv, newLit(name))
      for o in outVals: vals.add copyNimTree(o)
      branch.add newCall(bindSym"setRet", retP, vals)
    caseStmt.add nnkOfBranch.newTree(newLit(k), branch)
  caseStmt.add nnkElse.newTree(nnkDiscardStmt.newTree(newEmptyNode()))
  callBody.add caseStmt
  result = newProc(newEmptyNode(), nativeParams(), callBody, nnkLambda)
  result.addPragma(ident"nimcall")   # (a SlotNative)

proc supportExprs(params: seq[ParamInfo], ret: NimNode): tuple[supported, problem: NimNode] =
  ## Compile-time expressions: whether every parameter and the result are
  ## something scripts can hold (and copy, where they are copied), and the
  ## first problem otherwise.
  var supportedExpr = newLit(true)
  var problemExpr = newLit("")
  for i in countdown(params.len - 1, 0):
    let p = params[i]
    let t = (if p.isOpen: p.elem else: p.typ)
    var test = newCall(nnkBracketExpr.newTree(bindSym"scriptable", t))
    if not p.isVar and not p.isSink:   # passed by value: copied (a resource is not: a handle)
      test = infix(test, "and", newPar(infix(newCall(nnkBracketExpr.newTree(bindSym"copyable", t)), "or",
                                             newCall(nnkBracketExpr.newTree(bindSym"resourceType", t)))))
    test = newPar(test)
    supportedExpr = infix(test, "and", supportedExpr)
    problemExpr = nnkIfExpr.newTree(
      nnkElifExpr.newTree(prefix(test, "not"),
                          newLit("parameter " & p.name & " is a " & t.repr)),
      nnkElseExpr.newTree(problemExpr))
  if not isVoid(ret):
    let test = newPar(infix(newCall(nnkBracketExpr.newTree(bindSym"scriptable", ret)), "and",
                            newPar(infix(newCall(nnkBracketExpr.newTree(bindSym"copyable", ret)), "or",
                                         newCall(nnkBracketExpr.newTree(bindSym"resourceType", ret))))))
    supportedExpr = infix(test, "and", supportedExpr)
    problemExpr = nnkIfExpr.newTree(
      nnkElifExpr.newTree(prefix(test, "not"), newLit("the result is a " & ret.repr)),
      nnkElseExpr.newTree(problemExpr))
  (supportedExpr, problemExpr)

proc copyableResult(ret: NimNode): NimNode =
  ## (A wrapped proc's result is stored in the caller's result too: copyable only.)
  if isVoid(ret): newLit(true) else: newCall(nnkBracketExpr.newTree(bindSym"copyable", ret))

proc keyAndSignature(name, procName: string, params: seq[ParamInfo], ret: NimNode): tuple[key, sig: string] =
  var key = name & "("
  var sig = procName & "("
  for i, p in params:
    if i > 0:
      key.add ", "
      sig.add ", "
    key.add (if p.isVar: "var " else: "") & p.typ.repr
    sig.add p.name & ": " & (if p.isVar: "var " else: "") & p.typ.repr
  key.add ")"
  sig.add ")"
  if not isVoid(ret): sig.add ": " & ret.repr
  (key, sig)

macro bindOne(van: typed, flag: typed, disp: typed, name: static string,
              qualifier: static string, public: untyped, required: static int): untyped =
  let (params, ret) = paramsOf(van)
  let void = isVoid(ret)
  let n = params.len
  let slot = genSym(nskLet, "mixSlot")
  let supported = genSym(nskConst, "mixSupported")
  let problem = genSym(nskConst, "mixProblem")

  let (key, sig) = keyAndSignature(name, $public, params, ret)

  var (supportedExpr, problemExpr) = supportExprs(params, ret)
  let resultTest = copyableResult(ret)
  supportedExpr = infix(supportedExpr, "and", resultTest)
  problemExpr = nnkIfExpr.newTree(
    nnkElifExpr.newTree(prefix(resultTest, "not"),
                        newLit("its result (" & ret.repr & ") holds a resource and cannot be stored")),
    nnkElseExpr.newTree(problemExpr))

  result = newStmtList()
  result.add nnkConstSection.newTree(
    nnkConstDef.newTree(supported, newEmptyNode(), supportedExpr),
    nnkConstDef.newTree(problem, newEmptyNode(), problemExpr))
  result.add newLetStmt(slot, newCall(bindSym"registerMixinSlot", newLit(name), newLit(key),
                                      newLit(sig), newCall(ident"addr", flag), supported, problem))

  # ---- the dispatcher
  let argsP = ident"args"
  let resP = ident"res"
  let a = genSym(nskLet, "a")
  let frame = genSym(nskVar, "frame")
  let e = genSym(nskLet, "e")
  var tupTy = newNimNode(nnkTupleConstr)
  for p in params:
    if p.isOpen: tupTy.add nnkTupleConstr.newTree(ident"pointer", ident"int")
    else: tupTy.add nnkPtrTy.newTree(p.typ)
  var ptrList = newNimNode(nnkBracket)
  var luaArgs = newNimNode(nnkBracket)
  for i, p in params:
    let path = newLit(name & " " & p.name)
    if p.isOpen:
      ptrList.add newCall(ident"pointer", newNilLit())
      let item = nnkBracketExpr.newTree(nnkBracketExpr.newTree(a), newLit(i))
      luaArgs.add newCall(nnkBracketExpr.newTree(bindSym"mixArgOpen", p.elem),
                          nnkBracketExpr.newTree(item, newLit(0)),
                          nnkBracketExpr.newTree(item, newLit(1)), path)
    else:
      let item = nnkBracketExpr.newTree(nnkBracketExpr.newTree(a), newLit(i))
      ptrList.add newCall(ident"pointer", item)
      luaArgs.add newCall(bindSym"mixArg", item, frame, path)
  let storeResult =
    if void: quote do: result = moDone
    else:
      quote do:
        try:
          mixStoreResult[`ret`](modVM, chainValue(), `resP`, `name` & " result")
          result = moDone
        except Exception as `e`:   # (raises: [] -- closures may raise anything)
          mixinFailed(`slot`, `e`.msg)
          result = (if `frame`.vanillaRan: moDone else: moVanilla)
  let castArgs =
    if n == 0: newEmptyNode()
    else: newLetStmt(a, nnkCast.newTree(nnkPtrTy.newTree(tupTy), argsP))
  let ptrArg = (if n == 0: newCall(nnkBracketExpr.newTree(ident"newSeq", ident"pointer")) else: ptrList)
  let luaArgsSeq = (if n == 0: newCall(nnkBracketExpr.newTree(ident"newSeq", bindSym"ScriptValue"))
                    else: prefix(luaArgs, "@"))
  let dispBody = quote do:
    {.cast(gcsafe).}:
      if not mixinMainThread: return moVanilla
      var `frame`: MixinFrame
      try:
        `castArgs`
        `frame` = beginMixinFrame(`slot`, `resP`, `ptrArg`)
        let st = runMixinChain(`frame`, `luaArgsSeq`)
        case st
        of csValue: `storeResult`
        of csVanillaDone: result = moDone
        of csRaised:
          mixinPending = `frame`.raised
          result = moRaise
        of csNone: result = moVanilla
      except Exception as `e`:
        mixinFailed(`slot`, `e`.msg)
        result = (if not `frame`.isNil and `frame`.vanillaRan: moDone else: moVanilla)
      if not `frame`.isNil: endMixinFrame(`frame`)
  let dispProc = newProc(newEmptyNode(), [bindSym"MixinOutcome",
                         newIdentDefs(argsP, ident"pointer"), newIdentDefs(resP, ident"pointer")],
                         dispBody, nnkLambda)
  dispProc.addPragma(ident"nimcall")
  dispProc.addPragma(ident"gcsafe")
  dispProc.addPragma(nnkExprColonExpr.newTree(ident"raises", newNimNode(nnkBracket)))

  # ---- orig: the original body with a script's arguments
  let vmP = ident"vm"
  let sargs = ident"sargs"
  let retP = ident"ret"
  let of2 = genSym(nskLet, "frame")
  var origBody = newStmtList(newLetStmt(of2, bindSym"origFrame"))
  var vanCall = newCall(van)
  for i, p in params:
    let path = newLit(name & " argument " & $(i + 1))
    if p.isOpen:
      let s = genSym(nskVar, "s" & $i)
      origBody.add nnkVarSection.newTree(newIdentDefs(s, nnkBracketExpr.newTree(ident"seq", p.elem)))
      origBody.add newCall(bindSym"mixTakeSeq", vmP, newCall(bindSym"arg", sargs, newLit(i)), s, path)
      vanCall.add s
    else:
      let t = genSym(nskVar, "t" & $i)
      let pv = genSym(nskLet, "p" & $i)
      origBody.add nnkVarSection.newTree(newIdentDefs(t, p.typ))
      origBody.add newLetStmt(pv, newCall(bindSym"mixTake", vmP, newCall(bindSym"arg", sargs, newLit(i)),
                                          of2, newLit(i), t, newLit(p.isVar), path))
      vanCall.add nnkBracketExpr.newTree(pv)
  origBody.add newCall(bindSym"noteVanilla", of2)
  let ex = genSym(nskLet, "ex")
  let rv = genSym(nskLet, "r")
  let vv = genSym(nskLet, "v")
  let callAndReturn =
    if void:
      quote do:
        `vanCall`
        `retP`.setRet(NilValue)
    else:
      quote do:
        let `rv` = `vanCall`
        if not `of2`.isNil and `of2`.alive and not `of2`.res.isNil:
          cast[ptr `ret`](`of2`.res)[] = `rv`   # (results are copyable, see mixSupported)
        let `vv` = mixResult(`rv`, `name`)
        if not `of2`.isNil: `of2`.vanillaValue = `vv`
        `retP`.setRet(`vv`)
  origBody.add quote do:
    try:
      `callAndReturn`
    except CatchableError as `ex`:
      vanillaRaised(`of2`, `ex`, `name`)
  let origProc = newProc(newEmptyNode(), nativeParams(), origBody, nnkLambda)
  origProc.addPragma(ident"nimcall")

  # ---- call: the public proc (engine.call), defaults filled in by Nim
  let target = (if qualifier.len == 0: public else: newDotExpr(ident(qualifier), public))
  let callProc = callNative(params, ret, required, name, target)

  result.add quote do:
    when `supported`:
      `disp` = `dispProc`
      `slot`.orig = `origProc`
      when compiles(`target`):   # (a private proc can be wrapped, not called)
        `slot`.call = `callProc`

proc bindEntries(here: string, wanted: proc (module: string): bool): NimNode =
  result = newStmtList()
  while bound.len < moddableRegistry.len: bound.add false
  var modules: seq[string]
  var picked: seq[int]
  for i in 0 ..< moddableRegistry.len:
    let m = moddableRegistry[i].module
    if bound[i] or not wanted(m): continue
    picked.add i
    if m != here and m notin modules: modules.add m
  for m in modules:
    result.add nnkImportStmt.newTree(newLit(m))
  for i in picked:
    let e = moddableRegistry[i]
    let qualifier = (if e.module == here: "" else: stemOfPath(e.module))
    result.add newCall(bindSym"bindOne", ident(e.vanilla), ident(e.flag), ident(e.dispatch),
                       newLit(e.name), newLit(qualifier), ident(e.public), newLit(e.required))
    bound[i] = true

macro bindModdables*(here: static string): untyped =
  ## Bind every {.moddable.} proc compiled so far that is not bound yet.
  ## `here`: the calling module's path (its own procs are not imported).
  ## The modules it binds are imported into the calling module, so call it
  ## from a module of its own (their names would hide the caller's).
  bindEntries(here, proc (m: string): bool = true)

macro bindModdablesIn*(here: static string, paths: static openArray[string]): untyped =
  ## The same, only for these modules (paths relative to `here`; one ending in
  ## "/" is a folder: every module under it): the binding is split over a few
  ## modules so its C compiles in parallel.
  var dir = here
  while dir.len > 0 and dir[^1] notin {'/', '\\'}: dir.setLen(dir.len - 1)
  var prefixes: seq[string]
  for f in paths: prefixes.add normPath(dir & f)
  bindEntries(here, proc (m: string): bool =
    let mm = normPath(m)
    for p in prefixes:
      if mm.startsWith(p): return true
    false)

# ------------------------------------------------- callable-only procs ----
# The rest of the game's exported procs (helpers that are not {.moddable.}):
# engine.call reaches them too, but they cannot be wrapped.

const NotModdable = "it is not moddable: engine.call can call it, mixins cannot wrap it"

proc requiredArgs(impl: NimNode): int =
  ## Parameters through the last one without a default.
  var n = 0
  for i in 1 ..< impl[3].len:
    let d = impl[3][i]
    n += d.len - 2
    if d[^1].kind == nnkEmpty: result = n

macro bindCallable(s: typed, name: static string): untyped =
  result = newStmtList()
  var choices: seq[NimNode]
  if s.kind in {nnkClosedSymChoice, nnkOpenSymChoice}:
    for c in s: choices.add c
  else:
    choices.add s
  for c in choices:
    if c.kind != nnkSym or c.symKind notin {nskProc, nskFunc}: continue
    let impl = c.getImpl
    if impl.kind notin {nnkProcDef, nnkFuncDef}: continue
    if impl[2].kind != nnkEmpty and impl[2].len > 0: continue          # generic
    let (params, ret) = paramsOf(c)
    if ret.kind == nnkVarTy or (ret.kind == nnkBracketExpr and ret[0].kind == nnkSym and $ret[0] == "lent"):
      continue
    var untypedParam = false
    for p in params:
      if p.typ.kind == nnkSym and $p.typ in ["untyped", "typed", "typedesc"]: untypedParam = true
    if untypedParam: continue
    let (key, sig) = keyAndSignature(name, $c, params, ret)
    let (supportedExpr, problemExpr) = supportExprs(params, ret)
    let supported = genSym(nskConst, "callSupported")
    let problem = genSym(nskConst, "callProblem")
    let slot = genSym(nskLet, "callSlot")
    result.add nnkConstSection.newTree(
      nnkConstDef.newTree(supported, newEmptyNode(), supportedExpr),
      nnkConstDef.newTree(problem, newEmptyNode(),
        nnkIfExpr.newTree(nnkElifExpr.newTree(supported, newLit(NotModdable)),
                          nnkElseExpr.newTree(problemExpr))))
    result.add newLetStmt(slot, newCall(bindSym"registerMixinSlot", newLit(name), newLit(key),
                                        newLit(sig), newNilLit(), newLit(false), problem))
    let native = callNative(params, ret, requiredArgs(impl), name, c)
    result.add quote do:
      when `supported`:
        `slot`.call = `native`

proc exportedProcNames(src: string): seq[string] =
  ## The exported, non-generic proc / func names a module's source declares
  ## at top level (also inside top-level `when`), except {.moddable.} ones.
  let ast = parseStmt(src)
  proc walk(n: NimNode, names: var seq[string]) =
    for x in n:
      case x.kind
      of nnkProcDef, nnkFuncDef:
        if x[0].kind == nnkPostfix and x[0][1].kind == nnkIdent and
           (x[2].kind == nnkEmpty or x[2].len == 0):
          var moddable = false
          if x[4].kind == nnkPragma:
            for p in x[4]:
              if p.kind == nnkIdent and $p == "moddable": moddable = true
          let name = $x[0][1]
          if not moddable and name notin names: names.add name
      of nnkWhenStmt:
        for branch in x: walk(branch[^1], names)
      of nnkStmtList:
        walk(x, names)
      else: discard
  walk(ast, result)

macro bindCallables*(here: static string, modules: static openArray[string],
                     skip: static seq[string] = newSeq[string]()): untyped =
  # (a typed default: an empty `[]` crashes the compiler's macro VM)
  ## engine.call for every exported proc of `modules` (paths relative to the
  ## calling module, `here`) that is not {.moddable.} (those are bound by
  ## bindModdables, mixins included), except the names in `skip`.
  result = newStmtList()
  var dir = here
  while dir.len > 0 and dir[^1] notin {'/', '\\'}: dir.setLen(dir.len - 1)
  for rel in modules:
    let path = dir & rel
    let stem = stemOfPath(path)
    let names = exportedProcNames(staticRead(path))
    if names.len == 0: continue   # (only types, templates, iterators)
    result.add nnkImportStmt.newTree(newLit(path))
    for name in names:
      if name in skip: continue
      # (`when declared`: a proc inside an inactive `when` branch, like an
      # emscripten-only one, is in the source but not in this build)
      let sym = newDotExpr(ident(stem), ident(name))
      result.add nnkWhenStmt.newTree(nnkElifBranch.newTree(newCall(ident"declared", sym),
        newCall(bindSym"bindCallable", copyNimTree(sym), newLit(stem & "." & name))))
