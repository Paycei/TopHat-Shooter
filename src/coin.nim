import raylib, types, math

proc newCoin*(x, y: float32, value: int = 1): Coin =
  result = Coin(
    pos: newVector2f(x, y),
    radius: 6,
    value: value,
    lifetime: 15.0
  )

proc updateCoin*(coin: Coin, dt: float32): bool =
  coin.lifetime -= dt
  return coin.lifetime > 0

proc drawCoin*(coin: Coin) =
  # Pulsing effect
  let pulse = 1.0 + 0.2 * sin(coin.lifetime * 5.0)
  let size = coin.radius * pulse
  
  drawCircle(Vector2(x: coin.pos.x, y: coin.pos.y), size, Gold)
  drawCircleLines(coin.pos.x.int32, coin.pos.y.int32, size, Orange)
  
  # Draw value if > 1
  if coin.value > 1:
    let text = $coin.value
    drawText(text, (coin.pos.x - 4).int32, (coin.pos.y - 5).int32, 10, Black)

proc checkPlayerCollision*(coin: Coin, player: Player): bool =
  let collectRange = if player.magnetTimer > 0: 80.0 else: coin.radius + player.radius
  distance(coin.pos, player.pos) < collectRange

proc moveCoinToPlayer*(coin: Coin, playerPos: Vector2f, dt: float32) =
  let dir = (playerPos - coin.pos).normalize()
  let pullSpeed = 300.0
  coin.pos = coin.pos + dir * pullSpeed * dt
