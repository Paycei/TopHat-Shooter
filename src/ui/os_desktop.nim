## OS-Themed Desktop Environment Module
## Main menu as an operating system desktop

import raylib, rlgl, math, strutils, strformat, times
import ../types, ../localization, ../render_context, background_fx, ../desktop_bg_skins, desktop_bg_fx, ../settings, ../save_system, ../cube_skins

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
    # Transient OS-style toast (e.g. advancement unlocked)
    toastText*: string
    toastTimer*: float32

var
  activeDesktop*: OSDesktop = nil

const
  ICON_SIZE = 64
  ICON_SPACING = 100
  TASKBAR_HEIGHT = 40
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
                  iconColor: Color(r: 255, g: 100, b: 100, a: 255))
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
    toastText: "",
    toastTimer: 0.0
  )

proc updateOSDesktop*(desktop: OSDesktop, dt: float32, mouseOverWindow: bool = false,
                      screenWidth: int = 1024, screenHeight: int = 768) =
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

  if isMouseButtonPressed(Left) and overCube and not mouseOverWindow and
     not desktop.cubeEscaping:
    desktop.cubeDragging  = true
    desktop.cubeDragLastX = mp.x
    desktop.cubeDragLastY = mp.y
    desktop.cubeAngVelX   = 0.0
    desktop.cubeAngVelY   = 0.0

  if desktop.cubeDragging:
    if isMouseButtonDown(Left):
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

  if not desktop.cubeDragging:
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
    if desktop.cubePortalMode:
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
      # On the portal background, route through the portals; otherwise fly off-screen.
      var selectedBg: DesktopBgType = dbgDefault
      var currentCubeSkin: CubeSkinType = cskDefault
      if not globalSettings.isNil:
        selectedBg = DesktopBgType(globalSettings.desktopBg)
        currentCubeSkin = CubeSkinType(globalSettings.cubeSkin)
      if selectedBg == dbgPortal and currentCubeSkin == cskCompanion:
        desktop.cubePortalMode = true
        # Spin right (cubeAngVelY > 0) → enter the orange portal on the right
        desktop.cubePortalEnterRight = desktop.cubeAngVelY >= 0.0'f32
      else:
        desktop.cubePortalMode = false
        # Fly off roughly along the spin direction, drifting upward
        let dirX = (if desktop.cubeAngVelY >= 0: 1.0'f32 else: -1.0'f32)
        let dirLen = sqrt(dirX * dirX + 0.55'f32 * 0.55'f32)
        desktop.cubeEscapeDirX = dirX / dirLen
        desktop.cubeEscapeDirY = -0.55'f32 / dirLen

  # Tick down the desktop toast
  if desktop.toastTimer > 0.0'f32:
    desktop.toastTimer = max(0.0'f32, desktop.toastTimer - dt)

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

proc brightened(color: Color, delta: int): Color =
  Color(
    r: uint8(clamp(color.r.int + delta, 0, 255)),
    g: uint8(clamp(color.g.int + delta, 0, 255)),
    b: uint8(clamp(color.b.int + delta, 0, 255)),
    a: color.a
  )

proc darkened(color: Color, delta: int): Color =
  brightened(color, -delta)

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
  let edge = if selected: brightened(accent, 35) else: Color(r: 86, g: 104, b: 130, a: 235)
  let topFill = if selected: Color(r: 36, g: 50, b: 70, a: 248) else: Color(r: 24, g: 32, b: 48, a: 232)
  let bottomFill = if selected: Color(r: 18, g: 24, b: 38, a: 250) else: Color(r: 12, g: 17, b: 28, a: 238)

  if selected:
    drawSoftGlow(icon.x.float32 + ICON_SIZE.float32 * 0.5, icon.y.float32 + ICON_SIZE.float32 * 0.5,
                 45.0, Color(r: accent.r, g: accent.g, b: accent.b, a: 90), 0.85)

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
           1, Color(r: accent.r, g: accent.g, b: accent.b, a: if selected: 175 else: 95))

  let scanY = y + 12 + int32((sin(time * 2.4 + icon.iconType.int.float32) * 0.5 + 0.5) * (iconSize.float32 - 24.0))
  drawRectangle(x + 8, scanY, iconSize - 16, 2,
                Color(r: accent.r, g: accent.g, b: accent.b, a: if selected: 92 else: 38))

