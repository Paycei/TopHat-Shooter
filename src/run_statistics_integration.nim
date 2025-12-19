# ============================================================================
# RUN STATISTICS INTEGRATION
# Hooks statistics tracking into game update loops
# Import this and call tracking procs from game.nim
# ============================================================================

import run_statistics, types, player, bullet, enemy

export run_statistics

# ============================================================================
# GAME LIFECYCLE INTEGRATION
# ============================================================================

proc initializeRunTracking*(game: Game) =
  ## Start tracking for a new run
  startNewRun(game.mode)
  game.showRunStatsGraphs = true

proc finalizeRunTracking*(game: Game) =
  ## Finish tracking and calculate final metrics
  let waveReached = if game.mode == gmWaveBased: game.currentWave else: int(game.time / 60)
  let finalScore = game.player.kills
  
  endRun(game.player, waveReached, finalScore, game.cheatsUsed, true)

proc hasValidRunStats*(): bool =
  ## Check if we have valid run statistics to display
  result = not currentRunStats.isNil and currentRunStats.runDuration > 0

# ============================================================================
# COMBAT TRACKING INTEGRATION
# ============================================================================

proc trackBulletFired*(game: Game) =
  ## Call when player fires a bullet
  recordShotFired()

proc trackBulletHit*(game: Game, bullet: Bullet, enemy: Enemy, damage: float32) =
  ## Call when a bullet hits an enemy
  let isCrit = damage > bullet.damage * 1.5  # Simple crit detection
  recordShotHit(damage, enemy.enemyType, isCrit)
  
  # Track special mechanics
  if bullet.isPiercing:
    recordSpecialMechanic("piercing")
  if bullet.isExplosive:
    recordSpecialMechanic("explosive")
  if bullet.isHoming:
    recordSpecialMechanic("homing")
  if bullet.hasSplit:
    recordSpecialMechanic("split")

proc trackBulletDespawn*(game: Game, bullet: Bullet, hitEnemy: bool) =
  ## Call when a bullet despawns
  if not hitEnemy and bullet.lifetime > 0.1:  # Don't count instant despawns
    recordShotMissed()

proc trackEnemyKilled*(game: Game, enemy: Enemy) =
  ## Call when an enemy is killed
  recordKill(enemy.enemyType, enemy.isElite, enemy.isBoss, game.time, enemy.pos)

proc trackPlayerDamage*(game: Game, damage: float32, enemyType: EnemyType) =
  ## Call when player takes damage
  recordDamageTaken(damage, enemyType, game.time, game.player.pos)
  
  # Check for near-death
  if game.player.hp < 10 and game.player.hp > 0:
    recordNearDeath(game.time, game.player.pos)

# ============================================================================
# MOVEMENT TRACKING INTEGRATION
# ============================================================================

proc trackMovementFrame*(game: Game, dt: float32) =
  ## Call every frame to track movement
  updateMovement(game.player, dt, game.time)
  updateRunDuration(dt)

proc trackPhaseShift*(game: Game) =
  ## Call when player uses phase shift
  recordLegendaryAbility("phase_shift", game.time, game.player.pos)

proc trackTimeWarp*(game: Game) =
  ## Call when player activates time warp
  recordLegendaryAbility("time_warp", game.time, game.player.pos)

proc trackParry*(game: Game) =
  ## Call when player activates parry
  recordLegendaryAbility("parry", game.time, game.player.pos)

proc trackParrySuccess*(game: Game) =
  ## Call when parry successfully reflects a bullet
  recordSuccessfulParry()

# ============================================================================
# RESOURCE TRACKING INTEGRATION
# ============================================================================

proc trackCoinPickup*(game: Game, amount: int) =
  ## Call when player collects coins
  recordCoinEarned(amount)

proc trackShopPurchase*(game: Game, itemName: string, cost: int) =
  ## Call when player buys from shop
  recordCoinSpent(cost, itemName, game.time)

proc trackWallPlacement*(game: Game, pos: Vector2f) =
  ## Call when player places a wall
  recordWallPlaced(game.time, pos)

proc trackWallDestruction*(game: Game, damageBlocked: float32) =
  ## Call when a wall is destroyed
  recordWallDestroyed(damageBlocked)

proc trackConsumablePickup*(game: Game, consumType: ConsumableType) =
  ## Call when player picks up a consumable
  recordConsumable(consumType)

# ============================================================================
# POWER-UP TRACKING INTEGRATION
# ============================================================================

proc trackPowerUpSelection*(game: Game, powerUp: PowerUp) =
  ## Call when player selects a power-up
  recordPowerUpChosen(powerUp, game.time)

proc trackPowerUpDamage*(game: Game, powerType: PowerUpType, damage: float32) =
  ## Call to attribute damage to a specific power-up
  recordPowerUpDamage(powerType, damage)

proc trackPowerUpKill*(game: Game, powerType: PowerUpType) =
  ## Call to attribute a kill to a specific power-up
  recordPowerUpKill(powerType)

# ============================================================================
# PERFORMANCE TRACKING INTEGRATION
# ============================================================================

proc trackWaveCompletion*(game: Game, waveNumber: int, waveTime: float32) =
  ## Call when a wave is completed
  recordWaveComplete(waveNumber, waveTime, game.time)

# ============================================================================
# HELPER PROCS FOR POWER-UP DAMAGE ATTRIBUTION
# ============================================================================

proc attributeDamageToActivePowerUps*(game: Game, baseDamage: float32) =
  ## Automatically attribute damage to active power-ups that contributed
  ## Call this whenever player deals damage
  
  if currentRunStats.isNil:
    return
  
  # Check which power-ups are active and contributed to this damage
  for powerUp in game.player.powerUps:
    var contributionFactor = 0.0
    
    case powerUp.powerType
    of puBulletDamage:
      contributionFactor = 0.15 * powerUp.level.float32  # Direct damage increase
    of puExplosiveBullets:
      contributionFactor = 0.10  # Explosion damage
    of puPiercingShots:
      contributionFactor = 0.08  # Multi-target efficiency
    of puMultiShot:
      contributionFactor = 0.12  # Multiple projectiles
    of puDoubleShot:
      contributionFactor = 0.10
    of puBulletSpeed:
      contributionFactor = 0.05  # Hit more often
    of puRapidFire:
      contributionFactor = 0.10  # More shots = more damage
    of puMagicalBullets:
      contributionFactor = 0.08  # Homing accuracy
    of puCriticalHit:
      contributionFactor = 0.12  # Crit damage
    of puFireBullets, puPoisonShot, puFrostShots, puArcaneBullets:
      contributionFactor = 0.10  # Elemental damage
    of puFireAura, puLightningAura, puPoisonAura:
      contributionFactor = 0.15  # Aura damage
    of puDamageZone:
      contributionFactor = 0.10
    of puChainLightning:
      contributionFactor = 0.12
    of puBulletRicochet:
      contributionFactor = 0.08
    of puBulletSplit:
      contributionFactor = 0.10
    of puOvercharge:
      contributionFactor = 0.08
    of puEchoShots:
      contributionFactor = 0.09
    # Masteries amplify elemental effects
    of puFireMastery, puPoisonMastery, puFrostMastery, 
       puArcaneMastery, puLightningMastery, puWindMastery:
      contributionFactor = 0.20
    else:
      contributionFactor = 0.0
    
    if contributionFactor > 0:
      let attributedDamage = baseDamage * contributionFactor
      recordPowerUpDamage(powerUp.powerType, attributedDamage)
