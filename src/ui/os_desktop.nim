## OS-Themed Desktop Environment Module
## Main menu as an operating system desktop

import raylib, types, math, strutils, strformat, times

type
  DesktopIconType* = enum
    diPlay          # Launch game (Play.exe)
    diSurvival      # Survival mode (Survival.exe)
    diStatistics    # Statistics viewer (Stats.exe)
    diSettings      # Settings panel (Settings.exe)
    diHelp          # Help/Documentation (Help.txt)
    diQuit          # Shutdown (Shutdown.exe)
    diSandbox       # Sandbox mode (Sandbox.exe)
  
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

const
  ICON_SIZE = 64
  ICON_SPACING = 100
  TASKBAR_HEIGHT = 40
  DESKTOP_GRID_START_X = 80
  DESKTOP_GRID_START_Y = 80

proc newOSDesktop*(): OSDesktop =
  result = OSDesktop(
    icons: @[
      DesktopIcon(iconType: diPlay, x: DESKTOP_GRID_START_X, y: DESKTOP_GRID_START_Y, 
                  selected: true, name: "Play.exe",
                  iconColor: Color(r: 100, g: 200, b: 255, a: 255)),
      DesktopIcon(iconType: diSurvival, x: DESKTOP_GRID_START_X, y: DESKTOP_GRID_START_Y + ICON_SPACING, 
                  selected: false, name: "Survival.exe",
                  iconColor: Color(r: 255, g: 150, b: 100, a: 255)),
      DesktopIcon(iconType: diStatistics, x: DESKTOP_GRID_START_X, y: DESKTOP_GRID_START_Y + ICON_SPACING * 2, 
                  selected: false, name: "Stats.exe",
                  iconColor: Color(r: 255, g: 200, b: 50, a: 255)),
      DesktopIcon(iconType: diSettings, x: DESKTOP_GRID_START_X, y: DESKTOP_GRID_START_Y + ICON_SPACING * 3, 
                  selected: false, name: "Settings.exe",
                  iconColor: Color(r: 200, g: 100, b: 255, a: 255)),
      DesktopIcon(iconType: diHelp, x: DESKTOP_GRID_START_X, y: DESKTOP_GRID_START_Y + ICON_SPACING * 4, 
                  selected: false, name: "Help.txt",
                  iconColor: Color(r: 100, g: 255, b: 150, a: 255)),
      DesktopIcon(iconType: diQuit, x: DESKTOP_GRID_START_X, y: DESKTOP_GRID_START_Y + ICON_SPACING * 5, 
                  selected: false, name: "Shutdown.exe",
                  iconColor: Color(r: 255, g: 100, b: 100, a: 255)),
      DesktopIcon(iconType: diSandbox, x: DESKTOP_GRID_START_X + ICON_SPACING, y: DESKTOP_GRID_START_Y, 
                  selected: false, name: "Sandbox.exe",
                  iconColor: Color(r: 255, g: 165, b: 0, a: 255))
    ],
    selectedIcon: 0,
    time: 0,
    taskbarHeight: TASKBAR_HEIGHT,
    windows: @[],
    showCursor: true
  )

proc updateOSDesktop*(desktop: OSDesktop, dt: float32) =
  desktop.time += dt
  
  # Update all icon selections
  for i in 0..<desktop.icons.len:
    desktop.icons[i].selected = (i == desktop.selectedIcon)

