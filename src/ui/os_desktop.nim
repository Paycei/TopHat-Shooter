## OS-Themed Desktop Environment Module
## Main menu as an operating system desktop

import raylib, ../types, ../localization, math, strutils, strformat, times, ../render_context, background_fx

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
  of diPlay: t(tkMenuPlay) & ".exe"
  of diSurvival: t(tkMenuSurvival) & ".exe"
  of diStatistics: t(tkMenuStats) & ".exe"
  of diSettings: t(tkMenuSettings) & ".exe"
  of diHelp: t(tkMenuHelp) & ".txt"
  of diQuit: t(tkMenuQuit) & ".exe"
  of diSandbox: t(tkMenuSandbox) & ".exe"
  of diShop: "Shop.exe"
  of diPvP: "PvP.exe"
  of diRoguelite: "Roguelite.exe"
  of diAdvancements: "Advncmnts.exe"

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
      DesktopIcon(iconType: diQuit, x: DESKTOP_GRID_START_X + ICON_SPACING, y: DESKTOP_GRID_START_Y + ICON_SPACING * 4,
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
    loadingText: ""
  )

proc updateOSDesktop*(desktop: OSDesktop, dt: float32) =
  desktop.time += dt
  
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
  
  of diShop:
    # Shop icon - shopping bag with color swatches
    # Draw shopping bag body
    let bagWidth = 24
    let bagHeight = 28
    let bagTop = centerY - 14
    
    # Bag body (trapezoid shape - wider at bottom)
    drawRectangle((centerX - bagWidth div 2).int32, bagTop.int32, bagWidth.int32, bagHeight.int32, icon.iconColor)
    
    # Bag handles
    let handleWidth = 14
    let handleTop = bagTop - 6
    drawLine(Vector2(x: (centerX - handleWidth div 2).float32, y: handleTop.float32),
            Vector2(x: (centerX - handleWidth div 2).float32, y: bagTop.float32), 3, icon.iconColor)
    drawLine(Vector2(x: (centerX + handleWidth div 2).float32, y: handleTop.float32),
            Vector2(x: (centerX + handleWidth div 2).float32, y: bagTop.float32), 3, icon.iconColor)
    drawLine(Vector2(x: (centerX - handleWidth div 2).float32, y: handleTop.float32),
            Vector2(x: (centerX + handleWidth div 2).float32, y: handleTop.float32), 3, icon.iconColor)
    
    # Color swatches on bag (showing customization options)
    let swatchSize = 5.float32
    let swatchY = (centerY + 2).float32
    let colors = [
      Color(r: 255, g: 100, b: 180, a: 255),  # Pink (player skin)
      Color(r: 0, g: 255, b: 100, a: 255),    # Green (player skin)
      Color(r: 0, g: 200, b: 255, a: 255)     # Cyan (bullet skin)
    ]
    for i in 0..<3:
      let swatchX = (centerX - 8 + i * 8).float32
      drawCircle(Vector2(x: swatchX, y: swatchY), swatchSize, colors[i])
  
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
    # Sandbox/testing icon - laboratory flask/beaker
    let flaskColor = icon.iconColor
    let liquidColor = Color(r: 0, g: 200, b: 255, a: 200)
    
    # Flask body (trapezoid shape)
    let baseWidth = 20
    let topWidth = 12
    let flaskHeight = 24
    let flaskBottom = centerY + 12
    let flaskTop = flaskBottom - flaskHeight
    
    # Draw flask outline (wider at bottom, narrower at top)
    # Bottom rectangle
    drawRectangle((centerX - baseWidth div 2).int32, (flaskBottom - 16).int32,
                 baseWidth.int32, 16.int32, flaskColor)
    # Neck
    drawRectangle((centerX - topWidth div 2).int32, (flaskTop).int32,
                 topWidth.int32, 8.int32, flaskColor)
    
    # Flask sides (trapezoid effect)
    drawTriangle(
      Vector2(x: (centerX - topWidth div 2).float32, y: (flaskTop + 8).float32),
      Vector2(x: (centerX - baseWidth div 2).float32, y: (flaskBottom - 16).float32),
      Vector2(x: (centerX - topWidth div 2).float32, y: (flaskBottom - 16).float32),
      flaskColor
    )
    drawTriangle(
      Vector2(x: (centerX + topWidth div 2).float32, y: (flaskTop + 8).float32),
      Vector2(x: (centerX + baseWidth div 2).float32, y: (flaskBottom - 16).float32),
      Vector2(x: (centerX + topWidth div 2).float32, y: (flaskBottom - 16).float32),
      flaskColor
    )
    
    # Liquid inside (partial fill)
    let liquidHeight = 10
    drawRectangle((centerX - baseWidth div 2 + 2).int32, (flaskBottom - liquidHeight).int32,
                 (baseWidth - 4).int32, liquidHeight.int32, liquidColor)
    
    # Bubbles in liquid
    drawCircle(Vector2(x: (centerX - 4).float32, y: (flaskBottom - 5).float32), 2, White)
    drawCircle(Vector2(x: (centerX + 3).float32, y: (flaskBottom - 8).float32), 1.5, White)
  
  of diPvP:
    # PvP icon - two crossed swords
    let swordColor = icon.iconColor
    let swordLength = 20.float32
    let swordWidth = 3.float32
    
    # Left sword (diagonal)
    let angle1 = -PI / 4.0  # -45 degrees
    let x1Start = centerX.float32 + cos(angle1 + PI) * swordLength
    let y1Start = centerY.float32 + sin(angle1 + PI) * swordLength
    let x1End = centerX.float32 + cos(angle1) * swordLength
    let y1End = centerY.float32 + sin(angle1) * swordLength
    drawLine(Vector2(x: x1Start, y: y1Start), Vector2(x: x1End, y: y1End),
            swordWidth, swordColor)
    
    # Right sword (diagonal opposite)
    let angle2 = PI / 4.0  # 45 degrees
    let x2Start = centerX.float32 + cos(angle2 + PI) * swordLength
    let y2Start = centerY.float32 + sin(angle2 + PI) * swordLength
    let x2End = centerX.float32 + cos(angle2) * swordLength
    let y2End = centerY.float32 + sin(angle2) * swordLength
    drawLine(Vector2(x: x2Start, y: y2Start), Vector2(x: x2End, y: y2End),
            swordWidth, swordColor)
    
    # Central clash effect
    drawCircle(Vector2(x: centerX.float32, y: centerY.float32), 6,
              Color(r: 255, g: 255, b: 255, a: 200))
    drawCircle(Vector2(x: centerX.float32, y: centerY.float32), 4, swordColor)

  of diRoguelite:
    # Roguelite icon - branching sector nodes
    let nodeColor = icon.iconColor
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
    # Advancements icon - progress ledger with tier nodes
    let ledgerX = centerX - 16
    let ledgerY = centerY - 18
    drawRectangle(ledgerX.int32, ledgerY.int32, 32, 36, Color(r: 18, g: 28, b: 42, a: 255))
    drawRectangleLines(Rectangle(x: ledgerX.float32, y: ledgerY.float32,
                                 width: 32.0, height: 36.0), 2, icon.iconColor)
    for i in 0..<3:
      let rowY = ledgerY + 8 + i * 9
      drawCircle(Vector2(x: (ledgerX + 7).float32, y: rowY.float32), 3,
                 if i == 0: Gold elif i == 1: icon.iconColor else: Color(r: 90, g: 255, b: 150, a: 255))
      drawRectangle((ledgerX + 13).int32, (rowY - 2).int32, (12 + i * 3).int32, 3,
                    Color(r: 170, g: 210, b: 230, a: 220))
    drawLine(Vector2(x: (ledgerX + 7).float32, y: (ledgerY + 8).float32),
             Vector2(x: (ledgerX + 7).float32, y: (ledgerY + 26).float32),
             1, Color(r: 120, g: 220, b: 255, a: 180))
  
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
  drawText("NET", (indicatorX + 16).int32, (clockY + 3).int32, 12,
          Color(r: 150, g: 150, b: 150, a: 255))

