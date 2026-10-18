## The low half of mixins: the `{.moddable.}` pragma.
##
##   proc damageEnemy*(e: Enemy, amount: float32): float32 {.moddable.} = ...
##
## keeps the proc exactly as callers see it (same name, parameters, defaults,
## pragmas), but moves its body into an exported `mixV_*` proc and makes the
## public one check a plain bool first: while no mod wraps it, a call costs
## one load and a branch. When a mod does (mixin.wrap in mod_mixin.nim), the
## flag is on and the call goes through `mixFn_*`, which the high half
## (mod_mixin_bind) fills in with the code that runs the scripts.
##
## This module imports nothing but std/macros on purpose: localization,
## sound, settings and the rest of the low modules use the pragma, and they
## sit below everything the script runtime needs.

import std/macros

type
  MixinOutcome* = enum
    moVanilla   ## nothing took the call: run the original body
    moDone      ## the scripts produced the result (`res` is written)
    moRaise     ## the original raised inside the scripts' call: re-raise it
  MixinDispatch* = proc (args, res: pointer): MixinOutcome {.nimcall, gcsafe, raises: [].}
    ## `args` points at a tuple holding a pointer to every parameter
    ## (openArrays as (first element, length)); `res` at the result, or nil.

  ModdableEntry* = object
    ## One {.moddable.} proc, recorded at compile time for the binder.
    name*: string        ## "module.proc", the name scripts use
    module*: string      ## absolute path of the defining module
    public*: string      ## the proc's own name
    vanilla*: string     ## the original body (mixV_*)
    flag*: string        ## mixOn_*: true while some mod wraps it
    dispatch*: string    ## mixFn_*: the high half's entry point
    required*: int       ## parameters before the first one with a default

var moddableRegistry* {.compileTime.}: seq[ModdableEntry]
  ## Every moddable proc compiled so far, in compile order.
var moddableNames*: seq[string]
  ## The same names at run time (filled at module init): the debug startup
  ## check compares them with what the binder bound.
var mixinPending* {.threadvar.}: ref Exception
  ## What moRaise re-raises (set by the high half on the main thread).
var mixinMainThread* {.threadvar.}: bool
  ## True on the game's main thread only: worker threads (sound, Discord)
  ## always run the original body.

proc raiseMixinPending() {.noinline.} =
  var e = mixinPending
  mixinPending = nil
  if e.isNil: e = newException(CatchableError, "mixin: the original raised, but the error was lost")
  raise e

template mixinOpenArray*(a: untyped): untyped =
  ## An openArray parameter travels as (first element, length).
  ((if a.len > 0: cast[pointer](addr a[0]) else: nil), a.len)

macro distinctBaseOf*(T: typedesc): untyped =
  ## The type a distinct type is made from (T itself if it is not distinct),
  ## for the copy checks of the mixin layer (std/typetraits is not used here).
  var t = getTypeImpl(T)
  if t.kind == nnkBracketExpr and t.len == 2: t = getTypeImpl(t[1])   # typedesc[X]
  if t.kind == nnkDistinctTy: t[0] else: T

# ------------------------------------------------------------- the macro ----
proc identText(n: NimNode): string =
  case n.kind
  of nnkIdent, nnkSym: result = $n
  of nnkPostfix: result = identText(n[1])
  of nnkAccQuoted:
    for c in n: result.add identText(c)
  else: result = n.repr

proc mangle(s: string): string =
  for c in s:
    if c in {'a'..'z', 'A'..'Z', '0'..'9'}: result.add c
    else: result.add "_" & $ord(c)

proc stemOf(path: string): string =
  var a = 0
  for i in 0 ..< path.len:
    if path[i] in {'/', '\\'}: a = i + 1
  result = path[a .. ^1]
  if result.len > 4 and result[^4 .. ^1] == ".nim":
    result.setLen(result.len - 4)

proc typeHead(t: NimNode): string =
  ## The outer type constructor's name ("openArray", "static", ...), or "".
  var t = t
  if t.kind == nnkVarTy: t = t[0]
  case t.kind
  of nnkBracketExpr: identText(t[0])
  of nnkIdent, nnkSym: identText(t)
  of nnkCommand: identText(t[0])   # `sink T`, `lent T`
  else: ""

proc pragmaNames(p: NimNode): seq[string] =
  if p.kind != nnkPragma: return
  for x in p:
    case x.kind
    of nnkIdent, nnkSym: result.add $x
    of nnkExprColonExpr, nnkCall: result.add identText(x[0])
    else: discard

proc mentions(n: NimNode, name: string): bool =
  ## Whether `n` uses the identifier `name` anywhere (a recursive call).
  if n.kind in {nnkIdent, nnkSym}: return eqIdent(n, name)
  for c in n:
    if mentions(c, name): return true
  false

