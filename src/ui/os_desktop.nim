## OS-Themed Desktop Environment Module
## Main menu as an operating system desktop

import raylib, rlgl, math, strutils, strformat, times
import ../types, ../localization, ../render_context, background_fx, ../desktop_bg_skins, desktop_bg_fx, ../settings, ../save_system, ../cube_skins, ../particle_types, ../utils

type
  DesktopIconType* = enum
    diPlay          # Launch game (Play.exe) - 0
    diSurvival      # Survival mode (Survival.exe) - 1
    diStatistics    # Statistics viewer (Stats.exe) - 2
    diSettings      # Settings panel (Settings.exe) - 3
    diShop          # Customization Shop (Shop.exe) - 4
    diHelp          # Help/Documentation (Help.txt) - 5
    diQuit          # Shutdown (Shutdown.exe) - 6
    diSandbox       # Sandbox mode (Sandbox.exe) - 7
    diPvP           # PvP mode (PvP.exe) - 8
    diRoguelite     # Roguelite mode (Roguelite.exe) - 9
    diAdvancements  # Persistent advancement viewer (Advncmnts.exe) - 10
    diChangelog     # Patch notes / changelog viewer (PATCHLOG.txt) - 11
    diCredits       # Credits + support the project (CREDITS.nfo) - 12

  DesktopIcon* = object
    iconType*: DesktopIconType
    x*, y*: int
    selected*: bool
    name*: string
    iconColor*: Color

  WindowState* = ref object
    opened*: bool
    x*, y*: int
    width*, height*: int
    title*: string
    minimized*: bool

  DesktopToast* = object
    text*: string
    timer*: float32

  OSDesktop* = ref object
    icons*: seq[DesktopIcon]
    selectedIcon*: int
    time*: float32
    taskbarHeight*: int
    windows*: seq[WindowState]
    showCursor*: bool
    mousePos*: Vector2
    loadingActive*: bool
    loadingProgress*: float32
    loadingText*: string
    # Cube interactive rotation state (quaternion: w, x, y, z)
    cubeQW*: float32
    cubeQX*: float32
    cubeQY*: float32
    cubeQZ*: float32
    cubeAngVelX*: float32  # world-space angular velocity (view X axis = pitch)
    cubeAngVelY*: float32  # world-space angular velocity (view Y axis = yaw)
    cubeDragging*: bool
    cubeDragLastX*: float32
    cubeDragLastY*: float32
    # Cached Euler angles (radians) derived from quaternion for wallpaper rendering
    cubeRotX*: float32
    cubeRotY*: float32
    cubeRotZ*: float32
    # Orbital-escape easter egg: sustained fast spinning knocks the cube out of orbit
    cubeEscapeArmed*: bool      # set by main while the advancement is still locked
    cubeEscapeTriggered*: bool  # one-shot flag consumed by main to grant the advancement
    cubeSpinHeat*: float32      # seconds of sustained fast spin accumulated so far
    cubeEscaping*: bool
    cubeEscapeTimer*: float32
    cubeEscapeDirX*: float32
    cubeEscapeDirY*: float32
    cubeOffsetX*: float32       # render offset of the cube from its orbit slot
    cubeOffsetY*: float32
    cubePortalMode*: bool       # escape routes through the portal background portals
    cubePortalEnterRight*: bool # true = enter orange (right), exit blue (left)
    # Dice-roll easter egg: on the poker table with the dice skin, the escape
    # becomes a die drop that settles on a random face and reports the number.
    cubeDiceMode*: bool         # escape is a dice roll; also holds the cube still at rest after
    cubeDiceResult*: int        # rolled face value (1..6)
    cubeDiceTQW*: float32       # target orientation quaternion (result face -> camera)
    cubeDiceTQX*: float32
    cubeDiceTQY*: float32
    cubeDiceTQZ*: float32
    cubeDiceResultTimer*: float32  # seconds left to show the big result number
    cubeDiceVelY*: float32      # vertical velocity of the die during the bounce drop
    cubeDiceSpinX*: float32     # per-axis angular velocity while tumbling (rad/s)
    cubeDiceSpinY*: float32
    cubeDiceSpinZ*: float32
    # Kernel Panic + Jack-O'-Node: fast spinning fans the candle (0..1 glow boost)
    # instead of breaking orbit; decays back when the player stops spinning.
    cubeJackGlow*: float32
    # Transient OS-style toasts (stacked)
    toasts*: seq[DesktopToast]

var
  activeDesktop*: OSDesktop = nil

const
  ICON_SIZE = 64
  ICON_SPACING = 100
  TASKBAR_HEIGHT = 40
  MAX_DESKTOP_TOASTS* = 5
  DESKTOP_GRID_START_X = 80
  DESKTOP_GRID_START_Y = 80
  ICON_LABEL_WIDTH = 88
  ICON_LABEL_FONT_SIZE = 14
  ICON_LABEL_MIN_SIZE = 9

proc getIconName(iconType: DesktopIconType): string =
  ## Get the localized name for a desktop icon
  case iconType
  of diPlay: t(tkDesktopIconPlay)
  of diSurvival: t(tkDesktopIconSurvival)
  of diStatistics: t(tkDesktopIconStats)
  of diSettings: t(tkDesktopIconSettings)
  of diHelp: t(tkDesktopIconHelp)
  of diQuit: t(tkDesktopIconQuit)
  of diSandbox: t(tkDesktopIconSandbox)
  of diShop: t(tkDesktopIconShop)
  of diPvP: t(tkDesktopIconPvP)
  of diRoguelite: t(tkDesktopIconRoguelite)
  of diAdvancements: t(tkDesktopIconAdvancements)
  of diChangelog: t(tkDesktopIconChangelog)
  of diCredits: t(tkDesktopIconCredits)

proc bestDesktopLabelFontSize(text: string, maxWidth, preferredSize: int32,
                              minSize: int32 = ICON_LABEL_MIN_SIZE): int32 =
  result = preferredSize
  if maxWidth <= 0:
    return
  while result > minSize and measureText(text, result) > maxWidth:
    dec result

