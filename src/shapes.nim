## Player Shapes System
## Defines available player shapes and rendering functions

import raylib, math
import draw_prims
import particle_types, localization, cube_skins, cube_render, utils

type
  ShapeType* = enum
    shHexagon,     # Default hexagonal shape
    shTriangle,    # Triangle shape
    shSquare,      # Square shape
    shCircle       # Simple circle shape

  ShapeData* = object
    name*: string
    description*: string
    isUnlocked*: bool

# Global shape database
var shapeDatabase*: array[ShapeType, ShapeData]

proc initializeShapes*() =
  ## Initialize all available shapes with their data
  shapeDatabase[shHexagon] = ShapeData(
    name: t("shape_hexagon"),
    description: t("shape_hexagon_desc"),
    isUnlocked: true
  )

  shapeDatabase[shTriangle] = ShapeData(
    name: t("shape_triangle"),
    description: t("shape_triangle_desc"),
    isUnlocked: true
  )

  shapeDatabase[shSquare] = ShapeData(
    name: t("shape_square"),
    description: t("shape_square_desc"),
    isUnlocked: true
  )

  shapeDatabase[shCircle] = ShapeData(
    name: t("shape_circle"),
    description: t("shape_circle_desc"),
    isUnlocked: true
  )

proc getShapeData*(shapeType: ShapeType): ShapeData =
  ## Get the shape data for a specific shape type
  return shapeDatabase[shapeType]

proc topHatAlpha(v: float32): uint8 = clampByteF(v)  # delegate to utils.clampByteF

