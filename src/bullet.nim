import raylib, types, math

const BASE_PLAYER_BULLET_RADIUS* = 4.5

proc newBullet*(x, y: float32, direction: Vector2f, speed, damage: float32, fromPlayer: bool = true, 
                isHoming: bool = false, isPiercing: bool = false, isExplosive: bool = false,
                hasBounce: bool = false, canSplit: bool = false, slowAmount: float32 = 0, 
                poisonDuration: float32 = 0, fireDuration: float32 = 0, windPushForce: float32 = 0,
                isPentagon: bool = false, isEcho: bool = false, 
                isBossBullet: bool = false): Bullet =
  # BUFFED: Faster projectiles across the board
  let finalSpeed = if fromPlayer: speed else: speed * 1.25  # Enemy bullets even faster
  
  result = Bullet(
    pos: newVector2f(x, y),
    vel: direction.normalize() * finalSpeed,
    radius: if fromPlayer: BASE_PLAYER_BULLET_RADIUS else: 6,
    damage: damage,
    fromPlayer: fromPlayer,
    lifetime: 4.0,  # Bullets despawn after 3 seconds (reduced from 5)
    isHoming: isHoming,
    isPiercing: isPiercing,
    isExplosive: isExplosive,
    piercedEnemies: 0,
    bounceCount: if hasBounce: 0 else: -1,
    hasSplit: not canSplit,
    slowAmount: slowAmount,  # Slow effect magnitude (0-1 range)
    poisonDuration: poisonDuration,  # Poison duration in seconds
    fireDuration: fireDuration,  # Fire duration in seconds
    windPushForce: windPushForce,  # Wind push force
    isPentagon: isPentagon,
    hitEnemies: @[],  # Initialize empty sequence
    travelDistance: 0.0,  # Track distance for Overcharge
    isEcho: isEcho,  # Whether this is an echo trail bullet
    echoTrailTimer: 0.0,  # Timer for spawning echo trails
    isBossBullet: isBossBullet  # Mark boss bullets for glow effect
  )

proc updateBullet*(bullet: Bullet, dt: float32): bool =
  # Track distance traveled for Overcharge power-up
  let movement = bullet.vel * dt
  bullet.travelDistance += movement.length()
  
  bullet.pos = bullet.pos + movement
  bullet.lifetime -= dt
  return bullet.lifetime > 0

