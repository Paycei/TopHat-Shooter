import json, os, random, strutils
import types, settings, save_system, powerup, skins, bullet_skins, bullet_shapes, shapes, particle_skins, desktop_bg_skins, cube_skins, anticheat

const
  RogueliteProfileVersion* = 4
  RogueliteFloorsToWin* = 4
  RogueliteMinHeat* = 1
  RogueliteMaxHeat* = 3
  RogueliteMaxBossTier* = 3
  RogueliteHeatRosterWaveOffset* = 1
  RogueliteHeatDifficultyPerTier* = 0.18'f32
  RogueliteHeatBossDifficultyPerTier* = 0.35'f32
  RogueliteHeatSpawnBurstPerTier* = 0.025'f32
  RogueliteHeatSpawnRatePerTier* = 0.035'f32

type
  RogueliteUnlockCategory* = enum
    rucStarterKits,
    rucPowerFamilies,
    rucRelics,
    rucChallengeTiers

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
    unlockedStarterKits: {rskOperator},
    unlockedPowerFamilies: {rpfCore, rpfShield},
    unlockedRelics: {rrtDiscountProtocol},
    unlockedPlayerSkins: @["skDefault"],
    unlockedBulletSkins: @["bskDefault"],
    unlockedPlayerShapes: @["shHexagon"],
    unlockedBulletShapes: @["bshCircle"],
    unlockedParticleSkins: @["pskDefault"],
    unlockedDesktopBgs: @["dbgDefault"],
    unlockedCubeSkins: @["cskDefault"],
    unlockedBossTier: 1,
    highestHeat: RogueliteMinHeat,
    bestFloor: 1,
    bestRooms: 0,
    bestEndlessLoop: 0,
    totalRuns: 0,
    wins: 0
  )

proc starterName*(kit: RogueliteStarterKit): string =
  case kit
  of rskOperator: "Operator"
  of rskBulwark: "Bulwark"
  of rskArcanist: "Arcanist"

proc starterDescription*(kit: RogueliteStarterKit): string =
  case kit
  of rskOperator: "Start with 15 credits and no preset power-up."
  of rskBulwark: "Start with 5 credits, +3 walls, and Fortified armor."
  of rskArcanist: "Start with Arcane Bullets installed and no credits."

proc familyName*(family: RoguelitePowerFamily): string =
  case family
  of rpfCore: "Core"
  of rpfShield: "Shield"
  of rpfArcane: "Arcane"
  of rpfFire: "Fire"
  of rpfFrost: "Frost"
  of rpfPoison: "Poison"
  of rpfLightning: "Lightning"
  of rpfWind: "Wind"
  of rpfBlood: "Blood"

proc relicName*(relic: RogueliteRelicType): string =
  case relic
  of rrtNone: "None"
  of rrtDiscountProtocol: "Discount Protocol"
  of rrtShardMagnet: "Shard Magnet"
  of rrtEliteDividend: "Elite Dividend"
  of rrtEmergencyPatch: "Emergency Patch"
  of rrtDraftCache: "Draft Cache"

proc relicDescription*(relic: RogueliteRelicType): string =
  case relic
  of rrtNone: "No active relic."
  of rrtDiscountProtocol: "Rerolls cost 20% less, never below 5 credits."
  of rrtShardMagnet: "Shards from cleared rooms are increased by 25%."
  of rrtEliteDividend: "Elite rooms grant +30 credits and bonus shards."
  of rrtEmergencyPatch: "Floor bosses heal 2 HP and grant +1 shield charge."
  of rrtDraftCache: "Rerolls cost 10 fewer credits after other discounts."

proc makeRelic*(relicType: RogueliteRelicType): RogueliteRelic =
  RogueliteRelic(
    relicType: relicType,
    name: relicName(relicType),
    description: relicDescription(relicType)
  )

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

