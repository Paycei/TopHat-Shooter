## OS-Style Task Manager (Pause Menu)
## Pause menu styled as system task manager with mouse support

import raylib, math, strutils
import ../types, ../powerup_data, ../localization, ../render_context, ../survival, ../patches, ../utils
import ui_helpers, icon_drawing

const
  TASK_MANAGER_WIDTH = 700
  TASK_MANAGER_HEIGHT = 500

const
  TaskManagerPanelW* = TASK_MANAGER_WIDTH
  TaskManagerPanelH* = TASK_MANAGER_HEIGHT
    ## Panel size, exported so callers can cap the UI scale against it.
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

proc taskManagerTabs*(game: Game): seq[TaskManagerTab] =
  ## The tabs this run shows, left to right. Patches only exist in a roguelite
  ## run, so only that mode gets their tab.
  if game.mode == gmRoguelite and not game.rogueliteRun.isNil:
    @[tmtProcesses, tmtPatches, tmtPerformance]
  else:
    @[tmtProcesses, tmtPerformance]

proc stepTaskManagerTab*(game: Game, current: TaskManagerTab, step: int): TaskManagerTab =
  ## The tab `step` places from `current`, wrapping (Left/Right in the menu).
  let tabs = taskManagerTabs(game)
  let at = max(0, tabs.find(current))
  tabs[(at + step + tabs.len * 2) mod tabs.len]

proc taskManagerTabLabel(tab: TaskManagerTab): string =
  case tab
  of tmtProcesses: t("os_tab_processes")
  of tmtPatches: t("os_tab_patches")
  of tmtPerformance: t("os_tab_performance")
  of tmtSettings: ""

var
  patchTabSelection = 0
    ## Which installed patch the Patches tab's detail pane is showing.
  patchTabLastMouse = Vector2(x: -1, y: -1)
    ## Hover only moves the selection when the pointer actually moves, so a
    ## cursor resting over the list can't undo every UP/DOWN press.

proc drawPatchDetail(game: Game, patch: RogueliteRelicType, x, y, w, h: int32) =
  ## Everything about one patch: glyph, name, KB number, category, what it
  ## does, and (for the charge patches) whether its charge is up.
  let accent = patchAccent(patch)
  drawRectangle(x, y, w, h, Color(r: 28, g: 34, b: 46, a: 255))
  drawRectangle(x, y, 3, h, accent)
  drawRectangleLines(Rectangle(x: x.float32, y: y.float32, width: w.float32, height: h.float32),
                     1, withAlpha(accent, 110))

  const iconSize = 44'i32
  let ix = x + 16
  let iy = y + 16
  drawRectangle(ix - 4, iy - 4, iconSize + 8, iconSize + 8, withAlpha(accent, 30))
  drawPatchIcon(ix, iy, iconSize, patch, accent)

  let tx = ix + iconSize + 14
  let tw = x + w - 14 - tx
  let name = patchName(patch)
  drawText(fitWithEllipsis(name, tw, 18), tx, iy + 2, 18, White)
  let kb = patchKbLabel(patch)
  drawText(kb, tx, iy + 28, 12, Color(r: 140, g: 150, b: 165, a: 255))
  let category = patchCategoryName(patchCategory(patch)).toUpperAscii
  drawText(category, tx + measureText(kb, 12) + 12, iy + 28, 12, accent)

  var ly = iy + iconSize + 18
  drawLine(Vector2(x: (x + 14).float32, y: (ly - 8).float32),
           Vector2(x: (x + w - 14).float32, y: (ly - 8).float32), 1, Color(r: 60, g: 70, b: 85, a: 255))
  const descSize = 14'i32
  for line in wrapTextLines(patchDescription(patch), w - 28, descSize):
    drawText(line, x + 14, ly, descSize, Color(r: 215, g: 225, b: 235, a: 255))
    ly += descSize + 6

  let status = patchStatus(game, patch)
  let label = t("os_status") & ": "
  let sy = y + h - 26
  drawText(label, x + 14, sy, 12, LightGray)
  drawText(patchStatusLabel(status), x + 14 + measureText(label, 12), sy, 12, patchStatusColor(status))

