proc calculateWaveEnemyCount(waveNumber: int): int =
  # Scale enemy count based on wave number
  # Start with 8 enemies, add 2-3 per wave
  result = int(8 + float(waveNumber - 1) * 1.5)
  # Cap at 100 enemies per wave
  if result > 100:
    result = 100

proc startWave*(game: Game) =
  game.waveInProgress = true
  game.waveStartTime = game.time  # Track when this wave started
  # Visual pulse ring, cyan for normal waves, orange for boss-lead waves
  let wavePulseColor = if game.wavesUntilBoss == 0:
    Color(r: 255, g: 160, b: 0, a: 255)
  else:
    Color(r: 0, g: 200, b: 255, a: 255)
  spawnWavePulse(game.osBackground,
    game.screenWidth.float32 / 2.0,
    game.screenHeight.float32 / 2.0,
    wavePulseColor)
  var waveEnemyCount = calculateWaveEnemyCount(game.currentWave)

  # Apply boss wave reduction if this is a boss wave
  if game.wavesUntilBoss == 0:
    waveEnemyCount = (waveEnemyCount.float32 * BOSS_WAVE_SPAWN_MULTIPLIER).int

  game.waveEnemiesTotal = waveEnemyCount
  game.waveEnemiesRemaining = waveEnemyCount
  game.spawnTimer = 0

  # Mark wave start for combo tracking
  startWaveCombo(game.dopamine.comboSystem)

  # PLAYER SCALING: Multiply current stats by 1.2% per wave (preserves shop purchases and power-ups)
  # This applies scaling multiplicatively to whatever stats the player has built up
  let waveScaling: float32 = 1.012  # 1.2% increase per wave

  # Apply multiplicative scaling to current stats (preserves all upgrades)
  game.player.maxHp *= waveScaling
  game.player.hp = min(game.player.hp * waveScaling, game.player.maxHp)  # Scale current HP but cap at maxHp
  game.player.damage *= waveScaling
  game.player.speed *= waveScaling
  game.player.baseSpeed *= waveScaling
  game.player.bulletSpeed = multiplyBulletSpeedDiminished(game.player.bulletSpeed, waveScaling)
  # Fire rate gets faster (lower number = faster), so we divide instead of multiply
  game.player.fireRate /= waveScaling

  # Reset all active ability cooldowns for new wave
  game.player.timeWarpUsesThisWave = 0
  game.player.timeWarpCooldown = 0
  game.player.phaseShiftCooldown = 0
  game.player.bloodPactCooldown = 0
  game.player.conduitCooldown = 0
  game.player.aftershockCooldown = 0
  game.player.novaCooldown = 0
  # Release any frozen Nova bullets before resetting
  if game.player.novaActive:
    for bullet in game.bullets:
      if bullet.isFrozenByNova and bullet.fromPlayer:
        bullet.vel = bullet.vel * 1.5
        bullet.isFrozenByNova = false
        bullet.isFromNova = true  # Mark for damage tracking
    game.player.novaActive = false
    game.player.novaFreezeTimer = 0
  # Reset Celestial Veil charge for new wave
  if hasPowerUp(game.player, puCelestialVeil):
    game.player.celestialVeilActive = true

