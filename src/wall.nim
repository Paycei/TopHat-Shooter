import raylib, types, powerup

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
  wall.duration -= dt
  return wall.hp > 0 and wall.duration > 0

proc drawWall*(wall: Wall, player: Player) =
  let alpha = (wall.hp / wall.maxHp * 255).uint8
  
  # Check if player has Wall Turrets power-up for different visual style
  let hasTurrets = hasPowerUp(player, puWallTurrets)
  
  if hasTurrets:
    # Turret skin - metallic gray/silver with gun turret on top
    # Base platform (darker)
    let baseColor = Color(r: 80, g: 80, b: 90, a: alpha)
    drawCircle(Vector2(x: wall.pos.x, y: wall.pos.y), wall.radius, baseColor)
    
    # Turret body on top (lighter, smaller circle)
    let turretColor = Color(r: 120, g: 120, b: 140, a: alpha)
    drawCircle(Vector2(x: wall.pos.x, y: wall.pos.y - wall.radius * 0.3), wall.radius * 0.6, turretColor)
    
    # Gun barrel (small rectangle pointing up/forward)
    let barrelWidth = wall.radius * 0.2
    let barrelHeight = wall.radius * 0.5
    drawRectangle((wall.pos.x - barrelWidth / 2).int32,
                  (wall.pos.y - wall.radius * 0.9).int32,
                  barrelWidth.int32, barrelHeight.int32,
                  Color(r: 60, g: 60, b: 70, a: alpha))
    
    # Metallic highlights/shine
    drawCircleLines(wall.pos.x.int32, wall.pos.y.int32, wall.radius,
                   Color(r: 180, g: 180, b: 200, a: alpha))
    drawCircleLines(wall.pos.x.int32, (wall.pos.y - wall.radius * 0.3).int32, wall.radius * 0.6,
                   Color(r: 160, g: 160, b: 180, a: alpha))
  else:
    # Normal wall skin - brown/wooden appearance
    let color = Color(r: 139, g: 69, b: 19, a: alpha)
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
  
  return true
