# Tests for the mod scripting runtime (src/modding/lua_bridge.nim over the
# vendored Lua 5.5).
#   nim r --mm:orc tests/test_mod_lua.nim
# Lua itself is tested upstream; these check what the bridge promises: the
# sandbox, per-mod isolation, the instruction budget and memory cap that no
# script can swallow, error positions, natives, userdata classes and the
# table API the mod modules use.

import std/[strutils, times, tables, os]
import ../src/modding/lua_bridge
import ../src/types
import ../src/game3d/[game_3d, engine_3d, player_3d]
import ../src/modding/[mod_hooks, mod_api, mod_3d, mod_assets, mod_world2d, mod_registry, mod_content_api, mod_ui,
                       mod_engine, mod_loader, mod_state]
import ../src/render_context, raylib
import ../src/modding/mod_catalog
import ../src/save_system, ../src/enemy_helpers, ../src/enemy, ../src/particle_pool, ../src/particle_types
import ../src/game/[things, combat]
import ../src/player, ../src/consumable, ../src/roguelite, ../src/patches, ../src/survival, ../src/powerup_data

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
  ok3("animation crossfade length",
      "local was = e.modelFade e.modelFade = 0.5 return math.abs(was - 0.2) < 1e-6, e.modelFade",
      ["true", "0.5"])
  check(world.entities[0].modelFade == 0.5, "modelFade reached the entity")
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
    beginModLoad(idx)
    let (_, err) = runIn(mods[idx].env, src)
    endModLoad()
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

# ------------------------------------------------- M0: foundations ----
# Library isolation, the load phase, mod events, per-entity data, spawn
# handles and mod.storage's profile folder.
block foundations:
  resetHooks()
  initModHooksVM(vm, base)
  installModApi(base)
  installMod3D(base)
  resetModContent()
  let libs = tableKeysOf(base)
  check("draw" in libs and "spawn" in libs and "hooks" in libs and "string" notin libs,
        "the game's libraries are listed for per-mod copies: " & $libs)

  proc addMod(id: string): ModRuntime =
    result = ModRuntime(id: id, name: id, version: "1.0.0", env: newModEnv(base, libs),
                        index: mods.len, runData: newScriptTable())
    mods.add(result)
    installModEnv(result)

  proc runAs(idx: int, src: string, loading = false): (seq[ScriptValue], string) =
    if loading: beginModLoad(idx) else: currentModIdx = idx
    result = runIn(mods[idx].env, src)
    if loading: endModLoad() else: currentModIdx = -1

  proc okAs(idx: int, name, src: string, expected: openArray[string], loading = false) =
    let (vals, err) = runAs(idx, src, loading)
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

  proc errAs(idx: int, name, src, fragment: string, loading = false) =
    let (_, err) = runAs(idx, src, loading)
    if err.len == 0 or fragment notin err:
      echo "FAIL ", name, ": expected an error containing '", fragment, "', got '", err.splitLines()[0], "'"
      inc failures
    else:
      inc passed

  let a = addMod("alpha")
  let b = addMod("beta")
  discard a
  discard b

  # ---- library isolation
  okAs(0, "a mod may replace a library function", "draw.circle = nil spawn.extra = 1 return draw.circle, spawn.extra", ["nil", "1"])
  okAs(1, "...without touching another mod's copy", "return type(draw.circle), spawn.extra", ["\"function\"", "nil"])

  # ---- register.* only while loading
  okAs(0, "register while loading", "return register.powerup{id = 'zap'}", ["\"alpha:zap\""], loading = true)
  errAs(0, "register from a hook or timer is refused", "register.powerup{id = 'late'}", "only works while the mod loads")
  errAs(0, "roster.add too", "roster.add('wave', 'etCube')", "only works while the mod loads")
  okAs(0, "override.* stays callable", "override.text('en', 'alpha_key', 'x') return 1", ["1"])

  # ---- mod events
  okAs(0, "handlers in order",
       "order = {} hooks.on('alpha:ping', function(n) order[#order + 1] = 'a' .. n end) " &
       "hooks.on('alpha:value', function(v, k) return v + k end) return 1", ["1"])
  okAs(1, "a second mod listens",
       "hooks.on('alpha:ping', function(n) hooks.emit('beta:heard', n) end) " &
       "hooks.on('alpha:value', function(v, k) return v * k end) " &
       "hooks.on('beta:heard', function(n) heard = n end) return 1", ["1"])
  okAs(0, "emit and filter", "hooks.emit('alpha:ping', 7) return order[1], hooks.filter('alpha:value', 2, 3)",
       ["\"a7\"", "15"])
  okAs(1, "the nested emit arrived", "return heard", ["7"])
  errAs(0, "event names need a colon", "hooks.emit('ping')", "<mod id>:<event>")
  okAs(0, "runaway recursion is capped",
       "hooks.on('alpha:loop', function() hooks.emit('alpha:loop') end) return pcall(hooks.emit, 'alpha:loop')", ["true"])
  check(mods[0].errorCount > 0, "the over-deep emit was reported as an error")
  okAs(0, "hooks.off", "local f = function() end hooks.on('alpha:x', f) hooks.off('alpha:x', f) return 1", ["1"])
  disableMod(1, "test")
  okAs(0, "a disabled mod's handlers are gone", "return hooks.filter('alpha:value', 2, 3)", ["5"])

  # ---- per-entity data and spawn handles
  resetHooks()
  installModApi(base)
  installMod3D(base)
  resetModContent()
  discard addMod("alpha")
  discard addMod("beta")
  let g = Game(player: Player(hp: 10, maxHp: 10), screenWidth: 1024, screenHeight: 768,
               nextEnemyId: 1, difficulty: 1.0, state: gsPlaying, mode: gmWaveBased)
  modBeginFrame(g)
  check(modCtx.game == g, "the run is published")
  okAs(0, "spawn.enemy returns a handle valid before it joins",
       "e = spawn.enemy('etCircle', 100, 50) e.data.mark = 'a' mods.export(e) return e:valid(), e.x, #game.enemies",
       ["true", "100", "0"])
  check(modPendingEnemies.len == 1 and modActions.len == 1 and modActions[0].kind == makJoinEnemy,
        "the spawn waits to join")
  okAs(1, "each mod has its own e.data", "local e = mods.get('alpha') return e.data.mark, (function() e.data.mark = 'b' return e.data.mark end)()",
       ["nil", "\"b\""])
  okAs(0, "...and the first one keeps its own", "return e.data.mark", ["\"a\""])
  okAs(0, "spawn.bullet returns a handle", "bl = spawn.bullet{x = 1, y = 2, vx = 0, vy = 10} bl.data.n = 3 return bl:valid(), bl.bulletId > 0",
       ["true", "true"])
  errAs(0, "e.data must be a table", "e.data = 5", "must be a table")
  # what game.nim's processModActions does with the joins
  for act in modActions:
    if act.kind == makJoinEnemy: g.enemies.add(act.target)
    if act.kind == makJoinBullet: g.bullets.add(act.bullet)
  modActions.setLen(0)
  modPendingEnemies.setLen(0)
  modPendingBullets.setLen(0)
  okAs(0, "joined", "return e:valid(), #game.enemies, #game.bullets", ["true", "1", "1"])
  captureRunData(g, false)
  check("@e:" notin g.modRunData, "a run save carries no entity data")
  captureRunData(g, true)
  check("@e:alpha" in g.modRunData and "@e:beta" in g.modRunData, "a snapshot carries every mod's entity data")
  let saved = g.modRunData
  # a resumed run (a new Game object, the same ids) gets it back
  let g2 = Game(player: Player(hp: 10, maxHp: 10), screenWidth: 1024, screenHeight: 768,
                nextEnemyId: 2, difficulty: 1.0, state: gsPlaying, mode: gmWaveBased,
                modRunData: saved, time: 10)
  g2.enemies = g.enemies
  g2.bullets = g.bullets
  modBeginFrame(g2)
  okAs(0, "entity data round-trips through the snapshot", "return game.enemies[1].data.mark, game.bullets[1].data.n",
       ["\"a\"", "3"])
  okAs(1, "for every mod", "return game.enemies[1].data.mark", ["\"b\""])
  let g3 = Game(player: Player(hp: 10, maxHp: 10), screenWidth: 1024, screenHeight: 768,
                nextEnemyId: 1, difficulty: 1.0, state: gsPlaying, mode: gmWaveBased)
  g3.enemies = g.enemies
  modBeginFrame(g3)
  okAs(0, "a fresh run starts without it", "return game.enemies[1].data.mark", ["nil"])

  # ---- PvP: no gameplay scripting
  modCtx.inPvP = true
  errAs(0, "spawns refuse in PvP", "spawn.enemy('etCircle', 0, 0)", "PvP")
  modCtx.inPvP = false

  # ---- mod.storage stays in the profile it was read from
  let home = getTempDir() / "tophat_test_home"
  putEnv("HOME", home)
  activeProfileSlot = 1
  let m = ModRuntime(id: "keeper", name: "keeper", version: "1", env: newModEnv(base, libs),
                     index: mods.len, runData: newScriptTable())
  mods.add(m)
  installModEnv(m)
  okAs(m.index, "storage write", "mod.storage.coins = 9 return 1", ["1"])
  activeProfileSlot = 2   # a profile switch reloads mods after this
  check(saveModStorage(m), "storage saved")
  check(fileExists(getProfileDir(1) / "mod_data" / "keeper.json") and
        not fileExists(getProfileDir(2) / "mod_data" / "keeper.json"),
        "storage written to the old profile's folder")
  activeProfileSlot = 1
  removeDir(home)
  modOutsideRun(false)
  resetHooks()