proc drawDesktopIcon(icon: DesktopIcon, time: float32, selected: bool) =
  let pulse = if selected: sin(time * 4.0) * 0.15 + 1.0 else: 1.0
  let iconSize = (ICON_SIZE.float32 * pulse).int32
  let offsetX = if selected: (ICON_SIZE - iconSize) div 2 else: 0
  let offsetY = if selected: (ICON_SIZE - iconSize) div 2 else: 0
  
  # OS-style icon window with depth
  # Shadow/depth layer
  drawRectangle((icon.x + offsetX + 3).int32, (icon.y + offsetY + 3).int32, 
               iconSize, iconSize,
               Color(r: 0, g: 0, b: 0, a: 100))
  
  # Icon background (window-like with gradient effect)
  let bgGradTop = if selected: 
    Color(r: 45, g: 45, b: 60, a: 240)
  else:
    Color(r: 30, g: 30, b: 40, a: 220)
  let bgGradBottom = if selected:
    Color(r: 30, g: 30, b: 45, a: 240)
  else:
    Color(r: 20, g: 20, b: 30, a: 220)
  
  drawRectangleGradientV((icon.x + offsetX).int32, (icon.y + offsetY).int32,
                         iconSize, iconSize,
                         bgGradTop, bgGradBottom)
  
  # Icon border with glow if selected
  let borderColor = if selected: 
    Color(r: 0, g: 200, b: 255, a: 255)
  else:
    Color(r: 80, g: 80, b: 100, a: 255)
  
  drawRectangleLines(Rectangle(x: (icon.x + offsetX).float32, 
                                y: (icon.y + offsetY).float32,
                                width: iconSize.float32, 
                                height: iconSize.float32), 2, borderColor)
  
  # Add corner decorations (OS-style window corners)
  if selected:
    let cornerSize = 8.int32
    # Top-left corner
    drawLine(Vector2(x: (icon.x + offsetX).float32, y: (icon.y + offsetY).float32),
            Vector2(x: (icon.x + offsetX + cornerSize).float32, y: (icon.y + offsetY).float32),
            2, Color(r: 100, g: 220, b: 255, a: 255))
    drawLine(Vector2(x: (icon.x + offsetX).float32, y: (icon.y + offsetY).float32),
            Vector2(x: (icon.x + offsetX).float32, y: (icon.y + offsetY + cornerSize).float32),
            2, Color(r: 100, g: 220, b: 255, a: 255))
    # Top-right corner
    drawLine(Vector2(x: (icon.x + offsetX + iconSize).float32, y: (icon.y + offsetY).float32),
            Vector2(x: (icon.x + offsetX + iconSize - cornerSize).float32, y: (icon.y + offsetY).float32),
            2, Color(r: 100, g: 220, b: 255, a: 255))
    drawLine(Vector2(x: (icon.x + offsetX + iconSize).float32, y: (icon.y + offsetY).float32),
            Vector2(x: (icon.x + offsetX + iconSize).float32, y: (icon.y + offsetY + cornerSize).float32),
            2, Color(r: 100, g: 220, b: 255, a: 255))
  
  # Icon graphic based on type
  let centerX = icon.x + ICON_SIZE div 2
  let centerY = icon.y + ICON_SIZE div 2
  
  case icon.iconType
  of diPlay:
    # Play triangle
    let size = 20.float32
    drawTriangle(
      Vector2(x: centerX.float32 - size, y: centerY.float32 - size),
      Vector2(x: centerX.float32 - size, y: centerY.float32 + size),
      Vector2(x: centerX.float32 + size, y: centerY.float32),
      icon.iconColor
    )
  
  of diSurvival:
    # Survival clock/timer
    drawCircle(Vector2(x: centerX.float32, y: centerY.float32), 18, icon.iconColor)
    drawLine(Vector2(x: centerX.float32, y: centerY.float32),
            Vector2(x: centerX.float32, y: centerY.float32 - 15), 3, White)
    drawLine(Vector2(x: centerX.float32, y: centerY.float32),
            Vector2(x: centerX.float32 + 10, y: centerY.float32), 3, White)
  
  of diStatistics:
    # Bar chart
    drawRectangle((centerX - 15).int32, (centerY + 5).int32, 8, 15, icon.iconColor)
    drawRectangle((centerX - 3).int32, centerY.int32, 8, 20, icon.iconColor)
    drawRectangle((centerX + 9).int32, (centerY - 5).int32, 8, 25, icon.iconColor)
  
  of diSettings:
    # Gear
    let gearRadius = 18.float32
    for i in 0..<8:
      let angle = (i.float32 * PI / 4.0) + time
      let x1 = centerX.float32 + cos(angle) * gearRadius
      let y1 = centerY.float32 + sin(angle) * gearRadius
      drawCircle(Vector2(x: x1, y: y1), 4, icon.iconColor)
    drawCircle(Vector2(x: centerX.float32, y: centerY.float32), 10, icon.iconColor)
  
  of diHelp:
    # Question mark in document
    drawRectangle((centerX - 12).int32, (centerY - 18).int32, 24, 32, icon.iconColor)
    drawText("?", (centerX - 7).int32, (centerY - 12).int32, 28, White)
  
  of diQuit:
    # Power symbol
    drawCircle(Vector2(x: centerX.float32, y: centerY.float32), 18, icon.iconColor)
    drawRectangle((centerX - 2).int32, (centerY - 18).int32, 4, 15, Black)
    drawCircle(Vector2(x: centerX.float32, y: centerY.float32), 12, Black)
  
  of diSandbox:
    # Sandbox/testing icon - wrench and hammer crossed
    # Wrench
    drawRectangle((centerX - 15).int32, (centerY - 5).int32, 12, 3, icon.iconColor)
    drawCircle(Vector2(x: (centerX - 15).float32, y: centerY.float32), 5, icon.iconColor)
    # Hammer
    drawRectangle((centerX + 3).int32, (centerY - 15).int32, 3, 12, icon.iconColor)
    drawRectangle((centerX).int32, (centerY - 18).int32, 9, 6, icon.iconColor)
  
  # Icon label with shadow
  let labelY = icon.y + ICON_SIZE + 8
  drawText(icon.name, (icon.x + 2).int32, (labelY + 2).int32, 14, Black)
  drawText(icon.name, icon.x.int32, labelY.int32, 14, White)

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
  
  drawText("TopHat", (startBtnX + 35).int32, (startBtnY + 7).int32, 18, White)
  
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
  drawText("NET", (indicatorX + 16).int32, (clockY + 3).int32, 12, 
          Color(r: 150, g: 150, b: 150, a: 255))

