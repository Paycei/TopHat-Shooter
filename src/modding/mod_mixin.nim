## The high half of mixins: what runs when a mod wraps one of the game's
## {.moddable.} procs, and the Lua side (`mixin`, `engine.call`).
##
##   mixin.wrap("combat.damageEnemy", function(orig, enemy, amount, ...)
##     return orig(enemy, amount * 2, ...)
##   end)
##
## mod_patch_core's pragma leaves, per proc, a flag and a dispatch slot;
## mod_mixin_bind generates the dispatcher and the two natives of each slot
## (`orig`, the original body; `call`, the public proc) out of the helpers
## here. A wrapped call:
##
##  1. pushes a frame holding pointers to the call's arguments and result,
##  2. hands the scripts the arguments (by-value objects as proxies borrowed
##     for the call: writes reach the argument; refs as proxies that keep the
##     object alive),
##  3. runs the layers outermost first, each getting `orig` = the rest of the
##     chain; the innermost `orig` runs the original body (writing var
##     parameters into the caller's variables when a script passes back what
##     it was given),
##  4. converts the outermost layer's result back.
##
## A layer that errors is logged and the call goes on without it (never
## running the original twice); a Nim exception raised by the original inside
## the chain is re-raised to the game's caller unless a layer handled it.

import std/[tables, strutils, algorithm]
import lua_bridge, mod_state, mod_hooks, mod_deep, mod_patch_core

type
  MixinLayer = object
    owner: int
    fn: ScriptValue
    priority: int
    order: int
    handle: int

  MixinFrame* = ref object
    slot*: MixinSlot
    ptrs*: seq[pointer]       ## the arguments (nil for an openArray)
    res*: pointer             ## the result, or nil
    alive*: bool
    vanillaRan*: bool
    vanillaValue*: ScriptValue  ## what the original returned, as scripts see it
    raised*: ref Exception    ## what the original raised inside the chain
    failure: string
    layers: seq[MixinLayer]

  MixinSlot* = ref object
    name*: string             ## "combat.damageEnemy"
    key*: string              ## "combat.damageEnemy(Enemy, float32, bool)": unique
    signature*: string        ## "damageEnemy(enemy: Enemy, baseDamage: float32, ...): float32"
    supported*: bool          ## false: a parameter or the result is not scriptable
    problem*: string          ## why not
    flag: ptr bool
    layers: seq[MixinLayer]
    orig*: SlotNative         ## the original body (set by the binder)
    call*: SlotNative         ## the public proc, mixins included (engine.call)

  SlotNative* = proc (vm: VM, args: openArray[ScriptValue], ret: var RetVals) {.nimcall.}
    ## A slot's natives capture nothing: storing a nimcall one is a pointer
    ## write, where a closure cost refcounting code per slot in the binders'
    ## module init (~0.4 MB of the exe over every slot).

  ChainStatus* = enum
    csValue        ## the scripts produced the result (frame value)
    csVanillaDone  ## a layer failed after the original ran: its result stands
    csRaised       ## the original raised and no layer handled it
    csNone         ## nothing useful ran: run the original

  MixinArgError* = object of ScriptError
    ## An argument a script passed does not convert (engine.call tries the
    ## next overload).

var
  mixinSlots*: seq[MixinSlot]
  slotsByName: Table[string, seq[int]]
  nextHandle = 1
  layerOrder = 0
  origFrame*: MixinFrame      ## the frame the original is being called for (nil: none)
  frameValue: ScriptValue     ## (runMixinChain's result)

proc registerMixinSlot*(name, key, signature: string, flag: ptr bool,
                        supported: bool, problem = ""): MixinSlot =
  result = MixinSlot(name: name, key: key, signature: signature, flag: flag,
                     supported: supported, problem: problem)
  slotsByName.mgetOrPut(name, @[]).add(mixinSlots.len)
  if key != name: slotsByName.mgetOrPut(key, @[]).add(mixinSlots.len)
  mixinSlots.add(result)

proc boundModdableNames*(): seq[string] =
  for s in mixinSlots: result.add(s.name)

proc isModdable*(s: MixinSlot): bool =
  ## A {.moddable.} proc (mixins can wrap it), not a callable-only one.
  not s.flag.isNil

proc hasSlot*(name: string): bool =
  slotsByName.hasKey(name)

proc mixinActive*(name: string): bool =
  ## Whether some mod wraps the moddable proc `name` right now.
  for i in slotsByName.getOrDefault(name):
    if not mixinSlots[i].flag.isNil and mixinSlots[i].flag[]: return true
  false

