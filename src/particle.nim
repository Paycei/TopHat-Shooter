import raylib, particle_types, types, random, math, strutils, particle_pool

# Export the particle pool type and functions
export Particle, ParticlePool, newParticlePool, updateParticlePool, drawParticlePool
export spawnExplosionPooled, spawnTimedParticlesPooled, spawnTimedParticlesAroundPooled
export spawnShockwavePooled, clearPool, getPoolStats

# PARTICLE SYSTEM WITH BACKWARDS-COMPATIBLE WRAPPER
# This file maintains the old API but can optionally use pooling for better performance

# LEGACY FUNCTIONS - These work with seq[Particle] for backwards compatibility
# Use these if you haven't migrated to pooling yet

proc newParticle*(x, y: float32, color: Color, speed: float32 = 100.0): Particle =
  let angle = rand(1.0) * PI * 2.0
  result = Particle(
    pos: newVector2f(x, y),
    vel: newVector2f(cos(angle) * speed, sin(angle) * speed),
    color: color,
    lifetime: 0.6 + rand(0.6),
    maxLifetime: 0.6 + rand(0.6),
    size: 3 + rand(5).float32
  )

proc updateParticle*(particle: Particle, dt: float32): bool =
  particle.pos = particle.pos + particle.vel * dt
  # Frame-independent slowdown: pow(0.95, 60*dt) simulates 60 FPS behavior at any framerate
  particle.vel = particle.vel * pow(0.95, 60.0 * dt)
  particle.lifetime -= dt
  return particle.lifetime > 0

proc drawParticle*(particle: Particle) =
  let alpha = (particle.lifetime / particle.maxLifetime * 255).uint8
  var c = particle.color
  c.a = alpha
  drawCircle(Vector2(x: particle.pos.x, y: particle.pos.y), particle.size, c)

# LEGACY PARTICLE LIMIT
const MAX_PARTICLES = 2000  # Hard cap to prevent memory growth

proc spawnExplosion*(particles: var seq[Particle], x, y: float32, color: Color, count: int = 20) =
  ## LEGACY VERSION - Still uses seq[Particle]
  ## For better performance, migrate to ParticlePool version
  
  # Check particle limit and remove oldest particles if needed
  if particles.len >= MAX_PARTICLES:
    let toRemove = min(100, particles.len div 10)
    particles = particles[toRemove..^1]
  
  let spaceAvailable = MAX_PARTICLES - particles.len
  let particlesToAdd = min(count, spaceAvailable)
  
  for i in 0..<particlesToAdd:
    particles.add(newParticle(x, y, color, 80 + rand(120).float32))

proc spawnTimedParticles*(particles: var seq[Particle], x, y: float32, rate: float32,
                          color: Color, count: int, dt: float32) =
  ## LEGACY VERSION - Frame-independent particle spawning
  if rand(1.0) < (rate * dt):
    spawnExplosion(particles, x, y, color, count)

proc spawnTimedParticlesAround*(particles: var seq[Particle], centerX, centerY: float32,
                                maxRadius: float32, rate: float32, color: Color,
                                count: int, dt: float32, offsetY: float32 = 0.0) =
  ## LEGACY VERSION - Frame-independent particle spawning with random positioning
  if rand(1.0) < (rate * dt):
    let particleAngle = rand(1.0) * PI * 2.0
    let particleDist = rand(maxRadius)
    let particleX = centerX + cos(particleAngle) * particleDist
    let particleY = centerY + sin(particleAngle) * particleDist + offsetY
    spawnExplosion(particles, particleX, particleY, color, count)

proc spawnShockwave*(particles: var seq[Particle], x, y: float32, radius: float32) =
  ## LEGACY VERSION - Spawn shockwave particles
  let particleCount = (radius * 0.5).int
  for i in 0..<particleCount:
    let angle = i.float32 / particleCount.float32 * PI * 2.0
    let px = x + cos(angle) * radius
    let py = y + sin(angle) * radius
    particles.add(newParticle(px, py, Color(r: 255, g: 200, b: 100, a: 255), 50))

# DAMAGE NUMBERS SYSTEM (unchanged)
proc newDamageNumber*(x, y: float32, damage: float32, fromPlayer: bool, isCritical: bool = false, damageType: DamageType = dtDefault): DamageNumber =
  let baseVelocityY = -80.0
  let horizontalSpread = (rand(1.0) - 0.5) * 100.0
  
  result = DamageNumber(
    pos: newVector2f(x, y),
    vel: newVector2f(horizontalSpread, baseVelocityY),
    damage: damage,
    lifetime: 0,
    maxLifetime: 1.5,
    fromPlayer: fromPlayer,
    isCritical: isCritical,
    damageType: damageType
  )

