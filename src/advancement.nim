## Persistent advancement system.
## Progress is derived from lifetime stats, last-run analytics, and roguelite profile data.

import json, os, times, strutils, math
import types, statistics, run_statistics, save_system

type
  AdvancementCategory* = enum
    acCombat
    acSurvival
    acResources
    acMastery
    acRoguelite

  AdvancementTier* = enum
    atBronze
    atSilver
    atGold
    atLegendary

  AdvancementDefinition* = object
    id*: string
    name*: string
    description*: string
    category*: AdvancementCategory
    tier*: AdvancementTier
    target*: float32
    points*: int
    reward*: string

  AdvancementEntry* = object
    id*: string
    progress*: float32
    unlocked*: bool
    claimed*: bool
    unlockedAt*: string

  AdvancementProfile* = ref object
    version*: int
    entries*: seq[AdvancementEntry]
    recentUnlocks*: seq[string]
    dirty*: bool

const
  AdvancementProfileVersion* = 1
  AdvancementRogueliteSectorsPerAct = 3

proc saveAdvancements*(profile: AdvancementProfile): bool

proc allAdvancementCategories*(): array[5, AdvancementCategory] =
  [acCombat, acSurvival, acResources, acMastery, acRoguelite]

proc categoryName*(category: AdvancementCategory): string =
  case category
  of acCombat: "Combat"
  of acSurvival: "Survival"
  of acResources: "Resources"
  of acMastery: "Mastery"
  of acRoguelite: "Roguelite"

proc categoryDescription*(category: AdvancementCategory): string =
  case category
  of acCombat: "Eliminations, bosses, accuracy, and combo pressure."
  of acSurvival: "Waves, endurance, no-damage windows, and clutch play."
  of acResources: "Credits, consumables, walls, and economy control."
  of acMastery: "Power-up drafting, legendary installs, and build depth."
  of acRoguelite: "Sector clears, banked shards, Heat unlocks, and full-run wins."

proc tierName*(tier: AdvancementTier): string =
  case tier
  of atBronze: "Bronze"
  of atSilver: "Silver"
  of atGold: "Gold"
  of atLegendary: "Legendary"

