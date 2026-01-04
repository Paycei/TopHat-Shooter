## OS-Themed Help System
## Terminal-style documentation viewer

import raylib, strutils, ui/os_window, math

type
  HelpCommand* = tuple[cmd: string, desc: string]
  
  HelpWindow* = ref object
    window*: OSWindow
    commandHistory*: seq[string]
    currentInput*: string
    outputLines*: seq[tuple[text: string, color: Color]]
    scrollOffset*: int
    cursorBlink*: float32
    pendingIconExecution*: int  # -1 = none, 0-6 = icon to execute (6 = sandbox)

const
  HELP_COMMANDS: seq[HelpCommand] = @[
    ("help", "Show this command list"),
    ("controls", "View controls and keybindings"),
    ("gameplay", "Game modes and mechanics"),
    ("powerups", "Power-up reference guide"),
    ("enemies", "Enemy types and strategies"),
    ("bosses", "Boss fight strategies"),
    ("stats", "Statistics and tracking info"),
    ("shop", "Shop and economy guide"),
    ("legendary", "Legendary abilities guide"),
    ("search", "Search help topics (usage: search <term>)"),
    ("clear", "Clear the screen"),
    ("", "──────────────────────────────────────"),
    ("play/survival/sandbox/settings/quit", "Launch desktop icons by name")
  ]

