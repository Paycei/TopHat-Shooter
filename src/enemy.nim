import raylib, types, random, math, wall

proc newEnemy*(x, y: float32, difficulty: float32, enemyType: EnemyType): Enemy =
  let strengthMultiplier = pow(1.15, difficulty)  # Exponential scaling
  
  case enemyType
  of etCircle:  # Normal chaser - slightly buffed
    let size = 10 + difficulty * 1.5 + rand(5).float32
    result = Enemy(
      pos: newVector2f(x, y),
      vel: newVector2f(0, 0),
      radius: size,
      hp: 1.0 * strengthMultiplier,
      maxHp: 1.0 * strengthMultiplier,
      speed: 100 + difficulty * 10,  # Faster
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
      lastWallDamageTime: 0
    )
  
  of etCube:  # Ranged shooter - BUFFED: backs away from player
    result = Enemy(
      pos: newVector2f(x, y),
      vel: newVector2f(0, 0),
      radius: 12 + difficulty * 1.2,
      hp: 2.0 * strengthMultiplier,  # More HP
      maxHp: 2.0 * strengthMultiplier,
      speed: 60 + difficulty * 3,  # Faster for kiting
      damage: 1,
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
      lastWallDamageTime: 0
    )
  
  of etTriangle:  # HEAVILY BUFFED: dash + free movement
    result = Enemy(
      pos: newVector2f(x, y),
      vel: newVector2f(0, 0),
      radius: 11 + difficulty * 1.0,
      hp: 1.2 * strengthMultiplier,  # More HP
      maxHp: 1.2 * strengthMultiplier,
      speed: 160 + difficulty * 15,  # Even faster
      damage: 2,
      color: Pink,
      enemyType: etTriangle,
      isBoss: false,
      bossPhase: bpCircle,
      phaseChangeTimer: 0,
      shootTimer: 0,
      spawnTimer: 0,
      dashTimer: 1.5,  # Dash cooldown
      hitCount: 0,
      requiredHits: 0,
      lastContactDamageTime: 0,
      teleportTimer: 0,
      shockwaveTimer: 0,
      burstTimer: 0,
      lastWallDamageTime: 0
    )
  
  of etStar:  # NERFED: fewer required hits
    let hits = 7 + (difficulty * 2.5).int  # Reduced from 15 + diff*8
    result = Enemy(
      pos: newVector2f(x, y),
      vel: newVector2f(0, 0),
      radius: 18 + difficulty * 2,
      hp: 9999.0,  # High HP, but uses hit counter instead
      maxHp: 9999.0,
      speed: 45 + difficulty * 4,  # Slightly faster
      damage: 2,
      color: Color(r: 255, g: 215, b: 0, a: 255),  # Gold
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
      hexTeleportTimer: 0
    )
  
  of etHexagon:  # Teleporting chaos enemy - shoots while teleporting!
    result = Enemy(
      pos: newVector2f(x, y),
      vel: newVector2f(0, 0),
      radius: 14 + difficulty * 1.5,
      hp: 3.0 * strengthMultiplier,
      maxHp: 3.0 * strengthMultiplier,
      speed: 70 + difficulty * 8,  # Medium speed
      damage: 1,
      color: Color(r: 128, g: 0, b: 255, a: 255),  # Purple
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
      hexTeleportTimer: 2.5 + rand(1.0)  # Teleports every 2.5-3.5s
    )

