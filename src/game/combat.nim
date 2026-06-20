import raylib, rlgl, random, types, particle, particle_pool, particle_types, powerup, run_statistics, boss_weakpoints
import ui/os_background

const GATE_DAMAGE_LEAK* = 0.04'f32  # fraction of body damage that still lands while a boss gate (adds/shield) is up

proc applyEliteModifiers(enemy: Enemy, baseDamage: float32): float32 =
  ## Applies elite damage modifiers (tank reduction, shield absorption) and boss defense multiplier
  ## Returns the actual damage to apply to enemy HP
  ## Handles multiple elite types for wave 25+ elites
  ##
  ## Note: enemy is a ref object, so field mutations below (e.g. enemy.shieldHp -= ...)
  ## are intentional and persist on the heap even though the parameter is a let binding.
  result = baseDamage

  # Boss defense multiplier: reduces all incoming damage
  if enemy.isBoss and enemy.defenseMultiplier > 0:
    result *= enemy.defenseMultiplier

  # Tank elite: still durable, but no longer late-midgame mini-bosses.
  # If multiple elites include Tank, apply reduction
  if enemy.isElite and etTank in enemy.eliteTypes:
    result *= 0.65  # 65% damage taken

  # Shielded elite: shield absorbs damage first
  if enemy.isElite and etShielded in enemy.eliteTypes and enemy.shieldHp > 0:
    if enemy.shieldHp >= result:
      # Shield absorbs all damage
      enemy.shieldHp -= result
      result = 0
    else:
      # Shield breaks, remaining damage goes to HP
      result -= enemy.shieldHp
      enemy.shieldHp = 0

  # Diamond enemy: 1-hit shield absorbs the first hit entirely (like Celestial Veil)
  if enemy.enemyType == etDiamond and enemy.diamondShieldActive:
    enemy.diamondShieldActive = false
    result = 0

