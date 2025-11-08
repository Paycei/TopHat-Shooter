import raylib, types, player, enemy, bullet, consumable, coin, wall, shop, particle, powerup, random, math

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
    timerFrozen: false,
    frozenTimeDisplay: 0,
    # Wave-based mode fields
    currentWave: 1,
    wavesUntilBoss: 3,
    waveEnemiesRemaining: 0,
    waveEnemiesTotal: 0,
    waveInProgress: false,
    waveCompleteTimer: 0
  )

proc calculateWaveEnemyCount(waveNumber: int): int =
  # Scale enemy count based on wave number
  # Start with 10 enemies, add 3-4 per wave
  result = 10 + (waveNumber - 1) * 3
  # Cap at 45 enemies per wave
  if result > 45:
    result = 45

proc startWave*(game: Game) =
  game.waveInProgress = true
  game.waveEnemiesTotal = calculateWaveEnemyCount(game.currentWave)
  game.waveEnemiesRemaining = game.waveEnemiesTotal
  game.spawnTimer = 0

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
      # Waves 5-6: Add hexagons (teleporting chaos)
      if roll < 65: enemyType = etCircle
      elif roll < 85: enemyType = etCube
      else: enemyType = etHexagon
    
    elif wave <= 10:
      # Waves 7-10: Add stars (tanky enemies)
      if roll < 45: enemyType = etCircle
      elif roll < 55: enemyType = etCube
      elif roll < 75: enemyType = etHexagon
      else: enemyType = etStar
    
    elif wave <= 15:
      # Waves 11-15: Full roster with triangles
      if roll < 30: enemyType = etCircle
      elif roll < 50: enemyType = etCube
      elif roll < 65: enemyType = etHexagon
      elif roll < 80: enemyType = etStar
      else: enemyType = etTriangle
    
    else:
      # Wave 16+: Balanced chaos - all enemy types
      if roll < 20: enemyType = etCircle
      elif roll < 40: enemyType = etCube
      elif roll < 55: enemyType = etHexagon
      elif roll < 75: enemyType = etStar
      else: enemyType = etTriangle
    
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
  
  # Check if it's time for a boss
  if game.wavesUntilBoss == 0:
    game.wavesUntilBoss = 3  # Reset counter
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
    
    # Base bullet properties
    let speed = game.player.bulletSpeed * 1.2
    let damage = game.player.damage
    
    if hasDoubleShot:
      # Shoot 2, 3, or 4 bullets based on level
      let level = getPowerUpLevel(game.player, puDoubleShot)
      let bulletCount = level + 1
      let spread = 0.15
      
      for i in 0..<bulletCount:
        let spreadAngle = (i.float32 - (bulletCount - 1).float32 / 2.0) * spread
        let spreadDir = newVector2f(
          direction.x * cos(spreadAngle) - direction.y * sin(spreadAngle),
          direction.x * sin(spreadAngle) + direction.y * cos(spreadAngle)
        )
        game.bullets.add(newBullet(game.player.pos.x, game.player.pos.y, spreadDir, 
                                  speed, damage, true, hasHoming, hasPiercing, hasExplosive))
    elif hasMultiShot:
      # Shoot in multiple directions
      let level = getPowerUpLevel(game.player, puMultiShot)
      let bulletCount = if level == 3: 5 else: 3
      let spreadAngle = if level == 2: 0.5 else: 0.3
      
      for i in 0..<bulletCount:
        let angle = (i - bulletCount div 2).float32 * spreadAngle
        let spreadDir = newVector2f(
          direction.x * cos(angle) - direction.y * sin(angle),
          direction.x * sin(angle) + direction.y * cos(angle)
        )
        game.bullets.add(newBullet(game.player.pos.x, game.player.pos.y, spreadDir, 
                                  speed, damage, true, hasHoming, hasPiercing, hasExplosive))
    else:
      # Normal single shot
      game.bullets.add(newBullet(game.player.pos.x, game.player.pos.y, direction, 
                                  speed, damage, true, hasHoming, hasPiercing, hasExplosive))
    
    game.player.lastShot = game.time
    
    # Add muzzle flash particles
    spawnExplosion(game.particles, game.player.pos.x, game.player.pos.y, Yellow, 5)

