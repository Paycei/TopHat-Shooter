## Run save/resume (checkpoint) system.
##
## Persists durable RUN state so the player can close the game or exit to the
## main menu mid-run and later resume. This is a CHECKPOINT save of durable
## progression (mode, player build, wave/floor/time counters), NOT a mid-frame
## snapshot of every bullet/enemy/timer -- transient per-frame state is left at
## fresh-Game defaults and only whitelisted durable fields are overwritten.
##
## Covered modes: gmWaveBased, gmTimeSurvival, gmRoguelite.
## Out of scope: gmPvP, gmSandbox, the 3D boss state.
##
## Format: hand-written JSON (mirrors save_system.nim), one file per profile at
## getAppDataPath()/run_save.json. A `version` int guards the format; on mismatch
## or parse failure the save is discarded and the run starts fresh.
##
## This module must NEVER import game.nim (that would form an import cycle). It
## restores the roguelite floor via dungeon.nim's deterministic generateFloor +
## enterRoom, which do not depend on game.nim.

import json, os
import types, save_system, utils, roguelite, dungeon

const RunSaveVersion = 1

proc getRunSavePath*(): string =
  getAppDataPath() / "run_save.json"

proc deleteRunSave*() =
  ## Remove the current profile's run save, if any.
  try:
    let path = getRunSavePath()
    if fileExists(path):
      removeFile(path)
  except CatchableError:
    echo "Warning: could not delete run save"

# ---------------------------------------------------------------------------
# Small enum parse helpers (name-serialized, like save_system.nim).
# ---------------------------------------------------------------------------
proc parsePowerType(s: string): PowerUpType = parseEnumOr(s, puDoubleShot)
proc parseRarity(s: string): PowerUpRarity = parseEnumOr(s, prCommon)
proc parseElement(s: string): ElementType = parseEnumOr(s, ElementType.etNone)
proc parseMode(s: string): GameMode = parseEnumOr(s, gmWaveBased)
proc parseTheme(s: string): DungeonFloorTheme = parseEnumOr(s, dftFirewall)
proc parseStarter(s: string): RogueliteStarterKit = parseEnumOr(s, rskOperator)
proc parseRelic(s: string): RogueliteRelicType = parseEnumOr(s, rrtNone)

# ---------------------------------------------------------------------------
# Player build serialization (durable-field whitelist).
# ---------------------------------------------------------------------------
proc playerToJson(p: Player): JsonNode =
  var powerUps = newJArray()
  for pu in p.powerUps:
    powerUps.add(%* {"t": $pu.powerType, "l": pu.level, "r": $pu.rarity})

  var orbs = newJArray()
  for o in p.rotatingOrbs:
    orbs.add(%* {"angle": o.angle, "radius": o.radius,
                 "element": $o.elementType, "level": o.orbLevel})

  var shieldHealths = newJArray()
  for s in p.shieldHealths: shieldHealths.add(%s)
  var shieldRegen = newJArray()
  for s in p.shieldRegenTimers: shieldRegen.add(%s)

  result = %* {
    "hp": p.hp, "maxHp": p.maxHp,
    "speed": p.speed, "baseSpeed": p.baseSpeed,
    "damage": p.damage, "bulletDamageMult": p.bulletDamageMult,
    "fireRate": p.fireRate, "bulletSpeed": p.bulletSpeed,
    "coins": p.coins, "kills": p.kills, "walls": p.walls,
    "rogueliteLevel": p.rogueliteLevel, "xp": p.xp, "xpToNextLevel": p.xpToNextLevel,
    "powerUps": powerUps,
    "rotatingOrbs": orbs, "orbRotationAngle": p.orbRotationAngle,
    "shieldHealths": shieldHealths, "shieldRegenTimers": shieldRegen,
    "shieldMaxHealth": p.shieldMaxHealth, "shieldRegenDelay": p.shieldRegenDelay,
    "singularityShield": p.singularityShield,
    "singularityShieldMaxPct": p.singularityShieldMaxPct,
    "singularityShieldRegenDelay": p.singularityShieldRegenDelay,
    "singularityShieldRegenRatePct": p.singularityShieldRegenRatePct,
    "timeWarpMaxUsesPerWave": p.timeWarpMaxUsesPerWave,
    "resonanceLevel": p.resonanceLevel,
    "hasVolatile": p.hasVolatile,
    "healPowerMult": p.healPowerMult,
    "hasBountiful": p.hasBountiful,
    "glitchChance": p.glitchChance,
    "hasSectorProtocol": p.hasSectorProtocol,
    "celestialVeilCharges": p.celestialVeilCharges,
    "roomEchoCharges": p.roomEchoCharges,
    "corruptedCoreHpAcc": p.corruptedCoreHpAcc,
    "rageStacks": p.rageStacks,
    "hasFireMastery": p.hasFireMastery,
    "hasPoisonMastery": p.hasPoisonMastery,
    "hasFrostMastery": p.hasFrostMastery,
    "hasArcaneMastery": p.hasArcaneMastery,
    "hasLightningMastery": p.hasLightningMastery,
    "hasWindMastery": p.hasWindMastery,
    "hasBloodMastery": p.hasBloodMastery,
    "skinType": p.skinType, "bulletSkinType": p.bulletSkinType,
    "bulletShapeType": p.bulletShapeType, "shapeType": p.shapeType,
    "particleSkinType": p.particleSkinType, "cubeSkinType": p.cubeSkinType,
    "wearsTophat": p.wearsTophat, "wearsCheaterHat": p.wearsCheaterHat,
    "hasOrbitalCube": p.hasOrbitalCube, "rogueliteCosmetic": p.rogueliteCosmetic
  }

