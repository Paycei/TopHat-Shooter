## 3D Boss Module
## Handles 3D boss definitions, behaviors, and attacks

import raylib, math, random
import types_3d, engine_3d, player_3d

# ===== BOSS INITIALIZATION =====

proc getBoss3D*(bossId: int): Boss3D =
  case bossId
  of 7:  # The Orbital Commander - 3D Version
    result = Boss3D(
      pos: vec3(0, 100, 0),
      health: 1000.0,
      maxHealth: 1000.0,
      phase: 1,
      attackTimer: 3.0,
      moveTimer: 0.0,
      satellites: @[]
    )
    
    # Initialize satellites in orbit
    for i in 0..<4:
      let angle = i.float32 * 2.0 * PI / 4.0
      result.satellites.add(BossSatellite(
        pos: vec3(0, 100, 0),
        angle: angle,
        distance: 50.0,
        health: 150.0,
        active: true
      ))
  
  else:
    # Default boss
    result = Boss3D(
      pos: vec3(0, 100, 0),
      health: 500.0,
      maxHealth: 500.0,
      phase: 1,
      attackTimer: 2.0,
      moveTimer: 0.0,
      satellites: @[]
    )

# ===== BOSS AI & MOVEMENT =====

proc updateBoss*(boss: var Boss3D, player: Player3D, projectiles: var seq[Projectile3D], dt: float32) =
  # Update phase
  let healthPercent = boss.health / boss.maxHealth
  if healthPercent < 0.5 and boss.phase == 1:
    boss.phase = 2
    # Add more satellites in phase 2
    for i in 0..<4:
      let angle = i.float32 * 2.0 * PI / 4.0 + PI / 4.0
      boss.satellites.add(BossSatellite(
        pos: vec3(0, 100, 0),
        angle: angle,
        distance: 75.0,
        health: 100.0,
        active: true
      ))
  
  # Update satellite orbits
  for sat in boss.satellites.mitems:
    if sat.active:
      sat.angle += dt * 0.8  # Orbit speed
      sat.pos.x = boss.pos.x + cos(sat.angle) * sat.distance
      sat.pos.z = boss.pos.z + sin(sat.angle) * sat.distance
      sat.pos.y = boss.pos.y
  
  # Boss movement (orbital pattern)
  boss.moveTimer += dt
  let moveAngle = boss.moveTimer * 0.2
  let moveRadius = 150.0
  boss.pos.x = cos(moveAngle) * moveRadius
  boss.pos.z = sin(moveAngle) * moveRadius
  boss.pos.y = 100.0 + sin(boss.moveTimer * 0.5) * 10.0
  
  # Attack logic
  boss.attackTimer -= dt
  
  if boss.attackTimer <= 0:
    # Phase 1: Satellite attacks
    if boss.phase == 1:
      # Shoot from random active satellite
      var activeSats: seq[int] = @[]
      for i, sat in boss.satellites:
        if sat.active:
          activeSats.add(i)
      
      if activeSats.len > 0:
        let satIdx = activeSats[rand(activeSats.len - 1)]
        let sat = boss.satellites[satIdx]
        let dir = (player.pos - sat.pos).normalize()
        
        projectiles.add(Projectile3D(
          pos: sat.pos,
          vel: dir * 250.0,
          damage: 5.0,  # Reduced from 20.0 for better balance
          lifetime: 5.0,
          fromPlayer: false,
          active: true
        ))
        boss.attackTimer = 2.0
    
    # Phase 2: Core attacks + satellite barrage
    else:
      # Core spiral attack
      for i in 0..<8:
        let angle = i.float32 * 2.0 * PI / 8.0 + boss.moveTimer
        let dir = vec3(cos(angle), 0, sin(angle)).normalize()
        
        projectiles.add(Projectile3D(
          pos: boss.pos,
          vel: dir * 200.0,
          damage: 4.0,  # Reduced from 15.0 for better balance
          lifetime: 5.0,
          fromPlayer: false,
          active: true
        ))
      
      # Satellite barrage
      for sat in boss.satellites:
        if sat.active:
          let dir = (player.pos - sat.pos).normalize()
          projectiles.add(Projectile3D(
            pos: sat.pos,
            vel: dir * 300.0,
            damage: 5.0,  # Reduced from 20.0 for better balance
            lifetime: 5.0,
            fromPlayer: false,
            active: true
          ))
        boss.attackTimer = 4.0

# ===== RENDERING =====

proc drawBoss*(boss: Boss3D) =
  # Draw core
  let coreColor = if boss.phase == 1: Gray else: Red
  drawSphere(Vector3(x: boss.pos.x, y: boss.pos.y, z: boss.pos.z), 20.0, coreColor)
  
  # Draw core glow
  drawSphere(Vector3(x: boss.pos.x, y: boss.pos.y, z: boss.pos.z), 22.0, fade(coreColor, 0.3))
  
  # Draw satellites
  for sat in boss.satellites:
    if sat.active:
      drawSphere(Vector3(x: sat.pos.x, y: sat.pos.y, z: sat.pos.z), 5.0, Purple)
      
      # Orbit trail
      drawLine3D(Vector3(x: boss.pos.x, y: boss.pos.y, z: boss.pos.z),
                Vector3(x: sat.pos.x, y: sat.pos.y, z: sat.pos.z),
                fade(Purple, 0.3))
      
      # Satellite glow
      drawSphere(Vector3(x: sat.pos.x, y: sat.pos.y, z: sat.pos.z), 6.0, fade(Purple, 0.2))

proc takeBossDamage*(boss: var Boss3D, projectile: Projectile3D): bool =
  # Check satellite hits
  for sat in boss.satellites.mitems:
    if sat.active and distance(sat.pos, projectile.pos) < 6.0:
      sat.health -= projectile.damage
      if sat.health <= 0:
        sat.active = false
        # Destroying a satellite damages the boss core
        boss.health -= 125.0  # Each satellite represents 125 HP (1000 / 8 satellites)
      return true
  
  # Check core hit (only in phase 2)
  if boss.phase >= 2 and distance(boss.pos, projectile.pos) < 22.0:
    boss.health -= projectile.damage
    return true
  
  false