proc updateGame*(game: Game, dt: float32) =
  # Handle boss spawn timer and timer freezing
  if game.bossSpawnTimer > 0:
    game.bossSpawnTimer -= dt
    game.timerFrozen = true
    # Don't update game time while timer is frozen
  else:
    if game.timerFrozen:
      game.timerFrozen = false
    game.time += dt
  
  game.spawnTimer += dt
  game.difficulty = game.time / 10.0  # Difficulty increases every 10 seconds
  
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
  
  # Check shooting
  let mousePos = getMousePosition()
  let shootDir = newVector2f(mousePos.x - game.player.pos.x, mousePos.y - game.player.pos.y)
  
  if isMouseButtonDown(Left) or isKeyDown(Space):
    if shootDir.length() > 0:
      shootBullet(game, shootDir)
  
  # Auto-shoot
  if game.player.autoShoot and game.enemies.len > 0:
    var nearestEnemy: Enemy = nil
    var nearestDist = 350.0
    
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
      # Spawn wave enemies gradually with dynamic rate
      # Earlier waves spawn faster for momentum, later waves space out for intensity
      let baseSpawnRate = if game.currentWave <= 3: 0.6
                         elif game.currentWave <= 7: 0.7
                         elif game.currentWave <= 12: 0.75
                         else: 0.8
      
      if game.spawnTimer > baseSpawnRate and game.waveEnemiesRemaining > 0:
        spawnWaveEnemy(game)
        game.spawnTimer = 0
      
      # Check if wave is complete
      if checkWaveComplete(game):
        game.waveInProgress = false

        # Advance wave counters so the next wave uses the next wave number
        game.currentWave += 1
        game.wavesUntilBoss -= 1

        # If wavesUntilBoss reached zero, schedule a boss wave next
        if game.wavesUntilBoss <= 0:
          # Do not reset wavesUntilBoss here — the boss-spawning logic checks for 0.
          # We'll show a short transition before the boss arrives.
          game.waveCompleteTimer = 2.0
          game.state = gsWaveTransition
        else:
          # Regular wave complete: show power-up choices
          game.powerUpChoices = generatePowerUpChoices(game.player, false)
          game.selectedPowerUp = 0
          game.state = gsPowerUpSelect
    
    # Boss wave spawning
    if game.wavesUntilBoss == 0 and not game.bossActive and game.bossSpawnTimer <= 0:
      game.bossCount += 1
      # Scale boss difficulty based on wave number (every 3 waves = +1 difficulty)
      let bossDifficulty = (game.currentWave - 1).float32 / 3.0
      game.enemies.add(spawnBoss(game.screenWidth, game.screenHeight, 
                                bossDifficulty, game.bossCount))
      game.bossActive = true
      game.bossSpawnTimer = 2.5
      game.frozenTimeDisplay = game.time
      
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
      game.bossSpawnTimer = 2.5
      game.frozenTimeDisplay = game.time
      
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
  var i = 0
  var bossDefeated = false
  while i < game.enemies.len:
    let enemy = game.enemies[i]
    
    if not updateEnemy(enemy, game.player.pos, dt, game.walls, game.time):
      # Enemy died - drop coins and particles
      let coinValue = if enemy.isBoss:
        # Boss drops scale with difficulty: 15 + 5 per difficulty level
        15 + (game.difficulty * 5).int
      else:
        # Regular enemies drop based on type
        case enemy.enemyType
        of etCircle: 1
        of etCube: 2
        of etTriangle: 3
        of etStar: 5
        of etHexagon: 3
      
      game.coins.add(newCoin(enemy.pos.x, enemy.pos.y, coinValue))
      
      # Star explosion on death - damages player if too close
      if enemy.enemyType == etStar:
        const explosionRadius = 120.0  # LARGER explosion radius
        const explosionDamage = 2.0
        
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
          game.wavesUntilBoss = 3  # Next boss in 3 waves
        # Time survival mode continues with existing logic
      
      game.enemies.delete(i)
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
          takeDamage(game.player, enemy.damage.float32)
          enemy.lastContactDamageTime = game.time
          spawnExplosion(game.particles, game.player.pos.x, game.player.pos.y, Red, 10)
          
          if game.player.hp <= 0:
            game.state = gsGameOver
      else:
        # Regular enemies die on contact
        takeDamage(game.player, enemy.damage.float32)
        enemy.hp = 0
        game.enemies.delete(i)
        
        if game.player.hp <= 0:
          game.state = gsGameOver
        continue
    
    i += 1
  
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
    
    # Homing bullet logic
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
        # Adjust velocity toward enemy
        let level = getPowerUpLevel(game.player, puHomingBullets)
        let turnRate = case level
          of 1: 0.05
          of 2: 0.1
          else: 0.15
        
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
      let shieldRadius = game.player.radius + 20
      var hitShield = false
      
      for j in 0..<shieldCount:
        let angle = game.player.shieldAngle + (j.float32 * PI * 2.0 / shieldCount.float32)
        let shieldX = game.player.pos.x + cos(angle) * shieldRadius
        let shieldY = game.player.pos.y + sin(angle) * shieldRadius
        let shieldPos = newVector2f(shieldX, shieldY)
        
        if checkShieldCollision(bullet, shieldPos):
          hitShield = true
          spawnExplosion(game.particles, shieldX, shieldY, SkyBlue, 8)
          break
      
      if hitShield:
        game.bullets.delete(i)
        continue
    
    # Check bullet-enemy collision
    var hitEnemy = false
    if bullet.fromPlayer:
      for j in 0..<game.enemies.len:
        if checkBulletEnemyCollision(bullet, game.enemies[j]):
          if game.enemies[j].enemyType == etStar:
            # Stars use hit counter
            game.enemies[j].hitCount += 1
          else:
            game.enemies[j].hp -= bullet.damage
          hitEnemy = true
          
          # Impact particles
          spawnExplosion(game.particles, bullet.pos.x, bullet.pos.y, 
                        game.enemies[j].color, 5)
          
          # Explosive bullets create area damage
          if bullet.isExplosive:
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
            if bullet.piercedEnemies >= level:
              hitEnemy = true
            else:
              hitEnemy = false  # Don't delete bullet yet
          
          if hitEnemy:
            break
    else:
      # Enemy bullet hitting player
      if checkBulletPlayerCollision(bullet, game.player):
        takeDamage(game.player, 1)
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
    if not updateCoin(game.coins[i], dt):
      game.coins.delete(i)
      continue
    
    # Magnet effect
    if game.player.magnetTimer > 0:
      moveCoinToPlayer(game.coins[i], game.player.pos, dt)
    
    if checkPlayerCollision(game.coins[i], game.player):
      game.player.coins += game.coins[i].value
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
  let displayTime = if game.timerFrozen: game.frozenTimeDisplay else: game.time
  let minutes = (displayTime / 60.0).int
  let seconds = (displayTime mod 60.0).int
  let timeText = $minutes & ":" & (if seconds < 10: "0" else: "") & $seconds
  
  drawText("HP: " & $game.player.hp.int & "/" & $game.player.maxHp.int, 10, 10, 20, if game.player.hp <= 1: Red else: White)
  drawText("Coins: " & $game.player.coins, 10, 35, 20, Gold)
  drawText("Kills: " & $game.player.kills, 10, 60, 20, White)
  
  # Animate timer when frozen
  let timeColor = if game.timerFrozen:
    let pulse = ((game.bossSpawnTimer * 4.0).int mod 2)
    if pulse == 0: Yellow else: Orange
  else:
    White
  drawText("Time: " & timeText, 10, 85, 20, timeColor)
  
  # Boss warning indicator
  if game.bossSpawnTimer > 0:
    let warningAlpha = ((game.bossSpawnTimer * 6.0).int mod 2)
    let warningColor = if warningAlpha == 0:
      Color(r: 255, g: 50, b: 50, a: 255)
    else:
      Color(r: 255, g: 100, b: 100, a: 200)
    
    let warningText = "!!! BOSS INCOMING !!!"
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
  
  drawText("Damage: " & $(game.player.damage.int), game.screenWidth - 200, yOffset, 16, White)
  yOffset += 20
  let shotsPerSec = 1.0 / getCurrentFireRate(game.player)
  drawText("Fire Rate: " & $(shotsPerSec.int) & "/s", game.screenWidth - 200, yOffset, 16, White)
  yOffset += 20
  drawText("Auto: " & (if game.player.autoShoot: "ON" else: "OFF"), game.screenWidth - 200, yOffset, 16, 
           if game.player.autoShoot: Green else: Red)
  
  # Stats
  drawText("Enemies: " & $game.enemies.len, game.screenWidth - 200, yOffset + 30, 14, LightGray)
  drawText("Bullets: " & $game.bullets.len, game.screenWidth - 200, yOffset + 48, 14, LightGray)
  drawText("Particles: " & $game.particles.len, game.screenWidth - 200, yOffset + 66, 14, LightGray)
  
  drawText("F: Auto | TAB: Shop | E: Wall | ESC: Pause", 
           game.screenWidth div 2 - 240, game.screenHeight - 25, 16, LightGray)

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
  
  # Countdown
  let countdown = (game.waveCompleteTimer + 0.5).int
  let countText = $countdown
  let countWidth = measureText(countText, 60)
  drawText(countText, game.screenWidth div 2 - countWidth div 2, game.screenHeight div 2 + 90, 60, Gold)
  
  drawText("Press ENTER to start", game.screenWidth div 2 - 130, game.screenHeight - 80, 20, LightGray)
