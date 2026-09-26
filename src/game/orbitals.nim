import raylib, rlgl, math, tables
import types, player, particle_pool, particle_types, powerup, game/combat, game/bullets
from run_statistics import trackPowerUpDamage, trackPowerUpDamageWithMastery, trackHealing

# ORBITAL WEAPONS SYSTEM

proc applyOrbDamage(game: var Game, orb: RotatingOrb, enemy: Enemy,
                    baseDamage: float32, orbPos: Vector2f,
                    stats: CombatStats) =
  ## Apply damage from orb to enemy (the caller owns the hit cooldown)

  # Calculate actual damage
  var actualBaseDamage = baseDamage

  # Arcane orbs are pure damage (no DoT/effect), so they get an inherent
  # damage premium over the other elements to make that trade-off worthwhile.
  if orb.elementType == etArcane:
    actualBaseDamage *= 1.5  # +50% base damage

  # Mastery bonus for the elements whose orb payoff is the impact damage itself.
  # Fire/poison orbs get their +150% through the DoT (applyMasteryDoT below) and
  # blood's mastery pays out as lifesteal, so neither is boosted twice here.
  # Mastery bonus for the orbs whose payoff is the impact damage itself. Arcane
  # is capped at +75% (see ArcaneMasteryDmgMult). Fire/poison get theirs through
  # the DoT, and frost/blood masteries pay out as chill and lifesteal instead.
  let orbMasteryMult = case orb.elementType
    of etArcane:
      if game.player.hasArcaneMastery: ArcaneMasteryDmgMult else: 1.0'f32
    of etWind:
      if game.player.hasWindMastery: MasteryDamageMult else: 1.0'f32
    of etLightning:
      if game.player.hasLightningMastery: MasteryDamageMult else: 1.0'f32
    else: 1.0'f32
  actualBaseDamage *= orbMasteryMult

  # Use passed-in stats for crit calculation (avoids recomputing per orb hit)
  let damageWithCrit = applyCriticalHitFromStats(stats, actualBaseDamage)
  let actualDamage = damageEnemy(enemy, damageWithCrit)

  # Track statistics for the orb type.
  #
  # The mastery share is derived from orbMasteryMult, the multiplier that was
  # actually applied above -- so poison/fire/frost/blood masteries (whose payoff
  # is the DoT, the chill and the lifesteal, and which leave orbMasteryMult at
  # 1.0) are no longer credited impact damage they did not add.
  #
  # With the legendary owned, baseDamage comes from puRotatingOrbs rather than
  # from any element orb's level, so the legendary is the base earner -- but the
  # mastery still gets its cut, which the old branch dropped entirely.
  if orb.elementType != etNone:
    let masteryPower = case orb.elementType
      of etPoison: puPoisonMastery
      of etFire: puFireMastery
      of etLightning: puLightningMastery
      of etWind: puWindMastery
      of etFrost: puFrostMastery
      of etArcane: puArcaneMastery
      else: puBloodMastery
    let basePower =
      if hasPowerUp(game.player, puRotatingOrbs): puRotatingOrbs
      else:
        case orb.elementType
        of etPoison: puPoisonOrb
        of etFire: puFireOrb
        of etLightning: puLightningOrb
        of etWind: puWindOrb
        of etFrost: puFrostOrb
        of etArcane: puArcaneOrb
        else: puBloodOrb
    trackPowerUpDamageWithMastery(game, basePower, masteryPower, actualDamage, orbMasteryMult)

  # Create damage number
  game.showDamage(enemy.pos, actualDamage, fromPlayer = true,
                  isCritical = damageWithCrit > actualBaseDamage, damageType = dtDefault)