proc drawPatchesTab(game: Game, x, y, width, height: int32, mouseSupported: bool) =
  ## The run's patches in install order (left), and the one under the cursor
  ## or the UP/DOWN selection explained in full (right). The HUD only has room
  ## for names; this is where a player learns what each patch does.
  let relics = if game.rogueliteRun.isNil: @[] else: game.rogueliteRun.relics
  var yOffset = y + 10
  drawText(t("os_installed_patches") & " (" & $relics.len & "):", x + 10, yOffset, 16,
           Color(r: 0, g: 200, b: 255, a: 255))
  yOffset += 30

  if relics.len == 0:
    for line in wrapTextLines(t("os_no_patches"), width - 40, 14):
      drawText(line, x + 20, yOffset, 14, Gray)
      yOffset += 20
    return

  if isKeyPressed(KeyboardKey.Up) or isKeyPressed(KeyboardKey.W) or gamepadNavPressed(gnUp):
    dec patchTabSelection
  if isKeyPressed(KeyboardKey.Down) or isKeyPressed(KeyboardKey.S) or gamepadNavPressed(gnDown):
    inc patchTabSelection

  const rowH = 18'i32
  const listW = 300'i32
  let listX = x + 10
  let shown = min(relics.len, int((y + height - yOffset) div rowH))
  patchTabSelection = clamp(patchTabSelection, 0, max(0, shown - 1))
  let mouse = getVirtualMousePosition()
  let mouseMoved = mouse.x != patchTabLastMouse.x or mouse.y != patchTabLastMouse.y
  patchTabLastMouse = mouse
  if mouseSupported and (mouseMoved or isPointerPressed()):
    for i in 0..<shown:
      if isMouseOverRect(mouse, listX, yOffset + i.int32 * rowH, listW, rowH):
        patchTabSelection = i

  let kbW = measureText("KB-0000", 12)
  for i in 0..<shown:
    let patch = relics[i].relicType
    let ry = yOffset + i.int32 * rowH
    let status = patchStatus(game, patch)
    let spent = status in {psUsed, psStalled}
    if i == patchTabSelection:
      drawRectangle(listX, ry, listW, rowH, Color(r: 0, g: 200, b: 255, a: 45))
      drawRectangleLines(Rectangle(x: listX.float32, y: ry.float32, width: listW.float32,
                                   height: rowH.float32), 1, Color(r: 0, g: 200, b: 255, a: 170))
    elif i mod 2 == 0:
      drawRectangle(listX, ry, listW, rowH, Color(r: 30, g: 35, b: 45, a: 100))
    let accent = patchAccent(patch)
    drawPatchIcon(listX + 4, ry + 1, rowH - 2, patch, if spent: withAlpha(accent, 100) else: accent)
    drawText(patchKbLabel(patch), listX + 26, ry + 3, 12, Color(r: 120, g: 135, b: 150, a: 255))
    let statusText = patchStatusLabel(status)
    let statusW = measureText(statusText, 12)
    drawText(statusText, listX + listW - 6 - statusW, ry + 3, 12, patchStatusColor(status))
    let nameX = listX + 26 + kbW + 8
    drawText(fitWithEllipsis(patchName(patch), listX + listW - 6 - statusW - 8 - nameX, 12),
             nameX, ry + 3, 12, if spent: Gray else: White)

  let paneX = listX + listW + 10
  let paneW = x + width - 10 - paneX
  let paneH = y + height - yOffset - 18
  drawPatchDetail(game, relics[patchTabSelection].relicType, paneX, yOffset, paneW, paneH)
  drawText(t("os_patches_hint"), paneX, yOffset + paneH + 5, 10, Color(r: 120, g: 135, b: 150, a: 255))

