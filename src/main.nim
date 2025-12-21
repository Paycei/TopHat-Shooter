import raylib, types, game, shop, wall, particle, powerup, player, coin, random, math, strutils, sound, settings, cheat, statistics, run_statistics, run_statistics_ui, settings_types, save_system

const
  screenWidth = 1024
  screenHeight = 768
  targetFPS = 60
  MOUSE_MOVEMENT_THRESHOLD = 2.0  # Minimum pixel movement to count as "mouse moved"

proc isMenuClickValid*(game: Game, settings: Settings, mousePos: Vector2f, buttonX: int32, buttonY: int32, buttonWidth: int32, buttonHeight: int32): bool =
  ## Helper function to validate mouse clicks in menus
  ## Returns true if mouse click is within button bounds and mouse support is enabled
  if not settings.mouseSupport or not game.mouseMovedRecently:
    return false
  return mousePos.x >= buttonX.float32 and mousePos.x <= (buttonX + buttonWidth).float32 and
         mousePos.y >= buttonY.float32 and mousePos.y <= (buttonY + buttonHeight).float32

proc hasMouseMoved*(game: Game): bool =
  ## Detects if mouse has actually moved (not just hovering)
  let currentPos = getMousePosition()
  let dx = abs(currentPos.x - game.lastMousePos.x)
  let dy = abs(currentPos.y - game.lastMousePos.y)
  result = (dx > MOUSE_MOVEMENT_THRESHOLD or dy > MOUSE_MOVEMENT_THRESHOLD)

proc updateMouseTracking*(game: Game) =
  ## Updates mouse position tracking and resets keyboard flag if mouse moved
  let currentPos = getMousePosition()
  if hasMouseMoved(game):
    game.mouseMovedRecently = true
    game.keyboardUsedRecently = false
  game.lastMousePos = newVector2f(currentPos.x, currentPos.y)

proc markKeyboardUsed*(game: Game) =
  ## Marks that keyboard was just used, disabling mouse selection temporarily
  game.keyboardUsedRecently = true
  game.mouseMovedRecently = false

proc drawCustomCursor*(time: float32) =
  ## Draw custom crosshair cursor (only when system cursor is hidden)
  let mousePos = getMousePosition()
  let cursorPulse = sin(time * 8.0) * 2 + 8
  
  # Outer rotating ring
  for i in 0..<8:
    let angle = time * 4.0 + i.float32 * PI / 4.0
    let x = mousePos.x + cos(angle) * cursorPulse
    let y = mousePos.y + sin(angle) * cursorPulse
    drawCircle(Vector2(x: x, y: y), 2, Color(r: 255'u8, g: 200'u8, b: 50'u8, a: 200'u8))
  
  # Crosshair lines
  drawLine(Vector2(x: mousePos.x - 8, y: mousePos.y), 
          Vector2(x: mousePos.x - 3, y: mousePos.y), 2, White)
  drawLine(Vector2(x: mousePos.x + 3, y: mousePos.y), 
          Vector2(x: mousePos.x + 8, y: mousePos.y), 2, White)
  drawLine(Vector2(x: mousePos.x, y: mousePos.y - 8), 
          Vector2(x: mousePos.x, y: mousePos.y - 3), 2, White)
  drawLine(Vector2(x: mousePos.x, y: mousePos.y + 3), 
          Vector2(x: mousePos.x, y: mousePos.y + 8), 2, White)
  
  # Center dot
  drawCircle(Vector2(x: mousePos.x, y: mousePos.y), 2, Red)

