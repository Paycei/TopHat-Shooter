import std/math
import raylib
import particle_types
import types, powerup, bullet, particle_pool

proc newWall*(x, y: float32, player: Player): Wall =
  # Calculate HP based on WallMaster powerup
  let baseHp = 10.0
  let wallMasterLevel = getPowerUpLevel(player, puWallMaster)
  let hpMultiplier = case wallMasterLevel
    of 1: 2.5
    else: 1.0

  let maxHp = baseHp * hpMultiplier

  # Facing normal: points from the player toward the placement spot, so the slab
  # turns its broad face to block that direction ("facing away from the player").
  let facing = arctan2(y - player.pos.y, x - player.pos.x)

  result = Wall(
    pos: newVector2f(x, y),
    radius: 25,
    hp: maxHp,
    maxHp: maxHp,
    duration: 30.0,
    shootTimer: 0.0,  # Initialize ready to shoot
    angle: facing,
    turretAngle: facing,
    # Plain walls get the oriented-slab shape; turret emplacements stay circular.
    slabShape: not hasPowerUp(player, puWallTurrets)
  )

proc updateWall*(wall: Wall, dt: float32): bool =
  if wall.permanent:
    # Dungeon obstacles ignore the duration timer, but enemies (and bosses) can
    # now smash them: a permanent wall lives only while it still has HP.
    return wall.hp > 0
  wall.duration -= dt
  return wall.hp > 0 and wall.duration > 0

