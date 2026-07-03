import raylib, math, random, std/deques
import particle_types, types, wall, powerup, powerup_data, localization, skins, shapes, cube_skins, ui/ui_constants, settings, utils

const
  PlayerAcceleration = 7.0'f32
  PlayerBraking = 1.8'f32
  PlayerInertiaReferenceRadius = 14.0'f32

proc approachVelocity(current, target: Vector2f, acceleration, dt: float32): Vector2f =
  ## Framerate-independent velocity easing for movement inertia.
  let blend = 1.0'f32 - pow(0.001'f32, acceleration * dt)
  current + (target - current) * clamp(blend, 0.0'f32, 1.0'f32)

proc playerInertiaSizeScale(player: Player): float32 =
  let safeRadius = max(player.radius, 1.0'f32)
  clamp(sqrt(safeRadius / PlayerInertiaReferenceRadius), 0.75'f32, 1.85'f32)

proc dataHarvestRangeMult*(player: Player): float32 =
  ## DATA_HARVEST.dll widens the pickup/collection aura: +25% / +50% / +100%
  ## at levels 1 / 2 / 3 (mirrors its XP multiplier in xp_orb.nim).
  case getPowerUpLevel(player, puDataHarvest)
  of 0: 1.0'f32
  of 1: 1.25'f32
  of 2: 1.5'f32
  else: 2.0'f32

proc refreshPlayerSize(player: Player) =
  ## Keep radius-derived gameplay values current before movement inertia reads them.
  let hpAboveBase = max(0.0'f32, player.maxHp - 7.5'f32)
  player.radius = player.baseRadius + sqrt(hpAboveBase) * 0.4'f32
  # Base collection aura, widened by DATA_HARVEST.dll. This single assignment is
  # the source of truth for pickup range (coins, XP orbs, and consumables all
  # test against player.auraRadius), so the bonus applies everywhere at once.
  player.auraRadius = player.radius * 3.5 * dataHarvestRangeMult(player)

proc orbCoreColor(elementType: ElementType, base: Color): Color =
  case elementType
  of etFire: Color(r: 255, g: 225, b: 90, a: 255)
  of etLightning: Color(r: 245, g: 255, b: 255, a: 255)
  of etPoison: Color(r: 215, g: 255, b: 160, a: 255)
  of etWind: Color(r: 235, g: 255, b: 255, a: 255)
  of etFrost: Color(r: 230, g: 250, b: 255, a: 255)
  of etArcane: Color(r: 255, g: 210, b: 255, a: 255)
  of etBlood: Color(r: 255, g: 150, b: 150, a: 255)
  else: brighten(base, 45)

proc newPlayer*(x, y: float32): Player =
  result = Player(
    pos: newVector2f(x, y),
    vel: newVector2f(0, 0),
    radius: 14,
    baseRadius: 14,
    hp: 9,
    maxHp: 9,
    speed: 177.5,
    baseSpeed: 177.5,
    damage: 1,
    bulletDamageMult: 1.0,  # Multiplier for bullet-only damage bonuses (e.g. Arcane Bullets)
    fireRate: 0.4275,
    bulletSpeed: 325,
    lastShot: 0,
    coins: 0,
    kills: 0,
    walls: 0,
    rogueliteLevel: 1,    # Roguelite in-run level (see xp_orb.nim)
    xp: 0,
    xpToNextLevel: 10,    # mirrors xpRequiredForLevel(1) in xp_orb.nim
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
    # Singularity (Gravity Well) regenerating HP-based shield defaults
    singularityShield: 0.0,
    singularityShieldMaxPct: 0.10,    # 10% of max HP
    singularityShieldRegenTimer: 0.0,
    singularityShieldRegenDelay: 5.0, # Regen starts after 5 seconds without damage
    singularityShieldRegenRatePct: 0.005, # Regenerate 5% of max shield (0.5% of max HP) per second
    killsSinceLastHeal: 0,
    regenTimer: 0,
    lastDamageEvent: deNone,
    rageStacks: 0,
    critCharge: 0,
    auraRadius: 50.0,  # Invisible coin collection aura
    doubleShotDelay: 0,
    rapidFireSpinup: 0,  # Minigun spin-up meter (RapidFire legendary)
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
    pulseArmorTriggered: false,
    skinType: 0,  # Default skin (skDefault)
    bulletSkinType: 0,
    bulletShapeType: 0,
    shapeType: 0,
    particleSkinType: 0,
    hasVolatile: false,
    resonanceLevel: 0,
    bloodPactCooldown: 0.0,
    conduitCooldown: 0.0,
    aftershockCooldown: 0.0,
    aftershockPosHistory: initDeque[Vector2f](),
    aftershockSampleTimer: 0.0,
    novaCooldown: 0.0,
    novaActive: false,
    novaFreezeTimer: 0.0,
    healPowerMult: 1.0,
  )

proc hasAnyOrbPowerUp*(player: Player): bool =
  ## Check if player has any orb power-up equipped (rotating legendary + all elemental orbs)
  if hasPowerUp(player, puRotatingOrbs): return true
  for orbType in elementalOrbTypes:
    if hasPowerUp(player, orbType): return true
  return false

proc updatePlayer*(player: Player, dt: float32, screenWidth, screenHeight: int32, walls: seq[Wall]) =
  # Update powerup timers
  if player.speedBoostTimer > 0:
    player.speedBoostTimer -= dt
  if player.invincibilityTimer > 0:
    player.invincibilityTimer -= dt
  if player.fireRateBoostTimer > 0:
    player.fireRateBoostTimer -= dt
  if player.adaptiveFirewallTimer > 0:
    player.adaptiveFirewallTimer -= dt
  if player.killChainTimer > 0:
    player.killChainTimer -= dt
    if player.killChainTimer <= 0:
      player.killChainCount = 0  # Window expired, reset streak
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

  # Update new legendary active ability cooldowns
  if player.bloodPactCooldown > 0:
    player.bloodPactCooldown -= dt
  if player.conduitCooldown > 0:
    player.conduitCooldown -= dt
  if player.aftershockCooldown > 0:
    player.aftershockCooldown -= dt
  if player.novaCooldown > 0:
    player.novaCooldown -= dt

  # Nova freeze timer - count down and release bullets when expired
  # (Actual bullet release is handled in game.nim updateGame loop)
  if player.novaActive and player.novaFreezeTimer > 0:
    player.novaFreezeTimer -= dt
    if player.novaFreezeTimer <= 0:
      player.novaFreezeTimer = 0
      player.novaActive = false
      # Note: bullet release (vel *= 1.5, isFrozenByNova = false) done in game.nim

  # Aftershock position history sampling (every 0.05s = 40 samples for 2s of history)
  if player.aftershockCooldown >= 0:  # always sample (even when cooldown is 0)
    player.aftershockSampleTimer += dt
    if player.aftershockSampleTimer >= 0.05:
      player.aftershockSampleTimer -= 0.05
      player.aftershockPosHistory.addLast(player.pos)
      # Keep only the last 40 samples (2 seconds at 0.05s intervals)
      if player.aftershockPosHistory.len > 40:
        player.aftershockPosHistory.popFirst()

  # Update Pulse Armor cooldown. Clamp at 0 so it never crosses into negative
  # (a negative cooldown used to be misread as the trigger sentinel, causing
  # spurious auto-fires every cooldown cycle).
  if player.pulseArmorCooldown > 0:
    player.pulseArmorCooldown = max(0.0'f32, player.pulseArmorCooldown - dt)

  let oldRadius = player.radius
  refreshPlayerSize(player)
  if player.rotatingOrbs.len > 0 and abs(player.radius - oldRadius) > 0.001'f32:
    redistributeAllOrbs(player)

  # Calculate current speed with boost
  var currentSpeed = player.speed
  if player.speedBoostTimer > 0:
    currentSpeed *= 1.4  # 40% speed boost
  if player.outOfCombatSpeedBoost:
    currentSpeed *= 1.25  # Roguelite out-of-combat bonus

  var moveDir = newVector2f(0, 0)

  let kb = globalSettings.keybinds
  if isKeyDown(kb[kaMoveUp]): moveDir.y -= 1
  if isKeyDown(kb[kaMoveDown]): moveDir.y += 1
  if isKeyDown(kb[kaMoveLeft]): moveDir.x -= 1
  if isKeyDown(kb[kaMoveRight]): moveDir.x += 1

  if moveDir.length() > 0:
    moveDir = moveDir.normalize()
  let targetVel = moveDir * currentSpeed
  let inertiaScale = playerInertiaSizeScale(player)
  let acceleration = (if moveDir.length() > 0: PlayerAcceleration else: PlayerBraking) / inertiaScale
  player.vel = approachVelocity(player.vel, targetVel, acceleration, dt)

  # Calculate next position
  let nextPos = player.pos + player.vel * dt

  # Wall collision with sliding. The move is redirected along the contacted
  # wall's surface normal so the player glides along faces hit at an angle.
  # (Per-axis resolution alone freezes on rotated faces, where both the X-only
  # and Y-only probes penetrate the slab.) A per-axis fallback handles inside
  # corners where the tangential slide still ends inside a wall.
  proc hitsAnyWall(p: Vector2f): bool =
    for w in walls:
      if checkPlayerWallCollision(p, player.radius, w):
        return true
    false

  var move = nextPos - player.pos
  if hitsAnyWall(player.pos + move):
    # Subtract the component pushing into each contacted wall; iterate a few
    # times so multi-wall contacts settle.
    for _ in 0 ..< 3:
      let target = player.pos + move
      var n = newVector2f(0, 0)
      var hit = false
      for w in walls:
        if checkPlayerWallCollision(target, player.radius, w):
          n = n + wallContactNormal(w, target)
          hit = true
      if not hit: break
      let nl = n.length()
      if nl < 0.0001'f32: break
      n = n * (1.0'f32 / nl)
      let moveInto = move.x * n.x + move.y * n.y
      if moveInto < 0:
        move = move - n * moveInto        # project the move onto the wall tangent
      let velInto = player.vel.x * n.x + player.vel.y * n.y
      if velInto < 0:
        player.vel = player.vel - n * velInto

  if not hitsAnyWall(player.pos + move):
    player.pos = player.pos + move
  else:
    # Inside corner: let whichever single axis is free still pass.
    if not hitsAnyWall(newVector2f(player.pos.x + move.x, player.pos.y)):
      player.pos.x = player.pos.x + move.x
    else:
      player.vel.x = 0
    if not hitsAnyWall(newVector2f(player.pos.x, player.pos.y + move.y)):
      player.pos.y = player.pos.y + move.y
    else:
      player.vel.y = 0

  # Clamp to screen
  if player.pos.x < player.radius:
    player.pos.x = player.radius
    if player.vel.x < 0: player.vel.x = 0
  if player.pos.x > screenWidth.float32 - player.radius:
    player.pos.x = screenWidth.float32 - player.radius
    if player.vel.x > 0: player.vel.x = 0
  if player.pos.y < player.radius:
    player.pos.y = player.radius
    if player.vel.y < 0: player.vel.y = 0
  if player.pos.y > screenHeight.float32 - player.radius:
    player.pos.y = screenHeight.float32 - player.radius
    if player.vel.y > 0: player.vel.y = 0

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

  # Singularity (Gravity Well) - HP-based shield that regenerates after delay
  # NOTE: runs independently of puRotatingShield
  if hasPowerUp(player, puGravityWell):
    let shieldMax = player.maxHp * player.singularityShieldMaxPct
    # Clamp current shield to new max if max HP changed
    if player.singularityShield > shieldMax:
      player.singularityShield = shieldMax

    if player.singularityShield < shieldMax:
      player.singularityShieldRegenTimer += dt
      if player.singularityShieldRegenTimer >= player.singularityShieldRegenDelay:
        let regenAmount = player.maxHp * player.singularityShieldRegenRatePct * dt
        player.singularityShield = min(player.singularityShield + regenAmount, shieldMax)
    else:
      # Fully charged - reset timer
      player.singularityShieldRegenTimer = 0.0
  else:
    # Clear when not active
    player.singularityShield = 0.0
    player.singularityShieldRegenTimer = 0.0

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
      # Outer boundary ring, clearly visible
      drawCircleLines(player.pos.x.int32, player.pos.y.int32, slowRadius + 3.0,
                     Color(r: 100, g: 150, b: 255, a: 70))
      drawCircleLines(player.pos.x.int32, player.pos.y.int32, slowRadius,
                     Color(r: 120, g: 170, b: 255, a: 210))
      # Rotating dots at 68% radius, gives it a sense of rotation
      let dashRadius = slowRadius * 0.68
      for d in 0..7:
        let dashAngle = time * (-0.55) + d.float32 * PI * 0.25
        let dx = player.pos.x + cos(dashAngle) * dashRadius
        let dy = player.pos.y + sin(dashAngle) * dashRadius
        drawCircle(Vector2(x: dx, y: dy), 2.5, Color(r: 140, g: 185, b: 255, a: 65))

    # Fire aura visual
    if powerUp.powerType == puFireAura:
      let fireRadius = case powerUp.level
        of 1: 187.5
        of 2: 250.0
        else: 312.5
      let alpha = 40 + (sin(player.shieldAngle * 4) * 20).int
      drawCircle(Vector2(x: player.pos.x, y: player.pos.y), fireRadius,
                Color(r: 255, g: 50, b: 0, a: alpha.uint8))
      drawCircleLines(player.pos.x.int32, player.pos.y.int32, fireRadius + 3.0,
                     Color(r: 255, g: 80, b: 0, a: 65))
      drawCircleLines(player.pos.x.int32, player.pos.y.int32, fireRadius,
                     Color(r: 255, g: 100, b: 0, a: 210))

    # Lightning aura visual
    if powerUp.powerType == puLightningAura:
      let lightningRadius = case powerUp.level
        of 1: 187.5
        of 2: 250.0
        else: 312.5
      let alpha = 25 + (sin(player.shieldAngle * 5) * 15).int
      drawCircle(Vector2(x: player.pos.x, y: player.pos.y), lightningRadius,
                Color(r: 100, g: 150, b: 255, a: alpha.uint8))
      drawCircleLines(player.pos.x.int32, player.pos.y.int32, lightningRadius + 3.0,
                     Color(r: 100, g: 180, b: 255, a: 65))
      drawCircleLines(player.pos.x.int32, player.pos.y.int32, lightningRadius,
                     Color(r: 150, g: 210, b: 255, a: 210))

    # Poison aura visual
    if powerUp.powerType == puPoisonAura:
      let poisonRadius = case powerUp.level
        of 1: 187.5
        of 2: 250.0
        else: 312.5
      let alpha = 35 + (sin(player.shieldAngle * 3) * 20).int
      drawCircle(Vector2(x: player.pos.x, y: player.pos.y), poisonRadius,
                Color(r: 100, g: 200, b: 100, a: alpha.uint8))
      drawCircleLines(player.pos.x.int32, player.pos.y.int32, poisonRadius + 3.0,
                     Color(r: 80, g: 200, b: 80, a: 65))
      drawCircleLines(player.pos.x.int32, player.pos.y.int32, poisonRadius,
                     Color(r: 100, g: 230, b: 100, a: 210))

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

  # Singularity (Gravity Well) shield visual - translucent purple halo
  if hasPowerUp(player, puGravityWell) and player.singularityShield > 0.0:
    let shieldMax = player.maxHp * player.singularityShieldMaxPct
    let shieldFrac = if shieldMax > 0.0: clamp(player.singularityShield / shieldMax, 0.0, 1.0) else: 0.0
    let shieldRadius = player.radius * 2.4
    let fillAlpha = uint8(40 + (shieldFrac * 160).int)
    let lineAlpha = uint8(90 + (shieldFrac * 140).int)
    drawCircle(Vector2(x: player.pos.x, y: player.pos.y), shieldRadius,
               Color(r: 170, g: 110, b: 255, a: fillAlpha))
    drawCircleLines(player.pos.x.int32, player.pos.y.int32, shieldRadius,
                    Color(r: 170, g: 110, b: 255, a: lineAlpha))

  # Celestial Veil, soft translucent ring around the player while the charge is ready.
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

  # Dodge flash effect, takeDamage sets lastDamageEvent = deDodged as a one-frame signal.
  if player.lastDamageEvent == deDodged and player.hp > 0:
    drawText(t(tkPlayerDodge), (player.pos.x - 25).int32, (player.pos.y - 35).int32, 14, Yellow)
    player.lastDamageEvent = deNone  # Consume flag

  # Celestial Veil absorbed-hit flash, takeDamage sets lastDamageEvent = deCelestialVeil.
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

  # Skin-colored motion trail: faint afterimages while moving at speed.
  # Skipped during speed boost, which draws its own stronger trail below.
  if player.speedBoostTimer <= 0:
    let speed = player.vel.length()
    if speed > 80:
      let trailStrength = min((speed - 80.0) / 260.0, 1.0)
      for i in 1..3:
        let trailAlpha = uint8(trailStrength * (42 - i * 11).float32)
        let trailScale = 0.9 - i.float32 * 0.18
        let trailX = player.pos.x - player.vel.x * i.float32 * 0.012
        let trailY = player.pos.y - player.vel.y * i.float32 * 0.012
        drawCircle(Vector2(x: trailX, y: trailY), player.radius * trailScale,
                  Color(r: baseColor.r, g: baseColor.g, b: baseColor.b, a: trailAlpha))

  # Draw player using selected shape
  let shapeType = player.shapeType.ShapeType
  drawPlayerShape(player.pos, player.radius, shapeType, baseColor, secondaryColor, coreColor,
                  time, rotation, pulse, glowIntensity)

  # Secret cosmetic: the kernel's tophat, earned by clearing wave 60.
  # Band and outline take the player's current body color so the hat
  # matches the equipped skin (and status tints like invincibility gold).
  if player.wearsTophat:
    drawTopHat(player.pos, player.radius, time, 1.0'f32, baseColor)

  # Secret cosmetic: the cheater hat, earned by opening cd+ during a run.
  # Drawn after the tophat so it visually takes priority when both are enabled.
  if player.wearsCheaterHat:
    drawCheaterHat(player.pos, player.radius, time)

  # Secret cosmetic: the desktop cube, knocked out of orbit (Escape Velocity),
  # now orbits the player. Colored by the equipped desktop-cube skin.
  if player.hasOrbitalCube:
    let cubeSkin = CubeSkinType(clamp(player.cubeSkinType, 0, ord(high(CubeSkinType))))
    let cubeData = getCubeSkinData(cubeSkin)
    let orbitAngle = time * 1.3
    let orbitDist = player.radius * 2.5 + sin(time * 2.1) * 3.0
    let cubeCenter = Vector2(
      x: player.pos.x + cos(orbitAngle) * orbitDist,
      y: player.pos.y + sin(orbitAngle) * orbitDist * 0.72 + sin(time * 3.1) * 2.0)
    let cubeHeart = if cubeSkin == cskCompanion: Color(r: 244, g: 116, b: 150, a: 255)
                    else: Color(r: 0, g: 0, b: 0, a: 0)
    drawMiniCube(cubeCenter, 8.0'f32, time, cubeData.edgeColor, cubeData.glowColor, cubeHeart,
                isD20 = cubeSkin == cskD20, skin = cubeSkin, secretStyle = true)

  # Roguelite class emblem: a run-scoped cosmetic marking the chosen starter
  # kit. Body/side-mounted (and an inner orbit for the Arcanist), so it never
  # collides with the head-worn secret hats or the wider orbital-cube secret.
  if player.rogueliteCosmetic > 0:
    drawRogueliteClassCosmetic(player.pos, player.radius, time,
                               player.rogueliteCosmetic, baseColor)

  # 6. DATA PARTICLES (orbiting effect)
  if player.vel.length() > 10 or pulse > 0.7:
    let numParticles = 8
    for i in 0..<numParticles:
      let particleAngle = time * 3.0 + i.float32 * PI * 2.0 / numParticles.float32
      let particleDist = player.radius + 6 + sin(time * 4.0 + i.float32) * 2
      let px = player.pos.x + cos(particleAngle) * particleDist
      let py = player.pos.y + sin(particleAngle) * particleDist
      let particleAlpha = uint8(100 + pulse * 80)
      # Alternate primary/secondary skin colors so both show in motion
      let pColor = if i mod 2 == 0: baseColor else: secondaryColor
      drawCircle(Vector2(x: px, y: py), 1.8,
                Color(r: pColor.r, g: pColor.g, b: pColor.b, a: particleAlpha))

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

        # Pass 1, outer glow halo (wide, soft)
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

        # Pass 2, main arc (solid, medium thickness)
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

        # Pass 3, inner highlight (bright white-tinted, thin)
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

        # Endpoint energy nodes, animated pulse
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
    let playerOrbSizeBonus = max(0.0'f32, player.radius - player.baseRadius) * 0.85'f32
    let tPulse  = (sin(time * 4.0) * 0.12 + 0.88).float32
    let tPulseB = (sin(time * 6.0 + 1.0) * 0.18 + 0.82).float32

    # Draw one orbit lane per active level tier (deduplicate by radius).
    var drawnRadii: array[4, bool]
    for orb in player.rotatingOrbs:
      let lv = orb.orbLevel
      if lv >= 1 and lv <= 4 and not drawnRadii[lv - 1]:
        drawnRadii[lv - 1] = true
        let lanePulse = sin(time * (1.8 + lv.float32 * 0.25) + lv.float32) * 1.8
        let laneAlpha = 12 + lv * 4
        drawCircleLines(player.pos.x.int32, player.pos.y.int32, orb.radius + lanePulse,
                       Color(r: 190, g: 215, b: 255, a: clampByte(laneAlpha)))
        drawCircleLines(player.pos.x.int32, player.pos.y.int32, orb.radius - 3.0,
                       Color(r: 255, g: 255, b: 255, a: clampByte(5 + lv * 2)))

    for orb in player.rotatingOrbs:
      # Calculate orb position
      # Rings 2 and 4 orbit backwards for a dynamic counter-rotating effect
      let orbRotDir = if orb.orbLevel == 2 or orb.orbLevel == 4: -1.0'f32 else: 1.0'f32
      let angle = orbRotDir * player.orbRotationAngle + orb.angle
      let orbX = player.pos.x + cos(angle) * orb.radius
      let orbY = player.pos.y + sin(angle) * orb.radius

      let color = getElementColor(orb.elementType)
      let hotColor = brighten(color, 45)
      let shadowColor = darken(color, 70)
      let coreColor = orbCoreColor(orb.elementType, color)
      let levelScale = 1.0'f32 + min(3, max(0, orb.orbLevel - 1)).float32 * 0.08'f32
      let orbSize = (13.5'f32 + playerOrbSizeBonus) * levelScale

      drawLine(Vector2(x: player.pos.x, y: player.pos.y),
               Vector2(x: orbX, y: orbY), 1.0,
               withAlpha(color, 16 + min(12, orb.orbLevel * 3)))

      # Wide luminous trail following the actual orbit direction.
      const trailSegments = 12
      for segment in 0..<trailSegments:
        let fade = 1.0'f32 - segment.float32 / trailSegments.float32
        let trailAngle0 = angle - orbRotDir * (segment.float32 * 0.105'f32 + 0.08'f32)
        let trailAngle1 = angle - orbRotDir * ((segment.float32 + 1.0'f32) * 0.105'f32 + 0.08'f32)
        let x0 = player.pos.x + cos(trailAngle0) * orb.radius
        let y0 = player.pos.y + sin(trailAngle0) * orb.radius
        let x1 = player.pos.x + cos(trailAngle1) * orb.radius
        let y1 = player.pos.y + sin(trailAngle1) * orb.radius
        let trailWidth = max(1.1'f32, orbSize * (0.18'f32 + fade * 0.22'f32))
        let trailAlpha = int(118.0'f32 * fade * fade)
        drawLine(Vector2(x: x0, y: y0), Vector2(x: x1, y: y1), trailWidth,
                 withAlpha(color, trailAlpha))
        drawLine(Vector2(x: x0, y: y0), Vector2(x: x1, y: y1),
                 max(1.0'f32, trailWidth * 0.32'f32), withAlpha(hotColor, trailAlpha div 2))

      # Comet tail ghost-orbs give the path a readable sense of speed.
      for t in 1..8:
        let tailAngle = angle - orbRotDir * t.float32 * 0.18
        let tailAlpha = max(0, 82 - t * 9)
        let tailX = player.pos.x + cos(tailAngle) * orb.radius
        let tailY = player.pos.y + sin(tailAngle) * orb.radius
        let tailSize = orbSize * 0.72 * (1.0'f32 - t.float32 * 0.085'f32)
        if tailSize > 1.5:
          drawCircle(Vector2(x: tailX, y: tailY), tailSize,
                    withAlpha(color, tailAlpha))
          drawCircle(Vector2(x: tailX, y: tailY), tailSize * 0.38,
                    withAlpha(coreColor, tailAlpha div 2))

      # Layered glow, shadow rim, body, and bright glassy core.
      drawCircle(Vector2(x: orbX, y: orbY), orbSize * 2.15 * tPulse,
                withAlpha(color, 18))
      drawCircle(Vector2(x: orbX, y: orbY), orbSize * 1.55,
                withAlpha(color, 52))
      drawCircle(Vector2(x: orbX, y: orbY), orbSize * 1.12,
                withAlpha(shadowColor, 210))
      drawCircle(Vector2(x: orbX, y: orbY), orbSize * 0.92, color)

      let ringPulse = orbSize * 1.24 + sin(time * 5.0 + orb.angle) * 2.6
      drawCircleLines(orbX.int32, orbY.int32, ringPulse,
                     withAlpha(hotColor, int(165.0'f32 * tPulseB)))
      drawCircleLines(orbX.int32, orbY.int32, orbSize * 1.02,
                     withAlpha(brighten(color, 80), 210))

      drawCircle(Vector2(x: orbX, y: orbY), orbSize * 0.46,
                withAlpha(coreColor, 190))
      drawCircle(Vector2(x: orbX - orbSize * 0.20, y: orbY - orbSize * 0.20),
                orbSize * 0.18,
                Color(r: 255, g: 255, b: 255, a: 220))
      drawCircle(Vector2(x: orbX + orbSize * 0.18, y: orbY + orbSize * 0.16),
                orbSize * 0.10,
                withAlpha(shadowColor, 125))

      # Element-specific visual effects (time-based)
      case orb.elementType:
      of etFire:
        # Animated flame sparks orbiting with upward float
        for i in 0..3:
          let flameAngle = time * 4.5 + i.float32 * PI * 0.5
          let flameDist = orbSize + 3 + sin(time * 7.0 + i.float32 * 1.3) * 2.5
          let fx = orbX + cos(flameAngle) * flameDist
          let fy = orbY + sin(flameAngle) * flameDist - abs(sin(time * 8.0 + i.float32)) * 4.5
          drawCircle(Vector2(x: fx, y: fy), 2.5, Color(r: 255, g: 155, b: 25, a: 200))
          drawCircle(Vector2(x: fx, y: fy - 1.5), 1.2, Color(r: 255, g: 240, b: 100, a: 230))
      of etLightning:
        # Flickering electric arcs that change shape rapidly
        if (time * 12.0).int mod 2 == 0:
          for i in 0..3:
            let sparkAngle = time * 3.5 + i.float32 * PI * 0.5
            let sx = orbX + cos(sparkAngle) * (orbSize + 7)
            let sy = orbY + sin(sparkAngle) * (orbSize + 7)
            let mx = orbX + cos(sparkAngle + 0.35) * (orbSize + 3.5)
            let my = orbY + sin(sparkAngle + 0.35) * (orbSize + 3.5)
            drawLine(Vector2(x: orbX, y: orbY), Vector2(x: mx, y: my), 1,
                    Color(r: 220, g: 245, b: 255, a: 210))
            drawLine(Vector2(x: mx, y: my), Vector2(x: sx, y: sy), 1,
                    Color(r: 180, g: 215, b: 255, a: 160))
      of etPoison:
        # Rising bubbles from center of orb
        for i in 0..2:
          let bAngle = orb.angle * 2.0 + i.float32 * PI * 2.0 / 3.0
          let bRise = (time * 20.0 + i.float32 * 7.0) mod 13.0
          let bx = orbX + cos(bAngle) * (orbSize * 0.55)
          let by = orbY + sin(bAngle) * (orbSize * 0.55) - bRise
          let bAlpha = uint8(max(0, 185 - bRise.int * 14))
          let bSize = max(0.5, 2.2 - bRise * 0.12)
          drawCircle(Vector2(x: bx, y: by), bSize, Color(r: 135, g: 255, b: 135, a: bAlpha))
      of etWind:
        # Counter-rotating swirl streaks
        for i in 0..3:
          let streamAngle = -time * 5.5 + i.float32 * PI * 0.5
          for s in 0..1:
            let sd = orbSize * 0.65 + s.float32 * 3.5
            let sx = orbX + cos(streamAngle + s.float32 * 0.28) * sd
            let sy = orbY + sin(streamAngle + s.float32 * 0.28) * sd
            drawCircle(Vector2(x: sx, y: sy), 1.5,
                      Color(r: 210, g: 235, b: 255, a: uint8(145 - s * 55)))
      of etArcane:
        # Counter-rotating rune dots with bright centers
        for i in 0..2:
          let runeAngle = -time * 3.2 + i.float32 * PI * 2.0 / 3.0
          let rx = orbX + cos(runeAngle) * (orbSize + 5)
          let ry = orbY + sin(runeAngle) * (orbSize + 5)
          drawCircle(Vector2(x: rx, y: ry), 2.8, Color(r: 230, g: 155, b: 255, a: 220))
          drawCircle(Vector2(x: rx, y: ry), 1.1, Color(r: 255, g: 230, b: 255, a: 255))
      of etFrost:
        # 6-pointed ice crystal spikes slowly rotating
        for i in 0..5:
          let crystalAngle = i.float32 * PI / 3.0 + time * 0.4
          let cx1 = orbX + cos(crystalAngle) * (orbSize * 0.75)
          let cy1 = orbY + sin(crystalAngle) * (orbSize * 0.75)
          let cx2 = orbX + cos(crystalAngle) * (orbSize + 5.5)
          let cy2 = orbY + sin(crystalAngle) * (orbSize + 5.5)
          drawLine(Vector2(x: cx1, y: cy1), Vector2(x: cx2, y: cy2), 1.5,
                  Color(r: 175, g: 215, b: 255, a: 195))
          drawCircle(Vector2(x: cx2, y: cy2), 1.5, Color(r: 220, g: 240, b: 255, a: 230))
      of etBlood:
        # Dripping blood drops falling downward from orbit
        for i in 0..2:
          let dropAngle = orb.angle + i.float32 * PI * 2.0 / 3.0
          let dropFall = (time * 18.0 + i.float32 * 6.0) mod 14.0
          let dx = orbX + cos(dropAngle) * (orbSize * 0.55)
          let dy = orbY + sin(dropAngle) * (orbSize * 0.55) + dropFall
          let dAlpha = uint8(max(0, 205 - dropFall.int * 15))
          let dSize = max(0.5, 2.5 - dropFall * 0.14)
          drawCircle(Vector2(x: dx, y: dy), dSize, Color(r: 220, g: 35, b: 35, a: dAlpha))
      else:
        discard  # etNone or other unknown types

proc takeDamage*(player: Player, damage: float32): bool =
  ## Returns true if player died (HP reached 0 or below), false otherwise
  player.lastDamageAvoided = 0.0  # Reset each call
  # Shield boost absorbs hits first
  if player.shieldHits > 0:
    player.shieldHits -= 1
    player.lastDamageAvoided = damage
    # Visual/audio feedback happens in game.nim
    return false

  # Invincibility from consumables
  if player.invincibilityTimer > 0:
    player.lastDamageAvoided = damage
    return false

  # Parry invulnerability - also bounces bullets
  if player.parryActive:
    player.lastDamageAvoided = damage
    return false

  # Phase Shift invulnerability
  if player.phaseShiftInvulnTimer > 0:
    player.lastDamageAvoided = damage
    return false

  # Celestial Veil - absorb 1 hit per wave
  if player.celestialVeilActive and hasPowerUp(player, puCelestialVeil):
    player.celestialVeilActive = false
    player.lastDamageAvoided = damage
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
        player.lastDamageAvoided = damage
        player.lastDamageEvent = deDodged
        return false

  # Apply Fortified damage reduction
  var finalDamage = damage
  for powerUp in player.powerUps:
    if powerUp.powerType == puFortified:
      let reduction = case powerUp.level
        of 1: 0.1  # 10% reduction
        of 2: 0.2  # 20% reduction
        else: 0.3  # 30% reduction
      finalDamage *= (1.0 - reduction)
      break

  # Singularity (Gravity Well) HP-based shield absorbs damage first
  if hasPowerUp(player, puGravityWell) and player.singularityShield > 0.0:
    let absorb = min(player.singularityShield, finalDamage)
    if absorb > 0.0:
      player.singularityShield -= absorb
      finalDamage -= absorb
      # Reset regen timer on damage
      player.singularityShieldRegenTimer = 0.0
      # Mark recent damage for UI/feedback
      player.lastDamageEvent = deDamage
    if finalDamage <= 0.0:
      return false

  player.hp -= finalDamage

  # Clamp HP to 0 minimum
  if player.hp < 0:
    player.hp = 0

  player.lastDamageEvent = deDamage
  # Reset singularity shield regen timer on any player damage
  player.singularityShieldRegenTimer = 0.0

  # AdaptiveFirewall: fire rate boost after taking damage
  if hasPowerUp(player, puAdaptiveFirewall):
    player.adaptiveFirewallTimer = 3.0'f32

  # Pulse Armor - emit shockwave when taking damage (if not on cooldown)
  if player.pulseArmorCooldown <= 0 and hasPowerUp(player, puPulseArmor):
    # Trigger shockwave next frame in game.nim; cooldown is set there.
    player.pulseArmorTriggered = true

  # LastStand: intercept lethal damage once per life with 3s invulnerability
  if player.hp <= 0 and hasPowerUp(player, puLastStand) and not player.lastStandActivated:
    player.hp = 1.0'f32
    player.lastStandActivated = true
    player.invincibilityTimer = 3.0'f32
    return false

  # Return true if HP reached 0 or below (death condition)
  return player.hp <= 0

proc heal*(player: Player, amount: float32) =
  player.hp += amount * player.healPowerMult
  if player.hp > player.maxHp: player.hp = player.maxHp

proc activateSpeedBoost*(player: Player) =
  player.speedBoostTimer = 5.0

proc activateInvincibility*(player: Player) =
  player.invincibilityTimer = 3.0

proc activateFireRateBoost*(player: Player) =
  player.fireRateBoostTimer = 8.0

proc activateMagnet*(player: Player) =
  player.magnetTimer = 10.0
