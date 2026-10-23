import raylib, math, random
import modding/mod_patch_core
import draw_prims
import particle_types, types, utils, particle, particle_pool, pickup, powerup, sound, run_statistics, game/combat, gamemode_definitions, enemy_config
import modding/mod_hooks
import coop/coop_context
from roguelite import bankMetaCurrency

const RogueliteCoinScale* = 0.45'f32
  ## Roguelite kill-drop credit scale (measured: unscaled drops paid ~1600 of a
  ## run's ~2400 credits against stalls costing 55-250).

proc newCoin*(x, y: float32, value: int = 1, isBoss: bool = false): Coin {.moddable.} =
  # Scale coin radius based on value for visual feedback
  # Cap scaling at value 10 to prevent coins from becoming too large
  let baseRadius = 6.0
  let cappedValue = min(value, 10)
  let scaledRadius = baseRadius + (cappedValue - 1).float32 * 1.5  # Grows with value, capped at 10

  # Boss coins are larger and more prominent
  let finalRadius = if isBoss: scaledRadius * 1.8 else: scaledRadius

  result = Coin(
    pos: vec2(x, y),
    radius: finalRadius,
    value: value,
    lifetime: -1.0,  # Negative lifetime means no time-based despawn
    isBossCoin: isBoss
  )

proc pickupAlive*(game: Game, coin: Coin, dt: float32, count: int): bool {.moddable.} =
  # Coins despawn based on total count, not time
  # Keep coins until there are too many (> 150)
  # The boss coin is exempt: wave mode only advances once it is picked up, so
  # letting it fade out with the overflow would leave the run stuck forever.
  # Roguelite folders vacuum every coin at clear (collectAllCoins), so there
  # the overflow despawn would only ever delete credits a big pulse had earned.
  if coin.isBossCoin or game.mode == gmRoguelite:
    return true
  if count > 150:
    # Start despawning oldest coins (mark with positive lifetime)
    if coin.lifetime < 0:
      coin.lifetime = 3.0  # 3 seconds to fade out
    else:
      coin.lifetime -= dt
      return coin.lifetime > 0
  return true  # Keep coin if under limit

proc drawCoin(coin: Coin) {.moddable.} =
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
  drawDisc(coin.pos, size + 6 + pulse * 2, glowColor)

  # Main body
  drawDisc(coin.pos, size, mainColor)

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
  drawCircleOutline(coin.pos.x.int32, coin.pos.y.int32, size, rimColor)
  drawCircleOutline(coin.pos.x.int32, coin.pos.y.int32, size - 1.5, Color(r: 255, g: 255, b: 150, a: 120))

  # Rotating sparkle dots (4 dots orbiting)
  let sparkR = size + 4.5 + sin(t * 6.0) * 1.5
  for i in 0..<4:
    let sa = t * 3.5 + i.float32 * PI / 2.0
    let sx = coin.pos.x + cos(sa) * sparkR
    let sy = coin.pos.y + sin(sa) * sparkR
    let sparkAlpha = uint8(140 + sin(t * 8.0 + i.float32) * 80)
    drawDisc(Vector2(x: sx, y: sy), 1.8,
      Color(r: 255, g: 255, b: 200, a: sparkAlpha))

  # Boss coins: extra bold outer ring
  if coin.isBossCoin:
    let outerPulse = 1.0 + 0.4 * sin(t * 6.0)
    drawCircleOutline(coin.pos.x.int32, coin.pos.y.int32, size * outerPulse * 1.25,
                   Color(r: 255, g: 150, b: 150, a: 160))

  # Draw value if > 1
  if coin.value > 1:
    let text = $coin.value
    let fontSize = min(10 + (coin.value div 3), 16)
    let textWidth = measureText(text, fontSize.int32)
    drawText(text, (coin.pos.x - textWidth.float32 / 2).int32,
             (coin.pos.y - fontSize.float32 / 2).int32, fontSize.int32, Black)

proc pickupTrail*(coin: Coin): Color {.moddable.} =
  Color(r: 255, g: 215, b: 0, a: 150)

