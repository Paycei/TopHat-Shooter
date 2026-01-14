import raylib, types, wall, math, random, powerup, localization

proc newPlayer*(x, y: float32): Player =
  result = Player(
    pos: newVector2f(x, y),
    vel: newVector2f(0, 0),
    radius: 14,
    baseRadius: 14,
    hp: 7,
    maxHp: 7,
    speed: 175,
    baseSpeed: 175,
    damage: 1,
    fireRate: 0.425,
    bulletSpeed: 300,
    lastShot: 0,
    coins: 0,
    kills: 0,
    walls: 0,
    speedBoostTimer: 0,
    invincibilityTimer: 0,
    fireRateBoostTimer: 0,
    magnetTimer: 0,
    powerUps: @[],
    shieldAngle: 0,
    shieldHealths: @[],      # Will be populated when power-up is acquired
    shieldMaxHealth: 3.0,    # Starting health per shield (increases with upgrades)
    shieldRegenTimers: @[],  # Will be populated when power-up is acquired
    shieldRegenDelay: 4.0,   # Shields regenerate after 4 seconds (reduced by upgrades)
    killsSinceLastHeal: 0,
    regenTimer: 0,
    lastDamageTaken: 0,
    rageStacks: 0,
    critCharge: 0,
    autoShootEnabled: true,  # Auto-shoot starts enabled
    auraRadius: 50.0,  # Invisible coin collection aura
    doubleShotDelay: 0,
    bulletCounter: 0,  # Track bullets fired for special rounds power-up
    timeWarpCooldown: 0,
    timeWarpActive: false,
    timeWarpDuration: 0,
    timeWarpUsesThisWave: 0,
    timeWarpMaxUsesPerWave: 1,  # Default to level 1
    phaseShiftCooldown: 0,
    phaseShiftInvulnTimer: 0,
    lastPhaseShiftPos: newVector2f(x, y),
    rotatingOrbs: @[],
    orbRotationAngle: 0,
    hasFireMastery: false,
    hasPoisonMastery: false,
    hasFrostMastery: false,
    hasArcaneMastery: false,
    hasLightningMastery: false,
    hasWindMastery: false,
    hasBloodMastery: false,
    parryActive: false,
    parryCooldown: 0,
    parryDuration: 0,
    radialBurstTimer: 0.0,
    pulseArmorCooldown: 0.0
  )

proc hasAnyOrbPowerUp*(player: Player): bool =
  ## Check if player has any orb power-up equipped
  return hasPowerUp(player, puRotatingOrbs) or
         hasPowerUp(player, puPoisonOrb) or
         hasPowerUp(player, puFireOrb) or
         hasPowerUp(player, puLightningOrb) or
         hasPowerUp(player, puWindOrb) or
         hasPowerUp(player, puFrostOrb) or
         hasPowerUp(player, puArcaneOrb) or
         hasPowerUp(player, puBloodOrb)

