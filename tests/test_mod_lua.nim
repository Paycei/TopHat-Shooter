# Tests for the mod scripting runtime (src/modding/lua_bridge.nim over the
# vendored Lua 5.5).
#   nim r --mm:orc tests/test_mod_lua.nim
# Lua itself is tested upstream; these check what the bridge promises: the
# sandbox, per-mod isolation, the instruction budget and memory cap that no
# script can swallow, error positions, natives, userdata classes and the
# table API the mod modules use.

import std/[strutils, times]
import ../src/modding/lua_bridge

var failures = 0
var passed = 0

let (vm, base) = newScriptVM()
var printed: seq[string]
vm.printSink = proc (s: string) = printed.add(s)

proc show(v: ScriptValue): string =
  if v.kind == vkString: "\"" & v.str.s & "\"" else: vm.tostr(v)

proc runIn(env: ScriptTable, src: string, budget = 50_000_000): (seq[ScriptValue], string) =
  var r: RetVals
  try:
    let f = vm.loadChunk(src, "test/main.lua", env)
    let err = vm.protectedCall(vfunc(f), [], r, budget)
    (r.toSeq, err)
  except ScriptError as e:
    (@[], e.msg)

proc runChunk(src: string, budget = 50_000_000): (seq[ScriptValue], string) =
  runIn(newModEnv(base), src, budget)

proc expect(name, src: string, expected: openArray[string]) =
  let (vals, err) = runChunk(src)
  if err.len > 0:
    echo "FAIL ", name, ": error ", err.splitLines()[0]
    inc failures
    return
  var got: seq[string]
  for v in vals: got.add(show(v))
  if got != @expected:
    echo "FAIL ", name, "\n  expected ", @expected, "\n  got      ", got
    inc failures
  else:
    inc passed

proc expectErr(name, src, fragment: string) =
  let (_, err) = runChunk(src)
  if err.len == 0 or fragment notin err:
    echo "FAIL ", name, ": expected an error containing '", fragment, "', got '", err.splitLines()[0], "'"
    inc failures
  else:
    inc passed

proc check(cond: bool, name: string) =
  if cond: inc passed
  else:
    echo "FAIL ", name
    inc failures

# ------------------------------------------------------------- language ----
expect("numbers", "return 7 // 2, 7 / 2, 2^10, 1 << 4, 0xff & 0x0f, math.type(1), math.type(1.0)",
       ["3", "3.5", "1024", "16", "15", "\"integer\"", "\"float\""])
expect("strings", """return ("abc"):upper(), string.format("%d|%5.2f|%s", 42, 3.14159, "hi"), ("a,b"):find(",", 1, true), ("x1y22"):gsub("%d", "#")""",
       ["\"ABC\"", "\"42| 3.14|hi\"", "2", "\"x#y##\"", "3"])   # only the last call expands
expect("goto and const", "local <const> n = 3 local s = 0 for i = 1, n do if i == 2 then goto skip end s = s + i ::skip:: end return s",
       ["4"])
expect("coroutines", "local co = coroutine.wrap(function(a) local b = coroutine.yield(a + 1) return b * 2 end) return co(1), co(5)",
       ["2", "10"])
expect("5.1 names and extras", "return unpack({1, 2}), math.pow(2, 3), math.clamp(9, 0, 5), math.round(-2.5), math.sign(-3), #string.split('a,,b', ','), ('  x  '):trim()",
       ["1", "8", "5", "-3", "-1", "3", "\"x\""])
expectErr("NaN keys stay errors (Lua keeps IEEE math even in fast-math builds)",
          "local t = {} t[0/0] = 1", "NaN")
expect("print goes to the log", "print('a', 1, nil, true, 2.5) return 1", ["1"])
check(printed.len > 0 and printed[^1] == "a\t1\tnil\ttrue\t2.5", "print output: " & $printed)

# -------------------------------------------------------------- sandbox ----
expect("no outside world", "return io, os, debug, package, load, loadfile, dofile, require, string.dump",
       ["nil", "nil", "nil", "nil", "nil", "nil", "nil", "nil", "nil"])
