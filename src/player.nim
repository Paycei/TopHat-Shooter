import raylib, types, math

proc newPlayer*(x, y: float32): Player =
  result = Player(
    pos: newVector2f(x, y),
    vel: newVector2f(0, 0),
    radius: 12,
    baseRadius: 12,
    hp: 2,  # Nerfed from 3
    maxHp: 2,
    speed: 180,  # Nerfed from 200
    baseSpeed: 180,
    damage: 1,
    fireRate: 0.4,  # Nerfed from 0.3 (slower)
    bulletSpeed: 400,
    lastShot: 0,
    autoShoot: false,
    coins: 0,
    kills: 0,
    walls: 0,
    speedBoostTimer: 0,
    invincibilityTimer: 0,
    fireRateBoostTimer: 0,
    magnetTimer: 0
  )

proc updatePlayer*(player: Player, dt: float32, screenWidth, screenHeight: int32) =
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
  
  player.pos = player.pos + player.vel * dt
  
  # Clamp to screen
  if player.pos.x < player.radius: player.pos.x = player.radius
  if player.pos.x > screenWidth.float32 - player.radius: player.pos.x = screenWidth.float32 - player.radius
  if player.pos.y < player.radius: player.pos.y = player.radius
  if player.pos.y > screenHeight.float32 - player.radius: player.pos.y = screenHeight.float32 - player.radius
  
  # Scale radius with max HP (grows as player gets stronger)
  player.radius = player.baseRadius + (player.maxHp - 2) * 1.5

proc drawPlayer*(player: Player) =
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

proc takeDamage*(player: Player, damage: float32) =
  if player.invincibilityTimer > 0:
    return
  player.hp -= damage
  if player.hp < 0: player.hp = 0

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
  if player.fireRateBoostTimer > 0:
    return player.fireRate * 0.5
  return player.fireRate
