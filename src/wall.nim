import raylib
import types, powerup

proc newWall*(x, y: float32, player: Player): Wall =
  # Calculate HP based on WallMaster powerup
  let baseHp = 10.0
  let wallMasterLevel = getPowerUpLevel(player, puWallMaster)
  let hpMultiplier = case wallMasterLevel
    of 1: 2.5
    else: 1.0

  let maxHp = baseHp * hpMultiplier

  result = Wall(
    pos: newVector2f(x, y),
    radius: 25,
    hp: maxHp,
    maxHp: maxHp,
    duration: 30.0,
    shootTimer: 0.0  # Initialize ready to shoot
  )

proc updateWall*(wall: Wall, dt: float32): bool =
  if wall.permanent:
    # Dungeon obstacles ignore the duration timer, but enemies (and bosses) can
    # now smash them: a permanent wall lives only while it still has HP.
    return wall.hp > 0
  wall.duration -= dt
  return wall.hp > 0 and wall.duration > 0

proc drawWall*(wall: Wall, player: Player) =
  if wall.permanent:
    # Dungeon obstacle: solid block tinted with the floor theme accent
    let tint = wall.obstacleTint
    let body = Color(r: uint8(tint.r div 3), g: uint8(tint.g div 3),
                     b: uint8(tint.b div 3), a: 255)
    drawCircle(Vector2(x: wall.pos.x, y: wall.pos.y), wall.radius, body)
    drawCircleLines(wall.pos.x.int32, wall.pos.y.int32, wall.radius, tint)
    drawCircleLines(wall.pos.x.int32, wall.pos.y.int32, wall.radius * 0.55'f32,
                    Color(r: tint.r, g: tint.g, b: tint.b, a: 120))
    # Damage cue: once chipped, show a shrinking HP bar so the player can read
    # that these obstacles are destructible (and, in boss rooms, re-forming).
    if wall.hp < wall.maxHp:
      let barWidth = wall.radius * 2
      let hpPercent = wall.hp / wall.maxHp
      drawRectangle((wall.pos.x - wall.radius).int32, (wall.pos.y - wall.radius - 8).int32,
                    barWidth.int32, 3, Color(r: 60, g: 20, b: 20, a: 220))
      drawRectangle((wall.pos.x - wall.radius).int32, (wall.pos.y - wall.radius - 8).int32,
                    (barWidth * hpPercent).int32, 3, tint)
    return

  # Check if player has Wall Turrets power-up for different visual style
  let hasTurrets = hasPowerUp(player, puWallTurrets)

  if hasTurrets:
    # Turret skin - metallic gray/silver with gun turret on top
    # Base platform (darker)
    let baseColor = Color(r: 80, g: 80, b: 90, a: 255)
    drawCircle(Vector2(x: wall.pos.x, y: wall.pos.y), wall.radius, baseColor)

    # Turret body on top (lighter, smaller circle)
    let turretColor = Color(r: 120, g: 120, b: 140, a: 255)
    drawCircle(Vector2(x: wall.pos.x, y: wall.pos.y - wall.radius * 0.3), wall.radius * 0.6, turretColor)

    # Gun barrel (small rectangle pointing up/forward)
    let barrelWidth = wall.radius * 0.2
    let barrelHeight = wall.radius * 0.5
    drawRectangle((wall.pos.x - barrelWidth / 2).int32,
                  (wall.pos.y - wall.radius * 0.9).int32,
                  barrelWidth.int32, barrelHeight.int32,
                  Color(r: 60, g: 60, b: 70, a: 255))

    # Metallic highlights/shine
    drawCircleLines(wall.pos.x.int32, wall.pos.y.int32, wall.radius,
                   Color(r: 180, g: 180, b: 200, a: 255))
    drawCircleLines(wall.pos.x.int32, (wall.pos.y - wall.radius * 0.3).int32, wall.radius * 0.6,
                   Color(r: 160, g: 160, b: 180, a: 255))
  else:
    # Normal wall skin - brown/wooden appearance
    let color = Color(r: 139, g: 69, b: 19, a: 255)
    drawCircle(Vector2(x: wall.pos.x, y: wall.pos.y), wall.radius, color)
    drawCircleLines(wall.pos.x.int32, wall.pos.y.int32, wall.radius, Black)

  # Draw HP bar (same for both skins)
  let barWidth = wall.radius * 2
  let barHeight = 4.0
  let hpPercent = wall.hp / wall.maxHp
  drawRectangle((wall.pos.x - wall.radius).int32, (wall.pos.y - wall.radius - 10).int32,
                barWidth.int32, barHeight.int32, Red)
  drawRectangle((wall.pos.x - wall.radius).int32, (wall.pos.y - wall.radius - 10).int32,
                (barWidth * hpPercent).int32, barHeight.int32, Green)

proc takeDamage*(wall: Wall, damage: float32) =
  wall.hp -= damage
  if wall.hp < 0: wall.hp = 0

proc checkEnemyWallCollision*(enemy: Enemy, wall: Wall): bool =
  distance(enemy.pos, wall.pos) < enemy.radius + wall.radius

proc checkPlayerWallCollision*(playerPos: Vector2f, playerRadius: float32, wall: Wall): bool =
  distance(playerPos, wall.pos) < playerRadius + wall.radius

proc isValidWallPlacement*(pos: Vector2f, playerPos: Vector2f, walls: seq[Wall], enemies: seq[Enemy], radius: float32): bool =
  # Check if too close to player
  if distance(pos, playerPos) < radius * 2:
    return false

  # Check overlap with other walls
  for wall in walls:
    if distance(pos, wall.pos) < radius + wall.radius:
      return false

  # Check overlap with enemies
  for enemy in enemies:
    if distance(pos, enemy.pos) < radius + enemy.radius:
      return false

  return true
