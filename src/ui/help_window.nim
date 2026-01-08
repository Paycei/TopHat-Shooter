## OS-Themed Help System
## Terminal-style documentation viewer

import raylib, strutils, os_window, math

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
    ("powerups", "Complete power-up reference"),
    ("enemies", "Enemy types and behaviors"),
    ("bosses", "Boss information"),
    ("shop", "Shop items and costs"),
    ("clear", "Clear the screen"),
    ("", "--------------------------------------"),
    ("play/survival/sandbox/stats/settings/quit", "Launch desktop icons by name")
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
  result.outputLines.add(("TopHat-ShooterOS Help System v5.1", Color(r: 0, g: 255, b: 255, a: 255)))
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
      help.addOutput("=======================================", Color(r: 255, g: 200, b: 50, a: 255))
      help.addOutput("  AVAILABLE COMMANDS", Color(r: 255, g: 200, b: 50, a: 255))
      help.addOutput("=======================================", Color(r: 255, g: 200, b: 50, a: 255))
      help.addOutput("", White)
      for helpCmd in HELP_COMMANDS:
        help.addOutput("  " & helpCmd.cmd & " - " & helpCmd.desc, White)
      help.addOutput("", White)
    
    of "clear":
      help.outputLines = @[
        ("TopHat-Shooter Help System v5.1", Color(r: 0, g: 255, b: 255, a: 255)),
        ("Type 'help' for commands.", White),
        ("", White)
      ]
    
    of "controls":
      help.addOutput("", White)
      help.addOutput("=======================================", Color(r: 0, g: 255, b: 255, a: 255))
      help.addOutput("  CONTROLS & KEYBINDINGS", Color(r: 0, g: 255, b: 255, a: 255))
      help.addOutput("=======================================", Color(r: 0, g: 255, b: 255, a: 255))
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
      help.addOutput("=======================================", Color(r: 0, g: 255, b: 255, a: 255))
      help.addOutput("  GAME MODES", Color(r: 0, g: 255, b: 255, a: 255))
      help.addOutput("=======================================", Color(r: 0, g: 255, b: 255, a: 255))
      help.addOutput("", White)
      help.addOutput("WAVE-BASED MODE", Color(r: 255, g: 200, b: 50, a: 255))
      help.addOutput("  - Clear waves of enemies", White)
      help.addOutput("  - Boss appears every 5th wave", White)
      help.addOutput("  - Choose power-up after each wave", White)
      help.addOutput("  - Shop opens after power-up selection", White)
      help.addOutput("", White)
      help.addOutput("SURVIVAL MODE", Color(r: 255, g: 200, b: 50, a: 255))
      help.addOutput("  - Survive endless enemy hordes", White)
      help.addOutput("  - Enemies spawn continuously", White)
      help.addOutput("  - Boss appears every 60 seconds", White)
      help.addOutput("", White)
      help.addOutput("SANDBOX MODE", Color(r: 255, g: 200, b: 50, a: 255))
      help.addOutput("  - Testing mode with spawner controls", White)
      help.addOutput("  - Experiment with different scenarios", White)
      help.addOutput("", White)
    
    of "powerups":
      help.addOutput("", White)
      help.addOutput("=======================================", Color(r: 0, g: 255, b: 255, a: 255))
      help.addOutput("  POWER-UPS REFERENCE", Color(r: 0, g: 255, b: 255, a: 255))
      help.addOutput("=======================================", Color(r: 0, g: 255, b: 255, a: 255))
      help.addOutput("", White)
      help.addOutput("COMMON POWER-UPS", Color(r: 255, g: 200, b: 50, a: 255))
      help.addOutput("  Double Shot - Fire 2 bullets per shot", White)
      help.addOutput("  Rotating Shield - Orbiting protective shield", White)
      help.addOutput("  Damage Zone - Passive damage aura", White)
      help.addOutput("  Magical Bullets - Bullets track enemies", White)
      help.addOutput("  Piercing Shots - Bullets pass through enemies", White)
      help.addOutput("  Multi Shot - Shoots in 3 directions", White)
      help.addOutput("  Explosive Bullets - Bullets explode on impact", White)
      help.addOutput("  Life Steal - Gain HP from kills", White)
      help.addOutput("  Rapid Fire - Increased fire rate", White)
      help.addOutput("  Max Health - Increase max HP", White)
      help.addOutput("  Speed Boost - Permanent speed increase", White)
      help.addOutput("  Bullet Damage - Increased bullet damage", White)
      help.addOutput("  Bullet Speed - Faster bullets", White)
      help.addOutput("  Lucky Coins - Doubles coins collected", White)
      help.addOutput("  Wall Master - Place stronger walls", White)
      help.addOutput("  Auto Shoot - Auto-target nearest enemy", White)
      help.addOutput("  Bullet Size - Larger projectiles", White)
      help.addOutput("  Regeneration - Slowly restore HP", White)
      help.addOutput("  Dodge Chance - Chance to evade damage", White)
      help.addOutput("  Critical Hit - Random critical damage", White)
      help.addOutput("  Blood Bullets - Lifesteal on hit", White)
      help.addOutput("  Bullet Ricochet - Bullets ricochet off enemies", White)
      help.addOutput("  Slow Field - Enemies move slower nearby", White)
      help.addOutput("  Rage - Damage increases at low HP", White)
      help.addOutput("  Berserker - Attack speed at low HP", White)
      help.addOutput("  Thorns - Reflect damage to attackers", White)
      help.addOutput("  Bullet Split - Bullets split on impact", White)
      help.addOutput("  Chain Lightning - Damage chains between enemies", White)
      help.addOutput("  Frost Shots - Bullets slow enemies", White)
      help.addOutput("  Poison Shot - Poison bullets with DoT", White)
      help.addOutput("  Fire Bullets - Fire damage over time", White)
      help.addOutput("  Wind Bullets - Bullets push enemies", White)
      help.addOutput("  Overcharge - Bullets gain power over distance", White)
      help.addOutput("  Echo Shots - Bullets leave damaging trails", White)
      help.addOutput("", White)
      help.addOutput("ELEMENTAL ORBS", Color(r: 100, g: 200, b: 255, a: 255))
      help.addOutput("  Poison Orb - Poison elemental orb", White)
      help.addOutput("  Fire Orb - Fire elemental orb", White)
      help.addOutput("  Lightning Orb - Lightning elemental orb", White)
      help.addOutput("  Wind Orb - Wind elemental orb", White)
      help.addOutput("  Frost Orb - Frost elemental orb", White)
      help.addOutput("  Arcane Orb - Arcane elemental orb", White)
      help.addOutput("  Blood Orb - Blood elemental orb", White)
      help.addOutput("", White)
      help.addOutput("ELEMENTAL AURAS", Color(r: 200, g: 100, b: 255, a: 255))
      help.addOutput("  Fire Aura - Fire damage over time aura", White)
      help.addOutput("  Lightning Aura - Lightning chains between enemies", White)
      help.addOutput("  Poison Aura - Poison damage over time aura", White)
      help.addOutput("  Wind Aura - Pushes enemies away", White)
      help.addOutput("  Arcane Aura - Enhanced arcane damage aura", White)
      help.addOutput("  Blood Aura - Damage aura with lifesteal", White)
      help.addOutput("", White)
      help.addOutput("LEGENDARY POWER-UPS (Press Q)", Gold)
      help.addOutput("  Time Warp - Slow down time globally", White)
      help.addOutput("  Gravity Well - Pull enemies toward you", White)
      help.addOutput("  Phase Shift - Teleport dash through enemies", White)
      help.addOutput("  Parry - Invincible + bounce bullets", White)
      help.addOutput("  Rotating Orbs - All elemental orbs at once", White)
      help.addOutput("  Fire Mastery - Enhance all fire effects", White)
      help.addOutput("  Poison Mastery - Enhance all poison effects", White)
      help.addOutput("  Frost Mastery - Enhance all frost effects", White)
      help.addOutput("  Arcane Mastery - Enhance all arcane effects", White)
      help.addOutput("  Lightning Mastery - Enhance lightning effects", White)
      help.addOutput("  Wind Mastery - Enhance all wind effects", White)
      help.addOutput("  Blood Mastery - Enhance all blood effects", White)
      help.addOutput("", White)
    
    of "enemies":
      help.addOutput("", White)
      help.addOutput("=======================================", Color(r: 0, g: 255, b: 255, a: 255))
      help.addOutput("  ENEMY TYPES", Color(r: 0, g: 255, b: 255, a: 255))
      help.addOutput("=======================================", Color(r: 0, g: 255, b: 255, a: 255))
      help.addOutput("", White)
      help.addOutput("CIRCLE (Chaser)", Color(r: 255, g: 100, b: 100, a: 255))
      help.addOutput("  - Normal chasing enemies", White)
      help.addOutput("  - Follows player movement", White)
      help.addOutput("  - Most common enemy type", White)
      help.addOutput("", White)
      help.addOutput("CUBE (Turret)", Color(r: 100, g: 100, b: 255, a: 255))
      help.addOutput("  - Stationary or slow-moving shooters", White)
      help.addOutput("  - Fires projectiles at player", White)
      help.addOutput("  - Keep your distance", White)
      help.addOutput("", White)
      help.addOutput("TRIANGLE (Dasher)", Color(r: 255, g: 200, b: 50, a: 255))
      help.addOutput("  - Fast dash attackers", White)
      help.addOutput("  - Quick bursts of speed", White)
      help.addOutput("  - Dangerous at close range", White)
      help.addOutput("", White)
      help.addOutput("STAR (Tank)", Color(r: 150, g: 255, b: 150, a: 255))
      help.addOutput("  - High HP enemies", White)
      help.addOutput("  - Requires many hits to defeat", White)
      help.addOutput("  - Dashes when getting close", White)
      help.addOutput("", White)
      help.addOutput("HEXAGON (Warper)", Color(r: 200, g: 100, b: 255, a: 255))
      help.addOutput("  - Teleporting chaos enemy", White)
      help.addOutput("  - Unpredictable movement", White)
      help.addOutput("  - Can appear anywhere suddenly", White)
      help.addOutput("", White)
      help.addOutput("ELITE VARIANTS", Color(r: 255, g: 165, b: 0, a: 255))
      help.addOutput("  - Tougher versions of all enemy types", White)
      help.addOutput("  - Drop more coins when defeated", White)
      help.addOutput("  - Spawn in later waves", White)
      help.addOutput("", White)
    
    of "bosses":
      help.addOutput("", White)
      help.addOutput("=======================================", Color(r: 255, g: 100, b: 100, a: 255))
      help.addOutput("  BOSS INFORMATION", Color(r: 255, g: 100, b: 100, a: 255))
      help.addOutput("=======================================", Color(r: 255, g: 100, b: 100, a: 255))
      help.addOutput("", White)
      help.addOutput("BOSS SPAWNING", Color(r: 255, g: 200, b: 50, a: 255))
      help.addOutput("  Wave Mode: Every 5th wave (5, 10, 15...)", White)
      help.addOutput("  Survival Mode: Every 60 seconds", White)
      help.addOutput("", White)
      help.addOutput("BOSS MECHANICS", Color(r: 255, g: 200, b: 50, a: 255))
      help.addOutput("  - Unique attack patterns", White)
      help.addOutput("  - Multiple phases as HP decreases", White)
      help.addOutput("  - Higher HP and damage than normal enemies", White)
      help.addOutput("  - Speed and damage increase with each phase", White)
      help.addOutput("", White)
      help.addOutput("BOSS ATTACKS", Color(r: 255, g: 200, b: 50, a: 255))
      help.addOutput("  - Spiral patterns", White)
      help.addOutput("  - Burst fire", White)
      help.addOutput("  - Wave patterns", White)
      help.addOutput("  - Targeted shots", White)
      help.addOutput("  - Circle formations", White)
      help.addOutput("  - Laser beams", White)
      help.addOutput("  - Orbiting projectiles", White)
      help.addOutput("  - Meteor strikes", White)
      help.addOutput("  - Chain lightning", White)
      help.addOutput("  - Expanding pulses", White)
      help.addOutput("  - Teleportation", White)
      help.addOutput("  - Minion summoning", White)
      help.addOutput("  - Dash attacks", White)
      help.addOutput("", White)
      help.addOutput("REWARDS", Color(r: 255, g: 200, b: 50, a: 255))
      help.addOutput("  - Large coin drops", White)
      help.addOutput("  - Legendary power-up selection", White)
      help.addOutput("", White)
    
    of "shop":
      help.addOutput("", White)
      help.addOutput("=======================================", Color(r: 255, g: 200, b: 50, a: 255))
      help.addOutput("  SHOP ITEMS", Color(r: 255, g: 200, b: 50, a: 255))
      help.addOutput("=======================================", Color(r: 255, g: 200, b: 50, a: 255))
      help.addOutput("", White)
      help.addOutput("AVAILABLE ITEMS", Color(r: 255, g: 200, b: 50, a: 255))
      help.addOutput("  Damage + (8 CR base)", White)
      help.addOutput("    Increase bullet damage", White)
      help.addOutput("", White)
      help.addOutput("  Fire Rate + (10 CR base)", White)
      help.addOutput("    Shoot faster", White)
      help.addOutput("", White)
      help.addOutput("  Move Speed + (7 CR base)", White)
      help.addOutput("    Move faster", White)
      help.addOutput("", White)
      help.addOutput("  Max Health + (10 CR base)", White)
      help.addOutput("    Increase maximum HP", White)
      help.addOutput("", White)
      help.addOutput("  Bullet Speed + (6 CR base)", White)
      help.addOutput("    Faster bullet velocity", White)
      help.addOutput("", White)
      help.addOutput("  Wall x5 (14 CR base)", White)
      help.addOutput("    Buy 5 deployable walls", White)
      help.addOutput("", White)
      help.addOutput("COST SCALING", Color(r: 255, g: 200, b: 50, a: 255))
      help.addOutput("  - Costs increase with each purchase", White)
      help.addOutput("  - Each buy: cost = baseCost * 1.45^bought", White)
      help.addOutput("", White)
      help.addOutput("EARNING COINS", Color(r: 255, g: 200, b: 50, a: 255))
      help.addOutput("  - Kill enemies to collect coins", White)
      help.addOutput("  - Elite enemies drop more coins", White)
      help.addOutput("  - Bosses drop large amounts", White)
      help.addOutput("", White)
      help.addOutput("SHOP ACCESS", Color(r: 255, g: 200, b: 50, a: 255))
      help.addOutput("  - Opens after power-up selection", White)
      help.addOutput("  - Available between waves", White)
      help.addOutput("", White)
    
    
    # Desktop icon execution commands
    of "play", "play.exe":
      help.addOutput("Launching Play.exe...", Color(r: 100, g: 200, b: 255, a: 255))
      help.pendingIconExecution = 0
    
    of "survival", "survival.exe":
      help.addOutput("Launching Survival.exe...", Color(r: 255, g: 150, b: 100, a: 255))
      help.pendingIconExecution = 1
    
    of "stats", "stats.exe", "statistics":
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
