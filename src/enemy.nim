import raylib, types, random, math, wall, effects, tables, boss_definitions, run_statistics, enemy_config, enemy_helpers

proc getEffectiveSpeed*(baseSpeed: float32, waveNumber: int): float32 =
  ## NATURAL SPEED REDUCTION: Pure mathematical scaling with NO hardcoded thresholds
  ## Reduction emerges naturally from wave progression and enemy speed
  ## Exponential scaling for fast enemies that grows stronger over time
  
  # Reference speed: typical wave 1 enemy speed
  const REFERENCE_SPEED = 100.0
  
  # Calculate speed excess over reference (how much faster than normal)
  let speedRatio = baseSpeed / REFERENCE_SPEED
  
  # Wave pressure: natural logarithmic growth that increases smoothly with waves
  # ln(1 + wave/10) creates unbounded growth without thresholds:
  # Wave 1 -> 0.095, Wave 10 -> 0.693, Wave 20 -> 1.099, Wave 50 -> 1.705
  let wavePressure = ln(1.0 + waveNumber.float32 / 10.0)
  
  # Speed excess factor: exponential penalty for being faster than reference
  # Uses sqrt to convert ratio to excess smoothly:
  # 1.5x speed -> 1.22x factor, 2x -> 1.41x, 3x -> 1.73x, 4x -> 2.0x
  # max(0, ...) ensures no penalty for slower enemies
  let speedExcessFactor = max(0.0, sqrt(speedRatio) - 1.0)
  
  # Combined reduction: (speed_excess)^1.8 * wave_pressure * 0.28
  # Power of 1.8 creates strong exponential scaling for fast enemies
  # Coefficient 0.28 provides balanced reduction that grows naturally
  # Result: fast enemies in late waves get heavily reduced, but it's gradual
  let reductionFactor = pow(speedExcessFactor, 1.8) * wavePressure * 0.28
  
  # Apply reduction with natural diminishing returns
  # Formula: speed / (1 + factor) can never reduce to 0
  return baseSpeed / (1.0 + reductionFactor)

