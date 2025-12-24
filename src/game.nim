import raylib, types, player, enemy, bullet, consumable, coin, wall, shop, particle, powerup, sound, random, math, settings, tables, effects, strutils, boss_definitions, run_statistics

# CONFIGURABLE: Boss wave enemy spawn reduction (0.0 = no enemies, 1.0 = full enemies)
const BOSS_WAVE_SPAWN_MULTIPLIER = 0.5  # 50% of normal spawn

# ==================== BOSS WAVE MANAGER ====================
# Centralized boss wave and coin management

proc startBossWave*(manager: var BossWaveManager) =
  manager.active = true; manager.coinActive = false

proc bossDefeated*(manager: var BossWaveManager) =
  manager.active = false; manager.coinActive = true

proc bossCoinCollected*(manager: var BossWaveManager) =
  manager.coinActive = false

proc canStartNewWave*(manager: BossWaveManager): bool =
  not manager.active and not manager.coinActive

proc canSpawnBoss*(manager: BossWaveManager): bool =
  not manager.active and not manager.coinActive

proc isBossActive*(manager: BossWaveManager): bool = manager.active
proc isBossCoinActive*(manager: BossWaveManager): bool = manager.coinActive

proc completeBossWave*(game: Game) =
  ## Centralized boss wave completion - handles cleanup, advancement, power-up
  for enemy in game.enemies:
    spawnExplosion(game.particles, enemy.pos.x, enemy.pos.y, 
                  Color(r: 255, g: 50, b: 50, a: 255), 15)
  
  game.enemies = @[]
  game.bullets = @[]
  game.waveEnemiesRemaining = 0
  game.waveInProgress = false
  game.currentWave += 1
  game.wavesUntilBoss -= 1
  
  if game.wavesUntilBoss <= 0:
    game.wavesUntilBoss = 4  # Next boss in 5 waves
  
  game.powerUpChoices = generatePowerUpChoices(game.player, true)
  game.selectedPowerUp = 0
  initPowerUpRollAnimation(game)
  game.state = gsPowerUpSelect

# ==================== AURA SYSTEM REFACTORING ====================
# Unified aura configuration and rendering system to eliminate code duplication

type
  AuraVisualStyle = enum
    avsFlames         # Fire aura - rising flames and wisps
    avsLightning      # Lightning aura - electric arcs and bolts
    avsPoison         # Poison aura - toxic bubbles and fog
    avsWind           # Wind aura - swirling air currents
    avsArcane         # Arcane aura - orbiting runes and sparkles
    avsBlood          # Blood aura - dripping blood and mist

type
  AuraConfig = object
    radius: float32
    coreColor: Color
    ringColor: Color
    borderColor: Color
    pulseSpeed: float32
    visualStyle: AuraVisualStyle

# Aura configurations for each power-up type
proc getAuraConfig(auraType: PowerUpType, level: int): AuraConfig =
  let radius = case level
    of 1: 120.0
    of 2: 160.0
    else: 200.0
  
  case auraType
  of puFireAura:
    result = AuraConfig(
      radius: radius,
      coreColor: Color(r: 255, g: 200, b: 100, a: 40),
      ringColor: Color(r: 255, g: 100, b: 0, a: 60),
      borderColor: Color(r: 255, g: 80, b: 0, a: 80),
      pulseSpeed: 3.0,
      visualStyle: avsFlames
    )
  of puLightningAura:
    result = AuraConfig(
      radius: radius,
      coreColor: Color(r: 150, g: 200, b: 255, a: 50),
      ringColor: Color(r: 150, g: 200, b: 255, a: 50),
      borderColor: Color(r: 100, g: 180, b: 255, a: 70),
      pulseSpeed: 5.0,
      visualStyle: avsLightning
    )
  of puPoisonAura:
    result = AuraConfig(
      radius: radius,
      coreColor: Color(r: 80, g: 200, b: 80, a: 30),
      ringColor: Color(r: 100, g: 255, b: 100, a: 50),
      borderColor: Color(r: 80, g: 220, b: 80, a: 75),
      pulseSpeed: 2.5,
      visualStyle: avsPoison
    )
  of puWindAura:
    result = AuraConfig(
      radius: radius,
      coreColor: Color(r: 220, g: 240, b: 255, a: 35),
      ringColor: Color(r: 200, g: 230, b: 255, a: 50),
      borderColor: Color(r: 180, g: 220, b: 255, a: 65),
      pulseSpeed: 2.5,
      visualStyle: avsWind
    )
  of puArcaneAura:
    result = AuraConfig(
      radius: radius,
      coreColor: Color(r: 200, g: 100, b: 255, a: 45),
      ringColor: Color(r: 200, g: 100, b: 255, a: 55),
      borderColor: Color(r: 200, g: 100, b: 255, a: 180),
      pulseSpeed: 3.5,
      visualStyle: avsArcane
    )
  of puBloodAura:
    result = AuraConfig(
      radius: radius,
      coreColor: Color(r: 150, g: 30, b: 30, a: 50),
      ringColor: Color(r: 255, g: 50, b: 50, a: 60),
      borderColor: Color(r: 200, g: 40, b: 40, a: 85),
      pulseSpeed: 2.8,
      visualStyle: avsBlood
    )
  else:
    # Default fallback (should never happen)
    result = AuraConfig(
      radius: radius,
      coreColor: Color(r: 255, g: 255, b: 255, a: 50),
      ringColor: Color(r: 255, g: 255, b: 255, a: 50),
      borderColor: Color(r: 255, g: 255, b: 255, a: 100),
      pulseSpeed: 3.0,
      visualStyle: avsFlames
    )

proc drawAuraEffect(pos: Vector2f, config: AuraConfig, time: float32) =
  ## Unified aura drawing function that handles all visual styles
  let pulse = (sin(time * config.pulseSpeed) * 0.2 + 0.8).float32
  
  # Draw core glow (common to all auras)
  drawCircle(Vector2(x: pos.x, y: pos.y), 
             config.radius * 0.3 * pulse, config.coreColor)
  
  # Draw style-specific visuals
  case config.visualStyle
  of avsFlames:
    # Fire aura: animated fire rings with gradient
    let flicker = (sin(time * 15.0) * 0.1 + 0.9).float32
    for ring in 1..5:
      let progress = ring.float32 / 5.0
      let ringRadius = config.radius * progress * pulse * flicker
      let alpha = uint8((60 - ring * 8).float32 * flicker)
      let redShift = uint8(255 - progress * 50)
      let greenShift = uint8(100 + progress * 50)
      drawCircleLines(pos.x.int32, pos.y.int32, ringRadius, 
                     Color(r: redShift, g: greenShift, b: 0, a: alpha))
    
    # Rotating flame wisps
    for i in 0..7:
      let angle = time * 2.0 + i.float32 * PI / 4.0
      let dist = config.radius * 0.7 + sin(time * 3.0 + i.float32) * 15.0
      let x = pos.x + cos(angle) * dist
      let y = pos.y + sin(angle) * dist - abs(sin(time * 4.0 + i.float32)) * 8.0
      drawCircle(Vector2(x: x, y: y), 4 + sin(time * 5.0 + i.float32) * 2, 
                Color(r: 255, g: 150, b: 50, a: 180))
      drawCircle(Vector2(x: x, y: y - 2), 2, Color(r: 255, g: 255, b: 100, a: 220))
  
  of avsLightning:
    # Lightning aura: electric arcs and bolts
    let crackle = (sin(time * 20.0) * 0.5 + 0.5).float32
    
    # Animated electric arcs
    for arc in 1..4:
      let arcRadius = config.radius * (arc.float32 / 4.0) * pulse
      let alpha = uint8((50 - arc * 8).float32 * (0.7 + crackle * 0.3))
      drawCircleLines(pos.x.int32, pos.y.int32, arcRadius, 
                     Color(r: 150, g: 200, b: 255, a: alpha))
    
    # Lightning bolts shooting outward
    for i in 0..11:
      if (time * 10.0).int mod (i + 2) == 0:
        let angle = i.float32 * PI * 2.0 / 12.0 + time * 0.5
        let startDist = config.radius * 0.4
        let endDist = config.radius * 0.95
        let x1 = pos.x + cos(angle) * startDist
        let y1 = pos.y + sin(angle) * startDist
        let x2 = pos.x + cos(angle) * endDist
        let y2 = pos.y + sin(angle) * endDist
        
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
  
  of avsPoison:
    # Poison aura: toxic cloud with floating bubbles
    let drift = time * 0.8
    
    # Multiple toxic cloud layers
    for ring in 1..4:
      let ringRadius = config.radius * (ring.float32 / 4.0) * pulse
      let alpha = uint8((50 - ring * 10))
      drawCircleLines(pos.x.int32, pos.y.int32, ringRadius, 
                     Color(r: 100, g: 255, b: 100, a: alpha))
    
    # Floating toxic bubbles rising
    for i in 0..15:
      let angle = i.float32 * PI * 2.0 / 16.0
      let baseDist = config.radius * 0.6
      let floatOffset = sin(drift + i.float32 * 0.5) * 20.0
      let dist = baseDist + floatOffset
      let riseOffset = (time * 15.0 + i.float32 * 10.0) mod 30.0 - 15.0
      let x = pos.x + cos(angle) * dist
      let y = pos.y + sin(angle) * dist - riseOffset
      let bubbleSize = 3 + (i mod 3).float32
      
      drawCircle(Vector2(x: x, y: y), bubbleSize, Color(r: 120, g: 255, b: 120, a: 160))
      drawCircle(Vector2(x: x - 1, y: y - 1), bubbleSize * 0.4, Color(r: 180, g: 255, b: 180, a: 200))
      drawCircleLines(x.int32, y.int32, bubbleSize, Color(r: 80, g: 200, b: 80, a: 200))
  
  of avsWind:
    # Wind aura: swirling cyclone effect
    let rotationSpeed = time * 2.5
    let turbulence = sin(time * 3.0) * 0.1
    
    # Spiraling wind streams
    for ring in 1..4:
      let ringRadius = config.radius * (ring.float32 / 4.0)
      let spiralOffset = rotationSpeed * (1.0 + ring.float32 * 0.2)
      
      for streak in 0..15:
        let baseAngle = (streak.float32 / 16.0) * PI * 2.0 + spiralOffset
        let angleVariation = turbulence * sin(streak.float32 * 0.5)
        let angle = baseAngle + angleVariation
        
        let segments = 3
        for seg in 0..<segments:
          let segProgress = seg.float32 / segments.float32
          let startDist = ringRadius * (0.9 + segProgress * 0.1)
          let endDist = ringRadius * (0.95 + segProgress * 0.15)
          let angleOffset = 0.15 + segProgress * 0.1
          
          let x1 = pos.x + cos(angle) * startDist
          let y1 = pos.y + sin(angle) * startDist
          let x2 = pos.x + cos(angle + angleOffset) * endDist
          let y2 = pos.y + sin(angle + angleOffset) * endDist
          
          let alpha = uint8((50 - ring * 8 - seg * 5).float32)
          drawLine(Vector2(x: x1, y: y1), Vector2(x: x2, y: y2), 2, 
                  Color(r: 200, g: 230, b: 255, a: alpha))
    
    # Floating air particles
    for i in 0..11:
      let angle = i.float32 * PI * 2.0 / 12.0 + rotationSpeed * 0.3
      let dist = config.radius * 0.7 + sin(time * 2.0 + i.float32) * 25.0
      let x = pos.x + cos(angle) * dist
      let y = pos.y + sin(angle) * dist
      drawCircle(Vector2(x: x, y: y), 2, Color(r: 220, g: 240, b: 255, a: 150))
  
  of avsArcane:
    # Arcane aura: orbiting runes and sparkles
    let runeRotation = time * 1.5
    
    # Pulsing arcane rings with gradient
    for ring in 1..5:
      let progress = ring.float32 / 5.0
      let ringRadius = config.radius * progress * pulse
      let alpha = uint8((55 - ring * 8).float32 * pulse)
      let colorShift = uint8(200 - progress * 50)
      drawCircleLines(pos.x.int32, pos.y.int32, ringRadius, 
                     Color(r: colorShift, g: 100, b: 255, a: alpha))
    
    # Orbiting arcane runes
    for i in 0..11:
      let angle = i.float32 * PI * 2.0 / 12.0 + runeRotation
      let dist = config.radius * (0.85 + sin(time * 4.0 + angle) * 0.15)
      let x = pos.x + cos(angle) * dist
      let y = pos.y + sin(angle) * dist
      
      let runeSize = 4 + sin(time * 5.0 + i.float32) * 2
      drawCircle(Vector2(x: x, y: y), runeSize, Color(r: 220, g: 150, b: 255, a: 220))
      drawCircle(Vector2(x: x, y: y), runeSize * 1.5, Color(r: 200, g: 100, b: 255, a: 80))
    
    # Floating sparkles
    for i in 0..7:
      let angle = i.float32 * PI * 2.0 / 8.0 - runeRotation * 0.7
      let dist = config.radius * 0.5 + sin(time * 3.0 + i.float32) * 20.0
      let x = pos.x + cos(angle) * dist
      let y = pos.y + sin(angle) * dist
      let sparkleSize = 2 + (sin(time * 6.0 + i.float32) * 1.5)
      drawCircle(Vector2(x: x, y: y), sparkleSize.float32, Color(r: 255, g: 200, b: 255, a: 180))
  
  of avsBlood:
    # Blood aura: dripping blood and mist
    let heartbeat = abs(sin(time * 4.0))
    
    # Pulsing blood rings
    for ring in 1..4:
      let progress = ring.float32 / 4.0
      let ringRadius = config.radius * progress * pulse * (1.0 + heartbeat * 0.1)
      let alpha = uint8((60 - ring * 10).float32 * (0.8 + heartbeat * 0.2))
      let colorIntensity = uint8(255 - progress * 100)
      drawCircleLines(pos.x.int32, pos.y.int32, ringRadius, 
                     Color(r: colorIntensity, g: 50, b: 50, a: alpha))
    
    # Floating blood droplets
    for i in 0..13:
      let angle = i.float32 * PI * 2.0 / 14.0 + time * 0.5
      let dist = config.radius * 0.65 + sin(time * 2.5 + i.float32) * 15.0
      let dropFall = (time * 25.0 + i.float32 * 5.0) mod 40.0
      let x = pos.x + cos(angle) * dist
      let y = pos.y + sin(angle) * dist + dropFall - 20.0
      
      let dropSize = 4 - (dropFall / 20.0)
      if dropSize > 1.0:
        drawCircle(Vector2(x: x, y: y), dropSize.float32, Color(r: 200, g: 50, b: 50, a: 200))
        drawCircle(Vector2(x: x, y: y + 1), dropSize.float32 * 0.7, Color(r: 150, g: 30, b: 30, a: 200))
    
    # Swirling blood mist particles
    for i in 0..9:
      let angle = i.float32 * PI * 2.0 / 10.0 - time * 1.2
      let dist = config.radius * 0.8 + sin(time * 3.0 + i.float32) * 20.0
      let x = pos.x + cos(angle) * dist
      let y = pos.y + sin(angle) * dist
      drawCircle(Vector2(x: x, y: y), 3, Color(r: 255, g: 80, b: 80, a: 140))
    
    # Lifesteal heart symbols
    for corner in 0..3:
      let angle = corner.float32 * PI / 2.0 + PI / 4.0
      let dist = config.radius * 0.4
      let x = pos.x + cos(angle) * dist
      let y = pos.y + sin(angle) * dist
      let heartSize = 3 + heartbeat * 2
      
      drawCircle(Vector2(x: x - heartSize, y: y), heartSize, Color(r: 255, g: 100, b: 100, a: 180))
      drawCircle(Vector2(x: x + heartSize, y: y), heartSize, Color(r: 255, g: 100, b: 100, a: 180))
      drawCircle(Vector2(x: x, y: y + heartSize), heartSize * 1.2, Color(r: 255, g: 100, b: 100, a: 180))
  
  # Draw outer border (common to all auras)
  drawCircleLines(pos.x.int32, pos.y.int32, config.radius, config.borderColor)