proc updatePlayer*(player: Player, dt: float32, screenWidth, screenHeight: int32, walls: seq[Wall]) =
  # Update powerup timers
  if player.speedBoostTimer > 0:
    player.speedBoostTimer -= dt
  if player.invincibilityTimer > 0:
    player.invincibilityTimer -= dt
  if player.fireRateBoostTimer > 0:
    player.fireRateBoostTimer -= dt
  if player.magnetTimer > 0:
    player.magnetTimer -= dt
  
  # NOTE: double-shot delay timer is updated in game.nim where firing logic lives
  
  # Update legendary power-up cooldowns
  if player.timeWarpCooldown > 0:
    player.timeWarpCooldown -= dt
  if player.timeWarpDuration > 0:
    player.timeWarpDuration -= dt
    if player.timeWarpDuration <= 0:
      player.timeWarpActive = false
  if player.phaseShiftCooldown > 0:
    player.phaseShiftCooldown -= dt
  if player.phaseShiftInvulnTimer > 0:
    player.phaseShiftInvulnTimer -= dt
  
  # Update Parry power-up timers
  if player.parryActive:
    player.parryDuration -= dt
    if player.parryDuration <= 0:
      player.parryActive = false
  if player.parryCooldown > 0:
    player.parryCooldown -= dt
  
  # Update Pulse Armor cooldown
  if player.pulseArmorCooldown > 0:
    player.pulseArmorCooldown -= dt
  
  # Calculate current speed with boost
  var currentSpeed = player.speed
  if player.speedBoostTimer > 0:
    currentSpeed *= 1.5
  
  var moveDir = newVector2f(0, 0)
  
  if isKeyDown(W): moveDir.y -= 1
  if isKeyDown(S): moveDir.y += 1
  if isKeyDown(A): moveDir.x -= 1
  if isKeyDown(D): moveDir.x += 1
  
  if moveDir.length() > 0:
    moveDir = moveDir.normalize()
    player.vel = moveDir * currentSpeed
  else:
    player.vel = newVector2f(0, 0)
  
  # Calculate next position
  let nextPos = player.pos + player.vel * dt
  
  # Check wall collisions - player is blocked by walls
  var canMove = true
  for w in walls:
    if checkPlayerWallCollision(nextPos, player.radius, w):
      canMove = false
      break
  
  if canMove:
    player.pos = nextPos
  
  # Clamp to screen
  if player.pos.x < player.radius: player.pos.x = player.radius
  if player.pos.x > screenWidth.float32 - player.radius: player.pos.x = screenWidth.float32 - player.radius
  if player.pos.y < player.radius: player.pos.y = player.radius
  if player.pos.y > screenHeight.float32 - player.radius: player.pos.y = screenHeight.float32 - player.radius
  
  # Scale radius with max HP using square root for diminishing returns
  # Formula: baseRadius + sqrt(maxHp - 7) * scaleFactor
  # REDUCED: scaleFactor from 2.0 to 1.0 for less dramatic size scaling
  # At 7 HP (starting): 14 + sqrt(0) * 1 = 14 (same as base)
  # At 11 HP: 14 + sqrt(4) * 1 = 14 + 2.0 = 16.0 (was 18.0)
  # At 21 HP: 14 + sqrt(14) * 1 = 14 + 3.74 = 17.74 (was 21.48)
  let hpAboveBase = max(0.0, player.maxHp - 7.0)
  player.radius = player.baseRadius + sqrt(hpAboveBase) * 1.0
  
  # Scale aura with player radius - MUCH LARGER collection area
  player.auraRadius = player.radius * 3.5  # 3.5x player size for generous collection
  
  # Update shield angle for rotating shield power-up - NERFED rotation speed
  player.shieldAngle += dt * 1.0  # Reduced from 2.0 to 1.0 (50% slower)
  
  # Update shield health and regeneration
  if hasPowerUp(player, puRotatingShield):
    let shieldCount = 3  # Always 3 shields regardless of level
    # Ensure arrays are initialized
    if player.shieldHealths.len != shieldCount:
      player.shieldHealths = @[]
      player.shieldRegenTimers = @[]
      for i in 0..<shieldCount:
        player.shieldHealths.add(player.shieldMaxHealth)
        player.shieldRegenTimers.add(0.0)
    
    # Update regeneration timers and restore damaged/destroyed shields
    for i in 0..<player.shieldHealths.len:
      if player.shieldHealths[i] <= 0:
        # Shield is destroyed, increment regen timer
        player.shieldRegenTimers[i] += dt
        if player.shieldRegenTimers[i] >= player.shieldRegenDelay:
          # Restore shield to full health
          player.shieldHealths[i] = player.shieldMaxHealth
          player.shieldRegenTimers[i] = 0.0
      elif player.shieldHealths[i] < player.shieldMaxHealth:
        # Shield is damaged but not destroyed - regenerate it
        player.shieldRegenTimers[i] += dt
        if player.shieldRegenTimers[i] >= player.shieldRegenDelay:
          # Regenerate shield health gradually (50% of max health per second)
          let regenRate = player.shieldMaxHealth * 0.5
          player.shieldHealths[i] = min(player.shieldHealths[i] + regenRate * dt, player.shieldMaxHealth)
          # If fully healed, reset timer
          if player.shieldHealths[i] >= player.shieldMaxHealth:
            player.shieldRegenTimers[i] = 0.0
      else:
        # Shield is at full health, reset timer
        player.shieldRegenTimers[i] = 0.0
  
  # Update rotating orbs angle
  player.orbRotationAngle += dt * 2.0  # Rotate orbs around player
  
  # Clean up orbs if no orb power-ups are active
  if not hasAnyOrbPowerUp(player) and player.rotatingOrbs.len > 0:
    player.rotatingOrbs = @[]

