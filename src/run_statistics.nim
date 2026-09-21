import types, std/tables, times, math, strutils, boss_definitions
import particle_types

# Tracks ALL measurable gameplay data for analysis and visualization
type
  # EVENT TRACKING - Time-series events for detailed timeline analysis
  GameEventType* = enum
    geKill, geDamageTaken, geDamageDealt, gePowerUpChosen, geShopPurchase,
    geWaveComplete, geBossSpawn, geBossDefeat, geNearDeath, geLegendaryUsed,
    geWallPlaced, geCoinCollected, geConsumableUsed

  GameEvent* = object
    timestamp*: float32
    eventType*: GameEventType
    value*: float32
    details*: string
    position*: Vector2f

  # COMBAT STATISTICS
  CombatStats* = object
    shotsFired*, shotsHit*, shotsMissed*: int
    accuracyPercent*: float32
    totalDamageDealt*, totalDamageTaken*, largestSingleHit*: float32
    damageTakenByType*: Table[EnemyType, float32]
    totalKills*, eliteKills*, bossKills*: int
    killsByType*: Table[EnemyType, int]
    criticalHits*, piercingHits*, explosiveHits*, ricochets*, chainLightningProcs*: int
    homingBullets*, piercingBullets*, explosiveBullets*, splitBullets*: int
    # Combo and perfect wave stats
    maxCombo*, totalCombos*, perfectWaves*: int
    comboSum*: int  # For calculating average combo

  # MOVEMENT & SURVIVABILITY
  MovementStats* = object
    totalDistanceTraveled*, averageSpeed*: float32
    positionHeatmap*: seq[Vector2f]
    phaseShiftsUsed*, timeWarpsUsed*, parriesUsed*, successfulParries*: int
    totalPhaseShiftDistance*, totalTimeWarpDuration*: float32
    timeInvincible*, timeAtCriticalHP*, timeAtLowHP*: float32
    nearDeathCount*, hitsTakenCount*: int
    longestNoDamageStreak*, currentNoDamageStreak*, averageTimeBetweenHits*: float32
    damageAvoided*: float32

  # RESOURCE MANAGEMENT
  ResourceStats* = object
    coinsEarned*, coinsSpent*, coinsAtEnd*: int
    coinEfficiency*: float32
    wallsPlaced*, wallsDamaged*, wallsDestroyed*: int
    wallDamageBlocked*: float32
    consumablesCollected*, healthConsumablesUsed*: int
    consumablesByType*: Table[ConsumableType, int]
    shopPurchases*: seq[(float32, string)]
    totalSpentInShop*, shopVisits*: int

  # POWER-UP ANALYTICS
  PowerUpStats* = object
    powerUpsChosen*: seq[(float32, PowerUp)]
    totalPowerUps*, commonPowerUps*, legendaryPowerUps*: int
    damageContribution*: Table[PowerUpType, float32]
    mostEffectivePowerUp*, leastEffectivePowerUp*: PowerUpType
    synergyScore*: float32
    elementalCombo*: seq[PowerUpType]
    hasSynergy*: bool
    level1PowerUps*, level2PowerUps*, level3PowerUps*: int
    healingContribution*: Table[PowerUpType, float32]
    totalHealingFromPowerUps*: float32
    # Healing that did NOT come from a power-up, tracked exactly rather than
    # reconstructed from pickup counts, so the healing panel can list every
    # source without guessing at the formula or the max HP at the time.
    healingFromConsumables*: float32
    healingFromLevelUps*: float32

  # PERFORMANCE METRICS
  PerformanceStats* = object
    waveTimes*: seq[float32]
    averageWaveTime*, fastestWave*, slowestWave*: float32
    peakDPS*, averageDPS*: float32
    dpsHistory*: seq[(float32, float32)]
    currentDPSWindow*: seq[(float32, float32)]
    killsPerMinute*, damagePerShot*, shotEfficiency*: float32
    longestKillStreak*, currentKillStreak*: int
    killStreakHistory*: seq[(float32, int)]

  # COMPARISON METRICS
  ComparisonStats* = object
    accuracyVsOptimal*, dpsVsOptimal*, survivalVsPredicted*: float32
    powerUpQualityScore*, resourceUsageScore*, positioningScore*: float32
    playStyle*: string
    aggressionRating*, cautionRating*: float32

  # COMPLETE RUN STATISTICS
  RunStatistics* = ref object
    gameMode*: GameMode
    startTime*, endTime*: string
    runDuration*: float32
    waveReached*, finalScore*: int
    cheatsUsed*, died*: bool
    combat*: CombatStats
    movement*: MovementStats
    resources*: ResourceStats
    powerUps*: PowerUpStats
    performance*: PerformanceStats
    comparison*: ComparisonStats
    events*: seq[GameEvent]
    finalHP*, finalMaxHP*: float32
    finalCoins*: int
    finalPowerUps*: seq[PowerUp]
    rogueliteFloorReached*: int
    rogueliteRoomsCleared*: int
    rogueliteHeat*: int
    rogueliteEndlessLoop*: int
    rogueliteShardsEarned*: int
    rogueliteStarterKit*: string
    rogueliteRelics*: seq[string]