proc newBoss*(x, y: float32, difficulty: float32, bossType: BossType): Enemy =
  let strengthMultiplier = pow(1.15, difficulty)  # Reduced from 1.25
  
  result = Enemy(
    pos: newVector2f(x, y),
    vel: newVector2f(0, 0),
    radius: 50 + difficulty * 4,  # Bigger
    hp: 40 + difficulty * 20 * strengthMultiplier,  # NERFED: Was 80 + difficulty * 40
    maxHp: 40 + difficulty * 20 * strengthMultiplier,
    speed: 60 + difficulty * 5,  # Faster
    damage: 2 + (difficulty / 8).int,  # More damage
    color: case bossType
      of btShooter: DarkPurple
      of btSummoner: DarkGreen
      of btCharger: DarkBlue
      of btOrbit: Violet,
    enemyType: etCircle,
    isBoss: true,
    bossType: bossType,
    bossPhase: bpCircle,
    phaseChangeTimer: 8.0,  # Change phase every 8 seconds
    shootTimer: 0,
    spawnTimer: 0,
    dashTimer: 0,
    hitCount: 0,
    requiredHits: 0,
    lastContactDamageTime: 0,
    teleportTimer: 12.0,  # Teleport periodically
    shockwaveTimer: 6.0,  # Shockwave attack
    burstTimer: 0.5,  # Rapid fire bursts
    lastWallDamageTime: 0,
    entranceTimer: 0,
    targetPos: newVector2f(x, y)
  )

