## Mod runtime core: the script VM, hook handler lists and the bridge between
## game objects and script values.
##
## This is the module gameplay code imports to fire hooks, so it sits LOW in
## the dependency DAG: types + the script VM + mod_state only. Anything that
## needs higher-level game procs (spawning, damage, drawing) lives in
## mod_api.nim, which fills in the userdata classes and API tables at startup
## and is never imported by gameplay modules.
##
## Every call site is guarded by `hookActive(h)`, a single array length check,
## so with no mod loaded the hooks cost nothing. A handler that errors is
## logged and struck; a mod that keeps erroring, or keeps blowing its
## per-frame time budget, is switched off for the session (never the game).

import std/[json, tables, strutils, math, random]
import raylib
import ../types, ../game3d/types_3d, ../settings, ../save_system, ../gamepad_input
import lua_bridge, mod_state, mod_assets

type
  ModHook* = enum
    # lifecycle
    hkRunStart = "runStart"          ## (game, resumed)
    hkRunEnd = "runEnd"              ## (game, died)
    hkUpdate = "update"              ## (game, dt)
    hkPreUpdate = "preUpdate"        ## (game, dt)          before the simulation
    hkStateChange = "stateChange"    ## (game, from, to)    GameState names
    hkDrawBackground = "drawBackground"  ## (game)          world coordinates, under everything
    hkDrawWorld = "drawWorld"        ## (game)              world coordinates
    hkDrawHud = "drawHud"            ## (game, w, h)        screen coordinates
    hkDrawDesktop = "drawDesktop"    ## (w, h)              the desktop, over the wallpaper
    # waves and modes
    hkWaveStart = "waveStart"        ## (game, wave)
    hkWaveEnd = "waveEnd"            ## (game, wave)
    hkWaveEnemyCount = "waveEnemyCount"  ## filter (count, game, wave)
    hkWaveSpawn = "waveSpawn"        ## filter (enemyType, game, wave) -> type name
    hkSpawnInterval = "spawnInterval"    ## filter (seconds, game)
    hkBossForWave = "bossForWave"    ## filter (bossId, game, wave)
    hkSurvivalSpawn = "survivalSpawn"    ## filter (enemyType, game)
    hkSurvivalEvent = "survivalEvent"    ## cancel (game, eventName)
    hkFloorStart = "floorStart"      ## (game, floor)
    hkRoomEnter = "roomEnter"        ## (game, room)
    hkRoomCleared = "roomCleared"    ## (game, room)
    hkRogueSpawn = "rogueSpawn"      ## filter (enemyType, game)
    # enemies
    hkEnemySpawn = "enemySpawn"      ## (enemy)
    hkEnemyUpdate = "enemyUpdate"    ## cancel (enemy, dt): true skips the vanilla AI
    hkEnemyDraw = "enemyDraw"        ## cancel (enemy): true skips the vanilla body
    hkEnemyDamaged = "enemyDamaged"  ## filter (amount, enemy)
    hkEnemyDeath = "enemyDeath"      ## (enemy, game)
    # bosses
    hkBossSpawn = "bossSpawn"        ## (boss, game)
    hkBossPhase = "bossPhase"        ## (boss, phaseIndex)
    hkBossAttack = "bossAttack"      ## cancel (boss, attackTable)
    hkBossDeath = "bossDeath"        ## (boss, game)
    # player
    hkShoot = "shoot"                ## cancel (player, game): true skips the vanilla shot
    hkBulletHit = "bulletHit"        ## filter (damage, bullet, enemy)
    hkPlayerDamaged = "playerDamaged"    ## filter (amount, player)
    hkPlayerLethal = "playerLethal"  ## cancel (player): true keeps the player alive
    hkPlayerHeal = "playerHeal"      ## filter (amount, player)
    hkPlayerDraw = "playerDraw"      ## cancel (player): true skips the vanilla body
    hkPlayerUpdate = "playerUpdate"  ## cancel (player, dt): true skips vanilla movement
    hkDash = "dash"                  ## cancel (player): true stops the dash
    hkPlaceWall = "placeWall"        ## cancel (x, y, game): true places nothing
    hkAbility = "ability"            ## cancel (game): true skips the vanilla [Q] abilities
    hkCombatStats = "combatStats"    ## (player, stats) stats fields can be edited
    # bullets
    hkBulletSpawn = "bulletSpawn"    ## (bullet)            any new bullet, before it flies
    hkBulletUpdate = "bulletUpdate"  ## cancel (bullet, dt): true skips vanilla movement
    hkBulletDraw = "bulletDraw"      ## cancel (bullet): true skips the vanilla body
    # power-ups
    hkPowerUpChoices = "powerUpChoices"  ## filter (choicesTable, game)
    hkPowerUpPicked = "powerUpPicked"    ## (name, level, game)
    hkPowerUpApply = "powerUpApply"  ## cancel (name, level, player): true skips its stat changes
    hkLevelUp = "levelUp"            ## (game, level)
    # restore points
    hkCheckpoint = "checkpoint"      ## cancel (game): true skips the base mode's restore point
    hkRestorePointUsed = "restorePointUsed"  ## (game, used, max)  a Continue spent one; after runStart
    hkXpToLevel = "xpToLevel"        ## filter (xp, level, mode)
    # economy
    hkCoinValue = "coinValue"        ## filter (amount, enemy)
    hkXpValue = "xpValue"            ## filter (amount, enemy)
    hkPickup = "pickup"              ## cancel (kind, value, game): true = taken, no vanilla effect
    hkShopBuy = "shopBuy"            ## cancel (index, name, cost, game): true = not bought
    # 3D worlds (game3d/): the script-facing wrappers come from mod_3d
    hkWorld3dStart = "world3dStart"  ## (world, resumed)    first frame of a world, before its simulation
    hkWorld3dPreUpdate = "world3dPreUpdate"  ## (world, dt)  before the simulation
    hkWorld3dUpdate = "world3dUpdate"  ## (world, dt)       after the simulation
    hkWorld3dEnd = "world3dEnd"      ## (world, result)     "won" | "lost" | "exit"
    hkWorld3dDraw = "world3dDraw"    ## (world)             inside the 3D camera: draw3d.* allowed
    hkWorld3dDrawHud = "world3dDrawHud"  ## (world, w, h)   screen coordinates over the 3D view
    hkWorld3dShoot = "world3dShoot"  ## cancel (world): true skips the vanilla shot
    hkWorld3dHit = "world3dHit"      ## filter (damage, target, projectile): target = entity or "boss"/"satellite"
    hkWorld3dPlayerDamaged = "world3dPlayerDamaged"  ## filter (amount, source, entity)
    hkWorld3dPlayerLethal = "world3dPlayerLethal"  ## cancel (): true keeps the player alive
    hkWorld3dEntitySpawn = "world3dEntitySpawn"  ## (entity)
    hkWorld3dEntityUpdate = "world3dEntityUpdate"  ## cancel (entity, dt): true skips the built-in AI
    hkWorld3dEntityDraw = "world3dEntityDraw"  ## cancel (entity): true skips the built-in body
    hkWorld3dEntityDeath = "world3dEntityDeath"  ## (entity)
    hkWorld3dBossPhase = "world3dBossPhase"  ## (phase)
    hkWorld3dBossAttack = "world3dBossAttack"  ## cancel (phase, pattern): true skips the vanilla attack
    hkWorld3dPickup = "world3dPickup"  ## cancel (pickup): true = taken, no vanilla effect

  DrawTarget* = enum
    dtNone, dtWorld, dtHud, dtWorld3D  ## dtWorld3D: inside a 3D camera (world3dDraw, world3dEntityDraw)

  HudPart* = enum
    ## Built-in HUD pieces a mod may hide (hud.hide) to draw its own.
    hpAll = "all", hpPlayer = "player", hpRun = "run", hpBoss = "boss",
    hpCombo = "combo", hpBanners = "banners", hpAbilities = "abilities",
    hpHints = "hints", hpVignettes = "vignettes", hpDocks = "docks",
    hpDamageNumbers = "damageNumbers", hpCrosshair = "crosshair",
    hpRestorePoints = "restorePoints"  ## the meters and the loss animation; "all" leaves them

  ModRuntime* = ref object
    ## One successfully started mod.
    id*, name*, version*, author*: string
    dir*: string
    env*: ScriptTable
    index*: int
    disabled*: bool      ## switched off this session (errors / too slow)
    errorCount*: int
    lastError: string    ## the log shows a repeated error once, then a count
    repeats: int
    frameTime*: float64  ## seconds of script time this frame
    slowFrames*: int
    runData*: ScriptTable
    exports*: ScriptValue
    storage*: ScriptTable  ## mod.storage: kept per profile between sessions
    modTable*: ScriptTable ## the mod's `mod` table (mod.storage may be reassigned)

  ModKeybind* = ref object
    key*: string
    owner*: int
    modId*: string
    actionId*: string
    nameEn*: string
    nameEs*: string
    defaultKey*: KeyboardKey
    defaultPad*: GamepadButton
    keyBind*: KeyboardKey
    padBind*: GamepadButton

  Handler = object
    fn: ScriptValue
    owner: int

  ModTimer = object
    id: int
    owner: int
    fn: ScriptValue
    remaining: float64
    interval: float64    ## 0 = one-shot

  ModCtx* = object
    game*: Game          ## the run being played; nil on the desktop
    hudArena*: tuple[x, y, w, h: float64]  ## the arena in drawHud coordinates
    drawing*: DrawTarget
    inPvP*: bool
    lastState: GameState ## stateChange fires when the run state differs from this
    source*: PowerUpType ## the power-up a script is acting for (hasSource)
    hasSource*: bool     ## damage/healing done now is credited to `source`
    lastGame: Game       ## runStart fires when this changes
    endedGame: Game      ## runEnd fires once per run

  # Typed boxes so a Userdata can hold a game ref (they are not RootObj).
  GameBox* = ref object of RootObj
    g*: Game             ## nil = "the current run" (the global `game` proxy)
  PlayerBox* = ref object of RootObj
    p*: Player           ## nil = the current run's player
  EnemyBox* = ref object of RootObj
    e*: Enemy
  BulletBox* = ref object of RootObj
    b*: Bullet

