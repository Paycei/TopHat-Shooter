import raylib, types, random, math

proc newEnemy*(x, y: float32, difficulty: float32, enemyType: EnemyType): Enemy =
  let strengthMultiplier = pow(1.15, difficulty)  # Exponential scaling
  
  case enemyType
  of etCircle:  # Normal chaser
    let size = 10 + difficulty * 1.5 + rand(5).float32
    result = Enemy(
      pos: newVector2f(x, y),
      vel: newVector2f(0, 0),
      radius: size,
      hp: 1.0 * strengthMultiplier,
      maxHp: 1.0 * strengthMultiplier,
      speed: 80 + difficulty * 8,
      damage: 1,
      color: if difficulty < 5: Red elif difficulty < 10: Orange else: Maroon,
      enemyType: etCircle,
      isBoss: false,
      shootTimer: 0,
      spawnTimer: 0,
      dashTimer: 0,
      hitCount: 0,
      requiredHits: 0,
      lastContactDamageTime: 0
    )
  
  of etCube:  # Stationary/slow shooter
    result = Enemy(
      pos: newVector2f(x, y),
      vel: newVector2f(0, 0),
      radius: 12 + difficulty * 1.2,
      hp: 1.5 * strengthMultiplier,
      maxHp: 1.5 * strengthMultiplier,
      speed: 30 + difficulty * 2,  # Very slow
      damage: 1,
      color: Purple,
      enemyType: etCube,
      isBoss: false,
      shootTimer: 0,
      spawnTimer: 0,
      dashTimer: 0,
      hitCount: 0,
      requiredHits: 0,
      lastContactDamageTime: 0
    )
  
  of etTriangle:  # Fast dash attacker
    result = Enemy(
      pos: newVector2f(x, y),
      vel: newVector2f(0, 0),
      radius: 11 + difficulty * 1.0,
      hp: 1.0 * strengthMultiplier,
      maxHp: 0.8 * strengthMultiplier,
      speed: 150 + difficulty * 12,  # Very fast
      damage: 2,
      color: Pink,
      enemyType: etTriangle,
      isBoss: false,
      shootTimer: 0,
      spawnTimer: 0,
      dashTimer: 1.125,
      hitCount: 0,
      requiredHits: 0,
      lastContactDamageTime: 0
    )
  
  of etStar:  # Requires many hits
    let hits = 15 + (difficulty * 8).int
    result = Enemy(
      pos: newVector2f(x, y),
      vel: newVector2f(0, 0),
      radius: 18 + difficulty * 2,
      hp: 9999.0,  # High HP, but uses hit counter instead
      maxHp: 9999.0,
      speed: 40 + difficulty * 3,  # Slow
      damage: 2,
      color: Color(r: 255, g: 215, b: 0, a: 255),  # Gold
      enemyType: etStar,
      isBoss: false,
      shootTimer: 0,
      spawnTimer: 0,
      dashTimer: 0,
      hitCount: 0,
      requiredHits: hits,
      lastContactDamageTime: 0
    )

proc newBoss*(x, y: float32, difficulty: float32, bossType: BossType): Enemy =
  let strengthMultiplier = pow(1.2, difficulty)
  
  result = Enemy(
    pos: newVector2f(x, y),
    vel: newVector2f(0, 0),
    radius: 45 + difficulty * 3,
    hp: 50 + difficulty * 30 * strengthMultiplier,
    maxHp: 50 + difficulty * 30 * strengthMultiplier,
    speed: 50 + difficulty * 4,
    damage: 2 + (difficulty / 10).int,  # Scales with time
    color: case bossType
      of btShooter: DarkPurple
      of btSummoner: DarkGreen
      of btCharger: DarkBlue
      of btOrbit: Violet,
    enemyType: etCircle,
    isBoss: true,
    bossType: bossType,
    shootTimer: 0,
    spawnTimer: 0,
    dashTimer: 0,
    hitCount: 0,
    requiredHits: 0,
    lastContactDamageTime: 0
  )

