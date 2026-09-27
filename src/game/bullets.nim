import raylib, rlgl, random, math
import types, player, particle_pool, particle_types, effects, powerup, fx, game/combat
from run_statistics import trackPowerUpDamage, trackPowerUpDamageWithMastery, trackHealing

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

# Blood's mastery splits its budget between damage and lifesteal, so each side
# only doubles. Named so the damage split in the statistics can read the same
# number the damage itself is scaled by.
const BloodMasteryDmgMult* = 2.0'f32
const BloodMasteryLifestealMult* = 2.0'f32
  ## The lifesteal half of that budget. Every blood heal reads it, and so does the
  ## statistics split that credits Blood Mastery its share of the healing.

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
proc spawnLightningBolt*(game: var Game, fromPos, toPos: Vector2f,
                         color: Color = fx.DEFAULT_BOLT_COLOR) =
  fx.spawnLightningBoltInto(game.lightningBolts, fromPos, toPos, color)

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

# Path-swept blast corridors (Aftershock), forwarding stubs
proc spawnPathShockwave*(game: var Game, points: seq[Vector2f], width: float32,
                         color: Color) =
  fx.spawnPathShockwaveInto(game.pathShockwaves, points, width, color)

proc updatePathShockwaves*(game: var Game, dt: float32) =
  fx.updatePathShockwaves(game.pathShockwaves, dt)

proc drawPathShockwaves*(game: Game) =
  fx.drawPathShockwaves(game.pathShockwaves)

# Boss death blast (deallocation sweep), forwarding stubs.
# The sweep's colour is re-exported so the detonation game.nim spawns at the
# corpse can be tinted to match the wave it launches.
export BOSS_DEATH_BLAST_COLOR

proc spawnBossDeathBlast*(game: var Game, pos: Vector2f, maxRadius: float32,
                          sourceEnemyId: int,
                          color: Color = fx.BOSS_DEATH_BLAST_COLOR) =
  fx.spawnBossDeathBlastInto(game.bossDeathBlasts, pos, maxRadius, sourceEnemyId, color)

proc drawBossDeathBlasts*(game: Game) =
  fx.drawBossDeathBlasts(game.bossDeathBlasts)

proc blastFreeFizzle(game: var Game, pos: Vector2f, color: Color) =
  ## The little puff left where the sweep freed one hazard. Angular shards
  ## rather than a soft puff, so an erased projectile reads as data being
  ## dropped rather than as something burning up.
  for i in 0 ..< 5:
    let angle = rand(TAU).float32
    let speed = 50.0'f32 + rand(110.0).float32
    discard game.particlePool.acquireParticleDetailed(
      pos.x, pos.y, cos(angle) * speed, sin(angle) * speed, color,
      lifetime = 0.22'f32 + rand(0.16).float32,
      startSize = 3.5'f32, endSize = 0.0'f32,
      drag = 4.5'f32, glow = 1.5'f32,
      style = (if i mod 2 == 0: psShard else: psSpark),
      layer = plForeground,
      rotation = angle * 180.0'f32 / PI.float32,
      spin = (-420.0 + rand(840.0)).float32)

proc bossHazardDefused*(game: Game, sourceEnemyId: int): bool =
  ## True once a boss-death sweep owns this hazard's firer, which is the moment
  ## that boss died.
  ##
  ## The sweep needs about a second to cross the arena, and a shot it has not
  ## reached yet would still be a live shot -- so landing the killing blow could
  ## still cost the player the run, to a bullet fired by something that no
  ## longer exists. Winning the fight ENDS the fight: from the detonation
  ## onward every hazard that boss put in the air is inert, and the wave that
  ## follows is only the visible clean-up.
  ##
  ## Ownership is matched by sourceEnemyId rather than by defusing each object,
  ## so it also covers what a boss's leftovers would go on to produce -- a
  ## telegraph's lasers, a meteor warning's rocks -- since those inherit the
  ## same dead firer. Every damage path that reads a hazard's owner consults
  ## this, which is what makes "a dead boss cannot damage the player" one rule
  ## rather than a list of special cases.
  if sourceEnemyId < 0: return false
  for blast in game.bossDeathBlasts:
    if blast.sourceEnemyId == sourceEnemyId:
      return true
  false

