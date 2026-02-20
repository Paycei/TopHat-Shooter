## 3D Engine Core Module
## Handles camera, physics, rendering, and arena generation

import raylib, math
import types_3d

export Vector3f, FPSCamera, Platform3D, Projectile3D, Arena3D
export BossSatellite, Boss3D

proc vec3*(x, y, z: float32): Vector3f =
  Vector3f(x: x, y: y, z: z)

proc `+`*(a, b: Vector3f): Vector3f =
  vec3(a.x + b.x, a.y + b.y, a.z + b.z)

proc `-`*(a, b: Vector3f): Vector3f =
  vec3(a.x - b.x, a.y - b.y, a.z - b.z)

proc `*`*(v: Vector3f, s: float32): Vector3f =
  vec3(v.x * s, v.y * s, v.z * s)

proc `/`*(v: Vector3f, s: float32): Vector3f =
  vec3(v.x / s, v.y / s, v.z / s)

proc length*(v: Vector3f): float32 =
  sqrt(v.x * v.x + v.y * v.y + v.z * v.z)

proc normalize*(v: Vector3f): Vector3f =
  let len = v.length()
  if len > 0: vec3(v.x / len, v.y / len, v.z / len)
  else: vec3(0, 0, 0)

proc distance*(a, b: Vector3f): float32 =
  (b - a).length()

proc dot*(a, b: Vector3f): float32 =
  a.x * b.x + a.y * b.y + a.z * b.z

proc cross*(a, b: Vector3f): Vector3f =
  vec3(
    a.y * b.z - a.z * b.y,
    a.z * b.x - a.x * b.z,
    a.x * b.y - a.y * b.x
  )

proc initCamera3D*(pos: Vector3f): FPSCamera =
  FPSCamera(
    position: pos,
    target: pos + vec3(0, 0, -1),
    up: vec3(0, 1, 0),
    fovy: 60.0,
    yaw: 0.0,
    pitch: 0.0,
    shake: 0.0,
    shakeTime: 0.0
  )

proc updateCamera*(cam: var FPSCamera, mouseDelta: Vector2, sensitivity: float32) =
  # Update yaw (horizontal) - unlimited rotation
  cam.yaw += mouseDelta.x * sensitivity
  
  # Update pitch (vertical) - clamped to prevent gimbal lock
  cam.pitch -= mouseDelta.y * sensitivity
  
  # Clamp pitch to -89.9 to 89.9 degrees
  if cam.pitch > 89.9:
    cam.pitch = 89.9
  elif cam.pitch < -89.9:
    cam.pitch = -89.9
  
  # Update shake
  if cam.shakeTime > 0:
    cam.shakeTime -= getFrameTime()
    cam.shake = cam.shakeTime * 10.0
  else:
    cam.shake = 0

proc getForward*(cam: FPSCamera): Vector3f =
  # Convert to radians
  let yawRad = degToRad(cam.yaw)
  let pitchRad = degToRad(cam.pitch)
  
  # Standard FPS forward vector
  result.x = cos(yawRad) * cos(pitchRad)
  result.y = sin(pitchRad)
  result.z = sin(yawRad) * cos(pitchRad)

proc getRight*(cam: FPSCamera): Vector3f =
  # Convert to radians
  let yawRad = degToRad(cam.yaw)
  
  # Right vector is perpendicular to forward on XZ plane
  result.x = -sin(yawRad)
  result.y = 0.0
  result.z = cos(yawRad)

proc addShake*(cam: var FPSCamera, intensity: float32) =
  cam.shakeTime = intensity

const GRAVITY* = -20.0

proc checkGroundCollision*(pos: Vector3f, platforms: seq[Platform3D]): bool =
  for platform in platforms:
    let dx = abs(pos.x - platform.pos.x)
    let dz = abs(pos.z - platform.pos.z)
    let dy = abs(pos.y - platform.pos.y)
    
    if dx < platform.size.x and dz < platform.size.z and dy < 2.0:
      return true
  false

proc checkCollision*(pos: Vector3f, radius: float32, platforms: seq[Platform3D]): (bool, Platform3D) =
  for platform in platforms:
    let dx = abs(pos.x - platform.pos.x)
    let dz = abs(pos.z - platform.pos.z)
    let dy = pos.y - platform.pos.y
    
    if dx < platform.size.x + radius and dz < platform.size.z + radius and
       dy > 0 and dy < platform.size.y + 1.0:
      return (true, platform)
  (false, Platform3D())

proc sphereVsSphere*(pos1: Vector3f, r1: float32, pos2: Vector3f, r2: float32): bool =
  distance(pos1, pos2) < r1 + r2

