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
    
  Projectile3D* = object
    pos*: Vector3f
    vel*: Vector3f
    damage*: float32
    lifetime*: float32
    fromPlayer*: bool
    active*: bool
    
  Arena3D* = object
    radius*: float32
    platforms*: seq[Platform3D]
    skyColor*: Color
    floorColor*: Color
    wallColor*: Color

  BossSatellite* = object
    pos*: Vector3f
    angle*: float32
    distance*: float32
    health*: float32
    active*: bool
    
  Boss3D* = object
    pos*: Vector3f
    health*: float32
    maxHealth*: float32
    phase*: int
    attackTimer*: float32
    satellites*: seq[BossSatellite]
    moveTimer*: float32
