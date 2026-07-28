## OS-Themed Help System
## Terminal-style documentation viewer

import raylib, strutils, math
import os_window, ../localization, ../powerup_data, ../gamemode_definitions, ../enemy_config, ../boss_definitions, ../types, ../settings, icon_drawing
import ../gamepad_input

const
  HELP_LINE_HEIGHT* = 18
  HELP_ICON_SIZE* = HELP_LINE_HEIGHT - 4
  HELP_ICON_PADDING* = 6

type
  HelpCommand* = tuple[cmd: string, desc: string]

  HelpWindow* = ref object
    window*: OSWindow
    commandHistory*: seq[string]
    currentInput*: string
    outputLines*: seq[tuple[text: string, color: Color, icon: int, indent: int]]
    scrollOffset*: int
    cursorBlink*: float32
    pendingIconExecution*: int  # -1 = none, 0-6 = icon to execute (6 = sandbox)

proc getHelpCommands*(): seq[HelpCommand] =
  ## Returns help commands with translated descriptions
  @[
    ("help", t(tkHelpCmdHelp)),
    ("controls", t(tkHelpCmdControls)),
    ("gameplay", t(tkHelpCmdGameplay)),
    ("powerups", t(tkHelpCmdPowerups)),
    ("enemies", t(tkHelpCmdEnemies)),
    ("bosses", t(tkHelpCmdBosses)),
    ("shop", t(tkHelpCmdShop)),
    ("customize", "Customize player and bullet skins"),
    ("advancements", "Open persistent progression tracker"),
    ("clear", t(tkHelpClearCommand)),
    ("", t(tkHelpCommandSeparator)),
    (t(tkHelpLaunchTopics), t(tkHelpCmdLaunchIcons))
  ]

proc newHelpWindow*(screenWidth, screenHeight: int): HelpWindow =
  let windowWidth = 700
  let windowHeight = 500
  let windowX = (screenWidth - windowWidth) div 2
  let windowY = (screenHeight - windowHeight) div 2

  let osWin = newOSWindow(
    t(tkHelpWindowTitle),
    windowX, windowY,
    windowWidth, windowHeight,
    Color(r: 100, g: 255, b: 150, a: 255),  # Green
    owtHelp,
    resizable = false
  )

  result = HelpWindow(
    window: osWin,
    commandHistory: @[],
    currentInput: "",
    outputLines: @[],
    scrollOffset: 0,
    cursorBlink: 0,
    pendingIconExecution: -1
  )

  result.outputLines.add(("TopHat-ShooterOS Help System v6.1", Color(r: 0, g: 255, b: 255, a: 255), -1, 0))
  result.outputLines.add(("Type 'help' for commands or a topic name to learn more.", White, -1, 0))
  result.outputLines.add(("", White, -1, 0))

proc addOutput*(help: HelpWindow, text: string, color: Color = White, icon: int = -1, indent: int = 0) =
  help.outputLines.add((text, color, icon, indent))

proc wrapTextToWidth(text: string, maxWidth: int32, fontSize: int32): seq[string] =
  var resLines: seq[string] = @[]
  for paragraph in text.split("\n"):
    if paragraph.len == 0:
      resLines.add("")
      continue
    var words = paragraph.split(' ')
    var cur = ""
    for w in words:
      var candidate = if cur.len == 0: w else: cur & " " & w
      if measureText(candidate, fontSize) <= maxWidth:
        cur = candidate
      else:
        if cur.len > 0:
          resLines.add(cur)
          cur = w
        else:
          # Break the long word into chunks that fit
          var chunk = ""
          for ch in w:
            let test = chunk & ch
            if measureText(test, fontSize) <= maxWidth:
              chunk = test
            else:
              if chunk.len > 0:
                resLines.add(chunk)
              chunk = "" & ch
          if chunk.len > 0:
            cur = chunk
    if cur.len > 0:
      resLines.add(cur)
  return resLines

