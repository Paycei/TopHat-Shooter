## Icon Drawing System - Modern OS Theme with Enhanced Detail
## All icons drawn programmatically using shapes with depth and polish

import raylib, ../types, math

proc drawPowerUpIcon*(x, y, size: int32, powerType: PowerUpType, color: Color) =
  ## Draw power-up icons using geometric shapes with enhanced detail
  let cx = x + size div 2
  let cy = y + size div 2
  let rad = size.float32 / 2.5
  
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
    
  of puDamageZone:
    # Explosive burst with energy rings
    # Central core
    drawCircle(Vector2(x: cx.float32, y: cy.float32), rad * 0.4, Color(r: color.r, g: color.g, b: color.b, a: 180))
    drawCircle(Vector2(x: cx.float32, y: cy.float32), rad * 0.2, Color(r: min(color.r + 80, 255), g: min(color.g + 80, 255), b: min(color.b + 80, 255), a: 255))
    # Energy spikes
    for i in 0..11:
      let angle = i.float32 * PI / 6
      let length = if i mod 2 == 0: rad else: rad * 0.7
      let x1 = cx.float32 + cos(angle) * (rad * 0.4)
      let y1 = cy.float32 + sin(angle) * (rad * 0.4)
      let x2 = cx.float32 + cos(angle) * length
      let y2 = cy.float32 + sin(angle) * length
      let thickness = if i mod 2 == 0: 3.0 else: 2.0
      drawLine(Vector2(x: x1, y: y1), Vector2(x: x2, y: y2), thickness, color)
    # Concentric rings
    drawCircleLines(Vector2(x: cx.float32, y: cy.float32), rad * 0.6, Color(r: color.r, g: color.g, b: color.b, a: 120))
    drawCircleLines(Vector2(x: cx.float32, y: cy.float32), rad * 0.8, Color(r: color.r, g: color.g, b: color.b, a: 80))
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
    
  of puPiercingShots, puAutoShoot:
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
    drawRectangle(cx - 2, cy - int32(rad) - 8, 4, 10, Color(r: 80, g: 60, b: 40, a: 255))
    # Spark on fuse
    drawCircle(Vector2(x: cx.float32, y: (cy - int32(rad) - 8).float32), 4, Color(r: 255, g: 200, b: 50, a: 255))
    drawCircle(Vector2(x: cx.float32, y: (cy - int32(rad) - 8).float32), 2, Color(r: 255, g: 255, b: 200, a: 255))
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
  of puBulletSize:
    # Large expanding bullet with rings
    # Outer rings showing growth
    for i in countdown(3, 1):
      let ringRad = rad * (0.5 + i.float32 * 0.2)
      drawCircleLines(Vector2(x: cx.float32, y: cy.float32), ringRad, 
                     Color(r: color.r, g: color.g, b: color.b, a: uint8(80 - i * 20)))
    # Main bullet
    drawCircle(Vector2(x: (cx + 1).float32, y: (cy + 1).float32), rad * 0.7, Color(r: 0, g: 0, b: 0, a: 60))
    drawCircle(Vector2(x: cx.float32, y: cy.float32), rad * 0.7, color)
    # Highlight
    drawCircle(Vector2(x: (cx - 3).float32, y: (cy - 3).float32), rad * 0.3, 
              Color(r: min(color.r + 120, 255), g: min(color.g + 120, 255), b: min(color.b + 120, 255), a: 255))
    # Inner core
    drawCircle(Vector2(x: cx.float32, y: cy.float32), rad * 0.4, 
              Color(r: min(color.r + 80, 255), g: min(color.g + 80, 255), b: min(color.b + 80, 255), a: 200))
    
  of puRegeneration:
    # Medical cross with pulse
    # Pulse rings
    for i in 1..3:
      drawCircleLines(Vector2(x: cx.float32, y: cy.float32), rad + i.float32 * 3, 
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
      let sparkleX = cx.float32 + cos(angle) * (rad + 8)
      let sparkleY = cy.float32 + sin(angle) * (rad + 8)
      drawCircle(Vector2(x: sparkleX, y: sparkleY), 2, 
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
    
  else:
    # Default: Enhanced gear icon for unspecified types
    # Gear body shadow
    drawCircle(Vector2(x: (cx + 1).float32, y: (cy + 1).float32), rad * 0.6, Color(r: 0, g: 0, b: 0, a: 60))
    # Gear center
    drawCircle(Vector2(x: cx.float32, y: cy.float32), rad * 0.6, color)
    drawCircleLines(Vector2(x: cx.float32, y: cy.float32), rad * 0.6, 
                   Color(r: min(color.r + 80, 255), g: min(color.g + 80, 255), b: min(color.b + 80, 255), a: 255))
    # Gear teeth
    for i in 0..11:
      let angle = i.float32 * PI / 6
      let x1 = cx.float32 + cos(angle) * (rad * 0.6)
      let y1 = cy.float32 + sin(angle) * (rad * 0.6)
      let x2 = cx.float32 + cos(angle) * rad
      let y2 = cy.float32 + sin(angle) * rad
      # Tooth
      drawLine(Vector2(x: x1, y: y1), Vector2(x: x2, y: y2), 3, color)
      # Tooth highlight
      drawLine(Vector2(x: x1, y: y1), Vector2(x: x2, y: y2), 1, 
              Color(r: min(color.r + 100, 255), g: min(color.g + 100, 255), b: min(color.b + 100, 255), a: 255))
    # Inner hole
    drawCircle(Vector2(x: cx.float32, y: cy.float32), rad * 0.3, Color(r: 30, g: 35, b: 45, a: 255))
    drawCircleLines(Vector2(x: cx.float32, y: cy.float32), rad * 0.3, color)

proc drawShopIcon*(x, y, size: int32, itemIndex: int, color: Color) =
  ## Draw shop upgrade icons with enhanced detail
  let cx = x + size div 2
  let cy = y + size div 2
  let rad = size.float32 / 2.5
  
  case itemIndex
  of 0: # Damage + (Sword)
    # Enhanced sword from above
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