proc drawOSDesktop*(desktop: OSDesktop, screenWidth, screenHeight: int) =
  # Desktop background - dark gradient with grid pattern
  drawRectangleGradientV(0, 0, screenWidth.int32, screenHeight.int32,
                        Color(r: 10, g: 15, b: 25, a: 255),
                        Color(r: 20, g: 25, b: 40, a: 255))
  
  # Grid overlay for OS feel (subtle)
  let gridSpacing = 40
  for x in countup(0, screenWidth, gridSpacing):
    drawLine(Vector2(x: x.float32, y: 0), 
            Vector2(x: x.float32, y: screenHeight.float32), 1,
            Color(r: 30, g: 35, b: 50, a: 60))
  for y in countup(0, screenHeight, gridSpacing):
    drawLine(Vector2(x: 0, y: y.float32), 
            Vector2(x: screenWidth.float32, y: y.float32), 1,
            Color(r: 30, g: 35, b: 50, a: 60))
  
  # Animated circuit-like lines in background
  let lineCount = 10
  for i in 0..<lineCount:
    let offset = i.float32 * 40.0
    let progress = (desktop.time * 30.0 + offset) mod screenWidth.float32
    let y = (80 + i * 60) mod screenHeight
    
    # Horizontal line
    drawLine(Vector2(x: 0, y: y.float32),
            Vector2(x: progress, y: y.float32), 1,
            Color(r: 0, g: 100, b: 150, a: 30))
    
    # Vertical connection
    if i mod 3 == 0 and progress > 100:
      let vHeight = 40.0 + sin(desktop.time * 2.0 + offset) * 20.0
      drawLine(Vector2(x: progress, y: y.float32),
              Vector2(x: progress, y: y.float32 + vHeight), 1,
              Color(r: 0, g: 150, b: 200, a: 40))
  
  # Desktop icons
  for icon in desktop.icons:
    drawDesktopIcon(icon, desktop.time, icon.selected)
  
  # Taskbar
  drawTaskbar(screenWidth, screenHeight, desktop.time)
  
  # System info panel in top-right corner (like a widget)
  let panelX = screenWidth - 240
  let panelY = 10
  let panelW = 230
  let panelH = 100
  
  # Panel background with transparency
  drawRectangle(panelX.int32, panelY.int32, panelW.int32, panelH.int32,
               Color(r: 15, g: 20, b: 30, a: 180))
  drawRectangleLines(Rectangle(x: panelX.float32, y: panelY.float32,
                                width: panelW.float32, height: panelH.float32), 1,
                    Color(r: 0, g: 180, b: 180, a: 200))
  
  # Panel title bar
  drawRectangle(panelX.int32, panelY.int32, panelW.int32, 20,
               Color(r: 0, g: 40, b: 60, a: 220))
  drawText("System Monitor", (panelX + 8).int32, (panelY + 3).int32, 14,
          Color(r: 0, g: 200, b: 200, a: 255))
  
  # System stats (simulated)
  let uptime = int(desktop.time)
  let hours = uptime div 3600
  let minutes = (uptime mod 3600) div 60
  let seconds = uptime mod 60
  
  var infoY = panelY + 28
  drawText("CPU: Idle", (panelX + 8).int32, infoY.int32, 12,
          Color(r: 100, g: 255, b: 100, a: 255))
  infoY += 18
  drawText("Memory: 2.4 / 16 GB", (panelX + 8).int32, infoY.int32, 12,
          Color(r: 100, g: 200, b: 255, a: 255))
  infoY += 18
  drawText(&"Uptime: {hours:02d}:{minutes:02d}:{seconds:02d}", 
          (panelX + 8).int32, infoY.int32, 12,
          Color(r: 200, g: 200, b: 100, a: 255))
  infoY += 18
  drawText("Network: Connected", (panelX + 8).int32, infoY.int32, 12,
          Color(r: 100, g: 255, b: 150, a: 255))
  
  # Bottom desktop info (version and edition)
  drawText("TopHat-Shooter OS v4.1", 10, (screenHeight - 75).int32, 14,
          Color(r: 100, g: 100, b: 120, a: 200))
  drawText("[Elemental Edition]", 10, (screenHeight - 58).int32, 12,
          Color(r: 150, g: 150, b: 170, a: 180))

