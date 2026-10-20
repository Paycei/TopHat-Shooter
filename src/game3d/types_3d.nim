## 3D Types Module
## Contains all 3D-specific type definitions for the 3D engine

import raylib
import ../vec
export vec

type
  FPSCamera* = object
    position*: Vector3
    target*: Vector3
    up*: Vector3
    fovy*: float32
    yaw*, pitch*: float32
    shake*: float32
    shakeTime*: float32

  Platform3D* = object
    pos*: Vector3
    size*: Vector3
    color*: Color
    moving*: bool
    moveSpeed*: float32
    jumpPad*: bool
    jumpForce*: float32
    rotationSpeed*: float32  # For rotating platforms
    currentRotation*: float32

  Projectile3D* = ref object
    pos*: Vector3
    vel*: Vector3
    damage*: float32
    lifetime*: float32
    fromPlayer*: bool
    active*: bool
    isHoming*: bool  # For homing missiles
    homingStrength*: float32
    radius*: float32      # 0 = the default 1.5 (hit and drawn size)
    color*: Color         # alpha 0 = the default (yellow player, red enemy)
    gravity*: float32     # multiplier on the arena's gravity (0 = flies straight)
    pierce*: int          # extra targets it passes through before it is spent
    ownerId*: int         # id of the entity that fired it (0 = the player, the boss or a script)
    tag*: string          # mod-chosen kind, for scripts
    hitIds*: seq[int]     # entities a piercing shot already hit
    removed*: bool        # swept out of the world (scripts holding it see "no longer exists")

  Arena3D* = object
    radius*: float32
    platforms*: seq[Platform3D]
    skyColor*: Color
    floorColor*: Color
    wallColor*: Color
    gravity*: float32               # world units/s^2 (negative pulls down)
    boundsRadius*: float32          # the player is kept inside this radius
    deathPlaneY*: float32           # falling below this kills the player
    drawFloor*, drawWalls*: bool
    solidFloor*: bool               # the plane y = floorY is landable (like a platform top)
    floorY*: float32

  GravityWell* = object
    pos*: Vector3
    strength*: float32
    radius*: float32
    lifetime*: float32
    active*: bool

  BossSatellite* = object
    pos*: Vector3
    angle*: float32
    distance*: float32
    health*: float32
    maxHealth*: float32
    active*: bool
    orbitSpeed*: float32  # Variable orbit speed per satellite

  Boss3D* = object
    pos*: Vector3
    health*: float32
    maxHealth*: float32
    phase*: int
    attackTimer*: float32
    satellites*: seq[BossSatellite]
    moveTimer*: float32
    phaseTransitionTimer*: float32  # Brief invulnerability during phase changes
    attackPattern*: int  # Current attack pattern index
    teleportTimer*: float32
    gravityWells*: seq[GravityWell]

  DamageNumber3D* = object
    pos*: Vector3
    vel*: Vector3
    damage*: float32
    lifetime*: float32
    maxLifetime*: float32
    fromPlayer*: bool
    isCritical*: bool
    color*: Color  # alpha 0 = the default yellow

  EntityShape3D* = enum
    esNone, esCube, esSphere, esCylinder, esModel

  EntityAI3D* = enum
    aiNone, aiChase, aiOrbit, aiWander, aiTurret

  Entity3D* = ref object
    ## A generic thing in the world: an enemy, a target, a prop. Plain data
    ## only: scripts keep their own state in tables keyed by `id`.
    id*: int
    tag*: string           # mod-chosen kind
    pos*, vel*: Vector3
    yaw*: float32          # degrees, about the up axis
    hp*, maxHp*: float32
    radius*: float32       # hit and contact radius
    color*: Color
    shape*: EntityShape3D
    size*: Vector3        # esCube: full extents; esCylinder: y = height
    modelId*: int          # mod_assets model id (esModel); -1 none
    modelScale*: float32
    modelAnim*: int        # animation index + 1; 0 = the rest pose
    modelSpeed*: float32
    modelFade*: float32    # seconds a modelAnim change crossfades; 0 snaps
    ai*: EntityAI3D
    speed*: float32
    orbitRadius*: float32  # aiOrbit: distance kept from the player
    range*: float32        # shooters: 0 = unlimited
    contactDamage*: float32
    contactTimer*: float32 # seconds until the next contact hit
    fireInterval*: float32 # seconds between shots (0 = never)
    fireTimer*: float32
    projectileSpeed*: float32
    projectileDamage*: float32
    scoreValue*: int       # added to the world's score when it dies
    gravity*: bool
    solid*: bool           # pushes the player out of its way
    invulnerable*: bool    # takes hits without losing hp
    alive*: bool
    age*: float32
    wanderDir*: Vector3   # aiWander heading
    wanderTimer*: float32
    removed*: bool         # swept out of the world (or removed before it joined): gone for scripts

  Pickup3D* = ref object
    id*: int
    pos*: Vector3
    kind*: string          # "health", "ammo" or a mod-chosen tag
    value*: float32
    radius*: float32
    color*: Color          # alpha 0 = the kind's default
    alive*: bool
    age*: float32
    removed*: bool         # swept out of the world: gone for scripts

  Weapon3D* = object
    ammo*: int
    maxAmmo*: int
    fireRate*: float32
    fireTimer*: float32
    damage*: float32
    projectileSpeed*: float32
    spread*: float32            # cone half-angle in degrees
    pellets*: int               # projectiles per shot
    projectileRadius*: float32  # 0 = the default
    projectileColor*: Color     # alpha 0 = the default
    automatic*: bool            # holding the button keeps firing
    reloadTime*: float32        # seconds, 0 = instant
    reloadTimer*: float32       # > 0 while reloading
    infiniteAmmo*: bool

  Player3D* = object
    pos*: Vector3
    vel*: Vector3
    health*: float32
    maxHealth*: float32
    speed*: float32
    sprintMultiplier*: float32
    jumpForce*: float32
    jumpsRemaining*: int
    maxJumps*: int
    weapon*: Weapon3D
    grounded*: bool
    radius*: float32            # body radius against enemy shots and entities
    invulnTimer*: float32       # damage is ignored while > 0
    hitInvuln*: float32         # invulnerability after a hit (0 = none)
    canJump*: bool
    gravityScale*: float32

  World3DResult* = enum
    w3None = "none", w3Won = "won", w3Lost = "lost", w3Exit = "exit"

  World3DRules* = object
    exitOnBossDeath*: bool      # a dead boss ends the world as won
    exitOnPlayerDeath*: bool    # a dead player ends the world as lost
    timeLimit*: float32         # seconds, 0 = none
    timeLimitWins*: bool        # the limit ends the world as won instead of lost
    allowReload*: bool
    autoFire*: bool             # the weapon fires by itself whenever it can
    mouseSensitivity*: float32

  World3DOptions* = object
    ## How a world is entered (game.nim: enterWorld3D / beginEnter3D).
    bossEnabled*: bool
    bossId*: int
    modeKey*: string            # the mod game mode that opened it; "" = vanilla
    carryHp*: bool              # start from the 2D player's HP and hand it back
    resumed*: bool              # a saved run re-entering 3D

  Game3D* = ref object
    active*: bool
    result*: World3DResult
    pendingResult*: World3DResult  # a finish requested by a script; applied at the end of the frame
    quitRequested*: bool        # the pause overlay's "quit to desktop"
    arena*: Arena3D
    camera*: FPSCamera
    player*: Player3D
    boss*: Boss3D
    bossEnabled*: bool          # the vanilla Orbital Commander fight
    bossId*: int
    projectiles*: seq[Projectile3D]
    entities*: seq[Entity3D]
    pickups*: seq[Pickup3D]
    damageNumbers*: seq[DamageNumber3D]
    rules*: World3DRules
    modeKey*: string
    resumed*: bool
    carryHp*: bool
    startFired*: bool           # world3dStart has fired
    spawnPos*: Vector3
    timeElapsed*: float32
    paused*: bool
    score*, kills*, wave*: int  # counters scripts may use
    nextId*: int