proc refreshRogueliteUnlocks*(profile: RogueliteProfile) =
  if profile.isNil: return
  profile.version = RogueliteProfileVersion
  profile.unlockedStarterKits.incl(rskOperator)
  profile.unlockedPowerFamilies.incl(rpfCore)
  profile.unlockedPowerFamilies.incl(rpfShield)
  profile.unlockedRelics.incl(rrtDiscountProtocol)
  ensureString(profile.unlockedPlayerSkins, "skDefault")
  ensureString(profile.unlockedBulletSkins, "bskDefault")
  ensureString(profile.unlockedPlayerShapes, "shHexagon")
  ensureString(profile.unlockedBulletShapes, "bshCircle")
  ensureString(profile.unlockedParticleSkins, "pskDefault")
  ensureString(profile.unlockedDesktopBgs, "dbgDefault")
  ensureString(profile.unlockedCubeSkins, "cskDefault")
  profile.unlockedBossTier = clamp(profile.unlockedBossTier, 1, RogueliteMaxBossTier)
  profile.highestHeat = clamp(profile.highestHeat, RogueliteMinHeat, RogueliteMaxHeat)
  profile.dataShards = max(0, profile.dataShards)
  profile.cores = max(0, profile.cores)

proc starterKitCost*(kit: RogueliteStarterKit): int =
  case kit
  of rskOperator: 0
  of rskBulwark: 45
  of rskArcanist: 85

proc powerFamilyCost*(family: RoguelitePowerFamily): int =
  case family
  of rpfCore, rpfShield: 0
  of rpfArcane: 75
  of rpfFire, rpfFrost, rpfPoison: 120
  of rpfLightning, rpfWind: 190
  of rpfBlood: 280

proc relicCost*(relicType: RogueliteRelicType): int =
  case relicType
  of rrtNone: 0
  of rrtDiscountProtocol: 0
  of rrtShardMagnet: 55
  of rrtDraftCache: 90
  of rrtEmergencyPatch: 140
  of rrtEliteDividend: 260

proc heatTierCost*(nextHeat: int): int =
  ## Heat 2 needs a couple of Heat 1 runs to afford.
  ## Heat 3 is intentionally steep on shards AND requires Overheat Cores,
  ## which only drop on Heat 2+, enforcing the H1 -> H2 -> H3 ladder.
  case nextHeat
  of 2: 130
  of 3: 220
  else: 0

proc bossTierCost*(nextTier: int): int =
  case nextTier
  of 2: 150
  of 3: 270
  else: 0

proc unlockCount*(category: RogueliteUnlockCategory): int =
  case category
  of rucStarterKits: 3
  of rucPowerFamilies: 9
  of rucRelics: 5
  of rucChallengeTiers: 2

proc starterByUnlockIndex*(index: int): RogueliteStarterKit =
  case clamp(index, 0, 2)
  of 0: rskOperator
  of 1: rskBulwark
  else: rskArcanist

proc familyByUnlockIndex*(index: int): RoguelitePowerFamily =
  case clamp(index, 0, 8)
  of 0: rpfCore
  of 1: rpfShield
  of 2: rpfArcane
  of 3: rpfFire
  of 4: rpfFrost
  of 5: rpfPoison
  of 6: rpfLightning
  of 7: rpfWind
  else: rpfBlood

proc relicByUnlockIndex*(index: int): RogueliteRelicType =
  case clamp(index, 0, 4)
  of 0: rrtDiscountProtocol
  of 1: rrtShardMagnet
  of 2: rrtDraftCache
  of 3: rrtEmergencyPatch
  else: rrtEliteDividend

proc isUnlockPurchased*(profile: RogueliteProfile, category: RogueliteUnlockCategory, index: int): bool =
  if profile.isNil: return false
  case category
  of rucStarterKits:
    starterByUnlockIndex(index) in profile.unlockedStarterKits
  of rucPowerFamilies:
    familyByUnlockIndex(index) in profile.unlockedPowerFamilies
  of rucRelics:
    relicByUnlockIndex(index) in profile.unlockedRelics
  of rucChallengeTiers:
    if index == 0: profile.highestHeat >= RogueliteMaxHeat
    else: profile.unlockedBossTier >= RogueliteMaxBossTier