proc iconStatusText(actionKey, iconKey: TranslationKey): string =
  t(actionKey).replace("$1", t(iconKey))

proc executeCommand*(help: HelpWindow, cmd: string) =
  help.commandHistory.add(cmd)

  # Echo the command
  help.addOutput("$ " & cmd, Color(r: 0, g: 220, b: 220, a: 255))

  # Safety check for empty or whitespace-only commands
  let trimmedCmd = cmd.strip()
  if trimmedCmd.len == 0:
    return

  # Safe string splitting with error handling
  try:
    let parts = trimmedCmd.split(' ')
    if parts.len == 0 or parts[0] == "":
      return

    let command = parts[0].toLowerAscii()

    case command:
    of "help", "?":
      help.addOutput("", White)
      help.addOutput("=======================================", Color(r: 255, g: 200, b: 50, a: 255))
      help.addOutput("  " & t(tkHelpAvailableCommands), Color(r: 255, g: 200, b: 50, a: 255))
      help.addOutput("=======================================", Color(r: 255, g: 200, b: 50, a: 255))
      help.addOutput("", White)
      for helpCmd in getHelpCommands():
        help.addOutput("  " & helpCmd.cmd & " - " & helpCmd.desc, White)
      help.addOutput("", White)

    of "clear":
      help.outputLines = @[
        ("TopHat-ShooterOS Help System v6.1", Color(r: 0, g: 255, b: 255, a: 255), -1, 0),
        ("Type 'help' for commands.", White, -1, 0),
        ("", White, -1, 0)
      ]

    of "controls":
      help.addOutput("", White)
      help.addOutput("=======================================", Color(r: 0, g: 255, b: 255, a: 255))
      help.addOutput("  " & t(tkHelpControlsKeybindings), Color(r: 0, g: 255, b: 255, a: 255))
      help.addOutput("=======================================", Color(r: 0, g: 255, b: 255, a: 255))
      help.addOutput("", White)
      help.addOutput(t(tkHelpMovement), Color(r: 255, g: 200, b: 50, a: 255))
      help.addOutput("  " & t(tkHelpWASD), White)
      help.addOutput("  " & t(tkHelpArrowKeys), White)
      help.addOutput("", White)
      help.addOutput(t(tkHelpCombat), Color(r: 255, g: 200, b: 50, a: 255))
      help.addOutput("  " & t(tkHelpLeftMouse), White)
      help.addOutput("  " & t(tkHelpSpace), White)
      help.addOutput("", White)
      help.addOutput(t(tkHelpAbilities), Color(r: 255, g: 200, b: 50, a: 255))
      help.addOutput("  " & t(tkHelpQ), White)
      help.addOutput("  " & t(tkHelpE), White)
      help.addOutput("", White)
      help.addOutput(t(tkHelpMenu), Color(r: 255, g: 200, b: 50, a: 255))
      help.addOutput("  " & t(tkHelpESC), White)
      help.addOutput("  " & t(tkHelpF11), White)
      help.addOutput("", White)

    of "gameplay":
      help.addOutput("", White)
      help.addOutput("=======================================", Color(r: 0, g: 255, b: 255, a: 255))
      help.addOutput("  " & t(tkHelpGameplayTopic), Color(r: 0, g: 255, b: 255, a: 255))
      help.addOutput("=======================================", Color(r: 0, g: 255, b: 255, a: 255))
      help.addOutput("", White)
      for gm in getAllGameModes():
        help.addOutput(gm.name, Color(r: 255, g: 200, b: 50, a: 255))
        for line in gm.description.split("\n"):
          help.addOutput(line, White, -1, 0)
        help.addOutput("", White)

    of "powerups":
      help.addOutput("", White)
      help.addOutput("=======================================", Color(r: 0, g: 255, b: 255, a: 255))
      help.addOutput("  " & t(tkHelpPowerUpsTopic), Color(r: 0, g: 255, b: 255, a: 255))
      help.addOutput("=======================================", Color(r: 0, g: 255, b: 255, a: 255))
      help.addOutput("", White)
      # List all power-up names and short descriptions from authoritative source
      for i in ord(low(PowerUpType)) .. ord(high(PowerUpType)):
        let pu = PowerUpType(i)
        if isPowerUpDiscovered(pu):
          # Add name with icon index (ordinal of PowerUpType) and the powerup's own color
          let puColor = getPowerUpColor(pu)
          help.addOutput(getPowerUpName(pu), puColor, i, 0)
          # Use level 1 and default playerDamage for example descriptions, indent descriptions to align under name
          let desc = getPowerUpDescription(pu, 1, 1.0)
          for line in desc.split("\n"):
            help.addOutput(line, LightGray, -1, (HELP_ICON_SIZE + HELP_ICON_PADDING))
        else:
          # Undiscovered: a lock icon (sentinel -2) and preset text, hiding the
          # power-up's name and description until it's found in a run.
          help.addOutput(t(tkHelpPowerUpLockedName), Color(r: 130, g: 140, b: 155, a: 255), -2, 0)
          help.addOutput(t(tkHelpPowerUpLockedDesc), Color(r: 120, g: 130, b: 145, a: 255),
                         -1, (HELP_ICON_SIZE + HELP_ICON_PADDING))
        help.addOutput("", White, -1, 0)

    of "enemies":
      help.addOutput("", White)
      help.addOutput("=======================================", Color(r: 0, g: 255, b: 255, a: 255))
      help.addOutput("  " & t(tkHelpEnemiesTopic), Color(r: 0, g: 255, b: 255, a: 255))
      help.addOutput("=======================================", Color(r: 0, g: 255, b: 255, a: 255))
      help.addOutput("", White)
      for i in ord(low(EnemyType)) .. ord(high(EnemyType)):
        let et = EnemyType(i)
        let cfg = getEnemyConfig(et)
        help.addOutput("  " & cfg.name, cfg.baseColor)
        for line in cfg.description.split("\n"):
          help.addOutput("    " & line, White)
        help.addOutput("", White)

    of "bosses":
      help.addOutput("", White)
      help.addOutput("=======================================", Color(r: 255, g: 100, b: 100, a: 255))
      help.addOutput("  " & t(tkHelpBossesTopic), Color(r: 255, g: 100, b: 100, a: 255))
      help.addOutput("=======================================", Color(r: 255, g: 100, b: 100, a: 255))
      help.addOutput("", White)
      # General boss mechanics (keep high-level help text)
      help.addOutput(t(tkHelpBossSpawning), Color(r: 255, g: 200, b: 50, a: 255))
      help.addOutput("  " & t(tkHelpBossEvery5th), White)
      help.addOutput("  " & t(tkHelpBossEvery60Sec), White)
      help.addOutput("", White)
      help.addOutput(t(tkHelpBossMechanics), Color(r: 255, g: 200, b: 50, a: 255))
      help.addOutput("  - Unique attack patterns", White)
      help.addOutput("  - Multiple phases as HP decreases", White)
      help.addOutput("  - Higher HP and damage than normal enemies", White)
      help.addOutput("  - Speed and damage increase with each phase", White)
      help.addOutput("", White)
      help.addOutput(t(tkHelpBossAttacks), Color(r: 255, g: 200, b: 50, a: 255))
      help.addOutput("  - Refer to individual boss entries below for specifics", White)
      help.addOutput("", White)
      # List all bosses with short descriptions
      for id in 1..12:
        let bd = getBossDefinition(id)
        help.addOutput("  " & bd.name, bd.color)
        for line in bd.description.split("\n"):
          help.addOutput("    " & line, White)
        help.addOutput("", White)

    of "shop":
      help.addOutput("", White)
      help.addOutput("=======================================", Color(r: 255, g: 200, b: 50, a: 255))
      help.addOutput("  " & t(tkHelpShopTopic), Color(r: 255, g: 200, b: 50, a: 255))
      help.addOutput("=======================================", Color(r: 255, g: 200, b: 50, a: 255))
      help.addOutput("", White)
      help.addOutput(t(tkHelpAvailableItems), Color(r: 255, g: 200, b: 50, a: 255))
      help.addOutput("  " & t(tkHelpShopDamagePlus), White)
      help.addOutput("    " & t(tkHelpShopDamagePlusDesc), White)
      help.addOutput("", White)
      help.addOutput("  " & t(tkHelpShopFireRatePlus), White)
      help.addOutput("    " & t(tkHelpShopFireRatePlusDesc), White)
      help.addOutput("", White)
      help.addOutput("  " & t(tkHelpShopMoveSpeedPlus), White)
      help.addOutput("    " & t(tkHelpShopMoveSpeedPlusDesc), White)
      help.addOutput("", White)
      help.addOutput("  " & t(tkHelpShopMaxHealthPlus), White)
      help.addOutput("    " & t(tkHelpShopMaxHealthPlusDesc), White)
      help.addOutput("", White)
      help.addOutput("  " & t(tkHelpShopBulletSpeedPlus), White)
      help.addOutput("    " & t(tkHelpShopBulletSpeedPlusDesc), White)
      help.addOutput("", White)
      help.addOutput("  " & t(tkHelpShopWallX4), White)
      help.addOutput("    " & t(tkHelpShopWallX4Desc), White)
      help.addOutput("", White)
      help.addOutput(t(tkHelpCostScaling), Color(r: 255, g: 200, b: 50, a: 255))
      help.addOutput("  " & t(tkHelpCostScalingFormula), White)
      help.addOutput("", White)
      help.addOutput(t(tkHelpEarningCoins), Color(r: 255, g: 200, b: 50, a: 255))
      help.addOutput("  " & t(tkHelpKillEnemiesToCollect), White)
      help.addOutput("  " & t(tkHelpEliteDropMore), White)
      help.addOutput("  " & t(tkHelpBossDropLarge), White)
      help.addOutput("", White)
      help.addOutput(t(tkHelpShopAccess), Color(r: 255, g: 200, b: 50, a: 255))
      help.addOutput("  " & t(tkHelpOpensAfterPowerup), White)
      help.addOutput("  " & t(tkHelpAvailableBetweenWaves), White)
      help.addOutput("", White)

    # Desktop icon execution commands
    of "play", "play.exe":
      help.addOutput(iconStatusText(tkHelpLaunchingIcon, tkDesktopIconPlay), Color(r: 100, g: 200, b: 255, a: 255))
      help.pendingIconExecution = 0

    of "survival", "survival.exe":
      help.addOutput(iconStatusText(tkHelpLaunchingIcon, tkDesktopIconSurvival), Color(r: 255, g: 150, b: 100, a: 255))
      help.pendingIconExecution = 1

    of "stats", "stats.exe", "statistics":
      help.addOutput(iconStatusText(tkHelpOpeningIcon, tkDesktopIconStats), Color(r: 255, g: 200, b: 50, a: 255))
      help.pendingIconExecution = 2

    of "settings", "settings.exe":
      help.addOutput(iconStatusText(tkHelpOpeningIcon, tkDesktopIconSettings), Color(r: 200, g: 100, b: 255, a: 255))
      help.pendingIconExecution = 3

    of "shop.exe", "customization", "customize", "skins":
      help.addOutput(iconStatusText(tkHelpOpeningIcon, tkDesktopIconShop), Color(r: 255, g: 150, b: 50, a: 255))
      help.pendingIconExecution = 4

    of "advancements", "advncmnts.exe", "advancement":
      help.addOutput(iconStatusText(tkHelpOpeningIcon, tkDesktopIconAdvancements), Color(r: 90, g: 220, b: 255, a: 255))
      help.pendingIconExecution = 10

    of "credits", "credits.nfo", "about", "support":
      help.addOutput(iconStatusText(tkHelpOpeningIcon, tkDesktopIconCredits), Color(r: 255, g: 110, b: 160, a: 255))
      help.pendingIconExecution = 12  # diCredits = 12

    of "sandbox", "sandbox.exe":
      help.addOutput(iconStatusText(tkHelpLaunchingIcon, tkDesktopIconSandbox), Color(r: 255, g: 165, b: 0, a: 255))
      help.pendingIconExecution = 7  # diSandbox = 7

    of "quit", "shutdown", "shutdown.exe", "exit":
      help.addOutput(iconStatusText(tkHelpExecutingIcon, tkDesktopIconQuit), Color(r: 255, g: 100, b: 100, a: 255))
      help.pendingIconExecution = 6  # diQuit = 6

    else:
      help.addOutput(t(tkHelpUnknownCommand) & ": " & command, Red)
      help.addOutput(t(tkHelpTypeHelp), LightGray)
      help.addOutput("", White)

  except Exception as e:
    # Catch any errors during command execution
    help.addOutput(t(tkHelpErrorExecuting) & ": " & e.msg, Red)
    help.addOutput(t(tkHelpTypeHelp), LightGray)
    help.addOutput("", White)

