import raylib, types, random, math, wall, bullet

proc newEnemy*(x, y: float32, difficulty: float32, enemyType: EnemyType): Enemy =
  let strengthMultiplier = pow(1.15, difficulty)
  
  case enemyType
  of etCircle:  # Normal chaser
    let size = 10 + difficulty * 1.5 + rand(5).float32
    result = Enemy(
      pos: newVector2f(x, y),
      vel: newVector2f(0, 0),
      radius: size,
      hp: 1.0 * strengthMultiplier,
      maxHp: 1.0 * strengthMultiplier,
      speed: 100 + difficulty * 10,
      damage: 1,
      color: if difficulty < 5: Red elif difficulty < 10: Orange else: Maroon,
      enemyType: etCircle,
      isBoss: false,
      bossPhase: bpCircle,
      phaseChangeTimer: 0,
      shootTimer: 0,
      spawnTimer: 0,
      dashTimer: 0,
      hitCount: 0,
      requiredHits: 0,
      lastContactDamageTime: 0,
      teleportTimer: 0,
      shockwaveTimer: 0,
      burstTimer: 0,
      lastWallDamageTime: 0,
      attackWarningTimer: 0,
      attackExecuteTimer: 0,
      attackPhase: 0
    )
  
  of etCube:  # Ranged shooter - backs away (BUFFED - larger and more threatening)
    result = Enemy(
      pos: newVector2f(x, y),
      vel: newVector2f(0, 0),
      radius: 18 + difficulty * 1.8,  # INCREASED from 12 + difficulty * 1.2
      hp: 3.0 * strengthMultiplier,   # INCREASED from 2.0
      maxHp: 3.0 * strengthMultiplier,
      speed: 55 + difficulty * 3,     # DECREASED from 60 (more threatening when larger)
      damage: 2,                      # INCREASED from 1
      color: Purple,
      enemyType: etCube,
      isBoss: false,
      bossPhase: bpCircle,
      phaseChangeTimer: 0,
      shootTimer: 0,
      spawnTimer: 0,
      dashTimer: 0,
      hitCount: 0,
      requiredHits: 0,
      lastContactDamageTime: 0,
      teleportTimer: 0,
      shockwaveTimer: 0,
      burstTimer: 0,
      lastWallDamageTime: 0,
      attackWarningTimer: 0,
      attackExecuteTimer: 0,
      attackPhase: 0
    )
  
  of etTriangle:  # Dash + erratic movement
    result = Enemy(
      pos: newVector2f(x, y),
      vel: newVector2f(0, 0),
      radius: 11 + difficulty * 1.0,
      hp: 1.2 * strengthMultiplier,
      maxHp: 1.2 * strengthMultiplier,
      speed: 160 + difficulty * 15,
      damage: 2,
      color: Pink,
      enemyType: etTriangle,
      isBoss: false,
      bossPhase: bpCircle,
      phaseChangeTimer: 0,
      shootTimer: 0,
      spawnTimer: 0,
      dashTimer: 1.5,
      hitCount: 0,
      requiredHits: 0,
      lastContactDamageTime: 0,
      teleportTimer: 0,
      shockwaveTimer: 0,
      burstTimer: 0,
      lastWallDamageTime: 0,
      attackWarningTimer: 0,
      attackExecuteTimer: 0,
      attackPhase: 0
    )
  
  of etStar:  # Tank that dashes when close
    let hits = 5 + (difficulty * 1.8).int
    result = Enemy(
      pos: newVector2f(x, y),
      vel: newVector2f(0, 0),
      radius: 18 + difficulty * 2,
      hp: 9999.0,
      maxHp: 9999.0,
      speed: 70 + difficulty * 6,
      damage: 2,
      color: Color(r: 255, g: 215, b: 0, a: 255),
      enemyType: etStar,
      isBoss: false,
      bossPhase: bpCircle,
      phaseChangeTimer: 0,
      shootTimer: 0,
      spawnTimer: 0,
      dashTimer: 0,
      hitCount: 0,
      requiredHits: hits,
      lastContactDamageTime: 0,
      teleportTimer: 0,
      shockwaveTimer: 0,
      burstTimer: 0,
      lastWallDamageTime: 0,
      hexTeleportTimer: 0,
      attackWarningTimer: 0,
      attackExecuteTimer: 0,
      attackPhase: 0,
      dashCooldown: 2.0  # Dash every 2 seconds when close
    )
  
  of etHexagon:  # Teleporting chaos
    result = Enemy(
      pos: newVector2f(x, y),
      vel: newVector2f(0, 0),
      radius: 14 + difficulty * 1.5,
      hp: 3.0 * strengthMultiplier,
      maxHp: 3.0 * strengthMultiplier,
      speed: 70 + difficulty * 8,
      damage: 1,
      color: Color(r: 128, g: 0, b: 255, a: 255),
      enemyType: etHexagon,
      isBoss: false,
      bossPhase: bpCircle,
      phaseChangeTimer: 0,
      shootTimer: 0,
      spawnTimer: 0,
      dashTimer: 0,
      hitCount: 0,
      requiredHits: 0,
      lastContactDamageTime: 0,
      teleportTimer: 0,
      shockwaveTimer: 0,
      burstTimer: 0,
      lastWallDamageTime: 0,
      hexTeleportTimer: 2.5 + rand(1.0),
      attackWarningTimer: 0,
      attackExecuteTimer: 0,
      attackPhase: 0
    )
  
  of etCross:  # Shows cross warning before attack - BUFFED
    result = Enemy(
      pos: newVector2f(x, y),
      vel: newVector2f(0, 0),
      radius: 17 + difficulty * 1.5,  # INCREASED from 15
      hp: 4.0 * strengthMultiplier,   # INCREASED from 2.5
      maxHp: 4.0 * strengthMultiplier,
      speed: 50 + difficulty * 4,
      damage: 2,
      color: Color(r: 255, g: 100, b: 0, a: 255),
      enemyType: etCross,
      isBoss: false,
      bossPhase: bpCircle,
      phaseChangeTimer: 0,
      shootTimer: 0,
      spawnTimer: 0,
      dashTimer: 0,
      hitCount: 0,
      requiredHits: 0,
      lastContactDamageTime: 0,
      teleportTimer: 0,
      shockwaveTimer: 0,
      burstTimer: 0,
      lastWallDamageTime: 0,
      hexTeleportTimer: 0,
      attackWarningTimer: 0,
      attackExecuteTimer: 0,
      attackPhase: 0  # 0=patrol, 1=warning, 2=execute
    )
  
  of etDiamond:  # Shoots while dashing
    result = Enemy(
      pos: newVector2f(x, y),
      vel: newVector2f(0, 0),
      radius: 13 + difficulty * 1.1,
      hp: 1.8 * strengthMultiplier,
      maxHp: 1.8 * strengthMultiplier,
      speed: 140 + difficulty * 12,
      damage: 1,
      color: Color(r: 0, g: 200, b: 255, a: 255),
      enemyType: etDiamond,
      isBoss: false,
      bossPhase: bpCircle,
      phaseChangeTimer: 0,
      shootTimer: 0,
      spawnTimer: 0,
      dashTimer: 0,
      hitCount: 0,
      requiredHits: 0,
      lastContactDamageTime: 0,
      teleportTimer: 0,
      shockwaveTimer: 0,
      burstTimer: 0,
      lastWallDamageTime: 0,
      hexTeleportTimer: 0,
      attackWarningTimer: 0,
      attackExecuteTimer: 0,
      attackPhase: 0,
      dashCooldown: 2.5 + rand(1.0)
    )
  
  of etOctagon:  # Many slow inaccurate projectiles
    result = Enemy(
      pos: newVector2f(x, y),
      vel: newVector2f(0, 0),
      radius: 16 + difficulty * 1.4,
      hp: 3.5 * strengthMultiplier,
      maxHp: 3.5 * strengthMultiplier,
      speed: 90 + difficulty * 2,
      damage: 1,
      color: Color(r: 150, g: 150, b: 0, a: 255),
      enemyType: etOctagon,
      isBoss: false,
      bossPhase: bpCircle,
      phaseChangeTimer: 0,
      shootTimer: 0,
      spawnTimer: 0,
      dashTimer: 0,
      hitCount: 0,
      requiredHits: 0,
      lastContactDamageTime: 0,
      teleportTimer: 0,
      shockwaveTimer: 0,
      burstTimer: 0,
      lastWallDamageTime: 0,
      hexTeleportTimer: 0,
      attackWarningTimer: 0,
      attackExecuteTimer: 0,
      attackPhase: 0
    )
  
  of etPentagon:  # Single fast bullet, low fire rate
    result = Enemy(
      pos: newVector2f(x, y),
      vel: newVector2f(0, 0),
      radius: 14 + difficulty * 1.2,
      hp: 2.2 * strengthMultiplier,
      maxHp: 2.2 * strengthMultiplier,
      speed: 55 + difficulty * 3,
      damage: 2,
      color: Color(r: 0, g: 150, b: 100, a: 255),
      enemyType: etPentagon,
      isBoss: false,
      bossPhase: bpCircle,
      phaseChangeTimer: 0,
      shootTimer: 0,
      spawnTimer: 0,
      dashTimer: 0,
      hitCount: 0,
      requiredHits: 0,
      lastContactDamageTime: 0,
      teleportTimer: 0,
      shockwaveTimer: 0,
      burstTimer: 0,
      lastWallDamageTime: 0,
      hexTeleportTimer: 0,
      attackWarningTimer: 0,
      attackExecuteTimer: 0,
      attackPhase: 0
    )
  
  of etTrickster:  # False warning, real attack elsewhere
    result = Enemy(
      pos: newVector2f(x, y),
      vel: newVector2f(0, 0),
      radius: 17 + difficulty * 1.5,
      hp: 3.0 * strengthMultiplier,
      maxHp: 3.0 * strengthMultiplier,
      speed: 65 + difficulty * 5,
      damage: 2,
      color: Color(r: 200, g: 0, b: 200, a: 255),
      enemyType: etTrickster,
      isBoss: false,
      bossPhase: bpCircle,
      phaseChangeTimer: 0,
      shootTimer: 0,
      spawnTimer: 0,
      dashTimer: 0,
      hitCount: 0,
      requiredHits: 0,
      lastContactDamageTime: 0,
      teleportTimer: 0,
      shockwaveTimer: 0,
      burstTimer: 0,
      lastWallDamageTime: 0,
      hexTeleportTimer: 0,
      attackWarningTimer: 0,
      attackExecuteTimer: 0,
      attackPhase: 0,
      fakeWarningTimer: 3.0 + rand(2.0)
    )
  
  of etPhantom:  # Unpredictable teleporter with fake clones
    result = Enemy(
      pos: newVector2f(x, y),
      vel: newVector2f(0, 0),
      radius: 15 + difficulty * 1.3,
      hp: 2.8 * strengthMultiplier,
      maxHp: 2.8 * strengthMultiplier,
      speed: 80 + difficulty * 6,
      damage: 2,
      color: Color(r: 100, g: 100, b: 255, a: 180),
      enemyType: etPhantom,
      isBoss: false,
      bossPhase: bpCircle,
      phaseChangeTimer: 0,
      shootTimer: 0,
      spawnTimer: 0,
      dashTimer: 0,
      hitCount: 0,
      requiredHits: 0,
      lastContactDamageTime: 0,
      teleportTimer: 0,
      shockwaveTimer: 0,
      burstTimer: 0,
      lastWallDamageTime: 0,
      hexTeleportTimer: 0,
      attackWarningTimer: 0,
      attackExecuteTimer: 0,
      attackPhase: 0,
      clonePositions: @[],
      cloneTimer: 2.0 + rand(1.5)
    )