proc newHelpWindow*(screenWidth, screenHeight: int): HelpWindow =
  let windowWidth = 700
  let windowHeight = 500
  let windowX = (screenWidth - windowWidth) div 2
  let windowY = (screenHeight - windowHeight) div 2
  
  let osWin = newOSWindow(
    "Help System - Terminal",
    windowX, windowY,
    windowWidth, windowHeight,
    Color(r: 100, g: 255, b: 150, a: 255),  # Green
    owtHelp
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
  
  # Add welcome message
  result.outputLines.add(("TopHat-Shooter Help System v4.1", Color(r: 0, g: 255, b: 255, a: 255)))
  result.outputLines.add(("Type 'help' for commands or a topic name to learn more.", White))
  result.outputLines.add(("", White))

proc addOutput*(help: HelpWindow, text: string, color: Color = White) =
  help.outputLines.add((text, color))

proc executeCommand*(help: HelpWindow, cmd: string) =
  # Add command to history
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
      help.addOutput("═══════════════════════════════════════", Color(r: 255, g: 200, b: 50, a: 255))
      help.addOutput("  AVAILABLE COMMANDS", Color(r: 255, g: 200, b: 50, a: 255))
      help.addOutput("═══════════════════════════════════════", Color(r: 255, g: 200, b: 50, a: 255))
      help.addOutput("", White)
      for helpCmd in HELP_COMMANDS:
        help.addOutput("  " & helpCmd.cmd & " - " & helpCmd.desc, White)
      help.addOutput("", White)
    
    of "clear":
      help.outputLines = @[
        ("TopHat-Shooter Help System v4.1", Color(r: 0, g: 255, b: 255, a: 255)),
        ("Type 'help' for commands.", White),
        ("", White)
      ]
    
    of "controls":
      help.addOutput("", White)
      help.addOutput("═══════════════════════════════════════", Color(r: 0, g: 255, b: 255, a: 255))
      help.addOutput("  CONTROLS & KEYBINDINGS", Color(r: 0, g: 255, b: 255, a: 255))
      help.addOutput("═══════════════════════════════════════", Color(r: 0, g: 255, b: 255, a: 255))
      help.addOutput("", White)
      help.addOutput("MOVEMENT", Color(r: 255, g: 200, b: 50, a: 255))
      help.addOutput("  W/A/S/D ............ Move player", White)
      help.addOutput("  Arrow Keys ......... Alternative movement", White)
      help.addOutput("", White)
      help.addOutput("COMBAT", Color(r: 255, g: 200, b: 50, a: 255))
      help.addOutput("  Left Mouse ......... Shoot", White)
      help.addOutput("  Space .............. Shoot (alternative)", White)
      help.addOutput("  F .................. Toggle Auto-Shoot*", White)
      help.addOutput("", White)
      help.addOutput("ABILITIES", Color(r: 255, g: 200, b: 50, a: 255))
      help.addOutput("  Q .................. Activate Legendary Powers", White)
      help.addOutput("  E .................. Place Wall", White)
      help.addOutput("", White)
      help.addOutput("MENU", Color(r: 255, g: 200, b: 50, a: 255))
      help.addOutput("  ESC ................ Pause / Return to menu", White)
      help.addOutput("  Tab ................ Quick stats view", White)
      help.addOutput("  F11 ................ Toggle Fullscreen", White)
      help.addOutput("", White)
      help.addOutput("* Requires Auto-Shoot power-up", Color(r: 150, g: 150, b: 150, a: 255))
      help.addOutput("", White)
    
    of "gameplay":
      help.addOutput("", White)
      help.addOutput("═══════════════════════════════════════", Color(r: 0, g: 255, b: 255, a: 255))
      help.addOutput("  GAME MODES", Color(r: 0, g: 255, b: 255, a: 255))
      help.addOutput("═══════════════════════════════════════", Color(r: 0, g: 255, b: 255, a: 255))
      help.addOutput("", White)
      help.addOutput("WAVE-BASED MODE (Main)", Color(r: 255, g: 200, b: 50, a: 255))
      help.addOutput("  • Clear waves of enemies for upgrades", White)
      help.addOutput("  • Boss appears every 5 waves", White)
      help.addOutput("  • Choose power-ups after waves", White)
      help.addOutput("  • Shop opens after selecting powerup", White)
      help.addOutput("", White)
      help.addOutput("SURVIVAL MODE (Classic)", Color(r: 255, g: 200, b: 50, a: 255))
      help.addOutput("  • Survive endless enemy hordes", White)
      help.addOutput("  • Enemies spawn progressively harder", White)
      help.addOutput("  • Boss appears every 60 seconds", White)
      help.addOutput("", White)
    
    of "powerups":
      help.addOutput("", White)
      help.addOutput("═══════════════════════════════════════", Color(r: 0, g: 255, b: 255, a: 255))
      help.addOutput("  POWER-UP TYPES", Color(r: 0, g: 255, b: 255, a: 255))
      help.addOutput("═══════════════════════════════════════", Color(r: 0, g: 255, b: 255, a: 255))
      help.addOutput("", White)
      help.addOutput("LEGENDARY (Press Q to activate)", Gold)
      help.addOutput("  Time Warp .......... Slow down time", White)
      help.addOutput("  Phase Shift ........ Teleport dash", White)
      help.addOutput("  Parry .............. Reflect bullets", White)
      help.addOutput("", White)
      help.addOutput("COMMON (Passive)", Color(r: 150, g: 200, b: 255, a: 255))
      help.addOutput("  Damage+, Speed+, Fire Rate+, etc.", White)
      help.addOutput("", White)
    
    of "enemies":
      help.addOutput("", White)
      help.addOutput("═══════════════════════════════════════", Color(r: 0, g: 255, b: 255, a: 255))
      help.addOutput("  ENEMY TYPES", Color(r: 0, g: 255, b: 255, a: 255))
      help.addOutput("═══════════════════════════════════════", Color(r: 0, g: 255, b: 255, a: 255))
      help.addOutput("", White)
      help.addOutput("BASIC ENEMIES", White)
      help.addOutput("  • Red: Standard enemy", White)
      help.addOutput("  • Blue: Fast enemy", White)
      help.addOutput("  • Green: Tank enemy", White)
      help.addOutput("", White)
      help.addOutput("ELITE ENEMIES", Color(r: 255, g: 165, b: 0, a: 255))
      help.addOutput("  • Tougher, drop more coins", White)
      help.addOutput("  • Spawn from wave 3 onwards", White)
      help.addOutput("", White)
      help.addOutput("BOSSES", Red)
      help.addOutput("  • Appear every 5 waves / 60 seconds", White)
      help.addOutput("  • Multiple phases, unique attacks", White)
      help.addOutput("", White)
    
    of "bosses":
      help.addOutput("", White)
      help.addOutput("═══════════════════════════════════════", Color(r: 255, g: 100, b: 100, a: 255))
      help.addOutput("  BOSS FIGHT GUIDE", Color(r: 255, g: 100, b: 100, a: 255))
      help.addOutput("═══════════════════════════════════════", Color(r: 255, g: 100, b: 100, a: 255))
      help.addOutput("", White)
      help.addOutput("BOSS MECHANICS", Color(r: 255, g: 200, b: 50, a: 255))
      help.addOutput("  • Bosses spawn every 5 waves (Wave Mode)", White)
      help.addOutput("  • Bosses spawn every 60 seconds (Survival)", White)
      help.addOutput("  • Multiple attack phases", White)
      help.addOutput("  • Increased health and damage", White)
      help.addOutput("", White)
      help.addOutput("STRATEGIES", Color(r: 255, g: 200, b: 50, a: 255))
      help.addOutput("  • Circle strafe to avoid attacks", White)
      help.addOutput("  • Use walls for cover", White)
      help.addOutput("  • Save Legendary abilities for boss phases", White)
      help.addOutput("  • Focus on dodging over damage", White)
      help.addOutput("", White)
      help.addOutput("REWARDS", Color(r: 255, g: 200, b: 50, a: 255))
      help.addOutput("  • Large coin drops", White)
      help.addOutput("  • Guaranteed power-up choice", White)
      help.addOutput("  • Achievement progress", White)
      help.addOutput("", White)
    
    of "stats":
      help.addOutput("", White)
      help.addOutput("═══════════════════════════════════════", Color(r: 0, g: 255, b: 255, a: 255))
      help.addOutput("  STATISTICS TRACKING", Color(r: 0, g: 255, b: 255, a: 255))
      help.addOutput("═══════════════════════════════════════", Color(r: 0, g: 255, b: 255, a: 255))
      help.addOutput("", White)
      help.addOutput("TRACKED METRICS", Color(r: 255, g: 200, b: 50, a: 255))
      help.addOutput("  • Total games played", White)
      help.addOutput("  • Total playtime", White)
      help.addOutput("  • Highest wave reached", White)
      help.addOutput("  • Longest survival time", White)
      help.addOutput("  • Best kill count", White)
      help.addOutput("  • Bosses defeated", White)
      help.addOutput("", White)
      help.addOutput("VIEWING STATS", Color(r: 255, g: 200, b: 50, a: 255))
      help.addOutput("  • Open 'Stats.exe' from desktop", White)
      help.addOutput("  • View lifetime statistics", White)
      help.addOutput("  • Review last run performance", White)
      help.addOutput("  • Analyze power-up choices", White)
      help.addOutput("", White)
    
    of "shop":
      help.addOutput("", White)
      help.addOutput("═══════════════════════════════════════", Color(r: 255, g: 200, b: 50, a: 255))
      help.addOutput("  SHOP & ECONOMY", Color(r: 255, g: 200, b: 50, a: 255))
      help.addOutput("═══════════════════════════════════════", Color(r: 255, g: 200, b: 50, a: 255))
      help.addOutput("", White)
      help.addOutput("EARNING COINS", Color(r: 255, g: 200, b: 50, a: 255))
      help.addOutput("  • Kill enemies to drop coins", White)
      help.addOutput("  • Elite enemies drop more coins", White)
      help.addOutput("  • Bosses drop large amounts", White)
      help.addOutput("  • Coins persist between waves", White)
      help.addOutput("", White)
      help.addOutput("SHOP ITEMS", Color(r: 255, g: 200, b: 50, a: 255))
      help.addOutput("  • Health regeneration items", White)
      help.addOutput("  • Temporary buffs and boosts", White)
      help.addOutput("  • Consumable abilities", White)
      help.addOutput("  • Wall placement tools", White)
      help.addOutput("", White)
      help.addOutput("TIPS", Color(r: 255, g: 200, b: 50, a: 255))
      help.addOutput("  • Shop opens after selecting power-up", White)
      help.addOutput("  • Plan purchases before waves", White)
      help.addOutput("  • Prioritize survival items", White)
      help.addOutput("", White)
    
    of "legendary":
      help.addOutput("", White)
      help.addOutput("═══════════════════════════════════════", Gold)
      help.addOutput("  LEGENDARY ABILITIES", Gold)
      help.addOutput("═══════════════════════════════════════", Gold)
      help.addOutput("", White)
      help.addOutput("ACTIVATION", Color(r: 255, g: 200, b: 50, a: 255))
      help.addOutput("  • Press Q to activate legendary power", White)
      help.addOutput("  • Limited uses (check UI for count)", White)
      help.addOutput("  • Cooldown between activations", White)
      help.addOutput("", White)
      help.addOutput("TIME WARP", Color(r: 100, g: 200, b: 255, a: 255))
      help.addOutput("  • Slows down time dramatically", White)
      help.addOutput("  • You move at normal speed", White)
      help.addOutput("  • Perfect for dodging bullet hell", White)
      help.addOutput("  • Great for boss phases", White)
      help.addOutput("", White)
      help.addOutput("PHASE SHIFT", Color(r: 200, g: 100, b: 255, a: 255))
      help.addOutput("  • Teleport dash in movement direction", White)
      help.addOutput("  • Invulnerable during dash", White)
      help.addOutput("  • Can pass through enemies", White)
      help.addOutput("  • Ideal for repositioning", White)
      help.addOutput("", White)
      help.addOutput("PARRY", Color(r: 255, g: 215, b: 0, a: 255))
      help.addOutput("  • Reflects all bullets near you", White)
      help.addOutput("  • Returned bullets deal massive damage", White)
      help.addOutput("  • Timing is crucial", White)
      help.addOutput("  • High risk, high reward", White)
      help.addOutput("", White)
    
    of "search":
      if parts.len < 2 or parts[1].strip().len == 0:
        help.addOutput("Usage: search <term>", Red)
        help.addOutput("Example: search wall", LightGray)
      else:
        let searchTerm = parts[1].toLowerAscii()
        help.addOutput("", White)
        help.addOutput("Searching for: " & searchTerm, Color(r: 255, g: 200, b: 50, a: 255))
        help.addOutput("", White)
        
        var found = 0
        # Simple keyword matching
        if searchTerm in "wall":
          help.addOutput("Found in 'controls':", White)
          help.addOutput("  E .............. Place Wall", LightGray)
          found += 1
        
        if searchTerm in "legendary" or searchTerm in "ability" or searchTerm in "power":
          help.addOutput("Found in 'controls':", White)
          help.addOutput("  Q .............. Activate Legendary Powers", LightGray)
          help.addOutput("See also: legendary", LightGray)
          found += 1
        
        if searchTerm in "boss":
          help.addOutput("See: bosses", LightGray)
          found += 1
        
        if searchTerm in "shop" or searchTerm in "coin":
          help.addOutput("See: shop", LightGray)
          found += 1
        
        if found == 0:
          help.addOutput("No results found. Try: help", Red)
        
        help.addOutput("", White)
    
    # Desktop icon execution commands
    of "play", "play.exe":
      help.addOutput("Launching Play.exe...", Color(r: 100, g: 200, b: 255, a: 255))
      help.pendingIconExecution = 0
    
    of "survival", "survival.exe":
      help.addOutput("Launching Survival.exe...", Color(r: 255, g: 150, b: 100, a: 255))
      help.pendingIconExecution = 1
    
    of "stats.exe", "statistics":
      help.addOutput("Opening Stats.exe...", Color(r: 255, g: 200, b: 50, a: 255))
      help.pendingIconExecution = 2
    
    of "settings", "settings.exe":
      help.addOutput("Opening Settings.exe...", Color(r: 200, g: 100, b: 255, a: 255))
      help.pendingIconExecution = 3
    
    of "sandbox", "sandbox.exe":
      help.addOutput("Launching Sandbox.exe...", Color(r: 255, g: 165, b: 0, a: 255))
      help.pendingIconExecution = 6  # New index for sandbox
    
    of "quit", "shutdown", "shutdown.exe", "exit":
      help.addOutput("Shutting down...", Color(r: 255, g: 100, b: 100, a: 255))
      help.pendingIconExecution = 5
    
    else:
      help.addOutput("Unknown command: " & command, Red)
      help.addOutput("Type 'help' for available commands", LightGray)
      help.addOutput("Tip: You can also type icon names like 'play' or 'settings'", Color(r: 150, g: 150, b: 150, a: 255))
      help.addOutput("", White)
  
  except Exception as e:
    # Catch any errors during command execution
    help.addOutput("Error executing command: " & e.msg, Red)
    help.addOutput("Type 'help' for available commands", LightGray)
    help.addOutput("", White)


proc updateHelpWindow*(help: HelpWindow, dt: float32, screenWidth, screenHeight: int): int =
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
  let shouldClose = handleOSWindowInput(help.window, screenWidth, screenHeight)
  if shouldClose:
    help.window.visible = false
    return -1
  
  # Handle text input with safety checks
  let key = getCharPressed()
  if key > 0 and key < 256:  # Valid ASCII range
    let ch = char(key)
    # Only accept printable ASCII characters and limit input length
    if ch >= ' ' and ch <= '~' and help.currentInput.len < 100:
      help.currentInput.add(ch)
  
  # Handle backspace
  if isKeyPressed(Backspace) and help.currentInput.len > 0:
    help.currentInput.setLen(help.currentInput.len - 1)
  
  # Handle enter - execute command
  if isKeyPressed(Enter):
    if help.currentInput.len > 0:
      executeCommand(help, help.currentInput)
      help.currentInput = ""
    help.scrollOffset = max(0, help.outputLines.len - 15)  # Scroll to bottom
  
  # Handle scrolling with mouse wheel
  let wheel = getMouseWheelMove()
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
  
  # Draw output lines (with scrolling)
  var yPos = contentY + 10
  let lineHeight = 18
  let visibleLines = (contentH - 50) div lineHeight
  let startLine = help.scrollOffset
  let endLine = min(help.outputLines.len, startLine + visibleLines)
  
  for i in startLine..<endLine:
    let line = help.outputLines[i]
    drawText(line.text, (contentX + 10).int32, yPos.int32, 14, line.color)
    yPos += lineHeight
  
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
