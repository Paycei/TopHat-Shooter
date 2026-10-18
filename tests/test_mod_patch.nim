# Tests for mixins: the {.moddable.} pragma (src/modding/mod_patch_core.nim),
# the generated dispatchers (mod_mixin_bind) and the runtime (mod_mixin).
#   nim r --mm:orc tests/test_mod_patch.nim
# Every shape of proc in tests/mixin_fixture.nim is wrapped from Lua and
# called from Nim, the way the game calls its own procs.

import std/[strutils, times]
import ../src/modding/[lua_bridge, mod_hooks, mod_state]
import mixin_fixture
import ../src/modding/mod_mixin_bind
bindModdables(currentSourcePath())
bindCallables(currentSourcePath(), ["mixin_fixture.nim"])

var failures = 0
var passed = 0

proc check(cond: bool, name: string) =
  if cond: inc passed
  else:
    echo "FAIL ", name
    inc failures

let (vm, base) = newScriptVM()
initModHooksVM(vm, base)
rawSet(base, vstr("engine"), vtable(newScriptTable()))
installModMixin(base)
let m = ModRuntime(id: "t", name: "t", version: "1", env: newModEnv(base, tableKeysOf(base)),
                   index: 0, runData: newScriptTable())
mods.add(m)

proc run(src: string): (seq[ScriptValue], string) =
  currentModIdx = 0
  var r: RetVals
  try:
    let f = vm.loadChunk(src, "test/main.lua", m.env)
    let err = vm.protectedCall(vfunc(f), [], r)
    result = (r.toSeq, err)
  except ScriptError as e:
    result = (@[], e.msg)
  currentModIdx = -1

proc lua(src: string): string =
  ## Run a chunk; "" on success, else the error.
  run(src)[1]

proc luaNum(src: string): float64 =
  let (vals, err) = run(src)
  if err.len > 0:
    echo "  (error: ", err.splitLines()[0], ")"
    return -999
  if vals.len == 0 or vals[0].kind != vkNumber: return -998
  vals[0].n

proc errorLogged(fragment: string): bool =
  for l in modLog:
    if fragment in l.text: return true
  false

# ---- unwrapped: the original body, nothing else
check(plain(1) == 12 and plain(1, 5) == 15, "an unwrapped proc is itself")
check(not mixinActive("mixin_fixture.plain"), "no mixin, no flag")

# ---- engine.call
check(luaNum("return engine.call('mixin_fixture.plain', 3)") == 32, "engine.call fills in defaults")
check(luaNum("return engine.call('mixin_fixture.plain', 3, 5)") == 35, "engine.call with every argument")
check(luaNum("return engine.mixin_fixture.plain(4)") == 42, "engine.<module>.<proc>")
check("takes 1 to 2 arguments" in lua("engine.call('mixin_fixture.plain')"), "too few arguments")
check(luaNum("return engine.call('mixin_fixture.setOf')") == 1, "a set default")
check(luaNum("return engine.call('mixin_fixture.setOf', {'kA', 'kB'})") == 2, "a set from a list of names")

# ---- wrap: change the arguments and the result
check(lua("h1 = mixin.wrap('mixin_fixture.plain', function(orig, a, b) return orig(a + 1, b) * 2 end)") == "",
      "mixin.wrap")
check(mixinActive("mixin_fixture.plain"), "a wrap turns the flag on")
check(plain(1) == 44, "the game's own call goes through the wrap: " & $plain(1))
check(luaNum("return engine.call('mixin_fixture.plain', 1)") == 44, "...and so does engine.call")
check(lua("h2 = mixin.wrap('mixin_fixture.plain', function(orig, a, b) return orig(a, b) + 1 end, {priority = 10})") == "",
      "a second wrap")
check(plain(1) == 45, "higher priority runs outermost: " & $plain(1))
check(lua("assert(mixin.remove(h1))") == "" and plain(1) == 13, "mixin.remove takes one layer off")
check(lua("mixin.remove(h2)") == "" and plain(1) == 12 and not mixinActive("mixin_fixture.plain"),
      "and the last one turns the flag off")

# ---- before / after / replace
check(lua("hb = mixin.before('mixin_fixture.plain', function(a) if a == 0 then return -1 end end)") == "", "before")
check(plain(0) == -1 and plain(1) == 12, "before: a value cancels, nil carries on")
discard lua("mixin.remove(hb)")
check(lua("ha = mixin.after('mixin_fixture.fact', function(r, n) return r + 1 end)") == "", "after")
check(fact(3) == 16, "after, on a recursive proc (each level wrapped): " & $fact(3))
discard lua("mixin.remove(ha)")
check(lua("hr = mixin.replace('mixin_fixture.noArgs', function() return 8 end)") == "" and noArgs() == 8,
      "replace, no arguments")
discard lua("mixin.remove(hr)")

# ---- var parameters and borrowed proxies
check(lua("hv = mixin.wrap('mixin_fixture.scale', function(orig, stats, k) stats.rate = 9 saved = stats orig(stats, k * 2) end)") == "",
      "wrap a var parameter")
var s = Stats(damage: 1, rate: 1)
scale(s, 3)
check(s.damage == 6 and s.rate == 9, "writes reach the caller's variable: " & $s)
check("no longer exists" in lua("return saved.rate"), "a borrowed argument dies with its call")
discard lua("mixin.remove(hv)")
check(lua("hv = mixin.wrap('mixin_fixture.scale', function(orig, stats, k) orig({damage = 10, rate = 2}, k) end)") == "",
      "orig given a table for a var parameter")
