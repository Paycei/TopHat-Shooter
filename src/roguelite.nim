import json, os, random, strutils, math
import types, settings, save_system, powerup, powerup_data, skins, bullet_skins, bullet_shapes, shapes, particle_skins, desktop_bg_skins, cube_skins

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
    wins: 0,
    recursionDamageBonus: 0.0'f32,
    recursionLevel: 0,
    seenAffordableUnlocks: @[]
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
  ## Unlock order is the declaration order, so derive it instead of restating it.
  RogueliteStarterKit(clamp(index, 0, ord(high(RogueliteStarterKit))))

proc familyByUnlockIndex*(index: int): RoguelitePowerFamily =
  ## Unlock order is the declaration order, so derive it instead of restating it.
  RoguelitePowerFamily(clamp(index, 0, ord(high(RoguelitePowerFamily))))

proc relicByUnlockIndex*(index: int): RogueliteRelicType =
  ## NOT ordinal-aligned: this is a deliberate display order, not the enum order
  ## (index 2 is rrtDraftCache while ord 3 is rrtEliteDividend). Keep it explicit.
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

proc canAffordAnyUnlock*(profile: RogueliteProfile): bool =
  ## True if at least one not-yet-owned unlock is purchasable right now.
  ## Drives the "deal available" badge on the shop button so the player has a
  ## reason to open the shop the moment they can spend.
  if profile.isNil:
    return false
  for category in RogueliteUnlockCategory:
    for index in 0..<unlockCount(category):
      if canPurchaseUnlock(profile, category, index):
        return true
  false

proc unlockKey(profile: RogueliteProfile, category: RogueliteUnlockCategory, index: int): string =
  ## Stable identity for an unlock, used to remember which affordable items the
  ## player has already seen. Kits/families/relics key off their enum value;
  ## challenge tiers key off the concrete next level (so buying one tier still lets
  ## the *next*, genuinely-new tier re-trigger the badge).
  case category
  of rucStarterKits: "kit:" & $starterByUnlockIndex(index)
  of rucPowerFamilies: "fam:" & $familyByUnlockIndex(index)
  of rucRelics: "relic:" & $relicByUnlockIndex(index)
  of rucChallengeTiers:
    if profile.isNil: "tier:?"
    elif index == 0: "heat:" & $(profile.highestHeat + 1)
    else: "boss:" & $(profile.unlockedBossTier + 1)

proc hasUnseenAffordableUnlock*(profile: RogueliteProfile): bool =
  ## True only when an affordable unlock exists that the player has NOT yet been
  ## shown. Drives the shop button's "deal" badge so it appears once per newly
  ## affordable item and clears after the player opens the shop.
  if profile.isNil:
    return false
  for category in RogueliteUnlockCategory:
    for index in 0..<unlockCount(category):
      if canPurchaseUnlock(profile, category, index) and
         unlockKey(profile, category, index) notin profile.seenAffordableUnlocks:
        return true
  false

proc markAffordableUnlocksSeen*(profile: RogueliteProfile) =
  ## Record every currently-affordable unlock as seen, then persist. Called when
  ## the shop opens so the badge clears until something *new* becomes affordable.
  if profile.isNil:
    return
  var changed = false
  for category in RogueliteUnlockCategory:
    for index in 0..<unlockCount(category):
      if canPurchaseUnlock(profile, category, index):
        let key = unlockKey(profile, category, index)
        if key notin profile.seenAffordableUnlocks:
          profile.seenAffordableUnlocks.add(key)
          changed = true
  if changed:
    discard saveRogueliteProfile(profile)

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

proc parseEnumSet[T: enum](j: JsonNode): set[T] =
  ## Parse a JSON array of `$value` symbol names into an enum set, silently
  ## skipping any unknown member (so stale ids in old profiles are dropped, not
  ## collapsed to a default). Unifies the previous per-enum set parsers.
  result = {}
  if j.kind != JArray: return
  for item in j:
    try:
      result.incl(parseEnum[T](item.getStr()))
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
    "wins": profile.wins,
    "recursionDamageBonus": profile.recursionDamageBonus,
    "recursionLevel": profile.recursionLevel,
    "seenAffordableUnlocks": stringSeqToJson(profile.seenAffordableUnlocks)
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
  let kits = parseEnumSet[RogueliteStarterKit](j.getOrDefault("unlockedStarterKits"))
  if kits != {}: result.unlockedStarterKits = kits
  let families = parseEnumSet[RoguelitePowerFamily](j.getOrDefault("unlockedPowerFamilies"))
  if families != {}: result.unlockedPowerFamilies = families
  let relics = parseEnumSet[RogueliteRelicType](j.getOrDefault("unlockedRelics"))
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
  if j.hasKey("seenAffordableUnlocks"):
    result.seenAffordableUnlocks = parseStringSeq(j["seenAffordableUnlocks"])
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
  profile.recursionDamageBonus = fresh.recursionDamageBonus
  profile.recursionLevel = fresh.recursionLevel
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
    died: false,
    awaitingVictoryScreen: false
  )

  game.currentWave = 1
  game.wavesUntilBoss = 999
  game.waveInProgress = false
  game.waveEnemiesRemaining = 0
  game.player.coins = 0

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

  # SectorProtocol: bonus coins on floor completion
  if game.player.hasSectorProtocol:
    game.player.coins += 15

  if run.floorNumber >= RogueliteFloorsToWin:
    # Final floor boss down. Bank the win immediately (so a victory is never lost),
    # then hand off to the ending screen instead of silently rolling into the next
    # endless loop. The endless roll is deferred to rogueliteContinueEndless, called
    # only if the player chooses to push deeper rather than cash out.
    run.completed = true
    game.rogueliteProfile.wins += 1
    game.rogueliteProfile.bestEndlessLoop = max(game.rogueliteProfile.bestEndlessLoop,
                                                run.endlessLoop)
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

proc rogueliteContinueEndless*(run: RogueliteRun) =
  ## Player chose "Continue" on the ending screen: roll the completed run into the
  ## next endless loop. Mirrors the floor-reset the old completeRogueliteBoss did
  ## inline, now gated behind the victory-screen choice.
  if run.isNil: return
  run.awaitingVictoryScreen = false
  run.endlessLoop += 1
  run.floorNumber = 1
  run.usedThemes = {}
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