# INITIALIZATION HELPERS
proc initCombatStats*(): CombatStats =
  CombatStats(
    killsByType: initTable[EnemyType, int](),
    damageTakenByType: initTable[EnemyType, float32]()
  )

proc initMovementStats*(): MovementStats =
  MovementStats(positionHeatmap: @[])

proc initResourceStats*(): ResourceStats =
  ResourceStats(
    consumablesByType: initTable[ConsumableType, int](),
    shopPurchases: @[]
  )

proc initPowerUpStats*(): PowerUpStats =
  PowerUpStats(
    powerUpsChosen: @[],
    damageContribution: initTable[PowerUpType, float32](),
    elementalCombo: @[],
    healingContribution: initTable[PowerUpType, float32]()
  )

proc initPerformanceStats*(): PerformanceStats =
  PerformanceStats(
    waveTimes: @[],
    dpsHistory: @[],
    currentDPSWindow: @[],
    killStreakHistory: @[]
  )

proc initComparisonStats*(): ComparisonStats =
  ComparisonStats(
    playStyle: "Balanced",
    aggressionRating: 50.0,
    cautionRating: 50.0
  )

proc initRunStatistics*(): RunStatistics =
  RunStatistics(
    startTime: $now(),
    endTime: "",
    runDuration: 0.0,
    combat: initCombatStats(),
    movement: initMovementStats(),
    resources: initResourceStats(),
    powerUps: initPowerUpStats(),
    performance: initPerformanceStats(),
    comparison: initComparisonStats(),
    events: @[],
    finalPowerUps: @[],
    rogueliteStarterKit: "",
    rogueliteRelics: @[]
  )

# GLOBAL RUN STATS INSTANCE
var currentRunStats*: RunStatistics = nil

# RUN LIFECYCLE
proc startNewRun*(gameMode: GameMode) =
  currentRunStats = initRunStatistics()
  currentRunStats.gameMode = gameMode
  currentRunStats.startTime = $now()
  echo "[Stats] New run started: ", gameMode

proc calculatePlayStyle*() =
  if currentRunStats.isNil: return
  let run = currentRunStats

  # Priority-ordered classifier
  if run.movement.phaseShiftsUsed >= 5:
    run.comparison.playStyle = "Mobile"
  elif run.combat.totalDamageTaken < 20.0 and run.movement.longestNoDamageStreak > 45.0:
    run.comparison.playStyle = "Defensive"
  elif run.movement.timeAtCriticalHP / max(1.0, run.runDuration) > 0.15:
    run.comparison.playStyle = "Tank"
  elif run.performance.averageDPS > run.performance.peakDPS * 0.6:
    run.comparison.playStyle = "Aggressive"
  else:
    run.comparison.playStyle = "Balanced"

  # Normalize aggression/caution to 0-100 for bar display
  run.comparison.aggressionRating = clamp(
    (run.performance.averageDPS / max(1.0, run.performance.peakDPS)) * 100.0, 0.0, 100.0)
  run.comparison.cautionRating = clamp(
    (run.movement.longestNoDamageStreak / max(1.0, run.runDuration)) * 100.0, 0.0, 100.0)

