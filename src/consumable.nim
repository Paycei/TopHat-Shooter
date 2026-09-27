import raylib, random, math
import particle_types, types, utils

# Icon drawing: simple, clear glyphs so each pickup reads at a glance.

proc drawHealthIcon(cx, cy: int32, size: float32) =
  ## Simple plus/cross symbol (medical cross)
  let white = Color(r: 255, g: 255, b: 255, a: 255)
  let thickness: int32 = 3

  # Vertical bar
  drawRectangle(cx - 1, cy - 5, thickness, 10, white)

  # Horizontal bar
  drawRectangle(cx - 5, cy - 1, 10, thickness, white)

proc drawCoinIcon(cx, cy: int32, size: float32) =
  ## Simple $ symbol
  let gold = Color(r: 255, g: 215, b: 0, a: 255)

  # Draw $ character large and bold
  drawText("$", cx - 4, cy - 6, 14, Color(r: 50, g: 40, b: 0, a: 255))  # Shadow
  drawText("$", cx - 5, cy - 7, 14, gold)

proc drawSpeedIcon(cx, cy: int32, size: float32) =
  ## Three horizontal arrow lines (motion lines)
  let cyan = Color(r: 0, g: 255, b: 255, a: 255)

  # Three motion lines of increasing length
  for i in 0..2:
    let yPos: int32 = cy - 3 + (i * 3).int32
    let length: int32 = (8 + i * 2).int32
    # Arrow line
    drawRectangle(cx - 6, yPos, length, 2, cyan)
    # Arrow head
    drawTriangle(
      Vector2(x: (cx - 6 + length).float32, y: (yPos - 1).float32),
      Vector2(x: (cx - 6 + length).float32, y: (yPos + 3).float32),
      Vector2(x: (cx - 6 + length + 3).float32, y: (yPos + 1).float32),
      cyan
    )

proc drawInvincibilityIcon(cx, cy: int32, size: float32) =
  ## Simple star shape
  let magenta = Color(r: 255, g: 0, b: 255, a: 255)

  # Draw 8-pointed star with lines
  for i in 0..7:
    let angle = i.float32 * PI / 4.0
    let innerRadius = 2.0
    let outerRadius = 7.0

    let x1 = cx.float32 + cos(angle) * innerRadius
    let y1 = cy.float32 + sin(angle) * innerRadius
    let x2 = cx.float32 + cos(angle) * outerRadius
    let y2 = cy.float32 + sin(angle) * outerRadius

    drawLine(Vector2(x: x1, y: y1), Vector2(x: x2, y: y2), 3.0, magenta)

  # Center circle
  drawCircle(Vector2(x: cx.float32, y: cy.float32), 3, magenta)

proc drawFireRateIcon(cx, cy: int32, size: float32) =
  ## Simple lightning bolt (zigzag)
  let orange = Color(r: 255, g: 165, b: 0, a: 255)

  # Bold lightning bolt shape
  let points = [
    Vector2(x: (cx + 2).float32, y: (cy - 7).float32),
    Vector2(x: (cx - 1).float32, y: (cy - 1).float32),
    Vector2(x: (cx + 2).float32, y: (cy - 1).float32),
    Vector2(x: (cx - 2).float32, y: (cy + 7).float32),
    Vector2(x: (cx + 1).float32, y: (cy + 1).float32),
    Vector2(x: (cx - 2).float32, y: (cy + 1).float32)
  ]

  # Draw filled polygon
  for i in 0..4:
    drawTriangle(
      Vector2(x: cx.float32, y: cy.float32),
      points[i],
      points[(i + 1) mod 6],
      orange
    )

  # Outline for clarity
  for i in 0..5:
    drawLine(points[i], points[(i + 1) mod 6], 2.0, Color(r: 200, g: 130, b: 0, a: 255))