proc drawTopHat*(pos: Vector2f, radius: float32, time: float32,
                 alpha: float32 = 1.0'f32,
                 accent: Color = Color(r: 0, g: 230, b: 220, a: 255)) =
  ## The kernel's signature tophat, perched on a shape of the given radius.
  ## Every piece shares the same pivot and rotation so the hat tilts as one
  ## unit, and it stays upright while the shape spins beneath it. Shared by
  ## the lore cinematic, the in-game player (secret cosmetic), and the shop.
  ## `accent` tints the band and outline: the kernel keeps the terminal cyan
  ## default; cosmetic wearers pass their own color.
  let bob = sin(time * 2.0'f32) * radius * 0.05'f32
  let pivot = Vector2(x: pos.x, y: pos.y - radius * 0.74'f32 + bob)
  let tilt = -9.0'f32 + sin(time * 1.6'f32) * 2.5'f32
  let brimW = radius * 1.7'f32
  let brimH = radius * 0.22'f32
  let crownW = radius * 1.05'f32
  let crownH = radius * 1.05'f32
  let bandH = radius * 0.3'f32
  let rim = max(1.0'f32, radius * 0.06'f32)
  let hatColor = Color(r: 16, g: 20, b: 30, a: topHatAlpha(alpha * 245.0'f32))
  let rimColor = Color(r: uint8(accent.r.float32 * 0.87'f32),
                       g: uint8(accent.g.float32 * 0.87'f32),
                       b: uint8(accent.b.float32 * 0.87'f32),
                       a: topHatAlpha(alpha * 190.0'f32))
  let bandColor = Color(r: accent.r, g: accent.g, b: accent.b,
                        a: topHatAlpha(alpha * 235.0'f32))

  # Cyan rim drawn behind each piece doubles as an outline on dark scenes.
  drawRectangle(Rectangle(x: pivot.x, y: pivot.y,
                          width: crownW + rim * 2.0'f32, height: crownH + rim),
                Vector2(x: crownW * 0.5'f32 + rim, y: crownH + brimH + rim),
                tilt, rimColor)
  drawRectangle(Rectangle(x: pivot.x, y: pivot.y,
                          width: brimW + rim * 2.0'f32, height: brimH + rim * 2.0'f32),
                Vector2(x: brimW * 0.5'f32 + rim, y: brimH + rim),
                tilt, rimColor)
  # Crown above the brim, brim resting on the shape.
  drawRectangle(Rectangle(x: pivot.x, y: pivot.y, width: crownW, height: crownH),
                Vector2(x: crownW * 0.5'f32, y: crownH + brimH), tilt, hatColor)
  drawRectangle(Rectangle(x: pivot.x, y: pivot.y, width: brimW, height: brimH),
                Vector2(x: brimW * 0.5'f32, y: brimH), tilt, hatColor)
  # Hat band in terminal cyan.
  drawRectangle(Rectangle(x: pivot.x, y: pivot.y, width: crownW, height: bandH),
                Vector2(x: crownW * 0.5'f32, y: bandH + brimH), tilt, bandColor)

proc drawCheaterHat*(pos: Vector2f, radius: float32, time: float32,
                     alpha: float32 = 1.0'f32) =
  ## White pointy hat, matching the simple gnome-hat silhouette.
  let bob = sin(time * 2.0'f32) * radius * 0.05'f32
  let brimY = pos.y - radius * 0.95'f32 + bob
  let brimW = radius * 1.48'f32
  let brimH = radius * 0.2'f32
  let tip = Vector2(x: pos.x + sin(time * 1.4'f32) * radius * 0.08'f32,
                    y: pos.y - radius * 2.16'f32 + bob)
  let left = Vector2(x: pos.x - brimW * 0.5'f32, y: brimY + brimH * 0.45'f32)
  let right = Vector2(x: pos.x + brimW * 0.5'f32, y: brimY + brimH * 0.45'f32)
  let fill = Color(r: 248, g: 248, b: 255, a: topHatAlpha(alpha * 245.0'f32))
  let shade = Color(r: 202, g: 210, b: 228, a: topHatAlpha(alpha * 220.0'f32))
  let outline = Color(r: 116, g: 128, b: 148, a: topHatAlpha(alpha * 180.0'f32))
  drawTriangle(tip, left, right, fill)
  drawTriangleOutline(tip, left, right, outline)
  drawRectangleRounded(Rectangle(x: pos.x - brimW * 0.5'f32, y: brimY,
                                 width: brimW, height: brimH),
                       0.65'f32, 8, fill)
  drawRectangleRoundedLines(Rectangle(x: pos.x - brimW * 0.5'f32, y: brimY,
                                      width: brimW, height: brimH),
                            0.65'f32, 8, -1.5'f32, outline)
  drawDisc(Vector2(x: tip.x, y: tip.y), max(2.0'f32, radius * 0.11'f32), shade)

proc drawTriangleBothWindings(a, b, c: Vector2, color: Color) =
  drawTriangle(a, b, c, color)
  drawTriangle(a, c, b, color)

proc drawRogueliteClassCosmetic*(pos: Vector2f, radius: float32, time: float32,
                                 kit: int, bodyColor: Color) =
  ## Small, secondary class tell for the chosen roguelite starter kit
  ## (1 = Operator, 2 = Bulwark, 3 = Arcanist): a compact ~0.4r emblem worn on
  ## the lower-right "shoulder", just off the body rim. Deliberately understated
  ## so it never competes with the player or overlaps the head-worn secret hats
  ## (~pos.y - radius) or the wide orbital cube (2.5r).
  let bob = sin(time * 2.0'f32) * radius * 0.04'f32
  let ex  = pos.x + radius * 0.64'f32
  let ey  = pos.y + radius * 0.64'f32 + bob
  let es  = radius * 0.42'f32                                   # emblem half-extent
  case kit
  of 1:
    # OPERATOR: a tiny recon reticle: a small ring, a center dot, and four ticks.
    let green = Color(r: 90, g: 235, b: 170, a: 205)
    drawDisc(Vector2(x: ex, y: ey), es * 0.78'f32, Color(r: 90, g: 235, b: 170, a: 45))
    drawCircleOutline(ex.int32, ey.int32, es * 0.55'f32, green)
    drawDisc(Vector2(x: ex, y: ey), max(1.0'f32, radius * 0.07'f32), green)
    for i in 0 ..< 4:
      let a = i.float32 * (PI * 0.5'f32)
      drawStroke(Vector2(x: ex + cos(a) * es * 0.6'f32, y: ey + sin(a) * es * 0.6'f32),
               Vector2(x: ex + cos(a) * es * 0.92'f32, y: ey + sin(a) * es * 0.92'f32),
               max(1.0'f32, radius * 0.05'f32), green)
  of 2:
    # BULWARK: a tiny steel shield crest with a center seam and a stud.
    let steel  = Color(r: 168, g: 184, b: 208, a: 215)
    let steelHi = Color(r: 214, g: 226, b: 244, a: 230)
    let topL = Vector2(x: ex - es * 0.55'f32, y: ey - es * 0.55'f32)
    let topR = Vector2(x: ex + es * 0.55'f32, y: ey - es * 0.55'f32)
    let tip  = Vector2(x: ex, y: ey + es * 0.7'f32)
    drawTriangleBothWindings(topL, topR, tip, steel)
    drawStroke(topL, topR, max(1.0'f32, radius * 0.06'f32), steelHi)
    drawStroke(Vector2(x: ex, y: ey - es * 0.5'f32), tip,
             max(1.0'f32, radius * 0.05'f32), steelHi)
    drawDisc(Vector2(x: ex, y: ey - es * 0.18'f32), max(1.0'f32, radius * 0.06'f32),
               Color(r: 248, g: 200, b: 110, a: 230))
  of 3:
    # ARCANIST: a tiny arcane rune: a diamond outline with a soft glow and core.
    let line = Color(r: 210, g: 160, b: 255, a: 210)
    drawDisc(Vector2(x: ex, y: ey), es * 0.7'f32, Color(r: 190, g: 120, b: 255, a: 45))
    let up = Vector2(x: ex, y: ey - es * 0.7'f32)
    let rt = Vector2(x: ex + es * 0.55'f32, y: ey)
    let dn = Vector2(x: ex, y: ey + es * 0.7'f32)
    let lf = Vector2(x: ex - es * 0.55'f32, y: ey)
    let w  = max(1.0'f32, radius * 0.05'f32)
    drawStroke(up, rt, w, line); drawStroke(rt, dn, w, line)
    drawStroke(dn, lf, w, line); drawStroke(lf, up, w, line)
    drawDisc(Vector2(x: ex, y: ey), max(1.0'f32, radius * 0.08'f32),
               Color(r: 245, g: 225, b: 255, a: 235))
  else:
    discard

proc drawMiniCube*(center: Vector2, size: float32, time: float32,
                   edgeColor, glowColor: Color,
                   heartColor: Color = Color(r: 0, g: 0, b: 0, a: 0),
                   isD20: bool = false,
                   skin: CubeSkinType = cskDefault,
                   secretStyle: bool = false) =
  ## The desktop cube, pocket-sized: the orbital-cube secret cosmetic on the
  ## player and its shop preview. Drawn by the desktop cube's own renderer
  ## (cube_render.nim) so every skin looks the same here as on the desktop;
  ## the colour arguments are kept for callers, the skin supplies its own.
  let shown = if isD20: cskD20 else: skin
  drawZeroGravityWallpaperCube(center.x, center.y, size, time,
                               time * 0.9'f32, time * 1.4'f32, 0.0'f32, shown,
                               compact = true)

proc drawPlayerShape*(pos: Vector2f, radius: float32, shapeType: ShapeType,
                     baseColor, secondaryColor, coreColor: Color,
                     time, rotation, pulse, glowIntensity: float32) =
  ## Draw the player shape based on selected type
  ## All shapes use the same hitbox (circular) but different visuals

  case shapeType:
  of shHexagon:
    # Circle uses rotation for the hexagonal frame
    # Original circular rendering (same as before)
    # 1. OUTER ENERGY FIELD (background glow)
    let outerGlowRadius = radius + 12
    for i in 0..2:
      let layerRadius = outerGlowRadius + i.float32 * 4.0
      let layerAlpha = uint8((1.0 - i.float32 / 3.0) * glowIntensity * 50)
      drawDisc(Vector2(x: pos.x, y: pos.y), layerRadius,
                withAlpha(baseColor, layerAlpha))

    # CIRCUIT TRACES (inner glow layer)
    let numTraces = 6
    for i in 0..<numTraces:
      let angle = rotation + i.float32 * PI / 3.0
      let innerR = radius * 0.3
      let outerR = radius * 0.9
      let x1 = pos.x + cos(angle) * innerR
      let y1 = pos.y + sin(angle) * innerR
      let x2 = pos.x + cos(angle) * outerR
      let y2 = pos.y + sin(angle) * outerR
      let traceAlpha = uint8(80 + pulse * 60)
      drawStroke(Vector2(x: x1, y: y1), Vector2(x: x2, y: y2), 1.5,
              Color(r: min(secondaryColor.r.int + 60, 255).uint8,
                    g: min(secondaryColor.g.int + 60, 255).uint8,
                    b: min(secondaryColor.b.int + 60, 255).uint8, a: traceAlpha))

    # 3. ROTATING HEXAGONAL FRAME
    let hexRadius = radius * 0.85
    let hexPoints = 6
    for i in 0..<hexPoints:
      let angle = rotation + i.float32 * PI / 3.0 - PI / 2.0
      let nextAngle = rotation + (i + 1).float32 * PI / 3.0 - PI / 2.0
      let x1 = pos.x + cos(angle) * hexRadius
      let y1 = pos.y + sin(angle) * hexRadius
      let x2 = pos.x + cos(nextAngle) * hexRadius
      let y2 = pos.y + sin(nextAngle) * hexRadius
      drawStroke(Vector2(x: x1, y: y1), Vector2(x: x2, y: y2), 2.5, baseColor)
      # Corner nodes
      drawDisc(Vector2(x: x1, y: y1), 2.5, baseColor)

    # 4. MAIN BODY CIRCLE
    drawDisc(Vector2(x: pos.x, y: pos.y), radius * 0.6,
              Color(r: secondaryColor.r div 2, g: secondaryColor.g div 2, b: secondaryColor.b div 2, a: 200))

    # 4b. INNER COUNTER-ROTATING TRIANGLE (unique hexagon sub-element)
    let triInner = radius * 0.45
    let triRot = -rotation * 2.3  # spins opposite & faster
    for i in 0..<3:
      let a0 = triRot + i.float32 * (PI * 2.0 / 3.0)
      let a1 = triRot + (i + 1).float32 * (PI * 2.0 / 3.0)
      drawStroke(Vector2(x: pos.x + cos(a0) * triInner, y: pos.y + sin(a0) * triInner),
               Vector2(x: pos.x + cos(a1) * triInner, y: pos.y + sin(a1) * triInner),
               1.5, Color(r: min(secondaryColor.r.int + 100, 255).uint8,
                          g: min(secondaryColor.g.int + 100, 255).uint8,
                          b: min(secondaryColor.b.int + 100, 255).uint8, a: uint8(120 + pulse * 80)))

    # 5. BRIGHT WHITE CORE
    drawDisc(Vector2(x: pos.x, y: pos.y), radius * 0.35, coreColor)
    # Core highlight
    let highlightX = pos.x - radius * 0.15
    let highlightY = pos.y - radius * 0.15
    drawDisc(Vector2(x: highlightX, y: highlightY), radius * 0.15,
              Color(r: 255, g: 255, b: 255, a: 180))

  of shTriangle:
    # Triangle shape with same hitbox radius (no rotation)
    # 1. OUTER ENERGY FIELD (triangle glow)
    let triRadius = radius * 1.1  # Reduced from 1.3 to make visually smaller
    for layer in 0..2:
      let layerRadius = triRadius + layer.float32 * 5.0
      let layerAlpha = uint8((1.0 - layer.float32 / 3.0) * glowIntensity * 50)
      # Draw 3 vertices of triangle glow
      for i in 0..2:
        let angle = i.float32 * (2.0 * PI / 3.0) - PI / 2.0  # Static, no rotation
        let vx = pos.x + cos(angle) * layerRadius
        let vy = pos.y + sin(angle) * layerRadius
        drawDisc(Vector2(x: vx, y: vy), 8.0,
                  withAlpha(baseColor, layerAlpha))

    # 2. ENERGY LINES between vertices
    let numInnerTraces = 3
    for i in 0..<numInnerTraces:
      let angle1 = i.float32 * (2.0 * PI / 3.0) - PI / 2.0
      let angle2 = ((i + 1) mod 3).float32 * (2.0 * PI / 3.0) - PI / 2.0
      let innerR = radius * 0.4
      let x1 = pos.x + cos(angle1) * innerR
      let y1 = pos.y + sin(angle1) * innerR
      let x2 = pos.x + cos(angle2) * innerR
      let y2 = pos.y + sin(angle2) * innerR
      let traceAlpha = uint8(80 + pulse * 60)
      drawStroke(Vector2(x: x1, y: y1), Vector2(x: x2, y: y2), 2.0,
              Color(r: min(secondaryColor.r.int + 60, 255).uint8,
                    g: min(secondaryColor.g.int + 60, 255).uint8,
                    b: min(secondaryColor.b.int + 60, 255).uint8, a: traceAlpha))

    # 3. MAIN TRIANGLE OUTLINE
    let triPoints = 3
    for i in 0..<triPoints:
      let angle = i.float32 * (2.0 * PI / 3.0) - PI / 2.0
      let nextAngle = ((i + 1) mod 3).float32 * (2.0 * PI / 3.0) - PI / 2.0
      let x1 = pos.x + cos(angle) * triRadius
      let y1 = pos.y + sin(angle) * triRadius
      let x2 = pos.x + cos(nextAngle) * triRadius
      let y2 = pos.y + sin(nextAngle) * triRadius
      drawStroke(Vector2(x: x1, y: y1), Vector2(x: x2, y: y2), 3.0, baseColor)
      # Corner nodes
      drawDisc(Vector2(x: x1, y: y1), 3.5, baseColor)

    # 4. INNER TRIANGLE (filled)
    let v1x = pos.x + cos(-PI / 2.0) * (radius * 0.6)
    let v1y = pos.y + sin(-PI / 2.0) * (radius * 0.6)
    let v2x = pos.x + cos(2.0 * PI / 3.0 - PI / 2.0) * (radius * 0.6)
    let v2y = pos.y + sin(2.0 * PI / 3.0 - PI / 2.0) * (radius * 0.6)
    let v3x = pos.x + cos(4.0 * PI / 3.0 - PI / 2.0) * (radius * 0.6)
    let v3y = pos.y + sin(4.0 * PI / 3.0 - PI / 2.0) * (radius * 0.6)
    drawTriangle(Vector2(x: v1x, y: v1y), Vector2(x: v2x, y: v2y), Vector2(x: v3x, y: v3y),
                Color(r: secondaryColor.r div 2, g: secondaryColor.g div 2, b: secondaryColor.b div 2, a: 200))

    # 5. CORE CIRCLE
    drawDisc(Vector2(x: pos.x, y: pos.y), radius * 0.35, coreColor)
    let highlightX = pos.x - radius * 0.15
    let highlightY = pos.y - radius * 0.15
    drawDisc(Vector2(x: highlightX, y: highlightY), radius * 0.15,
              Color(r: 255, g: 255, b: 255, a: 180))
    # ORBITING DOT unique to triangle (secondary-colored halo around a bright core)
    let orbitAngle = time * 4.5
    let orbitR = radius * 0.55
    let orbitX = pos.x + cos(orbitAngle) * orbitR
    let orbitY = pos.y + sin(orbitAngle) * orbitR
    drawDisc(Vector2(x: orbitX, y: orbitY), radius * 0.16,
               Color(r: secondaryColor.r, g: secondaryColor.g, b: secondaryColor.b,
                     a: uint8(110 + pulse * 60)))
    drawDisc(Vector2(x: orbitX, y: orbitY), radius * 0.10, coreColor)

  of shSquare:
    # Square shape with same hitbox radius (no rotation)
    # 1. OUTER ENERGY FIELD (square glow)
    let squareSize = radius * 1.05  # Reduced from 1.3 to make even smaller
    for layer in 0..2:
      let layerSize = squareSize + layer.float32 * 6.0
      let layerAlpha = uint8((1.0 - layer.float32 / 3.0) * glowIntensity * 50)
      # Draw 4 corners of square glow
      for i in 0..3:
        let angle = i.float32 * PI / 2.0 + PI / 4.0  # Static, no rotation
        let vx = pos.x + cos(angle) * layerSize
        let vy = pos.y + sin(angle) * layerSize
        drawDisc(Vector2(x: vx, y: vy), 8.0,
                  withAlpha(baseColor, layerAlpha))

    # 2. ENERGY LINES connecting corners
    for i in 0..3:
      let angle1 = i.float32 * PI / 2.0 + PI / 4.0
      let angle2 = ((i + 1) mod 4).float32 * PI / 2.0 + PI / 4.0
      let innerR = radius * 0.4
      let x1 = pos.x + cos(angle1) * innerR
      let y1 = pos.y + sin(angle1) * innerR
      let x2 = pos.x + cos(angle2) * innerR
      let y2 = pos.y + sin(angle2) * innerR
      let traceAlpha = uint8(80 + pulse * 60)
      drawStroke(Vector2(x: x1, y: y1), Vector2(x: x2, y: y2), 2.0,
              Color(r: min(secondaryColor.r.int + 60, 255).uint8,
                    g: min(secondaryColor.g.int + 60, 255).uint8,
                    b: min(secondaryColor.b.int + 60, 255).uint8, a: traceAlpha))

    # 3. MAIN SQUARE OUTLINE
    for i in 0..3:
      let angle = i.float32 * PI / 2.0 + PI / 4.0
      let nextAngle = ((i + 1) mod 4).float32 * PI / 2.0 + PI / 4.0
      let x1 = pos.x + cos(angle) * squareSize
      let y1 = pos.y + sin(angle) * squareSize
      let x2 = pos.x + cos(nextAngle) * squareSize
      let y2 = pos.y + sin(nextAngle) * squareSize
      drawStroke(Vector2(x: x1, y: y1), Vector2(x: x2, y: y2), 3.0, baseColor)
      # Corner nodes
      drawDisc(Vector2(x: x1, y: y1), 3.5, baseColor)

    # 4. INNER SQUARE (filled)
    let innerSize = radius * 0.6
    let halfSize = innerSize / sqrt(2.0)
    let cx1 = pos.x + cos(PI / 4.0) * halfSize
    let cy1 = pos.y + sin(PI / 4.0) * halfSize
    let cx2 = pos.x + cos(3.0 * PI / 4.0) * halfSize
    let cy2 = pos.y + sin(3.0 * PI / 4.0) * halfSize
    let cx3 = pos.x + cos(5.0 * PI / 4.0) * halfSize
    let cy3 = pos.y + sin(5.0 * PI / 4.0) * halfSize
    let cx4 = pos.x + cos(7.0 * PI / 4.0) * halfSize
    let cy4 = pos.y + sin(7.0 * PI / 4.0) * halfSize
    drawTriangle(Vector2(x: cx1, y: cy1), Vector2(x: cx2, y: cy2), Vector2(x: pos.x, y: pos.y),
                Color(r: secondaryColor.r div 2, g: secondaryColor.g div 2, b: secondaryColor.b div 2, a: 200))
    drawTriangle(Vector2(x: cx2, y: cy2), Vector2(x: cx3, y: cy3), Vector2(x: pos.x, y: pos.y),
                Color(r: secondaryColor.r div 2, g: secondaryColor.g div 2, b: secondaryColor.b div 2, a: 200))
    drawTriangle(Vector2(x: cx3, y: cy3), Vector2(x: cx4, y: cy4), Vector2(x: pos.x, y: pos.y),
                Color(r: secondaryColor.r div 2, g: secondaryColor.g div 2, b: secondaryColor.b div 2, a: 200))
    drawTriangle(Vector2(x: cx4, y: cy4), Vector2(x: cx1, y: cy1), Vector2(x: pos.x, y: pos.y),
                Color(r: secondaryColor.r div 2, g: secondaryColor.g div 2, b: secondaryColor.b div 2, a: 200))

    # 5. CORE CIRCLE
    drawDisc(Vector2(x: pos.x, y: pos.y), radius * 0.35, coreColor)
    let highlightX = pos.x - radius * 0.15
    let highlightY = pos.y - radius * 0.15
    drawDisc(Vector2(x: highlightX, y: highlightY), radius * 0.15,
              Color(r: 255, g: 255, b: 255, a: 180))
    # SPINNING INNER ARC unique to square
    let arcAngle = time * -3.2
    let arcR = radius * 0.52
    for seg in 0..1:
      let sa = arcAngle + seg.float32 * PI
      drawStroke(Vector2(x: pos.x + cos(sa) * arcR, y: pos.y + sin(sa) * arcR),
               Vector2(x: pos.x + cos(sa + PI * 0.6) * arcR, y: pos.y + sin(sa + PI * 0.6) * arcR),
               2.0, Color(r: min(baseColor.r + 120, 255).uint8,
                          g: min(baseColor.g + 120, 255).uint8,
                          b: min(baseColor.b + 120, 255).uint8, a: uint8(140 + pulse * 80)))

  of shCircle:
    # Pure circle shape - clean and simple (uses rotation for pulsing effect)
    # 1. OUTER ENERGY FIELD (circular glow)
    let outerGlowRadius = radius + 10 + pulse * 3.0  # Pulsing glow
    for i in 0..3:
      let layerRadius = outerGlowRadius + i.float32 * 3.5
      let layerAlpha = uint8((1.0 - i.float32 / 4.0) * glowIntensity * 60)
      drawDisc(Vector2(x: pos.x, y: pos.y), layerRadius,
                withAlpha(baseColor, layerAlpha))

    # 2. ROTATING ENERGY RINGS (orbital layers)
    let numRings = 3
    for ring in 0..<numRings:
      let ringAngleOffset = rotation + ring.float32 * (2.0 * PI / numRings.float32)
      let ringRadius = radius * (0.6 + ring.float32 * 0.15)
      let numDots = 8
      for i in 0..<numDots:
        let angle = ringAngleOffset + i.float32 * (2.0 * PI / numDots.float32)
        let dotX = pos.x + cos(angle) * ringRadius
        let dotY = pos.y + sin(angle) * ringRadius
        let dotAlpha = uint8(100 + pulse * 80)
        let dotSize = 1.5 + pulse * 0.5
        drawDisc(Vector2(x: dotX, y: dotY), dotSize,
                  Color(r: min(baseColor.r + 30, 255), g: min(baseColor.g + 30, 255),
                        b: min(baseColor.b + 30, 255), a: dotAlpha))

    # 3. MAIN OUTER RING
    let mainRingRadius = radius * 0.9
    drawDisc(Vector2(x: pos.x, y: pos.y), mainRingRadius, baseColor)
    drawDisc(Vector2(x: pos.x, y: pos.y), mainRingRadius - 2.5,
              Color(r: baseColor.r div 2, g: baseColor.g div 2, b: baseColor.b div 2, a: 255))

    # 4. INNER BODY CIRCLE (darker fill)
    let bodyRadius = radius * 0.7
    drawDisc(Vector2(x: pos.x, y: pos.y), bodyRadius,
              Color(r: baseColor.r div 2, g: baseColor.g div 2, b: baseColor.b div 2, a: 220))

    # 5. SECONDARY COLOR RING (mid layer)
    let secondaryRing = radius * 0.55
    for i in 0..1:
      let ringR = secondaryRing - i.float32 * 2.0
      drawDisc(Vector2(x: pos.x, y: pos.y), ringR, secondaryColor)

    # 6. BRIGHT CORE with rotating highlight
    drawDisc(Vector2(x: pos.x, y: pos.y), radius * 0.4, coreColor)
    # Rotating core highlight
    let highlightAngle = rotation * 2.0
    let highlightDist = radius * 0.1
    let highlightX2 = pos.x + cos(highlightAngle) * highlightDist
    let highlightY2 = pos.y + sin(highlightAngle) * highlightDist
    drawDisc(Vector2(x: highlightX2, y: highlightY2), radius * 0.2,
              Color(r: 255, g: 255, b: 255, a: uint8(160 + pulse * 50)))
