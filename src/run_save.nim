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
## Format: hand-written JSON (mirrors save_system.nim), one file per mode per
## profile at getAppDataPath()/run_save_<mode>.json, so a run in one mode can
## never overwrite or discard another mode's saved run. A `version` int guards
## the format; on mismatch or parse failure the save is discarded and the run
## starts fresh.
##
## This module must NEVER import game.nim (that would form an import cycle). It
## restores the roguelite floor via dungeon.nim's deterministic generateFloor +
## enterRoom, which do not depend on game.nim.

import json, os
import particle_types, types, save_system, utils, roguelite, dungeon, powerup, tutorial

const RunSaveVersion = 1

const LegacyRunSaveFile = "run_save.json"  # pre per-mode single shared file
const BlockCheckpointFile = "run_checkpoint.json"

proc runSaveFileFor*(mode: GameMode): string =
  "run_save_" & $mode & ".json"

proc getRunSavePath*(file: string): string =
  getAppDataPath() / file

# Block-checkpoint presence cache. The game-over screen asks "is there a
# checkpoint, and for which wave?" from both its input branch and its draw
# branch, every frame -- without this that is two file reads plus two full JSON
# parses per frame. This process is the only writer, so the cache only has to be
# dropped when we write/delete, and it is keyed by path so switching profiles
# (which changes getAppDataPath) re-reads on its own.
var bcCachePath = ""      # "" = nothing cached yet
var bcCacheExists = false
var bcCacheWave = 1
var bcCacheLivesUsed = 0

proc invalidateBlockCheckpointCache*() =
  bcCachePath = ""

proc deleteRunSave*(file: string) =
  ## Remove one of the current profile's run save files, if present.
  if file == BlockCheckpointFile:
    invalidateBlockCheckpointCache()
  try:
    let path = getRunSavePath(file)
    if fileExists(path):
      removeFile(path)
  except CatchableError:
    echo "Warning: could not delete run save"

proc deleteRunSave*(mode: GameMode) =
  ## Remove this mode's run save for the current profile, if any.
  deleteRunSave(runSaveFileFor(mode))

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
    # Without the baseline, a resumed run counts its whole HP pool as "invested"
    # and hands Juggernaut its capped bonus for free.
    "baselineMaxHp": p.baselineMaxHp,
    "baseRadius": p.baseRadius,
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
    # Roguelite patch state that lives on the player. The installed set itself
    # is rebuilt from the run's patch list (syncPlayerPatches).
    "rollbackArmed": p.rollbackArmed,
    "patchBlockCharges": p.patchBlockCharges,
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
  if j.hasKey("baselineMaxHp"):
    p.baselineMaxHp = j["baselineMaxHp"].getFloat().float32
  else:
    # Pre-rework save: invested HP can't be told apart from automatic growth any
    # more, so credit none of it. Leaving the fresh 9.0 default here would hand a
    # late-wave resume the capped Juggernaut bonus for free.
    p.baselineMaxHp = p.maxHp
  # baseRadius is permanently grown by Heavy Rounds, so it is build state, not a
  # constant: without it a resumed run silently drops that power-up's drawback.
  f("baseRadius", p.baseRadius)
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
  b("rollbackArmed", p.rollbackArmed)
  i("patchBlockCharges", p.patchBlockCharges)
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
# A sector is DETERMINISTIC from (run.seed, floorNumber, endlessLoop) via
# dungeon.generateFloor: every layer's exits are rolled there. So instead of
# persisting the sector we persist its theme, the PATH of exits taken, and the
# live room's progress (flags + its pickups, which hold rolled patches and
# stall stock). Load regenerates the sector, replays the path, and overlays
# the live room. "floorFormat" 2 marks this layout; a save without it comes
# from the old grid dungeon and restarts its sector instead.
# ---------------------------------------------------------------------------
const RogueliteFloorFormat = 2

proc parsePickupKind(s: string): DungeonPickupKind = parseEnumOr(s, dpkShardCache)

