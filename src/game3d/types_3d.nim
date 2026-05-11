## 3D Types Module
## Contains all 3D-specific type definitions for the 3D engine

import raylib

type
  Vector3f* = object
    x*, y*, z*: float32

  FPSCamera* = object
    position*: Vector3f
    target*: Vector3f
    up*: Vector3f
    fovy*: float32
    yaw*, pitch*: float32
    shake*: float32
    shakeTime*: float32

  Platform3D* = object
    pos*: Vector3f
    size*: Vector3f
    color*: Color
    moving*: bool
    movePath*: seq[Vector3f]
    pathIndex*: int
    moveSpeed*: float32
    jumpPad*: bool
    jumpForce*: float32
    rotationSpeed*: float32  # For rotating platforms
    currentRotation*: float32

  Projectile3D* = object
    pos*: Vector3f
    vel*: Vector3f
    damage*: float32
    lifetime*: float32
    fromPlayer*: bool
    active*: bool
    isHoming*: bool  # For homing missiles
    homingTarget*: Vector3f
    homingStrength*: float32

  Arena3D* = object
    radius*: float32
    platforms*: seq[Platform3D]
    skyColor*: Color
    floorColor*: Color
    wallColor*: Color
    environmentIntensity*: float32  # For phase transitions

  GravityWell* = object
    pos*: Vector3f
    strength*: float32
    radius*: float32
    lifetime*: float32
    active*: bool

  BossSatellite* = object
    pos*: Vector3f
    angle*: float32
    distance*: float32
    health*: float32
    maxHealth*: float32
    active*: bool
    orbitSpeed*: float32  # Variable orbit speed per satellite
    laserChargeTimer*: float32  # For laser attacks
    targetSatelliteIndex*: int  # For inter-satellite lasers

  BossClone* = object
    pos*: Vector3f
    lifetime*: float32
    alpha*: float32

  Boss3D* = object
    pos*: Vector3f
    health*: float32
    maxHealth*: float32
    phase*: int
    attackTimer*: float32
    satellites*: seq[BossSatellite]
    moveTimer*: float32
    phaseTransitionTimer*: float32  # Brief invulnerability during phase changes
    attackPattern*: int  # Current attack pattern index
    patternTimer*: float32  # Timer for pattern rotation
    shieldActive*: bool  # For Phase 4 shield mechanic
    shieldHealth*: float32
    maxShieldHealth*: float32
    clones*: seq[BossClone]  # For Phase 4 afterimages
    teleportTimer*: float32
    gravityWells*: seq[GravityWell]
    berserkModeActive*: bool  # Phase 5 final stand

  DamageNumber3D* = object
    pos*: Vector3f
    vel*: Vector3f
    damage*: float32
    lifetime*: float32
    maxLifetime*: float32
    fromPlayer*: bool
    isCritical*: bool