const
  HookStepBudget* = 30_000_000   ## Lua instructions per hook call before it is aborted
  LoadStepBudget* = 300_000_000  ## Lua instructions for a mod's main chunk
  MaxModErrors = 25              ## errors before a mod is switched off
  SlowFrameSeconds = 0.008       ## one mod's script time per frame counted as slow
  MaxSlowFrames = 90             ## consecutive slow frames before a mod is switched off

var
  modVM*: VM
  modBase*: ScriptTable
  mods*: seq[ModRuntime]
  currentModIdx* = -1            ## whose code is running (print, registration owner)
  modCtx*: ModCtx
  gameClass*, playerClass*, enemyClass*, bulletClass*: UdClass
  modNotices*: seq[string]       ## player-facing notices for the desktop toasts
  hudNotice*: string             ## the same, shown briefly over a run in progress
  hudNoticeTimer*: float32
  handlers: array[ModHook, seq[Handler]]
  timers: seq[ModTimer]
  hiddenHud*: set[HudPart]       ## hud.hide(); every run starts with the full HUD
  restoreSpentPending: bool      ## restorePointUsed is owed to the next run that starts
  nextTimerId = 1
  modKeybinds*: seq[ModKeybind]

proc modKeybindKey*(modId, actionId: string): string =
  modId & ":" & actionId

proc modKeybindName*(b: ModKeybind): string =
  if globalSettings.isNil or globalSettings.language != "spanish": b.nameEn
  else: b.nameEs

proc modKeybindByKey*(key: string): ModKeybind =
  for b in modKeybinds:
    if b.key == key and b.owner >= 0 and b.owner < mods.len and not mods[b.owner].disabled:
      return b
  nil

proc modKeybindGamepadDown*(b: ModKeybind): bool =
  let pad = activeGamepad()
  b != nil and pad >= 0 and b.padBind != GamepadButton.Unknown and
    isGamepadButtonDown(pad, b.padBind)

proc modKeybindActive*(b: ModKeybind): bool =
  not b.isNil and (isKeyDown(b.keyBind) or modKeybindGamepadDown(b))

proc modKeybindPressed*(b: ModKeybind): bool =
  if b.isNil: return false
  let pad = activeGamepad()
  isKeyPressed(b.keyBind) or
    (pad >= 0 and b.padBind != GamepadButton.Unknown and
     isGamepadButtonPressed(pad, b.padBind))

proc modKeybindReleased*(b: ModKeybind): bool =
  if b.isNil: return false
  let pad = activeGamepad()
  isKeyReleased(b.keyBind) or
    (pad >= 0 and b.padBind != GamepadButton.Unknown and
     isGamepadButtonReleased(pad, b.padBind))

proc resetModKeybinds*() =
  modKeybinds.setLen(0)

proc dropModKeybinds*(owner: int) =
  var kept: seq[ModKeybind]
  for b in modKeybinds:
    if b.owner != owner: kept.add(b)
  modKeybinds = kept

proc restoreModKeybind*(b: ModKeybind) =
  if b.isNil or globalSettings.isNil: return
  let prefix = b.key & "="
  for entry in globalSettings.modKeybinds:
    if entry.startsWith(prefix):
      let parts = entry[prefix.len .. ^1].split('|')
      if parts.len == 2:
        try: b.keyBind = parseEnum[KeyboardKey](parts[0])
        except ValueError: discard
        try: b.padBind = parseEnum[GamepadButton](parts[1])
        except ValueError: discard
      return

proc saveModKeybind*(b: ModKeybind) =
  if b.isNil or globalSettings.isNil: return
  let prefix = b.key & "="
  var kept: seq[string]
  for entry in globalSettings.modKeybinds:
    if not entry.startsWith(prefix): kept.add(entry)
  kept.add(prefix & $b.keyBind & "|" & $b.padBind)
  globalSettings.modKeybinds = kept
  discard saveSettings(globalSettings)

proc hudHidden*(p: HudPart): bool {.inline.} =
  ## drawGame: is this built-in HUD piece hidden by a mod? "all" is the HUD
  ## drawn in play, so it leaves the restore points (crash and pause screens).
  hiddenHud != {} and (p in hiddenHud or (hpAll in hiddenHud and p != hpRestorePoints))

proc hookActive*(h: ModHook): bool {.inline.} =
  handlers[h].len > 0

proc currentMod*(): ModRuntime =
  if currentModIdx >= 0 and currentModIdx < mods.len: mods[currentModIdx] else: nil

# ------------------------------------------------------------- wrappers ----
proc wrapGame*(g: Game): ScriptValue =
  if g.isNil or gameClass.isNil: NilValue
  else: vud(Userdata(cls: gameClass, box: GameBox(g: g), key: cast[pointer](g)))

proc wrapPlayer*(p: Player): ScriptValue =
  if p.isNil or playerClass.isNil: NilValue
  else: vud(Userdata(cls: playerClass, box: PlayerBox(p: p), key: cast[pointer](p)))

proc wrapEnemy*(e: Enemy): ScriptValue =
  if e.isNil or enemyClass.isNil: NilValue
  else: vud(Userdata(cls: enemyClass, box: EnemyBox(e: e), key: cast[pointer](e)))

proc wrapBullet*(b: Bullet): ScriptValue =
  if b.isNil or bulletClass.isNil: NilValue
  else: vud(Userdata(cls: bulletClass, box: BulletBox(b: b), key: cast[pointer](b)))

proc unwrapGame*(v: ScriptValue): Game =
  if v.kind == vkUserdata and v.ud.cls == gameClass:
    let g = GameBox(v.ud.box).g
    return if g.isNil: modCtx.game else: g
  nil

proc unwrapPlayer*(v: ScriptValue): Player =
  if v.kind == vkUserdata and v.ud.cls == playerClass:
    let p = PlayerBox(v.ud.box).p
    if not p.isNil: return p
    if not modCtx.game.isNil: return modCtx.game.player
  nil

proc unwrapEnemy*(v: ScriptValue): Enemy =
  if v.kind == vkUserdata and v.ud.cls == enemyClass: EnemyBox(v.ud.box).e else: nil

proc unwrapBullet*(v: ScriptValue): Bullet =
  if v.kind == vkUserdata and v.ud.cls == bulletClass: BulletBox(v.ud.box).b else: nil

# ------------------------------------------------------ errors / budgets ----
proc disableMod*(idx: int, reason: string) =
  ## Switch a mod off for the rest of the session: its handlers and timers go,
  ## the game carries on. The run stays modded (it already ran mod code).
  if idx < 0 or idx >= mods.len or mods[idx].disabled:
    return
  let m = mods[idx]
  m.disabled = true
  for h in ModHook:
    var kept: seq[Handler]
    for hd in handlers[h]:
      if hd.owner != idx: kept.add(hd)
    handlers[h] = kept
  var keptTimers: seq[ModTimer]
  for t in timers:
    if t.owner != idx: keptTimers.add(t)
  timers = keptTimers
  modLogAdd(mlError, m.id, "switched off: " & reason)
  modNotices.add(m.name & ": " & reason)
  hudNotice = m.name & ": " & reason
  hudNoticeTimer = 6.0

proc reportModError*(idx: int, err: string) =
  if idx < 0 or idx >= mods.len:
    modLogAdd(mlError, "", err)
    return
  let m = mods[idx]
  if err == m.lastError:
    inc m.repeats
  else:
    if m.repeats > 0:
      modLogAdd(mlError, m.id, "(previous error repeated " & $m.repeats & " more times)")
    m.lastError = err
    m.repeats = 0
    modLogAdd(mlError, m.id, err)
  inc m.errorCount
  if m.errorCount >= MaxModErrors:
    if m.repeats > 0:
      modLogAdd(mlError, m.id, "(previous error repeated " & $m.repeats & " more times)")
      m.repeats = 0
    disableMod(idx, "too many errors (see MODS.EXE > Log)")

