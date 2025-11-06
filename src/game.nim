import raylib, types, player, enemy, bullet, consumable, coin, wall, shop, particle, random, math

proc newGame*(screenWidth, screenHeight: int32): Game =
  result = Game(
    state: gsPlaying,
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
    menuSelection: 0
  )

proc shootBullet*(game: Game, direction: Vector2f) =
  let currentFireRate = getCurrentFireRate(game.player)
  if game.time - game.player.lastShot >= currentFireRate:
    # BUFFED: Faster player bullets
    game.bullets.add(newBullet(game.player.pos.x, game.player.pos.y, direction, 
                                game.player.bulletSpeed * 1.2, game.player.damage, true))
    game.player.lastShot = game.time
    
    # Add muzzle flash particles
    spawnExplosion(game.particles, game.player.pos.x, game.player.pos.y, Yellow, 5)

proc updateGame*(game: Game, dt: float32) =
  game.time += dt
  game.spawnTimer += dt
  game.difficulty = game.time / 10.0  # Difficulty increases every 10 seconds
  
  # Update player (with wall collision)
  updatePlayer(game.player, dt, game.screenWidth, game.screenHeight, game.walls)
  
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
  
  # PROGRESSIVE SPAWNING: Slower at start, ramps up over time
  let baseSpawnRate = if game.difficulty < 1.0: 
    2.5  # Very slow at start (0-10s)
  elif game.difficulty < 3.0:
    1.8 / (1.0 + (game.difficulty - 1.0) * 0.3)  # Gradual increase (10-30s)
  else:
    1.2 / (1.0 + (game.difficulty - 3.0) * 0.4)  # Full chaos (30s+)
  
  let waveSpawnRate = baseSpawnRate * 0.7  # Extra fast during waves
  
  # Overlapping wave system - multiple mini-waves
  let waveProgress = (game.time mod 15.0) / 15.0
  let isWaveActive = waveProgress > 0.6  # 40% of time is wave mode
  
  let currentSpawnRate = if isWaveActive: waveSpawnRate else: baseSpawnRate
  
  if game.spawnTimer > currentSpawnRate:
    game.enemies.add(spawnEnemy(game.screenWidth, game.screenHeight, game.difficulty))
    game.spawnTimer = 0
    
    # During waves, spawn multiple enemies at once!
    if isWaveActive and rand(100) < 60:
      game.enemies.add(spawnEnemy(game.screenWidth, game.screenHeight, game.difficulty))
  
  # Boss spawn every 60 seconds
  if game.time >= game.bossTimer:
    game.bossCount += 1
    game.enemies.add(spawnBoss(game.screenWidth, game.screenHeight, game.difficulty, game.bossCount))
    game.bossTimer += 60.0
    
    # Spawn extra minions when boss arrives
    for i in 0..2:
      game.enemies.add(spawnEnemy(game.screenWidth, game.screenHeight, game.difficulty))
  
  # Update enemies
  var i = 0
  while i < game.enemies.len:
    let enemy = game.enemies[i]
    
    if not updateEnemy(enemy, game.player.pos, dt, game.walls, game.time):
      # Enemy died - drop coins and particles
      let coinValue = if enemy.isBoss: 15 else: (if enemy.enemyType == etStar: 5 else: 1)
      game.coins.add(newCoin(enemy.pos.x, enemy.pos.y, coinValue))
      
      # Death particles
      let particleColor = enemy.color
      spawnExplosion(game.particles, enemy.pos.x, enemy.pos.y, particleColor, 
                    if enemy.isBoss: 50 else: 15)
      
      # Drop consumable
      let dropChance = if enemy.isBoss: 80 elif enemy.enemyType == etStar: 40 else: 15
      if rand(99) < dropChance:
        game.consumables.add(newConsumable(enemy.pos.x, enemy.pos.y, game.difficulty))
      
      game.player.kills += 1
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
  
  # Update bullets
  i = 0
  while i < game.bullets.len:
    let bullet = game.bullets[i]
    
    if not updateBullet(bullet, dt) or isOffScreen(bullet, game.screenWidth, game.screenHeight):
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
  let minutes = (game.time / 60.0).int
  let seconds = (game.time mod 60.0).int
  let timeText = $minutes & ":" & (if seconds < 10: "0" else: "") & $seconds
  
  drawText("HP: " & $game.player.hp & "/" & $game.player.maxHp, 10, 10, 20, if game.player.hp <= 1: Red else: White)
  drawText("Coins: " & $game.player.coins, 10, 35, 20, Gold)
  drawText("Kills: " & $game.player.kills, 10, 60, 20, White)
  drawText("Time: " & timeText, 10, 85, 20, White)
  drawText("Walls: " & $game.player.walls, 10, 110, 20, Brown)
  
  # Wave indicator
  let waveProgress = (game.time mod 15.0) / 15.0
  if waveProgress > 0.6:
    drawText("*** WAVE ***", game.screenWidth div 2 - 80, 10, 25, Red)
  
  # Chaos meter
  let chaosLevel = min(game.difficulty * 10, 100).int
  drawText("Chaos: " & $chaosLevel & "%", 10, 135, 18, 
          if chaosLevel < 30: Green elif chaosLevel < 70: Orange else: Red)
  
  # Active powerup indicators
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
  
  drawText("Press R to restart or ESC to menu", game.screenWidth div 2 - 190, game.screenHeight div 2 + 140, 20, LightGray)
