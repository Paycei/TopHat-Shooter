import raylib, types, player, enemy, bullet, consumable, coin, wall, shop, particle, powerup, sound, random, math, settings, tables, effects, strutils

# CONFIGURABLE: Boss wave enemy spawn reduction (0.0 = no enemies, 1.0 = full enemies)
const BOSS_WAVE_SPAWN_MULTIPLIER = 0.5  # 50% of normal spawn

# CONFIGURABLE: Loot boundary margins (how far from edge loot can spawn)
const LOOT_MARGIN = 50.0  # Distance from screen edge

proc clampLootPosition(x, y: float32, screenWidth, screenHeight: int32): tuple[x, y: float32] =
  ## Clamps a position to be within screen bounds with margin
  ## Used to push loot spawned out-of-bounds back into playable area
  result.x = clamp(x, LOOT_MARGIN, screenWidth.float32 - LOOT_MARGIN)
  result.y = clamp(y, LOOT_MARGIN, screenHeight.float32 - LOOT_MARGIN)

proc applyEliteModifiers(enemy: Enemy, baseDamage: float32): float32 =
  ## Applies elite damage modifiers (tank reduction, shield absorption)
  ## Returns the actual damage to apply to enemy HP
  ## Handles multiple elite types for wave 25+ elites
  result = baseDamage
  
  # Tank elite: 65% damage reduction (buffed from 50%)
  # If multiple elites include Tank, apply reduction
  if enemy.isElite and etTank in enemy.eliteTypes:
    result *= 0.5  # 50% reduction
  
  # Shielded elite: shield absorbs damage first
  if enemy.isElite and etShielded in enemy.eliteTypes and enemy.shieldHp > 0:
    if enemy.shieldHp >= result:
      # Shield absorbs all damage
      enemy.shieldHp -= result
      result = 0
    else:
      # Shield breaks, remaining damage goes to HP
      result -= enemy.shieldHp
      enemy.shieldHp = 0

proc applyCriticalHit(player: Player, baseDamage: float32): float32 =
  ## Applies critical hit chance to any damage source
  ## Returns damage with critical multiplier applied if crit occurs
  if not hasPowerUp(player, puCriticalHit):
    return baseDamage
  
  let critLevel = getPowerUpLevel(player, puCriticalHit)
  let critChance = case critLevel
    of 1: 20  # Increased from 15%
    of 2: 35  # Increased from 20%
    else: 50  # Increased from 25%
  let critMultiplier = 2.0  # Fixed multiplier (was 2.0, 2.5, 3.0)
  
  if rand(99) < critChance:
    return baseDamage * critMultiplier
  else:
    return baseDamage

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
    countdownTimer: 0.3,  # Start with ready countdown
    waveClearedTimer: 0,
    bossActive: false,
    bossSpawnTimer: 0,
    bossCoinActive: false,
    cameFromPowerUpSelect: false,
    gameOverSoundPlayed: false,
    # Wave-based mode fields
    currentWave: 1,
    wavesUntilBoss: 4,  # Boss appears at waves 5, 10, 15, etc.
    waveEnemiesRemaining: 0,
    waveEnemiesTotal: 0,
    waveInProgress: false,
    # Cheat tracking
    cheatsUsed: false,  # Reset to false at start of each run
    # Mouse tracking for menu navigation
    lastMousePos: newVector2f(0, 0),
    mouseMovedRecently: false,
    keyboardUsedRecently: false,
    # State tracking for settings return
    previousState: gsMenu  # Default to menu
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
  var waveEnemyCount = calculateWaveEnemyCount(game.currentWave)
  
  # Apply boss wave reduction if this is a boss wave
  if game.wavesUntilBoss == 0:
    waveEnemyCount = (waveEnemyCount.float32 * BOSS_WAVE_SPAWN_MULTIPLIER).int
  
  game.waveEnemiesTotal = waveEnemyCount
  game.waveEnemiesRemaining = waveEnemyCount
  game.spawnTimer = 0
  
  # PLAYER SCALING: Multiply current stats by 1.25% per wave (preserves shop purchases and power-ups)
  # This applies scaling multiplicatively to whatever stats the player has built up
  let waveScaling = 1.0125  # 1.25% increase per wave
  
  # Apply multiplicative scaling to current stats (preserves all upgrades)
  game.player.maxHp *= waveScaling
  game.player.hp = min(game.player.hp * waveScaling, game.player.maxHp)  # Scale current HP but cap at maxHp
  game.player.damage *= waveScaling
  game.player.speed *= waveScaling
  game.player.baseSpeed *= waveScaling
  game.player.bulletSpeed *= waveScaling
  # Fire rate gets faster (lower number = faster), so we divide instead of multiply
  game.player.fireRate /= waveScaling
  
  # Reset all active ability cooldowns for new wave
  game.player.timeWarpUsesThisWave = 0
  game.player.timeWarpCooldown = 0
  game.player.phaseShiftCooldown = 0

proc spawnWaveEnemies*(game: Game, count: int) =
  # Spawn multiple enemies at once
  for _ in 0..<count:
    if game.waveEnemiesRemaining > 0:
      let wave = game.currentWave
      let roll = rand(100)
      var enemyType: EnemyType

      # NEW ENEMY EVERY 5 WAVES with high spawn rate for that enemy
      # Each new enemy gets 40-50% spawn rate in their introduction wave range
      if wave <= 5:
        # Waves 1-5: Only CIRCLES (tutorial phase)
        enemyType = etCircle
      
      elif wave <= 10:
        # Waves 6-10: Introduce PENTAGON (ranged basics)
        # Pentagon is the star here with 40% spawn rate
        if roll < 40: enemyType = etPentagon  # NEW ENEMY - prominent
        elif roll < 75: enemyType = etCircle
        else: enemyType = etCircle  # Keep it simple
      
      elif wave <= 15:
        # Waves 11-15: Introduce TRIANGLE (dash enemy)
        # Triangle gets 40% spawn rate
        if roll < 40: enemyType = etTriangle  # NEW ENEMY - prominent
        elif roll < 65: enemyType = etCircle
        else: enemyType = etPentagon
      
      elif wave <= 20:
        # Waves 16-20: Introduce CUBE (stationary shooter)
        # Cube gets 35% spawn rate
        if roll < 35: enemyType = etCube  # NEW ENEMY - prominent
        elif roll < 55: enemyType = etCircle
        elif roll < 75: enemyType = etPentagon
        else: enemyType = etTriangle
      
      elif wave <= 25:
        # Waves 21-25: Introduce STAR (tanky enemy)
        # Star gets 30% spawn rate
        if roll < 30: enemyType = etStar  # NEW ENEMY - prominent
        elif roll < 48: enemyType = etCircle
        elif roll < 63: enemyType = etCube
        elif roll < 78: enemyType = etPentagon
        else: enemyType = etTriangle
      
      elif wave <= 30:
        # Waves 26-30: Introduce CROSS (bullet spread)
        # Cross gets 25% spawn rate
        if roll < 25: enemyType = etCross  # NEW ENEMY - prominent
        elif roll < 42: enemyType = etCircle
        elif roll < 56: enemyType = etCube
        elif roll < 68: enemyType = etStar
        elif roll < 80: enemyType = etPentagon
        else: enemyType = etTriangle
      
      elif wave <= 35:
        # Waves 31-35: Introduce DIAMOND (orbit shooter)
        # Diamond gets 22% spawn rate
        if roll < 22: enemyType = etDiamond  # NEW ENEMY - prominent
        elif roll < 38: enemyType = etCircle
        elif roll < 51: enemyType = etCube
        elif roll < 63: enemyType = etStar
        elif roll < 74: enemyType = etCross
        elif roll < 84: enemyType = etPentagon
        else: enemyType = etTriangle
      
      elif wave <= 40:
        # Waves 36-40: Introduce OCTAGON (laser shooter)
        # Octagon gets 20% spawn rate
        if roll < 20: enemyType = etOctagon  # NEW ENEMY - prominent
        elif roll < 34: enemyType = etCircle
        elif roll < 46: enemyType = etCube
        elif roll < 58: enemyType = etStar
        elif roll < 68: enemyType = etCross
        elif roll < 77: enemyType = etDiamond
        elif roll < 86: enemyType = etPentagon
        else: enemyType = etTriangle
      
      elif wave <= 45:
        # Waves 41-45: Introduce HEXAGON (teleporter)
        # Hexagon gets 18% spawn rate
        if roll < 18: enemyType = etHexagon  # NEW ENEMY - prominent
        elif roll < 31: enemyType = etCircle
        elif roll < 43: enemyType = etCube
        elif roll < 54: enemyType = etStar
        elif roll < 64: enemyType = etCross
        elif roll < 73: enemyType = etDiamond
        elif roll < 81: enemyType = etOctagon
        elif roll < 89: enemyType = etPentagon
        else: enemyType = etTriangle
      
      elif wave <= 50:
        # Waves 46-50: Introduce TRICKSTER (deceptive attacks)
        # Trickster gets 16% spawn rate
        if roll < 16: enemyType = etTrickster  # NEW ENEMY - prominent
        elif roll < 28: enemyType = etCircle
        elif roll < 39: enemyType = etCube
        elif roll < 49: enemyType = etStar
        elif roll < 58: enemyType = etCross
        elif roll < 66: enemyType = etDiamond
        elif roll < 74: enemyType = etOctagon
        elif roll < 82: enemyType = etHexagon
        elif roll < 90: enemyType = etPentagon
        else: enemyType = etTriangle
      
      else:
        # Waves 51+: Introduce PHANTOM (unpredictable teleporter) + balanced roster
        # Phantom gets 15% spawn rate
        if roll < 15: enemyType = etPhantom  # NEW ENEMY - prominent
        elif roll < 26: enemyType = etCircle
        elif roll < 36: enemyType = etCube
        elif roll < 45: enemyType = etStar
        elif roll < 53: enemyType = etCross
        elif roll < 61: enemyType = etDiamond
        elif roll < 69: enemyType = etOctagon
        elif roll < 77: enemyType = etHexagon
        elif roll < 85: enemyType = etTrickster
        elif roll < 92: enemyType = etPentagon
        else: enemyType = etTriangle
      
      # Difficulty scaling
      let baseDifficulty = (wave - 1).float32 / 3.0
      
      let side = rand(3)
      var x, y: float32
      case side
      of 0: x = rand(game.screenWidth.int).float32; y = -30
      of 1: x = game.screenWidth.float32 + 30; y = rand(game.screenHeight.int).float32
      of 2: x = rand(game.screenWidth.int).float32; y = game.screenHeight.float32 + 30
      else: x = -30; y = rand(game.screenHeight.int).float32
      
      let enemy = newEnemy(x, y, baseDifficulty, enemyType)
      makeElite(enemy, wave)  # Chance to make enemy elite based on wave
      game.enemies.add(enemy)
      game.waveEnemiesRemaining -= 1

proc checkWaveComplete*(game: Game): bool =
  # Wave is complete when all enemies are defeated, none remain to spawn, 
  # AND boss coin has been collected (if there was one)
  return game.waveEnemiesRemaining == 0 and game.enemies.len == 0 and not game.bossCoinActive

