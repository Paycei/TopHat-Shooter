import raylib, rlgl, random, math
import types, player, particle_pool, particle_types, effects, powerup, fx, game/combat
from run_statistics import trackPowerUpDamage, trackPowerUpHealing

type BulletEffects* = tuple[
  slow: float32,
  poison: float32,
  fire: float32,
  wind: float32
]

const WindBulletFlatDamageBonus* = 0.5'f32

# Every mastery except Blood gives the same headline damage bonus (+150%), so a
# player can read "mastery = 2.5x damage on that element" and be right no matter
# which element they drafted. Blood keeps its own (x2 damage + x2 lifesteal)
# because half of its payoff is sustain rather than damage.
#
# Crucially this multiplies the ELEMENT's own damage - a DoT tick, an orb hit,
# an aura pulse - never the bullet's base damage. Scaling a whole bullet by a
# mastery multiplies every other damage power-up along with it, which is how you
# get 6x builds out of two legendaries.
const MasteryDamageMult* = 2.5'f32

# Arcane is the exception on the low side: its mastery also grants piercing (and
# arcane orbs already carry a +50% inherent premium), so its damage bonus is
# held to +75% instead of the shared +150%.
const ArcaneMasteryDmgMult* = 1.75'f32

proc windBulletFlatBonus*(player: Player): float32 =
  ## Wind Bullets' own flat damage contribution to a bullet, mastery included.
  ## The mastery scales this small flat number and nothing else - wind's payoff
  ## is the push and the slow, not the bullet damage.
  result = WindBulletFlatDamageBonus
  if player.hasWindMastery:
    result *= MasteryDamageMult

# Mastery multipliers, shared by every fire/poison DoT source (bullets, auras,
# orbs) so the element identity stays consistent: both masteries hit for the
# same +150%, and the duration multipliers are what keep fire a hot burst and
# poison a long drip.
const
  FireMasteryDmgMult* = MasteryDamageMult
  FireMasteryDurMult* = 1.5'f32
  PoisonMasteryDmgMult* = MasteryDamageMult
  PoisonMasteryDurMult* = 3.0'f32

# COMMON HELPER FUNCTIONS FOR POWER-UP CALCULATIONS

# Lightning visuals moved to src/fx.nim (forwarding stubs kept)
proc spawnLightningBolt*(game: var Game, fromPos, toPos: Vector2f) =
  fx.spawnLightningBoltInto(game.lightningBolts, fromPos, toPos)

proc updateLightningBolts*(game: var Game, dt: float32) =
  fx.updateLightningBolts(game.lightningBolts, dt)

proc drawLightningBolts*(game: Game) =
  fx.drawLightningBolts(game.lightningBolts)

# AoE-blast boundary rings (Star death explosion, etc.), forwarding stubs
proc spawnShockwaveRing*(game: var Game, pos: Vector2f, maxRadius: float32, color: Color) =
  fx.spawnShockwaveRingInto(game.shockwaveRings, pos, maxRadius, color)

proc updateShockwaveRings*(game: var Game, dt: float32) =
  fx.updateShockwaveRings(game.shockwaveRings, dt)

proc drawShockwaveRings*(game: Game) =
  fx.drawShockwaveRings(game.shockwaveRings)

proc getExplosionRadius*(level: int): float32 =
  ## Standard explosion radius for explosive bullets
  case level
  of 1: 50.0
  of 2: 75.0
  else: 100.0

proc getBulletDamageType*(bullet: Bullet): DamageType =
  ## Determine the damage-number color for a bullet's DIRECT hit.
  ## Fire/poison riders deliberately do NOT tint the direct hit: element colors
  ## are reserved for the DoT ticks themselves, so the player can tell their
  ## bullet damage (white) apart from burn/poison damage (orange/green).
  if bullet.isArcaneBullet:
    return dtArcane
  elif bullet.slowAmount > 0:
    return dtFrost  # Frost/slow bullets use the dedicated frost color (light blue)
  elif bullet.windPushForce > 0:
    return dtDefault  # Wind uses default white
  else:
    return dtDefault  # Normal bullets use white

# UNIFIED BULLET EFFECT SYSTEM

