import raylib, types, player, enemy, bullet, consumable, coin, wall, shop, particle, powerup, sound, random, math

proc newGame*(screenWidth, screenHeight: int32): Game =
  result = Game(
    state: gsPlaying,
    mode: gmWaveBased,  # Default to wave-based mode
    player: newPlayer(screenWidth.float32 / 2, screenHeight.float32 / 2),
    enemies: @[],
    bullets: @[],
    coins: @[],
    consumables: @[],
    walls: @[],
    particles: @[],
    attackWarnings: @[],
    lasers: @[],  # Initialize lasers array
    time: 0,
    spawnTimer: 0,
    bossTimer: 60.0,
    bossCount: 0,
    difficulty: 0,
    screenWidth: screenWidth,
    screenHeight: screenHeight,
    shopItems: initShopItems(),
    selectedShopItem: 0,
    menuSelection: 0,
    selectedPowerUp: 0,
    bossActive: false,
    bossSpawnTimer: 0,
    cameFromPowerUpSelect: false,
    gameOverSoundPlayed: false,
    # Wave-based mode fields
    currentWave: 1,
    wavesUntilBoss: 5,  # CHANGED: Boss appears every 5 waves instead of 3
    waveEnemiesRemaining: 0,
    waveEnemiesTotal: 0,
    waveInProgress: false
  )

proc calculateWaveEnemyCount(waveNumber: int): int =
  # Scale enemy count based on wave number (SLOWER PROGRESSION)
  # Start with 8 enemies, add 2-3 per wave
  result = 8 + (waveNumber - 1) * 2
  # Cap at 100 enemies per wave
  if result > 100:
    result = 100

proc startWave*(game: Game) =
  game.waveInProgress = true
  game.waveEnemiesTotal = calculateWaveEnemyCount(game.currentWave)
  game.waveEnemiesRemaining = game.waveEnemiesTotal
  game.spawnTimer = 0

proc spawnWaveEnemies*(game: Game, count: int) =
  # Spawn multiple enemies at once
  for _ in 0..<count:
    if game.waveEnemiesRemaining > 0:
      let wave = game.currentWave
      let roll = rand(100)
      var enemyType: EnemyType

      # Progressive enemy variety (matching difficulty-based progression)
      # Pentagon replaces early Cubes, Cubes appear later and buffed
      if wave <= 2:
        # Waves 1-2: Only circles - learn basics
        enemyType = etCircle
      elif wave <= 5:
        # Waves 3-5: Add Pentagon (easier ranged enemy)
        if roll < 80: enemyType = etCircle
        else: enemyType = etPentagon
      elif wave <= 8:
        # Waves 6-8: Add Triangles, CUBES START appearing
        if roll < 60: enemyType = etCircle
        elif roll < 80: enemyType = etPentagon
        elif roll < 95: enemyType = etTriangle
        else: enemyType = etCube
      elif wave <= 12:
        # Waves 9-12: Add Stars + Cross, Cubes more common
        if roll < 40: enemyType = etCircle
        elif roll < 55: enemyType = etPentagon
        elif roll < 65: enemyType = etCube
        elif roll < 80: enemyType = etTriangle
        elif roll < 90: enemyType = etStar
        else: enemyType = etCross
      elif wave <= 16:
        # Waves 13-16: Add Diamond + Octagon
        if roll < 25: enemyType = etCircle
        elif roll < 38: enemyType = etPentagon
        elif roll < 50: enemyType = etCube
        elif roll < 62: enemyType = etTriangle
        elif roll < 75: enemyType = etStar
        elif roll < 83: enemyType = etCross
        elif roll < 91: enemyType = etDiamond
        else: enemyType = etOctagon
      elif wave <= 21:
        # Waves 17-21: Add Hexagon
        if roll < 18: enemyType = etCircle
        elif roll < 30: enemyType = etPentagon
        elif roll < 42: enemyType = etCube
        elif roll < 54: enemyType = etTriangle
        elif roll < 66: enemyType = etStar
        elif roll < 74: enemyType = etCross
        elif roll < 82: enemyType = etDiamond
        elif roll < 91: enemyType = etOctagon
        else: enemyType = etHexagon
      elif wave <= 27:
        # Waves 22-27: Add Trickster
        if roll < 12: enemyType = etCircle
        elif roll < 22: enemyType = etPentagon
        elif roll < 32: enemyType = etCube
        elif roll < 42: enemyType = etTriangle
        elif roll < 54: enemyType = etStar
        elif roll < 63: enemyType = etCross
        elif roll < 72: enemyType = etDiamond
        elif roll < 82: enemyType = etOctagon
        elif roll < 91: enemyType = etHexagon
        else: enemyType = etTrickster
      else:
        # Waves 28+: All enemies including Phantom
        if roll < 10: enemyType = etCircle
        elif roll < 18: enemyType = etPentagon
        elif roll < 26: enemyType = etCube
        elif roll < 34: enemyType = etTriangle
        elif roll < 44: enemyType = etStar
        elif roll < 52: enemyType = etCross
        elif roll < 60: enemyType = etDiamond
        elif roll < 70: enemyType = etOctagon
        elif roll < 78: enemyType = etHexagon
        elif roll < 89: enemyType = etTrickster
        else: enemyType = etPhantom
      
      # Difficulty scaling
      let baseDifficulty = (wave - 1).float32 / 3.0
      
      let side = rand(3)
      var x, y: float32
      case side
      of 0: x = rand(game.screenWidth.int).float32; y = -30
      of 1: x = game.screenWidth.float32 + 30; y = rand(game.screenHeight.int).float32
      of 2: x = rand(game.screenWidth.int).float32; y = game.screenHeight.float32 + 30
      else: x = -30; y = rand(game.screenHeight.int).float32
      
      game.enemies.add(newEnemy(x, y, baseDifficulty, enemyType))
      game.waveEnemiesRemaining -= 1

proc spawnWaveEnemy*(game: Game) =
  if game.waveEnemiesRemaining > 0:
    # Progressive enemy variety based on wave number (mimics time survival progression)
    # Map waves to equivalent time survival difficulty for consistent balance
    let wave = game.currentWave
    let roll = rand(100)
    var enemyType: EnemyType
    
    if wave <= 2:
      # Waves 1-2: Only circles (tutorial waves)
      enemyType = etCircle
    
    elif wave <= 4:
      # Waves 3-4: Introduce cubes (ranged enemies)
      if roll < 80: enemyType = etCircle
      else: enemyType = etCube
    
    elif wave <= 6:
      # Waves 5-6: Add triangles (dash enemies, swapped with hexagon)
      if roll < 65: enemyType = etCircle
      elif roll < 85: enemyType = etCube
      else: enemyType = etTriangle
    
    elif wave <= 10:
      # Waves 7-10: Add stars (tanky enemies)
      if roll < 45: enemyType = etCircle
      elif roll < 55: enemyType = etCube
      elif roll < 70: enemyType = etTriangle
      else: enemyType = etStar
    
    elif wave <= 15:
      # Waves 11-15: Add hexagons (teleporting chaos, moved later)
      if roll < 30: enemyType = etCircle
      elif roll < 40: enemyType = etCube
      elif roll < 55: enemyType = etTriangle
      elif roll < 75: enemyType = etStar
      else: enemyType = etHexagon
    
    else:
      # Wave 16+: Balanced chaos - all enemy types
      if roll < 20: enemyType = etCircle
      elif roll < 35: enemyType = etCube
      elif roll < 55: enemyType = etTriangle
      elif roll < 70: enemyType = etStar
      else: enemyType = etHexagon
    
    # Difficulty scaling: increase every 3 waves (similar to time survival's 30s intervals)
    let baseDifficulty = (wave - 1).float32 / 3.0
    let strengthMultiplier = pow(1.15, baseDifficulty)
    
    # Spawn enemy at calculated difficulty
    let side = rand(3)
    var x, y: float32
    
    case side
    of 0: x = rand(game.screenWidth.int).float32; y = -30
    of 1: x = game.screenWidth.float32 + 30; y = rand(game.screenHeight.int).float32
    of 2: x = rand(game.screenWidth.int).float32; y = game.screenHeight.float32 + 30
    else: x = -30; y = rand(game.screenHeight.int).float32
    
    game.enemies.add(newEnemy(x, y, baseDifficulty, enemyType))
    game.waveEnemiesRemaining -= 1

proc checkWaveComplete*(game: Game): bool =
  # Wave is complete when all enemies are defeated and none remain to spawn
  return game.waveEnemiesRemaining == 0 and game.enemies.len == 0

proc advanceWave*(game: Game) =
  game.currentWave += 1
  game.wavesUntilBoss -= 1
  
  # Check if it's time for a boss (every 5 waves now)
  if game.wavesUntilBoss == 0:
    game.wavesUntilBoss = 5  # Reset counter - boss every 5 waves
    # Boss wave will be triggered in update loop

