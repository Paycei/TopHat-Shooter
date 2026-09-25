import json, os, random, strutils, math
import types, settings, save_system, powerup, powerup_data, patches, xp_orb, skins, bullet_skins, bullet_shapes, shapes, particle_skins, desktop_bg_skins, cube_skins

const
  RogueliteProfileVersion* = 5
    ## v5 = "earn, don't buy": the unlock shop is gone. Loading an older profile
    ## refunds everything it ever bought there (see legacyUnlockRefund).
  RogueliteFloorsToWin* = 4
  RogueliteMinHeat* = 1
  RogueliteMaxHeat* = 3
  RogueliteHeatRosterWaveOffset* = 1
  RogueliteHeatDifficultyPerTier* = 0.18'f32
  RogueliteHeatBossDifficultyPerTier* = 0.35'f32
  RogueliteHeatSpawnBurstPerTier* = 0.025'f32
  RogueliteHeatSpawnRatePerTier* = 0.035'f32

var activeRogueliteProfile*: RogueliteProfile
  ## The live Data Shard / Core wallet of the current save profile: the same
  ## object the shop, settings and advancements windows hold. main.nim keeps it
  ## current (setActiveRogueliteProfile). Wave and survival games never carry a
  ## `rogueliteProfile` of their own, so their rewards bank through this.

var pendingProfileRefund*: tuple[shards, cores: int]
  ## Currency refunded by the v4 -> v5 migration, parked here until main.nim
  ## can show it as a desktop toast (the profile loads before the desktop
  ## exists). Drained exactly once; the migrated profile is saved immediately,
  ## so a later load never refunds again.

proc saveRogueliteProfile*(profile: RogueliteProfile): bool
proc commitRogueliteRunProgress*(game: Game, died: bool): bool

proc heatChallengeRank*(heat: int): int =
  ## Heat 1 is the default baseline, Heat 2/3 add challenge.
  max(0, clamp(heat, RogueliteMinHeat, RogueliteMaxHeat) - RogueliteMinHeat)

proc getRogueliteProfilePath*(): string =
  getAppDataPath() / "roguelite_profile.json"

proc initRogueliteProfile*(): RogueliteProfile =
  result = RogueliteProfile(
    version: RogueliteProfileVersion,
    dataShards: 0,
    cores: 0,
    unlockedPlayerSkins: @["skDefault"],
    unlockedBulletSkins: @["bskDefault"],
    unlockedPlayerShapes: @["shHexagon"],
    unlockedBulletShapes: @["bshCircle"],
    unlockedParticleSkins: @["pskDefault"],
    unlockedDesktopBgs: @["dbgDefault"],
    unlockedCubeSkins: @["cskDefault"],
    highestHeat: RogueliteMinHeat,
    sectorsCleared: 0,
    bestFloor: 1,
    bestRooms: 0,
    bestEndlessLoop: 0,
    totalRuns: 0,
    wins: 0,
    recursionDamageBonus: 0.0'f32,
    recursionLevel: 0
  )

proc makeRelic*(relicType: RogueliteRelicType): RogueliteRelic =
  RogueliteRelic(relicType: relicType)

proc hasRelic*(run: RogueliteRun, relicType: RogueliteRelicType): bool =
  if run.isNil: return false
  for relic in run.relics:
    if relic.relicType == relicType:
      return true
  false

proc ensureString(list: var seq[string], value: string) =
  if value.len == 0: return
  for existing in list:
    if existing == value:
      return
  list.add(value)

proc normalizeRogueliteProfile*(profile: RogueliteProfile) =
  ## Stamp the current version and restore the invariants every profile must
  ## hold (default cosmetics owned, Heat in range, no negative wallet).
  if profile.isNil: return
  profile.version = RogueliteProfileVersion
  ensureString(profile.unlockedPlayerSkins, "skDefault")
  ensureString(profile.unlockedBulletSkins, "bskDefault")
  ensureString(profile.unlockedPlayerShapes, "shHexagon")
  ensureString(profile.unlockedBulletShapes, "bshCircle")
  ensureString(profile.unlockedParticleSkins, "pskDefault")
  ensureString(profile.unlockedDesktopBgs, "dbgDefault")
  ensureString(profile.unlockedCubeSkins, "cskDefault")
  profile.highestHeat = clamp(profile.highestHeat, RogueliteMinHeat, RogueliteMaxHeat)
  profile.dataShards = max(0, profile.dataShards)
  profile.cores = max(0, profile.cores)
  profile.sectorsCleared = max(0, profile.sectorsCleared)

# ---------------------------------------------------------------------------
# Legacy unlock-shop refund (v4 -> v5)
#
# Up to v4, boot profiles, power families, relics, Heat tiers and "Wave Surge"
# boss tiers were bought here with shards and cores. v5 makes all of it free
# (Heat is now earned by winning), so a migrating profile gets back exactly
# what it spent. These tables are the v4 prices, kept ONLY for that refund.

proc parseEnumSet[T: enum](j: JsonNode): set[T] =
  ## Parse a JSON array of `$value` symbol names into an enum set, silently
  ## skipping any unknown member.
  result = {}
  # isNil first: callers pass j.getOrDefault(...), which is nil (not an empty
  # array) when the key is absent, and reading .kind off nil segfaults.
  if j.isNil or j.kind != JArray: return
  for item in j:
    try:
      result.incl(parseEnum[T](item.getStr()))
    except ValueError:
      discard

proc legacyStarterKitCost(kit: RogueliteStarterKit): int =
  case kit
  of rskOperator: 0
  of rskBulwark: 45
  of rskArcanist: 85

proc legacyFamilyCost(family: RoguelitePowerFamily): tuple[shards, cores: int] =
  case family
  of rpfCore, rpfShield: (0, 0)
  of rpfArcane: (75, 0)
  of rpfFire, rpfFrost, rpfPoison: (120, 0)
  of rpfLightning, rpfWind: (190, 2)
  of rpfBlood: (280, 9)

proc legacyRelicCost(relic: RogueliteRelicType): tuple[shards, cores: int] =
  case relic
  of rrtShardMagnet: (55, 0)
  of rrtDraftCache: (90, 0)
  of rrtEmergencyPatch: (140, 1)
  of rrtEliteDividend: (260, 8)
  else: (0, 0)   # Discount Protocol was free; later patches were never sold

