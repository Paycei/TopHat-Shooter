import raylib, types, player, enemy, bullet, consumable, coin, wall, ui/os_shop, particle, powerup, sound, random, math, settings, tables, effects, boss_definitions, run_statistics, gamemode_definitions, ui/os_background, ui/os_hud, ui/os_debug_panel, ui/os_combined_hud, ui/os_system_screens, ui/os_enemy_labels, localization, enemy_config, particle_skins, d_systems, d_visuals, d_enhancements, ui/ui_constants, game3d/game_3d, survival  # Import 3D game module

# Configurable boss wave enemy spawn reduction
const BOSS_WAVE_SPAWN_MULTIPLIER = 0.25  # 25% of normal spawn

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
    spawnExplosionPooled(game.particlePool, enemy.pos.x, enemy.pos.y,
                  Color(r: 255, g: 50, b: 50, a: 255), 15)
  
  game.enemies = @[]
  game.bullets = @[]
  game.waveEnemiesRemaining = 0
  game.waveInProgress = false
  game.currentWave += 1
  game.wavesUntilBoss -= 1
  # Golden pulse on boss defeat
  spawnWavePulse(game.osBackground,
    game.screenWidth.float32 / 2.0,
    game.screenHeight.float32 / 2.0,
    Color(r: 255, g: 215, b: 0, a: 255))
  
  if game.wavesUntilBoss <= 0:
    game.wavesUntilBoss = 4  # Next boss in 5 waves
  
  # Reset combo after boss wave
  game.dopamine.comboSystem.killCount = 0
  game.dopamine.comboSystem.bonusCoins = 0
  game.dopamine.comboSystem.comboWindow = 4.0
  game.dopamine.comboSystem.displayTimer = 0
  game.dopamine.comboSystem.waveKillCount = 0
  game.dopamine.comboSystem.waveComboBreaks = 0
  
  # Calculate final wave stats for celebration
  calculateAccuracy(game.dopamine.waveStats)
  
  # Trigger wave celebration AFTER boss is defeated (every boss wave = every 5th wave)
  # Use currentWave - 1 because currentWave was just incremented above
  startCelebration(game.dopamine.waveCelebration, game.currentWave - 1, game.dopamine.waveStats)
  
  game.powerUpChoices = generatePowerUpChoices(game.player, true)
  game.selectedPowerUp = 0
  initPowerUpRollAnimation(game)
  game.state = gsPowerUpSelect

# Unified aura configuration and rendering system

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
    of 1: 150.0
    of 2: 200.0
    else: 250.0
  
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
  ##
  ## Note: `enemy` is a ref object, so field mutations below (e.g. enemy.shieldHp -= ...)
  ## are intentional and persist on the heap even though the parameter is a `let` binding.
  result = baseDamage
  
  # Boss defense multiplier: reduces all incoming damage
  if enemy.isBoss and enemy.defenseMultiplier > 0:
    result *= enemy.defenseMultiplier
  
  # Tank elite: 50% damage reduction
  # If multiple elites include Tank, apply reduction
  if enemy.isElite and etTank in enemy.eliteTypes:
    result *= 0.5  # 50% damage taken
  
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
  
  # Diamond enemy: 1-hit shield absorbs the first hit entirely (like Celestial Veil)
  if enemy.enemyType == etDiamond and enemy.diamondShieldActive:
    enemy.diamondShieldActive = false
    result = 0

proc damageEnemy(enemy: Enemy, baseDamage: float32): float32 =
  ## Helper to apply damage to enemy with elite modifiers
  ## Combines applyEliteModifiers and HP reduction in one call
  ## Returns the actual damage dealt after modifiers
  ## Note: Enemies can die (hp = 0) but can't have fractional HP below 0.01 while alive
  
  # Check boss invulnerability (during phase transitions)
  if enemy.isBoss and enemy.invulnerabilityTimer > 0:
    return 0.0
  
  result = applyEliteModifiers(enemy, baseDamage)
  
  # Stars use hit counter for ALL damage sources
  if enemy.enemyType == etStar:
    enemy.hitCount += 1
  else:
    enemy.hp -= result
  
# CENTRALIZED COMBAT STATS SYSTEM
# Single source of truth for all combat-related stat calculations
type CombatStats* = object
  damage*: float32          # Final damage with all bonuses
  baseDamage*: float32      # Base damage before power-ups (for attribution)
  fireRate*: float32        # Current fire rate with all modifiers
  critChance*: int          # Critical hit chance (0-100)
  critMultiplier*: float32  # Critical hit damage multiplier
  hasCrit*: bool            # Whether player has crit power-up

proc calculateCombatStats*(player: Player): CombatStats =
  ## Calculates all combat stats in one place
  ## Single source of truth for damage, fire rate, crit chance calculations
  result.baseDamage = player.damage
  result.damage = player.damage * player.bulletDamageMult  # Include bullet-specific multipliers
  result.fireRate = player.fireRate
  result.critChance = 0
  result.critMultiplier = 2.0
  result.hasCrit = false
  
  # DAMAGE CALCULATIONS
  
  # Damage boost consumable
  if player.damageBoostTimer > 0:
    result.damage *= 1.5  # +50% damage
  
  # Rage power-up - damage increases when HP is low
  for powerUp in player.powerUps:
    if powerUp.powerType == puRage:
      let hpPercent = player.hp / player.maxHp
      let hpLost = 1.0 - hpPercent
      let bonusPerTenPercent = case powerUp.level
        of 1: 0.05  # 5% per 10% HP lost
        of 2: 0.08  # 8% per 10% HP lost
        else: 0.12  # 12% per 10% HP lost
      let damageBonus = 1.0 + (hpLost * 10.0 * bonusPerTenPercent)
      result.damage *= damageBonus
  
  # Fire rate boost consumable
  if player.fireRateBoostTimer > 0:
    result.fireRate *= 0.6
  
  # Double Shot penalty - 25% slower fire rate
  for powerUp in player.powerUps:
    if powerUp.powerType == puDoubleShot:
      result.fireRate *= 1.25  # 25% slower (higher value = slower)
  
  # Berserker power-up - fire rate increases when HP is low
  for powerUp in player.powerUps:
    if powerUp.powerType == puBerserker:
      let hpPercent = player.hp / player.maxHp
      let hpLost = 1.0 - hpPercent
      let bonusPerTenPercent = case powerUp.level
        of 1: 0.05  # 5% per 10% HP lost
        of 2: 0.08  # 8% per 10% HP lost
        else: 0.15  # 15% per 10% HP lost
      let fireRateBonus = 1.0 + (hpLost * 10.0 * bonusPerTenPercent)
      result.fireRate *= (1.0 / fireRateBonus)  # Lower fire rate value = faster shooting
  
  # CRITICAL HIT CALCULATIONS
  
  if hasPowerUp(player, puCriticalHit):
    result.hasCrit = true
    let critLevel = getPowerUpLevel(player, puCriticalHit)
    result.critChance = case critLevel
      of 1: 20  # 20% chance
      of 2: 35  # 35% chance
      else: 50  # 50% chance
    result.critMultiplier = 2.0

proc applyCriticalHitFromStats*(stats: CombatStats, baseDamage: float32): float32 =
  ## Applies critical hit using pre-calculated stats
  ## Returns damage with critical multiplier if crit occurs
  if not stats.hasCrit:
    return baseDamage
  
  if rand(99) < stats.critChance:
    return baseDamage * stats.critMultiplier
  else:
    return baseDamage

proc applyCriticalHitWithFlag*(stats: CombatStats, baseDamage: float32): tuple[damage: float32, wasCrit: bool] =
  ## Applies critical hit using pre-calculated stats
  ## Returns tuple with damage and whether a crit occurred
  if not stats.hasCrit:
    return (baseDamage, false)
  
  if rand(99) < stats.critChance:
    return (baseDamage * stats.critMultiplier, true)
  else:
    return (baseDamage, false)

# DAMAGE NUMBERS HELPER

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
  
  # Track the damage type for this accumulation period
  enemy.lastAuraDamageType = damageType
  
  # Track if ANY tick was a crit during this accumulation period
  if wasCrit:
    enemy.auraDamageHadCrit = true
  
  # Check if enough time has passed to show a damage number
  let timeSinceLastNumber = game.time - enemy.lastAuraDamageNumberTime
  
  if timeSinceLastNumber >= DAMAGE_NUMBER_INTERVAL:
    # Time to show accumulated damage (raw damage, not per-second)
    if enemy.auraDamageAccumulator > 0:
      # Show the raw accumulated damage with crit status
      game.showDamage(enemy.pos, enemy.auraDamageAccumulator, fromPlayer = true,
                      isCritical = enemy.auraDamageHadCrit, damageType = damageType)
    
    # Reset accumulator, timer, and crit tracker
    enemy.auraDamageAccumulator = 0
    enemy.auraDamageHadCrit = false
    enemy.lastAuraDamageNumberTime = game.time

proc flushAccumulatedAuraDamage*(game: Game, enemy: Enemy) =
  ## Force display of any accumulated aura damage (used when enemy dies)
  ## This ensures players see the total damage dealt even if enemy dies before 0.5s interval
  if enemy.auraDamageAccumulator > 0:
    game.showDamage(enemy.pos, enemy.auraDamageAccumulator, fromPlayer = true,
                    isCritical = enemy.auraDamageHadCrit, damageType = enemy.lastAuraDamageType)
    # Reset accumulator and crit tracker
    enemy.auraDamageAccumulator = 0
    enemy.auraDamageHadCrit = false

proc accumulateAndShowContactDamage(game: Game, enemy: Enemy, actualDamage: float32) =
  ## Accumulates contact damage and displays damage numbers every 0.5 seconds
  ## Shows accumulated damage to prevent spam from 10 HP/sec ticks
  const DAMAGE_NUMBER_INTERVAL = 0.5  # Show damage numbers every 0.5 seconds
  
  # Initialize timer on first contact damage tick
  if enemy.lastContactDamageNumberTime == 0:
    enemy.lastContactDamageNumberTime = game.time
  
  # Accumulate damage
  enemy.contactDamageAccumulator += actualDamage
  
  # Check if enough time has passed to show a damage number
  let timeSinceLastNumber = game.time - enemy.lastContactDamageNumberTime
  
  if timeSinceLastNumber >= DAMAGE_NUMBER_INTERVAL:
    # Time to show accumulated damage
    if enemy.contactDamageAccumulator > 0:
      game.showDamage(enemy.pos, enemy.contactDamageAccumulator, fromPlayer = true,
                      isCritical = false, damageType = dtDefault)
    
    # Reset accumulator and timer
    enemy.contactDamageAccumulator = 0
    enemy.lastContactDamageNumberTime = game.time

proc flushAccumulatedContactDamage*(game: Game, enemy: Enemy) =
  ## Force display of any accumulated contact damage (used when enemy dies)
  ## This ensures players see the total damage dealt even if enemy dies before 0.5s interval
  if enemy.contactDamageAccumulator > 0:
    game.showDamage(enemy.pos, enemy.contactDamageAccumulator, fromPlayer = true,
                    isCritical = false, damageType = dtDefault)
    # Reset accumulator
    enemy.contactDamageAccumulator = 0

proc calculateContactDamageToEnemy*(player: Player, enemy: Enemy): tuple[damage: float32, wasCrit: bool] =
  ## Player ramming into an enemy deals damage based on:
  ##   - player.damage  (scales with all damage power-ups)
  ##   - player speed   (moving fast = hits harder, standing still = weak tap)
  ##   - max HP         (small bonus for tankier builds)
  ##   - critical hits  (respects the Critical Hit power-up)
  
  # Base: 50% of the player's current damage stat so it's always meaningful
  # but never outright replaces shooting as the main damage source
  var base = player.damage * 0.5
  
  # Speed multiplier: 0.5x at zero movement, 1.5x at full speed (175)
  let speedRatio = player.vel.length() / player.baseSpeed
  let speedMult = 0.5 + speedRatio * 1.0   # range: 0.5 – 1.5
  base *= speedMult
  
  # Max-HP bonus: +2% per HP above the base 9, capped at +50%
  let hpBonus = min((player.maxHp - 9.0) * 0.02, 0.5)
  base *= (1.0 + hpBonus)
  
  # Boss defense multiplier already handled by damageEnemy(), skip here
  
  # Critical hit — uses the same CombatStats path as bullets
  let stats = calculateCombatStats(player)
  let (finalDamage, wasCrit) = applyCriticalHitWithFlag(stats, base)
  return (finalDamage, wasCrit)

# THORNS REFLECTION HELPER

proc applyThornsReflection*(game: var Game, player: Player, damageToReflect: float32,
                            targetEnemy: Enemy, reflectType: string): float32 =
  ## Centralized thorns reflection calculation
  ## reflectType: "contact" for enemy contact, "bullet" for enemy bullets, "boss" for boss contact
  ## Returns actual damage dealt (after shields/reductions)
  if not hasPowerUp(player, puThorns):
    return 0.0
  
  let thornsLevel = getPowerUpLevel(player, puThorns)
  
  # Different reflection percentages for different damage types
  let reflectPercent = case reflectType
    of "bullet":
      case thornsLevel
      of 1: 0.5  # 50% reflection for bullets
      of 2: 1.0  # 100% reflection
      else: 2.0  # 200% reflection
    of "boss", "contact":
      case thornsLevel
      of 1: 0.5  # 50% reflection for contact
      of 2: 1.0  # 100% reflection
      else: 2.0  # 200% reflection
    else: 0.0
  
  let reflectDamageBase = damageToReflect * reflectPercent
  
  let hpScaling = player.maxHp * 0.01
  let reflectDamageWithScaling = reflectDamageBase + hpScaling
  
  # Apply critical hit chance to thorns reflection
  let thornStats = calculateCombatStats(player)
  let reflectDamageWithCrit = applyCriticalHitFromStats(thornStats, reflectDamageWithScaling)
  let actualDamage = damageEnemy(targetEnemy, reflectDamageWithCrit)
  
  # Track thorns damage for statistics
  trackPowerUpDamage(game, puThorns, actualDamage)
  
  # Create damage number for thorns reflection
  game.showDamage(targetEnemy.pos, actualDamage, fromPlayer = true,
                  isCritical = reflectDamageWithCrit > reflectDamageBase, damageType = dtDefault)
  
  # Visual feedback
  spawnExplosionPooled(game.particlePool, targetEnemy.pos.x, targetEnemy.pos.y, Red,
                if reflectType == "boss": 8 elif reflectType == "contact": 6 else: 5)
  
  return actualDamage

# COMMON HELPER FUNCTIONS FOR POWER-UP CALCULATIONS

# LIGHTNING BOLT VISUALS
const LIGHTNING_BOLT_DURATION* = 0.18'f32  # seconds the arc stays visible
const LIGHTNING_SEGMENTS      = 8          # number of jagged waypoints

proc spawnLightningBolt*(game: var Game, fromPos, toPos: Vector2f) =
  ## Spawn a short-lived jagged lightning arc between two world positions.
  ## Uses the deterministic particle-pool RNG via `rand`, so no extra state needed.
  let dx = toPos.x - fromPos.x
  let dy = toPos.y - fromPos.y
  let len = sqrt(dx * dx + dy * dy)
  if len < 1.0: return

  # Perpendicular unit vector for jag offsets
  let px = -dy / len
  let py =  dx / len

  # Jag amplitude: ~15% of total length, decreasing toward endpoints
  let ampBase = len * 0.15'f32

  var segs: seq[Vector2f] = @[fromPos]
  for i in 1..<LIGHTNING_SEGMENTS:
    let t = float32(i) / float32(LIGHTNING_SEGMENTS)
    # Linear interpolation base point
    let bx = fromPos.x + dx * t
    let by = fromPos.y + dy * t
    # Random jag perpendicular – envelope tapers at both ends
    let env   = 1.0'f32 - abs(t * 2.0'f32 - 1.0'f32)
    let jag   = (rand(1.0) * 2.0 - 1.0).float32 * ampBase * env
    segs.add(newVector2f(bx + px * jag, by + py * jag))
  segs.add(toPos)

  game.lightningBolts.add(LightningBolt(
    startPos:    fromPos,
    endPos:      toPos,
    lifetime:    LIGHTNING_BOLT_DURATION,
    maxLifetime: LIGHTNING_BOLT_DURATION,
    segments:    segs
  ))

proc updateLightningBolts*(game: var Game, dt: float32) =
  var i = 0
  while i < game.lightningBolts.len:
    game.lightningBolts[i].lifetime -= dt
    if game.lightningBolts[i].lifetime <= 0:
      game.lightningBolts.delete(i)
    else:
      inc i

proc drawLightningBolts*(game: Game) =
  for bolt in game.lightningBolts:
    let alpha = uint8(clamp(bolt.lifetime / bolt.maxLifetime * 255.0, 0.0, 255.0))
    # Bright core (white-yellow)
    let coreColor  = Color(r: 255, g: 255, b: 200, a: alpha)
    # Wider glow (pale blue)
    let glowColor  = Color(r: 140, g: 200, b: 255, a: uint8(alpha.int * 60 div 255))

    for i in 0..<bolt.segments.len - 1:
      let a = bolt.segments[i]
      let b = bolt.segments[i + 1]
      let ax = a.x.int32;  let ay = a.y.int32
      let bx = b.x.int32;  let by = b.y.int32
      # Glow pass (drawn first, wider conceptually – draw offset copies)
      drawLine(ax - 1, ay,     bx - 1, by,     glowColor)
      drawLine(ax + 1, ay,     bx + 1, by,     glowColor)
      drawLine(ax,     ay - 1, bx,     by - 1, glowColor)
      drawLine(ax,     ay + 1, bx,     by + 1, glowColor)
      # Core pass
      drawLine(ax, ay, bx, by, coreColor)

proc getAuraRadius*(level: int): float32 =
  ## Standard aura radius based on level (used by most aura effects)
  case level
  of 1: 150.0
  of 2: 200.0
  else: 250.0

proc getExplosionRadius*(level: int): float32 =
  ## Standard explosion radius for explosive bullets
  case level
  of 1: 50.0
  of 2: 75.0
  else: 100.0

proc getBulletDamageType*(bullet: Bullet): DamageType =
  ## Determine the damage type for a bullet based on its properties
  ## Returns the appropriate elemental type or dtDefault for normal bullets
  if bullet.isArcaneBullet:
    return dtArcane
  elif bullet.fireDuration > 0:
    return dtFire
  elif bullet.poisonDuration > 0:
    return dtPoison
  elif bullet.slowAmount > 0:
    return dtFrost  # Frost/slow bullets use the dedicated frost color (light blue)
  elif bullet.windPushForce > 0:
    return dtDefault  # Wind uses default white
  else:
    return dtDefault  # Normal bullets use white

# UNIFIED BULLET EFFECT SYSTEM

type
  BulletEffectType* = enum
    befFrost
    befPoison
    befFire
    befWind
    befChainLightning
    befBlood

  BulletEffect* = object
    effectType*: BulletEffectType
    baseDamage*: float32
    duration*: float32
    hasMastery*: bool
    level*: int

proc getBulletEffects(game: Game, bullet: Bullet): seq[BulletEffect] =
  ## Extract all active bullet effects from a bullet
  result = @[]
  
  # Frost effect
  if bullet.slowAmount > 0 and hasPowerUp(game.player, puFrostShots):
    result.add(BulletEffect(
      effectType: befFrost,
      baseDamage: bullet.damage,
      duration: 999999.0,  # Infinite
      hasMastery: game.player.hasFrostMastery,
      level: getPowerUpLevel(game.player, puFrostShots)
    ))
  
  # Poison effect
  if bullet.poisonDuration > 0 and hasPowerUp(game.player, puPoisonShot):
    let poisonLevel = getPowerUpLevel(game.player, puPoisonShot)
    let poisonDmg = case poisonLevel
      of 1: 1.0
      of 2: 1.5
      else: 2.0
    
    result.add(BulletEffect(
      effectType: befPoison,
      baseDamage: poisonDmg,
      duration: bullet.poisonDuration,
      hasMastery: game.player.hasPoisonMastery,
      level: poisonLevel
    ))
  
  # Fire effect
  if bullet.fireDuration > 0 and hasPowerUp(game.player, puFireBullets):
    let fireLevel = getPowerUpLevel(game.player, puFireBullets)
    let fireDmg = case fireLevel
      of 1: 1.0
      of 2: 1.5
      else: 2.0
    
    result.add(BulletEffect(
      effectType: befFire,
      baseDamage: fireDmg,
      duration: bullet.fireDuration,
      hasMastery: game.player.hasFireMastery,
      level: fireLevel
    ))
  
  # Wind effect
  if bullet.windPushForce > 0 and hasPowerUp(game.player, puWindBullets):
    result.add(BulletEffect(
      effectType: befWind,
      baseDamage: bullet.damage,
      duration: 0.0,  # Instant effect
      hasMastery: game.player.hasWindMastery,
      level: getPowerUpLevel(game.player, puWindBullets)
    ))
  
  # Chain Lightning effect
  if hasPowerUp(game.player, puChainLightning):
    result.add(BulletEffect(
      effectType: befChainLightning,
      baseDamage: bullet.damage,
      duration: 0.0,  # Instant effect
      hasMastery: game.player.hasLightningMastery,
      level: getPowerUpLevel(game.player, puChainLightning)
    ))
  
  # Blood effect
  if hasPowerUp(game.player, puBloodBullets):
    result.add(BulletEffect(
      effectType: befBlood,
      baseDamage: bullet.damage,
      duration: 0.0,  # Instant effect
      hasMastery: game.player.hasBloodMastery,
      level: getPowerUpLevel(game.player, puBloodBullets)
    ))

proc applyBulletEffect(game: var Game, effect: BulletEffect, enemy: Enemy,
                       bullet: Bullet, dt: float32, stats: CombatStats) =
  ## Apply a single bullet effect to an enemy
  ## Uses pre-calculated combat stats for critical hit calculations
  case effect.effectType
  of befFrost:
    # Frost: Permanent slow (reduced by debuffResistance for bosses)
    # Only apply if stronger than current slow or current slow expired
    let newSlowAmount = bullet.slowAmount * (1.0 - enemy.debuffResistance)
    if newSlowAmount > enemy.slowAmount or enemy.slowTimer <= 0:
      enemy.slowTimer = effect.duration
      enemy.slowAmount = newSlowAmount
  
  of befPoison:
    # Poison: DoT effect
    var poisonDmg = effect.baseDamage
    var poisonDur = effect.duration
    
    if effect.hasMastery:
      poisonDmg *= 2.5  # +150% damage
      poisonDur *= 2.0  # +100% duration
    
    applyEffect(enemy, etPoison, poisonDmg, poisonDur, "shot")
    
    # Apply slow only with mastery (reduced by debuffResistance for bosses)
    if effect.hasMastery:
      # Only apply if stronger than current slow or current slow expired
      let newSlowAmount = 0.30 * (1.0 - enemy.debuffResistance)
      if newSlowAmount > enemy.slowAmount or enemy.slowTimer <= 0:
        enemy.slowTimer = poisonDur
        enemy.slowAmount = newSlowAmount  # 30% slow
  
  of befFire:
    # Fire: DoT effect
    var fireDmg = effect.baseDamage
    var fireDur = effect.duration
    
    if effect.hasMastery:
      fireDmg *= 2.5  # +150% damage
      fireDur *= 2.0  # +100% duration
    
    applyEffect(enemy, etFire, fireDmg, fireDur, "shot")
    
    # Apply slow only with mastery (reduced by debuffResistance for bosses)
    if effect.hasMastery:
      # Only apply if stronger than current slow or current slow expired
      let newSlowAmount = 0.35 * (1.0 - enemy.debuffResistance)
      if newSlowAmount > enemy.slowAmount or enemy.slowTimer <= 0:
        enemy.slowTimer = fireDur
        enemy.slowAmount = newSlowAmount  # 35% slow
  
  of befWind:
    # Wind: Knockback
    let pushDir = (enemy.pos - game.player.pos).normalize()
    let bossResistance = if enemy.isBoss: 0.1 else: 1.0
    
    var actualWindForce = bullet.windPushForce
    if effect.hasMastery:
      actualWindForce *= 2.5  # +150% stronger
    
    # Apply push
    enemy.pos.x += pushDir.x * actualWindForce * dt * bossResistance
    enemy.pos.y += pushDir.y * actualWindForce * dt * bossResistance
    
    # Clamp to screen boundaries - enemies can't be pushed through borders
    enemy.pos.x = clamp(enemy.pos.x, enemy.radius, game.screenWidth.float32 - enemy.radius)
    enemy.pos.y = clamp(enemy.pos.y, enemy.radius, game.screenHeight.float32 - enemy.radius)
    
    # Apply slow only with mastery (reduced by debuffResistance for bosses)
    if effect.hasMastery:
      enemy.slowTimer = 0.2
      let slowValue = 0.40 * (1.0 - enemy.debuffResistance)
      if enemy.slowAmount < slowValue:
        enemy.slowAmount = slowValue  # 40% slow
    
    # Visual wind effect particles
    for k in 0..3:
      let particleAngle = rand(1.0) * PI * 2.0
      let particleDist = rand(enemy.radius + 10.0)
      let particleX = enemy.pos.x + cos(particleAngle) * particleDist
      let particleY = enemy.pos.y + sin(particleAngle) * particleDist
      spawnExplosionPooled(game.particlePool, particleX, particleY,
                    Color(r: 200, g: 230, b: 255, a: 180), 2)
  
  of befChainLightning:
    # Chain lightning: Chain to nearby enemies
    if enemy.chainLightningCooldown <= 0:
      let chainCount = effect.level  # 1, 2, or 3 chains
      let chainDamage = case effect.level
        of 1: 0.7
        of 2: 0.85
        else: 1.0
      
      var chainRange = case effect.level
        of 1: 125.0
        of 2: 150.0
        else: 175.0
      
      if effect.hasMastery:
        chainRange *= 1.5  # +50% range
      
      # Stun primary target (reduced by debuffResistance for bosses)
      # Only apply if stronger than current slow or current slow expired
      let newSlowAmount = 0.99 * (1.0 - enemy.debuffResistance)  # 99% slow = stun (cap to prevent permanent freeze)
      if newSlowAmount > enemy.slowAmount or enemy.slowTimer <= 0:
        enemy.slowTimer = 0.05
        enemy.slowAmount = newSlowAmount
      enemy.chainLightningCooldown = 0.3
      
      # Find nearby enemies to chain to
      var chained = 0
      for k in 0..<game.enemies.len:
        if game.enemies[k] != enemy and chained < chainCount:
          let dist = distance(enemy.pos, game.enemies[k].pos)
          if dist < chainRange and game.enemies[k].chainLightningCooldown <= 0:
            let chainDmgBase = effect.baseDamage * chainDamage
            let chainDmgWithCrit = applyCriticalHitFromStats(stats, chainDmgBase)
            let actualDamage = damageEnemy(game.enemies[k], chainDmgWithCrit)
            
            # Track chain lightning damage for statistics
            if actualDamage > 0:
              trackPowerUpDamage(game, puChainLightning, actualDamage)
            
            # Create damage number
            if actualDamage > 0:
              showDamage(game, game.enemies[k].pos, actualDamage, true,
                        chainDmgWithCrit > chainDmgBase, dtLightning)
            
            game.enemies[k].chainLightningCooldown = 0.3
            # Only apply stun if stronger than current slow or current slow expired
            let chainSlowAmount = 0.99 * (1.0 - game.enemies[k].debuffResistance)
            if chainSlowAmount > game.enemies[k].slowAmount or game.enemies[k].slowTimer <= 0:
              game.enemies[k].slowTimer = 0.05
              game.enemies[k].slowAmount = chainSlowAmount
            chained += 1
            
            # Lightning arc visual connecting the two enemies
            spawnLightningBolt(game, enemy.pos, game.enemies[k].pos)
  
  of befBlood:
    # Blood: Lifesteal
    var healPercent = case effect.level
      of 1: 0.0175  # 1.75%
      of 2: 0.0225  # 2.25%
      else: 0.03  # 3%
    
    if effect.hasMastery:
      healPercent *= 2.0  # +100% lifesteal
    
    let healAmount = effect.baseDamage * healPercent
    heal(game.player, healAmount)
    
    if healAmount > 0.01:
      spawnExplosionPooled(game.particlePool, game.player.pos.x, game.player.pos.y, Green, 3)
      showDamage(game, game.player.pos, healAmount, true, false, dtHeal)

proc applyBulletEffects*(game: var Game, bullet: Bullet, enemy: Enemy, dt: float32) =
  ## Apply all bullet effects to an enemy - unified entry point
  let effects = getBulletEffects(game, bullet)
  
  # Calculate combat stats once for all effects
  let stats = calculateCombatStats(game.player)
  
  for effect in effects:
    applyBulletEffect(game, effect, enemy, bullet, dt, stats)

proc cleanupGame*(game: Game) =
  ## Clean up game resources before creating a new game
  ## This prevents memory leaks and performance issues when returning to menu
  
  # Don't cleanup Discord client - it's global and persists across sessions
  # Just clear the reference
  game.discordClient = nil
  
  # Clear all game objects to help garbage collector
  game.enemies = @[]
  game.bullets = @[]
  game.coins = @[]
  game.consumables = @[]
  game.walls = @[]
  game.attackWarnings = @[]
  game.lasers = @[]
  game.meteorites = @[]
  game.damageNumbers = @[]
  
  # Clear player rotating orbs
  if not game.player.isNil:
    game.player.rotatingOrbs = @[]