proc pickupToJson(pk: DungeonPickup): JsonNode =
  %* {
    "kind": $pk.kind, "x": pk.pos.x, "y": pk.pos.y, "taken": pk.taken,
    "patch": $pk.patch, "pu": $pk.powerUp.powerType, "lvl": pk.powerUp.level,
    "rarity": $pk.powerUp.rarity, "amount": pk.amount, "group": pk.group
  }

proc jsonToPickup(j: JsonNode): DungeonPickup =
  DungeonPickup(
    kind: parsePickupKind(j.getOrDefault("kind").getStr()),
    pos: newVector2f(j.getOrDefault("x").getFloat().float32, j.getOrDefault("y").getFloat().float32),
    taken: j.getOrDefault("taken").getBool(false),
    patch: parseRelic(j.getOrDefault("patch").getStr("rrtNone")),
    powerUp: PowerUp(powerType: parsePowerType(j.getOrDefault("pu").getStr()),
                     level: j.getOrDefault("lvl").getInt(0),
                     rarity: parseRarity(j.getOrDefault("rarity").getStr("prCommon"))),
    amount: j.getOrDefault("amount").getInt(0),
    group: j.getOrDefault("group").getInt(0),
    spawnTimer: PickupSpawnTime)   # already materialized when it was saved

proc rogueliteRunToJson(run: RogueliteRun): JsonNode =
  var relics = newJArray()
  for r in run.relics: relics.add(%($r.relicType))

  var usedThemes = newJArray()
  for th in DungeonFloorTheme:
    if th in run.usedThemes: usedThemes.add(%($th))

  var themeChoices = newJArray()
  for th in run.nextThemeChoices: themeChoices.add(%($th))

  result = %* {
    "floorFormat": RogueliteFloorFormat,
    "seed": run.seed,
    "starterKit": $run.starterKit,
    "heat": run.heat,
    "floorNumber": run.floorNumber,
    "totalRoomsCleared": run.totalRoomsCleared,
    "usedThemes": usedThemes,
    "nextThemeChoices": themeChoices,
    "pendingFloorSelect": run.pendingFloorSelect,
    "relics": relics,
    "shardsEarned": run.shardsEarned,
    "coresEarned": run.coresEarned,
    "totalShardsBanked": run.totalShardsBanked,
    "totalCoresBanked": run.totalCoresBanked,
    "heatUnlocked": run.heatUnlocked,
    "endlessLoop": run.endlessLoop,
    "hasFloor": not run.floor.isNil
  }

  if not run.floor.isNil and run.floor.rooms.len > 0:
    let fl = run.floor
    let room = fl.rooms[fl.rooms.high]
    var path = newJArray()
    for p in fl.path: path.add(%p)
    var pickups = newJArray()
    for pk in room.pickups: pickups.add(pickupToJson(pk))
    result["floor"] = %* {
      "theme": $fl.theme,
      "path": path,
      "room": {
        "cleared": room.cleared, "rewardSpawned": room.rewardSpawned,
        "rewardClaimed": room.rewardClaimed, "restocks": room.restocks,
        "pickups": pickups
      }
    }

# ---------------------------------------------------------------------------
# Public API.
# ---------------------------------------------------------------------------
proc isSupportedRunMode(mode: GameMode): bool =
  mode in {gmWaveBased, gmTimeSurvival, gmRoguelite}