proc modFrameCheck*() =
  ## Once per frame: a mod that keeps spending too long in its scripts is
  ## switched off before it can drag the frame rate down for good.
  for i, m in mods:
    if m.disabled: continue
    if m.frameTime > SlowFrameSeconds:
      inc m.slowFrames
      if m.slowFrames >= MaxSlowFrames:
        disableMod(i, "too slow (over " & $int(SlowFrameSeconds * 1000) & " ms per frame)")
    else:
      m.slowFrames = 0
    m.frameTime = 0.0

# ------------------------------------------------------------- dispatch ----
proc callAs*(owner: int, fn: ScriptValue, args: openArray[ScriptValue],
             ret: var RetVals, budget = HookStepBudget): bool =
  ## Run one script function on behalf of mod `owner`. False on error (already
  ## reported). Nested calls (a native re-entering the VM) keep the outer budget.
  if owner >= 0 and owner < mods.len and mods[owner].disabled:
    return false
  let prev = currentModIdx
  currentModIdx = owner
  let t0 = getTime()
  let err = protectedCall(modVM, fn, args, ret, budget)
  if owner >= 0 and owner < mods.len:
    mods[owner].frameTime += getTime() - t0
  currentModIdx = prev
  if err.len > 0:
    reportModError(owner, err)
    return false
  true

proc addHandler*(h: ModHook, fn: ScriptValue, owner: int) =
  handlers[h].add(Handler(fn: fn, owner: owner))

proc removeHandler*(h: ModHook, fn: ScriptValue, owner: int) =
  var kept: seq[Handler]
  for hd in handlers[h]:
    if not (hd.owner == owner and rawEquals(hd.fn, fn)):
      kept.add(hd)
  handlers[h] = kept

proc fire*(h: ModHook, args: openArray[ScriptValue]) =
  ## Call every handler; results are ignored.
  let hs = handlers[h]
  var r: RetVals
  for hd in hs:
    discard callAs(hd.owner, hd.fn, args, r)

proc fireCancel*(h: ModHook, args: openArray[ScriptValue]): bool =
  ## True as soon as one handler returns true ("cancel the vanilla behaviour").
  let hs = handlers[h]
  var r: RetVals
  for hd in hs:
    if callAs(hd.owner, hd.fn, args, r) and r.count > 0 and
       r.first.kind == vkBool and r.first.b:
      return true
  false

proc filterNum*(h: ModHook, value: float64, args: openArray[ScriptValue]): float64 =
  ## Each handler gets (value, args...) and may return a number to replace it.
  result = value
  let hs = handlers[h]
  var r: RetVals
  var callArgs = newSeq[ScriptValue](args.len + 1)
  for i, a in args: callArgs[i + 1] = a
  for hd in hs:
    callArgs[0] = vnum(result)
    if callAs(hd.owner, hd.fn, callArgs, r) and r.count > 0 and r.first.kind == vkNumber:
      let n = r.first.n
      if n == n:  # NaN never replaces a game value
        result = n

proc filterValue*(h: ModHook, value: ScriptValue, args: openArray[ScriptValue]): ScriptValue =
  ## Like filterNum for any value: a non-nil return replaces it.
  result = value
  let hs = handlers[h]
  var r: RetVals
  var callArgs = newSeq[ScriptValue](args.len + 1)
  for i, a in args: callArgs[i + 1] = a
  for hd in hs:
    callArgs[0] = result
    if callAs(hd.owner, hd.fn, callArgs, r) and r.count > 0 and r.first.kind != vkNil:
      result = r.first

# --------------------------------------------------------------- timers ----
proc addTimer*(owner: int, fn: ScriptValue, delay, interval: float64): int =
  result = nextTimerId
  inc nextTimerId
  timers.add(ModTimer(id: result, owner: owner, fn: fn, remaining: max(0.0, delay),
                      interval: max(0.0, interval)))

proc cancelTimer*(id: int) =
  for i in 0 ..< timers.len:
    if timers[i].id == id:
      timers.delete(i)
      return

proc tickTimers(dt: float64) =
  var due: seq[ModTimer]
  var i = 0
  while i < timers.len:
    timers[i].remaining -= dt
    if timers[i].remaining <= 0.0:
      due.add(timers[i])
      if timers[i].interval > 0.0:
        timers[i].remaining += max(timers[i].interval, 0.001)
        inc i
      else:
        timers.delete(i)
    else:
      inc i
  var r: RetVals
  for t in due:
    discard callAs(t.owner, t.fn, [], r)

# ------------------------------------------------------------- run data ----
proc toJsonNode*(v: ScriptValue, depth = 0): JsonNode =
  ## Plain data only (numbers, strings, booleans, tables); functions and
  ## userdata are dropped, which is what makes run.data safe to save.
  if depth > 32: return newJNull()
  case v.kind
  of vkNil: result = newJNull()
  of vkBool: result = newJBool(v.b)
  of vkNumber: result = (if v.isInt: newJInt(int64(v.n)) else: newJFloat(v.n))
  of vkString: result = newJString(v.str.s)
  of vkTable:
    let t = v.tbl
    if t.hashCount == 0:
      result = newJArray()
      for x in t: result.add(toJsonNode(x, depth + 1))
    else:
      # Mixed/hash tables: keys as strings, numeric keys prefixed so they
      # come back as numbers.
      result = newJObject()
      for (k, x) in pairsCursor(t):
        let child = toJsonNode(x, depth + 1)
        if child.kind == JNull: continue
        case k.kind
        of vkString: result[k.str.s] = child
        of vkNumber: result["#" & numToStr(k.n)] = child
        of vkBool: result["?" & (if k.b: "true" else: "false")] = child
        else: discard
  else: result = newJNull()

proc fromJsonNode*(j: JsonNode): ScriptValue =
  case j.kind
  of JNull: NilValue
  of JBool: vbool(j.getBool)
  of JInt: vnum(j.getInt)
  of JFloat: vnum(j.getFloat)
  of JString: vstr(j.getStr)
  of JArray:
    let t = newScriptTable(j.len)
    for i, x in j.elems:   # by index: a null must not shift what follows
      let v = fromJsonNode(x)
      if v.kind != vkNil: rawSet(t, vnum(i + 1), v)
    vtable(t)
  of JObject:
    let t = newScriptTable()
    for k, x in j.pairs:
      let key =
        if k.len > 1 and k[0] == '#':
          var ok = false
          let n = strToNum(k[1 .. ^1], ok)
          if ok: vnum(n) else: vstr(k)
        elif k == "?true": TrueValue
        elif k == "?false": FalseValue
        else: vstr(k)
      let v = fromJsonNode(x)
      if v.kind != vkNil: rawSet(t, key, v)
    vtable(t)

proc captureRunData*(game: Game) =
  ## Serialize every mod's run.data into game.modRunData (both save layers
  ## call this right before writing; see mod_state.captureModRunData).
  let root = newJObject()
  for m in mods:
    if not m.runData.isNil and (m.runData.len > 0 or m.runData.hashCount > 0):
      root[m.id] = toJsonNode(vtable(m.runData))
  game.modRunData = if root.len > 0: $root else: ""

proc restoreRunData(game: Game) =
  for m in mods:
    m.runData = newScriptTable()
  if game.modRunData.len == 0:
    return
  try:
    let root = parseJson(game.modRunData)
    if root.kind != JObject: return
    for m in mods:
      if root.hasKey(m.id):
        let v = fromJsonNode(root[m.id])
        if v.kind == vkTable: m.runData = v.tbl
  except CatchableError:
    modLogAdd(mlWarn, "", "saved run.data could not be read; mods start it empty")

# ------------------------------------------------------ mod game modes ----
# register.gamemode: a vanilla base mode (wave / survival / roguelite) plus a
# mod's rules. The run carries the mode's key in game.modMode, which also
# gives it its own save slots (see mod_state.saveSlotTag).
type ModModeDef* = object
  key*: string         ## "<mod id>:<id>"
  nameEn*, nameEs*, descEn*, descEs*: string
  base*: GameMode
  spawning*: bool      ## false: the base mode spawns no regular enemies itself
  owner*: int
  onStart*: ScriptValue
  icon*: BodyReplace   ## the desktop icon's texture or model (none: a default glyph)
  color*: Color        ## icon accent; alpha 0 = not given, use the base mode's desktop colour
  desktop*: bool       ## puts an icon on the desktop
  threeD*: bool        ## base = "3d": the run lives in a 3D world (game3d/), never on the 2D arena
  restore*: ModRestoreRule  ## restorePoints / restoreGlyphs (types.difficultyMaxLives reads it)
  resumable*: bool     ## false: quitting ends the run; it is never saved to resume (see modRunResumable)

var modModes*: seq[ModModeDef]

proc findModMode*(key: string): int =
  for i, m in modModes:
    if m.key == key: return i
  -1

proc restoreRuleOf(modMode: string): ModRestoreRule {.nimcall.} =
  ## types.modRestoreRule's seam: the mode's own rule, plus a mod's
  ## hud.hide("restorePoints") for the run on screen (any mode).
  if modMode.len > 0 and modModes.len > 0:
    let i = findModMode(modMode)
    if i >= 0: result = modModes[i].restore
  if hpRestorePoints in hiddenHud: result.hideGlyphs = true