proc legacyUnlockRefund*(j: JsonNode): tuple[shards, cores: int] =
  ## Everything a v4 profile JSON spent in the old unlock shop.
  if j.isNil or j.kind != JObject:
    return
  for kit in parseEnumSet[RogueliteStarterKit](j.getOrDefault("unlockedStarterKits")):
    result.shards += legacyStarterKitCost(kit)
  for family in parseEnumSet[RoguelitePowerFamily](j.getOrDefault("unlockedPowerFamilies")):
    let c = legacyFamilyCost(family)
    result.shards += c.shards
    result.cores += c.cores
  for relic in parseEnumSet[RogueliteRelicType](j.getOrDefault("unlockedRelics")):
    let c = legacyRelicCost(relic)
    result.shards += c.shards
    result.cores += c.cores
  # Heat tiers: Heat 2 cost 130 shards, Heat 3 cost 220 shards + 8 cores.
  let heat = clamp(j.getOrDefault("highestHeat").getInt(RogueliteMinHeat),
                   RogueliteMinHeat, RogueliteMaxHeat)
  if heat >= 2: result.shards += 130
  if heat >= 3:
    result.shards += 220
    result.cores += 8
  # "Wave Surge" boss tiers: tier 2 cost 150 shards, tier 3 cost 270 + 6 cores.
  let tier = clamp(j.getOrDefault("unlockedBossTier").getInt(1), 1, 3)
  if tier >= 2: result.shards += 150
  if tier >= 3:
    result.shards += 270
    result.cores += 6

# ---------------------------------------------------------------------------
# Profile persistence

proc stringSeqToJson(values: seq[string]): JsonNode =
  result = newJArray()
  for value in values:
    if value.len > 0:
      result.add(%value)

proc parseStringSeq(j: JsonNode): seq[string] =
  result = @[]
  if j.kind != JArray: return
  for item in j:
    let value = item.getStr()
    if value.len > 0 and value notin result:
      result.add(value)

proc rogueliteProfileToJson*(profile: RogueliteProfile): JsonNode =
  %* {
    "version": profile.version,
    "dataShards": profile.dataShards,
    "cores": profile.cores,
    "unlockedPlayerSkins": stringSeqToJson(profile.unlockedPlayerSkins),
    "unlockedBulletSkins": stringSeqToJson(profile.unlockedBulletSkins),
    "unlockedPlayerShapes": stringSeqToJson(profile.unlockedPlayerShapes),
    "unlockedBulletShapes": stringSeqToJson(profile.unlockedBulletShapes),
    "unlockedParticleSkins": stringSeqToJson(profile.unlockedParticleSkins),
    "unlockedDesktopBgs": stringSeqToJson(profile.unlockedDesktopBgs),
    "unlockedCubeSkins": stringSeqToJson(profile.unlockedCubeSkins),
    "highestHeat": profile.highestHeat,
    "sectorsCleared": profile.sectorsCleared,
    "bestFloor": profile.bestFloor,
    "bestRooms": profile.bestRooms,
    "bestEndlessLoop": profile.bestEndlessLoop,
    "totalRuns": profile.totalRuns,
    "wins": profile.wins,
    "recursionDamageBonus": profile.recursionDamageBonus,
    "recursionLevel": profile.recursionLevel
  }

proc jsonToRogueliteProfile*(j: JsonNode): RogueliteProfile =
  ## Parse a profile. A pre-v5 profile is migrated in place: its unlock-shop
  ## spend is credited back and recorded in pendingProfileRefund. The caller
  ## (loadRogueliteProfile) saves right away so the refund can't repeat.
  result = initRogueliteProfile()
  if j.kind != JObject:
    return

  let storedVersion = j.getOrDefault("version").getInt(0)
  result.dataShards = j.getOrDefault("dataShards").getInt(result.dataShards)
  if j.hasKey("cores"):
    result.cores = j["cores"].getInt(result.cores)
  else:
    # v3 -> v4 migration: merge the two old rare currencies into cores
    # (singularity cores were ~4x rarer than overheat cores).
    result.cores = j.getOrDefault("overheatCores").getInt(0) +
                   4 * j.getOrDefault("singularityCores").getInt(0)
  if j.hasKey("unlockedPlayerSkins"):
    result.unlockedPlayerSkins = parseStringSeq(j["unlockedPlayerSkins"])
  if j.hasKey("unlockedBulletSkins"):
    result.unlockedBulletSkins = parseStringSeq(j["unlockedBulletSkins"])
  if j.hasKey("unlockedPlayerShapes"):
    result.unlockedPlayerShapes = parseStringSeq(j["unlockedPlayerShapes"])
  if j.hasKey("unlockedBulletShapes"):
    result.unlockedBulletShapes = parseStringSeq(j["unlockedBulletShapes"])
  if j.hasKey("unlockedParticleSkins"):
    result.unlockedParticleSkins = parseStringSeq(j["unlockedParticleSkins"])
  if j.hasKey("unlockedDesktopBgs"):
    result.unlockedDesktopBgs = parseStringSeq(j["unlockedDesktopBgs"])
  if j.hasKey("unlockedCubeSkins"):
    result.unlockedCubeSkins = parseStringSeq(j["unlockedCubeSkins"])
  result.highestHeat = j.getOrDefault("highestHeat").getInt(result.highestHeat)
  result.sectorsCleared = j.getOrDefault("sectorsCleared").getInt(0)
  # v3 profiles stored bestAct/bestSector; floors/rooms are their successors.
  result.bestFloor = j.getOrDefault("bestFloor").getInt(
    j.getOrDefault("bestAct").getInt(result.bestFloor))
  result.bestRooms = j.getOrDefault("bestRooms").getInt(
    j.getOrDefault("bestSector").getInt(result.bestRooms))
  result.bestEndlessLoop = j.getOrDefault("bestEndlessLoop").getInt(result.bestEndlessLoop)
  result.totalRuns = j.getOrDefault("totalRuns").getInt(result.totalRuns)
  result.wins = j.getOrDefault("wins").getInt(result.wins)
  result.recursionDamageBonus = j.getOrDefault("recursionDamageBonus").getFloat(result.recursionDamageBonus).float32
  if j.hasKey("recursionLevel"):
    result.recursionLevel = j["recursionLevel"].getInt(0)
  elif result.recursionDamageBonus > 0.0'f32:
    # Migrate pre-ladder saves: the old model only ever banked level-1 picks
    # (each +recursionDamageBonusForLevel(1)), so the bonus divided by that
    # per-pick amount recovers how many levels were earned.
    let perPick = recursionDamageBonusForLevel(1)
    result.recursionLevel = clamp(int(round(result.recursionDamageBonus / perPick)),
                                  0, getPowerUpMaxLevel(puRecursion))
  if storedVersion < 5:
    # Earn, don't buy. Heat already bought stays unlocked: nobody loses
    # access, and the refund still returns what it cost.
    let refund = legacyUnlockRefund(j)
    result.dataShards += refund.shards
    result.cores += refund.cores
    pendingProfileRefund.shards += refund.shards
    pendingProfileRefund.cores += refund.cores
  normalizeRogueliteProfile(result)

