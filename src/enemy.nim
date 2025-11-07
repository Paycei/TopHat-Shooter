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
      speed: 90 + difficulty * 10,  # Faster
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
      speed: 55 + difficulty * 3,  # Faster for kiting
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
    let hits = 8 + (difficulty * 3).int  # Reduced from 15 + diff*8
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
  let strengthMultiplier = pow(1.25, difficulty)  # Stronger scaling
  
  result = Enemy(
    pos: newVector2f(x, y),
    vel: newVector2f(0, 0),
    radius: 50 + difficulty * 4,  # Bigger
    hp: 80 + difficulty * 40 * strengthMultiplier,  # Much more HP
    maxHp: 80 + difficulty * 40 * strengthMultiplier,
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
    lastWallDamageTime: 0
  )

proc updateEnemy*(enemy: Enemy, playerPos: Vector2f, dt: float32, walls: seq[Wall], currentTime: float32): bool =
  if enemy.isBoss:
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
    let nextPos = enemy.pos + dir * enemy.speed * speedMod * dt
    
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
      enemy.vel = dir * enemy.speed * speedMod
      enemy.pos = enemy.pos + enemy.vel * dt
    
  else:
    case enemy.enemyType
    of etCircle:  # Normal chaser
      let dir = (playerPos - enemy.pos).normalize()
      var canMove = true
      let nextPos = enemy.pos + dir * enemy.speed * dt
      
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
        enemy.vel = dir * enemy.speed
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
        let nextPos = enemy.pos + retreatDir * enemy.speed * dt
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
        let nextPos = enemy.pos + dir * enemy.speed * 0.5 * dt
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
    
    of etTriangle:  # BUFFED: Free movement + aggressive repositioning
      enemy.dashTimer -= dt
      
      if enemy.dashTimer <= 0:
        # Execute dash toward player
        let dir = (playerPos - enemy.pos).normalize()
        enemy.vel = dir * enemy.speed * 3.0  # Super fast dash
        enemy.dashTimer = 1.8 + rand(0.8)
      else:
        # Between dashes: actively chase player with free movement
        let dir = (playerPos - enemy.pos).normalize()
        let distToPlayer = distance(enemy.pos, playerPos)
        
        # Add some erratic movement for unpredictability
        let erraticAngle = rand(0.5) - 0.25
        let erraticDir = newVector2f(
          dir.x * cos(erraticAngle) - dir.y * sin(erraticAngle),
          dir.x * sin(erraticAngle) + dir.y * cos(erraticAngle)
        )
        
        # Chase at full speed between dashes
        if distToPlayer > 100:
          enemy.vel = erraticDir * enemy.speed
        else:
          # Circle around player when close
          let tangent = newVector2f(-dir.y, dir.x)
          enemy.vel = (erraticDir * 0.5 + tangent * 0.5).normalize() * enemy.speed
        
        # Slow down velocity gradually
        enemy.vel = enemy.vel * 0.92
      
      var canMove = true
      let nextPos = enemy.pos + enemy.vel * dt
      
      for wall in walls:
        if distance(nextPos, wall.pos) < enemy.radius + wall.radius:
          canMove = false
          enemy.vel = enemy.vel * 0.3  # Bounce off walls
          
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
      let nextPos = enemy.pos + dir * enemy.speed * dt
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
        enemy.vel = dir * enemy.speed
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
        let nextPos = enemy.pos + dir * enemy.speed * dt
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
  
  # PROGRESSIVE DIFFICULTY SYSTEM - enemies unlock in phases
  let roll = rand(100)
  var enemyType: EnemyType
  
  if difficulty < 1.5:
    # Phase 1 (0-15s): Only circles - learn the basics (extended)
    enemyType = etCircle
  
  elif difficulty < 3.0:
    # Phase 2 (15-30s): Circles + Cubes - introduce ranged enemies
    if roll < 80: enemyType = etCircle
    else: enemyType = etCube
  
  elif difficulty < 4.5:
    # Phase 3 (30-45s): Add Hexagons - teleporting enemies
    if roll < 50: enemyType = etCircle
    elif roll < 75: enemyType = etCube
    else: enemyType = etHexagon
  
  elif difficulty < 6.0:
    # Phase 4 (45-60s): Add Stars - tanky enemies
    if roll < 40: enemyType = etCircle
    elif roll < 60: enemyType = etCube
    elif roll < 80: enemyType = etHexagon
    else: enemyType = etStar
  
  elif difficulty < 8.0:
    # Phase 5 (60-80s): Add Triangles - full roster
    if roll < 25: enemyType = etCircle
    elif roll < 45: enemyType = etCube
    elif roll < 60: enemyType = etHexagon
    elif roll < 80: enemyType = etStar
    else: enemyType = etTriangle
  
  else:
    # Phase 6 (80s+): Balanced chaos - all types common
    if roll < 20: enemyType = etCircle
    elif roll < 40: enemyType = etCube
    elif roll < 55: enemyType = etHexagon
    elif roll < 75: enemyType = etStar
    else: enemyType = etTriangle
  
  newEnemy(x, y, difficulty, enemyType)

proc spawnBoss*(screenWidth, screenHeight: int32, difficulty: float32, bossCount: int): Enemy =
  let side = rand(3)
  var x, y: float32
  
  case side
  of 0: x = rand(screenWidth.int).float32; y = -50
  of 1: x = screenWidth.float32 + 50; y = rand(screenHeight.int).float32
  of 2: x = rand(screenWidth.int).float32; y = screenHeight.float32 + 50
  else: x = -50; y = rand(screenHeight.int).float32
  
  # Cycle through boss types
  let bossType = BossType((bossCount - 1) mod 4)
  newBoss(x, y, difficulty, bossType)