proc updateEnemy*(enemy: Enemy, playerPos: Vector2f, dt: float32, walls: seq[Wall], currentTime: float32): bool =
  # Apply slow field effect to enemy speed
  var effectiveSpeed = enemy.speed
  if enemy.slowAmount > 0:
    effectiveSpeed = enemy.speed * (1.0 - enemy.slowAmount)
  
  if enemy.isBoss:
    # Handle entrance animation
    if enemy.entranceTimer > 0:
      enemy.entranceTimer -= dt
      
      # Smooth entrance movement
      let progress = 1.0 - (enemy.entranceTimer / 2.0)
      let easedProgress = progress * progress  # Ease-in
      
      # Interpolate to target position
      let startPos = case enemy.bossType
        of btShooter: newVector2f(enemy.targetPos.x, -100)
        of btSummoner: newVector2f(enemy.targetPos.x, enemy.targetPos.y + 300)
        of btCharger: newVector2f(-100, enemy.targetPos.y)
        of btOrbit: newVector2f(enemy.targetPos.x + 300, enemy.targetPos.y)
      
      enemy.pos.x = startPos.x + (enemy.targetPos.x - startPos.x) * easedProgress
      enemy.pos.y = startPos.y + (enemy.targetPos.y - startPos.y) * easedProgress
      
      # Boss is invulnerable during entrance
      return true
    
    enemy.shootTimer += dt
    enemy.spawnTimer += dt
    enemy.phaseChangeTimer -= dt
    enemy.teleportTimer -= dt
    enemy.shockwaveTimer -= dt
    enemy.burstTimer += dt
    
    # Phase change mechanic - bosses change form!
    if enemy.phaseChangeTimer <= 0:
      enemy.bossPhase = BossPhase((enemy.bossPhase.int + 1) mod 4)
      enemy.phaseChangeTimer = 8.0
      
      # Visual change based on phase
      case enemy.bossPhase
      of bpCircle:
        enemy.color = case enemy.bossType
          of btShooter: DarkPurple
          of btSummoner: DarkGreen
          of btCharger: DarkBlue
          of btOrbit: Violet
      of bpCube:
        enemy.color = Color(r: 100, g: 50, b: 150, a: 255)
      of bpTriangle:
        enemy.color = Color(r: 200, g: 50, b: 100, a: 255)
      of bpStar:
        enemy.color = Color(r: 255, g: 180, b: 0, a: 255)
    
    # Phase-based behavior modifiers
    var speedMod = 1.0
    case enemy.bossPhase
    of bpCircle:
      speedMod = 1.0
    of bpCube:
      speedMod = 0.6  # Slower, defensive
    of bpTriangle:
      speedMod = 1.8  # Much faster, aggressive
    of bpStar:
      speedMod = 0.8  # Moderate speed
    
    # Boss movement with wall collision
    let dir = (playerPos - enemy.pos).normalize()
    var canMove = true
    let nextPos = enemy.pos + dir * effectiveSpeed * speedMod * dt
    
    for wall in walls:
      if distance(nextPos, wall.pos) < enemy.radius + wall.radius:
        canMove = false
        
        # Boss colliding with wall - damage both (1 dmg/sec)
        if currentTime - enemy.lastWallDamageTime >= 1.0:
          wall.takeDamage(1.0)
          enemy.hp -= 1.0
          enemy.lastWallDamageTime = currentTime
        break
    
    if canMove:
      enemy.vel = dir * effectiveSpeed * speedMod
      enemy.pos = enemy.pos + enemy.vel * dt
    
  else:
    case enemy.enemyType
    of etCircle:  # Normal chaser
      let dir = (playerPos - enemy.pos).normalize()
      var canMove = true
      let nextPos = enemy.pos + dir * effectiveSpeed * dt
      
      for wall in walls:
        if distance(nextPos, wall.pos) < enemy.radius + wall.radius:
          canMove = false
          
          # Enemy colliding with wall - damage both (1 dmg/sec)
          if currentTime - enemy.lastWallDamageTime >= 1.0:
            wall.takeDamage(1.0)
            enemy.hp -= 1.0
            enemy.lastWallDamageTime = currentTime
          break
      
      if canMove:
        enemy.vel = dir * effectiveSpeed
        enemy.pos = enemy.pos + enemy.vel * dt
    
    of etCube:  # BUFFED: Backs away when player is close
      enemy.shootTimer += dt
      let distToPlayer = distance(enemy.pos, playerPos)
      let dir = (playerPos - enemy.pos).normalize()
      
      # Kiting behavior: maintain optimal distance
      const optimalDistance = 250.0
      const retreatDistance = 150.0
      
      if distToPlayer < retreatDistance:
        # Too close - back away!
        let retreatDir = dir * -1.0
        let nextPos = enemy.pos + retreatDir * effectiveSpeed * dt
        var canMove = true
        
        for wall in walls:
          if distance(nextPos, wall.pos) < enemy.radius + wall.radius:
            canMove = false
            
            # Enemy colliding with wall - damage both (1 dmg/sec)
            if currentTime - enemy.lastWallDamageTime >= 1.0:
              wall.takeDamage(1.0)
              enemy.hp -= 1.0
              enemy.lastWallDamageTime = currentTime
            break
        
        if canMove:
          enemy.pos = nextPos
      elif distToPlayer > optimalDistance:
        # Too far - move closer
        let nextPos = enemy.pos + dir * effectiveSpeed * 0.5 * dt
        var canMove = true
        
        for wall in walls:
          if distance(nextPos, wall.pos) < enemy.radius + wall.radius:
            canMove = false
            
            # Enemy colliding with wall - damage both (1 dmg/sec)
            if currentTime - enemy.lastWallDamageTime >= 1.0:
              wall.takeDamage(1.0)
              enemy.hp -= 1.0
              enemy.lastWallDamageTime = currentTime
            break
        
        if canMove:
          enemy.pos = nextPos
      # else: in optimal range, stay put
    
    of etTriangle:  # BUFFED: Dash + erratic movement - FULLY FUNCTIONAL
      enemy.dashTimer -= dt
      
      if enemy.dashTimer <= 0:
        # Execute dash toward player's CURRENT position
        let dir = (playerPos - enemy.pos).normalize()
        enemy.vel = dir * effectiveSpeed * 3.5  # Super fast dash
        enemy.dashTimer = 2.0 + rand(1.0)  # Reset dash cooldown (2-3 seconds)
      else:
        # Between dashes: erratic aggressive chasing behavior
        let dir = (playerPos - enemy.pos).normalize()
        let distToPlayer = distance(enemy.pos, playerPos)
        
        # Time-based sine wave for smooth unpredictable zigzag pattern
        let zigzagAngle = sin(currentTime * 7.0 + enemy.pos.x * 0.05) * 0.5
        let zigzagDir = newVector2f(
          dir.x * cos(zigzagAngle) - dir.y * sin(zigzagAngle),
          dir.x * sin(zigzagAngle) + dir.y * cos(zigzagAngle)
        )
        
        if distToPlayer > 120:
          # Long range: aggressive chase with zigzag
          enemy.vel = zigzagDir * effectiveSpeed * 0.9
        else:
          # Close range: circle strafe with unpredictable weaving
          let tangent = newVector2f(-dir.y, dir.x)
          let weaveIntensity = sin(currentTime * 10.0 + enemy.pos.y * 0.05) * 0.5
          let circleDir = (zigzagDir * (0.5 + weaveIntensity * 0.2) + tangent * (0.5 - weaveIntensity * 0.2)).normalize()
          enemy.vel = circleDir * effectiveSpeed * 0.95
        
        # Maintain momentum with very light damping
        enemy.vel = enemy.vel * 0.98
      
      var canMove = true
      let nextPos = enemy.pos + enemy.vel * dt
      
      for wall in walls:
        if distance(nextPos, wall.pos) < enemy.radius + wall.radius:
          canMove = false
          # Aggressive wall bounce maintains speed
          let wallDir = (enemy.pos - wall.pos).normalize()
          enemy.vel = wallDir * effectiveSpeed * 0.85
          
          # Enemy colliding with wall - damage both (1 dmg/sec)
          if currentTime - enemy.lastWallDamageTime >= 1.0:
            wall.takeDamage(1.0)
            enemy.hp -= 1.0
            enemy.lastWallDamageTime = currentTime
          break
      
      if canMove:
        enemy.pos = enemy.pos + enemy.vel * dt
    
    of etStar:  # Slow, tank enemy
      let dir = (playerPos - enemy.pos).normalize()
      let nextPos = enemy.pos + dir * effectiveSpeed * dt
      var canMove = true
      
      for wall in walls:
        if distance(nextPos, wall.pos) < enemy.radius + wall.radius:
          canMove = false
          
          # Enemy colliding with wall - damage both (1 dmg/sec)
          if currentTime - enemy.lastWallDamageTime >= 1.0:
            wall.takeDamage(1.0)
            enemy.hp -= 1.0
            enemy.lastWallDamageTime = currentTime
          break
      
      if canMove:
        enemy.vel = dir * effectiveSpeed
        enemy.pos = nextPos
    
    of etHexagon:  # Teleporting chaos enemy
      enemy.hexTeleportTimer -= dt
      enemy.shootTimer += dt
      
      if enemy.hexTeleportTimer <= 0:
        # Teleport to random position near player
        let angle = rand(1.0) * PI * 2.0
        let teleportDist = 150.0 + rand(100.0)
        enemy.pos.x = playerPos.x + cos(angle) * teleportDist
        enemy.pos.y = playerPos.y + sin(angle) * teleportDist
        
        # Reset timer
        enemy.hexTeleportTimer = 2.5 + rand(1.0)
      else:
        # Normal movement between teleports
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
  
  # Check if star enemy is defeated by hit count
  if enemy.enemyType == etStar and enemy.hitCount >= enemy.requiredHits:
    return false
  
  return enemy.hp > 0

