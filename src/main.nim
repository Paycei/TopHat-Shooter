import raylib, types, game, ui/os_shop, wall, particle, powerup, player, coin, random, math, strutils, sound, settings, cheat, statistics, run_statistics, save_system, sandbox, discord_helpers, discord_presence, discord_config, gamemode_definitions, ui/os_splash, ui/os_desktop, ui/os_window, ui/settings_window, ui/help_window, ui/stats_window, ui/os_task_manager

const
  screenWidth = 1024
  screenHeight = 768
  targetFPS = 60
  MOUSE_MOVEMENT_THRESHOLD = 2.0  # Minimum pixel movement to count as "mouse moved"

# Global Discord client that persists across game sessions
var globalDiscordClient: DiscordClient = nil

# Global OS windows
var osSettingsWindow: SettingsWindow = nil
var osHelpWindow: HelpWindow = nil
var osStatsWindow: StatsWindow = nil

var
  renderTarget: RenderTexture2D  # Virtual screen for consistent rendering
  renderScale: float32 = 1.0
  renderOffsetX: float32 = 0.0
  renderOffsetY: float32 = 0.0

proc updateRenderScale() =
  ## Calculate letterbox scaling for current window size
  let windowWidth = getScreenWidth()
  let windowHeight = getScreenHeight()
  
  let scaleX = windowWidth.float32 / screenWidth.float32
  let scaleY = windowHeight.float32 / screenHeight.float32
  
  # Use smaller scale to maintain aspect ratio
  renderScale = min(scaleX, scaleY)
  
  # Calculate centering offsets
  let scaledWidth = screenWidth.float32 * renderScale
  let scaledHeight = screenHeight.float32 * renderScale
  renderOffsetX = (windowWidth.float32 - scaledWidth) / 2.0
  renderOffsetY = (windowHeight.float32 - scaledHeight) / 2.0

proc getVirtualMousePosition(): Vector2 =
  ## Convert screen mouse position to virtual game coordinates
  let screenPos = getMousePosition()
  result.x = (screenPos.x - renderOffsetX) / renderScale
  result.y = (screenPos.y - renderOffsetY) / renderScale
  # Clamp to game bounds
  result.x = clamp(result.x, 0.0, screenWidth.float32)
  result.y = clamp(result.y, 0.0, screenHeight.float32)

proc beginGameDrawing() =
  ## Begin drawing to the virtual render target
  beginTextureMode(renderTarget)

proc endGameDrawing() =
  ## End drawing to render target and blit to screen with letterboxing
  endTextureMode()
  
  beginDrawing()
  clearBackground(Black)  # Black bars for letterboxing
  
  # Draw the scaled render texture
  let source = Rectangle(x: 0, y: 0, width: screenWidth.float32, height: -screenHeight.float32)
  let dest = Rectangle(x: renderOffsetX, y: renderOffsetY,
                       width: screenWidth.float32 * renderScale,
                       height: screenHeight.float32 * renderScale)
  drawTexture(renderTarget.texture, source, dest, Vector2(x: 0, y: 0), 0, White)
  
  endDrawing()

proc isMenuClickValid*(game: Game, settings: Settings, mousePos: Vector2f, buttonX: int32, buttonY: int32, buttonWidth: int32, buttonHeight: int32): bool =
  ## Helper function to validate mouse clicks in menus
  ## Returns true if mouse click is within button bounds and mouse support is enabled
  if not settings.mouseSupport or not game.mouseMovedRecently:
    return false
  return mousePos.x >= buttonX.float32 and mousePos.x <= (buttonX + buttonWidth).float32 and
         mousePos.y >= buttonY.float32 and mousePos.y <= (buttonY + buttonHeight).float32

proc hasMouseMoved*(game: Game): bool =
  ## Detects if mouse has actually moved (not just hovering)
  let currentPos = getVirtualMousePosition()
  let dx = abs(currentPos.x - game.lastMousePos.x)
  let dy = abs(currentPos.y - game.lastMousePos.y)
  result = (dx > MOUSE_MOVEMENT_THRESHOLD or dy > MOUSE_MOVEMENT_THRESHOLD)

proc updateMouseTracking*(game: Game) =
  ## Updates mouse position tracking and resets keyboard flag if mouse moved
  let currentPos = getVirtualMousePosition()
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

