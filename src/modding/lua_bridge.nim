## The mod scripting runtime: real Lua 5.5 (vendored, see lua_c.nim) behind a
## small Nim value API that the mod modules are written against.
##
##   ScriptValue      a Lua value as Nim sees it. Numbers, booleans and strings
##                    are copied; tables, functions and other objects are
##                    registry references that stay valid while Nim holds them.
##   ScriptTable      a Lua table (raw access only: rawGet/rawSet/len/add).
##   NativeProc       a Nim function scripts can call (reg / vnative).
##   UdClass/Userdata a Nim object scripts see as a Lua userdata, its fields and
##                    methods served by the class's procs (__index & co).
##   protectedCall    runs a script function under the watchdog.
##
## Error discipline. Lua raises errors with longjmp, which must never jump
## over a Nim frame (it would skip its destructors and `finally`s). So:
##  * Nim code only uses raw, non-raising Lua calls (rawget/rawset, never
##    anything that runs metamethods), and the allocator never fails (a soft
##    memory cap raises from the instruction hook instead);
##  * a Nim native signals an error by raising ScriptError; its trampoline
##    catches it, finishes every Nim scope, and only then calls lua_error from
##    a frame that holds nothing to clean up;
##  * Lua code is only ever entered through lua_pcall.
##
## Trust. Mods are approved before they are published, so scripts get every
## standard library (io, os, debug, package, load, string.dump...) and every
## metatable. Two things are kept from them: native modules
## (lua_loadlib_nodl.c), so a mod runs the same on every platform, and files
## outside the mod's own folders: every file the io, os, loadfile and package
## libraries open goes through `fileGate` (lua_files.h), which lets a mod read
## its folder and its mod.dataDir() and write only the latter. Each mod
## has its own globals table falling through to the shared library table, and
## its own copies of the library tables, so two mods don't trip over each
## other's names (a mod can still reach the shared table: getmetatable(_ENV)).
##
## Watchdog. The one guard left: a script that does not return within a few
## seconds (a frozen loop) is stopped with an error, so a bug cannot hang the
## game. Once it trips, pcall cannot keep the script running.

import std/[strutils, math, times]
import lua_c

type
  ValueKind* = enum
    vkNil, vkBool, vkNumber, vkString, vkTable, vkFunction,
    vkUserdata, vkOther

  ScriptStr* = ref object
    s*: string

  LuaRefObj = object
    id: cint
    gen: int
  LuaRef = ref LuaRefObj

  ScriptTable* = ref object
    r: LuaRef
  ScriptFunc* = ref object
    r: LuaRef

  ScriptValue* = object
    case kind*: ValueKind
    of vkNil: discard
    of vkBool: b*: bool
    of vkNumber:
      n*: float64
      isInt*: bool      ## a Lua integer (prints without ".0")
    of vkString: str*: ScriptStr
    of vkTable: tbl*: ScriptTable
    of vkFunction: fn*: ScriptFunc
    of vkUserdata: ud*: Userdata
    of vkOther: other: LuaRef   ## threads and anything else Nim only carries

  RetVals* = object
    ## Results of a call without a seq allocation for the common 0/1 case.
    count*: int
    first*: ScriptValue
    rest*: seq[ScriptValue]  ## values 2..count

  NativeProc* = proc (vm: VM, args: openArray[ScriptValue], ret: var RetVals) {.closure.}

  ScriptNative* = object
    name*: string
    fn*: NativeProc

  UdClass* = ref object
    ## Behaviour of one kind of userdata (a game entity, a texture, ...).
    name*: string
    index*: proc (vm: VM, ud: Userdata, key: ScriptValue): ScriptValue {.closure.}
    newindex*: proc (vm: VM, ud: Userdata, key, val: ScriptValue) {.closure.}
    tostr*: proc (ud: Userdata): string {.closure.}
    len*: proc (vm: VM, ud: Userdata): int {.closure.}
      ## `#ud` and ipairs(ud) (elements 1..len through `index`); nil = no length
    next*: proc (vm: VM, ud: Userdata, key: ScriptValue, k, v: var ScriptValue): bool {.closure.}
      ## pairs(ud): the entry after `key` (nil = first); false at the end
    call*: proc (vm: VM, ud: Userdata, args: openArray[ScriptValue], ret: var RetVals) {.closure.}
      ## ud(...) / obj:ud(): nil = not callable
    cached*: bool
      ## One Lua value per key: the same entity is always the same userdata,
      ## so scripts can use it as a table key. Only for keys that stay valid
      ## while the value lives (refs the box keeps alive, handles).
    mt: LuaRef
    cache: LuaRef

  Userdata* = ref object
    cls*: UdClass
    box*: RootRef            ## typed wrapper around the Nim object
    key*: pointer            ## identity: equality (and the cache) use (cls, key)
    handle*: int             ## numeric payload for handle-like userdata

  VM* = ref object
    L*: LuaState
    printSink*: proc (s: string) {.closure.}
    warnSink*: proc (s: string) {.closure.}   ## warn() and errors in __gc

  ScriptError* = object of CatchableError
    positioned*: bool        ## the message already starts with "file:line:"

  NativeBox = ref object
    name: string
    fn: NativeProc

  UdPayload = object
    tag: int32
    slot: int32

const
  TagUserdata = 0x55445431'i32
  TagNative = 0x4e415431'i32
  HookGranularity = 10_000    ## instructions between watchdog checks
  DefaultCallLimit* = 5.0     ## seconds a script call may run before the watchdog stops it
  LoadLimit* = 30.0           ## the same for a mod's main chunk (loading may build a lot)
  FrameLimit* = 10.0          ## all script calls of one frame together
  MaxScriptNesting* = 100     ## script -> game -> script ... levels (the C stack is finite)
  QuitSentinel* = "(the game is closing: os.exit)"
    ## the error os.exit unwinds a script with; never reported as a mod error

template NilValue*: ScriptValue = ScriptValue(kind: vkNil)
template TrueValue*: ScriptValue = ScriptValue(kind: vkBool, b: true)
template FalseValue*: ScriptValue = ScriptValue(kind: vkBool, b: false)

var
  theVM: VM
  luaGen = 1                  ## bumped on every close: refs from older states are dead
  liveL: LuaState             ## the open state (ref destructors)
  udSlots: seq[Userdata]
  udFree: seq[int32]
  natSlots: seq[NativeBox]
  natFree: seq[int32]
  callDepth: int
  watchClock: proc (): float64 {.nimcall.} = epochTime
  watchCallLimit = DefaultCallLimit   ## the default limit (tests shorten it)
  watchFrameLimit = FrameLimit
  watchLimit: float64                 ## the limit of the outermost call in progress
  watchStart: float64                 ## when it started
  idleStart: float64                  ## first tick of Lua running outside any call (a __gc)
  watchFrameSpent: float64            ## finished outermost calls this frame
  watchFrameArmed: bool               ## resetWatchdogFrame has run (the game's frame loop)
  watchTripped: bool
  watchMsg: string
  modQuitRequested*: bool             ## os.exit was called: main.nim closes the game
  modQuitCode*: int