proc newBoss*(x, y: float32, difficulty: float32, bossType: BossType): Enemy =
  let strengthMultiplier = pow(1.18, difficulty)
  
  result = Enemy(
    pos: newVector2f(x, y),
    vel: newVector2f(0, 0),
    radius: 50 + difficulty * 4,
    hp: 100 + difficulty * 30 * strengthMultiplier,
    maxHp: 100 + difficulty * 30 * strengthMultiplier,
    speed: 75 + difficulty * 5,
    damage: 2 + (difficulty / 8).int,
    color: case bossType
      of btShooter: DarkPurple
      of btSummoner: DarkGreen
      of btCharger: DarkBlue
      of btOrbit: Violet,
    enemyType: etCircle,
    isBoss: true,
    bossType: bossType,
    bossPhase: bpCircle,
    phaseChangeTimer: 8.0,
    shootTimer: 0,
    spawnTimer: 0,
    dashTimer: 0,
    hitCount: 0,
    requiredHits: 0,
    lastContactDamageTime: 0,
    teleportTimer: 12.0,
    shockwaveTimer: 6.0,
    burstTimer: 0.5,
    lastWallDamageTime: 0,
    entranceTimer: 0,
    targetPos: newVector2f(x, y),
    attackWarningTimer: 0,
    attackExecuteTimer: 0,
    attackPhase: 0
  )