proc enemyCoinValue(enemy: Enemy, mode: GameMode, currentWave: int, difficulty: float32): int {.moddable.} =
  if enemy.isBoss:
    let baseAmount = if mode == gmWaveBased:
      50 + (currentWave div BossWaveInterval) * 10  # +10 coins per boss number
    else:
      30 + (difficulty * 3.5).int
    let minAmount = (baseAmount.float32 * 0.9).int
    let maxAmount = (baseAmount.float32 * 1.1).int
    result = rand(minAmount..maxAmount)
  else:
    let waveBonus = if mode == gmWaveBased: 0 else: (currentWave div 10)
    let baseValue = case enemy.enemyType
      of FirstModEnemy..LastModEnemy: modEnemies[enemy.enemyType].coins
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
      of etThread: 1
      of etForkBomb: 2
      of etWatchdog: 3
      of etZombie: 3
      of etDeadlock: 2
      of etDaemon: 4
      of etInterrupt: 1
      of etFragment: 1
      of etPortGuard: 4
      of etSentry: 3
      of etMimic: 5
      of etRestorer: 4
      of etPacket: 3
      of etDriver: 5
      of etCorruptor: 4
      of etEnvironment: 0
    result = baseValue + waveBonus
  if enemy.isElite:
    result = (result.float32 * 1.5).int
  result = modCoinValue(enemy, result)