proc handleDesktopInput*(desktop: OSDesktop, game: Game): int =
  ## Returns selected menu option: 0=Play, 1=Survival, 2=Stats, 3=Settings, 4=Help, 5=Quit, 6=Sandbox
  ## Returns -1 if no action
  ## Note: Window occlusion should be handled by the calling code
  
  # Get mouse position
  let mousePos = getMousePosition()
  
  # Mouse hover detection - update selected icon based on hover
  var hoveredIcon = -1
  for i in 0..<desktop.icons.len:
    let icon = desktop.icons[i]
    # Check if mouse is over icon (including label area)
    let iconBounds = Rectangle(
      x: icon.x.float32 - 10,  # Add some padding
      y: icon.y.float32 - 10,
      width: (ICON_SIZE + 20).float32,
      height: (ICON_SIZE + 40).float32  # Extra height for label
    )
    
    if checkCollisionPointRec(mousePos, iconBounds):
      hoveredIcon = i
      desktop.selectedIcon = i
      break
  
  # Mouse click detection - select icon on click
  if isMouseButtonPressed(Left) and hoveredIcon >= 0:
    return hoveredIcon
  
  # Keyboard navigation (WASD or arrow keys)
  if isKeyPressed(Down) or isKeyPressed(S):
    desktop.selectedIcon = (desktop.selectedIcon + 1) mod desktop.icons.len
    return -1
  
  if isKeyPressed(Up) or isKeyPressed(W):
    desktop.selectedIcon = (desktop.selectedIcon - 1 + desktop.icons.len) mod desktop.icons.len
    return -1
  
  # Selection with Enter or E (keyboard only)
  if isKeyPressed(Enter) or isKeyPressed(E):
    return desktop.selectedIcon
  
  return -1
