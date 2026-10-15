## OS-Themed Desktop Environment Module
## Main menu as an operating system desktop

import raylib, rlgl, math, strutils, strformat, times, tables
import ../draw_prims
from std/unicode import runeAt, toUpper, `$`
import ../types, ../localization, ../render_context, background_fx, ../desktop_bg_skins, desktop_bg_fx, ../settings, ../save_system, ../cube_skins, ../cube_render, ../utils
import ../modding/[mod_assets, mod_hooks]
import ui_theme

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
    diFeedback      # Feedback / bug report form (FEEDBACK.exe) - 13
    diMods          # Mod manager (MODS.exe) - 14
    diModApp        # A register.app program (one icon per app, see syncModIcons) - 15
    diModMode       # A register.gamemode game mode (one icon per mode, see syncModIcons) - 16

  DesktopIcon* = object
    iconType*: DesktopIconType
    x*, y*: int
    selected*: bool
    name*: string
    iconColor*: Color
    modKey*: string   ## diModApp / diModMode only: the app's or mode's key ("<mod id>:<id>")

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
    windows*: seq[WindowState]
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
    # Rows per icon column in the current layout. Set by layoutDesktopIcons from
    # the logical viewport (which the UI-scale setting shrinks), and read back by
    # keyboard navigation so it always walks the grid that was actually drawn.
    gridRows*: int
    launchModKey*: string
      ## Key of the mod app or mode whose icon was just activated (read by main.nim
      ## when handleDesktopInput returns diModApp / diModMode).

var
  activeDesktop*: OSDesktop = nil

const
  ICON_SIZE* = 64
  ICON_SPACING = 100
  TASKBAR_HEIGHT = 40
  MAX_DESKTOP_TOASTS* = 5
  DESKTOP_GRID_START_X = 80
  DESKTOP_GRID_START_Y = 80
  ICON_LABEL_WIDTH = 88
  ICON_LABEL_FONT_SIZE = 14
  ICON_LABEL_MIN_SIZE = 9
  DESKTOP_MARGIN_RIGHT = 80
    ## Gap between the right screen edge and the right edge of a corner-anchored
    ## icon's label block (mirrors DESKTOP_GRID_START_X on the left).
  DESKTOP_MARGIN_BOTTOM = 28
    ## Gap between the taskbar and the bottom of a corner-anchored icon's hover
    ## box, so hovering the icon never fights the taskbar for the click.
  ICON_HOVER_BOTTOM = ICON_SIZE + 48
    ## Distance from an icon's y to the bottom of its hover/label block (see the
    ## hit box in handleDesktopInput). This, not ICON_SIZE, is what has to clear
    ## the taskbar for an icon to be fully visible and clickable.
  DESKTOP_GRID_ROWS = 6
    ## Rows per column in the designed layout (12 grid icons = two full columns).
    ## It is a maximum, not a fixed shape: layoutDesktopIcons drops to fewer rows
    ## -- and spills into more columns -- when the viewport is too short.

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
  of diFeedback: t(tkDesktopIconFeedback)
  of diMods: t(tkDesktopIconMods)
  of diModApp, diModMode: ""  # named per entry (modAppName / modModeName), see updateOSDesktop

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
  let lineWidth = measureText(text, fontSize)
  let drawX = labelX + max(0'i32, (ICON_LABEL_WIDTH - lineWidth) div 2)
  let th = activeTheme()
  case th.shell
  of ssTopHat:
    let shadowColor = Color(r: 0, g: 0, b: 0, a: if selected: 235 else: 180)
    let textColor = if selected: Color(r: 220, g: 248, b: 255, a: 255) else: White
    drawText(text, drawX + 2, y + 2, fontSize, shadowColor)
    drawText(text, drawX, y, fontSize, textColor)
  of ssCkn:
    # White on the wallpaper, an accent pill behind the chosen one.
    if selected:
      let pill = Rectangle(x: (drawX - 6).float32, y: (y - 3).float32,
                           width: (lineWidth + 12).float32, height: (fontSize + 6).float32)
      drawRectangleRounded(pill, cornerRoundness(pill.width, pill.height, 5.0'f32), 6,
                           withAlpha(th.accent, 225))
    else:
      drawText(text, drawX + 1, y + 1, fontSize, withAlpha(CknShadow, 200))
    drawText(text, drawX, y, fontSize, White)

proc isCornerIcon(iconType: DesktopIconType): bool =
  ## Icons that are pinned to a screen corner instead of living on the top-left
  ## grid. They are excluded from the grid flow and from its column arithmetic.
  ## They stack upward from the bottom-right corner in reverse seq order, so the
  ## last one in the seq sits in the corner itself.
  iconType in {diMods, diFeedback, diCredits}

proc isModIcon(iconType: DesktopIconType): bool =
  ## Mod icons (game modes, then apps): flowed like the grid, but in columns of
  ## their own that start after the built-in grid's last one (see
  ## layoutDesktopIcons).
  iconType in {diModMode, diModApp}

proc modBaseColor(base: GameMode): Color =
  ## The desktop colour of a mod mode's base mode (as in newOSDesktop).
  case base
  of gmTimeSurvival: Color(r: 255, g: 150, b: 100, a: 255)
  of gmRoguelite: Color(r: 0, g: 220, b: 180, a: 255)
  else: Color(r: 100, g: 200, b: 255, a: 255)

proc modModeIconColor(m: ModModeDef): Color =
  if m.color.a > 0: m.color else: modBaseColor(m.base)

proc syncModIcons(desktop: OSDesktop) =
  ## Keep exactly one icon per register.gamemode / register.app entry that
  ## wants one: modes first, then apps, each in registration order, between the
  ## built-in grid icons and the corner icons. Cheap when nothing changed (a key
  ## comparison); rebuilds keep the selection on the same icon where it still
  ## exists. A mode and an app may share a key, so icons are told apart by type.
  var want: seq[tuple[t: DesktopIconType, i: int]]
  for i in 0 ..< modModes.len:
    if modModes[i].desktop: want.add((diModMode, i))
  for i in 0 ..< modApps.len:
    if modApps[i].desktop: want.add((diModApp, i))
  proc wantKey(w: tuple[t: DesktopIconType, i: int]): string =
    if w.t == diModMode: modModes[w.i].key else: modApps[w.i].key
  var same = true
  var have = 0
  for icon in desktop.icons:
    if isModIcon(icon.iconType):
      if have >= want.len or icon.iconType != want[have].t or icon.modKey != wantKey(want[have]):
        same = false
        break
      inc have
  if same and have == want.len:
    return

  var selType = diPlay
  var selKey = ""
  if desktop.selectedIcon in 0 ..< desktop.icons.len:
    selType = desktop.icons[desktop.selectedIcon].iconType
    selKey = desktop.icons[desktop.selectedIcon].modKey
  var builtin, corner: seq[DesktopIcon]
  var modIcons: Table[string, DesktopIcon]
  for icon in desktop.icons:
    if isCornerIcon(icon.iconType): corner.add(icon)
    elif isModIcon(icon.iconType): modIcons[$icon.iconType & icon.modKey] = icon
    else: builtin.add(icon)
  var rebuilt = builtin
  for w in want:
    let key = wantKey(w)
    var icon = modIcons.getOrDefault($w.t & key, DesktopIcon(iconType: w.t, modKey: key))
    icon.iconColor = if w.t == diModMode: modModeIconColor(modModes[w.i]) else: modApps[w.i].color
    rebuilt.add(icon)
  rebuilt.add(corner)
  desktop.icons = rebuilt
  desktop.selectedIcon = clamp(desktop.selectedIcon, 0, desktop.icons.high)
  for i, icon in desktop.icons:
    if icon.iconType == selType and icon.modKey == selKey:
      desktop.selectedIcon = i
      break

proc desktopGridRows(screenHeight: int): int =
  ## Rows per icon column that actually fit above the taskbar in `screenHeight`
  ## logical pixels. DESKTOP_GRID_ROWS is the cap, so any viewport with room to
  ## spare keeps the layout the desktop has always had; the UI-scale setting
  ## divides that viewport, and at >100% six rows no longer fit, which is what
  ## used to push the last icons under the taskbar and off the bottom edge.
  let usable = screenHeight - TASKBAR_HEIGHT - DESKTOP_MARGIN_BOTTOM -
               DESKTOP_GRID_START_Y - ICON_HOVER_BOTTOM
  clamp(usable div ICON_SPACING + 1, 1, DESKTOP_GRID_ROWS)

proc layoutDesktopIcons*(desktop: OSDesktop, screenWidth, screenHeight: int) =
  ## Re-flow the desktop icons for the current logical viewport. The grid is
  ## column-major and fills top-to-bottom, so a shorter viewport simply starts a
  ## new column sooner rather than running off the bottom. The corner icons
  ## (diFeedback over diCredits) are not part of the grid: they are pinned to
  ## the bottom-right corner, so their slots follow
  ## the virtual canvas (1024 classic vs 1366 widescreen, switchable at runtime)
  ## as well as the scale.
  if desktop.isNil:
    return
  # The label is wider than the icon and drawn centred on it, so the visual
  # right edge sits half the overhang past the icon box.
  const labelOverhang = (ICON_LABEL_WIDTH - ICON_SIZE) div 2

  # The built-in grid alone decides the row count, so it lays out exactly as it
  # did before mod apps existed; app icons reuse that row count.
  var gridCount, appCount = 0
  for icon in desktop.icons:
    if isModIcon(icon.iconType): inc appCount
    elif not isCornerIcon(icon.iconType): inc gridCount

  var rows = desktopGridRows(screenHeight)
  # Height is the binding constraint at every scale the setting allows, but if a
  # viewport were ever too narrow for the columns that implies, growing them
  # downward beats stacking icons past the right edge.
  let maxCols = max(1, (screenWidth - DESKTOP_GRID_START_X - ICON_SIZE -
                        labelOverhang) div ICON_SPACING + 1)
  if gridCount > rows * maxCols:
    rows = (gridCount + maxCols - 1) div maxCols
  # Even the columns out: once the number of columns is settled, use the
  # shortest rows that still fill them, so 12 icons in 5 fitting rows read as
  # 4/4/4 rather than 5/5/2. This can only shorten the columns, never lengthen
  # them past what fits.
  let cols = max(1, (gridCount + rows - 1) div rows)
  rows = max(1, (gridCount + cols - 1) div cols)
  desktop.gridRows = rows

  # App icons start on the next fresh column and fill it column-major.
  let appBase = ((gridCount + rows - 1) div rows) * rows
  var slot = 0
  for icon in desktop.icons.mitems:
    if isCornerIcon(icon.iconType):
      continue
    let s = if isModIcon(icon.iconType): appBase + slot - gridCount else: slot
    icon.x = DESKTOP_GRID_START_X + (s div rows) * ICON_SPACING
    icon.y = DESKTOP_GRID_START_Y + (s mod rows) * ICON_SPACING
    inc slot

  let cornerX = screenWidth - DESKTOP_MARGIN_RIGHT - ICON_SIZE - labelOverhang
  let cornerY = screenHeight - TASKBAR_HEIGHT - DESKTOP_MARGIN_BOTTOM - ICON_HOVER_BOTTOM
  var cornerCount = 0
  for icon in desktop.icons:
    if isCornerIcon(icon.iconType):
      inc cornerCount
  var cornerSlot = 0
  for icon in desktop.icons.mitems:
    if isCornerIcon(icon.iconType):
      let above = cornerCount - 1 - cornerSlot
      icon.x = max(cornerX, DESKTOP_GRID_START_X)
      icon.y = max(cornerY - above * ICON_SPACING, DESKTOP_GRID_START_Y)
      inc cornerSlot

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
      # Bottom-right corner, off the top-left grid. Every position here (this one
      # and the grid slots above) is a placeholder: layoutDesktopIcons owns the
      # real coordinates, since they depend on the current logical viewport. The
      # *order* of this seq is what matters -- it is the grid's fill order, and
      # the corner stack's top-to-bottom order.
      DesktopIcon(iconType: diMods, x: DESKTOP_GRID_START_X + ICON_SPACING * 2, y: DESKTOP_GRID_START_Y,
                  selected: false, name: getIconName(diMods),
                  iconColor: Color(r: 120, g: 220, b: 160, a: 255)),
      DesktopIcon(iconType: diFeedback, x: DESKTOP_GRID_START_X + ICON_SPACING * 2, y: DESKTOP_GRID_START_Y,
                  selected: false, name: getIconName(diFeedback),
                  iconColor: Color(r: 255, g: 130, b: 90, a: 255)),
      DesktopIcon(iconType: diCredits, x: DESKTOP_GRID_START_X + ICON_SPACING * 2, y: DESKTOP_GRID_START_Y,
                  selected: false, name: getIconName(diCredits),
                  iconColor: Color(r: 255, g: 110, b: 160, a: 255))
    ],
    gridRows: DESKTOP_GRID_ROWS,
    selectedIcon: 0,
    time: 0,
    windows: @[],
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
    cubeDiceResultTimer: 0.0,
    cubeDiceVelY: 0.0,
    cubeDiceSpinX: 0.0,
    cubeDiceSpinY: 0.0,
    cubeDiceSpinZ: 0.0,
    cubeJackGlow: 0.0,
    toasts: @[]
  )
  # Anchor the corner icons before the first frame draws or hit-tests them.
  layoutDesktopIcons(result, getVirtualScreenWidth().int, getVirtualScreenHeight().int)

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

  # Mod apps come and go with reloads; then keep corner-anchored icons glued to
  # the corner when the HUD layout (and with it the virtual canvas width)
  # changes at runtime.
  syncModIcons(desktop)
  layoutDesktopIcons(desktop, screenWidth, screenHeight)

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

  # A mod wallpaper covers the built-in background: the cube is only there (and
  # grabbable) when the mod keeps it, and the background half of the easter-egg
  # combos (dice table, portals, Kernel Panic) is gone, so it acts as the default.
  let modWall = modWallpaper()
  let cubeShown = modWall.id == 0 or modWall.cube
  var wallBg: DesktopBgType = dbgDefault
  if modWall.id == 0 and not globalSettings.isNil:
    wallBg = DesktopBgType(globalSettings.desktopBg)

  let mp   = getVirtualMousePosition()
  let ddst = sqrt((mp.x-cubeCX)*(mp.x-cubeCX) + (mp.y-cubeCY)*(mp.y-cubeCY))
  let overCube = cubeShown and ddst <= (CubeDragRadius + cubeSize * 2.0)

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
    if isPointerDown() and cubeShown:
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
    let selectedBg = wallBg
    var currentCubeSkin: CubeSkinType = cskDefault
    if not globalSettings.isNil:
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
    let guardBg = wallBg
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
    if desktop.icons[i].iconType == diModApp:
      let app = findModApp(desktop.icons[i].modKey)
      desktop.icons[i].name = modAppName(app, getLanguage() == Spanish)
    elif desktop.icons[i].iconType == diModMode:
      desktop.icons[i].name = modModeName(desktop.icons[i].modKey, getLanguage() == Spanish)
    else:
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
    drawStroke(points[i], points[next], 2, edge)

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

  drawRectOutline(Rectangle(x: x.float32, y: y.float32,
                                width: iconSize.float32, height: iconSize.float32), 2, edge)
  drawStroke(Vector2(x: (x + 7).float32, y: (y + 5).float32),
           Vector2(x: (x + iconSize - 11).float32, y: (y + 5).float32),
           2, Color(r: 205, g: 245, b: 255, a: if selected: 150 else: 72))
  drawStroke(Vector2(x: (x + 5).float32, y: (y + iconSize - 7).float32),
           Vector2(x: (x + iconSize - 8).float32, y: (y + iconSize - 7).float32),
           1, withAlpha(accent, if selected: 175 else: 95))

  let scanY = y + 12 + int32((sin(time * 2.4 + icon.iconType.int.float32) * 0.5 + 0.5) * (iconSize.float32 - 24.0))
  drawRectangle(x + 8, scanY, iconSize - 16, 2,
                withAlpha(accent, if selected: 92 else: 38))

