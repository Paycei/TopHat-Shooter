## 3D Game Module
## The 3D world: main loop, generic content (entities, pickups, projectiles),
## damage rules, mod hooks, rendering. The vanilla Orbital Commander fight is
## one configuration of it (bossEnabled); mod game modes run without the boss.
##
## One frame, in order: input -> player -> weapon -> platforms -> boss (if
## enabled) -> entity AI -> projectiles (hits vs boss, satellites, entities and
## the player; homing; gravity) -> pickups -> damage numbers -> end checks.
## All damage to the player goes through damagePlayer3D, to entities through
## damageEntity3D, to the boss through takeBossDamage / damageBoss3D.

import std/tables
import raylib, math, random
import ../draw_prims
import types_3d, engine_3d, player_3d, boss_3d, ../types, ../localization, ../settings
import ../modding/[mod_hooks, mod_assets]

export types_3d

const
  QuitKey = KeyboardKey.Q  ## pause overlay: quit to the desktop

# CONSTRUCTION

proc allocId3D*(world: Game3D): int =
  ## Ids are never reused within a world; 0 means "none".
  result = world.nextId
  inc world.nextId

proc newEntity3D*(world: Game3D, tag = ""): Entity3D =
  ## A live entity with sane defaults, its id assigned. It joins the world when
  ## addEntity3D (or a queued wkSpawnEntity) adds it.
  Entity3D(
    id: allocId3D(world), tag: tag,
    hp: 30.0, maxHp: 30.0, radius: 4.0,
    color: Color(r: 230, g: 60, b: 60, a: 255),
    shape: esSphere, size: vec3(8, 8, 8),
    modelId: -1, modelScale: 0.0, modelSpeed: 1.0,   # scale 0 = fit the model to the entity's diameter
    modelFade: 0.2,
    ai: aiNone, speed: 30.0, orbitRadius: 60.0,
    projectileSpeed: 150.0, projectileDamage: 10.0,
    alive: true)

proc newPickup3D*(world: Game3D, pos: Vector3f, kind: string, value: float32): Pickup3D =
  Pickup3D(id: allocId3D(world), pos: pos, kind: kind, value: value, radius: 4.0, alive: true)

proc newProjectile3D*(pos, vel: Vector3f, damage: float32, fromPlayer: bool): Projectile3D =
  Projectile3D(pos: pos, vel: vel, damage: damage, lifetime: 6.0, fromPlayer: fromPlayer, active: true)

proc initGame3D*(opts: World3DOptions, player2D: Player): Game3D =
  ## The Orbital Commander arena (opts.bossEnabled) or an empty one for a mod
  ## world: the script builds it in world3dStart.
  let arena = if opts.bossEnabled: generateArena("space", 500.0) else: generateArena("empty", 500.0)
  # A mod world starts standing on its solid floor; the boss arena keeps its hover height.
  let startPos = if arena.solidFloor: vec3(0, arena.floorY + 1.0, 0) else: vec3(0, 15, 0)
  result = Game3D(
    arena: arena,
    camera: initCamera3D(startPos),
    bossEnabled: opts.bossEnabled, bossId: opts.bossId,
    active: true, result: w3None, pendingResult: w3None,
    rules: World3DRules(exitOnBossDeath: true, exitOnPlayerDeath: true,
                        allowReload: true, mouseSensitivity: 0.1),
    modeKey: opts.modeKey, resumed: opts.resumed, carryHp: opts.carryHp,
    spawnPos: startPos, nextId: 1)
  # The 2D player's HP comes along when asked; a fresh world starts at full HP.
  result.player = newPlayer3D(startPos, if opts.carryHp: player2D.hp else: player2D.maxHp)
  if opts.bossEnabled:
    result.boss = getBoss3D(opts.bossId)
    # Profile difficulty scales the 3D boss pool like its 2D counterparts
    result.boss.health *= difficultyEnemyHpMult()
    result.boss.maxHealth *= difficultyEnemyHpMult()

# DAMAGE NUMBERS

proc spawnDamageNumber3D*(damageNumbers: var seq[DamageNumber3D], pos: Vector3f, damage: float32,
                          color = Color()) =
  ## Create a new damage number at the given position (color alpha 0 = yellow)
  let horizontalSpread = vec3(
    (rand(1.0) - 0.5) * 20.0,
    0,
    (rand(1.0) - 0.5) * 20.0
  )

  if damageNumbers.len >= MaxDamageNumbers3D: return
  damageNumbers.add(DamageNumber3D(
    pos: pos,
    vel: vec3(horizontalSpread.x, 50.0, horizontalSpread.z),  # Float upward
    damage: damage,
    lifetime: 0,
    maxLifetime: 1.5,
    fromPlayer: true,
    isCritical: false,
    color: color
  ))