proc loadRogueliteProfile*(): RogueliteProfile =
  try:
    let path = getRogueliteProfilePath()
    if not fileExists(path):
      result = initRogueliteProfile()
      discard saveRogueliteProfile(result)
      return result
    let j = parseJson(readFile(path))
    result = jsonToRogueliteProfile(j)
    # Persist a migration immediately. This loader is called from many places;
    # re-reading an unsaved v4 file would refund it again every time.
    if j.kind == JObject and j.getOrDefault("version").getInt(0) < RogueliteProfileVersion:
      discard saveRogueliteProfile(result)
  except Exception as e:
    echo "Error loading roguelite profile: ", e.msg
    result = initRogueliteProfile()

proc saveRogueliteProfile*(profile: RogueliteProfile): bool =
  try:
    if profile.isNil: return false
    normalizeRogueliteProfile(profile)
    writeFile(getRogueliteProfilePath(), rogueliteProfileToJson(profile).pretty())
    true
  except Exception as e:
    echo "Error saving roguelite profile: ", e.msg
    false

proc resetRogueliteProfile*(profile: RogueliteProfile): bool =
  ## Reset an existing roguelite profile in place so active references stay valid.
  if profile.isNil:
    return false

  let fresh = initRogueliteProfile()
  profile.version = fresh.version
  profile.dataShards = fresh.dataShards
  profile.cores = fresh.cores
  profile.unlockedPlayerSkins = fresh.unlockedPlayerSkins
  profile.unlockedBulletSkins = fresh.unlockedBulletSkins
  profile.unlockedPlayerShapes = fresh.unlockedPlayerShapes
  profile.unlockedBulletShapes = fresh.unlockedBulletShapes
  profile.unlockedParticleSkins = fresh.unlockedParticleSkins
  profile.unlockedDesktopBgs = fresh.unlockedDesktopBgs
  profile.unlockedCubeSkins = fresh.unlockedCubeSkins
  profile.highestHeat = fresh.highestHeat
  profile.sectorsCleared = fresh.sectorsCleared
  profile.bestFloor = fresh.bestFloor
  profile.bestRooms = fresh.bestRooms
  profile.bestEndlessLoop = fresh.bestEndlessLoop
  profile.totalRuns = fresh.totalRuns
  profile.wins = fresh.wins
  profile.recursionDamageBonus = fresh.recursionDamageBonus
  profile.recursionLevel = fresh.recursionLevel
  saveRogueliteProfile(profile)

# ---------------------------------------------------------------------------
# Runs