proc drawDesktopIcon(icon: DesktopIcon, time: float32, selected: bool) =
  drawIconTile(icon, time, selected)

  # Icon graphic based on type
  let centerX = (icon.x + ICON_SIZE div 2).int32
  let centerY = (icon.y + ICON_SIZE div 2).int32
  let accent = icon.iconColor
  let bright = brightened(accent, 55)
  let dim = darkened(accent, 45)
  drawHexBadge(centerX, centerY, 22.0, Color(r: 8, g: 14, b: 24, a: 160),
               Color(r: accent.r, g: accent.g, b: accent.b, a: 120),
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

  # System tray - clock with dynamic time
  let currentTime = now()
  let timeStr = currentTime.format("HH:mm")
  let dateStr = currentTime.format("MM/dd")

  let clockX = screenWidth - 80
  let clockY = startBtnY + 2
  drawText(timeStr, clockX.int32, clockY.int32, 16,
          Color(r: 0, g: 255, b: 255, a: 255))
  drawText(dateStr, (clockX - 10).int32, (clockY + 16).int32, 12,
          Color(r: 100, g: 200, b: 200, a: 255))

  # System indicators with icons
  let indicatorX = screenWidth - 170
  # Network indicator (always connected in game)
  drawRectangle(indicatorX.int32, (clockY + 6).int32, 12, 8,
               Color(r: 50, g: 255, b: 50, a: 255))
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

proc drawZeroGravityWallpaperCube*(centerX, centerY, size, time,
                                   angleX, angleY, angleZ: float32,
                                   skin: CubeSkinType = cskDefault) =
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

  var faces: array[6, WallpaperCubeFace]
  var useCustomSkin = skin != cskDefault
  var skinDataLocal: CubeSkinData
  if useCustomSkin:
    skinDataLocal = getCubeSkinData(skin)

  for i in 0..<6:
    var avgZ = 0.0'f32
    for corner in CubeFaces[i]:
      avgZ += rotated[corner].z
    avgZ /= 4.0'f32

    let light = clamp((avgZ + 1.65'f32) / 3.3'f32, 0.0'f32, 1.0'f32)
    if not useCustomSkin:
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
    edgeColor = Color(r: skinDataLocal.edgeColor.r, g: skinDataLocal.edgeColor.g, b: skinDataLocal.edgeColor.b, a: 220)
    innerEdgeColor = Color(r: skinDataLocal.glowColor.r, g: skinDataLocal.glowColor.g, b: skinDataLocal.glowColor.b, a: 100)
  if skin == cskCompanion:
    # The real Companion Cube keeps its color in the hearts only, the edge
    # channels are recessed dark grey, not glowing pink.
    innerEdgeColor = Color(r: 90, g: 93, b: 104, a: 130)
  for edge in CubeEdges:
    drawLine(projected[edge[0]], projected[edge[1]], 4, innerEdgeColor)
    drawLine(projected[edge[0]], projected[edge[1]], 1.5, edgeColor)

  # Companion Cube skin: the Weighted Companion Cube look, a soft-pink heart
  # on a light disc at the center of every visible face. Faces were depth-sorted above, so the last three are the
  # camera-facing ones; each heart is drawn in its face's projected basis so
  # it foreshortens and tracks the face as the cube tumbles.
  if skin == cskCompanion:
    for fi in 3 .. 5:
      let c0 = faces[fi].corners[0]
      let c1 = faces[fi].corners[1]
      let c2 = faces[fi].corners[2]
      let c3 = faces[fi].corners[3]
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
      # back to +Z, tying into that ring. right = up × normal keeps a uniform
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

      # Back-face cull. The cube body is translucent, so a heart on a face that
      # has turned away would bleed through. With this right-handed tangent
      # frame a camera-facing face projects to a positive screen area and a
      # back face to negative, so we only draw the positive (visible) ones. The
      # area also shrinks to zero at the silhouette, so the heart fades to a
      # point there and the visible/hidden hand-off stays seamless.
      if sRx * sUy - sRy * sUx <= 0.0'f32:
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
    drawRectangle(barX, barY, fillW, barH, Color(r: color.r, g: color.g, b: color.b, a: 205))
    drawRectangle(barX, barY, fillW, 1,
                  Color(r: uint8(min(255, color.r.int + 60)),
                        g: uint8(min(255, color.g.int + 60)),
                        b: uint8(min(255, color.b.int + 60)), a: 220))
    let capX = barX + fillW
    drawRectangle(capX - 2, barY, 2, barH, Color(r: 255, g: 255, b: 255, a: 170))
    drawSoftGlow(capX.float32, (barY + barH div 2).float32, 7.0'f32,
                 Color(r: color.r, g: color.g, b: color.b, a: 130), 1.0'f32)
  drawRectangleLines(Rectangle(x: barX.float32, y: barY.float32,
                               width: barW.float32, height: barH.float32), 1,
                     Color(r: 0, g: 90, b: 110, a: 150))
  # Percentage, right-aligned
  let pStr = $int(pct + 0.5'f32) & "%"
  drawText(pStr, panelX + panelW - 9 - measureText(pStr, 12), y, 12, color)

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
    let bottomColor = darkened(topColor, 12)
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
    # thin at 1024×768 compared to the 170×64 shop card.
    let refW = int32(ceil(w / 6.0'f32))
    let refH = int32(ceil(h / 6.0'f32))
    pushMatrix()
    scalef(w / refW.float32, h / refH.float32, 1.0'f32)
    drawSharedBackdrop(refW, refH, desktop.time * 0.62,
                       topColor, bottomColor, gridColor, nodeColor, accentColor,
                       0.9, 0.8)
    popMatrix()

    drawSoftGlow(w * 0.64, h * 0.46, min(w, h) * 0.42,
                 Color(r: accentColor.r, g: accentColor.g, b: accentColor.b, a: 70), 0.7)
    drawSoftGlow(w * 0.18, h * 0.18, min(w, h) * 0.28,
                 Color(r: nodeColor.r, g: nodeColor.g, b: nodeColor.b, a: 56), 0.55)
    drawSoftGlow(w * 0.88, h * 0.82, min(w, h) * 0.30,
                 Color(r: bgData.primaryColor.r, g: bgData.primaryColor.g, b: bgData.primaryColor.b, a: 46), 0.5)

    drawDesktopBgThemeFx(selectedBg, screenWidth.int32, screenHeight.int32, desktop.time)

    for i in 0..3:
      let ringRadius = min(w, h) * (0.18 + i.float32 * 0.055)
      let alpha = uint8(26 + i * 9)
      drawCircleLines(Vector2(x: w * 0.64, y: h * 0.46), ringRadius,
                      Color(r: accentColor.r, g: accentColor.g, b: accentColor.b, a: alpha))
      let nodeAngle = desktop.time * (0.22 + i.float32 * 0.04) + i.float32 * PI * 0.38
      drawCircle(Vector2(x: w * 0.64 + cos(nodeAngle) * ringRadius,
                         y: h * 0.46 + sin(nodeAngle) * ringRadius),
                 3.0 + i.float32 * 0.35,
                 Color(r: nodeColor.r, g: nodeColor.g, b: nodeColor.b, a: uint8(120 + i * 18)))

    let centerX = w * 0.64
    let centerY = h * 0.46
    let currentCubeSkin = if not globalSettings.isNil: CubeSkinType(globalSettings.cubeSkin) else: cskDefault
    drawZeroGravityWallpaperCube(centerX + desktop.cubeOffsetX, centerY + desktop.cubeOffsetY,
                                 min(w, h) * 0.042'f32, desktop.time,
                                 desktop.cubeRotX, desktop.cubeRotY, desktop.cubeRotZ, currentCubeSkin)

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

  # Transient OS-style toast above the taskbar (bottom-right)
  if desktop.toastTimer > 0.0'f32 and desktop.toastText.len > 0:
    let fade = min(1.0'f32, desktop.toastTimer / 0.6'f32)
    let alpha = uint8(255.0'f32 * fade)
    let toastW = max(260'i32, measureText(desktop.toastText, 16) + 64)
    let toastH = 52'i32
    let toastX = int32(screenWidth - toastW.int - 16)
    let toastY = int32(screenHeight - TASKBAR_HEIGHT - toastH.int - 14)
    drawRectangle(toastX, toastY, toastW, toastH,
                  Color(r: 12, g: 22, b: 34, a: uint8(232.0'f32 * fade)))
    drawRectangleLines(Rectangle(x: toastX.float32, y: toastY.float32,
                                 width: toastW.float32, height: toastH.float32), 2,
                       Color(r: 255, g: 210, b: 80, a: alpha))
    drawHexBadge(toastX + 26, toastY + toastH div 2, 14.0,
                 Color(r: 60, g: 44, b: 8, a: uint8(220.0'f32 * fade)),
                 Color(r: 255, g: 210, b: 80, a: alpha))
    drawText(desktop.toastText, toastX + 48, toastY + (toastH - 16) div 2, 16,
             Color(r: 235, g: 245, b: 255, a: alpha))

proc handleDesktopInput*(desktop: OSDesktop, game: Game): int =
  ## Returns selected menu option: 0=Play, 1=Survival, 2=Stats, 3=Settings, 4=Shop, 5=Help, 6=Quit, 7=Sandbox, 9=Roguelite, 10=Advancements
  ## Returns -1 if no action
  ## Note: Window occlusion should be handled by the calling code

  # Column layout constants
  const COL0_COUNT = 6   # indices 0-5
  const COL1_COUNT = 6   # indices 6-11

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
    if isMouseButtonPressed(Left) and hoveredIcon >= 0:
      return desktop.icons[hoveredIcon].iconType.int

  # Keyboard navigation, arrow keys AND WASD, with full 2D grid support.
  # Moving any direction marks keyboard as in-use so the mouse won't jump the cursor.
  let col = if desktop.selectedIcon < COL0_COUNT: 0 else: 1
  let row = if col == 0: desktop.selectedIcon else: desktop.selectedIcon - COL0_COUNT

  if isKeyPressed(Down) or isKeyPressed(S):
    let colLen = if col == 0: COL0_COUNT else: COL1_COUNT
    desktop.selectedIcon = if col == 0: (row + 1) mod colLen
                           else: (row + 1) mod colLen + COL0_COUNT
    game.keyboardUsedRecently = true
    game.mouseMovedRecently = false
    return -1

  if isKeyPressed(Up) or isKeyPressed(W):
    let colLen = if col == 0: COL0_COUNT else: COL1_COUNT
    desktop.selectedIcon = if col == 0: (row - 1 + colLen) mod colLen
                           else: (row - 1 + colLen) mod colLen + COL0_COUNT
    game.keyboardUsedRecently = true
    game.mouseMovedRecently = false
    return -1

  if isKeyPressed(Right) or isKeyPressed(D):
    if col == 0:
      # Switch to column 1, clamp row to column 1's length
      desktop.selectedIcon = min(row, COL1_COUNT - 1) + COL0_COUNT
      game.keyboardUsedRecently = true
      game.mouseMovedRecently = false
    return -1

  if isKeyPressed(Left) or isKeyPressed(A):
    if col == 1:
      # Switch to column 0 at the same row
      desktop.selectedIcon = row
      game.keyboardUsedRecently = true
      game.mouseMovedRecently = false
    return -1

  # Confirm selection with Enter or E
  if isKeyPressed(Enter) or isKeyPressed(E):
    return desktop.icons[desktop.selectedIcon].iconType.int

  return -1

proc showDesktopToast*(desktop: OSDesktop, text: string) =
  desktop.toastText = text
  desktop.toastTimer = 5.0

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
