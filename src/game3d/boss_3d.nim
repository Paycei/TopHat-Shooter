## 3D Boss Module - The Orbital Commander

import raylib, math, random
import types_3d, engine_3d, player_3d

const
  PHASE2_THRESHOLD = 0.66  # Transition to Phase 2 when HP drops to 66% (and all satellites destroyed)
  PHASE3_THRESHOLD = 0.33  # Transition to Phase 3 when HP drops to 33%

# BOSS INITIALIZATION

proc getBoss3D*(bossId: int): Boss3D =
  case bossId
  of 7:  # The Orbital Commander
    result = Boss3D(
      pos: vec3(0, 100, 0),
      health: 1500.0,
      maxHealth: 1500.0,
      phase: 1,
      attackTimer: 3.0,
      moveTimer: 0.0,
      satellites: @[],
      phaseTransitionTimer: 0.0,
      attackPattern: 0,
      patternTimer: 0.0,
      shieldActive: false,
      shieldHealth: 0.0,
      maxShieldHealth: 0.0,
      clones: @[],
      teleportTimer: 0.0,
      gravityWells: @[],
      berserkModeActive: false
    )

    # Phase 1: Initialize 4 satellites - MUST destroy ALL to damage core
    for i in 0..<4:
      let angle = i.float32 * 2.0 * PI / 4.0
      result.satellites.add(BossSatellite(
        pos: vec3(0, 100, 0),
        angle: angle,
        distance: 50.0,
        health: 250.0,
        maxHealth: 250.0,
        active: true,
        orbitSpeed: 0.8,
        laserChargeTimer: 0.0,
        targetSatelliteIndex: -1
      ))

  else:
    # Default boss
    result = Boss3D(
      pos: vec3(0, 100, 0),
      health: 1000.0,
      maxHealth: 1000.0,
      phase: 1,
      attackTimer: 2.0,
      moveTimer: 0.0,
      satellites: @[],
      phaseTransitionTimer: 0.0,
      attackPattern: 0,
      patternTimer: 0.0,
      shieldActive: false,
      shieldHealth: 0.0,
      maxShieldHealth: 0.0,
      clones: @[],
      teleportTimer: 0.0,
      gravityWells: @[],
      berserkModeActive: false
    )

# PHASE TRANSITION LOGIC

proc initiatePhaseTransition(boss: var Boss3D, newPhase: int, arena: var Arena3D) =
  ## Handle phase transitions with environment changes
  boss.phase = newPhase
  boss.phaseTransitionTimer = 2.0
  boss.attackPattern = 0
  boss.patternTimer = 0.0

  case newPhase
  of 2:  # PHASE 2: Core exposed, gravity mechanics
    # Change environment dramatically
    arena.skyColor = Color(r: 40, g: 10, b: 60, a: 255)
    arena.floorColor = Color(r: 60, g: 20, b: 80, a: 255)
    arena.environmentIntensity = 0.6
    # Platforms start rotating
    for platform in arena.platforms.mitems:
      if platform.rotationSpeed == 0.0:
        platform.rotationSpeed = 0.3

  of 3:  # PHASE 3: Final stand
    boss.berserkModeActive = true
    # Environment becomes chaotic
    arena.skyColor = Color(r: 80, g: 0, b: 20, a: 255)
    arena.floorColor = Color(r: 100, g: 10, b: 30, a: 255)
    arena.environmentIntensity = 1.0
    # Faster platform rotation
    for platform in arena.platforms.mitems:
      platform.rotationSpeed = 0.6

  else:
    discard

proc executePhase1Attacks(boss: var Boss3D, player: Player3D, projectiles: var seq[Projectile3D]) =
  ## PHASE 1: Satellites attack - Core is COMPLETELY INVULNERABLE
  var activeSats: seq[int] = @[]
  for i, sat in boss.satellites:
    if sat.active:
      activeSats.add(i)

  if activeSats.len > 0:
    # 2 satellites shoot simultaneously
    let numShooters = min(2, activeSats.len)
    for j in 0..<numShooters:
      let satIdx = activeSats[rand(activeSats.len - 1)]
      let sat = boss.satellites[satIdx]
      let dir = (player.pos - sat.pos).normalize()

      projectiles.add(Projectile3D(
        pos: sat.pos,
        vel: dir * 280.0,
        damage: 10.0,
        lifetime: 6.0,
        fromPlayer: false,
        active: true,
        isHoming: false,
        homingTarget: vec3(0, 0, 0),
        homingStrength: 0.0
      ))

    boss.attackTimer = 1.2