proc updateDamageNumbers(damageNumbers: var seq[DamageNumber3D], dt: float32) =
  ## Update all damage numbers and remove expired ones
  var i = 0
  while i < damageNumbers.len:
    var dmg = damageNumbers[i]

    # Apply gravity/deceleration
    dmg.vel.y -= 80.0 * dt
    dmg.pos = vec3(
      dmg.pos.x + dmg.vel.x * dt,
      dmg.pos.y + dmg.vel.y * dt,
      dmg.pos.z + dmg.vel.z * dt
    )

    # Horizontal damping
    dmg.vel.x *= pow(0.95, 60.0 * dt)
    dmg.vel.z *= pow(0.95, 60.0 * dt)

    dmg.lifetime += dt
    damageNumbers[i] = dmg

    # Remove if expired
    if dmg.lifetime >= dmg.maxLifetime:
      damageNumbers.delete(i)
    else:
      i += 1

proc raylibCamera*(camera: FPSCamera): Camera =
  Camera(
    position: Vector3(x: camera.position.x, y: camera.position.y, z: camera.position.z),
    target: Vector3(x: camera.target.x, y: camera.target.y, z: camera.target.z),
    up: Vector3(x: 0, y: 1, z: 0),
    fovy: camera.fovy,
    projection: CameraProjection.Perspective
  )

proc worldToScreen3D*(camera: FPSCamera, pos: Vector3f): tuple[x, y: float32, visible: bool] =
  ## Where a world point lands on the screen; `visible` = in front of the
  ## camera and inside the window.
  let s = getWorldToScreen(Vector3(x: pos.x, y: pos.y, z: pos.z), raylibCamera(camera))
  let ahead = dot(pos - camera.position, camera.target - camera.position) > 0
  (s.x, s.y, ahead and s.x >= 0 and s.x <= getScreenWidth().float32 and
             s.y >= 0 and s.y <= getScreenHeight().float32)

proc drawDamageNumbers(damageNumbers: seq[DamageNumber3D], camera: FPSCamera) =
  ## Draw damage numbers in 3D space projected to 2D screen
  for dmg in damageNumbers:
    let progress = dmg.lifetime / dmg.maxLifetime
    let alpha = (1.0 - progress) * 255.0

    # Convert 3D position to screen position
    let screenPos = getWorldToScreen(
      Vector3(x: dmg.pos.x, y: dmg.pos.y, z: dmg.pos.z), raylibCamera(camera))

    # Only draw if on screen
    if screenPos.x >= 0 and screenPos.x <= getScreenWidth().float32 and
       screenPos.y >= 0 and screenPos.y <= getScreenHeight().float32:

      let damageText = $int(dmg.damage)
      let fontSize = max(8'i32, int32(24.0'f32 * damageNumberScaleOf(globalSettings)))
      let base = if dmg.color.a > 0: dmg.color else: Color(r: 255, g: 255, b: 100, a: 255)
      let color = Color(r: base.r, g: base.g, b: base.b, a: alpha.uint8)

      # Draw with shadow for better visibility
      drawText(damageText, int32(screenPos.x) - 1, int32(screenPos.y) - 1, fontSize, Black)
      drawText(damageText, int32(screenPos.x), int32(screenPos.y), fontSize, color)

# DAMAGE RULES

proc finishWorld3D*(world: Game3D, result: World3DResult) =
  ## Ends the world now (once): `result` is what game.nim acts on. Scripts
  ## request an ending with requestFinish3D instead, which lands at the end of
  ## the frame.
  if not world.active: return
  world.active = false
  world.result = result
  modWorld3DEnd(world, result)

proc requestFinish3D*(world: Game3D, result: World3DResult) =
  if world.pendingResult == w3None: world.pendingResult = result

proc damagePlayer3D*(world: Game3D, amount: float32, source = "script",
                     entity: Entity3D = nil): float32 =
  ## The one door for damage to the player: the world3dPlayerDamaged filter,
  ## the profile difficulty, the invulnerability window, and the lethal check.
  ## Returns the damage taken.
  if not world.active or amount <= 0 or world.player.invulnTimer > 0: return 0
  let filtered = modWorld3DPlayerDamaged(amount, source, entity)
  if filtered <= 0: return 0
  result = filtered * difficultyEnemyDamageMult()
  world.player.health -= result
  world.player.invulnTimer = world.player.hitInvuln
  if world.player.health <= 0 and modWorld3DPlayerLethal():
    if world.player.health <= 0: world.player.health = 1

proc healPlayer3D*(world: Game3D, amount: float32) =
  world.player.health = min(world.player.maxHealth, world.player.health + amount)

