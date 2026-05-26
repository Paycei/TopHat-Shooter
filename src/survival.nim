# SURVIVAL MODE - Time Survival specific logic

import raylib, random, math
import types, enemy, particle_pool, localization

proc spawnSurvivalEnemies*(game: Game) =
  ## Time-based enemy spawning for Survival mode.
  ## Spawn rate scales with difficulty, every 15 s a brief "wave burst" fires
  ## extra enemies (60 % chance of a double-spawn while waveProgress > 0.6).
  ## Boss waves double the spawn rate to maintain pressure.

  # Spawn-rate curve: slows logarithmically as difficulty climbs
  let baseSpawnRate =
    if game.difficulty < 1.5:
      3.0
    elif game.difficulty < 3.0:
      2.3 / (1.0 + (game.difficulty - 1.5) * 0.3)
    elif game.difficulty < 6.0:
      1.8 / (1.0 + (game.difficulty - 3.0) * 0.25)
    elif game.difficulty < 9.0:
      1.4 / (1.0 + (game.difficulty - 6.0) * 0.15)
    elif game.difficulty < 13.0:
      1.2 / (1.0 + (game.difficulty - 9.0) * 0.1)
    else:
      max(0.9, 1.0 / (1.0 + (game.difficulty - 13.0) * 0.05))

  # Every 15 s the last 40 % of the cycle is a "wave burst" with tighter rate
  let waveSpawnRate  = baseSpawnRate * 0.7
  let waveProgress   = (game.time mod 15.0) / 15.0
  let isWaveActive   = waveProgress > 0.6

  var currentSpawnRate = if isWaveActive: waveSpawnRate else: baseSpawnRate
  # Double spawn pressure while a boss is alive
  if game.bossWaveManager.active:
    currentSpawnRate = currentSpawnRate * 2.0

  if game.spawnTimer > currentSpawnRate:
    let newEnemy = spawnEnemy(game.screenWidth, game.screenHeight, game.difficulty, game)
    makeElite(newEnemy, (game.difficulty * 3).int)   # use difficulty as wave equivalent
    game.enemies.add(newEnemy)
    game.spawnTimer = 0

    # Extra spawn during wave burst (60 % chance, but not during boss fight)
    if isWaveActive and rand(100) < 60 and not game.bossWaveManager.active:
      let waveEnemy = spawnEnemy(game.screenWidth, game.screenHeight, game.difficulty, game)
      makeElite(waveEnemy, (game.difficulty * 3).int)
      game.enemies.add(waveEnemy)

    # Entrance particle burst for the latest enemy
    let newest = game.enemies[^1]
    for i in 0..<60:
      let angle = i.float32 * 0.1
      let dist  = i.float32 * 3.0
      spawnExplosionPooled(game.particlePool,
                           newest.pos.x + cos(angle) * dist,
                           newest.pos.y + sin(angle) * dist,
                           newest.color, 3)

proc drawSurvivalHUD*(game: Game, screenWidth, screenHeight: int32) =
  ## Draws the "WAVE INCOMING!" banner during the burst window of every 15-second cycle.
  ## Only shown when no boss is currently active.
  let waveProgress = (game.time mod 15.0) / 15.0
  if waveProgress > 0.6 and not game.bossWaveManager.active:
    drawText(t(tkGameWaveAnnouncementMain),
             screenWidth div 2 - 80, 10, 25, Red)
