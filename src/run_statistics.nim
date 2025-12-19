# ============================================================================
# RUN STATISTICS TRACKING
# Core tracking logic for per-run statistics
# Called from game update loops to record gameplay data
# ============================================================================

import run_statistics_types, types, math, times, std/tables, strutils, save_system

export run_statistics_types

# Forward declarations
proc calculateDerivedMetrics*()
proc updateDPS*(damage: float32)
proc calculatePlayStyle*()

# ============================================================================
# GLOBAL RUN STATS INSTANCE
# ============================================================================

var currentRunStats*: RunStatistics = nil

# ============================================================================
# RUN LIFECYCLE
# ============================================================================

proc startNewRun*(gameMode: GameMode) =
  ## Initialize statistics tracking for a new game run
  currentRunStats = initRunStatistics()
  currentRunStats.gameMode = gameMode
  currentRunStats.startTime = $now()
  
  echo "[Stats] New run started: ", gameMode

proc endRun*(player: Player, waveReached: int, finalScore: int, cheatsUsed: bool, died: bool) =
  ## Finalize statistics at end of run
  if currentRunStats.isNil:
    return
  
  currentRunStats.endTime = $now()
  currentRunStats.waveReached = waveReached
  currentRunStats.finalScore = finalScore
  currentRunStats.cheatsUsed = cheatsUsed
  currentRunStats.died = died
  
  # Capture final player state
  currentRunStats.finalHP = player.hp
  currentRunStats.finalMaxHP = player.maxHp
  currentRunStats.finalCoins = player.coins
  currentRunStats.finalPowerUps = player.powerUps
  
  # Calculate derived metrics
  calculateDerivedMetrics()
  
  echo "[Stats] Run ended - Wave: ", waveReached, " Score: ", finalScore

# ============================================================================
# COMBAT TRACKING
# ============================================================================

proc recordShotFired*() =
  ## Track a bullet being fired by player
  if currentRunStats.isNil: return
  currentRunStats.combat.shotsFired += 1

proc recordShotHit*(damage: float32, enemyType: EnemyType, isCrit: bool = false) =
  ## Track a bullet hitting an enemy
  if currentRunStats.isNil: return
  
  currentRunStats.combat.shotsHit += 1
  currentRunStats.combat.totalDamageDealt += damage
  
  if damage > currentRunStats.combat.largestSingleHit:
    currentRunStats.combat.largestSingleHit = damage
  
  if isCrit:
    currentRunStats.combat.criticalHits += 1
  
  # Update DPS tracking
  updateDPS(damage)

proc recordShotMissed*() =
  ## Track a bullet missing (despawned without hitting)
  if currentRunStats.isNil: return
  currentRunStats.combat.shotsMissed += 1

proc recordKill*(enemyType: EnemyType, isElite: bool, isBoss: bool, gameTime: float32, pos: Vector2f) =
  ## Track an enemy kill
  if currentRunStats.isNil: return
  
  currentRunStats.combat.totalKills += 1
  
  # Track by type
  if not currentRunStats.combat.killsByType.hasKey(enemyType):
    currentRunStats.combat.killsByType[enemyType] = 0
  currentRunStats.combat.killsByType[enemyType] += 1
  
  # Special enemy types
  if isElite:
    currentRunStats.combat.eliteKills += 1
  if isBoss:
    currentRunStats.combat.bossKills += 1
  
  # Kill streak tracking
  currentRunStats.performance.currentKillStreak += 1
  if currentRunStats.performance.currentKillStreak > currentRunStats.performance.longestKillStreak:
    currentRunStats.performance.longestKillStreak = currentRunStats.performance.currentKillStreak
  
  # Add event
  currentRunStats.events.add(GameEvent(
    timestamp: gameTime,
    eventType: geKill,
    value: 1.0,
    details: $enemyType & (if isElite: " (Elite)" else: "") & (if isBoss: " (Boss)" else: ""),
    position: pos
  ))

proc recordDamageTaken*(damage: float32, enemyType: EnemyType, gameTime: float32, playerPos: Vector2f) =
  ## Track damage received by player
  if currentRunStats.isNil: return
  
  currentRunStats.combat.totalDamageTaken += damage
  currentRunStats.movement.hitsTakenCount += 1
  
  # Track by enemy type
  if not currentRunStats.combat.damageTakenByType.hasKey(enemyType):
    currentRunStats.combat.damageTakenByType[enemyType] = 0.0
  currentRunStats.combat.damageTakenByType[enemyType] += damage
  
  # Reset no-damage streak
  if currentRunStats.movement.currentNoDamageStreak > currentRunStats.movement.longestNoDamageStreak:
    currentRunStats.movement.longestNoDamageStreak = currentRunStats.movement.currentNoDamageStreak
  currentRunStats.movement.currentNoDamageStreak = 0.0
  
  # Reset kill streak
  currentRunStats.performance.currentKillStreak = 0
  
  # Add event
  currentRunStats.events.add(GameEvent(
    timestamp: gameTime,
    eventType: geDamageTaken,
    value: damage,
    details: $enemyType,
    position: playerPos
  ))