proc saveRunState*(game: Game, file: string = "",
                   bypassStateGate: bool = false) =
  ## Serialize durable run state for the current mode. No-op for unsupported
  ## modes (PvP / sandbox / 3D boss) or when there is nothing to resume.
  ## `file` defaults to this mode's own run save.
  if game.isNil or not isSupportedRunMode(game.mode):
    return
  # A tutorial practice session (or a first run still inside its tutorial) is
  # never a run to resume -- and must not overwrite the player's real save.
  if tutorialSuppressesSaves(game):
    return
  let file = if file.len > 0: file else: runSaveFileFor(game.mode)
  # Only an actually-live run is resumable. Guards against persisting the idle
  # menu Game (which defaults to gmWaveBased) as a bogus wave-1 save on shutdown.
  # A block-checkpoint write (bypassStateGate) may fire at the boss-completion
  # moment where the transient state is not one of the resumable states.
  if not bypassStateGate and
     game.state notin {gsPlaying, gsPaused, gsShop, gsCountdown, gsWaveCleared,
                       gsPowerUpSelect, gsRogueliteFloorSelect}:
    return
  # Never persist a finished/failed run.
  if game.hasWonGame and game.mode == gmWaveBased:
    deleteRunSave(file)
    return
  if game.mode == gmRoguelite and (game.rogueliteRun.isNil or
     game.rogueliteRun.completed or game.rogueliteRun.died):
    deleteRunSave(file)
    return

  # Per-item purchase counts drive BOTH the shop's price curve
  # (baseCost * 1.8^bought) and the per-purchase gain curves, so they are durable
  # run state. The stat gains themselves are already baked into the saved player,
  # so these are restored as counters only -- never re-applied as effects.
  var shopBought = newJArray()
  for item in game.shopItems:
    shopBought.add(%item.bought)

  # Level-up drafts still owed. The draft on screen right now has already been
  # taken off the queue, so a level draft that is open counts as owed too;
  # without this, saving mid-draft lost that power-up choice on resume.
  let levelDraftOpen = game.state == gsPowerUpSelect and
    (game.levelDraftActive or
     (game.mode == gmRoguelite and game.powerUpChoices[0].rarity == prCommon))
  let draftsOwed = max(0, game.pendingLevelDrafts) + (if levelDraftOpen: 1 else: 0)

  # Any OTHER draft open right now: a boss's legendary reward, or wave mode's
  # between-waves pick. Neither is queued anywhere, so without this a resume
  # dropped straight back into play and the reward was simply gone.
  let openDraft =
    if game.state != gsPowerUpSelect or levelDraftOpen: ""
    elif game.powerUpChoices[0].rarity == prLegendary: "legendary"
    elif game.mode == gmWaveBased: "boundary"
    else: ""

  var root = %* {
    "version": RunSaveVersion,
    "mode": $game.mode,
    "cheatsUsed": game.cheatsUsed,
    "runHadDeath": game.runHadDeath,
    # Continues spent so far. This is the ONE durable home of the lives budget:
    # death deletes the normal run save but leaves the block checkpoint, so
    # without this counter riding along in the checkpoint every Continue would
    # restore a run that had never spent anything.
    "livesUsed": game.livesUsed,
    # What the lifetime statistics already hold for a continued run, so the
    # next record after a resume does not count those kills and time again.
    "statsBaseKills": game.statsBaseKills,
    "statsBaseTime": game.statsBaseTime,
    # Wave/survival meta-currency tally (display only: the wallet itself was
    # credited as each reward was earned).
    "metaShardsEarned": game.metaShardsEarned,
    "metaCoresEarned": game.metaCoresEarned,
    "time": game.time,
    "shopBought": shopBought,
    "pendingLevelDrafts": draftsOwed,
    "openDraft": openDraft,
    "player": playerToJson(game.player)
  }

  case game.mode
  of gmWaveBased:
    root["currentWave"] = %game.currentWave
    # A checkpoint written mid-wave already carries this wave's player scaling;
    # recording it stops the resumed startWave from applying it a second time.
    root["waveScalingApplied"] = %game.waveScalingApplied
    root["wavesUntilBoss"] = %game.wavesUntilBoss
    root["bossCount"] = %game.bossCount
    root["rerollCost"] = %game.rerollCost
    root["hasWonGame"] = %game.hasWonGame
    # Mid-fight (the boss respawns: bossCount must not count it twice) or boss
    # dead with its reward coin still on the floor (the wave only ends when that
    # coin is picked up; without it the resume re-fought a boss already killed).
    root["bossActive"] = %game.bossWaveManager.active
    root["bossCoinPending"] = %game.bossWaveManager.coinActive
  of gmTimeSurvival:
    root["survivalTime"] = %game.survivalTime
    root["bossTimer"] = %game.bossTimer
    root["bossCount"] = %game.bossCount
    # Saved mid-fight: bossCount already counts this boss, and the resume
    # respawns it, which bumped the count again and skipped a boss tier.
    root["bossActive"] = %game.bossWaveManager.active
    # Phases / System Events / Data Caches. A running event is not saved (the
    # resume drops it); a Rogue Process that was live is re-armed instead.
    let s = game.survival
    var chests = newJArray()
    for c in s.chests:
      chests.add(%* {"t": $c.tier, "x": c.pos.x, "y": c.pos.y})
    root["survivalFormat"] = %SurvivalSaveFormat
    root["survivalVictory"] = %s.victoryAchieved
    root["survivalNextEvent"] = %s.nextEventClock
    root["survivalLastEvent"] = %($s.lastEventKind)
    root["survivalNextRogue"] = %s.nextRogueIndex
    root["survivalRogueActive"] = %(s.event.kind == sekRogueProcess)
    root["survivalEventsStarted"] = %s.eventsStarted
    root["survivalEventsCleared"] = %s.eventsCleared
    root["survivalCachesOpened"] = %s.cachesOpened
    root["survivalChests"] = chests
  of gmRoguelite:
    root["roguelite"] = rogueliteRunToJson(game.rogueliteRun)
    # Theme choices are only rolled when the floor-select screen opens, so a
    # save taken between floors before that still holds the PREVIOUS floor's
    # cards. Only a save taken on that screen may keep the ones it shows.
    root["floorSelectOpen"] = %(game.state == gsRogueliteFloorSelect)
  else: discard

  try:
    writeFile(getRunSavePath(file), root.pretty())
  except CatchableError:
    echo "Warning: could not write run save"

