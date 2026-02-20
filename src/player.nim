import raylib, types, wall, math, random, powerup, localization, skins, shapes, ui/ui_constants

proc newPlayer*(x, y: float32): Player =
  result = Player(
    pos: newVector2f(x, y),
    vel: newVector2f(0, 0),
    radius: 14,
    baseRadius: 14,
    hp: 9,
    maxHp: 9,
    speed: 175,
    baseSpeed: 175,
    damage: 1,
    bulletDamageMult: 1.0,  # Multiplier for bullet-only damage bonuses (e.g. Arcane Bullets)
    fireRate: 0.425,
    bulletSpeed: 325,
    lastShot: 0,
    coins: 0,
    kills: 0,
    walls: 0,
    speedBoostTimer: 0,
    invincibilityTimer: 0,
    fireRateBoostTimer: 0,
    magnetTimer: 0,
    shieldBoostTimer: 0,     # Shield boost duration
    doubleCoinTimer: 0,      # Double coin duration
    damageBoostTimer: 0,     # Damage boost duration
    lifestealTimer: 0,       # Lifesteal duration
    shieldHits: 0,           # Remaining shield absorptions
    powerUps: @[],
    shieldAngle: 0,
    shieldHealths: @[],      # Will be populated when power-up is acquired
    shieldMaxHealth: 3.0,    # Starting health per shield (increases with upgrades)
    shieldRegenTimers: @[],  # Will be populated when power-up is acquired
    shieldRegenDelay: 4.0,   # Shields regenerate after 4 seconds (reduced by upgrades)
    killsSinceLastHeal: 0,
    regenTimer: 0,
    lastDamageTaken: -1,  # Unused sentinel kept for compatibility; see lastDamageEvent
    lastDamageEvent: deNone,
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
    timeWarpMaxUsesPerWave: 2,
    phaseShiftCooldown: 0,
    phaseShiftInvulnTimer: 0,
    teamId: ptNone,  # Default to no team
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
    pulseArmorCooldown: 0.0,
    skinType: 0,  # Default skin (skDefault)
    bulletSkinType: 0,
    bulletShapeType: 0,
    shapeType: 0,
    particleSkinType: 0
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
  if player.shieldBoostTimer > 0:
    player.shieldBoostTimer -= dt
  elif player.shieldBoostTimer <= 0:
      player.shieldHits = 0  # Clear shield when timer expires
  if player.doubleCoinTimer > 0:
    player.doubleCoinTimer -= dt
  if player.damageBoostTimer > 0:
    player.damageBoostTimer -= dt
  if player.lifestealTimer > 0:
    player.lifestealTimer -= dt
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
  # Note: baseRadius is also scaled by puHeavyRounds, so HP scaling preserves that multiplier.
  let hpAboveBase = max(0.0, player.maxHp - 7.5)
  player.radius = player.baseRadius + sqrt(hpAboveBase) * 0.4
  
  # Scale aura with player radius - collection area
  player.auraRadius = player.radius * 3.5  # 3.5x player size for generous collection
  
  # Update shield angle for rotating shield power-up
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
  player.orbRotationAngle += dt * 2.75  # Rotate orbs around player
  
  # Clean up orbs if no orb power-ups are active
  if not hasAnyOrbPowerUp(player) and player.rotatingOrbs.len > 0:
    player.rotatingOrbs = @[]

proc drawPlayer*(player: Player) =
  let time = getTime()  # Used throughout for animations
  # Slow field visual and other aura visuals
  for powerUp in player.powerUps:
    # Slow field visual
    if powerUp.powerType == puSlowField:
      let slowRadius = case powerUp.level
        of 1: 150.0
        of 2: 200.0
        else: 250.0
      let slowPulse = (sin(time * 1.5) * 0.06 + 0.94).float32
      let alpha = 12 + (sin(time * 2.0) * 6).int
      # Fill
      drawCircle(Vector2(x: player.pos.x, y: player.pos.y), slowRadius,
                Color(r: 100, g: 150, b: 255, a: alpha.uint8))
      # Expanding concentric rings that travel outward
      for ring in 0..2:
        let ringPhase = (time * 0.75 + ring.float32 * 0.333) mod 1.0
        let ringRadius = slowRadius * ringPhase.float32
        let ringAlpha = uint8((40.0 * (1.0 - ringPhase)).int)
        if ringRadius > 2:
          drawCircleLines(player.pos.x.int32, player.pos.y.int32, ringRadius,
                         Color(r: 120, g: 170, b: 255, a: ringAlpha))
      # Outer boundary - pulsing
      drawCircleLines(player.pos.x.int32, player.pos.y.int32, slowRadius * slowPulse,
                     Color(r: 100, g: 150, b: 255, a: 60))
      # Rotating dots at 68% radius — gives it a sense of rotation
      let dashRadius = slowRadius * 0.68
      for d in 0..7:
        let dashAngle = time * (-0.55) + d.float32 * PI * 0.25
        let dx = player.pos.x + cos(dashAngle) * dashRadius
        let dy = player.pos.y + sin(dashAngle) * dashRadius
        drawCircle(Vector2(x: dx, y: dy), 2.5, Color(r: 140, g: 185, b: 255, a: 65))
    
    # Fire aura visual
    if powerUp.powerType == puFireAura:
      let fireRadius = case powerUp.level
        of 1: 150.0
        of 2: 200.0
        else: 250.0
      let alpha = 40 + (sin(player.shieldAngle * 4) * 20).int
      drawCircle(Vector2(x: player.pos.x, y: player.pos.y), fireRadius,
                Color(r: 255, g: 50, b: 0, a: alpha.uint8))
      drawCircleLines(player.pos.x.int32, player.pos.y.int32, fireRadius,
                     Color(r: 255, g: 100, b: 0, a: 100))
    
    # Lightning aura visual
    if powerUp.powerType == puLightningAura:
      let lightningRadius = case powerUp.level
        of 1: 150.0
        of 2: 200.0
        else: 250.0
      let alpha = 25 + (sin(player.shieldAngle * 5) * 15).int
      drawCircle(Vector2(x: player.pos.x, y: player.pos.y), lightningRadius,
                Color(r: 100, g: 150, b: 255, a: alpha.uint8))
      drawCircleLines(player.pos.x.int32, player.pos.y.int32, lightningRadius,
                     Color(r: 150, g: 200, b: 255, a: 80))
    
    # Poison aura visual
    if powerUp.powerType == puPoisonAura:
      let poisonRadius = case powerUp.level
        of 1: 150.0
        of 2: 200.0
        else: 250.0
      let alpha = 35 + (sin(player.shieldAngle * 3) * 20).int
      drawCircle(Vector2(x: player.pos.x, y: player.pos.y), poisonRadius,
                Color(r: 100, g: 200, b: 100, a: alpha.uint8))
      drawCircleLines(player.pos.x.int32, player.pos.y.int32, poisonRadius,
                     Color(r: 100, g: 255, b: 100, a: 70))
  
  # Shield boost visual - cyan protective barrier
  if player.shieldHits > 0:
    let shieldPulse = 1.0 + 0.1 * sin(getTime() * 8.0)
    let shieldAlpha = 80 + (sin(getTime() * 4.0) * 40).int
    let shieldRadius = player.radius * 1.4 * shieldPulse
    drawCircle(Vector2(x: player.pos.x, y: player.pos.y), shieldRadius,
              Color(r: Cyan.r, g: Cyan.g, b: Cyan.b, a: shieldAlpha.uint8))
    drawCircleLines(player.pos.x.int32, player.pos.y.int32, shieldRadius, Cyan)
    # Draw shield hit counter
    let hitsText = $player.shieldHits
    drawText(hitsText, (player.pos.x - 4).int32, (player.pos.y + player.radius + 12).int32, 12, Cyan)
  
  # Celestial Veil — soft translucent ring around the player while the charge is ready.
  if player.celestialVeilActive and hasPowerUp(player, puCelestialVeil):
    let veilPulse   = 0.5 + 0.5 * sin(time * 3.0)
    let veilRadius  = player.radius * 1.65 + veilPulse * 3.0
    let veilAlpha   = uint8(40 + (veilPulse * 30).int)
    let veilLineA   = uint8(140 + (veilPulse * 60).int)
    let veilColor   = Color(r: 200, g: 200, b: 255, a: veilAlpha)
    let veilLine    = Color(r: 220, g: 220, b: 255, a: veilLineA)
    # Soft filled halo
    drawCircle(Vector2(x: player.pos.x, y: player.pos.y), veilRadius, veilColor)
    # Sharp outer ring
    drawCircleLines(player.pos.x.int32, player.pos.y.int32, veilRadius, veilLine)
    # Thin inner accent ring
    drawCircleLines(player.pos.x.int32, player.pos.y.int32, veilRadius - 3.0,
                    Color(r: 200, g: 200, b: 255, a: uint8(80 + (veilPulse * 40).int)))
    # Rotating star-glints around the ring (4 glints, 90° apart)
    for i in 0..3:
      let glintAngle = time * 1.5 + float32(i) * PI * 0.5
      let gx = player.pos.x + cos(glintAngle) * veilRadius
      let gy = player.pos.y + sin(glintAngle) * veilRadius
      drawCircle(Vector2(x: gx, y: gy), 2.5,
                 Color(r: 255, g: 255, b: 255, a: uint8(160 + (veilPulse * 80).int)))

  # Dodge flash effect — takeDamage sets lastDamageEvent = deDodged as a one-frame signal.
  if player.lastDamageEvent == deDodged and player.hp > 0:
    drawText(t(tkPlayerDodge), (player.pos.x - 25).int32, (player.pos.y - 35).int32, 14, Yellow)
    player.lastDamageEvent = deNone  # Consume flag

  # Celestial Veil absorbed-hit flash — takeDamage sets lastDamageEvent = deCelestialVeil.
  if player.lastDamageEvent == deCelestialVeil and player.hp > 0:
    drawText(t(tkPlayerVeil), (player.pos.x - 20).int32, (player.pos.y - 35).int32, 14,
             Color(r: 200, g: 200, b: 255, a: 255))
    player.lastDamageEvent = deNone  # Consume flag
  
  # PLAYER RENDERING
  let pulse = sin(time * 2.0) * 0.5 + 0.5  # Pulsing animation
  let rotation = time * 0.5  # Slow rotation for hex frame
  
  # Get colors from skin system
  let skinType = player.skinType.SkinType
  let (skinPrimary, skinSecondary, skinCore) = getSkinColors(skinType, time)
  var baseColor = skinPrimary
  var secondaryColor = skinSecondary
  var coreColor = skinCore
  var glowIntensity = 0.4 + pulse * 0.2  # Subtle pulse
  
  # Phase Shift invulnerability visual effect
  if player.phaseShiftInvulnTimer > 0:
    let phaseAlpha = (sin(player.phaseShiftInvulnTimer * 20.0) * 50 + 150).int
    baseColor = Color(r: 0, g: 255, b: 255, a: 255)  # Bright cyan
    glowIntensity = 0.8 + pulse * 0.2
    # Extra glow layers
    drawCircle(Vector2(x: player.pos.x, y: player.pos.y), player.radius + 8,
              Color(r: Cyan.r, g: Cyan.g, b: Cyan.b, a: phaseAlpha.uint8))
    drawText(t(tkPlayerPhase), (player.pos.x - 30).int32, (player.pos.y - 40).int32, 14, Cyan)
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
  
  # Draw player using selected shape
  let shapeType = player.shapeType.ShapeType
  drawPlayerShape(player.pos, player.radius, shapeType, baseColor, secondaryColor, coreColor,
                  time, rotation, pulse, glowIntensity)
  
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
  
  # Rotating shield visual
  for powerUp in player.powerUps:
    if powerUp.powerType == puRotatingShield:
      let level = powerUp.level
      let shieldCount = 3
      let shieldRadius = player.radius * 2.5 + 15

      let arcCoverage = case level
        of 1: 0.30
        of 2: 0.35
        else: 0.40

      for i in 0..<shieldCount:
        let baseAngle = player.shieldAngle + (i.float32 * PI * 2.0 / shieldCount.float32)
        let fullArcLength = PI * 2.0 / shieldCount.float32
        let activeArcLength = fullArcLength * arcCoverage
        let gapSize = (fullArcLength - activeArcLength) / 2.0
        let angle1 = baseAngle + gapSize
        let angle2 = angle1 + activeArcLength

        # DESTROYED: ghost recharge arc
        if i < player.shieldHealths.len and player.shieldHealths[i] <= 0:
          let regenProgress = if i < player.shieldRegenTimers.len:
            clamp(player.shieldRegenTimers[i] / player.shieldRegenDelay, 0.0, 1.0)
          else: 0.0
          let ghostAlpha = uint8(12 + (regenProgress * 50).int)
          # Dashed ghost arc (every other segment)
          let segments = 14
          for j in 0..<segments:
            if j mod 2 == 1: continue
            let t1 = j.float32 / segments.float32
            let t2 = (j + 1).float32 / segments.float32
            let a1 = angle1 + t1 * (angle2 - angle1)
            let a2 = angle1 + t2 * (angle2 - angle1)
            let x1 = player.pos.x + cos(a1) * shieldRadius
            let y1 = player.pos.y + sin(a1) * shieldRadius
            let x2 = player.pos.x + cos(a2) * shieldRadius
            let y2 = player.pos.y + sin(a2) * shieldRadius
            drawLine(Vector2(x: x1, y: y1), Vector2(x: x2, y: y2), 1.5,
                    Color(r: 0, g: 200, b: 255, a: ghostAlpha))
          continue

        # Color based on health
        var arcR: uint8 = 0
        var arcG: uint8 = 255
        var arcB: uint8 = 255
        if i < player.shieldHealths.len:
          let hp = player.shieldHealths[i] / player.shieldMaxHealth
          if hp < 0.4:
            arcR = 210; arcG = 45; arcB = 210
          elif hp < 0.7:
            arcR = 255; arcG = 100; arcB = 255

        let segments = 16

        # Pass 1 — outer glow halo (wide, soft)
        for j in 0..<segments:
          let t1 = j.float32 / segments.float32
          let t2 = (j + 1).float32 / segments.float32
          let a1 = angle1 + t1 * (angle2 - angle1)
          let a2 = angle1 + t2 * (angle2 - angle1)
          let gr = shieldRadius + 4.0
          let x1 = player.pos.x + cos(a1) * gr
          let y1 = player.pos.y + sin(a1) * gr
          let x2 = player.pos.x + cos(a2) * gr
          let y2 = player.pos.y + sin(a2) * gr
          drawLine(Vector2(x: x1, y: y1), Vector2(x: x2, y: y2), 6,
                  Color(r: arcR, g: arcG, b: arcB, a: 28))

        # Pass 2 — main arc (solid, medium thickness)
        for j in 0..<segments:
          let t1 = j.float32 / segments.float32
          let t2 = (j + 1).float32 / segments.float32
          let a1 = angle1 + t1 * (angle2 - angle1)
          let a2 = angle1 + t2 * (angle2 - angle1)
          let x1 = player.pos.x + cos(a1) * shieldRadius
          let y1 = player.pos.y + sin(a1) * shieldRadius
          let x2 = player.pos.x + cos(a2) * shieldRadius
          let y2 = player.pos.y + sin(a2) * shieldRadius
          drawLine(Vector2(x: x1, y: y1), Vector2(x: x2, y: y2), 2.5,
                  Color(r: arcR, g: arcG, b: arcB, a: 255))

        # Pass 3 — inner highlight (bright white-tinted, thin)
        for j in 0..<segments:
          let t1 = j.float32 / segments.float32
          let t2 = (j + 1).float32 / segments.float32
          let a1 = angle1 + t1 * (angle2 - angle1)
          let a2 = angle1 + t2 * (angle2 - angle1)
          let ir = shieldRadius - 2.5
          let x1 = player.pos.x + cos(a1) * ir
          let y1 = player.pos.y + sin(a1) * ir
          let x2 = player.pos.x + cos(a2) * ir
          let y2 = player.pos.y + sin(a2) * ir
          drawLine(Vector2(x: x1, y: y1), Vector2(x: x2, y: y2), 1,
                  Color(r: 200, g: 255, b: 255, a: 85))

        # Endpoint energy nodes — animated pulse
        let nodePulse = 3.5 + sin(time * 6.0 + i.float32 * 2.1) * 1.5
        let ex1 = player.pos.x + cos(angle1) * shieldRadius
        let ey1 = player.pos.y + sin(angle1) * shieldRadius
        let ex2 = player.pos.x + cos(angle2) * shieldRadius
        let ey2 = player.pos.y + sin(angle2) * shieldRadius

        # Outer glow on nodes
        drawCircle(Vector2(x: ex1, y: ey1), nodePulse + 3.5,
                  Color(r: arcR, g: arcG, b: arcB, a: 45))
        drawCircle(Vector2(x: ex2, y: ey2), nodePulse + 3.5,
                  Color(r: arcR, g: arcG, b: arcB, a: 45))
        # Main node
        drawCircle(Vector2(x: ex1, y: ey1), nodePulse,
                  Color(r: arcR, g: arcG, b: arcB, a: 255))
        drawCircle(Vector2(x: ex2, y: ey2), nodePulse,
                  Color(r: arcR, g: arcG, b: arcB, a: 255))
        # Bright core of node
        drawCircle(Vector2(x: ex1, y: ey1), nodePulse * 0.38,
                  Color(r: 255, g: 255, b: 255, a: 210))
        drawCircle(Vector2(x: ex2, y: ey2), nodePulse * 0.38,
                  Color(r: 255, g: 255, b: 255, a: 210))
  
  # Draw rotating orbs (if player has any orb power-ups)
  # Check if player has any orb power-ups before rendering
  if hasAnyOrbPowerUp(player) and player.rotatingOrbs.len > 0:
    let orbSizeScale = 15.5 + (player.radius - player.baseRadius) * 0.85
    let tPulse  = (sin(time * 4.0) * 0.12 + 0.88).float32
    let tPulseB = (sin(time * 6.0 + 1.0) * 0.18 + 0.82).float32

    # Draw one faint ring per active level tier (deduplicate by radius)
    var drawnRadii: array[4, bool]
    for orb in player.rotatingOrbs:
      let lv = orb.orbLevel
      if lv >= 1 and lv <= 4 and not drawnRadii[lv - 1]:
        drawnRadii[lv - 1] = true
        drawCircleLines(player.pos.x.int32, player.pos.y.int32, orb.radius,
                       Color(r: 200, g: 200, b: 200, a: 10))

    for orb in player.rotatingOrbs:
      # Calculate orb position
      # Rings 2 and 4 orbit backwards for a dynamic counter-rotating effect
      let orbRotDir = if orb.orbLevel == 2 or orb.orbLevel == 4: -1.0'f32 else: 1.0'f32
      let angle = orbRotDir * player.orbRotationAngle + orb.angle
      let orbX = player.pos.x + cos(angle) * orb.radius
      let orbY = player.pos.y + sin(angle) * orb.radius

      # Get element color
      let color = getElementColor(orb.elementType)

      # Comet tail: ghost orbs behind along the orbit
      # Tail direction follows the actual orbit direction
      for t in 1..6:
        let tailAngle = angle - orbRotDir * t.float32 * 0.21
        let tailAlpha = uint8(max(0, 52 - t * 9))
        let tailX = player.pos.x + cos(tailAngle) * orb.radius
        let tailY = player.pos.y + sin(tailAngle) * orb.radius
        let tailSize = orbSizeScale * 0.62 * (1.0 - t.float32 * 0.11)
        if tailSize > 1.5:
          drawCircle(Vector2(x: tailX, y: tailY), tailSize,
                    Color(r: color.r, g: color.g, b: color.b, a: tailAlpha))

      # Outer pulsing glow halo
      drawCircle(Vector2(x: orbX, y: orbY), orbSizeScale * 1.9 * tPulse,
                Color(r: color.r, g: color.g, b: color.b, a: 20))
      drawCircle(Vector2(x: orbX, y: orbY), orbSizeScale * 1.4,
                Color(r: color.r, g: color.g, b: color.b, a: 55))

      # Main orb body
      drawCircle(Vector2(x: orbX, y: orbY), orbSizeScale, color)

      # Outward energy ring (time-based pulse)
      let ringPulse = orbSizeScale * 1.2 + sin(time * 5.0 + orb.angle) * 2.5
      drawCircleLines(orbX.int32, orbY.int32, ringPulse,
                     Color(r: color.r, g: color.g, b: color.b, a: uint8(155.0 * tPulseB)))

      # Bright core + specular highlight
      drawCircle(Vector2(x: orbX, y: orbY), orbSizeScale * 0.44,
                Color(r: 255, g: 255, b: 255, a: 155))
      drawCircle(Vector2(x: orbX - orbSizeScale * 0.17, y: orbY - orbSizeScale * 0.17),
                orbSizeScale * 0.17,
                Color(r: 255, g: 255, b: 255, a: 200))

      # Element-specific visual effects (time-based)
      case orb.elementType:
      of etFire:
        # Animated flame sparks orbiting with upward float
        for i in 0..3:
          let flameAngle = time * 4.5 + i.float32 * PI * 0.5
          let flameDist = orbSizeScale + 3 + sin(time * 7.0 + i.float32 * 1.3) * 2.5
          let fx = orbX + cos(flameAngle) * flameDist
          let fy = orbY + sin(flameAngle) * flameDist - abs(sin(time * 8.0 + i.float32)) * 4.5
          drawCircle(Vector2(x: fx, y: fy), 2.5, Color(r: 255, g: 155, b: 25, a: 200))
          drawCircle(Vector2(x: fx, y: fy - 1.5), 1.2, Color(r: 255, g: 240, b: 100, a: 230))
      of etLightning:
        # Flickering electric arcs that change shape rapidly
        if (time * 12.0).int mod 2 == 0:
          for i in 0..3:
            let sparkAngle = time * 3.5 + i.float32 * PI * 0.5
            let sx = orbX + cos(sparkAngle) * (orbSizeScale + 7)
            let sy = orbY + sin(sparkAngle) * (orbSizeScale + 7)
            let mx = orbX + cos(sparkAngle + 0.35) * (orbSizeScale + 3.5)
            let my = orbY + sin(sparkAngle + 0.35) * (orbSizeScale + 3.5)
            drawLine(Vector2(x: orbX, y: orbY), Vector2(x: mx, y: my), 1,
                    Color(r: 220, g: 245, b: 255, a: 210))
            drawLine(Vector2(x: mx, y: my), Vector2(x: sx, y: sy), 1,
                    Color(r: 180, g: 215, b: 255, a: 160))
      of etPoison:
        # Rising bubbles from center of orb
        for i in 0..2:
          let bAngle = orb.angle * 2.0 + i.float32 * PI * 2.0 / 3.0
          let bRise = (time * 20.0 + i.float32 * 7.0) mod 13.0
          let bx = orbX + cos(bAngle) * (orbSizeScale * 0.55)
          let by = orbY + sin(bAngle) * (orbSizeScale * 0.55) - bRise
          let bAlpha = uint8(max(0, 185 - bRise.int * 14))
          let bSize = max(0.5, 2.2 - bRise * 0.12)
          drawCircle(Vector2(x: bx, y: by), bSize, Color(r: 135, g: 255, b: 135, a: bAlpha))
      of etWind:
        # Counter-rotating swirl streaks
        for i in 0..3:
          let streamAngle = -time * 5.5 + i.float32 * PI * 0.5
          for s in 0..1:
            let sd = orbSizeScale * 0.65 + s.float32 * 3.5
            let sx = orbX + cos(streamAngle + s.float32 * 0.28) * sd
            let sy = orbY + sin(streamAngle + s.float32 * 0.28) * sd
            drawCircle(Vector2(x: sx, y: sy), 1.5,
                      Color(r: 210, g: 235, b: 255, a: uint8(145 - s * 55)))
      of etArcane:
        # Counter-rotating rune dots with bright centers
        for i in 0..2:
          let runeAngle = -time * 3.2 + i.float32 * PI * 2.0 / 3.0
          let rx = orbX + cos(runeAngle) * (orbSizeScale + 5)
          let ry = orbY + sin(runeAngle) * (orbSizeScale + 5)
          drawCircle(Vector2(x: rx, y: ry), 2.8, Color(r: 230, g: 155, b: 255, a: 220))
          drawCircle(Vector2(x: rx, y: ry), 1.1, Color(r: 255, g: 230, b: 255, a: 255))
      of etFrost:
        # 6-pointed ice crystal spikes slowly rotating
        for i in 0..5:
          let crystalAngle = i.float32 * PI / 3.0 + time * 0.4
          let cx1 = orbX + cos(crystalAngle) * (orbSizeScale * 0.75)
          let cy1 = orbY + sin(crystalAngle) * (orbSizeScale * 0.75)
          let cx2 = orbX + cos(crystalAngle) * (orbSizeScale + 5.5)
          let cy2 = orbY + sin(crystalAngle) * (orbSizeScale + 5.5)
          drawLine(Vector2(x: cx1, y: cy1), Vector2(x: cx2, y: cy2), 1.5,
                  Color(r: 175, g: 215, b: 255, a: 195))
          drawCircle(Vector2(x: cx2, y: cy2), 1.5, Color(r: 220, g: 240, b: 255, a: 230))
      of etBlood:
        # Dripping blood drops falling downward from orbit
        for i in 0..2:
          let dropAngle = orb.angle + i.float32 * PI * 2.0 / 3.0
          let dropFall = (time * 18.0 + i.float32 * 6.0) mod 14.0
          let dx = orbX + cos(dropAngle) * (orbSizeScale * 0.55)
          let dy = orbY + sin(dropAngle) * (orbSizeScale * 0.55) + dropFall
          let dAlpha = uint8(max(0, 205 - dropFall.int * 15))
          let dSize = max(0.5, 2.5 - dropFall * 0.14)
          drawCircle(Vector2(x: dx, y: dy), dSize, Color(r: 220, g: 35, b: 35, a: dAlpha))
      else:
        discard  # etNone or other unknown types

proc takeDamage*(player: Player, damage: float32): bool =
  ## Returns true if player died (HP reached 0 or below), false otherwise
  # Shield boost absorbs hits first
  if player.shieldHits > 0:
    player.shieldHits -= 1
    # Visual/audio feedback happens in game.nim
    return false
  
  # Invincibility from consumables
  if player.invincibilityTimer > 0:
    return false
  
  # Parry invulnerability - also bounces bullets
  if player.parryActive:
    return false
  
  # Phase Shift invulnerability
  if player.phaseShiftInvulnTimer > 0:
    return false
  
  # Celestial Veil - absorb 1 hit per wave
  if player.celestialVeilActive and hasPowerUp(player, puCelestialVeil):
    player.celestialVeilActive = false
    player.lastDamageEvent = deCelestialVeil  # Signal "veil blocked"
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
        player.lastDamageEvent = deDodged
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
