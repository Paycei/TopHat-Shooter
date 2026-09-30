## 3D Player Module
## Handles 3D player movement, shooting, and weapon systems

import raylib, math, random
import types_3d, engine_3d

proc newWeapon3D*(): Weapon3D =
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

proc updateWeapon*(player: var Player3D, dt: float32) =
  if player.weapon.fireTimer > 0:
    player.weapon.fireTimer -= dt
  if player.weapon.reloadTimer > 0:
    player.weapon.reloadTimer -= dt
    if player.weapon.reloadTimer <= 0:
      player.weapon.reloadTimer = 0
      player.weapon.ammo = player.weapon.maxAmmo

proc weaponReady*(player: Player3D): bool =
  ## Whether pulling the trigger now fires a shot.
  (player.weapon.ammo > 0 or player.weapon.infiniteAmmo) and
    player.weapon.fireTimer <= 0 and player.weapon.reloadTimer <= 0

proc fireWeapon*(player: var Player3D, camera: FPSCamera, projectiles: var seq[Projectile3D]): bool =
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

proc reload*(player: var Player3D) =
  if player.weapon.reloadTime <= 0:
    player.weapon.ammo = player.weapon.maxAmmo
  elif player.weapon.reloadTimer <= 0 and player.weapon.ammo < player.weapon.maxAmmo:
    player.weapon.reloadTimer = player.weapon.reloadTime

proc newPlayer3D*(startPos: Vector3f, health2D: float32): Player3D =
  Player3D(
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

proc updatePlayer*(player: var Player3D, camera: FPSCamera, arena: Arena3D, dt: float32): bool =
  ## Movement, gravity, platform landings and the arena bounds. True when the
  ## player fell through the death plane (the caller decides what that means).
  if player.invulnTimer > 0:
    player.invulnTimer -= dt

  # Movement input
  var moveDir = vec3(0, 0, 0)
  let forward = camera.getForward()
  let right = camera.getRight()

  # Flatten movement to XZ plane
  let flatForward = vec3(forward.x, 0, forward.z).normalize()
  let flatRight = vec3(right.x, 0, right.z).normalize()

  if isKeyDown(KeyboardKey.W):
    moveDir = moveDir + flatForward
  if isKeyDown(KeyboardKey.S):
    moveDir = moveDir - flatForward
  if isKeyDown(KeyboardKey.D):
    moveDir = moveDir + flatRight
  if isKeyDown(KeyboardKey.A):
    moveDir = moveDir - flatRight

  # Normalize and apply speed
  if moveDir.length() > 0:
    moveDir = moveDir.normalize()
    let speed = if isKeyDown(KeyboardKey.LeftShift):
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
  if player.canJump and isKeyPressed(KeyboardKey.Space) and player.jumpsRemaining > 0:
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