proc main() =
  randomize()
  
  # Initialize settings first to check fullscreen preference
  let settings = initSettings()
  
  # Set up window with appropriate flags based on saved settings
  if settings.fullscreen:
    setConfigFlags(flags(WindowUndecorated, WindowResizable))
  else:
    setConfigFlags(flags(WindowResizable))
  
  initWindow(screenWidth, screenHeight, "TopHat-ShooterOS: v5.0 Edition")
  setTargetFPS(targetFPS)
  setExitKey(Null)
  hideCursor()  # Hide default cursor for custom cursor
  
  # Apply fullscreen if needed (resize and position)
  if settings.fullscreen:
    let monitor = getCurrentMonitor()
    let monitorWidth = getMonitorWidth(monitor)
    let monitorHeight = getMonitorHeight(monitor)
    setWindowSize(monitorWidth, monitorHeight)
    setWindowPosition(0, 0)
  
  # Create render target for letterboxing
  renderTarget = loadRenderTexture(screenWidth, screenHeight)
  updateRenderScale()
  
  # Initialize sound system
  discard initSoundSystem()
  
  # Initialize cheat menu
  let cheatMenu = initCheatMenu()
  
  # Apply remaining settings
  applySettings(settings)
  
  # Initialize and load statistics
  let stats = initStatistics()
  discard loadStatistics(stats)
  
  # Load last completed run statistics
  let loadedRunStats = loadLastRunStats()
  if not loadedRunStats.isNil:
    loadLastCompletedRun(loadedRunStats)
  
  var statsSavedThisGame = false  # Track if stats were saved for current game
  var fullscreenToggleRequested = false  # Flag to request fullscreen toggle on next frame
  
  # Initialize global Discord client (persists across game sessions)
  globalDiscordClient = newDiscordClient(DISCORD_APP_ID)
  discard globalDiscordClient.connect()  # Start background thread
  
  var currentGame = newGame(screenWidth, screenHeight)
  currentGame.state = gsSplash  # Start with splash screen
  # Assign global Discord client to game
  currentGame.discordClient = globalDiscordClient
  
  # Initialize OS-themed screens
  var splashScreen = newSplashScreen()
  var osDesktop = newOSDesktop()
  
  # Initialize OS windows (lazy initialization - create when first needed)
  osSettingsWindow = nil
  osHelpWindow = nil
  osStatsWindow = nil
  
  while not windowShouldClose():
    # Check if fullscreen toggle was requested
    if fullscreenToggleRequested:
      fullscreenToggleRequested = false
      
      if settings.fullscreen:
        # Going to fullscreen - maximize to monitor size
        let monitor = getCurrentMonitor()
        let monitorWidth = getMonitorWidth(monitor)
        let monitorHeight = getMonitorHeight(monitor)
        setWindowSize(monitorWidth, monitorHeight)
        setWindowPosition(0, 0)
      else:
        # Going to windowed - restore original window size
        setWindowSize(screenWidth, screenHeight)
        # Center the window on screen
        let monitor = getCurrentMonitor()
        let monitorWidth = getMonitorWidth(monitor)
        let monitorHeight = getMonitorHeight(monitor)
        setWindowPosition((monitorWidth - screenWidth) div 2, (monitorHeight - screenHeight) div 2)
      
      updateRenderScale()
      discard saveSettings(settings)
    
    let dt = getFrameTime()
    
    # Update render scale every frame in case window was resized
    updateRenderScale()
    
    # Update music stream (required for continuous playback)
    updateMusic()
    
    # Handle fullscreen toggle with F11 (borderless window)
    if isKeyPressed(F11):
      settings.fullscreen = not settings.fullscreen
      fullscreenToggleRequested = true
    
    # ALWAYS hide system cursor - we always use custom cursor
    hideCursor()
    
    case currentGame.state
    of gsSplash:
      # Update splash screen
      updateSplashScreen(splashScreen, dt)
      
      # Skip splash with any key
      if splashScreen.complete and (isKeyPressed(Space) or isKeyPressed(Enter) or 
                                     isKeyPressed(Escape) or isMouseButtonPressed(Left)):
        currentGame.state = gsMenu
      
      beginGameDrawing()
      drawSplashScreen(splashScreen, screenWidth, screenHeight)
      endGameDrawing()
    
    of gsMenu:
      # Play menu music
      playMusic(mtMenu)
      
      # Update time for menu animations
      currentGame.time += dt
      
      # Update OS desktop
      updateOSDesktop(osDesktop, dt)
      
      # Check if any windows are blocking desktop interaction
      # Only handle desktop input if no windows are open and covering the desktop
      let mousePos = getMousePosition()
      var windowBlocking = false
      
      if not osSettingsWindow.isNil and osSettingsWindow.window.visible and not osSettingsWindow.window.minimized:
        if checkCollisionPointRec(mousePos, Rectangle(x: osSettingsWindow.window.x.float32,
                                                       y: osSettingsWindow.window.y.float32,
                                                       width: osSettingsWindow.window.width.float32,
                                                       height: osSettingsWindow.window.height.float32)):
          windowBlocking = true
      
      if not windowBlocking and not osHelpWindow.isNil and osHelpWindow.window.visible and not osHelpWindow.window.minimized:
        if checkCollisionPointRec(mousePos, Rectangle(x: osHelpWindow.window.x.float32,
                                                       y: osHelpWindow.window.y.float32,
                                                       width: osHelpWindow.window.width.float32,
                                                       height: osHelpWindow.window.height.float32)):
          windowBlocking = true
      
      if not windowBlocking and not osStatsWindow.isNil and osStatsWindow.window.visible and not osStatsWindow.window.minimized:
        if checkCollisionPointRec(mousePos, Rectangle(x: osStatsWindow.window.x.float32,
                                                       y: osStatsWindow.window.y.float32,
                                                       width: osStatsWindow.window.width.float32,
                                                       height: osStatsWindow.window.height.float32)):
          windowBlocking = true
      
      # Handle OS desktop input and get action (only if no windows are blocking)
      let action = if not windowBlocking: handleDesktopInput(osDesktop, currentGame) else: -1
      
      # Process desktop actions
      if action >= 0:
        playSound(stMenuSelect)
        case action
        of 0:  # Play.exe - Wave-Based Mode
          currentGame = newGame(screenWidth, screenHeight)
          currentGame.discordClient = globalDiscordClient
          setGameMode(currentGame, gmWaveBased)
          initializeRunTracking(currentGame)
          currentGame.state = gsPlaying
          statsSavedThisGame = false
        of 1:  # Survival.exe - Time Survival Mode
          currentGame = newGame(screenWidth, screenHeight)
          currentGame.discordClient = globalDiscordClient
          setGameMode(currentGame, gmTimeSurvival)
          initializeRunTracking(currentGame)
          currentGame.state = gsPlaying
          statsSavedThisGame = false
        of 2:  # Stats.exe - Open Statistics Window
          # Reload stats from disk before opening window
          discard loadStatistics(stats)
          let freshRunStats = loadLastRunStats()
          if not freshRunStats.isNil:
            loadLastCompletedRun(freshRunStats)
          
          if osStatsWindow.isNil:
            osStatsWindow = newStatsWindow(screenWidth, screenHeight, stats)
          else:
            # Update stats reference if window already exists
            osStatsWindow.stats = stats
          osStatsWindow.window.visible = true
          osStatsWindow.window.focused = true
        of 3:  # Settings.exe - Open Settings Window
          if osSettingsWindow.isNil:
            osSettingsWindow = newSettingsWindow(screenWidth, screenHeight, settings)
          osSettingsWindow.window.visible = true
          osSettingsWindow.window.focused = true
        of 4:  # Help.txt - Open Help Window
          if osHelpWindow.isNil:
            osHelpWindow = newHelpWindow(screenWidth, screenHeight)
          osHelpWindow.window.visible = true
          osHelpWindow.window.focused = true
        of 5:  # Shutdown.exe - Quit
          break
        of 6:  # Sandbox.exe - Sandbox Mode
          currentGame = newGame(screenWidth, screenHeight)
          currentGame.discordClient = globalDiscordClient
          setGameMode(currentGame, gmSandbox)
          initializeRunTracking(currentGame)
          currentGame.state = gsPlaying
          statsSavedThisGame = false
        else: discard
      
      # Update Discord Rich Presence (throttled internally to prevent lag)
      if not currentGame.discordClient.isNil:
        runCallbacks(currentGame.discordClient)
        updateDiscordForMenu(currentGame.discordClient)
      
      # Update OS windows if they exist and are visible
      if not osSettingsWindow.isNil and osSettingsWindow.window.visible:
        let result = updateSettingsWindow(osSettingsWindow, dt, screenWidth, screenHeight)
        if result.fullscreenToggle:
          fullscreenToggleRequested = true
      
      if not osStatsWindow.isNil and osStatsWindow.window.visible:
        discard updateStatsWindow(osStatsWindow, dt, screenWidth, screenHeight)
      
      if not osHelpWindow.isNil and osHelpWindow.window.visible:
        let iconToExecute = updateHelpWindow(osHelpWindow, dt, screenWidth, screenHeight)
        # Handle icon execution from help window commands
        if iconToExecute >= 0:
          osHelpWindow.window.visible = false
          playSound(stMenuSelect)
          case iconToExecute
          of 0:  # Play.exe - Wave-Based Mode
            currentGame = newGame(screenWidth, screenHeight)
            currentGame.discordClient = globalDiscordClient
            setGameMode(currentGame, gmWaveBased)
            initializeRunTracking(currentGame)
            currentGame.state = gsPlaying
            statsSavedThisGame = false
          of 1:  # Survival.exe - Time Survival Mode
            currentGame = newGame(screenWidth, screenHeight)
            currentGame.discordClient = globalDiscordClient
            setGameMode(currentGame, gmTimeSurvival)
            initializeRunTracking(currentGame)
            currentGame.state = gsPlaying
            statsSavedThisGame = false
          of 2:  # Stats.exe - Open Statistics Window
            discard loadStatistics(stats)
            let freshRunStats = loadLastRunStats()
            if not freshRunStats.isNil:
              loadLastCompletedRun(freshRunStats)
            if osStatsWindow.isNil:
              osStatsWindow = newStatsWindow(screenWidth, screenHeight, stats)
            else:
              osStatsWindow.stats = stats
            osStatsWindow.window.visible = true
            osStatsWindow.window.focused = true
          of 3:  # Settings.exe - Open Settings Window
            if osSettingsWindow.isNil:
              osSettingsWindow = newSettingsWindow(screenWidth, screenHeight, settings)
            osSettingsWindow.window.visible = true
            osSettingsWindow.window.focused = true
          of 5:  # Shutdown.exe - Quit
            break
          of 6:  # Sandbox.exe - Sandbox Mode
            currentGame = newGame(screenWidth, screenHeight)
            currentGame.discordClient = globalDiscordClient
            setGameMode(currentGame, gmSandbox)
            initializeRunTracking(currentGame)
            currentGame.state = gsPlaying
            statsSavedThisGame = false
          else: discard
      
      beginGameDrawing()
      drawOSDesktop(osDesktop, screenWidth, screenHeight)
      
      # Draw OS windows on top if visible
      if not osStatsWindow.isNil and osStatsWindow.window.visible:
        drawStatsWindow(osStatsWindow, currentGame)
      
      if not osSettingsWindow.isNil and osSettingsWindow.window.visible:
        drawSettingsWindow(osSettingsWindow)
      
      if not osHelpWindow.isNil and osHelpWindow.window.visible:
        drawHelpWindow(osHelpWindow)
      
      # Draw custom cursor on menu
      drawCustomCursor(currentGame.time)
      
      endGameDrawing()
    
    of gsHelp:
      # Keep menu music playing during help screen
      playMusic(mtMenu)
      
      # Open OS help window if not already open
      if osHelpWindow.isNil:
        osHelpWindow = newHelpWindow(screenWidth, screenHeight)
      if not osHelpWindow.window.visible:
        osHelpWindow.window.visible = true
        osHelpWindow.window.focused = true
      
      # Update help window
      let iconToExecute = updateHelpWindow(osHelpWindow, dt, screenWidth, screenHeight)
      
      # Handle icon execution
      if iconToExecute >= 0:
        osHelpWindow.window.visible = false
        case iconToExecute
        of 0:  # Play
          # Start a fresh Wave-Based game (same pattern as main menu start)
          currentGame = newGame(screenWidth, screenHeight)
          currentGame.discordClient = globalDiscordClient
          setGameMode(currentGame, gmWaveBased)
          initializeRunTracking(currentGame)
          currentGame.state = gsPlaying
          statsSavedThisGame = false
        of 1:  # Survival
          # Start a fresh Time Survival game
          currentGame = newGame(screenWidth, screenHeight)
          currentGame.discordClient = globalDiscordClient
          setGameMode(currentGame, gmTimeSurvival)
          initializeRunTracking(currentGame)
          currentGame.state = gsPlaying
          statsSavedThisGame = false
        of 2:  # Stats
          currentGame.state = gsStatistics
        of 3:  # Settings
          currentGame.state = gsSettings
        of 5:  # Quit
          break
        else:
          discard
      
      if isKeyPressed(Escape) or not osHelpWindow.window.visible:
        osHelpWindow.window.visible = false
        currentGame.state = gsMenu
      
      beginGameDrawing()
      drawOSDesktop(osDesktop, screenWidth, screenHeight)
      drawHelpWindow(osHelpWindow)
      drawCustomCursor(currentGame.time)
      endGameDrawing()
    
    of gsSettings:
      # Keep menu music playing during settings
      playMusic(mtMenu)
      
      # Update time first
      currentGame.time += dt
      
      # Open OS settings window if not already open
      if osSettingsWindow.isNil:
        osSettingsWindow = newSettingsWindow(screenWidth, screenHeight, settings)
      if not osSettingsWindow.window.visible:
        osSettingsWindow.window.visible = true
        osSettingsWindow.window.focused = true
      
      # Update settings window
      let result = updateSettingsWindow(osSettingsWindow, dt, screenWidth, screenHeight)
      
      if isKeyPressed(Escape) or result.shouldClose or not osSettingsWindow.window.visible:
        osSettingsWindow.window.visible = false
        currentGame.state = currentGame.previousState  # Return to where we came from
        setGameVolume(settings.volume)  # Apply volume changes
        setMusicVolume(settings.musicVolume)  # Apply music volume changes
        playSound(stMenuSelect)
      
      if result.fullscreenToggle:
        fullscreenToggleRequested = true
      
      # Always draw the frame first
      beginGameDrawing()
      # Draw appropriate background based on where we came from
      if currentGame.previousState == gsMenu:
        drawOSDesktop(osDesktop, screenWidth, screenHeight)
      else:
        # From game pause - show game in background with overlay
        drawGame(currentGame)
        drawRectangle(0, 0, screenWidth, screenHeight, Color(r: 0, g: 0, b: 0, a: 150))
      
      drawSettingsWindow(osSettingsWindow)
      drawCustomCursor(currentGame.time)
      endGameDrawing()
    
    of gsStatistics:
      # Keep menu music playing during statistics screen
      playMusic(mtMenu)
      
      # Update time for animations
      currentGame.time += dt
      
      # Open OS stats window if not already open
      # Reload stats from disk before opening
      discard loadStatistics(stats)
      let freshRunStats = loadLastRunStats()
      if not freshRunStats.isNil:
        loadLastCompletedRun(freshRunStats)
      
      if osStatsWindow.isNil:
        osStatsWindow = newStatsWindow(screenWidth, screenHeight, stats)
      else:
        # Update stats reference if window already exists
        osStatsWindow.stats = stats
      if not osStatsWindow.window.visible:
        osStatsWindow.window.visible = true
        osStatsWindow.window.focused = true
      
      # Update stats window
      let shouldClose = updateStatsWindow(osStatsWindow, dt, screenWidth, screenHeight)
      
      if isKeyPressed(Escape) or shouldClose or not osStatsWindow.window.visible:
        osStatsWindow.window.visible = false
        currentGame.state = gsMenu
      
      beginGameDrawing()
      drawOSDesktop(osDesktop, screenWidth, screenHeight)
      drawStatsWindow(osStatsWindow, currentGame)
      drawCustomCursor(currentGame.time)
      endGameDrawing()

    of gsPlaying:
      # Dynamic music based on game state
      if currentGame.bossWaveManager.isBossActive():
        playMusic(mtBoss)
      else:
        playMusic(mtWave)
      
      # Update Discord Rich Presence (throttled internally to prevent lag)
      if not currentGame.discordClient.isNil and not cheatMenu.active:
        runCallbacks(currentGame.discordClient)
        updateDiscordForPlaying(currentGame.discordClient, currentGame)
      
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
        
        # Time Warp - slow down time
        if hasPowerUp(currentGame.player, puTimeWarp) and currentGame.player.timeWarpCooldown <= 0:
          # Check if uses available for this wave
          if currentGame.player.timeWarpUsesThisWave < currentGame.player.timeWarpMaxUsesPerWave:
            let duration = 3.5
            let cooldown = 10.0  # 10 second cooldown between uses
            
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
        if isSandboxMode(currentGame.mode):
          # Handle sandbox input
          handleSandboxInput(currentGame, screenWidth, screenHeight)
          # Update sandbox mode (god mode, freeze enemies, etc.)
          updateSandboxMode(currentGame, dt)
          # Update game normally (unless enemies are frozen)
          if not currentGame.sandboxFreezeEnemies:
            updateGame(currentGame, dt)
          else:
            # Still update player, bullets, particles, but not enemies
            updatePlayer(
              currentGame.player,
              dt,
              int32(currentGame.screenWidth),
              int32(currentGame.screenHeight),
              currentGame.walls
            )
            for bullet in currentGame.bullets:
              bullet.pos.x += bullet.vel.x * dt
              bullet.pos.y += bullet.vel.y * dt
            # Update particles and remove dead ones
            var aliveParticles: seq[Particle] = @[]
            for particle in currentGame.particles:
              if updateParticle(particle, dt):
                aliveParticles.add(particle)
            currentGame.particles = aliveParticles
        else:
          updateGame(currentGame, dt)
      
      beginGameDrawing()
      drawGame(currentGame)
      
      # Draw sandbox UI if in sandbox mode
      if isSandboxMode(currentGame.mode):
        drawSandboxSidebar(currentGame, screenWidth, screenHeight)
      
      # Draw cheat menu overlay if active
      drawCheatMenu(cheatMenu, currentGame, screenWidth, screenHeight)
      
      # Draw custom cursor during gameplay
      drawCustomCursor(currentGame.time)
      
      endGameDrawing()
    
    of gsPaused:
      # Keep current music playing but muted or paused
      # Music continues in background during pause
      
      # Update time for animations even when paused
      currentGame.time += dt
      
      # Update mouse tracking
      updateMouseTracking(currentGame)
      
      # Pause menu navigation - Tab switching (Left/Right or A/D)
      if isKeyPressed(Left) or isKeyPressed(A):
        currentGame.pauseMenuTab = case currentGame.pauseMenuTab
          of tmtProcesses: tmtPerformance
          of tmtPerformance: tmtProcesses
          else: tmtProcesses
        playSound(stMenuNav)
        markKeyboardUsed(currentGame)
      elif isKeyPressed(Right) or isKeyPressed(D):
        currentGame.pauseMenuTab = case currentGame.pauseMenuTab
          of tmtProcesses: tmtPerformance
          of tmtPerformance: tmtProcesses
          else: tmtProcesses
        playSound(stMenuNav)
        markKeyboardUsed(currentGame)
      
      # Actions
      if isKeyPressed(Space):  # Resume
        currentGame.state = gsPlaying
        playSound(stMenuSelect)
      elif isKeyPressed(Tab):  # Open Settings
        currentGame.previousState = gsPaused
        currentGame.state = gsSettings
        playSound(stMenuSelect)
      elif isKeyPressed(Q):  # Quit to main menu
        cleanupGame(currentGame)
        currentGame = newGame(screenWidth, screenHeight)
        currentGame.discordClient = globalDiscordClient
        currentGame.state = gsMenu
        playSound(stMenuSelect)
      elif isKeyPressed(Escape):  # ESC also resumes
        currentGame.state = gsPlaying
      
      # Update Discord Rich Presence (throttled internally to prevent lag)
      if not currentGame.discordClient.isNil:
        runCallbacks(currentGame.discordClient)
        updateDiscordForPaused(currentGame.discordClient, currentGame)
      
      beginGameDrawing()
      drawGame(currentGame)
      
      # Draw OS-style Task Manager pause menu and handle mouse interactions
      let menuResult = drawOSTaskManager(currentGame, currentGame.pauseMenuTab)
      
      # Handle tab changes from mouse
      if menuResult.newTab != currentGame.pauseMenuTab:
        currentGame.pauseMenuTab = menuResult.newTab
        playSound(stMenuNav)
      
      # Handle button clicks
      if menuResult.resumeClicked:
        currentGame.state = gsPlaying
        playSound(stMenuSelect)
      elif menuResult.settingsClicked:
        currentGame.previousState = gsPaused
        currentGame.state = gsSettings
        playSound(stMenuSelect)
      elif menuResult.exitClicked:
        cleanupGame(currentGame)
        currentGame = newGame(screenWidth, screenHeight)
        currentGame.discordClient = globalDiscordClient
        currentGame.state = gsMenu
        playSound(stMenuSelect)
      
      # Draw custom cursor (only if mouseSupport is enabled OR showCursorInMenus is enabled)
      if globalSettings.mouseSupport or globalSettings.showCursorInMenus:
        drawCustomCursor(currentGame.time)
      
      endGameDrawing()
    
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
      
      # Mouse click handling for shop items
      if isMouseButtonPressed(Left):
        let mousePos = getMousePosition()
        
        # Shop dimensions from shop.nim
        const SHOP_WIDTH = 950
        const SHOP_HEIGHT = 600
        const TITLE_BAR_HEIGHT = 45
        const SIDEBAR_WIDTH = 280
        const ITEM_HEIGHT = 60
        const ITEM_SPACING = 6
        
        let windowX = (currentGame.screenWidth - SHOP_WIDTH) div 2
        let windowY = (currentGame.screenHeight - SHOP_HEIGHT) div 2
        
        # Check close button click (X button in title bar)
        let closeButtonSize = 28
        let closeButtonX = windowX + SHOP_WIDTH - closeButtonSize - 10
        let closeButtonY = windowY + (TITLE_BAR_HEIGHT - closeButtonSize) div 2
        let closeButtonRect = Rectangle(x: closeButtonX.float32, y: closeButtonY.float32,
                                        width: closeButtonSize.float32, height: closeButtonSize.float32)
        
        if checkCollisionPointRec(mousePos, closeButtonRect):
          # Close shop and continue to next wave
          currentGame.cameFromPowerUpSelect = false
          currentGame.state = gsCountdown
          currentGame.countdownTimer = 0.5
        else:
          let sidebarX = windowX + 10
          let sidebarY = windowY + TITLE_BAR_HEIGHT + 10
          let shopX = sidebarX + SIDEBAR_WIDTH + 15
          let shopY = sidebarY + 10
          let itemsStartY = shopY + 35
          let shopWidth = SHOP_WIDTH - SIDEBAR_WIDTH - 40
          
          # Check shop item clicks
          var clickedItem = -1
          for i in 0..5:
            let itemY = itemsStartY + i * (ITEM_HEIGHT + ITEM_SPACING)
            let itemRect = Rectangle(x: shopX.float32, y: itemY.float32,
                                    width: shopWidth.float32, height: ITEM_HEIGHT.float32)
            
            if checkCollisionPointRec(mousePos, itemRect):
              clickedItem = i
              break
          
          # Check big buy button click
          let buyButtonWidth = 220
          let buyButtonHeight = 38
          let bottomY = windowY + SHOP_HEIGHT - 65
          let buyButtonX = windowX + SHOP_WIDTH - buyButtonWidth - 20
          let buyButtonY = bottomY + 12
          let buyButtonRect = Rectangle(x: buyButtonX.float32, y: buyButtonY.float32,
                                        width: buyButtonWidth.float32, height: buyButtonHeight.float32)
          
          if clickedItem >= 0:
            # Clicked on an item - select and buy it
            currentGame.selectedShopItem = clickedItem
            buyShopItem(currentGame, clickedItem)
          elif checkCollisionPointRec(mousePos, buyButtonRect):
            # Clicked the buy button - buy selected item
            buyShopItem(currentGame, currentGame.selectedShopItem)
      
      # Buy item with keyboard
      if isKeyPressed(Enter) or isKeyPressed(E):
        buyShopItem(currentGame, currentGame.selectedShopItem)
      
      # Close shop - always continue to next wave (no going back to power-up selection)
      if isKeyPressed(Escape) or isKeyPressed(Q):
        currentGame.cameFromPowerUpSelect = false
        currentGame.state = gsCountdown
        currentGame.countdownTimer = 0.5
      
      beginGameDrawing()
      drawGame(currentGame)
      drawShop(currentGame)
      
      # Draw custom cursor
      drawCustomCursor(currentGame.time)
      
      endGameDrawing()
    
    of gsCountdown:
      # Keep wave music during countdown
      playMusic(mtWave)
      
      # Countdown timer
      currentGame.countdownTimer -= dt
      
      if currentGame.countdownTimer <= 0:
        currentGame.state = gsPlaying
      
      beginGameDrawing()
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
      
      # Draw custom cursor
      drawCustomCursor(currentGame.time)
      
      endGameDrawing()
    
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
        
        if shouldOfferPowerUp and not currentGame.bossWaveManager.isBossCoinActive():
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
          initializeRerollCost(currentGame)
          currentGame.state = gsPowerUpSelect
        else:
          # No power-up, go straight to next wave
          currentGame.state = gsPlaying
          startWave(currentGame)
      
      beginGameDrawing()
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
      
      endGameDrawing()
    
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
        
        # Reroll power-ups with R key
        if isKeyPressed(R):
          if attemptRerollPowerUps(currentGame):
            markKeyboardUsed(currentGame)
          # If reroll failed (not enough coins), do nothing (could add sound here)
        
        # Mouse hover detection for card selection
        if isMouseButtonPressed(Left) or getMousePosition().x != 0:
          let mousePos = getMousePosition()
          # Use actual UI dimensions from os_powerup_installer.nim
          const INSTALLER_WIDTH = 1000
          const INSTALLER_HEIGHT = 650
          const TITLE_BAR_HEIGHT = 45
          const CARD_WIDTH = 280
          const CARD_HEIGHT = 380
          const CARD_SPACING = 35
          
          let windowX = (currentGame.screenWidth - INSTALLER_WIDTH) div 2
          let windowY = (currentGame.screenHeight - INSTALLER_HEIGHT) div 2
          let yPos = windowY + TITLE_BAR_HEIGHT + 75
          let totalCardWidth = CARD_WIDTH * 3 + CARD_SPACING * 2
          let startX = windowX + (INSTALLER_WIDTH - totalCardWidth) div 2
          
          # Check which card mouse is over
          for i in 0..2:
            let cardX = startX + i * (CARD_WIDTH + CARD_SPACING)
            let cardRect = Rectangle(x: cardX.float32, y: yPos.float32,
                                     width: CARD_WIDTH.float32, height: CARD_HEIGHT.float32)
            
            if checkCollisionPointRec(mousePos, cardRect):
              currentGame.selectedPowerUp = i
              break
        
        # Select power-up with keyboard or mouse click on card
        if isKeyPressed(Enter) or isKeyPressed(E):
          let chosenPowerUp = currentGame.powerUpChoices[currentGame.selectedPowerUp]
          applyPowerUp(currentGame.player, chosenPowerUp)
          
          # Track power-up selection for statistics
          trackPowerUpSelection(currentGame, chosenPowerUp)
          
          currentGame.cameFromPowerUpSelect = true
          currentGame.state = gsShop
        
        # Mouse click to select
        if isMouseButtonPressed(Left):
          let mousePos = getMousePosition()
          const INSTALLER_WIDTH = 1000
          const INSTALLER_HEIGHT = 650
          const TITLE_BAR_HEIGHT = 45
          const CARD_WIDTH = 280
          const CARD_HEIGHT = 380
          const CARD_SPACING = 35
          
          let windowX = (currentGame.screenWidth - INSTALLER_WIDTH) div 2
          let windowY = (currentGame.screenHeight - INSTALLER_HEIGHT) div 2
          let yPos = windowY + TITLE_BAR_HEIGHT + 75
          let totalCardWidth = CARD_WIDTH * 3 + CARD_SPACING * 2
          let startX = windowX + (INSTALLER_WIDTH - totalCardWidth) div 2
          
          # Check close button click (X button in title bar)
          let closeButtonSize = 28
          let closeButtonX = windowX + INSTALLER_WIDTH - closeButtonSize - 10
          let closeButtonY = windowY + (TITLE_BAR_HEIGHT - closeButtonSize) div 2
          let closeButtonRect = Rectangle(x: closeButtonX.float32, y: closeButtonY.float32,
                                          width: closeButtonSize.float32, height: closeButtonSize.float32)
          
          if checkCollisionPointRec(mousePos, closeButtonRect):
            # Close installer and go to shop
            currentGame.cameFromPowerUpSelect = true
            currentGame.state = gsShop
          else:
            # Check card clicks
            for i in 0..2:
              let cardX = startX + i * (CARD_WIDTH + CARD_SPACING)
              let cardRect = Rectangle(x: cardX.float32, y: yPos.float32,
                                       width: CARD_WIDTH.float32, height: CARD_HEIGHT.float32)
              
              if checkCollisionPointRec(mousePos, cardRect):
                currentGame.selectedPowerUp = i
                let chosenPowerUp = currentGame.powerUpChoices[currentGame.selectedPowerUp]
                applyPowerUp(currentGame.player, chosenPowerUp)
                trackPowerUpSelection(currentGame, chosenPowerUp)
                currentGame.cameFromPowerUpSelect = true
                currentGame.state = gsShop
                break
            
            # Check reroll button click
            let rerollX = windowX + 50
            let rerollWidth = 220
            let bottomY = windowY + INSTALLER_HEIGHT - 120
            let buttonY = bottomY + 15
            let buttonHeight = 42
            
            let rerollRect = Rectangle(x: rerollX.float32, y: buttonY.float32,
                                        width: rerollWidth.float32, height: buttonHeight.float32)
            
            if checkCollisionPointRec(mousePos, rerollRect):
              discard attemptRerollPowerUps(currentGame)
        
        # Skip power-up selection
        if isKeyPressed(Escape):
          currentGame.state = gsCountdown
          currentGame.countdownTimer = 0.5
      
      beginGameDrawing()
      drawPowerUpSelection(currentGame)
      drawCustomCursor(currentGame.time)
      endGameDrawing()
    
    of gsGameOver:
      # Stop music and play game over sound once
      if not currentGame.gameOverSoundPlayed:
        stopMusic()
        playSound(stGameOver, 1.0)
        currentGame.gameOverSoundPlayed = true
        
        # Clear Discord Rich Presence
        if not currentGame.discordClient.isNil:
          clearPresence(currentGame.discordClient)
        
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
          let bossesKilled = if shouldUseWaves(currentGame.mode):
            (currentGame.currentWave - 1) div 5  # Boss every 5 waves
          else:
            currentGame.bossCount
          
          updateStats(stats, 
                     shouldUseWaves(currentGame.mode),
                     currentGame.currentWave,
                     currentGame.time,
                     currentGame.player.kills,
                     currentGame.player.coins,
                     bossesKilled)
          discard saveStatistics(stats)
          statsSavedThisGame = true
      
      # Update mouse tracking
      updateMouseTracking(currentGame)
      
      # Keyboard navigation - A/D/LEFT/RIGHT to change button selection
      if isKeyPressed(Left) or isKeyPressed(A):
        currentGame.selectedGameOverButton = (currentGame.selectedGameOverButton - 1 + 3) mod 3
        playSound(stMenuNav)
        markKeyboardUsed(currentGame)
      elif isKeyPressed(Right) or isKeyPressed(D):
        currentGame.selectedGameOverButton = (currentGame.selectedGameOverButton + 1) mod 3
        playSound(stMenuNav)
        markKeyboardUsed(currentGame)
      
      # Execute action based on selected button or direct key press
      # SPACE and R both trigger restart (button 0)
      if (isKeyPressed(Space) or isKeyPressed(R)) or 
         (isKeyPressed(Enter) and currentGame.selectedGameOverButton == 0):
        # Store the current game mode before restarting
        let previousMode = currentGame.mode
        currentGame = newGame(screenWidth, screenHeight)
        currentGame.discordClient = globalDiscordClient
        setGameMode(currentGame, previousMode)  # Preserve the game mode
        initializeRunTracking(currentGame)  # Start tracking
        currentGame.state = gsPlaying
        playSound(stMenuSelect)
        statsSavedThisGame = false  # Reset for new game
      # TAB or V to view stats (button 1)
      elif (isKeyPressed(Tab) or isKeyPressed(V)) or 
           (isKeyPressed(Enter) and currentGame.selectedGameOverButton == 1):
        if hasValidRunStats():
          currentGame.state = gsRunStats
          playSound(stMenuSelect)
      # ESC or Q to exit (button 2)
      elif (isKeyPressed(Escape) or isKeyPressed(Q)) or 
           (isKeyPressed(Enter) and currentGame.selectedGameOverButton == 2):
        cleanupGame(currentGame)  # Clean up resources before creating new game
        currentGame = newGame(screenWidth, screenHeight)
        currentGame.discordClient = globalDiscordClient
        currentGame.state = gsMenu
        playSound(stMenuSelect)
        statsSavedThisGame = false  # Reset for new game
      
      # Mouse hover detection for button highlighting
      let mousePos = getMousePosition()
      const SCREEN_HEIGHT = 600  # Updated to match new height
      const BUTTON_WIDTH = 220
      const BUTTON_HEIGHT = 48
      
      let windowY = (screenHeight - SCREEN_HEIGHT) div 2
      let buttonY = windowY + SCREEN_HEIGHT - 100  # Updated to match new position
      let buttonSpacing = 40
      let totalButtonWidth = BUTTON_WIDTH * 3 + buttonSpacing * 2
      let buttonsX = (screenWidth - totalButtonWidth) div 2
      
      # Restart button (button 0)
      let restartRect = Rectangle(x: buttonsX.float32, y: buttonY.float32,
                                   width: BUTTON_WIDTH.float32, height: BUTTON_HEIGHT.float32)
      
      # View Stats button (button 1)
      let statsX = buttonsX + BUTTON_WIDTH + buttonSpacing
      let statsRect = Rectangle(x: statsX.float32, y: buttonY.float32,
                                width: BUTTON_WIDTH.float32, height: BUTTON_HEIGHT.float32)
      
      # Exit button (button 2)
      let exitX = statsX + BUTTON_WIDTH + buttonSpacing
      let exitRect = Rectangle(x: exitX.float32, y: buttonY.float32,
                               width: BUTTON_WIDTH.float32, height: BUTTON_HEIGHT.float32)
      
      # Mouse hover - update selected button
      if checkCollisionPointRec(mousePos, restartRect):
        currentGame.selectedGameOverButton = 0
      elif checkCollisionPointRec(mousePos, statsRect):
        currentGame.selectedGameOverButton = 1
      elif checkCollisionPointRec(mousePos, exitRect):
        currentGame.selectedGameOverButton = 2
      
      # Mouse click handling
      if isMouseButtonPressed(Left):
        if checkCollisionPointRec(mousePos, restartRect):
          # Restart game - preserve game mode
          let previousMode = currentGame.mode
          currentGame = newGame(screenWidth, screenHeight)
          currentGame.discordClient = globalDiscordClient
          setGameMode(currentGame, previousMode)  # Preserve the game mode
          initializeRunTracking(currentGame)
          currentGame.state = gsPlaying
          playSound(stMenuSelect)
          statsSavedThisGame = false
        elif checkCollisionPointRec(mousePos, statsRect):
          # View stats
          if hasValidRunStats():
            currentGame.state = gsRunStats
            playSound(stMenuSelect)
        elif checkCollisionPointRec(mousePos, exitRect):
          # Return to menu
          cleanupGame(currentGame)
          currentGame = newGame(screenWidth, screenHeight)
          currentGame.discordClient = globalDiscordClient
          currentGame.state = gsMenu
          playSound(stMenuSelect)
          statsSavedThisGame = false
      
      beginGameDrawing()
      drawGameOver(currentGame)
      
      # Draw custom cursor on game over screen
      drawCustomCursor(currentGame.time)
      
      endGameDrawing()
    
    of gsRunStats:
      # Display detailed run statistics
      
      # Update time for animations
      currentGame.time += dt
      
      # Return to game over with Tab
      if isKeyPressed(Tab):
        currentGame.state = gsGameOver
      
      # Return to game over screen with Escape
      if isKeyPressed(Escape):
        currentGame.state = gsGameOver
      
      # Quick restart
      if isKeyPressed(R):
        currentGame = newGame(screenWidth, screenHeight)
        currentGame.discordClient = globalDiscordClient
        currentGame.mode = gmWaveBased
        initializeRunTracking(currentGame)
        currentGame.state = gsPlaying
        statsSavedThisGame = false
      
      # Return to menu
      if isKeyPressed(Q):
        cleanupGame(currentGame)  # Clean up resources before creating new game
        currentGame = newGame(screenWidth, screenHeight)
        currentGame.discordClient = globalDiscordClient
        currentGame.state = gsMenu
        statsSavedThisGame = false
      
      beginGameDrawing()
      if hasValidRunStats():
        drawGameOverStatsScreen(currentRunStats, screenWidth, screenHeight, 
                               currentGame.time, currentGame.showRunStatsGraphs)
      else:
        # Fallback if no stats available
        clearBackground(Color(r: 20, g: 20, b: 30, a: 255))
        drawText("No statistics available", 
                screenWidth div 2 - 150, screenHeight div 2, 24, Red)
        drawText("Press ESC to return", 
                screenWidth div 2 - 120, screenHeight div 2 + 40, 18, LightGray)
      
      endGameDrawing()
  
  # Cleanup global Discord Rich Presence client
  if not globalDiscordClient.isNil:
    disconnect(globalDiscordClient)
  
  # Cleanup
  stopMusic()
  closeSoundSystem(globalSoundSystem)
  closeWindow()

when isMainModule:
  main()
