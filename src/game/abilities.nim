## [Q] legendary actives and wall placement: what a player's ability and wall
## presses do. Both read the active player's intent (input_intent.nim), so the
## host runs them for every player of a co-op run exactly as for the one
## player of a single-player run. main.nim calls them where it used to run them
## inline, ahead of updateGame, under the same gates (cheat menu, dialogs,
## cache reveal, mod screens).

import raylib, std/deques
import ../modding/mod_patch_core
import ../types, ../vec, ../wall, ../powerup, ../particle_pool, ../sound, ../d_systems,
       ../run_statistics, ../effects, ../input_intent, ../coop/coop_context
import ../modding/mod_hooks
import combat, bullets

const WallPlacementRange* = 250.0'f32  ## how far from the player a wall may go

proc updateWallPlacement*(game: var Game) {.moddable.} =
  ## Hold the wall key to preview, release it to place a wall at the aim point.
  let player = game.player
  # Roguelite: the wall key is also the pedestal/stall key. While one is in
  # range, or after a press was spent on one (until that key is let go), it
  # is not a wall key -- placement fires on RELEASE, so without this every
  # purchase would also drop a wall at the cursor.
  let interactOwnsKey = game.mode == gmRoguelite and
    (player.interactFocus or player.interactLatch)
  let eHeld = player.intent.wallHeld and player.walls > 0 and not interactOwnsKey
  game.player.placingWall = eHeld

  # Releasing the wall key places the wall at the aim point.
  if consumeEdge(player, ieWallRelease) and player.walls > 0 and not interactOwnsKey:
    # WORLD coords: the wall lives in the 1024-wide world, which is centered
    # inside the wider virtual screen in widescreen mode, and the intent's aim
    # point is already in world coords (as is the ghost preview in drawGame).
    let wallPos = player.intent.aim
    let inRange = distance(wallPos, player.pos) <= WallPlacementRange
    if inRange and isValidWallPlacement(wallPos, player.pos, game.walls,
                                        game.enemies, 25,
                                        game.screenWidth, game.screenHeight) and
       not modPlaceWall(game, wallPos.x, wallPos.y):
      game.walls.add(newWall(wallPos.x, wallPos.y, player))
      player.walls -= 1
      spawnExplosionPooled(game.particlePool, wallPos.x, wallPos.y, Brown, 15)
      trackWallPlacement(game, wallPos)
  # The spent [E] press stops owning the key once it is let go (cleared
  # after the release check above, so that release never places).
  if player.interactLatch and not player.intent.wallHeld:
    player.interactLatch = false

