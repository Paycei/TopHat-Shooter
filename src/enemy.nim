import raylib, types, random, math, wall, boss_definitions, run_statistics, enemy_config, enemy_helpers, boss_weakpoints, effects
import particle_types

proc newEnemy*(x, y: float32, difficulty: float32, enemyType: EnemyType, game: Game): Enemy =
  # Get enemy configuration
  let config = getEnemyConfig(enemyType)

  # Calculate scaled stats
  let stats = getScaledEnemyStats(config, difficulty)

  # Enforce minimum HP of 0.01
  let finalHp = max(stats.hp, 0.01)

  # Create base enemy with config values
  result = Enemy(
    id: game.nextEnemyId,
    pos: newVector2f(x, y),
    vel: newVector2f(0, 0),
    radius: stats.radius,
    collisionRadius: stats.radius * 0.4,  # 40% of visual size for enemy collision
    hp: finalHp,
    maxHp: finalHp,
    speed: stats.speed,
    contactDamage: config.contactDamage,
    rangedDamage: if config.hasRangedAttack: config.attack.damage else: 0,
    color: config.baseColor,
    enemyType: enemyType,
    isBoss: false,
    shootTimer: 0,
    spawnTimer: 0,
    dashTimer: if config.movement.dashCooldown > 0: config.movement.dashCooldown else: 0,
    hitCount: 0,
    requiredHits: stats.requiredHits,
    lastContactDamageTime: 0,
    teleportTimer: 0,
    shockwaveTimer: 0,
    burstTimer: 0,
    lastWallDamageTime: 0,
    attackWarningTimer: 0,
    attackExecuteTimer: if config.specialBehaviorType == "charge_shot":
      block:
        let sd = parseSpecialData(config.specialData)
        getSpecialFloat(sd, "charge_time", 3.0)
      else: 0,
    attackPhase: 0,
    hasEnteredScreen: not config.requiresScreenEntry,  # Inverted logic
    activeEffects: default(array[ElementType, ActiveEffect]),
    dashCooldown: config.movement.dashCooldown,
    hexTeleportTimer: if config.movement.teleportCooldown > 0: config.movement.teleportCooldown + rand(1.0) else: 0,
    fakeWarningTimer: if config.specialBehaviorType == "fake_warning_teleport": 3.0 + rand(2.0) else: 0,
    cloneTimer: if config.specialBehaviorType == "clone_teleport": 2.0 + rand(1.5) else: 0,
    clonePositions: @[],
    rotation: 0.0,
    spawnRingTimer: 0.45'f32
  )

  # Enemy offensive scaling. HP and speed already scale with difficulty, but
  # contact/ranged damage was flat from config. Ramp it with difficulty so enemies
  # grow naturally more dangerous, kicking in past difficulty 3 (~wave 15 in wave
  # mode) so the buff is felt "especially from wave 15 onwards".
  let enemyDamageScale = 1.0'f32 + max(0.0'f32, difficulty - 3.0'f32) * 0.10'f32
  result.contactDamage *= enemyDamageScale
  result.rangedDamage *= enemyDamageScale

  # Initialize boss-spawned flag (default: false, set to true by boss summon)
  result.spawnedByBoss = false
  result.threatLevel = 0

  # Initialize diamond shield (1-hit absorb, like Celestial Veil)
  result.diamondShieldActive = (enemyType == etDiamond)

  # Initialize defense multiplier (default: 1.0 = no reduction, bosses override this)
  if not result.isBoss:
    result.defenseMultiplier = 1.0

  # Initialize debuff resistance (default: 0.0 = no resistance, bosses set to 0.5 = 50% reduction)
  result.debuffResistance = 0.0

  # Prime movement state per enemy type.
  # Some enemies reuse dashCooldown/dashTimer for different phases; spawning them
  # in the wrong state leaves them "dashing" in place with zero velocity.
  case enemyType
  of etTriangle:
    # Triangles should begin in their wind-up/hunt loop, not an active dash.
    result.dashCooldown = 0.0
    result.dashTimer = config.movement.dashCooldown + rand(1.0)
  of etDiamond:
    # Diamonds should start roaming toward the player and only dash after a cooldown.
    result.dashTimer = 0.0
    result.dashCooldown = config.movement.dashCooldown + rand(1.0)
  else:
    discard

  # Increment enemy ID counter for next enemy
  game.nextEnemyId += 1

proc updateEnemy*(enemy: var Enemy, playerPos: Vector2f, dt: float32, walls: seq[Wall], currentTime: float32, game: var Game): bool =
  # Apply slow field effect
  var effectiveSpeed = getEffectiveSpeed(enemy.speed, game.currentWave)
  if enemy.slowAmount > 0:
    effectiveSpeed = effectiveSpeed * (1.0 - enemy.slowAmount)

  if enemy.isBoss:
    # Boss update logic
    if enemy.entranceTimer > 0:
      enemy.entranceTimer -= dt
      # Ease-in quad: gentle start, arrives at full speed, no deceleration pause
      let rawProgress = clamp(1.0 - (enemy.entranceTimer / 2.0), 0.0, 1.0)
      let progress = rawProgress * rawProgress
      enemy.pos.x = enemy.startPos.x + (enemy.targetPos.x - enemy.startPos.x) * progress
      enemy.pos.y = enemy.startPos.y + (enemy.targetPos.y - enemy.startPos.y) * progress
      if enemy.entranceTimer <= 0:
        enemy.pos = enemy.targetPos
        # Reset to 0 so the boss waits a full cooldown before first shot
        enemy.shootTimer = 0
      return true

    enemy.shootTimer += dt
    enemy.spawnTimer += dt

    # Custom bosses are moved by updateCustomBossBehavior in game.nim.
    # Running this generic chase first makes them snap toward the player,
    # especially after a committed dash exits with carried momentum.
    if enemy.bossDefinitionID <= 0:
      let dir = (playerPos - enemy.pos).normalize()
      var canMove = true
      let desiredVel = dir * effectiveSpeed
      let nextPos = enemy.pos + applyEnemyInertia(enemy, desiredVel, dt) * dt
      for wall in walls:
        if wallOverlapsCircle(wall, nextPos, enemy.radius):
          canMove = false
          if currentTime - enemy.lastWallDamageTime >= 1.0:
            wall.takeDamage(1.0)
            trackWallDamaged(game)
            enemy.hp -= 1.0
            # Enforce minimum health of 0.01
            if enemy.hp < 0.01:
              enemy.hp = 0.01
            enemy.lastWallDamageTime = currentTime
          break
      if canMove:
        enemy.pos = enemy.pos + enemy.vel * dt
      else:
        discard applyEnemyInertia(enemy, newVector2f(0, 0), dt)

  else:
    # Regular enemy updates
    case enemy.enemyType
    of etCircle:
      let dir = (playerPos - enemy.pos).normalize()
      var canMove = true
      let desiredVel = dir * effectiveSpeed
      let nextPos = enemy.pos + applyEnemyInertia(enemy, desiredVel, dt) * dt
      for wall in walls:
        if wallOverlapsCircle(wall, nextPos, enemy.radius):
          canMove = false
          if currentTime - enemy.lastWallDamageTime >= 1.0:
            wall.takeDamage(1.0)
            trackWallDamaged(game)
            enemy.hp -= 1.0
            # Enforce minimum health of 0.01
            if enemy.hp < 0.01:
              enemy.hp = 0.01
            enemy.lastWallDamageTime = currentTime
          break
      if canMove:
        enemy.pos = enemy.pos + enemy.vel * dt
      else:
        discard applyEnemyInertia(enemy, newVector2f(0, 0), dt)

    of etCube:
      # Get config for this enemy type
      let config = getEnemyConfig(enemy.enemyType)

      # Update timers
      enemy.shootTimer += dt

      # Check screen entry
      checkScreenEntry(enemy, game)

      # Determine next position
      var nextPos: Vector2f
      if not enemy.hasEnteredScreen:
        # Force entry toward screen center
        nextPos = forceScreenEntry(enemy, playerPos, dt, effectiveSpeed, game)
      else:
        # Maintain optimal distance from player
        nextPos = maintainOptimalDistance(enemy, playerPos, dt, effectiveSpeed, config)
      nextPos = nextInertialEnemyPos(enemy, nextPos, dt)

      # Check collisions
      let hitWall = checkWallCollision(enemy, nextPos, walls, currentTime, game)
      let hitBoundary = checkScreenBoundaryCollision(enemy, nextPos, game, config)

      # Apply movement if no collisions
      if not hitWall and not hitBoundary:
        enemy.pos = nextPos
      else:
        discard applyEnemyInertia(enemy, newVector2f(0, 0), dt)

      # Execute ranged attack (uses config values)
      executeRangedAttack(enemy, playerPos, game)

    of etTriangle:
      # Get config for this enemy type
      let config = getEnemyConfig(enemy.enemyType)

      # Calculate dash speed multiplier from config (dashSpeed / baseSpeed)
      let dashMultiplier = config.movement.dashSpeed / config.movement.baseSpeed

      # dashTimer    = inter-dash cooldown (counts down to 0, then dash fires)
      # dashCooldown = active dash duration (counts down while actually dashing)
      if enemy.dashCooldown > 0:
        # DASHING PHASE: maintain velocity for the full dash duration
        enemy.dashCooldown -= dt
      else:
        enemy.dashTimer -= dt
        if enemy.dashTimer <= 0:
          # Fire the dash, lock direction toward player right now
          let dir = (playerPos - enemy.pos).normalize()
          enemy.vel = dir * effectiveSpeed * dashMultiplier
          enemy.dashCooldown = config.movement.dashDuration  # Active dash duration
          enemy.dashTimer = config.movement.dashCooldown + rand(1.0)  # Next cooldown
          # Show a brief directional warning so the player has a chance to react
          game.attackWarnings.add(newAttackWarning(enemy.pos.x, enemy.pos.y, awtTriangleDash, 0.18))
        else:
          # WIND-UP MOVEMENT: zigzag toward player
          let dir = (playerPos - enemy.pos).normalize()
          let distToPlayer = distance(enemy.pos, playerPos)
          let zigzagAngle = sin(currentTime * 7.0 + enemy.pos.x * 0.05) * 0.5
          let zigzagDir = newVector2f(
            dir.x * cos(zigzagAngle) - dir.y * sin(zigzagAngle),
            dir.x * sin(zigzagAngle) + dir.y * cos(zigzagAngle)
          )
          if distToPlayer > 120:
            discard applyEnemyInertia(enemy, zigzagDir * effectiveSpeed * 0.9, dt)
          else:
            let tangent = newVector2f(-dir.y, dir.x)
            let weaveIntensity = sin(currentTime * 10.0 + enemy.pos.y * 0.05) * 0.5
            let circleDir = (zigzagDir * (0.5 + weaveIntensity * 0.2) + tangent * (0.5 - weaveIntensity * 0.2)).normalize()
            discard applyEnemyInertia(enemy, circleDir * effectiveSpeed * 0.95, dt)
          # Velocity dampening
          enemy.vel = enemy.vel * pow(0.98, 60.0 * dt)
      var canMove = true
      let nextPos = enemy.pos + enemy.vel * dt
      for wall in walls:
        if wallOverlapsCircle(wall, nextPos, enemy.radius):
          canMove = false
          let wallDir = (enemy.pos - wall.pos).normalize()
          enemy.vel = wallDir * effectiveSpeed * 0.85
          if currentTime - enemy.lastWallDamageTime >= 1.0:
            wall.takeDamage(1.0)
            trackWallDamaged(game)
            enemy.hp -= 1.0
            # Enforce minimum health of 0.01
            if enemy.hp < 0.01:
              enemy.hp = 0.01
            enemy.lastWallDamageTime = currentTime
          break
      if canMove:
        enemy.pos = enemy.pos + enemy.vel * dt

    of etStar:
      # Get config for this enemy type
      let config = getEnemyConfig(enemy.enemyType)
      let specialData = parseSpecialData(config.specialData)
      let dashRange = getSpecialFloat(specialData, "dash_range", 150.0)
      let dashMultiplier = config.movement.dashSpeed / config.movement.baseSpeed

      # Star dashes when close to player
      enemy.dashCooldown -= dt
      let distToPlayer = distance(enemy.pos, playerPos)
      if distToPlayer < dashRange and enemy.dashCooldown <= 0:
        let dir = (playerPos - enemy.pos).normalize()
        enemy.vel = dir * effectiveSpeed * dashMultiplier
        enemy.dashCooldown = config.movement.dashCooldown
      else:
        let dir = (playerPos - enemy.pos).normalize()
        discard applyEnemyInertia(enemy, dir * effectiveSpeed, dt)
      let nextPos = enemy.pos + enemy.vel * dt
      var canMove = true
      for wall in walls:
        if wallOverlapsCircle(wall, nextPos, enemy.radius):
          canMove = false
          if currentTime - enemy.lastWallDamageTime >= 1.0:
            wall.takeDamage(1.0)
            trackWallDamaged(game)
            # Stars use a hit-count system, not HP, wall collisions must not
            # bypass that mechanic by draining the placeholder baseHP.
            enemy.lastWallDamageTime = currentTime
          break
      if canMove:
        enemy.pos = nextPos

    of etHexagon:
      # Update timers
      enemy.hexTeleportTimer -= dt
      enemy.shootTimer += dt

      # Teleport behavior with pre-teleport warning
      let hexWarningTime = 0.8  # Show warning this many seconds before teleporting
      if enemy.hexTeleportTimer <= 0:
        # Execute the teleport to the pre-calculated destination
        enemy.pos.x = enemy.targetPos.x
        enemy.pos.y = enemy.targetPos.y
        enemy.vel = newVector2f(0, 0)
        enemy.hexTeleportTimer = 2.5 + rand(1.0)
        enemy.attackPhase = 0  # Reset: next cycle will show a fresh warning
      elif enemy.hexTeleportTimer <= hexWarningTime and enemy.attackPhase == 0:
        # Pre-calculate destination and show a warning there before teleporting
        let angle = rand(1.0) * PI * 2.0
        let teleportDist = 150.0 + rand(100.0)
        let margin = enemy.radius + 10.0
        let newX = clamp(playerPos.x + cos(angle) * teleportDist, margin, game.screenWidth.float32 - margin)
        let newY = clamp(playerPos.y + sin(angle) * teleportDist, margin, game.screenHeight.float32 - margin)
        enemy.targetPos = newVector2f(newX, newY)
        # Warn the player at the destination
        game.attackWarnings.add(newAttackWarning(newX, newY, awtHexTeleport, hexWarningTime))
        enemy.attackPhase = 1  # Warning shown; don't add it again this cycle
        var nextPos = chasePlayer(enemy, playerPos, dt, effectiveSpeed)
        nextPos = nextInertialEnemyPos(enemy, nextPos, dt)
        let hitWall = checkWallCollision(enemy, nextPos, walls, currentTime, game)
        if not hitWall:
          enemy.pos = nextPos
        else:
          discard applyEnemyInertia(enemy, newVector2f(0, 0), dt)
      else:
        # Chase player while waiting to teleport
        var nextPos = chasePlayer(enemy, playerPos, dt, effectiveSpeed)
        nextPos = nextInertialEnemyPos(enemy, nextPos, dt)
        let hitWall = checkWallCollision(enemy, nextPos, walls, currentTime, game)
        if not hitWall:
          enemy.pos = nextPos
        else:
          discard applyEnemyInertia(enemy, newVector2f(0, 0), dt)

      # Chaotic shooting (uses config for fire rate, bullet count, speed)
      executeRangedAttack(enemy, playerPos, game)

    of etCross:
      # Shows cross warning before attack, then dashes while rotating
      case enemy.attackPhase
      of 0:  # Patrol - slow movement
        let dir = (playerPos - enemy.pos).normalize()
        let nextPos = enemy.pos + applyEnemyInertia(enemy, dir * effectiveSpeed, dt) * dt
        var canMove = true
        for wall in walls:
          if wallOverlapsCircle(wall, nextPos, enemy.radius):
            canMove = false
            break
        if canMove:
          enemy.pos = nextPos
        else:
          discard applyEnemyInertia(enemy, newVector2f(0, 0), dt)

        enemy.attackWarningTimer += dt
        if enemy.attackWarningTimer >= 3.0:
          enemy.attackPhase = 1
          enemy.attackWarningTimer = 1.2  # Warning duration
          # Add warning to game
          game.attackWarnings.add(newAttackWarning(enemy.pos.x, enemy.pos.y, awtCross, 1.2))

      of 1:  # Warning phase - stop moving, prepare for dash
        enemy.attackWarningTimer -= dt
        discard applyEnemyInertia(enemy, newVector2f(0, 0), dt)
        if enemy.attackWarningTimer <= 0:
          enemy.attackPhase = 2
          enemy.attackExecuteTimer = 0.5  # Dash duration
          # Store dash direction toward player
          let dashDir = (playerPos - enemy.pos).normalize()
          enemy.vel = dashDir * effectiveSpeed * 4.0  # Fast dash (4x normal speed)

      of 2:  # Execute attack - DASH with rotation while firing laser
        enemy.attackExecuteTimer -= dt

        # Fire laser CONTINUOUSLY during dash, following the enemy position AND rotation
        # Laser follows the enemy during the entire dash
        game.lasers.add(newLaser(
          enemy.pos.x, enemy.pos.y,
          2,              # direction: 2 = cross (both horizontal and vertical)
          120.0,          # length: REDUCED from 200 to 120 (shorter lasers)
          20.0,           # thickness: width of laser beam
          1,              # damage
          dt,             # duration: just this frame, will be recreated next frame
          enemy.rotation, # rotation: pass the enemy's current rotation
          enemy.enemyType # enemyType: track which enemy type created this laser
        ))

        # Rotate during dash (clockwise at 12.5 radians per second)
        enemy.rotation += dt * 12.5

        # Dash movement with rotation
        if enemy.attackExecuteTimer > 0:
          # Continue dashing
          let nextPos = enemy.pos + enemy.vel * dt
          var canMove = true
          for wall in walls:
            if wallOverlapsCircle(wall, nextPos, enemy.radius):
              canMove = false
              # Bounce off walls during dash
              let wallDir = (enemy.pos - wall.pos).normalize()
              enemy.vel = wallDir * effectiveSpeed * 3.0
              break

          if canMove:
            enemy.pos = nextPos

          # Gradually slow down during dash
          enemy.vel = enemy.vel * pow(0.96, 60.0 * dt)
        else:
          # Dash finished, reset to patrol
          enemy.attackPhase = 0
          enemy.attackWarningTimer = 0
          enemy.attackExecuteTimer = 0
          enemy.vel = newVector2f(0, 0)
          enemy.rotation = 0.0  # Reset rotation
      else:
        discard

    of etDiamond:
      # Get config for this enemy type
      let config = getEnemyConfig(enemy.enemyType)
      let dashMultiplier = config.movement.dashSpeed / config.movement.baseSpeed

      # Dash and shoot behavior
      # dashCooldown = inter-dash cooldown (counts down to 0, then dash fires)
      # dashTimer    = active dash duration (counts down while actually dashing)
      enemy.dashCooldown -= dt
      enemy.shootTimer += dt

      if enemy.dashTimer > 0:
        # Currently dashing - maintain dash velocity for the full dash duration
        enemy.dashTimer -= dt
      elif enemy.dashCooldown <= 0:
        # Start a new dash toward player
        let dir = (playerPos - enemy.pos).normalize()
        enemy.vel = dir * effectiveSpeed * dashMultiplier
        enemy.dashTimer = config.movement.dashDuration  # Tracks remaining dash time
        enemy.dashCooldown = config.movement.dashCooldown + rand(1.0)

        # Brief directional dash warning so the player can react
        game.attackWarnings.add(newAttackWarning(enemy.pos.x, enemy.pos.y, awtTriangleDash, 0.18, enemy.id))

        # Shoot 3-spread at the start of each dash (uses config)
        executeRangedAttack(enemy, playerPos, game)
      else:
        # Normal movement between dashes
        let dir = (playerPos - enemy.pos).normalize()
        discard applyEnemyInertia(enemy, dir * effectiveSpeed * 0.7, dt)

      # Periodic random shooting only when not dashing
      if enemy.dashTimer <= 0 and enemy.shootTimer > config.attack.fireRate:
        let angle = rand(1.0) * PI * 2.0
        let tempDir = newVector2f(cos(angle), sin(angle))
        let tempPlayerPos = enemy.pos + tempDir * 100.0  # Fake target
        executeRangedAttack(enemy, tempPlayerPos, game)

      # Apply movement
      let nextPos = enemy.pos + enemy.vel * dt
      let hitWall = checkWallCollision(enemy, nextPos, walls, currentTime, game)
      if not hitWall:
        enemy.pos = nextPos

    of etOctagon:
      # Get config for this enemy type
      let config = getEnemyConfig(enemy.enemyType)

      # Update timers
      enemy.shootTimer += dt

      # Check screen entry
      checkScreenEntry(enemy, game)

      # Determine next position
      var nextPos: Vector2f
      if not enemy.hasEnteredScreen:
        # Force entry toward screen center
        nextPos = forceScreenEntry(enemy, playerPos, dt, effectiveSpeed, game)
      else:
        # Maintain optimal distance from player
        nextPos = maintainOptimalDistance(enemy, playerPos, dt, effectiveSpeed, config)
      nextPos = nextInertialEnemyPos(enemy, nextPos, dt)

      # Check collisions
      let hitWall = checkWallCollision(enemy, nextPos, walls, currentTime, game)
      let hitBoundary = checkScreenBoundaryCollision(enemy, nextPos, game, config)

      # Apply movement if no collisions
      if not hitWall and not hitBoundary:
        enemy.pos = nextPos
      else:
        discard applyEnemyInertia(enemy, newVector2f(0, 0), dt)

      # Rapid fire with inaccuracy (uses config values)
      executeRangedAttack(enemy, playerPos, game)

    of etPentagon:
      # Get config for this enemy type
      let config = getEnemyConfig(enemy.enemyType)

      # Update timers
      enemy.shootTimer += dt

      # Check screen entry
      checkScreenEntry(enemy, game)

      # Determine next position
      var nextPos: Vector2f
      if not enemy.hasEnteredScreen:
        # Force entry toward screen center
        nextPos = forceScreenEntry(enemy, playerPos, dt, effectiveSpeed, game)
      else:
        # Maintain optimal distance from player
        nextPos = maintainOptimalDistance(enemy, playerPos, dt, effectiveSpeed, config)
      nextPos = nextInertialEnemyPos(enemy, nextPos, dt)

      # Check collisions
      let hitWall = checkWallCollision(enemy, nextPos, walls, currentTime, game)
      let hitBoundary = checkScreenBoundaryCollision(enemy, nextPos, game, config)

      # Apply movement if no collisions
      if not hitWall and not hitBoundary:
        enemy.pos = nextPos
      else:
        discard applyEnemyInertia(enemy, newVector2f(0, 0), dt)

      # Powerful pentagon sniper shot (uses config values)
      executeRangedAttack(enemy, playerPos, game)

    of etTrickster:
      # Fake warning + teleport behavior, two phase:
      #   attackPhase 0: idle, counting down fakeWarningTimer
      #   attackPhase 1: warning is showing, counting down attackWarningTimer until TP
      let trickWarningDuration = 1.0

      if enemy.attackPhase == 0:
        enemy.fakeWarningTimer -= dt
        if enemy.fakeWarningTimer <= 0:
          let margin = enemy.radius + 10.0

          # Choose a FAKE position near the player for the visible warning
          let fakeAngle = rand(1.0) * PI * 2.0
          let fakeDist = 100.0 + rand(80.0)
          let fakeX = clamp(playerPos.x + cos(fakeAngle) * fakeDist, margin, game.screenWidth.float32 - margin)
          let fakeY = clamp(playerPos.y + sin(fakeAngle) * fakeDist, margin, game.screenHeight.float32 - margin)

          # Show fake warning - player expects the attack here
          game.attackWarnings.add(newAttackWarning(fakeX, fakeY, awtTricksterDecoy, trickWarningDuration))

          # Pre-calculate REAL destination (~90° away from the fake) and store it
          let realAngle = fakeAngle + PI * (0.5 + rand(1.0))
          let realDist = 120.0 + rand(80.0)
          enemy.targetPos = newVector2f(
            clamp(playerPos.x + cos(realAngle) * realDist, margin, game.screenWidth.float32 - margin),
            clamp(playerPos.y + sin(realAngle) * realDist, margin, game.screenHeight.float32 - margin)
          )

          # Subtle hint at the REAL destination, small and easy to miss
          game.attackWarnings.add(newAttackWarning(enemy.targetPos.x, enemy.targetPos.y, awtTricksterReal, trickWarningDuration))

          # Start waiting for the warning to expire before actually teleporting
          enemy.attackWarningTimer = trickWarningDuration
          enemy.attackPhase = 1

      elif enemy.attackPhase == 1:
        # Warning is showing, wait for it to expire, then teleport and shoot
        enemy.attackWarningTimer -= dt
        if enemy.attackWarningTimer <= 0:
          enemy.pos = enemy.targetPos
          enemy.vel = newVector2f(0, 0)
          # Shoot 6-way burst from the real position
          executeRangedAttack(enemy, playerPos, game)
          # Reset cycle
          enemy.fakeWarningTimer = 3.0 + rand(2.0)
          enemy.attackPhase = 0

      # Normal movement during both phases
      var nextPos = chasePlayer(enemy, playerPos, dt, effectiveSpeed * 0.6)
      nextPos = nextInertialEnemyPos(enemy, nextPos, dt)
      let hitWall = checkWallCollision(enemy, nextPos, walls, currentTime, game)
      if not hitWall:
        enemy.pos = nextPos
      else:
        discard applyEnemyInertia(enemy, newVector2f(0, 0), dt)

    of etPhantom:
      # Get config for this enemy type
      let config = getEnemyConfig(enemy.enemyType)

      # Three-phase state machine:
      #   phase 0: idle, cloneTimer counts down, then pre-calculate & warn
      #   phase 1: warning shown, attackWarningTimer counts down, then teleport
      #   phase 2: turret mode, clones fire sequentially until cloneTimer expires -> phase 0
      let phantomWarnDuration = 0.9
      let cloneShotInterval   = 0.45  # seconds between each sequential clone shot

      if enemy.attackPhase == 0:
        enemy.cloneTimer -= dt

        if enemy.cloneTimer <= 0:
          let margin = enemy.radius + 10.0

          # Pre-calculate real teleport destination
          let teleAngle = rand(1.0) * PI * 2.0
          let teleDist  = 140.0 + rand(90.0)
          enemy.targetPos = newVector2f(
            clamp(playerPos.x + cos(teleAngle) * teleDist, margin, game.screenWidth.float32 - margin),
            clamp(playerPos.y + sin(teleAngle) * teleDist, margin, game.screenHeight.float32 - margin)
          )

          # Pre-calculate 3 clone turret positions (evenly spread, randomised offset)
          let cloneBaseAngle = rand(1.0) * PI * 2.0
          enemy.clonePositions = @[]
          for i in 0..<3:
            let angle = cloneBaseAngle + i.float32 * PI * 2.0 / 3.0
            let dist  = 100.0 + rand(50.0)
            enemy.clonePositions.add(newVector2f(
              clamp(playerPos.x + cos(angle) * dist, margin, game.screenWidth.float32 - margin),
              clamp(playerPos.y + sin(angle) * dist, margin, game.screenHeight.float32 - margin)
            ))

          # Warn at the real teleport destination, portal marker
          game.attackWarnings.add(newAttackWarning(
            enemy.targetPos.x, enemy.targetPos.y, awtPhantomArrive, phantomWarnDuration))

          # Warn at every clone turret position, ghostly crosshair
          for clonePos in enemy.clonePositions:
            game.attackWarnings.add(newAttackWarning(
              clonePos.x, clonePos.y, awtPhantomClone, phantomWarnDuration))

          enemy.attackWarningTimer = phantomWarnDuration
          enemy.attackPhase = 1

      elif enemy.attackPhase == 1:
        # Warnings visible, wait, then teleport and enter turret mode
        enemy.attackWarningTimer -= dt
        if enemy.attackWarningTimer <= 0:
          enemy.pos = enemy.targetPos
          enemy.vel = newVector2f(0, 0)

          # Shoot once from the real landed position on arrival
          enemy.shootTimer = config.attack.fireRate + 1.0
          executeRangedAttack(enemy, playerPos, game)
          enemy.shootTimer = 0

          # Enter turret mode: hitCount = current clone index, burstTimer = shot delay
          enemy.hitCount  = 0
          enemy.burstTimer = 0.0  # fire clone 0 immediately on first tick
          enemy.cloneTimer = config.movement.teleportCooldown + rand(1.5)
          enemy.attackPhase = 2

      elif enemy.attackPhase == 2:
        # Sequential turret fire from clone positions
        enemy.burstTimer -= dt
        enemy.cloneTimer -= dt

        if enemy.burstTimer <= 0 and enemy.clonePositions.len > 0:
          let idx = enemy.hitCount mod enemy.clonePositions.len
          let clonePos    = enemy.clonePositions[idx]
          let originalPos = enemy.pos
          enemy.pos        = clonePos
          enemy.shootTimer = config.attack.fireRate + 1.0
          executeRangedAttack(enemy, playerPos, game)
          enemy.pos        = originalPos
          enemy.shootTimer = 0

          enemy.hitCount  += 1
          enemy.burstTimer = cloneShotInterval

        # When turret phase expires, go back to idle for next teleport cycle
        if enemy.cloneTimer <= 0:
          enemy.attackPhase = 0

      # Erratic wobbling movement during all phases
      let dir = (playerPos - enemy.pos).normalize()
      let wobble = sin(currentTime * 5.0) * 0.7
      let wobbleDir = newVector2f(
        dir.x * cos(wobble) - dir.y * sin(wobble),
        dir.x * sin(wobble) + dir.y * cos(wobble)
      )
      let nextPos = enemy.pos + applyEnemyInertia(enemy, wobbleDir * effectiveSpeed * 0.7, dt) * dt
      let hitWall = checkWallCollision(enemy, nextPos, walls, currentTime, game)
      if not hitWall:
        enemy.pos = nextPos
      else:
        discard applyEnemyInertia(enemy, newVector2f(0, 0), dt)

    of etSniper:
      # Sniper enemy - charges a powerful one-shot attack with warning
      let config = getEnemyConfig(enemy.enemyType)
      let specialData = parseSpecialData(config.specialData)
      let triggerRange = getSpecialFloat(specialData, "trigger_range", 500.0)  # Default matches config (was 300, increased to 500)
      let chargeTime = getSpecialFloat(specialData, "charge_time", 3.0)
      let cooldownTime = getSpecialFloat(specialData, "cooldown", 2.0)

      # Mark as entered screen once fully on-screen (required for executeRangedAttack)
      checkScreenEntry(enemy, game)

      let distToPlayer = distance(enemy.pos, playerPos)

      case enemy.attackPhase
      of 0:  # Hunting phase - moves toward player
        let dir = (playerPos - enemy.pos).normalize()
        let nextPos = enemy.pos + applyEnemyInertia(enemy, dir * effectiveSpeed * 0.8, dt) * dt
        var canMove = true
        for wall in walls:
          if wallOverlapsCircle(wall, nextPos, enemy.radius):
            canMove = false
            break
        if canMove:
          enemy.pos = nextPos
        else:
          discard applyEnemyInertia(enemy, newVector2f(0, 0), dt)

        # When close enough, start charging
        if distToPlayer < triggerRange:
          enemy.attackPhase = 1
          enemy.attackWarningTimer = 0
          enemy.attackExecuteTimer = chargeTime
          # Emit a reticle warning that lasts the full charge duration
          game.attackWarnings.add(newAttackWarning(enemy.pos.x, enemy.pos.y, awtSniperCharge, chargeTime, enemy.id))

      of 1:  # Charging phase - stands still, glows brighter
        enemy.attackWarningTimer += dt
        discard applyEnemyInertia(enemy, newVector2f(0, 0), dt)
        # Visual charging: change color intensity
        let chargeAmount = enemy.attackWarningTimer / enemy.attackExecuteTimer
        let intensity = uint8(150 + chargeAmount * 105)
        enemy.color = Color(r: intensity, g: 0, b: 0, a: 255)

        # When charge completes, fire using centralized system
        if enemy.attackWarningTimer >= enemy.attackExecuteTimer:
          executeRangedAttack(enemy, playerPos, game)
          enemy.attackPhase = 2
          enemy.attackExecuteTimer = cooldownTime
          enemy.color = Color(r: 220, g: 0, b: 0, a: 255)  # Reset color

      of 2:  # Cooldown phase - recover before hunting again
        enemy.attackExecuteTimer -= dt
        discard applyEnemyInertia(enemy, newVector2f(0, 0), dt)
        if enemy.attackExecuteTimer <= 0:
          enemy.attackPhase = 0
      else:
        discard

    of etEnvironment:
      discard  # Static non-combat entity, no movement logic

    of etMage:
      # Magical enemy: homing bullets + meteorite summoning
      let config = getEnemyConfig(enemy.enemyType)

      # Check screen entry
      checkScreenEntry(enemy, game)

      # Update timers
      enemy.shootTimer += dt  # For homing bullets
      enemy.spawnTimer += dt  # For meteorites

      # Shoot homing magic bullets using centralized system
      executeRangedAttack(enemy, playerPos, game)

      # Summon meteorites periodically using config values
      if enemy.spawnTimer > config.specialCooldown:
        let specialData = parseSpecialData(config.specialData)
        let baseCount = getSpecialInt(specialData, "meteorite_count", 2)
        let randomExtra = getSpecialInt(specialData, "meteorite_count_random", 1)
        var damage = getSpecialInt(specialData, "damage", 3)
        # Dungeon stat tuning also compresses special-attack damage
        if enemy.damageTuning > 0.0'f32 and enemy.damageTuning < 1.0'f32:
          damage = max(1, int(round(damage.float32 * enemy.damageTuning)))
        let warningTime = getSpecialFloat(specialData, "warning_time", 1.5)

        # Meteorite count from config
        let meteorCount = baseCount + (if randomExtra > 0: rand(randomExtra) else: 0)
        for i in 0..<meteorCount:
          # Target position near player (random offset)
          let offsetX = (rand(200.0) - 100.0)
          let offsetY = (rand(200.0) - 100.0)
          let targetX = playerPos.x + offsetX
          let targetY = playerPos.y + offsetY

          # Spawn position above screen
          let spawnX = targetX
          let spawnY = -50.0

          # Create meteorite with config damage and warning time
          let meteorite = newMeteorite(
            targetX = targetX,
            targetY = targetY,
            spawnX = spawnX,
            spawnY = spawnY,
            damage = damage,
            warningTime = warningTime
          )
          game.meteorites.add(meteorite)

        enemy.spawnTimer = 0

      # Movement: use helper functions for consistent behavior
      var nextPos: Vector2f
      if not enemy.hasEnteredScreen:
        nextPos = forceScreenEntry(enemy, playerPos, dt, effectiveSpeed, game)
      else:
        nextPos = maintainOptimalDistance(enemy, playerPos, dt, effectiveSpeed, config)
      nextPos = nextInertialEnemyPos(enemy, nextPos, dt)

      # Check wall collisions
      var canMove = true
      for wall in walls:
        if wallOverlapsCircle(wall, nextPos, enemy.radius):
          canMove = false
          if currentTime - enemy.lastWallDamageTime >= 1.0:
            wall.takeDamage(1.0)
            trackWallDamaged(game)
            enemy.hp -= 1.0
            # Enforce minimum health of 0.01
            if enemy.hp < 0.01:
              enemy.hp = 0.01
            enemy.lastWallDamageTime = currentTime
          break

      # Screen boundary check - keep ranged enemies inside once entered
      # Allow movement toward screen when off-screen, prevent leaving when inside
      if enemy.hasEnteredScreen:
        let isOffScreen = nextPos.x < enemy.radius or nextPos.x > game.screenWidth.float32 - enemy.radius or
                         nextPos.y < enemy.radius or nextPos.y > game.screenHeight.float32 - enemy.radius

        if isOffScreen:
          # Calculate direction toward screen center
          let screenCenterX = game.screenWidth.float32 / 2.0
          let screenCenterY = game.screenHeight.float32 / 2.0
          let towardCenter = (newVector2f(screenCenterX, screenCenterY) - enemy.pos).normalize()
          let movementDir = (nextPos - enemy.pos).normalize()

          # Calculate dot product to see if movement is toward center
          let dotProduct = towardCenter.x * movementDir.x + towardCenter.y * movementDir.y

          # Only block movement if it's moving away from center (dot < 0)
          # Allow movement if it's toward center (dot >= 0)
          if dotProduct < 0:
            canMove = false

      if canMove:
        enemy.pos = nextPos
      else:
        discard applyEnemyInertia(enemy, newVector2f(0, 0), dt)

  # Update chain lightning cooldown
  if enemy.chainLightningCooldown > 0:
    enemy.chainLightningCooldown -= dt

  # Update slow timer (from Chain Lightning stun and other effects)
  if enemy.slowTimer > 0:
    enemy.slowTimer -= dt
    if enemy.slowTimer <= 0:
      enemy.slowAmount = 0

  # Check if star is defeated by hit count
  if enemy.enemyType == etStar and enemy.hitCount >= enemy.requiredHits:
    return false

  # Enemies with exactly 0.01 HP are still alive (minimum health)
  # They die when hit again (hp becomes <= 0)
  return enemy.hp >= 0.01

