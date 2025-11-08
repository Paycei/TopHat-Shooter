import raylib, types

proc newBullet*(x, y: float32, direction: Vector2f, speed, damage: float32, fromPlayer: bool = true, 
                isHoming: bool = false, isPiercing: bool = false, isExplosive: bool = false,
                hasBounce: bool = false, canSplit: bool = false, slowAmount: float32 = 0, 
                poisonDuration: float32 = 0): Bullet =
  # BUFFED: Faster projectiles across the board
  let finalSpeed = if fromPlayer: speed else: speed * 1.25  # Enemy bullets even faster
  
  result = Bullet(
    pos: newVector2f(x, y),
    vel: direction.normalize() * finalSpeed,
    radius: if fromPlayer: 4 else: 6,
    damage: damage,
    fromPlayer: fromPlayer,
    lifetime: 5.0,  # Bullets despawn after 5 seconds
    isHoming: isHoming,
    isPiercing: isPiercing,
    isExplosive: isExplosive,
    piercedEnemies: 0,
    bounceCount: if hasBounce: 0 else: -1,
    hasSplit: not canSplit,
    slowAmount: slowAmount,
    poisonDuration: poisonDuration
  )

proc updateBullet*(bullet: Bullet, dt: float32): bool =
  bullet.pos = bullet.pos + bullet.vel * dt
  bullet.lifetime -= dt
  return bullet.lifetime > 0

proc drawBullet*(bullet: Bullet) =
  var color = if bullet.fromPlayer: Yellow else: Pink
  
  # Special bullet types have special colors
  if bullet.fromPlayer:
    if bullet.isHoming: color = Magenta
    elif bullet.isPiercing: color = SkyBlue
    elif bullet.isExplosive: color = Orange
    elif bullet.slowAmount > 0: color = Color(r: 150, g: 200, b: 255, a: 255)
    elif bullet.poisonDuration > 0: color = Green
    elif bullet.bounceCount >= 0: color = Color(r: 255, g: 200, b: 0, a: 255)
  
  drawCircle(Vector2(x: bullet.pos.x, y: bullet.pos.y), bullet.radius, color)
  
  # Add glow effect
  if not bullet.fromPlayer:
    drawCircleLines(bullet.pos.x.int32, bullet.pos.y.int32, bullet.radius + 2, 
                   Color(r: 255, g: 100, b: 150, a: 100))
  elif bullet.isExplosive:
    drawCircleLines(bullet.pos.x.int32, bullet.pos.y.int32, bullet.radius + 2, 
                   Color(r: 255, g: 150, b: 0, a: 150))
  elif bullet.slowAmount > 0:
    drawCircleLines(bullet.pos.x.int32, bullet.pos.y.int32, bullet.radius + 2,
                   Color(r: 100, g: 150, b: 255, a: 150))
  elif bullet.poisonDuration > 0:
    drawCircleLines(bullet.pos.x.int32, bullet.pos.y.int32, bullet.radius + 2,
                   Color(r: 50, g: 255, b: 50, a: 150))

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