proc spawnWaveEnemies*(game: Game, count: int) =
  # Spawn multiple enemies at once
  for _ in 0..<count:
    if game.waveEnemiesRemaining > 0:
      let wave: int = game.currentWave
      let roll: int = rand(100)
      var enemyType: EnemyType

      # NEW ENEMY EVERY 5 WAVES with high spawn rate for that enemy
      if wave <= 5:
        # Waves 1-5: Only CIRCLES
        enemyType = etCircle

      elif wave <= 10:
        # Waves 6-10: Introduce PENTAGON
        if roll < 40: enemyType = etPentagon
        elif roll < 75: enemyType = etCircle
        else: enemyType = etCircle  # Keep it simple

      elif wave <= 15:
        # Waves 11-15: Introduce TRIANGLE
        if roll < 40: enemyType = etTriangle
        elif roll < 65: enemyType = etCircle
        else: enemyType = etPentagon

      elif wave <= 20:
        # Waves 16-20: Introduce CUBE
        if roll < 25: enemyType = etCube
        elif roll < 40: enemyType = etCircle
        elif roll < 65: enemyType = etPentagon
        else: enemyType = etTriangle

      elif wave <= 25:
        # Waves 21-25: Introduce STAR, but keep the first tanky roster step gentler
        if roll < 12: enemyType = etStar
        elif roll < 28: enemyType = etCircle
        elif roll < 48: enemyType = etCube
        elif roll < 68: enemyType = etPentagon
        else: enemyType = etTriangle

      elif wave <= 30:
        # Waves 26-30: Introduce CROSS with a shallower composition swing
        if roll < 15: enemyType = etCross
        elif roll < 30: enemyType = etCircle
        elif roll < 45: enemyType = etCube
        elif roll < 57: enemyType = etStar
        elif roll < 75: enemyType = etPentagon
        else: enemyType = etTriangle

      elif wave <= 35:
        # Waves 31-35: Introduce DIAMOND, circles removed from wave 30+
        if roll < 16: enemyType = etDiamond
        elif roll < 33: enemyType = etCube
        elif roll < 47: enemyType = etStar
        elif roll < 63: enemyType = etCross
        elif roll < 80: enemyType = etPentagon
        else: enemyType = etTriangle

      elif wave <= 40:
        # Waves 36-40: Introduce OCTAGON
        if roll < 17: enemyType = etOctagon
        elif roll < 33: enemyType = etCube
        elif roll < 44: enemyType = etStar
        elif roll < 60: enemyType = etCross
        elif roll < 74: enemyType = etDiamond
        elif roll < 85: enemyType = etPentagon
        else: enemyType = etTriangle

      elif wave <= 45:
        # Waves 41-45: Introduce HEXAGON
        if roll < 18: enemyType = etHexagon
        elif roll < 25: enemyType = etCube
        elif roll < 35: enemyType = etStar
        elif roll < 55: enemyType = etCross
        elif roll < 73: enemyType = etDiamond
        elif roll < 81: enemyType = etOctagon
        elif roll < 89: enemyType = etPentagon
        else: enemyType = etTriangle

      elif wave <= 50:
        # Waves 46-50: Introduce TRICKSTER
        if roll < 20: enemyType = etTrickster
        elif roll < 33: enemyType = etCube
        elif roll < 39: enemyType = etStar
        elif roll < 48: enemyType = etCross
        elif roll < 56: enemyType = etDiamond
        elif roll < 64: enemyType = etOctagon
        elif roll < 72: enemyType = etHexagon
        elif roll < 85: enemyType = etPentagon
        else: enemyType = etTriangle

      elif wave <= 55:
        # Waves 51-55: Introduce PHANTOM
        if roll < 15: enemyType = etPhantom
        elif roll < 26: enemyType = etCube
        elif roll < 35: enemyType = etStar
        elif roll < 43: enemyType = etCross
        elif roll < 51: enemyType = etDiamond
        elif roll < 59: enemyType = etOctagon
        elif roll < 67: enemyType = etHexagon
        elif roll < 80: enemyType = etTrickster
        elif roll < 99: enemyType = etPentagon
        else: enemyType = etSniper

      else:
        # Waves 56+: Introduce MAGE + balanced roster
        if roll < 10: enemyType = etMage
        elif roll < 20: enemyType = etCube
        elif roll < 30: enemyType = etStar
        elif roll < 40: enemyType = etCross
        elif roll < 50: enemyType = etDiamond
        elif roll < 60: enemyType = etOctagon
        elif roll < 70: enemyType = etHexagon
        elif roll < 80: enemyType = etTrickster
        elif roll < 90: enemyType = etPhantom
        elif roll < 99: enemyType = etTriangle
        else: enemyType = etSniper

      # Wave enemies now use a softer difficulty slope so midgame HP does not outrun builds.
      let baseDifficulty = (wave - 1).float32 / 4.0

      let side = rand(3)
      var x, y: float32
      case side
      of 0: x = rand(game.screenWidth.int).float32; y = -30
      of 1: x = game.screenWidth.float32 + 30; y = rand(game.screenHeight.int).float32
      of 2: x = rand(game.screenWidth.int).float32; y = game.screenHeight.float32 + 30
      else: x = -30; y = rand(game.screenHeight.int).float32

      let enemy = newEnemy(x, y, baseDifficulty, enemyType, game)
      makeElite(enemy, wave)  # Chance to make enemy elite based on wave
      game.enemies.add(enemy)
      game.waveEnemiesRemaining -= 1