proc `=destroy`(x: LuaRefObj) =
  if x.gen == luaGen and not liveL.isNil and x.id > 0:
    luaL_unref(liveL, LUA_REGISTRYINDEX, x.id)

proc `=copy`(dest: var LuaRefObj, src: LuaRefObj) {.error.}

# ------------------------------------------------------------- basics ----
proc vnum*(n: float64): ScriptValue {.inline.} = ScriptValue(kind: vkNumber, n: n)
proc vnum*(n: int): ScriptValue {.inline.} = ScriptValue(kind: vkNumber, n: n.float64, isInt: true)
proc vbool*(b: bool): ScriptValue {.inline.} = ScriptValue(kind: vkBool, b: b)
proc vstr*(s: string): ScriptValue {.inline.} = ScriptValue(kind: vkString, str: ScriptStr(s: s))
proc vstr*(s: ScriptStr): ScriptValue {.inline.} = ScriptValue(kind: vkString, str: s)
proc vtable*(t: ScriptTable): ScriptValue {.inline.} = ScriptValue(kind: vkTable, tbl: t)
proc vfunc*(c: ScriptFunc): ScriptValue {.inline.} = ScriptValue(kind: vkFunction, fn: c)
proc vud*(u: Userdata): ScriptValue {.inline.} = ScriptValue(kind: vkUserdata, ud: u)

proc isNil*(v: ScriptValue): bool {.inline.} = v.kind == vkNil
proc truthy*(v: ScriptValue): bool {.inline.} =
  not (v.kind == vkNil or (v.kind == vkBool and not v.b))

proc typeName*(v: ScriptValue): string =
  case v.kind
  of vkNil: "nil"
  of vkBool: "boolean"
  of vkNumber: "number"
  of vkString: "string"
  of vkTable: "table"
  of vkFunction: "function"
  of vkUserdata: v.ud.cls.name
  of vkOther: "userdata"

proc setRet*(ret: var RetVals, v: ScriptValue) {.inline.} =
  ret.count = 1
  ret.first = v
  ret.rest.setLen(0)

proc setRet*(ret: var RetVals, vals: openArray[ScriptValue]) =
  ret.count = vals.len
  ret.rest.setLen(0)
  if vals.len > 0:
    ret.first = vals[0]
    for i in 1 ..< vals.len: ret.rest.add(vals[i])
  else:
    ret.first = NilValue

proc retAt*(ret: RetVals, i: int): ScriptValue {.inline.} =
  if i >= ret.count: NilValue
  elif i == 0: ret.first
  else: ret.rest[i - 1]

proc toSeq*(ret: RetVals): seq[ScriptValue] =
  for i in 0 ..< ret.count: result.add(ret.retAt(i))

# ---------------------------------------------------------- number format ----
proc numToStr*(n: float64): string =
  if n != n: return "nan"
  if n == Inf: return "inf"
  if n == NegInf: return "-inf"
  if n == floor(n) and abs(n) < 1e15:
    return $int64(n)
  result = formatFloat(n, ffDefault, 14)
  var mant = result
  var expo = ""
  let e = result.find('e')
  if e >= 0:
    mant = result[0 ..< e]
    expo = result[e .. ^1]
  if '.' in mant:
    mant = mant.strip(leading = false, chars = {'0'})
    if mant.endsWith("."): mant.setLen(mant.len - 1)
  result = mant & expo

proc strToNum*(s: string, ok: var bool): float64 =
  ## Lua's tonumber() for a string: decimal (with exponent) or 0x hex.
  ok = false
  let t = s.strip()
  if t.len == 0: return 0.0
  var neg = false
  var body = t
  if body[0] in {'-', '+'}:
    neg = body[0] == '-'
    body = body[1 .. ^1]
  if body.len > 2 and body[0] == '0' and body[1] in {'x', 'X'}:
    var v = 0.0
    for c in body[2 .. ^1]:
      let d = case c
        of '0'..'9': ord(c) - ord('0')
        of 'a'..'f': ord(c) - ord('a') + 10
        of 'A'..'F': ord(c) - ord('A') + 10
        else: -1
      if d < 0: return 0.0
      v = v * 16.0 + d.float64
    ok = true
    return if neg: -v else: v
  var sawDigit = false
  for c in body:
    if c in {'0'..'9'}: sawDigit = true
    elif c notin {'.', 'e', 'E', '+', '-'}: return 0.0
  if not sawDigit: return 0.0
  try:
    let v = parseFloat(body)
    ok = true
    result = if neg: -v else: v
  except ValueError:
    ok = false

# ------------------------------------------------------ memory and hooks ----
proc c_realloc(p: pointer, size: csize_t): pointer {.importc: "realloc", header: "<stdlib.h>".}
proc c_free(p: pointer) {.importc: "free", header: "<stdlib.h>".}
proc lua_concat(L: LuaState, n: cint) {.importc, cdecl.}

proc luaAlloc(ud, p: pointer, osize, nsize: csize_t): pointer {.cdecl.} =
  ## There is no memory cap: this only fails when the machine is out of
  ## memory.
  if nsize == 0:
    c_free(p)
    return nil
  c_realloc(p, nsize)

# Procs that leave through lua_error (a longjmp) must not register a Nim
# stack-trace frame: debug builds push one on entry and pop it on return, and
# a frame that is jumped over stays linked to a dead stack forever.
{.push stackTrace: off, lineTrace: off.}

proc raiseWatchdog(L: LuaState): cint {.cdecl.} =
  ## The watchdog's error, "file:line: ..." where the script was.
  luaL_where(L, 0)
  discard lua_pushlstring(L, cstring(watchMsg), csize_t(watchMsg.len))
  lua_concat(L, 2)
  lua_error(L)

