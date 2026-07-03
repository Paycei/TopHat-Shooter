import raylib, math, random
import particle_types, types, particle, particle_pool, powerup, sound, d_systems, d_enhancements, run_statistics, game/combat, gamemode_definitions

const LOOT_MARGIN* = 50.0  # Distance from screen edge

proc clampLootPosition*(x, y: float32, screenWidth, screenHeight: int32): tuple[x, y: float32] =
  ## Clamps a position to be within screen bounds with margin
  result.x = clamp(x, LOOT_MARGIN, screenWidth.float32 - LOOT_MARGIN)
  result.y = clamp(y, LOOT_MARGIN, screenHeight.float32 - LOOT_MARGIN)

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

proc enemyCoinValue*(enemy: Enemy, mode: GameMode, currentWave: int, difficulty: float32): int =
  if enemy.isBoss:
    let baseAmount = if mode == gmWaveBased:
      50 + (currentWave div 5) * 10  # +10 coins every 5 waves
    else:
      30 + (difficulty * 3.5).int
    let minAmount = (baseAmount.float32 * 0.9).int
    let maxAmount = (baseAmount.float32 * 1.1).int
    result = rand(minAmount..maxAmount)
  else:
    let waveBonus = if mode == gmWaveBased: 0 else: (currentWave div 10)
    let baseValue = case enemy.enemyType
      of etCircle: 1
      of etCube: 3           # More coins since it's now harder
      of etTriangle: 2
      of etStar: 5
      of etHexagon: 3
      of etCross: 3
      of etDiamond: 4
      of etOctagon: 3
      of etPentagon: 1       # Early game enemy, low coins
      of etTrickster: 6
      of etPhantom: 7
      of etSniper: 10
      of etMage: 10
      of etEnvironment: 0
    result = baseValue + waveBonus
  if enemy.isElite:
    result = (result.float32 * 1.5).int

proc dropEnemyCoin*(game: Game, enemy: Enemy) =
  var coinValue = enemyCoinValue(enemy, game.mode, game.currentWave, game.difficulty)
  let clampedPos = clampLootPosition(enemy.pos.x, enemy.pos.y, game.screenWidth, game.screenHeight)
  let requiresBossCoin = enemy.isBoss and game.mode == gmWaveBased
  game.coins.add(newCoin(clampedPos.x, clampedPos.y, coinValue, requiresBossCoin))

proc collectAllCoins*(game: Game) =
  ## Auto-bank every coin on the floor when the room is cleared, applying the
  ## same multipliers as contact pickup (Lucky Coins, Double Coin).
  if game.coins.len == 0: return
  var totalValue = 0
  for coin in game.coins:
    var coinValue = coin.value
    if hasPowerUp(game.player, puLuckyCoins):
      coinValue *= 2
    if game.player.doubleCoinTimer > 0:
      coinValue *= 2
    totalValue += coinValue
  game.coins = @[]
  if totalValue > 0:
    game.player.coins += totalValue
    playSound(stCoinPickup, 0.6)
    game.currencyIndicators.add(newCurrencyIndicator(
      game.player.pos.x, game.player.pos.y - 18, totalValue, cikCredits))

proc updateGameCoins*(game: Game, dt: float32): bool =
  ## Update all coins, handle collection, and magnet/aura movement.
  ## Returns true if a boss coin was collected and completeBossWave should be called.
  var i = 0
  while i < game.coins.len:
    if not updateCoin(game.coins[i], dt, game.coins.len):
      game.coins.delete(i)
      continue

    if checkAuraCollision(game.coins[i], game.player, game.player.auraRadius):
      moveCoinToPlayer(game.coins[i], game.player.pos, dt)
      spawnTimedParticlesPooled(game.particlePool, game.coins[i].pos.x, game.coins[i].pos.y, 18.0,
                         Color(r: 255, g: 215, b: 0, a: 150), 1, dt)

    if game.player.magnetTimer > 0:
      moveCoinToPlayer(game.coins[i], game.player.pos, dt)

    if checkPlayerCollision(game.coins[i], game.player):
      let isBossCoin = game.coins[i].isBossCoin
      var coinValue = game.coins[i].value
      if hasPowerUp(game.player, puLuckyCoins):
        coinValue *= 2
      if game.player.doubleCoinTimer > 0:
        coinValue *= 2
      game.player.coins += coinValue
      showCurrency(game, game.coins[i].pos, coinValue, cikCredits)

      trackCoinPickup(game, coinValue)

      recordCoin(game.dopamine.realTimeStats, game.dopamine.currentTime)
      recordCoin(game.dopamine.waveStats)
      playSound(stCoinPickup, if isBossCoin: 0.8 else: 0.5)
      let coinParticleColor = if isBossCoin: Color(r: 255, g: 50, b: 50, a: 255) else: Gold
      spawnExplosionPooled(game.particlePool, game.coins[i].pos.x, game.coins[i].pos.y, coinParticleColor, if isBossCoin: 20 else: 6)

      if isBossCoin and game.bossWaveManager.coinActive:
        game.bossWaveManager.coinActive = false
        if shouldUseWaves(game.mode):
          result = true

      game.coins.delete(i)
      continue

    i += 1

proc updateCoinsWaveCleared*(game: Game, dt: float32) =
  ## Simplified coin update for the brief gsWaveCleared window.
  ## Intentionally skips stat recording, achievement checks, and boss-coin logic.
  var i = 0
  while i < game.coins.len:
    if not updateCoin(game.coins[i], dt, game.coins.len):
      game.coins.delete(i)
      continue

    if checkAuraCollision(game.coins[i], game.player, game.player.auraRadius):
      moveCoinToPlayer(game.coins[i], game.player.pos, dt)

    if game.player.magnetTimer > 0:
      moveCoinToPlayer(game.coins[i], game.player.pos, dt)

    if checkPlayerCollision(game.coins[i], game.player):
      var coinValue = game.coins[i].value
      if hasPowerUp(game.player, puLuckyCoins):
        coinValue *= 2
      if game.player.doubleCoinTimer > 0:
        coinValue *= 2
      game.player.coins += coinValue
      trackCoinPickup(game, coinValue)
      playSound(stCoinPickup, 0.5)
      spawnExplosionPooled(game.particlePool, game.coins[i].pos.x, game.coins[i].pos.y, Gold, 6)
      game.coins.delete(i)
      continue

    i += 1

proc spawnMagnetCoins*(game: Game) =
  for _ in 0..<3:
    let angle = rand(1.0) * PI * 2.0
    let dist = 50.0 + rand(150.0)
    let coinX = game.player.pos.x + cos(angle) * dist
    let coinY = game.player.pos.y + sin(angle) * dist
    let clampedPos = clampLootPosition(coinX, coinY, game.screenWidth, game.screenHeight)
    game.coins.add(newCoin(clampedPos.x, clampedPos.y, 1))

proc drawGameCoins*(game: Game) =
  for coin in game.coins:
    drawCoin(coin)