proc drawDesktopLabel(text: string, x, y: int32, selected: bool) =
  let fontSize = bestDesktopLabelFontSize(text, ICON_LABEL_WIDTH, ICON_LABEL_FONT_SIZE)
  let labelX = x - ((ICON_LABEL_WIDTH - ICON_SIZE) div 2)
  let shadowColor = Color(r: 0, g: 0, b: 0, a: if selected: 235 else: 180)
  let textColor = if selected: Color(r: 220, g: 248, b: 255, a: 255) else: White
  let lineWidth = measureText(text, fontSize)
  let drawX = labelX + max(0'i32, (ICON_LABEL_WIDTH - lineWidth) div 2)
  drawText(text, drawX + 2, y + 2, fontSize, shadowColor)
  drawText(text, drawX, y, fontSize, textColor)

proc newOSDesktop*(): OSDesktop =
  result = OSDesktop(
    icons: @[
      DesktopIcon(iconType: diPlay, x: DESKTOP_GRID_START_X, y: DESKTOP_GRID_START_Y,
                  selected: true, name: getIconName(diPlay),
                  iconColor: Color(r: 100, g: 200, b: 255, a: 255)),
      DesktopIcon(iconType: diRoguelite, x: DESKTOP_GRID_START_X, y: DESKTOP_GRID_START_Y + ICON_SPACING,
                  selected: false, name: getIconName(diRoguelite),
                  iconColor: Color(r: 0, g: 220, b: 180, a: 255)),
      DesktopIcon(iconType: diSurvival, x: DESKTOP_GRID_START_X, y: DESKTOP_GRID_START_Y + ICON_SPACING * 2,
                  selected: false, name: getIconName(diSurvival),
                  iconColor: Color(r: 255, g: 150, b: 100, a: 255)),
      DesktopIcon(iconType: diStatistics, x: DESKTOP_GRID_START_X, y: DESKTOP_GRID_START_Y + ICON_SPACING * 3,
                  selected: false, name: getIconName(diStatistics),
                  iconColor: Color(r: 255, g: 200, b: 50, a: 255)),
      DesktopIcon(iconType: diSettings, x: DESKTOP_GRID_START_X, y: DESKTOP_GRID_START_Y + ICON_SPACING * 4,
                  selected: false, name: getIconName(diSettings),
                  iconColor: Color(r: 200, g: 100, b: 255, a: 255)),
      DesktopIcon(iconType: diHelp, x: DESKTOP_GRID_START_X, y: DESKTOP_GRID_START_Y + ICON_SPACING * 5,
                  selected: false, name: getIconName(diHelp),
                  iconColor: Color(r: 100, g: 255, b: 150, a: 255)),
      DesktopIcon(iconType: diSandbox, x: DESKTOP_GRID_START_X + ICON_SPACING, y: DESKTOP_GRID_START_Y,
                  selected: false, name: getIconName(diSandbox),
                  iconColor: Color(r: 255, g: 165, b: 0, a: 255)),
      DesktopIcon(iconType: diShop, x: DESKTOP_GRID_START_X + ICON_SPACING, y: DESKTOP_GRID_START_Y + ICON_SPACING,
                  selected: false, name: getIconName(diShop),
                  iconColor: Color(r: 255, g: 150, b: 50, a: 255)),
      DesktopIcon(iconType: diPvP, x: DESKTOP_GRID_START_X + ICON_SPACING, y: DESKTOP_GRID_START_Y + ICON_SPACING * 2,
                  selected: false, name: getIconName(diPvP),
                  iconColor: Color(r: 255, g: 50, b: 150, a: 255)),
      DesktopIcon(iconType: diAdvancements, x: DESKTOP_GRID_START_X + ICON_SPACING, y: DESKTOP_GRID_START_Y + ICON_SPACING * 3,
                  selected: false, name: getIconName(diAdvancements),
                  iconColor: Color(r: 90, g: 220, b: 255, a: 255)),
      DesktopIcon(iconType: diChangelog, x: DESKTOP_GRID_START_X + ICON_SPACING, y: DESKTOP_GRID_START_Y + ICON_SPACING * 4,
                  selected: false, name: getIconName(diChangelog),
                  iconColor: Color(r: 255, g: 180, b: 80, a: 255)),
      DesktopIcon(iconType: diQuit, x: DESKTOP_GRID_START_X + ICON_SPACING, y: DESKTOP_GRID_START_Y + ICON_SPACING * 5,
                  selected: false, name: getIconName(diQuit),
                  iconColor: Color(r: 255, g: 100, b: 100, a: 255)),
      # Third column: the two full columns above are already as tall as the
      # desktop allows (a 7th row would collide with the taskbar).
      DesktopIcon(iconType: diCredits, x: DESKTOP_GRID_START_X + ICON_SPACING * 2, y: DESKTOP_GRID_START_Y,
                  selected: false, name: getIconName(diCredits),
                  iconColor: Color(r: 255, g: 110, b: 160, a: 255))
    ],
    selectedIcon: 0,
    time: 0,
    taskbarHeight: TASKBAR_HEIGHT,
    windows: @[],
    showCursor: true,
    loadingActive: false,
    loadingProgress: 0.0,
    loadingText: "",
    # Start with identity quaternion, auto-rotation will spin it from here
    cubeQW: 1.0,
    cubeQX: 0.0,
    cubeQY: 0.0,
    cubeQZ: 0.0,
    cubeAngVelX: 0.0,
    cubeAngVelY: 0.0,
    cubeDragging: false,
    cubeDragLastX: 0.0,
    cubeDragLastY: 0.0,
    cubeRotX: 0.0,
    cubeRotY: 0.0,
    cubeRotZ: 0.0,
    cubeEscapeArmed: false,
    cubeEscapeTriggered: false,
    cubeSpinHeat: 0.0,
    cubeEscaping: false,
    cubeEscapeTimer: 0.0,
    cubeEscapeDirX: 0.0,
    cubeEscapeDirY: 0.0,
    cubeOffsetX: 0.0,
    cubeOffsetY: 0.0,
    cubePortalMode: false,
    cubePortalEnterRight: false,
    cubeDiceMode: false,
    cubeDiceResult: 0,
    cubeDiceTQW: 1.0,
    cubeDiceTQX: 0.0,
    cubeDiceTQY: 0.0,
    cubeDiceTQZ: 0.0,
    cubeDiceResultTimer: 0.0,
    cubeDiceVelY: 0.0,
    cubeDiceSpinX: 0.0,
    cubeDiceSpinY: 0.0,
    cubeDiceSpinZ: 0.0,
    cubeJackGlow: 0.0,
    toasts: @[]
  )

proc showDesktopToast*(desktop: OSDesktop, text: string)

proc diceTargetQuat(face: int): (float32, float32, float32, float32) =
  ## Quaternion (w,x,y,z) that turns the die so the given `face` value points at
  ## the camera (+z). Built as the minimal rotation taking that face's model
  ## normal to +z; matches the pip mapping in drawZeroGravityWallpaperCube
  ## (1:+z 6:-z 2:+x 5:-x 3:+y 4:-y). Identity for 1, 180° about X for 6.
  var nx, ny, nz: float32 = 0.0'f32
  case face
  of 1: nz = 1.0'f32
  of 6: nz = -1.0'f32
  of 2: nx = 1.0'f32
  of 5: nx = -1.0'f32
  of 3: ny = 1.0'f32
  else: ny = -1.0'f32        # 4
  if nz > 0.999'f32: return (1.0'f32, 0.0'f32, 0.0'f32, 0.0'f32)
  if nz < -0.999'f32: return (0.0'f32, 1.0'f32, 0.0'f32, 0.0'f32)
  # axis = normalize(N x (0,0,1)) = normalize((ny, -nx, 0))
  let al = sqrt(ny*ny + nx*nx)
  let ax = ny / al
  let ay = -nx / al
  let angle = arccos(clamp(nz, -1.0'f32, 1.0'f32))
  let sh = sin(angle * 0.5'f32)
  (cos(angle * 0.5'f32), ax * sh, ay * sh, 0.0'f32)

proc d20TargetQuat(face: int): (float32, float32, float32, float32) =
  ## Quaternion (w,x,y,z) that rotates the D20 so `face` value (1..20) points at
  ## the camera (+z). Each normal is the normalized centroid of the three icosahedron
  ## vertices for that face (derived from D20Verts/D20Faces/D20FaceNumbers).
  ## Opposite faces sum to 21 and have antipodal normals. Same rotation formula
  ## as diceTargetQuat: minimal arc from the face's outward normal to +z.
  const
    A = 0.35682'f32  # 1 / |centroid-sum vector| for all 20 faces
    B = 0.93418'f32  # (2 + phi_inv) / |centroid-sum vector|
    C = 0.57735'f32  # 1 / sqrt(3)
  var nx, ny, nz: float32
  case face
  of  1: nx = -C; ny =  C; nz =  C
  of  2: nx =  0; ny =  B; nz =  A
  of  3: nx =  0; ny =  B; nz = -A
  of  4: nx = -C; ny =  C; nz = -C
  of  5: nx = -B; ny =  A; nz =  0
  of  6: nx =  C; ny =  C; nz =  C
  of  7: nx = -A; ny =  0; nz =  B
  of  8: nx = -B; ny = -A; nz =  0
  of  9: nx = -A; ny =  0; nz = -B
  of 10: nx =  C; ny =  C; nz = -C
  of 11: nx = -C; ny = -C; nz =  C
  of 12: nx =  A; ny =  0; nz =  B
  of 13: nx =  B; ny =  A; nz =  0
  of 14: nx =  A; ny =  0; nz = -B
  of 15: nx = -C; ny = -C; nz = -C
  of 16: nx =  B; ny = -A; nz =  0
  of 17: nx =  C; ny = -C; nz =  C
  of 18: nx =  0; ny = -B; nz =  A
  of 19: nx =  0; ny = -B; nz = -A
  else:  nx =  C; ny = -C; nz = -C  # 20
  if nz > 0.999'f32: return (1.0'f32, 0.0'f32, 0.0'f32, 0.0'f32)
  if nz < -0.999'f32: return (0.0'f32, 1.0'f32, 0.0'f32, 0.0'f32)
  let al = sqrt(ny * ny + nx * nx)
  let ax = ny / al
  let ay = -nx / al
  let angle = arccos(clamp(nz, -1.0'f32, 1.0'f32))
  let sh = sin(angle * 0.5'f32)
  (cos(angle * 0.5'f32), ax * sh, ay * sh, 0.0'f32)

proc faceUpFromQuat(qw, qx, qy, qz: float32; isD20: bool): (int, float32, float32, float32, float32) =
  ## Camera direction in model space = third row of the rotation matrix from q.
  ## The face whose outward normal has the highest dot with that direction is the
  ## face pointing toward the camera (i.e. the face that landed up).
  ## Returns (faceNumber, targetQW, targetQX, targetQY, targetQZ).
  let camX = 2.0'f32 * (qx * qz - qw * qy)
  let camY = 2.0'f32 * (qy * qz + qw * qx)
  let camZ = 1.0'f32 - 2.0'f32 * (qx * qx + qy * qy)
  if isD20:
    const
      A = 0.35682'f32
      B = 0.93418'f32
      C = 0.57735'f32
      # Face normals for faces 1-20 in order (mirrors d20TargetQuat)
      dnx: array[20, float32] = [
        -C, 0.0'f32, 0.0'f32, -C, -B,  C, -A, -B, -A,  C,
        -C,       A,       B,  A, -C,  B,  C, 0.0'f32, 0.0'f32,  C]
      dny: array[20, float32] = [
         C,       B,       B,  C,  A,  C, 0.0'f32, -A, 0.0'f32,  C,
        -C, 0.0'f32,       A, 0.0'f32, -C, -A, -C,      -B,      -B, -C]
      dnz: array[20, float32] = [
         C,       A,      -A, -C, 0.0'f32,  C,  B, 0.0'f32, -B, -C,
         C,       B, 0.0'f32, -B, -C, 0.0'f32,  C,       A,      -A, -C]
    var best = -2.0'f32
    var bestFace = 1
    for i in 0..19:
      let s = dnx[i] * camX + dny[i] * camY + dnz[i] * camZ
      if s > best:
        best = s
        bestFace = i + 1
    let (tw, tx, ty, tz) = d20TargetQuat(bestFace)
    (bestFace, tw, tx, ty, tz)
  else:
    # Pip mapping: 1:+Z  6:-Z  2:+X  5:-X  3:+Y  4:-Y  (see diceTargetQuat)
    var best = camZ
    var bestFace = 1
    if -camZ > best: best = -camZ; bestFace = 6
    if  camX > best: best =  camX; bestFace = 2
    if -camX > best: best = -camX; bestFace = 5
    if  camY > best: best =  camY; bestFace = 3
    if -camY > best: best = -camY; bestFace = 4
    let (tw, tx, ty, tz) = diceTargetQuat(bestFace)
    (bestFace, tw, tx, ty, tz)

proc nlerpToward(qw, qx, qy, qz: var float32, tw, tx, ty, tz, t: float32) =
  ## Normalized lerp of the cube quaternion toward a target, along the short arc.
  var bw = tw; var bx = tx; var by = ty; var bz = tz
  if qw*bw + qx*bx + qy*by + qz*bz < 0.0'f32:
    bw = -bw; bx = -bx; by = -by; bz = -bz
  let rw = qw + (bw - qw) * t
  let rx = qx + (bx - qx) * t
  let ry = qy + (by - qy) * t
  let rz = qz + (bz - qz) * t
  let l = sqrt(rw*rw + rx*rx + ry*ry + rz*rz)
  if l > 1e-6'f32:
    qw = rw / l; qx = rx / l; qy = ry / l; qz = rz / l

proc updateOSDesktop*(desktop: OSDesktop, dt: float32, mouseOverWindow: bool = false,
                      screenWidth: int, screenHeight: int) =
  desktop.time += dt

  # Cube drag & inertia (quaternion, world-space axes)
  const
    CubeDragSensitivity = 0.008'f32
    CubeDragRadius      = 70.0'f32
    CubeLinearDrag      = 2.8'f32

  # Helper: compose a small world-space rotation onto the cube quaternion.
  # axis (ax,ay,az) must be unit length, angle in radians.
  proc applyWorldRot(qw, qx, qy, qz: var float32, ax, ay, az, angle: float32) =
    let half = angle * 0.5'f32
    let s = sin(half)
    let dw = cos(half)
    let dx = ax * s
    let dy = ay * s
    let dz = az * s
    # delta * current  (left-multiply = world space)
    let nw = dw*qw - dx*qx - dy*qy - dz*qz
    let nx = dw*qx + dx*qw + dy*qz - dz*qy
    let ny = dw*qy - dx*qz + dy*qw + dz*qx
    let nz = dw*qz + dx*qy - dy*qx + dz*qw
    let len = sqrt(nw*nw + nx*nx + ny*ny + nz*nz)
    qw = nw/len; qx = nx/len; qy = ny/len; qz = nz/len

  let w = screenWidth.float32
  let h = screenHeight.float32
  let cubeCX = w * 0.64
  let cubeCY = h * 0.46
  let cubeSize = min(w, h) * 0.042'f32

  let mp   = getVirtualMousePosition()
  let ddst = sqrt((mp.x-cubeCX)*(mp.x-cubeCX) + (mp.y-cubeCY)*(mp.y-cubeCY))
  let overCube = ddst <= (CubeDragRadius + cubeSize * 2.0)

  if isPointerPressed() and overCube and not mouseOverWindow and
     not desktop.cubeEscaping:
    desktop.cubeDragging  = true
    desktop.cubeDragLastX = mp.x
    desktop.cubeDragLastY = mp.y
    desktop.cubeAngVelX   = 0.0
    desktop.cubeAngVelY   = 0.0
    # Grabbing a settled die releases the dice-roll hold and resumes free tumbling.
    desktop.cubeDiceMode = false
    desktop.cubeDiceResultTimer = 0.0
    desktop.cubeDiceVelY = 0.0

  if desktop.cubeDragging:
    if isPointerDown():
      let ddx = mp.x - desktop.cubeDragLastX
      let ddy = mp.y - desktop.cubeDragLastY
      # right drag -> rotate around world Y (up)
      # down drag -> rotate around world X (right)
      if abs(ddx) > 0.001'f32:
        applyWorldRot(desktop.cubeQW, desktop.cubeQX, desktop.cubeQY, desktop.cubeQZ,
                      0, 1, 0, ddx * CubeDragSensitivity)
      if abs(ddy) > 0.001'f32:
        applyWorldRot(desktop.cubeQW, desktop.cubeQX, desktop.cubeQY, desktop.cubeQZ,
                      1, 0, 0, -ddy * CubeDragSensitivity)
      desktop.cubeAngVelY   = ddx * CubeDragSensitivity / dt
      desktop.cubeAngVelX   = -ddy * CubeDragSensitivity / dt
      desktop.cubeDragLastX = mp.x
      desktop.cubeDragLastY = mp.y
    else:
      desktop.cubeDragging = false

  if not desktop.cubeDragging and not desktop.cubeDiceMode:
    # Inertia: spin down from throw velocity
    if abs(desktop.cubeAngVelY) > 0.0001'f32:
      applyWorldRot(desktop.cubeQW, desktop.cubeQX, desktop.cubeQY, desktop.cubeQZ,
                    0, 1, 0, desktop.cubeAngVelY * dt)
    if abs(desktop.cubeAngVelX) > 0.0001'f32:
      applyWorldRot(desktop.cubeQW, desktop.cubeQX, desktop.cubeQY, desktop.cubeQZ,
                    1, 0, 0, desktop.cubeAngVelX * dt)
    if not desktop.cubeEscaping:
      # No drag while flying free: the cube keeps its full tumble until it returns
      let decay = exp(-CubeLinearDrag * dt)
      desktop.cubeAngVelX *= decay
      desktop.cubeAngVelY *= decay
    # Passive auto-rotation (world axes, original rates)
    applyWorldRot(desktop.cubeQW, desktop.cubeQX, desktop.cubeQY, desktop.cubeQZ,
                  1, 0, 0, -0.171'f32 * dt)
    applyWorldRot(desktop.cubeQW, desktop.cubeQX, desktop.cubeQY, desktop.cubeQZ,
                  0, 1, 0, 0.133'f32 * dt)
    applyWorldRot(desktop.cubeQW, desktop.cubeQX, desktop.cubeQY, desktop.cubeQZ,
                  0, 0, 1, 0.095'f32 * dt)
  # Orbital-escape easter egg: spinning the cube fast for long enough knocks it
  # out of orbit. This plays every time; main consumes cubeEscapeTriggered to
  # grant the (one-shot) advancement the first time it ever happens.
  const
    CubeEscapeSpinThreshold = 8.0'f32   # rad/s of combined spin counts as "fast"
    CubeEscapeHeatNeeded    = 4.0'f32   # seconds of sustained fast spin to break orbit
    CubeEscapeHeatDecay     = 2.0'f32   # heat drains this much faster than it builds
    CubeEscapeFlyTime       = 2.2'f32
    CubeEscapeHoldTime      = 1.4'f32
    CubeEscapeReturnTime    = 2.4'f32

  if desktop.cubeEscaping:
    desktop.cubeEscapeTimer += dt
    let tEsc = desktop.cubeEscapeTimer
    if desktop.cubeDiceMode:
      # Dice roll: the die is *tossed* from wherever it currently sits (so there is
      # never a jump), arcs up, then falls and bounces on the felt under gravity
      # while tumbling. Once it comes to rest the spin eases onto the rolled face
      # and it stays there (held) reporting the number. offsetY: 0 = table line,
      # negative = above it. Position is integrated continuously every frame, so it
      # is C0-continuous across every phase boundary (no teleport anywhere).
      const Restitution  = 0.46'f32   # energy kept per vertical bounce
      const SafetyTime   = 4.5'f32   # hard cap so it can never hang
      const AirDrag      = 0.4'f32   # fractional spin lost per second while airborne
      const FeltFriction = 6.0'f32   # much stronger spin decay once the die is on felt
      let g = h * 4.0'f32
      let resting = desktop.cubeOffsetY >= -0.5'f32 and
                    abs(desktop.cubeDiceVelY) < h * 0.09'f32
      if not resting and tEsc < SafetyTime:
        # Airborne: gravity, bounce off felt, independent per-axis tumble spin.
        desktop.cubeDiceVelY += g * dt
        desktop.cubeOffsetY += desktop.cubeDiceVelY * dt
        desktop.cubeOffsetX = 0.0'f32
        if desktop.cubeOffsetY >= 0.0'f32:
          desktop.cubeOffsetY = 0.0'f32
          if desktop.cubeDiceVelY > 0.0'f32:
            desktop.cubeDiceVelY = -desktop.cubeDiceVelY * Restitution
            # Scatter the tumble axis on each bounce so the roll looks unpredictable
            let bc = sin(desktop.time * 23.7'f32 + desktop.cubeDiceVelY * 11.3'f32)
            desktop.cubeDiceSpinX = desktop.cubeDiceSpinX * 0.7'f32 + bc * 5.0'f32
            desktop.cubeDiceSpinZ = -desktop.cubeDiceSpinZ * 0.5'f32 + bc * 3.0'f32
        let spinDecay = 1.0'f32 - AirDrag * dt
        desktop.cubeDiceSpinX *= spinDecay
        desktop.cubeDiceSpinY *= spinDecay
        desktop.cubeDiceSpinZ *= spinDecay
        applyWorldRot(desktop.cubeQW, desktop.cubeQX, desktop.cubeQY, desktop.cubeQZ,
                      1, 0, 0, desktop.cubeDiceSpinX * dt)
        applyWorldRot(desktop.cubeQW, desktop.cubeQX, desktop.cubeQY, desktop.cubeQZ,
                      0, 1, 0, desktop.cubeDiceSpinY * dt)
        applyWorldRot(desktop.cubeQW, desktop.cubeQX, desktop.cubeQY, desktop.cubeQZ,
                      0, 0, 1, desktop.cubeDiceSpinZ * dt)
      else:
        desktop.cubeDiceVelY = 0.0'f32
        desktop.cubeOffsetY = 0.0'f32
        desktop.cubeOffsetX = 0.0'f32
        if desktop.cubeDiceResult == 0:
          # Felt spin-down. As spin decays below SettleThreshold a face-gravity
          # pull grows quadratically, simulating friction catching a corner and
          # weight flattening the die onto a face. The result face is always read
          # from the actual resting orientation, never pre-computed.
          let totalSpin = sqrt(desktop.cubeDiceSpinX * desktop.cubeDiceSpinX +
                               desktop.cubeDiceSpinY * desktop.cubeDiceSpinY +
                               desktop.cubeDiceSpinZ * desktop.cubeDiceSpinZ)
          if totalSpin > 0.05'f32 and tEsc < SafetyTime:
            let feltDecay = clamp(1.0'f32 - FeltFriction * dt, 0.0'f32, 1.0'f32)
            desktop.cubeDiceSpinX *= feltDecay
            desktop.cubeDiceSpinY *= feltDecay
            desktop.cubeDiceSpinZ *= feltDecay
            applyWorldRot(desktop.cubeQW, desktop.cubeQX, desktop.cubeQY, desktop.cubeQZ,
                          1, 0, 0, desktop.cubeDiceSpinX * dt)
            applyWorldRot(desktop.cubeQW, desktop.cubeQX, desktop.cubeQY, desktop.cubeQZ,
                          0, 1, 0, desktop.cubeDiceSpinY * dt)
            applyWorldRot(desktop.cubeQW, desktop.cubeQX, desktop.cubeQY, desktop.cubeQZ,
                          0, 0, 1, desktop.cubeDiceSpinZ * dt)
            # Face gravity: zero at SettleThreshold, grows as friction kills spin.
            const SettleThreshold = 3.0'f32
            if totalSpin < SettleThreshold:
              let isD20 = not globalSettings.isNil and
                          CubeSkinType(globalSettings.cubeSkin) == cskD20
              let (_, tw, tx, ty, tz) = faceUpFromQuat(
                desktop.cubeQW, desktop.cubeQX, desktop.cubeQY, desktop.cubeQZ, isD20)
              let frac = 1.0'f32 - totalSpin / SettleThreshold
              nlerpToward(desktop.cubeQW, desktop.cubeQX, desktop.cubeQY, desktop.cubeQZ,
                          tw, tx, ty, tz, frac * frac * 2.5'f32 * dt)
          else:
            # Spin negligible or safety cap: read face from resting orientation.
            let isD20 = not globalSettings.isNil and
                        CubeSkinType(globalSettings.cubeSkin) == cskD20
            let (rf, _, _, _, _) = faceUpFromQuat(
              desktop.cubeQW, desktop.cubeQX, desktop.cubeQY, desktop.cubeQZ, isD20)
            desktop.cubeDiceResult = rf
            desktop.cubeAngVelX = 0.0'f32
            desktop.cubeAngVelY = 0.0'f32
            desktop.cubeDiceSpinX = 0.0'f32
            desktop.cubeDiceSpinY = 0.0'f32
            desktop.cubeDiceSpinZ = 0.0'f32
            desktop.cubeEscaping = false
            desktop.cubeDiceResultTimer = 3.5'f32
            showDesktopToast(desktop, "Rolled a " & $desktop.cubeDiceResult & "!")
    elif desktop.cubePortalMode:
      # Portal-background escape: cube flies into entry portal, teleports to exit,
      # then smoothly returns to orbit.
      # Portal positions match desktop_bg_fx.nim drawPortalFx: blue=(w*0.2,h*0.5), orange=(w*0.8,h*0.5)
      let entryOffX = if desktop.cubePortalEnterRight: w * 0.8'f32 - cubeCX else: w * 0.2'f32 - cubeCX
      let entryOffY = h * 0.5'f32 - cubeCY
      let exitOffX  = if desktop.cubePortalEnterRight: w * 0.2'f32 - cubeCX else: w * 0.8'f32 - cubeCX
      let exitOffY  = entryOffY
      if tEsc < CubeEscapeFlyTime:
        let p = tEsc / CubeEscapeFlyTime
        desktop.cubeOffsetX = entryOffX * p * p
        desktop.cubeOffsetY = entryOffY * p * p
      elif tEsc < CubeEscapeFlyTime + CubeEscapeHoldTime:
        # Hold at exit portal (position written every frame, no separate jump flag needed)
        desktop.cubeOffsetX = exitOffX
        desktop.cubeOffsetY = exitOffY
      elif tEsc < CubeEscapeFlyTime + CubeEscapeHoldTime + CubeEscapeReturnTime:
        # Smoothstep back to orbit from exit portal
        let p = (tEsc - CubeEscapeFlyTime - CubeEscapeHoldTime) / CubeEscapeReturnTime
        let eased = 1.0'f32 - p * p * (3.0'f32 - 2.0'f32 * p)
        desktop.cubeOffsetX = exitOffX * eased
        desktop.cubeOffsetY = exitOffY * eased
      else:
        desktop.cubeEscaping = false
        desktop.cubePortalMode = false
        desktop.cubeOffsetX = 0.0
        desktop.cubeOffsetY = 0.0
        desktop.cubeAngVelX *= 0.1'f32
        desktop.cubeAngVelY *= 0.1'f32
    else:
      let flyDist = max(w, h) * 0.95'f32
      if tEsc < CubeEscapeFlyTime:
        # Accelerate away from the orbit slot
        let p = tEsc / CubeEscapeFlyTime
        desktop.cubeOffsetX = desktop.cubeEscapeDirX * flyDist * p * p
        desktop.cubeOffsetY = desktop.cubeEscapeDirY * flyDist * p * p
      elif tEsc < CubeEscapeFlyTime + CubeEscapeHoldTime:
        desktop.cubeOffsetX = desktop.cubeEscapeDirX * flyDist
        desktop.cubeOffsetY = desktop.cubeEscapeDirY * flyDist
      elif tEsc < CubeEscapeFlyTime + CubeEscapeHoldTime + CubeEscapeReturnTime:
        # Smoothstep back into orbit
        let p = (tEsc - CubeEscapeFlyTime - CubeEscapeHoldTime) / CubeEscapeReturnTime
        let eased = 1.0'f32 - p * p * (3.0'f32 - 2.0'f32 * p)
        desktop.cubeOffsetX = desktop.cubeEscapeDirX * flyDist * eased
        desktop.cubeOffsetY = desktop.cubeEscapeDirY * flyDist * eased
      else:
        desktop.cubeEscaping = false
        desktop.cubeOffsetX = 0.0
        desktop.cubeOffsetY = 0.0
        desktop.cubeAngVelX *= 0.1'f32
        desktop.cubeAngVelY *= 0.1'f32
  elif desktop.cubeEscapeArmed:
    let spinSpeed = sqrt(desktop.cubeAngVelX * desktop.cubeAngVelX +
                         desktop.cubeAngVelY * desktop.cubeAngVelY)
    if spinSpeed >= CubeEscapeSpinThreshold:
      desktop.cubeSpinHeat += dt
    else:
      desktop.cubeSpinHeat = max(0.0'f32, desktop.cubeSpinHeat - dt * CubeEscapeHeatDecay)
    # Which background + skin is selected decides what sustained fast spinning does.
    var selectedBg: DesktopBgType = dbgDefault
    var currentCubeSkin: CubeSkinType = cskDefault
    if not globalSettings.isNil:
      selectedBg = DesktopBgType(globalSettings.desktopBg)
      currentCubeSkin = CubeSkinType(globalSettings.cubeSkin)
    if selectedBg == dbgHorror and currentCubeSkin == cskJack:
      # Kernel Panic + Jack-O'-Node: spinning the pumpkin doesn't break orbit, it
      # fans the candle inside - the carved face glows brighter the more it is
      # spun, and fades back when the player stops. Cap heat so the glow tracks
      # the spin responsively, and keep the cube in its orbit slot (no wobble).
      desktop.cubeSpinHeat = min(desktop.cubeSpinHeat, CubeEscapeHeatNeeded)
      desktop.cubeJackGlow = desktop.cubeSpinHeat / CubeEscapeHeatNeeded
      desktop.cubeOffsetX = 0.0'f32
      desktop.cubeOffsetY = 0.0'f32
    else:
      # Any other combo: the glow boost fades out, and sustained fast spinning
      # breaks the cube out of orbit (the orbital-escape easter egg).
      desktop.cubeJackGlow = max(0.0'f32, desktop.cubeJackGlow - dt * 2.5'f32)
      # Wobble in place as the orbit destabilizes, so the player gets feedback
      let strain = desktop.cubeSpinHeat / CubeEscapeHeatNeeded
      desktop.cubeOffsetX = sin(desktop.time * 37.0'f32) * 3.5'f32 * strain
      desktop.cubeOffsetY = cos(desktop.time * 31.0'f32) * 3.5'f32 * strain
      if desktop.cubeSpinHeat >= CubeEscapeHeatNeeded:
        desktop.cubeEscaping = true
        desktop.cubeEscapeTimer = 0.0
        desktop.cubeSpinHeat = 0.0
        # Stay armed so the easter egg can play again on the next sustained spin.
        desktop.cubeEscapeTriggered = true
        desktop.cubeDragging = false
        if (selectedBg == dbgCasino or selectedBg == dbgDragon) and
           (currentCubeSkin == cskDice or currentCubeSkin == cskD20):
          # Dice roll: any dice skin (Lucky Die or Dragon's Fang D20) on either
          # dice background (Casino or Dragon's Lair). D20 rolls 1-20; Lucky Die
          # rolls 1-6. Target quaternion settles the matching face toward the camera.
          desktop.cubeDiceMode = true
          desktop.cubePortalMode = false
          desktop.cubeDiceResult = 0  # result is read from the resting orientation
          # Seed tumble spin from the player's throw + a chaotic component so every
          # roll looks different even at the same spin speed.
          let throwChaos = sin(desktop.time * 17.3'f32 + desktop.cubeAngVelY * 5.1'f32)
          let vy = desktop.cubeAngVelY
          let vx = desktop.cubeAngVelX
          let throwMag = clamp(abs(vy), 6.0'f32, 26.0'f32)
          desktop.cubeDiceSpinY = throwMag * (if vy >= 0: 1.0'f32 else: -1.0'f32) +
                                   throwChaos * 4.0'f32
          desktop.cubeDiceSpinX = 10.0'f32 + abs(vx) * 0.8'f32 + throwChaos * 5.0'f32
          desktop.cubeDiceSpinZ = throwChaos * 6.0'f32
          # Toss it up from its current position: an upward impulse, gravity does the rest.
          desktop.cubeDiceVelY = -1.55'f32 * h
        elif selectedBg == dbgPortal and currentCubeSkin == cskCompanion:
          desktop.cubeDiceMode = false
          desktop.cubePortalMode = true
          # Spin right (cubeAngVelY > 0) -> enter the orange portal on the right
          desktop.cubePortalEnterRight = desktop.cubeAngVelY >= 0.0'f32
        else:
          desktop.cubeDiceMode = false
          desktop.cubePortalMode = false
          # Fly off roughly along the spin direction, drifting upward
          let dirX = (if desktop.cubeAngVelY >= 0: 1.0'f32 else: -1.0'f32)
          let dirLen = sqrt(dirX * dirX + 0.55'f32 * 0.55'f32)
          desktop.cubeEscapeDirX = dirX / dirLen
          desktop.cubeEscapeDirY = -0.55'f32 / dirLen

  # Tick down desktop toasts and remove expired entries
  if desktop.toasts.len > 0:
    var newToasts: seq[DesktopToast] = @[]
    for t in desktop.toasts:
      var nt = t
      nt.timer = max(0.0'f32, nt.timer - dt)
      if nt.timer > 0.0'f32:
        newToasts.add(nt)
    desktop.toasts = newToasts

  # Tick down the big dice-result number
  if desktop.cubeDiceResultTimer > 0.0'f32:
    desktop.cubeDiceResultTimer = max(0.0'f32, desktop.cubeDiceResultTimer - dt)

  # Release the dice hold if the player leaves a dice-combo (either dice skin on
  # either dice background) while the die rests, so it doesn't stay frozen elsewhere.
  if desktop.cubeDiceMode and not desktop.cubeEscaping and not globalSettings.isNil:
    let guardBg = DesktopBgType(globalSettings.desktopBg)
    let guardSkin = CubeSkinType(globalSettings.cubeSkin)
    let onDiceCombo = (guardBg == dbgCasino or guardBg == dbgDragon) and
                      (guardSkin == cskDice or guardSkin == cskD20)
    if not onDiceCombo:
      desktop.cubeDiceMode = false
      desktop.cubeDiceResult = 0
      desktop.cubeDiceResultTimer = 0.0'f32
      desktop.cubeDiceVelY = 0.0'f32
      desktop.cubeDiceSpinX = 0.0'f32
      desktop.cubeDiceSpinY = 0.0'f32
      desktop.cubeDiceSpinZ = 0.0'f32

  # Convert cube quaternion to Euler angles (X, Y, Z) for wallpaper rendering
  # Rotation order: rotate X, then Y, then Z (Rx -> Ry -> Rz)
  let qw = desktop.cubeQW
  let qx = desktop.cubeQX
  let qy = desktop.cubeQY
  let qz = desktop.cubeQZ

  let r00 = 1.0'f32 - 2.0'f32*(qy*qy + qz*qz)
  let r10 = 2.0'f32*(qx*qy + qz*qw)
  let r20 = 2.0'f32*(qx*qz - qy*qw)
  let r21 = 2.0'f32*(qy*qz + qx*qw)
  let r22 = 1.0'f32 - 2.0'f32*(qx*qx + qy*qy)

  var sy = -r20
  if sy > 1.0'f32:
    sy = 1.0'f32
  elif sy < -1.0'f32:
    sy = -1.0'f32

  desktop.cubeRotX = arctan2(r21, r22)
  desktop.cubeRotY = arcsin(sy)
  desktop.cubeRotZ = arctan2(r10, r00)

  # Update loading animation if active
  if desktop.loadingActive:
    desktop.loadingProgress += dt * 2.0  # Progress speed
    if desktop.loadingProgress >= 1.0:
      desktop.loadingActive = false
      desktop.loadingProgress = 0.0

  # Update all icon names to reflect current language
  for i in 0..<desktop.icons.len:
    desktop.icons[i].name = getIconName(desktop.icons[i].iconType)
    desktop.icons[i].selected = (i == desktop.selectedIcon)

proc drawHexBadge(cx, cy: int32, radius: float32, fill, edge: Color, rotation: float32 = PI / 6.0) =
  var points: array[6, Vector2]
  for i in 0..<6:
    let angle = rotation + i.float32 * PI / 3.0
    points[i] = Vector2(x: cx.float32 + cos(angle) * radius,
                        y: cy.float32 + sin(angle) * radius)

  for i in 1..<5:
    drawTriangle(points[0], points[i], points[i + 1], fill)
  for i in 0..<6:
    let next = (i + 1) mod 6
    drawLine(points[i], points[next], 2, edge)

proc drawIconTile(icon: DesktopIcon, time: float32, selected: bool) =
  let pulse = if selected: sin(time * 4.0) * 0.15 + 1.0 else: 1.0
  let iconSize = (ICON_SIZE.float32 * pulse).int32
  let offsetX = if selected: (ICON_SIZE - iconSize) div 2 else: 0
  let offsetY = if selected: (ICON_SIZE - iconSize) div 2 else: 0
  let x = icon.x.int32 + offsetX
  let y = icon.y.int32 + offsetY
  let accent = icon.iconColor
  let edge = if selected: brighten(accent, 35, accent.a.int) else: Color(r: 86, g: 104, b: 130, a: 235)
  let topFill = if selected: Color(r: 36, g: 50, b: 70, a: 248) else: Color(r: 24, g: 32, b: 48, a: 232)
  let bottomFill = if selected: Color(r: 18, g: 24, b: 38, a: 250) else: Color(r: 12, g: 17, b: 28, a: 238)

  if selected:
    drawSoftGlow(icon.x.float32 + ICON_SIZE.float32 * 0.5, icon.y.float32 + ICON_SIZE.float32 * 0.5,
                 45.0, withAlpha(accent, 90), 0.85)

  drawRectangle(x + 5, y + 7, iconSize, iconSize, Color(r: 0, g: 0, b: 0, a: 95))
  drawRectangleGradientV(x, y, iconSize, iconSize, topFill, bottomFill)

  # Chamfered, glassy corners keep the OS look without needing image assets.
  let cut = max(7'i32, iconSize div 8)
  let darkCorner = Color(r: 7, g: 10, b: 18, a: 230)
  drawTriangle(Vector2(x: x.float32, y: y.float32),
               Vector2(x: (x + cut).float32, y: y.float32),
               Vector2(x: x.float32, y: (y + cut).float32), darkCorner)
  drawTriangle(Vector2(x: (x + iconSize).float32, y: (y + iconSize).float32),
               Vector2(x: (x + iconSize - cut).float32, y: (y + iconSize).float32),
               Vector2(x: (x + iconSize).float32, y: (y + iconSize - cut).float32), darkCorner)

  drawRectangleLines(Rectangle(x: x.float32, y: y.float32,
                                width: iconSize.float32, height: iconSize.float32), 2, edge)
  drawLine(Vector2(x: (x + 7).float32, y: (y + 5).float32),
           Vector2(x: (x + iconSize - 11).float32, y: (y + 5).float32),
           2, Color(r: 205, g: 245, b: 255, a: if selected: 150 else: 72))
  drawLine(Vector2(x: (x + 5).float32, y: (y + iconSize - 7).float32),
           Vector2(x: (x + iconSize - 8).float32, y: (y + iconSize - 7).float32),
           1, withAlpha(accent, if selected: 175 else: 95))

  let scanY = y + 12 + int32((sin(time * 2.4 + icon.iconType.int.float32) * 0.5 + 0.5) * (iconSize.float32 - 24.0))
  drawRectangle(x + 8, scanY, iconSize - 16, 2,
                withAlpha(accent, if selected: 92 else: 38))

proc drawDesktopIcon(icon: DesktopIcon, time: float32, selected: bool) =
  drawIconTile(icon, time, selected)

  # Icon graphic based on type
  let centerX = (icon.x + ICON_SIZE div 2).int32
  let centerY = (icon.y + ICON_SIZE div 2).int32
  let accent = icon.iconColor
  let bright = brighten(accent, 55, accent.a.int)
  let dim = brighten(accent, -(45), accent.a.int)
  drawHexBadge(centerX, centerY, 22.0, Color(r: 8, g: 14, b: 24, a: 160),
               withAlpha(accent, 120),
               PI / 6.0 + time * 0.08)

  case icon.iconType
  of diPlay:
    # Launch prism
    drawTriangle(
      Vector2(x: (centerX - 9).float32, y: (centerY - 14).float32),
      Vector2(x: (centerX - 9).float32, y: (centerY + 14).float32),
      Vector2(x: (centerX + 16).float32, y: centerY.float32),
      accent
    )
    drawTriangle(
      Vector2(x: (centerX - 5).float32, y: (centerY - 7).float32),
      Vector2(x: (centerX - 5).float32, y: (centerY + 7).float32),
      Vector2(x: (centerX + 7).float32, y: centerY.float32),
      bright
    )

  of diSurvival:
    # Survival shield timer
    drawCircle(Vector2(x: centerX.float32, y: centerY.float32), 18, dim)
    drawCircleLines(Vector2(x: centerX.float32, y: centerY.float32), 18, bright)
    drawCircle(Vector2(x: centerX.float32, y: centerY.float32), 4, bright)
    drawLine(Vector2(x: centerX.float32, y: centerY.float32),
            Vector2(x: centerX.float32, y: centerY.float32 - 15), 3, White)
    drawLine(Vector2(x: centerX.float32, y: centerY.float32),
            Vector2(x: centerX.float32 + 10, y: centerY.float32), 3, White)
    for i in 0..3:
      let angle = i.float32 * PI / 2.0 + time * 0.6
      drawCircle(Vector2(x: centerX.float32 + cos(angle) * 22.0,
                         y: centerY.float32 + sin(angle) * 22.0), 2.2, accent)

  of diStatistics:
    # Analytics bars with trend line
    drawRectangle(centerX - 17, centerY + 5, 7, 15, dim)
    drawRectangle(centerX - 5, centerY - 2, 7, 22, accent)
    drawRectangle(centerX + 7, centerY - 10, 7, 30, bright)
    drawLine(Vector2(x: (centerX - 18).float32, y: (centerY + 2).float32),
             Vector2(x: (centerX - 3).float32, y: (centerY - 8).float32), 2, White)
    drawLine(Vector2(x: (centerX - 3).float32, y: (centerY - 8).float32),
             Vector2(x: (centerX + 18).float32, y: (centerY - 17).float32), 2, White)

  of diSettings:
    # Tuning sliders
    for i in 0..2:
      let y = centerY - 13 + i * 13
      drawLine(Vector2(x: (centerX - 18).float32, y: y.float32),
               Vector2(x: (centerX + 18).float32, y: y.float32), 3, dim)
      let knobX = centerX - 10 + ((i * 13) mod 27)
      drawCircle(Vector2(x: knobX.float32, y: y.float32), 5, bright)
      drawCircleLines(Vector2(x: knobX.float32, y: y.float32), 7, accent)

  of diShop:
    # Store crate with swatches
    drawRectangle(centerX - 15, centerY - 9, 30, 24, accent)
    drawRectangle(centerX - 12, centerY - 14, 24, 8, dim)
    drawLine(Vector2(x: (centerX - 7).float32, y: (centerY - 14).float32),
             Vector2(x: (centerX - 7).float32, y: (centerY - 22).float32), 3, bright)
    drawLine(Vector2(x: (centerX + 7).float32, y: (centerY - 14).float32),
             Vector2(x: (centerX + 7).float32, y: (centerY - 22).float32), 3, bright)
    drawLine(Vector2(x: (centerX - 7).float32, y: (centerY - 22).float32),
             Vector2(x: (centerX + 7).float32, y: (centerY - 22).float32), 3, bright)
    let colors = [
      Color(r: 255, g: 100, b: 180, a: 255),
      Color(r: 0, g: 255, b: 100, a: 255),
      Color(r: 0, g: 200, b: 255, a: 255)
    ]
    for i in 0..<3:
      drawCircle(Vector2(x: (centerX - 8 + i * 8).float32, y: (centerY + 5).float32), 4.5, colors[i])

  of diHelp:
    # Luminous document
    drawRectangle(centerX - 13, centerY - 18, 26, 34, accent)
    drawTriangle(Vector2(x: (centerX + 13).float32, y: (centerY - 18).float32),
                 Vector2(x: (centerX + 13).float32, y: (centerY - 6).float32),
                 Vector2(x: (centerX + 1).float32, y: (centerY - 18).float32), bright)
    drawText("?", centerX - 7, centerY - 10, 26, White)

  of diQuit:
    # Shutdown ring
    drawCircle(Vector2(x: centerX.float32, y: centerY.float32), 19, dim)
    drawCircle(Vector2(x: centerX.float32, y: centerY.float32), 12, Color(r: 8, g: 12, b: 20, a: 255))
    drawCircleLines(Vector2(x: centerX.float32, y: centerY.float32), 18, bright)
    drawRectangle(centerX - 2, centerY - 21, 4, 18, bright)

  of diSandbox:
    # Lab flask
    let flaskColor = accent
    let liquidColor = Color(r: 0, g: 200, b: 255, a: 200)
    let baseWidth = 20'i32
    let topWidth = 12'i32
    let flaskHeight = 24'i32
    let flaskBottom = centerY + 12
    let flaskTop = flaskBottom - flaskHeight
    drawRectangle(centerX - topWidth div 2, flaskTop, topWidth, 8, flaskColor)
    drawTriangle(
      Vector2(x: (centerX - topWidth div 2).float32, y: (flaskTop + 8).float32),
      Vector2(x: (centerX - baseWidth div 2).float32, y: flaskBottom.float32),
      Vector2(x: (centerX + baseWidth div 2).float32, y: flaskBottom.float32),
      flaskColor
    )
    drawRectangle(centerX - baseWidth div 2 + 3, flaskBottom - 10, baseWidth - 6, 8, liquidColor)
    drawCircle(Vector2(x: (centerX - 4).float32, y: (flaskBottom - 5).float32), 2, White)
    drawCircle(Vector2(x: (centerX + 3).float32, y: (flaskBottom - 8).float32), 1.5, White)

  of diPvP:
    # Versus duel glyph
    drawLine(Vector2(x: (centerX - 18).float32, y: (centerY + 15).float32),
             Vector2(x: (centerX + 13).float32, y: (centerY - 16).float32), 4, accent)
    drawLine(Vector2(x: (centerX + 18).float32, y: (centerY + 15).float32),
             Vector2(x: (centerX - 13).float32, y: (centerY - 16).float32), 4, bright)
    drawRectangle(centerX - 17, centerY + 10, 10, 4, dim)
    drawRectangle(centerX + 7, centerY + 10, 10, 4, dim)
    drawCircle(Vector2(x: centerX.float32, y: centerY.float32), 6, Color(r: 255, g: 255, b: 255, a: 205))
    drawCircle(Vector2(x: centerX.float32, y: centerY.float32), 3, accent)

  of diRoguelite:
    # Branching sector nodes
    let nodeColor = accent
    let top = Vector2(x: centerX.float32, y: (centerY - 18).float32)
    let left = Vector2(x: (centerX - 18).float32, y: (centerY + 12).float32)
    let mid = Vector2(x: centerX.float32, y: (centerY + 18).float32)
    let right = Vector2(x: (centerX + 18).float32, y: (centerY + 12).float32)
    drawLine(top, left, 3, Color(r: 120, g: 255, b: 220, a: 220))
    drawLine(top, mid, 3, Color(r: 120, g: 255, b: 220, a: 220))
    drawLine(top, right, 3, Color(r: 120, g: 255, b: 220, a: 220))
    drawCircle(top, 7, nodeColor)
    drawCircle(left, 6, Gold)
    drawCircle(mid, 6, nodeColor)
    drawCircle(right, 6, Color(r: 255, g: 110, b: 90, a: 255))

  of diAdvancements:
    # Progress ledger with tier nodes
    let ledgerX = centerX - 16
    let ledgerY = centerY - 18
    drawRectangle(ledgerX.int32, ledgerY.int32, 32, 36, Color(r: 18, g: 28, b: 42, a: 255))
    drawRectangleLines(Rectangle(x: ledgerX.float32, y: ledgerY.float32,
                                 width: 32.0, height: 36.0), 2, accent)
    for i in 0..<3:
      let rowY = ledgerY + 8 + i * 9
      drawCircle(Vector2(x: (ledgerX + 7).float32, y: rowY.float32), 3,
                 if i == 0: Gold elif i == 1: accent else: Color(r: 90, g: 255, b: 150, a: 255))
      drawRectangle((ledgerX + 13).int32, (rowY - 2).int32, (12 + i * 3).int32, 3,
                    Color(r: 170, g: 210, b: 230, a: 220))
    drawLine(Vector2(x: (ledgerX + 7).float32, y: (ledgerY + 8).float32),
             Vector2(x: (ledgerX + 7).float32, y: (ledgerY + 26).float32),
             1, Color(r: 120, g: 220, b: 255, a: 180))

  of diChangelog:
    # Patch-notes document with a folded corner, text lines, and a "new" star
    let docX = centerX - 13
    let docY = centerY - 17
    drawRectangle(docX.int32, docY.int32, 26, 34, Color(r: 240, g: 240, b: 246, a: 255))
    drawRectangleLines(Rectangle(x: docX.float32, y: docY.float32,
                                 width: 26.0, height: 34.0), 2, accent)
    # Folded top-right corner
    drawTriangle(Vector2(x: (docX + 26).float32, y: docY.float32),
                 Vector2(x: (docX + 26).float32, y: (docY + 9).float32),
                 Vector2(x: (docX + 17).float32, y: docY.float32), dim)
    # Text lines of varying length
    for i in 0..<4:
      let lineY = docY + 8 + i * 6
      let lineW = if i == 3: 10 else: 16 - (i mod 2) * 4
      drawRectangle((docX + 5).int32, lineY.int32, lineW.int32, 2,
                    Color(r: 70, g: 90, b: 120, a: 220))
    # Sparkle marking fresh changes
    let starX = (centerX + 12).float32
    let starY = (centerY + 14).float32
    drawLine(Vector2(x: starX - 5, y: starY), Vector2(x: starX + 5, y: starY), 2, bright)
    drawLine(Vector2(x: starX, y: starY - 5), Vector2(x: starX, y: starY + 5), 2, bright)
    drawCircle(Vector2(x: starX, y: starY), 1.5, White)

  of diCredits:
    # Terminal panel with a beating heart: credits + "support the project"
    let panelX = centerX - 18
    let panelY = centerY - 15
    drawRectangle(panelX.int32, panelY.int32, 36, 30, Color(r: 14, g: 18, b: 30, a: 255))
    drawRectangleLines(Rectangle(x: panelX.float32, y: panelY.float32,
                                 width: 36.0, height: 30.0), 2, accent)
    # Title bar of the "window"
    drawRectangle(panelX.int32, panelY.int32, 36, 6, dim)
    for i in 0..<3:
      drawCircle(Vector2(x: (panelX + 5 + i * 6).float32, y: (panelY + 3).float32),
                 1.4, Color(r: 240, g: 240, b: 250, a: 220))
    # Heart, gently beating so the icon reads as a "thanks / support" affordance
    let beat = 1.0'f32 + sin(time * 3.2) * 0.09'f32
    let hx = centerX.float32
    let hy = (centerY + 2).float32
    let lobe = 4.6'f32 * beat
    drawCircle(Vector2(x: hx - lobe * 0.85, y: hy - lobe * 0.5), lobe, bright)
    drawCircle(Vector2(x: hx + lobe * 0.85, y: hy - lobe * 0.5), lobe, bright)
    drawTriangle(Vector2(x: hx - lobe * 1.72, y: hy - lobe * 0.15),
                 Vector2(x: hx, y: hy + lobe * 2.05),
                 Vector2(x: hx + lobe * 1.72, y: hy - lobe * 0.15), bright)
    drawCircle(Vector2(x: hx - lobe * 0.7, y: hy - lobe * 0.75), lobe * 0.3,
               Color(r: 255, g: 255, b: 255, a: 180))
  # Locked overlay for modes that are gated by progression
  var isLocked = false
  case icon.iconType
  of diRoguelite:
    if globalSettings.isNil or not globalSettings.rogueliteUnlocked:
      isLocked = true
  of diSurvival:
    if globalSettings.isNil or not globalSettings.survivalUnlocked:
      isLocked = true
  else: discard

  if isLocked:
    let ix = icon.x.int32
    let iy = icon.y.int32
    # dim the icon tile
    drawRectangle(ix + 4, iy + 4, ICON_SIZE.int32 - 8, ICON_SIZE.int32 - 8,
                  Color(r: 0, g: 0, b: 0, a: 120))
    # simple padlock: shackle (arc) + body
    let lockW = 18'i32
    let lockH = 12'i32
    let lockCX = centerX
    let lockCY = centerY - 2
    let shackleR = 9.0'f32
    drawCircleLines(Vector2(x: lockCX.float32, y: (lockCY - 6).float32), shackleR, Color(r: 235, g: 240, b: 245, a: 220))
    drawRectangle((lockCX - lockW div 2).int32, (lockCY - 1).int32, lockW.int32, lockH.int32, Color(r: 235, g: 240, b: 245, a: 230))
    drawRectangleLines(Rectangle(x: (lockCX - lockW div 2).float32, y: (lockCY - 1).float32,
                                 width: lockW.float32, height: lockH.float32), 2, Color(r: 18, g: 22, b: 28, a: 200))
    # keyhole
    drawRectangle(lockCX - 1, lockCY + 2, 3, 5, Color(r: 18, g: 22, b: 28, a: 255))

  # Icon label with shadow
  let labelY = icon.y + ICON_SIZE + 8
  drawDesktopLabel(icon.name, icon.x.int32, labelY.int32, selected)

proc drawTaskbar(screenWidth, screenHeight: int, time: float32) =
  # Taskbar background
  drawRectangle(0, (screenHeight - TASKBAR_HEIGHT).int32,
               screenWidth.int32, TASKBAR_HEIGHT.int32,
               Color(r: 20, g: 20, b: 30, a: 240))
  drawRectangleLines(Rectangle(x: 0, y: (screenHeight - TASKBAR_HEIGHT).float32,
                                width: screenWidth.float32, height: TASKBAR_HEIGHT.float32),
                    1, Color(r: 0, g: 200, b: 200, a: 255))

  # Start button
  let startBtnW = 120
  let startBtnH = 32
  let startBtnX = 8
  let startBtnY = screenHeight - TASKBAR_HEIGHT + 4

  drawRectangle(startBtnX.int32, startBtnY.int32, startBtnW.int32, startBtnH.int32,
               Color(r: 0, g: 60, b: 80, a: 255))
  drawRectangleLines(Rectangle(x: startBtnX.float32, y: startBtnY.float32,
                                width: startBtnW.float32, height: startBtnH.float32), 2,
                    Color(r: 0, g: 200, b: 255, a: 255))

  # Logo in start button
  let logoSize = 16
  drawRectangle((startBtnX + 10).int32, (startBtnY + 8).int32,
               logoSize.int32, logoSize.int32,
               Color(r: 0, g: 200, b: 255, a: 255))

  drawText(t("os_tophat_button"), (startBtnX + 35).int32, (startBtnY + 7).int32, 18, White)

  # System tray - clock with dynamic time. HH and MM are drawn at fixed x
  # positions and the ":" blinks in its own reserved slot at a true 1 Hz (from
  # the real wall-clock nanosecond). Drawing the pieces separately keeps the
  # minutes from sliding when the colon disappears.
  let currentTime = now()
  let hhStr = currentTime.format("HH")
  let mmStr = currentTime.format("mm")
  let dateStr = currentTime.format("MM/dd")

  let clockX = screenWidth - 80
  let clockY = startBtnY + 2
  let clockCol = Color(r: 0, g: 255, b: 255, a: 255)
  let hhW = measureText(hhStr, 16)
  let colonW = measureText(":", 16)
  drawText(hhStr, clockX.int32, clockY.int32, 16, clockCol)
  if currentTime.nanosecond < 500_000_000:
    drawText(":", (clockX + hhW).int32, clockY.int32, 16, clockCol)
  drawText(mmStr, (clockX + hhW + colonW).int32, clockY.int32, 16, clockCol)
  drawText(dateStr, (clockX - 10).int32, (clockY + 16).int32, 12,
          Color(r: 100, g: 200, b: 200, a: 255))

  # Volume indicator - a speaker with radiating sound-wave arcs plus a percentage.
  # The arcs (not stacked bars) and the "%" label make it read unambiguously as
  # master volume, so it can't be mistaken for the network/signal indicator.
  # Average of the effects (`volume`) and music channels, so the tray reflects
  # overall loudness rather than just one slider.
  let vol = if globalSettings.isNil: 0.5'f32
            else: (globalSettings.volume + globalSettings.musicVolume) * 0.5'f32
  let muted = vol <= 0.001'f32
  let volX = screenWidth - 222
  let cy = (clockY + 9).float32          # vertical centre, aligned with the clock text
  let spkCol = if muted: Color(r: 255, g: 110, b: 110, a: 255)
               else: Color(r: 175, g: 228, b: 228, a: 255)
  # Speaker: a solid cone (back box + triangular flare).
  drawRectangle(volX.int32, (cy - 3.0'f32).int32, 4, 6, spkCol)
  drawTriangle(Vector2(x: (volX + 4).float32, y: cy - 6.0'f32),
               Vector2(x: (volX + 4).float32, y: cy + 6.0'f32),
               Vector2(x: (volX + 11).float32, y: cy), spkCol)
  if muted:
    # Muted: a red cross where the sound waves would be.
    drawLine(Vector2(x: (volX + 15).float32, y: cy - 5.0'f32),
             Vector2(x: (volX + 23).float32, y: cy + 5.0'f32), 2, spkCol)
    drawLine(Vector2(x: (volX + 23).float32, y: cy - 5.0'f32),
             Vector2(x: (volX + 15).float32, y: cy + 5.0'f32), 2, spkCol)
  else:
    # Concentric sound-wave arcs; each lights as the volume crosses its band.
    let waveCenter = Vector2(x: (volX + 9).float32, y: cy)
    for i in 0..2:
      let r = 6.5'f32 + i.float32 * 4.0'f32
      let lit = vol >= i.float32 / 3.0'f32
      let arcCol = if lit: Color(r: 0, g: 235, b: 205, a: 255)
                   else: Color(r: 45, g: 70, b: 75, a: 180)
      drawRing(waveCenter, r - 1.0'f32, r + 0.6'f32, -52.0'f32, 52.0'f32, 14, arcCol)
  # Percentage label removes any doubt about what the icon represents.
  let pctText = $int(round(vol * 100.0'f32)) & "%"
  drawText(pctText, (volX + 28).int32, (clockY + 3).int32, 12,
           if muted: Color(r: 255, g: 130, b: 130, a: 255)
           else: Color(r: 135, g: 212, b: 212, a: 255))

  # System indicators with icons
  let indicatorX = screenWidth - 146
  # Network indicator: a "connected" LED that softly pulses so it reads as live.
  let netPulse = (sin(time * 3.0) * 0.5 + 0.5)
  let netAlpha = uint8(170.0 + netPulse * 85.0)
  drawRectangle(indicatorX.int32, (clockY + 6).int32, 12, 8,
               Color(r: 50, g: 255, b: 50, a: netAlpha))
  drawText(t(tkDesktopNet), (indicatorX + 16).int32, (clockY + 3).int32, 12,
          Color(r: 150, g: 150, b: 150, a: 255))

type
  WallpaperCubePoint = object
    x, y, z: float32

  WallpaperCubeFace = object
    corners: array[4, int]
    depth: float32
    color: Color

proc rotateWallpaperCubePoint(point: WallpaperCubePoint,
                              angleX, angleY, angleZ: float32): WallpaperCubePoint =
  let sinX = sin(angleX)
  let cosX = cos(angleX)
  let sinY = sin(angleY)
  let cosY = cos(angleY)
  let sinZ = sin(angleZ)
  let cosZ = cos(angleZ)

  var x = point.x
  var y = point.y * cosX - point.z * sinX
  var z = point.y * sinX + point.z * cosX

  let yRotX = x * cosY + z * sinY
  z = -x * sinY + z * cosY
  x = yRotX

  let zRotX = x * cosZ - y * sinZ
  y = x * sinZ + y * cosZ
  x = zRotX

  WallpaperCubePoint(x: x, y: y, z: z)

proc projectWallpaperCubePoint(point: WallpaperCubePoint,
                               centerX, centerY, scale: float32): Vector2 =
  let cameraDistance = 4.2'f32
  let depth = max(1.35'f32, cameraDistance - point.z)
  let perspective = cameraDistance / depth
  Vector2(
    x: centerX + point.x * scale * perspective,
    y: centerY + point.y * scale * perspective
  )

proc drawWallpaperCubeFace(points: array[8, Vector2], face: WallpaperCubeFace) =
  let a = points[face.corners[0]]
  let b = points[face.corners[1]]
  let c = points[face.corners[2]]
  let d = points[face.corners[3]]
  drawTriangle(a, b, c, face.color)
  drawTriangle(a, c, d, face.color)

proc drawTriangleBothWindings(a, b, c: Vector2, color: Color) =
  ## Filled triangles are winding-sensitive when backface culling is active,
  ## and the winding of face-local geometry flips as the cube tumbles, emit
  ## both orders so the triangle can never be culled away.
  drawTriangle(a, b, c, color)
  drawTriangle(a, c, b, color)

# Fixed light in MODEL space, shared by every wallpaper-solid renderer: because
# it rotates with the solid, dotting it with a face's own (model-space) normal
# gives a brightness that is constant per face, the shading is baked onto each
# side and never tracks the camera.
const
  LightDirX = 0.442'f32
  LightDirY = -0.694'f32
  LightDirZ = 0.568'f32

const
  D20InvPhi = 0.6180339887'f32 ## 1/phi: scales the classic (0,+-1,+-phi)
    ## icosahedron vertices so every vertex's largest axis component reaches
    ## exactly 1, matching the unit cube's own reach at the same `size`.
  D20Verts: array[12, WallpaperCubePoint] = [
    WallpaperCubePoint(x: -D20InvPhi, y:  1.0'f32,    z:  0.0'f32),
    WallpaperCubePoint(x:  D20InvPhi, y:  1.0'f32,    z:  0.0'f32),
    WallpaperCubePoint(x: -D20InvPhi, y: -1.0'f32,    z:  0.0'f32),
    WallpaperCubePoint(x:  D20InvPhi, y: -1.0'f32,    z:  0.0'f32),
    WallpaperCubePoint(x:  0.0'f32,   y: -D20InvPhi,  z:  1.0'f32),
    WallpaperCubePoint(x:  0.0'f32,   y:  D20InvPhi,  z:  1.0'f32),
    WallpaperCubePoint(x:  0.0'f32,   y: -D20InvPhi,  z: -1.0'f32),
    WallpaperCubePoint(x:  0.0'f32,   y:  D20InvPhi,  z: -1.0'f32),
    WallpaperCubePoint(x:  1.0'f32,   y:  0.0'f32,    z: -D20InvPhi),
    WallpaperCubePoint(x:  1.0'f32,   y:  0.0'f32,    z:  D20InvPhi),
    WallpaperCubePoint(x: -1.0'f32,   y:  0.0'f32,    z: -D20InvPhi),
    WallpaperCubePoint(x: -1.0'f32,   y:  0.0'f32,    z:  D20InvPhi)
  ]
  ## Standard indexed icosahedron face list (12 verts / 20 tri faces / 30
  ## edges, Euler check: 12 - 30 + 20 = 2).
  D20Faces: array[20, array[3, int]] = [
    [0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11],
    [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
    [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9],
    [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]
  ]
  ## Face -> die value, indexed the same as D20Faces. A regular icosahedron is
  ## centrally symmetric (face i's antipode is another face in this list), so
  ## values are assigned in antipodal pairs summing to 21, exactly like a real
  ## D20 (and this skin's own Lucky Die, whose pips sum to 7 on opposite faces).
  D20FaceNumbers: array[20, int] = [
    1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 17, 18, 19, 20, 16, 12, 11, 15, 14, 13
  ]
  D20Edges: array[30, array[2, int]] = [
    [0, 11], [5, 11], [0, 5],  [1, 5],  [0, 1],  [1, 7],  [0, 7],  [7, 10], [0, 10], [10, 11],
    [5, 9],  [1, 9],  [4, 11], [4, 5],  [2, 10], [2, 11], [6, 7],  [6, 10], [1, 8],  [7, 8],
    [3, 9],  [4, 9],  [3, 4],  [2, 4],  [2, 3],  [2, 6],  [3, 6],  [6, 8],  [3, 8],  [8, 9]
  ]
  ## For each entry in D20Edges, the two faces from D20Faces that share it.
  ## Lets the edge pass draw each edge exactly once: visible if either adjacent
  ## face is front-facing (silhouette edges included, pure back-face edges skipped).
  D20EdgeFaces: array[30, array[2, int]] = [
    [0, 4],  [0, 6],  [0, 1],  [1, 5],  [1, 2],  [2, 9],  [2, 3],  [3, 8],  [3, 4],  [4, 7],
    [5, 15], [5, 19], [6, 16], [6, 15], [7, 17], [7, 16], [8, 18], [8, 17], [9, 19], [9, 18],
    [10, 14],[10, 15],[10, 11],[11, 16],[11, 12],[12, 17],[12, 13],[13, 18],[13, 14],[14, 19]
  ]

type
  D20Face = object
    corners: array[3, int]
    idx: int
    depth: float32
    nx, ny, nz: float32
    color: Color

proc drawD20WallpaperCube(centerX, centerY, size, time,
                          angleX, angleY, angleZ: float32, skinData: CubeSkinData) =
  ## Dragon's Fang: a real icosahedron standing in for the wallpaper cube, not
  ## a paint job on the cube's 8-vert/6-face geometry. Reuses the cube's point
  ## rotate/project helpers (shape-agnostic) but needs its own face/edge
  ## tables and a painter's-algorithm sort sized for 20 faces instead of 6.
  var rotated: array[12, WallpaperCubePoint]
  var projected: array[12, Vector2]
  for i in 0 ..< 12:
    rotated[i] = rotateWallpaperCubePoint(D20Verts[i], angleX, angleY, angleZ)
    projected[i] = projectWallpaperCubePoint(rotated[i], centerX, centerY, size)

  var faces: array[20, D20Face]
  for i in 0 ..< 20:
    var avgZ = 0.0'f32
    var nX = 0.0'f32
    var nY = 0.0'f32
    var nZ = 0.0'f32
    for corner in D20Faces[i]:
      avgZ += rotated[corner].z
      nX += D20Verts[corner].x
      nY += D20Verts[corner].y
      nZ += D20Verts[corner].z
    avgZ /= 3.0'f32
    # A facet's averaged corners point the same way as its outward normal (true
    # for any face of any solid centred at the origin) but, unlike the cube's
    # axis-aligned faces, aren't already unit length, normalise before using
    # this as a light direction.
    let nLen = sqrt(nX * nX + nY * nY + nZ * nZ)
    if nLen > 0.0001'f32:
      nX /= nLen; nY /= nLen; nZ /= nLen
    let light = clamp((nX * LightDirX + nY * LightDirY + nZ * LightDirZ) * 0.5'f32 + 0.5'f32,
                      0.0'f32, 1.0'f32)
    # Opaque, like the Lucky Die: a real gemstone, not cube glass. The base
    # colour is near-black, so lean on the edge colour (gold) for the lit
    # facets rather than a flat multiply, or the shading would barely show.
    let baseC = skinData.faceColor
    let hiC = skinData.edgeColor
    faces[i] = D20Face(
      corners: D20Faces[i],
      idx: i,
      depth: avgZ,
      nx: nX, ny: nY, nz: nZ,
      color: Color(
        r: uint8(clamp(baseC.r.float32 + light * (hiC.r.float32 - baseC.r.float32) * 0.45'f32, 0.0'f32, 255.0'f32)),
        g: uint8(clamp(baseC.g.float32 + light * (hiC.g.float32 - baseC.g.float32) * 0.45'f32, 0.0'f32, 255.0'f32)),
        b: uint8(clamp(baseC.b.float32 + light * (hiC.b.float32 - baseC.b.float32) * 0.45'f32, 0.0'f32, 255.0'f32)),
        a: 255
      )
    )

  for pass in 0 ..< faces.len:
    for i in 0 ..< (faces.len - 1):
      if faces[i].depth > faces[i + 1].depth:
        swap(faces[i], faces[i + 1])

  let edgeColor = Color(r: skinData.edgeColor.r, g: skinData.edgeColor.g,
                        b: skinData.edgeColor.b, a: 230)
  let innerEdgeColor = Color(r: skinData.glowColor.r, g: skinData.glowColor.g,
                             b: skinData.glowColor.b, a: 110)

  var isFrontFacingByIdx: array[20, bool]
  for face in faces:
    let fn = WallpaperCubePoint(x: face.nx, y: face.ny, z: face.nz)
    let rn = rotateWallpaperCubePoint(fn, angleX, angleY, angleZ)
    isFrontFacingByIdx[face.idx] = rn.z > 0.0'f32

  # Edge pass FIRST: the opaque fills drawn below cover all interior edge glow,
  # leaving only the true silhouette boundary visible. Drawing edges last caused
  # the 2.4px glow halo to bleed outside the filled area at every face vertex.
  for i in 0 ..< 30:
    if isFrontFacingByIdx[D20EdgeFaces[i][0]] or isFrontFacingByIdx[D20EdgeFaces[i][1]]:
      drawLine(projected[D20Edges[i][0]], projected[D20Edges[i][1]], 2.4'f32, innerEdgeColor)
      drawLine(projected[D20Edges[i][0]], projected[D20Edges[i][1]], 1.0'f32, edgeColor)

  const SevenSeg: array[10, array[7, bool]] = [
    [true,  true,  true,  true,  true,  true,  false], # 0: a b c d e f
    [false, true,  true,  false, false, false, false], # 1: b c
    [true,  true,  false, true,  true,  false, true ], # 2: a b d e g
    [true,  true,  true,  true,  false, false, true ], # 3: a b c d g
    [false, true,  true,  false, false, true,  true ], # 4: b c f g
    [true,  false, true,  true,  false, true,  true ], # 5: a c d f g
    [true,  false, true,  true,  true,  true,  true ], # 6: a c d e f g
    [true,  true,  true,  false, false, false, false], # 7: a b c
    [true,  true,  true,  true,  true,  true,  true ], # 8: all
    [true,  true,  true,  true,  false, true,  true ]  # 9: a b c d f g
  ]
  const dHw = 0.115'f32
  const dHh = 0.185'f32
  const dDc = dHw + 0.03'f32

  # Horizontal centre of a seven-seg glyph's actual INK (not its nominal cell).
  # The left column (-hw) is inked by segments a,d,e,f,g and the right column
  # (+hw) by a,b,c,d,g, so "1" (only b,c) lives entirely in the right column and
  # its ink centre is +hw. Centring the cell would leave "1" jammed against the
  # cartouche's right edge (and every tens digit of 10-19 is a "1"); offsetting
  # by -inkCentre lands the drawn strokes on the face centre instead.
  proc inkCentreU(digit: int, hw: float32): float32 =
    let s = SevenSeg[digit]
    let left  = s[0] or s[3] or s[4] or s[5] or s[6]
    let right = s[0] or s[1] or s[2] or s[3] or s[6]
    let uMin = (if left: -hw else: hw)
    let uMax = (if right: hw else: -hw)
    (uMin + uMax) * 0.5'f32

  # Single painter's-order pass: draw each face's fill then immediately its
  # numeral, so a nearer face's fill correctly occludes a farther face's
  # numeral in the overlap region (same principle as the cube skin decorations).
  for face in faces:
    drawTriangleBothWindings(projected[face.corners[0]], projected[face.corners[1]],
                             projected[face.corners[2]], face.color)
    if not isFrontFacingByIdx[face.idx]:
      continue
    let fc3d = WallpaperCubePoint(
      x: (rotated[face.corners[0]].x + rotated[face.corners[1]].x + rotated[face.corners[2]].x) / 3.0'f32,
      y: (rotated[face.corners[0]].y + rotated[face.corners[1]].y + rotated[face.corners[2]].y) / 3.0'f32,
      z: (rotated[face.corners[0]].z + rotated[face.corners[1]].z + rotated[face.corners[2]].z) / 3.0'f32)
    let fcScreen = projectWallpaperCubePoint(fc3d, centerX, centerY, size)

    # Inset triangular bevels and a dark cartouche make the D20 read as an
    # engraved tabletop die rather than flat numbered facets.
    let insetA = Vector2(
      x: projected[face.corners[0]].x * 0.82'f32 + fcScreen.x * 0.18'f32,
      y: projected[face.corners[0]].y * 0.82'f32 + fcScreen.y * 0.18'f32)
    let insetB = Vector2(
      x: projected[face.corners[1]].x * 0.82'f32 + fcScreen.x * 0.18'f32,
      y: projected[face.corners[1]].y * 0.82'f32 + fcScreen.y * 0.18'f32)
    let insetC = Vector2(
      x: projected[face.corners[2]].x * 0.82'f32 + fcScreen.x * 0.18'f32,
      y: projected[face.corners[2]].y * 0.82'f32 + fcScreen.y * 0.18'f32)
    drawLine(insetA, insetB, 1.3'f32, withAlpha(innerEdgeColor, 120'u8))
    drawLine(insetB, insetC, 1.3'f32, withAlpha(innerEdgeColor, 120'u8))
    drawLine(insetC, insetA, 1.3'f32, withAlpha(innerEdgeColor, 120'u8))
    drawLine(insetA, insetB, 0.55'f32, withAlpha(edgeColor, 185'u8))
    drawLine(insetB, insetC, 0.55'f32, withAlpha(edgeColor, 185'u8))
    drawLine(insetC, insetA, 0.55'f32, withAlpha(edgeColor, 185'u8))

    let n = WallpaperCubePoint(x: face.nx, y: face.ny, z: face.nz)
    var refAxis: WallpaperCubePoint
    if abs(n.y) < 0.5'f32:
      refAxis = WallpaperCubePoint(x: 0.0'f32, y: -1.0'f32, z: 0.0'f32)
    else:
      refAxis = WallpaperCubePoint(x: 0.0'f32, y: 0.0'f32, z: 1.0'f32)
    let nDotRef = n.x * refAxis.x + n.y * refAxis.y + n.z * refAxis.z
    var tanUp = WallpaperCubePoint(
      x: refAxis.x - nDotRef * n.x,
      y: refAxis.y - nDotRef * n.y,
      z: refAxis.z - nDotRef * n.z)
    let tanUpLen = sqrt(tanUp.x * tanUp.x + tanUp.y * tanUp.y + tanUp.z * tanUp.z)
    tanUp = WallpaperCubePoint(x: tanUp.x / tanUpLen, y: tanUp.y / tanUpLen,
                               z: tanUp.z / tanUpLen)
    let right3d = WallpaperCubePoint(
      x: n.y * tanUp.z - n.z * tanUp.y,
      y: n.z * tanUp.x - n.x * tanUp.z,
      z: n.x * tanUp.y - n.y * tanUp.x)
    let rUp = rotateWallpaperCubePoint(tanUp, angleX, angleY, angleZ)
    let rRight = rotateWallpaperCubePoint(right3d, angleX, angleY, angleZ)
    let rightEnd = projectWallpaperCubePoint(
      WallpaperCubePoint(x: fc3d.x + rRight.x, y: fc3d.y + rRight.y, z: fc3d.z + rRight.z),
      centerX, centerY, size)
    let upEnd = projectWallpaperCubePoint(
      WallpaperCubePoint(x: fc3d.x + rUp.x, y: fc3d.y + rUp.y, z: fc3d.z + rUp.z),
      centerX, centerY, size)
    let sRx = rightEnd.x - fcScreen.x
    let sRy = rightEnd.y - fcScreen.y
    let sUx = upEnd.x - fcScreen.x
    let sUy = upEnd.y - fcScreen.y
    # Anchor the numeral/cartouche at the on-screen centroid of the projected
    # triangle, NOT at project(centroid3d). A perspective divide preserves
    # cross-ratios, not centroids, so projecting the 3D face center lands biased
    # toward the nearer vertices; on a tilted facet that pushes the number
    # visibly off-centre. The mean of the three projected corners is the true
    # visual centre of the drawn triangle, so the glyph reads centred at every
    # tilt (and is a no-op on face-on facets, where the two points coincide).
    let anchorX = (projected[face.corners[0]].x + projected[face.corners[1]].x +
                   projected[face.corners[2]].x) / 3.0'f32
    let anchorY = (projected[face.corners[0]].y + projected[face.corners[1]].y +
                   projected[face.corners[2]].y) / 3.0'f32
    template fp(u, v: float32): Vector2 =
      Vector2(x: anchorX + sRx * (u) + sUx * (v),
              y: anchorY + sRy * (u) + sUy * (v))
    const CartSeg = 18
    # A true circle in face space (equal u/v radius): it projects to the correctly
    # foreshortened ellipse when the facet is tilted, but reads as a round token
    # face-on rather than a permanently squashed oval. Sized to clear the digit
    # bounding box (corner ~0.22 single / ~0.32 two-digit) with a small margin.
    let cartR = if D20FaceNumbers[face.idx] < 10: 0.26'f32 else: 0.36'f32
    # Fan apex sits on the same anchor as the rim (fp's origin), shared with the
    # ink-centred numeral, so the disc stays centred on the number on every facet.
    let cartCentre = fp(0.0'f32, 0.0'f32)
    var prevCart = fp(cartR, 0.0'f32)
    for c in 1 .. CartSeg:
      let ang = c.float32 / CartSeg.float32 * PI * 2.0'f32
      let curCart = fp(cos(ang) * cartR, sin(ang) * cartR)
      drawTriangleBothWindings(cartCentre, prevCart, curCart, Color(r: 5, g: 4, b: 6, a: 82))
      drawLine(prevCart, curCart, 0.65'f32, withAlpha(edgeColor, 115'u8))
      prevCart = curCart
    template drawDigit(digit: int, du, dv, hw, hh: float32) =
      let seg = SevenSeg[digit]
      if seg[0]:
        drawLine(fp(du - hw, dv + hh), fp(du + hw, dv + hh), 2.2'f32, innerEdgeColor)
        drawLine(fp(du - hw, dv + hh), fp(du + hw, dv + hh), 1.0'f32, edgeColor)
      if seg[1]:
        drawLine(fp(du + hw, dv), fp(du + hw, dv + hh), 2.2'f32, innerEdgeColor)
        drawLine(fp(du + hw, dv), fp(du + hw, dv + hh), 1.0'f32, edgeColor)
      if seg[2]:
        drawLine(fp(du + hw, dv - hh), fp(du + hw, dv), 2.2'f32, innerEdgeColor)
        drawLine(fp(du + hw, dv - hh), fp(du + hw, dv), 1.0'f32, edgeColor)
      if seg[3]:
        drawLine(fp(du - hw, dv - hh), fp(du + hw, dv - hh), 2.2'f32, innerEdgeColor)
        drawLine(fp(du - hw, dv - hh), fp(du + hw, dv - hh), 1.0'f32, edgeColor)
      if seg[4]:
        drawLine(fp(du - hw, dv - hh), fp(du - hw, dv), 2.2'f32, innerEdgeColor)
        drawLine(fp(du - hw, dv - hh), fp(du - hw, dv), 1.0'f32, edgeColor)
      if seg[5]:
        drawLine(fp(du - hw, dv), fp(du - hw, dv + hh), 2.2'f32, innerEdgeColor)
        drawLine(fp(du - hw, dv), fp(du - hw, dv + hh), 1.0'f32, edgeColor)
      if seg[6]:
        drawLine(fp(du - hw, dv), fp(du + hw, dv), 2.2'f32, innerEdgeColor)
        drawLine(fp(du - hw, dv), fp(du + hw, dv), 1.0'f32, edgeColor)
    let value = D20FaceNumbers[face.idx]
    if value < 10:
      drawDigit(value, -inkCentreU(value, dHw), 0.0'f32, dHw, dHh)
    else:
      let tens = value div 10
      let ones = value mod 10
      drawDigit(tens, -dDc - inkCentreU(tens, dHw), 0.0'f32, dHw, dHh)
      drawDigit(ones,  dDc - inkCentreU(ones, dHw), 0.0'f32, dHw, dHh)

proc drawZeroGravityWallpaperCube*(centerX, centerY, size, time,
                                   angleX, angleY, angleZ: float32,
                                   skin: CubeSkinType = cskDefault,
                                   glowBoost: float32 = 0.0'f32) =
  const
    CubeFaces: array[6, array[4, int]] = [
      [0, 1, 2, 3],
      [4, 7, 6, 5],
      [0, 4, 5, 1],
      [3, 2, 6, 7],
      [1, 5, 6, 2],
      [0, 3, 7, 4]
    ]
    CubeEdges: array[12, array[2, int]] = [
      [0, 1], [1, 2], [2, 3], [3, 0],
      [4, 5], [5, 6], [6, 7], [7, 4],
      [0, 4], [1, 5], [2, 6], [3, 7]
    ]

  let cx = centerX
  let cy = centerY
  let pulse = sin(time * 0.72'f32) * 0.5'f32 + 0.5'f32

  drawSoftGlow(cx, cy, size * 2.15'f32,
               Color(r: 0, g: 210, b: 255, a: uint8(34.0'f32 + pulse * 16.0'f32)), 0.6)
  drawCircle(Vector2(x: cx, y: cy), size * 1.36'f32,
             Color(r: 0, g: 180, b: 225, a: 18))

  for i in 0..<5:
    let orbitAngle = time * (0.18'f32 + i.float32 * 0.018'f32) + i.float32 * PI * 0.42'f32
    let orbitRadius = size * (1.42'f32 + i.float32 * 0.09'f32)
    let moteX = cx + cos(orbitAngle) * orbitRadius
    let moteY = cy + sin(orbitAngle * 0.78'f32) * orbitRadius * 0.28'f32
    drawCircle(Vector2(x: moteX, y: moteY), 1.3'f32 + i.float32 * 0.12'f32,
               Color(r: 170, g: 250, b: 255, a: uint8(58 + i * 12)))

  if skin == cskD20:
    # A D20 is a different solid entirely (12 verts/20 tri faces), not a paint
    # job on the cube's 8-vert/6-face geometry, hand off to its own renderer
    # rather than threading icosahedron cases through every branch below that
    # assumes a 6-faced cube (CubeFaces/CubeEdges, the "last 3 faces are
    # camera-facing" trick, etc).
    drawD20WallpaperCube(cx, cy, size, time, angleX, angleY, angleZ, getCubeSkinData(skin))
    return

  var base: array[8, WallpaperCubePoint]
  base[0] = WallpaperCubePoint(x: -1.0, y: -1.0, z: -1.0)
  base[1] = WallpaperCubePoint(x:  1.0, y: -1.0, z: -1.0)
  base[2] = WallpaperCubePoint(x:  1.0, y:  1.0, z: -1.0)
  base[3] = WallpaperCubePoint(x: -1.0, y:  1.0, z: -1.0)
  base[4] = WallpaperCubePoint(x: -1.0, y: -1.0, z:  1.0)
  base[5] = WallpaperCubePoint(x:  1.0, y: -1.0, z:  1.0)
  base[6] = WallpaperCubePoint(x:  1.0, y:  1.0, z:  1.0)
  base[7] = WallpaperCubePoint(x: -1.0, y:  1.0, z:  1.0)

  var rotated: array[8, WallpaperCubePoint]
  var projected: array[8, Vector2]
  for i in 0..<8:
    rotated[i] = rotateWallpaperCubePoint(base[i], angleX, angleY, angleZ)
    projected[i] = projectWallpaperCubePoint(rotated[i], cx, cy, size)

  var faces: array[6, WallpaperCubeFace]
  var useCustomSkin = skin != cskDefault
  var skinDataLocal: CubeSkinData
  if useCustomSkin:
    skinDataLocal = getCubeSkinData(skin)

  for i in 0..<6:
    var avgZ = 0.0'f32
    var nX = 0.0'f32
    var nY = 0.0'f32
    var nZ = 0.0'f32
    for corner in CubeFaces[i]:
      avgZ += rotated[corner].z
      nX += base[corner].x
      nY += base[corner].y
      nZ += base[corner].z
    avgZ /= 4.0'f32          # still drives the painter's-algorithm depth sort
    # Averaging a face's 4 base corners yields its centre = its unit normal (the
    # cube is centred at the origin and axis-aligned), so no normalisation needed.
    nX *= 0.25'f32; nY *= 0.25'f32; nZ *= 0.25'f32

    let light = clamp((nX * LightDirX + nY * LightDirY + nZ * LightDirZ) * 0.5'f32 + 0.5'f32,
                      0.0'f32, 1.0'f32)
    if skin == cskDice:
      # A real die is a solid object, not glass: opaque faces, cleanly shaded per
      # baked side so the cube reads as a solid white body the pips sit on.
      let sh = 0.72'f32 + light * 0.28'f32
      faces[i] = WallpaperCubeFace(
        corners: CubeFaces[i],
        depth: avgZ,
        color: Color(
          r: uint8(clamp(236.0'f32 * sh, 0.0'f32, 255.0'f32)),
          g: uint8(clamp(237.0'f32 * sh, 0.0'f32, 255.0'f32)),
          b: uint8(clamp(242.0'f32 * sh, 0.0'f32, 255.0'f32)),
          a: 255
        )
      )
    elif not useCustomSkin:
      faces[i] = WallpaperCubeFace(
        corners: CubeFaces[i],
        depth: avgZ,
        color: Color(
          r: uint8(18.0'f32 + light * 42.0'f32),
          g: uint8(116.0'f32 + light * 92.0'f32),
          b: uint8(168.0'f32 + light * 70.0'f32),
          a: uint8(84.0'f32 + light * 86.0'f32)
        )
      )
    else:
      let base = skinDataLocal.faceColor
      let hi = skinDataLocal.edgeColor
      let glow = skinDataLocal.glowColor
      let rVal = base.r.float32 + light * (hi.r.float32 - base.r.float32) * 0.35'f32
      let gVal = base.g.float32 + light * (hi.g.float32 - base.g.float32) * 0.35'f32
      let bVal = base.b.float32 + light * (hi.b.float32 - base.b.float32) * 0.35'f32
      let aVal = base.a.float32 * 0.5'f32 + light * (glow.a.float32 * 0.5'f32)
      faces[i] = WallpaperCubeFace(
        corners: CubeFaces[i],
        depth: avgZ,
        color: Color(
          r: uint8(clamp(rVal, 0.0'f32, 255.0'f32)),
          g: uint8(clamp(gVal, 0.0'f32, 255.0'f32)),
          b: uint8(clamp(bVal, 0.0'f32, 255.0'f32)),
          a: uint8(clamp(aVal, 0.0'f32, 255.0'f32))
        )
      )

  for pass in 0..<faces.len:
    for i in 0..<(faces.len - 1):
      if faces[i].depth > faces[i + 1].depth:
        swap(faces[i], faces[i + 1])

  for face in faces:
    drawWallpaperCubeFace(projected, face)

  var edgeColor = Color(r: 190, g: 250, b: 255, a: 220)
  var innerEdgeColor = Color(r: 0, g: 215, b: 255, a: 100)
  if skin != cskDefault:
    edgeColor = withAlpha(skinDataLocal.edgeColor, 220)
    innerEdgeColor = withAlpha(skinDataLocal.glowColor, 100)
  if skin == cskCompanion:
    # The real Companion Cube keeps its color in the hearts only, the edge
    # channels are recessed dark grey, not glowing pink.
    innerEdgeColor = Color(r: 90, g: 93, b: 104, a: 130)
  for edge in CubeEdges:
    drawLine(projected[edge[0]], projected[edge[1]], 4, innerEdgeColor)
    drawLine(projected[edge[0]], projected[edge[1]], 1.5, edgeColor)

  # Companion Cube skin: the Weighted Companion Cube look, a soft-pink heart
  # on a light disc at the center of every visible face. Faces were depth-sorted
  # above, so the last three are the camera-facing ones; each decoration is
  # drawn in its face's projected basis so it foreshortens and tracks the face
  # as the cube tumbles.
  if skin == cskCompanion or skin == cskJack or skin == cskCyber or skin == cskDice:
    let firstFace = if skin == cskJack: 1 else: 3
    let lastFace = if skin == cskJack: 1 else: 5
    for fi in firstFace .. lastFace:
      let c0 = (if skin == cskJack: CubeFaces[fi][0] else: faces[fi].corners[0])
      let c1 = (if skin == cskJack: CubeFaces[fi][1] else: faces[fi].corners[1])
      let c2 = (if skin == cskJack: CubeFaces[fi][2] else: faces[fi].corners[2])
      let c3 = (if skin == cskJack: CubeFaces[fi][3] else: faces[fi].corners[3])
      # Build a *canonical* tangent frame for the heart instead of reading it
      # off the face's corner winding (which differs per face, so the hearts
      # used to point every which way). The face normal in cube space is just
      # the face centre (the cube is centred at the origin), an axis unit vector.
      let n = WallpaperCubePoint(
        x: (base[c0].x + base[c1].x + base[c2].x + base[c3].x) * 0.25'f32,
        y: (base[c0].y + base[c1].y + base[c2].y + base[c3].y) * 0.25'f32,
        z: (base[c0].z + base[c1].z + base[c2].z + base[c3].z) * 0.25'f32)
      # Choose a consistent "up". Screen-up is world -Y in this projection (the
      # cube uses a y-down basis), so the four side faces take up = -Y: their
      # hearts all sit upright and point toward the cube's top ring. The
      # top/bottom faces (normal ±Y) have no in-plane vertical, so they fall
      # back to +Z, tying into that ring. right = up x normal keeps a uniform
      # handedness, so a camera-facing face always projects to a positive area.
      var up3d: WallpaperCubePoint
      if abs(n.y) < 0.5'f32:
        up3d = WallpaperCubePoint(x: 0.0'f32, y: -1.0'f32, z: 0.0'f32)
      else:
        up3d = WallpaperCubePoint(x: 0.0'f32, y: 0.0'f32, z: 1.0'f32)
      let right3d = WallpaperCubePoint(
        x: up3d.y * n.z - up3d.z * n.y,
        y: up3d.z * n.x - up3d.x * n.z,
        z: up3d.x * n.y - up3d.y * n.x)

      # Rotate the tangents with the cube and project them as screen vectors, so
      # the heart stays painted on (foreshortens, attached) while keeping its
      # consistent orientation. Each tangent is a unit cube axis = one face
      # half-edge, so the projected basis matches the heart's previous size.
      let rUp = rotateWallpaperCubePoint(up3d, angleX, angleY, angleZ)
      let rRight = rotateWallpaperCubePoint(right3d, angleX, angleY, angleZ)
      let fc3d = WallpaperCubePoint(
        x: (rotated[c0].x + rotated[c1].x + rotated[c2].x + rotated[c3].x) * 0.25'f32,
        y: (rotated[c0].y + rotated[c1].y + rotated[c2].y + rotated[c3].y) * 0.25'f32,
        z: (rotated[c0].z + rotated[c1].z + rotated[c2].z + rotated[c3].z) * 0.25'f32)
      let fcScreen = projectWallpaperCubePoint(fc3d, cx, cy, size)
      let rightEnd = projectWallpaperCubePoint(
        WallpaperCubePoint(x: fc3d.x + rRight.x, y: fc3d.y + rRight.y, z: fc3d.z + rRight.z),
        cx, cy, size)
      let upEnd = projectWallpaperCubePoint(
        WallpaperCubePoint(x: fc3d.x + rUp.x, y: fc3d.y + rUp.y, z: fc3d.z + rUp.z),
        cx, cy, size)
      let sRx = rightEnd.x - fcScreen.x
      let sRy = rightEnd.y - fcScreen.y
      let sUx = upEnd.x - fcScreen.x
      let sUy = upEnd.y - fcScreen.y

      # Back-face cull. The cube body is translucent, so most skins only draw on
      # the camera-facing side. Jack is intentionally exempt so the carved face
      # still reads through the cube when that side rotates away.
      if skin != cskJack and sRx * sUy - sRy * sUx <= 0.0'f32:
        continue

      if skin == cskJack:
        # Jack-O'-Node: carve a glowing face into one fixed side. Features are
        # laid out in the face-local (right, up) basis so they foreshorten and
        # ride the cube as it tumbles, exactly like the Companion heart.
        template fp(u, v: float32): Vector2 =
          Vector2(x: fcScreen.x + sRx * (u) + sUx * (v),
                  y: fcScreen.y + sRy * (u) + sUy * (v))
        # Spinning the pumpkin on the Kernel Panic background fans the candle:
        # glowBoost (0..1) brightens the bloom and warms the carved features toward
        # a fierce white-hot grin. Stays baked per-face (no screen-space halo).
        let gb = clamp(glowBoost, 0.0'f32, 1.0'f32)
        let glowMul = 1.0'f32 + gb * 3.6'f32
        let candle = Color(r: 255,
                           g: uint8(min(255.0'f32, 225.0'f32 + gb * 30.0'f32)),
                           b: uint8(min(255.0'f32, 120.0'f32 + gb * 125.0'f32)), a: 255)
        # Candlelight baked onto the face: concentric translucent discs drawn in
        # the face's own (right, up) plane via fp(), so the bloom foreshortens and
        # rides each side like the carving (a screen-space glow looked detached
        # and floated off the cube as it tumbled). Layered large->small, deep
        # orange at the rim to bright candle at the core; the overlap stacks into
        # a soft radial falloff. Gently flickers. Drawn before the opaque features
        # so they stay crisp on top.
        # Flicker harder the more it is fanned, so a charged jack visibly seethes.
        let flick = (0.74'f32 + 0.26'f32 * sin(time * 6.3'f32 + fi.float32 * 1.7'f32)) *
                    (1.0'f32 + gb * 0.35'f32 * sin(time * 13.0'f32 + fi.float32))
        const GlowRings = 9
        const GlowSeg = 24
        for g in 0 ..< GlowRings:
          let gf = g.float32 / GlowRings.float32
          let rr = 0.95'f32 * (1.0'f32 - gf)
          let gc = Color(r: 255,
                         g: uint8(135.0'f32 + gf * 105.0'f32),
                         b: uint8(20.0'f32 + gf * 95.0'f32),
                         a: uint8(min(255.0'f32, (12.0'f32 + gf * 12.0'f32) * flick * glowMul)))
          var prevG = fp(rr, 0.0'f32)
          for s in 1 .. GlowSeg:
            let ang = s.float32 / GlowSeg.float32 * PI * 2.0'f32
            let curG = fp(cos(ang) * rr, sin(ang) * rr)
            drawTriangleBothWindings(fcScreen, prevG, curG, gc)
            prevG = curG
        # Two triangular eyes and a small triangular nose.
        drawTriangleBothWindings(fp(-0.34'f32, 0.32'f32), fp(-0.12'f32, 0.32'f32),
                                 fp(-0.23'f32, 0.10'f32), candle)
        drawTriangleBothWindings(fp(0.12'f32, 0.32'f32), fp(0.34'f32, 0.32'f32),
                                 fp(0.23'f32, 0.10'f32), candle)
        drawTriangleBothWindings(fp(-0.08'f32, 0.06'f32), fp(0.08'f32, 0.06'f32),
                                 fp(0.0'f32, -0.07'f32), candle)
        # Toothy grin: a smiling band whose lower edge zigzags into teeth.
        const MTeeth = 6
        var prevTop, prevBot: Vector2
        for i in 0 .. MTeeth:
          let f = i.float32 / MTeeth.float32
          let u = -0.40'f32 + 0.80'f32 * f
          let smile = (u / 0.40'f32) * (u / 0.40'f32)         # 0 centre, 1 corners
          let vTop = -0.16'f32 - 0.14'f32 * (1.0'f32 - smile) # corners ride up
          let vBot = vTop - (if i mod 2 == 0: 0.12'f32 else: 0.05'f32)
          let curTop = fp(u, vTop)
          let curBot = fp(u, vBot)
          if i > 0:
            drawTriangleBothWindings(prevTop, curTop, prevBot, candle)
            drawTriangleBothWindings(curTop, curBot, prevBot, candle)
          prevTop = curTop
          prevBot = curBot
        continue

      if skin == cskCyber:
        # Cyberdeck: a holographic HUD panel projected on each face, a baked
        # cyan glow, an inset neon frame with magenta corner brackets, scanline
        # ticks, and a pulsing centre node. Drawn in the face's (right,up) basis
        # via fp() so it foreshortens and rides the face like a real projection.
        template fp(u, v: float32): Vector2 =
          Vector2(x: fcScreen.x + sRx * (u) + sUx * (v),
                  y: fcScreen.y + sRy * (u) + sUy * (v))
        let cyan = Color(r: 80, g: 245, b: 255, a: 255)
        let mag  = Color(r: 255, g: 60,  b: 200, a: 255)
        let pulseC = 0.6'f32 + 0.4'f32 * sin(time * 3.0'f32 + fi.float32 * 2.0'f32)
        # Baked cyan hologram glow (concentric discs, large->small, stacked).
        const CRings = 7
        const CSeg = 22
        for g in 0 ..< CRings:
          let gf = g.float32 / CRings.float32
          let rr = 0.85'f32 * (1.0'f32 - gf)
          let gc = Color(r: uint8(40.0'f32 + gf * 40.0'f32), g: 245, b: 255,
                         a: uint8((9.0'f32 + gf * 9.0'f32) * pulseC))
          var prevG = fp(rr, 0.0'f32)
          for s in 1 .. CSeg:
            let ang = s.float32 / CSeg.float32 * PI * 2.0'f32
            let curG = fp(cos(ang) * rr, sin(ang) * rr)
            drawTriangleBothWindings(fcScreen, prevG, curG, gc)
            prevG = curG
        # Inset neon frame (cyan) with a soft glow underlay.
        const pin = 0.6'f32
        let frame = [fp(-pin, -pin), fp(pin, -pin), fp(pin, pin), fp(-pin, pin)]
        for k in 0 .. 3:
          let a0 = frame[k]
          let a1 = frame[(k + 1) mod 4]
          drawLine(a0, a1, 3.0'f32, Color(r: 80, g: 245, b: 255, a: 55))
          drawLine(a0, a1, 1.3'f32, cyan)
        # Magenta corner brackets: short L-arms inset from each corner.
        const bl = 0.22'f32
        const cornerSigns = [(-1.0'f32, -1.0'f32), (1.0'f32, -1.0'f32),
                             (1.0'f32, 1.0'f32), (-1.0'f32, 1.0'f32)]
        for c in cornerSigns:
          let cu = c[0] * pin
          let cv = c[1] * pin
          drawLine(fp(cu, cv), fp(cu - c[0] * bl, cv), 2.2'f32, mag)
          drawLine(fp(cu, cv), fp(cu, cv - c[1] * bl), 2.2'f32, mag)
        # Faint scanline ticks across the panel.
        for r in 0 .. 2:
          let vv = -0.30'f32 + r.float32 * 0.30'f32
          drawLine(fp(-0.45'f32, vv), fp(0.45'f32, vv), 1.0'f32,
                   Color(r: 80, g: 245, b: 255, a: 65))
        # Pulsing centre node: cyan ring with a magenta core.
        let nodeR = (3.0'f32 + 2.0'f32 * pulseC) * (size / 60.0'f32)
        drawCircle(fcScreen, max(1.0'f32, nodeR * 1.7'f32),
                   Color(r: 80, g: 245, b: 255, a: 120))
        drawCircle(fcScreen, max(0.7'f32, nodeR), mag)
        continue

      if skin == cskDice:
        # Classic die: each physical face shows its pip count, identified by the
        # model-space normal n so the number is baked to that side (opposite faces
        # sum to 7). Pips are dark dots placed in the face's (right,up) basis via
        # fp(), foreshortening with the cube.
        template fp(u, v: float32): Vector2 =
          Vector2(x: fcScreen.x + sRx * (u) + sUx * (v),
                  y: fcScreen.y + sRy * (u) + sUy * (v))
        let pip =
          if   n.z >  0.5'f32: 1
          elif n.z < -0.5'f32: 6
          elif n.x >  0.5'f32: 2
          elif n.x < -0.5'f32: 5
          elif n.y >  0.5'f32: 3
          else: 4
        const d = 0.30'f32
        var spots: seq[(float32, float32)]
        case pip
        of 1: spots = @[(0.0'f32, 0.0'f32)]
        of 2: spots = @[(-d, -d), (d, d)]
        of 3: spots = @[(-d, -d), (0.0'f32, 0.0'f32), (d, d)]
        of 4: spots = @[(-d, -d), (d, -d), (-d, d), (d, d)]
        of 5: spots = @[(-d, -d), (d, -d), (0.0'f32, 0.0'f32), (-d, d), (d, d)]
        else: spots = @[(-d, -d), (d, -d), (-d, 0.0'f32), (d, 0.0'f32), (-d, d), (d, d)]
        # Each pip is a filled disc in face-local units, drawn as a triangle fan
        # through fp(): because fp projects the face plane, the disc comes out as a
        # foreshortened ellipse painted ON the face, not a flat screen-facing dot.
        # Radius capped under half the 0.30 pip spacing so the "6" never overlaps.
        const pr = 0.14'f32
        const PipSeg = 14
        let pipCol = Color(r: 28, g: 28, b: 34, a: 255)
        for sp in spots:
          let centre = fp(sp[0], sp[1])
          var prevP = fp(sp[0] + pr, sp[1])
          for s in 1 .. PipSeg:
            let ang = s.float32 / PipSeg.float32 * PI * 2.0'f32
            let curP = fp(sp[0] + cos(ang) * pr, sp[1] + sin(ang) * pr)
            drawTriangleBothWindings(centre, prevP, curP, pipCol)
            prevP = curP
        continue

      # Light recessed disc behind the heart (a circle in the face plane).
      let discColor = Color(r: 222, g: 224, b: 229, a: 255)
      var prevDisc = Vector2(x: fcScreen.x + sRx * 0.55'f32, y: fcScreen.y + sRy * 0.55'f32)
      for i in 1 .. 12:
        let a = i.float32 / 12.0'f32 * PI * 2.0'f32
        let dx = cos(a) * 0.55'f32
        let dy = sin(a) * 0.55'f32
        let cur = Vector2(x: fcScreen.x + sRx * dx + sUx * dy,
                          y: fcScreen.y + sRy * dx + sUy * dy)
        drawTriangleBothWindings(fcScreen, prevDisc, cur, discColor)
        prevDisc = cur

      # Classic parametric heart: width along the face's right axis, height
      # along its up axis (negated so the point sits toward the bottom edge and
      # the lobes: the heart's top toward the up edge on every face).
      let heartColor = Color(r: 244, g: 116, b: 150, a: 255)
      var prevHeart = fcScreen  # placeholder; set from the i = 0 sample below
      var first = true
      for i in 0 .. 24:
        let t = i.float32 / 24.0'f32 * PI * 2.0'f32
        let hx = 0.34'f32 * (16.0'f32 * pow(sin(t), 3.0'f32)) / 17.0'f32
        let yc = (13.0'f32 * cos(t) - 5.0'f32 * cos(2.0'f32 * t) -
                  2.0'f32 * cos(3.0'f32 * t) - cos(4.0'f32 * t)) / 17.0'f32
        let hy = (-yc - 0.15'f32) * 0.34'f32
        let cur = Vector2(x: fcScreen.x + sRx * hx - sUx * hy,
                          y: fcScreen.y + sRy * hx - sUy * hy)
        if not first:
          drawTriangleBothWindings(fcScreen, prevHeart, cur, heartColor)
        prevHeart = cur
        first = false

proc drawDesktopWallpaper*(screenWidth, screenHeight: int, time,
                          cubeRotX, cubeRotY, cubeRotZ: float32,
                          cubeOffsetX: float32 = 0.0, cubeOffsetY: float32 = 0.0) =
  drawSharedBackdrop(screenWidth.int32, screenHeight.int32, time * 0.62,
                     Color(r: 5, g: 8, b: 18, a: 255),
                     Color(r: 18, g: 17, b: 34, a: 255),
                     Color(r: 38, g: 54, b: 78, a: 34),
                     Color(r: 95, g: 130, b: 174, a: 70),
                     Color(r: 0, g: 184, b: 225, a: 48),
                     0.9, 0.8)

  let w = screenWidth.float32
  let h = screenHeight.float32
  let centerX = w * 0.64
  let centerY = h * 0.46

  drawSoftGlow(centerX, centerY, min(w, h) * 0.42,
               Color(r: 0, g: 170, b: 220, a: 70), 0.7)
  drawSoftGlow(w * 0.18, h * 0.18, min(w, h) * 0.28,
               Color(r: 95, g: 130, b: 255, a: 56), 0.55)
  drawSoftGlow(w * 0.88, h * 0.82, min(w, h) * 0.30,
               Color(r: 0, g: 220, b: 165, a: 46), 0.5)

  # Orbital rings behind the desktop make the menu feel like a live command surface.
  for i in 0..4:
    let ringRadius = min(w, h) * (0.18 + i.float32 * 0.055)
    let alpha = uint8(26 + i * 9)
    drawCircleLines(Vector2(x: centerX, y: centerY), ringRadius,
                    Color(r: 80, g: 210, b: 255, a: alpha))
    let angle = time * (0.22 + i.float32 * 0.04) + i.float32 * PI * 0.38
    let nodeX = centerX + cos(angle) * ringRadius
    let nodeY = centerY + sin(angle) * ringRadius
    drawCircle(Vector2(x: nodeX, y: nodeY), 3.0 + i.float32 * 0.35,
               Color(r: 165, g: 245, b: 255, a: uint8(120 + i * 18)))

  let currentCubeSkin = if not globalSettings.isNil: CubeSkinType(globalSettings.cubeSkin) else: cskDefault
  drawZeroGravityWallpaperCube(centerX + cubeOffsetX, centerY + cubeOffsetY,
                               min(w, h) * 0.042'f32, time,
                               cubeRotX, cubeRotY, cubeRotZ, currentCubeSkin)

  # Thin scan bands and routing traces.
  for i in 0..<14:
    let y = ((i.float32 * 67.0 + time * (16.0 + i.float32 * 1.7)) mod (h + 90.0)) - 45.0
    let sway = sin(time * 0.7 + i.float32) * 32.0
    let alpha = uint8(18 + (i mod 4) * 8)
    drawLine(Vector2(x: -40.0, y: y),
             Vector2(x: w + 40.0, y: y + sway * 0.18),
             1, Color(r: 0, g: 198, b: 238, a: alpha))
    if i mod 3 == 0:
      let x = (w * (0.22 + (i mod 5).float32 * 0.13) + sway) mod max(w, 1.0)
      drawLine(Vector2(x: x, y: y - 28.0),
               Vector2(x: x, y: y + 32.0),
               1, Color(r: 85, g: 240, b: 255, a: uint8(alpha + 28)))
      drawCircle(Vector2(x: x, y: y), 2.6, Color(r: 180, g: 250, b: 255, a: 130))

  # Left-side launch column silhouette keeps icons readable over the animation.
  drawRectangleGradientH(0, 0, min(310, screenWidth).int32, screenHeight.int32,
                         Color(r: 2, g: 5, b: 12, a: 155),
                         Color(r: 2, g: 5, b: 12, a: 0))
  drawLine(Vector2(x: 250.0, y: 42.0),
           Vector2(x: 250.0 + sin(time * 0.9) * 10.0, y: h - 74.0),
           1, Color(r: 70, g: 230, b: 255, a: 64))

proc simUsage(time, base, amp, speed, phase: float32): float32 =
  ## Smooth pseudo-load for the decorative System Monitor: two layered sines so
  ## the curve drifts slowly without looking obviously periodic. Not real data.
  let v = base + sin(time * speed + phase) * amp +
                 sin(time * speed * 2.7'f32 + phase * 1.7'f32) * amp * 0.35'f32
  clamp(v, 2.0'f32, 99.0'f32)

proc drawUsageRow(panelX, panelW, y: int32, label: string, pct: float32, color: Color) =
  ## One System-Monitor line: label, a tracked fill bar with a bright leading
  ## cap, and the percentage.
  drawText(label, panelX + 9, y, 12, color)
  let barX = panelX + 58
  let barW = panelW - 58 - 44
  let barY = y + 2
  const barH = 9'i32
  # Track + quarter ticks
  drawRectangle(barX, barY, barW, barH, Color(r: 20, g: 28, b: 42, a: 235))
  for q in 1 .. 3:
    drawRectangle(barX + (barW * q.int32) div 4, barY, 1, barH,
                  Color(r: 0, g: 70, b: 90, a: 150))
  # Fill, top highlight, bright cap + glow
  let fillW = int32(barW.float32 * clamp(pct, 0.0'f32, 100.0'f32) / 100.0'f32)
  if fillW > 1:
    drawRectangle(barX, barY, fillW, barH, withAlpha(color, 205))
    drawRectangle(barX, barY, fillW, 1,
                  Color(r: uint8(min(255, color.r.int + 60)),
                        g: uint8(min(255, color.g.int + 60)),
                        b: uint8(min(255, color.b.int + 60)), a: 220))
    let capX = barX + fillW
    drawRectangle(capX - 2, barY, 2, barH, Color(r: 255, g: 255, b: 255, a: 170))
    drawSoftGlow(capX.float32, (barY + barH div 2).float32, 7.0'f32,
                 withAlpha(color, 130), 1.0'f32)
  drawRectangleLines(Rectangle(x: barX.float32, y: barY.float32,
                               width: barW.float32, height: barH.float32), 1,
                     Color(r: 0, g: 90, b: 110, a: 150))
  # Percentage, right-aligned
  let pStr = $int(pct + 0.5'f32) & "%"
  drawText(pStr, panelX + panelW - 9 - measureText(pStr, 12), y, 12, color)

proc drawHorrorWatchers(cx, cy, cubeSize, w, h, time, glow: float32) =
  ## Kernel Panic reveal (only fires for the spun Jack-O'-Node, the one combo this
  ## easter egg works on): as the candle is fanned (glow 0..1) the lantern throws
  ## warm light into the dark room and things in the black wake up - pairs of
  ## sickly eyes open and watch the cube, and a red dread bleeds in from the edges.
  let g = clamp(glow, 0.0'f32, 1.0'f32)
  if g <= 0.02'f32: return
  let s = min(w, h)

  # 1. The lantern casting flickering light into the room (a halo of *cast* light
  #    around the cube - the pumpkin lighting its surroundings, not face shading).
  let flick = 0.78'f32 + 0.22'f32 * sin(time * 7.3'f32) + 0.08'f32 * sin(time * 17.0'f32)
  drawSoftGlow(cx, cy, cubeSize * (2.6'f32 + g * 5.0'f32),
               Color(r: 255, g: 145, b: 35, a: uint8(min(255.0'f32, 80.0'f32 * g * flick))), 0.7)
  drawSoftGlow(cx, cy, cubeSize * (1.5'f32 + g * 2.4'f32),
               Color(r: 255, g: 195, b: 95, a: uint8(min(255.0'f32, 70.0'f32 * g * flick))), 0.85)

  # 2. Eyes opening in the surrounding darkness, kept clear of the centre where the
  #    cube sits. Each watcher wakes at a slightly higher glow, so they open in
  #    sequence as the candle flares, and blink now and then.
  const Haunts = 7
  const hx = [0.16'f32, 0.86'f32, 0.09'f32, 0.93'f32, 0.40'f32, 0.74'f32, 0.28'f32]
  const hy = [0.20'f32, 0.15'f32, 0.66'f32, 0.60'f32, 0.87'f32, 0.86'f32, 0.40'f32]
  const hsz = [0.95'f32, 1.25'f32, 1.05'f32, 0.8'f32, 1.15'f32, 0.7'f32, 0.6'f32]
  for k in 0 ..< Haunts:
    let seed = k.float32 * 12.9898'f32
    let wake = clamp((g - 0.12'f32 - 0.085'f32 * k.float32) / 0.32'f32, 0.0'f32, 1.0'f32)
    if wake <= 0.0'f32: continue
    let ex = hx[k] * w
    let ey = hy[k] * h
    let sc = s * 0.032'f32 * hsz[k]
    let bt = sin(time * (0.6'f32 + 0.4'f32 * abs(sin(seed))) + seed * 9.0'f32)
    let blink = if bt > 0.86'f32: max(0.06'f32, 1.0'f32 - (bt - 0.86'f32) / 0.14'f32) else: 1.0'f32
    let open = wake * blink
    let eyeA = uint8(225.0'f32 * wake)
    let glowA = uint8(80.0'f32 * wake)
    let eyeCol  = Color(r: 205, g: 220, b: 95, a: eyeA)
    let darkSlit = Color(r: 9, g: 13, b: 6, a: eyeA)
    let sway = sin(time * 0.5'f32 + seed) * sc * 0.1'f32
    for side in [-1.0'f32, 1.0'f32]:
      let eex = ex + side * sc * 1.05'f32 + sway
      drawSoftGlow(eex, ey, sc * 1.35'f32, Color(r: 175, g: 210, b: 70, a: glowA), 0.6)
      drawEllipse(eex.int32, ey.int32, sc * 0.72'f32, max(0.5'f32, sc * 0.46'f32 * open), eyeCol)
      drawEllipse(eex.int32, ey.int32, sc * 0.16'f32, max(0.5'f32, sc * 0.4'f32 * open), darkSlit)

  # 3. Red dread bleeding in from the edges, pulsing with the glow.
  let dread = uint8(min(255.0'f32, 150.0'f32 * g * (0.7'f32 + 0.3'f32 * sin(time * 2.0'f32))))
  let clear = Color(r: 0, g: 0, b: 0, a: 0)
  let blood = Color(r: 110, g: 6, b: 8, a: dread)
  let vw = w * 0.28'f32
  let vh = h * 0.28'f32
  drawRectangleGradientH(0, 0, vw.int32, h.int32, blood, clear)
  drawRectangleGradientH(int32(w - vw), 0, vw.int32, h.int32, clear, blood)
  drawRectangleGradientV(0, 0, w.int32, vh.int32, blood, clear)
  drawRectangleGradientV(0, int32(h - vh), w.int32, vh.int32, clear, blood)

proc drawOSDesktop*(desktop: OSDesktop, screenWidth, screenHeight: int) =
  ## Draw the active desktop background. If the player has selected a desktop
  ## background from settings/shop use that otherwise fall back to the
  ## original hardcoded wallpaper.
  var selectedBg: DesktopBgType = dbgDefault
  if not globalSettings.isNil:
    selectedBg = DesktopBgType(globalSettings.desktopBg)

  case selectedBg
  of dbgDefault:
    # Exact, hardcoded wallpaper (keeps cube rotations and all effects)
    drawDesktopWallpaper(screenWidth, screenHeight, desktop.time,
                         desktop.cubeRotX, desktop.cubeRotY, desktop.cubeRotZ,
                         desktop.cubeOffsetX, desktop.cubeOffsetY)
  else:
    let bgData = getDesktopBgData(selectedBg)
    let topColor = bgData.bgColor
    let bottomColor = brighten(topColor, -(12), topColor.a.int)
    let gridColor = Color(r: uint8((bgData.primaryColor.r.int + bgData.accentColor.r.int) div 2),
                          g: uint8((bgData.primaryColor.g.int + bgData.accentColor.g.int) div 2),
                          b: uint8((bgData.primaryColor.b.int + bgData.accentColor.b.int) div 2),
                          a: 34)
    let nodeColor = bgData.accentColor
    let accentColor = bgData.primaryColor
    let w = screenWidth.float32
    let h = screenHeight.float32

    # Draw the shared backdrop at 1/6th the virtual canvas size so the grid
    # cell count and star density match what the shop preview miniature shows.
    # The fixed-size elements (48 px grid, 48 stars) are otherwise spread too
    # thin at 1024x768 compared to the 170x64 shop card.
    let refW = int32(ceil(w / 6.0'f32))
    let refH = int32(ceil(h / 6.0'f32))
    pushMatrix()
    scalef(w / refW.float32, h / refH.float32, 1.0'f32)
    drawSharedBackdrop(refW, refH, desktop.time * 0.62,
                       topColor, bottomColor, gridColor, nodeColor, accentColor,
                       0.9, 0.8)
    popMatrix()

    drawSoftGlow(w * 0.64, h * 0.46, min(w, h) * 0.42,
                 withAlpha(accentColor, 70), 0.7)
    drawSoftGlow(w * 0.18, h * 0.18, min(w, h) * 0.28,
                 withAlpha(nodeColor, 56), 0.55)
    drawSoftGlow(w * 0.88, h * 0.82, min(w, h) * 0.30,
                 withAlpha(bgData.primaryColor, 46), 0.5)

    drawDesktopBgThemeFx(selectedBg, screenWidth.int32, screenHeight.int32, desktop.time)

    for i in 0..3:
      let ringRadius = min(w, h) * (0.18 + i.float32 * 0.055)
      let alpha = uint8(26 + i * 9)
      drawCircleLines(Vector2(x: w * 0.64, y: h * 0.46), ringRadius,
                      withAlpha(accentColor, alpha))
      let nodeAngle = desktop.time * (0.22 + i.float32 * 0.04) + i.float32 * PI * 0.38
      drawCircle(Vector2(x: w * 0.64 + cos(nodeAngle) * ringRadius,
                         y: h * 0.46 + sin(nodeAngle) * ringRadius),
                 3.0 + i.float32 * 0.35,
                 withAlpha(nodeColor, uint8(120 + i * 18)))

    let centerX = w * 0.64
    let centerY = h * 0.46
    let currentCubeSkin = if not globalSettings.isNil: CubeSkinType(globalSettings.cubeSkin) else: cskDefault

    # Kernel Panic: the cube cowers. A constant high-frequency jitter (terror)
    # with an occasional larger flinch, layered ON TOP of cubeOffsetX/Y so the
    # orbital-escape easter egg still owns that state. Suppressed mid-escape so
    # the cube can fly cleanly. Stateless: derived purely from desktop.time, the
    # same trick the escape "strain" shudder uses.
    var tremX, tremY = 0.0'f32
    if selectedBg == dbgHorror and not desktop.cubeEscaping and
       currentCubeSkin != cskJack:
      let t = desktop.time
      let flinch = 1.0'f32 + 1.0'f32 * max(0.0'f32, sin(t * 0.9'f32) - 0.6'f32)
      let amp = min(w, h) * 0.001'f32 * flinch
      tremX = (sin(t * 53.0'f32) + 0.5'f32 * sin(t * 89.0'f32)) * amp
      tremY = (cos(t * 61.0'f32) + 0.5'f32 * sin(t * 97.0'f32)) * amp

    # Kernel Panic + spun Jack-O'-Node: reveal the watchers in the dark behind the
    # cube before drawing it, so the lantern light and eyes sit underneath.
    if selectedBg == dbgHorror and desktop.cubeJackGlow > 0.01'f32:
      drawHorrorWatchers(centerX, centerY, min(w, h) * 0.042'f32,
                         w, h, desktop.time, desktop.cubeJackGlow)

    drawZeroGravityWallpaperCube(centerX + desktop.cubeOffsetX + tremX,
                                 centerY + desktop.cubeOffsetY + tremY,
                                 min(w, h) * 0.042'f32, desktop.time,
                                 desktop.cubeRotX, desktop.cubeRotY, desktop.cubeRotZ,
                                 currentCubeSkin, desktop.cubeJackGlow)

    # Dice roll result: a big gold number that pops above the settled die.
    if desktop.cubeDiceResultTimer > 0.0'f32 and desktop.cubeDiceResult > 0:
      let fade = min(1.0'f32, desktop.cubeDiceResultTimer / 0.6'f32)
      let a = uint8(255.0'f32 * fade)
      let label = $desktop.cubeDiceResult
      let fs = int32(min(w, h) * 0.16'f32)
      let lw = measureText(label, fs)
      let lx = int32(centerX) - lw div 2
      let ly = int32(centerY - min(w, h) * 0.20'f32) - fs div 2
      drawText(label, lx + 3, ly + 3, fs, Color(r: 0, g: 0, b: 0, a: uint8(160.0'f32 * fade)))
      drawText(label, lx, ly, fs, Color(r: 255, g: 215, b: 90, a: a))

  # Desktop icons
  for icon in desktop.icons:
    drawDesktopIcon(icon, desktop.time, icon.selected)

  # Taskbar
  drawTaskbar(screenWidth, screenHeight, desktop.time)

  # ---- System Monitor widget (top-right) ----------------------------------
  # Decorative readout: the bars show smoothly-drifting simulated load so the
  # panel feels alive. Only Uptime is real (desktop session time).
  let panelW = 240'i32
  let panelH = 128'i32
  let panelX = (screenWidth - panelW.int - 14).int32
  let panelY = 12'i32
  let tm = desktop.time

  # Depth halo, gradient body, crisp border
  drawSoftGlow((panelX + panelW div 2).float32, (panelY + panelH div 2).float32,
               panelW.float32 * 0.62'f32, Color(r: 0, g: 120, b: 150, a: 24), 1.0'f32)
  drawRectangleGradientV(panelX, panelY, panelW, panelH,
                         Color(r: 18, g: 26, b: 38, a: 222),
                         Color(r: 9, g: 13, b: 22, a: 222))
  drawRectangleLines(Rectangle(x: panelX.float32, y: panelY.float32,
                               width: panelW.float32, height: panelH.float32), 1,
                     Color(r: 0, g: 180, b: 190, a: 210))
  # Corner accents
  let corner = Color(r: 0, g: 235, b: 235, a: 235)
  const cl = 10'i32
  drawRectangle(panelX, panelY, cl, 2, corner)
  drawRectangle(panelX, panelY, 2, cl, corner)
  drawRectangle(panelX + panelW - cl, panelY, cl, 2, corner)
  drawRectangle(panelX + panelW - 2, panelY, 2, cl, corner)
  drawRectangle(panelX, panelY + panelH - 2, cl, 2, corner)
  drawRectangle(panelX, panelY + panelH - cl, 2, cl, corner)
  drawRectangle(panelX + panelW - cl, panelY + panelH - 2, cl, 2, corner)
  drawRectangle(panelX + panelW - 2, panelY + panelH - cl, 2, cl, corner)

  # Title bar with a pulsing "live" dot
  drawRectangleGradientV(panelX + 1, panelY + 1, panelW - 2, 21,
                         Color(r: 0, g: 56, b: 78, a: 235),
                         Color(r: 0, g: 32, b: 48, a: 235))
  drawText(t(tkOSSystemMonitor), panelX + 9, panelY + 5, 14,
           Color(r: 120, g: 235, b: 235, a: 255))
  let pulse = sin(tm * 3.0'f32) * 0.5'f32 + 0.5'f32
  drawCircle(Vector2(x: (panelX + panelW - 16).float32, y: (panelY + 11).float32),
             4.0'f32, Color(r: 70, g: 255, b: 120, a: uint8(110.0'f32 + pulse * 145.0'f32)))

  # CPU sparkline (scrolling filled waveform)
  let gx = panelX + 9
  let gy = panelY + 30
  let gw = panelW - 18
  const gh = 30'i32
  drawRectangle(gx, gy, gw, gh, Color(r: 8, g: 14, b: 22, a: 215))
  for i in 0 ..< gw.int:
    let v = simUsage(tm - (gw.int - i).float32 * 0.05'f32,
                     40.0'f32, 3.5'f32, 0.12'f32, 0.0'f32) / 100.0'f32
    let h = int32(v * gh.float32)
    drawRectangle(gx + i.int32, gy + gh - h, 1, h, Color(r: 0, g: 190, b: 160, a: 70))
    drawRectangle(gx + i.int32, gy + gh - h, 1, 1, Color(r: 90, g: 255, b: 210, a: 200))
  drawRectangleLines(Rectangle(x: gx.float32, y: gy.float32,
                               width: gw.float32, height: gh.float32), 1,
                     Color(r: 0, g: 80, b: 100, a: 140))

  # Metric bars
  var rowY = panelY + 68
  drawUsageRow(panelX, panelW, rowY, "CPU",
               simUsage(tm, 40.0'f32, 3.5'f32, 0.12'f32, 0.0'f32),
               Color(r: 80, g: 230, b: 120, a: 255))
  rowY += 20
  drawUsageRow(panelX, panelW, rowY, t(tkOSMemory),
               simUsage(tm, 40.0'f32, 2.5'f32, 0.08'f32, 2.0'f32),
               Color(r: 90, g: 180, b: 255, a: 255))

  # Uptime (real desktop session time)
  let uptime = int(desktop.time)
  let hours = uptime div 3600
  let minutes = (uptime mod 3600) div 60
  let seconds = uptime mod 60
  drawText(&"Uptime  {hours:02d}:{minutes:02d}:{seconds:02d}",
           panelX + 9, panelY + panelH - 18, 12,
           Color(r: 170, g: 190, b: 210, a: 200))

  # Bottom desktop info (version and edition)
  drawText(t(tkOSTopHatOS), 10, (screenHeight - 75).int32, 14,
          Color(r: 100, g: 100, b: 120, a: 200))
  drawText(t(tkOSEdition), 10, (screenHeight - 58).int32, 12,
          Color(r: 150, g: 150, b: 170, a: 180))

  # Transient OS-style toasts above the taskbar (bottom-right), stacked
  if desktop.toasts.len > 0:
    let toastH = 52'i32
    let spacing = 8'i32
    let numberToDraw = if desktop.toasts.len < MAX_DESKTOP_TOASTS: desktop.toasts.len else: MAX_DESKTOP_TOASTS
    var j = 0
    while j < numberToDraw:
      let idx = desktop.toasts.len - 1 - j
      let t = desktop.toasts[idx]
      let fade = min(1.0'f32, t.timer / 0.6'f32)
      let alpha = uint8(255.0'f32 * fade)
      let toastW = max(260'i32, measureText(t.text, 16) + 64)
      let toastX = int32(screenWidth - toastW.int - 16)
      let toastY = int32(screenHeight - TASKBAR_HEIGHT - toastH.int - 14 - j * (toastH + spacing).int)
      drawRectangle(toastX, toastY, toastW, toastH,
                    Color(r: 12, g: 22, b: 34, a: uint8(232.0'f32 * fade)))
      drawRectangleLines(Rectangle(x: toastX.float32, y: toastY.float32,
                                   width: toastW.float32, height: toastH.float32), 2,
                         Color(r: 255, g: 210, b: 80, a: alpha))
      drawHexBadge(toastX + 26, toastY + toastH div 2, 14.0,
                   Color(r: 60, g: 44, b: 8, a: uint8(220.0'f32 * fade)),
                   Color(r: 255, g: 210, b: 80, a: alpha))
      drawText(t.text, toastX + 48, toastY + (toastH - 16) div 2, 16,
               Color(r: 235, g: 245, b: 255, a: alpha))
      inc j

proc showDesktopToast*(desktop: OSDesktop, text: string) =
  if desktop.isNil: return
  # Keep the sequence bounded to the max visible stack
  if desktop.toasts.len >= MAX_DESKTOP_TOASTS:
    desktop.toasts.delete(0)
  desktop.toasts.add(DesktopToast(text: text, timer: 5.0'f32))

proc tickDesktopToasts*(desktop: OSDesktop, dt: float32) =
  ## Tick toast timers outside the full desktop update (e.g. during gameplay).
  if desktop.isNil or desktop.toasts.len == 0: return
  var newToasts: seq[DesktopToast] = @[]
  for t in desktop.toasts:
    var nt = t
    nt.timer = max(0.0'f32, nt.timer - dt)
    if nt.timer > 0.0'f32:
      newToasts.add(nt)
  desktop.toasts = newToasts

proc drawDesktopToastsOverlay*(desktop: OSDesktop, screenWidth, screenHeight: int32) =
  ## Draw the toast stack in the bottom-right corner without the full desktop frame.
  if desktop.isNil or desktop.toasts.len == 0: return
  let toastH = 52'i32
  let spacing = 8'i32
  let numberToDraw = min(desktop.toasts.len, MAX_DESKTOP_TOASTS)
  var j = 0
  while j < numberToDraw:
    let idx = desktop.toasts.len - 1 - j
    let toast = desktop.toasts[idx]
    let fade = min(1.0'f32, toast.timer / 0.6'f32)
    let alpha = uint8(255.0'f32 * fade)
    let toastW = max(260'i32, measureText(toast.text, 16) + 64)
    let toastX = int32(screenWidth - toastW - 16)
    let toastY = int32(screenHeight - toastH - 14 - j * (toastH + spacing))
    drawRectangle(toastX, toastY, toastW, toastH,
                  Color(r: 12, g: 22, b: 34, a: uint8(232.0'f32 * fade)))
    drawRectangleLines(Rectangle(x: toastX.float32, y: toastY.float32,
                                 width: toastW.float32, height: toastH.float32), 2,
                       Color(r: 255, g: 210, b: 80, a: alpha))
    drawHexBadge(toastX + 26, toastY + toastH div 2, 14.0,
                 Color(r: 60, g: 44, b: 8, a: uint8(220.0'f32 * fade)),
                 Color(r: 255, g: 210, b: 80, a: alpha))
    drawText(toast.text, toastX + 48, toastY + (toastH - 16) div 2, 16,
             Color(r: 235, g: 245, b: 255, a: alpha))
    inc j

# Desktop grid shape for keyboard navigation. One entry per column, in the same
# order the icons are appended in newOSDesktop -- bump the matching count when an
# icon is added or the new icon is keyboard-unreachable.
const DESKTOP_COL_COUNTS = [6, 6, 1]

proc iconGridPos(index: int): tuple[col, row: int] =
  ## Map a flat icon index onto its (column, row) slot.
  var remaining = index
  for c in 0 ..< DESKTOP_COL_COUNTS.len:
    if remaining < DESKTOP_COL_COUNTS[c]:
      return (c, remaining)
    remaining -= DESKTOP_COL_COUNTS[c]
  (DESKTOP_COL_COUNTS.len - 1, DESKTOP_COL_COUNTS[^1] - 1)

proc iconGridIndex(col, row: int): int =
  ## Inverse of iconGridPos, clamping the row into the target column's length.
  let c = clamp(col, 0, DESKTOP_COL_COUNTS.len - 1)
  result = 0
  for i in 0 ..< c:
    result += DESKTOP_COL_COUNTS[i]
  result += clamp(row, 0, DESKTOP_COL_COUNTS[c] - 1)

proc handleDesktopInput*(desktop: OSDesktop, game: Game): int =
  ## Returns selected menu option: 0=Play, 1=Survival, 2=Stats, 3=Settings, 4=Shop, 5=Help, 6=Quit, 7=Sandbox, 9=Roguelite, 10=Advancements, 11=Changelog, 12=Credits
  ## Returns -1 if no action
  ## Note: Window occlusion should be handled by the calling code

  # Get mouse position
  let mousePos = getVirtualMousePosition()

  # Mouse hover detection, only update keyboard selection when the mouse actually moved,
  # so keyboard navigation is never silently overwritten by a stationary cursor.
  if game.mouseMovedRecently:
    var hoveredIcon = -1
    for i in 0..<desktop.icons.len:
      let icon = desktop.icons[i]
      let iconBounds = Rectangle(
        x: icon.x.float32 - 10,
        y: icon.y.float32 - 10,
        width: (ICON_SIZE + 20).float32,
        height: (ICON_SIZE + 58).float32
      )
      if checkCollisionPointRec(mousePos, iconBounds):
        hoveredIcon = i
        desktop.selectedIcon = i
        break

    # Mouse click
    if isPointerPressed() and hoveredIcon >= 0:
        let clicked = desktop.icons[hoveredIcon]
        # If the icon represents a locked mode, show a toast and swallow the click.
        case clicked.iconType
        of diRoguelite:
          if not globalSettings.isNil and not globalSettings.rogueliteUnlocked:
            showDesktopToast(desktop, t(tkDesktopModeLocked) & " " & t(tkRogueliteLockedDesc))
            return -1
          else:
            return clicked.iconType.int
        of diSurvival:
          if not globalSettings.isNil and not globalSettings.survivalUnlocked:
            showDesktopToast(desktop, t(tkDesktopModeLocked) & " " & t(tkSurvivalLockedDesc))
            return -1
          else:
            return clicked.iconType.int
        else:
          return clicked.iconType.int

  # Keyboard navigation, arrow keys AND WASD, with full 2D grid support.
  # Moving any direction marks keyboard as in-use so the mouse won't jump the cursor.
  let (col, row) = iconGridPos(desktop.selectedIcon)
  let colLen = DESKTOP_COL_COUNTS[col]

  if isKeyPressed(Down) or isKeyPressed(S):
    desktop.selectedIcon = iconGridIndex(col, (row + 1) mod colLen)
    game.keyboardUsedRecently = true
    game.mouseMovedRecently = false
    return -1

  if isKeyPressed(Up) or isKeyPressed(W):
    desktop.selectedIcon = iconGridIndex(col, (row - 1 + colLen) mod colLen)
    game.keyboardUsedRecently = true
    game.mouseMovedRecently = false
    return -1

  if isKeyPressed(Right) or isKeyPressed(D):
    if col < DESKTOP_COL_COUNTS.len - 1:
      # Next column to the right, clamping the row to that column's length
      desktop.selectedIcon = iconGridIndex(col + 1, row)
      game.keyboardUsedRecently = true
      game.mouseMovedRecently = false
    return -1

  if isKeyPressed(Left) or isKeyPressed(A):
    if col > 0:
      desktop.selectedIcon = iconGridIndex(col - 1, row)
      game.keyboardUsedRecently = true
      game.mouseMovedRecently = false
    return -1

  # Confirm selection with Enter or E
  if isKeyPressed(Enter) or isKeyPressed(E):
    return desktop.icons[desktop.selectedIcon].iconType.int

  return -1

proc startLoadingAnimation*(desktop: OSDesktop, text: string) =
  ## Start a loading animation with the given text
  desktop.loadingActive = true
  desktop.loadingProgress = 0.0
  desktop.loadingText = text

proc drawLoadingOverlay*(desktop: OSDesktop, screenWidth, screenHeight: int) =
  ## Draw the loading animation overlay if active
  if not desktop.loadingActive:
    return

  # Semi-transparent dark overlay
  drawRectangle(0, 0, screenWidth.int32, screenHeight.int32,
               Color(r: 0, g: 0, b: 0, a: 180))

  # Loading window/panel
  let panelWidth = 500
  let panelHeight = 200
  let panelX = (screenWidth - panelWidth) div 2
  let panelY = (screenHeight - panelHeight) div 2

  # Panel background with OS-style border
  drawRectangle(panelX.int32, panelY.int32, panelWidth.int32, panelHeight.int32,
               Color(r: 25, g: 30, b: 45, a: 255))
  drawRectangleLines(Rectangle(x: panelX.float32, y: panelY.float32,
                                width: panelWidth.float32, height: panelHeight.float32), 2,
                    Color(r: 0, g: 180, b: 220, a: 255))

  # Title bar
  drawRectangle(panelX.int32, panelY.int32, panelWidth.int32, 30,
               Color(r: 0, g: 50, b: 80, a: 255))
  drawText(t("os_loading") & "...", (panelX + 10).int32, (panelY + 7).int32, 16,
          Color(r: 0, g: 200, b: 255, a: 255))

  # Loading text
  let textY = panelY + 60
  let textWidth = measureText(desktop.loadingText, 20)
  let textX = panelX + (panelWidth - textWidth) div 2
  drawText(desktop.loadingText, textX.int32, textY.int32, 20, White)

  # Progress bar
  let barWidth = 400
  let barHeight = 30
  let barX = panelX + (panelWidth - barWidth) div 2
  let barY = panelY + 110

  # Progress bar background
  drawRectangle(barX.int32, barY.int32, barWidth.int32, barHeight.int32,
               Color(r: 20, g: 25, b: 35, a: 255))
  drawRectangleLines(Rectangle(x: barX.float32, y: barY.float32,
                                width: barWidth.float32, height: barHeight.float32), 2,
                    Color(r: 60, g: 80, b: 100, a: 255))

  # Progress fill with gradient effect
  let fillWidth = (barWidth.float32 * min(desktop.loadingProgress, 1.0)).int32
  if fillWidth > 0:
    drawRectangleGradientH(barX.int32, barY.int32, fillWidth, barHeight.int32,
                          Color(r: 0, g: 140, b: 200, a: 255),
                          Color(r: 0, g: 200, b: 255, a: 255))

  # Progress percentage
  let percentage = int(min(desktop.loadingProgress, 1.0) * 100.0)
  let percentText = $percentage & "%"
  let percentWidth = measureText(percentText, 18)
  let percentX = barX + (barWidth - percentWidth) div 2
  let percentY = barY + 6
  drawText(percentText, percentX.int32, percentY.int32, 18,
          Color(r: 255, g: 255, b: 255, a: 255))

  # Animated loading dots
  let dotCount = 3
  let dotsY = panelY + 160
  let dotSpacing = 15
  let dotsStartX = (screenWidth - (dotCount * dotSpacing)) div 2

  for i in 0..<dotCount:
    let dotX = dotsStartX + i * dotSpacing
    let dotPhase = desktop.time * 3.0 + i.float32 * 0.3
    let dotAlpha = ((sin(dotPhase) + 1.0) / 2.0 * 200.0 + 55.0).uint8
    drawCircle(Vector2(x: dotX.float32, y: dotsY.float32), 4,
              Color(r: 0, g: 200, b: 255, a: dotAlpha))