proc recordSpecialMechanic*(mechType: string) =
  ## Track special bullet mechanics being used
  if currentRunStats.isNil: return
  
  case mechType
  of "piercing":
    currentRunStats.combat.piercingShots += 1
  of "explosive":
    currentRunStats.combat.explosiveKills += 1
  of "ricochet":
    currentRunStats.combat.ricochets += 1
  of "chain_lightning":
    currentRunStats.combat.chainLightningProcs += 1
  of "homing":
    currentRunStats.combat.homingBullets += 1
  of "split":
    currentRunStats.combat.splitBullets += 1
  else:
    discard

# ============================================================================
# MOVEMENT TRACKING
# ============================================================================

proc updateMovement*(player: Player, dt: float32, gameTime: float32) =
  ## Track player movement and positioning
  if currentRunStats.isNil: return
  
  # Calculate distance traveled
  let speed = player.vel.length()
  currentRunStats.movement.totalDistanceTraveled += speed * dt
  
  # Sample position for heatmap (every 0.5 seconds)
  if gameTime - int(gameTime / 0.5).float32 * 0.5 < dt:
    currentRunStats.movement.positionHeatmap.add(player.pos)
  
  # Track time at low HP
  let hpPercent = player.hp / player.maxHp
  if hpPercent < 0.25:
    currentRunStats.movement.timeAtCriticalHP += dt
  if hpPercent < 0.5:
    currentRunStats.movement.timeAtLowHP += dt
  
  # Update no-damage streak
  currentRunStats.movement.currentNoDamageStreak += dt
  
  # Track invincibility time
  if player.invincibilityTimer > 0 or player.phaseShiftInvulnTimer > 0 or player.parryActive:
    currentRunStats.movement.timeInvincible += dt

proc recordLegendaryAbility*(abilityType: string, gameTime: float32, playerPos: Vector2f) =
  ## Track legendary ability usage
  if currentRunStats.isNil: return
  
  case abilityType
  of "phase_shift":
    currentRunStats.movement.phaseShiftsUsed += 1
  of "time_warp":
    currentRunStats.movement.timeWarpsUsed += 1
  of "parry":
    currentRunStats.movement.parriesUsed += 1
  else:
    discard
  
  # Add event
  currentRunStats.events.add(GameEvent(
    timestamp: gameTime,
    eventType: geLegendaryUsed,
    value: 0.0,
    details: abilityType,
    position: playerPos
  ))

proc recordSuccessfulParry*() =
  ## Track a bullet successfully reflected by parry
  if currentRunStats.isNil: return
  currentRunStats.movement.successfulParries += 1

proc recordNearDeath*(gameTime: float32, playerPos: Vector2f) =
  ## Track HP dropping below 10
  if currentRunStats.isNil: return
  
  currentRunStats.movement.nearDeathCount += 1
  
  currentRunStats.events.add(GameEvent(
    timestamp: gameTime,
    eventType: geNearDeath,
    value: 0.0,
    details: "HP < 10",
    position: playerPos
  ))

# ============================================================================
# RESOURCE TRACKING
# ============================================================================

proc recordCoinEarned*(amount: int) =
  ## Track coins collected
  if currentRunStats.isNil: return
  currentRunStats.resources.coinsEarned += amount

proc recordCoinSpent*(amount: int, itemName: string, gameTime: float32) =
  ## Track coins spent in shop
  if currentRunStats.isNil: return
  
  currentRunStats.resources.coinsSpent += amount
  currentRunStats.resources.shopPurchases.add((gameTime, itemName))
  currentRunStats.resources.shopVisits += 1
  
  currentRunStats.events.add(GameEvent(
    timestamp: gameTime,
    eventType: geShopPurchase,
    value: amount.float32,
    details: itemName,
    position: newVector2f(0, 0)  # Shop has no position
  ))

proc recordWallPlaced*(gameTime: float32, pos: Vector2f) =
  ## Track wall placement
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
  ## Track wall destruction
  if currentRunStats.isNil: return
  
  currentRunStats.resources.wallsDestroyed += 1
  currentRunStats.resources.wallDamageBlocked += damageBlocked

proc recordWallDamaged*() =
  ## Track wall taking damage (but not destroyed)
  if currentRunStats.isNil: return
  
  currentRunStats.resources.wallsDamaged += 1