proc loadRunSaveJson(file: string): JsonNode =
  ## Parse the run save, returning nil on any failure or version mismatch.
  try:
    let path = getRunSavePath(file)
    if not fileExists(path):
      return nil
    let j = parseJson(readFile(path))
    if j.kind != JObject or j.getOrDefault("version").getInt(-1) != RunSaveVersion:
      return nil
    return j
  except CatchableError:
    return nil

proc migrateLegacyRunSave() =
  ## Older builds kept every mode's run in one shared run_save.json. Move it to
  ## the per-mode file for the mode it records (or drop it if that slot is
  ## already taken or the file is unreadable).
  try:
    let legacy = getRunSavePath(LegacyRunSaveFile)
    if not fileExists(legacy):
      return
    let j = loadRunSaveJson(LegacyRunSaveFile)
    if not j.isNil:
      let mode = parseMode(j.getOrDefault("mode").getStr("gmWaveBased"))
      let dest = getRunSavePath(runSaveFileFor(mode))
      if not fileExists(dest):
        moveFile(legacy, dest)
        return
    removeFile(legacy)
  except CatchableError:
    echo "Warning: could not migrate legacy run save"

proc hasSavedRun*(mode: GameMode): bool =
  ## True when `mode` has a valid saved run on the current profile.
  migrateLegacyRunSave()
  loadRunSaveJson(runSaveFileFor(mode)) != nil

