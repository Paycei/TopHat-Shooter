## Player Shapes System
## Defines available player shapes and rendering functions

import raylib, types, math, localization

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
    
    # 2. CIRCUIT TRACES (inner glow layer)
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
              Color(r: min(baseColor.r + 50, 255), g: min(baseColor.g + 50, 255), 
                    b: min(baseColor.b + 50, 255), a: traceAlpha))
    
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
              Color(r: baseColor.r div 2, g: baseColor.g div 2, b: baseColor.b div 2, a: 200))
    
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
              Color(r: min(baseColor.r + 50, 255), g: min(baseColor.g + 50, 255), 
                    b: min(baseColor.b + 50, 255), a: traceAlpha))
    
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
                Color(r: baseColor.r div 2, g: baseColor.g div 2, b: baseColor.b div 2, a: 200))
    
    # 5. CORE CIRCLE
    drawCircle(Vector2(x: pos.x, y: pos.y), radius * 0.35, coreColor)
    let highlightX = pos.x - radius * 0.15
    let highlightY = pos.y - radius * 0.15
    drawCircle(Vector2(x: highlightX, y: highlightY), radius * 0.15,
              Color(r: 255, g: 255, b: 255, a: 180))
  
  of shSquare:
    # Square shape with same hitbox radius (no rotation)
    # 1. OUTER ENERGY FIELD (square glow)
    let squareSize = radius * 1.3  # Reduced from 1.5 to make even smaller
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
              Color(r: min(baseColor.r + 50, 255), g: min(baseColor.g + 50, 255), 
                    b: min(baseColor.b + 50, 255), a: traceAlpha))
    
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
    let innerSize = radius * 0.75
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
                Color(r: baseColor.r div 2, g: baseColor.g div 2, b: baseColor.b div 2, a: 200))
    drawTriangle(Vector2(x: cx2, y: cy2), Vector2(x: cx3, y: cy3), Vector2(x: pos.x, y: pos.y),
                Color(r: baseColor.r div 2, g: baseColor.g div 2, b: baseColor.b div 2, a: 200))
    drawTriangle(Vector2(x: cx3, y: cy3), Vector2(x: cx4, y: cy4), Vector2(x: pos.x, y: pos.y),
                Color(r: baseColor.r div 2, g: baseColor.g div 2, b: baseColor.b div 2, a: 200))
    drawTriangle(Vector2(x: cx4, y: cy4), Vector2(x: cx1, y: cy1), Vector2(x: pos.x, y: pos.y),
                Color(r: baseColor.r div 2, g: baseColor.g div 2, b: baseColor.b div 2, a: 200))
    
    # 5. CORE CIRCLE
    drawCircle(Vector2(x: pos.x, y: pos.y), radius * 0.35, coreColor)
    let highlightX = pos.x - radius * 0.15
    let highlightY = pos.y - radius * 0.15
    drawCircle(Vector2(x: highlightX, y: highlightY), radius * 0.15,
              Color(r: 255, g: 255, b: 255, a: 180))
  
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