proc drawBarricadeWall(wall: Wall) =
  ## Player-placed wall: an oriented stone/steel slab whose broad face turns to
  ## block the direction it was placed in (wall.angle = outward normal).
  let ang = wall.angle
  let ca = cos(ang)
  let sa = sin(ang)
  let rotDeg = radToDeg(ang)
  let r = wall.radius
  let halfLen = r                              # face half-length == collision radius
  let halfThick = r * WallSlabThicknessRatio   # slab depth along the normal (matches the hitbox)

  # Local -> world. +X is the outward normal, +Y runs along the face.
  template lw(lx, ly: float32): Vector2 =
    Vector2(x: wall.pos.x + lx * ca - ly * sa,
            y: wall.pos.y + lx * sa + ly * ca)
  # Centered rotated rect helper (origin at the slab center == wall.pos).
  template slab(halfW, halfH: float32, col: Color) =
    drawRectangle(Rectangle(x: wall.pos.x, y: wall.pos.y,
                            width: halfW * 2, height: halfH * 2),
                  Vector2(x: halfW, y: halfH), rotDeg, col)

  let hpPct = clamp(wall.hp / wall.maxHp, 0.0'f32, 1.0'f32)
  # Damage darkens the stone toward a scorched red.
  let dmg = 1.0'f32 - hpPct
  let baseCol = Color(r: uint8(70 + dmg * 40), g: uint8(74 - dmg * 34),
                      b: uint8(82 - dmg * 40), a: 255)

  # 1) Drop shadow, pushed slightly outward + down so the slab feels raised.
  drawRectangle(Rectangle(x: wall.pos.x + ca * 3.0'f32, y: wall.pos.y + sa * 3.0'f32 + 4.0'f32,
                          width: halfThick * 2 + 5, height: halfLen * 2 + 5),
                Vector2(x: halfThick + 2.5'f32, y: halfLen + 2.5'f32), rotDeg,
                Color(r: 0, g: 0, b: 0, a: 70))

  # 2) Body + beveled top plate.
  slab(halfThick, halfLen, baseCol)
  slab(halfThick * 0.78'f32, halfLen * 0.9'f32,
       Color(r: uint8(104 + dmg * 30), g: uint8(110 - dmg * 50), b: uint8(120 - dmg * 56), a: 255))

  # 3) Edge shading: bright bevel on the outward face, shadow on the player side.
  drawLine(lw(halfThick, -halfLen), lw(halfThick, halfLen), 2.5'f32,
           Color(r: 168, g: 176, b: 190, a: 255))     # outward (+X) catches light
  drawLine(lw(-halfThick, -halfLen), lw(-halfThick, halfLen), 2.5'f32,
           Color(r: 28, g: 30, b: 36, a: 255))          # inward (-X) in shadow

  # 4) Brick seams across the face split the slab into three blocks.
  for s in [-0.34'f32, 0.34'f32]:
    drawLine(lw(-halfThick, halfLen * s), lw(halfThick, halfLen * s), 1.5'f32,
             Color(r: 40, g: 42, b: 48, a: 200))

  # 5) Corner rivets.
  let bx = halfThick * 0.62'f32
  let by = halfLen * 0.82'f32
  for sx in [-1.0'f32, 1.0'f32]:
    for sy in [-1.0'f32, 1.0'f32]:
      let p = lw(bx * sx, by * sy)
      drawCircle(p, 2.2'f32, Color(r: 188, g: 194, b: 206, a: 255))
      drawCircle(Vector2(x: p.x - 0.6'f32, y: p.y - 0.6'f32), 0.9'f32,
                 Color(r: 235, g: 240, b: 250, a: 255))

  # 6) Cracks once chipped: a couple of jagged dark forks scaled by damage.
  if dmg > 0.15'f32:
    let cracks = 1 + int(dmg * 2.0'f32)
    for c in 0 ..< cracks:
      let cy = (c.float32 / max(1.0'f32, cracks.float32 - 1.0'f32) - 0.5'f32) * halfLen * 1.2'f32
      drawLine(lw(-halfThick * 0.7'f32, cy), lw(halfThick * 0.5'f32, cy + halfLen * 0.18'f32),
               1.4'f32, Color(r: 18, g: 18, b: 22, a: 230))
      drawLine(lw(halfThick * 0.5'f32, cy + halfLen * 0.18'f32),
               lw(halfThick * 0.9'f32, cy - halfLen * 0.05'f32),
               1.2'f32, Color(r: 18, g: 18, b: 22, a: 210))

proc drawTurretWall(wall: Wall) =
  ## Wall Turrets skin: a circular gun emplacement with a barrel that tracks the
  ## current target (wall.turretAngle) and a targeting eye that heats up to fire.
  let cx = wall.pos.x
  let cy = wall.pos.y
  let r = wall.radius
  let ang = wall.turretAngle
  let ca = cos(ang)
  let sa = sin(ang)

  # Shadow + dark hex base plate (rotated so it doesn't look like a plain disc).
  drawCircle(Vector2(x: cx, y: cy + 4.0'f32), r, Color(r: 0, g: 0, b: 0, a: 60))
  drawPoly(Vector2(x: cx, y: cy), 6, r, radToDeg(ang), Color(r: 66, g: 70, b: 80, a: 255))
  drawPolyLines(Vector2(x: cx, y: cy), 6, r, radToDeg(ang), 2.0'f32,
                Color(r: 150, g: 156, b: 168, a: 255))
  for i in 0 ..< 6:
    let a2 = ang + i.float32 * PI / 3.0'f32
    drawCircle(Vector2(x: cx + cos(a2) * r * 0.80'f32, y: cy + sin(a2) * r * 0.80'f32),
               1.8'f32, Color(r: 182, g: 188, b: 200, a: 255))

  # Barrel: a thick segment from the hub out to the muzzle along the aim.
  let barLen = r * 1.18'f32
  let muzzle = Vector2(x: cx + ca * barLen, y: cy + sa * barLen)
  drawLine(Vector2(x: cx, y: cy), muzzle, r * 0.36'f32, Color(r: 52, g: 55, b: 63, a: 255))
  drawLine(Vector2(x: cx, y: cy), muzzle, r * 0.18'f32, Color(r: 92, g: 98, b: 110, a: 255))
  drawCircle(muzzle, r * 0.18'f32, Color(r: 38, g: 40, b: 46, a: 255))

  # Rotating turret dome over the hub.
  drawCircle(Vector2(x: cx, y: cy), r * 0.58'f32, Color(r: 118, g: 124, b: 138, a: 255))
  drawCircle(Vector2(x: cx - r * 0.15'f32, y: cy - r * 0.15'f32), r * 0.28'f32,
             Color(r: 150, g: 156, b: 170, a: 220))   # specular highlight
  drawCircleLines(cx.int32, cy.int32, r * 0.58'f32, Color(r: 172, g: 178, b: 192, a: 255))

  # Targeting eye: heats from amber to white-hot as the next shot approaches.
  let heat = clamp(1.0'f32 - wall.shootTimer / 1.5'f32, 0.25'f32, 1.0'f32)
  let eye = Vector2(x: cx + ca * r * 0.24'f32, y: cy + sa * r * 0.24'f32)
  drawCircle(eye, r * 0.17'f32, Color(r: uint8(120 + heat * 135), g: uint8(35 + heat * 60), b: 35, a: 255))
  drawCircle(eye, r * 0.08'f32, Color(r: 255, g: uint8(160 + heat * 90), b: uint8(60 + heat * 120), a: 255))

proc drawWall*(wall: Wall, player: Player) =
  if wall.permanent:
    # Dungeon obstacle: solid block tinted with the floor theme accent
    let tint = wall.obstacleTint
    let body = Color(r: uint8(tint.r div 3), g: uint8(tint.g div 3),
                     b: uint8(tint.b div 3), a: 255)
    drawCircle(Vector2(x: wall.pos.x, y: wall.pos.y), wall.radius, body)
    drawCircleLines(wall.pos.x.int32, wall.pos.y.int32, wall.radius, tint)
    drawCircleLines(wall.pos.x.int32, wall.pos.y.int32, wall.radius * 0.55'f32,
                    Color(r: tint.r, g: tint.g, b: tint.b, a: 120))
    # Damage cue: once chipped, show a shrinking HP bar so the player can read
    # that these obstacles are destructible (and, in boss rooms, re-forming).
    if wall.hp < wall.maxHp:
      let barWidth = wall.radius * 2
      let hpPercent = wall.hp / wall.maxHp
      drawRectangle((wall.pos.x - wall.radius).int32, (wall.pos.y - wall.radius - 8).int32,
                    barWidth.int32, 3, Color(r: 60, g: 20, b: 20, a: 220))
      drawRectangle((wall.pos.x - wall.radius).int32, (wall.pos.y - wall.radius - 8).int32,
                    (barWidth * hpPercent).int32, 3, tint)
    return

  # Player-placed wall: turrets stay circular emplacements; plain walls are
  # oriented barricade slabs facing away from where the player placed them. Drawn
  # from the stored shape so the visual always matches the collision footprint.
  if wall.slabShape:
    drawBarricadeWall(wall)
  else:
    drawTurretWall(wall)

  # Draw HP bar (same for both skins), only once chipped to reduce clutter.
  let hpPercent = wall.hp / wall.maxHp
  if hpPercent < 0.999'f32:
    let barWidth = wall.radius * 2
    let barHeight = 4.0
    let barY = (wall.pos.y - wall.radius - 10).int32
    let barX = (wall.pos.x - wall.radius).int32
    drawRectangle(barX - 1, barY - 1, barWidth.int32 + 2, barHeight.int32 + 2,
                  Color(r: 0, g: 0, b: 0, a: 200))
    drawRectangle(barX, barY, barWidth.int32, barHeight.int32, Color(r: 90, g: 30, b: 30, a: 255))
    let fillCol = if hpPercent > 0.5: Color(r: 80, g: 210, b: 90, a: 255)
                  elif hpPercent > 0.25: Color(r: 230, g: 200, b: 60, a: 255)
                  else: Color(r: 230, g: 80, b: 60, a: 255)
    drawRectangle(barX, barY, (barWidth * hpPercent).int32, barHeight.int32, fillCol)

proc takeDamage*(wall: Wall, damage: float32) =
  wall.hp -= damage
  if wall.hp < 0: wall.hp = 0

proc checkEnemyWallCollision*(enemy: Enemy, wall: Wall): bool =
  wallOverlapsCircle(wall, enemy.pos, enemy.radius)

proc checkPlayerWallCollision*(playerPos: Vector2f, playerRadius: float32, wall: Wall): bool =
  wallOverlapsCircle(wall, playerPos, playerRadius)

proc isValidWallPlacement*(pos: Vector2f, playerPos: Vector2f, walls: seq[Wall], enemies: seq[Enemy], radius: float32): bool =
  # Check if too close to player
  if distance(pos, playerPos) < radius * 2:
    return false

  # Check overlap with other walls (slab-aware so you can pack slabs tighter)
  for wall in walls:
    if wallOverlapsCircle(wall, pos, radius):
      return false

  # Check overlap with enemies
  for enemy in enemies:
    if distance(pos, enemy.pos) < radius + enemy.radius:
      return false

  return true

proc processWallTurret*(wall: var Wall, enemies: seq[Enemy], bullets: var seq[Bullet],
                        player: Player, particlePool: ParticlePool, dt: float32,
                        screenWidth: int32, screenHeight: int32) =
  # Handles turret cooldown, target selection and bullet spawn for a single wall
  if not hasPowerUp(player, puWallTurrets):
    return

  let turretLevel = getPowerUpLevel(player, puWallTurrets)
  let turretCooldown = if turretLevel >= 2: 1.0 else: 1.5
  let turretRange = case turretLevel
    of 1: 350.0
    of 2: 425.0
    else: 500.0

  wall.shootTimer -= dt

  # Acquire the nearest in-range target every frame so the barrel can track it
  # smoothly, independent of the firing cooldown.
  var nearestEnemy: Enemy = nil
  var nearestDist = 999999.0
  for e in enemies:
    let dist = distance(wall.pos, e.pos)
    if dist < nearestDist and dist < turretRange:
      nearestDist = dist
      nearestEnemy = e

  if nearestEnemy != nil:
    # Rotate toward the target along the shortest arc.
    let desired = arctan2(nearestEnemy.pos.y - wall.pos.y, nearestEnemy.pos.x - wall.pos.x)
    var delta = desired - wall.turretAngle
    while delta > PI: delta -= 2.0'f32 * PI
    while delta < -PI: delta += 2.0'f32 * PI
    wall.turretAngle += delta * min(1.0'f32, dt * 10.0'f32)

  if wall.shootTimer <= 0:
    if nearestEnemy != nil:
      let direction = (nearestEnemy.pos - wall.pos).normalize()

      var turretDamage = 1.0
      if hasPowerUp(player, puWallMaster):
        let fortifyLevel = getPowerUpLevel(player, puWallMaster)
        turretDamage = case fortifyLevel
          of 1: 1.5
          of 2: 2.0
          else: 3.0

      let damageScaling = player.damage * 0.3
      turretDamage += damageScaling

      let shotCount = if turretLevel >= 3: 2 else: 1
      for _ in 0..<shotCount:
        bullets.add(newBullet(
          x = wall.pos.x,
          y = wall.pos.y,
          direction = direction,
          speed = 350.0,
          damage = turretDamage,
          fromPlayer = true,
          isHoming = false,
          isPiercing = false,
          isExplosive = false,
          hasBounce = false,
          canSplit = false,
          slowAmount = 0.0,
          poisonDuration = 0.0,
          fireDuration = 0.0,
          windPushForce = 0.0,
          bulletSkin = player.bulletSkinType,
          bulletShape = player.bulletShapeType,
          isFromWallTurret = true
        ))

      # Muzzle flash at the barrel tip so it lines up with the tracked aim.
      let muzzleX = wall.pos.x + cos(wall.turretAngle) * wall.radius * 1.18'f32
      let muzzleY = wall.pos.y + sin(wall.turretAngle) * wall.radius * 1.18'f32
      spawnExplosionPooled(particlePool, muzzleX, muzzleY, Color(r: 255, g: 200, b: 100, a: 255), 8)
      wall.shootTimer = turretCooldown

proc processPendingWallRespawns*(pending: var seq[PendingWallRespawn], walls: var seq[Wall],
                                enemies: seq[Enemy], player: Player, particlePool: ParticlePool,
                                dt: float32) =
  var i = 0
  while i < pending.len:
    pending[i].timer -= dt
    if pending[i].timer <= 0:
      let spot = pending[i]
      var blocked = distance(player.pos, spot.pos) < spot.radius + player.radius + 8
      if not blocked:
        for enemy in enemies:
          if enemy.isBoss and distance(enemy.pos, spot.pos) < spot.radius + enemy.radius:
            blocked = true
            break
      if blocked:
        pending[i].timer = 0.4'f32
        inc i
      else:
        walls.add(Wall(
          pos: spot.pos, radius: spot.radius,
          hp: spot.maxHp, maxHp: spot.maxHp,
          duration: 1.0, permanent: true, respawns: true,
          obstacleTint: spot.tint))
        spawnExplosionPooled(particlePool, spot.pos.x, spot.pos.y, spot.tint, 12)
        pending.delete(i)
    else:
      inc i