proc moddableImpl(def: NimNode): NimNode =
  if def.kind notin {nnkProcDef, nnkFuncDef}:
    error("{.moddable.} only works on procs and funcs", def)
  if def[2].kind != nnkEmpty and def[2].len > 0:
    error("{.moddable.} procs cannot be generic", def)
  if def.body.kind == nnkEmpty:
    error("put {.moddable.} on the proc's implementation, not its forward declaration", def)
  let pnames = pragmaNames(def.pragma)
  for bad in ["compileTime", "noreturn", "importc", "borrow", "exportc", "error"]:
    if bad in pnames:
      error("{.moddable.} cannot be used with {." & bad & ".}", def)
  let params = def.params
  let ret = params[0]
  if ret.kind == nnkVarTy or typeHead(ret) == "lent":
    error("{.moddable.} procs cannot return var/lent", def)

  let procName = identText(def.name)
  let path = def.lineInfoObj.filename
  let stem = stemOf(path)
  let line = def.lineInfoObj.line
  let base = mangle(stem) & "_" & mangle(procName) & "_" & $line
  let vanName = ident("mixV_" & base)
  let flagName = ident("mixOn_" & base)
  let dispName = ident("mixFn_" & base)
  let isFunc = def.kind == nnkFuncDef
  let isVoid = ret.kind == nnkEmpty or (ret.kind == nnkIdent and $ret == "void")

  # Parameters, flattened ("a, b: int" is two).
  var argNames: seq[NimNode]
  var argTypes: seq[NimNode]
  for i in 1 ..< params.len:
    let d = params[i]
    for j in 0 ..< d.len - 2:
      argNames.add d[j]
      argTypes.add d[^2]
  for t in argTypes:
    if typeHead(t) in ["static", "typedesc", "untyped", "typed"]:
      error("{.moddable.} procs cannot take static/typedesc/untyped parameters", def)
  # Arguments a call must pass: through the last parameter without a default
  # (one after a defaulted parameter makes those defaults reachable only by
  # name, so engine.call passes everything up to it).
  var required = 0
  block:
    var n = 0
    for i in 1 ..< params.len:
      let d = params[i]
      n += d.len - 2
      if d[^1].kind == nnkEmpty: required = n

  # The original body, under its new name: no defaults (only the public proc
  # is called with missing arguments) unless a default is what gives the
  # parameter its type (`consume = true`), no export pragmas.
  var van = copyNimTree(def)
  van[0] = postfix(vanName, "*")
  for i in 1 ..< van.params.len:
    if van.params[i][^2].kind != nnkEmpty:
      van.params[i][^1] = newEmptyNode()
  if van.pragma.kind == nnkPragma:
    var kept = newNimNode(nnkPragma)
    for x in van.pragma:
      let n = (case x.kind
               of nnkIdent, nnkSym: $x
               of nnkExprColonExpr, nnkCall: identText(x[0])
               else: "")
      if n notin ["deprecated", "exportc", "extern"]:
        kept.add x
    van.pragma = (if kept.len > 0: kept else: newEmptyNode())
  # The original comes first, so the public proc sees its effects (a
  # forward-declared callee counts as not GC-safe, which would break procs
  # the sound and Discord threads reach). A recursive body needs the public
  # name declared before it: only then is the public proc forward-declared.
  var fwd = newEmptyNode()
  if mentions(def.body, procName):
    fwd = copyNimTree(def)
    fwd.body = newEmptyNode()

  # The public proc: identical signature, dispatching body.
  var call = newCall(vanName)
  for a in argNames: call.add a
  let runVanilla = if isVoid: call else: newAssignment(ident"result", call)

  var tup = newNimNode(nnkTupleConstr)
  for i, a in argNames:
    let h = typeHead(argTypes[i])
    if h in ["openArray", "varargs"]:
      tup.add newCall(bindSym"mixinOpenArray", a)
    else:
      tup.add newCall(ident"addr", a)
  let argsPtr = if argNames.len == 0: newNilLit()
                else: newCall(ident"addr", ident"mixArgs")
  let resPtr = if isVoid: newNilLit() else: newCall(ident"addr", ident"result")
  var dispatchStmts = newStmtList()
  if argNames.len > 0:
    dispatchStmts.add newVarStmt(ident"mixArgs", tup)
  let caseStmt = nnkCaseStmt.newTree(
    newCall(dispName, argsPtr, resPtr),
    nnkOfBranch.newTree(bindSym"moDone", nnkReturnStmt.newTree(newEmptyNode())),
    nnkOfBranch.newTree(bindSym"moRaise", newCall(bindSym"raiseMixinPending")),
    nnkOfBranch.newTree(bindSym"moVanilla", nnkDiscardStmt.newTree(newEmptyNode())))
  dispatchStmts.add caseStmt
  var guarded = nnkIfStmt.newTree(nnkElifBranch.newTree(
    newCall(ident"unlikely", flagName), dispatchStmts))
  var runtimeBody = newStmtList()
  if isFunc:
    runtimeBody.add nnkPragmaBlock.newTree(
      nnkPragma.newTree(nnkCast.newTree(newEmptyNode(), ident"noSideEffect")),
      newStmtList(guarded))
  else:
    runtimeBody.add guarded
  runtimeBody.add runVanilla
  let whenStmt = nnkWhenStmt.newTree(
    nnkElifBranch.newTree(ident"nimvm", newStmtList(copyNimTree(runVanilla))),
    nnkElse.newTree(runtimeBody))
  var pub = copyNimTree(def)
  pub.body = newStmtList(whenStmt)

  let fullName = stem & "." & procName
  let vanS = "mixV_" & base
  let flagS = "mixOn_" & base
  let dispS = "mixFn_" & base
  let entry = quote do:
    static:
      moddableRegistry.add(ModdableEntry(name: `fullName`, module: `path`,
        public: `procName`, vanilla: `vanS`, flag: `flagS`, dispatch: `dispS`,
        required: `required`))
  result = newStmtList(
    nnkVarSection.newTree(
      newIdentDefs(postfix(flagName, "*"), ident"bool"),
      newIdentDefs(postfix(dispName, "*"), bindSym"MixinDispatch")),
    fwd,
    van,
    pub,
    entry,
    newCall(ident"add", bindSym"moddableNames", newLit(stem & "." & procName)))

macro moddable*(def: untyped): untyped =
  ## Make a proc wrappable and replaceable by mods (mixin.wrap & co.).
  moddableImpl(def)