proc drawOSDesktop*(desktop: OSDesktop, screenWidth, screenHeight: int) =
  drawSharedBackdrop(screenWidth.int32, screenHeight.int32, desktop.time * 0.75,
                     Color(r: 8, g: 12, b: 24, a: 255),
                     Color(r: 18, g: 24, b: 38, a: 255),
                     Color(r: 32, g: 40, b: 62, a: 42),
                     Color(r: 72, g: 108, b: 160, a: 78),
                     Color(r: 0, g: 160, b: 220, a: 54),
                     0.85, 0.9)
  
  # Animated circuit-like lines in background
  let lineCount = 10
  for i in 0..<lineCount:
    let offset = i.float32 * 52.0
    let rawProgress = desktop.time * (38.0 + i.float32 * 1.5) + offset
    let progress = rawProgress - floor(rawProgress / screenWidth.float32).float32 * screenWidth.float32
    let y = 88.0 + i.float32 * 56.0 + sin(desktop.time * 0.8 + i.float32 * 0.6) * 18.0
    let lineColor = Color(r: 0, g: uint8(96 + i * 8), b: uint8(150 + (i mod 3) * 24), a: 38)
    
    # Horizontal line
    drawLine(Vector2(x: 0, y: y),
            Vector2(x: progress, y: y), 1, lineColor)
    
    # Vertical connection
    if i mod 2 == 0 and progress > 110.0:
      let vHeight = 36.0 + sin(desktop.time * 2.2 + offset) * 16.0
      drawLine(Vector2(x: progress, y: y),
              Vector2(x: progress, y: y + vHeight), 1,
              Color(r: 0, g: 175, b: 220, a: 50))
      drawCircle(Vector2(x: progress, y: y), 2.5, Color(r: 90, g: 220, b: 255, a: 110))
  
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
  drawText(t(tkOSSystemMonitor), (panelX + 8).int32, (panelY + 3).int32, 14,
          Color(r: 0, g: 200, b: 200, a: 255))
  
  # System stats (simulated)
  let uptime = int(desktop.time)
  let hours = uptime div 3600
  let minutes = (uptime mod 3600) div 60
  let seconds = uptime mod 60
  
  var infoY = panelY + 28
  drawText(t(tkOSCPUIdle), (panelX + 8).int32, infoY.int32, 12,
          Color(r: 100, g: 255, b: 100, a: 255))
  infoY += 18
  drawText(t(tkOSMemory), (panelX + 8).int32, infoY.int32, 12,
          Color(r: 100, g: 200, b: 255, a: 255))
  infoY += 18
  drawText(&"Uptime: {hours:02d}:{minutes:02d}:{seconds:02d}",
          (panelX + 8).int32, infoY.int32, 12,
          Color(r: 200, g: 200, b: 100, a: 255))
  infoY += 18
  drawText(t(tkOSNetwork), (panelX + 8).int32, infoY.int32, 12,
          Color(r: 100, g: 255, b: 150, a: 255))
  
  # Bottom desktop info (version and edition)
  drawText(t(tkOSTopHatOS), 10, (screenHeight - 75).int32, 14,
          Color(r: 100, g: 100, b: 120, a: 200))
  drawText(t(tkOSEdition), 10, (screenHeight - 58).int32, 12,
          Color(r: 150, g: 150, b: 170, a: 180))