proc applySavedRun*(game: Game, file: string = ""): bool =
  ## Restore saved state onto a freshly constructed Game that has already had
  ## newGame + setGameMode(savedMode) applied. Returns false on parse failure or
  ## version/mode mismatch; the caller then deletes the file and starts fresh.
  ## On success the game.state is set to the correct resume entry state.
  ## `file` defaults to this mode's own run save.
  migrateLegacyRunSave()
  let j = loadRunSaveJson(if file.len > 0: file else: runSaveFileFor(game.mode))
  if j.isNil:
    return false

  let savedMode = parseMode(j.getOrDefault("mode").getStr("gmWaveBased"))
  if savedMode != game.mode:
    return false

  try:
    game.cheatsUsed = j.getOrDefault("cheatsUsed").getBool(false)
    # Sticky death flag. Saves from before this field existed default to false;
    # that is safe for the normal run save (death deletes it), and the block
    # checkpoint path re-flags it at the call site since resuming one means the
    # player died.
    game.runHadDeath = j.getOrDefault("runHadDeath").getBool(false)
    # Saves from before the lives system default to 0 spent, which is the
    # generous reading -- an in-flight run keeps its full budget.
    game.livesUsed = max(0, j.getOrDefault("livesUsed").getInt(0))
    game.statsBaseKills = max(0, j.getOrDefault("statsBaseKills").getInt(0))
    game.statsBaseTime = max(0.0, j.getOrDefault("statsBaseTime").getFloat(0.0)).float32
    game.metaShardsEarned = max(0, j.getOrDefault("metaShardsEarned").getInt(0))
    game.metaCoresEarned = max(0, j.getOrDefault("metaCoresEarned").getInt(0))
    game.time = j.getOrDefault("time").getFloat(0.0).float32
    game.pendingLevelDrafts = max(0, j.getOrDefault("pendingLevelDrafts").getInt(0))
    if j.hasKey("player"):
      applyPlayerJson(game.player, j["player"])

    # Restore the shop price/gain curves. Counters only: the purchases they paid
    # for are already part of the restored player stats (re-applying the effects
    # here would double them).
    # getElems() rather than a raw `.kind` test: getOrDefault returns nil for a
    # missing key, and reading .kind off that nil segfaults. Saves written before
    # shopBought existed have no such key, so this must stay nil-tolerant.
    let shopBought = j.getOrDefault("shopBought").getElems()
    for i in 0 ..< min(shopBought.len, game.shopItems.len):
      game.shopItems[i].bought = max(0, shopBought[i].getInt(0))

    case game.mode
    of gmWaveBased:
      game.currentWave = j.getOrDefault("currentWave").getInt(1)
      # Saves from before this field existed default to 0: scaling is applied
      # on resume exactly as it always was.
      game.waveScalingApplied = j.getOrDefault("waveScalingApplied").getInt(0)
      # Clamped so a save written under a different boss cadence cannot schedule
      # a stale, longer gap before the counter resyncs.
      game.wavesUntilBoss = min(j.getOrDefault("wavesUntilBoss").getInt(BossWaveInterval - 1),
                                BossWaveInterval - 1)
      game.bossCount = j.getOrDefault("bossCount").getInt(0)
      game.rerollCost = j.getOrDefault("rerollCost").getInt(0)
      game.hasWonGame = j.getOrDefault("hasWonGame").getBool(false)
      game.waveInProgress = false
      game.waveEnemiesRemaining = 0
      game.bossWaveManager = BossWaveManager(active: false, coinActive: false)
      if j.getOrDefault("bossActive").getBool(false):
        # The resumed wave respawns this boss, which counts it again.
        game.bossCount = max(0, game.bossCount - 1)
      elif j.getOrDefault("bossCoinPending").getBool(false):
        # The boss is already dead: only its reward coin was left. Re-arm the
        # coin (updateGameCoins puts it back on the floor) so collecting it ends
        # the wave, instead of restarting the boss wave and fighting it again.
        # The pending coin also holds off startWave and the boss spawner.
        game.bossWaveManager.coinActive = true
      # gsPlaying + waveInProgress=false makes updateGame auto-start currentWave
      # through the normal startWave path.
      game.state = gsPlaying

    of gmTimeSurvival:
      game.survivalTime = j.getOrDefault("survivalTime").getFloat(0.0).float32
      # Every whole minute up to the restored clock was already paid into the
      # wallet before this save, so resuming must not pay it again.
      game.survivalMinutesRewarded = int(game.survivalTime / 60.0'f32)
      game.bossTimer = j.getOrDefault("bossTimer").getFloat(0.0).float32
      game.bossCount = j.getOrDefault("bossCount").getInt(0)
      if j.getOrDefault("survivalFormat").getInt(0) < SurvivalSaveFormat:
        # A save from the old 90 s boss cadence: its bossCount means nothing on
        # the 5:00 phase schedule. Count the phase bosses the clock has passed;
        # any that is overdue simply spawns on resume.
        game.bossCount = min(SurvivalFinalBoss - 1, int(game.survivalTime / SurvivalPhaseLength))
      elif j.getOrDefault("bossActive").getBool(false):
        # Saved mid-fight: the boss respawns on resume (the clock is still at
        # its spawn time) and spawning bumps bossCount, so undo this boss's
        # count or the resume would skip ahead to the next boss.
        game.bossCount = max(0, game.bossCount - 1)
      game.bossTimer = max(0.0'f32, survivalBossTime(game.bossCount + 1) - game.survivalTime)
      var s = initSurvivalState()
      s.victoryAchieved = j.getOrDefault("survivalVictory").getBool(false)
      # The resume drops any running event: hold the next one off briefly.
      s.nextEventClock = max(j.getOrDefault("survivalNextEvent").getFloat(0.0).float32,
                             game.survivalTime + 15.0'f32)
      s.lastEventKind = parseEnumOr(j.getOrDefault("survivalLastEvent").getStr(""), sekNone)
      s.nextRogueIndex = max(0, j.getOrDefault("survivalNextRogue").getInt(0))
      if j.getOrDefault("survivalRogueActive").getBool(false):
        s.nextRogueIndex = max(0, s.nextRogueIndex - 1)   # the hunt re-fires
      s.eventsStarted = max(0, j.getOrDefault("survivalEventsStarted").getInt(0))
      s.eventsCleared = max(0, j.getOrDefault("survivalEventsCleared").getInt(0))
      s.cachesOpened = max(0, j.getOrDefault("survivalCachesOpened").getInt(0))
      s.formationClock = game.survivalTime + 10.0'f32
      s.bossWarnedIndex = game.bossCount   # re-warn about the next boss if due
      for c in j.getOrDefault("survivalChests").getElems():
        s.chests.add(SurvivalChest(
          tier: parseEnumOr(c.getOrDefault("t").getStr(""), sctMinor),
          pos: newVector2f(c.getOrDefault("x").getFloat(0.0).float32,
                           c.getOrDefault("y").getFloat(0.0).float32),
          age: 1.0'f32))
      game.survival = s
      game.waveInProgress = false
      game.bossWaveManager = BossWaveManager(active: false, coinActive: false)
      # No phase banner on resume: the phase has not changed.
      game.survival.lastPhase = survivalPhase(game)
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
        usedThemes: {},
        pendingFloorSelect: rj.getOrDefault("pendingFloorSelect").getBool(false),
        relics: @[],
        shardsEarned: rj.getOrDefault("shardsEarned").getInt(0),
        coresEarned: rj.getOrDefault("coresEarned").getInt(0),
        totalShardsBanked: rj.getOrDefault("totalShardsBanked").getInt(0),
        totalCoresBanked: rj.getOrDefault("totalCoresBanked").getInt(0),
        heatUnlocked: rj.getOrDefault("heatUnlocked").getInt(0),
        endlessLoop: rj.getOrDefault("endlessLoop").getInt(0),
        completed: false,
        died: false,
        awaitingVictoryScreen: false
      )
      # .getElems() on each: iterating a JsonNode reads .kind, which segfaults
      # when the key is absent (getOrDefault yields nil, not an empty array).
      for th in rj.getOrDefault("usedThemes").getElems():
        run.usedThemes.incl(parseTheme(th.getStr()))
      var idx = 0
      for th in rj.getOrDefault("nextThemeChoices").getElems():
        if idx < 3:
          run.nextThemeChoices[idx] = parseTheme(th.getStr())
          inc idx
      for r in rj.getOrDefault("relics").getElems():
        let patch = parseRelic(r.getStr())
        if patch != rrtNone and not run.hasRelic(patch):
          run.relics.add(makeRelic(patch))

      game.rogueliteRun = run
      game.player.rogueliteCosmetic = ord(run.starterKit) + 1
      game.wavesUntilBoss = 999
      # The player's patch mirror is rebuilt from the run's list, the one
      # source of truth for what is installed.
      syncPlayerPatches(game)

      if run.pendingFloorSelect or not rj.hasKey("floor"):
        # Between floors: drop into the floor-select screen.
        run.floor = nil
        # The cards are only kept when the save was taken ON that screen (and
        # were ever rolled): that is what the player saw, and rerolling them
        # would let a quit reroll the floors. A save taken earlier, e.g. the
        # boss-clear checkpoint, still holds the previous floor's cards -- the
        # theme just played among them -- so this floor's are rolled now.
        let neverRolled =
          run.nextThemeChoices[0] == run.nextThemeChoices[1] and
          run.nextThemeChoices[1] == run.nextThemeChoices[2] and
          run.nextThemeChoices[0] == dftFirewall
        if neverRolled or not j.getOrDefault("floorSelectOpen").getBool(false):
          generateThemeChoices(run)
        game.state = gsRogueliteFloorSelect
      else:
        let fj = rj["floor"]
        let theme = parseTheme(fj.getOrDefault("theme").getStr())
        run.usedThemes.incl(theme)
        game.state = gsPlaying
        if rj.getOrDefault("floorFormat").getInt(0) < RogueliteFloorFormat:
          # A save from the old grid dungeon: its room layout no longer exists.
          # Keep the run (player, patches, Heat, currencies) and restart the
          # sector it was in from its start room.
          startDungeonFloor(game, theme)
        else:
          # Regenerate the deterministic sector, replay the exits taken, then
          # overlay the live room's saved progress.
          run.floor = generateFloor(game, theme, run.floorNumber)
          beginSectorRooms(game)
          let pathJson = fj.getOrDefault("path").getElems()
          var pathOk = true
          for k in 1 ..< pathJson.len:
            let exitIdx = pathJson[k].getInt(-1)
            if k >= run.floor.layers.len or exitIdx < 0 or
               exitIdx >= run.floor.layers[k].exits.len:
              pathOk = false
              break
            # Folders behind the live one were finished when the player left them.
            let prev = run.floor.rooms[run.floor.rooms.high]
            prev.cleared = true
            prev.rewardSpawned = true
            prev.rewardClaimed = true
            discard appendRoom(game, exitIdx)
          if not pathOk:
            startDungeonFloor(game, theme)
          else:
            let room = run.floor.rooms[run.floor.rooms.high]
            let roomJson = fj.getOrDefault("room")
            if not roomJson.isNil and roomJson.kind == JObject:
              room.cleared = roomJson.getOrDefault("cleared").getBool(room.cleared)
              room.rewardSpawned = roomJson.getOrDefault("rewardSpawned").getBool(false)
              room.rewardClaimed = roomJson.getOrDefault("rewardClaimed").getBool(room.rewardClaimed)
              room.restocks = roomJson.getOrDefault("restocks").getInt(0)
              room.pickups = @[]
              for pk in roomJson.getOrDefault("pickups").getElems():
                room.pickups.add(jsonToPickup(pk))
            # enterRoom re-arms a fresh encounter for an un-cleared folder (a
            # mid-fight save restarts that fight) and leaves a cleared one as
            # it was, reward and stalls included.
            enterRoom(game, run.floor.rooms.high, ddDown, resumed = true)
    else:
      return false

    # A boss reward or between-waves draft that was open at save time is owed
    # again (level-up drafts ride along in pendingLevelDrafts instead). The
    # choices are re-rolled: the save keeps which draft it was, not its cards.
    let openDraft = j.getOrDefault("openDraft").getStr("")
    if openDraft in ["legendary", "boundary"]:
      game.powerUpChoices = generatePowerUpChoices(game.player, openDraft == "legendary",
                                                   AllPowerFamilies, game.mode)
      game.selectedPowerUp = 0
      initPowerUpRollAnimation(game)
      initializeRerollCost(game)
      game.levelDraftActive = false
      if game.mode == gmRoguelite and not game.rogueliteRun.isNil and
         game.rogueliteRun.pendingFloorSelect:
        # The floor boss's reward. Its room is not rebuilt between floors, so
        # the pick must lead straight to floor select rather than to the boss
        # room's exit portal.
        game.cheatRogueliteDirectFloorSelect = true
      game.state = gsPowerUpSelect

    return true
  except CatchableError:
    return false

# ---------------------------------------------------------------------------
# Block checkpoint: a durable, death-surviving wave-mode checkpoint written when
# a boss block is cleared. Stored in a SEPARATE file so player death (which
# deletes the normal run save) leaves it intact, enabling "Continue (Wave N)".
# ---------------------------------------------------------------------------
proc saveBlockCheckpoint*(game: Game) =
  ## Persist the current wave-mode run as a death-surviving checkpoint. Uses the
  ## state-gate bypass so it can fire outside the resumable states.
  ## Nightmare profiles never write one -- see difficultyAllowsContinue.
  if game.isNil or game.mode != gmWaveBased or not difficultyAllowsContinue():
    return
  invalidateBlockCheckpointCache()
  saveRunState(game, BlockCheckpointFile, bypassStateGate = true)

proc refreshBlockCheckpointCache() =
  let path = getRunSavePath(BlockCheckpointFile)
  if bcCachePath == path:
    return
  let j = loadRunSaveJson(BlockCheckpointFile)
  bcCacheExists = j != nil
  bcCacheWave = if j.isNil: 1 else: j.getOrDefault("currentWave").getInt(1)
  bcCacheLivesUsed = if j.isNil: 0 else: max(0, j.getOrDefault("livesUsed").getInt(0))
  bcCachePath = path

proc blockCheckpointExists*(): bool =
  ## Raw file presence, ignoring the difficulty and lives gates. Used by the
  ## game-over screen to decide WHOSE lives to show: a checkpoint on disk is the
  ## run that Continue would resume, so its counter is the one at stake even
  ## once it has been spent down to zero and the button is gone.
  refreshBlockCheckpointCache()
  bcCacheExists

proc blockCheckpointLivesUsed*(): int =
  ## Continues already spent by the run held in the block checkpoint. 0 when
  ## there is no checkpoint (a run that has not continued has spent nothing).
  refreshBlockCheckpointCache()
  if bcCacheExists: bcCacheLivesUsed else: 0

proc hasBlockCheckpoint*(): bool =
  ## Nightmare answers "no" even if a file somehow exists (e.g. a checkpoint left
  ## behind by an older build), so the Continue option can never come back.
  ## A run that has spent its whole lives budget answers "no" the same way, which
  ## is what turns the budget into a real limit rather than a display.
  if not difficultyAllowsContinue():
    return false
  refreshBlockCheckpointCache()
  if not bcCacheExists:
    return false
  livesRemaining(bcCacheLivesUsed) != 0

proc blockCheckpointWave*(): int =
  ## Wave the block checkpoint resumes at, or 1 if there is no valid checkpoint.
  refreshBlockCheckpointCache()
  bcCacheWave

proc consumeContinueLife*(game: Game) =
  ## Spend one life on a run that has just resumed its block checkpoint, and
  ## patch the new count straight back into the checkpoint file.
  ##
  ## The write-back is the whole point: applyBlockCheckpoint has just restored
  ## livesUsed FROM that file, so bumping it only in memory would be undone the
  ## moment the player died again before reaching the next boss block -- the
  ## same checkpoint would reload with the old count and the budget would never
  ## run out. Patching just this one key (rather than re-serializing the game)
  ## keeps the rest of the checkpoint byte-identical to what was verified good.
  inc game.livesUsed
  # The death that led here has already been written to the lifetime statistics,
  # and the checkpoint has just rolled the kill count and clock back. From here
  # on only what is gained on top of them is new (see persistRunResults).
  game.statsBaseKills = game.player.kills
  game.statsBaseTime = runElapsedTime(game)
  # Arm the "life lost" animation. Doing it here rather than at the two call
  # sites means every way of spending a life is animated by construction -- the
  # game-over Continue button and the desktop's resume-a-dead-run both land
  # here, and a third path added later would too.
  game.lifeLostTimer = LifeLostAnimDuration
  game.lifeLostSoundStage = 0
  let j = loadRunSaveJson(BlockCheckpointFile)
  if j.isNil:
    return
  j["livesUsed"] = %game.livesUsed
  invalidateBlockCheckpointCache()
  try:
    writeFile(getRunSavePath(BlockCheckpointFile), j.pretty())
  except CatchableError:
    echo "Warning: could not write run save"

proc applyBlockCheckpoint*(game: Game): bool =
  ## Restore the block checkpoint onto a freshly constructed wave-mode Game.
  applySavedRun(game, BlockCheckpointFile)

proc deleteBlockCheckpoint*() =
  deleteRunSave(BlockCheckpointFile)
