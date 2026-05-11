## OS-Style Task Manager (Pause Menu)
## Pause menu styled as system task manager with mouse support

import raylib, ../types, ../powerup_data, math, ../localization, ../render_context

const
  TASK_MANAGER_WIDTH = 700
  TASK_MANAGER_HEIGHT = 500
  TITLE_BAR_HEIGHT = 35
  TAB_HEIGHT = 35
  BUTTON_HEIGHT = 40
  BUTTON_SPACING = 15

proc isMouseOverRect*(mousePos: Vector2, x, y, width, height: int32): bool =
  ## Helper to check if mouse is over a rectangle
  result = mousePos.x >= x.float32 and mousePos.x <= (x + width).float32 and
           mousePos.y >= y.float32 and mousePos.y <= (y + height).float32

proc drawTaskManagerTab(x, y, width: int32, text: string, active: bool, hovered: bool) =
  ## Draw a single tab button
  let bgColor = if active:
    Color(r: 45, g: 55, b: 70, a: 255)
  elif hovered:
    Color(r: 35, g: 45, b: 60, a: 255)
  else:
    Color(r: 25, g: 35, b: 50, a: 255)

  drawRectangle(x, y, width, TAB_HEIGHT, bgColor)

  # Tab border
  let borderColor = if active:
    Color(r: 0, g: 200, b: 255, a: 255)
  else:
    Color(r: 60, g: 70, b: 85, a: 255)

  drawRectangleLines(Rectangle(x: x.float32, y: y.float32,
                                width: width.float32, height: TAB_HEIGHT.float32),
                    if active: 2 else: 1, borderColor)

  # Tab text
  let textWidth = measureText(text, 14)
  let textColor = if active:
    Color(r: 0, g: 200, b: 255, a: 255)
  else:
    Color(r: 150, g: 150, b: 150, a: 255)

  drawText(text, x + (width - textWidth) div 2, y + 10, 14, textColor)

proc drawProcessesTab(game: Game, x, y, width, height: int32) =
  ## Draw the Processes tab showing active power-ups
  var yOffset = y + 10

  drawText(t("os_running_processes") & ":", x + 10, yOffset, 16,
          Color(r: 0, g: 200, b: 255, a: 255))
  yOffset += 30

  if game.player.powerUps.len == 0:
    drawText(t("os_no_active_processes"), x + 20, yOffset, 14, Gray)
  else:
    # Header
    drawText(t("os_process_name"), x + 20, yOffset, 12, LightGray)
    drawText(t("os_version"), x + 300, yOffset, 12, LightGray)
    drawText(t("os_status"), x + 400, yOffset, 12, LightGray)
    yOffset += 20

    # Separator line
    drawLine(Vector2(x: (x + 10).float32, y: yOffset.float32),
            Vector2(x: (x + width - 10).float32, y: yOffset.float32),
            1, Color(r: 60, g: 70, b: 85, a: 255))
    yOffset += 10

    # List active power-ups
    for i, powerUp in game.player.powerUps:
      if yOffset > y + height - 30:
        break  # Don't overflow

      let processName = getPowerUpName(powerUp.powerType)
      let versionText = "v" & $powerUp.level & ".0"
      let statusText = "Running"

      # Alternate row background
      if i mod 2 == 0:
        drawRectangle(x + 10, yOffset - 5, width - 20, 25,
                     Color(r: 30, g: 35, b: 45, a: 100))

      # Process icon (colored square)
      let iconColor = if powerUp.rarity == prLegendary:
        Color(r: 255, g: 215, b: 0, a: 255)
      else:
        Color(r: 0, g: 200, b: 255, a: 255)

      drawRectangle(x + 20, yOffset - 2, 15, 15, iconColor)

      drawText(processName & ".exe", x + 45, yOffset, 12, White)
      drawText(versionText, x + 300, yOffset, 12, Color(r: 150, g: 150, b: 150, a: 255))
      drawText(statusText, x + 400, yOffset, 12, Color(r: 100, g: 255, b: 100, a: 255))

      yOffset += 30

