import raylib, math
import types, bullet, particle_skins, particle_types, powerup, sound, d_systems, run_statistics, fx, game/combat, game/bullets

proc rotateVec(v: Vector2f, angle: float32): Vector2f =
  newVector2f(v.x * cos(angle) - v.y * sin(angle), v.x * sin(angle) + v.y * cos(angle))

proc calcBulletEffects(player: Player): BulletEffects =
  ## Computes the elemental/knockback values that every player bullet carries.
  ## Single source of truth shared by shootBullet and fireDoubleShotBurst.
  var slow, poison, fire, wind = 0.0'f32

  if hasPowerUp(player, puFrostShots):
    let lvl = getPowerUpLevel(player, puFrostShots)
    slow = case lvl
      of 1: 0.25
      of 2: 0.4
      else: 0.6
    if player.hasFrostMastery:
      slow += 0.2  # +20% slow (total up to 80%)

  # These are DoT *durations* in seconds (dps lives in bullets.nim
  # fireDotDamage/poisonDotDamage): poison lingers 1.5-2x longer than fire,
  # matching the power-up descriptions.
  if hasPowerUp(player, puPoisonShot):
    poison = case getPowerUpLevel(player, puPoisonShot)
      of 1: 4.0
      of 2: 5.0
      else: 6.0

  if hasPowerUp(player, puFireBullets):
    fire = case getPowerUpLevel(player, puFireBullets)
      of 1: 2.0
      of 2: 3.0
      else: 4.0

  if hasPowerUp(player, puWindBullets):
    let lvl = getPowerUpLevel(player, puWindBullets)
    wind = case lvl
      of 1: 100.0
      of 2: 200.0
      else: 350.0

  if hasPowerUp(player, puHeavyRounds):
    let lvl = getPowerUpLevel(player, puHeavyRounds)
    let heavyKnockback = case lvl
      of 1: 80.0
      of 2: 150.0
      else: 250.0
    wind += heavyKnockback

  (slow, poison, fire, wind)

proc baseBulletSpeed(player: Player): float32 =
  ## Player bullets travel at 1.2x the configured bulletSpeed, plus a *subtle*
  ## nudge tied to how much faster than baseline the player is currently moving.
  ## Only the excess over baseline (ratio - 1.0) feeds in, and at a low 0.15
  ## transfer, so a +33% Speed Boost adds just ~+5% bullet speed, barely
  ## noticeable, while a baseline-speed player sees no change at all.
  result = player.bulletSpeed * 1.2
  if player.baseSpeed > 0:
    let speedRatio = player.speed / player.baseSpeed
    result *= 1.0'f32 + (speedRatio - 1.0'f32) * 0.15'f32

const
  TracerMaxRange   = 1400.0'f32  # px; long enough to cross the whole arena
  TracerHalfWidth  = 14.0'f32    # px; aim-assist forgiveness either side of the line
  TracerDamageMult = 0.75'f32    # fraction of the shot's damage delivered instantly

proc fireLightspeedTracer(game: Game, origin, dir: Vector2f, stats: combat.CombatStats) =
  ## Bullet Speed (Legendary) "Lightspeed Tracer": casts an instant hitscan beam
  ## down the firing line and deals guaranteed damage to the FIRST enemy it
  ## crosses, before the physical bullet has even travelled. Single-target with
  ## no AoE or elemental riders -- the whole payoff is the unmissable lead hit.
  let len = dir.length()
  if len < 0.0001'f32:
    return
  let dx = dir.x / len
  let dy = dir.y / len

  # Walk the ray: keep the enemy with the smallest forward projection (t) whose
  # perpendicular distance to the line falls within its radius + beam width.
  var bestEnemy: Enemy = nil
  var bestT = TracerMaxRange
  for enemy in game.enemies:
    if enemy.isBoss and enemy.invulnerabilityTimer > 0:
      continue
    let vx = enemy.pos.x - origin.x
    let vy = enemy.pos.y - origin.y
    let t = vx * dx + vy * dy              # projection along the beam
    if t <= 0.0'f32 or t > bestT:
      continue
    let perpDist = abs(vx * (-dy) + vy * dx)  # distance from the beam line
    if perpDist <= enemy.radius + TracerHalfWidth:
      bestEnemy = enemy
      bestT = t

  if bestEnemy == nil:
    return

  let tracerBase = stats.damage * TracerDamageMult
  let (tracerDmg, wasCrit) = applyCriticalHitWithFlag(stats, tracerBase)
  let actual = damageEnemy(bestEnemy, tracerDmg)
  if actual > 0:
    trackPowerUpDamage(game, puBulletSpeed, actual)
    showDamage(game, bestEnemy.pos, actual, fromPlayer = true,
               isCritical = wasCrit, damageType = dtDefault)

  # Instant beam visual from the muzzle to the struck enemy.
  spawnLightningBoltInto(game.lightningBolts, origin, bestEnemy.pos)