proc shootBullet*(game: Game, direction: Vector2f) =
  let currentFireRate = getCurrentFireRate(game.player)
  if game.time - game.player.lastShot >= currentFireRate:
    # Check for power-ups that modify shooting
    let hasHoming = hasPowerUp(game.player, puHomingBullets)
    let hasPiercing = hasPowerUp(game.player, puPiercingShots)
    let hasExplosive = hasPowerUp(game.player, puExplosiveBullets)
    let hasDoubleShot = hasPowerUp(game.player, puDoubleShot)
    let hasMultiShot = hasPowerUp(game.player, puMultiShot)
    let hasRicochet = hasPowerUp(game.player, puBulletRicochet)
    let hasSplit = hasPowerUp(game.player, puBulletSplit)
    let hasFrost = hasPowerUp(game.player, puFrostShots)
    let hasPoison = hasPowerUp(game.player, puPoisonDamage)
    
    # Base bullet properties - use current damage with Rage bonus
    var speed = game.player.bulletSpeed * 1.2
    var damage = getCurrentDamage(game.player)
    var bulletRadius = 4.0
    
    # Apply bullet size power-up
    if hasPowerUp(game.player, puBulletSize):
      let sizeLevel = getPowerUpLevel(game.player, puBulletSize)
      let sizeMultiplier = case sizeLevel
        of 1: 1.4
        of 2: 1.8
        else: 2.4
      bulletRadius *= sizeMultiplier
    
    # Apply critical hit chance
    if hasPowerUp(game.player, puCriticalHit):
      let critLevel = getPowerUpLevel(game.player, puCriticalHit)
      let critChance = case critLevel
        of 1: 15
        of 2: 20
        else: 25
      let critMultiplier = case critLevel
        of 1: 2.0
        of 2: 2.5
        else: 3.0
      if rand(99) < critChance:
        damage *= critMultiplier
    
    # Calculate slow and poison effects
    var slowEffect = 0.0
    var poisonEffect = 0.0
    if hasFrost:
      let frostLevel = getPowerUpLevel(game.player, puFrostShots)
      slowEffect = case frostLevel
        of 1: 0.25
        of 2: 0.4
        else: 0.6
    if hasPoison:
      let poisonLevel = getPowerUpLevel(game.player, puPoisonDamage)
      poisonEffect = case poisonLevel
        of 1: 4.0
        of 2: 5.0
        else: 6.0
    
    if hasDoubleShot and hasMultiShot:
      # When both active: Fire multishot pattern, then schedule second burst
      let multiLevel = getPowerUpLevel(game.player, puMultiShot)
      let multiCount = case multiLevel
        of 1: 2
        of 2: 3
        else: 4
      let spreadAngle = if multiLevel == 1: 0.2 elif multiLevel == 2: 0.3 else: 0.4
      let doubleLevel = getPowerUpLevel(game.player, puDoubleShot)
      let burstCount = doubleLevel + 3  # Level 1 = 2 bursts, Level 2 = 3, Level 3 = 4
      
      # Fire first burst
      for i in 0..<multiCount:
        let angle = (i.float32 - (multiCount - 1).float32 / 2.0) * spreadAngle
        let spreadDir = newVector2f(
          direction.x * cos(angle) - direction.y * sin(angle),
          direction.x * sin(angle) + direction.y * cos(angle)
        )
        let bullet = newBullet(game.player.pos.x, game.player.pos.y, spreadDir, 
                              speed, damage, true, hasHoming, hasPiercing, hasExplosive,
                              hasRicochet, hasSplit, slowEffect, poisonEffect)
        bullet.radius = bulletRadius
        game.bullets.add(bullet)
      
      # Schedule remaining bursts with small delays (rapid succession)
      game.player.doubleShotDelay = 0.08 * (burstCount - 1).float32
    
    elif hasDoubleShot:
      # Fire in quick succession (. .) pattern
      let level = getPowerUpLevel(game.player, puDoubleShot)
      let burstCount = level + 3  # Level 1 = 2, Level 2 = 3, Level 3 = 4
      
      # Fire first bullet immediately
      let bullet = newBullet(game.player.pos.x, game.player.pos.y, direction, 
                            speed, damage, true, hasHoming, hasPiercing, hasExplosive,
                            hasRicochet, hasSplit, slowEffect, poisonEffect)
      bullet.radius = bulletRadius
      game.bullets.add(bullet)
      
      # Schedule remaining bullets with small delays (0.08s between each)
      game.player.doubleShotDelay = 0.08 * (burstCount - 1).float32
    elif hasMultiShot:
      # Shoot in multiple directions
      let level = getPowerUpLevel(game.player, puMultiShot)
      let bulletCount = case level
        of 1: 2
        of 2: 3
        else: 4
      let spreadAngle = if level == 1: 0.2 elif level == 2: 0.3 else: 0.4
      
      for i in 0..<bulletCount:
        let angle = (i.float32 - (bulletCount - 1).float32 / 2.0) * spreadAngle
        let spreadDir = newVector2f(
          direction.x * cos(angle) - direction.y * sin(angle),
          direction.x * sin(angle) + direction.y * cos(angle)
        )
        let bullet = newBullet(game.player.pos.x, game.player.pos.y, spreadDir, 
                              speed, damage, true, hasHoming, hasPiercing, hasExplosive,
                              hasRicochet, hasSplit, slowEffect, poisonEffect)
        bullet.radius = bulletRadius
        game.bullets.add(bullet)
    else:
      # Normal single shot
      let bullet = newBullet(game.player.pos.x, game.player.pos.y, direction, 
                            speed, damage, true, hasHoming, hasPiercing, hasExplosive,
                            hasRicochet, hasSplit, slowEffect, poisonEffect)
      bullet.radius = bulletRadius
      game.bullets.add(bullet)
    
    game.player.lastShot = game.time
    
    # Play shoot sound
    playSound(stShoot, 0.3)
    
    # Determine particle color based on bullet type - MATCHES BULLET COLOR
    var particleColor = Yellow  # Default
    if hasHoming: particleColor = Magenta
    elif hasPiercing: particleColor = SkyBlue
    elif hasExplosive: particleColor = Orange
    elif slowEffect > 0: particleColor = Color(r: 150, g: 200, b: 255, a: 255)
    elif poisonEffect > 0: particleColor = Green
    elif hasRicochet: particleColor = Color(r: 255, g: 200, b: 0, a: 255)
    
    # Add muzzle flash particles with matching color
    spawnExplosion(game.particles, game.player.pos.x, game.player.pos.y, particleColor, 5)

# Helper to fire delayed double-shot bursts
proc fireDoubleShotBurst*(game: Game, direction: Vector2f, hasMultiShot: bool) =
  let hasHoming = hasPowerUp(game.player, puHomingBullets)
  let hasPiercing = hasPowerUp(game.player, puPiercingShots)
  let hasExplosive = hasPowerUp(game.player, puExplosiveBullets)
  let hasRicochet = hasPowerUp(game.player, puBulletRicochet)
  let hasSplit = hasPowerUp(game.player, puBulletSplit)
  let hasFrost = hasPowerUp(game.player, puFrostShots)
  let hasPoison = hasPowerUp(game.player, puPoisonDamage)
  
  var speed = game.player.bulletSpeed * 1.2
  var damage = getCurrentDamage(game.player)
  var bulletRadius = 4.0
  
  if hasPowerUp(game.player, puBulletSize):
    let sizeLevel = getPowerUpLevel(game.player, puBulletSize)
    let sizeMultiplier = case sizeLevel
      of 1: 1.4
      of 2: 1.8
      else: 2.4
    bulletRadius *= sizeMultiplier
  
  var slowEffect = 0.0
  var poisonEffect = 0.0
  if hasFrost:
    let frostLevel = getPowerUpLevel(game.player, puFrostShots)
    slowEffect = case frostLevel
      of 1: 0.25
      of 2: 0.4
      else: 0.6
  if hasPoison:
    let poisonLevel = getPowerUpLevel(game.player, puPoisonDamage)
    poisonEffect = case poisonLevel
      of 1: 4.0
      of 2: 5.0
      else: 6.0
  
  if hasMultiShot:
    let multiLevel = getPowerUpLevel(game.player, puMultiShot)
    let multiCount = case multiLevel
      of 1: 2
      of 2: 3
      else: 4
    let spreadAngle = if multiLevel == 1: 0.2 elif multiLevel == 2: 0.3 else: 0.4
    
    for i in 0..<multiCount:
      let angle = (i.float32 - (multiCount - 1).float32 / 2.0) * spreadAngle
      let spreadDir = newVector2f(
        direction.x * cos(angle) - direction.y * sin(angle),
        direction.x * sin(angle) + direction.y * cos(angle)
      )
      let bullet = newBullet(game.player.pos.x, game.player.pos.y, spreadDir, 
                            speed, damage, true, hasHoming, hasPiercing, hasExplosive,
                            hasRicochet, hasSplit, slowEffect, poisonEffect)
      bullet.radius = bulletRadius
      game.bullets.add(bullet)
  else:
    let bullet = newBullet(game.player.pos.x, game.player.pos.y, direction, 
                          speed, damage, true, hasHoming, hasPiercing, hasExplosive,
                          hasRicochet, hasSplit, slowEffect, poisonEffect)
    bullet.radius = bulletRadius
    game.bullets.add(bullet)
  
  playSound(stShoot, 0.25)