proc drawBullet*(bullet: Bullet, hasOvercharge: bool = false) =
  var color = if bullet.fromPlayer: Yellow else: Pink
  
  # Echo bullets are semi-transparent and fade out
  if bullet.isEcho:
    let fadeAlpha = uint8((bullet.lifetime / 0.5) * 150.0)  # Fade based on remaining lifetime
    color = Color(r: 200, g: 200, b: 255, a: fadeAlpha)  # Ghost blue-white
  
  # Special bullet types have special colors
  if bullet.fromPlayer and not bullet.isEcho:
    if bullet.isHoming: color = Magenta
    elif bullet.isPiercing: color = SkyBlue
    elif bullet.isExplosive: color = Orange
    elif bullet.windPushForce > 0: color = Color(r: 200, g: 230, b: 255, a: 255)  # Light cyan for wind
    elif bullet.slowAmount > 0: color = Color(r: 150, g: 200, b: 255, a: 255)
    elif bullet.poisonDuration > 0: color = Green
    elif bullet.bounceCount >= 0: color = Color(r: 255, g: 200, b: 0, a: 255)
  
  # Draw pentagon shape for pentagon bullets
  if bullet.isPentagon:
    # Draw pentagon shape
    let points = 5
    for i in 0..<points:
      let angle = i.float32 * PI * 2.0 / 5.0 - PI / 2.0  # Start from top
      let nextAngle = (i + 1).float32 * PI * 2.0 / 5.0 - PI / 2.0
      let x1 = bullet.pos.x + cos(angle) * bullet.radius
      let y1 = bullet.pos.y + sin(angle) * bullet.radius
      let x2 = bullet.pos.x + cos(nextAngle) * bullet.radius
      let y2 = bullet.pos.y + sin(nextAngle) * bullet.radius
      drawLine(Vector2(x: x1, y: y1), Vector2(x: x2, y: y2), 3, color)
    # Fill center
    drawCircle(Vector2(x: bullet.pos.x, y: bullet.pos.y), bullet.radius * 0.5, color)
  else:
    # Normal circle bullet
    drawCircle(Vector2(x: bullet.pos.x, y: bullet.pos.y), bullet.radius, color)
  
  # Add glow effect
  if not bullet.fromPlayer:
    # Boss bullets get a special strong glow effect
    if bullet.isBossBullet:
      # Multiple glow rings for boss bullets
      drawCircleLines(bullet.pos.x.int32, bullet.pos.y.int32, bullet.radius + 4, 
                     Color(r: 255, g: 50, b: 150, a: 200))
      drawCircleLines(bullet.pos.x.int32, bullet.pos.y.int32, bullet.radius + 7, 
                     Color(r: 255, g: 100, b: 150, a: 120))
      drawCircleLines(bullet.pos.x.int32, bullet.pos.y.int32, bullet.radius + 10, 
                     Color(r: 255, g: 150, b: 180, a: 60))
    elif bullet.isPentagon:
      # Pentagon glow
      for i in 0..<5:
        let angle = i.float32 * PI * 2.0 / 5.0 - PI / 2.0
        let nextAngle = (i + 1).float32 * PI * 2.0 / 5.0 - PI / 2.0
        let x1 = bullet.pos.x + cos(angle) * (bullet.radius + 3)
        let y1 = bullet.pos.y + sin(angle) * (bullet.radius + 3)
        let x2 = bullet.pos.x + cos(nextAngle) * (bullet.radius + 3)
        let y2 = bullet.pos.y + sin(nextAngle) * (bullet.radius + 3)
        drawLine(Vector2(x: x1, y: y1), Vector2(x: x2, y: y2), 2,
                Color(r: 0, g: 200, b: 150, a: 100))
    else:
      drawCircleLines(bullet.pos.x.int32, bullet.pos.y.int32, bullet.radius + 2, 
                     Color(r: 255, g: 100, b: 150, a: 100))
  elif bullet.isExplosive:
    drawCircleLines(bullet.pos.x.int32, bullet.pos.y.int32, bullet.radius + 2, 
                   Color(r: 255, g: 150, b: 0, a: 150))
  elif bullet.windPushForce > 0:
    drawCircleLines(bullet.pos.x.int32, bullet.pos.y.int32, bullet.radius + 2,
                   Color(r: 180, g: 220, b: 255, a: 150))
  elif bullet.slowAmount > 0:
    drawCircleLines(bullet.pos.x.int32, bullet.pos.y.int32, bullet.radius + 2,
                   Color(r: 100, g: 150, b: 255, a: 150))
  elif bullet.poisonDuration > 0:
    drawCircleLines(bullet.pos.x.int32, bullet.pos.y.int32, bullet.radius + 2,
                   Color(r: 50, g: 255, b: 50, a: 150))
  
  # Overcharge visual effect - ONLY if player has the power-up
  if hasOvercharge and bullet.fromPlayer and bullet.travelDistance > 0:
    # Calculate charge level based on distance (0.0 to 1.0)
    let chargeLevel = min(bullet.travelDistance / 2500.0, 1.0)  # Max at 2500 units
    
    if chargeLevel > 0.1:  # Only show glow when bullet has traveled some distance
      # Color shift: Yellow (low) → Orange (mid) → Red (high)
      let glowColor = if chargeLevel < 0.33:
        # Yellow to Orange
        let t = chargeLevel / 0.33
        Color(
          r: 255,
          g: uint8(255.0 - t * 100.0),  # 255 → 155
          b: 0,
          a: uint8(100.0 + chargeLevel * 100.0)
        )
      elif chargeLevel < 0.66:
        # Orange to Red
        let t = (chargeLevel - 0.33) / 0.33
        Color(
          r: 255,
          g: uint8(155.0 - t * 155.0),  # 155 → 0
          b: 0,
          a: uint8(100.0 + chargeLevel * 100.0)
        )
      else:
        # Deep Red (max charge)
        Color(
          r: 255,
          g: 0,
          b: 0,
          a: uint8(100.0 + chargeLevel * 100.0)
        )
      
      # Draw expanding glow rings
      let glowRadius = bullet.radius + 2 + chargeLevel * 4
      drawCircleLines(bullet.pos.x.int32, bullet.pos.y.int32, glowRadius, glowColor)
      
      # Add a second, larger glow ring for high charge
      if chargeLevel > 0.5:
        let outerGlow = glowColor
        let outerRadius = glowRadius + 3
        drawCircleLines(bullet.pos.x.int32, bullet.pos.y.int32, outerRadius, 
                       Color(r: outerGlow.r, g: outerGlow.g, b: outerGlow.b, a: outerGlow.a div 2))

proc isOffScreen*(bullet: Bullet, screenWidth, screenHeight: int32): bool =
  bullet.pos.x < -50 or bullet.pos.x > screenWidth.float32 + 50 or
  bullet.pos.y < -50 or bullet.pos.y > screenHeight.float32 + 50

proc checkBulletEnemyCollision*(bullet: Bullet, enemy: Enemy): bool =
  if not bullet.fromPlayer: return false
  distance(bullet.pos, enemy.pos) < bullet.radius + enemy.radius

proc checkBulletPlayerCollision*(bullet: Bullet, player: Player): bool =
  if bullet.fromPlayer: return false
  distance(bullet.pos, player.pos) < bullet.radius + player.radius

