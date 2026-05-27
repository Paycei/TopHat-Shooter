## PARTICLE POOLING SYSTEM FOR PERFORMANCE
## Instead of constantly creating and destroying particles, we reuse them from a pool.

import raylib, random, math
import particle_types


const
  DEFAULT_POOL_SIZE* = 2000
  POOL_GROWTH_SIZE* = 500
  MAX_POOL_SIZE = DEFAULT_POOL_SIZE * 4
  PARTICLE_CULL_MARGIN = 24.0'f32
  PARTICLE_DESPAWN_MARGIN = 140.0'f32
  PARTICLE_SOFT_FRAME_SPAWN_LIMIT = 180.0'f32

proc particlePressure(pool: ParticlePool): float32 =
  let usagePressure =
    if pool.maxCapacity > 0: pool.activeCount.float32 / pool.maxCapacity.float32
    else: 0.0'f32
  let spawnPressure = clamp(pool.spawnedThisFrame.float32 / PARTICLE_SOFT_FRAME_SPAWN_LIMIT, 0.0'f32, 1.0'f32)
  max(usagePressure, spawnPressure)

proc scaledParticleBurstCount*(pool: ParticlePool, requestedCount: int): int =
  if requestedCount <= 0:
    return 0

  let pressure = particlePressure(pool)
  let scale =
    if pressure >= 0.96'f32: 0.25'f32
    elif pressure >= 0.88'f32: 0.40'f32
    elif pressure >= 0.78'f32: 0.55'f32
    elif pressure >= 0.66'f32: 0.72'f32
    elif pressure >= 0.54'f32: 0.85'f32
    else: 1.0'f32

  if scale >= 1.0'f32:
    return requestedCount

  let minimumCount = if requestedCount >= 6: 2 else: 1
  max(minimumCount, int(ceil(requestedCount.float32 * scale)))

proc particleRenderSettings(activeCount: int): tuple[drawStep: int, simplified: bool, drawHalos: bool] =
  if activeCount >= 1200:
    (3, true, false)
  elif activeCount >= 700:
    (2, true, false)
  elif activeCount >= 250:
    (1, true, false)
  elif activeCount >= 120:
    (1, false, false)
  else:
    (1, false, true)

proc isParticleVisible(particle: ptr Particle, screenWidth, screenHeight: float32): bool =
  let haloRadius =
    if particle.glow > 0: particle.size * (1.5'f32 + particle.glow * 0.45'f32)
    else: particle.size
  let margin = haloRadius + PARTICLE_CULL_MARGIN
  particle.pos.x >= -margin and particle.pos.x <= screenWidth + margin and
    particle.pos.y >= -margin and particle.pos.y <= screenHeight + margin

