import raylib, types, random, math

proc newConsumable*(x, y: float32, difficulty: float32): Consumable =
  # Weighted selection based on difficulty
  let roll = rand(100)
  var cType: ConsumableType
  
  if roll < 40:
    cType = ctHealth
  elif roll < 65:
    cType = ctCoin
  elif roll < 78:
    cType = ctSpeed
  elif roll < 88:
    cType = ctFireRate
  elif roll < 95:
    cType = ctMagnet
  else:
    cType = ctInvincibility
  
  result = Consumable(
    pos: newVector2f(x, y),
    radius: 8,
    consumableType: cType,
    lifetime: 12.0
  )

proc updateConsumable*(consumable: Consumable, dt: float32): bool =
  consumable.lifetime -= dt
  return consumable.lifetime > 0

proc drawConsumable*(consumable: Consumable) =
  let pulse = 1.0 + 0.15 * sin(consumable.lifetime * 6.0)
  let size = consumable.radius * pulse
  
  let color = case consumable.consumableType
    of ctHealth: Green
    of ctCoin: Gold
    of ctSpeed: SkyBlue
    of ctInvincibility: Magenta
    of ctFireRate: Orange
    of ctMagnet: Purple
  
  drawCircle(Vector2(x: consumable.pos.x, y: consumable.pos.y), size, color)
  drawCircleLines(consumable.pos.x.int32, consumable.pos.y.int32, size, Black)
  
  # Draw icon/symbol
  case consumable.consumableType
  of ctHealth:
    drawText("+", (consumable.pos.x - 4).int32, (consumable.pos.y - 6).int32, 12, White)
  of ctCoin:
    drawText("$", (consumable.pos.x - 4).int32, (consumable.pos.y - 6).int32, 12, Black)
  of ctSpeed:
    drawText("S", (consumable.pos.x - 4).int32, (consumable.pos.y - 6).int32, 12, White)
  of ctInvincibility:
    drawText("!", (consumable.pos.x - 3).int32, (consumable.pos.y - 6).int32, 12, White)
  of ctFireRate:
    drawText("F", (consumable.pos.x - 4).int32, (consumable.pos.y - 6).int32, 12, White)
  of ctMagnet:
    drawText("M", (consumable.pos.x - 4).int32, (consumable.pos.y - 6).int32, 12, White)

proc checkPlayerCollision*(consumable: Consumable, player: Player): bool =
  distance(consumable.pos, player.pos) < consumable.radius + player.radius