# ------------------------------------------- M1: things and projectiles ----
block things2d:
  resetHooks()
  initModHooksVM(vm, base)
  installModApi(base)
  installMod3D(base)
  installWorld2D(base)
  resetModContent()
  let libs = tableKeysOf(base)
  let m = ModRuntime(id: "necro", name: "necro", version: "1", env: newModEnv(base, libs),
                     index: 0, runData: newScriptTable())
  mods.add(m)
  installModEnv(m)

  proc run1(src: string, loading = false): (seq[ScriptValue], string) =
    if loading: beginModLoad(0) else: currentModIdx = 0
    result = runIn(m.env, src)
    if loading: endModLoad() else: currentModIdx = -1

  proc ok1(name, src: string, expected: openArray[string], loading = false) =
    let (vals, err) = run1(src, loading)
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

  proc err1(name, src, fragment: string, loading = false) =
    let (_, err) = run1(src, loading)
    if err.len == 0 or fragment notin err:
      echo "FAIL ", name, ": expected an error containing '", fragment, "', got '", err.splitLines()[0], "'"
      inc failures
    else:
      inc passed

  # ---- registration (strict tables)
  ok1("register.thing", "ALLY = register.thing{id = 'ally', team = 'player', motion = 'static', radius = 20, " &
      "contactDamage = 2, hp = 10, solid = true, weapon = {interval = 0.5, range = 200, damage = 3}} " &
      "BOLT = register.projectile{id = 'bolt', pierce = 2, onHit = function(b, e, d) return d * 2 end} " &
      "WALL = register.thing{id = 'wall', shape = 'rect', w = 40, h = 40, blocksBullets = true, hitByBullets = true, hp = 5} " &
      "return ALLY, BOLT", ["\"necro:ally\"", "\"necro:bolt\""], loading = true)
  err1("register.thing rejects unknown keys", "register.thing{id = 'x', colour = 'red'}", "unknown field 'colour'", loading = true)
  err1("register.thing checks enum names", "register.thing{id = 'y', team = 'blue'}", "unknown value 'blue'", loading = true)
  err1("weapon tables are strict", "register.thing{id = 'z', weapon = {rate = 1}}", "unknown field 'rate'", loading = true)
  err1("register.projectile is strict", "register.projectile{id = 'p', speed = 3}", "unknown field 'speed'", loading = true)
  err1("register.thing only while loading", "register.thing{id = 'late'}", "only works while the mod loads")
  check(thingKinds.len == 2 and projectileKinds.len == 1, "kinds registered")

  # ---- spawning
  let g = Game(player: Player(hp: 10, maxHp: 10, radius: 12, pos: newVector2f(500, 500)), screenWidth: 1024,
               screenHeight: 768, nextEnemyId: 1, difficulty: 1.0, state: gsPlaying, mode: gmWaveBased,
               particlePool: newParticlePool())
  modBeginFrame(g)
  ok1("spawn.thing returns a handle valid before it joins",
      "a = spawn.thing(ALLY, 100, 100, {tag = 'first'}) a.data.souls = 3 " &
      "return a:valid(), a.x, a.kind, a.tag, a.solid, a.hp, #game:things()",
      ["true", "100", "\"necro:ally\"", "\"first\"", "true", "10", "0"])
  err1("spawn.thing rejects unknown overrides", "spawn.thing(ALLY, 0, 0, {colour = 1})", "unknown field 'colour'")
  err1("spawn.thing needs a registered kind", "spawn.thing('necro:nope', 0, 0)", "no thing kind")
  err1("spawn.hazard is strict", "spawn.hazard{shape = 'circle', radius = 5}", "unknown field 'radius'")
  err1("thing.id is read-only", "a.id = 4", "read-only")
  ok1("spawn.hazard", "hz = spawn.hazard{shape = 'circle', x = 300, y = 300, r = 50, warn = 0.5, active = 0.2, damage = 4, hurts = 'enemies'} return hz.kind, hz.hazard.warn",
      ["\"@hazard\"", "0.5"])
  for act in modActions:
    if act.kind == makJoinThing: discard joinThing(g, act.thing, act.callback, act.owner)
  modActions.setLen(0)
  ok1("joined", "return #game:things(), #game:things('first'), #game:thingsNear(100, 100, 5), a:valid(), a.data.souls",
      ["2", "1", "1", "true", "3"])

  # ---- the join cap
  while g.modThings.len < MaxModThings - 1:
    g.modThings.add(ModThing(kind: "necro:ally", id: 100000 + g.modThings.len))
  ok1("one more fits", "spawn.thing(ALLY, 0, 0) return 1", ["1"])
  err1("the cap holds", "spawn.thing(ALLY, 0, 0)", "already holds")
  modActions.setLen(0)
  modPendingThings.setLen(0)
  g.modThings.setLen(2)

  # ---- simulation: a hazard telegraphs, then hurts; contact damage; turret fire
  let e = newEnemy(300, 300, 1.0, etCircle, g)
  e.hp = 50
  e.maxHp = 50
  g.enemies.add(e)
  var grid: SpatialGrid
  grid.rebuild(g.enemies, 96, -200, -200, 1224, 968)
  updateThings(g, 0.25, 0.25, grid, 40)
  check(e.hp == 50, "the hazard only warns at first")
  updateThings(g, 0.3, 0.3, grid, 40)
  check(e.hp < 50, "then it hurts: " & $e.hp)
  let afterHazard = e.hp
  for i in 0 ..< 3: updateThings(g, 0.1, 0.1, grid, 40)
  sweepThings(g)
  check(g.modThings.len == 1, "the spent hazard is gone")
  # the ally sits on the enemy: contact damage, and its turret fires a bullet
  g.modThings[0].pos = newVector2f(300, 300)
  updateThings(g, 0.3, 0.3, grid, 40)
  check(e.hp < afterHazard, "contact damage hit the enemy")
  check(g.bullets.len >= 1 and g.bullets[^1].fromPlayer, "the turret fired")
  # projectile routing
  ok1("bullet kinds", "b = spawn.bullet{x = 0, y = 0, kind = BOLT, fromPlayer = true} return b.modKind, b.modPierce",
      ["\"necro:bolt\"", "2"])
  let pb = modPendingBullets[^1]
  check(modBulletHit(pb, e, 5) == 10, "a kind's onHit routes the hit")
  err1("unknown bullet kind", "spawn.bullet{kind = 'nope:x'}", "no projectile kind")
  # thing methods
  ok1("damage, heal, kill", "local t = game:things('first')[1] local d = t:damage(4) local h = t:heal(1) " &
      "local hp = t.hp t:kill() return d, h, hp, t.dead, t:valid()", ["4", "1", "7", "true", "false"])
  ok1("explode hurts enemies", "local before = game.enemies[1].hp game:explode(300, 300, 40, 2) return game.enemies[1].hp < before", ["true"])
  modActions.setLen(0)
  modPendingBullets.setLen(0)
  modOutsideRun(false)
  resetHooks()