proc drawPlayer*(player: Player) =
  # Slow field visual and other aura visuals
  for powerUp in player.powerUps:
    # Slow field visual
    if powerUp.powerType == puSlowField:
      let slowRadius = case powerUp.level
        of 1: 120.0
        of 2: 160.0
        else: 200.0
      let alpha = 15 + (sin(player.shieldAngle * 2) * 8).int
      drawCircle(Vector2(x: player.pos.x, y: player.pos.y), slowRadius,
                Color(r: 100, g: 150, b: 255, a: alpha.uint8))
      drawCircleLines(player.pos.x.int32, player.pos.y.int32, slowRadius,
                     Color(r: 100, g: 150, b: 255, a: 60))
    
    # Fire aura visual
    if powerUp.powerType == puFireAura:
      let fireRadius = case powerUp.level
        of 1: 120.0
        of 2: 160.0
        else: 200.0
      let alpha = 40 + (sin(player.shieldAngle * 4) * 20).int
      drawCircle(Vector2(x: player.pos.x, y: player.pos.y), fireRadius,
                Color(r: 255, g: 50, b: 0, a: alpha.uint8))
      drawCircleLines(player.pos.x.int32, player.pos.y.int32, fireRadius,
                     Color(r: 255, g: 100, b: 0, a: 100))
    
    # Lightning aura visual
    if powerUp.powerType == puLightningAura:
      let lightningRadius = case powerUp.level
        of 1: 120.0
        of 2: 160.0
        else: 200.0
      let alpha = 25 + (sin(player.shieldAngle * 5) * 15).int
      drawCircle(Vector2(x: player.pos.x, y: player.pos.y), lightningRadius,
                Color(r: 100, g: 150, b: 255, a: alpha.uint8))
      drawCircleLines(player.pos.x.int32, player.pos.y.int32, lightningRadius,
                     Color(r: 150, g: 200, b: 255, a: 80))
    
    # Poison aura visual
    if powerUp.powerType == puPoisonAura:
      let poisonRadius = case powerUp.level
        of 1: 120.0
        of 2: 160.0
        else: 200.0
      let alpha = 35 + (sin(player.shieldAngle * 3) * 20).int
      drawCircle(Vector2(x: player.pos.x, y: player.pos.y), poisonRadius,
                Color(r: 100, g: 200, b: 100, a: alpha.uint8))
      drawCircleLines(player.pos.x.int32, player.pos.y.int32, poisonRadius,
                     Color(r: 100, g: 255, b: 100, a: 70))
  
  # Dodge flash effect
  if player.lastDamageTaken == 0 and player.hp > 0:
    drawText(t(tkPlayerDodge), (player.pos.x - 25).int32, (player.pos.y - 35).int32, 14, Yellow)
    player.lastDamageTaken = -1  # Clear flag
  
  # === MODERN OS-STYLE PLAYER RENDERING ===
  let time = getTime()
  let pulse = sin(time * 2.0) * 0.5 + 0.5  # Pulsing animation
  let rotation = time * 0.5  # Slow rotation for hex frame
  
  # Determine base color based on state
  var baseColor = Color(r: 0, g: 200, b: 200, a: 255)  # Cyan (system primary)
  var coreColor = Color(r: 255, g: 255, b: 255, a: 255)  # White core
  var glowIntensity = 0.4 + pulse * 0.2  # Subtle pulse
  
  # Phase Shift invulnerability visual effect
  if player.phaseShiftInvulnTimer > 0:
    let phaseAlpha = (sin(player.phaseShiftInvulnTimer * 20.0) * 50 + 150).int
    baseColor = Color(r: 0, g: 255, b: 255, a: 255)  # Bright cyan
    glowIntensity = 0.8 + pulse * 0.2
    # Extra glow layers
    drawCircle(Vector2(x: player.pos.x, y: player.pos.y), player.radius + 8, 
              Color(r: 0, g: 255, b: 255, a: phaseAlpha.uint8))
    drawText(t(tkPlayerPhase), (player.pos.x - 30).int32, (player.pos.y - 40).int32, 14, SkyBlue)
  # Parry active visual effect - white/silver shield
  elif player.parryActive:
    let parryAlpha = (sin(player.parryDuration * 20.0) * 50 + 150).int
    baseColor = Color(r: 255, g: 255, b: 255, a: 255)  # White
    coreColor = Color(r: 220, g: 220, b: 255, a: 255)  # Light blue
    glowIntensity = 1.0
    drawCircle(Vector2(x: player.pos.x, y: player.pos.y), player.radius + 8, 
              Color(r: 255, g: 255, b: 255, a: parryAlpha.uint8))
    drawText(t(tkPlayerParry), (player.pos.x - 25).int32, (player.pos.y - 40).int32, 16, White)
  # Invincibility visual effect
  elif player.invincibilityTimer > 0:
    let flash = ((player.invincibilityTimer * 10).int mod 2 == 0)
    if flash:
      baseColor = Color(r: 255, g: 215, b: 0, a: 255)  # Gold
      coreColor = Color(r: 255, g: 255, b: 200, a: 255)
    else:
      baseColor = Color(r: 0, g: 200, b: 255, a: 255)  # Cyan
    glowIntensity = 0.9
  
  # Speed boost color modification
  if player.speedBoostTimer > 0:
    baseColor = Color(r: 0, g: 255, b: 200, a: 255)  # Green-cyan tint
    glowIntensity += 0.2
  
  # 1. OUTER ENERGY FIELD (background glow)
  let outerGlowRadius = player.radius + 12
  for i in 0..2:
    let layerRadius = outerGlowRadius + i.float32 * 4.0
    let layerAlpha = uint8((1.0 - i.float32 / 3.0) * glowIntensity * 50)
    drawCircle(Vector2(x: player.pos.x, y: player.pos.y), layerRadius,
              Color(r: baseColor.r, g: baseColor.g, b: baseColor.b, a: layerAlpha))
  
  # 2. CIRCUIT TRACES (inner glow layer)
  let numTraces = 6
  for i in 0..<numTraces:
    let angle = rotation + i.float32 * PI / 3.0
    let innerR = player.radius * 0.3
    let outerR = player.radius * 0.9
    let x1 = player.pos.x + cos(angle) * innerR
    let y1 = player.pos.y + sin(angle) * innerR
    let x2 = player.pos.x + cos(angle) * outerR
    let y2 = player.pos.y + sin(angle) * outerR
    let traceAlpha = uint8(80 + pulse * 60)
    drawLine(Vector2(x: x1, y: y1), Vector2(x: x2, y: y2), 1.5,
            Color(r: min(baseColor.r + 50, 255), g: min(baseColor.g + 50, 255), 
                  b: min(baseColor.b + 50, 255), a: traceAlpha))
  
  # 3. ROTATING HEXAGONAL FRAME
  let hexRadius = player.radius * 0.85
  let hexPoints = 6
  for i in 0..<hexPoints:
    let angle = rotation + i.float32 * PI / 3.0 - PI / 2.0
    let nextAngle = rotation + (i + 1).float32 * PI / 3.0 - PI / 2.0
    let x1 = player.pos.x + cos(angle) * hexRadius
    let y1 = player.pos.y + sin(angle) * hexRadius
    let x2 = player.pos.x + cos(nextAngle) * hexRadius
    let y2 = player.pos.y + sin(nextAngle) * hexRadius
    drawLine(Vector2(x: x1, y: y1), Vector2(x: x2, y: y2), 2.5, baseColor)
    # Corner nodes
    drawCircle(Vector2(x: x1, y: y1), 2.5, baseColor)
  
  # 4. MAIN BODY CIRCLE
  drawCircle(Vector2(x: player.pos.x, y: player.pos.y), player.radius * 0.6,
            Color(r: baseColor.r div 2, g: baseColor.g div 2, b: baseColor.b div 2, a: 200))
  
  # 5. BRIGHT WHITE CORE
  drawCircle(Vector2(x: player.pos.x, y: player.pos.y), player.radius * 0.35, coreColor)
  # Core highlight
  let highlightX = player.pos.x - player.radius * 0.15
  let highlightY = player.pos.y - player.radius * 0.15
  drawCircle(Vector2(x: highlightX, y: highlightY), player.radius * 0.15,
            Color(r: 255, g: 255, b: 255, a: 180))
  
  # 6. DATA PARTICLES (orbiting effect)
  if player.vel.length() > 10 or pulse > 0.7:
    let numParticles = 8
    for i in 0..<numParticles:
      let particleAngle = time * 3.0 + i.float32 * PI * 2.0 / numParticles.float32
      let particleDist = player.radius + 6 + sin(time * 4.0 + i.float32) * 2
      let px = player.pos.x + cos(particleAngle) * particleDist
      let py = player.pos.y + sin(particleAngle) * particleDist
      let particleAlpha = uint8(100 + pulse * 80)
      drawCircle(Vector2(x: px, y: py), 1.8,
                Color(r: baseColor.r, g: baseColor.g, b: baseColor.b, a: particleAlpha))
  
  # Speed boost indicator (motion trails)
  if player.speedBoostTimer > 0:
    for i in 1..3:
      let trailAlpha = uint8(60 - i * 15)
      let trailScale = 1.0 - i.float32 * 0.1
      let trailX = player.pos.x - player.vel.x * i.float32 * 0.015
      let trailY = player.pos.y - player.vel.y * i.float32 * 0.015
      drawCircle(Vector2(x: trailX, y: trailY), player.radius * trailScale,
                Color(r: 0, g: 255, b: 200, a: trailAlpha))
  
  # Rotating shield visual (if player has it) - NERFED with gaps
  for powerUp in player.powerUps:
    if powerUp.powerType == puRotatingShield:
      let level = powerUp.level
      let shieldCount = 3  # Always 3 shields regardless of level
      
      # Shield scales with player size for better visual feedback
      let shieldRadius = player.radius * 2.5 + 15  # Reduced from +15 to +10
      let shieldThickness = 3.0
      
      # Level-based coverage matches collision: NERFED values
      let arcCoverage = case level
        of 1: 0.30  # 30% coverage (was 50%)
        of 2: 0.35  # 35% coverage (was 70%)
        else: 0.40  # 40% coverage (was 85%)
      
      # Draw partial curved shield lines with visible gaps
      for i in 0..<shieldCount:
        # Skip destroyed shields
        if i < player.shieldHealths.len and player.shieldHealths[i] <= 0:
          continue
          
        let baseAngle = player.shieldAngle + (i.float32 * PI * 2.0 / shieldCount.float32)
        let fullArcLength = PI * 2.0 / shieldCount.float32
        let activeArcLength = fullArcLength * arcCoverage
        
        # Center the active arc, leaving gaps
        let gapSize = (fullArcLength - activeArcLength) / 2.0
        let angle1 = baseAngle + gapSize
        let angle2 = angle1 + activeArcLength
        
        # Determine shield color based on health - cyan/teal theme
        var shieldColor = Color(r: 0, g: 255, b: 255, a: 255)  # Cyan
        if i < player.shieldHealths.len:
          let healthPercent = player.shieldHealths[i] / player.shieldMaxHealth
          if healthPercent < 0.4:
            shieldColor = Color(r: 200, g: 50, b: 200, a: 255)  # Magenta when low
          elif healthPercent < 0.7:
            shieldColor = Color(r: 255, g: 100, b: 255, a: 255)  # Light magenta when medium
        
        # Draw arc segments for the ACTIVE portion only
        let segments = 16
        for j in 0..<segments:
          let t1 = j.float32 / segments.float32
          let t2 = (j + 1).float32 / segments.float32
          let a1 = angle1 + t1 * (angle2 - angle1)
          let a2 = angle1 + t2 * (angle2 - angle1)
          
          let x1 = player.pos.x + cos(a1) * shieldRadius
          let y1 = player.pos.y + sin(a1) * shieldRadius
          let x2 = player.pos.x + cos(a2) * shieldRadius
          let y2 = player.pos.y + sin(a2) * shieldRadius
          
          drawLine(Vector2(x: x1, y: y1), Vector2(x: x2, y: y2), shieldThickness, shieldColor)
        
        # Add energy glow at shield endpoints (shows active coverage)
        let ex1 = player.pos.x + cos(angle1) * shieldRadius
        let ey1 = player.pos.y + sin(angle1) * shieldRadius
        let ex2 = player.pos.x + cos(angle2) * shieldRadius
        let ey2 = player.pos.y + sin(angle2) * shieldRadius
        
        drawCircle(Vector2(x: ex1, y: ey1), 5, shieldColor)
        drawCircle(Vector2(x: ex2, y: ey2), 5, shieldColor)
  
  # Draw rotating orbs (if player has any orb power-ups)
  # Check if player has any orb power-ups before rendering
  if hasAnyOrbPowerUp(player) and player.rotatingOrbs.len > 0:
    # Scale orb size with player size (larger orbs for better visibility and impact)
    let orbSizeScale = 13.0 + (player.radius - player.baseRadius) * 0.85
    
    for orb in player.rotatingOrbs:
      # Calculate orb position
      let angle = player.orbRotationAngle + orb.angle
      let orbX = player.pos.x + cos(angle) * orb.radius
      let orbY = player.pos.y + sin(angle) * orb.radius
      
      # Get element color
      let color = getElementColor(orb.elementType)
      
      # Multi-layered orb with glow effects and trails
      # Outer glow aura - Reduced glow size from 12/9 to 8/6 for less overwhelming effect
      drawCircle(Vector2(x: orbX, y: orbY), 8 + (orbSizeScale - 6.0) * 1.2, 
                Color(r: color.r, g: color.g, b: color.b, a: 30))
      drawCircle(Vector2(x: orbX, y: orbY), 6 + (orbSizeScale - 6.0) * 1.0, 
                Color(r: color.r, g: color.g, b: color.b, a: 60))
      
      # Main orb body - scaled
      drawCircle(Vector2(x: orbX, y: orbY), orbSizeScale, color)
      
      # Pulsing energy ring - scaled
      let pulseSize = (7 + orbSizeScale - 6.0) + sin(angle * 3.0) * 1.5
      drawCircleLines(orbX.int32, orbY.int32, pulseSize, 
                     Color(r: color.r, g: color.g, b: color.b, a: 180))
      
      # Bright core with highlight - Made highlight much more subtle
      drawCircle(Vector2(x: orbX, y: orbY), orbSizeScale * 0.4,
                Color(r: 255, g: 255, b: 255, a: 150))
      drawCircle(Vector2(x: orbX - (orbSizeScale * 0.15), y: orbY - (orbSizeScale * 0.15)), orbSizeScale * 0.15,
                Color(r: 255, g: 255, b: 255, a: 180))
      
      # Element-specific visual effects
      case orb.elementType:
      of etFire:
        # Flickering flame particles
        for i in 0..2:
          let flameAngle = angle + i.float32 * 2.0
          let flameDist = 8 + sin(flameAngle * 5.0) * 2
          let fx = orbX + cos(flameAngle) * flameDist
          let fy = orbY + sin(flameAngle) * flameDist - abs(sin(flameAngle * 3.0)) * 3
          drawCircle(Vector2(x: fx, y: fy), 2, Color(r: 255, g: 150, b: 50, a: 180))
      of etLightning:
        # Electric sparks
        if (angle * 10.0).int mod 3 == 0:
          for i in 0..3:
            let sparkAngle = angle + i.float32 * PI / 2.0
            let sx = orbX + cos(sparkAngle) * 10
            let sy = orbY + sin(sparkAngle) * 10
            drawLine(Vector2(x: orbX, y: orbY), Vector2(x: sx, y: sy), 1,
                    Color(r: 200, g: 220, b: 255, a: 150))
      of etPoison:
        # Dripping poison drops
        let dropY = orbY + abs(sin(angle * 2.0)) * 5
        drawCircle(Vector2(x: orbX, y: dropY), 1.5, Color(r: 120, g: 255, b: 120, a: 180))
      of etWind:
        # Swirling air streams
        for i in 0..2:
          let streamAngle = angle - i.float32 * 0.5
          let sx = orbX + cos(streamAngle) * (8 + i.float32 * 2)
          let sy = orbY + sin(streamAngle) * (8 + i.float32 * 2)
          drawCircle(Vector2(x: sx, y: sy), 1, Color(r: 220, g: 240, b: 255, a: 120))
      of etArcane:
        # Orbiting runes
        for i in 0..2:
          let runeAngle = -angle * 2.0 + i.float32 * PI * 2.0 / 3.0
          let rx = orbX + cos(runeAngle) * 8
          let ry = orbY + sin(runeAngle) * 8
          drawCircle(Vector2(x: rx, y: ry), 1.5, Color(r: 220, g: 150, b: 255, a: 200))
      of etFrost:
        # Ice crystals
        for i in 0..5:
          let crystalAngle = i.float32 * PI / 3.0
          let cx1 = orbX + cos(crystalAngle) * 7
          let cy1 = orbY + sin(crystalAngle) * 7
          let cx2 = orbX + cos(crystalAngle) * 9
          let cy2 = orbY + sin(crystalAngle) * 9
          drawLine(Vector2(x: cx1, y: cy1), Vector2(x: cx2, y: cy2), 1,
                  Color(r: 150, g: 200, b: 255, a: 180))
      else:
        discard  # etNone or other unknown types