proc dropEnemyCoin*(game: Game, enemy: Enemy) {.moddable.} =
  var coinValue = enemyCoinValue(enemy, game.mode, game.currentWave, game.difficulty)
  # Density normalisation (wave mode). Coin value is granted per enemy, so the
  # ~4x head count would otherwise pay out ~4x per wave -- a measured run earned
  # 27.5k coins and bought 53 shop upgrades. Bosses are exempt: there is still
  # exactly one of them, so their lump is not a per-enemy quantity at all.
  # Roguelite rooms fight on the same density curve (densityWave), but round
  # STOCHASTICALLY instead of flooring at 1: a pulsed swarm is mostly 1-credit
  # enemies, and the floor minted a credit from every one of them (measured:
  # 1000-2600 unspendable credits by the last sector). Wave mode keeps its
  # floor so every kill there still visibly pays. Survival's horde rounds
  # stochastically too (no RogueliteCoinScale): its credits only buy rerolls.
  if (densityWave(game) > 0 or game.mode == gmTimeSurvival) and not enemy.isBoss:
    var scaled = coinValue.float32 * densityRebate(game)
    if game.mode == gmTimeSurvival:
      coinValue = int(scaled) + (if rand(1.0'f32) < fract01(scaled): 1 else: 0)
      if coinValue <= 0:
        return
    elif game.mode == gmRoguelite:
      # Credits only buy /pkg stalls and rerolls here (no stat shop), so kill
      # drops are scaled to what a sector should afford: one or two stalls.
      scaled *= RogueliteCoinScale
      coinValue = int(scaled) + (if rand(1.0'f32) < fract01(scaled): 1 else: 0)
      if coinValue <= 0:
        return
    else:
      coinValue = max(1, int(scaled))
  let clampedPos = clampLootPosition(enemy.pos.x, enemy.pos.y, game.screenWidth, game.screenHeight)
  let requiresBossCoin = enemy.isBoss and game.mode == gmWaveBased
  game.coins.add(newCoin(clampedPos.x, clampedPos.y, coinValue, requiresBossCoin))

proc awardMetaCurrency*(game: Game, shards: int, cores: int = 0) {.moddable.} =
  ## Wave/survival reward: bank Data Shards / Cores into the profile wallet the
  ## cosmetic shop spends from, tally them for the end-of-run screens, and float
  ## the amounts over the player. A cheated run earns nothing from here on (what
  ## was banked before the cheat menu opened is kept).
  if game.cheatsUsed or not bankMetaCurrency(shards, cores):
    return
  # A co-op team earns it together: every teammate banks it in their own wallet.
  pushTeamProfileEvent(game, ProfileEvent(kind: pekMetaBank, a: int32(shards), b: int32(cores)))
  game.metaShardsEarned += max(0, shards)
  game.metaCoresEarned += max(0, cores)
  # Kept live (finalizeRunTracking re-syncs it) because the victory screen's
  # View Stats opens before the run is finalized.
  if not currentRunStats.isNil:
    currentRunStats.rogueliteShardsEarned = game.metaShardsEarned
  if shards > 0:
    showCurrency(game, game.player.pos + vec2(0, -40), shards, cikDataShards)
  if cores > 0:
    showCurrency(game, game.player.pos + vec2(28, -26), cores, cikCores)

proc coinPickupValue*(player: Player, value: int): int {.moddable.} =
  ## A coin's credits once Lucky Coins and Double Coin have doubled it.
  result = value
  if hasPowerUp(player, puLuckyCoins):
    result *= 2
  if player.doubleCoinTimer > 0:
    result *= 2

proc gainCoinCredits(game: Game, values: openArray[int]): int =
  ## Bank coins worth `values`: each player of the run with their own Lucky
  ## Coins and Double Coin. Returns the active player's share (the pop-up's).
  for v in values:
    result += coinPickupValue(game.player, v)
  if game.players.len <= 1:
    gainCredits(game, result)
    return
  for p in game.players:
    if p.eliminated: continue
    var share = 0
    for v in values:
      share += coinPickupValue(p, v)
    p.coins += share
  if result > 0:
    bookCredits(game, result)

proc collectAllCoins*(game: Game) {.moddable.} =
  ## Auto-bank every coin on the floor when the room is cleared, applying the
  ## same multipliers as contact pickup (Lucky Coins, Double Coin).
  if game.coins.len == 0: return
  var values: seq[int]
  for coin in game.coins:
    values.add coin.value
  game.coins = @[]
  let totalValue = gainCoinCredits(game, values)
  if totalValue > 0:
    playSound(stCoinPickup, 0.6)
    recordFx(CoopFx(kind: fxCurrency, x: game.player.pos.x, y: game.player.pos.y - 18,
                    a: int32(totalValue), b: int32(ord(cikCredits))))
    game.currencyIndicators.add(newCurrencyIndicator(
      game.player.pos.x, game.player.pos.y - 18, totalValue, cikCredits))

proc collectPickup*(game: Game, coin: Coin): bool {.moddable.} =
  ## The player touched `coin`: a mod's pickup hook may take it (never the boss
  ## coin), else its credits, feedback and stats (the caller removes it). True:
  ## it was the boss wave's coin and the wave can end.
  let isBossCoin = coin.isBossCoin
  if not isBossCoin and modPickup(game, "coin", coin.value.float64):
    return false
  let coinValue = gainCoinCredits(game, [coin.value])
  showCurrency(game, coin.pos, coinValue, cikCredits)
  playSound(stCoinPickup, if isBossCoin: 0.8 else: 0.5)
  let coinParticleColor = if isBossCoin: Color(r: 255, g: 50, b: 50, a: 255) else: Gold
  spawnExplosionPooled(game.particlePool, coin.pos.x, coin.pos.y, coinParticleColor, if isBossCoin: 20 else: 6)

  if isBossCoin and game.bossWaveManager.coinActive:
    game.bossWaveManager.coinActive = false
    if shouldUseWaves(game.mode):
      result = true

proc updateGameCoins*(game: Game, dt: float32): bool {.moddable.} =
  ## Update all coins, handle collection, and magnet/aura movement.
  ## Returns true if a boss coin was collected and completeBossWave should be called.
  # Recovery: the wave is waiting on a boss coin that no longer exists (a run
  # saved by an older build, where the coin could fade out). Put one back at
  # the arena centre so the wave can finish.
  if game.bossWaveManager.coinActive and shouldUseWaves(game.mode):
    var bossCoinPresent = false
    for coin in game.coins:
      if coin.isBossCoin:
        bossCoinPresent = true
        break
    if not bossCoinPresent:
      game.coins.add(newCoin(game.screenWidth.float32 / 2, game.screenHeight.float32 / 2,
                             1, isBoss = true))

  result = updatePickups(game, game.coins, dt)

proc spawnMagnetCoins*(game: Game) {.moddable.} =
  for _ in 0..<3:
    let angle = rand(1.0) * PI * 2.0
    let dist = 50.0 + rand(150.0)
    let coinX = game.player.pos.x + cos(angle) * dist
    let coinY = game.player.pos.y + sin(angle) * dist
    let clampedPos = clampLootPosition(coinX, coinY, game.screenWidth, game.screenHeight)
    game.coins.add(newCoin(clampedPos.x, clampedPos.y, 1))

proc drawGameCoins*(game: Game) {.moddable.} =
  for coin in game.coins:
    drawCoin(coin)