proc shootBullet*(game: Game, direction: Vector2f) =
  # Calculate all combat stats once at the start
  var stats = calculateCombatStats(game.player)
  applyBossArenaCombatBonus(game, stats)

  if game.time - game.player.lastShot >= stats.fireRate:
    # Increment bullet counter for special rounds power-up
    game.player.bulletCounter += 1

    recordShot(game.dopamine.waveStats, false)  # Will be updated to true if hit

    # Check for power-ups that modify shooting
    let hasHoming: bool = hasPowerUp(game.player, puMagicalBullets)
    let hasPiercing: bool = hasPowerUp(game.player, puPiercingShots)
    let hasExplosive: bool = hasPowerUp(game.player, puExplosiveBullets)
    let hasDoubleShot: bool = hasPowerUp(game.player, puDoubleShot)
    let hasMultiShot: bool = hasPowerUp(game.player, puMultiShot)
    let hasRicochet: bool = hasPowerUp(game.player, puBulletRicochet)
    let hasSplit: bool = hasPowerUp(game.player, puBulletSplit)
    let hasArcane: bool = hasPowerUp(game.player, puArcaneBullets)

    # Base bullet properties - use calculated stats
    var speed = baseBulletSpeed(game.player)
    var damage = stats.damage  # Already includes Rage bonus

    # Compute rage multiplier at fire time so hit-block can isolate the bonus
    var rageMultiplier = 1.0'f32
    for powerUp in game.player.powerUps:
      if powerUp.powerType == puRage:
        let hpPercent = game.player.hp / game.player.maxHp
        let hpLost = 1.0 - hpPercent
        let bonusPerTenPercent = case powerUp.level
          of 1: 0.05
          of 2: 0.08
          else: 0.12
        rageMultiplier = 1.0 + (hpLost * 10.0 * bonusPerTenPercent)
        break

    # Double-shot bullets deal 15% less damage per bullet
    if hasDoubleShot:
      damage *= 0.85  # 15% less damage per bullet

    # Multi-Shot no longer triples baseline DPS by itself.
    if hasMultiShot:
      damage *= 0.7

    var bulletRadius = BASE_PLAYER_BULLET_RADIUS

    # Apply heavy rounds power-up
    if hasPowerUp(game.player, puHeavyRounds):
      let heavyLevel = getPowerUpLevel(game.player, puHeavyRounds)
      bulletRadius *= getHeavyRoundsSizeMultiplier(heavyLevel)

    # Apply critical hit chance using pre-calculated stats and capture if it was a crit
    let baseDamagePreCrit = damage  # Store pre-crit value for puCriticalHit tracking
    let (damageWithCrit, wasCrit) = applyCriticalHitWithFlag(stats, damage)
    damage = damageWithCrit

    # Cheap flat damage for Wind Bullets so the upgrade is meaningful
    if hasPowerUp(game.player, puWindBullets):
      damage += WindBulletFlatDamageBonus

    # RoomEcho: charged bullets from room clear deal bonus damage
    if game.player.roomEchoCharges > 0:
      damage *= 1.6'f32
      game.player.roomEchoCharges -= 1

    # Check for Special Rounds power-up
    var isSpecialRound = false
    if hasPowerUp(game.player, puSpecialRounds):
      let specialLevel = getPowerUpLevel(game.player, puSpecialRounds)
      let roundInterval = case specialLevel
        of 1: 5  # Every 5th bullet
        of 2: 4  # Every 4th bullet
        else: 3  # Every 3rd bullet

      if game.player.bulletCounter mod roundInterval == 0:
        isSpecialRound = true
        # Special rounds deal bonus damage
        damage *= 1.75  # +75% bonus damage

    # Apply Arcane Mastery bonus to Arcane bullets (damage + piercing)
    var arcanePiercing = hasPiercing  # Start with base piercing status
    if hasArcane and game.player.hasArcaneMastery:
      damage *= 1.5  # +50% additional damage on top of Arcane Bullets bonus
      arcanePiercing = true  # Grant piercing to Arcane bullets with mastery

    # Calculate slow, poison, fire, and wind effects
    let fx = calcBulletEffects(game.player)
    let slowEffect = fx.slow
    let poisonEffect = fx.poison
    let fireEffect = fx.fire
    let windEffect = fx.wind

    # Wind Mastery: increase bullet damage for wind bullets
    if windEffect > 0 and game.player.hasWindMastery:
      damage *= 2.5  # +150% damage for wind bullets

    if hasDoubleShot and hasMultiShot:
      # When both active: Fire multishot pattern (3 directions), then schedule second burst
      let multiCount = 3  # Always 3 bullets for legendary Multi-Shot
      let spreadAngle = 0.3

      # Fire first burst (3 bullets = 1 normal + 2 bonus from Multi-Shot)
      for i in 0..<multiCount:
        let angle = (i.float32 - (multiCount - 1).float32 / 2.0) * spreadAngle
        let spreadDir = rotateVec(direction, angle)
        let bullet = newBullet(
          x = game.player.pos.x,
          y = game.player.pos.y,
          direction = spreadDir,
          speed = speed,
          damage = damage,
          fromPlayer = true,
          isHoming = hasHoming,
          isPiercing = arcanePiercing,
          isExplosive = hasExplosive,
          hasBounce = hasRicochet,
          canSplit = hasSplit,
          slowAmount = slowEffect,
          poisonDuration = poisonEffect,
          fireDuration = fireEffect,
          windPushForce = windEffect,
          isArcaneBullet = hasArcane,
          isBonusFromMultiShot = (i > 0),  # First bullet (i=0) is normal, rest are bonus
          wasCrit = wasCrit,
          isSpecialRound = isSpecialRound,
          bulletSkin = game.player.bulletSkinType,
          bulletShape = game.player.bulletShapeType
        )
        bullet.radius = bulletRadius
        bullet.baseDamagePreCrit = baseDamagePreCrit
        bullet.rageMultiplier = rageMultiplier
        game.bullets.add(bullet)
        trackBulletFired(game)  # Track shot for statistics

      # Schedule second burst with small delay (0.08s) - LEGENDARY Double Shot is single level
      # This second burst will also have 3 bullets, all marked as bonus from Double Shot
      game.player.doubleShotDelay = 0.08

    elif hasDoubleShot:
      # LEGENDARY: Fire 2 bullets in quick succession (single level only)
      # Fire first bullet immediately (this is the normal bullet)
      let bullet = newBullet(
        x = game.player.pos.x,
        y = game.player.pos.y,
        direction = direction,
        speed = speed,
        damage = damage,
        fromPlayer = true,
        isHoming = hasHoming,
        isPiercing = arcanePiercing,
        isExplosive = hasExplosive,
        hasBounce = hasRicochet,
        canSplit = hasSplit,
        slowAmount = slowEffect,
        poisonDuration = poisonEffect,
        fireDuration = fireEffect,
        windPushForce = windEffect,
        isArcaneBullet = hasArcane,
        isBonusFromDoubleShot = false,  # First bullet is normal
        wasCrit = wasCrit,
        isSpecialRound = isSpecialRound,
        bulletSkin = game.player.bulletSkinType,
        bulletShape = game.player.bulletShapeType
      )
      bullet.radius = bulletRadius
      bullet.baseDamagePreCrit = baseDamagePreCrit
      bullet.rageMultiplier = rageMultiplier
      assignBulletId(game, bullet)
      game.bullets.add(bullet)
      trackBulletFired(game)  # Track shot for statistics

      # Schedule second bullet with small delay (0.08s) - will be marked as bonus
      game.player.doubleShotDelay = 0.08
    elif hasMultiShot:
      # Shoot in 3 directions (legendary, no nerfs)
      let bulletCount = 3  # Always 3 bullets
      let spreadAngle = 0.3

      for i in 0..<bulletCount:
        let angle = (i.float32 - (bulletCount - 1).float32 / 2.0) * spreadAngle
        let spreadDir = rotateVec(direction, angle)
        let bullet = newBullet(
          x = game.player.pos.x,
          y = game.player.pos.y,
          direction = spreadDir,
          speed = speed,
          damage = damage,
          fromPlayer = true,
          isHoming = hasHoming,
          isPiercing = arcanePiercing,
          isExplosive = hasExplosive,
          hasBounce = hasRicochet,
          canSplit = hasSplit,
          slowAmount = slowEffect,
          poisonDuration = poisonEffect,
          fireDuration = fireEffect,
          windPushForce = windEffect,
          isArcaneBullet = hasArcane,
          isBonusFromMultiShot = (i > 0),  # First bullet (i=0) is normal, rest are bonus
          wasCrit = wasCrit,
          isSpecialRound = isSpecialRound,
          bulletSkin = game.player.bulletSkinType,
          bulletShape = game.player.bulletShapeType
        )
        bullet.radius = bulletRadius
        bullet.baseDamagePreCrit = baseDamagePreCrit
        bullet.rageMultiplier = rageMultiplier
        game.bullets.add(bullet)
        trackBulletFired(game)  # Track shot for statistics
    else:
      # Normal single shot
      let bullet = newBullet(
        x = game.player.pos.x,
        y = game.player.pos.y,
        direction = direction,
        speed = speed,
        damage = damage,
        fromPlayer = true,
        isHoming = hasHoming,
        isPiercing = arcanePiercing,
        isExplosive = hasExplosive,
        hasBounce = hasRicochet,
        canSplit = hasSplit,
        slowAmount = slowEffect,
        poisonDuration = poisonEffect,
        fireDuration = fireEffect,
        windPushForce = windEffect,
        isArcaneBullet = hasArcane,
        wasCrit = wasCrit,
        isSpecialRound = isSpecialRound,
        bulletSkin = game.player.bulletSkinType,
        bulletShape = game.player.bulletShapeType
      )
      bullet.radius = bulletRadius
      bullet.baseDamagePreCrit = baseDamagePreCrit
      bullet.rageMultiplier = rageMultiplier
      assignBulletId(game, bullet)
      game.bullets.add(bullet)
      trackBulletFired(game)  # Track shot for statistics

    # Bullet Speed (Legendary): fire the instant hitscan lead hit down the aim
    # line, once per shot (independent of Multi-/Double-Shot bullet counts).
    if hasPowerUp(game.player, puBulletSpeed):
      fireLightspeedTracer(game, game.player.pos, direction, stats)

    game.player.lastShot = game.time

    # Nova: freeze newly spawned player bullets if Nova is active
    if game.player.novaActive:
      for bullet in game.bullets:
        if bullet.fromPlayer and not bullet.isFrozenByNova:
          bullet.isFrozenByNova = true

    # Play shoot sound
    playSound(stShoot, 0.3)

    # Use the new particle skin system
    let skinType = ParticleSkinType(game.player.particleSkinType)
    spawnShootingParticles(game.particlePool, game.player.pos.x, game.player.pos.y, direction, skinType, game.time)