expect("locked metatables", "return getmetatable(_ENV), getmetatable('')", ["false", "false"])
expectErr("collectgarbage is limited", "collectgarbage('stop')", "only")
block isolation:
  let a = newModEnv(base)
  let b = newModEnv(base)
  discard runIn(a, "math.pi = 3 string.upper = nil shared = 1 function f() return 1 end")
  let (vals, err) = runIn(b, "return math.pi > 3.1, ('x'):upper(), shared, f")
  check(err.len == 0 and vals.len == 4 and vals[0].b and vals[1].str.s == "X" and
        vals[2].kind == vkNil and vals[3].kind == vkNil, "mods cannot touch each other's globals or libraries")
  let (v2, _) = runIn(a, "return shared, ('y'):upper()")
  check(v2.len == 2 and v2[0].kind == vkNumber and v2[1].str.s == "Y",
        "a mod keeps its own globals; string methods stay intact")

# --------------------------------------------------------------- guards ----
expectErr("endless loop", "while true do end", "ran too long")
expectErr("not through pcall", "local ok = pcall(function() while true do end end) return 'escaped'", "ran too long")
expectErr("not through xpcall", "xpcall(function() while true do end end, function() return 'no' end) return 'escaped'", "ran too long")
expectErr("not through coroutines", "local co = coroutine.create(function() while true do end end) coroutine.resume(co) return 'escaped'", "ran too long")
expectErr("memory cap", "local t = {} for i = 1, 1e9 do t[i] = ('x'):rep(4096) .. i end", "out of memory")
expect("memory comes back", "return collectgarbage('count') < 64 * 1024", ["true"])
expectErr("deep recursion", "local function f(n) return 1 + f(n + 1) end return f(1)", "stack overflow")
expectErr("deep nesting", "return " & "(".repeat(400) & "1" & ")".repeat(400), "")
expect("still healthy afterwards", "return 1 + 1", ["2"])

# --------------------------------------------------------------- errors ----
expectErr("syntax error position", "local x = = 1", "test/main.lua:1: unexpected symbol near '='")
expectErr("runtime error position", "\n\nlocal t = nil\nreturn t.x", "test/main.lua:4:")
block traceback:
  let (_, err) = runChunk("local function inner() error('deep') end\nlocal function outer() inner() end\nouter()")
  check("test/main.lua:1: deep" in err and "stack traceback" in err, "errors carry a traceback: " & err.splitLines()[0])

# -------------------------------------------------------------- natives ----
base.reg("twice") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
  ret.setRet(vnum(vm.checkNum(args, 0, "twice") * 2))
base.reg("pair") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
  ret.setRet([vstr(vm.checkStr(args, 0, "pair")), vnum(args.len)])
base.reg("strict") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
  discard vm.checkTable(args, 0, "strict")
base.reg("callback") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
  var r: RetVals
  vm.callValue(vm.checkFunc(args, 0, "callback"), [vnum(20)], r)
  ret.setRet(r.retAt(0))
expect("native call", "return twice(21), pair('x', 1, 2)", ["42", "\"x\"", "3"])
expectErr("native arg error has the caller's position", "\n\nstrict(5)", "test/main.lua:3: bad argument #1 to 'strict' (table expected, got number)")
expect("native calling back into Lua", "return callback(function(n) return n + 1 end)", ["21"])
expectErr("error inside the callback", "callback(function() error('inner boom') end)", "inner boom")
expect("pcall catches native errors", "local ok, e = pcall(strict, 1) return ok, e:find('table expected') ~= nil", ["false", "true"])