# ==================== END AURA SYSTEM ====================

# CONFIGURABLE: Loot boundary margins (how far from edge loot can spawn)
const LOOT_MARGIN = 50.0  # Distance from screen edge

proc clampLootPosition(x, y: float32, screenWidth, screenHeight: int32): tuple[x, y: float32] =
  ## Clamps a position to be within screen bounds with margin
  ## Used to push loot spawned out-of-bounds back into playable area
  result.x = clamp(x, LOOT_MARGIN, screenWidth.float32 - LOOT_MARGIN)
  result.y = clamp(y, LOOT_MARGIN, screenHeight.float32 - LOOT_MARGIN)

proc applyEliteModifiers(enemy: Enemy, baseDamage: float32): float32 =
  ## Applies elite damage modifiers (tank reduction, shield absorption) and boss defense multiplier
  ## Returns the actual damage to apply to enemy HP
  ## Handles multiple elite types for wave 25+ elites
  result = baseDamage
  
  # Boss defense multiplier: reduces all incoming damage
  if enemy.isBoss and enemy.defenseMultiplier > 0:
    result *= enemy.defenseMultiplier
  
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

proc damageEnemy(enemy: Enemy, baseDamage: float32): float32 =
  ## Helper to apply damage to enemy with elite modifiers
  ## Combines applyEliteModifiers and HP reduction in one call
  ## Returns the actual damage dealt after modifiers
  result = applyEliteModifiers(enemy, baseDamage)
  enemy.hp -= result

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

# ============================================================================
# DAMAGE NUMBERS HELPER
# ============================================================================

proc showDamage*(game: Game, pos: Vector2f, damage: float32, fromPlayer: bool, 
                isCritical: bool = false, damageType: DamageType = dtDefault) =
  ## Centralized helper to create and display damage numbers
  game.damageNumbers.add(newDamageNumber(pos.x, pos.y, damage, fromPlayer, isCritical, damageType))

proc accumulateAndShowAuraDamage(game: Game, enemy: Enemy, actualDamage: float32,
                                  damageType: DamageType, wasCrit: bool = false) =
  ## Accumulates aura damage and displays damage numbers reliably
  ## Shows accumulated damage every 0.5 seconds to ensure visibility
  ## Handles shield absorption and zero-damage cases gracefully
  const DAMAGE_NUMBER_INTERVAL = 0.5  # Show damage numbers every 0.5 seconds
  
  # Initialize timer on first aura damage tick to prevent 0 damage reporting
  if enemy.lastAuraDamageNumberTime == 0:
    enemy.lastAuraDamageNumberTime = game.time
  
  # Accumulate damage (even if 0, we track it)
  enemy.auraDamageAccumulator += actualDamage
  
  # Check if enough time has passed to show a damage number
  let timeSinceLastNumber = game.time - enemy.lastAuraDamageNumberTime
  
  if timeSinceLastNumber >= DAMAGE_NUMBER_INTERVAL:
    # Time to show accumulated damage
    if enemy.auraDamageAccumulator > 0:
      # Convert accumulated damage to per-second rate for display
      let damagePerSecond = enemy.auraDamageAccumulator / timeSinceLastNumber
      
      game.showDamage(enemy.pos, damagePerSecond, fromPlayer = true, 
                      isCritical = wasCrit, damageType = damageType)
    
    # Reset accumulator and timer
    enemy.auraDamageAccumulator = 0
    enemy.lastAuraDamageNumberTime = game.time

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
    rerollCost: 0,  # Initialize reroll cost (set properly when entering power-up selection)
    bossWaveManager: BossWaveManager(active: false, coinActive: false),
    bossSpawnTimer: 0,
    cameFromPowerUpSelect: false,
    gameOverSoundPlayed: false,
    # Wave-based mode fields
    currentWave: 1,
    wavesUntilBoss: 4,  # Boss appears at waves 5, 10, 15, etc.
    waveEnemiesRemaining: 0,
    waveEnemiesTotal: 0,
    waveInProgress: false,
    waveStartTime: 0.0,
    # Cheat tracking
    cheatsUsed: false,  # Reset to false at start of each run
    # Mouse tracking for menu navigation
    lastMousePos: newVector2f(0, 0),
    mouseMovedRecently: false,
    keyboardUsedRecently: false,
    # State tracking for settings return
    previousState: gsMenu,  # Default to menu
    # Enemy ID counter for unique tracking
    nextEnemyId: 0,  # Start at 0, increment with each enemy created
    # Statistics menu tab
    statsMenuTab: 0  # 0 = Lifetime, 1 = Last Run
  )
  
  # Note: initializeRunTracking is called explicitly when starting a game
  # (not in sandbox mode) to ensure correct mode is tracked

proc calculateWaveEnemyCount(waveNumber: int): int =
  # Scale enemy count based on wave number (SLOWER PROGRESSION)
  # Start with 8 enemies, add 2-3 per wave
  result = 8 + (waveNumber - 1) * 2
  # Cap at 100 enemies per wave
  if result > 100:
    result = 100

proc startWave*(game: Game) =
  game.waveInProgress = true
  game.waveStartTime = game.time  # Track when this wave started
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
      let wave: int = game.currentWave
      let roll: int = rand(100)
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
        # Cube gets 30% spawn rate
        if roll < 30: enemyType = etCube  # NEW ENEMY - prominent
        elif roll < 45: enemyType = etCircle
        elif roll < 65: enemyType = etPentagon
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
        elif roll < 26: enemyType = etCube # Don't spawn circles or triangles after wave 50
        elif roll < 35: enemyType = etStar
        elif roll < 43: enemyType = etCross
        elif roll < 51: enemyType = etDiamond
        elif roll < 59: enemyType = etOctagon
        elif roll < 67: enemyType = etHexagon
        elif roll < 75: enemyType = etTrickster
        elif roll < 82: enemyType = etPentagon
        elif roll < 98: enemyType = etMage
        else: enemyType = etSniper
      
      # Difficulty scaling
      let baseDifficulty = (wave - 1).float32 / 3.0
      
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

proc checkWaveComplete*(game: Game): bool =
  # Wave is complete when all enemies are defeated, none remain to spawn, 
  # AND boss coin has been collected (if there was one)
  return game.waveEnemiesRemaining == 0 and game.enemies.len == 0 and not game.bossWaveManager.isBossCoinActive()

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
    let hasHoming: bool = hasPowerUp(game.player, puMagicalBullets)
    let hasPiercing: bool = hasPowerUp(game.player, puPiercingShots)
    let hasExplosive: bool = hasPowerUp(game.player, puExplosiveBullets)
    let hasDoubleShot: bool = hasPowerUp(game.player, puDoubleShot)
    let hasMultiShot: bool = hasPowerUp(game.player, puMultiShot)
    let hasRicochet: bool = hasPowerUp(game.player, puBulletRicochet)
    let hasSplit: bool = hasPowerUp(game.player, puBulletSplit)
    let hasFrost: bool = hasPowerUp(game.player, puFrostShots)
    let hasPoison: bool = hasPowerUp(game.player, puPoisonShot)
    let hasFire: bool = hasPowerUp(game.player, puFireBullets)
    let hasArcane: bool = hasPowerUp(game.player, puArcaneBullets)
    
    # Base bullet properties - use current damage with Rage bonus
    var speed = game.player.bulletSpeed * 1.2
    var damage = getCurrentDamage(game.player)
    
    # Track base damage before power-up multipliers for attribution
    let damageBeforePowerUps = game.player.damage  # Pure base damage (no Rage)
    
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
    
    # Track Bullet Damage power-up contribution
    # This power-up doubles base damage (applied in applyPowerUp)
    var bulletDamageBonus = 0.0
    if hasPowerUp(game.player, puBulletDamage):
      bulletDamageBonus = damageBeforePowerUps  # The extra 100% (base damage doubled)
    
    # Track Arcane Bullets contribution
    var arcaneBulletsBonus = 0.0
    if hasArcane:
      let arcaneLevel = getPowerUpLevel(game.player, puArcaneBullets)
      let arcaneMultiplier = case arcaneLevel
        of 1: 0.5   # +50%
        of 2: 1.0   # +100%
        else: 1.5   # +150%
      arcaneBulletsBonus = damageBeforePowerUps * arcaneMultiplier
    
    # Apply critical hit chance
    damage = applyCriticalHit(game.player, damage)
    
    # Apply Arcane Mastery bonus to Arcane bullets (damage + piercing)
    var arcanePiercing = hasPiercing  # Start with base piercing status
    var arcaneMasteryBonus = 0.0
    if hasArcane and game.player.hasArcaneMastery:
      let damageBeforeMastery = damage
      damage *= 3.0  # +200% additional damage on top of Arcane Bullets bonus
      arcaneMasteryBonus = damage - damageBeforeMastery  # The extra 200%
      arcanePiercing = true  # Grant piercing to Arcane bullets with mastery
    
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
      
      # Fire first burst (3 bullets = 1 normal + 2 bonus from Multi-Shot)
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
          isArcaneBullet = hasArcane,
          isBonusFromMultiShot = (i > 0)  # First bullet (i=0) is normal, rest are bonus
        )
        bullet.radius = bulletRadius
        game.bullets.add(bullet)
        trackBulletFired(game)  # Track shot for statistics
      
      # Schedule second burst with small delay (0.08s) - LEGENDARY Double Shot is single level
      # This second burst will also have 3 bullets, all marked as bonus from Double Shot
      game.player.doubleShotDelay = 0.08
    
    elif hasDoubleShot:
      # LEGENDARY: Fire 2 bullets in quick succession (single level only)
      # Fire first bullet immediately (this is the normal bullet)
      let bullet = newBullet(
        x = game.player.pos.x,
        y = game.player.pos.y,
        direction = direction,
        speed = speed,
        damage = damage,
        fromPlayer = true,
        isHoming = hasHoming,
        isPiercing = arcanePiercing,
        isExplosive = hasExplosive,
        hasBounce = hasRicochet,
        canSplit = hasSplit,
        slowAmount = slowEffect,
        poisonDuration = poisonEffect,
        fireDuration = fireEffect,
        windPushForce = windEffect,
        isArcaneBullet = hasArcane,
        isBonusFromDoubleShot = false  # First bullet is normal
      )
      bullet.radius = bulletRadius
      game.bullets.add(bullet)
      trackBulletFired(game)  # Track shot for statistics
      
      # Schedule second bullet with small delay (0.08s) - will be marked as bonus
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
          isArcaneBullet = hasArcane,
          isBonusFromMultiShot = (i > 0)  # First bullet (i=0) is normal, rest are bonus
        )
        bullet.radius = bulletRadius
        game.bullets.add(bullet)
        trackBulletFired(game)  # Track shot for statistics
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
        isPiercing = arcanePiercing,
        isExplosive = hasExplosive,
        hasBounce = hasRicochet,
        canSplit = hasSplit,
        slowAmount = slowEffect,
        poisonDuration = poisonEffect,
        fireDuration = fireEffect,
        windPushForce = windEffect,
        isArcaneBullet = hasArcane
      )
      bullet.radius = bulletRadius
      game.bullets.add(bullet)
      trackBulletFired(game)  # Track shot for statistics
    
    game.player.lastShot = game.time
    
    # Play shoot sound
    playSound(stShoot, 0.3)
    
    # Determine particle color based on bullet type - MATCHES BULLET COLOR
    var particleColor = Yellow  # Default
    if hasArcane: particleColor = Color(r: 200, g: 100, b: 255, a: 255)
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
  let hasHoming = hasPowerUp(game.player, puMagicalBullets)
  let hasPiercing = hasPowerUp(game.player, puPiercingShots)
  let hasExplosive = hasPowerUp(game.player, puExplosiveBullets)
  let hasRicochet = hasPowerUp(game.player, puBulletRicochet)
  let hasSplit = hasPowerUp(game.player, puBulletSplit)
  let hasFrost = hasPowerUp(game.player, puFrostShots)
  let hasPoison = hasPowerUp(game.player, puPoisonShot)
  let hasFire = hasPowerUp(game.player, puFireBullets)
  let hasArcane = hasPowerUp(game.player, puArcaneBullets)
  
  var speed = game.player.bulletSpeed * 1.2
  var damage = getCurrentDamage(game.player) * 0.85  # BUFFED: Second bullet reduced by 15% (was 25%)
  var bulletRadius = BASE_PLAYER_BULLET_RADIUS
  
  # Apply Arcane Mastery piercing bonus
  var arcanePiercing = hasPiercing
  if hasArcane and game.player.hasArcaneMastery:
    arcanePiercing = true  # Grant piercing to Arcane bullets with mastery
  
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
        isPiercing = arcanePiercing,
        isExplosive = hasExplosive,
        hasBounce = hasRicochet,
        canSplit = hasSplit,
        slowAmount = slowEffect,
        poisonDuration = poisonEffect,
        fireDuration = fireEffect,
        windPushForce = windEffect,
        isArcaneBullet = hasArcane,
        isBonusFromDoubleShot = true,  # Second burst is always bonus from Double Shot
        isBonusFromMultiShot = (i > 0)  # Side bullets also bonus from Multi-Shot
      )
      bullet.radius = bulletRadius
      game.bullets.add(bullet)
      trackBulletFired(game)  # Track shot for statistics
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
      isArcaneBullet = hasArcane,
      isBonusFromDoubleShot = true  # Second burst is bonus from Double Shot
    )
    bullet.radius = bulletRadius
    game.bullets.add(bullet)
    trackBulletFired(game)  # Track shot for statistics
  
  playSound(stShoot, 0.25)

