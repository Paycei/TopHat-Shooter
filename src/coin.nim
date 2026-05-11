import raylib, types, math

proc newCoin*(x, y: float32, value: int = 1, isBoss: bool = false): Coin =
  # Scale coin radius based on value for visual feedback
  # Cap scaling at value 10 to prevent coins from becoming too large
  let baseRadius = 6.0
  let cappedValue = min(value, 10)
  let scaledRadius = baseRadius + (cappedValue - 1).float32 * 1.5  # Grows with value, capped at 10

  # Boss coins are larger and more prominent
  let finalRadius = if isBoss: scaledRadius * 1.8 else: scaledRadius

  result = Coin(
    pos: newVector2f(x, y),
    radius: finalRadius,
    value: value,
    lifetime: -1.0,  # Negative lifetime means no time-based despawn
    isBossCoin: isBoss
  )

proc updateCoin*(coin: Coin, dt: float32, totalCoins: int): bool =
  # Coins despawn based on total count, not time
  # Keep coins until there are too many (> 150)
  if totalCoins > 150:
    # Start despawning oldest coins (mark with positive lifetime)
    if coin.lifetime < 0:
      coin.lifetime = 3.0  # 3 seconds to fade out
    else:
      coin.lifetime -= dt
      return coin.lifetime > 0
  return true  # Keep coin if under limit

proc drawCoin*(coin: Coin) =
  let t = getTime()
  # Pulsing effect (more intense for boss coins)
  let pulseSpeed = if coin.isBossCoin: 8.0 else: 5.0
  let pulseAmount = if coin.isBossCoin: 0.3 else: 0.18
  let pulse = 1.0 + pulseAmount * sin(t * pulseSpeed)
  let size = coin.radius * pulse

  # Boss coins have special red colors
  let mainColor = if coin.isBossCoin:
    Color(r: 255, g: 50, b: 50, a: 255)
  else:
    Gold
  let glowColor = if coin.isBossCoin:
    Color(r: 255, g: 100, b: 100, a: 60)
  else:
    Color(r: 255, g: 215, b: 0, a: 55)
  let rimColor = if coin.isBossCoin:
    Color(r: 200, g: 0, b: 0, a: 255)
  else:
    Orange

  # Outer soft glow
  drawCircle(Vector2(x: coin.pos.x, y: coin.pos.y), size + 6 + pulse * 2, glowColor)

  # Main body
  drawCircle(Vector2(x: coin.pos.x, y: coin.pos.y), size, mainColor)

  # Spinning inner diamond (4-point star shape using 4 triangles)
  let spinAngle = t * 2.8  # rotation speed
  let dR = size * 0.55
  for i in 0..<4:
    let a0 = spinAngle + i.float32 * PI / 2.0
    let a1 = spinAngle + (i.float32 + 1.0) * PI / 2.0
    let amid = spinAngle + (i.float32 + 0.5) * PI / 2.0
    let innerR = dR * 0.35
    drawTriangle(
      Vector2(x: coin.pos.x + cos(a0) * dR,    y: coin.pos.y + sin(a0) * dR),
      Vector2(x: coin.pos.x + cos(amid) * innerR, y: coin.pos.y + sin(amid) * innerR),
      Vector2(x: coin.pos.x + cos(a1) * dR,    y: coin.pos.y + sin(a1) * dR),
      Color(r: 255, g: 255, b: 180, a: 200))

  # Outer ring / rim
  drawCircleLines(coin.pos.x.int32, coin.pos.y.int32, size, rimColor)
  drawCircleLines(coin.pos.x.int32, coin.pos.y.int32, size - 1.5, Color(r: 255, g: 255, b: 150, a: 120))

  # Rotating sparkle dots (4 dots orbiting)
  let sparkR = size + 4.5 + sin(t * 6.0) * 1.5
  for i in 0..<4:
    let sa = t * 3.5 + i.float32 * PI / 2.0
    let sx = coin.pos.x + cos(sa) * sparkR
    let sy = coin.pos.y + sin(sa) * sparkR
    let sparkAlpha = uint8(140 + sin(t * 8.0 + i.float32) * 80)
    drawCircle(Vector2(x: sx, y: sy), 1.8,
      Color(r: 255, g: 255, b: 200, a: sparkAlpha))

  # Boss coins: extra bold outer ring
  if coin.isBossCoin:
    let outerPulse = 1.0 + 0.4 * sin(t * 6.0)
    drawCircleLines(coin.pos.x.int32, coin.pos.y.int32, size * outerPulse * 1.25,
                   Color(r: 255, g: 150, b: 150, a: 160))

  # Draw value if > 1
  if coin.value > 1:
    let text = $coin.value
    let fontSize = min(10 + (coin.value div 3), 16)
    let textWidth = measureText(text, fontSize.int32)
    drawText(text, (coin.pos.x - textWidth.float32 / 2).int32,
             (coin.pos.y - fontSize.float32 / 2).int32, fontSize.int32, Black)

proc checkPlayerCollision*(coin: Coin, player: Player): bool =
  let collectRange = if player.magnetTimer > 0: 80.0 else: coin.radius + player.radius
  distance(coin.pos, player.pos) < collectRange

proc checkAuraCollision*(coin: Coin, player: Player, auraRadius: float32): bool =
  # Check if coin is within player's collection aura
  distance(coin.pos, player.pos) < auraRadius

proc moveCoinToPlayer*(coin: Coin, playerPos: Vector2f, dt: float32) =
  let dir = (playerPos - coin.pos).normalize()
  let pullSpeed = 300.0
  coin.pos = coin.pos + dir * pullSpeed * dt