proc updateEnemy*(enemy: Enemy, playerPos: Vector2f, dt: float32, walls: seq[Wall]): bool =
  if enemy.isBoss:
    enemy.shootTimer += dt
    enemy.spawnTimer += dt
    
    # Boss movement
    let dir = (playerPos - enemy.pos).normalize()
    var canMove = true
    let nextPos = enemy.pos + dir * enemy.speed * dt
    
    for wall in walls:
      if distance(nextPos, wall.pos) < enemy.radius + wall.radius:
        canMove = false
        break
    
    if canMove:
      enemy.vel = dir * enemy.speed
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
          break
      
      if canMove:
        enemy.vel = dir * enemy.speed
        enemy.pos = enemy.pos + enemy.vel * dt
    
    of etCube:  # Shooter - barely moves
      enemy.shootTimer += dt
      let dir = (playerPos - enemy.pos).normalize()
      let slowMove = dir * enemy.speed * dt * 0.5
      enemy.pos = enemy.pos + slowMove
    
    of etTriangle:  # Dash attacker
      enemy.dashTimer -= dt
      if enemy.dashTimer <= 0:
        # Dash toward player
        let dir = (playerPos - enemy.pos).normalize()
        enemy.vel = dir * enemy.speed * 2.0
        enemy.dashTimer = 2.0 + rand(1.0)
      else:
        # Slow down after dash
        enemy.vel = enemy.vel * 0.95
      
      var canMove = true
      let nextPos = enemy.pos + enemy.vel * dt
      
      for wall in walls:
        if distance(nextPos, wall.pos) < enemy.radius + wall.radius:
          canMove = false
          enemy.vel = newVector2f(0, 0)
          break
      
      if canMove:
        enemy.pos = enemy.pos + enemy.vel * dt
    
    of etStar:  # Slow, tank enemy
      let dir = (playerPos - enemy.pos).normalize()
      enemy.vel = dir * enemy.speed
      enemy.pos = enemy.pos + enemy.vel * dt
  
  # Check if star enemy is defeated by hit count
  if enemy.enemyType == etStar and enemy.hitCount >= enemy.requiredHits:
    return false
  
  return enemy.hp > 0

proc drawEnemy*(enemy: Enemy) =
  if enemy.isBoss:
    drawCircle(Vector2(x: enemy.pos.x, y: enemy.pos.y), enemy.radius, enemy.color)
    drawCircleLines(enemy.pos.x.int32, enemy.pos.y.int32, enemy.radius, Black)
    drawCircle(Vector2(x: enemy.pos.x, y: enemy.pos.y), enemy.radius * 0.3, White)
    
    # Boss HP bar
    let barWidth = enemy.radius * 2
    let barHeight = 6.0
    let hpPercent = enemy.hp / enemy.maxHp
    drawRectangle((enemy.pos.x - enemy.radius).int32, (enemy.pos.y - enemy.radius - 12).int32, 
                  barWidth.int32, barHeight.int32, Red)
    drawRectangle((enemy.pos.x - enemy.radius).int32, (enemy.pos.y - enemy.radius - 12).int32, 
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
  
  # Weighted enemy type selection based on difficulty
  let roll = rand(100)
  var enemyType: EnemyType
  
  if difficulty < 2:
    # Early game: mostly circles
    if roll < 80: enemyType = etCircle
    elif roll < 95: enemyType = etCube
    else: enemyType = etTriangle
  elif difficulty < 5:
    # Mid game: more variety
    if roll < 50: enemyType = etCircle
    elif roll < 75: enemyType = etCube
    elif roll < 95: enemyType = etTriangle
    else: enemyType = etStar
  else:
    # Late game: all types common
    if roll < 40: enemyType = etCircle
    elif roll < 65: enemyType = etCube
    elif roll < 85: enemyType = etTriangle
    else: enemyType = etStar
  
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