modRestoreRuleImpl = restoreRuleOf

var resumeOverride: tuple[game: Game, on: bool]
  ## run.resumable for one run (the Game it was set on); the mode's flag otherwise

proc modModeResumable*(key: string): bool =
  ## Whether runs of mod game mode `key` are saved to resume when the player
  ## quits (register.gamemode resumable; built-in modes always are).
  if key.len == 0 or modModes.len == 0: return true
  let i = findModMode(key)
  i < 0 or modModes[i].resumable

proc modRunResumable*(game: Game): bool =
  ## run_save.saveRunState / suspend.suspendGame / main: may this run be saved
  ## so the player can resume it after quitting? False makes quitting end it.
  ## run.resumable decides for the run it was set on, else the mode's flag.
  if game.isNil: return true
  if not resumeOverride.game.isNil and resumeOverride.game == game: return resumeOverride.on
  modModeResumable(game.modMode)

proc setRunResumable*(game: Game, on: bool) =
  ## run.resumable = on, for this run only.
  resumeOverride = (game, on)

proc modModeIs3D*(key: string): bool =
  ## Whether the mod game mode `key` runs in a 3D world.
  if key.len == 0 or modModes.len == 0: return false
  let i = findModMode(key)
  i >= 0 and modModes[i].threeD

proc modModeSpawns*(game: Game): bool =
  ## Whether the base mode's own spawning runs (always, outside mod modes).
  if game.modMode.len == 0 or modModes.len == 0: return true
  let i = findModMode(game.modMode)
  i < 0 or modModes[i].spawning

proc modModeName*(key: string, spanish: bool): string =
  let i = findModMode(key)
  if i < 0: return key
  if spanish and modModes[i].nameEs.len > 0: modModes[i].nameEs else: modModes[i].nameEn

# ------------------------------------------------------------ mod apps ----
# register.app: a program a mod adds to the desktop: its own window (and, unless
# it opts out, its own desktop icon), opened from the icon or from MODS.EXE's
# Apps tab. It draws in a canvas, in canvas coordinates, and gets clicks while
# its window is open; update runs every frame the window is open and not
# minimized. Windows and icons name an app by key: reloadMods rebuilds the list,
# so an index is only good for the call it was looked up for.
type ModApp* = object
  key*: string         ## "<mod id>:<id>"
  nameEn*, nameEs*: string
  owner*: int
  draw*, update*, click*, drag*: ScriptValue
  icon*: BodyReplace   ## the desktop icon's texture or model (none: a default glyph)
  color*: Color        ## accent of the window's title bar and the icon tile
  width*, height*: int ## the canvas at opening (and its minimum when resizable)
  resizable*: bool
  desktop*: bool       ## puts an icon on the desktop

const
  ModAppDefaultColor* = Color(r: 120, g: 220, b: 160, a: 255)  # MODS.EXE's green
  ModAppMinW* = 240
  ModAppMaxW* = 960
  ModAppMinH* = 160
  ModAppMaxH* = 640

var modApps*: seq[ModApp]

proc findModApp*(key: string): int =
  ## Index of the app with this key, -1 if it is gone (a reload dropped it).
  for i in 0 ..< modApps.len:
    if modApps[i].key == key: return i
  -1

proc modAppName*(i: int, spanish: bool): string =
  if i < 0 or i >= modApps.len: return ""
  if spanish and modApps[i].nameEs.len > 0: modApps[i].nameEs else: modApps[i].nameEn

proc modAppDraw*(i: int, w, h, mx, my: float32) =
  ## Called with the canvas already translated to (0, 0) and scissored.
  if i < 0 or i >= modApps.len or modApps[i].draw.kind notin {vkFunction, vkNative}: return
  let prev = modCtx.drawing
  let prevArena = modCtx.hudArena
  modCtx.drawing = dtHud
  modCtx.hudArena = (0.0, 0.0, w.float64, h.float64)
  var r: RetVals
  discard callAs(modApps[i].owner, modApps[i].draw,
                 [vnum(w.float64), vnum(h.float64), vnum(mx.float64), vnum(my.float64)], r)
  modCtx.drawing = prev
  modCtx.hudArena = prevArena

proc modAppUpdate*(i: int, dt: float32) =
  if i < 0 or i >= modApps.len or modApps[i].update.kind notin {vkFunction, vkNative}: return
  var r: RetVals
  discard callAs(modApps[i].owner, modApps[i].update, [vnum(dt.float64)], r)

proc modAppClick*(i: int, x, y: float32, button: string, w, h: float32) =
  ## click(x, y, button, w, h): canvas coordinates, and the canvas size.
  if i < 0 or i >= modApps.len or modApps[i].click.kind notin {vkFunction, vkNative}: return
  var r: RetVals
  discard callAs(modApps[i].owner, modApps[i].click,
                 [vnum(x.float64), vnum(y.float64), vstr(button), vnum(w.float64), vnum(h.float64)], r)

proc modAppDrag*(i: int, x, y: float32, w, h: float32) =
  ## drag(x, y, w, h): canvas coordinates while the left mouse button is held.
  if i < 0 or i >= modApps.len or modApps[i].drag.kind notin {vkFunction, vkNative}: return
  var r: RetVals
  discard callAs(modApps[i].owner, modApps[i].drag,
                 [vnum(x.float64), vnum(y.float64), vnum(w.float64), vnum(h.float64)], r)

# ---------------------------------------------------------- lifecycle ----
proc resetHooks*() =
  ## Forget every handler, timer and mod (the loader calls this first).
  for h in ModHook: handlers[h].setLen(0)
  timers.setLen(0)
  mods.setLen(0)
  currentModIdx = -1
  modCtx = ModCtx()
  modNotices.setLen(0)
  hiddenHud = {}
  restoreSpentPending = false
  resumeOverride = (nil, true)
  resetModKeybinds()

proc dropHandlersOf*(idx: int) =
  ## A mod that failed while loading leaves nothing behind.
  for h in ModHook:
    var kept: seq[Handler]
    for hd in handlers[h]:
      if hd.owner != idx: kept.add(hd)
    handlers[h] = kept
  var keptTimers: seq[ModTimer]
  for t in timers:
    if t.owner != idx: keptTimers.add(t)
  timers = keptTimers

proc isActiveRunState*(s: GameState): bool =
  s in {gsPlaying, gsCountdown, gsShop, gsWaveCleared, gsPowerUpSelect,
        gsRogueliteFloorSelect, gsDeathSequence, gsPaused, gs3DBoss}

proc modOutsideRun*(pvp: bool) =
  ## main.nim, every frame no run is on screen: scripts must not see the last
  ## run as still going (run.active, hooks fired by shared code such as the
  ## bullet constructor), and PvP never runs gameplay scripts.
  modCtx.game = nil
  modCtx.inPvP = pvp

proc modWatchState*(game: Game) =
  ## main.nim, once per frame before the state machine: `stateChange` for any
  ## transition of the run in progress (menus, drafts, pause, game over...).
  if game.isNil or mods.len == 0 or game.mode == gmPvP:
    return
  if game != modCtx.lastGame:
    modCtx.lastState = game.state
    return
  if game.state != modCtx.lastState:
    let before = modCtx.lastState
    modCtx.lastState = game.state
    if hookActive(hkStateChange):
      fire(hkStateChange, [wrapGame(game), vstr($before), vstr($game.state)])

proc modBeginFrame*(game: Game) =
  ## Top of updateGame: publishes the run to scripts and fires runStart the
  ## first time a run is seen, before anything this frame can spawn or hit.
  if mods.len == 0 or game.isNil:
    return
  modCtx.game = game
  modCtx.inPvP = game.mode == gmPvP
  if modCtx.inPvP:
    return  # no gameplay scripting in PvP (matched lobbies only share content)
  if game != modCtx.lastGame and isActiveRunState(game.state):
    modCtx.lastGame = game
    modCtx.lastState = game.state
    timers.setLen(0)
    hiddenHud = {}
    resumeOverride = (nil, true)   # run.resumable is per run
    restoreRunData(game)
    let resumed = game.time > 0.5
    if hookActive(hkRunStart):
      fire(hkRunStart, [wrapGame(game), vbool(resumed)])
    if game.modMode.len > 0:
      let mi = findModMode(game.modMode)
      if mi >= 0 and modModes[mi].onStart.kind in {vkFunction, vkNative}:
        var r: RetVals
        discard callAs(modModes[mi].owner, modModes[mi].onStart, [wrapGame(game), vbool(resumed)], r)
    if restoreSpentPending:
      restoreSpentPending = false
      if hookActive(hkRestorePointUsed):
        let budget = difficultyMaxLives(game.mode, game.modMode)
        fire(hkRestorePointUsed, [wrapGame(game), vnum(game.livesUsed),
                                  (if budget == UnlimitedLives: vnum(Inf) else: vnum(budget))])

proc modRestorePointSpent*() =
  ## run_save.consumeContinueLife: a Continue just spent a restore point. The
  ## event fires on the continued run's first frame, after runStart and the
  ## mode's onStart, when its run.data is back.
  restoreSpentPending = mods.len > 0

