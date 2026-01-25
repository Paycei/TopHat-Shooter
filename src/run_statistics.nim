import types, std/tables, times, math, strutils, boss_definitions

# Forward declarations for functions defined later in file
proc calculateDerivedMetrics*()
proc updateDPS*(damage: float32)
proc calculatePlayStyle*()

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
    criticalHits*, piercingShots*, explosiveKills*, ricochets*, chainLightningProcs*: int
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
    killContribution*: Table[PowerUpType, int]
    mostEffectivePowerUp*, leastEffectivePowerUp*: PowerUpType
    synergyScore*: float32
    elementalCombo*: seq[PowerUpType]
    hasSynergy*: bool
    level1PowerUps*, level2PowerUps*, level3PowerUps*: int
  
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
    killContribution: initTable[PowerUpType, int](),
    elementalCombo: @[]
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
    finalPowerUps: @[]
  )

# GLOBAL RUN STATS INSTANCE
var currentRunStats*: RunStatistics = nil

# RUN LIFECYCLE
proc startNewRun*(gameMode: GameMode) =
  currentRunStats = initRunStatistics()
  currentRunStats.gameMode = gameMode
  currentRunStats.startTime = $now()
  echo "[Stats] New run started: ", gameMode

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

# COMBAT TRACKING
proc recordShotFired*() =
  if currentRunStats.isNil: return
  currentRunStats.combat.shotsFired += 1

proc recordShotHit*(damage: float32, enemyType: EnemyType, isCrit: bool = false) =
  if currentRunStats.isNil: return
  
  currentRunStats.combat.shotsHit += 1
  currentRunStats.combat.totalDamageDealt += damage
  
  if damage > currentRunStats.combat.largestSingleHit:
    currentRunStats.combat.largestSingleHit = damage
  
  if isCrit:
    currentRunStats.combat.criticalHits += 1
  
  updateDPS(damage)

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
  
  # Kill streak tracking removed
  # currentRunStats.performance.currentKillStreak += 1
  # if currentRunStats.performance.currentKillStreak > currentRunStats.performance.longestKillStreak:
  #   currentRunStats.performance.longestKillStreak = currentRunStats.performance.currentKillStreak
  
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
  # Kill streak tracking removed
  # currentRunStats.performance.currentKillStreak = 0
  
  currentRunStats.events.add(GameEvent(
    timestamp: gameTime,
    eventType: geDamageTaken,
    value: damage,
    details: $enemyType,
    position: playerPos
  ))

proc recordSpecialMechanic*(mechType: string) =
  if currentRunStats.isNil: return
  
  case mechType
  of "piercing": currentRunStats.combat.piercingShots += 1
  of "explosive": currentRunStats.combat.explosiveKills += 1
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

proc recordPowerUpKill*(powerType: PowerUpType) =
  if currentRunStats.isNil: return
  
  if not currentRunStats.powerUps.killContribution.hasKey(powerType):
    currentRunStats.powerUps.killContribution[powerType] = 0
  currentRunStats.powerUps.killContribution[powerType] += 1

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

proc updateDPS*(damage: float32) =
  if currentRunStats.isNil: return
  
  let currentTime = currentRunStats.runDuration
  currentRunStats.performance.currentDPSWindow.add((currentTime, damage))
  
  while currentRunStats.performance.currentDPSWindow.len > 0 and 
        currentTime - currentRunStats.performance.currentDPSWindow[0][0] > 5.0:
    currentRunStats.performance.currentDPSWindow.delete(0)
  
  var totalDamage = 0.0
  for entry in currentRunStats.performance.currentDPSWindow:
    totalDamage += entry[1]
  
  let windowDuration = min(5.0, currentTime)
  let currentDPS = totalDamage / windowDuration
  
  currentRunStats.performance.peakDPS = max(currentRunStats.performance.peakDPS, currentDPS)
  
  if currentRunStats.performance.dpsHistory.len == 0 or 
     currentTime - currentRunStats.performance.dpsHistory[^1][0] >= 1.0:
    currentRunStats.performance.dpsHistory.add((currentTime, currentDPS.float32))

proc updateRunDuration*(dt: float32) =
  if currentRunStats.isNil: return
  currentRunStats.runDuration += dt

