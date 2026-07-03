import raylib, random, math
import particle_types, types, ui/consumable_icons, ui/ui_constants

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
    Color(r: auraColor.r, g: auraColor.g, b: auraColor.b, a: uint8(auraColor.a.float32 * 0.5)))
  drawCircle(Vector2(x: consumable.pos.x, y: consumable.pos.y), auraR1, auraColor)

  # 4 rotating sparkle dots around the aura ring
  for i in 0..<4:
    let sa = t * 2.2 + i.float32 * PI / 2.0
    let sr = auraR1 + 2.0
    drawCircle(
      Vector2(x: consumable.pos.x + cos(sa) * sr, y: consumable.pos.y + sin(sa) * sr),
      2.0, Color(r: auraColor.r, g: auraColor.g, b: auraColor.b, a: 200))

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