proc updateDamageNumber*(dmgNum: DamageNumber, dt: float32): bool =
  dmgNum.vel.y += 200.0 * dt
  dmgNum.pos = dmgNum.pos + dmgNum.vel * dt
  dmgNum.vel.x = dmgNum.vel.x * pow(0.95, 60.0 * dt)
  dmgNum.lifetime += dt
  return dmgNum.lifetime < dmgNum.maxLifetime

proc drawDamageNumber*(dmgNum: DamageNumber) =
  let progress = dmgNum.lifetime / dmgNum.maxLifetime
  let alpha = (1.0 - progress) * 255.0
  
  var color: Color
  var fontSize: int32
  
  if dmgNum.isCritical:
    case dmgNum.damageType
    of dtFire:
      color = Color(r: 255, g: 80, b: 0, a: alpha.uint8)
    of dtPoison:
      color = Color(r: 50, g: 255, b: 50, a: alpha.uint8)
    of dtLaser:
      color = Color(r: 150, g: 150, b: 255, a: alpha.uint8)
    of dtLightning:
      color = Color(r: 255, g: 255, b: 80, a: alpha.uint8)
    of dtArcane:
      color = Color(r: 180, g: 50, b: 200, a: alpha.uint8)
    of dtExplosion:
      color = Color(r: 255, g: 165, b: 0, a: alpha.uint8)
    of dtHeal:
      color = Color(r: 50, g: 255, b: 50, a: alpha.uint8)
    else:
      color = Color(r: 255, g: 255, b: 50, a: alpha.uint8)
    fontSize = 24
  elif dmgNum.fromPlayer:
    case dmgNum.damageType
    of dtFire:
      color = Color(r: 255, g: 80, b: 0, a: alpha.uint8)
    of dtPoison:
      color = Color(r: 50, g: 255, b: 50, a: alpha.uint8)
    of dtLaser:
      color = Color(r: 150, g: 150, b: 255, a: alpha.uint8)
    of dtLightning:
      color = Color(r: 255, g: 255, b: 80, a: alpha.uint8)
    of dtArcane:
      color = Color(r: 180, g: 50, b: 200, a: alpha.uint8)
    of dtExplosion:
      color = Color(r: 255, g: 165, b: 0, a: alpha.uint8)
    of dtCritical:
      color = Color(r: 255, g: 255, b: 50, a: alpha.uint8)
    of dtHeal:
      color = Color(r: 50, g: 255, b: 50, a: alpha.uint8)
      if dmgNum.damage < 1.0:
        fontSize = int32(clamp(12.0 + dmgNum.damage * 4.0, 12.0, 16.0))
      else:
        fontSize = int32(clamp(16.0 + (dmgNum.damage / 5.0) * 4.0, 16.0, 24.0))
    of dtDefault:
      color = Color(r: 255, g: 255, b: 255, a: alpha.uint8)
    
    if dmgNum.damageType != dtHeal:
      fontSize = 18
  else:
    case dmgNum.damageType
    of dtFire:
      color = Color(r: 255, g: 80, b: 0, a: alpha.uint8)
    of dtPoison:
      color = Color(r: 50, g: 255, b: 50, a: alpha.uint8)
    of dtLaser:
      color = Color(r: 200, g: 50, b: 255, a: alpha.uint8)
    of dtLightning:
      color = Color(r: 255, g: 255, b: 80, a: alpha.uint8)
    of dtArcane:
      color = Color(r: 180, g: 50, b: 200, a: alpha.uint8)
    of dtExplosion:
      color = Color(r: 255, g: 165, b: 0, a: alpha.uint8)
    of dtCritical:
      color = Color(r: 255, g: 255, b: 50, a: alpha.uint8)
    of dtHeal:
      color = Color(r: 50, g: 255, b: 50, a: alpha.uint8)
    of dtDefault:
      color = Color(r: 255, g: 150, b: 0, a: alpha.uint8)
    
    fontSize = 20
  
  let damageText =
    if dmgNum.damage >= 10.0:
      $dmgNum.damage.int
    elif dmgNum.damage >= 1.0:
      formatFloat(dmgNum.damage, ffDecimal, 1)
    else:
      formatFloat(dmgNum.damage, ffDecimal, 2)
  
  let displayText = if dmgNum.isCritical: damageText & "!" else: damageText
  let textWidth = measureText($displayText, fontSize)
  let x = (dmgNum.pos.x - textWidth.float32 / 2.0).int32
  let y = dmgNum.pos.y.int32
  
  # Outline (black)
  for dx in [-1, 0, 1]:
    for dy in [-1, 0, 1]:
      if dx != 0 or dy != 0:
        drawText($displayText, int32(x + dx), int32(y + dy), fontSize,
                Color(r: 0, g: 0, b: 0, a: uint8(alpha * 0.8)))
  
  # Main text
  drawText($displayText, x, y, fontSize, color)