proc unlockCost*(profile: RogueliteProfile, category: RogueliteUnlockCategory, index: int): int =
  case category
  of rucStarterKits:
    starterKitCost(starterByUnlockIndex(index))
  of rucPowerFamilies:
    powerFamilyCost(familyByUnlockIndex(index))
  of rucRelics:
    relicCost(relicByUnlockIndex(index))
  of rucChallengeTiers:
    if profile.isNil: 0
    elif index == 0: heatTierCost(profile.highestHeat + 1)
    else: bossTierCost(profile.unlockedBossTier + 1)

proc unlockCoreCost*(profile: RogueliteProfile, category: RogueliteUnlockCategory, index: int): int =
  ## Rare-currency cost (cores only drop on Heat 2+, enforcing the
  ## H1 -> H2 -> H3 ladder for the unlocks that demand them).
  case category
  of rucPowerFamilies:
    case familyByUnlockIndex(index)
    of rpfLightning, rpfWind: 2
    of rpfBlood: 9
    else: 0
  of rucRelics:
    case relicByUnlockIndex(index)
    of rrtEmergencyPatch: 1
    of rrtEliteDividend: 8
    else: 0
  of rucChallengeTiers:
    if profile.isNil:
      0
    elif index == 0:
      if profile.highestHeat + 1 >= RogueliteMaxHeat: 8 else: 0
    else:
      if profile.unlockedBossTier + 1 >= RogueliteMaxBossTier: 6 else: 0
  else:
    0

proc canPurchaseUnlock*(profile: RogueliteProfile, category: RogueliteUnlockCategory, index: int): bool =
  if profile.isNil or isUnlockPurchased(profile, category, index):
    return false
  let cost = unlockCost(profile, category, index)
  let coreCost = unlockCoreCost(profile, category, index)
  (cost > 0 or coreCost > 0) and
    profile.dataShards >= cost and
    profile.cores >= coreCost

proc purchaseRogueliteUnlock*(profile: RogueliteProfile, category: RogueliteUnlockCategory, index: int): bool =
  if not canPurchaseUnlock(profile, category, index):
    return false

  let cost = unlockCost(profile, category, index)
  let coreCost = unlockCoreCost(profile, category, index)
  profile.dataShards -= cost
  profile.cores -= coreCost
  case category
  of rucStarterKits:
    profile.unlockedStarterKits.incl(starterByUnlockIndex(index))
  of rucPowerFamilies:
    profile.unlockedPowerFamilies.incl(familyByUnlockIndex(index))
  of rucRelics:
    profile.unlockedRelics.incl(relicByUnlockIndex(index))
  of rucChallengeTiers:
    if index == 0:
      profile.highestHeat = min(RogueliteMaxHeat, profile.highestHeat + 1)
    else:
      profile.unlockedBossTier = min(RogueliteMaxBossTier, profile.unlockedBossTier + 1)
  if not saveRogueliteProfile(profile):
    echo "Warning: Roguelite unlock was applied, but the profile could not be saved."
  true

proc starterSetToJson(s: set[RogueliteStarterKit]): JsonNode =
  result = newJArray()
  for value in RogueliteStarterKit:
    if value in s:
      result.add(%($value))

proc familySetToJson(s: set[RoguelitePowerFamily]): JsonNode =
  result = newJArray()
  for value in RoguelitePowerFamily:
    if value in s:
      result.add(%($value))

proc relicSetToJson(s: set[RogueliteRelicType]): JsonNode =
  result = newJArray()
  for value in RogueliteRelicType:
    if value in s and value != rrtNone:
      result.add(%($value))

