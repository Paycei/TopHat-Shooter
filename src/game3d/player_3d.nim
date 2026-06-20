## 3D Player Module
## Handles 3D player movement, shooting, and weapon systems

import raylib, math
import types_3d, engine_3d

type
  Weapon3D* = object
    ammo*: int
    maxAmmo*: int
    fireRate*: float32
    fireTimer*: float32
    damage*: float32

  Player3D* = object
    pos*: Vector3f
    vel*: Vector3f
    health*: float32
    maxHealth*: float32
    speed*: float32
    sprintMultiplier*: float32
    jumpForce*: float32
    canJump*: bool
    jumpsRemaining*: int
    maxJumps*: int
    weapon*: Weapon3D
    grounded*: bool

proc newWeapon3D*(): Weapon3D =
  Weapon3D(
    ammo: 500,        # Increased from 150 for longer fights
    maxAmmo: 500,     # Increased from 150 for longer fights
    fireRate: 0.125,
    fireTimer: 0.0,
    damage: 15.0
  )

proc updateWeapon*(player: var Player3D, dt: float32) =
  if player.weapon.fireTimer > 0:
    player.weapon.fireTimer -= dt

proc fireWeapon*(player: var Player3D, camera: FPSCamera, projectiles: var seq[Projectile3D]): bool =
  if player.weapon.ammo > 0 and player.weapon.fireTimer <= 0:
    player.weapon.ammo -= 1
    player.weapon.fireTimer = player.weapon.fireRate

    let forward = camera.getForward()
    let spawnPos = player.pos + vec3(0, 1.5, 0) + forward * 2.0

    projectiles.add(Projectile3D(
      pos: spawnPos,
      vel: forward * 600.0,
      damage: player.weapon.damage,
      lifetime: 3.0,
      fromPlayer: true,
      active: true
    ))
    return true
  false

proc reload*(player: var Player3D) =
  player.weapon.ammo = player.weapon.maxAmmo

proc newPlayer3D*(startPos: Vector3f, health2D: float32): Player3D =
  Player3D(
    pos: startPos,
    vel: vec3(0, 0, 0),
    health: health2D,    # Carry over health from 2D phase
    maxHealth: health2D, # Maintain same max health
    speed: 75.0,  # Balanced speed for 3D movement
    sprintMultiplier: 1.5,
    jumpForce: 50.0,
    canJump: true,
    jumpsRemaining: 2,
    maxJumps: 2,
    weapon: newWeapon3D(),
    grounded: false
  )

proc updatePlayer*(player: var Player3D, camera: FPSCamera, platforms: seq[Platform3D], dt: float32) =
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
  player.vel.y += GRAVITY * dt

  # Jumping
  if isKeyPressed(KeyboardKey.Space) and player.jumpsRemaining > 0:
    player.vel.y = player.jumpForce
    player.jumpsRemaining -= 1

  # Update position
  let nextPos = player.pos + player.vel * dt

  # Check platform collision
  let (collided, platform) = checkCollision(nextPos, 1.0, platforms)

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

  # Keep player in arena bounds
  let maxDist = 450.0
  let dist = sqrt(player.pos.x * player.pos.x + player.pos.z * player.pos.z)
  if dist > maxDist:
    let angle = arctan2(player.pos.z, player.pos.x)
    player.pos.x = cos(angle) * maxDist
    player.pos.z = sin(angle) * maxDist

  # Death plane
  if player.pos.y < -50:
    player.health = 0