proc updateGame*(game: var Game, dt: float32) =
  # Handle boss spawn warning timer (non-blocking)
  if game.bossSpawnTimer > 0:
    game.bossSpawnTimer -= dt
  
  # Always update game time
  game.time += dt
  
  game.spawnTimer += dt
  game.difficulty = game.time / 10.0  # Difficulty increases every 10 seconds
  
  # Update attack warnings
  var i = 0
  while i < game.attackWarnings.len:
    game.attackWarnings[i].lifetime -= dt
    if game.attackWarnings[i].lifetime <= 0:
      game.attackWarnings.delete(i)
      continue
    i += 1
  
  # Update lasers and check collision with player
  var j = 0
  while j < game.lasers.len:
    game.lasers[j].lifetime -= dt
    
    # Check if player is hit by laser (only once per laser)
    if not game.lasers[j].hasHitPlayer and game.player.invincibilityTimer <= 0:
      let laser = game.lasers[j]
      let dx = game.player.pos.x - laser.pos.x
      let dy = game.player.pos.y - laser.pos.y
      
      var hit = false
      case laser.direction
      of 0:  # Horizontal laser
        if abs(dy) < laser.thickness and abs(dx) < laser.length:
          hit = true
      of 1:  # Vertical laser
        if abs(dx) < laser.thickness and abs(dy) < laser.length:
          hit = true
      of 2:  # Cross (both horizontal and vertical)
        if (abs(dy) < laser.thickness and abs(dx) < laser.length) or
           (abs(dx) < laser.thickness and abs(dy) < laser.length):
          hit = true
      else:
        discard
      
      if hit:
        takeDamage(game.player, laser.damage.float32)
        game.lasers[j].hasHitPlayer = true
        if game.player.hp <= 0:
          game.state = gsGameOver
    
    # Remove expired lasers
    if game.lasers[j].lifetime <= 0:
      game.lasers.delete(j)
      continue
    j += 1
  
  # Update player (with wall collision)
  updatePlayer(game.player, dt, game.screenWidth, game.screenHeight, game.walls)
  
  # Damage zone power-up effect
  if hasPowerUp(game.player, puDamageZone):
    let level = getPowerUpLevel(game.player, puDamageZone)
    let zoneDamage = case level
      of 1: 2.0
      of 2: 5.0
      else: 10.0
    let zoneRadius = case level
      of 1: 50.0
      of 2: 100.0
      else: 150.0
    
    for enemy in game.enemies:
      let dist = distance(game.player.pos, enemy.pos)
      if dist < zoneRadius:
        enemy.hp -= zoneDamage * dt
  
  # Regeneration power-up effect - NERFED
  if hasPowerUp(game.player, puRegeneration):
    game.player.regenTimer += dt
    let level = getPowerUpLevel(game.player, puRegeneration)
    let regenInterval = case level
      of 1: 15.0  # NERFED from 12s to 15s
      of 2: 11.0  # NERFED from 8s to 11s
      else: 8.0   # NERFED from 5s to 8s
    
    if game.player.regenTimer >= regenInterval:
      heal(game.player, 1)
      game.player.regenTimer = 0
      spawnExplosion(game.particles, game.player.pos.x, game.player.pos.y, Green, 10)
  
  # Slow Field power-up effect - NERFED for balance
  if hasPowerUp(game.player, puSlowField):
    let level = getPowerUpLevel(game.player, puSlowField)
    let slowPercent = case level
      of 1: 0.30  # NERFED from 50% to 30% slow
      of 2: 0.45  # NERFED from 65% to 45% slow
      else: 0.55  # NERFED from 75% to 55% slow
    let slowRadius = case level
      of 1: 120.0  # NERFED from 150 to 120
      of 2: 160.0  # NERFED from 200 to 160
      else: 200.0  # NERFED from 250 to 200
    
    for enemy in game.enemies:
      let dist = distance(game.player.pos, enemy.pos)
      if dist < slowRadius:
        # Apply slow effect
        enemy.slowTimer = 0.2  # Refresh slow duration
        enemy.slowAmount = slowPercent
      else:
        # Decay slow effect when outside range
        if enemy.slowTimer > 0:
          enemy.slowTimer -= dt
          if enemy.slowTimer <= 0:
            enemy.slowAmount = 0

  
  # Check shooting
  let mousePos = getMousePosition()
  let shootDir = newVector2f(mousePos.x - game.player.pos.x, mousePos.y - game.player.pos.y)
  
  # Handle delayed double-shot bursts (rapid succession)
  if game.player.doubleShotDelay > 0:
    let prevDelay = game.player.doubleShotDelay
    game.player.doubleShotDelay -= dt
    
    # Fire burst when delay crosses 0.08s threshold
    if prevDelay > 0.08 and game.player.doubleShotDelay <= 0.08:
      let hasMultiShot = hasPowerUp(game.player, puMultiShot)
      fireDoubleShotBurst(game, shootDir, hasMultiShot)
    
    # Fire additional bursts for level 2 and 3
    if prevDelay > 0.16 and game.player.doubleShotDelay <= 0.16:
      let hasMultiShot = hasPowerUp(game.player, puMultiShot)
      fireDoubleShotBurst(game, shootDir, hasMultiShot)
    
    # Clamp to 0
    if game.player.doubleShotDelay < 0:
      game.player.doubleShotDelay = 0
  
  if isMouseButtonDown(Left) or isKeyDown(Space):
    if shootDir.length() > 0:
      shootBullet(game, shootDir)
  
  # Auto-shoot (now a toggleable power-up!) - Toggle handled in main.nim with F key
  if hasPowerUp(game.player, puAutoShoot) and game.player.autoShootEnabled and game.enemies.len > 0:
    let autoLevel = getPowerUpLevel(game.player, puAutoShoot)
    
    # Auto-shoot has reduced fire rate and range at lower levels
    let autoFireMult = case autoLevel
      of 1: 0.6   # 60% of normal fire rate
      of 2: 0.8   # 80% of normal fire rate
      else: 1.0   # Full fire rate at level 3
    
    let autoRange = case autoLevel
      of 1: 250.0
      of 2: 350.0
      else: 450.0
    
    let autoFireRate = getCurrentFireRate(game.player) / autoFireMult
    if game.time - game.player.lastShot >= autoFireRate:
      var nearestEnemy: Enemy = nil
      var nearestDist = autoRange
      
      for enemy in game.enemies:
        let dist = distance(game.player.pos, enemy.pos)
        if dist < nearestDist:
          nearestDist = dist
          nearestEnemy = enemy
      
      if nearestEnemy != nil:
        let dir = nearestEnemy.pos - game.player.pos
        shootBullet(game, dir)
  
  # MODE-SPECIFIC ENEMY SPAWNING
  if game.mode == gmWaveBased:
    # WAVE-BASED MODE: Spawn enemies in defined waves
    if not game.waveInProgress and not game.bossActive and game.state == gsPlaying:
      # Start a new wave
      startWave(game)
    
    if game.waveInProgress and game.bossSpawnTimer <= 0:
      # DYNAMIC MULTIPLE ENEMY SPAWNING
      # Spawn 1-3 enemies at once based on wave progression
      let spawnCount = if game.currentWave <= 3: 1
                      elif game.currentWave <= 7: (if rand(100) < 50: 1 else: 2)
                      elif game.currentWave <= 12: (if rand(100) < 30: 1 elif rand(100) < 70: 2 else: 3)
                      else: (if rand(100) < 20: 1 elif rand(100) < 50: 2 else: 3)
      
      # SLOWER SPAWN RATE - increased from 0.6-0.8 to 0.8-1.2
      let baseSpawnRate = if game.currentWave <= 3: 1.0
                         elif game.currentWave <= 7: 1.1
                         elif game.currentWave <= 12: 1.15
                         else: 1.2
      
      if game.spawnTimer > baseSpawnRate and game.waveEnemiesRemaining > 0:
        spawnWaveEnemies(game, spawnCount)
        game.spawnTimer = 0
      
      # Check if wave is complete
      if checkWaveComplete(game):
        game.waveInProgress = false
        
        # Play wave complete sound
        playSound(stWaveComplete)

        # Advance wave counters so the next wave uses the next wave number
        game.currentWave += 1
        game.wavesUntilBoss -= 1

        # ADJUSTED: Power-ups less frequent (every 2 waves instead of every wave)
        let shouldOfferPowerUp = (game.currentWave mod 2) == 0
        
        # If wavesUntilBoss reached zero, schedule a boss wave next (no pause needed)
        if game.wavesUntilBoss <= 0:
          # Trigger boss warning for 1.5 seconds, but gameplay continues
          game.bossSpawnTimer = 1.5
          # ALWAYS offer power-up before boss (critical moment)
          game.powerUpChoices = generatePowerUpChoices(game.player, false)
          game.selectedPowerUp = 0
          game.state = gsPowerUpSelect
        elif shouldOfferPowerUp:
          # Regular wave complete: show power-up choices (every 2 waves)
          game.powerUpChoices = generatePowerUpChoices(game.player, false)
          game.selectedPowerUp = 0
          game.state = gsPowerUpSelect
        # Otherwise, wave completes and next wave starts immediately
    
    # Boss wave spawning
    if game.wavesUntilBoss == 0 and not game.bossActive and game.state == gsPlaying:
      game.bossCount += 1
      # Scale boss difficulty based on wave number (every 3 waves = +1 difficulty)
      let bossDifficulty = (game.currentWave - 1).float32 / 3.0
      game.enemies.add(spawnBoss(game.screenWidth, game.screenHeight, 
                                bossDifficulty, game.bossCount))
      game.bossActive = true
      game.bossSpawnTimer = 1.5  # Short warning, doesn't pause gameplay
      game.wavesUntilBoss = 5  # Reset for next boss (every 5 waves)
      
      # Play boss spawn sound
      playSound(stBossSpawn)
      
      # Entrance particles
      let boss = game.enemies[^1]
      case boss.bossType
      of btShooter:
        for i in 0..<60:
          let angle = i.float32 * 0.1
          let dist = i.float32 * 3
          let x = boss.pos.x + cos(angle) * dist
          let y = boss.pos.y + sin(angle) * dist
          spawnExplosion(game.particles, x, y, Purple, 3)
      of btSummoner:
        for ring in 0..4:
          spawnShockwave(game.particles, boss.pos.x, boss.pos.y, ring.float32 * 50 + 50)
      of btCharger:
        for i in 0..20:
          let x = boss.pos.x - i.float32 * 15
          spawnExplosion(game.particles, x, boss.pos.y, Blue, 5)
      of btOrbit:
        for i in 0..<40:
          let angle = i.float32 * PI * 2.0 / 40.0
          let dist = 80.0
          let x = boss.pos.x + cos(angle) * dist
          let y = boss.pos.y + sin(angle) * dist
          spawnExplosion(game.particles, x, y, Violet, 4)
  
  else:
    # TIME SURVIVAL MODE: Original time-based spawning
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
    
    let waveSpawnRate = baseSpawnRate * 0.7
    let waveProgress = (game.time mod 15.0) / 15.0
    let isWaveActive = waveProgress > 0.6
    
    var currentSpawnRate = if isWaveActive: waveSpawnRate else: baseSpawnRate
    if game.bossActive:
      currentSpawnRate = currentSpawnRate * 2.0
    
    if game.spawnTimer > currentSpawnRate:
      game.enemies.add(spawnEnemy(game.screenWidth, game.screenHeight, game.difficulty))
      game.spawnTimer = 0
      
      if isWaveActive and rand(100) < 60 and not game.bossActive:
        game.enemies.add(spawnEnemy(game.screenWidth, game.screenHeight, game.difficulty))
    
    # Boss spawn every 60 seconds
    if game.time >= game.bossTimer and not game.bossActive:
      game.bossCount += 1
      game.enemies.add(spawnBoss(game.screenWidth, game.screenHeight, game.difficulty, game.bossCount))
      game.bossTimer += 60.0
      game.bossActive = true
      game.bossSpawnTimer = 1.5  # Short warning, doesn't pause gameplay
      
      let boss = game.enemies[^1]
      case boss.bossType
      of btShooter:
        for i in 0..<60:
          let angle = i.float32 * 0.1
          let dist = i.float32 * 3
          let x = boss.pos.x + cos(angle) * dist
          let y = boss.pos.y + sin(angle) * dist
          spawnExplosion(game.particles, x, y, Purple, 3)
      of btSummoner:
        for ring in 0..4:
          spawnShockwave(game.particles, boss.pos.x, boss.pos.y, ring.float32 * 50 + 50)
      of btCharger:
        for i in 0..20:
          let x = boss.pos.x - i.float32 * 15
          spawnExplosion(game.particles, x, boss.pos.y, Blue, 5)
      of btOrbit:
        for i in 0..<40:
          let angle = i.float32 * PI * 2.0 / 40.0
          let dist = 80.0
          let x = boss.pos.x + cos(angle) * dist
          let y = boss.pos.y + sin(angle) * dist
          spawnExplosion(game.particles, x, y, Violet, 4)
  
  # Update enemies
  var enemyIdx = 0
  var bossDefeated = false
  while enemyIdx < game.enemies.len:
    let enemy = game.enemies[enemyIdx]
    
    # Update poison damage over time
    if enemy.poisonTimer > 0:
      enemy.poisonTimer -= dt
      enemy.hp -= enemy.poisonDamage * dt
      # Poison visual effect
      if (game.time * 10).int mod 3 == 0:
        spawnExplosion(game.particles, enemy.pos.x, enemy.pos.y, Green, 2)
    
    # Update chain lightning cooldown
    if enemy.chainLightningCooldown > 0:
      enemy.chainLightningCooldown -= dt
    
    if not updateEnemy(enemy, game.player.pos, dt, game.walls, game.time, game):
      # Enemy died - drop coins and particles
      
      # Play enemy death sound
      playSound(stEnemyDeath, if enemy.isBoss: 1.0 else: 0.4)
      
      let coinValue = if enemy.isBoss:
        # Boss drops scale with difficulty: 15 + 5 per difficulty level
        30 + (game.difficulty * 3.5).int
      else:
        # Regular enemies drop based on type
        case enemy.enemyType
        of etCircle: 1
        of etCube: 3           # More coins since it's now harder
        of etTriangle: 3
        of etStar: 5
        of etHexagon: 3
        of etCross: 3
        of etDiamond: 3
        of etOctagon: 2
        of etPentagon: 1       # Early game enemy, low coins
        of etTrickster: 4
        of etPhantom: 4
      
      game.coins.add(newCoin(enemy.pos.x, enemy.pos.y, coinValue))
      
      # Star explosion on death - damages player if too close
      if enemy.enemyType == etStar:
        const explosionRadius = 120.0  # LARGER explosion radius
        const explosionDamage = 2.0
        
        # Play explosion sound
        playSound(stExplosion, 0.8)
        
        # Check if player is in explosion radius
        let distToPlayer = distance(enemy.pos, game.player.pos)
        if distToPlayer < explosionRadius:
          takeDamage(game.player, explosionDamage)
          if game.player.hp <= 0:
            game.state = gsGameOver
        
        # Create MASSIVE explosion visual with multiple layers
        spawnExplosion(game.particles, enemy.pos.x, enemy.pos.y, 
                      Color(r: 255, g: 150, b: 0, a: 255), 60)  # More particles
        spawnExplosion(game.particles, enemy.pos.x, enemy.pos.y, 
                      Color(r: 255, g: 220, b: 100, a: 255), 40)  # Bright inner core
        # Add multiple shockwave rings for clarity
        spawnShockwave(game.particles, enemy.pos.x, enemy.pos.y, explosionRadius)
        spawnShockwave(game.particles, enemy.pos.x, enemy.pos.y, explosionRadius * 0.7)
        spawnShockwave(game.particles, enemy.pos.x, enemy.pos.y, explosionRadius * 0.4)
      
      # Death particles
      let particleColor = enemy.color
      spawnExplosion(game.particles, enemy.pos.x, enemy.pos.y, particleColor, 
                    if enemy.isBoss: 50 else: 15)
      
      # Drop consumable
      let dropChance = if enemy.isBoss: 80 elif enemy.enemyType == etStar: 40 else: 15
      if rand(99) < dropChance:
        game.consumables.add(newConsumable(enemy.pos.x, enemy.pos.y, game.difficulty))
      
      game.player.kills += 1
      
      # Life steal power-up effect
      if hasPowerUp(game.player, puLifeSteal):
        let level = getPowerUpLevel(game.player, puLifeSteal)
        game.player.killsSinceLastHeal += 1
        let healsPerKills = case level
          of 1: 10
          of 2: 7
          else: 4
        
        if game.player.killsSinceLastHeal >= healsPerKills:
          heal(game.player, 1)
          game.player.killsSinceLastHeal = 0
          spawnExplosion(game.particles, game.player.pos.x, game.player.pos.y, Green, 15)
      
      # Check if boss was defeated
      if enemy.isBoss:
        bossDefeated = true
        game.bossActive = false
        
        # Mode-specific boss defeat handling
        if game.mode == gmWaveBased:
          # Wave mode: advance wave and reset boss counter
          game.currentWave += 1
          game.wavesUntilBoss = 5  # Next boss in 5 waves
        # Time survival mode continues with existing logic
      
      game.enemies.delete(enemyIdx)
      continue
    
    # BOSS SPECIAL ATTACKS - HEAVILY BUFFED
    if enemy.isBoss:
      # Teleport ability
      if enemy.teleportTimer <= 0:
        # Short teleport burst
        let angle = rand(1.0) * PI * 2.0
        let teleportDist = 150 + rand(100).float32
        enemy.pos.x += cos(angle) * teleportDist
        enemy.pos.y += sin(angle) * teleportDist
        
        # Clamp to screen
        if enemy.pos.x < 50: enemy.pos.x = 50
        if enemy.pos.x > game.screenWidth.float32 - 50: enemy.pos.x = game.screenWidth.float32 - 50
        if enemy.pos.y < 50: enemy.pos.y = 50
        if enemy.pos.y > game.screenHeight.float32 - 50: enemy.pos.y = game.screenHeight.float32 - 50
        
        enemy.teleportTimer = 10.0 + rand(5.0)
        spawnExplosion(game.particles, enemy.pos.x, enemy.pos.y, Purple, 30)
      
      # Shockwave attack
      if enemy.shockwaveTimer <= 0:
        spawnShockwave(game.particles, enemy.pos.x, enemy.pos.y, enemy.radius + 100)
        
        # Spawn bullets in shockwave pattern
        for angle in 0..<16:
          let rad = angle.float32 * PI / 8.0
          let dir = newVector2f(cos(rad), sin(rad))
          game.bullets.add(newBullet(enemy.pos.x, enemy.pos.y, dir, 220, 1, false))
        
        enemy.shockwaveTimer = 5.0 + rand(3.0)
      
      # Phase-based attacks
      case enemy.bossPhase
      of bpCircle:
        # Original boss behavior
        case enemy.bossType
        of btShooter:  # Spiral shooter - MORE BULLETS
          if enemy.shootTimer > 0.8:  # Faster
            for angle in 0..<12:  # More bullets
              let rad = angle.float32 * PI / 6.0 + game.time * 2
              let dir = newVector2f(cos(rad), sin(rad))
              game.bullets.add(newBullet(enemy.pos.x, enemy.pos.y, dir, 240, 1, false))
            enemy.shootTimer = 0
        
        of btSummoner:  # Spawn minions - MORE MINIONS
          if enemy.spawnTimer > 3.0:  # Faster
            for _ in 0..3:  # More minions
              let angle = rand(1.0) * PI * 2
              let spawnDist = enemy.radius + 20
              let spawnX = enemy.pos.x + cos(angle) * spawnDist
              let spawnY = enemy.pos.y + sin(angle) * spawnDist
              game.enemies.add(newEnemy(spawnX, spawnY, game.difficulty, etCircle))
            enemy.spawnTimer = 0
        
        of btCharger:  # Dash attacks - FASTER
          if enemy.shootTimer > 2.0:  # Faster
            let dir = (game.player.pos - enemy.pos).normalize()
            enemy.vel = dir * enemy.speed * 4.0  # Faster dash
            enemy.shootTimer = 0
        
        of btOrbit:  # Orbiting projectiles - MORE CHAOS
          if enemy.shootTimer > 0.2:  # Much faster
            let angle = game.time * 4
            let orbitRadius = enemy.radius + 30
            for i in 0..<6:  # More bullets
              let a = angle + i.float32 * PI / 3.0
              let bulletX = enemy.pos.x + cos(a) * orbitRadius
              let bulletY = enemy.pos.y + sin(a) * orbitRadius
              let dir = (game.player.pos - newVector2f(bulletX, bulletY)).normalize()
              game.bullets.add(newBullet(bulletX, bulletY, dir, 200, 1, false))
            enemy.shootTimer = 0
      
      of bpCube:
        # Defensive phase - shoots in all directions
        if enemy.burstTimer > 1.0:
          for angle in 0..<8:
            let rad = angle.float32 * PI / 4.0
            let dir = newVector2f(cos(rad), sin(rad))
            game.bullets.add(newBullet(enemy.pos.x, enemy.pos.y, dir, 200, 1, false))
          enemy.burstTimer = 0
      
      of bpTriangle:
        # Aggressive phase - rapid dashes and shots
        if enemy.burstTimer > 0.5:
          let dir = (game.player.pos - enemy.pos).normalize()
          for i in 0..2:
            let spreadAngle = (i - 1).float32 * 0.3
            let spreadDir = newVector2f(
              dir.x * cos(spreadAngle) - dir.y * sin(spreadAngle),
              dir.x * sin(spreadAngle) + dir.y * cos(spreadAngle)
            )
            game.bullets.add(newBullet(enemy.pos.x, enemy.pos.y, spreadDir, 280, 1, false))
          enemy.burstTimer = 0
      
      of bpStar:
        # Bullet storm phase!
        if enemy.burstTimer > 0.15:
          let angle = rand(1.0) * PI * 2.0
          let dir = newVector2f(cos(angle), sin(angle))
          game.bullets.add(newBullet(enemy.pos.x, enemy.pos.y, dir, 250, 1, false))
          enemy.burstTimer = 0
    
    # Hexagon enemies shoot chaotically
    if enemy.enemyType == etHexagon and enemy.shootTimer > 1.2:
      # Shoot 2-4 bullets in random directions
      let bulletCount = 2 + rand(2)
      for _ in 0..<bulletCount:
        let angle = rand(1.0) * PI * 2.0
        let dir = newVector2f(cos(angle), sin(angle))
        game.bullets.add(newBullet(enemy.pos.x, enemy.pos.y, dir, 220, 1, false))
      enemy.shootTimer = 0
    
    # Cube enemies shoot - BUFFED
    if enemy.enemyType == etCube and enemy.shootTimer > 1.5:  # Faster
      let dir = (game.player.pos - enemy.pos).normalize()
      
      # Shoot 3-shot burst
      for i in 0..2:
        let spreadAngle = (i - 1).float32 * 0.2
        let spreadDir = newVector2f(
          dir.x * cos(spreadAngle) - dir.y * sin(spreadAngle),
          dir.x * sin(spreadAngle) + dir.y * cos(spreadAngle)
        )
        game.bullets.add(newBullet(enemy.pos.x, enemy.pos.y, spreadDir, 260, 1, false))
      
      enemy.shootTimer = 0
    
    # Check collision with player
    if distance(enemy.pos, game.player.pos) < enemy.radius + game.player.radius:
      if enemy.isBoss:
        # Boss deals continuous damage
        if game.time - enemy.lastContactDamageTime >= 0.5:  # 2 HP per second
          var bossContactDamage = enemy.damage.float32
          
          # Thorns reflection damage
          if hasPowerUp(game.player, puThorns):
            let thornsLevel = getPowerUpLevel(game.player, puThorns)
            let reflectPercent = case thornsLevel
              of 1: 0.20
              of 2: 0.40
              else: 0.70
            enemy.hp -= bossContactDamage * reflectPercent
            spawnExplosion(game.particles, enemy.pos.x, enemy.pos.y, Red, 8)
          
          takeDamage(game.player, bossContactDamage)
          playSound(stPlayerHit, 0.6)
          enemy.lastContactDamageTime = game.time
          spawnExplosion(game.particles, game.player.pos.x, game.player.pos.y, Red, 10)
          
          if game.player.hp <= 0:
            game.state = gsGameOver
      else:
        # Regular enemies die on contact
        var enemyContactDamage = enemy.damage.float32
        
        # Thorns reflection damage - kills enemy if damage exceeds HP
        if hasPowerUp(game.player, puThorns):
          let thornsLevel = getPowerUpLevel(game.player, puThorns)
          let reflectPercent = case thornsLevel
            of 1: 0.20
            of 2: 0.40
            else: 0.70
          let reflectedDamage = enemyContactDamage * reflectPercent
          enemy.hp -= reflectedDamage
          spawnExplosion(game.particles, enemy.pos.x, enemy.pos.y, Red, 6)
        
        takeDamage(game.player, enemyContactDamage)
        playSound(stPlayerHit, 0.5)
        enemy.hp = 0
        game.enemies.delete(enemyIdx)
        
        if game.player.hp <= 0:
          game.state = gsGameOver
        continue
    
    enemyIdx += 1
  
  # If boss was defeated, trigger power-up selection
  if bossDefeated:
    # Mode-specific boss defeat rewards
    if game.mode == gmWaveBased:
      # Wave mode: offer legendary upgrades
      game.powerUpChoices = generatePowerUpChoices(game.player, true)
    else:
      # Time survival: offer regular upgrades
      game.powerUpChoices = generatePowerUpChoices(game.player, false)
    
    game.selectedPowerUp = 0
    game.state = gsPowerUpSelect
    # Clear all enemies and bullets for clean screen
    game.enemies = @[]
    game.bullets = @[]
  
  # Update bullets
  i = 0
  while i < game.bullets.len:
    let bullet = game.bullets[i]
    
    # Homing bullet logic (NERFED at low levels)
    if bullet.isHoming and bullet.fromPlayer and game.enemies.len > 0:
      # Find nearest enemy
      var nearestEnemy: Enemy = nil
      var nearestDist = 999999.0
      
      for enemy in game.enemies:
        let dist = distance(bullet.pos, enemy.pos)
        if dist < nearestDist:
          nearestDist = dist
          nearestEnemy = enemy
      
      if nearestEnemy != nil:
        # HEAVILY NERFED tracking at level 1, noticeable at level 2, strong at level 3
        let level = getPowerUpLevel(game.player, puHomingBullets)
        let turnRate = case level
          of 1: 0.015  # VERY weak tracking, barely noticeable
          of 2: 0.06   # Moderate tracking
          else: 0.15   # Strong tracking
        
        let toEnemy = (nearestEnemy.pos - bullet.pos).normalize()
        let currentDir = bullet.vel.normalize()
        let newDir = (currentDir * (1.0 - turnRate) + toEnemy * turnRate).normalize()
        bullet.vel = newDir * bullet.vel.length()

    if not updateBullet(bullet, dt) or isOffScreen(bullet, game.screenWidth, game.screenHeight):
      game.bullets.delete(i)
      continue

    # Check rotating shield collision
    if not bullet.fromPlayer and hasPowerUp(game.player, puRotatingShield):
      let level = getPowerUpLevel(game.player, puRotatingShield)
      let shieldCount = level + 1
      let shieldRadius = game.player.radius * 2.5 + 15  # Reduced from +15 to +10
      var hitShield = false

      # Level-based coverage: NERFED - much smaller coverage
      let arcCoverage = case level
        of 1: 0.25  # Only 10% of each arc is active (was 15%)
        of 2: 0.35  # 20% coverage (was 30%)
        else: 0.45  # 35% coverage, significant gaps (was 50%)

      # Check collision with shield arcs (with gaps)
      for j in 0..<shieldCount:
        let baseAngle = game.player.shieldAngle + (j.float32 * PI * 2.0 / shieldCount.float32)
        let fullArcLength = PI * 2.0 / shieldCount.float32
        let activeArcLength = fullArcLength * arcCoverage

        # Center the active arc portion, leaving gaps at the edges
        let gapSize = (fullArcLength - activeArcLength) / 2.0
        let angle1 = baseAngle + gapSize
        let angle2 = angle1 + activeArcLength
        
        # Check multiple points along the ACTIVE portion of the arc
        for k in 0..12:  # Reduced from 16 to 12 points for thinner coverage
          let t = k.float32 / 12.0
          let angle = angle1 + t * (angle2 - angle1)
          let shieldX = game.player.pos.x + cos(angle) * shieldRadius
          let shieldY = game.player.pos.y + sin(angle) * shieldRadius
          let shieldPos = newVector2f(shieldX, shieldY)
          
          if distance(bullet.pos, shieldPos) < bullet.radius + 4:  # Reduced from +6 to +4
            hitShield = true
            playSound(stShield, 0.4)
            spawnExplosion(game.particles, shieldX, shieldY, SkyBlue, 8)
            break
        
        if hitShield:
          break
      
      if hitShield:
        game.bullets.delete(i)
        continue
    
    # Check bullet-enemy collision
    var hitEnemy = false
    if bullet.fromPlayer:
      for j in 0..<game.enemies.len:
        # Skip if this bullet already hit this enemy
        if j in bullet.hitEnemies:
          continue
          
        if checkBulletEnemyCollision(bullet, game.enemies[j]):
          # Mark this enemy as hit by this bullet
          bullet.hitEnemies.add(j)
          
          # Play enemy hit sound
          playSound(stEnemyHit, 0.3)
          
          if game.enemies[j].enemyType == etStar:
            # Stars use hit counter
            game.enemies[j].hitCount += 1
          else:
            game.enemies[j].hp -= bullet.damage
          hitEnemy = true
          
          # Apply frost shot slow effect - INDEFINITE (permanent until enemy dies)
          if bullet.slowAmount > 0 and hasPowerUp(game.player, puFrostShots):
            game.enemies[j].slowTimer = 999999.0  # Effectively infinite
            game.enemies[j].slowAmount = bullet.slowAmount
          
          # Apply poison damage over time
          if bullet.poisonDuration > 0 and hasPowerUp(game.player, puPoisonDamage):
            let poisonLevel = getPowerUpLevel(game.player, puPoisonDamage)
            let poisonDmg = case poisonLevel
              of 1: 1.0
              of 2: 2.0
              else: 4.0
            game.enemies[j].poisonTimer = bullet.poisonDuration
            game.enemies[j].poisonDamage = poisonDmg
          
          # Chain lightning effect - hits nearby enemies
          if hasPowerUp(game.player, puChainLightning) and game.enemies[j].chainLightningCooldown <= 0:
            let chainLevel = getPowerUpLevel(game.player, puChainLightning)
            let chainCount = chainLevel  # 1, 2, or 3 chains
            let chainDamage = case chainLevel
              of 1: 0.7
              of 2: 0.8
              else: 0.9
            let chainRange = 120.0
            
            # Mark this enemy to prevent re-chaining
            game.enemies[j].chainLightningCooldown = 0.3
            
            # Find nearby enemies to chain to
            var chained = 0
            for k in 0..<game.enemies.len:
              if k != j and chained < chainCount:
                let dist = distance(game.enemies[j].pos, game.enemies[k].pos)
                if dist < chainRange and game.enemies[k].chainLightningCooldown <= 0:
                  game.enemies[k].hp -= bullet.damage * chainDamage
                  game.enemies[k].chainLightningCooldown = 0.3
                  chained += 1
                  
                  # Lightning visual effect
                  for step in 0..10:
                    let t = step.float32 / 10.0
                    let x = game.enemies[j].pos.x + (game.enemies[k].pos.x - game.enemies[j].pos.x) * t
                    let y = game.enemies[j].pos.y + (game.enemies[k].pos.y - game.enemies[j].pos.y) * t
                    spawnExplosion(game.particles, x, y, Color(r: 255, g: 255, b: 100, a: 255), 2)
          
          # Bullet split on hit
          if hasPowerUp(game.player, puBulletSplit) and not bullet.hasSplit:
            let splitLevel = getPowerUpLevel(game.player, puBulletSplit)
            let splitCount = splitLevel + 1  # 2, 3, or 4 bullets
            
            for split in 0..<splitCount:
              let angle = split.float32 * PI * 2.0 / splitCount.float32
              let dir = newVector2f(cos(angle), sin(angle))
              let splitBullet = newBullet(bullet.pos.x, bullet.pos.y, dir, 
                                         bullet.vel.length() * 0.7, bullet.damage * 0.5, true,
                                         bullet.isHoming, bullet.isPiercing, bullet.isExplosive,
                                         bullet.bounceCount >= 0, false, bullet.slowAmount, bullet.poisonDuration)
              splitBullet.hasSplit = true  # Prevent infinite splitting
              splitBullet.hitEnemies = bullet.hitEnemies  # Inherit hit list to prevent re-hitting
              game.bullets.add(splitBullet)
          
          # Vampirism healing - restore HP based on damage dealt
          if hasPowerUp(game.player, puVampirism):
            let vampLevel = getPowerUpLevel(game.player, puVampirism)
            let healPercent = case vampLevel
              of 1: 0.05  # 5%
              of 2: 0.10  # 10%
              else: 0.18  # 18%
            let healAmount = bullet.damage * healPercent
            heal(game.player, healAmount)
            if healAmount > 0.01:  # Only show particles if significant healing
              spawnExplosion(game.particles, game.player.pos.x, game.player.pos.y, Green, 3)
          
          # Impact particles
          spawnExplosion(game.particles, bullet.pos.x, bullet.pos.y, 
                        game.enemies[j].color, 5)
          
          # Explosive bullets create area damage
          if bullet.isExplosive:
            playSound(stExplosion, 0.5)
            let level = getPowerUpLevel(game.player, puExplosiveBullets)
            let explosionRadius = case level
              of 1: 40.0
              of 2: 60.0
              else: 80.0
            
            # Damage all enemies in radius
            for k in 0..<game.enemies.len:
              let dist = distance(bullet.pos, game.enemies[k].pos)
              if dist < explosionRadius:
                game.enemies[k].hp -= bullet.damage * 0.5
            
            # Enhanced visual explosion with shockwave
            spawnExplosion(game.particles, bullet.pos.x, bullet.pos.y, Orange, 35)
            spawnExplosion(game.particles, bullet.pos.x, bullet.pos.y, Yellow, 20)
            spawnShockwave(game.particles, bullet.pos.x, bullet.pos.y, explosionRadius)
          
          # Piercing bullets can hit multiple enemies
          if bullet.isPiercing:
            let level = getPowerUpLevel(game.player, puPiercingShots)
            bullet.piercedEnemies += 1
            # Level 1 = pierce 1 (hit 2 total), Level 2 = pierce 2 (hit 3 total), etc.
            if bullet.piercedEnemies > level:
              hitEnemy = true  # Delete bullet after hitting level+1 enemies
            else:
              hitEnemy = false  # Don't delete bullet yet, continue piercing
          
          # Bullet ricochet off enemies (if not piercing/exploding)
          if bullet.bounceCount >= 0 and not bullet.isPiercing and not bullet.isExplosive:
            let ricochetLevel = getPowerUpLevel(game.player, puBulletRicochet)
            let maxRicochets = ricochetLevel  # 1, 2, or 3 ricochets
            
            if bullet.bounceCount < maxRicochets:
              # Ricochet toward a different enemy that hasn't been hit yet
              var ricochetTarget: Enemy = nil
              var targetIndex = -1
              for k in 0..<game.enemies.len:
                # Skip current enemy, already-hit enemies, and use random selection
                if k != j and k notin bullet.hitEnemies and (ricochetTarget == nil or rand(100) < 50):
                  ricochetTarget = game.enemies[k]
                  targetIndex = k
              
              if ricochetTarget != nil:
                let ricochetDir = (ricochetTarget.pos - bullet.pos).normalize()
                bullet.vel = ricochetDir * bullet.vel.length()
                bullet.bounceCount += 1
                hitEnemy = false  # Don't delete bullet
                spawnExplosion(game.particles, bullet.pos.x, bullet.pos.y, Yellow, 8)
              else:
                hitEnemy = true
            else:
              hitEnemy = true
          
          if hitEnemy:
            break
    else:
      # Enemy bullet hitting player
      if checkBulletPlayerCollision(bullet, game.player):
        var bulletDamage = 1.0
        
        # Thorns reflection - damage the originating enemy
        if hasPowerUp(game.player, puThorns):
          let thornsLevel = getPowerUpLevel(game.player, puThorns)
          let reflectPercent = case thornsLevel
            of 1: 0.20
            of 2: 0.40
            else: 0.70
          let reflectedDamage = bulletDamage * reflectPercent
          
          # Find nearest enemy to reflect damage to
          var nearestEnemy: Enemy = nil
          var nearestDist = 999999.0
          for enemy in game.enemies:
            let dist = distance(bullet.pos, enemy.pos)
            if dist < nearestDist:
              nearestDist = dist
              nearestEnemy = enemy
          
          if nearestEnemy != nil:
            nearestEnemy.hp -= reflectedDamage
            spawnExplosion(game.particles, nearestEnemy.pos.x, nearestEnemy.pos.y, Red, 5)
        
        takeDamage(game.player, bulletDamage)
        hitEnemy = true
        spawnExplosion(game.particles, bullet.pos.x, bullet.pos.y, Red, 8)
        
        if game.player.hp <= 0:
          game.state = gsGameOver
    
    # Check bullet-wall collision (only enemy bullets)
    if not bullet.fromPlayer:
      for wall in game.walls:
        if checkBulletWallCollision(bullet, wall):
          hitEnemy = true
          wall.takeDamage(bullet.damage)  # Full bullet damage
          spawnExplosion(game.particles, bullet.pos.x, bullet.pos.y, Brown, 4)
          break
    
    if hitEnemy:
      game.bullets.delete(i)
      continue
    
    i += 1
  
  # Update coins
  i = 0
  while i < game.coins.len:
    if not updateCoin(game.coins[i], dt, game.coins.len):
      game.coins.delete(i)
      continue
    
    # Check if coin is in player's collection aura (auto-collect)
    if checkAuraCollision(game.coins[i], game.player, game.player.auraRadius):
      # Pull coin toward player with magnet animation
      moveCoinToPlayer(game.coins[i], game.player.pos, dt)
      
      # Add subtle particle trail for magnet effect
      if rand(100) < 30:  # 30% chance per frame
        spawnExplosion(game.particles, game.coins[i].pos.x, game.coins[i].pos.y, 
                      Color(r: 255, g: 215, b: 0, a: 150), 1)
    
    # Enhanced magnet effect from consumable
    if game.player.magnetTimer > 0:
      moveCoinToPlayer(game.coins[i], game.player.pos, dt)
    
    # Collect coin on contact
    if checkPlayerCollision(game.coins[i], game.player):
      game.player.coins += game.coins[i].value
      playSound(stCoinPickup, 0.5)
      spawnExplosion(game.particles, game.coins[i].pos.x, game.coins[i].pos.y, Gold, 6)
      game.coins.delete(i)
      continue
    
    i += 1
  
  # Update consumables
  i = 0
  while i < game.consumables.len:
    if not updateConsumable(game.consumables[i], dt):
      game.consumables.delete(i)
      continue
    
    if checkPlayerCollision(game.consumables[i], game.player):
      playSound(stPowerUp, 0.6)
      
      case game.consumables[i].consumableType
      of ctHealth:
        heal(game.player, 1)
      of ctCoin:
        game.player.coins += 5
      of ctSpeed:
        activateSpeedBoost(game.player)
      of ctInvincibility:
        activateInvincibility(game.player)
      of ctFireRate:
        activateFireRateBoost(game.player)
      of ctMagnet:
        activateMagnet(game.player)
      
      let particleColor = case game.consumables[i].consumableType
        of ctHealth: Green
        of ctCoin: Gold
        of ctSpeed: SkyBlue
        of ctInvincibility: Magenta
        of ctFireRate: Orange
        of ctMagnet: Purple
      
      spawnExplosion(game.particles, game.consumables[i].pos.x, game.consumables[i].pos.y, 
                    particleColor, 10)
      game.consumables.delete(i)
      continue
    
    i += 1
  
  # Update walls
  i = 0
  while i < game.walls.len:
    if not updateWall(game.walls[i], dt):
      spawnExplosion(game.particles, game.walls[i].pos.x, game.walls[i].pos.y, Brown, 20)
      game.walls.delete(i)
      continue
    i += 1
  
  # Update particles
  i = 0
  while i < game.particles.len:
    if not updateParticle(game.particles[i], dt):
      game.particles.delete(i)
      continue
    i += 1