proc countHook(L: LuaState, ar: pointer) {.cdecl.} =
  ## Every HookGranularity instructions (coroutines inherit it). Holds no Nim
  ## state, so it may raise. Once tripped it fires on every instruction of the
  ## thread it catches, so `while true do pcall(f) end` cannot outlive it: the
  ## first instruction outside the pcall raises again.
  if watchTripped:
    lua_sethook(L, countHook, LUA_MASKCOUNT, 1)
    discard raiseWatchdog(L)
  if lua_gethookcount(L) == 1:   # left over from an earlier trip
    lua_sethook(L, countHook, LUA_MASKCOUNT, HookGranularity)
  let now = watchClock()
  var limit, spent: float64
  if callDepth > 0:
    limit = watchLimit
    spent = now - watchStart
    if watchFrameArmed and watchFrameSpent + spent > watchFrameLimit:
      limit = 0.0
  else:
    # Lua running outside every call: a finalizer (__gc) during an allocation.
    if idleStart == 0.0: idleStart = now
    limit = watchCallLimit
    spent = now - idleStart
  if spent > limit:
    watchTripped = true
    watchMsg = "script did not return for " & $int(spent + 0.5) &
               " s (frozen?): stopped by the watchdog"
    lua_sethook(L, countHook, LUA_MASKCOUNT, 1)
    discard raiseWatchdog(L)

proc panicFn(L: LuaState): cint {.cdecl.} =
  ## An error outside every protected call: a bug in this bridge, never a mod's.
  let msg = lua_tolstring(L, -1, nil)
  stderr.writeLine("Lua panic: ", if msg.isNil: "?" else: $msg)
  quit(1)

{.pop.}

# ------------------------------------------------------------ references ----
proc refTop(L: LuaState): LuaRef =
  ## Pops the top value into the registry.
  LuaRef(id: luaL_ref(L, LUA_REGISTRYINDEX), gen: luaGen)

proc refAt(L: LuaState, idx: cint): LuaRef =
  lua_pushvalue(L, idx)
  refTop(L)

proc pushRef(L: LuaState, r: LuaRef) =
  if r.isNil or r.gen != luaGen: lua_pushnil(L)
  else: discard lua_rawgeti(L, LUA_REGISTRYINDEX, r.id)

proc requireVM(): VM =
  if theVM.isNil or theVM.L.isNil:
    raise newException(ScriptError, "no script VM")
  theVM

template withL(body: untyped) =
  let L {.inject.} = requireVM().L
  body

# -------------------------------------------------------------- slots ----
proc allocUdSlot(u: Userdata): int32 =
  if udFree.len > 0:
    result = udFree.pop()
    udSlots[result] = u
  else:
    result = udSlots.len.int32
    udSlots.add(u)

proc allocNatSlot(b: NativeBox): int32 =
  if natFree.len > 0:
    result = natFree.pop()
    natSlots[result] = b
  else:
    result = natSlots.len.int32
    natSlots.add(b)

proc payloadAt(L: LuaState, idx: cint): ptr UdPayload {.inline.} =
  ## Our userdata are exactly one UdPayload; anything else (an io file
  ## handle is two pointers) is not ours, whatever its first bytes hold.
  if lua_type(L, idx) != LUA_TUSERDATA or
     lua_rawlen(L, idx) != uint64(sizeof(UdPayload)): return nil
  cast[ptr UdPayload](lua_touserdata(L, idx))

proc userdataAt(L: LuaState, idx: cint): Userdata =
  let pl = payloadAt(L, idx)
  if pl != nil and pl.tag == TagUserdata and pl.slot >= 0 and pl.slot < udSlots.len.int32:
    udSlots[pl.slot]
  else:
    nil

proc slotGc(L: LuaState): cint {.cdecl.} =
  ## __gc of every userdata this bridge makes: lets go of its Nim object.
  let pl = payloadAt(L, 1)
  if pl != nil and pl.slot >= 0:
    if pl.tag == TagUserdata and pl.slot < udSlots.len.int32:
      udSlots[pl.slot] = nil
      udFree.add(pl.slot)
    elif pl.tag == TagNative and pl.slot < natSlots.len.int32:
      natSlots[pl.slot] = nil
      natFree.add(pl.slot)
    pl.slot = -1
  0

# ---------------------------------------------------------- conversions ----
proc pushUserdata(L: LuaState, u: Userdata)

proc toValue(L: LuaState, idx: cint): ScriptValue =
  case lua_type(L, idx)
  of LUA_TNIL, LUA_TNONE: NilValue
  of LUA_TBOOLEAN: vbool(lua_toboolean(L, idx) != 0)
  of LUA_TNUMBER:
    if lua_isinteger(L, idx) != 0:
      ScriptValue(kind: vkNumber, n: lua_tointegerx(L, idx, nil).float64, isInt: true)
    else:
      ScriptValue(kind: vkNumber, n: lua_tonumberx(L, idx, nil))
  of LUA_TSTRING:
    var len: csize_t
    let p = lua_tolstring(L, idx, addr len)
    var s = newString(len.int)
    if len > 0: copyMem(addr s[0], p, len.int)
    vstr(s)
  of LUA_TTABLE: ScriptValue(kind: vkTable, tbl: ScriptTable(r: refAt(L, idx)))
  of LUA_TFUNCTION: ScriptValue(kind: vkFunction, fn: ScriptFunc(r: refAt(L, idx)))
  of LUA_TUSERDATA:
    let u = userdataAt(L, idx)
    if u.isNil: ScriptValue(kind: vkOther, other: refAt(L, idx))
    else: vud(u)
  else:
    ScriptValue(kind: vkOther, other: refAt(L, idx))

proc pushValue(L: LuaState, v: ScriptValue) =
  case v.kind
  of vkNil: lua_pushnil(L)
  of vkBool: lua_pushboolean(L, cint(v.b))
  of vkNumber:
    if v.isInt and abs(v.n) < 9.0e15: lua_pushinteger(L, int64(v.n))
    else: lua_pushnumber(L, v.n)
  of vkString:
    discard lua_pushlstring(L, cstring(v.str.s), csize_t(v.str.s.len))
  of vkTable: pushRef(L, v.tbl.r)
  of vkFunction: pushRef(L, v.fn.r)
  of vkUserdata: pushUserdata(L, v.ud)
  of vkOther: pushRef(L, v.other)

proc pushRet(L: LuaState, ret: RetVals): cint =
  discard lua_checkstack(L, cint(ret.count + 8))
  for i in 0 ..< ret.count: pushValue(L, ret.retAt(i))
  ret.count.cint

# ------------------------------------------------------ error plumbing ----
proc pushErrorFor(L: LuaState, e: ref CatchableError) =
  ## The error message for lua_error: "file:line: msg" like luaL_error.
  var msg = e.msg
  if not (e of ref ScriptError and (ref ScriptError)(e).positioned):
    luaL_where(L, 1)
    var len: csize_t
    let p = lua_tolstring(L, -1, addr len)
    var where = newString(len.int)
    if len > 0: copyMem(addr where[0], p, len.int)
    lua_pop(L, 1)
    msg = where & msg
  discard lua_pushlstring(L, cstring(msg), csize_t(msg.len))

