## The script-facing API (MODDING.md documents it for modders).
##
## Builds the userdata classes behind `game`, `player`, enemies and bullets
## (field access through mod_reflect, plus methods and x/y shortcuts) and the
## library tables every mod sees: hooks, timer, input, draw, lang, color, mods.
## installModEnv adds each mod's own `mod`, `run` and `require`.
##
## Layering: this module may import gameplay modules, but gameplay modules
## never import it (they import mod_hooks). Anything that must run inside
## game.nim (spawning into the live enemy list, starting waves, bosses) is
## queued as a ModAction and executed there, outside every entity loop.

import std/[os, strutils, tables, json, math]
import raylib
import ../types, ../particle_types, ../localization, ../render_context, ../settings, ../powerup
import ../enemy_config, ../boss_definitions, ../player, ../game/combat, ../d_systems, ../particle_pool, ../sound
import ../powerup_data, ../ui/icon_drawing, ../save_system, ../run_statistics
import mod_assets
import lua_bridge, mod_state, mod_hooks, mod_reflect, mod_deep

var
  gameMethods, playerMethods, enemyMethods, bulletMethods: ScriptTable
  textEntries: seq[tuple[lang: Language, key, value: string, owner: int]]
    ## Every string a mod added, so a mod that fails to load can be undone.

proc addModText(lang: Language, key, value: string, owner: int) =
  textEntries.add((lang, key, value, owner))
  setModTranslation(lang, key, value)

proc dropModText*(owner: int) =
  ## Forget one mod's strings and rebuild the overlay from everyone else's.
  var kept: typeof(textEntries)
  for e in textEntries:
    if e.owner != owner: kept.add(e)
  textEntries = kept
  clearModTranslations()
  for e in textEntries: setModTranslation(e.lang, e.key, e.value)

# ------------------------------------------------------------- helpers ----
proc keyName*(key: ScriptValue): string {.inline.} =
  if key.kind == vkString: key.str.s else: ""

proc requireRunGame*(vm: VM): Game =
  if modCtx.game.isNil:
    vm.runtimeError("no run in progress ('game' only exists while a run is played)")
  modCtx.game

proc selfGame(vm: VM, args: openArray[ScriptValue], fname: string): Game =
  result = unwrapGame(arg(args, 0))
  if result.isNil:
    vm.runtimeError("game:" & fname & "() needs the game (call it with ':'), and a run in progress")

proc selfPlayer(vm: VM, args: openArray[ScriptValue], fname: string): Player =
  result = unwrapPlayer(arg(args, 0))
  if result.isNil:
    vm.runtimeError("player:" & fname & "() needs a player (call it with ':')")

proc selfEnemy(vm: VM, args: openArray[ScriptValue], fname: string): Enemy =
  result = unwrapEnemy(arg(args, 0))
  if result.isNil:
    vm.runtimeError("enemy:" & fname & "() needs an enemy (call it with ':')")

proc namesTable*(names: seq[string]): ScriptValue =
  let t = newScriptTable(names.len)
  for n in names: t.add(vstr(n))
  vtable(t)

proc requireDrawing(vm: VM, fname: string) =
  if modCtx.drawing == dtNone:
    vm.runtimeError("draw." & fname & " only works inside a draw hook " &
                    "(drawWorld, drawHud, enemyDraw, playerDraw)")
  if modCtx.drawing == dtWorld3D:
    vm.runtimeError("draw." & fname & " is 2D: in world3dDraw and world3dEntityDraw " &
                    "use the draw3d library (draw.* works in world3dDrawHud)")

proc f32(vm: VM, args: openArray[ScriptValue], i: int, fname: string): float32 {.inline.} =
  vm.checkNum(args, i, fname).float32

proc creditedPowerUp(vm: VM, args: openArray[ScriptValue], i: int,
                     fname: string): tuple[has: bool, pt: PowerUpType] =
  ## The power-up a damage/heal call is credited to: an explicit name argument,
  ## else the power-up whose script is running (modCtx.source), else none.
  let v = arg(args, i)
  if v.kind == vkString:
    var pt: PowerUpType
    if not resolvePowerUpScriptName(v.str.s, pt):
      vm.argError(fname, i, "unknown power-up '" & v.str.s & "'")
    return (true, pt)
  if v.kind != vkNil:
    vm.argError(fname, i, "source must be a power-up name")
  (modCtx.hasSource, modCtx.source)

proc textPair(vm: VM, v: ScriptValue, what: string): tuple[en, es: string]
proc checkName(vm: VM, t: ScriptTable, what: string): string

# ----------------------------------------------------------- classes ----
const
  GameReadOnly = ["mode", "state", "modded", "cheatsUsed", "modFingerprint", "modMode",
                  "modRunData", "screenWidth", "screenHeight"]
  PlayerReadOnly = ["baselineMaxHp"]
  EnemyReadOnly = ["id", "enemyType", "isBoss", "bossDefinitionID", "currentPhaseIndex",
                   "bossTotalMaxHp"]

proc posGet(pos, vel: Vector2f, name: string, found: var bool): ScriptValue =
  found = true
  case name
  of "x": vnum(pos.x.float64)
  of "y": vnum(pos.y.float64)
  of "vx": vnum(vel.x.float64)
  of "vy": vnum(vel.y.float64)
  else:
    found = false
    NilValue

proc posSet(vm: VM, pos, vel: var Vector2f, name: string, v: ScriptValue): bool =
  case name
  of "x": pos.x = vm.checkNum([v], 0, "x").float32
  of "y": pos.y = vm.checkNum([v], 0, "y").float32
  of "vx": vel.x = vm.checkNum([v], 0, "vx").float32
  of "vy": vel.y = vm.checkNum([v], 0, "vy").float32
  else: return false
  true

proc makeClasses() =
  gameClass = UdClass(name: "game", cached: true)
  gameClass.index = proc (vm: VM, ud: Userdata, key: ScriptValue): ScriptValue =
    let m = rawGet(gameMethods, key)
    if m.kind != vkNil: return m
    let g = unwrapGame(vud(ud))
    if g.isNil: vm.runtimeError("no run in progress ('game' only exists while a run is played)")
    let name = keyName(key)
    if name == "player": return wrapPlayer(g.player)
    var found = false
    result = deepGet(g, name, "game", found)
    if not found: vm.runtimeError("game has no field '" & name & "'")
  gameClass.newindex = proc (vm: VM, ud: Userdata, key, val: ScriptValue) =
    let g = unwrapGame(vud(ud))
    if g.isNil: vm.runtimeError("no run in progress")
    let name = keyName(key)
    if name in GameReadOnly: vm.runtimeError("game." & name & " is read-only")
    if not deepSet(vm, g, name, val, "game"):
      vm.runtimeError("game has no field '" & name & "'")
  gameClass.tostr = proc (ud: Userdata): string = "game"

  playerClass = UdClass(name: "player", cached: true)
  playerClass.index = proc (vm: VM, ud: Userdata, key: ScriptValue): ScriptValue =
    let m = rawGet(playerMethods, key)
    if m.kind != vkNil: return m
    let p = unwrapPlayer(vud(ud))
    if p.isNil: vm.runtimeError("no run in progress ('player' only exists while a run is played)")
    let name = keyName(key)
    var found = false
    result = posGet(p.pos, p.vel, name, found)
    if found: return
    result = deepGet(p, name, "player", found)
    if not found: vm.runtimeError("player has no field '" & name & "'")
  playerClass.newindex = proc (vm: VM, ud: Userdata, key, val: ScriptValue) =
    let p = unwrapPlayer(vud(ud))
    if p.isNil: vm.runtimeError("no run in progress")
    let name = keyName(key)
    if name in PlayerReadOnly: vm.runtimeError("player." & name & " is read-only")
    if posSet(vm, p.pos, p.vel, name, val): return
    if not deepSet(vm, p, name, val, "player"):
      vm.runtimeError("player has no field '" & name & "'")
  playerClass.tostr = proc (ud: Userdata): string = "player"

  enemyClass = UdClass(name: "enemy", cached: true)
  enemyClass.index = proc (vm: VM, ud: Userdata, key: ScriptValue): ScriptValue =
    let m = rawGet(enemyMethods, key)
    if m.kind != vkNil: return m
    let e = EnemyBox(ud.box).e
    let name = keyName(key)
    if name == "type": return vstr($e.enemyType)
    var found = false
    result = posGet(e.pos, e.vel, name, found)
    if found: return
    result = deepGet(e, name, "enemy", found)
    if not found: vm.runtimeError("enemy has no field '" & name & "'")
  enemyClass.newindex = proc (vm: VM, ud: Userdata, key, val: ScriptValue) =
    let e = EnemyBox(ud.box).e
    let name = keyName(key)
    if name in EnemyReadOnly:
      vm.runtimeError("enemy." & name & " is read-only")
    if e.isBoss and name in ["hp", "maxHp"]:
      vm.runtimeError("a boss's " & name & " is read-only (use boss:damage(amount))")
    if posSet(vm, e.pos, e.vel, name, val): return
    if not deepSet(vm, e, name, val, "enemy"):
      vm.runtimeError("enemy has no field '" & name & "'")
  enemyClass.tostr = proc (ud: Userdata): string =
    let e = EnemyBox(ud.box).e
    "enemy #" & $e.id & " (" & $e.enemyType & ")"

  bulletClass = UdClass(name: "bullet", cached: true)
  bulletClass.index = proc (vm: VM, ud: Userdata, key: ScriptValue): ScriptValue =
    let m = rawGet(bulletMethods, key)
    if m.kind != vkNil: return m
    let b = BulletBox(ud.box).b
    let name = keyName(key)
    var found = false
    result = posGet(b.pos, b.vel, name, found)
    if found: return
    result = deepGet(b, name, "bullet", found)
    if not found: vm.runtimeError("bullet has no field '" & name & "'")
  bulletClass.newindex = proc (vm: VM, ud: Userdata, key, val: ScriptValue) =
    let b = BulletBox(ud.box).b
    let name = keyName(key)
    if posSet(vm, b.pos, b.vel, name, val): return
    if not deepSet(vm, b, name, val, "bullet"):
      vm.runtimeError("bullet has no field '" & name & "'")
  bulletClass.tostr = proc (ud: Userdata): string = "bullet"

# ------------------------------------------------------------ methods ----
proc installMethods() =
  gameMethods = newScriptTable()
  playerMethods = newScriptTable()
  enemyMethods = newScriptTable()
  bulletMethods = newScriptTable()

  # game.enemies / game.bullets are the live lists themselves (mod_deep):
  # #game.enemies, game.enemies[1], ipairs(...), and calling one iterates it
  # (for e in game:enemies() do ... end skips the dead).
  gameMethods.reg("enemyCount") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    let g = vm.selfGame(args, "enemyCount")
    var n = 0
    for e in g.enemies:
      if e.hp > 0: inc n
    ret.setRet(vnum(n))
  gameMethods.reg("nearestEnemy") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    let g = vm.selfGame(args, "nearestEnemy")
    let x = vm.checkNum(args, 1, "nearestEnemy")
    let y = vm.checkNum(args, 2, "nearestEnemy")
    let maxD = vm.optNum(args, 3, "nearestEnemy", 1e18)
    var best: Enemy = nil
    var bestD = maxD * maxD
    for e in g.enemies:
      if e.hp <= 0: continue
      let dx = e.pos.x.float64 - x
      let dy = e.pos.y.float64 - y
      let d = dx * dx + dy * dy
      if d < bestD:
        bestD = d
        best = e
    ret.setRet(wrapEnemy(best))
  gameMethods.reg("enemiesNear") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    let g = vm.selfGame(args, "enemiesNear")
    let x = vm.checkNum(args, 1, "enemiesNear")
    let y = vm.checkNum(args, 2, "enemiesNear")
    let r = vm.checkNum(args, 3, "enemiesNear")
    let t = newScriptTable()
    for e in g.enemies:
      if e.hp <= 0: continue
      let dx = e.pos.x.float64 - x
      let dy = e.pos.y.float64 - y
      if dx * dx + dy * dy <= r * r:
        t.add(wrapEnemy(e))
    ret.setRet(vtable(t))
  gameMethods.reg("isMode") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## game:isMode("wave" | "survival" | "roguelite" | "sandbox" | a mod mode id)
    let g = vm.selfGame(args, "isMode")
    let want = vm.checkStr(args, 1, "isMode")
    let base = case g.mode
      of gmWaveBased: "wave"
      of gmTimeSurvival: "survival"
      of gmRoguelite: "roguelite"
      of gmSandbox: "sandbox"
      of gmPvP: "pvp"
    ret.setRet(vbool(want == base or (g.modMode.len > 0 and want == g.modMode)))
  gameMethods.reg("fields") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ret.setRet(namesTable(deepNames(vm.selfGame(args, "fields"))))

  playerMethods.reg("fields") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ret.setRet(namesTable(deepNames(vm.selfPlayer(args, "fields"))))
  playerMethods.reg("powerUpLevel") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## player:powerUpLevel("puDoubleShot") -> 0 when not installed
    let p = vm.selfPlayer(args, "powerUpLevel")
    let name = vm.checkStr(args, 1, "powerUpLevel")
    var pt: PowerUpType
    if not resolvePowerUpScriptName(name, pt): vm.runtimeError("unknown power-up '" & name & "'")
    ret.setRet(vnum(getPowerUpLevel(p, pt)))
  playerMethods.reg("hasPowerUp") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    let p = vm.selfPlayer(args, "hasPowerUp")
    let name = vm.checkStr(args, 1, "hasPowerUp")
    var pt: PowerUpType
    if not resolvePowerUpScriptName(name, pt): vm.runtimeError("unknown power-up '" & name & "'")
    ret.setRet(vbool(hasPowerUp(p, pt)))

  enemyMethods.reg("fields") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ret.setRet(namesTable(deepNames(vm.selfEnemy(args, "fields"))))
  enemyMethods.reg("valid") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## Still alive and still in the current run.
    let e = vm.selfEnemy(args, "valid")
    var inRun = false
    if e.hp > 0 and not modCtx.game.isNil:
      for x in modCtx.game.enemies:
        if x == e:
          inRun = true
          break
    ret.setRet(vbool(inRun))

  bulletMethods.reg("fields") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    let b = unwrapBullet(arg(args, 0))
    if b.isNil: vm.runtimeError("bullet:fields() needs a bullet (call it with ':')")
    ret.setRet(namesTable(deepNames(b)))