proc drawMagnetIcon(cx, cy: int32, size: float32) =
  ## Horseshoe magnet - U shape with colored ends
  let purple = Color(r: 147, g: 51, b: 234, a: 255)
  let red = Color(r: 255, g: 0, b: 0, a: 255)
  let blue = Color(r: 0, g: 100, b: 255, a: 255)

  # Left pole (red - north)
  drawRectangle(cx - 6, cy - 5, 3, 8, red)

  # Right pole (blue - south)
  drawRectangle(cx + 3, cy - 5, 3, 8, blue)

  # Bottom connector
  drawRectangle(cx - 6, cy + 3, 12, 3, purple)

proc drawShieldIcon(cx, cy: int32, size: float32) =
  ## Classic shield shape
  let cyan = Color(r: 0, g: 255, b: 255, a: 255)
  let dark = Color(r: 0, g: 150, b: 150, a: 255)

  # Shield outline shape using triangles
  # Top half
  drawTriangle(
    Vector2(x: cx.float32, y: (cy - 7).float32),
    Vector2(x: (cx - 6).float32, y: cy.float32),
    Vector2(x: (cx + 6).float32, y: cy.float32),
    dark
  )

  # Bottom point
  drawTriangle(
    Vector2(x: (cx - 6).float32, y: cy.float32),
    Vector2(x: (cx + 6).float32, y: cy.float32),
    Vector2(x: cx.float32, y: (cy + 7).float32),
    dark
  )

  # Shield border (outline)
  drawLine(Vector2(x: cx.float32, y: (cy - 7).float32),
           Vector2(x: (cx - 6).float32, y: cy.float32), 2.0, cyan)
  drawLine(Vector2(x: cx.float32, y: (cy - 7).float32),
           Vector2(x: (cx + 6).float32, y: cy.float32), 2.0, cyan)
  drawLine(Vector2(x: (cx - 6).float32, y: cy.float32),
           Vector2(x: cx.float32, y: (cy + 7).float32), 2.0, cyan)
  drawLine(Vector2(x: (cx + 6).float32, y: cy.float32),
           Vector2(x: cx.float32, y: (cy + 7).float32), 2.0, cyan)

  # Center cross for detail
  drawLine(Vector2(x: cx.float32, y: (cy - 3).float32),
           Vector2(x: cx.float32, y: (cy + 3).float32), 2.0, cyan)
  drawLine(Vector2(x: (cx - 3).float32, y: cy.float32),
           Vector2(x: (cx + 3).float32, y: cy.float32), 2.0, cyan)

proc drawDoubleCoinIcon(cx, cy: int32, size: float32) =
  ## Two coins stacked with "2x" text
  let gold = Color(r: 255, g: 223, b: 0, a: 255)
  let darkGold = Color(r: 200, g: 170, b: 0, a: 255)

  # Back coin (offset)
  drawCircle(Vector2(x: (cx + 2).float32, y: (cy + 2).float32), 5, darkGold)
  drawCircleLines(Vector2(x: (cx + 2).float32, y: (cy + 2).float32), 5,
                  Color(r: 150, g: 120, b: 0, a: 255))

  # Front coin
  drawCircle(Vector2(x: (cx - 2).float32, y: (cy - 2).float32), 5, gold)
  drawCircleLines(Vector2(x: (cx - 2).float32, y: (cy - 2).float32), 5, darkGold)

  # "2x" text
  drawText("2x", cx - 5, cy - 4, 8, Color(r: 50, g: 40, b: 0, a: 255))

proc drawDamageBoostIcon(cx, cy: int32, size: float32) =
  ## Simple upward arrow with exclamation
  let redOrange = Color(r: 255, g: 69, b: 0, a: 255)

  # Arrow shaft
  drawRectangle(cx - 1, cy - 2, 3, 8, redOrange)

  # Arrow head (triangle)
  drawTriangle(
    Vector2(x: cx.float32, y: (cy - 7).float32),
    Vector2(x: (cx - 4).float32, y: (cy - 2).float32),
    Vector2(x: (cx + 4).float32, y: (cy - 2).float32),
    redOrange
  )

  # Exclamation mark inside
  drawRectangle(cx - 1, cy - 1, 2, 4, Color(r: 255, g: 255, b: 255, a: 255))
  drawRectangle(cx - 1, cy + 4, 2, 2, Color(r: 255, g: 255, b: 255, a: 255))