proc newEnemy*(x, y: float32, difficulty: float32, enemyType: EnemyType, game: Game): Enemy =
  # Get enemy configuration
  let config = getEnemyConfig(enemyType)
  
  # Calculate scaled stats
  let stats = getScaledEnemyStats(config, difficulty)
  
  # Create base enemy with config values
  result = Enemy(
    id: game.nextEnemyId,
    pos: newVector2f(x, y),
    vel: newVector2f(0, 0),
    radius: stats.radius,
    collisionRadius: stats.radius * 0.4,  # 40% of visual size for enemy collision
    hp: stats.hp,
    maxHp: stats.hp,
    speed: stats.speed,
    contactDamage: config.contactDamage,
    rangedDamage: if config.hasRangedAttack: config.attack.damage.int else: 0,
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
    attackExecuteTimer: if config.specialBehaviorType == "charge_shot": 3.0 else: 0,
    attackPhase: 0,
    hasEnteredScreen: not config.requiresScreenEntry,  # Inverted logic
    activeEffects: initTable[ElementType, ActiveEffect](),
    dashCooldown: config.movement.dashCooldown,
    hexTeleportTimer: if config.movement.teleportCooldown > 0: config.movement.teleportCooldown + rand(1.0) else: 0,
    fakeWarningTimer: if config.specialBehaviorType == "fake_warning_teleport": 3.0 + rand(2.0) else: 0,
    cloneTimer: if config.specialBehaviorType == "clone_teleport": 2.0 + rand(1.5) else: 0,
    clonePositions: @[],
    rotation: 0.0
  )
  
  # Initialize boss-spawned flag (default: false, set to true by boss summon)
  result.spawnedByBoss = false
  
  # Initialize defense multiplier (default: 1.0 = no reduction, bosses override this)
  if not result.isBoss:
    result.defenseMultiplier = 1.0
  
  # Initialize debuff resistance (default: 0.0 = no resistance, bosses set to 0.5 = 50% reduction)
  result.debuffResistance = 0.0
  
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
      let progress = clamp(1.0 - (enemy.entranceTimer / 1.0), 0.0, 1.0)
      # Linear interpolation (no smoothing)
      enemy.pos.x = enemy.startPos.x + (enemy.targetPos.x - enemy.startPos.x) * progress
      enemy.pos.y = enemy.startPos.y + (enemy.targetPos.y - enemy.startPos.y) * progress
      # If arrival completed this frame, prime shooting so it happens immediately
      if enemy.entranceTimer <= 0:
        enemy.pos = enemy.targetPos
        enemy.shootTimer = 0.81
      return true
    
    enemy.shootTimer += dt
    enemy.spawnTimer += dt
    
    # CUSTOM BOSS COLOR UPDATE (HP-based phases)
    # Update custom boss color based on HP percentage and phase definitions
    let hpPercent = enemy.hp / enemy.maxHp
    if hpPercent <= 0.25:
      # Final phase - bright glow
      enemy.color = Color(r: 255, g: 100, b: 255, a: 255)  # Magenta glow
    elif hpPercent <= 0.35:
      # Third phase
      enemy.color = Color(r: 255, g: 150, b: 0, a: 255)  # Orange
    elif hpPercent <= 0.5:
      # Second phase  
      enemy.color = Color(r: 255, g: 50, b: 50, a: 255)  # Red
    elif hpPercent <= 0.7:
      # Getting damaged
      enemy.color = Color(r: 200, g: 100, b: 50, a: 255)  # Dark orange
    # else: keep original color (full HP)
    
    
    let dir = (playerPos - enemy.pos).normalize()
    var canMove = true
    let nextPos = enemy.pos + dir * effectiveSpeed * dt
    for wall in walls:
      if distance(nextPos, wall.pos) < enemy.radius + wall.radius:
        canMove = false
        if currentTime - enemy.lastWallDamageTime >= 1.0:
          wall.takeDamage(1.0)
          trackWallDamaged(game)
          enemy.hp -= 1.0
          enemy.lastWallDamageTime = currentTime
        break
    if canMove:
      enemy.vel = dir * effectiveSpeed
      enemy.pos = enemy.pos + enemy.vel * dt
  
  else:
    # Regular enemy updates
    case enemy.enemyType
    of etCircle:
      let dir = (playerPos - enemy.pos).normalize()
      var canMove = true
      let nextPos = enemy.pos + dir * effectiveSpeed * dt
      for wall in walls:
        if distance(nextPos, wall.pos) < enemy.radius + wall.radius:
          canMove = false
          if currentTime - enemy.lastWallDamageTime >= 1.0:
            wall.takeDamage(1.0)
            enemy.hp -= 1.0
            enemy.lastWallDamageTime = currentTime
          break
      if canMove:
        enemy.vel = dir * effectiveSpeed
        enemy.pos = enemy.pos + enemy.vel * dt
    
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
      
      # Check collisions
      let hitWall = checkWallCollision(enemy, nextPos, walls, currentTime, game)
      let hitBoundary = checkScreenBoundaryCollision(enemy, nextPos, game, config)
      
      # Apply movement if no collisions
      if not hitWall and not hitBoundary:
        enemy.pos = nextPos
      
      # Execute ranged attack (uses config values)
      executeRangedAttack(enemy, playerPos, game)
    
    of etTriangle:
      # Get config for this enemy type
      let config = getEnemyConfig(enemy.enemyType)
      
      # Calculate dash speed multiplier from config (dashSpeed / baseSpeed)
      let dashMultiplier = config.movement.dashSpeed / config.movement.baseSpeed
      
      enemy.dashTimer -= dt
      if enemy.dashTimer <= 0:
        let dir = (playerPos - enemy.pos).normalize()
        enemy.vel = dir * effectiveSpeed * dashMultiplier
        enemy.dashTimer = config.movement.dashCooldown + rand(1.0)
      else:
        let dir = (playerPos - enemy.pos).normalize()
        let distToPlayer = distance(enemy.pos, playerPos)
        let zigzagAngle = sin(currentTime * 7.0 + enemy.pos.x * 0.05) * 0.5
        let zigzagDir = newVector2f(
          dir.x * cos(zigzagAngle) - dir.y * sin(zigzagAngle),
          dir.x * sin(zigzagAngle) + dir.y * cos(zigzagAngle)
        )
        if distToPlayer > 120:
          enemy.vel = zigzagDir * effectiveSpeed * 0.9
        else:
          let tangent = newVector2f(-dir.y, dir.x)
          let weaveIntensity = sin(currentTime * 10.0 + enemy.pos.y * 0.05) * 0.5
          let circleDir = (zigzagDir * (0.5 + weaveIntensity * 0.2) + tangent * (0.5 - weaveIntensity * 0.2)).normalize()
          enemy.vel = circleDir * effectiveSpeed * 0.95
        # Velocity dampening
        enemy.vel = enemy.vel * pow(0.98, 60.0 * dt)
      var canMove = true
      let nextPos = enemy.pos + enemy.vel * dt
      for wall in walls:
        if distance(nextPos, wall.pos) < enemy.radius + wall.radius:
          canMove = false
          let wallDir = (enemy.pos - wall.pos).normalize()
          enemy.vel = wallDir * effectiveSpeed * 0.85
          if currentTime - enemy.lastWallDamageTime >= 1.0:
            wall.takeDamage(1.0)
            trackWallDamaged(game)
            enemy.hp -= 1.0
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
        enemy.vel = dir * effectiveSpeed
      let nextPos = enemy.pos + enemy.vel * dt
      var canMove = true
      for wall in walls:
        if distance(nextPos, wall.pos) < enemy.radius + wall.radius:
          canMove = false
          if currentTime - enemy.lastWallDamageTime >= 1.0:
            wall.takeDamage(1.0)
            trackWallDamaged(game)
            enemy.hp -= 1.0
            enemy.lastWallDamageTime = currentTime
          break
      if canMove:
        enemy.pos = nextPos
    
    of etHexagon:
      # Update timers
      enemy.hexTeleportTimer -= dt
      enemy.shootTimer += dt
      
      # Teleport behavior
      if enemy.hexTeleportTimer <= 0:
        let angle = rand(1.0) * PI * 2.0
        let teleportDist = 150.0 + rand(100.0)
        enemy.pos.x = playerPos.x + cos(angle) * teleportDist
        enemy.pos.y = playerPos.y + sin(angle) * teleportDist
        enemy.hexTeleportTimer = 2.5 + rand(1.0)
      else:
        # Chase player when not teleporting
        let nextPos = chasePlayer(enemy, playerPos, dt, effectiveSpeed)
        let hitWall = checkWallCollision(enemy, nextPos, walls, currentTime, game)
        if not hitWall:
          enemy.pos = nextPos
      
      # Chaotic shooting (uses config for fire rate, bullet count, speed)
      executeRangedAttack(enemy, playerPos, game)
    
    of etCross:
      # Shows cross warning before attack, then dashes while rotating
      case enemy.attackPhase
      of 0:  # Patrol - slow movement
        let dir = (playerPos - enemy.pos).normalize()
        let nextPos = enemy.pos + dir * effectiveSpeed * dt
        var canMove = true
        for wall in walls:
          if distance(nextPos, wall.pos) < enemy.radius + wall.radius:
            canMove = false
            break
        if canMove:
          enemy.pos = nextPos
        
        enemy.attackWarningTimer += dt
        if enemy.attackWarningTimer >= 3.0:
          enemy.attackPhase = 1
          enemy.attackWarningTimer = 1.2  # Warning duration
          # Add warning to game
          game.attackWarnings.add(newAttackWarning(enemy.pos.x, enemy.pos.y, "cross", 1.2))
      
      of 1:  # Warning phase - stop moving, prepare for dash
        enemy.attackWarningTimer -= dt
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
        
        # Rotate during dash (FASTER rotation in OPPOSITE direction)
        enemy.rotation -= dt * -12.5  # -12.5 radians per second (negative = clockwise)
        
        # Dash movement with rotation
        if enemy.attackExecuteTimer > 0:
          # Continue dashing
          let nextPos = enemy.pos + enemy.vel * dt
          var canMove = true
          for wall in walls:
            if distance(nextPos, wall.pos) < enemy.radius + wall.radius:
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
          
          # Reset to patrol phase after firing
          enemy.attackPhase = 0
          enemy.attackWarningTimer = 0
          enemy.attackExecuteTimer = 0
      else:
        discard
    
    of etDiamond:
      # Get config for this enemy type
      let config = getEnemyConfig(enemy.enemyType)
      let dashMultiplier = config.movement.dashSpeed / config.movement.baseSpeed
      
      # Dash and shoot behavior
      enemy.dashCooldown -= dt
      enemy.shootTimer += dt
      
      if enemy.dashCooldown <= 0:
        # Start dash
        let dir = (playerPos - enemy.pos).normalize()
        enemy.vel = dir * effectiveSpeed * dashMultiplier
        enemy.dashCooldown = config.movement.dashCooldown + rand(1.0)
        
        # Shoot 3-spread during dash start (uses config)
        executeRangedAttack(enemy, playerPos, game)
      else:
        # Normal movement
        let dir = (playerPos - enemy.pos).normalize()
        enemy.vel = dir * effectiveSpeed * 0.7
      
      # Periodic shooting during movement (random direction)
      if enemy.shootTimer > config.attack.fireRate:
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
      
      # Check collisions
      let hitWall = checkWallCollision(enemy, nextPos, walls, currentTime, game)
      let hitBoundary = checkScreenBoundaryCollision(enemy, nextPos, game, config)
      
      # Apply movement if no collisions
      if not hitWall and not hitBoundary:
        enemy.pos = nextPos
      
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
      
      # Check collisions
      let hitWall = checkWallCollision(enemy, nextPos, walls, currentTime, game)
      let hitBoundary = checkScreenBoundaryCollision(enemy, nextPos, game, config)
      
      # Apply movement if no collisions
      if not hitWall and not hitBoundary:
        enemy.pos = nextPos
      
      # Powerful pentagon sniper shot (uses config values)
      executeRangedAttack(enemy, playerPos, game)
    
    of etTrickster:
      # Fake warning + teleport behavior
      enemy.fakeWarningTimer -= dt
      
      if enemy.fakeWarningTimer <= 0:
        # Show fake warning at current position
        game.attackWarnings.add(newAttackWarning(enemy.pos.x, enemy.pos.y, "fake", 1.0))
        
        # Teleport to different position
        let angle = rand(1.0) * PI * 2.0
        let dist = 120.0 + rand(80.0)
        let newX = playerPos.x + cos(angle) * dist
        let newY = playerPos.y + sin(angle) * dist
        enemy.pos = newVector2f(newX, newY)
        
        # Shoot 6-way burst from NEW position (uses config)
        executeRangedAttack(enemy, playerPos, game)
        
        enemy.fakeWarningTimer = 3.0 + rand(2.0)
      
      # Normal movement
      let nextPos = chasePlayer(enemy, playerPos, dt, effectiveSpeed * 0.6)
      let hitWall = checkWallCollision(enemy, nextPos, walls, currentTime, game)
      if not hitWall:
        enemy.pos = nextPos
    
    of etPhantom:
      # Get config for this enemy type
      let config = getEnemyConfig(enemy.enemyType)
      
      # Unpredictable teleporter with fake clones
      enemy.cloneTimer -= dt
      enemy.shootTimer += dt
      
      if enemy.cloneTimer <= 0:
        # Create 3 fake clone positions
        enemy.clonePositions = @[]
        for i in 0..<3:
          let angle = i.float32 * PI * 2.0 / 3.0
          let dist = 100.0 + rand(50.0)
          enemy.clonePositions.add(newVector2f(
            enemy.pos.x + cos(angle) * dist,
            enemy.pos.y + sin(angle) * dist
          ))
        
        # Teleport to random position near player
        let teleAngle = rand(1.0) * PI * 2.0
        let teleDist = 140.0 + rand(90.0)
        enemy.pos = newVector2f(
          playerPos.x + cos(teleAngle) * teleDist,
          playerPos.y + sin(teleAngle) * teleDist
        )
        
        enemy.cloneTimer = config.movement.teleportCooldown + rand(1.5)
      
      # Shoot from random clone or real position (uses config fire rate)
      if enemy.shootTimer > config.attack.fireRate:
        var shootPos = enemy.pos
        if enemy.clonePositions.len > 0 and rand(100) < 60:
          shootPos = enemy.clonePositions[rand(enemy.clonePositions.len - 1)]
        
        # Temporarily change position to shoot from clone, then restore
        let originalPos = enemy.pos
        enemy.pos = shootPos
        executeRangedAttack(enemy, playerPos, game)
        enemy.pos = originalPos
      
      # Erratic wobbling movement
      let dir = (playerPos - enemy.pos).normalize()
      let wobble = sin(currentTime * 5.0) * 0.7
      let wobbleDir = newVector2f(
        dir.x * cos(wobble) - dir.y * sin(wobble),
        dir.x * sin(wobble) + dir.y * cos(wobble)
      )
      let nextPos = enemy.pos + wobbleDir * effectiveSpeed * 0.7 * dt
      let hitWall = checkWallCollision(enemy, nextPos, walls, currentTime, game)
      if not hitWall:
        enemy.pos = nextPos
    
    of etSniper:
      # Sniper enemy - charges a powerful one-shot attack with warning
      let config = getEnemyConfig(enemy.enemyType)
      let specialData = parseSpecialData(config.specialData)
      let triggerRange = getSpecialFloat(specialData, "trigger_range", 300.0)
      let chargeTime = getSpecialFloat(specialData, "charge_time", 3.0)
      let cooldownTime = getSpecialFloat(specialData, "cooldown", 2.0)
      
      let distToPlayer = distance(enemy.pos, playerPos)
      
      case enemy.attackPhase
      of 0:  # Hunting phase - moves toward player
        let dir = (playerPos - enemy.pos).normalize()
        let nextPos = enemy.pos + dir * effectiveSpeed * 0.8 * dt
        var canMove = true
        for wall in walls:
          if distance(nextPos, wall.pos) < enemy.radius + wall.radius:
            canMove = false
            break
        if canMove:
          enemy.pos = nextPos
        
        # When close enough, start charging
        if distToPlayer < triggerRange:
          enemy.attackPhase = 1
          enemy.attackWarningTimer = 0
          enemy.attackExecuteTimer = chargeTime
      
      of 1:  # Charging phase - stands still, glows brighter
        enemy.attackWarningTimer += dt
        # Visual charging: change color intensity
        let chargeAmount = enemy.attackWarningTimer / enemy.attackExecuteTimer
        let intensity = uint8(150 + chargeAmount * 105)
        enemy.color = Color(r: intensity, g: 50, b: intensity, a: 255)
        
        # When charge completes, fire using centralized system
        if enemy.attackWarningTimer >= enemy.attackExecuteTimer:
          executeRangedAttack(enemy, playerPos, game)
          enemy.attackPhase = 2
          enemy.attackExecuteTimer = cooldownTime
          enemy.color = Color(r: 200, g: 50, b: 200, a: 255)  # Reset color
      
      of 2:  # Cooldown phase - recover before hunting again
        enemy.attackExecuteTimer -= dt
        if enemy.attackExecuteTimer <= 0:
          enemy.attackPhase = 0
      else:
        discard
    
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
        let damage = getSpecialInt(specialData, "damage", 3)
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
      
      # Check wall collisions
      var canMove = true
      for wall in walls:
        if distance(nextPos, wall.pos) < enemy.radius + wall.radius:
          canMove = false
          if currentTime - enemy.lastWallDamageTime >= 1.0:
            wall.takeDamage(1.0)
            trackWallDamaged(game)
            enemy.hp -= 1.0
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
  
  # Update all active effects for this enemy
  let effectDamage = updateEffects(enemy, dt)
  if effectDamage > 0:
    enemy.hp -= effectDamage
  
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
  
  return enemy.hp > 0