proc getAdvancementDefinitions*(): seq[AdvancementDefinition] =
  @[
    AdvancementDefinition(
      id: "combat_first_breach",
      name: "First Breach",
      description: "Terminate your first hostile process.",
      category: acCombat,
      tier: atBronze,
      target: 1.0'f32,
      points: 10,
      reward: "Operator badge: Breach"
    ),
    AdvancementDefinition(
      id: "combat_threat_hunter",
      name: "Threat Hunter",
      description: "Defeat 100 enemies across all tracked modes.",
      category: acCombat,
      tier: atBronze,
      target: 100.0'f32,
      points: 20,
      reward: "20 advancement points"
    ),
    AdvancementDefinition(
      id: "combat_process_reaper",
      name: "Process Reaper",
      description: "Defeat 1,000 enemies across all tracked modes.",
      category: acCombat,
      tier: atGold,
      target: 1000.0'f32,
      points: 60,
      reward: "Gold combat plate"
    ),
    AdvancementDefinition(
      id: "combat_boss_signal",
      name: "Boss Signal",
      description: "Defeat your first boss-class process.",
      category: acCombat,
      tier: atBronze,
      target: 1.0'f32,
      points: 20,
      reward: "Boss telemetry feed"
    ),
    AdvancementDefinition(
      id: "combat_boss_hunter",
      name: "Boss Hunter",
      description: "Defeat 10 bosses across all tracked modes.",
      category: acCombat,
      tier: atSilver,
      target: 10.0'f32,
      points: 45,
      reward: "Hunter process tag"
    ),
    AdvancementDefinition(
      id: "combat_deadeye",
      name: "Deadeye Protocol",
      description: "Finish a run with at least 85% shot accuracy.",
      category: acCombat,
      tier: atGold,
      target: 85.0'f32,
      points: 55,
      reward: "Precision badge"
    ),
    AdvancementDefinition(
      id: "combat_combo_chain",
      name: "Combo Chain",
      description: "Reach a 15x combo in a tracked run.",
      category: acCombat,
      tier: atSilver,
      target: 15.0'f32,
      points: 35,
      reward: "Combo analyzer"
    ),
    AdvancementDefinition(
      id: "combat_singularity",
      name: "Singularity Chain",
      description: "Reach a 50x combo in a tracked run.",
      category: acCombat,
      tier: atLegendary,
      target: 50.0'f32,
      points: 100,
      reward: "Legendary chain marker"
    ),

    AdvancementDefinition(
      id: "survival_hold_line",
      name: "Hold the Line",
      description: "Reach wave 5 in wave mode.",
      category: acSurvival,
      tier: atBronze,
      target: 5.0'f32,
      points: 15,
      reward: "Wave log access"
    ),
    AdvancementDefinition(
      id: "survival_sector_warden",
      name: "Sector Warden",
      description: "Reach wave 15 in wave mode.",
      category: acSurvival,
      tier: atSilver,
      target: 15.0'f32,
      points: 35,
      reward: "Warden status line"
    ),
    AdvancementDefinition(
      id: "survival_firewall_legend",
      name: "Firewall Legend",
      description: "Reach wave 35 in wave mode.",
      category: acSurvival,
      tier: atLegendary,
      target: 35.0'f32,
      points: 95,
      reward: "Legendary firewall seal"
    ),
    AdvancementDefinition(
      id: "survival_five_minutes",
      name: "Five-Minute Runtime",
      description: "Survive for 5 minutes in time survival.",
      category: acSurvival,
      tier: atBronze,
      target: 300.0'f32,
      points: 20,
      reward: "Runtime monitor"
    ),
    AdvancementDefinition(
      id: "survival_twenty_minutes",
      name: "Twenty-Minute Runtime",
      description: "Survive for 20 minutes in time survival.",
      category: acSurvival,
      tier: atGold,
      target: 1200.0'f32,
      points: 70,
      reward: "Extended runtime flag"
    ),
    AdvancementDefinition(
      id: "survival_clean_window",
      name: "Clean Window",
      description: "Maintain a 30 second no-damage streak in a tracked run.",
      category: acSurvival,
      tier: atSilver,
      target: 30.0'f32,
      points: 35,
      reward: "Defensive trace"
    ),
    AdvancementDefinition(
      id: "survival_phantom_runtime",
      name: "Phantom Runtime",
      description: "Maintain a 90 second no-damage streak in a tracked run.",
      category: acSurvival,
      tier: atLegendary,
      target: 90.0'f32,
      points: 95,
      reward: "Phantom shell tag"
    ),

    AdvancementDefinition(
      id: "resource_cache_foundry",
      name: "Cache Foundry",
      description: "Bank 500 credits across tracked runs.",
      category: acResources,
      tier: atBronze,
      target: 500.0'f32,
      points: 20,
      reward: "Credit ledger"
    ),
    AdvancementDefinition(
      id: "resource_vault_breach",
      name: "Vault Breach",
      description: "Bank 2,500 credits across tracked runs.",
      category: acResources,
      tier: atSilver,
      target: 2500.0'f32,
      points: 40,
      reward: "Vault marker"
    ),
    AdvancementDefinition(
      id: "resource_credit_blackhole",
      name: "Credit Blackhole",
      description: "Bank 10,000 credits across tracked runs.",
      category: acResources,
      tier: atGold,
      target: 10000.0'f32,
      points: 75,
      reward: "Gold economy plate"
    ),
    AdvancementDefinition(
      id: "resource_wallwright",
      name: "Wallwright",
      description: "Place 20 walls in a tracked run.",
      category: acResources,
      tier: atSilver,
      target: 20.0'f32,
      points: 35,
      reward: "Constructor permit"
    ),
    AdvancementDefinition(
      id: "resource_field_medic",
      name: "Field Medic",
      description: "Collect 25 consumables in a tracked run.",
      category: acResources,
      tier: atSilver,
      target: 25.0'f32,
      points: 35,
      reward: "Recovery badge"
    ),

    AdvancementDefinition(
      id: "mastery_first_install",
      name: "First Install",
      description: "Choose your first power-up in a tracked run.",
      category: acMastery,
      tier: atBronze,
      target: 1.0'f32,
      points: 10,
      reward: "Installer audit"
    ),
    AdvancementDefinition(
      id: "mastery_kernel_stack",
      name: "Kernel Stack",
      description: "Install 8 power-ups in a single tracked run.",
      category: acMastery,
      tier: atSilver,
      target: 8.0'f32,
      points: 35,
      reward: "Stack visualizer"
    ),
    AdvancementDefinition(
      id: "mastery_legendary_handshake",
      name: "Legendary Handshake",
      description: "Install a legendary power-up in a tracked run.",
      category: acMastery,
      tier: atSilver,
      target: 1.0'f32,
      points: 35,
      reward: "Legendary handshake key"
    ),
    AdvancementDefinition(
      id: "mastery_legendary_cluster",
      name: "Legendary Cluster",
      description: "Install 4 legendary power-ups in a single tracked run.",
      category: acMastery,
      tier: atGold,
      target: 4.0'f32,
      points: 70,
      reward: "Cluster badge"
    ),
    AdvancementDefinition(
      id: "mastery_elemental_mesh",
      name: "Elemental Mesh",
      description: "Build a run with 4 elemental or aura power-ups.",
      category: acMastery,
      tier: atGold,
      target: 4.0'f32,
      points: 70,
      reward: "Elemental mesh map"
    ),

    AdvancementDefinition(
      id: "roguelite_first_sector",
      name: "First Sector Clear",
      description: "Clear any 3-wave roguelite sector.",
      category: acRoguelite,
      tier: atBronze,
      target: 1.0'f32,
      points: 20,
      reward: "Sector route cache"
    ),
    AdvancementDefinition(
      id: "roguelite_act_runner",
      name: "Act Runner",
      description: "Clear 5 roguelite sectors across all runs.",
      category: acRoguelite,
      tier: atSilver,
      target: 5.0'f32,
      points: 40,
      reward: "Route planner"
    ),
    AdvancementDefinition(
      id: "roguelite_shard_cache",
      name: "Shard Cache",
      description: "Bank 100 Data Shards in your roguelite profile.",
      category: acRoguelite,
      tier: atSilver,
      target: 100.0'f32,
      points: 40,
      reward: "Shard ledger"
    ),
    AdvancementDefinition(
      id: "roguelite_heat_check",
      name: "Heat Check",
      description: "Unlock Heat 2 from the roguelite unlock shop.",
      category: acRoguelite,
      tier: atSilver,
      target: 2.0'f32,
      points: 40,
      reward: "Heat dial"
    ),
    AdvancementDefinition(
      id: "roguelite_heat_singularity",
      name: "Heat Singularity",
      description: "Unlock Heat 3, the highest roguelite Heat.",
      category: acRoguelite,
      tier: atLegendary,
      target: 3.0'f32,
      points: 100,
      reward: "Singularity heat plate"
    ),
    AdvancementDefinition(
      id: "roguelite_victory_kernel",
      name: "Victory Kernel",
      description: "Defeat the third act boss and complete a roguelite run.",
      category: acRoguelite,
      tier: atLegendary,
      target: 1.0'f32,
      points: 110,
      reward: "Victory kernel seal"
    )
  ]