proc updateCustomBossBehavior(game: Game, enemy: Enemy, phase: BossPhaseDefinition, dt: float32) =
  ## Updates boss movement based on phase specialBehavior
  if phase.specialBehavior == "":
    return  # No special behavior
  
  let playerDist = distance(enemy.pos, game.player.pos)
  let toPlayer = (game.player.pos - enemy.pos).normalize()
  let centerX = game.screenWidth.float32 / 2.0
  let centerY = game.screenHeight.float32 / 2.0
  
  case phase.specialBehavior
  of "circle_movement":
    # FIXED: Smooth velocity-based orbiting (no teleportation)
    # Calculate target position on circle
    let orbitRadius = 200.0
    let orbitSpeed = 0.4  # Radians per second
    let angle = game.time * orbitSpeed
    let targetX = centerX + cos(angle) * orbitRadius
    let targetY = centerY + sin(angle) * orbitRadius
    
    # Move toward target position smoothly using velocity
    let toTarget = (newVector2f(targetX, targetY) - enemy.pos).normalize()
    enemy.pos = enemy.pos + toTarget * enemy.speed * dt
  
  of "circle_player":
    # Orbit around player specifically
    let orbitRadius = 180.0
    let orbitSpeed = 80.0
    let angle = arctan2(enemy.pos.y - game.player.pos.y, enemy.pos.x - game.player.pos.x)
    let newAngle = angle + (orbitSpeed * dt / orbitRadius)
    enemy.pos.x = game.player.pos.x + cos(newAngle) * orbitRadius
    enemy.pos.y = game.player.pos.y + sin(newAngle) * orbitRadius
  
  of "aggressive":
    # Chase player directly
    enemy.pos = enemy.pos + toPlayer * enemy.speed * dt
  
  of "defensive":
    # Keep distance from player
    if playerDist < 250.0:
      let retreatDir = toPlayer * -1.0
      enemy.pos = enemy.pos + retreatDir * enemy.speed * 0.5 * dt
    else:
      # Drift toward center if far from player
      let toCenter = (newVector2f(centerX, centerY) - enemy.pos).normalize()
      enemy.pos = enemy.pos + toCenter * enemy.speed * 0.3 * dt
  
  of "geometric_movement":
    # Square/geometric pattern movement
    let patternPhase = game.time * 1.0
    let sinePhase = sin(patternPhase) * 150.0
    let cosinePhase = cos(patternPhase) * 150.0
    enemy.pos.x = centerX + sinePhase
    enemy.pos.y = centerY + cosinePhase
  
  of "teleport_pattern":
    # Occasionally teleport (handled via attacks, just face player here)
    if playerDist > 150.0:
      enemy.pos = enemy.pos + toPlayer * enemy.speed * dt * 0.5
  
  of "clone_assault":
    # Erratic movement toward player with sudden direction changes
    if game.time.int mod 2 == 0:  # Change direction every 2 seconds
      enemy.pos = enemy.pos + toPlayer * enemy.speed * dt
    else:
      let perpDir = newVector2f(-toPlayer.y, toPlayer.x)
      enemy.pos = enemy.pos + perpDir * enemy.speed * dt
  
  of "reality_break":
    # Chaotic unpredictable movement
    let randomAngle = rand(1.0) * PI * 2.0
    let randomDir = newVector2f(cos(randomAngle), sin(randomAngle))
    enemy.pos = enemy.pos + randomDir * enemy.speed * dt
  
  of "laser_web":
    # Stay in center, minimal movement
    let toCenter = (newVector2f(centerX, centerY) - enemy.pos).normalize()
    enemy.pos = enemy.pos + toCenter * 20.0 * dt  # Very slow drift to center
  
  of "laser_chaos":
    # Rapid erratic movement
    let angle = game.time * 3.0 + enemy.pos.x * 0.01
    let chaosDir = newVector2f(cos(angle), sin(angle))
    enemy.pos = enemy.pos + chaosDir * enemy.speed * dt * 0.8
  
  of "slow_charge":
    # Slow movement toward player, charging up
    enemy.pos = enemy.pos + toPlayer * enemy.speed * 0.3 * dt
  
  of "electric_storm":
    # Fast erratic movement
    let angle = game.time * 2.5
    let stormDir = newVector2f(cos(angle + enemy.pos.x * 0.02), sin(angle + enemy.pos.y * 0.02))
    enemy.pos = enemy.pos + stormDir * enemy.speed * dt
  
  of "overcharged":
    # Very fast aggressive movement
    enemy.pos = enemy.pos + toPlayer * enemy.speed * 1.2 * dt
  
  of "deploy_satellites":
    # Stationary in center
    enemy.pos = newVector2f(centerX, centerY)
  
  of "multi_orbital":
    # Slow rotation around player
    let orbitRadius = 150.0
    let orbitSpeed = 50.0
    let angle = arctan2(enemy.pos.y - game.player.pos.y, enemy.pos.x - game.player.pos.x)
    let newAngle = angle + (orbitSpeed * dt / orbitRadius)
    enemy.pos.x = game.player.pos.x + cos(newAngle) * orbitRadius
    enemy.pos.y = game.player.pos.y + sin(newAngle) * orbitRadius
  
  of "orbital_chaos":
    # Fast erratic orbital movement
    let orbitRadius = 200.0 + sin(game.time) * 50.0
    let orbitSpeed = 150.0
    let angle = arctan2(enemy.pos.y - game.player.pos.y, enemy.pos.x - game.player.pos.x)
    let newAngle = angle + (orbitSpeed * dt / orbitRadius)
    enemy.pos.x = game.player.pos.x + cos(newAngle) * orbitRadius
    enemy.pos.y = game.player.pos.y + sin(newAngle) * orbitRadius
  
  of "aggressive_chase":
    # Fast aggressive chase
    enemy.pos = enemy.pos + toPlayer * enemy.speed * 1.1 * dt
  
  of "enraged_assault":
    # Rapid aggressive movement with occasional direction change
    if game.time.int mod 3 == 0:
      enemy.pos = enemy.pos + toPlayer * enemy.speed * 1.3 * dt
    else:
      let sideDir = newVector2f(-toPlayer.y, toPlayer.x)
      enemy.pos = enemy.pos + sideDir * enemy.speed * dt
  
  of "unstoppable":
    # Extremely fast movement toward player
    enemy.pos = enemy.pos + toPlayer * enemy.speed * 1.5 * dt
  
  of "meteor_storm":
    # Rapid circling movement with erratic patterns (Meteor Striker phase 2)
    let meteorAngle = game.time * 2.0 + sin(game.time * 3.0) * 0.5
    let meteorRadius = 180.0 + cos(game.time * 1.5) * 30.0
    let meteorX = game.player.pos.x + cos(meteorAngle) * meteorRadius
    let meteorY = game.player.pos.y + sin(meteorAngle) * meteorRadius
    let toTarget = (newVector2f(meteorX, meteorY) - enemy.pos).normalize()
    enemy.pos = enemy.pos + toTarget * enemy.speed * dt
  
  of "summon_frenzy":
    # Defensive positioning with occasional aggressive bursts (Summoner King phase 2)
    if game.time.int mod 5 == 0:
      # Aggressive burst every 5 seconds
      enemy.pos = enemy.pos + toPlayer * enemy.speed * 1.2 * dt
    else:
      # Maintain defensive distance
      if playerDist < 220.0:
        let retreatDir = toPlayer * -1.0
        enemy.pos = enemy.pos + retreatDir * enemy.speed * 0.7 * dt
      else:
        # Slow drift toward center
        let toCenter = (newVector2f(centerX, centerY) - enemy.pos).normalize()
        enemy.pos = enemy.pos + toCenter * enemy.speed * 0.4 * dt
  
  of "berserk_rampage":
    # Extremely fast aggressive chase with wild movements (Berserker phase 3)
    let berserkerAngle = sin(game.time * 8.0) * 0.6
    let wildDir = newVector2f(
      toPlayer.x * cos(berserkerAngle) - toPlayer.y * sin(berserkerAngle),
      toPlayer.x * sin(berserkerAngle) + toPlayer.y * cos(berserkerAngle)
    )
    enemy.pos = enemy.pos + wildDir * enemy.speed * 1.6 * dt
  
  of "prism_defense":
    # Stationary with slight orbital movement (Prism Architect phase 1)
    let prismOrbitRadius = 80.0
    let prismAngle = game.time * 0.5
    let prismX = centerX + cos(prismAngle) * prismOrbitRadius
    let prismY = centerY + sin(prismAngle) * prismOrbitRadius
    let toOrbit = (newVector2f(prismX, prismY) - enemy.pos).normalize()
    enemy.pos = enemy.pos + toOrbit * enemy.speed * 0.6 * dt
  
  of "prism_array":
    # Figure-8 movement pattern (Prism Architect phase 2)
    let figure8Time = game.time * 1.5
    let figure8X = centerX + sin(figure8Time) * 150.0
    let figure8Y = centerY + sin(figure8Time * 2.0) * 100.0
    let toFigure8 = (newVector2f(figure8X, figure8Y) - enemy.pos).normalize()
    enemy.pos = enemy.pos + toFigure8 * enemy.speed * dt
  
  of "light_cascade":
    # Rapid sweeping movement across the arena (Prism Architect phase 3)
    let sweepAngle = game.time * 2.5
    let sweepRadius = 180.0
    let sweepX = centerX + cos(sweepAngle) * sweepRadius
    let sweepY = centerY + sin(sweepAngle) * sweepRadius
    enemy.pos = newVector2f(sweepX, sweepY)  # Direct teleportation for smooth sweep
  
  of "slow_time":
    # Very slow methodical movement (Timekeeper phase 1)
    enemy.pos = enemy.pos + toPlayer * enemy.speed * 0.4 * dt
  
  of "time_distortion":
    # Stuttering movement with temporal echoes (Timekeeper phase 2)
    if (game.time * 4.0).int mod 2 == 0:
      enemy.pos = enemy.pos + toPlayer * enemy.speed * 1.5 * dt
    # else: freeze in place (temporal pause)
  
  of "time_collapse":
    # Ultra-fast blinking movement (Timekeeper phase 3)
    let blinkFrequency = game.time * 6.0
    if (blinkFrequency).int mod 3 == 0:
      # Rapid blink toward player
      enemy.pos = enemy.pos + toPlayer * enemy.speed * 2.0 * dt
    else:
      # Strafe around player
      let strafeDir = newVector2f(-toPlayer.y, toPlayer.x)
      enemy.pos = enemy.pos + strafeDir * enemy.speed * 1.2 * dt
  
  of "chaotic_movement":
    # Unpredictable random movement (Chaos Weaver phase 1)
    let chaosAngle = rand(1.0) * PI * 2.0
    let chaosFactor = sin(game.time * 7.0 + enemy.pos.x * 0.03) * 0.8
    let chaosDir = newVector2f(cos(chaosAngle + chaosFactor), sin(chaosAngle + chaosFactor))
    enemy.pos = enemy.pos + chaosDir * enemy.speed * 0.9 * dt
  
  of "entropy_field":
    # Erratic spiraling with sudden direction changes (Chaos Weaver phase 2)
    let entropySpiral = game.time * 3.0 + sin(game.time * 5.0)
    let entropyRadius = 160.0 + sin(game.time * 2.0) * 40.0
    let entropyX = game.player.pos.x + cos(entropySpiral) * entropyRadius
    let entropyY = game.player.pos.y + sin(entropySpiral) * entropyRadius
    enemy.pos = newVector2f(entropyX, entropyY)
  
  of "total_chaos":
    # Maximum chaos - random teleports and movements (Chaos Weaver phase 3)
    if (game.time * 3.0).int mod 4 == 0:
      # Random teleport near player
      let chaosAngle = rand(1.0) * PI * 2.0
      let chaosDist = 120.0 + rand(80.0)
      enemy.pos = newVector2f(
        game.player.pos.x + cos(chaosAngle) * chaosDist,
        game.player.pos.y + sin(chaosAngle) * chaosDist
      )
    else:
      # Wild erratic movement
      let wildAngle = game.time * 10.0 + rand(1.0)
      let wildDir = newVector2f(cos(wildAngle), sin(wildAngle))
      enemy.pos = enemy.pos + wildDir * enemy.speed * 1.4 * dt
  
  of "balanced_assault":
    # Steady circling with balanced approach (Omega Entity phase 1)
    let balanceAngle = game.time * 1.2
    let balanceRadius = 190.0
    let balanceX = centerX + cos(balanceAngle) * balanceRadius
    let balanceY = centerY + sin(balanceAngle) * balanceRadius
    let toBalance = (newVector2f(balanceX, balanceY) - enemy.pos).normalize()
    enemy.pos = enemy.pos + toBalance * enemy.speed * dt
  
  of "aggressive_mixed":
    # Alternating between chase and strafe (Omega Entity phase 2)
    if (game.time * 2.0).int mod 3 == 0:
      enemy.pos = enemy.pos + toPlayer * enemy.speed * 1.2 * dt
    else:
      let mixedStrafe = newVector2f(-toPlayer.y, toPlayer.x)
      enemy.pos = enemy.pos + mixedStrafe * enemy.speed * 0.9 * dt
  
  of "adaptive_combat":
    # Smart positioning based on player distance (Omega Entity phase 3)
    if playerDist < 150.0:
      # Retreat and reposition
      let adaptRetreat = toPlayer * -1.0
      enemy.pos = enemy.pos + adaptRetreat * enemy.speed * 1.1 * dt
    elif playerDist > 280.0:
      # Close distance aggressively
      enemy.pos = enemy.pos + toPlayer * enemy.speed * 1.3 * dt
    else:
      # Optimal range - circle strafe
      let adaptStrafe = newVector2f(-toPlayer.y, toPlayer.x)
      enemy.pos = enemy.pos + adaptStrafe * enemy.speed * dt
  
  of "final_form":
    # Ultimate pattern - combines teleportation, aggression, and unpredictability (Omega Entity phase 4)
    let finalPhase = (game.time * 4.0).int mod 6
    case finalPhase
    of 0, 1:
      # Aggressive chase
      enemy.pos = enemy.pos + toPlayer * enemy.speed * 1.8 * dt
    of 2:
      # Rapid teleport near player
      let finalAngle = rand(1.0) * PI * 2.0
      enemy.pos = newVector2f(
        game.player.pos.x + cos(finalAngle) * 140.0,
        game.player.pos.y + sin(finalAngle) * 140.0
      )
    of 3, 4:
      # Circle strafe at high speed
      let finalOrbitAngle = game.time * 5.0
      let finalOrbitRadius = 180.0
      enemy.pos.x = game.player.pos.x + cos(finalOrbitAngle) * finalOrbitRadius
      enemy.pos.y = game.player.pos.y + sin(finalOrbitAngle) * finalOrbitRadius
    else:
      # Erratic chaos movement
      let chaosAngle = game.time * 8.0 + sin(game.time * 3.0)
      let chaosDir = newVector2f(cos(chaosAngle), sin(chaosAngle))
      enemy.pos = enemy.pos + chaosDir * enemy.speed * 1.5 * dt
  
  else:
    discard

