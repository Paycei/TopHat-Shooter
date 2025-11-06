import raylib, types

proc newBullet*(x, y: float32, direction: Vector2f, speed, damage: float32, fromPlayer: bool = true): Bullet =
  # BUFFED: Faster projectiles across the board
  let finalSpeed = if fromPlayer: speed else: speed * 1.25  # Enemy bullets even faster
  
  result = Bullet(
    pos: newVector2f(x, y),
    vel: direction.normalize() * finalSpeed,
    radius: if fromPlayer: 4 else: 6,
    damage: damage,
    fromPlayer: fromPlayer,
    lifetime: 5.0  # Bullets despawn after 5 seconds
  )

proc updateBullet*(bullet: Bullet, dt: float32): bool =
  bullet.pos = bullet.pos + bullet.vel * dt
  bullet.lifetime -= dt
  return bullet.lifetime > 0

proc drawBullet*(bullet: Bullet) =
  let color = if bullet.fromPlayer: Yellow else: Pink
  drawCircle(Vector2(x: bullet.pos.x, y: bullet.pos.y), bullet.radius, color)
  
  # Add glow effect for more visual chaos
  if not bullet.fromPlayer:
    drawCircleLines(bullet.pos.x.int32, bullet.pos.y.int32, bullet.radius + 2, 
                   Color(r: 255, g: 100, b: 150, a: 100))

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