proc beginRogueliteRun*(game: Game, profile: RogueliteProfile,
                         starterKit: RogueliteStarterKit, heat: int) =
  normalizeRogueliteProfile(profile)
  let maxUnlockedHeat = if profile.isNil: RogueliteMinHeat else: profile.highestHeat
  let clampedHeat = clamp(heat, RogueliteMinHeat, maxUnlockedHeat)
  let heatRank = heatChallengeRank(clampedHeat)
  game.rogueliteProfile = profile
  game.rogueliteRun = RogueliteRun(
    seed: rand(1_000_000_000),
    starterKit: starterKit,
    heat: clampedHeat,
    floorNumber: 1,
    floor: nil,
    totalRoomsCleared: 0,
    usedThemes: {},
    pendingFloorSelect: true,
    relics: @[],
    shardsEarned: 0,
    coresEarned: 0,
    totalShardsBanked: 0,
    totalCoresBanked: 0,
    heatUnlocked: 0,
    endlessLoop: 0,
    completed: false,
    died: false,
    awaitingVictoryScreen: false
  )

  game.currentWave = 1
  game.wavesUntilBoss = 999
  game.waveInProgress = false
  game.waveEnemiesRemaining = 0
  game.player.coins = 0
  game.player.patches = {}
  game.player.patchBlockCharges = 0
  game.player.overclockStallTimer = 0
  game.player.rollbackArmed = false
  game.player.cronJobTimer = 0
  # Roguelite has its own XP curve (see XpRogueliteBase); the fresh player
  # starts on the shared level-1 threshold.
  game.player.xpToNextLevel = xpRequiredForLevel(game.player.rogueliteLevel, gmRoguelite)

  # Run-scoped class emblem worn over the body (0 = none). Distinct from the
  # head-worn secret hats and orbital cube, so it stacks without overlapping.
  game.player.rogueliteCosmetic = ord(starterKit) + 1

  case starterKit
  of rskOperator:
    game.player.coins = 15
  of rskBulwark:
    game.player.coins = 5
    game.player.walls += 3
    applyPowerUp(game.player, PowerUp(powerType: puFortified, level: 1, rarity: prCommon))
  of rskArcanist:
    game.player.coins = 0
    applyPowerUp(game.player, PowerUp(powerType: puArcaneBullets, level: 1, rarity: prCommon))

  game.player.coins += heatRank * 5

  # Permanent cross-run damage earned from every Recursion ever picked up.
  # The player object is freshly built (newGame) with base damage when the
  # roguelite window opens, so this multiplier is applied exactly once per run.
  if not profile.isNil and profile.recursionDamageBonus > 0.0'f32:
    game.player.damage *= (1.0'f32 + profile.recursionDamageBonus)

  # Seed the player's Recursion ladder position so the draft offers the NEXT
  # level (recursionLevel + 1) rather than restarting at level 1. We add the
  # entry directly instead of via applyPowerUp because the damage for these
  # banked levels is already applied above through recursionDamageBonus.
  if not profile.isNil and profile.recursionLevel > 0:
    game.player.powerUps.add(
      PowerUp(powerType: puRecursion, level: profile.recursionLevel, rarity: prCommon))

# ---------------------------------------------------------------------------
# Patches

proc installPatch*(game: Game, patch: RogueliteRelicType): bool =
  ## THE way a patch enters a run: records it on the run (the persisted list),
  ## mirrors it onto the player (what the effect hooks test), and arms any
  ## charge it starts with. False if there is no run or it is already applied.
  ## Feedback (sound, floating text) is the caller's job.
  if game.rogueliteRun.isNil or patch == rrtNone or game.rogueliteRun.hasRelic(patch):
    return false
  game.rogueliteRun.relics.add(makeRelic(patch))
  game.player.patches.incl(patch)
  case patch
  of rrtRollback:
    game.player.rollbackArmed = true
  of rrtFirewallRule:
    game.player.patchBlockCharges = max(game.player.patchBlockCharges, 1)
  of rrtCronJob:
    game.player.cronJobTimer = CronJobInterval
  else:
    discard
  true

proc syncPlayerPatches*(game: Game) =
  ## Rebuild the player's patch mirror from the run (after a checkpoint
  ## restore, which rebuilds the run's relic list from JSON).
  if game.player.isNil: return
  game.player.patches = {}
  if game.rogueliteRun.isNil: return
  for relic in game.rogueliteRun.relics:
    game.player.patches.incl(relic.relicType)

proc unownedPatches*(run: RogueliteRun,
                     exclude: set[RogueliteRelicType] = {}): seq[RogueliteRelicType] =
  for p in AllPatches:
    if p notin exclude and not run.hasRelic(p):
      result.add(p)

proc rollPatchChoices*(run: RogueliteRun, count: int,
                       exclude: set[RogueliteRelicType] = {}): seq[RogueliteRelicType] =
  ## Up to `count` distinct patches this run doesn't have yet. Fewer (possibly
  ## none) once the pool runs dry; callers fall back to another reward.
  var pool = unownedPatches(run, exclude)
  shuffle(pool)
  for i in 0 ..< min(count, pool.len):
    result.add(pool[i])

# ---------------------------------------------------------------------------
# Sector completion

proc awardHeatBossEconomy(game: Game) =
  if game.rogueliteRun.isNil:
    return

  let heatRank = heatChallengeRank(game.rogueliteRun.heat)
  if heatRank <= 0:
    return

  game.rogueliteRun.coresEarned += 2 + heatRank + game.rogueliteRun.endlessLoop * 2
  if heatRank >= 2:
    game.rogueliteRun.coresEarned += 4 * (1 + game.rogueliteRun.endlessLoop)

proc completeRogueliteBoss*(game: Game) =
  ## Sector SERVICE shut down: bank rewards and either advance to the next
  ## sector's theme select or close out a win (and roll into the endless loop).
  if game.rogueliteRun.isNil: return
  let run = game.rogueliteRun
  let heatRank = heatChallengeRank(run.heat)
  let bossShardReward = 50 + run.floorNumber * 16 + heatRank * 20 +
                        run.endlessLoop * 24
  run.shardsEarned += bossShardReward
  awardHeatBossEconomy(game)
  game.player.coins += 25 + run.floorNumber * 8 + heatRank * 7 +
                       run.endlessLoop * 10
  game.wavesUntilBoss = 999

  if not game.cheatsUsed and not game.rogueliteProfile.isNil:
    inc game.rogueliteProfile.sectorsCleared

  if hasPatch(game.player, rrtEmergencyPatch):
    game.player.hp = min(game.player.maxHp,
                         game.player.hp + game.player.maxHp * EmergencyPatchBossHeal)

  # SectorProtocol: bonus coins on floor completion
  if game.player.hasSectorProtocol:
    game.player.coins += 15

  if run.floorNumber >= RogueliteFloorsToWin:
    # Final floor boss down. Bank the win immediately (so a victory is never lost),
    # then hand off to the ending screen instead of silently rolling into the next
    # endless loop. The endless roll is deferred to rogueliteContinueEndless, called
    # only if the player chooses to push deeper rather than cash out.
    run.completed = true
    if not game.cheatsUsed and not game.rogueliteProfile.isNil:  # records feed shard-paying advancements
      let profile = game.rogueliteProfile
      profile.wins += 1
      profile.bestEndlessLoop = max(profile.bestEndlessLoop, run.endlessLoop)
      # Heat is EARNED: winning at your highest Heat unlocks the next one.
      if run.heat >= profile.highestHeat and profile.highestHeat < RogueliteMaxHeat:
        inc profile.highestHeat
        run.heatUnlocked = profile.highestHeat
    discard commitRogueliteRunProgress(game, false)
    # Unlock Survival mode on a legitimate roguelite victory
    if not game.cheatsUsed and not globalSettings.isNil and not globalSettings.survivalUnlocked:
      globalSettings.survivalUnlocked = true
      discard saveSettings(globalSettings)
    run.awaitingVictoryScreen = true
    # pendingFloorSelect stays false: no floor select until the player opts to continue.
  else:
    run.floorNumber += 1
    run.pendingFloorSelect = true
    if not game.rogueliteProfile.isNil:
      discard saveRogueliteProfile(game.rogueliteProfile)

proc rogueliteContinueEndless*(run: RogueliteRun) =
  ## Player chose "Continue" on the ending screen: roll the completed run into the
  ## next endless loop. Mirrors the floor-reset the old completeRogueliteBoss did
  ## inline, now gated behind the victory-screen choice.
  if run.isNil: return
  run.awaitingVictoryScreen = false
  # The win is banked; the run itself goes on. Left set, `completed` makes every
  # later save treat the endless run as finished and delete it, so quitting
  # mid-loop threw the run (and its unbanked shards) away.
  run.completed = false
  run.endlessLoop += 1
  run.floorNumber = 1
  run.usedThemes = {}
  run.pendingFloorSelect = true

proc commitRogueliteRunProgress*(game: Game, died: bool): bool =
  if game.rogueliteProfile.isNil or game.rogueliteRun.isNil:
    return false

  game.rogueliteRun.died = died
  # A run that spent a restore point was already counted when it first died;
  # dying again after the Continue is the same run, not another one.
  if died and game.livesUsed == 0:
    game.rogueliteProfile.totalRuns += 1

  # A cheated run banks nothing: its shards/cores are discarded, and its records
  # are not written either, since they unlock advancements whose claims pay shards.
  if not game.cheatsUsed:
    game.rogueliteProfile.dataShards += game.rogueliteRun.shardsEarned
    game.rogueliteProfile.cores += game.rogueliteRun.coresEarned
    # Running totals survive the zeroing below, so the BSOD / victory screen
    # can still say what this run paid out.
    game.rogueliteRun.totalShardsBanked += game.rogueliteRun.shardsEarned
    game.rogueliteRun.totalCoresBanked += game.rogueliteRun.coresEarned
    game.rogueliteProfile.bestFloor = max(game.rogueliteProfile.bestFloor,
                                          game.rogueliteRun.floorNumber)
    game.rogueliteProfile.bestRooms = max(game.rogueliteProfile.bestRooms,
                                          game.rogueliteRun.totalRoomsCleared)
    game.rogueliteProfile.bestEndlessLoop = max(game.rogueliteProfile.bestEndlessLoop,
                                                game.rogueliteRun.endlessLoop)
  game.rogueliteRun.shardsEarned = 0
  game.rogueliteRun.coresEarned = 0
  saveRogueliteProfile(game.rogueliteProfile)

# Wave / Time Survival meta-currency
#
# Wave and survival runs pay into the same wallet the cosmetic shop spends from.
# Roguelite accrues into its RogueliteRun and banks at run end, but these modes
# have several resume paths (exact snapshot, run-save checkpoint, death-surviving
# block checkpoint), so each reward is banked the moment it is earned instead:
# a crash or quit never loses it, and suspend.nim already treats the profile as
# live state a restore never rolls back.
#
# Rough totals, for tuning against a Heat 1 roguelite win (~700 shards, 0 cores):
#   wave 60 cleared  ~616 shards, ~22 cores
#   20:00 survival   ~600 shards, ~25 cores (4 phase bosses, ~20 System Events,
#                    4 Rogue Processes, the victory bonus and the minute drip)
#   15:00 death      ~330 shards, ~12 cores

const MetaRewardBossTierCap* = 12
  ## The wave-60 boss. Endless waves and long survival runs keep paying this tier.

proc waveClearShardReward*(wave: int): int =
  ## A regular (non-boss) wave cleared: 1 shard early on, 8 by wave 59.
  1 + max(1, wave) div 8

proc bossShardReward*(bossTier: int): int =
  ## Boss N is the same fight in wave and survival mode, so it pays the same:
  ## 12 shards for the first boss, 56 for the final one.
  8 + 4 * clamp(bossTier, 1, MetaRewardBossTierCap)

proc bossCoreReward*(bossTier: int): int =
  ## Cores start at boss 3 (wave 15) and top out at 4.
  clamp(bossTier, 1, MetaRewardBossTierCap) div 3

proc survivalMinuteShardReward*(minute: int): int =
  ## Each whole minute on the survival clock: 2 shards, +1 every third minute.
  2 + max(1, minute) div 3

const
  SurvivalVictoryShards* = 100  ## Beating the 20:00 final boss
  SurvivalVictoryCores* = 5

proc survivalBossTier(bossNumber: int): int =
  ## Survival fights four phase bosses, which are wave bosses 3 / 6 / 9 / 12;
  ## Overtime keeps fighting the final one.
  clamp(bossNumber * 3, 3, MetaRewardBossTierCap)

proc survivalBossShardReward*(bossNumber: int): int =
  ## Survival boss bounty. There are four bosses instead of the thirteen the
  ## old 90 s cadence fought by 20:00, so each pays double its wave-mode tier:
  ## 40 / 64 / 88 / 112, then 84 per Overtime boss.
  if bossNumber > 4: 84
  else: 2 * bossShardReward(survivalBossTier(bossNumber))

proc survivalBossCoreReward*(bossNumber: int): int =
  ## 2 / 4 / 6 / 8 Cores for the phase bosses, 6 per Overtime boss.
  if bossNumber > 4: 6
  else: 2 * bossCoreReward(survivalBossTier(bossNumber))

proc survivalEventShardReward*(phaseIndex: int, rogue: bool): int =
  ## A System Event cleared (3 + 2 per phase) or a Rogue Process killed
  ## (6 + 3 per phase). phaseIndex is 0 for Boot through 4 for Overtime.
  let p = clamp(phaseIndex, 0, 4)
  if rogue: 6 + 3 * p else: 3 + 2 * p

proc bankMetaCurrency*(shards, cores: int): bool =
  ## Credit the live wallet and save it. False when nothing was credited (no
  ## active profile, or nothing to bank).
  let profile = activeRogueliteProfile
  if profile.isNil or (shards <= 0 and cores <= 0):
    return false
  profile.dataShards += max(0, shards)
  profile.cores += max(0, cores)
  if not saveRogueliteProfile(profile):
    echo "Warning: Meta-currency was banked, but the roguelite profile could not be saved."
  true

# Cosmetic unlock economy

type
  CosmeticKind* = enum
    ckPlayerSkin,
    ckBulletSkin,
    ckPlayerShape,
    ckBulletShape,
    ckParticle,
    ckDesktopBg,
    ckCubeSkin

  CosmeticCost* = object
    dataShards*: int
    cores*: int

proc makeCost(dataShards: int, cores: int = 0): CosmeticCost =
  CosmeticCost(
    dataShards: dataShards,
    cores: cores
  )

proc isFree*(cost: CosmeticCost): bool =
  cost.dataShards <= 0 and cost.cores <= 0

proc ensureId(list: var seq[string], id: string) =
  if id.len == 0:
    return
  for existing in list:
    if existing == id:
      return
  list.add(id)

proc hasId(list: seq[string], id: string): bool =
  for existing in list:
    if existing == id:
      return true
  false

const CosmeticInfo: array[CosmeticKind, tuple[count, defaultIndex: int]] = [
  ckPlayerSkin:  (ord(high(SkinType)) + 1,        ord(skDefault)),
  ckBulletSkin:  (ord(high(BulletSkinType)) + 1,  ord(bskDefault)),
  ckPlayerShape: (ord(high(ShapeType)) + 1,       ord(shHexagon)),
  ckBulletShape: (ord(high(BulletShapeType)) + 1, ord(bshCircle)),
  ckParticle:    (ord(high(ParticleSkinType)) + 1, ord(pskDefault)),
  ckDesktopBg:   (ord(high(DesktopBgType)) + 1,   ord(dbgDefault)),
  ckCubeSkin:    (ord(high(CubeSkinType)) + 1,    ord(cskDefault)),
]

proc defaultCosmeticIndex*(kind: CosmeticKind): int = CosmeticInfo[kind].defaultIndex

proc cosmeticCount*(kind: CosmeticKind): int = CosmeticInfo[kind].count

proc isValidCosmeticIndex*(kind: CosmeticKind, index: int): bool =
  index >= 0 and index < cosmeticCount(kind)

proc cosmeticId*(kind: CosmeticKind, index: int): string =
  if not isValidCosmeticIndex(kind, index):
    return ""
  case kind
  of ckPlayerSkin: $SkinType(index)
  of ckBulletSkin: $BulletSkinType(index)
  of ckPlayerShape: $ShapeType(index)
  of ckBulletShape: $BulletShapeType(index)
  of ckParticle: $ParticleSkinType(index)
  of ckDesktopBg: $DesktopBgType(index)
  of ckCubeSkin: $CubeSkinType(index)

proc unlockedList(profile: RogueliteProfile, kind: CosmeticKind): var seq[string] =
  ## Single chokepoint mapping a CosmeticKind to its unlock-id list on the
  ## profile. Returns the field by `var` so the ownership procs below share one
  ## body instead of parallel per-kind cases.
  case kind
  of ckPlayerSkin: return profile.unlockedPlayerSkins
  of ckBulletSkin: return profile.unlockedBulletSkins
  of ckPlayerShape: return profile.unlockedPlayerShapes
  of ckBulletShape: return profile.unlockedBulletShapes
  of ckParticle: return profile.unlockedParticleSkins
  of ckDesktopBg: return profile.unlockedDesktopBgs
  of ckCubeSkin: return profile.unlockedCubeSkins

proc equippedIndex(settings: Settings, kind: CosmeticKind): var int =
  ## Single chokepoint mapping a CosmeticKind to its equipped-index field in
  ## Settings (stored as a plain ordinal). Returned by `var` for read + write.
  case kind
  of ckPlayerSkin: return settings.playerSkin
  of ckBulletSkin: return settings.bulletSkin
  of ckPlayerShape: return settings.playerShape
  of ckBulletShape: return settings.bulletShape
  of ckParticle: return settings.particleEffect
  of ckDesktopBg: return settings.desktopBg
  of ckCubeSkin: return settings.cubeSkin

proc ensureBaseCosmeticUnlocks*(profile: RogueliteProfile) =
  if profile.isNil:
    return
  for kind in CosmeticKind:
    ensureId(unlockedList(profile, kind), cosmeticId(kind, defaultCosmeticIndex(kind)))

proc cosmeticIsUnlocked*(profile: RogueliteProfile, kind: CosmeticKind,
                         index: int): bool =
  if not isValidCosmeticIndex(kind, index):
    return false
  if index == defaultCosmeticIndex(kind):
    return true
  if profile.isNil:
    return false

  hasId(unlockedList(profile, kind), cosmeticId(kind, index))

proc addCosmeticUnlock(profile: RogueliteProfile, kind: CosmeticKind, index: int) =
  if profile.isNil:
    return
  ensureId(unlockedList(profile, kind), cosmeticId(kind, index))

proc cosmeticCost*(kind: CosmeticKind, index: int): CosmeticCost =
  if not isValidCosmeticIndex(kind, index) or index == defaultCosmeticIndex(kind):
    return makeCost(0)

  case kind
  of ckPlayerSkin:
    case SkinType(index)
    of skDefault: makeCost(0)
    of skNeonPink: makeCost(30)
    of skEmerald: makeCost(40)
    of skSunset: makeCost(55)
    of skAmethyst: makeCost(70)
    of skIce: makeCost(85)
    of skGold: makeCost(115, 1)
    of skShadow: makeCost(130, 2)
    of skMatrix: makeCost(165, 3)
    of skRainbow: makeCost(190, 4)
    of skVoid: makeCost(230, 10)
    of skPlasma: makeCost(250, 12)
    of skStars: makeCost(150, 2)
    of skLightning: makeCost(180, 4)
  of ckBulletSkin:
    case BulletSkinType(index)
    of bskDefault: makeCost(0)
    of bskNeonPink: makeCost(22)
    of bskEmerald: makeCost(30)
    of bskSunset: makeCost(40)
    of bskAmethyst: makeCost(54)
    of bskIce: makeCost(68)
    of bskGold: makeCost(90, 1)
    of bskShadow: makeCost(105, 2)
    of bskMatrix: makeCost(125, 2)
    of bskRainbow: makeCost(150, 3)
    of bskVoid: makeCost(190, 9)
    of bskPlasma: makeCost(210, 10)
    of bskStars: makeCost(120, 2)
    of bskLightning: makeCost(150, 3)
  of ckPlayerShape:
    case ShapeType(index)
    of shHexagon: makeCost(0)
    of shTriangle: makeCost(36)
    of shSquare: makeCost(52)
    of shCircle: makeCost(64)
  of ckBulletShape:
    case BulletShapeType(index)
    of bshCircle: makeCost(0)
    of bshTriangle: makeCost(24)
    of bshDiamond: makeCost(42)
    of bshSquare: makeCost(55)
    of bshPentagon: makeCost(80, 1)
    of bshStar: makeCost(135, 3)
  of ckParticle:
    case ParticleSkinType(index)
    of pskDefault: makeCost(0)
    of pskFire: makeCost(45)
    of pskIce: makeCost(48)
    of pskToxic: makeCost(60)
    of pskPlasma: makeCost(95, 1)
    of pskGold: makeCost(105, 1)
    of pskShadow: makeCost(120, 2)
    of pskStars: makeCost(140, 2)
    of pskHearts: makeCost(150, 2)
    of pskLightning: makeCost(175, 4)
    of pskRainbow: makeCost(205, 9)
    of pskVoid: makeCost(240, 11)
    of pskAmethyst: makeCost(58)
    of pskMatrix: makeCost(130, 2)
  of ckDesktopBg:
    case DesktopBgType(index)
    of dbgDefault: makeCost(0)
    of dbgNeon:    makeCost(35)
    of dbgMatrix:  makeCost(50)
    of dbgVoid:    makeCost(70)
    of dbgSunrise: makeCost(90, 1)
    of dbgOcean:   makeCost(110, 1)
    of dbgInferno: makeCost(150, 7)
    of dbgPortal:  makeCost(200, 9)
    of dbgHorror:  makeCost(180, 8)
    of dbgCyber:   makeCost(170, 8)
    of dbgCasino:  makeCost(165, 7)
    of dbgDragon:  makeCost(210, 10)
  of ckCubeSkin:
    case CubeSkinType(index)
    of cskDefault: makeCost(0)
    of cskNeon:    makeCost(28)
    of cskIce:     makeCost(42)
    of cskGold:    makeCost(65, 1)
    of cskShadow:  makeCost(85, 1)
    of cskPlasma:  makeCost(120, 2)
    of cskMatrix:  makeCost(140, 2)
    of cskCompanion: makeCost(155, 3)
    of cskJack:    makeCost(150, 3)
    of cskCyber:   makeCost(135, 2)
    of cskDice:    makeCost(95, 1)
    of cskD20:     makeCost(220, 10)

proc canAffordCosmetic*(profile: RogueliteProfile, kind: CosmeticKind,
                        index: int): bool =
  if profile.isNil or not isValidCosmeticIndex(kind, index):
    return false
  if cosmeticIsUnlocked(profile, kind, index):
    return false
  let cost = cosmeticCost(kind, index)
  not cost.isFree and
    profile.dataShards >= cost.dataShards and
    profile.cores >= cost.cores

proc purchaseCosmetic*(profile: RogueliteProfile, kind: CosmeticKind,
                       index: int): bool =
  if profile.isNil or not isValidCosmeticIndex(kind, index):
    return false
  ensureBaseCosmeticUnlocks(profile)
  if cosmeticIsUnlocked(profile, kind, index):
    return true
  if not canAffordCosmetic(profile, kind, index):
    return false

  let cost = cosmeticCost(kind, index)
  profile.dataShards -= cost.dataShards
  profile.cores -= cost.cores
  addCosmeticUnlock(profile, kind, index)
  if not saveRogueliteProfile(profile):
    echo "Warning: Cosmetic unlock was applied, but the roguelite profile could not be saved."
  true

# Cosmetic pack bundles
#
# A pack is a curated theme "trio" -- one player skin + one bullet skin + one
# particle effect -- sold together at a markdown vs buying each member solo.
# Packs add NO new persisted state: buying one just unlocks its members through
# the same per-kind unlock lists that `purchaseCosmetic` uses. A pack counts as
# owned once every member is unlocked, and it only ever charges for the members
# the player does not already own (still discounted), so partial owners are
# never double-charged.

const PackDiscount* = 0.6'f32   # pay 60% of retail -> a 40% markdown

type
  CosmeticPackId* = enum
    cpGold, cpIce, cpShadow, cpRainbow, cpVoid, cpPlasma,
    cpSunset, cpEmerald, cpNeonPink, cpAmethyst, cpMatrix, cpStars, cpLightning

  CosmeticPackMember* = tuple[kind: CosmeticKind, index: int]

  CosmeticPack* = object
    id*: CosmeticPackId
    nameKey*: string                  # localization key, resolved via t() at draw time
    descKey*: string
    accent*: tuple[r, g, b: uint8]     # card theming colour
    members*: seq[CosmeticPackMember]

const allCosmeticPacks*: array[CosmeticPackId, CosmeticPack] = [
  cpGold: CosmeticPack(id: cpGold, nameKey: "pack_gold", descKey: "pack_gold_desc",
    accent: (255'u8, 215'u8, 0'u8),
    members: @[(ckPlayerSkin, ord(skGold)), (ckBulletSkin, ord(bskGold)), (ckParticle, ord(pskGold))]),
  cpIce: CosmeticPack(id: cpIce, nameKey: "pack_ice", descKey: "pack_ice_desc",
    accent: (150'u8, 220'u8, 255'u8),
    members: @[(ckPlayerSkin, ord(skIce)), (ckBulletSkin, ord(bskIce)), (ckParticle, ord(pskIce))]),
  cpShadow: CosmeticPack(id: cpShadow, nameKey: "pack_shadow", descKey: "pack_shadow_desc",
    accent: (120'u8, 120'u8, 150'u8),
    members: @[(ckPlayerSkin, ord(skShadow)), (ckBulletSkin, ord(bskShadow)), (ckParticle, ord(pskShadow))]),
  cpRainbow: CosmeticPack(id: cpRainbow, nameKey: "pack_rainbow", descKey: "pack_rainbow_desc",
    accent: (255'u8, 80'u8, 180'u8),
    members: @[(ckPlayerSkin, ord(skRainbow)), (ckBulletSkin, ord(bskRainbow)), (ckParticle, ord(pskRainbow))]),
  cpVoid: CosmeticPack(id: cpVoid, nameKey: "pack_void", descKey: "pack_void_desc",
    accent: (130'u8, 70'u8, 190'u8),
    members: @[(ckPlayerSkin, ord(skVoid)), (ckBulletSkin, ord(bskVoid)), (ckParticle, ord(pskVoid))]),
  cpPlasma: CosmeticPack(id: cpPlasma, nameKey: "pack_plasma", descKey: "pack_plasma_desc",
    accent: (150'u8, 120'u8, 255'u8),
    members: @[(ckPlayerSkin, ord(skPlasma)), (ckBulletSkin, ord(bskPlasma)), (ckParticle, ord(pskPlasma))]),
  cpSunset: CosmeticPack(id: cpSunset, nameKey: "pack_sunset", descKey: "pack_sunset_desc",
    accent: (255'u8, 120'u8, 20'u8),
    members: @[(ckPlayerSkin, ord(skSunset)), (ckBulletSkin, ord(bskSunset)), (ckParticle, ord(pskFire))]),
  cpEmerald: CosmeticPack(id: cpEmerald, nameKey: "pack_emerald", descKey: "pack_emerald_desc",
    accent: (0'u8, 220'u8, 110'u8),
    members: @[(ckPlayerSkin, ord(skEmerald)), (ckBulletSkin, ord(bskEmerald)), (ckParticle, ord(pskToxic))]),
  cpNeonPink: CosmeticPack(id: cpNeonPink, nameKey: "pack_neon_pink", descKey: "pack_neon_pink_desc",
    accent: (255'u8, 60'u8, 180'u8),
    members: @[(ckPlayerSkin, ord(skNeonPink)), (ckBulletSkin, ord(bskNeonPink)), (ckParticle, ord(pskHearts))]),
  cpAmethyst: CosmeticPack(id: cpAmethyst, nameKey: "pack_amethyst", descKey: "pack_amethyst_desc",
    accent: (170'u8, 80'u8, 255'u8),
    members: @[(ckPlayerSkin, ord(skAmethyst)), (ckBulletSkin, ord(bskAmethyst)), (ckParticle, ord(pskAmethyst))]),
  cpMatrix: CosmeticPack(id: cpMatrix, nameKey: "pack_matrix", descKey: "pack_matrix_desc",
    accent: (0'u8, 230'u8, 70'u8),
    members: @[(ckPlayerSkin, ord(skMatrix)), (ckBulletSkin, ord(bskMatrix)), (ckParticle, ord(pskMatrix))]),
  cpStars: CosmeticPack(id: cpStars, nameKey: "pack_stars", descKey: "pack_stars_desc",
    accent: (255'u8, 225'u8, 120'u8),
    members: @[(ckPlayerSkin, ord(skStars)), (ckBulletSkin, ord(bskStars)), (ckParticle, ord(pskStars))]),
  cpLightning: CosmeticPack(id: cpLightning, nameKey: "pack_lightning", descKey: "pack_lightning_desc",
    accent: (120'u8, 190'u8, 255'u8),
    members: @[(ckPlayerSkin, ord(skLightning)), (ckBulletSkin, ord(bskLightning)), (ckParticle, ord(pskLightning))]),
]

proc packMembers*(id: CosmeticPackId): seq[CosmeticPackMember] =
  allCosmeticPacks[id].members

proc packMemberCount*(id: CosmeticPackId): int =
  allCosmeticPacks[id].members.len

proc applyDiscount(cost: CosmeticCost, factor: float32): CosmeticCost =
  makeCost(max(0, int(round(cost.dataShards.float32 * factor))),
           max(0, int(round(cost.cores.float32 * factor))))

proc packFullRetail*(id: CosmeticPackId): CosmeticCost =
  ## Sum of every member's individual price (the struck-through "before" price).
  for m in allCosmeticPacks[id].members:
    let c = cosmeticCost(m.kind, m.index)
    result.dataShards += c.dataShards
    result.cores += c.cores

proc packUnownedRetail*(profile: RogueliteProfile, id: CosmeticPackId): CosmeticCost =
  ## Retail sum of only the members the player does not yet own.
  for m in allCosmeticPacks[id].members:
    if not cosmeticIsUnlocked(profile, m.kind, m.index):
      let c = cosmeticCost(m.kind, m.index)
      result.dataShards += c.dataShards
      result.cores += c.cores

proc packPrice*(profile: RogueliteProfile, id: CosmeticPackId): CosmeticCost =
  ## What the player pays right now: discounted price of the unowned members.
  applyDiscount(packUnownedRetail(profile, id), PackDiscount)

proc packOwnedCount*(profile: RogueliteProfile, id: CosmeticPackId): int =
  for m in allCosmeticPacks[id].members:
    if cosmeticIsUnlocked(profile, m.kind, m.index): inc result

proc packIsOwned*(profile: RogueliteProfile, id: CosmeticPackId): bool =
  packOwnedCount(profile, id) >= allCosmeticPacks[id].members.len

proc canAffordPack*(profile: RogueliteProfile, id: CosmeticPackId): bool =
  if profile.isNil or packIsOwned(profile, id):
    return false
  let price = packPrice(profile, id)
  profile.dataShards >= price.dataShards and profile.cores >= price.cores

proc purchasePack*(profile: RogueliteProfile, id: CosmeticPackId): bool =
  ## Buy every not-yet-owned member of the pack at the discounted price in one
  ## transaction: deduct once, unlock all, save once. False if already fully
  ## owned or unaffordable.
  if profile.isNil:
    return false
  ensureBaseCosmeticUnlocks(profile)
  if packIsOwned(profile, id):
    return false
  if not canAffordPack(profile, id):
    return false

  let price = packPrice(profile, id)
  profile.dataShards -= price.dataShards
  profile.cores -= price.cores
  for m in allCosmeticPacks[id].members:
    if not cosmeticIsUnlocked(profile, m.kind, m.index):
      addCosmeticUnlock(profile, m.kind, m.index)
  if not saveRogueliteProfile(profile):
    echo "Warning: Cosmetic pack unlock was applied, but the roguelite profile could not be saved."
  true

proc sanitizeEquippedCosmetics*(settings: Settings,
                                profile: RogueliteProfile): bool =
  if settings.isNil:
    return false
  ensureBaseCosmeticUnlocks(profile)

  for kind in CosmeticKind:
    let idx = equippedIndex(settings, kind)
    if not isValidCosmeticIndex(kind, idx) or
       not cosmeticIsUnlocked(profile, kind, idx):
      equippedIndex(settings, kind) = defaultCosmeticIndex(kind)
      result = true

  if settings.kernelTophatEquipped and settings.cheaterHatEquipped:
    settings.cheaterHatEquipped = false
    result = true