proc parseStarterSet(j: JsonNode): set[RogueliteStarterKit] =
  result = {}
  if j.kind != JArray: return
  for item in j:
    try:
      result.incl(parseEnum[RogueliteStarterKit](item.getStr()))
    except ValueError:
      discard

proc parseFamilySet(j: JsonNode): set[RoguelitePowerFamily] =
  result = {}
  if j.kind != JArray: return
  for item in j:
    try:
      result.incl(parseEnum[RoguelitePowerFamily](item.getStr()))
    except ValueError:
      discard

proc parseRelicSet(j: JsonNode): set[RogueliteRelicType] =
  result = {}
  if j.kind != JArray: return
  for item in j:
    try:
      result.incl(parseEnum[RogueliteRelicType](item.getStr()))
    except ValueError:
      discard

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
    "unlockedStarterKits": starterSetToJson(profile.unlockedStarterKits),
    "unlockedPowerFamilies": familySetToJson(profile.unlockedPowerFamilies),
    "unlockedRelics": relicSetToJson(profile.unlockedRelics),
    "unlockedPlayerSkins": stringSeqToJson(profile.unlockedPlayerSkins),
    "unlockedBulletSkins": stringSeqToJson(profile.unlockedBulletSkins),
    "unlockedPlayerShapes": stringSeqToJson(profile.unlockedPlayerShapes),
    "unlockedBulletShapes": stringSeqToJson(profile.unlockedBulletShapes),
    "unlockedParticleSkins": stringSeqToJson(profile.unlockedParticleSkins),
    "unlockedDesktopBgs": stringSeqToJson(profile.unlockedDesktopBgs),
    "unlockedCubeSkins": stringSeqToJson(profile.unlockedCubeSkins),
    "unlockedBossTier": profile.unlockedBossTier,
    "highestHeat": profile.highestHeat,
    "bestFloor": profile.bestFloor,
    "bestRooms": profile.bestRooms,
    "bestEndlessLoop": profile.bestEndlessLoop,
    "totalRuns": profile.totalRuns,
    "wins": profile.wins
  }

proc jsonToRogueliteProfile*(j: JsonNode): RogueliteProfile =
  result = initRogueliteProfile()
  if j.kind != JObject:
    return

  result.version = j.getOrDefault("version").getInt(0)
  result.dataShards = j.getOrDefault("dataShards").getInt(result.dataShards)
  if j.hasKey("cores"):
    result.cores = j["cores"].getInt(result.cores)
  else:
    # v3 -> v4 migration: merge the two old rare currencies into cores
    # (singularity cores were ~4x rarer than overheat cores).
    result.cores = j.getOrDefault("overheatCores").getInt(0) +
                   4 * j.getOrDefault("singularityCores").getInt(0)
  let kits = parseStarterSet(j.getOrDefault("unlockedStarterKits"))
  if kits != {}: result.unlockedStarterKits = kits
  let families = parseFamilySet(j.getOrDefault("unlockedPowerFamilies"))
  if families != {}: result.unlockedPowerFamilies = families
  let relics = parseRelicSet(j.getOrDefault("unlockedRelics"))
  if relics != {}: result.unlockedRelics = relics
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
  result.unlockedBossTier = j.getOrDefault("unlockedBossTier").getInt(result.unlockedBossTier)
  result.highestHeat = j.getOrDefault("highestHeat").getInt(result.highestHeat)
  # v3 profiles stored bestAct/bestSector; floors/rooms are their successors.
  result.bestFloor = j.getOrDefault("bestFloor").getInt(
    j.getOrDefault("bestAct").getInt(result.bestFloor))
  result.bestRooms = j.getOrDefault("bestRooms").getInt(
    j.getOrDefault("bestSector").getInt(result.bestRooms))
  result.bestEndlessLoop = j.getOrDefault("bestEndlessLoop").getInt(result.bestEndlessLoop)
  result.totalRuns = j.getOrDefault("totalRuns").getInt(result.totalRuns)
  result.wins = j.getOrDefault("wins").getInt(result.wins)
  refreshRogueliteUnlocks(result)