proc checkBulletWallCollision*(bullet: Bullet, wall: Wall): bool =
  if bullet.fromPlayer: return false # Player bullets pass through walls
  distance(bullet.pos, wall.pos) < bullet.radius + wall.radius

proc checkShieldCollision*(bullet: Bullet, shieldPos: Vector2f): bool =
  # Check if enemy bullet hits player's rotating shield
  if bullet.fromPlayer: return false
  distance(bullet.pos, shieldPos) < bullet.radius + 6

## Utility functions for bullet synergies and cloning

proc cloneBullet*(original: Bullet, newPos: Vector2f, newVel: Vector2f, 
                  damageMultiplier: float32 = 1.0, speedMultiplier: float32 = 1.0,
                  radiusMultiplier: float32 = 1.0, preventSplit: bool = false): Bullet =
  ## Clone a bullet preserving ALL its properties for perfect synergy
  ## This ensures Split Shot, Echo, and other effects inherit all bullet modifiers
  result = newBullet(
    newPos.x, newPos.y, newVel.normalize(),
    original.vel.length() * speedMultiplier,
    original.damage * damageMultiplier,
    original.fromPlayer,
    original.isHoming,
    original.isPiercing,
    original.isExplosive,
    original.bounceCount >= 0,  # hasBounce
    not preventSplit,  # canSplit (inverse of preventSplit)
    original.slowAmount,
    original.poisonDuration,
    original.fireDuration,
    original.windPushForce,  # Preserve wind push force
    original.isPentagon,
    original.isEcho,
    original.isBossBullet
  )
  
  # Copy additional state that needs to be preserved
  result.radius = original.radius * radiusMultiplier
  result.travelDistance = original.travelDistance  # Preserve Overcharge progress
  result.bounceCount = original.bounceCount  # Preserve ricochet state
  result.piercedEnemies = original.piercedEnemies  # Preserve pierce state
  result.hasSplit = preventSplit or original.hasSplit  # Preserve split state
  
  # Copy hit enemies list for independent tracking
  for enemyIdx in original.hitEnemies:
    result.hitEnemies.add(enemyIdx)

proc createSplitBullets*(game: Game, sourceBullet: Bullet, splitCount: int, 
                        damageMultiplier: float32 = 0.5, speedMultiplier: float32 = 0.7) =
  ## Create split bullets that inherit ALL properties from source bullet
  ## SYNERGY SYSTEM: Split bullets maintain explosive, homing, piercing, poison, etc.
  for split in 0..<splitCount:
    let angle = split.float32 * PI * 2.0 / splitCount.float32
    let dir = newVector2f(cos(angle), sin(angle))
    let vel = dir * sourceBullet.vel.length() * speedMultiplier
    
    let splitBullet = cloneBullet(
      sourceBullet,
      sourceBullet.pos,
      vel,
      damageMultiplier,
      speedMultiplier,
      0.9,  # Slightly smaller radius
      true  # Prevent infinite splitting
    )
    
    game.bullets.add(splitBullet)

proc createRicochetBullet*(game: Game, sourceBullet: Bullet, targetPos: Vector2f,
                          damageMultiplier: float32 = 0.75) =
  ## Create a ricochet bullet that inherits ALL properties
  ## SYNERGY SYSTEM: Ricochet bullets can split, explode, poison, etc.
  let toTarget = (targetPos - sourceBullet.pos).normalize()
  let vel = toTarget * sourceBullet.vel.length()
  
  let ricochetBullet = cloneBullet(
    sourceBullet,
    sourceBullet.pos,
    vel,
    damageMultiplier,
    1.0,  # Same speed
    1.0,  # Same size
    false  # Can still split
  )
  
  # Increment bounce count for the new bullet
  ricochetBullet.bounceCount += 1
  
  game.bullets.add(ricochetBullet)

proc createEchoBullet*(game: Game, sourceBullet: Bullet, 
                      damageMultiplier: float32 = 0.4, speedMultiplier: float32 = 0.5,
                      lifetime: float32 = 0.35) =
  ## Create an echo trail bullet that inherits ALL properties
  ## SYNERGY SYSTEM: Echo bullets can split, ricochet, explode, etc.
  let echoBullet = cloneBullet(
    sourceBullet,
    sourceBullet.pos,
    sourceBullet.vel,
    damageMultiplier,
    speedMultiplier,
    0.8,  # Slightly smaller
    false  # Can split (for echo + split synergy)
  )
  
  # Make it an echo bullet with limited lifetime
  echoBullet.isEcho = true
  echoBullet.lifetime = lifetime
  
  # Reset bounce count for echoes (they get fresh ricochets)
  if echoBullet.bounceCount >= 0:
    echoBullet.bounceCount = 0
  
  game.bullets.add(echoBullet)
