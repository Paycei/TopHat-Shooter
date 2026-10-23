# Tests for the mod scripting runtime (src/modding/lua_bridge.nim over the
# vendored Lua 5.5).
#   nim r --mm:orc tests/test_mod_lua.nim
# Lua itself is tested upstream; these check what the bridge promises: the
# whole standard library (minus native modules), per-mod globals, the
# watchdog that no script can outlive, error positions, natives, userdata
# classes and the table API the mod modules use.

import std/[strutils, tables, os]
import ../src/modding/lua_bridge
import ../src/types, ../src/localization
import ../src/game3d/[game_3d, engine_3d, player_3d]
import ../src/modding/[mod_hooks, mod_api, mod_3d, mod_assets, mod_world2d, mod_registry, mod_content_api, mod_ui,
                       mod_engine, mod_loader, mod_state]
import ../src/render_context, raylib
import ../src/modding/[mod_catalog, mod_deep]
import ../src/save_system, ../src/enemy_helpers, ../src/enemy, ../src/particle_pool, ../src/particle_types
import ../src/game/[things, combat]
import ../src/player, ../src/consumable, ../src/roguelite, ../src/patches, ../src/survival, ../src/powerup_data
import ../src/powerup
import ../src/modding/[mod_mixin_bind, mod_rl]
import mixin_bind_game   # binds the game's {.moddable.} procs imported above

var failures = 0
var passed = 0

# The example mods live in the mod registry (github.com/Paycei/TopHat-Shooter-ModRoot,
# its examples/ folder): read from a checkout of it next to this repository, or
# wherever TOPHAT_EXAMPLES points. Without one, their checks are skipped.
let examplesDir = getEnv("TOPHAT_EXAMPLES",
                         currentSourcePath().parentDir / ".." / ".." / "TopHat-Shooter-ModRoot" / "examples")
let haveExamples = dirExists(examplesDir)
if not haveExamples:
  echo "SKIP the example mods: no checkout of the mod registry at ", examplesDir

let (vm, base) = newScriptVM()
var printed: seq[string]
vm.printSink = proc (s: string) = printed.add(s)

proc check(cond: bool, name: string) =
  if cond: inc passed
  else:
    echo "FAIL ", name
    inc failures

proc show(v: ScriptValue): string =
  if v.kind == vkString: "\"" & v.str.s & "\"" else: vm.tostr(v)

proc shown(vals: seq[ScriptValue]): seq[string] =
  for v in vals: result.add(show(v))

proc runIn(env: ScriptTable, src: string): (seq[ScriptValue], string) =
  var r: RetVals
  try:
    let f = vm.loadChunk(src, "test/main.lua", env)
    let err = vm.protectedCall(vfunc(f), [], r)
    (r.toSeq, err)
  except ScriptError as e:
    (@[], e.msg)

type Ctx = object
  ## Where a chunk runs: `env` (nil: a fresh environment per chunk) as mod `idx`.
  env: ScriptTable
  idx: int

let bare = Ctx(env: nil, idx: -1)

proc run(c: Ctx, src: string, loading = false, safe = false): (seq[ScriptValue], string) =
  ## `loading` runs it as the mod's main chunk, `safe` at a safe point.
  let env = if c.env == nil: newModEnv(base) else: c.env
  if loading: beginModLoad(c.idx) else: currentModIdx = c.idx
  scriptSafe = safe
  result = runIn(env, src)
  scriptSafe = false
  if loading: endModLoad() else: currentModIdx = -1

proc ok(c: Ctx, name, src: string, expected: openArray[string], loading = false, safe = false) =
  let (vals, err) = c.run(src, loading, safe)
  if err.len > 0:
    check(false, name & ": error " & err.splitLines()[0])
  else:
    let got = shown(vals)
    check(got == @expected, name & (if got == @expected: "" else: "\n  expected " & $(@expected) & "\n  got      " & $got))

proc bad(c: Ctx, name, src, fragment: string, loading = false, safe = false) =
  let (_, err) = c.run(src, loading, safe)
  check(err.len > 0 and fragment in err,
        name & ": expected an error containing '" & fragment & "', got '" &
        (if err.len > 0: err.splitLines()[0] else: "") & "'")

proc addMod(id: string, dir = ""): Ctx =
  ## A mod with the environment the loader gives it (mod, run, require).
  let m = ModRuntime(id: id, name: id, version: "1.0.0", env: newModEnv(base, tableKeysOf(base)),
                     dir: dir, index: mods.len, runData: newScriptTable())
  mods.add(m)
  installModEnv(m)
  Ctx(env: m.env, idx: m.index)

proc freshApi(extra: openArray[proc (base: ScriptTable) {.nimcall.}] = []) =
  ## A clean slate of hooks and content, the base API plus `extra` installers.
  resetHooks()
  initModHooksVM(vm, base)
  installModApi(base)
  installMod3D(base)
  for install in extra: install(base)
  resetModContent()

proc tempHome(name: string): string =
  ## A fresh data root (a run that crashed must not leave its state to the next).
  result = getTempDir() / name
  removeDir(result)
  putEnv("HOME", result)
  putEnv("APPDATA", result)   # what getRootDataPath reads on Windows
  activeProfileSlot = 1

proc newRun(): Game =
  ## A bare run, seated as newGame seats one (`players` holds its player).
  let p = newPlayer(500, 500)
  Game(player: p, players: @[p], screenWidth: 1024, screenHeight: 768, nextEnemyId: 1,
       difficulty: 1.0, state: gsPlaying, mode: gmWaveBased, particlePool: newParticlePool())

# ------------------------------------------------------------- language ----
bare.ok("5.1 names and extras", "return unpack({1, 2}), math.pow(2, 3), math.clamp(9, 0, 5), math.round(-2.5), math.sign(-3), #string.split('a,,b', ','), ('  x  '):trim()",
        ["1", "8", "5", "-3", "-1", "3", "\"x\""])
bare.bad("NaN keys stay errors (Lua keeps IEEE math even in fast-math builds)",
         "local t = {} t[0/0] = 1", "NaN")
bare.ok("print goes to the log", "print('a', 1, nil, true, 2.5) return 1", ["1"])
check(printed.len > 0 and printed[^1] == "a\t1\tnil\ttrue\t2.5", "print output: " & $printed)

# ---------------------------------------------------------------- trust ----
bare.ok("the whole standard library",
        "return type(io.open), type(os.time), type(debug.traceback), type(package.loaded), type(load), " &
        "type(loadfile), type(dofile), type(string.dump), type(require), type(warn)",
        ["\"function\"", "\"function\"", "\"function\"", "\"table\"", "\"function\"",
         "\"function\"", "\"function\"", "\"function\"", "\"function\"", "\"function\""])
bare.ok("no native modules", "local f, msg, where = package.loadlib('x.dll', 'f') " &
        "return f, where, msg:find('dynamic libraries not enabled', 1, true) ~= nil, package.cpath, #package.searchers",
        ["nil", "\"absent\"", "true", "\"\"", "2"])
bare.ok("open metatables", "return type(getmetatable(_ENV).__index), getmetatable('').__index == getmetatable(_ENV).__index.string",
        ["\"table\"", "true"])
bare.ok("bytecode round-trips", "local f = load(string.dump(function(a) return a * 3 end)) return f(4)", ["12"])
block files:
  # Outside a mod's own code no file opens (the sandbox, see "files" below).
  let p = (getTempDir() / "tophat_lua_io_test.txt").replace('\\', '/')
  bare.ok("no file opens outside a mod's code",
          "local f, err = io.open('" & p & "', 'w') return f, err:find('denied', 1, true) ~= nil, " &
          "(loadfile('" & p & "')), (os.remove('" & p & "'))",
          ["nil", "true", "nil", "nil"])
  check(not fileExists(p), "nothing was written")
bare.ok("os.date takes C99 formats everywhere", "return os.date('!%F %T', 0)", ["\"1970-01-01 00:00:00\""])
bare.bad("the number locale stays C", "os.setlocale('de_DE')", "C number format")
bare.bad("os.exit unwinds the script", "os.exit(3) return 1", QuitSentinel)
check(modQuitRequested and modQuitCode == 3, "os.exit asks the game to close, with its code")
modQuitRequested = false
modQuitCode = 0
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

# ------------------------------------------------------------- watchdog ----
setWatchdogLimits(call = 0.2)
bare.bad("endless loop", "while true do end", "watchdog")
bare.bad("not through pcall", "while true do pcall(function() while true do end end) end", "watchdog")
bare.bad("not through coroutines",
         "local co = coroutine.create(function() while true do end end) while true do coroutine.resume(co) end",
         "watchdog")
discard bare.run("debug.sethook()")   # a mod taking the hook off...
bare.bad("...gets it back on its next call", "while true do end", "watchdog")
setWatchdogLimits()
bare.bad("deep recursion", "local function f(n) return 1 + f(n + 1) end return f(1)", "stack overflow")
bare.bad("deep nesting", "return " & "(".repeat(400) & "1" & ")".repeat(400), "")
bare.ok("still healthy afterwards", "return 1 + 1", ["2"])

