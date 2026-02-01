import raylib, particle_types, random, math

## PARTICLE POOLING SYSTEM FOR PERFORMANCE
## Instead of constantly creating and destroying particles, we reuse them from a pool.
## This eliminates memory allocations during gameplay, improving performance.
## 
## Note: Particle and ParticlePool types are defined in particle_types.nim

const
  DEFAULT_POOL_SIZE* = 2000       # Initial pool capacity
  POOL_GROWTH_SIZE* = 500         # How much to grow when pool is full

proc newParticlePool*(initialCapacity: int = DEFAULT_POOL_SIZE): ParticlePool =
  ## Create a new particle pool with pre-allocated particles
  result = ParticlePool(
    particles: newSeq[Particle](initialCapacity),
    activeCount: 0,
    maxCapacity: initialCapacity
  )
  
  # Pre-allocate all particle objects
  for i in 0..<initialCapacity:
    result.particles[i] = Particle(
      pos: newVector2f(0, 0),
      vel: newVector2f(0, 0),
      color: Color(r: 0, g: 0, b: 0, a: 0),
      lifetime: 0.0,
      maxLifetime: 0.0,
      size: 0.0
    )

proc resetParticle(particle: Particle, x, y: float32, color: Color, speed: float32) =
  ## Reset a particle to new values (for reuse)
  let angle = rand(1.0) * PI * 2.0
  particle.pos.x = x
  particle.pos.y = y
  particle.vel.x = cos(angle) * speed
  particle.vel.y = sin(angle) * speed
  particle.color = color
  particle.lifetime = 0.6 + rand(0.6)
  particle.maxLifetime = particle.lifetime
  particle.size = 3 + rand(5).float32

proc acquireParticle*(pool: ParticlePool, x, y: float32, color: Color, speed: float32): bool =
  ## Get a particle from the pool and initialize it
  ## Returns true if successful, false if pool is full
  
  if pool.activeCount >= pool.maxCapacity:
    # Pool is full - try to find an expired particle to reuse
    for i in 0..<pool.activeCount:
      if pool.particles[i].lifetime <= 0:
        # Found an expired particle - reuse it
        resetParticle(pool.particles[i], x, y, color, speed)
        return true
    
    # No expired particles found - grow the pool if possible
    if pool.maxCapacity < DEFAULT_POOL_SIZE * 3:  # Allow growing up to 3x initial size
      let oldCapacity = pool.maxCapacity
      pool.maxCapacity = min(oldCapacity + POOL_GROWTH_SIZE, DEFAULT_POOL_SIZE * 3)
      
      # Allocate new particles
      for i in oldCapacity..<pool.maxCapacity:
        pool.particles.add(Particle(
          pos: newVector2f(0, 0),
          vel: newVector2f(0, 0),
          color: Color(r: 0, g: 0, b: 0, a: 0),
          lifetime: 0.0,
          maxLifetime: 0.0,
          size: 0.0
        ))
    else:
      # Pool at max capacity - replace oldest active particle
      var oldestIndex = 0
      var oldestLifetimeRatio = 1.0
      
      for i in 0..<pool.activeCount:
        let ratio = pool.particles[i].lifetime / pool.particles[i].maxLifetime
        if ratio < oldestLifetimeRatio:
          oldestLifetimeRatio = ratio
          oldestIndex = i
      
      resetParticle(pool.particles[oldestIndex], x, y, color, speed)
      return true
  
  # We have space - use the next available slot
  resetParticle(pool.particles[pool.activeCount], x, y, color, speed)
  pool.activeCount += 1
  return true

proc updateParticlePool*(pool: ParticlePool, dt: float32) =
  ## Update all active particles and compact the pool
  ## Moves expired particles to the end and reduces activeCount
  
  var writeIndex = 0
  var i = 0
  
  while i < pool.activeCount:
    let particle = pool.particles[i]
    
    # Update particle physics
    particle.pos.x += particle.vel.x * dt
    particle.pos.y += particle.vel.y * dt
    
    # Slowdown: pow(0.95, 60*dt)
    let slowdownFactor = pow(0.95, 60.0 * dt)
    particle.vel.x *= slowdownFactor
    particle.vel.y *= slowdownFactor
    
    particle.lifetime -= dt
    
    # Keep active particles at the front
    if particle.lifetime > 0:
      if writeIndex != i:
        # Swap particles to compact active ones at the front
        let temp = pool.particles[writeIndex]
        pool.particles[writeIndex] = pool.particles[i]
        pool.particles[i] = temp
      writeIndex += 1
    
    i += 1
  
  # Update active count to exclude expired particles
  pool.activeCount = writeIndex

proc drawParticlePool*(pool: ParticlePool) =
  ## Draw all active particles from the pool
  for i in 0..<pool.activeCount:
    let particle = pool.particles[i]
    let alpha = (particle.lifetime / particle.maxLifetime * 255).uint8
    var c = particle.color
    c.a = alpha
    drawCircle(Vector2(x: particle.pos.x, y: particle.pos.y), particle.size, c)

proc spawnExplosionPooled*(pool: ParticlePool, x, y: float32, color: Color, count: int = 20) =
  ## Spawn explosion particles using the pool
  for i in 0..<count:
    discard pool.acquireParticle(x, y, color, 80 + rand(120).float32)

