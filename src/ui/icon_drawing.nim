## Icon Drawing System - Modern OS Theme
## All icons drawn programmatically using shapes, no emoji

import raylib, types, math

proc drawPowerUpIcon*(x, y, size: int32, powerType: PowerUpType, color: Color) =
  ## Draw power-up icons using geometric shapes
  let cx = x + size div 2
  let cy = y + size div 2
  let rad = size.float32 / 2.5
  
  case powerType
  of puDoubleShot:
    # Two bullets
    drawCircle(Vector2(x: (cx - 8).float32, y: cy.float32), 6, color)
    drawCircle(Vector2(x: (cx + 8).float32, y: cy.float32), 6, color)
    
  of puRotatingShield:
    # Shield outline
    drawCircle(Vector2(x: cx.float32, y: cy.float32), rad, Color(r: 0, g: 0, b: 0, a: 50))
    drawCircleLines(Vector2(x: cx.float32, y: cy.float32), rad, color)
    drawCircleLines(Vector2(x: cx.float32, y: cy.float32), rad - 2, color)
    # Cross pattern
    drawLine(cx - 8, cy, cx + 8, cy, color)
    drawLine(cx, cy - 8, cx, cy + 8, color)
    
  of puDamageZone:
    # Explosion burst
    for i in 0..7:
      let angle = i.float32 * PI / 4
      let x1 = cx.float32 + cos(angle) * (rad * 0.5)
      let y1 = cy.float32 + sin(angle) * (rad * 0.5)
      let x2 = cx.float32 + cos(angle) * rad
      let y2 = cy.float32 + sin(angle) * rad
      drawLine(int32(x1), int32(y1), int32(x2), int32(y2), color)
    drawCircle(Vector2(x: cx.float32, y: cy.float32), rad * 0.3, color)
  of puMagicalBullets:
    # Star shape
    let points = 5
    for i in 0..<points:
      let angle1 = i.float32 * 2 * PI / points.float32 - PI/2
      let angle2 = (i.float32 + 0.5).float32 * 2 * PI / points.float32 - PI/2
      let x1 = cx.float32 + cos(angle1) * rad
      let y1 = cy.float32 + sin(angle1) * rad
      let x2 = cx.float32 + cos(angle2) * (rad * 0.5)
      let y2 = cy.float32 + sin(angle2) * (rad * 0.5)
      drawLine(Vector2(x: x1, y: y1), Vector2(x: x2, y: y2), 2, color)
    
  of puPiercingShots, puAutoShoot:
    # Arrow/Target
    drawLine(cx - 10, cy, cx + 10, cy, color)
    drawLine(cx + 10, cy, cx + 6, cy - 4, color)
    drawLine(cx + 10, cy, cx + 6, cy + 4, color)
    drawCircleLines(Vector2(x: (cx - 8).float32, y: cy.float32), 6, color)
    
  of puMultiShot:
    # Three diverging lines
    drawLine(Vector2(x: (cx - 10).float32, y: (cy + 8).float32), 
               Vector2(x: (cx + 10).float32, y: (cy + 8).float32), 2, color)
    drawLine(Vector2(x: (cx - 10).float32, y: cy.float32), 
               Vector2(x: (cx + 10).float32, y: cy.float32), 2, color)
    drawLine(Vector2(x: (cx - 10).float32, y: (cy - 8).float32), 
               Vector2(x: (cx + 10).float32, y: (cy - 8).float32), 2, color)
    
  of puExplosiveBullets:
    # Bomb shape
    drawCircle(Vector2(x: cx.float32, y: cy.float32), rad * 0.8, color)
    drawRectangle(cx - 2, cy - int32(rad) - 6, 4, 8, color)
    drawCircle(Vector2(x: cx.float32, y: (cy - int32(rad) - 6).float32), 3, color)
    
  of puLifeSteal, puBloodBullets, puBloodOrb, puBloodAura, puBloodMastery:
    # Blood drop
    drawCircle(Vector2(x: cx.float32, y: (cy + 2).float32), rad * 0.6, color)
    drawTriangle(Vector2(x: cx.float32, y: (cy - int32(rad)).float32),
                Vector2(x: (cx - 6).float32, y: (cy + 2).float32),
                Vector2(x: (cx + 6).float32, y: (cy + 2).float32), color)
    
  of puRapidFire, puOvercharge:
    # Lightning bolt
    drawLine(Vector2(x: cx.float32, y: (cy - 10).float32), 
               Vector2(x: (cx + 4).float32, y: (cy - 2).float32), 3, color)
    drawLine(Vector2(x: (cx + 4).float32, y: (cy - 2).float32), 
               Vector2(x: (cx - 2).float32, y: (cy + 2).float32), 3, color)
    drawLine(Vector2(x: (cx - 2).float32, y: (cy + 2).float32), 
               Vector2(x: cx.float32, y: (cy + 10).float32), 3, color)
  of puMaxHealth:
    # Heart shape
    drawCircle(Vector2(x: (cx - 5).float32, y: (cy - 3).float32), 5, color)
    drawCircle(Vector2(x: (cx + 5).float32, y: (cy - 3).float32), 5, color)
    drawTriangle(Vector2(x: (cx - 10).float32, y: (cy - 3).float32),
                Vector2(x: (cx + 10).float32, y: (cy - 3).float32),
                Vector2(x: cx.float32, y: (cy + 10).float32), color)
    
  of puSpeedBoost:
    # Running shoe/wing
    drawRectangle(cx - 8, cy - 4, 12, 8, color)
    drawTriangle(Vector2(x: (cx + 4).float32, y: cy.float32),
                Vector2(x: (cx + 4).float32, y: (cy - 8).float32),
                Vector2(x: (cx + 12).float32, y: (cy - 4).float32), color)
    
  of puBulletDamage, puCriticalHit:
    # Sword
    drawRectangle(cx - 2, cy - 10, 4, 12, color)
    drawRectangle(cx - 6, cy + 2, 12, 3, color)
    drawRectangle(cx - 3, cy + 5, 6, 6, color)
    
  of puBulletSpeed:
    # Rocket
    drawTriangle(Vector2(x: cx.float32, y: (cy - 10).float32),
                Vector2(x: (cx - 4).float32, y: (cy - 2).float32),
                Vector2(x: (cx + 4).float32, y: (cy - 2).float32), color)
    drawRectangle(cx - 3, cy - 2, 6, 10, color)
    drawTriangle(Vector2(x: (cx - 3).float32, y: (cy + 8).float32),
                Vector2(x: (cx - 6).float32, y: (cy + 12).float32),
                Vector2(x: (cx - 3).float32, y: (cy + 10).float32), color)
    drawTriangle(Vector2(x: (cx + 3).float32, y: (cy + 8).float32),
                Vector2(x: (cx + 6).float32, y: (cy + 12).float32),
                Vector2(x: (cx + 3).float32, y: (cy + 10).float32), color)
    
  of puLuckyCoins:
    # Coin stack
    drawCircleLines(Vector2(x: cx.float32, y: (cy - 4).float32), 7, color)
    drawCircleLines(Vector2(x: cx.float32, y: cy.float32), 7, color)
    drawCircleLines(Vector2(x: cx.float32, y: (cy + 4).float32), 7, color)
    drawLine(cx, cy - 4, cx, cy + 4, color)
    
  of puWallMaster:
    # Brick wall
    for i in 0..2:
      drawRectangle(cx - 10, int32(cy - 8 + i * 6), 8, 4, color)
      drawRectangle(cx + 2, int32(cy - 8 + i * 6), 8, 4, color)
  of puBulletSize:
    # Large circle
    drawCircle(Vector2(x: cx.float32, y: cy.float32), rad, color)
    drawCircleLines(Vector2(x: cx.float32, y: cy.float32), rad - 3, color)
    
  of puRegeneration:
    # Plus/cross in circle
    drawCircleLines(Vector2(x: cx.float32, y: cy.float32), rad, color)
    drawLine(Vector2(x: (cx - 8).float32, y: cy.float32), 
               Vector2(x: (cx + 8).float32, y: cy.float32), 3, color)
    drawLine(Vector2(x: cx.float32, y: (cy - 8).float32), 
               Vector2(x: cx.float32, y: (cy + 8).float32), 3, color)
    
  of puDodgeChance:
    # Wind/speed lines
    for i in 0..2:
      let yy = cy - 6 + i * 6
      drawLine(Vector2(x: (cx - 10).float32, y: yy.float32), 
                 Vector2(x: (cx + 6).float32, y: yy.float32), 2, color)
      drawLine(Vector2(x: (cx + 6).float32, y: yy.float32), 
                 Vector2(x: (cx + 2).float32, y: (yy - 3).float32), 2, color)
    
  of puBulletRicochet:
    # Bouncing arrow
    drawLine(Vector2(x: (cx - 10).float32, y: (cy + 6).float32), 
               Vector2(x: (cx - 2).float32, y: (cy - 6).float32), 2, color)
    drawLine(Vector2(x: (cx - 2).float32, y: (cy - 6).float32), 
               Vector2(x: (cx + 10).float32, y: (cy + 6).float32), 2, color)
    # Arrowheads
    drawLine(cx + 10, cy + 6, cx + 6, cy + 4, color)
    drawLine(cx + 10, cy + 6, cx + 8, cy + 10, color)
    
  of puSlowField, puFrostShots, puFrostOrb, puFrostMastery:
    # Snowflake
    drawLine(cx, cy - 10, cx, cy + 10, color)
    drawLine(cx - 10, cy, cx + 10, cy, color)
    drawLine(cx - 7, cy - 7, cx + 7, cy + 7, color)
    drawLine(cx - 7, cy + 7, cx + 7, cy - 7, color)
    
  of puRage, puBerserker:
    # Angry face/X eyes
    drawCircleLines(Vector2(x: cx.float32, y: cy.float32), rad, color)
    drawLine(Vector2(x: (cx - 6).float32, y: (cy - 4).float32), 
               Vector2(x: (cx - 2).float32, y: (cy - 1).float32), 2, color)
    drawLine(Vector2(x: (cx - 2).float32, y: (cy - 4).float32), 
               Vector2(x: (cx - 6).float32, y: (cy - 1).float32), 2, color)
    drawLine(Vector2(x: (cx + 2).float32, y: (cy - 4).float32), 
               Vector2(x: (cx + 6).float32, y: (cy - 1).float32), 2, color)
    drawLine(Vector2(x: (cx + 6).float32, y: (cy - 4).float32), 
               Vector2(x: (cx + 2).float32, y: (cy - 1).float32), 2, color)
    drawLine(Vector2(x: (cx - 6).float32, y: (cy + 5).float32), 
               Vector2(x: (cx + 6).float32, y: (cy + 5).float32), 3, color)
  of puThorns:
    # Rose with thorns
    drawCircle(Vector2(x: cx.float32, y: (cy - 6).float32), 5, color)
    drawLine(Vector2(x: cx.float32, y: (cy - 1).float32), 
               Vector2(x: cx.float32, y: (cy + 10).float32), 2, color)
    drawLine(Vector2(x: cx.float32, y: (cy + 2).float32), 
               Vector2(x: (cx - 4).float32, y: cy.float32), 2, color)
    drawLine(Vector2(x: cx.float32, y: (cy + 6).float32), 
               Vector2(x: (cx + 4).float32, y: (cy + 4).float32), 2, color)
    
  of puBulletSplit:
    # Trident
    drawLine(Vector2(x: cx.float32, y: (cy - 10).float32), 
               Vector2(x: cx.float32, y: (cy + 10).float32), 2, color)
    drawLine(Vector2(x: (cx - 5).float32, y: (cy - 10).float32), 
               Vector2(x: (cx - 5).float32, y: (cy - 2).float32), 2, color)
    drawLine(Vector2(x: (cx + 5).float32, y: (cy - 10).float32), 
               Vector2(x: (cx + 5).float32, y: (cy - 2).float32), 2, color)
    
  of puChainLightning, puLightningAura, puLightningOrb, puLightningMastery:
    # Lightning bolt
    drawLine(Vector2(x: (cx + 2).float32, y: (cy - 10).float32), 
               Vector2(x: cx.float32, y: (cy - 2).float32), 3, color)
    drawLine(Vector2(x: cx.float32, y: (cy - 2).float32), 
               Vector2(x: (cx + 4).float32, y: cy.float32), 3, color)
    drawLine(Vector2(x: (cx + 4).float32, y: cy.float32), 
               Vector2(x: (cx - 2).float32, y: (cy + 10).float32), 3, color)
    
  of puPoisonShot, puPoisonAura, puPoisonOrb, puPoisonMastery:
    # Skull
    drawCircle(Vector2(x: cx.float32, y: (cy - 2).float32), 8, color)
    drawCircle(Vector2(x: (cx - 3).float32, y: (cy - 4).float32), 2, Black)
    drawCircle(Vector2(x: (cx + 3).float32, y: (cy - 4).float32), 2, Black)
    drawRectangle(cx - 4, cy + 2, 8, 6, color)
    
  of puFireBullets, puFireAura, puFireOrb, puFireMastery:
    # Flame
    drawTriangle(Vector2(x: cx.float32, y: (cy - 10).float32),
                Vector2(x: (cx - 6).float32, y: (cy + 8).float32),
                Vector2(x: (cx + 6).float32, y: (cy + 8).float32), color)
    drawTriangle(Vector2(x: cx.float32, y: (cy - 6).float32),
                Vector2(x: (cx - 3).float32, y: (cy + 4).float32),
                Vector2(x: (cx + 3).float32, y: (cy + 4).float32), 
                Color(r: 255, g: 255, b: 200, a: 200))
  of puWindBullets, puWindAura, puWindOrb, puWindMastery:
    # Wind swirl
    for i in 0..2:
      let offset = i * 4 - 4
      drawCircleSector(Vector2(x: (cx + offset).float32, y: cy.float32), 
                      rad * 0.6, 0, 180, 12, color)
    
  of puTimeWarp:
    # Clock
    drawCircleLines(Vector2(x: cx.float32, y: cy.float32), rad, color)
    drawLine(Vector2(x: cx.float32, y: cy.float32), 
               Vector2(x: cx.float32, y: (cy - 8).float32), 2, color)
    drawLine(Vector2(x: cx.float32, y: cy.float32), 
               Vector2(x: (cx + 6).float32, y: cy.float32), 2, color)
    
  of puGravityWell:
    # Spiral/vortex
    for i in 0..5:
      let angle = i.float32 * PI / 3
      let r = rad * (1.0 - i.float32 / 6.0)
      drawCircleSector(Vector2(x: cx.float32, y: cy.float32), r, 
                      angle * 180 / PI, (angle + PI/3) * 180 / PI, 8, color)
    
  of puPhaseShift:
    # Ghost/transparent
    drawCircle(Vector2(x: cx.float32, y: (cy - 4).float32), 6, 
              Color(r: color.r, g: color.g, b: color.b, a: 100))
    drawCircleLines(Vector2(x: cx.float32, y: (cy - 4).float32), 6, color)
    drawRectangle(cx - 6, cy + 2, 12, 8, 
                 Color(r: color.r, g: color.g, b: color.b, a: 100))
    drawRectangleLines(Rectangle(x: (cx - 6).float32, y: (cy + 2).float32, 
                                 width: 12, height: 8), 1, color)
    
  of puEchoShots:
    # Radio waves
    for i in 1..3:
      drawCircleLines(Vector2(x: cx.float32, y: cy.float32), 
                     rad * i.float32 / 3.0, color)
    drawCircle(Vector2(x: cx.float32, y: cy.float32), 3, color)
    
  of puRotatingOrbs, puArcaneBullets, puArcaneAura, puArcaneOrb, puArcaneMastery:
    # Crystal/gem
    drawTriangle(Vector2(x: cx.float32, y: (cy - 10).float32),
                Vector2(x: (cx - 6).float32, y: (cy - 2).float32),
                Vector2(x: (cx + 6).float32, y: (cy - 2).float32), color)
    drawTriangle(Vector2(x: (cx - 6).float32, y: (cy - 2).float32),
                Vector2(x: (cx + 6).float32, y: (cy - 2).float32),
                Vector2(x: cx.float32, y: (cy + 8).float32), color)
    drawLine(cx - 6, cy - 2, cx + 6, cy - 2, color)
  of puParry:
    # Shield with reflection
    drawCircle(Vector2(x: cx.float32, y: cy.float32), rad * 0.8, Color(r: 0, g: 0, b: 0, a: 50))
    drawCircleLines(Vector2(x: cx.float32, y: cy.float32), rad * 0.8, color)
    drawLine(Vector2(x: (cx - 6).float32, y: (cy - 6).float32), 
               Vector2(x: (cx + 6).float32, y: (cy + 6).float32), 2, color)
    
  else:
    # Default: Gear icon for unspecified types
    drawCircleLines(Vector2(x: cx.float32, y: cy.float32), rad * 0.6, color)
    for i in 0..7:
      let angle = i.float32 * PI / 4
      let x1 = cx.float32 + cos(angle) * (rad * 0.6)
      let y1 = cy.float32 + sin(angle) * (rad * 0.6)
      let x2 = cx.float32 + cos(angle) * rad
      let y2 = cy.float32 + sin(angle) * rad
      drawLine(Vector2(x: x1, y: y1), Vector2(x: x2, y: y2), 2, color)
    drawCircle(Vector2(x: cx.float32, y: cy.float32), rad * 0.3, color)

