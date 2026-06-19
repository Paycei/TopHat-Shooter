proc applyOrbDamage(game: var Game, orb: RotatingOrb, enemy: Enemy,
                    baseDamage: float32, orbPos: Vector2f, currentTime: float32,
                    enemyIdx: int, stats: CombatStats): bool =
  ## Apply damage from orb to enemy and handle hit cooldown
  ## Returns true if damage was applied

  # Check if we can hit this enemy (cooldown check)
  # Prune stale entries while we're here: any entry older than 2s is a dead
  # enemy and will never be referenced again (IDs only increment).
  var toDelete: seq[int]
  for id, t in orb.lastHitTime:
    if currentTime - t > 2.0:
      toDelete.add(id)
  for id in toDelete:
    orb.lastHitTime.del(id)

  if orb.lastHitTime.getOrDefault(enemyIdx, 0.0) > currentTime - 0.5:
    return false  # Still within 0.5s cooldown

  # Calculate actual damage
  var actualBaseDamage = baseDamage

  # Apply Arcane Mastery bonus for Arcane orbs
  if orb.elementType == etArcane and game.player.hasArcaneMastery:
    actualBaseDamage *= 2.0  # +100% damage

  # Apply Wind Mastery bonus for Wind orbs
  if orb.elementType == etWind and game.player.hasWindMastery:
    actualBaseDamage *= 2.5  # +150% damage

  # Use passed-in stats for crit calculation (avoids recomputing per orb hit)
  let damageWithCrit = applyCriticalHitFromStats(stats, actualBaseDamage)
  let actualDamage = damageEnemy(enemy, damageWithCrit)

  # Track statistics for the orb type
  if hasPowerUp(game.player, puRotatingOrbs):
    trackPowerUpDamage(game, puRotatingOrbs, actualDamage)
  else:
    # Track individual orb type with mastery bonus
    case orb.elementType
    of etPoison:
      trackPowerUpDamage(game, puPoisonOrb, actualDamage)
      if game.player.hasPoisonMastery:
        trackPowerUpDamage(game, puPoisonMastery, actualDamage)
    of etFire:
      trackPowerUpDamage(game, puFireOrb, actualDamage)
      if game.player.hasFireMastery:
        trackPowerUpDamage(game, puFireMastery, actualDamage)
    of etLightning:
      trackPowerUpDamage(game, puLightningOrb, actualDamage)
      if game.player.hasLightningMastery:
        trackPowerUpDamage(game, puLightningMastery, actualDamage)
    of etWind:
      trackPowerUpDamage(game, puWindOrb, actualDamage)
      if game.player.hasWindMastery:
        trackPowerUpDamage(game, puWindMastery, actualDamage)
    of etFrost:
      trackPowerUpDamage(game, puFrostOrb, actualDamage)
      if game.player.hasFrostMastery:
        trackPowerUpDamage(game, puFrostMastery, actualDamage)
    of etArcane:
      trackPowerUpDamage(game, puArcaneOrb, actualDamage)
      if game.player.hasArcaneMastery:
        trackPowerUpDamage(game, puArcaneMastery, actualDamage)
    of etBlood:
      trackPowerUpDamage(game, puBloodOrb, actualDamage)
      if game.player.hasBloodMastery:
        trackPowerUpDamage(game, puBloodMastery, actualDamage)
    of etNone: discard

  # Create damage number
  game.showDamage(enemy.pos, actualDamage, fromPlayer = true,
                  isCritical = damageWithCrit > actualBaseDamage, damageType = dtDefault)

  # Record hit time
  orb.lastHitTime[enemyIdx] = currentTime

  return true

