## Player Shapes System
## Defines available player shapes and rendering functions

import raylib, math
import types, localization

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

proc getUnlockedShapes*(): seq[ShapeType] =
  ## Return a list of all unlocked shapes
  result = @[]
  for shapeType in ShapeType:
    if shapeDatabase[shapeType].isUnlocked:
      result.add(shapeType)

proc topHatAlpha(v: float32): uint8 =
  uint8(clamp(v, 0.0'f32, 255.0'f32))

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

proc drawMiniCube*(center: Vector2, size: float32, time: float32,
                   edgeColor, glowColor: Color,
                   heartColor: Color = Color(r: 0, g: 0, b: 0, a: 0)) =
  ## Tiny spinning wireframe cube: the desktop cube, pocket-sized. Used by
  ## the orbital-cube secret cosmetic on the player and its shop preview.
  ## When `heartColor` is opaque (the Companion Cube skin) a small Portal-style
  ## heart is painted on the camera-facing side.
  const base = [
    (-1.0'f32, -1.0'f32, -1.0'f32), (1.0'f32, -1.0'f32, -1.0'f32),
    (1.0'f32, 1.0'f32, -1.0'f32), (-1.0'f32, 1.0'f32, -1.0'f32),
    (-1.0'f32, -1.0'f32, 1.0'f32), (1.0'f32, -1.0'f32, 1.0'f32),
    (1.0'f32, 1.0'f32, 1.0'f32), (-1.0'f32, 1.0'f32, 1.0'f32)]
  const edges = [
    (0, 1), (1, 2), (2, 3), (3, 0),
    (4, 5), (5, 6), (6, 7), (7, 4),
    (0, 4), (1, 5), (2, 6), (3, 7)]
  let ax = time * 0.9'f32
  let ay = time * 1.4'f32
  let cax = cos(ax)
  let sax = sin(ax)
  let cay = cos(ay)
  let say = sin(ay)
  var pts: array[8, Vector2]
  for i in 0..<8:
    let (x, y, z) = base[i]
    # Rotate around X, then Y; orthographic projection is fine at this size.
    let y2 = y * cax - z * sax
    let z2 = y * sax + z * cax
    let x3 = x * cay + z2 * say
    pts[i] = Vector2(x: center.x + x3 * size, y: center.y + y2 * size)
  drawCircle(center, size * 1.9'f32,
             Color(r: glowColor.r, g: glowColor.g, b: glowColor.b, a: 36))
  for e in edges:
    drawLine(pts[e[0]], pts[e[1]], 2.6'f32,
             Color(r: glowColor.r, g: glowColor.g, b: glowColor.b, a: 110))
    drawLine(pts[e[0]], pts[e[1]], 1.2'f32, edgeColor)

  # Companion Cube skin: a soft-pink heart on a light disc at the centre of
  # every camera-facing face, drawn in that face's own projected basis so it
  # foreshortens and tumbles with the cube exactly like the full-size desktop
  # cube. A signed-area back-face cull drops the hidden faces and fades each
  # heart to a point at the silhouette, so the visible/hidden hand-off is
  # seamless rather than popping in and out.
  if heartColor.a > 0:
    const faces = [
      [0, 1, 2, 3], [4, 5, 6, 7],   # -Z, +Z
      [0, 3, 7, 4], [1, 2, 6, 5],   # -X, +X
      [0, 1, 5, 4], [3, 2, 6, 7]]   # -Y, +Y
    # Rotate a cube-space direction and return its orthographic screen offset.
    proc rotProj(x, y, z: float32): Vector2 =
      let y2 = y * cax - z * sax
      let z2 = y * sax + z * cax
      let x3 = x * cay + z2 * say
      Vector2(x: x3 * size, y: y2 * size)
    for f in faces:
      # Face normal in cube space is the face centre (cube centred at origin).
      let nx = (base[f[0]][0] + base[f[1]][0] + base[f[2]][0] + base[f[3]][0]) * 0.25'f32
      let ny = (base[f[0]][1] + base[f[1]][1] + base[f[2]][1] + base[f[3]][1]) * 0.25'f32
      let nz = (base[f[0]][2] + base[f[1]][2] + base[f[2]][2] + base[f[3]][2]) * 0.25'f32
      # Canonical "up": side faces point their hearts toward the top ring; the
      # top/bottom faces (normal ±Y) fall back to +Z. right = up × normal keeps
      # a uniform handedness, so a camera-facing face projects to positive area.
      var ux, uy, uz: float32
      if abs(ny) < 0.5'f32:
        ux = 0.0'f32; uy = -1.0'f32; uz = 0.0'f32
      else:
        ux = 0.0'f32; uy = 0.0'f32; uz = 1.0'f32
      let rx = uy * nz - uz * ny
      let ry = uz * nx - ux * nz
      let rz = ux * ny - uy * nx
      let fc = rotProj(nx, ny, nz)
      let fcScreen = Vector2(x: center.x + fc.x, y: center.y + fc.y)
      let sR = rotProj(rx, ry, rz)
      let sU = rotProj(ux, uy, uz)
      # Back-face cull: a camera-facing face has positive signed screen area,
      # which also shrinks to zero at the silhouette (heart fades to a point).
      if sR.x * sU.y - sR.y * sU.x <= 0.0'f32:
        continue
      # Light recessed disc behind the heart (a circle in the face plane).
      let discColor = Color(r: 222, g: 224, b: 229, a: 255)
      var prevDisc = Vector2(x: fcScreen.x + sR.x * 0.55'f32, y: fcScreen.y + sR.y * 0.55'f32)
      for i in 1 .. 12:
        let a = i.float32 / 12.0'f32 * PI * 2.0'f32
        let dx = cos(a) * 0.55'f32
        let dy = sin(a) * 0.55'f32
        let cur = Vector2(x: fcScreen.x + sR.x * dx + sU.x * dy,
                          y: fcScreen.y + sR.y * dx + sU.y * dy)
        drawTriangle(fcScreen, prevDisc, cur, discColor)
        drawTriangle(fcScreen, cur, prevDisc, discColor)
        prevDisc = cur
      # Classic parametric heart: width along the face's right axis, height
      # along its up axis (negated so the point sits toward the bottom edge).
      var prevHeart = Vector2()
      var first = true
      for i in 0 .. 24:
        let t = i.float32 / 24.0'f32 * PI * 2.0'f32
        let hx = 0.34'f32 * (16.0'f32 * pow(sin(t), 3.0'f32)) / 17.0'f32
        let yc = (13.0'f32 * cos(t) - 5.0'f32 * cos(2.0'f32 * t) -
                  2.0'f32 * cos(3.0'f32 * t) - cos(4.0'f32 * t)) / 17.0'f32
        let hy = (-yc - 0.15'f32) * 0.34'f32
        let cur = Vector2(x: fcScreen.x + sR.x * hx - sU.x * hy,
                          y: fcScreen.y + sR.y * hx - sU.y * hy)
        if not first:
          drawTriangle(fcScreen, prevHeart, cur, heartColor)
          drawTriangle(fcScreen, cur, prevHeart, heartColor)
        prevHeart = cur
        first = false

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
      drawCircle(Vector2(x: pos.x, y: pos.y), layerRadius,
                Color(r: baseColor.r, g: baseColor.g, b: baseColor.b, a: layerAlpha))

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
      drawLine(Vector2(x: x1, y: y1), Vector2(x: x2, y: y2), 1.5,
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
      drawLine(Vector2(x: x1, y: y1), Vector2(x: x2, y: y2), 2.5, baseColor)
      # Corner nodes
      drawCircle(Vector2(x: x1, y: y1), 2.5, baseColor)

    # 4. MAIN BODY CIRCLE
    drawCircle(Vector2(x: pos.x, y: pos.y), radius * 0.6,
              Color(r: secondaryColor.r div 2, g: secondaryColor.g div 2, b: secondaryColor.b div 2, a: 200))

    # 4b. INNER COUNTER-ROTATING TRIANGLE (unique hexagon sub-element)
    let triInner = radius * 0.45
    let triRot = -rotation * 2.3  # spins opposite & faster
    for i in 0..<3:
      let a0 = triRot + i.float32 * (PI * 2.0 / 3.0)
      let a1 = triRot + (i + 1).float32 * (PI * 2.0 / 3.0)
      drawLine(Vector2(x: pos.x + cos(a0) * triInner, y: pos.y + sin(a0) * triInner),
               Vector2(x: pos.x + cos(a1) * triInner, y: pos.y + sin(a1) * triInner),
               1.5, Color(r: min(secondaryColor.r.int + 100, 255).uint8,
                          g: min(secondaryColor.g.int + 100, 255).uint8,
                          b: min(secondaryColor.b.int + 100, 255).uint8, a: uint8(120 + pulse * 80)))

    # 5. BRIGHT WHITE CORE
    drawCircle(Vector2(x: pos.x, y: pos.y), radius * 0.35, coreColor)
    # Core highlight
    let highlightX = pos.x - radius * 0.15
    let highlightY = pos.y - radius * 0.15
    drawCircle(Vector2(x: highlightX, y: highlightY), radius * 0.15,
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
        drawCircle(Vector2(x: vx, y: vy), 8.0,
                  Color(r: baseColor.r, g: baseColor.g, b: baseColor.b, a: layerAlpha))

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
      drawLine(Vector2(x: x1, y: y1), Vector2(x: x2, y: y2), 2.0,
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
      drawLine(Vector2(x: x1, y: y1), Vector2(x: x2, y: y2), 3.0, baseColor)
      # Corner nodes
      drawCircle(Vector2(x: x1, y: y1), 3.5, baseColor)

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
    drawCircle(Vector2(x: pos.x, y: pos.y), radius * 0.35, coreColor)
    let highlightX = pos.x - radius * 0.15
    let highlightY = pos.y - radius * 0.15
    drawCircle(Vector2(x: highlightX, y: highlightY), radius * 0.15,
              Color(r: 255, g: 255, b: 255, a: 180))
    # ORBITING DOT unique to triangle (secondary-colored halo around a bright core)
    let orbitAngle = time * 4.5
    let orbitR = radius * 0.55
    let orbitX = pos.x + cos(orbitAngle) * orbitR
    let orbitY = pos.y + sin(orbitAngle) * orbitR
    drawCircle(Vector2(x: orbitX, y: orbitY), radius * 0.16,
               Color(r: secondaryColor.r, g: secondaryColor.g, b: secondaryColor.b,
                     a: uint8(110 + pulse * 60)))
    drawCircle(Vector2(x: orbitX, y: orbitY), radius * 0.10, coreColor)

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
        drawCircle(Vector2(x: vx, y: vy), 8.0,
                  Color(r: baseColor.r, g: baseColor.g, b: baseColor.b, a: layerAlpha))

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
      drawLine(Vector2(x: x1, y: y1), Vector2(x: x2, y: y2), 2.0,
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
      drawLine(Vector2(x: x1, y: y1), Vector2(x: x2, y: y2), 3.0, baseColor)
      # Corner nodes
      drawCircle(Vector2(x: x1, y: y1), 3.5, baseColor)

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
    drawCircle(Vector2(x: pos.x, y: pos.y), radius * 0.35, coreColor)
    let highlightX = pos.x - radius * 0.15
    let highlightY = pos.y - radius * 0.15
    drawCircle(Vector2(x: highlightX, y: highlightY), radius * 0.15,
              Color(r: 255, g: 255, b: 255, a: 180))
    # SPINNING INNER ARC unique to square
    let arcAngle = time * -3.2
    let arcR = radius * 0.52
    for seg in 0..1:
      let sa = arcAngle + seg.float32 * PI
      drawLine(Vector2(x: pos.x + cos(sa) * arcR, y: pos.y + sin(sa) * arcR),
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
      drawCircle(Vector2(x: pos.x, y: pos.y), layerRadius,
                Color(r: baseColor.r, g: baseColor.g, b: baseColor.b, a: layerAlpha))

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
        drawCircle(Vector2(x: dotX, y: dotY), dotSize,
                  Color(r: min(baseColor.r + 30, 255), g: min(baseColor.g + 30, 255),
                        b: min(baseColor.b + 30, 255), a: dotAlpha))

    # 3. MAIN OUTER RING
    let mainRingRadius = radius * 0.9
    drawCircle(Vector2(x: pos.x, y: pos.y), mainRingRadius, baseColor)
    drawCircle(Vector2(x: pos.x, y: pos.y), mainRingRadius - 2.5,
              Color(r: baseColor.r div 2, g: baseColor.g div 2, b: baseColor.b div 2, a: 255))

    # 4. INNER BODY CIRCLE (darker fill)
    let bodyRadius = radius * 0.7
    drawCircle(Vector2(x: pos.x, y: pos.y), bodyRadius,
              Color(r: baseColor.r div 2, g: baseColor.g div 2, b: baseColor.b div 2, a: 220))

    # 5. SECONDARY COLOR RING (mid layer)
    let secondaryRing = radius * 0.55
    for i in 0..1:
      let ringR = secondaryRing - i.float32 * 2.0
      drawCircle(Vector2(x: pos.x, y: pos.y), ringR, secondaryColor)

    # 6. BRIGHT CORE with rotating highlight
    drawCircle(Vector2(x: pos.x, y: pos.y), radius * 0.4, coreColor)
    # Rotating core highlight
    let highlightAngle = rotation * 2.0
    let highlightDist = radius * 0.1
    let highlightX2 = pos.x + cos(highlightAngle) * highlightDist
    let highlightY2 = pos.y + sin(highlightAngle) * highlightDist
    drawCircle(Vector2(x: highlightX2, y: highlightY2), radius * 0.2,
              Color(r: 255, g: 255, b: 255, a: uint8(160 + pulse * 50)))
