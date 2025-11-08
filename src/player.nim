import raylib, types, wall, math, random

proc newPlayer*(x, y: float32): Player =
  result = Player(
    pos: newVector2f(x, y),
    vel: newVector2f(0, 0),
    radius: 12,
    baseRadius: 12,
    hp: 5,  # 5 for early game comfort
    maxHp: 5,
    speed: 170,  # 170 for better feel
    baseSpeed: 170,
    damage: 1,
    fireRate: 0.45,  #  0.45 for smoother shooting
    bulletSpeed: 300,
    lastShot: 0,
    coins: 0,
    kills: 0,
    walls: 0,
    speedBoostTimer: 0,
    invincibilityTimer: 0,
    fireRateBoostTimer: 0,
    magnetTimer: 0,
    powerUps: @[],
    shieldAngle: 0,
    killsSinceLastHeal: 0,
    regenTimer: 0,
    lastDamageTaken: 0,
    rageStacks: 0,
    critCharge: 0,
    autoShootEnabled: true  # Auto-shoot starts enabled
  )

proc updatePlayer*(player: Player, dt: float32, screenWidth, screenHeight: int32, walls: seq[Wall]) =
  # Update powerup timers
  if player.speedBoostTimer > 0:
    player.speedBoostTimer -= dt
  if player.invincibilityTimer > 0:
    player.invincibilityTimer -= dt
  if player.fireRateBoostTimer > 0:
    player.fireRateBoostTimer -= dt
  if player.magnetTimer > 0:
    player.magnetTimer -= dt
  
  # Calculate current speed with boost
  var currentSpeed = player.speed
  if player.speedBoostTimer > 0:
    currentSpeed *= 1.5
  
  var moveDir = newVector2f(0, 0)
  
  if isKeyDown(W): moveDir.y -= 1
  if isKeyDown(S): moveDir.y += 1
  if isKeyDown(A): moveDir.x -= 1
  if isKeyDown(D): moveDir.x += 1
  
  if moveDir.length() > 0:
    moveDir = moveDir.normalize()
    player.vel = moveDir * currentSpeed
  else:
    player.vel = newVector2f(0, 0)
  
  # Calculate next position
  let nextPos = player.pos + player.vel * dt
  
  # Check wall collisions - player is blocked by walls
  var canMove = true
  for w in walls:
    if checkPlayerWallCollision(nextPos, player.radius, w):
      canMove = false
      break
  
  if canMove:
    player.pos = nextPos
  
  # Clamp to screen
  if player.pos.x < player.radius: player.pos.x = player.radius
  if player.pos.x > screenWidth.float32 - player.radius: player.pos.x = screenWidth.float32 - player.radius
  if player.pos.y < player.radius: player.pos.y = player.radius
  if player.pos.y > screenHeight.float32 - player.radius: player.pos.y = screenHeight.float32 - player.radius
  
  # Scale radius with max HP (grows as player gets stronger)
  player.radius = player.baseRadius + (player.maxHp - 6) * 1
  
  # Update shield angle for rotating shield power-up
  player.shieldAngle += dt * 2.0