proc loadRogueliteProfile*(): RogueliteProfile =
  try:
    let path = getRogueliteProfilePath()
    if not fileExists(path):
      result = initRogueliteProfile()
      discard saveRogueliteProfile(result)
      return result
    result = jsonToRogueliteProfile(parseJson(readFile(path)))
  except Exception as e:
    echo "Error loading roguelite profile: ", e.msg
    result = initRogueliteProfile()

proc saveRogueliteProfile*(profile: RogueliteProfile): bool =
  try:
    if profile.isNil: return false
    refreshRogueliteUnlocks(profile)
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
  profile.unlockedStarterKits = fresh.unlockedStarterKits
  profile.unlockedPowerFamilies = fresh.unlockedPowerFamilies
  profile.unlockedRelics = fresh.unlockedRelics
  profile.unlockedPlayerSkins = fresh.unlockedPlayerSkins
  profile.unlockedBulletSkins = fresh.unlockedBulletSkins
  profile.unlockedPlayerShapes = fresh.unlockedPlayerShapes
  profile.unlockedBulletShapes = fresh.unlockedBulletShapes
  profile.unlockedParticleSkins = fresh.unlockedParticleSkins
  profile.unlockedDesktopBgs = fresh.unlockedDesktopBgs
  profile.unlockedCubeSkins = fresh.unlockedCubeSkins
  profile.unlockedBossTier = fresh.unlockedBossTier
  profile.highestHeat = fresh.highestHeat
  profile.bestFloor = fresh.bestFloor
  profile.bestRooms = fresh.bestRooms
  profile.bestEndlessLoop = fresh.bestEndlessLoop
  profile.totalRuns = fresh.totalRuns
  profile.wins = fresh.wins
  saveRogueliteProfile(profile)

proc beginRogueliteRun*(game: Game, profile: RogueliteProfile,
                         starterKit: RogueliteStarterKit, heat: int) =
  refreshRogueliteUnlocks(profile)
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
    keys: 0,
    combatRoomsSinceDraft: 0,
    usedThemes: {},
    pendingFloorSelect: true,
    relics: @[],
    shardsEarned: 0,
    coresEarned: 0,
    endlessLoop: 0,
    completed: false,
    died: false
  )

  game.currentWave = 1
  game.wavesUntilBoss = 999
  game.waveInProgress = false
  game.waveEnemiesRemaining = 0
  game.player.coins = 0

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

const RogueliteRelicRewardOrder = [rrtDiscountProtocol, rrtShardMagnet, rrtEliteDividend,
                                   rrtEmergencyPatch, rrtDraftCache]

proc grantNextUnlockedRelic*(game: Game): bool =
  if game.rogueliteRun.isNil or game.rogueliteProfile.isNil:
    return false

  for relicType in RogueliteRelicRewardOrder:
    if relicType in game.rogueliteProfile.unlockedRelics and
       not game.rogueliteRun.hasRelic(relicType):
      game.rogueliteRun.relics.add(makeRelic(relicType))
      return true
  false

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
  ## Floor boss defeated: bank rewards and either advance to the next floor's
  ## theme select or close out a win (and roll into the endless loop).
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

  discard grantNextUnlockedRelic(game)

  if run.hasRelic(rrtEmergencyPatch):
    game.player.hp = min(game.player.maxHp, game.player.hp + 2.0)
    game.player.shieldHits += 1

  if run.floorNumber >= RogueliteFloorsToWin:
    run.completed = true
    game.rogueliteProfile.wins += 1
    game.rogueliteProfile.bestEndlessLoop = max(game.rogueliteProfile.bestEndlessLoop,
                                                run.endlessLoop)
    discard commitRogueliteRunProgress(game, false)
    # Unlock Survival mode on a legitimate roguelite victory
    if runIsLegit(game) and not globalSettings.isNil and not globalSettings.survivalUnlocked:
      globalSettings.survivalUnlocked = true
      discard saveSettings(globalSettings)
    run.endlessLoop += 1
    run.floorNumber = 1
    run.usedThemes = {}
  else:
    run.floorNumber += 1

  run.pendingFloorSelect = true