# --------------------------------------------------------------- errors ----
bare.bad("syntax error position", "local x = = 1", "test/main.lua:1: unexpected symbol near '='")
bare.bad("runtime error position", "\n\nlocal t = nil\nreturn t.x", "test/main.lua:4:")
block traceback:
  let (_, err) = bare.run("local function inner() error('deep') end\nlocal function outer() inner() end\nouter()")
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
bare.ok("native call", "return twice(21), pair('x', 1, 2)", ["42", "\"x\"", "3"])
bare.bad("native arg error has the caller's position", "\n\nstrict(5)", "test/main.lua:3: bad argument #1 to 'strict' (table expected, got number)")
bare.ok("native calling back into Lua", "return callback(function(n) return n + 1 end)", ["21"])
bare.bad("error inside the callback", "callback(function() error('inner boom') end)", "inner boom")
bare.ok("pcall catches native errors", "local ok, e = pcall(strict, 1) return ok, e:find('table expected') ~= nil", ["false", "true"])

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
  bare.ok("length and index", "return #LIST, LIST[2], LIST[9], LIST.name, tostring(LIST)",
          ["3", "20", "nil", "\"items\"", "\"list of 3\""])
  bare.ok("ipairs and pairs", "local a, b = 0, 0 for i, v in ipairs(LIST) do a = a + i * v end for k, v in pairs(LIST) do b = b + v end return a, b",
          ["140", "60"])
  bare.ok("calling iterates", "local s = 0 for v in LIST() do s = s + v end return s", ["60"])
  bare.ok("writes", "LIST[1] = 5 return LIST[1]", ["5"])
  bare.bad("class errors are script errors", "LIST.x = 1", "list only takes numbers")
  bare.ok("same object, same value", "local t = {} t[LIST] = 1 return LIST == LIST2, t[LIST2], rawequal(LIST, LIST2)",
          ["true", "1", "true"])
  bare.bad("a file handle is not mistaken for game userdata",
           "return getmetatable(LIST).__index(io.stdout, 1)", "attempt to index a userdata")
  bare.ok("nor freed as one", "getmetatable(LIST).__gc(io.stdout) return io.type(io.stdout), LIST == io.stdout",
          ["\"file\"", "false"])
  rawSet(base, vstr("THING"), vud(Userdata(cls: UdClass(name: "thing"), key: nil)))
  bare.bad("no length", "return #THING", "length of a thing")
  bare.bad("not callable", "return THING()", "call a thing")

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
  bare.ok("metatables set from Nim", "return CHILD.k, CHILD[1]", ["true", "1"])
  var raised = false
  try: rawSet(t, NilValue, vnum(1))
  except ScriptError: raised = true
  check(raised, "a nil key is a ScriptError, not a Lua panic")

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
  let c = Ctx(env: newModEnv(base), idx: 0)
  let world = initGame3D(World3DOptions(), Player(hp: 100, maxHp: 100))
  let dmgMult = difficultyEnemyDamageMult()

  # ---- no world yet
  activeWorld3D = nil
  c.ok("active() is false without a world", "return world3d.active()", ["false"])
  c.bad("spawn needs a world", "world3d.spawn{}", "needs an active 3D world")
  c.bad("enter needs a run", "world3d.enter{}", "needs a run in progress")
  c.bad("draw3d outside a draw hook", "draw3d.cube(0, 0, 0, 1, 1, 1, '#ffffff')", "only works inside world3dDraw")
  activeWorld3D = world
  modCtx.drawing = dtHud
  c.bad("draw3d in the 2D HUD hook", "draw3d.sphere(0, 0, 0, 1, '#ffffff')", "only works inside world3dDraw")
  modCtx.drawing = dtWorld3D
  c.bad("draw.* in a 3D draw hook", "draw.rect(0, 0, 1, 1, '#ffffff')", "draw3d library")
  c.ok("draw3d.text queues a label", "draw3d.text('hi', 1, 2, 3, 30, '#ff0000')", [])
  check(world3dLabels.len == 1 and world3dLabels[0].text == "hi" and world3dLabels[0].size == 30,
        "a label was queued")
  world3dLabels.setLen(0)
  modCtx.drawing = dtNone

  # ---- spawning goes through the queue
  world3dActions.setLen(0)
  c.ok("spawn returns the entity at once",
       "e = world3d.spawn{tag = 'grunt', x = 10, y = 5, z = -3, hp = 50, ai = 'chase', speed = 12, radius = 2, color = '#ff0000'} " &
       "return e.tag, e.x, e.z, e.hp, e.maxHp, e.ai, e.shape, e.color.r, e:valid(), #world3d.entities()",
       ["\"grunt\"", "10", "-3", "50", "50", "\"chase\"", "\"sphere\"", "255", "true", "0"])
  check(world3dActions.len == 1, "the spawn waits in the queue")
  processWorld3DActions(world)
  check(world3dActions.len == 0 and world.entities.len == 1, "the queue applied it")
  check(abs(world.entities[0].hp - 50 * difficultyEnemyHpMult()) < 0.01, "enemy HP got the profile difficulty once")
  c.ok("entities lists it", "return #world3d.entities(), #world3d.entities('grunt'), #world3d.entities('nope'), world3d.entities()[1] == e",
       ["1", "1", "0", "true"])
  c.ok("fields read and write",
       "e.x = 20 e.vz = 2 e.pos.y = 9 e.hp = 40 e.shape = 'cube' e.size = {x = 1, y = 2, z = 3} " &
       "return e.x, e.vz, e.y, e.pos.y, e.hp, e.shape, e.size.y, e.ai",
       ["20", "2", "9", "9", "40", "\"cube\"", "2", "\"chase\""])
  check(world.entities[0].pos.x == 20 and world.entities[0].vel.z == 2 and world.entities[0].shape == esCube,
        "writes reached the entity")
  c.bad("id is read-only", "e.id = 5", "read-only")
  c.bad("unknown field", "return e.bogus", "no field 'bogus'")
  c.bad("bad ai name", "e.ai = 'zoom'", "unknown ai")
  c.bad("NaN is rejected", "e.x = 0/0", "must be a finite number")
  c.bad("spawn: unknown field", "world3d.spawn{bogus = 1}", "no settable field 'bogus'")
  c.ok("methods",
       "e.hp = 40 local dealt = e:damage(15) return dealt, e.hp, e:distanceTo(20, 9, -3), e:distanceTo(e), #e:fields() > 10",
       ["15", "25", "0", "0", "true"])
  c.bad("method without self", "local f = e.kill f()", "call it with ':'")

  # ---- hooks see the wrappers; a dead entity is readable in its death hook
  c.ok("death hook wrapper",
       "deaths = {} hooks.on('world3dEntityDeath', function(en) deaths[#deaths + 1] = en.tag .. ':' .. tostring(en.hp <= 0) .. ':' .. tostring(en:valid()) end) " &
       "e:kill() return deaths[1], e.tag, e:valid()",
       ["\"grunt:true:false\"", "\"grunt\"", "false"])
  check(world.kills == 1, "a kill counted")
  sweepDead(world)
  check(world.entities.len == 0, "the sweep dropped it")
  c.bad("removed entity", "return e.tag", "entity no longer exists")
  c.ok("valid() still answers", "return e:valid()", ["false"])

  # ---- removal before it joined, projectiles and pickups
  c.ok("remove a pending spawn", "q = world3d.spawn{tag = 'ghost'} q:remove() return q:valid()", ["false"])
  processWorld3DActions(world)
  check(world.entities.len == 0, "a removed pending entity never joined")
  c.ok("projectile wrapper",
       "p = world3d.projectile{x = 1, vx = 5, damage = 7, fromPlayer = true, homing = true, pierce = 2, tag = 'bolt', radius = 2} " &
       "return p.damage, p.vx, p.x, p.pierce, p.tag, p.isHoming, p.homingStrength, p.fromPlayer, p.radius, #world3d.world.projectiles",
       ["7", "5", "1", "2", "\"bolt\"", "true", "200", "true", "2", "0"])
  processWorld3DActions(world)
  c.ok("projectile joined", "return #world3d.world.projectiles, world3d.world.projectiles[1] == p", ["1", "true"])
  c.ok("projectile write and remove", "p.damage = 9 p.vy = 3 local d = p.damage p:remove() return d, p:valid()", ["9", "false"])
  c.bad("removed projectile", "return p.damage", "projectile no longer exists")
  sweepDead(world)
  c.ok("pickup wrapper",
       "k = world3d.pickup{x = 1, y = 2, z = 3, kind = 'ammo', value = 10} return k.kind, k.value, k.x, k.z, #world3d.world.pickups",
       ["\"ammo\"", "10", "1", "3", "0"])
  processWorld3DActions(world)
  c.ok("pickup joined and removed", "k.y = 4 local n, y = #world3d.world.pickups, k.y k:remove() return n, y, k:valid()",
       ["1", "4", "false"])
  sweepDead(world)
  check(world.pickups.len == 0, "pickup swept")

  # ---- platforms and the arena
  c.ok("platform (full extents in, half extents stored)",
       "local i = world3d.platform{x = 5, y = 1, w = 10, h = 2, d = 6, jumpPad = true} " &
       "local pl = world3d.world.arena.platforms[i] return i, pl.size.x, pl.size.y, pl.size.z, pl.jumpForce, pl.pos.x",
       ["1", "5", "1", "3", "800", "5"])
  c.ok("arena bulk setter",
       "world3d.arena{radius = 200, sky = '#102030', gravity = -5, floorVisible = false, deathPlaneY = -9} " &
       "local a = world3d.world.arena return a.radius, a.boundsRadius, a.gravity, a.drawFloor, a.skyColor.g, a.deathPlaneY",
       ["200", "180", "-5", "false", "32", "-9"])
  c.ok("arena theme rebuilds it", "world3d.arena{theme = 'space'} return #world3d.world.arena.platforms > 0, world3d.world.arena.radius",
       ["true", "200"])
  c.bad("arena bad theme", "world3d.arena{theme = 'lava'}", "must be one of")
  c.ok("clearPlatforms", "world3d.clearPlatforms() return #world3d.world.arena.platforms", ["0"])

  # ---- world / player proxies
  c.ok("world fields",
       "local w = world3d.world w.score = 5 w.rules.timeLimit = 30 w.camera.fovy = 90 world3d.player.pos.y = 30 world3d.player.weapon.damage = 40 " &
       "return w.score, w.rules.timeLimit, w.camera.fovy, world3d.player.pos.y, w.player.weapon.damage, w.rules.exitOnBossDeath, w.active, w.result, w.bossEnabled",
       ["5", "30", "90", "30", "40", "true", "true", "\"none\"", "false"])
  check(world.score == 5 and world.rules.timeLimit == 30 and world.camera.fovy == 90 and
        world.player.pos.y == 30 and world.player.weapon.damage == 40, "proxy writes reached the world")
  c.bad("world.active is read-only", "world3d.world.active = false", "read-only")
  c.bad("lists cannot be replaced", "world3d.world.entities = 1", "must be set from a list")
  c.ok("the same world is the same value", "return world3d.world == world3d.world", ["true"])
  c.ok("two more entities", "world3d.spawn{tag = 'a'} world3d.spawn{tag = 'b'} return 1", ["1"])
  processWorld3DActions(world)
  c.ok("entity iterator", "local n = 0 for en in world3d.world.entities() do n = n + 1 end return n", ["2"])
  c.ok("damagePlayer / healPlayer",
       "world3d.player.health = 50 local d = world3d.damagePlayer(10) local h = world3d.player.health world3d.healPlayer(3) return d, h, world3d.player.health",
       [show(vnum((10 * dmgMult).float64)), show(vnum((50 - 10 * dmgMult).float64)),
        show(vnum((53 - 10 * dmgMult).float64))])
  c.ok("aim", "local x, y, z, dx, dy, dz = world3d.aim() return x, y, z, dx > 0.99", ["0", "-8.5", "0", "true"])   # the empty world starts on its solid floor

  # ---- raycast
  c.ok("spawn a far target", "target = world3d.spawn{tag = 'far', x = 0, y = 0, z = 50, radius = 4} return 1", ["1"])
  processWorld3DActions(world)
  c.ok("remove the entities at the origin",
       "for en in world3d.world.entities() do if en.tag ~= 'far' then en:remove() end end return #world3d.entities()", ["1"])
  sweepDead(world)
  c.ok("raycast result",
       "local h = world3d.raycast(0, 0, 0, 0, 0, 1) return h.kind, math.floor(h.dist), h.entity == target, world3d.raycast(0, 0, 0, 0, 0, -1, 10).kind",
       ["\"entity\"", "46", "true", "\"none\""])

  # ---- ending the world
  for (src, want) in [("world3d.finish(true)", w3Won), ("world3d.finish('lost')", w3Lost), ("world3d.exit()", w3Exit)]:
    world.pendingResult = w3None
    c.ok(src, src, [])
    check(world.pendingResult == want, src & " requests " & $want)
  world.pendingResult = w3None
  c.bad("finish argument", "world3d.finish(3)", "use true, false")

  # ---- hooks get wrappers as arguments
  c.ok("world3dStart gets the world",
       "startScore = nil hooks.on('world3dStart', function(w, resumed) startScore = w.score .. tostring(resumed) end) return 1", ["1"])
  modWorld3DStart(world, true)
  c.ok("world3dStart ran", "return startScore", ["\"5true\""])
  c.ok("world3dHit filter",
       "hits = {} hooks.on('world3dHit', function(dmg, target, proj) hits[#hits + 1] = (type(target) == 'string' and target or target.tag) .. ':' .. (proj and proj.tag or '-') return dmg * 2 end) return 1", ["1"])
  let shot = newProjectile3D(vec3(0, 0, 0), vec3(0, 0, 0), 10, true)
  shot.tag = "arrow"
  check(modWorld3DHit(10, world.entities[0], "", shot) == 20, "the hit filter doubled the damage")
  check(modWorld3DHit(10, nil, "boss", nil) == 20, "the filter also takes 'boss'")
  c.ok("hit hook arguments", "return hits[1], hits[2]", ["\"far:arrow\"", "\"boss:-\""])
  c.ok("player damaged filter",
       "hooks.on('world3dPlayerDamaged', function(amount, source, en) seen = source .. ':' .. type(en) return amount * 0.5 end) return 1", ["1"])
  world.player.health = 100
  world.player.invulnTimer = 0
  let took = damagePlayer3D(world, 10, "trap")
  check(abs(took - 5 * dmgMult) < 0.001, "the damage filter halved it")
  c.ok("player damaged arguments", "return seen", ["\"trap:nil\""])

  # ---- override targets
  c.ok("3D override targets", "override.model('boss3d', nil) override.model('satellite3d', nil) override.texture('entity3d:grunt', nil) " &
       "override.model('projectile3d:player', nil) override.model('projectile3d:enemy', nil) override.model('pickup3d:health', nil) return 1", ["1"])
  check(entity3dTex.hasKey("grunt") and pickup3dTex.hasKey("health"), "overrides have slots")
  c.bad("unknown target lists the 3D ones", "override.model('bogus', nil)", "boss3d, satellite3d, entity3d:<tag>")

  # ---- a world with a boss
  let bossWorld = initGame3D(World3DOptions(bossEnabled: true, bossId: 7), Player(hp: 100, maxHp: 100))
  activeWorld3D = bossWorld
  c.ok("boss snapshot", "local b = world3d.boss() return b.phase, b.health > 1000, #b.satellites", ["1", "true", "4"])
  c.bad("boss HP is read-only", "world3d.world.boss.health = 5", "read-only")
  c.ok("satellites are writable", "world3d.world.boss.satellites[1].health = 9 return world3d.world.boss.satellites[1].health", ["9"])
  let before = bossWorld.boss.health
  c.ok("damageBoss", "return world3d.damageBoss(100)", ["true"])
  check(abs(before - bossWorld.boss.health - 100) < 0.01, "damageBoss hurt the core")
  activeWorld3D = world
  c.ok("no boss: snapshot is nil", "return world3d.boss(), world3d.damageBoss(5)", ["nil", "false"])

  # ---- stale wrappers after the world ends
  c.ok("hold wrappers", "heldWorld = world3d.world heldPlayer = world3d.player heldEntity = world3d.spawn{tag = 'held'} " &
       "return heldWorld.score", ["5"])
  processWorld3DActions(world)
  c.ok("hold an entity from a list", "held2 = world3d.world.entities[1] return held2.tag", ["\"far\""])
  activeWorld3D = nil
  c.bad("stale world", "return heldWorld.score", "no longer exists")
  c.bad("stale player proxy", "return heldPlayer.health", "no longer exists")
  c.bad("stale entity", "return heldEntity.tag", "entity no longer exists")
  c.bad("stale entity (from a list)", "return held2.tag", "entity no longer exists")
  c.ok("stale valid()", "return heldEntity:valid(), world3d.active()", ["false", "false"])

  resetHooks()