# ---------------------------------------------------------------- frames ----
proc beginMixinFrame*(slot: MixinSlot, res: pointer, ptrs: openArray[pointer]): MixinFrame =
  result = MixinFrame(slot: slot, res: res, alive: true, ptrs: @ptrs, layers: slot.layers)

proc endMixinFrame*(f: MixinFrame) =
  f.alive = false

proc frameAlive(f: MixinFrame): proc (): bool {.closure.} =
  result = proc (): bool = f.alive

# ----------------------------------------------------------- marshalling ----
proc mixArg*[T](p: ptr T, frame: MixinFrame, path: string): ScriptValue =
  ## A parameter as the scripts see it during the call.
  proxyAt(p, frameAlive(frame), path)

proc mixArgOpen*[E](data: pointer, n: int, path: string): ScriptValue =
  ## An openArray parameter: a table of its items.
  let t = newScriptTable(n)
  let a = cast[ptr UncheckedArray[E]](data)
  for i in 0 ..< n: t.add(nimToScript(a[i], path & "[" & $(i + 1) & "]"))
  vtable(t)

proc argError(vm: VM, msg: string) {.noreturn.} =
  raise newException(MixinArgError, msg)

proc mixArgCount*(name: string, required, n, got: int) {.noreturn, noinline.} =
  ## engine.call got too few or too many arguments for `name` (one copy of
  ## this message code, not one inlined into every generated native).
  raise newException(MixinArgError, name & " takes " &
    (if required == n: $n else: $required & " to " & $n) & " arguments, got " & $got)

proc mixTake*[T](vm: VM, v: ScriptValue, frame: MixinFrame, i: int, tmp: var T,
                 isVar: bool, path: string): ptr T =
  ## Where `orig` / engine.call find argument i: the caller's own variable
  ## when the script passes back the proxy it was given (and always, for a
  ## var parameter, which then takes the new value), game data a proxy
  ## points at (for a var parameter), else `tmp`, converted.
  when isResource(T):
    # (a handle: the resource itself, never a copy)
    result = resPointer[T](v)
    if result.isNil: argError(vm, path & " expects a " & resName[T]() & ", got " & typeName(v))
  else:
    if not frame.isNil and frame.alive and i < frame.ptrs.len and not frame.ptrs[i].isNil:
      let fp = cast[ptr T](frame.ptrs[i])
      when not (T is ScriptValue):
        if proxyPointer(v) == frame.ptrs[i]: return fp
      if isVar:
        try: scriptToNim(vm, v, fp[], path)
        except ScriptError as e: argError(vm, e.msg)
        return fp
    when T is object or T is tuple or T is seq or T is array:
      if isVar:
        let pp = proxyOf[T](v)
        if not pp.isNil: return pp
    try: scriptToNim(vm, v, tmp, path)
    except ScriptError as e: argError(vm, e.msg)
    result = addr tmp

proc mixTakeSeq*[E](vm: VM, v: ScriptValue, tmp: var seq[E], path: string) =
  ## An openArray argument from a script: a list.
  try: scriptToNim(vm, v, tmp, path)
  except ScriptError as e: argError(vm, e.msg)

proc mixResult*[R](r: sink R, path: string): ScriptValue =
  nimToScript(r, path)

proc mixStoreResult*[R](vm: VM, v: ScriptValue, res: pointer, path: string) =
  scriptToNim(vm, v, cast[ptr R](res)[], path)

proc noteVanilla*(frame: MixinFrame) {.inline.} =
  if not frame.isNil: frame.vanillaRan = true

proc vanillaRaised*(frame: MixinFrame, e: ref Exception, name: string) {.noreturn.} =
  ## The original raised inside the chain: remembered (the game's caller gets
  ## it back unless a layer handles it), and a Lua error for the layer.
  if not frame.isNil: frame.raised = e
  raise newException(ScriptError, name & ": the game's own code raised " & $e.name & ": " & e.msg)

# ----------------------------------------------------------------- chains ----
proc callOriginal(frame: MixinFrame, args: seq[ScriptValue], ok: var bool): ScriptValue =
  var r: RetVals
  let prev = origFrame
  origFrame = frame
  try:
    frame.slot.orig(modVM, args, r)
    ok = true
    result = r.retAt(0)
  except CatchableError as e:
    ok = false
    frame.failure = e.msg
  origFrame = prev

