import raylib, types, random, math, strutils

proc newParticle*(x, y: float32, color: Color, speed: float32 = 100.0): Particle =
  let angle = rand(1.0) * PI * 2.0
  result = Particle(
    pos: newVector2f(x, y),
    vel: newVector2f(cos(angle) * speed, sin(angle) * speed),
    color: color,
    lifetime: 0.6 + rand(0.6),  # Longer lifetime for visibility
    maxLifetime: 0.6 + rand(0.6),
    size: 3 + rand(5).float32  # Larger particles
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

# ============================================================================
# DAMAGE NUMBERS SYSTEM
# ============================================================================

proc newDamageNumber*(x, y: float32, damage: float32, fromPlayer: bool, isCritical: bool = false): DamageNumber =
  ## Create a new floating damage number
  ## fromPlayer: true if player dealt damage to enemy, false if enemy dealt damage to player
  ## isCritical: true for critical hits (larger size, different color)
  let baseVelocityY = -80.0  # Move upward faster
  let horizontalSpread = (rand(1.0) - 0.5) * 100.0  # More horizontal movement for bounce effect
  
  result = DamageNumber(
    pos: newVector2f(x, y),
    vel: newVector2f(horizontalSpread, baseVelocityY),
    damage: damage,
    lifetime: 0,
    maxLifetime: 1.5,  # Visible for 1.5 seconds for full bounce animation
    fromPlayer: fromPlayer,
    isCritical: isCritical
  )

proc updateDamageNumber*(dmgNum: DamageNumber, dt: float32): bool =
  ## Update damage number position and lifetime
  ## Returns true if should continue existing, false if expired
  
  # Apply gravity for bouncing effect (frame-independent)
  dmgNum.vel.y += 200.0 * dt  # Gravity acceleration
  
  dmgNum.pos = dmgNum.pos + dmgNum.vel * dt
  
  # Horizontal slowdown (air resistance)
  dmgNum.vel.x = dmgNum.vel.x * pow(0.95, 60.0 * dt)
  
  dmgNum.lifetime += dt
  return dmgNum.lifetime < dmgNum.maxLifetime

proc drawDamageNumber*(dmgNum: DamageNumber) =
  ## Draw the damage number with fade-out effect
  let progress = dmgNum.lifetime / dmgNum.maxLifetime
  let alpha = (1.0 - progress) * 255.0  # Fade out over time
  
  # Determine color and size based on type
  var color: Color
  var fontSize: int32
  
  if dmgNum.isCritical:
    # Critical hits: larger, yellow text
    color = Color(r: 255, g: 255, b: 50, a: alpha.uint8)
    fontSize = 24
  elif dmgNum.fromPlayer:
    # Player damage to enemy: white/red
    color = Color(r: 255, g: 100, b: 100, a: alpha.uint8)
    fontSize = 18
  else:
    # Enemy damage to player: orange/red (more alarming)
    color = Color(r: 255, g: 150, b: 0, a: alpha.uint8)
    fontSize = 20
  
  # Format damage text
  let damageText = 
    if dmgNum.damage >= 10.0:
      $dmgNum.damage.int  # Show as integer for large values
    else:
      formatFloat(dmgNum.damage, ffDecimal, 1)  # Show 1 decimal for small values
  
  # Draw text with slight outline for better visibility
  let textWidth = measureText($damageText, fontSize)
  let x = (dmgNum.pos.x - textWidth.float32 / 2.0).int32
  let y = dmgNum.pos.y.int32
  
  # Outline (black)
  for dx in [-1, 0, 1]:
    for dy in [-1, 0, 1]:
      if dx != 0 or dy != 0:
        drawText($damageText, int32(x + dx), int32(y + dy), fontSize,
                Color(r: 0, g: 0, b: 0, a: uint8(alpha * 0.8)))
  
  # Main text
  drawText($damageText, x, y, fontSize, color)