proc updateHelpWindow*(help: HelpWindow, dt: float32, screenWidth, screenHeight: int, allWindows: openArray[OSWindow]): int =
  ## Returns icon to execute: -1 = none, 0-6 = desktop icon index (6 = sandbox)
  ## Window closing is handled by setting help.window.visible = false
  updateOSWindow(help.window, dt)
  help.cursorBlink += dt

  if not help.window.visible:
    return -1

  # Check for pending icon execution
  if help.pendingIconExecution >= 0:
    let iconToExecute = help.pendingIconExecution
    help.pendingIconExecution = -1
    help.window.visible = false  # Close help window after executing icon
    return iconToExecute

  # Check if window should close
  let shouldClose = handleOSWindowInput(help.window, screenWidth, screenHeight, allWindows)
  if shouldClose:
    help.window.visible = false
    return -1

  # The whole window is a typed-command REPL, so the on-screen keyboard is
  # always up while it is open rather than being tied to a focused field.
  setTextInputActive(true, tikText)

  # Handle text input with safety checks
  let key = pollCharPressed()
  if key > 0 and key < 256:  # Valid ASCII range
    let ch = char(key)
    # Only accept printable ASCII characters and limit input length
    if ch >= ' ' and ch <= '~' and help.currentInput.len < 100:
      help.currentInput.add(ch)

  # Handle backspace
  if pollBackspacePressed() and help.currentInput.len > 0:
    help.currentInput.setLen(help.currentInput.len - 1)

  # Handle enter - execute command
  if pollEnterPressed():
    if help.currentInput.len > 0:
      executeCommand(help, help.currentInput)
      help.currentInput = ""
    help.scrollOffset = max(0, help.outputLines.len - 15)  # Scroll to bottom

  # Handle scrolling with mouse wheel
  let wheel = getPointerWheelMove()
  if wheel != 0:
    help.scrollOffset = clamp(help.scrollOffset - int(wheel * 3), 0,
                              max(0, help.outputLines.len - 15))

  return -1  # No icon to execute