proc recordConsumable*(consumType: ConsumableType) =
  ## Track consumable pickup
  if currentRunStats.isNil: return
  
  currentRunStats.resources.consumablesCollected += 1
  
  if not currentRunStats.resources.consumablesByType.hasKey(consumType):
    currentRunStats.resources.consumablesByType[consumType] = 0
  currentRunStats.resources.consumablesByType[consumType] += 1
  
  if consumType == ctHealth:
    currentRunStats.resources.healthConsumablesUsed += 1

# ============================================================================
# POWER-UP TRACKING
# ============================================================================

proc recordPowerUpChosen*(powerUp: PowerUp, gameTime: float32) =
  ## Track power-up selection
  if currentRunStats.isNil: return
  
  currentRunStats.powerUps.powerUpsChosen.add((gameTime, powerUp))
  currentRunStats.powerUps.totalPowerUps += 1
  
  case powerUp.rarity
  of prCommon:
    currentRunStats.powerUps.commonPowerUps += 1
  of prLegendary:
    currentRunStats.powerUps.legendaryPowerUps += 1
  
  case powerUp.level
  of 1:
    currentRunStats.powerUps.level1PowerUps += 1
  of 2:
    currentRunStats.powerUps.level2PowerUps += 1
  of 3:
    currentRunStats.powerUps.level3PowerUps += 1
  else:
    discard
  
  currentRunStats.events.add(GameEvent(
    timestamp: gameTime,
    eventType: gePowerUpChosen,
    value: powerUp.level.float32,
    details: $powerUp.powerType & " Lv" & $powerUp.level,
    position: newVector2f(0, 0)
  ))

proc recordPowerUpDamage*(powerType: PowerUpType, damage: float32) =
  ## Track damage contribution from specific power-up
  if currentRunStats.isNil: return
  
  if not currentRunStats.powerUps.damageContribution.hasKey(powerType):
    currentRunStats.powerUps.damageContribution[powerType] = 0.0
  currentRunStats.powerUps.damageContribution[powerType] += damage

proc recordPowerUpKill*(powerType: PowerUpType) =
  ## Track kills attributed to specific power-up
  if currentRunStats.isNil: return
  
  if not currentRunStats.powerUps.killContribution.hasKey(powerType):
    currentRunStats.powerUps.killContribution[powerType] = 0
  currentRunStats.powerUps.killContribution[powerType] += 1

# ============================================================================
# PERFORMANCE TRACKING
# ============================================================================

proc recordWaveComplete*(waveNumber: int, waveTime: float32, gameTime: float32) =
  ## Track wave completion
  if currentRunStats.isNil: return
  
  currentRunStats.performance.waveTimes.add(waveTime)
  
  currentRunStats.events.add(GameEvent(
    timestamp: gameTime,
    eventType: geWaveComplete,
    value: waveNumber.float32,
    details: "Wave " & $waveNumber & " (" & waveTime.formatFloat(ffDecimal, 1) & "s)",
    position: newVector2f(0, 0)
  ))

proc updateDPS*(damage: float32) =
  ## Update DPS tracking (called on damage dealt)
  if currentRunStats.isNil: return
  
  let currentTime = currentRunStats.runDuration
  
  # Add to rolling window (last 5 seconds)
  currentRunStats.performance.currentDPSWindow.add((currentTime, damage))
  
  # Remove old entries
  while currentRunStats.performance.currentDPSWindow.len > 0 and 
        currentTime - currentRunStats.performance.currentDPSWindow[0][0] > 5.0:
    currentRunStats.performance.currentDPSWindow.delete(0)
  
  # Calculate current DPS
  var totalDamage = 0.0
  for entry in currentRunStats.performance.currentDPSWindow:
    totalDamage += entry[1]
  
  let windowDuration = min(5.0, currentTime)
  let currentDPS = totalDamage / windowDuration
  
  currentRunStats.performance.peakDPS = max(currentRunStats.performance.peakDPS, currentDPS)
  
  # Sample DPS history every second
  if currentRunStats.performance.dpsHistory.len == 0 or 
     currentTime - currentRunStats.performance.dpsHistory[^1][0] >= 1.0:
    currentRunStats.performance.dpsHistory.add((currentTime, currentDPS.float32))

proc updateRunDuration*(dt: float32) =
  ## Update total run time
  if currentRunStats.isNil: return
  currentRunStats.runDuration += dt

# ============================================================================
# DERIVED METRICS CALCULATION
# ============================================================================

