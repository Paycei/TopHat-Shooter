import raylib, types, math

proc newWall*(x, y: float32): Wall =
  result = Wall(
    pos: newVector2f(x, y),
    radius: 25,
    hp: 10,
    maxHp: 10,
    duration: 30.0
  )

proc updateWall*(wall: Wall, dt: float32): bool =
  wall.duration -= dt
  return wall.hp > 0 and wall.duration > 0

proc drawWall*(wall: Wall) =
  let alpha = (wall.hp / wall.maxHp * 255).uint8
  let color = Color(r: 139, g: 69, b: 19, a: alpha)
  drawCircle(Vector2(x: wall.pos.x, y: wall.pos.y), wall.radius, color)
  drawCircleLines(wall.pos.x.int32, wall.pos.y.int32, wall.radius, Black)
  
  # Draw HP bar
  let barWidth = wall.radius * 2
  let barHeight = 4.0
  let hpPercent = wall.hp / wall.maxHp
  drawRectangle((wall.pos.x - wall.radius).int32, (wall.pos.y - wall.radius - 10).int32, 
                barWidth.int32, barHeight.int32, Red)
  drawRectangle((wall.pos.x - wall.radius).int32, (wall.pos.y - wall.radius - 10).int32, 
                (barWidth * hpPercent).int32, barHeight.int32, Green)

proc takeDamage*(wall: Wall, damage: float32) =
  wall.hp -= damage

proc isValidWallPlacement*(pos: Vector2f, playerPos: Vector2f, walls: seq[Wall], enemies: seq[Enemy], radius: float32): bool =
  # Check if too close to player
  if distance(pos, playerPos) < radius * 3:
    return false
  
  # Check overlap with other walls
  for wall in walls:
    if distance(pos, wall.pos) < radius + wall.radius:
      return false
  
  # Basic check: don't place if it completely surrounds player
  # (simplified - just check if too many walls around player)
  var wallsNearPlayer = 0
  for wall in walls:
    if distance(wall.pos, playerPos) < 100:
      wallsNearPlayer += 1
  
  if wallsNearPlayer >= 3:
    return false
  
  return true