# Like types.nim's Enemy/Bullet list iterators: yield copies, re-check the
# length, so a script growing or shrinking a world's lists mid-walk is safe.
iterator items*(a: seq[Entity3D]): Entity3D {.inline.} =
  let n = a.len
  var i = 0
  while i < n and i < a.len:
    yield a[i]
    inc i

iterator pairs*(a: seq[Entity3D]): tuple[key: int, val: Entity3D] {.inline.} =
  let n = a.len
  var i = 0
  while i < n and i < a.len:
    yield (i, a[i])
    inc i

iterator items*(a: seq[Projectile3D]): Projectile3D {.inline.} =
  let n = a.len
  var i = 0
  while i < n and i < a.len:
    yield a[i]
    inc i

iterator pairs*(a: seq[Projectile3D]): tuple[key: int, val: Projectile3D] {.inline.} =
  let n = a.len
  var i = 0
  while i < n and i < a.len:
    yield (i, a[i])
    inc i

iterator items*(a: seq[Pickup3D]): Pickup3D {.inline.} =
  let n = a.len
  var i = 0
  while i < n and i < a.len:
    yield a[i]
    inc i

iterator pairs*(a: seq[Pickup3D]): tuple[key: int, val: Pickup3D] {.inline.} =
  let n = a.len
  var i = 0
  while i < n and i < a.len:
    yield (i, a[i])
    inc i

var activeWorld3D*: Game3D
  ## The 3D world in play (nil outside one). Game.game3D only marks that a
  ## world exists; this global holds the reference so low modules can reach it.

var pendingWorld3D*: World3DOptions
  ## What the fade to black in progress (Game.transitioning) enters when it
  ## completes; set by whoever starts the fade (sandbox.nim's button, beginEnter3D).

const
  MaxDamageNumbers3D* = 300  ## floating numbers on screen at once (the oldest go first)
  MaxPellets3D* = 1000       ## shots per trigger pull: a script's weapon.pellets = 1e9 must not hang the frame
