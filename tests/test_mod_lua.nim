# Tests for the mod scripting runtime (src/modding/lua_bridge.nim over the
# vendored Lua 5.5).
#   nim r --mm:orc tests/test_mod_lua.nim
# Lua itself is tested upstream; these check what the bridge promises: the
# sandbox, per-mod isolation, the instruction budget and memory cap that no
# script can swallow, error positions, natives, userdata classes and the
# table API the mod modules use.

import std/[strutils, times, tables]
import ../src/modding/lua_bridge
import ../src/types
import ../src/game3d/[game_3d, engine_3d, player_3d]
import ../src/modding/[mod_hooks, mod_api, mod_3d, mod_assets]

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


# ------------------------------------------------------------- 3D worlds ----
# The script API of the 3D worlds (src/modding/mod_3d.nim), everything that
# runs without a window: wrappers, fields, the action queue, stale-world safety,
# hook arguments, draw3d's guards. Not covered (needs a GL context): actually
# rendering (draw3d.* drawing calls, override looks, labels on screen) and
# input-driven frames (updateGame3D).
block world3d:
  initModHooksVM(vm, base)
  installModApi(base)
  installMod3D(base)
  let env3 = newModEnv(base)

  proc run3(src: string): (seq[ScriptValue], string) =
    currentModIdx = 0
    result = runIn(env3, src)
    currentModIdx = -1

  proc ok3(name, src: string, expected: openArray[string]) =
    let (vals, err) = run3(src)
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

  proc err3(name, src, fragment: string) =
    let (_, err) = run3(src)
    if err.len == 0 or fragment notin err:
      echo "FAIL ", name, ": expected an error containing '", fragment, "', got '", err.splitLines()[0], "'"
      inc failures
    else:
      inc passed

  let world = initGame3D(World3DOptions(), Player(hp: 100, maxHp: 100))
  let hpMult = difficultyEnemyHpMult()
  let dmgMult = difficultyEnemyDamageMult()

  # ---- no world yet
  activeWorld3D = nil
  ok3("active() is false without a world", "return world3d.active()", ["false"])
  err3("spawn needs a world", "world3d.spawn{}", "needs an active 3D world")
  err3("world needs a world", "return world3d.world", "needs an active 3D world")
  err3("player needs a world", "return world3d.player", "needs an active 3D world")
  err3("enter needs a run", "world3d.enter{}", "needs a run in progress")
  err3("draw3d outside a draw hook", "draw3d.cube(0, 0, 0, 1, 1, 1, '#ffffff')", "only works inside world3dDraw")
  activeWorld3D = world
  modCtx.drawing = dtHud
  err3("draw3d in the 2D HUD hook", "draw3d.sphere(0, 0, 0, 1, '#ffffff')", "only works inside world3dDraw")
  modCtx.drawing = dtWorld3D
  err3("draw.* in a 3D draw hook", "draw.rect(0, 0, 1, 1, '#ffffff')", "draw3d library")
  err3("draw3d checks its numbers", "draw3d.cube('x', 0, 0, 1, 1, 1, '#ffffff')", "number expected")
  err3("draw3d checks its colour", "draw3d.sphere(0, 0, 0, 1, {})", "colour needs")
  err3("draw3d.model wants a model", "draw3d.model(5, 0, 0, 0)", "model expected")
  ok3("draw3d.text queues a label", "draw3d.text('hi', 1, 2, 3, 30, '#ff0000')", [])
  check(world3dLabels.len == 1 and world3dLabels[0].text == "hi" and world3dLabels[0].size == 30,
        "a label was queued")
  world3dLabels.setLen(0)
  modCtx.drawing = dtNone
  ok3("active() with a world", "return world3d.active()", ["true"])

  # ---- spawning goes through the queue
  world3dActions.setLen(0)
  ok3("spawn returns the entity at once",
      "e = world3d.spawn{tag = 'grunt', x = 10, y = 5, z = -3, hp = 50, ai = 'chase', speed = 12, radius = 2, color = '#ff0000'} " &
      "return e.tag, e.x, e.z, e.hp, e.maxHp, e.ai, e.shape, e.color.r, e:valid(), #world3d.entities()",
      ["\"grunt\"", "10", "-3", "50", "50", "\"chase\"", "\"sphere\"", "255", "true", "0"])
  check(world3dActions.len == 1, "the spawn waits in the queue")
  processWorld3DActions(world)
  check(world3dActions.len == 0 and world.entities.len == 1, "the queue applied it")
  check(abs(world.entities[0].hp - 50 * hpMult) < 0.01, "enemy HP got the profile difficulty once")
  ok3("entities lists it", "return #world3d.entities(), #world3d.entities('grunt'), #world3d.entities('nope'), world3d.entities()[1] == e",
      ["1", "1", "0", "true"])
  ok3("fields read and write",
      "e.x = 20 e.vz = 2 e.pos.y = 9 e.hp = 40 e.shape = 'cube' e.size = {x = 1, y = 2, z = 3} " &
      "return e.x, e.vz, e.y, e.pos.y, e.hp, e.shape, e.size.y, e.ai",
      ["20", "2", "9", "9", "40", "\"cube\"", "2", "\"chase\""])
  check(world.entities[0].pos.x == 20 and world.entities[0].vel.z == 2 and world.entities[0].shape == esCube,
        "writes reached the entity")
  err3("id is read-only", "e.id = 5", "read-only")
  err3("alive is read-only", "e.alive = false", "read-only")
  err3("unknown field read", "return e.bogus", "no field 'bogus'")
  err3("unknown field write", "e.bogus = 1", "no field 'bogus'")
  err3("bad ai name", "e.ai = 'zoom'", "unknown ai")
  err3("NaN is rejected", "e.x = 0/0", "must be a finite number")
  err3("spawn: unknown field", "world3d.spawn{bogus = 1}", "no settable field 'bogus'")
  err3("spawn: bad ai", "world3d.spawn{ai = 'zoom'}", "unknown ai")
  err3("spawn: id is fixed", "world3d.spawn{id = 3}", "cannot be set")
  ok3("methods",
      "e.hp = 40 local dealt = e:damage(15) return dealt, e.hp, e:distanceTo(20, 9, -3), e:distanceTo(e), #e:fields() > 10",
      ["15", "25", "0", "0", "true"])
  err3("damage needs a number", "e:damage('x')", "number expected")
  err3("method without self", "local f = e.kill f()", "call it with ':'")

  # ---- hooks see the wrappers; a dead entity is readable in its death hook
  ok3("death hook wrapper",
      "deaths = {} hooks.on('world3dEntityDeath', function(en) deaths[#deaths + 1] = en.tag .. ':' .. tostring(en.hp <= 0) .. ':' .. tostring(en:valid()) end) " &
      "e:kill() return deaths[1], e.tag, e:valid()",
      ["\"grunt:true:false\"", "\"grunt\"", "false"])
  check(world.kills == 1, "a kill counted")
  sweepDead(world)
  check(world.entities.len == 0, "the sweep dropped it")
  err3("removed entity read", "return e.tag", "entity no longer exists")
  err3("removed entity write", "e.x = 1", "entity no longer exists")
  err3("removed entity method", "e:kill()", "entity no longer exists")
  ok3("valid() still answers", "return e:valid()", ["false"])

  # ---- removal before it joined, projectiles and pickups
  ok3("remove a pending spawn", "q = world3d.spawn{tag = 'ghost'} q:remove() return q:valid()", ["false"])
  processWorld3DActions(world)
  check(world.entities.len == 0, "a removed pending entity never joined")
  ok3("projectile wrapper",
      "p = world3d.projectile{x = 1, vx = 5, damage = 7, fromPlayer = true, homing = true, pierce = 2, tag = 'bolt', radius = 2} " &
      "return p.damage, p.vx, p.x, p.pierce, p.tag, p.isHoming, p.homingStrength, p.fromPlayer, p.radius, #world3d.world.projectiles",
      ["7", "5", "1", "2", "\"bolt\"", "true", "200", "true", "2", "0"])
  processWorld3DActions(world)
  ok3("projectile joined", "return #world3d.world.projectiles, world3d.world.projectiles[1] == p", ["1", "true"])
  ok3("projectile write and remove", "p.damage = 9 p.vy = 3 local d = p.damage p:remove() return d, p:valid()", ["9", "false"])
  err3("removed projectile", "return p.damage", "projectile no longer exists")
  err3("projectile owner must be an entity", "world3d.projectile{owner = 5}", "must be an entity")
  err3("projectile typo", "world3d.projectile{dmg = 5}", "unknown field 'dmg'")
  sweepDead(world)
  ok3("pickup wrapper",
      "k = world3d.pickup{x = 1, y = 2, z = 3, kind = 'ammo', value = 10} return k.kind, k.value, k.x, k.z, #world3d.world.pickups",
      ["\"ammo\"", "10", "1", "3", "0"])
  processWorld3DActions(world)
  ok3("pickup joined", "k.y = 4 return #world3d.world.pickups, k.y, k:valid()", ["1", "4", "true"])
  err3("pickup id is read-only", "k.id = 1", "read-only")
  ok3("pickup remove", "k:remove() return k:valid()", ["false"])
  err3("removed pickup", "return k.kind", "pickup no longer exists")
  sweepDead(world)
  check(world.pickups.len == 0, "pickup swept")

  # ---- platforms and the arena
  ok3("platform (full extents in, half extents stored)",
      "local i = world3d.platform{x = 5, y = 1, w = 10, h = 2, d = 6, jumpPad = true} " &
      "local pl = world3d.world.arena.platforms[i] return i, pl.size.x, pl.size.y, pl.size.z, pl.jumpForce, pl.pos.x",
      ["1", "5", "1", "3", "800", "5"])
  err3("platform typo", "world3d.platform{width = 5}", "unknown field 'width'")
  ok3("arena bulk setter",
      "world3d.arena{radius = 200, sky = '#102030', gravity = -5, floorVisible = false, deathPlaneY = -9} " &
      "local a = world3d.world.arena return a.radius, a.boundsRadius, a.gravity, a.drawFloor, a.skyColor.g, a.deathPlaneY",
      ["200", "180", "-5", "false", "32", "-9"])
  ok3("arena theme rebuilds it", "world3d.arena{theme = 'space'} return #world3d.world.arena.platforms > 0, world3d.world.arena.radius",
      ["true", "200"])
  err3("arena bad theme", "world3d.arena{theme = 'lava'}", "must be one of")
  err3("arena typo", "world3d.arena{colour = 1}", "unknown field 'colour'")
  ok3("clearPlatforms", "world3d.clearPlatforms() return #world3d.world.arena.platforms", ["0"])

  # ---- world / player proxies
  ok3("world fields",
      "local w = world3d.world w.score = 5 w.rules.timeLimit = 30 w.camera.fovy = 90 world3d.player.pos.y = 30 world3d.player.weapon.damage = 40 " &
      "return w.score, w.rules.timeLimit, w.camera.fovy, world3d.player.pos.y, w.player.weapon.damage, w.rules.exitOnBossDeath, w.active, w.result, w.bossEnabled",
      ["5", "30", "90", "30", "40", "true", "true", "\"none\"", "false"])
  check(world.score == 5 and world.rules.timeLimit == 30 and world.camera.fovy == 90 and
        world.player.pos.y == 30 and world.player.weapon.damage == 40, "proxy writes reached the world")
  err3("world.active is read-only", "world3d.world.active = false", "read-only")
  err3("world.modeKey is read-only", "world3d.world.modeKey = 'x'", "read-only")
  err3("lists cannot be replaced", "world3d.world.entities = 1", "must be set from a list")
  err3("unknown world field", "return world3d.world.bogus", "no field 'bogus'")
  ok3("world:fields()", "return #world3d.world:fields() > 10", ["true"])
  ok3("the same world is the same value", "return world3d.world == world3d.world", ["true"])
  ok3("two more entities", "world3d.spawn{tag = 'a'} world3d.spawn{tag = 'b'} return 1", ["1"])
  processWorld3DActions(world)
  ok3("entity iterator", "local n = 0 for en in world3d.world.entities() do n = n + 1 end return n", ["2"])
  ok3("damagePlayer / healPlayer",
      "world3d.player.health = 50 local d = world3d.damagePlayer(10) local h = world3d.player.health world3d.healPlayer(3) return d, h, world3d.player.health",
      [show(vnum((10 * dmgMult).float64)), show(vnum((50 - 10 * dmgMult).float64)),
       show(vnum((53 - 10 * dmgMult).float64))])
  ok3("shake", "world3d.shake(0.5) return world3d.world.camera.shakeTime", ["0.5"])
  ok3("aim", "local x, y, z, dx, dy, dz = world3d.aim() return x, y, z, dx > 0.99", ["0", "-8.5", "0", "true"])   # the empty world starts on its solid floor
  err3("damagePlayer needs a number", "world3d.damagePlayer()", "number expected")

  # ---- raycast
  ok3("spawn a far target", "target = world3d.spawn{tag = 'far', x = 0, y = 0, z = 50, radius = 4} return 1", ["1"])
  processWorld3DActions(world)
  ok3("remove the entities at the origin",
      "for en in world3d.world.entities() do if en.tag ~= 'far' then en:remove() end end return #world3d.entities()", ["1"])
  sweepDead(world)
  ok3("raycast result",
      "local h = world3d.raycast(0, 0, 0, 0, 0, 1) return h.kind, math.floor(h.dist), h.entity == target, world3d.raycast(0, 0, 0, 0, 0, -1, 10).kind",
      ["\"entity\"", "46", "true", "\"none\""])
  err3("raycast direction", "world3d.raycast(0, 0, 0, 0, 0, 0)", "cannot be zero")

  # ---- ending the world
  world.pendingResult = w3None
  ok3("finish(true)", "world3d.finish(true)", [])
  check(world.pendingResult == w3Won, "finish(true) requests won")
  world.pendingResult = w3None
  ok3("finish('lost')", "world3d.finish('lost')", [])
  check(world.pendingResult == w3Lost, "finish('lost') requests lost")
  world.pendingResult = w3None
  ok3("exit", "world3d.exit()", [])
  check(world.pendingResult == w3Exit, "exit requests exit")
  world.pendingResult = w3None
  err3("finish argument", "world3d.finish(3)", "use true, false")

  # ---- hooks get wrappers as arguments
  ok3("world3dStart gets the world",
      "startScore = nil hooks.on('world3dStart', function(w, resumed) startScore = w.score .. tostring(resumed) end) return 1", ["1"])
  modWorld3DStart(world, true)
  ok3("world3dStart ran", "return startScore", ["\"5true\""])
  ok3("world3dHit filter",
      "hits = {} hooks.on('world3dHit', function(dmg, target, proj) hits[#hits + 1] = (type(target) == 'string' and target or target.tag) .. ':' .. (proj and proj.tag or '-') return dmg * 2 end) return 1", ["1"])
  let shot = newProjectile3D(vec3(0, 0, 0), vec3(0, 0, 0), 10, true)
  shot.tag = "arrow"
  check(modWorld3DHit(10, world.entities[0], "", shot) == 20, "the hit filter doubled the damage")
  check(modWorld3DHit(10, nil, "boss", nil) == 20, "the filter also takes 'boss'")
  ok3("hit hook arguments", "return hits[1], hits[2]", ["\"far:arrow\"", "\"boss:-\""])
  ok3("player damaged filter",
      "hooks.on('world3dPlayerDamaged', function(amount, source, en) seen = source .. ':' .. type(en) return amount * 0.5 end) return 1", ["1"])
  world.player.health = 100
  world.player.invulnTimer = 0
  let took = damagePlayer3D(world, 10, "trap")
  check(abs(took - 5 * dmgMult) < 0.001, "the damage filter halved it")
  ok3("player damaged arguments", "return seen", ["\"trap:nil\""])

  # ---- override targets
  ok3("3D override targets", "override.model('boss3d', nil) override.model('satellite3d', nil) override.texture('entity3d:grunt', nil) " &
      "override.model('projectile3d:player', nil) override.model('projectile3d:enemy', nil) override.model('pickup3d:health', nil) return 1", ["1"])
  check(entity3dTex.hasKey("grunt") and pickup3dTex.hasKey("health"), "overrides have slots")
  err3("bad projectile target", "override.model('projectile3d:both', nil)", "use projectile3d:player or projectile3d:enemy")
  err3("entity target needs a tag", "override.model('entity3d:', nil)", "needs the entity's tag")
  err3("unknown target lists the 3D ones", "override.model('bogus', nil)", "boss3d, satellite3d, entity3d:<tag>")

  # ---- a world with a boss
  let bossWorld = initGame3D(World3DOptions(bossEnabled: true, bossId: 7), Player(hp: 100, maxHp: 100))
  activeWorld3D = bossWorld
  ok3("boss snapshot", "local b = world3d.boss() return b.phase, b.health > 1000, #b.satellites", ["1", "true", "4"])
  err3("boss HP is read-only", "world3d.world.boss.health = 5", "read-only")
  ok3("satellites are writable", "world3d.world.boss.satellites[1].health = 9 return world3d.world.boss.satellites[1].health", ["9"])
  let before = bossWorld.boss.health
  ok3("damageBoss", "return world3d.damageBoss(100)", ["true"])
  check(abs(before - bossWorld.boss.health - 100) < 0.01, "damageBoss hurt the core")
  activeWorld3D = world
  ok3("no boss: snapshot is nil", "return world3d.boss(), world3d.damageBoss(5)", ["nil", "false"])

  # ---- stale wrappers after the world ends
  ok3("hold wrappers", "heldWorld = world3d.world heldPlayer = world3d.player heldEntity = world3d.spawn{tag = 'held'} " &
      "return heldWorld.score", ["5"])
  processWorld3DActions(world)
  ok3("hold an entity from a list", "held2 = world3d.world.entities[1] return held2.tag", ["\"far\""])
  activeWorld3D = nil
  err3("stale world", "return heldWorld.score", "no longer exists")
  err3("stale world write", "heldWorld.score = 1", "no longer exists")
  err3("stale player proxy", "return heldPlayer.health", "no longer exists")
  err3("stale entity", "return heldEntity.tag", "entity no longer exists")
  err3("stale entity (from a list)", "return held2.tag", "entity no longer exists")
  ok3("stale valid()", "return heldEntity:valid(), world3d.active()", ["false", "false"])
  err3("stale spawn", "world3d.spawn{}", "needs an active 3D world")

  resetHooks()