# ------------------------------------------------------------- userdata ----
block userdata:
  var items = @[10, 20, 30]
  let listCls = UdClass(name: "list", cached: true)
  listCls.len = proc (vm: VM, ud: Userdata): int = items.len
  listCls.index = proc (vm: VM, ud: Userdata, key: ScriptValue): ScriptValue =
    if key.kind == vkNumber and key.n >= 1 and key.n <= items.len.float64: vnum(items[int(key.n) - 1])
    elif key.kind == vkString and key.str.s == "name": vstr("items")
    else: NilValue
  listCls.newindex = proc (vm: VM, ud: Userdata, key, val: ScriptValue) =
    if key.kind != vkNumber: vm.runtimeError("list only takes numbers")
    items[int(key.n) - 1] = int(vm.checkNum([val], 0, "set"))
  listCls.next = proc (vm: VM, ud: Userdata, key: ScriptValue, k, v: var ScriptValue): bool =
    let i = if key.kind == vkNumber: int(key.n) else: 0
    if i >= items.len: return false
    k = vnum(i + 1)
    v = vnum(items[i])
    true
  listCls.call = proc (vm: VM, ud: Userdata, args: openArray[ScriptValue], ret: var RetVals) =
    var i = 0
    ret.setRet(vnative(newNative("it", proc (vm: VM, a: openArray[ScriptValue], r: var RetVals) =
      if i < items.len:
        r.setRet(vnum(items[i]))
        inc i
      else:
        r.setRet(NilValue))))
  listCls.tostr = proc (ud: Userdata): string = "list of " & $items.len
  var anchor = 7
  rawSet(base, vstr("LIST"), vud(Userdata(cls: listCls, key: addr anchor)))
  rawSet(base, vstr("LIST2"), vud(Userdata(cls: listCls, key: addr anchor)))
  expect("length and index", "return #LIST, LIST[2], LIST[9], LIST.name, tostring(LIST)",
         ["3", "20", "nil", "\"items\"", "\"list of 3\""])
  expect("ipairs and pairs", "local a, b = 0, 0 for i, v in ipairs(LIST) do a = a + i * v end for k, v in pairs(LIST) do b = b + v end return a, b",
         ["140", "60"])
  expect("calling iterates", "local s = 0 for v in LIST() do s = s + v end return s", ["60"])
  expect("writes", "LIST[1] = 5 return LIST[1]", ["5"])
  expectErr("class errors are script errors", "LIST.x = 1", "list only takes numbers")
  expect("same object, same value", "local t = {} t[LIST] = 1 return LIST == LIST2, t[LIST2], rawequal(LIST, LIST2)",
         ["true", "1", "true"])
  expect("metatable hidden", "return getmetatable(LIST)", ["false"])
  let plain = UdClass(name: "thing")
  rawSet(base, vstr("THING"), vud(Userdata(cls: plain, key: nil)))
  expectErr("no length", "return #THING", "length of a thing")
  expectErr("not callable", "return THING()", "call a thing")

# --------------------------------------------------------------- tables ----
block tables:
  let t = newScriptTable()
  t.add(vnum(1))
  t.add(vstr("two"))
  rawSet(t, vstr("k"), vbool(true))
  check(t.len == 2 and t.item(2).str.s == "two" and rawGetStr(t, "k").b and t.hashCount == 1,
        "table API: add / item / rawSet / hashCount")
  var n = 0
  for v in t: inc n
  check(n == 2 and t.entries.len == 3, "items and entries")
  let mt = newScriptTable()
  rawSet(mt, vstr("__index"), vtable(t))
  let child = newScriptTable()
  child.meta = mt
  rawSet(base, vstr("CHILD"), vtable(child))
  expect("metatables set from Nim", "return CHILD.k, CHILD[1]", ["true", "1"])
  var raised = false
  try: rawSet(t, NilValue, vnum(1))
  except ScriptError: raised = true
  check(raised, "a nil key is a ScriptError, not a Lua panic")

# ---------------------------------------------------------- performance ----
block perf:
  let t0 = cpuTime()
  let (vals, err) = runChunk("local function fib(n) if n < 2 then return n end return fib(n - 1) + fib(n - 2) end return fib(25)")
  let ms = (cpuTime() - t0) * 1000.0
  check(err.len == 0 and vals.len == 1 and vals[0].n == 75025.0, "fib(25)")
  echo "fib(25) in ", formatFloat(ms, ffDecimal, 1), " ms"

closeScriptVM()
echo passed, " passed, ", failures, " failed"
if failures > 0: quit(1)