proc calculateDerivedMetrics*() =
  if currentRunStats.isNil: return

  let totalShots = currentRunStats.combat.shotsFired
  if totalShots > 0:
    currentRunStats.combat.accuracyPercent =
      (currentRunStats.combat.shotsHit.float32 / totalShots.float32) * 100.0

  if currentRunStats.runDuration > 0:
    currentRunStats.performance.averageDPS =
      currentRunStats.combat.totalDamageDealt / currentRunStats.runDuration
    currentRunStats.performance.killsPerMinute =
      (currentRunStats.combat.totalKills.float32 / currentRunStats.runDuration) * 60.0

  if currentRunStats.performance.waveTimes.len > 0:
    currentRunStats.performance.averageWaveTime =
      currentRunStats.performance.waveTimes.sum() / currentRunStats.performance.waveTimes.len.float32
    currentRunStats.performance.fastestWave = currentRunStats.performance.waveTimes.min()
    currentRunStats.performance.slowestWave = currentRunStats.performance.waveTimes.max()

  # Damage per bullet that actually connected
  if currentRunStats.combat.shotsHit > 0:
    currentRunStats.performance.damagePerShot =
      currentRunStats.combat.totalDamageDealt / currentRunStats.combat.shotsHit.float32
  # Expected value per trigger pull including misses
  if currentRunStats.combat.shotsFired > 0:
    currentRunStats.performance.shotEfficiency =
      currentRunStats.combat.totalDamageDealt / currentRunStats.combat.shotsFired.float32

  if currentRunStats.combat.totalKills > 0:
    currentRunStats.resources.coinEfficiency =
      currentRunStats.resources.coinsEarned.float32 / currentRunStats.combat.totalKills.float32

  currentRunStats.resources.coinsAtEnd = currentRunStats.finalCoins

  if currentRunStats.runDuration > 0:
    currentRunStats.movement.averageSpeed =
      currentRunStats.movement.totalDistanceTraveled / currentRunStats.runDuration

  if currentRunStats.movement.hitsTakenCount > 0:
    currentRunStats.movement.averageTimeBetweenHits =
      currentRunStats.runDuration / currentRunStats.movement.hitsTakenCount.float32

  var maxDamage = 0.0
  var minDamage = float32.high
  var maxPowerUp: PowerUpType
  var minPowerUp: PowerUpType
  var foundMax = false
  var foundMin = false

  for powerType, damage in currentRunStats.powerUps.damageContribution:
    if damage > maxDamage:
      maxDamage = damage
      maxPowerUp = powerType
      foundMax = true
    if damage < minDamage and damage > 0:
      minDamage = damage
      minPowerUp = powerType
      foundMin = true

  if foundMax:
    currentRunStats.powerUps.mostEffectivePowerUp = maxPowerUp
  if foundMin:
    currentRunStats.powerUps.leastEffectivePowerUp = minPowerUp

  calculatePlayStyle()
  echo "[Stats] Derived metrics calculated"

# LAST RUN STORAGE
var lastCompletedRun*: RunStatistics = nil

proc cloneRunStatistics*(src: RunStatistics): RunStatistics =
  ## Value-copy of a run's stats. Every field is a value type (seq/Table/string/
  ## scalars), so a single object assignment deep-copies the whole record. Used so
  ## the "last run" snapshot cannot keep mutating when the same run object keeps
  ## accumulating (the checkpoint-continue path resumes into currentRunStats).
  if src.isNil:
    return nil
  result = RunStatistics()
  result[] = src[]

proc endRun*(player: Player, waveReached: int, finalScore: int, cheatsUsed: bool, died: bool) =
  if currentRunStats.isNil:
    return

  currentRunStats.endTime = $now()
  currentRunStats.waveReached = waveReached
  currentRunStats.finalScore = finalScore
  currentRunStats.cheatsUsed = cheatsUsed
  currentRunStats.died = died
  currentRunStats.finalHP = player.hp
  currentRunStats.finalMaxHP = player.maxHp
  currentRunStats.finalCoins = player.coins
  currentRunStats.finalPowerUps = player.powerUps

  calculateDerivedMetrics()
  echo "[Stats] Run ended - Wave: ", waveReached, " Score: ", finalScore

proc updateDPS*(damage: float32) =
  if currentRunStats.isNil: return

  let currentTime = currentRunStats.runDuration
  # Coalesce into the newest 0.1s bucket. Damage now arrives from every source
  # (aura beats, DoT ticks on every burning enemy, orbital contacts), not just
  # bullet hits, so one entry per event would push the window into the thousands
  # and make the delete(0) trim below quadratic every frame.
  if currentRunStats.performance.currentDPSWindow.len > 0 and
     currentTime - currentRunStats.performance.currentDPSWindow[^1][0] < 0.1:
    currentRunStats.performance.currentDPSWindow[^1][1] += damage
  else:
    currentRunStats.performance.currentDPSWindow.add((currentTime, damage))

  while currentRunStats.performance.currentDPSWindow.len > 0 and
        currentTime - currentRunStats.performance.currentDPSWindow[0][0] > 5.0:
    currentRunStats.performance.currentDPSWindow.delete(0)

  var totalDamage = 0.0
  for entry in currentRunStats.performance.currentDPSWindow:
    totalDamage += entry[1]

  let windowDuration =
    if currentRunStats.performance.currentDPSWindow.len > 0:
      max(0.1, currentTime - currentRunStats.performance.currentDPSWindow[0][0])
    else:
      max(0.1, currentTime)
  let currentDPS = totalDamage / windowDuration

  currentRunStats.performance.peakDPS = max(currentRunStats.performance.peakDPS, currentDPS)

  if currentRunStats.performance.dpsHistory.len == 0 or
     currentTime - currentRunStats.performance.dpsHistory[^1][0] >= 1.0:
    currentRunStats.performance.dpsHistory.add((currentTime, currentDPS.float32))