# --------------------------------------------- M2: statuses and hooks ----
block statuses:
  resetHooks()
  initModHooksVM(vm, base)
  installModApi(base)
  installMod3D(base)
  installWorld2D(base)
  installContentApi(base)
  resetModContent()
  let m = ModRuntime(id: "hex", name: "hex", version: "1", env: newModEnv(base, tableKeysOf(base)),
                     index: 0, runData: newScriptTable())
  mods.add(m)
  installModEnv(m)
  proc run2(src: string, loading = false): (seq[ScriptValue], string) =
    if loading: beginModLoad(0) else: currentModIdx = 0
    result = runIn(m.env, src)
    if loading: endModLoad() else: currentModIdx = -1
  proc ok2(name, src: string, expected: openArray[string], loading = false) =
    let (vals, err) = run2(src, loading)
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
  proc err2(name, src, fragment: string, loading = false) =
    let (_, err) = run2(src, loading)
    if err.len == 0 or fragment notin err:
      echo "FAIL ", name, ": expected an error containing '", fragment, "', got '", err.splitLines()[0], "'"
      inc failures
    else:
      inc passed

  ok2("register.status", "SOUL = register.status{id = 'soul', maxStacks = 3, duration = 2, tickInterval = 0.5, " &
      "modifiers = {speed = -0.2, damageTaken = 0.5, damageDealt = -0.25}, " &
      "onTick = function(t, stacks) ticks = (ticks or 0) + stacks end, onExpire = function(t) expired = true end} " &
      "applied = {} hooks.on('statusApplied', function(t, name, n) applied[#applied + 1] = name .. n end) return SOUL",
      ["\"hex:soul\""], loading = true)
  err2("register.status is strict", "register.status{id = 'x', stack = 2}", "unknown field 'stack'", loading = true)
  err2("modifiers are strict", "register.status{id = 'y', modifiers = {haste = 1}}", "unknown field 'haste'", loading = true)
  let p = newPlayer(500, 500)
  check(p.dashTime == DashDuration and p.dashRecharge == DashCooldownTime and dashBurstOf(p) == DashSpeedMult,
        "newPlayer sets the dash tunables")
  let g = Game(player: p, screenWidth: 1024, screenHeight: 768, nextEnemyId: 1, difficulty: 1.0,
               state: gsPlaying, mode: gmWaveBased, particlePool: newParticlePool())
  modBeginFrame(g)
  let e = newEnemy(100, 100, 1.0, etCircle, g)
  e.hp = 100
  e.maxHp = 100
  g.enemies.add(e)
  ok2("apply and stack", "local e = game.enemies[1] e:applyStatus(SOUL) e:applyStatus(SOUL, {stacks = 5}) " &
      "local s = e:status(SOUL) return s.stacks, s.remaining, applied[1], applied[2]",
      ["3", "2", "\"hex:soul1\"", "\"hex:soul3\""])
  check(abs(e.statusSpeed - -0.6) < 0.001 and abs(e.statusDamageTaken - 1.5) < 0.001, "modifiers summed: " & $e.statusSpeed)
  check(abs(enemyDamageDealtMult(e) - 0.25) < 0.001, "damage dealt modifier")
  let dealt = applyEnemyHpDamage(e, 10)
  check(abs(dealt - 25) < 0.01, "damage taken goes through the status: " & $dealt)
  tickModStatuses(e, 0.6)
  ok2("onTick ran", "return ticks", ["3"])
  tickModStatuses(e, 1.6)
  check(e.modStatuses.len == 0 and e.statusSpeed == 0, "the status expired")
  ok2("onExpire ran", "return expired", ["true"])
  ok2("built-in effects by name", "local e = game.enemies[1] e:applyStatus('slow', {magnitude = 0.5, duration = 2}) " &
      "e:applyStatus('fire', {magnitude = 2, duration = 1}) return e:status('slow').magnitude, e:status('fire').magnitude, e:status('poison')",
      ["0.5", "2", "nil"])
  err2("unknown status", "game.enemies[1]:applyStatus('soggy')", "unknown status 'soggy'")
  ok2("player statuses", "player:applyStatus(SOUL, {duration = 1}) return player:status(SOUL).stacks", ["1"])
  check(abs(calculateCombatStats(p).damage - p.damage * 0.75) < 0.001, "player damage dealt modifier")
  ok2("clearStatus", "player:clearStatus(SOUL) return player:status(SOUL)", ["nil"])

  # ---- difficulty.scale
  let hpBefore = difficultyEnemyHpMult()
  ok2("difficulty.scale", "difficulty.scale{enemyHp = 2, spawnPace = 1.5} return difficulty.get().enemyHp", ["2"])
  check(abs(difficultyEnemyHpMult() - hpBefore * 2) < 0.001, "the lever scales the profile's")
  err2("difficulty.scale is strict", "difficulty.scale{hp = 2}", "unknown field 'hp'")
  let g2 = Game(player: newPlayer(0, 0), state: gsPlaying, mode: gmWaveBased)
  modBeginFrame(g2)
  check(difficultyEnemyHpMult() == hpBefore, "a new run starts at 1")
  modBeginFrame(g)   # back to the first run (it counts as new again: fine for the rest)

  # ---- filters
  ok2("contact and bullet filters", "hooks.on('enemyContact', function(d, e, p) return d * 3 end) " &
      "hooks.on('bulletHitPlayer', function(d, b, p) return 0 end) return 1", ["1"])
  check(modEnemyContact(e, 2) == 6, "enemyContact filter")
  let eb = Bullet(damage: 4)
  check(modBulletHitPlayer(eb, 4) == 0, "bulletHitPlayer filter")
  # ---- a named cause of death
  g.player.hp = 1
  ok2("hurt with a cause", "return player:hurt(50, {cause = 'Lava'})", ["true"])
  check(g.deathCause == dcMod and g.deathSourceName == "Lava", "the death screen names the cause")
  err2("hurt options are strict", "player:hurt(1, {reason = 'x'})", "unknown field 'reason'")
  modOutsideRun(false)
  resetHooks()