proc drawSimplifiedParticle(particle: ptr Particle, pos: Vector2, mainColor, coreColor: Color) =
  case particle.style
  of psSpark:
    let velLen = particle.vel.length()
    let dir =
      if velLen > 0.01'f32: particle.vel.normalize()
      else:
        let angle = particle.rotation * PI.float32 / 180.0'f32
        newVector2f(cos(angle), sin(angle))
    let streakLength = max(1.5'f32, particle.size * (1.2'f32 + min(1.8'f32, velLen / 150.0'f32)))
    drawLine(
      (particle.pos.x - dir.x * streakLength * 0.4'f32).int32,
      (particle.pos.y - dir.y * streakLength * 0.4'f32).int32,
      (particle.pos.x + dir.x * streakLength * 0.6'f32).int32,
      (particle.pos.y + dir.y * streakLength * 0.6'f32).int32,
      mainColor
    )
  of psShard:
    drawPoly(pos, 4, max(0.8'f32, particle.size * 0.8'f32), particle.rotation, mainColor)
  of psEmber, psSoft:
    drawCircle(pos, max(0.7'f32, particle.size * 0.75'f32), mainColor)

proc clampByte(value: float32): uint8 =
  uint8(clamp(value, 0.0'f32, 255.0'f32).int)

proc alphaScaled(color: Color, scale: float32): Color =
  result = color
  result.a = clampByte(color.a.float32 * scale)

proc brighten(color: Color, amount: float32): Color =
  result = Color(
    r: clampByte(color.r.float32 + amount),
    g: clampByte(color.g.float32 + amount),
    b: clampByte(color.b.float32 + amount),
    a: color.a
  )

proc newParticleTemplate(): Particle =
  Particle(
    pos: newVector2f(0, 0),
    vel: newVector2f(0, 0),
    color: Color(r: 0, g: 0, b: 0, a: 0),
    coreColor: Color(r: 0, g: 0, b: 0, a: 0),
    lifetime: 0.0,
    maxLifetime: 0.0,
    size: 0.0,
    startSize: 0.0,
    endSize: 0.0,
    drag: 0.0,
    gravity: 0.0,
    glow: 0.0,
    style: psSoft,
    layer: plBackground,
    rotation: 0.0,
    spin: 0.0
  )

proc newParticlePool*(initialCapacity: int = DEFAULT_POOL_SIZE): ParticlePool =
  ## Create a new particle pool with pre-allocated particles
  result = ParticlePool(
    particles: newSeq[Particle](initialCapacity),
    activeCount: 0,
    maxCapacity: initialCapacity,
    spawnedThisFrame: 0
  )

  for i in 0..<initialCapacity:
    result.particles[i] = newParticleTemplate()

proc configureParticle(particle: var Particle, x, y, velX, velY: float32,
                       color: Color, lifetime, startSize, endSize, drag,
                       gravity, glow: float32, style: ParticleStyle,
                       layer: ParticleLayer,
                       rotation, spin: float32) =
  particle.pos.x = x
  particle.pos.y = y
  particle.vel.x = velX
  particle.vel.y = velY
  particle.color = color
  particle.coreColor = brighten(color, 65.0)
  particle.lifetime = lifetime
  particle.maxLifetime = lifetime
  particle.size = startSize
  particle.startSize = startSize
  particle.endSize = endSize
  particle.drag = drag
  particle.gravity = gravity
  particle.glow = glow
  particle.style = style
  particle.layer = layer
  particle.rotation = rotation
  particle.spin = spin

proc reserveParticleSlot(pool: ParticlePool): int =
  if pool.activeCount < pool.maxCapacity:
    result = pool.activeCount
    pool.activeCount += 1
    return

  if pool.maxCapacity < MAX_POOL_SIZE:
    let oldCapacity = pool.maxCapacity
    pool.maxCapacity = min(oldCapacity + POOL_GROWTH_SIZE, MAX_POOL_SIZE)
    for _ in oldCapacity..<pool.maxCapacity:
      pool.particles.add(newParticleTemplate())
    result = pool.activeCount
    pool.activeCount += 1
    return

  var oldestIndex = 0
  var oldestLifetimeRatio = 2.0'f32
  for i in 0..<pool.activeCount:
    let particle = pool.particles[i]
    let ratio =
      if particle.maxLifetime > 0: particle.lifetime / particle.maxLifetime
      else: 0.0'f32
    if ratio < oldestLifetimeRatio:
      oldestLifetimeRatio = ratio
      oldestIndex = i
  result = oldestIndex

proc resetParticle(particle: var Particle, x, y: float32, color: Color, speed: float32) =
  ## Reset a particle to new values (for reuse)
  let angle = rand(1.0) * PI * 2.0
  let velocity = newVector2f(cos(angle) * speed, sin(angle) * speed)
  let lifetime = 0.35'f32 + rand(0.45).float32
  let startSize = 2.4'f32 + rand(3.8).float32
  let style =
    if rand(1.0) < 0.18: psSpark
    elif rand(1.0) < 0.35: psShard
    else: psSoft

  configureParticle(
    particle,
    x, y,
    velocity.x, velocity.y,
    color,
    lifetime,
    startSize,
    max(0.35'f32, startSize * (0.18'f32 + rand(0.18).float32)),
    3.0'f32 + rand(4.0).float32,
    (-18.0 + rand(36.0)).float32,
    0.8'f32 + rand(0.7).float32,
    style,
    plBackground,
    rand(360.0).float32,
    (-280.0 + rand(560.0)).float32
  )

proc acquireParticleDetailed*(pool: ParticlePool, x, y, velX, velY: float32,
                              color: Color, lifetime: float32 = 0.5,
                              startSize: float32 = 3.5, endSize: float32 = 0.5,
                              drag: float32 = 4.0, gravity: float32 = 0.0,
                              glow: float32 = 1.0, style: ParticleStyle = psSoft,
                              layer: ParticleLayer = plBackground,
                              rotation: float32 = 0.0, spin: float32 = 0.0): bool =
  let idx = reserveParticleSlot(pool)
  configureParticle(pool.particles[idx], x, y, velX, velY, color,
                    lifetime, startSize, endSize, drag, gravity, glow,
                    style, layer, rotation, spin)
  pool.spawnedThisFrame += 1
  true

proc acquireParticle*(pool: ParticlePool, x, y: float32, color: Color, speed: float32): bool =
  ## Get a particle from the pool and initialize it
  let idx = reserveParticleSlot(pool)
  resetParticle(pool.particles[idx], x, y, color, speed)
  pool.spawnedThisFrame += 1
  true

proc isParticleWithinSimulationBounds(particle: ptr Particle, screenWidth, screenHeight: float32): bool =
  let haloRadius =
    if particle.glow > 0: particle.size * (1.5'f32 + particle.glow * 0.45'f32)
    else: particle.size
  let margin = haloRadius + PARTICLE_DESPAWN_MARGIN
  particle.pos.x >= -margin and particle.pos.x <= screenWidth + margin and
    particle.pos.y >= -margin and particle.pos.y <= screenHeight + margin

proc updateParticlePool*(pool: ParticlePool, dt: float32) =
  ## Update all active particles and compact the pool
  if pool.activeCount <= 0 or dt <= 0.0'f32:
    pool.spawnedThisFrame = 0
    return

  let screenWidth = getScreenWidth().float32
  let screenHeight = getScreenHeight().float32
  var writeIndex = 0
  for i in 0..<pool.activeCount:
    let particle = addr pool.particles[i]

    particle.vel.y += particle.gravity * dt
    let dragFactor = 1.0'f32 / (1.0'f32 + particle.drag * dt)
    particle.vel.x *= dragFactor
    particle.vel.y *= dragFactor
    particle.pos.x += particle.vel.x * dt
    particle.pos.y += particle.vel.y * dt
    particle.rotation += particle.spin * dt
    particle.lifetime -= dt

    if particle.lifetime <= 0.0'f32:
      continue

    let lifeRatio =
      if particle.maxLifetime > 0: clamp(particle.lifetime / particle.maxLifetime, 0.0'f32, 1.0'f32)
      else: 0.0'f32
    let sizeEase = lifeRatio * lifeRatio * (3.0'f32 - 2.0'f32 * lifeRatio)
    particle.size = particle.endSize + (particle.startSize - particle.endSize) * sizeEase

    if not isParticleWithinSimulationBounds(particle, screenWidth, screenHeight):
      continue

    if writeIndex != i:
      pool.particles[writeIndex] = particle[]
    writeIndex += 1

  pool.activeCount = writeIndex
  pool.spawnedThisFrame = 0

proc drawParticlePoolLayer*(pool: ParticlePool, layer: ParticleLayer) =
  ## Draw only particles assigned to the given layer
  let renderSettings = particleRenderSettings(pool.activeCount)
  let screenWidth = getScreenWidth().float32
  let screenHeight = getScreenHeight().float32
  var layerIndex = 0

  for i in 0..<pool.activeCount:
    let particle = addr pool.particles[i]
    if particle.layer != layer:
      continue
    if not isParticleVisible(particle, screenWidth, screenHeight):
      continue
    layerIndex += 1
    if renderSettings.drawStep > 1 and ((layerIndex - 1) mod renderSettings.drawStep) != 0:
      continue
    let lifeRatio =
      if particle.maxLifetime > 0: clamp(particle.lifetime / particle.maxLifetime, 0.0'f32, 1.0'f32)
      else: 0.0'f32
    let fade = sqrt(lifeRatio)
    let mainColor = alphaScaled(particle.color, fade)
    let haloColor = alphaScaled(particle.color, fade * 0.24'f32 * (0.8'f32 + particle.glow * 0.35'f32))
    let coreColor = alphaScaled(particle.coreColor, fade * 0.9'f32)
    let pos = Vector2(x: particle.pos.x, y: particle.pos.y)

    if renderSettings.drawHalos and particle.glow > 0:
      drawCircle(pos, particle.size * (1.5'f32 + particle.glow * 0.45'f32), haloColor)

    if renderSettings.simplified:
      drawSimplifiedParticle(particle, pos, mainColor, coreColor)
      continue

    case particle.style
    of psSoft:
      drawCircle(pos, particle.size, mainColor)
      drawCircle(pos, max(0.7'f32, particle.size * 0.4'f32), coreColor)
    of psSpark:
      let velLen = particle.vel.length()
      let dir =
        if velLen > 0.01'f32: particle.vel.normalize()
        else:
          let angle = particle.rotation * PI.float32 / 180.0'f32
          newVector2f(cos(angle), sin(angle))
      let streakLength = particle.size * (1.5'f32 + min(2.8'f32, velLen / 110.0'f32))
      let startPos = Vector2(x: particle.pos.x - dir.x * streakLength * 0.45'f32,
                             y: particle.pos.y - dir.y * streakLength * 0.45'f32)
      let endPos = Vector2(x: particle.pos.x + dir.x * streakLength * 0.55'f32,
                           y: particle.pos.y + dir.y * streakLength * 0.55'f32)
      let thickness = max(1.0'f32, particle.size * 0.38'f32)
      let perp = newVector2f(-dir.y, dir.x)
      for layer in -1..1:
        let offset = perp * (thickness * 0.45'f32 * layer.float32)
        drawLine(
          (startPos.x + offset.x).int32, (startPos.y + offset.y).int32,
          (endPos.x + offset.x).int32, (endPos.y + offset.y).int32,
          mainColor
        )
      drawCircle(pos, max(0.8'f32, particle.size * 0.24'f32), coreColor)
    of psEmber:
      drawCircle(pos, particle.size * 0.95'f32, alphaScaled(mainColor, 0.88'f32))
      drawCircle(pos, max(0.6'f32, particle.size * 0.32'f32), coreColor)
    of psShard:
      drawPoly(pos, 4, particle.size, particle.rotation, mainColor)
      drawPoly(pos, 4, max(0.5'f32, particle.size * 0.55'f32), particle.rotation, coreColor)

proc drawParticlePool*(pool: ParticlePool) =
  ## Draw all active particles from the pool
  drawParticlePoolLayer(pool, plBackground)
  drawParticlePoolLayer(pool, plForeground)

proc spawnExplosionPooled*(pool: ParticlePool, x, y: float32, color: Color, count: int = 20) =
  ## Spawn a richer mixed explosion burst using the pool
  let adjustedCount = scaledParticleBurstCount(pool, count)
  for _ in 0..<adjustedCount:
    let angle = rand(1.0) * PI * 2.0
    let speed = 85.0'f32 + rand(145.0).float32
    let velX = cos(angle) * speed
    let velY = sin(angle) * speed
    let roll = rand(1.0)
    let style =
      if roll < 0.20: psSpark
      elif roll < 0.38: psShard
      elif roll < 0.62: psEmber
      else: psSoft
    let startSize =
      case style
      of psSpark: 1.8'f32 + rand(1.7).float32
      of psShard: 2.2'f32 + rand(2.1).float32
      of psEmber: 2.6'f32 + rand(2.5).float32
      of psSoft: 3.0'f32 + rand(3.0).float32
    let lifetime =
      case style
      of psSpark: 0.16'f32 + rand(0.15).float32
      of psShard: 0.22'f32 + rand(0.18).float32
      of psEmber: 0.30'f32 + rand(0.28).float32
      of psSoft: 0.26'f32 + rand(0.22).float32
    let gravity =
      case style
      of psEmber: 45.0'f32 + rand(75.0).float32
      of psSpark: 0.0'f32
      else: (-15.0 + rand(30.0)).float32
    discard pool.acquireParticleDetailed(
      x, y, velX, velY, color,
      lifetime = lifetime,
      startSize = startSize,
      endSize = max(0.25'f32, startSize * (0.12'f32 + rand(0.18).float32)),
      drag = 3.5'f32 + rand(4.5).float32,
      gravity = gravity,
      glow = 0.9'f32 + rand(0.9).float32,
      style = style,
      rotation = rand(360.0).float32,
      spin = (-360.0 + rand(720.0)).float32
    )

  let flashCount = max(1, adjustedCount div 8)
  let flashColor = brighten(color, 80.0)
  for _ in 0..<flashCount:
    let angle = rand(1.0) * PI * 2.0
    let speed = 40.0'f32 + rand(60.0).float32
    discard pool.acquireParticleDetailed(
      x, y, cos(angle) * speed, sin(angle) * speed, flashColor,
      lifetime = 0.12'f32 + rand(0.08).float32,
      startSize = 5.0'f32 + rand(2.0).float32,
      endSize = 0.6'f32,
      drag = 6.0'f32,
      glow = 1.5'f32,
      style = psSoft
    )

proc spawnTrailParticlePooled*(pool: ParticlePool, x, y: float32, color: Color, count: int) =
  ## Spawn short-lived trail particles optimized for bullet trails
  let adjustedCount = scaledParticleBurstCount(pool, count)
  for i in 0..<adjustedCount:
    let angle = rand(1.0) * PI * 2.0
    let speed = 18.0'f32 + rand(34.0).float32
    let style = if i mod 3 == 0: psSoft else: psSpark
    discard pool.acquireParticleDetailed(
      x, y, cos(angle) * speed, sin(angle) * speed, color,
      lifetime = 0.10'f32 + rand(0.12).float32,
      startSize = if style == psSpark: 1.6'f32 + rand(1.0).float32 else: 2.0'f32 + rand(1.2).float32,
      endSize = 0.2'f32,
      drag = 7.0'f32 + rand(4.0).float32,
      gravity = if style == psSoft: 10.0'f32 + rand(20.0).float32 else: 0.0'f32,
      glow = if style == psSpark: 0.7'f32 else: 1.0'f32,
      style = style
    )

proc spawnTimedParticlesPooled*(pool: ParticlePool, x, y: float32, rate: float32,
                                color: Color, count: int, dt: float32) =
  if rand(1.0) < (rate * dt):
    spawnExplosionPooled(pool, x, y, color, count)

proc spawnTimedParticlesAroundPooled*(pool: ParticlePool, centerX, centerY: float32,
                                      maxRadius: float32, rate: float32, color: Color,
                                      count: int, dt: float32, offsetY: float32 = 0.0) =
  if rand(1.0) < (rate * dt):
    let particleAngle = rand(1.0) * PI * 2.0
    let particleDist = rand(maxRadius)
    let particleX = centerX + cos(particleAngle) * particleDist
    let particleY = centerY + sin(particleAngle) * particleDist + offsetY
    spawnExplosionPooled(pool, particleX, particleY, color, count)

proc spawnShockwavePooled*(pool: ParticlePool, x, y: float32, radius: float32) =
  ## Spawn an outward ring of bright sparks
  let particleCount = scaledParticleBurstCount(pool, max(6, (radius * 0.18'f32).int))
  let shockColor = Color(r: 255, g: 220, b: 140, a: 255)
  for i in 0..<particleCount:
    let angle = i.float32 / particleCount.float32 * PI * 2.0
    let px = x + cos(angle) * radius
    let py = y + sin(angle) * radius
    let speed = 70.0'f32 + rand(45.0).float32
    discard pool.acquireParticleDetailed(
      px, py, cos(angle) * speed, sin(angle) * speed, shockColor,
      lifetime = 0.18'f32 + rand(0.14).float32,
      startSize = 2.0'f32 + rand(1.6).float32,
      endSize = 0.2'f32,
      drag = 4.0'f32 + rand(2.0).float32,
      glow = 1.25'f32,
      style = if i mod 3 == 0: psShard else: psSpark,
      rotation = angle * 180.0'f32 / PI.float32
    )

proc spawnExplosiveRingPooled*(pool: ParticlePool, x, y: float32, radius: float32,
                               ringCount: int, color: Color) =
  ## Spawn concentric rings of particles for explosive bullets
  for ring in 1..ringCount:
    let ringRadius = radius * (ring.float32 / ringCount.float32)
    let particlesInRing = scaledParticleBurstCount(pool, max(4, (ringRadius * 0.16'f32).int))

    for i in 0..<particlesInRing:
      let angle = i.float32 / particlesInRing.float32 * PI * 2.0
      let px = x + cos(angle) * ringRadius
      let py = y + sin(angle) * ringRadius
      let speed = 35.0'f32 + ring.float32 * 12.0'f32 + rand(35.0).float32
      discard pool.acquireParticleDetailed(
        px, py, cos(angle) * speed, sin(angle) * speed, color,
        lifetime = 0.22'f32 + rand(0.18).float32,
        startSize = max(1.2'f32, 3.4'f32 - ring.float32 * 0.45'f32) + rand(0.8).float32,
        endSize = 0.25'f32,
        drag = 4.2'f32 + rand(2.0).float32,
        glow = 0.8'f32 + ring.float32 * 0.12'f32,
        style = if (i + ring) mod 4 == 0: psSpark else: psSoft,
        rotation = angle * 180.0'f32 / PI.float32
      )

proc spawnSpiralExplosionPooled*(pool: ParticlePool, x, y: float32, radius: float32,
                                 armCount: int, color: Color) =
  ## Spawn particles in a spiral pattern radiating outward
  let particlesPerArm = scaledParticleBurstCount(pool, max(3, (radius * 0.05'f32).int))

  for arm in 0..<armCount:
    let baseAngle = (arm.float32 / armCount.float32) * PI * 2.0

    for i in 0..<particlesPerArm:
      let progress = i.float32 / particlesPerArm.float32
      let spiralAngle = baseAngle + progress * PI * 0.7
      let spiralRadius = radius * progress
      let px = x + cos(spiralAngle) * spiralRadius
      let py = y + sin(spiralAngle) * spiralRadius
      let tangent = spiralAngle + PI * 0.5
      let speed = 45.0'f32 + progress * 95.0'f32 + rand(28.0).float32
      discard pool.acquireParticleDetailed(
        px, py, cos(tangent) * speed, sin(tangent) * speed, color,
        lifetime = 0.20'f32 + progress * 0.22'f32 + rand(0.10).float32,
        startSize = 1.8'f32 + progress * 2.2'f32 + rand(0.7).float32,
        endSize = 0.2'f32,
        drag = 3.0'f32 + rand(2.5).float32,
        glow = 0.9'f32 + progress * 0.7'f32,
        style = if i mod 3 == 0: psSpark else: psSoft,
        rotation = spiralAngle * 180.0'f32 / PI.float32,
        spin = 60.0'f32 + rand(200.0).float32
      )

proc spawnNovaExplosionPooled*(pool: ParticlePool, x, y: float32, radius: float32,
                               primaryColor, secondaryColor: Color) =
  ## Spawn a multi-layered nova explosion with core flash, shell, and shock ring
  let coreParticles = scaledParticleBurstCount(pool, 4)
  for _ in 0..<coreParticles:
    let angle = rand(1.0) * PI * 2.0
    let dist = rand(radius * 0.24'f32)
    let px = x + cos(angle) * dist
    let py = y + sin(angle) * dist
    discard pool.acquireParticleDetailed(
      px, py,
      cos(angle) * (65.0'f32 + rand(65.0).float32),
      sin(angle) * (65.0'f32 + rand(65.0).float32),
      secondaryColor,
      lifetime = 0.16'f32 + rand(0.08).float32,
      startSize = 5.0'f32 + rand(3.0).float32,
      endSize = 0.4'f32,
      drag = 5.0'f32,
      glow = 1.7'f32,
      style = psSoft
    )

  let middleParticles = scaledParticleBurstCount(pool, max(8, (radius * 0.16'f32).int))
  for i in 0..<middleParticles:
    let angle = i.float32 / middleParticles.float32 * PI * 2.0
    let shellRadius = radius * (0.45'f32 + rand(0.18).float32)
    let px = x + cos(angle) * shellRadius
    let py = y + sin(angle) * shellRadius
    let speed = 120.0'f32 + rand(85.0).float32
    let shellColor = if i mod 4 == 0: secondaryColor else: primaryColor
    discard pool.acquireParticleDetailed(
      px, py, cos(angle) * speed, sin(angle) * speed, shellColor,
      lifetime = 0.22'f32 + rand(0.18).float32,
      startSize = 2.4'f32 + rand(1.8).float32,
      endSize = 0.2'f32,
      drag = 3.5'f32 + rand(2.0).float32,
      glow = 1.15'f32,
      style = if i mod 3 == 0: psShard else: psSpark,
      rotation = angle * 180.0'f32 / PI.float32,
      spin = (-220.0 + rand(440.0)).float32
    )

  let outerParticles = scaledParticleBurstCount(pool, max(10, (radius * 0.20'f32).int))
  for i in 0..<outerParticles:
    let angle = i.float32 / outerParticles.float32 * PI * 2.0
    let px = x + cos(angle) * radius
    let py = y + sin(angle) * radius
    discard pool.acquireParticleDetailed(
      px, py,
      cos(angle) * (85.0'f32 + rand(45.0).float32),
      sin(angle) * (85.0'f32 + rand(45.0).float32),
      if i mod 5 == 0: secondaryColor else: primaryColor,
      lifetime = 0.18'f32 + rand(0.12).float32,
      startSize = 1.8'f32 + rand(1.2).float32,
      endSize = 0.1'f32,
      drag = 4.5'f32,
      glow = 1.0'f32,
      style = psSpark,
      rotation = angle * 180.0'f32 / PI.float32
    )

proc clearPool*(pool: ParticlePool) =
  pool.activeCount = 0
  pool.spawnedThisFrame = 0

proc spawnEnemyDeathBurst*(pool: ParticlePool, x, y: float32,
                           enemyColor: Color, enemyRadius: float32,
                           isBoss: bool = false) =
  ## Rich multi-layer death burst: colored shrapnel + white sparks + shockwave ring.
  let baseCount = scaledParticleBurstCount(pool, if isBoss: 20 else: 10)
  let sparkCount = scaledParticleBurstCount(pool, if isBoss: 10 else: 4)
  let ringParticles = scaledParticleBurstCount(pool, if isBoss: 12 else: 6)
  let baseSpeed = if isBoss: 240.0'f32 else: 165.0'f32
  let brightEnemy = brighten(enemyColor, 70.0)

  for _ in 0..<baseCount:
    let angle = rand(1.0) * PI * 2.0
    let spawnRadius = rand(enemyRadius * 0.55'f32)
    let speed = baseSpeed + rand(baseSpeed * 0.65'f32).float32
    discard pool.acquireParticleDetailed(
      x + cos(angle) * spawnRadius,
      y + sin(angle) * spawnRadius,
      cos(angle) * speed,
      sin(angle) * speed,
      enemyColor,
      lifetime = 0.28'f32 + rand(0.26).float32,
      startSize = 2.8'f32 + rand(3.0).float32,
      endSize = 0.25'f32,
      drag = 3.2'f32 + rand(2.5).float32,
      gravity = 20.0'f32 + rand(50.0).float32,
      glow = 1.0'f32,
      style = if rand(1.0) < 0.4: psShard else: psEmber,
      rotation = rand(360.0).float32,
      spin = (-320.0 + rand(640.0)).float32
    )

  for _ in 0..<sparkCount:
    let angle = rand(1.0) * PI * 2.0
    let speed = baseSpeed * 1.45'f32 + rand(95.0).float32
    discard pool.acquireParticleDetailed(
      x, y, cos(angle) * speed, sin(angle) * speed, Color(r: 255, g: 255, b: 255, a: 255),
      lifetime = 0.12'f32 + rand(0.12).float32,
      startSize = 1.8'f32 + rand(1.3).float32,
      endSize = 0.1'f32,
      drag = 3.0'f32,
      glow = 1.3'f32,
      style = psSpark,
      rotation = angle * 180.0'f32 / PI.float32
    )

  let ringRadius = enemyRadius * 1.2'f32
  for i in 0..<ringParticles:
    let angle = i.float32 * PI * 2.0 / ringParticles.float32
    let speed = baseSpeed * 0.42'f32
    discard pool.acquireParticleDetailed(
      x + cos(angle) * ringRadius,
      y + sin(angle) * ringRadius,
      cos(angle) * speed,
      sin(angle) * speed,
      brightEnemy,
      lifetime = 0.18'f32 + rand(0.12).float32,
      startSize = 2.1'f32 + rand(1.5).float32,
      endSize = 0.2'f32,
      drag = 4.0'f32,
      glow = 1.1'f32,
      style = if i mod 3 == 0: psSpark else: psSoft,
      rotation = angle * 180.0'f32 / PI.float32
    )

  let coreFlashCount = if isBoss: 5 else: 2
  for _ in 0..<coreFlashCount:
    let angle = rand(1.0) * PI * 2.0
    discard pool.acquireParticleDetailed(
      x, y,
      cos(angle) * (30.0'f32 + rand(30.0).float32),
      sin(angle) * (30.0'f32 + rand(30.0).float32),
      brightEnemy,
      lifetime = 0.10'f32 + rand(0.06).float32,
      startSize = enemyRadius * (if isBoss: 0.7'f32 else: 0.45'f32) + rand(3.0).float32,
      endSize = 0.6'f32,
      drag = 6.0'f32,
      glow = 1.8'f32,
      style = psSoft
    )

proc getPoolStats*(pool: ParticlePool): tuple[active: int, capacity: int, usage: float] =
  result.active = pool.activeCount
  result.capacity = pool.maxCapacity
  result.usage = if pool.maxCapacity > 0: pool.activeCount.float / pool.maxCapacity.float else: 0.0