proc drawLifestealIcon(cx, cy: int32, size: float32) =
  ## Heart with droplet inside
  let darkRed = Color(r: 139, g: 0, b: 0, a: 255)
  let brightRed = Color(r: 255, g: 50, b: 50, a: 255)

  # Simple heart shape using two circles and a triangle
  # Left circle
  drawCircle(Vector2(x: (cx - 3).float32, y: (cy - 2).float32), 4, darkRed)
  # Right circle
  drawCircle(Vector2(x: (cx + 3).float32, y: (cy - 2).float32), 4, darkRed)
  # Bottom triangle
  drawTriangle(
    Vector2(x: (cx - 6).float32, y: (cy - 2).float32),
    Vector2(x: (cx + 6).float32, y: (cy - 2).float32),
    Vector2(x: cx.float32, y: (cy + 7).float32),
    darkRed
  )

  # Small droplet inside heart
  drawCircle(Vector2(x: cx.float32, y: cy.float32), 2, brightRed)
  drawTriangle(
    Vector2(x: cx.float32, y: (cy - 3).float32),
    Vector2(x: (cx - 2).float32, y: cy.float32),
    Vector2(x: (cx + 2).float32, y: cy.float32),
    brightRed
  )

proc drawConsumableIcon*(x, y, radius: float32, cType: ConsumableType, pulse: float32) =
  ## Central icon dispatcher with pulse animation
  let size = radius * pulse
  let cx = x.int32
  let cy = y.int32

  case cType
  of ctHealth:
    drawHealthIcon(cx, cy, size)
  of ctCoin:
    drawCoinIcon(cx, cy, size)
  of ctSpeed:
    drawSpeedIcon(cx, cy, size)
  of ctInvincibility:
    drawInvincibilityIcon(cx, cy, size)
  of ctFireRate:
    drawFireRateIcon(cx, cy, size)
  of ctMagnet:
    drawMagnetIcon(cx, cy, size)
  of ctShieldBoost:
    drawShieldIcon(cx, cy, size)
  of ctDoubleCoin:
    drawDoubleCoinIcon(cx, cy, size)
  of ctDamageBoost:
    drawDamageBoostIcon(cx, cy, size)
  of ctLifesteal:
    drawLifestealIcon(cx, cy, size)

proc newConsumable*(x, y: float32, difficulty: float32): Consumable =
  # Weighted selection based on difficulty
  let roll = rand(100)
  var cType: ConsumableType

  if roll < 30:        # Health - common (30%)
    cType = ctHealth
  elif roll < 50:      # Coin - common (20%)
    cType = ctCoin
  elif roll < 63:      # Speed - uncommon (13%)
    cType = ctSpeed
  elif roll < 73:      # Fire Rate - uncommon (10%)
    cType = ctFireRate
  elif roll < 81:      # Shield Boost - uncommon (8%)
    cType = ctShieldBoost
  elif roll < 88:      # Magnet - rare (7%)
    cType = ctMagnet
  elif roll < 93:      # Damage Boost - rare (5%)
    cType = ctDamageBoost
  elif roll < 97:      # Invincibility - epic (4%)
    cType = ctInvincibility
  elif roll < 99:      # Double Coin - epic (2%)
    cType = ctDoubleCoin
  else:                # Lifesteal - legendary (1%)
    cType = ctLifesteal

  result = Consumable(
    pos: newVector2f(x, y),
    radius: 8,
    consumableType: cType,
    lifetime: 15.0
  )

proc newSpecificConsumable*(x, y: float32, cType: ConsumableType): Consumable =
  ## Create a consumable of a specific type (for boss drops, etc.)
  result = Consumable(
    pos: newVector2f(x, y),
    radius: 8,
    consumableType: cType,
    lifetime: 15.0
  )

proc updateConsumable*(consumable: Consumable, dt: float32): bool =
  consumable.lifetime -= dt
  return consumable.lifetime > 0