proc modCheckpointVetoed*(game: Game): bool =
  ## run_save.saveBlockCheckpoint, for the base mode's own restore points (not
  ## a script's run.restorePoints.save): true = a `checkpoint` handler skipped it.
  hookActive(hkCheckpoint) and not game.isNil and game.mode != gmPvP and
    fireCancel(hkCheckpoint, [wrapGame(game)])

proc tickPowerUpScripts(game: Game, dt: float64)

proc modUpdate*(game: Game, dt: float32) =
  ## End of updateGame's simulation: ticks timers and fires `update` (both on
  ## the world clock), and checks the per-frame time budgets.
  if mods.len == 0 or game.isNil or modCtx.inPvP:
    return
  if hudNoticeTimer > 0.0:
    hudNoticeTimer = max(0.0'f32, hudNoticeTimer - dt)
  if game.state notin {gsPlaying, gsCountdown, gs3DBoss}:
    return
  if game.state in {gsPlaying, gs3DBoss}:
    tickTimers(dt.float64)
    tickPowerUpScripts(game, dt.float64)
    if hookActive(hkUpdate):
      fire(hkUpdate, [wrapGame(game), vnum(dt.float64)])
  modFrameCheck()

proc modRunEnd*(game: Game, died: bool) =
  if mods.len == 0 or game.isNil or game.mode == gmPvP or game == modCtx.endedGame:
    return
  modCtx.endedGame = game
  if hookActive(hkRunEnd):
    fire(hkRunEnd, [wrapGame(game), vbool(died)])

proc modDrawWorld*(game: Game) =
  if not hookActive(hkDrawWorld) or game.isNil or game.mode == gmPvP:
    return
  modCtx.drawing = dtWorld
  fire(hkDrawWorld, [wrapGame(game)])
  modCtx.drawing = dtNone

proc modDrawBackground*(game: Game) =
  if not hookActive(hkDrawBackground) or game.isNil or game.mode == gmPvP:
    return
  modCtx.drawing = dtWorld
  fire(hkDrawBackground, [wrapGame(game)])
  modCtx.drawing = dtNone

proc modDrawDesktop*(w, h: int32) =
  if not hookActive(hkDrawDesktop):
    return
  modCtx.drawing = dtHud
  modCtx.hudArena = (0.0, 0.0, w.float64, h.float64)
  fire(hkDrawDesktop, [vnum(w.int), vnum(h.int)])
  modCtx.drawing = dtNone

proc modPreUpdate*(game: Game, dt: float32) =
  if hookActive(hkPreUpdate) and not modCtx.inPvP and game.state in {gsPlaying, gs3DBoss}:
    fire(hkPreUpdate, [wrapGame(game), vnum(dt.float64)])

proc modDrawHud*(game: Game, w, h: int32, arena: tuple[x, y, w, h: float64]) =
  ## `arena` is where the arena sits in these coordinates (draw.arena()), so a
  ## mod can keep clear of the widescreen docks.
  if not hookActive(hkDrawHud) or game.isNil or game.mode == gmPvP:
    return
  modCtx.hudArena = arena
  modCtx.drawing = dtHud
  fire(hkDrawHud, [wrapGame(game), vnum(w.int), vnum(h.int)])
  modCtx.drawing = dtNone

proc initModHooksVM*(vm: VM, base: ScriptTable) =
  modVM = vm
  modBase = base
  vm.printSink = proc (s: string) =
    let m = currentMod()
    modLogAdd(mlInfo, (if m.isNil: "" else: m.id), s)

# ------------------------------------------------------------ names ----
var
  enemyNameResolver*: proc (name: string, et: var EnemyType): bool {.nimcall.}
    ## Installed by mod_api: built-in names ("etCube") and mod enemies.
  enemyTypeNamer*: proc (et: EnemyType): string {.nimcall.}
    ## The name scripts see for a type (a mod enemy's own name for its slot).

proc enemyTypeName*(et: EnemyType): string =
  if enemyTypeNamer.isNil: $et else: enemyTypeNamer(et)

proc resolveEnemyName*(name: string, et: var EnemyType): bool =
  if not enemyNameResolver.isNil:
    return enemyNameResolver(name, et)
  try:
    et = parseEnum[EnemyType](name)
    true
  except ValueError:
    false

# roster.add: mod enemies mixed into a mode's own spawn picks.
type RosterEntry* = object
  mode*: GameMode
  et*: EnemyType
  chance*: float64     ## per spawn pick, 0..1
  fromWave*: int       ## wave mode: first wave
  minTime*: float64    ## survival: seconds on the survival clock
  minFloor*: int       ## roguelite: first sector
  owner*: int

var rosterEntries*: seq[RosterEntry]

proc applyRoster(game: Game, et: EnemyType): EnemyType =
  result = et
  for r in rosterEntries:
    if r.mode != game.mode or r.owner < mods.len and mods[r.owner].disabled:
      continue
    let eligible = case game.mode
      of gmWaveBased: game.currentWave >= r.fromWave
      of gmTimeSurvival: game.survivalTime.float64 >= r.minTime
      of gmRoguelite: game.rogueliteRun.isNil or game.rogueliteRun.floorNumber >= r.minFloor
      else: false
    if eligible and rand(1.0) < r.chance:
      return r.et

proc filterEnemyType(h: ModHook, et: EnemyType, args: openArray[ScriptValue]): EnemyType =
  ## Handlers get (typeName, args...) and may return another type's name.
  result = et
  let hs = handlers[h]
  var r: RetVals
  var callArgs = newSeq[ScriptValue](args.len + 1)
  for i, a in args: callArgs[i + 1] = a
  for hd in hs:
    callArgs[0] = vstr(enemyTypeName(result))
    if callAs(hd.owner, hd.fn, callArgs, r) and r.count > 0 and r.first.kind == vkString:
      var t: EnemyType
      if resolveEnemyName(r.first.str.s, t):
        result = t
      else:
        reportModError(hd.owner, $h & ": unknown enemy type '" & r.first.str.s & "'")

# ------------------------------------------------------- action queue ----
# Hooks fire inside the game's entity loops, where adding or removing enemies
# would corrupt the iteration. Anything structural a script asks for is queued
# here and carried out by game.nim (processModActions) right after the
# simulation, outside every loop, the same frame.
type
  ModActionKind* = enum
    makSpawnEnemy, makSpawnBoss, makRemoveEnemy, makSpawnBullet, makRemoveBullet,
    makStartWave, makEndWave, makWin, makLose, makPowerUpDraft,
    makGivePowerUp, makTakePowerUp, makSpawnCoin, makSpawnXp, makSpawnConsumable,
    makEnter3D

  ModAction* = object
    kind*: ModActionKind
    owner*: int
    enemyType*: EnemyType
    x*, y*, vx*, vy*: float32
    bossId*: int
    elite*: bool
    difficulty*: float32   ## < 0: the run's current difficulty
    target*: Enemy
    damage*, radius*, lifetime*: float32
    fromPlayer*: bool
    color*: Color
    hasColor*: bool
    callback*: ScriptValue ## called with the spawned enemy
    bullet*: Bullet
    powerType*: PowerUpType
    level*, value*: int
    consumable*: ConsumableType
    enter3d*: World3DOptions ## makEnter3D: how the 3D world is entered

var modActions*: seq[ModAction]

proc queueModAction*(a: ModAction) =
  if modActions.len < 4096:  # a runaway loop can't queue the whole heap
    modActions.add(a)

proc modActionDone*(a: ModAction, spawned: Enemy) =
  if a.callback.kind in {vkFunction, vkNative} and not spawned.isNil:
    var r: RetVals
    discard callAs(a.owner, a.callback, [wrapEnemy(spawned)], r)

# ------------------------------------------------------ boss routes ----
type ScriptFn* = object
  owner*: int
  fn*: ScriptValue

var
  bossAttackFns*: Table[string, ScriptFn]   ## "mod:<key>" attack  -> fn(boss, attack, game)
  bossBehaviorFns*: Table[string, ScriptFn] ## "mod:<key>" movement -> fn(boss, dt, game)
  bossDrawFns*: Table[int, ScriptFn]        ## boss ID -> fn(boss)
  enemyDrawFns*: Table[int, ScriptFn]       ## EnemyType ord -> fn(enemy) (mod enemies)
  enemyUpdateFns*: Table[int, ScriptFn]     ## EnemyType ord -> fn(enemy, dt, game)
  powerUpUpdateFns*: Table[int, ScriptFn]   ## PowerUpType ord -> fn(player, level, dt, game)
  powerUpHitFns*: Table[int, ScriptFn]      ## PowerUpType ord -> fn(bullet, enemy, damage, level)
  powerUpDamageSink*: proc (game: Game, pt: PowerUpType, amount: float32) {.nimcall.}
    ## Installed by mod_api: books damage a mod power-up dealt in the run stats.

proc callForPowerUp*(pt: PowerUpType, f: ScriptFn, args: openArray[ScriptValue],
                     r: var RetVals): bool =
  ## Run a power-up's own script with the power-up as the credited source, so
  ## enemy:damage / player:heal inside it land in that power-up's statistics.
  let prevSource = modCtx.source
  let prevHas = modCtx.hasSource
  modCtx.source = pt
  modCtx.hasSource = true
  defer:
    modCtx.source = prevSource
    modCtx.hasSource = prevHas
  callAs(f.owner, f.fn, args, r)

proc ownedLevels(p: Player, table: Table[int, ScriptFn]): seq[tuple[pt: PowerUpType, level: int]] =
  ## The player's power-ups that have a script in `table` (a snapshot: a
  ## script may add or remove power-ups while the list is being walked).
  if table.len == 0 or p.isNil: return
  for pu in p.powerUps:
    if pu.level > 0 and table.hasKey(ord(pu.powerType)):
      result.add((pu.powerType, pu.level))

proc tickPowerUpScripts(game: Game, dt: float64) =
  var r: RetVals
  for (pt, level) in ownedLevels(game.player, powerUpUpdateFns):
    discard callForPowerUp(pt, powerUpUpdateFns[ord(pt)],
                           [wrapPlayer(game.player), vnum(level), vnum(dt), wrapGame(game)], r)

proc attackTable*(attack: BossAttack): ScriptValue =
  let t = newScriptTable()
  rawSet(t, vstr("type"), vstr($attack.attackType))
  rawSet(t, vstr("damage"), vnum(attack.damage.float64))
  rawSet(t, vstr("cooldown"), vnum(attack.cooldown.float64))
  rawSet(t, vstr("projectileSpeed"), vnum(attack.projectileSpeed.float64))
  rawSet(t, vstr("projectileCount"), vnum(attack.projectileCount))
  rawSet(t, vstr("spreadAngle"), vnum(attack.spreadAngle.float64))
  rawSet(t, vstr("durationOrRadius"), vnum(attack.durationOrRadius.float64))
  rawSet(t, vstr("bulletRadius"), vnum(attack.bulletRadius.float64))
  rawSet(t, vstr("special"), vstr(attack.specialData))
  vtable(t)

# ------------------------------------------- typed call-site helpers ----
# One per hook, so gameplay code stays a single line. Each returns the
# vanilla value untouched when nothing is registered.

proc modWaveStart*(game: Game) =
  if hookActive(hkWaveStart):
    fire(hkWaveStart, [wrapGame(game), vnum(game.currentWave)])

proc modWaveEnd*(game: Game) =
  if hookActive(hkWaveEnd):
    fire(hkWaveEnd, [wrapGame(game), vnum(game.currentWave)])

proc modWaveEnemyCount*(game: Game, count: int): int =
  if not hookActive(hkWaveEnemyCount): return count
  let n = filterNum(hkWaveEnemyCount, count.float64, [wrapGame(game), vnum(game.currentWave)])
  clamp(int(round(n)), 0, 5000)

proc modWaveSpawn*(game: Game, et: EnemyType): EnemyType =
  result = et
  if rosterEntries.len > 0: result = applyRoster(game, result)
  if hookActive(hkWaveSpawn):
    result = filterEnemyType(hkWaveSpawn, result, [wrapGame(game), vnum(game.currentWave)])

proc modSpawnInterval*(game: Game, seconds: float32): float32 =
  if not hookActive(hkSpawnInterval): return seconds
  max(0.02'f32, filterNum(hkSpawnInterval, seconds.float64, [wrapGame(game)]).float32)

proc modBossForWave*(game: Game, bossId, wave: int): int =
  if not hookActive(hkBossForWave): return bossId
  int(round(filterNum(hkBossForWave, bossId.float64, [wrapGame(game), vnum(wave)])))

proc modSurvivalSpawn*(game: Game, et: EnemyType): EnemyType =
  result = et
  if rosterEntries.len > 0: result = applyRoster(game, result)
  if hookActive(hkSurvivalSpawn):
    result = filterEnemyType(hkSurvivalSpawn, result, [wrapGame(game)])

proc modSurvivalEvent*(game: Game, name: string): bool =
  hookActive(hkSurvivalEvent) and fireCancel(hkSurvivalEvent, [wrapGame(game), vstr(name)])

proc modFloorStart*(game: Game, floor: int) =
  if hookActive(hkFloorStart): fire(hkFloorStart, [wrapGame(game), vnum(floor)])

proc modRoomEnter*(game: Game, room: int) =
  if hookActive(hkRoomEnter): fire(hkRoomEnter, [wrapGame(game), vnum(room)])

proc modRoomCleared*(game: Game, room: int) =
  if hookActive(hkRoomCleared): fire(hkRoomCleared, [wrapGame(game), vnum(room)])

proc modRogueSpawn*(game: Game, et: EnemyType): EnemyType =
  result = et
  if rosterEntries.len > 0: result = applyRoster(game, result)
  if hookActive(hkRogueSpawn):
    result = filterEnemyType(hkRogueSpawn, result, [wrapGame(game)])

proc modEnemySpawn*(e: Enemy) =
  if hookActive(hkEnemySpawn) and not modCtx.inPvP:
    fire(hkEnemySpawn, [wrapEnemy(e)])

proc modEnemyUpdate*(e: Enemy, dt: float32): bool =
  ## True: a script took over this enemy's AI for the frame.
  if modCtx.inPvP: return false
  if enemyUpdateFns.len > 0:
    let f = enemyUpdateFns.getOrDefault(ord(e.enemyType))
    if f.fn.kind in {vkFunction, vkNative}:
      var r: RetVals
      if callAs(f.owner, f.fn, [wrapEnemy(e), vnum(dt.float64), wrapGame(modCtx.game)], r) and
         r.count > 0 and r.first.kind == vkBool and r.first.b:
        return true
  hookActive(hkEnemyUpdate) and fireCancel(hkEnemyUpdate, [wrapEnemy(e), vnum(dt.float64)])

proc modEnemyDraw*(e: Enemy): bool =
  ## True: a script drew this enemy's body (the built-in one is skipped).
  if modCtx.inPvP: return false
  let prev = modCtx.drawing
  modCtx.drawing = dtWorld
  defer: modCtx.drawing = prev
  if e.isBoss and bossDrawFns.len > 0:
    let f = bossDrawFns.getOrDefault(e.bossDefinitionID)
    if f.fn.kind in {vkFunction, vkNative}:
      var r: RetVals
      if callAs(f.owner, f.fn, [wrapEnemy(e)], r):
        return true
  if not e.isBoss and enemyDrawFns.len > 0:
    let f = enemyDrawFns.getOrDefault(ord(e.enemyType))
    if f.fn.kind in {vkFunction, vkNative}:
      var r: RetVals
      if callAs(f.owner, f.fn, [wrapEnemy(e)], r):
        return true
  hookActive(hkEnemyDraw) and fireCancel(hkEnemyDraw, [wrapEnemy(e)])

proc modEnemyDamaged*(e: Enemy, amount: float32): float32 =
  if not hookActive(hkEnemyDamaged) or modCtx.inPvP: return amount
  max(0.0, filterNum(hkEnemyDamaged, amount.float64, [wrapEnemy(e)])).float32

proc modEnemyDeath*(e: Enemy, game: Game) =
  if hookActive(hkEnemyDeath): fire(hkEnemyDeath, [wrapEnemy(e), wrapGame(game)])

proc modBossSpawn*(boss: Enemy, game: Game) =
  if hookActive(hkBossSpawn): fire(hkBossSpawn, [wrapEnemy(boss), wrapGame(game)])

proc modBossPhase*(boss: Enemy, phaseIndex: int) =
  if hookActive(hkBossPhase): fire(hkBossPhase, [wrapEnemy(boss), vnum(phaseIndex)])

proc modBossDeath*(boss: Enemy, game: Game) =
  if hookActive(hkBossDeath): fire(hkBossDeath, [wrapEnemy(boss), wrapGame(game)])

proc modBossAttack*(game: Game, boss: Enemy, attack: BossAttack): bool =
  ## True when the attack is handled here: cancelled by a bossAttack handler,
  ## or a "mod:" attack routed to the script that registered it (an unknown one,
  ## e.g. from a mod that is no longer loaded, simply does nothing).
  if modCtx.inPvP: return false
  let isModAttack = attack.specialData.startsWith("mod:")
  if hookActive(hkBossAttack) and
     fireCancel(hkBossAttack, [wrapEnemy(boss), attackTable(attack)]):
    return true
  if not isModAttack:
    return false
  let f = bossAttackFns.getOrDefault(attack.specialData)
  if f.fn.kind in {vkFunction, vkNative}:
    var r: RetVals
    discard callAs(f.owner, f.fn, [wrapEnemy(boss), attackTable(attack), wrapGame(game)], r)
  true

proc modBossBehavior*(game: Game, boss: Enemy, behavior: string, dt: float32): bool =
  ## "mod:" movement behaviours. True when handled.
  if not behavior.startsWith("mod:"): return false
  let f = bossBehaviorFns.getOrDefault(behavior)
  if f.fn.kind in {vkFunction, vkNative}:
    var r: RetVals
    discard callAs(f.owner, f.fn, [wrapEnemy(boss), vnum(dt.float64), wrapGame(game)], r)
  true

proc modShoot*(game: Game, dirX, dirY: float32): bool =
  hookActive(hkShoot) and not modCtx.inPvP and
    fireCancel(hkShoot, [wrapPlayer(game.player), wrapGame(game), vnum(dirX.float64), vnum(dirY.float64)])

proc modBulletHit*(b: Bullet, e: Enemy, damage: float32): float32 =
  result = damage
  if modCtx.inPvP: return
  if powerUpHitFns.len > 0 and b.fromPlayer and not modCtx.game.isNil:
    var r: RetVals
    for (pt, level) in ownedLevels(modCtx.game.player, powerUpHitFns):
      let before = result
      if callForPowerUp(pt, powerUpHitFns[ord(pt)],
                        [wrapBullet(b), wrapEnemy(e), vnum(before.float64), vnum(level)], r) and
         r.count > 0 and r.first.kind == vkNumber and r.first.n == r.first.n:
        result = max(0.0'f32, r.first.n.float32)
        if result > before and not powerUpDamageSink.isNil:
          powerUpDamageSink(modCtx.game, pt, result - before)
  if hookActive(hkBulletHit):
    result = max(0.0, filterNum(hkBulletHit, result.float64, [wrapBullet(b), wrapEnemy(e)])).float32

proc isRunPlayer(p: Player): bool {.inline.} =
  not modCtx.inPvP and not modCtx.game.isNil and modCtx.game.player == p

proc modPlayerDamaged*(p: Player, amount: float32): float32 =
  if not hookActive(hkPlayerDamaged) or not isRunPlayer(p): return amount
  max(0.0, filterNum(hkPlayerDamaged, amount.float64, [wrapPlayer(p)])).float32

proc modPlayerLethal*(p: Player): bool =
  hookActive(hkPlayerLethal) and isRunPlayer(p) and fireCancel(hkPlayerLethal, [wrapPlayer(p)])

proc modPlayerHeal*(p: Player, amount: float32): float32 =
  if not hookActive(hkPlayerHeal) or not isRunPlayer(p): return amount
  max(0.0, filterNum(hkPlayerHeal, amount.float64, [wrapPlayer(p)])).float32

proc modPlayerDraw*(p: Player): bool =
  if not hookActive(hkPlayerDraw) or not isRunPlayer(p): return false
  let prev = modCtx.drawing
  modCtx.drawing = dtWorld
  defer: modCtx.drawing = prev
  fireCancel(hkPlayerDraw, [wrapPlayer(p)])

proc modPlayerUpdate*(p: Player, dt: float32): bool =
  hookActive(hkPlayerUpdate) and isRunPlayer(p) and
    fireCancel(hkPlayerUpdate, [wrapPlayer(p), vnum(dt.float64)])

proc modDash*(p: Player): bool =
  hookActive(hkDash) and isRunPlayer(p) and fireCancel(hkDash, [wrapPlayer(p)])

proc modPlaceWall*(game: Game, x, y: float32): bool =
  hookActive(hkPlaceWall) and not modCtx.inPvP and
    fireCancel(hkPlaceWall, [vnum(x.float64), vnum(y.float64), wrapGame(game)])

proc modAbility*(game: Game): bool =
  hookActive(hkAbility) and not modCtx.inPvP and fireCancel(hkAbility, [wrapGame(game)])

proc inRunScripts(): bool {.inline.} =
  not modCtx.inPvP and not modCtx.game.isNil

proc modBulletSpawn*(b: Bullet) =
  if hookActive(hkBulletSpawn) and inRunScripts():
    fire(hkBulletSpawn, [wrapBullet(b)])

proc modBulletUpdate*(b: Bullet, dt: float32): bool =
  hookActive(hkBulletUpdate) and inRunScripts() and
    fireCancel(hkBulletUpdate, [wrapBullet(b), vnum(dt.float64)])

proc modBulletDraw*(b: Bullet): bool =
  if not hookActive(hkBulletDraw) or not inRunScripts(): return false
  let prev = modCtx.drawing
  modCtx.drawing = dtWorld
  defer: modCtx.drawing = prev
  fireCancel(hkBulletDraw, [wrapBullet(b)])

proc modLevelUp*(game: Game, level: int) =
  if hookActive(hkLevelUp) and not modCtx.inPvP:
    fire(hkLevelUp, [wrapGame(game), vnum(level)])

proc modXpToLevel*(xp, level: int, mode: GameMode): int =
  if not hookActive(hkXpToLevel) or not inRunScripts(): return xp
  let modeName = case mode
    of gmWaveBased: "wave"
    of gmTimeSurvival: "survival"
    of gmRoguelite: "roguelite"
    of gmSandbox: "sandbox"
    of gmPvP: "pvp"
  max(1, int(round(filterNum(hkXpToLevel, xp.float64, [vnum(level), vstr(modeName)]))))

proc modPowerUpApply*(p: Player, name: string, level: int): bool =
  hookActive(hkPowerUpApply) and isRunPlayer(p) and
    fireCancel(hkPowerUpApply, [vstr(name), vnum(level), wrapPlayer(p)])

proc modPickup*(game: Game, kind: string, value: float64): bool =
  ## True: a script took the pickup (it is gone, the vanilla reward is skipped).
  hookActive(hkPickup) and not modCtx.inPvP and
    fireCancel(hkPickup, [vstr(kind), vnum(value), wrapGame(game)])

proc modShopBuy*(game: Game, index: int, name: string, cost: int): bool =
  hookActive(hkShopBuy) and not modCtx.inPvP and
    fireCancel(hkShopBuy, [vnum(index + 1), vstr(name), vnum(cost), wrapGame(game)])

proc modCombatStats*(p: Player, damage, fireRate: var float32, critChance: var int,
                     critMultiplier: var float32) =
  ## Handlers get (player, stats) and edit the stats table in place.
  if not hookActive(hkCombatStats) or not isRunPlayer(p): return
  let t = newScriptTable()
  rawSet(t, vstr("damage"), vnum(damage.float64))
  rawSet(t, vstr("fireRate"), vnum(fireRate.float64))
  rawSet(t, vstr("critChance"), vnum(critChance))
  rawSet(t, vstr("critMultiplier"), vnum(critMultiplier.float64))
  fire(hkCombatStats, [wrapPlayer(p), vtable(t)])
  template readBack(key: string, dest: untyped, conv: untyped) =
    let v = rawGetStr(t, key)
    if v.kind == vkNumber and v.n == v.n:
      dest = conv(v.n)
  readBack("damage", damage, float32)
  readBack("fireRate", fireRate, float32)
  readBack("critChance", critChance, int)
  readBack("critMultiplier", critMultiplier, float32)
  fireRate = max(0.01'f32, fireRate)
  critChance = clamp(critChance, 0, 100)

proc modPowerUpPicked*(game: Game, name: string, level: int) =
  if hookActive(hkPowerUpPicked):
    fire(hkPowerUpPicked, [vstr(name), vnum(level), wrapGame(game)])

proc modCoinValue*(e: Enemy, amount: int): int =
  if not hookActive(hkCoinValue) or modCtx.inPvP: return amount
  max(0, int(round(filterNum(hkCoinValue, amount.float64, [wrapEnemy(e)]))))

proc modXpValue*(e: Enemy, amount: int): int =
  if not hookActive(hkXpValue) or modCtx.inPvP: return amount
  max(0, int(round(filterNum(hkXpValue, amount.float64, [wrapEnemy(e)]))))

# ------------------------------------------------------------ 3D worlds ----
# The game3d/ engine fires the world3d* hooks; the script-facing wrappers for
# its objects are made by mod_3d (high layer), which fills these impl vars at
# startup. Until then (and in tests with no scripting) a wrapper is nil.
var
  wrapWorld3DImpl*: proc (w: Game3D): ScriptValue {.nimcall.}
  wrapEntity3DImpl*: proc (e: Entity3D): ScriptValue {.nimcall.}
  wrapProjectile3DImpl*: proc (p: Projectile3D): ScriptValue {.nimcall.}
  wrapPickup3DImpl*: proc (p: Pickup3D): ScriptValue {.nimcall.}

proc wrapWorld3D*(w: Game3D): ScriptValue =
  if w.isNil or wrapWorld3DImpl.isNil: NilValue else: wrapWorld3DImpl(w)

proc wrapEntity3D*(e: Entity3D): ScriptValue =
  if e.isNil or wrapEntity3DImpl.isNil: NilValue else: wrapEntity3DImpl(e)

proc wrapProjectile3D*(p: Projectile3D): ScriptValue =
  if p.isNil or wrapProjectile3DImpl.isNil: NilValue else: wrapProjectile3DImpl(p)

proc wrapPickup3D*(p: Pickup3D): ScriptValue =
  if p.isNil or wrapPickup3DImpl.isNil: NilValue else: wrapPickup3DImpl(p)

# The world's own action queue. Hooks fire inside the world's entity and
# projectile loops, so a script adding things there only queues them here; the
# engine (game_3d.nim processWorld3DActions) applies the queue between stages,
# outside every loop. Removal needs no queue: `alive = false` and the engine
# sweeps the dead after the stage.
type
  World3DActionKind* = enum
    wkSpawnEntity, wkSpawnProjectile, wkSpawnPickup, wkFinish

  World3DAction* = object
    kind*: World3DActionKind
    owner*: int
    entity*: Entity3D          ## wkSpawnEntity: already built (id assigned), not yet in the world
    projectile*: Projectile3D  ## wkSpawnProjectile
    pickup*: Pickup3D          ## wkSpawnPickup
    result*: World3DResult     ## wkFinish
    callback*: ScriptValue     ## wkSpawnEntity: called with the entity once it is in the world

var world3dActions*: seq[World3DAction]

type World3DLabel* = object
  ## draw3d.text: a label anchored to a point in the world. Text cannot be drawn
  ## inside the 3D camera, so the engine draws these after it, once per frame.
  pos*: Vector3f
  text*: string
  size*: int32
  color*: Color
  font*: int          ## a mod font (assets.font), 0 = the game's own
  spacing*: float32   ## a mod font's letter spacing

const MaxWorld3DLabels* = 512
var world3dLabels*: seq[World3DLabel]

proc queueWorld3DAction*(a: World3DAction) =
  if world3dActions.len < 4096:  # a runaway loop can't queue the whole heap
    world3dActions.add(a)

proc world3DActionDone*(a: World3DAction) =
  ## The engine calls this once a wkSpawnEntity is in the world.
  if a.callback.kind in {vkFunction, vkNative} and not a.entity.isNil:
    var r: RetVals
    discard callAs(a.owner, a.callback, [wrapEntity3D(a.entity)], r)

proc world3dScripts(): bool {.inline.} =
  not modCtx.inPvP

proc modWorld3DStart*(w: Game3D, resumed: bool) =
  if hookActive(hkWorld3dStart) and world3dScripts():
    fire(hkWorld3dStart, [wrapWorld3D(w), vbool(resumed)])

proc modWorld3DPreUpdate*(w: Game3D, dt: float32) =
  if hookActive(hkWorld3dPreUpdate) and world3dScripts():
    fire(hkWorld3dPreUpdate, [wrapWorld3D(w), vnum(dt.float64)])

proc modWorld3DUpdate*(w: Game3D, dt: float32) =
  if hookActive(hkWorld3dUpdate) and world3dScripts():
    fire(hkWorld3dUpdate, [wrapWorld3D(w), vnum(dt.float64)])

proc modWorld3DEnd*(w: Game3D, result: World3DResult) =
  if hookActive(hkWorld3dEnd) and world3dScripts():
    fire(hkWorld3dEnd, [wrapWorld3D(w), vstr($result)])

proc modWorld3DDraw*(w: Game3D) =
  ## Inside beginMode3D: draw3d.* works, draw.* does not.
  if not hookActive(hkWorld3dDraw) or not world3dScripts(): return
  let prev = modCtx.drawing
  modCtx.drawing = dtWorld3D
  fire(hkWorld3dDraw, [wrapWorld3D(w)])
  modCtx.drawing = prev

proc modWorld3DDrawHud*(w: Game3D, sw, sh: int32) =
  ## After the vanilla 3D HUD, screen pixels: draw.* works.
  if not hookActive(hkWorld3dDrawHud) or not world3dScripts(): return
  let prev = modCtx.drawing
  let prevArena = modCtx.hudArena
  modCtx.hudArena = (0.0, 0.0, sw.float64, sh.float64)
  modCtx.drawing = dtHud
  fire(hkWorld3dDrawHud, [wrapWorld3D(w), vnum(sw.int), vnum(sh.int)])
  modCtx.drawing = prev
  modCtx.hudArena = prevArena

proc modWorld3DShoot*(w: Game3D): bool =
  hookActive(hkWorld3dShoot) and world3dScripts() and
    fireCancel(hkWorld3dShoot, [wrapWorld3D(w)])

proc modWorld3DHit*(damage: float32, target: Entity3D, targetName: string,
                    proj: Projectile3D): float32 =
  ## target is the entity that was hit, or nil for the boss ("boss") and its
  ## satellites ("satellite"), named by `targetName`.
  if not hookActive(hkWorld3dHit) or not world3dScripts(): return damage
  let t = if target.isNil: vstr(targetName) else: wrapEntity3D(target)
  max(0.0, filterNum(hkWorld3dHit, damage.float64, [t, wrapProjectile3D(proj)])).float32

proc modWorld3DPlayerDamaged*(amount: float32, source: string, entity: Entity3D): float32 =
  ## source: "projectile" (the boss's and entities' shots), "contact" (with the
  ## entity) or whatever world3d.damagePlayer was given ("script" by default).
  ## A fall through the death plane is not damage: world3dPlayerLethal handles it.
  if not hookActive(hkWorld3dPlayerDamaged) or not world3dScripts(): return amount
  max(0.0, filterNum(hkWorld3dPlayerDamaged, amount.float64,
                     [vstr(source), wrapEntity3D(entity)])).float32

proc modWorld3DPlayerLethal*(): bool =
  hookActive(hkWorld3dPlayerLethal) and world3dScripts() and
    fireCancel(hkWorld3dPlayerLethal, [])

proc modWorld3DEntitySpawn*(e: Entity3D) =
  if hookActive(hkWorld3dEntitySpawn) and world3dScripts():
    fire(hkWorld3dEntitySpawn, [wrapEntity3D(e)])

proc modWorld3DEntityUpdate*(e: Entity3D, dt: float32): bool =
  ## True: a script took over this entity's AI for the frame.
  hookActive(hkWorld3dEntityUpdate) and world3dScripts() and
    fireCancel(hkWorld3dEntityUpdate, [wrapEntity3D(e), vnum(dt.float64)])

proc modWorld3DEntityDraw*(e: Entity3D): bool =
  ## True: a script drew this entity (the built-in body is skipped).
  if not hookActive(hkWorld3dEntityDraw) or not world3dScripts(): return false
  let prev = modCtx.drawing
  modCtx.drawing = dtWorld3D
  defer: modCtx.drawing = prev
  fireCancel(hkWorld3dEntityDraw, [wrapEntity3D(e)])

proc modWorld3DEntityDeath*(e: Entity3D) =
  if hookActive(hkWorld3dEntityDeath) and world3dScripts():
    fire(hkWorld3dEntityDeath, [wrapEntity3D(e)])

proc modWorld3DBossPhase*(phase: int) =
  if hookActive(hkWorld3dBossPhase) and world3dScripts():
    fire(hkWorld3dBossPhase, [vnum(phase)])

proc modWorld3DBossAttack*(phase, pattern: int): bool =
  hookActive(hkWorld3dBossAttack) and world3dScripts() and
    fireCancel(hkWorld3dBossAttack, [vnum(phase), vnum(pattern)])

proc modWorld3DPickup*(p: Pickup3D): bool =
  ## True: a script took the pickup (it is gone, the vanilla effect is skipped).
  hookActive(hkWorld3dPickup) and world3dScripts() and
    fireCancel(hkWorld3dPickup, [wrapPickup3D(p)])

proc clearModRoutes*() =
  ## Loader: forget every per-content script route (a fresh set is registered).
  modActions.setLen(0)
  world3dActions.setLen(0)
  world3dLabels.setLen(0)
  rosterEntries.setLen(0)
  modModes.setLen(0)
  bossAttackFns.clear()
  bossBehaviorFns.clear()
  bossDrawFns.clear()
  enemyDrawFns.clear()
  enemyUpdateFns.clear()
  powerUpUpdateFns.clear()
  powerUpHitFns.clear()
  modApps.setLen(0)

proc dropRoutesOf*(owner: int) =
  ## A mod that failed while loading leaves no routes behind.
  var keptRoster: seq[RosterEntry]
  for r in rosterEntries:
    if r.owner != owner: keptRoster.add(r)
  rosterEntries = keptRoster
  var keptModes: seq[ModModeDef]
  for m in modModes:
    if m.owner != owner: keptModes.add(m)
  modModes = keptModes
  var keptApps: seq[ModApp]
  for a in modApps:
    if a.owner != owner: keptApps.add(a)
  modApps = keptApps
  var ks: seq[string]
  for k, f in bossAttackFns:
    if f.owner == owner: ks.add(k)
  for k in ks: bossAttackFns.del(k)
  ks.setLen(0)
  for k, f in bossBehaviorFns:
    if f.owner == owner: ks.add(k)
  for k in ks: bossBehaviorFns.del(k)
  var ids: seq[int]
  for k, f in bossDrawFns:
    if f.owner == owner: ids.add(k)
  for k in ids: bossDrawFns.del(k)
  ids.setLen(0)
  for k, f in enemyDrawFns:
    if f.owner == owner: ids.add(k)
  for k in ids: enemyDrawFns.del(k)
  ids.setLen(0)
  for k, f in enemyUpdateFns:
    if f.owner == owner: ids.add(k)
  for k in ids: enemyUpdateFns.del(k)
  for fns in [addr powerUpUpdateFns, addr powerUpHitFns]:
    ids.setLen(0)
    for k, f in fns[]:
      if f.owner == owner: ids.add(k)
    for k in ids: fns[].del(k)