proc advanceWave*(game: Game) =
  game.currentWave += 1
  game.wavesUntilBoss -= 1
  
  # Check if it's time for a boss (every 5 waves now)
  if game.wavesUntilBoss == 0:
    game.wavesUntilBoss = 4  # Reset counter - boss every 5 waves
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
    let hasPoison = hasPowerUp(game.player, puPoisonShot)
    let hasFire = hasPowerUp(game.player, puFireBullets)
    let hasMagic = hasPowerUp(game.player, puMagicBullets)
    
    # Base bullet properties - use current damage with Rage bonus
    var speed = game.player.bulletSpeed * 1.2
    var damage = getCurrentDamage(game.player)
    
    # BUFFED: Double-shot bullets deal 10% less damage per bullet (was 20%)
    if hasDoubleShot:
      damage *= 0.9  # 10% less damage per bullet
        
    var bulletRadius = BASE_PLAYER_BULLET_RADIUS
    
    # Apply bullet size power-up
    if hasPowerUp(game.player, puBulletSize):
      let sizeLevel = getPowerUpLevel(game.player, puBulletSize)
      let sizeMultiplier = case sizeLevel
        of 1: 1.4
        of 2: 1.8
        else: 2.4
      bulletRadius *= sizeMultiplier
    
    # Apply critical hit chance using global function
    damage = applyCriticalHit(game.player, damage)
    
    # Apply Arcane Mastery bonus to magic bullets
    if hasMagic and game.player.hasArcaneMastery:
      damage *= 3.0  # +200% additional damage on top of Magic Bullets bonus
    
    # Calculate slow, poison, fire, and wind effects
    var slowEffect = 0.0
    var poisonEffect = 0.0
    var fireEffect = 0.0
    var windEffect = 0.0
    
    if hasFrost:
      let frostLevel = getPowerUpLevel(game.player, puFrostShots)
      slowEffect = case frostLevel
        of 1: 0.25
        of 2: 0.4
        else: 0.6
      # Apply Frost Mastery bonus if owned
      if game.player.hasFrostMastery:
        slowEffect += 0.2  # +20% slow (total up to 80%)
    if hasPoison:
      let poisonLevel = getPowerUpLevel(game.player, puPoisonShot)
      let poisonBaseScaling = game.player.damage * 0.1
      poisonEffect = case poisonLevel
        of 1: 1.0 + poisonBaseScaling
        of 2: 1.5 + poisonBaseScaling
        else: 2.0 + poisonBaseScaling
    if hasFire:
      let fireLevel = getPowerUpLevel(game.player, puFireBullets)
      let fireBaseScaling = game.player.damage * 0.1
      fireEffect = case fireLevel
        of 1: 0.5 + fireBaseScaling
        of 2: 1.0 + fireBaseScaling
        else: 1.5 + fireBaseScaling
    
    # Wind bullets push effect
    if hasPowerUp(game.player, puWindBullets):
      let windLevel = getPowerUpLevel(game.player, puWindBullets)
      windEffect = case windLevel
        of 1: 100.0   # Weak push
        of 2: 200.0   # Medium push
        else: 350.0   # Strong push
    
    if hasDoubleShot and hasMultiShot:
      # When both active: Fire multishot pattern (3 directions), then schedule second burst
      let multiCount = 3  # Always 3 bullets for legendary Multi-Shot
      let spreadAngle = 0.3  # Fixed spread for 3-shot pattern
      
      # Fire first burst
      for i in 0..<multiCount:
        let angle = (i.float32 - (multiCount - 1).float32 / 2.0) * spreadAngle
        let spreadDir = newVector2f(
          direction.x * cos(angle) - direction.y * sin(angle),
          direction.x * sin(angle) + direction.y * cos(angle)
        )
        let bullet = newBullet(
          x = game.player.pos.x,
          y = game.player.pos.y,
          direction = spreadDir,
          speed = speed,
          damage = damage,
          fromPlayer = true,
          isHoming = hasHoming,
          isPiercing = hasPiercing,
          isExplosive = hasExplosive,
          hasBounce = hasRicochet,
          canSplit = hasSplit,
          slowAmount = slowEffect,
          poisonDuration = poisonEffect,
          fireDuration = fireEffect,
          windPushForce = windEffect,
          isMagicBullet = hasMagic
        )
        bullet.radius = bulletRadius
        game.bullets.add(bullet)
      
      # Schedule second burst with small delay (0.08s) - LEGENDARY Double Shot is single level
      game.player.doubleShotDelay = 0.08
    
    elif hasDoubleShot:
      # LEGENDARY: Fire 2 bullets in quick succession (single level only)
      # Fire first bullet immediately
      let bullet = newBullet(
        x = game.player.pos.x,
        y = game.player.pos.y,
        direction = direction,
        speed = speed,
        damage = damage,
        fromPlayer = true,
        isHoming = hasHoming,
        isPiercing = hasPiercing,
        isExplosive = hasExplosive,
        hasBounce = hasRicochet,
        canSplit = hasSplit,
        slowAmount = slowEffect,
        poisonDuration = poisonEffect,
        fireDuration = fireEffect,
        windPushForce = windEffect,
        isMagicBullet = hasMagic
      )
      bullet.radius = bulletRadius
      game.bullets.add(bullet)
      
      # Schedule second bullet with small delay (0.08s)
      game.player.doubleShotDelay = 0.08
    elif hasMultiShot:
      # Shoot in 3 directions (legendary, no nerfs)
      let bulletCount = 3  # Always 3 bullets
      let spreadAngle = 0.3  # Fixed spread
      
      for i in 0..<bulletCount:
        let angle = (i.float32 - (bulletCount - 1).float32 / 2.0) * spreadAngle
        let spreadDir = newVector2f(
          direction.x * cos(angle) - direction.y * sin(angle),
          direction.x * sin(angle) + direction.y * cos(angle)
        )
        let bullet = newBullet(
          x = game.player.pos.x,
          y = game.player.pos.y,
          direction = spreadDir,
          speed = speed,
          damage = damage,
          fromPlayer = true,
          isHoming = hasHoming,
          isPiercing = hasPiercing,
          isExplosive = hasExplosive,
          hasBounce = hasRicochet,
          canSplit = hasSplit,
          slowAmount = slowEffect,
          poisonDuration = poisonEffect,
          fireDuration = fireEffect,
          windPushForce = windEffect,
          isMagicBullet = hasMagic
        )
        bullet.radius = bulletRadius
        game.bullets.add(bullet)
    else:
      # Normal single shot
      let bullet = newBullet(
        x = game.player.pos.x,
        y = game.player.pos.y,
        direction = direction,
        speed = speed,
        damage = damage,
        fromPlayer = true,
        isHoming = hasHoming,
        isPiercing = hasPiercing,
        isExplosive = hasExplosive,
        hasBounce = hasRicochet,
        canSplit = hasSplit,
        slowAmount = slowEffect,
        poisonDuration = poisonEffect,
        fireDuration = fireEffect,
        windPushForce = windEffect,
        isMagicBullet = hasMagic
      )
      bullet.radius = bulletRadius
      game.bullets.add(bullet)
    
    game.player.lastShot = game.time
    
    # Play shoot sound
    playSound(stShoot, 0.3)
    
    # Determine particle color based on bullet type - MATCHES BULLET COLOR
    var particleColor = Yellow  # Default
    if hasMagic: particleColor = Color(r: 200, g: 100, b: 255, a: 255)
    elif hasHoming: particleColor = Magenta
    elif hasPiercing: particleColor = SkyBlue
    elif hasExplosive: particleColor = Orange
    elif fireEffect > 0: particleColor = Color(r: 255, g: 80, b: 20, a: 255)
    elif windEffect > 0: particleColor = Color(r: 200, g: 230, b: 255, a: 255)
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
  let hasPoison = hasPowerUp(game.player, puPoisonShot)
  let hasFire = hasPowerUp(game.player, puFireBullets)
  let hasMagic = hasPowerUp(game.player, puMagicBullets)
  
  var speed = game.player.bulletSpeed * 1.2
  var damage = getCurrentDamage(game.player) * 0.85  # BUFFED: Second bullet reduced by 15% (was 25%)
  var bulletRadius = BASE_PLAYER_BULLET_RADIUS
  
  # NERF: Multi-shot bullets deal less damage per bullet (scales with level)
  if hasMultiShot:
    let multiLevel = getPowerUpLevel(game.player, puMultiShot)
    let damageMultiplier = case multiLevel
      of 1: 0.67   # -33% damage (2 bullets = 134% total)
      of 2: 0.5    # -50% damage (3 bullets = 150% total)
      else: 0.45   # -55% damage (4 bullets = 180% total)
    damage *= damageMultiplier
  
  if hasPowerUp(game.player, puBulletSize):
    let sizeLevel = getPowerUpLevel(game.player, puBulletSize)
    let sizeMultiplier = case sizeLevel
      of 1: 1.4
      of 2: 1.8
      else: 2.4
    bulletRadius *= sizeMultiplier
  
  var slowEffect = 0.0
  var poisonEffect = 0.0
  var fireEffect = 0.0
  var windEffect = 0.0
  
  if hasFrost:
    let frostLevel = getPowerUpLevel(game.player, puFrostShots)
    slowEffect = case frostLevel
      of 1: 0.25
      of 2: 0.4
      else: 0.6
  if hasPoison:
    let poisonLevel = getPowerUpLevel(game.player, puPoisonShot)
    let poisonBaseScaling = game.player.damage * 0.1
    poisonEffect = case poisonLevel
      of 1: 1.0 + poisonBaseScaling
      of 2: 1.5 + poisonBaseScaling
      else: 2.0 + poisonBaseScaling
  if hasFire:
    let fireLevel = getPowerUpLevel(game.player, puFireBullets)
    let fireBaseScaling = game.player.damage * 0.1
    fireEffect = case fireLevel
      of 1: 0.5 + fireBaseScaling
      of 2: 1.0 + fireBaseScaling
      else: 1.5 + fireBaseScaling
  if hasPowerUp(game.player, puWindBullets):
    let windLevel = getPowerUpLevel(game.player, puWindBullets)
    windEffect = case windLevel
      of 1: 100.0   # Weak push
      of 2: 200.0   # Medium push
      else: 350.0   # Strong push
  
  if hasMultiShot:
    let multiCount = 3  # Always 3 bullets for legendary Multi-Shot
    let spreadAngle = 0.3  # Fixed spread
    
    for i in 0..<multiCount:
      let angle = (i.float32 - (multiCount - 1).float32 / 2.0) * spreadAngle
      let spreadDir = newVector2f(
        direction.x * cos(angle) - direction.y * sin(angle),
        direction.x * sin(angle) + direction.y * cos(angle)
      )
      let bullet = newBullet(
        x = game.player.pos.x,
        y = game.player.pos.y,
        direction = spreadDir,
        speed = speed,
        damage = damage,
        fromPlayer = true,
        isHoming = hasHoming,
        isPiercing = hasPiercing,
        isExplosive = hasExplosive,
        hasBounce = hasRicochet,
        canSplit = hasSplit,
        slowAmount = slowEffect,
        poisonDuration = poisonEffect,
        fireDuration = fireEffect,
        windPushForce = windEffect,
        isMagicBullet = hasMagic
      )
      bullet.radius = bulletRadius
      game.bullets.add(bullet)
  else:
    let bullet = newBullet(
      x = game.player.pos.x,
      y = game.player.pos.y,
      direction = direction,
      speed = speed,
      damage = damage,
      fromPlayer = true,
      isHoming = hasHoming,
      isPiercing = hasPiercing,
      isExplosive = hasExplosive,
      hasBounce = hasRicochet,
      canSplit = hasSplit,
      slowAmount = slowEffect,
      poisonDuration = poisonEffect,
      fireDuration = fireEffect,
      windPushForce = windEffect,
      isMagicBullet = hasMagic
    )
    bullet.radius = bulletRadius
    game.bullets.add(bullet)
  
  playSound(stShoot, 0.25)

