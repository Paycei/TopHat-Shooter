import raylib, rlgl, random, math, types, settings, save_system, enemy, bullet, consumable, coin, wall, boss_definitions, particle, particle_pool, particle_types, powerup, powerup_data, sound, d_systems, gamemode_definitions, run_statistics, enemy_config, localization
import game/bullets
import ui/icon_drawing
import utils
export utils

const DEATH_SLOW_DURATION* = 1.1'f32
const DEATH_SPEEDUP_DURATION = 0.35'f32
const DEATH_FADE_DURATION = 0.65'f32
const DEATH_TOTAL_DURATION = DEATH_SLOW_DURATION + DEATH_SPEEDUP_DURATION + DEATH_FADE_DURATION
const DEATH_SLOW_SCALE = 0.16'f32
const DEATH_FAST_SCALE = 1.35'f32


proc getDeathSequenceTimeScale(timer: float32): float32 =
  if timer < DEATH_SLOW_DURATION:
    return DEATH_SLOW_SCALE

  if timer < DEATH_SLOW_DURATION + DEATH_SPEEDUP_DURATION:
    let t = clamp((timer - DEATH_SLOW_DURATION) / DEATH_SPEEDUP_DURATION, 0.0'f32, 1.0'f32)
    let eased = 1.0'f32 - pow(1.0'f32 - t, 3.0'f32)
    return DEATH_SLOW_SCALE + (DEATH_FAST_SCALE - DEATH_SLOW_SCALE) * eased

  DEATH_FAST_SCALE

proc installPowerUp*(game: var Game, powerUp: PowerUp) =
  ## Centralized install feedback so every selected power-up feels like an event.
  applyPowerUp(game.player, powerUp)
  trackPowerUpSelection(game, powerUp)

  let powerName = $powerUp.powerType
  var isNewDiscovery = false
  if not globalSettings.isNil and powerName notin globalSettings.discoveredPowerUps:
    globalSettings.discoveredPowerUps.add(powerName)
    discard saveSettings(globalSettings)
    isNewDiscovery = true

  let accent = if powerUp.rarity == prLegendary:
    Color(r: 255, g: 215, b: 0, a: 255)
  else:
    getPowerUpColor(powerUp.powerType)
  let powerUpName = getPowerUpName(powerUp.powerType)

  game.recentPowerUp = powerUp
  game.recentPowerUpMaxTimer = if powerUp.rarity == prLegendary: 5.0'f32 else: 4.0'f32
  game.recentPowerUpTimer = game.recentPowerUpMaxTimer
  # Only toast the first time a power-up is discovered; repeat installs skip the toast.
  if isNewDiscovery:
    game.pendingToasts.add(t(tkNewProcessInstalled) & ": " & powerUpName)
  addShake(game.dopamine.screenShake, siPowerUp, accent)
  spawnExplosionPooled(game.particlePool, game.player.pos.x, game.player.pos.y,
                       accent, if powerUp.rarity == prLegendary: 72 else: 46)
  playSound(stPowerUp, if powerUp.rarity == prLegendary: 1.0 else: 0.85)