proc updateEnemy*(enemy: Enemy, playerPos: Vector2f, dt: float32, walls: seq[Wall], currentTime: float32, game: var Game): bool =
  # Apply slow field effect
  var effectiveSpeed = enemy.speed
  if enemy.slowAmount > 0:
    effectiveSpeed = enemy.speed * (1.0 - enemy.slowAmount)
  
  if enemy.isBoss:
    # Boss update logic (keeping existing)
    if enemy.entranceTimer > 0:
      enemy.entranceTimer -= dt
      let progress = 1.0 - (enemy.entranceTimer / 2.0)
      let easedProgress = progress * progress
      let startPos = case enemy.bossType
        of btShooter: newVector2f(enemy.targetPos.x, -100)
        of btSummoner: newVector2f(enemy.targetPos.x, enemy.targetPos.y + 300)
        of btCharger: newVector2f(-100, enemy.targetPos.y)
        of btOrbit: newVector2f(enemy.targetPos.x + 300, enemy.targetPos.y)
      enemy.pos.x = startPos.x + (enemy.targetPos.x - startPos.x) * easedProgress
      enemy.pos.y = startPos.y + (enemy.targetPos.y - startPos.y) * easedProgress
      return true
    
    enemy.shootTimer += dt
    enemy.spawnTimer += dt
    enemy.phaseChangeTimer -= dt
    enemy.teleportTimer -= dt
    enemy.shockwaveTimer -= dt
    enemy.burstTimer += dt
    
    if enemy.phaseChangeTimer <= 0:
      enemy.bossPhase = BossPhase((enemy.bossPhase.int + 1) mod 4)
      enemy.phaseChangeTimer = 8.0
      case enemy.bossPhase
      of bpCircle: enemy.color = case enemy.bossType
        of btShooter: DarkPurple
        of btSummoner: DarkGreen
        of btCharger: DarkBlue
        of btOrbit: Violet
      of bpCube: enemy.color = Color(r: 100, g: 50, b: 150, a: 255)
      of bpTriangle: enemy.color = Color(r: 200, g: 50, b: 100, a: 255)
      of bpStar: enemy.color = Color(r: 255, g: 180, b: 0, a: 255)
    
    var speedMod = case enemy.bossPhase
      of bpCircle: 1.0
      of bpCube: 0.6
      of bpTriangle: 1.8
      of bpStar: 0.8
    
    let dir = (playerPos - enemy.pos).normalize()
    var canMove = true
    let nextPos = enemy.pos + dir * effectiveSpeed * speedMod * dt
    for wall in walls:
      if distance(nextPos, wall.pos) < enemy.radius + wall.radius:
        canMove = false
        if currentTime - enemy.lastWallDamageTime >= 1.0:
          wall.takeDamage(1.0)
          enemy.hp -= 1.0
          enemy.lastWallDamageTime = currentTime
        break
    if canMove:
      enemy.vel = dir * effectiveSpeed * speedMod
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
      enemy.shootTimer += dt
      let distToPlayer = distance(enemy.pos, playerPos)
      let dir = (playerPos - enemy.pos).normalize()
      const optimalDistance = 250.0
      const retreatDistance = 150.0
      if distToPlayer < retreatDistance:
        let retreatDir = dir * -1.0
        let nextPos = enemy.pos + retreatDir * effectiveSpeed * dt
        var canMove = true
        for wall in walls:
          if distance(nextPos, wall.pos) < enemy.radius + wall.radius:
            canMove = false
            if currentTime - enemy.lastWallDamageTime >= 1.0:
              wall.takeDamage(1.0)
              enemy.hp -= 1.0
              enemy.lastWallDamageTime = currentTime
            break
        if canMove:
          enemy.pos = nextPos
      elif distToPlayer > optimalDistance:
        let nextPos = enemy.pos + dir * effectiveSpeed * 0.5 * dt
        var canMove = true
        for wall in walls:
          if distance(nextPos, wall.pos) < enemy.radius + wall.radius:
            canMove = false
            if currentTime - enemy.lastWallDamageTime >= 1.0:
              wall.takeDamage(1.0)
              enemy.hp -= 1.0
              enemy.lastWallDamageTime = currentTime
            break
        if canMove:
          enemy.pos = nextPos
    
    of etTriangle:
      enemy.dashTimer -= dt
      if enemy.dashTimer <= 0:
        let dir = (playerPos - enemy.pos).normalize()
        enemy.vel = dir * effectiveSpeed * 3.5
        enemy.dashTimer = 2.0 + rand(1.0)
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
        enemy.vel = enemy.vel * 0.98
      var canMove = true
      let nextPos = enemy.pos + enemy.vel * dt
      for wall in walls:
        if distance(nextPos, wall.pos) < enemy.radius + wall.radius:
          canMove = false
          let wallDir = (enemy.pos - wall.pos).normalize()
          enemy.vel = wallDir * effectiveSpeed * 0.85
          if currentTime - enemy.lastWallDamageTime >= 1.0:
            wall.takeDamage(1.0)
            enemy.hp -= 1.0
            enemy.lastWallDamageTime = currentTime
          break
      if canMove:
        enemy.pos = enemy.pos + enemy.vel * dt
    
    of etStar:
      # Star dashes when close to player
      enemy.dashCooldown -= dt
      let distToPlayer = distance(enemy.pos, playerPos)
      if distToPlayer < 150 and enemy.dashCooldown <= 0:
        let dir = (playerPos - enemy.pos).normalize()
        enemy.vel = dir * effectiveSpeed * 3.0
        enemy.dashCooldown = 2.0
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
            enemy.hp -= 1.0
            enemy.lastWallDamageTime = currentTime
          break
      if canMove:
        enemy.pos = nextPos
    
    of etHexagon:
      enemy.hexTeleportTimer -= dt
      enemy.shootTimer += dt
      if enemy.hexTeleportTimer <= 0:
        let angle = rand(1.0) * PI * 2.0
        let teleportDist = 150.0 + rand(100.0)
        enemy.pos.x = playerPos.x + cos(angle) * teleportDist
        enemy.pos.y = playerPos.y + sin(angle) * teleportDist
        enemy.hexTeleportTimer = 2.5 + rand(1.0)
      else:
        let dir = (playerPos - enemy.pos).normalize()
        let nextPos = enemy.pos + dir * effectiveSpeed * dt
        var canMove = true
        for wall in walls:
          if distance(nextPos, wall.pos) < enemy.radius + wall.radius:
            canMove = false
            if currentTime - enemy.lastWallDamageTime >= 1.0:
              wall.takeDamage(1.0)
              enemy.hp -= 1.0
              enemy.lastWallDamageTime = currentTime
            break
        if canMove:
          enemy.pos = nextPos
    
    of etCross:
      # Shows cross warning before attack
      case enemy.attackPhase
      of 0:  # Patrol - slow movement
        let dir = (playerPos - enemy.pos).normalize()
        let nextPos = enemy.pos + dir * effectiveSpeed * 0.5 * dt
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
      
      of 1:  # Warning phase - stop moving
        enemy.attackWarningTimer -= dt
        if enemy.attackWarningTimer <= 0:
          enemy.attackPhase = 2
          enemy.attackExecuteTimer = 0.3  # Quick execution
      
      of 2:  # Execute attack - create LASER cross pattern (instant damage zone)
        enemy.attackExecuteTimer += dt
        if enemy.attackExecuteTimer >= 0.05:  # Fire laser after brief delay
          # Create cross laser - instant damage zone that stays for a bit
          game.lasers.add(newLaser(
            enemy.pos.x, enemy.pos.y,
            2,              # direction: 2 = cross (both horizontal and vertical)
            200.0,          # length: how far the laser extends (reduced from 400)
            15.0,           # thickness: width of laser beam (reduced from 25)
            2,              # damage
            0.4             # duration: stays for 0.4 seconds
          ))
          
          # Reset to patrol phase after firing
          enemy.attackPhase = 0
          enemy.attackWarningTimer = 0
          enemy.attackExecuteTimer = 0
      else:
        discard
    
    of etDiamond:
      # Shoots slow projectiles while dashing
      enemy.dashCooldown -= dt
      enemy.shootTimer += dt
      if enemy.dashCooldown <= 0:
        let dir = (playerPos - enemy.pos).normalize()
        enemy.vel = dir * effectiveSpeed * 2.5
        enemy.dashCooldown = 2.5 + rand(1.0)
        # Shoot 3 slow projectiles during dash start
        for i in -1..1:
          let spreadAngle = i.float32 * 0.3
          let spreadDir = newVector2f(
            dir.x * cos(spreadAngle) - dir.y * sin(spreadAngle),
            dir.x * sin(spreadAngle) + dir.y * cos(spreadAngle)
          )
          game.bullets.add(newBullet(enemy.pos.x, enemy.pos.y, spreadDir, 150, 1, false))
      else:
        let dir = (playerPos - enemy.pos).normalize()
        enemy.vel = dir * effectiveSpeed * 0.7
      
      # Shoot slow projectiles periodically during movement
      if enemy.shootTimer > 1.0:
        let angle = rand(1.0) * PI * 2.0
        let dir = newVector2f(cos(angle), sin(angle))
        game.bullets.add(newBullet(enemy.pos.x, enemy.pos.y, dir, 140, 1, false))
        enemy.shootTimer = 0
      
      var canMove = true
      let nextPos = enemy.pos + enemy.vel * dt
      for wall in walls:
        if distance(nextPos, wall.pos) < enemy.radius + wall.radius:
          canMove = false
          break
      if canMove:
        enemy.pos = nextPos
    
    of etOctagon:
      # Many slow inaccurate projectiles
      enemy.shootTimer += dt
      if enemy.shootTimer > 0.4:  # Very frequent
        let dir = (playerPos - enemy.pos).normalize()
        # Add random inaccuracy
        let inaccuracy = (rand(1.0) - 0.5) * 0.8
        let inaccurateDir = newVector2f(
          dir.x * cos(inaccuracy) - dir.y * sin(inaccuracy),
          dir.x * sin(inaccuracy) + dir.y * cos(inaccuracy)
        )
        game.bullets.add(newBullet(enemy.pos.x, enemy.pos.y, inaccurateDir, 120, 1, false))
        enemy.shootTimer = 0
      
      # Slow backing movement
      let dir = (playerPos - enemy.pos).normalize()
      let distToPlayer = distance(enemy.pos, playerPos)
      if distToPlayer < 200:
        let retreatDir = dir * -1.0
        let nextPos = enemy.pos + retreatDir * effectiveSpeed * dt
        var canMove = true
        for wall in walls:
          if distance(nextPos, wall.pos) < enemy.radius + wall.radius:
            canMove = false
            break
        if canMove:
          enemy.pos = nextPos
    
    of etPentagon:
      # BUFFED: Pentagon-shaped bullet projectile, larger size
      enemy.shootTimer += dt
      if enemy.shootTimer > 2.5:  # Low fire rate
        let dir = (playerPos - enemy.pos).normalize()
        let pentagonBullet = newBullet(enemy.pos.x, enemy.pos.y, dir, 400, 2, false,
                                       false, false, false, false, false, 0, 0, true)  # isPentagon = true
        pentagonBullet.radius = 10  # MUCH LARGER bullet (was 6 for enemy bullets)
        game.bullets.add(pentagonBullet)
        enemy.shootTimer = 0
      
      # Maintain distance
      let dir = (playerPos - enemy.pos).normalize()
      let distToPlayer = distance(enemy.pos, playerPos)
      const optimalDistance = 300.0
      if distToPlayer < optimalDistance - 50:
        let retreatDir = dir * -1.0
        let nextPos = enemy.pos + retreatDir * effectiveSpeed * dt
        var canMove = true
        for wall in walls:
          if distance(nextPos, wall.pos) < enemy.radius + wall.radius:
            canMove = false
            break
        if canMove:
          enemy.pos = nextPos
      elif distToPlayer > optimalDistance + 50:
        let nextPos = enemy.pos + dir * effectiveSpeed * 0.6 * dt
        var canMove = true
        for wall in walls:
          if distance(nextPos, wall.pos) < enemy.radius + wall.radius:
            canMove = false
            break
        if canMove:
          enemy.pos = nextPos
    
    of etTrickster:
      # Shows false warning, attacks differently
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
        
        # Shoot from NEW position (not where warning was)
        for i in 0..<6:
          let bulletAngle = i.float32 * PI / 3.0
          let dir = newVector2f(cos(bulletAngle), sin(bulletAngle))
          game.bullets.add(newBullet(enemy.pos.x, enemy.pos.y, dir, 250, 1, false))
        
        enemy.fakeWarningTimer = 3.0 + rand(2.0)
      
      # Normal movement
      let dir = (playerPos - enemy.pos).normalize()
      let nextPos = enemy.pos + dir * effectiveSpeed * 0.6 * dt
      var canMove = true
      for wall in walls:
        if distance(nextPos, wall.pos) < enemy.radius + wall.radius:
          canMove = false
          break
      if canMove:
        enemy.pos = nextPos
    
    of etPhantom:
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
        
        enemy.cloneTimer = 2.0 + rand(1.5)
      
      # Shoot from random clone or real position
      if enemy.shootTimer > 0.8:
        var shootPos = enemy.pos
        if enemy.clonePositions.len > 0 and rand(100) < 60:
          shootPos = enemy.clonePositions[rand(enemy.clonePositions.len - 1)]
        
        let dir = (playerPos - shootPos).normalize()
        game.bullets.add(newBullet(shootPos.x, shootPos.y, dir, 260, 1, false))
        enemy.shootTimer = 0
      
      # Erratic movement
      let dir = (playerPos - enemy.pos).normalize()
      let wobble = sin(currentTime * 5.0) * 0.7
      let wobbleDir = newVector2f(
        dir.x * cos(wobble) - dir.y * sin(wobble),
        dir.x * sin(wobble) + dir.y * cos(wobble)
      )
      let nextPos = enemy.pos + wobbleDir * effectiveSpeed * 0.7 * dt
      var canMove = true
      for wall in walls:
        if distance(nextPos, wall.pos) < enemy.radius + wall.radius:
          canMove = false
          break
      if canMove:
        enemy.pos = nextPos
  
  # Update poison
  if enemy.poisonTimer > 0:
    enemy.poisonTimer -= dt
    enemy.hp -= enemy.poisonDamage * dt
  
  # Update chain lightning cooldown
  if enemy.chainLightningCooldown > 0:
    enemy.chainLightningCooldown -= dt
  
  # Check if star is defeated by hit count
  if enemy.enemyType == etStar and enemy.hitCount >= enemy.requiredHits:
    return false
  
  return enemy.hp > 0