proc runFrom(frame: MixinFrame, k: int, args: seq[ScriptValue], ok: var bool): ScriptValue =
  ## Layer k with `orig` = the rest of the chain (k past the last: the original).
  if k >= frame.layers.len: return callOriginal(frame, args, ok)
  let layer = frame.layers[k]
  let next = vnative(newNative("orig", proc (vm: VM, a: openArray[ScriptValue], r: var RetVals) =
    var inner = false
    let v = runFrom(frame, k + 1, @a, inner)
    if not inner: vm.runtimeError(frame.failure)
    r.setRet(v)))
  var callArgs = newSeq[ScriptValue](args.len + 1)
  callArgs[0] = next
  for i, a in args: callArgs[i + 1] = a
  var r: RetVals
  if callAs(layer.owner, layer.fn, callArgs, r):
    ok = true
    return r.retAt(0)
  # This layer failed (callAs logged it): the call goes on without it.
  if frame.vanillaRan:
    ok = frame.raised.isNil
    return frame.vanillaValue
  runFrom(frame, k + 1, args, ok)

proc runMixinChain*(frame: MixinFrame, args: seq[ScriptValue]): ChainStatus =
  var ok = false
  frameValue = runFrom(frame, 0, args, ok)
  if ok: csValue
  elif not frame.raised.isNil: csRaised
  elif frame.vanillaRan: csVanillaDone
  else: csNone

proc chainValue*(): ScriptValue = frameValue

proc mixinFailed*(slot: MixinSlot, msg: string) =
  ## A dispatcher's own error (a result that does not convert...).
  modLogAdd(mlError, "", "mixin " & slot.name & ": " & msg)

# ---------------------------------------------------------- the Lua side ----
proc findSlots(vm: VM, name: string): seq[MixinSlot] =
  for i in slotsByName.getOrDefault(name): result.add(mixinSlots[i])
  if result.len == 0:
    vm.runtimeError("no moddable proc '" & name & "' (mixin.list() names them)")

proc refreshFlag(s: MixinSlot) =
  if not s.flag.isNil: s.flag[] = s.supported and s.layers.len > 0

proc sortLayers(s: MixinSlot) =
  s.layers.sort(proc (a, b: MixinLayer): int =
    result = cmp(b.priority, a.priority)   # higher priority runs first (outermost)
    if result == 0: result = cmp(a.order, b.order))

proc resetMixins() =
  for s in mixinSlots:
    s.layers.setLen(0)
    s.refreshFlag()

proc dropMixinsOf(owner: int) =
  for s in mixinSlots:
    var kept: seq[MixinLayer]
    for l in s.layers:
      if l.owner != owner: kept.add(l)
    s.layers = kept
    s.refreshFlag()

const MixinPrelude = """
local mixin = ...
-- before / after / replace are wraps: before(fn(...)) runs first and a
-- non-nil return cancels the call (that value is the result); after(fn(result,
-- ...)) runs after it and a non-nil return replaces the result; replace(fn(...))
-- never runs the original.
local wrap = mixin.wrap
function mixin.before(name, fn, opts)
  return wrap(name, function(orig, ...)
    local r = fn(...)
    if r ~= nil then return r end
    return orig(...)
  end, opts)
end
function mixin.after(name, fn, opts)
  return wrap(name, function(orig, ...)
    local r = orig(...)
    local r2 = fn(r, ...)
    if r2 ~= nil then return r2 end
    return r
  end, opts)
end
function mixin.replace(name, fn, opts)
  return wrap(name, function(orig, ...) return fn(...) end, opts)
end
"""

proc addSlotCaller(t: ScriptTable, procName: string, slots: seq[MixinSlot],
                   callSlots: proc (vm: VM, slots: seq[MixinSlot], args: openArray[ScriptValue],
                                    ret: var RetVals) {.nimcall.}) =
  ## engine.<module>.<proc>: made here, not in installModMixin's loop, so each
  ## native captures its own slots (closures made in a loop share the loop's
  ## variables).
  t.reg(procName) do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    callSlots(vm, slots, args, ret)