proc newGame*(screenWidth, screenHeight: int32, playerSkin: int = 0, bulletSkin: int = 0, playerShape: int = 0, particleSkin: int = 0, bulletShape: int = 0): Game =
  let defaultMode = gmWaveBased  # Default to wave-based mode
  let modeDef = getGameModeDefinition(defaultMode)
  
  result = Game(
    state: gsPlaying,
    mode: defaultMode,
    player: newPlayer(screenWidth.float32 / 2, screenHeight.float32 / 2),
    enemies: @[],
    bullets: @[],
    bulletIdCounter: 0,  # Start at 0, increment with each bullet that needs tracking
    coins: @[],
    consumables: @[],
    walls: @[],
    particlePool: newParticlePool(2000),
    attackWarnings: @[],
    lasers: @[],
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
    statsMenuTab: 0,  # 0 = Lifetime, 1 = Last Run
    # OS-Style Visual System
    osBackground: newOSBackground(),
    osHUD: newOSHUD(),
    pauseMenuTab: tmtProcesses,  # Default to Processes tab in task manager
    selectedGameOverButton: 0,  # Default to Restart button
    dopamine: newDopamineState()
  )
  
  initEnhancedDopamine(result.dopamine)
  
  # Apply gamemode-specific starting values
  result.player.coins = modeDef.playerStartCoins
  
  # Apply player skin from settings
  result.player.skinType = playerSkin
  result.player.bulletSkinType = bulletSkin
  result.player.shapeType = playerShape
  result.player.bulletShapeType = bulletShape
  result.player.particleSkinType = particleSkin
  
  # Discord client is assigned from global instance in main.nim
  # Don't create a new client here to avoid threading issues
  
  # Note: initializeRunTracking is called explicitly when starting a game
  # (not in sandbox mode) to ensure correct mode is tracked

proc setGameMode*(game: Game, mode: GameMode) =
  ## Changes the game mode and applies mode-specific settings
  game.mode = mode
  let modeDef = getGameModeDefinition(mode)
  
  # Apply mode-specific starting values
  game.player.coins = modeDef.playerStartCoins
  
  # Reset wave-specific state if not using waves
  if not modeDef.usesWaves:
    game.currentWave = 1
    game.waveInProgress = false
    game.waveEnemiesRemaining = 0

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
  # Visual pulse ring — cyan for normal waves, orange for boss-lead waves
  let wavePulseColor = if game.wavesUntilBoss == 1:
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
        # Waves 21-25: Introduce STAR
        if roll < 20: enemyType = etStar
        elif roll < 35: enemyType = etCircle
        elif roll < 53: enemyType = etCube
        elif roll < 70: enemyType = etPentagon
        else: enemyType = etTriangle
      
      elif wave <= 30:
        # Waves 26-30: Introduce CROSS
        if roll < 25: enemyType = etCross
        elif roll < 42: enemyType = etCircle
        elif roll < 55: enemyType = etCube
        elif roll < 65: enemyType = etStar
        elif roll < 80: enemyType = etPentagon
        else: enemyType = etTriangle
      
      elif wave <= 35:
        # Waves 31-35: Introduce DIAMOND
        if roll < 22: enemyType = etDiamond
        elif roll < 38: enemyType = etCircle
        elif roll < 51: enemyType = etCube
        elif roll < 61: enemyType = etStar
        elif roll < 74: enemyType = etCross
        elif roll < 84: enemyType = etPentagon
        else: enemyType = etTriangle
      
      elif wave <= 40:
        # Waves 36-40: Introduce OCTAGON
        if roll < 20: enemyType = etOctagon
        elif roll < 34: enemyType = etCircle
        elif roll < 46: enemyType = etCube
        elif roll < 56: enemyType = etStar
        elif roll < 68: enemyType = etCross
        elif roll < 77: enemyType = etDiamond
        elif roll < 86: enemyType = etPentagon
        else: enemyType = etTriangle
      
      elif wave <= 45:
        # Waves 41-45: Introduce HEXAGON
        if roll < 18: enemyType = etHexagon
        elif roll < 25: enemyType = etCube # Don't spawn circles after wave 40
        elif roll < 35: enemyType = etStar
        elif roll < 55: enemyType = etCross
        elif roll < 73: enemyType = etDiamond
        elif roll < 81: enemyType = etOctagon
        elif roll < 89: enemyType = etPentagon
        else: enemyType = etTriangle
      
      elif wave <= 50:
        # Waves 46-50: Introduce TRICKSTER
        if roll < 20: enemyType = etTrickster
        elif roll < 33: enemyType = etCube # Don't spawn circles after wave 40
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
        elif roll < 26: enemyType = etCube # Don't spawn circles after wave 40
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
        elif roll < 20: enemyType = etCube # Don't spawn circles or pentagons after wave 56
        elif roll < 30: enemyType = etStar
        elif roll < 40: enemyType = etCross
        elif roll < 50: enemyType = etDiamond
        elif roll < 60: enemyType = etOctagon
        elif roll < 70: enemyType = etHexagon
        elif roll < 80: enemyType = etTrickster
        elif roll < 90: enemyType = etPhantom
        elif roll < 99: enemyType = etTriangle
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
  # Calculate all combat stats once at the start
  let stats = calculateCombatStats(game.player)
  
  if game.time - game.player.lastShot >= stats.fireRate:
    # Increment bullet counter for special rounds power-up
    game.player.bulletCounter += 1
    
    recordShot(game.dopamine.waveStats, false)  # Will be updated to true if hit
    
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
    
    # Base bullet properties - use calculated stats
    var speed = game.player.bulletSpeed * 1.2
    var damage = stats.damage  # Already includes Rage bonus
    
    # Double-shot bullets deal 10% less damage per bullet
    if hasDoubleShot:
      damage *= 0.85  # 15% less damage per bullet
        
    var bulletRadius = BASE_PLAYER_BULLET_RADIUS
    
    # Apply heavy rounds power-up
    if hasPowerUp(game.player, puHeavyRounds):
      let heavyLevel = getPowerUpLevel(game.player, puHeavyRounds)
      let heavyMultiplier = case heavyLevel
        of 1: 1.5   # +50% size
        of 2: 2.0   # +100% size
        else: 2.5   # +150% size
      bulletRadius *= heavyMultiplier
    
    # Apply critical hit chance using pre-calculated stats and capture if it was a crit
    let baseDamagePreCrit = damage  # Store pre-crit value for puCriticalHit tracking
    let (damageWithCrit, wasCrit) = applyCriticalHitWithFlag(stats, damage)
    damage = damageWithCrit
    
    # Check for Special Rounds power-up
    var isSpecialRound = false
    if hasPowerUp(game.player, puSpecialRounds):
      let specialLevel = getPowerUpLevel(game.player, puSpecialRounds)
      let roundInterval = case specialLevel
        of 1: 5  # Every 5th bullet
        of 2: 4  # Every 4th bullet
        else: 3  # Every 3rd bullet
      
      if game.player.bulletCounter mod roundInterval == 0:
        isSpecialRound = true
        # Special rounds deal bonus damage
        damage *= 1.75  # +75% bonus damage
    
    # Apply Arcane Mastery bonus to Arcane bullets (damage + piercing)
    var arcanePiercing = hasPiercing  # Start with base piercing status
    var arcaneMasteryBonus = 0.0
    if hasArcane and game.player.hasArcaneMastery:
      let damageBeforeMastery = damage
      damage *= 2.0  # +100% additional damage on top of Arcane Bullets bonus
      arcaneMasteryBonus = damage - damageBeforeMastery  # The extra 150%
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
    
    # Heavy Rounds knockback effect (adds to windEffect if both exist)
    if hasPowerUp(game.player, puHeavyRounds):
      let heavyLevel = getPowerUpLevel(game.player, puHeavyRounds)
      let heavyKnockback = case heavyLevel
        of 1: 80.0    # Slight knockback
        of 2: 150.0   # Increased knockback
        else: 250.0   # Strong knockback
      windEffect += heavyKnockback
    
    if hasDoubleShot and hasMultiShot:
      # When both active: Fire multishot pattern (3 directions), then schedule second burst
      let multiCount = 3  # Always 3 bullets for legendary Multi-Shot
      let spreadAngle = 0.3
      
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
          isBonusFromMultiShot = (i > 0),  # First bullet (i=0) is normal, rest are bonus
          wasCrit = wasCrit,
          isSpecialRound = isSpecialRound,
          bulletSkin = game.player.bulletSkinType,
          bulletShape = game.player.bulletShapeType
        )
        bullet.radius = bulletRadius
        bullet.baseDamagePreCrit = baseDamagePreCrit
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
        isBonusFromDoubleShot = false,  # First bullet is normal
        wasCrit = wasCrit,
        isSpecialRound = isSpecialRound,
        bulletSkin = game.player.bulletSkinType,
        bulletShape = game.player.bulletShapeType
      )
      bullet.radius = bulletRadius
      bullet.baseDamagePreCrit = baseDamagePreCrit
      assignBulletId(game, bullet)
      game.bullets.add(bullet)
      trackBulletFired(game)  # Track shot for statistics
      
      # Schedule second bullet with small delay (0.08s) - will be marked as bonus
      game.player.doubleShotDelay = 0.08
    elif hasMultiShot:
      # Shoot in 3 directions (legendary, no nerfs)
      let bulletCount = 3  # Always 3 bullets
      let spreadAngle = 0.3
      
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
          isBonusFromMultiShot = (i > 0),  # First bullet (i=0) is normal, rest are bonus
          wasCrit = wasCrit,
          isSpecialRound = isSpecialRound,
          bulletSkin = game.player.bulletSkinType,
          bulletShape = game.player.bulletShapeType
        )
        bullet.radius = bulletRadius
        bullet.baseDamagePreCrit = baseDamagePreCrit
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
        isArcaneBullet = hasArcane,
        wasCrit = wasCrit,
        isSpecialRound = isSpecialRound,
        bulletSkin = game.player.bulletSkinType,
        bulletShape = game.player.bulletShapeType
      )
      bullet.radius = bulletRadius
      bullet.baseDamagePreCrit = baseDamagePreCrit
      assignBulletId(game, bullet)
      game.bullets.add(bullet)
      trackBulletFired(game)  # Track shot for statistics
    
    game.player.lastShot = game.time
    
    # Nova: freeze newly spawned player bullets if Nova is active
    if game.player.novaActive:
      for bullet in game.bullets:
        if bullet.fromPlayer and not bullet.isFrozenByNova:
          bullet.isFrozenByNova = true
    
    # Play shoot sound
    playSound(stShoot, 0.3)
    
    # Use the new particle skin system
    let skinType = ParticleSkinType(game.player.particleSkinType)
    spawnShootingParticles(game.particlePool, game.player.pos.x, game.player.pos.y, skinType, game.time)

# Helper to fire delayed double-shot bursts
proc fireDoubleShotBurst*(game: Game, direction: Vector2f, hasMultiShot: bool) =
  # Calculate combat stats once for the burst
  let burstStats = calculateCombatStats(game.player)
  
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
  var damage = burstStats.damage * 0.85  # Second bullet reduced by 15%
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
  
  # Roll for critical hit
  let burstBaseDamagePreCrit = damage  # Store pre-crit value for puCriticalHit tracking
  let (damageWithCrit, wasCrit) = applyCriticalHitWithFlag(burstStats, damage)
  damage = damageWithCrit
  
  if hasPowerUp(game.player, puHeavyRounds):
    let sizeLevel = getPowerUpLevel(game.player, puHeavyRounds)
    let sizeMultiplier = case sizeLevel
      of 1: 1.5
      of 2: 2.0
      else: 2.5
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
    let spreadAngle = 0.3
    
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
        isBonusFromDoubleShot = true,
        isBonusFromMultiShot = (i > 0),
        wasCrit = wasCrit,
        bulletSkin = game.player.bulletSkinType,
        bulletShape = game.player.bulletShapeType
      )
      bullet.radius = bulletRadius
      bullet.baseDamagePreCrit = burstBaseDamagePreCrit
      assignBulletId(game, bullet)
      game.bullets.add(bullet)
      trackBulletFired(game)
      
      # Spawn shooting particles (only once, not per bullet in multi-shot)
      if i == 0:
        spawnShootingParticles(game.particlePool, game.player.pos.x, game.player.pos.y, ParticleSkinType(game.player.particleSkinType), game.time)
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
      isBonusFromDoubleShot = true,
      wasCrit = wasCrit,
      bulletSkin = game.player.bulletSkinType,
      bulletShape = game.player.bulletShapeType
    )
    bullet.radius = bulletRadius
    bullet.baseDamagePreCrit = burstBaseDamagePreCrit
    assignBulletId(game, bullet)
    game.bullets.add(bullet)
    trackBulletFired(game)
    
    # Spawn shooting particles
    spawnShootingParticles(game.particlePool, game.player.pos.x, game.player.pos.y, ParticleSkinType(game.player.particleSkinType), game.time)
  
  playSound(stShoot, 0.25)

proc updateCustomBossBehavior(game: Game, enemy: Enemy, phase: BossPhaseDefinition, dt: float32) =
  ## Updates boss movement based on phase specialBehavior
  if phase.specialBehavior == "":
    return
  
  let playerDist = distance(enemy.pos, game.player.pos)
  let toPlayer = (game.player.pos - enemy.pos).normalize()
  let centerX = game.screenWidth.float32 / 2.0
  let centerY = game.screenHeight.float32 / 2.0
  
  case phase.specialBehavior
  of "circle_movement":
    # Smooth velocity-based orbiting
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
      enemy.pos = enemy.pos + retreatDir * enemy.speed * 0.85 * dt
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
    # Erratic movement toward player with smooth direction blending (sin-based, no frame dependency)
    let cloneBlend = sin(game.time * PI) * 0.5 + 0.5  # 0..1, completes one cycle per 2s
    let perpDir = newVector2f(-toPlayer.y, toPlayer.x)
    let blendedDir = (toPlayer * cloneBlend + perpDir * (1.0 - cloneBlend)).normalize()
    enemy.pos = enemy.pos + blendedDir * enemy.speed * dt
  
  of "reality_break":
    # Chaotic unpredictable movement — time-based multi-frequency angle, no per-frame rand
    let randomAngle = game.time * 1.3 + sin(game.time * 2.7 + enemy.pos.x * 0.01) * PI +
                      cos(game.time * 1.9 + enemy.pos.y * 0.01) * PI
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
  
  of "electric_buildup":
    # Moves slowly with sudden micro-movements like electricity
    let chargeJitter = sin(game.time * 30.0 + cos(game.time * 40.0)) * 20.0 * dt
    let baseMove = toPlayer * enemy.speed * 0.6 * dt
    
    # Multiple jitter directions for electric feel
    let jitterAngle = game.time * 35.0
    let jitterX = cos(jitterAngle) * chargeJitter + cos(jitterAngle * 1.7) * chargeJitter * 0.5
    let jitterY = sin(jitterAngle) * chargeJitter + sin(jitterAngle * 1.3) * chargeJitter * 0.5
    
    enemy.pos = enemy.pos + baseMove + newVector2f(jitterX, jitterY)
    
    # Constant electric particles — timer-gated to ~6 spawns/sec regardless of fps
    if (game.time mod 0.15) < dt:
      let sparkX = enemy.pos.x + (rand(1.0) - 0.5) * enemy.radius * 2
      let sparkY = enemy.pos.y + (rand(1.0) - 0.5) * enemy.radius * 2
      spawnExplosionPooled(game.particlePool, sparkX, sparkY,
                     Color(r: 255, g: 255, b: 150, a: 255), 1)
  
  of "electric_surge":
    # Rapid zigzag movement like lightning bolt — smooth continuous direction, not discrete phase buckets
    let surgeAngle = arctan2(toPlayer.y, toPlayer.x) + sin(game.time * 15.0) * 0.5
    let surgeDir = newVector2f(cos(surgeAngle), sin(surgeAngle))
    enemy.pos = enemy.pos + surgeDir * enemy.speed * 1.0 * dt
    
    # Electric particles — gated to ~10 spawns/sec, not every frame
    if (game.time mod 0.1) < dt:
      spawnExplosionPooled(game.particlePool, enemy.pos.x, enemy.pos.y,
                     Color(r: 220, g: 230, b: 255, a: 200), 2)
  
  of "critical_discharge":
    # Ultra-chaotic movement with occasional micro-teleports
    # Use time-based trigger (~once every 2s) instead of per-frame rand, so rate is fps-independent
    let zapInterval = 2.0 + sin(game.time * 0.8) * 0.5  # 1.5–2.5s varying interval
    if (game.time mod zapInterval) < dt:
      let zapAngle = rand(1.0) * PI * 2.0
      let zapDist = 30.0 + rand(50.0)
      var newX = enemy.pos.x + cos(zapAngle) * zapDist
      var newY = enemy.pos.y + sin(zapAngle) * zapDist
      
      # Clamp within screen boundaries
      let margin = enemy.radius + 10.0
      newX = clamp(newX, margin, game.screenWidth.float32 - margin)
      newY = clamp(newY, margin, game.screenHeight.float32 - margin)
      
      enemy.pos = newVector2f(newX, newY)
      spawnExplosionPooled(game.particlePool, enemy.pos.x, enemy.pos.y,
                     Color(r: 255, g: 255, b: 255, a: 255), 15)
    else:
      # Normal zigzag but very fast
      let dischargeAngle = game.time * 25.0 + sin(game.time * 50.0)
      let chaosDir = newVector2f(cos(dischargeAngle), sin(dischargeAngle))
      enemy.pos = enemy.pos + chaosDir * enemy.speed * 1.25 * dt
  
  of "orbital_pattern":
    # Slow, calculated circular orbit (Orbital Commander phase 1)
    let orbitAngle = game.time * 0.8
    let orbitRadius = 200.0
    let orbitX = centerX + cos(orbitAngle) * orbitRadius
    let orbitY = centerY + sin(orbitAngle) * orbitRadius
    let toOrbit = (newVector2f(orbitX, orbitY) - enemy.pos).normalize()
    enemy.pos = enemy.pos + toOrbit * enemy.speed * dt
  
  of "satellite_swarm":
    # Complex multi-layer orbit (Orbital Commander phase 2)
    # Velocity-based movement toward the orbit target — no direct position assignment
    let swarmAngle1 = game.time * 1.2
    let swarmAngle2 = game.time * 0.6
    let innerRadius = 150.0 + sin(game.time * 2.0) * 30.0
    let outerRadius = 200.0
    let avgX = (cos(swarmAngle1) * innerRadius + cos(swarmAngle2) * outerRadius) / 2.0
    let avgY = (sin(swarmAngle1) * innerRadius + sin(swarmAngle2) * outerRadius) / 2.0
    var targetX = centerX + avgX
    var targetY = centerY + avgY
    let margin = enemy.radius + 10.0
    targetX = clamp(targetX, margin, game.screenWidth.float32 - margin)
    targetY = clamp(targetY, margin, game.screenHeight.float32 - margin)
    let toSwarm = (newVector2f(targetX, targetY) - enemy.pos).normalize()
    enemy.pos = enemy.pos + toSwarm * enemy.speed * 1.1 * dt
  
  of "electric_storm":
    # Fast erratic movement
    let angle = game.time * 2.5
    let stormDir = newVector2f(cos(angle + enemy.pos.x * 0.02), sin(angle + enemy.pos.y * 0.02))
    enemy.pos = enemy.pos + stormDir * enemy.speed * dt
  
  of "overcharged":
    # Very fast aggressive movement
    enemy.pos = enemy.pos + toPlayer * enemy.speed * 1.15 * dt
  
  of "deploy_satellites":
    # Drift slowly toward screen center — velocity-based, not instant snap
    let toCenter = (newVector2f(centerX, centerY) - enemy.pos).normalize()
    enemy.pos = enemy.pos + toCenter * enemy.speed * 0.4 * dt
  
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
    enemy.pos = enemy.pos + toPlayer * enemy.speed * 1.05 * dt
  
  of "enraged_assault":
    # Rapid aggressive movement with smooth direction blending (sin-based, no frame dependency)
    # blend = 1 -> full chase, blend = 0 -> full strafe, cycles on a 3s period
    let enrageBlend = sin(game.time * (PI * 2.0 / 3.0)) * 0.5 + 0.5
    let sideDir = newVector2f(-toPlayer.y, toPlayer.x)
    let enrageDir = (toPlayer * enrageBlend + sideDir * (1.0 - enrageBlend)).normalize()
    enemy.pos = enemy.pos + enrageDir * enemy.speed * 1.15 * dt
  
  of "unstoppable":
    # Extremely fast movement toward player
    enemy.pos = enemy.pos + toPlayer * enemy.speed * 1.25 * dt
  
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
    # sin-based blend: aggressive near peak, defensive near trough — 5s period, fps-independent
    let frenzyBlend = sin(game.time * (PI * 2.0 / 5.0)) * 0.5 + 0.5  # 0..1 over 5s
    if frenzyBlend > 0.85:
      # Aggressive burst near the peak of each 5s cycle
      enemy.pos = enemy.pos + toPlayer * enemy.speed * 1.2 * dt
    else:
      # Maintain defensive distance
      if playerDist < 220.0:
        let retreatDir = toPlayer * -1.0
        enemy.pos = enemy.pos + retreatDir * enemy.speed * 0.8 * dt
      else:
        let toCenter = (newVector2f(centerX, centerY) - enemy.pos).normalize()
        enemy.pos = enemy.pos + toCenter * enemy.speed * 0.4 * dt
  
  of "berserk_rampage":
    # Extremely fast aggressive chase with wild movements (Berserker phase 3)
    let berserkerAngle = sin(game.time * 8.0) * 0.6
    let wildDir = newVector2f(
      toPlayer.x * cos(berserkerAngle) - toPlayer.y * sin(berserkerAngle),
      toPlayer.x * sin(berserkerAngle) + toPlayer.y * cos(berserkerAngle)
    )
    enemy.pos = enemy.pos + wildDir * enemy.speed * 1.35 * dt
  
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
    var sweepX = centerX + cos(sweepAngle) * sweepRadius
    var sweepY = centerY + sin(sweepAngle) * sweepRadius
    
    # Clamp within screen boundaries
    let margin = enemy.radius + 10.0
    sweepX = clamp(sweepX, margin, game.screenWidth.float32 - margin)
    sweepY = clamp(sweepY, margin, game.screenHeight.float32 - margin)
    
    # Smooth movement toward sweep target instead of instant position assignment
    let toSweep = (newVector2f(sweepX, sweepY) - enemy.pos).normalize()
    enemy.pos = enemy.pos + toSweep * enemy.speed * 1.3 * dt
  
  of "slow_time":
    # Very slow methodical movement (Timekeeper phase 1)
    enemy.pos = enemy.pos + toPlayer * enemy.speed * 0.4 * dt
  
  of "time_distortion":
    # Stuttering movement with temporal echoes (Timekeeper phase 2)
    # Smooth stutter: move fast during "on" half, freeze during "off" half of each 0.25s cycle
    let distortBlend = sin(game.time * PI * 4.0) * 0.5 + 0.5  # 0..1 at 4Hz, fully continuous
    enemy.pos = enemy.pos + toPlayer * enemy.speed * 1.5 * distortBlend * dt
  
  of "time_collapse":
    # Ultra-fast blinking movement (Timekeeper phase 3)
    # Smooth blend between charge-at-player and strafe on a 0.5s cycle
    let collapseBlend = sin(game.time * PI * 2.0) * 0.5 + 0.5  # 0..1 at 1Hz (0.5s per half)
    let strafeDir = newVector2f(-toPlayer.y, toPlayer.x)
    # High blend -> charge fast, low blend -> strafe
    let chaseContrib = toPlayer * 2.0 * collapseBlend
    let strafeContrib = strafeDir * 1.2 * (1.0 - collapseBlend)
    let collapseDir = (chaseContrib + strafeContrib).normalize()
    enemy.pos = enemy.pos + collapseDir * enemy.speed * dt
  
  of "chaotic_movement":
    # Unpredictable random movement (Chaos Weaver phase 1)
    # Multi-frequency time-based angle — looks chaotic but smooth, no per-frame rand
    let chaosFactor = sin(game.time * 7.0 + enemy.pos.x * 0.03) * 0.8
    let chaosAngle = game.time * 2.1 + sin(game.time * 5.3) * PI * 0.7
    let chaosDir = newVector2f(cos(chaosAngle + chaosFactor), sin(chaosAngle + chaosFactor))
    enemy.pos = enemy.pos + chaosDir * enemy.speed * 0.9 * dt
  
  of "entropy_field":
    # Erratic spiraling with sudden direction changes (Chaos Weaver phase 2)
    # Move toward a spiraling target instead of instant position set
    let entropySpiral = game.time * 3.0 + sin(game.time * 5.0)
    let entropyRadius = 160.0 + sin(game.time * 2.0) * 40.0
    var entropyX = game.player.pos.x + cos(entropySpiral) * entropyRadius
    var entropyY = game.player.pos.y + sin(entropySpiral) * entropyRadius
    
    # Clamp within screen boundaries
    let margin = enemy.radius + 10.0
    entropyX = clamp(entropyX, margin, game.screenWidth.float32 - margin)
    entropyY = clamp(entropyY, margin, game.screenHeight.float32 - margin)
    
    # Smooth movement toward orbit target instead of instant position assignment
    let toEntropy = (newVector2f(entropyX, entropyY) - enemy.pos).normalize()
    enemy.pos = enemy.pos + toEntropy * enemy.speed * 1.1 * dt
  
  of "total_chaos":
    # Maximum chaos - truly unpredictable
    # Time-based trigger (~once every 1.5s) instead of per-frame rand — fps-independent
    let chaosInterval = 1.5 + sin(game.time * 1.1) * 0.6  # 0.9–2.1s varying interval
    if (game.time mod chaosInterval) < dt:
      let chaosAngle = rand(1.0) * PI * 2.0
      let chaosDist = 80.0 + rand(180.0)
      let newX = game.player.pos.x + cos(chaosAngle) * chaosDist
      let newY = game.player.pos.y + sin(chaosAngle) * chaosDist
      
      # Ensure within bounds
      enemy.pos = newVector2f(
        clamp(newX, 50.0, game.screenWidth.float32 - 50.0),
        clamp(newY, 50.0, game.screenHeight.float32 - 50.0)
      )
      
      # Chaotic teleport effect
      spawnExplosionPooled(game.particlePool, enemy.pos.x, enemy.pos.y,
                     Color(r: uint8(255 - rand(100)), g: uint8(rand(255)),
                           b: uint8(255 - rand(100)), a: 255), 25)
    else:
      # Erratic movement with random speed bursts
      let speedMult = 0.8 + rand(0.8)  # 80% to 160% speed
      let wildAngle = game.time * 12.0 + rand(2.0)
      let wildDir = newVector2f(
        cos(wildAngle + sin(game.time * 8.0)),
        sin(wildAngle + cos(game.time * 11.0))
      )
      enemy.pos = enemy.pos + wildDir * enemy.speed * speedMult * dt
  
  of "balanced_assault":
    # Steady circling with balanced approach (Omega Entity phase 1)
    let balanceAngle = game.time * 1.2
    let balanceRadius = 190.0
    let balanceX = centerX + cos(balanceAngle) * balanceRadius
    let balanceY = centerY + sin(balanceAngle) * balanceRadius
    let toBalance = (newVector2f(balanceX, balanceY) - enemy.pos).normalize()
    enemy.pos = enemy.pos + toBalance * enemy.speed * dt
  
  of "aggressive_mixed":
    # Alternating between chase and strafe (Omega Entity phase 2) — sin-based blend, no frame dependency
    # Completes one full chase->strafe cycle every 1.5s
    let mixedBlend = sin(game.time * (PI * 2.0 / 1.5)) * 0.5 + 0.5  # 0..1
    let mixedStrafe = newVector2f(-toPlayer.y, toPlayer.x)
    let mixedDir = (toPlayer * (mixedBlend * 1.2) + mixedStrafe * ((1.0 - mixedBlend) * 0.9)).normalize()
    enemy.pos = enemy.pos + mixedDir * enemy.speed * dt
  
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
      # Dash toward a position near player — time-gated teleport ~once per 0.8s, fps-independent
      let finalTeleportInterval = 0.8 + sin(game.time * 1.7) * 0.2  # 0.6–1.0s
      if (game.time mod finalTeleportInterval) < dt:
        let finalAngle = rand(1.0) * PI * 2.0
        var newX = game.player.pos.x + cos(finalAngle) * 140.0
        var newY = game.player.pos.y + sin(finalAngle) * 140.0
        let margin = enemy.radius + 10.0
        newX = clamp(newX, margin, game.screenWidth.float32 - margin)
        newY = clamp(newY, margin, game.screenHeight.float32 - margin)
        enemy.pos = newVector2f(newX, newY)
      else:
        enemy.pos = enemy.pos + toPlayer * enemy.speed * 1.5 * dt
    of 3, 4:
      # Circle strafe at high speed (smooth velocity-based, not instant position set)
      let finalOrbitAngle = game.time * 2.5  # slowed from 5.0 to avoid jitter
      let finalOrbitRadius = 180.0
      let orbitTarget = newVector2f(
        game.player.pos.x + cos(finalOrbitAngle) * finalOrbitRadius,
        game.player.pos.y + sin(finalOrbitAngle) * finalOrbitRadius
      )
      let toOrbit = (orbitTarget - enemy.pos).normalize()
      enemy.pos = enemy.pos + toOrbit * enemy.speed * 1.2 * dt
    else:
      # Erratic chaos movement
      let chaosAngle = game.time * 8.0 + sin(game.time * 3.0)
      let chaosDir = newVector2f(cos(chaosAngle), sin(chaosAngle))
      enemy.pos = enemy.pos + chaosDir * enemy.speed * 1.5 * dt
  
  of "enraged":
    # Enraged behavior - Extremely aggressive meteor striker behavior (Apocalypse phase)
    # Ultra-fast aggressive pursuit with erratic movement patterns
    let enragedSpeed = enemy.speed * 1.2  # 20% speed boost when enraged
    let enragedAngle = game.time * 4.0 + sin(game.time * 6.0) * 0.8
    
    # Primary movement: Aggressive chase with weaving patterns
    let baseChase = toPlayer * enragedSpeed * dt
    let weaveOffset = newVector2f(
      sin(enragedAngle) * 30.0 * dt,
      cos(enragedAngle * 1.3) * 30.0 * dt
    )
    
    # Combine chase and weave for unpredictable aggressive movement
    enemy.pos = enemy.pos + baseChase + weaveOffset
    
    # Occasional burst movement for added aggression
    if (game.time * 5.0).int mod 7 == 0:
      # Sudden burst toward player
      enemy.pos = enemy.pos + toPlayer * enemy.speed * 0.8 * dt
  
  else:
    discard