proc calculateDerivedMetrics*() =
  ## Calculate all derived statistics at end of run
  if currentRunStats.isNil: return
  
  # Combat accuracy
  let totalShots = currentRunStats.combat.shotsFired
  if totalShots > 0:
    currentRunStats.combat.accuracyPercent = 
      (currentRunStats.combat.shotsHit.float32 / totalShots.float32) * 100.0
  
  # Average DPS
  if currentRunStats.runDuration > 0:
    currentRunStats.performance.averageDPS = 
      currentRunStats.combat.totalDamageDealt / currentRunStats.runDuration
    
    # Kills per minute
    currentRunStats.performance.killsPerMinute = 
      (currentRunStats.combat.totalKills.float32 / currentRunStats.runDuration) * 60.0
  
  # Wave time stats
  if currentRunStats.performance.waveTimes.len > 0:
    currentRunStats.performance.averageWaveTime = 
      currentRunStats.performance.waveTimes.sum() / currentRunStats.performance.waveTimes.len.float32
    currentRunStats.performance.fastestWave = currentRunStats.performance.waveTimes.min()
    currentRunStats.performance.slowestWave = currentRunStats.performance.waveTimes.max()
  
  # Shot efficiency
  if currentRunStats.combat.shotsFired > 0:
    currentRunStats.performance.damagePerShot = 
      currentRunStats.combat.totalDamageDealt / currentRunStats.combat.shotsFired.float32
    currentRunStats.performance.shotEfficiency = 
      currentRunStats.combat.totalDamageDealt / currentRunStats.combat.shotsFired.float32
  
  # Resource efficiency
  if currentRunStats.combat.totalKills > 0:
    currentRunStats.resources.coinEfficiency = 
      currentRunStats.resources.coinsEarned.float32 / currentRunStats.combat.totalKills.float32
  
  currentRunStats.resources.coinsAtEnd = 
    currentRunStats.resources.coinsEarned - currentRunStats.resources.coinsSpent
  
  # Movement averages
  if currentRunStats.runDuration > 0:
    currentRunStats.movement.averageSpeed = 
      currentRunStats.movement.totalDistanceTraveled / currentRunStats.runDuration
  
  if currentRunStats.movement.hitsTakenCount > 0:
    currentRunStats.movement.averageTimeBetweenHits = 
      currentRunStats.runDuration / currentRunStats.movement.hitsTakenCount.float32
  
  # Power-up effectiveness (find most/least effective)
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
  
  # Play style analysis
  calculatePlayStyle()
  
  echo "[Stats] Derived metrics calculated"

proc calculatePlayStyle*() =
  ## Analyze play style based on behavior patterns
  if currentRunStats.isNil: return
  
  # Aggression rating: based on DPS, accuracy, movement
  var aggressionScore = 0.0
  
  # High DPS = aggressive
  if currentRunStats.performance.averageDPS > 50:
    aggressionScore += 30
  
  # High accuracy = aggressive (taking aimed shots)
  if currentRunStats.combat.accuracyPercent > 60:
    aggressionScore += 20
  
  # Lots of movement = aggressive
  if currentRunStats.movement.averageSpeed > 100:
    aggressionScore += 20
  
  # Close-range time = aggressive
  if currentRunStats.movement.timeAtCriticalHP / currentRunStats.runDuration > 0.1:
    aggressionScore += 30
  
  # Caution rating: based on damage taken, positioning, resources
  var cautionScore = 0.0
  
  # Low damage taken = cautious
  if currentRunStats.combat.totalDamageTaken < 50:
    cautionScore += 30
  
  # Long no-damage streaks = cautious
  if currentRunStats.movement.longestNoDamageStreak > 30:
    cautionScore += 25
  
  # Wall usage = cautious
  if currentRunStats.resources.wallsPlaced > 5:
    cautionScore += 20
  
  # Saved coins = cautious
  if currentRunStats.resources.coinsAtEnd > 100:
    cautionScore += 25
  
  currentRunStats.comparison.aggressionRating = aggressionScore
  currentRunStats.comparison.cautionRating = cautionScore
  
  # Classify play style
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


# ============================================================================
# LAST RUN STORAGE
# Keep a copy of the last completed run for viewing in main menu
# ============================================================================

var lastCompletedRun*: RunStatistics = nil

proc saveLastCompletedRun*() =
  ## Store a copy of the current run for viewing in main menu and save to disk
  if not currentRunStats.isNil:
    lastCompletedRun = currentRunStats
    # Save to disk using save_system
    if saveLastRunStats(currentRunStats):
      echo "[Stats] Last run saved to memory and disk"
    else:
      echo "[Stats] Last run saved to memory only (disk save failed)"

proc loadLastCompletedRun*() =
  ## Load the last completed run from disk on startup
  let loadedStats = loadLastRunStats()
  if not loadedStats.isNil:
    lastCompletedRun = loadedStats
    echo "[Stats] Last run loaded from disk"
  else:
    echo "[Stats] No previous run found on disk"

proc hasLastRunStats*(): bool =
  ## Check if we have a previous run to display
  result = not lastCompletedRun.isNil

proc getLastRunStats*(): RunStatistics =
  ## Get the last completed run statistics
  result = lastCompletedRun