proc generateArena*(theme: string, radius: float32): Arena3D =
  result.radius = radius
  result.platforms = @[]
  
  case theme
  of "space":  # Boss #7 theme
    result.skyColor = Color(r: 5, g: 5, b: 20, a: 255)
    result.floorColor = Color(r: 20, g: 20, b: 40, a: 255)
    result.wallColor = Color(r: 50, g: 50, b: 100, a: 255)
    
    # Ground ring
    for i in 0..<8:
      let angle = i.float32 * 2.0 * PI / 8.0
      result.platforms.add(Platform3D(
        pos: vec3(cos(angle) * 200, 0, sin(angle) * 200),
        size: vec3(50, 2, 50),
        color: Color(r: 100, g: 100, b: 150, a: 255),
        moving: false,
        movePath: @[],
        pathIndex: 0,
        moveSpeed: 0.0,
        jumpPad: false,
        jumpForce: 0.0,
        rotationSpeed: 0.3,  # Will spin in phase 3+
        currentRotation: 0.0
      ))
    
    # Mid platforms
    for i in 0..<6:
      let angle = i.float32 * 2.0 * PI / 6.0
      result.platforms.add(Platform3D(
        pos: vec3(cos(angle) * 150, 30, sin(angle) * 150),
        size: vec3(30, 2, 30),
        color: Color(r: 120, g: 120, b: 180, a: 255),
        moving: false,
        movePath: @[],
        pathIndex: 0,
        moveSpeed: 0.0,
        jumpPad: false,
        jumpForce: 0.0,
        rotationSpeed: 0.5,  # Will spin in phase 3+
        currentRotation: 0.0
      ))
    
    # High orbital platforms (moving)
    for i in 0..<4:
      let angle = i.float32 * 2.0 * PI / 4.0
      result.platforms.add(Platform3D(
        pos: vec3(cos(angle) * 250, 60, sin(angle) * 250),
        size: vec3(25, 2, 25),
        color: Color(r: 150, g: 100, b: 255, a: 255),
        moving: true,
        movePath: @[],
        pathIndex: 0,
        moveSpeed: 0.3,
        jumpPad: false,
        jumpForce: 0.0,
        rotationSpeed: 0.0,
        currentRotation: 0.0
      ))
    
    # Central jump pad
    result.platforms.add(Platform3D(
      pos: vec3(0, 5, 0),
      size: vec3(40, 1, 40),
      color: Color(r: 0, g: 255, b: 0, a: 255),
      moving: false,
      movePath: @[],
      pathIndex: 0,
      moveSpeed: 0.0,
      jumpPad: true,
      jumpForce: 800.0,
      rotationSpeed: 0.0,
      currentRotation: 0.0
    ))
  
  else:  # Default arena
    result.skyColor = Color(r: 20, g: 30, b: 40, a: 255)
    result.floorColor = Color(r: 40, g: 40, b: 40, a: 255)
    result.wallColor = Color(r: 60, g: 60, b: 60, a: 255)
    
    # Simple platform layout
    for i in 0..<12:
      let angle = i.float32 * 2.0 * PI / 12.0
      let dist = 100.0 + (i mod 3).float32 * 50.0
      let height = (i mod 3).float32 * 20.0
      
      result.platforms.add(Platform3D(
        pos: vec3(cos(angle) * dist, height, sin(angle) * dist),
        size: vec3(30, 2, 30),
        color: Color(r: 80, g: 80, b: 80, a: 255),
        moving: false,
        movePath: @[],
        pathIndex: 0,
        moveSpeed: 0.0,
        jumpPad: false,
        jumpForce: 0.0,
        rotationSpeed: 0.0,
        currentRotation: 0.0
      ))
  
  result.environmentIntensity = 0.0

proc updatePlatforms*(platforms: var seq[Platform3D], dt: float32) =
  for platform in platforms.mitems:
    if platform.moving:
      # Simple circular orbit
      let speed = platform.moveSpeed * dt
      let currentAngle = arctan2(platform.pos.z, platform.pos.x)
      let radius = sqrt(platform.pos.x * platform.pos.x + platform.pos.z * platform.pos.z)
      let newAngle = currentAngle + speed
      
      platform.pos.x = cos(newAngle) * radius
      platform.pos.z = sin(newAngle) * radius
    
    # Update rotation
    if platform.rotationSpeed != 0.0:
      platform.currentRotation += platform.rotationSpeed * dt
      if platform.currentRotation > 2.0 * PI:
        platform.currentRotation -= 2.0 * PI

# RENDERING

proc drawArena*(arena: Arena3D) =
  # Draw sky
  clearBackground(arena.skyColor)
  
  # Draw floor
  drawCube(Vector3(x: 0, y: -10, z: 0),
          arena.radius * 4, 1.0, arena.radius * 4,
          arena.floorColor)
  
  # Draw walls
  drawCylinderWires(Vector3(x: 0, y: 50, z: 0),
                   arena.radius, arena.radius, 100.0, 32,
                   arena.wallColor)

proc drawPlatform*(platform: Platform3D) =
  drawCube(Vector3(x: platform.pos.x, y: platform.pos.y, z: platform.pos.z),
          platform.size.x * 2, platform.size.y * 2, platform.size.z * 2,
          platform.color)
  
  # Draw edge glow
  drawCubeWires(Vector3(x: platform.pos.x, y: platform.pos.y, z: platform.pos.z),
               platform.size.x * 2, platform.size.y * 2, platform.size.z * 2,
               White)
  
  # Jump pad indicator
  if platform.jumpPad:
    let t = getTime() * 3.0
    let glow = (sin(t) * 0.5 + 0.5).float32
    drawCylinder(Vector3(x: platform.pos.x, y: platform.pos.y + 3, z: platform.pos.z),
                0.5, 0.5, 2.0, 8,
                Color(r: 0, g: uint8(255.0 * glow), b: 0, a: 200))

proc drawProjectile*(proj: Projectile3D) =
  let color = if proj.fromPlayer: Yellow else: Red
  drawSphere(Vector3(x: proj.pos.x, y: proj.pos.y, z: proj.pos.z), 1.5, color)
  
  # Trail effect
  drawSphere(Vector3(x: proj.pos.x - proj.vel.x * 0.05,
                    y: proj.pos.y - proj.vel.y * 0.05,
                    z: proj.pos.z - proj.vel.z * 0.05),
            1.0, fade(color, 0.5))