proc spawnDungeonEnemies*(game: Game, count: int) =
  ## Roguelite dungeon rooms: spawn from the floor theme's roster, scaled by
  ## floor/room depth/heat instead of the wave number.
  let run = game.rogueliteRun
  if run == nil or run.floor == nil:
    return
  let room = currentDungeonRoom(run)
  if room == nil:
    return
  let baseDifficulty = dungeonEnemyDifficulty(run, room)
  let eliteRoll = dungeonEliteRoll(run, room)
  for _ in 0..<count:
    if game.waveEnemiesRemaining <= 0:
      break
    let enemyType = rollEncounterEnemyType(run, room)
    let side = rand(3)
    var x, y: float32
    case side
    of 0: x = rand(game.screenWidth.int).float32; y = -30
    of 1: x = game.screenWidth.float32 + 30; y = rand(game.screenHeight.int).float32
    of 2: x = rand(game.screenWidth.int).float32; y = game.screenHeight.float32 + 30
    else: x = -30; y = rand(game.screenHeight.int).float32

    let enemy = newEnemy(x, y, baseDifficulty, enemyType, game)
    # Compress advanced types' stats toward the room threat before elite
    # bonuses so elites scale relative to the tuned baseline. The elite roll
    # only drives the CHANCE; stat magnitudes follow the room's wave
    # equivalent so elite-room guarantees don't inflate elite damage.
    tuneDungeonEnemyStats(enemy, run, room)
    makeElite(enemy, eliteRoll,
              scalingWave = int(dungeonRoomWaveEquivalent(run, room)))
    var visualThreat = 1 + (run.floorNumber - 1) + (run.heat div 2) + run.endlessLoop
    if room.kind == drkElite:
      visualThreat += 1
    if enemy.isElite:
      visualThreat += 1
    if enemy.contactDamage >= game.player.maxHp * 0.45:
      visualThreat = max(visualThreat, 4)
    enemy.threatLevel = max(enemy.threatLevel, clamp(visualThreat, 1, 5))
    game.enemies.add(enemy)
    game.waveEnemiesRemaining -= 1

proc checkWaveComplete*(game: Game): bool =
  # Wave is complete when all enemies are defeated, none remain to spawn,
  # AND boss coin has been collected (if there was one)
  return game.waveEnemiesRemaining == 0 and game.enemies.len == 0 and not game.bossWaveManager.isBossCoinActive()

proc advanceWave*(game: Game) =
  game.currentWave += 1
  game.wavesUntilBoss -= 1

  if game.comebackBonusActive and game.currentWave >= game.comebackEndWave:
    removeComebackBonus(game)

  # Check if it's time for a boss (every 5 waves now)
  if game.wavesUntilBoss == 0:
    game.wavesUntilBoss = 4  # Reset counter - boss every 5 waves
    # Boss wave will be triggered in update loop

type BulletEffects = tuple[
  slow: float32,
  poison: float32,
  fire: float32,
  wind: float32
]

const WindBulletFlatDamageBonus = 0.5'f32