proc addBossAttackWarning(game: var Game, enemy: Enemy, attack: BossAttack) =
  ## Emits a short visual pre-fire warning for a boss attack.
  ## Called ~0.4 s before the attack actually fires.
  ## No-ops for types that already manage their own deferred-warning objects.
  const WARNING_DURATION = 0.4'f32

  # These types build their own AttackWarning objects with deferred execution
  if attack.attackType in [bapLaser, bapTeleport, bapMeteor]:
    return

  let warningType = case attack.attackType
    of bapDash:    "boss_dash"
    of bapBurst:   "boss_burst"
    of bapCircle:  "boss_circle"
    of bapSpiral:  "boss_spiral"
    of bapBarrage: "boss_barrage"
    of bapPulse:   "boss_pulse"
    of bapChain:   "boss_chain"
    of bapWave:    "boss_wave"
    of bapSummon:  "boss_summon"
    of bapSnipe:   "laser_pointer"
    else:          return  # bapTargeted, bapOrbit — no pre-warning

  # For dash attacks, targetPos is the actual landing spot (origin + dir × dashDist)
  # so the arrow in the warning covers the true path the boss will travel.
  # All other attacks just lock onto the player's current position.
  let warningTargetPos =
    if attack.attackType == bapDash:
      let toPlayer = game.player.pos - enemy.pos
      let d = sqrt(toPlayer.x * toPlayer.x + toPlayer.y * toPlayer.y)
      let dir = if d > 0.01: newVector2f(toPlayer.x / d, toPlayer.y / d)
                else: newVector2f(1.0'f32, 0.0'f32)
      let dashDist = case attack.specialData
        of "charge_attack": 350.0'f32
        of "double_charge": 300.0'f32
        of "rage_charge":   280.0'f32
        else:               350.0'f32
      newVector2f(enemy.pos.x + dir.x * dashDist, enemy.pos.y + dir.y * dashDist)
    else:
      game.player.pos

  game.attackWarnings.add(AttackWarning(
    pos:                  enemy.pos,
    attackType:           warningType,
    lifetime:             WARNING_DURATION,
    maxLifetime:          WARNING_DURATION,
    sourceEnemyId:        enemy.id,
    laserAngles:          @[],
    targetPos:            warningTargetPos,
    bulletsCreated:       false,
    isBossTeleportTarget: false
  ))