# ------------------------------------------------ M3: content registries ----
block registries:
  resetHooks()
  initModHooksVM(vm, base)
  installModApi(base)
  installMod3D(base)
  installWorld2D(base)
  installContentApi(base)
  resetModContent()
  let home = getTempDir() / "tophat_test_home3"
  putEnv("HOME", home)
  activeProfileSlot = 1
  let m = ModRuntime(id: "kit", name: "kit", version: "1", env: newModEnv(base, tableKeysOf(base)),
                     index: 0, runData: newScriptTable())
  mods.add(m)
  installModEnv(m)
  proc run3(src: string, loading = false): (seq[ScriptValue], string) =
    if loading: beginModLoad(0) else: currentModIdx = 0
    result = runIn(m.env, src)
    if loading: endModLoad() else: currentModIdx = -1
  proc ok3(name, src: string, expected: openArray[string], loading = false) =
    let (vals, err) = run3(src, loading)
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
  proc err3(name, src, fragment: string, loading = false) =
    let (_, err) = run3(src, loading)
    if err.len == 0 or fragment notin err:
      echo "FAIL ", name, ": expected an error containing '", fragment, "', got '", err.splitLines()[0], "'"
      inc failures
    else:
      inc passed

  ok3("register everything",
      "MANA = register.consumable{id = 'mana', color = '#4080ff', weight = 1e6, stats = {damage = '+50%'}, " &
      "  onPickup = function(p, g, x, y) picked = x end} " &
      "CORE = register.shopItem{id = 'core', name = 'Spare Core', cost = 10, costMult = 2, maxBuys = 2, " &
      "  stats = {walls = 3}, onBuy = function(p, g, n) boughtN = n end} " &
      "WARD = register.patch{id = 'ward', name = 'Ward', weight = 1e6, stats = {maxHp = 2}, " &
      "  onInstall = function(p, g) installed = true end} " &
      "STORM = register.survivalEvent{id = 'storm', name = 'Storm', duration = 10, warmup = 0, " &
      "  reward = false, weights = {boot = 5}, onStart = function(ev, g) ev.data.n = 0 started = true end, " &
      "  update = function(ev, g, dt) ev.data.n = ev.data.n + 1 if ev.data.n >= 3 then return 'success' end end, " &
      "  onFinish = function(ev, g, ok) finished = ok end} " &
      "SLAYER = register.advancement{id = 'slayer', name = 'Slayer', goal = 3} " &
      "ZAP = register.powerup{id = 'zap', active = {cooldown = 4, activate = function(p, lvl, g) zapped = lvl end}} " &
      "return MANA, CORE, WARD, STORM, SLAYER",
      ["\"kit:mana\"", "\"kit:core\"", "\"kit:ward\"", "\"kit:storm\"", "\"kit:slayer\""], loading = true)
  err3("strict consumable", "register.consumable{id = 'x', wieght = 1}", "unknown field 'wieght'", loading = true)
  err3("stats DSL checks fields", "register.shopItem{id = 'y', stats = {bogus = 1}}", "not a number field", loading = true)
  err3("stats DSL checks values", "register.patch{id = 'z', stats = {damage = 'lots'}}", "is not a change", loading = true)
  err3("event reward names", "register.survivalEvent{id = 'w', reward = 'gold'}", "sctMinor", loading = true)

  let p = newPlayer(500, 500)
  p.damage = 2
  var g = Game(player: p, screenWidth: 1024, screenHeight: 768, nextEnemyId: 1, difficulty: 1.0,
               state: gsPlaying, mode: gmWaveBased, particlePool: newParticlePool(), currentWave: 5)
  modBeginFrame(g)

  # ---- consumables
  let c = newConsumable(10, 20, 1.0, gmWaveBased)
  check(c.consumableType == ctMod and c.modKey == "kit:mana", "a heavy mod consumable wins the drop roll")
  modConsumablePickup(g, c)
  check(abs(p.damage - 3) < 0.001, "its stats applied")
  ok3("its onPickup ran", "return picked", ["10"])
  ok3("spawn.consumable by name", "spawn.consumable(MANA, 1, 2) return 1", ["1"])
  check(modActions[^1].kind == makSpawnConsumable and modActions[^1].key == "kit:mana", "queued with its name")
  modActions.setLen(0)

  # ---- shop rows
  let rows = modShopRows(g)
  check(rows.len == 1 and shopItemDefs[rows[0]].key == "kit:core", "the mod row is offered")
  check(modShopCost(shopItemDefs[rows[0]], 1) == 20, "its own price curve")
  let walls = p.walls
  setModShopBought(g, "kit:core", 1)
  modShopBuyDone(g, rows[0], 1)
  check(p.walls == walls + 3 and modShopBoughtCount(g, "kit:core") == 1, "stats applied, purchase counted")
  ok3("onBuy ran", "return boughtN", ["1"])

  # ---- patches
  g.mode = gmRoguelite
  g.rogueliteRun = RogueliteRun(floorNumber: 1)
  let choices = rollPatchChoices(g.rogueliteRun, 3)
  check(choices.len == 3 and choices[0].relicType == rrtMod and choices[0].modKey == "kit:ward",
        "a heavy mod patch is drafted")
  let hp0 = p.maxHp
  check(installPatch(g, choices[0]), "installed")
  check(not installPatch(g, choices[0]), "only once")
  check(p.maxHp == hp0 + 2 and rrtMod in p.patches, "its stats applied and mirrored")
  check(patchName(choices[0]) == "Ward" and patchKbLabel(choices[0]).startsWith("KB-9"), "named by its registration")
  ok3("onInstall ran; hasPatch", "return installed, player:hasPatch(WARD), player:hasPatch('rrtOverclock')",
      ["true", "true", "false"])
  check(rollPatchChoices(g.rogueliteRun, 30).len == len(AllPatches), "an owned mod patch is not offered again")

  # ---- survival events
  g.mode = gmTimeSurvival
  g.survival = initSurvivalState()
  startSurvivalEvent(g, sekMod, "kit:storm")
  check(g.survival.event.kind == sekMod and g.survival.event.modKey == "kit:storm", "the mod event runs")
  check(survivalEventName(sekMod, "kit:storm") == "Storm", "named")
  ok3("onStart ran", "return started", ["true"])
  for i in 0 ..< 3: updateSurvivalEvent(g, 0.1)
  check(g.survival.event.kind == sekNone, "its update finished it")
  ok3("onFinish ran", "return finished", ["true"])

  # ---- achievements
  ok3("progress", "return advancements.progress('slayer', 2), advancements.get('slayer').unlocked", ["false", "false"])
  ok3("unlock", "return advancements.progress('slayer'), advancements.get('slayer').unlocked", ["true", "true"])
  check(advancementToasts.len == 1, "an unlock toast is queued")
  check(fileExists(getProfileDir(1) / "mod_data" / "@advancements.json"), "kept in the profile's mod_data")
  advancementToasts.setLen(0)
  err3("another mod's achievement", "advancements.progress('other:x')", "no achievement")

  # ---- [Q] abilities
  var zap: PowerUpType
  check(resolvePowerUpScriptName("kit:zap", zap) and powerUpDef(zap).inLegendaryPanel and
        powerUpDef(zap).activeCooldown == 4, "an active power-up is on the [Q] strip")
  g.mode = gmWaveBased
  p.powerUps.add(PowerUp(powerType: zap, level: 1))
  check(modActivateAbilities(g) and abilityCooldown(p, zap) == 4, "[Q] fired it; cooldown set")
  check(not modActivateAbilities(g), "not again while cooling down")
  ok3("activate ran", "return zapped", ["1"])
  modOutsideRun(false)
  resetHooks()
  removeDir(home)