proc installModMixin*(base: ScriptTable) =
  ## The `mixin` library and engine.call / engine.<module>.<proc> (into the
  ## engine table mod_api made).
  let mixinT = newScriptTable()
  mixinT.reg("wrap") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## mixin.wrap(name, fn(orig, ...) [, {priority = n}]) -> handle
    let owner = currentModIdx
    let name = vm.checkStr(args, 0, "wrap")
    let fn = vm.checkFunc(args, 1, "wrap")
    var priority = 0
    let opts = arg(args, 2)
    if opts.kind == vkTable:
      let p = rawGetStr(opts.tbl, "priority")
      if p.kind == vkNumber: priority = int(p.n)
      elif p.kind != vkNil: vm.runtimeError("mixin.wrap: priority must be a number")
    elif opts.kind != vkNil: vm.runtimeError("mixin.wrap: options must be a table")
    let slots = vm.findSlots(name)
    if slots.len > 1:
      var keys: seq[string]
      for s in slots: keys.add(s.key)
      vm.runtimeError("mixin.wrap: '" & name & "' is overloaded; name one: " & keys.join(", "))
    let s = slots[0]
    if not s.supported:
      vm.runtimeError("mixin.wrap: " & s.name & " cannot be wrapped (" & s.problem & ")")
    inc layerOrder
    let handle = nextHandle
    inc nextHandle
    s.layers.add(MixinLayer(owner: owner, fn: fn, priority: priority, order: layerOrder, handle: handle))
    s.sortLayers()
    s.refreshFlag()
    ret.setRet(vnum(handle))
  mixinT.reg("remove") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## mixin.remove(handle) -> true if it was installed
    let h = vm.checkInt(args, 0, "remove")
    for s in mixinSlots:
      for i, l in s.layers:
        if l.handle == h:
          s.layers.delete(i)
          s.refreshFlag()
          ret.setRet(TrueValue)
          return
    ret.setRet(FalseValue)
  mixinT.reg("list") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## mixin.list([prefix]) -> every moddable proc's name (an overload's with
    ## its parameter types), sorted
    let prefix = vm.optStr(args, 0, "list", "")
    var names: seq[string]
    for s in mixinSlots:
      let n = (if slotsByName.getOrDefault(s.name).len > 1: s.key else: s.name)
      if n.startsWith(prefix) and n notin names: names.add(n)
    names.sort()
    let t = newScriptTable(names.len)
    for n in names: t.add(vstr(n))
    ret.setRet(vtable(t))
  mixinT.reg("has") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ret.setRet(vbool(slotsByName.hasKey(vm.checkStr(args, 0, "has"))))
  mixinT.reg("signature") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## mixin.signature(name) -> its Nim signature(s), one per line
    var sigs: seq[string]
    for s in vm.findSlots(vm.checkStr(args, 0, "signature")):
      sigs.add(s.signature & (if s.supported: "" else: "  -- cannot be wrapped: " & s.problem))
    ret.setRet(vstr(sigs.join("\n")))
  rawSet(base, vstr("mixin"), vtable(mixinT))
  let cl = modVM.loadChunk(MixinPrelude, "mixin", base)
  var r: RetVals
  let err = protectedCall(modVM, vfunc(cl), [vtable(mixinT)], r)
  if err.len > 0: modLogAdd(mlError, "", "mixin prelude: " & err)

  # engine.call(name, ...) and engine.<module>.<proc>(...): the public proc,
  # mixins included.
  let engineV = rawGetStr(base, "engine")
  if engineV.kind != vkTable: return
  let engineT = engineV.tbl
  proc callSlots(vm: VM, slots: seq[MixinSlot], args: openArray[ScriptValue], ret: var RetVals) {.nimcall.} =
    var firstErr = ""
    for s in slots:
      if s.call.isNil:
        let why = if s.problem.len > 0: s.problem
                  else: "only its own module calls it: mixins can wrap it, scripts cannot call it"
        firstErr = s.name & " cannot be called from a script (" & why & ")"
        continue
      try:
        s.call(vm, args, ret)
        return
      except MixinArgError as e:
        if firstErr.len == 0: firstErr = e.msg
    vm.runtimeError(firstErr)
  engineT.reg("call") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## engine.call("module.proc", ...) -> what the proc returns
    let name = vm.checkStr(args, 0, "call")
    var rest = newSeq[ScriptValue](max(0, args.len - 1))
    for i in 1 ..< args.len: rest[i - 1] = args[i]
    callSlots(vm, vm.findSlots(name), rest, ret)
  var modules: Table[string, ScriptTable]
  for name, idxs in slotsByName.pairs:
    if '(' in name: continue
    let dot = name.find('.')
    if dot < 0: continue
    let module = name[0 ..< dot]
    let procName = name[dot + 1 .. ^1]
    if not modules.hasKey(module):
      modules[module] = newScriptTable()
      if rawGetStr(engineT, module).kind == vkNil:
        rawSet(engineT, vstr(module), vtable(modules[module]))
    var slots: seq[MixinSlot]
    for i in idxs: slots.add(mixinSlots[i])
    modules[module].addSlotCaller(procName, slots, callSlots)

addModTeardown(resetMixins, dropMixinsOf)
mixinMainThread = true   # module init runs on the game's main thread