type
  BulletEffectType = enum
    befFrost
    befPoison
    befFire
    befWind
    befChainLightning
    befBlood

  BulletEffect = object
    effectType*: BulletEffectType
    baseDamage*: float32
    duration*: float32
    hasMastery*: bool
    level*: int

proc fireDotDamage(level: int, playerDamage: float32): float32 =
  ## Fire identity: hot and fast - high dps over a short burn.
  let base = case level
    of 1: 2.5'f32
    of 2: 3.75'f32
    else: 5.0'f32
  base + playerDamage * 0.25

proc poisonDotDamage(level: int, playerDamage: float32): float32 =
  ## Poison identity: slow drip - lower dps but a much longer duration,
  ## so the total damage slightly exceeds fire's if the target stays alive.
  let base = case level
    of 1: 1.5'f32
    of 2: 2.5'f32
    else: 3.75'f32
  base + playerDamage * 0.2

proc getBulletEffects(game: Game, bullet: Bullet): seq[BulletEffect] =
  ## Extract all active bullet effects from a bullet
  result = @[]
  if bullet.isEcho or bullet.isFromBulletSplit:
    return

  # Frost effect
  if bullet.slowAmount > 0 and hasPowerUp(game.player, puFrostShots):
    result.add(BulletEffect(
      effectType: befFrost,
      baseDamage: bullet.damage,
      duration: 999999.0,  # Infinite
      hasMastery: game.player.hasFrostMastery,
      level: getPowerUpLevel(game.player, puFrostShots)
    ))

  # Poison effect
  if bullet.poisonDuration > 0 and hasPowerUp(game.player, puPoisonShot):
    let lvl = getPowerUpLevel(game.player, puPoisonShot)
    result.add(BulletEffect(effectType: befPoison,
      baseDamage: poisonDotDamage(lvl, game.player.damage),
      duration: bullet.poisonDuration, hasMastery: game.player.hasPoisonMastery, level: lvl))

  # Fire effect
  if bullet.fireDuration > 0 and hasPowerUp(game.player, puFireBullets):
    let lvl = getPowerUpLevel(game.player, puFireBullets)
    result.add(BulletEffect(effectType: befFire,
      baseDamage: fireDotDamage(lvl, game.player.damage),
      duration: bullet.fireDuration, hasMastery: game.player.hasFireMastery, level: lvl))

  # Wind effect
  if bullet.windPushForce > 0 and hasPowerUp(game.player, puWindBullets):
    result.add(BulletEffect(
      effectType: befWind,
      baseDamage: bullet.damage,
      duration: 0.0,  # Instant effect
      hasMastery: game.player.hasWindMastery,
      level: getPowerUpLevel(game.player, puWindBullets)
    ))

  # Chain Lightning effect
  if hasPowerUp(game.player, puChainLightning):
    result.add(BulletEffect(
      effectType: befChainLightning,
      baseDamage: bullet.damage,
      duration: 0.0,  # Instant effect
      hasMastery: game.player.hasLightningMastery,
      level: getPowerUpLevel(game.player, puChainLightning)
    ))

  # Blood effect
  if hasPowerUp(game.player, puBloodBullets):
    result.add(BulletEffect(
      effectType: befBlood,
      baseDamage: bullet.damage,
      duration: 0.0,  # Instant effect
      hasMastery: game.player.hasBloodMastery,
      level: getPowerUpLevel(game.player, puBloodBullets)
    ))

proc applyMasteryDoT*(enemy: Enemy, elemType: ElementType,
                     baseDmg, baseDur: float32,
                     hasMastery: bool,
                     masteryDmgMult, masteryDurMult: float32,
                     masterySlowAmount: float32,
                     source: string) =
  ## Applies a DoT effect with optional mastery bonus and mastery-gated slow.
  ## Slow threshold and multipliers are explicit parameters so each element
  ## can still be tuned independently.
  var dmg = baseDmg
  var dur = baseDur
  if hasMastery:
    dmg *= masteryDmgMult
    dur *= masteryDurMult
  applyEffect(enemy, elemType, dmg, dur, source)
  if hasMastery:
    enemy.slowTimer = 0.2
    if enemy.slowAmount < masterySlowAmount:
      enemy.slowAmount = masterySlowAmount