# ------------------------------------------------- the 3D example mods ----
# mods-sdk/examples/arena_3d and orbital_tweaks: both main.lua files must
# compile, load against the real API, and (driving the engine's hook helpers and
# action queue by hand, no window) play their parts. Drawing hooks need a GL
# context and are not run.
block examples3d:
  const arenaSrc = staticRead("../mods-sdk/examples/arena_3d/main.lua")
  const orbitalSrc = staticRead("../mods-sdk/examples/orbital_tweaks/main.lua")
  for (name, src) in [("arena_3d", arenaSrc), ("orbital_tweaks", orbitalSrc)]:
    try:
      discard vm.loadChunk(src, name & "/main.lua", newModEnv(base))
      inc passed
    except ScriptError as e:
      echo "FAIL ", name, " does not compile: ", e.msg.splitLines()[0]
      inc failures

  proc makeMods() =
    ## Two mods with the environment the loader gives them (mod, run, require).
    mods = @[]
    for (i, id) in [(0, "arena_3d"), (1, "orbital_tweaks")]:
      let m = ModRuntime(id: id, name: id, version: "1.0.0", env: newModEnv(base), index: i)
      mods.add(m)
      installModEnv(m)

  proc load(idx: int, src: string) =
    currentModIdx = idx
    let (_, err) = runIn(mods[idx].env, src)
    currentModIdx = -1
    check(err.len == 0, "example main chunk " & $idx & " loads" & (if err.len > 0: ": " & err.splitLines()[0] else: ""))

  proc tick(w: Game3D, dt: float32 = 0.05) =
    w.timeElapsed += dt
    modWorld3DUpdate(w, dt)
    processWorld3DActions(w)
    sweepDead(w)

  resetHooks()
  makeMods()
  load(0, arenaSrc)
  check(modModes.len == 1 and modModes[0].threeD and modModes[0].key == "arena_3d:cube_siege", "Cube Siege registers a 3d mode")

  var w = initGame3D(World3DOptions(modeKey: "arena_3d:cube_siege"), Player(hp: 100, maxHp: 100))
  activeWorld3D = w
  world3dActions.setLen(0)
  modWorld3DStart(w, false)
  processWorld3DActions(w)
  check(w.arena.platforms.len == 7 and w.arena.platforms[6].jumpPad, "Cube Siege builds its arena")
  check(w.player.weapon.pellets == 8 and w.player.weapon.maxAmmo == 24, "Cube Siege tunes the shotgun")
  var sawTurret, sawOrbiter, sawBrute, sawPickup = false
  var safety = 0
  while w.pendingResult == w3None and safety < 4000:
    inc safety
    tick(w)
    for e in w.entities:
      if e.tag == "turret": sawTurret = true
      if e.tag == "orbiter": sawOrbiter = true
      if e.tag == "brute": sawBrute = true
    for e in w.entities:
      if e.alive: killEntity3D(w, e)
    if w.pickups.len > 0: sawPickup = true
  check(sawTurret and sawOrbiter and sawBrute, "waves mix chase, orbit, turret and brute entities")
  check(sawPickup, "kills drop pickups")
  check(w.pendingResult == w3Won and w.wave == 6, "six cleared waves win the world (wave " & $w.wave & ")")
  let over = newPickup3D(w, vec3(0, 0, 0), "overcharge", 8)
  check(modWorld3DPickup(over), "the overcharge pickup is taken by the script")
  check(abs(w.player.weapon.damage - 24) < 0.01, "overcharge doubles the pellet damage")
  check(not modWorld3DPickup(newPickup3D(w, vec3(0, 0, 0), "health", 20)), "health keeps its built-in effect")
  # a resumed run continues at its wave
  check(mods[0].runData != nil and rawGetStr(mods[0].runData, "wave").kind == vkNumber, "run.data carries the wave")
  var w2 = initGame3D(World3DOptions(modeKey: "arena_3d:cube_siege", resumed: true), Player(hp: 100, maxHp: 100))
  activeWorld3D = w2
  modWorld3DStart(w2, true)
  check(w2.wave == 5, "a resumed run restarts its wave (wave " & $w2.wave & ")")
  # another mode's world is left alone
  var w3 = initGame3D(World3DOptions(modeKey: "other:mode"), Player(hp: 100, maxHp: 100))
  activeWorld3D = w3
  modWorld3DStart(w3, false)
  check(w3.arena.platforms.len == 0, "Cube Siege ignores other worlds")

  # orbital_tweaks on the vanilla boss-7 world
  resetHooks()
  makeMods()
  load(1, orbitalSrc)
  var wb = initGame3D(World3DOptions(bossEnabled: true, bossId: 7), Player(hp: 100, maxHp: 100))
  activeWorld3D = wb
  world3dActions.setLen(0)
  modWorld3DStart(wb, false)
  processWorld3DActions(wb)
  check(wb.entities.len == 4 and wb.entities[0].tag == "drone" and wb.entities[0].ai == aiOrbit, "four orbiting drones join the boss fight")
  let bolt = newProjectile3D(vec3(0, 0, 0), vec3(0, 0, 0), 10, true)
  check(abs(modWorld3DHit(10, nil, "satellite", bolt) - 15) < 0.01, "satellites take bonus damage")
  check(abs(modWorld3DHit(10, nil, "boss", bolt) - 10) < 0.01, "the core does not")
  modWorld3DBossPhase(2)
  processWorld3DActions(wb)
  check(wb.entities.len == 6, "phase 2 sends two more drones")
  wb.player.health = 50
  killEntity3D(wb, wb.entities[0])
  check(wb.player.health == 55, "a drone kill heals 5")
  check(mods[0].errorCount == 0 and mods[1].errorCount == 0, "no hook of either example raised an error")
  activeWorld3D = nil
  resetHooks()
  mods.setLen(0)

