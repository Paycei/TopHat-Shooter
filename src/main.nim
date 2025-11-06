import raylib, types, game, shop, wall, particle, random, math

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
  
  # Menu options
  let startY = 320
  let spacing = 60
  
  let menuItems = ["Start Game", "Help", "Quit"]
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
    "WASD - Move",
    "Mouse/Space - Shoot",
    "F - Toggle Auto-Shoot",
    "E - Place Wall (requires walls in inventory)",
    "TAB - Open Shop",
    "ESC - Pause/Menu",
    "",
    "ENEMIES (unlock progressively):",
    "Phase 1: Circles - Basic chasers",
    "Phase 2: Cubes - Ranged shooters (10s)",
    "Phase 3: Stars - Tanky targets (25s)",
    "Phase 4: Triangles - Dash attackers (40s)",
    "Phase 5: Full chaos! (60s+)",
    "Bosses: Shape-shift with crazy attacks",
    "",
    "POWERUPS:",
    "+ (Green) - Health",
    "$ (Gold) - 5 Coins",
    "S (Cyan) - Speed Boost",
    "! (Magenta) - Invincibility",
    "F (Orange) - Fire Rate Boost",
    "M (Purple) - Coin Magnet",
    "",
    "Survive the progressive chaos as long as possible!"
  ]
  
  for line in instructions:
    if line.len > 0:
      drawText(line, 150, y, 20, White)
    y += 25
  
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
        currentGame.menuSelection = (currentGame.menuSelection + 1) mod 3
      if isKeyPressed(Up):
        currentGame.menuSelection = (currentGame.menuSelection - 1 + 3) mod 3
      
      if isKeyPressed(Enter):
        case currentGame.menuSelection
        of 0:  # Start Game
          currentGame = newGame(screenWidth, screenHeight)
          currentGame.state = gsPlaying
        of 1:  # Help
          currentGame.state = gsHelp
        of 2:  # Quit
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
      # Toggle auto-shoot
      if isKeyPressed(F):
        currentGame.player.autoShoot = not currentGame.player.autoShoot
      
      # Open shop
      if isKeyPressed(Tab):
        currentGame.state = gsShop
      
      # Place wall
      if isKeyPressed(E) and currentGame.player.walls > 0:
        let mousePos = getMousePosition()
        let wallPos = newVector2f(mousePos.x, mousePos.y)
        
        if isValidWallPlacement(wallPos, currentGame.player.pos, currentGame.walls, 
                                currentGame.enemies, 25):
          currentGame.walls.add(newWall(mousePos.x, mousePos.y))
          currentGame.player.walls -= 1
          spawnExplosion(currentGame.particles, mousePos.x, mousePos.y, Brown, 15)
      
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
      
      # Close shop
      if isKeyPressed(Tab) or isKeyPressed(Escape):
        currentGame.state = gsPlaying
      
      beginDrawing()
      drawGame(currentGame)
      drawShop(currentGame)
      endDrawing()
    
    of gsGameOver:
      if isKeyPressed(R):
        currentGame = newGame(screenWidth, screenHeight)
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