proc updateGame*(game: var Game, dt: float32) =
  # Time Warp effect - apply slow to delta time for enemies/bullets
  var effectiveDt = dt
  if game.player.timeWarpActive:
    let slowFactor = 0.50  # 50% slow = 50% speed (single level)
    effectiveDt = dt * slowFactor
  
  # Handle boss spawn warning timer (non-blocking)
  if game.bossSpawnTimer > 0:
    game.bossSpawnTimer -= dt
  
  # Always update game time (player time not affected)
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
        if takeDamage(game.player, laser.damage.float32):
          game.state = gsGameOver
        game.lasers[j].hasHitPlayer = true
    
    # Remove expired lasers
    if game.lasers[j].lifetime <= 0:
      game.lasers.delete(j)
      continue
    j += 1
  
  # Update player (with wall collision)
  updatePlayer(game.player, dt, game.screenWidth, game.screenHeight, game.walls)
  
  # Player poison damage from venomous elites
  # Uses accumulator system to ensure only whole number damage is applied
  if game.player.poisonTimer > 0:
    game.player.poisonTimer -= dt
    
    # Accumulate fractional damage
    game.player.poisonAccumulator += game.player.poisonDamage * dt
    
    # Apply damage in whole number increments
    if game.player.poisonAccumulator >= 1.0:
      let wholeDamage = game.player.poisonAccumulator.int.float32  # Floor to whole number
      game.player.poisonAccumulator -= wholeDamage  # Keep remainder
      
      if takeDamage(game.player, wholeDamage):
        game.state = gsGameOver
      
      # Additional safety check: ensure game ends if HP reaches 0
      if game.player.hp <= 0:
        game.state = gsGameOver
    
    # Poison visual effect (frame-independent)
    # Spawn ~20 particles/sec
    if rand(1.0) < (20.0 * dt):
      spawnExplosion(game.particles, game.player.pos.x, game.player.pos.y, Green, 2)
  
  # Damage zone power-up effect
  if hasPowerUp(game.player, puDamageZone):
    let level = getPowerUpLevel(game.player, puDamageZone)
    let zoneDamage = case level
      of 1: 3.0
      of 2: 6.0
      else: 12.0
    let zoneRadius = case level
      of 1: 120.0
      of 2: 160.0
      else: 200.0
    
    for enemy in game.enemies:
      let dist = distance(game.player.pos, enemy.pos)
      if dist < zoneRadius:
        let damageWithCrit = applyCriticalHit(game.player, zoneDamage * dt)
        let actualDamage = applyEliteModifiers(enemy, damageWithCrit)
        enemy.hp -= actualDamage
  
  # Regeneration power-up is now handled per wave completion, not per time interval
  # See wave completion code for regeneration logic
  
  # Slow Field power-up effect - NERFED for balance
  if hasPowerUp(game.player, puSlowField):
    let level = getPowerUpLevel(game.player, puSlowField)
    let slowPercent = case level
      of 1: 0.30  # NERFED from 50% to 30% slow
      of 2: 0.45  # NERFED from 65% to 45% slow
      else: 0.55  # NERFED from 75% to 55% slow
    let slowRadius = case level
      of 1: 120.0
      of 2: 160.0
      else: 200.0
    
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
  
  # Fire Aura power-up effect - applies burning damage over time
  if hasPowerUp(game.player, puFireAura):
    let level = getPowerUpLevel(game.player, puFireAura)
    let damageScaling = game.player.damage * 0.1
    let fireDamagePerSec = case level
      of 1: 0.5 + damageScaling
      of 2: 1.0 + damageScaling
      else: 1.5 + damageScaling
    let fireDuration = case level
      of 1: 2.0
      of 2: 3.0
      else: 4.0
    let fireRadius = case level
      of 1: 120.0
      of 2: 160.0
      else: 200.0
    
    for enemy in game.enemies:
      let dist = distance(game.player.pos, enemy.pos)
      if dist < fireRadius:
        var actualFireDamage = fireDamagePerSec
        var actualFireDuration = fireDuration
        
        # Apply Fire Mastery bonuses if owned
        if game.player.hasFireMastery:
          actualFireDamage *= 2.5  # +150% damage
          actualFireDuration *= 2.0  # +100% duration
        
        # Apply fire effect using new system
        applyEffect(enemy, etFire, actualFireDamage, actualFireDuration, "aura")
        
        # Apply slow ONLY if player has Fire Mastery
        if game.player.hasFireMastery:
          enemy.slowTimer = 0.2
          if enemy.slowAmount < 0.35:
            enemy.slowAmount = 0.35  # 35% slow
        
        # Visual fire particles (frame-independent)
        # 8% @ 60fps = 4.8 particles/sec → use dt scaling
        if rand(1.0) < (4.8 * dt):
          let particleAngle = rand(1.0) * PI * 2.0
          let particleDist = rand(enemy.radius + 5.0)
          let particleX = enemy.pos.x + cos(particleAngle) * particleDist
          let particleY = enemy.pos.y + sin(particleAngle) * particleDist - 3.0
          spawnExplosion(game.particles, particleX, particleY, Red, 2)
  
  # Lightning Aura power-up effect - low damage with chain lightning
  if hasPowerUp(game.player, puLightningAura):
    let level = getPowerUpLevel(game.player, puLightningAura)
    let damageScaling = game.player.damage * 0.1
    var lightningDamagePerSec = case level
      of 1: 0.3 + damageScaling
      of 2: 0.6 + damageScaling
      else: 1.0 + damageScaling
    var maxChains = case level
      of 1: 1
      of 2: 2
      else: 3
    let lightningRadius = case level
      of 1: 120.0
      of 2: 160.0
      else: 200.0
    let chainRange = 80.0  # Distance lightning can chain between enemies
    
    # Apply Lightning Mastery bonuses if owned
    if game.player.hasLightningMastery:
      lightningDamagePerSec *= 2.5  # +150% damage
      maxChains += 1  # +1 chain
    
    # Build list of enemies in range
    var enemiesInRange: seq[tuple[enemy: Enemy, dist: float32]] = @[]
    for enemy in game.enemies:
      let dist = distance(game.player.pos, enemy.pos)
      if dist < lightningRadius:
        enemiesInRange.add((enemy: enemy, dist: dist))
    
    # Apply damage and chain lightning
    var processedEnemies: seq[Enemy] = @[]
    for entry in enemiesInRange:
      let enemy = entry.enemy
      if enemy notin processedEnemies:
        # Apply initial damage with crit chance
        let damageWithCrit = applyCriticalHit(game.player, lightningDamagePerSec * dt)
        let actualDamage = applyEliteModifiers(enemy, damageWithCrit)
        enemy.hp -= actualDamage
        processedEnemies.add(enemy)
        
        # Apply slow ONLY if player has Lightning Mastery
        if game.player.hasLightningMastery:
          enemy.slowTimer = 0.2
          if enemy.slowAmount < 0.25:
            enemy.slowAmount = 0.25  # 25% slow
        
        # Visual lightning spark (frame-independent)
        # 10% @ 60fps = 6 particles/sec
        if rand(1.0) < (6.0 * dt):
          spawnExplosion(game.particles, enemy.pos.x, enemy.pos.y, 
                        Color(r: 150, g: 200, b: 255, a: 255), 3)
        
        # Chain to nearby enemies
        var currentEnemy = enemy
        for chainNum in 1..maxChains:
          # Find nearest unchained enemy within chain range
          var nearestDist = chainRange + 1.0
          var nearestEnemy: Enemy = nil
          
          for other in game.enemies:
            if other != currentEnemy and other notin processedEnemies:
              let chainDist = distance(currentEnemy.pos, other.pos)
              if chainDist < chainRange and chainDist < nearestDist:
                nearestDist = chainDist
                nearestEnemy = other
          
          if nearestEnemy != nil:
            # Apply chained damage (same as initial) with crit chance
            let chainDamageWithCrit = applyCriticalHit(game.player, lightningDamagePerSec * dt)
            let chainedDamage = applyEliteModifiers(nearestEnemy, chainDamageWithCrit)
            nearestEnemy.hp -= chainedDamage
            processedEnemies.add(nearestEnemy)
            
            # Apply 5% slow effect to chained enemy
            nearestEnemy.slowTimer = 0.2
            if nearestEnemy.slowAmount < 0.05:
              nearestEnemy.slowAmount = 0.05
            
            # Visual chain lightning particle (frame-independent)
            # 20% @ 60fps = 12 particles/sec
            if rand(1.0) < (12.0 * dt):
              let midX = (currentEnemy.pos.x + nearestEnemy.pos.x) / 2.0
              let midY = (currentEnemy.pos.y + nearestEnemy.pos.y) / 2.0
              spawnExplosion(game.particles, midX, midY,
                            Color(r: 200, g: 220, b: 255, a: 200), 2)
            
            currentEnemy = nearestEnemy
          else:
            break  # No more enemies to chain to
  
  # Magic Aura power-up effect - pure arcane damage
  if hasPowerUp(game.player, puMagicAura):
    let level = getPowerUpLevel(game.player, puMagicAura)
    let damageScaling = game.player.damage * 0.1
    var magicDamagePerSec = case level
      of 1: 0.5 + damageScaling
      of 2: 1.0 + damageScaling
      else: 1.5 + damageScaling
    let magicRadius = case level
      of 1: 120.0
      of 2: 160.0
      else: 200.0
    
    # Apply Arcane Mastery bonuses if owned
    if game.player.hasArcaneMastery:
      magicDamagePerSec *= 3.0  # +200% damage
    
    for enemy in game.enemies:
      let dist = distance(game.player.pos, enemy.pos)
      if dist < magicRadius:
        let damageWithCrit = applyCriticalHit(game.player, magicDamagePerSec * dt)
        let actualDamage = applyEliteModifiers(enemy, damageWithCrit)
        enemy.hp -= actualDamage
        
        # Visual arcane particles (purple sparkles) (frame-independent)
        # 12% @ 60fps = 7.2 particles/sec
        if rand(1.0) < (7.2 * dt):
          let particleAngle = rand(1.0) * PI * 2.0
          let particleDist = rand(enemy.radius + 3.0)
          let particleX = enemy.pos.x + cos(particleAngle) * particleDist
          let particleY = enemy.pos.y + sin(particleAngle) * particleDist
          spawnExplosion(game.particles, particleX, particleY, 
                        Color(r: 200, g: 100, b: 255, a: 255), 2)
  
  # Poison Aura power-up effect - low damage, longer duration
  if hasPowerUp(game.player, puPoisonAura):
    let level = getPowerUpLevel(game.player, puPoisonAura)
    let damageScaling = game.player.damage * 0.1
    let poisonDamagePerSec = case level
      of 1: 0.2 + damageScaling
      of 2: 0.4 + damageScaling
      else: 0.6 + damageScaling
    let poisonDuration = case level
      of 1: 6.0
      of 2: 8.0
      else: 10.0
    let poisonRadius = case level
      of 1: 120.0
      of 2: 160.0
      else: 200.0
    
    for enemy in game.enemies:
      let dist = distance(game.player.pos, enemy.pos)
      if dist < poisonRadius:
        var actualPoisonDamage = poisonDamagePerSec
        var actualPoisonDuration = poisonDuration
        
        # Apply Poison Mastery bonuses if owned
        if game.player.hasPoisonMastery:
          actualPoisonDamage *= 2.5  # +150% damage
          actualPoisonDuration *= 2.0  # +100% duration
        
        # Apply poison aura effect (separate from bullet poison)
        applyEffect(enemy, etPoison, actualPoisonDamage, actualPoisonDuration, "aura")
        
        # Apply slow ONLY if player has Poison Mastery
        if game.player.hasPoisonMastery:
          enemy.slowTimer = 0.2
          if enemy.slowAmount < 0.30:
            enemy.slowAmount = 0.30  # 30% slow
        
        # Visual poison particles (frame-independent)
        # 6% @ 60fps = 3.6 particles/sec
        if rand(1.0) < (3.6 * dt):
          let particleAngle = rand(1.0) * PI * 2.0
          let particleDist = rand(enemy.radius + 5.0)
          let particleX = enemy.pos.x + cos(particleAngle) * particleDist
          let particleY = enemy.pos.y + sin(particleAngle) * particleDist - 3.0
          spawnExplosion(game.particles, particleX, particleY, 
                        Color(r: 100, g: 255, a: 200), 2)
  
  # Wind Aura power-up effect - pushes enemies away from player (slow aura but different mechanic)
  if hasPowerUp(game.player, puWindAura):
    let level = getPowerUpLevel(game.player, puWindAura)
    var pushStrength = case level
      of 1: 50.0   # Weak push
      of 2: 80.0   # Medium push
      else: 120.0  # Strong push
    let windRadius = case level
      of 1: 120.0
      of 2: 160.0
      else: 200.0
    
    # Apply Wind Mastery bonuses if owned
    if game.player.hasWindMastery:
      pushStrength *= 2.5  # Stronger push (+150%)
    
    for enemy in game.enemies:
      let dist = distance(game.player.pos, enemy.pos)
      if dist < windRadius and dist > 5.0:  # Don't push if too close
        # Calculate push direction (away from player)
        let pushDir = (enemy.pos - game.player.pos).normalize()
        
        # Bosses are much more resistant to wind push (10% effectiveness)
        let bossResistance = if enemy.isBoss: 0.1 else: 1.0
        
        # Apply push force (stronger when closer)
        let pushForce = pushStrength * (1.0 - (dist / windRadius)) * bossResistance
        enemy.pos.x += pushDir.x * pushForce * dt
        enemy.pos.y += pushDir.y * pushForce * dt
        
        # Apply slow ONLY if player has Wind Mastery
        if game.player.hasWindMastery:
          enemy.slowTimer = 0.2
          if enemy.slowAmount < 0.40:
            enemy.slowAmount = 0.40  # 40% slow
        
        # Visual wind particles (outward from player toward enemies) (frame-independent)
        # 8% @ 60fps = 4.8 particles/sec
        if rand(1.0) < (4.8 * dt):
          let particleAngle = rand(1.0) * PI * 2.0
          let particleDist = rand(windRadius * 0.8)
          let particleX = game.player.pos.x + cos(particleAngle) * particleDist
          let particleY = game.player.pos.y + sin(particleAngle) * particleDist
          spawnExplosion(game.particles, particleX, particleY, 
                        Color(r: 200, g: 230, b: 255, a: 150), 2)
  
  # Gravity Well (Singularity) - Pull enemies toward player with bonus effect on ranged
  if hasPowerUp(game.player, puGravityWell):
    let pullRadius = 300.0  # Single level - balanced radius
    let basePullStrength = 100.0
    
    for enemy in game.enemies:
      let dist = distance(game.player.pos, enemy.pos)
      if dist < pullRadius and dist > 10.0:  # Don't pull if too close
        # Calculate direction to player
        let toPlayer = (game.player.pos - enemy.pos).normalize()
        
        # Check if this is a ranged enemy (gets 50% extra pull)
        let isRanged = enemy.enemyType in [etCube, etPentagon, etOctagon, etHexagon, etSniper]
        let pullMultiplier = if isRanged: 1.5 else: 1.0
        
        # Apply pull force (stronger when closer)
        let pullForce = basePullStrength * pullMultiplier * (1.0 - (dist / pullRadius))
        enemy.pos.x += toPlayer.x * pullForce * dt
        enemy.pos.y += toPlayer.y * pullForce * dt
        
        # Spawn visual particles for gravity effect (more for ranged enemies) (frame-independent)
        # 25% @ 60fps = 15 particles/sec for ranged, 15% = 9 particles/sec for melee
        let particleRate = if isRanged: 15.0 else: 9.0
        if rand(1.0) < (particleRate * dt):
          let particleAngle = rand(1.0) * PI * 2.0
          let particleDist = rand(pullRadius)
          let particleX = game.player.pos.x + cos(particleAngle) * particleDist
          let particleY = game.player.pos.y + sin(particleAngle) * particleDist
          let particleColor = if isRanged: Color(r: 138, g: 43, b: 226, a: 220) else: Color(r: 75, g: 0, b: 130, a: 200)
          spawnExplosion(game.particles, particleX, particleY, particleColor, 2)
    
    # Also pull coins
    let coinPullMultiplier = 0.0  # No coins for now
    for coin in game.coins:
      let dist = distance(game.player.pos, coin.pos)
      if dist < pullRadius and dist > 10.0:
        let toPlayer = (game.player.pos - coin.pos).normalize()
        let pullForce = basePullStrength * coinPullMultiplier * (1.0 - (dist / pullRadius))
        coin.pos.x += toPlayer.x * pullForce * dt
        coin.pos.y += toPlayer.y * pullForce * dt


  # Rotating Orbs power-up - elemental orbs that orbit the player and damage enemies
  # Check for both the legendary all-element version and individual element power-ups
  if hasPowerUp(game.player, puRotatingOrbs) or 
     hasPowerUp(game.player, puPoisonOrb) or 
     hasPowerUp(game.player, puFireOrb) or 
     hasPowerUp(game.player, puLightningOrb) or 
     hasPowerUp(game.player, puWindOrb) or 
     hasPowerUp(game.player, puFrostOrb):
    
    # Calculate base damage (BUFFED RANGE 2-6, but reduced multiplier)
    # Add small damage scaling from player's damage stat (10% of player damage)
    let damageScaling = game.player.damage * 0.05  # Reduced from 0.1 to 0.05 for compensation
    
    let baseDamage = if hasPowerUp(game.player, puRotatingOrbs):
      0.5 + damageScaling  # Legendary version reduced from 1.0 to 0.5 for compensation
    else:
      # For individual orbs, use level-based damage (multiplied by 0.5 to balance the 2-6 buff)
      var maxDamage = 0.0
      if hasPowerUp(game.player, puPoisonOrb):
        maxDamage = max(maxDamage, getElementDamage(getPowerUpLevel(game.player, puPoisonOrb)))
      if hasPowerUp(game.player, puFireOrb):
        maxDamage = max(maxDamage, getElementDamage(getPowerUpLevel(game.player, puFireOrb)))
      if hasPowerUp(game.player, puLightningOrb):
        maxDamage = max(maxDamage, getElementDamage(getPowerUpLevel(game.player, puLightningOrb)))
      if hasPowerUp(game.player, puWindOrb):
        maxDamage = max(maxDamage, getElementDamage(getPowerUpLevel(game.player, puWindOrb)))
      if hasPowerUp(game.player, puFrostOrb):
        maxDamage = max(maxDamage, getElementDamage(getPowerUpLevel(game.player, puFrostOrb)))
      (maxDamage * 0.5) + damageScaling  # Multiply by 0.5 to balance the 2-6 range
    
    let orbRadius = 6.0  # Visual orb size - matches drawn size
    let orbDetectionRange = 0.0  # No extra detection range
    
    # Update each orb and check for collisions
    for orb in game.player.rotatingOrbs:
      # Calculate orb position
      let angle = game.player.orbRotationAngle + orb.angle
      let orbX = game.player.pos.x + cos(angle) * orb.radius
      let orbY = game.player.pos.y + sin(angle) * orb.radius
      let orbPos = newVector2f(orbX, orbY)
      
      # Check collision with enemies
      var enemyIdx = 0
      for enemy in game.enemies:
        let dist = distance(orbPos, enemy.pos)
        
        # Check if orb is touching enemy (with increased detection range)
        if dist < orbRadius + enemy.radius + orbDetectionRange:
          # Check if we haven't hit this enemy recently (cooldown per enemy)
          let currentTime = game.time
          var canHit = true
          
          if orb.lastHitTime.hasKey(enemyIdx):
            # 0.5 second cooldown per enemy (prevents multi-hitting same enemy)
            if currentTime - orb.lastHitTime[enemyIdx] < 0.5:
              canHit = false
          
          if canHit:
            # Apply damage (with element-specific bonuses)
            var actualBaseDamage = baseDamage
            
            # Apply Arcane Mastery bonus for Magic orbs
            if orb.elementType == etMagic and game.player.hasArcaneMastery:
              actualBaseDamage *= 3.0  # +200% damage
            
            let damageWithCrit = applyCriticalHit(game.player, actualBaseDamage)
            let actualDamage = applyEliteModifiers(enemy, damageWithCrit)
            enemy.hp -= actualDamage
            
            # Record hit time
            orb.lastHitTime[enemyIdx] = currentTime
            
            # Apply element-specific effects
            case orb.elementType
            of etPoison:
              # Poison: 0.3 dmg/sec for 4 seconds (NERFED base, scaled with player damage)
              let poisonDamageScaling = game.player.damage * 0.1
              var poisonDmg = 0.3 + poisonDamageScaling
              var poisonDur = 4.0
              
              # Apply Poison Mastery bonuses if owned
              if game.player.hasPoisonMastery:
                poisonDmg *= 2.5  # +150% damage
                poisonDur *= 2.0  # +100% duration
              
              applyEffect(enemy, etPoison, poisonDmg, poisonDur, "orb")
              
              # Apply slow ONLY if player has Poison Mastery
              if game.player.hasPoisonMastery:
                enemy.slowTimer = 0.2
                if enemy.slowAmount < 0.30:
                  enemy.slowAmount = 0.30  # 30% slow
              
              # Green particles
              spawnExplosion(game.particles, orbX, orbY, 
                           Color(r: 100, g: 255, b: 100, a: 255), 5)
            
            of etFire:
              # Fire: 0.4 dmg/sec for 2 seconds (NERFED base, scaled with player damage)
              let fireDamageScaling = game.player.damage * 0.1
              var fireDmg = 0.4 + fireDamageScaling
              var fireDur = 2.0
              
              # Apply Fire Mastery bonuses if owned
              if game.player.hasFireMastery:
                fireDmg *= 2.5  # +150% damage
                fireDur *= 2.0  # +100% duration
              
              applyEffect(enemy, etFire, fireDmg, fireDur, "orb")
              
              # Apply slow ONLY if player has Fire Mastery
              if game.player.hasFireMastery:
                enemy.slowTimer = 0.2
                if enemy.slowAmount < 0.35:
                  enemy.slowAmount = 0.35  # 35% slow
              
              # Orange/red particles
              spawnExplosion(game.particles, orbX, orbY, Orange, 5)
              spawnExplosion(game.particles, orbX, orbY, Red, 3)
            
            of etLightning:
              # Lightning: Instant damage + chain to nearby enemy
              # Already dealt base damage, now chain
              let chainRange = 80.0
              var chainCount = 1  # Default chain count
              var nearestDist = chainRange + 1.0
              var nearestEnemy: Enemy = nil
              var nearestIdx = -1
              
              # Apply Lightning Mastery bonuses if owned
              if game.player.hasLightningMastery:
                chainCount = 2  # +1 additional chain
              
              var checkIdx = 0
              for other in game.enemies:
                if other != enemy:
                  let chainDist = distance(enemy.pos, other.pos)
                  if chainDist < chainRange and chainDist < nearestDist:
                    nearestDist = chainDist
                    nearestEnemy = other
                    nearestIdx = checkIdx
                checkIdx += 1
              
              if nearestEnemy != nil:
                # Deal 70% damage to chained enemy with crit chance
                let chainDamageWithCrit = applyCriticalHit(game.player, baseDamage * 0.7)
                let chainDamage = applyEliteModifiers(nearestEnemy, chainDamageWithCrit)
                nearestEnemy.hp -= chainDamage
                
                # Apply slow if has Lightning Mastery
                if game.player.hasLightningMastery:
                  nearestEnemy.slowTimer = 0.2
                  if nearestEnemy.slowAmount < 0.25:
                    nearestEnemy.slowAmount = 0.25  # 25% slow
                
                # Visual chain
                spawnExplosion(game.particles, nearestEnemy.pos.x, nearestEnemy.pos.y,
                             Color(r: 200, g: 220, b: 255, a: 255), 3)
                
                # If has Lightning Mastery, chain one more time
                if game.player.hasLightningMastery:
                  var secondNearestDist = chainRange + 1.0
                  var secondNearestEnemy: Enemy = nil
                  
                  for other in game.enemies:
                    if other != enemy and other != nearestEnemy:
                      let chainDist = distance(nearestEnemy.pos, other.pos)
                      if chainDist < chainRange and chainDist < secondNearestDist:
                        secondNearestDist = chainDist
                        secondNearestEnemy = other
                  
                  if secondNearestEnemy != nil:
                    let secondChainDamageWithCrit = applyCriticalHit(game.player, baseDamage * 0.7)
                    let secondChainDamage = applyEliteModifiers(secondNearestEnemy, secondChainDamageWithCrit)
                    secondNearestEnemy.hp -= secondChainDamage
                    
                    # Apply slow to second chain
                    secondNearestEnemy.slowTimer = 0.2
                    if secondNearestEnemy.slowAmount < 0.25:
                      secondNearestEnemy.slowAmount = 0.25
                    
                    # Visual chain
                    spawnExplosion(game.particles, secondNearestEnemy.pos.x, secondNearestEnemy.pos.y,
                                 Color(r: 200, g: 220, b: 255, a: 255), 3)
              
              # Apply slow to primary target if has Lightning Mastery
              if game.player.hasLightningMastery:
                enemy.slowTimer = 0.2
                if enemy.slowAmount < 0.25:
                  enemy.slowAmount = 0.25  # 25% slow
              
              # Yellow particles
              spawnExplosion(game.particles, orbX, orbY, Yellow, 5)
            
            of etWind:
              # Wind: Knockback away from player
              let pushDir = (enemy.pos - game.player.pos).normalize()
              var pushForce = 200.0  # Strong knockback
              let bossResistance = if enemy.isBoss: 0.1 else: 1.0
              
              # Apply Wind Mastery bonuses if owned
              if game.player.hasWindMastery:
                pushForce *= 2.5  # Stronger push (+150%)
              
              enemy.pos.x += pushDir.x * pushForce * dt * bossResistance
              enemy.pos.y += pushDir.y * pushForce * dt * bossResistance
              
              # Apply slow ONLY if player has Wind Mastery
              if game.player.hasWindMastery:
                enemy.slowTimer = 0.2
                if enemy.slowAmount < 0.40:
                  enemy.slowAmount = 0.40  # 40% slow
              
              # Cyan particles
              spawnExplosion(game.particles, orbX, orbY,
                           Color(r: 200, g: 230, b: 255, a: 255), 5)
            
            of etFrost:
              # Frost: 30% slow effect base (permanent until removed)
              enemy.slowTimer = 999.0  # Very long duration
              var frostSlow = 0.3  # Base 30% slow
              
              # Apply Frost Mastery bonus if owned
              if game.player.hasFrostMastery:
                frostSlow = 0.5  # +20% slow (50% total with mastery)
              
              if enemy.slowAmount < frostSlow:
                enemy.slowAmount = frostSlow
              
              # Light blue particles
              spawnExplosion(game.particles, orbX, orbY,
                           Color(r: 150, g: 200, b: 255, a: 255), 5)
            
            of etMagic:
              # Magic: Pure arcane damage (already dealt) + purple sparkles
              spawnExplosion(game.particles, orbX, orbY,
                           Color(r: 200, g: 100, b: 255, a: 255), 5)
            
            of etNone:
              discard
        
        enemyIdx += 1
      
      # Clean up old hit times (>2 seconds ago) to prevent memory growth
      var toRemove: seq[int] = @[]
      for enemyIdx, hitTime in orb.lastHitTime:
        if game.time - hitTime > 2.0:
          toRemove.add(enemyIdx)
      for idx in toRemove:
        orb.lastHitTime.del(idx)

  
  # Check shooting
  let mousePos = getMousePosition()
  let shootDir = newVector2f(mousePos.x - game.player.pos.x, mousePos.y - game.player.pos.y)
  
  # Handle delayed double-shot bursts (rapid succession)
  # LEGENDARY Double Shot: Only 1 additional burst after 0.08s delay
  if game.player.doubleShotDelay > 0:
    game.player.doubleShotDelay -= dt
    
    # Fire second burst when delay reaches 0 (after 0.08s has elapsed)
    if game.player.doubleShotDelay <= 0:
      let hasMultiShot = hasPowerUp(game.player, puMultiShot)
      fireDoubleShotBurst(game, shootDir, hasMultiShot)
      game.player.doubleShotDelay = 0  # Reset to 0
  
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
    # Don't start a new wave if we're waiting for boss coin collection
    if not game.waveInProgress and not game.bossActive and not game.bossCoinActive and game.state == gsPlaying:
      # Start a new wave
      startWave(game)
    
    if game.waveInProgress and game.bossSpawnTimer <= 0:
      # DYNAMIC MULTIPLE ENEMY SPAWNING - scales more with wave number
      # More enemies spawn at once as waves progress
      let spawnCount = if game.currentWave <= 3: 1
                       elif game.currentWave <= 8: (if rand(100) < 50: 1 else: 2)
                       elif game.currentWave <= 15: (if rand(100) < 30: 1 elif rand(100) < 70: 2 else: 3)
                       elif game.currentWave <= 25: (if rand(100) < 20: 2 elif rand(100) < 60: 3 else: 4)
                       else: (if rand(100) < 15: 2 elif rand(100) < 45: 3 elif rand(100) < 75: 4 else: 5)
      
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
        
        # Regeneration power-up - heal variable HP per wave based on level
        if hasPowerUp(game.player, puRegeneration):
          let level = getPowerUpLevel(game.player, puRegeneration)
          var healAmount = 0
          
          case level
          of 1:
            # Level 1: 1-2 health (base)
            healAmount = 1 + rand(1)  # rand(1) gives 0 or 1
          of 2:
            # Level 2: 2-4 health (+1 to +2 bonus)
            healAmount = 2 + rand(2)  # 2, 3, or 4
          else:
            # Level 3: 3-6 health (+2 to +4 bonus)
            healAmount = 3 + rand(3)  # 3, 4, 5, or 6
          
          heal(game.player, healAmount.float32)
          spawnExplosion(game.particles, game.player.pos.x, game.player.pos.y, Green, 15)
        
        # Play wave complete sound
        playSound(stWaveComplete)

        # DON'T advance wave here if we're waiting for boss coin
        # The wave will advance when the boss coin is collected
        if not game.bossCoinActive:
          # Advance wave counters so the next wave uses the next wave number
          game.currentWave += 1
          game.wavesUntilBoss -= 1

        # ADJUSTED: Power-ups less frequent (every 2 waves instead of every wave)
        let shouldOfferPowerUp = (game.currentWave mod 2) == 0
        
        # Transition to wave cleared state for 0.3s to let players collect coins
        game.waveClearedTimer = 0.3
        game.state = gsWaveCleared
        
        # Store whether we should offer power-up after the timer
        # Store this in cameFromPowerUpSelect as a temporary flag
        game.cameFromPowerUpSelect = shouldOfferPowerUp or (game.wavesUntilBoss <= 0)
    
    # Boss wave spawning - don't spawn if there's a boss coin waiting to be collected
    if game.wavesUntilBoss == 0 and not game.bossActive and not game.bossCoinActive and game.state == gsPlaying:
      game.bossCount += 1
      # Scale boss difficulty based on wave number (every 3 waves = +1 difficulty)
      let bossDifficulty = (game.currentWave - 1).float32 / 3.0
      # FIX: Use currentWave + 1 since we haven't advanced the wave yet
      # The boss should spawn for the wave we're ABOUT to start, not the one we just finished
      let actualBossWave = game.currentWave + 1
      game.enemies.add(spawnBoss(game.screenWidth, game.screenHeight, 
                                bossDifficulty, game.bossCount, actualBossWave))
      game.bossActive = true
      game.bossSpawnTimer = 1.5  # Short warning, doesn't pause gameplay
      # Don't reset wavesUntilBoss here - it will be reset when boss coin is collected
      
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
      let enemy = spawnEnemy(game.screenWidth, game.screenHeight, game.difficulty)
      makeElite(enemy, (game.difficulty * 3).int)  # Use difficulty as wave equivalent
      game.enemies.add(enemy)
      game.spawnTimer = 0
      
      if isWaveActive and rand(100) < 60 and not game.bossActive:
        let waveEnemy = spawnEnemy(game.screenWidth, game.screenHeight, game.difficulty)
        makeElite(waveEnemy, (game.difficulty * 3).int)
        game.enemies.add(waveEnemy)
    
    # Boss spawn every 60 seconds
    if game.time >= game.bossTimer and not game.bossActive:
      game.bossCount += 1
      game.enemies.add(spawnBoss(game.screenWidth, game.screenHeight, game.difficulty, game.bossCount, game.currentWave))
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
    
    # Update elite effects (regeneration, etc.)
    updateEliteEffects(enemy, dt)
    
    # Update poison damage over time
    # Update all active effects for this enemy
    let effectDamage = updateEffects(enemy, effectiveDt)
    if effectDamage > 0:
      let actualDamage = applyEliteModifiers(enemy, effectDamage)
      enemy.hp -= actualDamage
    
    # Update chain lightning cooldown
    if enemy.chainLightningCooldown > 0:
      enemy.chainLightningCooldown -= effectiveDt  # Use slowed time
    
    # Update slow timer (from Chain Lightning stun and other effects)
    if enemy.slowTimer > 0:
      enemy.slowTimer -= effectiveDt
      if enemy.slowTimer <= 0:
        enemy.slowAmount = 0
    
    if not updateEnemy(enemy, game.player.pos, effectiveDt, game.walls, game.time, game):  # Use slowed time
      # Enemy died - drop coins and particles
      
      # Play enemy death sound
      playSound(stEnemyDeath, if enemy.isBoss: 1.0 else: 0.4)
      
      # Calculate coin value with elite multiplier
      var coinValue = if enemy.isBoss:
        # Boss drops scale with difficulty: 15 + 5 per difficulty level
        30 + (game.difficulty * 3.5).int
      else:
        # Regular enemies drop based on type, with minimal wave scaling
        # Every 10 waves adds 1 coin (very slow scaling) - REDUCED from 5 to 10
        let waveBonus = (game.currentWave div 10)  # Much slower scaling
        let baseValue = case enemy.enemyType
          of etCircle: 1
          of etCube: 3           # More coins since it's now harder
          of etTriangle: 2
          of etStar: 5
          of etHexagon: 3
          of etCross: 3
          of etDiamond: 3
          of etOctagon: 2
          of etPentagon: 1       # Early game enemy, low coins
          of etTrickster: 6
          of etPhantom: 6
          of etSniper: 5
        baseValue + waveBonus
      
      # Elite enemies drop 1.5x coins (less common but tougher)
      if enemy.isElite:
        coinValue = (coinValue.float32 * 1.5).int
      
      # Clamp coin position to be in bounds (for enemies killed out-of-bounds)
      let clampedPos = clampLootPosition(enemy.pos.x, enemy.pos.y, game.screenWidth, game.screenHeight)
      # Boss coins are special and must be collected to end the wave
      game.coins.add(newCoin(clampedPos.x, clampedPos.y, coinValue, enemy.isBoss))
      
      # Elite Explosive death effect
      # Handles multiple elite types (wave 25+)
      if enemy.isElite and etExplosive in enemy.eliteTypes:
        const eliteExplosionRadius = 100.0
        const eliteExplosionDamage = 2.0
        
        # Play explosion sound
        playSound(stExplosion, 0.7)
        
        # Check if player is in explosion radius
        let distToPlayer = distance(enemy.pos, game.player.pos)
        if distToPlayer < eliteExplosionRadius:
          if takeDamage(game.player, eliteExplosionDamage):
            game.state = gsGameOver
        
        # Create explosion visual
        spawnExplosion(game.particles, enemy.pos.x, enemy.pos.y, 
                      Color(r: 255, g: 128, b: 0, a: 255), 40)
        spawnShockwave(game.particles, enemy.pos.x, enemy.pos.y, eliteExplosionRadius)
      
      # Star explosion on death - damages player if too close
      if enemy.enemyType == etStar:
        const explosionRadius = 120.0  # LARGER explosion radius
        const explosionDamage = 2.0
        
        # Play explosion sound
        playSound(stExplosion, 0.8)
        
        # Check if player is in explosion radius
        let distToPlayer = distance(enemy.pos, game.player.pos)
        if distToPlayer < explosionRadius:
          if takeDamage(game.player, explosionDamage):
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
        # Clamp consumable position to be in bounds (for enemies killed out-of-bounds)
        let clampedPos = clampLootPosition(enemy.pos.x, enemy.pos.y, game.screenWidth, game.screenHeight)
        game.consumables.add(newConsumable(clampedPos.x, clampedPos.y, game.difficulty))
      
      game.player.kills += 1
      
      # Life steal power-up effect
      if hasPowerUp(game.player, puLifeSteal):
        let level = getPowerUpLevel(game.player, puLifeSteal)
        game.player.killsSinceLastHeal += 1
        let healsPerKills = case level
          of 1: 20
          of 2: 15
          else: 10
        
        if game.player.killsSinceLastHeal >= healsPerKills:
          heal(game.player, 1)
          game.player.killsSinceLastHeal = 0
          spawnExplosion(game.particles, game.player.pos.x, game.player.pos.y, Green, 15)
      
      # Check if boss was defeated
      if enemy.isBoss:
        bossDefeated = true
        game.bossActive = false
        
        # Mark that a boss coin is now active and must be collected
        game.bossCoinActive = true
        
        # Mode-specific boss defeat handling - NO longer advance wave here
        # Wave will advance when boss coin is collected
      
      game.enemies.delete(enemyIdx)
      continue
    
    enemyIdx += 1
  
  # Enemy-to-enemy collision detection (prevents overlapping)
  # Uses smaller collisionRadius for more natural-feeling spacing
  for i in 0..<game.enemies.len:
    for j in (i + 1)..<game.enemies.len:
      let dist = distance(game.enemies[i].pos, game.enemies[j].pos)
      let minDist = game.enemies[i].collisionRadius + game.enemies[j].collisionRadius
      
      if dist < minDist and dist > 0:
        # Enemies are overlapping - push them apart
        let overlap = minDist - dist
        let pushDir = (game.enemies[j].pos - game.enemies[i].pos).normalize()
        
        # Push each enemy half the overlap distance (equal force)
        let pushAmount = overlap * 0.5
        game.enemies[i].pos = game.enemies[i].pos - pushDir * pushAmount
        game.enemies[j].pos = game.enemies[j].pos + pushDir * pushAmount
  
  # Boss attack loop
  enemyIdx = 0
  while enemyIdx < game.enemies.len:
    let enemy = game.enemies[enemyIdx]
    
    # BOSS SPECIAL ATTACKS - HEAVILY BUFFED
    if enemy.isBoss:
      # Teleport ability
      if enemy.teleportTimer <= 0:
        # Short teleport burst
        var newX: float32
        var newY: float32
        var validTeleport = false
        
        # Keep trying to find a valid teleport position that's at least 10 pixels away from player
        for _ in 0..<10:
          let angle = rand(1.0) * PI * 2.0
          let teleportDist = 150 + rand(100).float32
          newX = enemy.pos.x + cos(angle) * teleportDist
          newY = enemy.pos.y + sin(angle) * teleportDist
          
          # Check distance to player - must be at least 10 pixels away
          let distToPlayer = distance(newVector2f(newX, newY), game.player.pos)
          if distToPlayer >= 10.0:
            validTeleport = true
            break
        
        # Only teleport if we found a valid position, otherwise skip this teleport
        if validTeleport:
          enemy.pos.x = newX
          enemy.pos.y = newY
          
          # Clamp to screen
          if enemy.pos.x < 50: enemy.pos.x = 50
          if enemy.pos.x > game.screenWidth.float32 - 50: enemy.pos.x = game.screenWidth.float32 - 50
          if enemy.pos.y < 50: enemy.pos.y = 50
          if enemy.pos.y > game.screenHeight.float32 - 50: enemy.pos.y = game.screenHeight.float32 - 50
          
          spawnExplosion(game.particles, enemy.pos.x, enemy.pos.y, Purple, 30)
        
        enemy.teleportTimer = 10.0 + rand(5.0)
      
      # Shockwave attack
      if enemy.shockwaveTimer <= 0:
        spawnShockwave(game.particles, enemy.pos.x, enemy.pos.y, enemy.radius + 100)
        
        # Spawn bullets in shockwave pattern - NERFED damage
        for angle in 0..<16:
          let rad = angle.float32 * PI / 8.0
          let dir = newVector2f(cos(rad), sin(rad))
          game.bullets.add(newBullet(
            x = enemy.pos.x,
            y = enemy.pos.y,
            direction = dir,
            speed = 220,
            damage = 0.75,
            fromPlayer = false,
            isBossBullet = true
          ))
        
        enemy.shockwaveTimer = 5.0 + rand(3.0)
      
      # Phase-based attacks WITH PROGRESSIVE ABILITIES
      # Bosses gain new abilities based on bossCount (how many bosses defeated)
      case enemy.bossPhase
      of bpCircle:
        # Original boss behavior + progressive abilities
        case enemy.bossType
        of btShooter:  # Spiral shooter
          if enemy.shootTimer > 0.8:
            # Basic spiral attack
            for angle in 0..<12:
              let rad = angle.float32 * PI / 6.0 + game.time * 2
              let dir = newVector2f(cos(rad), sin(rad))
              game.bullets.add(newBullet(
                x = enemy.pos.x,
                y = enemy.pos.y,
                direction = dir,
                speed = 240,
                damage = 0.75,
                fromPlayer = false,
                isBossBullet = true
              ))
            
            # PROGRESSIVE ABILITY: Rotating laser beams (unlocks at boss 2+)
            if game.bossCount >= 2:
              let laserAngle = game.time * 2.5  # Rotation speed
              for i in 0..<3:  # 3 rotating laser arms
                let armAngle = laserAngle + i.float32 * (PI * 2.0 / 3.0)
                game.lasers.add(newLaser(
                  enemy.pos.x, enemy.pos.y,
                  0,  # horizontal (will be rotated)
                  150.0,  # length
                  15.0,   # thickness
                  1,      # damage
                  0.1,    # very short lifetime (visual only)
                  armAngle  # rotation
                ))
            
            enemy.shootTimer = 0
        
        of btSummoner:  # Spawn minions
          if enemy.spawnTimer > 3.0:
            # Basic minion spawning
            for _ in 0..3:
              let angle = rand(1.0) * PI * 2
              let spawnDist = enemy.radius + 20
              let spawnX = enemy.pos.x + cos(angle) * spawnDist
              let spawnY = enemy.pos.y + sin(angle) * spawnDist
              game.enemies.add(newEnemy(spawnX, spawnY, game.difficulty, etCircle))
            
            # PROGRESSIVE ABILITY: Spawn near player (unlocks at boss 3+)
            if game.bossCount >= 3:
              for _ in 0..1:  # 2 enemies near player
                let angle = rand(1.0) * PI * 2
                let spawnDist = 120.0 + rand(50.0)
                let spawnX = game.player.pos.x + cos(angle) * spawnDist
                let spawnY = game.player.pos.y + sin(angle) * spawnDist
                # Clamp to screen bounds
                let clampedX = clamp(spawnX, 50.0, game.screenWidth.float32 - 50.0)
                let clampedY = clamp(spawnY, 50.0, game.screenHeight.float32 - 50.0)
                game.enemies.add(newEnemy(clampedX, clampedY, game.difficulty, etTriangle))
                # Warning particles
                spawnExplosion(game.particles, clampedX, clampedY, Red, 20)
            
            enemy.spawnTimer = 0
        
        of btCharger:  # Dash attacks
          if enemy.shootTimer > 2.0:
            let dir = (game.player.pos - enemy.pos).normalize()
            enemy.vel = dir * enemy.speed * 4.0
            
            # PROGRESSIVE ABILITY: Leave damaging trail (unlocks at boss 2+)
            if game.bossCount >= 2:
              # Spawn damage zone particles along dash path
              for i in 0..8:
                let trailPos = enemy.pos - dir * (i.float32 * 20.0)
                spawnExplosion(game.particles, trailPos.x, trailPos.y, 
                             Color(r: 255, g: 100, b: 0, a: 200), 12)
                
                # Damage player if in trail
                if distance(game.player.pos, trailPos) < 30:
                  if game.time - enemy.lastContactDamageTime >= 0.3:
                    if takeDamage(game.player, 1.0):
                      game.state = gsGameOver
                    enemy.lastContactDamageTime = game.time
            
            enemy.shootTimer = 0
        
        of btOrbit:  # Orbiting projectiles
          if enemy.shootTimer > 0.2:
            let angle = game.time * 4
            let orbitRadius = enemy.radius + 30
            for i in 0..<6:
              let a = angle + i.float32 * PI / 3.0
              let bulletX = enemy.pos.x + cos(a) * orbitRadius
              let bulletY = enemy.pos.y + sin(a) * orbitRadius
              let dir = (game.player.pos - newVector2f(bulletX, bulletY)).normalize()
              game.bullets.add(newBullet(
                x = bulletX,
                y = bulletY,
                direction = dir,
                speed = 200,
                damage = 0.75,
                fromPlayer = false,
                isBossBullet = true
              ))
            
            # PROGRESSIVE ABILITY: Homing orbital bullets (unlocks at boss 3+)
            if game.bossCount >= 3 and (game.time.int mod 3) == 0:  # Every 3 seconds
              let homingAngle = rand(1.0) * PI * 2.0
              let bulletX = enemy.pos.x + cos(homingAngle) * orbitRadius
              let bulletY = enemy.pos.y + sin(homingAngle) * orbitRadius
              let homingBullet = newBullet(
                x = bulletX,
                y = bulletY,
                direction = normalize(game.player.pos - newVector2f(bulletX, bulletY)),
                speed = 180.0,
                damage = 1.0'f32,
                fromPlayer = false,
                isHoming = true,
                isPiercing = false,
                isExplosive = false,
                hasBounce = false,
                canSplit = false,
                slowAmount = 0.0,
                poisonDuration = 0.0,
                fireDuration = 0.0,
                windPushForce = 0.0,
                isPentagon = false,
                isEcho = false,
                isBossBullet = true
              )
              game.bullets.add(homingBullet)
            
            enemy.shootTimer = 0
      
      of bpCube:
        # Defensive phase - shoots in all directions
        if enemy.burstTimer > 1.0:
          for angle in 0..<8:
            let rad = angle.float32 * PI / 4.0
            let dir = newVector2f(cos(rad), sin(rad))
            game.bullets.add(newBullet(
              x = enemy.pos.x,
              y = enemy.pos.y,
              direction = dir,
              speed = 200,
              damage = 0.75,
              fromPlayer = false,
              isBossBullet = true
            ))
          
          # PROGRESSIVE ABILITY: Cross lasers (unlocks at boss 4+)
          if game.bossCount >= 4:
            game.lasers.add(newLaser(
              enemy.pos.x, enemy.pos.y,
              2,  # cross pattern
              180.0,  # length
              20.0,   # thickness
              2,      # higher damage
              0.4,    # longer duration
              0.0     # no rotation
            ))
          
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
            game.bullets.add(newBullet(
              x = enemy.pos.x,
              y = enemy.pos.y,
              direction = spreadDir,
              speed = 280,
              damage = 0.75,
              fromPlayer = false,
              isBossBullet = true
            ))
          
          # PROGRESSIVE ABILITY: Predict player position (unlocks at boss 5+)
          if game.bossCount >= 5:
            # Calculate predicted player position based on velocity
            let predictTime = 0.5  # Predict 0.5 seconds ahead
            let predictedPos = game.player.pos + game.player.vel * predictTime
            let predictDir = (predictedPos - enemy.pos).normalize()
            game.bullets.add(newBullet(
              x = enemy.pos.x,
              y = enemy.pos.y,
              direction = predictDir,
              speed = 350,
              damage = 1.0,
              fromPlayer = false,
              isBossBullet = true
            ))
          
          enemy.burstTimer = 0
      
      of bpStar:
        # Bullet storm phase!
        if enemy.burstTimer > 0.15:
          let angle = rand(1.0) * PI * 2.0
          let dir = newVector2f(cos(angle), sin(angle))
          game.bullets.add(newBullet(
            x = enemy.pos.x,
            y = enemy.pos.y,
            direction = dir,
            speed = 250,
            damage = 0.75,
            fromPlayer = false,
            isBossBullet = true
          ))
          
          # PROGRESSIVE ABILITY: Star burst attack (unlocks at boss 6+)
          if game.bossCount >= 6 and (game.time * 100).int mod 100 == 0:  # Occasionally
            # Spawn 5-pointed star burst
            for i in 0..<5:
              let starAngle = i.float32 * (PI * 2.0 / 5.0)
              let starDir = newVector2f(cos(starAngle), sin(starAngle))
              game.bullets.add(newBullet(
                x = enemy.pos.x,
                y = enemy.pos.y,
                direction = starDir,
                speed = 300,
                damage = 1.0,
                fromPlayer = false,
                isBossBullet = true
              ))
          
          enemy.burstTimer = 0
    
    # Hexagon enemies shoot chaotically
    if enemy.enemyType == etHexagon and enemy.shootTimer > 1.2:
      # Shoot 2-4 bullets in random directions
      let bulletCount = 2 + rand(2)
      for _ in 0..<bulletCount:
        let angle = rand(1.0) * PI * 2.0
        let dir = newVector2f(cos(angle), sin(angle))
        game.bullets.add(newBullet(
          x = enemy.pos.x,
          y = enemy.pos.y,
          direction = dir,
          speed = 220,
          damage = 1,
          fromPlayer = false
        ))
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
        game.bullets.add(newBullet(
          x = enemy.pos.x,
          y = enemy.pos.y,
          direction = spreadDir,
          speed = 260,
          damage = 1,
          fromPlayer = false
        ))
      
      enemy.shootTimer = 0
    
    # Check collision with player (with small coyote/forgiveness zone on edges)
    # Reduce effective collision radius by 8% for slight edge forgiveness
    let effectivePlayerRadius = game.player.radius * 0.92  # 8% reduction = coyote
    if distance(enemy.pos, game.player.pos) < enemy.radius + effectivePlayerRadius:
      if enemy.isBoss:
        # Boss deals continuous damage
        if game.time - enemy.lastContactDamageTime >= 0.5:  # 2 HP per second
          var bossContactDamage = enemy.damage.float32
          
          # Thorns reflection damage
          if hasPowerUp(game.player, puThorns):
            let thornsLevel = getPowerUpLevel(game.player, puThorns)
            let reflectPercent = case thornsLevel
              of 1: 0.35  # BUFFED from 0.20 to 0.35
              of 2: 0.60  # BUFFED from 0.40 to 0.60
              else: 1.00  # BUFFED from 0.70 to 1.00 (full reflection!)
            let reflectDamageBase = bossContactDamage * reflectPercent
            let reflectDamageWithCrit = applyCriticalHit(game.player, reflectDamageBase)
            let actualDamage = applyEliteModifiers(enemy, reflectDamageWithCrit)
            enemy.hp -= actualDamage
            spawnExplosion(game.particles, enemy.pos.x, enemy.pos.y, Red, 8)
          
          if takeDamage(game.player, bossContactDamage):
            game.state = gsGameOver
          playSound(stPlayerHit, 0.6)
          enemy.lastContactDamageTime = game.time
          spawnExplosion(game.particles, game.player.pos.x, game.player.pos.y, Red, 10)
      else:
        # Regular enemies die on contact
        var enemyContactDamage = enemy.damage.float32
        
        # Venomous elite effect - applies poison to player
        # Handles multiple elite types (wave 25+)
        # NERFED: Reduced poison damage from 1.0 DPS to 0.5 DPS (1.5 total over 3s instead of 3.0)
        if enemy.isElite and etVenomous in enemy.eliteTypes:
          game.player.poisonTimer = 3.0  # 3 seconds of poison
          game.player.poisonDamage = 0.5  # 0.5 DPS = 1.5 total damage (NERFED from 1.0)
          game.player.poisonAccumulator = 0.0  # Reset accumulator for new poison application
          spawnExplosion(game.particles, game.player.pos.x, game.player.pos.y, Green, 10)
        
        # Thorns reflection damage - kills enemy if damage exceeds HP
        if hasPowerUp(game.player, puThorns):
          let thornsLevel = getPowerUpLevel(game.player, puThorns)
          let reflectPercent = case thornsLevel
            of 1: 0.35  # BUFFED from 0.20 to 0.35
            of 2: 0.60  # BUFFED from 0.40 to 0.60
            else: 1.00  # BUFFED from 0.70 to 1.00 (full reflection!)
          let reflectedDamageBase = enemyContactDamage * reflectPercent
          let reflectedDamageWithCrit = applyCriticalHit(game.player, reflectedDamageBase)
          let actualDamage = applyEliteModifiers(enemy, reflectedDamageWithCrit)
          enemy.hp -= actualDamage
          spawnExplosion(game.particles, enemy.pos.x, enemy.pos.y, Red, 6)
        
        if takeDamage(game.player, enemyContactDamage):
          game.state = gsGameOver
        playSound(stPlayerHit, 0.5)
        enemy.hp = 0
        game.enemies.delete(enemyIdx)
        continue
    
    enemyIdx += 1
  
  # If boss was defeated in TIME SURVIVAL mode, trigger power-up selection
  # In WAVE mode, power-ups are only given between waves, not on boss defeat
  if bossDefeated and game.mode == gmTimeSurvival:
    # Time survival: offer regular upgrades after boss
    game.powerUpChoices = generatePowerUpChoices(game.player, false)
    game.selectedPowerUp = 0
    initPowerUpRollAnimation(game)
    game.state = gsPowerUpSelect
    # Clear all enemies and bullets for clean screen
    game.enemies = @[]
    game.bullets = @[]
  
  # Update bullets
  i = 0
  while i < game.bullets.len:
    let bullet = game.bullets[i]
    
    # Homing bullet logic (LEGENDARY - Single Level)
    if bullet.isHoming and bullet.fromPlayer and game.enemies.len > 0:
      # NERF: Very limited tracking range - greatly reduced
      let trackingRange = 160.0  # Down from unlimited - much shorter range
      
      # Find nearest enemy that CAN be hit (not already pierced through)
      var nearestEnemy: Enemy = nil
      var nearestDist = 999999.0
      
      for enemyIdx in 0..<game.enemies.len:
        let enemy = game.enemies[enemyIdx]
        let dist = distance(bullet.pos, enemy.pos)
        
        # Only track if within range AND not already pierced/hit by this bullet
        if dist < trackingRange and dist < nearestDist and enemyIdx notin bullet.hitEnemies:
          nearestDist = dist
          nearestEnemy = enemy
      
      if nearestEnemy != nil:
        # LEGENDARY: Strong, balanced tracking - single level
        let turnRate = 0.05  # Good tracking without being overpowered
        
        let toEnemy = (nearestEnemy.pos - bullet.pos).normalize()
        let currentDir = bullet.vel.normalize()
        let newDir = (currentDir * (1.0 - turnRate) + toEnemy * turnRate).normalize()
        bullet.vel = newDir * bullet.vel.length()

    # Use effectiveDt for enemy bullets (slowed by Time Warp), normal dt for player bullets
    let bulletDt = if bullet.fromPlayer: dt else: effectiveDt
    if not updateBullet(bullet, bulletDt) or isOffScreen(bullet, game.screenWidth, game.screenHeight):
      game.bullets.delete(i)
      continue
    
    # Echo Shots - spawn ghost trail bullets (SINGLE LEVEL)
    if bullet.fromPlayer and not bullet.isEcho and hasPowerUp(game.player, puEchoShots):
      bullet.echoTrailTimer += bulletDt
      
      let spawnInterval = 0.08  # Single level - balanced spawn rate
      let echoDamageMultiplier = 0.40  # Single level - 40% damage
      
      if bullet.echoTrailTimer >= spawnInterval:
        bullet.echoTrailTimer = 0.0
        
        # Create echo bullet with full synergy support
        createEchoBullet(game, bullet, echoDamageMultiplier, 0.5, 0.35)

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
          
          # Calculate final damage with Overcharge modifier
          var finalDamage = bullet.damage
          if hasPowerUp(game.player, puOvercharge):
            let level = getPowerUpLevel(game.player, puOvercharge)
            let dmgPerUnit = 0.04 / 100.0  # +4% per 100 units traveled
            
            # Max bonus and range scale with level
            let maxBonus = case level
              of 1: 0.4  # Max 40% bonus
              of 2: 0.8  # Max 80% bonus
              else: 1.2  # Max 120% bonus
            
            # Max range for bonus (units traveled)
            let maxRange = case level
              of 1: 40.0   # Very short range
              of 2: 70.0   # Medium range
              else: 100.0  # Long range
            
            # Capped by both maxBonus and maxRange
            let distanceBonus = min(bullet.travelDistance * dmgPerUnit, bullet.travelDistance / maxRange * maxBonus)
            let bonusMultiplier = min(distanceBonus, maxBonus)
            finalDamage = bullet.damage * (1.0 + bonusMultiplier)
          
          if game.enemies[j].enemyType == etStar:
            # Stars use hit counter
            game.enemies[j].hitCount += 1
          else:
            # Apply elite modifiers to damage
            var actualDamage = finalDamage
            
            # Tank elite: 60% damage reduction (buffed from 50%)
            # Handles multiple elite types (wave 25+)
            if game.enemies[j].isElite and etTank in game.enemies[j].eliteTypes:
              actualDamage *= 0.4  # 60% reduction means 40% damage taken
            
            # Shielded elite: shield absorbs damage first
            if game.enemies[j].isElite and etShielded in game.enemies[j].eliteTypes and game.enemies[j].shieldHp > 0:
              if game.enemies[j].shieldHp >= actualDamage:
                # Shield absorbs all damage
                game.enemies[j].shieldHp -= actualDamage
                actualDamage = 0
              else:
                # Shield breaks, remaining damage goes to HP
                actualDamage -= game.enemies[j].shieldHp
                game.enemies[j].shieldHp = 0
            
            game.enemies[j].hp -= actualDamage
          hitEnemy = true
          
          # Apply frost shot slow effect - INDEFINITE (permanent until enemy dies)
          if bullet.slowAmount > 0 and hasPowerUp(game.player, puFrostShots):
            game.enemies[j].slowTimer = 999999.0  # Effectively infinite
            game.enemies[j].slowAmount = bullet.slowAmount
          
          # Apply poison damage over time
          if bullet.poisonDuration > 0 and hasPowerUp(game.player, puPoisonShot):
            let poisonLevel = getPowerUpLevel(game.player, puPoisonShot)
            let poisonBaseScaling = game.player.damage * 0.1
            var poisonDmg = case poisonLevel
              of 1: 1.0 + poisonBaseScaling
              of 2: 1.5 + poisonBaseScaling
              else: 2.0 + poisonBaseScaling
            var poisonDur = bullet.poisonDuration
            
            # Apply Poison Mastery bonuses if owned
            if game.player.hasPoisonMastery:
              poisonDmg *= 2.5  # +150% damage
              poisonDur *= 2.0  # +100% duration
            
            applyEffect(game.enemies[j], etPoison, poisonDmg, poisonDur, "shot")
            
            # Apply slow ONLY if player has Poison Mastery
            if game.player.hasPoisonMastery:
              game.enemies[j].slowTimer = max(game.enemies[j].slowTimer, poisonDur)
              game.enemies[j].slowAmount = max(game.enemies[j].slowAmount, 0.30)  # 30% slow
          
          # Apply fire damage over time
          if bullet.fireDuration > 0 and hasPowerUp(game.player, puFireBullets):
            let fireLevel = getPowerUpLevel(game.player, puFireBullets)
            let fireBaseScaling = game.player.damage * 0.1
            var fireDmg = case fireLevel
              of 1: 0.5 + fireBaseScaling
              of 2: 1.0 + fireBaseScaling
              else: 1.5 + fireBaseScaling
            var fireDur = bullet.fireDuration
            
            # Apply Fire Mastery bonuses if owned
            if game.player.hasFireMastery:
              fireDmg *= 2.5  # +150% damage
              fireDur *= 2.0  # +100% duration
            
            applyEffect(game.enemies[j], etFire, fireDmg, fireDur, "shot")
            
            # Apply slow ONLY if player has Fire Mastery
            if game.player.hasFireMastery:
              game.enemies[j].slowTimer = max(game.enemies[j].slowTimer, fireDur)
              game.enemies[j].slowAmount = max(game.enemies[j].slowAmount, 0.35)  # 35% slow
          
          # Apply wind push force (knock back effect)
          if bullet.windPushForce > 0 and hasPowerUp(game.player, puWindBullets):
            # Calculate push direction (away from player toward enemy)
            let pushDir = (game.enemies[j].pos - game.player.pos).normalize()
            # Bosses are much more resistant to wind push (10% effectiveness)
            let bossResistance = if game.enemies[j].isBoss: 0.1 else: 1.0
            
            # Apply Wind Mastery bonuses if owned
            var actualWindForce = bullet.windPushForce
            if game.player.hasWindMastery:
              actualWindForce *= 2.5  # Stronger push (+150%)
            
            # Apply knockback force
            game.enemies[j].pos.x += pushDir.x * actualWindForce * dt * bossResistance
            game.enemies[j].pos.y += pushDir.y * actualWindForce * dt * bossResistance
            
            # Apply slow ONLY if player has Wind Mastery
            if game.player.hasWindMastery:
              game.enemies[j].slowTimer = 0.2
              if game.enemies[j].slowAmount < 0.40:
                game.enemies[j].slowAmount = 0.40  # 40% slow
            
            # Visual wind effect particles
            for k in 0..3:
              let particleAngle = rand(1.0) * PI * 2.0
              let particleDist = rand(game.enemies[j].radius + 10.0)
              let particleX = game.enemies[j].pos.x + cos(particleAngle) * particleDist
              let particleY = game.enemies[j].pos.y + sin(particleAngle) * particleDist
              spawnExplosion(game.particles, particleX, particleY, 
                            Color(r: 200, g: 230, b: 255, a: 180), 2)
          
          # Chain lightning effect - hits nearby enemies
          if hasPowerUp(game.player, puChainLightning) and game.enemies[j].chainLightningCooldown <= 0:
            let chainLevel = getPowerUpLevel(game.player, puChainLightning)
            let chainCount = chainLevel  # 1, 2, or 3 chains
            let chainDamage = case chainLevel
              of 1: 0.7
              of 2: 0.8
              else: 0.9
            # Chain range increases with level: 120, 140, 160
            var chainRange = case chainLevel
              of 1: 120.0
              of 2: 140.0
              else: 160.0
            
            # Lightning Mastery increases range by 50%
            if game.player.hasLightningMastery:
              chainRange *= 1.5
            
            # Lightning bullets stun enemies for 0.05s (applied to primary target)
            game.enemies[j].slowTimer = max(game.enemies[j].slowTimer, 0.05)
            game.enemies[j].slowAmount = 1.0  # 100% slow = stun
            
            # Mark this enemy to prevent re-chaining
            game.enemies[j].chainLightningCooldown = 0.3
            
            # Find nearby enemies to chain to
            var chained = 0
            for k in 0..<game.enemies.len:
              if k != j and chained < chainCount:
                let dist = distance(game.enemies[j].pos, game.enemies[k].pos)
                if dist < chainRange and game.enemies[k].chainLightningCooldown <= 0:
                  let chainDmgBase = finalDamage * chainDamage
                  let chainDmgWithCrit = applyCriticalHit(game.player, chainDmgBase)
                  let actualDamage = applyEliteModifiers(game.enemies[k], chainDmgWithCrit)
                  game.enemies[k].hp -= actualDamage
                  game.enemies[k].chainLightningCooldown = 0.3
                  # Lightning also stuns chained enemies for 0.05s
                  game.enemies[k].slowTimer = max(game.enemies[k].slowTimer, 0.05)
                  game.enemies[k].slowAmount = 1.0  # 100% slow = stun
                  chained += 1
                  
                  # Lightning visual effect
                  for step in 0..10:
                    let t = step.float32 / 10.0
                    let x = game.enemies[j].pos.x + (game.enemies[k].pos.x - game.enemies[j].pos.x) * t
                    let y = game.enemies[j].pos.y + (game.enemies[k].pos.y - game.enemies[j].pos.y) * t
                    spawnExplosion(game.particles, x, y, Color(r: 255, g: 255, b: 100, a: 255), 2)
          
          # Bullet split on hit - SYNERGY: Inherits ALL bullet properties
          if hasPowerUp(game.player, puBulletSplit) and not bullet.hasSplit:
            let splitLevel = getPowerUpLevel(game.player, puBulletSplit)
            let splitCount = splitLevel + 1  # 2, 3, or 4 bullets
            
            # Use the new synergy system to create split bullets
            createSplitBullets(game, bullet, splitCount, 0.5, 0.7)
          
          # Vampirism healing - restore HP based on damage dealt
          if hasPowerUp(game.player, puVampirism):
            let vampLevel = getPowerUpLevel(game.player, puVampirism)
            let healPercent = case vampLevel
              of 1: 0.02  # 2.0% (reduced from 5%)
              of 2: 0.03  # 3.0% (reduced from 10%)
              else: 0.04  # 4.0% (reduced from 18%)
            let healAmount = finalDamage * healPercent
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
                let explosionDmg = finalDamage * 0.5
                let actualDamage = applyEliteModifiers(game.enemies[k], explosionDmg)
                game.enemies[k].hp -= actualDamage
            
            # Enhanced visual explosion with shockwave
            spawnExplosion(game.particles, bullet.pos.x, bullet.pos.y, Orange, 35)
            spawnExplosion(game.particles, bullet.pos.x, bullet.pos.y, Yellow, 20)
            spawnShockwave(game.particles, bullet.pos.x, bullet.pos.y, explosionRadius)
          
          # Piercing bullets can hit multiple enemies
          if bullet.isPiercing:
            let level = getPowerUpLevel(game.player, puPiercingShots)
            bullet.piercedEnemies += 1
            bullet.damage *= 0.67  # Reduce damage by 33% per pierce
            # Level 1 = pierce 1 (hit 2 total), Level 2 = pierce 2 (hit 3 total), etc.
            if bullet.piercedEnemies > level:
              hitEnemy = true  # Delete bullet after hitting level+1 enemies
            else:
              hitEnemy = false  # Don't delete bullet yet, continue piercing
          
          # Bullet ricochet off enemies - SYNERGY: Works with split and can trigger split on each hit
          if bullet.bounceCount >= 0 and not bullet.isPiercing:
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
                
                # SYNERGY: Reset split flag so ricochet bullets can split again on next hit
                if hasPowerUp(game.player, puBulletSplit):
                  bullet.hasSplit = false
                
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
        # Parry - bounce bullets back (LEGENDARY active ability)
        if game.player.parryActive:
          # Reverse bullet direction - bounce it back toward source
          let towardEnemy = (bullet.pos - game.player.pos).normalize()
          bullet.vel = towardEnemy * bullet.vel.length()
          bullet.fromPlayer = false  # Mark as enemy bullet so it can hit enemies
          
          # Visual effect for parry bounce
          spawnExplosion(game.particles, bullet.pos.x, bullet.pos.y, 
                        Color(r: 255, g: 255, b: 200, a: 255), 12)
          
          # Bullet continues bouncing, don't delete it
          i += 1
          continue
        
        var bulletDamage = 1.0
        
        # Thorns reflection - damage the originating enemy
        if hasPowerUp(game.player, puThorns):
          let thornsLevel = getPowerUpLevel(game.player, puThorns)
          let reflectPercent = case thornsLevel
            of 1: 0.35  # BUFFED from 0.20 to 0.35
            of 2: 0.60  # BUFFED from 0.40 to 0.60
            else: 1.00  # BUFFED from 0.70 to 1.00 (full reflection!)
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
            let actualDamage = applyEliteModifiers(nearestEnemy, reflectedDamage)
            nearestEnemy.hp -= actualDamage
            spawnExplosion(game.particles, nearestEnemy.pos.x, nearestEnemy.pos.y, Red, 5)
        
        if takeDamage(game.player, bulletDamage):
          game.state = gsGameOver
        hitEnemy = true
        spawnExplosion(game.particles, bullet.pos.x, bullet.pos.y, Red, 8)
    
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
      
      # Add subtle particle trail for magnet effect (frame-independent)
      # 30% @ 60fps = 18 particles/sec
      if rand(1.0) < (18.0 * dt):
        spawnExplosion(game.particles, game.coins[i].pos.x, game.coins[i].pos.y, 
                      Color(r: 255, g: 215, b: 0, a: 150), 1)
    
    # Enhanced magnet effect from consumable
    if game.player.magnetTimer > 0:
      moveCoinToPlayer(game.coins[i], game.player.pos, dt)
    
    # Collect coin on contact
    if checkPlayerCollision(game.coins[i], game.player):
      let isBossCoin = game.coins[i].isBossCoin
      game.player.coins += game.coins[i].value
      playSound(stCoinPickup, if isBossCoin: 0.8 else: 0.5)
      # Boss coins have red particles, regular coins have gold
      let coinParticleColor = if isBossCoin: Color(r: 255, g: 50, b: 50, a: 255) else: Gold
      spawnExplosion(game.particles, game.coins[i].pos.x, game.coins[i].pos.y, coinParticleColor, if isBossCoin: 20 else: 6)
      
      # If this was a boss coin, end the boss wave and advance
      if isBossCoin and game.bossCoinActive:
        game.bossCoinActive = false
        if game.mode == gmWaveBased:
          # Create explosion particles for all remaining enemies before clearing them
          for enemy in game.enemies:
            spawnExplosion(game.particles, enemy.pos.x, enemy.pos.y, 
                          Color(r: 255, g: 50, b: 50, a: 255), 15)
          
          # Clear all remaining enemies and bullets when boss wave completes
          game.enemies = @[]
          game.bullets = @[]
          
          # Reset wave enemy counters to prevent double wave advance
          game.waveEnemiesRemaining = 0
          game.waveInProgress = false
          
          # Advance to next wave after boss completion
          game.currentWave += 1
          game.wavesUntilBoss -= 1
          # Reset wavesUntilBoss if it hits 0 or below
          if game.wavesUntilBoss <= 0:
            game.wavesUntilBoss = 4  # Next boss in 5 waves (every 5 waves: 5, 10, 15, etc)
          
          # Offer LEGENDARY power-up after completing boss wave
          game.powerUpChoices = generatePowerUpChoices(game.player, true)
          game.selectedPowerUp = 0
          initPowerUpRollAnimation(game)
          game.state = gsPowerUpSelect
      
      game.coins.delete(i)
      continue
    
    i += 1
  
  # Update consumables
  i = 0
  while i < game.consumables.len:
    if not updateConsumable(game.consumables[i], dt):
      game.consumables.delete(i)
      continue
    
    # Check if consumable is in player's collection aura (auto-collect like coins)
    if isInPlayerAura(game.consumables[i], game.player):
      # Pull consumable toward player with magnet animation
      moveConsumableToPlayer(game.consumables[i], game.player.pos, dt)
      
      # Add subtle particle trail for magnet effect
      if rand(100) < 30:  # 30% chance per frame
        spawnExplosion(game.particles, game.consumables[i].pos.x, game.consumables[i].pos.y, 
                      Purple, 1)
    
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
        # Spawn 3 coins in random positions around the player
        for _ in 0..<3:
          let angle = rand(1.0) * PI * 2.0
          let distance = 50.0 + rand(150.0)
          let coinX = game.player.pos.x + cos(angle) * distance
          let coinY = game.player.pos.y + sin(angle) * distance
          # Clamp coin position to be in bounds (in case player is near edge)
          let clampedPos = clampLootPosition(coinX, coinY, game.screenWidth, game.screenHeight)
          game.coins.add(newCoin(clampedPos.x, clampedPos.y, 1))
      
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
  
  # CRITICAL SAFETY CHECK: Ensure player death is always detected
  # This catches edge cases where HP reaches 0 but game didn't transition to game over
  if game.player.hp <= 0 and game.state == gsPlaying:
    game.state = gsGameOver

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
  let hasOvercharge = hasPowerUp(game.player, puOvercharge)
  for bullet in game.bullets:
    drawBullet(bullet, hasOvercharge)
  
  # Draw enemies
  for enemy in game.enemies:
    # Draw elite aura first (so it appears behind the enemy)
    if enemy.isElite:
      drawEliteAura(enemy, game.time)
    drawEnemy(enemy)
  
  # Draw Gravity Well visual effect
  if hasPowerUp(game.player, puGravityWell):
    let level = getPowerUpLevel(game.player, puGravityWell)
    let pullRadius = if level == 1: 250.0 else: 350.0
    
    # Draw swirling vortex rings
    for ring in 1..4:
      let ringRadius = pullRadius * (ring.float32 / 4.0)
      let alpha = uint8(60 - ring * 10)
      let rotationOffset = (game.time * (ring.float32 * 0.5)).float32
      
      # Draw spiral dots around each ring
      for i in 0..15:
        let angle = (i.float32 / 16.0) * PI * 2.0 + rotationOffset
        let x = game.player.pos.x + cos(angle) * ringRadius
        let y = game.player.pos.y + sin(angle) * ringRadius
        drawCircle(Vector2(x: x, y: y), 3, Color(r: 75, g: 0, b: 130, a: alpha))
    
    # Draw outer radius circle (very faint)
    drawCircleLines(game.player.pos.x.int32, game.player.pos.y.int32, pullRadius, 
                   Color(r: 138, g: 43, b: 226, a: 40))
  
  # Draw Fire Aura visual effect
  if hasPowerUp(game.player, puFireAura):
    let level = getPowerUpLevel(game.player, puFireAura)
    let fireRadius = case level
      of 1: 120.0
      of 2: 160.0
      else: 200.0
    
    # IMPROVED: Multi-layered fire aura with better animation
    let pulse = (sin(game.time * 3.0) * 0.2 + 0.8).float32
    let flicker = (sin(game.time * 15.0) * 0.1 + 0.9).float32
    
    # Inner glow (bright core)
    drawCircle(Vector2(x: game.player.pos.x, y: game.player.pos.y), 
               fireRadius * 0.3 * pulse, Color(r: 255, g: 200, b: 100, a: 40))
    
    # Multiple animated fire rings with gradient
    for ring in 1..5:
      let progress = ring.float32 / 5.0
      let ringRadius = fireRadius * progress * pulse * flicker
      let alpha = uint8((60 - ring * 8).float32 * flicker)
      let redShift = uint8(255 - progress * 50)
      let greenShift = uint8(100 + progress * 50)
      drawCircleLines(game.player.pos.x.int32, game.player.pos.y.int32, ringRadius, 
                     Color(r: redShift, g: greenShift, b: 0, a: alpha))
    
    # Rotating flame wisps
    for i in 0..7:
      let angle = game.time * 2.0 + i.float32 * PI / 4.0
      let dist = fireRadius * 0.7 + sin(game.time * 3.0 + i.float32) * 15.0
      let x = game.player.pos.x + cos(angle) * dist
      let y = game.player.pos.y + sin(angle) * dist - abs(sin(game.time * 4.0 + i.float32)) * 8.0
      drawCircle(Vector2(x: x, y: y), 4 + sin(game.time * 5.0 + i.float32) * 2, 
                Color(r: 255, g: 150, b: 50, a: 180))
      drawCircle(Vector2(x: x, y: y - 2), 2, Color(r: 255, g: 255, b: 100, a: 220))
    
    # Outer border with ember particles
    drawCircleLines(game.player.pos.x.int32, game.player.pos.y.int32, fireRadius, 
                   Color(r: 255, g: 80, b: 0, a: 80))
  
  # Draw Lightning Aura visual effect
  if hasPowerUp(game.player, puLightningAura):
    let level = getPowerUpLevel(game.player, puLightningAura)
    let lightningRadius = case level
      of 1: 120.0
      of 2: 160.0
      else: 200.0
    
    # IMPROVED: Electric storm effect with crackling energy
    let pulse = (sin(game.time * 5.0) * 0.15 + 0.85).float32
    let crackle = (sin(game.time * 20.0) * 0.5 + 0.5).float32
    
    # Inner electric core
    drawCircle(Vector2(x: game.player.pos.x, y: game.player.pos.y), 
               lightningRadius * 0.25 * pulse, Color(r: 150, g: 200, b: 255, a: 50))
    
    # Animated electric arcs
    for arc in 1..4:
      let arcRadius = lightningRadius * (arc.float32 / 4.0) * pulse
      let alpha = uint8((50 - arc * 8).float32 * (0.7 + crackle * 0.3))
      drawCircleLines(game.player.pos.x.int32, game.player.pos.y.int32, arcRadius, 
                     Color(r: 150, g: 200, b: 255, a: alpha))
    
    # Lightning bolts shooting outward
    for i in 0..11:
      if (game.time * 10.0).int mod (i + 2) == 0:  # Sporadic bolts
        let angle = i.float32 * PI * 2.0 / 12.0 + game.time * 0.5
        let startDist = lightningRadius * 0.4
        let endDist = lightningRadius * 0.95
        let x1 = game.player.pos.x + cos(angle) * startDist
        let y1 = game.player.pos.y + sin(angle) * startDist
        let x2 = game.player.pos.x + cos(angle) * endDist
        let y2 = game.player.pos.y + sin(angle) * endDist
        
        # Jagged lightning effect
        var segments = 4
        var prevX = x1
        var prevY = y1
        for seg in 1..segments:
          let t = seg.float32 / segments.float32
          let nextX = x1 + (x2 - x1) * t + (if seg mod 2 == 0: -5.0 else: 5.0)
          let nextY = y1 + (y2 - y1) * t + (if seg mod 2 == 0: 5.0 else: -5.0)
          drawLine(Vector2(x: prevX, y: prevY), Vector2(x: nextX, y: nextY), 2, 
                  Color(r: 200, g: 220, b: 255, a: 200))
          prevX = nextX
          prevY = nextY
    
    # Outer border with electric glow
    drawCircleLines(game.player.pos.x.int32, game.player.pos.y.int32, lightningRadius, 
                   Color(r: 100, g: 180, b: 255, a: 70))
  
  # Draw Poison Aura visual effect
  if hasPowerUp(game.player, puPoisonAura):
    let level = getPowerUpLevel(game.player, puPoisonAura)
    let poisonRadius = case level
      of 1: 120.0
      of 2: 160.0
      else: 200.0
    
    # IMPROVED: Toxic cloud with floating bubbles
    let pulse = (sin(game.time * 2.5) * 0.25 + 0.75).float32
    let drift = game.time * 0.8
    
    # Dense toxic fog (inner)
    drawCircle(Vector2(x: game.player.pos.x, y: game.player.pos.y), 
               poisonRadius * 0.35 * pulse, Color(r: 80, g: 200, b: 80, a: 30))
    
    # Multiple toxic cloud layers
    for ring in 1..4:
      let ringRadius = poisonRadius * (ring.float32 / 4.0) * pulse
      let alpha = uint8((50 - ring * 10))
      drawCircleLines(game.player.pos.x.int32, game.player.pos.y.int32, ringRadius, 
                     Color(r: 100, g: 255, b: 100, a: alpha))
    
    # Floating toxic bubbles rising
    for i in 0..15:
      let angle = i.float32 * PI * 2.0 / 16.0
      let baseDist = poisonRadius * 0.6
      let floatOffset = sin(drift + i.float32 * 0.5) * 20.0
      let dist = baseDist + floatOffset
      let riseOffset = (game.time * 15.0 + i.float32 * 10.0) mod 30.0 - 15.0
      let x = game.player.pos.x + cos(angle) * dist
      let y = game.player.pos.y + sin(angle) * dist - riseOffset
      let bubbleSize = 3 + (i mod 3).float32
      
      # Bubble with highlight
      drawCircle(Vector2(x: x, y: y), bubbleSize, Color(r: 120, g: 255, b: 120, a: 160))
      drawCircle(Vector2(x: x - 1, y: y - 1), bubbleSize * 0.4, Color(r: 180, g: 255, b: 180, a: 200))
      drawCircleLines(x.int32, y.int32, bubbleSize, Color(r: 80, g: 200, b: 80, a: 200))
    
    # Outer border
    drawCircleLines(game.player.pos.x.int32, game.player.pos.y.int32, poisonRadius, 
                   Color(r: 80, g: 220, b: 80, a: 75))
  
  # Draw Wind Aura visual effect
  if hasPowerUp(game.player, puWindAura):
    let level = getPowerUpLevel(game.player, puWindAura)
    let windRadius = case level
      of 1: 120.0
      of 2: 160.0
      else: 200.0
    
    # IMPROVED: Swirling cyclone effect with dynamic air currents
    let rotationSpeed = game.time * 2.5
    let turbulence = sin(game.time * 3.0) * 0.1
    
    # Inner vortex core
    drawCircle(Vector2(x: game.player.pos.x, y: game.player.pos.y), 
               windRadius * 0.2, Color(r: 220, g: 240, b: 255, a: 35))
    
    # Spiraling wind streams (multiple layers)
    for ring in 1..4:
      let ringRadius = windRadius * (ring.float32 / 4.0)
      let spiralOffset = rotationSpeed * (1.0 + ring.float32 * 0.2)
      
      # Multiple wind streaks per ring
      for streak in 0..15:
        let baseAngle = (streak.float32 / 16.0) * PI * 2.0 + spiralOffset
        let angleVariation = turbulence * sin(streak.float32 * 0.5)
        let angle = baseAngle + angleVariation
        
        # Draw flowing wind lines with trail effect
        let segments = 3
        for seg in 0..<segments:
          let segProgress = seg.float32 / segments.float32
          let startDist = ringRadius * (0.9 + segProgress * 0.1)
          let endDist = ringRadius * (0.95 + segProgress * 0.15)
          let angleOffset = 0.15 + segProgress * 0.1
          
          let x1 = game.player.pos.x + cos(angle) * startDist
          let y1 = game.player.pos.y + sin(angle) * startDist
          let x2 = game.player.pos.x + cos(angle + angleOffset) * endDist
          let y2 = game.player.pos.y + sin(angle + angleOffset) * endDist
          
          let alpha = uint8((50 - ring * 8 - seg * 5).float32)
          drawLine(Vector2(x: x1, y: y1), Vector2(x: x2, y: y2), 2, 
                  Color(r: 200, g: 230, b: 255, a: alpha))
    
    # Floating air particles
    for i in 0..11:
      let angle = i.float32 * PI * 2.0 / 12.0 + rotationSpeed * 0.3
      let dist = windRadius * 0.7 + sin(game.time * 2.0 + i.float32) * 25.0
      let x = game.player.pos.x + cos(angle) * dist
      let y = game.player.pos.y + sin(angle) * dist
      drawCircle(Vector2(x: x, y: y), 2, Color(r: 220, g: 240, b: 255, a: 150))
    
    # Outer border
    drawCircleLines(game.player.pos.x.int32, game.player.pos.y.int32, windRadius, 
                   Color(r: 180, g: 220, b: 255, a: 65))
  
  # Draw Arcane Aura visual effect
  if hasPowerUp(game.player, puMagicAura):
    let level = getPowerUpLevel(game.player, puMagicAura)
    let arcaneRadius = case level
      of 1: 120.0
      of 2: 160.0
      else: 200.0
    
    # IMPROVED: Mystical arcane energy with orbiting runes
    let pulse = (sin(game.time * 3.5) * 0.2 + 0.8).float32
    let runeRotation = game.time * 1.5
    
    # Magical core glow
    drawCircle(Vector2(x: game.player.pos.x, y: game.player.pos.y), 
               arcaneRadius * 0.3 * pulse, Color(r: 200, g: 100, b: 255, a: 45))
    
    # Pulsing arcane rings with gradient
    for ring in 1..5:
      let progress = ring.float32 / 5.0
      let ringRadius = arcaneRadius * progress * pulse
      let alpha = uint8((55 - ring * 8).float32 * pulse)
      let colorShift = uint8(200 - progress * 50)
      drawCircleLines(game.player.pos.x.int32, game.player.pos.y.int32, ringRadius, 
                     Color(r: colorShift, g: 100, b: 255, a: alpha))
    
    # Orbiting arcane runes/symbols (outer ring)
    for i in 0..11:
      let angle = i.float32 * PI * 2.0 / 12.0 + runeRotation
      let dist = arcaneRadius * (0.85 + sin(game.time * 4.0 + angle) * 0.15)
      let x = game.player.pos.x + cos(angle) * dist
      let y = game.player.pos.y + sin(angle) * dist
      
      # Rune symbol (small cross/star pattern)
      let runeSize = 4 + sin(game.time * 5.0 + i.float32) * 2
      drawCircle(Vector2(x: x, y: y), runeSize, Color(r: 220, g: 150, b: 255, a: 220))
      # Rune glow
      drawCircle(Vector2(x: x, y: y), runeSize * 1.5, Color(r: 200, g: 100, b: 255, a: 80))
    
    # Floating sparkles (inner region)
    for i in 0..7:
      let angle = i.float32 * PI * 2.0 / 8.0 - runeRotation * 0.7
      let dist = arcaneRadius * 0.5 + sin(game.time * 3.0 + i.float32) * 20.0
      let x = game.player.pos.x + cos(angle) * dist
      let y = game.player.pos.y + sin(angle) * dist
      let sparkleSize = 2 + (sin(game.time * 6.0 + i.float32) * 1.5)
      drawCircle(Vector2(x: x, y: y), sparkleSize.float32, Color(r: 255, g: 200, b: 255, a: 180))
    
    # Outer arcane border
    drawCircleLines(game.player.pos.x.int32, game.player.pos.y.int32, arcaneRadius, 
                   Color(r: 200, g: 100, b: 255, a: 180))
  
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

  # Show FPS if enabled in settings (subtle display)
  if globalSettings != nil and globalSettings.showFPS:
    let fps = getFPS()
    # Subtle gray colors instead of bright colors
    let fpsColor = if fps >= 55: Color(r: 150, g: 150, b: 150, a: 200)  # Good FPS - light gray
                   elif fps >= 30: Color(r: 180, g: 160, b: 100, a: 200)  # Medium FPS - muted yellow
                   else: Color(r: 180, g: 120, b: 120, a: 200)  # Low FPS - muted red
    drawText("FPS: " & $fps, game.screenWidth - 100, 10, 16, fpsColor)  # Smaller font (16 instead of 20)
  
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
    elif game.bossCoinActive:
      # Show message when boss is defeated but coin not yet collected
      let pulseAlpha = (sin(game.time * 4.0) * 60 + 195).int.uint8
      drawText("Collect the Boss Coin!", 10, 160, 18, Color(r: 255, g: 215, b: 0, a: pulseAlpha))
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
    var puYOffset: int32 = 185
    drawText("Power-Ups:", 10, puYOffset, 16, Yellow)
    puYOffset += 20
    for powerUp in game.player.powerUps:
      let name = getPowerUpName(powerUp.powerType)
      drawText(name & " L" & $powerUp.level, 10, puYOffset.int32, 14, White)
      puYOffset += 18
  
  # Active powerup timers (right side) - ALL controlled by showDebugStats setting
  if globalSettings != nil and globalSettings.showDebugStats:
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
    
    # Show stats panel (damage and fire rate with 2 decimals)
    drawText("Damage: " & formatFloat(getCurrentDamage(game.player), ffDecimal, 2), game.screenWidth - 200, yOffset, 16, White)
    yOffset += 20
    let shotsPerSec = 1.0 / getCurrentFireRate(game.player)
    drawText("Fire Rate: " & formatFloat(shotsPerSec, ffDecimal, 2) & "/s", game.screenWidth - 200, yOffset, 16, White)
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
  
  # Legendary power-up display (bottom-left corner) - INLINE with Q key hint
  var legendaryYOffset: int32 = game.screenHeight - 80
  
  # Time Warp - only show if has uses available this wave OR actively timing down
  if hasPowerUp(game.player, puTimeWarp):
    let usesAvailable = game.player.timeWarpMaxUsesPerWave - game.player.timeWarpUsesThisWave
    # Show only if has uses left OR is active/on cooldown
    if usesAvailable > 0:
      if game.player.timeWarpActive:
        drawText("Chronos - Q: ACTIVE", 10, legendaryYOffset, 14, 
                Color(r: 200, g: 100, b: 255, a: 255))
        legendaryYOffset += 18
      elif game.player.timeWarpCooldown > 0:
        drawText("Chronos - Q: " & $(game.player.timeWarpCooldown.int + 1) & "s", 10, legendaryYOffset, 14, 
                Color(r: 100, g: 100, b: 100, a: 200))
        legendaryYOffset += 18
      else:
        drawText("Chronos - Q: Ready (" & $usesAvailable & "/" & $game.player.timeWarpMaxUsesPerWave & ")", 10, legendaryYOffset, 14,
                Color(r: 200, g: 100, b: 255, a: 255))
        legendaryYOffset += 18
  
  # Phase Shift - always show if available (has cooldown mechanic)
  if hasPowerUp(game.player, puPhaseShift):
    if game.player.phaseShiftInvulnTimer > 0:
      drawText("Phase - Q: DASH", 10, legendaryYOffset, 14, SkyBlue)
      legendaryYOffset += 18
    elif game.player.phaseShiftCooldown > 0:
      drawText("Phase - Q: " & $(game.player.phaseShiftCooldown.int + 1) & "s", 10, legendaryYOffset, 14,
              Color(r: 100, g: 100, b: 100, a: 200))
      legendaryYOffset += 18
    else:
      drawText("Phase - Q: Ready", 10, legendaryYOffset, 14, SkyBlue)
      legendaryYOffset += 18
  
  # Parry - active defense ability with cooldown display
  if hasPowerUp(game.player, puParry):
    if game.player.parryActive:
      drawText("Parry - Q: ACTIVE", 10, legendaryYOffset, 14, White)
      legendaryYOffset += 18
    elif game.player.parryCooldown > 0:
      drawText("Parry - Q: " & $(game.player.parryCooldown.int + 1) & "s", 10, legendaryYOffset, 14,
              Color(r: 100, g: 100, b: 100, a: 200))
      legendaryYOffset += 18
    else:
      drawText("Parry - Q: Ready", 10, legendaryYOffset, 14, White)
      legendaryYOffset += 18
  
  # Instructions only for non-legendary keys
  drawText("E: Wall | ESC: Pause", 
           game.screenWidth div 2 - 100, game.screenHeight - 25, 16, LightGray)
  
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
  
  # Show cheat indicator
  var yOffset = 120
  if game.cheatsUsed:
    drawText("Cheats Used: YES", game.screenWidth.int32 div 2 - 100, game.screenHeight.int32 div 2 + yOffset.int32, 20, Color(r: 255, g: 100, b: 100, a: 255))
  else:
    drawText("Cheats Used: NO", game.screenWidth div 2 - 95, game.screenHeight div 2 + yOffset.int32, 20, Color(r: 100, g: 255, b: 100, a: 255))
  
  drawText("Press R to restart or ESC to menu", game.screenWidth div 2 - 190, game.screenHeight div 2 + 160, 20, LightGray)

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
