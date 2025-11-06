import raylib, types, random, math

proc newParticle*(x, y: float32, color: Color, speed: float32 = 100.0): Particle =
  let angle = rand(1.0) * PI * 2.0
  result = Particle(
    pos: newVector2f(x, y),
    vel: newVector2f(cos(angle) * speed, sin(angle) * speed),
    color: color,
    lifetime: 0.5 + rand(0.5),
    maxLifetime: 0.5 + rand(0.5),
    size: 2 + rand(4).float32
  )

proc updateParticle*(particle: Particle, dt: float32): bool =
  particle.pos = particle.pos + particle.vel * dt
  particle.vel = particle.vel * 0.95  # Slow down
  particle.lifetime -= dt
  return particle.lifetime > 0

proc drawParticle*(particle: Particle) =
  let alpha = (particle.lifetime / particle.maxLifetime * 255).uint8
  var c = particle.color
  c.a = alpha
  drawCircle(Vector2(x: particle.pos.x, y: particle.pos.y), particle.size, c)

proc spawnExplosion*(particles: var seq[Particle], x, y: float32, color: Color, count: int = 20) =
  for i in 0..<count:
    particles.add(newParticle(x, y, color, 80 + rand(120).float32))

proc spawnShockwave*(particles: var seq[Particle], x, y: float32, radius: float32) =
  let particleCount = (radius * 0.5).int
  for i in 0..<particleCount:
    let angle = i.float32 / particleCount.float32 * PI * 2.0
    let px = x + cos(angle) * radius
    let py = y + sin(angle) * radius
    particles.add(newParticle(px, py, Color(r: 255, g: 200, b: 100, a: 255), 50))