proc drawEnemy*(enemy: Enemy) =
  if enemy.isBoss:
    # Boss drawing (keeping existing code)
    case enemy.bossType
    of btShooter:
      let time = getTime() * 2.0
      for i in 0..5:
        let angle = time + i.float32 * PI * 2.0 / 6.0
        let dist = enemy.radius + 20 + sin(time * 3.0) * 10
        let x = enemy.pos.x + cos(angle) * dist
        let y = enemy.pos.y + sin(angle) * dist
        drawCircle(Vector2(x: x, y: y), 8, Color(r: 128, g: 0, b: 255, a: 100))
    of btSummoner:
      let pulse = sin(getTime() * 3.0) * 15 + 30
      drawCircleLines(enemy.pos.x.int32, enemy.pos.y.int32, enemy.radius + pulse, 
                     Color(r: 0, g: 255, b: 100, a: 150))
      drawCircleLines(enemy.pos.x.int32, enemy.pos.y.int32, enemy.radius + pulse + 15, 
                     Color(r: 0, g: 200, b: 80, a: 100))
    of btCharger:
      for i in 0..3:
        let angle = rand(1.0) * PI * 2.0
        let dist = enemy.radius + 10 + rand(15).float32
        let x = enemy.pos.x + cos(angle) * dist
        let y = enemy.pos.y + sin(angle) * dist
        drawLine(Vector2(x: enemy.pos.x, y: enemy.pos.y), Vector2(x: x, y: y), 2, 
                Color(r: 100, g: 200, b: 255, a: 180))
    of btOrbit:
      let time = getTime() * 4.0
      for i in 0..7:
        let angle = time + i.float32 * PI * 2.0 / 8.0
        let dist = enemy.radius + 35
        let x = enemy.pos.x + cos(angle) * dist
        let y = enemy.pos.y + sin(angle) * dist
        drawCircle(Vector2(x: x, y: y), 6, Color(r: 200, g: 100, b: 255, a: 150))
    
    case enemy.bossPhase
    of bpCircle:
      drawCircle(Vector2(x: enemy.pos.x, y: enemy.pos.y), enemy.radius, enemy.color)
      drawCircleLines(enemy.pos.x.int32, enemy.pos.y.int32, enemy.radius, Black)
      drawCircle(Vector2(x: enemy.pos.x, y: enemy.pos.y), enemy.radius * 0.3, White)
    of bpCube:
      let size = enemy.radius * 1.2
      drawRectangle((enemy.pos.x - size).int32, (enemy.pos.y - size).int32, 
                    (size * 2).int32, (size * 2).int32, enemy.color)
      drawRectangleLines((enemy.pos.x - size).int32, (enemy.pos.y - size).int32, 
                         (size * 2).int32, (size * 2).int32, Black)
    of bpTriangle:
      let v1 = Vector2(x: enemy.pos.x, y: enemy.pos.y - enemy.radius)
      let v2 = Vector2(x: enemy.pos.x - enemy.radius * 0.87, y: enemy.pos.y + enemy.radius * 0.5)
      let v3 = Vector2(x: enemy.pos.x + enemy.radius * 0.87, y: enemy.pos.y + enemy.radius * 0.5)
      drawTriangle(v1, v2, v3, enemy.color)
      drawTriangleLines(v1, v2, v3, Black)
    of bpStar:
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
        drawLine(Vector2(x: prevX, y: prevY), Vector2(x: x, y: y), 3, enemy.color)
    
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
      # FIXED HITBOX - use radius directly, not 1.4x multiplier
      let size = enemy.radius  # Changed from enemy.radius * 1.4
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
      # IMPROVED: Subtle pulsing glow animation
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
      # Draw improved cross shape with more detail
      let armLength = enemy.radius * 0.75
      let armThickness = 5.0  # Changed to float
      
      # Draw cross arms with gradient effect
      drawLine(Vector2(x: enemy.pos.x - armLength, y: enemy.pos.y),
              Vector2(x: enemy.pos.x + armLength, y: enemy.pos.y), armThickness, enemy.color)
      drawLine(Vector2(x: enemy.pos.x, y: enemy.pos.y - armLength),
              Vector2(x: enemy.pos.x, y: enemy.pos.y + armLength), armThickness, enemy.color)
      
      # Draw inner bright cross
      let innerLength = armLength * 0.6
      drawLine(Vector2(x: enemy.pos.x - innerLength, y: enemy.pos.y),
              Vector2(x: enemy.pos.x + innerLength, y: enemy.pos.y), 2,
              Color(r: 255, g: 150, b: 50, a: 255))
      drawLine(Vector2(x: enemy.pos.x, y: enemy.pos.y - innerLength),
              Vector2(x: enemy.pos.x, y: enemy.pos.y + innerLength), 2,
              Color(r: 255, g: 150, b: 50, a: 255))
      
      # Draw central core
      drawCircle(Vector2(x: enemy.pos.x, y: enemy.pos.y), enemy.radius * 0.45, enemy.color)
      drawCircle(Vector2(x: enemy.pos.x, y: enemy.pos.y), enemy.radius * 0.25,
                Color(r: 255, g: 150, b: 0, a: 255))
      
      # Warning glow with pulsing effect
      if enemy.attackPhase == 1:
        let pulseIntensity = uint8((sin(getTime() * 15.0) * 0.5 + 0.5) * 200)
        drawCircleLines(enemy.pos.x.int32, enemy.pos.y.int32, enemy.radius + 8,
                       Color(r: 255, g: 50, b: 0, a: pulseIntensity))
        drawCircleLines(enemy.pos.x.int32, enemy.pos.y.int32, enemy.radius + 12,
                       Color(r: 255, g: 0, b: 0, a: (pulseIntensity div 2).uint8))
    
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
  else:
    discard