proc executeCustomBossAttack(game: var Game, enemy: Enemy, attack: BossAttack, phase: BossPhaseDefinition, bossDef: BossDefinition) =
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
        fromPlayer = false, isBossBullet = true, sourceEnemyId = enemy.id,
        bossBulletShape = bossBulletShapeFor(enemy.bossDefinitionID),
        bulletRadius = attack.bulletRadius
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
        fromPlayer = false, isBossBullet = true, sourceEnemyId = enemy.id,
        bossBulletShape = bossBulletShapeFor(enemy.bossDefinitionID),
        bulletRadius = attack.bulletRadius
      ))
  
  of bapWave:
    # SpecialData modes:
    # - "rainbow_wave": Colorful cascading pattern (Boss 9)
    # - "temporal_wave": Time-distorted slow bullets (Boss 10)
    # - Default: Standard sine wave pattern
    
    let waveMode = attack.specialData
    
    # Configure wave behavior based on mode
    let (speedMultiplier, colorScheme) = case waveMode
      of "rainbow_wave":
        (1.0, "rainbow")  # Normal speed, rainbow particles
      of "temporal_wave":
        (0.7, "temporal")  # 30% slower, cyan particles
      else:
        (1.0, "default")  # Standard
    
    for i in 0..<attack.projectileCount:
      let t = i.float32 / attack.projectileCount.float32
      let angle = t * attack.spreadAngle.degToRad() - attack.spreadAngle.degToRad() / 2.0 + arctan2(toPlayer.y, toPlayer.x)
      let dir = newVector2f(cos(angle), sin(angle))
      
      let bulletSpeed = attack.projectileSpeed * speedMultiplier
      
      game.bullets.add(newBullet(
        x = enemy.pos.x, y = enemy.pos.y, direction = dir,
        speed = bulletSpeed, damage = attack.damage * phase.damageMultiplier,
        fromPlayer = false, isBossBullet = true, sourceEnemyId = enemy.id,
        bossBulletShape = bossBulletShapeFor(enemy.bossDefinitionID),
        bulletRadius = attack.bulletRadius
      ))
      
      # Special visual effects per wave type
      case colorScheme
      of "rainbow":
        # Create rainbow trail particles
        let rainbowColor = case i mod 7
          of 0: Color(r: 255, g: 0, b: 0, a: 255)     # Red
          of 1: Color(r: 255, g: 127, b: 0, a: 255)   # Orange
          of 2: Color(r: 255, g: 255, b: 0, a: 255)   # Yellow
          of 3: Color(r: 0, g: 255, b: 0, a: 255)     # Green
          of 4: Color(r: 0, g: 0, b: 255, a: 255)     # Blue
          of 5: Color(r: 75, g: 0, b: 130, a: 255)    # Indigo
          else: Color(r: 148, g: 0, b: 211, a: 255)   # Violet
        spawnExplosionPooled(game.particlePool, enemy.pos.x, enemy.pos.y, rainbowColor, 4)
      of "temporal":
        # Cyan time-distortion particles
        spawnExplosionPooled(game.particlePool, enemy.pos.x, enemy.pos.y,
                      Color(r: 100, g: 220, b: 220, a: 255), 3)
      else:
        discard
  
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
        fromPlayer = false, isBossBullet = true, sourceEnemyId = enemy.id,
        bossBulletShape = bossBulletShapeFor(enemy.bossDefinitionID),
        bulletRadius = attack.bulletRadius
      ))
  
  of bapCircle:
    # Perfect ring of bullets with thematic variants
    # SpecialData modes:
    # - "time_ring": Temporal distortion ring with pulsing cyan bullets (Boss 10)
    # - Default: Standard perfect circle
    
    let circleMode = attack.specialData
    
    # Configure circle behavior based on mode
    let (bulletSpeed, particleColor, rotationOffset) = case circleMode
      of "time_ring":
        (attack.projectileSpeed * 0.85, Color(r: 100, g: 220, b: 220, a: 255), game.time * 0.5)  # Slower temporal bullets with rotation
      else:
        (attack.projectileSpeed, phase.color, 0.0)  # Standard
    
    # Create pre-fire visual effect for time_ring
    if circleMode == "time_ring":
      # Create temporal distortion rings before firing
      for ring in 0..2:
        let ringRadius = 30.0 + ring.float32 * 25.0
        for i in 0..<16:
          let angle = i.float32 * PI * 2.0 / 16.0
          let ringX = enemy.pos.x + cos(angle) * ringRadius
          let ringY = enemy.pos.y + sin(angle) * ringRadius
          spawnExplosionPooled(game.particlePool, ringX, ringY,
                        Color(r: 100, g: 220, b: 220, a: 255), 3)
    
    # Create circle of bullets
    for i in 0..<attack.projectileCount:
      let angle = i.float32 * PI * 2.0 / attack.projectileCount.float32 + rotationOffset
      let dir = newVector2f(cos(angle), sin(angle))
      game.bullets.add(newBullet(
        x = enemy.pos.x, y = enemy.pos.y, direction = dir,
        speed = bulletSpeed, damage = attack.damage * phase.damageMultiplier,
        fromPlayer = false, isBossBullet = true, sourceEnemyId = enemy.id,
        bossBulletShape = bossBulletShapeFor(enemy.bossDefinitionID),
        bulletRadius = attack.bulletRadius
      ))
      
      # Add temporal particle trail for time_ring
      if circleMode == "time_ring":
        let trailRadius = 20.0
        let trailX = enemy.pos.x + cos(angle) * trailRadius
        let trailY = enemy.pos.y + sin(angle) * trailRadius
        spawnExplosionPooled(game.particlePool, trailX, trailY, particleColor, 2)
  
  of bapLaser:
    # Boss laser with proper warning system
    # Laser patterns customized via specialData
    # EXISTING: "cross_laser", "rotating_grid", "prismatic_cage", "laser_snipe"
    
    let patternType = attack.specialData
    let laserCount = case patternType
      of "rotating_grid": attack.projectileCount * 2  # Double density for grid
      of "prismatic_cage": attack.projectileCount * 3  # Triple density for cage
      of "splitting_laser": attack.projectileCount  # Triangle pattern
      of "hexagonal_prism": 6  # Always 6 beams
      of "prismatic_storm": attack.projectileCount * 2  # Massive light show!
      of "temporal_beam": attack.projectileCount  # Temporal cross pattern
      of "chaos_beam": rand(attack.projectileCount) + attack.projectileCount  # Random chaos
      of "omega_beam": attack.projectileCount * 2  # Massive ultimate beams
      else: attack.projectileCount
    
    # Calculate all laser angles for the warning system
    var warningAngles: seq[float32] = @[]
    
    # For cross_laser pattern, always create 4 beams (cardinal directions)
    let actualLaserCount = if patternType == "cross_laser": 4 else: laserCount
    
    for i in 0..<actualLaserCount:
      let angle = case patternType
        of "rotating_grid":
          # Grid pattern - two perpendicular sets
          if i.float < actualLaserCount / 2:
            i.float32 * attack.spreadAngle.degToRad() / (actualLaserCount / 2).float32
          else:
            (i.float32 - actualLaserCount.float / 2.0) * attack.spreadAngle.degToRad() / (actualLaserCount / 2).float32 + PI / 2.0
        
        of "splitting_laser":
          # Triangle pattern (120° apart) that appears to split/refract
          i.float32 * (PI * 2.0 / 3.0) + game.time * 0.5  # Slow rotation
        
        of "hexagonal_prism":
          # Perfect hexagonal pattern (60° apart) - geometric precision
          i.float32 * (PI / 3.0) + game.time * 0.3
        
        of "prismatic_storm":
          # Massive radial array with rainbow effect
          # Create dense radial pattern with slight randomization for light scatter
          let baseAngle = i.float32 * (PI * 2.0) / actualLaserCount.float32
          baseAngle + (rand(1.0) - 0.5) * 0.15  # Slight scatter for prismatic effect
        
        of "prismatic_cage":
          # Calculate angle biased toward player with radial spread
          let angleToPlayer = arctan2(game.player.pos.y - enemy.pos.y,
                                       game.player.pos.x - enemy.pos.x)
          
          # Create proper radial pattern with player bias
          let segmentAngle = (PI * 2.0) / actualLaserCount.float32
          let baseAngle = i.float32 * segmentAngle
          
          # 40% of lasers aim near player, 60% are radial
          if rand(100) < 40:
            # Aim toward player with spread
            angleToPlayer + (rand(1.0) - 0.5) * (PI / 3.0)  # ±60° spread
          else:
            # Radial distribution with slight randomization
            baseAngle + (rand(1.0) - 0.5) * 0.2  # ±6° randomization
        
        of "laser_snipe":
          # Rapid fire lasers aimed directly at player with minimal spread
          let angleToPlayer = arctan2(game.player.pos.y - enemy.pos.y, game.player.pos.x - enemy.pos.x)
          # Very tight spread around player position (5 degrees)
          angleToPlayer + (rand(1.0) - 0.5) * 0.175
        
        of "cross_laser":
          # Cross pattern - always 4 beams in cardinal directions (0°, 90°, 180°, 270°)
          i.float32 * (PI / 2.0) + game.time
        
        of "temporal_beam":
          # TEMPORAL BEAM - Time-distorted cross pattern with slow rotation
          # Creates 4 beams in rotating cardinal directions
          # Beams have temporal distortion effect (stuttering, phasing)
          i.float32 * (PI / 2.0) + game.time * 0.4  # Slower rotation for time effect
        
        of "chaos_beam":
          # CHAOS BEAM - Completely unpredictable laser angles with clustering
          # Create random cluster center for grouped chaos
          let clusterCenter = if i == 0: rand(PI * 2.0) else: warningAngles[0] + rand(0.5)
          let clusterSpread = 0.3 + rand(0.7)  # Variable clustering (0.3-1.0 radians)
          # Random angle with slight clustering around center for chaotic but not totally random
          clusterCenter + (rand(1.0) - 0.5) * clusterSpread
        
        of "omega_beam":
          # OMEGA BEAM - Ultimate laser pattern combining ALL previous mechanics
          # Three different sub-patterns: radial, player-tracking, and temporal spiral
          
          # Pattern 1: Rotating radial beams (Boss 4 style) - first third of lasers
          if i < actualLaserCount div 3:
            i.float32 * (PI * 2.0) / (actualLaserCount div 3).float32 + game.time * 0.8
          
          # Pattern 2: Player-tracking spread (Boss 9 style) - middle third
          elif i < (actualLaserCount * 2) div 3:
            let idx = i - (actualLaserCount div 3)
            let angleToPlayer = arctan2(game.player.pos.y - enemy.pos.y,
                                         game.player.pos.x - enemy.pos.x)
            let spread = (idx.float32 - (actualLaserCount div 3).float32 / 2.0) * 0.3
            angleToPlayer + spread
          
          # Pattern 3: Temporal spiraling beams (Boss 10 style) - last third
          else:
            let idx = i - (actualLaserCount * 2) div 3
            let spiral = idx.float32 * 0.5 + game.time * 0.6
            spiral + sin(game.time * 2.0) * 0.4  # Wavy temporal distortion
        
        else:
          # Default pattern - distribute evenly
          i.float32 * (PI * 2.0) / actualLaserCount.float32 + game.time
      warningAngles.add(angle)
    
    # Add boss laser warning with proper visual indicators
    # WARNING: Show for 1.2 seconds before firing (much longer than current 0.3s)
    const BOSS_LASER_WARNING_TIME = 1.2
    let laserDamage = (attack.damage * phase.damageMultiplier).int
    
    # PRE-FIRE VISUAL EFFECTS for special laser patterns
    if patternType == "chaos_beam":
      # Create flickering chaotic particles along laser paths
      for angle in warningAngles:
        for step in 1..8:
          let dist = step.float32 * 40.0
          let px = enemy.pos.x + cos(angle) * dist
          let py = enemy.pos.y + sin(angle) * dist
          # Flickering random colors for chaos
          let chaosColor = Color(
            r: (100 + rand(155)).uint8,
            g: (50 + rand(205)).uint8,
            b: (100 + rand(155)).uint8,
            a: 255
          )
          spawnExplosionPooled(game.particlePool, px, py, chaosColor, 3)
    
    elif patternType == "omega_beam":
      # MASSIVE rainbow particle explosion for ultimate laser
      for ring in 0..6:
        let ringRadius = 30.0 + ring.float32 * 28.0
        for i in 0..<24:
          let angle = i.float32 * PI * 2.0 / 24.0
          let px = enemy.pos.x + cos(angle) * ringRadius
          let py = enemy.pos.y + sin(angle) * ringRadius
          # Rainbow spectrum
          let rainbowColor = case i mod 7:
            of 0: Color(r: 255, g: 0, b: 0, a: 255)
            of 1: Color(r: 255, g: 127, b: 0, a: 255)
            of 2: Color(r: 255, g: 255, b: 0, a: 255)
            of 3: Color(r: 0, g: 255, b: 0, a: 255)
            of 4: Color(r: 0, g: 255, b: 255, a: 255)
            of 5: Color(r: 0, g: 0, b: 255, a: 255)
            else: Color(r: 255, g: 0, b: 255, a: 255)
          spawnExplosionPooled(game.particlePool, px, py, rainbowColor, 7)
      
      # Add electric arcs (Boss 6 style)
      for i in 0..<20:
        let angle = i.float32 * PI * 2.0 / 20.0
        let arcX = enemy.pos.x + cos(angle) * 70.0
        let arcY = enemy.pos.y + sin(angle) * 70.0
        spawnExplosionPooled(game.particlePool, arcX, arcY,
                      Color(r: 255, g: 255, b: 200, a: 255), 6)
    
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
    
  of bapBarrage:
    # Massive bullet spray with multiple themes
    # SpecialData modes:
    # - "voltage_burst": Electric explosion with yellow bullets (Boss 6)
    # - "blood_burst": Berserker rage explosion with red bullets (Boss 8)
    # - "orbital_bombardment": Space bombardment from above (Boss 7)
    # - "random_spread": Chaotic spread with random angles (Boss 11 Phase 1)
    # - "chaos_storm", "entropy_burst": Randomized chaos attacks (Boss 11)
    # - "chromatic_burst": Rainbow prismatic explosion (Boss 9 Phase 2)
    # - "light_burst": Pure brilliance explosion (Boss 9 Phase 3)
    # - "time_shatter": Reality-shattering temporal explosion (Boss 10 Phase 3)
    # - "omega_barrage": Ultimate massive barrage from final boss (Boss 12 Phase 4)
    
    let barrageMode = attack.specialData
    let isChaosAttack = barrageMode in ["chaos_storm", "entropy_burst", "random_spread"]
    let isElectricAttack = barrageMode == "voltage_burst"
    let isBerserkAttack = barrageMode == "blood_burst"
    let isOrbitalAttack = barrageMode == "orbital_bombardment"
    let isChromaticAttack = barrageMode == "chromatic_burst"
    let isLightAttack = barrageMode == "light_burst"
    let isTimeShatter = barrageMode == "time_shatter"
    let isOmegaBarrage = barrageMode == "omega_barrage"
    
    # Randomize count ±30% for chaos
    let bulletCount = if isChaosAttack:
      (attack.projectileCount.float32 * (0.7 + rand(0.6))).int
    elif isOmegaBarrage:
      attack.projectileCount * 2  # Double bullets for ultimate attack
    else:
      attack.projectileCount
    
    # Randomize spread for chaos
    let spreadAngle = if isChaosAttack:
      180.0 + rand(180.0)  # Might not even be 360!
    else:
      360.0
    
    # MODE-SPECIFIC PRE-EXPLOSION EFFECTS
    if isElectricAttack:
      # Create electric sparks radiating outward
      for i in 0..<bulletCount div 2:
        let angle = i.float32 * PI * 2.0 / (bulletCount div 2).float32
        let sparkX = enemy.pos.x + cos(angle) * 40.0
        let sparkY = enemy.pos.y + sin(angle) * 40.0
        spawnExplosionPooled(game.particlePool, sparkX, sparkY,
                      Color(r: 255, g: 255, b: 100, a: 255), 4)
    
    elif isBerserkAttack:
      # Create blood/rage particles in circular waves
      for ring in 0..2:
        let ringRadius = 35.0 + ring.float32 * 25.0
        for i in 0..<12:
          let angle = i.float32 * PI * 2.0 / 12.0
          let bloodX = enemy.pos.x + cos(angle) * ringRadius
          let bloodY = enemy.pos.y + sin(angle) * ringRadius
          spawnExplosionPooled(game.particlePool, bloodX, bloodY,
                        Color(r: 200 + rand(55).uint8, g: 0, b: 0, a: 255), 5)
      
      # Screen shake for rage
      addShake(game.dopamine.screenShake, siLarge)
    
    elif isOrbitalAttack:
      # Create star field effect - bullets rain from space
      for i in 0..<8:
        let angle = i.float32 * PI * 2.0 / 8.0
        let starX = enemy.pos.x + cos(angle) * 60.0
        let starY = enemy.pos.y + sin(angle) * 60.0
        spawnExplosionPooled(game.particlePool, starX, starY,
                      Color(r: 200, g: 150, b: 255, a: 255), 6)
    
    elif isChromaticAttack:
      # Create rainbow prismatic rings expanding outward
      for ring in 0..3:
        let ringRadius = 30.0 + ring.float32 * 20.0
        for i in 0..<12:
          let angle = i.float32 * PI * 2.0 / 12.0
          let prismX = enemy.pos.x + cos(angle) * ringRadius
          let prismY = enemy.pos.y + sin(angle) * ringRadius
          # Rainbow colors based on position
          let rainbowColor = case i mod 7
            of 0: Color(r: 255, g: 0, b: 0, a: 255)     # Red
            of 1: Color(r: 255, g: 127, b: 0, a: 255)   # Orange
            of 2: Color(r: 255, g: 255, b: 0, a: 255)   # Yellow
            of 3: Color(r: 0, g: 255, b: 0, a: 255)     # Green
            of 4: Color(r: 0, g: 0, b: 255, a: 255)     # Blue
            of 5: Color(r: 75, g: 0, b: 130, a: 255)    # Indigo
            else: Color(r: 148, g: 0, b: 211, a: 255)   # Violet
          spawnExplosionPooled(game.particlePool, prismX, prismY, rainbowColor, 5)
    
    elif isLightAttack:
      # Create brilliant white/rainbow light explosion
      for ring in 0..4:
        let ringRadius = 25.0 + ring.float32 * 18.0
        for i in 0..<16:
          let angle = i.float32 * PI * 2.0 / 16.0
          let lightX = enemy.pos.x + cos(angle) * ringRadius
          let lightY = enemy.pos.y + sin(angle) * ringRadius
          # Brilliant white with rainbow tint
          let tint = case (i + ring) mod 7
            of 0: Color(r: 255, g: 200, b: 200, a: 255)
            of 1: Color(r: 255, g: 230, b: 200, a: 255)
            of 2: Color(r: 255, g: 255, b: 200, a: 255)
            of 3: Color(r: 200, g: 255, b: 200, a: 255)
            of 4: Color(r: 200, g: 230, b: 255, a: 255)
            of 5: Color(r: 230, g: 200, b: 255, a: 255)
            else: Color(r: 255, g: 255, b: 255, a: 255)  # Pure white
          spawnExplosionPooled(game.particlePool, lightX, lightY, tint, 6)
      
      # Intense screen shake for brilliance
      addShake(game.dopamine.screenShake, siLarge)
    
    elif isTimeShatter:
      # TIME SHATTER - Reality-breaking temporal fracture explosion
      # Create massive expanding temporal cracks radiating outward
      for ring in 0..6:
        let ringRadius = 20.0 + ring.float32 * 25.0
        for i in 0..<20:
          let angle = i.float32 * PI * 2.0 / 20.0
          let shatterX = enemy.pos.x + cos(angle) * ringRadius
          let shatterY = enemy.pos.y + sin(angle) * ringRadius
          # Bright cyan-white temporal fracture particles
          let brightness = 100 + (ring * 20)
          spawnExplosionPooled(game.particlePool, shatterX, shatterY,
                        Color(r: brightness.uint8, g: 220 + (ring * 5).uint8, b: 220 + (ring * 5).uint8, a: 255), 5)
      
      # Create radiating time crack lines extending far outward
      for i in 0..<16:
        let angle = i.float32 * PI * 2.0 / 16.0
        for step in 1..20:
          let crackRadius = step.float32 * 20.0
          let crackX = enemy.pos.x + cos(angle) * crackRadius
          let crackY = enemy.pos.y + sin(angle) * crackRadius
          # Cyan temporal cracks with fading intensity
          let fade = (255 - step * 8).clamp(100, 255)
          spawnExplosionPooled(game.particlePool, crackX, crackY,
                        Color(r: 100, g: 220, b: 220, a: fade.uint8), 3)
      
      # Add swirling temporal distortion particles
      for spiral in 0..<8:
        for step in 0..15:
          let spiralAngle = (spiral.float32 * PI / 4.0) + (step.float32 * 0.3)
          let spiralRadius = step.float32 * 12.0
          let spiralX = enemy.pos.x + cos(spiralAngle) * spiralRadius
          let spiralY = enemy.pos.y + sin(spiralAngle) * spiralRadius
          spawnExplosionPooled(game.particlePool, spiralX, spiralY,
                        Color(r: 150, g: 255, b: 255, a: 255), 2)
      
      # MASSIVE screen shake for reality-shattering effect
      addShake(game.dopamine.screenShake, siMassive)
    
    elif barrageMode == "omega_barrage":
      # OMEGA BARRAGE - Ultimate final boss attack combining all elements
      # Creates massive multi-colored explosion with all previous boss themes
      # Rainbow prismatic rings (like Boss 9)
      for ring in 0..5:
        let ringRadius = 25.0 + ring.float32 * 30.0
        for i in 0..<18:
          let angle = i.float32 * PI * 2.0 / 18.0
          let omegaX = enemy.pos.x + cos(angle) * ringRadius
          let omegaY = enemy.pos.y + sin(angle) * ringRadius
          # Rainbow colors cycling through spectrum
          let rainbowColor = case i mod 7
            of 0: Color(r: 255, g: 0, b: 0, a: 255)     # Red
            of 1: Color(r: 255, g: 127, b: 0, a: 255)   # Orange
            of 2: Color(r: 255, g: 255, b: 0, a: 255)   # Yellow
            of 3: Color(r: 0, g: 255, b: 0, a: 255)     # Green
            of 4: Color(r: 0, g: 255, b: 255, a: 255)   # Cyan
            of 5: Color(r: 0, g: 0, b: 255, a: 255)     # Blue
            else: Color(r: 255, g: 0, b: 255, a: 255)   # Magenta
          spawnExplosionPooled(game.particlePool, omegaX, omegaY, rainbowColor, 6)
      
      # Electric crackling effects (like Boss 6)
      for i in 0..<bulletCount div 3:
        let angle = i.float32 * PI * 2.0 / (bulletCount div 3).float32
        let sparkX = enemy.pos.x + cos(angle) * 55.0
        let sparkY = enemy.pos.y + sin(angle) * 55.0
        spawnExplosionPooled(game.particlePool, sparkX, sparkY,
                      Color(r: 255, g: 255, b: 100, a: 255), 5)
      
      # Temporal rifts (like Boss 10)
      for i in 0..<12:
        let angle = i.float32 * PI * 2.0 / 12.0
        for step in 1..12:
          let riftRadius = step.float32 * 22.0
          let riftX = enemy.pos.x + cos(angle) * riftRadius
          let riftY = enemy.pos.y + sin(angle) * riftRadius
          spawnExplosionPooled(game.particlePool, riftX, riftY,
                        Color(r: 150, g: 255, b: 255, a: 255), 3)
      
      # ABSOLUTELY MASSIVE screen shake - this is the ultimate attack
      addShake(game.dopamine.screenShake, siMassive)
    
    for i in 0..<bulletCount:
      let angle = if isChaosAttack:
        (i.float32 / bulletCount.float32) * spreadAngle.degToRad() + rand(1.0)
      else:
        i.float32 * PI * 2.0 / bulletCount.float32
      
      let dir = newVector2f(cos(angle), sin(angle))
      
      # Randomize speed ±25% for chaos
      let speed = if isChaosAttack:
        attack.projectileSpeed * (0.75 + rand(0.5))
      else:
        attack.projectileSpeed
      
      # Randomize damage ±10% for chaos
      let damage = if isChaosAttack:
        attack.damage * phase.damageMultiplier * (0.9 + rand(0.2))
      else:
        attack.damage * phase.damageMultiplier
      
      game.bullets.add(newBullet(
        x = enemy.pos.x, y = enemy.pos.y, direction = dir,
        speed = speed, damage = damage,
        fromPlayer = false, isBossBullet = true, sourceEnemyId = enemy.id,
        bossBulletShape = bossBulletShapeFor(enemy.bossDefinitionID),
        bulletRadius = attack.bulletRadius
      ))
    
    # MODE-SPECIFIC EXPLOSIONS
    let (explosionSize, explosionColor) = case barrageMode
      of "voltage_burst":
        (45, Color(r: 255, g: 255, b: 200, a: 255))  # Bright yellow electric
      of "blood_burst":
        (50, Color(r: 255, g: 0, b: 0, a: 255))  # Massive red rage explosion
      of "orbital_bombardment":
        (40, Color(r: 180, g: 120, b: 255, a: 255))  # Purple space explosion
      of "chromatic_burst":
        (42, Color(r: 255, g: 150, b: 255, a: 255))  # Pink/magenta prismatic
      of "light_burst":
        (55, Color(r: 255, g: 255, b: 255, a: 255))  # Massive white brilliance
      of "time_shatter":
        (65, Color(r: 150, g: 255, b: 255, a: 255))  # Massive cyan temporal shatter
      of "random_spread":
        (32, Color(r: rand(200).uint8 + 55, g: rand(200).uint8 + 55, b: rand(200).uint8 + 55, a: 255))  # Random bright chaos
      of "chaos_storm", "entropy_burst":
        (35, Color(r: rand(255).uint8, g: rand(255).uint8, b: rand(255).uint8, a: 255))  # Random chaos
      of "omega_barrage":
        (70, Color(r: 255, g: 50, b: 255, a: 255))  # MASSIVE pink/magenta final boss explosion
      else:
        (30, phase.color)  # Standard
    
    spawnExplosionPooled(game.particlePool, enemy.pos.x, enemy.pos.y, explosionColor, explosionSize)
  
  of bapPulse:
    # Expanding ring with multiple thematic variants
    # SpecialData modes:
    # - "electric_discharge": Electric shockwave with crackling particles (Boss 6)
    # - "ground_slam": Berserker impact with rocks/debris (Boss 8 Phase 2)
    # - "earthquake": MASSIVE berserker slam, screen shake, cracks (Boss 8 Phase 3)
    # - "overload_pulse": Intense electric overload (Boss 6 Phase 3)
    # - "gravity_pulse": Space-themed gravity wave (Boss 7)
    # - "blinding_pulse": Brilliant light explosion (Boss 9 Phase 3)
    # - "entropy_wave": Chaotic unstable shockwave (Boss 11 Phase 3)
    # - "omega_pulse": Ultimate combined shockwave (Boss 12 Phase 4)
    # - Default: Standard pulse
    
    let pulseMode = attack.specialData
    
    # Configure pulse behavior and visuals based on mode
    let (bulletCount, particleColor, explosionSize) = case pulseMode
      of "electric_discharge":
        (32, Color(r: 255, g: 255, b: 150, a: 255), 35)  # Dense electric pulse
      of "ground_slam":
        (28, Color(r: 150, g: 75, b: 30, a: 255), 40)  # Fewer but stronger, brown/rock color
      of "earthquake":
        (36, Color(r: 100, g: 50, b: 20, a: 255), 60)  # MASSIVE slam, huge shake
      of "overload_pulse":
        (40, Color(r: 255, g: 255, b: 255, a: 255), 50)  # Maximum density, white overload
      of "gravity_pulse":
        (30, Color(r: 150, g: 100, b: 255, a: 255), 45)  # Space purple
      of "blinding_pulse":
        (38, Color(r: 255, g: 255, b: 255, a: 255), 55)  # Brilliant white light explosion
      of "chrono_pulse":
        (28, Color(r: 100, g: 220, b: 220, a: 255), 42)  # Temporal shockwave, cyan
      of "chrono_break":
        (36, Color(r: 150, g: 255, b: 255, a: 255), 58)  # Massive time shattering pulse
      of "entropy_wave":
        (rand(20) + 20, Color(r: rand(255).uint8, g: rand(255).uint8, b: rand(255).uint8, a: 255), 50)  # Chaotic random pulse
      of "omega_pulse":
        (42, Color(r: 255, g: 100, b: 255, a: 255), 65)  # ULTIMATE pulse - huge and powerful
      else:
        (24, phase.color, 35)  # Standard pulse
    
    # TRIGGER SCREEN SHAKE
    addShake(game.dopamine.screenShake, siLarge)
    
    # Create expanding pulse ring
    for i in 0..<bulletCount:
      let angle = i.float32 * PI * 2.0 / bulletCount.float32
      let dir = newVector2f(cos(angle), sin(angle))
      game.bullets.add(newBullet(
        x = enemy.pos.x, y = enemy.pos.y, direction = dir,
        speed = attack.projectileSpeed, damage = attack.damage * phase.damageMultiplier,
        fromPlayer = false, isBossBullet = true, sourceEnemyId = enemy.id,
        bossBulletShape = bossBulletShapeFor(enemy.bossDefinitionID),
        bulletRadius = attack.bulletRadius
      ))
    
    # MODE-SPECIFIC VISUAL ENHANCEMENTS
    case pulseMode:
      of "electric_discharge", "overload_pulse":
        # Create multiple expanding particle rings
        let ringCount = if pulseMode == "overload_pulse": 4 else: 3
        for ring in 0..<ringCount:
          let ringRadius = 30.0 + ring.float32 * 25.0
          for i in 0..<16:
            let angle = i.float32 * PI * 2.0 / 16.0
            let sparkX = enemy.pos.x + cos(angle) * ringRadius
            let sparkY = enemy.pos.y + sin(angle) * ringRadius
            spawnExplosionPooled(game.particlePool, sparkX, sparkY,
                          Color(r: 255, g: 255, b: 200, a: 255), 3)
      
      of "ground_slam", "earthquake":
        # Create rock/debris particles flying outward
        let debrisCount = if pulseMode == "earthquake": 32 else: 20
        for i in 0..<debrisCount:
          let angle = i.float32 * PI * 2.0 / debrisCount.float32
          let debrisRadius = 40.0 + rand(60.0)
          let debrisX = enemy.pos.x + cos(angle) * debrisRadius
          let debrisY = enemy.pos.y + sin(angle) * debrisRadius
          # Brown/orange debris colors
          spawnExplosionPooled(game.particlePool, debrisX, debrisY,
                        Color(r: 120 + rand(80).uint8, g: 60 + rand(40).uint8, b: 20, a: 255), 4)
        
        # Earthquake gets GROUND CRACKS (radial lines)
        if pulseMode == "earthquake":
          for i in 0..<8:
            let angle = i.float32 * PI * 2.0 / 8.0
            for step in 1..10:
              let crackRadius = step.float32 * 15.0
              let crackX = enemy.pos.x + cos(angle) * crackRadius
              let crackY = enemy.pos.y + sin(angle) * crackRadius
              spawnExplosionPooled(game.particlePool, crackX, crackY,
                            Color(r: 80, g: 40, b: 10, a: 255), 2)
      
      of "gravity_pulse":
        # Space-themed spiral particles
        for ring in 0..3:
          let ringRadius = 35.0 + ring.float32 * 30.0
          for i in 0..<12:
            let angle = i.float32 * PI * 2.0 / 12.0 + ring.float32 * 0.3  # Spiral offset
            let gravX = enemy.pos.x + cos(angle) * ringRadius
            let gravY = enemy.pos.y + sin(angle) * ringRadius
            spawnExplosionPooled(game.particlePool, gravX, gravY,
                          Color(r: 150, g: 100, b: 255, a: 255), 3)
      
      of "blinding_pulse":
        # Brilliant prismatic light explosion with rainbow rings
        for ring in 0..5:
          let ringRadius = 30.0 + ring.float32 * 25.0
          for i in 0..<20:
            let angle = i.float32 * PI * 2.0 / 20.0
            let lightX = enemy.pos.x + cos(angle) * ringRadius
            let lightY = enemy.pos.y + sin(angle) * ringRadius
            # Rainbow prismatic effect
            let lightColor = case (i + ring) mod 7
              of 0: Color(r: 255, g: 200, b: 200, a: 255)
              of 1: Color(r: 255, g: 230, b: 200, a: 255)
              of 2: Color(r: 255, g: 255, b: 200, a: 255)
              of 3: Color(r: 200, g: 255, b: 200, a: 255)
              of 4: Color(r: 200, g: 230, b: 255, a: 255)
              of 5: Color(r: 230, g: 200, b: 255, a: 255)
              else: Color(r: 255, g: 255, b: 255, a: 255)
            spawnExplosionPooled(game.particlePool, lightX, lightY, lightColor, 4)
      
      of "chrono_pulse":
        # Temporal distortion waves - expanding time rings
        for ring in 0..3:
          let ringRadius = 35.0 + ring.float32 * 28.0
          for i in 0..<14:
            let angle = i.float32 * PI * 2.0 / 14.0
            let timeX = enemy.pos.x + cos(angle) * ringRadius
            let timeY = enemy.pos.y + sin(angle) * ringRadius
            # Cyan/turquoise temporal particles with brightness variation
            let brightness = 100 + (ring * 35)
            spawnExplosionPooled(game.particlePool, timeX, timeY,
                          Color(r: brightness.uint8, g: 220, b: 220, a: 255), 3)
      
      of "chrono_break":
        # MASSIVE reality-breaking time shatter effect
        # Create multiple layers of temporal fractures
        for ring in 0..5:
          let ringRadius = 30.0 + ring.float32 * 30.0
          for i in 0..<18:
            let angle = i.float32 * PI * 2.0 / 18.0
            let shatterX = enemy.pos.x + cos(angle) * ringRadius
            let shatterY = enemy.pos.y + sin(angle) * ringRadius
            # Bright cyan-white time shatter particles
            spawnExplosionPooled(game.particlePool, shatterX, shatterY,
                          Color(r: 150, g: 255, b: 255, a: 255), 5)
        
        # Add radial time cracks extending outward
        for i in 0..<12:
          let angle = i.float32 * PI * 2.0 / 12.0
          for step in 1..15:
            let crackRadius = step.float32 * 18.0
            let crackX = enemy.pos.x + cos(angle) * crackRadius
            let crackY = enemy.pos.y + sin(angle) * crackRadius
            spawnExplosionPooled(game.particlePool, crackX, crackY,
                          Color(r: 100, g: 220, b: 220, a: 255), 2)
      
      of "entropy_wave":
        # ENTROPY WAVE - Chaotic unstable shockwave with randomized effects
        # Create multiple chaotic spiral patterns with random colors
        for spiral in 0..<rand(4) + 3:  # 3-6 spirals
          for ring in 0..rand(5) + 3:  # Variable rings per spiral
            let ringRadius = 25.0 + ring.float32 * (20.0 + rand(15.0))
            let spiralAngle = (spiral.float32 * PI * 2.0 / (spiral + 3).float32) + rand(PI)
            for i in 0..<rand(8) + 8:  # Variable particle count
              let angle = i.float32 * PI * 2.0 / (i + 8).float32 + spiralAngle
              let chaosX = enemy.pos.x + cos(angle) * ringRadius
              let chaosY = enemy.pos.y + sin(angle) * ringRadius
              # Completely random colors for pure chaos
              let chaosColor = Color(
                r: rand(200).uint8 + 55,
                g: rand(200).uint8 + 55,
                b: rand(200).uint8 + 55,
                a: 255
              )
              spawnExplosionPooled(game.particlePool, chaosX, chaosY, chaosColor, rand(5) + 2)
        
        # Add random crackling effects
        for i in 0..<rand(15) + 10:
          let randomAngle = rand(PI * 2.0)
          let randomRadius = rand(120.0) + 30.0
          let crackX = enemy.pos.x + cos(randomAngle) * randomRadius
          let crackY = enemy.pos.y + sin(randomAngle) * randomRadius
          spawnExplosionPooled(game.particlePool, crackX, crackY,
                        Color(r: rand(255).uint8, g: rand(255).uint8, b: rand(255).uint8, a: 255), 4)
      
      of "omega_pulse":
        # OMEGA PULSE - Ultimate shockwave combining all boss themes
        # Rainbow prismatic rings (like Boss 9)
        for ring in 0..6:
          let ringRadius = 30.0 + ring.float32 * 32.0
          for i in 0..<20:
            let angle = i.float32 * PI * 2.0 / 20.0
            let omegaX = enemy.pos.x + cos(angle) * ringRadius
            let omegaY = enemy.pos.y + sin(angle) * ringRadius
            # Rainbow spectrum
            let rainbowColor = case i mod 7
              of 0: Color(r: 255, g: 0, b: 0, a: 255)     # Red
              of 1: Color(r: 255, g: 127, b: 0, a: 255)   # Orange
              of 2: Color(r: 255, g: 255, b: 0, a: 255)   # Yellow
              of 3: Color(r: 0, g: 255, b: 0, a: 255)     # Green
              of 4: Color(r: 0, g: 255, b: 255, a: 255)   # Cyan
              of 5: Color(r: 0, g: 0, b: 255, a: 255)     # Blue
              else: Color(r: 255, g: 0, b: 255, a: 255)   # Magenta
            spawnExplosionPooled(game.particlePool, omegaX, omegaY, rainbowColor, 6)
        
        # Electric crackling (like Boss 6)
        for i in 0..<16:
          let angle = i.float32 * PI * 2.0 / 16.0
          let sparkX = enemy.pos.x + cos(angle) * 65.0
          let sparkY = enemy.pos.y + sin(angle) * 65.0
          spawnExplosionPooled(game.particlePool, sparkX, sparkY,
                        Color(r: 255, g: 255, b: 150, a: 255), 5)
        
        # Temporal rifts (like Boss 10)
        for i in 0..<14:
          let angle = i.float32 * PI * 2.0 / 14.0
          for step in 1..18:
            let riftRadius = step.float32 * 20.0
            let riftX = enemy.pos.x + cos(angle) * riftRadius
            let riftY = enemy.pos.y + sin(angle) * riftRadius
            spawnExplosionPooled(game.particlePool, riftX, riftY,
                          Color(r: 150, g: 255, b: 255, a: 255), 3)
        
        # Light brilliance bursts (like Boss 9)
        for burst in 0..4:
          let burstAngle = burst.float32 * PI * 2.0 / 5.0
          for step in 0..8:
            let burstRadius = step.float32 * 25.0
            let burstX = enemy.pos.x + cos(burstAngle) * burstRadius
            let burstY = enemy.pos.y + sin(burstAngle) * burstRadius
            spawnExplosionPooled(game.particlePool, burstX, burstY,
                          Color(r: 255, g: 255, b: 255, a: 255), 4)
      
      else:
        discard  # No extra effects for default
    
    # Central explosion (size varies by mode)
    spawnExplosionPooled(game.particlePool, enemy.pos.x, enemy.pos.y, particleColor, explosionSize)
  
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
      spawnExplosionPooled(game.particlePool, enemy.pos.x, enemy.pos.y, phase.color, 8)
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
        # Use a fixed base difficulty so minions don't become stronger over time
        let minion = newEnemy(
          spawnX, spawnY,
          2.5,  # Fixed difficulty - does NOT scale with time
          thisType,
          game
        )
        # Mark as boss-spawned so it doesn't drop coins (prevent farming)
        minion.spawnedByBoss = true
        
        # NERF: Make boss-summoned minions smaller and slower
        minion.radius = minion.radius * 1.0  # 35% smaller
        minion.collisionRadius = minion.collisionRadius * 1.0  # Keep collision consistent
        minion.speed = minion.speed * 0.70  # 30% slower
        
        game.enemies.add(minion)
      
      # Visual feedback for summoning
      spawnExplosionPooled(game.particlePool, enemy.pos.x, enemy.pos.y, phase.color, 15)
  
  of bapMeteor:
    # Falling projectiles from above — screen-wide barrage with a guaranteed dodge gap
    # SpecialData modes:
    # - "warn_impact":    Show warnings before meteors arrive
    # - "massive_impact": Larger meteorites, more coverage
    # - "apocalypse_mode": Maximum meteorites, longer warnings
    # - "satellite_strike": Purple space theme

    let meteorMode = attack.specialData

    # Resolve bullet radius: 0 means "use default 6" (see BossAttack type comment).
    # A zero radius would make spacing = 0, causing an infinite loop in the layout loop below.
    let rawMeteorRadius = if attack.bulletRadius > 0: attack.bulletRadius else: 6.0'f32

    # Configure per-mode parameters
    let (warningTime, meteorColor, bRadius) = case meteorMode
      of "massive_impact":
        (0.65'f32, Color(r: 255, g: 100, b: 0, a: 255),
         rawMeteorRadius * 1.4)
      of "apocalypse_mode":
        (0.85'f32, Color(r: 255, g: 50, b: 0, a: 255),
         rawMeteorRadius * 1.6)
      of "satellite_strike":
        (0.75'f32, Color(r: 180, g: 120, b: 255, a: 255),
         rawMeteorRadius)
      else:  # "warn_impact" and everything else
        (0.55'f32, Color(r: 255, g: 150, b: 50, a: 255),
         rawMeteorRadius)

    # Layout: distribute meteors across 50% of the screen width
    let sw        = game.screenWidth.float32
    let margin    = 15.0'f32                       # keep away from edges
    let spacing   = bRadius * 5.0'f32              # center-to-center distance (2.5x->5.0x = 50% fewer meteors)

    # Barrage zone: half the screen width, randomly offset so it isn't always on one side
    let zoneWidth = sw * 0.5'f32
    let zoneStart = margin + rand(max(0.0'f32, sw - 2.0'f32 * margin - zoneWidth))
    let zoneEnd   = zoneStart + zoneWidth

    # Guaranteed safe gap: player must physically fit through it
    let gapHalf   = game.player.radius + bRadius + 28.0'f32  # 28 px clearance each side
    let gapMin    = zoneStart + gapHalf
    let gapMax    = zoneEnd   - gapHalf
    let gapCenter = gapMin + rand(max(0.0'f32, gapMax - gapMin))

    # Collect all meteor X positions inside the zone that fall outside the gap
    var meteorXs: seq[float32] = @[]
    var mx = zoneStart + bRadius
    while mx <= zoneEnd - bRadius:
      if abs(mx - gapCenter) >= gapHalf:
        meteorXs.add(mx)
      mx += spacing

    # For each position, place a timed warning, bullet spawns when warning expires
    let impactY = clamp(game.player.pos.y + 80.0'f32,
                        game.screenHeight.float32 * 0.5'f32,
                        game.screenHeight.float32 * 0.85'f32)

    for targetX in meteorXs:
      var w = AttackWarning(
        pos:          newVector2f(targetX, impactY),
        targetPos:    newVector2f(targetX, -50.0),   # bullet spawn point
        attackType:   "meteor",
        lifetime:     warningTime,
        maxLifetime:  warningTime,
        sourceEnemyId: enemy.id,
        bulletSpeed:  attack.projectileSpeed,
        bulletDamage: attack.damage * phase.damageMultiplier,
        bulletRadius: bRadius,
        overrideColor: meteorColor,
        bulletsCreated: false
      )
      game.attackWarnings.add(w)
  
  of bapOrbit:
    # ORBITAL SATELLITE SYSTEM
    # Creates persistent satellites that orbit, shoot, and can be destroyed
    # SpecialData modes:
    # - "electric_charges": Electric Boss 6 - yellow sparking satellites
    # - "satellite_orbit": Orbital Boss 7 - space theme, slower, methodical
    # - "dual_layer_orbit": Two concentric rings of satellites
    # - "orbital_storm": Three concentric rings (maximum chaos)
    
    # Only create satellites if they don't already exist
    if enemy.satellites.len == 0:
      let orbitMode = attack.specialData
      let satelliteCount = attack.projectileCount
      let baseOrbitRadius = attack.durationOrRadius
      
      # Configure layers based on mode
      let (layerCount, rotationSpeed, satelliteColor) = case orbitMode
        of "electric_charges":
          (1, 1.2, Color(r: 255, g: 255, b: 100, a: 255))  # Single fast layer, yellow
        of "satellite_orbit":
          (1, 0.6, Color(r: 150, g: 100, b: 255, a: 255))  # Single slow layer, purple
        of "dual_layer_orbit":
          (2, 1.0, Color(r: 200, g: 150, b: 255, a: 255))  # Two layers, medium speed
        of "orbital_storm":
          (3, 1.3, Color(r: 180, g: 120, b: 255, a: 255))  # Three layers, fast
        else:
          (1, 1.0, phase.color)  # Default single layer
      
      # Create satellites in multiple orbital layers
      for layer in 0..<layerCount:
        # Calculate satellites per layer (distribute evenly)
        let satsThisLayer = satelliteCount div layerCount
        let layerRadius = baseOrbitRadius + (layer.float32 * 50.0)  # Each layer 50px apart
        let angleOffset = if layer mod 2 == 0: 0.0 else: (PI / satsThisLayer.float32)  # Stagger alternating layers
        # Alternating layers rotate in opposite directions for visual complexity
        let layerRotationSpeed = if layer mod 2 == 0: rotationSpeed else: -rotationSpeed
        
        for i in 0..<satsThisLayer:
          let angle = i.float32 * (PI * 2.0 / satsThisLayer.float32) + angleOffset
          enemy.satellites.add(OrbitalSatellite(
            pos: newVector2f(
              enemy.pos.x + cos(angle) * layerRadius,
              enemy.pos.y + sin(angle) * layerRadius
            ),
            angle: angle,
            radius: layerRadius,
            rotationSpeed: layerRotationSpeed,
            hp: 8,  # REDUCED from 15 to 8 (easier to destroy)
            shootTimer: 0.5 + rand(1.0) + (layer.float32 * 0.3),  # Later layers shoot slightly later
            owner: enemy.id,
            laserActive: false,
            laserTarget: game.player.pos,  # Initialize with current player position
            laserChargeTime: 0.0
          ))
      
      # Visual effects based on mode
      let (explosionSize, explosionColor) = case orbitMode
        of "electric_charges":
          (35, Color(r: 255, g: 255, b: 150, a: 255))  # Bright yellow sparks
        of "satellite_orbit":
          (30, Color(r: 150, g: 100, b: 255, a: 255))  # Purple space theme
        of "dual_layer_orbit":
          (40, Color(r: 200, g: 150, b: 255, a: 255))  # Bright purple
        of "orbital_storm":
          (50, Color(r: 255, g: 200, b: 255, a: 255))  # Massive pink explosion
        else:
          (30, phase.color)
      
      spawnExplosionPooled(game.particlePool, enemy.pos.x, enemy.pos.y, explosionColor, explosionSize)
      
      # Extra ring effects for multi-layer
      if layerCount > 1:
        for layer in 0..<layerCount:
          let ringRadius = baseOrbitRadius + (layer.float32 * 50.0)
          for i in 0..<8:
            let angle = i.float32 * (PI * 2.0 / 8.0)
            let ringX = enemy.pos.x + cos(angle) * ringRadius
            let ringY = enemy.pos.y + sin(angle) * ringRadius
            spawnExplosionPooled(game.particlePool, ringX, ringY, satelliteColor, 3)
  
  of bapChain:
    # CHAIN LIGHTNING SYSTEM
    # Chain mechanics with visual lightning arcs
    # SpecialData modes:
    # - "chain_basic": Simple 3-chain lightning (Phase 1)
    # - "chain_storm": Multi-target chain web (Phase 2)
    # - "chain_overload": Maximum chain lightning chaos (Phase 3)
    
    let chainMode = attack.specialData
    
    # Configure chain behavior based on mode
    let (chainCount, chainsPerDirection, chainDecay) = case chainMode
      of "chain_basic":
        (attack.projectileCount, 2, 0.75)  # 3 directions, 2 chains each, 75% decay
      of "chain_storm":
        (attack.projectileCount, 3, 0.65)  # 5 directions, 3 chains each, 65% decay
      of "chain_overload":
        (attack.projectileCount, 4, 0.6)   # 8 directions, 4 chains each, 60% decay
      else:
        (attack.projectileCount, 2, 0.75)  # Default to basic
    
    # Create chain lightning in multiple directions
    for i in 0..<chainCount:
      let baseAngle = i.float32 * (PI * 2.0 / chainCount.float32) + rand(0.3)
      let dir = newVector2f(cos(baseAngle), sin(baseAngle))
      
      var currentDamage = attack.damage * phase.damageMultiplier
      var lastX = enemy.pos.x
      var lastY = enemy.pos.y
      
      # Create chain sequence in this direction
      for chainStep in 1..chainsPerDirection:
        let distance = chainStep.float32 * 80.0  # Distance between chain points
        let chainX = enemy.pos.x + dir.x * distance
        let chainY = enemy.pos.y + dir.y * distance
        
        # Check if chain is still on screen
        if chainX < 0 or chainX > game.screenWidth.float32 or
           chainY < 0 or chainY > game.screenHeight.float32:
          break
        
        # VISUAL: Persistent jagged lightning arc between chain points
        spawnLightningBolt(game, newVector2f(lastX, lastY), newVector2f(chainX, chainY))
        
        # Create bullet at chain point
        game.bullets.add(newBullet(
          x = chainX, y = chainY,
          direction = dir,
          speed = 180.0 + rand(40.0),  # Slightly randomized speed
          damage = currentDamage,
          fromPlayer = false,
          isBossBullet = true,
          sourceEnemyId = enemy.id,
          bossBulletShape = bossBulletShapeFor(enemy.bossDefinitionID)
        ))
        
        # Chain impact explosion
        spawnExplosionPooled(game.particlePool, chainX, chainY,
                      Color(r: 255, g: 255, b: 150, a: 255), 8)
        
        # Decay damage for next chain
        currentDamage *= chainDecay
        lastX = chainX
        lastY = chainY
      
      # SPECIAL: Chain storm creates branching
      if chainMode == "chain_storm" and rand(100) < 40:
        # 40% chance to create a branch
        let branchAngle = baseAngle + (if rand(2) == 0: 0.6 else: -0.6)
        let branchDir = newVector2f(cos(branchAngle), sin(branchAngle))
        let branchDist = 120.0
        let branchX = enemy.pos.x + branchDir.x * branchDist
        let branchY = enemy.pos.y + branchDir.y * branchDist
        
        if branchX > 0 and branchX < game.screenWidth.float32 and
           branchY > 0 and branchY < game.screenHeight.float32:
          # VISUAL: Persistent lightning arc for branch
          spawnLightningBolt(game, enemy.pos, newVector2f(branchX, branchY))
          
          game.bullets.add(newBullet(
            x = branchX, y = branchY,
            direction = branchDir,
            speed = 200.0,
            damage = attack.damage * phase.damageMultiplier * 0.5,
            fromPlayer = false, isBossBullet = true, sourceEnemyId = enemy.id,
        bossBulletShape = bossBulletShapeFor(enemy.bossDefinitionID),
        bulletRadius = attack.bulletRadius
          ))
    
    # Central explosion - varies by mode
    let (explosionSize, explosionColor) = case chainMode
      of "chain_overload": (40, Color(r: 255, g: 255, b: 255, a: 255))  # White overload
      of "chain_storm": (30, Color(r: 255, g: 255, b: 150, a: 255))     # Bright yellow
      else: (20, Color(r: 255, g: 255, b: 100, a: 255))                 # Yellow
    
    spawnExplosionPooled(game.particlePool, enemy.pos.x, enemy.pos.y, explosionColor, explosionSize)
  
  of bapTeleport:
    # Teleport to new location and shoot - customized via specialData
    # "afterimage_burst" = creates multiple images with burst effect
    # "triple_clone" = teleports to 3 locations simultaneously
    # "dimensional_rift" = creates rift visual effect
    
    let teleportMode = attack.specialData
    let teleportCount = case teleportMode
      of "triple_clone": 3
      of "time_echo": 2
      of "echo_burst": 4
      of "temporal_collapse": 6
      of "afterimage_burst": 3 + rand(2)  # 3-4 ghost images with rapid bursts
      of "chaos_blink": rand(2) + 1  # 1-2 random teleports with unstable reality tears
      of "reality_shift": rand(2) + 2  # 2-3 reality shifts with dimensional bridges
      of "dimensional_rift": 2  # 2 major dimensional rifts
      of "dimensional_chaos": rand(3) + 3  # 3-5 chaotic dimension portals with vortexes
      of "omega_blink": rand(2) + 4  # 4-5 ultimate teleports combining all effects
      else: 1
    
    # TELEPORT WARNING SYSTEM - Show player where boss will appear BEFORE bullets spawn
    # Pre-calculate all teleport positions and create warning indicators
    const BOSS_TELEPORT_MIN_DIST = 150.0  # Minimum distance boss can teleport near player
    var teleportWarningPositions: seq[Vector2f] = @[]
    for t in 0..<teleportCount:
      var newX, newY: float32
      var attempts = 0
      while true:
        newX = game.screenWidth.float32 * (0.2 + rand(0.6))
        newY = game.screenHeight.float32 * (0.2 + rand(0.6))
        let dx = newX - game.player.pos.x
        let dy = newY - game.player.pos.y
        let distSq = dx * dx + dy * dy
        inc attempts
        if distSq >= BOSS_TELEPORT_MIN_DIST * BOSS_TELEPORT_MIN_DIST or attempts >= 10:
          break  # Accept position if far enough or after max retries
      teleportWarningPositions.add(newVector2f(newX, newY))
    
    # Create pre-warning indicators at each teleport location
    let warningDuration = case teleportMode
      of "afterimage_burst": 0.6
      of "triple_clone": 0.7
      of "time_echo": 0.5
      of "echo_burst": 0.5
      of "temporal_collapse": 0.6
      of "chaos_blink": 0.5
      of "reality_shift": 0.7
      of "dimensional_rift": 0.8
      of "dimensional_chaos": 0.7
      of "omega_blink": 1.0
      else: 0.5
    
    # Create visual warnings for each teleport position
    # Calculate bullet spawn parameters BEFORE creating warnings
    let (bulletSpeed, bulletDamageMultiplier) = case teleportMode
      of "time_echo":
        (160.0, 0.65)  # Slower temporal echoes, reduced damage
      of "echo_burst":
        (200.0, 0.6)  # Many rapid echoes, lower damage
      of "temporal_collapse":
        (180.0, 0.7)  # Moderate speed reality-breaking shots
      of "afterimage_burst":
        (190.0 + rand(40.0), 0.65)  # Variable speed ghost shots
      of "chaos_blink":
        (170.0 + rand(60.0), 0.7)  # Random speed chaos
      of "reality_shift":
        (160.0 + rand(80.0), 0.65)  # Highly variable speed
      of "dimensional_rift":
        (180.0 + rand(50.0), 0.72)  # Dimensional rift shots with variance
      of "dimensional_chaos":
        (150.0 + rand(100.0), 0.75)  # Maximum speed variation
      of "omega_blink":
        (220.0, 0.8)  # Fast ultimate shots
      else:
        (200.0, 0.7)  # Default
    
    for idx in 0..<teleportWarningPositions.len:
      let warningPos = teleportWarningPositions[idx]
      # Create warning with bullet spawn data stored
      let warning = AttackWarning(
        pos: warningPos,
        attackType: "teleport_warning",
        lifetime: warningDuration,
        maxLifetime: warningDuration,
        sourceEnemyId: enemy.id,
        laserAngles: @[],
        laserLength: 0.0,
        laserCount: 0,
        laserDamage: 0,
        laserDuration: 0.0,
        lasersCreated: false,
        laserPattern: teleportMode,  # Store mode for visual rendering
        enemyType: etCircle,
        targetPos: warningPos,
        fromSatellite: false,
        # Store bullet spawn data for delayed creation
        bulletCount: attack.projectileCount,
        bulletSpeed: bulletSpeed,
        bulletDamage: attack.damage * phase.damageMultiplier * bulletDamageMultiplier,
        bulletSpreadAngle: 360.0,  # Full circle
        bulletsCreated: false,
        # Mark first position as where boss should teleport
        isBossTeleportTarget: (idx == 0)
      )
      game.attackWarnings.add(warning)

  of bapDash:
    # BERSERKER DASH SYSTEM with multi-charge mechanics
    # SpecialData modes:
    # - "charge_attack": Basic charge with screen shake
    # - "double_charge": Charges twice in rapid succession
    # - "rage_charge": THREE charges in combo! Maximum aggression!
    
    let dashMode = attack.specialData
    let dashDir = toPlayer
    var dashSpeed = attack.projectileSpeed
    
    # Cap dash speed to player speed for fairness
    # Bosses can charge at you, but never faster than you can move away
    if dashSpeed > game.player.speed:
      dashSpeed = game.player.speed
    
    # Configure dash based on mode
    let (dashDist, trailColor) = case dashMode
      of "charge_attack":
        (350.0, Color(r: 255, g: 50, b: 0, a: 255))  # Single charge, red trail
      of "double_charge":
        (300.0, Color(r: 255, g: 100, b: 0, a: 255))  # Double charge, bright red
      of "rage_charge":
        (280.0, Color(r: 255, g: 0, b: 0, a: 255))  # TRIPLE charge, pure red
      else:
        (350.0, phase.color)  # Default
    
    let dashTime = dashDist / dashSpeed  # Calculate duration based on speed
    
    # Set up dash state with charge count
    enemy.isDashing = true
    enemy.dashVelocity = dashDir * dashSpeed
    enemy.dashDuration = dashTime
    enemy.dashMaxDuration = dashTime
    
    # Store remaining charges (will re-trigger after current dash finishes)
    # This is handled in boss update logic by checking dashChargesRemaining
    
    # SCREEN SHAKE based on mode
    addShake(game.dopamine.screenShake, siLarge)
    
    # Create MORE impressive trail effects for rage charges
    let trailCount = if dashMode == "rage_charge": 8 elif dashMode == "double_charge": 6 else: 4
    for i in 0..<trailCount:
      let trailPos = i.float32 * (dashDist / trailCount.float32)
      game.bullets.add(newBullet(
        x = enemy.pos.x + dashDir.x * trailPos,
        y = enemy.pos.y + dashDir.y * trailPos,
        direction = dashDir,
        speed = dashSpeed * 0.4,  # Trail effect
        damage = attack.damage * phase.damageMultiplier * 0.6,  # Trail damage
        fromPlayer = false, isBossBullet = true, sourceEnemyId = enemy.id,
        bossBulletShape = bossBulletShapeFor(enemy.bossDefinitionID),
        bulletRadius = attack.bulletRadius
      ))
    
    # Rage charges get FIRE RING on activation
    if dashMode == "rage_charge":
      for i in 0..<16:
        let angle = i.float32 * (PI * 2.0 / 16.0)
        let ringX = enemy.pos.x + cos(angle) * 60.0
        let ringY = enemy.pos.y + sin(angle) * 60.0
        spawnExplosionPooled(game.particlePool, ringX, ringY,
                      Color(r: 255, g: 50, b: 0, a: 255), 5)
    
    # Initial visual explosion with colors
    let (explosionSize, explosionColor) = case dashMode
      of "rage_charge": (40, Color(r: 255, g: 0, b: 0, a: 255))
      of "double_charge": (30, Color(r: 255, g: 100, b: 0, a: 255))
      else: (20, trailColor)
    
    spawnExplosionPooled(game.particlePool, enemy.pos.x, enemy.pos.y, explosionColor, explosionSize)
  
  of bapSnipe:
    # PRECISION SNIPE SYSTEM - Boss 7 Orbital Commander
    # SpecialData modes:
    # - "orbital_snipe": Aimed shot from satellite position (shows laser pointer warning)
    # - "precision_strike": Double snipe with warning indicators
    # - "satellite_barrage": Multiple rapid snipes from different angles
    # - Default: Standard snipe
    
    let snipeMode = attack.specialData
    
    # Configure snipe behavior
    let (showWarning, warningTime, bulletColor) = case snipeMode
      of "orbital_snipe":
        (true, 0.8, Color(r: 150, g: 100, b: 255, a: 255))  # Purple space snipe with warning
      of "precision_strike":
        (true, 0.6, Color(r: 200, g: 150, b: 255, a: 255))  # Bright purple, shorter warning
      of "satellite_barrage":
        (true, 0.4, Color(r: 180, g: 120, b: 255, a: 255))  # Quick warnings for rapid fire
      else:
        (false, 0.0, phase.color)  # No warning for default
    
    # Show warning indicators at the TARGET position (near player), not at the enemy
    if showWarning:
      for i in 0..<attack.projectileCount:
        let spread = if attack.projectileCount > 1:
          (i.float32 - attack.projectileCount.float32 / 2.0) * attack.spreadAngle.degToRad() / attack.projectileCount.float32
        else: 0.0
        let aimAngle = arctan2(toPlayer.y, toPlayer.x) + spread
        # Project from enemy toward player to approximate impact point (capped at screen edge)
        let maxDist = min(distance(enemy.pos, game.player.pos) + 80.0, 600.0)
        let warnX = enemy.pos.x + cos(aimAngle) * maxDist
        let warnY = enemy.pos.y + sin(aimAngle) * maxDist
        game.attackWarnings.add(newAttackWarning(warnX, warnY, "laser_pointer", warningTime))
    
    # Fire the actual snipe shots
    for i in 0..<attack.projectileCount:
      let spread = if attack.projectileCount > 1:
        (i.float32 - attack.projectileCount.float32 / 2.0) * attack.spreadAngle.degToRad() / attack.projectileCount.float32
      else: 0.0
      let angle = arctan2(toPlayer.y, toPlayer.x) + spread
      let dir = newVector2f(cos(angle), sin(angle))
      
      # Enhanced bullet for special snipes
      game.bullets.add(newBullet(
        x = enemy.pos.x, y = enemy.pos.y, direction = dir,
        speed = attack.projectileSpeed, damage = attack.damage * phase.damageMultiplier,
        fromPlayer = false, isBossBullet = true, sourceEnemyId = enemy.id,
        bossBulletShape = bossBulletShapeFor(enemy.bossDefinitionID),
        bulletRadius = attack.bulletRadius
      ))
      
      # Visual muzzle flash per shot
      spawnExplosionPooled(game.particlePool, enemy.pos.x, enemy.pos.y, bulletColor, 8)
    
    # Special visual effects for satellite snipes
    if snipeMode == "satellite_barrage":
      # Create star pattern around boss
      for i in 0..<8:
        let angle = i.float32 * PI * 2.0 / 8.0
        let starX = enemy.pos.x + cos(angle) * 50.0
        let starY = enemy.pos.y + sin(angle) * 50.0
        spawnExplosionPooled(game.particlePool, starX, starY,
                      Color(r: 200, g: 150, b: 255, a: 255), 4)

# ORBITAL WEAPONS SYSTEM

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
    actualBaseDamage *= 2.0  # +100% damage
  
  # Use centralized stats for crit calculation
  let stats = calculateCombatStats(game.player)
  let damageWithCrit = applyCriticalHitFromStats(stats, actualBaseDamage)
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
  
  # Calculate combat stats once for all effect calculations
  let stats = calculateCombatStats(game.player)
  
  case orb.elementType
  of etPoison:
    # Poison: DoT effect
    let poisonDamageScaling = game.player.damage * 0.2
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
    spawnExplosionPooled(game.particlePool, orbPos.x, orbPos.y,
                   Color(r: 100, g: 255, b: 100, a: 255), 5)
  
  of etFire:
    # Fire: DoT effect
    let fireDamageScaling = game.player.damage * 0.2
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
    spawnExplosionPooled(game.particlePool, orbPos.x, orbPos.y, Orange, 5)
    spawnExplosionPooled(game.particlePool, orbPos.x, orbPos.y, Red, 3)
  
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
      let chainDamageWithCrit = applyCriticalHitFromStats(stats, baseDamage * 0.7)
      let chainDamage = damageEnemy(nearestEnemy, chainDamageWithCrit)
      
      # Track lightning orb chain damage (attribute to the same orb type as the parent hit)
      if hasPowerUp(game.player, puRotatingOrbs):
        trackPowerUpDamage(game, puRotatingOrbs, chainDamage)
      else:
        trackPowerUpDamage(game, puLightningOrb, chainDamage)
      
      game.showDamage(nearestEnemy.pos, chainDamage, fromPlayer = true,
                      isCritical = chainDamageWithCrit > baseDamage * 0.7, damageType = dtLightning)
      
      # Apply slow if has Lightning Mastery
      if game.player.hasLightningMastery:
        nearestEnemy.slowTimer = 0.2
        if nearestEnemy.slowAmount < 0.25:
          nearestEnemy.slowAmount = 0.25  # 25% slow
      
      # Lightning arc from hit enemy to chained enemy
      spawnLightningBolt(game, enemy.pos, nearestEnemy.pos)
      
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
          let secondChainDamageWithCrit = applyCriticalHitFromStats(stats, baseDamage * 0.7)
          let secondChainDamage = damageEnemy(secondNearestEnemy, secondChainDamageWithCrit)
          
          # Track second chain damage
          if hasPowerUp(game.player, puRotatingOrbs):
            trackPowerUpDamage(game, puRotatingOrbs, secondChainDamage)
          else:
            trackPowerUpDamage(game, puLightningOrb, secondChainDamage)
          
          game.showDamage(secondNearestEnemy.pos, secondChainDamage, fromPlayer = true,
                          isCritical = secondChainDamageWithCrit > baseDamage * 0.7, damageType = dtLightning)
          
          secondNearestEnemy.slowTimer = 0.2
          if secondNearestEnemy.slowAmount < 0.25:
            secondNearestEnemy.slowAmount = 0.25
          
          # Lightning arc from first chain to second chain
          spawnLightningBolt(game, nearestEnemy.pos, secondNearestEnemy.pos)
    
    # Apply slow to primary target if has Lightning Mastery
    if game.player.hasLightningMastery:
      enemy.slowTimer = 0.2
      if enemy.slowAmount < 0.25:
        enemy.slowAmount = 0.25
    
    # Yellow particles
    spawnExplosionPooled(game.particlePool, orbPos.x, orbPos.y, Yellow, 5)
  
  of etWind:
    # Wind: Knockback
    let pushDir = (enemy.pos - game.player.pos).normalize()
    var pushForce = 200.0
    let bossResistance = if enemy.isBoss: 0.1 else: 1.0
    
    if game.player.hasWindMastery:
      pushForce *= 2.5  # +150% stronger
    
    enemy.pos.x += pushDir.x * pushForce * dt * bossResistance
    enemy.pos.y += pushDir.y * pushForce * dt * bossResistance
    
    # Clamp to screen boundaries - enemies can't be pushed through borders
    enemy.pos.x = clamp(enemy.pos.x, enemy.radius, game.screenWidth.float32 - enemy.radius)
    enemy.pos.y = clamp(enemy.pos.y, enemy.radius, game.screenHeight.float32 - enemy.radius)
    
    # Apply slow only with Wind Mastery
    if game.player.hasWindMastery:
      enemy.slowTimer = 0.2
      if enemy.slowAmount < 0.40:
        enemy.slowAmount = 0.40  # 40% slow
    
    # Cyan particles
    spawnExplosionPooled(game.particlePool, orbPos.x, orbPos.y,
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
    spawnExplosionPooled(game.particlePool, orbPos.x, orbPos.y,
                   Color(r: 150, g: 200, b: 255, a: 255), 5)
  
  of etArcane:
    # Arcane: Pure damage (already applied) + purple sparkles
    spawnExplosionPooled(game.particlePool, orbPos.x, orbPos.y,
                   Color(r: 200, g: 100, b: 255, a: 255), 5)
  
  of etBlood:
    # Blood: Lifesteal
    var lifestealPercent = 0.05  # Base 5%
    
    if game.player.hasBloodMastery:
      lifestealPercent *= 2.0  # 10.0% with mastery
    
    let healAmount = baseDamage * lifestealPercent
    game.player.hp = min(game.player.hp + healAmount, game.player.maxHp)
    
    if healAmount > 0.01:
      game.showDamage(game.player.pos, healAmount, fromPlayer = true,
                      isCritical = false, damageType = dtHeal)
      
      # Green healing particles at player
      spawnExplosionPooled(game.particlePool, game.player.pos.x, game.player.pos.y,
                     Color(r: 100, g: 255, b: 100, a: 255), 3)
    
    # Red blood particles at hit location
    spawnExplosionPooled(game.particlePool, orbPos.x, orbPos.y,
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
  let damageScaling = game.player.damage * 0.3
  let baseDamage = if hasPowerUp(game.player, puRotatingOrbs):
    1.5 + damageScaling  # Legendary version
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
    maxDamage + damageScaling
  
  let orbRadius = 9.0
  let orbDetectionRange = 0.0
  
  # Update each orb
  for orb in game.player.rotatingOrbs:
    # Calculate orb position (rings 2 and 4 orbit backwards)
    let orbRotDir = if orb.orbLevel == 2 or orb.orbLevel == 4: -1.0'f32 else: 1.0'f32
    let angle = orbRotDir * game.player.orbRotationAngle + orb.angle
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

# MAIN GAME UPDATE LOOP
proc updateGame*(game: var Game, dt: float32) =
  updateDopamine(game.dopamine, dt)
  
  let celebrationActive = updateCelebration(game.dopamine.waveCelebration, dt)
  let introActive = updateIntroduction(game.dopamine.bossIntro, dt)
  updateAchievements(game.dopamine.achievements, dt)
  
  # If wave celebration is active, pause the game completely and return early
  if celebrationActive:
    return
  
  # If boss introduction is active, only allow player movement and particles
  if introActive:
    updatePlayer(game.player, dt, game.screenWidth, game.screenHeight, game.walls)
    
    # Update particles so visual feedback continues
    updateParticlePool(game.particlePool, dt)
    
    # Update game time
    game.time += dt
    game.frameCount += 1
    
    return
  
  # Handle 3D boss state
  if game.state == gs3DBoss:
    if game.game3D != nil:
      var game3D = cast[ptr Game3D](game.game3D)
      updateGame3D(game3D[], dt)
      
      if not game3D[].active:
        # 3D boss fight ended - return to 2D
        if game3D[].won:
          # Boss defeated - transfer health back
          game.player.hp = game3D[].player.health
          # Clean up and complete boss wave
          game.bossWaveManager.bossDefeated()
          game.bossWaveManager.coinActive = false  # Skip coin for 3D boss
          completeBossWave(game)
          game.state = gsPowerUpSelect
          enableCursor()
        else:
          # Player died in 3D
          game.state = gsGameOver
          enableCursor()
        # Clean up 3D game
        dealloc(game.game3D)
        game.game3D = nil
    return
  
  # Handle transition to 3D mode
  if game.transitioning:
    game.fadeAlpha += dt * 2.0
    if game.fadeAlpha >= 1.0:
      game.fadeAlpha = 1.0
      game.transitioning = false
      
      # Initialize and switch to 3D mode
      var game3D = create(Game3D)
      game3D[] = initGame3D(7, game.player)
      game.game3D = cast[pointer](game3D)
      game.state = gs3DBoss
      disableCursor()  # For mouse look
    return
  
  # Update real-time stats power level
  calculatePowerLevel(game.dopamine.realTimeStats, game.player)
    
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
  
  # OPTIMIZATION: Track frame count for satellite optimizations
  game.frameCount += 1
  
  # Track movement and update run duration for statistics
  trackMovementFrame(game, dt)
  
  game.spawnTimer += dt
  
  # Difficulty scaling (not in sandbox mode)
  if not isSandboxMode(game.mode):
    let modeDef = getGameModeDefinition(game.mode)
    # In wave-based mode, difficulty scales with wave number, not time
    if game.mode == gmWaveBased:
      game.difficulty = (game.currentWave.float32 / 5.0) * modeDef.difficultyScale
    else:
      # In other modes, difficulty scales with time
      game.difficulty = (game.time / 10.0) * modeDef.difficultyScale
  
  # Update attack warnings and create lasers from boss warnings when they expire
  var i = 0
  while i < game.attackWarnings.len:
    game.attackWarnings[i].lifetime -= dt
    
    # Only laser-beam warnings need to follow their source enemy as it moves
    # during the wind-up (so the drawn lines stay anchored to the boss).
    # All other warnings are stamped at a fixed world position and must not move.
    let warnType = game.attackWarnings[i].attackType
    if game.attackWarnings[i].sourceEnemyId >= 0 and
       (warnType == "boss_laser" or warnType == "satellite_laser"):
      for enemy in game.enemies:
        if enemy.id == game.attackWarnings[i].sourceEnemyId:
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
    
    # TELEPORT WARNING SYSTEM: Spawn bullets when warning expires
    if game.attackWarnings[i].attackType == "teleport_warning" and
       not game.attackWarnings[i].bulletsCreated and
       game.attackWarnings[i].lifetime <= 0.1:
      
      let warningPos = game.attackWarnings[i].pos
      let teleportMode = game.attackWarnings[i].laserPattern  # Mode stored in laserPattern field
      
      # Teleport boss to this position if this is the marked teleport target
      if game.attackWarnings[i].isBossTeleportTarget:
        for enemy in game.enemies:
          if enemy.id == game.attackWarnings[i].sourceEnemyId:
            # Teleport boss to this warning position
            enemy.pos = warningPos
            
            # Create dramatic teleport arrival effect
            let arrivalExplosionSize = case teleportMode
              of "time_echo": 18
              of "echo_burst": 20
              of "temporal_collapse": 25
              of "afterimage_burst": 16
              of "chaos_blink": 22
              of "reality_shift": 26
              of "dimensional_rift": 24
              of "dimensional_chaos": 30
              of "omega_blink": 35
              else: 15
            
            spawnExplosionPooled(game.particlePool, warningPos.x, warningPos.y,
                          Color(r: 150, g: 100, b: 255, a: 255), arrivalExplosionSize)
            break
      
      # Spawn bullets at warning position
      if game.attackWarnings[i].bulletCount > 0:
        for bulletIdx in 0..<game.attackWarnings[i].bulletCount:
          # Randomize angle for chaos modes
          let angle = if teleportMode in ["chaos_blink", "reality_shift", "dimensional_rift", "dimensional_chaos"]:
            bulletIdx.float32 * PI * 2.0 / game.attackWarnings[i].bulletCount.float32 + rand(0.4)
          else:
            bulletIdx.float32 * PI * 2.0 / game.attackWarnings[i].bulletCount.float32
          let dir = newVector2f(cos(angle), sin(angle))
          
          # Spawn bullet from this teleport location
          let warnSourceId = game.attackWarnings[i].sourceEnemyId
          var warnBossShape = 0
          for be in game.enemies:
            if be.id == warnSourceId:
              warnBossShape = bossBulletShapeFor(be.bossDefinitionID)
              break
          game.bullets.add(newBullet(
            x = warningPos.x, y = warningPos.y,
            direction = dir,
            speed = game.attackWarnings[i].bulletSpeed,
            damage = game.attackWarnings[i].bulletDamage,
            fromPlayer = false, isBossBullet = true,
            sourceEnemyId = warnSourceId,
            bossBulletShape = warnBossShape
          ))
      
      # Mark bullets as created
      game.attackWarnings[i].bulletsCreated = true

    # METEOR SYSTEM: Spawn bullet when warning expires
    if game.attackWarnings[i].attackType == "meteor" and
       not game.attackWarnings[i].bulletsCreated and
       game.attackWarnings[i].lifetime <= 0.05:
      let w = game.attackWarnings[i]
      var bossShape = 0
      for be in game.enemies:
        if be.id == w.sourceEnemyId:
          bossShape = bossBulletShapeFor(be.bossDefinitionID)
          break
      game.bullets.add(newBullet(
        x = w.targetPos.x, y = w.targetPos.y,
        direction = newVector2f(0, 1),
        speed = w.bulletSpeed,
        damage = w.bulletDamage,
        fromPlayer = false, isBossBullet = true,
        sourceEnemyId = w.sourceEnemyId,
        bossBulletShape = bossShape,
        bulletRadius = w.bulletRadius,
        colorOverride = w.overrideColor
      ))
      # Satellite strike entry flash
      if w.overrideColor.r < 200 and w.overrideColor.b > 200:  # purple = satellite
        for step in 0..4:
          spawnExplosionPooled(game.particlePool, w.targetPos.x, -50.0 - step.float32 * 25.0,
                              Color(r: 150, g: 100, b: 255, a: 255), 3)
      game.attackWarnings[i].bulletsCreated = true

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

  # Nova freeze expiry: when novaActive becomes false (set by player.nim), release bullets
  if not game.player.novaActive:
    for bullet in game.bullets:
      if bullet.isFrozenByNova and bullet.fromPlayer:
        bullet.vel = bullet.vel * 1.5
        bullet.isFrozenByNova = false

  # Radial Burst power-up - periodic circle of bullets
  if hasPowerUp(game.player, puRadialBurst):
    game.player.radialBurstTimer -= dt
    if game.player.radialBurstTimer <= 0:
      let level = getPowerUpLevel(game.player, puRadialBurst)
      let (bulletCount, cooldown) = case level
        of 1: (8, 3.5)
        of 2: (10, 3.0)
        else: (14, 2.0)
      
      # Calculate combat stats for radial burst bullets
      let stats = calculateCombatStats(game.player)
      
      # Fire circle of bullets
      for i in 0..<bulletCount:
        let angle = (i.float32 / bulletCount.float32) * PI * 2.0
        let direction = newVector2f(cos(angle), sin(angle))
        
        # Create bullet with player's current stats
        let damageWithCrit = applyCriticalHitFromStats(stats, stats.damage)
        
        game.bullets.add(newBullet(
          x = game.player.pos.x,
          y = game.player.pos.y,
          direction = direction,
          speed = game.player.bulletSpeed,
          damage = damageWithCrit,
          fromPlayer = true,
          isHoming = false,
          isPiercing = hasPowerUp(game.player, puPiercingShots),
          isExplosive = hasPowerUp(game.player, puExplosiveBullets),
          hasBounce = hasPowerUp(game.player, puBulletRicochet),
          canSplit = hasPowerUp(game.player, puBulletSplit),
          slowAmount = 0.0,  # Add elemental effects if player has them
          poisonDuration = 0.0,
          fireDuration = 0.0,
          windPushForce = 0.0,
          bulletSkin = game.player.bulletSkinType,
          bulletShape = game.player.bulletShapeType,
          isFromRadialBurst = true
        ))
      
      # Visual feedback
      spawnExplosionPooled(game.particlePool, game.player.pos.x, game.player.pos.y,
                    Color(r: 100, g: 200, b: 255, a: 255), 25)
      
      game.player.radialBurstTimer = cooldown
  
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
    
    # Poison visual effect
    # Spawn ~20 particles/sec
    spawnTimedParticlesPooled(game.particlePool, game.player.pos.x, game.player.pos.y, 20.0, Green, 2, dt)
  
  # Regeneration power-up is now handled per wave completion, not per time interval
  # See wave completion code for regeneration logic
  
  # Slow Field power-up effect
  if hasPowerUp(game.player, puSlowField):
    let level = getPowerUpLevel(game.player, puSlowField)
    let slowPercent = case level
      of 1: 0.30  # NERFED from 50% to 30% slow
      of 2: 0.45  # NERFED from 65% to 45% slow
      else: 0.55  # NERFED from 75% to 55% slow
    let slowRadius = getAuraRadius(level)
    
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
    let damageScaling = game.player.damage * 0.3
    let fireDamagePerSec = case level
      of 1: 1.0 + damageScaling
      of 2: 2.5 + damageScaling
      else: 5.0 + damageScaling
    let fireDuration = case level
      of 1: 2.0
      of 2: 2.5
      else: 5.0
    let fireRadius = getAuraRadius(level)
    
    for enemy in game.enemies:
      let dist = distance(game.player.pos, enemy.pos)
      if dist < fireRadius:
        var actualFireDamage = fireDamagePerSec
        var actualFireDuration = fireDuration
        
        # Apply Fire Mastery bonuses if owned
        if game.player.hasFireMastery:
          actualFireDamage *= 2.5  # +150% damage
          actualFireDuration *= 2.0  # +100% duration
        
        # Apply fire effect
        applyEffect(enemy, etFire, actualFireDamage, actualFireDuration, "aura")
        
        # Apply slow ONLY if player has Fire Mastery
        if game.player.hasFireMastery:
          enemy.slowTimer = 0.2
          if enemy.slowAmount < 0.35:
            enemy.slowAmount = 0.35  # 35% slow
        
        # Visual fire particles
        spawnTimedParticlesAroundPooled(game.particlePool, enemy.pos.x, enemy.pos.y,
                                 enemy.radius + 5.0, 4.8, Red, 2, dt, -3.0)
  
  # Lightning Aura power-up effect - low damage with chain lightning
  if hasPowerUp(game.player, puLightningAura):
    let level = getPowerUpLevel(game.player, puLightningAura)
    let damageScaling = game.player.damage * 0.3
    var lightningDamagePerSec = case level
      of 1: 1.0 + damageScaling
      of 2: 2.5 + damageScaling
      else: 5.0 + damageScaling
    var maxChains = case level
      of 1: 1
      of 2: 2
      else: 4
    let lightningRadius = getAuraRadius(level)
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
    
    # Calculate combat stats once before loop
    let stats = calculateCombatStats(game.player)
    
    # Apply damage and chain lightning
    var processedEnemies: seq[Enemy] = @[]
    for entry in enemiesInRange:
      let enemy = entry.enemy
      if enemy notin processedEnemies:
        # Apply initial damage with crit chance using centralized stats
        let (damageWithCrit, wasCrit) = applyCriticalHitWithFlag(stats, lightningDamagePerSec * dt)
        let actualDamage = damageEnemy(enemy, damageWithCrit)
        processedEnemies.add(enemy)
        
        # Track lightning aura damage for statistics
        trackPowerUpDamage(game, puLightningAura, actualDamage)
        
        # Use accumulation system for reliable damage numbers
        accumulateAndShowAuraDamage(game, enemy, actualDamage, dtLightning, wasCrit)
        
        # Apply slow ONLY if player has Lightning Mastery
        if game.player.hasLightningMastery:
          enemy.slowTimer = 0.2
          if enemy.slowAmount < 0.25:
            enemy.slowAmount = 0.25  # 25% slow
        
        # Visual lightning spark
        spawnTimedParticlesPooled(game.particlePool, enemy.pos.x, enemy.pos.y, 6.0,
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
            # Apply chained damage (same as initial) with crit chance using centralized stats
            let (chainDamageWithCrit, chainWasCrit) = applyCriticalHitWithFlag(stats, lightningDamagePerSec * dt)
            let chainedDamage = damageEnemy(nearestEnemy, chainDamageWithCrit)
            processedEnemies.add(nearestEnemy)
            
            # Track chained lightning damage for statistics
            trackPowerUpDamage(game, puLightningAura, chainedDamage)
            
            # Use accumulation system for chained lightning to prevent spam
            accumulateAndShowAuraDamage(game, nearestEnemy, chainedDamage, dtLightning, chainWasCrit)
            
            # Apply 5% slow effect to chained enemy
            nearestEnemy.slowTimer = 0.2
            if nearestEnemy.slowAmount < 0.05:
              nearestEnemy.slowAmount = 0.05
            
            # Lightning arc visual
            spawnLightningBolt(game, currentEnemy.pos, nearestEnemy.pos)

            currentEnemy = nearestEnemy
          else:
            break  # No more enemies to chain to
  
  # Arcane Aura power-up effect - pure arcane damage
  if hasPowerUp(game.player, puArcaneAura):
    let level = getPowerUpLevel(game.player, puArcaneAura)
    let damageScaling = game.player.damage * 0.3
    var arcaneDamagePerSec = case level
      of 1: 3.5 + damageScaling
      of 2: 7.5 + damageScaling
      else: 10.0 + damageScaling
    let arcaneRadius = getAuraRadius(level)
    
    # Apply Arcane Mastery bonuses if owned
    if game.player.hasArcaneMastery:
      arcaneDamagePerSec *= 2.0  # +100% damage
    
    # Calculate combat stats once before loop
    let arcaneStats = calculateCombatStats(game.player)
    
    for enemy in game.enemies:
      let dist = distance(game.player.pos, enemy.pos)
      if dist < arcaneRadius:
        let (damageWithCrit, wasCrit) = applyCriticalHitWithFlag(arcaneStats, arcaneDamagePerSec * dt)
        let actualDamage = damageEnemy(enemy, damageWithCrit)
        
        # Track arcane aura damage for statistics
        trackPowerUpDamage(game, puArcaneAura, actualDamage)
        
        # Use accumulation system for reliable damage numbers
        accumulateAndShowAuraDamage(game, enemy, actualDamage, dtArcane, wasCrit)
        
        # Visual arcane particles (purple sparkles)
        spawnTimedParticlesAroundPooled(game.particlePool, enemy.pos.x, enemy.pos.y,
                                 enemy.radius + 3.0, 7.2,
                                 Color(r: 200, g: 100, b: 255, a: 255), 2, dt)
  
  # Poison Aura power-up effect - low damage, longer duration
  if hasPowerUp(game.player, puPoisonAura):
    let level = getPowerUpLevel(game.player, puPoisonAura)
    let damageScaling = game.player.damage * 0.3
    let poisonDamagePerSec = case level
      of 1: 1.0 + damageScaling
      of 2: 2.5 + damageScaling
      else: 5.0 + damageScaling
    let poisonDuration = case level
      of 1: 6.0
      of 2: 8.0
      else: 10.0
    let poisonRadius = getAuraRadius(level)
    
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
        
        # Visual poison particles
        spawnTimedParticlesAroundPooled(game.particlePool, enemy.pos.x, enemy.pos.y,
                                 enemy.radius + 5.0, 3.6,
                                 Color(r: 100, g: 255, a: 200), 2, dt, -3.0)
  
  # Wind Aura power-up effect - pushes enemies away from player (slow aura but different mechanic)
  if hasPowerUp(game.player, puWindAura):
    let level = getPowerUpLevel(game.player, puWindAura)
    var pushStrength = case level
      of 1: 50.0   # Weak push
      of 2: 80.0   # Medium push
      else: 120.0  # Strong push
    let windRadius = getAuraRadius(level)
    
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
        
        # Clamp to screen boundaries - enemies can't be pushed through borders
        enemy.pos.x = clamp(enemy.pos.x, enemy.radius, game.screenWidth.float32 - enemy.radius)
        enemy.pos.y = clamp(enemy.pos.y, enemy.radius, game.screenHeight.float32 - enemy.radius)
        
        # Apply slow ONLY if player has Wind Mastery
        if game.player.hasWindMastery:
          enemy.slowTimer = 0.2
          if enemy.slowAmount < 0.40:
            enemy.slowAmount = 0.40  # 40% slow
        
        # Visual wind particles (outward from player toward enemies)
        spawnTimedParticlesAroundPooled(game.particlePool, game.player.pos.x, game.player.pos.y,
                                 windRadius * 0.8, 4.8,
                                 Color(r: 200, g: 230, b: 255, a: 150), 2, dt)
  
  # Blood Aura power-up effect - damage with lifesteal
  if hasPowerUp(game.player, puBloodAura):
    let level = getPowerUpLevel(game.player, puBloodAura)
    let damageScaling = game.player.damage * 0.3
    var bloodDamagePerSec = case level
      of 1: 1.0 + damageScaling
      of 2: 2.5 + damageScaling
      else: 5.0 + damageScaling
    let lifestealPercent = case level
      of 1: 0.025  # 2.5% lifesteal
      of 2: 0.05   # 5% lifesteal
      else: 0.075  # 7.5% lifesteal
    let bloodRadius = case level
      of 1: 120.0
      of 2: 160.0
      else: 200.0
    
    # Apply Blood Mastery bonuses if owned
    var actualLifestealPercent: float64 = lifestealPercent
    if game.player.hasBloodMastery:
      bloodDamagePerSec *= 2.5  # +150% damage
      actualLifestealPercent *= 2.0  # +100% lifesteal
    
    # Static variable to track last healing number display time
    var lastBloodHealTime {.global.} = 0.0
    const BLOOD_HEAL_DISPLAY_INTERVAL = 0.5  # Show healing number every 0.5 seconds
    
    # Accumulate healing for display (show healing number once per 0.5s)
    var totalHealing = 0.0
    
    # Calculate combat stats once before loop
    let bloodStats = calculateCombatStats(game.player)
    
    for enemy in game.enemies:
      let dist = distance(game.player.pos, enemy.pos)
      if dist < bloodRadius:
        # Apply blood damage with crit chance using centralized stats
        let (damageWithCrit, wasCrit) = applyCriticalHitWithFlag(bloodStats, bloodDamagePerSec * dt)
        let actualDamage = damageEnemy(enemy, damageWithCrit)
        
        # Track blood aura damage for statistics
        trackPowerUpDamage(game, puBloodAura, actualDamage)
        
        # Accumulate healing based on damage dealt
        totalHealing += actualDamage * actualLifestealPercent
        
        # Use accumulation system for reliable damage numbers (use dtFire for red blood damage)
        accumulateAndShowAuraDamage(game, enemy, actualDamage, dtFire, wasCrit)
        
        # Visual blood particles
        spawnTimedParticlesAroundPooled(game.particlePool, enemy.pos.x, enemy.pos.y,
                                 enemy.radius + 5.0, 4.8,
                                 Color(r: 255, g: 50, b: 50, a: 255), 2, dt, -3.0)
    
    # Apply accumulated healing to player
    if totalHealing > 0:
      game.player.hp = min(game.player.hp + totalHealing, game.player.maxHp)
      
      # Show healing number periodically using tracked time
      if game.time - lastBloodHealTime >= BLOOD_HEAL_DISPLAY_INTERVAL:
        # Display raw accumulated healing (not per-second)
        game.showDamage(game.player.pos, totalHealing, fromPlayer = true,
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
        
        # Spawn visual particles for gravity effect (more for ranged enemies)
        let particleRate = if isRanged: 15.0 else: 9.0
        let particleColor = if isRanged: Color(r: 138, g: 43, b: 226, a: 220) else: Color(r: 75, g: 0, b: 130, a: 200)
        spawnTimedParticlesAroundPooled(game.particlePool, game.player.pos.x, game.player.pos.y,
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

  # Pulse Armor - emit shockwave when taking damage
  if game.player.pulseArmorCooldown < 0:  # -1 signals trigger
    let level = getPowerUpLevel(game.player, puPulseArmor)
    if level > 0:
      let (pushRadius, pushForce, baseDamage, cooldown) = case level
        of 1: (120.0, 400.0, 0.0, 8.0)    # Level 1: small radius, low force, no damage, 8s cooldown
        of 2: (160.0, 500.0, 2.0, 6.0)    # Level 2: medium radius, medium force, 2 damage, 6s cooldown
        else: (200.0, 600.0, 4.0, 4.0)     # Level 3: large radius, high force, 4 damage, 4s cooldown
      
      # Calculate damage scaling from max HP (scales with tank stats)
      let damageScaling = game.player.maxHp * 0.01  # 1% of max HP as scaling
      let damage = baseDamage + damageScaling
      
      # Push all enemies within radius (and damage them if level > 1)
      for enemy in game.enemies:
        let dist = distance(game.player.pos, enemy.pos)
        if dist < pushRadius and dist > 5.0:
          # Calculate push direction (away from player)
          let awayFromPlayer = (enemy.pos - game.player.pos).normalize()
          
          # Apply push force (stronger when closer)
          let actualPushForce = pushForce * (1.0 - (dist / pushRadius))
          enemy.vel.x += awayFromPlayer.x * actualPushForce
          enemy.vel.y += awayFromPlayer.y * actualPushForce
          
          # Apply damage for level 2 and 3
          if baseDamage > 0:
            let actualDamage = damageEnemy(enemy, damage)
            # Track pulse armor damage for statistics
            trackPowerUpDamage(game, puPulseArmor, actualDamage)
            # Show damage number
            game.showDamage(enemy.pos, actualDamage, fromPlayer = true,
                          isCritical = false, damageType = dtDefault)
      
      # Visual feedback - expanding shockwave ring
      spawnExplosionPooled(game.particlePool, game.player.pos.x, game.player.pos.y,
                    Color(r: 100, g: 200, b: 255, a: 255), 40)
      
      # Set cooldown
      game.player.pulseArmorCooldown = cooldown
      playSound(stExplosion, 0.6)
  
  # Update Pulse Armor cooldown
  if game.player.pulseArmorCooldown > 0:
    game.player.pulseArmorCooldown -= dt

  # Rotating Orbs power-up - elemental orbs that orbit the player and damage enemies
  updateOrbitalWeapons(game, dt)

  # Decay active lightning bolt visuals
  updateLightningBolts(game, dt)
  

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
  
  # MODE-SPECIFIC ENEMY SPAWNING
  if not isSandboxMode(game.mode):
    if shouldUseWaves(game.mode):
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
          var healAmount = 0.0
          
          case level
          of 1:
            # Level 1: 1.5-2.5 health (base)
            healAmount = 1.5 + rand(1.0)  # 1.5 to 2.5
          of 2:
            # Level 2: 2.5-4.5 health
            healAmount = 2.5 + rand(2.0)  # 2.5 to 4.5
          else:
            # Level 3: 3.5-6.5 health
            healAmount = 3.5 + rand(3.0)  # 3.5 to 6.5
          
          heal(game.player, healAmount)
          spawnExplosionPooled(game.particlePool, game.player.pos.x, game.player.pos.y, Green, 15)
        
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
        
        # Calculate final wave stats
        calculateAccuracy(game.dopamine.waveStats)
        
        # Check for perfect wave combo bonus
        let perfectWaveBonus = checkPerfectWaveCombo(game.dopamine.comboSystem, game.waveEnemiesTotal)
        if perfectWaveBonus > 0:
          game.player.coins += perfectWaveBonus
          playSound(stCoinPickup)  # Play coin sound for bonus
          trackPerfectWave()  # Track for statistics
        
        # Wave celebration removed from here - now only happens after boss defeat
        
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
      # Use a boss wave that maps to the boss block (ceil to next multiple of 5)
      # This allows debug spawns when wavesUntilBoss is forced to 0 (boss appears
      # for the current boss block: waves 1-5 => boss 1, 6-10 => boss 2, etc.)
      let bossBlockWave = ((game.currentWave - 1) div 5 + 1) * 5
      let bossNumber = getCustomBossNumber(bossBlockWave)
      
      # Check if this is Boss #7 (3D boss)
      if bossNumber == 13: # Disabled for now (7)
        # Start transition to 3D mode
        game.transitioning = true
        game.fadeAlpha = 0.0
        game.bossWaveManager.startBossWave()  # Mark boss wave as active
        playSound(stBossSpawn)
      else:
        # Normal 2D boss
        game.enemies.add(spawnBoss(game.screenWidth, game.screenHeight,
                  bossDifficulty, game.bossCount, bossBlockWave))
        game.bossWaveManager.startBossWave()  # Mark boss wave as active
        game.bossSpawnTimer = 1.5  # Short warning, doesn't pause gameplay
        # Don't reset wavesUntilBoss here - it will be reset when boss coin is collected
        
        # Play boss spawn sound
        playSound(stBossSpawn)
        
        # Entrance particles
        let boss = game.enemies[^1]
        
        # Trigger boss introduction - use correct boss number, not wave number
        let bossName = getBossDefinition(bossNumber).name
        let bossTitle = getBossDefinition(bossNumber).description
        startIntroduction(game.dopamine.bossIntro, bossName, bossTitle, boss.maxHp)
        
        # Spawn entrance particles for custom boss
        for i in 0..<60:
          let angle = i.float32 * 0.1
          let dist = i.float32 * 3
          let x = boss.pos.x + cos(angle) * dist
          let y = boss.pos.y + sin(angle) * dist
          spawnExplosionPooled(game.particlePool, x, y, boss.color, 3)
    
    elif isTimeSurvivalMode(game.mode):
      # TIME SURVIVAL MODE: delegate to survival.nim
      spawnSurvivalEnemies(game)

  # Update enemies

  var enemyIdx = 0
  var bossDefeated = false
  while enemyIdx < game.enemies.len:
    var enemy = game.enemies[enemyIdx]
    
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
      
      # Use accumulation system for reliable DOT damage numbers
      # Determine damage type based on active effects
      var dotDamageType = dtDefault
      if hasActiveEffect(enemy, etPoison):
        dotDamageType = dtPoison
      elif hasActiveEffect(enemy, etFire):
        dotDamageType = dtFire
      elif hasActiveEffect(enemy, etLightning):
        dotDamageType = dtLightning  # Use lightning color for lightning
      
      # Use accumulation system like auras (shows every 0.5s)
      accumulateAndShowAuraDamage(game, enemy, actualDamage, dotDamageType, false)
    
    # Update chain lightning cooldown
    if enemy.chainLightningCooldown > 0:
      enemy.chainLightningCooldown -= effectiveDt  # Use slowed time
    
    # Update slow timer (from Chain Lightning stun and other effects)
    if enemy.slowTimer > 0:
      enemy.slowTimer -= effectiveDt
      if enemy.slowTimer <= 0:
        enemy.slowAmount = 0
    
    if not updateEnemy(enemy, game.player.pos, effectiveDt, game.walls, game.time, game):  # Use slowed time
      # Enemy died - show any accumulated aura damage before death
      flushAccumulatedAuraDamage(game, enemy)
      
      # Enemy died - drop coins and particles
      
      # Play enemy death sound
      playSound(stEnemyDeath, if enemy.isBoss: 1.0 else: 0.4)
      
      # Boss-spawned minions don't drop coins (prevent farming)
      if not enemy.spawnedByBoss:
        # Calculate coin value with elite multiplier
        var coinValue = if enemy.isBoss:
          # Boss drops - in wave mode scale with waves, in other modes scale with difficulty
          let baseAmount = if game.mode == gmWaveBased:
            # Wave-based: scale with wave number instead of time
            50 + (game.currentWave div 5) * 10  # +10 coins every 5 waves
          else:
            # Other modes: scale with difficulty (time-based)
            30 + (game.difficulty * 3.5).int
          # Add randomness: ±20% variation
          let minAmount = (baseAmount.float32 * 0.9).int
          let maxAmount = (baseAmount.float32 * 1.1).int
          rand(minAmount..maxAmount)
        else:
          # Regular enemies drop based on type
          # In wave mode, coins don't scale with waves to keep economy consistent
          let waveBonus = if game.mode == gmWaveBased: 0 else: (game.currentWave div 10)
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
        spawnExplosionPooled(game.particlePool, enemy.pos.x, enemy.pos.y,
                      Color(r: 255, g: 128, b: 0, a: 255), 40)
        spawnShockwavePooled(game.particlePool, enemy.pos.x, enemy.pos.y, eliteExplosionRadius)
      
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
        spawnExplosionPooled(game.particlePool, enemy.pos.x, enemy.pos.y,
                      Color(r: 255, g: 150, b: 0, a: 255), 60)  # More particles
        spawnExplosionPooled(game.particlePool, enemy.pos.x, enemy.pos.y,
                      Color(r: 255, g: 220, b: 100, a: 255), 40)  # Bright inner core
        # Add multiple shockwave rings for clarity
        spawnShockwavePooled(game.particlePool, enemy.pos.x, enemy.pos.y, explosionRadius)
        spawnShockwavePooled(game.particlePool, enemy.pos.x, enemy.pos.y, explosionRadius * 0.7)
        spawnShockwavePooled(game.particlePool, enemy.pos.x, enemy.pos.y, explosionRadius * 0.4)
      
      # Death particles — rich multi-layer burst
      spawnEnemyDeathBurst(game.particlePool, enemy.pos.x, enemy.pos.y,
                           enemy.color, enemy.radius, enemy.isBoss)
      
      # Drop consumable
      if enemy.isBoss:
        # BOSSES ALWAYS DROP HEALTH - offset from coin position so it's visible
        let clampedPos = clampLootPosition(enemy.pos.x, enemy.pos.y, game.screenWidth, game.screenHeight)
        # Offset health drop 40 pixels to the right of the coin
        let healthX = clampedPos.x + 40.0
        let healthY = clampedPos.y
        let healthPos = clampLootPosition(healthX, healthY, game.screenWidth, game.screenHeight)
        game.consumables.add(newSpecificConsumable(healthPos.x, healthPos.y, ctHealth))
      else:
        # Regular enemies have 15% chance to drop a consumable
        if rand(99) < 15:
          # Clamp consumable position to be in bounds (for enemies killed out-of-bounds)
          let clampedPos = clampLootPosition(enemy.pos.x, enemy.pos.y, game.screenWidth, game.screenHeight)
          # In wave mode, consumables don't scale with difficulty to keep drop quality consistent
          let consumableDifficulty = if game.mode == gmWaveBased: 1.0 else: game.difficulty
          game.consumables.add(newConsumable(clampedPos.x, clampedPos.y, consumableDifficulty))
      
      game.player.kills += 1
      
      # Lifesteal consumable - heal 1 HP per kill
      if game.player.lifestealTimer > 0:
        heal(game.player, 1)
        # Show heal damage number
        showDamage(game, game.player.pos, 1.0, true, false, dtHeal)
      
      if game.player.kills == 1:
        discard unlockAchievement(game.dopamine.achievements, "first_blood")
      if game.player.kills == 100:
        discard unlockAchievement(game.dopamine.achievements, "centurion")
      
      recordKill(game.dopamine.realTimeStats)
      
      if enemy.isBoss:
        # Boss kill - MASSIVE effects
        addShake(game.dopamine.screenShake, siMassive)
        activateSlowMo(game.dopamine.slowMotion, smtBossKill)
        # Record kill with high damage for stats
        recordKill(game.dopamine.waveStats, enemy.maxHp)
      else:
        # Regular enemy kill - standard effects
        addShake(game.dopamine.screenShake, siMedium)
        activateSlowMo(game.dopamine.slowMotion, smtKill)
        # Record kill with damage dealt
        recordKill(game.dopamine.waveStats, 0)  # Don't track individual enemy damage for non-bosses
      
      # Kill streak system removed - only using combo system now
      
      # Track combo and award bonus coins (but not for boss minions)
      if not enemy.spawnedByBoss:
        let comboBonus = addComboKill(game.dopamine.comboSystem, game.dopamine.currentTime)
        if comboBonus > 0:
          game.player.coins += comboBonus
          recordCombo(game.dopamine.waveStats, game.dopamine.comboSystem.killCount)
        
        # Track combo statistics for run stats
        trackCombo(game, game.dopamine.comboSystem.killCount)
      
      # Check for milestones
      if checkMilestone(game.dopamine.milestones, mtKills, game.player.kills, game.dopamine.currentTime):
        addNotification(game.osHUD, "MILESTONE: " & game.dopamine.milestones.recentMilestone.name,
                        ntInfo)
      
      # Track enemy kill for statistics
      trackEnemyKilled(game, enemy)
      
      # Life steal power-up effect
      if hasPowerUp(game.player, puLifeSteal):
        let level = getPowerUpLevel(game.player, puLifeSteal)
        game.player.killsSinceLastHeal += 1
        let healsPerKills = case level
          of 1: 12
          of 2: 9
          else: 6
        
        if game.player.killsSinceLastHeal >= healsPerKills:
          heal(game.player, 0.5)  # Heal 0.5 HP
          game.player.killsSinceLastHeal = 0
          spawnExplosionPooled(game.particlePool, game.player.pos.x, game.player.pos.y, Green, 15)
      
      # Check if boss was defeated
      if enemy.isBoss:
        bossDefeated = true
        
        # Mark that a boss coin is now active and must be collected
        game.bossWaveManager.bossDefeated()
        
        # Count total bosses defeated from game state
        var totalBossesDefeated = game.bossCount
        if totalBossesDefeated >= 10:
          discard unlockAchievement(game.dopamine.achievements, "boss_slayer")
        
        # Mode-specific boss defeat handling - NO longer advance wave here
        # Wave will advance when boss coin is collected
      
      # Volatile: death pulse spreads active elements to nearby enemies
      if game.player.hasVolatile:
        var activeEffectCount = 0
        for et, ae in enemy.activeEffects:
          if ae.primary.isActive:
            activeEffectCount += 1
        if activeEffectCount >= 2:
          const volatilePulseRadius = 120.0
          for otherEnemy in game.enemies:
            if otherEnemy.id != enemy.id:
              let dist = distance(enemy.pos, otherEnemy.pos)
              if dist <= volatilePulseRadius:
                # Spread each active element at 60% DPS and 50% duration
                for et, ae in enemy.activeEffects:
                  if ae.primary.isActive:
                    applyEffect(otherEnemy, ae.primary.elementType,
                                ae.primary.damagePerSec * 0.6,
                                ae.primary.remainingDuration * 0.5,
                                "volatile_pulse")
          spawnExplosionPooled(game.particlePool, enemy.pos.x, enemy.pos.y,
                        Color(r: 255, g: 150, b: 50, a: 255), 20)
      
      game.enemies.delete(enemyIdx)
      continue
    
    # Write back modified enemy to array
    game.enemies[enemyIdx] = enemy
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
      
      # Update invulnerability timer
      if enemy.invulnerabilityTimer > 0:
        enemy.invulnerabilityTimer -= dt
        if enemy.invulnerabilityTimer < 0:
          enemy.invulnerabilityTimer = 0
      
      # Check if we need to transition to a new phase
      for i, phase in bossDef.phases:
        if hpPercent <= phase.hpThreshold and i > enemy.currentPhaseIndex:
          enemy.currentPhaseIndex = i
          
          # DRAMATIC PHASE TRANSITION EFFECTS
          # 1. Brief invulnerability
          enemy.invulnerabilityTimer = 2.0
          
          # 2. Screen shake for impact
          addShake(game.dopamine.screenShake, siLarge)
          
          # 3. Massive particle explosion (expanding rings)
          for ring in 1..5:
            for j in 0..23:
              let angle = j.float32 * PI * 2.0 / 24.0
              let dist = ring.float32 * 35.0
              let px = enemy.pos.x + cos(angle) * dist
              let py = enemy.pos.y + sin(angle) * dist
              spawnExplosionPooled(game.particlePool, px, py, phase.color, 8)
          
          # 4. Extra burst at center
          spawnExplosionPooled(game.particlePool, enemy.pos.x, enemy.pos.y,
                        Color(r: 255, g: 255, b: 255, a: 255), 40)
          
          # REGENERATE SATELLITES - Clear existing satellites so new phase can spawn correct number
          # This ensures bosses with satellite attacks get the proper count for the new phase
          if enemy.satellites.len > 0:
            # Create destruction effect for each destroyed satellite
            for satellite in enemy.satellites:
              spawnExplosionPooled(game.particlePool, satellite.pos.x, satellite.pos.y,
                            Color(r: 100, g: 150, b: 255, a: 255), 12)
            # Clear satellite list - new phase will regenerate with correct count
            enemy.satellites = @[]
          
          # Reinitialize attack timers for new phase.
          # Use WARNING_LEAD_TIME so the pre-fire warning fires immediately and
          # the attack follows 0.4 s later — fast phase-start without skipping warnings.
          const PHASE_TRANSITION_LEAD = 0.4'f32
          enemy.attackTimers = @[]
          enemy.attackWarningFired = @[]
          for attack in phase.attacks:
            enemy.attackTimers.add(PHASE_TRANSITION_LEAD)
            enemy.attackWarningFired.add(false)
          # Update boss color and apply phase modifiers
          enemy.color = phase.color
          # Apply phase speedMultiplier to wave-scaled base speed
          let scaledBaseSpeed = getScaledBossSpeed(bossDef, game.currentWave)
          let calculatedSpeed = scaledBaseSpeed * phase.speedMultiplier
          
          enemy.speed = calculatedSpeed
          enemy.defenseMultiplier = phase.defenseMultiplier  # Apply defense multiplier from phase
          break
        
      # Update boss behavior based on specialBehavior
      if enemy.currentPhaseIndex < bossDef.phases.len:
        let phase = bossDef.phases[enemy.currentPhaseIndex]
        # Slow boss 50% when close to the player so they aren't instantly overwhelmed
        const bossSlowRadius = 20.0
        let distToPlayer = distance(enemy.pos, game.player.pos)
        let savedSpeed = enemy.speed
        if distToPlayer < bossSlowRadius and not enemy.isDashing:
          enemy.speed *= 0.5
        updateCustomBossBehavior(game, enemy, phase, dt)
        enemy.speed = savedSpeed  # Always restore the real speed
      
      # Handle boss dash movement (overrides normal movement)
      if enemy.isDashing:
        enemy.dashDuration -= dt
        if enemy.dashDuration > 0:
          # Apply dash velocity
          enemy.pos = enemy.pos + enemy.dashVelocity * dt
          
          # Create dash trail particles ~15 times/sec regardless of fps
          if (enemy.dashDuration mod (1.0 / 15.0)) < dt:
            let trailColor = if enemy.currentPhaseIndex < bossDef.phases.len:
              bossDef.phases[enemy.currentPhaseIndex].color
            else:
              Red
            spawnExplosionPooled(game.particlePool, enemy.pos.x, enemy.pos.y, trailColor, 5)
        else:
          # Dash complete
          enemy.isDashing = false
          enemy.dashDuration = 0
          if enemy.currentPhaseIndex < bossDef.phases.len:
            let endColor = bossDef.phases[enemy.currentPhaseIndex].color
            spawnExplosionPooled(game.particlePool, enemy.pos.x, enemy.pos.y, endColor, 20)
      
      # Update attack timers
      for i in 0..<enemy.attackTimers.len:
        enemy.attackTimers[i] -= dt
      
      # Execute attacks when timers expire, emit pre-fire warning ~0.4 s before each shot
      if enemy.currentPhaseIndex < bossDef.phases.len:
        let phase = bossDef.phases[enemy.currentPhaseIndex]
        const WARNING_LEAD_TIME = 0.4'f32
        for i, attack in phase.attacks:
          if i < enemy.attackTimers.len:
            # Show pre-fire warning once per cycle — fires as soon as the timer
            # enters the warning window, regardless of cooldown length.
            # This works even when cooldown <= WARNING_LEAD_TIME.
            if enemy.attackTimers[i] <= WARNING_LEAD_TIME and
               not enemy.attackWarningFired[i]:
              addBossAttackWarning(game, enemy, attack)
              enemy.attackWarningFired[i] = true
            # Fire attack when timer reaches zero; reset for next cycle
            if enemy.attackTimers[i] <= 0:
              executeCustomBossAttack(game, enemy, attack, phase, bossDef)
              enemy.attackTimers[i] = attack.cooldown
              enemy.attackWarningFired[i] = false

    # Regular enemy shooting (config-driven system)
    if enemy.enemyType in [etCube, etHexagon, etOctagon, etPentagon, etPhantom, etDiamond, etMage]:
      let config = getEnemyConfig(enemy.enemyType)
      
      # Only shoot if enemy has ranged attack configured
      if config.hasRangedAttack:
        let attackConfig = config.attack
        
        # Check shoot timer
        if enemy.shootTimer > attackConfig.fireRate:
          let dir = (game.player.pos - enemy.pos).normalize()
          
          # Handle burst shooting
          if attackConfig.usesBurst:
            for i in 0..<attackConfig.burstCount:
              let spreadAngle = (i - (attackConfig.burstCount div 2)).float32 * attackConfig.spreadAngle
              let spreadDir = newVector2f(
                dir.x * cos(spreadAngle) - dir.y * sin(spreadAngle),
                dir.x * sin(spreadAngle) + dir.y * cos(spreadAngle)
              )
              
              let bullet = newBullet(
                x = enemy.pos.x,
                y = enemy.pos.y,
                direction = spreadDir,
                speed = attackConfig.bulletSpeed,
                damage = attackConfig.damage,
                fromPlayer = false,
                isHoming = attackConfig.homingStrength > 0,
                sourceEnemyId = enemy.id
              )
              
              # Apply special bullet properties
              if attackConfig.isPentagonBullet:
                bullet.radius = 10  # Larger pentagon bullet
              
              game.bullets.add(bullet)
          else:
            # Non-burst shooting
            for i in 0..<attackConfig.bulletCount:
              var shootDir: Vector2f
              
              if attackConfig.spreadAngle >= 6.0:  # Full circle (chaotic)
                # Random direction for chaotic enemies like Hexagon
                let angle = rand(1.0) * PI * 2.0
                shootDir = newVector2f(cos(angle), sin(angle))
              else:
                # Spread pattern
                let spreadAngle = (i - (attackConfig.bulletCount div 2)).float32 * attackConfig.spreadAngle
                shootDir = newVector2f(
                  dir.x * cos(spreadAngle) - dir.y * sin(spreadAngle),
                  dir.x * sin(spreadAngle) + dir.y * cos(spreadAngle)
                )
              
              # Add inaccuracy for Octagon
              if enemy.enemyType == etOctagon:
                let inaccuracy = (rand(1.0) - 0.5) * attackConfig.spreadAngle
                shootDir = newVector2f(
                  shootDir.x * cos(inaccuracy) - shootDir.y * sin(inaccuracy),
                  shootDir.x * sin(inaccuracy) + shootDir.y * cos(inaccuracy)
                )
              
              let bullet = newBullet(
                x = enemy.pos.x,
                y = enemy.pos.y,
                direction = shootDir,
                speed = attackConfig.bulletSpeed,
                damage = attackConfig.damage,
                fromPlayer = false,
                isHoming = attackConfig.homingStrength > 0,
                sourceEnemyId = enemy.id
              )
              
              # Apply special bullet properties
              if attackConfig.isPentagonBullet:
                bullet.radius = 10  # Larger pentagon bullet
              
              game.bullets.add(bullet)
          
          enemy.shootTimer = 0
    
    # Check collision with player (with small coyote/forgiveness zone on edges)
    # Reduce effective collision radius by 10% for slight edge forgiveness
    let effectivePlayerRadius = game.player.radius * 0.90  # 10% reduction = coyote
    if distance(enemy.pos, game.player.pos) < enemy.radius + effectivePlayerRadius:
      if enemy.isBoss:
        # Boss deals continuous damage
        if game.time - enemy.lastContactDamageTime >= 0.5:  # 2 HP per second
          var bossContactDamage = enemy.contactDamage.float32  # Use contactDamage instead of damage
          
          # Thorns reflection damage
          discard applyThornsReflection(game, game.player, bossContactDamage, enemy, "boss")
          
          let playerDied = takeDamage(game.player, bossContactDamage)
          
          # Pulse Armor shockwave when taking damage
          if not playerDied and hasPowerUp(game.player, puPulseArmor):
            let pulseLevel = getPowerUpLevel(game.player, puPulseArmor)
            # Check cooldown (1 second between shockwaves)
            if game.time - game.player.pulseArmorCooldown >= 1.0:
              # Shockwave parameters based on level
              let shockwaveRadius = case pulseLevel
                of 1: 100.0
                of 2: 150.0
                else: 200.0
              let shockwaveDamage = case pulseLevel
                of 1: 0.0
                of 2: 2.0
                else: 4.0
              let shockwaveForce = case pulseLevel
                of 1: 200.0
                of 2: 300.0
                else: 400.0
              
              # Apply shockwave to all enemies in radius
              for shockEnemy in game.enemies:
                let dist = distance(game.player.pos, shockEnemy.pos)
                if dist < shockwaveRadius:
                  # Knockback
                  let pushDir = (shockEnemy.pos - game.player.pos).normalize()
                  let bossResistance = if shockEnemy.isBoss: 0.2 else: 1.0
                  shockEnemy.pos.x += pushDir.x * shockwaveForce * 0.016 * bossResistance
                  shockEnemy.pos.y += pushDir.y * shockwaveForce * 0.016 * bossResistance
                  
                  # Clamp to screen boundaries - enemies can't be pushed through borders
                  shockEnemy.pos.x = clamp(shockEnemy.pos.x, shockEnemy.radius, game.screenWidth.float32 - shockEnemy.radius)
                  shockEnemy.pos.y = clamp(shockEnemy.pos.y, shockEnemy.radius, game.screenHeight.float32 - shockEnemy.radius)
                  
                  # Damage (only for level 2 and 3)
                  if shockwaveDamage > 0:
                    # Stars use hit counter for all damage sources
                    if shockEnemy.enemyType == etStar:
                      shockEnemy.hitCount += 1
                    else:
                      shockEnemy.hp -= shockwaveDamage
                    showDamage(game, shockEnemy.pos, shockwaveDamage, true, false, dtDefault)
              
              # Visual feedback - shockwave ring
              for i in 0..8:
                let angle = (i.float32 / 8.0) * PI * 2.0
                let particlePos = Vector2f(
                  x: game.player.pos.x + cos(angle) * shockwaveRadius,
                  y: game.player.pos.y + sin(angle) * shockwaveRadius
                )
                spawnExplosionPooled(game.particlePool, particlePos.x, particlePos.y,
                              Color(r: 150, g: 200, b: 255, a: 200), 5)
              
              game.player.pulseArmorCooldown = game.time
          
          if playerDied:
            game.state = gsGameOver
          
          # Track boss contact damage for statistics
          trackPlayerDamage(game, bossContactDamage, enemy.enemyType)
          
          # Create damage number for boss contact damage
          game.showDamage(game.player.pos, bossContactDamage, fromPlayer = false,
                          isCritical = false, damageType = dtDefault)
          
          playSound(stPlayerHit, 0.6)
          enemy.lastContactDamageTime = game.time
          spawnExplosionPooled(game.particlePool, game.player.pos.x, game.player.pos.y, Red, 10)
      else:
        # Regular enemies deal contact damage with cooldown (once every 0.5 seconds)
        if game.time - enemy.lastContactDamageTime >= 0.5:  # Contact damage cooldown
          var enemyContactDamage = enemy.contactDamage.float32  # Damage enemy deals to player
          
          # Venomous elite effect - applies poison to player
          # Handles multiple elite types (wave 25+)
          if enemy.isElite and etVenomous in enemy.eliteTypes:
            game.player.poisonTimer = 3.0  # 3 seconds of poison
            game.player.poisonDamage = 0.5  # 0.5 DPS = 1.5 total damage
            game.player.poisonAccumulator = 0.0  # Reset accumulator for new poison application
            spawnExplosionPooled(game.particlePool, game.player.pos.x, game.player.pos.y, Green, 10)
          
          # Thorns reflection damage - damages enemy but doesn't kill instantly
          discard applyThornsReflection(game, game.player, enemyContactDamage, enemy, "contact")
          
          let playerDied = takeDamage(game.player, enemyContactDamage)
          
          # Pulse Armor shockwave when taking damage
          if not playerDied and hasPowerUp(game.player, puPulseArmor):
            let pulseLevel = getPowerUpLevel(game.player, puPulseArmor)
            # Check cooldown (1 second between shockwaves)
            if game.time - game.player.pulseArmorCooldown >= 1.0:
              # Shockwave parameters based on level
              let shockwaveRadius = case pulseLevel
                of 1: 100.0
                of 2: 150.0
                else: 200.0
              let shockwaveDamage = case pulseLevel
                of 1: 0.0
                of 2: 2.0
                else: 4.0
              let shockwaveForce = case pulseLevel
                of 1: 200.0
                of 2: 300.0
                else: 400.0
              
              # Apply shockwave to all enemies in radius
              for shockEnemy in game.enemies:
                let dist = distance(game.player.pos, shockEnemy.pos)
                if dist < shockwaveRadius:
                  # Knockback
                  let pushDir = (shockEnemy.pos - game.player.pos).normalize()
                  let bossResistance = if shockEnemy.isBoss: 0.2 else: 1.0
                  shockEnemy.pos.x += pushDir.x * shockwaveForce * 0.016 * bossResistance
                  shockEnemy.pos.y += pushDir.y * shockwaveForce * 0.016 * bossResistance
                  
                  # Clamp to screen boundaries - enemies can't be pushed through borders
                  shockEnemy.pos.x = clamp(shockEnemy.pos.x, shockEnemy.radius, game.screenWidth.float32 - shockEnemy.radius)
                  shockEnemy.pos.y = clamp(shockEnemy.pos.y, shockEnemy.radius, game.screenHeight.float32 - shockEnemy.radius)
                  
                  # Damage (only for level 2 and 3)
                  if shockwaveDamage > 0:
                    # Stars use hit counter for all damage sources
                    if shockEnemy.enemyType == etStar:
                      shockEnemy.hitCount += 1
                    else:
                      shockEnemy.hp -= shockwaveDamage
                    showDamage(game, shockEnemy.pos, shockwaveDamage, true, false, dtDefault)
              
              # Visual feedback - shockwave ring
              for i in 0..8:
                let angle = (i.float32 / 8.0) * PI * 2.0
                let particlePos = Vector2f(
                  x: game.player.pos.x + cos(angle) * shockwaveRadius,
                  y: game.player.pos.y + sin(angle) * shockwaveRadius
                )
                spawnExplosionPooled(game.particlePool, particlePos.x, particlePos.y,
                              Color(r: 150, g: 200, b: 255, a: 200), 5)
              
              game.player.pulseArmorCooldown = game.time
          
          if playerDied:
            game.state = gsGameOver
          
          # Track enemy contact damage for statistics
          trackPlayerDamage(game, enemyContactDamage, enemy.enemyType)
          
          # Create damage number for player taking damage
          showDamage(game, game.player.pos, enemyContactDamage, false, false, dtDefault)
          
          playSound(stPlayerHit, 0.5)
          
          # Deal contact damage to enemy based on player damage stat, speed, and crits
          let (contactDamageToEnemy, contactWasCrit) = calculateContactDamageToEnemy(game.player, enemy)
          
          # Stars use hit counter for all damage sources
          if enemy.enemyType == etStar:
            enemy.hitCount += 1
          else:
            let actualContactDmg = damageEnemy(enemy, contactDamageToEnemy)
            discard actualContactDmg
          
          enemy.lastContactDamageTime = game.time
          
          # Accumulate damage for damage number display (shows every 0.5s)
          # Crits shown immediately and in the right color
          if contactWasCrit:
            showDamage(game, enemy.pos, contactDamageToEnemy, true, true, dtCritical)
          else:
            accumulateAndShowContactDamage(game, enemy, contactDamageToEnemy)
          
          # Visual feedback — more particles for crits
          let contactParticleCount = if contactWasCrit: 8 else: 3
          spawnExplosionPooled(game.particlePool, enemy.pos.x, enemy.pos.y, enemy.color, contactParticleCount)
          
          # Remove enemy if HP reaches 0
          if enemy.hp <= 0:
            # Flush any accumulated contact damage before death
            flushAccumulatedContactDamage(game, enemy)
            game.enemies.delete(enemyIdx)
            continue
    
    enemyIdx += 1
  
  # If boss was defeated in TIME SURVIVAL mode, trigger power-up selection
  # In WAVE mode, power-ups are only given between waves, not on boss defeat
  if bossDefeated and not shouldUseWaves(game.mode):
    # Time survival: offer regular upgrades after boss
    game.powerUpChoices = generatePowerUpChoices(game.player, false)
    game.selectedPowerUp = 0
    initPowerUpRollAnimation(game)
    game.state = gsPowerUpSelect
    # Clear all enemies and bullets for clean screen
    game.enemies = @[]
    game.bullets = @[]
  
  # Update boss satellites (persistent orbiting satellites)
  for enemy in game.enemies:
    if enemy.isBoss and enemy.satellites.len > 0:
      var i = enemy.satellites.len - 1
      while i >= 0:
        # Update orbit position using individual satellite rotation speed
        enemy.satellites[i].angle += dt * enemy.satellites[i].rotationSpeed
        enemy.satellites[i].pos.x = enemy.pos.x + cos(enemy.satellites[i].angle) * enemy.satellites[i].radius
        enemy.satellites[i].pos.y = enemy.pos.y + sin(enemy.satellites[i].angle) * enemy.satellites[i].radius
        
        # LASER TARGETING SYSTEM - Continuous lasers with player coordinate tracking
        enemy.satellites[i].shootTimer -= dt
        
        # Update laser charge/target system
        if enemy.satellites[i].shootTimer <= 0:
          if not enemy.satellites[i].laserActive:
            # Start charging laser - lock onto current player position
            enemy.satellites[i].laserActive = true
            enemy.satellites[i].laserTarget = game.player.pos
            enemy.satellites[i].laserChargeTime = 0.0
            enemy.satellites[i].shootTimer = 4.5 + rand(1.0)  # Time until next laser cycle
          else:
            # Laser cycle complete, deactivate and prepare for next shot
            enemy.satellites[i].laserActive = false
        
        # Laser active - warning phase then fire
        if enemy.satellites[i].laserActive:
          enemy.satellites[i].laserChargeTime += dt
          
          # OPTIMIZATION: Only calculate laser geometry every 3 frames during warning
          let shouldUpdateLaser = (game.frameCount mod 3 == 0) or (enemy.satellites[i].laserChargeTime >= 1.5)
          
          if shouldUpdateLaser:
            # Calculate direction through locked target position to screen edge
            let toTarget = (enemy.satellites[i].laserTarget - enemy.satellites[i].pos).normalize()
            let targetAngle = arctan2(toTarget.y, toTarget.x)
            
            # Calculate maximum laser length to reach screen edge
            # OPTIMIZATION: Cache this value per enemy instead of recalculating
            let maxScreenDist = sqrt(game.screenWidth.float32 * game.screenWidth.float32 +
                                     game.screenHeight.float32 * game.screenHeight.float32)
            
            # WARNING PHASE (first 1.5 seconds)
            if enemy.satellites[i].laserChargeTime < 1.5:
              # Update existing warning position to follow satellite, or create new one
              var warningFound = false
              for warning in game.attackWarnings:
                if warning.attackType == "satellite_laser" and
                   warning.sourceEnemyId == enemy.id and
                   warning.fromSatellite:
                  # Update warning position to follow satellite
                  warning.pos = enemy.satellites[i].pos
                  warningFound = true
                  break
              
              # Create new warning if doesn't exist
              if not warningFound:
                game.attackWarnings.add(newSatelliteLaserWarning(
                  enemy.satellites[i].pos.x,
                  enemy.satellites[i].pos.y,
                  enemy.satellites[i].laserTarget.x,
                  enemy.satellites[i].laserTarget.y,
                  1.5 - enemy.satellites[i].laserChargeTime,
                  enemy.id
                ))
            
            # FIRING PHASE (after warning)
            else:
              # OPTIMIZATION: Only create laser every 2 frames instead of every frame
              # Lasers last 2 frames so this maintains continuous beam appearance
              if game.frameCount mod 2 == 0:
                game.lasers.add(newLaser(
                  enemy.satellites[i].pos.x,
                  enemy.satellites[i].pos.y,
                  3,                    # direction: 3 = single rotated beam
                  maxScreenDist,        # length: extend all the way across screen
                  12.0,                 # thickness: visible laser beam
                  2,                    # damage
                  dt * 3.0,             # duration: 3 frames worth for smooth overlap
                  targetAngle,          # rotation: angle through target point
                  enemy.enemyType       # enemyType: track source
                ))
              
              # Visual feedback for laser firing - reduced frequency
              if game.frameCount mod 8 == 0:  # Reduced from every 2 frames to every 8
                spawnExplosionPooled(game.particlePool, enemy.satellites[i].pos.x, enemy.satellites[i].pos.y,
                              Color(r: 255, g: 200, b: 100, a: 255), 6)  # Smaller particles (6 instead of 8)
        
        # OPTIMIZATION: Bullet collision - only check if satellite is on screen
        var satelliteDestroyed = false
        let onScreen = enemy.satellites[i].pos.x > -50 and enemy.satellites[i].pos.x < game.screenWidth.float32 + 50 and
                       enemy.satellites[i].pos.y > -50 and enemy.satellites[i].pos.y < game.screenHeight.float32 + 50
        
        if onScreen:
          # OPTIMIZATION: Check only player bullets in spatial proximity
          for bullet in game.bullets:
            if bullet.fromPlayer:
              # Quick AABB check before distance calculation
              let dx = abs(bullet.pos.x - enemy.satellites[i].pos.x)
              let dy = abs(bullet.pos.y - enemy.satellites[i].pos.y)
              if dx < 25.0 and dy < 25.0:  # INCREASED from 20.0 to 25.0 (easier to hit)
                if dx * dx + dy * dy < 484.0:  # INCREASED from 225.0 to 484.0 (22.0 * 22.0 = 484, larger hitbox)
                  enemy.satellites[i].hp -= 1
                  spawnExplosionPooled(game.particlePool, enemy.satellites[i].pos.x, enemy.satellites[i].pos.y,
                                Color(r: 255, g: 150, b: 0, a: 255), 6)  # Smaller (6 instead of 8)
                  if enemy.satellites[i].hp <= 0:
                    # Satellite destroyed!
                    spawnExplosionPooled(game.particlePool, enemy.satellites[i].pos.x, enemy.satellites[i].pos.y,
                                  Red, 20)  # Smaller (20 instead of 25)
                    playSound(stEnemyDeath, 0.4)
                    enemy.satellites.delete(i)
                    satelliteDestroyed = true
                    break
        
        if not satelliteDestroyed:
          i -= 1
        else:
          # Already deleted, continue
          i -= 1
  
  # Update bullets
  i = 0
  while i < game.bullets.len:
    let bullet = game.bullets[i]
    
    # Homing bullet logic
    if bullet.isHoming:
      if bullet.fromPlayer and game.enemies.len > 0:
        # Player homing bullets track enemies (LEGENDARY - Single Level)
        # HEAVY NERF: Much shorter tracking range and weaker turn rate
        let trackingRange = 120.0
        
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
          let turnRate = 0.02  # NERFED from 0.05
          
          let toEnemy = (nearestEnemy.pos - bullet.pos).normalize()
          let currentDir = bullet.vel.normalize()
          let newDir = (currentDir * (1.0 - turnRate) + toEnemy * turnRate).normalize()
          bullet.vel = newDir * bullet.vel.length()
      
      elif not bullet.fromPlayer:
        # Enemy homing bullets track the player (etMage magic bullets)
        let trackingRange = 400.0  # Longer range for enemy homing
        let dist = distance(bullet.pos, game.player.pos)
        
        if dist < trackingRange:
          # Gentle tracking strength for enemy bullets - dodgeable
          let turnRate = 0.0075  # Reduced from 0.02 - very gentle curve
          
          let toPlayer = (game.player.pos - bullet.pos).normalize()
          let currentDir = bullet.vel.normalize()
          let newDir = (currentDir * (1.0 - turnRate) + toPlayer * turnRate).normalize()
          bullet.vel = newDir * bullet.vel.length()

    # Use effectiveDt for enemy bullets (slowed by Time Warp), normal dt for player bullets
    let bulletDt = if bullet.fromPlayer: dt else: effectiveDt
    
    # Nova: frozen player bullets don't move or expire
    if bullet.isFrozenByNova and bullet.fromPlayer:
      i += 1
      continue
    
    if not updateBullet(bullet, bulletDt) or isOffScreen(bullet, game.screenWidth, game.screenHeight):
      # Track bullet despawn (missed shot) for player bullets only
      if bullet.fromPlayer:
        trackBulletDespawn(game, bullet, false)
      game.bullets.delete(i)
      continue
    
    if bullet.fromPlayer and bullet.isExplosive and not bullet.isEcho:
      let level = getPowerUpLevel(game.player, puExplosiveBullets)
      # Accumulator-based spawning: no rand() call per frame, deterministic interval
      let spawnInterval = case level
        of 1: 0.20   # 5 spawns/sec
        of 2: 0.13   # ~7.5 spawns/sec
        else: 0.10   # 10 spawns/sec
      let particleCount = case level
        of 1: 2
        of 2: 2
        else: 3
      bullet.particleTrailTimer += bulletDt
      if bullet.particleTrailTimer >= spawnInterval:
        bullet.particleTrailTimer -= spawnInterval
        spawnTrailParticlePooled(game.particlePool, bullet.pos.x, bullet.pos.y,
                                 Color(r: 255, g: 150, b: 50, a: 200), particleCount)
    
    # Update sourceEnemyPos to track the enemy's current position
    # This ensures parried bullets go to where the enemy last was, not where it shot from
    if not bullet.fromPlayer and bullet.sourceEnemyId >= 0:
      for enemy in game.enemies:
        if enemy.id == bullet.sourceEnemyId:
          bullet.sourceEnemyPos = enemy.pos
          break
    
    # Echo Shots - spawn ghost trail bullets (LEGENDARY)
    if bullet.fromPlayer and not bullet.isEcho and hasPowerUp(game.player, puEchoShots):
      # Ensure parent bullet has an ID for tracking
      if bullet.bulletId == 0:
        assignBulletId(game, bullet)
      
      bullet.echoTrailTimer += bulletDt
      
      let spawnInterval = 0.05  # Was 0.08 - now spawns 60% faster
      let echoDamageMultiplier = 0.60  # Was 0.40 - now deals 60% damage
      
      if bullet.echoTrailTimer >= spawnInterval:
        bullet.echoTrailTimer = 0.0
        
        # Create echo bullet
        createEchoBullet(game, bullet, echoDamageMultiplier, 0.7, 0.7)

    # Check rotating shield collision
    if not bullet.fromPlayer and hasPowerUp(game.player, puRotatingShield):
      let level = getPowerUpLevel(game.player, puRotatingShield)
      let shieldCount = 3  # Always 3 shields regardless of level
      let shieldRadius = game.player.radius * 2.5 + 15  # Reduced from +15 to +10
      var hitShield = false
      var hitShieldIndex = -1

      # Level-based coverage
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
            spawnExplosionPooled(game.particlePool, shieldX, shieldY, Color(r: 0, g: 255, b: 255, a: 255), 8)  # Cyan explosion
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
            # Overcharge: Bullets gain damage based on distance traveled
            # +1.5% damage per 10 units traveled, up to +150% at 1000 units
            # Formula: damage * (1 + min(travelDistance * 0.0015, 1.5))
            # Examples:
            #   - 100 units = +15% damage (1.15x)
            #   - 500 units = +75% damage (1.75x)
            #   - 1000+ units = +150% damage (2.5x, 2.5x damage!)
            
            let damagePerUnit = 0.0015  # 0.15% per unit, 1.5% per 10 units
            let maxBonus = 1.5  # Max +150% damage (2.5x total)
            let bonusMultiplier = min(bullet.travelDistance * damagePerUnit, maxBonus)
            
            finalDamage = bullet.damage * (1.0 + bonusMultiplier)
            overchargeExtraDamage = finalDamage - bullet.damage
          
          # Use the bullet's stored crit status (rolled when bullet was created)
          let isCrit = bullet.wasCrit
          
          if game.enemies[j].enemyType == etStar:
            # Stars use hit counter
            game.enemies[j].hitCount += 1
          else:
            # Apply elite modifiers to damage
            var actualDamage = finalDamage
            
            # Higher defenseMultiplier = MORE defense (takes LESS damage)
            # 0.5 = half defense (takes 2x damage), 1.0 = normal, 2.0 = double defense (takes 0.5x damage)
            if game.enemies[j].isBoss and game.enemies[j].defenseMultiplier > 0:
              actualDamage /= game.enemies[j].defenseMultiplier
            
            # Tank elite: 50% damage reduction
            # Handles multiple elite types
            if game.enemies[j].isElite and etTank in game.enemies[j].eliteTypes:
              actualDamage *= 0.5  # 50% damage taken
            
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
            
            # Diamond enemy: 1-hit shield absorbs the first bullet entirely (like Celestial Veil)
            if game.enemies[j].enemyType == etDiamond and game.enemies[j].diamondShieldActive:
              game.enemies[j].diamondShieldActive = false
              shieldDamage += actualDamage
              actualDamage = 0
            
            game.enemies[j].hp -= actualDamage
            
            # Volatile: enemies with 2+ active DoTs take +50% bullet damage
            var volatileBonusDamage = 0.0
            if game.player.hasVolatile and bullet.fromPlayer:
              var activeEffectCount = 0
              for et, ae in game.enemies[j].activeEffects:
                if ae.primary.isActive:
                  activeEffectCount += 1
              if activeEffectCount >= 2:
                volatileBonusDamage = actualDamage * 0.5
                game.enemies[j].hp -= volatileBonusDamage
                trackPowerUpDamage(game, puVolatile, volatileBonusDamage)
                showDamage(game, game.enemies[j].pos, volatileBonusDamage, true, false, dtArcane)
            
            # Resonance: bullets hitting DoT enemies deal bonus damage equal to % of combined DPS
            var resonanceBonusDamage = 0.0
            if game.player.resonanceLevel > 0 and bullet.fromPlayer:
              var totalDoTDps = 0.0
              for et, ae in game.enemies[j].activeEffects:
                if ae.primary.isActive:
                  totalDoTDps += ae.primary.damagePerSec
              if totalDoTDps > 0:
                let resonancePct = case game.player.resonanceLevel
                  of 1: 0.20
                  of 2: 0.30
                  else: 0.40
                resonanceBonusDamage = totalDoTDps * resonancePct
                game.enemies[j].hp -= resonanceBonusDamage
                trackPowerUpDamage(game, puResonance, resonanceBonusDamage)
                showDamage(game, game.enemies[j].pos, resonanceBonusDamage, true, false, dtPoison)
            
            # Giant Slayer: Deal % of enemy current HP as bonus damage
            var giantSlayerDamage = 0.0
            if hasPowerUp(game.player, puGiantSlayer):
              let giantSlayerLevel = getPowerUpLevel(game.player, puGiantSlayer)
              let percentDamage = case giantSlayerLevel
                of 1: 0.01  # 1% of current HP
                of 2: 0.0175  # 1.75% of current HP
                else: 0.025  # 2.5% of current HP
              
              giantSlayerDamage = game.enemies[j].hp * percentDamage
              
              # Apply elite modifiers to Giant Slayer damage too
              if game.enemies[j].isBoss and game.enemies[j].defenseMultiplier > 0:
                giantSlayerDamage /= game.enemies[j].defenseMultiplier
              
              # Tank elite: 50% damage reduction
              if game.enemies[j].isElite and etTank in game.enemies[j].eliteTypes:
                giantSlayerDamage *= 0.5  # 50% damage taken
              
              # Shielded elite: Giant Slayer damage goes through shield to HP
              game.enemies[j].hp -= giantSlayerDamage
              
              # Track Giant Slayer damage contribution
              trackPowerUpDamage(game, puGiantSlayer, giantSlayerDamage)
              
              # Show Giant Slayer damage number in distinct color (purple/arcane)
              if giantSlayerDamage > 0:
                showDamage(game, game.enemies[j].pos, giantSlayerDamage, true, false, dtArcane)
            
            # Track bullet hit for statistics (now includes Giant Slayer damage)
            trackBulletHit(game, bullet, game.enemies[j], actualDamage + shieldDamage + giantSlayerDamage)
            
            # Track damage for real-time DPS display
            recordDamage(game.dopamine.realTimeStats, actualDamage + shieldDamage + giantSlayerDamage, game.time)
            
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
            
            # Track Special Rounds contribution (bonus damage from every Nth bullet)
            if bullet.isSpecialRound:
              # Special rounds deal 1.5x damage, so the bonus is 0.5x of final damage
              # Calculate: baseDamage * 1.5 = actualDamage, so baseDamage = actualDamage / 1.5
              # Bonus = actualDamage - baseDamage = actualDamage - (actualDamage / 1.5) = actualDamage * (1 - 1/1.5) = actualDamage * 0.333
              let specialRoundsBonusDamage = actualDamage * 0.333
              trackPowerUpDamage(game, puSpecialRounds, specialRoundsBonusDamage)
            
            # Track Wall Turrets contribution (all damage from turret-fired bullets)
            if bullet.isFromWallTurret:
              trackPowerUpDamage(game, puWallTurrets, actualDamage)
            
            # Track Radial Burst contribution (all damage from Radial Burst bullets)
            if bullet.isFromRadialBurst:
              trackPowerUpDamage(game, puRadialBurst, actualDamage)
            
            # Track Critical Hit contribution (bonus damage from crits)
            if bullet.wasCrit and hasPowerUp(game.player, puCriticalHit):
              # Crit multiplier is 2x, so bonus is exactly half the post-crit damage
              let critBonusDamage = actualDamage * 0.5
              trackPowerUpDamage(game, puCriticalHit, critBonusDamage)
            
            # Track Piercing Shots contribution (2nd+ hits are entirely powered by the power-up)
            if bullet.piercedEnemies > 0 and hasPowerUp(game.player, puPiercingShots):
              trackPowerUpDamage(game, puPiercingShots, actualDamage)
            
            # Track Echo Shots contribution (all echo bullet damage)
            if bullet.isEcho:
              trackPowerUpDamage(game, puEchoShots, actualDamage)
            
            # Track Bullet Split contribution (all split bullet damage)
            if bullet.isFromBulletSplit:
              trackPowerUpDamage(game, puBulletSplit, actualDamage)
            
            # Track Bullet Ricochet contribution (all ricochet bullet damage)
            if bullet.isRicochet:
              trackPowerUpDamage(game, puBulletRicochet, actualDamage)
            
            # Track Parry contribution (all parried bullet damage)
            if bullet.isParried:
              trackPowerUpDamage(game, puParry, actualDamage)
            
            # Create damage number for shield damage (blue colored for shields)
            if shieldDamage > 0:
              showDamage(game, game.enemies[j].pos, shieldDamage, true, isCrit, dtLaser)
            
            # Create damage number for HP damage (player damage to enemy) - only if damage was dealt
            if actualDamage > 0:
              let bulletDmgType = getBulletDamageType(bullet)
              showDamage(game, game.enemies[j].pos, actualDamage, true, isCrit, bulletDmgType)
          hitEnemy = true
          
          # Remove all echo trail bullets when main bullet hits an enemy
          # This prevents the entire trail from stacking damage on one target
          if not bullet.isEcho and bullet.bulletId > 0:
            # Remove all echo children of this bullet
            var k = 0
            while k < game.bullets.len:
              if game.bullets[k].isEcho and game.bullets[k].parentBulletId == bullet.bulletId:
                game.bullets.delete(k)
                # Don't increment k since we removed an element
              else:
                k += 1
          
          # Heavy Rounds knockback effect
          if hasPowerUp(game.player, puHeavyRounds):
            let heavyLevel = getPowerUpLevel(game.player, puHeavyRounds)
            let knockbackForce = case heavyLevel
              of 1: 50.0   # Slight knockback
              of 2: 100.0  # Increased knockback
              else: 150.0  # Strong knockback
            
            # Calculate knockback direction (away from bullet trajectory)
            let pushDir = bullet.vel.normalize()
            let bossResistance = if game.enemies[j].isBoss: 0.2 else: 1.0
            
            # Apply knockback to enemy
            game.enemies[j].pos.x += pushDir.x * knockbackForce * 0.016 * bossResistance
            game.enemies[j].pos.y += pushDir.y * knockbackForce * 0.016 * bossResistance
            
            # Clamp to screen boundaries - enemies can't be pushed through borders
            game.enemies[j].pos.x = clamp(game.enemies[j].pos.x, game.enemies[j].radius, game.screenWidth.float32 - game.enemies[j].radius)
            game.enemies[j].pos.y = clamp(game.enemies[j].pos.y, game.enemies[j].radius, game.screenHeight.float32 - game.enemies[j].radius)
          
          # Special Rounds stun effect
          if bullet.isSpecialRound:
            # Apply brief stun (80% slow for 0.5 seconds)
            let stunDuration = 0.5
            let baseStunAmount = 0.8  # 80% slow
            let stunAmount = baseStunAmount * (1.0 - game.enemies[j].debuffResistance)
            game.enemies[j].slowTimer = stunDuration
            game.enemies[j].slowAmount = max(game.enemies[j].slowAmount, stunAmount)
            
            # Visual feedback - extra particles in gold color
            spawnExplosionPooled(game.particlePool, bullet.pos.x, bullet.pos.y,
                          Color(r: 255, g: 215, b: 0, a: 255), 15)
          
          # UNIFIED BULLET EFFECT SYSTEM
          applyBulletEffects(game, bullet, game.enemies[j], dt)
          
          # Bullet split on hit - SYNERGY: Inherits ALL bullet properties
          if hasPowerUp(game.player, puBulletSplit) and not bullet.hasSplit:
            let splitLevel = getPowerUpLevel(game.player, puBulletSplit)
            let splitCount = splitLevel + 1  # 2, 3, or 4 bullets
            
            createSplitBullets(game, bullet, splitCount, 0.5, 0.7)
          
          # Impact particles
          spawnExplosionPooled(game.particlePool, bullet.pos.x, bullet.pos.y,
                        game.enemies[j].color, 5)
          
          # Explosive bullets create area damage
          if bullet.isExplosive:
            playSound(stExplosion, 0.5)
            let level = getPowerUpLevel(game.player, puExplosiveBullets)
            let explosionRadius = getExplosionRadius(level)
            
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
                  showDamage(game, game.enemies[k].pos, actualDamage, true, isCrit, dtExplosion)
            
            # Level-based visual scaling similar to satellites
            case level
            of 1:
              # Basic explosion - single nova burst
              spawnNovaExplosionPooled(game.particlePool, bullet.pos.x, bullet.pos.y,
                                       explosionRadius, Orange, Yellow)
              spawnShockwavePooled(game.particlePool, bullet.pos.x, bullet.pos.y, explosionRadius)
            of 2:
              spawnNovaExplosionPooled(game.particlePool, bullet.pos.x, bullet.pos.y,
                                       explosionRadius, Orange, Yellow)
              spawnExplosiveRingPooled(game.particlePool, bullet.pos.x, bullet.pos.y,
                                       explosionRadius, 3, Color(r: 255, g: 180, b: 0, a: 255))
              spawnShockwavePooled(game.particlePool, bullet.pos.x, bullet.pos.y, explosionRadius)
            of 3:
              # Maximum explosion - nova + rings + spiral (satellite-like complexity)
              spawnNovaExplosionPooled(game.particlePool, bullet.pos.x, bullet.pos.y,
                                       explosionRadius, Orange, Yellow)
              spawnExplosiveRingPooled(game.particlePool, bullet.pos.x, bullet.pos.y,
                                       explosionRadius, 4, Color(r: 255, g: 180, b: 0, a: 255))
              spawnSpiralExplosionPooled(game.particlePool, bullet.pos.x, bullet.pos.y,
                                         explosionRadius, 6, Color(r: 255, g: 100, b: 0, a: 255))
              spawnShockwavePooled(game.particlePool, bullet.pos.x, bullet.pos.y, explosionRadius)
            else:
              # Fallback to basic
              spawnExplosionPooled(game.particlePool, bullet.pos.x, bullet.pos.y, Orange, 35)
              spawnExplosionPooled(game.particlePool, bullet.pos.x, bullet.pos.y, Yellow, 20)
              spawnShockwavePooled(game.particlePool, bullet.pos.x, bullet.pos.y, explosionRadius)
          
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
                bullet.isRicochet = true  # Mark for statistics tracking
                
                # Reduce damage by 25% per ricochet
                bullet.damage = bullet.damage * 0.75
                
                # SYNERGY: Reset split flag so ricochet bullets can split again on next hit
                if hasPowerUp(game.player, puBulletSplit):
                  bullet.hasSplit = false
                
                hitEnemy = false  # Don't delete bullet
                spawnExplosionPooled(game.particlePool, bullet.pos.x, bullet.pos.y, Yellow, 8)
              else:
                hitEnemy = true
            else:
              hitEnemy = true
          
          if hitEnemy:
            break
    else:
      # Enemy bullet hitting player
      if checkBulletPlayerCollision(bullet, game.player):
        # Parry - bounce bullets back
        if game.player.parryActive:
          # Bounce toward the enemy that shot the bullet
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
          
          # If source enemy is dead, use the position where bullet was shot from
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
          bullet.isParried = true  # Mark for statistics tracking
          
          # Visual effect for parry bounce
          spawnExplosionPooled(game.particlePool, bullet.pos.x, bullet.pos.y,
                        Color(r: 255, g: 255, b: 200, a: 255), 12)
          
          # Bullet continues bouncing, don't delete it
          i += 1
          continue
        
        var bulletDamage = bullet.damage
        
        # Thorns reflection - damage the originating enemy (the one that shot the bullet)
        if hasPowerUp(game.player, puThorns):
          # Find the enemy that shot this bullet using sourceEnemyId
          var sourceEnemy: Enemy = nil
          for enemy in game.enemies:
            if enemy.id == bullet.sourceEnemyId:
              sourceEnemy = enemy
              break
          
          if sourceEnemy != nil:
            discard applyThornsReflection(game, game.player, bulletDamage, sourceEnemy, "bullet")
        
        if takeDamage(game.player, bulletDamage):
          game.state = gsGameOver
        else:
          # Pulse Armor shockwave when taking damage from bullets
          if hasPowerUp(game.player, puPulseArmor):
            let pulseLevel = getPowerUpLevel(game.player, puPulseArmor)
            # Check cooldown (1 second between shockwaves)
            if game.time - game.player.pulseArmorCooldown >= 1.0:
              # Shockwave parameters based on level
              let shockwaveRadius = case pulseLevel
                of 1: 100.0
                of 2: 150.0
                else: 200.0
              let shockwaveDamage = case pulseLevel
                of 1: 0.0
                of 2: 2.0
                else: 4.0
              let shockwaveForce = case pulseLevel
                of 1: 200.0
                of 2: 300.0
                else: 400.0
              
              # Apply shockwave to all enemies in radius
              for shockEnemy in game.enemies:
                let dist = distance(game.player.pos, shockEnemy.pos)
                if dist < shockwaveRadius:
                  # Knockback
                  let pushDir = (shockEnemy.pos - game.player.pos).normalize()
                  let bossResistance = if shockEnemy.isBoss: 0.2 else: 1.0
                  shockEnemy.pos.x += pushDir.x * shockwaveForce * 0.016 * bossResistance
                  shockEnemy.pos.y += pushDir.y * shockwaveForce * 0.016 * bossResistance
                  
                  # Clamp to screen boundaries - enemies can't be pushed through borders
                  shockEnemy.pos.x = clamp(shockEnemy.pos.x, shockEnemy.radius, game.screenWidth.float32 - shockEnemy.radius)
                  shockEnemy.pos.y = clamp(shockEnemy.pos.y, shockEnemy.radius, game.screenHeight.float32 - shockEnemy.radius)
                  
                  # Damage (only for level 2 and 3)
                  if shockwaveDamage > 0:
                    # Stars use hit counter for all damage sources
                    if shockEnemy.enemyType == etStar:
                      shockEnemy.hitCount += 1
                    else:
                      shockEnemy.hp -= shockwaveDamage
                    showDamage(game, shockEnemy.pos, shockwaveDamage, true, false, dtDefault)
              
              # Visual feedback - shockwave ring
              for i in 0..8:
                let angle = (i.float32 / 8.0) * PI * 2.0
                let particlePos = Vector2f(
                  x: game.player.pos.x + cos(angle) * shockwaveRadius,
                  y: game.player.pos.y + sin(angle) * shockwaveRadius
                )
                spawnExplosionPooled(game.particlePool, particlePos.x, particlePos.y,
                              Color(r: 150, g: 200, b: 255, a: 200), 5)
              
              game.player.pulseArmorCooldown = game.time
        
        # Track bullet damage for statistics
        var sourceEnemyType = etCircle
        if bullet.sourceEnemyId >= 0:
          for enemy in game.enemies:
            if enemy.id == bullet.sourceEnemyId:
              sourceEnemyType = enemy.enemyType
              break
        trackPlayerDamage(game, bulletDamage, sourceEnemyType)
        
        # Create damage number (enemy to player)
        # Determine bullet damage type based on bullet properties
        var bulletDamageType = dtDefault
        if bullet.isBossBullet:
          bulletDamageType = dtCritical  # Boss bullets use yellow/critical color
        elif bullet.isPentagon:
          bulletDamageType = dtLaser  # Pentagon bullets use purple/laser color
        
        showDamage(game, game.player.pos, bulletDamage, false, false, bulletDamageType)
        
        hitEnemy = true
        spawnExplosionPooled(game.particlePool, bullet.pos.x, bullet.pos.y, Red, 8)
    
    # Check bullet-wall collision (enemy bullets)
    if not bullet.fromPlayer:
      for wall in game.walls:
        if checkBulletWallCollision(bullet, wall):
          hitEnemy = true
          wall.takeDamage(bullet.damage)  # Full bullet damage
          trackWallDamaged(game)
          # Show wall damage number (red to indicate enemy damage to structures)
          showDamage(game, bullet.pos, bullet.damage, fromPlayer = false,
                     isCritical = false, damageType = dtDefault)
          spawnExplosionPooled(game.particlePool, bullet.pos.x, bullet.pos.y, Brown, 4)
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
      
      # Check collision with player while falling
      if distance(meteorite.pos, game.player.pos) < meteorite.radius + game.player.radius:
        if takeDamage(game.player, meteorite.damage.float32):
          game.state = gsGameOver
        
        # Track meteorite damage
        trackPlayerDamage(game, meteorite.damage.float32, etMage)
        
        # Create damage number
        showDamage(game, game.player.pos, meteorite.damage.float32, false, false, dtExplosion)
        
        playSound(stPlayerHit, 0.6)
        
        # Create explosion effect
        spawnExplosionPooled(game.particlePool, meteorite.pos.x, meteorite.pos.y, Orange, 25)
        
        # Remove meteorite after hitting player
        game.meteorites.delete(i)
        continue
      
      # Check if meteorite reached target (or went past it)
      let distToTarget = distance(meteorite.pos, meteorite.targetPos)
      if distToTarget < 20.0 or meteorite.pos.y > meteorite.targetPos.y:
        # Meteorite impact at ground - use appropriate color based on damage
        let impactColor = if meteorite.damage.float > 50.0:
          Color(r: 255, g: 50, b: 0, a: 255)   # Dark orange for apocalypse
        elif meteorite.damage.float > 30.0:
          Color(r: 255, g: 100, b: 0, a: 255)  # Orange for massive impact
        else:
          Color(r: 255, g: 150, b: 50, a: 255) # Default peachy orange
        # Create explosion effect with appropriate color
        spawnExplosionPooled(game.particlePool, meteorite.pos.x, meteorite.pos.y, impactColor, 25)
        
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
      
      # Add subtle particle trail for magnet effect
      spawnTimedParticlesPooled(game.particlePool, game.coins[i].pos.x, game.coins[i].pos.y, 18.0,
                         Color(r: 255, g: 215, b: 0, a: 150), 1, dt)
    
    # Magnet effect from consumable
    if game.player.magnetTimer > 0:
      moveCoinToPlayer(game.coins[i], game.player.pos, dt)
    
    # Collect coin on contact
    if checkPlayerCollision(game.coins[i], game.player):
      let isBossCoin = game.coins[i].isBossCoin
      # Apply Greed multiplier and Double Coin multiplier (they stack)
      var coinValue = game.coins[i].value
      if hasPowerUp(game.player, puLuckyCoins):
        coinValue *= 2
      if game.player.doubleCoinTimer > 0:
        coinValue *= 2
      game.player.coins += coinValue
      
      # Track coin pickup for statistics
      trackCoinPickup(game, coinValue)
      
      recordCoin(game.dopamine.realTimeStats, game.dopamine.currentTime)
      recordCoin(game.dopamine.waveStats)
      if game.player.coins >= 1000:
        discard unlockAchievement(game.dopamine.achievements, "wealthy")
      
      playSound(stCoinPickup, if isBossCoin: 0.8 else: 0.5)
      # Boss coins have red particles, regular coins have gold
      let coinParticleColor = if isBossCoin: Color(r: 255, g: 50, b: 50, a: 255) else: Gold
      spawnExplosionPooled(game.particlePool, game.coins[i].pos.x, game.coins[i].pos.y, coinParticleColor, if isBossCoin: 20 else: 6)
      
      # If this was a boss coin, end the boss wave and advance
      if isBossCoin and game.bossWaveManager.isBossCoinActive():
        game.bossWaveManager.bossCoinCollected()
        if shouldUseWaves(game.mode):
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
    
    # Check if consumable is in player's collection aura (auto-collect)
    if isInPlayerAura(game.consumables[i], game.player):
      # Pull consumable toward player with magnet animation
      moveConsumableToPlayer(game.consumables[i], game.player.pos, dt)
      
      # Add subtle particle trail for magnet effect
      spawnTimedParticlesPooled(game.particlePool, game.consumables[i].pos.x, game.consumables[i].pos.y,
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
        # Double coin multiplier applies here
        let coinValue = if game.player.doubleCoinTimer > 0: 10 else: 5
        game.player.coins += coinValue
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
      of ctShieldBoost:
        game.player.shieldBoostTimer = 10.0
        game.player.shieldHits = 2  # Absorbs 2 hits
      of ctDoubleCoin:
        game.player.doubleCoinTimer = 10.0  # 10 seconds of double coins
      of ctDamageBoost:
        game.player.damageBoostTimer = 10.0
      of ctLifesteal:
        game.player.lifestealTimer = 15.0
      
      let particleColor = case game.consumables[i].consumableType
        of ctHealth: Green
        of ctCoin: Gold
        of ctSpeed: Cyan
        of ctInvincibility: Magenta
        of ctFireRate: Orange
        of ctMagnet: Purple
        of ctShieldBoost: Cyan
        of ctDoubleCoin: Color(r: 255, g: 223, b: 0, a: 255)
        of ctDamageBoost: Color(r: 255, g: 69, b: 0, a: 255)
        of ctLifesteal: Color(r: 139, g: 0, b: 0, a: 255)
      
      spawnExplosionPooled(game.particlePool, game.consumables[i].pos.x, game.consumables[i].pos.y,
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
      spawnExplosionPooled(game.particlePool, game.walls[i].pos.x, game.walls[i].pos.y, Brown, 20)
      game.walls.delete(i)
      continue
    
    # Wall Turrets power-up - walls shoot at enemies
    if hasPowerUp(game.player, puWallTurrets):
      game.walls[i].shootTimer -= dt
      if game.walls[i].shootTimer <= 0:
        # Find nearest enemy
        var nearestEnemy: Enemy = nil
        var nearestDist = 999999.0
        for enemy in game.enemies:
          let dist = distance(game.walls[i].pos, enemy.pos)
          if dist < nearestDist and dist < 400.0:  # 400px range
            nearestDist = dist
            nearestEnemy = enemy
        
        # Shoot at nearest enemy
        if nearestEnemy != nil:
          let direction = (nearestEnemy.pos - game.walls[i].pos).normalize()
          
          # Calculate turret damage based on Fortify level and player damage scaling
          var turretDamage = 1.0
          if hasPowerUp(game.player, puWallMaster):
            let fortifyLevel = getPowerUpLevel(game.player, puWallMaster)
            turretDamage = case fortifyLevel
              of 1: 1.5  # +50% damage
              of 2: 2.0  # +100% damage
              else: 3.0  # +200% damage
          
          # Add damage scaling from player damage
          let damageScaling = game.player.damage * 0.3
          turretDamage += damageScaling
          
          game.bullets.add(newBullet(
            x = game.walls[i].pos.x,
            y = game.walls[i].pos.y,
            direction = direction,
            speed = 350.0,
            damage = turretDamage,
            fromPlayer = true,  # Count as player damage for scoring
            isHoming = false,
            isPiercing = false,
            isExplosive = false,
            hasBounce = false,
            canSplit = false,
            slowAmount = 0.0,
            poisonDuration = 0.0,
            fireDuration = 0.0,
            windPushForce = 0.0,
            bulletSkin = game.player.bulletSkinType,
            bulletShape = game.player.bulletShapeType,
            isFromWallTurret = true
          ))
          
          # Visual feedback
          spawnExplosionPooled(game.particlePool, game.walls[i].pos.x, game.walls[i].pos.y,
                        Color(r: 255, g: 200, b: 100, a: 255), 8)
          
          game.walls[i].shootTimer = 1.5  # 1.5 second cooldown
    
    i += 1
  
  # Update particles
  updateParticlePool(game.particlePool, dt)
  
  # Update damage numbers
  i = 0
  while i < game.damageNumbers.len:
    if not updateDamageNumber(game.damageNumbers[i], dt):
      game.damageNumbers.delete(i)
      continue
    i += 1
  
  # This catches edge cases where HP reaches 0 but game didn't transition to game over
  if game.player.hp <= 0 and game.state == gsPlaying:
    game.state = gsGameOver

proc drawGame*(game: Game) =
  # Calculate screen shake offset
  var shakeOffsetX: float32 = 0
  var shakeOffsetY: float32 = 0
  
  let shakeOffset = getShakeOffset(game.dopamine.screenShake)
  shakeOffsetX = shakeOffset.x
  shakeOffsetY = shakeOffset.y
  
  if shakeOffsetX != 0 or shakeOffsetY != 0:
    
    # Apply shake using Camera2D
    var camera = Camera2D(
      offset: Vector2(x: game.screenWidth.float32 / 2.0 + shakeOffsetX,
                     y: game.screenHeight.float32 / 2.0 + shakeOffsetY),
      target: Vector2(x: game.screenWidth.float32 / 2.0,
                     y: game.screenHeight.float32 / 2.0),
      rotation: 0,
      zoom: 1.0
    )
    beginMode2D(camera)
  
  # Update and draw OS-style background
  let dt = getFrameTime()
  updateOSBackground(game.osBackground, dt, game.player.hp, game.player.maxHp,
                     game.bossWaveManager.isBossActive())
  drawOSBackground(game.osBackground, game.screenWidth, game.screenHeight)
  
  # Draw particles first (background layer)
  drawParticlePool(game.particlePool)

  # Draw lightning bolt arcs (chain lightning visuals, short-lived)
  drawLightningBolts(game)

  # Draw attack warnings (before everything else so they're visible)
  for warning in game.attackWarnings:
    drawAttackWarning(warning)
  
  # Draw lasers (after warnings, before walls for visual layering)
  for laser in game.lasers:
    drawLaser(laser)
  
  # Draw meteorites (show both warning and falling meteorites)
  for meteorite in game.meteorites:
    if meteorite.warningTimer > 0:
      # Draw warning indicator at target position (flashing)
      let warningAlpha = if (meteorite.warningTimer * 6.0).int mod 2 == 0: uint8(200) else: uint8(100)
      drawCircleLines(meteorite.targetPos.x.int32, meteorite.targetPos.y.int32, meteorite.radius,
                     Color(r: 255, g: 100, b: 0, a: warningAlpha))
      drawCircleLines(meteorite.targetPos.x.int32, meteorite.targetPos.y.int32, meteorite.radius + 5,
                     Color(r: 255, g: 50, b: 0, a: warningAlpha div 2))
    else:
      # Draw falling meteorite
      drawCircle(Vector2(x: meteorite.pos.x, y: meteorite.pos.y), meteorite.radius,
                Color(r: 255, g: 100, b: 0, a: 255))
      # Add fiery glow effect
      drawCircleLines(meteorite.pos.x.int32, meteorite.pos.y.int32, meteorite.radius + 3,
                     Color(r: 255, g: 150, b: 0, a: 200))
      drawCircleLines(meteorite.pos.x.int32, meteorite.pos.y.int32, meteorite.radius + 6,
                     Color(r: 255, g: 200, b: 50, a: 100))
  
  # Draw walls
  for wall in game.walls:
    drawWall(wall, game.player)
  
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
    drawBullet(bullet, hasOvercharge, hasBloodBullets, game.time)
  
  # Draw enemies
  for enemy in game.enemies:
    # Draw elite aura first (so it appears behind the enemy)
    if enemy.isElite:
      drawEliteAura(enemy, game.time)
    drawEnemy(enemy)
    
    # Draw OS-style enemy labels above each enemy
    drawEnemyLabel(enemy, showHealthBar = true, enabled = globalSettings.showEnemyLabels)
    
    # Draw warning indicators for elite/boss enemies
    drawEnemyWarningIndicator(enemy)
    
    # Draw boss satellites
    if enemy.isBoss and enemy.satellites.len > 0:
      # OPTIMIZATION: Draw orbit trails first in single batch
      # Only draw trails for every other satellite to reduce draw calls
      for idx, sat in enemy.satellites:
        if idx mod 2 == 0:  # Skip every other trail
          drawCircleLines(enemy.pos.x.int32, enemy.pos.y.int32, sat.radius,
                         Color(r: 100, g: 150, b: 255, a: 30))  # Reduced alpha (30 instead of 50)
      
      # Draw all satellites
      for sat in enemy.satellites:
        # Draw satellite body
        let satColor = if sat.hp > 5:
          Color(r: 120, g: 180, b: 255, a: 255)  # Healthy - blue
        else:
          Color(r: 255, g: 150, b: 80, a: 255)   # Damaged - orange
        
        drawCircle(Vector2(x: sat.pos.x, y: sat.pos.y), 18.0, satColor)  # INCREASED from 12.0 to 18.0 (larger, easier to see and hit)

        if sat.laserActive and sat.laserChargeTime < 1.5:
          # crosshair
          let targetSize = 15.0
          let pulseAlpha = uint8(150 + sin(game.time * 8.0) * 105)  # Pulsing effect
          let targetColor = Color(r: 255, g: 50, b: 50, a: pulseAlpha)
          
          # Draw simple crosshair (X pattern)
          drawLine(
            Vector2(x: sat.laserTarget.x - targetSize, y: sat.laserTarget.y - targetSize),
            Vector2(x: sat.laserTarget.x + targetSize, y: sat.laserTarget.y + targetSize),
            2,
            targetColor
          )
          drawLine(
            Vector2(x: sat.laserTarget.x - targetSize, y: sat.laserTarget.y + targetSize),
            Vector2(x: sat.laserTarget.x + targetSize, y: sat.laserTarget.y - targetSize),
            2,
            targetColor
          )
          # Single circle only
          drawCircleLines(sat.laserTarget.x.int32, sat.laserTarget.y.int32, targetSize,
                         targetColor)
          
          # OPTIMIZATION: Skip targeting line during warning phase - laser beam itself is enough visual feedback
  
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
  
  # UNIFIED AURA RENDERING
  # Draw all active aura effects using the unified aura system
  const AURA_TYPES = [puSlowField, puFireAura, puLightningAura, puPoisonAura, puWindAura, puArcaneAura, puBloodAura]
  for auraType in AURA_TYPES:
    if hasPowerUp(game.player, auraType):
      let level = getPowerUpLevel(game.player, auraType)
      let config = getAuraConfig(auraType, level)
      drawAuraEffect(game.player.pos, config, game.time)
  
  # Draw player
  drawPlayer(game.player)
  
  # Damage vignette: red edge-flash when player takes damage
  # lastDamageTaken is set to the damage amount for 1 frame, then reset by the player module.
  # We track a fading vignette timer in game.time so it lasts ~0.35s.
  if game.player.lastDamageTaken > 0:
    # Re-use osBackground.alertLevel as a proxy for recent-damage intensity.
    # We clamp it to [0,1]; the existing alert system already fades it naturally.
    game.osBackground.alertLevel = min(game.osBackground.alertLevel + 0.5, 1.0)
  
  # Full-screen red vignette when alertLevel > 0
  if game.osBackground.alertLevel > 0:
    let vigAlpha = uint8(game.osBackground.alertLevel * 80)
    let vW: int32 = 160
    drawRectangleGradientH(0, 0, vW, game.screenHeight,
      Color(r: 255, g: 0, b: 0, a: vigAlpha), Color(r: 0, g: 0, b: 0, a: 0))
    drawRectangleGradientH(game.screenWidth - vW, 0, vW, game.screenHeight,
      Color(r: 0, g: 0, b: 0, a: 0), Color(r: 255, g: 0, b: 0, a: vigAlpha))
    drawRectangleGradientV(0, 0, game.screenWidth, vW,
      Color(r: 255, g: 0, b: 0, a: vigAlpha), Color(r: 0, g: 0, b: 0, a: 0))
    drawRectangleGradientV(0, game.screenHeight - vW, game.screenWidth, vW,
      Color(r: 0, g: 0, b: 0, a: 0), Color(r: 255, g: 0, b: 0, a: vigAlpha))
  
  # Draw damage numbers (on top of everything except UI)
  for damageNum in game.damageNumbers:
    drawDamageNumber(damageNum)
  
  # Update OS-style HUD
  updateOSHUD(game.osHUD, dt)
  
  # Draw unified combined HUD panel (top-left, almost touching top)
  drawCombinedHUDPanel(game, 10, 2)
  
  # Draw action log (notifications)
  drawActionLog(game.osHUD, game.screenWidth, game.screenHeight)

  # Kill streak system removed - now only combo system is used
  drawCombo(game.dopamine.comboSystem, game.screenWidth, game.screenHeight, game.dopamine.currentTime)
  drawMilestone(game.dopamine.milestones, game.screenWidth, game.screenHeight)
  drawMicroRewards(game.dopamine.microRewards)

  # Wave start banner (slides in from top for first 1.5s of each wave)
  if game.waveInProgress:
    let waveAge = game.time - game.waveStartTime
    let isBossNext = game.wavesUntilBoss == 0
    drawWaveStartBanner(game.currentWave, waveAge, game.screenWidth, game.screenHeight, isBossNext)
  
  drawWaveCelebration(game.dopamine.waveCelebration, game.screenWidth, game.screenHeight)
  drawBossIntroduction(game.dopamine.bossIntro, game.screenWidth, game.screenHeight)
  drawAchievementPopup(game.dopamine.achievements, game.screenWidth, game.screenHeight)
  # Real-time stats now integrated into debug panel
  
  # Mode-specific UI removed - now handled by OS-Style Left Info Panel
  # (Wave info, enemies count, etc. are all in the left panel)
  
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
  if isTimeSurvivalMode(game.mode):
    drawSurvivalHUD(game, game.screenWidth, game.screenHeight)
  
  # Combined HUD panel already shows all info, no need for separate panels
  
  # OS-Style Debug Panel (right side, touching right edge) - controlled by showDebugStats setting
  if globalSettings != nil and globalSettings.showDebugStats:
    drawDebugPanel(game, game.screenWidth, 2)
  
  # Legendary Power-ups Panel (bottom-left corner) - Always show cooldowns for legendary abilities
  drawLegendaryPowerUpsPanel(game, game.screenWidth.int32, game.screenHeight.int32)

  # Instructions only for non-legendary keys
  drawText(t(tkGameInstructionsWall),
           game.screenWidth div 2 - 100, game.screenHeight - 25, 16, LightGray)
  
  # End 2D camera mode if screen shake was applied
  if shakeOffsetX != 0 or shakeOffsetY != 0:
    endMode2D()

proc drawGameOver*(game: Game) =
  # Use the new OS-style system crash screen
  drawSystemCrash(game, game.selectedGameOverButton)

proc drawWaveTransition*(game: Game) =
  # Draw the game in background
  drawGame(game)
  
  # Dark overlay
  drawRectangle(0, 0, game.screenWidth, game.screenHeight, Color(r: 0, g: 0, b: 0, a: 180))
  
  # Title
  drawText(t(tkGameGetReady), game.screenWidth div 2 - 120, game.screenHeight div 2 - 80, 50, Yellow)
  
  # Boss wave notification with wave number
  let bossWaveText = t(tkGameBossWavePrefix) & $(game.currentWave + 1)
  let bossTextWidth = measureText(bossWaveText, 35)
  drawText(bossWaveText, game.screenWidth div 2 - bossTextWidth div 2, game.screenHeight div 2, 35, Red)
  
  drawText(t(tkGameIncoming), game.screenWidth div 2 - 75, game.screenHeight div 2 + 40, 30, Orange)
  
  drawText(t(tkGamePressEnterToStart), game.screenWidth div 2 - 130, game.screenHeight - 80, 20, LightGray)