proc applyPlayerJson(p: Player, j: JsonNode) =
  ## Overwrite whitelisted durable fields onto a fresh newPlayer. Transient
  ## per-frame timers/cooldowns are intentionally left at their defaults.
  template f(key: string, field: untyped) =
    if j.hasKey(key): field = j[key].getFloat().float32
  template i(key: string, field: untyped) =
    if j.hasKey(key): field = j[key].getInt()
  template b(key: string, field: untyped) =
    if j.hasKey(key): field = j[key].getBool()

  f("hp", p.hp); f("maxHp", p.maxHp)
  f("speed", p.speed); f("baseSpeed", p.baseSpeed)
  f("damage", p.damage); f("bulletDamageMult", p.bulletDamageMult)
  f("fireRate", p.fireRate); f("bulletSpeed", p.bulletSpeed)
  i("coins", p.coins); i("kills", p.kills); i("walls", p.walls)
  i("rogueliteLevel", p.rogueliteLevel); i("xp", p.xp); i("xpToNextLevel", p.xpToNextLevel)

  if j.hasKey("powerUps"):
    p.powerUps = @[]
    for pu in j["powerUps"]:
      p.powerUps.add(PowerUp(
        powerType: parsePowerType(pu["t"].getStr()),
        level: pu["l"].getInt(),
        rarity: parseRarity(pu.getOrDefault("r").getStr("prCommon"))))

  if j.hasKey("rotatingOrbs"):
    p.rotatingOrbs = @[]
    for o in j["rotatingOrbs"]:
      p.rotatingOrbs.add(RotatingOrb(
        angle: o["angle"].getFloat().float32,
        radius: o["radius"].getFloat().float32,
        elementType: parseElement(o["element"].getStr()),
        orbLevel: o["level"].getInt(1),
        hitEnemies: @[]))
  f("orbRotationAngle", p.orbRotationAngle)

  if j.hasKey("shieldHealths"):
    p.shieldHealths = @[]
    for s in j["shieldHealths"]: p.shieldHealths.add(s.getFloat().float32)
  if j.hasKey("shieldRegenTimers"):
    p.shieldRegenTimers = @[]
    for s in j["shieldRegenTimers"]: p.shieldRegenTimers.add(s.getFloat().float32)
  f("shieldMaxHealth", p.shieldMaxHealth); f("shieldRegenDelay", p.shieldRegenDelay)
  f("singularityShield", p.singularityShield)
  f("singularityShieldMaxPct", p.singularityShieldMaxPct)
  f("singularityShieldRegenDelay", p.singularityShieldRegenDelay)
  f("singularityShieldRegenRatePct", p.singularityShieldRegenRatePct)

  i("timeWarpMaxUsesPerWave", p.timeWarpMaxUsesPerWave)
  i("resonanceLevel", p.resonanceLevel)
  b("hasVolatile", p.hasVolatile)
  f("healPowerMult", p.healPowerMult)
  b("hasBountiful", p.hasBountiful)
  f("glitchChance", p.glitchChance)
  b("hasSectorProtocol", p.hasSectorProtocol)
  i("celestialVeilCharges", p.celestialVeilCharges)
  i("roomEchoCharges", p.roomEchoCharges)
  f("corruptedCoreHpAcc", p.corruptedCoreHpAcc)
  i("rageStacks", p.rageStacks)

  b("hasFireMastery", p.hasFireMastery)
  b("hasPoisonMastery", p.hasPoisonMastery)
  b("hasFrostMastery", p.hasFrostMastery)
  b("hasArcaneMastery", p.hasArcaneMastery)
  b("hasLightningMastery", p.hasLightningMastery)
  b("hasWindMastery", p.hasWindMastery)
  b("hasBloodMastery", p.hasBloodMastery)

  i("skinType", p.skinType); i("bulletSkinType", p.bulletSkinType)
  i("bulletShapeType", p.bulletShapeType); i("shapeType", p.shapeType)
  i("particleSkinType", p.particleSkinType); i("cubeSkinType", p.cubeSkinType)
  b("wearsTophat", p.wearsTophat); b("wearsCheaterHat", p.wearsCheaterHat)
  b("hasOrbitalCube", p.hasOrbitalCube); i("rogueliteCosmetic", p.rogueliteCosmetic)

