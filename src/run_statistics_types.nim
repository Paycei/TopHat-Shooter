# ============================================================================
# RUN STATISTICS TYPES
# Per-run (single game session) statistics tracking
# Tracks ALL measurable gameplay data for analysis and visualization
# ============================================================================

import types, std/tables, times

type
  # ============================================================================
  # EVENT TRACKING
  # Time-series events for detailed timeline analysis
  # ============================================================================
  
  GameEventType* = enum
    geKill,              # Enemy killed
    geDamageTaken,       # Player took damage
    geDamageDealt,       # Player dealt damage
    gePowerUpChosen,     # Power-up selected
    geShopPurchase,      # Item bought from shop
    geWaveComplete,      # Wave cleared
    geBossSpawn,         # Boss spawned
    geBossDefeat,        # Boss defeated
    geNearDeath,         # HP dropped below 10
    geLegendaryUsed,     # Legendary ability activated
    geWallPlaced,        # Wall placed
    geCoinCollected,     # Coins collected (batch)
    geConsumableUsed     # Consumable picked up
  
  GameEvent* = object
    timestamp*: float32
    eventType*: GameEventType
    value*: float32        # Numeric value (damage, coins, etc.)
    details*: string       # Additional context
    position*: Vector2f    # Where the event occurred
  
  # ============================================================================
  # COMBAT STATISTICS
  # All offensive and defensive combat metrics
  # ============================================================================
  
  CombatStats* = object
    # Shooting accuracy
    shotsFired*: int
    shotsHit*: int
    shotsMissed*: int
    accuracyPercent*: float32
    
    # Damage metrics
    totalDamageDealt*: float32
    totalDamageTaken*: float32
    largestSingleHit*: float32
    damageTakenByType*: Table[EnemyType, float32]
    
    # Kill tracking
    totalKills*: int
    killsByType*: Table[EnemyType, int]
    eliteKills*: int
    bossKills*: int
    
    # Special mechanics
    criticalHits*: int
    piercingShots*: int
    explosiveKills*: int
    ricochets*: int
    chainLightningProcs*: int
    
    # Bullet type usage (tracking which mechanics were active)
    homingBullets*: int
    piercingBullets*: int
    explosiveBullets*: int
    splitBullets*: int
    
  # ============================================================================
  # MOVEMENT & SURVIVABILITY
  # Tracking player positioning, dodging, and defensive play
  # ============================================================================
  
  MovementStats* = object
    # Distance and positioning
    totalDistanceTraveled*: float32
    averageSpeed*: float32
    positionHeatmap*: seq[Vector2f]  # Sampled every 0.5s
    
    # Legendary abilities
    phaseShiftsUsed*: int
    totalPhaseShiftDistance*: float32
    timeWarpsUsed*: int
    totalTimeWarpDuration*: float32
    parriesUsed*: int
    successfulParries*: int  # Bullets actually reflected
    
    # Survivability
    timeInvincible*: float32
    timeAtCriticalHP*: float32  # HP < 25%
    timeAtLowHP*: float32       # HP < 50%
    nearDeathCount*: int        # HP dropped below 10
    damageAvoided*: float32     # Estimated via dodges/invincibility
    
    # Defensive metrics
    longestNoDamageStreak*: float32
    currentNoDamageStreak*: float32
    hitsTakenCount*: int
    averageTimeBetweenHits*: float32
  
  # ============================================================================
  # RESOURCE MANAGEMENT
  # Coins, walls, consumables, shop purchases
  # ============================================================================
  
  ResourceStats* = object
    # Economy
    coinsEarned*: int
    coinsSpent*: int
    coinsAtEnd*: int
    coinEfficiency*: float32  # Coins earned per kill
    
    # Walls
    wallsPlaced*: int
    wallsDamaged*: int
    wallsDestroyed*: int
    wallDamageBlocked*: float32
    
    # Consumables
    consumablesCollected*: int
    consumablesByType*: Table[ConsumableType, int]
    healthPotionsUsed*: int
    
    # Shop
    shopPurchases*: seq[(float32, string)]  # timestamp, item name
    totalSpentInShop*: int
    shopVisits*: int
  
  # ============================================================================
  # POWER-UP ANALYTICS
  # Tracking power-up choices, effectiveness, and synergies
  # ============================================================================
  
  PowerUpStats* = object
    # Selection timeline
    powerUpsChosen*: seq[(float32, PowerUp)]  # timestamp, powerup
    totalPowerUps*: int
    commonPowerUps*: int
    legendaryPowerUps*: int
    
    # Effectiveness tracking
    damageContribution*: Table[PowerUpType, float32]
    killContribution*: Table[PowerUpType, int]
    mostEffectivePowerUp*: PowerUpType
    leastEffectivePowerUp*: PowerUpType
    
    # Synergy analysis
    synergyScore*: float32  # 0-100 rating of power-up combo
    elementalCombo*: seq[PowerUpType]  # Active elemental power-ups
    hasSynergy*: bool
    
    # Level distribution
    level1PowerUps*: int
    level2PowerUps*: int
    level3PowerUps*: int
  
  # ============================================================================
  # PERFORMANCE METRICS
  # Time-based and efficiency measurements
  # ============================================================================
  
  PerformanceStats* = object
    # Wave performance (wave-based mode)
    waveTimes*: seq[float32]  # Time to complete each wave
    averageWaveTime*: float32
    fastestWave*: float32
    slowestWave*: float32
    
    # DPS tracking
    peakDPS*: float32
    averageDPS*: float32
    dpsHistory*: seq[(float32, float32)]  # timestamp, dps value
    currentDPSWindow*: seq[(float32, float32)]  # Rolling window for calculation
    
    # Efficiency metrics
    killsPerMinute*: float32
    damagePerShot*: float32
    shotEfficiency*: float32  # Damage dealt / shots fired
    
    # Streak tracking
    longestKillStreak*: int
    currentKillStreak*: int
    killStreakHistory*: seq[(float32, int)]  # timestamp, streak count
  
  # ============================================================================
  # COMPARISON METRICS
  # Derived stats comparing to optimal/previous performance
  # ============================================================================
  
  ComparisonStats* = object
    # Optimal comparison
    accuracyVsOptimal*: float32     # % of theoretical max accuracy
    dpsVsOptimal*: float32          # % of theoretical max DPS
    survivalVsPredicted*: float32   # vs expected survival time
    
    # Decision quality
    powerUpQualityScore*: float32   # 0-100 rating of power-up choices
    resourceUsageScore*: float32    # 0-100 rating of coin/wall usage
    positioningScore*: float32      # 0-100 based on damage taken
    
    # Play style classification
    playStyle*: string  # "Aggressive", "Defensive", "Balanced", "Mobile", "Tank"
    aggressionRating*: float32  # 0-100
    cautionRating*: float32     # 0-100
  
  # ============================================================================
  # COMPLETE RUN STATISTICS
  # Main container for all per-run statistical data
  # ============================================================================
  
  RunStatistics* = ref object
    # ========================================
    # RUN METADATA
    # ========================================
    gameMode*: GameMode
    startTime*: string       # ISO format timestamp
    endTime*: string
    runDuration*: float32    # Total seconds
    waveReached*: int
    finalScore*: int
    cheatsUsed*: bool
    died*: bool              # False if quit/exited
    
    # ========================================
    # CATEGORY STATISTICS
    # ========================================
    combat*: CombatStats
    movement*: MovementStats
    resources*: ResourceStats
    powerUps*: PowerUpStats
    performance*: PerformanceStats
    comparison*: ComparisonStats
    
    # ========================================
    # TIMELINE & EVENTS
    # ========================================
    events*: seq[GameEvent]
    
    # ========================================
    # FINAL PLAYER STATE
    # ========================================
    finalHP*: float32
    finalMaxHP*: float32
    finalCoins*: int
    finalPowerUps*: seq[PowerUp]