proc drawGame*(game: Game) =
  clearBackground(Color(r: 20, g: 20, b: 30, a: 255))
  
  # Draw particles first (background layer)
  for particle in game.particles:
    drawParticle(particle)
  
  # Draw attack warnings (before everything else so they're visible)
  for warning in game.attackWarnings:
    drawAttackWarning(warning)
  
  # Draw lasers (after warnings, before walls for visual layering)
  for laser in game.lasers:
    drawLaser(laser)
  
  # Draw walls
  for wall in game.walls:
    drawWall(wall)
  
  # Draw coins
  for coin in game.coins:
    drawCoin(coin)
  
  # Draw consumables
  for consumable in game.consumables:
    drawConsumable(consumable)
  
  # Draw bullets
  for bullet in game.bullets:
    drawBullet(bullet)
  
  # Draw enemies
  for enemy in game.enemies:
    drawEnemy(enemy)
  
  # Draw player
  drawPlayer(game.player)
  
  # Draw UI
  let minutes = (game.time / 60.0).int
  let seconds = (game.time mod 60.0).int
  let timeText = $minutes & ":" & (if seconds < 10: "0" else: "") & $seconds
  
  drawText("HP: " & $game.player.hp.int & "/" & $game.player.maxHp.int, 10, 10, 20, if game.player.hp <= 1: Red else: White)
  drawText("Coins: " & $game.player.coins, 10, 35, 20, Gold)
  drawText("Kills: " & $game.player.kills, 10, 60, 20, White)
  drawText("Time: " & timeText, 10, 85, 20, White)
  
  # Simple boss warning text (no timer pause)
  if game.bossSpawnTimer > 0:
    let warningAlpha = ((game.bossSpawnTimer * 6.0).int mod 2)
    let warningColor = if warningAlpha == 0:
      Color(r: 255, g: 50, b: 50, a: 255)
    else:
      Color(r: 255, g: 100, b: 100, a: 200)
    
    let warningText = "BOSS INCOMING"
    let textWidth = measureText(warningText, 40)
    drawText(warningText, (game.screenWidth div 2 - textWidth div 2).int32,
             (game.screenHeight div 2 - 60).int32, 40, warningColor)
  drawText("Walls: " & $game.player.walls, 10, 110, 20, Brown)
  
  # Mode-specific UI
  if game.mode == gmWaveBased:
    # Wave information
    let waveDisplay = if game.bossActive:
      "Boss Wave " & $(game.currentWave)
    else:
      "Wave " & $(game.currentWave)
    drawText(waveDisplay, 10, 135, 20, if game.bossActive: Red else: Yellow)
    
    if game.waveInProgress and not game.bossActive:
      let enemiesLeft = game.waveEnemiesRemaining + game.enemies.len
      drawText("Enemies: " & $enemiesLeft & "/" & $game.waveEnemiesTotal, 10, 160, 18, Orange)
    elif game.bossActive:
      drawText("Defeat the Boss!", 10, 160, 18, Red)
  else:
    # Time survival mode - show chaos meter
    let chaosLevel = min(game.difficulty * 10, 100).int
    drawText("Chaos: " & $chaosLevel & "%", 10, 135, 18, 
            if chaosLevel < 30: Green elif chaosLevel < 70: Orange else: Red)
  
  # Boss health bar (top of screen)
  if game.bossActive:
    for enemy in game.enemies:
      if enemy.isBoss and enemy.entranceTimer <= 0:
        let barWidth = 400
        let barHeight = 25
        let barX = game.screenWidth div 2 - barWidth div 2
        let barY = 15
        let hpPercent = enemy.hp / enemy.maxHp

        
        # Health bar background
        drawRectangle(int32(barX), int32(barY), int32(barWidth), int32(barHeight),
                      Color(r: 60, g: 20, b: 20, a: 255))
        
        # Health bar fill with gradient
        let fillWidth = (barWidth.float32 * hpPercent).int32
        let barColor = if hpPercent > 0.6: Green elif hpPercent > 0.3: Yellow else: Red
        drawRectangle(int32(barX), int32(barY), fillWidth, int32(barHeight), barColor)
        
        # Health bar border
        drawRectangleLines(int32(barX), int32(barY), int32(barWidth), int32(barHeight), White)
        
        # HP text
        let hpText = $(enemy.hp.int) & " / " & $(enemy.maxHp.int)
        let hpTextWidth = measureText(hpText, 16)
        drawText(hpText, int32(game.screenWidth div 2 - hpTextWidth div 2), int32(barY + 4), 16, White)
        break
  
  # Time survival mode - show wave indicator (only for time survival)
  if game.mode == gmTimeSurvival:
    let waveProgress = (game.time mod 15.0) / 15.0
    if waveProgress > 0.6 and not game.bossActive:
      drawText("*** WAVE ***", game.screenWidth div 2 - 80, 10, 25, Red)
  
  # Active power-ups display (left side)
  if game.player.powerUps.len > 0:
    var puYOffset: int32 = 170
    drawText("Power-Ups:", 10, puYOffset, 16, Yellow)
    puYOffset += 20
    for powerUp in game.player.powerUps:
      let name = getPowerUpName(powerUp.powerType)
      drawText(name & " L" & $powerUp.level, 10, puYOffset.int32, 14, White)
      puYOffset += 18
  
  # Active powerup timers (right side)
  var yOffset: int32 = 10

  if game.player.speedBoostTimer > 0:
    drawText("Speed Boost: " & $(game.player.speedBoostTimer.int + 1) & "s",
           game.screenWidth - 200, yOffset, 16, SkyBlue)
    yOffset += 20
  if game.player.invincibilityTimer > 0:
    drawText("Invincible: " & $(game.player.invincibilityTimer.int + 1) & "s", 
            game.screenWidth - 200, yOffset, 16, Magenta)
    yOffset += 20
  if game.player.fireRateBoostTimer > 0:
    drawText("Fire Rate: " & $(game.player.fireRateBoostTimer.int + 1) & "s", 
            game.screenWidth - 200, yOffset, 16, Orange)
    yOffset += 20
  if game.player.magnetTimer > 0:
    drawText("Magnet: " & $(game.player.magnetTimer.int + 1) & "s", 
            game.screenWidth - 200, yOffset, 16, Purple)
    yOffset += 20
  
  drawText("Damage: " & $(getCurrentDamage(game.player).int), game.screenWidth - 200, yOffset, 16, White)
  yOffset += 20
  let shotsPerSec = 1.0 / getCurrentFireRate(game.player)
  drawText("Fire Rate: " & $(shotsPerSec.int) & "/s", game.screenWidth - 200, yOffset, 16, White)
  yOffset += 20
  
  # Show Rage/Berserker bonuses when HP is low
  if hasPowerUp(game.player, puRage) or hasPowerUp(game.player, puBerserker):
    let hpPercent = game.player.hp / game.player.maxHp
    if hpPercent < 0.7:
      if hasPowerUp(game.player, puRage):
        let rageLevel = getPowerUpLevel(game.player, puRage)
        let rageMultiplier = 
          case rageLevel
          of 1: 0.5
          of 2: 0.8
          else: 1.2
        drawText("Rage: +" & $((1.0 - hpPercent) * 100.0 * rageMultiplier).int & "% dmg",
                game.screenWidth - 200, yOffset, 14, Red)
        yOffset += 18

      if hasPowerUp(game.player, puBerserker):
        let berserkLevel = getPowerUpLevel(game.player, puBerserker)
        let berserkMultiplier = 
          case berserkLevel
          of 1: 0.5
          of 2: 0.8
          else: 1.5
        drawText("Berserk: +" & $((1.0 - hpPercent) * 100.0 * berserkMultiplier).int & "% rate",
                game.screenWidth - 200, yOffset, 14, Orange)
        yOffset += 18
  
  # Only show auto-shoot status if player has the power-up
  if hasPowerUp(game.player, puAutoShoot):
    let autoLevel = getPowerUpLevel(game.player, puAutoShoot)
    drawText("Auto: L" & $autoLevel, game.screenWidth - 200, yOffset, 16, Green)
    yOffset += 20
  
  # Stats
  drawText("Enemies: " & $game.enemies.len, game.screenWidth - 200, yOffset + 10, 14, LightGray)
  drawText("Bullets: " & $game.bullets.len, game.screenWidth - 200, yOffset + 28, 14, LightGray)
  drawText("Particles: " & $game.particles.len, game.screenWidth - 200, yOffset + 46, 14, LightGray)
  
  drawText("E: Wall | ESC: Pause", 
           game.screenWidth div 2 - 180, game.screenHeight - 25, 16, LightGray)
  
  # Custom animated crosshair cursor
  let mousePos = getMousePosition()
  let cursorPulse = sin(game.time * 8.0) * 2 + 8
  
  # Outer rotating ring
  for i in 0..<8:
    let angle = game.time * 4.0 + i.float32 * PI / 4.0
    let x = mousePos.x + cos(angle) * cursorPulse
    let y = mousePos.y + sin(angle) * cursorPulse
    drawCircle(Vector2(x: x, y: y), 2, Color(r: 255'u8, g: 200'u8, b: 50'u8, a: 200'u8))
  
  # Crosshair lines
  drawLine(Vector2(x: mousePos.x - 8, y: mousePos.y), 
          Vector2(x: mousePos.x - 3, y: mousePos.y), 2, White)
  drawLine(Vector2(x: mousePos.x + 3, y: mousePos.y), 
          Vector2(x: mousePos.x + 8, y: mousePos.y), 2, White)
  drawLine(Vector2(x: mousePos.x, y: mousePos.y - 8), 
          Vector2(x: mousePos.x, y: mousePos.y - 3), 2, White)
  drawLine(Vector2(x: mousePos.x, y: mousePos.y + 3), 
          Vector2(x: mousePos.x, y: mousePos.y + 8), 2, White)
  
  # Center dot
  drawCircle(Vector2(x: mousePos.x, y: mousePos.y), 2, Red)