template luaEntry(name, body: untyped) =
  ## A C function Lua calls into. `body` computes the number of results; a
  ## ScriptError (or any other CatchableError) becomes a Lua error, raised
  ## only after every Nim scope inside has finished.
  proc `name Impl`(L {.inject.}: LuaState): tuple[n: cint, err: bool] {.nimcall.} =
    try:
      let n: cint = block:
        body
      result = (n, false)
    except CatchableError as e:
      pushErrorFor(L, e)
      result = (0.cint, true)
  proc name(state: LuaState): cint {.cdecl, stackTrace: off, lineTrace: off.} =
    let r = `name Impl`(state)
    if r.err: discard lua_error(state)
    r.n

# --------------------------------------------------------------- natives ----
luaEntry(nativeTrampoline):
  let pl = payloadAt(L, lua_upvalueindex(1))   # debug.setupvalue can change it
  if pl.isNil or pl.tag != TagNative or pl.slot < 0 or pl.slot >= natSlots.len.int32 or
     natSlots[pl.slot].isNil:
    raise newException(ScriptError, "stale native function")
  let box = natSlots[pl.slot]
  let top = lua_gettop(L)
  var args = newSeq[ScriptValue](top)
  for i in 0 ..< top: args[i] = toValue(L, cint(i + 1))
  var ret: RetVals
  box.fn(theVM, args, ret)
  pushRet(L, ret)

var gcMeta: LuaRef   ## metatable with just __gc, for native boxes

proc newNative*(name: string, fn: NativeProc): ScriptNative =
  ScriptNative(name: name, fn: fn)

proc vnative*(n: ScriptNative): ScriptValue =
  ## A Lua function that runs `n.fn` (a C closure holding its Nim box).
  withL:
    let pl = cast[ptr UdPayload](lua_newuserdatauv(L, csize_t(sizeof(UdPayload)), 0))
    pl.tag = TagNative
    pl.slot = allocNatSlot(NativeBox(name: n.name, fn: n.fn))
    pushRef(L, gcMeta)
    discard lua_setmetatable(L, -2)
    lua_pushcclosure(L, nativeTrampoline, 1)
    result = ScriptValue(kind: vkFunction, fn: ScriptFunc(r: refTop(L)))

# -------------------------------------------------------------- tables ----
proc newScriptTable*(narr = 0): ScriptTable =
  withL:
    lua_createtable(L, narr.cint, 0)
    result = ScriptTable(r: refTop(L))

proc checkKey(k: ScriptValue) =
  if k.kind == vkNil: raise newException(ScriptError, "table index is nil")
  if k.kind == vkNumber and k.n != k.n: raise newException(ScriptError, "table index is NaN")

proc rawGet*(t: ScriptTable, k: ScriptValue): ScriptValue =
  if k.kind == vkNil or (k.kind == vkNumber and k.n != k.n): return NilValue
  withL:
    pushRef(L, t.r)
    if lua_type(L, -1) != LUA_TTABLE:
      lua_pop(L, 1)
      return NilValue
    pushValue(L, k)
    discard lua_rawget(L, -2)
    result = toValue(L, -1)
    lua_pop(L, 2)

proc rawGetStr*(t: ScriptTable, s: string): ScriptValue =
  withL:
    pushRef(L, t.r)
    if lua_type(L, -1) != LUA_TTABLE:
      lua_pop(L, 1)
      return NilValue
    discard lua_pushlstring(L, cstring(s), csize_t(s.len))
    discard lua_rawget(L, -2)
    result = toValue(L, -1)
    lua_pop(L, 2)

proc rawGetStr*(t: ScriptTable, s: ScriptStr): ScriptValue {.inline.} = rawGetStr(t, s.s)

proc rawSet*(t: ScriptTable, k, v: ScriptValue) =
  checkKey(k)
  withL:
    pushRef(L, t.r)
    if lua_type(L, -1) != LUA_TTABLE:
      lua_pop(L, 1)
      return
    pushValue(L, k)
    pushValue(L, v)
    lua_rawset(L, -3)
    lua_pop(L, 1)

proc len*(t: ScriptTable): int =
  ## The raw length (the border of the array part).
  withL:
    pushRef(L, t.r)
    result = if lua_type(L, -1) == LUA_TTABLE: int(lua_rawlen(L, -1)) else: 0
    lua_pop(L, 1)

proc item*(t: ScriptTable, i: int): ScriptValue =
  ## Element `i`, 1-based like Lua.
  withL:
    pushRef(L, t.r)
    if lua_type(L, -1) != LUA_TTABLE:
      lua_pop(L, 1)
      return NilValue
    discard lua_rawgeti(L, -1, i.int64)
    result = toValue(L, -1)
    lua_pop(L, 2)

proc add*(t: ScriptTable, v: ScriptValue) =
  ## Append (t[#t + 1] = v).
  withL:
    pushRef(L, t.r)
    if lua_type(L, -1) != LUA_TTABLE:
      lua_pop(L, 1)
      return
    let n = int64(lua_rawlen(L, -1))
    pushValue(L, v)
    lua_rawseti(L, -2, n + 1)
    lua_pop(L, 1)

proc entries*(t: ScriptTable): seq[tuple[k, v: ScriptValue]] =
  ## Every key/value pair (a snapshot, in Lua's traversal order).
  withL:
    pushRef(L, t.r)
    if lua_type(L, -1) != LUA_TTABLE:
      lua_pop(L, 1)
      return
    let ti = lua_gettop(L)
    lua_pushnil(L)
    while lua_next(L, ti) != 0:
      result.add((toValue(L, -2), toValue(L, -1)))
      lua_pop(L, 1)
    lua_pop(L, 1)

iterator pairsCursor*(t: ScriptTable): tuple[k, v: ScriptValue] =
  for e in entries(t): yield e

iterator items*(t: ScriptTable): ScriptValue =
  ## t[1] .. t[#t]
  let n = t.len
  for i in 1 .. n: yield t.item(i)

proc hashCount*(t: ScriptTable): int =
  ## Entries outside the array part 1..#t.
  let n = t.len
  for (k, _) in entries(t):
    if not (k.kind == vkNumber and k.n == floor(k.n) and k.n >= 1 and k.n <= n.float64):
      inc result

proc meta*(t: ScriptTable): ScriptTable =
  withL:
    pushRef(L, t.r)
    if lua_getmetatable(L, -1) != 0:
      result = ScriptTable(r: refTop(L))
    lua_pop(L, 1)

proc `meta=`*(t: ScriptTable, mt: ScriptTable) =
  withL:
    pushRef(L, t.r)
    if mt.isNil: lua_pushnil(L) else: pushRef(L, mt.r)
    discard lua_setmetatable(L, -2)
    lua_pop(L, 1)