proc v2(x, y: float32): Vector2 {.inline.} = Vector2(x: x, y: y)

proc drawIconTri(a, b, c: Vector2, col: Color) =
  ## Winding-safe triangle. raylib culls back faces, so a triangle whose points
  ## happen to be wound the wrong way silently renders nothing -- very easy to
  ## trip over when hand-placing icon geometry. Reorder instead of failing.
  let cross = (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
  if cross < 0.0'f32: drawTriangle(a, b, c, col)
  else: drawTriangle(a, c, b, col)

proc drawIconDisc(cx, cy, r: float32, fill, edge: Color, thick: float32 = 2.0) =
  ## Filled disc with a rim. Every icon glyph sits on the busy animated
  ## wallpaper, so shapes need their own dark backing plus a bright edge to
  ## hold their silhouette.
  drawDisc(v2(cx, cy), r, fill)
  drawRing(v2(cx, cy), r - thick, r, 0.0, 360.0, 32, edge)

proc drawDesktopIcon*(icon: DesktopIcon, time: float32, selected: bool) =
  ## Tile, glyph and label. Exported so cutscenes can stage the real desktop
  ## (the lore intro's flood shot corrupts these very icons). The tile and
  ## glyph are the app's picture, the same in every theme; the label is the
  ## shell's.
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
    # Launch prism, with thruster streaks so it reads as "start a run" rather
    # than "resume a video".
    let pcx = centerX.float32
    let pcy = centerY.float32
    for i in 0..2:
      let phase = (time * 1.5'f32 + i.float32 * 0.31'f32) mod 1.0'f32
      let sx = pcx - 11.0'f32 - phase * 11.0'f32
      let sy = pcy - 7.0'f32 + i.float32 * 7.0'f32
      drawStroke(v2(sx, sy), v2(sx + 7.0'f32, sy), 2,
               withAlpha(bright, uint8(165.0'f32 * (1.0'f32 - phase))))
    drawIconTri(v2(pcx - 11, pcy - 16), v2(pcx - 11, pcy + 16), v2(pcx + 18, pcy),
                Color(r: 8, g: 12, b: 20, a: 235))
    drawIconTri(v2(pcx - 9, pcy - 13), v2(pcx - 9, pcy + 13), v2(pcx + 15, pcy), accent)
    drawIconTri(v2(pcx - 5, pcy - 7), v2(pcx - 5, pcy + 7), v2(pcx + 7, pcy), bright)

  of diSurvival:
    # Stopwatch: survival is "how long did you last", and the crown + sweeping
    # hand say that far faster than the old clock-face-plus-orbiting-dots did.
    let scx = centerX.float32
    let scy = centerY.float32 + 2.0'f32
    # Crown and side button on top of the case.
    drawRectangle((centerX - 4).int32, (scy - 22.0'f32).int32, 8, 5, bright)
    drawStroke(v2(scx + 12, scy - 17), v2(scx + 17, scy - 22), 4, dim)
    drawIconDisc(scx, scy, 17.0, Color(r: 10, g: 16, b: 26, a: 245), bright, 2.5)
    # Quarter ticks.
    for i in 0..3:
      let a = i.float32 * (PI / 2.0'f32)
      let ca = cos(a)
      let sa = sin(a)
      drawStroke(v2(scx + ca * 10.0, scy + sa * 10.0),
               v2(scx + ca * 13.5, scy + sa * 13.5), 2, withAlpha(accent, 210))
    # Fixed minute hand plus a hand that actually sweeps.
    drawStroke(v2(scx, scy), v2(scx, scy - 11), 3, White)
    let sweep = time * 1.25'f32 - PI / 2.0'f32
    drawStroke(v2(scx, scy), v2(scx + cos(sweep) * 13.0, scy + sin(sweep) * 13.0), 2, accent)
    drawDisc(v2(scx, scy), 2.4, bright)

  of diStatistics:
    # Analytics bars on a real axis, with the trend line ending in a marker.
    let bx = centerX.float32
    let by = centerY.float32
    drawStroke(v2(bx - 19, by + 19), v2(bx + 19, by + 19), 2, withAlpha(bright, 200))
    drawStroke(v2(bx - 19, by - 19), v2(bx - 19, by + 19), 2, withAlpha(bright, 120))
    let heights = [13'i32, 20'i32, 28'i32]
    let barCols = [dim, accent, bright]
    for i in 0..2:
      let h = heights[i]
      let x = centerX - 15 + i.int32 * 11
      drawRectangle(x, (centerY + 18 - h).int32, 8, h, barCols[i])
      drawRectOutline(Rectangle(x: x.float32, y: (centerY + 18 - h).float32,
                                   width: 8.0, height: h.float32), 1,
                         Color(r: 8, g: 12, b: 20, a: 190))
    drawStroke(v2(bx - 12, by + 2), v2(bx - 1, by - 6), 2, White)
    drawStroke(v2(bx - 1, by - 6), v2(bx + 11, by - 14), 2, White)
    drawDisc(v2(bx + 11, by - 14), 3.0, White)

  of diSettings:
    # Slowly turning cog. The old three-slider glyph read as an audio mixer;
    # the gear is the one settings symbol every player already knows.
    let cogCX = centerX.float32
    let cogCY = centerY.float32
    let spin = time * 0.35'f32
    # Teeth: thick radial spokes poking out past the body rim.
    for i in 0..7:
      let a = spin + i.float32 * (PI / 4.0'f32)
      let ca = cos(a)
      let sa = sin(a)
      drawStroke(Vector2(x: cogCX + ca * 11.0'f32, y: cogCY + sa * 11.0'f32),
               Vector2(x: cogCX + ca * 20.0'f32, y: cogCY + sa * 20.0'f32), 8, dim)
      drawStroke(Vector2(x: cogCX + ca * 11.0'f32, y: cogCY + sa * 11.0'f32),
               Vector2(x: cogCX + ca * 18.0'f32, y: cogCY + sa * 18.0'f32), 4, bright)
    # Body, rim and hub hole.
    drawDisc(Vector2(x: cogCX, y: cogCY), 14, accent)
    drawCircleOutline(Vector2(x: cogCX, y: cogCY), 14, bright)
    drawDisc(Vector2(x: cogCX, y: cogCY), 6, Color(r: 8, g: 12, b: 20, a: 255))
    drawCircleOutline(Vector2(x: cogCX, y: cogCY), 6.5, bright)

  of diShop:
    # Shopping bag with paint swatches. The old crate silhouette was ambiguous;
    # a bag with a bold handle arc is unmistakably "store".
    let sx = centerX.float32
    let sy = centerY.float32
    # Handle first so the bag body overlaps its feet.
    drawRing(v2(sx, sy - 8.0), 6.0, 9.0, 180.0, 360.0, 20, bright)
    # Body: slightly tapered, dark backing then accent face.
    drawIconTri(v2(sx - 16, sy - 7), v2(sx - 13, sy + 18), v2(sx + 13, sy + 18), accent)
    drawIconTri(v2(sx - 16, sy - 7), v2(sx + 13, sy + 18), v2(sx + 16, sy - 7), accent)
    drawStroke(v2(sx - 16, sy - 7), v2(sx + 16, sy - 7), 3, dim)
    drawStroke(v2(sx - 13, sy + 18), v2(sx + 13, sy + 18), 2, dim)
    let colors = [
      Color(r: 255, g: 100, b: 180, a: 255),
      Color(r: 0, g: 255, b: 100, a: 255),
      Color(r: 0, g: 200, b: 255, a: 255)
    ]
    for i in 0..<3:
      let px = sx - 8.0'f32 + i.float32 * 8.0'f32
      drawDisc(v2(px, sy + 6.0), 4.2, Color(r: 8, g: 12, b: 20, a: 220))
      drawDisc(v2(px, sy + 6.0), 3.2, colors[i])

  of diHelp:
    # Manual: a book rather than a sheet, so it never reads as the changelog
    # document sitting two icons away.
    let hx = centerX.float32
    let hy = centerY.float32
    drawRectangle((centerX - 15).int32, (centerY - 17).int32, 30, 34, accent)
    drawRectangle((centerX - 15).int32, (centerY - 17).int32, 6, 34, dim)
    drawRectOutline(Rectangle(x: hx - 15, y: hy - 17, width: 30.0, height: 34.0), 2,
                       Color(r: 8, g: 12, b: 20, a: 220))
    # Page edge highlight on the open side.
    drawStroke(v2(hx + 13, hy - 15), v2(hx + 13, hy + 15), 2, withAlpha(bright, 200))
    drawText("?", (centerX - 4).int32, (centerY - 13).int32, 27, White)

  of diQuit:
    # True power glyph: a broken ring with the stem sitting in the gap.
    let qx = centerX.float32
    let qy = centerY.float32
    drawDisc(v2(qx, qy), 18.0, Color(r: 8, g: 12, b: 20, a: 210))
    drawRing(v2(qx, qy), 12.0, 17.0, 250.0, 650.0, 40, dim)
    drawRing(v2(qx, qy), 13.5, 16.0, 250.0, 650.0, 40, bright)
    drawRectangle((centerX - 3).int32, (centerY - 21).int32, 6, 18,
                  Color(r: 8, g: 12, b: 20, a: 235))
    drawRectangle((centerX - 2).int32, (centerY - 20).int32, 4, 16, bright)

  of diSandbox:
    # Lab flask with bubbles rising through the liquid.
    let baseWidth = 22'i32
    let topWidth = 12'i32
    let flaskBottom = centerY + 13
    let flaskTop = flaskBottom - 26
    let liquidColor = Color(r: 0, g: 200, b: 255, a: 220)
    # Neck, rim and body.
    drawRectangle(centerX - topWidth div 2, flaskTop, topWidth, 9, accent)
    drawRectangle(centerX - topWidth div 2 - 2, flaskTop - 3, topWidth + 4, 4, bright)
    drawIconTri(v2((centerX - topWidth div 2).float32, (flaskTop + 9).float32),
                v2((centerX - baseWidth div 2).float32, flaskBottom.float32),
                v2((centerX + baseWidth div 2).float32, flaskBottom.float32), accent)
    drawIconTri(v2((centerX - topWidth div 2).float32, (flaskTop + 9).float32),
                v2((centerX + baseWidth div 2).float32, flaskBottom.float32),
                v2((centerX + topWidth div 2).float32, (flaskTop + 9).float32), accent)
    drawRectangle(centerX - baseWidth div 2 + 4, flaskBottom - 9, baseWidth - 8, 8, liquidColor)
    drawIconTri(v2((centerX - 7).float32, (flaskBottom - 9).float32),
                v2((centerX - baseWidth div 2 + 4).float32, (flaskBottom - 1).float32),
                v2((centerX + baseWidth div 2 - 4).float32, (flaskBottom - 1).float32), liquidColor)
    for i in 0..2:
      let phase = (time * 0.8'f32 + i.float32 * 0.37'f32) mod 1.0'f32
      let by = flaskBottom.float32 - 8.0'f32 - phase * 16.0'f32
      drawDisc(v2(centerX.float32 - 4.0'f32 + i.float32 * 4.0'f32, by),
                 1.8'f32 - phase * 0.6'f32,
                 Color(r: 255, g: 255, b: 255, a: uint8(210.0'f32 * (1.0'f32 - phase))))

  of diPvP:
    # Crossed swords. The bare X read as a "close" glyph; blades with tips,
    # crossguards and pommels read as a duel.
    let px = centerX.float32
    let py = centerY.float32
    for s in 0..1:
      let flip = if s == 0: 1.0'f32 else: -1.0'f32
      let col = if s == 0: accent else: bright
      # Blade runs from a lower corner to the opposite top corner. Everything
      # else is derived from that direction so the hilt parts stay square to
      # the blade instead of being eyeballed per side.
      let hilt = v2(px - flip * 15.0'f32, py + 16.0'f32)
      let tip = v2(px + flip * 15.0'f32, py - 17.0'f32)
      let dx = tip.x - hilt.x
      let dy = tip.y - hilt.y
      let len = sqrt(dx * dx + dy * dy)
      let ux = dx / len
      let uy = dy / len
      let perpX = -uy
      let perpY = ux
      # Blade: dark backing stroke, then the bright edge, stopping short so the
      # tip triangle forms the point.
      let bladeEnd = v2(tip.x - ux * 7.0'f32, tip.y - uy * 7.0'f32)
      drawStroke(hilt, tip, 6, Color(r: 8, g: 12, b: 20, a: 230))
      drawStroke(v2(hilt.x + ux * 8.0'f32, hilt.y + uy * 8.0'f32), bladeEnd, 3, col)
      drawIconTri(tip,
                  v2(bladeEnd.x + perpX * 3.2'f32, bladeEnd.y + perpY * 3.2'f32),
                  v2(bladeEnd.x - perpX * 3.2'f32, bladeEnd.y - perpY * 3.2'f32), col)
      # Crossguard: square to the blade, a fixed step up from the grip.
      let guard = v2(hilt.x + ux * 9.0'f32, hilt.y + uy * 9.0'f32)
      drawStroke(v2(guard.x + perpX * 6.5'f32, guard.y + perpY * 6.5'f32),
               v2(guard.x - perpX * 6.5'f32, guard.y - perpY * 6.5'f32), 3, dim)
      # Grip and pommel.
      drawStroke(hilt, guard, 3, dim)
      drawDisc(hilt, 3.2, bright)
    drawDisc(v2(px, py), 5.5, Color(r: 255, g: 255, b: 255, a: 215))
    drawDisc(v2(px, py), 2.6, accent)

  of diRoguelite:
    # Route map read bottom-to-top: you start at the base node, the path forks,
    # and the run ends at the boss diamond. The old flat 4-node cluster had no
    # direction to it.
    let mx = centerX.float32
    let my = centerY.float32
    let start = v2(mx, my + 17)
    let forkL = v2(mx - 14, my + 3)
    let forkR = v2(mx + 14, my + 3)
    let boss  = v2(mx, my - 15)
    let pathCol = Color(r: 120, g: 255, b: 220, a: 210)
    for (a, b) in [(start, forkL), (start, forkR), (forkL, boss), (forkR, boss)]:
      drawStroke(a, b, 4, Color(r: 8, g: 12, b: 20, a: 200))
      drawStroke(a, b, 2, pathCol)
    # Nodes: dark cores with bright rims so they stay legible over the paths.
    drawIconDisc(start.x, start.y, 5.5, Color(r: 8, g: 12, b: 20, a: 245), accent, 2.0)
    drawIconDisc(forkL.x, forkL.y, 5.5, Color(r: 8, g: 12, b: 20, a: 245), Gold, 2.0)
    drawIconDisc(forkR.x, forkR.y, 5.5, Color(r: 8, g: 12, b: 20, a: 245), accent, 2.0)
    # Boss node as a diamond, the one shape the others do not use.
    let bossCol = Color(r: 255, g: 110, b: 90, a: 255)
    drawIconTri(v2(boss.x, boss.y - 8), v2(boss.x - 8, boss.y), v2(boss.x, boss.y + 8), bossCol)
    drawIconTri(v2(boss.x, boss.y - 8), v2(boss.x, boss.y + 8), v2(boss.x + 8, boss.y), bossCol)
    drawDisc(v2(boss.x, boss.y), 2.6, Color(r: 255, g: 240, b: 220, a: 240))

  of diAdvancements:
    # Trophy. The old ledger-of-rows glyph collided with the help and changelog
    # documents; a cup is the one universally read "achievements" symbol.
    let tx = centerX.float32
    let ty = centerY.float32
    # Side handles, drawn before the cup so the cup laps over their roots.
    drawRing(v2(tx - 11.0, ty - 8.0), 4.5, 7.0, 90.0, 270.0, 18, dim)
    drawRing(v2(tx + 11.0, ty - 8.0), 4.5, 7.0, 270.0, 450.0, 18, dim)
    # Cup bowl, tapering to the stem.
    drawIconTri(v2(tx - 12, ty - 17), v2(tx - 9, ty + 2), v2(tx + 9, ty + 2), Gold)
    drawIconTri(v2(tx - 12, ty - 17), v2(tx + 9, ty + 2), v2(tx + 12, ty - 17), Gold)
    drawStroke(v2(tx - 12, ty - 17), v2(tx + 12, ty - 17), 3, bright)
    # Stem and base.
    drawRectangle((centerX - 3).int32, (centerY + 2).int32, 6, 7, dim)
    drawRectangle((centerX - 10).int32, (centerY + 9).int32, 20, 5, Gold)
    drawRectangle((centerX - 12).int32, (centerY + 14).int32, 24, 4, dim)
    # Star on the cup face: a 10-point fan alternating outer and inner radius
    # (a 5-point fan would just draw a pentagon).
    let starY = ty - 8.0'f32
    let starCol = Color(r: 255, g: 250, b: 225, a: 235)
    for i in 0..9:
      let a = -PI / 2.0'f32 + i.float32 * (PI / 5.0'f32)
      let b = a + (PI / 5.0'f32)
      let ra = if i mod 2 == 0: 7.0'f32 else: 3.1'f32
      let rb = if i mod 2 == 0: 3.1'f32 else: 7.0'f32
      drawIconTri(v2(tx, starY),
                  v2(tx + cos(a) * ra, starY + sin(a) * ra),
                  v2(tx + cos(b) * rb, starY + sin(b) * rb), starCol)

  of diChangelog:
    # Patch-notes document with a folded corner, text lines, and a "new" star
    let docX = centerX - 13
    let docY = centerY - 17
    drawRectangle(docX.int32, docY.int32, 26, 34, Color(r: 240, g: 240, b: 246, a: 255))
    drawRectOutline(Rectangle(x: docX.float32, y: docY.float32,
                                 width: 26.0, height: 34.0), 2, accent)
    # Folded top-right corner
    drawTriangle(Vector2(x: (docX + 26).float32, y: docY.float32),
                 Vector2(x: (docX + 26).float32, y: (docY + 9).float32),
                 Vector2(x: (docX + 17).float32, y: docY.float32), dim)
    # Text lines of varying length, each led by a bullet so it reads as notes.
    for i in 0..<4:
      let lineY = docY + 8 + i * 6
      let lineW = if i == 3: 9 else: 14 - (i mod 2) * 4
      drawDisc(v2((docX + 5).float32, (lineY + 1).float32), 1.4,
                 Color(r: 90, g: 130, b: 175, a: 235))
      drawRectangle((docX + 9).int32, lineY.int32, lineW.int32, 3,
                    Color(r: 70, g: 90, b: 120, a: 235))
    # Sparkle marking fresh changes
    let starX = (centerX + 12).float32
    let starY = (centerY + 14).float32
    drawStroke(Vector2(x: starX - 5, y: starY), Vector2(x: starX + 5, y: starY), 2, bright)
    drawStroke(Vector2(x: starX, y: starY - 5), Vector2(x: starX, y: starY + 5), 2, bright)
    drawDisc(Vector2(x: starX, y: starY), 1.5, White)

  of diCredits:
    # Terminal panel with a beating heart: credits + "support the project"
    let panelX = centerX - 18
    let panelY = centerY - 15
    drawRectangle(panelX.int32, panelY.int32, 36, 30, Color(r: 14, g: 18, b: 30, a: 255))
    drawRectOutline(Rectangle(x: panelX.float32, y: panelY.float32,
                                 width: 36.0, height: 30.0), 2, accent)
    # Title bar of the "window"
    drawRectangle(panelX.int32, panelY.int32, 36, 6, dim)
    for i in 0..<3:
      drawDisc(Vector2(x: (panelX + 5 + i * 6).float32, y: (panelY + 3).float32),
                 1.4, Color(r: 240, g: 240, b: 250, a: 220))
    # Heart, gently beating so the icon reads as a "thanks / support" affordance
    let beat = 1.0'f32 + sin(time * 3.2) * 0.09'f32
    let hx = centerX.float32
    let hy = (centerY + 2).float32
    let lobe = 4.6'f32 * beat
    drawDisc(Vector2(x: hx - lobe * 0.85, y: hy - lobe * 0.5), lobe, bright)
    drawDisc(Vector2(x: hx + lobe * 0.85, y: hy - lobe * 0.5), lobe, bright)
    drawTriangle(Vector2(x: hx - lobe * 1.72, y: hy - lobe * 0.15),
                 Vector2(x: hx, y: hy + lobe * 2.05),
                 Vector2(x: hx + lobe * 1.72, y: hy - lobe * 0.15), bright)
    drawDisc(Vector2(x: hx - lobe * 0.7, y: hy - lobe * 0.75), lobe * 0.3,
               Color(r: 255, g: 255, b: 255, a: 180))

  of diFeedback:
    # A software bug caught in a speech bubble: "tell us what broke". The
    # beetle's legs twitch so the icon reads as a live critter, not a blob.
    let bx = centerX.float32
    let by = centerY.float32 - 2.0'f32
    let bubble = Rectangle(x: bx - 18, y: by - 14, width: 36, height: 26)
    drawIconTri(v2(bx - 11, by + 10), v2(bx - 3, by + 10), v2(bx - 13, by + 19),
                accent)
    drawRectangleRounded(bubble, 0.35, 6, Color(r: 14, g: 18, b: 30, a: 255))
    drawRectangleRoundedLines(bubble, 0.35, 6, -2.0, accent)
    # Legs first so the shell laps over their roots; three per side.
    let twitch = sin(time * 9.0'f32) * 1.2'f32
    let legCol = Color(r: 230, g: 236, b: 245, a: 230)
    for i in 0..2:
      let ly = by - 4.0'f32 + i.float32 * 4.0'f32
      let tw = if i == 1: -twitch else: twitch
      drawStroke(v2(bx - 3, ly), v2(bx - 10, ly - 1.5'f32 + tw), 1.6, legCol)
      drawStroke(v2(bx + 3, ly), v2(bx + 10, ly - 1.5'f32 - tw), 1.6, legCol)
    # Antennae.
    drawStroke(v2(bx - 1.5'f32, by - 8), v2(bx - 5, by - 12), 1.4, legCol)
    drawStroke(v2(bx + 1.5'f32, by - 8), v2(bx + 5, by - 12), 1.4, legCol)
    # Head and split shell.
    drawDisc(v2(bx, by - 7), 2.8, dim)
    drawEllipse(bx.int32, (by + 1).int32, 5.5, 7.0, accent)
    drawStroke(v2(bx, by - 5), v2(bx, by + 8), 1.4, Color(r: 14, g: 18, b: 30, a: 255))
    drawDisc(v2(bx - 2.4'f32, by - 1), 1.1, bright)
    drawDisc(v2(bx + 2.4'f32, by + 3), 1.1, bright)

  of diMods:
    # A puzzle piece easing into its socket: add-ons plugged into the system.
    # The slow slide keeps it reading as "plug in" rather than as a static tile.
    let panel = Rectangle(x: centerX.float32 - 18, y: centerY.float32 - 16, width: 36, height: 32)
    let panelCol = Color(r: 14, g: 18, b: 30, a: 255)
    drawRectangleRounded(panel, 0.25, 6, panelCol)
    drawRectangleRoundedLines(panel, 0.25, 6, -2.0, dim)
    let slide = (sin(time * 2.0'f32) * 0.5'f32 + 0.5'f32) * 3.0'f32
    let px = centerX.float32 - 2.0'f32 + slide
    let py = centerY.float32 + 2.0'f32
    let s = 16.0'f32
    drawRectangleRounded(Rectangle(x: px - s / 2, y: py - s / 2, width: s, height: s), 0.2, 4, accent)
    drawDisc(v2(px, py - s / 2 - 1.5'f32), 3.8, accent)          # top tab
    drawDisc(v2(px + s / 2 + 1.5'f32, py), 3.8, accent)          # right tab
    drawDisc(v2(px - s / 2 + 0.5'f32, py), 3.4, panelCol)        # left slot
    drawDisc(v2(px, py + s / 2 - 0.5'f32), 3.4, panelCol)        # bottom slot
    drawDisc(v2(px - 3.5'f32, py - 3.5'f32), 1.6, bright)        # glint
  of diModApp:
    # A mod app: its own texture or model when it gave one, else a little window
    # showing the first letter of its name. The MOD tag marks it as not built in.
    let app = findModApp(icon.modKey)
    let look = if app >= 0: modApps[app].icon else: BodyReplace()
    let cx = centerX.float32
    let cy = centerY.float32
    if look.model > 0:
      drawModelIcon(look.model, cx, cy, 42, look.pose)
    elif look.id > 0:
      let (tw, th) = textureSize(look.id)
      let fit = 42.0'f32 / max(1.0'f32, max(tw, th).float32)
      drawModTexture(look.id, cx, cy, tw.float32 * fit, th.float32 * fit, 0, White)
    else:
      let frame = Rectangle(x: cx - 19, y: cy - 15, width: 38, height: 30)
      drawRectangleRounded(frame, 0.15, 4, Color(r: 14, g: 18, b: 30, a: 255))
      drawRectangleRoundedLines(frame, 0.15, 4, -2.0, accent)
      drawRectangle(int32(frame.x) + 2, int32(frame.y) + 2, int32(frame.width) - 4, 6, dim)
      # The first character, whole: a name may start with an accented letter.
      let letter = if icon.name.len > 0: unicode.toUpper($icon.name.runeAt(0)) else: "?"
      let lw = measureText(letter, 18)
      drawText(letter, centerX - lw div 2, centerY - 5, 18, bright)
    let tagX = icon.x.int32 + ICON_SIZE - 26
    let tagY = icon.y.int32 + ICON_SIZE - 12
    drawRectangle(tagX, tagY, 24, 10, Color(r: 8, g: 14, b: 24, a: 215))
    drawText("MOD", tagX + 3, tagY + 1, 8, bright)
  of diModMode:
    # A mod game mode: its own texture or model when it gave one, else a play
    # triangle on a little screen. Same MOD tag as the apps.
    let mi = findModMode(icon.modKey)
    let look = if mi >= 0: modModes[mi].icon else: BodyReplace()
    let cx = centerX.float32
    let cy = centerY.float32
    if look.model > 0:
      drawModelIcon(look.model, cx, cy, 42, look.pose)
    elif look.id > 0:
      let (tw, th) = textureSize(look.id)
      let fit = 42.0'f32 / max(1.0'f32, max(tw, th).float32)
      drawModTexture(look.id, cx, cy, tw.float32 * fit, th.float32 * fit, 0, White)
    else:
      let frame = Rectangle(x: cx - 19, y: cy - 15, width: 38, height: 30)
      drawRectangleRounded(frame, 0.15, 4, Color(r: 14, g: 18, b: 30, a: 255))
      drawRectangleRoundedLines(frame, 0.15, 4, -2.0, accent)
      let pulse = 1.0'f32 + sin(time * 3.0'f32) * 0.06'f32
      let h = 9.0'f32 * pulse
      drawTriangle(v2(cx - h * 0.6'f32, cy - h), v2(cx - h * 0.6'f32, cy + h),
                   v2(cx + h, cy), bright)
    let tagX = icon.x.int32 + ICON_SIZE - 26
    let tagY = icon.y.int32 + ICON_SIZE - 12
    drawRectangle(tagX, tagY, 24, 10, Color(r: 8, g: 14, b: 24, a: 215))
    drawText("MOD", tagX + 3, tagY + 1, 8, bright)

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
    drawCircleOutline(Vector2(x: lockCX.float32, y: (lockCY - 6).float32), shackleR, Color(r: 235, g: 240, b: 245, a: 220))
    drawRectangle((lockCX - lockW div 2).int32, (lockCY - 1).int32, lockW.int32, lockH.int32, Color(r: 235, g: 240, b: 245, a: 230))
    drawRectOutline(Rectangle(x: (lockCX - lockW div 2).float32, y: (lockCY - 1).float32,
                                 width: lockW.float32, height: lockH.float32), 2, Color(r: 18, g: 22, b: 28, a: 200))
    # keyhole
    drawRectangle(lockCX - 1, lockCY + 2, 3, 5, Color(r: 18, g: 22, b: 28, a: 255))

  # Icon label with shadow
  let labelY = icon.y + ICON_SIZE + 8
  drawDesktopLabel(icon.name, icon.x.int32, labelY.int32, selected)

proc drawCknStartButton(x, y, w, h: int, th: UiTheme) =
  ## The CKN shell's start button: a pill with the logo and a polite "Start".
  let rect = Rectangle(x: x.float32, y: y.float32, width: w.float32, height: h.float32)
  drawCknPanel(rect, h.float32 * 0.5'f32, mixColor(th.surface, White, 0.5'f32),
               mixColor(th.surface, th.raised, 0.75'f32))
  drawCknLogo((x + 22).float32, (y + h div 2 + 2).float32, 11.0'f32, arc = th.accent)
  let label = t(tkOSCknStartButton)
  drawText(label, (x + 40).int32, (y + (h - 16) div 2).int32,
           bestDesktopLabelFontSize(label, (w - 48).int32, 16), th.text)

proc drawTaskbar(screenWidth, screenHeight: int, time: float32) =
  ## Every theme draws the stock taskbar in its colours; the start button is
  ## the shell's own.
  # Taskbar background
  drawRectangle(0, (screenHeight - TASKBAR_HEIGHT).int32,
               screenWidth.int32, TASKBAR_HEIGHT.int32,
               uiSurface(20, 20, 30, 240))
  drawRectOutline(Rectangle(x: 0, y: (screenHeight - TASKBAR_HEIGHT).float32,
                                width: screenWidth.float32, height: TASKBAR_HEIGHT.float32),
                    1, uiLine(0, 200, 200))

  # Start button
  let startBtnW = 120
  let startBtnH = 32
  let startBtnX = 8
  let startBtnY = screenHeight - TASKBAR_HEIGHT + 4

  let th = activeTheme()
  case th.shell
  of ssTopHat:
    drawRectangle(startBtnX.int32, startBtnY.int32, startBtnW.int32, startBtnH.int32,
                 uiSurface(0, 60, 80))
    drawRectOutline(Rectangle(x: startBtnX.float32, y: startBtnY.float32,
                                  width: startBtnW.float32, height: startBtnH.float32), 2,
                      uiLine(0, 200, 255))

    # Logo in start button
    let logoSize = 16
    drawRectangle((startBtnX + 10).int32, (startBtnY + 8).int32,
                 logoSize.int32, logoSize.int32,
                 uiInk(0, 200, 255))

    drawText(t("os_tophat_button"), (startBtnX + 35).int32, (startBtnY + 7).int32, 18, uiInk(White))
  of ssCkn:
    drawCknStartButton(startBtnX, startBtnY, startBtnW, startBtnH, th)

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
  let clockCol = uiInk(0, 255, 255)
  let hhW = measureText(hhStr, 16)
  let colonW = measureText(":", 16)
  drawText(hhStr, clockX.int32, clockY.int32, 16, clockCol)
  if currentTime.nanosecond < 500_000_000:
    drawText(":", (clockX + hhW).int32, clockY.int32, 16, clockCol)
  drawText(mmStr, (clockX + hhW + colonW).int32, clockY.int32, 16, clockCol)
  drawText(dateStr, (clockX - 10).int32, (clockY + 16).int32, 12,
          uiInk(100, 200, 200))

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
  let spkCol = if muted: uiInk(255, 110, 110)
               else: uiInk(175, 228, 228)
  # Speaker: a solid cone (back box + triangular flare).
  drawRectangle(volX.int32, (cy - 3.0'f32).int32, 4, 6, spkCol)
  drawTriangle(Vector2(x: (volX + 4).float32, y: cy - 6.0'f32),
               Vector2(x: (volX + 4).float32, y: cy + 6.0'f32),
               Vector2(x: (volX + 11).float32, y: cy), spkCol)
  if muted:
    # Muted: a red cross where the sound waves would be.
    drawStroke(Vector2(x: (volX + 15).float32, y: cy - 5.0'f32),
             Vector2(x: (volX + 23).float32, y: cy + 5.0'f32), 2, spkCol)
    drawStroke(Vector2(x: (volX + 23).float32, y: cy - 5.0'f32),
             Vector2(x: (volX + 15).float32, y: cy + 5.0'f32), 2, spkCol)
  else:
    # Concentric sound-wave arcs; each lights as the volume crosses its band.
    let waveCenter = Vector2(x: (volX + 9).float32, y: cy)
    for i in 0..2:
      let r = 6.5'f32 + i.float32 * 4.0'f32
      let lit = vol >= i.float32 / 3.0'f32
      let arcCol = if lit: uiInk(0, 235, 205)
                   else: uiLine(45, 70, 75, 180)
      drawRing(waveCenter, r - 1.0'f32, r + 0.6'f32, -52.0'f32, 52.0'f32, 14, arcCol)
  # Percentage label removes any doubt about what the icon represents.
  let pctText = $int(round(vol * 100.0'f32)) & "%"
  drawText(pctText, (volX + 28).int32, (clockY + 3).int32, 12,
           if muted: uiInk(255, 130, 130)
           else: uiInk(135, 212, 212))

  # System indicators with icons
  let indicatorX = screenWidth - 146
  # Network indicator: a "connected" LED that softly pulses so it reads as live.
  let netPulse = (sin(time * 3.0) * 0.5 + 0.5)
  let netAlpha = uint8(170.0 + netPulse * 85.0)
  drawRectangle(indicatorX.int32, (clockY + 6).int32, 12, 8,
               uiInk(50, 255, 50, netAlpha.int))
  drawText(t(tkDesktopNet), (indicatorX + 16).int32, (clockY + 3).int32, 12,
          uiInk(150, 150, 150))

proc drawDesktopWallpaper*(screenWidth, screenHeight: int, time,
                          cubeRotX, cubeRotY, cubeRotZ: float32,
                          cubeOffsetX: float32 = 0.0, cubeOffsetY: float32 = 0.0,
                          modCube = false) =
  ## `modCube`: the live desktop, where a mod's cube model stands in for the
  ## cube (the shop's preview cards keep showing the built-in one).
  # Translucent light adds up instead of darkening the frame (see ui_theme).
  beginKeepAlpha()
  defer: endKeepAlpha()
  drawSharedBackdrop(screenWidth.int32, screenHeight.int32, time * 0.62,
                     Color(r: 5, g: 8, b: 18, a: 255),
                     Color(r: 18, g: 17, b: 34, a: 255),
                     Color(r: 38, g: 54, b: 78, a: 34),
                     Color(r: 95, g: 130, b: 174, a: 70),
                     Color(r: 0, g: 184, b: 225, a: 48),
                     0.9, 0.8)

  let w = screenWidth.float32
  let h = screenHeight.float32
  let s = min(w, h)
  let u = max(s / 768.0'f32, 0.3'f32)
  let centerX = w * CubeAnchorX
  let centerY = h * CubeAnchorY
  let c = Vector2(x: centerX, y: centerY)

  # Light: a cyan pool around the cube, cooler washes in two corners.
  drawGlow(c, s * 0.62'f32, Color(r: 0, g: 170, b: 220, a: 90))
  drawGlow(Vector2(x: w * 0.18'f32, y: h * 0.18'f32), s * 0.44'f32, Color(r: 95, g: 130, b: 255, a: 62))
  drawGlow(Vector2(x: w * 0.88'f32, y: h * 0.82'f32), s * 0.46'f32, Color(r: 0, g: 220, b: 165, a: 52))

  # A slow radar sweep turning under the rings.
  let sweep = time * 0.35'f32
  let sweepR = s * 0.4'f32
  const SweepSteps = 10
  for k in 0 ..< SweepSteps:
    let a0 = sweep - k.float32 * 0.06'f32
    let a1 = sweep - (k + 1).float32 * 0.06'f32
    let fadeK = 1.0'f32 - k.float32 / SweepSteps.float32
    drawGradientTriangle(c, Vector2(x: centerX + cos(a0) * sweepR, y: centerY + sin(a0) * sweepR),
                         Vector2(x: centerX + cos(a1) * sweepR, y: centerY + sin(a1) * sweepR),
                         Color(r: 80, g: 220, b: 255, a: uint8(26.0'f32 * fadeK)),
                         Color(r: 80, g: 220, b: 255, a: 0), Color(r: 80, g: 220, b: 255, a: 0))
  drawStroke(c, Vector2(x: centerX + cos(sweep) * sweepR, y: centerY + sin(sweep) * sweepR),
             max(0.5'f32, 1.0'f32 * u), Color(r: 120, g: 235, b: 255, a: 70))

  # Orbital rings: a gyroscope of thin rings, each with dashed arcs of light
  # turning the opposite way to its neighbours and a glowing node riding it.
  for i in 0..4:
    let ringRadius = s * (0.18'f32 + i.float32 * 0.055'f32)
    drawCircleOutline(c, ringRadius, Color(r: 80, g: 210, b: 255, a: uint8(26 + i * 9)))
    let dir = if (i and 1) == 0: 1.0'f32 else: -1.0'f32
    let spin = time * (0.12'f32 + i.float32 * 0.03'f32) * dir * 180.0'f32 / PI + i.float32 * 47.0'f32
    for d in 0 ..< 3:
      let start = spin + d.float32 * 120.0'f32
      drawRing(c, ringRadius - max(0.4'f32, 1.0'f32 * u), ringRadius + max(0.4'f32, 1.0'f32 * u),
               start, start + 22.0'f32 + i.float32 * 4.0'f32, 10,
               Color(r: 120, g: 230, b: 255, a: uint8(60 + i * 10)))
    let angle = time * (0.22'f32 + i.float32 * 0.04'f32) + i.float32 * PI * 0.38'f32
    let node = Vector2(x: centerX + cos(angle) * ringRadius, y: centerY + sin(angle) * ringRadius)
    drawGlow(node, 10.0'f32 * u, Color(r: 120, g: 240, b: 255, a: 120))
    drawDisc(node, max(0.6'f32, (2.4'f32 + i.float32 * 0.3'f32) * u),
             Color(r: 190, g: 250, b: 255, a: uint8(170 + i * 16)))
  # Tick marks round the outermost ring, like a dial.
  let tickR = s * (0.18'f32 + 4.0'f32 * 0.055'f32) + 6.0'f32 * u
  for t in 0 ..< 72:
    let a = t.float32 / 72.0'f32 * PI * 2.0'f32 + time * 0.02'f32
    let major = t mod 6 == 0
    let len = (if major: 8.0'f32 else: 3.5'f32) * u
    drawStroke(Vector2(x: centerX + cos(a) * tickR, y: centerY + sin(a) * tickR),
               Vector2(x: centerX + cos(a) * (tickR + len), y: centerY + sin(a) * (tickR + len)),
               max(0.4'f32, 1.0'f32 * u), Color(r: 90, g: 220, b: 255, a: (if major: 80'u8 else: 38'u8)))

  let currentCubeSkin = if not globalSettings.isNil: CubeSkinType(globalSettings.cubeSkin) else: cskDefault
  if not (modCube and drawCubeModModel(centerX + cubeOffsetX, centerY + cubeOffsetY,
                                       s * 0.042'f32, cubeRotX, cubeRotY, cubeRotZ)):
    drawZeroGravityWallpaperCube(centerX + cubeOffsetX, centerY + cubeOffsetY,
                                 s * 0.042'f32, time,
                                 cubeRotX, cubeRotY, cubeRotZ, currentCubeSkin)

  # Thin scan bands and routing traces.
  for i in 0..<14:
    let y = ((i.float32 * 67.0 + time * (16.0 + i.float32 * 1.7)) mod (h + 90.0)) - 45.0
    let sway = sin(time * 0.7 + i.float32) * 32.0
    let alpha = uint8(18 + (i mod 4) * 8)
    drawStroke(Vector2(x: -40.0, y: y),
             Vector2(x: w + 40.0, y: y + sway * 0.18),
             1, Color(r: 0, g: 198, b: 238, a: alpha))
    if i mod 3 == 0:
      let x = (w * (0.22 + (i mod 5).float32 * 0.13) + sway) mod max(w, 1.0)
      drawTaperedLine(Vector2(x: x, y: y - 28.0), Vector2(x: x, y: y + 32.0), 0.0'f32, 1.6'f32,
                      Color(r: 85, g: 240, b: 255, a: 0), Color(r: 85, g: 240, b: 255, a: uint8(alpha + 60)))
      drawGlow(Vector2(x: x, y: y), 8.0'f32, Color(r: 120, g: 240, b: 255, a: 110))
      drawDisc(Vector2(x: x, y: y), 2.2, Color(r: 190, g: 250, b: 255, a: 180))

  # Left-side launch column silhouette keeps icons readable over the animation.
  drawRectangleGradientH(0, 0, min(310, screenWidth).int32, screenHeight.int32,
                         Color(r: 2, g: 5, b: 12, a: 155),
                         Color(r: 2, g: 5, b: 12, a: 0))
  drawStroke(Vector2(x: 250.0, y: 42.0),
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
  drawRectangle(barX, barY, barW, barH, uiSurface(20, 28, 42, 235))
  for q in 1 .. 3:
    drawRectangle(barX + (barW * q.int32) div 4, barY, 1, barH,
                  uiLine(0, 70, 90, 150))
  # Fill, top highlight, bright cap + glow
  let fillW = int32(barW.float32 * clamp(pct, 0.0'f32, 100.0'f32) / 100.0'f32)
  if fillW > 1:
    drawRectangle(barX, barY, fillW, barH, withAlpha(color, 205))
    drawRectangle(barX, barY, fillW, 1,
                  Color(r: uint8(min(255, color.r.int + 60)),
                        g: uint8(min(255, color.g.int + 60)),
                        b: uint8(min(255, color.b.int + 60)), a: 220))
    let capX = barX + fillW
    drawRectangle(capX - 2, barY, 2, barH, uiGlow(255, 255, 255, 170))
    drawSoftGlow(capX.float32, (barY + barH div 2).float32, 7.0'f32,
                 withAlpha(color, 130), 1.0'f32)
  drawRectOutline(Rectangle(x: barX.float32, y: barY.float32,
                               width: barW.float32, height: barH.float32), 1,
                     uiLine(0, 90, 110, 150))
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
  drawGlow(Vector2(x: cx, y: cy), cubeSize * (3.2'f32 + g * 6.0'f32),
           Color(r: 255, g: 145, b: 35, a: uint8(min(255.0'f32, 120.0'f32 * g * flick))))
  drawGlow(Vector2(x: cx, y: cy), cubeSize * (1.8'f32 + g * 2.8'f32),
           Color(r: 255, g: 195, b: 95, a: uint8(min(255.0'f32, 110.0'f32 * g * flick))))

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
      let eye = Vector2(x: eex, y: ey)
      drawGlow(eye, sc * 1.9'f32, Color(r: 175, g: 210, b: 70, a: uint8(min(255.0'f32, glowA.float32 * 1.4'f32))))
      drawRadialGradient(eye, sc * 0.72'f32, max(0.5'f32, sc * 0.46'f32 * open),
                         Color(r: 240, g: 245, b: 150, a: eyeA), eyeCol, reSmooth)
      drawRadialGradient(eye, sc * 0.16'f32, max(0.5'f32, sc * 0.4'f32 * open), darkSlit, darkSlit, reLinear, 1)

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

proc drawDesktopCube(desktop: OSDesktop, w, h: float32,
                     jitterX = 0.0'f32, jitterY = 0.0'f32) =
  ## The interactive cube in its orbit slot, plus the dice-roll result above it.
  ## Drawn by the themed backgrounds and by a mod wallpaper that keeps the cube.
  beginKeepAlpha()   # its glass adds light instead of darkening the frame
  defer: endKeepAlpha()
  let centerX = w * CubeAnchorX
  let centerY = h * CubeAnchorY
  let skin = if not globalSettings.isNil: CubeSkinType(globalSettings.cubeSkin) else: cskDefault
  # A mod's cube model (override.model("cube") / a desktop cosmetic) turns
  # with the same drag-and-spin rotation the cube would.
  if not drawCubeModModel(centerX + desktop.cubeOffsetX + jitterX,
                          centerY + desktop.cubeOffsetY + jitterY, min(w, h) * 0.042'f32,
                          desktop.cubeRotX, desktop.cubeRotY, desktop.cubeRotZ):
    drawZeroGravityWallpaperCube(centerX + desktop.cubeOffsetX + jitterX,
                                 centerY + desktop.cubeOffsetY + jitterY,
                                 min(w, h) * 0.042'f32, desktop.time,
                                 desktop.cubeRotX, desktop.cubeRotY, desktop.cubeRotZ,
                                 skin, desktop.cubeJackGlow)

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

proc drawToastStack(desktop: OSDesktop, screenWidth, bottom: int32) =
  ## The toast stack in the bottom-right corner, newest lowest, its bottom
  ## card 14px above `bottom` (the taskbar on the desktop, the screen edge
  ## over a game screen).
  let toastH = 52'i32
  let spacing = 8'i32
  let th = activeTheme()
  for j in 0 ..< min(desktop.toasts.len, MAX_DESKTOP_TOASTS):
    let toast = desktop.toasts[desktop.toasts.len - 1 - j]
    let fade = min(1.0'f32, toast.timer / 0.6'f32)
    let alpha = uint8(255.0'f32 * fade)
    let toastW = max(260'i32, measureText(toast.text, 16) + 64)
    let toastX = screenWidth - toastW - 16
    let toastY = bottom - toastH - 14 - j.int32 * (toastH + spacing)
    let textY = toastY + (toastH - 16) div 2
    case th.shell
    of ssTopHat:
      drawRectangle(toastX, toastY, toastW, toastH,
                    uiSurface(12, 22, 34, int(232.0'f32 * fade)))
      drawRectOutline(Rectangle(x: toastX.float32, y: toastY.float32,
                                   width: toastW.float32, height: toastH.float32), 2,
                         uiLine(255, 210, 80, alpha.int))
      drawHexBadge(toastX + 26, toastY + toastH div 2, 14.0,
                   uiSurface(60, 44, 8, int(220.0'f32 * fade)),
                   uiLine(255, 210, 80, alpha.int))
      drawText(toast.text, toastX + 48, textY, 16, uiInk(235, 245, 255, alpha.int))
    of ssCkn:
      drawCknPanel(Rectangle(x: toastX.float32, y: toastY.float32,
                             width: toastW.float32, height: toastH.float32), 10.0'f32,
                   withAlpha(th.surface, 250.0'f32 * fade),
                   withAlpha(mixColor(th.surface, th.raised, 0.75'f32), alpha),
                   shadowAlpha = 70.0'f32 * fade)
      drawDisc(Vector2(x: (toastX + 26).float32, y: (toastY + toastH div 2).float32), 15.0'f32,
               withAlpha(mixColor(th.surface, th.accent, 0.14'f32), alpha))
      drawCknLogo((toastX + 26).float32, (toastY + toastH div 2 + 2).float32, 10.0'f32, fade,
                  arc = th.accent)
      drawText(toast.text, toastX + 48, textY, 16, withAlpha(th.text, alpha))

proc drawSystemMonitor(desktop: OSDesktop, screenWidth: int) =
  ## The System Monitor widget (top-right). Decorative readout: the bars show
  ## smoothly-drifting simulated load so the panel feels alive. Only Uptime is
  ## real (desktop session time).
  let panelW = 240'i32
  let panelH = 128'i32
  let panelX = (screenWidth - panelW.int - 14).int32
  let panelY = 12'i32
  let tm = desktop.time

  # Depth halo, gradient body, crisp border. A light theme lifts the panel
  # with a shadow instead: on its surfaces a halo is just a pale disc.
  if activeTheme().light:
    drawRectangle(panelX + 2, panelY + 4, panelW, panelH, withAlpha(CknShadow, 70))
  else:
    drawSoftGlow((panelX + panelW div 2).float32, (panelY + panelH div 2).float32,
                 panelW.float32 * 0.62'f32, uiGlow(0, 120, 150, 24), 1.0'f32)
  drawRectangleGradientV(panelX, panelY, panelW, panelH,
                         uiSurface(18, 26, 38, 222),
                         uiSurface(9, 13, 22, 222))
  drawRectOutline(Rectangle(x: panelX.float32, y: panelY.float32,
                               width: panelW.float32, height: panelH.float32), 1,
                     uiLine(0, 180, 190, 210))
  # Corner accents
  let corner = uiLine(0, 235, 235, 235)
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
                         uiSurface(0, 56, 78, 235),
                         uiSurface(0, 32, 48, 235))
  drawText(t(tkOSSystemMonitor), panelX + 9, panelY + 5, 14,
           uiInk(120, 235, 235))
  let pulse = sin(tm * 3.0'f32) * 0.5'f32 + 0.5'f32
  drawDisc(Vector2(x: (panelX + panelW - 16).float32, y: (panelY + 11).float32),
             4.0'f32, uiInk(70, 255, 120, int(110.0'f32 + pulse * 145.0'f32)))

  # CPU sparkline (scrolling filled waveform)
  let gx = panelX + 9
  let gy = panelY + 30
  let gw = panelW - 18
  const gh = 30'i32
  drawRectangle(gx, gy, gw, gh, uiSurface(8, 14, 22, 215))
  for i in 0 ..< gw.int:
    let v = simUsage(tm - (gw.int - i).float32 * 0.05'f32,
                     40.0'f32, 3.5'f32, 0.12'f32, 0.0'f32) / 100.0'f32
    let h = int32(v * gh.float32)
    drawRectangle(gx + i.int32, gy + gh - h, 1, h, uiGlow(0, 190, 160, 70))
    drawRectangle(gx + i.int32, gy + gh - h, 1, 1, uiInk(90, 255, 210, 200))
  drawRectOutline(Rectangle(x: gx.float32, y: gy.float32,
                               width: gw.float32, height: gh.float32), 1,
                     uiLine(0, 80, 100, 140))

  # Metric bars
  var rowY = panelY + 68
  drawUsageRow(panelX, panelW, rowY, "CPU",
               simUsage(tm, 40.0'f32, 3.5'f32, 0.12'f32, 0.0'f32),
               uiInk(80, 230, 120))
  rowY += 20
  drawUsageRow(panelX, panelW, rowY, t(tkOSMemory),
               simUsage(tm, 40.0'f32, 2.5'f32, 0.08'f32, 2.0'f32),
               uiInk(90, 180, 255))

  # Uptime (real desktop session time)
  let uptime = int(desktop.time)
  let hours = uptime div 3600
  let minutes = (uptime mod 3600) div 60
  let seconds = uptime mod 60
  drawText(&"Uptime  {hours:02d}:{minutes:02d}:{seconds:02d}",
           panelX + 9, panelY + panelH - 18, 12,
           uiInk(170, 190, 210, 200))

proc fract(x: float32): float32 {.inline.} = x - floor(x)

proc drawDawnGlow(cx, cy, radius: float32, color: Color) =
  ## Light that fades to nothing at its rim, `color.a` opaque at the centre.
  ## drawSoftGlow's six discs band visibly at a sun's size.
  const Layers = 24
  let perLayer = 1.0'f32 - pow(1.0'f32 - color.a.float32 / 255.0'f32, 1.0'f32 / Layers.float32)
  for i in countdown(Layers, 1):
    drawDisc(Vector2(x: cx, y: cy), radius * i.float32 / Layers.float32,
             withAlpha(color, perLayer * 255.0'f32))

proc drawCknWallpaper*(w, h, t: float32, desktop: OSDesktop = nil) =
  ## CKN OS's own wallpaper, its logo as a landscape: a dawn sky, the sun
  ## half-risen on the horizon right under the cube, the logo's blue arcs
  ## around it. Below the line lies the old floor, a faint grid running to the
  ## horizon: everything that was here first. `t` animates it; the desktop's
  ## cube floats over the sun when there is a desktop to take it from.
  # Light adds up here the way it looks. The default blend also blends the
  # frame's alpha down under every translucent layer, and the frame is shown
  # premultiplied over black (post_fx.nim), so on this opaque, fairly bright
  # sky stacked glows would read as dark halos. Keeping alpha opaque fixes it.
  beginKeepAlpha()
  defer: endKeepAlpha()
  let horizon = h * 0.68'f32
  let sunX = w * 0.64'f32
  let sunR = min(w, h) * 0.13'f32

  drawRectangleGradientV(0, 0, w.int32, horizon.int32 + 1,
                         Color(r: 20, g: 36, b: 76, a: 255), Color(r: 86, g: 134, b: 206, a: 255))
  # The last stars, fading out toward the light.
  for i in 0..<36:
    let sx = fract(sin(i.float32 * 12.9898'f32) * 43758.547'f32) * w
    let sy = fract(sin(i.float32 * 78.233'f32) * 23421.631'f32) * horizon * 0.55'f32
    let fadeDown = 1.0'f32 - sy / (horizon * 0.55'f32)
    let twinkle = 0.55'f32 + 0.45'f32 * sin(t * (0.6'f32 + (i mod 5).float32 * 0.23'f32) + i.float32)
    drawDisc(Vector2(x: sx, y: sy), 1.1'f32 + (i mod 3).float32 * 0.35'f32,
             Color(r: 236, g: 240, b: 255, a: clampByteF(120.0'f32 * fadeDown * twinkle)))

  # Dawn: warm light pooling on the horizon around the sun.
  drawDawnGlow(sunX, horizon, sunR * 3.6'f32, Color(r: 255, g: 168, b: 96, a: 120))
  drawDawnGlow(sunX, horizon, sunR * 1.9'f32, Color(r: 255, g: 204, b: 132, a: 130))
  drawDisc(Vector2(x: sunX, y: horizon), sunR, CknSun)
  drawDisc(Vector2(x: sunX, y: horizon), sunR * 0.82'f32, Color(r: 255, g: 214, b: 140, a: 255))

  # The logo's arc, echoed: slow blue rings over the sun.
  for i in 0..2:
    let r = sunR * (1.45'f32 + i.float32 * 0.42'f32) + sin(t * 0.5'f32 + i.float32 * 1.3'f32) * 3.0'f32
    drawRing(Vector2(x: sunX, y: horizon), r, r + 4.0'f32 - i.float32, 180.0'f32, 360.0'f32, 64,
             Color(r: 150, g: 196, b: 255, a: uint8(110 - i * 30)))

  # Clouds drifting across the light.
  for i in 0..<5:
    let span = w + 400.0'f32
    let cx = fract((i.float32 * 0.37'f32) + t * (0.004'f32 + i.float32 * 0.0015'f32)) * span - 200.0'f32
    let cy = horizon * (0.22'f32 + (i mod 3).float32 * 0.17'f32)
    let rx = 120.0'f32 + (i mod 2).float32 * 70.0'f32
    for k in 0..2:
      drawEllipse((cx + k.float32 * rx * 0.45'f32).int32, (cy - k.float32 * 6.0'f32).int32,
                  rx * (0.7'f32 - k.float32 * 0.15'f32), 14.0'f32 + k.float32 * 4.0'f32,
                  Color(r: 255, g: 255, b: 255, a: 13))

  # Below the line: deep, still ground (it covers the sun's lower half).
  drawRectangleGradientV(0, horizon.int32, w.int32, (h - horizon).int32 + 1,
                         Color(r: 30, g: 54, b: 110, a: 255), Color(r: 10, g: 20, b: 46, a: 255))
  # The sun's reflection, shimmering.
  for i in 0..<9:
    let ry = horizon + 6.0'f32 + i.float32 * 9.0'f32
    let half = sunR * (0.95'f32 - i.float32 * 0.09'f32) * (0.85'f32 + 0.15'f32 * sin(t * 1.7'f32 + i.float32))
    drawRectangle((sunX - half).int32, ry.int32, (half * 2.0'f32).int32, 3,
                  Color(r: 255, g: 190, b: 110, a: uint8(max(0, 120 - i * 13))))
  # The old floor: a grid running to the horizon.
  let floorH = h - horizon
  for i in -10..10:
    drawStroke(Vector2(x: sunX, y: horizon), Vector2(x: sunX + i.float32 * w * 0.16'f32, y: h),
               1, Color(r: 120, g: 170, b: 240, a: 22))
  for i in 1..7:
    let ly = horizon + floorH * pow(i.float32 / 7.0'f32, 1.8'f32)
    drawStroke(Vector2(x: 0, y: ly), Vector2(x: w, y: ly), 1, Color(r: 120, g: 170, b: 240, a: 20))
  # The line itself.
  drawRectangle(0, horizon.int32 - 1, w.int32, 2, Color(r: 170, g: 206, b: 255, a: 200))

  # The launch column keeps its icons readable over the sky.
  drawRectangleGradientH(0, 0, min(310'i32, w.int32), h.int32,
                         Color(r: 8, g: 16, b: 40, a: 120), Color(r: 8, g: 16, b: 40, a: 0))

  if not desktop.isNil:
    drawDesktopCube(desktop, w, h)

proc drawThemeWallpaper*(th: UiTheme, w, h, time: float32, desktop: OSDesktop = nil) =
  ## The free default background in theme `th`: a mod theme's own image (the
  ## cube floating over it), else its shell's wallpaper. `desktop` supplies the
  ## live cube; without one (a shop thumbnail) the stock wallpaper shows an
  ## unturned cube and CKN Dawn none.
  if th.wallpaper > 0:
    drawModTexture(th.wallpaper, 0, 0, w, h, 0, White, centered = false)
    if not desktop.isNil:
      drawDesktopCube(desktop, w, h)
    return
  case th.shell
  of ssTopHat:
    if desktop.isNil:
      drawDesktopWallpaper(w.int, h.int, time, 0.0'f32, 0.0'f32, 0.0'f32)
    else:
      # Exact, hardcoded wallpaper (keeps cube rotations and all effects)
      drawDesktopWallpaper(w.int, h.int, desktop.time,
                           desktop.cubeRotX, desktop.cubeRotY, desktop.cubeRotZ,
                           desktop.cubeOffsetX, desktop.cubeOffsetY, modCube = true)
  of ssCkn:
    drawCknWallpaper(w, h, time, desktop)

proc drawOSDesktopLayer(desktop: OSDesktop, screenWidth, screenHeight: int)

proc drawOSDesktop*(desktop: OSDesktop, screenWidth, screenHeight: int) =
  ## Draw the active desktop background. If the player has selected a desktop
  ## background from settings/shop use that otherwise fall back to the
  ## interface theme's own wallpaper. The lore intro films this desktop as
  ## TopHat-ShooterOS (withTheme(stockTheme())).
  themeLayer:
    drawOSDesktopLayer(desktop, screenWidth, screenHeight)

proc drawOSDesktopLayer(desktop: OSDesktop, screenWidth, screenHeight: int) =
  var selectedBg: DesktopBgType = dbgDefault
  if not globalSettings.isNil:
    selectedBg = DesktopBgType(globalSettings.desktopBg)

  # A mod wallpaper (equipped cosmetic or override.texture("desktop")) covers
  # the screen instead of the built-in background; the cube stays on top only
  # when the mod asked for it (cube = true) or gave it a model.
  if drawDesktopModBackground(screenWidth.int32, screenHeight.int32):
    if modWallpaper().cube:
      drawDesktopCube(desktop, screenWidth.float32, screenHeight.float32)
  else:
    case selectedBg
    of dbgDefault:
      drawThemeWallpaper(activeTheme(), screenWidth.float32, screenHeight.float32,
                         desktop.time, desktop)
    else:
      let w = screenWidth.float32
      let h = screenHeight.float32
      drawDesktopBgScene(selectedBg, screenWidth.int32, screenHeight.int32, desktop.time)

      let centerX = w * CubeAnchorX
      let centerY = h * CubeAnchorY
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

      drawDesktopCube(desktop, w, h, tremX, tremY)

  # Desktop icons
  for icon in desktop.icons:
    drawDesktopIcon(icon, desktop.time, icon.selected)

  # Taskbar
  drawTaskbar(screenWidth, screenHeight, desktop.time)

  drawSystemMonitor(desktop, screenWidth)

  # Bottom desktop info (version and edition): on the wallpaper, the shell's
  case activeTheme().shell
  of ssTopHat:
    drawText(t(tkOSTopHatOS), 10, (screenHeight - 75).int32, 14,
            Color(r: 100, g: 100, b: 120, a: 200))
    drawText(t(tkOSEdition), 10, (screenHeight - 58).int32, 12,
            Color(r: 150, g: 150, b: 170, a: 180))
  of ssCkn:
    drawText(themeName(activeTheme()), 10, (screenHeight - 75).int32, 14,
            Color(r: 236, g: 240, b: 246, a: 210))
    drawText(t(tkOSCknEdition), 10, (screenHeight - 58).int32, 12,
            Color(r: 190, g: 204, b: 226, a: 180))

  # Transient OS-style toasts above the taskbar (bottom-right), stacked
  drawToastStack(desktop, screenWidth.int32, (screenHeight - TASKBAR_HEIGHT).int32)

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
  themeLayer:
    drawToastStack(desktop, screenWidth, screenHeight)

# Desktop grid shape for keyboard navigation. It is derived from the layout
# layoutDesktopIcons actually produced rather than hard-coded, so navigation
# follows the grid when a short viewport (UI scale above 100%) reflows it into
# more, shorter columns. The corner-anchored icons (last in the seq) form one
# trailing column, matching how they are stacked on screen, which is how
# diFeedback and diCredits stay reachable from the keyboard.
proc desktopGridColumns(desktop: OSDesktop): tuple[rows, builtin, apps, cols: int] =
  ## Columns left to right: the built-in grid, then the mod-app columns (same
  ## row count, starting fresh), then the corner column if there is one.
  let rows = max(1, desktop.gridRows)
  var nb, na = 0
  for icon in desktop.icons:
    if isModIcon(icon.iconType): inc na
    elif not isCornerIcon(icon.iconType): inc nb
  let corner = desktop.icons.len - nb - na
  (rows, nb, na, (nb + rows - 1) div rows + (na + rows - 1) div rows + (if corner > 0: 1 else: 0))

proc desktopColLen(desktop: OSDesktop, col: int): int =
  ## Number of icons in column `col`: the flowed grid columns first, then the
  ## mod-app columns, then the one column holding every corner-anchored icon.
  let (rows, nb, na, _) = desktopGridColumns(desktop)
  let gridCols = (nb + rows - 1) div rows
  let appCols = (na + rows - 1) div rows
  if col < gridCols: min(rows, nb - col * rows)
  elif col < gridCols + appCols: min(rows, na - (col - gridCols) * rows)
  else: desktop.icons.len - nb - na

proc iconGridPos(desktop: OSDesktop, index: int): tuple[col, row: int] =
  ## Map a flat icon index onto its (column, row) slot.
  let cols = desktopGridColumns(desktop).cols
  var remaining = index
  for c in 0 ..< cols:
    let len = desktopColLen(desktop, c)
    if remaining < len:
      return (c, remaining)
    remaining -= len
  (max(0, cols - 1), 0)

proc iconGridIndex(desktop: OSDesktop, col, row: int): int =
  ## Inverse of iconGridPos, clamping the row into the target column's length.
  let cols = desktopGridColumns(desktop).cols
  let c = clamp(col, 0, cols - 1)
  result = 0
  for i in 0 ..< c:
    result += desktopColLen(desktop, i)
  result += clamp(row, 0, desktopColLen(desktop, c) - 1)

proc handleDesktopInput*(desktop: OSDesktop, game: Game): int =
  ## Returns selected menu option: 0=Play, 1=Survival, 2=Stats, 3=Settings, 4=Shop, 5=Help, 6=Quit, 7=Sandbox, 9=Roguelite, 10=Advancements, 11=Changelog, 12=Credits, 13=Feedback, 14=Mods, 15=a mod app / 16=a mod game mode (desktop.launchModKey)
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
        of diModApp, diModMode:
          desktop.launchModKey = clicked.modKey
          return clicked.iconType.int
        else:
          return clicked.iconType.int

  # Keyboard navigation, arrow keys AND WASD, with full 2D grid support.
  # Moving any direction marks keyboard as in-use so the mouse won't jump the cursor.
  let (col, row) = iconGridPos(desktop, desktop.selectedIcon)
  let colLen = desktopColLen(desktop, col)
  let colCount = desktopGridColumns(desktop).cols

  if isKeyPressed(Down) or isKeyPressed(S):
    desktop.selectedIcon = iconGridIndex(desktop, col, (row + 1) mod colLen)
    game.keyboardUsedRecently = true
    game.mouseMovedRecently = false
    return -1

  if isKeyPressed(Up) or isKeyPressed(W):
    desktop.selectedIcon = iconGridIndex(desktop, col, (row - 1 + colLen) mod colLen)
    game.keyboardUsedRecently = true
    game.mouseMovedRecently = false
    return -1

  if isKeyPressed(Right) or isKeyPressed(D):
    if col < colCount - 1:
      # Next column to the right, clamping the row to that column's length
      desktop.selectedIcon = iconGridIndex(desktop, col + 1, row)
      game.keyboardUsedRecently = true
      game.mouseMovedRecently = false
    return -1

  if isKeyPressed(Left) or isKeyPressed(A):
    if col > 0:
      desktop.selectedIcon = iconGridIndex(desktop, col - 1, row)
      game.keyboardUsedRecently = true
      game.mouseMovedRecently = false
    return -1

  # Confirm selection with Enter or E
  if isKeyPressed(Enter) or isKeyPressed(E):
    let chosen = desktop.icons[desktop.selectedIcon]
    if chosen.iconType in {diModApp, diModMode}:
      desktop.launchModKey = chosen.modKey
    return chosen.iconType.int

  return -1

proc startLoadingAnimation*(desktop: OSDesktop, text: string) =
  ## Start a loading animation with the given text
  desktop.loadingActive = true
  desktop.loadingProgress = 0.0
  desktop.loadingText = text

proc drawCknLoadingOverlay(desktop: OSDesktop, screenWidth, screenHeight: int, th: UiTheme) =
  ## The CKN shell loads things the way CKN OS installed itself: a rounded,
  ## polite dialog with the logo and a rounded progress bar.
  drawRectangle(0, 0, screenWidth.int32, screenHeight.int32, withAlpha(CknShadow, 150))
  let pw = 500.0'f32
  let ph = 190.0'f32
  let px = ((screenWidth.float32 - pw) * 0.5'f32).floor
  let py = ((screenHeight.float32 - ph) * 0.5'f32).floor
  let track = mixColor(th.surface, th.raised, 0.75'f32)
  drawCknPanel(Rectangle(x: px, y: py, width: pw, height: ph), 12.0'f32, th.surface, track,
               shadowAlpha = 90.0'f32)
  drawCknLogo(px + 46.0'f32, py + 46.0'f32, 22.0'f32, arc = th.accent)
  drawText(t("os_loading"), px.int32 + 84, py.int32 + 30, 22, th.text)
  drawText(desktop.loadingText, px.int32 + 30, py.int32 + 84,
           bestDesktopLabelFontSize(desktop.loadingText, (pw - 60.0'f32).int32, 18), th.text)
  let frac = clamp(desktop.loadingProgress, 0.0'f32, 1.0'f32)
  let bar = Rectangle(x: px + 30.0'f32, y: py + 120.0'f32, width: pw - 60.0'f32, height: 12.0'f32)
  drawRectangleRounded(bar, 1.0'f32, 8, track)
  if frac > 0.0'f32:
    drawRectangleRounded(Rectangle(x: bar.x, y: bar.y, width: max(12.0'f32, bar.width * frac),
                                   height: bar.height), 1.0'f32, 8, th.accent)
  let pct = $int(frac * 100.0'f32) & "%"
  drawText(pct, (bar.x + bar.width).int32 - measureText(pct, 14), bar.y.int32 + 20, 14, th.muted)

proc drawLoadingOverlayLayer(desktop: OSDesktop, screenWidth, screenHeight: int)

proc drawLoadingOverlay*(desktop: OSDesktop, screenWidth, screenHeight: int) =
  ## Draw the loading animation overlay if active
  if not desktop.loadingActive:
    return
  themeLayer:
    let th = activeTheme()
    if th.shell == ssCkn:
      drawCknLoadingOverlay(desktop, screenWidth, screenHeight, th)
    else:
      drawLoadingOverlayLayer(desktop, screenWidth, screenHeight)

proc drawLoadingOverlayLayer(desktop: OSDesktop, screenWidth, screenHeight: int) =
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
               uiSurface(25, 30, 45))
  drawRectOutline(Rectangle(x: panelX.float32, y: panelY.float32,
                                width: panelWidth.float32, height: panelHeight.float32), 2,
                    uiLine(0, 180, 220))

  # Title bar
  drawRectangle(panelX.int32, panelY.int32, panelWidth.int32, 30,
               uiSurface(0, 50, 80))
  drawText(t("os_loading") & "...", (panelX + 10).int32, (panelY + 7).int32, 16,
          uiInk(0, 200, 255))

  # Loading text
  let textY = panelY + 60
  let textWidth = measureText(desktop.loadingText, 20)
  let textX = panelX + (panelWidth - textWidth) div 2
  drawText(desktop.loadingText, textX.int32, textY.int32, 20, uiInk(White))

  # Progress bar
  let barWidth = 400
  let barHeight = 30
  let barX = panelX + (panelWidth - barWidth) div 2
  let barY = panelY + 110

  # Progress bar background
  drawRectangle(barX.int32, barY.int32, barWidth.int32, barHeight.int32,
               uiSurface(20, 25, 35))
  drawRectOutline(Rectangle(x: barX.float32, y: barY.float32,
                                width: barWidth.float32, height: barHeight.float32), 2,
                    uiLine(60, 80, 100))

  # Progress fill with gradient effect
  let fillWidth = (barWidth.float32 * min(desktop.loadingProgress, 1.0)).int32
  if fillWidth > 0:
    drawRectangleGradientH(barX.int32, barY.int32, fillWidth, barHeight.int32,
                          uiSurface(0, 140, 200),
                          uiSurface(0, 200, 255))

  # Progress percentage
  let percentage = int(min(desktop.loadingProgress, 1.0) * 100.0)
  let percentText = $percentage & "%"
  let percentWidth = measureText(percentText, 18)
  let percentX = barX + (barWidth - percentWidth) div 2
  let percentY = barY + 6
  drawText(percentText, percentX.int32, percentY.int32, 18,
          uiInk(255, 255, 255))

  # Animated loading dots
  let dotCount = 3
  let dotsY = panelY + 160
  let dotSpacing = 15
  let dotsStartX = (screenWidth - (dotCount * dotSpacing)) div 2

  for i in 0..<dotCount:
    let dotX = dotsStartX + i * dotSpacing
    let dotPhase = desktop.time * 3.0 + i.float32 * 0.3
    let dotAlpha = ((sin(dotPhase) + 1.0) / 2.0 * 200.0 + 55.0).uint8
    drawDisc(Vector2(x: dotX.float32, y: dotsY.float32), 4,
              uiSurface(Color(r: 0, g: 200, b: 255, a: dotAlpha)))
