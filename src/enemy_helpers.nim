## Enemy Helper Functions
## Centralized attack execution, movement, and special behaviors

import raylib, types, random, math, tables, strutils, enemy_config, bullet, wall, run_statistics

const
  EnemyInertiaAcceleration* = 4.5'f32
  EnemyInertiaBraking* = 1.4'f32
  EnemyInertiaReferenceRadius* = 10.5'f32
  BossInertiaReferenceRadius* = 50.0'f32

proc approachVelocity*(current, target: Vector2f, acceleration, dt: float32): Vector2f =
  ## Framerate-independent velocity easing shared by enemy movement patterns.
  let blend = 1.0'f32 - pow(0.001'f32, acceleration * dt)
  current + (target - current) * clamp(blend, 0.0'f32, 1.0'f32)

proc enemyInertiaSizeScale*(enemy: Enemy): float32 =
  let referenceRadius =
    if enemy.isBoss: BossInertiaReferenceRadius
    else: EnemyInertiaReferenceRadius
  let safeRadius = max(enemy.radius, 1.0'f32)
  clamp(sqrt(safeRadius / referenceRadius), 0.75'f32, 2.4'f32)

proc applyEnemyInertia*(enemy: var Enemy, desiredVel: Vector2f, dt: float32,
                        acceleration: float32 = EnemyInertiaAcceleration,
                        braking: float32 = EnemyInertiaBraking): Vector2f =
  let sizeScale = enemyInertiaSizeScale(enemy)
  let smoothing =
    if desiredVel.length() > 0.01'f32: acceleration / sizeScale
    else: braking / sizeScale
  enemy.vel = approachVelocity(enemy.vel, desiredVel, smoothing, dt)
  enemy.vel

proc desiredVelocityFromNext*(currentPos, desiredNextPos: Vector2f, dt: float32): Vector2f =
  if dt <= 0:
    return newVector2f(0, 0)
  (desiredNextPos - currentPos) * (1.0'f32 / dt)

proc nextInertialEnemyPos*(enemy: var Enemy, desiredNextPos: Vector2f, dt: float32): Vector2f =
  let desiredVel = desiredVelocityFromNext(enemy.pos, desiredNextPos, dt)
  enemy.pos + applyEnemyInertia(enemy, desiredVel, dt) * dt

# SPECIAL DATA PARSING
proc parseSpecialData*(data: string): Table[string, string] =
  ## Parse special behavior data string into key-value table
  ## Format: "key1:value1|key2:value2|key3:value3"
  result = initTable[string, string]()

  if data.len == 0:
    return

  for pair in data.split('|'):
    let parts = pair.split(':')
    if parts.len == 2:
      result[parts[0].strip()] = parts[1].strip()

proc getSpecialFloat*(data: Table[string, string], key: string, default: float32): float32 =
  ## Get float value from special data with fallback
  if data.hasKey(key):
    try:
      return data[key].parseFloat().float32
    except:
      return default
  return default

proc getSpecialInt*(data: Table[string, string], key: string, default: int): int =
  ## Get int value from special data with fallback
  if data.hasKey(key):
    try:
      return data[key].parseInt()
    except:
      return default
  return default

# ATTACK EXECUTION

proc executeRangedAttack*(enemy: var Enemy, playerPos: Vector2f, game: var Game) =
  ## Centralized ranged attack execution using enemy config
  ## Replaces all hardcoded bullet creation logic

  let config = getEnemyConfig(enemy.enemyType)

  # Skip if enemy doesn't have ranged attacks
  if not config.hasRangedAttack:
    return

  # Check if enemy can shoot (timer check)
  if enemy.shootTimer < config.attack.fireRate:
    return

  # Skip if hasn't entered screen yet
  if config.requiresScreenEntry and not enemy.hasEnteredScreen:
    return

  # Get attack configuration
  let attack = config.attack
  let dir = (playerPos - enemy.pos).normalize()

  # Determine bullet count (with randomization support)
  var bulletCount = attack.bulletCount
  if attack.randomizeBulletCount and attack.bulletCountMin > 0 and attack.bulletCountMax > 0:
    bulletCount = attack.bulletCountMin + rand(attack.bulletCountMax - attack.bulletCountMin)

  # Fire bullets with spread pattern
  for i in 0..<bulletCount:
    var bulletDir = dir

    # Apply spread angle (for multi-shot)
    if bulletCount > 1 and attack.spreadAngle > 0:
      # For random full-circle spread (Hexagon)
      if attack.spreadAngle > 6.0:  # Full circle
        let randomAngle = rand(1.0) * PI * 2.0
        bulletDir = newVector2f(cos(randomAngle), sin(randomAngle))
      else:
        # Linear spread
        let spreadOffset = (i.float32 - (bulletCount - 1).float32 / 2.0) * (attack.spreadAngle / max(1.0, (bulletCount - 1).float32))
        bulletDir = newVector2f(
          dir.x * cos(spreadOffset) - dir.y * sin(spreadOffset),
          dir.x * sin(spreadOffset) + dir.y * cos(spreadOffset)
        )

    # Apply inaccuracy (random spread)
    if attack.inaccuracyAmount > 0:
      let inaccuracy = (rand(1.0) - 0.5) * attack.inaccuracyAmount
      bulletDir = newVector2f(
        bulletDir.x * cos(inaccuracy) - bulletDir.y * sin(inaccuracy),
        bulletDir.x * sin(inaccuracy) + bulletDir.y * cos(inaccuracy)
      )

    # Create bullet with config parameters
    let bullet = newBullet(
      x = enemy.pos.x,
      y = enemy.pos.y,
      direction = bulletDir,
      speed = attack.bulletSpeed,
      damage = attack.damage,
      fromPlayer = false,
      isHoming = attack.homingStrength > 0.0,
      isPiercing = false,
      isExplosive = false,
      hasBounce = false,
      canSplit = false,
      slowAmount = 0.0,
      poisonDuration = 0.0,
      fireDuration = 0.0,
      windPushForce = 0.0,
      isPentagon = attack.isPentagonBullet,
      isEcho = false,
      isBossBullet = false,
      sourceEnemyId = enemy.id,
      sourceEnemyType = enemy.enemyType
    )

    # Set custom bullet size if specified
    if attack.bulletRadius > 0:
      bullet.radius = attack.bulletRadius

    game.bullets.add(bullet)

  # Reset shoot timer
  enemy.shootTimer = 0

# MOVEMENT HELPERS

proc maintainOptimalDistance*(enemy: Enemy, playerPos: Vector2f, dt: float32, effectiveSpeed: float32, config: EnemyConfig): Vector2f =
  ## Movement behavior for ranged enemies that maintain distance
  ## Returns next position based on distance to player

  if not config.movement.maintainsDistance:
    return enemy.pos

  let dir = (playerPos - enemy.pos).normalize()
  let distToPlayer = distance(enemy.pos, playerPos)
  let movement = config.movement

  # Retreat when too close
  if distToPlayer < movement.retreatDistance:
    let retreatDir = dir * -1.0
    return enemy.pos + retreatDir * effectiveSpeed * dt

  # Approach when too far
  elif distToPlayer > movement.optimalDistance:
    return enemy.pos + dir * effectiveSpeed * 0.5 * dt

  # Optimal range - strafe/float sideways
  else:
    let tangent = newVector2f(-dir.y, dir.x)
    return enemy.pos + tangent * effectiveSpeed * 0.3 * dt

proc forceScreenEntry*(enemy: Enemy, playerPos: Vector2f, dt: float32, effectiveSpeed: float32, game: Game): Vector2f =
  ## Force ranged enemies to enter screen before engaging
  ## Returns position moving toward screen center

  # If already entered, return current position
  if enemy.hasEnteredScreen:
    return enemy.pos

  # Move toward screen center
  let screenCenterX = game.screenWidth.float32 / 2.0
  let screenCenterY = game.screenHeight.float32 / 2.0
  let towardCenter = (newVector2f(screenCenterX, screenCenterY) - enemy.pos).normalize()

  return enemy.pos + towardCenter * effectiveSpeed * dt

proc checkScreenEntry*(enemy: var Enemy, game: Game) =
  ## Check if enemy has fully entered screen bounds
  if not enemy.hasEnteredScreen:
    if enemy.pos.x > enemy.radius and enemy.pos.x < game.screenWidth.float32 - enemy.radius and
       enemy.pos.y > enemy.radius and enemy.pos.y < game.screenHeight.float32 - enemy.radius:
      enemy.hasEnteredScreen = true

proc checkScreenBoundaryCollision*(enemy: Enemy, nextPos: Vector2f, game: Game, config: EnemyConfig): bool =
  ## Check if ranged enemy would leave screen bounds
  ## Returns true if movement should be blocked

  # Only applies to ranged enemies that entered screen
  if not config.requiresScreenEntry or not enemy.hasEnteredScreen:
    return false

  # Check if next position is off-screen
  let isOffScreen = nextPos.x < enemy.radius or nextPos.x > game.screenWidth.float32 - enemy.radius or
                   nextPos.y < enemy.radius or nextPos.y > game.screenHeight.float32 - enemy.radius

  if not isOffScreen:
    return false

  # Block movement if moving away from center
  let screenCenterX = game.screenWidth.float32 / 2.0
  let screenCenterY = game.screenHeight.float32 / 2.0
  let towardCenter = (newVector2f(screenCenterX, screenCenterY) - enemy.pos).normalize()
  let movementDir = (nextPos - enemy.pos).normalize()
  let dotProduct = towardCenter.x * movementDir.x + towardCenter.y * movementDir.y

  return dotProduct < 0  # Block if moving away from center

# COLLISION HELPERS

proc checkWallCollision*(enemy: var Enemy, nextPos: Vector2f, walls: seq[Wall], currentTime: float32, game: var Game): bool =
  ## Check wall collision and apply damage
  ## Returns true if collision occurred

  for wall in walls:
    if distance(nextPos, wall.pos) < enemy.radius + wall.radius:
      # Apply periodic wall damage
      if currentTime - enemy.lastWallDamageTime >= 1.0:
        wall.takeDamage(1.0)
        trackWallDamaged(game)
        enemy.hp -= 1.0
        enemy.lastWallDamageTime = currentTime
      return true

  return false

# SIMPLE MOVEMENT PATTERNS

proc chasePlayer*(enemy: Enemy, playerPos: Vector2f, dt: float32, effectiveSpeed: float32): Vector2f =
  ## Simple chase movement toward player
  let dir = (playerPos - enemy.pos).normalize()
  return enemy.pos + dir * effectiveSpeed * dt