proc commitRogueliteRunProgress*(game: Game, died: bool): bool =
  if game.rogueliteProfile.isNil or game.rogueliteRun.isNil:
    return false

  game.rogueliteRun.died = died
  if died:
    game.rogueliteProfile.totalRuns += 1

  game.rogueliteProfile.dataShards += game.rogueliteRun.shardsEarned
  game.rogueliteProfile.cores += game.rogueliteRun.coresEarned
  game.rogueliteProfile.bestFloor = max(game.rogueliteProfile.bestFloor,
                                        game.rogueliteRun.floorNumber)
  game.rogueliteProfile.bestRooms = max(game.rogueliteProfile.bestRooms,
                                        game.rogueliteRun.totalRoomsCleared)
  game.rogueliteProfile.bestEndlessLoop = max(game.rogueliteProfile.bestEndlessLoop,
                                              game.rogueliteRun.endlessLoop)
  game.rogueliteRun.shardsEarned = 0
  game.rogueliteRun.coresEarned = 0
  refreshRogueliteUnlocks(game.rogueliteProfile)
  saveRogueliteProfile(game.rogueliteProfile)

proc unlockedFamilySet*(profile: RogueliteProfile): set[RoguelitePowerFamily] =
  if profile.isNil:
    {rpfCore, rpfShield}
  else:
    profile.unlockedPowerFamilies

proc rerollDiscountForRelics*(run: RogueliteRun, baseCost: int): int =
  result = baseCost
  if run != nil and run.hasRelic(rrtDiscountProtocol):
    result = max(5, int(result.float32 * 0.8))
  if run != nil and run.hasRelic(rrtDraftCache):
    result = max(5, result - 10)

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

proc defaultCosmeticIndex*(kind: CosmeticKind): int =
  case kind
  of ckPlayerSkin: ord(skDefault)
  of ckBulletSkin: ord(bskDefault)
  of ckPlayerShape: ord(shHexagon)
  of ckBulletShape: ord(bshCircle)
  of ckParticle: ord(pskDefault)
  of ckDesktopBg: ord(dbgDefault)
  of ckCubeSkin: ord(cskDefault)

proc cosmeticCount*(kind: CosmeticKind): int =
  case kind
  of ckPlayerSkin: ord(high(SkinType)) + 1
  of ckBulletSkin: ord(high(BulletSkinType)) + 1
  of ckPlayerShape: ord(high(ShapeType)) + 1
  of ckBulletShape: ord(high(BulletShapeType)) + 1
  of ckParticle: ord(high(ParticleSkinType)) + 1
  of ckDesktopBg: ord(high(DesktopBgType)) + 1
  of ckCubeSkin: ord(high(CubeSkinType)) + 1

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

proc ensureBaseCosmeticUnlocks*(profile: RogueliteProfile) =
  if profile.isNil:
    return
  ensureId(profile.unlockedPlayerSkins, $skDefault)
  ensureId(profile.unlockedBulletSkins, $bskDefault)
  ensureId(profile.unlockedPlayerShapes, $shHexagon)
  ensureId(profile.unlockedBulletShapes, $bshCircle)
  ensureId(profile.unlockedParticleSkins, $pskDefault)
  ensureId(profile.unlockedDesktopBgs, $dbgDefault)
  ensureId(profile.unlockedCubeSkins, $cskDefault)