var frameDamageDealt*: float32 = 0.0'f32
  ## Damage dealt since the last takeFrameDamageDealt(). The in-HUD DPS readout
  ## lives on the per-game dopamine state, which this global-state module cannot
  ## reach, so updateGame drains this once a frame instead. Without it the HUD
  ## would still show gun-only DPS while the end-of-run figure covers everything.

proc takeFrameDamageDealt*(): float32 =
  result = frameDamageDealt
  frameDamageDealt = 0.0'f32

proc recordDamageDealt*(damage: float32) =
  ## THE single entry point for "the player dealt damage". Called from
  ## applyEnemyHpDamage (combat.nim), so auras, DoT ticks, orbitals, explosions,
  ## thorns, chain lightning and every activated ability land here alongside
  ## bullet hits -- previously only direct bullet damage was counted, which made
  ## Damage Dealt and DPS meaningless for anything but a pure gun build.
  if damage <= 0.0'f32: return
  frameDamageDealt += damage
  if currentRunStats.isNil: return
  currentRunStats.combat.totalDamageDealt += damage
  updateDPS(damage)

# COMBAT TRACKING
proc recordShotFired*() =
  if currentRunStats.isNil: return
  currentRunStats.combat.shotsFired += 1

proc recordShotHit*(damage: float32, enemyType: EnemyType, isCrit: bool = false,
                    countsAsShot: bool = true) =
  ## Shot bookkeeping only -- the damage itself is booked by recordDamageDealt at
  ## the point it is applied. countsAsShot is false for the second and later
  ## enemies a piercing or ricocheting bullet touches: those are extra contacts
  ## from one trigger pull, not extra shots that connected.
  if currentRunStats.isNil: return

  if countsAsShot:
    currentRunStats.combat.shotsHit += 1
    if isCrit:
      currentRunStats.combat.criticalHits += 1

  if damage > currentRunStats.combat.largestSingleHit:
    currentRunStats.combat.largestSingleHit = damage

proc recordShotMissed*() =
  if currentRunStats.isNil: return
  currentRunStats.combat.shotsMissed += 1

proc recordKill*(enemyType: EnemyType, isElite: bool, isBoss: bool, gameTime: float32, pos: Vector2f) =
  if currentRunStats.isNil: return

  currentRunStats.combat.totalKills += 1

  if not currentRunStats.combat.killsByType.hasKey(enemyType):
    currentRunStats.combat.killsByType[enemyType] = 0
  currentRunStats.combat.killsByType[enemyType] += 1

  if isElite:
    currentRunStats.combat.eliteKills += 1
  if isBoss:
    currentRunStats.combat.bossKills += 1

  currentRunStats.performance.currentKillStreak += 1
  if currentRunStats.performance.currentKillStreak > currentRunStats.performance.longestKillStreak:
    currentRunStats.performance.longestKillStreak = currentRunStats.performance.currentKillStreak

  currentRunStats.events.add(GameEvent(
    timestamp: gameTime,
    eventType: geKill,
    value: 1.0,
    details: $enemyType & (if isElite: " (Elite)" else: "") & (if isBoss: " (Boss)" else: ""),
    position: pos
  ))

proc recordDamageTaken*(damage: float32, enemyType: EnemyType, gameTime: float32, playerPos: Vector2f) =
  if currentRunStats.isNil: return

  currentRunStats.combat.totalDamageTaken += damage
  currentRunStats.movement.hitsTakenCount += 1

  if not currentRunStats.combat.damageTakenByType.hasKey(enemyType):
    currentRunStats.combat.damageTakenByType[enemyType] = 0.0
  currentRunStats.combat.damageTakenByType[enemyType] += damage

  if currentRunStats.movement.currentNoDamageStreak > currentRunStats.movement.longestNoDamageStreak:
    currentRunStats.movement.longestNoDamageStreak = currentRunStats.movement.currentNoDamageStreak
  currentRunStats.movement.currentNoDamageStreak = 0.0
  currentRunStats.performance.currentKillStreak = 0

  currentRunStats.events.add(GameEvent(
    timestamp: gameTime,
    eventType: geDamageTaken,
    value: damage,
    details: $enemyType,
    position: playerPos
  ))

proc recordDamageAvoided*(amount: float32) =
  if currentRunStats.isNil or amount <= 0.0: return
  currentRunStats.movement.damageAvoided += amount

proc recordSpecialMechanic*(mechType: string) =
  if currentRunStats.isNil: return

  case mechType
  of "piercing": currentRunStats.combat.piercingHits += 1
  of "explosive": currentRunStats.combat.explosiveHits += 1
  of "ricochet": currentRunStats.combat.ricochets += 1
  of "chain_lightning": currentRunStats.combat.chainLightningProcs += 1
  of "homing": currentRunStats.combat.homingBullets += 1
  of "split": currentRunStats.combat.splitBullets += 1
  else: discard