proc executePhase2Attacks(boss: var Boss3D, player: Player3D, projectiles: var seq[Projectile3D]) =
  ## PHASE 2: Core attacks + gravity wells + teleportation

  if boss.attackPattern == 0:
    # Pattern A: 16-way spiral from core
    for i in 0..<16:
      let angle = i.float32 * 2.0 * PI / 16.0 + boss.moveTimer * 2.0
      let dir = vec3(cos(angle), 0, sin(angle)).normalize()

      projectiles.add(Projectile3D(
        pos: boss.pos,
        vel: dir * 220.0,
        damage: 8.0,
        lifetime: 7.0,
        fromPlayer: false,
        active: true,
        isHoming: false,
        homingTarget: vec3(0, 0, 0),
        homingStrength: 0.0
      ))

    boss.attackTimer = 2.5
    boss.attackPattern = 1

  elif boss.attackPattern == 1:
    # Pattern B: Teleport behind player + radial burst
    # Teleport to behind player
    let toPlayer = (player.pos - boss.pos).normalize()
    let teleportPos = player.pos - toPlayer * 100.0
    boss.pos.x = teleportPos.x
    boss.pos.z = teleportPos.z
    boss.pos.y = 100.0

    # Set teleport timer to prevent movement override
    boss.teleportTimer = 0.5  # Stay in place for 0.5 seconds after teleport

    # Fire radial burst from new position
    for i in 0..<12:
      let angle = i.float32 * 2.0 * PI / 12.0
      let dir = vec3(cos(angle), 0, sin(angle)).normalize()

      projectiles.add(Projectile3D(
        pos: boss.pos,
        vel: dir * 250.0,
        damage: 10.0,
        lifetime: 6.0,
        fromPlayer: false,
        active: true,
        isHoming: false,
        homingTarget: vec3(0, 0, 0),
        homingStrength: 0.0
      ))

    boss.attackTimer = 2.0
    boss.attackPattern = 2

  else:
    # Pattern C: Gravity wells
    for i in 0..<2:
      let angle = rand(2.0 * PI).float32
      let distance = 80.0 + rand(80.0).float32
      let wellPos = vec3(
        cos(angle) * distance,
        80.0 + rand(40.0).float32,
        sin(angle) * distance
      )

      boss.gravityWells.add(GravityWell(
        pos: wellPos,
        strength: 180.0,
        radius: 70.0,
        lifetime: 6.0,
        active: true
      ))

    boss.attackTimer = 3.0
    boss.attackPattern = 0

proc executePhase3Attacks(boss: var Boss3D, player: Player3D, projectiles: var seq[Projectile3D]) =
  ## PHASE 3: Berserk - Everything unleashed

  # Continuous rapid-fire
  if int(boss.moveTimer * 12) mod 4 == 0:
    let dirToPlayer = (player.pos - boss.pos).normalize()
    projectiles.add(Projectile3D(
      pos: boss.pos,
      vel: dirToPlayer * 400.0,
      damage: 10.0,
      lifetime: 5.0,
      fromPlayer: false,
      active: true,
      isHoming: false,
      homingTarget: vec3(0, 0, 0),
      homingStrength: 0.0
    ))

  # Periodic massive attacks
  if boss.attackTimer <= 0:
    if boss.attackPattern mod 2 == 0:
      # Homing swarm
      for i in 0..<8:
        let angle = i.float32 * 2.0 * PI / 8.0
        let offset = vec3(cos(angle) * 25.0, 0, sin(angle) * 25.0)

        projectiles.add(Projectile3D(
          pos: boss.pos + offset,
          vel: vec3(0, 0, 0),
          damage: 15.0,
          lifetime: 8.0,
          fromPlayer: false,
          active: true,
          isHoming: true,
          homingTarget: player.pos,
          homingStrength: 200.0
        ))

      boss.attackTimer = 2.5
    else:
      # Gravity well + spiral combo
      boss.gravityWells.add(GravityWell(
        pos: vec3(cos(boss.moveTimer) * 100.0, 90.0, sin(boss.moveTimer) * 100.0),
        strength: 250.0,
        radius: 80.0,
        lifetime: 5.0,
        active: true
      ))

      for i in 0..<12:
        let angle = i.float32 * 2.0 * PI / 12.0 + boss.moveTimer * 3.0
        let dir = vec3(cos(angle), 0, sin(angle)).normalize()

        projectiles.add(Projectile3D(
          pos: boss.pos,
          vel: dir * 280.0,
          damage: 12.0,
          lifetime: 7.0,
          fromPlayer: false,
          active: true,
          isHoming: false,
          homingTarget: vec3(0, 0, 0),
          homingStrength: 0.0
        ))

      boss.attackTimer = 2.0

    boss.attackPattern += 1