proc drawShopIcon*(x, y, size: int32, itemIndex: int, color: Color) =
  ## Draw shop upgrade icons
  let cx = x + size div 2
  let cy = y + size div 2
  let rad = size.float32 / 2.5
  
  case itemIndex
  of 0: # Damage +
    # Sword
    drawRectangle(cx - 2, cy - 10, 4, 12, color)
    drawRectangle(cx - 6, cy + 2, 12, 3, color)
    drawRectangle(cx - 3, cy + 5, 6, 6, color)
    
  of 1: # Fire Rate +
    # Lightning bolt
    drawLine(Vector2(x: (cx + 2).float32, y: (cy - 10).float32), 
               Vector2(x: cx.float32, y: (cy - 2).float32), 3, color)
    drawLine(Vector2(x: cx.float32, y: (cy - 2).float32), 
               Vector2(x: (cx + 4).float32, y: cy.float32), 3, color)
    drawLine(Vector2(x: (cx + 4).float32, y: cy.float32), 
               Vector2(x: (cx - 2).float32, y: (cy + 10).float32), 3, color)
    
  of 2: # Move Speed +
    # Running shoe
    drawRectangle(cx - 8, cy - 4, 12, 8, color)
    drawTriangle(Vector2(x: (cx + 4).float32, y: cy.float32),
                Vector2(x: (cx + 4).float32, y: (cy - 8).float32),
                Vector2(x: (cx + 12).float32, y: (cy - 4).float32), color)
    
  of 3: # Max Health +
    # Heart
    drawCircle(Vector2(x: (cx - 5).float32, y: (cy - 3).float32), 5, color)
    drawCircle(Vector2(x: (cx + 5).float32, y: (cy - 3).float32), 5, color)
    drawTriangle(Vector2(x: (cx - 10).float32, y: (cy - 3).float32),
                Vector2(x: (cx + 10).float32, y: (cy - 3).float32),
                Vector2(x: cx.float32, y: (cy + 10).float32), color)
    
  of 4: # Bullet Speed +
    # Rocket
    drawTriangle(Vector2(x: cx.float32, y: (cy - 10).float32),
                Vector2(x: (cx - 4).float32, y: (cy - 2).float32),
                Vector2(x: (cx + 4).float32, y: (cy - 2).float32), color)
    drawRectangle(cx - 3, cy - 2, 6, 10, color)
    
  of 5: # Wall (x5)
    # Brick wall
    for i in 0..2:
      drawRectangle(cx - 10, int32(cy - 8 + i * 6), 8, 4, color)
      drawRectangle(cx + 2, int32(cy - 8 + i * 6), 8, 4, color)
    
  else:
    # Default
    drawCircleLines(Vector2(x: cx.float32, y: cy.float32), rad, color)