proc activateLegendaries*(game: var Game) {.moddable.} =
  ## [Q] was pressed: fire every legendary active the player owns at once.
  var anyActivated = false

  # Time Warp - slow down time
  if hasPowerUp(game.player, puTimeWarp) and game.player.timeWarpCooldown <= 0:
    # Check if uses available for this wave
    if game.player.timeWarpUsesThisWave < game.player.timeWarpMaxUsesPerWave:
      let duration = 3.5
      let cooldown = 10.0  # 10 second cooldown between uses

      game.player.timeWarpActive = true
      game.player.timeWarpDuration = duration
      game.player.timeWarpCooldown = cooldown
      game.player.timeWarpUsesThisWave += 1  # Increment uses
      trackTimeWarp(game, duration)
      spawnExplosionPooled(game.particlePool, game.player.pos.x, game.player.pos.y,
                    Color(r: 138, g: 43, b: 226, a: 255), 30)
      anyActivated = true

  # Phase Shift - teleport dash (SINGLE LEVEL - scales with speed)
  if hasPowerUp(game.player, puPhaseShift) and game.player.phaseShiftCooldown <= 0:
    # Distance scales with player movement speed (base 140, scales up with speed)
    let baseDistance = 140.0
    let speedRatio = game.player.speed / game.player.baseSpeed
    let dashDistance = baseDistance * speedRatio

    let cooldown = 5.0  # 5 second cooldown
    let invulnDuration = 0.5  # 0.5 second invulnerability after dash

    # Dash direction: where the player is steering (the keys, or the stick)
    var dashDir = game.player.intent.move

    # Always activate cooldown and invulnerability
    game.player.phaseShiftCooldown = cooldown
    game.player.phaseShiftInvulnTimer = invulnDuration

    if dashDir.length() > 0:
      # Dash in movement direction
      dashDir = dashDir.normalize()
      let shiftStart = game.player.pos
      game.player.lastPhaseShiftPos = shiftStart

      # Land on the farthest point along the dash (in tenths) that is in
      # bounds and clear of every wall. Teleporting blindly could drop the
      # player inside a dungeon obstacle, where movement can never leave it.
      var landing = shiftStart
      for step in countdown(10, 1):
        let reach = dashDistance.float32 * step.float32 / 10.0'f32
        let candidate = vec2(
          clamp(shiftStart.x + dashDir.x * reach, game.player.radius,
                game.screenWidth.float32 - game.player.radius),
          clamp(shiftStart.y + dashDir.y * reach, game.player.radius,
                game.screenHeight.float32 - game.player.radius))
        var blocked = false
        for w in game.walls:
          if checkPlayerWallCollision(candidate, game.player.radius, w):
            blocked = true
            break
        if not blocked:
          landing = candidate
          break
      game.player.pos = landing

      # Record actual distance traveled (post-clamp) for stats
      let actualDashDist = distance(game.player.lastPhaseShiftPos, game.player.pos)
      trackPhaseShift(game, actualDashDist)

      # Visual effects at start and end position
      spawnExplosionPooled(game.particlePool, game.player.lastPhaseShiftPos.x,
                    game.player.lastPhaseShiftPos.y, SkyBlue, 25)
      spawnExplosionPooled(game.particlePool, game.player.pos.x,
                    game.player.pos.y, SkyBlue, 25)
    else:
      # Dash in place - just visual effect (zero distance, still counts as a use)
      trackPhaseShift(game, 0.0)
      spawnExplosionPooled(game.particlePool, game.player.pos.x,
                    game.player.pos.y, SkyBlue, 30)

    anyActivated = true

  # Parry - active defense ability (SINGLE LEVEL - invincible + bounce bullets)
  if hasPowerUp(game.player, puParry) and game.player.parryCooldown <= 0:
    let duration = 0.5  # 0.5 second parry window
    let cooldown = 5.0  # 5 second cooldown

    game.player.parryActive = true
    game.player.parryDuration = duration
    game.player.parryCooldown = cooldown

    spawnExplosionPooled(game.particlePool, game.player.pos.x, game.player.pos.y,
                  Color(r: 255, g: 255, b: 255, a: 255), 35)
    anyActivated = true

  # Blood Pact - sacrifice 25% current HP to unleash an amplified blood
  # nova. Every enemy is hit for a big share of its OWN max HP (so it stays
  # devastating at any wave) plus bonus damage from the blood spent. The
  # damage is NO LONGER split across targets. Bosses resist the nova and
  # are spared while invulnerable during a phase-change transition.
  if hasPowerUp(game.player, puBloodPact) and game.player.bloodPactCooldown <= 0:
    if game.player.hp > 1.0 and game.enemies.len > 0:
      const
        BLOOD_PACT_ENEMY_FRAC = 0.20'f32   # share of a normal enemy's CURRENT HP per cast
        BLOOD_PACT_BOSS_FRAC  = 0.03'f32   # bosses only take a small share
        BLOOD_PACT_BONUS_MULT = 1.0'f32    # bonus damage per point of HP sacrificed
      const
        BloodBright = Color(r: 235, g: 40, b: 40, a: 255)
        BloodDeep   = Color(r: 130, g: 0, b: 25, a: 255)
        BloodPactMaxTethers = 12  # a packed wave would otherwise be a red mesh
      let sacrifice = game.player.hp * 0.25
      game.player.hp = max(0.1, game.player.hp - sacrifice)
      let bonus = sacrifice * BLOOD_PACT_BONUS_MULT

      var tethersDrawn = 0
      for enemy in game.enemies:
        if enemy.isBoss and enemy.invulnerabilityTimer > 0:
          continue  # respect phase-transition invulnerability
        if shieldBlocksHit(game, enemy, game.player.pos):
          continue  # a Port Guard facing the caster takes it on the shield
        let intended = if enemy.isBoss: enemy.maxHp * BLOOD_PACT_BOSS_FRAC + bonus * 0.4
                       else: enemy.hp * BLOOD_PACT_ENEMY_FRAC + bonus
        # Bosses resist it like every other non-bullet damage path: phase
        # defense, the weak-point multiplier and the adds/shield gate.
        let dealt = applyEnemyHpDamage(enemy, intended * bossPassiveDamageTaken(enemy))
        trackPowerUpDamage(game, puBloodPact, dealt)
        if dealt > 0:
          showDamage(game, enemy.pos, dealt, true, false, dtDefault)

        # The pact reaches every enemy at once, so the hit has to be shown
        # ON each enemy - a burst at the player alone reads as "nothing
        # happened" when the victims are across the arena.
        spawnExplosionPooled(game.particlePool, enemy.pos.x, enemy.pos.y,
                             BloodBright, if enemy.isBoss: 26 else: 14)
        if tethersDrawn < BloodPactMaxTethers:
          spawnLightningBolt(game, game.player.pos, enemy.pos, BloodBright)
          inc tethersDrawn

      game.player.bloodPactCooldown = 3.0
      # Self-inflicted detonation at the caster: a deep core plus two rings
      # so the sacrifice reads as an outward pulse, not a puff of smoke.
      spawnNovaExplosionPooled(game.particlePool,
                               game.player.pos.x, game.player.pos.y,
                               95.0'f32, BloodBright, BloodDeep)
      spawnExplosionPooled(game.particlePool, game.player.pos.x,
                           game.player.pos.y, BloodDeep, 40)
      spawnShockwaveRing(game, game.player.pos, 150.0'f32, BloodBright)
      spawnShockwaveRing(game, game.player.pos, 275.0'f32, BloodDeep)
      addShake(game.dopamine.screenShake, siLarge, BloodDeep)
      anyActivated = true

  # Conduit - detonate all active DoTs for 3x remaining tick damage
  if hasPowerUp(game.player, puConduit) and game.player.conduitCooldown <= 0:
    const ConduitMaxArcs = 14  # cap the tethers, not the damage
    var totalDetonated = 0.0
    var arcsDrawn = 0
    for enemy in game.enemies:
      var elementsToDetonate: seq[ElementType] = @[]
      for et, ae in enemy.activeEffects.pairs:
        if ae.primary.isActive and ae.primary.remainingDuration > 0:
          elementsToDetonate.add(et)
      var enemyBurst = 0.0'f32
      for et in elementsToDetonate:
        var ae = enemy.activeEffects[et]
        var burstDmg = ae.primary.remainingDuration * ae.primary.damagePerSec * 3.0
        if et == etPoison:
          # Detonating a ramped poison honors the stacks, then consumes them
          burstDmg *= poisonStackMultiplier(enemy)
          enemy.poisonStacks = 0
        # The ticks being detonated were boss-mitigated; the burst must be too,
        # or a 3x payout ignores every boss resistance and gate.
        burstDmg *= bossPassiveDamageTaken(enemy)
        let dealt = applyEnemyHpDamage(enemy, burstDmg)
        trackPowerUpDamage(game, puConduit, dealt)
        # Color the number by the element that actually detonated, so a
        # multi-element stack reads as several distinct payloads popping.
        if dealt > 0:
          showDamage(game, enemy.pos, dealt, true, false, elementDamageType(et))
        totalDetonated += dealt
        enemyBurst += dealt

        # One burst per detonated element, tinted to that element: this is
        # what makes "your DoTs just exploded" legible at a glance.
        let ec = elementColor(et)
        spawnExplosionPooled(game.particlePool, enemy.pos.x, enemy.pos.y, ec, 16)
        spawnExplosiveRingPooled(game.particlePool, enemy.pos.x, enemy.pos.y,
                                 enemy.radius + 26.0'f32, 2, ec)

        ae.primary.isActive = false
        ae.primary.remainingDuration = 0
        ae.primary.damagePerSec = 0
        ae.fallback.remainingDuration = 0
        enemy.activeEffects[et] = ae

      if enemyBurst > 0:
        # Ring size scales with how much this target had banked, so the
        # juicy targets visibly pop harder than the near-expired ones.
        let ringR = clamp(enemy.radius + 30.0'f32 + enemyBurst * 0.35'f32,
                          40.0'f32, 150.0'f32)
        spawnShockwaveRing(game, enemy.pos, ringR,
                           Color(r: 160, g: 120, b: 255, a: 255))
        if arcsDrawn < ConduitMaxArcs:
          # The player is the conduit; the arc shows the discharge path.
          spawnLightningBolt(game, game.player.pos, enemy.pos,
                             Color(r: 180, g: 150, b: 255, a: 255))
          inc arcsDrawn

    if totalDetonated > 0:
      game.player.conduitCooldown = 15.0
      spawnNovaExplosionPooled(game.particlePool,
                               game.player.pos.x, game.player.pos.y,
                               70.0'f32,
                               Color(r: 160, g: 120, b: 255, a: 255),
                               Color(r: 235, g: 225, b: 255, a: 255))
      addShake(game.dopamine.screenShake,
               if arcsDrawn >= 4: siLarge else: siMedium,
               Color(r: 160, g: 120, b: 255, a: 255))
      anyActivated = true

  # Aftershock - shockwave traces backward along last 2s of movement path
  if hasPowerUp(game.player, puAftershock) and game.player.aftershockCooldown <= 0:
    let history = game.player.aftershockPosHistory
    if history.len >= 2:
      const shockwaveWidth = 50.0
      let baseDamage = game.player.damage * 2.0
      const knockbackForce = 200.0
      const AftershockColor = Color(r: 120, g: 195, b: 255, a: 255)
      var hitEnemyIds: seq[int] = @[]

      # Trace backward through path segments
      var segIdx = history.len - 1
      while segIdx >= 1:
        let segEnd = history[segIdx]
        let segStart = history[segIdx - 1]
        let segVec = segEnd - segStart
        let segLen = segVec.length()
        if segLen > 0.01:
          let segNorm = segVec.normalize()
          for enemy in game.enemies:
            if enemy.id notin hitEnemyIds:
              let toEnemy = enemy.pos - segStart
              let t = clamp(toEnemy.x * segNorm.x + toEnemy.y * segNorm.y, 0.0, segLen)
              let closest = segStart + segNorm * t
              let dist = distance(closest, enemy.pos)
              if dist <= shockwaveWidth + enemy.radius:
                hitEnemyIds.add(enemy.id)
                let dealt =
                  if shieldBlocksHit(game, enemy, closest): 0.0'f32
                  else: applyEnemyHpDamage(enemy, baseDamage * bossPassiveDamageTaken(enemy))
                trackPowerUpDamage(game, puAftershock, dealt)
                if dealt > 0:
                  showDamage(game, enemy.pos, dealt, true, false, dtDefault)
                # Knockback away from path
                let awayFromPath = if dist > 0.1: (enemy.pos - closest).normalize()
                                   else: segNorm * -1.0
                enemy.vel.x += awayFromPath.x * knockbackForce
                enemy.vel.y += awayFromPath.y * knockbackForce
                # Burst at the point on the path that actually caught them,
                # plus a ring on the enemy, so the knockback has a cause.
                spawnExplosionPooled(game.particlePool, closest.x, closest.y,
                                     AftershockColor, 10)
                spawnShockwaveRing(game, enemy.pos,
                                   enemy.radius + 34.0'f32, AftershockColor)
        segIdx -= 1

      # The corridor IS the ability - without drawing it, a player who has
      # run a wide loop just sees enemies fly away from nothing. Feed the
      # sampled path (oldest first) to a swept shockwave; the crest then
      # retraces the route backwards exactly like the damage resolution.
      var pathPoints: seq[Vector2] = @[]
      for p in history:
        pathPoints.add(p)
      spawnPathShockwave(game, pathPoints, shockwaveWidth, AftershockColor)

      # Sparks seeded along the corridor give the swath texture and keep it
      # alive after the crest has passed. Every other sample keeps the cost
      # bounded (the history holds at most 40 points).
      for idx in countup(0, pathPoints.len - 1, 2):
        spawnTrailParticlePooled(game.particlePool,
                                 pathPoints[idx].x, pathPoints[idx].y,
                                 AftershockColor, 4)

      game.player.aftershockCooldown = 14.0
      game.player.aftershockPosHistory.clear()
      spawnNovaExplosionPooled(game.particlePool,
                               game.player.pos.x, game.player.pos.y,
                               shockwaveWidth + 20.0'f32, AftershockColor,
                               Color(r: 240, g: 250, b: 255, a: 255))
      addShake(game.dopamine.screenShake, siLarge, AftershockColor)
      anyActivated = true

  # Nova - freeze all player bullets for 2 seconds, release at 1.5x speed
  if hasPowerUp(game.player, puNova) and game.player.novaCooldown <= 0 and not game.player.novaActive:
    const NovaColor = Color(r: 200, g: 200, b: 255, a: 255)
    game.player.novaActive = true
    game.player.novaFreezeTimer = 2.0
    game.player.novaCooldown = 16.0
    # Freeze all currently-in-flight player bullets
    for bullet in game.bullets:
      if bullet.fromPlayer and ownerSlot(bullet) == game.player.slot:   # (the caster's own)
        bullet.isFrozenByNova = true
        # Mark the moment of capture on each bullet, otherwise the freeze
        # is a state change with no on-screen event at all.
        spawnExplosionPooled(game.particlePool, bullet.pos.x, bullet.pos.y,
                             NovaColor, 4)
    spawnNovaExplosionPooled(game.particlePool,
                             game.player.pos.x, game.player.pos.y,
                             80.0'f32, NovaColor,
                             Color(r: 255, g: 255, b: 255, a: 255))
    # A wide, slow ring reads as the freeze field sweeping outward.
    spawnShockwaveRing(game, game.player.pos, 320.0'f32, NovaColor)
    addShake(game.dopamine.screenShake, siMedium, NovaColor)
    anyActivated = true

  # Mod power-ups with an active ability (register.powerup active)
  if modActivateAbilities(game):
    anyActivated = true

  # Play sound if any ability was activated
  if anyActivated:
    playSound(stPowerUp)
  modAbilityUsed(game)   # mods: [Q] was pressed (after the built-in abilities)