proc updateBoss*(boss: var Boss3D, player: var Player3D, projectiles: var seq[Projectile3D],
                 arena: var Arena3D, dt: float32) =

  boss.moveTimer += dt

  # Phase transition invulnerability
  if boss.phaseTransitionTimer > 0:
    boss.phaseTransitionTimer -= dt
    return

  # Check for phase transitions based on HP
  let healthPercent = boss.health / boss.maxHealth

  if healthPercent <= PHASE3_THRESHOLD and boss.phase < 3:
    initiatePhaseTransition(boss, 3, arena)
  elif healthPercent <= PHASE2_THRESHOLD and boss.phase < 2:
    # Check if all satellites destroyed
    var allSatellitesDestroyed = true
    for sat in boss.satellites:
      if sat.active:
        allSatellitesDestroyed = false
        break

    if allSatellitesDestroyed:
      initiatePhaseTransition(boss, 2, arena)

  # Update satellite orbits
  for sat in boss.satellites.mitems:
    if sat.active:
      sat.angle += dt * sat.orbitSpeed
      sat.pos.x = boss.pos.x + cos(sat.angle) * sat.distance
      sat.pos.z = boss.pos.z + sin(sat.angle) * sat.distance
      sat.pos.y = boss.pos.y

  # Boss movement based on phase
  # Update teleport timer
  if boss.teleportTimer > 0:
    boss.teleportTimer -= dt

  # Only apply movement patterns if not in teleport cooldown
  if boss.teleportTimer <= 0:
    case boss.phase
    of 1:
      # Slow orbital
      let moveAngle = boss.moveTimer * 0.2
      let moveRadius = 150.0
      boss.pos.x = cos(moveAngle) * moveRadius
      boss.pos.z = sin(moveAngle) * moveRadius
      boss.pos.y = 100.0 + sin(boss.moveTimer * 0.5) * 10.0

    of 2:
      # Faster, erratic
      let moveAngle = boss.moveTimer * 0.4
      let moveRadius = 120.0 + sin(boss.moveTimer * 0.8) * 50.0
      boss.pos.x = cos(moveAngle) * moveRadius
      boss.pos.z = sin(moveAngle) * moveRadius
      boss.pos.y = 100.0 + sin(boss.moveTimer * 1.2) * 20.0

    of 3:
      # Aggressive positioning
      let toPlayer = player.pos - boss.pos
      if toPlayer.length() > 100.0:
        boss.pos = boss.pos + toPlayer.normalize() * 150.0 * dt
      boss.pos.y = 100.0 + sin(boss.moveTimer * 0.8) * 15.0

    else:
      discard

  # Update timers
  boss.attackTimer -= dt

  # Execute attacks
  if boss.attackTimer <= 0:
    case boss.phase
    of 1:
      executePhase1Attacks(boss, player, projectiles)
    of 2:
      executePhase2Attacks(boss, player, projectiles)
    of 3:
      executePhase3Attacks(boss, player, projectiles)
    else:
      discard

  # Update gravity wells
  var i = 0
  while i < boss.gravityWells.len:
    boss.gravityWells[i].lifetime -= dt

    if boss.gravityWells[i].lifetime <= 0:
      boss.gravityWells.delete(i)
    else:
      # Apply gravity to player
      let toPlayer = player.pos - boss.gravityWells[i].pos
      let dist = toPlayer.length()

      if dist < boss.gravityWells[i].radius:
        let pullDir = (boss.gravityWells[i].pos - player.pos).normalize()
        let pullStrength = boss.gravityWells[i].strength * (1.0 - dist / boss.gravityWells[i].radius)
        player.vel = player.vel + pullDir * pullStrength * dt

      i += 1

  # Update homing projectiles
  for proj in projectiles.mitems:
    if proj.isHoming and proj.active and not proj.fromPlayer:
      let toTarget = player.pos - proj.pos
      let homingForce = toTarget.normalize() * proj.homingStrength
      proj.vel = (proj.vel + homingForce * dt).normalize() * proj.vel.length()

# RENDERING