# ------------------------------------------------------- M4: in-run UI ----
block inRunUi:
  resetHooks()
  initModHooksVM(vm, base)
  installModApi(base)
  installMod3D(base)
  installWorld2D(base)
  installContentApi(base)
  installModUi(base)
  resetModContent()
  let m = ModRuntime(id: "story", name: "story", version: "1", env: newModEnv(base, tableKeysOf(base)),
                     index: 0, runData: newScriptTable())
  mods.add(m)
  installModEnv(m)
  proc run4(src: string, loading = false): (seq[ScriptValue], string) =
    if loading: beginModLoad(0) else: currentModIdx = 0
    result = runIn(m.env, src)
    if loading: endModLoad() else: currentModIdx = -1
  proc ok4(name, src: string, expected: openArray[string], loading = false) =
    let (vals, err) = run4(src, loading)
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
  proc err4(name, src, fragment: string, loading = false) =
    let (_, err) = run4(src, loading)
    if err.len == 0 or fragment notin err:
      echo "FAIL ", name, ": expected an error containing '", fragment, "', got '", err.splitLines()[0], "'"
      inc failures
    else:
      inc passed

  ok4("register.hudCard / pauseAction",
      "register.hudCard{id = 'souls', title = 'SOULS', height = 30, draw = function(x, y, w, h) end} " &
      "register.pauseAction{id = 'skip', name = 'Skip intro', onClick = function(g) skipped = true end} return 1",
      ["1"], loading = true)
  err4("hudCard is strict", "register.hudCard{id = 'x', hieght = 3, draw = function() end}", "unknown field 'hieght'", loading = true)
  err4("hudCard needs draw", "register.hudCard{id = 'y'}", "needs draw", loading = true)
  check(hudCardDefs.len == 1 and livePauseActions().len == 1, "registered")
  runPauseAction(0)
  ok4("pause actions run", "return skipped", ["true"])
  ok4("the game's screens are there", "return type(ui.dialogue), type(ui.choose), type(ui.cutscene)",
      ["\"function\"", "\"function\"", "\"function\""])

  err4("ui.open needs a run", "ui.open{draw = function() end}", "no run in progress")
  let g = Game(player: newPlayer(100, 100), state: gsPlaying, mode: gmWaveBased, screenWidth: 1024, screenHeight: 768)
  modBeginFrame(g)
  err4("ui.open is strict", "ui.open{draw = function() end, pasue = false}", "unknown field 'pasue'")
  ok4("ui.open", "closed = 0 s = ui.open{draw = function(w, h) end, onClose = function() closed = closed + 1 end} " &
      "return s:isOpen(), ui.isOpen(s)", ["true", "true"])
  check(modUiPauses() and modUiHoldsInput(), "an open screen pauses and takes the input")
  check(modUiBack() and not modUiHoldsInput(), "Esc / B closes it")
  ok4("onClose ran", "return closed, s:isOpen()", ["1", "false"])
  ok4("a screen that lets the run go on", "t = ui.open{draw = function() end, pause = false, closeOnBack = false} return 1", ["1"])
  check(not modUiPauses() and modUiHoldsInput() and not modUiBack(), "not pausing; Esc does not close it")
  ok4("updates", "n = 0 u = ui.open{draw = function() end, update = function(dt) n = n + dt end, pause = false} return 1", ["1"])
  updateModUi(0.5)
  ok4("its update ran", "return n", ["0.5"])
  ok4("ui.closeAll", "ui.closeAll() return t:isOpen(), u:isOpen()", ["false", "false"])
  ok4("dialogue opens a screen", "d = ui.dialogue{lines = {{speaker = 'A', text = 'hi'}}, onDone = function() dd = true end} return d:isOpen()", ["true"])
  check(modModals.len == 1 and modModals[0].owner == 0, "as the mod that called it")
  check(modUiBack(), "skippable")
  ok4("onDone ran on skip", "return dd", ["true"])
  err4("dialogue needs lines", "ui.dialogue{}", "needs lines")
  err4("widgets only draw", "ui.button(0, 0, 10, 10, 'x')", "draws")
  ok4("toast", "ui.toast('hello') return 1", ["1"])
  check(g.pendingToasts == @["hello"], "a toast over the run")
  ok4("banner", "ui.banner('ROUND 2', 'Fight!') return 1", ["1"])
  check(modBanner.title == "ROUND 2" and modBanner.timer > 0, "a banner is up")
  ok4("a screen left open", "ui.open{draw = function() end} return 1", ["1"])
  let g2 = Game(player: newPlayer(100, 100), state: gsPlaying, mode: gmWaveBased)
  modBeginFrame(g2)
  check(modModals.len == 0, "a new run starts with no mod screens")
  modOutsideRun(false)
  resetHooks()

