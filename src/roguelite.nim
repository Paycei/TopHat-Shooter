import json, os, random, strutils, math
import types, save_system, powerup

const
  RogueliteProfileVersion* = 1
  RogueliteSectorsPerAct* = 3
  RogueliteActsToWin* = 3
  RogueliteBaseSectorWaves* = 3
  RogueliteMaxHeat* = 6
  RogueliteMaxBossTier* = 3

type
  RogueliteWaveOutcome* = enum
    rwoContinue,
    rwoDraft,
    rwoSectorClear,
    rwoActBoss

  RogueliteUnlockCategory* = enum
    rucStarterKits,
    rucPowerFamilies,
    rucRelics,
    rucChallengeTiers

proc saveRogueliteProfile*(profile: RogueliteProfile): bool
proc commitRogueliteRunProgress*(game: Game, died: bool): bool

proc getRogueliteProfilePath*(): string =
  getAppDataPath() / "roguelite_profile.json"

proc initRogueliteProfile*(): RogueliteProfile =
  result = RogueliteProfile(
    version: RogueliteProfileVersion,
    dataShards: 0,
    unlockedStarterKits: {rskOperator},
    unlockedPowerFamilies: {rpfCore, rpfShield},
    unlockedRelics: {rrtDiscountProtocol},
    unlockedBossTier: 1,
    highestHeat: 0,
    bestAct: 1,
    bestSector: 0,
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
  of rrtShardMagnet: "Shards from waves and sector clears are increased by 25%."
  of rrtEliteDividend: "Elite sectors grant +25 credits and bonus shards."
  of rrtEmergencyPatch: "Act bosses heal 2 HP and grant +1 shield charge."
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

proc refreshRogueliteUnlocks*(profile: RogueliteProfile) =
  if profile.isNil: return
  profile.version = RogueliteProfileVersion
  profile.unlockedStarterKits.incl(rskOperator)
  profile.unlockedPowerFamilies.incl(rpfCore)
  profile.unlockedPowerFamilies.incl(rpfShield)
  profile.unlockedRelics.incl(rrtDiscountProtocol)
  profile.unlockedBossTier = clamp(profile.unlockedBossTier, 1, RogueliteMaxBossTier)
  profile.highestHeat = clamp(profile.highestHeat, 0, RogueliteMaxHeat)

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
  if nextHeat <= 0: 0 else: 45 + nextHeat * 35

proc bossTierCost*(nextTier: int): int =
  case nextTier
  of 2: 130
  of 3: 230
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

proc canPurchaseUnlock*(profile: RogueliteProfile, category: RogueliteUnlockCategory, index: int): bool =
  if profile.isNil or isUnlockPurchased(profile, category, index):
    return false
  let cost = unlockCost(profile, category, index)
  cost > 0 and profile.dataShards >= cost

proc purchaseRogueliteUnlock*(profile: RogueliteProfile, category: RogueliteUnlockCategory, index: int): bool =
  if not canPurchaseUnlock(profile, category, index):
    return false

  let cost = unlockCost(profile, category, index)
  profile.dataShards -= cost
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

proc rogueliteProfileToJson*(profile: RogueliteProfile): JsonNode =
  %* {
    "version": profile.version,
    "dataShards": profile.dataShards,
    "unlockedStarterKits": starterSetToJson(profile.unlockedStarterKits),
    "unlockedPowerFamilies": familySetToJson(profile.unlockedPowerFamilies),
    "unlockedRelics": relicSetToJson(profile.unlockedRelics),
    "unlockedBossTier": profile.unlockedBossTier,
    "highestHeat": profile.highestHeat,
    "bestAct": profile.bestAct,
    "bestSector": profile.bestSector,
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
  let kits = parseStarterSet(j.getOrDefault("unlockedStarterKits"))
  if kits != {}: result.unlockedStarterKits = kits
  let families = parseFamilySet(j.getOrDefault("unlockedPowerFamilies"))
  if families != {}: result.unlockedPowerFamilies = families
  let relics = parseRelicSet(j.getOrDefault("unlockedRelics"))
  if relics != {}: result.unlockedRelics = relics
  result.unlockedBossTier = j.getOrDefault("unlockedBossTier").getInt(result.unlockedBossTier)
  result.highestHeat = j.getOrDefault("highestHeat").getInt(result.highestHeat)
  result.bestAct = j.getOrDefault("bestAct").getInt(result.bestAct)
  result.bestSector = j.getOrDefault("bestSector").getInt(result.bestSector)
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
  profile.unlockedStarterKits = fresh.unlockedStarterKits
  profile.unlockedPowerFamilies = fresh.unlockedPowerFamilies
  profile.unlockedRelics = fresh.unlockedRelics
  profile.unlockedBossTier = fresh.unlockedBossTier
  profile.highestHeat = fresh.highestHeat
  profile.bestAct = fresh.bestAct
  profile.bestSector = fresh.bestSector
  profile.bestEndlessLoop = fresh.bestEndlessLoop
  profile.totalRuns = fresh.totalRuns
  profile.wins = fresh.wins
  saveRogueliteProfile(profile)

proc sectorModifierName*(modifier: RogueliteSectorModifier): string =
  case modifier
  of rsmSafehouse: "Safehouse"
  of rsmOverclocked: "Overclocked"
  of rsmEliteCache: "Elite Cache"
  of rsmFirewall: "Firewall"
  of rsmVolatileMemory: "Volatile Memory"
  of rsmBlackMarket: "Black Market"

proc sectorModifierDescription*(sector: RogueliteSector): string =
  case sector.modifier
  of rsmSafehouse: "Low pressure, lower shards, credit reward."
  of rsmOverclocked: "+28% pressure, +5 elite chance, +18% shards."
  of rsmEliteCache: "+38% pressure, +26 elite chance, +35% shards."
  of rsmFirewall: "+22% pressure, +8 elite chance, +15% shards."
  of rsmVolatileMemory: "+50% pressure, +16 elite chance, +48% shards."
  of rsmBlackMarket: "+16% pressure, +4 elite chance, bonus credits."

proc rewardName*(reward: RogueliteRewardType): string =
  case reward
  of rrwCredits: "Credits"
  of rrwRelic: "Relic"
  of rrwPowerFamily: "Power Family"
  of rrwShardCache: "Shard Cache"

proc makeSector(modifier: RogueliteSectorModifier, reward: RogueliteRewardType,
                act, sectorIndex, heat, endlessLoop: int): RogueliteSector =
  let actPressure = max(0, act - 1).float32 * 0.13
  let sectorPressure = max(0, sectorIndex - 1).float32 * 0.05
  let endlessPressure = endlessLoop.float32 * 0.35
  let heatPressure = heat.float32 * 0.18
  result = RogueliteSector(
    name: sectorModifierName(modifier) & " " & $act & "." & $sectorIndex,
    modifier: modifier,
    rewardType: reward,
    waveCount: RogueliteBaseSectorWaves,
    enemyPressure: 1.0 + actPressure + sectorPressure + endlessPressure + heatPressure,
    eliteChanceBonus: heat * 5 + endlessLoop * 7 + act * 2,
    shardMultiplier: 1.0 + heat.float32 * 0.12 + endlessLoop.float32 * 0.22,
    isElite: modifier == rsmEliteCache
  )

  case modifier
  of rsmSafehouse:
    result.enemyPressure *= 0.98
    result.shardMultiplier *= 0.9
  of rsmOverclocked:
    result.enemyPressure *= 1.28
    result.eliteChanceBonus += 5
    result.shardMultiplier *= 1.18
  of rsmEliteCache:
    result.enemyPressure *= 1.38
    result.eliteChanceBonus += 26
    result.shardMultiplier *= 1.35
  of rsmFirewall:
    result.enemyPressure *= 1.22
    result.eliteChanceBonus += 8
    result.shardMultiplier *= 1.15
  of rsmVolatileMemory:
    result.enemyPressure *= 1.5
    result.eliteChanceBonus += 16
    result.shardMultiplier *= 1.48
  of rsmBlackMarket:
    result.enemyPressure *= 1.16
    result.eliteChanceBonus += 4
    result.shardMultiplier *= 1.08

proc generateSectorChoices*(run: RogueliteRun) =
  if run.isNil: return
  let act = run.act + run.endlessLoop * RogueliteActsToWin
  let sectorIndex = run.sectorsThisAct + 1
  run.nextSectorChoices[0] = makeSector(rsmSafehouse, rrwCredits, act, sectorIndex, run.heat, run.endlessLoop)
  run.nextSectorChoices[1] = makeSector(
    if rand(100) < 50: rsmOverclocked else: rsmBlackMarket,
    if rand(100) < 50: rrwShardCache else: rrwPowerFamily,
    act, sectorIndex, run.heat, run.endlessLoop)
  run.nextSectorChoices[2] = makeSector(
    if rand(100) < 65: rsmEliteCache else: rsmVolatileMemory,
    rrwRelic, act, sectorIndex, run.heat, run.endlessLoop)

proc beginRogueliteRun*(game: Game, profile: RogueliteProfile,
                         starterKit: RogueliteStarterKit, heat: int) =
  refreshRogueliteUnlocks(profile)
  let clampedHeat = clamp(heat, 0, profile.highestHeat)
  game.rogueliteProfile = profile
  game.rogueliteRun = RogueliteRun(
    seed: rand(1_000_000_000),
    starterKit: starterKit,
    heat: clampedHeat,
    act: 1,
    sector: 0,
    sectorsThisAct: 0,
    sectorWavesCleared: 0,
    totalSectorsCleared: 0,
    activeSector: makeSector(rsmSafehouse, rrwCredits, 1, 1, clampedHeat, 0),
    relics: @[],
    shardsEarned: 0,
    endlessLoop: 0,
    pendingSectorSelect: true,
    pendingActBoss: false,
    completed: false,
    died: false
  )
  generateSectorChoices(game.rogueliteRun)

  game.currentWave = 1 + clampedHeat * 2
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

proc selectRogueliteSector*(game: Game, choiceIndex: int) =
  if game.rogueliteRun.isNil: return
  let idx = clamp(choiceIndex, 0, 2)
  game.rogueliteRun.activeSector = game.rogueliteRun.nextSectorChoices[idx]
  game.rogueliteRun.sectorWavesCleared = 0
  game.rogueliteRun.pendingSectorSelect = false
  game.rogueliteRun.pendingActBoss = false
  game.waveInProgress = false
  game.waveEnemiesRemaining = 0
  game.spawnTimer = 0
  game.wavesUntilBoss = 999

proc finishRogueliteWave*(game: Game): RogueliteWaveOutcome =
  if game.rogueliteRun.isNil:
    return rwoContinue

  let sector = game.rogueliteRun.activeSector
  game.rogueliteRun.sectorWavesCleared += 1
  game.currentWave += 1

  let relicShardMultiplier = if game.rogueliteRun.hasRelic(rrtShardMagnet): 1.25'f32 else: 1.0'f32
  let effectiveShardMultiplier = sector.shardMultiplier * relicShardMultiplier
  let baseShard = 2 + game.rogueliteRun.act + game.rogueliteRun.endlessLoop
  let shardBonus = int(ceil(baseShard.float32 * effectiveShardMultiplier))
  game.rogueliteRun.shardsEarned += max(1, shardBonus)

  if game.rogueliteRun.sectorWavesCleared >= sector.waveCount:
    game.rogueliteRun.totalSectorsCleared += 1
    game.rogueliteRun.sector += 1
    game.rogueliteRun.sectorsThisAct += 1
    game.rogueliteRun.shardsEarned += int(ceil(8.0 * effectiveShardMultiplier))
    if sector.rewardType == rrwCredits or sector.modifier == rsmBlackMarket:
      game.player.coins += 20 + game.rogueliteRun.act * 5 + game.rogueliteRun.heat * 3
    if sector.isElite or sector.rewardType == rrwRelic:
      game.player.coins += 10
    if sector.isElite and game.rogueliteRun.hasRelic(rrtEliteDividend):
      game.player.coins += 25
      game.rogueliteRun.shardsEarned += int(ceil(10.0 * effectiveShardMultiplier))
    if game.rogueliteRun.sectorsThisAct >= RogueliteSectorsPerAct:
      game.rogueliteRun.pendingActBoss = true
      game.wavesUntilBoss = 0
      return rwoActBoss
    game.rogueliteRun.pendingSectorSelect = true
    generateSectorChoices(game.rogueliteRun)
    return rwoSectorClear

  if game.rogueliteRun.sectorWavesCleared == 2:
    return rwoDraft
  return rwoContinue

proc completeRogueliteBoss*(game: Game) =
  if game.rogueliteRun.isNil: return
  let bossShardReward = 35 + game.rogueliteRun.act * 10 + game.rogueliteRun.heat * 8 +
                        game.rogueliteRun.endlessLoop * 15
  game.rogueliteRun.shardsEarned += bossShardReward
  game.rogueliteRun.pendingActBoss = false
  game.wavesUntilBoss = 999

  let eligibleRelics = [rrtDiscountProtocol, rrtShardMagnet, rrtEliteDividend,
                        rrtEmergencyPatch, rrtDraftCache]
  for relicType in eligibleRelics:
    if relicType in game.rogueliteProfile.unlockedRelics and
       not game.rogueliteRun.hasRelic(relicType):
      game.rogueliteRun.relics.add(makeRelic(relicType))
      break

  if game.rogueliteRun.hasRelic(rrtEmergencyPatch):
    game.player.hp = min(game.player.maxHp, game.player.hp + 2.0)
    game.player.shieldHits += 1

  if game.rogueliteRun.act >= RogueliteActsToWin:
    game.rogueliteRun.completed = true
    game.rogueliteProfile.wins += 1
    game.rogueliteProfile.bestEndlessLoop = max(game.rogueliteProfile.bestEndlessLoop,
                                                game.rogueliteRun.endlessLoop)
    discard commitRogueliteRunProgress(game, false)
    game.rogueliteRun.endlessLoop += 1
    game.rogueliteRun.act = 1
    game.rogueliteRun.sectorsThisAct = 0
  else:
    game.rogueliteRun.act += 1
    game.rogueliteRun.sectorsThisAct = 0

  game.rogueliteRun.pendingSectorSelect = true
  generateSectorChoices(game.rogueliteRun)

proc commitRogueliteRunProgress*(game: Game, died: bool): bool =
  if game.rogueliteProfile.isNil or game.rogueliteRun.isNil:
    return false

  game.rogueliteRun.died = died
  if died:
    game.rogueliteProfile.totalRuns += 1

  game.rogueliteProfile.dataShards += game.rogueliteRun.shardsEarned
  game.rogueliteProfile.bestAct = max(game.rogueliteProfile.bestAct, game.rogueliteRun.act)
  game.rogueliteProfile.bestSector = max(game.rogueliteProfile.bestSector,
                                         game.rogueliteRun.totalSectorsCleared)
  game.rogueliteProfile.bestEndlessLoop = max(game.rogueliteProfile.bestEndlessLoop,
                                              game.rogueliteRun.endlessLoop)
  game.rogueliteRun.shardsEarned = 0
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