proc drawBoss*(boss: Boss3D) =
  # Phase transition flash
  if boss.phaseTransitionTimer > 0:
    let flashIntensity = sin(boss.phaseTransitionTimer * 10.0) * 0.5 + 0.5
    drawSphere(Vector3(x: boss.pos.x, y: boss.pos.y, z: boss.pos.z),
              25.0, fade(White, flashIntensity * 0.8))

  # Core color and size based on phase
  var coreColor: Color
  var coreSize = 20.0

  case boss.phase
  of 1:
    coreColor = Color(r: 120, g: 120, b: 120, a: 255)  # Gray - protected
  of 2:
    coreColor = Color(r: 150, g: 50, b: 200, a: 255)  # Purple - exposed
    coreSize = 22.0
  of 3:
    coreColor = Color(r: 255, g: 0, b: 0, a: 255)  # Red - berserk
    coreSize = 30.0 + sin(boss.moveTimer * 5.0) * 3.0  # Pulsing
  else:
    coreColor = Gray

  # Draw core
  drawSphere(Vector3(x: boss.pos.x, y: boss.pos.y, z: boss.pos.z), coreSize, coreColor)

  # Draw core glow
  let glowSize = coreSize + 2.0 + sin(boss.moveTimer * 2.0) * 1.0
  drawSphere(Vector3(x: boss.pos.x, y: boss.pos.y, z: boss.pos.z), glowSize, fade(coreColor, 0.3))

  # Draw satellites
  for sat in boss.satellites:
    if sat.active:
      let satColor = if boss.phase >= 2: Color(r: 200, g: 50, b: 255, a: 255) else: Purple
      drawSphere(Vector3(x: sat.pos.x, y: sat.pos.y, z: sat.pos.z), 5.0, satColor)

      # Orbit trail
      drawLine3D(Vector3(x: boss.pos.x, y: boss.pos.y, z: boss.pos.z),
                Vector3(x: sat.pos.x, y: sat.pos.y, z: sat.pos.z),
                fade(satColor, 0.3))

      # Satellite glow
      drawSphere(Vector3(x: sat.pos.x, y: sat.pos.y, z: sat.pos.z), 6.0, fade(satColor, 0.2))

proc drawGravityWells*(boss: Boss3D) =
  for well in boss.gravityWells:
    if well.active:
      let progress = well.lifetime / 6.0
      let alpha = progress * 0.4

      # Core
      drawSphere(Vector3(x: well.pos.x, y: well.pos.y, z: well.pos.z),
                8.0, fade(Color(r: 150, g: 0, b: 150, a: 255), alpha))

      # Radius indicator
      drawSphereWires(Vector3(x: well.pos.x, y: well.pos.y, z: well.pos.z),
                     well.radius, 8, 8, fade(Color(r: 200, g: 0, b: 200, a: 255), alpha * 0.5))

proc drawSatelliteHealthbars*(boss: Boss3D, camera: FPSCamera) =
  for sat in boss.satellites:
    if sat.active:
      let barPos = Vector3(x: sat.pos.x, y: sat.pos.y + 10.0, z: sat.pos.z)

      let screenPos = getWorldToScreen(barPos,
        Camera(
          position: Vector3(x: camera.position.x, y: camera.position.y, z: camera.position.z),
          target: Vector3(x: camera.target.x, y: camera.target.y, z: camera.target.z),
          up: Vector3(x: 0, y: 1, z: 0),
          fovy: camera.fovy,
          projection: CameraProjection.Perspective
        )
      )

      if screenPos.x >= 0 and screenPos.x <= getScreenWidth().float32 and
         screenPos.y >= 0 and screenPos.y <= getScreenHeight().float32:

        let barWidth = 60.0
        let barHeight = 8.0
        let healthPercent = sat.health / sat.maxHealth

        # Background
        drawRectangle(int32(screenPos.x - barWidth / 2), int32(screenPos.y - barHeight / 2),
                     int32(barWidth), int32(barHeight), Color(r: 100, g: 0, b: 0, a: 200))

        # Foreground
        drawRectangle(int32(screenPos.x - barWidth / 2), int32(screenPos.y - barHeight / 2),
                     int32(barWidth * healthPercent), int32(barHeight), Color(r: 150, g: 100, b: 255, a: 255))

        # Border
        drawRectangleLines(int32(screenPos.x - barWidth / 2), int32(screenPos.y - barHeight / 2),
                          int32(barWidth), int32(barHeight), White)

proc takeBossDamage*(boss: var Boss3D, projectile: Projectile3D): tuple[hit: bool, damageDealt: float32, isSatellite: bool, hitPos: Vector3f] =
  # Phase transition invulnerability
  if boss.phaseTransitionTimer > 0:
    return (false, 0.0, false, vec3(0, 0, 0))

  # Check satellite hits
  for sat in boss.satellites.mitems:
    if sat.active and distance(sat.pos, projectile.pos) < 6.0:
      let damageDealt = min(projectile.damage, sat.health)
      sat.health -= projectile.damage
      if sat.health <= 0:
        sat.active = false
      return (true, damageDealt, true, sat.pos)

  # PHASE 1: Core is COMPLETELY INVULNERABLE while ANY satellites exist
  if boss.phase == 1:
    var anySatelliteActive = false
    for sat in boss.satellites:
      if sat.active:
        anySatelliteActive = true
        break

    if anySatelliteActive:
      # Core cannot be damaged - satellites must be destroyed first
      return (false, 0.0, false, vec3(0, 0, 0))

  # PHASE 2+: Core is vulnerable
  if distance(boss.pos, projectile.pos) < 22.0:
    let damageDealt = min(projectile.damage, boss.health)
    boss.health -= projectile.damage
    return (true, damageDealt, false, boss.pos)

  (false, 0.0, false, vec3(0, 0, 0))