# --------------------------------------------------- M5: engine control ----
block engine:
  resetHooks()
  initModHooksVM(vm, base)
  installModApi(base)
  installMod3D(base)
  installWorld2D(base)
  installContentApi(base)
  installModUi(base)
  installModEngine(base)
  resetModContent()
  let m = ModRuntime(id: "eng", name: "eng", version: "1", env: newModEnv(base, tableKeysOf(base)),
                     index: 0, runData: newScriptTable())
  mods.add(m)
  installModEnv(m)
  proc run5(src: string, loading = false): (seq[ScriptValue], string) =
    if loading: beginModLoad(0) else: currentModIdx = 0
    result = runIn(m.env, src)
    if loading: endModLoad() else: currentModIdx = -1
  proc ok5(name, src: string, expected: openArray[string], loading = false) =
    let (vals, err) = run5(src, loading)
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
  proc err5(name, src, fragment: string, loading = false) =
    let (_, err) = run5(src, loading)
    if err.len == 0 or fragment notin err:
      echo "FAIL ", name, ": expected an error containing '", fragment, "', got '", err.splitLines()[0], "'"
      inc failures
    else:
      inc passed

  ok5("register.command", "register.command{name = 'Souls', help = 'Counts souls', " &
      "run = function(args) return {'souls: ' .. (args[1] or '0'), 'ok'} end} return 1", ["1"], loading = true)
  err5("command names are one word", "register.command{name = 'two words', run = function() end}", "one word", loading = true)
  var lines: seq[string]
  check(runModCommand("souls", @["7"], lines) and lines == @["souls: 7", "ok"], "the terminal runs it: " & $lines)
  check(not runModCommand("nope", @[], lines), "unknown words are not mods'")
  check(modCommandHelp().len == 1, "listed under help")

  err5("camera needs a run", "camera.zoom = 2", "needs a run")
  let g = Game(player: newPlayer(100, 100), state: gsPlaying, mode: gmWaveBased, screenWidth: 1024, screenHeight: 768)
  modBeginFrame(g)
  ok5("camera", "camera.zoom = 2 camera.follow(true) return camera.zoom, camera.following", ["2", "true"])
  updateModCamera(g, 0.016)
  check(g.modWorld.camZoom == 2 and g.modWorld.camCurX == 256 and g.modWorld.camCurY == 192,
        "following the player, clamped inside the arena: " & $g.modWorld.camCurX & "," & $g.modWorld.camCurY)
  ok5("zoom is clamped", "camera.zoom = 9 return camera.zoom", ["3"])
  setWorldView(0, 0, 1)
  setWorldCamera(2, 512, 384)
  let wp = worldToVirtual(Vector2(x: 512, y: 384))
  check(abs(wp.x - 512) < 0.01 and abs(wp.y - 384) < 0.01, "the camera's centre is the screen's")
  ok5("toWorld inverts toScreen", "local x, y = camera.toScreen(600, 400) local a, b = camera.toWorld(x, y) " &
      "return math.floor(a + 0.5), math.floor(b + 0.5)", ["600", "400"])
  clearWorldCamera()
  ok5("reset", "camera.reset() return camera.zoom", ["1"])
  ok5("time", "time.scale = 0.5 time.enemyScale = 0 return time.scale, time.enemyScale", ["0.5", "0"])
  check(modWorldTimeScale(g) == 0.5 and g.modWorld.enemyTimeSet, "the run's clocks")
  err5("time.scale is a number", "time.scale = 'fast'", "finite number")
  ok5("hitstop / slowmo", "time.hitstop(0.1) time.slowmo(1, 0.3, true) return 1", ["1"])
  check(g.dopamine.slowMotion.active and g.dopamine.slowMotion.hitStopTimer > 0, "the game's own time layers")
  check(ord(LastModPowerUp) - ord(FirstModPowerUp) + 1 == 256 and ord(LastModEnemy) - ord(FirstModEnemy) + 1 == 128,
        "256 mod power-ups and 128 mod enemies")
  modOutsideRun(false)
  resetHooks()