proc rawEquals*(a, b: ScriptValue): bool =
  if a.kind != b.kind: return false
  case a.kind
  of vkNil: result = true
  of vkBool: result = a.b == b.b
  of vkNumber: result = a.n == b.n
  of vkString: result = a.str.s == b.str.s
  of vkUserdata: result = a.ud.cls == b.ud.cls and a.ud.key == b.ud.key
  else:
    withL:
      pushValue(L, a)
      pushValue(L, b)
      result = lua_rawequal(L, -1, -2) != 0
      lua_pop(L, 2)

# ------------------------------------------------------------ userdata ----
luaEntry(udIndex):
  let u = userdataAt(L, 1)
  if u.isNil or u.cls.index.isNil:
    raise newException(ScriptError, "attempt to index a " & (if u.isNil: "userdata" else: u.cls.name) & " value")
  let key = toValue(L, 2)
  pushValue(L, u.cls.index(theVM, u, key))
  1.cint

luaEntry(udNewindex):
  let u = userdataAt(L, 1)
  if u.isNil or u.cls.newindex.isNil:
    raise newException(ScriptError, "cannot assign fields of a " & (if u.isNil: "userdata" else: u.cls.name))
  u.cls.newindex(theVM, u, toValue(L, 2), toValue(L, 3))
  0.cint

luaEntry(udLen):
  let u = userdataAt(L, 1)
  if u.isNil or u.cls.len.isNil:
    raise newException(ScriptError, "attempt to get length of a " & (if u.isNil: "userdata" else: u.cls.name) & " value")
  lua_pushinteger(L, u.cls.len(theVM, u).int64)
  1.cint

luaEntry(udCall):
  let u = userdataAt(L, 1)
  if u.isNil or u.cls.call.isNil:
    raise newException(ScriptError, "attempt to call a " & (if u.isNil: "userdata" else: u.cls.name) & " value")
  let top = lua_gettop(L)
  var args = newSeq[ScriptValue](max(0, top - 1))
  for i in 2 .. top: args[i - 2] = toValue(L, cint(i))
  var ret: RetVals
  u.cls.call(theVM, u, args, ret)
  pushRet(L, ret)

luaEntry(udNext):
  let u = userdataAt(L, 1)
  if u.isNil or u.cls.next.isNil:
    raise newException(ScriptError, "cannot iterate this value")
  var k, v: ScriptValue
  if u.cls.next(theVM, u, toValue(L, 2), k, v):
    pushValue(L, k)
    pushValue(L, v)
    2.cint
  else:
    lua_pushnil(L)
    1.cint

luaEntry(udPairs):
  lua_pushcclosure(L, udNext, 0)
  lua_pushvalue(L, 1)
  lua_pushnil(L)
  3.cint

luaEntry(udTostring):
  let u = userdataAt(L, 1)
  let s = if u.isNil: "userdata"
          elif not u.cls.tostr.isNil: u.cls.tostr(u)
          else: u.cls.name & ": 0x" & toHex(cast[uint](u.key), 8).toLowerAscii
  discard lua_pushlstring(L, cstring(s), csize_t(s.len))
  1.cint

luaEntry(udEq):
  let a = userdataAt(L, 1)
  let b = userdataAt(L, 2)
  lua_pushboolean(L, cint(not a.isNil and not b.isNil and a.cls == b.cls and a.key == b.key))
  1.cint

proc setField(L: LuaState, name: string, fn: LuaCFunction) =
  discard lua_pushstring(L, cstring(name))
  lua_pushcclosure(L, fn, 0)
  lua_rawset(L, -3)

proc ensureClass(L: LuaState, cls: UdClass) =
  ## The class's metatable (and entity cache) for the current Lua state.
  if not cls.mt.isNil and cls.mt.gen == luaGen: return
  lua_createtable(L, 0, 12)
  discard lua_pushstring(L, "__name")
  discard lua_pushstring(L, cstring(cls.name))
  lua_rawset(L, -3)
  setField(L, "__index", udIndex)
  setField(L, "__newindex", udNewindex)
  if not cls.len.isNil: setField(L, "__len", udLen)
  if not cls.call.isNil: setField(L, "__call", udCall)
  if not cls.next.isNil: setField(L, "__pairs", udPairs)
  setField(L, "__tostring", udTostring)
  setField(L, "__eq", udEq)
  setField(L, "__gc", slotGc)
  cls.mt = refTop(L)
  if cls.cached:
    lua_createtable(L, 0, 0)
    lua_createtable(L, 0, 1)
    discard lua_pushstring(L, "__mode")
    discard lua_pushstring(L, "v")
    lua_rawset(L, -3)
    discard lua_setmetatable(L, -2)
    cls.cache = refTop(L)

proc newUserdata(L: LuaState, u: Userdata) =
  let pl = cast[ptr UdPayload](lua_newuserdatauv(L, csize_t(sizeof(UdPayload)), 0))
  pl.tag = TagUserdata
  pl.slot = allocUdSlot(u)
  pushRef(L, u.cls.mt)
  discard lua_setmetatable(L, -2)

proc pushUserdata(L: LuaState, u: Userdata) =
  ensureClass(L, u.cls)
  if not u.cls.cached:
    newUserdata(L, u)
    return
  pushRef(L, u.cls.cache)
  if lua_rawgetp(L, -1, u.key) == LUA_TUSERDATA:
    lua_rotate(L, -2, 1)   # [ud, cache]
    lua_pop(L, 1)
    return
  lua_pop(L, 1)            # the nil
  newUserdata(L, u)        # [cache, ud]
  lua_pushvalue(L, -1)
  lua_rawsetp(L, -3, u.key)
  lua_rotate(L, -2, 1)
  lua_pop(L, 1)

# -------------------------------------------------------------- calling ----
proc tracebackHandler(L: LuaState): cint {.cdecl.} =
  ## Message handler of protectedCall: the error text plus a traceback.
  if lua_type(L, 1) == LUA_TSTRING:
    luaL_traceback(L, L, lua_tolstring(L, 1, nil), 1)
  else:
    luaL_traceback(L, L, "(error object is not a string)", 1)
  1

proc errorText(L: LuaState, idx: cint): string =
  if lua_type(L, idx) == LUA_TSTRING:
    var len: csize_t
    let p = lua_tolstring(L, idx, addr len)
    result = newString(len.int)
    if len > 0: copyMem(addr result[0], p, len.int)
  else:
    result = "(error object is a " & $lua_type(L, idx) & " value)"

proc beginCall(L: LuaState, limit: float64): bool =
  ## Enter a script call; false when calls already nest MaxScriptNesting deep.
  ## The outermost call starts the watchdog's clock (a nested one, from a
  ## native inside a script, runs on the outer call's).
  if callDepth >= MaxScriptNesting: return false
  if callDepth == 0:
    watchTripped = false
    idleStart = 0.0
    watchLimit = if limit > 0.0: limit else: watchCallLimit
    watchStart = watchClock()
    if lua_gethook(L).isNil:   # a mod's debug.sethook() took the watchdog off
      lua_sethook(L, countHook, LUA_MASKCOUNT, HookGranularity)
  inc callDepth
  true