# MOVEMENT TRACKING
proc updateMovement*(player: Player, dt: float32, gameTime: float32) =
  if currentRunStats.isNil: return

  let speed = player.vel.length()
  currentRunStats.movement.totalDistanceTraveled += speed * dt

  if gameTime - int(gameTime / 0.5).float32 * 0.5 < dt:
    currentRunStats.movement.positionHeatmap.add(player.pos)

  let hpPercent = player.hp / player.maxHp
  if hpPercent < 0.25:
    currentRunStats.movement.timeAtCriticalHP += dt
  if hpPercent < 0.5:
    currentRunStats.movement.timeAtLowHP += dt

  currentRunStats.movement.currentNoDamageStreak += dt

  if player.invincibilityTimer > 0 or player.phaseShiftInvulnTimer > 0 or player.parryActive:
    currentRunStats.movement.timeInvincible += dt

proc recordLegendaryAbility*(abilityType: string, gameTime: float32, playerPos: Vector2f) =
  if currentRunStats.isNil: return

  case abilityType
  of "phase_shift": currentRunStats.movement.phaseShiftsUsed += 1
  of "time_warp": currentRunStats.movement.timeWarpsUsed += 1
  of "parry": currentRunStats.movement.parriesUsed += 1
  else: discard

  currentRunStats.events.add(GameEvent(
    timestamp: gameTime,
    eventType: geLegendaryUsed,
    value: 0.0,
    details: abilityType,
    position: playerPos
  ))

proc recordSuccessfulParry*() =
  if currentRunStats.isNil: return
  currentRunStats.movement.successfulParries += 1

proc recordNearDeath*(gameTime: float32, playerPos: Vector2f) =
  if currentRunStats.isNil: return

  currentRunStats.movement.nearDeathCount += 1
  currentRunStats.events.add(GameEvent(
    timestamp: gameTime,
    eventType: geNearDeath,
    value: 0.0,
    details: "HP < 10",
    position: playerPos
  ))

# RESOURCE TRACKING
proc recordCoinEarned*(amount: int) =
  if currentRunStats.isNil: return
  currentRunStats.resources.coinsEarned += amount

proc recordCoinSpent*(amount: int, itemName: string, gameTime: float32) =
  if currentRunStats.isNil: return

  currentRunStats.resources.coinsSpent += amount
  currentRunStats.resources.shopPurchases.add((gameTime, itemName))
  currentRunStats.resources.shopVisits += 1

  currentRunStats.events.add(GameEvent(
    timestamp: gameTime,
    eventType: geShopPurchase,
    value: amount.float32,
    details: itemName,
    position: newVector2f(0, 0)
  ))

proc recordRerollSpent*(amount: int) =
  if currentRunStats.isNil: return
  currentRunStats.resources.coinsSpent += amount

proc recordWallPlaced*(gameTime: float32, pos: Vector2f) =
  if currentRunStats.isNil: return

  currentRunStats.resources.wallsPlaced += 1
  currentRunStats.events.add(GameEvent(
    timestamp: gameTime,
    eventType: geWallPlaced,
    value: 1.0,
    details: "Wall",
    position: pos
  ))

proc recordWallDestroyed*(damageBlocked: float32) =
  if currentRunStats.isNil: return

  currentRunStats.resources.wallsDestroyed += 1
  currentRunStats.resources.wallDamageBlocked += damageBlocked

proc recordWallDamaged*() =
  if currentRunStats.isNil: return
  currentRunStats.resources.wallsDamaged += 1

proc recordConsumable*(consumType: ConsumableType) =
  if currentRunStats.isNil: return

  currentRunStats.resources.consumablesCollected += 1

  if not currentRunStats.resources.consumablesByType.hasKey(consumType):
    currentRunStats.resources.consumablesByType[consumType] = 0
  currentRunStats.resources.consumablesByType[consumType] += 1

  if consumType == ctHealth:
    currentRunStats.resources.healthConsumablesUsed += 1

# POWER-UP TRACKING
proc recordPowerUpChosen*(powerUp: PowerUp, gameTime: float32) =
  if currentRunStats.isNil: return

  currentRunStats.powerUps.powerUpsChosen.add((gameTime, powerUp))
  currentRunStats.powerUps.totalPowerUps += 1

  case powerUp.rarity
  of prCommon: currentRunStats.powerUps.commonPowerUps += 1
  of prLegendary: currentRunStats.powerUps.legendaryPowerUps += 1

  case powerUp.level
  of 1: currentRunStats.powerUps.level1PowerUps += 1
  of 2: currentRunStats.powerUps.level2PowerUps += 1
  of 3: currentRunStats.powerUps.level3PowerUps += 1
  else: discard

  currentRunStats.events.add(GameEvent(
    timestamp: gameTime,
    eventType: gePowerUpChosen,
    value: powerUp.level.float32,
    details: $powerUp.powerType & " Lv" & $powerUp.level,
    position: newVector2f(0, 0)
  ))