proc drawLaser*(laser: Laser) =
  # Calculate alpha based on lifetime (fade out at the end)
  let fadePercent = laser.lifetime / laser.maxLifetime
  let baseAlpha = uint8(fadePercent * 200 + 55)  # 55-255 alpha
  
  # Enhanced laser colors with bright core
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
  
  of 2:  # Cross laser (both horizontal and vertical)
    # Horizontal outer glow
    drawRectangle(
      (laser.pos.x - laser.length).int32,
      (laser.pos.y - laser.thickness - 6).int32,
      (laser.length * 2).int32,
      (laser.thickness * 2 + 12).int32,
      outerGlow
    )
    # Horizontal mid glow
    drawRectangle(
      (laser.pos.x - laser.length).int32,
      (laser.pos.y - laser.thickness - 2).int32,
      (laser.length * 2).int32,
      (laser.thickness * 2 + 4).int32,
      midGlow
    )
    # Horizontal core
    drawRectangle(
      (laser.pos.x - laser.length).int32,
      (laser.pos.y - laser.thickness).int32,
      (laser.length * 2).int32,
      (laser.thickness * 2).int32,
      coreColor
    )
    # Vertical outer glow
    drawRectangle(
      (laser.pos.x - laser.thickness - 6).int32,
      (laser.pos.y - laser.length).int32,
      (laser.thickness * 2 + 12).int32,
      (laser.length * 2).int32,
      outerGlow
    )
    # Vertical mid glow
    drawRectangle(
      (laser.pos.x - laser.thickness - 2).int32,
      (laser.pos.y - laser.length).int32,
      (laser.thickness * 2 + 4).int32,
      (laser.length * 2).int32,
      midGlow
    )
    # Vertical core
    drawRectangle(
      (laser.pos.x - laser.thickness).int32,
      (laser.pos.y - laser.length).int32,
      (laser.thickness * 2).int32,
      (laser.length * 2).int32,
      coreColor
    )
  
  else:
    discard