proc drawEnemy*(enemy: Enemy) =
  if enemy.isBoss:
    # Draw unique boss aura/effect based on type
    case enemy.bossType
    of btShooter:  # Rotating purple aura
      let time = getTime() * 2.0
      for i in 0..5:
        let angle = time + i.float32 * PI * 2.0 / 6.0
        let dist = enemy.radius + 20 + sin(time * 3.0) * 10
        let x = enemy.pos.x + cos(angle) * dist
        let y = enemy.pos.y + sin(angle) * dist
        drawCircle(Vector2(x: x, y: y), 8, Color(r: 128, g: 0, b: 255, a: 100))
    
    of btSummoner:  # Pulsing green rings
      let pulse = sin(getTime() * 3.0) * 15 + 30
      drawCircleLines(enemy.pos.x.int32, enemy.pos.y.int32, enemy.radius + pulse, 
                     Color(r: 0, g: 255, b: 100, a: 150))
      drawCircleLines(enemy.pos.x.int32, enemy.pos.y.int32, enemy.radius + pulse + 15, 
                     Color(r: 0, g: 200, b: 80, a: 100))
    
    of btCharger:  # Electric blue crackling
      for i in 0..3:
        let angle = rand(1.0) * PI * 2.0
        let dist = enemy.radius + 10 + rand(15).float32
        let x = enemy.pos.x + cos(angle) * dist
        let y = enemy.pos.y + sin(angle) * dist
        drawLine(Vector2(x: enemy.pos.x, y: enemy.pos.y), Vector2(x: x, y: y), 2, 
                Color(r: 100, g: 200, b: 255, a: 180))
    
    of btOrbit:  # Violet orbiting particles
      let time = getTime() * 4.0
      for i in 0..7:
        let angle = time + i.float32 * PI * 2.0 / 8.0
        let dist = enemy.radius + 35
        let x = enemy.pos.x + cos(angle) * dist
        let y = enemy.pos.y + sin(angle) * dist
        drawCircle(Vector2(x: x, y: y), 6, Color(r: 200, g: 100, b: 255, a: 150))
    
    # Draw based on current phase
    case enemy.bossPhase
    of bpCircle:
      drawCircle(Vector2(x: enemy.pos.x, y: enemy.pos.y), enemy.radius, enemy.color)
      drawCircleLines(enemy.pos.x.int32, enemy.pos.y.int32, enemy.radius, Black)
      drawCircle(Vector2(x: enemy.pos.x, y: enemy.pos.y), enemy.radius * 0.3, White)
    
    of bpCube:
      # Square form
      let size = enemy.radius * 1.2
      drawRectangle((enemy.pos.x - size).int32, (enemy.pos.y - size).int32, 
                    (size * 2).int32, (size * 2).int32, enemy.color)
      drawRectangleLines((enemy.pos.x - size).int32, (enemy.pos.y - size).int32, 
                         (size * 2).int32, (size * 2).int32, Black)
    
    of bpTriangle:
      # Triangle form
      let v1 = Vector2(x: enemy.pos.x, y: enemy.pos.y - enemy.radius)
      let v2 = Vector2(x: enemy.pos.x - enemy.radius * 0.87, y: enemy.pos.y + enemy.radius * 0.5)
      let v3 = Vector2(x: enemy.pos.x + enemy.radius * 0.87, y: enemy.pos.y + enemy.radius * 0.5)
      drawTriangle(v1, v2, v3, enemy.color)
      drawTriangleLines(v1, v2, v3, Black)
    
    of bpStar:
      # Star form
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
    
    # Boss HP bar
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
      # Draw as square
      let size = enemy.radius * 1.4
      drawRectangle((enemy.pos.x - size).int32, (enemy.pos.y - size).int32, 
                    (size * 2).int32, (size * 2).int32, enemy.color)
      drawRectangleLines((enemy.pos.x - size).int32, (enemy.pos.y - size).int32, 
                         (size * 2).int32, (size * 2).int32, Black)
    
    of etTriangle:
      # Draw as triangle
      let v1 = Vector2(x: enemy.pos.x, y: enemy.pos.y - enemy.radius)
      let v2 = Vector2(x: enemy.pos.x - enemy.radius * 0.87, y: enemy.pos.y + enemy.radius * 0.5)
      let v3 = Vector2(x: enemy.pos.x + enemy.radius * 0.87, y: enemy.pos.y + enemy.radius * 0.5)
      drawTriangle(v1, v2, v3, enemy.color)
      drawTriangleLines(v1, v2, v3, Black)
    
    of etStar:
      # Draw as star with hit counter
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
      
      # Draw hit counter
      let remaining = enemy.requiredHits - enemy.hitCount
      let text = $remaining
      let textWidth = measureText(text, 14)
      drawText(text, (enemy.pos.x - textWidth / 2).int32, (enemy.pos.y - 7).int32, 14, Black)
    
    of etHexagon:
      # Draw as hexagon with teleport glow
      let points = 6
      for i in 0..<points:
        let angle = i.float32 * PI / 3.0
        let nextAngle = (i + 1).float32 * PI / 3.0
        let x1 = enemy.pos.x + cos(angle) * enemy.radius
        let y1 = enemy.pos.y + sin(angle) * enemy.radius
        let x2 = enemy.pos.x + cos(nextAngle) * enemy.radius
        let y2 = enemy.pos.y + sin(nextAngle) * enemy.radius
        drawLine(Vector2(x: x1, y: y1), Vector2(x: x2, y: y2), 2, enemy.color)
      
      # Teleport warning glow
      if enemy.hexTeleportTimer < 0.5:
        let glowAlpha = ((enemy.hexTeleportTimer * 4.0).int mod 2) * 150
        drawCircle(Vector2(x: enemy.pos.x, y: enemy.pos.y), enemy.radius + 5, 
                  Color(r: 255, g: 255, b: 0, a: glowAlpha.uint8))