proc executeCustomBossAttack(game: Game, enemy: Enemy, attack: BossAttack, phase: BossPhaseDefinition, bossDef: BossDefinition) =
  ## Executes a single boss attack based on its pattern type
  let toPlayer = (game.player.pos - enemy.pos).normalize()
  
  case attack.attackType
  of bapSpiral:
    # Rotating spiral pattern
    for i in 0..<attack.projectileCount:
      let angle = i.float32 * PI * 2.0 / attack.projectileCount.float32 + game.time * attack.spreadAngle.degToRad()
      let dir = newVector2f(cos(angle), sin(angle))
      game.bullets.add(newBullet(
        x = enemy.pos.x, y = enemy.pos.y, direction = dir,
        speed = attack.projectileSpeed, damage = attack.damage * phase.damageMultiplier,
        fromPlayer = false, isBossBullet = true, sourceEnemyId = enemy.id
      ))
  
  of bapBurst:
    # Rapid burst in spread pattern
    let baseAngle = arctan2(toPlayer.y, toPlayer.x)
    for i in 0..<attack.projectileCount:
      let offset = (i.float32 - attack.projectileCount.float32 / 2.0) * attack.spreadAngle.degToRad() / attack.projectileCount.float32
      let angle = baseAngle + offset
      let dir = newVector2f(cos(angle), sin(angle))
      game.bullets.add(newBullet(
        x = enemy.pos.x, y = enemy.pos.y, direction = dir,
        speed = attack.projectileSpeed, damage = attack.damage * phase.damageMultiplier,
        fromPlayer = false, isBossBullet = true, sourceEnemyId = enemy.id
      ))
  
  of bapWave:
    # Sine wave pattern
    for i in 0..<attack.projectileCount:
      let t = i.float32 / attack.projectileCount.float32
      let angle = t * attack.spreadAngle.degToRad() - attack.spreadAngle.degToRad() / 2.0 + arctan2(toPlayer.y, toPlayer.x)
      let dir = newVector2f(cos(angle), sin(angle))
      game.bullets.add(newBullet(
        x = enemy.pos.x, y = enemy.pos.y, direction = dir,
        speed = attack.projectileSpeed, damage = attack.damage * phase.damageMultiplier,
        fromPlayer = false, isBossBullet = true, sourceEnemyId = enemy.id
      ))
  
  of bapTargeted:
    # Direct shots at player
    for i in 0..<attack.projectileCount:
      let spread = if attack.projectileCount > 1:
        (i.float32 - attack.projectileCount.float32 / 2.0) * attack.spreadAngle.degToRad() / attack.projectileCount.float32
      else: 0.0
      let angle = arctan2(toPlayer.y, toPlayer.x) + spread
      let dir = newVector2f(cos(angle), sin(angle))
      game.bullets.add(newBullet(
        x = enemy.pos.x, y = enemy.pos.y, direction = dir,
        speed = attack.projectileSpeed, damage = attack.damage * phase.damageMultiplier,
        fromPlayer = false, isBossBullet = true, sourceEnemyId = enemy.id
      ))
  
  of bapCircle:
    # Perfect circle of bullets
    for i in 0..<attack.projectileCount:
      let angle = i.float32 * PI * 2.0 / attack.projectileCount.float32
      let dir = newVector2f(cos(angle), sin(angle))
      game.bullets.add(newBullet(
        x = enemy.pos.x, y = enemy.pos.y, direction = dir,
        speed = attack.projectileSpeed, damage = attack.damage * phase.damageMultiplier,
        fromPlayer = false, isBossBullet = true, sourceEnemyId = enemy.id
      ))
  
  of bapLaser:
    # IMPROVED: Boss laser with proper warning system
    # Laser patterns customized via specialData
    # "cross_laser" = standard cross pattern (4 perpendicular beams)
    # "rotating_grid" = rotating grid of lasers (cross pattern)
    # "prismatic_cage" = many random lasers biased towards player
    # "laser_snipe" = rapid-fire lasers aimed directly at player
    
    let patternType = attack.specialData
    let laserCount = case patternType
      of "rotating_grid": attack.projectileCount * 2  # Double density for grid
      of "prismatic_cage": attack.projectileCount * 3  # Triple density for cage
      else: attack.projectileCount
    
    # Calculate all laser angles for the warning system
    var warningAngles: seq[float32] = @[]
    
    # FIX: For cross_laser pattern, always create 4 beams (cardinal directions)
    let actualLaserCount = if patternType == "cross_laser": 4 else: laserCount
    
    for i in 0..<actualLaserCount:
      let angle = case patternType
        of "rotating_grid":
          # Grid pattern - two perpendicular sets
          if i.float < actualLaserCount / 2:
            i.float32 * attack.spreadAngle.degToRad() / (actualLaserCount / 2).float32
          else:
            (i.float32 - actualLaserCount.float / 2.0) * attack.spreadAngle.degToRad() / (actualLaserCount / 2).float32 + PI / 2.0
        of "prismatic_cage":
          # Random radial lasers biased towards player direction
          # 60% of lasers aim near player, 40% are completely random
          let angleToPlayer = arctan2(game.player.pos.y - enemy.pos.y, game.player.pos.x - enemy.pos.x)
          if rand(100) < 60:
            # Aim near player with some spread (±45 degrees)
            angleToPlayer + (rand(1.0) - 0.5) * (PI / 2.0)
          else:
            # Completely random direction
            rand(1.0) * PI * 2.0
        of "laser_snipe":
          # Rapid fire lasers aimed directly at player with minimal spread
          let angleToPlayer = arctan2(game.player.pos.y - enemy.pos.y, game.player.pos.x - enemy.pos.x)
          # Very tight spread around player position (±5 degrees)
          angleToPlayer + (rand(1.0) - 0.5) * 0.175
        of "cross_laser":
          # Cross pattern - always 4 beams in cardinal directions (0°, 90°, 180°, 270°)
          i.float32 * (PI / 2.0) + game.time
        else:
          # Default pattern - distribute evenly
          i.float32 * (PI * 2.0) / actualLaserCount.float32 + game.time
      warningAngles.add(angle)
    
    # Add boss laser warning with proper visual indicators
    # WARNING: Show for 1.2 seconds before firing (much longer than current 0.3s)
    const BOSS_LASER_WARNING_TIME = 1.2
    let laserDamage = (attack.damage * phase.damageMultiplier).int
    
    # Adjust laser length based on pattern type
    # For prismatic_cage and laser_snipe, calculate length to reach screen edge
    # Use diagonal distance from center to corner to ensure full coverage
    let laserLength = if patternType in ["prismatic_cage", "laser_snipe"]:
      # Calculate diagonal distance from center to corner for full screen coverage
      # Add extra margin to guarantee lasers always reach beyond screen edges
      let centerX = game.screenWidth.float32 / 2.0
      let centerY = game.screenHeight.float32 / 2.0
      let diagonalDistance = sqrt(centerX * centerX + centerY * centerY)
      # Use 1.5x diagonal distance to ensure lasers always extend beyond screen
      diagonalDistance * 1.5
    else:
      800.0
    
    game.attackWarnings.add(newBossLaserWarning(
      enemy.pos.x, enemy.pos.y, 
      BOSS_LASER_WARNING_TIME,
      warningAngles,
      laserLength,  # Adjusted based on pattern type
      laserDamage,
      attack.durationOrRadius,  # Laser active duration
      patternType,  # Pass the pattern type for proper laser creation
      enemy.enemyType,  # Track which enemy type created this attack
      enemy.id  # Pass enemy ID so warning can follow boss
    ))
    
    # NOTE: Lasers are NOT created immediately
    # They will be created when warning lifetime reaches 0 (handled in updateGame)
  
  of bapBarrage:
    # Massive bullet spray
    for i in 0..<attack.projectileCount:
      let angle = i.float32 * PI * 2.0 / attack.projectileCount.float32
      let dir = newVector2f(cos(angle), sin(angle))
      game.bullets.add(newBullet(
        x = enemy.pos.x, y = enemy.pos.y, direction = dir,
        speed = attack.projectileSpeed, damage = attack.damage * phase.damageMultiplier,
        fromPlayer = false, isBossBullet = true, sourceEnemyId = enemy.id
      ))
  
  of bapPulse:
    # Expanding ring (handled as circle with specific speed)
    for i in 0..<24:  # Fixed count for pulse
      let angle = i.float32 * PI * 2.0 / 24.0
      let dir = newVector2f(cos(angle), sin(angle))
      game.bullets.add(newBullet(
        x = enemy.pos.x, y = enemy.pos.y, direction = dir,
        speed = attack.projectileSpeed, damage = attack.damage * phase.damageMultiplier,
        fromPlayer = false, isBossBullet = true, sourceEnemyId = enemy.id
      ))
  
  of bapSummon:
    # Spawn minion enemies around the boss - customizable via specialData
    # Parse specialData to determine minion types: "minion_circle", "minion_triangle", "minion_mixed"
    var minionType = etCircle  # Default
    var useVariation = false
    
    if attack.specialData != "":
      case attack.specialData
      of "minion_circle":
        minionType = etCircle
      of "minion_triangle":
        minionType = etTriangle
      of "minion_cube":
        minionType = etCube
      of "minion_pentagon":
        minionType = etPentagon
      of "minion_mixed":
        useVariation = true  # Vary minion types
      else:
        minionType = etCircle
    
    # CAP: Count existing boss-spawned enemies to prevent overwhelming defensive builds
    var bossSpawnedCount = 0
    for e in game.enemies:
      if e.spawnedByBoss:
        bossSpawnedCount += 1
    
    # Maximum boss-spawned enemies allowed at once (configurable cap)
    const MAX_BOSS_SPAWNED_ENEMIES = 12
    
    # Calculate how many we can actually spawn
    let maxToSpawn = max(0, MAX_BOSS_SPAWNED_ENEMIES - bossSpawnedCount)
    let actualSpawnCount = min(attack.projectileCount, maxToSpawn)
    
    # Only proceed if we can spawn at least one enemy
    if actualSpawnCount <= 0:
      # Skip spawning but still show visual feedback
      spawnExplosion(game.particles, enemy.pos.x, enemy.pos.y, phase.color, 8)
    else:
      for i in 0..<actualSpawnCount:
        let angle = i.float32 * PI * 2.0 / actualSpawnCount.float32
        let spawnDist = enemy.radius + 60.0  # Spawn outside boss radius
        let spawnX = enemy.pos.x + cos(angle) * spawnDist
        let spawnY = enemy.pos.y + sin(angle) * spawnDist
        
        # Determine this minion's type
        var thisType = minionType
        if useVariation:
          # Vary between circle, triangle, and cube based on index
          thisType = case i mod 3
            of 0: etCircle
            of 1: etTriangle
            else: etCube
        
        # Create minion with determined type
        let minion = newEnemy(
          spawnX, spawnY, 
          game.difficulty * 0.6,  # Minions are weaker than regular enemies
          thisType,
          game
        )
        # Mark as boss-spawned so it doesn't drop coins (prevent farming)
        minion.spawnedByBoss = true
        
        # NERF: Make boss-summoned minions smaller and slower
        minion.radius = minion.radius * 0.65  # 35% smaller
        minion.collisionRadius = minion.collisionRadius * 0.65  # Keep collision consistent
        minion.speed = minion.speed * 0.70  # 30% slower
        
        game.enemies.add(minion)
      
      # Visual feedback for summoning
      spawnExplosion(game.particles, enemy.pos.x, enemy.pos.y, phase.color, 15)
  
  of bapMeteor:
    # Falling projectiles from above - customizable via specialData
    # "warn_impact" = show visual warnings before meteors hit
    # "massive_impact" = larger impact radius
    # "apocalypse_mode" = massive meteors with longer warnings
    
    let showWarning = attack.specialData.contains("warn")
    let impactRadius = case attack.specialData
      of "massive_impact": attack.durationOrRadius * 1.5
      of "apocalypse_mode": attack.durationOrRadius * 2.0
      else: attack.durationOrRadius
    
    for i in 0..<attack.projectileCount:
      # Randomly place meteors around player
      let offsetX = (rand(1.0) - 0.5) * impactRadius * 2.0
      let targetX = game.player.pos.x + offsetX
      
      # Show warning circle if specified
      if showWarning:
        game.attackWarnings.add(newAttackWarning(targetX, game.screenHeight.float32 + 50.0, "meteor", 0.5))
      
      # Spawn meteor from above
      let startY = -50.0
      
      # Spawn the actual meteor bullet from top of screen
      game.bullets.add(newBullet(
        x = targetX, y = startY, direction = newVector2f(0, 1),
        speed = attack.projectileSpeed, damage = attack.damage * phase.damageMultiplier,
        fromPlayer = false, isBossBullet = true, sourceEnemyId = enemy.id
      ))
  
  of bapOrbit:
    # Orbiting projectiles around boss - customized via specialData
    # "satellite_orbit" = standard single orbit
    # "dual_layer_orbit" = two layers rotating at different speeds
    # "orbital_storm" = multiple dense layers
    
    let orbitMode = attack.specialData
    let layerCount = case orbitMode
      of "dual_layer_orbit": 2
      of "orbital_storm": 3
      else: 1
    
    for layer in 0..<layerCount:
      let layerOffset = layer.float32 * PI * 2.0 / layerCount.float32
      let layerSpeedMultiplier = 1.0 + (layer.float32 * 0.5)  # Layers rotate at different speeds
      let bulletsPerLayer = if orbitMode == "orbital_storm": attack.projectileCount * 2 else: attack.projectileCount
      
      for i in 0..<bulletsPerLayer:
        let angle = i.float32 * attack.spreadAngle.degToRad() + (game.time * 2.0 * layerSpeedMultiplier) + layerOffset
        let orbitRadius = attack.durationOrRadius * (0.8 + layer.float32 * 0.3)  # Different radius per layer
        let orbitX = enemy.pos.x + cos(angle) * orbitRadius
        let orbitY = enemy.pos.y + sin(angle) * orbitRadius
        
        # Create bullet at orbit position moving tangentially
        let tangentAngle = angle + PI / 2.0
        let dir = newVector2f(cos(tangentAngle), sin(tangentAngle))
        
        game.bullets.add(newBullet(
          x = orbitX, y = orbitY, direction = dir,
          speed = attack.projectileSpeed, damage = attack.damage * phase.damageMultiplier,
          fromPlayer = false, isBossBullet = true, sourceEnemyId = enemy.id
        ))
  
  of bapChain:
    # Chain lightning effect - customized via specialData
    # "chain_4_targets" = 4 target chain
    # "chain_lightning_storm" = dense multi-chain
    # "massive_chain" = extra-dense chains
    
    let chainMode = attack.specialData
    let effectiveChainCount = case chainMode
      of "chain_lightning_storm": attack.projectileCount + 2
      of "massive_chain": attack.projectileCount + 4
      else: attack.projectileCount
    
    let bulletMultiplier = case chainMode
      of "massive_chain": 4
      of "chain_lightning_storm": 3
      else: 3
    
    for i in 0..<effectiveChainCount:
      let angle = i.float32 * PI * 2.0 / effectiveChainCount.float32 + rand(0.5)
      let dir = newVector2f(cos(angle), sin(angle))
      
      # Create multiple bullets in chain sequence
      for j in 0..<bulletMultiplier:
        let distance = j.float32 * 60.0
        game.bullets.add(newBullet(
          x = enemy.pos.x + dir.x * distance, 
          y = enemy.pos.y + dir.y * distance,
          direction = dir,
          speed = attack.projectileSpeed,
          damage = attack.damage * phase.damageMultiplier * 0.6,  # Chain hits are weaker
          fromPlayer = false, isBossBullet = true, sourceEnemyId = enemy.id
        ))
    
    # Visual effect
    spawnExplosion(game.particles, enemy.pos.x, enemy.pos.y, Yellow, 20)
  
  of bapTeleport:
    # Teleport to new location and shoot - customized via specialData
    # "afterimage_burst" = creates multiple images with burst effect
    # "triple_clone" = teleports to 3 locations simultaneously
    # "dimensional_rift" = creates rift visual effect
    
    let teleportMode = attack.specialData
    let teleportCount = case teleportMode
      of "triple_clone": 3
      else: 1
    
    # Create visual effect for each teleport
    spawnExplosion(game.particles, enemy.pos.x, enemy.pos.y, phase.color, 15)
    
    # Perform teleports
    var teleportPositions: seq[Vector2f] = @[]
    for t in 0..<teleportCount:
      let newX = game.screenWidth.float32 * (0.2 + rand(0.6))
      let newY = game.screenHeight.float32 * (0.2 + rand(0.6))
      teleportPositions.add(newVector2f(newX, newY))
      
      # Teleport boss to first position (update actual position)
      if t == 0:
        enemy.pos = newVector2f(newX, newY)
      
      # Visual effect at new position
      spawnExplosion(game.particles, newX, newY, phase.color, 15)
      
      # Shoot burst after each teleport
      if attack.projectileCount > 0:
        for i in 0..<attack.projectileCount:
          let angle = i.float32 * PI * 2.0 / attack.projectileCount.float32
          let dir = newVector2f(cos(angle), sin(angle))
          
          # For triple clone, shoot from alternate positions too
          let shootPos = if teleportMode == "triple_clone" and t > 0:
            teleportPositions[t]
          else:
            enemy.pos
          
          game.bullets.add(newBullet(
            x = shootPos.x, y = shootPos.y, direction = dir,
            speed = 200.0, damage = attack.damage * phase.damageMultiplier,
            fromPlayer = false, isBossBullet = true, sourceEnemyId = enemy.id
          ))
  
  of bapDash:
    # Dash toward player at high speed
    let dashDir = toPlayer
    let dashSpeed = attack.projectileSpeed
    
    # Store dash velocity (this would need enemy velocity tracking)
    # For now, create a fast-moving "charge" effect with bullets
    for i in 0..4:
      game.bullets.add(newBullet(
        x = enemy.pos.x + dashDir.x * i.float32 * 40.0,
        y = enemy.pos.y + dashDir.y * i.float32 * 40.0,
        direction = dashDir,
        speed = dashSpeed,
        damage = attack.damage * phase.damageMultiplier,
        fromPlayer = false, isBossBullet = true, sourceEnemyId = enemy.id
      ))
    
    # Move boss forward
    enemy.pos = enemy.pos + dashDir * 80.0
    spawnExplosion(game.particles, enemy.pos.x, enemy.pos.y, phase.color, 10)
  
  of bapSnipe:
    # Precise aimed shots
    for i in 0..<attack.projectileCount:
      let spread = if attack.projectileCount > 1:
        (i.float32 - attack.projectileCount.float32 / 2.0) * attack.spreadAngle.degToRad() / attack.projectileCount.float32
      else: 0.0
      let angle = arctan2(toPlayer.y, toPlayer.x) + spread
      let dir = newVector2f(cos(angle), sin(angle))
      
      # Fire precise shot
      game.bullets.add(newBullet(
        x = enemy.pos.x, y = enemy.pos.y, direction = dir,
        speed = attack.projectileSpeed, damage = attack.damage * phase.damageMultiplier,
        fromPlayer = false, isBossBullet = true, sourceEnemyId = enemy.id
      ))

