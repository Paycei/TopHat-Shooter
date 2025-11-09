import raylib, types, game, shop, wall, particle, powerup, random, math, strutils, sound, settings, cheat

const
  screenWidth = 1024
  screenHeight = 768
  targetFPS = 60

proc drawMenu(game: Game) =
  clearBackground(Color(r: 20, g: 20, b: 30, a: 255))
  
  # Subtle animated background particles (reduced from 50 to 25)
  for i in 0..<25:
    let offset = i.float32 * 0.7
    let x = ((game.time * 20.0 + offset * 20) mod screenWidth.float32).int32
    let y = ((game.time * 10.0 + offset * 40) mod screenHeight.float32).int32
    let size = 2 + (sin(game.time * 2.0 + offset) * 1).int32
    let alpha = uint8(30 + sin(game.time * 2.0 + offset) * 15)
    drawCircle(Vector2(x: x.float32, y: y.float32), size.float32, 
              Color(r: 100'u8, g: 150'u8, b: 255'u8, a: alpha))
  
  # Reduced rotating shapes (from 8 to 4)
  for i in 0..<4:
    let angle = game.time * 0.3 + i.float32 * PI / 2.0
    let radius = 120.0 + sin(game.time * 1.5 + i.float32) * 30.0
    let x = screenWidth.float32 / 2 + cos(angle) * radius
    let y = 120.0 + sin(angle) * radius * 0.5
    let size = 12 + (sin(game.time * 2.0 + i.float32) * 5).int32
    let alpha = uint8(20 + (sin(game.time * 2.0 + i.float32) * 10))
    drawCircle(Vector2(x: x, y: y), size.float32, 
              Color(r: 255'u8, g: 200'u8, b: 50'u8, a: alpha))
  
  # Title with subtle pulse (reduced from 0.15 to 0.08)
  let pulse = 1.0 + 0.08 * sin(game.time * 3)
  let titleSize = (55 * pulse).int32
  
  # Simplified title glow (single layer instead of 3)
  drawText("TopHat SHOOTER", 
          (screenWidth div 2 - 218).int32, 151.int32, 
          (titleSize + 2).int32,
          Color(r: 255'u8, g: 255'u8, b: 0'u8, a: 40'u8))
  
  drawText("TopHat SHOOTER", screenWidth div 2 - 220, 150, titleSize, Yellow)
  
  # Simplified subtitle (removed shake and color change)
  drawText("CHAOS EDITION", screenWidth div 2 - 150, 200, 28, Orange)
  
  # Simplified UPDATE 2! badge (removed extreme effects)
  let updateSize = 30
  let updateX = screenWidth div 2 - 80
  let updateY = 245
  
  # Simple glow
  drawText("UPDATE 2!", int32(updateX - 1), int32(updateY - 1), updateSize.int32,
          Color(r: 255'u8, g: 120'u8, b: 0'u8, a: 80'u8))
  
  drawText("UPDATE 2!", int32(updateX), int32(updateY), updateSize.int32, Gold)
  
  # Menu options with minimal animation
  let startY = 360
  let spacing = 65
  
  let menuItems = ["Play", "Survival Mode", "Settings", "Help", "Quit"]
  for i in 0..<menuItems.len:
    let y = startY + i * spacing
    let isSelected = i == game.menuSelection
    
    # selection glow
    if isSelected:
      let glowPulse = sin(game.time * 6.0) * 0.3 + 0.7
      let glowSize = 15 + (glowPulse * 10).int32
      drawCircle(Vector2(x: (screenWidth div 2).float32, y: y.float32 + 15),
                glowSize.float32, Color(r: 255'u8, g: 200'u8, b: 0'u8, a: 80'u8))
    
    let color = if isSelected: Gold else: White
    let text = if isSelected: "> " & menuItems[i] else: menuItems[i]
    let textWidth = measureText(text, 32)
    
    drawText(text, screenWidth div 2 - textWidth div 2, y.int32, 32, color)
  
  # crosshair cursor
  let mousePos = getMousePosition()
  let cursorPulse = sin(game.time * 8.0) * 2 + 8
  
  # Outer rotating ring
  for i in 0..<8:
    let angle = game.time * 4.0 + i.float32 * PI / 4.0
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

proc drawHelp(game: Game) =
  clearBackground(Color(r: 20, g: 20, b: 30, a: 255))
  
  drawText("HOW TO PLAY", screenWidth div 2 - 130, 50, 40, Yellow)
  
  var y: int32 = 130
  let instructions = [
    "CONTROLS:",
    "WASD - Move",
    "Mouse/Space - Shoot",
    "F - Toggle Auto-Shoot (requires powerup)",
    "E - Place Wall (requires walls in inventory)",
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
    "",
    "ENEMIES:",
    "Circles - Basic chasers",
    "Cubes - Ranged shooters",
    "Stars - Tanky targets",
    "Triangles - Dash attackers",
    "Hexagons - Teleporting chaos",
    "Bosses - Shape-shift with special attacks"
  ]
  
  for line in instructions:
    if line.len > 0:
      drawText(line, 120, y, 18, White)
    y += 22
  
  drawText("Press ESC to return", screenWidth div 2 - 130, screenHeight - 60, 20, LightGray)

proc main() =
  randomize()
  
  initWindow(screenWidth, screenHeight, "TopHat-Shooter: Chaos Edition")
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
  
  var currentGame = newGame(screenWidth, screenHeight)
  currentGame.state = gsMenu
  
  while not windowShouldClose():
    let dt = getFrameTime()
    
    # Update music stream (required for continuous playback)
    updateMusic()
    
    case currentGame.state
    of gsMenu:
      # Play menu music
      playMusic(mtMenu)
      
      # Update time for menu animations
      currentGame.time += dt
      
      # Menu navigation
      if isKeyPressed(Down):
        currentGame.menuSelection = (currentGame.menuSelection + 1) mod 5
        playSound(stMenuNav)
      if isKeyPressed(Up):
        currentGame.menuSelection = (currentGame.menuSelection - 1 + 5) mod 5
        playSound(stMenuNav)
      
      if isKeyPressed(Enter):
        playSound(stMenuSelect)
        case currentGame.menuSelection
        of 0:  # Wave-Based Mode
          currentGame = newGame(screenWidth, screenHeight)
          currentGame.mode = gmWaveBased
          currentGame.state = gsPlaying
        of 1:  # Time Survival Mode
          currentGame = newGame(screenWidth, screenHeight)
          currentGame.mode = gmTimeSurvival
          currentGame.state = gsPlaying
        of 2:  # Settings
          currentGame.state = gsSettings
        of 3:  # Help
          currentGame.state = gsHelp
        of 4:  # Quit
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
        currentGame.state = gsMenu
        setGameVolume(settings.volume)  # Apply volume changes
        setMusicVolume(settings.musicVolume)  # Apply music volume changes
        playSound(stMenuSelect)
      
      updateSettings(settings)
      
      beginDrawing()
      drawSettings(settings, screenWidth, screenHeight)
      endDrawing()
    
    of gsPlaying:
      # Dynamic music based on game state
      if currentGame.bossActive:
        playMusic(mtBoss)
      else:
        playMusic(mtWave)
      
      # Check for cheat menu activation
      checkCheatSequence(cheatMenu, currentGame.time)
      
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

      # Toggle auto-shoot with F key
      if isKeyPressed(F) and hasPowerUp(currentGame.player, puAutoShoot):
        currentGame.player.autoShootEnabled = not currentGame.player.autoShootEnabled
        let feedbackColor = if currentGame.player.autoShootEnabled: Green else: Red
        spawnExplosion(currentGame.particles, currentGame.player.pos.x, currentGame.player.pos.y, 
                      feedbackColor, 20)
      
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
      
      if isKeyPressed(Escape):
        currentGame.state = gsPlaying
      
      beginDrawing()
      drawGame(currentGame)
      
      # Draw pause overlay
      drawRectangle(0, 0, screenWidth, screenHeight, Color(r: 0, g: 0, b: 0, a: 150))
      drawText("PAUSED", screenWidth div 2 - 100, screenHeight div 2 - 40, 50, White)
      drawText("Press ESC to resume", screenWidth div 2 - 120, screenHeight div 2 + 20, 20, LightGray)
      endDrawing()
    
    of gsShop:
      # Play power-up music in shop
      playMusic(mtPowerUp)
      
      # Navigate shop
      if isKeyPressed(Down):
        currentGame.selectedShopItem = (currentGame.selectedShopItem + 1) mod 6
      if isKeyPressed(Up):
        currentGame.selectedShopItem = (currentGame.selectedShopItem - 1 + 6) mod 6
      
      # Buy item
      if isKeyPressed(Enter):
        buyShopItem(currentGame, currentGame.selectedShopItem)
      
      # Close shop - always continue to next wave (no going back to power-up selection)
      if isKeyPressed(Escape):
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
      let alpha = uint8(200.0 * (countdownValue + 0.3))
      
      # Dark overlay that fades out
      drawRectangle(0, 0, screenWidth, screenHeight, 
                   Color(r: 0, g: 0, b: 0, a: alpha))
      
      # Countdown text with scale pulse
      let textSize = (120 * pulse).int32
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
      let subtitle = "Get Ready!"
      let subWidth = measureText(subtitle, 30)
      drawText(subtitle,
              screenWidth div 2 - subWidth div 2,
              screenHeight div 2 + 80,
              30,
              Color(r: 200, g: 200, b: 200, a: alpha))
      
      endDrawing()
    
    of gsPowerUpSelect:
      # Play power-up selection music
      playMusic(mtPowerUp)
      
      # Navigate power-up choices
      if isKeyPressed(Left):
        currentGame.selectedPowerUp = (currentGame.selectedPowerUp - 1 + 3) mod 3
      if isKeyPressed(Right):
        currentGame.selectedPowerUp = (currentGame.selectedPowerUp + 1) mod 3
      
      # Select power-up
      if isKeyPressed(Enter):
        applyPowerUp(currentGame.player, currentGame.powerUpChoices[currentGame.selectedPowerUp])
        # Automatically go to shop after power-up selection
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
      
      if isKeyPressed(R):
        currentGame = newGame(screenWidth, screenHeight)
        currentGame.mode = gmWaveBased  # Default to wave-based on restart
        currentGame.state = gsPlaying
      
      if isKeyPressed(Escape):
        currentGame = newGame(screenWidth, screenHeight)
        currentGame.state = gsMenu
      
      beginDrawing()
      drawGameOver(currentGame)
      endDrawing()
  
  # Cleanup
  stopMusic()
  closeSoundSystem(globalSoundSystem)
  closeWindow()

when isMainModule:
  main()