proc getAdvancementsPath*(): string =
  getAppDataPath() / "advancements.json"

proc newAdvancementProfile*(): AdvancementProfile =
  result = AdvancementProfile(
    version: AdvancementProfileVersion,
    entries: @[],
    recentUnlocks: @[],
    dirty: true
  )
  for def in getAdvancementDefinitions():
    result.entries.add(AdvancementEntry(id: def.id, progress: 0.0, unlocked: false,
                                        claimed: false, unlockedAt: ""))

proc findEntryIndex*(profile: AdvancementProfile, id: string): int =
  if profile.isNil:
    return -1
  for i in 0..<profile.entries.len:
    if profile.entries[i].id == id:
      return i
  -1

proc hasDefinition(id: string): bool =
  for def in getAdvancementDefinitions():
    if def.id == id:
      return true
  false

proc ensureAdvancementEntries*(profile: AdvancementProfile) =
  if profile.isNil:
    return
  if profile.version < AdvancementProfileVersion:
    profile.version = AdvancementProfileVersion
    profile.dirty = true

  for def in getAdvancementDefinitions():
    if profile.findEntryIndex(def.id) < 0:
      profile.entries.add(AdvancementEntry(id: def.id, progress: 0.0,
                                           unlocked: false, claimed: false,
                                           unlockedAt: ""))
      profile.dirty = true

  var i = 0
  while i < profile.entries.len:
    if not hasDefinition(profile.entries[i].id):
      profile.entries.delete(i)
      profile.dirty = true
    else:
      inc i

