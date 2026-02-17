## Bullet Shapes System
## Cosmetic shapes for player bullets

import raylib, types, math, localization

type
  BulletShapeType* = enum
    bshCircle,    # Default – plain circle
    bshTriangle,  # Three-pointed
    bshDiamond,   # Four-pointed rotated square
    bshSquare,    # Axis-aligned square
    bshPentagon,  # Five-pointed polygon
    bshStar,      # Six-pointed star

  BulletShapeData* = object
    name*: string
    description*: string
    isUnlocked*: bool

var bulletShapeDatabase*: array[BulletShapeType, BulletShapeData]

proc initializeBulletShapes*() =
  bulletShapeDatabase[bshCircle] = BulletShapeData(
    name: t("bshape_circle"), description: t("bshape_circle_desc"), isUnlocked: true)
  bulletShapeDatabase[bshTriangle] = BulletShapeData(
    name: t("bshape_triangle"), description: t("bshape_triangle_desc"), isUnlocked: true)
  bulletShapeDatabase[bshDiamond] = BulletShapeData(
    name: t("bshape_diamond"), description: t("bshape_diamond_desc"), isUnlocked: true)
  bulletShapeDatabase[bshSquare] = BulletShapeData(
    name: t("bshape_square"), description: t("bshape_square_desc"), isUnlocked: true)
  bulletShapeDatabase[bshPentagon] = BulletShapeData(
    name: t("bshape_pentagon"), description: t("bshape_pentagon_desc"), isUnlocked: true)
  bulletShapeDatabase[bshStar] = BulletShapeData(
    name: t("bshape_star"), description: t("bshape_star_desc"), isUnlocked: true)

proc getBulletShapeData*(s: BulletShapeType): BulletShapeData = bulletShapeDatabase[s]
proc isBulletShapeUnlocked*(s: BulletShapeType): bool = bulletShapeDatabase[s].isUnlocked

proc getUnlockedBulletShapes*(): seq[BulletShapeType] =
  for s in BulletShapeType:
    if bulletShapeDatabase[s].isUnlocked:
      result.add(s)

# Drawing