proc cosmeticIsUnlocked*(profile: RogueliteProfile, kind: CosmeticKind,
                         index: int): bool =
  if not isValidCosmeticIndex(kind, index):
    return false
  if index == defaultCosmeticIndex(kind):
    return true
  if profile.isNil:
    return false

  let id = cosmeticId(kind, index)
  case kind
  of ckPlayerSkin: hasId(profile.unlockedPlayerSkins, id)
  of ckBulletSkin: hasId(profile.unlockedBulletSkins, id)
  of ckPlayerShape: hasId(profile.unlockedPlayerShapes, id)
  of ckBulletShape: hasId(profile.unlockedBulletShapes, id)
  of ckParticle: hasId(profile.unlockedParticleSkins, id)
  of ckDesktopBg: hasId(profile.unlockedDesktopBgs, id)
  of ckCubeSkin: hasId(profile.unlockedCubeSkins, id)

proc addCosmeticUnlock(profile: RogueliteProfile, kind: CosmeticKind, index: int) =
  if profile.isNil:
    return
  let id = cosmeticId(kind, index)
  case kind
  of ckPlayerSkin: ensureId(profile.unlockedPlayerSkins, id)
  of ckBulletSkin: ensureId(profile.unlockedBulletSkins, id)
  of ckPlayerShape: ensureId(profile.unlockedPlayerShapes, id)
  of ckBulletShape: ensureId(profile.unlockedBulletShapes, id)
  of ckParticle: ensureId(profile.unlockedParticleSkins, id)
  of ckDesktopBg: ensureId(profile.unlockedDesktopBgs, id)
  of ckCubeSkin: ensureId(profile.unlockedCubeSkins, id)

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

proc sanitizeEquippedCosmetics*(settings: Settings,
                                profile: RogueliteProfile): bool =
  if settings.isNil:
    return false
  ensureBaseCosmeticUnlocks(profile)

  if not isValidCosmeticIndex(ckPlayerSkin, settings.playerSkin) or
     not cosmeticIsUnlocked(profile, ckPlayerSkin, settings.playerSkin):
    settings.playerSkin = defaultCosmeticIndex(ckPlayerSkin)
    result = true

  if not isValidCosmeticIndex(ckBulletSkin, settings.bulletSkin) or
     not cosmeticIsUnlocked(profile, ckBulletSkin, settings.bulletSkin):
    settings.bulletSkin = defaultCosmeticIndex(ckBulletSkin)
    result = true

  if not isValidCosmeticIndex(ckPlayerShape, settings.playerShape) or
     not cosmeticIsUnlocked(profile, ckPlayerShape, settings.playerShape):
    settings.playerShape = defaultCosmeticIndex(ckPlayerShape)
    result = true

  if not isValidCosmeticIndex(ckBulletShape, settings.bulletShape) or
     not cosmeticIsUnlocked(profile, ckBulletShape, settings.bulletShape):
    settings.bulletShape = defaultCosmeticIndex(ckBulletShape)
    result = true

  if not isValidCosmeticIndex(ckParticle, settings.particleEffect) or
     not cosmeticIsUnlocked(profile, ckParticle, settings.particleEffect):
    settings.particleEffect = defaultCosmeticIndex(ckParticle)
    result = true

  if not isValidCosmeticIndex(ckDesktopBg, settings.desktopBg) or
     not cosmeticIsUnlocked(profile, ckDesktopBg, settings.desktopBg):
    settings.desktopBg = defaultCosmeticIndex(ckDesktopBg)
    result = true

  if not isValidCosmeticIndex(ckCubeSkin, settings.cubeSkin) or
     not cosmeticIsUnlocked(profile, ckCubeSkin, settings.cubeSkin):
    settings.cubeSkin = defaultCosmeticIndex(ckCubeSkin)
    result = true

  if settings.kernelTophatEquipped and settings.cheaterHatEquipped:
    settings.cheaterHatEquipped = false
    result = true