proc getAdvancementDefinition*(id: string): AdvancementDefinition =
  for def in getAdvancementDefinitions():
    if def.id == id:
      return def
  AdvancementDefinition()

proc getAdvancementEntry*(profile: AdvancementProfile, id: string): AdvancementEntry =
  let idx = profile.findEntryIndex(id)
  if idx >= 0:
    return profile.entries[idx]
  AdvancementEntry(id: id, progress: 0.0, unlocked: false, claimed: false, unlockedAt: "")

proc definitionsForCategory*(category: AdvancementCategory): seq[AdvancementDefinition] =
  result = @[]
  for def in getAdvancementDefinitions():
    if def.category == category:
      result.add(def)

proc advancementPercent*(entry: AdvancementEntry, def: AdvancementDefinition): float32 =
  if def.target <= 0:
    return 1.0'f32
  clamp(entry.progress / def.target, 0.0'f32, 1.0'f32)

proc formatAdvancementProgress*(entry: AdvancementEntry, def: AdvancementDefinition): string =
  let shown = min(entry.progress, def.target)
  if def.target >= 100.0'f32:
    $shown.int & " / " & $def.target.int
  elif def.target == floor(def.target):
    $shown.int & " / " & $def.target.int
  else:
    shown.formatFloat(ffDecimal, 1) & " / " & def.target.formatFloat(ffDecimal, 1)

proc totalUnlocked*(profile: AdvancementProfile): int =
  if profile.isNil: return 0
  for entry in profile.entries:
    if entry.unlocked:
      inc result

proc totalClaimed*(profile: AdvancementProfile): int =
  if profile.isNil: return 0
  for entry in profile.entries:
    if entry.claimed:
      inc result

proc totalAvailablePoints*(profile: AdvancementProfile): int =
  if profile.isNil: return 0
  for def in getAdvancementDefinitions():
    let entry = profile.getAdvancementEntry(def.id)
    if entry.unlocked:
      result += def.points

proc totalClaimedPoints*(profile: AdvancementProfile): int =
  if profile.isNil: return 0
  for def in getAdvancementDefinitions():
    let entry = profile.getAdvancementEntry(def.id)
    if entry.claimed:
      result += def.points

proc unclaimedPoints*(profile: AdvancementProfile): int =
  if profile.isNil: return 0
  for def in getAdvancementDefinitions():
    let entry = profile.getAdvancementEntry(def.id)
    if entry.unlocked and not entry.claimed:
      result += def.points

proc categoryTotals*(profile: AdvancementProfile,
                     category: AdvancementCategory): tuple[unlocked, total, unclaimed: int] =
  for def in getAdvancementDefinitions():
    if def.category != category:
      continue
    inc result.total
    let entry = profile.getAdvancementEntry(def.id)
    if entry.unlocked:
      inc result.unlocked
      if not entry.claimed:
        inc result.unclaimed

proc totalKills(stats: Statistics): int =
  if stats.isNil: return 0
  stats.waveMode.totalKills + stats.timeMode.totalKills + stats.rogueliteMode.totalKills

proc totalCoins(stats: Statistics): int =
  if stats.isNil: return 0
  stats.waveMode.totalCoins + stats.timeMode.totalCoins + stats.rogueliteMode.totalCoins

proc totalBosses(stats: Statistics): int =
  if stats.isNil: return 0
  stats.waveMode.bossesDefeated + stats.timeMode.bossesDefeated + stats.rogueliteMode.bossesDefeated

proc highestWave(stats: Statistics): int =
  if stats.isNil: return 0
  max(stats.waveMode.highestWaveReached, stats.waveMode.bestScore)

proc longestSurvival(stats: Statistics): float32 =
  if stats.isNil: return 0.0'f32
  max(stats.timeMode.longestSurvivalTime, stats.timeMode.bestScore.float32)

proc countElementalPowerUps(runStats: RunStatistics): int =
  if runStats.isNil:
    return 0
  for powerUp in runStats.finalPowerUps:
    case powerUp.powerType
    of puPoisonShot, puFireBullets, puWindBullets, puFrostShots,
       puPoisonOrb, puFireOrb, puLightningOrb, puWindOrb, puFrostOrb,
       puArcaneOrb, puBloodOrb, puFireAura, puLightningAura, puPoisonAura,
       puWindAura, puArcaneAura, puBloodAura, puRotatingOrbs:
      inc result
    else:
      discard