proc drawCustomBoss*(enemy: Enemy) =
  ## Redesigned boss visuals
  let time    = getTime()
  let pulse   = sin(time * 2.5) * 0.5 + 0.5    # fast pulse  0..1
  let blink   = sin(time * 4.0) * 0.5 + 0.5    # very fast   0..1
  let breathe = sin(time * 1.0) * 0.5 + 0.5    # slow breath 0..1
  let hpPct   = clamp(enemy.hp / enemy.maxHp, 0.0, 1.0)
  let cx = enemy.pos.x
  let cy = enemy.pos.y
  let r  = enemy.radius
  # How far the boss has ascended through its phases. The per-boss "ascension"
  # overlay at the end of this proc uses it to make the boss look progressively
  # more powerful (extra crowns, satellites, rings, …) each phase. 0 = base form.
  let phaseLvl = max(0, enemy.currentPhaseIndex)
  let pf = phaseLvl.float32

  proc poly(sides: int, radius, baseAngle, thick: float32, col: Color) =
    for i in 0 ..< sides:
      let a0 = baseAngle + i.float32       * (PI * 2.0 / sides.float32)
      let a1 = baseAngle + (i+1).float32   * (PI * 2.0 / sides.float32)
      drawLine(Vector2(x: cx + cos(a0)*radius, y: cy + sin(a0)*radius),
               Vector2(x: cx + cos(a1)*radius, y: cy + sin(a1)*radius),
               thick, col)

  proc spoke(count: int, inner, outer, baseAngle, thick: float32, col: Color) =
    for i in 0 ..< count:
      let a = baseAngle + i.float32 * (PI * 2.0 / count.float32)
      drawLine(Vector2(x: cx + cos(a)*inner, y: cy + sin(a)*inner),
               Vector2(x: cx + cos(a)*outer, y: cy + sin(a)*outer), thick, col)

  proc glow(radius: float32, col: Color) =
    drawCircle(Vector2(x: cx, y: cy), radius, col)

  proc hueCol(h: float32, alpha: uint8): Color =
    Color(r: uint8(clamp(abs(sin(h*PI*2.0))*255.0, 0.0'f32, 255.0'f32)),
          g: uint8(clamp(abs(sin((h+0.33)*PI*2.0))*255.0, 0.0'f32, 255.0'f32)),
          b: uint8(clamp(abs(sin((h+0.66)*PI*2.0))*255.0, 0.0'f32, 255.0'f32)), a: alpha)

  case enemy.bossDefinitionID

  of 1:  # THE SPIRAL GUARDIAN
    glow(r + 22 + breathe*6, Color(r: 80, g: 20, b: 160, a: 35))
    glow(r + 14 + pulse*4,   Color(r: 120, g: 40, b: 220, a: 55))
    poly(18, r + 10, time * 0.8,   2, Color(r: 140, g: 60, b: 255, a: 140))
    poly(12, r + 4,  -time * 1.2,  2, Color(r: 180, g: 100, b: 255, a: 100))
    poly(6,  r - 6,  time * 2.0,   3, Color(r: 220, g: 140, b: 255, a: 180))
    for i in 0 ..< 8:
      let armAngle = time * 1.5 + i.float32 * PI / 4.0
      for step in 0 ..< 6:
        let t  = step.float32 / 5.0
        let t2 = (step+1).float32 / 5.0
        let dist1 = r * 0.15 + t  * r * 0.7
        let dist2 = r * 0.15 + t2 * r * 0.7
        let a1 = armAngle + t  * 0.6
        let a2 = armAngle + t2 * 0.6
        let alpha = uint8((1.0 - t) * 200)
        drawLine(Vector2(x: cx+cos(a1)*dist1, y: cy+sin(a1)*dist1),
                 Vector2(x: cx+cos(a2)*dist2, y: cy+sin(a2)*dist2),
                 2, Color(r: 200, g: 130, b: 255, a: alpha))
    glow(r * 0.72, enemy.color)
    poly(9, r * 0.72, time*0.4, 3, Color(r: 180, g: 100, b: 255, a: 255))
    let eyeH = r * (0.35 + breathe*0.08)
    let eyeW = r * 0.14
    drawLine(Vector2(x: cx, y: cy-eyeH), Vector2(x: cx+eyeW, y: cy), 2, White)
    drawLine(Vector2(x: cx+eyeW, y: cy), Vector2(x: cx, y: cy+eyeH), 2, White)
    drawLine(Vector2(x: cx, y: cy+eyeH), Vector2(x: cx-eyeW, y: cy), 2, White)
    drawLine(Vector2(x: cx-eyeW, y: cy), Vector2(x: cx, y: cy-eyeH), 2, White)
    glow(r * 0.18 + pulse*3, Color(r: 255, g: 220, b: 255, a: 255))
    glow(r * 0.08, Color(r: 255, g: 255, b: 255, a: 255))

  of 2:  # THE SUMMONER KING
    glow(r + 20 + breathe*5, Color(r: 20, g: 100, b: 20, a: 40))
    glow(r + 12 + pulse*3,   Color(r: 40, g: 180, b: 40, a: 60))
    for i in 0 ..< 8:
      let a = time * 0.6 + i.float32 * PI / 4.0
      drawCircle(Vector2(x: cx + cos(a)*(r+6), y: cy + sin(a)*(r+6)), 5,
                 Color(r: 100, g: 255, b: 80, a: 180))
    for i in 0 ..< 6:
      let a = -time * 0.9 + i.float32 * PI / 3.0
      drawCircle(Vector2(x: cx + cos(a)*(r-8), y: cy + sin(a)*(r-8)), 3,
                 Color(r: 60, g: 200, b: 255, a: 150))
    poly(12, r * 0.88, 0.0, 3, Color(r: 60, g: 200, b: 60, a: 220))
    for i in 0 ..< 5:
      let baseA   = -PI*0.5 - 0.45 + i.float32 * 0.22
      let spikeLen = r * (if i == 2: 0.70 else: 0.50)
      let bx = cx + cos(baseA) * r * 0.88
      let by = cy + sin(baseA) * r * 0.88
      let tx = cx + cos(baseA) * (r * 0.88 + spikeLen)
      let ty = cy + sin(baseA) * (r * 0.88 + spikeLen)
      drawLine(Vector2(x: bx, y: by), Vector2(x: tx, y: ty), 4,
               Color(r: 255, g: 215, b: 0, a: 230))
      drawCircle(Vector2(x: tx, y: ty), 5, Color(r: 255, g: 240, b: 80, a: 255))
    glow(r * 0.75, enemy.color)
    poly(3, r*0.45, time*0.7,  3, Color(r: 255, g: 215, b: 0, a: 200))
    poly(3, r*0.30, -time*1.1, 2, Color(r: 180, g: 255, b: 100, a: 180))
    glow(r * 0.16 + breathe*3, Color(r: 200, g: 255, b: 100, a: 255))
    glow(r * 0.07, Color(r: 255, g: 255, b: 200, a: 255))

  of 3:  # THE METEOR STRIKER
    let fireRage = 1.0 + (1.0 - hpPct) * 0.8
    glow(r + 28*fireRage + pulse*8, Color(r: 255, g: 60,  b: 0, a: uint8(50*fireRage)))
    glow(r + 16*fireRage + blink*4, Color(r: 255, g: 120, b: 0, a: uint8(80*fireRage)))
    for i in 0 ..< 12:
      let a     = i.float32 * PI / 6.0 + time * 0.3
      let inner = r * 0.88
      let outer = r * (1.0 + (if i mod 2 == 0: 0.55 else: 0.30)*fireRage) +
                  sin(time*4.0 + i.float32) * 4.0
      drawLine(Vector2(x: cx+cos(a)*inner, y: cy+sin(a)*inner),
               Vector2(x: cx+cos(a)*outer, y: cy+sin(a)*outer),
               (if i mod 2 == 0: 5.0 else: 3.0),
               Color(r: 255, g: uint8(80+i*10), b: 0, a: 220))
    for i in 0 ..< 14:
      let a0 = i.float32     * (PI*2.0/14.0)
      let a1 = (i+1).float32 * (PI*2.0/14.0)
      let r0 = r * (if i mod 2 == 0: 1.0 else: 0.78)
      let r1 = r * (if (i+1) mod 2 == 0: 1.0 else: 0.78)
      drawLine(Vector2(x: cx+cos(a0)*r0, y: cy+sin(a0)*r0),
               Vector2(x: cx+cos(a1)*r1, y: cy+sin(a1)*r1), 4, enemy.color)
    glow(r * 0.76, Color(r: 140, g: 60, b: 20, a: 255))
    let crackAlpha = uint8(80 + (1.0 - hpPct) * 175)
    for i in 0 ..< 6:
      let crackA = i.float32 * PI / 3.0 + 0.3
      let tip    = r * (0.55 + i.float32*0.04)
      let mid    = r * 0.38
      drawLine(Vector2(x: cx, y: cy),
               Vector2(x: cx+cos(crackA)*tip, y: cy+sin(crackA)*tip),
               2, Color(r: 255, g: 150, b: 0, a: crackAlpha))
      let brA = crackA + 0.35
      drawLine(Vector2(x: cx+cos(crackA)*mid, y: cy+sin(crackA)*mid),
               Vector2(x: cx+cos(brA)*tip*0.7, y: cy+sin(brA)*tip*0.7),
               1, Color(r: 255, g: 200, b: 0, a: crackAlpha))
    glow(r*0.22 + pulse*5, Color(r: 255, g: 240, b: 80, a: 255))
    glow(r*0.10, Color(r: 255, g: 255, b: 255, a: 255))

  of 4:  # Boss 4: The Laser Architect (Cyan geometric)
    # Geometric grid lines
    let gridSize = enemy.radius * 0.3
    for i in -2..2:
      let xOffset = i.float32 * gridSize
      drawLine(Vector2(x: enemy.pos.x + xOffset, y: enemy.pos.y - enemy.radius),
              Vector2(x: enemy.pos.x + xOffset, y: enemy.pos.y + enemy.radius),
              1, Color(r: 0, g: 150, b: 200, a: 100))
      drawLine(Vector2(x: enemy.pos.x - enemy.radius, y: enemy.pos.y + xOffset),
              Vector2(x: enemy.pos.x + enemy.radius, y: enemy.pos.y + xOffset),
              1, Color(r: 0, g: 150, b: 200, a: 100))

    # Main hexagonal body
    let hexPoints = 6
    for i in 0..<hexPoints:
      let angle = i.float32 * PI / 3.0 + time * 0.5
      let nextAngle = (i + 1).float32 * PI / 3.0 + time * 0.5
      let x1 = enemy.pos.x + cos(angle) * enemy.radius
      let y1 = enemy.pos.y + sin(angle) * enemy.radius
      let x2 = enemy.pos.x + cos(nextAngle) * enemy.radius
      let y2 = enemy.pos.y + sin(nextAngle) * enemy.radius
      drawLine(Vector2(x: x1, y: y1), Vector2(x: x2, y: y2), 4, enemy.color)

    # Central projection point
    drawCircle(Vector2(x: enemy.pos.x, y: enemy.pos.y), enemy.radius * 0.2,
               Color(r: 100, g: 255, b: 255, a: 255))

  of 5:  # THE VOID DANCER
    glow(r + 30 + breathe*8, Color(r: 10, g: 0, b: 20, a: 120))
    glow(r + 18, Color(r: 40, g: 0, b: 60, a: 90))
    for i in 1 ..< 5:
      let ringR = r * (0.35 + i.float32*0.22)
      drawCircleLines(cx.int32, cy.int32, ringR,
                      Color(r: uint8(60+i*20), g: 0, b: uint8(90+i*25), a: uint8(100-i*15)))
    for i in 0 ..< 8:
      let a    = time * (if i mod 2 == 0: 1.3 else: -0.9) + i.float32 * PI / 4.0
      let dist = r + 14 + sin(time*3.0 + i.float32)*5
      let sx = cx + cos(a)*dist
      let sy = cy + sin(a)*dist
      let sA = a
      let sLen = 10.0 + pulse*4
      drawLine(Vector2(x: sx+cos(sA)*sLen, y: sy+sin(sA)*sLen),
               Vector2(x: sx+cos(sA+0.4)*5, y: sy+sin(sA+0.4)*5), 2,
               Color(r: 180, g: 40, b: 255, a: 200))
      drawLine(Vector2(x: sx+cos(sA)*sLen, y: sy+sin(sA)*sLen),
               Vector2(x: sx+cos(sA-0.4)*5, y: sy+sin(sA-0.4)*5), 2,
               Color(r: 180, g: 40, b: 255, a: 200))
    for i in 1 ..< 5:
      let tx = cx - enemy.vel.x * i.float32 * 0.025
      let ty = cy - enemy.vel.y * i.float32 * 0.025
      drawCircle(Vector2(x: tx, y: ty), r*0.70,
                 Color(r: 80, g: 0, b: 120, a: uint8(100-i*20)))
    glow(r*0.78, enemy.color)
    poly(5, r*0.48, -time*1.5, 2, Color(r: 200, g: 80, b: 255, a: 200))
    spoke(5, 0.0, r*0.48, -time*1.5, 1, Color(r: 160, g: 40, b: 220, a: 150))
    glow(r*0.22, Color(r: 0, g: 0, b: 0, a: 255))
    drawCircleLines(cx.int32, cy.int32, r*0.22,
                    Color(r: 220, g: 80, b: 255, a: uint8(200*blink)))
    glow(r*0.08, Color(r: 255, g: 180, b: 255, a: 255))

  of 6:  # THE CHAIN REACTOR
    # Electric-storm helpers (immediate-mode jagged arcs, no RNG state)
    # Voltage rises as the Reactor loses HP: arcs get longer and more violent.
    let volt   = 1.0'f32 + (1.0'f32 - hpPct) * 1.4'f32
    # Quantize time so arcs "snap" to a fresh jagged shape ~22x/sec -> crackle.
    let flick  = floor(time * 22.0)
    let epulse = sin(time * 9.0) * 0.5 + 0.5
    proc nz(x: float32): float32 =
      ## Deterministic hash in -1..1 (fract-of-sin); cosmetic flicker only.
      let s = sin(x * 127.1'f32 + 311.7'f32) * 43758.5453'f32
      (s - floor(s)) * 2.0'f32 - 1.0'f32
    proc bolt(ax, ay, bx, by, amp, seed: float32, core, halo: Color) =
      ## Jagged lightning arc (ax,ay)->(bx,by), regenerated fresh each frame.
      let dx = bx - ax
      let dy = by - ay
      let ln = sqrt(dx * dx + dy * dy)
      if ln < 1.0'f32: return
      let nx = -dy / ln
      let ny =  dx / ln
      const N = 8
      var px = ax
      var py = ay
      for i in 1 .. N:
        let t   = i.float32 / N.float32
        let env = 1.0'f32 - abs(t * 2.0'f32 - 1.0'f32)   # taper toward endpoints
        let off = (if i == N: 0.0'f32 else: nz(seed + i.float32 * 7.13'f32) * amp * env)
        let qx  = ax + dx * t + nx * off
        let qy  = ay + dy * t + ny * off
        drawLine(Vector2(x: px, y: py), Vector2(x: qx, y: qy), 4.0, halo)  # soft glow
        drawLine(Vector2(x: px, y: py), Vector2(x: qx, y: qy), 1.6, core)  # bright core
        px = qx; py = qy
    let arcCore = Color(r: 255, g: 255, b: 215, a: 255)
    let arcHalo = Color(r: 120, g: 200, b: 255, a: 70)

    glow(r + 24 + blink*8,  Color(r: 255, g: 255, b: 80,  a: uint8(60*blink)))
    glow(r + 14 + pulse*5,  Color(r: 255, g: 220, b: 0,   a: 80))
    # Ambient corona tendrils crackling around the body (slow rotation). Kept
    # deliberately short and DIM so they read as an electric aura, not as an
    # aimed attack - the bright full-length bolts are reserved for bapChain.
    let tendCore = Color(r: 255, g: 240, b: 150, a: 150)
    let tendHalo = Color(r: 120, g: 200, b: 255, a: 45)
    for i in 0 ..< 3:
      let baseA = time * 0.7 + i.float32 * (TAU / 3.0)
      let reach = r * (1.25'f32 + 0.45'f32 * volt) + nz(flick + i.float32) * 12.0'f32
      let ex = cx + cos(baseA) * reach
      let ey = cy + sin(baseA) * reach
      bolt(cx, cy, ex, ey, r * 0.30'f32, flick * 3.0 + i.float32 * 17.0, tendCore, tendHalo)
      drawCircle(Vector2(x: ex, y: ey), 2.0'f32 + epulse * 1.2'f32,
                 Color(r: 255, g: 255, b: 180, a: 150))
    for i in 0 ..< 6:
      let a      = i.float32 * PI / 3.0 + time*0.2
      let inner  = r * 0.20
      let outer  = r * 1.08
      let midA   = r * 0.55
      let aLeft  = a - 0.18
      let aRight = a + 0.18
      drawLine(Vector2(x: cx+cos(a)*inner,    y: cy+sin(a)*inner),
               Vector2(x: cx+cos(aLeft)*midA,  y: cy+sin(aLeft)*midA),
               3, Color(r: 255, g: 255, b: 120, a: 220))
      drawLine(Vector2(x: cx+cos(aLeft)*midA,  y: cy+sin(aLeft)*midA),
               Vector2(x: cx+cos(aRight)*midA, y: cy+sin(aRight)*midA),
               3, Color(r: 255, g: 255, b: 120, a: 220))
      drawLine(Vector2(x: cx+cos(aRight)*midA, y: cy+sin(aRight)*midA),
               Vector2(x: cx+cos(a)*outer,     y: cy+sin(a)*outer),
               3, Color(r: 255, g: 240, b: 50, a: 255))
    poly(24, r + 8, time*2.0, 2, Color(r: 255, g: 255, b: 100, a: 140))
    glow(r*0.68, enemy.color)
    drawCircleLines(cx.int32, cy.int32, r*0.40,
                    Color(r: 255, g: 255, b: 200, a: 180))
    poly(16, r*0.40, time*3.0, 2, Color(r: 255, g: 255, b: 255, a: 120))
    for i in 0 ..< 10:
      let a        = time*8.0 + i.float32 * 0.628
      let startR   = r*0.42
      let endR     = r*0.70 + sin(time*6.0+i.float32)*12
      let sparkAlpha = uint8((sin(time*12.0 + i.float32*0.9)*0.5 + 0.5)*200)
      drawLine(Vector2(x: cx+cos(a)*startR, y: cy+sin(a)*startR),
               Vector2(x: cx+cos(a)*endR,   y: cy+sin(a)*endR),
               1, Color(r: 255, g: 255, b: 255, a: sparkAlpha))
    glow(r*0.20 + blink*5, Color(r: 255, g: 255, b: 255, a: 255))
    glow(r*0.09, Color(r: 200, g: 255, b: 255, a: 255))
    # Internal core crackle: short bright arcs from the core out to the shell.
    for i in 0 ..< 5:
      let a = time * 1.3 + i.float32 * (TAU / 5.0)
      bolt(cx + cos(a) * r * 0.18'f32, cy + sin(a) * r * 0.18'f32,
           cx + cos(a) * r * 0.90'f32, cy + sin(a) * r * 0.90'f32,
           r * 0.16'f32, flick * 5.0 + i.float32 * 9.0, arcCore, arcHalo)
    # Discharge arcs: the Reactor visibly charges its coil weak-points, tying the
    # "tap the coils in sequence" mechanic to the electric theme. Active (next)
    # coils get a fat bright arc; dormant ones a thin one.
    for tgt in enemy.weakPoint.targets:
      if tgt.hit: continue
      let amp   = if tgt.active: 18.0'f32 else: 8.0'f32
      let aCore = if tgt.active: arcCore else: Color(r: 200, g: 220, b: 255, a: 120)
      bolt(cx, cy, tgt.pos.x, tgt.pos.y, amp,
           flick * 2.0 + tgt.index.float32 * 23.0, aCore, arcHalo)

  of 7:  # THE ORBITAL COMMANDER
    glow(r + 22 + breathe*6, Color(r: 20, g: 10, b: 60, a: 50))
    poly(60, r + 24,  time*0.15,  2, Color(r: 150, g: 120, b: 255, a: 100))
    poly(60, r + 16, -time*0.25,  2, Color(r: 120, g: 90,  b: 220, a: 120))
    poly(60, r + 8,   time*0.40,  2, Color(r: 180, g: 140, b: 255, a: 140))
    for i in 0 ..< 3:
      let satR   = r + 26 + i.float32 * 14
      let satSpd = 1.5 - i.float32*0.4
      let satA   = time * satSpd + i.float32 * (PI*2.0/3.0)
      let sx = cx + cos(satA)*satR
      let sy = cy + sin(satA)*satR
      let satCol = Color(r: uint8(180+i*25), g: uint8(140+i*20), b: 255, a: 255)
      drawCircle(Vector2(x: sx, y: sy), 6, satCol)
      drawCircleLines(sx.int32, sy.int32, 8, Color(r: 255, g: 255, b: 255, a: 120))
      let panA = satA + PI/2.0
      drawLine(Vector2(x: sx+cos(panA)*8, y: sy+sin(panA)*8),
               Vector2(x: sx-cos(panA)*8, y: sy-sin(panA)*8), 3, satCol)
    poly(8, r*0.95, PI/8.0, 4, Color(r: 160, g: 120, b: 255, a: 220))
    poly(8, r*0.78, PI/8.0 + time*0.2, 2, Color(r: 200, g: 160, b: 255, a: 180))
    glow(r*0.70, enemy.color)
    spoke(8, 0.0, r*0.58, time*0.3, 1, Color(r: 200, g: 170, b: 255, a: 100))
    drawCircleLines(cx.int32, cy.int32, r*0.35,
                    Color(r: 200, g: 170, b: 255, a: 150))
    glow(r*0.18 + pulse*8, Color(r: 255, g: 240, b: 255, a: uint8(200*pulse)))
    glow(r*0.10, Color(r: 255, g: 255, b: 255, a: 255))

  of 8:  # THE BERSERKER JUGGERNAUT
    let rage  = 1.0 - hpPct
    let rageF = 1.0 + rage * 1.2
    glow(r + 20*rageF + pulse*8*rageF, Color(r: 255, g: 0, b: 0, a: uint8(80*rage+20)))
    glow(r + 10*rageF, Color(r: 200, g: 0, b: 0, a: uint8(60*rage+10)))
    for i in 0 ..< 10:
      let a        = i.float32 * PI / 5.0 + time * 0.15
      let spikeLen = r * (0.35 + (if i mod 2 == 0: 0.55 else: 0.30)*rageF)
      let inner    = r * 0.82
      let bx = cx + cos(a)*inner
      let by = cy + sin(a)*inner
      let tx = cx + cos(a)*(inner+spikeLen)
      let ty = cy + sin(a)*(inner+spikeLen)
      let spikeAlpha = uint8(160 + rage*95)
      drawLine(Vector2(x: bx, y: by), Vector2(x: tx, y: ty), 5,
               Color(r: 200, g: 0, b: 0, a: spikeAlpha))
      drawLine(Vector2(x: bx, y: by),
               Vector2(x: cx+cos(a+0.20)*inner, y: cy+sin(a+0.20)*inner),
               3, Color(r: 160, g: 0, b: 0, a: spikeAlpha))
      drawLine(Vector2(x: bx, y: by),
               Vector2(x: cx+cos(a-0.20)*inner, y: cy+sin(a-0.20)*inner),
               3, Color(r: 160, g: 0, b: 0, a: spikeAlpha))
    glow(r*0.82, enemy.color)
    let scarAlpha = uint8(60 + rage*195)
    for i in 0 ..< 7:
      let scarA = i.float32 * PI / 3.5 + 0.25
      let tip   = r*(0.50 + i.float32*0.03)
      drawLine(Vector2(x: cx, y: cy),
               Vector2(x: cx+cos(scarA)*tip, y: cy+sin(scarA)*tip),
               2, Color(r: 255, g: uint8(rage*180), b: 0, a: scarAlpha))
    poly(10, r*0.55, -time*0.8, 2,
         Color(r: uint8(150+rage*105), g: 0, b: 0, a: uint8(120+rage*135)))
    let coreR = uint8(200 + rage*55)
    let coreG = uint8(rage*80)
    glow(r*0.22 + pulse*4*rageF, Color(r: coreR, g: coreG, b: 0, a: 255))
    glow(r*0.09, Color(r: 255, g: 255, b: 255, a: 255))

  of 9:  # Boss 9: The Prism Architect (Rainbow/prismatic)
    # Rainbow refraction rings
    let colors = [
      Color(r: 255, g: 0, b: 0, a: 100),    # Red
      Color(r: 255, g: 127, b: 0, a: 100),  # Orange
      Color(r: 255, g: 255, b: 0, a: 100),  # Yellow
      Color(r: 0, g: 255, b: 0, a: 100),    # Green
      Color(r: 0, g: 0, b: 255, a: 100),    # Blue
      Color(r: 139, g: 0, b: 255, a: 100)   # Purple
    ]

    for i in 0..<6:
      let ringRadius = enemy.radius + i.float32 * 4 + sin(time * 3.0 + i.float32) * 2
      drawCircleLines(enemy.pos.x.int32, enemy.pos.y.int32, ringRadius, colors[i])

    # Prismatic core - hexagon
    let hexPoints = 6
    for i in 0..<hexPoints:
      let angle = i.float32 * PI / 3.0 + time
      let nextAngle = (i + 1).float32 * PI / 3.0 + time
      let x1 = enemy.pos.x + cos(angle) * enemy.radius * 0.8
      let y1 = enemy.pos.y + sin(angle) * enemy.radius * 0.8
      let x2 = enemy.pos.x + cos(nextAngle) * enemy.radius * 0.8
      let y2 = enemy.pos.y + sin(nextAngle) * enemy.radius * 0.8
      drawLine(Vector2(x: x1, y: y1), Vector2(x: x2, y: y2), 4, enemy.color)

    # Bright light center
    drawCircle(Vector2(x: enemy.pos.x, y: enemy.pos.y), enemy.radius * 0.3,
               Color(r: 255, g: 255, b: 255, a: 255))

  of 10:  # THE TIMEKEEPER
    for i in 0 ..< 5:
      let rippleR = r*(0.30 + i.float32*0.22) + sin(time*2.0 - i.float32*0.6)*4
      let rippleA = uint8(max(0.0, sin(time*2.0 - i.float32*0.6)*100 + 60))
      drawCircleLines(cx.int32, cy.int32, rippleR,
                      Color(r: 0, g: 200, b: 200, a: rippleA))
    for i in 0 ..< 12:
      let a          = i.float32 * PI / 6.0
      let toothOuter = r * (if i mod 3 == 0: 1.10 else: 1.02)
      let toothInner = r * 0.92
      drawLine(Vector2(x: cx+cos(a)*toothInner, y: cy+sin(a)*toothInner),
               Vector2(x: cx+cos(a)*toothOuter, y: cy+sin(a)*toothOuter),
               (if i mod 3 == 0: 4.0 else: 2.0),
               Color(r: 0, g: 220, b: 220, a: 220))
    glow(r*0.88, enemy.color)
    drawCircleLines(cx.int32, cy.int32, r*0.88,
                    Color(r: 0, g: 240, b: 240, a: 220))
    for i in 0 ..< 12:
      let a     = i.float32 * PI / 6.0 - PI/2.0
      let inner = r * (if i mod 3 == 0: 0.60 else: 0.72)
      drawLine(Vector2(x: cx+cos(a)*inner,    y: cy+sin(a)*inner),
               Vector2(x: cx+cos(a)*(r*0.84), y: cy+sin(a)*(r*0.84)),
               (if i mod 3 == 0: 3.0 else: 1.5),
               Color(r: 0, g: 255, b: 255, a: 200))
    let minuteA = time * 1.0 - PI/2.0
    drawLine(Vector2(x: cx, y: cy),
             Vector2(x: cx+cos(minuteA)*r*0.70, y: cy+sin(minuteA)*r*0.70),
             2, Color(r: 200, g: 255, b: 255, a: 255))
    let hourA = time * 0.083 - PI/2.0
    drawLine(Vector2(x: cx, y: cy),
             Vector2(x: cx+cos(hourA)*r*0.48, y: cy+sin(hourA)*r*0.48),
             4, Color(r: 100, g: 255, b: 255, a: 255))
    let sweepA = time * 6.28 - PI/2.0
    drawLine(Vector2(x: cx, y: cy),
             Vector2(x: cx+cos(sweepA)*r*0.78, y: cy+sin(sweepA)*r*0.78),
             1, Color(r: 255, g: 80, b: 80, a: 220))
    glow(r*0.08 + pulse*2, Color(r: 0, g: 255, b: 255, a: 255))
    glow(r*0.04, Color(r: 255, g: 255, b: 255, a: 255))

  of 11:  # Boss 11: The Chaos Weaver (Purple chaos theme)
    # Chaotic energy bolts
    let chaosCount = 12
    for i in 0..<chaosCount:
      let angle = (i.float32 + sin(time * 5.0 + i.float32) * 0.5) * PI * 2.0 / chaosCount.float32
      let dist = enemy.radius * (0.7 + sin(time * 3.0 + i.float32 * 0.5) * 0.3)
      let x = enemy.pos.x + cos(angle) * dist
      let y = enemy.pos.y + sin(angle) * dist
      drawLine(Vector2(x: enemy.pos.x, y: enemy.pos.y),
              Vector2(x: x, y: y), 2,
              Color(r: 200, g: 0, b: 200, a: 150))
      drawCircle(Vector2(x: x, y: y), 3,
                Color(r: 255, g: 100, b: 255, a: 200))

    # Unstable core
    let coreSize = enemy.radius * (0.6 + sin(time * 7.0) * 0.2)
    drawCircle(Vector2(x: enemy.pos.x, y: enemy.pos.y), coreSize, enemy.color)
    drawCircleLines(enemy.pos.x.int32, enemy.pos.y.int32, coreSize,
                   Color(r: 255, g: 40, b: 220, a: 255))

    # Chaotic center
    drawCircle(Vector2(x: enemy.pos.x, y: enemy.pos.y), enemy.radius * 0.3,
               Color(r: 255, g: 0, b: 255, a: 255))

  of 12:  # Boss 12: The Omega Entity (Color-shifting ultimate)
    # Phase-based color shifting
    let phaseHue = (enemy.currentPhaseIndex.float32 / 4.0) + time * 0.1
    let shiftR = uint8(abs(sin(phaseHue * PI * 2.0)) * 255)
    let shiftG = uint8(abs(sin((phaseHue + 0.33) * PI * 2.0)) * 255)
    let shiftB = uint8(abs(sin((phaseHue + 0.66) * PI * 2.0)) * 255)

    # Multiple rotating layers
    for layer in 0..2:
      let layerRadius = enemy.radius * (0.4 + layer.float32 * 0.3)
      let layerRotation = time * (1.0 + layer.float32) * (if layer mod 2 == 0: 1.0 else: -1.0)
      let layerPoints = 8 + layer * 4

      for i in 0..<layerPoints:
        let angle = i.float32 * PI * 2.0 / layerPoints.float32 + layerRotation
        let nextAngle = (i + 1).float32 * PI * 2.0 / layerPoints.float32 + layerRotation
        let x1 = enemy.pos.x + cos(angle) * layerRadius
        let y1 = enemy.pos.y + sin(angle) * layerRadius
        let x2 = enemy.pos.x + cos(nextAngle) * layerRadius
        let y2 = enemy.pos.y + sin(nextAngle) * layerRadius
        drawLine(Vector2(x: x1, y: y1), Vector2(x: x2, y: y2), 3,
                Color(r: shiftR, g: shiftG, b: shiftB, a: 200))

    # Supreme core with all colors
    drawCircle(Vector2(x: enemy.pos.x, y: enemy.pos.y), enemy.radius * 0.4,
               Color(r: shiftR, g: shiftG, b: shiftB, a: 255))
    drawCircleLines(enemy.pos.x.int32, enemy.pos.y.int32, enemy.radius * 0.4, White)
    drawCircle(Vector2(x: enemy.pos.x, y: enemy.pos.y), enemy.radius * 0.2,
               Color(r: 255, g: 255, b: 255, a: 255))

  else:
    glow(r + 12 + pulse*5, Color(r: 255, g: 255, b: 255, a: 40))
    glow(r, enemy.color)
    poly(8, r, time, 2, White)
    glow(r*0.25, Color(r: 255, g: 255, b: 255, a: 255))

  # Per-boss "ascension" visuals
  # Each phase the boss survives into makes it LOOK more powerful, in a way
  # tailored to its identity: the Orbital Commander fields more satellites, the
  # Summoner King grows a taller crown, the Berserker bristles with more spikes,
  # etc. Phase 0 (the base form) adds nothing; power escalates with phaseLvl.
  if phaseLvl >= 1:
    case enemy.bossDefinitionID
    of 1:  # Spiral Guardian: extra cosmic rings + orbiting stars
      for k in 0 ..< phaseLvl:
        poly(14 + k*4, r + 16 + k.float32*7.0,
             time*(0.6 + k.float32*0.3)*(if k mod 2 == 0: 1.0 else: -1.0), 2,
             Color(r: 170, g: 110, b: 255, a: uint8(clamp(70 + k*22, 0, 255))))
      let stars = phaseLvl*3
      for i in 0 ..< stars:
        let a = time*1.2 + i.float32*(TAU/stars.float32)
        let d = r + 26 + pf*4.0
        drawCircle(Vector2(x: cx+cos(a)*d, y: cy+sin(a)*d), 2.5 + pf*0.4,
                   Color(r: 235, g: 205, b: 255, a: 225))

    of 2:  # Summoner King: orbiting golden sigils + royal halo
      let sig = 4 + phaseLvl*2
      for i in 0 ..< sig:
        let a = time*0.8 + i.float32*(TAU/sig.float32)
        let d = r + 18 + pf*5.0
        let sx = cx + cos(a)*d
        let sy = cy + sin(a)*d
        drawCircle(Vector2(x: sx, y: sy), 3.0 + pf*0.5, Color(r: 255, g: 215, b: 60, a: 235))
        drawCircleLines(sx.int32, sy.int32, 5.0 + pf, Color(r: 200, g: 255, b: 120, a: 160))
      poly(8, r + 12 + pf*4.0, time*0.4, 2, Color(r: 255, g: 215, b: 0, a: uint8(80 + phaseLvl*30)))

    of 3:  # Meteor Striker: molten halo + orbiting fireballs
      drawCircleLines(cx.int32, cy.int32, r + 18 + pf*6.0,
                      Color(r: 255, g: 90, b: 0, a: uint8(70 + phaseLvl*30)))
      let fb = phaseLvl + 1
      for i in 0 ..< fb:
        let a = time*1.4 + i.float32*(TAU/fb.float32)
        let d = r + 22 + pf*5.0
        let fx = cx + cos(a)*d
        let fy = cy + sin(a)*d
        drawCircle(Vector2(x: fx, y: fy), 4.0 + pf*0.6, Color(r: 255, g: 140, b: 20, a: 235))
        drawCircle(Vector2(x: fx, y: fy), 2.0, Color(r: 255, g: 240, b: 150, a: 255))

    of 4:  # Laser Architect: nested rotating frames + orbiting nodes
      for k in 0 ..< phaseLvl:
        let sides = if k mod 2 == 0: 6 else: 3
        poly(sides, r + 12 + k.float32*8.0,
             time*(0.4 + k.float32*0.25)*(if k mod 2 == 0: 1.0 else: -1.0), 2,
             Color(r: 0, g: 220, b: 255, a: uint8(clamp(110 - k*20, 0, 255))))
      let nodes = 4 + phaseLvl*2
      for i in 0 ..< nodes:
        let a = -time*0.5 + i.float32*(TAU/nodes.float32)
        let d = r + 14 + pf*5.0
        let nx = cx + cos(a)*d
        let ny = cy + sin(a)*d
        drawRectangle((nx-2.0).int32, (ny-2.0).int32, 4, 4, Color(r: 120, g: 255, b: 255, a: 225))

    of 5:  # Void Dancer: deeper void halo + orbiting shards
      glow(r + 24 + pf*8.0, Color(r: 20, g: 0, b: 40, a: uint8(55 + phaseLvl*22)))
      for k in 0 ..< phaseLvl:
        drawCircleLines(cx.int32, cy.int32, r + 14 + k.float32*7.0,
                        Color(r: 140, g: 30, b: 200, a: uint8(clamp(120 - k*20, 0, 255))))
      let shards = phaseLvl*3
      for i in 0 ..< shards:
        let a = -time*1.1 + i.float32*(TAU/shards.float32)
        let d = r + 20 + pf*5.0
        drawCircle(Vector2(x: cx+cos(a)*d, y: cy+sin(a)*d), 2.5 + pf*0.4,
                   Color(r: 200, g: 80, b: 255, a: 225))

    of 6:  # Chain Reactor: overcharged coil ring + radial discharge sparks
      poly(30, r + 12 + pf*5.0, time*2.5, 2, Color(r: 255, g: 255, b: 120, a: uint8(80 + phaseLvl*30)))
      # More phases -> a denser, more violent crown of forked sparks (no orbits).
      let arms = 6 + phaseLvl*4
      for i in 0 ..< arms:
        let a   = time*3.0 + i.float32*(TAU/arms.float32)
        let r0  = r + 6.0
        let r1  = r + 16.0 + pf*9.0 + sin(time*14.0 + i.float32)*5.0
        # Two-segment forked spark: bend it sideways at the midpoint.
        let bend = (if i mod 2 == 0: 0.16 else: -0.16)
        let mx  = cx + cos(a + bend) * (r0 + r1) * 0.5
        let my  = cy + sin(a + bend) * (r0 + r1) * 0.5
        let sparkA = uint8(120 + phaseLvl*30)
        drawLine(Vector2(x: cx + cos(a)*r0, y: cy + sin(a)*r0),
                 Vector2(x: mx, y: my), 1.5, Color(r: 255, g: 255, b: 200, a: sparkA))
        drawLine(Vector2(x: mx, y: my),
                 Vector2(x: cx + cos(a)*r1, y: cy + sin(a)*r1), 1.5,
                 Color(r: 255, g: 255, b: 255, a: sparkA))

    of 7:  # Orbital Commander: MORE satellites (its signature power)
      let extra = phaseLvl*2
      for i in 0 ..< extra:
        let satR = r + 30 + pf*6.0
        let a = -time*0.8 + i.float32*(TAU/extra.float32)
        let sx = cx + cos(a)*satR
        let sy = cy + sin(a)*satR
        drawCircle(Vector2(x: sx, y: sy), 5, Color(r: 180, g: 150, b: 255, a: 240))
        drawCircleLines(sx.int32, sy.int32, 7, Color(r: 255, g: 255, b: 255, a: 130))
        let panA = a + PI/2.0
        drawLine(Vector2(x: sx+cos(panA)*7, y: sy+sin(panA)*7),
                 Vector2(x: sx-cos(panA)*7, y: sy-sin(panA)*7), 2,
                 Color(r: 200, g: 170, b: 255, a: 225))
      poly(60, r + 30 + pf*6.0, time*0.1, 2, Color(r: 150, g: 120, b: 255, a: uint8(70 + phaseLvl*20)))

    of 8:  # Berserker Juggernaut: rage halo + extra spike crown
      glow(r + 16 + pf*6.0, Color(r: 255, g: 0, b: 0, a: uint8(40 + phaseLvl*25)))
      let spikes = 6 + phaseLvl*2
      for i in 0 ..< spikes:
        let a = time*0.2 + i.float32*(TAU/spikes.float32) + 0.3
        let inner = r + 6 + pf*2.0
        let outer = inner + 10 + pf*5.0
        drawLine(Vector2(x: cx+cos(a)*inner, y: cy+sin(a)*inner),
                 Vector2(x: cx+cos(a)*outer, y: cy+sin(a)*outer), 3,
                 Color(r: 220, g: 30, b: 20, a: 230))

    of 9:  # Prism Architect: extra spectrum rings + orbiting prism shards
      for k in 0 ..< (phaseLvl*2):
        drawCircleLines(cx.int32, cy.int32, r + 10 + k.float32*5.0,
                        hueCol(k.float32/6.0 + time*0.2, uint8(max(40, 120 - k*12))))
      let shards = 3 + phaseLvl*2
      for i in 0 ..< shards:
        let a = time*0.9 + i.float32*(TAU/shards.float32)
        let d = r + 16 + pf*5.0
        drawCircle(Vector2(x: cx+cos(a)*d, y: cy+sin(a)*d), 3.0 + pf*0.4,
                   hueCol(i.float32/shards.float32 + time*0.3, 230))

    of 10:  # Timekeeper: extra gear rings + orbiting time glyphs
      for k in 0 ..< phaseLvl:
        poly(12 + k*4, r + 12 + k.float32*7.0,
             time*(0.3 + k.float32*0.2)*(if k mod 2 == 0: 1.0 else: -1.0), 2,
             Color(r: 0, g: 230, b: 230, a: uint8(clamp(120 - k*20, 0, 255))))
      let glyphs = phaseLvl*2
      for i in 0 ..< glyphs:
        let a = -time*0.6 + i.float32*(TAU/glyphs.float32)
        let d = r + 18 + pf*5.0
        drawCircle(Vector2(x: cx+cos(a)*d, y: cy+sin(a)*d), 2.5, Color(r: 180, g: 255, b: 255, a: 220))

    of 11:  # Chaos Weaver: denser chaos bolts + RGB-split halo
      let bolts = phaseLvl*4
      for i in 0 ..< bolts:
        let a = (i.float32 + sin(time*4.0 + i.float32)*0.6)*(TAU/bolts.float32)
        let d = r + 14 + pf*6.0 + sin(time*3.0 + i.float32)*4.0
        drawLine(Vector2(x: cx, y: cy), Vector2(x: cx+cos(a)*d, y: cy+sin(a)*d), 1.5,
                 Color(r: 220, g: 60, b: 230, a: 150))
      let hr = r + 12 + pf*4.0
      drawCircleLines((cx-pf*2.0).int32, cy.int32, hr, Color(r: 255, g: 0, b: 0, a: uint8(40 + phaseLvl*20)))
      drawCircleLines((cx+pf*2.0).int32, cy.int32, hr, Color(r: 0, g: 255, b: 0, a: uint8(40 + phaseLvl*20)))

    of 12:  # Omega Entity: color-cycling outer rings + energy pillars
      for k in 0 ..< (phaseLvl + 1):
        drawCircleLines(cx.int32, cy.int32, r + 14 + k.float32*8.0,
                        hueCol(k.float32/4.0 + time*0.3, uint8(max(40, 110 - k*18))))
      let pillars = 2 + phaseLvl
      for d in 0 ..< pillars:
        let a = time*0.5 + d.float32*(TAU/pillars.float32)
        let reach = r + 26 + pf*6.0
        drawLine(Vector2(x: cx+cos(a)*r, y: cy+sin(a)*r),
                 Vector2(x: cx+cos(a)*reach, y: cy+sin(a)*reach), 3,
                 hueCol(d.float32/pillars.float32 + time, 200))

    else: discard

proc drawBossPhaseTransition*(enemy: Enemy) =
  ## Epic per-boss phase-change animation. Plays while a boss is invulnerable
  ## during a phase transition (driven entirely by `invulnerabilityTimer`, which
  ## is only ever set by `transitionBossToPhase`). The boss is frozen for this
  ## whole window, so this fully owns the boss's transition visuals. Each boss
  ## gets a thematically distinct "charge up and transform" beat:
  ## energy gathers inward (charge), the core flashes white (snap), then the new
  ## phase erupts outward (burst).
  let dur = BossPhaseTransitionDuration
  let p = clamp(1.0'f32 - enemy.invulnerabilityTimer / dur, 0.0'f32, 1.0'f32)
  let time = getTime()
  let cx = enemy.pos.x
  let cy = enemy.pos.y
  let r  = enemy.radius

  # Two acts: gather (0..0.45) then release (0.45..1.0). `flash` peaks at the snap.
  let charge = clamp(p / 0.45'f32, 0.0'f32, 1.0'f32)
  let burst  = clamp((p - 0.45'f32) / 0.55'f32, 0.0'f32, 1.0'f32)
  let flash  = 1.0'f32 - abs(p - 0.45'f32) / 0.45'f32
  let gather = charge * (1.0'f32 - burst)   # charge visuals fade out as burst begins

  proc a(x: float32): uint8 = uint8(clamp(x, 0.0'f32, 255.0'f32))

  proc hueCol(h: float32, alpha: uint8): Color =
    Color(r: a(abs(sin(h*PI*2.0))*255),
          g: a(abs(sin((h+0.33)*PI*2.0))*255),
          b: a(abs(sin((h+0.66)*PI*2.0))*255), a: alpha)

  proc nz(seed: float32): float32 =
    ## Cheap deterministic 0..1 hash (no global RNG: safe to call from drawing).
    let v = sin(seed*127.1 + 13.7) * 43758.5453
    v - floor(v)

  proc ringT(radius, thick: float32, col: Color) =
    for k in 0 ..< max(1, thick.int):
      drawCircleLines(cx.int32, cy.int32, radius - thick*0.5 + k.float32, col)

  proc shock(extra, thick: float32, col: Color) =
    ## Expanding ring over the burst that fades as it grows.
    if burst > 0.0'f32:
      ringT(r + burst*extra, thick,
            Color(r: col.r, g: col.g, b: col.b, a: a((1.0'f32 - burst) * col.a.float32)))

  # Shared white-hot core flare at the snap moment.
  if flash > 0.05'f32:
    drawCircle(Vector2(x: cx, y: cy), r*(0.6 + flash*1.5), Color(r: 255, g: 255, b: 255, a: a(flash*190.0)))
    drawCircle(Vector2(x: cx, y: cy), r*(0.3 + flash*0.7), Color(r: 255, g: 255, b: 255, a: a(flash*255.0)))

  case enemy.bossDefinitionID

  of 1:  # Spiral Guardian: vortex implosion then purple nova
    for arm in 0 ..< 6:
      let base = -time*5.0 + arm.float32*(TAU/6.0)
      let outer = r*0.2 + (1.0'f32 - gather)*150.0
      var prev = Vector2(x: cx, y: cy)
      for step in 0 .. 12:
        let t = step.float32 / 12.0
        let dist = outer*(1.0 - t) + r*0.15*t
        let ang = base + t*5.0
        let pt = Vector2(x: cx + cos(ang)*dist, y: cy + sin(ang)*dist)
        if step > 0:
          drawLine(prev, pt, 2.0, Color(r: 190, g: 120, b: 255, a: a(200.0*gather)))
        prev = pt
    shock(170.0, 3.0, Color(r: 150, g: 70, b: 255, a: 220))
    shock(110.0, 2.0, Color(r: 220, g: 160, b: 255, a: 160))

  of 2:  # Summoner King: summoning ritual, golden release
    let ringR = r + 18.0 + (1.0'f32 - gather)*60.0
    for i in 0 ..< 12:
      let a0 = time*1.2 + i.float32*(TAU/12.0)
      let a1 = time*1.2 + (i+1).float32*(TAU/12.0)
      drawLine(Vector2(x: cx+cos(a0)*ringR, y: cy+sin(a0)*ringR),
               Vector2(x: cx+cos(a1)*ringR, y: cy+sin(a1)*ringR), 2.5,
               Color(r: 80, g: 230, b: 90, a: a(220.0*max(gather, 0.3))))
    for i in 0 ..< 6:
      let ang = -time*2.0 + i.float32*(TAU/6.0)
      drawCircle(Vector2(x: cx+cos(ang)*ringR, y: cy+sin(ang)*ringR), 4.0 + gather*2.0,
                 Color(r: 255, g: 230, b: 90, a: a(255.0*max(gather, 0.35))))
    for s in 0 ..< 3:
      let off = (s.float32 - 1.0)*r*0.5
      drawLine(Vector2(x: cx+off, y: cy), Vector2(x: cx+off, y: cy - (r+80.0)*gather), 3.0,
               Color(r: 150, g: 255, b: 120, a: a(160.0*gather)))
    shock(150.0, 3.0, Color(r: 255, g: 215, b: 60, a: 220))
    for i in 0 ..< 6:
      let ang = i.float32*(TAU/6.0)
      let d = r + burst*150.0
      drawCircle(Vector2(x: cx+cos(ang)*d, y: cy+sin(ang)*d), 5.0*(1.0-burst) + 1.0,
                 Color(r: 120, g: 255, b: 90, a: a((1.0'f32-burst)*255.0)))

  of 3:  # Meteor Striker: volcanic eruption
    for i in 0 ..< 8:
      let ang = i.float32*(TAU/8.0) + 0.2
      let tip = r*0.2 + r*1.1*gather
      var prev = Vector2(x: cx, y: cy)
      for step in 1 .. 3:
        let t = step.float32 / 3.0
        let jit = sin(time*20.0 + i.float32*2.0 + step.float32)*6.0
        let pt = Vector2(x: cx + cos(ang)*tip*t + cos(ang+1.57)*jit,
                         y: cy + sin(ang)*tip*t + sin(ang+1.57)*jit)
        drawLine(prev, pt, 3.0, Color(r: 255, g: a(120.0 + gather*100.0), b: 0, a: a(230.0*gather)))
        prev = pt
    shock(160.0, 4.0, Color(r: 255, g: 80, b: 0, a: 230))
    shock(100.0, 2.0, Color(r: 255, g: 180, b: 30, a: 180))
    for i in 0 ..< 10:
      let hx = cx + sin(i.float32*1.7)*r*1.2
      let ey = cy - burst*(120.0 + (i mod 5).float32*20.0)
      drawLine(Vector2(x: hx, y: ey), Vector2(x: hx, y: ey+14.0), 2.0,
               Color(r: 255, g: 160, b: 40, a: a((1.0'f32-burst)*220.0)))

  of 4:  # Laser Architect: blueprint reconstruction
    let cyan = Color(r: 0, g: 220, b: 255, a: a(230.0*max(gather, 0.3)))
    let half = r + 14.0 + (1.0'f32 - gather)*70.0
    let bl = 16.0'f32
    for sx in [-1.0'f32, 1.0'f32]:
      for sy in [-1.0'f32, 1.0'f32]:
        let bx = cx + sx*half
        let by = cy + sy*half
        drawLine(Vector2(x: bx, y: by), Vector2(x: bx - sx*bl, y: by), 2.5, cyan)
        drawLine(Vector2(x: bx, y: by), Vector2(x: bx, y: by - sy*bl), 2.5, cyan)
    for i in 0 ..< 6:
      let a0 = time*1.5 + i.float32*(TAU/6.0)
      let a1 = time*1.5 + (i+1).float32*(TAU/6.0)
      drawLine(Vector2(x: cx+cos(a0)*r*0.7, y: cy+sin(a0)*r*0.7),
               Vector2(x: cx+cos(a1)*r*0.7, y: cy+sin(a1)*r*0.7), 2.0, cyan)
    let sweep = time*1.5
    let scanY = cy - half + 2.0*half*(sweep - floor(sweep))
    drawLine(Vector2(x: cx-half, y: scanY), Vector2(x: cx+half, y: scanY), 1.5,
             Color(r: 120, g: 255, b: 255, a: a(160.0*gather)))
    shock(150.0, 3.0, Color(r: 0, g: 220, b: 255, a: 220))
    if burst > 0.0'f32:
      let g = r + burst*150.0
      drawLine(Vector2(x: cx-g, y: cy), Vector2(x: cx+g, y: cy), 1.5, Color(r: 0, g: 220, b: 255, a: a((1.0'f32-burst)*150.0)))
      drawLine(Vector2(x: cx, y: cy-g), Vector2(x: cx, y: cy+g), 1.5, Color(r: 0, g: 220, b: 255, a: a((1.0'f32-burst)*150.0)))

  of 5:  # Void Dancer: collapsing black hole then reality tear
    for k in 0 ..< 4:
      let fr = gather + k.float32*0.25
      let frac = fr - floor(fr)
      let rad = (r+120.0)*(1.0 - frac) + r*0.2
      drawCircleLines(cx.int32, cy.int32, rad, Color(r: 120, g: 20, b: 160, a: a(180.0*(1.0-frac)*max(gather, 0.2))))
    drawCircle(Vector2(x: cx, y: cy), r*0.5*(1.0'f32-burst), Color(r: 10, g: 0, b: 20, a: a(220.0*gather)))
    drawCircleLines(cx.int32, cy.int32, r*0.5*(1.0'f32-burst) + 2.0, Color(r: 220, g: 60, b: 230, a: a(230.0*gather)))
    if burst > 0.0'f32:
      let tr = r + burst*160.0
      var prev = Vector2(x: cx+tr, y: cy)
      for i in 1 .. 24:
        let ang = i.float32*(TAU/24.0)
        let jag = tr + sin(i.float32*3.0 + time*10.0)*10.0
        let pt = Vector2(x: cx+cos(ang)*jag, y: cy+sin(ang)*jag)
        drawLine(prev, pt, 2.0, Color(r: 200, g: 60, b: 230, a: a((1.0'f32-burst)*220.0)))
        prev = pt

  of 6:  # Chain Reactor: electric overload discharge
    for i in 0 ..< 10:
      let ang = time*3.0 + i.float32*(TAU/10.0)
      let r0 = r + 4.0
      let r1 = r + 10.0 + sin(time*30.0 + i.float32*5.0)*8.0*gather
      drawLine(Vector2(x: cx+cos(ang)*r0, y: cy+sin(ang)*r0),
               Vector2(x: cx+cos(ang)*r1, y: cy+sin(ang)*r1), 1.5,
               Color(r: 255, g: 240, b: 80, a: a(220.0*gather)))
    if burst > 0.0'f32:
      for b in 0 ..< 8:
        let ang = b.float32*(TAU/8.0) + time*0.5
        var prev = Vector2(x: cx+cos(ang)*r, y: cy+sin(ang)*r)
        let reach = r + burst*150.0
        for step in 1 .. 5:
          let t = step.float32 / 5.0
          let jit = sin(time*40.0 + b.float32*7.0 + step.float32*2.0)*14.0*(1.0-t)
          let d = r + (reach-r)*t
          let pt = Vector2(x: cx+cos(ang)*d + cos(ang+1.57)*jit, y: cy+sin(ang)*d + sin(ang+1.57)*jit)
          drawLine(prev, pt, 2.0, Color(r: 255, g: 255, b: 120, a: a((1.0'f32-burst)*240.0)))
          prev = pt
    shock(150.0, 2.0, Color(r: 255, g: 240, b: 80, a: 200))

  of 7:  # Orbital Commander: satellite redeploy
    for i in 0 ..< 8:
      let ang = time*2.0 + i.float32*(TAU/8.0)
      let dist = r*0.3 + (r+110.0)*(1.0'f32 - gather)
      drawCircle(Vector2(x: cx+cos(ang)*dist, y: cy+sin(ang)*dist), 3.5,
                 Color(r: 90, g: 160, b: 255, a: a(230.0*max(gather, 0.3))))
    let rr = r + 20.0
    for q in 0 ..< 4:
      let a0 = time*0.8 + q.float32*(PI*0.5)
      let a1 = a0 + 0.5
      drawLine(Vector2(x: cx+cos(a0)*rr, y: cy+sin(a0)*rr),
               Vector2(x: cx+cos(a1)*rr, y: cy+sin(a1)*rr), 2.5,
               Color(r: 120, g: 190, b: 255, a: a(200.0*max(gather, 0.4))))
    if burst > 0.0'f32:
      for i in 0 ..< 8:
        let ang = i.float32*(TAU/8.0)
        let d = r + burst*130.0
        drawCircle(Vector2(x: cx+cos(ang)*d, y: cy+sin(ang)*d), 4.0,
                   Color(r: 90, g: 160, b: 255, a: a((1.0'f32 - burst*0.5)*230.0)))
    shock(150.0, 3.0, Color(r: 80, g: 150, b: 255, a: 210))

  of 8:  # Berserker Juggernaut: rage roar
    let shake = sin(time*60.0)*4.0*gather
    let bx = cx + shake
    for i in 0 ..< 8:
      let ang = i.float32*(TAU/8.0)
      let d0 = r + 14.0 + (1.0'f32 - gather)*50.0
      let p0 = Vector2(x: bx+cos(ang)*d0, y: cy+sin(ang)*d0)
      let p1 = Vector2(x: bx+cos(ang-0.18)*(d0-12.0), y: cy+sin(ang-0.18)*(d0-12.0))
      let p2 = Vector2(x: bx+cos(ang+0.18)*(d0-12.0), y: cy+sin(ang+0.18)*(d0-12.0))
      drawLine(p1, p0, 3.0, Color(r: 255, g: 50, b: 30, a: a(230.0*gather)))
      drawLine(p2, p0, 3.0, Color(r: 255, g: 50, b: 30, a: a(230.0*gather)))
    drawCircle(Vector2(x: bx, y: cy), r*0.5, Color(r: 255, g: 40, b: 20, a: a(120.0*gather)))
    if burst > 0.0'f32:
      for w in 0 ..< 3:
        let fr = burst - w.float32*0.18
        if fr > 0.0'f32:
          drawCircleLines(cx.int32, cy.int32, r + fr*170.0, Color(r: 255, g: 50, b: 30, a: a((1.0'f32-fr)*230.0)))
      for i in 0 ..< 12:
        let ang = i.float32*(TAU/12.0)
        let d = r + burst*150.0
        drawLine(Vector2(x: cx+cos(ang)*(d-12.0), y: cy+sin(ang)*(d-12.0)),
                 Vector2(x: cx+cos(ang)*d, y: cy+sin(ang)*d), 3.0,
                 Color(r: 255, g: 90, b: 40, a: a((1.0'f32-burst)*230.0)))

  of 9:  # Prism Architect: prismatic refraction burst
    for i in 0 ..< 12:
      let ang = i.float32*(TAU/12.0) + time
      let d = r*0.2 + (r+90.0)*(1.0'f32 - gather)
      drawLine(Vector2(x: cx+cos(ang)*d, y: cy+sin(ang)*d),
               Vector2(x: cx+cos(ang)*(d+10.0), y: cy+sin(ang)*(d+10.0)), 2.0,
               Color(r: 255, g: 255, b: 255, a: a(200.0*gather)))
    if burst > 0.0'f32:
      for i in 0 ..< 18:
        let ang = i.float32*(TAU/18.0)
        let col = hueCol(i.float32/18.0, a((1.0'f32-burst)*230.0))
        let d = r + burst*170.0
        drawLine(Vector2(x: cx+cos(ang)*r, y: cy+sin(ang)*r),
                 Vector2(x: cx+cos(ang)*d, y: cy+sin(ang)*d), 2.5, col)
      for k in 0 ..< 3:
        drawCircleLines(cx.int32, cy.int32, r + burst*130.0 - k.float32*14.0,
                        hueCol(k.float32/3.0 + time, a((1.0'f32-burst)*200.0)))

  of 10:  # Timekeeper: time rewind
    let teal = Color(r: 120, g: 230, b: 210, a: a(220.0*max(gather, 0.3)))
    let clockR = r + 22.0
    for i in 0 ..< 12:
      let ang = i.float32*(TAU/12.0)
      drawLine(Vector2(x: cx+cos(ang)*(clockR-6.0), y: cy+sin(ang)*(clockR-6.0)),
               Vector2(x: cx+cos(ang)*clockR, y: cy+sin(ang)*clockR), 2.0, teal)
    drawCircleLines(cx.int32, cy.int32, clockR, teal)
    let hAng = -time*6.0
    drawLine(Vector2(x: cx, y: cy), Vector2(x: cx+cos(hAng)*r*0.7, y: cy+sin(hAng)*r*0.7), 2.5,
             Color(r: 255, g: 220, b: 80, a: a(230.0*gather)))
    let mAng = -time*2.0
    drawLine(Vector2(x: cx, y: cy), Vector2(x: cx+cos(mAng)*r*0.45, y: cy+sin(mAng)*r*0.45), 2.5,
             Color(r: 255, g: 220, b: 80, a: a(230.0*gather)))
    for k in 1 .. 3:
      let ga = -time*6.0 + k.float32*0.4
      drawCircleLines((cx+cos(ga)*8.0).int32, (cy+sin(ga)*8.0).int32, r*0.8,
                      Color(r: 120, g: 230, b: 210, a: a(60.0*gather/k.float32)))
    shock(150.0, 3.0, Color(r: 120, g: 230, b: 210, a: 210))
    if burst > 0.0'f32:
      for i in 0 ..< 12:
        let ang = i.float32*(TAU/12.0)
        let d = r + burst*140.0
        drawLine(Vector2(x: cx+cos(ang)*(d-10.0), y: cy+sin(ang)*(d-10.0)),
                 Vector2(x: cx+cos(ang)*d, y: cy+sin(ang)*d), 2.0,
                 Color(r: 255, g: 220, b: 80, a: a((1.0'f32-burst)*200.0)))

  of 11:  # Chaos Weaver: glitch storm
    let glitch = floor(time*15.0)
    for i in 0 ..< 10:
      let ang = nz(i.float32 + glitch)*TAU
      let d = r*0.3 + nz(i.float32*2.3 + glitch)*(r+60.0)
      let gx = cx + cos(ang)*d
      let gy = cy + sin(ang)*d
      let sz = 4.0 + nz(i.float32 + glitch + 5.0)*8.0
      drawRectangleLines(gx.int32, gy.int32, sz.int32, sz.int32,
                         Color(r: 200, g: 60, b: 230, a: a(220.0*max(gather, 0.4))))
    for i in 0 ..< 6:
      let a0 = nz(i.float32 + glitch + 9.0)*TAU
      let a1 = a0 + 0.6 + nz(i.float32 + glitch + 3.0)
      let rr = r + 12.0 + nz(i.float32 + glitch)*30.0
      drawLine(Vector2(x: cx+cos(a0)*rr, y: cy+sin(a0)*rr),
               Vector2(x: cx+cos(a1)*rr, y: cy+sin(a1)*rr), 2.0,
               Color(r: 150, g: 80, b: 255, a: a(200.0*gather)))
    if burst > 0.0'f32:
      let br = r + burst*150.0
      drawCircleLines((cx-8.0).int32, cy.int32, br, Color(r: 255, g: 0, b: 0, a: a((1.0'f32-burst)*180.0)))
      drawCircleLines((cx+8.0).int32, cy.int32, br, Color(r: 0, g: 255, b: 0, a: a((1.0'f32-burst)*180.0)))
      drawCircleLines(cx.int32, (cy+8.0).int32, br, Color(r: 0, g: 120, b: 255, a: a((1.0'f32-burst)*180.0)))

  of 12:  # Omega Entity: ultimate ascension (grand finale)
    for layer in 0 ..< 3:
      let lr = r*(0.6 + layer.float32*0.3) + burst*60.0*layer.float32
      let rot = time*(1.0 + layer.float32)*(if layer mod 2 == 0: 1.0 else: -1.0)
      let pts = 6 + layer*3
      for i in 0 ..< pts:
        let a0 = rot + i.float32*(TAU/pts.float32)
        let a1 = rot + (i+1).float32*(TAU/pts.float32)
        let col = hueCol(layer.float32/3.0 + time*0.3, a(220.0*max(gather, 0.4)))
        drawLine(Vector2(x: cx+cos(a0)*lr, y: cy+sin(a0)*lr),
                 Vector2(x: cx+cos(a1)*lr, y: cy+sin(a1)*lr), 2.5, col)
    for d in 0 ..< 4:
      let ang = d.float32*(PI*0.5) + time*0.5
      let reach = (r+100.0)*gather + burst*120.0
      drawLine(Vector2(x: cx+cos(ang)*r, y: cy+sin(ang)*r),
               Vector2(x: cx+cos(ang)*(r+reach), y: cy+sin(ang)*(r+reach)), 4.0,
               hueCol(d.float32/4.0 + time, a(200.0*max(gather, burst))))
    if burst > 0.0'f32:
      for k in 0 ..< 4:
        let fr = burst - k.float32*0.15
        if fr > 0.0'f32:
          drawCircleLines(cx.int32, cy.int32, r + fr*180.0, hueCol(k.float32/4.0 + time*0.5, a((1.0'f32-fr)*220.0)))

  else:  # Unknown boss id: themed generic implode/nova (the case is on int, not an enum)
    for i in 0 ..< 10:
      let ang = i.float32*(TAU/10.0)
      let d = r*0.2 + (r+90.0)*(1.0'f32 - gather)
      drawLine(Vector2(x: cx+cos(ang)*d, y: cy+sin(ang)*d),
               Vector2(x: cx+cos(ang)*(d+10.0), y: cy+sin(ang)*(d+10.0)), 2.0,
               Color(r: enemy.color.r, g: enemy.color.g, b: enemy.color.b, a: a(220.0*gather)))
    shock(150.0, 3.0, Color(r: enemy.color.r, g: enemy.color.g, b: enemy.color.b, a: 220))

proc getThreatColor(level: int): Color =
  case clamp(level, 0, 5)
  of 0: Color(r: 0, g: 0, b: 0, a: 0)
  of 1: Color(r: 80, g: 210, b: 255, a: 255)
  of 2: Color(r: 185, g: 115, b: 255, a: 255)
  of 3: Color(r: 255, g: 175, b: 60, a: 255)
  of 4: Color(r: 255, g: 75, b: 45, a: 255)
  else: Color(r: 255, g: 245, b: 165, a: 255)

proc drawThreatAura(enemy: Enemy) =
  let level = clamp(enemy.threatLevel, 0, 5)
  if level <= 0:
    return

  let t = getTime().float32
  let color = getThreatColor(level)
  let pulse = sin(t * (3.2 + level.float32 * 0.35) + enemy.id.float32 * 0.17) * 0.5 + 0.5
  let cx = enemy.pos.x
  let cy = enemy.pos.y
  let baseRadius = enemy.radius + 6.0 + level.float32 * 3.0 + pulse * (2.0 + level.float32)

  drawCircle(Vector2(x: cx, y: cy), baseRadius + 7.0,
             Color(r: color.r, g: color.g, b: color.b, a: uint8(18 + level * 8)))
  for ring in 0..1:
    let ringRadius = baseRadius + ring.float32 * (5.0 + level.float32)
    let alpha = uint8(max(35, 150 - ring * 45 - level * 8))
    drawCircleLines(cx.int32, cy.int32, ringRadius, Color(r: color.r, g: color.g, b: color.b, a: alpha))

  let spokeCount = 6 + level * 2
  for i in 0..<spokeCount:
    let angle = t * (0.45 + level.float32 * 0.04) + i.float32 * TAU / spokeCount.float32
    let inner = enemy.radius + 3.0 + level.float32
    let outer = baseRadius + 4.0 + sin(t * 5.0 + i.float32) * 2.0
    let alpha = uint8(85 + min(110, level * 24))
    drawLine(
      Vector2(x: cx + cos(angle) * inner, y: cy + sin(angle) * inner),
      Vector2(x: cx + cos(angle) * outer, y: cy + sin(angle) * outer),
      if level >= 4: 2.4 else: 1.4,
      Color(r: color.r, g: color.g, b: color.b, a: alpha))

  if level >= 3:
    let pipCount = min(5, level)
    let totalW = pipCount.float32 * 8.0
    let pipY = cy - enemy.radius - 19.0 - level.float32 * 2.0
    for i in 0..<pipCount:
      let px = cx - totalW / 2.0 + i.float32 * 8.0
      drawRectangle(px.int32, pipY.int32, 5, 5, Color(r: color.r, g: color.g, b: color.b, a: 230))
      drawRectangleLines(px.int32, pipY.int32, 5, 5, Color(r: 255, g: 255, b: 255, a: 150))

proc drawEnemy*(enemy: Enemy) =
  ## Draws an enemy based on its type. Bosses are forwarded to drawCustomBoss.
  # Spawn ring: expanding coloured circle that fades out as the enemy materialises
  if enemy.spawnRingTimer > 0:
    let t = enemy.spawnRingTimer / 0.45'f32          # 1.0 (just spawned) → 0.0 (faded)
    let ringRadius = enemy.radius * (1.0'f32 + (1.0'f32 - t) * 1.2'f32)
    drawCircleLines(enemy.pos.x.int32, enemy.pos.y.int32, ringRadius,
                    Color(r: enemy.color.r, g: enemy.color.g, b: enemy.color.b, a: uint8(t * 200.0'f32)))
    drawCircleLines(enemy.pos.x.int32, enemy.pos.y.int32, ringRadius * 0.72'f32,
                    Color(r: 255, g: 255, b: 255, a: uint8(t * 90.0'f32)))

  # Status effect overlays: pulsing coloured ring tied to active DoT / slow state
  let st = getTime()
  if hasActiveEffect(enemy, etFire):
    let p = float32(sin(st * 8.0) * 0.5 + 0.5)
    drawCircleLines(enemy.pos.x.int32, enemy.pos.y.int32, enemy.radius + 3.0'f32 + p * 2.0'f32,
                    Color(r: 255, g: uint8(80.0'f32 + p * 80.0'f32), b: 0, a: uint8(120.0'f32 + p * 80.0'f32)))
  if hasActiveEffect(enemy, etPoison):
    let p = float32(sin(st * 4.0) * 0.5 + 0.5)
    drawCircleLines(enemy.pos.x.int32, enemy.pos.y.int32, enemy.radius + 3.0'f32 + p * 2.0'f32,
                    Color(r: 30, g: uint8(180.0'f32 + p * 60.0'f32), b: 30, a: uint8(110.0'f32 + p * 80.0'f32)))
  if hasActiveEffect(enemy, etLightning):
    let p = float32(sin(st * 10.0) * 0.5 + 0.5)
    drawCircleLines(enemy.pos.x.int32, enemy.pos.y.int32, enemy.radius + 4.0'f32 + p * 2.0'f32,
                    Color(r: 200, g: 220, b: 255, a: uint8(100.0'f32 + p * 100.0'f32)))
  if hasActiveEffect(enemy, etArcane):
    let p = float32(sin(st * 5.0) * 0.5 + 0.5)
    drawCircleLines(enemy.pos.x.int32, enemy.pos.y.int32, enemy.radius + 3.0'f32 + p * 2.0'f32,
                    Color(r: 160, g: 0, b: 220, a: uint8(100.0'f32 + p * 90.0'f32)))
  if enemy.slowAmount > 0.25'f32:
    let p = float32(sin(st * 3.0) * 0.5 + 0.5)
    let frostA = uint8(clamp(enemy.slowAmount * 160.0'f32, 40.0'f32, 160.0'f32))
    drawCircleLines(enemy.pos.x.int32, enemy.pos.y.int32, enemy.radius + 5.0'f32 + p * 2.0'f32,
                    Color(r: 150, g: 220, b: 255, a: frostA))

  # Hit flash: additive white fill that decays over 0.10 s
  if enemy.hitFlashTimer > 0:
    let flashA = uint8(clamp(enemy.hitFlashTimer / 0.10'f32 * 210.0'f32, 0.0'f32, 210.0'f32))
    drawCircle(Vector2(x: enemy.pos.x, y: enemy.pos.y), enemy.radius,
               Color(r: 255, g: 255, b: 255, a: flashA))

  if enemy.cursed:
    # Pulsing purple hex-ring marking a cursed enemy (Curse power-up)
    let cp = sin(getTime() * 4.0) * 0.5 + 0.5
    drawCircleLines(enemy.pos.x.int32, enemy.pos.y.int32, enemy.radius + 4.0 + cp * 3.0,
                    Color(r: 175, g: 60, b: 215, a: uint8(110 + cp * 90)))
    drawCircleLines(enemy.pos.x.int32, enemy.pos.y.int32, enemy.radius + 7.0 + cp * 4.0,
                    Color(r: 200, g: 110, b: 240, a: uint8(50 + cp * 60)))

  if enemy.isBoss:
    # Boss drawing
    drawCustomBoss(enemy)

    # Boss HP is shown by the top-of-screen phase HUD (drawBossPhaseHud).
    # No per-body bar here, otherwise the boss appears to have two health bars.
    # During a phase change the boss plays its epic, per-boss transformation
    # animation, which owns all of the transition visuals.
    if enemy.invulnerabilityTimer > 0:
      drawBossPhaseTransition(enemy)
  else:
    drawThreatAura(enemy)
    case enemy.enemyType
    of etCircle:
      let t = getTime()
      let pulse = sin(t * 2.5) * 0.5 + 0.5
      let cx = enemy.pos.x
      let cy = enemy.pos.y
      let r  = enemy.radius
      # Soft outer glow
      drawCircle(Vector2(x: cx, y: cy), r + 7 + pulse * 3,
                Color(r: enemy.color.r, g: enemy.color.g, b: enemy.color.b, a: uint8(30 + pulse * 25)))
      # Quivering spike crown (8 short radiating lines driven by velocity + time)
      let numSpikes = 8
      let velLen = sqrt(enemy.vel.x * enemy.vel.x + enemy.vel.y * enemy.vel.y)
      let velAngle = if velLen > 1.0: arctan2(enemy.vel.y, enemy.vel.x) else: 0.0
      for si in 0..<numSpikes:
        let baseAngle = si.float32 * PI / 4.0 + velAngle
        let quiver = sin(t * 18.0 + si.float32 * 0.9) * 0.18  # quiver offset
        let spikeAngle = baseAngle + quiver
        let spikeInner = r * 1.02
        # Spikes are longer in the direction of movement
        let alignBonus = max(0.0, cos(spikeAngle - velAngle)) * (velLen / 80.0) * 4.0
        let spikeOuter = r + 5.0 + alignBonus + pulse * 2.0
        let spikeAlpha = uint8(160 + pulse * 60)
        drawLine(
          Vector2(x: cx + cos(spikeAngle) * spikeInner, y: cy + sin(spikeAngle) * spikeInner),
          Vector2(x: cx + cos(spikeAngle) * spikeOuter, y: cy + sin(spikeAngle) * spikeOuter),
          1.8, Color(r: min(enemy.color.r + 80, 255).uint8,
                     g: min(enemy.color.g + 80, 255).uint8,
                     b: min(enemy.color.b + 80, 255).uint8, a: spikeAlpha))
      # Comet tail when moving fast
      if velLen > 40.0:
        let tailDir = Vector2(x: -enemy.vel.x / velLen, y: -enemy.vel.y / velLen)
        for ti in 1..3:
          let tf = ti.float32
          drawCircle(
            Vector2(x: cx + tailDir.x * tf * r * 0.55, y: cy + tailDir.y * tf * r * 0.55),
            r * (1.0'f32 - tf * 0.22'f32),
            Color(r: enemy.color.r, g: enemy.color.g, b: enemy.color.b, a: uint8(55 - ti * 15)))
      # Main body
      drawCircle(Vector2(x: cx, y: cy), r, enemy.color)
      # Dark-tinted rim (same hue, much darker, no white)
      drawCircleLines(cx.int32, cy.int32, r,
                     Color(r: enemy.color.r div 3, g: enemy.color.g div 3, b: enemy.color.b div 3, a: 220))
      # Inner concentric ring for depth
      drawCircleLines(cx.int32, cy.int32, r * 0.55,
                     Color(r: enemy.color.r div 2, g: enemy.color.g div 2, b: enemy.color.b div 2, a: 120))
      # Bright core dot, keep white, it's a tiny accent not an outline
      drawCircle(Vector2(x: cx, y: cy), r * 0.20,
                Color(r: 255, g: 255, b: 255, a: 200))

    of etCube:
      let t  = getTime()
      let s  = enemy.radius
      let cx = enemy.pos.x
      let cy = enemy.pos.y
      # Soft glow halo
      drawCircle(Vector2(x: cx, y: cy), s + 9,
                Color(r: enemy.color.r, g: enemy.color.g, b: enemy.color.b, a: 28))
      # Main filled square
      drawRectangle((cx - s).int32, (cy - s).int32,
                    (s * 2).int32, (s * 2).int32, enemy.color)
      # Crisp dark border (hue-matched, not white)
      drawRectangleLines((cx - s).int32, (cy - s).int32,
                         (s * 2).int32, (s * 2).int32,
                         Color(r: enemy.color.r div 3, g: enemy.color.g div 3, b: enemy.color.b div 3, a: 220))
      # Inner X cross, "gun turret" visual cue for ranged attacker
      drawLine(Vector2(x: cx - s * 0.55, y: cy - s * 0.55),
               Vector2(x: cx + s * 0.55, y: cy + s * 0.55), 2,
               Color(r: enemy.color.r div 2, g: enemy.color.g div 2, b: enemy.color.b div 2, a: 160))
      drawLine(Vector2(x: cx + s * 0.55, y: cy - s * 0.55),
               Vector2(x: cx - s * 0.55, y: cy + s * 0.55), 2,
               Color(r: enemy.color.r div 2, g: enemy.color.g div 2, b: enemy.color.b div 2, a: 160))
      # Inner square (rotated 45°) drawn as diamond for extra detail
      let d = s * 0.42
      drawLine(Vector2(x: cx, y: cy - d), Vector2(x: cx + d, y: cy), 2,
               Color(r: enemy.color.r div 2, g: enemy.color.g div 2, b: enemy.color.b div 2, a: 130))
      drawLine(Vector2(x: cx + d, y: cy), Vector2(x: cx, y: cy + d), 2,
               Color(r: enemy.color.r div 2, g: enemy.color.g div 2, b: enemy.color.b div 2, a: 130))
      drawLine(Vector2(x: cx, y: cy + d), Vector2(x: cx - d, y: cy), 2,
               Color(r: enemy.color.r div 2, g: enemy.color.g div 2, b: enemy.color.b div 2, a: 130))
      drawLine(Vector2(x: cx - d, y: cy), Vector2(x: cx, y: cy - d), 2,
               Color(r: enemy.color.r div 2, g: enemy.color.g div 2, b: enemy.color.b div 2, a: 130))
      # Corner accent circles, bright white, tiny, feels like rivets
      let cs = s * 0.14
      for ox, oy in [(-(s-cs), -(s-cs)), ((s-cs), -(s-cs)),
                     ((s-cs),  (s-cs)),  (-(s-cs),  (s-cs))].items:
        drawCircle(Vector2(x: cx + ox, y: cy + oy), cs,
                  Color(r: 255, g: 255, b: 255, a: 180))
      # Slow-spinning inner square outline (machine-gun turret feel)
      let squareSpin = t * 0.55
      let sqR = s * 0.55
      for si in 0..<4:
        let a0 = squareSpin + si.float32 * PI / 2.0 + PI / 4.0
        let a1 = squareSpin + (si.float32 + 1.0) * PI / 2.0 + PI / 4.0
        drawLine(
          Vector2(x: cx + cos(a0) * sqR, y: cy + sin(a0) * sqR),
          Vector2(x: cx + cos(a1) * sqR, y: cy + sin(a1) * sqR),
          1.5, Color(r: min(enemy.color.r + 60, 255).uint8,
                     g: min(enemy.color.g + 60, 255).uint8,
                     b: min(enemy.color.b + 60, 255).uint8, a: 180))
      # Pulsing orange core, gun-turret charge indicator
      let firePulse = float32(sin(t * 8.0) * 0.5 + 0.5)
      drawCircle(Vector2(x: cx, y: cy), s * 0.22'f32 + firePulse * 2.0'f32,
                Color(r: 255, g: uint8(120.0'f32 + firePulse * 80.0'f32), b: 0,
                      a: uint8(160.0'f32 + firePulse * 60.0'f32)))

    of etTriangle:
      # During active dash: show a bright motion trail behind the triangle
      if enemy.dashCooldown > 0:
        for i in 1..8:
          let trailAlpha = uint8(220 - i * 25)
          let trailScale = 1.0 - (i.float32 * 0.09)
          let trailX = enemy.pos.x - enemy.vel.x * i.float32 * 0.012
          let trailY = enemy.pos.y - enemy.vel.y * i.float32 * 0.012
          let r = enemy.radius * trailScale
          let tv1 = Vector2(x: trailX, y: trailY - r)
          let tv2 = Vector2(x: trailX - r * 0.87, y: trailY + r * 0.5)
          let tv3 = Vector2(x: trailX + r * 0.87, y: trailY + r * 0.5)
          drawTriangle(tv1, tv2, tv3, Color(r: 255'u8, g: 160'u8, b: 255'u8, a: trailAlpha))
        # Speed lines along velocity direction
        let velLenSq = enemy.vel.x * enemy.vel.x + enemy.vel.y * enemy.vel.y
        if velLenSq > 0.01:
          let velLen = sqrt(velLenSq)
          let dashDir = newVector2f(-enemy.vel.x / velLen, -enemy.vel.y / velLen)
          let perpDir = newVector2f(-dashDir.y, dashDir.x)
          for i in 0..4:
            let perp = sin(i.float32 * 1.2566) * enemy.radius * 0.6
            let lineX = enemy.pos.x + perpDir.x * perp
            let lineY = enemy.pos.y + perpDir.y * perp
            let lineLen = enemy.radius * (1.5 + i.float32 * 0.3)
            drawLine(Vector2(x: lineX, y: lineY),
                     Vector2(x: lineX + dashDir.x * lineLen, y: lineY + dashDir.y * lineLen),
                     2, Color(r: 255'u8, g: 100'u8, b: 255'u8, a: 160'u8))
      elif enemy.dashTimer < 1.0:
        # Wind-up glow: grows brighter as the next dash approaches
        let chargePercent = 1.0 - (enemy.dashTimer / 1.0)
        let glowAlpha = uint8(chargePercent * 210)
        let glowRadius = enemy.radius + 4.0 + chargePercent * 8.0
        drawCircle(Vector2(x: enemy.pos.x, y: enemy.pos.y), glowRadius,
                  Color(r: 255'u8, g: 80'u8, b: 255'u8, a: glowAlpha))
        # Crackle lines from body when very close to dashing
        if enemy.dashTimer < 0.8:
          let crackle = (0.8'f32 - enemy.dashTimer) / 0.8'f32
          for ci in 0..<6:
            let ca = ci.float32 * PI / 3.0'f32 + float32(getTime() * 0.5)
            let cLen = enemy.radius * 0.4'f32 * crackle
            drawLine(
              Vector2(x: enemy.pos.x + cos(ca) * enemy.radius * 0.3'f32,
                      y: enemy.pos.y + sin(ca) * enemy.radius * 0.3'f32),
              Vector2(x: enemy.pos.x + cos(ca) * (enemy.radius * 0.3'f32 + cLen),
                      y: enemy.pos.y + sin(ca) * (enemy.radius * 0.3'f32 + cLen)),
              1.5, Color(r: 255'u8, g: 80'u8, b: 255'u8, a: uint8(crackle * 200.0'f32)))
      let v1 = Vector2(x: enemy.pos.x, y: enemy.pos.y - enemy.radius)
      let v2 = Vector2(x: enemy.pos.x - enemy.radius * 0.87, y: enemy.pos.y + enemy.radius * 0.5)
      let v3 = Vector2(x: enemy.pos.x + enemy.radius * 0.87, y: enemy.pos.y + enemy.radius * 0.5)
      drawTriangle(v1, v2, v3, enemy.color)
      # Dark hue-matched outline instead of white
      drawTriangleLines(v1, v2, v3,
                       Color(r: enemy.color.r div 3, g: enemy.color.g div 3, b: enemy.color.b div 3, a: 220))
      # Inner triangle for depth, slightly lighter than the dark outline
      let is2 = 0.48
      let iv1 = Vector2(x: enemy.pos.x, y: enemy.pos.y - enemy.radius * is2)
      let iv2 = Vector2(x: enemy.pos.x - enemy.radius * 0.87 * is2, y: enemy.pos.y + enemy.radius * 0.5 * is2)
      let iv3 = Vector2(x: enemy.pos.x + enemy.radius * 0.87 * is2, y: enemy.pos.y + enemy.radius * 0.5 * is2)
      drawTriangleLines(iv1, iv2, iv3,
                       Color(r: enemy.color.r div 2, g: enemy.color.g div 2, b: enemy.color.b div 2, a: 130))
      # Center core dot, tiny white accent, not an outline
      drawCircle(Vector2(x: enemy.pos.x, y: enemy.pos.y + enemy.radius * 0.12),
                enemy.radius * 0.14, Color(r: 255, g: 255, b: 255, a: 200))

    of etStar:
      let t  = getTime()
      let cx = enemy.pos.x
      let cy = enemy.pos.y
      let r  = enemy.radius
      let pulseIntensity = sin(t * 3.0) * 0.3 + 0.5

      # Outer glow layers
      drawCircle(Vector2(x: cx, y: cy), r + 14,
                Color(r: 255'u8, g: 215'u8, b: 0'u8, a: uint8(pulseIntensity * 50)))
      drawCircle(Vector2(x: cx, y: cy), r + 7,
                Color(r: 255'u8, g: 215'u8, b: 0'u8, a: uint8(pulseIntensity * 80)))

      # Dash charge indicator (overrides normal glow when charging)
      if enemy.dashCooldown < 0.5:
        let chargePercent = 1.0 - (enemy.dashCooldown / 0.5)
        let chargeGlow = uint8(chargePercent * 160)
        drawCircle(Vector2(x: cx, y: cy), r + 9,
                  Color(r: 255'u8, g: 200'u8, b: 0'u8, a: chargeGlow))

      # Draw filled star using triangle fan (10 segments alternating outer/inner)
      let starRot = float32(getTime() * 0.25)
      let points = 5
      let innerR = r * 0.42
      for i in 0..<points * 2:
        let a0 = i.float32       * PI / points.float32 - PI / 2.0 + starRot
        let a1 = (i + 1).float32 * PI / points.float32 - PI / 2.0 + starRot
        let r0 = if i mod 2 == 0: r else: innerR
        let r1 = if (i + 1) mod 2 == 0: r else: innerR
        let p0 = Vector2(x: cx + cos(a0) * r0, y: cy + sin(a0) * r0)
        let p1 = Vector2(x: cx + cos(a1) * r1, y: cy + sin(a1) * r1)
        drawTriangle(p0, p1, Vector2(x: cx, y: cy), enemy.color)

      # Star outline, dark golden, not white
      for i in 0..<points * 2:
        let a0 = i.float32       * PI / points.float32 - PI / 2.0 + starRot
        let a1 = (i + 1).float32 * PI / points.float32 - PI / 2.0 + starRot
        let r0 = if i mod 2 == 0: r else: innerR
        let r1 = if (i + 1) mod 2 == 0: r else: innerR
        drawLine(Vector2(x: cx + cos(a0) * r0, y: cy + sin(a0) * r0),
                 Vector2(x: cx + cos(a1) * r1, y: cy + sin(a1) * r1),
                 2, Color(r: 255, g: 200, b: 0, a: 220))

      # Bright center core
      drawCircle(Vector2(x: cx, y: cy), r * 0.20,
                Color(r: 255, g: 255, b: 255, a: 230))

      # Vertex node indicators, one glowing dot per required hit, dims when hit consumed
      for vi in 0..<enemy.requiredHits:
        let vAngle = vi.float32 * (PI * 2.0 / enemy.requiredHits.float32) - PI / 2.0 + starRot
        let nodeR = r * 1.15
        let isHit = vi < enemy.hitCount
        let nodeAlpha = if isHit: 40'u8 else: 230'u8
        let nodeColor = if isHit:
          Color(r: 80, g: 80, b: 0, a: nodeAlpha)
        else:
          Color(r: 255, g: 240, b: 0, a: nodeAlpha)
        let nodeGlowAlpha = if isHit: 0'u8 else: uint8(80 + pulseIntensity * 60)
        # Glow halo
        drawCircle(
          Vector2(x: cx + cos(vAngle) * nodeR, y: cy + sin(vAngle) * nodeR),
          5.5, Color(r: 255, g: 230, b: 0, a: nodeGlowAlpha))
        # Solid dot
        drawCircle(
          Vector2(x: cx + cos(vAngle) * nodeR, y: cy + sin(vAngle) * nodeR),
          3.0, nodeColor)

      # Final-hit urgency pulse on the last surviving vertex node
      let remaining = enemy.requiredHits - enemy.hitCount
      if remaining == 1:
        let urgency = float32(sin(getTime() * 12.0) * 0.5 + 0.5)
        let lastAngle = enemy.hitCount.float32 * (PI * 2.0 / enemy.requiredHits.float32) - PI / 2.0 + starRot
        drawCircle(
          Vector2(x: cx + cos(lastAngle) * r * 1.15'f32, y: cy + sin(lastAngle) * r * 1.15'f32),
          8.0'f32 + urgency * 4.0'f32,
          Color(r: 255, g: 230, b: 0, a: uint8(urgency * 180.0'f32)))

      # Hit counter, white text on small dark pill
      let text = $remaining
      let textWidth = measureText(text, 14)
      drawCircle(Vector2(x: cx, y: cy), r * 0.28,
                Color(r: 0, g: 0, b: 0, a: 160))
      drawText(text, (cx - textWidth / 2).int32, (cy - 7).int32, 14,
               Color(r: 255, g: 255, b: 255, a: 240))

    of etHexagon:
      let t   = getTime()
      let cx  = enemy.pos.x
      let cy  = enemy.pos.y
      let r   = enemy.radius
      let rot = t * 0.35  # slow rotation
      # Soft outer glow
      drawCircle(Vector2(x: cx, y: cy), r + 8,
                Color(r: enemy.color.r, g: enemy.color.g, b: enemy.color.b, a: 28))
      # Filled hex body, triangle fan gives visual weight to the wireframe
      for i in 0..<6:
        let fa0 = i.float32       * PI / 3.0'f32 + rot
        let fa1 = (i + 1).float32 * PI / 3.0'f32 + rot
        drawTriangle(
          Vector2(x: cx, y: cy),
          Vector2(x: cx + cos(fa0) * r, y: cy + sin(fa0) * r),
          Vector2(x: cx + cos(fa1) * r, y: cy + sin(fa1) * r),
          Color(r: enemy.color.r, g: enemy.color.g, b: enemy.color.b, a: 55))
      # Outer hexagon (slowly rotating)
      for i in 0..<6:
        let a0 = i.float32       * PI / 3.0 + rot
        let a1 = (i + 1).float32 * PI / 3.0 + rot
        drawLine(Vector2(x: cx + cos(a0) * r,       y: cy + sin(a0) * r),
                 Vector2(x: cx + cos(a1) * r,       y: cy + sin(a1) * r),
                 3, enemy.color)
      # Inner hexagon (counter-rotating, 60° offset)
      let ir = r * 0.52
      for i in 0..<6:
        let a0 = i.float32       * PI / 3.0 - rot + PI / 6.0
        let a1 = (i + 1).float32 * PI / 3.0 - rot + PI / 6.0
        drawLine(Vector2(x: cx + cos(a0) * ir, y: cy + sin(a0) * ir),
                 Vector2(x: cx + cos(a1) * ir, y: cy + sin(a1) * ir),
                 2, Color(r: enemy.color.r, g: enemy.color.g, b: enemy.color.b, a: 180))
      # 6 spokes: outer vertex -> inner vertex
      for i in 0..<6:
        let ao = i.float32 * PI / 3.0 + rot
        let ai = i.float32 * PI / 3.0 - rot + PI / 6.0
        drawLine(Vector2(x: cx + cos(ao) * r,  y: cy + sin(ao) * r),
                 Vector2(x: cx + cos(ai) * ir, y: cy + sin(ai) * ir),
                 1, Color(r: enemy.color.r, g: enemy.color.g, b: enemy.color.b, a: 90))
      # Bright center core, tinted, not raw white
      drawCircle(Vector2(x: cx, y: cy), r * 0.18,
                Color(r: uint8(min(255, enemy.color.r.int + 80)), g: uint8(min(255, enemy.color.g.int + 80)), b: uint8(min(255, enemy.color.b.int + 80)), a: 230))
      # Teleport blink warning, scatter-dissolve effect
      if enemy.hexTeleportTimer < 0.5:
        let dissolveProgress = 1.0 - (enemy.hexTeleportTimer / 0.5)
        let blinkAlpha = uint8((sin(t * 30.0) * 0.5 + 0.5) * 180)
        # Outer warning ring
        drawCircleLines(cx.int32, cy.int32, r + 5,
          Color(r: 255, g: 255, b: 0, a: blinkAlpha))
        # Scattering fragments: 12 dots that drift outward as dissolve increases
        for di in 0..<12:
          let dAngle = di.float32 * PI / 6.0 + t * 4.0
          let dDist = r * (0.5 + dissolveProgress * 1.8)
          let dSize = max(0.5, 3.0 * (1.0 - dissolveProgress))
          let dAlpha = uint8((1.0 - dissolveProgress) * 200)
          drawCircle(
            Vector2(x: cx + cos(dAngle) * dDist, y: cy + sin(dAngle) * dDist),
            dSize, Color(r: min(enemy.color.r + 100, 255).uint8,
                         g: min(enemy.color.g + 100, 255).uint8,
                         b: 255, a: dAlpha))

    of etCross:
      # Draw cross shape with rotation support
      let armLength = enemy.radius * 0.8  # Slightly longer arms
      let armThickness = 8.0

      # Apply rotation (during dash)
      let rotAngle = enemy.rotation

      # Calculate rotated cross arms
      # Horizontal arm (rotated)
      let hx1 = enemy.pos.x + cos(rotAngle) * (-armLength)
      let hy1 = enemy.pos.y + sin(rotAngle) * (-armLength)
      let hx2 = enemy.pos.x + cos(rotAngle) * armLength
      let hy2 = enemy.pos.y + sin(rotAngle) * armLength

      # Vertical arm (rotated 90 degrees from horizontal)
      let vAngle = rotAngle + PI / 2.0
      let vx1 = enemy.pos.x + cos(vAngle) * (-armLength)
      let vy1 = enemy.pos.y + sin(vAngle) * (-armLength)
      let vx2 = enemy.pos.x + cos(vAngle) * armLength
      let vy2 = enemy.pos.y + sin(vAngle) * armLength

      # Draw rotated cross arms with thicker lines
      drawLine(Vector2(x: hx1, y: hy1), Vector2(x: hx2, y: hy2), armThickness, enemy.color)
      drawLine(Vector2(x: vx1, y: vy1), Vector2(x: vx2, y: vy2), armThickness, enemy.color)

      # Draw inner bright cross (also rotated) - slightly thicker
      let innerLength = armLength * 0.65
      let innerThickness = 3.5
      let ihx1 = enemy.pos.x + cos(rotAngle) * (-innerLength)
      let ihy1 = enemy.pos.y + sin(rotAngle) * (-innerLength)
      let ihx2 = enemy.pos.x + cos(rotAngle) * innerLength
      let ihy2 = enemy.pos.y + sin(rotAngle) * innerLength
      let ivx1 = enemy.pos.x + cos(vAngle) * (-innerLength)
      let ivy1 = enemy.pos.y + sin(vAngle) * (-innerLength)
      let ivx2 = enemy.pos.x + cos(vAngle) * innerLength
      let ivy2 = enemy.pos.y + sin(vAngle) * innerLength

      drawLine(Vector2(x: ihx1, y: ihy1), Vector2(x: ihx2, y: ihy2), innerThickness,
              Color(r: 255, g: 150, b: 50, a: 255))
      drawLine(Vector2(x: ivx1, y: ivy1), Vector2(x: ivx2, y: ivy2), innerThickness,
              Color(r: 255, g: 150, b: 50, a: 255))

      # Glowing arm-tip caps
      let tipPoints = [
        Vector2(x: hx2, y: hy2), Vector2(x: hx1, y: hy1),
        Vector2(x: vx2, y: vy2), Vector2(x: vx1, y: vy1)]
      let tipColor = if enemy.attackPhase == 2:
          Color(r: 255, g: 255, b: 255, a: 220)
        elif enemy.attackPhase == 1:
          let tp = uint8((sin(getTime() * 15.0) * 0.5 + 0.5) * 220.0)
          Color(r: 255, g: 30, b: 0, a: tp)
        else:
          Color(r: 255, g: 130, b: 30, a: 140)
      for tip in tipPoints:
        drawCircle(tip, enemy.radius * 0.13'f32, tipColor)

      # Draw central core - slightly larger
      drawCircle(Vector2(x: enemy.pos.x, y: enemy.pos.y), enemy.radius * 0.5, enemy.color)
      drawCircle(Vector2(x: enemy.pos.x, y: enemy.pos.y), enemy.radius * 0.3,
                Color(r: 255, g: 150, b: 0, a: 255))

      # Warning glow with pulsing effect
      if enemy.attackPhase == 1:
        let pulseIntensity = uint8((sin(getTime() * 15.0) * 0.5 + 0.5) * 200)
        drawCircleLines(enemy.pos.x.int32, enemy.pos.y.int32, enemy.radius + 8,
                       Color(r: 255, g: 50, b: 0, a: pulseIntensity))
        drawCircleLines(enemy.pos.x.int32, enemy.pos.y.int32, enemy.radius + 12,
                       Color(r: 255, g: 0, b: 0, a: (pulseIntensity div 2).uint8))

      # Dash effect - motion blur trail during phase 2
      if enemy.attackPhase == 2:
        for i in 1..3:
          let trailAlpha = uint8(150 - i * 40)
          let trailScale = 1.0 - (i.float32 * 0.15)
          let trailX = enemy.pos.x - enemy.vel.x * i.float32 * 0.03
          let trailY = enemy.pos.y - enemy.vel.y * i.float32 * 0.03
          let trailLength = armLength * trailScale

          # Trail horizontal
          let thx1 = trailX + cos(rotAngle - i.float32 * 0.3) * (-trailLength)
          let thy1 = trailY + sin(rotAngle - i.float32 * 0.3) * (-trailLength)
          let thx2 = trailX + cos(rotAngle - i.float32 * 0.3) * trailLength
          let thy2 = trailY + sin(rotAngle - i.float32 * 0.3) * trailLength

          drawLine(Vector2(x: thx1, y: thy1), Vector2(x: thx2, y: thy2), 2,
                  Color(r: enemy.color.r, g: enemy.color.g, b: enemy.color.b, a: trailAlpha))

    of etDiamond:
      let cx = enemy.pos.x
      let cy = enemy.pos.y
      let r  = enemy.radius
      # Soft glow halo
      drawCircle(Vector2(x: cx, y: cy), r + 8,
                Color(r: enemy.color.r, g: enemy.color.g, b: enemy.color.b, a: 30))
      # Spinning jewel, rotate 4 vertices by time
      let dRot = float32(getTime() * 0.4)
      let dv1 = Vector2(x: cx + cos(-PI/2.0'f32 + dRot) * r, y: cy + sin(-PI/2.0'f32 + dRot) * r)
      let dv2 = Vector2(x: cx + cos(0.0'f32     + dRot) * r, y: cy + sin(0.0'f32     + dRot) * r)
      let dv3 = Vector2(x: cx + cos( PI/2.0'f32 + dRot) * r, y: cy + sin( PI/2.0'f32 + dRot) * r)
      let dv4 = Vector2(x: cx + cos( PI         + dRot) * r, y: cy + sin( PI         + dRot) * r)
      # Filled diamond (two triangles, using rotated vertices)
      drawTriangle(dv1, dv2, dv4, enemy.color)
      drawTriangle(dv2, dv3, dv4, enemy.color)
      # Bright cyan outline
      drawLine(dv1, dv2, 3, Color(r: 0'u8, g: 230'u8, b: 255'u8, a: 255))
      drawLine(dv2, dv3, 3, Color(r: 0'u8, g: 230'u8, b: 255'u8, a: 255))
      drawLine(dv3, dv4, 3, Color(r: 0'u8, g: 230'u8, b: 255'u8, a: 255))
      drawLine(dv4, dv1, 3, Color(r: 0'u8, g: 230'u8, b: 255'u8, a: 255))
      # Inner diamond counter-offset for spinning-jewel facet effect
      let ir = r * 0.45
      let iRot = dRot + 0.3'f32
      let iv1 = Vector2(x: cx + cos(-PI/2.0'f32 + iRot) * ir, y: cy + sin(-PI/2.0'f32 + iRot) * ir)
      let iv2 = Vector2(x: cx + cos(0.0'f32     + iRot) * ir, y: cy + sin(0.0'f32     + iRot) * ir)
      let iv3 = Vector2(x: cx + cos( PI/2.0'f32 + iRot) * ir, y: cy + sin( PI/2.0'f32 + iRot) * ir)
      let iv4 = Vector2(x: cx + cos( PI         + iRot) * ir, y: cy + sin( PI         + iRot) * ir)
      drawLine(iv1, iv2, 1, Color(r: 0'u8, g: 160'u8, b: 200'u8, a: 180))
      drawLine(iv2, iv3, 1, Color(r: 0'u8, g: 160'u8, b: 200'u8, a: 180))
      drawLine(iv3, iv4, 1, Color(r: 0'u8, g: 160'u8, b: 200'u8, a: 180))
      drawLine(iv4, iv1, 1, Color(r: 0'u8, g: 160'u8, b: 200'u8, a: 180))
      # Tinted center core
      drawCircle(Vector2(x: cx, y: cy), r * 0.18,
                Color(r: uint8(min(255, enemy.color.r.int + 80)), g: uint8(min(255, enemy.color.g.int + 80)), b: uint8(min(255, enemy.color.b.int + 80)), a: 220))
      # Dash charge indicator
      if enemy.dashCooldown < 0.5:
        let chargePercent = 1.0 - (enemy.dashCooldown / 0.5)
        let glowIntensity = uint8(chargePercent * 180)
        drawCircleLines(cx.int32, cy.int32, r + 7,
                       Color(r: 0, g: 255, b: 255, a: glowIntensity))
      # Diamond 1-hit shield visual (Celestial Veil style)
      if enemy.diamondShieldActive:
        let veilPulse  = 0.5 + 0.5 * sin(getTime() * 3.5)
        let veilRadius = r * 1.7 + veilPulse * 3.0
        let veilAlpha  = uint8(35 + (veilPulse * 30).int)
        let veilLineA  = uint8(140 + (veilPulse * 70).int)
        drawCircle(Vector2(x: cx, y: cy), veilRadius,
                   Color(r: 160, g: 230, b: 255, a: veilAlpha))
        drawCircleLines(cx.int32, cy.int32, veilRadius,
                        Color(r: 180, g: 245, b: 255, a: veilLineA))

    of etOctagon:
      let t  = getTime()
      let cx = enemy.pos.x
      let cy = enemy.pos.y
      let r  = enemy.radius
      # Soft glow
      drawCircle(Vector2(x: cx, y: cy), r + 7,
                Color(r: enemy.color.r, g: enemy.color.g, b: enemy.color.b, a: 28))
      # Outer octagon
      for i in 0..<8:
        let a0 = i.float32       * PI / 4.0
        let a1 = (i + 1).float32 * PI / 4.0
        drawLine(Vector2(x: cx + cos(a0) * r, y: cy + sin(a0) * r),
                 Vector2(x: cx + cos(a1) * r, y: cy + sin(a1) * r),
                 3, enemy.color)
      # Inner octagon (45° offset, counter-rotating slightly)
      let ir  = r * 0.52
      let rot = t * 0.4
      for i in 0..<8:
        let a0 = i.float32       * PI / 4.0 + PI / 8.0 + rot
        let a1 = (i + 1).float32 * PI / 4.0 + PI / 8.0 + rot
        drawLine(Vector2(x: cx + cos(a0) * ir, y: cy + sin(a0) * ir),
                 Vector2(x: cx + cos(a1) * ir, y: cy + sin(a1) * ir),
                 2, Color(r: enemy.color.r, g: enemy.color.g, b: enemy.color.b, a: 180))
      # 8 radial spokes: center -> outer vertex, dark-tinted, not white
      for i in 0..<8:
        let a = i.float32 * PI / 4.0
        drawLine(Vector2(x: cx, y: cy),
                 Vector2(x: cx + cos(a) * r * 0.48, y: cy + sin(a) * r * 0.48),
                 1, Color(r: enemy.color.r div 2, g: enemy.color.g div 2, b: enemy.color.b div 2, a: 100))
      # Gun-port dots at outer vertices, pulsing with fire rate
      let portGlow = float32(sin(t * 10.0) * 0.5 + 0.5)
      for i in 0..<8:
        let pa = i.float32 * PI / 4.0
        drawCircle(
          Vector2(x: cx + cos(pa) * r, y: cy + sin(pa) * r),
          3.5'f32 + portGlow * 1.5'f32,
          Color(r: 255, g: 255, b: uint8(portGlow * 80.0'f32), a: uint8(140.0'f32 + portGlow * 80.0'f32)))
      # Tinted center core
      drawCircle(Vector2(x: cx, y: cy), r * 0.20,
                Color(r: uint8(min(255, enemy.color.r.int + 80)), g: uint8(min(255, enemy.color.g.int + 80)), b: uint8(min(255, enemy.color.b.int + 80)), a: 220))
      # Rapid-fire pulsing ring
      let fireGlow = uint8((sin(t * 10.0) * 0.35 + 0.65) * 110)
      drawCircleLines(cx.int32, cy.int32, r + 4,
                     Color(r: 255, g: 255, b: 0, a: fireGlow))

    of etPentagon:
      let t  = getTime()
      let cx = enemy.pos.x
      let cy = enemy.pos.y
      let r  = enemy.radius
      # Soft outer glow
      drawCircle(Vector2(x: cx, y: cy), r + 8,
                Color(r: enemy.color.r, g: enemy.color.g, b: enemy.color.b, a: 28))
      # Outer pentagon, counter-rotates opposite to inner for gear-within-gear read
      let rot2 = float32(-t * 0.18)
      for i in 0..<5:
        let a0 = i.float32       * PI * 2.0 / 5.0 - PI / 2.0 + rot2
        let a1 = (i + 1).float32 * PI * 2.0 / 5.0 - PI / 2.0 + rot2
        drawLine(Vector2(x: cx + cos(a0) * r, y: cy + sin(a0) * r),
                 Vector2(x: cx + cos(a1) * r, y: cy + sin(a1) * r),
                 3, enemy.color)
      # Inner pentagon
      let ir  = r * 0.50
      let rot = t * 0.3
      for i in 0..<5:
        let a0 = i.float32       * PI * 2.0 / 5.0 + rot
        let a1 = (i + 1).float32 * PI * 2.0 / 5.0 + rot
        drawLine(Vector2(x: cx + cos(a0) * ir, y: cy + sin(a0) * ir),
                 Vector2(x: cx + cos(a1) * ir, y: cy + sin(a1) * ir),
                 2, Color(r: enemy.color.r, g: enemy.color.g, b: enemy.color.b, a: 180))
      # 5 spokes from center to outer vertices, dark-tinted
      for i in 0..<5:
        let a = i.float32 * PI * 2.0 / 5.0 - PI / 2.0
        drawLine(Vector2(x: cx, y: cy),
                 Vector2(x: cx + cos(a) * r * 0.50, y: cy + sin(a) * r * 0.50),
                 1, Color(r: enemy.color.r div 2, g: enemy.color.g div 2, b: enemy.color.b div 2, a: 100))
      # Tinted center core
      drawCircle(Vector2(x: cx, y: cy), r * 0.18,
                Color(r: uint8(min(255, enemy.color.r.int + 80)), g: uint8(min(255, enemy.color.g.int + 80)), b: uint8(min(255, enemy.color.b.int + 80)), a: 220))
      # Charge-up glow when about to fire
      if enemy.shootTimer > 2.0:
        let chargePercent = (enemy.shootTimer - 2.0) / 0.5
        let glowIntensity = uint8(chargePercent * 200)
        drawCircle(Vector2(x: cx, y: cy), r + 7,
                  Color(r: 0, g: 255, b: 150, a: glowIntensity))
      # Bullet preview dots at outer vertices when charging
      if enemy.shootTimer > 1.5:
        let previewAlpha = uint8(clamp((enemy.shootTimer - 1.5'f32) / 1.0'f32 * 180.0'f32, 0.0'f32, 180.0'f32))
        for i in 0..<5:
          let pa = i.float32 * PI * 2.0 / 5.0 - PI / 2.0 + rot2
          drawCircle(
            Vector2(x: cx + cos(pa) * r, y: cy + sin(pa) * r),
            4.0'f32, Color(r: 0, g: 200, b: 100, a: previewAlpha))

    of etTrickster:
      let t  = getTime()
      let cx = enemy.pos.x
      let cy = enemy.pos.y
      let r  = enemy.radius
      let rot = t  # rotates each frame
      # Ghost silhouettes, flickering decoys orbiting the body
      for gi in 0..1:
        let gPhase = gi.float32 * PI + t * 2.5'f32
        let gx = cx + cos(gPhase) * r * 1.4'f32
        let gy = cy + sin(gPhase * 0.7'f32) * r * 1.4'f32
        let gFlicker = float32(sin(t * 17.0 + gi.float32 * 2.1) * 0.5 + 0.5)
        drawCircle(Vector2(x: gx, y: gy), r * 0.45'f32,
                  Color(r: enemy.color.r, g: enemy.color.g, b: enemy.color.b,
                        a: uint8(gFlicker * 38.0'f32)))
      # Outer jagged ring
      let segments = 6
      for i in 0..<segments:
        let a0 = i.float32       * PI * 2.0 / segments.float32 + rot
        let a1 = (i + 1).float32 * PI * 2.0 / segments.float32 + rot
        let r0 = if i mod 2 == 0: r else: r * 0.78
        let r1 = if (i + 1) mod 2 == 0: r else: r * 0.78
        drawLine(Vector2(x: cx + cos(a0) * r0, y: cy + sin(a0) * r0),
                 Vector2(x: cx + cos(a1) * r1, y: cy + sin(a1) * r1),
                 2, enemy.color)
      # Inner counter-rotating smooth hexagon
      for i in 0..<6:
        let a0 = i.float32       * PI / 3.0 - rot * 0.6
        let a1 = (i + 1).float32 * PI / 3.0 - rot * 0.6
        let ir = r * 0.48
        drawLine(Vector2(x: cx + cos(a0) * ir, y: cy + sin(a0) * ir),
                 Vector2(x: cx + cos(a1) * ir, y: cy + sin(a1) * ir),
                 2, Color(r: enemy.color.r, g: enemy.color.g, b: enemy.color.b, a: 160))
      # Filled center
      drawCircle(Vector2(x: cx, y: cy), r * 0.32, enemy.color)
      # Tinted core, not white
      drawCircle(Vector2(x: cx, y: cy), r * 0.16,
                Color(r: uint8(min(255, enemy.color.r.int + 80)), g: uint8(min(255, enemy.color.g.int + 80)), b: uint8(min(255, enemy.color.b.int + 80)), a: 220))
      # Mysterious outer pulse ring
      let mysterPulse = sin(t * 4.0) * 10 + 15
      drawCircleLines(cx.int32, cy.int32, r + mysterPulse,
                     Color(r: 255, g: 0, b: 255, a: 80))

    of etSniper:
      # Draw sniper with charging visualization

      # Persistent glowing aura (always visible, not just when charging)
      let baseGlowPulse = sin(getTime() * 3.0) * 0.3 + 0.7  # Pulse between 0.7-1.0
      let baseGlowRadius = enemy.radius + 8 + baseGlowPulse * 4

      # Multiple glow layers for strong glowing effect
      drawCircle(Vector2(x: enemy.pos.x, y: enemy.pos.y), baseGlowRadius,
                Color(r: 255, g: 50, b: 50, a: uint8(60 * baseGlowPulse)))
      drawCircle(Vector2(x: enemy.pos.x, y: enemy.pos.y), baseGlowRadius - 4,
                Color(r: 255, g: 80, b: 80, a: uint8(90 * baseGlowPulse)))
      drawCircleLines(enemy.pos.x.int32, enemy.pos.y.int32, enemy.radius + 12,
                     Color(r: 255, g: 100, b: 100, a: uint8(120 * baseGlowPulse)))

      # Main body - circular with crosshair
      drawCircle(Vector2(x: enemy.pos.x, y: enemy.pos.y), enemy.radius, enemy.color)

      # Crosshair: rotates slowly when idle, freezes red on lock-on
      let cr = if enemy.attackPhase == 1: 0.0'f32 else: float32(sin(getTime() * 0.9) * 0.35)
      let crossColor = if enemy.attackPhase == 1: Color(r: 255, g: 30, b: 30, a: 220)
                       else: Color(r: 255, g: 255, b: 255, a: 200)
      let cs = enemy.radius * 0.6'f32
      drawLine(
        Vector2(x: enemy.pos.x + cos(cr + PI) * cs, y: enemy.pos.y + sin(cr + PI) * cs),
        Vector2(x: enemy.pos.x + cos(cr)      * cs, y: enemy.pos.y + sin(cr)      * cs),
        2, crossColor)
      drawLine(
        Vector2(x: enemy.pos.x + cos(cr + PI/2.0'f32) * cs, y: enemy.pos.y + sin(cr + PI/2.0'f32) * cs),
        Vector2(x: enemy.pos.x + cos(cr - PI/2.0'f32) * cs, y: enemy.pos.y + sin(cr - PI/2.0'f32) * cs),
        2, crossColor)
      # Scope tick marks draw inward as charge builds
      if enemy.attackPhase == 1:
        let chargeProgress = if enemy.attackExecuteTimer > 0.0'f32:
          clamp(enemy.attackWarningTimer / enemy.attackExecuteTimer, 0.0'f32, 1.0'f32)
          else: 0.0'f32
        let tickLen = cs * 0.25'f32 * chargeProgress
        for ti in 0..<4:
          let ta = cr + ti.float32 * PI / 2.0'f32
          let tipX = enemy.pos.x + cos(ta) * cs
          let tipY = enemy.pos.y + sin(ta) * cs
          drawLine(
            Vector2(x: tipX, y: tipY),
            Vector2(x: tipX - cos(ta) * tickLen, y: tipY - sin(ta) * tickLen),
            2, Color(r: 255, g: 0, b: 0, a: 180))

      # Center dot
      drawCircle(Vector2(x: enemy.pos.x, y: enemy.pos.y), 3.0, Red)

      # Charging effect - expanding rings when charging (ADDITIONAL glow on top of base glow)
      if enemy.attackPhase == 1:
        let chargePercent = enemy.attackWarningTimer / enemy.attackExecuteTimer
        let ringAlpha = uint8((sin(getTime() * 10.0) * 0.5 + 0.5) * 200)
        let ringRadius = enemy.radius + (chargePercent * 20.0)
        drawCircleLines(enemy.pos.x.int32, enemy.pos.y.int32, ringRadius,
                       Color(r: 200, g: 50, b: 200, a: ringAlpha))

        # Inner pulsing ring
        let innerRing = enemy.radius + (chargePercent * 10.0)
        drawCircleLines(enemy.pos.x.int32, enemy.pos.y.int32, innerRing,
                       Color(r: 255, g: 150, b: 255, a: 100))

    of etPhantom:
      let t  = getTime()
      let cx = enemy.pos.x
      let cy = enemy.pos.y
      let r  = enemy.radius
      # Pulsing translucent fill (ghost body, not fully solid)
      let bodyAlpha = uint8(140 + sin(t * 2.0) * 30)
      drawCircle(Vector2(x: cx, y: cy), r,
                Color(r: enemy.color.r, g: enemy.color.g, b: enemy.color.b, a: bodyAlpha))
      # Outer wispy ring, fades in and out
      let wispAlpha = uint8((sin(t * 1.5) * 0.4 + 0.6) * 90)
      drawCircleLines(cx.int32, cy.int32, r + 6,
                     Color(r: enemy.color.r, g: enemy.color.g, b: enemy.color.b, a: wispAlpha))
      # Inner concentric rings (ghostly depth)
      drawCircleLines(cx.int32, cy.int32, r * 0.65,
                     Color(r: 180, g: 180, b: 255, a: uint8(60 + sin(t * 3.0) * 30)))
      drawCircleLines(cx.int32, cy.int32, r * 0.35,
                     Color(r: 200, g: 200, b: 255, a: uint8(80 + sin(t * 4.5) * 30)))
      # Dim center dot (almost invisible, ghost-like)
      drawCircle(Vector2(x: cx, y: cy), r * 0.14,
                Color(r: 240, g: 240, b: 255, a: 180))
      # Tiny eyes, subtle tell distinguishing the real phantom from clones
      drawCircle(Vector2(x: cx - r * 0.18'f32, y: cy - r * 0.20'f32), r * 0.07'f32,
                Color(r: 255, g: 255, b: 255, a: 190))
      drawCircle(Vector2(x: cx + r * 0.18'f32, y: cy - r * 0.20'f32), r * 0.07'f32,
                Color(r: 255, g: 255, b: 255, a: 190))
      # Trailing fade ring
      let fadeRing = sin(t * 3.0) * 8 + 12
      drawCircleLines(cx.int32, cy.int32, r + fadeRing,
                     Color(r: 150, g: 150, b: 255, a: 60))
      # Draw fake clones, blue-shifted so sharp players can eventually distinguish them
      for clonePos in enemy.clonePositions:
        let cloneAlpha = uint8((sin(t * 5.0) * 0.5 + 0.5) * 100)
        drawCircle(Vector2(x: clonePos.x, y: clonePos.y), r * 0.7,
                  Color(r: uint8(max(0, enemy.color.r.int - 20)),
                        g: enemy.color.g,
                        b: uint8(min(255, enemy.color.b.int + 60)),
                        a: cloneAlpha))
        drawCircleLines(clonePos.x.int32, clonePos.y.int32, r * 0.7,
                       Color(r: 200, g: 200, b: 255, a: uint8(cloneAlpha.float32 * 0.6)))

    of etMage:
      let t  = getTime()
      let cx = enemy.pos.x
      # Gentle vertical bob
      let cy = enemy.pos.y + sin(t * 2.2) * 3.5
      let r  = enemy.radius

      # Colours
      let bodyCol   = enemy.color                                          # base purple
      let robeCol   = Color(r: bodyCol.r div 2, g: bodyCol.g div 2, b: bodyCol.b div 2, a: 255)
      let glowCol   = Color(r: uint8(min(255, bodyCol.r.int + 60)), g: uint8(min(255, bodyCol.g.int + 80)), b: 255, a: 180)
      let accentCol = Color(r: 220, g: 170, b: 255, a: 255)  # lavender highlight
      let orbCol    = Color(r: 160, g: 255, b: 220, a: 255)  # teal orb

      # Outer magical aura
      let auraPulse = sin(t * 3.0) * 0.4 + 0.6
      drawCircle(Vector2(x: cx, y: cy), r + 16 + auraPulse * 5,
                Color(r: glowCol.r, g: glowCol.g, b: glowCol.b, a: uint8(22 * auraPulse)))
      drawCircle(Vector2(x: cx, y: cy), r + 9 + auraPulse * 3,
                Color(r: glowCol.r, g: glowCol.g, b: glowCol.b, a: uint8(38 * auraPulse)))

      # Ground magic circle, drawn before robe body so it appears as a floor projection
      let circleRot = float32(-t * 0.6)
      let cgr = r * 1.35'f32
      let cgy = cy + r * 0.5'f32
      for i in 0..<6:
        let ca0 = i.float32       * PI / 3.0'f32 + circleRot
        let ca1 = (i + 1).float32 * PI / 3.0'f32 + circleRot
        drawLine(
          Vector2(x: cx + cos(ca0) * cgr,        y: cgy + sin(ca0) * cgr * 0.28'f32),
          Vector2(x: cx + cos(ca1) * cgr,        y: cgy + sin(ca1) * cgr * 0.28'f32),
          1, Color(r: glowCol.r, g: glowCol.g, b: glowCol.b, a: 35))
        drawLine(
          Vector2(x: cx, y: cgy),
          Vector2(x: cx + cos(ca0) * cgr * 0.6'f32, y: cgy + sin(ca0) * cgr * 0.28'f32 * 0.6'f32),
          1, Color(r: glowCol.r, g: glowCol.g, b: glowCol.b, a: 25))

      # Robe body (filled circle, slightly larger at bottom)
      # Bottom robe hem, slightly wider oval hint via two offset circles
      drawCircle(Vector2(x: cx, y: cy + r * 0.15), r * 0.88, robeCol)
      # Main body
      drawCircle(Vector2(x: cx, y: cy), r, bodyCol)
      # Robe hem dark edge (no white, dark tinted border)
      drawCircleLines(cx.int32, cy.int32, r,
                     Color(r: robeCol.r, g: robeCol.g, b: robeCol.b, a: 200))

      # Pointy wizard hat
      # Hat brim: a flattened circle behind the tip
      let brimY = cy - r * 0.62
      let brimW = r * 0.78
      let brimH = r * 0.18
      # Draw brim as a thin filled ellipse using two triangles
      for i in 0..<8:
        let a0 = i.float32       * PI / 4.0
        let a1 = (i + 1).float32 * PI / 4.0
        drawTriangle(
          Vector2(x: cx,                                y: brimY),
          Vector2(x: cx + cos(a0) * brimW, y: brimY + sin(a0) * brimH),
          Vector2(x: cx + cos(a1) * brimW, y: brimY + sin(a1) * brimH),
          robeCol)
      # Hat cone: triangle pointing upward
      let hatTipX = cx + sin(t * 0.5) * r * 0.08   # slight sway
      let hatTipY = cy - r * 1.52
      let hatBL   = Vector2(x: cx - brimW * 0.72, y: brimY + brimH * 0.3)
      let hatBR   = Vector2(x: cx + brimW * 0.72, y: brimY + brimH * 0.3)
      let hatTip  = Vector2(x: hatTipX, y: hatTipY)
      drawTriangle(hatTip, hatBL, hatBR, bodyCol)
      # Hat dark border
      drawLine(hatTip, hatBL, 2, robeCol)
      drawLine(hatTip, hatBR, 2, robeCol)
      # Hat brim dark border
      for i in 0..<8:
        let a0 = i.float32       * PI / 4.0
        let a1 = (i + 1).float32 * PI / 4.0
        drawLine(
          Vector2(x: cx + cos(a0) * brimW, y: brimY + sin(a0) * brimH),
          Vector2(x: cx + cos(a1) * brimW, y: brimY + sin(a1) * brimH),
          2, robeCol)
      # Hat star badge, tiny 4-pointed star on the cone
      let badgeX = cx + (hatTipX - cx) * 0.45
      let badgeY = hatTipY + (brimY - hatTipY) * 0.42
      let bs = r * 0.11
      for i in 0..<4:
        let a = i.float32 * PI / 2.0 + t * 0.8
        drawLine(Vector2(x: badgeX - cos(a) * bs, y: badgeY - sin(a) * bs),
                 Vector2(x: badgeX + cos(a) * bs, y: badgeY + sin(a) * bs),
                 2, Color(r: 255, g: 240, b: 80, a: 230))

      # Staff (orbiting, held to the side)
      let staffAngle  = -PI * 0.30 + sin(t * 1.1) * 0.12   # mostly up-right, gentle sway
      let staffLen    = r * 1.55
      let staffRootX  = cx + cos(staffAngle + PI) * r * 0.35
      let staffRootY  = cy + sin(staffAngle + PI) * r * 0.35
      let staffTipX   = staffRootX + cos(staffAngle) * staffLen
      let staffTipY   = staffRootY + sin(staffAngle) * staffLen
      # Shaft, two-tone: dark base with bright highlight offset
      drawLine(Vector2(x: staffRootX, y: staffRootY),
               Vector2(x: staffTipX,  y: staffTipY), 4, robeCol)
      drawLine(Vector2(x: staffRootX - 1, y: staffRootY - 1),
               Vector2(x: staffTipX  - 1, y: staffTipY  - 1), 2, accentCol)
      # Orb at tip, teal glowing sphere
      let orbPulse = sin(t * 4.5) * 0.35 + 0.65
      drawCircle(Vector2(x: staffTipX, y: staffTipY), r * 0.19 + orbPulse * 2,
                Color(r: orbCol.r, g: orbCol.g, b: orbCol.b, a: uint8(60 * orbPulse)))
      drawCircle(Vector2(x: staffTipX, y: staffTipY), r * 0.16, orbCol)
      drawCircle(Vector2(x: staffTipX - r * 0.04, y: staffTipY - r * 0.04),
                r * 0.06, Color(r: 255, g: 255, b: 255, a: 200))  # specular

      #  3 Orbiting arcane runes
      for i in 0..2:
        let runeAngle = t * 1.8 + i.float32 * (PI * 2.0 / 3.0)
        let runeDist  = r + 14
        let rx = cx + cos(runeAngle) * runeDist
        let ry = cy + sin(runeAngle) * runeDist
        # Rune glyph: small 3-line asterisk
        let rs = r * 0.10
        for j in 0..<3:
          let ra = runeAngle + j.float32 * PI / 3.0
          drawLine(Vector2(x: rx - cos(ra) * rs, y: ry - sin(ra) * rs),
                   Vector2(x: rx + cos(ra) * rs, y: ry + sin(ra) * rs),
                   2, accentCol)
        # Glow dot behind rune
        drawCircle(Vector2(x: rx, y: ry), r * 0.08,
                  Color(r: glowCol.r, g: glowCol.g, b: glowCol.b, a: 120))

      # Rising magic sparks
      for i in 0..3:
        let pt   = t * 1.2 + i.float32 * 1.57
        let age  = pt mod 2.4         # 0..2.4 s lifespan
        let frac = age / 2.4
        let spX  = cx + sin(pt * 2.3 + i.float32) * r * 0.55
        let spY  = cy - r * 0.3 - frac * r * 1.2
        let spA  = uint8((1.0 - frac) * 180)
        drawCircle(Vector2(x: spX, y: spY), r * 0.06 * (1.0 - frac * 0.5),
                  Color(r: orbCol.r, g: orbCol.g, b: orbCol.b, a: spA))

      # Eyes (two small bright dots on the body)
      let eyeY   = cy - r * 0.15
      let eyeOff = r * 0.22
      drawCircle(Vector2(x: cx - eyeOff, y: eyeY), r * 0.09,
                Color(r: 255, g: 240, b: 80, a: 240))
      drawCircle(Vector2(x: cx + eyeOff, y: eyeY), r * 0.09,
                Color(r: 255, g: 240, b: 80, a: 240))
      # Pupil dots
      drawCircle(Vector2(x: cx - eyeOff, y: eyeY), r * 0.04,
                Color(r: 60, g: 20, b: 80, a: 255))
      drawCircle(Vector2(x: cx + eyeOff, y: eyeY), r * 0.04,
                Color(r: 60, g: 20, b: 80, a: 255))

      # Casting charge indicator
      if enemy.shootTimer > 2.0:
        let chargeGlow = sin((enemy.shootTimer - 2.0) * 10.0) * 0.5 + 0.5
        drawCircleLines(cx.int32, cy.int32, r + 7,
                       Color(r: orbCol.r, g: orbCol.g, b: orbCol.b, a: uint8(160 * chargeGlow)))

    of etEnvironment:
      discard  # Environmental objects have no draw logic here

# --- Shared attack-warning telegraph vocabulary -----------------------------
# Every telegraph derives its fade, pulse and danger build-up the SAME way, so
# the whole warning system reads as one visual language. Branches still pick
# their own shapes and per-archetype colours (red = laser, orange = dash,
# purple = teleport, green = summon, yellow = lightning), but the *timing* of
# alpha and intensity is standardized through these helpers instead of being
# hand-recomputed per branch.

proc warningPulse(): float32 {.inline.} =
  ## Shared "breathing" pulse used so telegraphs feel alive. Range ~5..15.
  sin(getTime() * 20.0).float32 * 5.0 + 10.0

proc fadeAlpha(warning: AttackWarning): uint8 {.inline.} =
  ## Telegraph that fades OUT as it expires (brightest when fresh). The default
  ## for most enemy/boss markers.
  uint8((warning.lifetime / warning.maxLifetime) * 200.0)

proc warningProgress(warning: AttackWarning): float32 {.inline.} =
  ## 0.0 when the warning appears, 1.0 the instant it fires. The clock for
  ## telegraphs that ramp UP (reticles closing in, impact urgency rising).
  1.0'f32 - warning.lifetime / warning.maxLifetime

proc rampAlpha(warning: AttackWarning, base, span: float32,
               maxA: float32 = 255.0'f32): uint8 {.inline.} =
  ## Intensity that grows as the strike nears: base + progress*span, clamped.
  ## Standardizes the shared "danger builds toward impact" ramp (meteors,
  ## reticles, tesla strikes, arc beams, the ricochet telegraph).
  uint8(clamp(base + warningProgress(warning) * span, 0.0'f32, maxA))

proc drawMeteorWarning*(impact, source: Vector2f, radius: float32,
                        baseCol: Color, progress: float32,
                        blastRadius: float32 = 0.0'f32) =
  ## The single, shared incoming-meteorite telegraph used by EVERY meteor: the
  ## boss bapMeteor warning columns AND the real Meteorite rocks (etMage and the
  ## boss signature modes). `source` is the off-screen entry point, so the streak
  ## and arrowhead drawn from source->impact point along the rock's true travel
  ## direction. `progress` is 0 when the warning appears, 1 at impact.
  ##
  ## `blastRadius > 0` marks a rock that EXPLODES on contact with the ground
  ## (splash damage, e.g. boss-3's rocks). The telegraph then also draws the
  ## ground blast AoE in hot red so an exploding rock reads instantly different
  ## from a direct-hit one and the player knows how much room to clear.
  let pulse = warningPulse()
  let t = getTime()

  # Travel direction: from where the rock enters toward where it lands.
  var dir = (impact - source).normalize()
  if dir.x == 0 and dir.y == 0: dir = newVector2f(0, 1)   # default: straight down
  let perp = newVector2f(-dir.y, dir.x)
  let fromDir = newVector2f(-dir.x, -dir.y)

  let urgency = uint8(clamp(60.0'f32 + progress * 165.0'f32, 0.0'f32, 225.0'f32))
  let ringR = max(radius, 9.0'f32)

  # 1) SHORT incoming streak. Its length scales with the rock's size (bigger rock
  #    -> longer, heavier streak) and is never longer than the real spawn
  #    distance. A tapering dashed line leading into the impact from the source
  #    side = the direction the rock is coming from.
  let srcDist = (impact - source).length()
  let streakLen = min(95.0'f32 + radius * 4.0'f32, srcDist)
  const segs = 7
  for s in 0 ..< segs:
    let f0 = s.float32 / segs.float32
    let f1 = (s.float32 + 0.6'f32) / segs.float32          # gap after each dash
    # Bold, bright dashes with a high floor so the whole tail reads clearly
    # instead of fading toward the source.
    let a = uint8(clamp((0.7'f32 + 0.3'f32 * (1.0'f32 - f0)) * 255.0'f32,
                        0.0'f32, 255.0'f32))
    drawLine(Vector2(x: impact.x + fromDir.x * streakLen * f0,
                     y: impact.y + fromDir.y * streakLen * f0),
             Vector2(x: impact.x + fromDir.x * streakLen * f1,
                     y: impact.y + fromDir.y * streakLen * f1),
             2.0'f32 + radius * 0.05'f32,
             Color(r: baseCol.r, g: baseCol.g, b: baseCol.b, a: a))

  # 2) Arrowhead at the impact pointing the way the rock travels (scales w/ size).
  let headLen = 12.0'f32 + radius * 0.45'f32
  let wing = headLen * 0.6'f32
  drawLine(Vector2(x: impact.x, y: impact.y),
           Vector2(x: impact.x - dir.x * headLen + perp.x * wing,
                   y: impact.y - dir.y * headLen + perp.y * wing),
           2.5'f32, Color(r: 255, g: 225, b: 170, a: urgency))
  drawLine(Vector2(x: impact.x, y: impact.y),
           Vector2(x: impact.x - dir.x * headLen - perp.x * wing,
                   y: impact.y - dir.y * headLen - perp.y * wing),
           2.5'f32, Color(r: 255, g: 225, b: 170, a: urgency))

  # 3) Converging ring tightening onto the landing spot as impact nears.
  let convR = ringR + (1.0'f32 - progress) * (22.0'f32 + radius * 1.2'f32)
  drawCircleLines(impact.x.int32, impact.y.int32, convR,
                 Color(r: baseCol.r, g: baseCol.g, b: baseCol.b,
                       a: uint8(120.0'f32 * (1.0'f32 - progress))))

  # 4) Impact zone: pulsing target ring + center dot mark the exact landing point.
  let impactR = ringR + pulse * 0.35'f32
  drawCircleLines(impact.x.int32, impact.y.int32, impactR,
                 Color(r: baseCol.r, g: baseCol.g, b: baseCol.b, a: urgency))
  drawCircle(Vector2(x: impact.x, y: impact.y), 3.0'f32 + pulse * 0.22'f32,
            Color(r: 255, g: 190, b: 90, a: urgency))

  # 5) EXPLOSIVE rocks: telegraph the ground blast AoE so it reads as clearly
  #    more dangerous than a direct-hit rock. A breathing dashed red danger ring
  #    at the TRUE blast radius, a faint red fill, and inward hazard ticks.
  if blastRadius > 0.0'f32:
    let hotA = uint8(clamp(70.0'f32 + progress * 150.0'f32, 0.0'f32, 220.0'f32))
    let br = blastRadius * (1.0'f32 + sin(t * 6.0'f32) * 0.03'f32)   # subtle breathe
    drawCircle(Vector2(x: impact.x, y: impact.y), br,
               Color(r: 255, g: 40, b: 0, a: uint8(hotA.float32 * 0.12'f32)))
    const dashes = 22
    let spin = t * 0.6'f32
    for d in 0 ..< dashes:
      if d mod 2 == 1: continue                                      # every other = gap
      let a0 = d.float32 / dashes.float32 * (PI * 2.0'f32) + spin
      let a1 = (d.float32 + 0.85'f32) / dashes.float32 * (PI * 2.0'f32) + spin
      drawLine(Vector2(x: impact.x + cos(a0) * br, y: impact.y + sin(a0) * br),
               Vector2(x: impact.x + cos(a1) * br, y: impact.y + sin(a1) * br),
               2.5'f32, Color(r: 255, g: 70, b: 20, a: hotA))
    for k in 0 ..< 8:                                               # inward hazard ticks
      let a = k.float32 * (PI / 4.0'f32) + spin
      drawLine(Vector2(x: impact.x + cos(a) * br, y: impact.y + sin(a) * br),
               Vector2(x: impact.x + cos(a) * (br - 9.0'f32),
                       y: impact.y + sin(a) * (br - 9.0'f32)),
               2.0'f32, Color(r: 255, g: 130, b: 50, a: hotA))

proc drawAttackWarning*(warning: AttackWarning) =
  let alpha = fadeAlpha(warning)
  let pulse = warningPulse()

  case warning.attackType
  of awtCross:
    # Draw cross warning pattern - matches actual laser size
    let armLength = 100.0 + pulse  # Reduced from 180 to match laser
    drawLine(Vector2(x: warning.pos.x - armLength, y: warning.pos.y),
            Vector2(x: warning.pos.x + armLength, y: warning.pos.y), 6,
            Color(r: 255, g: 0, b: 0, a: alpha))
    drawLine(Vector2(x: warning.pos.x, y: warning.pos.y - armLength),
            Vector2(x: warning.pos.x, y: warning.pos.y + armLength), 6,
            Color(r: 255, g: 0, b: 0, a: alpha))
    # Add inner glow
    drawLine(Vector2(x: warning.pos.x - armLength, y: warning.pos.y),
            Vector2(x: warning.pos.x + armLength, y: warning.pos.y), 2,
            Color(r: 255, g: 150, b: 0, a: alpha))
    drawLine(Vector2(x: warning.pos.x, y: warning.pos.y - armLength),
            Vector2(x: warning.pos.x, y: warning.pos.y + armLength), 2,
            Color(r: 255, g: 150, b: 0, a: alpha))
  of awtMeteor:
    # Boss bapMeteor columns route through the one shared meteor telegraph.
    # targetPos holds the off-screen spawn point, so the streak + arrowhead point
    # along the rock's true travel direction. Falls back to "straight above" for
    # any meteor warning that didn't record an explicit spawn (targetPos unset).
    let spawn = if warning.targetPos.x == 0 and warning.targetPos.y == 0:
                  newVector2f(warning.pos.x, 0.0'f32)
                else: warning.targetPos
    let baseCol = if warning.overrideColor.a > 0: warning.overrideColor
                  else: Color(r: 255, g: 130, b: 30, a: 255)
    drawMeteorWarning(warning.pos, spawn, warning.bulletRadius, baseCol,
                      warningProgress(warning))

  of awtBurst:
    # Draw circular burst warning (generic / unused fallback, kept for safety)
    drawCircleLines(warning.pos.x.int32, warning.pos.y.int32, 50.0 + pulse,
                   Color(r: 255, g: 100, b: 0, a: alpha))
    drawCircleLines(warning.pos.x.int32, warning.pos.y.int32, 70.0 + pulse,
                   Color(r: 255, g: 100, b: 0, a: (alpha div 2).uint8))
  of awtFake:
    # Generic fallback fake, kept for safety
    drawCircleLines(warning.pos.x.int32, warning.pos.y.int32, 40.0 + pulse,
                   Color(r: 255, g: 255, b: 0, a: alpha))
    drawText("!", (warning.pos.x - 8).int32, (warning.pos.y - 12).int32, 24,
            Color(r: 255, g: 255, b: 0, a: alpha))

  # Triangle
  of awtTriangleDash:
    # Magenta starburst flash, very short duration, directional cue at launch point
    let cx = warning.pos.x; let cy = warning.pos.y
    let r = 18.0 + pulse * 0.8
    for i in 0..<8:
      let a = i.float32 * PI / 4.0
      drawLine(Vector2(x: cx, y: cy),
               Vector2(x: cx + cos(a) * r, y: cy + sin(a) * r),
               3, Color(r: 255'u8, g: 80'u8, b: 255'u8, a: alpha))
    drawCircle(Vector2(x: cx, y: cy), 6.0,
               Color(r: 255'u8, g: 180'u8, b: 255'u8, a: alpha))

  # Hexagon
  of awtHexTeleport:
    # Purple contracting hexagon, shows EXACTLY where the hex will appear
    let cx = warning.pos.x; let cy = warning.pos.y
    # Outer hex shrinks inward as timer counts down (progress = 0->1 as lifetime->0)
    let progress = warningProgress(warning)
    let outerR = 55.0 - progress * 20.0 + pulse * 0.5
    let innerR = outerR * 0.55
    for i in 0..<6:
      let a0 = i.float32 * PI / 3.0
      let a1 = (i + 1).float32 * PI / 3.0
      drawLine(Vector2(x: cx + cos(a0) * outerR, y: cy + sin(a0) * outerR),
               Vector2(x: cx + cos(a1) * outerR, y: cy + sin(a1) * outerR),
               4, Color(r: 180'u8, g: 0'u8, b: 255'u8, a: alpha))
      drawLine(Vector2(x: cx + cos(a0) * innerR, y: cy + sin(a0) * innerR),
               Vector2(x: cx + cos(a1) * innerR, y: cy + sin(a1) * innerR),
               2, Color(r: 220'u8, g: 80'u8, b: 255'u8, a: (alpha div 2).uint8))
    # Spokes
    for i in 0..<6:
      let a = i.float32 * PI / 3.0 + PI / 6.0
      drawLine(Vector2(x: cx + cos(a) * innerR, y: cy + sin(a) * innerR),
               Vector2(x: cx + cos(a) * outerR,  y: cy + sin(a) * outerR),
               1, Color(r: 200'u8, g: 50'u8, b: 255'u8, a: (alpha div 2).uint8))
    # Center dot
    drawCircle(Vector2(x: cx, y: cy), 5.0 + pulse * 0.3,
               Color(r: 255'u8, g: 150'u8, b: 255'u8, a: alpha))

  # Trickster
  of awtTricksterDecoy:
    # Bright orange diamond + "?", looks threatening but it's a lie
    let cx = warning.pos.x; let cy = warning.pos.y
    let sz = 30.0 + pulse * 0.6
    # Outer glow circle
    drawCircleLines(cx.int32, cy.int32, sz + 8,
                   Color(r: 255'u8, g: 140'u8, b: 0'u8, a: (alpha div 2).uint8))
    # Diamond outline
    drawLine(Vector2(x: cx,      y: cy - sz), Vector2(x: cx + sz, y: cy),
             3, Color(r: 255'u8, g: 140'u8, b: 0'u8, a: alpha))
    drawLine(Vector2(x: cx + sz, y: cy),      Vector2(x: cx,      y: cy + sz),
             3, Color(r: 255'u8, g: 140'u8, b: 0'u8, a: alpha))
    drawLine(Vector2(x: cx,      y: cy + sz), Vector2(x: cx - sz, y: cy),
             3, Color(r: 255'u8, g: 140'u8, b: 0'u8, a: alpha))
    drawLine(Vector2(x: cx - sz, y: cy),      Vector2(x: cx,      y: cy - sz),
             3, Color(r: 255'u8, g: 140'u8, b: 0'u8, a: alpha))
    # "?" text, hints it might be a trick
    let qw = measureText("?", 22)
    drawText("?", (cx - qw / 2).int32, (cy - 11).int32, 22,
             Color(r: 255'u8, g: 200'u8, b: 0'u8, a: alpha))

  # Trickster real destination
  of awtTricksterReal:
    # Tiny, dim magenta dot, easy to miss unless you're looking for it
    let cx = warning.pos.x; let cy = warning.pos.y
    let subtleAlpha = uint8(alpha.float32 * 0.35)  # Much dimmer than decoy
    let r = 8.0 + pulse * 0.2
    drawCircleLines(cx.int32, cy.int32, r,
                   Color(r: 220'u8, g: 0'u8, b: 180'u8, a: subtleAlpha))
    drawCircle(Vector2(x: cx, y: cy), 3.0,
               Color(r: 255'u8, g: 80'u8, b: 220'u8, a: subtleAlpha))

  # Phantom arrive
  of awtPhantomArrive:
    # Indigo/blue concentric portal rings, unambiguously "something is appearing here"
    let cx = warning.pos.x; let cy = warning.pos.y
    let progress = warningProgress(warning)
    # Rings converge inward as the phantom approaches
    for ring in 0..2:
      let baseR = 55.0 - ring.float32 * 14.0
      let r = baseR - progress * 18.0 + pulse * 0.4
      let ringAlpha = uint8(alpha.float32 * (1.0 - ring.float32 * 0.28))
      drawCircleLines(cx.int32, cy.int32, r,
                     Color(r: 60'u8, g: 80'u8, b: 255'u8, a: ringAlpha))
    # Rotating 4-petal cross inside the rings
    let crossLen = 18.0 + pulse * 0.3
    let rot = getTime() * 3.0
    for i in 0..<4:
      let a = rot + i.float32 * PI / 2.0
      drawLine(Vector2(x: cx, y: cy),
               Vector2(x: cx + cos(a) * crossLen, y: cy + sin(a) * crossLen),
               2, Color(r: 130'u8, g: 160'u8, b: 255'u8, a: alpha))
    # Center core
    drawCircle(Vector2(x: cx, y: cy), 5.0,
               Color(r: 200'u8, g: 220'u8, b: 255'u8, a: alpha))

  # Phantom clone / shoot origin
  of awtPhantomClone:
    # Ghostly white/teal crosshair, marks each bullet spawn point
    let cx = warning.pos.x; let cy = warning.pos.y
    let sz = 22.0 + pulse * 0.4
    let gap = 6.0  # Gap at center
    # Four arms of the crosshair
    for i in 0..<4:
      let a = i.float32 * PI / 2.0
      drawLine(Vector2(x: cx + cos(a) * gap,  y: cy + sin(a) * gap),
               Vector2(x: cx + cos(a) * sz,   y: cy + sin(a) * sz),
               2, Color(r: 180'u8, g: 255'u8, b: 240'u8, a: alpha))
    # Diagonal accent lines (x) at half opacity
    for i in 0..<4:
      let a = i.float32 * PI / 2.0 + PI / 4.0
      let diagLen = sz * 0.6
      drawLine(Vector2(x: cx + cos(a) * gap,     y: cy + sin(a) * gap),
               Vector2(x: cx + cos(a) * diagLen, y: cy + sin(a) * diagLen),
               1, Color(r: 180'u8, g: 255'u8, b: 240'u8, a: (alpha div 2).uint8))
    # Outer ring
    drawCircleLines(cx.int32, cy.int32, sz,
                   Color(r: 120'u8, g: 220'u8, b: 210'u8, a: (alpha div 2).uint8))

  of awtBossLaser:
    # Boss laser warning with accurate beam visualization
    # Shows exactly where each laser beam will appear
    # Different drawing based on pattern type
    let isRadialPattern = warning.laserPattern in ["prismatic_cage", "laser_snipe"]

    for angle in warning.laserAngles:
      if isRadialPattern:
        # Radial pattern: Draw from boss center outward only
        let startX = warning.pos.x + cos(angle) * 40.0  # Start from boss center (small offset)
        let startY = warning.pos.y + sin(angle) * 40.0
        let endX = warning.pos.x + cos(angle) * warning.laserLength
        let endY = warning.pos.y + sin(angle) * warning.laserLength

        # Draw warning line (pulsing)
        let warningThickness = 8 + pulse * 0.3
        drawLine(
          Vector2(x: startX, y: startY),
          Vector2(x: endX, y: endY),
          warningThickness,
          Color(r: 255, g: 50, b: 0, a: alpha)
        )

        # Draw inner glow line
        drawLine(
          Vector2(x: startX, y: startY),
          Vector2(x: endX, y: endY),
          3,
          Color(r: 255, g: 200, b: 100, a: (alpha div 2).uint8)
        )

        # Draw danger markers along the beam path
        for i in 0..4:
          let markerDist = 40.0 + (warning.laserLength - 40.0) * (i.float32 / 4.0) * 0.7
          let markerX = warning.pos.x + cos(angle) * markerDist
          let markerY = warning.pos.y + sin(angle) * markerDist
          let markerSize = 6.0 + sin(getTime() * 15.0 + i.float32) * 2.0
          drawCircle(
            Vector2(x: markerX, y: markerY),
            markerSize,
            Color(r: 255, g: 0, b: 0, a: (alpha div 2).uint8)
          )
      else:
        # Cross pattern: Draw in both directions (extends through center)
        let startX = warning.pos.x + cos(angle) * (-warning.laserLength)
        let startY = warning.pos.y + sin(angle) * (-warning.laserLength)
        let endX = warning.pos.x + cos(angle) * warning.laserLength
        let endY = warning.pos.y + sin(angle) * warning.laserLength

        # Draw warning line (pulsing)
        let warningThickness = 8 + pulse * 0.3
        drawLine(
          Vector2(x: startX, y: startY),
          Vector2(x: endX, y: endY),
          warningThickness,
          Color(r: 255, g: 50, b: 0, a: alpha)
        )

        # Draw inner glow line
        drawLine(
          Vector2(x: startX, y: startY),
          Vector2(x: endX, y: endY),
          3,
          Color(r: 255, g: 200, b: 100, a: (alpha div 2).uint8)
        )

        # Draw danger markers along the beam path (both sides)
        for i in -2..2:
          if i == 0: continue  # Skip center
          let markerDist = warning.laserLength * (i.float32 / 2.0) * 0.7
          let markerX = warning.pos.x + cos(angle) * markerDist
          let markerY = warning.pos.y + sin(angle) * markerDist
          let markerSize = 6.0 + sin(getTime() * 15.0 + i.float32) * 2.0
          drawCircle(
            Vector2(x: markerX, y: markerY),
            markerSize,
            Color(r: 255, g: 0, b: 0, a: (alpha div 2).uint8)
          )

    # Draw central danger indicator at boss position
    let centralPulse = sin(getTime() * 12.0) * 0.3 + 0.7
    drawCircleLines(
      warning.pos.x.int32, warning.pos.y.int32,
      50.0 + pulse * 1.5,
      Color(r: 255, g: 0, b: 0, a: uint8(alpha.float32 * centralPulse))
    )
    drawCircleLines(
      warning.pos.x.int32, warning.pos.y.int32,
      70.0 + pulse * 1.5,
      Color(r: 255, g: 100, b: 0, a: uint8(alpha.float32 * centralPulse * 0.6))
    )

    # Draw "DANGER" text
    let dangerText = "LASER INCOMING"
    let textSize = 16
    let textWidth = measureText(dangerText, textSize.int32)
    drawText(
      dangerText,
      (warning.pos.x - textWidth / 2).int32,
      (warning.pos.y - 90).int32,
      textSize.int32,
      Color(r: 255, g: 255, b: 255, a: alpha)
    )

  of awtSatelliteLaser:
    # Draw warning for satellite laser that extends through target point
    # Calculate direction from satellite through target to edge
    let toTarget = (warning.targetPos - warning.pos).normalize()
    let angle = arctan2(toTarget.y, toTarget.x)

    # Calculate endpoint: extend far beyond target
    let maxDist = 2000.0  # Very long distance to ensure it reaches screen edge
    let endX = warning.pos.x + cos(angle) * maxDist
    let endY = warning.pos.y + sin(angle) * maxDist

    # Draw warning line from satellite through target
    let warningThickness = 10 + pulse * 0.5
    drawLine(
      Vector2(x: warning.pos.x, y: warning.pos.y),
      Vector2(x: endX, y: endY),
      warningThickness,
      Color(r: 255, g: 100, b: 0, a: alpha)
    )

    # Draw inner glow line
    drawLine(
      Vector2(x: warning.pos.x, y: warning.pos.y),
      Vector2(x: endX, y: endY),
      3,
      Color(r: 255, g: 200, b: 50, a: (alpha div 2).uint8)
    )

    # Draw pulsing danger markers along the beam path
    let markerCount = 8
    for i in 0..<markerCount:
      let markerDist = maxDist * (i.float32 / markerCount.float32)
      let markerX = warning.pos.x + cos(angle) * markerDist
      let markerY = warning.pos.y + sin(angle) * markerDist
      let markerSize = 8.0 + sin(getTime() * 15.0 + i.float32 * 0.8) * 3.0
      drawCircle(
        Vector2(x: markerX, y: markerY),
        markerSize,
        Color(r: 255, g: 50, b: 0, a: (alpha div 2).uint8)
      )

    # Draw target crosshair at the locked coordinates
    let targetSize = 20.0 + pulse * 0.8
    let targetAlpha = uint8((sin(getTime() * 12.0) * 0.3 + 0.7) * alpha.float32)

    # Crosshair lines
    drawLine(
      Vector2(x: warning.targetPos.x - targetSize, y: warning.targetPos.y),
      Vector2(x: warning.targetPos.x + targetSize, y: warning.targetPos.y),
      4,
      Color(r: 255, g: 0, b: 0, a: targetAlpha)
    )
    drawLine(
      Vector2(x: warning.targetPos.x, y: warning.targetPos.y - targetSize),
      Vector2(x: warning.targetPos.x, y: warning.targetPos.y + targetSize),
      4,
      Color(r: 255, g: 0, b: 0, a: targetAlpha)
    )

    # Target circle
    drawCircleLines(
      warning.targetPos.x.int32, warning.targetPos.y.int32,
      targetSize,
      Color(r: 255, g: 0, b: 0, a: targetAlpha)
    )
    drawCircleLines(
      warning.targetPos.x.int32, warning.targetPos.y.int32,
      targetSize * 1.5,
      Color(r: 255, g: 100, b: 0, a: (targetAlpha div 2).uint8)
    )

    # Warning text at target
    let warningText = "TARGET"
    let textSize = 14
    let textWidth = measureText(warningText, textSize.int32)
    drawText(
      warningText,
      (warning.targetPos.x - textWidth / 2).int32,
      (warning.targetPos.y - 35).int32,
      textSize.int32,
      Color(r: 255, g: 255, b: 255, a: alpha)
    )

  of awtTeleportWarning:
    # Teleport warning - shows where boss will appear
    let warningMode = warning.laserPattern  # Contains the teleport mode

    # Base pulsing circle for all teleport warnings
    drawCircleLines(warning.pos.x.int32, warning.pos.y.int32, 40.0 + pulse * 2,
                   Color(r: 150, g: 100, b: 255, a: alpha))
    drawCircleLines(warning.pos.x.int32, warning.pos.y.int32, 60.0 + pulse,
                   Color(r: 150, g: 100, b: 255, a: (alpha div 2).uint8))

    # Mode-specific visual effects
    case warningMode
    of "afterimage_burst":
      # Ghost shimmer effect
      drawCircleLines(warning.pos.x.int32, warning.pos.y.int32, 30.0 + pulse * 1.5,
                     Color(r: 100, g: 200, b: 255, a: (alpha div 2).uint8))
      # Ghost glyph
      drawText("*", (warning.pos.x - 5).int32, (warning.pos.y - 8).int32, 20,
              Color(r: 150, g: 100, b: 255, a: alpha))
    of "triple_clone", "dimensional_chaos", "omega_blink":
      # Multiple expanding rings for clone/chaos modes
      for i in 1..3:
        let ringRadius = 35.0 + pulse + (i.float32 * 15.0)
        let ringAlpha = uint8((alpha.float32 * (1.0 - i.float32 * 0.25)).uint8.clamp(0, 255))
        drawCircleLines(warning.pos.x.int32, warning.pos.y.int32, ringRadius,
                       Color(r: 200, g: 100, b: 255, a: ringAlpha))
    of "dimensional_rift":
      let cx = warning.pos.x; let cy = warning.pos.y
      let t = getTime()
      let progress = warningProgress(warning)  # 0->1 as warning expires

      # Tear: a jagged fracture line across the rift centre
      # Two counter-rotating halves pull apart as the rift opens
      let tearLen  = 38.0'f32 + progress * 22.0'f32
      let tearGap  = 3.0'f32  + progress * 6.0'f32   # gap widens as it tears
      let tearTilt = sin(t * 1.8'f32) * 0.25'f32      # subtle organic wobble
      let tearA    = tearTilt
      # Left half
      drawLine(Vector2(x: cx - cos(tearA) * tearGap,  y: cy - sin(tearA) * tearGap),
               Vector2(x: cx - cos(tearA) * tearLen,  y: cy - sin(tearA) * tearLen),
               4, Color(r: 0'u8, g: 220'u8, b: 255'u8, a: alpha))
      drawLine(Vector2(x: cx - cos(tearA) * tearGap,  y: cy - sin(tearA) * tearGap),
               Vector2(x: cx - cos(tearA) * tearLen,  y: cy - sin(tearA) * tearLen),
               2, Color(r: 220'u8, g: 255'u8, b: 255'u8, a: uint8(alpha.float32 * 0.6'f32)))
      # Right half
      drawLine(Vector2(x: cx + cos(tearA) * tearGap,  y: cy + sin(tearA) * tearGap),
               Vector2(x: cx + cos(tearA) * tearLen,  y: cy + sin(tearA) * tearLen),
               4, Color(r: 0'u8, g: 220'u8, b: 255'u8, a: alpha))
      drawLine(Vector2(x: cx + cos(tearA) * tearGap,  y: cy + sin(tearA) * tearGap),
               Vector2(x: cx + cos(tearA) * tearLen,  y: cy + sin(tearA) * tearLen),
               2, Color(r: 220'u8, g: 255'u8, b: 255'u8, a: uint8(alpha.float32 * 0.6'f32)))

      # Three concentric distortion rings that breathe
      for ri in 0..<3:
        let baseR   = 22.0'f32 + ri.float32 * 18.0'f32
        let breathe = sin(t * (3.5'f32 - ri.float32 * 0.9'f32) + ri.float32 * 1.1'f32) * 4.0'f32
        let ringR   = baseR + breathe + progress * 10.0'f32
        let rAlpha  = uint8(alpha.float32 * (1.0'f32 - ri.float32 * 0.28'f32))
        # Alternate purple / cyan per ring
        let ringCol = if ri mod 2 == 0:
          Color(r: 180'u8, g: 60'u8,  b: 255'u8, a: rAlpha)
        else:
          Color(r: 40'u8,  g: 200'u8, b: 255'u8, a: rAlpha)
        drawCircleLines(cx.int32, cy.int32, ringR, ringCol)
        # Inner bright core ring
        drawCircleLines(cx.int32, cy.int32, ringR * 0.75'f32,
                       Color(r: ringCol.r, g: ringCol.g, b: ringCol.b,
                             a: uint8(rAlpha.float32 * 0.4'f32)))

      # 12 orbiting shards on two counter-rotating layers
      for i in 0..<12:
        let layer    = i mod 2
        let spin     = if layer == 0: t * 2.2'f32 else: -(t * 1.5'f32)
        let baseAng  = i.float32 * (PI * 2.0'f32 / 12.0'f32) + spin
        let orbitR   = if layer == 0: 32.0'f32 + pulse * 0.6'f32
                       else:          20.0'f32 + pulse * 0.4'f32
        let sx = cx + cos(baseAng) * orbitR
        let sy = cy + sin(baseAng) * orbitR
        let shardSize = if layer == 0: 5.0'f32 + progress * 3.0'f32
                        else:          3.0'f32 + progress * 2.0'f32
        let sCol = if i mod 3 == 0:
          Color(r: 220'u8, g: 80'u8,  b: 255'u8, a: alpha)
        elif i mod 3 == 1:
          Color(r: 60'u8,  g: 210'u8, b: 255'u8, a: alpha)
        else:
          Color(r: 160'u8, g: 40'u8,  b: 255'u8, a: uint8(alpha.float32 * 0.7'f32))
        drawCircle(Vector2(x: sx, y: sy), shardSize, sCol)
        # Thin trailing spoke from centre to each outer-layer shard
        if layer == 0:
          drawLine(Vector2(x: cx, y: cy), Vector2(x: sx, y: sy),
                  1, Color(r: sCol.r, g: sCol.g, b: sCol.b, a: uint8(alpha.float32 * 0.25'f32)))

      # Void core, deep black circle with a glowing rim
      let coreR = 9.0'f32 + progress * 5.0'f32 + sin(t * 8.0'f32) * 1.5'f32
      drawCircle(Vector2(x: cx, y: cy), coreR,
                Color(r: 10'u8, g: 0'u8, b: 30'u8, a: uint8(alpha.float32 * 0.92'f32)))
      drawCircleLines(cx.int32, cy.int32, coreR,
                     Color(r: 200'u8, g: 100'u8, b: 255'u8, a: alpha))
      drawCircleLines(cx.int32, cy.int32, coreR + 3.0'f32,
                     Color(r: 80'u8, g: 220'u8, b: 255'u8, a: uint8(alpha.float32 * 0.5'f32)))
    of "chaos_blink", "reality_shift":
      # Chaotic swirl pattern
      for i in 0..11:
        let angle = i.float32 * (PI * 2.0 / 12.0) + getTime() * 3.0
        let swrlX = warning.pos.x + cos(angle) * (35.0 + pulse)
        let swrlY = warning.pos.y + sin(angle) * (35.0 + pulse)
        let chaosAlpha = uint8((alpha.float32 * (0.5 + sin(getTime() * 10.0 + i.float32) * 0.5)).uint8.clamp(0, 255))
        drawCircle(Vector2(x: swrlX, y: swrlY), 4.0 + pulse * 0.2,
                  Color(r: uint8(150 + rand(100)), g: uint8(100 + rand(100)),
                        b: uint8(150 + rand(100)), a: chaosAlpha))
    else:
      # Default warning pattern
      for i in 0..3:
        let angle = i.float32 * (PI / 2.0) + getTime()
        let sparkX = warning.pos.x + cos(angle) * (25.0 + pulse)
        let sparkY = warning.pos.y + sin(angle) * (25.0 + pulse)
        drawCircle(Vector2(x: sparkX, y: sparkY), 3.0,
                  Color(r: 150, g: 100, b: 255, a: alpha))

    # Center danger indicator
    let centerPulse = sin(getTime() * 15.0) * 0.3 + 0.7
    drawCircle(Vector2(x: warning.pos.x, y: warning.pos.y), 8.0 + pulse * centerPulse,
              Color(r: 255, g: 100, b: 200, a: uint8(alpha.float32 * centerPulse)))

  of awtSniperCharge, awtLaserPointer:
    # Red targeting reticle that fills in over the charge duration.
    # awtLaserPointer (boss snipe) shares this reticle: previously it produced a
    # "laser_pointer" string with no draw branch, so it silently fell through to
    # the generic else and rendered nothing. Merging the cases is the fix.
    let cx = warning.pos.x; let cy = warning.pos.y
    let progress = warningProgress(warning)
    let urgency = rampAlpha(warning, 60.0, 160.0, 200.0)
    # Outer ring shrinks as charge completes (sense of closing in)
    let outerR = 50.0 - progress * 20.0 + pulse * 0.4
    drawCircleLines(cx.int32, cy.int32, outerR,
                   Color(r: 220'u8, g: 0'u8, b: 0'u8, a: urgency))
    # Crosshair arms
    let crossLen = outerR * 0.65
    let innerGap = 5.0 + progress * 8.0
    for i in 0..<4:
      let a = i.float32 * PI / 2.0
      drawLine(Vector2(x: cx + cos(a) * innerGap,  y: cy + sin(a) * innerGap),
               Vector2(x: cx + cos(a) * crossLen,  y: cy + sin(a) * crossLen),
               2, Color(r: 255'u8, g: 0'u8, b: 0'u8, a: urgency))
    # Growing center dot
    let dotR = 3.0 + progress * 9.0
    drawCircle(Vector2(x: cx, y: cy), dotR,
               Color(r: 255'u8, g: 0'u8, b: 0'u8, a: urgency))

  of awtBossDash:
    # Full-path dashed arrow from the boss's current position to the computed
    # landing spot (stored in targetPos at warning-creation time).
    # This gives the player a clear read of exactly where the boss will end up.
    let cx = warning.pos.x; let cy = warning.pos.y
    let tx = warning.targetPos.x; let ty = warning.targetPos.y
    let dx = tx - cx;             let dy = ty - cy
    let dist = sqrt(dx * dx + dy * dy)
    if dist > 0.01:
      let nx = dx / dist; let ny = dy / dist  # unit direction
      let perpX = -ny;    let perpY = nx       # perpendicular

      # Dashed shaft, 6 segments, solid/gap alternating
      let segCount = 6
      for i in 0..<segCount:
        if i mod 2 == 0:
          let t0 = i.float32 / segCount.float32
          let t1 = (i.float32 + 0.75'f32) / segCount.float32
          drawLine(Vector2(x: cx + nx * dist * t0, y: cy + ny * dist * t0),
                   Vector2(x: cx + nx * dist * t1, y: cy + ny * dist * t1),
                   5, Color(r: 255'u8, g: 140'u8, b: 0'u8, a: alpha))

      # Arrowhead at the landing spot
      let headLen  = 20.0'f32 + pulse * 0.5'f32
      let headWide = 10.0'f32
      drawLine(Vector2(x: tx, y: ty),
               Vector2(x: tx - nx * headLen + perpX * headWide,
                       y: ty - ny * headLen + perpY * headWide),
               5, Color(r: 255'u8, g: 140'u8, b: 0'u8, a: alpha))
      drawLine(Vector2(x: tx, y: ty),
               Vector2(x: tx - nx * headLen - perpX * headWide,
                       y: ty - ny * headLen - perpY * headWide),
               5, Color(r: 255'u8, g: 140'u8, b: 0'u8, a: alpha))

      # Pulsing landing-zone circle at destination
      drawCircleLines(tx.int32, ty.int32, 18.0'f32 + pulse,
                     Color(r: 255'u8, g: 80'u8, b: 0'u8, a: alpha))
      drawCircleLines(tx.int32, ty.int32, 10.0'f32,
                     Color(r: 255'u8, g: 200'u8, b: 80'u8, a: (alpha div 2).uint8))

    # Origin ring at boss position
    drawCircleLines(cx.int32, cy.int32, 16.0'f32 + pulse * 0.5'f32,
                   Color(r: 255'u8, g: 180'u8, b: 0'u8, a: alpha))

  of awtBossBurst:
    # Fanned lines radiating toward the locked aim direction
    let cx = warning.pos.x; let cy = warning.pos.y
    let toTarget = warning.targetPos - warning.pos
    let dist = sqrt(toTarget.x * toTarget.x + toTarget.y * toTarget.y)
    let baseAngle = if dist > 0.01: arctan2(toTarget.y, toTarget.x) else: 0.0
    let fanHalf = PI / 4.0
    for i in 0..<5:
      let t = i.float32 / 4.0
      let a = baseAngle - fanHalf + t * fanHalf * 2.0
      let lineLen = 35.0 + pulse
      drawLine(Vector2(x: cx, y: cy),
               Vector2(x: cx + cos(a) * lineLen, y: cy + sin(a) * lineLen),
               3, Color(r: 255'u8, g: 80'u8, b: 0'u8, a: alpha))
    drawCircle(Vector2(x: cx, y: cy), 6.0,
               Color(r: 255'u8, g: 140'u8, b: 0'u8, a: alpha))

  of awtBossWave:
    # Dashed fan lines toward locked aim direction (blue/purple tone)
    let cx = warning.pos.x; let cy = warning.pos.y
    let toTarget = warning.targetPos - warning.pos
    let dist = sqrt(toTarget.x * toTarget.x + toTarget.y * toTarget.y)
    let baseAngle = if dist > 0.01: arctan2(toTarget.y, toTarget.x) else: 0.0
    let fanHalf = PI / 3.0
    for i in 0..<5:
      let t = i.float32 / 4.0
      let a = baseAngle - fanHalf + t * fanHalf * 2.0
      let lineLen = 40.0 + pulse * 0.8
      for step in 0..<3:
        let s = step.float32 / 3.0
        let e = (step.float32 + 0.6) / 3.0
        drawLine(Vector2(x: cx + cos(a) * lineLen * s, y: cy + sin(a) * lineLen * s),
                 Vector2(x: cx + cos(a) * lineLen * e, y: cy + sin(a) * lineLen * e),
                 2, Color(r: 100'u8, g: 100'u8, b: 255'u8, a: alpha))
    drawCircle(Vector2(x: cx, y: cy), 6.0,
               Color(r: 150'u8, g: 100'u8, b: 255'u8, a: alpha))

  of awtBossCircle, awtBossSpiral:
    # Pulsing rings with tick marks, omnidirectional threat
    let cx = warning.pos.x; let cy = warning.pos.y
    let r1 = 30.0 + pulse * 1.5
    let r2 = 46.0 + pulse * 1.2
    drawCircleLines(cx.int32, cy.int32, r1, Color(r: 255'u8, g: 50'u8, b: 50'u8, a: alpha))
    drawCircleLines(cx.int32, cy.int32, r2,
                   Color(r: 255'u8, g: 80'u8, b: 0'u8, a: (alpha div 2).uint8))
    for i in 0..<8:
      let a = i.float32 * PI / 4.0
      drawLine(Vector2(x: cx + cos(a) * (r1 - 6), y: cy + sin(a) * (r1 - 6)),
               Vector2(x: cx + cos(a) * (r1 + 6), y: cy + sin(a) * (r1 + 6)),
               2, Color(r: 255'u8, g: 50'u8, b: 50'u8, a: alpha))

  of awtBossBarrage:
    # Ring with many radiating spokes, massive spray indicator
    let cx = warning.pos.x; let cy = warning.pos.y
    let r = 28.0 + pulse
    drawCircleLines(cx.int32, cy.int32, r, Color(r: 255'u8, g: 50'u8, b: 0'u8, a: alpha))
    for i in 0..<12:
      let a = i.float32 * PI / 6.0
      drawLine(Vector2(x: cx + cos(a) * r,        y: cy + sin(a) * r),
               Vector2(x: cx + cos(a) * (r + 14), y: cy + sin(a) * (r + 14)),
               2, Color(r: 255'u8, g: 80'u8, b: 0'u8, a: alpha))

  of awtBossPulse:
    # Three concentric pulsing rings, expanding shockwave cue
    let cx = warning.pos.x; let cy = warning.pos.y
    for ring in 0..<3:
      let r = 20.0 + ring.float32 * 18.0 + pulse * 0.7
      let ringAlpha = uint8(alpha.float32 * (1.0 - ring.float32 * 0.28))
      drawCircleLines(cx.int32, cy.int32, r,
                     Color(r: 200'u8, g: 50'u8, b: 255'u8, a: ringAlpha))

  of awtBossChain:
    # Rotating zigzag lightning spokes, chain lightning cue
    let cx = warning.pos.x; let cy = warning.pos.y
    let rot = getTime() * 2.0
    for i in 0..<4:
      let a = rot + i.float32 * PI / 2.0
      let mid = newVector2f(cx + cos(a) * (20.0 + pulse), cy + sin(a) * (20.0 + pulse))
      let tip = newVector2f(cx + cos(a + 0.35) * (38.0 + pulse), cy + sin(a + 0.35) * (38.0 + pulse))
      drawLine(Vector2(x: cx, y: cy), Vector2(x: mid.x, y: mid.y),
               2, Color(r: 255'u8, g: 255'u8, b: 100'u8, a: alpha))
      drawLine(Vector2(x: mid.x, y: mid.y), Vector2(x: tip.x, y: tip.y),
               2, Color(r: 255'u8, g: 255'u8, b: 100'u8, a: alpha))
    drawCircleLines(cx.int32, cy.int32, 14.0 + pulse * 0.4,
                   Color(r: 255'u8, g: 255'u8, b: 150'u8, a: alpha))

  of awtBossSummon:
    # Spinning summoning circle with 6 rune-spokes and orbiting dots
    let cx = warning.pos.x; let cy = warning.pos.y
    let rot = getTime() * 2.0
    let outerR = 40.0 + pulse
    drawCircleLines(cx.int32, cy.int32, outerR,
                   Color(r: 100'u8, g: 255'u8, b: 80'u8, a: alpha))
    drawCircleLines(cx.int32, cy.int32, 24.0 + pulse * 0.5,
                   Color(r: 100'u8, g: 255'u8, b: 80'u8, a: (alpha div 2).uint8))
    for i in 0..<6:
      let a = rot + i.float32 * PI / 3.0
      drawLine(Vector2(x: cx, y: cy),
               Vector2(x: cx + cos(a) * outerR, y: cy + sin(a) * outerR),
               1, Color(r: 80'u8, g: 200'u8, b: 60'u8, a: alpha))
      drawCircle(Vector2(x: cx + cos(a) * outerR, y: cy + sin(a) * outerR), 4.0,
                 Color(r: 100'u8, g: 255'u8, b: 80'u8, a: alpha))

  of awtTeslaStrike:
    # Chain Reactor ground strike. Pulsing danger ring that brightens as the
    # bolt nears; a faint column shows it is coming from above. NOTE: the actual
    # lethal flash is the bolt/particle system (ungated by showHints) - this is
    # only the dodge telegraph.
    let cx = warning.pos.x; let cy = warning.pos.y
    let r  = warning.bulletRadius
    let progress = warningProgress(warning)
    if warning.lifetime <= TeslaStrikeActive:
      drawCircle(Vector2(x: cx, y: cy), r, Color(r: 255'u8, g: 255'u8, b: 200'u8, a: 150'u8))
      drawCircleLines(cx.int32, cy.int32, r, Color(r: 255'u8, g: 255'u8, b: 255'u8, a: 255'u8))
    else:
      let a2 = rampAlpha(warning, 60.0, 170.0)
      drawLine(Vector2(x: cx, y: 0), Vector2(x: cx, y: cy), 2,
               Color(r: 255'u8, g: 240'u8, b: 120'u8, a: uint8(progress * 80.0)))
      drawCircleLines(cx.int32, cy.int32, r,
                     Color(r: 255'u8, g: 235'u8, b: 70'u8, a: a2))
      drawCircleLines(cx.int32, cy.int32, r * 0.66,
                     Color(r: 255'u8, g: 255'u8, b: 160'u8, a: (a2 div 2).uint8))
      let rot = getTime() * 3.0
      for k in 0..<8:
        let ang = rot + k.float32 * PI / 4.0
        drawLine(Vector2(x: cx + cos(ang) * r * 0.8, y: cy + sin(ang) * r * 0.8),
                 Vector2(x: cx + cos(ang + 0.3) * r, y: cy + sin(ang + 0.3) * r),
                 1.5, Color(r: 255'u8, g: 255'u8, b: 150'u8, a: a2))

  of awtArcBeam:
    # Chain Reactor lightning wall segment. Dim full-width preview marks the kill
    # zone; a bright thin core line + endpoint nodes make the path unambiguous.
    let half = warning.laserLength
    let a = Vector2(x: warning.pos.x, y: warning.pos.y)
    let b = Vector2(x: warning.targetPos.x, y: warning.targetPos.y)
    if warning.lifetime <= ArcBeamActive:
      drawLine(a, b, half * 2.0, Color(r: 255'u8, g: 255'u8, b: 200'u8, a: 130'u8))
    else:
      let a2 = rampAlpha(warning, 45.0, 160.0)
      drawLine(a, b, half * 2.0, Color(r: 255'u8, g: 230'u8, b: 80'u8, a: (a2 div 5).uint8))
      drawLine(a, b, 2, Color(r: 255'u8, g: 240'u8, b: 90'u8, a: a2))
      drawCircle(a, 5.0, Color(r: 255'u8, g: 255'u8, b: 160'u8, a: a2))
      drawCircle(b, 5.0, Color(r: 255'u8, g: 255'u8, b: 160'u8, a: a2))

  of awtRicochetLaser:
    # The Laser Architect's bouncing beam, wind-up telegraph only. A loud, hard
    # to miss preview: a glowing danger band along the whole bounce route, a
    # crisp core line, energy dashes marching toward the muzzle to show the shot
    # direction, pulsing bounce nodes, and a colour that ramps cyan -> hot white
    # as fire nears. The live lethal beam is drawn ungated by drawRicochetLaserBeam.
    if warning.ricochetPath.len >= 2 and warning.lifetime > RicochetLaserActive:
      let progress = warningProgress(warning)  # 0 -> 1 toward fire
      let pulse = (sin(getTime() * 12.0) * 0.5 + 0.5).float32
      let a2 = rampAlpha(warning, 70.0, 185.0)
      let bandA = uint8(clamp((30.0 + progress * 90.0) * (0.7 + pulse * 0.3), 0.0, 255.0))
      # Colour ramps from cyan to hot white/red as the shot becomes imminent.
      let warm = uint8(clamp(progress * progress * 255.0, 0.0, 255.0))
      let core = Color(r: (120.0 + warm.float32 * 0.53).uint8,
                       g: (230.0 + (255.0 - 230.0) * progress).uint8,
                       b: 255'u8, a: a2)
      let halfW = warning.laserLength
      let coreThick = 2.0 + progress * 3.0 + pulse * 1.5

      for s in 0 ..< warning.ricochetPath.len - 1:
        let p0 = warning.ricochetPath[s]
        let p1 = warning.ricochetPath[s + 1]
        let a0 = Vector2(x: p0.x, y: p0.y)
        let b0 = Vector2(x: p1.x, y: p1.y)
        # Wide danger band marking the kill width, then the bright core line.
        drawLine(a0, b0, halfW * 2.0, Color(r: 0'u8, g: 190'u8, b: 255'u8, a: bandA))
        drawLine(a0, b0, coreThick, core)

      # Energy dashes marching along the path toward the muzzle (shot direction).
      let totalLen = polylineLength(warning.ricochetPath)
      if totalLen > 1.0:
        const DASH_SPACING = 46.0'f32
        let march = (getTime() * 320.0).float32 mod DASH_SPACING
        var d = march
        let dashA = uint8(clamp(120.0 + progress * 135.0, 0.0, 255.0))
        while d < totalLen:
          let head = ricochetSweptPath(warning.ricochetPath, d)
          if head.len >= 1:
            let hp = head[^1]
            drawCircle(Vector2(x: hp.x, y: hp.y), 2.5 + progress * 1.5,
                       Color(r: 235'u8, g: 250'u8, b: 255'u8, a: dashA))
          d += DASH_SPACING

      # Bounce nodes pulse so the ricochet corners read clearly.
      for v in warning.ricochetPath:
        drawCircle(Vector2(x: v.x, y: v.y), 4.0 + pulse * 2.0,
                   Color(r: 180'u8, g: 240'u8, b: 255'u8, a: a2))
      # Charging ring at the muzzle, tightening as the shot nears.
      let muzzle = warning.ricochetPath[0]
      drawCircleLines(muzzle.x.int32, muzzle.y.int32, 22.0 - progress * 12.0 + pulse * 4.0,
                      Color(r: 220'u8, g: 250'u8, b: 255'u8, a: a2))

  of awtVoidRift:
    # The Void Dancer's dimensional tear. The kill-zone ring is purple; an inner
    # ring collapses INWARD toward the core as detonation nears (an implosion
    # telegraph), with jagged void cracks radiating from a dark core. NOTE: the
    # lethal eruption itself is the radial void bullets + implosion particles
    # spawned in game.nim's warning loop (both ungated by showHints), so the kill
    # moment stays visible even with hints off - this branch is only the dodge cue.
    let cx = warning.pos.x; let cy = warning.pos.y
    let r  = warning.bulletRadius
    let progress = warningProgress(warning)  # 0 -> 1 toward collapse
    if warning.lifetime <= VoidRiftActive:
      drawCircle(Vector2(x: cx, y: cy), r, Color(r: 150'u8, g: 40'u8, b: 220'u8, a: 150'u8))
      drawCircleLines(cx.int32, cy.int32, r, Color(r: 235'u8, g: 200'u8, b: 255'u8, a: 255'u8))
      drawCircleLines(cx.int32, cy.int32, r * 0.5, Color(r: 255'u8, g: 255'u8, b: 255'u8, a: 220'u8))
    else:
      let a2 = rampAlpha(warning, 55.0, 175.0)
      drawCircleLines(cx.int32, cy.int32, r,
                     Color(r: 170'u8, g: 60'u8, b: 230'u8, a: a2))
      let collapseR = r * (1.0 - progress * 0.7)
      drawCircleLines(cx.int32, cy.int32, collapseR,
                     Color(r: 220'u8, g: 150'u8, b: 255'u8, a: a2))
      let rot = getTime() * 1.5
      for k in 0..<6:
        let ang = rot + k.float32 * PI / 3.0
        let inner = newVector2f(cx + cos(ang) * collapseR * 0.4, cy + sin(ang) * collapseR * 0.4)
        let outer = newVector2f(cx + cos(ang + 0.25) * r, cy + sin(ang + 0.25) * r)
        drawLine(Vector2(x: inner.x, y: inner.y), Vector2(x: outer.x, y: outer.y),
                 1.5, Color(r: 200'u8, g: 120'u8, b: 255'u8, a: a2))
      drawCircle(Vector2(x: cx, y: cy), 5.0 + (1.0 - progress) * 4.0,
                 Color(r: 30'u8, g: 0'u8, b: 50'u8, a: a2))

  of awtNone:
    # Unassigned/placeholder warning: nothing to telegraph. No `else` branch on
    # purpose - the case is exhaustive so adding a new AttackWarningType forces a
    # decision about its visual at compile time.
    discard

proc drawRicochetLaserBeam*(warning: AttackWarning) =
  ## Live lethal pass for the ricochet beam, drawn ungated (independent of the
  ## showHints telegraph gate) so the active beam is always visible like a Laser.
  ## The beam-front races along the path (RicochetLaserSweep) for an "advancing
  ## shot" feel; only the swept-so-far portion is drawn, tipped by a bright head.
  if warning.attackType != awtRicochetLaser: return
  if warning.lifetime > RicochetLaserActive: return
  if warning.ricochetPath.len < 2: return

  let halfW = warning.laserLength
  let activeElapsed = RicochetLaserActive - warning.lifetime
  let sweepFrac = clamp(activeElapsed / RicochetLaserSweep, 0.0'f32, 1.0'f32)
  let totalLen = polylineLength(warning.ricochetPath)
  let swept = ricochetSweptPath(warning.ricochetPath, sweepFrac * totalLen)
  if swept.len < 1: return

  # Trailing beam fades slightly once the front has fully arrived.
  let tailFade = clamp(warning.lifetime / RicochetLaserActive, 0.4'f32, 1.0'f32)
  let glowA = uint8(clamp(150.0'f32 * tailFade, 0.0'f32, 255.0'f32))
  let coreA = uint8(clamp(255.0'f32 * tailFade, 0.0'f32, 255.0'f32))

  for s in 0 ..< swept.len - 1:
    let a0 = Vector2(x: swept[s].x, y: swept[s].y)
    let b0 = Vector2(x: swept[s + 1].x, y: swept[s + 1].y)
    drawLine(a0, b0, halfW * 2.0, Color(r: 120'u8, g: 230'u8, b: 255'u8, a: glowA))
    drawLine(a0, b0, 3.5, Color(r: 235'u8, g: 255'u8, b: 255'u8, a: coreA))
  # Bounce nodes the beam has already reached.
  for v in swept:
    drawCircle(Vector2(x: v.x, y: v.y), 5.0, Color(r: 200'u8, g: 245'u8, b: 255'u8, a: coreA))
  # Bright travelling head at the beam-front while it is still racing.
  if sweepFrac < 1.0'f32:
    let head = swept[^1]
    let hp = (sin(getTime() * 30.0) * 0.5 + 0.5).float32
    drawCircle(Vector2(x: head.x, y: head.y), halfW + 6.0 + hp * 4.0,
               Color(r: 200'u8, g: 245'u8, b: 255'u8, a: 130'u8))
    drawCircle(Vector2(x: head.x, y: head.y), halfW * 0.6 + 3.0,
               Color(r: 255'u8, g: 255'u8, b: 255'u8, a: 255'u8))

proc drawLaser*(laser: Laser) =
  # Calculate alpha based on lifetime with accelerated fade
  let fadePercent = laser.lifetime / laser.maxLifetime

  # Accelerated fade in last 30% of lifetime for smoother disappearance
  let adjustedFade = if fadePercent < 0.3:
    # Quick fade in final 30% of lifetime: 0.3 -> 0.0 becomes 1.0 -> 0.0
    fadePercent / 0.3
  else:
    1.0

  let baseAlpha = uint8(adjustedFade * 200 + 55)  # 55-255 alpha

  # Laser colors with bright core
  let outerGlow = Color(r: 255, g: 100, b: 0, a: (baseAlpha div 3).uint8)
  let midGlow = Color(r: 255, g: 150, b: 30, a: (baseAlpha div 2).uint8)
  let coreColor = Color(r: 255, g: 200, b: 100, a: baseAlpha)

  case laser.direction
  of 0:  # Horizontal laser
    # Outer glow
    drawRectangle(
      (laser.pos.x - laser.length).int32,
      (laser.pos.y - laser.thickness - 6).int32,
      (laser.length * 2).int32,
      (laser.thickness * 2 + 12).int32,
      outerGlow
    )
    # Mid glow
    drawRectangle(
      (laser.pos.x - laser.length).int32,
      (laser.pos.y - laser.thickness - 2).int32,
      (laser.length * 2).int32,
      (laser.thickness * 2 + 4).int32,
      midGlow
    )
    # Bright core
    drawRectangle(
      (laser.pos.x - laser.length).int32,
      (laser.pos.y - laser.thickness).int32,
      (laser.length * 2).int32,
      (laser.thickness * 2).int32,
      coreColor
    )

  of 1:  # Vertical laser
    # Outer glow
    drawRectangle(
      (laser.pos.x - laser.thickness - 6).int32,
      (laser.pos.y - laser.length).int32,
      (laser.thickness * 2 + 12).int32,
      (laser.length * 2).int32,
      outerGlow
    )
    # Mid glow
    drawRectangle(
      (laser.pos.x - laser.thickness - 2).int32,
      (laser.pos.y - laser.length).int32,
      (laser.thickness * 2 + 4).int32,
      (laser.length * 2).int32,
      midGlow
    )
    # Bright core
    drawRectangle(
      (laser.pos.x - laser.thickness).int32,
      (laser.pos.y - laser.length).int32,
      (laser.thickness * 2).int32,
      (laser.length * 2).int32,
      coreColor
    )

  of 2:  # Cross laser (both horizontal and vertical) with rotation
    # Helper to calculate rotated endpoints
    proc getRotatedEnd(centerX, centerY, length, angle: float32): Vector2 =
      Vector2(
        x: centerX + cos(angle) * length,
        y: centerY + sin(angle) * length
      )

    # Draw horizontal beam (along rotation angle)
    let horizStart = getRotatedEnd(laser.pos.x, laser.pos.y, -laser.length, laser.rotation)
    let horizEnd = getRotatedEnd(laser.pos.x, laser.pos.y, laser.length, laser.rotation)

    # Draw multiple parallel lines to simulate thickness with glow
    # Outer glow
    for offset in -6 .. 6:
      let perpAngle = laser.rotation + PI / 2.0
      let offsetX = cos(perpAngle) * offset.float32
      let offsetY = sin(perpAngle) * offset.float32
      drawLine(
        Vector2(x: horizStart.x + offsetX, y: horizStart.y + offsetY),
        Vector2(x: horizEnd.x + offsetX, y: horizEnd.y + offsetY),
        3,
        outerGlow
      )
    # Mid glow
    for offset in -2 .. 2:
      let perpAngle = laser.rotation + PI / 2.0
      let offsetX = cos(perpAngle) * offset.float32
      let offsetY = sin(perpAngle) * offset.float32
      drawLine(
        Vector2(x: horizStart.x + offsetX, y: horizStart.y + offsetY),
        Vector2(x: horizEnd.x + offsetX, y: horizEnd.y + offsetY),
        3,
        midGlow
      )
    # Core
    drawLine(horizStart, horizEnd, 3, coreColor)

    # Draw vertical beam (perpendicular, 90 degrees offset)
    let vertAngle = laser.rotation + PI / 2.0
    let vertStart = getRotatedEnd(laser.pos.x, laser.pos.y, -laser.length, vertAngle)
    let vertEnd = getRotatedEnd(laser.pos.x, laser.pos.y, laser.length, vertAngle)

    # Outer glow
    for offset in -6 .. 6:
      let perpAngle = vertAngle + PI / 2.0
      let offsetX = cos(perpAngle) * offset.float32
      let offsetY = sin(perpAngle) * offset.float32
      drawLine(
        Vector2(x: vertStart.x + offsetX, y: vertStart.y + offsetY),
        Vector2(x: vertEnd.x + offsetX, y: vertEnd.y + offsetY),
        3,
        outerGlow
      )
    # Mid glow
    for offset in -2 .. 2:
      let perpAngle = vertAngle + PI / 2.0
      let offsetX = cos(perpAngle) * offset.float32
      let offsetY = sin(perpAngle) * offset.float32
      drawLine(
        Vector2(x: vertStart.x + offsetX, y: vertStart.y + offsetY),
        Vector2(x: vertEnd.x + offsetX, y: vertEnd.y + offsetY),
        3,
        midGlow
      )
    # Core
    drawLine(vertStart, vertEnd, 3, coreColor)

  of 3:  # Single rotated beam (for radial/prismatic patterns)
    # Helper to calculate rotated endpoints
    proc getRotatedEnd(centerX, centerY, length, angle: float32): Vector2 =
      Vector2(
        x: centerX + cos(angle) * length,
        y: centerY + sin(angle) * length
      )

    # Draw single beam along rotation angle - RADIAL (from center outward only)
    let beamStart = Vector2(x: laser.pos.x, y: laser.pos.y)  # Start at boss center
    let beamEnd = getRotatedEnd(laser.pos.x, laser.pos.y, laser.length, laser.rotation)  # Extend outward

    # Draw multiple parallel lines to simulate thickness with glow
    # Outer glow
    for offset in -6 .. 6:
      let perpAngle = laser.rotation + PI / 2.0
      let offsetX = cos(perpAngle) * offset.float32
      let offsetY = sin(perpAngle) * offset.float32
      drawLine(
        Vector2(x: beamStart.x + offsetX, y: beamStart.y + offsetY),
        Vector2(x: beamEnd.x + offsetX, y: beamEnd.y + offsetY),
        3,
        outerGlow
      )
    # Mid glow
    for offset in -2 .. 2:
      let perpAngle = laser.rotation + PI / 2.0
      let offsetX = cos(perpAngle) * offset.float32
      let offsetY = sin(perpAngle) * offset.float32
      drawLine(
        Vector2(x: beamStart.x + offsetX, y: beamStart.y + offsetY),
        Vector2(x: beamEnd.x + offsetX, y: beamEnd.y + offsetY),
        3,
        midGlow
      )
    # Core
    drawLine(beamStart, beamEnd, 3, coreColor)

  else:
    discard

proc spawnEnemy*(screenWidth, screenHeight: int32, difficulty: float32, game: Game,
                 rosterDifficulty: float32 = -1.0'f32): Enemy =
  ## Spawn a random enemy off-screen. Enemy *stats* scale with `difficulty`; the
  ## *type* is chosen by `pickSpawnType` (enemy_data.nim) from the pool gated by
  ## introductionDifficulty/fadeOutDifficulty/spawnWeight in `allEnemyDefs`.
  ##
  ## `rosterDifficulty` (default -1 = "same as difficulty") decouples which types
  ## may spawn from how strong they are. Survival passes a value just below the
  ## current difficulty during a boss fight so no enemy type debuts mid-boss, while
  ## keeping the stat scaling of the live difficulty.
  let side = rand(3)
  var x, y: float32

  case side
  of 0: x = rand(screenWidth.int).float32; y = -30
  of 1: x = screenWidth.float32 + 30; y = rand(screenHeight.int).float32
  of 2: x = rand(screenWidth.int).float32; y = screenHeight.float32 + 30
  else: x = -30; y = rand(screenHeight.int).float32

  let typeDifficulty = if rosterDifficulty < 0.0'f32: difficulty else: rosterDifficulty
  newEnemy(x, y, difficulty, pickSpawnType(typeDifficulty), game)

proc spawnBoss*(screenWidth, screenHeight: int32, difficulty: float32, bossCount: int, waveNumber: int): Enemy =
  ## Spawns a boss - either custom (waves 1-60) or random (after wave 60)
  ##
  ## CUSTOM BOSSES (every 5 waves):
  ##   - Use definitions from boss_definitions.nim
  ##   - HP-based phase system
  ##   - Unique attack patterns and abilities per boss
  ##
  ## Boss 12 (The Final Sentinel) repeats after wave 60 with increased stats
  ##
  # Check if this should be a custom boss (every 5 waves)
  let useCustomBoss = isBossWave(waveNumber)

  if useCustomBoss:
    # CUSTOM BOSS CREATION (Waves 1-60, every 5 waves)
    # Custom bosses use the advanced definition system from boss_definitions.nim
    # They have HP-based phases (defined in BossDefinition) and don't transform
    let bossDef = getBossForWave(waveNumber)
    let centerX = screenWidth.float32 / 2
    let centerY = screenHeight.float32 / 2
    var targetX, targetY, startX, startY: float32

    # Position based on boss ID (varied entrance positions)
    # For orbital/circling bosses the targetPos is placed on the orbit
    # radius edge so the entrance slide lands them right into the pattern.
    let orbitLandRadius = 180.0  # matches circle_player orbit radius
    case (bossDef.bossID - 1) mod 4
    of 0:  # From top
      startX = centerX; startY = -100
      # Land at top of orbit circle
      targetX = centerX; targetY = centerY - orbitLandRadius
    of 1:  # From bottom
      startX = centerX; startY = screenHeight.float32 + 100
      # Land at bottom of orbit circle
      targetX = centerX; targetY = centerY + orbitLandRadius
    of 2:  # From left
      startX = -100; startY = centerY
      # Land at left of orbit circle
      targetX = centerX - orbitLandRadius; targetY = centerY
    of 3:  # From right
      startX = screenWidth.float32 + 100; startY = centerY
      # Land at right of orbit circle
      targetX = centerX + orbitLandRadius; targetY = centerY
    else:
      startX = centerX; startY = -100
      targetX = centerX; targetY = centerY - orbitLandRadius

    # Create boss with custom stats
    let scaledHP = getScaledBossHP(bossDef, waveNumber)
    let phaseHpPools = getBossPhaseHpPools(bossDef, scaledHP)
    let firstPhaseHp =
      if phaseHpPools.len > 0: phaseHpPools[0]
      else: scaledHP
    let scaledSpeed = getScaledBossSpeed(bossDef, waveNumber)
    let scaledDamage = getScaledBossDamage(bossDef, waveNumber)

    # Initialize attack timers for first phase
    var initialAttackTimers: seq[float32] = @[]
    var initialAttackWarningFired: seq[bool] = @[]
    if bossDef.phases.len > 0:
      for attack in bossDef.phases[0].attacks:
        initialAttackTimers.add(attack.cooldown)  # Start with cooldown so attacks don't fire immediately
        initialAttackWarningFired.add(false)

    # Apply first phase multipliers to initial stats
    let firstPhaseSpeed = if bossDef.phases.len > 0:
      scaledSpeed * bossDef.phases[0].speedMultiplier
    else:
      scaledSpeed
    let firstPhaseDefense = if bossDef.phases.len > 0:
      bossDef.phases[0].defenseMultiplier
    else:
      1.0

    result = Enemy(
      pos: newVector2f(startX, startY),
      vel: newVector2f(0, 0),
      radius: bossDef.baseRadius,
      collisionRadius: bossDef.baseRadius * 0.4,
      hp: firstPhaseHp,
      maxHp: firstPhaseHp,
      speed: firstPhaseSpeed,  # Apply speedMultiplier from first phase
      contactDamage: scaledDamage,  # Boss contact damage
      rangedDamage: scaledDamage,   # Boss ranged damage
      color: bossDef.color,
      enemyType: etCircle,
      isBoss: true,
      bossDefinitionID: bossDef.bossID,
      currentPhaseIndex: 0,
      bossTotalMaxHp: scaledHP,
      bossPhaseHpPools: phaseHpPools,
      bossPhaseBreakFlashTimer: 0.0,
      attackTimers: initialAttackTimers,
      attackWarningFired: initialAttackWarningFired,
      startPos: newVector2f(startX, startY),
      shootTimer: 0,
      spawnTimer: 0,
      dashTimer: 0,
      hitCount: 0,
      requiredHits: 0,
      reflectShieldCooldown: 7.0'f32,  # delay first overload shield ~7s into the fight
      lastContactDamageTime: 0,
      teleportTimer: 10.0,
      shockwaveTimer: 8.0,
      burstTimer: 0.5,
      lastWallDamageTime: 0,
      entranceTimer: 2.0,
      entranceWait: 0.0,
      targetPos: newVector2f(targetX, targetY),
      attackWarningTimer: 0,
      attackExecuteTimer: 0,
      attackPhase: 0,
      defenseMultiplier: firstPhaseDefense,  # Apply defenseMultiplier from first phase
      debuffResistance: 0.5,  # Bosses have 50% stun/slow resistance
      # Boss dash state initialization
      isDashing: false,
      dashVelocity: newVector2f(0, 0),
      dashDuration: 0,
      dashMaxDuration: 0,
      dashTargetPos: newVector2f(0, 0),
      pendingDashLocked: false,
      pendingDashStart: newVector2f(0, 0),
      pendingDashTarget: newVector2f(0, 0),
      weakPoint: initBossWeakPointState(bossDef.weakPoint, bossDef.bossID),
      activeEffects: default(array[ElementType, ActiveEffect])
    )

proc makeElite*(enemy: Enemy, waveNumber: int = 0, scalingWave: int = -1) =
  ## Converts a regular enemy into an elite with enhanced stats and special abilities
  ## Elite chance increases with wave number, but the midgame ramp is kept gentler.
  ## Dual-modifier elites are delayed so waves 20-35 do not suddenly feel boss-like.
  ## BALANCED: Multiple effects apply with diminishing returns to prevent exponential growth
  ##
  ## `scalingWave` decouples stat magnitude from the chance roll: the dungeon
  ## boosts `waveNumber` to guarantee elites in elite rooms, which must NOT
  ## inflate the wave-calibrated stat bonuses below. Defaults to `waveNumber`.

  # Don't make bosses elite
  if enemy.isBoss:
    return

  # Elite chance: ramps from 2% → 12% by wave 29, then continues +1%/wave to cap 32%
  let baseChance = min(2 + (waveNumber.float32 * 0.35).int, 12)
  let lateBonus = max(0, waveNumber - 28)
  let eliteChance = min(baseChance + lateBonus, 32)
  if rand(99) >= eliteChance:
    return

  let statWave = if scalingWave >= 0: scalingWave else: waveNumber

  enemy.isElite = true
  enemy.eliteAuraPhase = 0.0
  enemy.eliteTypes = @[]  # Initialize empty list for multiple types
  enemy.threatLevel = max(enemy.threatLevel,
    if statWave >= 60: 5
    elif statWave >= 50: 4
    elif statWave >= 35: 3
    elif statWave >= 20: 2
    else: 1)

  # Elite scaling multiplier based on wave, reduced to avoid runaway EHP.
  let eliteScaling = 1.0 + (statWave.float32 * 0.03)
  # Speed scaling is lighter still so modifiers add texture, not unavoidable pressure.
  let eliteSpeedScaling = 1.0 + (statWave.float32 * 0.015)

  # Determine number of elite effects based on wave
  # BALANCED: Delay dual-effect elites until later so midgame remains readable.
  let numEffects = if statWave >= 55:
    # Waves 55+: 65% chance for a dual-effect elite
    if rand(99) < 65: 2 else: 1
  elif statWave >= 35:
    # Waves 35–54: 35% chance for a dual-effect elite
    if rand(99) < 35: 2 else: 1
  else:
    # Waves 1-34: Single effect
    1

  # Choose random elite types (ensure no duplicates)
  # STAR ENEMY RESTRICTION: Stars cannot get Tank, Shielded, or Regenerative (they're already tanky)
  var availableTypes = if enemy.enemyType == etStar:
    @[etSwift, etVenomous, etExplosive]  # Exclude Tank, Shielded, and Regenerative
  else:
    @[etSwift, etTank, etVenomous, etExplosive, etRegenerative, etShielded]

  # TANK RESTRICTION: If Tank is selected, remove Regenerative from available types
  # This prevents the overpowered Tank + Regenerative combo

  for i in 0..<numEffects:
    if availableTypes.len == 0:
      break
    let idx = rand(availableTypes.len - 1)
    let selectedType = availableTypes[idx]
    enemy.eliteTypes.add(selectedType)
    availableTypes.delete(idx)

    # If Tank was selected, remove Regenerative to prevent overpowered combo
    if selectedType == etTank:
      for j in countdown(availableTypes.len - 1, 0):
        if availableTypes[j] == etRegenerative:
          availableTypes.delete(j)
          break
    # If Regenerative was selected, remove Tank to prevent overpowered combo
    elif selectedType == etRegenerative:
      for j in countdown(availableTypes.len - 1, 0):
        if availableTypes[j] == etTank:
          availableTypes.delete(j)
          break

  # For backward compatibility, set primary eliteType to first in list
  enemy.eliteType = if enemy.eliteTypes.len > 0: enemy.eliteTypes[0] else: etNone

  # Multiplier for multiple effects (diminishing returns)
  # 1 effect = 100%, 2 effects = 70% effectiveness to prevent stacking exponentially
  let effectMultiplier = if enemy.eliteTypes.len >= 2: 0.7 else: 1.0

  # BASE ELITE BONUS: All elites get a base stat increase
  # This represents them being fundamentally stronger than normal enemies
  let baseEliteBonus = 1.15  # 15% base bonus to all stats
  enemy.maxHp *= baseEliteBonus
  enemy.hp *= baseEliteBonus
  enemy.contactDamage = enemy.contactDamage.float32 * baseEliteBonus
  enemy.rangedDamage = enemy.rangedDamage.float32 * baseEliteBonus

  # Apply elite modifications for ALL types in the list
  for eType in enemy.eliteTypes:
    case eType
    of etSwift:
      # 40% faster movement + reduced speed scaling
      enemy.speed *= (1.4 * eliteSpeedScaling * effectMultiplier)
      # Cap speed increase
      let maxSpeed = 1000.0
      if enemy.speed > maxSpeed:
        enemy.speed = maxSpeed
      enemy.shootTimer *= 0.7  # Faster shooting
      if enemy.dashCooldown > 0:
        enemy.dashCooldown *= 0.75
      # Swift elites are smaller
      enemy.radius *= 0.9
      enemy.collisionRadius *= 0.9
      enemy.contactDamage += float32(1 + (statWave div 5))
      enemy.rangedDamage += float32(1 + (statWave div 5))
      enemy.maxHp *= (0.9 * eliteScaling)
      enemy.hp *= (0.9 * eliteScaling)

    of etTank:
      # Tank elites are still durable, but no longer mini-bosses in wave 20-30.
      enemy.maxHp *= (1.45 * eliteScaling * effectMultiplier)
      enemy.hp *= (1.45 * eliteScaling * effectMultiplier)
      enemy.speed *= 0.8  # Slow
      # Tank elites are larger
      enemy.radius *= 1.3
      enemy.collisionRadius *= 1.3
      enemy.contactDamage += float32(statWave div 5)
      enemy.rangedDamage += float32(statWave div 5)

    of etVenomous:
      # Poisons player on contact
      # Balanced growth with reduced speed scaling
      enemy.speed *= (1.15 * eliteSpeedScaling * effectMultiplier)  # Uses speed scaling
      enemy.contactDamage += float32(2 + (statWave div 7))
      enemy.rangedDamage += float32(2 + (statWave div 7))
      enemy.maxHp *= (1.3 * eliteScaling * effectMultiplier)  # Uses normal scaling
      enemy.hp *= (1.3 * eliteScaling * effectMultiplier)

    of etExplosive:
      # Explodes on death
      # Multiple effects reduce HP scaling but use reduced speed scaling
      enemy.maxHp *= (1.55 * eliteScaling * effectMultiplier)
      enemy.hp *= (1.55 * eliteScaling * effectMultiplier)
      enemy.contactDamage += float32(2 + (statWave div 7))
      enemy.rangedDamage += float32(2 + (statWave div 7))
      enemy.speed *= (1.0 * eliteSpeedScaling * effectMultiplier)

    of etRegenerative:
      # Regenerates 5% HP per second
      enemy.regenTimer = 0.0
      # Multiple effects reduce HP scaling
      enemy.maxHp *= (1.45 * eliteScaling * effectMultiplier)
      enemy.hp *= (1.45 * eliteScaling * effectMultiplier)
      enemy.contactDamage += float32(1 + (statWave div 5))
      enemy.rangedDamage += float32(1 + (statWave div 5))

    of etShielded:
      # Has a shield that absorbs damage
      # Multiple effects reduce HP and shield scaling
      enemy.maxHp *= (1.15 * eliteScaling * effectMultiplier)
      enemy.hp *= (1.15 * eliteScaling * effectMultiplier)
      let shieldAmount = enemy.maxHp * 0.45  # Shield = 45% of max HP
      enemy.shieldHp = shieldAmount
      enemy.maxShieldHp = shieldAmount
      enemy.contactDamage += float32(2 + (statWave div 5))
      enemy.rangedDamage += float32(2 + (statWave div 5))

    else:
      discard

  # All elites drop slightly more coins (1.5x multiplier applied in game.nim)
  # All elites are slightly larger for visibility (if not already modified by Swift or Tank)
  if etSwift notin enemy.eliteTypes and etTank notin enemy.eliteTypes:
    enemy.radius *= 1.15
    enemy.collisionRadius *= 1.15

proc getEliteAuraColor*(eliteType: EliteType): Color =
  ## Returns the aura color for each elite type
  case eliteType
  of etNone: White  # Should never be called
  of etSwift: SkyBlue
  of etTank: Gray
  of etVenomous: Green
  of etExplosive: Orange
  of etRegenerative: Color(r: 255, g: 100, b: 255, a: 255)  # Magenta
  of etShielded: Color(r: 100, g: 200, b: 255, a: 255)  # Cyan

proc drawEliteAura*(enemy: Enemy, gameTime: float32) =
  ## Draws the visual aura around elite enemies
  ## For multi-elite enemies (wave 25+), draws layered auras with different colors
  if not enemy.isElite or enemy.eliteTypes.len == 0:
    return

  # Pulsing aura effect
  enemy.eliteAuraPhase += 0.05
  let pulseIntensity = sin(enemy.eliteAuraPhase) * 0.3 + 0.7  # 0.4 to 1.0

  # Draw auras for each elite type (layered effect for multiple types)
  for idx, eType in enemy.eliteTypes:
    let auraColor = getEliteAuraColor(eType)
    let radiusOffset = idx.float32 * 5.0

    # Bold close ring, sits just outside the body, highest contrast
    drawCircleLines(enemy.pos.x.int32, enemy.pos.y.int32,
      enemy.radius + 6.0 + radiusOffset,
      Color(r: auraColor.r, g: auraColor.g, b: auraColor.b,
            a: uint8(190.0'f32 * float32(pulseIntensity))))

    # Three expanding outer glow rings
    for i in 0..2:
      let ringRadius = enemy.radius + 13.0 + radiusOffset + i.float32 * 7.0 +
                       float32(sin(gameTime * 3.0 + idx.float32) * 3.0)
      let alpha = uint8((210.0'f32 - i.float32 * 55.0'f32) * float32(pulseIntensity))
      drawCircleLines(enemy.pos.x.int32, enemy.pos.y.int32, ringRadius,
        Color(r: auraColor.r, g: auraColor.g, b: auraColor.b, a: alpha))

  # Draw health bar for Tank elites (above shield bar if present)
  if etTank in enemy.eliteTypes:
    let barWidth = enemy.radius * 2.0
    let barHeight = 5.0
    # If shielded, place HP bar above shield bar, otherwise at default position
    let barY = if etShielded in enemy.eliteTypes:
      enemy.pos.y - enemy.radius - 20.0  # Above shield bar (which is at -12)
    else:
      enemy.pos.y - enemy.radius - 12.0  # Default position
    let barX = enemy.pos.x - barWidth / 2.0

    # HP background (red)
    drawRectangle(
      barX.int32,
      barY.int32,
      barWidth.int32,
      barHeight.int32,
      Color(r: 80, g: 20, b: 20, a: 200)
    )

    # HP fill (green to yellow gradient based on health)
    let hpPercent = enemy.hp / enemy.maxHp
    let fillColor = if hpPercent > 0.5:
      Color(r: uint8(100 + (1.0 - hpPercent) * 155), g: 255, b: 0, a: 255)  # Green to yellow
    else:
      Color(r: 255, g: uint8(hpPercent * 510), b: 0, a: 255)  # Yellow to red

    drawRectangle(
      barX.int32,
      barY.int32,
      (barWidth * hpPercent).int32,
      barHeight.int32,
      fillColor
    )

    # HP border
    drawRectangleLines(
      barX.int32,
      barY.int32,
      barWidth.int32,
      barHeight.int32,
      Color(r: 200, g: 100, b: 0, a: 255)
    )

  # Draw shield bar for shielded elites
  if etShielded in enemy.eliteTypes and enemy.shieldHp > 0:
    let barWidth = enemy.radius * 2.0
    let barHeight = 4.0
    let barX = enemy.pos.x - barWidth / 2.0
    let barY = enemy.pos.y - enemy.radius - 12.0

    # Shield background
    drawRectangle(
      barX.int32,
      barY.int32,
      barWidth.int32,
      barHeight.int32,
      Color(r: 40, g: 40, b: 40, a: 200)
    )

    # Shield fill
    let shieldPercent = enemy.shieldHp / enemy.maxShieldHp
    drawRectangle(
      barX.int32,
      barY.int32,
      (barWidth * shieldPercent).int32,
      barHeight.int32,
      Color(r: 100, g: 200, b: 255, a: 255)
    )

    # Shield border
    drawRectangleLines(
      barX.int32,
      barY.int32,
      barWidth.int32,
      barHeight.int32,
      Color(r: 150, g: 220, b: 255, a: 255)
    )

proc drawEliteOverlay*(enemy: Enemy, gameTime: float32) =
  ## Drawn AFTER drawEnemy, places colored outline and orbit crown on top of the body
  if not enemy.isElite or enemy.eliteTypes.len == 0:
    return

  let pulseIntensity = float32(sin(enemy.eliteAuraPhase) * 0.3 + 0.7)
  let numTypes = enemy.eliteTypes.len

  # Layer A: colored body outline (on top of enemy body, most noticeable change)
  for idx, eType in enemy.eliteTypes:
    let col = getEliteAuraColor(eType)
    let outlineR = enemy.radius + 1.5'f32 + idx.float32 * 3.0'f32
    let outlineA = uint8((230.0'f32 - idx.float32 * 40.0'f32) * pulseIntensity)
    drawCircleLines(enemy.pos.x.int32, enemy.pos.y.int32, outlineR,
      Color(r: col.r, g: col.g, b: col.b, a: outlineA))

  # Layer B: rotating orbit crown (6 bright dots per type, second type counter-rotates)
  for idx, eType in enemy.eliteTypes:
    let col = getEliteAuraColor(eType)
    let orbitR = enemy.radius + 10.0'f32 + idx.float32 * 5.5'f32
    let rotSpeed = if idx == 0: 2.2'f32 else: -1.8'f32
    for di in 0..<6:
      let ang = di.float32 * PI / 3.0'f32 + gameTime * rotSpeed + idx.float32 * PI / 6.0'f32
      drawCircle(
        Vector2(x: enemy.pos.x + cos(ang) * orbitR, y: enemy.pos.y + sin(ang) * orbitR),
        2.6'f32 + pulseIntensity * 1.2'f32,
        Color(r: col.r, g: col.g, b: col.b, a: uint8(210.0'f32 * pulseIntensity)))

  # Layer C: type icon above the head, side-by-side for dual types
  let iconS = 5.0'f32
  let iconBaseY = enemy.pos.y - enemy.radius - 17.0'f32
  for idx, eType in enemy.eliteTypes:
    let col = getEliteAuraColor(eType)
    let iconX = enemy.pos.x + (idx.float32 - (numTypes - 1).float32 * 0.5'f32) * 14.0'f32
    let iconY = iconBaseY
    case eType
    of etSwift:
      # Lightning bolt ⚡ (two segments)
      drawLine(Vector2(x: iconX + 2, y: iconY - iconS),
               Vector2(x: iconX - 1, y: iconY), 2, col)
      drawLine(Vector2(x: iconX - 1, y: iconY),
               Vector2(x: iconX - 3, y: iconY + iconS), 2, col)
    of etTank:
      # Shield arc (3-segment arc on top half + flat bottom)
      for si in 0..<4:
        let sa0 = PI + si.float32 * PI / 4.0'f32
        let sa1 = PI + (si.float32 + 1.0'f32) * PI / 4.0'f32
        drawLine(Vector2(x: iconX + cos(sa0) * iconS, y: iconY + sin(sa0) * iconS),
                 Vector2(x: iconX + cos(sa1) * iconS, y: iconY + sin(sa1) * iconS),
                 2, col)
      drawLine(Vector2(x: iconX - iconS, y: iconY), Vector2(x: iconX + iconS, y: iconY), 2, col)
    of etVenomous:
      # X shape
      drawLine(Vector2(x: iconX - iconS, y: iconY - iconS),
               Vector2(x: iconX + iconS, y: iconY + iconS), 2, col)
      drawLine(Vector2(x: iconX + iconS, y: iconY - iconS),
               Vector2(x: iconX - iconS, y: iconY + iconS), 2, col)
    of etExplosive:
      # 4-point starburst
      for si in 0..<4:
        let sa = si.float32 * PI / 2.0'f32 + PI / 4.0'f32
        drawLine(Vector2(x: iconX, y: iconY),
                 Vector2(x: iconX + cos(sa) * iconS, y: iconY + sin(sa) * iconS), 2, col)
    of etRegenerative:
      # + (plus sign)
      drawLine(Vector2(x: iconX - iconS, y: iconY),
               Vector2(x: iconX + iconS, y: iconY), 2, col)
      drawLine(Vector2(x: iconX, y: iconY - iconS),
               Vector2(x: iconX, y: iconY + iconS), 2, col)
    of etShielded:
      # Circle outline
      drawCircleLines(iconX.int32, iconY.int32, iconS,
                      Color(r: col.r, g: col.g, b: col.b, a: 255))
    of etNone:
      discard

proc updateEliteEffects*(enemy: Enemy, dt: float32) =
  ## Updates elite-specific effects like regeneration
  ## Handles multiple elite types (wave 25+)
  if not enemy.isElite:
    return

  # Process each elite type effect
  for eType in enemy.eliteTypes:
    case eType
    of etRegenerative:
      # Regenerate 5% max HP per second
      enemy.regenTimer += dt
      if enemy.regenTimer >= 0.2:  # Update every 0.2 seconds
        let regenAmount = enemy.maxHp * 0.01  # 1.0% per 0.2s = 5% per second
        enemy.hp = min(enemy.hp + regenAmount, enemy.maxHp)
        enemy.regenTimer = 0.0

    else:
      discard