proc endCall(L: LuaState) =
  dec callDepth
  if callDepth == 0:
    watchFrameSpent += watchClock() - watchStart
    idleStart = 0.0
    if watchTripped:
      watchTripped = false
      lua_sethook(L, countHook, LUA_MASKCOUNT, HookGranularity)

const NestingError = "scripts call each other more than " & $MaxScriptNesting &
                     " levels deep (a hook or event raising itself?)"

proc setWatchdogClock*(clock: proc (): float64 {.nimcall.}) =
  ## The watchdog's clock (main.nim passes raylib's monotonic timer once the
  ## window exists; until then the wall clock).
  watchClock = clock

proc setWatchdogLimits*(call = DefaultCallLimit, frame = FrameLimit) =
  ## Seconds a call / a whole frame of calls may run (tests shorten them).
  watchCallLimit = call
  watchFrameLimit = frame

proc resetWatchdogFrame*() =
  ## Once per frame: the per-frame total starts again.
  watchFrameSpent = 0.0
  watchFrameArmed = true

proc protectedCall*(vm: VM, f: ScriptValue, args: openArray[ScriptValue],
                    ret: var RetVals, limit = 0.0): string =
  ## Run `f` under the watchdog (`limit` seconds for an outermost call, 0 =
  ## the default; a nested call keeps the outer one's). "" on success, else
  ## the error with a traceback.
  let L = vm.L
  ret = RetVals()
  if L.isNil: return "no script VM"
  if not beginCall(L, limit): return NestingError
  let base = lua_gettop(L)
  discard lua_checkstack(L, cint(args.len + 8))
  lua_pushcclosure(L, tracebackHandler, 0)
  pushValue(L, f)
  for a in args: pushValue(L, a)
  let st = lua_pcall(L, args.len.cint, LUA_MULTRET, base + 1)
  endCall(L)
  if st != LUA_OK:
    result = errorText(L, -1)
    lua_settop(L, base)
    return
  let n = lua_gettop(L) - base - 1
  var vals = newSeq[ScriptValue](n)
  for i in 0 ..< n: vals[i] = toValue(L, cint(base + 2 + i))
  ret.setRet(vals)
  lua_settop(L, base)

proc callValue*(vm: VM, f: ScriptValue, args: openArray[ScriptValue], ret: var RetVals) =
  ## Call from inside a native: errors come back as a ScriptError (already
  ## positioned), which the native's trampoline turns back into a Lua error.
  let L = vm.L
  if not beginCall(L, 0.0): raise newException(ScriptError, NestingError)
  let base = lua_gettop(L)
  discard lua_checkstack(L, cint(args.len + 8))
  pushValue(L, f)
  for a in args: pushValue(L, a)
  let st = lua_pcall(L, args.len.cint, LUA_MULTRET, 0)
  endCall(L)
  if st != LUA_OK:
    let msg = errorText(L, -1)
    lua_settop(L, base)
    var e = newException(ScriptError, msg)
    e.positioned = true
    raise e
  let n = lua_gettop(L) - base
  var vals = newSeq[ScriptValue](n)
  for i in 0 ..< n: vals[i] = toValue(L, cint(base + 1 + i))
  ret.setRet(vals)
  lua_settop(L, base)

proc loadChunk*(vm: VM, src, chunkName: string, env: ScriptTable): ScriptFunc =
  ## Compile a chunk (source, or bytecode from string.dump / luac) into a
  ## function whose globals are `env`. Raises ScriptError on a syntax error.
  let L = vm.L
  let st = luaL_loadbufferx(L, cstring(src), csize_t(src.len), cstring("@" & chunkName), "bt")
  if st != LUA_OK:
    let msg = errorText(L, -1)
    lua_pop(L, 1)
    var e = newException(ScriptError, msg)
    e.positioned = true
    raise e
  pushRef(L, env.r)
  discard lua_setupvalue(L, -2, 1)   # its _ENV
  ScriptFunc(r: refTop(L))

proc runtimeError*(vm: VM, msg: string) {.noreturn.} =
  raise newException(ScriptError, msg)

proc tostr*(vm: VM, v: ScriptValue): string =
  ## Nim-side tostring (no metamethods run).
  case v.kind
  of vkNil: "nil"
  of vkBool: (if v.b: "true" else: "false")
  of vkNumber: (if v.isInt: $int64(v.n) else: numToStr(v.n))
  of vkString: v.str.s
  of vkUserdata:
    if not v.ud.cls.tostr.isNil: v.ud.cls.tostr(v.ud)
    else: v.ud.cls.name
  else: typeName(v)

luaEntry(logNative):
  if lua_type(L, 1) == LUA_TSTRING and not theVM.printSink.isNil:
    theVM.printSink(toValue(L, 1).str.s)
  0.cint

luaEntry(quitNative):
  ## os.exit([code]): the game closes at the end of the frame (saving as its
  ## Quit does); the script unwinds with QuitSentinel, which is not reported.
  modQuitRequested = true
  modQuitCode = case lua_type(L, 1)
    of LUA_TBOOLEAN: (if lua_toboolean(L, 1) != 0: 0 else: 1)
    of LUA_TNUMBER: int(lua_tointegerx(L, 1, nil))
    else: 0
  if modQuitRequested: raise newException(ScriptError, QuitSentinel)
  0.cint

var
  warnBuf: string
  warnOn = true

proc warnFn(ud: pointer, msg: cstring, tocont: cint) {.cdecl.} =
  ## Lua's warnings (warn(), an error inside a __gc) go to the mod log.
  ## Called from inside Lua, possibly mid-allocation: never raises.
  try:
    if msg.isNil: return
    let piece = $msg
    if warnBuf.len == 0 and tocont == 0 and piece.len > 0 and piece[0] == '@':
      if piece == "@on": warnOn = true
      elif piece == "@off": warnOn = false
      return
    warnBuf.add(piece)
    if tocont == 0:
      let whole = warnBuf
      warnBuf = ""
      if warnOn and not theVM.isNil and not theVM.warnSink.isNil:
        theVM.warnSink(whole)
  except CatchableError:
    discard

# ------------------------------------------------------- the file gate ----
var fileGate*: proc (path: string, write, quiet: bool): tuple[path, err: string] {.nimcall.}
  ## The mod file sandbox (set by mod_api): the absolute path a script's
  ## `path` means, or why the running mod may not open it (`err`, logged to
  ## the mod's log unless `quiet`). Every file the Lua libraries open goes
  ## through it (lua_files.h), and so do the path arguments of engine.call
  ## and rl.* (gatedPath); nil refuses all.