proc spawnEnemy*(screenWidth, screenHeight: int32, difficulty: float32): Enemy =
  let side = rand(3)
  var x, y: float32
  
  case side
  of 0: # Top
    x = rand(screenWidth.int).float32
    y = -30
  of 1: # Right
    x = screenWidth.float32 + 30
    y = rand(screenHeight.int).float32
  of 2: # Bottom
    x = rand(screenWidth.int).float32
    y = screenHeight.float32 + 30
  else: # Left
    x = -30
    y = rand(screenHeight.int).float32
  
  # PROGRESSIVE DIFFICULTY SYSTEM - enemies unlock in phases (REBALANCED)
  let roll = rand(100)
  var enemyType: EnemyType
  
  if difficulty < 1.5:
    # Phase 1 (0-15s): Only circles - learn the basics (extended)
    enemyType = etCircle
  
  elif difficulty < 4.0:
    # Phase 2 (15-40s): Circles + Cubes - introduce ranged enemies
    if roll < 90: enemyType = etCircle
    else: enemyType = etCube
  
  elif difficulty < 6.0:
    # Phase 3 (40-60s): Add Triangles - dash enemies (swapped with hexagon)
    if roll < 70: enemyType = etCircle
    elif roll < 85: enemyType = etCube
    else: enemyType = etTriangle
  
  elif difficulty < 12.0:
    # Phase 4 (60-120s): Add Stars - tanky enemies
    if roll < 50: enemyType = etCircle
    elif roll < 55: enemyType = etCube
    elif roll < 70: enemyType = etTriangle
    else: enemyType = etStar
  
  elif difficulty < 18.0:
    # Phase 5 (120-180s): Add Hexagons - teleporting chaos (was phase 3)
    if roll < 30: enemyType = etCircle
    elif roll < 40: enemyType = etCube
    elif roll < 55: enemyType = etTriangle
    elif roll < 75: enemyType = etStar
    else: enemyType = etHexagon
  
  else:
    # Phase 6 (180s+): Balanced chaos - all types common
    if roll < 20: enemyType = etCircle
    elif roll < 35: enemyType = etCube
    elif roll < 55: enemyType = etTriangle
    elif roll < 70: enemyType = etStar
    else: enemyType = etHexagon
  
  newEnemy(x, y, difficulty, enemyType)

proc spawnBoss*(screenWidth, screenHeight: int32, difficulty: float32, bossCount: int): Enemy =
  # Fixed spawn positions for each boss type
  let bossType = BossType((bossCount - 1) mod 4)
  
  # Determine fixed center position based on boss type
  let centerX = screenWidth.float32 / 2
  let centerY = screenHeight.float32 / 2
  var targetX, targetY: float32
  var startX, startY: float32
  
  case bossType
  of btShooter:  # Top center - descends from above
    targetX = centerX
    targetY = centerY - 100
    startX = centerX
    startY = -100
  of btSummoner:  # Bottom center - rises from below
    targetX = centerX
    targetY = centerY + 100
    startX = centerX
    startY = screenHeight.float32 + 100
  of btCharger:  # Left center - charges from left
    targetX = centerX - 120
    targetY = centerY
    startX = -100
    startY = centerY
  of btOrbit:  # Right center - spirals in from right
    targetX = centerX + 120
    targetY = centerY
    startX = screenWidth.float32 + 100
    startY = centerY
  
  var boss = newBoss(startX, startY, difficulty, bossType)
  boss.entranceTimer = 2.0  # 2 second entrance animation
  boss.targetPos = newVector2f(targetX, targetY)
  boss