# ============================================================================
# HELPER PROCS FOR INITIALIZATION
# ============================================================================

proc initCombatStats*(): CombatStats =
  result = CombatStats(
    killsByType: initTable[EnemyType, int](),
    damageTakenByType: initTable[EnemyType, float32]()
  )

proc initMovementStats*(): MovementStats =
  result = MovementStats(
    positionHeatmap: @[]
  )

proc initResourceStats*(): ResourceStats =
  result = ResourceStats(
    consumablesByType: initTable[ConsumableType, int](),
    shopPurchases: @[]
  )

proc initPowerUpStats*(): PowerUpStats =
  result = PowerUpStats(
    powerUpsChosen: @[],
    damageContribution: initTable[PowerUpType, float32](),
    killContribution: initTable[PowerUpType, int](),
    elementalCombo: @[]
  )

proc initPerformanceStats*(): PerformanceStats =
  result = PerformanceStats(
    waveTimes: @[],
    dpsHistory: @[],
    currentDPSWindow: @[],
    killStreakHistory: @[]
  )

proc initComparisonStats*(): ComparisonStats =
  result = ComparisonStats(
    playStyle: "Balanced",
    aggressionRating: 50.0,
    cautionRating: 50.0
  )

proc initRunStatistics*(): RunStatistics =
  ## Initialize a new run statistics object
  result = RunStatistics(
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