proc tophatFileCheck(path: cstring, write: cint, outp: ptr UncheckedArray[char],
                     cap: cint): cint {.exportc: "tophat_file_check", cdecl.} =
  ## Called by lua_files.h from inside a Lua library call: returns normally,
  ## never raises (the C caller turns a refusal into EACCES).
  try:
    if path.isNil or fileGate.isNil: return 0
    let (real, err) = fileGate($path, write != 0, quiet = false)
    if err.len > 0 or real.len == 0 or real.len >= cap.int or '\0' in real: return 0
    copyMem(outp, real.cstring, real.len + 1)
    1
  except CatchableError:
    0

proc gatedPath*(vm: VM, path: string, write: bool, what: string): string =
  ## A path argument of engine.call / rl.* where the running mod may use it
  ## (an error otherwise).
  if fileGate.isNil: vm.runtimeError(what & ": scripts cannot use files here")
  let (real, err) = fileGate(path, write, quiet = true)
  if err.len > 0: vm.runtimeError(what & ": " & err)
  real

# ------------------------------------------------------------- the VM ----
const Prelude = """
local log, select, tostring, concat, quit = ...
function print(...)
  local parts = {}
  for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
  log(concat(parts, "\t"))
end
unpack = table.unpack
math.pow = function(x, y) return x ^ y end
math.atan2 = math.atan
function math.clamp(x, lo, hi) if x < lo then return lo elseif x > hi then return hi end return x end
function math.lerp(a, b, t) return a + (b - a) * t end
function math.sign(x) if x > 0 then return 1 elseif x < 0 then return -1 end return 0 end
function math.round(x) if x >= 0 then return math.floor(x + 0.5) end return math.ceil(x - 0.5) end
function string.split(s, sep)
  sep = sep or " "
  if sep == "" then error("bad argument #2 to 'split' (empty separator)", 2) end
  local out, i = {}, 1
  while true do
    local a, b = string.find(s, sep, i, true)
    if not a then out[#out + 1] = string.sub(s, i) return out end
    out[#out + 1] = string.sub(s, i, a - 1)
    i = b + 1
  end
end
function string.trim(s) return (string.gsub(s, "^%s*(.-)%s*$", "%1")) end
-- The game formats and parses numbers with the C locale.
local setlocale = os.setlocale
function os.setlocale(locale, category)
  if locale ~= nil and locale ~= "C" and
     (category == nil or category == "all" or category == "numeric") then
    error("os.setlocale: the game needs the C number format; change 'collate', " ..
          "'ctype', 'monetary' or 'time' instead", 2)
  end
  return setlocale(locale, category)
end
function os.exit(code) quit(code) end
function debug.debug() error("debug.debug reads a terminal, which the game does not have", 2) end
"""

const
  SharedGlobals = ["assert", "error", "getmetatable", "ipairs", "next", "pairs", "rawequal",
                   "rawget", "rawlen", "rawset", "select", "setmetatable", "tonumber",
                   "tostring", "type", "_VERSION", "load", "loadfile", "dofile", "pcall",
                   "xpcall", "collectgarbage", "warn", "require", "package"]
  Libraries = ["coroutine", "table", "string", "math", "utf8", "io", "os", "debug"]
    ## copied per mod; `package` stays one table (require's searchers read it)

proc closeScriptVM*() =
  ## Close the Lua state: every userdata lets go of its Nim object, every
  ## reference Nim still holds goes dead.
  if theVM.isNil or theVM.L.isNil: return
  let L = theVM.L
  inc luaGen
  liveL = LuaState(nil)
  lua_close(L)
  theVM.L = LuaState(nil)
  udSlots.setLen(0)
  udFree.setLen(0)
  natSlots.setLen(0)
  natFree.setLen(0)
  callDepth = 0
  watchTripped = false
  idleStart = 0.0
  watchFrameSpent = 0.0
  warnBuf = ""
  warnOn = true

proc copyTable(L: LuaState, src: cint) =
  ## Push a shallow copy of the table at `src` (with the same metatable).
  let s = lua_absindex(L, src)
  lua_createtable(L, 0, 32)
  lua_pushnil(L)
  while lua_next(L, s) != 0:
    lua_pushvalue(L, -2)
    lua_rotate(L, -2, 1)     # [copy, key, key, value]
    lua_rawset(L, -4)
  if lua_getmetatable(L, s) != 0:
    discard lua_setmetatable(L, -2)

proc newScriptVM*(): tuple[vm: VM, base: ScriptTable] =
  ## A fresh Lua state (closing the previous one) and the shared library
  ## table every mod env falls through to.
  closeScriptVM()
  let L = lua_newstate(luaAlloc, nil, cuint(int64(epochTime() * 1000.0) and 0x7fffffff))
  discard lua_atpanic(L, panicFn)
  liveL = L
  theVM = VM(L: L)
  lua_sethook(L, countHook, LUA_MASKCOUNT, HookGranularity)
  lua_setwarnf(L, warnFn, nil)

  # Every standard library into the state's own globals. LUA_NOENV: the
  # player's LUA_PATH / LUA_CPATH environment must not change how mods load.
  discard lua_pushstring(L, "LUA_NOENV")
  lua_pushboolean(L, 1)
  lua_rawset(L, LUA_REGISTRYINDEX)
  for (name, opener) in [("_G", luaopen_base), ("package", luaopen_package),
                         ("coroutine", luaopen_coroutine), ("table", luaopen_table),
                         ("io", luaopen_io), ("os", luaopen_os), ("string", luaopen_string),
                         ("math", luaopen_math), ("utf8", luaopen_utf8), ("debug", luaopen_debug)]:
    luaL_requiref(L, cstring(name), opener, 1)
    lua_pop(L, 1)
  discard lua_rawgeti(L, LUA_REGISTRYINDEX, LUA_RIDX_GLOBALS)
  let globals = lua_gettop(L)

  # package: no search paths of its own (each mod's require finds its files
  # and other mods'; a mod may still add to package.path), no C searchers.
  discard lua_pushstring(L, "package")
  discard lua_rawget(L, globals)
  for field in ["path", "cpath"]:
    discard lua_pushstring(L, cstring(field))
    discard lua_pushstring(L, "")
    lua_rawset(L, -3)
  discard lua_pushstring(L, "searchers")
  discard lua_rawget(L, -2)
  if lua_type(L, -1) == LUA_TTABLE:
    for i in [4, 3]:
      lua_pushnil(L)
      lua_rawseti(L, -2, i.int64)
  lua_pop(L, 2)

  # The shared library table.
  lua_createtable(L, 0, 40)
  let baseIdx = lua_gettop(L)
  for name in SharedGlobals:
    discard lua_pushstring(L, cstring(name))
    discard lua_pushstring(L, cstring(name))
    discard lua_rawget(L, globals)
    lua_rawset(L, baseIdx)
  for name in Libraries:
    discard lua_pushstring(L, cstring(name))
    discard lua_pushstring(L, cstring(name))
    discard lua_rawget(L, globals)
    lua_rawset(L, baseIdx)
  let base = ScriptTable(r: refAt(L, baseIdx))

  # gc-only metatable for native boxes
  lua_createtable(L, 0, 1)
  discard lua_pushstring(L, "__gc")
  lua_pushcclosure(L, slotGc, 0)
  lua_rawset(L, -3)
  gcMeta = refTop(L)

  # Prelude: print, 5.1 names (unpack, math.pow), the game's extras, and
  # os.setlocale / os.exit / debug.debug made safe for a game.
  discard luaL_loadbufferx(L, Prelude, csize_t(Prelude.len), "=prelude", "t")
  lua_pushvalue(L, baseIdx)
  discard lua_setupvalue(L, -2, 1)
  lua_pushcclosure(L, logNative, 0)
  for name in ["select", "tostring"]:
    discard lua_pushstring(L, cstring(name))
    discard lua_rawget(L, globals)
  discard lua_pushstring(L, "table")
  discard lua_rawget(L, globals)
  discard lua_pushstring(L, "concat")
  discard lua_rawget(L, -2)
  lua_rotate(L, -2, 1)
  lua_pop(L, 1)
  lua_pushcclosure(L, quitNative, 0)
  if lua_pcall(L, 5, 0, 0) != LUA_OK:
    stderr.writeLine("mod prelude failed: ", errorText(L, -1))
    lua_pop(L, 1)
  lua_settop(L, 0)
  (theVM, base)