# ------------------------------------------------ 3D solid floor (arena) ----
block solidFloor3d:
  initModHooksVM(vm, base)
  installModApi(base)
  installMod3D(base)
  let envF = newModEnv(base)
  proc runF(src: string): string =
    currentModIdx = 0
    let (_, err) = runIn(envF, src)
    currentModIdx = -1
    err

  let ew = initGame3D(World3DOptions(), Player(hp: 100, maxHp: 100))
  check(ew.arena.solidFloor and ew.arena.floorY == -9.5'f32, "the empty arena has a solid floor at the drawn floor's top")
  check(ew.spawnPos.y > ew.arena.floorY and ew.player.pos.y > ew.arena.floorY, "the mod world spawns above the floor")
  check(not generateArena("space", 500).solidFloor and not generateArena("default", 500).solidFloor,
        "vanilla themes stay without a solid floor")
  let bw = initGame3D(World3DOptions(bossEnabled: true, bossId: 7), Player(hp: 100, maxHp: 100))
  check(not bw.arena.solidFloor and bw.player.pos.y == 15, "the boss arena is unchanged")

  # The player stands on it (no keys pressed: only gravity acts)
  for i in 0 ..< 240:
    discard updatePlayer(ew.player, ew.camera, ew.arena, 1.0'f32 / 60)
  check(abs(ew.player.pos.y - (ew.arena.floorY + 1.0'f32)) < 0.001 and ew.player.grounded and ew.player.vel.y == 0,
        "the player stands on the solid floor after 4 s")
  # ... and does not without it
  var hole = generateArena("empty", 500)
  hole.solidFloor = false
  var pl = newPlayer3D(vec3(0, 0, 0), 100)
  var fell = false
  for i in 0 ..< 240:
    if updatePlayer(pl, ew.camera, hole, 1.0'f32 / 60): fell = true
  check(fell, "without a solid floor the player falls through the death plane")

  # Raycast
  activeWorld3D = ew
  let hit = raycast3D(ew, vec3(0, 10, 0), vec3(0, -1, 0), 100)
  check(hit.kind == "floor" and abs(hit.dist - 19.5'f32) < 0.01, "a ray down hits the floor")
  check(raycast3D(ew, vec3(0, 10, 0), vec3(0, 1, 0), 100).kind == "none", "a ray up misses it")

  # Lua: setter, deep fields, ray kind
  check(runF("world3d.arena{solidFloor = false, floorY = 5}").len == 0, "arena{solidFloor, floorY} is accepted")
  check(not ew.arena.solidFloor and ew.arena.floorY == 5, "the setter wrote both fields")
  check(runF("world3d.arena{theme = 'empty'}").len == 0 and ew.arena.solidFloor and ew.arena.floorY == -9.5'f32,
        "a theme resets to that theme's floor")
  check(runF("world3d.arena{solidFloor = true, floorY = 0}").len == 0 and ew.arena.solidFloor and ew.arena.floorY == 0,
        "the setter turns it back on")
  var got: seq[string]
  block:
    currentModIdx = 0
    let (vals, err) = runIn(envF, "a = world3d.world.arena a.floorY = 2 return a.solidFloor, a.floorY, world3d.raycast(0, 10, 0, 0, -1, 0).kind")
    currentModIdx = -1
    check(err.len == 0, "deep proxy runs: " & err)
    for v in vals: got.add(show(v))
  check(got == @["true", "2", "\"floor\""] and ew.arena.floorY == 2, "arena.solidFloor/floorY through the deep proxy, raycast kind 'floor': " & $got)
  activeWorld3D = nil

closeScriptVM()
echo passed, " passed, ", failures, " failed"
if failures > 0: quit(1)
