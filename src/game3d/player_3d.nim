## 3D Player Module
## Handles 3D player movement, shooting, and weapon systems
##
## A player is driven by their intent (Player3D.intent), never the devices, so
## a co-op world moves every player alike. In 3D the 2D intent's fields mean:
## `move` = (strafe right, forward), `aim` = (yaw, pitch) in degrees,
## `fireHeld` = the trigger held, `wallHeld` = sprint, and the press counts
## ieDash = jump, ieAbility = a trigger pull (semi-automatic weapons),
## ieInteract = reload. capture3DIntent fills it from this machine's devices.

import raylib, math, random
import ../modding/mod_patch_core
import ../types, ../input_intent
import types_3d, engine_3d

const
  Edge3DJump* = ieDash
  Edge3DTrigger* = ieAbility
  Edge3DReload* = ieInteract

proc take3D*(p: Player3D, e: IntentEdge): bool =
  ## True once per press of `e` (its count is then used up).
  if p.intent.edges[e] != p.intent.seen[e]:
    p.intent.seen[e] = p.intent.edges[e]
    true
  else:
    false

proc viewOf*(p: Player3D): FPSCamera =
  ## A camera on the player's own view: where they move and shoot toward.
  FPSCamera(position: p.pos + vec3(0, 2, 0), up: vec3(0, 1, 0), fovy: 60.0,
            yaw: p.yaw, pitch: p.pitch)

proc capture3DIntent*(p: Player3D, cam: var FPSCamera, sensitivity: float32) {.moddable.} =
  ## This machine's keyboard and mouse into its player's intent: the mouse
  ## turns `cam` (this machine's view), and the view's angles are the aim.
  var it = p.intent
  beginIntentFrame(it)
  updateCamera(cam, getMouseDelta(), sensitivity)
  # Keep the mouse centred so it never hits the window's edge.
  setMousePosition(getScreenWidth() div 2, getScreenHeight() div 2)
  var move = Vector2()
  if isKeyDown(KeyboardKey.W): move.y += 1
  if isKeyDown(KeyboardKey.S): move.y -= 1
  if isKeyDown(KeyboardKey.D): move.x += 1
  if isKeyDown(KeyboardKey.A): move.x -= 1
  let len = sqrt(move.x * move.x + move.y * move.y)
  it.move = if len > 0: Vector2(x: move.x / len, y: move.y / len) else: move
  it.aim = Vector2(x: cam.yaw, y: cam.pitch)
  it.wallHeld = isKeyDown(KeyboardKey.LeftShift)
  it.fireHeld = isMouseButtonDown(MouseButton.Left)
  if isMouseButtonPressed(MouseButton.Left): pressEdge(it, Edge3DTrigger)
  if isKeyPressed(KeyboardKey.Space): pressEdge(it, Edge3DJump)
  if isKeyPressed(KeyboardKey.R): pressEdge(it, Edge3DReload)
  p.intent = it

proc applyAim3D*(p: Player3D) =
  ## The player looks where their intent aims (pitch kept off the poles).
  p.yaw = p.intent.aim.x
  p.pitch = clamp(p.intent.aim.y, -89.9'f32, 89.9'f32)

proc newWeapon3D(): Weapon3D {.moddable.} =
  Weapon3D(
    ammo: 500,        # Increased from 150 for longer fights
    maxAmmo: 500,     # Increased from 150 for longer fights
    fireRate: 0.125,
    fireTimer: 0.0,
    damage: 15.0,
    projectileSpeed: 600.0,
    spread: 0.0,
    pellets: 1
  )

proc updateWeapon*(player: Player3D, dt: float32) {.moddable.} =
  if player.weapon.fireTimer > 0:
    player.weapon.fireTimer -= dt
  if player.weapon.reloadTimer > 0:
    player.weapon.reloadTimer -= dt
    if player.weapon.reloadTimer <= 0:
      player.weapon.reloadTimer = 0
      player.weapon.ammo = player.weapon.maxAmmo

proc weaponReady*(player: Player3D): bool {.moddable.} =
  ## Whether pulling the trigger now fires a shot.
  (player.weapon.ammo > 0 or player.weapon.infiniteAmmo) and
    player.weapon.fireTimer <= 0 and player.weapon.reloadTimer <= 0

