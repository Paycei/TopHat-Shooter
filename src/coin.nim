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
  # Pulsing effect (more intense for boss coins)
  let pulseSpeed = if coin.isBossCoin: 8.0 else: 5.0
  let pulseAmount = if coin.isBossCoin: 0.3 else: 0.2
  let pulse = 1.0 + pulseAmount * sin(coin.lifetime * pulseSpeed)
  let size = coin.radius * pulse
  
  # Boss coins have special red colors
  let mainColor = if coin.isBossCoin: 
    Color(r: 255, g: 50, b: 50, a: 255)  # Bright red
  else: 
    Gold
  let outlineColor = if coin.isBossCoin: 
    Color(r: 200, g: 0, b: 0, a: 255)  # Dark red
  else: 
    Orange
  
  drawCircle(Vector2(x: coin.pos.x, y: coin.pos.y), size, mainColor)
  drawCircleLines(coin.pos.x.int32, coin.pos.y.int32, size, outlineColor)
  
  # Boss coins have extra visual ring
  if coin.isBossCoin:
    let outerPulse = 1.0 + 0.4 * sin(coin.lifetime * 6.0)
    drawCircleLines(coin.pos.x.int32, coin.pos.y.int32, size * outerPulse * 1.2, 
                   Color(r: 255, g: 150, b: 150, a: 180))  # Light red ring
  
  # Draw value if > 1 (scale text size with coin size)
  if coin.value > 1:
    let text = $coin.value
    let fontSize = min(10 + (coin.value div 3), 16)  # Larger text for bigger values
    let textWidth = measureText(text, fontSize.int32)
    drawText(text, (coin.pos.x - textWidth.float32 / 2).int32, (coin.pos.y - fontSize.float32 / 2).int32, fontSize.int32, Black)

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
