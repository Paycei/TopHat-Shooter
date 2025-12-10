import raylib, types, game, shop, wall, particle, powerup, player, coin, random, math, strutils, sound, settings, cheat

const
  screenWidth = 1024
  screenHeight = 768
  targetFPS = 60

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
  clearBackground(Color(r: 20, g: 20, b: 30, a: 255))
  
  # Subtle animated background particles
  for i in 0..<25:
    let offset = i.float32 * 0.7
    let x = ((game.time * 20.0 + offset * 20) mod screenWidth.float32).int32
    let y = ((game.time * 10.0 + offset * 40) mod screenHeight.float32).int32
    let size = 2 + (sin(game.time * 2.0 + offset) * 1).int32
    let alpha = uint8(30 + sin(game.time * 2.0 + offset) * 15)
    drawCircle(Vector2(x: x.float32, y: y.float32), size.float32, 
              Color(r: 100'u8, g: 150'u8, b: 255'u8, a: alpha))
  
  # Gentle floating orbs around title
  for i in 0..<6:
    let angle = game.time * 0.4 + i.float32 * PI / 3.0
    let radius = 150.0 + sin(game.time * 1.2 + i.float32) * 20.0
    let x = screenWidth.float32 / 2 + cos(angle) * radius
    let y = 140.0 + sin(angle) * radius * 0.4
    let size = 8 + (sin(game.time * 2.0 + i.float32) * 3).int32
    let alpha = uint8(25 + (sin(game.time * 2.0 + i.float32) * 12))
    drawCircle(Vector2(x: x, y: y), size.float32, 
              Color(r: 255'u8, g: 200'u8, b: 50'u8, a: alpha))
  
  # Title with subtle wave effect
  let titleText = "TopHat SHOOTER"
  let baseY = 150
  let baseTitleSize = 55
  
  # Gentle glow
  drawText(titleText, screenWidth.int32 div 2 - 218, 151, baseTitleSize.int32 + 2,
          Color(r: 255'u8, g: 255'u8, b: 0'u8, a: 50'u8))
  
  # Main title with subtle per-character wave
  for i in 0..<titleText.len:
    let charWave = sin(game.time * 3.0 + i.float32 * 0.4) * 2.0
    let charX = screenWidth div 2 - 220 + i * 31
    let charY = baseY.float32 + charWave
    drawText($titleText[i], charX.int32, charY.int32, baseTitleSize.int32, Yellow)
  
  # Subtitle with gentle pulse
  let subtitlePulse = 1.0 + sin(game.time * 2.5) * 0.06
  let subtitleSize = (28.float32 * subtitlePulse).int32
  drawText("CHAOS EDITION", screenWidth div 2 - 150, 200, subtitleSize, Orange)
  
  # UPDATE 3 badge with subtle glow
  let updateX = screenWidth div 2 - 80
  let updateY = 245
  let updatePulse = 1.0 + sin(game.time * 4.0) * 0.1
  let updateSize = (30.float32 * updatePulse).int32
  
  drawText("UPDATE 3!", int32(updateX - 1), int32(updateY - 1), updateSize + 2,
          Color(r: 255'u8, g: 120'u8, b: 0'u8, a: 80'u8))
  drawText("UPDATE 3!", int32(updateX), int32(updateY), updateSize, Gold)
  
  # Menu options with subtle selection indicator
  let startY = 360
  let spacing = 65
  
  let menuItems = ["Play", "Survival Mode", "Settings", "Help", "Quit"]
  
  # Mouse hover detection (only if mouse support is enabled)
  if globalSettings.mouseSupport:
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
  
  # Draw custom cursor only if system cursor is hidden
  if not isCursorOnScreen():
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
  
  # Draw custom cursor only if system cursor is hidden
  if not isCursorOnScreen():
    drawCustomCursor(game.time)
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
    
    # Handle fullscreen toggle with F11
    if isKeyPressed(F11):
      settings.fullscreen = not settings.fullscreen
      toggleFullscreen()
    
    # Control cursor visibility based on game state and settings
    case currentGame.state
    of gsMenu, gsHelp, gsShop, gsPowerUpSelect:
      # In menu states, mouse support setting determines cursor behavior
      if settings.mouseSupport:
        showCursor()
      else:
        hideCursor()
    of gsSettings:
      # Always show cursor in settings (needed for interaction)
      showCursor()
    of gsPlaying, gsPaused, gsWaveCleared, gsCountdown, gsGameOver:
      # Always hide cursor during gameplay (custom cursor used)
      hideCursor()
    else:
      hideCursor()
    
    case currentGame.state
    of gsMenu:
      # Play menu music
      playMusic(mtMenu)
      
      # Update time for menu animations
      currentGame.time += dt
      
      # Menu navigation
      if isKeyPressed(Down) or isKeyPressed(S):
        currentGame.menuSelection = (currentGame.menuSelection + 1) mod 5
        playSound(stMenuNav)
      if isKeyPressed(Up) or isKeyPressed(W):
        currentGame.menuSelection = (currentGame.menuSelection - 1 + 5) mod 5
        playSound(stMenuNav)
      
      if isKeyPressed(Enter) or isKeyPressed(E) or isMouseButtonPressed(Left):
        # For mouse clicks, verify we're clicking on a menu item (only if mouse support enabled)
        var validClick = isKeyPressed(Enter) or isKeyPressed(E)
        if not validClick and isMouseButtonPressed(Left) and settings.mouseSupport:
          let mousePos = getMousePosition()
          let startY = 360
          let spacing = 65
          let menuItems = ["Play", "Survival Mode", "Settings", "Help", "Quit"]
          
          for i in 0..<menuItems.len:
            let y = startY + i * spacing
            let text = if i == currentGame.menuSelection: "> " & menuItems[i] & " <" else: menuItems[i]
            let textWidth = measureText(text, 32)
            let textX = screenWidth div 2 - textWidth div 2
            
            if mousePos.x >= textX.float32 and mousePos.x <= (textX + textWidth).float32 and
               mousePos.y >= y.float32 and mousePos.y <= (y + 32).float32:
              validClick = true
              break
        
        if validClick:
          playSound(stMenuSelect)
          case currentGame.menuSelection
          of 0:  # Wave-Based Mode
            currentGame = newGame(screenWidth, screenHeight)
            currentGame.mode = gmWaveBased
            currentGame.state = gsPlaying  # Start playing immediately
          of 1:  # Time Survival Mode
            currentGame = newGame(screenWidth, screenHeight)
            currentGame.mode = gmTimeSurvival
            currentGame.state = gsPlaying  # Start playing immediately
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
      drawSettings(settings, screenWidth, screenHeight, currentGame.time)
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
          
          let cooldown = 10.0  # 10 second cooldown
          let invulnDuration = 0.6
          
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
      
      # Navigate shop with keyboard
      if isKeyPressed(Down) or isKeyPressed(S):
        currentGame.selectedShopItem = (currentGame.selectedShopItem + 1) mod 6
      if isKeyPressed(Up) or isKeyPressed(W):
        currentGame.selectedShopItem = (currentGame.selectedShopItem - 1 + 6) mod 6
      
      # Buy item with keyboard or mouse
      if isKeyPressed(Enter) or isKeyPressed(E) or isMouseButtonPressed(Left):
        # For mouse clicks, verify we're clicking on a shop item (only if mouse support enabled)
        var validClick = isKeyPressed(Enter) or isKeyPressed(E)
        if not validClick and isMouseButtonPressed(Left) and settings.mouseSupport:
          let mousePos = getMousePosition()
          let shopStartX = currentGame.screenWidth div 2 - 200
          let startY = 120
          let itemHeight = 70
          
          for i in 0..5:
            let y = startY + i * itemHeight
            if mousePos.x >= shopStartX.float32 and mousePos.x <= (shopStartX + 400).float32 and
               mousePos.y >= y.float32 and mousePos.y <= (y + 60).float32:
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
          currentGame.player.coins += currentGame.coins[i].value
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
      
      # Only allow input after animation completes
      if currentGame.canSelectPowerUp:
        # Navigate power-up choices with keyboard
        if isKeyPressed(Left) or isKeyPressed(A):
          currentGame.selectedPowerUp = (currentGame.selectedPowerUp - 1 + 3) mod 3
        if isKeyPressed(Right) or isKeyPressed(D):
          currentGame.selectedPowerUp = (currentGame.selectedPowerUp + 1) mod 3
        
        # Select power-up with keyboard or mouse
        if isKeyPressed(Enter) or isKeyPressed(E) or isMouseButtonPressed(Left):
          # For mouse clicks, verify we're clicking on a card (only if mouse support enabled)
          var validClick = isKeyPressed(Enter) or isKeyPressed(E)
          if not validClick and isMouseButtonPressed(Left) and settings.mouseSupport:
            let mousePos = getMousePosition()
            let cardWidth = 200
            let cardHeight = 240
            let spacing = 40
            let totalWidth = cardWidth * 3 + spacing * 2
            let startX = (currentGame.screenWidth - totalWidth) div 2
            let cardY = if currentGame.powerUpChoices[0].rarity == prLegendary: 160 else: 180
            
            for i in 0..2:
              let cardX = startX + i * (cardWidth + spacing)
              if mousePos.x >= cardX.float32 and mousePos.x <= (cardX + cardWidth).float32 and
                 mousePos.y >= cardY.float32 and mousePos.y <= (cardY + cardHeight).float32:
                validClick = true
                break
          
          if validClick:
            applyPowerUp(currentGame.player, currentGame.powerUpChoices[currentGame.selectedPowerUp])
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
      
      if isKeyPressed(Escape) or isKeyPressed(Q):
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