proc applyEnemyHpDamage*(enemy: Enemy, damage: float32): float32 =
  ## Applies raw HP damage. Bosses only lose HP from the active phase pool.
  if damage <= 0.0'f32:
    return 0.0'f32

  if enemy.isBoss:
    if enemy.invulnerabilityTimer > 0:
      return 0.0'f32

    let dealt = min(damage, max(enemy.hp, 0.0'f32))
    enemy.hp -= dealt
    return dealt

  enemy.hp -= damage
  damage

proc damageEnemy*(enemy: Enemy, baseDamage: float32): float32 =
  ## Helper to apply damage to enemy with elite modifiers
  ## Combines applyEliteModifiers and HP reduction in one call
  ## Returns the actual damage dealt after modifiers
  ## Note: Enemies can die (hp = 0) but can't have fractional HP below 0.01 while alive

  # Check boss invulnerability (during phase transitions)
  if enemy.isBoss and enemy.invulnerabilityTimer > 0:
    return 0.0

  result = applyEliteModifiers(enemy, baseDamage)
  result *= bossWeakPointDamageMultiplier(enemy, bwdsPassive)

  # Boss gate: while adds are alive or the overload shield is up (and no
  # vulnerability window is open), throttle non-bullet damage too. Otherwise a
  # DoT/aura/explosion build could chip a sealed boss and skip the mechanic.
  if enemy.isBoss and enemy.weakPoint.exposedTimer <= 0 and
      (enemy.addsGateActive or enemy.reflectShieldActive):
    result *= GATE_DAMAGE_LEAK

  # Stars use hit counter for ALL damage sources
  if enemy.enemyType == etStar:
    enemy.hitCount += 1
  else:
    result = applyEnemyHpDamage(enemy, result)

# CENTRALIZED COMBAT STATS SYSTEM
# Single source of truth for all combat-related stat calculations
type CombatStats* = object
  damage*: float32          # Final damage with all bonuses
  baseDamage*: float32      # Base damage before power-ups (for attribution)
  fireRate*: float32        # Current fire rate with all modifiers
  critChance*: int          # Critical hit chance (0-100)
  critMultiplier*: float32  # Critical hit damage multiplier
  hasCrit*: bool            # Whether player has crit power-up

proc calculateCombatStats*(player: Player): CombatStats =
  ## Calculates all combat stats in one place
  ## Single source of truth for damage, fire rate, crit chance calculations
  result.baseDamage = player.damage
  result.damage = player.damage * player.bulletDamageMult  # Include bullet-specific multipliers
  result.fireRate = player.fireRate
  result.critChance = 0
  result.critMultiplier = 2.0
  result.hasCrit = false

  # DAMAGE CALCULATIONS

  # Damage boost consumable
  if player.damageBoostTimer > 0:
    result.damage *= 1.4  # +40% damage

  # Rage power-up - damage increases when HP is low
  for powerUp in player.powerUps:
    if powerUp.powerType == puRage:
      let hpPercent = player.hp / player.maxHp
      let hpLost = 1.0 - hpPercent
      let bonusPerTenPercent = case powerUp.level
        of 1: 0.05  # 5% per 10% HP lost
        of 2: 0.08  # 8% per 10% HP lost
        else: 0.12  # 12% per 10% HP lost
      let damageBonus = 1.0 + (hpLost * 10.0 * bonusPerTenPercent)
      result.damage *= damageBonus

  # Fire rate boost consumable
  if player.fireRateBoostTimer > 0:
    result.fireRate *= 0.75    # 25% faster fire rate (lower value = faster)

  # Double Shot penalty - 25% slower fire rate
  for powerUp in player.powerUps:
    if powerUp.powerType == puDoubleShot:
      result.fireRate *= 1.25  # 25% slower (higher value = slower)

  # Berserker power-up - fire rate increases when HP is low
  for powerUp in player.powerUps:
    if powerUp.powerType == puBerserker:
      let hpPercent = player.hp / player.maxHp
      let hpLost = 1.0 - hpPercent
      let bonusPerTenPercent = case powerUp.level
        of 1: 0.05  # 5% per 10% HP lost
        of 2: 0.08  # 8% per 10% HP lost
        else: 0.15  # 15% per 10% HP lost
      let fireRateBonus = 1.0 + (hpLost * 10.0 * bonusPerTenPercent)
      result.fireRate *= (1.0 / fireRateBonus)  # Lower fire rate value = faster shooting

  # CRITICAL HIT CALCULATIONS

  if hasPowerUp(player, puCriticalHit):
    result.hasCrit = true
    let critLevel = getPowerUpLevel(player, puCriticalHit)
    result.critChance = case critLevel
      of 1: 20  # 20% chance
      of 2: 35  # 35% chance
      else: 50  # 50% chance
    result.critMultiplier = 2.0

proc applyBossArenaCombatBonus*(game: Game, stats: var CombatStats) =
  let bonus = getBossArenaCombatBonus(game.osBackground)
  stats.damage *= bonus.damageMult
  stats.fireRate *= bonus.fireRateMult

proc applyCriticalHitWithFlag*(stats: CombatStats, baseDamage: float32): tuple[damage: float32, wasCrit: bool] =
  ## Applies critical hit using pre-calculated stats
  ## Returns tuple with damage and whether a crit occurred
  if not stats.hasCrit:
    return (baseDamage, false)

  if rand(99) < stats.critChance:
    return (baseDamage * stats.critMultiplier, true)
  else:
    return (baseDamage, false)

proc applyCriticalHitFromStats*(stats: CombatStats, baseDamage: float32): float32 =
  applyCriticalHitWithFlag(stats, baseDamage).damage

# DAMAGE NUMBERS HELPER

proc showDamage*(game: Game, pos: Vector2f, damage: float32, fromPlayer: bool,
                isCritical: bool = false, damageType: DamageType = dtDefault) =
  ## Centralized helper to create and display damage numbers
  game.damageNumbers.add(newDamageNumber(pos.x, pos.y, damage, fromPlayer, isCritical, damageType))

proc showCurrency*(game: Game, pos: Vector2f, amount: int,
                   kind: CurrencyIndicatorKind = cikCredits) =
  ## Centralized helper for floating currency pickup indicators.
  if amount == 0:
    return
  game.currencyIndicators.add(newCurrencyIndicator(pos.x, pos.y, amount, kind))

proc showPerk*(game: Game, pos: Vector2f, text: string, color: Color) =
  ## Centralized helper for floating "+SHIELD" / "+SPEED" style consumable
  ## pickup indicators.
  game.perkIndicators.add(newPerkIndicator(pos.x, pos.y, text, color))

const DAMAGE_NUMBER_INTERVAL = 0.5'f32

proc tickAccumulator*(game: Game, enemy: Enemy, acc: var DamageAccumulator,
                      damage: float32, damageType: DamageType, wasCrit: bool = false) =
  if acc.lastTime == 0:
    acc.lastTime = game.time
  acc.total += damage
  acc.damageType = damageType
  if wasCrit:
    acc.hadCrit = true
  if game.time - acc.lastTime >= DAMAGE_NUMBER_INTERVAL:
    if acc.total > 0:
      game.showDamage(enemy.pos, acc.total, fromPlayer = true,
                      isCritical = acc.hadCrit, damageType = acc.damageType)
    acc.total = 0
    acc.hadCrit = false
    acc.lastTime = game.time

proc flushAccumulator*(game: Game, enemy: Enemy, acc: var DamageAccumulator) =
  if acc.total > 0:
    game.showDamage(enemy.pos, acc.total, fromPlayer = true,
                    isCritical = acc.hadCrit, damageType = acc.damageType)
    acc.total = 0
    acc.hadCrit = false

proc accumulateAndShowAuraDamage*(game: Game, enemy: Enemy, actualDamage: float32,
                                  damageType: DamageType, wasCrit: bool = false) =
  tickAccumulator(game, enemy, enemy.auraAcc, actualDamage, damageType, wasCrit)

proc flushAccumulatedAuraDamage*(game: Game, enemy: Enemy) =
  flushAccumulator(game, enemy, enemy.auraAcc)

proc accumulateAndShowContactDamage*(game: Game, enemy: Enemy, actualDamage: float32) =
  tickAccumulator(game, enemy, enemy.contactAcc, actualDamage, dtDefault)

proc flushAccumulatedContactDamage*(game: Game, enemy: Enemy) =
  flushAccumulator(game, enemy, enemy.contactAcc)

proc calculateContactDamageToEnemy*(player: Player, enemy: Enemy): tuple[damage: float32, wasCrit: bool] =
  ## Player ramming into an enemy deals damage based on:
  ##   - player.damage  (scales with all damage power-ups)
  ##   - player speed   (moving fast = hits harder, standing still = weak tap)
  ##   - max HP         (small bonus for tankier builds)
  ##   - critical hits  (respects the Critical Hit power-up)

  # Base: 50% of the player's current damage stat so it's always meaningful
  # but never outright replaces shooting as the main damage source
  var base = player.damage * 0.5

  # Speed multiplier: 0.5x at zero movement, 1.5x at full speed (175)
  let speedRatio = player.vel.length() / player.baseSpeed
  let speedMult = 0.5 + speedRatio * 1.0   # range: 0.5: 1.5
  base *= speedMult

  # Max-HP bonus: +2% per HP above the base 9, capped at +50%
  let hpBonus = min((player.maxHp - 9.0) * 0.02, 0.5)
  base *= (1.0 + hpBonus)

  # Boss defense multiplier already handled by damageEnemy(), skip here

  # Critical hit, uses the same CombatStats path as bullets
  let stats = calculateCombatStats(player)
  let (finalDamage, wasCrit) = applyCriticalHitWithFlag(stats, base)
  return (finalDamage, wasCrit)

# THORNS REFLECTION HELPER

proc applyThornsReflection*(game: var Game, player: Player, damageToReflect: float32,
                            targetEnemy: Enemy, reflectType: string): float32 =
  ## Centralized thorns reflection calculation
  ## reflectType: "contact" for enemy contact, "bullet" for enemy bullets, "boss" for boss contact
  ## Returns actual damage dealt (after shields/reductions)
  if not hasPowerUp(player, puThorns):
    return 0.0

  let thornsLevel = getPowerUpLevel(player, puThorns)

  let reflectPercent =
    if reflectType in ["bullet", "boss", "contact"]:
      case thornsLevel
      of 1: 1.0'f32  # 100% reflection
      of 2: 2.0'f32  # 200% reflection
      else: 3.0'f32  # 300% reflection
    else: 0.0'f32

  let reflectDamageBase = damageToReflect * reflectPercent

  let hpScaling = player.maxHp * 0.01
  let reflectDamageWithScaling = reflectDamageBase + hpScaling

  # Apply critical hit chance to thorns reflection
  let thornStats = calculateCombatStats(player)
  let reflectDamageWithCrit = applyCriticalHitFromStats(thornStats, reflectDamageWithScaling)
  let actualDamage = damageEnemy(targetEnemy, reflectDamageWithCrit)

  # Track thorns damage for statistics
  trackPowerUpDamage(game, puThorns, actualDamage)

  # Create damage number for thorns reflection
  game.showDamage(targetEnemy.pos, actualDamage, fromPlayer = true,
                  isCritical = reflectDamageWithCrit > reflectDamageBase, damageType = dtDefault)

  # Visual feedback
  spawnExplosionPooled(game.particlePool, targetEnemy.pos.x, targetEnemy.pos.y, Red,
                if reflectType == "boss": 8 elif reflectType == "contact": 6 else: 5)

  return actualDamage