# ------------------------------------------------------------ libraries ----
proc parseHook(vm: VM, name: string): ModHook =
  try:
    parseEnum[ModHook](name)
  except ValueError:
    var names: seq[string]
    for h in ModHook: names.add($h)
    vm.runtimeError("unknown hook '" & name & "' (hooks: " & names.join(", ") & ")")

proc requireOwner*(vm: VM, what: string): int =
  if currentModIdx < 0:
    vm.runtimeError(what & " must be called from mod code")
  currentModIdx

proc keyFromName(vm: VM, name: string): KeyboardKey =
  ## "space", "a", "f1", "leftShift", "1"...
  var n = name.strip()
  if n.len == 1 and n[0] in {'0'..'9'}:
    const digits = [KeyboardKey.Zero, One, Two, Three, Four, Five, Six, Seven, Eight, Nine]
    return digits[ord(n[0]) - ord('0')]
  if n.len > 0:
    n[0] = n[0].toUpperAscii
  try:
    parseEnum[KeyboardKey](n)
  except ValueError:
    vm.runtimeError("unknown key '" & name & "'")

proc mouseButtonFromArg(vm: VM, v: ScriptValue): MouseButton =
  if v.kind == vkNil: return MouseButton.Left
  if v.kind == vkString:
    case v.str.s.toLowerAscii
    of "left": return MouseButton.Left
    of "right": return MouseButton.Right
    of "middle": return MouseButton.Middle
    else: discard
  vm.runtimeError("mouse button must be \"left\", \"right\" or \"middle\"")

proc parseLanguage(vm: VM, s: string): Language =
  case s.toLowerAscii
  of "en", "english": English
  of "es", "spanish", "espanol": Spanish
  else: vm.runtimeError("unknown language '" & s & "' (use \"en\" or \"es\")")