proc drawRecentPowerUpInstall*(game: Game) =
  if game.recentPowerUpTimer <= 0.0 or game.recentPowerUpMaxTimer <= 0.0:
    return

  let progress = clamp(game.recentPowerUpTimer / game.recentPowerUpMaxTimer, 0.0'f32, 1.0'f32)
  let fadeIn = clamp((game.recentPowerUpMaxTimer - game.recentPowerUpTimer) / 0.22'f32, 0.0'f32, 1.0'f32)
  let fadeOut = clamp(game.recentPowerUpTimer / 0.55'f32, 0.0'f32, 1.0'f32)
  let alphaF = min(fadeIn, fadeOut)
  let alpha = int(255.0'f32 * alphaF)
  if alpha <= 0:
    return

  let powerUp = game.recentPowerUp
  let accent = if powerUp.rarity == prLegendary:
    Color(r: 255, g: 215, b: 0, a: 255)
  else:
    getPowerUpColor(powerUp.powerType)
  let name = getPowerUpName(powerUp.powerType)
  let title = if powerUp.rarity == prLegendary: "LEGENDARY INSTALLED" else: "POWER-UP INSTALLED"
  let nameSize: int32 = if measureText(name, 18) > 220: 15 else: 18
  let cardWidth: int32 = min(330'i32, max(220'i32, measureText(name, nameSize) + 88'i32))
  let cardHeight: int32 = 58
  let lift = (1.0'f32 - progress) * 20.0'f32
  let pulse = 1.0'f32 + sin(game.time * 8.0'f32) * 0.035'f32
  var cardX = (game.player.pos.x - cardWidth.float32 / 2.0'f32).int32
  var cardY = (game.player.pos.y - game.player.radius - 92.0'f32 - lift).int32
  cardX = clamp(cardX, 12'i32, game.screenWidth - cardWidth - 12'i32)
  cardY = clamp(cardY, 38'i32, game.screenHeight - cardHeight - 24'i32)

  let ringAlpha = int(145.0'f32 * alphaF)
  for ring in 0..2:
    let ringT = ((1.0'f32 - progress) + ring.float32 * 0.21'f32) mod 1.0'f32
    let radius = game.player.radius + 22.0'f32 + ringT * 78.0'f32
    drawCircleLines(game.player.pos.x.int32, game.player.pos.y.int32, radius,
                    withAlpha(accent, int(ringAlpha.float32 * (1.0'f32 - ringT))))

  let scaledW = (cardWidth.float32 * pulse).int32
  let scaledH = (cardHeight.float32 * pulse).int32
  cardX -= (scaledW - cardWidth) div 2
  cardY -= (scaledH - cardHeight) div 2

  drawRectangle(cardX + 3, cardY + 4, scaledW, scaledH, Color(r: 0, g: 0, b: 0, a: clampByte(alpha div 3)))
  drawRectangle(cardX, cardY, scaledW, scaledH, Color(r: 7, g: 12, b: 20, a: clampByte(int(220.0'f32 * alphaF))))
  drawRectangle(cardX, cardY, 4, scaledH, withAlpha(accent, alpha))
  drawRectangleLines(Rectangle(x: cardX.float32, y: cardY.float32, width: scaledW.float32, height: scaledH.float32),
                     1, withAlpha(accent, alpha))
  drawPowerUpIcon(cardX + 12, cardY + 10, 38, powerUp.powerType, withAlpha(accent, alpha))
  drawText(title, cardX + 61, cardY + 10, 10, withAlpha(accent, alpha))
  drawText(name, cardX + 61, cardY + 25, nameSize, Color(r: 240, g: 248, b: 255, a: clampByte(alpha)))
  let levelText = if powerUp.rarity == prLegendary: "ONE-SHOT MODULE" else: "LEVEL " & $powerUp.level
  drawText(levelText, cardX + 61, cardY + 45, 9, Color(r: 165, g: 190, b: 210, a: clampByte(alpha)))

proc spawnPlayerDeathExplosion(game: Game) =
  let deathPos = game.player.pos
  spawnExplosionPooled(game.particlePool, deathPos.x, deathPos.y,
                      Color(r: 255, g: 45, b: 45, a: 255), 95)
  spawnExplosionPooled(game.particlePool, deathPos.x, deathPos.y,
                      Color(r: 255, g: 205, b: 90, a: 255), 52)
  spawnExplosionPooled(game.particlePool, deathPos.x, deathPos.y,
                      Color(r: 90, g: 15, b: 15, a: 225), 34)

  for _ in 0..<68:
    let angle = rand(1.0) * PI * 2.0
    let speed = 150.0'f32 + rand(230.0).float32
    let size = 3.8'f32 + rand(4.8).float32
    let color =
      if rand(1.0) < 0.30:
        Color(r: 255, g: 255, b: 245, a: 255)
      elif rand(1.0) < 0.62:
        Color(r: 255, g: 235, b: 135, a: 255)
      else:
        Color(r: 255, g: 55, b: 45, a: 255)
    discard game.particlePool.acquireParticleDetailed(
      deathPos.x, deathPos.y,
      cos(angle) * speed, sin(angle) * speed,
      color,
      lifetime = 0.36'f32 + rand(0.32).float32,
      startSize = size,
      endSize = 0.25'f32,
      drag = 3.8'f32 + rand(3.0).float32,
      gravity = (-25.0 + rand(55.0)).float32,
      glow = 1.5'f32,
      style = if rand(1.0) < 0.45: psShard else: psSpark,
      layer = plForeground,
      rotation = rand(360.0).float32,
      spin = (-520.0 + rand(1040.0)).float32
    )

  for i in 0..<26:
    let angle = i.float32 / 26.0'f32 * PI * 2.0'f32 + rand(0.10).float32
    let speed = 310.0'f32 + rand(170.0).float32
    discard game.particlePool.acquireParticleDetailed(
      deathPos.x, deathPos.y,
      cos(angle) * speed, sin(angle) * speed,
      Color(r: 255, g: 242, b: 178, a: 255),
      lifetime = 0.44'f32 + rand(0.18).float32,
      startSize = 3.0'f32 + rand(2.5).float32,
      endSize = 0.15'f32,
      drag = 1.8'f32 + rand(1.4).float32,
      glow = 2.0'f32,
      style = psSpark,
      layer = plForeground,
      rotation = angle * 180.0'f32 / PI.float32,
      spin = (-260.0 + rand(520.0)).float32
    )

  spawnShockwavePooled(game.particlePool, deathPos.x, deathPos.y, 70.0)
  spawnShockwavePooled(game.particlePool, deathPos.x, deathPos.y, 125.0)
  spawnShockwavePooled(game.particlePool, deathPos.x, deathPos.y, 190.0)
  playSound(stExplosion, 0.9)

proc resolveKillerName(game: Game, cause: DeathCause, source: Enemy,
                       sourceType: EnemyType): tuple[name: string, wasBoss: bool] =
  ## Best-effort human-readable name for whatever killed the player.
  # A concrete source object is the most reliable signal.
  if source != nil:
    if source.isBoss:
      return (getBossDefinition(source.bossDefinitionID).name, true)
    if source.enemyType != etEnvironment:
      return (getEnemyConfig(source.enemyType).name, false)
  # Lasers/meteorites/boss-melee rarely carry a source object but are strongly
  # boss-associated: attribute to a living boss when one is present. (Bullets are
  # excluded: they pass their real shooter, so a minion bullet during a boss wave
  # must not be blamed on the boss.)
  if cause in {dcLaser, dcMeteorite, dcBossContact}:
    for e in game.enemies:
      if e.isBoss:
        return (getBossDefinition(e.bossDefinitionID).name, true)
  # Fall back to the raw enemy type, skipping the environment sentinel.
  if sourceType != etEnvironment:
    return (getEnemyConfig(sourceType).name, false)
  return ("", false)

# Comeback mechanic: fixed additive deltas applied to a fresh player at run start.
# Using additive amounts (not a percentage reversal at expiry) guarantees shop/power-up
# purchases made during the run are not affected when the bonus is removed.
const ComebackHpBonus    = 9.0'f32   * 0.1'f32  # +0.9
const ComebackDmgBonus   = 1.0'f32   * 0.1'f32  # +0.1
const ComebackSpeedBonus = 177.5'f32 * 0.1'f32  # +17.75
const ComebackFrBonus    = 0.4275'f32 * 0.1'f32  # 0.04275 subtracted (lower = faster)
const ComebackBsBonus    = 325.0'f32 * 0.1'f32  # +32.5

proc removeComebackBonus*(game: Game) =
  game.comebackBonusActive = false
  game.comebackEndWave = 0
  game.player.maxHp -= ComebackHpBonus
  game.player.hp = min(game.player.hp, game.player.maxHp)
  game.player.damage -= ComebackDmgBonus
  game.player.baseSpeed -= ComebackSpeedBonus
  game.player.speed -= ComebackSpeedBonus
  game.player.fireRate += ComebackFrBonus
  game.player.bulletSpeed -= ComebackBsBonus

proc applyComebackBonus*(game: Game) =
  if globalSettings.isNil or globalSettings.lastDeathWave <= 0:
    return
  if game.mode != gmWaveBased:
    return
  game.comebackBonusActive = true
  game.comebackEndWave = globalSettings.lastDeathWave
  game.player.maxHp += ComebackHpBonus
  game.player.hp = game.player.maxHp
  game.player.damage += ComebackDmgBonus
  game.player.baseSpeed += ComebackSpeedBonus
  game.player.speed += ComebackSpeedBonus
  game.player.fireRate -= ComebackFrBonus
  game.player.bulletSpeed += ComebackBsBonus
  # Consume the stored death wave so restarts don't re-apply it indefinitely
  globalSettings.lastDeathWave = 0
  discard saveSettings(globalSettings)

proc beginPlayerDeathSequence*(game: Game, cause: DeathCause = dcUnknown,
                               source: Enemy = nil, sourceType: EnemyType = etEnvironment) =
  ## Starts the delayed singleplayer death playback before the game-over screen.
  if game.state == gsDeathSequence or game.state == gsGameOver:
    return

  # Record the killer exactly once. The guard above is the latch: same-frame
  # corpse hits and death-playback collisions re-enter here but return early,
  # so the first (true killing) call is the one that sticks.
  game.deathCause = cause
  let killer = resolveKillerName(game, cause, source, sourceType)
  game.deathSourceName = killer.name
  game.deathSourceWasBoss = killer.wasBoss

  if isPvPMode(game.mode):
    game.state = gsGameOver
    return

  # Save the death wave for the comeback mechanic on the next wave-based run.
  if game.mode == gmWaveBased and not game.cheatsUsed and not globalSettings.isNil:
    globalSettings.lastDeathWave = game.currentWave
    discard saveSettings(globalSettings)

  game.state = gsDeathSequence
  game.transitioning = false
  game.fadeAlpha = 0.0
  game.deathSequenceTimer = 0.0
  game.deathSequenceFadeAlpha = 0.0
  game.deathSequenceTimeScale = DEATH_SLOW_SCALE
  game.selectedGameOverButton = 0
  game.player.hp = 0
  game.player.vel = newVector2f(0, 0)
  game.player.timeWarpActive = false
  game.player.timeWarpDuration = 0
  spawnPlayerDeathExplosion(game)
  addShake(game.dopamine.screenShake, siMassive)

proc updateDeathSequencePlayback*(game: var Game, dt: float32) =
  game.deathSequenceTimer += dt
  game.deathSequenceTimeScale = getDeathSequenceTimeScale(game.deathSequenceTimer)
  let worldDt = dt * game.deathSequenceTimeScale

  game.time += worldDt
  game.frameCount += 1

  updateDopamine(game.dopamine, worldDt)
  updateLightningBolts(game, worldDt)
  updateShockwaveRings(game, worldDt)

  var i = 0
  while i < game.attackWarnings.len:
    game.attackWarnings[i].lifetime -= worldDt
    if game.attackWarnings[i].lifetime <= 0:
      game.attackWarnings.delete(i)
    else:
      inc i

  i = 0
  while i < game.lasers.len:
    game.lasers[i].lifetime -= worldDt
    if game.lasers[i].lifetime <= 0:
      game.lasers.delete(i)
    else:
      inc i

  i = 0
  while i < game.bullets.len:
    if game.bullets[i].isFrozenByNova and game.bullets[i].fromPlayer:
      inc i
      continue

    if not updateBullet(game.bullets[i], worldDt) or isOffScreen(game.bullets[i], game.screenWidth, game.screenHeight):
      game.bullets.delete(i)
    else:
      inc i

  i = 0
  while i < game.enemies.len:
    var enemy = game.enemies[i]
    discard updateEnemy(enemy, game.player.pos, worldDt, game.walls, game.time, game)
    game.enemies[i] = enemy
    inc i

  i = 0
  while i < game.meteorites.len:
    if game.meteorites[i].warningTimer > 0:
      game.meteorites[i].warningTimer -= worldDt
    else:
      game.meteorites[i].pos = game.meteorites[i].pos + game.meteorites[i].vel * worldDt
      if game.meteorites[i].pos.x < -100 or game.meteorites[i].pos.x > game.screenWidth.float32 + 100 or
         game.meteorites[i].pos.y < -100 or game.meteorites[i].pos.y > game.screenHeight.float32 + 100:
        game.meteorites.delete(i)
        continue
    inc i

  i = 0
  while i < game.coins.len:
    if not updateCoin(game.coins[i], worldDt, game.coins.len):
      game.coins.delete(i)
    else:
      inc i

  i = 0
  while i < game.consumables.len:
    if not updateConsumable(game.consumables[i], worldDt):
      game.consumables.delete(i)
    else:
      inc i

  i = 0
  while i < game.walls.len:
    if not updateWall(game.walls[i], worldDt):
      game.walls.delete(i)
    else:
      inc i

  updateParticlePool(game.particlePool, worldDt)

  i = 0
  while i < game.damageNumbers.len:
    if not updateDamageNumber(game.damageNumbers[i], worldDt):
      game.damageNumbers.delete(i)
    else:
      inc i

  i = 0
  while i < game.currencyIndicators.len:
    if not updateCurrencyIndicator(game.currencyIndicators[i], worldDt):
      game.currencyIndicators.delete(i)
    else:
      inc i

  i = 0
  while i < game.perkIndicators.len:
    if not updatePerkIndicator(game.perkIndicators[i], worldDt):
      game.perkIndicators.delete(i)
    else:
      inc i

  let fadeStart = DEATH_SLOW_DURATION + DEATH_SPEEDUP_DURATION
  game.deathSequenceFadeAlpha =
    if game.deathSequenceTimer <= fadeStart:
      0.0
    else:
      clamp((game.deathSequenceTimer - fadeStart) / DEATH_FADE_DURATION, 0.0'f32, 1.0'f32)

  if game.deathSequenceTimer >= DEATH_TOTAL_DURATION:
    game.deathSequenceFadeAlpha = 1.0
    game.state = gsGameOver