proc applyBulletEffect(game: var Game, effect: BulletEffect, enemy: Enemy,
                       bullet: Bullet, dt: float32, stats: CombatStats) =
  ## Apply a single bullet effect to an enemy
  ## Uses pre-calculated combat stats for critical hit calculations
  case effect.effectType
  of befFrost:
    # Frost: Permanent slow (reduced by debuffResistance for bosses)
    # Only apply if stronger than current slow or current slow expired
    let newSlowAmount = bullet.slowAmount * (1.0 - enemy.debuffResistance)
    if newSlowAmount > enemy.slowAmount or enemy.slowTimer <= 0:
      enemy.slowTimer = effect.duration
      enemy.slowAmount = newSlowAmount

  of befPoison:
    # applyMasteryDoT handles the DoT; slow is applied separately below
    # because bullet hits need debuffResistance scaling and a stronger-wins guard.
    applyMasteryDoT(enemy, etPoison, effect.baseDamage, effect.duration,
                    effect.hasMastery,
                    masteryDmgMult = PoisonMasteryDmgMult, masteryDurMult = PoisonMasteryDurMult,
                    masterySlowAmount = 0.0, source = "shot")
    if effect.hasMastery:
      let newSlowAmount = 0.40 * (1.0 - enemy.debuffResistance)
      let actualDur = effect.duration * PoisonMasteryDurMult  # already scaled by masteryDurMult
      if newSlowAmount > enemy.slowAmount or enemy.slowTimer <= 0:
        enemy.slowTimer = actualDur
        enemy.slowAmount = newSlowAmount

  of befFire:
    applyMasteryDoT(enemy, etFire, effect.baseDamage, effect.duration,
                    effect.hasMastery,
                    masteryDmgMult = FireMasteryDmgMult, masteryDurMult = FireMasteryDurMult,
                    masterySlowAmount = 0.0, source = "shot")
    if effect.hasMastery:
      let newSlowAmount = 0.45 * (1.0 - enemy.debuffResistance)
      let actualDur = effect.duration * FireMasteryDurMult
      if newSlowAmount > enemy.slowAmount or enemy.slowTimer <= 0:
        enemy.slowTimer = actualDur
        enemy.slowAmount = newSlowAmount

  of befWind:
    # Wind: Knockback
    let pushDir = (enemy.pos - game.player.pos).normalize()
    let bossResistance = if enemy.isBoss: 0.1 else: 1.0

    var actualWindForce = bullet.windPushForce
    if effect.hasMastery:
      actualWindForce *= 3.5  # +250% stronger

    # Apply push
    enemy.pos.x += pushDir.x * actualWindForce * dt * bossResistance
    enemy.pos.y += pushDir.y * actualWindForce * dt * bossResistance

    # Clamp to screen boundaries - enemies can't be pushed through borders
    enemy.pos.x = clamp(enemy.pos.x, enemy.radius, game.screenWidth.float32 - enemy.radius)
    enemy.pos.y = clamp(enemy.pos.y, enemy.radius, game.screenHeight.float32 - enemy.radius)

    # Apply slow only with mastery (reduced by debuffResistance for bosses)
    if effect.hasMastery:
      enemy.slowTimer = 0.2
      let slowValue = 0.45 * (1.0 - enemy.debuffResistance)
      if enemy.slowAmount < slowValue:
        enemy.slowAmount = slowValue  # 45% slow

    # Visual wind effect particles
    for k in 0..3:
      let particleAngle = rand(1.0) * PI * 2.0
      let particleDist = rand(enemy.radius + 10.0)
      let particleX = enemy.pos.x + cos(particleAngle) * particleDist
      let particleY = enemy.pos.y + sin(particleAngle) * particleDist
      spawnExplosionPooled(game.particlePool, particleX, particleY,
                    Color(r: 200, g: 230, b: 255, a: 180), 2)

  of befChainLightning:
    # Chain lightning: Chain to nearby enemies
    if enemy.chainLightningCooldown <= 0:
      let chainCount = effect.level  # 1, 2, or 3 chains
      let chainDamage = case effect.level
        of 1: 0.7
        of 2: 0.85
        else: 1.0

      var chainRange = case effect.level
        of 1: 125.0
        of 2: 150.0
        else: 175.0

      var chainDmgMult = 1.0'f32
      if effect.hasMastery:
        chainRange *= 1.5  # +50% range
        chainDmgMult = MasteryDamageMult  # +150% damage

      # Stun primary target (reduced by debuffResistance for bosses)
      # Only apply if stronger than current slow or current slow expired
      let newSlowAmount = 0.99 * (1.0 - enemy.debuffResistance)  # 99% slow = stun (cap to prevent permanent freeze)
      if newSlowAmount > enemy.slowAmount or enemy.slowTimer <= 0:
        enemy.slowTimer = 0.05
        enemy.slowAmount = newSlowAmount
      enemy.chainLightningCooldown = 0.3

      # Find nearby enemies to chain to
      var chained = 0
      for k in 0..<game.enemies.len:
        if game.enemies[k] != enemy and chained < chainCount:
          let dist = distance(enemy.pos, game.enemies[k].pos)
          if dist < chainRange and game.enemies[k].chainLightningCooldown <= 0:
            let chainDmgBase = effect.baseDamage * chainDamage * chainDmgMult
            let chainDmgWithCrit = applyCriticalHitFromStats(stats, chainDmgBase)
            let actualDamage = damageEnemy(game.enemies[k], chainDmgWithCrit)

            # Track chain lightning damage for statistics
            if actualDamage > 0:
              trackPowerUpDamage(game, puChainLightning, actualDamage)
              if game.player.hasLightningMastery:
                trackPowerUpDamage(game, puLightningMastery, actualDamage)

            # Create damage number
            if actualDamage > 0:
              showDamage(game, game.enemies[k].pos, actualDamage, true,
                        chainDmgWithCrit > chainDmgBase, dtLightning)

            game.enemies[k].chainLightningCooldown = 0.3
            # Only apply stun if stronger than current slow or current slow expired
            let chainSlowAmount = 0.99 * (1.0 - game.enemies[k].debuffResistance)
            if chainSlowAmount > game.enemies[k].slowAmount or game.enemies[k].slowTimer <= 0:
              game.enemies[k].slowTimer = 0.05
              game.enemies[k].slowAmount = chainSlowAmount
            chained += 1

            # Lightning arc visual connecting the two enemies
            spawnLightningBolt(game, enemy.pos, game.enemies[k].pos)

  of befBlood:
    # Blood: Lifesteal
    var healPercent = case effect.level
      of 1: 0.0075  # 0.75%
      of 2: 0.01    # 1.0%
      else: 0.01375 # 1.375%

    if effect.hasMastery:
      healPercent *= 2.0  # +100% lifesteal

    let healAmount = 0.01 + effect.baseDamage * healPercent
    # heal() applies the player's healPowerMult; attribute base vs multiplier separately
    heal(game.player, healAmount)
    if healAmount > 0.01:
      # Attribute the base healing to the lifesteal source
      trackPowerUpHealing(game, puBloodBullets, healAmount)
      # Attribute any bonus from the global heal multiplier to the heal-power power-up
      let bonusHealing = healAmount * (game.player.healPowerMult - 1.0)
      if bonusHealing > 0.001 and hasPowerUp(game.player, puHealPower):
        trackPowerUpHealing(game, puHealPower, bonusHealing)

    if healAmount > 0.01:
      spawnExplosionPooled(game.particlePool, game.player.pos.x, game.player.pos.y, Green, 3)
      showDamage(game, game.player.pos, healAmount, true, false, dtHeal)

proc applyBulletEffects*(game: var Game, bullet: Bullet, enemy: Enemy, dt: float32) =
  ## Apply all bullet effects to an enemy - unified entry point
  let effects = getBulletEffects(game, bullet)

  # Calculate combat stats once for all effects
  let stats = calculateCombatStats(game.player)

  for effect in effects:
    applyBulletEffect(game, effect, enemy, bullet, dt, stats)