proc takeDamage*(player: Player, damage: float32): bool =
  ## Returns true if player died (HP reached 0 or below), false otherwise
  # Invincibility from consumables
  if player.invincibilityTimer > 0:
    return false
  
  # Parry invulnerability - also bounces bullets
  if player.parryActive:
    return false
  
  # Phase Shift invulnerability
  if player.phaseShiftInvulnTimer > 0:
    return false
  
  # Dodge chance power-up
  for powerUp in player.powerUps:
    if powerUp.powerType == puDodgeChance:
      let dodgeChance = case powerUp.level
        of 1: 15
        of 2: 20
        else: 30
      if rand(99) < dodgeChance:
        # Dodged! Visual feedback
        player.lastDamageTaken = 0
        return false
  
  # Apply Fortified damage reduction
  var finalDamage = damage
  for powerUp in player.powerUps:
    if powerUp.powerType == puFortified:
      let reduction = case powerUp.level
        of 1: 0.15  # 15% reduction
        of 2: 0.25  # 25% reduction
        else: 0.35  # 35% reduction
      finalDamage *= (1.0 - reduction)
      break
  
  player.hp -= finalDamage
  
  # Clamp HP to 0 minimum
  if player.hp < 0: 
    player.hp = 0
  
  player.lastDamageTaken = damage
  
  # Pulse Armor - emit shockwave when taking damage (if not on cooldown)
  for powerUp in player.powerUps:
    if powerUp.powerType == puPulseArmor and player.pulseArmorCooldown <= 0:
      # Trigger shockwave - cooldown will be set in game.nim
      player.pulseArmorCooldown = -1.0  # -1 signals to trigger in game.nim
      break
  
  # Return true if HP reached 0 or below (death condition)
  return player.hp <= 0

proc heal*(player: Player, amount: float32) =
  player.hp += amount
  if player.hp > player.maxHp: player.hp = player.maxHp

proc activateSpeedBoost*(player: Player) =
  player.speedBoostTimer = 5.0

proc activateInvincibility*(player: Player) =
  player.invincibilityTimer = 3.0

proc activateFireRateBoost*(player: Player) =
  player.fireRateBoostTimer = 8.0

proc activateMagnet*(player: Player) =
  player.magnetTimer = 10.0