proc blastFreeBeam(game: var Game, laser: Laser, color: Color) =
  ## A beam is cleared as one object, so its puffs go at the TIPS -- where the
  ## wave actually caught up with it -- and not back at the dead firer the
  ## sweep left behind long ago. The arms mirror how drawLaser lays the beam
  ## out: 0/1 extend both ways on an axis, 2 is a rotated cross, 3 is a single
  ## arm along the rotation.
  const Quarter = (PI / 2.0).float32
  let arms = case laser.direction
    of 0: @[0.0'f32, PI.float32]
    of 1: @[Quarter, -Quarter]
    of 2: @[laser.rotation, laser.rotation + PI.float32,
            laser.rotation + Quarter, laser.rotation - Quarter]
    else: @[laser.rotation]
  for a in arms:
    blastFreeFizzle(game, newVector2f(laser.pos.x + cos(a) * laser.length,
                                      laser.pos.y + sin(a) * laser.length), color)

proc blastHasReached(blast: BossDeathBlast, pos: Vector2f,
                     extra: float32 = 0.0'f32): bool =
  ## Has the sweep's edge covered this hazard yet? `extra` is the hazard's own
  ## reach past that point, which is what makes a beam wait until the wave has
  ## washed past its tip rather than popping the instant the edge leaves its
  ## firer.
  ##
  ## The maxRadius fallback is the guarantee that nothing of the boss survives:
  ## a hazard can sit -- or a screen-diagonal beam can reach -- well outside the
  ## arena, where no amount of expansion the player can SEE would ever cover it,
  ## so the sweep's final step takes whatever is left.
  distance(pos, blast.pos) + extra <= blast.radius or
    blast.radius >= blast.maxRadius

proc updateBossDeathBlasts*(game: var Game, dt: float32) =
  ## Advance every boss-death sweep and erase the hazards its edge has reached.
  ##
  ## The wave only ever DELETES. It never calls takeDamage, damageEnemy or any
  ## other damage path, so it is safe to let it cover the whole arena: the
  ## player, surviving minions and the boss's reward drops are untouched. Only
  ## hazards whose sourceEnemyId matches the dead boss are swept, so a minion's
  ## bullets keep flying and the fight around the corpse continues honestly.
  var i = 0
  while i < game.bossDeathBlasts.len:
    let blast = game.bossDeathBlasts[i]

    # Spent sweep: nothing left to clear, just fade the ring out.
    if blast.radius >= blast.maxRadius:
      blast.fadeTimer -= dt
      if blast.fadeTimer <= 0:
        game.bossDeathBlasts.delete(i)
      else:
        inc i
      continue

    blast.radius = min(blast.radius + blast.speed * dt, blast.maxRadius)

    # Projectiles: gone the moment the edge passes over them. The test is
    # ownership plus which way the shot is pointed, NOT isBossBullet -- a shot
    # the boss's reflect shield turned back on the player keeps its player-fired
    # shape and only hands over its ownership, and it is every bit as much a
    # hazard the dead boss put in the air. A bullet the player has since parried
    # back has fromPlayer set again, so it correctly survives the sweep.
    var b = 0
    while b < game.bullets.len:
      let bullet = game.bullets[b]
      if not bullet.fromPlayer and bullet.sourceEnemyId == blast.sourceEnemyId and
         blastHasReached(blast, bullet.pos):
        blastFreeFizzle(game, bullet.pos, blast.color)
        game.bullets.delete(b)
      else:
        inc b

    # Beams anchor on their firer and reach `length` outward from it, so
    # clearing one the instant the edge touches its origin would pop every
    # boss beam at once, and clearing it halfway would leave a floating stub.
    # Instead a beam goes when the wave has washed past its far tip -- the same
    # "cleared once the edge arrives" rule, applied to the furthest point the
    # beam actually occupies.
    var l = 0
    while l < game.lasers.len:
      let laser = game.lasers[l]
      if laser.sourceEnemyId == blast.sourceEnemyId and
         blastHasReached(blast, laser.pos, laser.length):
        blastFreeBeam(game, laser, blast.color)
        game.lasers.delete(l)
      else:
        inc l

    # Meteorites: while a rock is still telegraphing it sits off-screen, so the
    # edge is tested against the marked impact point instead -- otherwise the
    # warning circle would outlive the boss and land on an empty arena.
    var m = 0
    while m < game.meteorites.len:
      let rock = game.meteorites[m]
      let at = if rock.warningTimer > 0: rock.targetPos else: rock.pos
      if rock.sourceEnemyId == blast.sourceEnemyId and
         blastHasReached(blast, at):
        blastFreeFizzle(game, at, blast.color)
        game.meteorites.delete(m)
      else:
        inc m

    # Telegraphs: an un-fired warning is a hazard too -- left alone it would
    # spawn its lasers or bullets seconds after the boss is already dead.
    var w = 0
    while w < game.attackWarnings.len:
      let warn = game.attackWarnings[w]
      if warn.sourceEnemyId == blast.sourceEnemyId and
         blastHasReached(blast, warn.pos):
        blastFreeFizzle(game, warn.pos, blast.color)
        game.attackWarnings.delete(w)
      else:
        inc w

    inc i

const
  WindHitLaunchScale* = 0.5'f32
    ## Converts a wind push "force" (windPushForce, the Wind orb's pushForce) into
    ## the launch speed fed to enemy.knockbackVel. Those forces were tuned as a
    ## per-frame nudge scaled by dt; as a launch speed that coasts to a stop
    ## (~speed / 4.2 px of travel, see the decay in game.nim) they are ~14x too
    ## strong, so they are scaled down here and capped below.
  WindHitMaxLaunch* = 700.0'f32
    ## Ceiling on a single wind hit's launch (~170 px), the Wind Aura's own level-3
    ## gust. Without it Wind Mastery + Heavy Rounds reached 2100 px/s (~500 px per
    ## bullet) and pinned whole waves against the arena edge.

proc windHitLaunch*(force: float32): float32 =
  ## Launch speed for one wind hit of the given push force (before boss resistance).
  min(force * WindHitLaunchScale, WindHitMaxLaunch)

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
  # hasMastery is recorded ON the effect so the tick-time statistics credit the
  # mastery only for DoTs it actually amplified, rather than reading the player's
  # current flag against a burn applied before the mastery was picked.
  applyEffect(enemy, elemType, dmg, dur, source, hasMastery)
  if hasMastery:
    applySlow(enemy, masterySlowAmount, 0.2)

proc applyBulletEffect(game: var Game, effect: BulletEffect, enemy: Enemy,
                       bullet: Bullet, dt: float32, stats: CombatStats,
                       shielded: bool) =
  ## Apply a single bullet effect to an enemy
  ## Uses pre-calculated combat stats for critical hit calculations.
  ## `shielded` = a Port Guard's shield took the shot: the burns and the
  ## lifesteal ride on damage that never landed, so they are dropped.
  if shielded and effect.effectType in {befPoison, befFire, befBlood}:
    return
  case effect.effectType
  of befFrost:
    # Frost: Permanent slow (reduced by debuffResistance for bosses). Kept in
    # its own slot so a short stun or aura slow can't cut it short.
    applyFrostChill(enemy, bullet.slowAmount * (1.0 - enemy.debuffResistance))

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
      applySlow(enemy, newSlowAmount, actualDur)

  of befFire:
    applyMasteryDoT(enemy, etFire, effect.baseDamage, effect.duration,
                    effect.hasMastery,
                    masteryDmgMult = FireMasteryDmgMult, masteryDurMult = FireMasteryDurMult,
                    masterySlowAmount = 0.0, source = "shot")
    if effect.hasMastery:
      let newSlowAmount = 0.45 * (1.0 - enemy.debuffResistance)
      let actualDur = effect.duration * FireMasteryDurMult
      applySlow(enemy, newSlowAmount, actualDur)

  of befWind:
    # Wind: Knockback. A hit is a single impulse, so it feeds enemy.knockbackVel
    # (a launch speed that coasts to a stop, integrated and screen-clamped in
    # game.nim) like Heavy Rounds and the Wind Aura. It used to be a one-frame
    # position nudge scaled by dt: ~2 px per hit at 60 fps, and weaker still at
    # higher frame rates.
    let pushDir = (enemy.pos - game.player.pos).normalize()
    let bossResistance = if enemy.isBoss: 0.1'f32 else: 1.0'f32

    var actualWindForce = bullet.windPushForce
    if effect.hasMastery:
      actualWindForce *= 3.5  # +250% stronger

    # Never accumulate, and never cancel a stronger shove already in flight.
    let launch = pushDir * (windHitLaunch(actualWindForce) * bossResistance)
    if launch.length() > enemy.knockbackVel.length():
      enemy.knockbackVel = launch

    # Apply slow only with mastery (reduced by debuffResistance for bosses)
    if effect.hasMastery:
      applySlow(enemy, 0.45 * (1.0 - enemy.debuffResistance), 0.2)  # 45% slow

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
      applySlow(enemy, newSlowAmount, 0.05)
      enemy.chainLightningCooldown = 0.3

      # Find nearby enemies to chain to
      var chained = 0
      for k in 0..<game.enemies.len:
        if game.enemies[k] != enemy and chained < chainCount:
          let dist = distance(enemy.pos, game.enemies[k].pos)
          if dist < chainRange and game.enemies[k].chainLightningCooldown <= 0:
            let chainDmgBase = effect.baseDamage * chainDamage * chainDmgMult
            let chainDmgWithCrit = applyCriticalHitFromStats(stats, chainDmgBase)
            let actualDamage =
              if shieldBlocksHit(game, game.enemies[k], enemy.pos): 0.0'f32
              else: damageEnemy(game.enemies[k], chainDmgWithCrit)

            # Track chain lightning damage, splitting off the mastery's share.
            # Keyed off effect.hasMastery -- the flag that actually scaled
            # chainDmgMult above -- not the player's live mastery state.
            if actualDamage > 0:
              trackPowerUpDamageWithMastery(game, puChainLightning, puLightningMastery,
                                            actualDamage, chainDmgMult)

            # Create damage number
            if actualDamage > 0:
              showDamage(game, game.enemies[k].pos, actualDamage, true,
                        chainDmgWithCrit > chainDmgBase, dtLightning)

            game.enemies[k].chainLightningCooldown = 0.3
            applySlow(game.enemies[k], 0.99 * (1.0 - game.enemies[k].debuffResistance), 0.05)
            chained += 1

            # Lightning arc visual connecting the two enemies
            spawnLightningBolt(game, enemy.pos, game.enemies[k].pos)

  of befBlood:
    # Blood: Lifesteal
    let baseHealPercent = case effect.level
      of 1: 0.0075'f32  # 0.75%
      of 2: 0.01'f32    # 1.0%
      else: 0.01375'f32 # 1.375%
    let healPercent =
      if effect.hasMastery: baseHealPercent * BloodMasteryLifestealMult  # +100% lifesteal
      else: baseHealPercent

    # Per-hit heal, density-normalised (see densityHealScale). heal() applies the
    # multiplier and the max-HP clamp and reports what was ACTUALLY restored, so
    # a hit taken at full HP books nothing instead of inflating lifesteal totals.
    let perHitHeal = (0.01'f32 + effect.baseDamage * healPercent) * densityHealScale(game)
    let restored = heal(game.player, perHitHeal)
    # The mastery doubles only the lifesteal term, not the flat 0.01, so its
    # multiplier on this heal is the ratio against the unmastered figure.
    let bloodMasteryMult = (0.01'f32 + effect.baseDamage * healPercent) /
                           (0.01'f32 + effect.baseDamage * baseHealPercent)
    trackHealing(game, puBloodBullets, perHitHeal, restored, bloodMasteryMult)

    if restored > 0.01:
      spawnExplosionPooled(game.particlePool, game.player.pos.x, game.player.pos.y, Green, 3)
      showDamage(game, game.player.pos, restored, true, false, dtHeal)

proc applyBulletEffects*(game: var Game, bullet: Bullet, enemy: Enemy, dt: float32,
                         shielded = false) =
  ## Apply all bullet effects to an enemy - unified entry point
  let effects = getBulletEffects(game, bullet)

  # Calculate combat stats once for all effects
  let stats = calculateCombatStats(game.player)

  for effect in effects:
    applyBulletEffect(game, effect, enemy, bullet, dt, stats, shielded)