# ------------------------------------------------- the 3D example mod ----
# The registry's examples/arena_3d (Cube Siege, plus its tweaks to the game's own
# boss-7 fight): its main.lua must load against the real API, and (driving the
# engine's hook helpers and action queue by hand, no window) play both parts.
# Drawing hooks need a GL context and are not run.
block examples3d:
  if not haveExamples: break examples3d
  let arenaSrc = readFile(examplesDir / "arena_3d" / "main.lua")

  proc load() =
    mods.setLen(0)
    let c = addMod("arena_3d")
    let (_, err) = c.run(arenaSrc, loading = true)
    check(err.len == 0, "arena_3d loads" & (if err.len > 0: ": " & err.splitLines()[0] else: ""))

  proc tick(w: Game3D, dt: float32 = 0.05) =
    w.timeElapsed += dt
    modWorld3DUpdate(w, dt)
    processWorld3DActions(w)
    sweepDead(w)

  resetHooks()
  load()
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
  check(modWorld3DPickup(newPickup3D(w, vec3(0, 0, 0), "overcharge", 8)), "the overcharge pickup is taken by the script")
  check(abs(w.player.weapon.damage - 24) < 0.01, "overcharge doubles the pellet damage")
  check(not modWorld3DPickup(newPickup3D(w, vec3(0, 0, 0), "health", 20)), "health keeps its built-in effect")
  # a resumed run continues at its wave
  check(rawGetStr(mods[0].runData, "wave").kind == vkNumber, "run.data carries the wave")
  var w2 = initGame3D(World3DOptions(modeKey: "arena_3d:cube_siege", resumed: true), Player(hp: 100, maxHp: 100))
  activeWorld3D = w2
  modWorld3DStart(w2, true)
  check(w2.wave == 5, "a resumed run restarts its wave (wave " & $w2.wave & ")")
  # another mode's world is left alone
  var w3 = initGame3D(World3DOptions(modeKey: "other:mode"), Player(hp: 100, maxHp: 100))
  activeWorld3D = w3
  modWorld3DStart(w3, false)
  check(w3.arena.platforms.len == 0, "Cube Siege ignores other worlds")

  # the tweaks to the vanilla boss-7 world (a fresh load, as a reload would do)
  resetHooks()
  clearModRoutes()
  load()
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
  check(mods[0].errorCount == 0, "no hook of the example raised an error")
  activeWorld3D = nil
  resetHooks()
  mods.setLen(0)