# DERIVED METRICS CALCULATION
proc calculatePlayStyle*() =
  if currentRunStats.isNil: return
  
  var aggressionScore = 0.0
  if currentRunStats.performance.averageDPS > 50: aggressionScore += 30
  if currentRunStats.combat.accuracyPercent > 60: aggressionScore += 20
  if currentRunStats.movement.averageSpeed > 100: aggressionScore += 20
  if currentRunStats.movement.timeAtCriticalHP / currentRunStats.runDuration > 0.1: aggressionScore += 30
  
  var cautionScore = 0.0
  if currentRunStats.combat.totalDamageTaken < 50: cautionScore += 30
  if currentRunStats.movement.longestNoDamageStreak > 30: cautionScore += 25
  if currentRunStats.resources.wallsPlaced > 5: cautionScore += 20
  if currentRunStats.resources.coinsAtEnd > 100: cautionScore += 25
  
  currentRunStats.comparison.aggressionRating = aggressionScore
  currentRunStats.comparison.cautionRating = cautionScore
  
  if aggressionScore > 70:
    currentRunStats.comparison.playStyle = "Aggressive"
  elif cautionScore > 70:
    currentRunStats.comparison.playStyle = "Defensive"
  elif currentRunStats.movement.phaseShiftsUsed > 10:
    currentRunStats.comparison.playStyle = "Mobile"
  elif currentRunStats.movement.timeAtCriticalHP > 10:
    currentRunStats.comparison.playStyle = "Tank"
  else:
    currentRunStats.comparison.playStyle = "Balanced"

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
  
  if currentRunStats.combat.shotsFired > 0:
    currentRunStats.performance.damagePerShot = 
      currentRunStats.combat.totalDamageDealt / currentRunStats.combat.shotsFired.float32
    currentRunStats.performance.shotEfficiency = 
      currentRunStats.combat.totalDamageDealt / currentRunStats.combat.shotsFired.float32
  
  if currentRunStats.combat.totalKills > 0:
    currentRunStats.resources.coinEfficiency = 
      currentRunStats.resources.coinsEarned.float32 / currentRunStats.combat.totalKills.float32
  
  currentRunStats.resources.coinsAtEnd = 
    currentRunStats.resources.coinsEarned - currentRunStats.resources.coinsSpent
  
  if currentRunStats.runDuration > 0:
    currentRunStats.movement.averageSpeed = 
      currentRunStats.movement.totalDistanceTraveled / currentRunStats.runDuration
  
  if currentRunStats.movement.hitsTakenCount > 0:
    currentRunStats.movement.averageTimeBetweenHits = 
      currentRunStats.runDuration / currentRunStats.movement.hitsTakenCount.float32
  
  var maxDamage = 0.0
  var minDamage = float32.high
  var maxPowerUp = puDoubleShot
  var minPowerUp = puDoubleShot
  
  for powerType, damage in currentRunStats.powerUps.damageContribution:
    if damage > maxDamage:
      maxDamage = damage
      maxPowerUp = powerType
    if damage < minDamage and damage > 0:
      minDamage = damage
      minPowerUp = powerType
  
  if maxDamage > 0:
    currentRunStats.powerUps.mostEffectivePowerUp = maxPowerUp
    currentRunStats.powerUps.leastEffectivePowerUp = minPowerUp
  
  calculatePlayStyle()
  echo "[Stats] Derived metrics calculated"

# LAST RUN STORAGE
var lastCompletedRun*: RunStatistics = nil

proc saveLastCompletedRun*() =
  ## Store a copy of the current run for viewing (save to disk handled externally)
  if not currentRunStats.isNil:
    lastCompletedRun = currentRunStats
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

# Game Lifecycle
proc initializeRunTracking*(game: Game) =
  startNewRun(game.mode)
  game.showRunStatsGraphs = true

proc finalizeRunTracking*(game: Game) =
  let waveReached = if game.mode == gmWaveBased: game.currentWave else: int(game.time / 60)
  let finalScore = game.player.kills
  endRun(game.player, waveReached, finalScore, game.cheatsUsed, true)

proc hasValidRunStats*(): bool =
  result = not currentRunStats.isNil and currentRunStats.runDuration > 0

# Combat Integration
proc trackBulletFired*(game: Game) =
  recordShotFired()

proc trackBulletHit*(game: Game, bullet: Bullet, enemy: Enemy, damage: float32) =
  let isCrit = damage > bullet.damage * 1.5
  recordShotHit(damage, enemy.enemyType, isCrit)
  
  if bullet.isPiercing: recordSpecialMechanic("piercing")
  if bullet.isExplosive: recordSpecialMechanic("explosive")
  if bullet.isHoming: recordSpecialMechanic("homing")
  if bullet.hasSplit: recordSpecialMechanic("split")

proc trackBulletDespawn*(game: Game, bullet: Bullet, hitEnemy: bool) =
  if not hitEnemy and bullet.lifetime > 0.1:
    recordShotMissed()

proc trackEnemyKilled*(game: Game, enemy: Enemy) =
  recordKill(enemy.enemyType, enemy.isElite, enemy.isBoss, game.time, enemy.pos)

proc trackPlayerDamage*(game: Game, damage: float32, enemyType: EnemyType) =
  recordDamageTaken(damage, enemyType, game.time, game.player.pos)
  
  if game.player.hp < 10 and game.player.hp > 0:
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

proc trackPhaseShift*(game: Game) =
  recordLegendaryAbility("phase_shift", game.time, game.player.pos)

proc trackTimeWarp*(game: Game) =
  recordLegendaryAbility("time_warp", game.time, game.player.pos)

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

proc trackPowerUpKill*(game: Game, powerType: PowerUpType) =
  recordPowerUpKill(powerType)

# Performance Integration
proc trackWaveCompletion*(game: Game, waveNumber: int, waveTime: float32) =
  recordWaveComplete(waveNumber, waveTime, game.time)