# Helper to fire delayed double-shot bursts
proc fireDoubleShotBurst*(game: Game, direction: Vector2f, hasMultiShot: bool) =
  # Calculate combat stats once for the burst
  var burstStats = calculateCombatStats(game.player)
  applyBossArenaCombatBonus(game, burstStats)

  let hasHoming = hasPowerUp(game.player, puMagicalBullets)
  let hasPiercing = hasPowerUp(game.player, puPiercingShots)
  let hasExplosive = hasPowerUp(game.player, puExplosiveBullets)
  let hasRicochet = hasPowerUp(game.player, puBulletRicochet)
  let hasSplit = hasPowerUp(game.player, puBulletSplit)
  let hasArcane = hasPowerUp(game.player, puArcaneBullets)

  var speed = baseBulletSpeed(game.player)
  var damage = burstStats.damage * 0.85  # Second bullet reduced by 15%
  var bulletRadius = BASE_PLAYER_BULLET_RADIUS

  # Apply Arcane Mastery bonus consistently to delayed burst bullets too.
  var arcanePiercing = hasPiercing
  if hasArcane and game.player.hasArcaneMastery:
    damage *= 1.5  # +50% additional damage on top of Arcane Bullets bonus
    arcanePiercing = true  # Grant piercing to Arcane bullets with mastery

  # NERF: Multi-shot bullets deal less damage per bullet
  if hasMultiShot:
    damage *= 0.7

  # Roll for critical hit
  let burstBaseDamagePreCrit = damage  # Store pre-crit value for puCriticalHit tracking
  let (damageWithCrit, wasCrit) = applyCriticalHitWithFlag(burstStats, damage)
  damage = damageWithCrit

  # Cheap flat damage for Wind Bullets so the upgrade is meaningful
  if hasPowerUp(game.player, puWindBullets):
    damage += WindBulletFlatDamageBonus

  if hasPowerUp(game.player, puHeavyRounds):
    let sizeLevel = getPowerUpLevel(game.player, puHeavyRounds)
    bulletRadius *= getHeavyRoundsSizeMultiplier(sizeLevel)

  let fx = calcBulletEffects(game.player)
  let slowEffect = fx.slow
  let poisonEffect = fx.poison
  let fireEffect = fx.fire
  let windEffect = fx.wind

  # Wind Mastery: increase burst bullet damage for wind-enabled bullets
  if windEffect > 0 and game.player.hasWindMastery:
    damage *= 2.5  # +150% damage for wind bullets

  if hasMultiShot:
    let multiCount = 3  # Always 3 bullets for legendary Multi-Shot
    let spreadAngle = 0.3

    for i in 0..<multiCount:
      let angle = (i.float32 - (multiCount - 1).float32 / 2.0) * spreadAngle
      let spreadDir = rotateVec(direction, angle)
      let bullet = newBullet(
        x = game.player.pos.x,
        y = game.player.pos.y,
        direction = spreadDir,
        speed = speed,
        damage = damage,
        fromPlayer = true,
        isHoming = hasHoming,
        isPiercing = arcanePiercing,
        isExplosive = hasExplosive,
        hasBounce = hasRicochet,
        canSplit = hasSplit,
        slowAmount = slowEffect,
        poisonDuration = poisonEffect,
        fireDuration = fireEffect,
        windPushForce = windEffect,
        isArcaneBullet = hasArcane,
        isBonusFromDoubleShot = true,
        isBonusFromMultiShot = (i > 0),
        wasCrit = wasCrit,
        bulletSkin = game.player.bulletSkinType,
        bulletShape = game.player.bulletShapeType
      )
      bullet.radius = bulletRadius
      bullet.baseDamagePreCrit = burstBaseDamagePreCrit
      assignBulletId(game, bullet)
      game.bullets.add(bullet)
      trackBulletFired(game)

      # Spawn shooting particles (only once, not per bullet in multi-shot)
      if i == 0:
        spawnShootingParticles(game.particlePool, game.player.pos.x, game.player.pos.y, direction, ParticleSkinType(game.player.particleSkinType), game.time)
  else:
    let bullet = newBullet(
      x = game.player.pos.x,
      y = game.player.pos.y,
      direction = direction,
      speed = speed,
      damage = damage,
      fromPlayer = true,
      isHoming = hasHoming,
      isPiercing = arcanePiercing,
      isExplosive = hasExplosive,
      hasBounce = hasRicochet,
      canSplit = hasSplit,
      slowAmount = slowEffect,
      poisonDuration = poisonEffect,
      fireDuration = fireEffect,
      windPushForce = windEffect,
      isArcaneBullet = hasArcane,
      isBonusFromDoubleShot = true,
      wasCrit = wasCrit,
      bulletSkin = game.player.bulletSkinType,
      bulletShape = game.player.bulletShapeType
    )
    bullet.radius = bulletRadius
    bullet.baseDamagePreCrit = burstBaseDamagePreCrit
    assignBulletId(game, bullet)
    game.bullets.add(bullet)
    trackBulletFired(game)

    # Spawn shooting particles
    spawnShootingParticles(game.particlePool, game.player.pos.x, game.player.pos.y, direction, ParticleSkinType(game.player.particleSkinType), game.time)

  playSound(stShoot, 0.25)