# ------------------------------------------------ 3D solid floor (arena) ----
block solidFloor3d:
  initModHooksVM(vm, base)
  installModApi(base)
  installMod3D(base)
  let c = Ctx(env: newModEnv(base), idx: 0)

  let ew = initGame3D(World3DOptions(), Player(hp: 100, maxHp: 100))
  check(ew.arena.solidFloor and ew.arena.floorY == -9.5'f32, "the empty arena has a solid floor at the drawn floor's top")
  check(ew.spawnPos.y > ew.arena.floorY and ew.player.pos.y > ew.arena.floorY, "the mod world spawns above the floor")
  check(not generateArena("space", 500).solidFloor and not generateArena("default", 500).solidFloor,
        "vanilla themes stay without a solid floor")
  let bw = initGame3D(World3DOptions(bossEnabled: true, bossId: 7), Player(hp: 100, maxHp: 100))
  check(not bw.arena.solidFloor and bw.player.pos.y == 15, "the boss arena is unchanged")

  # The player stands on it (no keys pressed: only gravity acts)
  for i in 0 ..< 240:
    discard updatePlayer(ew.player, ew.arena, 1.0'f32 / 60)
  check(abs(ew.player.pos.y - (ew.arena.floorY + 1.0'f32)) < 0.001 and ew.player.grounded and ew.player.vel.y == 0,
        "the player stands on the solid floor after 4 s")
  # ... and does not without it
  var hole = generateArena("empty", 500)
  hole.solidFloor = false
  var pl = newPlayer3D(vec3(0, 0, 0), 100)
  var fell = false
  for i in 0 ..< 240:
    if updatePlayer(pl, hole, 1.0'f32 / 60): fell = true
  check(fell, "without a solid floor the player falls through the death plane")

  activeWorld3D = ew
  let hit = raycast3D(ew, vec3(0, 10, 0), vec3(0, -1, 0), 100)
  check(hit.kind == "floor" and abs(hit.dist - 19.5'f32) < 0.01, "a ray down hits the floor")
  check(raycast3D(ew, vec3(0, 10, 0), vec3(0, 1, 0), 100).kind == "none", "a ray up misses it")

  c.ok("arena{solidFloor, floorY}", "world3d.arena{solidFloor = false, floorY = 5}", [])
  check(not ew.arena.solidFloor and ew.arena.floorY == 5, "the setter wrote both fields")
  c.ok("a theme resets the floor", "world3d.arena{theme = 'empty'}", [])
  check(ew.arena.solidFloor and ew.arena.floorY == -9.5'f32, "...to that theme's")
  c.ok("arena.solidFloor/floorY through the deep proxy, raycast kind 'floor'",
       "a = world3d.world.arena a.floorY = 2 return a.solidFloor, a.floorY, world3d.raycast(0, 10, 0, 0, -1, 0).kind",
       ["true", "2", "\"floor\""])
  check(ew.arena.floorY == 2, "the proxy wrote floorY")
  activeWorld3D = nil

# ------------------------------------------------- M0: foundations ----
# Library isolation, the load phase, mod events, per-entity data, spawn
# handles, mod.storage's profile folder and the file sandbox.
block foundations:
  freshApi()
  let libs = tableKeysOf(base)
  check("draw" in libs and "spawn" in libs and "hooks" in libs and "string" notin libs,
        "the game's libraries are listed for per-mod copies: " & $libs)
  var a = addMod("alpha")
  var b = addMod("beta")

  # ---- library isolation
  a.ok("a mod may replace a library function", "draw.circle = nil spawn.extra = 1 return draw.circle, spawn.extra", ["nil", "1"])
  b.ok("...without touching another mod's copy", "return type(draw.circle), spawn.extra", ["\"function\"", "nil"])

  # ---- register.* only while loading
  a.ok("register while loading", "return register.powerup{id = 'zap'}", ["\"alpha:zap\""], loading = true)
  a.bad("register from a hook or timer is refused", "register.powerup{id = 'late'}", "only works while the mod loads")
  a.bad("roster.add too", "roster.add('wave', 'etCube')", "only works while the mod loads")
  a.ok("override.* stays callable", "override.text('en', 'alpha_key', 'x') return 1", ["1"])

  # ---- mod events
  a.ok("handlers in order",
       "order = {} hooks.on('alpha:ping', function(n) order[#order + 1] = 'a' .. n end) " &
       "hooks.on('alpha:value', function(v, k) return v + k end) return 1", ["1"])
  b.ok("a second mod listens",
       "hooks.on('alpha:ping', function(n) hooks.emit('beta:heard', n) end) " &
       "hooks.on('alpha:value', function(v, k) return v * k end) " &
       "hooks.on('beta:heard', function(n) heard = n end) return 1", ["1"])
  a.ok("emit and filter", "hooks.emit('alpha:ping', 7) return order[1], hooks.filter('alpha:value', 2, 3)",
       ["\"a7\"", "15"])
  b.ok("the nested emit arrived", "return heard", ["7"])
  a.bad("event names need a colon", "hooks.emit('ping')", "<mod id>:<event>")
  a.ok("runaway recursion is capped",
       "hooks.on('alpha:loop', function() hooks.emit('alpha:loop') end) return pcall(hooks.emit, 'alpha:loop')", ["true"])
  check(mods[0].errorCount > 0, "the over-deep emit was reported as an error")
  a.ok("hooks.off", "local f = function() end hooks.on('alpha:x', f) hooks.off('alpha:x', f) return 1", ["1"])
  disableMod(1, "test")
  a.ok("a disabled mod's handlers are gone", "return hooks.filter('alpha:value', 2, 3)", ["5"])

  # ---- per-entity data and spawn handles
  freshApi()
  mods.setLen(0)
  a = addMod("alpha")
  b = addMod("beta")
  let g = newRun()
  modBeginFrame(g)
  check(modCtx.game == g, "the run is published")
  a.ok("spawn.enemy returns a handle valid before it joins",
       "e = spawn.enemy('etCircle', 100, 50) e.data.mark = 'a' mods.export(e) return e:valid(), e.x, #game.enemies",
       ["true", "100", "0"])
  check(modPendingEnemies.len == 1 and modActions.len == 1 and modActions[0].kind == makJoinEnemy,
        "the spawn waits to join")
  b.ok("each mod has its own e.data", "local e = mods.get('alpha') return e.data.mark, (function() e.data.mark = 'b' return e.data.mark end)()",
       ["nil", "\"b\""])
  a.ok("...and the first one keeps its own", "return e.data.mark", ["\"a\""])
  a.ok("spawn.bullet returns a handle", "bl = spawn.bullet{x = 1, y = 2, vx = 0, vy = 10} bl.data.n = 3 return bl:valid(), bl.bulletId > 0",
       ["true", "true"])
  a.bad("e.data must be a table", "e.data = 5", "must be a table")
  # what game.nim's processModActions does with the joins
  for act in modActions:
    if act.kind == makJoinEnemy: g.enemies.add(act.target)
    if act.kind == makJoinBullet: g.bullets.add(act.bullet)
  modActions.setLen(0)
  modPendingEnemies.setLen(0)
  modPendingBullets.setLen(0)
  a.ok("joined", "return e:valid(), #game.enemies, #game.bullets", ["true", "1", "1"])
  captureRunData(g, false)
  check("@e:" notin g.modRunData, "a run save carries no entity data")
  captureRunData(g, true)
  check("@e:alpha" in g.modRunData and "@e:beta" in g.modRunData, "a snapshot carries every mod's entity data")
  # a resumed run (a new Game object, the same ids) gets it back
  let g2 = newRun()
  g2.nextEnemyId = 2
  g2.modRunData = g.modRunData
  g2.time = 10
  g2.enemies = g.enemies
  g2.bullets = g.bullets
  modBeginFrame(g2)
  a.ok("entity data round-trips through the snapshot", "return game.enemies[1].data.mark, game.bullets[1].data.n",
       ["\"a\"", "3"])
  b.ok("for every mod", "return game.enemies[1].data.mark", ["\"b\""])
  let g3 = newRun()
  g3.enemies = g.enemies
  modBeginFrame(g3)
  a.ok("a fresh run starts without it", "return game.enemies[1].data.mark", ["nil"])

  # ---- PvP: no gameplay scripting
  modCtx.inPvP = true
  a.bad("spawns refuse in PvP", "spawn.enemy('etCircle', 0, 0)", "PvP")
  modCtx.inPvP = false

  # ---- mod.storage stays in the profile it was read from
  let home = tempHome("tophat_test_home")
  let keeper = addMod("keeper")
  keeper.ok("storage write", "mod.storage.coins = 9 return 1", ["1"])
  activeProfileSlot = 2   # a profile switch reloads mods after this
  check(saveModStorage(mods[keeper.idx]), "storage saved")
  check(fileExists(getProfileDir(1) / "mod_data" / "keeper.json") and
        not fileExists(getProfileDir(2) / "mod_data" / "keeper.json"),
        "storage written to the old profile's folder")
  activeProfileSlot = 1

  # ---- files: a mod reads its folder and mod.dataDir(), writes only the latter
  let boxDir = home / "mods" / "boxed"
  createDir(boxDir / "lib")
  writeFile(boxDir / "notes.txt", "own file")
  writeFile(boxDir / "lib" / "helper.lua", "return 'helped'")
  writeFile(home / "secret.txt", "not the mod's")
  let bx = addMod("boxed", boxDir)
  let secret = (home / "secret.txt").replace('\\', '/')
  bx.ok("reads its own folder",
        "local f = assert(io.open('notes.txt')) local s = f:read('a') f:close() " &
        "local line for l in io.lines('notes.txt') do line = l end " &
        "return s, loadfile('lib/helper.lua')(), require('lib.helper'), line",
        ["\"own file\"", "\"helped\"", "\"helped\"", "\"own file\""])
  bx.ok("its folder is read-only",
        "return io.open('notes.txt', 'a') == nil, io.open('new.txt', 'w') == nil, " &
        "os.remove('notes.txt') == nil, os.rename('notes.txt', mod.dataDir() .. '/moved.txt') == nil",
        ["true", "true", "true", "true"])
  check(readFile(boxDir / "notes.txt") == "own file" and not fileExists(boxDir / "new.txt"),
        "the mod's folder is unchanged")
  bx.ok("writes and reads mod.dataDir()",
        "local d = mod.dataDir() local f = assert(io.open(d .. '/save.txt', 'w')) f:write('kept') f:close() " &
        "assert(os.rename(d .. '/save.txt', d .. '/kept.txt')) " &
        "local g = assert(io.open(d .. '/kept.txt')) local s = g:read('a') g:close() " &
        "return s, os.remove(d .. '/kept.txt')",
        ["\"kept\"", "true"])
  bx.ok("nothing outside its folders opens",
        "return io.open('" & secret & "') == nil, io.open('../../secret.txt') == nil, " &
        "loadfile('../../secret.txt') == nil, pcall(dofile, '" & secret & "') == false, " &
        "io.open(mod.dataDir() .. '/../boxed.json', 'w') == nil, pcall(io.lines, '../../secret.txt') == false",
        ["true", "true", "true", "true", "true", "true"])
  bx.ok("nor through package.path or the original tables",
        "package.path = '" & (home.replace('\\', '/')) & "/?.txt' " &
        "local ok = pcall(require, 'secret') package.path = '' " &
        "return ok, getmetatable(_ENV).__index.io.open('" & secret & "') == nil, " &
        "package.loaded.io.open('" & secret & "') == nil, (pcall(os.tmpname))",
        ["false", "true", "true", "false"])
  bx.bad("mod.path stays inside", "return mod.path('../../secret.txt')", "outside the mod's folders")
  bx.bad("assets stay inside", "return assets.text('" & secret & "')", "outside the mod's folders")
  check(readFile(home / "secret.txt") == "not the mod's", "the outside file is untouched")
  removeDir(home)
  modOutsideRun(false)
  mods.setLen(0)
  resetHooks()

# ------------------------------------------------- open data (trusted) ----
# Everything is writable (the player's progression too); lists and tables
# grow and shrink at safe points; the game's globals are reachable; and
# engine.defer runs a function at the next safe point.
var openNumber = 3
var openTable = initTable[string, int]()
block openData:
  freshApi()
  let c = addMod("open")
  let g = newRun()
  modBeginFrame(g)
  let e1 = newEnemy(100, 100, 1.0, etCircle, g)
  g.enemies.add(e1)

  # ---- lists
  c.bad("a list changes length only at a safe point", "game.enemies:add(game.enemies[1])", "safe point")
  c.ok("list:add", "game.enemies:add(game.enemies[1]) return #game.enemies, game.enemies[2] == game.enemies[1]",
       ["2", "true"], safe = true)
  c.ok("list:remove", "game.enemies:remove(2) return #game.enemies", ["1"], safe = true)
  c.ok("list:insert (position first, like table.insert)",
       "game.pendingToasts:add('b') game.pendingToasts:insert(1, 'a') return #game.pendingToasts, game.pendingToasts[1]",
       ["2", "\"a\""], safe = true)
  c.ok("list:copy is plain data", "local c = game.pendingToasts:copy() c[1] = 'z' return type(c), game.pendingToasts[1]",
       ["\"table\"", "\"a\""])
  c.ok("list:clear", "game.pendingToasts:clear() return #game.pendingToasts", ["0"], safe = true)
  c.ok("a list from a table, tuples from tables",
       "game.modShopBought = {{key = 'x', bought = 2}} return #game.modShopBought, game.modShopBought[1].bought",
       ["1", "2"], safe = true)
  c.bad("an enemy list takes enemies", "game.enemies:add(5)", "expects an enemy", safe = true)
  check(g.enemies.len == 1 and g.enemies[0] == e1, "the enemy list is intact")

  # ---- tables
  registerModGlobal("openTable", addr openTable)
  c.ok("a table grows at a safe point", "local t = engine.globals.openTable t.kills = 5 return t.kills, #t",
       ["5", "1"], safe = true)
  c.bad("...and only there", "engine.globals.openTable.deaths = 1", "safe point")
  c.ok("an entry changes anywhere", "engine.globals.openTable.kills = 6 return engine.globals.openTable.kills", ["6"])
  check(openTable["kills"] == 6, "...for the game too")
  c.ok("pairs over a table", "local n = 0 for k, v in pairs(engine.globals.openTable) do n = n + v end return n", ["6"])
  c.ok("nil removes an entry", "engine.globals.openTable.kills = nil return #engine.globals.openTable", ["0"], safe = true)

  # ---- enemies and bosses
  c.ok("an enemy becomes another type", "game.enemies[1].type = 'etCube' return game.enemies[1].type", ["\"etCube\""])
  check(e1.enemyType == etCube, "...for the game too")
  c.ok("hp is set outright; a sliver reads as spent", "local e = game.enemies[1] e.hp = 0.00001 return e.hp", ["0"])
  c.bad("identity stays read-only", "game.enemies[1].id = 9", "read-only")
  c.bad("the reward rule stays read-only", "game.cheatsUsed = false", "read-only")

  # ---- engine.defer and game.state
  c.ok("engine.defer waits for a safe point",
       "engine.defer(function() deferred = #game.enemies game.enemies:add(game.enemies[1]) end) return deferred",
       ["nil"])
  runDeferredCalls()
  c.ok("...where lists may grow", "return deferred, #game.enemies", ["1", "2"])
  g.enemies.setLen(1)
  c.ok("game.state changes at the next safe point", "game.state = 'gsShop' return game.state", ["\"gsPlaying\""])
  runDeferredCalls()
  check(g.state == gsShop, "the state changed at the safe point")
  g.state = gsPlaying
  c.ok("enum names match style-insensitively", "game.state = 'gs_shop'", [])
  runDeferredCalls()
  check(g.state == gsShop, "...like parseEnum did")
  g.state = gsPlaying
  c.bad("an unknown enum name is an error", "game.state = 'gsNope'", "has no value named 'gsNope'")

  # ---- engine.globals
  registerModGlobal("openNumber", addr openNumber)
  c.ok("engine.globals reads and writes the game's globals",
       "engine.globals.openNumber = engine.globals.openNumber + 8 return engine.globals.openNumber", ["11"])
  check(openNumber == 11, "the global changed")
  c.ok("engine.globals lists what it has",
       "local names = {} for k in pairs(engine.globals) do names[k] = true end return names.settings, names.openNumber",
       ["true", "true"])
  c.bad("an unknown global names the ones there are", "return engine.globals.nope", "it has")

  # ---- mixins on the game's own code
  installModMixin(base)
  let mm = addMod("mixer")
  let target = newEnemy(0, 0, 1.0, etCircle, g)
  target.hp = 100
  mm.ok("wrap the game's damage door", "hd = mixin.wrap('combat.applyEnemyHpDamage', function(orig, e, dmg) return orig(e, dmg * 2) end)", [])
  check(applyEnemyHpDamage(target, 5) == 10 and target.hp == 90, "the game's own call is doubled: " & $target.hp)
  mm.ok("mixin.remove", "mixin.remove(hd)", [])
  check(applyEnemyHpDamage(target, 5) == 5, "and back")
  mm.ok("engine.<module>.<proc> calls the game", "return math.type(engine.types.difficultyEnemyHpMult())", ["\"float\""])
  mm.bad("engine.call names the arity it wants", "return engine.types.difficultyEnemyHpMult(1, 2, 3)",
         "types.difficultyEnemyHpMult takes 0 arguments, got 3")
  mm.ok("mixin.list names the game's procs", "return #mixin.list('combat.') > 3", ["true"])

  # ---- rl: raylib for scripts (what works without a window)
  installModRl(base)
  let rl = addMod("rl", getTempDir() / "tophat_rl_mod")
  rl.ok("rl colours", "return rl.Red.r, rl.RayWhite.g", ["230", "245"])
  rl.bad("rl's file arguments stay in the mod's folders", "return rl.loadTexture('../../outside.png')", "outside the mod's folders")
  rl.bad("rl writes only to mod.dataDir()", "return rl.exportImage(rl.genImageColor(2, 2, rl.Red), 'shot.png')", "read-only")
  rl.ok("rl takes tables for its structs",
        "return rl.checkCollisionRecs({x = 0, y = 0, width = 10, height = 10}, {x = 5, y = 5, width = 10, height = 10})",
        ["true"])
  rl.ok("an out parameter comes back after the result",
        "local hit, p = rl.checkCollisionLines({x = 0, y = 0}, {x = 10, y = 10}, {x = 0, y = 10}, {x = 10, y = 0}) " &
        "return hit, p.x, p.y", ["true", "5", "5"])
  rl.ok("a resource handle (an image, no GPU needed)",
        "img = rl.genImageColor(4, 3, rl.Red) return img.width, img.height, img.owned, tostring(img)",
        ["4", "3", "true", "\"Image\""])
  rl.ok("a var resource parameter edits the handle's own resource",
        "rl.imageResize(img, 8, 6) return img.width, img.height", ["8", "6"])
  rl.ok("rl.unload", "local ok = rl.unload(img) return ok, (pcall(function() return img.width end))", ["true", "false"])
  releaseScriptResources()

  modOutsideRun(false)
  mods.setLen(0)
  resetHooks()

# ------------------------------------------- M1: things and projectiles ----
block things2d:
  freshApi([installWorld2D])
  let c = addMod("necro")

  # ---- registration (strict tables)
  c.ok("register.thing", "ALLY = register.thing{id = 'ally', team = 'player', motion = 'static', radius = 20, " &
       "contactDamage = 2, hp = 10, solid = true, weapon = {interval = 0.5, range = 200, damage = 3}} " &
       "BOLT = register.projectile{id = 'bolt', pierce = 2, onHit = function(b, e, d) return d * 2 end} " &
       "WALL = register.thing{id = 'wall', shape = 'rect', w = 40, h = 40, blocksBullets = true, hitByBullets = true, hp = 5} " &
       "return ALLY, BOLT", ["\"necro:ally\"", "\"necro:bolt\""], loading = true)
  c.bad("register.thing rejects unknown keys", "register.thing{id = 'x', colour = 'red'}", "unknown field 'colour'", loading = true)
  c.bad("register.thing checks enum names", "register.thing{id = 'y', team = 'blue'}", "unknown value 'blue'", loading = true)
  check(thingKinds.len == 2 and projectileKinds.len == 1, "kinds registered")

  # ---- spawning
  let g = newRun()
  g.player = Player(hp: 10, maxHp: 10, radius: 12, pos: vec2(500, 500))
  modBeginFrame(g)
  c.ok("spawn.thing returns a handle valid before it joins",
       "a = spawn.thing(ALLY, 100, 100, {tag = 'first'}) a.data.souls = 3 " &
       "return a:valid(), a.x, a.kind, a.tag, a.solid, a.hp, #game:things()",
       ["true", "100", "\"necro:ally\"", "\"first\"", "true", "10", "0"])
  c.bad("spawn.thing needs a registered kind", "spawn.thing('necro:nope', 0, 0)", "no thing kind")
  c.ok("spawn.hazard", "hz = spawn.hazard{shape = 'circle', x = 300, y = 300, r = 50, warn = 0.5, active = 0.2, damage = 4, hurts = 'enemies'} return hz.kind, hz.hazard.warn",
       ["\"@hazard\"", "0.5"])
  for act in modActions:
    if act.kind == makJoinThing: discard joinThing(g, act.thing, act.callback, act.owner)
  modActions.setLen(0)
  c.ok("joined", "return #game:things(), #game:things('first'), #game:thingsNear(100, 100, 5), a:valid(), a.data.souls",
       ["2", "1", "1", "true", "3"])

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
  g.modThings[0].pos = vec2(300, 300)
  updateThings(g, 0.3, 0.3, grid, 40)
  check(e.hp < afterHazard, "contact damage hit the enemy")
  check(g.bullets.len >= 1 and g.bullets[^1].fromPlayer, "the turret fired")
  # projectile routing
  c.ok("bullet kinds", "b = spawn.bullet{x = 0, y = 0, kind = BOLT, fromPlayer = true} return b.modKind, b.modPierce",
       ["\"necro:bolt\"", "2"])
  check(modBulletHit(modPendingBullets[^1], e, 5) == 10, "a kind's onHit routes the hit")
  c.bad("unknown bullet kind", "spawn.bullet{kind = 'nope:x'}", "no projectile kind")
  # thing methods
  c.ok("damage, heal, kill", "local t = game:things('first')[1] local d = t:damage(4) local h = t:heal(1) " &
       "local hp = t.hp t:kill() return d, h, hp, t.dead, t:valid()", ["4", "1", "7", "true", "false"])
  c.ok("explode hurts enemies", "local before = game.enemies[1].hp game:explode(300, 300, 40, 2) return game.enemies[1].hp < before", ["true"])
  modActions.setLen(0)
  modPendingBullets.setLen(0)
  modOutsideRun(false)
  mods.setLen(0)
  resetHooks()

# --------------------------------------------- M2: statuses and hooks ----
block statuses:
  freshApi([installWorld2D, installContentApi])
  let c = addMod("hex")
  c.ok("register.status", "SOUL = register.status{id = 'soul', maxStacks = 3, duration = 2, tickInterval = 0.5, " &
       "modifiers = {speed = -0.2, damageTaken = 0.5, damageDealt = -0.25}, " &
       "onTick = function(t, stacks) ticks = (ticks or 0) + stacks end, onExpire = function(t) expired = true end} " &
       "applied = {} hooks.on('statusApplied', function(t, name, n) applied[#applied + 1] = name .. n end) return SOUL",
       ["\"hex:soul\""], loading = true)
  c.bad("register.status is strict", "register.status{id = 'x', stack = 2}", "unknown field 'stack'", loading = true)
  let g = newRun()
  let p = g.player
  modBeginFrame(g)
  let e = newEnemy(100, 100, 1.0, etCircle, g)
  e.hp = 100
  e.maxHp = 100
  g.enemies.add(e)
  c.ok("apply and stack", "local e = game.enemies[1] e:applyStatus(SOUL) e:applyStatus(SOUL, {stacks = 5}) " &
       "local s = e:status(SOUL) return s.stacks, s.remaining, applied[1], applied[2]",
       ["3", "2", "\"hex:soul1\"", "\"hex:soul3\""])
  check(abs(e.statusSpeed - -0.6) < 0.001 and abs(e.statusDamageTaken - 1.5) < 0.001, "modifiers summed: " & $e.statusSpeed)
  check(abs(enemyDamageDealtMult(e) - 0.25) < 0.001, "damage dealt modifier")
  let dealt = applyEnemyHpDamage(e, 10)
  check(abs(dealt - 25) < 0.01, "damage taken goes through the status: " & $dealt)
  tickModStatuses(e, 0.6)
  c.ok("onTick ran", "return ticks", ["3"])
  tickModStatuses(e, 1.6)
  check(e.modStatuses.len == 0 and e.statusSpeed == 0, "the status expired")
  c.ok("onExpire ran", "return expired", ["true"])
  c.ok("built-in effects by name", "local e = game.enemies[1] e:applyStatus('slow', {magnitude = 0.5, duration = 2}) " &
       "e:applyStatus('fire', {magnitude = 2, duration = 1}) return e:status('slow').magnitude, e:status('fire').magnitude, e:status('poison')",
       ["0.5", "2", "nil"])
  c.bad("unknown status", "game.enemies[1]:applyStatus('soggy')", "unknown status 'soggy'")
  c.ok("player statuses", "player:applyStatus(SOUL, {duration = 1}) return player:status(SOUL).stacks", ["1"])
  check(abs(calculateCombatStats(p).damage - p.damage * 0.75) < 0.001, "player damage dealt modifier")
  c.ok("clearStatus", "player:clearStatus(SOUL) return player:status(SOUL)", ["nil"])

  # ---- difficulty.scale
  let hpBefore = difficultyEnemyHpMult()
  c.ok("difficulty.scale", "difficulty.scale{enemyHp = 2, spawnPace = 1.5} return difficulty.get().enemyHp", ["2"])
  check(abs(difficultyEnemyHpMult() - hpBefore * 2) < 0.001, "the lever scales the profile's")
  modBeginFrame(newRun())
  check(difficultyEnemyHpMult() == hpBefore, "a new run starts at 1")
  modBeginFrame(g)   # back to the first run (it counts as new again: fine for the rest)

  # ---- filters
  c.ok("contact and bullet filters", "hooks.on('enemyContact', function(d, e, p) return d * 3 end) " &
       "hooks.on('bulletHitPlayer', function(d, b, p) return 0 end) return 1", ["1"])
  check(modEnemyContact(e, 2) == 6, "enemyContact filter")
  check(modBulletHitPlayer(Bullet(damage: 4), 4) == 0, "bulletHitPlayer filter")
  # ---- a named cause of death
  g.player.hp = 1
  c.ok("hurt with a cause", "return player:hurt(50, {cause = 'Lava'})", ["true"])
  check(g.deathCause == dcMod and g.deathSourceName == "Lava", "the death screen names the cause")
  modOutsideRun(false)
  mods.setLen(0)
  resetHooks()

# ------------------------------------------------ M3: content registries ----
block registries:
  freshApi([installWorld2D, installContentApi])
  let home = tempHome("tophat_test_home3")
  let c = addMod("kit")
  c.ok("register everything",
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
  c.bad("stats DSL checks fields", "register.shopItem{id = 'y', stats = {bogus = 1}}", "not a number field", loading = true)
  c.bad("stats DSL checks values", "register.patch{id = 'z', stats = {damage = 'lots'}}", "is not a change", loading = true)
  c.bad("event reward names", "register.survivalEvent{id = 'w', reward = 'gold'}", "sctMinor", loading = true)

  var g = newRun()
  let p = g.player
  p.damage = 2
  g.currentWave = 5
  modBeginFrame(g)

  # ---- consumables
  let cons = newConsumable(10, 20, 1.0, gmWaveBased)
  check(cons.consumableType == ctMod and cons.modKey == "kit:mana", "a heavy mod consumable wins the drop roll")
  modConsumablePickup(g, cons)
  check(abs(p.damage - 3) < 0.001, "its stats applied")
  c.ok("its onPickup ran", "return picked", ["10"])
  c.ok("spawn.consumable by name", "spawn.consumable(MANA, 1, 2) return 1", ["1"])
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
  c.ok("onBuy ran", "return boughtN", ["1"])

  # ---- patches
  g.mode = gmRoguelite
  g.rogueliteRun = RogueliteRun(floorNumber: 1)
  let choices = rollPatchChoices(g.rogueliteRun, 3)
  check(choices.len == 3 and choices[0].relicType == rrtMod and choices[0].modKey == "kit:ward",
        "a heavy mod patch is drafted")
  let hp0 = p.maxHp
  check(installPatch(g, choices[0]) and not installPatch(g, choices[0]), "installed, only once")
  check(p.maxHp == hp0 + 2 and rrtMod in p.patches, "its stats applied and mirrored")
  check(patchName(choices[0]) == "Ward" and patchKbLabel(choices[0]).startsWith("KB-9"), "named by its registration")
  c.ok("onInstall ran; hasPatch", "return installed, player:hasPatch(WARD), player:hasPatch('rrtOverclock')",
       ["true", "true", "false"])
  check(rollPatchChoices(g.rogueliteRun, 30).len == len(AllPatches), "an owned mod patch is not offered again")

  # ---- survival events
  g.mode = gmTimeSurvival
  g.survival = initSurvivalState()
  startSurvivalEvent(g, sekMod, "kit:storm")
  check(g.survival.event.kind == sekMod and g.survival.event.modKey == "kit:storm", "the mod event runs")
  check(survivalEventName(sekMod, "kit:storm") == "Storm", "named")
  c.ok("onStart ran", "return started", ["true"])
  for i in 0 ..< 3: updateSurvivalEvent(g, 0.1)
  check(g.survival.event.kind == sekNone, "its update finished it")
  c.ok("onFinish ran", "return finished", ["true"])

  # ---- achievements
  c.ok("progress", "return advancements.progress('slayer', 2), advancements.get('slayer').unlocked", ["false", "false"])
  c.ok("unlock", "return advancements.progress('slayer'), advancements.get('slayer').unlocked", ["true", "true"])
  check(advancementToasts.len == 1, "an unlock toast is queued")
  check(fileExists(getProfileDir(1) / "mod_data" / "@advancements.json"), "kept in the profile's mod_data")
  advancementToasts.setLen(0)
  c.bad("another mod's achievement", "advancements.progress('other:x')", "no achievement")

  # ---- [Q] abilities
  var zap: PowerUpType
  check(resolvePowerUpScriptName("kit:zap", zap) and powerUpDef(zap).inLegendaryPanel and
        powerUpDef(zap).activeCooldown == 4, "an active power-up is on the [Q] strip")
  g.mode = gmWaveBased
  p.powerUps.add(PowerUp(powerType: zap, level: 1))
  check(modActivateAbilities(g) and abilityCooldown(p, zap) == 4, "[Q] fired it; cooldown set")
  check(not modActivateAbilities(g), "not again while cooling down")
  c.ok("activate ran", "return zapped", ["1"])
  modOutsideRun(false)
  mods.setLen(0)
  resetHooks()
  removeDir(home)

# ------------------------------------------------------- M4: in-run UI ----
block inRunUi:
  freshApi([installWorld2D, installContentApi, installModUi])
  let c = addMod("story")
  c.ok("register.hudCard / pauseAction",
       "register.hudCard{id = 'souls', title = 'SOULS', height = 30, draw = function(x, y, w, h) end} " &
       "register.pauseAction{id = 'skip', name = 'Skip intro', onClick = function(g) skipped = true end} return 1",
       ["1"], loading = true)
  c.bad("hudCard needs draw", "register.hudCard{id = 'y'}", "needs draw", loading = true)
  check(hudCardDefs.len == 1 and livePauseActions().len == 1, "registered")
  runPauseAction(0)
  c.ok("pause actions run", "return skipped", ["true"])
  c.ok("the game's screens are there", "return type(ui.dialogue), type(ui.choose), type(ui.cutscene)",
       ["\"function\"", "\"function\"", "\"function\""])

  c.bad("ui.open needs a run", "ui.open{draw = function() end}", "no run in progress")
  let g = newRun()
  modBeginFrame(g)
  c.bad("ui.open is strict", "ui.open{draw = function() end, pasue = false}", "unknown field 'pasue'")
  c.ok("ui.open", "closed = 0 s = ui.open{draw = function(w, h) end, onClose = function() closed = closed + 1 end} " &
       "return s:isOpen(), ui.isOpen(s)", ["true", "true"])
  check(modUiPauses() and modUiHoldsInput(), "an open screen pauses and takes the input")
  check(modUiBack() and not modUiHoldsInput(), "Esc / B closes it")
  c.ok("onClose ran", "return closed, s:isOpen()", ["1", "false"])
  c.ok("a screen that lets the run go on", "t = ui.open{draw = function() end, pause = false, closeOnBack = false} return 1", ["1"])
  check(not modUiPauses() and modUiHoldsInput() and not modUiBack(), "not pausing; Esc does not close it")
  c.ok("updates", "n = 0 u = ui.open{draw = function() end, update = function(dt) n = n + dt end, pause = false} return 1", ["1"])
  updateModUi(0.5)
  c.ok("its update ran", "return n", ["0.5"])
  c.ok("ui.closeAll", "ui.closeAll() return t:isOpen(), u:isOpen()", ["false", "false"])
  c.ok("dialogue opens a screen", "d = ui.dialogue{lines = {{speaker = 'A', text = 'hi'}}, onDone = function() dd = true end} return d:isOpen()", ["true"])
  check(modModals.len == 1 and modModals[0].owner == 0, "as the mod that called it")
  check(modUiBack(), "skippable")
  c.ok("onDone ran on skip", "return dd", ["true"])
  c.bad("dialogue needs lines", "ui.dialogue{}", "needs lines")
  c.bad("widgets only draw", "ui.button(0, 0, 10, 10, 'x')", "draws")
  c.ok("toast and banner", "ui.toast('hello') ui.banner('ROUND 2', 'Fight!') return 1", ["1"])
  check(g.pendingToasts == @["hello"], "a toast over the run")
  check(modBanner.title == "ROUND 2" and modBanner.timer > 0, "a banner is up")
  c.ok("a screen left open", "ui.open{draw = function() end} return 1", ["1"])
  modBeginFrame(newRun())
  check(modModals.len == 0, "a new run starts with no mod screens")

  # ---- mod screens: register.screen + screens.go / back (gsModScreen)
  c.ok("register.screen",
       "log = {} register.screen{id = 'map', enter = function(from, n) log[#log+1] = 'enter ' .. from .. ' ' .. tostring(n) end, " &
       "update = function(dt) log[#log+1] = 'update' end, draw = function(w, h) log[#log+1] = 'draw' end, " &
       "leave = function(to) log[#log+1] = 'leave ' .. to end} " &
       "register.screen{id = 'inv', draw = function() end} return 1",
       ["1"], loading = true)
  c.bad("screens.go needs a registered screen", "screens.go('nope')", "no screen 'story:nope'")
  let gs = newRun()
  c.ok("screens.go opens at the next frame's top", "screens.go('map', 7) return screens.current()", ["nil"])
  applyScreenRequests(gs)
  check(gs.state == gsModScreen and activeScreen == "story:map" and screenOverRun, "over the run: " & $gs.state)
  check(isActiveRunState(gs.state), "the run is still the run on screen")
  tickModScreen(0.016)
  check(drawModScreen(1024, 768), "the game's pointer by default")
  c.ok("enter got where it came from", "return table.concat(log, ',')", ["\"enter gsPlaying 7,update,draw\""])
  c.ok("a second screen", "screens.go('inv') return 1", ["1"])
  applyScreenRequests(gs)
  check(activeScreen == "story:inv" and screenDepth() == 2, "stacked: " & activeScreen)
  c.ok("back", "screens.back() return 1", ["1"])
  applyScreenRequests(gs)
  check(activeScreen == "story:map" and gs.state == gsModScreen, "back to the first screen")
  c.ok("back again", "screens.back() return screens.depth()", ["1"])
  applyScreenRequests(gs)
  check(gs.state == gsPlaying and activeScreen == "" and not screenOverRun, "back to the run: " & $gs.state)
  c.ok("leave ran", "return log[#log]", ["\"leave gsPlaying\""])
  c.ok("open again", "screens.go('map') return 1", ["1"])
  applyScreenRequests(gs)
  gs.state = gsGameOver   # the game moved on by itself (a game over, a script)
  applyScreenRequests(gs)
  check(activeScreen == "" and gs.state == gsGameOver, "the screens are left when the state moves on")
  c.ok("screens.list", "return #screens.list()", ["2"])
  modOutsideRun(false)
  mods.setLen(0)
  resetHooks()

# ------------------------------------------------------ mod languages ----
block modLanguages:
  freshApi([installWorld2D, installContentApi, installModUi])
  clearModTranslations()
  clearModLanguages()
  let c = addMod("lingo")
  let playEn = t(tkDesktopIconPlay)
  let survivalEn = t(tkDesktopIconSurvival)
  c.ok("register.language",
       "return register.language{id = 'fr', name = 'Francais', base = 'en', " &
       "strings = {desktop_icon_play = 'JOUER'}}", ["\"fr\""], loading = true)
  c.ok("a mod text in it", "register.hudCard{id = 'souls', title = {en = 'Souls', es = 'Almas', fr = 'Ames'}, " &
       "draw = function() end} return #lang.list()", ["3"], loading = true)
  c.bad("en / es are not mod languages", "register.language{id = 'es'}", "built in", loading = true)
  check(t(tkDesktopIconPlay) == playEn and pickText("Souls", "Almas") == "Souls", "English until it is used")
  c.ok("lang.use", "return lang.use('fr'), lang.current()", ["true", "\"fr\""])
  check(t(tkDesktopIconPlay) == "JOUER", "its strings: " & t(tkDesktopIconPlay))
  check(t(tkDesktopIconSurvival) == survivalEn, "its gaps show the base language")
  check(pickText("Souls", "Almas") == "Ames", "a mod's own text in it: " & pickText("Souls", "Almas"))
  check(languageSetting() == "fr" and languageDisplayName("fr") == "Francais", "settings name and display name")
  check(nextLanguageSetting("spanish") == "fr" and nextLanguageSetting("fr") == "english", "the settings cycle")
  c.ok("lang.use('es')", "return lang.use('es'), lang.current()", ["true", "\"es\""])
  check(pickText("Souls", "Almas") == "Almas" and activeModLanguage == "", "a built-in language again")
  c.ok("an unknown language", "return lang.use('xx')", ["false"])
  check(getLanguage() == English, "falls back to English")
  check(useLanguage("fr"), "back to the mod language")
  dropModText(0)
  check(modLanguageIndex("fr") < 0 and t(tkDesktopIconPlay) == playEn, "its mod gone, its language goes")
  setLanguage(English)

  # ---- MODS.EXE's Console: expressions show their values, globals persist
  proc lastLog(): string = (if modLog.len > 0: modLog[^1].text else: "")
  runConsole("1 + 2")
  check(lastLog() == "= 3", "an expression shows its value: " & lastLog())
  runConsole("x = 20")
  check(lastLog() == "> x = 20", "a statement just runs: " & lastLog())
  runConsole("x + 1, 'hi'")
  check(lastLog() == "= 21, \"hi\"", "its globals persist: " & lastLog())
  runConsole("1 +")
  check(modLog[^1].level == mlError, "a syntax error is logged: " & lastLog())
  mods.setLen(0)
  resetHooks()

# --------------------------------------------------- M5: engine control ----
block engine:
  freshApi([installWorld2D, installContentApi, installModUi, installModEngine])
  let c = addMod("eng")
  c.ok("register.command", "register.command{name = 'Souls', help = 'Counts souls', " &
       "run = function(args) return {'souls: ' .. (args[1] or '0'), 'ok'} end} return 1", ["1"], loading = true)
  c.bad("command names are one word", "register.command{name = 'two words', run = function() end}", "one word", loading = true)
  var lines: seq[string]
  check(runModCommand("souls", @["7"], lines) and lines == @["souls: 7", "ok"], "the terminal runs it: " & $lines)
  check(not runModCommand("nope", @[], lines), "unknown words are not mods'")
  check(modCommandHelp().len == 1, "listed under help")

  c.bad("camera needs a run", "camera.zoom = 2", "needs a run")
  let g = newRun()
  g.player = newPlayer(100, 100)
  modBeginFrame(g)
  c.ok("camera", "camera.zoom = 2 camera.follow(true) return camera.zoom, camera.following", ["2", "true"])
  updateModCamera(g, 0.016)
  check(g.modWorld.camZoom == 2 and g.modWorld.camCurX == 256 and g.modWorld.camCurY == 192,
        "following the player, clamped inside the arena: " & $g.modWorld.camCurX & "," & $g.modWorld.camCurY)
  c.bad("zoom must be above 0", "camera.zoom = 0", "above 0")
  setWorldView(0, 0, 1)
  setWorldCamera(2, 512, 384)
  let wp = worldToVirtual(Vector2(x: 512, y: 384))
  check(abs(wp.x - 512) < 0.01 and abs(wp.y - 384) < 0.01, "the camera's centre is the screen's")
  c.ok("toWorld inverts toScreen", "local x, y = camera.toScreen(600, 400) local a, b = camera.toWorld(x, y) " &
       "return math.floor(a + 0.5), math.floor(b + 0.5)", ["600", "400"])
  clearWorldCamera()
  c.ok("reset", "camera.reset() return camera.zoom", ["1"])
  c.ok("time", "time.scale = 0.5 time.enemyScale = 0 return time.scale, time.enemyScale", ["0.5", "0"])
  check(modWorldTimeScale(g) == 0.5 and g.modWorld.enemyTimeSet, "the run's clocks")
  c.ok("hitstop / slowmo", "time.hitstop(0.1) time.slowmo(1, 0.3, true) return 1", ["1"])
  check(g.dopamine.slowMotion.active and g.dopamine.slowMotion.hitStopTimer > 0, "the game's own time layers")
  modOutsideRun(false)
  mods.setLen(0)
  resetHooks()

# ------------------------------------------------ M6: the 2D example mods ----
# The registry's examples necromancer, story_mode and chaos_engine load against the
# real API (story_mode's texture is stubbed: no GL context here) and play their
# parts through the engine's hook helpers. A fourth mod listens to the
# necromancer's events, as the example's comments invite.
block examples2d:
  if not haveExamples: break examples2d
  freshApi([installWorld2D, installContentApi, installModUi, installModEngine])
  let home = tempHome("tophat_test_home6")
  resetAdvancementCache()
  let exampleSrc = [
    ("necromancer", readFile(examplesDir / "necromancer" / "main.lua")),
    ("story_mode", readFile(examplesDir / "story_mode" / "main.lua")),
    ("chaos_engine", readFile(examplesDir / "chaos_engine" / "main.lua")),
    ("probe", "hooks.on('necromancer:raiseChance', function(c) return 1 end) " &
              "hooks.on('necromancer:raised', function(ally, e) raisedFrom = e.enemyType end) " &
              "function probe() return mods.get('necromancer').THRALL, raisedFrom end")]
  mods = @[]
  var ctxs: seq[Ctx]
  for (id, src) in exampleSrc:
    let c = addMod(id)
    ctxs.add(c)
    if id == "story_mode":
      discard runIn(c.env, "assets.texture = function(path) return {width = 48, height = 48} end")
    let (_, err) = c.run(src, loading = true)
    check(err.len == 0, id & " loads" & (if err.len > 0: ": " & err.splitLines()[0] else: ""))
  check(findStatus("necromancer:soulBurn") >= 0 and thingKinds.len == 1, "necromancer registers its status and thrall")
  check(modModes.len == 1 and modModes[0].key == "story_mode:story" and hudCardDefs.len == 1 and
        pauseActionDefs.len == 1, "story_mode registers its mode, HUD card and pause action")
  check(findShopItem("chaos_engine:stabilizer") >= 0 and findPatch("chaos_engine:entropy") >= 0 and
        findSurvivalEvent("chaos_engine:storm") >= 0 and findAdvancement("chaos_engine:survivor") >= 0 and
        findCommand("chaos") >= 0, "chaos_engine registers its shop item, patch, event, achievement and command")

  # a story run: the opening cutscene holds the run, then the dialogue, then the blessing draft
  let g = newRun()
  g.player = newPlayer(500, 400)
  g.modMode = "story_mode:story"
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
  ctxs[3].ok("other mods see the export and the event", "return probe()", ["\"necromancer:thrall\"", "\"etCircle\""])
  ctxs[0].ok("run.data counts it", "return run.data.raised, run.data.souls", ["1", "3"])

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
  mods.setLen(0)
  resetHooks()
  removeDir(home)

# ---------------------------------------------- the mixins example mod ----
# The registry's examples/mixins against the real API: its mixins wrap the game's own
# damage and offer procs, its data file counts runs, its screen opens over a
# run. (Its minimap is GL work, which needs a window: the build covers that.)
block examplesMixins:
  if not haveExamples: break examplesMixins
  freshApi([installWorld2D, installContentApi, installModUi, installModEngine, installModMixin, installModRl])
  let home = tempHome("tophat_test_home7")
  let dir = examplesDir / "mixins"
  mods = @[]
  let c = addMod("mixins", dir)
  let (_, err) = c.run(readFile(dir / "main.lua"), loading = true)
  check(err.len == 0, "mixins loads" & (if err.len > 0: ": " & err.splitLines()[0] else: ""))
  check(mixinActive("combat.damageEnemy") and mixinActive("powerup.generatePowerUpChoices"), "its mixins are on")
  let g = newRun()
  g.player = newPlayer(500, 400)
  var registeredGame {.global.}: Game   # engine.globals.game (main.nim's currentGame in the game)
  registeredGame = g
  registerModGlobal("game", addr registeredGame)
  modBeginFrame(g)   # runStart
  let runsFile = getAppDataPath() / "mod_data" / "mixins" / "runs.txt"
  check(fileExists(runsFile) and readFile(runsFile) == "1", "its data file counts the run")
  discard generatePowerUpChoices(g.player, false, {rpfCore..rpfBlood}, gmWaveBased)
  proc boss(): Enemy =
    result = newEnemy(500, 200, 1.0, etCircle, g)
    result.isBoss = true
    result.maxHp = 1000
    result.hp = 1000
  let wrapped = damageEnemy(boss(), 8)
  discard c.run("screens.go('lab')")
  applyScreenRequests(g)
  check(g.state == gsModScreen and activeScreen == "mixins:lab" and "lab opened over gsPlaying" in modLog[^1].text,
        "its screen opens over the run")
  tickModScreen(0.016)
  requestScreenBack()
  applyScreenRequests(g)
  check(g.state == gsPlaying, "and Esc's back brings the run back")
  var mixinsErrors: seq[string]
  for line in modLog:
    if line.level == mlError and line.modId == "mixins": mixinsErrors.add(line.text)
  check(mods[0].errorCount == 0, "no error from its hooks, mixins or screen: " & mixinsErrors.join(" | "))
  dropHandlersOf(0)   # the mod goes away: its mixins with it
  let plain = damageEnemy(boss(), 8)
  check(not mixinActive("combat.damageEnemy") and abs(wrapped - plain * 1.25) < 0.001,
        "the game's own damage call went through its wrap: " & $wrapped & " vs " & $plain)
  registeredGame = nil
  modOutsideRun(false)
  resetHooks()
  removeDir(home)

closeScriptVM()

# ------------------------------------------- M5: content packs (a reload) ----
# The real loader: a mod with no script, only content/*.json. (reloadMods makes
# its own VM: this block runs last.)
block contentPacks:
  let home = tempHome("tophat_test_home5")
  proc reload(id: string): (ModStatus, string) =
    reloadMods(@[id])
    for mi in installedMods:
      if mi.id == id: return (mi.status, mi.message)
  let dir = modsRootDir() / "pack"
  createDir(dir / "content" / "items")
  writeFile(dir / "mod.json", "{\"id\": \"pack\", \"name\": \"Pack\", \"version\": \"1.0.0\"}")
  writeFile(dir / "content" / "items" / "a.json",
            "[{\"type\": \"powerup\", \"id\": \"grit\", \"name\": \"Grit\", \"stats\": {\"maxHp\": \"+2\"}}," &
            " {\"type\": \"shopItem\", \"id\": \"core\", \"cost\": 5, \"stats\": {\"walls\": 2}}," &
            " {\"type\": \"consumable\", \"id\": \"mana\", \"color\": \"#4080ff\", \"stats\": {\"damage\": \"+5%\"}}]")
  writeFile(dir / "content" / "b.json", "{\"type\": \"enemy\", \"id\": \"brute\", \"base\": \"etCube\", \"hp\": 9}")
  var (st, msg) = reload("pack")
  check(st == msLoaded, "a content-only mod loads: " & msg)
  var pt: PowerUpType
  var et: EnemyType
  check(resolvePowerUpScriptName("pack:grit", pt) and findShopItem("pack:core") >= 0 and
        findConsumable("pack:mana") >= 0 and resolveEnemyName("pack:brute", et), "its content registered")
  # a bad pack fails the mod, naming the file
  writeFile(dir / "content" / "c.json", "{\"type\": \"gizmo\", \"id\": \"x\"}")
  (st, msg) = reload("pack")
  check(st == msError and "content/c.json" in msg and "unknown type" in msg, "a bad entry fails the mod: " & msg)
  check(findShopItem("pack:core") < 0, "leaving nothing behind")
  # the content_pack example (JSON only, a roster entry included)
  if haveExamples:
    copyDir(examplesDir / "content_pack", modsRootDir() / "content_pack")
    (st, msg) = reload("content_pack")
    check(st == msLoaded, "the content_pack example loads: " & msg)
    check(resolvePowerUpScriptName("content_pack:grit", pt) and resolvePowerUpScriptName("content_pack:overclock", pt) and
          findShopItem("content_pack:core") >= 0 and findConsumable("content_pack:mana") >= 0 and
          resolveEnemyName("content_pack:brute", et), "with all its content")
    check(rosterEntries.len == 1 and rosterEntries[0].et == et and rosterEntries[0].fromWave == 4,
          "and its brute in wave mode's roster")
  writeFile(dir / "content" / "c.json", "{\"type\": \"roster\", \"mode\": \"wave\", \"enemy\": \"brute\", \"often\": 1}")
  (st, msg) = reload("pack")
  check("unknown field \"often\"" in msg, "roster entries are strict: " & msg)
  removeDir(home)
  closeScriptVM()

echo passed, " passed, ", failures, " failed"
if failures > 0: quit(1)
