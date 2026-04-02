import raylib, particle_types, types, random, math, strutils, particle_pool, ui/ui_constants

export Particle, ParticlePool, newParticlePool, updateParticlePool, drawParticlePool
export spawnExplosionPooled, spawnTimedParticlesPooled, spawnTimedParticlesAroundPooled
export spawnShockwavePooled, spawnExplosiveRingPooled, spawnSpiralExplosionPooled, spawnNovaExplosionPooled
export spawnTrailParticlePooled, spawnEnemyDeathBurst
export clearPool, getPoolStats

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
    of dtFrost:
      color = Color(r: 150, g: 220, b: 255, a: alpha.uint8)
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
    of dtFrost:
      color = Color(r: 150, g: 220, b: 255, a: alpha.uint8)
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
    of dtFrost:
      color = Color(r: 150, g: 220, b: 255, a: alpha.uint8)
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
  
  # Multiply damage by BALANCE_MULTIPLIER for display
  let displayDamage = dmgNum.damage * BALANCE_MULTIPLIER
  
  let damageText =
    if displayDamage >= 10.0:
      $round(displayDamage).int
    elif displayDamage >= 1.0:
      formatFloat(displayDamage, ffDecimal, 1)
    else:
      formatFloat(displayDamage, ffDecimal, 2)
  
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