proc installLibraries(base: ScriptTable) =
  # ---- hooks
  let hooksT = newScriptTable()
  hooksT.reg("on") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## hooks.on("update", function(game, dt) ... end)
    let owner = vm.requireOwner("hooks.on")
    let h = vm.parseHook(vm.checkStr(args, 0, "on"))
    let fn = vm.checkFunc(args, 1, "on")
    addHandler(h, fn, owner)
    ret.setRet(fn)
  hooksT.reg("off") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    let owner = vm.requireOwner("hooks.off")
    removeHandler(vm.parseHook(vm.checkStr(args, 0, "off")), vm.checkFunc(args, 1, "off"), owner)
  hooksT.reg("list") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    var names: seq[string]
    for h in ModHook: names.add($h)
    ret.setRet(namesTable(names))
  rawSet(base, vstr("hooks"), vtable(hooksT))

  # ---- timer (game time, during a run)
  let timerT = newScriptTable()
  timerT.reg("after") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    let owner = vm.requireOwner("timer.after")
    ret.setRet(vnum(addTimer(owner, vm.checkFunc(args, 1, "after"), vm.checkNum(args, 0, "after"), 0.0)))
  timerT.reg("every") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    let owner = vm.requireOwner("timer.every")
    let secs = vm.checkNum(args, 0, "every")
    if secs <= 0.0: vm.argError("every", 0, "interval must be positive")
    ret.setRet(vnum(addTimer(owner, vm.checkFunc(args, 1, "every"), secs, secs)))
  timerT.reg("cancel") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    cancelTimer(vm.checkInt(args, 0, "cancel"))
  rawSet(base, vstr("timer"), vtable(timerT))

  # ---- input
  let inputT = newScriptTable()
  inputT.reg("down") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ret.setRet(vbool(isKeyDown(vm.keyFromName(vm.checkStr(args, 0, "down")))))
  inputT.reg("pressed") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ret.setRet(vbool(isKeyPressed(vm.keyFromName(vm.checkStr(args, 0, "pressed")))))
  inputT.reg("released") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ret.setRet(vbool(isKeyReleased(vm.keyFromName(vm.checkStr(args, 0, "released")))))
  inputT.reg("mouse") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## World coordinates (the arena), like enemy and player positions.
    let p = getWorldMousePosition()
    ret.setRet([vnum(p.x.float64), vnum(p.y.float64)])
  inputT.reg("screenMouse") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## Screen (HUD) coordinates, for drawHud.
    let p = getVirtualMousePosition()
    ret.setRet([vnum(p.x.float64), vnum(p.y.float64)])
  inputT.reg("mouseDown") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ret.setRet(vbool(isMouseButtonDown(vm.mouseButtonFromArg(arg(args, 0)))))
  inputT.reg("mousePressed") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ret.setRet(vbool(isMouseButtonPressed(vm.mouseButtonFromArg(arg(args, 0)))))
  inputT.reg("action") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## input.action("dash") -> is the player's bound key for it held?
    let name = vm.checkStr(args, 0, "action")
    var a: KeyAction
    try:
      a = parseEnum[KeyAction]("ka" & name.capitalizeAscii)
    except ValueError:
      vm.runtimeError("unknown action '" & name & "' (moveUp, moveDown, moveLeft, " &
                      "moveRight, shoot, placeWall, legendary, dash)")
    let key = if globalSettings.isNil: defaultKeybinds[a] else: globalSettings.keybinds[a]
    ret.setRet(vbool(isKeyDown(key)))
  inputT.reg("bind") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    let owner = vm.requireOwner("input.bind")
    let b = modKeybindByKey(mods[owner].id & ":" & vm.checkStr(args, 0, "bind"))
    if b.isNil: vm.runtimeError("unknown mod keybind")
    ret.setRet(vbool(modKeybindActive(b)))
  inputT.reg("bindPressed") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    let owner = vm.requireOwner("input.bindPressed")
    let b = modKeybindByKey(mods[owner].id & ":" & vm.checkStr(args, 0, "bindPressed"))
    if b.isNil: vm.runtimeError("unknown mod keybind")
    ret.setRet(vbool(modKeybindPressed(b)))
  inputT.reg("bindReleased") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    let owner = vm.requireOwner("input.bindReleased")
    let b = modKeybindByKey(mods[owner].id & ":" & vm.checkStr(args, 0, "bindReleased"))
    if b.isNil: vm.runtimeError("unknown mod keybind")
    ret.setRet(vbool(modKeybindReleased(b)))
  rawSet(base, vstr("input"), vtable(inputT))

  # ---- draw (only inside draw hooks)
  let drawT = newScriptTable()
  drawT.reg("circle") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    vm.requireDrawing("circle")
    drawCircle(Vector2(x: vm.f32(args, 0, "circle"), y: vm.f32(args, 1, "circle")),
               vm.f32(args, 2, "circle"), parseColor(vm, arg(args, 3), "draw.circle"))
  drawT.reg("circleLines") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    vm.requireDrawing("circleLines")
    let r = vm.f32(args, 2, "circleLines")
    let thick = vm.optNum(args, 4, "circleLines", 1.0).float32
    drawRing(Vector2(x: vm.f32(args, 0, "circleLines"), y: vm.f32(args, 1, "circleLines")),
             max(0'f32, r - thick), r, 0, 360, 48, parseColor(vm, arg(args, 3), "draw.circleLines"))
  drawT.reg("rect") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    vm.requireDrawing("rect")
    drawRectangle(Rectangle(x: vm.f32(args, 0, "rect"), y: vm.f32(args, 1, "rect"),
                            width: vm.f32(args, 2, "rect"), height: vm.f32(args, 3, "rect")),
                  parseColor(vm, arg(args, 4), "draw.rect"))
  drawT.reg("rectLines") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    vm.requireDrawing("rectLines")
    drawRectangleLines(Rectangle(x: vm.f32(args, 0, "rectLines"), y: vm.f32(args, 1, "rectLines"),
                                 width: vm.f32(args, 2, "rectLines"), height: vm.f32(args, 3, "rectLines")),
                       vm.optNum(args, 5, "rectLines", 1.0).float32,
                       parseColor(vm, arg(args, 4), "draw.rectLines"))
  drawT.reg("line") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    vm.requireDrawing("line")
    drawLine(Vector2(x: vm.f32(args, 0, "line"), y: vm.f32(args, 1, "line")),
             Vector2(x: vm.f32(args, 2, "line"), y: vm.f32(args, 3, "line")),
             vm.optNum(args, 5, "line", 1.0).float32, parseColor(vm, arg(args, 4), "draw.line"))
  drawT.reg("poly") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## draw.poly(x, y, sides, radius, rotationDegrees, color)
    vm.requireDrawing("poly")
    let sides = vm.checkInt(args, 2, "poly")
    if sides < 3 or sides > 64: vm.argError("poly", 2, "sides must be 3-64")
    drawPoly(Vector2(x: vm.f32(args, 0, "poly"), y: vm.f32(args, 1, "poly")), sides.int32,
             vm.f32(args, 3, "poly"), vm.f32(args, 4, "poly"), parseColor(vm, arg(args, 5), "draw.poly"))
  drawT.reg("text") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## draw.text(text, x, y, size, color) -> width in pixels
    vm.requireDrawing("text")
    let s = vm.checkStr(args, 0, "text")
    let size = clamp(vm.checkInt(args, 3, "text"), 10, 200).int32
    drawText(s, vm.checkInt(args, 1, "text").int32, vm.checkInt(args, 2, "text").int32, size,
             parseColor(vm, arg(args, 4), "draw.text"))
    ret.setRet(vnum(measureText(s, size).int))
  drawT.reg("arena") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## In drawHud: x, y, w, h of the arena on screen (the docks sit outside it).
    ## In drawWorld: 0, 0 and the arena size.
    vm.requireDrawing("arena")
    if modCtx.drawing == dtWorld:
      let g = modCtx.game
      ret.setRet([vnum(0), vnum(0), vnum(if g.isNil: 1024 else: g.screenWidth.int),
                  vnum(if g.isNil: 768 else: g.screenHeight.int)])
    else:
      let a = modCtx.hudArena
      ret.setRet([vnum(a.x), vnum(a.y), vnum(a.w), vnum(a.h)])
  drawT.reg("textWidth") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    let size = clamp(vm.optInt(args, 1, "textWidth", 10), 10, 200).int32
    ret.setRet(vnum(measureText(vm.checkStr(args, 0, "textWidth"), size).int))
  rawSet(base, vstr("draw"), vtable(drawT))

  # ---- hud: hide built-in HUD pieces to draw your own (drawHud)
  let hudT = newScriptTable()
  proc hudPart(vm: VM, args: openArray[ScriptValue], fname: string): HudPart =
    let name = vm.checkStr(args, 0, fname)
    try:
      parseEnum[HudPart](name)
    except ValueError:
      var names: seq[string]
      for p in HudPart: names.add($p)
      vm.argError(fname, 0, "unknown HUD part '" & name & "' (" & names.join(", ") & ")")
  hudT.reg("hide") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## hud.hide("boss") -- until hud.show or the next run (every run starts full)
    hiddenHud.incl(vm.hudPart(args, "hide"))
  hudT.reg("show") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    hiddenHud.excl(vm.hudPart(args, "show"))
  hudT.reg("hidden") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ret.setRet(vbool(hudHidden(vm.hudPart(args, "hidden"))))
  hudT.reg("parts") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    var names: seq[string]
    for p in HudPart: names.add($p)
    ret.setRet(namesTable(names))
  rawSet(base, vstr("hud"), vtable(hudT))

  # ---- color
  let colorT = newScriptTable()
  colorT.reg("rgb") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ret.setRet(colorValue(Color(r: uint8(clamp(vm.checkInt(args, 0, "rgb"), 0, 255)),
                                g: uint8(clamp(vm.checkInt(args, 1, "rgb"), 0, 255)),
                                b: uint8(clamp(vm.checkInt(args, 2, "rgb"), 0, 255)),
                                a: uint8(clamp(vm.optInt(args, 3, "rgb", 255), 0, 255)))))
  colorT.reg("hex") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ret.setRet(colorValue(parseColor(vm, arg(args, 0), "color.hex")))
  rawSet(base, vstr("color"), vtable(colorT))

  # ---- lang
  let langT = newScriptTable()
  langT.reg("text") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ret.setRet(vstr(t(vm.checkStr(args, 0, "text"))))
  langT.reg("current") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ret.setRet(vstr(if getLanguage() == Spanish: "es" else: "en"))
  langT.reg("set") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## lang.set("en", "my_key", "Text") -- also overrides built-in strings
    let owner = vm.requireOwner("lang.set")
    addModText(vm.parseLanguage(vm.checkStr(args, 0, "set")),
               vm.checkStr(args, 1, "set"), vm.checkStr(args, 2, "set"), owner)
  langT.reg("add") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## lang.add({en = {key = "Text"}, es = {key = "Texto"}})
    let owner = vm.requireOwner("lang.add")
    let t = vm.checkTable(args, 0, "add")
    for (lk, lv) in pairsCursor(t):
      if lk.kind != vkString or lv.kind != vkTable:
        vm.runtimeError("lang.add expects {en = {key = text}, es = {...}}")
      let language = vm.parseLanguage(lk.str.s)
      for (k, v) in pairsCursor(lv.tbl):
        if k.kind == vkString and v.kind == vkString:
          addModText(language, k.str.s, v.str.s, owner)
  rawSet(base, vstr("lang"), vtable(langT))

  # ---- mods (inter-mod API)
  let modsT = newScriptTable()
  modsT.reg("export") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## mods.export(value): what other mods get from mods.get("<your id>")
    let owner = vm.requireOwner("mods.export")
    mods[owner].exports = arg(args, 0)
  modsT.reg("get") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    let id = vm.checkStr(args, 0, "get")
    for m in mods:
      if m.id == id and not m.disabled:
        ret.setRet(m.exports)
        return
    ret.setRet(NilValue)
  modsT.reg("isLoaded") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ret.setRet(vbool(vm.checkStr(args, 0, "isLoaded") in loadedModIds))
  modsT.reg("list") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    var ids: seq[string]
    for m in mods:
      if not m.disabled: ids.add(m.id)
    ret.setRet(namesTable(ids))
  rawSet(base, vstr("mods"), vtable(modsT))

  # ---- the current run
  rawSet(base, vstr("game"), vud(Userdata(cls: gameClass, box: GameBox(g: nil), key: nil)))
  rawSet(base, vstr("player"), vud(Userdata(cls: playerClass, box: PlayerBox(p: nil), key: nil)))

# =============================================================== content ====
# spawn / fx / enemies / bosses / override / register. Everything here that
# changes game content is recorded against the mod that did it, so a mod
# that fails while loading leaves nothing behind (dropModContent).

var
  enemyOverrides: seq[tuple[et: EnemyType, fields: ScriptTable, owner: int]]
  bossOwners: Table[int, int]     ## boss ID -> the mod that registered/replaced it
  nextModBossId = ModBossIdBase

proc applyEnemyOverrides(et: EnemyType, cfg: var EnemyConfig) {.nimcall.} =
  for o in enemyOverrides:
    if o.et == et:
      try:
        applyTable(modVM, cfg, o.fields, "override.enemy")
      except ScriptError:
        discard  # validated when registered

proc resolveEnemyNameImpl(name: string, et: var EnemyType): bool {.nimcall.} =
  try:
    et = parseEnum[EnemyType](name)
    et != etEnvironment
  except ValueError:
    false

proc resetNewContent()
proc dropNewContent(owner: int)

proc resetModContent*() =
  ## Loader: forget every piece of mod content (a fresh set registers next).
  enemyOverrides.setLen(0)
  bossOwners.clear()
  nextModBossId = ModBossIdBase
  clearModBosses()
  clearModRoutes()
  enemyConfigOverride = applyEnemyOverrides
  enemyNameResolver = resolveEnemyNameImpl
  resetNewContent()
  invalidateEnemyConfigCache()

proc dropModContent*(owner: int) =
  ## Loader: a mod failed while loading, so everything it registered goes.
  var kept: typeof(enemyOverrides)
  for o in enemyOverrides:
    if o.owner != owner: kept.add(o)
  enemyOverrides = kept
  var gone: seq[int]
  for id, o in bossOwners:
    if o == owner: gone.add(id)
  for id in gone:
    bossOwners.del(id)
    modBossDefs.del(id)
    modBossSlotWaves.del(id)
    modBossProcessNames.del(id)
  dropRoutesOf(owner)
  dropNewContent(owner)
  invalidateEnemyConfigCache()

proc checkEnemyType(vm: VM, args: openArray[ScriptValue], i: int, fname: string): EnemyType =
  let name = vm.checkStr(args, i, fname)
  if not resolveEnemyName(name, result):
    vm.argError(fname, i, "unknown enemy type '" & name & "' (enemies.types() lists them)")

proc checkBossId(vm: VM, args: openArray[ScriptValue], i: int, fname: string): int =
  result = vm.checkInt(args, i, fname)
  if result notin 1..MaxBossId and not hasModBoss(result):
    vm.argError(fname, i, "unknown boss id " & $result)

# ---- bosses from tables
const
  AttackDefaults = BossAttack(attackType: bapBurst, damage: 1.0, cooldown: 2.0,
                              projectileSpeed: 180.0, projectileCount: 8)
  WeakPointDefaults = BossWeakPointDefinition(requiredHits: 3, targetCount: 3,
    bodyDamageMultiplier: 0.35, weakCoreMultiplier: 2.5, exposureDuration: 3.5,
    cooldownDuration: 4.0, targetHitRadius: 18.0)

proc attackFromTable(vm: VM, t: ScriptTable, bossKey, what: string): BossAttack =
  result = AttackDefaults
  applyTable(vm, result, t, what, skip = ["type", "special"])
  let ty = rawGetStr(t, "type")
  if ty.kind == vkString:
    let s = ty.str.s
    if s.startsWith("mod:"):
      # A scripted attack of this boss: routed to its `attacks` table.
      result.attackType = bapBurst
      result.specialData = "mod:" & bossKey & ":" & s[4 .. ^1]
    else:
      try:
        result.attackType = parseEnum[BossAttackPattern](s)
      except ValueError:
        vm.runtimeError(what & ": unknown attack type '" & s & "' (bapSpiral, bapBurst, ...; or \"mod:<name>\")")
  let sp = rawGetStr(t, "special")
  if sp.kind == vkString and not result.specialData.startsWith("mod:"):
    result.specialData = sp.str.s

proc bossFromTable(vm: VM, t: ScriptTable, base: BossDefinition, id: int, owner: int): BossDefinition =
  result = base
  result.bossID = id
  let bossKey = $id
  applyTable(vm, result, t, "boss", skip = ["id", "hp", "speed", "damage", "radius", "phases",
                                             "weakPoint", "draw", "attacks", "behaviors",
                                             "process", "slotWave"])
  # Friendly aliases for the base stats.
  if rawGetStr(t, "hp").kind != vkNil: result.baseHP = vm.checkNum([rawGetStr(t, "hp")], 0, "hp").float32
  if rawGetStr(t, "speed").kind != vkNil: result.baseSpeed = vm.checkNum([rawGetStr(t, "speed")], 0, "speed").float32
  if rawGetStr(t, "damage").kind != vkNil: result.baseDamage = vm.checkInt([rawGetStr(t, "damage")], 0, "damage")
  if rawGetStr(t, "radius").kind != vkNil: result.baseRadius = vm.checkNum([rawGetStr(t, "radius")], 0, "radius").float32
  let wp = rawGetStr(t, "weakPoint")
  if wp.kind == vkTable:
    let kind = rawGetStr(wp.tbl, "kind")
    if kind.kind == vkString and kind.str.s != "bwoNone" and result.weakPoint.kind == bwoNone:
      result.weakPoint = WeakPointDefaults
    applyTable(vm, result.weakPoint, wp.tbl, "boss.weakPoint")
  let phases = rawGetStr(t, "phases")
  if phases.kind == vkTable:
    let n = phases.tbl.len
    if n == 0: vm.runtimeError("boss.phases needs at least one phase")
    result.phases.setLen(0)
    for i in 0 ..< n:
      let pv = phases.tbl.item(i + 1)
      if pv.kind != vkTable: vm.runtimeError("boss.phases[" & $(i + 1) & "] must be a table")
      var ph = BossPhaseDefinition(name: "PHASE " & $(i + 1),
                                   hpThreshold: 1.0'f32 - i.float32 / n.float32,
                                   speedMultiplier: 1.0, damageMultiplier: 1.0,
                                   defenseMultiplier: 1.0, color: result.color)
      let what = "boss.phases[" & $(i + 1) & "]"
      applyTable(vm, ph, pv.tbl, what, skip = ["attacks", "behavior"])
      let beh = rawGetStr(pv.tbl, "behavior")
      if beh.kind == vkString:
        ph.specialBehavior = if beh.str.s.startsWith("mod:"): "mod:" & bossKey & ":" & beh.str.s[4 .. ^1]
                             else: beh.str.s
      let atks = rawGetStr(pv.tbl, "attacks")
      if atks.kind == vkTable:
        for j in 0 ..< atks.tbl.len:
          let av = atks.tbl.item(j + 1)
          if av.kind != vkTable: vm.runtimeError(what & ".attacks[" & $(j + 1) & "] must be a table")
          ph.attacks.add(attackFromTable(vm, av.tbl, bossKey, what & ".attacks[" & $(j + 1) & "]"))
      result.phases.add(ph)
  # Script routes: attacks = {name = fn}, behaviors = {name = fn}, draw = fn
  for (key, fnTable) in [("attacks", 0), ("behaviors", 1)]:
    let fns = rawGetStr(t, key)
    if fns.kind == vkTable:
      for (k, f) in pairsCursor(fns.tbl):
        if k.kind != vkString or f.kind notin {vkFunction, vkNative}:
          vm.runtimeError("boss." & key & " must map names to functions")
        let route = "mod:" & bossKey & ":" & k.str.s
        if fnTable == 0: bossAttackFns[route] = ScriptFn(owner: owner, fn: f)
        else: bossBehaviorFns[route] = ScriptFn(owner: owner, fn: f)
  let draw = rawGetStr(t, "draw")
  if draw.kind in {vkFunction, vkNative}:
    bossDrawFns[id] = ScriptFn(owner: owner, fn: draw)
  let process = rawGetStr(t, "process")
  if process.kind == vkString:
    modBossProcessNames[id] = process.str.s
  let slot = rawGetStr(t, "slotWave")
  if slot.kind == vkNumber:
    modBossSlotWaves[id] = max(5, int(slot.n))
  if result.phases.len == 0:
    vm.runtimeError("boss needs phases = { {attacks = {...}}, ... }")

proc installContentLibraries(base: ScriptTable) =
  # ---- spawn (carried out at the end of the frame, see processModActions)
  let spawnT = newScriptTable()
  spawnT.reg("enemy") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## spawn.enemy("etCube", x, y [, {elite = true, difficulty = 3, onSpawn = fn}])
    let owner = vm.requireOwner("spawn.enemy")
    discard vm.requireRunGame()
    var a = ModAction(kind: makSpawnEnemy, owner: owner, difficulty: -1,
                      enemyType: vm.checkEnemyType(args, 0, "enemy"),
                      x: vm.checkNum(args, 1, "enemy").float32, y: vm.checkNum(args, 2, "enemy").float32)
    let opts = arg(args, 3)
    if opts.kind == vkTable:
      a.elite = truthy(rawGetStr(opts.tbl, "elite"))
      let d = rawGetStr(opts.tbl, "difficulty")
      if d.kind == vkNumber: a.difficulty = max(0.0, d.n).float32
      a.callback = rawGetStr(opts.tbl, "onSpawn")
    queueModAction(a)
  spawnT.reg("boss") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## spawn.boss(id [, {x = .., y = .., onSpawn = fn}])
    let owner = vm.requireOwner("spawn.boss")
    discard vm.requireRunGame()
    var a = ModAction(kind: makSpawnBoss, owner: owner, bossId: vm.checkBossId(args, 0, "boss"))
    let opts = arg(args, 1)
    if opts.kind == vkTable:
      let x = rawGetStr(opts.tbl, "x")
      let y = rawGetStr(opts.tbl, "y")
      if x.kind == vkNumber and y.kind == vkNumber:
        a.x = x.n.float32
        a.y = y.n.float32
      a.callback = rawGetStr(opts.tbl, "onSpawn")
    queueModAction(a)
  spawnT.reg("bullet") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## spawn.bullet{x = .., y = .., vx = .., vy = .., damage = 1, radius = 6,
    ##              lifetime = 3, fromPlayer = false, color = "#ff4040"}
    let owner = vm.requireOwner("spawn.bullet")
    discard vm.requireRunGame()
    let t = vm.checkTable(args, 0, "bullet")
    proc num(key: string, def: float64): float32 =
      let v = rawGetStr(t, key)
      if v.kind == vkNumber: v.n.float32 else: def.float32
    var a = ModAction(kind: makSpawnBullet, owner: owner, x: num("x", 0), y: num("y", 0),
                      vx: num("vx", 0), vy: num("vy", 200), damage: num("damage", 1),
                      radius: num("radius", 0), lifetime: num("lifetime", 0),
                      fromPlayer: truthy(rawGetStr(t, "fromPlayer")))
    let c = rawGetStr(t, "color")
    if c.kind != vkNil:
      a.color = parseColor(vm, c, "spawn.bullet")
      a.hasColor = true
    queueModAction(a)
  spawnT.reg("coin") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## spawn.coin(x, y [, value])
    discard vm.requireRunGame()
    queueModAction(ModAction(kind: makSpawnCoin, owner: vm.requireOwner("spawn.coin"),
                             x: vm.f32(args, 0, "coin"), y: vm.f32(args, 1, "coin"),
                             value: vm.optInt(args, 2, "coin", 1)))
  spawnT.reg("xp") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## spawn.xp(x, y [, value])
    discard vm.requireRunGame()
    queueModAction(ModAction(kind: makSpawnXp, owner: vm.requireOwner("spawn.xp"),
                             x: vm.f32(args, 0, "xp"), y: vm.f32(args, 1, "xp"),
                             value: vm.optInt(args, 2, "xp", 1)))
  spawnT.reg("consumable") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## spawn.consumable("ctHealth", x, y)
    discard vm.requireRunGame()
    let name = vm.checkStr(args, 0, "consumable")
    var ct: ConsumableType
    try: ct = parseEnum[ConsumableType](name)
    except ValueError:
      var names: seq[string]
      for c in ConsumableType: names.add($c)
      vm.argError("consumable", 0, "unknown consumable (" & names.join(", ") & ")")
    queueModAction(ModAction(kind: makSpawnConsumable, owner: vm.requireOwner("spawn.consumable"),
                             consumable: ct, x: vm.f32(args, 1, "consumable"),
                             y: vm.f32(args, 2, "consumable")))
  rawSet(base, vstr("spawn"), vtable(spawnT))

  # ---- enemy / player actions
  enemyMethods.reg("damage") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## enemy:damage(amount [, source]) -> damage actually dealt (bosses: their
    ## phase pool). `source` is a power-up name to credit in the run stats;
    ## inside a power-up's own update/onHit/onPickup it is that power-up.
    let e = vm.selfEnemy(args, "damage")
    let src = vm.creditedPowerUp(args, 2, "damage")
    let dealt = applyEnemyHpDamage(e, max(0.0, vm.checkNum(args, 1, "damage")).float32)
    if src.has and dealt > 0 and not modCtx.game.isNil:
      trackPowerUpDamage(modCtx.game, src.pt, dealt)
    ret.setRet(vnum(dealt.float64))
  enemyMethods.reg("kill") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## Dies this frame with the normal rewards. Bosses: use boss:damage(n).
    let e = vm.selfEnemy(args, "kill")
    if e.isBoss: vm.runtimeError("a boss cannot be killed outright; use boss:damage(amount)")
    e.hp = 0
    if e.requiredHits > 0: e.hitCount = max(e.hitCount, e.requiredHits)
  enemyMethods.reg("remove") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## Vanishes at the end of the frame: no death, no rewards. Not for bosses.
    let e = vm.selfEnemy(args, "remove")
    if e.isBoss: vm.runtimeError("a boss cannot be removed")
    queueModAction(ModAction(kind: makRemoveEnemy, owner: vm.requireOwner("enemy:remove"), target: e))
  enemyMethods.reg("heal") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    let e = vm.selfEnemy(args, "heal")
    if e.isBoss: vm.runtimeError("a boss cannot be healed by mods")
    e.hp = min(e.maxHp, e.hp + max(0.0, vm.checkNum(args, 1, "heal")).float32)
  playerMethods.reg("heal") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## player:heal(amount [, source]) -> HP actually restored. `source` credits
    ## a power-up's healing, like enemy:damage.
    let p = vm.selfPlayer(args, "heal")
    let src = vm.creditedPowerUp(args, 2, "heal")
    let requested = max(0.0, vm.checkNum(args, 1, "heal")).float32
    let restored = heal(p, requested)
    if src.has and not modCtx.game.isNil and modCtx.game.player == p:
      trackHealing(modCtx.game, src.pt, requested, restored)
    ret.setRet(vnum(restored.float64))
  playerMethods.reg("hurt") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## player:hurt(amount) -> true if it was lethal (profile difficulty applies)
    let p = vm.selfPlayer(args, "hurt")
    ret.setRet(vbool(takeDamage(p, max(0.0, vm.checkNum(args, 1, "hurt")).float32)))

  # ---- run control (queued: carried out after the simulation, this frame)
  proc checkPowerUp(vm: VM, args: openArray[ScriptValue], i: int, fname: string): PowerUpType =
    let name = vm.checkStr(args, i, fname)
    if not resolvePowerUpScriptName(name, result):
      vm.argError(fname, i, "unknown power-up '" & name & "' (powerups.list())")
  playerMethods.reg("give") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## player:give("puDoubleShot" [, level]) -- installs it (one level up, or
    ## up to `level`), with its normal pickup effects.
    discard vm.selfPlayer(args, "give")
    discard vm.requireRunGame()
    queueModAction(ModAction(kind: makGivePowerUp, owner: vm.requireOwner("player:give"),
                             powerType: vm.checkPowerUp(args, 1, "give"),
                             level: vm.optInt(args, 2, "give", 0)))
  playerMethods.reg("take") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## player:take("puDoubleShot") -- removes it from the player's list (what it
    ## does while owned stops; one-off stat gains from picking it up stay).
    discard vm.selfPlayer(args, "take")
    discard vm.requireRunGame()
    queueModAction(ModAction(kind: makTakePowerUp, owner: vm.requireOwner("player:take"),
                             powerType: vm.checkPowerUp(args, 1, "take")))
  template runAction(name: string, k: ModActionKind) =
    gameMethods.reg(name) do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
      discard vm.selfGame(args, name)
      queueModAction(ModAction(kind: k, owner: vm.requireOwner("game:" & name),
                               value: vm.optInt(args, 1, name, 1)))
  runAction("startWave", makStartWave)     # game:startWave()
  runAction("endWave", makEndWave)         # game:endWave(): no more spawns, regular enemies gone
  runAction("win", makWin)                 # game:win(): the run is won (victory screen)
  runAction("lose", makLose)               # game:lose(): the player dies (normal death path)
  runAction("powerUpDraft", makPowerUpDraft)  # game:powerUpDraft([count]): level-up drafts
  bulletMethods.reg("remove") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## bullet:remove() -- gone at the end of the frame.
    let b = unwrapBullet(arg(args, 0))
    if b.isNil: vm.runtimeError("bullet:remove() needs a bullet (call it with ':')")
    queueModAction(ModAction(kind: makRemoveBullet, owner: vm.requireOwner("bullet:remove"), bullet: b))

  # ---- fx
  let fxT = newScriptTable()
  fxT.reg("shake") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## fx.shake("small" | "medium" | "large" | "massive")
    let g = vm.requireRunGame()
    let name = vm.optStr(args, 0, "shake", "medium")
    try:
      addShake(g.dopamine.screenShake, parseEnum[ShakeIntensity]("si" & name.capitalizeAscii))
    except ValueError:
      vm.argError("shake", 0, "use \"small\", \"medium\", \"large\" or \"massive\"")
  fxT.reg("particles") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## fx.particles(x, y, color [, count])
    let g = vm.requireRunGame()
    spawnExplosionPooled(g.particlePool, vm.checkNum(args, 0, "particles").float32,
                         vm.checkNum(args, 1, "particles").float32,
                         parseColor(vm, arg(args, 2), "fx.particles"),
                         clamp(vm.optInt(args, 3, "particles", 20), 1, 200))
  fxT.reg("damageNumber") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## fx.damageNumber(x, y, amount [, critical])
    let g = vm.requireRunGame()
    showDamage(g, newVector2f(vm.checkNum(args, 0, "damageNumber").float32,
                              vm.checkNum(args, 1, "damageNumber").float32),
               vm.checkNum(args, 2, "damageNumber").float32, fromPlayer = true,
               isCritical = truthy(arg(args, 3)))
  fxT.reg("sound") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## fx.sound("explosion" [, volume, pitch]) -- the game's built-in sounds
    let name = vm.checkStr(args, 0, "sound")
    try:
      playSound(parseEnum[SoundType]("st" & name.capitalizeAscii),
                vm.optNum(args, 1, "sound", 1.0).float32, vm.optNum(args, 2, "sound", 1.0).float32)
    except ValueError:
      var names: seq[string]
      for s in SoundType: names.add(($s)[2 .. ^1])
      vm.argError("sound", 0, "unknown sound (" & names.join(", ") & ")")
  rawSet(base, vstr("fx"), vtable(fxT))

  # ---- enemies / bosses (lookups)
  let enemiesT = newScriptTable()
  enemiesT.reg("types") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    var names: seq[string]
    for et in EnemyType:
      if et == etEnvironment: continue
      var probe: EnemyType
      let n = enemyTypeName(et)
      if resolveEnemyName(n, probe): names.add(n)
    ret.setRet(namesTable(names))
  enemiesT.reg("config") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## A copy of an enemy type's stats, in the shape override.enemy takes.
    ret.setRet(objToValue(getEnemyConfig(vm.checkEnemyType(args, 0, "config"))))
  rawSet(base, vstr("enemies"), vtable(enemiesT))
  let bossesT = newScriptTable()
  bossesT.reg("get") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## A copy of a boss definition (phases, attacks...), handy to start from.
    ret.setRet(objToValue(getBossDefinition(vm.checkBossId(args, 0, "get"))))
  bossesT.reg("ids") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    let t = newScriptTable()
    for id in 1..MaxBossId: t.add(vnum(id))
    for id in ModBossIdBase ..< nextModBossId:
      if hasModBoss(id): t.add(vnum(id))
    ret.setRet(vtable(t))
  rawSet(base, vstr("bosses"), vtable(bossesT))

  # ---- override
  let overrideT = newScriptTable()
  overrideT.reg("enemy") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## override.enemy("etCircle", {baseHP = 3, baseColor = "#40ff80",
    ##                             movement = {baseSpeed = 160}})
    ## override.enemy("etCube", {update = function(e, dt, game) ... return true end,
    ##                           draw = function(e) ... end})  -- scripted AI / look
    let owner = vm.requireOwner("override.enemy")
    let et = vm.checkEnemyType(args, 0, "enemy")
    let src = vm.checkTable(args, 1, "enemy")
    # Behaviour functions go to the per-type script routes; the rest is config.
    let fields = newScriptTable()
    for (k, v) in pairsCursor(src):
      if k.kind == vkString and k.str.s in ["update", "draw"]:
        if v.kind notin {vkFunction, vkNative}:
          vm.runtimeError("override.enemy: " & k.str.s & " must be a function")
        if k.str.s == "update": enemyUpdateFns[ord(et)] = ScriptFn(owner: owner, fn: v)
        else: enemyDrawFns[ord(et)] = ScriptFn(owner: owner, fn: v)
      else:
        rawSet(fields, k, v)
    var probe = vanillaEnemyConfig(et)
    applyTable(vm, probe, fields, "override.enemy(\"" & $et & "\")")  # validate now
    enemyOverrides.add((et, fields, owner))
    invalidateEnemyConfigCache()
  overrideT.reg("boss") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## override.boss(5, {hp = 900, phases = {...}}) -- replaces what you give
    let owner = vm.requireOwner("override.boss")
    let id = vm.checkBossId(args, 0, "boss")
    let def = bossFromTable(vm, vm.checkTable(args, 1, "boss"), getBossDefinition(id), id, owner)
    modBossDefs[id] = def
    bossOwners[id] = owner
  overrideT.reg("text") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    let owner = vm.requireOwner("override.text")
    addModText(vm.parseLanguage(vm.checkStr(args, 0, "text")),
               vm.checkStr(args, 1, "text"), vm.checkStr(args, 2, "text"), owner)
  rawSet(base, vstr("override"), vtable(overrideT))

  # ---- register
  let registerT = newScriptTable()
  registerT.reg("keybind") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    let owner = vm.requireOwner("register.keybind")
    let t = vm.checkTable(args, 0, "register.keybind")
    let actionId = vm.checkName(t, "register.keybind")
    let key = modKeybindKey(mods[owner].id, actionId)
    if modKeybindByKey(key) != nil:
      vm.runtimeError("register.keybind: '" & key & "' is already registered")
    let defaultValue = rawGetStr(t, "default")
    if defaultValue.kind != vkString:
      vm.runtimeError("register.keybind: default must be a keyboard key name")
    let keyboard = vm.keyFromName(defaultValue.str.s)
    var pad = GamepadButton.Unknown
    let padValue = rawGetStr(t, "gamepad")
    if padValue.kind == vkString:
      try: pad = parseEnum[GamepadButton](padValue.str.s)
      except ValueError: vm.runtimeError("register.keybind: unknown gamepad button")
    let (nameEn, nameEs) = vm.textPair(rawGetStr(t, "name"), "name")
    let b = ModKeybind(key: key, owner: owner, modId: mods[owner].id,
                       actionId: actionId, nameEn: nameEn, nameEs: nameEs,
                       defaultKey: keyboard, defaultPad: pad,
                       keyBind: keyboard, padBind: pad)
    modKeybinds.add(b)
    restoreModKeybind(b)
    ret.setRet(vstr(key))
  registerT.reg("boss") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## local id = register.boss{name = "OVERCLOCK", hp = 600, phases = {...}}
    let owner = vm.requireOwner("register.boss")
    let t = vm.checkTable(args, 0, "boss")
    let id = nextModBossId
    inc nextModBossId
    let name = rawGetStr(t, "name")
    var base = BossDefinition(name: (if name.kind == vkString: name.str.s else: mods[owner].name),
                              baseHP: 400, baseSpeed: 60, baseDamage: 1, baseRadius: 40,
                              color: Color(r: 255, g: 90, b: 90, a: 255))
    let def = bossFromTable(vm, t, base, id, owner)
    modBossDefs[id] = def
    bossOwners[id] = owner
    if not modBossProcessNames.hasKey(id):
      modBossProcessNames[id] = mods[owner].id & ".sys"
    if not modBossSlotWaves.hasKey(id):
      modBossSlotWaves[id] = 25
    ret.setRet(vnum(id))
  rawSet(base, vstr("register"), vtable(registerT))

# ============================================================ new content ====
# register.powerup / register.enemy bind the reserved enum slots (in
# registration order, so the same mod set always binds the same slots), and
# roster.add mixes mod enemies into a mode's spawn picks.

type ModPowerUpScript = object
  owner: int
  nameEn, nameEs: string
  descEn, descEs: seq[string]  ## per level (the last one repeats)
  descFn: ScriptValue          ## or function(level) -> string
  icon: ScriptValue            ## function(color) drawing in a 32x32 box
  onPickup: ScriptValue        ## function(player, level, game)

var
  puScripts: array[ModPowerUpSlot, ModPowerUpScript]
  enemyOwners: array[ModEnemySlot, int]

proc textPair(vm: VM, v: ScriptValue, what: string): tuple[en, es: string] =
  ## "Text" or {en = "Text", es = "Texto"}.
  case v.kind
  of vkString: (v.str.s, "")
  of vkTable:
    let en = rawGetStr(v.tbl, "en")
    let es = rawGetStr(v.tbl, "es")
    ((if en.kind == vkString: en.str.s else: ""), (if es.kind == vkString: es.str.s else: ""))
  of vkNil: ("", "")
  else: vm.runtimeError(what & " must be a string or {en = .., es = ..}")

proc textList(vm: VM, v: ScriptValue, what: string): seq[string] =
  case v.kind
  of vkString: result = @[v.str.s]
  of vkTable:
    for x in v.tbl:
      if x.kind != vkString: vm.runtimeError(what & " entries must be strings")
      result.add(x.str.s)
  of vkNil: discard
  else: vm.runtimeError(what & " must be a string or a list of strings")

proc pickLang(en, es: string): string {.inline.} =
  if getLanguage() == Spanish and es.len > 0: es else: en

proc modPowerUpTextImpl(pt: PowerUpType, level: int, wantName: bool): string {.nimcall.} =
  if not isModPowerUp(pt): return ""
  let s = puScripts[pt]
  if wantName:
    return pickLang(s.nameEn, s.nameEs)
  if s.descFn.kind in {vkFunction, vkNative}:
    var r: RetVals
    if callAs(s.owner, s.descFn, [vnum(level)], r) and r.count > 0 and r.first.kind == vkString:
      return r.first.str.s
    return ""
  let list = if getLanguage() == Spanish and s.descEs.len > 0: s.descEs else: s.descEn
  if list.len == 0: return ""
  list[clamp(level - 1, 0, list.high)]

proc modPowerUpAppliedImpl(player: Player, pt: PowerUpType, level: int) {.nimcall.} =
  if not isModPowerUp(pt): return
  let s = puScripts[pt]
  if s.onPickup.kind in {vkFunction, vkNative}:
    var r: RetVals
    discard callForPowerUp(pt, ScriptFn(owner: s.owner, fn: s.onPickup),
                           [wrapPlayer(player), vnum(level), wrapGame(modCtx.game)], r)

proc modPowerUpIconImpl(pt: PowerUpType, color: Color): bool {.nimcall.} =
  if not isModPowerUp(pt): return false
  let s = puScripts[pt]
  if s.icon.kind notin {vkFunction, vkNative}: return false
  let prev = modCtx.drawing
  modCtx.drawing = dtHud
  defer: modCtx.drawing = prev
  var r: RetVals
  callAs(s.owner, s.icon, [colorValue(color)], r)

proc enemyNamerImpl(et: EnemyType): string {.nimcall.} = enemyScriptName(et)
proc enemyResolverImpl(name: string, et: var EnemyType): bool {.nimcall.} =
  resolveEnemyScriptName(name, et)

proc resetNewContent() =
  resetPowerUpDefs()
  resetModEnemies()
  for pt in ModPowerUpSlot: puScripts[pt] = ModPowerUpScript()
  for et in ModEnemySlot: enemyOwners[et] = -1
  modPowerUpText = modPowerUpTextImpl
  modPowerUpApplied = modPowerUpAppliedImpl
  modPowerUpIconDraw = modPowerUpIconImpl
  powerUpDamageSink = proc (game: Game, pt: PowerUpType, amount: float32) {.nimcall.} =
    trackPowerUpDamage(game, pt, amount)
  enemyTypeNamer = enemyNamerImpl
  enemyNameResolver = enemyResolverImpl

proc dropNewContent(owner: int) =
  var changed = false
  for pt in ModPowerUpSlot:
    if modPowerUps[pt].bound and puScripts[pt].owner == owner:
      modPowerUps[pt] = ModPowerUpInfo()
      puScripts[pt] = ModPowerUpScript()
      changed = true
  for et in ModEnemySlot:
    if enemyOwners[et] == owner:
      modEnemies[et] = ModEnemyInfo(base: etCircle)
      enemyOwners[et] = -1
  if changed: rebuildPowerUpPools()

proc checkName(vm: VM, t: ScriptTable, what: string): string =
  let v = rawGetStr(t, "id")
  if v.kind != vkString or v.str.s.len == 0:
    vm.runtimeError(what & " needs an id (letters, digits, _)")
  result = v.str.s
  for c in result:
    if c notin {'a'..'z', 'A'..'Z', '0'..'9', '_'}:
      vm.runtimeError(what & ": id may only use letters, digits and _ (got \"" & result & "\")")

proc parseModes(vm: VM, v: ScriptValue): set[GameMode] =
  if v.kind == vkNil: return {}
  for x in textList(vm, v, "modes"):
    case x
    of "wave": result.incl(gmWaveBased)
    of "survival": result.incl(gmTimeSurvival)
    of "roguelite": result.incl(gmRoguelite)
    of "sandbox": result.incl(gmSandbox)
    else: vm.runtimeError("modes: use \"wave\", \"survival\", \"roguelite\" or \"sandbox\" (got \"" & x & "\")")

proc applyPowerUpFields(vm: VM, def: var PowerUpDef, t: ScriptTable, what: string) =
  let lg = rawGetStr(t, "legendary")
  if lg.kind != vkNil:
    def.pool = if truthy(lg): puppLegendary else: puppNormal
    if truthy(lg): def.maxLevel = 1
  let ml = rawGetStr(t, "maxLevel")
  if ml.kind != vkNil: def.maxLevel = clamp(vm.checkInt([ml], 0, "maxLevel"), 1, 10)
  let c = rawGetStr(t, "color")
  if c.kind != vkNil: def.color = parseColor(vm, c, what & ".color")
  let fam = rawGetStr(t, "family")
  if fam.kind == vkString:
    try: def.family = parseEnum[RoguelitePowerFamily]("rpf" & fam.str.s.capitalizeAscii)
    except ValueError: vm.runtimeError(what & ": unknown family '" & fam.str.s & "' (core, shield, arcane, fire, frost, poison, lightning, wind, blood)")
  let grp = rawGetStr(t, "group")
  if grp.kind == vkString:
    try: def.group = parseEnum[PowerUpGroup]("pug" & grp.str.s.capitalizeAscii)
    except ValueError: vm.runtimeError(what & ": unknown group '" & grp.str.s & "' (none, orb, aura, bullet, mastery)")
  let modes = rawGetStr(t, "modes")
  if modes.kind != vkNil: def.allowedModes = parseModes(vm, modes)

proc installNewContent(base: ScriptTable) =
  let registerT = rawGetStr(base, "register").tbl
  registerT.reg("powerup") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## local name = register.powerup{id = "overdrive", name = "OVERDRIVE.exe", ...}
    let owner = vm.requireOwner("register.powerup")
    let t = vm.checkTable(args, 0, "powerup")
    let key = mods[owner].id & ":" & vm.checkName(t, "register.powerup")
    var slot = puMod00
    var found = false
    for pt in ModPowerUpSlot:
      if modPowerUps[pt].key == key: vm.runtimeError("register.powerup: '" & key & "' is already registered")
      if not found and not modPowerUps[pt].bound:
        slot = pt
        found = true
    if not found: vm.runtimeError("register.powerup: all 64 mod power-up slots are in use")
    var def = PowerUpDef(pool: puppNormal, family: rpfCore, group: pugNone, maxLevel: 3,
                         color: Color(r: 190, g: 190, b: 255, a: 255))
    vm.applyPowerUpFields(def, t, "register.powerup")
    var s = ModPowerUpScript(owner: owner)
    (s.nameEn, s.nameEs) = vm.textPair(rawGetStr(t, "name"), "name")
    if s.nameEn.len == 0: s.nameEn = key.split(':')[1].toUpperAscii & ".exe"
    let d = rawGetStr(t, "description")
    case d.kind
    of vkFunction, vkNative: s.descFn = d
    of vkTable:
      if rawGetStr(d.tbl, "en").kind != vkNil or rawGetStr(d.tbl, "es").kind != vkNil:
        s.descEn = vm.textList(rawGetStr(d.tbl, "en"), "description.en")
        s.descEs = vm.textList(rawGetStr(d.tbl, "es"), "description.es")
      else:
        s.descEn = vm.textList(d, "description")
    else: s.descEn = vm.textList(d, "description")
    s.icon = rawGetStr(t, "icon")
    s.onPickup = rawGetStr(t, "onPickup")
    # Per-frame and per-hit behaviour, run only while the player has it (and
    # credited to it in the run statistics).
    let upd = rawGetStr(t, "update")
    if upd.kind in {vkFunction, vkNative}: powerUpUpdateFns[ord(slot)] = ScriptFn(owner: owner, fn: upd)
    let hit = rawGetStr(t, "onHit")
    if hit.kind in {vkFunction, vkNative}: powerUpHitFns[ord(slot)] = ScriptFn(owner: owner, fn: hit)
    puScripts[slot] = s
    modPowerUps[slot] = ModPowerUpInfo(bound: true, key: key)
    setPowerUpDef(slot, def)
    ret.setRet(vstr(key))

  registerT.reg("enemy") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## local name = register.enemy{id = "bouncer", base = "etCube", hp = 3, ...}
    let owner = vm.requireOwner("register.enemy")
    let t = vm.checkTable(args, 0, "enemy")
    let idName = vm.checkName(t, "register.enemy")
    let key = mods[owner].id & ":" & idName
    var slot = etMod00
    var found = false
    for et in ModEnemySlot:
      if modEnemies[et].key == key: vm.runtimeError("register.enemy: '" & key & "' is already registered")
      if not found and not modEnemies[et].bound:
        slot = et
        found = true
    if not found: vm.runtimeError("register.enemy: all 32 mod enemy slots are in use")
    var base = etCircle
    let b = rawGetStr(t, "base")
    if b.kind == vkString:
      var parsed: EnemyType
      if not resolveEnemyScriptName(b.str.s, parsed) or parsed notin etCircle..etMage:
        vm.runtimeError("register.enemy: base must be a wave-mode enemy (etCircle ... etMage), got '" &
                        b.str.s & "'")
      base = parsed
    var cfg = vanillaEnemyConfig(base)
    cfg.enemyType = slot
    let label = rawGetStr(t, "name")
    cfg.name = if label.kind == vkString: label.str.s else: idName
    let desc = rawGetStr(t, "description")
    if desc.kind == vkString: cfg.description = desc.str.s
    template alias(key: string, body: untyped) =
      block:
        let v {.inject.} = rawGetStr(t, key)
        if v.kind != vkNil: body
    alias("hp"): cfg.baseHP = vm.checkNum([v], 0, "hp").float32
    alias("radius"): cfg.baseRadius = vm.checkNum([v], 0, "radius").float32
    alias("speed"): cfg.movement.baseSpeed = vm.checkNum([v], 0, "speed").float32
    alias("contactDamage"): cfg.contactDamage = vm.checkNum([v], 0, "contactDamage").float32
    alias("color"): cfg.baseColor = parseColor(vm, v, "register.enemy.color")
    let extra = rawGetStr(t, "config")
    if extra.kind == vkTable:
      applyTable(vm, cfg, extra.tbl, "register.enemy.config", skip = ["enemyType"])
    let coins = rawGetStr(t, "coins")
    let xp = rawGetStr(t, "xp")
    modEnemies[slot] = ModEnemyInfo(bound: true, key: key, label: cfg.name, base: base,
                                    coins: (if coins.kind == vkNumber: max(0, int(coins.n)) else: 2),
                                    xp: (if xp.kind == vkNumber: max(0, int(xp.n)) else: 1),
                                    config: cfg)
    enemyOwners[slot] = owner
    let upd = rawGetStr(t, "update")
    if upd.kind in {vkFunction, vkNative}: enemyUpdateFns[ord(slot)] = ScriptFn(owner: owner, fn: upd)
    let drw = rawGetStr(t, "draw")
    if drw.kind in {vkFunction, vkNative}: enemyDrawFns[ord(slot)] = ScriptFn(owner: owner, fn: drw)
    invalidateEnemyConfigCache()
    ret.setRet(vstr(key))

  let overrideT = rawGetStr(base, "override").tbl
  overrideT.reg("powerup") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## override.powerup("puDoubleShot", {maxLevel = 5, color = "#ff0000", modes = {"wave"},
    ##                                   update = fn(player, level, dt, game),
    ##                                   onHit = fn(bullet, enemy, damage, level) -> damage})
    let owner = vm.requireOwner("override.powerup")
    let name = vm.checkStr(args, 0, "powerup")
    var pt: PowerUpType
    if not resolvePowerUpScriptName(name, pt):
      vm.argError("powerup", 0, "unknown power-up '" & name & "'")
    let t = vm.checkTable(args, 1, "powerup")
    var def = powerUpDef(pt)
    vm.applyPowerUpFields(def, t, "override.powerup")
    setPowerUpDef(pt, def)
    # Extra behaviour on top of the built-in one (credited to it in the stats).
    let upd = rawGetStr(t, "update")
    if upd.kind in {vkFunction, vkNative}: powerUpUpdateFns[ord(pt)] = ScriptFn(owner: owner, fn: upd)
    let hit = rawGetStr(t, "onHit")
    if hit.kind in {vkFunction, vkNative}: powerUpHitFns[ord(pt)] = ScriptFn(owner: owner, fn: hit)

  let rosterT = newScriptTable()
  rosterT.reg("add") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## roster.add("wave", "mymod:bouncer", {chance = 0.15, fromWave = 3})
    ## (survival: minTime = seconds; roguelite: minFloor = sector)
    let owner = vm.requireOwner("roster.add")
    let mode = case vm.checkStr(args, 0, "add")
      of "wave": gmWaveBased
      of "survival": gmTimeSurvival
      of "roguelite": gmRoguelite
      else: vm.argError("add", 0, "mode must be \"wave\", \"survival\" or \"roguelite\"")
    var e = RosterEntry(mode: mode, et: vm.checkEnemyType(args, 1, "add"), chance: 0.1, owner: owner)
    let opts = arg(args, 2)
    if opts.kind == vkTable:
      let c = rawGetStr(opts.tbl, "chance")
      if c.kind == vkNumber: e.chance = clamp(c.n, 0.0, 1.0)
      let w = rawGetStr(opts.tbl, "fromWave")
      if w.kind == vkNumber: e.fromWave = int(w.n)
      let mt = rawGetStr(opts.tbl, "minTime")
      if mt.kind == vkNumber: e.minTime = mt.n
      let mf = rawGetStr(opts.tbl, "minFloor")
      if mf.kind == vkNumber: e.minFloor = int(mf.n)
    rosterEntries.add(e)
  rawSet(base, vstr("roster"), vtable(rosterT))

  let powerupsT = newScriptTable()
  powerupsT.reg("list") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    var names: seq[string]
    for pt in livePowerUps(): names.add(powerUpScriptName(pt))
    ret.setRet(namesTable(names))
  powerupsT.reg("get") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## A copy of a power-up's registry entry ({maxLevel, color, pool, ...}).
    var pt: PowerUpType
    let name = vm.checkStr(args, 0, "get")
    if not resolvePowerUpScriptName(name, pt): vm.argError("get", 0, "unknown power-up '" & name & "'")
    ret.setRet(objToValue(powerUpDef(pt)))
  rawSet(base, vstr("powerups"), vtable(powerupsT))

# ================================================================== assets ====
# assets.texture / assets.model / assets.sound load files from the mod's own
# folder; override.texture/model/sound/music swap the game's look and sound;
# register.cosmetic adds skins players equip in MODS.EXE.

var soundClass, shaderClass: UdClass
var textureClass*, modelClass*: UdClass

proc safeModPath*(m: ModRuntime, rel: string): string

proc modFile(vm: VM, rel, what: string): string =
  let owner = vm.requireOwner(what)
  result = safeModPath(mods[owner], rel)
  if result.len == 0: vm.runtimeError(what & ": '" & rel & "' is outside the mod folder")
  if not fileExists(result): vm.runtimeError(what & ": file not found: " & rel)

proc textureId*(vm: VM, v: ScriptValue, what: string): int =
  ## A texture handle, or a path (loaded on the spot).
  if v.kind == vkUserdata and v.ud.cls == textureClass: return v.ud.handle
  if v.kind == vkString:
    let id = loadModTexture(vm.modFile(v.str.s, what))
    if id == 0: vm.runtimeError(what & ": could not load '" & v.str.s & "' (PNG or GIF expected)")
    return id
  vm.runtimeError(what & ": texture expected (assets.texture(...) or a file name)")

proc loadModelFile(vm: VM, rel, what: string): int =
  ## A model from the mod's folder; what it could not use goes to the Log tab.
  var err, warn = ""
  result = loadModModel(vm.modFile(rel, what), err, warn)
  if result == 0: vm.runtimeError(what & ": " & rel & ": " & err)
  if warn.len > 0: modLogAdd(mlWarn, mods[vm.requireOwner(what)].id, rel & ": " & warn)

proc modelId*(vm: VM, v: ScriptValue, what: string): int =
  ## A model handle, or a path (loaded on the spot).
  if v.kind == vkUserdata and v.ud.cls == modelClass: return v.ud.handle
  if v.kind == vkString: return vm.loadModelFile(v.str.s, what)
  vm.runtimeError(what & ": model expected (assets.model(...) or a file name)")

proc resolveAnim(vm: VM, id: int, v: ScriptValue, what: string): int =
  ## An `animation` option (index + 1): a name or a number from 1; false
  ## holds the rest pose; nil or true plays the first one, if there is any.
  let names = modelAnimations(id)
  case v.kind
  of vkNil: result = min(1, names.len)
  of vkBool: result = if v.b: min(1, names.len) else: 0
  of vkNumber:
    if not (v.n >= 1 and v.n <= names.len.float64 and v.n == floor(v.n)):
      let shown = if v.n == floor(v.n) and abs(v.n) < 1.0e15: $int(v.n) else: $v.n
      vm.runtimeError(what & ": animation " & shown & " does not exist (the model has " &
                      $names.len & ")")
    result = int(v.n)
  of vkString:
    result = names.find(v.str.s) + 1
    if result == 0:
      vm.runtimeError(what & ": the model has no animation '" & v.str.s & "'" &
                      (if names.len > 0: " (it has: " & names.join(", ") & ")" else: " (it has none)"))
  else: vm.runtimeError(what & ": animation must be a name, a number or false")

proc readPose*(vm: VM, opts: ScriptValue, id: int, what: string): ModelPose =
  ## The pose options shared by override.model, draw.model and model cosmetics.
  result = ModelPose(speed: 1, lit: true, tint: White)
  if opts.kind != vkTable:
    result.anim = vm.resolveAnim(id, NilValue, what)
    return
  for (field, dest) in [("tilt", addr result.tilt), ("yaw", addr result.yaw),
                        ("pitch", addr result.pitch), ("roll", addr result.roll),
                        ("spin", addr result.spin), ("speed", addr result.speed)]:
    let v = rawGetStr(opts.tbl, field)
    if v.kind == vkNumber and abs(v.n) < 1.0e9: dest[] = v.n.float32   # (NaN fails too)
    elif v.kind != vkNil: vm.runtimeError(what & ": " & field & " must be a number")
  let lit = rawGetStr(opts.tbl, "lit")
  if lit.kind != vkNil: result.lit = truthy(lit)
  let tn = rawGetStr(opts.tbl, "tint")
  if tn.kind != vkNil: result.tint = parseColor(vm, tn, what & ".tint")
  result.anim = vm.resolveAnim(id, rawGetStr(opts.tbl, "animation"), what)

proc readScaleRotate(opts: ScriptValue, look: var BodyReplace) =
  look.scale = 1.0
  if opts.kind == vkTable:
    let s = rawGetStr(opts.tbl, "scale")
    if s.kind == vkNumber: look.scale = max(0.05, s.n).float32
    look.rotate = truthy(rawGetStr(opts.tbl, "rotate"))

proc texReplace(vm: VM, args: openArray[ScriptValue], texArg: int, what: string): BodyReplace =
  ## override.texture's look; nil clears the override.
  if arg(args, texArg).kind == vkNil: return BodyReplace()
  result = BodyReplace(id: vm.textureId(arg(args, texArg), what))
  readScaleRotate(arg(args, texArg + 1), result)

proc modelReplace(vm: VM, args: openArray[ScriptValue], modelArg: int, what: string): BodyReplace =
  ## override.model's look; nil clears the override.
  if arg(args, modelArg).kind == vkNil: return BodyReplace()
  let opts = arg(args, modelArg + 1)
  if opts.kind notin {vkNil, vkTable}: vm.argError("model", modelArg + 1, "options must be a table")
  result = BodyReplace(model: vm.modelId(arg(args, modelArg), what))
  result.pose = vm.readPose(opts, result.model, what)
  readScaleRotate(opts, result)

proc readDesktopEntry(vm: VM, t: ScriptTable, what: string, icon: var BodyReplace,
                      color: var Color, desktop: var bool) =
  ## The desktop-icon options register.app and register.gamemode share: icon
  ## (texture, model or file name), color (left as is when absent) and desktop
  ## (default true).
  let col = rawGetStr(t, "color")
  if col.kind != vkNil: color = parseColor(vm, col, what & " color")
  let dk = rawGetStr(t, "desktop")
  desktop = dk.kind == vkNil or truthy(dk)
  let ic = rawGetStr(t, "icon")
  if ic.kind == vkUserdata and ic.ud.cls == modelClass:
    icon.model = ic.ud.handle
  elif ic.kind == vkUserdata:
    icon.id = vm.textureId(ic, what & " icon")
  elif ic.kind == vkString:
    # By extension: an image is a texture, anything else is tried as a model.
    let ext = ic.str.s.toLowerAscii
    if ext.endsWith(".png") or ext.endsWith(".gif"): icon.id = vm.textureId(ic, what & " icon")
    else: icon.model = vm.modelId(ic, what & " icon")
  elif ic.kind != vkNil:
    vm.runtimeError(what & ": icon must be a texture, a model or a file name")
  if icon.model > 0:
    icon.pose = vm.readPose(vtable(t), icon.model, what)

proc bodySlot(vm: VM, target, fname, extraTarget: string): ptr BodyReplace =
  ## The body an override target names: player, enemy:<type>, boss:<id>,
  ## bullet:player, bullet:enemy or powerup:<name>.
  let colon = target.find(':')
  let kind = if colon >= 0: target[0 ..< colon] else: target
  let rest = if colon >= 0: target[colon + 1 .. ^1] else: ""
  case kind
  of "player": result = addr playerTex
  of "bullet":
    if rest notin ["player", "enemy"]: vm.argError(fname, 0, "use bullet:player or bullet:enemy")
    result = addr bulletTex[rest == "player"]
  of "enemy":
    var et: EnemyType
    if not resolveEnemyName(rest, et): vm.argError(fname, 0, "unknown enemy type '" & rest & "'")
    result = addr enemyTex[et]
  of "boss":
    var id = 0
    try: id = parseInt(rest)
    except ValueError: vm.argError(fname, 0, "boss:<id> needs a number")
    result = addr bossTex.mgetOrPut(id, BodyReplace())
  of "powerup":
    var pt: PowerUpType
    if not resolvePowerUpScriptName(rest, pt): vm.argError(fname, 0, "unknown power-up '" & rest & "'")
    result = addr powerUpTex[pt]
  of "boss3d":
    if colon >= 0: vm.argError(fname, 0, "use boss3d (the 3D world's boss)")
    result = addr boss3dTex
  of "satellite3d":
    if colon >= 0: vm.argError(fname, 0, "use satellite3d (the 3D boss's satellites)")
    result = addr satellite3dTex
  of "entity3d":
    if rest.len == 0: vm.argError(fname, 0, "entity3d:<tag> needs the entity's tag")
    result = addr entity3dTex.mgetOrPut(rest, BodyReplace())
  of "projectile3d":
    if rest notin ["player", "enemy"]: vm.argError(fname, 0, "use projectile3d:player or projectile3d:enemy")
    result = addr projectile3dTex[rest == "player"]
  of "pickup3d":
    if rest.len == 0: vm.argError(fname, 0, "pickup3d:<kind> needs the pickup's kind")
    result = addr pickup3dTex.mgetOrPut(rest, BodyReplace())
  else:
    vm.argError(fname, 0, "unknown target '" & target & "' (player, enemy:<type>, boss:<id>, " &
                "bullet:player, bullet:enemy, powerup:<name>, boss3d, satellite3d, entity3d:<tag>, " &
                "projectile3d:player, projectile3d:enemy, pickup3d:<kind>, " & extraTarget & ")")

proc installAssetLibraries(base: ScriptTable) =
  textureClass = UdClass(name: "texture")
  textureClass.index = proc (vm: VM, ud: Userdata, key: ScriptValue): ScriptValue =
    let (w, h) = textureSize(ud.handle)
    case keyName(key)
    of "width": vnum(w)
    of "height": vnum(h)
    of "frames": vnum(textureFrames(ud.handle))
    of "duration": vnum(textureDuration(ud.handle).float64)
    else: vm.runtimeError("texture has no field '" & keyName(key) & "'")
  textureClass.tostr = proc (ud: Userdata): string = "texture #" & $ud.handle
  soundClass = UdClass(name: "sound")
  soundClass.index = proc (vm: VM, ud: Userdata, key: ScriptValue): ScriptValue =
    if keyName(key) == "play":
      return vnative(newNative("play", proc (vm: VM, a: openArray[ScriptValue], r: var RetVals) =
        let self = arg(a, 0)
        if self.kind != vkUserdata or self.ud.cls != soundClass:
          vm.runtimeError("sound:play() needs a sound (call it with ':')")
        playModSound(self.ud.handle, vm.optNum(a, 1, "play", 1.0).float32,
                     vm.optNum(a, 2, "play", 1.0).float32)))
    vm.runtimeError("sound has no field '" & keyName(key) & "'")
  soundClass.tostr = proc (ud: Userdata): string = "sound #" & $ud.handle
  shaderClass = UdClass(name: "shader")
  shaderClass.index = proc (vm: VM, ud: Userdata, key: ScriptValue): ScriptValue =
    if keyName(key) == "set":
      return vnative(newNative("set", proc (vm: VM, a: openArray[ScriptValue], r: var RetVals) =
        ## shader:set("strength", 0.5) / shader:set("tint", {1, 0.5, 0.2})
        let self = arg(a, 0)
        if self.kind != vkUserdata or self.ud.cls != shaderClass:
          vm.runtimeError("shader:set() needs a shader (call it with ':')")
        let name = vm.checkStr(a, 1, "set")
        let v = arg(a, 2)
        var vals: seq[float32]
        if v.kind == vkNumber: vals.add(v.n.float32)
        elif v.kind == vkTable and v.tbl.len in 2..4:
          for x in v.tbl:
            if x.kind != vkNumber: vm.argError("set", 2, "vector entries must be numbers")
            vals.add(x.n.float32)
        else:
          vm.argError("set", 2, "a number or a list of 2 to 4 numbers")
        r.setRet(vbool(setModShaderValue(self.ud.handle, name, vals)))))
    vm.runtimeError("shader has no field '" & keyName(key) & "'")
  shaderClass.tostr = proc (ud: Userdata): string = "shader #" & $ud.handle
  modelClass = UdClass(name: "model")
  modelClass.index = proc (vm: VM, ud: Userdata, key: ScriptValue): ScriptValue =
    let s = modelSize(ud.handle)
    case keyName(key)
    of "width": vnum(s.x.float64)
    of "height": vnum(s.y.float64)
    of "depth": vnum(s.z.float64)
    of "animations": namesTable(modelAnimations(ud.handle))
    of "duration":
      vnative(newNative("duration", proc (vm: VM, a: openArray[ScriptValue], r: var RetVals) =
        ## mdl:duration([animation]) -> seconds one loop lasts (0: no animation)
        let self = arg(a, 0)
        if self.kind != vkUserdata or self.ud.cls != modelClass:
          vm.runtimeError("model:duration() needs a model (call it with ':')")
        let anim = vm.resolveAnim(self.ud.handle, arg(a, 1), "model:duration")
        r.setRet(vnum(modelAnimDuration(self.ud.handle, anim).float64))))
    else: vm.runtimeError("model has no field '" & keyName(key) & "'")
  modelClass.tostr = proc (ud: Userdata): string = "model #" & $ud.handle

  let assetsT = newScriptTable()
  assetsT.reg("texture") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## local tex = assets.texture("sprites/ship.png")  -- PNG or GIF in your mod folder
    let rel = vm.checkStr(args, 0, "texture")
    let id = loadModTexture(vm.modFile(rel, "assets.texture"))
    if id == 0: vm.runtimeError("assets.texture: could not load '" & rel & "' (PNG or GIF expected)")
    ret.setRet(vud(Userdata(cls: textureClass, handle: id, key: cast[pointer](id))))
  assetsT.reg("sound") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## local s = assets.sound("sfx/zap.wav"); s:play([volume, pitch])
    let rel = vm.checkStr(args, 0, "sound")
    let id = loadModSound(vm.modFile(rel, "assets.sound"))
    if id == 0: vm.runtimeError("assets.sound: could not load '" & rel & "' (WAV/OGG/MP3)")
    ret.setRet(vud(Userdata(cls: soundClass, handle: id, key: cast[pointer](id + 100000))))
  assetsT.reg("shader") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## local crt = assets.shader("fx/crt.fs")  -- a GLSL fragment shader; it gets
    ## `time` and `resolution` uniforms, and shader:set(name, value) for yours.
    let rel = vm.checkStr(args, 0, "shader")
    var err = ""
    let id = loadModShader(vm.modFile(rel, "assets.shader"), err)
    if id == 0: vm.runtimeError("assets.shader: " & rel & ": " & err)
    ret.setRet(vud(Userdata(cls: shaderClass, handle: id, key: cast[pointer](id + 200000))))
  assetsT.reg("model") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## local ship = assets.model("models/ship.glb")  -- GLB/glTF, OBJ, IQM, VOX or M3D;
    ## mdl.width/height/depth, mdl.animations, mdl:duration(anim)
    let id = vm.loadModelFile(vm.checkStr(args, 0, "model"), "assets.model")
    ret.setRet(vud(Userdata(cls: modelClass, handle: id, key: cast[pointer](id + 300000))))
  rawSet(base, vstr("assets"), vtable(assetsT))

  let drawT = rawGetStr(base, "draw").tbl
  drawT.reg("texture") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## draw.texture(tex, x, y [, {w = .., h = .., rotation = deg, tint = color,
    ##              origin = "center" | "topleft", frame = n, time = seconds}])
    ## A GIF plays by itself; frame (1 = first, wraps) or time (seconds into
    ## the animation) pick the frame instead.
    vm.requireDrawing("texture")
    let id = vm.textureId(arg(args, 0), "draw.texture")
    let (tw, th) = textureSize(id)
    var w = tw.float32
    var h = th.float32
    var rot = 0.0'f32
    var tint = White
    var centered = true
    var frame = -1
    let opts = arg(args, 3)
    if opts.kind == vkTable:
      let ow = rawGetStr(opts.tbl, "w")
      let oh = rawGetStr(opts.tbl, "h")
      if ow.kind == vkNumber: w = ow.n.float32
      if oh.kind == vkNumber: h = oh.n.float32
      if ow.kind == vkNumber and oh.kind != vkNumber and tw > 0: h = w * th.float32 / tw.float32
      let r = rawGetStr(opts.tbl, "rotation")
      if r.kind == vkNumber: rot = r.n.float32
      let tn = rawGetStr(opts.tbl, "tint")
      if tn.kind != vkNil: tint = parseColor(vm, tn, "draw.texture.tint")
      let o = rawGetStr(opts.tbl, "origin")
      if o.kind == vkString and o.str.s == "topleft": centered = false
      let fr = rawGetStr(opts.tbl, "frame")
      let tm = rawGetStr(opts.tbl, "time")
      if fr.kind == vkNumber:
        if fr.n != fr.n or abs(fr.n) > 9.0e15: vm.runtimeError("draw.texture: frame must be a whole number")
        frame = floorMod(int(floor(fr.n)) - 1, textureFrames(id))
      elif tm.kind == vkNumber:
        frame = textureFrameAt(id, tm.n)
    drawModTexture(id, vm.f32(args, 1, "texture"), vm.f32(args, 2, "texture"), w, h, rot, tint,
                   centered, frame)
  drawT.reg("model") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## draw.model(mdl, x, y [, {size = px, scale = px per unit, facing = deg,
    ##            tilt/yaw/pitch/roll = deg, spin = deg/s, animation = name | n | false,
    ##            speed = x, time = seconds, frame = n, lit = bool, tint = color}])
    ## Centred on x, y; its footprint (seen from above) is `size` wide (64 by
    ## default); its front points toward `facing` (90 = down, the default).
    vm.requireDrawing("model")
    let id = vm.modelId(arg(args, 0), "draw.model")
    let x = vm.f32(args, 1, "model")
    let y = vm.f32(args, 2, "model")
    let opts = arg(args, 3)
    if opts.kind notin {vkNil, vkTable}: vm.argError("model", 3, "options must be a table")
    let pose = vm.readPose(opts, id, "draw.model")
    var pxPerUnit = 64 / modelFootprint(id)
    var facing = 90.0'f32
    var frame = modelFrameAt(id, pose, getTime())
    if opts.kind == vkTable:
      let size = rawGetStr(opts.tbl, "size")
      let scale = rawGetStr(opts.tbl, "scale")
      if size.kind == vkNumber: pxPerUnit = size.n.float32 / modelFootprint(id)
      elif scale.kind == vkNumber: pxPerUnit = scale.n.float32
      let f = rawGetStr(opts.tbl, "facing")
      if f.kind == vkNumber and abs(f.n) < 1.0e9: facing = f.n.float32
      let fr = rawGetStr(opts.tbl, "frame")
      let tm = rawGetStr(opts.tbl, "time")
      if fr.kind == vkNumber and pose.anim > 0:
        if not (abs(fr.n) < 9.0e15): vm.runtimeError("draw.model: frame must be a whole number")
        frame = floorMod(int(floor(fr.n)) - 1, modelAnimFrames(id, pose.anim))
      elif tm.kind == vkNumber:
        frame = modelFrameAt(id, pose, tm.n)   # (a NaN time shows frame 1)
    drawModModel(id, x, y, pxPerUnit, facing, pose, frame)

  let overrideT = rawGetStr(base, "override").tbl
  overrideT.reg("texture") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## override.texture("enemy:etCube", "cube.png" [, {scale = 1.2, rotate = true}])
    ## targets: player, enemy:<type>, boss:<id>, bullet:player, bullet:enemy,
    ##          powerup:<name>, desktop ({cube = true} keeps the desktop cube).
    ## nil instead of the texture puts the game's own look back.
    let target = vm.checkStr(args, 0, "texture")
    let r = vm.texReplace(args, 1, "override.texture")
    if target == "desktop":
      desktopTex = r
      let opts = arg(args, 2)
      desktopCube = opts.kind == vkTable and truthy(rawGetStr(opts.tbl, "cube"))
    else:
      vm.bodySlot(target, "texture", "desktop")[] = r
    markActive()
  overrideT.reg("model") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## override.model("player", "models/ship.glb" [, {scale = 1.2, rotate = true,
    ##   tilt = 30, yaw = 0, pitch = 0, roll = 0, spin = 0, animation = "Idle",
    ##   speed = 1, lit = true, tint = color}])
    ## targets: those of override.texture, and "cube" (the desktop cube) in
    ## place of "desktop". nil instead of the model puts the game's own look back.
    let target = vm.checkStr(args, 0, "model")
    let r = vm.modelReplace(args, 1, "override.model")
    if target == "cube": cubeModel = r
    else: vm.bodySlot(target, "model", "cube")[] = r
    markActive()
  overrideT.reg("sound") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## override.sound("shoot", "sfx/pew.wav")
    let name = vm.checkStr(args, 0, "sound")
    var st: SoundType
    try: st = parseEnum[SoundType]("st" & name.capitalizeAscii)
    except ValueError: vm.argError("sound", 0, "unknown sound '" & name & "'")
    if not setModSound(st, vm.modFile(vm.checkStr(args, 1, "sound"), "override.sound")):
      vm.runtimeError("override.sound: could not load the file (WAV/OGG/MP3)")
  overrideT.reg("shader") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## override.shader("screen" | "game", shader) -- post-processing over the
    ## whole frame; "game" only while a run is on screen. nil switches it off.
    let target = vm.checkStr(args, 0, "shader")
    let v = arg(args, 1)
    var id = 0
    if v.kind == vkUserdata and v.ud.cls == shaderClass: id = v.ud.handle
    elif v.kind == vkString:
      var err = ""
      id = loadModShader(vm.modFile(v.str.s, "override.shader"), err)
      if id == 0: vm.runtimeError("override.shader: " & v.str.s & ": " & err)
    elif v.kind != vkNil:
      vm.argError("shader", 1, "a shader (assets.shader) or a file name")
    case target
    of "screen": screenShader = id
    of "game": gameShader = id
    else: vm.argError("shader", 0, "use \"screen\" or \"game\"")
  overrideT.reg("music") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## override.music("wave" | "menu" | "powerUp" | "boss", "music/track.ogg")
    let name = vm.checkStr(args, 0, "music")
    var track: MusicTrack
    try: track = parseEnum[MusicTrack]("mt" & name.capitalizeAscii)
    except ValueError: vm.argError("music", 0, "use \"menu\", \"wave\", \"powerUp\" or \"boss\"")
    if not setModMusic(track, vm.modFile(vm.checkStr(args, 1, "music"), "override.music")):
      vm.runtimeError("override.music: could not load the file (OGG/MP3/WAV)")

  let registerT = rawGetStr(base, "register").tbl
  registerT.reg("gamemode") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## register.gamemode{id = "glass", name = "Glass Cannon", description = "...",
    ##   base = "wave" | "survival" | "roguelite" | "3d", spawning = true,
    ##   onStart = function(game, resumed) ... end,
    ##   icon = texture | model | "file", color = "#64c8ff", desktop = true}
    let owner = vm.requireOwner("register.gamemode")
    let t = vm.checkTable(args, 0, "gamemode")
    let key = mods[owner].id & ":" & vm.checkName(t, "register.gamemode")
    if findModMode(key) >= 0: vm.runtimeError("register.gamemode: '" & key & "' is already registered")
    var m = ModModeDef(key: key, owner: owner, spawning: true, desktop: true, base: gmWaveBased)
    let b = rawGetStr(t, "base")
    if b.kind == vkString:
      if b.str.s == "3d":
        m.threeD = true   # a 3D world on a wave-mode run; the 2D arena never plays
      else:
        m.base = case b.str.s
          of "wave": gmWaveBased
          of "survival": gmTimeSurvival
          of "roguelite": gmRoguelite
          else: vm.runtimeError("register.gamemode: base must be \"wave\", \"survival\", \"roguelite\" or \"3d\"")
    (m.nameEn, m.nameEs) = vm.textPair(rawGetStr(t, "name"), "name")
    if m.nameEn.len == 0: m.nameEn = key
    (m.descEn, m.descEs) = vm.textPair(rawGetStr(t, "description"), "description")
    let sp = rawGetStr(t, "spawning")
    if sp.kind != vkNil: m.spawning = truthy(sp)
    if m.threeD: m.spawning = false
    m.onStart = rawGetStr(t, "onStart")
    vm.readDesktopEntry(t, "register.gamemode", m.icon, m.color, m.desktop)  # color a = 0: base mode's
    modModes.add(m)
    ret.setRet(vstr(key))
  registerT.reg("app") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## register.app{id = "settings", name = {en = "Settings", es = "Ajustes"},
    ##   draw = function(w, h, mouseX, mouseY) ... end,   -- canvas coordinates
    ##   update = function(dt) ... end, click = function(x, y, button, w, h) ... end,
    ##   drag = function(x, y, w, h) ... end,
    ##   icon = texture | model | "file", color = "#78dca0", width = 480, height = 360,
    ##   resizable = false, desktop = true}
    let owner = vm.requireOwner("register.app")
    let t = vm.checkTable(args, 0, "app")
    let key = mods[owner].id & ":" & vm.checkName(t, "register.app")
    for a in modApps:
      if a.key == key: vm.runtimeError("register.app: '" & key & "' is already registered")
    var app = ModApp(key: key, owner: owner)
    (app.nameEn, app.nameEs) = vm.textPair(rawGetStr(t, "name"), "name")
    if app.nameEn.len == 0: app.nameEn = key
    for (field, dest) in [("draw", addr app.draw), ("update", addr app.update),
                          ("click", addr app.click), ("drag", addr app.drag)]:
      let f = rawGetStr(t, field)
      if f.kind in {vkFunction, vkNative}: dest[] = f
      elif f.kind != vkNil: vm.runtimeError("register.app: " & field & " must be a function")
    if app.draw.kind == vkNil: vm.runtimeError("register.app needs a draw function")
    app.color = ModAppDefaultColor
    vm.readDesktopEntry(t, "register.app", app.icon, app.color, app.desktop)
    app.width = 480
    app.height = 360
    for (field, dest, lo, hi) in [("width", addr app.width, ModAppMinW, ModAppMaxW),
                                  ("height", addr app.height, ModAppMinH, ModAppMaxH)]:
      let v = rawGetStr(t, field)
      if v.kind == vkNumber and abs(v.n) < 1.0e9: dest[] = clamp(int(v.n), lo, hi)
      elif v.kind != vkNil: vm.runtimeError("register.app: " & field & " must be a number")
    app.resizable = truthy(rawGetStr(t, "resizable"))
    modApps.add(app)
    ret.setRet(vstr(key))
  registerT.reg("cosmetic") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## register.cosmetic{kind = "player" | "bullet" | "desktop", id = "neon",
    ##   name = "Neon", colors = {"#ff00ff", "#00ffff", "#ffffff"},
    ##   texture = "skins/neon.png", model = "skins/neon.glb", scale = 1.2, rotate = true,
    ##   plus override.model's pose options (tilt, spin, animation, ...)}
    ##   desktop only: the texture is the wallpaper (cube = true keeps the desktop
    ##   cube over it) and the model stands in for the desktop cube
    let owner = vm.requireOwner("register.cosmetic")
    let t = vm.checkTable(args, 0, "cosmetic")
    let kindName = rawGetStr(t, "kind")
    var kind = mckPlayer
    if kindName.kind == vkString:
      try: kind = parseEnum[ModCosmeticKind](kindName.str.s)
      except ValueError: vm.runtimeError("register.cosmetic: kind must be \"player\", \"bullet\", \"desktop\" or \"cube\"")
    let key = mods[owner].id & ":" & vm.checkName(t, "register.cosmetic")
    if cosmeticIndex(kind, key) > 0: vm.runtimeError("register.cosmetic: '" & key & "' is already registered")
    var c = ModCosmetic(kind: kind, key: key, owner: owner)
    let (nameEn, nameEs) = vm.textPair(rawGetStr(t, "name"), "name")
    c.name = pickLang(nameEn, nameEs)
    if c.name.len == 0: c.name = key
    let (descEn, descEs) = vm.textPair(rawGetStr(t, "description"), "description")
    c.description = pickLang(descEn, descEs)
    let colors = rawGetStr(t, "colors")
    if colors.kind == vkTable:
      if colors.tbl.len < 3: vm.runtimeError("register.cosmetic: colors needs 3 colours")
      c.hasPalette = true
      c.c1 = parseColor(vm, colors.tbl.item(1), "colors[1]")
      c.c2 = parseColor(vm, colors.tbl.item(2), "colors[2]")
      c.c3 = parseColor(vm, colors.tbl.item(3), "colors[3]")
    let tex = rawGetStr(t, "texture")
    if tex.kind != vkNil:
      c.look.id = vm.textureId(tex, "register.cosmetic")
    let mdl = rawGetStr(t, "model")
    if mdl.kind != vkNil:
      c.look.model = vm.modelId(mdl, "register.cosmetic")
      c.look.pose = vm.readPose(vtable(t), c.look.model, "register.cosmetic")
    readScaleRotate(vtable(t), c.look)
    c.cube = kind == mckDesktop and truthy(rawGetStr(t, "cube"))
    if not c.hasPalette and not c.look.hasLook:
      vm.runtimeError("register.cosmetic needs colors, a texture and/or a model")
    modCosmetics.add(c)
    ret.setRet(vstr(key))

proc installModApi*(base: ScriptTable) =
  ## Build the classes and the shared library tables (once per reload).
  textEntries.setLen(0)
  makeClasses()
  installMethods()
  installLibraries(base)
  installContentLibraries(base)
  installNewContent(base)
  installAssetLibraries(base)

# ---------------------------------------------------------- per mod env ----
proc safeModPath*(m: ModRuntime, rel: string): string =
  ## A path inside the mod's own folder, or "" if `rel` tries to leave it.
  if rel.len == 0 or rel.isAbsolute or ':' in rel or rel.startsWith("/") or
     rel.startsWith("\\"):
    return ""
  for part in rel.replace('\\', '/').split('/'):
    if part == "..":
      return ""
  let full = normalizedPath(m.dir / rel)
  let root = normalizedPath(m.dir)
  if not full.startsWith(root): return ""
  full

const MaxStorageBytes = 1_000_000

proc storagePath(m: ModRuntime): string =
  getAppDataPath() / "mod_data" / (m.id & ".json")

proc loadModStorage(m: ModRuntime) =
  m.storage = newScriptTable()
  try:
    let path = storagePath(m)
    if fileExists(path):
      let v = fromJsonNode(parseJson(readFile(path)))
      if v.kind == vkTable: m.storage = v.tbl
  except CatchableError:
    modLogAdd(mlWarn, m.id, "mod.storage could not be read; starting empty")

proc saveModStorage*(m: ModRuntime): bool =
  ## Plain data only (numbers, strings, booleans, tables), like run.data.
  if not m.modTable.isNil:
    # `mod.storage = {...}` replaces the table rather than editing it.
    let cur = rawGetStr(m.modTable, "storage")
    if cur.kind == vkTable: m.storage = cur.tbl
  if m.storage.isNil: return true
  try:
    let text = $toJsonNode(vtable(m.storage))
    if text.len > MaxStorageBytes:
      modLogAdd(mlError, m.id, "mod.storage is over 1 MB; not saved")
      return false
    createDir(getAppDataPath() / "mod_data")
    writeFile(storagePath(m), text)
    true
  except CatchableError:
    false

proc saveAllModStorage*() =
  ## Loader (before a reload) and main (on exit).
  for m in mods:
    if not m.disabled or not m.storage.isNil:
      discard saveModStorage(m)

proc installModEnv*(m: ModRuntime) =
  let env = m.env
  let modT = newScriptTable()
  rawSet(modT, vstr("id"), vstr(m.id))
  rawSet(modT, vstr("name"), vstr(m.name))
  rawSet(modT, vstr("version"), vstr(m.version))
  rawSet(modT, vstr("author"), vstr(m.author))
  let modId = m.id
  modT.reg("log") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    var parts: seq[string]
    for a in args: parts.add(vm.tostr(a))
    modLogAdd(mlInfo, modId, parts.join(" "))
  modT.reg("warn") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    var parts: seq[string]
    for a in args: parts.add(vm.tostr(a))
    modLogAdd(mlWarn, modId, parts.join(" "))
  # mod.storage survives sessions (per profile); mod.saveStorage() writes it now
  # (it is also saved on reload and when the game closes).
  loadModStorage(m)
  rawSet(modT, vstr("storage"), vtable(m.storage))
  m.modTable = modT
  let storageOwner = m
  modT.reg("saveStorage") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ret.setRet(vbool(saveModStorage(storageOwner)))
  rawSet(env, vstr("mod"), vtable(modT))

  # run.data: per mod, per run (saved with the run; see mod_hooks.captureRunData)
  let runT = newScriptTable()
  runT.meta = newScriptTable()
  let idx = m.index
  rawSet(runT.meta, vstr("__index"), vnative(newNative("run_index",
    proc (vm: VM, args: openArray[ScriptValue], ret: var RetVals) =
      if keyName(arg(args, 1)) == "data":
        if mods[idx].runData.isNil: mods[idx].runData = newScriptTable()
        ret.setRet(vtable(mods[idx].runData))
      elif keyName(arg(args, 1)) == "active":
        ret.setRet(vbool(not modCtx.game.isNil))
      else:
        ret.setRet(NilValue))))
  rawSet(runT.meta, vstr("__newindex"), vnative(newNative("run_newindex",
    proc (vm: VM, args: openArray[ScriptValue], ret: var RetVals) =
      # run.data = {...} replaces this run's data (it must stay plain data).
      if keyName(arg(args, 1)) == "data":
        let v = arg(args, 2)
        if v.kind != vkTable: vm.runtimeError("run.data must be a table")
        mods[idx].runData = v.tbl
      else:
        vm.runtimeError("run." & keyName(arg(args, 1)) & " cannot be set"))))
  rawSet(env, vstr("run"), vtable(runT))

  # require("folder.file") -> runs <mod>/folder/file.lua once, returns its value
  let loaded = newScriptTable()
  env.reg("require") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    let name = vm.checkStr(args, 0, "require")
    let cached = rawGetStr(loaded, name)
    if cached.kind != vkNil:
      ret.setRet(cached)
      return
    let rel = name.replace('.', '/') & ".lua"
    let path = safeModPath(mods[idx], rel)
    if path.len == 0:
      vm.runtimeError("require: '" & name & "' is outside the mod folder")
    if not fileExists(path):
      vm.runtimeError("require: module '" & name & "' not found (looked for " & rel & ")")
    var src = ""
    try:
      src = readFile(path)
    except IOError:
      vm.runtimeError("require: cannot read " & rel)
    let cl = vm.loadChunk(src, mods[idx].id & "/" & rel, mods[idx].env)
    var r: RetVals
    vm.callValue(vfunc(cl), [vstr(name)], r)
    let v = if r.count > 0 and r.first.kind != vkNil: r.first else: TrueValue
    rawSet(loaded, vstr(name), v)
    ret.setRet(v)