proc fireWeapon*(player: Player3D, camera: FPSCamera, projectiles: var seq[Projectile3D]): bool {.moddable.} =
  if weaponReady(player):
    if not player.weapon.infiniteAmmo:
      player.weapon.ammo -= 1
    player.weapon.fireTimer = player.weapon.fireRate

    let forward = camera.getForward()
    let spawnPos = player.pos + vec3(0, 1.5, 0) + forward * 2.0

    for _ in 0 ..< clamp(player.weapon.pellets, 1, MaxPellets3D):
      var dir = forward
      if player.weapon.spread > 0:
        # Each pellet strays inside the cone by turning the camera a little
        var aim = camera
        aim.yaw += (rand(2.0) - 1.0).float32 * player.weapon.spread
        aim.pitch += (rand(2.0) - 1.0).float32 * player.weapon.spread
        dir = aim.getForward()
      projectiles.add(Projectile3D(
        pos: spawnPos,
        vel: dir * player.weapon.projectileSpeed,
        damage: player.weapon.damage,
        lifetime: 3.0,
        fromPlayer: true,
        active: true,
        radius: player.weapon.projectileRadius,
        color: player.weapon.projectileColor
      ))
    return true
  false

proc reload*(player: Player3D) {.moddable.} =
  if player.weapon.reloadTime <= 0:
    player.weapon.ammo = player.weapon.maxAmmo
  elif player.weapon.reloadTimer <= 0 and player.weapon.ammo < player.weapon.maxAmmo:
    player.weapon.reloadTimer = player.weapon.reloadTime

proc newPlayer3D*(startPos: Vector3, health2D: float32, slot: int32 = 0): Player3D {.moddable.} =
  Player3D(
    slot: slot,
    pos: startPos,
    vel: vec3(0, 0, 0),
    health: health2D,    # Carry over health from 2D phase
    maxHealth: health2D, # Maintain same max health
    speed: 75.0,  # Balanced speed for 3D movement
    sprintMultiplier: 1.5,
    jumpForce: 50.0,
    jumpsRemaining: 2,
    maxJumps: 2,
    weapon: newWeapon3D(),
    grounded: false,
    radius: 3.5,         # + a default shot's 1.5 = the classic 5.0 hit distance
    canJump: true,
    gravityScale: 1.0
  )

proc updatePlayer*(player: Player3D, arena: Arena3D, dt: float32): bool {.moddable.} =
  ## Movement (their intent, along where they look), gravity, platform
  ## landings and the arena bounds. True when the player fell through the
  ## death plane (the caller decides what that means).
  if player.invulnTimer > 0:
    player.invulnTimer -= dt

  # Movement input
  let view = player.viewOf()
  let forward = view.getForward()
  let right = view.getRight()

  # Flatten movement to XZ plane
  let flatForward = vec3(forward.x, 0, forward.z).normalize()
  let flatRight = vec3(right.x, 0, right.z).normalize()

  var moveDir = flatRight * player.intent.move.x + flatForward * player.intent.move.y

  # Normalize and apply speed
  if moveDir.length() > 0:
    moveDir = moveDir.normalize()
    let speed = if player.intent.wallHeld:
                  player.speed * player.sprintMultiplier
                else:
                  player.speed
    player.vel.x = moveDir.x * speed
    player.vel.z = moveDir.z * speed
  else:
    player.vel.x = 0
    player.vel.z = 0

  # Apply gravity
  player.vel.y += arena.gravity * player.gravityScale * dt

  # Jumping
  if player.canJump and player.take3D(Edge3DJump) and player.jumpsRemaining > 0:
    player.vel.y = player.jumpForce
    player.jumpsRemaining -= 1

  # Update position
  let prevY = player.pos.y
  let nextPos = player.pos + player.vel * dt

  # Check platform collision
  let (collided, platform) = checkCollision(nextPos, 1.0, arena.platforms)

  if collided:
    # Landing on platform
    if player.vel.y < 0:
      player.pos.y = platform.pos.y + platform.size.y + 1.0
      player.vel.y = 0
      player.jumpsRemaining = player.maxJumps
      player.grounded = true

      # Check for jump pad
      if platform.jumpPad:
        player.vel.y = platform.jumpForce * 0.05  # Scale jump force
        player.jumpsRemaining = player.maxJumps

      player.pos.x = nextPos.x
      player.pos.z = nextPos.z
    else:
      player.pos = nextPos
  else:
    player.pos = nextPos
    player.grounded = false

  # Solid floor: lands exactly like a platform top (stand height +1.0)
  if arena.solidFloor and player.vel.y <= 0 and
     player.pos.y < arena.floorY + 1.0 and prevY >= arena.floorY:
    player.pos.y = arena.floorY + 1.0
    player.vel.y = 0
    player.jumpsRemaining = player.maxJumps
    player.grounded = true

  # Keep player in arena bounds
  let maxDist = arena.boundsRadius
  let dist = sqrt(player.pos.x * player.pos.x + player.pos.z * player.pos.z)
  if dist > maxDist:
    let angle = arctan2(player.pos.z, player.pos.x)
    player.pos.x = cos(angle) * maxDist
    player.pos.z = sin(angle) * maxDist

  # Death plane
  player.pos.y < arena.deathPlaneY