proc drawMenu(game: Game) =
  # Dark gradient background
  drawRectangleGradientV(0, 0, screenWidth, screenHeight, 
                         Color(r: 8, g: 10, b: 20, a: 255),
                         Color(r: 20, g: 12, b: 35, a: 255))
  
  # Animated starfield background
  for i in 0..<60:
    let offset = i.float32 * 1.2
    let speedFactor = 1.0 + (i mod 3).float32 * 0.5
    let x = ((game.time * 15.0 * speedFactor + offset * 30) mod (screenWidth.float32 + 100)).int32
    let y = ((offset * 15) mod screenHeight.float32).int32
    let size = 1 + (i mod 3)
    let twinkle = (sin(game.time * 4.0 + offset) * 0.5 + 0.5)
    let alpha = uint8(100 + twinkle * 155)
    drawCircle(Vector2(x: x.float32, y: y.float32), size.float32, 
               Color(r: 200'u8, g: 200'u8, b: 255'u8, a: alpha))
  
  # Large elemental particle swirls (background layer)
  for i in 0..<30:
    let offset = i.float32 * 0.9
    let angle = game.time * 0.3 + offset * 0.5
    let radius = 250.0 + sin(game.time * 0.8 + offset) * 80.0
    let x = screenWidth.float32 / 2 + cos(angle) * radius
    let y = 200.0 + sin(angle * 0.7) * radius * 0.6
    let size = 3 + (sin(game.time * 2.5 + offset) * 2).int32
    let pulse = sin(game.time * 3.0 + offset) * 0.4 + 0.6
    let alpha = uint8(30 + pulse * 40)
    
    # Elemental colors cycle
    let elementIndex = i mod 6
    var color: Color
    case elementIndex
    of 0: color = Color(r: 255'u8, g: 120'u8, b: 50'u8, a: alpha)   # Fire
    of 1: color = Color(r: 120'u8, g: 200'u8, b: 255'u8, a: alpha)  # Frost
    of 2: color = Color(r: 255'u8, g: 255'u8, b: 80'u8, a: alpha)   # Lightning
    of 3: color = Color(r: 100'u8, g: 255'u8, b: 150'u8, a: alpha)  # Poison
    of 4: color = Color(r: 200'u8, g: 100'u8, b: 255'u8, a: alpha)  # Arcane
    else: color = Color(r: 255'u8, g: 70'u8, b: 70'u8, a: alpha)    # Blood
    
    drawCircle(Vector2(x: x, y: y), size.float32, color)
    # Inner glow
    drawCircle(Vector2(x: x, y: y), (size.float32 * 0.5),
               Color(r: 255'u8, g: 255'u8, b: 255'u8, a: uint8(alpha div 3)))
  
  # Orbiting elemental orbs around title (mid layer)
  for i in 0..<6:
    let angle = game.time * 0.6 + i.float32 * PI / 3.0
    let radius = 200.0 + sin(game.time * 1.5 + i.float32) * 30.0
    let x = screenWidth.float32 / 2 + cos(angle) * radius
    let y = 160.0 + sin(angle) * radius * 0.4
    let size = 14 + (sin(game.time * 2.5 + i.float32) * 5).int32
    let pulse = sin(game.time * 3.0 + i.float32) * 0.3 + 0.7
    let alpha = uint8(80 + pulse * 120)
    
    # Assign elemental colors
    var orbColor: Color
    case i
    of 0: orbColor = Color(r: 255'u8, g: 130'u8, b: 50'u8, a: alpha)   # Fire
    of 1: orbColor = Color(r: 140'u8, g: 210'u8, b: 255'u8, a: alpha)  # Frost
    of 2: orbColor = Color(r: 255'u8, g: 255'u8, b: 100'u8, a: alpha)  # Lightning
    of 3: orbColor = Color(r: 110'u8, g: 255'u8, b: 110'u8, a: alpha)  # Poison
    of 4: orbColor = Color(r: 210'u8, g: 110'u8, b: 255'u8, a: alpha)  # Arcane
    else: orbColor = Color(r: 255'u8, g: 60'u8, b: 60'u8, a: alpha)    # Blood
    
    # Trail effect
    let trailAngle = angle - 0.15
    let trailX = screenWidth.float32 / 2 + cos(trailAngle) * radius
    let trailY = 160.0 + sin(trailAngle) * radius * 0.4
    drawCircle(Vector2(x: trailX, y: trailY), (size.float32 * 0.6),
               Color(r: orbColor.r, g: orbColor.g, b: orbColor.b, a: uint8(alpha div 3)))
    
    # Main orb with glow
    drawCircle(Vector2(x: x, y: y), size.float32, orbColor)
    drawCircle(Vector2(x: x, y: y), (size.float32 * 0.65),
               Color(r: 255'u8, g: 255'u8, b: 255'u8, a: uint8(alpha div 2)))
    drawCircle(Vector2(x: x, y: y), (size.float32 * 0.35),
               Color(r: 255'u8, g: 255'u8, b: 255'u8, a: 255'u8))
  
  # Title with elemental gradient effect
  let titleText = "TopHat SHOOTER"
  let baseY = 140
  let baseTitleSize = 60
  
  # Multi-layered glow with elemental colors
  drawText(titleText, screenWidth.int32 div 2 - 250, 142, baseTitleSize.int32 + 4,
          Color(r: 255'u8, g: 150'u8, b: 0'u8, a: 40'u8))
  drawText(titleText, screenWidth.int32 div 2 - 250, 143, baseTitleSize.int32 + 3,
          Color(r: 200'u8, g: 100'u8, b: 255'u8, a: 40'u8))
  
  # Main title with subtle per-character wave and elemental colors
  for i in 0..<titleText.len:
    let charWave = sin(game.time * 3.0 + i.float32 * 0.4) * 2.5
    let charX = screenWidth div 2 - 220 + i * 32
    let charY = baseY.float32 + charWave
    
    # Cycle through elemental colors for each character
    let colorIndex = (i + (game.time * 2.0).int) mod 6
    var charColor: Color
    case colorIndex
    of 0: charColor = Color(r: 255'u8, g: 200'u8, b: 50'u8, a: 255'u8)   # Lightning
    of 1: charColor = Color(r: 255'u8, g: 120'u8, b: 50'u8, a: 255'u8)   # Fire
    of 2: charColor = Color(r: 150'u8, g: 200'u8, b: 255'u8, a: 255'u8)  # Frost
    of 3: charColor = Color(r: 100'u8, g: 255'u8, b: 150'u8, a: 255'u8)  # Poison
    of 4: charColor = Color(r: 200'u8, g: 120'u8, b: 255'u8, a: 255'u8)  # Arcane
    else: charColor = Color(r: 255'u8, g: 100'u8, b: 100'u8, a: 255'u8)  # Blood
    
    drawText($titleText[i], charX.int32, charY.int32, baseTitleSize.int32, charColor)
  
  # Subtitle with pulsing elemental energy
  let subtitlePulse = 1.0 + sin(game.time * 3.0) * 0.08
  let subtitleSize = (32.float32 * subtitlePulse).int32
  let subtitleGlow = uint8(100 + sin(game.time * 4.0) * 50)
  
  drawText("ELEMENTAL UPDATE", screenWidth div 2 - 170, 212, subtitleSize + 2,
          Color(r: 160'u8, g: 90'u8, b: 230'u8, a: subtitleGlow))
  drawText("ELEMENTAL UPDATE", screenWidth div 2 - 170, 210, subtitleSize,
          Color(r: 255'u8, g: 180'u8, b: 100'u8, a: 255'u8))
  
  # Version badge with animated elemental border
  let versionX = screenWidth div 2 - 52.5
  let versionY = 260
  let versionPulse = 1.0 + sin(game.time * 5.0) * 0.12
  let versionSize = (26.float32 * versionPulse).int32
  
  # Rotating elemental ring around version
  for i in 0..<8:
    let ringAngle = game.time * 4.0 + i.float32 * PI / 4.0
    let ringX = versionX.float32 + 50 + cos(ringAngle) * 45
    let ringY = versionY.float32 + 13 + sin(ringAngle) * 20
    let ringColorIndex = i mod 6
    var ringColor: Color
    case ringColorIndex
    of 0: ringColor = Color(r: 255'u8, g: 200'u8, b: 50'u8, a: 150'u8)
    of 1: ringColor = Color(r: 255'u8, g: 100'u8, b: 50'u8, a: 150'u8)
    of 2: ringColor = Color(r: 150'u8, g: 200'u8, b: 255'u8, a: 150'u8)
    of 3: ringColor = Color(r: 100'u8, g: 255'u8, b: 100'u8, a: 150'u8)
    of 4: ringColor = Color(r: 200'u8, g: 100'u8, b: 255'u8, a: 150'u8)
    else: ringColor = Color(r: 255'u8, g: 50'u8, b: 50'u8, a: 150'u8)
    drawCircle(Vector2(x: ringX, y: ringY), 3, ringColor)
  
  drawText("v4.1", int32(versionX + 27.5), int32(versionY), versionSize,
          Color(r: 255'u8, g: 220'u8, b: 100'u8, a: 255'u8))
  
  # Menu options with subtle selection indicator
  let startY = 360
  let spacing = 65
  
  let menuItems = ["Play", "Survival Mode", "Statistics", "Settings", "Help", "Quit"]
  
  # Mouse hover detection (ONLY if mouse moved recently AND mouse support enabled AND keyboard NOT used recently)
  if globalSettings.mouseSupport and game.mouseMovedRecently and not game.keyboardUsedRecently:
    let mousePos = getMousePosition()
    for i in 0..<menuItems.len:
      let y = startY + i * spacing
      let text = if i == game.menuSelection: "> " & menuItems[i] & " <" else: menuItems[i]
      let textWidth = measureText(text, 32)
      let textX = screenWidth div 2 - textWidth div 2
      
      # Check if mouse is hovering over this menu item
      if mousePos.x >= textX.float32 and mousePos.x <= (textX + textWidth).float32 and
         mousePos.y >= y.float32 and mousePos.y <= (y + 32).float32:
        game.menuSelection = i
  
  for i in 0..<menuItems.len:
    let y = startY + i * spacing
    let isSelected = i == game.menuSelection
    
    # Simple selection glow
    if isSelected:
      let glowPulse = sin(game.time * 6.0) * 0.3 + 0.7
      let glowSize = 18 + (glowPulse * 8).int32
      drawCircle(Vector2(x: (screenWidth div 2).float32, y: y.float32 + 15),
                glowSize.float32, Color(r: 255'u8, g: 200'u8, b: 0'u8, a: 100'u8))
    
    let color = if isSelected: Gold else: White
    let text = if isSelected: "> " & menuItems[i] & " <" else: menuItems[i]
    let textWidth = measureText(text, 32)
    
    drawText(text, screenWidth div 2 - textWidth div 2, y.int32, 32, color)
  
  # Draw custom cursor (only if mouseSupport is enabled OR showCursorInMenus is enabled)
  if globalSettings.mouseSupport or globalSettings.showCursorInMenus:
    drawCustomCursor(game.time)

proc drawHelp(game: Game) =
  clearBackground(Color(r: 20, g: 20, b: 30, a: 255))
  
  drawText("HOW TO PLAY", screenWidth div 2 - 130, 50, 40, Yellow)
  
  var y: int32 = 130
  let instructions = [
    "CONTROLS:",
    "WASD - Move / Menu Navigation",
    "Mouse/Space - Shoot",
    "F - Toggle Auto-Shoot (requires powerup)",
    "E - Place Wall (requires walls in inventory)",
    "Q - Activate Legendary Power-Ups",
    "ESC - Pause/Menu",
    "",
    "WAVE-BASED MODE (Main):",
    "Clear waves of enemies for upgrades",
    "Defeat all enemies to advance waves",
    "Boss appears every 5 waves",
    "Choose power-ups after waves (every 2nd wave)",
    "Shop opens after selecting powerup",
    "Legendary upgrades after boss defeats",
    "",
    "SURVIVAL MODE (Classic):",
    "Survive endless enemy hordes",
    "Enemies spawn progressively harder",
    "Boss appears every 60 seconds",
  ]
  
  for line in instructions:
    if line.len > 0:
      drawText(line, 120, y, 18, White)
    y += 22
  
  drawText("Press ESC to return", screenWidth div 2 - 130, screenHeight - 60, 20, LightGray)
  
  # Draw custom cursor (only if mouseSupport is enabled OR showCursorInMenus is enabled)
  if globalSettings.mouseSupport or globalSettings.showCursorInMenus:
    drawCustomCursor(game.time)

proc drawStatistics(game: Game, stats: Statistics) =
  clearBackground(Color(r: 20, g: 20, b: 30, a: 255))
  
  # Title
  drawText("STATISTICS", screenWidth div 2 - 120, 40, 40, Yellow)
  
  # Tab buttons
  let tab1X = screenWidth div 2 - 260
  let tab2X = screenWidth div 2 - 80
  let tab3X = screenWidth div 2 + 100
  let tabY = 95
  let tabWidth = 160
  let tabHeight = 35
  
  # Tab 1: Lifetime Stats
  let tab1Color = if game.statsMenuTab == 0: Gold else: Color(r: 100, g: 100, b: 120, a: 255)
  let tab1BgColor = if game.statsMenuTab == 0: Color(r: 60, g: 60, b: 70, a: 255) else: Color(r: 40, g: 40, b: 50, a: 255)
  drawRectangle(int32(tab1X), int32(tabY), int32(tabWidth), int32(tabHeight), tab1BgColor)
  drawRectangleLines(Rectangle(x: tab1X.float32, y: tabY.float32, width: tabWidth.float32, height: tabHeight.float32), 2, tab1Color)
  drawText("1. LIFETIME", int32(tab1X) + 15, int32(tabY) + 8, 18, tab1Color)
  
  # Tab 2: Last Run Stats
  let hasLastRun = hasLastRunStats()
  let tab2Color = if game.statsMenuTab == 1: 
                    (if hasLastRun: Gold else: Color(r: 80, g: 80, b: 80, a: 255))
                  else: 
                    (if hasLastRun: Color(r: 100, g: 100, b: 120, a: 255) else: Color(r: 60, g: 60, b: 60, a: 255))
  let tab2BgColor = if game.statsMenuTab == 1: Color(r: 60, g: 60, b: 70, a: 255) else: Color(r: 40, g: 40, b: 50, a: 255)
  drawRectangle(int32(tab2X), int32(tabY), int32(tabWidth), int32(tabHeight), tab2BgColor)
  drawRectangleLines(Rectangle(x: tab2X.float32, y: tabY.float32, width: tabWidth.float32, height: tabHeight.float32), 2, tab2Color)
  drawText("2. LAST RUN", int32(tab2X) + 15, int32(tabY) + 8, 18, tab2Color)
  
  # Tab 3: Power-ups
  let tab3Color = if game.statsMenuTab == 2:
                    (if hasLastRun: Gold else: Color(r: 80, g: 80, b: 80, a: 255))
                  else:
                    (if hasLastRun: Color(r: 100, g: 100, b: 120, a: 255) else: Color(r: 60, g: 60, b: 60, a: 255))
  let tab3BgColor = if game.statsMenuTab == 2: Color(r: 60, g: 60, b: 70, a: 255) else: Color(r: 40, g: 40, b: 50, a: 255)
  drawRectangle(int32(tab3X), int32(tabY), int32(tabWidth), int32(tabHeight), tab3BgColor)
  drawRectangleLines(Rectangle(x: tab3X.float32, y: tabY.float32, width: tabWidth.float32, height: tabHeight.float32), 2, tab3Color)
  drawText("3. POWER-UPS", int32(tab3X) + 10, int32(tabY) + 8, 18, tab3Color)
  
  # Content area starts below tabs
  let contentY: int32 = 150
  
  if game.statsMenuTab == 0:
    # === LIFETIME STATISTICS ===
    var y: int32 = contentY
    drawText("OVERALL", 100, y, 28, Gold)
    y += 35
    drawText("Total Games: " & $stats.totalGamesPlayed, 100, y, 20, White)
    y += 25
    drawText("Total Playtime: " & formatTime(stats.totalPlayTime), 100, y, 20, White)
    y += 35
    
    # Wave Mode stats
    drawText("WAVE MODE", 100, y, 28, Color(r: 100, g: 200, b: 255, a: 255))
    y += 35
    drawText("Games Played: " & $stats.waveMode.gamesPlayed, 120, y, 18, White)
    y += 23
    drawText("Highest Wave: " & $stats.waveMode.highestWaveReached, 120, y, 18, White)
    y += 23
    drawText("Avg Wave Reached: " & formatFloat(stats.waveMode.averageWaveReached, ffDecimal, 1), 120, y, 18, White)
    y += 23
    drawText("Best Kills: " & $stats.waveMode.bestKills, 120, y, 18, White)
    y += 23
    drawText("Best Coins: " & $stats.waveMode.bestCoins, 120, y, 18, Gold)
    y += 23
    drawText("Total Kills: " & $stats.waveMode.totalKills, 120, y, 18, White)
    y += 23
    drawText("Bosses Defeated: " & $stats.waveMode.bossesDefeated, 120, y, 18, Red)
    y += 23
    drawText("Playtime: " & formatTime(stats.waveMode.totalTimePlayed), 120, y, 18, White)
    y += 35
    
    # Time Survival Mode stats
    drawText("TIME SURVIVAL MODE", 100, y, 28, Color(r: 255, g: 150, b: 100, a: 255))
    y += 35
    drawText("Games Played: " & $stats.timeMode.gamesPlayed, 120, y, 18, White)
    y += 23
    drawText("Longest Survival: " & formatTime(stats.timeMode.longestSurvivalTime), 120, y, 18, White)
    y += 23
    drawText("Avg Survival: " & formatTime(stats.timeMode.averageSurvivalTime), 120, y, 18, White)
    y += 23
    drawText("Best Kills: " & $stats.timeMode.bestKills, 120, y, 18, White)
    y += 23
    drawText("Best Coins: " & $stats.timeMode.bestCoins, 120, y, 18, Gold)
    y += 23
    drawText("Total Kills: " & $stats.timeMode.totalKills, 120, y, 18, White)
    y += 23
    drawText("Bosses Defeated: " & $stats.timeMode.bossesDefeated, 120, y, 18, Red)
  
  elif game.statsMenuTab == 1:
    # === LAST RUN STATISTICS ===
    if hasLastRun:
      let runStats = getLastRunStats()
      # Use the full run statistics screen but in compact form
      drawRunStatisticsScreen(runStats, screenWidth, screenHeight, game.time, true)
    else:
      # No last run available
      drawText("No previous run statistics available", 
              screenWidth div 2 - 220, screenHeight div 2 - 40, 20, Color(r: 150, g: 150, b: 150, a: 255))
      drawText("Complete a game to see detailed run statistics here", 
              screenWidth div 2 - 260, screenHeight div 2, 18, Color(r: 120, g: 120, b: 120, a: 255))
  
  elif game.statsMenuTab == 2:
    # === POWER-UP BREAKDOWN ===
    if hasLastRun:
      let runStats = getLastRunStats()
      drawDetailedPowerUpScreen(runStats.powerUps, runStats.combat, 
                               screenWidth, screenHeight, game.time)
    else:
      # No last run available
      drawText("No power-up statistics available", 
              screenWidth div 2 - 220, screenHeight div 2 - 40, 20, Color(r: 150, g: 150, b: 150, a: 255))
      drawText("Complete a game to see power-up breakdown here", 
              screenWidth div 2 - 260, screenHeight div 2, 18, Color(r: 120, g: 120, b: 120, a: 255))
  
  # Footer instructions
  let footerText = if hasLastRun: 
                     "Press 1 for Lifetime | 2 for Last Run | 3 for Power-Ups | ESC to return"
                   else:
                     "Press 1 for Lifetime | ESC to return"
  drawText(footerText, screenWidth div 2 - 330, screenHeight - 60, 20, LightGray)
  
  # Draw custom cursor (only if mouseSupport is enabled OR showCursorInMenus is enabled)
  if globalSettings.mouseSupport or globalSettings.showCursorInMenus:
    drawCustomCursor(game.time)


proc main() =
  randomize()
  
  initWindow(screenWidth, screenHeight, "TopHat-Shooter: Elemental Edition")
  setTargetFPS(targetFPS)
  setExitKey(Null)
  hideCursor()  # Hide default cursor for custom cursor
  
  # Initialize sound system
  discard initSoundSystem()
  
  # Initialize cheat menu
  let cheatMenu = initCheatMenu()
  
  # Initialize settings
  let settings = initSettings()
  applySettings(settings)
  
  # Apply fullscreen setting if it was saved
  if settings.fullscreen:
    toggleFullscreen()
  
  # Initialize and load statistics
  let stats = initStatistics()
  discard loadStatistics(stats)
  
  # Load last completed run statistics
  let loadedRunStats = loadLastRunStats()
  if not loadedRunStats.isNil:
    loadLastCompletedRun(loadedRunStats)
  
  var statsSavedThisGame = false  # Track if stats were saved for current game
  
  var currentGame = newGame(screenWidth, screenHeight)
  currentGame.state = gsMenu
  
  while not windowShouldClose():
    let dt = getFrameTime()
    
    # Update music stream (required for continuous playback)
    updateMusic()
    
    # Handle fullscreen toggle with F11
    if isKeyPressed(F11):
      settings.fullscreen = not settings.fullscreen
      toggleFullscreen()
    
    # ALWAYS hide system cursor - we always use custom cursor
    hideCursor()
    
    case currentGame.state
    of gsMenu:
      # Play menu music
      playMusic(mtMenu)
      
      # Update time for menu animations
      currentGame.time += dt
      
      # Update mouse tracking
      updateMouseTracking(currentGame)
      
      # Menu navigation - keyboard has priority
      if isKeyPressed(Down) or isKeyPressed(S):
        currentGame.menuSelection = (currentGame.menuSelection + 1) mod 6
        playSound(stMenuNav)
        markKeyboardUsed(currentGame)
      if isKeyPressed(Up) or isKeyPressed(W):
        currentGame.menuSelection = (currentGame.menuSelection - 1 + 6) mod 6
        playSound(stMenuNav)
        markKeyboardUsed(currentGame)
      
      if isKeyPressed(Enter) or isKeyPressed(E) or isMouseButtonPressed(Left):
        # For mouse clicks, verify we're clicking on a menu item (only if mouse support enabled AND mouse moved recently)
        var validClick = isKeyPressed(Enter) or isKeyPressed(E)
        if not validClick and isMouseButtonPressed(Left):
          let mousePos = getMousePosition()
          let startY = 360
          let spacing = 65
          let menuItems = ["Play", "Survival Mode", "Statistics", "Settings", "Help", "Quit"]
          
          for i in 0..<menuItems.len:
            let y = startY + i * spacing
            let text = if i == currentGame.menuSelection: "> " & menuItems[i] & " <" else: menuItems[i]
            let textWidth = measureText(text, 32)
            let textX = screenWidth div 2 - textWidth div 2
            
            if isMenuClickValid(currentGame, settings, Vector2f(x: mousePos.x, y: mousePos.y), textX, int32(y), textWidth, int32(32)):
              validClick = true
              break
        
        if validClick:
          playSound(stMenuSelect)
          case currentGame.menuSelection
          of 0:  # Wave-Based Mode
            currentGame = newGame(screenWidth, screenHeight)
            currentGame.mode = gmWaveBased
            initializeRunTracking(currentGame)  # Start tracking
            currentGame.state = gsPlaying  # Start playing immediately
            statsSavedThisGame = false  # Reset for new game
          of 1:  # Time Survival Mode
            currentGame = newGame(screenWidth, screenHeight)
            currentGame.mode = gmTimeSurvival
            initializeRunTracking(currentGame)  # Start tracking
            currentGame.state = gsPlaying  # Start playing immediately
            statsSavedThisGame = false  # Reset for new game
          of 2:  # Statistics
            currentGame.state = gsStatistics
          of 3:  # Settings
            currentGame.previousState = gsMenu
            currentGame.state = gsSettings
          of 4:  # Help
            currentGame.state = gsHelp
          of 5:  # Quit
            break
          else: discard
      
      beginDrawing()
      drawMenu(currentGame)
      endDrawing()
    
    of gsHelp:
      # Keep menu music playing during help screen
      playMusic(mtMenu)
      
      if isKeyPressed(Escape):
        currentGame.state = gsMenu
      
      beginDrawing()
      drawHelp(currentGame)
      endDrawing()
    
    of gsSettings:
      # Keep menu music playing during settings
      playMusic(mtMenu)
      
      if isKeyPressed(Escape):
        currentGame.state = currentGame.previousState  # Return to where we came from
        setGameVolume(settings.volume)  # Apply volume changes
        setMusicVolume(settings.musicVolume)  # Apply music volume changes
        playSound(stMenuSelect)
      
      updateSettings(settings)
      
      beginDrawing()
      drawSettings(settings, screenWidth, screenHeight, currentGame.time)
      endDrawing()
    
    of gsStatistics:
      # Keep menu music playing during statistics screen
      playMusic(mtMenu)
      
      # Update time for animations
      currentGame.time += dt
      
      # Tab switching: 1 = Lifetime, 2 = Last Run, 3 = Power-Ups
      if isKeyPressed(One):
        currentGame.statsMenuTab = 0
      if isKeyPressed(Two):
        currentGame.statsMenuTab = 1
      if isKeyPressed(Three):
        currentGame.statsMenuTab = 2
      
      if isKeyPressed(Escape):
        currentGame.state = gsMenu
      
      beginDrawing()
      drawStatistics(currentGame, stats)
      endDrawing()

    of gsPlaying:
      # Dynamic music based on game state
      if currentGame.bossActive:
        playMusic(mtBoss)
      else:
        playMusic(mtWave)
      
      # Check for cheat menu activation
      checkCheatSequence(cheatMenu, currentGame, currentGame.time)
      
      # Update cheat menu if active (pauses game)
      if cheatMenu.active:
        updateCheatMenu(cheatMenu, currentGame)
      
      # Only process game input if cheat menu is not active
      if not cheatMenu.active:
        # Shop removed from gameplay - only accessible during power-up selection
        
        # Place wall
        if isKeyPressed(E) and currentGame.player.walls > 0:
          let mousePos = getMousePosition()
          let wallPos = newVector2f(mousePos.x, mousePos.y)

          if isValidWallPlacement(wallPos, currentGame.player.pos, currentGame.walls, 
                                  currentGame.enemies, 25):
            currentGame.walls.add(newWall(mousePos.x, mousePos.y, currentGame.player))
            currentGame.player.walls -= 1
            spawnExplosion(currentGame.particles, mousePos.x, mousePos.y, Brown, 15)
            trackWallPlacement(currentGame, wallPos)

      # Toggle auto-shoot with F key
      if isKeyPressed(F) and hasPowerUp(currentGame.player, puAutoShoot):
        currentGame.player.autoShootEnabled = not currentGame.player.autoShootEnabled
        let feedbackColor = if currentGame.player.autoShootEnabled: Green else: Red
        spawnExplosion(currentGame.particles, currentGame.player.pos.x, currentGame.player.pos.y, 
                      feedbackColor, 20)
      
      # Activate ALL legendary power-ups with Q key (simultaneous activation)
      if isKeyPressed(Q):
        var anyActivated = false
        
        # Time Warp - slow down time (3 LEVELS - adds +1 use per wave)
        if hasPowerUp(currentGame.player, puTimeWarp) and currentGame.player.timeWarpCooldown <= 0:
          # Check if uses available for this wave
          if currentGame.player.timeWarpUsesThisWave < currentGame.player.timeWarpMaxUsesPerWave:
            let duration = 3.5
            let cooldown = 20.0  # 20 second cooldown between uses
            
            currentGame.player.timeWarpActive = true
            currentGame.player.timeWarpDuration = duration
            currentGame.player.timeWarpCooldown = cooldown
            currentGame.player.timeWarpUsesThisWave += 1  # Increment uses
            spawnExplosion(currentGame.particles, currentGame.player.pos.x, currentGame.player.pos.y, 
                          Color(r: 138, g: 43, b: 226, a: 255), 30)
            anyActivated = true
        
        # Phase Shift - teleport dash (SINGLE LEVEL - scales with speed)
        if hasPowerUp(currentGame.player, puPhaseShift) and currentGame.player.phaseShiftCooldown <= 0:
          # Distance scales with player movement speed (base 140, scales up with speed)
          let baseDistance = 140.0
          let speedRatio = currentGame.player.speed / currentGame.player.baseSpeed
          let dashDistance = baseDistance * speedRatio
          
          let cooldown = 5.0  # 5 second cooldown
          let invulnDuration = 0.5  # 0.5 second invulnerability after dash
          
          # Calculate dash direction - PRIORITIZE WASD movement direction
          var dashDir = newVector2f(0, 0)
          if isKeyDown(W): dashDir.y -= 1
          if isKeyDown(S): dashDir.y += 1
          if isKeyDown(A): dashDir.x -= 1
          if isKeyDown(D): dashDir.x += 1
          
          # Always activate cooldown and invulnerability
          currentGame.player.phaseShiftCooldown = cooldown
          currentGame.player.phaseShiftInvulnTimer = invulnDuration
          
          if dashDir.length() > 0:
            # Dash in movement direction
            dashDir = dashDir.normalize()
            currentGame.player.lastPhaseShiftPos = currentGame.player.pos
            currentGame.player.pos.x += dashDir.x * dashDistance
            currentGame.player.pos.y += dashDir.y * dashDistance
            
            # Keep player in bounds
            currentGame.player.pos.x = max(currentGame.player.radius, 
                                           min(currentGame.player.pos.x, 
                                               currentGame.screenWidth.float32 - currentGame.player.radius))
            currentGame.player.pos.y = max(currentGame.player.radius, 
                                           min(currentGame.player.pos.y, 
                                               currentGame.screenHeight.float32 - currentGame.player.radius))
            
            # Visual effects at start and end position
            spawnExplosion(currentGame.particles, currentGame.player.lastPhaseShiftPos.x, 
                          currentGame.player.lastPhaseShiftPos.y, SkyBlue, 25)
            spawnExplosion(currentGame.particles, currentGame.player.pos.x, 
                          currentGame.player.pos.y, SkyBlue, 25)
          else:
            # Dash in place - just visual effect
            spawnExplosion(currentGame.particles, currentGame.player.pos.x, 
                          currentGame.player.pos.y, SkyBlue, 30)
          
          anyActivated = true
        
        # Parry - active defense ability (SINGLE LEVEL - invincible + bounce bullets)
        if hasPowerUp(currentGame.player, puParry) and currentGame.player.parryCooldown <= 0:
          let duration = 0.5  # 0.5 second parry window
          let cooldown = 5.0  # 5 second cooldown
          
          currentGame.player.parryActive = true
          currentGame.player.parryDuration = duration
          currentGame.player.parryCooldown = cooldown
          
          spawnExplosion(currentGame.particles, currentGame.player.pos.x, currentGame.player.pos.y, 
                        Color(r: 255, g: 255, b: 255, a: 255), 35)
          anyActivated = true
        
        # Play sound if any ability was activated
        if anyActivated:
          playSound(stPowerUp)
      
      # Pause
      if isKeyPressed(Escape):
        currentGame.state = gsPaused
      
      # Update game (only if cheat menu is not active)
      if not cheatMenu.active:
        updateGame(currentGame, dt)
      
      beginDrawing()
      drawGame(currentGame)
      
      # Draw cheat menu overlay if active
      drawCheatMenu(cheatMenu, currentGame, screenWidth, screenHeight)
      
      endDrawing()
    
    of gsPaused:
      # Keep current music playing but muted or paused
      # Music continues in background during pause
      
      # Update time for animations even when paused
      currentGame.time += dt
      
      # Update mouse tracking
      updateMouseTracking(currentGame)
      
      # Pause menu navigation - keyboard has priority
      if isKeyPressed(Down) or isKeyPressed(S):
        currentGame.menuSelection = (currentGame.menuSelection + 1) mod 3
        playSound(stMenuNav)
        markKeyboardUsed(currentGame)
      if isKeyPressed(Up) or isKeyPressed(W):
        currentGame.menuSelection = (currentGame.menuSelection - 1 + 3) mod 3
        playSound(stMenuNav)
        markKeyboardUsed(currentGame)
      
      # Mouse hover detection (ONLY if mouse moved recently AND mouse support enabled AND keyboard NOT used recently)
      if globalSettings.mouseSupport and currentGame.mouseMovedRecently and not currentGame.keyboardUsedRecently:
        let mousePos = getMousePosition()
        let pauseOptions = ["Resume", "Settings", "Main Menu"]
        let optionStartY = screenHeight div 2 + 20
        let optionSpacing = 60
        
        for i in 0..<pauseOptions.len:
          let y = optionStartY + i * optionSpacing
          let text = if i == currentGame.menuSelection: "> " & pauseOptions[i] & " <" else: pauseOptions[i]
          let textWidth = measureText(text, 32)
          let textX = screenWidth div 2 - textWidth div 2
          
          # Check if mouse is hovering over this menu item
          if mousePos.x >= textX.float32 and mousePos.x <= (textX + textWidth).float32 and
             mousePos.y >= y.float32 and mousePos.y <= (y + 32).float32:
            currentGame.menuSelection = i
      
      # Select pause menu option
      if isKeyPressed(Enter) or isKeyPressed(E) or isMouseButtonPressed(Left):
        # For mouse clicks, verify we're clicking on a menu item (only if mouse support enabled AND mouse moved recently)
        var validClick = isKeyPressed(Enter) or isKeyPressed(E)
        if not validClick and isMouseButtonPressed(Left):
          let mousePos = getMousePosition()
          let pauseOptions = ["Resume", "Settings", "Main Menu"]
          let optionStartY = screenHeight div 2 + 20
          let optionSpacing = 60
          
          for i in 0..<pauseOptions.len:
            let y = optionStartY + i * optionSpacing
            let text = if i == currentGame.menuSelection: "> " & pauseOptions[i] & " <" else: pauseOptions[i]
            let textWidth = measureText(text, 32)
            let textX = screenWidth div 2 - textWidth div 2
            
            if isMenuClickValid(currentGame, globalSettings, Vector2f(x: mousePos.x, y: mousePos.y), textX, int32(y), textWidth, int32(32)):
              validClick = true
              break
        
        if validClick:
          playSound(stMenuSelect)
          case currentGame.menuSelection
          of 0:  # Resume
            currentGame.state = gsPlaying
          of 1:  # Settings
            currentGame.previousState = gsPaused
            currentGame.state = gsSettings
          of 2:  # Main Menu
            currentGame = newGame(screenWidth, screenHeight)
            currentGame.state = gsMenu
          else: discard
      
      # Also allow ESC to resume
      if isKeyPressed(Escape):
        currentGame.state = gsPlaying
      
      beginDrawing()
      drawGame(currentGame)
      
      # Draw pause overlay
      drawRectangle(0, 0, screenWidth, screenHeight, Color(r: 0, g: 0, b: 0, a: 150))
      drawText("PAUSED", screenWidth div 2 - 100, screenHeight div 2 - 80, 50, White)
      
      # Draw pause menu options
      let pauseOptions = ["Resume", "Settings", "Main Menu"]
      let optionStartY = screenHeight div 2 + 20
      let optionSpacing = 60
      
      for i in 0..<pauseOptions.len:
        let y = optionStartY + i * optionSpacing
        let isSelected = i == currentGame.menuSelection
        
        # Selection glow
        if isSelected:
          let glowPulse = sin(currentGame.time * 6.0) * 0.3 + 0.7
          let glowSize = 18 + (glowPulse * 8).int32
          drawCircle(Vector2(x: (screenWidth div 2).float32, y: y.float32 + 15),
                    glowSize.float32, Color(r: 255'u8, g: 200'u8, b: 0'u8, a: 100'u8))
        
        let color = if isSelected: Gold else: White
        let text = if isSelected: "> " & pauseOptions[i] & " <" else: pauseOptions[i]
        let textWidth = measureText(text, 32)
        drawText(text, screenWidth div 2 - textWidth div 2, y.int32, 32, color)
      
      # Draw instructions
      drawText("Press ESC to resume", screenWidth div 2 - 130, screenHeight - 60, 20, LightGray)
      
      # Draw custom cursor (only if mouseSupport is enabled OR showCursorInMenus is enabled)
      if globalSettings.mouseSupport or globalSettings.showCursorInMenus:
        drawCustomCursor(currentGame.time)
      
      endDrawing()
    
    of gsShop:
      # Play power-up music in shop
      playMusic(mtPowerUp)
      
      # Update mouse tracking
      updateMouseTracking(currentGame)
      
      # Navigate shop with keyboard
      if isKeyPressed(Down) or isKeyPressed(S):
        currentGame.selectedShopItem = (currentGame.selectedShopItem + 1) mod 6
        markKeyboardUsed(currentGame)
      if isKeyPressed(Up) or isKeyPressed(W):
        currentGame.selectedShopItem = (currentGame.selectedShopItem - 1 + 6) mod 6
        markKeyboardUsed(currentGame)
      
      # Buy item with keyboard or mouse
      if isKeyPressed(Enter) or isKeyPressed(E) or isMouseButtonPressed(Left):
        # For mouse clicks, verify we're clicking on a shop item (only if mouse support enabled AND mouse moved recently)
        var validClick = isKeyPressed(Enter) or isKeyPressed(E)
        if not validClick and isMouseButtonPressed(Left):
          let mousePos = getMousePosition()
          let shopStartX = currentGame.screenWidth div 2 - 200
          let startY = 120
          let itemHeight = 70
          
          for i in 0..5:
            let y = startY + i * itemHeight
            if isMenuClickValid(currentGame, settings, Vector2f(x: mousePos.x, y: mousePos.y), shopStartX, int32(y), 400, 60):
              validClick = true
              break
        
        if validClick:
          buyShopItem(currentGame, currentGame.selectedShopItem)
      
      # Close shop - always continue to next wave (no going back to power-up selection)
      if isKeyPressed(Escape) or isKeyPressed(Q):
        currentGame.cameFromPowerUpSelect = false
        currentGame.state = gsCountdown
        currentGame.countdownTimer = 0.5
      
      beginDrawing()
      drawGame(currentGame)
      drawShop(currentGame)
      endDrawing()
    
    of gsCountdown:
      # Keep wave music during countdown
      playMusic(mtWave)
      
      # Countdown timer
      currentGame.countdownTimer -= dt
      
      if currentGame.countdownTimer <= 0:
        currentGame.state = gsPlaying
      
      beginDrawing()
      drawGame(currentGame)
      
      # Draw stylish countdown overlay
      let countdownValue = max(currentGame.countdownTimer, 0.0)
      let pulse = 1.0 + sin(currentGame.countdownTimer * 10) * 0.1
      let alpha = uint8(200.0 * (countdownValue + 0.1))
      
      # Dark overlay that fades out
      drawRectangle(0, 0, screenWidth, screenHeight, 
                   Color(r: 0, g: 0, b: 0, a: alpha))
      
      # Countdown text with scale pulse
      let textSize = (120 * pulse).int32
      # Always show numeric countdown
      let countdownText = formatFloat(countdownValue, ffDecimal, 1)
      let textWidth = measureText(countdownText, textSize)
      
      # Glow effect - draw multiple times with offset
      for i in 1..3:
        let glowAlpha = uint8(50.0 * (4 - i).float)
        let glowSize = textSize + i * 4
        let glowWidth = measureText(countdownText, glowSize.int32)
        drawText(countdownText,
                (screenWidth div 2 - glowWidth div 2).int32,
                (screenHeight div 2 - glowSize div 2).int32,
                glowSize.int32,
                Color(r: 255, g: 200, b: 0, a: glowAlpha))
      
      # Main text
      let textColor = if countdownValue > 0.5:
        Color(r: 255, g: 255, b: 100, a: 255)
      else:
        Color(r: 100, g: 255, b: 100, a: 255)
      
      drawText(countdownText,
              screenWidth div 2 - textWidth div 2,
              screenHeight div 2 - textSize div 2,
              textSize,
              textColor)
      
      # Subtitle
      let subtitle = "READY?"
      let subWidth = measureText(subtitle, 40)
      drawText(subtitle,
              screenWidth div 2 - subWidth div 2,
              screenHeight div 2 + 80,
              40,
              Color(r: 255, g: 255, b: 100, a: alpha))
      
      endDrawing()
    
    of gsWaveCleared:
      # Keep wave music during wave cleared screen
      playMusic(mtWave)
      
      # Update wave cleared timer
      currentGame.waveClearedTimer -= dt
      
      # Continue coin collection during this phase
      updatePlayer(currentGame.player, dt, screenWidth, screenHeight, currentGame.walls)
      
      # Update coins and handle collection
      var i = 0
      while i < currentGame.coins.len:
        if not updateCoin(currentGame.coins[i], dt, currentGame.coins.len):
          currentGame.coins.delete(i)
          continue
        
        # Check if coin is in player's collection aura (auto-collect)
        if checkAuraCollision(currentGame.coins[i], currentGame.player, currentGame.player.auraRadius):
          moveCoinToPlayer(currentGame.coins[i], currentGame.player.pos, dt)
        
        # Enhanced magnet effect from consumable
        if currentGame.player.magnetTimer > 0:
          moveCoinToPlayer(currentGame.coins[i], currentGame.player.pos, dt)
        
        # Collect coin on contact
        if checkPlayerCollision(currentGame.coins[i], currentGame.player):
          # Apply Lucky Coins (Greed) multiplier - doubles coins collected
          let coinValue = if hasPowerUp(currentGame.player, puLuckyCoins):
            currentGame.coins[i].value * 2
          else:
            currentGame.coins[i].value
          currentGame.player.coins += coinValue
          playSound(stCoinPickup, 0.5)
          spawnExplosion(currentGame.particles, currentGame.coins[i].pos.x, currentGame.coins[i].pos.y, Gold, 6)
          currentGame.coins.delete(i)
          continue
        
        i += 1
      
      # Update particles and remove dead ones
      var pi = 0
      while pi < currentGame.particles.len:
        if not updateParticle(currentGame.particles[pi], dt):
          currentGame.particles.delete(pi)
        else:
          pi += 1
      
      # Transition to power-up selection or next wave
      if currentGame.waveClearedTimer <= 0:
        let shouldOfferPowerUp = currentGame.cameFromPowerUpSelect
        
        if shouldOfferPowerUp and not currentGame.bossCoinActive:
          # Determine if it's a boss wave power-up
          let isBossWave = currentGame.wavesUntilBoss <= 0
          
          if isBossWave:
            # Trigger boss warning
            currentGame.bossSpawnTimer = 1.5
            # ALWAYS offer power-up before boss (critical moment)
            currentGame.powerUpChoices = generatePowerUpChoices(currentGame.player, false)
          else:
            # Regular wave power-up
            currentGame.powerUpChoices = generatePowerUpChoices(currentGame.player, false)
          
          currentGame.selectedPowerUp = 0
          initPowerUpRollAnimation(currentGame)
          currentGame.state = gsPowerUpSelect
        else:
          # No power-up, go straight to next wave
          currentGame.state = gsPlaying
          startWave(currentGame)
      
      beginDrawing()
      drawGame(currentGame)
      
      # Draw "WAVE CLEARED!" text (static, no pulsing)
      let waveText = "WAVE CLEARED!"
      let waveTextSize = 48.int32
      let waveTextWidth = measureText(waveText, waveTextSize)
      
      # Simple centered text with subtle shadow
      let textX = (screenWidth div 2 - waveTextWidth div 2).int32
      let textY = 40.int32
      
      # Shadow
      drawText(waveText, textX + 2.int32, textY + 2.int32, waveTextSize,
              Color(r: 0, g: 0, b: 0, a: 100))
      
      # Main text
      drawText(waveText, textX, textY, waveTextSize,
              Color(r: 150, g: 255, b: 150, a: 255))
      
      endDrawing()
    
    of gsPowerUpSelect:
      # Play power-up selection music
      playMusic(mtPowerUp)
      
      # Update roll animation
      updatePowerUpRollAnimation(currentGame, dt)
      
      # Update mouse tracking
      updateMouseTracking(currentGame)
      
      # Only allow input after animation completes
      if currentGame.canSelectPowerUp:
        # Navigate power-up choices with keyboard
        if isKeyPressed(Left) or isKeyPressed(A):
          currentGame.selectedPowerUp = (currentGame.selectedPowerUp - 1 + 3) mod 3
          markKeyboardUsed(currentGame)
        if isKeyPressed(Right) or isKeyPressed(D):
          currentGame.selectedPowerUp = (currentGame.selectedPowerUp + 1) mod 3
          markKeyboardUsed(currentGame)
        
        # Select power-up with keyboard or mouse
        if isKeyPressed(Enter) or isKeyPressed(E) or isMouseButtonPressed(Left):
          # For mouse clicks, verify we're clicking on a card (only if mouse support enabled AND mouse moved recently)
          var validClick = isKeyPressed(Enter) or isKeyPressed(E)
          if not validClick and isMouseButtonPressed(Left):
            let mousePos = getMousePosition()
            let cardWidth = 200
            let cardHeight = 240
            let spacing = 40
            let totalWidth = cardWidth * 3 + spacing * 2
            let startX = (currentGame.screenWidth - totalWidth) div 2
            let cardY = if currentGame.powerUpChoices[0].rarity == prLegendary: 160 else: 180
            
            for i in 0..2:
              let cardX = startX + i * (cardWidth + spacing)
              if isMenuClickValid(currentGame, settings, Vector2f(x: mousePos.x, y: mousePos.y), int32(cardX), int32(cardY), int32(cardWidth), int32(cardHeight)):
                validClick = true
                break
          
          if validClick:
            let chosenPowerUp = currentGame.powerUpChoices[currentGame.selectedPowerUp]
            applyPowerUp(currentGame.player, chosenPowerUp)
            
            # Track power-up selection for statistics
            trackPowerUpSelection(currentGame, chosenPowerUp)
            
            currentGame.cameFromPowerUpSelect = true
            currentGame.state = gsShop
        
        # Skip power-up selection
        if isKeyPressed(Escape):
          currentGame.state = gsCountdown
          currentGame.countdownTimer = 0.5
      
      beginDrawing()
      drawPowerUpSelection(currentGame)
      endDrawing()
    
    of gsGameOver:
      # Stop music and play game over sound once
      if not currentGame.gameOverSoundPlayed:
        stopMusic()
        playSound(stGameOver, 1.0)
        currentGame.gameOverSoundPlayed = true
        
        # Finalize run tracking and save for menu viewing
        if hasValidRunStats():
          finalizeRunTracking(currentGame)
          saveLastCompletedRun()  # Save to memory
          # Also save to disk
          if not currentRunStats.isNil:
            discard saveLastRunStats(currentRunStats)
        
        # Save statistics only once per game over
        if not statsSavedThisGame and not currentGame.cheatsUsed:
          # Calculate bosses defeated based on wave progress
          let bossesKilled = if currentGame.mode == gmWaveBased:
            (currentGame.currentWave - 1) div 5  # Boss every 5 waves
          else:
            currentGame.bossCount
          
          updateStats(stats, 
                     currentGame.mode == gmWaveBased,
                     currentGame.currentWave,
                     currentGame.time,
                     currentGame.player.kills,
                     currentGame.player.coins,
                     bossesKilled)
          discard saveStatistics(stats)
          statsSavedThisGame = true
      
      # Navigate to run stats screen
      if isKeyPressed(Tab) and hasValidRunStats():
        currentGame.state = gsRunStats
      
      # Keyboard controls
      if isKeyPressed(R):
        currentGame = newGame(screenWidth, screenHeight)
        currentGame.mode = gmWaveBased  # Default to wave-based on restart
        initializeRunTracking(currentGame)  # Start tracking
        currentGame.state = gsPlaying
        statsSavedThisGame = false  # Reset for new game
      
      if isKeyPressed(Escape) or isKeyPressed(Q):
        currentGame = newGame(screenWidth, screenHeight)
        currentGame.state = gsMenu
        statsSavedThisGame = false  # Reset for new game
      
      # Mouse click handling for buttons
      if isMouseButtonPressed(Left):
        let mousePos = getMousePosition()
        let buttonY = screenHeight div 2 + 200
        let buttonWidth = 200
        let buttonHeight = 50
        let buttonSpacing = 220
        
        # Restart button
        let restartX = screenWidth div 2 - buttonSpacing
        let restartRect = Rectangle(x: restartX.float32, y: buttonY.float32,
                                     width: buttonWidth.float32, height: buttonHeight.float32)
        
        # Menu button  
        let menuX = screenWidth div 2 + 20
        let menuRect = Rectangle(x: menuX.float32, y: buttonY.float32,
                                 width: buttonWidth.float32, height: buttonHeight.float32)
        
        # Check clicks
        if checkCollisionPointRec(mousePos, restartRect):
          # Restart game
          currentGame = newGame(screenWidth, screenHeight)
          currentGame.mode = gmWaveBased
          initializeRunTracking(currentGame)
          currentGame.state = gsPlaying
          statsSavedThisGame = false
        elif checkCollisionPointRec(mousePos, menuRect):
          # Return to menu
          currentGame = newGame(screenWidth, screenHeight)
          currentGame.state = gsMenu
          statsSavedThisGame = false
      
      beginDrawing()
      drawGameOver(currentGame)
      
      # Show hint to view stats
      if hasValidRunStats():
        drawText("Press TAB for detailed run statistics", 
                screenWidth div 2 - 200, screenHeight - 120, 18, Gold)
      
      endDrawing()
    
    of gsRunStats:
      # Display detailed run statistics
      
      # Update time for animations
      currentGame.time += dt
      
      # Toggle graphs OR return to game over with Tab
      if isKeyPressed(Tab):
        currentGame.state = gsGameOver
      
      # Return to game over screen with Escape (same as Tab now)
      if isKeyPressed(Escape):
        currentGame.state = gsGameOver
      
      # Quick restart
      if isKeyPressed(R):
        currentGame = newGame(screenWidth, screenHeight)
        currentGame.mode = gmWaveBased
        initializeRunTracking(currentGame)
        currentGame.state = gsPlaying
        statsSavedThisGame = false
      
      # Return to menu
      if isKeyPressed(Q):
        currentGame = newGame(screenWidth, screenHeight)
        currentGame.state = gsMenu
        statsSavedThisGame = false
      
      beginDrawing()
      if hasValidRunStats():
        drawRunStatisticsScreen(currentRunStats, screenWidth, screenHeight, 
                               currentGame.time, currentGame.showRunStatsGraphs)
      else:
        # Fallback if no stats available
        clearBackground(Color(r: 20, g: 20, b: 30, a: 255))
        drawText("No statistics available", 
                screenWidth div 2 - 150, screenHeight div 2, 24, Red)
        drawText("Press ESC to return", 
                screenWidth div 2 - 120, screenHeight div 2 + 40, 18, LightGray)
      
      # Show navigation hints
      let hintY = screenHeight - 30
      drawText("R - Restart | Q - Menu | ESC - Back | TAB - Toggle Graphs", 
              (screenWidth div 2 - 280).int32, hintY.int32, 16.int32, Gold)
      
      endDrawing()
  
  # Cleanup
  stopMusic()
  closeSoundSystem(globalSoundSystem)
  closeWindow()

when isMainModule:
  main()