proc newModEnv*(base: ScriptTable, extra: openArray[string] = []): ScriptTable =
  ## One mod's globals: its own copies of the library tables (Lua's, plus the
  ## game's tables named in `extra`), falling through to `base`
  ## (getmetatable(_ENV).__index: what every mod shares). The copies are
  ## shallow: the natives inside stay shared, but one mod replacing
  ## `draw.circle` or adding to `spawn` changes only its own table.
  withL:
    lua_createtable(L, 0, 16)
    let env = lua_gettop(L)
    pushRef(L, base.r)
    let b = lua_gettop(L)
    for name in Libraries:
      discard lua_pushstring(L, cstring(name))
      discard lua_pushstring(L, cstring(name))
      discard lua_rawget(L, b)
      copyTable(L, -1)
      lua_rotate(L, -2, 1)
      lua_pop(L, 1)
      lua_rawset(L, env)
    for name in extra:
      discard lua_pushlstring(L, cstring(name), csize_t(name.len))
      discard lua_pushlstring(L, cstring(name), csize_t(name.len))
      discard lua_rawget(L, b)
      if lua_type(L, -1) == LUA_TTABLE:
        copyTable(L, -1)
        lua_rotate(L, -2, 1)
        lua_pop(L, 1)
        lua_rawset(L, env)
      else:
        lua_pop(L, 2)
    discard lua_pushstring(L, "_G")
    lua_pushvalue(L, env)
    lua_rawset(L, env)
    lua_createtable(L, 0, 1)
    discard lua_pushstring(L, "__index")
    lua_pushvalue(L, b)
    lua_rawset(L, -3)
    discard lua_setmetatable(L, env)
    lua_pop(L, 1)   # base
    result = ScriptTable(r: refTop(L))

proc tableKeysOf*(base: ScriptTable): seq[string] =
  ## The string keys of `base` whose values are tables (the game's libraries,
  ## for newModEnv's `extra`).
  for (k, v) in entries(base):
    if k.kind == vkString and v.kind == vkTable and k.str.s notin Libraries and
       k.str.s != "package":
      result.add(k.str.s)

# ------------------------------------------------------------ arg helpers ----
proc arg*(args: openArray[ScriptValue], i: int): ScriptValue {.inline.} =
  if i < args.len: args[i] else: NilValue

proc argError*(vm: VM, fname: string, i: int, msg: string) {.noreturn.} =
  vm.runtimeError("bad argument #" & $(i + 1) & " to '" & fname & "' (" & msg & ")")

proc checkNum*(vm: VM, args: openArray[ScriptValue], i: int, fname: string): float64 =
  let v = arg(args, i)
  if v.kind == vkNumber: return v.n
  if v.kind == vkString:
    var ok = false
    let n = strToNum(v.str.s, ok)
    if ok: return n
  vm.argError(fname, i, "number expected, got " & (if i < args.len: typeName(v) else: "no value"))

proc checkInt*(vm: VM, args: openArray[ScriptValue], i: int, fname: string): int =
  let n = vm.checkNum(args, i, fname)
  if n != n or abs(n) > 9.0e15: vm.argError(fname, i, "number has no integer representation")
  int(floor(n))

proc optNum*(vm: VM, args: openArray[ScriptValue], i: int, fname: string, def: float64): float64 =
  if arg(args, i).kind == vkNil: def else: vm.checkNum(args, i, fname)

proc optInt*(vm: VM, args: openArray[ScriptValue], i: int, fname: string, def: int): int =
  if arg(args, i).kind == vkNil: def else: vm.checkInt(args, i, fname)

proc checkStr*(vm: VM, args: openArray[ScriptValue], i: int, fname: string): string =
  let v = arg(args, i)
  case v.kind
  of vkString: v.str.s
  of vkNumber: (if v.isInt: $int64(v.n) else: numToStr(v.n))
  else: vm.argError(fname, i, "string expected, got " & (if i < args.len: typeName(v) else: "no value"))

proc optStr*(vm: VM, args: openArray[ScriptValue], i: int, fname: string, def: string): string =
  if arg(args, i).kind == vkNil: def else: vm.checkStr(args, i, fname)

proc checkTable*(vm: VM, args: openArray[ScriptValue], i: int, fname: string): ScriptTable =
  let v = arg(args, i)
  if v.kind != vkTable:
    vm.argError(fname, i, "table expected, got " & (if i < args.len: typeName(v) else: "no value"))
  v.tbl

proc checkFunc*(vm: VM, args: openArray[ScriptValue], i: int, fname: string): ScriptValue =
  let v = arg(args, i)
  if v.kind != vkFunction:
    vm.argError(fname, i, "function expected, got " & (if i < args.len: typeName(v) else: "no value"))
  v

proc reg*(t: ScriptTable, name: string, fn: NativeProc) =
  rawSet(t, vstr(name), vnative(newNative(name, fn)))