# ---------------------------------------------------------------------------
# Roguelite run serialization.
#
# The dungeon floor geometry is DETERMINISTIC from (run.seed, floorNumber,
# endlessLoop) via dungeon.generateFloor, so instead of persisting the whole
# room graph we persist only the mutable per-room progress and regenerate the
# geometry on load, then overlay the progress by room index.
# ---------------------------------------------------------------------------
proc rogueliteRunToJson(run: RogueliteRun): JsonNode =
  var relics = newJArray()
  for r in run.relics: relics.add(%($r.relicType))

  var usedThemes = newJArray()
  for th in DungeonFloorTheme:
    if th in run.usedThemes: usedThemes.add(%($th))

  var themeChoices = newJArray()
  for th in run.nextThemeChoices: themeChoices.add(%($th))

  result = %* {
    "seed": run.seed,
    "starterKit": $run.starterKit,
    "heat": run.heat,
    "floorNumber": run.floorNumber,
    "totalRoomsCleared": run.totalRoomsCleared,
    "keys": run.keys,
    "combatRoomsSinceDraft": run.combatRoomsSinceDraft,
    "usedThemes": usedThemes,
    "nextThemeChoices": themeChoices,
    "pendingFloorSelect": run.pendingFloorSelect,
    "relics": relics,
    "shardsEarned": run.shardsEarned,
    "coresEarned": run.coresEarned,
    "endlessLoop": run.endlessLoop,
    "hasFloor": not run.floor.isNil
  }

  if not run.floor.isNil:
    let fl = run.floor
    var rooms = newJArray()
    for room in fl.rooms:
      var pickups = newJArray()
      for pk in room.pickups: pickups.add(%pk.taken)
      rooms.add(%* {
        "cleared": room.cleared, "visited": room.visited,
        "seen": room.seen, "locked": room.locked,
        "pickupsTaken": pickups
      })
    result["floor"] = %* {
      "theme": $fl.theme,
      "currentRoom": fl.currentRoom,
      "mapRevealed": fl.mapRevealed,
      "compassFound": fl.compassFound,
      "rooms": rooms
    }

# ---------------------------------------------------------------------------
# Public API.
# ---------------------------------------------------------------------------
proc isSupportedRunMode(mode: GameMode): bool =
  mode in {gmWaveBased, gmTimeSurvival, gmRoguelite}