proc getConsumableColor(cType: ConsumableType): Color =
  ## Get the background color for each consumable type
  case cType
  of ctHealth: Color(r: 50, g: 255, b: 50, a: 255)        # Bright green
  of ctCoin: Color(r: 255, g: 215, b: 0, a: 255)          # Gold
  of ctSpeed: Cyan                                          # Cyan
  of ctInvincibility: Color(r: 255, g: 0, b: 255, a: 255) # Magenta
  of ctFireRate: Color(r: 255, g: 165, b: 0, a: 255)      # Orange
  of ctMagnet: Color(r: 147, g: 51, b: 234, a: 255)       # Purple
  of ctShieldBoost: Cyan                                    # Cyan
  of ctDoubleCoin: Color(r: 255, g: 223, b: 0, a: 255)    # Bright gold
  of ctDamageBoost: Color(r: 255, g: 69, b: 0, a: 255)    # Red-orange
  of ctLifesteal: Color(r: 139, g: 0, b: 0, a: 255)       # Dark red

proc drawConsumable*(consumable: Consumable) =
  let t = getTime()
  let pulse = 1.0 + 0.15 * sin(t * 6.0)
  let size = consumable.radius * pulse

  # Per-type aura color
  let auraColor = case consumable.consumableType
    of ctHealth:       Color(r: 50,  g: 255, b: 80,  a: 50)
    of ctCoin:         Color(r: 255, g: 215, b: 0,   a: 50)
    of ctSpeed:        Color(r: 0,   g: 220, b: 255, a: 50)
    of ctInvincibility:Color(r: 255, g: 0,   b: 255, a: 50)
    of ctFireRate:     Color(r: 255, g: 140, b: 0,   a: 50)
    of ctMagnet:       Color(r: 180, g: 80,  b: 255, a: 50)
    of ctShieldBoost:  Color(r: 100, g: 200, b: 255, a: 50)
    of ctDoubleCoin:   Color(r: 255, g: 230, b: 50,  a: 50)
    of ctDamageBoost:  Color(r: 255, g: 60,  b: 0,   a: 50)
    of ctLifesteal:    Color(r: 200, g: 0,   b: 0,   a: 50)

  # Outer soft aura glow (two layers for depth)
  let auraR1 = size + 7 + sin(t * 4.0) * 2.5
  let auraR2 = size + 13 + sin(t * 3.0 + 1.0) * 3.0
  drawCircle(Vector2(x: consumable.pos.x, y: consumable.pos.y), auraR2,
    withAlpha(auraColor, uint8(auraColor.a.float32 * 0.5)))
  drawCircle(Vector2(x: consumable.pos.x, y: consumable.pos.y), auraR1, auraColor)

  # 4 rotating sparkle dots around the aura ring
  for i in 0..<4:
    let sa = t * 2.2 + i.float32 * PI / 2.0
    let sr = auraR1 + 2.0
    drawCircle(
      Vector2(x: consumable.pos.x + cos(sa) * sr, y: consumable.pos.y + sin(sa) * sr),
      2.0, withAlpha(auraColor, 200))

  # Draw background circle
  let color = getConsumableColor(consumable.consumableType)
  drawCircle(Vector2(x: consumable.pos.x, y: consumable.pos.y), size, color)
  drawCircleLines(consumable.pos.x.int32, consumable.pos.y.int32, size, Black)

  # Use new detailed icon system
  drawConsumableIcon(consumable.pos.x, consumable.pos.y,
                    consumable.radius, consumable.consumableType, pulse)

proc checkPlayerCollision*(consumable: Consumable, player: Player): bool =
  distance(consumable.pos, player.pos) < consumable.radius + player.radius

proc isInPlayerAura*(consumable: Consumable, player: Player): bool =
  # Check if consumable is within player's collection aura
  distance(consumable.pos, player.pos) < player.auraRadius

proc moveConsumableToPlayer*(consumable: Consumable, playerPos: Vector2f, dt: float32) =
  let dir = (playerPos - consumable.pos).normalize()
  let pullSpeed = 300.0
  consumable.pos = consumable.pos + dir * pullSpeed * dt