proc rogueliteSectorsCleared(profile: RogueliteProfile): int =
  if profile.isNil:
    return 0
  max(profile.bestSector, max(0, profile.bestAct - 1) * AdvancementRogueliteSectorsPerAct)

proc measuredProgress(def: AdvancementDefinition, stats: Statistics,
                      lastRun: RunStatistics,
                      rogueliteProfile: RogueliteProfile): float32 =
  case def.id
  of "combat_first_breach", "combat_threat_hunter", "combat_process_reaper":
    totalKills(stats).float32
  of "combat_boss_signal", "combat_boss_hunter":
    totalBosses(stats).float32
  of "combat_deadeye":
    if lastRun.isNil: 0.0'f32 else: lastRun.combat.accuracyPercent
  of "combat_combo_chain", "combat_singularity":
    if lastRun.isNil: 0.0'f32 else: lastRun.combat.maxCombo.float32
  of "survival_hold_line", "survival_sector_warden", "survival_firewall_legend":
    highestWave(stats).float32
  of "survival_five_minutes", "survival_twenty_minutes":
    longestSurvival(stats)
  of "survival_clean_window", "survival_phantom_runtime":
    if lastRun.isNil: 0.0'f32 else: lastRun.movement.longestNoDamageStreak
  of "resource_cache_foundry", "resource_vault_breach", "resource_credit_blackhole":
    totalCoins(stats).float32
  of "resource_wallwright":
    if lastRun.isNil: 0.0'f32 else: lastRun.resources.wallsPlaced.float32
  of "resource_field_medic":
    if lastRun.isNil: 0.0'f32 else: lastRun.resources.consumablesCollected.float32
  of "mastery_first_install", "mastery_kernel_stack":
    if lastRun.isNil: 0.0'f32 else: lastRun.powerUps.totalPowerUps.float32
  of "mastery_legendary_handshake", "mastery_legendary_cluster":
    if lastRun.isNil: 0.0'f32 else: lastRun.powerUps.legendaryPowerUps.float32
  of "mastery_elemental_mesh":
    countElementalPowerUps(lastRun).float32
  of "roguelite_first_sector", "roguelite_act_runner":
    rogueliteSectorsCleared(rogueliteProfile).float32
  of "roguelite_shard_cache":
    if rogueliteProfile.isNil: 0.0'f32 else: rogueliteProfile.dataShards.float32
  of "roguelite_heat_check", "roguelite_heat_singularity":
    if rogueliteProfile.isNil: 0.0'f32 else: rogueliteProfile.highestHeat.float32
  of "roguelite_victory_kernel":
    if rogueliteProfile.isNil: 0.0'f32 else: rogueliteProfile.wins.float32
  else:
    0.0'f32

proc syncAdvancements*(profile: AdvancementProfile, stats: Statistics,
                       lastRun: RunStatistics = nil,
                       rogueliteProfile: RogueliteProfile = nil): seq[AdvancementDefinition] =
  if profile.isNil:
    return @[]
  profile.ensureAdvancementEntries()

  for def in getAdvancementDefinitions():
    let idx = profile.findEntryIndex(def.id)
    if idx < 0:
      continue

    let measured = measuredProgress(def, stats, lastRun, rogueliteProfile)
    if measured > profile.entries[idx].progress:
      profile.entries[idx].progress = measured
      profile.dirty = true

    if not profile.entries[idx].unlocked and profile.entries[idx].progress >= def.target:
      profile.entries[idx].unlocked = true
      profile.entries[idx].unlockedAt = $now()
      profile.recentUnlocks.add(def.id)
      profile.dirty = true
      result.add(def)

proc claimAdvancement*(profile: AdvancementProfile, id: string): bool =
  let idx = profile.findEntryIndex(id)
  if idx < 0:
    return false
  if profile.entries[idx].unlocked and not profile.entries[idx].claimed:
    profile.entries[idx].claimed = true
    profile.dirty = true
    return true
  false