# ============================================================================
# ORBITAL WEAPONS SYSTEM - REFACTORED
# ============================================================================

proc applyOrbDamage(game: var Game, orb: RotatingOrb, enemy: Enemy, 
                    baseDamage: float32, orbPos: Vector2f, currentTime: float32,
                    enemyIdx: int): bool =
  ## Apply damage from orb to enemy and handle hit cooldown
  ## Returns true if damage was applied
  
  # Check if we can hit this enemy (cooldown check)
  if orb.lastHitTime.hasKey(enemyIdx):
    if currentTime - orb.lastHitTime[enemyIdx] < 0.5:  # 0.5s cooldown per enemy
      return false
  
  # Calculate actual damage
  var actualBaseDamage = baseDamage
  
  # Apply Arcane Mastery bonus for Arcane orbs
  if orb.elementType == etArcane and game.player.hasArcaneMastery:
    actualBaseDamage *= 3.0  # +200% damage
  
  let damageWithCrit = applyCriticalHit(game.player, actualBaseDamage)
  let actualDamage = damageEnemy(enemy, damageWithCrit)
  
  # Track statistics for the orb type
  if hasPowerUp(game.player, puRotatingOrbs):
    trackPowerUpDamage(game, puRotatingOrbs, actualDamage)
  else:
    # Track individual orb type
    case orb.elementType
    of etPoison: trackPowerUpDamage(game, puPoisonOrb, actualDamage)
    of etFire: trackPowerUpDamage(game, puFireOrb, actualDamage)
    of etLightning: trackPowerUpDamage(game, puLightningOrb, actualDamage)
    of etWind: trackPowerUpDamage(game, puWindOrb, actualDamage)
    of etFrost: trackPowerUpDamage(game, puFrostOrb, actualDamage)
    of etArcane: trackPowerUpDamage(game, puArcaneOrb, actualDamage)
    of etBlood: trackPowerUpDamage(game, puBloodOrb, actualDamage)
    of etNone: discard
  
  # Create damage number
  game.showDamage(enemy.pos, actualDamage, fromPlayer = true,
                  isCritical = damageWithCrit > actualBaseDamage, damageType = dtDefault)
  
  # Record hit time
  orb.lastHitTime[enemyIdx] = currentTime
  
  return true

proc applyOrbEffects(game: var Game, orb: RotatingOrb, enemy: Enemy, 
                     baseDamage: float32, orbPos: Vector2f, dt: float32) =
  ## Apply element-specific effects from orb to enemy
  
  case orb.elementType
  of etPoison:
    # Poison: DoT effect
    let poisonDamageScaling = game.player.damage * 0.1
    var poisonDmg = 0.3 + poisonDamageScaling
    var poisonDur = 4.0
    
    if game.player.hasPoisonMastery:
      poisonDmg *= 2.5  # +150% damage
      poisonDur *= 2.0  # +100% duration
    
    applyEffect(enemy, etPoison, poisonDmg, poisonDur, "orb")
    
    # Apply slow only with Poison Mastery
    if game.player.hasPoisonMastery:
      enemy.slowTimer = 0.2
      if enemy.slowAmount < 0.30:
        enemy.slowAmount = 0.30  # 30% slow
    
    # Green particles
    spawnExplosion(game.particles, orbPos.x, orbPos.y, 
                   Color(r: 100, g: 255, b: 100, a: 255), 5)
  
  of etFire:
    # Fire: DoT effect
    let fireDamageScaling = game.player.damage * 0.1
    var fireDmg = 0.4 + fireDamageScaling
    var fireDur = 2.0
    
    if game.player.hasFireMastery:
      fireDmg *= 2.5  # +150% damage
      fireDur *= 2.0  # +100% duration
    
    applyEffect(enemy, etFire, fireDmg, fireDur, "orb")
    
    # Apply slow only with Fire Mastery
    if game.player.hasFireMastery:
      enemy.slowTimer = 0.2
      if enemy.slowAmount < 0.35:
        enemy.slowAmount = 0.35  # 35% slow
    
    # Orange/red particles
    spawnExplosion(game.particles, orbPos.x, orbPos.y, Orange, 5)
    spawnExplosion(game.particles, orbPos.x, orbPos.y, Red, 3)
  
  of etLightning:
    # Lightning: Chain to nearby enemies
    let chainRange = 80.0
    
    var nearestDist = chainRange + 1.0
    var nearestEnemy: Enemy = nil
    var nearestIdx = -1
    
    # Find nearest enemy to chain to
    var checkIdx = 0
    for other in game.enemies:
      if other != enemy:
        let chainDist = distance(enemy.pos, other.pos)
        if chainDist < chainRange and chainDist < nearestDist:
          nearestDist = chainDist
          nearestEnemy = other
          nearestIdx = checkIdx
      checkIdx += 1
    
    # Apply chain damage
    if nearestEnemy != nil:
      let chainDamageWithCrit = applyCriticalHit(game.player, baseDamage * 0.7)
      let chainDamage = damageEnemy(nearestEnemy, chainDamageWithCrit)
      
      game.showDamage(nearestEnemy.pos, chainDamage, fromPlayer = true,
                      isCritical = chainDamageWithCrit > baseDamage * 0.7, damageType = dtLightning)
      
      # Apply slow if has Lightning Mastery
      if game.player.hasLightningMastery:
        nearestEnemy.slowTimer = 0.2
        if nearestEnemy.slowAmount < 0.25:
          nearestEnemy.slowAmount = 0.25  # 25% slow
      
      spawnExplosion(game.particles, nearestEnemy.pos.x, nearestEnemy.pos.y,
                     Color(r: 200, g: 220, b: 255, a: 255), 3)
      
      # Second chain with Lightning Mastery
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
          let secondChainDamage = damageEnemy(secondNearestEnemy, secondChainDamageWithCrit)
          
          game.showDamage(secondNearestEnemy.pos, secondChainDamage, fromPlayer = true,
                          isCritical = secondChainDamageWithCrit > baseDamage * 0.7, damageType = dtLightning)
          
          secondNearestEnemy.slowTimer = 0.2
          if secondNearestEnemy.slowAmount < 0.25:
            secondNearestEnemy.slowAmount = 0.25
          
          spawnExplosion(game.particles, secondNearestEnemy.pos.x, secondNearestEnemy.pos.y,
                         Color(r: 200, g: 220, b: 255, a: 255), 3)
    
    # Apply slow to primary target if has Lightning Mastery
    if game.player.hasLightningMastery:
      enemy.slowTimer = 0.2
      if enemy.slowAmount < 0.25:
        enemy.slowAmount = 0.25
    
    # Yellow particles
    spawnExplosion(game.particles, orbPos.x, orbPos.y, Yellow, 5)
  
  of etWind:
    # Wind: Knockback
    let pushDir = (enemy.pos - game.player.pos).normalize()
    var pushForce = 200.0
    let bossResistance = if enemy.isBoss: 0.1 else: 1.0
    
    if game.player.hasWindMastery:
      pushForce *= 2.5  # +150% stronger
    
    enemy.pos.x += pushDir.x * pushForce * dt * bossResistance
    enemy.pos.y += pushDir.y * pushForce * dt * bossResistance
    
    # Apply slow only with Wind Mastery
    if game.player.hasWindMastery:
      enemy.slowTimer = 0.2
      if enemy.slowAmount < 0.40:
        enemy.slowAmount = 0.40  # 40% slow
    
    # Cyan particles
    spawnExplosion(game.particles, orbPos.x, orbPos.y,
                   Color(r: 200, g: 230, b: 255, a: 255), 5)
  
  of etFrost:
    # Frost: Permanent slow
    enemy.slowTimer = 999.0
    var frostSlow = 0.3  # Base 30%
    
    if game.player.hasFrostMastery:
      frostSlow = 0.5  # 50% with mastery
    
    if enemy.slowAmount < frostSlow:
      enemy.slowAmount = frostSlow
    
    # Light blue particles
    spawnExplosion(game.particles, orbPos.x, orbPos.y,
                   Color(r: 150, g: 200, b: 255, a: 255), 5)
  
  of etArcane:
    # Arcane: Pure damage (already applied) + purple sparkles
    spawnExplosion(game.particles, orbPos.x, orbPos.y,
                   Color(r: 200, g: 100, b: 255, a: 255), 5)
  
  of etBlood:
    # Blood: Lifesteal
    var lifestealPercent = 0.05  # Base 5%
    
    if game.player.hasBloodMastery:
      lifestealPercent *= 2.5  # 12.5% with mastery
    
    let healAmount = baseDamage * lifestealPercent
    game.player.hp = min(game.player.hp + healAmount, game.player.maxHp)
    
    if healAmount > 0.01:
      game.showDamage(game.player.pos, healAmount, fromPlayer = true, 
                      isCritical = false, damageType = dtHeal)
      
      # Green healing particles at player
      spawnExplosion(game.particles, game.player.pos.x, game.player.pos.y, 
                     Color(r: 100, g: 255, b: 100, a: 255), 3)
    
    # Red blood particles at hit location
    spawnExplosion(game.particles, orbPos.x, orbPos.y,
                   Color(r: 255, g: 50, b: 50, a: 255), 5)
  
  of etNone:
    discard

proc updateOrbitalWeapons(game: var Game, dt: float32) =
  ## Update all rotating orbs and handle collisions with enemies
  
  # Check if player has any orb power-ups
  if not (hasPowerUp(game.player, puRotatingOrbs) or 
          hasPowerUp(game.player, puPoisonOrb) or 
          hasPowerUp(game.player, puFireOrb) or 
          hasPowerUp(game.player, puLightningOrb) or 
          hasPowerUp(game.player, puWindOrb) or 
          hasPowerUp(game.player, puFrostOrb) or
          hasPowerUp(game.player, puArcaneOrb) or
          hasPowerUp(game.player, puBloodOrb)):
    return
  
  # Calculate base damage
  let damageScaling = game.player.damage * 0.1
  let baseDamage = if hasPowerUp(game.player, puRotatingOrbs):
    0.1 + damageScaling  # Legendary version
  else:
    # For individual orbs, use level-based damage
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
    if hasPowerUp(game.player, puArcaneOrb):
      maxDamage = max(maxDamage, getElementDamage(getPowerUpLevel(game.player, puArcaneOrb)))
    if hasPowerUp(game.player, puBloodOrb):
      maxDamage = max(maxDamage, getElementDamage(getPowerUpLevel(game.player, puBloodOrb)))
    (maxDamage * 0.5) + damageScaling
  
  let orbRadius = 6.0
  let orbDetectionRange = 0.0
  
  # Update each orb
  for orb in game.player.rotatingOrbs:
    # Calculate orb position
    let angle = game.player.orbRotationAngle + orb.angle
    let orbX = game.player.pos.x + cos(angle) * orb.radius
    let orbY = game.player.pos.y + sin(angle) * orb.radius
    let orbPos = newVector2f(orbX, orbY)
    
    # Check collisions with enemies
    var enemyIdx = 0
    for enemy in game.enemies:
      let dist = distance(orbPos, enemy.pos)
      
      # Check if orb is touching enemy
      if dist < orbRadius + enemy.radius + orbDetectionRange:
        # Apply damage
        if applyOrbDamage(game, orb, enemy, baseDamage, orbPos, game.time, enemyIdx):
          # Apply element-specific effects
          applyOrbEffects(game, orb, enemy, baseDamage, orbPos, dt)
      
      enemyIdx += 1
    
    # Clean up old hit times (>2 seconds ago) to prevent memory growth
    var toRemove: seq[int] = @[]
    for idx, hitTime in orb.lastHitTime:
      if game.time - hitTime > 2.0:
        toRemove.add(idx)
    for idx in toRemove:
      orb.lastHitTime.del(idx)

# ============================================================================
# MAIN GAME UPDATE LOOP
# ============================================================================