proc drawPlayer*(player: Player) =
  # Damage zone visual (if player has it)
  for powerUp in player.powerUps:
    if powerUp.powerType == puDamageZone:
      let zoneRadius = case powerUp.level
        of 1: 50.0
        of 2: 100.0
        else: 150.0
      let alpha = 30 + (sin(player.shieldAngle * 3) * 15).int
      drawCircle(Vector2(x: player.pos.x, y: player.pos.y), zoneRadius, 
                Color(r: 255, g: 100, b: 0, a: alpha.uint8))
    
    # Slow field visual
    if powerUp.powerType == puSlowField:
      let slowRadius = case powerUp.level
        of 1: 150.0
        of 2: 200.0
        else: 250.0
      let alpha = 20 + (sin(player.shieldAngle * 2) * 10).int
      drawCircle(Vector2(x: player.pos.x, y: player.pos.y), slowRadius,
                Color(r: 100, g: 150, b: 255, a: alpha.uint8))
      drawCircleLines(player.pos.x.int32, player.pos.y.int32, slowRadius,
                     Color(r: 100, g: 150, b: 255, a: 80))
  
  # Dodge flash effect
  if player.lastDamageTaken == 0 and player.hp > 0:
    drawText("DODGE!", (player.pos.x - 25).int32, (player.pos.y - 35).int32, 14, Yellow)
    player.lastDamageTaken = -1  # Clear flag
  
  # Invincibility visual effect
  if player.invincibilityTimer > 0:
    let flash = ((player.invincibilityTimer * 10).int mod 2 == 0)
    if flash:
      drawCircle(Vector2(x: player.pos.x, y: player.pos.y), player.radius, Gold)
    else:
      drawCircle(Vector2(x: player.pos.x, y: player.pos.y), player.radius, Blue)
  else:
    drawCircle(Vector2(x: player.pos.x, y: player.pos.y), player.radius, Blue)
  
  drawCircleLines(player.pos.x.int32, player.pos.y.int32, player.radius, DarkBlue)
  
  # Speed boost indicator
  if player.speedBoostTimer > 0:
    drawCircleLines(player.pos.x.int32, player.pos.y.int32, player.radius + 3, Green)
  
  # Rotating shield visual (if player has it) - NERFED with gaps
  for powerUp in player.powerUps:
    if powerUp.powerType == puRotatingShield:
      let level = powerUp.level
      let shieldCount = case level
        of 1: 2
        of 2: 3
        else: 4
      
      # Shield scales with player size for better visual feedback
      let shieldRadius = player.radius * 2.0 + 15
      let shieldThickness = 3.0
      
      # Level-based coverage matches collision: L1=50%, L2=70%, L3=85%
      let arcCoverage = case level
        of 1: 0.50
        of 2: 0.70
        else: 0.85
      
      # Draw partial curved shield lines with visible gaps
      for i in 0..<shieldCount:
        let baseAngle = player.shieldAngle + (i.float32 * PI * 2.0 / shieldCount.float32)
        let fullArcLength = PI * 2.0 / shieldCount.float32
        let activeArcLength = fullArcLength * arcCoverage
        
        # Center the active arc, leaving gaps
        let gapSize = (fullArcLength - activeArcLength) / 2.0
        let angle1 = baseAngle + gapSize
        let angle2 = angle1 + activeArcLength
        
        # Draw arc segments for the ACTIVE portion only
        let segments = 16
        for j in 0..<segments:
          let t1 = j.float32 / segments.float32
          let t2 = (j + 1).float32 / segments.float32
          let a1 = angle1 + t1 * (angle2 - angle1)
          let a2 = angle1 + t2 * (angle2 - angle1)
          
          let x1 = player.pos.x + cos(a1) * shieldRadius
          let y1 = player.pos.y + sin(a1) * shieldRadius
          let x2 = player.pos.x + cos(a2) * shieldRadius
          let y2 = player.pos.y + sin(a2) * shieldRadius
          
          drawLine(Vector2(x: x1, y: y1), Vector2(x: x2, y: y2), shieldThickness, SkyBlue)
        
        # Add energy glow at shield endpoints (shows active coverage)
        let ex1 = player.pos.x + cos(angle1) * shieldRadius
        let ey1 = player.pos.y + sin(angle1) * shieldRadius
        let ex2 = player.pos.x + cos(angle2) * shieldRadius
        let ey2 = player.pos.y + sin(angle2) * shieldRadius
        
        drawCircle(Vector2(x: ex1, y: ey1), 5, Color(r: 135, g: 206, b: 235, a: 200))
        drawCircle(Vector2(x: ex2, y: ey2), 5, Color(r: 135, g: 206, b: 235, a: 200))

proc takeDamage*(player: Player, damage: float32) =
  if player.invincibilityTimer > 0:
    return
  
  # Dodge chance power-up
  for powerUp in player.powerUps:
    if powerUp.powerType == puDodgeChance:
      let dodgeChance = case powerUp.level
        of 1: 12
        of 2: 20
        else: 30
      if rand(99) < dodgeChance:
        # Dodged! Visual feedback
        player.lastDamageTaken = 0
        return
  
  player.hp -= damage
  if player.hp < 0: player.hp = 0
  player.lastDamageTaken = damage

proc heal*(player: Player, amount: float32) =
  player.hp += amount
  if player.hp > player.maxHp: player.hp = player.maxHp

proc activateSpeedBoost*(player: Player) =
  player.speedBoostTimer = 5.0

proc activateInvincibility*(player: Player) =
  player.invincibilityTimer = 3.0

proc activateFireRateBoost*(player: Player) =
  player.fireRateBoostTimer = 8.0

proc activateMagnet*(player: Player) =
  player.magnetTimer = 10.0

proc getCurrentFireRate*(player: Player): float32 =
  var rate = player.fireRate
  
  # Fire rate boost consumable
  if player.fireRateBoostTimer > 0:
    rate *= 0.5
  
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
      rate *= (1.0 / fireRateBonus)  # Lower fire rate value = faster shooting
  
  return rate

proc getCurrentDamage*(player: Player): float32 =
  var damage = player.damage
  
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
      damage *= damageBonus
  
  return damage