proc handleDesktopInput*(desktop: OSDesktop, game: Game): int =
  ## Returns selected menu option: 0=Play, 1=Survival, 2=Stats, 3=Settings, 4=Shop, 5=Help, 6=Quit, 7=Sandbox, 9=Roguelite, 10=Advancements
  ## Returns -1 if no action
  ## Note: Window occlusion should be handled by the calling code
  
  # Get mouse position
  let mousePos = getVirtualMousePosition()
  
  # Mouse hover detection - update selected icon based on hover
  var hoveredIcon = -1
  for i in 0..<desktop.icons.len:
    let icon = desktop.icons[i]
    # Check if mouse is over icon (including label area)
    let iconBounds = Rectangle(
      x: icon.x.float32 - 10,  # Add some padding
      y: icon.y.float32 - 10,
      width: (ICON_SIZE + 20).float32,
      height: (ICON_SIZE + 58).float32  # Extra height for multiline label
    )
    
    if checkCollisionPointRec(mousePos, iconBounds):
      hoveredIcon = i
      desktop.selectedIcon = i
      break
  
  # Mouse click detection - select icon on click
  if isMouseButtonPressed(Left) and hoveredIcon >= 0:
    return desktop.icons[hoveredIcon].iconType.int  # Return iconType, not array index
  
  # Keyboard navigation (WASD or arrow keys)
  if isKeyPressed(Down) or isKeyPressed(S):
    desktop.selectedIcon = (desktop.selectedIcon + 1) mod desktop.icons.len
    return -1
  
  if isKeyPressed(Up) or isKeyPressed(W):
    desktop.selectedIcon = (desktop.selectedIcon - 1 + desktop.icons.len) mod desktop.icons.len
    return -1
  
  # Selection with Enter or E (keyboard only)
  if isKeyPressed(Enter) or isKeyPressed(E):
    return desktop.icons[desktop.selectedIcon].iconType.int  # Return iconType, not array index
  
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