# ------------------------------------------------ M6: the 2D example mods ----
# mods-sdk/examples/necromancer, story_mode and chaos_engine load against the
# real API (story_mode's texture is stubbed: no GL context here) and play their
# parts through the engine's hook helpers. A fourth mod listens to the
# necromancer's events, as the example's comments invite.
block examples2d:
  resetHooks()
  initModHooksVM(vm, base)
  installModApi(base)
  installMod3D(base)
  installWorld2D(base)
  installContentApi(base)
  installModUi(base)
  installModEngine(base)
  resetModContent()
  let home = getTempDir() / "tophat_test_home6"
  putEnv("HOME", home)
  activeProfileSlot = 1
  resetAdvancementCache()
  const exampleSrc = [
    ("necromancer", staticRead("../mods-sdk/examples/necromancer/main.lua")),
    ("story_mode", staticRead("../mods-sdk/examples/story_mode/main.lua")),
    ("chaos_engine", staticRead("../mods-sdk/examples/chaos_engine/main.lua")),
    ("probe", "hooks.on('necromancer:raiseChance', function(c) return 1 end) " &
              "hooks.on('necromancer:raised', function(ally, e) raisedFrom = e.enemyType end) " &
              "function probe() return mods.get('necromancer').THRALL, raisedFrom end")]
  mods = @[]
  for i, (id, src) in exampleSrc:
    let m = ModRuntime(id: id, name: id, version: "1.0.0", env: newModEnv(base, tableKeysOf(base)),
                       index: i, runData: newScriptTable())
    mods.add(m)
    installModEnv(m)
    if id == "story_mode":
      discard runIn(m.env, "assets.texture = function(path) return {width = 48, height = 48} end")
    beginModLoad(i)
    let (_, err) = runIn(m.env, src)
    endModLoad()
    check(err.len == 0, id & " loads" & (if err.len > 0: ": " & err.splitLines()[0] else: ""))
  check(findStatus("necromancer:soulBurn") >= 0 and thingKinds.len == 1, "necromancer registers its status and thrall")
  check(modModes.len == 1 and modModes[0].key == "story_mode:story" and hudCardDefs.len == 1 and
        pauseActionDefs.len == 1, "story_mode registers its mode, HUD card and pause action")
  check(findShopItem("chaos_engine:stabilizer") >= 0 and findPatch("chaos_engine:entropy") >= 0 and
        findSurvivalEvent("chaos_engine:storm") >= 0 and findAdvancement("chaos_engine:survivor") >= 0 and
        findCommand("chaos") >= 0, "chaos_engine registers its shop item, patch, event, achievement and command")

  proc probe(): seq[string] =
    currentModIdx = 3
    let (vals, err) = runIn(mods[3].env, "return probe()")
    currentModIdx = -1
    if err.len > 0: return @[err]
    for v in vals: result.add(show(v))

  # a story run: the opening cutscene holds the run, then the dialogue, then the blessing draft
  let g = Game(player: newPlayer(500, 400), state: gsPlaying, mode: gmWaveBased, modMode: "story_mode:story",
               screenWidth: 1024, screenHeight: 768, nextEnemyId: 1, difficulty: 1.0,
               particlePool: newParticlePool())
  modBeginFrame(g)
  check(modModals.len == 1 and modUiHoldsInput() and modUiPauses(), "the story opens with a cutscene")
  check(modUiBack(), "Esc skips it")
  check(modModals.len == 1, "...into the dialogue")
  check(modUiBack(), "Esc skips the dialogue")
  check(modModals.len == 1 and not modUiBack(), "the blessing draft cannot be skipped")
  clearModModals()

  # necromancer: a burning enemy rises as a thrall when it dies
  let e = newEnemy(300, 300, 1.0, etCircle, g)
  g.enemies.add(e)
  check(applyModStatus(e, "necromancer:soulBurn", -1, 1, 3), "soul burn applies")
  modEnemyDeath(e, g)
  check(modPendingThings.len == 1 and modPendingThings[0].kind == "necromancer:thrall", "a thrall rises")
  let pr = probe()
  check(pr == @["\"necromancer:thrall\"", "\"etCircle\""], "other mods see the export and the event: " & $pr)
  currentModIdx = 0
  let (raised, rerr) = runIn(mods[0].env, "return run.data.raised, run.data.souls")
  currentModIdx = -1
  check(rerr.len == 0 and raised.len == 2 and show(raised[0]) == "1" and show(raised[1]) == "3",
        "run.data counts it: " & rerr)

  # chaos_engine: bosses get a camera punch
  let boss = newEnemy(500, 200, 1.0, etCircle, g)
  boss.isBoss = true
  modBossSpawn(boss, g)
  check(g.modWorld.camZoom == 1.5 and g.modWorld.camFollow and g.dopamine.slowMotion.active,
        "a boss arrives zoomed in, in slow motion")
  var lines: seq[string]
  check(runModCommand("chaos", @[], lines) and lines.len == 1 and "0 / 100" in lines[0], "the chaos command: " & $lines)
  modActions.setLen(0)
  modPendingThings.setLen(0)
  modOutsideRun(false)
  resetHooks()
  removeDir(home)