proc saveRunState*(game: Game) =
  ## Serialize durable run state for the current mode. No-op for unsupported
  ## modes (PvP / sandbox / 3D boss) or when there is nothing to resume.
  if game.isNil or not isSupportedRunMode(game.mode):
    return
  # Only an actually-live run is resumable. Guards against persisting the idle
  # menu Game (which defaults to gmWaveBased) as a bogus wave-1 save on shutdown.
  if game.state notin {gsPlaying, gsPaused, gsShop, gsCountdown, gsWaveCleared,
                       gsPowerUpSelect, gsRogueliteFloorSelect}:
    return
  # Never persist a finished/failed run.
  if game.hasWonGame and game.mode == gmWaveBased:
    deleteRunSave()
    return
  if game.mode == gmRoguelite and (game.rogueliteRun.isNil or
     game.rogueliteRun.completed or game.rogueliteRun.died):
    deleteRunSave()
    return

  var root = %* {
    "version": RunSaveVersion,
    "mode": $game.mode,
    "cheatsUsed": game.cheatsUsed,
    "time": game.time,
    "player": playerToJson(game.player)
  }

  case game.mode
  of gmWaveBased:
    root["currentWave"] = %game.currentWave
    root["wavesUntilBoss"] = %game.wavesUntilBoss
    root["bossCount"] = %game.bossCount
    root["rerollCost"] = %game.rerollCost
    root["hasWonGame"] = %game.hasWonGame
  of gmTimeSurvival:
    root["survivalTime"] = %game.survivalTime
    root["bossTimer"] = %game.bossTimer
    root["bossCount"] = %game.bossCount
  of gmRoguelite:
    root["roguelite"] = rogueliteRunToJson(game.rogueliteRun)
  else: discard

  try:
    writeFile(getRunSavePath(), root.pretty())
  except CatchableError:
    echo "Warning: could not write run save"

proc loadRunSaveJson(): JsonNode =
  ## Parse the run save, returning nil on any failure or version mismatch.
  try:
    let path = getRunSavePath()
    if not fileExists(path):
      return nil
    let j = parseJson(readFile(path))
    if j.kind != JObject or j.getOrDefault("version").getInt(-1) != RunSaveVersion:
      return nil
    return j
  except CatchableError:
    return nil

proc hasSavedRun*(): bool =
  loadRunSaveJson() != nil

proc loadSavedRunMode*(): GameMode =
  ## Mode of the current saved run, or gmWaveBased if there is no valid save
  ## (callers should gate on hasSavedRun first).
  let j = loadRunSaveJson()
  if j.isNil: return gmWaveBased
  parseMode(j.getOrDefault("mode").getStr("gmWaveBased"))