proc applyOrbEffects(game: var Game, orb: RotatingOrb, enemy: Enemy,
                     baseDamage: float32, orbPos: Vector2f, dt: float32,
                     stats: CombatStats) =
  ## Apply element-specific effects from orb to enemy

  case orb.elementType
  of etPoison:
    let poisonDmg = 0.3 + game.player.damage * 0.2
    applyMasteryDoT(enemy, etPoison, poisonDmg, 4.0,
                    game.player.hasPoisonMastery,
                    masteryDmgMult = 2.5, masteryDurMult = 2.0,
                    masterySlowAmount = 0.30, source = "orb")

    # Green particles
    spawnExplosionPooled(game.particlePool, orbPos.x, orbPos.y,
                   Color(r: 100, g: 255, b: 100, a: 255), 5)

  of etFire:
    let fireDmg = 0.4 + game.player.damage * 0.2
    applyMasteryDoT(enemy, etFire, fireDmg, 2.0,
                    game.player.hasFireMastery,
                    masteryDmgMult = 2.5, masteryDurMult = 2.0,
                    masterySlowAmount = 0.35, source = "orb")

    # Orange/red particles
    spawnExplosionPooled(game.particlePool, orbPos.x, orbPos.y, Orange, 5)
    spawnExplosionPooled(game.particlePool, orbPos.x, orbPos.y, Red, 3)

  of etLightning:
    # Lightning: Chain to nearby enemies
    let chainRange = 80.0

    var nearestDist = chainRange + 1.0
    var nearestEnemy: Enemy = nil
    var nearestIdx = -1

    # Find nearest enemy to chain to
    var checkIdx = 0
    for other in game.enemies:
      if other != enemy:
        let chainDist = distance(enemy.pos, other.pos)
        if chainDist < chainRange and chainDist < nearestDist:
          nearestDist = chainDist
          nearestEnemy = other
          nearestIdx = checkIdx
      checkIdx += 1

    # Apply chain damage
    if nearestEnemy != nil:
      let chainDamageWithCrit = applyCriticalHitFromStats(stats, baseDamage * 0.7)
      let chainDamage = damageEnemy(nearestEnemy, chainDamageWithCrit)

      # Track lightning orb chain damage, belongs to puChainLightning regardless of trigger source
      trackPowerUpDamage(game, puChainLightning, chainDamage)

      game.showDamage(nearestEnemy.pos, chainDamage, fromPlayer = true,
                      isCritical = chainDamageWithCrit > baseDamage * 0.7, damageType = dtLightning)

      # Apply slow if has Lightning Mastery
      if game.player.hasLightningMastery:
        nearestEnemy.slowTimer = 0.2
        if nearestEnemy.slowAmount < 0.25:
          nearestEnemy.slowAmount = 0.25  # 25% slow

      # Lightning arc from hit enemy to chained enemy
      spawnLightningBolt(game, enemy.pos, nearestEnemy.pos)

      # Second chain with Lightning Mastery
      if game.player.hasLightningMastery:
        var secondNearestDist = chainRange + 1.0
        var secondNearestEnemy: Enemy = nil

        for other in game.enemies:
          if other != enemy and other != nearestEnemy:
            let chainDist = distance(nearestEnemy.pos, other.pos)
            if chainDist < chainRange and chainDist < secondNearestDist:
              secondNearestDist = chainDist
              secondNearestEnemy = other

        if secondNearestEnemy != nil:
          let secondChainDamageWithCrit = applyCriticalHitFromStats(stats, baseDamage * 0.7)
          let secondChainDamage = damageEnemy(secondNearestEnemy, secondChainDamageWithCrit)

          # Track second chain damage, belongs to puChainLightning regardless of trigger source
          trackPowerUpDamage(game, puChainLightning, secondChainDamage)

          game.showDamage(secondNearestEnemy.pos, secondChainDamage, fromPlayer = true,
                          isCritical = secondChainDamageWithCrit > baseDamage * 0.7, damageType = dtLightning)

          secondNearestEnemy.slowTimer = 0.2
          if secondNearestEnemy.slowAmount < 0.25:
            secondNearestEnemy.slowAmount = 0.25

          # Lightning arc from first chain to second chain
          spawnLightningBolt(game, nearestEnemy.pos, secondNearestEnemy.pos)

    # Apply slow to primary target if has Lightning Mastery
    if game.player.hasLightningMastery:
      enemy.slowTimer = 0.2
      if enemy.slowAmount < 0.25:
        enemy.slowAmount = 0.25

    # Yellow particles
    spawnExplosionPooled(game.particlePool, orbPos.x, orbPos.y, Yellow, 5)

  of etWind:
    # Wind: Knockback
    let pushDir = (enemy.pos - game.player.pos).normalize()
    var pushForce = 200.0
    let bossResistance = if enemy.isBoss: 0.1 else: 1.0

    if game.player.hasWindMastery:
      pushForce *= 2.5  # +150% stronger

    enemy.pos.x += pushDir.x * pushForce * dt * bossResistance
    enemy.pos.y += pushDir.y * pushForce * dt * bossResistance

    # Clamp to screen boundaries - enemies can't be pushed through borders
    enemy.pos.x = clamp(enemy.pos.x, enemy.radius, game.screenWidth.float32 - enemy.radius)
    enemy.pos.y = clamp(enemy.pos.y, enemy.radius, game.screenHeight.float32 - enemy.radius)

    # Apply slow only with Wind Mastery
    if game.player.hasWindMastery:
      enemy.slowTimer = 0.2
      if enemy.slowAmount < 0.40:
        enemy.slowAmount = 0.40  # 40% slow

    # Cyan particles
    spawnExplosionPooled(game.particlePool, orbPos.x, orbPos.y,
                   Color(r: 200, g: 230, b: 255, a: 255), 5)

  of etFrost:
    # Frost: Permanent slow
    enemy.slowTimer = 999.0
    var frostSlow = 0.3  # Base 30%

    if game.player.hasFrostMastery:
      frostSlow = 0.5  # 50% with mastery

    if enemy.slowAmount < frostSlow:
      enemy.slowAmount = frostSlow

    # Light blue particles
    spawnExplosionPooled(game.particlePool, orbPos.x, orbPos.y,
                   Color(r: 150, g: 200, b: 255, a: 255), 5)

  of etArcane:
    # Arcane: Pure damage (already applied) + purple sparkles
    spawnExplosionPooled(game.particlePool, orbPos.x, orbPos.y,
                   Color(r: 200, g: 100, b: 255, a: 255), 5)

  of etBlood:
    # Blood: Lifesteal
    var lifestealPercent = 0.05  # Base 5%

    if game.player.hasBloodMastery:
      lifestealPercent *= 2.0  # 10.0% with mastery

    let healAmount = baseDamage * lifestealPercent
    game.player.hp = min(game.player.hp + healAmount, game.player.maxHp)
    if healAmount > 0.0:
      trackPowerUpHealing(game, puBloodOrb, healAmount)

    if healAmount > 0.01:
      game.showDamage(game.player.pos, healAmount, fromPlayer = true,
                      isCritical = false, damageType = dtHeal)

      # Green healing particles at player
      spawnExplosionPooled(game.particlePool, game.player.pos.x, game.player.pos.y,
                     Color(r: 100, g: 255, b: 100, a: 255), 3)

    # Red blood particles at hit location
    spawnExplosionPooled(game.particlePool, orbPos.x, orbPos.y,
                   Color(r: 255, g: 50, b: 50, a: 255), 5)

  of etNone:
    discard