proc drawPerformanceTab(game: Game, x, y, width, height: int32, time: float32) =
  ## Draw the Performance tab showing game statistics
  var yOffset = y + 10

  drawText(t("os_system_performance") & ":", x + 10, yOffset, 16,
          Color(r: 0, g: 200, b: 255, a: 255))
  yOffset += 30

  # Current session stats
  let stats = [
    if game.mode == gmTimeSurvival: ("Phase", survivalPhaseReachedLabel(game))
    else: ("Wave", $game.currentWave),
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

proc drawQuitConfirmDialog*(game: Game): tuple[confirmed, cancelled: bool] =
  ## Draw an OS-style "Are you sure?" confirmation dialog over the task manager.
  result.confirmed = false
  result.cancelled  = false

  let sw = getVirtualScreenWidth()
  let sh = getVirtualScreenHeight()
  let mousePos = getVirtualMousePosition()

  const
    DW: int32 = 440
    DH: int32 = 200
    BTN_W: int32 = 160
    BTN_H: int32 = 40

  let dx: int32 = (sw - DW) div 2
  let dy: int32 = (sh - DH) div 2

  # Extra dark backdrop on top of the existing overlay
  drawRectangle(0'i32, 0'i32, sw, sh, Color(r: 0, g: 0, b: 0, a: 120))

  # Dialog shadow
  drawRectangle(dx + 6, dy + 6, DW, DH, Color(r: 0, g: 0, b: 0, a: 140))
  # Dialog background
  drawRectangle(dx, dy, DW, DH, Color(r: 20, g: 25, b: 35, a: 255))
  drawRectangleLines(Rectangle(x: dx.float32, y: dy.float32,
                               width: DW.float32, height: DH.float32),
                     3, Color(r: 255, g: 80, b: 80, a: 255))

  # Title bar
  let tbH: int32 = 35
  drawRectangle(dx, dy, DW, tbH, Color(r: 120, g: 30, b: 30, a: 255))
  let titleStr = "CONFIRM EXIT"
  let titleW = measureText(titleStr, 16)
  drawText(titleStr, dx + (DW - titleW) div 2, dy + 8, 16,
           Color(r: 255, g: 200, b: 200, a: 255))

  # Body text
  let bodyStr = "Return to main menu?"
  let bodyW = measureText(bodyStr, 18)
  drawText(bodyStr, dx + (DW - bodyW) div 2, dy + tbH + 28, 18, White)

  let subStr = "Your progress will be saved."
  let subW = measureText(subStr, 13)
  drawText(subStr, dx + (DW - subW) div 2, dy + tbH + 58, 13,
           Color(r: 200, g: 150, b: 150, a: 255))

  # Buttons row
  let btnY: int32  = dy + DH - BTN_H - 22
  let noX: int32   = dx + (DW div 2) - BTN_W - 12
  let yesX: int32  = dx + (DW div 2) + 12

  let noHov  = isMouseOverRect(mousePos, noX,  btnY, BTN_W, BTN_H)
  let yesHov = isMouseOverRect(mousePos, yesX, btnY, BTN_W, BTN_H)
  # Mouse confirm is gated by pauseMenuExitCooldown (2 s anti-accident window).
  # Keyboard confirm is gated by pauseMenuExitCooldown too, PLUS the tiny
  # frame-guard that prevents Q-open and Q-confirm firing in the same poll cycle.
  let mouseReady = game.pauseMenuExitCooldown <= 0.0
  let keyReady   = game.pauseMenuExitCooldown <= 0.0 and game.confirmQuitFrameGuard <= 0.0

  # Cancel button (green: safe)
  let noBg = if noHov: Color(r: 0, g: 150, b: 0, a: 255) else: Color(r: 0, g: 110, b: 0, a: 255)
  drawRectangle(noX, btnY, BTN_W, BTN_H, noBg)
  drawRectangleLines(Rectangle(x: noX.float32, y: btnY.float32,
                               width: BTN_W.float32, height: BTN_H.float32),
                     if noHov: 3 else: 2,
                     if noHov: Color(r: 0, g: 255, b: 100, a: 255) else: Color(r: 0, g: 200, b: 60, a: 255))
  let noText = "[ESC] CANCEL"
  let noTW = measureText(noText, 14)
  drawText(noText, noX + (BTN_W - noTW) div 2, btnY + 12, 14, White)

  # Confirm button (red: destructive) greyed while mouse cooldown is active
  let yesBg = if not mouseReady:
    Color(r: 90, g: 90, b: 90, a: 255)
  elif yesHov:
    Color(r: 160, g: 40, b: 40, a: 255)
  else:
    Color(r: 120, g: 30, b: 30, a: 255)

  drawRectangle(yesX, btnY, BTN_W, BTN_H, yesBg)
  drawRectangleLines(Rectangle(x: yesX.float32, y: btnY.float32,
                               width: BTN_W.float32, height: BTN_H.float32),
                     if (yesHov and mouseReady): 3 else: 2,
                     if not mouseReady: Color(r: 140, g: 140, b: 140, a: 255)
                     elif yesHov: Color(r: 255, g: 100, b: 100, a: 255) else: Color(r: 200, g: 60, b: 60, a: 255))

  # Replace quit text with remaining seconds while mouse-cooldown is active
  let yesText = if mouseReady:
    "[Q] EXIT"
  else:
    $(int(ceil(game.pauseMenuExitCooldown)))
  let yesTW = measureText(yesText, 14)
  drawText(yesText, yesX + (BTN_W - yesTW) div 2, btnY + 12, 14, White)

  # Input keyboard uses keyReady (frame-guard only); mouse uses mouseReady (2 s cooldown).
  if isPointerPressed():
    if noHov:
      result.cancelled = true
    elif yesHov and mouseReady:
      result.confirmed = true
  if isKeyPressed(Escape): result.cancelled = true
  if isKeyPressed(Q)     and keyReady: result.confirmed = true
  if isKeyPressed(Enter) and keyReady: result.confirmed = true

proc drawOSTaskManager*(game: Game, selectedTab: TaskManagerTab): tuple[resumeClicked, settingsClicked, exitClicked: bool, newTab: TaskManagerTab] =
  ## Draw the task manager (pause menu)
  ## Returns tuple indicating which button was clicked (if any) and which tab should be selected
  result.resumeClicked = false
  result.settingsClicked = false
  result.exitClicked = false
  result.newTab = selectedTab

  let screenWidth = getVirtualScreenWidth()
  let screenHeight = getVirtualScreenHeight()
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

  # Tabs: Processes and Performance, plus Patches in a roguelite run.
  let tabY = windowY + TITLE_BAR_HEIGHT
  let tabs = taskManagerTabs(game)
  # A tab this run doesn't have (a stale selection) falls back to Processes.
  let shownTab = if selectedTab in tabs: selectedTab else: tmtProcesses
  let tabWidth = (TASK_MANAGER_WIDTH div tabs.len).int32
  for i, tab in tabs:
    let tx = windowX + i.int32 * tabWidth
    # The last tab absorbs the rounding so the bar spans the whole window.
    let tw = if i == tabs.high: windowX + TASK_MANAGER_WIDTH - tx else: tabWidth
    let hovered = mouseSupported and isMouseOverRect(mousePos, tx, tabY, tw, TAB_HEIGHT)
    if hovered and isPointerPressed():
      result.newTab = tab
    drawTaskManagerTab(tx, tabY, tw, taskManagerTabLabel(tab), shownTab == tab, hovered)

  # Content area
  let contentY = tabY + TAB_HEIGHT + 10
  let contentHeight = TASK_MANAGER_HEIGHT - TITLE_BAR_HEIGHT - TAB_HEIGHT - 165

  # Bottom buttons
  let buttonY = windowY + TASK_MANAGER_HEIGHT - 80
  let buttonsStartX = windowX + (TASK_MANAGER_WIDTH - 600) div 2

  case shownTab
  of tmtProcesses:
    drawProcessesTab(game, windowX, contentY, TASK_MANAGER_WIDTH.int32, contentHeight.int32)
  of tmtPatches:
    # No lives panel in a roguelite run, so the list may run down to the buttons.
    drawPatchesTab(game, windowX, contentY, TASK_MANAGER_WIDTH.int32, buttonY - 10 - contentY,
                   mouseSupported)
  of tmtPerformance:
    drawPerformanceTab(game, windowX, contentY, TASK_MANAGER_WIDTH.int32, contentHeight.int32, game.time)
  of tmtSettings:
    discard

  # Lives panel between the tab content and the buttons. Wave mode only: it is
  # the only mode with a continue budget, and an always-empty panel in survival
  # or a roguelite floor would read as a bug rather than "not applicable here".
  if game.mode == gmWaveBased and game.hasWonGame:
    drawEndlessRestorePanel(windowX + 20, buttonY - LivesPanelHeight - 14,
                            TASK_MANAGER_WIDTH.int32 - 40, game.time)
  elif game.mode == gmWaveBased:
    drawLivesPanel(windowX + 20, buttonY - LivesPanelHeight - 14,
                   TASK_MANAGER_WIDTH.int32 - 40, game.livesUsed,
                   difficultyMaxLives(), UnlimitedLives, game.time)

  # Check mouse hover for buttons
  let exitHovered = mouseSupported and isMouseOverRect(mousePos, buttonsStartX, buttonY, 180, BUTTON_HEIGHT)
  let settingsX = buttonsStartX + 180 + BUTTON_SPACING
  let settingsHovered = mouseSupported and isMouseOverRect(mousePos, settingsX, buttonY, 180, BUTTON_HEIGHT)
  let resumeX = settingsX + 180 + BUTTON_SPACING
  let resumeHovered = mouseSupported and isMouseOverRect(mousePos, resumeX, buttonY, 180, BUTTON_HEIGHT)

  # Handle button clicks
  if mouseSupported and isPointerPressed():
    if exitHovered:
      result.exitClicked = true
    elif settingsHovered:
      result.settingsClicked = true
    elif resumeHovered:
      result.resumeClicked = true

  # Exit button
  let exitBgColor = if exitHovered:
    Color(r: 150, g: 40, b: 40, a: 255)
  else:
    Color(r: 120, g: 30, b: 30, a: 255)

  drawRectangle(buttonsStartX, buttonY, 180, BUTTON_HEIGHT, exitBgColor)
  drawRectangleLines(Rectangle(x: buttonsStartX.float32, y: buttonY.float32,
                                width: 180.0, height: BUTTON_HEIGHT.float32),
                    if exitHovered: 3 else: 2,
                    if exitHovered: Color(r: 255, g: 100, b: 100, a: 255) else: Color(r: 255, g: 80, b: 80, a: 255))
  let exitText = "[Q] EXIT"
  let exitWidth = measureText(exitText, 14)
  drawText(exitText, buttonsStartX + (180 - exitWidth) div 2,
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

  # Resume button
  let resumeBgColor = if resumeHovered:
    Color(r: 0, g: 150, b: 0, a: 255)
  else:
    Color(r: 0, g: 120, b: 0, a: 255)

  drawRectangle(resumeX, buttonY, 180, BUTTON_HEIGHT, resumeBgColor)
  drawRectangleLines(Rectangle(x: resumeX.float32, y: buttonY.float32,
                                width: 180.0, height: BUTTON_HEIGHT.float32),
                    if resumeHovered: 3 else: 2,
                    if resumeHovered: Color(r: 0, g: 255, b: 100, a: 255) else: Color(r: 0, g: 255, b: 0, a: 255))
  let resumeText = "[SPACE] RESUME"
  let resumeWidth = measureText(resumeText, 14)
  drawText(resumeText, resumeX + (180 - resumeWidth) div 2,
          buttonY + 12, 14, White)

  # Status message
  drawText(t("os_system_paused") & " - " & t("os_press_space_continue"),
          windowX + 20, windowY + TASK_MANAGER_HEIGHT - 30, 12, LightGray)
