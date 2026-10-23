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

import std/[os, strutils, tables, json, math, algorithm]
import raylib
import ../draw_prims
import ../types, ../particle_types, ../localization, ../render_context, ../settings, ../powerup, ../utils
import ../enemy_config, ../boss_definitions, ../player, ../enemy, ../bullet, ../game/combat, ../game/death, ../game/bosses, ../d_systems, ../particle_pool, ../sound
import ../powerup_data, ../ui/icon_drawing, ../save_system, ../run_statistics, ../run_save, ../suspend
import ../statistics, ../roguelite
import ../game3d/types_3d, ../coop/coop_context
import mod_assets, mod_media
import lua_bridge, mod_state, mod_hooks, mod_reflect, mod_deep, mod_registry

var
  gameMethods*, playerMethods*, enemyMethods*, bulletMethods*: ScriptTable
    ## The methods tables (the high-layer API modules add their own methods).
  textEntries: seq[tuple[lang, key, value: string, owner: int, isText: bool]]
    ## Every string a mod added, so a mod that fails to load can be undone.
    ## `lang`: "english", "spanish" or a mod language's id; `isText`: a mod
    ## text's translation, keyed by its English ({en = .., fr = ..}).
  languageDefs: seq[tuple[lang: ModLanguage, owner: int]]   ## register.language

proc applyModText(lang, key, value: string, isText: bool) =
  if isText: setModLanguageText(lang, key, value)
  elif lang == $English: setModTranslation(English, key, value)
  elif lang == $Spanish: setModTranslation(Spanish, key, value)
  else: setModLanguageString(lang, key, value)

proc addModText(lang, key, value: string, owner: int, isText = false) =
  textEntries.add((lang, key, value, owner, isText))
  applyModText(lang, key, value, isText)

proc dropModText*(owner: int) =
  ## Forget one mod's strings and languages and rebuild the overlay from
  ## everyone else's.
  var kept: typeof(textEntries)
  for e in textEntries:
    if e.owner != owner: kept.add(e)
  textEntries = kept
  var keptLangs: typeof(languageDefs)
  for d in languageDefs:
    if d.owner != owner: keptLangs.add(d)
  languageDefs = keptLangs
  clearModTranslations()
  clearModLanguages()
  for d in languageDefs: addModLanguage(d.lang.id, d.lang.name, d.lang.base)
  for e in textEntries: applyModText(e.lang, e.key, e.value, e.isText)

# ------------------------------------------------------------- helpers ----
proc keyName*(key: ScriptValue): string {.inline.} =
  if key.kind == vkString: key.str.s else: ""

proc requireRunGame*(vm: VM): Game =
  if modCtx.inPvP:
    vm.runtimeError("not available in PvP (matches stay vanilla)")
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
                    "(drawWorld, drawHud, enemyDraw, playerDraw, pvpDrawWorld, pvpDrawHud...)")
  if modCtx.drawing == dtWorld3D:
    vm.runtimeError("draw." & fname & " is 2D: in world3dDraw and world3dEntityDraw " &
                    "use the draw3d library (draw.* works in world3dDrawHud)")

proc f32(vm: VM, args: openArray[ScriptValue], i: int, fname: string): float32 {.inline.} =
  vm.checkNum(args, i, fname).float32

var fontClass*: UdClass   ## assets.font handles (made in installAssetLibraries)