proc drawHelpWindow*(help: HelpWindow) =
  if not help.window.visible:
    return

  # Draw window chrome
  drawWindowChrome(help.window)

  if help.window.minimized:
    return

  let contentX = help.window.x + WINDOW_PADDING
  let contentY = help.window.y + TITLE_BAR_HEIGHT + WINDOW_PADDING
  let contentW = help.window.width - WINDOW_PADDING * 2
  let contentH = help.window.height - TITLE_BAR_HEIGHT - WINDOW_PADDING * 2

  # Terminal background
  drawRectangle(contentX.int32, contentY.int32, contentW.int32, contentH.int32,
               Color(r: 5, g: 5, b: 10, a: 255))
  drawRectangleLines(Rectangle(x: contentX.float32, y: contentY.float32,
                                width: contentW.float32, height: contentH.float32),
                    1, Color(r: 0, g: 200, b: 200, a: 255))

  # Draw output lines (with scrolling, wrapping, and optional icons)
  var yPos = contentY + 10
  let lineHeight = HELP_LINE_HEIGHT
  let visibleLines = (contentH - 50) div lineHeight
  let startEntry = clamp(help.scrollOffset, 0, max(0, help.outputLines.len - 1))

  let baseTextX = contentX + 10
  var i = startEntry
  var stopRendering = false
  while i < help.outputLines.len and not stopRendering:
    let line = help.outputLines[i]
    let hasPowerUpIcon = line.icon >= 0
    let hasLockIcon = line.icon == -2  # sentinel: undiscovered power-up
    let iconPresent = hasPowerUpIcon or hasLockIcon
    var availableW: int32 = (contentW - 20).int32 - line.indent.int32
    if iconPresent:
      availableW = availableW - int32(HELP_ICON_SIZE + HELP_ICON_PADDING)
    if availableW < 20.int32:
      availableW = 20.int32

    let wrapped = wrapTextToWidth(line.text, availableW, int32(14))

    # Draw icon (on first wrapped line) if present
    if iconPresent and wrapped.len > 0:
      let iconX = (baseTextX + line.indent).int32
      if hasLockIcon:
        drawLockIcon(iconX, yPos.int32, int32(HELP_ICON_SIZE), line.color)
      else:
        drawPowerUpIcon(iconX, yPos.int32, int32(HELP_ICON_SIZE), PowerUpType(line.icon), line.color)
    
    var firstWrapped = true
    for wline in wrapped:
      let textX = baseTextX + line.indent + (if iconPresent and firstWrapped: HELP_ICON_SIZE + HELP_ICON_PADDING else: 0)
      drawText(wline, textX.int32, yPos.int32, 14, line.color)
      yPos += lineHeight
      firstWrapped = false
      if yPos + lineHeight > contentY + contentH - 50:
        stopRendering = true
        break
    
    if not stopRendering:
      i = i + 1

  # Draw command prompt at bottom
  let promptY = contentY + contentH - 30
  drawRectangle(contentX.int32, promptY.int32, contentW.int32, 30,
               Color(r: 10, g: 10, b: 15, a: 255))

  let promptText = "$ " & help.currentInput
  drawText(promptText, (contentX + 10).int32, (promptY + 7).int32, 16,
          Color(r: 0, g: 220, b: 220, a: 255))

  # Draw blinking cursor
  if (help.cursorBlink mod 1.0) < 0.5:
    let cursorX = contentX + 10 + measureText(promptText, 16)
    drawRectangle((cursorX + 2).int32, (promptY + 7).int32, 8, 16,
                 Color(r: 0, g: 255, b: 255, a: 255))

  # Draw scroll indicator if needed
  if help.outputLines.len > visibleLines:
    let scrollBarX = contentX + contentW - 10
    let scrollBarY = contentY + 10
    let scrollBarH = contentH - 50
    let scrollThumbH = max(20, int(float32(scrollBarH) *
                        float32(visibleLines) / float32(help.outputLines.len)))
    let scrollThumbY = clamp(
      scrollBarY + int(float32(scrollBarH - scrollThumbH) *
                        float32(help.scrollOffset) / float32(max(1, help.outputLines.len - visibleLines))),
      scrollBarY,
      scrollBarY + scrollBarH - scrollThumbH)

    # Scroll track
    drawRectangle(scrollBarX.int32, scrollBarY.int32, 6, scrollBarH.int32,
                 Color(r: 20, g: 20, b: 30, a: 255))

    # Scroll thumb
    drawRectangle(scrollBarX.int32, scrollThumbY.int32, 6, scrollThumbH.int32,
                 Color(r: 0, g: 200, b: 200, a: 255))

  # Draw resize indicator
  drawResizeIndicator(help.window)