proc updateOrbitalWeapons(game: var Game, dt: float32) =
  ## Update all rotating orbs and handle collisions with enemies

  # Check if player has any orb power-ups
  if not hasAnyOrbPowerUp(game.player):
    return

  # Calculate combat stats once for all orb hits this frame
  let orbStats = calculateCombatStats(game.player)

  # Calculate base damage
  let damageScaling = game.player.damage * 0.2
  let baseDamage = if hasPowerUp(game.player, puRotatingOrbs):
    5.0 + damageScaling  # Legendary version
  else:
    # For individual orbs, use level-based damage
    var maxDamage = 0.0
    if hasPowerUp(game.player, puPoisonOrb):
      maxDamage = max(maxDamage, getElementDamage(getPowerUpLevel(game.player, puPoisonOrb)))
    if hasPowerUp(game.player, puFireOrb):
      maxDamage = max(maxDamage, getElementDamage(getPowerUpLevel(game.player, puFireOrb)))
    if hasPowerUp(game.player, puLightningOrb):
      maxDamage = max(maxDamage, getElementDamage(getPowerUpLevel(game.player, puLightningOrb)))
    if hasPowerUp(game.player, puWindOrb):
      maxDamage = max(maxDamage, getElementDamage(getPowerUpLevel(game.player, puWindOrb)))
    if hasPowerUp(game.player, puFrostOrb):
      maxDamage = max(maxDamage, getElementDamage(getPowerUpLevel(game.player, puFrostOrb)))
    if hasPowerUp(game.player, puArcaneOrb):
      maxDamage = max(maxDamage, getElementDamage(getPowerUpLevel(game.player, puArcaneOrb)))
    if hasPowerUp(game.player, puBloodOrb):
      maxDamage = max(maxDamage, getElementDamage(getPowerUpLevel(game.player, puBloodOrb)))
    maxDamage + damageScaling

  let orbRadius = 7.5
  let orbDetectionRange = 0.0

  # Update each orb
  for orb in game.player.rotatingOrbs:
    # Calculate orb position (rings 2 and 4 orbit backwards)
    let orbRotDir = if orb.orbLevel == 2 or orb.orbLevel == 4: -1.0'f32 else: 1.0'f32
    let angle = orbRotDir * game.player.orbRotationAngle + orb.angle
    let orbX = game.player.pos.x + cos(angle) * orb.radius
    let orbY = game.player.pos.y + sin(angle) * orb.radius
    let orbPos = newVector2f(orbX, orbY)

    # Check collisions with enemies
    var enemyIdx = 0
    for enemy in game.enemies:
      let dist = distance(orbPos, enemy.pos)

      # Check if orb is touching enemy
      if dist < orbRadius + enemy.radius + orbDetectionRange:
        # Apply damage
        if applyOrbDamage(game, orb, enemy, baseDamage, orbPos, game.time, enemyIdx, orbStats):
          # Apply element-specific effects
          applyOrbEffects(game, orb, enemy, baseDamage, orbPos, dt, orbStats)

      enemyIdx += 1

    # Clean up old hit times to prevent memory growth
    var toRemove: seq[int] = @[]
    for idx, hitTime in orb.lastHitTime:
      if game.time - hitTime > 2.0:
        toRemove.add(idx)
    for idx in toRemove:
      orb.lastHitTime.del(idx)