proc applySavedRun*(game: Game): bool =
  ## Restore saved state onto a freshly constructed Game that has already had
  ## newGame + setGameMode(savedMode) applied. Returns false on parse failure or
  ## version/mode mismatch; the caller then deletes the file and starts fresh.
  ## On success the game.state is set to the correct resume entry state.
  let j = loadRunSaveJson()
  if j.isNil:
    return false

  let savedMode = parseMode(j.getOrDefault("mode").getStr("gmWaveBased"))
  if savedMode != game.mode:
    return false

  try:
    game.cheatsUsed = j.getOrDefault("cheatsUsed").getBool(false)
    game.time = j.getOrDefault("time").getFloat(0.0).float32
    if j.hasKey("player"):
      applyPlayerJson(game.player, j["player"])

    case game.mode
    of gmWaveBased:
      game.currentWave = j.getOrDefault("currentWave").getInt(1)
      # Clamped: saves written before the interval-4 cadence can hold 4, which
      # would schedule one stale 5-wave gap before the counter resyncs.
      game.wavesUntilBoss = min(j.getOrDefault("wavesUntilBoss").getInt(BossWaveInterval - 1),
                                BossWaveInterval - 1)
      game.bossCount = j.getOrDefault("bossCount").getInt(0)
      game.rerollCost = j.getOrDefault("rerollCost").getInt(0)
      game.hasWonGame = j.getOrDefault("hasWonGame").getBool(false)
      game.waveInProgress = false
      game.waveEnemiesRemaining = 0
      game.bossWaveManager = BossWaveManager(active: false, coinActive: false)
      # gsPlaying + waveInProgress=false makes updateGame auto-start currentWave
      # through the normal startWave path.
      game.state = gsPlaying

    of gmTimeSurvival:
      game.survivalTime = j.getOrDefault("survivalTime").getFloat(0.0).float32
      game.bossTimer = j.getOrDefault("bossTimer").getFloat(0.0).float32
      game.bossCount = j.getOrDefault("bossCount").getInt(0)
      game.waveInProgress = false
      game.bossWaveManager = BossWaveManager(active: false, coinActive: false)
      game.state = gsPlaying

    of gmRoguelite:
      if not j.hasKey("roguelite"):
        return false
      let rj = j["roguelite"]
      let run = RogueliteRun(
        seed: rj.getOrDefault("seed").getInt(0),
        starterKit: parseStarter(rj.getOrDefault("starterKit").getStr("rskOperator")),
        heat: rj.getOrDefault("heat").getInt(RogueliteMinHeat),
        floorNumber: rj.getOrDefault("floorNumber").getInt(1),
        floor: nil,
        totalRoomsCleared: rj.getOrDefault("totalRoomsCleared").getInt(0),
        keys: rj.getOrDefault("keys").getInt(0),
        combatRoomsSinceDraft: rj.getOrDefault("combatRoomsSinceDraft").getInt(0),
        usedThemes: {},
        pendingFloorSelect: rj.getOrDefault("pendingFloorSelect").getBool(false),
        relics: @[],
        shardsEarned: rj.getOrDefault("shardsEarned").getInt(0),
        coresEarned: rj.getOrDefault("coresEarned").getInt(0),
        endlessLoop: rj.getOrDefault("endlessLoop").getInt(0),
        completed: false,
        died: false,
        awaitingVictoryScreen: false
      )
      for th in rj.getOrDefault("usedThemes"):
        run.usedThemes.incl(parseTheme(th.getStr()))
      var idx = 0
      for th in rj.getOrDefault("nextThemeChoices"):
        if idx < 3:
          run.nextThemeChoices[idx] = parseTheme(th.getStr())
          inc idx
      for r in rj.getOrDefault("relics"):
        run.relics.add(makeRelic(parseRelic(r.getStr())))

      game.rogueliteRun = run
      game.player.rogueliteCosmetic = ord(run.starterKit) + 1
      game.wavesUntilBoss = 999

      if run.pendingFloorSelect or not rj.hasKey("floor"):
        # Between floors: drop into the floor-select screen with the saved
        # theme choices (regenerated if the save had none).
        run.floor = nil
        # Regenerate choices only if the saved array was never populated (all
        # three still at the default theme); otherwise keep what the player saw.
        if run.nextThemeChoices[0] == run.nextThemeChoices[1] and
           run.nextThemeChoices[1] == run.nextThemeChoices[2] and
           run.nextThemeChoices[0] == dftFirewall:
          generateThemeChoices(run, 1)
        game.state = gsRogueliteFloorSelect
      else:
        let fj = rj["floor"]
        let theme = parseTheme(fj.getOrDefault("theme").getStr())
        # Regenerate the deterministic geometry, then overlay saved progress.
        let floor = generateFloor(game, theme, run.floorNumber)
        run.floor = floor
        run.usedThemes.incl(theme)
        floor.mapRevealed = fj.getOrDefault("mapRevealed").getBool(false)
        floor.compassFound = fj.getOrDefault("compassFound").getBool(false)
        let roomsJson = fj.getOrDefault("rooms")
        if roomsJson.kind == JArray and roomsJson.len == floor.rooms.len:
          for ri in 0 ..< floor.rooms.len:
            let room = floor.rooms[ri]
            let rjson = roomsJson[ri]
            room.cleared = rjson.getOrDefault("cleared").getBool(room.cleared)
            room.visited = rjson.getOrDefault("visited").getBool(room.visited)
            room.seen = rjson.getOrDefault("seen").getBool(room.seen)
            room.locked = rjson.getOrDefault("locked").getBool(room.locked)
            let pj = rjson.getOrDefault("pickupsTaken")
            if pj.kind == JArray and pj.len == room.pickups.len:
              for pi in 0 ..< room.pickups.len:
                room.pickups[pi].taken = pj[pi].getBool(false)
        else:
          # Geometry drift between versions: cannot safely overlay progress.
          return false
        let curRoom = clamp(fj.getOrDefault("currentRoom").getInt(floor.startIdx),
                            0, floor.rooms.high)
        game.state = gsPlaying
        # enterRoom re-arms a fresh encounter for an un-cleared combat room
        # (mid-encounter runs re-roll from encounterSeed) and simply opens the
        # doors for a cleared one.
        enterRoom(game, curRoom, ddUp)
    else:
      return false

    return true
  except CatchableError:
    return false
