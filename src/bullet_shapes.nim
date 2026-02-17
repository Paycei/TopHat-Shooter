## Bullet Shapes System
## Cosmetic shapes for player bullets (circle, triangle, diamond, square, star, arrow)

import raylib, types, math, localization

type
  BulletShapeType* = enum
    bshCircle,    # Default – plain circle
    bshTriangle,  # Three-pointed
    bshDiamond,   # Four-pointed rotated square
    bshSquare,    # Axis-aligned square
    bshStar,      # Six-pointed star
    bshArrow,     # Arrow pointing in direction of travel

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
  bulletShapeDatabase[bshStar] = BulletShapeData(
    name: t("bshape_star"), description: t("bshape_star_desc"), isUnlocked: true)
  bulletShapeDatabase[bshArrow] = BulletShapeData(
    name: t("bshape_arrow"), description: t("bshape_arrow_desc"), isUnlocked: true)

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
  ## travelAngle  = arctan2(vel.y, vel.x) – only used by bshArrow.

  case shape

  of bshCircle:
    # Glow ring
    drawCircle(Vector2(x: pos.x, y: pos.y), radius + 3,
               Color(r: glowColor.r, g: glowColor.g, b: glowColor.b, a: 60))
    drawCircle(Vector2(x: pos.x, y: pos.y), radius, color)

  of bshTriangle:
    # Equilateral triangle, tip pointing in travel direction
    let rot = travelAngle - PI / 2.0  # tip up by default, rotated to face travel
    for i in 0..<3:
      let a1 = rot + i.float32 * (2.0 * PI / 3.0)
      let a2 = rot + (i + 1).float32 * (2.0 * PI / 3.0)
      drawLine(
        Vector2(x: pos.x + cos(a1) * radius, y: pos.y + sin(a1) * radius),
        Vector2(x: pos.x + cos(a2) * radius, y: pos.y + sin(a2) * radius),
        2, color)
    # Filled centre
    let v1 = Vector2(x: pos.x + cos(rot)                   * radius * 0.9,
                     y: pos.y + sin(rot)                   * radius * 0.9)
    let v2 = Vector2(x: pos.x + cos(rot + 2.094) * radius * 0.9,
                     y: pos.y + sin(rot + 2.094) * radius * 0.9)
    let v3 = Vector2(x: pos.x + cos(rot + 4.189) * radius * 0.9,
                     y: pos.y + sin(rot + 4.189) * radius * 0.9)
    drawTriangle(v1, v2, v3,
                 Color(r: color.r, g: color.g, b: color.b, a: 180))
    # Glow
    drawCircle(Vector2(x: pos.x, y: pos.y), radius + 2,
               Color(r: glowColor.r, g: glowColor.g, b: glowColor.b, a: 40))

  of bshDiamond:
    # Four-pointed diamond (square rotated 45°)
    let r = radius * 1.1
    let top    = Vector2(x: pos.x,     y: pos.y - r)
    let right  = Vector2(x: pos.x + r, y: pos.y)
    let bottom = Vector2(x: pos.x,     y: pos.y + r)
    let left   = Vector2(x: pos.x - r, y: pos.y)
    drawTriangle(top, right, bottom,
                 Color(r: color.r, g: color.g, b: color.b, a: 200))
    drawTriangle(top, bottom, left,
                 Color(r: color.r, g: color.g, b: color.b, a: 200))
    # Outline
    drawLine(top, right, 1.5, color)
    drawLine(right, bottom, 1.5, color)
    drawLine(bottom, left, 1.5, color)
    drawLine(left, top, 1.5, color)
    # Highlight
    drawLine(top, right, 1, Color(r: 255, g: 255, b: 255, a: 80))
    drawCircle(Vector2(x: pos.x, y: pos.y), radius + 2,
               Color(r: glowColor.r, g: glowColor.g, b: glowColor.b, a: 50))

  of bshSquare:
    let h = radius * 0.9  # half-side
    let tl = Vector2(x: pos.x - h, y: pos.y - h)
    let tr = Vector2(x: pos.x + h, y: pos.y - h)
    let bl = Vector2(x: pos.x - h, y: pos.y + h)
    let br = Vector2(x: pos.x + h, y: pos.y + h)
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
    # Six-pointed star = two overlapping equilateral triangles
    let r1 = radius * 1.05
    let r2 = radius * 0.5   # inner radius of the star points
    for tri in 0..1:
      let baseRot = tri.float32 * PI / 3.0   # 0° and 60°
      let v1 = Vector2(x: pos.x + cos(baseRot)         * r1,
                       y: pos.y + sin(baseRot)         * r1)
      let v2 = Vector2(x: pos.x + cos(baseRot + 2.094) * r1,
                       y: pos.y + sin(baseRot + 2.094) * r1)
      let v3 = Vector2(x: pos.x + cos(baseRot + 4.189) * r1,
                       y: pos.y + sin(baseRot + 4.189) * r1)
      drawTriangle(v1, v2, v3,
                   Color(r: color.r, g: color.g, b: color.b, a: 200))
    # Bright core dot
    drawCircle(Vector2(x: pos.x, y: pos.y), r2 * 0.6, color)
    drawCircle(Vector2(x: pos.x, y: pos.y), radius + 3,
               Color(r: glowColor.r, g: glowColor.g, b: glowColor.b, a: 55))

  of bshArrow:
    # Filled arrowhead pointing in direction of travel
    let rot = travelAngle
    let tipDist  = radius * 1.3
    let wingDist = radius * 0.9
    let wingSpread = radius * 0.7
    let tailLen  = radius * 0.5

    let tip   = Vector2(x: pos.x + cos(rot) * tipDist,
                        y: pos.y + sin(rot) * tipDist)
    let wLeft = Vector2(x: pos.x + cos(rot + PI * 0.75) * wingDist + cos(rot + PI / 2) * wingSpread,
                        y: pos.y + sin(rot + PI * 0.75) * wingDist + sin(rot + PI / 2) * wingSpread)
    let wRight= Vector2(x: pos.x + cos(rot - PI * 0.75) * wingDist + cos(rot - PI / 2) * wingSpread,
                        y: pos.y + sin(rot - PI * 0.75) * wingDist + sin(rot - PI / 2) * wingSpread)
    let tail  = Vector2(x: pos.x - cos(rot) * tailLen,
                        y: pos.y - sin(rot) * tailLen)

    drawTriangle(tip, wLeft, tail,
                 Color(r: color.r, g: color.g, b: color.b, a: 220))
    drawTriangle(tip, tail, wRight,
                 Color(r: color.r, g: color.g, b: color.b, a: 220))
    # Bright outline
    drawLine(tip, wLeft, 1.5, color)
    drawLine(tip, wRight, 1.5, color)
    drawLine(wLeft, tail, 1, color)
    drawLine(wRight, tail, 1, color)
    drawCircle(Vector2(x: pos.x, y: pos.y), radius + 2,
               Color(r: glowColor.r, g: glowColor.g, b: glowColor.b, a: 40))