proc killPlayerFall(world: Game3D) =
  ## Below the death plane. A script that keeps the player alive gets them back
  ## at the spawn point.
  world.player.health = 0
  if modWorld3DPlayerLethal():
    world.player.health = max(world.player.health, 1.0'f32)
    world.player.pos = world.spawnPos
    world.player.vel = vec3(0, 0, 0)

proc killEntity3D*(world: Game3D, e: Entity3D, credit = true) =
  ## Death: hook, score and kill count (credit). The entity leaves the list
  ## when the frame's sweep runs.
  if not e.alive: return
  e.alive = false
  e.hp = min(e.hp, 0.0'f32)
  if credit:
    inc world.kills
    world.score += e.scoreValue
  modWorld3DEntityDeath(e)

proc damageEntity3D*(world: Game3D, e: Entity3D, amount: float32): float32 =
  ## Returns the damage dealt (0 for an invulnerable or dead entity).
  if not e.alive or e.invulnerable or amount <= 0: return 0
  result = min(amount, e.hp)
  e.hp -= amount
  if e.hp <= 0:
    killEntity3D(world, e)

proc damageBoss3D*(world: Game3D, amount: float32) =
  ## Scripted damage straight to the boss core (no shield or phase rules).
  if not world.bossEnabled or world.boss.health <= 0 or amount <= 0: return
  let dealt = min(amount, world.boss.health)
  world.boss.health -= amount
  spawnDamageNumber3D(world.damageNumbers, world.boss.pos, dealt)

# CONTENT

proc addEntity3D*(world: Game3D, e: Entity3D) =
  ## An entity joins the world: profile difficulty scales its HP once, here.
  if e.id == 0: e.id = allocId3D(world)
  e.hp *= difficultyEnemyHpMult()
  e.maxHp *= difficultyEnemyHpMult()
  if e.fireInterval > 0 and e.fireTimer <= 0: e.fireTimer = e.fireInterval
  e.alive = true
  world.entities.add(e)
  modWorld3DEntitySpawn(e)

proc processWorld3DActions*(world: Game3D) =
  ## Applies what scripts queued (spawns, finish requests); called between the
  ## frame's stages, outside every loop.
  if world3dActions.len == 0: return
  var actions = move world3dActions
  world3dActions = @[]
  for a in actions:
    case a.kind
    of wkSpawnEntity:
      # (a script may have removed or killed it again before it joined; it then
      # never joins, and is gone for good)
      if not a.entity.isNil:
        if a.entity.alive and not a.entity.removed and world.entities.len < MaxEntities3D:
          addEntity3D(world, a.entity)
          world3DActionDone(a)
        else:
          a.entity.alive = false
          a.entity.removed = true
    of wkSpawnProjectile:
      if not a.projectile.isNil:
        if a.projectile.active and not a.projectile.removed and
           world.projectiles.len < MaxProjectiles3D:
          world.projectiles.add(a.projectile)
        else:
          a.projectile.active = false
          a.projectile.removed = true
    of wkSpawnPickup:
      if not a.pickup.isNil:
        if a.pickup.alive and not a.pickup.removed and world.pickups.len < MaxPickups3D:
          if a.pickup.id == 0: a.pickup.id = allocId3D(world)
          world.pickups.add(a.pickup)
        else:
          a.pickup.alive = false
          a.pickup.removed = true
    of wkFinish:
      requestFinish3D(world, a.result)

# RAYCAST

type
  RayHit3D* = object
    kind*: string        ## "none", "platform", "floor", "entity", "boss" or "satellite"
    dist*: float32
    pos*: Vector3f
    entity*: Entity3D    ## the entity hit, when kind == "entity"
    platform*: int       ## index into arena.platforms, when kind == "platform"

proc raySphere(origin, dir, center: Vector3f, radius: float32): float32 =
  ## Distance along a unit ray to a sphere, -1 for a miss.
  let oc = origin - center
  let b = dot(oc, dir)
  let c = dot(oc, oc) - radius * radius
  let disc = b * b - c
  if disc < 0: return -1
  let t = -b - sqrt(disc)
  if t >= 0: t
  elif -b + sqrt(disc) >= 0: 0.0'f32   # started inside
  else: -1

proc rayBox(origin, dir, center, half: Vector3f): float32 =
  ## Slab test against an axis-aligned box, -1 for a miss.
  var tMin = 0.0'f32
  var tMax = 1.0e30'f32
  let o = [origin.x, origin.y, origin.z]
  let d = [dir.x, dir.y, dir.z]
  let c = [center.x, center.y, center.z]
  let h = [half.x, half.y, half.z]
  for axis in 0 .. 2:
    if abs(d[axis]) < 1.0e-8:
      if o[axis] < c[axis] - h[axis] or o[axis] > c[axis] + h[axis]: return -1
    else:
      var t1 = (c[axis] - h[axis] - o[axis]) / d[axis]
      var t2 = (c[axis] + h[axis] - o[axis]) / d[axis]
      if t1 > t2: swap(t1, t2)
      tMin = max(tMin, t1)
      tMax = min(tMax, t2)
      if tMin > tMax: return -1
  tMin

proc raycast3D*(world: Game3D, origin, dir: Vector3f, maxDist: float32): RayHit3D =
  ## The nearest platform, live entity, boss core or satellite along a ray.
  let d = dir.normalize()
  result = RayHit3D(kind: "none", dist: maxDist)
  for i, p in world.arena.platforms:
    let t = rayBox(origin, d, p.pos, p.size)
    if t >= 0 and t < result.dist:
      result.kind = "platform"
      result.dist = t
      result.platform = i
      result.entity = nil
  if world.arena.solidFloor and d.y < -1.0e-6 and origin.y >= world.arena.floorY:
    let t = (world.arena.floorY - origin.y) / d.y
    let hx = origin.x + d.x * t
    let hz = origin.z + d.z * t
    if t < result.dist and sqrt(hx * hx + hz * hz) <= world.arena.boundsRadius:
      result.kind = "floor"
      result.dist = t
      result.entity = nil
  for e in world.entities:
    if not e.alive: continue
    let t = raySphere(origin, d, e.pos, e.radius)
    if t >= 0 and t < result.dist:
      result.kind = "entity"
      result.dist = t
      result.entity = e
  if world.bossEnabled and world.boss.health > 0:
    let t = raySphere(origin, d, world.boss.pos, 22.0)
    if t >= 0 and t < result.dist:
      result.kind = "boss"
      result.dist = t
      result.entity = nil
    for sat in world.boss.satellites:
      if sat.active:
        let ts = raySphere(origin, d, sat.pos, 6.0)
        if ts >= 0 and ts < result.dist:
          result.kind = "satellite"
          result.dist = ts
          result.entity = nil
  result.pos = origin + d * result.dist

# FRAME STAGES

proc landOnPlatform(e: Entity3D, nextPos: var Vector3f, arena: Arena3D) =
  ## A falling entity comes to rest on a platform's top or the arena's solid floor.
  if e.vel.y > 0: return
  let footBefore = e.pos.y - e.radius
  let footAfter = nextPos.y - e.radius
  for p in arena.platforms:
    let top = p.pos.y + p.size.y
    if footBefore >= top - 0.5 and footAfter <= top and
       abs(nextPos.x - p.pos.x) < p.size.x + e.radius * 0.5 and
       abs(nextPos.z - p.pos.z) < p.size.z + e.radius * 0.5:
      nextPos.y = top + e.radius
      e.vel.y = 0
      return
  if arena.solidFloor and footBefore >= arena.floorY - 0.5 and footAfter <= arena.floorY:
    nextPos.y = arena.floorY + e.radius
    e.vel.y = 0

proc steerEntity(world: Game3D, e: Entity3D, dt: float32) =
  ## The built-in AI: sets the heading and velocity, and shoots.
  let toPlayer = world.player.pos - e.pos
  let flat = vec3(toPlayer.x, 0, toPlayer.z)
  case e.ai
  of aiNone:
    discard
  of aiChase:
    let dir = if e.gravity: flat.normalize() else: toPlayer.normalize()
    e.vel.x = dir.x * e.speed
    e.vel.z = dir.z * e.speed
    if not e.gravity: e.vel.y = dir.y * e.speed
  of aiOrbit:
    let radius = max(1.0'f32, e.orbitRadius)
    let radial = (vec3(0, 0, 0) - flat).normalize()   # from the player out to the entity
    let tangent = vec3(-radial.z, 0, radial.x)
    let pull = clamp((radius - flat.length()) * 2.0'f32, -e.speed * 2, e.speed * 2)
    e.vel.x = tangent.x * e.speed + radial.x * pull
    e.vel.z = tangent.z * e.speed + radial.z * pull
  of aiWander:
    e.wanderTimer -= dt
    if e.wanderTimer <= 0:
      let a = rand(2.0 * PI).float32
      e.wanderDir = vec3(cos(a), 0, sin(a))
      e.wanderTimer = 1.5 + rand(2.0).float32
    e.vel.x = e.wanderDir.x * e.speed
    e.vel.z = e.wanderDir.z * e.speed
  of aiTurret:
    e.vel.x = 0
    e.vel.z = 0
  # Face the way it moves (or the player, standing still)
  let heading = if e.ai == aiTurret or (abs(e.vel.x) + abs(e.vel.z)) < 0.01: flat
                else: vec3(e.vel.x, 0, e.vel.z)
  if heading.length() > 0.001:
    e.yaw = radToDeg(arctan2(heading.x, heading.z))
  # Shooting (any AI with a fire interval)
  if e.fireInterval > 0:
    e.fireTimer -= dt
    if e.fireTimer <= 0 and (e.range <= 0 or toPlayer.length() <= e.range):
      e.fireTimer = e.fireInterval
      let dir = toPlayer.normalize()
      var shot = newProjectile3D(e.pos, dir * e.projectileSpeed, e.projectileDamage, false)
      shot.ownerId = e.id
      shot.tag = e.tag
      if world.projectiles.len < MaxProjectiles3D: world.projectiles.add(shot)

proc updateEntities(world: Game3D, dt: float32) =
  # By index and never resizing the list: hooks fired in here only queue new entities.
  for i in 0 ..< world.entities.len:
    let e = world.entities[i]
    if not e.alive: continue
    e.age += dt
    if e.contactTimer > 0: e.contactTimer -= dt
    if not modWorld3DEntityUpdate(e, dt):
      steerEntity(world, e, dt)
    if not e.alive: continue   # a script killed it
    # Physics
    if e.gravity: e.vel.y += world.arena.gravity * dt
    var nextPos = e.pos + e.vel * dt
    if e.gravity: landOnPlatform(e, nextPos, world.arena)
    e.pos = nextPos
    let dist = sqrt(e.pos.x * e.pos.x + e.pos.z * e.pos.z)
    if dist > world.arena.boundsRadius:
      let k = world.arena.boundsRadius / dist
      e.pos.x *= k
      e.pos.z *= k
    if e.pos.y < world.arena.deathPlaneY:
      killEntity3D(world, e, credit = false)
      continue
    # Touching the player
    let toPlayer = world.player.pos - e.pos
    let reach = e.radius + world.player.radius
    if toPlayer.length() < reach:
      if e.contactDamage > 0 and e.contactTimer <= 0:
        discard damagePlayer3D(world, e.contactDamage, "contact", e)
        e.contactTimer = 1.0
      if e.solid:
        let push = vec3(toPlayer.x, 0, toPlayer.z).normalize()
        let flatGap = sqrt(toPlayer.x * toPlayer.x + toPlayer.z * toPlayer.z)
        let overlap = reach - flatGap
        if overlap > 0:
          world.player.pos.x += push.x * overlap
          world.player.pos.z += push.z * overlap

proc homingTarget(world: Game3D, pos: Vector3f): tuple[found: bool, pos: Vector3f] =
  ## The nearest thing a player's homing shot can chase.
  var best = 1.0e30'f32
  for e in world.entities:
    if e.alive:
      let d = distance(pos, e.pos)
      if d < best:
        best = d
        result = (true, e.pos)
  if world.bossEnabled and world.boss.health > 0:
    let d = distance(pos, world.boss.pos)
    if d < best:
      result = (true, world.boss.pos)

proc updateProjectiles(world: Game3D, dt: float32, holdEnemyHoming = false) =
  ## holdEnemyHoming: the boss is mid phase transition (its whole update, and with
  ## it the steering of its homing shots, pauses, as it always did).
  # Homing steers a shot's heading and keeps its speed (a shot spawned at rest
  # stays at rest, as the boss's swarm always did): enemy shots chase the
  # player, the player's chase the nearest entity or the boss.
  for proj in world.projectiles:
    if proj.isHoming and proj.active and not (holdEnemyHoming and not proj.fromPlayer):
      var aim: Vector3f
      var chase = true
      if proj.fromPlayer:
        let target = homingTarget(world, proj.pos)
        chase = target.found
        aim = target.pos
      else:
        aim = world.player.pos
      if chase:
        let homingForce = (aim - proj.pos).normalize() * proj.homingStrength
        proj.vel = (proj.vel + homingForce * dt).normalize() * proj.vel.length()

  for proj in world.projectiles:
    if proj.active:
      if proj.gravity != 0:
        proj.vel.y += world.arena.gravity * proj.gravity * dt
      proj.pos = proj.pos + proj.vel * dt
      proj.lifetime -= dt

      if proj.lifetime <= 0:
        proj.active = false

      # Check hits
      if proj.fromPlayer:
        if world.bossEnabled:
          let hitResult = takeBossDamage(world.boss, proj)
          if hitResult.hit:
            # Spawn damage number at hit position
            spawnDamageNumber3D(world.damageNumbers, hitResult.hitPos, hitResult.damageDealt)
            proj.active = false
        if proj.active:
          for e in world.entities:
            if not e.alive or e.id in proj.hitIds: continue
            if distance(proj.pos, e.pos) < e.radius + proj.effectiveRadius():
              let dealt = damageEntity3D(world, e, modWorld3DHit(proj.damage, e, "", proj))
              if dealt > 0:
                spawnDamageNumber3D(world.damageNumbers, proj.pos, dealt)
              if proj.pierce > 0:
                dec proj.pierce
                proj.hitIds.add(e.id)
              else:
                proj.active = false
                break
      else:
        if distance(proj.pos, world.player.pos) < world.player.radius + proj.effectiveRadius():
          discard damagePlayer3D(world, proj.damage, "projectile")
          proj.active = false

proc updatePickups(world: Game3D, dt: float32) =
  for p in world.pickups:
    if not p.alive: continue
    p.age += dt
    if distance(p.pos, world.player.pos) < p.radius + world.player.radius:
      if not modWorld3DPickup(p):
        case p.kind
        of "health": healPlayer3D(world, p.value)
        of "ammo":
          world.player.weapon.ammo = min(world.player.weapon.maxAmmo,
                                         world.player.weapon.ammo + int(p.value))
        else: discard
      p.alive = false

proc sweepDead*(world: Game3D) =
  ## Drops what died this frame from the lists; what leaves is `removed` for good
  ## (a script still holding it reads "no longer exists").
  var i = 0
  for e in world.entities:
    if e.alive:
      world.entities[i] = e
      inc i
    else:
      e.removed = true
  world.entities.setLen(i)
  i = 0
  for p in world.pickups:
    if p.alive:
      world.pickups[i] = p
      inc i
    else:
      p.removed = true
  world.pickups.setLen(i)
  i = 0
  for p in world.projectiles:
    if p.active:
      world.projectiles[i] = p
      inc i
    else:
      p.removed = true
  world.projectiles.setLen(i)

proc updateGame3D*(world: Game3D, dt: float32) =
  # Handle pause toggle
  if isKeyPressed(KeyboardKey.Escape):
    world.paused = not world.paused
    if world.paused:
      enableCursor()
    else:
      disableCursor()
  if world.paused and isKeyPressed(QuitKey):
    world.quitRequested = true   # main.nim leaves for the desktop

  if not world.active or world.paused:
    return

  if not world.startFired:
    world.startFired = true
    modWorld3DStart(world, world.resumed)
    processWorld3DActions(world)

  world.timeElapsed += dt

  # Update camera
  let mouseDelta = getMouseDelta()
  updateCamera(world.camera, mouseDelta, world.rules.mouseSensitivity)

  # Keep mouse centered to prevent hitting screen edges
  let centerX = getScreenWidth() div 2
  let centerY = getScreenHeight() div 2
  setMousePosition(centerX, centerY)

  modWorld3DPreUpdate(world, dt)
  processWorld3DActions(world)

  # Update player
  let fell = updatePlayer(world.player, world.camera, world.arena, dt)
  updateWeapon(world.player, dt)
  if fell: killPlayerFall(world)

  # Shooting
  let trigger = world.rules.autoFire or
                (if world.player.weapon.automatic: isMouseButtonDown(MouseButton.Left)
                 else: isMouseButtonPressed(MouseButton.Left))
  if trigger and weaponReady(world.player):
    if modWorld3DShoot(world):
      world.player.weapon.fireTimer = world.player.weapon.fireRate   # a script fired instead
    else:
      discard fireWeapon(world.player, world.camera, world.projectiles)

  if world.rules.allowReload and isKeyPressed(KeyboardKey.R):
    reload(world.player)

  # Update platforms
  updatePlatforms(world.arena.platforms, dt)

  # Update boss (with arena for environment changes)
  let bossFrozen = world.bossEnabled and world.boss.phaseTransitionTimer > 0
  if world.bossEnabled:
    updateBoss(world.boss, world.player, world.projectiles, world.arena, dt)

  updateEntities(world, dt)
  processWorld3DActions(world)

  updateProjectiles(world, dt, bossFrozen)
  updatePickups(world, dt)
  sweepDead(world)

  # Update damage numbers
  updateDamageNumbers(world.damageNumbers, dt)

  # Update camera position to follow player
  world.camera.position = world.player.pos + vec3(0, 2, 0)
  world.camera.target = world.camera.position + world.camera.getForward()

  modWorld3DUpdate(world, dt)
  processWorld3DActions(world)

  # Check win/loss
  if world.pendingResult != w3None:
    finishWorld3D(world, world.pendingResult)
  elif world.player.health <= 0 and world.rules.exitOnPlayerDeath:
    finishWorld3D(world, w3Lost)
  elif world.bossEnabled and world.boss.health <= 0 and world.rules.exitOnBossDeath:
    finishWorld3D(world, w3Won)
  elif world.rules.timeLimit > 0 and world.timeElapsed >= world.rules.timeLimit:
    finishWorld3D(world, if world.rules.timeLimitWins: w3Won else: w3Lost)

# RENDERING

proc renderCamera(world: Game3D): Camera =
  ## The camera the scene is drawn with: the world's, shaken (world3d.shake).
  result = raylibCamera(world.camera)
  if world.camera.shake > 0.001:
    let k = world.camera.shake * 0.2'f32
    let jitter = Vector3(x: (rand(2.0) - 1.0).float32 * k, y: (rand(2.0) - 1.0).float32 * k,
                         z: (rand(2.0) - 1.0).float32 * k)
    result.position = Vector3(x: result.position.x + jitter.x, y: result.position.y + jitter.y,
                              z: result.position.z + jitter.z)
    result.target = Vector3(x: result.target.x + jitter.x, y: result.target.y + jitter.y,
                            z: result.target.z + jitter.z)

proc drawEntity3D(world: Game3D, e: Entity3D, cam: Camera) =
  if modWorld3DEntityDraw(e): return
  let pos = Vector3(x: e.pos.x, y: e.pos.y, z: e.pos.z)
  # A mod's look for this tag (override.model("entity3d:<tag>")); a model set on
  # the entity itself wins over it.
  if e.shape != esNone and not (e.shape == esModel and e.modelId > 0) and
     entity3dTex.len > 0 and e.tag in entity3dTex:
    let look = entity3dTex[e.tag]
    if look.hasLook:
      drawBodyWorld3D(look, cam, e.pos.x, e.pos.y, e.pos.z, e.radius * 2, e.yaw, e.age.float,
                      key = animKey(cast[pointer](e)))
      return
  case e.shape
  of esNone:
    discard
  of esCube:
    drawCube(pos, e.size.x, e.size.y, e.size.z, e.color)
    drawCubeWires(pos, e.size.x, e.size.y, e.size.z, fade(White, 0.5))
  of esSphere:
    drawSphere(pos, e.radius, e.color)
    drawSphereWires(pos, e.radius, 8, 8, fade(White, 0.35))
  of esCylinder:
    drawCylinder(Vector3(x: e.pos.x, y: e.pos.y - e.size.y / 2, z: e.pos.z),
                 e.radius, e.radius, e.size.y, 14, e.color)
  of esModel:
    if e.modelId > 0:
      let scale = if e.modelScale > 0: e.modelScale
                  else: 2 * e.radius / max(modelFootprint(e.modelId), 1.0e-6'f32)
      drawModelWorld3D(e.modelId, e.pos.x, e.pos.y, e.pos.z, scale, e.yaw, 0, 0,
                       ModelPose(anim: e.modelAnim, speed: e.modelSpeed, lit: true, tint: White,
                                 fade: e.modelFade),
                       White, world.timeElapsed.float, animKey(cast[pointer](e)))

proc drawPickup3D(p: Pickup3D, cam: Camera) =
  if pickup3dTex.len > 0 and p.kind in pickup3dTex:
    let look = pickup3dTex[p.kind]
    if look.hasLook:
      drawBodyWorld3D(look, cam, p.pos.x, p.pos.y + sin(p.age * 3.0) * 1.5, p.pos.z, p.radius * 2,
                      p.age * 60.0, p.age.float)
      return
  let color = if p.color.a > 0: p.color
              else:
                case p.kind
                of "health": Color(r: 60, g: 230, b: 110, a: 255)
                of "ammo": Color(r: 255, g: 210, b: 60, a: 255)
                else: White
  let bob = sin(p.age * 3.0) * 1.5
  let pos = Vector3(x: p.pos.x, y: p.pos.y + bob, z: p.pos.z)
  drawSphere(pos, p.radius * 0.5, color)
  drawSphereWires(pos, p.radius, 8, 8, fade(color, 0.5))

proc renderGame3D*(world: Game3D) =
  # 3D rendering
  let cam = renderCamera(world)
  beginMode3D(cam)

  drawArena(world.arena)

  for platform in world.arena.platforms:
    drawPlatform(platform)

  if world.bossEnabled:
    # Draw gravity wells
    drawGravityWells(world.boss)

    drawBoss(world.boss, cam)

  for e in world.entities:
    if e.alive:
      drawEntity3D(world, e, cam)

  for p in world.pickups:
    if p.alive:
      drawPickup3D(p, cam)

  for proj in world.projectiles:
    if proj.active:
      let look = projectile3dTex[proj.fromPlayer]
      if look.hasLook:
        drawBodyWorld3D(look, cam, proj.pos.x, proj.pos.y, proj.pos.z, proj.effectiveRadius() * 2,
                        radToDeg(arctan2(proj.vel.x, proj.vel.z)), getTime())
      else:
        drawProjectile(proj)

  modWorld3DDraw(world)

  endMode3D()

  # draw3d.text labels (text cannot be drawn inside the 3D camera)
  if world3dLabels.len > 0:
    for label in world3dLabels:
      let sp = worldToScreen3D(world.camera, label.pos)
      if sp.visible and label.font > 0:
        let size = label.size.float32
        let x = sp.x.float32 - measureModText(label.font, label.text, size, label.spacing) / 2
        drawModText(label.font, label.text, x + 1, sp.y.float32 + 1, size, label.spacing, fade(Black, 0.7))
        drawModText(label.font, label.text, x, sp.y.float32, size, label.spacing, label.color)
      elif sp.visible:
        let w = measureText(label.text, label.size)
        drawText(label.text, int32(sp.x) - w div 2 + 1, int32(sp.y) + 1, label.size, fade(Black, 0.7))
        drawText(label.text, int32(sp.x) - w div 2, int32(sp.y), label.size, label.color)
    world3dLabels.setLen(0)

  let showPlayer = not hudHidden(hpPlayer)
  let showBoss = world.bossEnabled and not hudHidden(hpBoss)

  # Draw satellite healthbars (in 2D overlay)
  if showBoss:
    drawSatelliteHealthbars(world.boss, world.camera)

  # Draw damage numbers (in 2D overlay), subject to the Interface tab's toggle.
  if showDamageNumbersOf(globalSettings) and not hudHidden(hpDamageNumbers):
    drawDamageNumbers(world.damageNumbers, world.camera)

  # 2D HUD
  if showBoss or showPlayer:
    drawRectangle(10, 10, 320, if showBoss: 150 else: 60, fade(Black, 0.7))
  if showPlayer:
    drawText(t(tkGame3DHp) & ": " & $int(world.player.health), 20, 20, 20, Red)
    let ammoText = if world.player.weapon.reloadTimer > 0: t(tkGame3DReloading)
                   elif world.player.weapon.infiniteAmmo: t(tkGame3DAmmo) & ": --"
                   else: t(tkGame3DAmmo) & ": " & $world.player.weapon.ammo & "/" & $world.player.weapon.maxAmmo
    drawText(ammoText, 20, 45, 20, Yellow)

  if showBoss:
    # Boss health bar
    let bossHpPercent = world.boss.health / world.boss.maxHealth
    drawText(t(tkGame3DBossHp) & ":", 20, 70, 18, White)
    drawRectangle(20, 92, 280, 20, Color(r: 50, g: 0, b: 0, a: 200))
    drawRectangle(20, 92, int32(280.0 * bossHpPercent), 20, Color(r: 255, g: 50, b: 50, a: 255))
    drawRectOutline(20, 92, 280, 20, White)

    # Phase indicator with color
    let phaseColor = case world.boss.phase
      of 1: Gray
      of 2: Color(r: 150, g: 50, b: 200, a: 255)
      of 3: Color(r: 255, g: 0, b: 0, a: 255)
      else: White

    let phaseText = t(tkGame3DPhase) & " " & $world.boss.phase & "/3"
    drawText(phaseText, 20, 120, 20, phaseColor)

    # Satellite count (Phase 1 only)
    if world.boss.phase == 1:
      var activeSats = 0
      for sat in world.boss.satellites:
        if sat.active:
          activeSats += 1

      if activeSats > 0:
        drawText(t(tkGame3DSatellites) & ": " & $activeSats & " (" & t(tkGame3DDestroyAll) & ")", 20, 145, 16, Color(r: 255, g: 200, b: 50, a: 255))

    # Phase transition warning
    if world.boss.phaseTransitionTimer > 0:
      let warningText = t(tkGame3DPhaseTransition)
      let textWidth = measureText(warningText, 40)
      let flashAlpha = (sin(world.boss.phaseTransitionTimer * 10.0) * 0.5 + 0.5) * 255.0
      drawText(warningText, (getScreenWidth() - textWidth) div 2, 100, 40,
               fade(Color(r: 255, g: 255, b: 0, a: 255), flashAlpha / 255.0))

  # Crosshair
  let centerX = getScreenWidth() div 2
  let centerY = getScreenHeight() div 2
  if not hudHidden(hpCrosshair):
    drawCircleOutline(centerX, centerY, 10, White)
    drawStroke(centerX - 15, centerY, centerX + 15, centerY, White)
    drawStroke(centerX, centerY - 15, centerX, centerY + 15, White)

  modWorld3DDrawHud(world, getScreenWidth(), getScreenHeight())

  # Pause message
  if world.paused:
    let pauseText = t(tkGame3DPaused)
    let resumeText = t(tkGame3DPressEscResume)
    let quitText = t(tkGame3DPressQQuit)
    let textWidth1 = measureText(pauseText, 40)
    let textWidth2 = measureText(resumeText, 20)
    let textWidth3 = measureText(quitText, 20)

    # Dark overlay
    drawRectangle(0, 0, getScreenWidth(), getScreenHeight(), fade(Black, 0.5))

    drawText(pauseText, centerX - textWidth1 div 2, centerY - 30, 40, White)
    drawText(resumeText, centerX - textWidth2 div 2, centerY + 20, 20, LightGray)
    drawText(quitText, centerX - textWidth3 div 2, centerY + 50, 20, LightGray)
