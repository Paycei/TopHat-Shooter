## Icon Drawing System - Modern OS Theme with detail
## All icons drawn programmatically using shapes with depth and polish

import raylib, rlgl, math
import ../types

type
  CurrencyIconType* = enum
    ciNone,
    ciCredits,
    ciDataShards,
    ciOverheatCore,
    ciSingularityCore,
    ciHeat

proc drawCurrencyIcon*(cx, cy, size: int32, iconType: CurrencyIconType,
                       alpha: uint8 = 255) =
  ## Draw compact currency/status icons for HUDs and shops.
  if iconType == ciNone:
    return

  let radius = max(5.0'f32, size.float32 * 0.42'f32)
  let shadow = Color(r: 0, g: 0, b: 0, a: uint8(min(150, alpha.int)))

  case iconType
  of ciCredits:
    let outer = Color(r: 255, g: 215, b: 0, a: alpha)
    let inner = Color(r: 205, g: 160, b: 0, a: alpha)
    drawCircle(Vector2(x: (cx + 1).float32, y: (cy + 2).float32), radius, shadow)
    drawCircle(Vector2(x: cx.float32, y: cy.float32), radius, outer)
    drawCircle(Vector2(x: cx.float32, y: cy.float32), radius * 0.72'f32, inner)
    drawCircleLines(cx, cy, radius, Color(r: 255, g: 242, b: 130, a: alpha))
    drawText("$", cx - size div 7, cy - size div 3, max(8'i32, size div 2),
             Color(r: 55, g: 42, b: 0, a: alpha))
  of ciDataShards:
    let edge = Color(r: 255, g: 215, b: 0, a: alpha)
    let fill = Color(r: 70, g: 215, b: 255, a: alpha)
    let glow = Color(r: 70, g: 215, b: 255, a: uint8(alpha.int div 3))
    let top = Vector2(x: cx.float32, y: cy.float32 - radius)
    let left = Vector2(x: cx.float32 - radius * 0.82'f32, y: cy.float32 + radius * 0.72'f32)
    let right = Vector2(x: cx.float32 + radius * 0.82'f32, y: cy.float32 + radius * 0.72'f32)
    drawCircle(Vector2(x: cx.float32, y: cy.float32), radius * 1.05'f32, glow)
    drawTriangle(top, left, right, fill)
    drawTriangleLines(top, left, right, edge)
    drawLine(cx, cy - (radius * 0.72'f32).int32, cx, cy + (radius * 0.45'f32).int32,
             Color(r: 220, g: 255, b: 255, a: alpha))
    drawCircle(Vector2(x: (cx - 2).float32, y: (cy - 3).float32), max(1.5'f32, radius * 0.16'f32),
               Color(r: 255, g: 255, b: 255, a: uint8(min(220, alpha.int))))
  of ciOverheatCore:
    let core = Color(r: 255, g: 95, b: 42, a: alpha)
    let hot = Color(r: 255, g: 214, b: 78, a: alpha)
    drawCircle(Vector2(x: (cx + 1).float32, y: (cy + 2).float32), radius, shadow)
    drawCircle(Vector2(x: cx.float32, y: cy.float32), radius, core)
    drawCircle(Vector2(x: cx.float32, y: cy.float32), radius * 0.52'f32, hot)
    drawCircleLines(cx, cy, radius * 1.16'f32, Color(r: 255, g: 130, b: 80, a: uint8(alpha.int div 2)))
    drawTriangle(
      Vector2(x: cx.float32, y: cy.float32 - radius * 0.98'f32),
      Vector2(x: cx.float32 - radius * 0.34'f32, y: cy.float32 - radius * 0.05'f32),
      Vector2(x: cx.float32 + radius * 0.32'f32, y: cy.float32 - radius * 0.08'f32),
      Color(r: 255, g: 245, b: 150, a: uint8(min(230, alpha.int))))
  of ciSingularityCore:
    let outer = Color(r: 170, g: 110, b: 255, a: alpha)
    let inner = Color(r: 18, g: 8, b: 34, a: alpha)
    drawCircle(Vector2(x: (cx + 1).float32, y: (cy + 2).float32), radius, shadow)
    drawCircle(Vector2(x: cx.float32, y: cy.float32), radius, outer)
    drawCircle(Vector2(x: cx.float32, y: cy.float32), radius * 0.64'f32, inner)
    for i in 0..2:
      let r = radius * (0.58'f32 + i.float32 * 0.26'f32)
      drawCircleLines(cx, cy, r, Color(r: 190, g: 150, b: 255, a: uint8(max(45, alpha.int - i * 62))))
    drawLine(cx - (radius * 0.75'f32).int32, cy, cx + (radius * 0.75'f32).int32, cy,
             Color(r: 240, g: 230, b: 255, a: uint8(min(210, alpha.int))))
  of ciHeat:
    let heat = Color(r: 255, g: 120, b: 60, a: alpha)
    let bright = Color(r: 255, g: 222, b: 86, a: alpha)
    drawCircle(Vector2(x: cx.float32, y: cy.float32 + radius * 0.28'f32), radius * 0.58'f32, shadow)
    drawTriangle(
      Vector2(x: cx.float32, y: cy.float32 - radius),
      Vector2(x: cx.float32 - radius * 0.68'f32, y: cy.float32 + radius * 0.68'f32),
      Vector2(x: cx.float32 + radius * 0.68'f32, y: cy.float32 + radius * 0.68'f32),
      heat)
    drawCircle(Vector2(x: cx.float32, y: cy.float32 + radius * 0.28'f32), radius * 0.68'f32, heat)
    drawTriangle(
      Vector2(x: cx.float32, y: cy.float32 - radius * 0.42'f32),
      Vector2(x: cx.float32 - radius * 0.28'f32, y: cy.float32 + radius * 0.55'f32),
      Vector2(x: cx.float32 + radius * 0.26'f32, y: cy.float32 + radius * 0.55'f32),
      bright)
  of ciNone:
    discard

proc drawPowerUpIcon*(x, y, size: int32, powerType: PowerUpType, color: Color) =
  ## Draw power-up icons using geometric shapes with enhanced detail
  if size <= 0:
    return

  const IconDesignSize = 50'i32
  let inset = max(1.0'f32, min(3.0'f32, size.float32 * 0.12'f32))
  let scale = max(0.01'f32, (size.float32 - inset * 2.0'f32) / IconDesignSize.float32)

  rlgl.pushMatrix()
  defer: rlgl.popMatrix()
  rlgl.translatef(x.float32 + inset, y.float32 + inset, 0.0'f32)
  rlgl.scalef(scale, scale, 1.0'f32)

  let cx = IconDesignSize div 2
  let cy = IconDesignSize div 2
  let rad = IconDesignSize.float32 / 2.5

  case powerType
  of puDoubleShot:
    # Two bullets with depth
    let bulletColor = color
    let highlightColor = Color(r: min(color.r + 60, 255), g: min(color.g + 60, 255), b: min(color.b + 60, 255), a: color.a)
    # Left bullet
    drawCircle(Vector2(x: (cx - 8).float32, y: cy.float32), 7, Color(r: 0, g: 0, b: 0, a: 80))
    drawCircle(Vector2(x: (cx - 9).float32, y: (cy - 1).float32), 7, bulletColor)
    drawCircle(Vector2(x: (cx - 10).float32, y: (cy - 2).float32), 3, highlightColor)
    # Right bullet
    drawCircle(Vector2(x: (cx + 8).float32, y: cy.float32), 7, Color(r: 0, g: 0, b: 0, a: 80))
    drawCircle(Vector2(x: (cx + 7).float32, y: (cy - 1).float32), 7, bulletColor)
    drawCircle(Vector2(x: (cx + 6).float32, y: (cy - 2).float32), 3, highlightColor)
    # Motion lines
    for i in 0..2:
      let offset = i * 3
      drawLine(int32(cx - 16 - offset), cy, int32(cx - 11 - offset), cy, Color(r: color.r, g: color.g, b: color.b, a: uint8(100 - i * 30)))
      drawLine(int32(cx + 11 + offset), cy, int32(cx + 16 + offset), cy, Color(r: color.r, g: color.g, b: color.b, a: uint8(100 - i * 30)))

  of puRotatingShield:
    # Ornate shield with layered protection
    # Outer rim with shimmer
    drawCircle(Vector2(x: cx.float32, y: cy.float32), rad + 2, Color(r: 0, g: 0, b: 0, a: 60))
    drawCircleLines(Vector2(x: cx.float32, y: cy.float32), rad, color)
    drawCircleLines(Vector2(x: cx.float32, y: cy.float32), rad - 2, color)
    drawCircleLines(Vector2(x: cx.float32, y: cy.float32), rad - 4, Color(r: color.r, g: color.g, b: color.b, a: 150))
    # Shield sectors
    for i in 0..3:
      let angle = i.float32 * PI / 2 + PI / 4
      drawCircleSector(Vector2(x: cx.float32, y: cy.float32), rad - 6,
                      angle * 180 / PI - 15, angle * 180 / PI + 15, 8,
                      Color(r: color.r, g: color.g, b: color.b, a: 120))
    # Center emblem
    drawCircle(Vector2(x: cx.float32, y: cy.float32), 5, color)
    drawCircleLines(Vector2(x: cx.float32, y: cy.float32), 7, color)

  of puMagicalBullets:
    # Mystical star with aura
    let points = 5
    # Outer glow
    for glowRad in countdown(int(rad + 4), int(rad), 2):
      drawRing(Vector2(x: cx.float32, y: cy.float32),
              glowRad.float32 - 1, glowRad.float32, 0, 360, 20,
              Color(r: color.r, g: color.g, b: color.b, a: uint8(30)))
    # Star shape with inner detail
    for i in 0..<points:
      let angle1 = i.float32 * 2 * PI / points.float32 - PI/2
      let angle2 = (i.float32 + 0.5).float32 * 2 * PI / points.float32 - PI/2
      # Outer point
      let x1 = cx.float32 + cos(angle1) * rad
      let y1 = cy.float32 + sin(angle1) * rad
      # Inner valley
      let x2 = cx.float32 + cos(angle2) * (rad * 0.4)
      let y2 = cy.float32 + sin(angle2) * (rad * 0.4)
      # Draw filled triangle
      drawTriangle(Vector2(x: cx.float32, y: cy.float32), Vector2(x: x1, y: y1), Vector2(x: x2, y: y2), color)
      drawLine(Vector2(x: x1, y: y1), Vector2(x: x2, y: y2), 2, Color(r: min(color.r + 60, 255), g: min(color.g + 60, 255), b: min(color.b + 60, 255), a: color.a))
    # Center crystal
    drawCircle(Vector2(x: cx.float32, y: cy.float32), 4, Color(r: min(color.r + 80, 255), g: min(color.g + 80, 255), b: min(color.b + 80, 255), a: 255))

  of puPiercingShots:
    # Tactical targeting arrow
    # Arrow body with gradient
    drawRectangle(cx - 12, cy - 3, 18, 6, color)
    drawRectangle(cx - 12, cy - 2, 18, 2, Color(r: min(color.r + 60, 255), g: min(color.g + 60, 255), b: min(color.b + 60, 255), a: color.a))
    # Arrow head
    drawTriangle(Vector2(x: (cx + 6).float32, y: (cy - 6).float32),
                Vector2(x: (cx + 6).float32, y: (cy + 6).float32),
                Vector2(x: (cx + 14).float32, y: cy.float32), color)
    drawLine(Vector2(x: (cx + 6).float32, y: (cy - 6).float32), Vector2(x: (cx + 14).float32, y: cy.float32), 2,
            Color(r: min(color.r + 60, 255), g: min(color.g + 60, 255), b: min(color.b + 60, 255), a: color.a))
    drawLine(Vector2(x: (cx + 6).float32, y: (cy + 6).float32), Vector2(x: (cx + 14).float32, y: cy.float32), 2,
            Color(r: min(color.r + 60, 255), g: min(color.g + 60, 255), b: min(color.b + 60, 255), a: color.a))
    # Target reticle
    drawCircleLines(Vector2(x: (cx - 10).float32, y: cy.float32), 8, color)
    drawCircleLines(Vector2(x: (cx - 10).float32, y: cy.float32), 5, Color(r: color.r, g: color.g, b: color.b, a: 150))
    # Crosshair
    drawLine(cx - 10, cy - 11, cx - 10, cy - 9, color)
    drawLine(cx - 10, cy + 9, cx - 10, cy + 11, color)
    drawLine(cx - 13, cy, cx - 15, cy, color)
    drawLine(cx - 5, cy, cx - 7, cy, color)
  of puMultiShot:
    # Triple diverging beams with energy trails
    let beamColors = [
      Color(r: color.r, g: color.g, b: color.b, a: 200),
      Color(r: color.r, g: color.g, b: color.b, a: 255),
      Color(r: color.r, g: color.g, b: color.b, a: 200)
    ]
    # Draw beams with gradient effect
    for i in 0..2:
      let yOff = int32((i - 1) * 9)
      # Beam body
      drawRectangle(cx - 12, cy + yOff - 2, 20, 4, beamColors[i])
      # Highlight
      drawRectangle(cx - 12, cy + yOff - 1, 20, 1, Color(r: min(color.r + 80, 255), g: min(color.g + 80, 255), b: min(color.b + 80, 255), a: color.a))
      # Arrow head
      drawTriangle(Vector2(x: (cx + 8).float32, y: (cy + yOff - 3).float32),
                  Vector2(x: (cx + 8).float32, y: (cy + yOff + 3).float32),
                  Vector2(x: (cx + 14).float32, y: (cy + yOff).float32), beamColors[i])
    # Source point
    drawCircle(Vector2(x: (cx - 13).float32, y: cy.float32), 5, color)
    drawCircle(Vector2(x: (cx - 13).float32, y: cy.float32), 3, Color(r: min(color.r + 80, 255), g: min(color.g + 80, 255), b: min(color.b + 80, 255), a: 255))

  of puExplosiveBullets:
    # Detailed bomb with fuse
    # Shadow
    drawCircle(Vector2(x: cx.float32, y: (cy + 2).float32), rad * 0.9, Color(r: 0, g: 0, b: 0, a: 60))
    # Main bomb body
    drawCircle(Vector2(x: cx.float32, y: cy.float32), rad * 0.9, color)
    # Shine highlight
    drawCircle(Vector2(x: (cx - 3).float32, y: (cy - 3).float32), 4, Color(r: min(color.r + 100, 255), g: min(color.g + 100, 255), b: min(color.b + 100, 255), a: 180))
    # Fuse
    let fuseTop = cy - int32(rad * 0.9'f32) - 3
    drawRectangle(cx - 2, fuseTop, 4, 8, Color(r: 80, g: 60, b: 40, a: 255))
    # Spark on fuse
    drawCircle(Vector2(x: cx.float32, y: fuseTop.float32), 3, Color(r: 255, g: 200, b: 50, a: 255))
    drawCircle(Vector2(x: cx.float32, y: fuseTop.float32), 1.5'f32, Color(r: 255, g: 255, b: 200, a: 255))
    # Warning symbol on bomb
    drawLine(cx, cy - 5, cx, cy + 2, Color(r: 255, g: 100, b: 0, a: 255))
    drawCircle(Vector2(x: cx.float32, y: (cy + 5).float32), 1, Color(r: 255, g: 100, b: 0, a: 255))
  of puLifeSteal, puBloodBullets, puBloodOrb, puBloodAura, puBloodMastery:
    # Detailed blood drop with shine
    # Shadow
    drawCircle(Vector2(x: (cx + 1).float32, y: (cy + 3).float32), rad * 0.7, Color(r: 0, g: 0, b: 0, a: 60))
    # Main drop body
    drawCircle(Vector2(x: cx.float32, y: (cy + 2).float32), rad * 0.7, color)
    drawTriangle(Vector2(x: cx.float32, y: (cy - int32(rad * 0.9)).float32),
                Vector2(x: (cx - 7).float32, y: (cy + 2).float32),
                Vector2(x: (cx + 7).float32, y: (cy + 2).float32), color)
    # Highlight shine
    drawCircle(Vector2(x: (cx - 3).float32, y: (cy - 2).float32), 3, Color(r: min(color.r + 100, 255), g: min(color.g + 100, 255), b: min(color.b + 100, 255), a: 200))
    drawCircle(Vector2(x: (cx + 4).float32, y: (cy + 4).float32), 2, Color(r: min(color.r + 80, 255), g: min(color.g + 80, 255), b: min(color.b + 80, 255), a: 150))
    # Drip effect
    drawCircle(Vector2(x: cx.float32, y: (cy + int32(rad * 0.7) + 3).float32), 2, Color(r: color.r, g: color.g, b: color.b, a: 180))

  of puRapidFire, puOvercharge:
    # Lightning bolt with energy
    # Glow effect
    for i in 1..3:
      let offset = i * 2
      drawLine(Vector2(x: (cx + offset).float32, y: (cy - 12).float32),
               Vector2(x: (cx + 4 + offset).float32, y: (cy - 2).float32), float32(4 - i),
               Color(r: color.r, g: color.g, b: color.b, a: uint8(60 - i * 15)))
    # Main bolt
    drawLine(Vector2(x: (cx + 2).float32, y: (cy - 12).float32),
             Vector2(x: (cx + 4).float32, y: (cy - 2).float32), 4, color)
    drawLine(Vector2(x: (cx + 4).float32, y: (cy - 2).float32),
             Vector2(x: (cx - 2).float32, y: (cy + 2).float32), 4, color)
    drawLine(Vector2(x: (cx - 2).float32, y: (cy + 2).float32),
             Vector2(x: cx.float32, y: (cy + 12).float32), 4, color)
    # Bright core
    drawLine(Vector2(x: (cx + 2).float32, y: (cy - 12).float32),
             Vector2(x: (cx + 4).float32, y: (cy - 2).float32), 2,
             Color(r: min(color.r + 120, 255), g: min(color.g + 120, 255), b: min(color.b + 120, 255), a: 255))
    drawLine(Vector2(x: (cx + 4).float32, y: (cy - 2).float32),
             Vector2(x: (cx - 2).float32, y: (cy + 2).float32), 2,
             Color(r: min(color.r + 120, 255), g: min(color.g + 120, 255), b: min(color.b + 120, 255), a: 255))
    # Spark points
    drawCircle(Vector2(x: (cx + 2).float32, y: (cy - 12).float32), 3, Color(r: min(color.r + 150, 255), g: min(color.g + 150, 255), b: min(color.b + 150, 255), a: 255))
    drawCircle(Vector2(x: cx.float32, y: (cy + 12).float32), 3, Color(r: min(color.r + 150, 255), g: min(color.g + 150, 255), b: min(color.b + 150, 255), a: 255))
  of puMaxHealth:
    # Detailed 3D heart
    # Shadow
    drawCircle(Vector2(x: (cx - 4).float32, y: (cy - 1).float32), 6, Color(r: 0, g: 0, b: 0, a: 60))
    drawCircle(Vector2(x: (cx + 6).float32, y: (cy - 1).float32), 6, Color(r: 0, g: 0, b: 0, a: 60))
    # Main heart chambers
    drawCircle(Vector2(x: (cx - 5).float32, y: (cy - 3).float32), 6, color)
    drawCircle(Vector2(x: (cx + 5).float32, y: (cy - 3).float32), 6, color)
    drawTriangle(Vector2(x: (cx - 11).float32, y: (cy - 3).float32),
                Vector2(x: (cx + 11).float32, y: (cy - 3).float32),
                Vector2(x: cx.float32, y: (cy + 12).float32), color)
    # Highlights
    drawCircle(Vector2(x: (cx - 7).float32, y: (cy - 6).float32), 3, Color(r: min(color.r + 100, 255), g: min(color.g + 100, 255), b: min(color.b + 100, 255), a: 200))
    drawCircle(Vector2(x: (cx + 3).float32, y: (cy - 6).float32), 2, Color(r: min(color.r + 80, 255), g: min(color.g + 80, 255), b: min(color.b + 80, 255), a: 150))
    # Pulse rings
    drawCircleLines(Vector2(x: cx.float32, y: (cy + 1).float32), rad + 4, Color(r: color.r, g: color.g, b: color.b, a: 60))
    drawCircleLines(Vector2(x: cx.float32, y: (cy + 1).float32), rad + 2, Color(r: color.r, g: color.g, b: color.b, a: 100))

  of puSpeedBoost:
    # Athletic shoe with motion
    # Shoe sole shadow
    drawRectangle(cx - 7, cy - 2, 14, 10, Color(r: 0, g: 0, b: 0, a: 60))
    # Main shoe body
    drawRectangle(cx - 9, cy - 4, 14, 9, color)
    # Highlight stripe
    drawRectangle(cx - 9, cy - 3, 14, 2, Color(r: min(color.r + 80, 255), g: min(color.g + 80, 255), b: min(color.b + 80, 255), a: 255))
    # Wing/speed indicator
    drawTriangle(Vector2(x: (cx + 5).float32, y: cy.float32),
                Vector2(x: (cx + 5).float32, y: (cy - 9).float32),
                Vector2(x: (cx + 14).float32, y: (cy - 5).float32), color)
    drawLine(Vector2(x: (cx + 5).float32, y: (cy - 9).float32), Vector2(x: (cx + 14).float32, y: (cy - 5).float32), 2,
            Color(r: min(color.r + 80, 255), g: min(color.g + 80, 255), b: min(color.b + 80, 255), a: 255))
    # Speed lines
    for i in 0..2:
      let xOff = int32(-14 - i * 4)
      drawLine(int32(cx + xOff), int32(cy - int32(2 + i * 2)), int32(cx + xOff + 6), int32(cy - int32(2 + i * 2)), Color(r: color.r, g: color.g, b: color.b, a: uint8(120 - i * 30)))
  of puCriticalHit:
    # Detailed sword with gleam
    # Shadow
    drawRectangle(cx - 1, cy - 9, 5, 14, Color(r: 0, g: 0, b: 0, a: 60))
    # Blade
    drawRectangle(cx - 2, cy - 11, 4, 14, color)
    drawLine(cx, cy - 11, cx, cy + 3, Color(r: min(color.r + 120, 255), g: min(color.g + 120, 255), b: min(color.b + 120, 255), a: 255))
    # Crossguard
    drawRectangle(cx - 7, cy + 3, 14, 4, Color(r: min(color.r - 30, 0), g: min(color.g - 30, 0), b: min(color.b - 30, 0), a: color.a))
    drawRectangle(cx - 7, cy + 3, 14, 2, color)
    # Handle
    drawRectangle(cx - 3, cy + 7, 6, 7, Color(r: 100, g: 70, b: 50, a: 255))
    drawRectangle(cx - 3, cy + 8, 6, 1, Color(r: 150, g: 120, b: 90, a: 255))
    drawRectangle(cx - 3, cy + 11, 6, 1, Color(r: 150, g: 120, b: 90, a: 255))
    # Pommel
    drawCircle(Vector2(x: cx.float32, y: (cy + 15).float32), 3, Color(r: 120, g: 90, b: 60, a: 255))
    # Shine effect
    drawLine(cx - 1, cy - 9, cx - 1, cy - 3, Color(r: 255, g: 255, b: 255, a: 180))

  of puCurse:
    # Cursed skull: rounded cranium, two hollow eye sockets, a small toothy jaw
    let dark = Color(r: color.r div 3, g: color.g div 3, b: color.b div 3, a: color.a)
    let bright = Color(r: min(color.r.int + 90, 255).uint8,
                       g: min(color.g.int + 90, 255).uint8,
                       b: min(color.b.int + 90, 255).uint8, a: color.a)
    # Pulsing curse halo
    let cp = (sin(getTime() * 4.0) * 0.5 + 0.5).float32
    drawCircleLines(cx, cy - 2, rad + 1.0 + cp * 2.0,
                    Color(r: bright.r, g: bright.g, b: bright.b, a: uint8(70 + cp * 70)))
    # Cranium
    drawCircle(Vector2(x: cx.float32, y: (cy - 3).float32), rad * 0.85, color)
    drawCircleLines(cx, cy - 3, rad * 0.85, dark)
    # Jaw block
    drawRectangle(cx - int32(rad * 0.45), cy + int32(rad * 0.35),
                  int32(rad * 0.9), int32(rad * 0.45), color)
    # Teeth gaps
    drawLine(cx, cy + int32(rad * 0.35), cx, cy + int32(rad * 0.8), dark)
    drawLine(cx - int32(rad * 0.22), cy + int32(rad * 0.35), cx - int32(rad * 0.22), cy + int32(rad * 0.8), dark)
    drawLine(cx + int32(rad * 0.22), cy + int32(rad * 0.35), cx + int32(rad * 0.22), cy + int32(rad * 0.8), dark)
    # Eye sockets
    drawCircle(Vector2(x: (cx - int32(rad * 0.35)).float32, y: (cy - int32(rad * 0.15)).float32), rad * 0.26, dark)
    drawCircle(Vector2(x: (cx + int32(rad * 0.35)).float32, y: (cy - int32(rad * 0.15)).float32), rad * 0.26, dark)
    # Glowing eye points
    drawCircle(Vector2(x: (cx - int32(rad * 0.35)).float32, y: (cy - int32(rad * 0.15)).float32), rad * 0.10, bright)
    drawCircle(Vector2(x: (cx + int32(rad * 0.35)).float32, y: (cy - int32(rad * 0.15)).float32), rad * 0.10, bright)

  of puBulletSpeed:
    # Detailed rocket with flames
    # Shadow
    drawTriangle(Vector2(x: (cx + 1).float32, y: (cy - 9).float32),
                Vector2(x: (cx - 3).float32, y: (cy - 1).float32),
                Vector2(x: (cx + 5).float32, y: (cy - 1).float32), Color(r: 0, g: 0, b: 0, a: 60))
    # Nose cone
    drawTriangle(Vector2(x: cx.float32, y: (cy - 11).float32),
                Vector2(x: (cx - 5).float32, y: (cy - 2).float32),
                Vector2(x: (cx + 5).float32, y: (cy - 2).float32), color)
    # Highlight on cone
    drawLine(cx - 2, cy - 8, cx - 2, cy - 3, Color(r: min(color.r + 100, 255), g: min(color.g + 100, 255), b: min(color.b + 100, 255), a: 200))
    # Body
    drawRectangle(cx - 4, cy - 2, 8, 12, color)
    drawRectangle(cx - 3, cy - 2, 3, 12, Color(r: min(color.r + 60, 255), g: min(color.g + 60, 255), b: min(color.b + 60, 255), a: 255))
    # Window
    drawCircle(Vector2(x: cx.float32, y: (cy + 2).float32), 3, Color(r: 100, g: 180, b: 255, a: 255))
    drawCircle(Vector2(x: (cx - 1).float32, y: (cy + 1).float32), 2, Color(r: 150, g: 220, b: 255, a: 200))
    # Fins
    drawTriangle(Vector2(x: (cx - 4).float32, y: (cy + 10).float32),
                Vector2(x: (cx - 8).float32, y: (cy + 14).float32),
                Vector2(x: (cx - 4).float32, y: (cy + 12).float32), color)
    drawTriangle(Vector2(x: (cx + 4).float32, y: (cy + 10).float32),
                Vector2(x: (cx + 8).float32, y: (cy + 14).float32),
                Vector2(x: (cx + 4).float32, y: (cy + 12).float32), color)
    # Exhaust flames
    drawTriangle(Vector2(x: (cx - 3).float32, y: (cy + 10).float32),
                Vector2(x: (cx + 3).float32, y: (cy + 10).float32),
                Vector2(x: cx.float32, y: (cy + 16).float32), Color(r: 255, g: 150, b: 50, a: 255))
    drawTriangle(Vector2(x: (cx - 2).float32, y: (cy + 10).float32),
                Vector2(x: (cx + 2).float32, y: (cy + 10).float32),
                Vector2(x: cx.float32, y: (cy + 14).float32), Color(r: 255, g: 220, b: 100, a: 255))
  of puLuckyCoins:
    # Stacked coins with shine
    # Bottom coin shadow
    drawCircle(Vector2(x: (cx + 1).float32, y: (cy + 6).float32), 8, Color(r: 0, g: 0, b: 0, a: 60))
    # Three layered coins
    for i in countdown(2, 0):
      let yOff = int32(cy + i * 4 - 4)
      # Coin body
      drawCircle(Vector2(x: cx.float32, y: yOff.float32), 8, color)
      # Edge detail
      drawCircleLines(Vector2(x: cx.float32, y: yOff.float32), 8, Color(r: min(color.r + 80, 255), g: min(color.g + 80, 255), b: min(color.b + 80, 255), a: 255))
      drawCircleLines(Vector2(x: cx.float32, y: yOff.float32), 6, Color(r: color.r, g: color.g, b: color.b, a: 200))
      # Symbol
      if i == 0:  # Top coin gets the symbol
        drawText("$", cx - 4, yOff - 6, 12, Color(r: min(color.r + 100, 255), g: min(color.g + 100, 255), b: min(color.b + 100, 255), a: 255))
      # Shine
      drawCircle(Vector2(x: (cx - 3).float32, y: (yOff - 3).float32), 2, Color(r: 255, g: 255, b: 200, a: 200))

  of puWallMaster:
    # Brick wall with mortar
    let brickColor = color
    let mortarColor = Color(r: max(color.r - 50, 0), g: max(color.g - 50, 0), b: max(color.b - 50, 0), a: 255)
    # Draw mortar background
    drawRectangle(cx - 12, cy - 10, 24, 20, mortarColor)
    # Draw bricks with 3D effect
    for row in 0..2:
      let yPos: int32 = cy - 10 + int32(row * 7)
      let offset: int32 = if row mod 2 == 0: 0 else: 6
      for col in 0..2:
        let xPos: int32 = cx - 12 + offset + int32(col * 12)
        if xPos + 10 <= cx + 12:  # Don't draw if outside wall bounds
          # Brick shadow
          drawRectangle(xPos + 1, yPos + 1, 10, 5, Color(r: 0, g: 0, b: 0, a: 80))
          # Brick body
          drawRectangle(xPos, yPos, 10, 5, brickColor)
          # Highlight
          drawRectangle(xPos, yPos, 10, 1, Color(r: min(brickColor.r + 60, 255), g: min(brickColor.g + 60, 255), b: min(brickColor.b + 60, 255), a: 255))
          drawRectangle(xPos, yPos, 1, 5, Color(r: min(brickColor.r + 40, 255), g: min(brickColor.g + 40, 255), b: min(brickColor.b + 40, 255), a: 255))
    # Frame
    drawRectangleLines(Rectangle(x: (cx - 12).float32, y: (cy - 10).float32, width: 24, height: 20), 2, color)

  of puRegeneration:
    # Medical cross with pulse
    # Pulse rings
    for i in 1..3:
      drawCircleLines(Vector2(x: cx.float32, y: cy.float32), rad + i.float32 * 2,
                     Color(r: color.r, g: color.g, b: color.b, a: uint8(100 - i * 25)))
    # Circle background
    drawCircle(Vector2(x: (cx + 1).float32, y: (cy + 1).float32), rad, Color(r: 0, g: 0, b: 0, a: 60))
    drawCircle(Vector2(x: cx.float32, y: cy.float32), rad, Color(r: 255, g: 255, b: 255, a: 255))
    drawCircleLines(Vector2(x: cx.float32, y: cy.float32), rad, color)
    # Medical cross with depth
    # Vertical bar
    drawRectangle(cx - 3, cy - 10, 6, 20, color)
    drawRectangle(cx - 2, cy - 10, 2, 20, Color(r: min(color.r + 80, 255), g: min(color.g + 80, 255), b: min(color.b + 80, 255), a: 255))
    # Horizontal bar
    drawRectangle(cx - 10, cy - 3, 20, 6, color)
    drawRectangle(cx - 10, cy - 2, 20, 2, Color(r: min(color.r + 80, 255), g: min(color.g + 80, 255), b: min(color.b + 80, 255), a: 255))
  of puDodgeChance:
    # Dynamic wind/evasion lines with motion blur
    let baseAlpha = 150
    # Multiple speed lines at different heights
    for i in 0..3:
      let yy = int32(cy - 9 + i * 6)
      let lineLength = int32(18 - i * 2)
      # Motion trail
      for j in 0..2:
        let xOffset = int32(-j * 3)
        let alpha = uint8(baseAlpha - j * 40 - i * 10)
        drawLine(cx - 12 + xOffset, yy, cx - 12 + xOffset + lineLength, yy,
                Color(r: color.r, g: color.g, b: color.b, a: alpha))
      # Arrow tip
      drawLine(cx + 8, yy, cx + 4, yy - 3, color)
      drawLine(cx + 8, yy, cx + 4, yy + 3, color)
    # Blur silhouette
    for i in 0..2:
      let alpha = uint8(60 - i * 15)
      drawCircle(Vector2(x: (cx - 6 - i * 3).float32, y: cy.float32), 4,
                Color(r: color.r, g: color.g, b: color.b, a: alpha))

  of puBulletRicochet:
    # Bouncing trajectory with impact points
    # Path line
    drawLine(Vector2(x: (cx - 12).float32, y: (cy + 8).float32), Vector2(x: (cx - 4).float32, y: (cy - 8).float32), 3.0, color)
    drawLine(Vector2(x: (cx - 4).float32, y: (cy - 8).float32), Vector2(x: (cx + 4).float32, y: cy.float32), 3.0, color)
    drawLine(Vector2(x: (cx + 4).float32, y: cy.float32), Vector2(x: (cx + 12).float32, y: (cy - 8).float32), 3.0, color)
    # Impact/bounce points with rings
    for i, pos in [(cx - 4, cy - 8), (cx + 4, cy)]:
      drawCircle(Vector2(x: pos[0].float32, y: pos[1].float32), 4, color)
      drawCircleLines(Vector2(x: pos[0].float32, y: pos[1].float32), 6,
                     Color(r: color.r, g: color.g, b: color.b, a: 150))
      drawCircleLines(Vector2(x: pos[0].float32, y: pos[1].float32), 8,
                     Color(r: color.r, g: color.g, b: color.b, a: 80))
    # Arrowhead at end
    drawLine(Vector2(x: (cx + 12).float32, y: (cy - 8).float32), Vector2(x: (cx + 8).float32, y: (cy - 6).float32), 2.0, color)
    drawLine(Vector2(x: (cx + 12).float32, y: (cy - 8).float32), Vector2(x: (cx + 10).float32, y: (cy - 11).float32), 2.0, color)
    # Bullet trail
    drawCircle(Vector2(x: (cx - 12).float32, y: (cy + 8).float32), 3,
              Color(r: min(color.r + 80, 255), g: min(color.g + 80, 255), b: min(color.b + 80, 255), a: 255))
  of puSlowField, puFrostShots, puFrostOrb, puFrostMastery:
    # Detailed snowflake with ice crystals
    # Center crystal
    drawCircle(Vector2(x: cx.float32, y: cy.float32), 4, Color(r: min(color.r + 120, 255), g: min(color.g + 120, 255), b: min(color.b + 120, 255), a: 255))
    # Main axes with gradient
    for i in 0..5:
      let angle = i.float32 * PI / 3
      let cos_a = cos(angle)
      let sin_a = sin(angle)
      # Main branch
      drawLine(Vector2(x: cx.float32, y: cy.float32),
              Vector2(x: cx.float32 + cos_a * (rad + 2), y: cy.float32 + sin_a * (rad + 2)), 3, color)
      drawLine(Vector2(x: cx.float32, y: cy.float32),
              Vector2(x: cx.float32 + cos_a * (rad - 2), y: cy.float32 + sin_a * (rad - 2)), 2,
              Color(r: min(color.r + 80, 255), g: min(color.g + 80, 255), b: min(color.b + 80, 255), a: 255))
      # Branch detail - sub-arms
      for side in [-1, 1]:
        let branchAngle = angle + side.float32 * PI / 6
        let startDist = rad * 0.6
        let endDist = rad * 0.4
        drawLine(Vector2(x: cx.float32 + cos_a * startDist, y: cy.float32 + sin_a * startDist),
                Vector2(x: cx.float32 + cos(branchAngle) * (startDist + endDist),
                        y: cy.float32 + sin(branchAngle) * (startDist + endDist)), 2, color)
    # Ice crystals at tips
    for i in 0..5:
      let angle = i.float32 * PI / 3
      let tipX = cx.float32 + cos(angle) * (rad + 2)
      let tipY = cy.float32 + sin(angle) * (rad + 2)
      drawCircle(Vector2(x: tipX, y: tipY), 2, Color(r: 200, g: 230, b: 255, a: 255))

  of puRage, puBerserker:
    # Angry face with veins and intensity
    # Face outline
    drawCircle(Vector2(x: (cx + 1).float32, y: (cy + 1).float32), rad, Color(r: 0, g: 0, b: 0, a: 60))
    drawCircle(Vector2(x: cx.float32, y: cy.float32), rad, Color(r: 180, g: 40, b: 40, a: 255))
    drawCircleLines(Vector2(x: cx.float32, y: cy.float32), rad, color)
    # Anger veins
    drawLine(Vector2(x: (cx - int32(rad) + 2).float32, y: (cy - 8).float32), Vector2(x: (cx - int32(rad) + 5).float32, y: (cy - 5).float32), 2.0, Color(r: 150, g: 30, b: 30, a: 255))
    drawLine(Vector2(x: (cx + int32(rad) - 2).float32, y: (cy - 8).float32), Vector2(x: (cx + int32(rad) - 5).float32, y: (cy - 5).float32), 2.0, Color(r: 150, g: 30, b: 30, a: 255))
    # Angry X eyes with glow
    for eyeX in [cx - 6, cx + 6]:
      drawLine(Vector2(x: (eyeX - 3).float32, y: (cy - 5).float32), Vector2(x: (eyeX + 3).float32, y: (cy - 1).float32), 3.0, color)
      drawLine(Vector2(x: (eyeX + 3).float32, y: (cy - 5).float32), Vector2(x: (eyeX - 3).float32, y: (cy - 1).float32), 3.0, color)
      # Eye glow
      drawCircle(Vector2(x: eyeX.float32, y: (cy - 3).float32), 2,
                Color(r: 255, g: 100, b: 100, a: 150))
    # Angry frown with teeth
    drawLine(Vector2(x: (cx - 8).float32, y: (cy + 6).float32), Vector2(x: (cx + 8).float32, y: (cy + 6).float32), 3.0, color)
    # Teeth
    for i in 0..3:
      let toothX = cx - 6 + i * 4
      drawLine(Vector2(x: toothX.float32, y: (cy + 5).float32), Vector2(x: toothX.float32, y: (cy + 8).float32), 2.0, Color(r: 255, g: 255, b: 255, a: 255))
  of puThorns:
    # Rose with detailed thorns
    # Stem with thorns
    drawRectangle(cx - 2, cy - 2, 4, 14, Color(r: 80, g: 140, b: 80, a: 255))
    drawRectangle(cx - 1, cy - 2, 1, 14, Color(r: 120, g: 180, b: 120, a: 255))
    # Thorns on stem
    for i in 0..3:
      let thornY = cy + i * 3
      # Left thorn
      drawTriangle(Vector2(x: (cx - 2).float32, y: thornY.float32),
                  Vector2(x: (cx - 5).float32, y: (thornY + 2).float32),
                  Vector2(x: (cx - 2).float32, y: (thornY + 2).float32), Color(r: 60, g: 100, b: 60, a: 255))
      # Right thorn
      drawTriangle(Vector2(x: (cx + 2).float32, y: thornY.float32),
                  Vector2(x: (cx + 5).float32, y: (thornY + 2).float32),
                  Vector2(x: (cx + 2).float32, y: (thornY + 2).float32), Color(r: 60, g: 100, b: 60, a: 255))
    # Rose bloom
    drawCircle(Vector2(x: (cx + 1).float32, y: (cy - 5).float32), 7, Color(r: 0, g: 0, b: 0, a: 60))
    drawCircle(Vector2(x: cx.float32, y: (cy - 6).float32), 7, color)
    # Rose petals detail
    for i in 0..4:
      let angle = i.float32 * 2 * PI / 5
      let petalX = cx.float32 + cos(angle) * 5
      let petalY = cy.float32 - 6 + sin(angle) * 5
      drawCircle(Vector2(x: petalX, y: petalY), 3, Color(r: color.r, g: color.g, b: color.b, a: 200))
    # Center highlight
    drawCircle(Vector2(x: (cx - 2).float32, y: (cy - 8).float32), 2,
              Color(r: min(color.r + 100, 255), g: min(color.g + 100, 255), b: min(color.b + 100, 255), a: 255))

  of puBulletSplit:
    # Trident/fork with energy
    # Central prong
    drawLine(Vector2(x: cx.float32, y: (cy - 12).float32), Vector2(x: cx.float32, y: (cy + 12).float32), 3.0, color)
    drawLine(Vector2(x: cx.float32, y: (cy - 12).float32), Vector2(x: cx.float32, y: (cy + 8).float32), 2.0, Color(r: min(color.r + 80, 255), g: min(color.g + 80, 255), b: min(color.b + 80, 255), a: 255))
    # Left prong
    drawLine(Vector2(x: (cx - 6).float32, y: (cy - 12).float32), Vector2(x: (cx - 6).float32, y: (cy - 2).float32), 3.0, color)
    drawLine(Vector2(x: (cx - 6).float32, y: (cy - 12).float32), Vector2(x: (cx - 6).float32, y: (cy - 4).float32), 2.0, Color(r: min(color.r + 80, 255), g: min(color.g + 80, 255), b: min(color.b + 80, 255), a: 255))
    # Right prong
    drawLine(Vector2(x: (cx + 6).float32, y: (cy - 12).float32), Vector2(x: (cx + 6).float32, y: (cy - 2).float32), 3.0, color)
    drawLine(Vector2(x: (cx + 6).float32, y: (cy - 12).float32), Vector2(x: (cx + 6).float32, y: (cy - 4).float32), 2.0, Color(r: min(color.r + 80, 255), g: min(color.g + 80, 255), b: min(color.b + 80, 255), a: 255))
    # Connection pieces
    drawLine(Vector2(x: (cx - 6).float32, y: (cy - 2).float32), Vector2(x: cx.float32, y: (cy + 2).float32), 2.0, color)
    drawLine(Vector2(x: (cx + 6).float32, y: (cy - 2).float32), Vector2(x: cx.float32, y: (cy + 2).float32), 2.0, color)
    # Energy balls at tips
    for prong in [cx - 6, cx, cx + 6]:
      drawCircle(Vector2(x: prong.float32, y: (cy - 12).float32), 3,
                Color(r: min(color.r + 120, 255), g: min(color.g + 120, 255), b: min(color.b + 120, 255), a: 255))
      drawCircleLines(Vector2(x: prong.float32, y: (cy - 12).float32), 4, color)
    # Handle
    drawRectangle(cx - 3, cy + 2, 6, 10, Color(r: 100, g: 80, b: 60, a: 255))
  of puChainLightning, puLightningAura, puLightningOrb, puLightningMastery:
    # Forked lightning bolt with glow
    # Glow effect
    for i in 1..4:
      let glowOffset = i * 2
      let alpha = uint8(80 - i * 15)
      drawLine(Vector2(x: (cx + 3 + glowOffset).float32, y: (cy - 12).float32),
              Vector2(x: (cx + 1 + glowOffset).float32, y: (cy - 3).float32), float32(5 - i),
              Color(r: color.r, g: color.g, b: color.b, a: alpha))
    # Main bolt
    drawLine(Vector2(x: (cx + 3).float32, y: (cy - 12).float32),
            Vector2(x: (cx + 1).float32, y: (cy - 3).float32), 5, color)
    drawLine(Vector2(x: (cx + 1).float32, y: (cy - 3).float32),
            Vector2(x: (cx + 5).float32, y: cy.float32), 5, color)
    drawLine(Vector2(x: (cx + 5).float32, y: cy.float32),
            Vector2(x: (cx - 2).float32, y: (cy + 12).float32), 5, color)
    # Bright core
    drawLine(Vector2(x: (cx + 3).float32, y: (cy - 12).float32),
            Vector2(x: (cx + 1).float32, y: (cy - 3).float32), 2,
            Color(r: 255, g: 255, b: 255, a: 255))
    drawLine(Vector2(x: (cx + 5).float32, y: cy.float32),
            Vector2(x: (cx - 2).float32, y: (cy + 12).float32), 2,
            Color(r: 255, g: 255, b: 255, a: 255))
    # Side branches
    drawLine(Vector2(x: (cx + 1).float32, y: (cy - 3).float32),
            Vector2(x: (cx - 3).float32, y: (cy - 1).float32), 3, color)
    drawLine(Vector2(x: (cx + 5).float32, y: cy.float32),
            Vector2(x: (cx + 9).float32, y: (cy + 2).float32), 3, color)
    # Electrical points
    for pos in [(cx + 3, cy - 12), (cx - 2, cy + 12)]:
      drawCircle(Vector2(x: pos[0].float32, y: pos[1].float32), 3,
                Color(r: 255, g: 255, b: 255, a: 255))
      drawCircleLines(Vector2(x: pos[0].float32, y: pos[1].float32), 5, color)
  of puPoisonShot, puPoisonAura, puPoisonOrb, puPoisonMastery:
    # Skull with poison drip
    # Skull shadow
    drawCircle(Vector2(x: (cx + 1).float32, y: cy.float32), 9, Color(r: 0, g: 0, b: 0, a: 60))
    # Skull main
    drawCircle(Vector2(x: cx.float32, y: (cy - 2).float32), 9, color)
    # Eye sockets
    drawCircle(Vector2(x: (cx - 4).float32, y: (cy - 4).float32), 3, Black)
    drawCircle(Vector2(x: (cx + 4).float32, y: (cy - 4).float32), 3, Black)
    # Eye glow
    drawCircle(Vector2(x: (cx - 4).float32, y: (cy - 5).float32), 2,
              Color(r: min(color.r + 100, 255), g: min(color.g + 100, 255), b: color.b, a: 200))
    drawCircle(Vector2(x: (cx + 4).float32, y: (cy - 5).float32), 2,
              Color(r: min(color.r + 100, 255), g: min(color.g + 100, 255), b: color.b, a: 200))
    # Nose
    drawTriangle(Vector2(x: cx.float32, y: (cy - 1).float32),
                Vector2(x: (cx - 2).float32, y: (cy + 2).float32),
                Vector2(x: (cx + 2).float32, y: (cy + 2).float32), Black)
    # Jaw with teeth
    drawRectangle(cx - 5, cy + 3, 10, 7, color)
    # Teeth detail
    for i in 0..4:
      let toothX = int32(cx - 4 + i * 2)
      drawRectangle(toothX, cy + 3, 1, 3, Black)
    # Poison drip below
    for i in 0..2:
      let dropY = int32(cy + 11 + i * 4)
      let dropSize = 3 - i
      drawCircle(Vector2(x: cx.float32, y: dropY.float32), dropSize.float32,
                Color(r: color.r, g: color.g, b: color.b, a: uint8(200 - i * 50)))

  of puFireBullets, puFireAura, puFireOrb, puFireMastery:
    # Layered flame with heat shimmer
    # Bottom flame (darker/orange)
    drawTriangle(Vector2(x: cx.float32, y: (cy - 11).float32),
                Vector2(x: (cx - 7).float32, y: (cy + 10).float32),
                Vector2(x: (cx + 7).float32, y: (cy + 10).float32),
                Color(r: 255, g: 100, b: 20, a: 255))
    # Middle flame (bright orange)
    drawTriangle(Vector2(x: cx.float32, y: (cy - 8).float32),
                Vector2(x: (cx - 5).float32, y: (cy + 8).float32),
                Vector2(x: (cx + 5).float32, y: (cy + 8).float32),
                Color(r: 255, g: 150, b: 40, a: 255))
    # Inner flame (yellow)
    drawTriangle(Vector2(x: cx.float32, y: (cy - 6).float32),
                Vector2(x: (cx - 3).float32, y: (cy + 5).float32),
                Vector2(x: (cx + 3).float32, y: (cy + 5).float32),
                Color(r: 255, g: 220, b: 100, a: 255))
    # Core (white hot)
    drawTriangle(Vector2(x: cx.float32, y: (cy - 3).float32),
                Vector2(x: (cx - 2).float32, y: (cy + 3).float32),
                Vector2(x: (cx + 2).float32, y: (cy + 3).float32),
                Color(r: 255, g: 255, b: 220, a: 255))
    # Heat shimmer particles
    for i in 0..3:
      let particleY = cy + 10 + i * 3
      let particleX = cx + (if i mod 2 == 0: -3 else: 3)
      drawCircle(Vector2(x: particleX.float32, y: particleY.float32), 2,
                Color(r: 255, g: 200, b: 100, a: uint8(150 - i * 30)))
  of puWindBullets, puWindAura, puWindOrb, puWindMastery:
    # Wind swirls and gusts
    # Multiple curved wind streams
    for i in 0..2:
      let offsetX = i * 5 - 5
      let startAngle = 180.0
      let endAngle = 0.0
      # Main arc
      drawCircleSector(Vector2(x: (cx + offsetX).float32, y: cy.float32),
                      rad * 0.7, startAngle, endAngle, 12,
                      Color(r: color.r, g: color.g, b: color.b, a: uint8(180 - i * 40)))
      # Secondary smaller arcs
      drawCircleSector(Vector2(x: (cx + offsetX).float32, y: (cy - 4).float32),
                      rad * 0.4, startAngle, endAngle, 8,
                      Color(r: color.r, g: color.g, b: color.b, a: uint8(120 - i * 30)))
    # Wind particles/leaves
    for i in 0..4:
      let particleAngle = i.float32 * 0.8
      let particleX = cx + int32(cos(particleAngle) * (rad + 5))
      let particleY = cy + int32(sin(particleAngle) * 8)
      drawCircle(Vector2(x: particleX.float32, y: particleY.float32), 2,
                Color(r: color.r, g: color.g, b: color.b, a: 200))

  of puTimeWarp:
    # Ornate clock with roman numerals
    # Clock face shadow
    drawCircle(Vector2(x: (cx + 1).float32, y: (cy + 1).float32), rad, Color(r: 0, g: 0, b: 0, a: 60))
    # Clock face
    drawCircle(Vector2(x: cx.float32, y: cy.float32), rad, Color(r: 30, g: 35, b: 45, a: 255))
    drawCircleLines(Vector2(x: cx.float32, y: cy.float32), rad, color)
    drawCircleLines(Vector2(x: cx.float32, y: cy.float32), rad - 2, Color(r: color.r, g: color.g, b: color.b, a: 150))
    # Hour marks
    for i in 0..11:
      let angle = i.float32 * PI / 6 - PI / 2
      let markX = cx.float32 + cos(angle) * (rad - 4)
      let markY = cy.float32 + sin(angle) * (rad - 4)
      let markSize = if i mod 3 == 0: 3 else: 2
      drawCircle(Vector2(x: markX, y: markY), markSize.float32, color)
    # Clock hands with glow
    # Hour hand
    drawLine(Vector2(x: cx.float32, y: cy.float32),
            Vector2(x: cx.float32, y: (cy - 8).float32), 3, color)
    # Minute hand
    drawLine(Vector2(x: cx.float32, y: cy.float32),
            Vector2(x: (cx + 7).float32, y: cy.float32), 2, color)
    # Center pivot
    drawCircle(Vector2(x: cx.float32, y: cy.float32), 3, Color(r: min(color.r + 100, 255), g: min(color.g + 100, 255), b: min(color.b + 100, 255), a: 255))
  of puGravityWell:
    # Gravitational vortex with orbiting matter
    # Central singularity
    drawCircle(Vector2(x: cx.float32, y: cy.float32), 5, Color(r: 0, g: 0, b: 20, a: 255))
    drawCircleLines(Vector2(x: cx.float32, y: cy.float32), 6, color)
    # Spiral arms
    for arm in 0..2:
      let armAngle = arm.float32 * 2 * PI / 3
      for i in 0..8:
        let dist = i.float32 * 2 + 8
        let angle = armAngle + i.float32 * 0.4
        let spiralX = cx.float32 + cos(angle) * dist
        let spiralY = cy.float32 + sin(angle) * dist
        let dotSize = 3 - i div 3
        drawCircle(Vector2(x: spiralX, y: spiralY), dotSize.float32,
                  Color(r: color.r, g: color.g, b: color.b, a: uint8(255 - i * 20)))
    # Accretion disk rings
    for i in 1..3:
      let ringRad = rad * (0.3 + i.float32 * 0.25)
      drawCircleLines(Vector2(x: cx.float32, y: cy.float32), ringRad,
                     Color(r: color.r, g: color.g, b: color.b, a: uint8(150 - i * 30)))

  of puPhaseShift:
    # Ghost/transparent figure phasing
    # Solid form (leaving)
    drawCircle(Vector2(x: (cx - 6).float32, y: (cy - 4).float32), 6,
              Color(r: color.r, g: color.g, b: color.b, a: 180))
    drawRectangle(cx - 12, cy + 2, 12, 10,
                 Color(r: color.r, g: color.g, b: color.b, a: 180))
    # Phasing forms (middle states)
    for i in 1..2:
      let phaseX = int32(cx - 6 + i * 6)
      let alpha = uint8(120 - i * 40)
      drawCircle(Vector2(x: phaseX.float32, y: (cy - 4).float32), 6,
                Color(r: color.r, g: color.g, b: color.b, a: alpha))
      drawRectangle(phaseX - 6, cy + 2, 12, 10,
                   Color(r: color.r, g: color.g, b: color.b, a: alpha))
    # Arriving form (more solid)
    drawCircle(Vector2(x: (cx + 6).float32, y: (cy - 4).float32), 6, color)
    drawCircleLines(Vector2(x: (cx + 6).float32, y: (cy - 4).float32), 6,
                   Color(r: min(color.r + 80, 255), g: min(color.g + 80, 255), b: min(color.b + 80, 255), a: 255))
    drawRectangle(cx, cy + 2, 12, 10, color)
    drawRectangleLines(Rectangle(x: cx.float32, y: (cy + 2).float32, width: 12, height: 10), 1,
                      Color(r: min(color.r + 80, 255), g: min(color.g + 80, 255), b: min(color.b + 80, 255), a: 255))
    # Phase particles
    for i in 0..6:
      let particleX = int32(cx - 12 + i * 4)
      let particleY = int32(cy + (if i mod 2 == 0: -2 else: 0))
      drawCircle(Vector2(x: particleX.float32, y: particleY.float32), 1,
                Color(r: color.r, g: color.g, b: color.b, a: uint8(100 + i * 20)))
  of puEchoShots:
    # Radio waves/echo visualization
    # Central source
    drawCircle(Vector2(x: cx.float32, y: cy.float32), 4, color)
    drawCircle(Vector2(x: cx.float32, y: cy.float32), 2, Color(r: min(color.r + 120, 255), g: min(color.g + 120, 255), b: min(color.b + 120, 255), a: 255))
    # Expanding echo rings
    for i in 1..5:
      let ringRad = rad * i.float32 / 5.0 + 4
      let alpha = uint8(200 - i * 30)
      let thickness = max(3 - i div 2, 1).float32
      drawRing(Vector2(x: cx.float32, y: cy.float32), ringRad - thickness/2, ringRad + thickness/2, 0, 360, 36,
               Color(r: color.r, g: color.g, b: color.b, a: alpha))
    # Directional wave indicators
    for i in 0..3:
      let angle = i.float32 * PI / 2
      let waveX = cx.float32 + cos(angle) * (rad + 6)
      let waveY = cy.float32 + sin(angle) * (rad + 6)
      drawCircle(Vector2(x: waveX, y: waveY), 2,
                Color(r: min(color.r + 80, 255), g: min(color.g + 80, 255), b: min(color.b + 80, 255), a: 255))

  of puRotatingOrbs, puArcaneBullets, puArcaneAura, puArcaneOrb, puArcaneMastery:
    # Mystical crystal/gem with facets
    # Gem shadow
    drawTriangle(Vector2(x: (cx + 1).float32, y: (cy - 9).float32),
                Vector2(x: (cx - 5).float32, y: (cy - 1).float32),
                Vector2(x: (cx + 7).float32, y: (cy - 1).float32), Color(r: 0, g: 0, b: 0, a: 60))
    # Top pyramid
    drawTriangle(Vector2(x: cx.float32, y: (cy - 11).float32),
                Vector2(x: (cx - 7).float32, y: (cy - 2).float32),
                Vector2(x: (cx + 7).float32, y: (cy - 2).float32), color)
    # Facet highlights on top
    drawLine(cx, cy - 11, cx - 7, cy - 2, Color(r: min(color.r + 100, 255), g: min(color.g + 100, 255), b: min(color.b + 100, 255), a: 200))
    drawLine(cx, cy - 11, cx + 7, cy - 2, Color(r: min(color.r + 60, 255), g: min(color.g + 60, 255), b: min(color.b + 60, 255), a: 150))
    # Bottom pyramid
    drawTriangle(Vector2(x: (cx - 7).float32, y: (cy - 2).float32),
                Vector2(x: (cx + 7).float32, y: (cy - 2).float32),
                Vector2(x: cx.float32, y: (cy + 9).float32),
                Color(r: max(color.r - 40, 0), g: max(color.g - 40, 0), b: max(color.b - 40, 0), a: color.a))
    # Bottom facets
    drawLine(cx - 7, cy - 2, cx, cy + 9, Color(r: max(color.r - 20, 0), g: max(color.g - 20, 0), b: max(color.b - 20, 0), a: color.a))
    drawLine(cx + 7, cy - 2, cx, cy + 9, Color(r: max(color.r - 60, 0), g: max(color.g - 60, 0), b: max(color.b - 60, 0), a: color.a))
    # Center line
    drawLine(Vector2(x: (cx - 7).float32, y: (cy - 2).float32), Vector2(x: (cx + 7).float32, y: (cy - 2).float32), 2.0, Color(r: min(color.r + 80, 255), g: min(color.g + 80, 255), b: min(color.b + 80, 255), a: 255))
    # Inner glow
    drawCircle(Vector2(x: cx.float32, y: (cy - 2).float32), 3,
              Color(r: min(color.r + 150, 255), g: min(color.g + 150, 255), b: min(color.b + 150, 255), a: 200))
    # Magical sparkles around gem
    for i in 0..5:
      let angle = i.float32 * PI / 3
      let sparkleOrbit = rad * 0.88'f32
      let sparkleX = cx.float32 + cos(angle) * sparkleOrbit
      let sparkleY = cy.float32 + sin(angle) * sparkleOrbit
      drawCircle(Vector2(x: sparkleX, y: sparkleY), 1.6'f32,
                Color(r: min(color.r + 120, 255), g: min(color.g + 120, 255), b: min(color.b + 120, 255), a: 180))
  of puParry:
    # Shield with reflection symbol
    # Shield shadow
    drawCircle(Vector2(x: (cx + 1).float32, y: (cy + 1).float32), rad * 0.9, Color(r: 0, g: 0, b: 0, a: 60))
    # Shield main body
    drawCircle(Vector2(x: cx.float32, y: cy.float32), rad * 0.9, Color(r: 40, g: 50, b: 70, a: 255))
    # Shield rim
    drawCircleLines(Vector2(x: cx.float32, y: cy.float32), rad * 0.9, color)
    drawCircleLines(Vector2(x: cx.float32, y: cy.float32), rad * 0.8, Color(r: color.r, g: color.g, b: color.b, a: 200))
    # Shield boss (center)
    drawCircle(Vector2(x: cx.float32, y: cy.float32), 5, color)
    drawCircle(Vector2(x: (cx - 2).float32, y: (cy - 2).float32), 2,
              Color(r: min(color.r + 100, 255), g: min(color.g + 100, 255), b: min(color.b + 100, 255), a: 255))
    # Reflection symbol (bouncing arrows)
    # Incoming arrow
    drawLine(Vector2(x: (cx - 12).float32, y: (cy - 8).float32), Vector2(x: (cx - 6).float32, y: (cy - 2).float32), 3.0, Color(r: 255, g: 100, b: 100, a: 255))
    drawLine(Vector2(x: (cx - 12).float32, y: (cy - 8).float32), Vector2(x: (cx - 10).float32, y: (cy - 10).float32), 2.0, Color(r: 255, g: 100, b: 100, a: 255))
    # Reflected arrow
    drawLine(Vector2(x: (cx + 6).float32, y: (cy + 2).float32), Vector2(x: (cx + 12).float32, y: (cy + 8).float32), 3.0, Color(r: 100, g: 255, b: 255, a: 255))
    drawLine(Vector2(x: (cx + 12).float32, y: (cy + 8).float32), Vector2(x: (cx + 14).float32, y: (cy + 6).float32), 2.0, Color(r: 100, g: 255, b: 255, a: 255))
    drawLine(Vector2(x: (cx + 12).float32, y: (cy + 8).float32), Vector2(x: (cx + 10).float32, y: (cy + 10).float32), 2.0, Color(r: 100, g: 255, b: 255, a: 255))
    # Impact point with sparkle
    drawCircle(Vector2(x: (cx - 3).float32, y: (cy - 3).float32), 3, Color(r: 255, g: 255, b: 100, a: 255))
    for i in 0..3:
      let angle = i.float32 * PI / 2
      let rayX = cx.float32 - 3 + cos(angle) * 5
      let rayY = cy.float32 - 3 + sin(angle) * 5
      drawLine(cx - 3, cy - 3, int32(rayX), int32(rayY), Color(r: 255, g: 255, b: 200, a: 200))

  of puRadialBurst:
    # Circle of bullets radiating outward
    # Center shadow
    drawCircle(Vector2(x: (cx + 1).float32, y: (cy + 1).float32), rad * 0.4, Color(r: 0, g: 0, b: 0, a: 60))
    # Center glow
    drawCircle(Vector2(x: cx.float32, y: cy.float32), rad * 0.4, color)
    drawCircle(Vector2(x: cx.float32, y: cy.float32), rad * 0.3,
              Color(r: min(color.r + 150, 255), g: min(color.g + 150, 255), b: min(color.b + 150, 255), a: 255))
    # Radiating bullets in circle
    for i in 0..7:
      let angle = i.float32 * PI / 4
      let bulletX = cx.float32 + cos(angle) * (rad * 0.8)
      let bulletY = cy.float32 + sin(angle) * (rad * 0.8)
      # Bullet
      drawCircle(Vector2(x: bulletX, y: bulletY), 3, color)
      # Motion trail
      let trailX = cx.float32 + cos(angle) * (rad * 0.6)
      let trailY = cy.float32 + sin(angle) * (rad * 0.6)
      drawLine(Vector2(x: trailX, y: trailY), Vector2(x: bulletX, y: bulletY), 2.0,
              Color(r: color.r, g: color.g, b: color.b, a: 150))
    # Pulse rings
    drawCircleLines(Vector2(x: cx.float32, y: cy.float32), rad * 0.5, color)
    drawCircleLines(Vector2(x: cx.float32, y: cy.float32), rad * 0.7,
                   Color(r: color.r, g: color.g, b: color.b, a: 150))

  of puWallTurrets:
    # Wall with turret on top
    # Wall shadow
    drawRectangle(cx - 8, cy + 2, 16, 10, Color(r: 0, g: 0, b: 0, a: 60))
    # Wall body
    drawRectangle(cx - 10, cy, 20, 10, Color(r: 100, g: 80, b: 60, a: 255))
    drawRectangleLines(Rectangle(x: (cx - 10).float32, y: cy.float32, width: 20, height: 10), 2.0,
                      Color(r: 80, g: 60, b: 40, a: 255))
    # Brick texture
    for i in 0..2:
      drawLine(cx - 10, cy + int32(i * 3 + 3), cx + 10, cy + int32(i * 3 + 3),
              Color(r: 80, g: 60, b: 40, a: 150))
    # Turret base
    drawCircle(Vector2(x: cx.float32, y: (cy - 3).float32), 6, Color(r: 70, g: 70, b: 80, a: 255))
    drawCircleLines(Vector2(x: cx.float32, y: (cy - 3).float32), 6, color)
    # Turret barrel
    drawRectangle(cx - 2, cy - 12, 4, 10, color)
    drawRectangleLines(Rectangle(x: (cx - 2).float32, y: (cy - 12).float32, width: 4, height: 10), 1.5,
                      Color(r: min(color.r + 80, 255), g: min(color.g + 80, 255), b: min(color.b + 80, 255), a: 255))
    # Barrel highlight
    drawRectangle(cx - 1, cy - 12, 2, 10,
                 Color(r: min(color.r + 100, 255), g: min(color.g + 100, 255), b: min(color.b + 100, 255), a: 200))
    # Muzzle flash
    drawCircle(Vector2(x: cx.float32, y: (cy - 13).float32), 3, Color(r: 255, g: 200, b: 100, a: 255))
    for i in 0..3:
      let angle = i.float32 * PI / 2
      let rayX = cx.float32 + cos(angle - PI / 2) * 5
      let rayY = cy.float32 - 13 + sin(angle - PI / 2) * 5
      drawLine(cx, cy - 13, int32(rayX), int32(rayY), Color(r: 255, g: 200, b: 100, a: 200))

  of puHeavyRounds:
    # Cannonball with weight rings
    drawCircle(Vector2(x: (cx + 2).float32, y: (cy + 3).float32), 11, Color(r: 0, g: 0, b: 0, a: 70))
    drawCircle(Vector2(x: cx.float32, y: cy.float32), 11, color)
    drawCircle(Vector2(x: cx.float32, y: cy.float32), 9, Color(r: max(color.r - 35, 0), g: max(color.g - 35, 0), b: max(color.b - 35, 0), a: 255))
    drawCircle(Vector2(x: (cx - 4).float32, y: (cy - 4).float32), 3, Color(r: min(color.r + 110, 255), g: min(color.g + 110, 255), b: min(color.b + 110, 255), a: 200))
    drawCircle(Vector2(x: (cx - 2).float32, y: (cy - 2).float32), 1, Color(r: 255, g: 255, b: 255, a: 180))
    drawCircleLines(Vector2(x: cx.float32, y: cy.float32), 14, Color(r: color.r, g: color.g, b: color.b, a: 100))
    drawCircleLines(Vector2(x: cx.float32, y: cy.float32), 17, Color(r: color.r, g: color.g, b: color.b, a: 50))

  of puPulseArmor:
    # Chest armor with outward pulse wave
    drawRectangle(cx - 12, cy - 9, 5, 8, Color(r: max(color.r - 25, 0), g: max(color.g - 25, 0), b: max(color.b - 25, 0), a: 255))
    drawRectangle(cx + 7, cy - 9, 5, 8, Color(r: max(color.r - 25, 0), g: max(color.g - 25, 0), b: max(color.b - 25, 0), a: 255))
    drawRectangle(cx - 6, cy - 6, 12, 14, Color(r: 0, g: 0, b: 0, a: 65))
    drawRectangle(cx - 7, cy - 8, 14, 14, color)
    drawRectangle(cx - 7, cy - 8, 14, 3, Color(r: min(color.r + 70, 255), g: min(color.g + 70, 255), b: min(color.b + 70, 255), a: 255))
    drawLine(cx, cy - 5, cx - 4, cy + 2, Color(r: max(color.r - 30, 0), g: max(color.g - 30, 0), b: max(color.b - 30, 0), a: 255))
    drawLine(cx, cy - 5, cx + 4, cy + 2, Color(r: max(color.r - 30, 0), g: max(color.g - 30, 0), b: max(color.b - 30, 0), a: 255))
    drawCircle(Vector2(x: cx.float32, y: (cy - 1).float32), 3, Color(r: min(color.r + 160, 255), g: min(color.g + 160, 255), b: min(color.b + 160, 255), a: 255))
    drawCircleLines(Vector2(x: cx.float32, y: (cy - 1).float32), 8, Color(r: color.r, g: color.g, b: color.b, a: 190))
    drawCircleLines(Vector2(x: cx.float32, y: (cy - 1).float32), 13, Color(r: color.r, g: color.g, b: color.b, a: 120))
    drawCircleLines(Vector2(x: cx.float32, y: (cy - 1).float32), 18, Color(r: color.r, g: color.g, b: color.b, a: 55))

  of puFortified:
    # Castle battlement tower
    drawRectangle(cx - 6, cy - 4, 13, 17, Color(r: 0, g: 0, b: 0, a: 70))
    drawRectangle(cx - 7, cy - 6, 14, 16, color)
    drawRectangle(cx - 7, cy - 6, 14, 3, Color(r: min(color.r + 55, 255), g: min(color.g + 55, 255), b: min(color.b + 55, 255), a: 255))
    drawRectangle(cx - 7, cy - 6, 2, 16, Color(r: min(color.r + 35, 255), g: min(color.g + 35, 255), b: min(color.b + 35, 255), a: 180))
    for i in 0..2:
      let bx: int32 = cx - 7 + int32(i * 5)
      drawRectangle(bx, cy - 12, 4, 7, color)
      drawRectangle(bx, cy - 12, 4, 2, Color(r: min(color.r + 55, 255), g: min(color.g + 55, 255), b: min(color.b + 55, 255), a: 255))
    drawRectangle(cx - 3, cy + 2, 6, 8, Color(r: 18, g: 22, b: 32, a: 255))
    drawRectangle(cx - 6, cy - 1, 3, 5, Color(r: 18, g: 22, b: 32, a: 255))
    drawRectangle(cx + 3, cy - 1, 3, 5, Color(r: 18, g: 22, b: 32, a: 255))

  of puSpecialRounds:
    # Bullet with a star insignia on the shell
    drawRectangle(cx - 5, cy - 8, 11, 15, Color(r: 0, g: 0, b: 0, a: 70))
    drawRectangle(cx - 6, cy - 10, 12, 14, color)
    drawRectangle(cx - 6, cy - 10, 12, 3, Color(r: min(color.r + 75, 255), g: min(color.g + 75, 255), b: min(color.b + 75, 255), a: 255))
    drawRectangle(cx - 5, cy - 10, 3, 14, Color(r: min(color.r + 40, 255), g: min(color.g + 40, 255), b: min(color.b + 40, 255), a: 180))
    drawTriangle(Vector2(x: cx.float32, y: (cy - 16).float32),
                Vector2(x: (cx - 6).float32, y: (cy - 10).float32),
                Vector2(x: (cx + 6).float32, y: (cy - 10).float32), color)
    drawLine(cx - 4, cy - 13, cx - 4, cy - 11, Color(r: min(color.r + 100, 255), g: min(color.g + 100, 255), b: min(color.b + 100, 255), a: 200))
    let sCX = cx.float32
    let sCY = float32(cy + 1)
    for i in 0..4:
      let a1 = i.float32 * 2 * PI / 5.0 - PI / 2
      let a2 = (i.float32 + 0.5) * 2 * PI / 5.0 - PI / 2
      let x1 = sCX + cos(a1) * 4
      let y1 = sCY + sin(a1) * 4
      let x2 = sCX + cos(a2) * 2
      let y2 = sCY + sin(a2) * 2
      drawTriangle(Vector2(x: sCX, y: sCY), Vector2(x: x1, y: y1), Vector2(x: x2, y: y2),
                  Color(r: min(color.r + 110, 255), g: min(color.g + 110, 255), b: min(color.b + 110, 255), a: 255))
    drawRectangle(cx - 6, cy + 3, 12, 3, Color(r: min(color.r + 40, 255), g: min(color.g + 40, 255), b: min(color.b + 40, 255), a: 200))

  of puGiantSlayer:
    # Small hero figure targeting a large reticle
    let figX: int32 = cx - 9
    let figHeadY: int32 = cy + 2
    drawCircle(Vector2(x: figX.float32, y: figHeadY.float32), 3, color)
    drawRectangle(figX - 2, figHeadY + 3, 5, 7, color)
    drawRectangle(figX - 2, figHeadY + 3, 5, 2, Color(r: min(color.r + 60, 255), g: min(color.g + 60, 255), b: min(color.b + 60, 255), a: 255))
    let tCX = float32(cx + 7)
    let tCY = float32(cy - 5)
    drawCircleLines(Vector2(x: tCX, y: tCY), 9.5, Color(r: color.r, g: color.g, b: color.b, a: 210))
    drawCircleLines(Vector2(x: tCX, y: tCY), 6.5, Color(r: color.r, g: color.g, b: color.b, a: 150))
    drawLine(int32(tCX - 13), int32(tCY), int32(tCX - 7), int32(tCY), color)
    drawLine(int32(tCX + 7), int32(tCY), int32(tCX + 13), int32(tCY), color)
    drawLine(int32(tCX), int32(tCY - 13), int32(tCX), int32(tCY - 7), color)
    drawLine(int32(tCX), int32(tCY + 7), int32(tCX), int32(tCY + 13), color)
    drawCircle(Vector2(x: tCX, y: tCY), 2,
              Color(r: min(color.r + 160, 255), g: min(color.g + 160, 255), b: min(color.b + 160, 255), a: 255))
    for i in 0..4:
      let t = float32(i) / 5.0
      let dotX = float32(figX) + t * (tCX - float32(figX))
      let dotY = float32(figHeadY) + t * (tCY - float32(figHeadY))
      drawCircle(Vector2(x: dotX, y: dotY), 1.2,
                Color(r: color.r, g: color.g, b: color.b, a: uint8(180 - i * 30)))
  of puCelestialVeil:
    # Glowing veil: outer ring + translucent inner dome + star glint
    let glowColor = Color(r: min(color.r + 40, 255), g: min(color.g + 40, 255), b: 255, a: 180)
    let innerColor = Color(r: color.r, g: color.g, b: min(color.b + 80, 255), a: 80)
    # Soft shadow
    drawCircle(Vector2(x: (cx + 1).float32, y: (cy + 1).float32), rad, Color(r: 0, g: 0, b: 0, a: 60))
    # Inner translucent fill
    drawCircle(Vector2(x: cx.float32, y: cy.float32), rad, innerColor)
    # Outer ring
    drawCircleLines(Vector2(x: cx.float32, y: cy.float32), rad, glowColor)
    drawCircleLines(Vector2(x: cx.float32, y: cy.float32), rad - 2, Color(r: 220, g: 220, b: 255, a: 120))
    # Star glint at top
    let sx = cx.float32
    let sy = (cy.float32 - rad * 0.5)
    let gs = rad * 0.25
    drawLine(Vector2(x: sx - gs, y: sy), Vector2(x: sx + gs, y: sy), 2, Color(r: 255, g: 255, b: 255, a: 220))
    drawLine(Vector2(x: sx, y: sy - gs), Vector2(x: sx, y: sy + gs), 2, Color(r: 255, g: 255, b: 255, a: 220))
    drawLine(Vector2(x: sx - gs * 0.6, y: sy - gs * 0.6), Vector2(x: sx + gs * 0.6, y: sy + gs * 0.6), 1, Color(r: 255, g: 255, b: 255, a: 140))
    drawLine(Vector2(x: sx + gs * 0.6, y: sy - gs * 0.6), Vector2(x: sx - gs * 0.6, y: sy + gs * 0.6), 1, Color(r: 255, g: 255, b: 255, a: 140))

  of puVolatile:
    # Explosion burst: concentric rings + radiating sparks
    drawCircle(Vector2(x: cx.float32, y: cy.float32), rad * 0.55, Color(r: 255, g: 80, b: 20, a: 200))
    drawCircle(Vector2(x: cx.float32, y: cy.float32), rad * 0.35, Color(r: 255, g: 200, b: 60, a: 240))
    drawCircleLines(Vector2(x: cx.float32, y: cy.float32), rad * 0.75, Color(r: color.r, g: color.g, b: color.b, a: 180))
    drawCircleLines(Vector2(x: cx.float32, y: cy.float32), rad, Color(r: color.r, g: color.g, b: color.b, a: 90))
    for i in 0..5:
      let angle = i.float32 * PI / 3.0
      let x1 = cx.float32 + cos(angle) * rad * 0.75
      let y1 = cy.float32 + sin(angle) * rad * 0.75
      let x2 = cx.float32 + cos(angle) * rad * 1.05
      let y2 = cy.float32 + sin(angle) * rad * 1.05
      drawLine(Vector2(x: x1, y: y1), Vector2(x: x2, y: y2), 2, Color(r: 255, g: 180, b: 0, a: 200))

  of puResonance:
    # Concentric waves emanating outward
    drawCircle(Vector2(x: cx.float32, y: cy.float32), rad * 0.28, color)
    for i in 1..3:
      let r = rad * float32(i) * 0.33
      let alpha = uint8(200 - i * 50)
      drawCircleLines(Vector2(x: cx.float32, y: cy.float32), r, Color(r: color.r, g: color.g, b: color.b, a: alpha))
    # Small dots on outermost ring
    for i in 0..5:
      let angle = i.float32 * PI / 3.0
      let dx = cx.float32 + cos(angle) * rad
      let dy = cy.float32 + sin(angle) * rad
      drawCircle(Vector2(x: dx, y: dy), 2, Color(r: color.r, g: color.g, b: color.b, a: 160))

  of puBloodPact:
    # Heart shape with crack/sacrifice line
    let hc = Color(r: 220, g: 30, b: 30, a: 240)
    drawCircle(Vector2(x: (cx - 5).float32, y: (cy - 3).float32), 6, hc)
    drawCircle(Vector2(x: (cx + 5).float32, y: (cy - 3).float32), 6, hc)
    drawTriangle(Vector2(x: (cx - 11).float32, y: (cy - 3).float32),
                 Vector2(x: (cx + 11).float32, y: (cy - 3).float32),
                 Vector2(x: cx.float32, y: (cy + 11).float32), hc)
    # Crack line
    drawLine(Vector2(x: cx.float32, y: (cy - 9).float32), Vector2(x: (cx - 2).float32, y: (cy + 2).float32), 2, Color(r: 255, g: 255, b: 255, a: 200))
    drawLine(Vector2(x: (cx - 2).float32, y: (cy + 2).float32), Vector2(x: (cx + 1).float32, y: (cy + 10).float32), 2, Color(r: 255, g: 255, b: 255, a: 200))

  of puConduit:
    # Flask with elemental dots inside
    let fColor = color
    drawRectangle(cx - 4, cy - 12, 8, 4, fColor)
    drawRectangle(cx - 3, cy - 12, 6, 2, Color(r: min(fColor.r + 60, 255), g: min(fColor.g + 60, 255), b: min(fColor.b + 60, 255), a: 255))
    drawCircle(Vector2(x: cx.float32, y: (cy + 3).float32), 9, Color(r: 0, g: 0, b: 0, a: 60))
    drawCircle(Vector2(x: cx.float32, y: (cy + 2).float32), 9, fColor)
    drawCircle(Vector2(x: cx.float32, y: (cy + 2).float32), 6, Color(r: min(fColor.r + 40, 255), g: min(fColor.g + 100, 255), b: 255, a: 180))
    drawCircle(Vector2(x: (cx - 2).float32, y: (cy + 2).float32), 2, Color(r: 255, g: 80, b: 20, a: 240))
    drawCircle(Vector2(x: (cx + 3).float32, y: (cy + 5).float32), 2, Color(r: 100, g: 220, b: 80, a: 240))
    drawCircle(Vector2(x: (cx - 1).float32, y: (cy + 6).float32), 1.5, Color(r: 80, g: 80, b: 255, a: 240))

  of puAftershock:
    # Spiral / trailing arc backward
    for i in 0..7:
      let t = float32(i) / 8.0
      let angle = t * PI * 1.5 + PI
      let r = rad * 0.3 + rad * 0.7 * t
      let px = cx.float32 + cos(angle) * r
      let py = cy.float32 + sin(angle) * r
      let a = uint8(220 - i * 25)
      drawCircle(Vector2(x: px, y: py), 2.5 - t * 1.0, Color(r: color.r, g: color.g, b: color.b, a: a))
    # Arrow tip at center
    drawCircle(Vector2(x: cx.float32, y: cy.float32), 4, Color(r: min(color.r + 80, 255), g: min(color.g + 80, 255), b: min(color.b + 80, 255), a: 230))

  of puNova:
    # Frozen bullets arranged in a ring, then released
    drawCircleLines(Vector2(x: cx.float32, y: cy.float32), rad, Color(r: 180, g: 220, b: 255, a: 200))
    drawCircleLines(Vector2(x: cx.float32, y: cy.float32), rad * 0.6, Color(r: 150, g: 200, b: 255, a: 120))
    for i in 0..5:
      let angle = i.float32 * PI / 3.0
      let bx = cx.float32 + cos(angle) * rad * 0.85
      let by = cy.float32 + sin(angle) * rad * 0.85
      drawCircle(Vector2(x: bx, y: by), 3.5, Color(r: 200, g: 235, b: 255, a: 230))
      drawCircle(Vector2(x: bx, y: by), 1.5, Color(r: 255, g: 255, b: 255, a: 255))
    # Central pause symbol
    drawRectangle(cx - 4, cy - 6, 3, 12, Color(r: 180, g: 220, b: 255, a: 220))
    drawRectangle(cx + 1, cy - 6, 3, 12, Color(r: 180, g: 220, b: 255, a: 220))

  of puHealPower:
    # Heart with upward surge arrow, amplified healing
    # Outer soft glow ring
    drawCircle(Vector2(x: cx.float32, y: cy.float32), rad + 3, Color(r: 255, g: 80, b: 120, a: 35))
    drawCircle(Vector2(x: cx.float32, y: cy.float32), rad + 1, Color(r: 255, g: 120, b: 150, a: 55))
    # Heart, two lobes + a bottom point
    let lobeR = rad * 0.38
    let lobeOffX = rad * 0.30
    let lobeOffY = rad * 0.12
    let heartColor     = Color(r: min(color.r + 20, 255), g: min(color.g, 100), b: min(color.b, 110), a: color.a)
    let heartHighlight = Color(r: 255, g: 200, b: 210, a: 200)
    let heartShadow    = Color(r: 0, g: 0, b: 0, a: 60)
    # Shadow offset
    drawCircle(Vector2(x: (cx.float32 - lobeOffX + 1), y: (cy.float32 - lobeOffY + 2)), lobeR, heartShadow)
    drawCircle(Vector2(x: (cx.float32 + lobeOffX + 1), y: (cy.float32 - lobeOffY + 2)), lobeR, heartShadow)
    # Lobes
    drawCircle(Vector2(x: (cx.float32 - lobeOffX), y: (cy.float32 - lobeOffY)), lobeR, heartColor)
    drawCircle(Vector2(x: (cx.float32 + lobeOffX), y: (cy.float32 - lobeOffY)), lobeR, heartColor)
    # Bottom triangle to close the heart shape
    let tipY = cy.float32 + rad * 0.72
    drawTriangle(
      Vector2(x: cx.float32 - rad * 0.72, y: cy.float32 - lobeOffY * 0.3),
      Vector2(x: cx.float32 + rad * 0.72, y: cy.float32 - lobeOffY * 0.3),
      Vector2(x: cx.float32,              y: tipY),
      heartColor)
    # Specular highlight on left lobe
    drawCircle(Vector2(x: (cx.float32 - lobeOffX - 2), y: (cy.float32 - lobeOffY - 3)), lobeR * 0.35, heartHighlight)
    # Upward surge arrow in the heart centre
    let arrowColor = Color(r: 255, g: 255, b: 255, a: 230)
    let ax = cx
    let ayBase = cy + 5
    let ayTip  = cy - 7
    # Arrow shaft
    drawRectangle(ax - 1, ayTip, 3, ayBase - ayTip, arrowColor)
    # Arrow head
    drawTriangle(
      Vector2(x: ax.float32,       y: (ayTip - 5).float32),
      Vector2(x: (ax - 5).float32, y: ayTip.float32),
      Vector2(x: (ax + 5).float32, y: ayTip.float32),
      arrowColor)
    # Small plus sparkles at top-right to hint at boosted healing
    let spX = cx + int32(rad * 0.68)
    let spY = cy - int32(rad * 0.62)
    drawLine(spX - 3, spY,     spX + 3, spY,     Color(r: 255, g: 240, b: 80, a: 210))
    drawLine(spX,     spY - 3, spX,     spY + 3, Color(r: 255, g: 240, b: 80, a: 210))

  of puBountiful:
    # Cornucopia icon: a overflowing horn / basket with three gem-dots tumbling out
    let gold   = Color(r: 255, g: 200, b: 50,  a: 255)
    let bright = Color(r: 255, g: 235, b: 130, a: 255)
    let shadow = Color(r: 0,   g: 0,   b: 0,   a: 60)
    # Horn body, thick arc curving from top-left to bottom-right
    drawCircleLines(Vector2(x: (cx - 2).float32, y: cy.float32), rad * 0.85, gold)
    drawCircleLines(Vector2(x: (cx - 2).float32, y: cy.float32), rad * 0.75, Color(r: gold.r, g: gold.g, b: gold.b, a: 160))
    # Opening of the horn (wide end, right side), filled wedge hint
    drawCircle(Vector2(x: (cx + int32(rad * 0.6)).float32, y: (cy - int32(rad * 0.2)).float32), rad * 0.28, Color(r: gold.r, g: gold.g, b: gold.b, a: 90))
    # Three bouncing consumable dots spilling out (health=green, coin=gold, speed=cyan)
    let dotColors = [
      Color(r: 80,  g: 230, b: 80,  a: 255),   # health green
      Color(r: 255, g: 215, b: 0,   a: 255),   # coin gold
      Color(r: 0,   g: 200, b: 255, a: 255),   # speed cyan
    ]
    let dotOffsets: array[3, (float32, float32)] = [
      ( rad * 0.62'f32,  -rad * 0.55'f32),
      ( rad * 0.85'f32,  -rad * 0.20'f32),
      ( rad * 0.70'f32,   rad * 0.18'f32),
    ]
    for k in 0..2:
      let (dx, dy) = dotOffsets[k]
      let dc = dotColors[k]
      drawCircle(Vector2(x: cx.float32 + dx + 1, y: cy.float32 + dy + 1), 4, shadow)
      drawCircle(Vector2(x: cx.float32 + dx,      y: cy.float32 + dy),     4, dc)
      drawCircle(Vector2(x: cx.float32 + dx - 1,  y: cy.float32 + dy - 1), 1.5, bright)
    # Sparkle at the horn tip (top-left)
    let tx = cx - int32(rad * 0.72)
    let ty = cy - int32(rad * 0.30)
    drawLine(tx - 3, ty,     tx + 3, ty,     Color(r: 255, g: 240, b: 100, a: 200))
    drawLine(tx,     ty - 3, tx,     ty + 3, Color(r: 255, g: 240, b: 100, a: 200))

proc drawShopIcon*(x, y, size: int32, itemIndex: int, color: Color) =
  let cx = x + size div 2
  let cy = y + size div 2
  let rad = size.float32 / 2.5

  case itemIndex
  of 0: # Damage + (Sword)
    drawRectangle(cx - 1, cy - 9, 5, 14, Color(r: 0, g: 0, b: 0, a: 60))
    drawRectangle(cx - 2, cy - 11, 4, 14, color)
    drawLine(cx, cy - 11, cx, cy + 3, Color(r: min(color.r + 120, 255), g: min(color.g + 120, 255), b: min(color.b + 120, 255), a: 255))
    drawRectangle(cx - 7, cy + 3, 14, 4, Color(r: min(color.r - 30, 0), g: min(color.g - 30, 0), b: min(color.b - 30, 0), a: color.a))
    drawRectangle(cx - 7, cy + 3, 14, 2, color)
    drawRectangle(cx - 3, cy + 7, 6, 7, Color(r: 100, g: 70, b: 50, a: 255))
    drawRectangle(cx - 3, cy + 8, 6, 1, Color(r: 150, g: 120, b: 90, a: 255))
    drawRectangle(cx - 3, cy + 11, 6, 1, Color(r: 150, g: 120, b: 90, a: 255))
    drawCircle(Vector2(x: cx.float32, y: (cy + 15).float32), 3, Color(r: 120, g: 90, b: 60, a: 255))
    drawLine(cx - 1, cy - 9, cx - 1, cy - 3, Color(r: 255, g: 255, b: 255, a: 180))

  of 1: # Fire Rate + (Lightning)
    for i in 1..3:
      let glowOffset = i * 2
      let alpha = uint8(80 - i * 15)
      drawLine(Vector2(x: (cx + 3 + glowOffset).float32, y: (cy - 12).float32),
              Vector2(x: (cx + 1 + glowOffset).float32, y: (cy - 3).float32), float32(5 - i),
              Color(r: color.r, g: color.g, b: color.b, a: alpha))
    drawLine(Vector2(x: (cx + 3).float32, y: (cy - 12).float32),
            Vector2(x: (cx + 1).float32, y: (cy - 3).float32), 5, color)
    drawLine(Vector2(x: (cx + 1).float32, y: (cy - 3).float32),
            Vector2(x: (cx + 5).float32, y: cy.float32), 5, color)
    drawLine(Vector2(x: (cx + 5).float32, y: cy.float32),
            Vector2(x: (cx - 2).float32, y: (cy + 12).float32), 5, color)
    drawLine(Vector2(x: (cx + 3).float32, y: (cy - 12).float32),
            Vector2(x: (cx + 1).float32, y: (cy - 3).float32), 2, Color(r: 255, g: 255, b: 255, a: 255))
    drawCircle(Vector2(x: (cx + 3).float32, y: (cy - 12).float32), 3, Color(r: 255, g: 255, b: 255, a: 255))
  of 2: # Move Speed + (Running shoe)
    drawRectangle(cx - 7, cy - 2, 14, 10, Color(r: 0, g: 0, b: 0, a: 60))
    drawRectangle(cx - 9, cy - 4, 14, 9, color)
    drawRectangle(cx - 9, cy - 3, 14, 2, Color(r: min(color.r + 80, 255), g: min(color.g + 80, 255), b: min(color.b + 80, 255), a: 255))
    drawTriangle(Vector2(x: (cx + 5).float32, y: cy.float32),
                Vector2(x: (cx + 5).float32, y: (cy - 9).float32),
                Vector2(x: (cx + 14).float32, y: (cy - 5).float32), color)
    drawLine(Vector2(x: (cx + 5).float32, y: (cy - 9).float32), Vector2(x: (cx + 14).float32, y: (cy - 5).float32), 2,
            Color(r: min(color.r + 80, 255), g: min(color.g + 80, 255), b: min(color.b + 80, 255), a: 255))
    for i in 0..2:
      let xOff = int32(-14 - i * 4)
      drawLine(int32(cx + xOff), int32(cy - 2 - i * 2), int32(cx + xOff + 6), int32(cy - 2 - i * 2), Color(r: color.r, g: color.g, b: color.b, a: uint8(120 - i * 30)))

  of 3: # Max Health + (Heart)
    drawCircle(Vector2(x: (cx - 4).float32, y: (cy - 1).float32), 6, Color(r: 0, g: 0, b: 0, a: 60))
    drawCircle(Vector2(x: (cx + 6).float32, y: (cy - 1).float32), 6, Color(r: 0, g: 0, b: 0, a: 60))
    drawCircle(Vector2(x: (cx - 5).float32, y: (cy - 3).float32), 6, color)
    drawCircle(Vector2(x: (cx + 5).float32, y: (cy - 3).float32), 6, color)
    drawTriangle(Vector2(x: (cx - 11).float32, y: (cy - 3).float32),
                Vector2(x: (cx + 11).float32, y: (cy - 3).float32),
                Vector2(x: cx.float32, y: (cy + 12).float32), color)
    drawCircle(Vector2(x: (cx - 7).float32, y: (cy - 6).float32), 3, Color(r: min(color.r + 100, 255), g: min(color.g + 100, 255), b: min(color.b + 100, 255), a: 200))
    drawCircle(Vector2(x: (cx + 3).float32, y: (cy - 6).float32), 2, Color(r: min(color.r + 80, 255), g: min(color.g + 80, 255), b: min(color.b + 80, 255), a: 150))
    drawCircleLines(Vector2(x: cx.float32, y: (cy + 1).float32), rad + 4, Color(r: color.r, g: color.g, b: color.b, a: 60))

  of 4: # Bullet Speed + (Rocket)
    drawTriangle(Vector2(x: (cx + 1).float32, y: (cy - 9).float32),
                Vector2(x: (cx - 3).float32, y: (cy - 1).float32),
                Vector2(x: (cx + 5).float32, y: (cy - 1).float32), Color(r: 0, g: 0, b: 0, a: 60))
    drawTriangle(Vector2(x: cx.float32, y: (cy - 11).float32),
                Vector2(x: (cx - 5).float32, y: (cy - 2).float32),
                Vector2(x: (cx + 5).float32, y: (cy - 2).float32), color)
    drawLine(cx - 2, cy - 8, cx - 2, cy - 3, Color(r: min(color.r + 100, 255), g: min(color.g + 100, 255), b: min(color.b + 100, 255), a: 200))
    drawRectangle(cx - 4, cy - 2, 8, 12, color)
    drawRectangle(cx - 3, cy - 2, 3, 12, Color(r: min(color.r + 60, 255), g: min(color.g + 60, 255), b: min(color.b + 60, 255), a: 255))
    drawCircle(Vector2(x: cx.float32, y: (cy + 2).float32), 3, Color(r: 100, g: 180, b: 255, a: 255))
    drawTriangle(Vector2(x: (cx - 4).float32, y: (cy + 10).float32),
                Vector2(x: (cx - 8).float32, y: (cy + 14).float32),
                Vector2(x: (cx - 4).float32, y: (cy + 12).float32), color)
    drawTriangle(Vector2(x: (cx + 4).float32, y: (cy + 10).float32),
                Vector2(x: (cx + 8).float32, y: (cy + 14).float32),
                Vector2(x: (cx + 4).float32, y: (cy + 12).float32), color)
    drawTriangle(Vector2(x: (cx - 3).float32, y: (cy + 10).float32),
                Vector2(x: (cx + 3).float32, y: (cy + 10).float32),
                Vector2(x: cx.float32, y: (cy + 16).float32), Color(r: 255, g: 150, b: 50, a: 255))
  of 5: # Wall (x5) - Brick wall
    let brickColor = color
    let mortarColor = Color(r: max(color.r - 50, 0), g: max(color.g - 50, 0), b: max(color.b - 50, 0), a: 255)
    drawRectangle(cx - 12, cy - 10, 24, 20, mortarColor)
    for row in 0..2:
      let yPos: int32 = cy - 10 + int32(row * 7)
      let offset: int32 = if row mod 2 == 0: 0 else: 6
      for col in 0..2:
        let xPos: int32 = cx - 12 + offset + int32(col * 12)
        if xPos + 10 <= cx + 12:
          drawRectangle(xPos + 1, yPos + 1, 10, 5, Color(r: 0, g: 0, b: 0, a: 80))
          drawRectangle(xPos, yPos, 10, 5, brickColor)
          drawRectangle(xPos, yPos, 10, 1, Color(r: min(brickColor.r + 60, 255), g: min(brickColor.g + 60, 255), b: min(brickColor.b + 60, 255), a: 255))
          drawRectangle(xPos, yPos, 1, 5, Color(r: min(brickColor.r + 40, 255), g: min(brickColor.g + 40, 255), b: min(brickColor.b + 40, 255), a: 255))
    drawRectangleLines(Rectangle(x: (cx - 12).float32, y: (cy - 10).float32, width: 24, height: 20), 2, color)

  else:
    # Default gear
    drawCircle(Vector2(x: (cx + 1).float32, y: (cy + 1).float32), rad * 0.6, Color(r: 0, g: 0, b: 0, a: 60))
    drawCircle(Vector2(x: cx.float32, y: cy.float32), rad * 0.6, color)
    drawCircleLines(Vector2(x: cx.float32, y: cy.float32), rad * 0.6,
                   Color(r: min(color.r + 80, 255), g: min(color.g + 80, 255), b: min(color.b + 80, 255), a: 255))
    for i in 0..11:
      let angle = i.float32 * PI / 6
      let x1 = cx.float32 + cos(angle) * (rad * 0.6)
      let y1 = cy.float32 + sin(angle) * (rad * 0.6)
      let x2 = cx.float32 + cos(angle) * rad
      let y2 = cy.float32 + sin(angle) * rad
      drawLine(Vector2(x: x1, y: y1), Vector2(x: x2, y: y2), 3, color)
      drawLine(Vector2(x: x1, y: y1), Vector2(x: x2, y: y2), 1,
              Color(r: min(color.r + 100, 255), g: min(color.g + 100, 255), b: min(color.b + 100, 255), a: 255))
    drawCircle(Vector2(x: cx.float32, y: cy.float32), rad * 0.3, Color(r: 30, g: 35, b: 45, a: 255))
    drawCircleLines(Vector2(x: cx.float32, y: cy.float32), rad * 0.3, color)
