import raylib, types, wall, math, random, std/tables

proc newPlayer*(x, y: float32): Player =
  result = Player(
    pos: newVector2f(x, y),
    vel: newVector2f(0, 0),
    radius: 14,
    baseRadius: 14,
    hp: 7,
    maxHp: 7,
    speed: 175,
    baseSpeed: 175,
    damage: 1,
    fireRate: 0.42,
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
    autoShootEnabled: true,  # Auto-shoot starts enabled
    activePowerUps: @[],
    powerUpTimers: initTable[PowerUpType, float32](),
    auraRadius: 50.0,  # Invisible coin collection aura
    doubleShotDelay: 0,
    # Initialize legendary power-up cooldowns
    timeWarpCooldown: 0,
    timeWarpActive: false,
    timeWarpDuration: 0,
    timeWarpUsesThisWave: 0,
    timeWarpMaxUsesPerWave: 1,  # Default to level 1
    phaseShiftCooldown: 0,
    phaseShiftInvulnTimer: 0,
    lastPhaseShiftPos: newVector2f(x, y)
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
  
  # Update double-shot delay timer
  if player.doubleShotDelay > 0:
    player.doubleShotDelay -= dt
  
  # Update legendary power-up cooldowns
  if player.timeWarpCooldown > 0:
    player.timeWarpCooldown -= dt
  if player.timeWarpDuration > 0:
    player.timeWarpDuration -= dt
    if player.timeWarpDuration <= 0:
      player.timeWarpActive = false
  if player.phaseShiftCooldown > 0:
    player.phaseShiftCooldown -= dt
  if player.phaseShiftInvulnTimer > 0:
    player.phaseShiftInvulnTimer -= dt
  
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
  
  # Scale radius with max HP using square root for diminishing returns
  # Formula: baseRadius + sqrt(maxHp - 7) * scaleFactor
  # This makes high HP less impactful on size than low HP gains
  # At 7 HP (starting): 14 + sqrt(0) * 2 = 14 (same as base)
  # At 11 HP: 14 + sqrt(4) * 2 = 14 + 4.0 = 18.0 (was 19 with linear)
  # At 21 HP: 14 + sqrt(14) * 2 = 14 + 7.48 = 21.48 (was 29 with linear)
  let hpAboveBase = max(0.0, player.maxHp - 7.0)
  player.radius = player.baseRadius + sqrt(hpAboveBase) * 2.0
  
  # Scale aura with player radius - MUCH LARGER collection area
  player.auraRadius = player.radius * 3.5  # 3.5x player size for generous collection
  
  # Update shield angle for rotating shield power-up - NERFED rotation speed
  player.shieldAngle += dt * 1.0  # Reduced from 2.0 to 1.0 (50% slower)

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
    
    # Slow field visual - NERFED, smaller and more transparent
    if powerUp.powerType == puSlowField:
      let slowRadius = case powerUp.level
        of 1: 120.0  # NERFED from 150
        of 2: 160.0  # NERFED from 200
        else: 200.0  # NERFED from 250
      let alpha = 15 + (sin(player.shieldAngle * 2) * 8).int  # More transparent
      drawCircle(Vector2(x: player.pos.x, y: player.pos.y), slowRadius,
                Color(r: 100, g: 150, b: 255, a: alpha.uint8))
      drawCircleLines(player.pos.x.int32, player.pos.y.int32, slowRadius,
                     Color(r: 100, g: 150, b: 255, a: 60))  # Less visible
  
  # NOTE: Coin collection aura is INVISIBLE - no visual rendering
  
  # Dodge flash effect
  if player.lastDamageTaken == 0 and player.hp > 0:
    drawText("DODGE!", (player.pos.x - 25).int32, (player.pos.y - 35).int32, 14, Yellow)
    player.lastDamageTaken = -1  # Clear flag
  
  # Phase Shift invulnerability visual effect
  if player.phaseShiftInvulnTimer > 0:
    let pulseAlpha = (sin(player.phaseShiftInvulnTimer * 20.0) * 50 + 150).int
    drawCircle(Vector2(x: player.pos.x, y: player.pos.y), player.radius + 5, 
              Color(r: 0, g: 255, b: 255, a: pulseAlpha.uint8))
    drawCircle(Vector2(x: player.pos.x, y: player.pos.y), player.radius, 
              Color(r: 100, g: 255, b: 255, a: 200))
  # Invincibility visual effect
  elif player.invincibilityTimer > 0:
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
      let shieldRadius = player.radius * 2.5 + 15  # Reduced from +15 to +10
      let shieldThickness = 3.0
      
      # Level-based coverage matches collision: NERFED values
      let arcCoverage = case level
        of 1: 0.25  # 10% coverage (was 50%)
        of 2: 0.35  # 20% coverage (was 70%)
        else: 0.45  # 35% coverage (was 85%)
      
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

proc takeDamage*(player: Player, damage: float32): bool =
  ## Returns true if player died (HP reached 0), false otherwise
  # Invincibility from consumables
  if player.invincibilityTimer > 0:
    return false
  
  # Phase Shift invulnerability
  if player.phaseShiftInvulnTimer > 0:
    return false
  
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
        return false
  
  let hpBefore = player.hp
  player.hp -= damage
  if player.hp < 0: player.hp = 0
  player.lastDamageTaken = damage
  
  # Return true only if HP reached 0 from a positive value
  return hpBefore > 0 and player.hp <= 0

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
    rate *= 0.6
  
  # Double Shot penalty - 40% slower fire rate
  for powerUp in player.powerUps:
    if powerUp.powerType == puDoubleShot:
      rate *= 1.4  # 40% slower (higher value = slower)
  
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