proc textFont*(vm: VM, v: ScriptValue, what: string): tuple[font: int, spacing: float32] =
  ## The optional font argument of draw.text, draw.textWidth and draw3d.text:
  ## a font (assets.font) or {font = f, spacing = px}. Font 0 = the game's own.
  case v.kind
  of vkNil: (0, 0'f32)
  of vkUserdata:
    if v.ud.cls != fontClass: vm.runtimeError(what & ": a font (assets.font) expected")
    (v.ud.handle, 0'f32)
  of vkTable:
    var r = (font: 0, spacing: 0'f32)
    let f = rawGetStr(v.tbl, "font")
    if f.kind == vkUserdata and f.ud.cls == fontClass: r.font = f.ud.handle
    elif f.kind != vkNil: vm.runtimeError(what & ": font must be a font (assets.font)")
    let sp = rawGetStr(v.tbl, "spacing")
    if sp.kind == vkNumber and abs(sp.n) < 1000: r.spacing = sp.n.float32   # (NaN fails too)
    elif sp.kind != vkNil: vm.runtimeError(what & ": spacing must be a number")
    r
  else: vm.runtimeError(what & ": a font (assets.font) or {font = ..., spacing = ...} expected")

proc fontSize*(n: float64): float32 =
  ## A size for text in a mod font: 1 to 400 pixels (a NaN gives 1).
  if n >= 1 and n <= 400: n.float32 elif n > 400: 400 else: 1

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

proc textPair*(vm: VM, v: ScriptValue, what: string): tuple[en, es: string]
proc checkName*(vm: VM, t: ScriptTable, what: string): string

proc entityDataValue*(vm: VM, kind: int64, id: int, what: string): ScriptValue =
  ## `x.data`: the running mod's own table for this entity.
  let owner = currentModIdx
  if owner < 0 or owner >= mods.len: vm.runtimeError(what & ".data must be used from mod code")
  vtable(entityDataFor(owner, entityKey(kind, id)))

proc setEntityData*(vm: VM, kind: int64, id: int, val: ScriptValue, what: string) =
  ## `x.data = {...}` replaces the running mod's table for this entity.
  let owner = currentModIdx
  if owner < 0 or owner >= mods.len: vm.runtimeError(what & ".data must be used from mod code")
  if val.kind != vkTable: vm.runtimeError(what & ".data must be a table")
  mods[owner].entityData[entityKey(kind, id)] = val.tbl

proc bulletDataId(vm: VM, b: Bullet): int =
  ## A bullet's id for b.data, given on first use (0 = never needed one). PvP
  ## bullets always have one (pvp_game numbers them from 1).
  if b.bulletId == 0:
    let g = modCtx.game
    if g.isNil: vm.runtimeError("bullet.data needs a run or a PvP match in progress")
    g.bulletIdCounter += 1
    b.bulletId = g.bulletIdCounter
  b.bulletId

# ----------------------------------------------------------- classes ----
const
  GameReadOnly = ["mode", "modMode", "modded", "cheatsUsed", "modFingerprint", "modRunData",
                  "players", "coop",
                  "screenWidth", "screenHeight"]
    ## Mods are trusted; these stay read-only because something keys on them:
    ## mode / modMode name the run's save slots, modded / cheatsUsed /
    ## modFingerprint are the reward rule (a run with mods is cheated unless
    ## every mod opts out), modRunData is rebuilt from run.data on save, and
    ## the screen size is recomputed every frame, players and coop are a co-op
    ## run's seats (game.players is a list of player objects to read and
    ## change, not to add to). game.state is writable: the
    ## change happens at the next safe point.
  PvPPlayerExtras* = ["index", "name", "deaths", "streak", "connected", "alive", "isLocal"]
    ## What a PvP player shows besides its fields (mod_pvp's pvpPlayerField)
  EnemyReadOnly = ["id", "isBoss", "bossTotalMaxHp"]
    ## The enemy's identity (scripts' per-entity data, the spatial grid and
    ## the boss bookkeeping key on these); bossTotalMaxHp follows the pools.

proc posGet*(pos, vel: Vector2, name: string, found: var bool): ScriptValue =
  found = true
  case name
  of "x": vnum(pos.x.float64)
  of "y": vnum(pos.y.float64)
  of "vx": vnum(vel.x.float64)
  of "vy": vnum(vel.y.float64)
  else:
    found = false
    NilValue

proc posSet*(vm: VM, pos, vel: var Vector2, name: string, v: ScriptValue): bool =
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
    if name == "players":
      # A fresh list of the run's players: read and change them, never add one.
      let t = newScriptTable(g.players.len)
      for p in g.players: t.add(wrapPlayer(p))
      return vtable(t)
    var found = false
    result = deepGet(g, name, "game", found)
    if not found: vm.runtimeError("game has no field '" & name & "'")
  gameClass.newindex = proc (vm: VM, ud: Userdata, key, val: ScriptValue) =
    let g = unwrapGame(vud(ud))
    if g.isNil: vm.runtimeError("no run in progress")
    let name = keyName(key)
    if name in GameReadOnly: vm.runtimeError("game." & name & " is read-only")
    if name == "state":
      # A state change mid-frame would leave main.nim's state machine halfway
      # through the old state's branch: it happens at the next safe point.
      var st: GameState
      assignScript(vm, st, val, "game.state")
      let target = g
      deferCall(currentModIdx, vnative(newNative("setState",
        proc (vm: VM, a: openArray[ScriptValue], r: var RetVals) = target.state = st)))
      return
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
    if not modCtx.match.isNil and not pvpPlayerFieldImpl.isNil:
      result = pvpPlayerFieldImpl(p, name, found)   # index, name, deaths... of a PvP player
      if found: return
    result = deepGet(p, name, "player", found)
    if not found: vm.runtimeError("player has no field '" & name & "'")
  playerClass.newindex = proc (vm: VM, ud: Userdata, key, val: ScriptValue) =
    let p = unwrapPlayer(vud(ud))
    if p.isNil: vm.runtimeError("no run in progress")
    let name = keyName(key)
    if not modCtx.match.isNil and name in PvPPlayerExtras:
      vm.runtimeError("player." & name & " is read-only")
    if posSet(vm, p.pos, p.vel, name, val):
      if not modCtx.match.isNil and name in ["x", "y"] and not pvpPlayerMovedImpl.isNil:
        pvpPlayerMovedImpl(p)   # a PvP player moved by a script: snap it on every machine
      return
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
    if name == "data": return vm.entityDataValue(EdEnemy, e.id, "enemy")
    var found = false
    result = posGet(e.pos, e.vel, name, found)
    if found: return
    result = deepGet(e, name, "enemy", found)
    if not found: vm.runtimeError("enemy has no field '" & name & "'")
  enemyClass.newindex = proc (vm: VM, ud: Userdata, key, val: ScriptValue) =
    let e = EnemyBox(ud.box).e
    let name = keyName(key)
    if name == "data":
      vm.setEntityData(EdEnemy, e.id, val, "enemy")
      return
    if name in EnemyReadOnly:
      vm.runtimeError("enemy." & name & " is read-only")
    case name
    of "hp":
      # Set outright (not damage): a boss's is its current phase pool, and an
      # emptied pool moves it on (or defeats it) in the enemy loop.
      setEnemyHp(e, vm.checkNum([val], 0, "hp").float32)
      return
    of "maxHp":
      let v = vm.checkNum([val], 0, "maxHp").float32
      if not (v > 0.0'f32): vm.runtimeError("enemy.maxHp must be above 0")
      e.maxHp = v
      if e.isBoss and e.currentPhaseIndex >= 0 and e.currentPhaseIndex < e.bossPhaseHpPools.len:
        e.bossPhaseHpPools[e.currentPhaseIndex] = v
        var total = 0.0'f32
        for pool in e.bossPhaseHpPools: total += pool
        e.bossTotalMaxHp = total
      return
    of "type", "enemyType":
      # Becomes another kind of enemy (its AI and look from the next frame).
      var et: EnemyType
      if val.kind != vkString or not resolveEnemyName(val.str.s, et) or not isEnemyLive(et):
        vm.runtimeError("enemy." & name & " must be an enemy type name (enemies.types())")
      e.enemyType = et
      return
    of "bossDefinitionID":
      let id = vm.checkInt([val], 0, "bossDefinitionID")
      if not e.isBoss: vm.runtimeError("enemy.bossDefinitionID: not a boss")
      if getBossDefinition(id).phases.len == 0:
        vm.runtimeError("enemy.bossDefinitionID: no boss " & $id)
      e.bossDefinitionID = id
      return
    of "currentPhaseIndex":
      # A real phase change (HP pool, speed, attacks, the phase banner).
      if not e.isBoss: vm.runtimeError("enemy.currentPhaseIndex: not a boss")
      let def = getBossDefinition(e.bossDefinitionID)
      let idx = vm.checkInt([val], 0, "currentPhaseIndex")
      if idx < 0 or idx >= def.phases.len:
        vm.runtimeError("enemy.currentPhaseIndex: this boss has phases 0 to " & $(def.phases.len - 1))
      var g = modCtx.game
      if g.isNil: vm.runtimeError("enemy.currentPhaseIndex needs a run in progress")
      transitionBossToPhase(g, e, def, idx)
      return
    else: discard
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
    if name == "data": return vm.entityDataValue(EdBullet, vm.bulletDataId(b), "bullet")
    var found = false
    result = posGet(b.pos, b.vel, name, found)
    if found: return
    if not modCtx.match.isNil and not pvpBulletFieldImpl.isNil:
      result = pvpBulletFieldImpl(b, name, found)   # a PvP bullet's owner
      if found: return
    result = deepGet(b, name, "bullet", found)
    if not found: vm.runtimeError("bullet has no field '" & name & "'")
  bulletClass.newindex = proc (vm: VM, ud: Userdata, key, val: ScriptValue) =
    let b = BulletBox(ud.box).b
    let name = keyName(key)
    if name == "data":
      vm.setEntityData(EdBullet, vm.bulletDataId(b), val, "bullet")
      return
    if not modCtx.match.isNil:
      # A PvP bullet's kind / pierce are its mod fields (match:spawnBullet's
      # names); its owner is read-only.
      if name == "owner": vm.runtimeError("bullet.owner is read-only")
      if name in ["kind", "pierce"]:
        discard deepSet(vm, b, (if name == "kind": "modKind" else: "modPierce"), val, "bullet")
        return
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
      if not inRun:
        # a spawn.enemy handle waiting to join at the end of the frame
        inRun = e in modPendingEnemies or modCtx.game.pendingBoss == e
    ret.setRet(vbool(inRun))

  bulletMethods.reg("fields") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    let b = unwrapBullet(arg(args, 0))
    if b.isNil: vm.runtimeError("bullet:fields() needs a bullet (call it with ':')")
    ret.setRet(namesTable(deepNames(b)))
  bulletMethods.reg("valid") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## Still flying in the current run (or a spawn.bullet handle about to join).
    let b = unwrapBullet(arg(args, 0))
    if b.isNil: vm.runtimeError("bullet:valid() needs a bullet (call it with ':')")
    if not modCtx.match.isNil and not pvpBulletLiveImpl.isNil:
      ret.setRet(vbool(pvpBulletLiveImpl(b)))
      return
    let g = modCtx.game
    ret.setRet(vbool(not g.isNil and b.lifetime > 0 and
                     (b in g.bullets or b in modPendingBullets)))

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

proc parseLanguage(vm: VM, s: string): string =
  ## A language's settings name: "english", "spanish" or a mod language's id
  ## (register.language; its strings may come before it is registered).
  case s.toLowerAscii
  of "en", "english": $English
  of "es", "spanish", "espanol": $Spanish
  else:
    if s.len == 0 or s.len > 32 or not s.allCharsInSet(IdentChars + {'-'}):
      vm.runtimeError("'" & s & "' is not a language (\"en\", \"es\" or a register.language id)")
    s

proc languageCode(setting: string): string =
  ## lang.current's name for a language: "en" / "es" / the mod language's id.
  if setting == $English: "en" elif setting == $Spanish: "es" else: setting

proc installLibraries(base: ScriptTable) =
  # ---- hooks
  let hooksT = newScriptTable()
  hooksT.reg("on") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## hooks.on("update", function(game, dt) ... end)
    ## hooks.on("necro:raised", fn) -- a name with ':' is a mod event (hooks.emit)
    let owner = vm.requireOwner("hooks.on")
    let name = vm.checkStr(args, 0, "on")
    let fn = vm.checkFunc(args, 1, "on")
    if ':' in name: addCustomHandler(name, fn, owner)
    else: addHandler(vm.parseHook(name), fn, owner)
    ret.setRet(fn)
  hooksT.reg("off") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    let owner = vm.requireOwner("hooks.off")
    let name = vm.checkStr(args, 0, "off")
    let fn = vm.checkFunc(args, 1, "off")
    if ':' in name: removeCustomHandler(name, fn, owner)
    else: removeHandler(vm.parseHook(name), fn, owner)
  proc eventName(vm: VM, args: openArray[ScriptValue], fname: string): string =
    result = vm.checkStr(args, 0, fname)
    if ':' notin result:
      vm.argError(fname, 0, "a mod event is named \"<mod id>:<event>\" (got \"" & result & "\")")
  hooksT.reg("emit") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## hooks.emit("necro:raised", ...) -- every handler of the event, in order
    let name = vm.eventName(args, "emit")
    discard vm.requireOwner("hooks.emit")
    let rest = if args.len > 1: @(args.toOpenArray(1, args.high)) else: @[]
    if not emitCustom(name, rest):
      vm.runtimeError("hooks.emit: '" & name & "' nested more than " & $MaxCustomDepth & " deep")
  hooksT.reg("filter") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## hooks.filter("necro:soulValue", value, ...) -> the value after every
    ## handler (each gets (value, ...) and may return a replacement)
    let name = vm.eventName(args, "filter")
    discard vm.requireOwner("hooks.filter")
    var ok = true
    let rest = if args.len > 2: @(args.toOpenArray(2, args.high)) else: @[]
    let v = filterCustom(name, arg(args, 1), rest, ok)
    if not ok:
      vm.runtimeError("hooks.filter: '" & name & "' nested more than " & $MaxCustomDepth & " deep")
    ret.setRet(v)
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
    drawDisc(Vector2(x: vm.f32(args, 0, "circle"), y: vm.f32(args, 1, "circle")),
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
    drawRectOutline(Rectangle(x: vm.f32(args, 0, "rectLines"), y: vm.f32(args, 1, "rectLines"),
                                 width: vm.f32(args, 2, "rectLines"), height: vm.f32(args, 3, "rectLines")),
                       vm.optNum(args, 5, "rectLines", 1.0).float32,
                       parseColor(vm, arg(args, 4), "draw.rectLines"))
  drawT.reg("line") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    vm.requireDrawing("line")
    drawStroke(Vector2(x: vm.f32(args, 0, "line"), y: vm.f32(args, 1, "line")),
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
    ## draw.text(text, x, y, size, color [, font | {font = f, spacing = px}]) -> width in pixels
    vm.requireDrawing("text")
    let s = vm.checkStr(args, 0, "text")
    let (font, spacing) = vm.textFont(arg(args, 5), "draw.text")
    if font > 0:
      let size = fontSize(vm.checkNum(args, 3, "text"))
      drawModText(font, s, vm.f32(args, 1, "text"), vm.f32(args, 2, "text"), size, spacing,
                  parseColor(vm, arg(args, 4), "draw.text"))
      ret.setRet(vnum(measureModText(font, s, size, spacing).float64))
      return
    let size = clamp(vm.checkInt(args, 3, "text"), 1, 100_000).int32   # (int32 range)
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
    ## draw.textWidth(text [, size = 10, font | {font = f, spacing = px}])
    let (font, spacing) = vm.textFont(arg(args, 2), "draw.textWidth")
    if font > 0:
      ret.setRet(vnum(measureModText(font, vm.checkStr(args, 0, "textWidth"),
                                     fontSize(vm.optNum(args, 1, "textWidth", 10)), spacing).float64))
      return
    let size = clamp(vm.optInt(args, 1, "textWidth", 10), 1, 100_000).int32
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
    ## lang.current() -> "en", "es" or the id of the mod language in use
    ret.setRet(vstr(languageCode(languageSetting())))
  langT.reg("use") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## lang.use("fr") -> true: switch the game's language (and the setting);
    ## false: no such language is loaded (the game falls back to English)
    let setting = vm.parseLanguage(vm.checkStr(args, 0, "lang.use"))
    if not globalSettings.isNil: globalSettings.language = setting
    ret.setRet(vbool(useLanguage(setting)))
  langT.reg("list") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## lang.list() -> {{id = "en", name = "English"}, {id = "es", ...}, <mod languages>}
    let lt = newScriptTable()
    var n = 0
    template entry(id, name: string) =
      let e = newScriptTable()
      rawSet(e, vstr("id"), vstr(id))
      rawSet(e, vstr("name"), vstr(name))
      inc n
      rawSet(lt, vnum(n), vtable(e))
    entry("en", getLanguageName(English))
    entry("es", getLanguageName(Spanish))
    for l in modLanguages: entry(l.id, l.name)
    ret.setRet(vtable(lt))
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
  modsT.reg("dir") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## mods.dir("other_id") -> that loaded mod's folder (nil if it is not loaded)
    let id = vm.checkStr(args, 0, "dir")
    for m in mods:
      if m.id == id:
        ret.setRet(vstr(m.dir))
        return
    ret.setRet(NilValue)
  modsT.reg("list") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    var ids: seq[string]
    for m in mods:
      if not m.disabled: ids.add(m.id)
    ret.setRet(namesTable(ids))
  rawSet(base, vstr("mods"), vtable(modsT))

  # ---- engine: the game itself (its global state; later its procs)
  let engineT = newScriptTable()
  engineT.reg("defer") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## engine.defer(fn): run fn at the next safe point (after this frame's
    ## simulation, or at the top of the next frame), where lists may grow
    ## and shrink.
    deferCall(vm.requireOwner("engine.defer"), vm.checkFunc(args, 0, "defer"))
  let globalsCls = UdClass(name: "globals")
  globalsCls.index = proc (vm: VM, ud: Userdata, key: ScriptValue): ScriptValue =
    let name = keyName(key)
    var found = false
    result = modGlobalGet(name, found)
    if not found:
      vm.runtimeError("engine.globals has no '" & name & "' (it has " & modGlobalNames().join(", ") & ")")
  globalsCls.newindex = proc (vm: VM, ud: Userdata, key, val: ScriptValue) =
    if not modGlobalSet(vm, keyName(key), val):
      vm.runtimeError("engine.globals has no '" & keyName(key) & "'")
  globalsCls.next = proc (vm: VM, ud: Userdata, key: ScriptValue, k, v: var ScriptValue): bool =
    let names = modGlobalNames()
    var at = 0
    if key.kind == vkString:
      at = names.find(key.str.s) + 1
      if at == 0: return false
    if at >= names.len: return false
    var found = false
    k = vstr(names[at])
    v = modGlobalGet(names[at], found)
    true
  globalsCls.tostr = proc (ud: Userdata): string = "engine.globals"
  rawSet(engineT, vstr("globals"), vud(Userdata(cls: globalsCls, key: nil)))
  rawSet(engineT, vstr("version"), vstr(GameVersion))
  engineT.reg("atLeast") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## engine.atLeast("1.12") -> whether this game is that version or newer
    ret.setRet(vbool(versionAtLeast(GameVersion, vm.checkStr(args, 0, "engine.atLeast"))))
  engineT.reg("has") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## engine.has("screens.go") -> whether the API has it (a dotted path from
    ## the globals every mod sees; for the game's procs, mixin.has)
    var cur = vtable(modBase)
    for part in vm.checkStr(args, 0, "engine.has").split('.'):
      if cur.kind != vkTable or part.len == 0:
        cur = NilValue
        break
      cur = rawGetStr(cur.tbl, part)
    ret.setRet(vbool(cur.kind != vkNil))
  rawSet(base, vstr("engine"), vtable(engineT))

  # What engine.globals reaches from here (main.nim adds its own: the run on
  # screen, the desktop, the windows, the advancement profile). The player's
  # real progression is in there too: mods are trusted.
  registerModGlobal("settings", addr globalSettings)
  registerModGlobal("stats", addr globalStats)
  registerModGlobal("roguelite", addr activeRogueliteProfile)
  registerModGlobal("runStats", addr currentRunStats)
  registerModGlobal("sound", addr globalSoundSystem)
  registerModGlobal("difficulty", addr currentDifficulty)
  registerModGlobal("language", addr currentLanguage)
  registerModGlobal("profileSlot", addr activeProfileSlot)
  registerModGlobal("world3d", addr activeWorld3D)

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
        if k.kind != vkString or f.kind != vkFunction:
          vm.runtimeError("boss." & key & " must map names to functions")
        let route = "mod:" & bossKey & ":" & k.str.s
        if fnTable == 0: bossAttackFns[route] = ScriptFn(owner: owner, fn: f)
        else: bossBehaviorFns[route] = ScriptFn(owner: owner, fn: f)
  let draw = rawGetStr(t, "draw")
  if draw.kind == vkFunction:
    bossDrawFns[id] = ScriptFn(owner: owner, fn: draw)
  let process = rawGetStr(t, "process")
  if process.kind == vkString:
    modBossProcessNames[id] = process.str.s
  let slot = rawGetStr(t, "slotWave")
  if slot.kind == vkNumber:
    modBossSlotWaves[id] = max(5, int(slot.n))
  if result.phases.len == 0:
    vm.runtimeError("boss needs phases = { {attacks = {...}}, ... }")

proc buildScriptBullet*(vm: VM, t: ScriptTable): Bullet =
  ## spawn.bullet's table -> a bullet, not yet in the run.
  proc num(key: string, def: float32): float32 = vm.numField(t, key, "spawn.bullet", def)
  let vx = num("vx", 0)
  let vy = num("vy", 200)
  let speed = sqrt(vx * vx + vy * vy)
  let dir = if speed > 0: vec2(vx / speed, vy / speed) else: vec2(1, 0)
  result = newBullet(num("x", 0), num("y", 0), dir, speed, num("damage", 1),
                     fromPlayer = truthy(rawGetStr(t, "fromPlayer")))
  let r = num("radius", 0)
  if r > 0: result.radius = r
  let lt = num("lifetime", 0)
  if lt > 0: result.lifetime = lt
  let c = rawGetStr(t, "color")
  if c.kind != vkNil: result.colorOverride = parseColor(vm, c, "spawn.bullet")

proc installContentLibraries(base: ScriptTable) =
  # ---- spawn (carried out at the end of the frame, see processModActions)
  let spawnT = newScriptTable()
  spawnT.reg("enemy") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## spawn.enemy("etCube", x, y [, {elite = true, difficulty = 3, onSpawn = fn}])
    ## -> the enemy, at once: it joins the run at the end of the frame (e:valid()
    ## is already true; onSpawn runs when it joins).
    let owner = vm.requireOwner("spawn.enemy")
    let g = vm.requireRunGame()
    let et = vm.checkEnemyType(args, 0, "enemy")
    let x = vm.checkNum(args, 1, "enemy").float32
    let y = vm.checkNum(args, 2, "enemy").float32
    var a = ModAction(kind: makJoinEnemy, owner: owner)
    var difficulty = g.difficulty
    var elite = false
    let opts = arg(args, 3)
    if opts.kind == vkTable:
      elite = truthy(rawGetStr(opts.tbl, "elite"))
      let d = rawGetStr(opts.tbl, "difficulty")
      if d.kind == vkNumber: difficulty = max(0.0, d.n).float32
      a.callback = rawGetStr(opts.tbl, "onSpawn")
    elif opts.kind != vkNil:
      vm.argError("enemy", 3, "options must be a table")
    let e = newEnemy(x, y, difficulty, et, g)
    if elite: makeElite(e, g.currentWave, force = true)
    a.target = e
    modPendingEnemies.add(e)
    queueModAction(a)
    ret.setRet(wrapEnemy(e))
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
    ## -> the bullet, at once (it flies from the end of the frame)
    let owner = vm.requireOwner("spawn.bullet")
    discard vm.requireRunGame()
    let t = vm.checkTable(args, 0, "bullet")
    let b = vm.buildScriptBullet(t)
    modPendingBullets.add(b)
    queueModAction(ModAction(kind: makJoinBullet, owner: owner, bullet: b))
    ret.setRet(wrapBullet(b))
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
    ## spawn.consumable("ctHealth", x, y) -- or a mod's ("<mod id>:<id>")
    discard vm.requireRunGame()
    let name = vm.checkStr(args, 0, "consumable")
    var ct: ConsumableType
    var key = ""
    if ':' in name:
      if findConsumable(name) < 0:
        vm.argError("consumable", 0, "no consumable '" & name & "' (register.consumable it first)")
      ct = ctMod
      key = name
    else:
      try: ct = parseEnum[ConsumableType](name)
      except ValueError: ct = ctMod
      if ct == ctMod:
        var names: seq[string]
        for c in ConsumableType:
          if c != ctMod: names.add($c)
        vm.argError("consumable", 0, "unknown consumable (" & names.join(", ") & ", or a mod's)")
    queueModAction(ModAction(kind: makSpawnConsumable, owner: vm.requireOwner("spawn.consumable"),
                             consumable: ct, key: key, x: vm.f32(args, 1, "consumable"),
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
    ## Dies this frame with the normal rewards. A boss skips its remaining
    ## phases and is defeated the normal way (rewards, the boss wave ending).
    let e = vm.selfEnemy(args, "kill")
    if e.isBoss:
      let phases = getBossDefinition(e.bossDefinitionID).phases.len
      if phases > 0: e.currentPhaseIndex = phases - 1
    e.hp = 0
    if e.requiredHits > 0: e.hitCount = max(e.hitCount, e.requiredHits)
  enemyMethods.reg("remove") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## Vanishes at the end of the frame: no death, no rewards. A boss is never
    ## removed: its phases and its boss wave only end through its defeat
    ## (enemy:kill() defeats it at once).
    let e = vm.selfEnemy(args, "remove")
    queueModAction(ModAction(kind: makRemoveEnemy, owner: vm.requireOwner("enemy:remove"), target: e))
  enemyMethods.reg("heal") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## Up to its maxHp (a boss: its current phase pool's).
    let e = vm.selfEnemy(args, "heal")
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
    ## player:hurt(amount [, {cause = "Lava"}]) -> true if it was lethal (profile
    ## difficulty applies). With a cause, a lethal hurt ends the run at once and
    ## the death screen names it.
    let p = vm.selfPlayer(args, "hurt")
    var cause = ""
    let opts = arg(args, 2)
    if opts.kind == vkTable:
      vm.checkKeys(opts.tbl, ["cause"], "player:hurt")
      let c = rawGetStr(opts.tbl, "cause")
      if c.kind == vkString: cause = c.str.s
      elif c.kind != vkNil: vm.runtimeError("player:hurt: cause must be a string")
    elif opts.kind != vkNil:
      vm.argError("hurt", 2, "options must be a table")
    let lethal = takeDamage(p, max(0.0, vm.checkNum(args, 1, "hurt")).float32)
    let g = modCtx.game
    if lethal and cause.len > 0 and not g.isNil and p in g.players and g.state == gsPlaying:
      g.modWorld.deathLabel = cause
      withPlayer(g, p):   # (any player of a co-op run, not only the active one)
        beginPlayerDeathSequence(g, dcMod)
    ret.setRet(vbool(lethal))

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
                         max(vm.optInt(args, 3, "particles", 20), 1))
  fxT.reg("damageNumber") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## fx.damageNumber(x, y, amount [, critical])
    let g = vm.requireRunGame()
    showDamage(g, vec2(vm.checkNum(args, 0, "damageNumber").float32,
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
        if v.kind != vkFunction:
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
  registerT.reg("language") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## register.language{id = "fr", name = "Francais", base = "en" | "es",
    ##   strings = {key = "text", ...}} -> "fr": a language of the game, listed
    ## in Settings and the first-run picker. Its gaps show the base language.
    ## Registering the same id again (another mod, a translation pack) adds
    ## strings; lang.set("fr", key, text) does too.
    let owner = vm.requireLoading("register.language")
    let t = vm.checkTable(args, 0, "register.language")
    vm.checkKeys(t, ["id", "name", "base", "strings"], "register.language")
    let idV = rawGetStr(t, "id")
    if idV.kind != vkString: vm.runtimeError("register.language needs id = \"<language id>\"")
    let id = vm.parseLanguage(idV.str.s)
    if id in [$English, $Spanish]:
      vm.runtimeError("register.language: '" & idV.str.s & "' is built in (add its strings with lang.set)")
    let baseV = rawGetStr(t, "base")
    var base = English
    if baseV.kind == vkString and vm.parseLanguage(baseV.str.s) == $Spanish: base = Spanish
    elif baseV.kind != vkNil and not (baseV.kind == vkString and vm.parseLanguage(baseV.str.s) == $English):
      vm.runtimeError("register.language.base must be \"en\" or \"es\"")
    let nameV = rawGetStr(t, "name")
    if nameV.kind notin {vkNil, vkString}: vm.runtimeError("register.language.name must be a string")
    let name = if nameV.kind == vkString: nameV.str.s else: ""
    languageDefs.add((ModLanguage(id: id, name: name, base: base), owner))
    addModLanguage(id, name, base)
    let s = rawGetStr(t, "strings")
    if s.kind == vkTable:
      for (k, v) in pairsCursor(s.tbl):
        if k.kind != vkString or v.kind != vkString:
          vm.runtimeError("register.language.strings must map keys to text")
        addModText(id, k.str.s, v.str.s, owner)
    elif s.kind != vkNil: vm.runtimeError("register.language.strings must be a table")
    ret.setRet(vstr(id))
  registerT.reg("keybind") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    let owner = vm.requireLoading("register.keybind")
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
    let owner = vm.requireLoading("register.boss")
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
  stats: seq[StatDelta]        ## applied once per level gained (the `stats` table)

var
  puScripts: array[ModPowerUpSlot, ModPowerUpScript]
  enemyOwners: array[ModEnemySlot, int]

proc textPair*(vm: VM, v: ScriptValue, what: string): tuple[en, es: string] =
  ## "Text" or {en = "Text", es = "Texto"}; any other key is a mod language's
  ## ({en = "Souls", fr = "Ames"}), which pickText shows while it is in use
  ## (texts a mod registers while it loads; a runtime text picks itself).
  case v.kind
  of vkString: (v.str.s, "")
  of vkTable:
    let en = rawGetStr(v.tbl, "en")
    let es = rawGetStr(v.tbl, "es")
    let enText = if en.kind == vkString: en.str.s else: ""
    if enText.len > 0 and modLoading and currentModIdx >= 0:
      for (k, tv) in pairsCursor(v.tbl):
        if k.kind == vkString and tv.kind == vkString and k.str.s notin ["en", "es"]:
          addModText(vm.parseLanguage(k.str.s), enText, tv.str.s, currentModIdx, isText = true)
    (enText, (if es.kind == vkString: es.str.s else: ""))
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
  pickText(en, es)

proc modPowerUpTextImpl(pt: PowerUpType, level: int, wantName: bool): string {.nimcall.} =
  if not isModPowerUp(pt): return ""
  let s = puScripts[pt]
  if wantName:
    return pickLang(s.nameEn, s.nameEs)
  if s.descFn.kind == vkFunction:
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
  applyStatDeltas(player, s.stats)
  if s.onPickup.kind == vkFunction:
    var r: RetVals
    discard callForPowerUp(pt, ScriptFn(owner: s.owner, fn: s.onPickup),
                           [wrapPlayer(player), vnum(level), wrapGame(modCtx.game)], r)

proc modPowerUpIconImpl(pt: PowerUpType, color: Color): bool {.nimcall.} =
  if not isModPowerUp(pt): return false
  let s = puScripts[pt]
  if s.icon.kind != vkFunction: return false
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
  activeCooldownOf = proc (pt: PowerUpType): float32 {.nimcall.} = powerUpDef(pt).activeCooldown
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

proc checkName*(vm: VM, t: ScriptTable, what: string): string =
  let v = rawGetStr(t, "id")
  if v.kind != vkString or v.str.s.len == 0:
    vm.runtimeError(what & " needs an id (letters, digits, _)")
  result = v.str.s
  for c in result:
    if c notin {'a'..'z', 'A'..'Z', '0'..'9', '_'}:
      vm.runtimeError(what & ": id may only use letters, digits and _ (got \"" & result & "\")")

proc parseModes*(vm: VM, v: ScriptValue): set[GameMode] =
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
    let owner = vm.requireLoading("register.powerup")
    let t = vm.checkTable(args, 0, "powerup")
    let key = mods[owner].id & ":" & vm.checkName(t, "register.powerup")
    var slot = FirstModPowerUp
    var found = false
    for pt in ModPowerUpSlot:
      if modPowerUps[pt].key == key: vm.runtimeError("register.powerup: '" & key & "' is already registered")
      if not found and not modPowerUps[pt].bound:
        slot = pt
        found = true
    if not found:
      vm.runtimeError("register.powerup: all " & $(ord(LastModPowerUp) - ord(FirstModPowerUp) + 1) &
                      " mod power-up slots are in use")
    var def = PowerUpDef(pool: puppNormal, family: rpfCore, group: pugNone, maxLevel: 3,
                         color: Color(r: 190, g: 190, b: 255, a: 255))
    vm.applyPowerUpFields(def, t, "register.powerup")
    var s = ModPowerUpScript(owner: owner)
    (s.nameEn, s.nameEs) = vm.textPair(rawGetStr(t, "name"), "name")
    if s.nameEn.len == 0: s.nameEn = key.split(':')[1].toUpperAscii & ".exe"
    let d = rawGetStr(t, "description")
    case d.kind
    of vkFunction: s.descFn = d
    of vkTable:
      if rawGetStr(d.tbl, "en").kind != vkNil or rawGetStr(d.tbl, "es").kind != vkNil:
        s.descEn = vm.textList(rawGetStr(d.tbl, "en"), "description.en")
        s.descEs = vm.textList(rawGetStr(d.tbl, "es"), "description.es")
      else:
        s.descEn = vm.textList(d, "description")
    else: s.descEn = vm.textList(d, "description")
    s.icon = rawGetStr(t, "icon")
    s.onPickup = rawGetStr(t, "onPickup")
    let st = rawGetStr(t, "stats")
    if st.kind == vkTable:
      for (k, x) in pairsCursor(st.tbl):
        if k.kind != vkString: vm.runtimeError("register.powerup.stats keys must be player field names")
        var e = ""
        let d = parseStatDelta(k.str.s, x, e)
        if e.len > 0: vm.runtimeError("register.powerup: " & e)
        s.stats.add(d)
    elif st.kind != vkNil: vm.runtimeError("register.powerup.stats must be a table")
    # Per-frame and per-hit behaviour, run only while the player has it (and
    # credited to it in the run statistics).
    let upd = rawGetStr(t, "update")
    if upd.kind == vkFunction: powerUpUpdateFns[ord(slot)] = ScriptFn(owner: owner, fn: upd)
    let hit = rawGetStr(t, "onHit")
    if hit.kind == vkFunction: powerUpHitFns[ord(slot)] = ScriptFn(owner: owner, fn: hit)
    # An active [Q] ability: active = {cooldown = seconds, activate = fn(player, level, game)}
    let act = rawGetStr(t, "active")
    if act.kind == vkTable:
      vm.checkKeys(act.tbl, ["cooldown", "activate"], "register.powerup.active")
      let fn = rawGetStr(act.tbl, "activate")
      if fn.kind != vkFunction:
        vm.runtimeError("register.powerup.active needs activate = function(player, level, game)")
      let cd = rawGetStr(act.tbl, "cooldown")
      def.activeCooldown = if cd.kind == vkNumber and abs(cd.n) < 1.0e6: max(0.0, cd.n).float32 else: 5'f32
      def.inLegendaryPanel = true
      powerUpActiveFns[ord(slot)] = ScriptFn(owner: owner, fn: fn)
    elif act.kind != vkNil:
      vm.runtimeError("register.powerup.active must be a table {cooldown, activate}")
    puScripts[slot] = s
    modPowerUps[slot] = ModPowerUpInfo(bound: true, key: key)
    setPowerUpDef(slot, def)
    ret.setRet(vstr(key))

  registerT.reg("enemy") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## local name = register.enemy{id = "bouncer", base = "etCube", hp = 3, ...}
    let owner = vm.requireLoading("register.enemy")
    let t = vm.checkTable(args, 0, "enemy")
    let idName = vm.checkName(t, "register.enemy")
    let key = mods[owner].id & ":" & idName
    var slot = FirstModEnemy
    var found = false
    for et in ModEnemySlot:
      if modEnemies[et].key == key: vm.runtimeError("register.enemy: '" & key & "' is already registered")
      if not found and not modEnemies[et].bound:
        slot = et
        found = true
    if not found:
      vm.runtimeError("register.enemy: all " & $(ord(LastModEnemy) - ord(FirstModEnemy) + 1) &
                      " mod enemy slots are in use")
    var base = etCircle
    let b = rawGetStr(t, "base")
    if b.kind == vkString:
      var parsed: EnemyType
      if not resolveEnemyScriptName(b.str.s, parsed) or isModEnemy(parsed) or parsed == etEnvironment:
        vm.runtimeError("register.enemy: base must be one of the game's own enemy types, got '" &
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
    if upd.kind == vkFunction: enemyUpdateFns[ord(slot)] = ScriptFn(owner: owner, fn: upd)
    let drw = rawGetStr(t, "draw")
    if drw.kind == vkFunction: enemyDrawFns[ord(slot)] = ScriptFn(owner: owner, fn: drw)
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
    if upd.kind == vkFunction: powerUpUpdateFns[ord(pt)] = ScriptFn(owner: owner, fn: upd)
    let hit = rawGetStr(t, "onHit")
    if hit.kind == vkFunction: powerUpHitFns[ord(pt)] = ScriptFn(owner: owner, fn: hit)

  let rosterT = newScriptTable()
  rosterT.reg("add") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## roster.add("wave", "mymod:bouncer", {chance = 0.15, fromWave = 3})
    ## (survival: minTime = seconds; roguelite: minFloor = sector)
    let owner = vm.requireLoading("roster.add")
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
# assets.texture / assets.model / assets.sound load files (relative paths are
# the mod's own folder, absolute ones anywhere); override.texture/model/sound/
# music swap the game's look and sound; register.cosmetic adds skins players
# equip in MODS.EXE.

var soundClass, shaderClass, musicClass: UdClass
var textureClass*, modelClass*, videoClass*: UdClass

# ------------------------------------------------------ file sandbox ----
# A mod reads files in its own folder and in its mod.dataDir() (a folder of
# its own in the profile), and writes only in mod.dataDir(): its folder is
# read-only (a file written there would change its fingerprint and move its
# saves). Relative paths start in the mod's folder. The game's natives check
# paths here; the Lua libraries' own file calls do too, through fileGate.

proc modDataDir(m: ModRuntime): string =
  ## In the profile folder mod.storage was read from (see storagePath).
  (if m.storageDir.len > 0: m.storageDir else: getAppDataPath() / "mod_data") / m.id

proc insideDir(path, dir: string): bool =
  ## `path` is `dir` or below it (both normalized; case-blind on Windows).
  var p = path
  var d = dir
  when defined(windows):
    p = p.replace('/', '\\').toLowerAscii
    d = d.replace('/', '\\').toLowerAscii
  while d.len > 1 and d[^1] in {'/', '\\'}: d.setLen(d.len - 1)
  p == d or (p.len > d.len and p.startsWith(d) and p[d.len] in {'/', '\\'})

proc confineModPath(m: ModRuntime, rel: string, write: bool): tuple[path, err: string] =
  ## Where a script's path points and whether the mod may use it there
  ## (`err` says why not).
  let full = normalizedPath(if rel.isAbsolute: rel else: m.dir / rel)
  let data = normalizedPath(modDataDir(m))
  if insideDir(full, data):
    if write:
      try: createDir(data)
      except OSError, IOError: discard
    return (full, "")
  if m.dir.len > 0 and insideDir(full, normalizedPath(m.dir)):
    if not write: return (full, "")
    return ("", "'" & rel & "' is in the mod's folder, which is read-only (write to mod.dataDir())")
  ("", "'" & rel & "' is outside the mod's folders (a mod reads its folder and mod.dataDir(), " &
       "and writes only mod.dataDir())")

proc modFileGate(path: string, write, quiet: bool): tuple[path, err: string] =
  ## lua_bridge's fileGate, for the running mod.
  if currentModIdx < 0 or currentModIdx >= mods.len:
    return ("", "files can only be opened by a mod's own code")
  let m = mods[currentModIdx]
  result = confineModPath(m, path, write)
  if result.err.len > 0 and not quiet: modLogAdd(mlWarn, m.id, "file refused: " & result.err)

fileGate = modFileGate

proc modPath(vm: VM, rel, what: string): string =
  ## Where the calling mod's path points (the file may not exist).
  let owner = vm.requireOwner(what)
  let (path, err) = confineModPath(mods[owner], rel, write = false)
  if err.len > 0: vm.runtimeError(what & ": " & err)
  path

proc modFile(vm: VM, rel, what: string): string =
  result = vm.modPath(rel, what)
  if not fileExists(result): vm.runtimeError(what & ": file not found: " & rel)

proc loadTextureFile(vm: VM, rel, what: string): int =
  ## An image or a video from the mod's folder, as a texture.
  var err = ""
  result = loadModTexture(vm.modFile(rel, what), err)
  if result == 0: vm.runtimeError(what & ": " & rel & ": " & err)

proc textureId*(vm: VM, v: ScriptValue, what: string): int =
  ## A texture (or video) handle, or a path (loaded on the spot).
  if v.kind == vkUserdata and (v.ud.cls == textureClass or v.ud.cls == videoClass):
    return v.ud.handle
  if v.kind == vkString: return vm.loadTextureFile(v.str.s, what)
  vm.runtimeError(what & ": texture expected (assets.texture(...), assets.video(...) or a file name)")

proc frameOption*(vm: VM, opts: ScriptTable, id: int, what: string): int =
  ## The GIF frame (0-based) a draw's `frame` (1 = first, wraps) or `time`
  ## (seconds into the animation) option picks; -1 = neither (the wall clock).
  let fr = rawGetStr(opts, "frame")
  let tm = rawGetStr(opts, "time")
  if fr.kind == vkNumber:
    # a positive range test: release builds use fast math, where x != x is folded away
    if not (abs(fr.n) <= 9.0e15): vm.runtimeError(what & ": frame must be a whole number")
    floorMod(int(floor(fr.n)) - 1, textureFrames(id))
  elif tm.kind == vkNumber:
    textureFrameAt(id, tm.n)
  else:
    -1

proc loadModelFile(vm: VM, rel, what: string): int =
  ## A model from the mod's folder.
  var err = ""
  result = loadModModel(vm.modFile(rel, what), err)
  if result == 0: vm.runtimeError(what & ": " & rel & ": " & err)

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
  result = ModelPose(speed: 1, lit: true, tint: White, fade: 0.2)
  if opts.kind != vkTable:
    result.anim = vm.resolveAnim(id, NilValue, what)
    return
  for (field, dest) in [("tilt", addr result.tilt), ("yaw", addr result.yaw),
                        ("pitch", addr result.pitch), ("roll", addr result.roll),
                        ("spin", addr result.spin), ("speed", addr result.speed),
                        ("fade", addr result.fade)]:
    let v = rawGetStr(opts.tbl, field)
    if v.kind == vkNumber and abs(v.n) < 1.0e9: dest[] = v.n.float32   # (NaN fails too)
    elif v.kind != vkNil: vm.runtimeError(what & ": " & field & " must be a number")
  result.fade = max(result.fade, 0)
  let lit = rawGetStr(opts.tbl, "lit")
  if lit.kind != vkNil: result.lit = truthy(lit)
  let tn = rawGetStr(opts.tbl, "tint")
  if tn.kind != vkNil: result.tint = parseColor(vm, tn, what & ".tint")
  result.anim = vm.resolveAnim(id, rawGetStr(opts.tbl, "animation"), what)

proc readAnimKey*(vm: VM, opts: ScriptValue, what: string): AnimKey =
  ## draw.model / draw3d.model's `key`: a string or number naming what is
  ## drawn, so it crossfades when its animation changes (each mod's keys are
  ## its own).
  if opts.kind != vkTable: return NoAnimKey
  let k = rawGetStr(opts.tbl, "key")
  case k.kind
  of vkNil: NoAnimKey
  of vkString: animKey(cast[pointer](vm), k.str.s)
  of vkNumber: animKey(cast[pointer](vm), $k.n)
  else: vm.runtimeError(what & ": key must be a string or a number")

proc readScaleRotate*(opts: ScriptValue, look: var BodyReplace) =
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
    # By extension: an image or a video is a texture, anything else is tried as a model.
    if isTextureFile(ic.str.s): icon.id = vm.textureId(ic, what & " icon")
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

proc restoreBudget(vm: VM, v: ScriptValue, what: string): int =
  ## One budget: a whole number from 0, or "unlimited".
  if v.kind == vkString and v.str.s == "unlimited": return UnlimitedLives
  if v.kind == vkNumber and v.n >= 0 and v.n <= 1000 and v.n == floor(v.n): return int(v.n)
  vm.runtimeError(what & " must be a whole number from 0 to 1000 or \"unlimited\"")

proc readRestoreRule(vm: VM, t: ScriptTable): ModRestoreRule =
  ## register.gamemode's restorePoints (false: none at all; a budget for every
  ## difficulty; or {easy =, medium =, hard =, nightmare =}, where a missing
  ## difficulty keeps the base mode's) and restoreGlyphs (false: no meters).
  let rp = rawGetStr(t, "restorePoints")
  case rp.kind
  of vkNil: discard
  of vkBool: result.disabled = not rp.b
  of vkTable:
    for (k, v) in pairsCursor(rp.tbl):
      if k.kind != vkString:
        vm.runtimeError("register.gamemode: restorePoints keys must be difficulty names")
      var d: GameDifficulty
      try: d = parseEnum[GameDifficulty](k.str.s)
      except ValueError:
        vm.runtimeError("register.gamemode: unknown difficulty '" & k.str.s &
                        "' in restorePoints (easy, medium, hard, nightmare)")
      result.budget[d] = vm.restoreBudget(v, "register.gamemode: restorePoints." & k.str.s)
      result.custom.incl(d)
  else:
    let n = vm.restoreBudget(rp, "register.gamemode: restorePoints")
    for d in GameDifficulty:
      result.budget[d] = n
    result.custom = {low(GameDifficulty) .. high(GameDifficulty)}
  let g = rawGetStr(t, "restoreGlyphs")
  case g.kind
  of vkNil: discard
  of vkBool: result.hideGlyphs = not g.b
  else: vm.runtimeError("register.gamemode: restoreGlyphs must be true or false")

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
        if v.kind == vkUserdata and (v.ud.cls == textureClass or v.ud.cls == videoClass):
          # shader:set("noise", tex): a sampler2D reads a texture or a video
          let status = setModShaderTexture(self.ud.handle, name, v.ud.handle)
          if status < 0:
            vm.argError("set", 2, "a shader reads at most " & $MaxShaderTextures & " textures")
          r.setRet(vbool(status > 0))
          return
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

  # A method of a video or music handle: checks `self`, then runs `body`, which
  # sees `vm`, `args` and the handle's `id` (a video's is its texture id).
  template mediaMethod(klass: UdClass, kindName, mname: string, body: untyped): ScriptValue {.dirty.} =
    vnative(newNative(mname, proc (vm: VM, args: openArray[ScriptValue], r: var RetVals) =
      let self = arg(args, 0)
      if self.kind != vkUserdata or self.ud.cls != klass:
        vm.runtimeError(kindName & ":" & mname & "() needs a " & kindName & " (call it with ':')")
      let id = self.ud.handle
      body))
  proc numberArg(vm: VM, v: ScriptValue, what: string): float =
    if v.kind != vkNumber or not (abs(v.n) < 1.0e9): vm.runtimeError(what & " must be a number")
    v.n

  videoClass = UdClass(name: "video")
  videoClass.index = proc (vm: VM, ud: Userdata, key: ScriptValue): ScriptValue =
    let info = videoInfo(textureVideo(ud.handle))
    case keyName(key)
    of "width": vnum(info.width)
    of "height": vnum(info.height)
    of "duration": vnum(info.duration)
    of "time": vnum(info.time)
    of "fps": vnum(info.fps)
    of "playing": vbool(info.playing)
    of "paused": vbool(info.paused)
    of "ended": vbool(info.ended)
    of "hasAudio": vbool(info.hasAudio)
    of "loop": vbool(info.loop)
    of "volume": vnum(info.volume.float64)
    of "play":
      mediaMethod(videoClass, "video", "play"):
        playVideo(textureVideo(id))
    of "pause":
      mediaMethod(videoClass, "video", "pause"):
        pauseVideo(textureVideo(id))
    of "stop":
      mediaMethod(videoClass, "video", "stop"):
        stopVideo(textureVideo(id))
    of "seek":
      mediaMethod(videoClass, "video", "seek"):
        seekVideo(textureVideo(id), vm.numberArg(arg(args, 1), "video:seek's seconds"))
    else: vm.runtimeError("video has no field '" & keyName(key) & "'")
  videoClass.newindex = proc (vm: VM, ud: Userdata, key, val: ScriptValue) =
    case keyName(key)
    of "loop": setVideoLoop(textureVideo(ud.handle), truthy(val))
    of "volume": setVideoVolume(textureVideo(ud.handle), vm.numberArg(val, "video.volume").float32)
    else: vm.runtimeError("video." & keyName(key) & " cannot be set (only loop and volume)")
  videoClass.tostr = proc (ud: Userdata): string = "video #" & $ud.handle

  musicClass = UdClass(name: "music")
  musicClass.index = proc (vm: VM, ud: Userdata, key: ScriptValue): ScriptValue =
    let info = musicInfo(ud.handle)
    case keyName(key)
    of "duration": vnum(info.duration.float64)
    of "time": vnum(info.time.float64)
    of "playing": vbool(info.playing)
    of "paused": vbool(info.paused)
    of "loop": vbool(info.loop)
    of "layer": vbool(info.layer)
    of "volume": vnum(info.volume.float64)
    of "pitch": vnum(info.pitch.float64)
    of "pan": vnum(info.pan.float64)
    of "play":
      mediaMethod(musicClass, "music", "play"):
        playModMusic(id, not modCtx.game.isNil)
    of "pause":
      mediaMethod(musicClass, "music", "pause"):
        pauseModMusic(id)
    of "stop":
      mediaMethod(musicClass, "music", "stop"):
        stopModMusic(id)
    of "seek":
      mediaMethod(musicClass, "music", "seek"):
        seekModMusic(id, vm.numberArg(arg(args, 1), "music:seek's seconds").float32)
    else: vm.runtimeError("music has no field '" & keyName(key) & "'")
  musicClass.newindex = proc (vm: VM, ud: Userdata, key, val: ScriptValue) =
    var m = musicInfo(ud.handle)
    case keyName(key)
    of "loop": m.loop = truthy(val)
    of "layer": m.layer = truthy(val)
    of "volume": m.volume = vm.numberArg(val, "music.volume").float32
    of "pitch": m.pitch = vm.numberArg(val, "music.pitch").float32
    of "pan": m.pan = vm.numberArg(val, "music.pan").float32
    else: vm.runtimeError("music." & keyName(key) & " cannot be set " &
                          "(only loop, layer, volume, pitch and pan)")
    setMusicOption(ud.handle, m.loop, m.layer, m.volume, m.pitch, m.pan)
  musicClass.tostr = proc (ud: Userdata): string = "music #" & $ud.handle

  fontClass = UdClass(name: "font")
  fontClass.index = proc (vm: VM, ud: Userdata, key: ScriptValue): ScriptValue =
    if keyName(key) == "size": return vnum(fontBaseSize(ud.handle))
    vm.runtimeError("font has no field '" & keyName(key) & "'")
  fontClass.tostr = proc (ud: Userdata): string = "font #" & $ud.handle

  let assetsT = newScriptTable()
  assetsT.reg("texture") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## local tex = assets.texture("sprites/ship.png")  -- an image (PNG, JPG, GIF, ...)
    ## or a video in your mod folder
    let id = vm.loadTextureFile(vm.checkStr(args, 0, "texture"), "assets.texture")
    ret.setRet(vud(Userdata(cls: textureClass, handle: id, key: cast[pointer](id))))
  assetsT.reg("video") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## local clip = assets.video("intro.mpg")  -- MPEG-1 (convert anything else with
    ## ffmpeg, see MODDING.md). Goes wherever a texture goes.
    let rel = vm.checkStr(args, 0, "video")
    let id = vm.loadTextureFile(rel, "assets.video")
    if textureVideo(id) == 0:
      vm.runtimeError("assets.video: " & rel & ": not a video (an MPEG-1 .mpg file is)")
    ret.setRet(vud(Userdata(cls: videoClass, handle: id, key: cast[pointer](id + 400000))))
  assetsT.reg("music") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## local theme = assets.music("music/theme.ogg"); theme:play()
    let rel = vm.checkStr(args, 0, "music")
    var err = ""
    let id = loadModMusic(vm.modFile(rel, "assets.music"), err)
    if id == 0: vm.runtimeError("assets.music: " & rel & ": " & err)
    ret.setRet(vud(Userdata(cls: musicClass, handle: id, key: cast[pointer](id + 500000))))
  assetsT.reg("font") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## local f = assets.font("fonts/pixel.ttf" [, {size = 32, smooth = true, chars = "..."}])
    let rel = vm.checkStr(args, 0, "font")
    let opts = arg(args, 1)
    if opts.kind notin {vkNil, vkTable}: vm.argError("font", 1, "options must be a table")
    let ext = rel.splitFile.ext.toLowerAscii
    var size = 32
    var smooth = ext in [".ttf", ".otf"]   # bitmap fonts stay sharp
    var chars = ""
    if opts.kind == vkTable:
      let s = rawGetStr(opts.tbl, "size")
      if s.kind == vkNumber and s.n >= 4 and s.n <= 256: size = int(s.n)
      elif s.kind != vkNil: vm.runtimeError("assets.font: size must be a number from 4 to 256")
      let sm = rawGetStr(opts.tbl, "smooth")
      if sm.kind != vkNil: smooth = truthy(sm)
      let c = rawGetStr(opts.tbl, "chars")
      if c.kind == vkString: chars = c.str.s
      elif c.kind != vkNil: vm.runtimeError("assets.font: chars must be a string")
    var err = ""
    let id = loadModFont(vm.modFile(rel, "assets.font"), size, smooth, chars, err)
    if id == 0: vm.runtimeError("assets.font: " & rel & ": " & err)
    ret.setRet(vud(Userdata(cls: fontClass, handle: id, key: cast[pointer](id + 600000))))
  assetsT.reg("text") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## assets.text("data/story.txt") -> the file's contents (a string)
    let rel = vm.checkStr(args, 0, "text")
    let path = vm.modFile(rel, "assets.text")
    try: ret.setRet(vstr(readFile(path)))
    except IOError: vm.runtimeError("assets.text: cannot read " & rel)
  assetsT.reg("json") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## assets.json("data/levels.json") -> its value (tables, numbers, strings, booleans)
    let rel = vm.checkStr(args, 0, "json")
    let path = vm.modFile(rel, "assets.json")
    var node: JsonNode
    try: node = parseJson(readFile(path))
    except IOError: vm.runtimeError("assets.json: cannot read " & rel)
    except JsonParsingError as e: vm.runtimeError("assets.json: " & rel & ": " & e.msg)
    except ValueError as e: vm.runtimeError("assets.json: " & rel & ": " & e.msg)
    ret.setRet(fromJsonNode(node))
  assetsT.reg("exists") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## assets.exists("music/boss.ogg") -> is there such a file (or folder) in your mod?
    let path = vm.modPath(vm.checkStr(args, 0, "exists"), "assets.exists")
    ret.setRet(vbool(fileExists(path) or dirExists(path)))
  assetsT.reg("list") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## assets.list(["levels"]) -> the names in a folder of your mod, sorted;
    ## folders end with "/"
    let rel = vm.optStr(args, 0, "list", "")
    let path = if rel.len == 0 or rel == ".": mods[vm.requireOwner("assets.list")].dir
               else: vm.modPath(rel, "assets.list")
    if not dirExists(path): vm.runtimeError("assets.list: no folder '" & rel & "' in the mod")
    var names: seq[string]
    for kind, entry in walkDir(path, relative = true):
      names.add(if kind in {pcDir, pcLinkToDir}: entry & "/" else: entry)
    names.sort(cmpIgnoreCase)
    ret.setRet(namesTable(names))
  assetsT.reg("sound") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## local s = assets.sound("sfx/zap.wav"); s:play([volume, pitch])
    let rel = vm.checkStr(args, 0, "sound")
    let id = loadModSound(vm.modFile(rel, "assets.sound"))
    if id == 0: vm.runtimeError("assets.sound: could not load '" & rel & "' (WAV, OGG, MP3, FLAC or QOA)")
    ret.setRet(vud(Userdata(cls: soundClass, handle: id, key: cast[pointer](id + 100000))))
  assetsT.reg("shader") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## local crt = assets.shader("fx/crt.fs" [, "fx/crt.vs"])  -- a GLSL fragment
    ## shader (and a vertex shader); it gets `time` and `resolution` uniforms,
    ## and shader:set(name, value) for yours (numbers, vectors, textures).
    let rel = vm.checkStr(args, 0, "shader")
    let vsRel = vm.optStr(args, 1, "shader", "")
    let vs = if vsRel.len > 0: vm.modFile(vsRel, "assets.shader") else: ""
    var err = ""
    let id = loadModShader(vm.modFile(rel, "assets.shader"), err, vs)
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
      frame = vm.frameOption(opts.tbl, id, "draw.texture")
    drawModTexture(id, vm.f32(args, 1, "texture"), vm.f32(args, 2, "texture"), w, h, rot, tint,
                   centered, frame)
  drawT.reg("model") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## draw.model(mdl, x, y [, {size = px, scale = px per unit, facing = deg,
    ##            tilt/yaw/pitch/roll = deg, spin = deg/s, animation = name | n | false,
    ##            speed = x, time = seconds, frame = n, lit = bool, tint = color,
    ##            key = name | n, fade = seconds}])
    ## Centred on x, y; its footprint (seen from above) is `size` wide (64 by
    ## default); its front points toward `facing` (90 = down, the default).
    ## With a `key`, a change of animation crossfades over `fade` seconds.
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
        frame = floorMod(int(floor(fr.n)) - 1, modelAnimFrames(id, pose.anim)).float32
      elif tm.kind == vkNumber:
        frame = modelFrameAt(id, pose, tm.n)   # (a NaN time shows frame 1)
    drawModModel(id, x, y, pxPerUnit, facing, pose, frame, vm.readAnimKey(opts, "draw.model"))

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
      vm.runtimeError("override.sound: could not load the file (WAV, OGG, MP3, FLAC or QOA)")
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
    ## override.music("wave" | "menu" | "powerUp" | "boss" | "survival" |
    ##   "roguelite" | "storyIntro" | "storyRootAccess" | "storyBelow" |
    ##   "storyUptime", "music/track.ogg")
    let name = vm.checkStr(args, 0, "music")
    var track: MusicTrack
    try: track = parseEnum[MusicTrack]("mt" & name.capitalizeAscii)
    except ValueError: vm.argError("music", 0, "use \"menu\", \"wave\", \"powerUp\", \"boss\", " &
                                   "\"survival\", \"roguelite\", \"storyIntro\", \"storyRootAccess\", " &
                                   "\"storyBelow\" or \"storyUptime\"")
    if not setModMusic(track, vm.modFile(vm.checkStr(args, 1, "music"), "override.music")):
      vm.runtimeError("override.music: could not load the file (OGG, MP3, WAV, FLAC, QOA, XM or MOD)")

  let registerT = rawGetStr(base, "register").tbl
  registerT.reg("gamemode") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## register.gamemode{id = "glass", name = "Glass Cannon", description = "...",
    ##   base = "wave" | "survival" | "roguelite" | "3d", spawning = true,
    ##   onStart = function(game, resumed) ... end,
    ##   icon = texture | model | "file", color = "#64c8ff", desktop = true,
    ##   coop = true}   -- coop = false: CO-OP.EXE does not offer it
    let owner = vm.requireLoading("register.gamemode")
    let t = vm.checkTable(args, 0, "gamemode")
    let key = mods[owner].id & ":" & vm.checkName(t, "register.gamemode")
    if findModMode(key) >= 0: vm.runtimeError("register.gamemode: '" & key & "' is already registered")
    var m = ModModeDef(key: key, owner: owner, spawning: true, desktop: true, base: gmWaveBased,
                       resumable: true, coop: true)
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
    m.restore = vm.readRestoreRule(t)
    let rs = rawGetStr(t, "resumable")
    case rs.kind
    of vkNil: discard
    of vkBool: m.resumable = rs.b
    else: vm.runtimeError("register.gamemode: resumable must be true or false")
    m.onStart = rawGetStr(t, "onStart")
    let co = rawGetStr(t, "coop")
    case co.kind
    of vkNil: discard
    of vkBool: m.coop = co.b
    else: vm.runtimeError("register.gamemode: coop must be true or false")
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
    let owner = vm.requireLoading("register.app")
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
      if f.kind == vkFunction: dest[] = f
      elif f.kind != vkNil: vm.runtimeError("register.app: " & field & " must be a function")
    if app.draw.kind == vkNil: vm.runtimeError("register.app needs a draw function")
    app.color = ModAppDefaultColor
    vm.readDesktopEntry(t, "register.app", app.icon, app.color, app.desktop)
    app.width = 480
    app.height = 360
    for (field, dest, lo, hi) in [("width", addr app.width, ModAppMinW, ModAppMaxW),
                                  ("height", addr app.height, ModAppMinH, ModAppMaxH)]:
      let v = rawGetStr(t, field)
      if v.kind == vkNumber and abs(v.n) < 1.0e9: dest[] = max(int(v.n), lo)   # (the window chrome needs the minimum)
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
    let owner = vm.requireLoading("register.cosmetic")
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

proc installCoopLibrary(base: ScriptTable) =
  ## The global `coop`: the co-op run on screen, read live.
  let t = newScriptTable()
  t.reg("active") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## coop.active() -> boolean: a co-op run is on screen (CO-OP.EXE)
    ret.setRet(vbool(coopActive() and not modCtx.game.isNil))
  t.reg("isHost") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## coop.isHost() -> boolean: this machine simulates the co-op run (gameplay hooks fire here)
    ret.setRet(vbool(coopHost()))
  t.reg("isClient") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## coop.isClient() -> boolean: this machine draws the host's run; only drawing
    ## hooks fire, and what scripts spawn or remove here is dropped
    ret.setRet(vbool(coopClient()))
  t.reg("localSlot") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## coop.localSlot() -> number: this machine's seat (0 is the host's, 0 in single player)
    ret.setRet(vnum(localSlot.float64))
  t.reg("players") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## coop.players() -> {player...}: every player of the run, by seat (just the
    ## player in single player); player.slot is each one's seat
    let list = newScriptTable()
    let g = modCtx.game
    if not g.isNil and not modCtx.inPvP:
      for k, p in g.players:
        rawSet(list, vnum(float64(k + 1)), wrapPlayer(p))
    ret.setRet(vtable(list))
  t.reg("teamLives") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## coop.teamLives() -> number | nil: the team's lives left (math.huge when
    ## unlimited); nil outside a co-op run
    let g = modCtx.game
    if g.isNil or g.coop.isNil: ret.setRet(NilValue)
    elif g.coop.teamLives == UnlimitedLives: ret.setRet(vnum(Inf))
    else: ret.setRet(vnum(g.coop.teamLives.float64))
  t.reg("name") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## coop.name(slot) -> string | nil: the nickname at that seat
    let slot = int(vm.checkNum(args, 0, "name"))
    let g = modCtx.game
    if g.isNil or g.coop.isNil or slot < 0 or slot >= MaxCoopPlayers: ret.setRet(NilValue)
    else: ret.setRet(vstr(g.coop.nicknames[slot]))
  rawSet(base, vstr("coop"), vtable(t))

proc installModApi*(base: ScriptTable) =
  ## Build the classes and the shared library tables (once per reload).
  textEntries.setLen(0)
  languageDefs.setLen(0)
  makeClasses()
  installCoopLibrary(base)
  installMethods()
  installLibraries(base)
  installContentLibraries(base)
  installNewContent(base)
  installAssetLibraries(base)

# ---------------------------------------------------------- per mod env ----
proc storagePath(m: ModRuntime): string =
  ## In the profile folder the storage was read from: a profile switch must
  ## never write one profile's mod.storage into another's folder.
  m.storageDir / (m.id & ".json")

proc loadModStorage(m: ModRuntime) =
  m.storage = newScriptTable()
  m.storageDir = getAppDataPath() / "mod_data"
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
    if m.storageDir.len == 0: return true   # never loaded: nothing of it to keep
    createDir(m.storageDir)
    writeFile(storagePath(m), text)
    true
  except CatchableError:
    false

proc saveAllModStorage*() =
  ## Loader (before a reload) and main (on exit).
  for m in mods:
    if not m.disabled or not m.storage.isNil:
      discard saveModStorage(m)

proc restoreGame(vm: VM, what: string): Game =
  result = modCtx.game
  if result.isNil or modCtx.inPvP:
    vm.runtimeError("run.restorePoints." & what & " needs a run in progress")

proc budgetValue(n: int): ScriptValue =
  ## A restore-point count for scripts: unlimited reads as math.huge.
  if n == UnlimitedLives: vnum(Inf) else: vnum(n)   # an integer, so it prints "2", not "2.0"

proc installRestorePoints(): ScriptTable =
  ## run.restorePoints: the run's restore points ("lives"): its budget, what is
  ## spent, its death-surviving checkpoint (save / clear) and whether they are
  ## drawn. Everything reads live from the run on screen.
  result = newScriptTable()
  let t = result
  proc selfArgs(args: openArray[ScriptValue]): int =
    ## Called with ':' by mistake: skip the table itself.
    if arg(args, 0).kind == vkTable and rawEquals(arg(args, 0), vtable(t)): 1 else: 0
  t.reg("save") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## run.restorePoints.save([label]) -> written: the run as it stands now
    ## (run.data included) becomes the checkpoint a death can Continue from.
    ## `label` ("ROUND 3" or {en =, es =}) is what the Continue button names.
    let g = vm.restoreGame("save")
    let (en, es) = vm.textPair(arg(args, selfArgs(args)), "run.restorePoints.save: label")
    ret.setRet(vbool(saveBlockCheckpoint(g, scripted = true, labelEn = en, labelEs = es)))
  t.reg("clear") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## run.restorePoints.clear() -- drop the checkpoint: no Continue from it
    let g = vm.restoreGame("clear")
    deleteBlockCheckpoint(g.mode, g.modMode)
  t.meta = newScriptTable()
  rawSet(t.meta, vstr("__index"), vnative(newNative("restore_index",
    proc (vm: VM, args: openArray[ScriptValue], ret: var RetVals) =
      let name = keyName(arg(args, 1))
      let g = vm.restoreGame(name)
      case name
      of "enabled":
        ret.setRet(vbool(g.mode in RestorePointModes and not modRestoreRule(g.modMode).disabled))
      of "max": ret.setRet(budgetValue(difficultyMaxLives(g.mode, g.modMode)))
      of "used": ret.setRet(vnum(g.livesUsed))
      of "left": ret.setRet(budgetValue(livesRemaining(g.livesUsed, g.mode, g.modMode)))
      of "saved": ret.setRet(vbool(canContinueRun(g)))
      of "offline": ret.setRet(vbool(restorePointsOffline(g)))
      of "glyphs": ret.setRet(vbool(restorePointsShown(g)))
      else: vm.runtimeError("run.restorePoints has no field '" & name &
                            "' (enabled, max, used, left, saved, offline, glyphs, save, clear)"))))
  rawSet(t.meta, vstr("__newindex"), vnative(newNative("restore_newindex",
    proc (vm: VM, args: openArray[ScriptValue], ret: var RetVals) =
      let name = keyName(arg(args, 1))
      let g = vm.restoreGame(name)
      let v = arg(args, 2)
      if name == "used":
        if not (v.kind == vkNumber and v.n >= 0 and v.n <= 1000 and v.n == floor(v.n)):
          vm.runtimeError("run.restorePoints.used must be a whole number from 0 to 1000")
        setRestorePointsUsed(g, int(v.n))
      else:
        vm.runtimeError("run.restorePoints." & name & " cannot be set (only used can; " &
                        "hide the meters with hud.hide(\"restorePoints\"))"))))

const EnvPrelude = """
local env = ...
-- Code a mod loads gets the mod's globals unless it says otherwise. (Which
-- files it may load, and where relative paths start, is the file sandbox's
-- business: lua_files.h.)
local load0, loadfile0 = load, loadfile
function load(chunk, chunkname, mode, ...)
  if select("#", ...) == 0 then return load0(chunk, chunkname, mode, env) end
  return load0(chunk, chunkname, mode, (...))
end
function loadfile(filename, mode, ...)
  if select("#", ...) == 0 then return loadfile0(filename, mode, env) end
  return loadfile0(filename, mode, (...))
end
function dofile(filename)
  local f, err = loadfile(filename)
  if not f then error(err, 2) end
  return f()
end
"""

proc installEnvPrelude(m: ModRuntime) =
  ## The mod's own load / loadfile / dofile, which default to its globals.
  let cl = modVM.loadChunk(EnvPrelude, m.id & "/(environment)", m.env)
  var r: RetVals
  let err = protectedCall(modVM, vfunc(cl), [vtable(m.env)], r)
  if err.len > 0: modLogAdd(mlError, m.id, "environment: " & err)

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
  # Files (the file sandbox above): mod.dir is the mod's folder (read-only),
  # mod.path(rel) an absolute path from a relative one, mod.dataDir() a
  # folder of the mod's own in the profile, the only place it may write.
  rawSet(modT, vstr("dir"), vstr(m.dir))
  modT.reg("path") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    let rel = vm.checkStr(args, 0, "path")
    let (path, err) = confineModPath(storageOwner, rel, write = false)
    if err.len > 0: vm.runtimeError("mod.path: " & err)
    ret.setRet(vstr(path))
  modT.reg("dataDir") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    let dir = modDataDir(storageOwner)
    try: createDir(dir)
    except OSError, IOError: vm.runtimeError("mod.dataDir: cannot create " & dir)
    ret.setRet(vstr(dir))
  rawSet(env, vstr("mod"), vtable(modT))
  installEnvPrelude(m)

  # run.restorePoints: the death-surviving checkpoint and its budget, live
  let restoreT = installRestorePoints()

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
      elif keyName(arg(args, 1)) == "restorePoints":
        ret.setRet(vtable(restoreT))
      elif keyName(arg(args, 1)) == "resumable":
        # Whether quitting saves this run to resume (the mode's flag unless
        # run.resumable changed it); nil outside a run.
        ret.setRet(if modCtx.game.isNil: NilValue else: vbool(modRunResumable(modCtx.game)))
      else:
        ret.setRet(NilValue))))
  rawSet(runT.meta, vstr("__newindex"), vnative(newNative("run_newindex",
    proc (vm: VM, args: openArray[ScriptValue], ret: var RetVals) =
      # run.data = {...} replaces this run's data (it must stay plain data).
      if keyName(arg(args, 1)) == "data":
        let v = arg(args, 2)
        if v.kind != vkTable: vm.runtimeError("run.data must be a table")
        mods[idx].runData = v.tbl
      elif keyName(arg(args, 1)) == "resumable":
        # run.resumable = false: quitting ends this run instead of saving it
        # (a save already on disk goes at once); true allows it again.
        let v = arg(args, 2)
        if v.kind != vkBool: vm.runtimeError("run.resumable must be true or false")
        let g = modCtx.game
        if g.isNil or modCtx.inPvP: vm.runtimeError("run.resumable needs a run in progress")
        setRunResumable(g, v.b)
        if not v.b:
          deleteRunSave(g.mode, g.modMode)
          deleteSuspendSnapshot(g.mode, g.modMode)
      else:
        vm.runtimeError("run." & keyName(arg(args, 1)) & " cannot be set"))))
  rawSet(env, vstr("run"), vtable(runT))

  # require("folder.file") runs <mod>/folder/file.lua (or folder/file/init.lua;
  # "folder/file.lua" spelled as a path works too) once and returns its value;
  # require("other_id:folder.file") does the same for a loaded mod's module, in
  # that mod's globals. Each module loads once, kept in the shared
  # package.loaded["<id>:<module>"]. A name with no such file goes on to Lua's
  # own require (package.preload, package.path, the standard library names).
  env.reg("require") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    let name = vm.checkStr(args, 0, "require")
    var owner = idx
    var module = name
    let colon = name.find(':')
    if colon > 0:
      let id = name[0 ..< colon]
      module = name[colon + 1 .. ^1]
      owner = -1
      for i, other in mods:
        if other.id == id and not other.disabled: owner = i
      if owner < 0:
        vm.runtimeError("require: no loaded mod '" & id & "' (list it in mod.json's " &
                        "\"dependencies\" so it loads first)")
    let key = mods[owner].id & ":" & module
    let pkg = rawGetStr(modBase, "package")
    let loadedV = if pkg.kind == vkTable: rawGetStr(pkg.tbl, "loaded") else: NilValue
    if loadedV.kind == vkTable:
      let cached = rawGetStr(loadedV.tbl, key)
      if cached.kind != vkNil:
        ret.setRet(cached)
        return
    let asPath = '/' in module or '\\' in module or module.endsWith(".lua")
    let stem = if asPath: module else: module.replace('.', '/')
    let tries = if module.endsWith(".lua"): @[stem] else: @[stem & ".lua", stem / "init.lua"]
    var path, rel = ""
    for t in tries:
      let (p, err) = confineModPath(mods[owner], t, write = false)
      if err.len > 0: vm.runtimeError("require: " & err)
      if fileExists(p):
        (path, rel) = (p, t)
        break
    if path.len == 0:
      if colon < 0:
        let stock = rawGetStr(modBase, "require")
        if stock.kind == vkFunction:
          vm.callValue(stock, [vstr(name)], ret)
          return
      vm.runtimeError("require: module '" & module & "' not found in mod '" & mods[owner].id &
                      "' (looked for " & tries.join(", ") & ")")
    var src = ""
    try:
      src = readFile(path)
    except IOError:
      vm.runtimeError("require: cannot read " & rel)
    let cl = vm.loadChunk(src, mods[owner].id & "/" & rel.replace('\\', '/'), mods[owner].env)
    var r: RetVals
    vm.callValue(vfunc(cl), [vstr(name), vstr(path)], r)
    let v = if r.count > 0 and r.first.kind != vkNil: r.first else: TrueValue
    if loadedV.kind == vkTable: rawSet(loadedV.tbl, vstr(key), v)
    ret.setRet(v)