proc applyOrbEffects(game: var Game, orb: RotatingOrb, enemy: Enemy,
                     baseDamage: float32, orbPos: Vector2f, dt: float32,
                     stats: CombatStats, shielded: bool) =
  ## Apply element-specific effects from orb to enemy. `shielded` = a Port
  ## Guard's shield took the orb: its burns and lifesteal ride on damage that
  ## never landed, so they are dropped (knockback, chill and chains still go).
  if shielded and orb.elementType in {etPoison, etFire, etBlood}:
    return

  case orb.elementType
  of etPoison:
    let poisonDmg = 0.25 + game.player.damage * 0.18
    applyMasteryDoT(enemy, etPoison, poisonDmg, 5.0,
                    game.player.hasPoisonMastery,
                    masteryDmgMult = PoisonMasteryDmgMult, masteryDurMult = PoisonMasteryDurMult,
                    masterySlowAmount = 0.40, source = "orb")

    # Green particles
    spawnExplosionPooled(game.particlePool, orbPos.x, orbPos.y,
                   Color(r: 100, g: 255, b: 100, a: 255), 5)

  of etFire:
    let fireDmg = 0.5 + game.player.damage * 0.22
    applyMasteryDoT(enemy, etFire, fireDmg, 2.0,
                    game.player.hasFireMastery,
                    masteryDmgMult = FireMasteryDmgMult, masteryDurMult = FireMasteryDurMult,
                    masterySlowAmount = 0.45, source = "orb")

    # Orange/red particles
    spawnExplosionPooled(game.particlePool, orbPos.x, orbPos.y, Orange, 5)
    spawnExplosionPooled(game.particlePool, orbPos.x, orbPos.y, Red, 3)

  of etLightning:
    # Lightning: Chain to nearby enemies
    let chainRange = 80.0
    # The chains are computed from the raw orb damage (not the mastery-boosted
    # impact value in applyOrbDamage), so the +150% has to be applied here too.
    let chainBase = baseDamage * 0.7 *
      (if game.player.hasLightningMastery: MasteryDamageMult else: 1.0'f32)

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
      let chainDamageWithCrit = applyCriticalHitFromStats(stats, chainBase)
      let chainDamage =
        if shieldBlocksHit(game, nearestEnemy, enemy.pos): 0.0'f32
        else: damageEnemy(nearestEnemy, chainDamageWithCrit)

      # Track lightning orb chain damage, belongs to puChainLightning regardless of trigger source
      trackPowerUpDamage(game, puChainLightning, chainDamage)

      if chainDamage > 0:
        game.showDamage(nearestEnemy.pos, chainDamage, fromPlayer = true,
                        isCritical = chainDamageWithCrit > chainBase, damageType = dtLightning)

      # Apply slow if has Lightning Mastery
      if game.player.hasLightningMastery:
        applySlow(nearestEnemy, 0.25, 0.2)  # 25% slow

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
          let secondChainDamageWithCrit = applyCriticalHitFromStats(stats, chainBase)
          let secondChainDamage =
            if shieldBlocksHit(game, secondNearestEnemy, nearestEnemy.pos): 0.0'f32
            else: damageEnemy(secondNearestEnemy, secondChainDamageWithCrit)

          # Track second chain damage, belongs to puChainLightning regardless of trigger source
          trackPowerUpDamage(game, puChainLightning, secondChainDamage)

          if secondChainDamage > 0:
            game.showDamage(secondNearestEnemy.pos, secondChainDamage, fromPlayer = true,
                            isCritical = secondChainDamageWithCrit > chainBase, damageType = dtLightning)

          applySlow(secondNearestEnemy, 0.25, 0.2)

          # Lightning arc from first chain to second chain
          spawnLightningBolt(game, nearestEnemy.pos, secondNearestEnemy.pos)

    # Apply slow to primary target if has Lightning Mastery
    if game.player.hasLightningMastery:
      applySlow(enemy, 0.25, 0.2)

    # Yellow particles
    spawnExplosionPooled(game.particlePool, orbPos.x, orbPos.y, Yellow, 5)

  of etWind:
    # Wind: Knockback, as a single impulse through enemy.knockbackVel (it used
    # to be a dt-scaled one-frame nudge: a few pixels, and frame-rate dependent).
    let pushDir = (enemy.pos - game.player.pos).normalize()
    var pushForce = 200.0'f32
    let bossResistance = if enemy.isBoss: 0.1'f32 else: 1.0'f32

    if game.player.hasWindMastery:
      pushForce *= 3.5  # +250% stronger

    let launch = pushDir * (windHitLaunch(pushForce) * bossResistance)
    if launch.length() > enemy.knockbackVel.length():
      enemy.knockbackVel = launch

    # Apply slow only with Wind Mastery
    if game.player.hasWindMastery:
      applySlow(enemy, 0.45, 0.2)  # 45% slow

    # Cyan particles
    spawnExplosionPooled(game.particlePool, orbPos.x, orbPos.y,
                   Color(r: 200, g: 230, b: 255, a: 255), 5)

  of etFrost:
    # Frost: Permanent slow, in the frost slot so short slows can't erase it
    var frostSlow = 0.3'f32  # Base 30%

    if game.player.hasFrostMastery:
      frostSlow = 0.55  # 55% with mastery

    applyFrostChill(enemy, frostSlow)

    # Light blue particles
    spawnExplosionPooled(game.particlePool, orbPos.x, orbPos.y,
                   Color(r: 150, g: 200, b: 255, a: 255), 5)

  of etArcane:
    # Arcane: Pure damage (already applied) + purple sparkles
    spawnExplosionPooled(game.particlePool, orbPos.x, orbPos.y,
                   Color(r: 200, g: 100, b: 255, a: 255), 5)

  of etBlood:
    # Blood: Lifesteal
    let masteryMult =
      if game.player.hasBloodMastery: BloodMasteryLifestealMult  # 10.0% with mastery
      else: 1.0'f32
    let lifestealPercent = 0.045'f32 * masteryMult  # Base 4.5%

    # Goes through heal() like every other lifesteal source: it was the only one
    # writing hp directly, which silently skipped the player's heal-power
    # multiplier and booked overheal as healing.
    let orbHeal = baseDamage * lifestealPercent
    let restored = heal(game.player, orbHeal)
    trackHealing(game, puBloodOrb, orbHeal, restored, masteryMult)

    if restored > 0.01:
      game.showDamage(game.player.pos, restored, fromPlayer = true,
                      isCritical = false, damageType = dtHeal)

      # Green healing particles at player
      spawnExplosionPooled(game.particlePool, game.player.pos.x, game.player.pos.y,
                     Color(r: 100, g: 255, b: 100, a: 255), 3)

    # Red blood particles at hit location
    spawnExplosionPooled(game.particlePool, orbPos.x, orbPos.y,
                   Color(r: 255, g: 50, b: 50, a: 255), 5)

  of etNone:
    discard

proc updateOrbitalWeapons*(game: var Game, dt: float32) =
  ## Update all rotating orbs and handle collisions with enemies

  # Check if player has any orb power-ups
  if not hasAnyOrbPowerUp(game.player):
    return

  # Calculate combat stats once for all orb hits this frame
  let orbStats = calculateCombatStats(game.player)

  # Calculate base damage
  let damageScaling = game.player.damage * 0.18
  let baseDamage = if hasPowerUp(game.player, puRotatingOrbs):
    4.5 + damageScaling  # Legendary version
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
    for enemy in game.enemies:
      let dist = distance(orbPos, enemy.pos)

      # Check if orb is touching enemy. The 0.5s hit cooldown is keyed by the
      # enemy's stable id. It used to be keyed by its index in game.enemies,
      # which shifts every time an enemy dies, so the cooldown jumped onto
      # whichever enemy slid into that slot.
      if dist < orbRadius + enemy.radius + orbDetectionRange and
          orb.lastHitTime.getOrDefault(enemy.id, -1.0) <= game.time - 0.5:
        orb.lastHitTime[enemy.id] = game.time
        # A Port Guard facing the player takes the orb on its shield. A
        # blocked touch still spends the cooldown, so it sparks once per
        # window instead of every frame.
        let shielded = shieldBlocksHit(game, enemy, game.player.pos)
        if not shielded:
          applyOrbDamage(game, orb, enemy, baseDamage, orbPos, orbStats)
        # Apply element-specific effects
        applyOrbEffects(game, orb, enemy, baseDamage, orbPos, dt, orbStats, shielded)

    # Clean up old hit times to prevent memory growth
    var toRemove: seq[int] = @[]
    for idx, hitTime in orb.lastHitTime:
      if game.time - hitTime > 2.0:
        toRemove.add(idx)
    for idx in toRemove:
      orb.lastHitTime.del(idx)