closeScriptVM()

# ------------------------------------------- M5: content packs (a reload) ----
# The real loader: a mod with no script, only content/*.json. (reloadMods makes
# its own VM: this block runs last.)
block contentPacks:
  let home = getTempDir() / "tophat_test_home5"
  putEnv("HOME", home)
  activeProfileSlot = 1
  let dir = modsRootDir() / "pack"
  createDir(dir / "content" / "items")
  writeFile(dir / "mod.json", "{\"id\": \"pack\", \"name\": \"Pack\", \"version\": \"1.0.0\"}")
  writeFile(dir / "content" / "items" / "a.json",
            "[{\"type\": \"powerup\", \"id\": \"grit\", \"name\": \"Grit\", \"stats\": {\"maxHp\": \"+2\"}}," &
            " {\"type\": \"shopItem\", \"id\": \"core\", \"cost\": 5, \"stats\": {\"walls\": 2}}," &
            " {\"type\": \"consumable\", \"id\": \"mana\", \"color\": \"#4080ff\", \"stats\": {\"damage\": \"+5%\"}}]")
  writeFile(dir / "content" / "b.json", "{\"type\": \"enemy\", \"id\": \"brute\", \"base\": \"etCube\", \"hp\": 9}")
  reloadMods(@["pack"])
  var st: ModStatus
  var msg = ""
  for mi in installedMods:
    if mi.id == "pack":
      st = mi.status
      msg = mi.message
  check(st == msLoaded, "a content-only mod loads: " & msg)
  var pt: PowerUpType
  check(resolvePowerUpScriptName("pack:grit", pt) and findShopItem("pack:core") >= 0 and
        findConsumable("pack:mana") >= 0, "its content registered")
  var et: EnemyType
  check(resolveEnemyName("pack:brute", et), "and its enemy")
  # a bad pack fails the mod, naming the file
  writeFile(dir / "content" / "c.json", "{\"type\": \"gizmo\", \"id\": \"x\"}")
  reloadMods(@["pack"])
  for mi in installedMods:
    if mi.id == "pack":
      st = mi.status
      msg = mi.message
  check(st == msError and "content/c.json" in msg and "unknown type" in msg, "a bad entry fails the mod: " & msg)
  check(findShopItem("pack:core") < 0, "leaving nothing behind")
  # the shipped content_pack example (JSON only, a roster entry included)
  copyDir(currentSourcePath().parentDir / ".." / "mods-sdk" / "examples" / "content_pack", modsRootDir() / "content_pack")
  reloadMods(@["content_pack"])
  for mi in installedMods:
    if mi.id == "content_pack":
      st = mi.status
      msg = mi.message
  check(st == msLoaded, "the content_pack example loads: " & msg)
  check(resolvePowerUpScriptName("content_pack:grit", pt) and resolvePowerUpScriptName("content_pack:overclock", pt) and
        findShopItem("content_pack:core") >= 0 and findConsumable("content_pack:mana") >= 0 and
        resolveEnemyName("content_pack:brute", et), "with all its content")
  check(rosterEntries.len == 1 and rosterEntries[0].et == et and rosterEntries[0].fromWave == 4,
        "and its brute in wave mode's roster")
  writeFile(dir / "content" / "c.json", "{\"type\": \"roster\", \"mode\": \"wave\", \"enemy\": \"brute\", \"often\": 1}")
  reloadMods(@["pack"])
  for mi in installedMods:
    if mi.id == "pack": msg = mi.message
  check("unknown field \"often\"" in msg, "roster entries are strict: " & msg)
  removeDir(home)
  closeScriptVM()

echo passed, " passed, ", failures, " failed"
if failures > 0: quit(1)