scale(s, 2)
check(s.damage == 20 and s.rate == 2, "the table's values go into the caller's variable: " & $s)
discard lua("mixin.remove(hv)")

# ---- results that are objects
check(lua("hm = mixin.after('mixin_fixture.makeStats', function(r, d) r.rate = 5 return r end)") == "", "after an object result")
let ms = makeStats(2)
check(ms.damage == 2 and ms.rate == 5, "the result proxy was edited and returned: " & $ms)
discard lua("mixin.remove(hm)")
check(lua("hm = mixin.replace('mixin_fixture.makeStats', function(d) return {damage = d * 3} end)") == "", "replace with a table")
check(makeStats(2).damage == 6, "a table becomes the object")
discard lua("mixin.remove(hm)")

check(lua("ht = mixin.after('mixin_fixture.trio', function(r) r[2].damage = 9 return r end)") == "", "after an array result")
let tr = trio()
check(tr[0].damage == 0 and tr[1].damage == 9 and tr[2].damage == 2, "edited in place and returned: " & $tr)
discard lua("mixin.remove(ht)")

# ---- refs stay alive
check(lua("hk = mixin.wrap('mixin_fixture.boxed', function(orig, b) keep = b b.n = b.n + 1 return orig(b) end)") == "", "a ref argument")
check(boxed(Box(n: 1)) == 2, "edited through its proxy")
check(luaNum("return keep.n") == 2, "and kept alive after the call")
discard lua("mixin.remove(hk)")

# ---- openArray
check(lua("ho = mixin.wrap('mixin_fixture.total', function(orig, xs) xs[#xs + 1] = 100 return orig(xs) end)") == "", "an openArray")
check(total([1, 2]) == 103, "a table of its items, back as a list")
discard lua("mixin.remove(ho)")

# ---- func (no side effects) and void procs
check(lua("hp = mixin.wrap('mixin_fixture.pure', function(orig, a, b) return orig(a, b) * 10 end)") == "" and pure(1, 2) == 30,
      "a func can be wrapped")
discard lua("mixin.remove(hp)")
check(lua("hn = mixin.before('mixin_fixture.notice', function(msg) heard = msg end)") == "", "a void proc")
notice("hi")
check(luaNum("return #heard") == 2, "its arguments arrive")
discard lua("mixin.remove(hn)")

# ---- errors: a failing layer is skipped, the original runs once
modLog.setLen(0)
check(lua("he = mixin.wrap('mixin_fixture.plain', function(orig, a, b) error('boom') end)") == "", "a layer that errors")
check(plain(1) == 12 and errorLogged("boom"), "is logged and skipped")
discard lua("mixin.remove(he)")
counter = 0
check(lua("he = mixin.wrap('mixin_fixture.counted', function(orig) local r = orig() error('late') end)") == "", "erroring after orig")
check(counted() == 1 and counter == 1, "keeps the original's result without running it twice")
discard lua("mixin.remove(he)")

# ---- the original raising
check(lua("hx = mixin.wrap('mixin_fixture.raiser', function(orig, x) return orig(x) end)") == "", "wrap a proc that raises")
var raisedType = ""
try: discard raiser(-1)
except ValueError as e: raisedType = $e.name & ":" & e.msg
check(raisedType == "ValueError:negative", "its exception reaches the game's caller: " & raisedType)
check(raiser(4) == 4, "and it still works")
discard lua("mixin.remove(hx)")
check(lua("hx = mixin.wrap('mixin_fixture.raiser', function(orig, x) local ok = pcall(orig, x) if not ok then return 0 end return x end)") == "",
      "a layer that handles it")
check(raiser(-1) == 0, "swallows it")
discard lua("mixin.remove(hx)")

# ---- overloads, unsupported signatures, discovery
check("overloaded" in lua("mixin.wrap('mixin_fixture.name', function(o, x) return 'no' end)"), "an overload must be named")
check(lua("hs = mixin.wrap('mixin_fixture.name(string)', function(o, x) return 'w' .. o(x) end)") == "", "by its parameter types")
check(name("x") == "ws:x" and name(kB) == "k:kB", "only that overload is wrapped")
discard lua("mixin.remove(hs)")
check("cannot be wrapped" in lua("mixin.wrap('mixin_fixture.callback', function(o, f) end)"), "a proc parameter cannot be wrapped")
check(luaNum("local n = 0 for _, name in ipairs(mixin.list('mixin_fixture.')) do n = n + 1 end return n") >= 15,
      "mixin.list names them")
check("plain(a: int, b: int): int" in run("return mixin.signature('mixin_fixture.plain')")[0][0].str.s,
      "mixin.signature")

# ---- callable-only procs
check(luaNum("return engine.mixin_fixture.helper(2)") == 6 and luaNum("return engine.call('mixin_fixture.helper', 2, 5)") == 10,
      "a plain exported proc is callable")
check("not moddable" in lua("mixin.wrap('mixin_fixture.helper', function(o, x) end)"), "but cannot be wrapped")

# ---- teardown
discard lua("mixin.wrap('mixin_fixture.plain', function(orig, a, b) return 0 end)")
resetHooks()
check(plain(1) == 12 and not mixinActive("mixin_fixture.plain"), "a reload takes every mixin off")

# ---- the cost of an unwrapped call (one bool check)
block cost:
  var acc = 0
  let t0 = cpuTime()
  for i in 0 ..< 20_000_000: acc += plain(i and 7)
  let ms = (cpuTime() - t0) * 1000.0
  echo "20M unwrapped calls: ", formatFloat(ms, ffDecimal, 1), " ms (", acc mod 7, ")"

echo passed, " passed, ", failures, " failed"
if failures > 0: quit(1)