proc drawGameOver*(game: Game) =
  clearBackground(Color(r: 20, g: 20, b: 30, a: 255))
  
  drawText("GAME OVER", game.screenWidth div 2 - 150, game.screenHeight div 2 - 100, 50, Red)
  
  let minutes = (game.time / 60.0).int
  let seconds = (game.time mod 60.0).int
  let timeText = $minutes & ":" & (if seconds < 10: "0" else: "") & $seconds
  
  drawText("Time Survived: " & timeText, game.screenWidth div 2 - 120, game.screenHeight div 2, 25, White)
  drawText("Kills: " & $game.player.kills, game.screenWidth div 2 - 60, game.screenHeight div 2 + 40, 25, White)
  drawText("Coins Earned: " & $game.player.coins, game.screenWidth div 2 - 130, game.screenHeight div 2 + 80, 25, Gold)
  
  # Show wave number if in wave mode
  if game.mode == gmWaveBased:
    drawText("Wave Reached: " & $game.currentWave, game.screenWidth div 2 - 120, game.screenHeight div 2 - 40, 25, Yellow)
  
  drawText("Press R to restart or ESC to menu", game.screenWidth div 2 - 190, game.screenHeight div 2 + 140, 20, LightGray)

proc drawWaveTransition*(game: Game) =
  # Draw the game in background
  drawGame(game)
  
  # Dark overlay
  drawRectangle(0, 0, game.screenWidth, game.screenHeight, Color(r: 0, g: 0, b: 0, a: 180))
  
  # Title
  drawText("GET READY!", game.screenWidth div 2 - 120, game.screenHeight div 2 - 80, 50, Yellow)
  
  # Boss wave notification with wave number
  let bossWaveText = "BOSS WAVE " & $(game.currentWave + 1)
  let bossTextWidth = measureText(bossWaveText, 35)
  drawText(bossWaveText, game.screenWidth div 2 - bossTextWidth div 2, game.screenHeight div 2, 35, Red)
  
  drawText("INCOMING", game.screenWidth div 2 - 75, game.screenHeight div 2 + 40, 30, Orange)
  

  drawText("Press ENTER to start", game.screenWidth div 2 - 130, game.screenHeight - 80, 20, LightGray)