proc recordPowerUpDamage*(powerType: PowerUpType, damage: float32) =
  if currentRunStats.isNil: return

  if not currentRunStats.powerUps.damageContribution.hasKey(powerType):
    currentRunStats.powerUps.damageContribution[powerType] = 0.0
  currentRunStats.powerUps.damageContribution[powerType] += damage

proc recordPowerUpHealing*(powerType: PowerUpType, amount: float32) =
  if currentRunStats.isNil: return
  if not currentRunStats.powerUps.healingContribution.hasKey(powerType):
    currentRunStats.powerUps.healingContribution[powerType] = 0.0
  currentRunStats.powerUps.healingContribution[powerType] += amount
  currentRunStats.powerUps.totalHealingFromPowerUps += amount

proc trackHealing*(game: Game, source: PowerUpType, healed: float32) =
  ## Books ACTUAL restored HP (the return value of heal()), split between the
  ## power-up that granted it and puHealPower's multiplier. Deriving the split
  ## from healPowerMult here means a heal can never be credited twice, can never
  ## book overheal, and picks up any future source of the multiplier for free.
  if healed <= 0.0'f32: return
  let mult = max(1.0'f32, game.player.healPowerMult)
  let baseShare = healed / mult
  recordPowerUpHealing(source, baseShare)
  let bonus = healed - baseShare
  if bonus > 0.0'f32:
    recordPowerUpHealing(puHealPower, bonus)

proc trackConsumableHealing*(game: Game, healed: float32) =
  ## Health pickups are not a power-up, so their base healing gets its own bucket
  ## instead of being reconstructed in the stats window from a pickup count and a
  ## duplicated formula (which missed Cornucopia's +40% and used end-of-run maxHp).
  if currentRunStats.isNil or healed <= 0.0'f32: return
  let mult = max(1.0'f32, game.player.healPowerMult)
  let baseShare = healed / mult
  currentRunStats.powerUps.healingFromConsumables += baseShare
  let bonus = healed - baseShare
  if bonus > 0.0'f32:
    recordPowerUpHealing(puHealPower, bonus)

proc trackLevelUpHealing*(game: Game, healed: float32) =
  ## The partial heal granted by a run level-up, same split as above.
  if currentRunStats.isNil or healed <= 0.0'f32: return
  let mult = max(1.0'f32, game.player.healPowerMult)
  let baseShare = healed / mult
  currentRunStats.powerUps.healingFromLevelUps += baseShare
  let bonus = healed - baseShare
  if bonus > 0.0'f32:
    recordPowerUpHealing(puHealPower, bonus)

# PERFORMANCE TRACKING
proc recordWaveComplete*(waveNumber: int, waveTime: float32, gameTime: float32) =
  if currentRunStats.isNil: return

  currentRunStats.performance.waveTimes.add(waveTime)

  # Create appropriate description based on whether it's a boss wave
  let waveDescription = if isBossWave(waveNumber):
    "Boss " & $getCustomBossNumber(waveNumber) & " cleared (" & waveTime.formatFloat(ffDecimal, 1) & "s)"
  else:
    "Wave " & $waveNumber & " (" & waveTime.formatFloat(ffDecimal, 1) & "s)"

  currentRunStats.events.add(GameEvent(
    timestamp: gameTime,
    eventType: geWaveComplete,
    value: waveNumber.float32,
    details: waveDescription,
    position: newVector2f(0, 0)
  ))

proc updateRunDuration*(dt: float32) =
  if currentRunStats.isNil: return
  currentRunStats.runDuration += dt

# DERIVED METRICS CALCULATION

proc saveLastCompletedRun*() =
  ## Store a copy of the current run for viewing (save to disk handled externally)
  if not currentRunStats.isNil:
    lastCompletedRun = cloneRunStatistics(currentRunStats)
    echo "[Stats] Last run saved to memory"

proc loadLastCompletedRun*(loadedStats: RunStatistics) =
  ## Load a previously completed run from external source
  if not loadedStats.isNil:
    lastCompletedRun = loadedStats
    echo "[Stats] Last run loaded into memory"
  else:
    echo "[Stats] No previous run data provided"

proc hasLastRunStats*(): bool =
  result = not lastCompletedRun.isNil

proc getLastRunStats*(): RunStatistics =
  result = lastCompletedRun

proc clearLastCompletedRun*() =
  ## Clear the in-memory completed-run snapshot used by stats and advancements.
  lastCompletedRun = nil

# Game Lifecycle
proc initializeRunTracking*(game: Game) =
  startNewRun(game.mode)
  # A run resumed from a checkpoint keeps its wave/floor progress but lost its
  # in-memory statistics with the process. Seed the clock from the restored run
  # time so the per-minute rates (DPS, kills/min) are not divided by the few
  # minutes played since the resume while the wave counter still reads 30.
  currentRunStats.runDuration = max(0.0'f32, runElapsedTime(game))
  game.showRunStatsGraphs = true

proc resumeRunTracking*(game: Game) =
  ## Keep accumulating into the CURRENT run's statistics instead of starting a
  ## fresh record. Used by the game-over "Continue" path: resuming from the last
  ## boss-block checkpoint continues the same run, so kills, power-ups collected,
  ## damage and time must carry over rather than reset to zero.
  ##
  ## Falls back to a fresh record when there is nothing live to resume (the
  ## checkpoint is being continued in a later session, so the stats died with the
  ## process) or when the mode does not match.
  if currentRunStats.isNil or currentRunStats.gameMode != game.mode:
    startNewRun(game.mode)
  else:
    # finalizeRunTracking stamped this run as ended when the player died; the run
    # is live again, so clear the terminal markers. lastCompletedRun already holds
    # its own copy (cloneRunStatistics), so it keeps showing the death snapshot.
    currentRunStats.endTime = ""
    currentRunStats.died = false
    echo "[Stats] Run resumed from checkpoint - carrying accumulated stats"
  game.showRunStatsGraphs = true

proc finalizeRunTracking*(game: Game, died: bool) =
  ## died is false for the wave-60 victory screen and for a banked roguelite cash
  ## out; it used to be hardcoded true, so every won run was recorded as a death.
  let waveReached =
    if game.mode == gmWaveBased:
      game.currentWave
    elif game.mode == gmRoguelite and game.rogueliteRun != nil:
      game.rogueliteRun.totalRoomsCleared
    else:
      int(runElapsedTime(game) / 60)
  let finalScore = game.player.kills
  if game.mode == gmRoguelite and game.rogueliteRun != nil and not currentRunStats.isNil:
    currentRunStats.rogueliteFloorReached = game.rogueliteRun.floorNumber
    currentRunStats.rogueliteRoomsCleared = game.rogueliteRun.totalRoomsCleared
    currentRunStats.rogueliteHeat = game.rogueliteRun.heat
    currentRunStats.rogueliteEndlessLoop = game.rogueliteRun.endlessLoop
    currentRunStats.rogueliteShardsEarned = game.rogueliteRun.shardsEarned
    currentRunStats.rogueliteStarterKit = $game.rogueliteRun.starterKit
    currentRunStats.rogueliteRelics = @[]
    for relic in game.rogueliteRun.relics:
      currentRunStats.rogueliteRelics.add(relic.name)
  endRun(game.player, waveReached, finalScore, game.cheatsUsed, died)

proc hasValidRunStats*(): bool =
  result = not currentRunStats.isNil and currentRunStats.runDuration > 0

# Combat Integration
proc trackBulletFired*(game: Game) =
  ## Counts one player projectile. EVERY player bullet must pass through here,
  ## including the ones spawned by split, ricochet, echo, radial burst and wall
  ## turrets: their contacts are counted as hits, so leaving them out of the
  ## fired count is what let accuracy climb past 100%.
  recordShotFired()
  game.dopamine.waveStats.shotsFired += 1

proc trackBulletHit*(game: Game, bullet: Bullet, enemy: Enemy, damage: float32) =
  ## One trigger pull is one shot however many enemies the bullet goes on to
  ## touch, so only the first contact counts towards shotsHit (and the crit
  ## tally). Without this, piercing and ricochet builds report accuracy well
  ## over 100%.
  let firstContact = not bullet.hasCountedHit
  if firstContact:
    bullet.hasCountedHit = true
    game.dopamine.waveStats.shotsHit += 1
  recordShotHit(damage, enemy.enemyType, bullet.wasCrit, countsAsShot = firstContact)

  if bullet.isPiercing: recordSpecialMechanic("piercing")
  if bullet.isExplosive: recordSpecialMechanic("explosive")
  if bullet.isHoming: recordSpecialMechanic("homing")
  if bullet.hasSplit: recordSpecialMechanic("split")

proc trackBulletDespawn*(game: Game, bullet: Bullet, hitEnemy: bool) =
  if not hitEnemy and bullet.piercedEnemies == 0 and bullet.lifetime > 0.1:
    recordShotMissed()

proc trackEnemyKilled*(game: Game, enemy: Enemy) =
  recordKill(enemy.enemyType, enemy.isElite, enemy.isBoss, game.time, enemy.pos)

const NearDeathHpFraction = 0.15'f32
  ## Near-death is a FRACTION of max HP. The old absolute "< 10" was written in
  ## display units (BALANCE_MULTIPLIER = 100) but compared against internal HP,
  ## whose starting maximum is 9 -- so every hit in the run logged a near-death.

proc trackPlayerDamage*(game: Game, enemyType: EnemyType) =
  ## Books what the hit ACTUALLY cost, read from player.lastDamageTaken rather
  ## than the damage that was offered. A hit that was dodged, parried, blocked by
  ## a shield charge or eaten by Celestial Veil leaves that at 0, so it is
  ## recorded purely as avoided damage and no longer also lands here -- which is
  ## what used to break the hit count, the no-damage streak and the kill streak.
  let damage = game.player.lastDamageTaken
  if damage <= 0.0'f32:
    return

  recordDamageTaken(damage, enemyType, game.time, game.player.pos)
  game.dopamine.waveStats.damageTaken += damage
  game.dopamine.waveStats.isPerfect = false

  if game.player.hp > 0 and game.player.hp < game.player.maxHp * NearDeathHpFraction:
    recordNearDeath(game.time, game.player.pos)

# Combo and Perfect Wave Integration
proc trackCombo*(game: Game, comboCount: int) =
  ## Track combo statistics
  if currentRunStats.isNil:
    return

  # Track max combo
  if comboCount > currentRunStats.combat.maxCombo:
    currentRunStats.combat.maxCombo = comboCount

  # Add to sum for average calculation (when combo ends)
  if comboCount >= 2:  # Only count actual combos (2+)
    currentRunStats.combat.totalCombos += 1
    currentRunStats.combat.comboSum += comboCount

proc trackPerfectWave*() =
  ## Track when a perfect wave is achieved
  if currentRunStats.isNil:
    return
  currentRunStats.combat.perfectWaves += 1

# Movement Integration
proc trackMovementFrame*(game: Game, dt: float32) =
  updateMovement(game.player, dt, game.time)
  updateRunDuration(dt)

proc trackPhaseShift*(game: Game, distanceTraveled: float32) =
  recordLegendaryAbility("phase_shift", game.time, game.player.pos)
  if currentRunStats.isNil: return
  currentRunStats.movement.totalPhaseShiftDistance += distanceTraveled

proc trackTimeWarp*(game: Game, duration: float32) =
  recordLegendaryAbility("time_warp", game.time, game.player.pos)
  if currentRunStats.isNil: return
  currentRunStats.movement.totalTimeWarpDuration += duration

proc trackDamageAvoided*(game: Game) =
  recordDamageAvoided(game.player.lastDamageAvoided)

proc trackParry*(game: Game) =
  recordLegendaryAbility("parry", game.time, game.player.pos)

proc trackParrySuccess*(game: Game) =
  recordSuccessfulParry()

# Resource Integration
proc trackCoinPickup*(game: Game, amount: int) =
  recordCoinEarned(amount)

proc trackShopPurchase*(game: Game, itemName: string, cost: int) =
  recordCoinSpent(cost, itemName, game.time)

proc trackWallPlacement*(game: Game, pos: Vector2f) =
  recordWallPlaced(game.time, pos)

proc trackWallDestruction*(game: Game, damageBlocked: float32) =
  recordWallDestroyed(damageBlocked)

proc trackWallDamaged*(game: Game) =
  recordWallDamaged()

proc trackConsumablePickup*(game: Game, consumType: ConsumableType) =
  recordConsumable(consumType)

# Power-Up Integration
proc trackPowerUpSelection*(game: Game, powerUp: PowerUp) =
  recordPowerUpChosen(powerUp, game.time)

proc trackPowerUpDamage*(game: Game, powerType: PowerUpType, damage: float32) =
  recordPowerUpDamage(powerType, damage)

proc trackPowerUpDamageWithMastery*(game: Game, basePower, masteryPower: PowerUpType,
                                    damage: float32, masteryMult: float32) =
  ## Splits one hit between the ability and the elemental mastery amplifying it,
  ## instead of handing the FULL post-mastery damage to both. With
  ## MasteryDamageMult = 2.5 the old double-credit reported 250% of the hit to the
  ## aura plus another 250% to the mastery; the mastery's real share is the part
  ## above 1x, and the ability keeps the rest.
  ##
  ## masteryMult of 1.0 means the mastery did not touch this hit (frost/blood orb
  ## masteries pay out as chill and lifesteal, fire/poison through the DoT), so it
  ## is credited nothing rather than the whole hit.
  if damage <= 0.0'f32: return
  if masteryMult > 1.0'f32:
    let baseShare = damage / masteryMult
    recordPowerUpDamage(basePower, baseShare)
    recordPowerUpDamage(masteryPower, damage - baseShare)
  else:
    recordPowerUpDamage(basePower, damage)

# Performance Integration
proc trackWaveCompletion*(game: Game, waveNumber: int, waveTime: float32) =
  recordWaveComplete(waveNumber, waveTime, game.time)
