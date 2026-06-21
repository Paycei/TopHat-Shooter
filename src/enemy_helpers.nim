## Enemy Helper Functions
## Centralized attack execution, movement, and special behaviors

import raylib, random, math, tables, strutils
import particle_types
import types, enemy_config, bullet, wall, run_statistics

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
  # Per-enemy damage (newEnemy seeds it from the config) so elite bonuses and
  # dungeon stat tuning actually reach the bullets, instead of the raw config.
  let bulletDamage = if enemy.rangedDamage > 0: enemy.rangedDamage
                     else: attack.damage
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
      damage = bulletDamage,
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
    if wallOverlapsCircle(wall, nextPos, enemy.radius):
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

# UNIFORM SPATIAL HASH GRID: proximity-query acceleration
#
# Purpose: replace the O(n²) / O(bullets × enemies) "scan every enemy" loops in
# game.nim with O(n) neighbourhood queries. A bullet only ever collides with an
# enemy a few pixels away. This grid buckets enemy indices by screen cell so a query
# returns only the handful of enemies in the cells overlapping a small AABB.
#
#  - It stores enemy *indices* into `game.enemies`, valid only for one frame.
#    The bullet loop never adds/deletes enemies, so indices stay stable while a
#    grid is in use (rebuild once, query many).
#  - Queries are *non-lossy supersets*: `nearby(pos, r)` yields every index whose
#    cell overlaps the r-radius AABB around `pos`. Callers pass r large enough to
#    cover the real hit distance (`bullet.radius + maxEnemyRadius`), then re-run
#    the *exact* original distance test on each candidate. Enemies the grid skips
#    are provably beyond hit range, so skipping them changes nothing.
#  - Off-grid (far off-screen) enemies clamp into edge cells. They can only be
#    returned for edge queries, where the caller's distance test rejects them
#    no false hits and any *real* collision happens on-screen where binning is
#    exact, so no real hit is ever missed.
#  - Buckets are reused across frames (`setLen(0)` keeps capacity) so steady-state
#    rebuilds allocate nothing. Inline iterators yield without allocating either.

type
  SpatialGrid* = object
    cellSize: float32
    cols, rows: int
    originX, originY: float32        ## world coord of cell (0,0)'s top-left corner
    cells: seq[seq[int32]]           ## row-major cols*rows buckets, reused across rebuilds

proc gridClampi(v, lo, hi: int): int {.inline.} =
  if v < lo: lo elif v > hi: hi else: v

proc rebuild*(grid: var SpatialGrid, enemies: seq[Enemy],
              cellSize, minX, minY, maxX, maxY: float32) =
  ## Re-bin every enemy index into the grid. O(enemy count). Call once per frame
  ## before a batch of queries; the produced indices are valid until `game.enemies`
  ## is next mutated (add/delete), which must not happen between rebuild and use.
  grid.cellSize = max(1.0'f32, cellSize)
  grid.originX = minX
  grid.originY = minY
  let cols = max(1, int((maxX - minX) / grid.cellSize) + 1)
  let rows = max(1, int((maxY - minY) / grid.cellSize) + 1)
  let needed = cols * rows
  if grid.cells.len < needed:
    grid.cells.setLen(needed)
  grid.cols = cols
  grid.rows = rows

  # Clear only the in-range buckets (keep their capacity for next frame).
  for i in 0 ..< needed:
    grid.cells[i].setLen(0)

  let invCell = 1.0'f32 / grid.cellSize
  for idx in 0 ..< enemies.len:
    let p = enemies[idx].pos
    let cx = gridClampi(int((p.x - minX) * invCell), 0, cols - 1)
    let cy = gridClampi(int((p.y - minY) * invCell), 0, rows - 1)
    grid.cells[cy * cols + cx].add(int32(idx))

iterator nearby*(grid: SpatialGrid, pos: Vector2f, radius: float32): int =
  ## Yield every enemy index in the cells overlapping the AABB
  ## [pos - radius, pos + radius]. A non-lossy superset of the enemies within
  ## `radius` of `pos`; the caller must still run its precise distance test.
  ## No allocation, safe to call per-bullet in a hot loop.
  if grid.cols > 0 and grid.rows > 0:
    let invCell = 1.0'f32 / grid.cellSize
    let r = max(0.0'f32, radius)
    let minCx = gridClampi(int((pos.x - r - grid.originX) * invCell), 0, grid.cols - 1)
    let maxCx = gridClampi(int((pos.x + r - grid.originX) * invCell), 0, grid.cols - 1)
    let minCy = gridClampi(int((pos.y - r - grid.originY) * invCell), 0, grid.rows - 1)
    let maxCy = gridClampi(int((pos.y + r - grid.originY) * invCell), 0, grid.rows - 1)
    for cy in minCy .. maxCy:
      let rowBase = cy * grid.cols
      for cx in minCx .. maxCx:
        for idx in grid.cells[rowBase + cx]:
          yield int(idx)