proc drawPerformanceTab(game: Game, x, y, width, height: int32, time: float32) =
  ## Draw the Performance tab showing game statistics
  var yOffset = y + 10

  drawText(t("os_system_performance") & ":", x + 10, yOffset, 16,
          Color(r: 0, g: 200, b: 255, a: 255))
  yOffset += 30

  # Current session stats
  let stats = [
    ("Wave", $game.currentWave),
    ("Uptime", $(game.time.int div 60) & ":" &
               (if game.time.int mod 60 < 10: "0" else: "") & $(game.time.int mod 60)),
    ("Threats Eliminated", $game.player.kills),
    ("Resources Collected", $game.player.coins),
    ("System Integrity", $round(game.player.hp).int & "/" & $round(game.player.maxHp).int),
    ("Active Processes", $game.player.powerUps.len),
    ("Defensive Barriers", $game.player.walls)
  ]

  for stat in stats:
    let (label, value) = stat
    drawText(label & ":", x + 30, yOffset, 14, LightGray)
    drawText(value, x + 300, yOffset, 14, White)
    yOffset += 25

proc drawOSTaskManager*(game: Game, selectedTab: TaskManagerTab): tuple[resumeClicked, settingsClicked, exitClicked: bool, newTab: TaskManagerTab] =
  ## Draw the task manager (pause menu)
  ## Returns tuple indicating which button was clicked (if any) and which tab should be selected
  result.resumeClicked = false
  result.settingsClicked = false
  result.exitClicked = false
  result.newTab = selectedTab

  let screenWidth = game.screenWidth
  let screenHeight = game.screenHeight
  let mousePos = getVirtualMousePosition()
  let mouseSupported = game.mouseMovedRecently

  # Dark overlay
  drawRectangle(0, 0, screenWidth, screenHeight, Color(r: 0, g: 0, b: 0, a: 200))

  # Calculate window position (centered)
  let windowX = (screenWidth - TASK_MANAGER_WIDTH) div 2
  let windowY = (screenHeight - TASK_MANAGER_HEIGHT) div 2

  # Window shadow
  drawRectangle((windowX + 5).int32, (windowY + 5).int32,
               TASK_MANAGER_WIDTH, TASK_MANAGER_HEIGHT,
               Color(r: 0, g: 0, b: 0, a: 120))

  # Window background
  drawRectangle(windowX, windowY, TASK_MANAGER_WIDTH, TASK_MANAGER_HEIGHT,
               Color(r: 20, g: 25, b: 35, a: 255))

  # Window border
  drawRectangleLines(Rectangle(x: windowX.float32, y: windowY.float32,
                                width: TASK_MANAGER_WIDTH.float32, height: TASK_MANAGER_HEIGHT.float32),
                    3, Color(r: 0, g: 200, b: 255, a: 255))

  # Title bar
  drawRectangle(windowX, windowY, TASK_MANAGER_WIDTH, TITLE_BAR_HEIGHT,
               Color(r: 35, g: 45, b: 60, a: 255))

  drawText(t("os_system_manager"), windowX + 15, windowY + 8, 18,
          Color(r: 0, g: 200, b: 255, a: 255))

  # Tabs (only Processes and Performance)
  let tabY = windowY + TITLE_BAR_HEIGHT
  let tabWidth = TASK_MANAGER_WIDTH div 2

  # Check mouse hover and clicks for tabs
  let processesHovered = mouseSupported and isMouseOverRect(mousePos, windowX, tabY, tabWidth.int32, TAB_HEIGHT)
  let performanceHovered = mouseSupported and isMouseOverRect(mousePos, windowX + tabWidth.int32, tabY, tabWidth.int32, TAB_HEIGHT)

  # Handle tab clicks
  if mouseSupported and isMouseButtonPressed(Left):
    if processesHovered:
      result.newTab = tmtProcesses
    elif performanceHovered:
      result.newTab = tmtPerformance

  drawTaskManagerTab(windowX, tabY, tabWidth.int32, "Processes",
                    selectedTab == tmtProcesses, processesHovered)
  drawTaskManagerTab(windowX + tabWidth.int32, tabY, tabWidth.int32, "Performance",
                    selectedTab == tmtPerformance, performanceHovered)

  # Content area
  let contentY = tabY + TAB_HEIGHT + 10
  let contentHeight = TASK_MANAGER_HEIGHT - TITLE_BAR_HEIGHT - TAB_HEIGHT - 120

  case selectedTab
  of tmtProcesses:
    drawProcessesTab(game, windowX, contentY, TASK_MANAGER_WIDTH.int32, contentHeight.int32)
  of tmtPerformance:
    drawPerformanceTab(game, windowX, contentY, TASK_MANAGER_WIDTH.int32, contentHeight.int32, game.time)
  else:
    discard

  # Bottom buttons
  let buttonY = windowY + TASK_MANAGER_HEIGHT - 80
  let buttonsStartX = windowX + (TASK_MANAGER_WIDTH - 600) div 2

  # Check mouse hover for buttons
  let resumeHovered = mouseSupported and isMouseOverRect(mousePos, buttonsStartX, buttonY, 180, BUTTON_HEIGHT)
  let settingsX = buttonsStartX + 180 + BUTTON_SPACING
  let settingsHovered = mouseSupported and isMouseOverRect(mousePos, settingsX, buttonY, 180, BUTTON_HEIGHT)
  let exitX = settingsX + 180 + BUTTON_SPACING
  let exitHovered = mouseSupported and isMouseOverRect(mousePos, exitX, buttonY, 180, BUTTON_HEIGHT)

  # Handle button clicks
  if mouseSupported and isMouseButtonPressed(Left):
    if resumeHovered:
      result.resumeClicked = true
    elif settingsHovered:
      result.settingsClicked = true
    elif exitHovered:
      result.exitClicked = true

  # Resume button
  let resumeBgColor = if resumeHovered:
    Color(r: 0, g: 150, b: 0, a: 255)
  else:
    Color(r: 0, g: 120, b: 0, a: 255)

  drawRectangle(buttonsStartX, buttonY, 180, BUTTON_HEIGHT, resumeBgColor)
  drawRectangleLines(Rectangle(x: buttonsStartX.float32, y: buttonY.float32,
                                width: 180.0, height: BUTTON_HEIGHT.float32),
                    if resumeHovered: 3 else: 2,
                    if resumeHovered: Color(r: 0, g: 255, b: 100, a: 255) else: Color(r: 0, g: 255, b: 0, a: 255))
  let resumeText = "[SPACE] RESUME"
  let resumeWidth = measureText(resumeText, 14)
  drawText(resumeText, buttonsStartX + (180 - resumeWidth) div 2,
          buttonY + 12, 14, White)

  # Settings button
  let settingsBgColor = if settingsHovered:
    Color(r: 80, g: 90, b: 105, a: 255)
  else:
    Color(r: 60, g: 70, b: 85, a: 255)

  drawRectangle(settingsX, buttonY, 180, BUTTON_HEIGHT, settingsBgColor)
  drawRectangleLines(Rectangle(x: settingsX.float32, y: buttonY.float32,
                                width: 180.0, height: BUTTON_HEIGHT.float32),
                    if settingsHovered: 3 else: 2,
                    if settingsHovered: Color(r: 150, g: 170, b: 190, a: 255) else: Color(r: 120, g: 140, b: 160, a: 255))
  let settingsText = "[TAB] SETTINGS"
  let settingsWidth = measureText(settingsText, 14)
  drawText(settingsText, settingsX + (180 - settingsWidth) div 2,
          buttonY + 12, 14, White)

  # Exit button
  let exitBgColor = if exitHovered:
    Color(r: 150, g: 40, b: 40, a: 255)
  else:
    Color(r: 120, g: 30, b: 30, a: 255)

  drawRectangle(exitX, buttonY, 180, BUTTON_HEIGHT, exitBgColor)
  drawRectangleLines(Rectangle(x: exitX.float32, y: buttonY.float32,
                                width: 180.0, height: BUTTON_HEIGHT.float32),
                    if exitHovered: 3 else: 2,
                    if exitHovered: Color(r: 255, g: 100, b: 100, a: 255) else: Color(r: 255, g: 80, b: 80, a: 255))
  let exitText = "[Q] EXIT"
  let exitWidth = measureText(exitText, 14)
  drawText(exitText, exitX + (180 - exitWidth) div 2,
          buttonY + 12, 14, White)

  # Status message
  drawText(t("os_system_paused") & " - " & t("os_press_space_continue"),
          windowX + 20, windowY + TASK_MANAGER_HEIGHT - 30, 12, LightGray)