proc drawCustomBoss*(enemy: Enemy) =
  ## Draw unique visual representation for each of the 12 custom bosses
  let time = getTime()
  let pulse = sin(time * 2.0) * 0.5 + 0.5  # Pulse animation 0-1
  
  case enemy.bossDefinitionID
  of 1:  # Boss 1: The Spiral Guardian (Purple mystical entity)
    # Outer mystical ring
    let ringPulse = sin(time * 3.0) * 5.0
    drawCircle(Vector2(x: enemy.pos.x, y: enemy.pos.y), enemy.radius + 8 + ringPulse, 
               Color(r: 80, g: 40, b: 160, a: 80))
    
    # Main body - purple orb
    drawCircle(Vector2(x: enemy.pos.x, y: enemy.pos.y), enemy.radius, enemy.color)
    drawCircleLines(enemy.pos.x.int32, enemy.pos.y.int32, enemy.radius, Black)
    
    # Spiral pattern inside
    for i in 0..11:
      let angle = i.float32 * PI / 6.0 + time * 2.0
      let radius = enemy.radius * 0.6 * (1.0 - (i.float32 / 12.0))
      let x = enemy.pos.x + cos(angle) * radius
      let y = enemy.pos.y + sin(angle) * radius
      let size = 3.0 + pulse * 2.0
      drawCircle(Vector2(x: x, y: y), size, Color(r: 200, g: 150, b: 255, a: 200))
  
  of 2:  # Boss 2: The Summoner King (Green nature theme)
    # Leaf-like petal pattern
    for i in 0..7:
      let angle = i.float32 * PI / 4.0 + time * 0.5
      let petalDist = enemy.radius * 0.8
      let px = enemy.pos.x + cos(angle) * petalDist
      let py = enemy.pos.y + sin(angle) * petalDist
      drawCircle(Vector2(x: px, y: py), enemy.radius * 0.3, 
                Color(r: 100, g: 200, b: 100, a: 180))
    
    # Central body
    drawCircle(Vector2(x: enemy.pos.x, y: enemy.pos.y), enemy.radius * 0.7, enemy.color)
    drawCircleLines(enemy.pos.x.int32, enemy.pos.y.int32, enemy.radius * 0.7, Black)
    
    # Crown symbol
    for i in 0..4:
      let angle = i.float32 * PI * 2.0 / 5.0 - PI / 2.0
      let x1 = enemy.pos.x + cos(angle) * enemy.radius * 0.4
      let y1 = enemy.pos.y + sin(angle) * enemy.radius * 0.4
      let x2 = enemy.pos.x + cos(angle) * enemy.radius * 0.6
      let y2 = enemy.pos.y + sin(angle) * enemy.radius * 0.6
      drawLine(Vector2(x: x1, y: y1), Vector2(x: x2, y: y2), 3, 
              Color(r: 255, g: 215, b: 0, a: 255))
  
  of 3:  # Boss 3: The Meteor Striker (Orange/red fire theme)
    # Fiery outer glow
    let fireGlow = sin(time * 5.0) * 10.0
    drawCircle(Vector2(x: enemy.pos.x, y: enemy.pos.y), enemy.radius + 10 + fireGlow,
               Color(r: 255, g: 100, b: 0, a: 100))
    drawCircle(Vector2(x: enemy.pos.x, y: enemy.pos.y), enemy.radius + 5 + fireGlow * 0.5,
               Color(r: 255, g: 150, b: 0, a: 150))
    
    # Jagged meteor shape
    let points = 12
    for i in 0..<points:
      let angle = i.float32 * PI * 2.0 / points.float32
      let nextAngle = (i + 1).float32 * PI * 2.0 / points.float32
      let variation = if i mod 2 == 0: 1.0 else: 0.7  # Jagged edges
      let r1 = enemy.radius * variation
      let r2 = enemy.radius * (if (i + 1) mod 2 == 0: 1.0 else: 0.7)
      let x1 = enemy.pos.x + cos(angle) * r1
      let y1 = enemy.pos.y + sin(angle) * r1
      let x2 = enemy.pos.x + cos(nextAngle) * r2
      let y2 = enemy.pos.y + sin(nextAngle) * r2
      drawLine(Vector2(x: x1, y: y1), Vector2(x: x2, y: y2), 3, enemy.color)
    
    # Hot core
    drawCircle(Vector2(x: enemy.pos.x, y: enemy.pos.y), enemy.radius * 0.4,
               Color(r: 255, g: 255, b: 100, a: 255))
  
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
  
  of 5:  # Boss 5: The Void Dancer (Dark purple with void effects)
    # Void distortion rings
    for i in 1..3:
      let ringRadius = enemy.radius * (0.4 + i.float32 * 0.3)
      let ringAlpha = uint8(100 - i * 20)
      drawCircleLines(enemy.pos.x.int32, enemy.pos.y.int32, ringRadius,
                     Color(r: 80, g: 0, b: 120, a: ringAlpha))
    
    # Shadow trail effect
    let trailCount = 5
    for i in 1..trailCount:
      let trailAlpha = uint8(150 - i * 25)
      let trailX = enemy.pos.x - enemy.vel.x * i.float32 * 0.02
      let trailY = enemy.pos.y - enemy.vel.y * i.float32 * 0.02
      drawCircle(Vector2(x: trailX, y: trailY), enemy.radius * 0.8,
                Color(r: 120, g: 0, b: 180, a: trailAlpha))
    
    # Main dark orb
    drawCircle(Vector2(x: enemy.pos.x, y: enemy.pos.y), enemy.radius, enemy.color)
    drawCircleLines(enemy.pos.x.int32, enemy.pos.y.int32, enemy.radius, 
                   Color(r: 160, g: 40, b: 220, a: 255))
    
    # Void core
    drawCircle(Vector2(x: enemy.pos.x, y: enemy.pos.y), enemy.radius * 0.3,
               Color(r: 0, g: 0, b: 0, a: 200))
  
  of 6:  # Boss 6: The Chain Reactor (Electric yellow/white)
    # Electric sparks around boss
    let sparkCount = 8
    for i in 0..<sparkCount:
      let angle = i.float32 * PI * 2.0 / sparkCount.float32 + time * 5.0
      let sparkDist = enemy.radius + 10 + sin(time * 10.0 + i.float32) * 5
      let sparkX = enemy.pos.x + cos(angle) * sparkDist
      let sparkY = enemy.pos.y + sin(angle) * sparkDist
      drawCircle(Vector2(x: sparkX, y: sparkY), 3, 
                Color(r: 255, g: 255, b: 100, a: 200))
      # Lightning bolt to spark
      drawLine(Vector2(x: enemy.pos.x, y: enemy.pos.y),
              Vector2(x: sparkX, y: sparkY), 2,
              Color(r: 255, g: 255, b: 200, a: 150))
    
    # Electric core with pulsing
    let electricPulse = enemy.radius + sin(time * 8.0) * 5
    drawCircle(Vector2(x: enemy.pos.x, y: enemy.pos.y), electricPulse,
               Color(r: 255, g: 255, b: 0, a: 180))
    drawCircle(Vector2(x: enemy.pos.x, y: enemy.pos.y), enemy.radius * 0.6, enemy.color)
    drawCircleLines(enemy.pos.x.int32, enemy.pos.y.int32, enemy.radius * 0.6, White)
    
    # Bright electric center
    drawCircle(Vector2(x: enemy.pos.x, y: enemy.pos.y), enemy.radius * 0.3,
               Color(r: 255, g: 255, b: 255, a: 255))
  
  of 7:  # Boss 7: The Orbital Commander (Purple/blue space theme)
    # Orbital rings
    for i in 1..3:
      let ringRadius = enemy.radius * (0.5 + i.float32 * 0.4)
      let ringRotation = time * (i.float32 * 0.5)
      # Draw orbital ring as dashed circle
      for j in 0..23:
        let angle = j.float32 * PI / 12.0 + ringRotation
        let nextAngle = (j.float32 + 0.5).float32 * PI / 12.0 + ringRotation
        let x1 = enemy.pos.x + cos(angle) * ringRadius
        let y1 = enemy.pos.y + sin(angle) * ringRadius
        let x2 = enemy.pos.x + cos(nextAngle) * ringRadius
        let y2 = enemy.pos.y + sin(nextAngle) * ringRadius
        drawLine(Vector2(x: x1, y: y1), Vector2(x: x2, y: y2), 2,
                Color(r: 150, g: 100, b: 255, a: 180))
    
    # Satellite markers on rings
    for i in 0..2:
      let angle = time * (1.0 + i.float32) + i.float32 * PI / 1.5
      let dist = enemy.radius * (1.0 + i.float32 * 0.4)
      let satX = enemy.pos.x + cos(angle) * dist
      let satY = enemy.pos.y + sin(angle) * dist
      drawCircle(Vector2(x: satX, y: satY), 4, 
                Color(r: 200, g: 150, b: 255, a: 255))
    
    # Central command hub
    drawCircle(Vector2(x: enemy.pos.x, y: enemy.pos.y), enemy.radius * 0.6, enemy.color)
    drawCircleLines(enemy.pos.x.int32, enemy.pos.y.int32, enemy.radius * 0.6, 
                   Color(r: 200, g: 150, b: 255, a: 255))
    drawCircle(Vector2(x: enemy.pos.x, y: enemy.pos.y), enemy.radius * 0.3,
               Color(r: 150, g: 100, b: 255, a: 255))
  
  of 8:  # Boss 8: The Berserker Juggernaut (Red rage theme)
    # Rage aura - intensity based on HP
    let hpPercent = enemy.hp / enemy.maxHp
    let rageIntensity = 1.0 - hpPercent  # More rage at low HP
    let auraSize = enemy.radius + 15 + rageIntensity * 10
    let auraAlpha = uint8(80 + rageIntensity * 100)
    
    drawCircle(Vector2(x: enemy.pos.x, y: enemy.pos.y), auraSize,
               Color(r: 255, g: 0, b: 0, a: auraAlpha))
    drawCircle(Vector2(x: enemy.pos.x, y: enemy.pos.y), auraSize * 0.7,
               Color(r: 255, g: 50, b: 0, a: auraAlpha))
    
    # Muscular/bulky shape - overlapping circles
    let bulkOffset = enemy.radius * 0.4
    drawCircle(Vector2(x: enemy.pos.x - bulkOffset, y: enemy.pos.y), enemy.radius * 0.7,
               enemy.color)
    drawCircle(Vector2(x: enemy.pos.x + bulkOffset, y: enemy.pos.y), enemy.radius * 0.7,
               enemy.color)
    drawCircle(Vector2(x: enemy.pos.x, y: enemy.pos.y), enemy.radius * 0.8, enemy.color)
    
    # Angry core
    drawCircle(Vector2(x: enemy.pos.x, y: enemy.pos.y), enemy.radius * 0.4,
               Color(r: 150, g: 0, b: 0, a: 255))
    
    # Rage veins
    for i in 0..5:
      let angle = i.float32 * PI / 3.0 + time * 2.0
      let x1 = enemy.pos.x + cos(angle) * (enemy.radius * 0.4)
      let y1 = enemy.pos.y + sin(angle) * (enemy.radius * 0.4)
      let x2 = enemy.pos.x + cos(angle) * (enemy.radius * 0.7)
      let y2 = enemy.pos.y + sin(angle) * (enemy.radius * 0.7)
      drawLine(Vector2(x: x1, y: y1), Vector2(x: x2, y: y2), 2,
              Color(r: 180, g: 0, b: 0, a: 255))
  
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
  
  of 10:  # Boss 10: The Timekeeper (Cyan time theme)
    # Time distortion waves
    for i in 1..4:
      let waveRadius = enemy.radius * (0.3 + i.float32 * 0.3)
      let waveTime = time * 2.0 - i.float32 * 0.5
      let waveAlpha = uint8(abs(sin(waveTime)) * 150)
      drawCircleLines(enemy.pos.x.int32, enemy.pos.y.int32, waveRadius,
                     Color(r: 0, g: 180, b: 180, a: waveAlpha))
    
    # Clock face
    drawCircle(Vector2(x: enemy.pos.x, y: enemy.pos.y), enemy.radius * 0.9, enemy.color)
    drawCircleLines(enemy.pos.x.int32, enemy.pos.y.int32, enemy.radius * 0.9, 
                   Color(r: 0, g: 220, b: 220, a: 255))
    
    # Clock hands
    let minuteAngle = time * 0.5
    let hourAngle = time * 0.1
    drawLine(Vector2(x: enemy.pos.x, y: enemy.pos.y),
            Vector2(x: enemy.pos.x + cos(minuteAngle) * enemy.radius * 0.7,
                    y: enemy.pos.y + sin(minuteAngle) * enemy.radius * 0.7),
            3, Color(r: 100, g: 255, b: 255, a: 255))
    drawLine(Vector2(x: enemy.pos.x, y: enemy.pos.y),
            Vector2(x: enemy.pos.x + cos(hourAngle) * enemy.radius * 0.5,
                    y: enemy.pos.y + sin(hourAngle) * enemy.radius * 0.5),
            4, Color(r: 150, g: 255, b: 255, a: 255))
    
    # Time core
    drawCircle(Vector2(x: enemy.pos.x, y: enemy.pos.y), enemy.radius * 0.15,
               Color(r: 0, g: 255, b: 255, a: 255))
  
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
    # Fallback for any undefined boss - simple circle
    drawCircle(Vector2(x: enemy.pos.x, y: enemy.pos.y), enemy.radius, enemy.color)
    drawCircleLines(enemy.pos.x.int32, enemy.pos.y.int32, enemy.radius, Black)
    drawCircle(Vector2(x: enemy.pos.x, y: enemy.pos.y), enemy.radius * 0.3, White)

