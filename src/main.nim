import raylib, types, game, shop, wall, particle, powerup, random, math, strutils

const
  screenWidth = 1024
  screenHeight = 768
  targetFPS = 60

proc drawMenu(game: Game) =
  clearBackground(Color(r: 20, g: 20, b: 30, a: 255))
  
  # Title with pulsing effect
  let pulse = 1.0 + 0.1 * sin(game.time * 3)
  let titleSize = (50 * pulse).int32
  drawText("TopHat SHOOTER", screenWidth div 2 - 220, 150, titleSize, Yellow)
  drawText("CHAOS EDITION", screenWidth div 2 - 150, 200, 25, Red)
  
  # Flashy UPDATE 2! badge with glow effect
  let updatePulse = 1.0 + 0.2 * sin(game.time * 6)
  let updateSize = (28 * updatePulse).int32
  let updateX = screenWidth div 2 - 70
  let updateY = 240
  
  # Glow layers
  for i in 1..3:
    let glowAlpha = uint8(40 * (4 - i))  # already integer, no float needed
    let glowSize: int32 = int32(updateSize + i * 3)
    drawText("UPDATE 2!", int32(updateX - i), int32(updateY - i), glowSize,
            Color(r: 255'u8, g: 100'u8, b: 0'u8, a: glowAlpha))

  # Main update text with gradient effect
  let updateColor = if (game.time * 3).int mod 2 == 0:
    Color(r: 255'u8, g: 150'u8, b: 50'u8, a: 255'u8)
  else:
    Color(r: 255'u8, g: 200'u8, b: 100'u8, a: 255'u8)

  drawText("UPDATE 2!", int32(updateX), int32(updateY), int32(updateSize), updateColor)
  
  # Menu options
  let startY = 340
  let spacing = 60
  
  let menuItems = ["Play", "Survival Mode", "Help", "Quit"]
  for i in 0..<menuItems.len:
    let y = startY + i * spacing
    let color = if i == game.menuSelection: Gold else: White
    let text = if i == game.menuSelection: "> " & menuItems[i] & " <" else: menuItems[i]
    let textWidth = measureText(text, 30)
    drawText(text, screenWidth div 2 - textWidth div 2, y.int32, 30, color)

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
    "TAB - Open Shop",
    "ESC - Pause/Menu",
    "",
    "WAVE-BASED MODE (Main):",
    "Clear waves of enemies for upgrades",
    "Defeat all enemies to advance waves",
    "Boss appears every 3 waves",
    "Choose power-ups after each wave",
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
  
  var currentGame = newGame(screenWidth, screenHeight)
  currentGame.state = gsMenu
  
  while not windowShouldClose():
    let dt = getFrameTime()
    
    case currentGame.state
    of gsMenu:
      # Update time for menu animations
      currentGame.time += dt
      
      # Menu navigation
      if isKeyPressed(Down):
        currentGame.menuSelection = (currentGame.menuSelection + 1) mod 4
      if isKeyPressed(Up):
        currentGame.menuSelection = (currentGame.menuSelection - 1 + 4) mod 4
      
      if isKeyPressed(Enter):
        case currentGame.menuSelection
        of 0:  # Wave-Based Mode
          currentGame = newGame(screenWidth, screenHeight)
          currentGame.mode = gmWaveBased
          currentGame.state = gsPlaying
        of 1:  # Time Survival Mode
          currentGame = newGame(screenWidth, screenHeight)
          currentGame.mode = gmTimeSurvival
          currentGame.state = gsPlaying
        of 2:  # Help
          currentGame.state = gsHelp
        of 3:  # Quit
          break
        else: discard
      
      beginDrawing()
      drawMenu(currentGame)
      endDrawing()
    
    of gsHelp:
      if isKeyPressed(Escape):
        currentGame.state = gsMenu
      
      beginDrawing()
      drawHelp(currentGame)
      endDrawing()
    
    of gsPlaying:
      # Open shop
      if isKeyPressed(Tab):
        currentGame.state = gsShop
      
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
      
      updateGame(currentGame, dt)
      
      beginDrawing()
      drawGame(currentGame)
      endDrawing()
    
    of gsPaused:
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
      # Navigate shop
      if isKeyPressed(Down):
        currentGame.selectedShopItem = (currentGame.selectedShopItem + 1) mod 6
      if isKeyPressed(Up):
        currentGame.selectedShopItem = (currentGame.selectedShopItem - 1 + 6) mod 6
      
      # Buy item
      if isKeyPressed(Enter):
        buyShopItem(currentGame, currentGame.selectedShopItem)
      
      # Close shop - start countdown
      if isKeyPressed(Tab) or isKeyPressed(Escape):
        currentGame.state = gsCountdown
        currentGame.countdownTimer = 0.5
      
      beginDrawing()
      drawGame(currentGame)
      drawShop(currentGame)
      endDrawing()
    
    of gsCountdown:
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
      # Navigate power-up choices
      if isKeyPressed(Left):
        currentGame.selectedPowerUp = (currentGame.selectedPowerUp - 1 + 3) mod 3
      if isKeyPressed(Right):
        currentGame.selectedPowerUp = (currentGame.selectedPowerUp + 1) mod 3
      
      # Select power-up
      if isKeyPressed(Enter):
        applyPowerUp(currentGame.player, currentGame.powerUpChoices[currentGame.selectedPowerUp])
        currentGame.state = gsCountdown
        currentGame.countdownTimer = 0.5
      
      beginDrawing()
      drawPowerUpSelection(currentGame)
      endDrawing()
    
    of gsGameOver:
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
  
  closeWindow()

when isMainModule:
  main()