proc claimAllAdvancements*(profile: AdvancementProfile): int =
  if profile.isNil:
    return 0
  for i in 0..<profile.entries.len:
    if profile.entries[i].unlocked and not profile.entries[i].claimed:
      profile.entries[i].claimed = true
      profile.dirty = true
      inc result

proc resetAdvancements*(profile: AdvancementProfile): bool =
  ## Reset an existing advancement profile in place so open windows keep their reference.
  if profile.isNil:
    return false

  let fresh = newAdvancementProfile()
  profile.version = fresh.version
  profile.entries = fresh.entries
  profile.recentUnlocks = @[]
  profile.dirty = true
  saveAdvancements(profile)

proc resetAdvancementCategory*(profile: AdvancementProfile,
                               category: AdvancementCategory): bool =
  ## Clear one advancement category without replacing the profile object.
  if profile.isNil:
    return false

  for def in definitionsForCategory(category):
    let idx = profile.findEntryIndex(def.id)
    if idx >= 0:
      profile.entries[idx].progress = 0.0'f32
      profile.entries[idx].unlocked = false
      profile.entries[idx].claimed = false
      profile.entries[idx].unlockedAt = ""
      profile.dirty = true

  var recent: seq[string] = @[]
  for id in profile.recentUnlocks:
    let def = getAdvancementDefinition(id)
    if def.id.len > 0 and def.category != category:
      recent.add(id)
  profile.recentUnlocks = recent
  profile.dirty = true
  saveAdvancements(profile)

proc advancementEntryToJson(entry: AdvancementEntry): JsonNode =
  %* {
    "id": entry.id,
    "progress": entry.progress,
    "unlocked": entry.unlocked,
    "claimed": entry.claimed,
    "unlockedAt": entry.unlockedAt
  }

proc advancementProfileToJson*(profile: AdvancementProfile): JsonNode =
  var entries = newJArray()
  if not profile.isNil:
    for entry in profile.entries:
      entries.add(advancementEntryToJson(entry))

  var recent = newJArray()
  if not profile.isNil:
    for id in profile.recentUnlocks:
      recent.add(%id)

  %* {
    "version": (if profile.isNil: AdvancementProfileVersion else: profile.version),
    "entries": entries,
    "recentUnlocks": recent
  }

proc jsonToAdvancementProfile*(node: JsonNode): AdvancementProfile =
  result = AdvancementProfile(
    version: node.getOrDefault("version").getInt(AdvancementProfileVersion),
    entries: @[],
    recentUnlocks: @[],
    dirty: false
  )

  if node.hasKey("entries"):
    for item in node["entries"]:
      var entry = AdvancementEntry(
        id: item.getOrDefault("id").getStr(""),
        progress: item.getOrDefault("progress").getFloat(0.0).float32,
        unlocked: item.getOrDefault("unlocked").getBool(false),
        claimed: item.getOrDefault("claimed").getBool(false),
        unlockedAt: item.getOrDefault("unlockedAt").getStr("")
      )
      if entry.id.len > 0:
        result.entries.add(entry)

  if node.hasKey("recentUnlocks"):
    for item in node["recentUnlocks"]:
      result.recentUnlocks.add(item.getStr())

  result.ensureAdvancementEntries()

proc saveAdvancements*(profile: AdvancementProfile): bool =
  try:
    if profile.isNil:
      return false
    let jsonString = advancementProfileToJson(profile).pretty()
    writeFile(getAdvancementsPath(), jsonString)
    profile.dirty = false
    echo "Advancements saved successfully to ", getAdvancementsPath()
    true
  except IOError as e:
    echo "Error saving advancements: ", e.msg
    false
  except Exception as e:
    echo "Unexpected error saving advancements: ", e.msg
    false

proc loadAdvancements*(): AdvancementProfile =
  try:
    let path = getAdvancementsPath()
    if not fileExists(path):
      echo "No advancements file found at ", path, ", using defaults"
      return newAdvancementProfile()

    let data = parseJson(readFile(path))
    result = jsonToAdvancementProfile(data)
    echo "Advancements loaded successfully from ", path
  except IOError as e:
    echo "Error loading advancements: ", e.msg
    result = newAdvancementProfile()
  except JsonParsingError as e:
    echo "Error parsing advancements file: ", e.msg
    result = newAdvancementProfile()
  except Exception as e:
    echo "Unexpected error loading advancements: ", e.msg
    result = newAdvancementProfile()