proc drawPlayerBulletShape*(pos: Vector2f, radius: float32,
                             shape: BulletShapeType, travelAngle: float32,
                             color, glowColor: Color) =
  ## Draw one player bullet with the chosen cosmetic shape.

  case shape

  of bshCircle:
    # Glow ring
    drawCircle(Vector2(x: pos.x, y: pos.y), radius + 3,
               Color(r: glowColor.r, g: glowColor.g, b: glowColor.b, a: 60))
    drawCircle(Vector2(x: pos.x, y: pos.y), radius, color)

  of bshTriangle:
    # Equilateral triangle, tip pointing in travel direction.
    # travelAngle points right (0) = tip at right side of bullet.
    # drawNgon-style: first vertex is placed at `rot`, so rot = travelAngle.
    let rot = travelAngle
    let cx = pos.x; let cy = pos.y; let r = radius
    # Filled body using fan from center
    for i in 0..<3:
      let a0 = rot + i.float32 * (2.0 * PI / 3.0)
      let a1 = rot + (i + 1).float32 * (2.0 * PI / 3.0)
      drawTriangle(
        Vector2(x: cx, y: cy),
        Vector2(x: cx + cos(a0) * r, y: cy + sin(a0) * r),
        Vector2(x: cx + cos(a1) * r, y: cy + sin(a1) * r),
        Color(r: color.r, g: color.g, b: color.b, a: 200))
    # Outline
    for i in 0..<3:
      let a0 = rot + i.float32 * (2.0 * PI / 3.0)
      let a1 = rot + (i + 1).float32 * (2.0 * PI / 3.0)
      drawLine(
        Vector2(x: cx + cos(a0) * r, y: cy + sin(a0) * r),
        Vector2(x: cx + cos(a1) * r, y: cy + sin(a1) * r),
        1.5, color)
    # Glow
    drawCircle(Vector2(x: pos.x, y: pos.y), radius + 2,
               Color(r: glowColor.r, g: glowColor.g, b: glowColor.b, a: 40))

  of bshPentagon:
    # Regular pentagon, one vertex tip pointing in travel direction
    let cx = pos.x; let cy = pos.y; let r = radius * 1.15
    let rot = travelAngle
    # Filled via fan from center
    for i in 0..<5:
      let a0 = rot + i.float32 * (2.0 * PI / 5.0)
      let a1 = rot + (i + 1).float32 * (2.0 * PI / 5.0)
      drawTriangle(
        Vector2(x: cx, y: cy),
        Vector2(x: cx + cos(a0) * r, y: cy + sin(a0) * r),
        Vector2(x: cx + cos(a1) * r, y: cy + sin(a1) * r),
        Color(r: color.r, g: color.g, b: color.b, a: 210))
    # Outline
    for i in 0..<5:
      let a0 = rot + i.float32 * (2.0 * PI / 5.0)
      let a1 = rot + (i + 1).float32 * (2.0 * PI / 5.0)
      drawLine(
        Vector2(x: cx + cos(a0) * r, y: cy + sin(a0) * r),
        Vector2(x: cx + cos(a1) * r, y: cy + sin(a1) * r),
        1.5, color)
    drawCircle(Vector2(x: cx, y: cy), radius + 2,
               Color(r: glowColor.r, g: glowColor.g, b: glowColor.b, a: 45))

  of bshDiamond:
    # Four-pointed diamond – tip points in direction of travel
    let r = radius * 1.1
    let rot = travelAngle  # tip of diamond faces travel direction
    let tip    = Vector2(x: pos.x + cos(rot)             * r, y: pos.y + sin(rot)             * r)
    let right  = Vector2(x: pos.x + cos(rot + PI / 2.0)  * r, y: pos.y + sin(rot + PI / 2.0)  * r)
    let tail   = Vector2(x: pos.x + cos(rot + PI)        * r, y: pos.y + sin(rot + PI)        * r)
    let left   = Vector2(x: pos.x + cos(rot - PI / 2.0)  * r, y: pos.y + sin(rot - PI / 2.0)  * r)
    drawTriangle(tip, right, tail,
                 Color(r: color.r, g: color.g, b: color.b, a: 200))
    drawTriangle(tip, tail, left,
                 Color(r: color.r, g: color.g, b: color.b, a: 200))
    # Outline
    drawLine(tip, right, 1.5, color)
    drawLine(right, tail, 1.5, color)
    drawLine(tail, left, 1.5, color)
    drawLine(left, tip, 1.5, color)
    # Highlight
    drawLine(tip, right, 1, Color(r: 255, g: 255, b: 255, a: 80))
    drawCircle(Vector2(x: pos.x, y: pos.y), radius + 2,
               Color(r: glowColor.r, g: glowColor.g, b: glowColor.b, a: 50))

  of bshSquare:
    # Square rotated so one corner points in the direction of travel
    let h = radius * 0.9
    let rot = travelAngle + PI / 4.0  # rotate 45° so a corner leads
    let tl = Vector2(x: pos.x + cos(rot)               * h * 1.414,
                     y: pos.y + sin(rot)               * h * 1.414)
    let tr = Vector2(x: pos.x + cos(rot + PI / 2.0)    * h * 1.414,
                     y: pos.y + sin(rot + PI / 2.0)    * h * 1.414)
    let br = Vector2(x: pos.x + cos(rot + PI)           * h * 1.414,
                     y: pos.y + sin(rot + PI)           * h * 1.414)
    let bl = Vector2(x: pos.x + cos(rot + 3.0 * PI / 2.0) * h * 1.414,
                     y: pos.y + sin(rot + 3.0 * PI / 2.0) * h * 1.414)
    # Fill via two triangles
    drawTriangle(tl, tr, br,
                 Color(r: color.r, g: color.g, b: color.b, a: 200))
    drawTriangle(tl, br, bl,
                 Color(r: color.r, g: color.g, b: color.b, a: 200))
    # Outline
    drawLine(tl, tr, 1.5, color)
    drawLine(tr, br, 1.5, color)
    drawLine(br, bl, 1.5, color)
    drawLine(bl, tl, 1.5, color)
    drawCircle(Vector2(x: pos.x, y: pos.y), radius + 2,
               Color(r: glowColor.r, g: glowColor.g, b: glowColor.b, a: 45))

  of bshStar:
    # Six-pointed star = two overlapping equilateral triangles (same as boss star shape).
    # One triangle tip faces the travel direction, the other is 60° offset.
    let cx = pos.x; let cy = pos.y; let r = radius * 1.2
    let rot1 = travelAngle                 # first triangle tip points forward
    let rot2 = travelAngle + PI / 3.0     # second triangle 60° offset
    # Draw both triangles using fan-from-center (avoids winding issues)
    for baseRot in [rot1, rot2]:
      for i in 0..<3:
        let a0 = baseRot + i.float32 * (2.0 * PI / 3.0)
        let a1 = baseRot + (i + 1).float32 * (2.0 * PI / 3.0)
        drawTriangle(
          Vector2(x: cx, y: cy),
          Vector2(x: cx + cos(a0) * r, y: cy + sin(a0) * r),
          Vector2(x: cx + cos(a1) * r, y: cy + sin(a1) * r),
          Color(r: color.r, g: color.g, b: color.b, a: 200))
    # Interior hexagon – the overlap region of the two triangles.
    # In a Star of David the inner hexagon vertices sit at r * (1/sqrt(3)) ≈ r * 0.577
    # rotated 30° from the first triangle's base rotation.
    let rHex = r * 0.577
    let hexRot = rot1 + PI / 6.0  # 30° offset aligns with hexagon vertices
    for i in 0..<6:
      let a0 = hexRot + i.float32 * (PI / 3.0)
      let a1 = hexRot + (i + 1).float32 * (PI / 3.0)
      drawTriangle(
        Vector2(x: cx, y: cy),
        Vector2(x: cx + cos(a0) * rHex, y: cy + sin(a0) * rHex),
        Vector2(x: cx + cos(a1) * rHex, y: cy + sin(a1) * rHex),
        Color(r: 255, g: 255, b: 255, a: 120))
    # Outline rings
    for baseRot in [rot1, rot2]:
      for i in 0..<3:
        let a0 = baseRot + i.float32 * (2.0 * PI / 3.0)
        let a1 = baseRot + (i + 1).float32 * (2.0 * PI / 3.0)
        drawLine(
          Vector2(x: cx + cos(a0) * (r + 1), y: cy + sin(a0) * (r + 1)),
          Vector2(x: cx + cos(a1) * (r + 1), y: cy + sin(a1) * (r + 1)),
          1.5, color)
    # Bright core dot
    drawCircle(Vector2(x: pos.x, y: pos.y), radius * 0.28, color)
    drawCircle(Vector2(x: pos.x, y: pos.y), radius + 4,
               Color(r: glowColor.r, g: glowColor.g, b: glowColor.b, a: 55))