proc updateGame*(game: var Game, dt: float32) =
  # Time Warp effect - apply slow to delta time for enemies/bullets
  var effectiveDt = dt
  if game.player.timeWarpActive:
    let slowFactor = 0.5  # 50% slow = 50% speed (single level)
    effectiveDt = dt * slowFactor
  
  # Handle boss spawn warning timer (non-blocking)
  if game.bossSpawnTimer > 0:
    game.bossSpawnTimer -= dt
  
  # Always update game time (player time not affected)
  game.time += dt
  
  # Track movement and update run duration for statistics
  trackMovementFrame(game, dt)
  
  game.spawnTimer += dt
  
  # Difficulty increases over time (not in sandbox mode)
  if game.mode != gmSandbox:
    game.difficulty = game.time / 10.0  # Difficulty increases every 10 seconds
  
  # Update attack warnings and create lasers from boss warnings when they expire
  var i = 0
  while i < game.attackWarnings.len:
    game.attackWarnings[i].lifetime -= dt
    
    # Update warning position to follow the boss that created it
    if game.attackWarnings[i].sourceEnemyId >= 0:
      # Find the boss enemy
      for enemy in game.enemies:
        if enemy.id == game.attackWarnings[i].sourceEnemyId:
          # Update warning position to boss's current position
          game.attackWarnings[i].pos = enemy.pos
          break
    
    # BOSS LASER SYSTEM: Create lasers when warning expires (at 0.1s remaining for smooth transition)
    if game.attackWarnings[i].attackType == "boss_laser" and 
       not game.attackWarnings[i].lasersCreated and
       game.attackWarnings[i].lifetime <= 0.1:
      
      # Find the boss to get current position for laser spawn
      var laserSpawnPos = game.attackWarnings[i].pos
      if game.attackWarnings[i].sourceEnemyId >= 0:
        for enemy in game.enemies:
          if enemy.id == game.attackWarnings[i].sourceEnemyId:
            laserSpawnPos = enemy.pos
            break
      
      # Determine laser direction type based on pattern
      # direction = 2: Cross pattern (two perpendicular beams) - for cross_laser, rotating_grid
      # direction = 3: Single rotated beam - for prismatic_cage, laser_snipe, and other radial patterns
      let laserDirection = if game.attackWarnings[i].laserPattern in ["cross_laser", "rotating_grid"]:
        2  # Cross pattern
      else:
        3  # Single rotated beam (for prismatic_cage, laser_snipe, and other radial patterns)
      
      # Reduce laser duration - all lasers last shorter now (0.5x duration)
      let reducedDuration = game.attackWarnings[i].laserDuration * 0.5
      
      # Create all the lasers for this warning at boss's current position
      for angle in game.attackWarnings[i].laserAngles:
        game.lasers.add(newLaser(
          laserSpawnPos.x,
          laserSpawnPos.y,
          direction = laserDirection,
          length = game.attackWarnings[i].laserLength,
          thickness = 15.0,
          damage = game.attackWarnings[i].laserDamage,
          duration = reducedDuration,  # Reduced duration
          rotation = angle,
          enemyType = game.attackWarnings[i].enemyType
        ))
      
      # Mark lasers as created
      game.attackWarnings[i].lasersCreated = true
    
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
      
      # Transform player position into laser's local space (accounting for rotation)
      let dx = game.player.pos.x - laser.pos.x
      let dy = game.player.pos.y - laser.pos.y
      
      # Rotate point by -rotation to get local coordinates
      let cosR = cos(-laser.rotation)
      let sinR = sin(-laser.rotation)
      let localX = dx * cosR - dy * sinR
      let localY = dx * sinR + dy * cosR
      
      var hit = false
      case laser.direction
      of 0:  # Horizontal laser (extends along X axis in local space)
        if abs(localY) < laser.thickness and abs(localX) < laser.length:
          hit = true
      of 1:  # Vertical laser (extends along Y axis in local space)
        if abs(localX) < laser.thickness and abs(localY) < laser.length:
          hit = true
      of 2:  # Cross (both horizontal and vertical in local space)
        if (abs(localY) < laser.thickness and abs(localX) < laser.length) or
           (abs(localX) < laser.thickness and abs(localY) < laser.length):
          hit = true
      of 3:  # Single radial beam (extends outward along rotation angle)
        # Check if player is in the beam: within thickness and from center to length
        if abs(localY) < laser.thickness and localX >= 0 and localX < laser.length:
          hit = true
      else:
        discard
      
      if hit:
        if takeDamage(game.player, laser.damage.float32):
          game.state = gsGameOver
        
        # Track damage taken for statistics
        trackPlayerDamage(game, laser.damage.float32, laser.enemyType)
        
        # Create damage number for laser damage
        game.showDamage(game.player.pos, laser.damage.float32, fromPlayer = false,
                        isCritical = false, damageType = dtLaser)
        
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
      
      # Track poison damage for statistics
      trackPlayerDamage(game, wholeDamage, etCircle)
      
      # Create damage number for poison damage
      game.showDamage(game.player.pos, wholeDamage, fromPlayer = false,
                      isCritical = false, damageType = dtPoison)
      
      # Additional safety check: ensure game ends if HP reaches 0
      if game.player.hp <= 0:
        game.state = gsGameOver
    
    # Poison visual effect (frame-independent)
    # Spawn ~20 particles/sec
    spawnTimedParticles(game.particles, game.player.pos.x, game.player.pos.y, 20.0, Green, 2, dt)
  
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
        let actualDamage = damageEnemy(enemy, damageWithCrit)
        
        # Track damage zone damage for statistics
        trackPowerUpDamage(game, puDamageZone, actualDamage)
        
        # Use new accumulation system for reliable damage numbers
        accumulateAndShowAuraDamage(game, enemy, actualDamage, dtDefault, 
                                     damageWithCrit > zoneDamage * dt)
  
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
    let damageScaling = game.player.damage * 0.2
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
        spawnTimedParticlesAround(game.particles, enemy.pos.x, enemy.pos.y, 
                                 enemy.radius + 5.0, 4.8, Red, 2, dt, -3.0)
  
  # Lightning Aura power-up effect - low damage with chain lightning
  if hasPowerUp(game.player, puLightningAura):
    let level = getPowerUpLevel(game.player, puLightningAura)
    let damageScaling = game.player.damage * 0.2
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
        let actualDamage = damageEnemy(enemy, damageWithCrit)
        processedEnemies.add(enemy)
        
        # Track lightning aura damage for statistics
        trackPowerUpDamage(game, puLightningAura, actualDamage)
        
        # Use new accumulation system for reliable damage numbers
        accumulateAndShowAuraDamage(game, enemy, actualDamage, dtLightning,
                                     damageWithCrit > lightningDamagePerSec * dt)
        
        # Apply slow ONLY if player has Lightning Mastery
        if game.player.hasLightningMastery:
          enemy.slowTimer = 0.2
          if enemy.slowAmount < 0.25:
            enemy.slowAmount = 0.25  # 25% slow
        
        # Visual lightning spark (frame-independent)
        # 10% @ 60fps = 6 particles/sec
        spawnTimedParticles(game.particles, enemy.pos.x, enemy.pos.y, 6.0,
                           Color(r: 150, g: 200, b: 255, a: 255), 3, dt)
        
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
            let chainedDamage = damageEnemy(nearestEnemy, chainDamageWithCrit)
            processedEnemies.add(nearestEnemy)
            
            # Track chained lightning damage for statistics
            trackPowerUpDamage(game, puLightningAura, chainedDamage)
            
            # Use accumulation system for chained lightning to prevent spam
            accumulateAndShowAuraDamage(game, nearestEnemy, chainedDamage, dtLightning,
                                       chainDamageWithCrit > lightningDamagePerSec * dt)
            
            # Apply 5% slow effect to chained enemy
            nearestEnemy.slowTimer = 0.2
            if nearestEnemy.slowAmount < 0.05:
              nearestEnemy.slowAmount = 0.05
            
            # Visual chain lightning particle (frame-independent)
            # 20% @ 60fps = 12 particles/sec
            let midX = (currentEnemy.pos.x + nearestEnemy.pos.x) / 2.0
            let midY = (currentEnemy.pos.y + nearestEnemy.pos.y) / 2.0
            spawnTimedParticles(game.particles, midX, midY, 12.0,
                               Color(r: 200, g: 220, b: 255, a: 200), 2, dt)
            
            currentEnemy = nearestEnemy
          else:
            break  # No more enemies to chain to
  
  # Arcane Aura power-up effect - pure arcane damage
  if hasPowerUp(game.player, puArcaneAura):
    let level = getPowerUpLevel(game.player, puArcaneAura)
    let damageScaling = game.player.damage * 0.2
    var arcaneDamagePerSec = case level
      of 1: 0.5 + damageScaling
      of 2: 1.0 + damageScaling
      else: 1.5 + damageScaling
    let arcaneRadius = case level
      of 1: 120.0
      of 2: 160.0
      else: 200.0
    
    # Apply Arcane Mastery bonuses if owned
    if game.player.hasArcaneMastery:
      arcaneDamagePerSec *= 3.0  # +200% damage
    
    for enemy in game.enemies:
      let dist = distance(game.player.pos, enemy.pos)
      if dist < arcaneRadius:
        let damageWithCrit = applyCriticalHit(game.player, arcaneDamagePerSec * dt)
        let actualDamage = damageEnemy(enemy, damageWithCrit)
        
        # Track arcane aura damage for statistics
        trackPowerUpDamage(game, puArcaneAura, actualDamage)
        
        # Use new accumulation system for reliable damage numbers
        accumulateAndShowAuraDamage(game, enemy, actualDamage, dtArcane,
                                     damageWithCrit > arcaneDamagePerSec * dt)
        
        # Visual arcane particles (purple sparkles) (frame-independent)
        # 12% @ 60fps = 7.2 particles/sec
        spawnTimedParticlesAround(game.particles, enemy.pos.x, enemy.pos.y, 
                                 enemy.radius + 3.0, 7.2, 
                                 Color(r: 200, g: 100, b: 255, a: 255), 2, dt)
  
  # Poison Aura power-up effect - low damage, longer duration
  if hasPowerUp(game.player, puPoisonAura):
    let level = getPowerUpLevel(game.player, puPoisonAura)
    let damageScaling = game.player.damage * 0.2
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
        spawnTimedParticlesAround(game.particles, enemy.pos.x, enemy.pos.y, 
                                 enemy.radius + 5.0, 3.6, 
                                 Color(r: 100, g: 255, a: 200), 2, dt, -3.0)
  
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
        spawnTimedParticlesAround(game.particles, game.player.pos.x, game.player.pos.y, 
                                 windRadius * 0.8, 4.8, 
                                 Color(r: 200, g: 230, b: 255, a: 150), 2, dt)
  
  # Blood Aura power-up effect - damage with lifesteal
  if hasPowerUp(game.player, puBloodAura):
    let level = getPowerUpLevel(game.player, puBloodAura)
    let damageScaling = game.player.damage * 0.2
    var bloodDamagePerSec = case level
      of 1: 0.5 + damageScaling
      of 2: 1.0 + damageScaling
      else: 1.5 + damageScaling
    let lifestealPercent = case level
      of 1: 0.025  # 2.5% lifesteal
      of 2: 0.05  # 5% lifesteal
      else: 0.075  # 7.5% lifesteal
    let bloodRadius = case level
      of 1: 120.0
      of 2: 160.0
      else: 200.0
    
    # Apply Blood Mastery bonuses if owned
    var actualLifestealPercent = lifestealPercent
    if game.player.hasBloodMastery:
      bloodDamagePerSec *= 2.5  # +150% damage
      actualLifestealPercent *= 2.5  # +150% lifesteal
    
    # Static variable to track last healing number display time
    var lastBloodHealTime {.global.} = 0.0
    const BLOOD_HEAL_DISPLAY_INTERVAL = 0.5  # Show healing number every 0.5 seconds
    
    # Accumulate healing for display (show healing number once per 0.5s)
    var totalHealing = 0.0
    
    for enemy in game.enemies:
      let dist = distance(game.player.pos, enemy.pos)
      if dist < bloodRadius:
        # Apply blood damage with crit chance
        let damageWithCrit = applyCriticalHit(game.player, bloodDamagePerSec * dt)
        let actualDamage = damageEnemy(enemy, damageWithCrit)
        
        # Track blood aura damage for statistics
        trackPowerUpDamage(game, puBloodAura, actualDamage)
        
        # Accumulate healing based on damage dealt
        totalHealing += actualDamage * actualLifestealPercent
        
        # Use new accumulation system for reliable damage numbers (use dtFire for red blood damage)
        accumulateAndShowAuraDamage(game, enemy, actualDamage, dtFire,
                                     damageWithCrit > bloodDamagePerSec * dt)
        
        # Visual blood particles (frame-independent)
        # 8% @ 60fps = 4.8 particles/sec
        spawnTimedParticlesAround(game.particles, enemy.pos.x, enemy.pos.y, 
                                 enemy.radius + 5.0, 4.8, 
                                 Color(r: 255, g: 50, b: 50, a: 255), 2, dt, -3.0)
    
    # Apply accumulated healing to player
    if totalHealing > 0:
      game.player.hp = min(game.player.hp + totalHealing, game.player.maxHp)
      
      # Show healing number periodically using tracked time
      if game.time - lastBloodHealTime >= BLOOD_HEAL_DISPLAY_INTERVAL:
        game.showDamage(game.player.pos, totalHealing / dt, fromPlayer = true,
                        isCritical = false, damageType = dtHeal)
        lastBloodHealTime = game.time
  
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
        let particleColor = if isRanged: Color(r: 138, g: 43, b: 226, a: 220) else: Color(r: 75, g: 0, b: 130, a: 200)
        spawnTimedParticlesAround(game.particles, game.player.pos.x, game.player.pos.y,
                                 pullRadius, particleRate, particleColor, 2, dt)
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
  updateOrbitalWeapons(game, dt)
  

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
    
    # LEGENDARY Auto-Shoot: Full fire rate at level 1
    let autoFireMult = case autoLevel
      of 1: 1.0   # 100% of normal fire rate
      of 2: 1.0
      else: 1.0
    
    let autoRange = case autoLevel
      of 1: 450.0
      of 2: 450.0
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
  if game.mode != gmSandbox:
    if game.mode == gmWaveBased:
    # WAVE-BASED MODE: Spawn enemies in defined waves
    # Don't start a new wave if we're waiting for boss coin collection
      if not game.waveInProgress and game.bossWaveManager.canStartNewWave() and game.state == gsPlaying:
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
        
        # Track wave completion for statistics
        let waveTime = game.time - game.waveStartTime
        trackWaveCompletion(game, game.currentWave, waveTime)
        
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
        if not game.bossWaveManager.isBossCoinActive():
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
    if game.wavesUntilBoss == 0 and game.bossWaveManager.canSpawnBoss() and game.state == gsPlaying:
      game.bossCount += 1
      # Scale boss difficulty based on wave number (every 3 waves = +1 difficulty)
      let bossDifficulty = (game.currentWave - 1).float32 / 3.0
      # FIX: Use a boss wave that maps to the boss block (ceil to next multiple of 5)
      # This allows debug spawns when wavesUntilBoss is forced to 0 (boss appears
      # for the current boss block: waves 1-5 => boss 1, 6-10 => boss 2, etc.)
      let bossBlockWave = ((game.currentWave - 1) div 5 + 1) * 5
      game.enemies.add(spawnBoss(game.screenWidth, game.screenHeight,
                bossDifficulty, game.bossCount, bossBlockWave))
      game.bossWaveManager.startBossWave()  # Mark boss wave as active
      game.bossSpawnTimer = 1.5  # Short warning, doesn't pause gameplay
      # Don't reset wavesUntilBoss here - it will be reset when boss coin is collected
      
      # Play boss spawn sound
      playSound(stBossSpawn)
      
      # Entrance particles
      let boss = game.enemies[^1]
      # Spawn entrance particles for custom boss
      for i in 0..<60:
        let angle = i.float32 * 0.1
        let dist = i.float32 * 3
        let x = boss.pos.x + cos(angle) * dist
        let y = boss.pos.y + sin(angle) * dist
        spawnExplosion(game.particles, x, y, boss.color, 3)
    
    elif game.mode == gmTimeSurvival:
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
      if game.bossWaveManager.isBossActive():
        currentSpawnRate = currentSpawnRate * 2.0
      
      if game.spawnTimer > currentSpawnRate:
        let enemy = spawnEnemy(game.screenWidth, game.screenHeight, game.difficulty, game)
        makeElite(enemy, (game.difficulty * 3).int)  # Use difficulty as wave equivalent
        game.enemies.add(enemy)
        game.spawnTimer = 0
        
        if isWaveActive and rand(100) < 60 and not game.bossWaveManager.isBossActive():
          let waveEnemy = spawnEnemy(game.screenWidth, game.screenHeight, game.difficulty, game)
          makeElite(waveEnemy, (game.difficulty * 3).int)
          game.enemies.add(waveEnemy)
        
        let boss = game.enemies[^1]
        # Spawn entrance particles for custom boss
        for i in 0..<60:
          let angle = i.float32 * 0.1
          let dist = i.float32 * 3
          let x = boss.pos.x + cos(angle) * dist
          let y = boss.pos.y + sin(angle) * dist
          spawnExplosion(game.particles, x, y, boss.color, 3)
  # End of enemy spawning logic (excluded for sandbox mode)
  
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
      let actualDamage = damageEnemy(enemy, effectDamage)
      
      # Track DoT damage for power-up statistics based on active effect sources
      if hasActiveEffect(enemy, etPoison):
        # Check source to determine which power-up to attribute
        let poisonEffect = enemy.activeEffects[etPoison]
        if poisonEffect.primary.source == "aura":
          trackPowerUpDamage(game, puPoisonAura, actualDamage)
        elif poisonEffect.primary.source == "shot" or poisonEffect.primary.source == "bullet":
          trackPowerUpDamage(game, puPoisonShot, actualDamage)
        elif poisonEffect.primary.source == "orb":
          trackPowerUpDamage(game, puPoisonOrb, actualDamage)
      elif hasActiveEffect(enemy, etFire):
        # Check source to determine which power-up to attribute
        let fireEffect = enemy.activeEffects[etFire]
        if fireEffect.primary.source == "aura":
          trackPowerUpDamage(game, puFireAura, actualDamage)
        elif fireEffect.primary.source == "shot" or fireEffect.primary.source == "bullet":
          trackPowerUpDamage(game, puFireBullets, actualDamage)
        elif fireEffect.primary.source == "orb":
          trackPowerUpDamage(game, puFireOrb, actualDamage)
      
      # Create damage number for DOT effects (periodically to avoid spam)
      if rand(1.0) < (2.0 * dt):  # Show ~2.0 numbers per second
        # Determine damage type based on active effects
        var dotDamageType = dtDefault
        if hasActiveEffect(enemy, etPoison):
          dotDamageType = dtPoison
        elif hasActiveEffect(enemy, etFire):
          dotDamageType = dtFire
        elif hasActiveEffect(enemy, etLightning):
          dotDamageType = dtLightning  # Use lightning color for lightning
        
        game.showDamage(enemy.pos, actualDamage / effectiveDt, fromPlayer = true,
                        isCritical = false, damageType = dotDamageType)
    
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
      
      # Boss-spawned minions don't drop coins (prevent farming)
      if not enemy.spawnedByBoss:
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
            of etMage: 4           # Mage enemy coin value
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
          
          # Track explosion damage for statistics
          trackPlayerDamage(game, eliteExplosionDamage, enemy.enemyType)
          
          # Create damage number for explosion damage
          game.showDamage(game.player.pos, eliteExplosionDamage, fromPlayer = false,
                          isCritical = false, damageType = dtExplosion)
        
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
          
          # Track boss explosion damage for statistics
          trackPlayerDamage(game, explosionDamage, enemy.enemyType)
          
          # Create damage number for boss explosion damage
          game.showDamage(game.player.pos, explosionDamage, fromPlayer = false,
                          isCritical = false, damageType = dtExplosion)
        
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
      
      # Track enemy kill for statistics
      trackEnemyKilled(game, enemy)
      
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
        
        # Mark that a boss coin is now active and must be collected
        game.bossWaveManager.bossDefeated()
        
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
    
    # BOSS SPECIAL ATTACKS
    if enemy.isBoss:
      # CUSTOM BOSS ATTACKS - Full pattern system from boss_definitions.nim
      # Get boss definition and check for phase transitions
      let bossDef = getBossDefinition(enemy.bossDefinitionID)
      let hpPercent = enemy.hp / enemy.maxHp
      
      # Check if we need to transition to a new phase
      for i, phase in bossDef.phases:
        if hpPercent <= phase.hpThreshold and i > enemy.currentPhaseIndex:
          enemy.currentPhaseIndex = i
          # Reinitialize attack timers for new phase
          enemy.attackTimers = @[]
          for attack in phase.attacks:
            enemy.attackTimers.add(0.0)  # Reset timers to 0 so new phase attacks immediately
          # Update boss color and apply phase modifiers
          enemy.color = phase.color
          enemy.speed = bossDef.baseSpeed * phase.speedMultiplier
          enemy.defenseMultiplier = phase.defenseMultiplier  # Apply defense multiplier from phase
          break
        
      # Update boss behavior based on specialBehavior
      if enemy.currentPhaseIndex < bossDef.phases.len:
        let phase = bossDef.phases[enemy.currentPhaseIndex]
        updateCustomBossBehavior(game, enemy, phase, dt)
      
      # Update attack timers
      for i in 0..<enemy.attackTimers.len:
        enemy.attackTimers[i] -= dt
      
      # Execute attacks when timers expire
      if enemy.currentPhaseIndex < bossDef.phases.len:
        let phase = bossDef.phases[enemy.currentPhaseIndex]
        for i, attack in phase.attacks:
          if i < enemy.attackTimers.len and enemy.attackTimers[i] <= 0:
            # Execute this attack based on its pattern
            executeCustomBossAttack(game, enemy, attack, phase, bossDef)
            # Reset timer
            enemy.attackTimers[i] = attack.cooldown

    # Hexagon enemies shoot chaotically (applies to all hexagon enemies, not just bosses)
    if enemy.enemyType == etHexagon and enemy.shootTimer > 1.0:
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
          damage = enemy.rangedDamage.float32,  # FIX: Convert int to float32
          fromPlayer = false,
          sourceEnemyId = enemy.id
        ))
      enemy.shootTimer = 0
    
    # Cube enemies shoot - BUFFED
    if enemy.enemyType == etCube and enemy.shootTimer > 1.75:  # Faster
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
          speed = 250,
          damage = enemy.rangedDamage.float32,  # FIX: Convert int to float32
          fromPlayer = false,
          sourceEnemyId = enemy.id
        ))
      
      enemy.shootTimer = 0
    
    # Check collision with player (with small coyote/forgiveness zone on edges)
    # Reduce effective collision radius by 10% for slight edge forgiveness
    let effectivePlayerRadius = game.player.radius * 0.90  # 10% reduction = coyote
    if distance(enemy.pos, game.player.pos) < enemy.radius + effectivePlayerRadius:
      if enemy.isBoss:
        # Boss deals continuous damage
        if game.time - enemy.lastContactDamageTime >= 0.5:  # 2 HP per second
          var bossContactDamage = enemy.contactDamage.float32  # FIX: Use contactDamage instead of damage
          
          # Thorns reflection damage
          if hasPowerUp(game.player, puThorns):
            let thornsLevel = getPowerUpLevel(game.player, puThorns)
            let reflectPercent = case thornsLevel
              of 1: 0.5  # BUFFED from 0.20 to 0.35
              of 2: 1.0  # BUFFED from 0.40 to 0.60
              else: 1.5  # BUFFED from 0.70 to 1.00 (full reflection!)
            let reflectDamageBase = bossContactDamage * reflectPercent
            let reflectDamageWithCrit = applyCriticalHit(game.player, reflectDamageBase)
            let actualDamage = damageEnemy(enemy, reflectDamageWithCrit)
            
            # Track thorns damage for statistics
            trackPowerUpDamage(game, puThorns, actualDamage)
            
            # Create damage number for thorns reflection (boss contact)
            game.showDamage(enemy.pos, actualDamage, fromPlayer = true,
                            isCritical = reflectDamageWithCrit > reflectDamageBase, damageType = dtDefault)
            
            spawnExplosion(game.particles, enemy.pos.x, enemy.pos.y, Red, 8)
          
          if takeDamage(game.player, bossContactDamage):
            game.state = gsGameOver
          
          # Track boss contact damage for statistics
          trackPlayerDamage(game, bossContactDamage, enemy.enemyType)
          
          # Create damage number for boss contact damage
          game.showDamage(game.player.pos, bossContactDamage, fromPlayer = false,
                          isCritical = false, damageType = dtDefault)
          
          playSound(stPlayerHit, 0.6)
          enemy.lastContactDamageTime = game.time
          spawnExplosion(game.particles, game.player.pos.x, game.player.pos.y, Red, 10)
      else:
        # Regular enemies die on contact
        var enemyContactDamage = enemy.contactDamage.float32  # FIX: Use contactDamage instead of damage
        
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
          let actualDamage = damageEnemy(enemy, reflectedDamageWithCrit)
          
          # Track thorns damage for statistics
          trackPowerUpDamage(game, puThorns, actualDamage)
          
          # Create damage number for thorns reflection (enemy contact)
          game.showDamage(enemy.pos, actualDamage, fromPlayer = true,
                          isCritical = reflectedDamageWithCrit > reflectedDamageBase, damageType = dtDefault)
          
          spawnExplosion(game.particles, enemy.pos.x, enemy.pos.y, Red, 6)
        
        if takeDamage(game.player, enemyContactDamage):
          game.state = gsGameOver
        
        # Track enemy contact damage for statistics
        trackPlayerDamage(game, enemyContactDamage, enemy.enemyType)
        
        # Create damage number for enemy contact damage
        showDamage(game, game.player.pos, enemyContactDamage, false, false, dtDefault)
        
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
    
    # Homing bullet logic (LEGENDARY - Single Level) - NERFED
    if bullet.isHoming and bullet.fromPlayer and game.enemies.len > 0:
      # HEAVY NERF: Much shorter tracking range and weaker turn rate
      let trackingRange = 120.0  # NERFED from 160.0 - very short range now
      
      # Find nearest enemy that HASN'T been hit by this bullet yet
      var nearestEnemy: Enemy = nil
      var nearestDist = 999999.0
      
      for enemyIdx in 0..<game.enemies.len:
        let enemy = game.enemies[enemyIdx]
        let dist = distance(bullet.pos, enemy.pos)
        
        # Only track if within range AND not already hit by this bullet (using enemy ID)
        if dist < trackingRange and dist < nearestDist and enemy.id notin bullet.hitEnemies:
          nearestDist = dist
          nearestEnemy = enemy
      
      if nearestEnemy != nil:
        # HEAVY NERF: Much weaker tracking - bullets barely curve
        let turnRate = 0.02  # NERFED from 0.05 - very weak tracking now
        
        let toEnemy = (nearestEnemy.pos - bullet.pos).normalize()
        let currentDir = bullet.vel.normalize()
        let newDir = (currentDir * (1.0 - turnRate) + toEnemy * turnRate).normalize()
        bullet.vel = newDir * bullet.vel.length()

    # Use effectiveDt for enemy bullets (slowed by Time Warp), normal dt for player bullets
    let bulletDt = if bullet.fromPlayer: dt else: effectiveDt
    if not updateBullet(bullet, bulletDt) or isOffScreen(bullet, game.screenWidth, game.screenHeight):
      # Track bullet despawn (missed shot) for player bullets only
      if bullet.fromPlayer:
        trackBulletDespawn(game, bullet, false)
      game.bullets.delete(i)
      continue
    
    # Update sourceEnemyPos to track the enemy's current position
    # This ensures parried bullets go to where the enemy last was, not where it shot from
    if not bullet.fromPlayer and bullet.sourceEnemyId >= 0:
      for enemy in game.enemies:
        if enemy.id == bullet.sourceEnemyId:
          bullet.sourceEnemyPos = enemy.pos
          break
    
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
      let shieldCount = 3  # Always 3 shields regardless of level
      let shieldRadius = game.player.radius * 2.5 + 15  # Reduced from +15 to +10
      var hitShield = false
      var hitShieldIndex = -1

      # Level-based coverage: NERFED - much smaller coverage
      let arcCoverage = case level
        of 1: 0.30  # 30% coverage
        of 2: 0.35  # 35% coverage
        else: 0.40  # 40% coverage

      # Check collision with shield arcs (with gaps)
      for j in 0..<shieldCount:
        # Skip destroyed shields
        if j < game.player.shieldHealths.len and game.player.shieldHealths[j] <= 0:
          continue
          
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
            hitShieldIndex = j
            playSound(stShield, 0.4)
            spawnExplosion(game.particles, shieldX, shieldY, Color(r: 0, g: 255, b: 255, a: 255), 8)  # Cyan explosion
            break
        
        if hitShield:
          break
      
      if hitShield and hitShieldIndex >= 0:
        # Damage the specific shield
        if hitShieldIndex < game.player.shieldHealths.len:
          game.player.shieldHealths[hitShieldIndex] -= 1.0
          # Reset regen timer for this shield
          if hitShieldIndex < game.player.shieldRegenTimers.len:
            game.player.shieldRegenTimers[hitShieldIndex] = 0.0
        game.bullets.delete(i)
        continue
    
    # Check bullet-enemy collision
    var hitEnemy = false
    if bullet.fromPlayer:
      for j in 0..<game.enemies.len:
        # Skip if this bullet already hit this enemy (using enemy ID)
        if game.enemies[j].id in bullet.hitEnemies:
          continue
          
        if checkBulletEnemyCollision(bullet, game.enemies[j]):
          # Mark this enemy as hit by this bullet (using enemy ID, not index)
          bullet.hitEnemies.add(game.enemies[j].id)
          
          # Play enemy hit sound
          playSound(stEnemyHit, 0.3)
          
          # Calculate final damage with Overcharge modifier
          var finalDamage = bullet.damage
          var overchargeExtraDamage = 0.0
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
            overchargeExtraDamage = finalDamage - bullet.damage
          
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
            var shieldDamage = 0.0  # Track damage absorbed by shield
            if game.enemies[j].isElite and etShielded in game.enemies[j].eliteTypes and game.enemies[j].shieldHp > 0:
              if game.enemies[j].shieldHp >= actualDamage:
                # Shield absorbs all damage
                shieldDamage = actualDamage
                game.enemies[j].shieldHp -= actualDamage
                actualDamage = 0
              else:
                # Shield breaks, remaining damage goes to HP
                shieldDamage = game.enemies[j].shieldHp
                actualDamage -= game.enemies[j].shieldHp
                game.enemies[j].shieldHp = 0
            
            game.enemies[j].hp -= actualDamage
            
            # Track bullet hit for statistics
            trackBulletHit(game, bullet, game.enemies[j], actualDamage + shieldDamage)
            
            # Track power-up damage contributions (only ACTUAL extra damage they caused)
            
            # Track Overcharge damage contribution (only extra damage from distance)
            if overchargeExtraDamage > 0:
              trackPowerUpDamage(game, puOvercharge, overchargeExtraDamage)
            
            # Track Rage damage contribution (only extra damage from low HP)
            for powerUp in game.player.powerUps:
              if powerUp.powerType == puRage:
                let hpPercent = game.player.hp / game.player.maxHp
                let hpLost = 1.0 - hpPercent
                let bonusPerTenPercent = case powerUp.level
                  of 1: 0.05
                  of 2: 0.08
                  else: 0.12
                let damageBonus = hpLost * 10.0 * bonusPerTenPercent
                if damageBonus > 0:
                  # Calculate actual rage damage: base damage * bonus percentage
                  let rageDamageRatio = damageBonus / (1.0 + damageBonus)
                  let rageDamage = actualDamage * rageDamageRatio
                  trackPowerUpDamage(game, puRage, rageDamage)
            
            # Track Multi-Shot contribution (only from bonus bullets)
            if bullet.isBonusFromMultiShot:
              trackPowerUpDamage(game, puMultiShot, actualDamage)
            
            # Track Double Shot contribution (only from bonus bullets)
            if bullet.isBonusFromDoubleShot:
              trackPowerUpDamage(game, puDoubleShot, actualDamage)
            
            # Create damage number for shield damage (cyan/blue colored for shields)
            if shieldDamage > 0:
              showDamage(game, game.enemies[j].pos, shieldDamage, true, false, dtLightning)
            
            # Create damage number for HP damage (player damage to enemy) - only if damage was dealt
            if actualDamage > 0:
              let isCrit = finalDamage > bullet.damage  # Critical if final damage exceeds base damage
              showDamage(game, game.enemies[j].pos, actualDamage, true, isCrit)
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
                  let actualDamage = damageEnemy(game.enemies[k], chainDmgWithCrit)
                  
                  # Create damage number for chain lightning damage
                  if actualDamage > 0:
                    showDamage(game, game.enemies[k].pos, actualDamage, true, 
                              chainDmgWithCrit > chainDmgBase, dtLightning)
                  
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
          
          # Blood bullet healing - restore HP based on damage dealt
          if hasPowerUp(game.player, puBloodBullets):
            let vampLevel = getPowerUpLevel(game.player, puBloodBullets)
            var healPercent = case vampLevel
              of 1: 0.015  # 1.5% (reduced from 5%)
              of 2: 0.025  # 2.5% (reduced from 10%)
              else: 0.035  # 3.5% (reduced from 18%)
            
            # Apply Blood Mastery bonus if owned
            if game.player.hasBloodMastery:
              healPercent *= 2.5  # +150% lifesteal
            
            let healAmount = finalDamage * healPercent
            heal(game.player, healAmount)
            if healAmount > 0.01:  # Only show particles if significant healing
              spawnExplosion(game.particles, game.player.pos.x, game.player.pos.y, Green, 3)
              
              # Create heal number for blood bullet lifesteal
              showDamage(game, game.player.pos, healAmount, true, false, dtHeal)
          
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
                let actualDamage = damageEnemy(game.enemies[k], explosionDmg)
                
                # Track explosive bullet damage contribution
                if actualDamage > 0:
                  trackPowerUpDamage(game, puExplosiveBullets, actualDamage)
                
                # Create damage number for explosive bullet area damage
                if actualDamage > 0:
                  showDamage(game, game.enemies[k].pos, actualDamage, true, false, dtExplosion)
            
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
              # Ricochet toward the NEAREST enemy that hasn't been hit yet
              var ricochetTarget: Enemy = nil
              var targetIndex = -1
              var nearestDist = 999999.0
              
              for k in 0..<game.enemies.len:
                # Skip current enemy and already-hit enemies (using enemy ID)
                if k != j and game.enemies[k].id notin bullet.hitEnemies:
                  let dist = distance(bullet.pos, game.enemies[k].pos)
                  if dist < nearestDist:
                    nearestDist = dist
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
          # FIX: Bounce toward the enemy that shot the bullet
          # If enemy is dead, bounce toward where it was when it shot
          var targetPos: Vector2f
          var foundTarget = false
          
          # Try to find the living enemy that shot this bullet by ID
          if bullet.sourceEnemyId >= 0:
            for enemy in game.enemies:
              if enemy.id == bullet.sourceEnemyId:
                targetPos = enemy.pos
                foundTarget = true
                break
          
          # If source enemy is dead/missing, use the position where bullet was shot from
          if not foundTarget:
            targetPos = bullet.sourceEnemyPos
            foundTarget = true
          
          # Calculate bounce direction toward target position
          let bounceDir = if foundTarget:
            (targetPos - bullet.pos).normalize()
          else:
            # Ultimate fallback: bounce away from player (should never happen)
            (bullet.pos - game.player.pos).normalize()
          
          bullet.vel = bounceDir * bullet.vel.length()
          bullet.fromPlayer = true  # Mark as player bullet so it can damage enemies
          
          # Visual effect for parry bounce
          spawnExplosion(game.particles, bullet.pos.x, bullet.pos.y, 
                        Color(r: 255, g: 255, b: 200, a: 255), 12)
          
          # Bullet continues bouncing, don't delete it
          i += 1
          continue
        
        var bulletDamage = bullet.damage  # FIX: Use the actual bullet damage instead of hardcoded 1.0
        
        # Thorns reflection - damage the originating enemy (the one that shot the bullet)
        if hasPowerUp(game.player, puThorns):
          let thornsLevel = getPowerUpLevel(game.player, puThorns)
          let reflectPercent = case thornsLevel
            of 1: 0.35  # BUFFED from 0.20 to 0.35
            of 2: 0.60  # BUFFED from 0.40 to 0.60
            else: 1.00  # BUFFED from 0.70 to 1.00
          let reflectedDamage = bulletDamage * reflectPercent
          
          # Find the enemy that shot this bullet using sourceEnemyId
          var sourceEnemy: Enemy = nil
          for enemy in game.enemies:
            if enemy.id == bullet.sourceEnemyId:
              sourceEnemy = enemy
              break
          
          if sourceEnemy != nil:
            let actualDamage = damageEnemy(sourceEnemy, reflectedDamage)
            
            # Track thorns damage for statistics
            trackPowerUpDamage(game, puThorns, actualDamage)
            
            # Create damage number for thorns reflection (bullet)
            showDamage(game, sourceEnemy.pos, actualDamage, true, false, dtDefault)
            
            spawnExplosion(game.particles, sourceEnemy.pos.x, sourceEnemy.pos.y, Red, 5)
        
        if takeDamage(game.player, bulletDamage):
          game.state = gsGameOver
        
        # Track bullet damage for statistics (try to get enemy type from sourceEnemyId)
        var sourceEnemyType = etCircle
        if bullet.sourceEnemyId >= 0 and bullet.sourceEnemyId < game.enemies.len:
          sourceEnemyType = game.enemies[bullet.sourceEnemyId].enemyType
        trackPlayerDamage(game, bulletDamage, sourceEnemyType)
        
        # Create damage number (enemy damage to player)
        # Determine bullet damage type based on bullet properties
        var bulletDamageType = dtDefault
        if bullet.isBossBullet:
          bulletDamageType = dtCritical  # Boss bullets use yellow/critical color
        elif bullet.isPentagon:
          bulletDamageType = dtLaser  # Pentagon bullets use purple/laser color
        
        showDamage(game, game.player.pos, bulletDamage, false, false, bulletDamageType)
        
        hitEnemy = true
        spawnExplosion(game.particles, bullet.pos.x, bullet.pos.y, Red, 8)
    
    # Check bullet-wall collision (only enemy bullets)
    if not bullet.fromPlayer:
      for wall in game.walls:
        if checkBulletWallCollision(bullet, wall):
          hitEnemy = true
          wall.takeDamage(bullet.damage)  # Full bullet damage
          trackWallDamaged(game)
          spawnExplosion(game.particles, bullet.pos.x, bullet.pos.y, Brown, 4)
          break
    
    if hitEnemy:
      game.bullets.delete(i)
      continue
    
    i += 1
  
  # Update meteorites (from etMage enemy)
  i = 0
  while i < game.meteorites.len:
    let meteorite = game.meteorites[i]
    
    # Update warning timer
    if meteorite.warningTimer > 0:
      meteorite.warningTimer -= dt
    else:
      # Warning finished - meteorite starts falling
      # Calculate velocity toward target
      let direction = (meteorite.targetPos - meteorite.pos).normalize()
      meteorite.vel = direction * 800.0  # Fast falling speed
      
      # Update position
      meteorite.pos = meteorite.pos + meteorite.vel * dt
      
      # Check if meteorite reached target (or went past it)
      let distToTarget = distance(meteorite.pos, meteorite.targetPos)
      if distToTarget < 20.0 or meteorite.pos.y > meteorite.targetPos.y:
        # Meteorite impact!
        # Check collision with player
        if distance(meteorite.pos, game.player.pos) < meteorite.radius + game.player.radius:
          if takeDamage(game.player, meteorite.damage.float32):
            game.state = gsGameOver
          
          # Track meteorite damage
          trackPlayerDamage(game, meteorite.damage.float32, etMage)
          
          # Create damage number
          showDamage(game, game.player.pos, meteorite.damage.float32, false, false, dtExplosion)
          
          playSound(stPlayerHit, 0.6)
        
        # Create explosion effect
        spawnExplosion(game.particles, meteorite.pos.x, meteorite.pos.y, Orange, 25)
        
        # Remove meteorite after impact
        game.meteorites.delete(i)
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
      spawnTimedParticles(game.particles, game.coins[i].pos.x, game.coins[i].pos.y, 18.0,
                         Color(r: 255, g: 215, b: 0, a: 150), 1, dt)
    
    # Enhanced magnet effect from consumable
    if game.player.magnetTimer > 0:
      moveCoinToPlayer(game.coins[i], game.player.pos, dt)
    
    # Collect coin on contact
    if checkPlayerCollision(game.coins[i], game.player):
      let isBossCoin = game.coins[i].isBossCoin
      # Apply Lucky Coins (Greed) multiplier - doubles coins collected
      let coinValue = if hasPowerUp(game.player, puLuckyCoins):
        game.coins[i].value * 2
      else:
        game.coins[i].value
      game.player.coins += coinValue
      
      # Track coin pickup for statistics
      trackCoinPickup(game, coinValue)
      
      playSound(stCoinPickup, if isBossCoin: 0.8 else: 0.5)
      # Boss coins have red particles, regular coins have gold
      let coinParticleColor = if isBossCoin: Color(r: 255, g: 50, b: 50, a: 255) else: Gold
      spawnExplosion(game.particles, game.coins[i].pos.x, game.coins[i].pos.y, coinParticleColor, if isBossCoin: 20 else: 6)
      
      # If this was a boss coin, end the boss wave and advance
      if isBossCoin and game.bossWaveManager.isBossCoinActive():
        game.bossWaveManager.bossCoinCollected()  # Mark boss coin as collected
        if game.mode == gmWaveBased:
          # Use centralized boss wave completion logic
          game.completeBossWave()
      
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
      
      # Add subtle particle trail for magnet effect (frame-independent)
      spawnTimedParticles(game.particles, game.consumables[i].pos.x, game.consumables[i].pos.y,
                         18.0, Purple, 1, dt)
    
    if checkPlayerCollision(game.consumables[i], game.player):
      playSound(stPowerUp, 0.6)
      
      # Track consumable pickup for statistics
      trackConsumablePickup(game, game.consumables[i].consumableType)
      
      case game.consumables[i].consumableType
      of ctHealth:
        heal(game.player, 1)
        # Create heal damage number (green, floating up)
        showDamage(game, game.player.pos, 1.0, true, false, dtHeal)
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
      let damageBlocked = game.walls[i].maxHp - game.walls[i].hp
      trackWallDestruction(game, damageBlocked)
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
  
  # Update damage numbers
  i = 0
  while i < game.damageNumbers.len:
    if not updateDamageNumber(game.damageNumbers[i], dt):
      game.damageNumbers.delete(i)
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
  let hasBloodBullets = hasPowerUp(game.player, puBloodBullets)
  for bullet in game.bullets:
    drawBullet(bullet, hasOvercharge, hasBloodBullets)
  
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
  
  # ==================== UNIFIED AURA RENDERING ====================
  # Draw all active aura effects using the unified aura system
  const AURA_TYPES = [puFireAura, puLightningAura, puPoisonAura, puWindAura, puArcaneAura, puBloodAura]
  for auraType in AURA_TYPES:
    if hasPowerUp(game.player, auraType):
      let level = getPowerUpLevel(game.player, auraType)
      let config = getAuraConfig(auraType, level)
      drawAuraEffect(game.player.pos, config, game.time)
  # ==================== END UNIFIED AURA RENDERING ====================
  
  # Draw player
  drawPlayer(game.player)
  
  # Draw damage numbers (on top of everything except UI)
  for damageNum in game.damageNumbers:
    drawDamageNumber(damageNum)
  
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
    let waveDisplay = if game.bossWaveManager.isBossActive():
      "Boss Wave " & $(game.currentWave)
    else:
      "Wave " & $(game.currentWave)
    drawText(waveDisplay, 10, 135, 20, if game.bossWaveManager.isBossActive(): Red else: Yellow)
    
    if game.waveInProgress and not game.bossWaveManager.isBossActive():
      let enemiesLeft = game.waveEnemiesRemaining + game.enemies.len
      drawText("Enemies: " & $enemiesLeft & "/" & $game.waveEnemiesTotal, 10, 160, 18, Orange)
    elif game.bossWaveManager.isBossActive():
      drawText("Defeat the Boss!", 10, 160, 18, Red)
    elif game.bossWaveManager.isBossCoinActive():
      # Show message when boss is defeated but coin not yet collected
      let pulseAlpha = (sin(game.time * 4.0) * 60 + 195).int.uint8
      drawText("Collect the Boss Coin!", 10, 160, 18, Color(r: 255, g: 215, b: 0, a: pulseAlpha))
  else:
    # Time survival mode - show chaos meter (not shown in sandbox)
    if game.mode == gmTimeSurvival:
      let chaosLevel = min(game.difficulty * 10, 100).int
      drawText("Chaos: " & $chaosLevel & "%", 10, 135, 18, 
              if chaosLevel < 30: Green elif chaosLevel < 70: Orange else: Red)
  
  # Boss health bar (top of screen)
  if game.bossWaveManager.isBossActive():
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
    if waveProgress > 0.6 and not game.bossWaveManager.isBossActive():
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
    # Show speed stat
    drawText("Speed: " & formatFloat(game.player.speed, ffDecimal, 2), game.screenWidth - 200, yOffset, 16, White)
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
            else: 1.2
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
  
  # Note: Custom cursor is now drawn in main.nim after all UI overlays
  # This ensures the cursor appears above sandbox menu and other overlays

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
  
  # Draw buttons at the bottom
  let buttonY = game.screenHeight div 2 + 200
  let buttonWidth: int32 = 200
  let buttonHeight: int32 = 50
  let buttonSpacing = 220
  
  # Restart button
  let restartX = game.screenWidth div 2 - buttonSpacing
  let restartRect = Rectangle(x: restartX.float32, y: buttonY.float32, 
                               width: buttonWidth.float32, height: buttonHeight.float32)
  
  # Menu button
  let menuX = game.screenWidth div 2 + 20
  let menuRect = Rectangle(x: menuX.float32, y: buttonY.float32,
                           width: buttonWidth.float32, height: buttonHeight.float32)
  
  # Check mouse hover for both buttons
  let mousePos = getMousePosition()
  let hoverRestart = checkCollisionPointRec(mousePos, restartRect)
  let hoverMenu = checkCollisionPointRec(mousePos, menuRect)
  
  # Draw restart button
  let restartBgColor = if hoverRestart: 
    Color(r: 60, g: 60, b: 80, a: 255) 
  else: 
    Color(r: 40, g: 40, b: 60, a: 255)
  let restartBorderColor = if hoverRestart:
    Color(r: 100, g: 200, b: 255, a: 255)
  else:
    Color(r: 80, g: 80, b: 100, a: 255)
  
  drawRectangle(restartX.int32, buttonY, buttonWidth, buttonHeight, restartBgColor)
  drawRectangleLines(restartRect, 2, restartBorderColor)
  drawText("RESTART (R)", (restartX + 30).int32, (buttonY + 15).int32, 20, White)
  
  # Draw menu button
  let menuBgColor = if hoverMenu:
    Color(r: 60, g: 60, b: 80, a: 255)
  else:
    Color(r: 40, g: 40, b: 60, a: 255)
  let menuBorderColor = if hoverMenu:
    Color(r: 100, g: 200, b: 255, a: 255)
  else:
    Color(r: 80, g: 80, b: 100, a: 255)
  
  drawRectangle(menuX.int32, buttonY, buttonWidth, buttonHeight, menuBgColor)
  drawRectangleLines(menuRect, 2, menuBorderColor)
  drawText("MENU (ESC)", (menuX + 35).int32, (buttonY + 15).int32, 20, White)

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