proc spawnEnemy*(screenWidth, screenHeight: int32, difficulty: float32): Enemy =
  let side = rand(3)
  var x, y: float32
  
  case side
  of 0: x = rand(screenWidth.int).float32; y = -30
  of 1: x = screenWidth.float32 + 30; y = rand(screenHeight.int).float32
  of 2: x = rand(screenWidth.int).float32; y = screenHeight.float32 + 30
  else: x = -30; y = rand(screenHeight.int).float32
  
  # PROGRESSIVE DIFFICULTY SYSTEM with new enemy types
  let roll = rand(100)
  var enemyType: EnemyType
  
  if difficulty < 2.0:
    # Phase 1: Only circles
    enemyType = etCircle
  elif difficulty < 5.0:
    # Phase 2: Circles + Pentagon (easier ranged enemy)
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
    # Phase 8: All enemies including Phantom
    if roll < 10: enemyType = etCircle
    elif roll < 18: enemyType = etPentagon
    elif roll < 26: enemyType = etCube
    elif roll < 34: enemyType = etTriangle
    elif roll < 44: enemyType = etStar
    elif roll < 52: enemyType = etCross
    elif roll < 60: enemyType = etDiamond
    elif roll < 70: enemyType = etOctagon
    elif roll < 78: enemyType = etHexagon
    elif roll < 89: enemyType = etTrickster
    else: enemyType = etPhantom
  
  newEnemy(x, y, difficulty, enemyType)

proc spawnBoss*(screenWidth, screenHeight: int32, difficulty: float32, bossCount: int): Enemy =
  let bossType = BossType((bossCount - 1) mod 4)
  let centerX = screenWidth.float32 / 2
  let centerY = screenHeight.float32 / 2
  var targetX, targetY, startX, startY: float32
  
  case bossType
  of btShooter:
    targetX = centerX; targetY = centerY - 100
    startX = centerX; startY = -100
  of btSummoner:
    targetX = centerX; targetY = centerY + 100
    startX = centerX; startY = screenHeight.float32 + 100
  of btCharger:
    targetX = centerX - 120; targetY = centerY
    startX = -100; startY = centerY
  of btOrbit:
    targetX = centerX + 120; targetY = centerY
    startX = screenWidth.float32 + 100; startY = centerY
  
  var boss = newBoss(startX, startY, difficulty, bossType)
  boss.entranceTimer = 2.0
  boss.targetPos = newVector2f(targetX, targetY)
  boss