proc spawnTimedParticlesPooled*(pool: ParticlePool, x, y: float32, rate: float32,
                                color: Color, count: int, dt: float32) =
  ## Particle spawning using pool
  if rand(1.0) < (rate * dt):
    spawnExplosionPooled(pool, x, y, color, count)

proc spawnTimedParticlesAroundPooled*(pool: ParticlePool, centerX, centerY: float32,
                                      maxRadius: float32, rate: float32, color: Color,
                                      count: int, dt: float32, offsetY: float32 = 0.0) =
  ## Particle spawning with random positioning using pool
  if rand(1.0) < (rate * dt):
    let particleAngle = rand(1.0) * PI * 2.0
    let particleDist = rand(maxRadius)
    let particleX = centerX + cos(particleAngle) * particleDist
    let particleY = centerY + sin(particleAngle) * particleDist + offsetY
    spawnExplosionPooled(pool, particleX, particleY, color, count)

proc spawnShockwavePooled*(pool: ParticlePool, x, y: float32, radius: float32) =
  ## Spawn shockwave particles using pool
  let particleCount = (radius * 0.5).int
  for i in 0..<particleCount:
    let angle = i.float32 / particleCount.float32 * PI * 2.0
    let px = x + cos(angle) * radius
    let py = y + sin(angle) * radius
    discard pool.acquireParticle(px, py, Color(r: 255, g: 200, b: 100, a: 255), 50)

proc spawnExplosiveRingPooled*(pool: ParticlePool, x, y: float32, radius: float32, 
                               ringCount: int, color: Color) =
  ## Spawn concentric rings of particles for explosive bullets (like satellite trails)
  ## Creates multiple expanding rings similar to how satellites show orbit trails
  for ring in 1..ringCount:
    let ringRadius = radius * (ring.float32 / ringCount.float32)
    let particlesInRing = max(8, (ringRadius * 0.4).int)  # More particles in larger rings
    
    for i in 0..<particlesInRing:
      let angle = i.float32 / particlesInRing.float32 * PI * 2.0
      let px = x + cos(angle) * ringRadius
      let py = y + sin(angle) * ringRadius
      
      # Vary particle size based on ring (outer rings have smaller particles)
      let speedVariation = 30.0 + rand(40).float32
      discard pool.acquireParticle(px, py, color, speedVariation)

proc spawnSpiralExplosionPooled*(pool: ParticlePool, x, y: float32, radius: float32,
                                  armCount: int, color: Color) =
  ## Spawn particles in a spiral pattern radiating outward
  ## Creates a rotating vortex effect similar to the gravity well visualization
  let particlesPerArm = max(5, (radius * 0.15).int)
  
  for arm in 0..<armCount:
    let baseAngle = (arm.float32 / armCount.float32) * PI * 2.0
    
    for i in 0..<particlesPerArm:
      let progress = i.float32 / particlesPerArm.float32
      let spiralAngle = baseAngle + progress * PI * 0.5  # Add spiral twist
      let spiralRadius = radius * progress
      
      let px = x + cos(spiralAngle) * spiralRadius
      let py = y + sin(spiralAngle) * spiralRadius
      
      # Speed increases with distance from center
      let speed = 60.0 + progress * 80.0 + rand(30).float32
      discard pool.acquireParticle(px, py, color, speed)

proc spawnNovaExplosionPooled*(pool: ParticlePool, x, y: float32, radius: float32,
                                primaryColor, secondaryColor: Color) =
  ## Spawn a multi-layered nova explosion with inner and outer waves
  ## Combines multiple particle patterns for a spectacular effect
  
  # Inner bright core - reduced from 15 to 8
  for i in 0..<8:
    let angle = rand(1.0) * PI * 2.0
    let dist = rand(radius * 0.3)
    let px = x + cos(angle) * dist
    let py = y + sin(angle) * dist
    discard pool.acquireParticle(px, py, secondaryColor, 100 + rand(100).float32)
  
  # Middle expanding wave - reduced multiplier from 0.6 to 0.4
  let middleParticles = (radius * 0.4).int
  for i in 0..<middleParticles:
    let angle = i.float32 / middleParticles.float32 * PI * 2.0
    let px = x + cos(angle) * radius * 0.6
    let py = y + sin(angle) * radius * 0.6
    discard pool.acquireParticle(px, py, primaryColor, 120 + rand(80).float32)
  
  # Outer shockwave ring - reduced multiplier from 0.8 to 0.5
  let outerParticles = (radius * 0.5).int
  for i in 0..<outerParticles:
    let angle = i.float32 / outerParticles.float32 * PI * 2.0
    let px = x + cos(angle) * radius
    let py = y + sin(angle) * radius
    # Mix primary and secondary colors for variety
    let color = if i mod 3 == 0: secondaryColor else: primaryColor
    discard pool.acquireParticle(px, py, color, 80 + rand(60).float32)

proc clearPool*(pool: ParticlePool) =
  ## Clear all active particles from the pool
  pool.activeCount = 0

proc getPoolStats*(pool: ParticlePool): tuple[active: int, capacity: int, usage: float] =
  ## Get statistics about pool usage
  result.active = pool.activeCount
  result.capacity = pool.maxCapacity
  result.usage = if pool.maxCapacity > 0: pool.activeCount.float / pool.maxCapacity.float else: 0.0