proc drawEnemy*(enemy: Enemy) =
  if enemy.isBoss:
    # Boss drawing - unique visuals for each of the 12 custom bosses
    drawCustomBoss(enemy)
    
    # HP bar (common to all bosses)
    let barWidth = enemy.radius * 2.5
    let barHeight = 8.0
    let hpPercent = enemy.hp / enemy.maxHp
    drawRectangle((enemy.pos.x - enemy.radius * 1.25).int32, (enemy.pos.y - enemy.radius - 16).int32, 
                  barWidth.int32, barHeight.int32, Red)
    drawRectangle((enemy.pos.x - enemy.radius * 1.25).int32, (enemy.pos.y - enemy.radius - 16).int32, 
                  (barWidth * hpPercent).int32, barHeight.int32, Green)
  else:
    case enemy.enemyType
    of etCircle:
      drawCircle(Vector2(x: enemy.pos.x, y: enemy.pos.y), enemy.radius, enemy.color)
      drawCircleLines(enemy.pos.x.int32, enemy.pos.y.int32, enemy.radius, Black)
    
    of etCube:
      # Use radius directly, not 1.4x multiplier
      let size = enemy.radius
      drawRectangle((enemy.pos.x - size).int32, (enemy.pos.y - size).int32, 
                    (size * 2).int32, (size * 2).int32, enemy.color)
      drawRectangleLines((enemy.pos.x - size).int32, (enemy.pos.y - size).int32, 
                         (size * 2).int32, (size * 2).int32, Black)
    
    of etTriangle:
      if enemy.dashTimer > 1.5:
        for i in 1..5:
          let trailAlpha = uint8(180 - i * 30)
          let trailScale = 1.0 - (i.float32 * 0.15)
          let trailX = enemy.pos.x - enemy.vel.x * i.float32 * 0.02
          let trailY = enemy.pos.y - enemy.vel.y * i.float32 * 0.02
          let r = enemy.radius * trailScale
          let tv1 = Vector2(x: trailX, y: trailY - r)
          let tv2 = Vector2(x: trailX - r * 0.87, y: trailY + r * 0.5)
          let tv3 = Vector2(x: trailX + r * 0.87, y: trailY + r * 0.5)
          drawTriangle(tv1, tv2, tv3, Color(r: enemy.color.r, g: enemy.color.g, b: enemy.color.b, a: trailAlpha))
      let v1 = Vector2(x: enemy.pos.x, y: enemy.pos.y - enemy.radius)
      let v2 = Vector2(x: enemy.pos.x - enemy.radius * 0.87, y: enemy.pos.y + enemy.radius * 0.5)
      let v3 = Vector2(x: enemy.pos.x + enemy.radius * 0.87, y: enemy.pos.y + enemy.radius * 0.5)
      drawTriangle(v1, v2, v3, enemy.color)
      drawTriangleLines(v1, v2, v3, Black)
      if enemy.dashTimer < 0.5 and enemy.dashTimer > 0:
        let chargePercent = 1.0 - (enemy.dashTimer / 0.5)
        let glowIntensity = uint8(chargePercent * 200)
        drawCircle(Vector2(x: enemy.pos.x, y: enemy.pos.y), enemy.radius + 5, 
                  Color(r: 255'u8, g: 100'u8, b: 255'u8, a: glowIntensity))
    
    of etStar:
      # Subtle pulsing glow animation
      let pulseIntensity = sin(getTime() * 3.0) * 0.3 + 0.5  # Smooth pulse between 0.5-0.8
      let glowAlpha = uint8(pulseIntensity * 80)  # Max 64 alpha (was much higher)
      
      # Multiple glow layers for softer effect
      drawCircle(Vector2(x: enemy.pos.x, y: enemy.pos.y), enemy.radius + 12,
                Color(r: 255'u8, g: 215'u8, b: 0'u8, a: glowAlpha))
      drawCircle(Vector2(x: enemy.pos.x, y: enemy.pos.y), enemy.radius + 6,
                Color(r: 255'u8, g: 215'u8, b: 0'u8, a: uint8(glowAlpha.float32 * 1.5)))
      
      # Dash charge indicator (overrides normal glow when charging)
      if enemy.dashCooldown < 0.5:
        let chargePercent = 1.0 - (enemy.dashCooldown / 0.5)
        let chargeGlow = uint8(chargePercent * 150)
        drawCircle(Vector2(x: enemy.pos.x, y: enemy.pos.y), enemy.radius + 8, 
                  Color(r: 255'u8, g: 200'u8, b: 0'u8, a: chargeGlow))
      
      # Draw star shape
      let points = 5
      for i in 0..<points*2:
        let angle = i.float32 * PI / points.float32
        let r = if i mod 2 == 0: enemy.radius else: enemy.radius * 0.5
        let x = enemy.pos.x + cos(angle) * r
        let y = enemy.pos.y + sin(angle) * r
        if i == 0:
          continue
        let prevAngle = (i-1).float32 * PI / points.float32
        let prevR = if (i-1) mod 2 == 0: enemy.radius else: enemy.radius * 0.5
        let prevX = enemy.pos.x + cos(prevAngle) * prevR
        let prevY = enemy.pos.y + sin(prevAngle) * prevR
        drawLine(Vector2(x: prevX, y: prevY), Vector2(x: x, y: y), 2, enemy.color)
      
      # Hit counter
      let remaining = enemy.requiredHits - enemy.hitCount
      let text = $remaining
      let textWidth = measureText(text, 14)
      drawText(text, (enemy.pos.x - textWidth / 2).int32, (enemy.pos.y - 7).int32, 14, Black)
    
    of etHexagon:
      let points = 6
      for i in 0..<points:
        let angle = i.float32 * PI / 3.0
        let nextAngle = (i + 1).float32 * PI / 3.0
        let x1 = enemy.pos.x + cos(angle) * enemy.radius
        let y1 = enemy.pos.y + sin(angle) * enemy.radius
        let x2 = enemy.pos.x + cos(nextAngle) * enemy.radius
        let y2 = enemy.pos.y + sin(nextAngle) * enemy.radius
        drawLine(Vector2(x: x1, y: y1), Vector2(x: x2, y: y2), 2, enemy.color)
      if enemy.hexTeleportTimer < 0.5:
        let glowAlpha = ((enemy.hexTeleportTimer * 4.0).int mod 2) * 150
        drawCircle(Vector2(x: enemy.pos.x, y: enemy.pos.y), enemy.radius + 5, 
                  Color(r: 255, g: 255, b: 0, a: glowAlpha.uint8))
    
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
      # Draw diamond shape
      let v1 = Vector2(x: enemy.pos.x, y: enemy.pos.y - enemy.radius)
      let v2 = Vector2(x: enemy.pos.x + enemy.radius, y: enemy.pos.y)
      let v3 = Vector2(x: enemy.pos.x, y: enemy.pos.y + enemy.radius)
      let v4 = Vector2(x: enemy.pos.x - enemy.radius, y: enemy.pos.y)
      drawLine(v1, v2, 3, enemy.color)
      drawLine(v2, v3, 3, enemy.color)
      drawLine(v3, v4, 3, enemy.color)
      drawLine(v4, v1, 3, enemy.color)
      drawCircle(Vector2(x: enemy.pos.x, y: enemy.pos.y), enemy.radius * 0.3, enemy.color)
      # Dash indicator
      if enemy.dashCooldown < 0.5:
        let glowAlpha = ((enemy.dashCooldown * 6.0).int mod 2) * 150 + 50
        drawCircle(Vector2(x: enemy.pos.x, y: enemy.pos.y), enemy.radius + 6,
                  Color(r: 0, g: 255, b: 255, a: glowAlpha.uint8))
    
    of etOctagon:
      # Draw octagon
      let points = 8
      for i in 0..<points:
        let angle = i.float32 * PI / 4.0
        let nextAngle = (i + 1).float32 * PI / 4.0
        let x1 = enemy.pos.x + cos(angle) * enemy.radius
        let y1 = enemy.pos.y + sin(angle) * enemy.radius
        let x2 = enemy.pos.x + cos(nextAngle) * enemy.radius
        let y2 = enemy.pos.y + sin(nextAngle) * enemy.radius
        drawLine(Vector2(x: x1, y: y1), Vector2(x: x2, y: y2), 2, enemy.color)
      drawCircle(Vector2(x: enemy.pos.x, y: enemy.pos.y), enemy.radius * 0.4, enemy.color)
      # Constant firing glow
      let fireGlow = uint8((sin(getTime() * 10.0) * 0.3 + 0.7) * 100)
      drawCircleLines(enemy.pos.x.int32, enemy.pos.y.int32, enemy.radius + 4,
                     Color(r: 255, g: 255, b: 0, a: fireGlow))
    
    of etPentagon:
      # Draw pentagon
      let points = 5
      for i in 0..<points:
        let angle = i.float32 * PI * 2.0 / 5.0 - PI / 2.0
        let nextAngle = (i + 1).float32 * PI * 2.0 / 5.0 - PI / 2.0
        let x1 = enemy.pos.x + cos(angle) * enemy.radius
        let y1 = enemy.pos.y + sin(angle) * enemy.radius
        let x2 = enemy.pos.x + cos(nextAngle) * enemy.radius
        let y2 = enemy.pos.y + sin(nextAngle) * enemy.radius
        drawLine(Vector2(x: x1, y: y1), Vector2(x: x2, y: y2), 3, enemy.color)
      drawCircle(Vector2(x: enemy.pos.x, y: enemy.pos.y), enemy.radius * 0.35, enemy.color)
      # Charge-up glow when about to fire
      if enemy.shootTimer > 2.0:
        let chargePercent = (enemy.shootTimer - 2.0) / 0.5
        let glowIntensity = uint8(chargePercent * 200)
        drawCircle(Vector2(x: enemy.pos.x, y: enemy.pos.y), enemy.radius + 7,
                  Color(r: 0, g: 255, b: 150, a: glowIntensity))
    
    of etTrickster:
      # Draw trickster with deceptive appearance
      let segments = 6
      for i in 0..<segments:
        let angle = i.float32 * PI * 2.0 / segments.float32 + getTime()
        let nextAngle = (i + 1).float32 * PI * 2.0 / segments.float32 + getTime()
        let r = if i mod 2 == 0: enemy.radius * 0.8 else: enemy.radius
        let nextR = if (i + 1) mod 2 == 0: enemy.radius * 0.8 else: enemy.radius
        let x1 = enemy.pos.x + cos(angle) * r
        let y1 = enemy.pos.y + sin(angle) * r
        let x2 = enemy.pos.x + cos(nextAngle) * nextR
        let y2 = enemy.pos.y + sin(nextAngle) * nextR
        drawLine(Vector2(x: x1, y: y1), Vector2(x: x2, y: y2), 2, enemy.color)
      drawCircle(Vector2(x: enemy.pos.x, y: enemy.pos.y), enemy.radius * 0.3, enemy.color)
      # Mysterious pulse
      let mysterPulse = sin(getTime() * 4.0) * 10 + 15
      drawCircleLines(enemy.pos.x.int32, enemy.pos.y.int32, enemy.radius + mysterPulse,
                     Color(r: 255, g: 0, b: 255, a: 100))
    
    of etSniper:
      # Draw sniper with charging visualization
      # Main body - circular with crosshair
      drawCircle(Vector2(x: enemy.pos.x, y: enemy.pos.y), enemy.radius, enemy.color)
      
      # Crosshair pattern
      let crossSize = enemy.radius * 0.6
      drawLine(Vector2(x: enemy.pos.x - crossSize, y: enemy.pos.y),
              Vector2(x: enemy.pos.x + crossSize, y: enemy.pos.y), 2,
              Color(r: 255, g: 255, b: 255, a: 200))
      drawLine(Vector2(x: enemy.pos.x, y: enemy.pos.y - crossSize),
              Vector2(x: enemy.pos.x, y: enemy.pos.y + crossSize), 2,
              Color(r: 255, g: 255, b: 255, a: 200))
      
      # Center dot
      drawCircle(Vector2(x: enemy.pos.x, y: enemy.pos.y), 3.0, Red)
      
      # Charging effect - expanding rings when charging
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
      # Draw phantom with transparency
      drawCircle(Vector2(x: enemy.pos.x, y: enemy.pos.y), enemy.radius, enemy.color)
      # Fade effect
      let fadeRing = sin(getTime() * 3.0) * 8 + 12
      drawCircleLines(enemy.pos.x.int32, enemy.pos.y.int32, enemy.radius + fadeRing,
                     Color(r: 150, g: 150, b: 255, a: 120))
      # Draw fake clones
      for clonePos in enemy.clonePositions:
        let cloneAlpha = uint8((sin(getTime() * 5.0) * 0.5 + 0.5) * 120)
        drawCircle(Vector2(x: clonePos.x, y: clonePos.y), enemy.radius * 0.7,
                  Color(r: enemy.color.r, g: enemy.color.g, b: enemy.color.b, a: cloneAlpha))
    
    of etMage:
      # Draw mage with magical floating effect
      # Floating animation (vertical bob)
      let floatOffset = sin(getTime() * 2.0) * 4.0
      let centerY = enemy.pos.y + floatOffset
      
      # Magical aura (outer glow)
      let auraRadius = enemy.radius + 8
      let auraPulse = (sin(getTime() * 4.0) * 0.3 + 0.7)
      drawCircle(Vector2(x: enemy.pos.x, y: centerY), auraRadius, 
                Color(r: 138, g: 43, b: 226, a: uint8(60 * auraPulse)))
      
      # Main body (purple circle)
      drawCircle(Vector2(x: enemy.pos.x, y: centerY), enemy.radius, enemy.color)
      drawCircleLines(enemy.pos.x.int32, centerY.int32, enemy.radius, 
                     Color(r: 186, g: 85, b: 211, a: 255))
      
      # Magic staff/wand (small line extending from body)
      let staffAngle = getTime() * 1.5
      let staffLength = enemy.radius * 0.8
      let staffEndX = enemy.pos.x + cos(staffAngle) * staffLength
      let staffEndY = centerY + sin(staffAngle) * staffLength
      drawLine(Vector2(x: enemy.pos.x, y: centerY),
              Vector2(x: staffEndX, y: staffEndY), 3,
              Color(r: 200, g: 150, b: 255, a: 255))
      # Staff orb
      drawCircle(Vector2(x: staffEndX, y: staffEndY), 4, 
                Color(r: 255, g: 200, b: 255, a: 255))
      
      # Orbiting magic runes (3 runes)
      for i in 0..2:
        let runeAngle = getTime() * 2.0 + (i.float32 * PI * 2.0 / 3.0)
        let runeDist = enemy.radius + 12
        let runeX = enemy.pos.x + cos(runeAngle) * runeDist
        let runeY = centerY + sin(runeAngle) * runeDist
        drawCircle(Vector2(x: runeX, y: runeY), 3, 
                  Color(r: 255, g: 150, b: 255, a: 200))
        # Rune glow
        drawCircleLines(runeX.int32, runeY.int32, 4, 
                       Color(r: 200, g: 100, b: 255, a: 150))
      
      # Magic particles floating upward
      for i in 0..4:
        let particleTime = getTime() * 1.5 + i.float32
        let particleY = centerY - (particleTime mod 20.0) * 2.0
        let particleX = enemy.pos.x + sin(particleTime) * 8.0
        let particleAlpha = uint8(255 - ((particleTime mod 20.0) / 20.0) * 255)
        drawCircle(Vector2(x: particleX, y: particleY), 2, 
                  Color(r: 200, g: 100, b: 255, a: particleAlpha))
      
      # Casting indicator when shooting
      if enemy.shootTimer > 2.0:  # About to shoot
        let chargeGlow = (sin((enemy.shootTimer - 2.0) * 10.0) * 0.5 + 0.5)
        drawCircleLines(enemy.pos.x.int32, centerY.int32, enemy.radius + 6,
                       Color(r: 255, g: 100, b: 255, a: uint8(150 * chargeGlow)))

proc drawAttackWarning*(warning: AttackWarning) =
  let alpha = uint8((warning.lifetime / warning.maxLifetime) * 200)
  let pulse = sin(getTime() * 20.0) * 5 + 10
  
  case warning.attackType
  of "cross":
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
  of "burst":
    # Draw circular burst warning
    drawCircleLines(warning.pos.x.int32, warning.pos.y.int32, 50.0 + pulse,
                   Color(r: 255, g: 100, b: 0, a: alpha))
    drawCircleLines(warning.pos.x.int32, warning.pos.y.int32, 70.0 + pulse,
                   Color(r: 255, g: 100, b: 0, a: (alpha div 2).uint8))
  of "fake":
    # Draw deceptive warning (looks dangerous but isn't)
    drawCircleLines(warning.pos.x.int32, warning.pos.y.int32, 40.0 + pulse,
                   Color(r: 255, g: 255, b: 0, a: alpha))
    drawText("!", (warning.pos.x - 8).int32, (warning.pos.y - 12).int32, 24,
            Color(r: 255, g: 255, b: 0, a: alpha))
  
  of "boss_laser":
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
  
  of "satellite_laser":
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
  
  else:
    discard

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

proc spawnEnemy*(screenWidth, screenHeight: int32, difficulty: float32, game: Game): Enemy =
  let side = rand(3)
  var x, y: float32
  
  case side
  of 0: x = rand(screenWidth.int).float32; y = -30
  of 1: x = screenWidth.float32 + 30; y = rand(screenHeight.int).float32
  of 2: x = rand(screenWidth.int).float32; y = screenHeight.float32 + 30
  else: x = -30; y = rand(screenHeight.int).float32
  
  # PROGRESSIVE DIFFICULTY SYSTEM
  let roll = rand(100)
  var enemyType: EnemyType
  
  if difficulty < 2.0:
    # Phase 1: Only circles
    enemyType = etCircle
  elif difficulty < 5.0:
    # Phase 2: Circles + Pentagon
    if roll < 80: enemyType = etCircle
    else: enemyType = etPentagon
  elif difficulty < 8.0:
    # Phase 3: Add Triangles + Cubes start appearing
    if roll < 60: enemyType = etCircle
    elif roll < 80: enemyType = etPentagon
    elif roll < 90: enemyType = etTriangle
    else: enemyType = etCube
  elif difficulty < 11.0:
    # Phase 4: Add Stars + Cross, Cubes more common
    if roll < 40: enemyType = etCircle
    elif roll < 55: enemyType = etPentagon
    elif roll < 65: enemyType = etCube
    elif roll < 80: enemyType = etTriangle
    elif roll < 90: enemyType = etStar
    else: enemyType = etCross
  elif difficulty < 14.0:
    # Phase 5: Add Diamond + Octagon
    if roll < 25: enemyType = etCircle
    elif roll < 38: enemyType = etPentagon
    elif roll < 50: enemyType = etCube
    elif roll < 62: enemyType = etTriangle
    elif roll < 75: enemyType = etStar
    elif roll < 83: enemyType = etCross
    elif roll < 91: enemyType = etDiamond
    else: enemyType = etOctagon
  elif difficulty < 18.0:
    # Phase 6: Add Hexagon
    if roll < 18: enemyType = etCircle
    elif roll < 30: enemyType = etPentagon
    elif roll < 42: enemyType = etCube
    elif roll < 54: enemyType = etTriangle
    elif roll < 66: enemyType = etStar
    elif roll < 74: enemyType = etCross
    elif roll < 82: enemyType = etDiamond
    elif roll < 91: enemyType = etOctagon
    else: enemyType = etHexagon
  elif difficulty < 23.0:
    # Phase 7: Add Trickster
    if roll < 12: enemyType = etCircle
    elif roll < 22: enemyType = etPentagon
    elif roll < 32: enemyType = etCube
    elif roll < 42: enemyType = etTriangle
    elif roll < 54: enemyType = etStar
    elif roll < 63: enemyType = etCross
    elif roll < 72: enemyType = etDiamond
    elif roll < 82: enemyType = etOctagon
    elif roll < 91: enemyType = etHexagon
    else: enemyType = etTrickster
  else:
    # Phase 8: All enemies including Phantom, Mage, and rare Sniper
    if roll < 8: enemyType = etCircle
    elif roll < 15: enemyType = etPentagon
    elif roll < 22: enemyType = etCube
    elif roll < 29: enemyType = etTriangle
    elif roll < 38: enemyType = etStar
    elif roll < 45: enemyType = etCross
    elif roll < 52: enemyType = etDiamond
    elif roll < 60: enemyType = etOctagon
    elif roll < 68: enemyType = etHexagon
    elif roll < 78: enemyType = etTrickster
    elif roll < 88: enemyType = etPhantom
    elif roll < 98: enemyType = etMage  # 10% chance - powerful magic user
    else: enemyType = etSniper  # Very rare 2% chance
  
  newEnemy(x, y, difficulty, enemyType, game)

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
    case (bossDef.bossID - 1) mod 4
    of 0:  # From top
      targetX = centerX; targetY = centerY - 80
      startX = centerX; startY = -100
    of 1:  # From bottom
      targetX = centerX; targetY = centerY + 80
      startX = centerX; startY = screenHeight.float32 + 100
    of 2:  # From left
      targetX = centerX - 100; targetY = centerY
      startX = -100; startY = centerY
    of 3:  # From right
      targetX = centerX + 100; targetY = centerY
      startX = screenWidth.float32 + 100; startY = centerY
    else:
      targetX = centerX; targetY = centerY
      startX = centerX; startY = -100
    
    # Create boss with custom stats
    let scaledHP = getScaledBossHP(bossDef, waveNumber)
    let scaledSpeed = getScaledBossSpeed(bossDef, waveNumber)
    let scaledDamage = getScaledBossDamage(bossDef, waveNumber)
    
    # Initialize attack timers for first phase
    var initialAttackTimers: seq[float32] = @[]
    if bossDef.phases.len > 0:
      for attack in bossDef.phases[0].attacks:
        initialAttackTimers.add(attack.cooldown)  # Start with cooldown so attacks don't fire immediately
    
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
      hp: scaledHP,
      maxHp: scaledHP,
      speed: firstPhaseSpeed,  # Apply speedMultiplier from first phase
      contactDamage: scaledDamage,  # Boss contact damage
      rangedDamage: scaledDamage,   # Boss ranged damage
      color: bossDef.color,
      enemyType: etCircle,
      isBoss: true,
      bossDefinitionID: bossDef.bossID,
      currentPhaseIndex: 0,
      attackTimers: initialAttackTimers,
      startPos: newVector2f(startX, startY),
      shootTimer: 0,
      spawnTimer: 0,
      dashTimer: 0,
      hitCount: 0,
      requiredHits: 0,
      lastContactDamageTime: 0,
      teleportTimer: 10.0,
      shockwaveTimer: 8.0,
      burstTimer: 0.5,
      lastWallDamageTime: 0,
      entranceTimer: 1.0,
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
      activeEffects: initTable[ElementType, ActiveEffect]()
    )

proc makeElite*(enemy: Enemy, waveNumber: int = 0) =
  ## Converts a regular enemy into an elite with enhanced stats and special abilities
  ## Elite chance increases with wave number: base 3% + 0.5% per wave (capped at 15%)
  ## At wave 25+, elites can have multiple effects (2-3 types combined)
  ## BALANCED: Multiple effects apply with diminishing returns to prevent exponential growth
  
  # Don't make bosses elite
  if enemy.isBoss:
    return
  
  # Calculate elite chance based on wave (3% + 0.5% per wave, max 15%)
  let eliteChance = min(3 + (waveNumber.float32 * 0.5).int, 15)
  if rand(99) >= eliteChance:
    return
  
  enemy.isElite = true
  enemy.eliteAuraPhase = 0.0
  enemy.eliteTypes = @[]  # Initialize empty list for multiple types
  
  # Elite scaling multiplier based on wave (7.5% per wave for HP/damage)
  let eliteScaling = 1.0 + (waveNumber.float32 * 0.075)
  # Reduced speed scaling for elites (2.5% per wave instead of 7.5%)
  let eliteSpeedScaling = 1.0 + (waveNumber.float32 * 0.025)
  
  # Determine number of elite effects based on wave
  # BALANCED: Max 2 effects for wave 25+, not 3 (reduces exponential stacking)
  let numEffects = if waveNumber >= 25:
    # Waves 25+: 1-2 effects (50% for dual effect)
    if rand(99) < 50: 2 else: 1
  else:
    # Waves 1-24: Single effect
    1
  
  # Choose random elite types (ensure no duplicates)
  # STAR ENEMY RESTRICTION: Stars cannot get Tank, Shielded, or Regenerative (they're already tanky)
  var availableTypes = if enemy.enemyType == etStar:
    @[etSwift, etVenomous, etExplosive]  # Exclude Tank, Shielded, and Regenerative
  else:
    @[etSwift, etTank, etVenomous, etExplosive, etRegenerative, etShielded]
  
  for i in 0..<numEffects:
    if availableTypes.len == 0:
      break
    let idx = rand(availableTypes.len - 1)
    enemy.eliteTypes.add(availableTypes[idx])
    availableTypes.delete(idx)
  
  # For backward compatibility, set primary eliteType to first in list
  enemy.eliteType = if enemy.eliteTypes.len > 0: enemy.eliteTypes[0] else: etNone
  
  # Multiplier for multiple effects (diminishing returns)
  # 1 effect = 100%, 2 effects = 75% effectiveness to prevent stacking exponentially
  let effectMultiplier = if enemy.eliteTypes.len >= 2: 0.75 else: 1.0
  
  # BASE ELITE BONUS: All elites get a base stat increase
  # This represents them being fundamentally stronger than normal enemies
  let baseEliteBonus = 1.3  # 30% base bonus to all stats
  enemy.maxHp *= baseEliteBonus
  enemy.hp *= baseEliteBonus
  enemy.contactDamage = (enemy.contactDamage.float32 * baseEliteBonus).int
  enemy.rangedDamage = (enemy.rangedDamage.float32 * baseEliteBonus).int
  
  # Apply elite modifications for ALL types in the list
  for eType in enemy.eliteTypes:
    case eType
    of etSwift:
      # 33% faster movement (reduced from 40%) + reduced speed scaling
      enemy.speed *= (1.33 * eliteSpeedScaling * effectMultiplier)
      # Cap speed increase
      let maxSpeed = 1000.0
      if enemy.speed > maxSpeed:
        enemy.speed = maxSpeed
      enemy.shootTimer *= 0.6  # Faster shooting
      if enemy.dashCooldown > 0:
        enemy.dashCooldown *= 0.65
      # Swift elites are smaller
      enemy.radius *= 0.9
      enemy.collisionRadius *= 0.9
      enemy.contactDamage += 1 + (waveNumber div 5)
      enemy.rangedDamage += 1 + (waveNumber div 5)
      enemy.maxHp *= (0.85 * eliteScaling)  # Reduced from 0.9
      enemy.hp *= (0.85 * eliteScaling)
    
    of etTank:
      # BALANCED: 3.2x HP with reduced damage reduction
      # Multiple effects further reduce HP scaling
      enemy.maxHp *= (3.2 * eliteScaling * effectMultiplier)
      enemy.hp *= (3.2 * eliteScaling * effectMultiplier)
      enemy.speed *= 0.75  # Slower
      # Tank elites are larger
      enemy.radius *= 1.3
      enemy.collisionRadius *= 1.3
      enemy.contactDamage += waveNumber div 5
      enemy.rangedDamage += waveNumber div 5
    
    of etVenomous:
      # Poisons player on contact
      # Balanced growth with reduced speed scaling
      enemy.speed *= (1.15 * eliteSpeedScaling * effectMultiplier)  # Uses speed scaling
      enemy.contactDamage += 2 + (waveNumber div 7)
      enemy.rangedDamage += 2 + (waveNumber div 7)
      enemy.maxHp *= (1.5 * eliteScaling * effectMultiplier)  # Uses normal scaling
      enemy.hp *= (1.5 * eliteScaling * effectMultiplier)
    
    of etExplosive:
      # Explodes on death
      # Multiple effects reduce HP scaling but use reduced speed scaling
      enemy.maxHp *= (2.1 * eliteScaling * effectMultiplier)
      enemy.hp *= (2.1 * eliteScaling * effectMultiplier)
      enemy.contactDamage += 2 + (waveNumber div 7)
      enemy.rangedDamage += 2 + (waveNumber div 7)
      enemy.speed *= (1.0 * eliteSpeedScaling * effectMultiplier)
    
    of etRegenerative:
      # Regenerates 5% HP per second
      enemy.regenTimer = 0.0
      # Multiple effects reduce HP scaling
      enemy.maxHp *= (2.0 * eliteScaling * effectMultiplier)
      enemy.hp *= (2.0 * eliteScaling * effectMultiplier)
      enemy.contactDamage += 1 + (waveNumber div 5)
      enemy.rangedDamage += 1 + (waveNumber div 5)
    
    of etShielded:
      # Has a shield that absorbs damage
      # Multiple effects reduce HP and shield scaling
      enemy.maxHp *= (1.2 * eliteScaling * effectMultiplier)
      enemy.hp *= (1.2 * eliteScaling * effectMultiplier)
      let shieldAmount = enemy.maxHp * 0.75  # Shield = 75% of max HP
      enemy.shieldHp = shieldAmount
      enemy.maxShieldHp = shieldAmount
      enemy.contactDamage += 2 + (waveNumber div 5)
      enemy.rangedDamage += 2 + (waveNumber div 5)
    
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

proc getEliteName*(eliteType: EliteType): string =
  ## Returns the display name for each elite type
  case eliteType
  of etNone: ""
  of etSwift: "Swift"
  of etTank: "Tank"
  of etVenomous: "Venomous"
  of etExplosive: "Explosive"
  of etRegenerative: "Regenerative"
  of etShielded: "Shielded"

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
    # Each aura is slightly offset for visibility
    let radiusOffset = idx.float32 * 4.0
    let auraRadius = enemy.radius + 8.0 + radiusOffset + (sin(gameTime * 3.0 + idx.float32) * 3.0)
    
    # Draw outer glow rings (multiple for depth)
    for i in 0..2:
      let ringRadius = auraRadius + i.float32 * 4.0
      let alpha = uint8((180 - i * 50).float32 * pulseIntensity * 0.8)  # Slightly more transparent for multiple
      let ringColor = Color(
        r: auraColor.r,
        g: auraColor.g,
        b: auraColor.b,
        a: alpha
      )
      drawCircleLines(
        enemy.pos.x.int32,
        enemy.pos.y.int32,
        ringRadius,
        ringColor
      )
    
    # Draw inner filled circle for core glow
    let coreAlpha = uint8(60.0 * pulseIntensity)  # Less opaque for layering
    let coreColor = Color(
      r: auraColor.r,
      g: auraColor.g,
      b: auraColor.b,
      a: coreAlpha
    )
    drawCircle(
      Vector2(x: enemy.pos.x, y: enemy.pos.y),
      auraRadius - 4.0,
      coreColor
    )
  
  # Draw health bar for Tank elites (above shield bar if present)
  if etTank in enemy.eliteTypes:
    let barWidth = enemy.radius * 2.0
    let barHeight = 5.0
    # If shielded, place HP bar above shield bar; otherwise at default position
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
