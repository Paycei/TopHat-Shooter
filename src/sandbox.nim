# SANDBOX MODE - Testing and Development Tools

import raylib, types, enemy, powerup, boss_definitions, std/strutils, random

const
  SIDEBAR_WIDTH = 300
  SIDEBAR_PADDING = 10
  BUTTON_HEIGHT = 35
  BUTTON_SPACING = 5
  TAB_HEIGHT = 40
  SCROLL_SPEED = 20

# UI DRAWING
proc drawEnemiesTab(game: Game, sidebarX, startY, screenHeight: int32) =
  var currentY: int32 = startY + 10 - game.sandboxScrollOffset
  let contentX: int32 = sidebarX + SIDEBAR_PADDING
  let buttonWidth: int32 = SIDEBAR_WIDTH - SIDEBAR_PADDING * 2
  
  drawText("Spawn Enemies:", contentX, currentY, 18, White)
  currentY += 25
  
  # List all enemy types with spawn buttons
  let enemyTypes = [
    ("Circle", etCircle, "Normal chasers"),
    ("Cube", etCube, "Stationary/slow shooters"),
    ("Triangle", etTriangle, "Fast dash attackers"),
    ("Star", etStar, "High HP, needs many hits"),
    ("Hexagon", etHexagon, "Teleporting chaos enemy"),
    ("Cross", etCross, "Cross-shaped attack pattern"),
    ("Diamond", etDiamond, "Shoots while dashing"),
    ("Octagon", etOctagon, "Many slow projectiles"),
    ("Pentagon", etPentagon, "Single fast bullet"),
    ("Trickster", etTrickster, "False warnings, unpredictable"),
    ("Phantom", etPhantom, "Teleports with fake clones"),
    ("Sniper", etSniper, "Charges one-shot attack"),
    ("Mage", etMage, "Summons meteorites")
  ]
  
  for (name, enemyType, desc) in enemyTypes:
    if currentY > startY - 50 and currentY < screenHeight - 50:  # Only draw visible items
      drawRectangle(contentX, currentY, buttonWidth, BUTTON_HEIGHT, Color(r: 70, g: 70, b: 120, a: 255))
      drawRectangleLines(contentX, currentY, buttonWidth, BUTTON_HEIGHT, Color(r: 100, g: 100, b: 150, a: 255))
      drawText(name, contentX + 5, currentY + 5, 16, White)
      drawText(desc, contentX + 5, currentY + 20, 12, Color(r: 180, g: 180, b: 180, a: 255))
    currentY += BUTTON_HEIGHT + BUTTON_SPACING
  
  # Add spawn multiple enemies button
  currentY += 10
  if currentY > startY - 50 and currentY < screenHeight - 50:
    drawRectangle(contentX, currentY, buttonWidth, BUTTON_HEIGHT, Color(r: 120, g: 70, b: 70, a: 255))
    drawText("Spawn 10 Random", contentX + 5, currentY + 10, 16, Yellow)

proc drawBossesTab(game: Game, sidebarX, startY, screenHeight: int32) =
  var currentY: int32 = startY + 10 - game.sandboxScrollOffset
  let contentX: int32 = sidebarX + SIDEBAR_PADDING
  let buttonWidth: int32 = SIDEBAR_WIDTH - SIDEBAR_PADDING * 2
  
  drawText("Spawn Bosses:", contentX, currentY, 18, White)
  currentY += 25
  
  # Dynamically fetch all boss definitions
  for bossId in 1..12:
    let bossDef = getBossDefinition(bossId)
    
    if currentY > startY - 50 and currentY < screenHeight - 50:
      drawRectangle(contentX, currentY, buttonWidth, BUTTON_HEIGHT, Color(r: 120, g: 50, b: 50, a: 255))
      drawRectangleLines(contentX, currentY, buttonWidth, BUTTON_HEIGHT, Color(r: 150, g: 80, b: 80, a: 255))
      drawText($bossId & ". " & bossDef.name, contentX + 5, currentY + 5, 16, Red)
      drawText(bossDef.description, contentX + 5, currentY + 20, 12, Color(r: 200, g: 150, b: 150, a: 255))
    currentY += BUTTON_HEIGHT + BUTTON_SPACING

proc drawControlsTab(game: Game, sidebarX, startY, screenHeight: int32) =
  var currentY: int32 = startY + 10
  let contentX: int32 = sidebarX + SIDEBAR_PADDING
  let buttonWidth: int32 = SIDEBAR_WIDTH - SIDEBAR_PADDING * 2
  
  # God Mode toggle
  let godModeColor = if game.sandboxGodMode: Green else: Color(r: 80, g: 80, b: 80, a: 255)
  drawRectangle(contentX, currentY, buttonWidth, BUTTON_HEIGHT, godModeColor)
  drawText("God Mode: " & (if game.sandboxGodMode: "ON" else: "OFF"), contentX + 5, currentY + 10, 16, White)
  currentY += BUTTON_HEIGHT + BUTTON_SPACING + 5
  
  # Freeze Enemies toggle
  let freezeColor = if game.sandboxFreezeEnemies: Color(r: 100, g: 150, b: 255, a: 255) else: Color(r: 80, g: 80, b: 80, a: 255)
  drawRectangle(contentX, currentY, buttonWidth, BUTTON_HEIGHT, freezeColor)
  drawText("Freeze Enemies: " & (if game.sandboxFreezeEnemies: "ON" else: "OFF"), contentX + 5, currentY + 10, 16, White)
  currentY += BUTTON_HEIGHT + BUTTON_SPACING + 5
  
  # Clear All Enemies button
  drawRectangle(contentX, currentY, buttonWidth, BUTTON_HEIGHT, Color(r: 150, g: 50, b: 50, a: 255))
  drawText("Clear All Enemies", contentX + 5, currentY + 10, 16, White)
  currentY += BUTTON_HEIGHT + BUTTON_SPACING + 10
  
  # Wave controls
  drawText("Wave: " & $game.currentWave, contentX, currentY, 16, White)
  currentY += 25
  drawRectangle(contentX, currentY, buttonWidth div 2 - 3, BUTTON_HEIGHT, Color(r: 80, g: 80, b: 120, a: 255))
  drawText("Wave -", contentX + 5, currentY + 10, 16, White)
  drawRectangle(contentX + buttonWidth div 2 + 3, currentY, buttonWidth div 2 - 3, BUTTON_HEIGHT, Color(r: 80, g: 80, b: 120, a: 255))
  drawText("Wave +", contentX + buttonWidth div 2 + 8, currentY + 10, 16, White)
  currentY += BUTTON_HEIGHT + BUTTON_SPACING + 10
  
  # Difficulty controls
  drawText("Difficulty: " & formatFloat(game.difficulty, ffDecimal, 1), contentX, currentY, 16, White)
  currentY += 25
  drawRectangle(contentX, currentY, buttonWidth div 2 - 3, BUTTON_HEIGHT, Color(r: 120, g: 80, b: 80, a: 255))
  drawText("Diff -", contentX + 5, currentY + 10, 16, White)
  drawRectangle(contentX + buttonWidth div 2 + 3, currentY, buttonWidth div 2 - 3, BUTTON_HEIGHT, Color(r: 120, g: 80, b: 80, a: 255))
  drawText("Diff +", contentX + buttonWidth div 2 + 8, currentY + 10, 16, White)
  currentY += BUTTON_HEIGHT + BUTTON_SPACING + 10
  
  # Player stats
  drawText("HP: " & $game.player.hp & "/" & $game.player.maxHp, contentX, currentY, 14, White)
  currentY += 20
  drawText("Coins: " & $game.player.coins, contentX, currentY, 14, Gold)
  currentY += 20
  drawText("Enemies: " & $game.enemies.len, contentX, currentY, 14, White)
  currentY += 25
  
  # Heal button
  drawRectangle(contentX, currentY, buttonWidth, BUTTON_HEIGHT, Color(r: 50, g: 150, b: 50, a: 255))
  drawText("Heal to Full HP", contentX + 5, currentY + 10, 16, White)
  currentY += BUTTON_HEIGHT + BUTTON_SPACING + 5
  
  # Add coins button
  drawRectangle(contentX, currentY, buttonWidth, BUTTON_HEIGHT, Color(r: 180, g: 140, b: 0, a: 255))
  drawText("Add 1000 Coins", contentX + 5, currentY + 10, 16, White)
  currentY += BUTTON_HEIGHT + BUTTON_SPACING + 10
  
  # Open Shop button
  drawRectangle(contentX, currentY, buttonWidth, BUTTON_HEIGHT, Color(r: 70, g: 120, b: 180, a: 255))
  drawText("Open Shop", contentX + 5, currentY + 10, 16, White)
  currentY += BUTTON_HEIGHT + BUTTON_SPACING + 5
  
  # Open Power-Up Selection button
  drawRectangle(contentX, currentY, buttonWidth, BUTTON_HEIGHT, Color(r: 120, g: 70, b: 180, a: 255))
  drawText("Roll Power-Ups", contentX + 5, currentY + 10, 16, White)

proc drawSandboxSidebar*(game: Game, screenWidth, screenHeight: int32) =
  if not game.sandboxSidebarOpen:
    # Draw toggle button when closed
    let toggleX = screenWidth - 50
    let toggleY = screenHeight div 2 - 30
    drawRectangle(toggleX, toggleY, 40, 60, Color(r: 50, g: 50, b: 50, a: 200))
    drawText(">>", toggleX + 8, toggleY + 18, 24, White)
    return
  
  # Draw sidebar background
  let sidebarX = screenWidth - SIDEBAR_WIDTH
  drawRectangle(sidebarX, 0, SIDEBAR_WIDTH, screenHeight, Color(r: 40, g: 40, b: 40, a: 230))
  
  # Draw close button
  let closeX = sidebarX + SIDEBAR_WIDTH - 35
  drawRectangle(closeX, 5, 30, 30, Color(r: 150, g: 50, b: 50, a: 255))
  drawText("X", closeX + 8, 8, 20, White)
  
  # Draw title
  drawText("SANDBOX MODE", sidebarX + 10, 10, 20, Yellow)
  
  # Draw tabs
  let tabs = ["Enemies", "Bosses", "Controls"]
  let tabWidth: int32 = (SIDEBAR_WIDTH - SIDEBAR_PADDING * 4) div 3
  var currentY: int32 = 45
  
  for i, tabName in tabs:
    let tabX = sidebarX + SIDEBAR_PADDING + i * (tabWidth + SIDEBAR_PADDING)
    let tabColor = if i == game.sandboxSelectedTab: 
      Color(r: 70, g: 130, b: 180, a: 255) 
    else: 
      Color(r: 60, g: 60, b: 60, a: 255)
    drawRectangle(int32(tabX), int32(currentY), int32(tabWidth), int32(TAB_HEIGHT - 5), tabColor)
    let textWidth = measureText(tabName, 16)
    drawText(tabName, int32(tabX + (tabWidth - textWidth) div 2), int32(currentY + 10), int32(16), White)
  
  currentY += TAB_HEIGHT + 5
  
  # Draw content based on selected tab
  case game.sandboxSelectedTab
  of 0:  # Enemies tab
    drawEnemiesTab(game, sidebarX, currentY, screenHeight)
  of 1:  # Bosses tab
    drawBossesTab(game, sidebarX, currentY, screenHeight)
  of 2:  # Controls tab
    drawControlsTab(game, sidebarX, currentY, screenHeight)
  else:
    discard

# INPUT HANDLING
proc handleEnemiesTabClick(game: Game, mousePos: Vector2, sidebarX, screenWidth, screenHeight: int32) =
  let startY = 45 + TAB_HEIGHT + 5
  var currentY = startY + 35 - game.sandboxScrollOffset  # After "Spawn Enemies:" text
  let contentX = sidebarX + SIDEBAR_PADDING
  let buttonWidth = SIDEBAR_WIDTH - SIDEBAR_PADDING * 2
  
  let enemyTypes = [etCircle, etCube, etTriangle, etStar, etHexagon, etCross, 
                    etDiamond, etOctagon, etPentagon, etTrickster, etPhantom, etSniper, etMage]
  
  for enemyType in enemyTypes:
    if mousePos.x >= contentX.float32 and mousePos.x <= (contentX + buttonWidth).float32 and
       mousePos.y >= currentY.float32 and mousePos.y <= (currentY + BUTTON_HEIGHT).float32:
      # Spawn enemy from side of screen (same as wave mode)
      let side = rand(3)
      var spawnX, spawnY: float32
      case side
      of 0: spawnX = rand(screenWidth.int).float32; spawnY = -30
      of 1: spawnX = screenWidth.float32 + 30; spawnY = rand(screenHeight.int).float32
      of 2: spawnX = rand(screenWidth.int).float32; spawnY = screenHeight.float32 + 30
      else: spawnX = -30; spawnY = rand(screenHeight.int).float32
      
      let enemy = newEnemy(spawnX, spawnY, game.difficulty, enemyType, game)
      game.enemies.add(enemy)
      return
    currentY += BUTTON_HEIGHT + BUTTON_SPACING
  
  # Check "Spawn 10 Random" button
  currentY += 10
  if mousePos.x >= contentX.float32 and mousePos.x <= (contentX + buttonWidth).float32 and
     mousePos.y >= currentY.float32 and mousePos.y <= (currentY + BUTTON_HEIGHT).float32:
    # Spawn 10 random enemies from sides of screen (same as wave mode)
    for i in 0..<10:
      let side = rand(3)
      var spawnX, spawnY: float32
      case side
      of 0: spawnX = rand(screenWidth.int).float32; spawnY = -30
      of 1: spawnX = screenWidth.float32 + 30; spawnY = rand(screenHeight.int).float32
      of 2: spawnX = rand(screenWidth.int).float32; spawnY = screenHeight.float32 + 30
      else: spawnX = -30; spawnY = rand(screenHeight.int).float32
      
      let randomType = enemyTypes[rand(enemyTypes.len - 1)]
      let enemy = newEnemy(spawnX, spawnY, game.difficulty, randomType, game)
      game.enemies.add(enemy)

proc handleBossesTabClick(game: Game, mousePos: Vector2, sidebarX, screenWidth, screenHeight: int32) =
  let startY = 45 + TAB_HEIGHT + 5
  var currentY = startY + 35 - game.sandboxScrollOffset
  let contentX = sidebarX + SIDEBAR_PADDING
  let buttonWidth = SIDEBAR_WIDTH - SIDEBAR_PADDING * 2
  
  # Check each boss button
  for bossId in 1..12:
    if mousePos.x >= contentX.float32 and mousePos.x <= (contentX + buttonWidth).float32 and
       mousePos.y >= currentY.float32 and mousePos.y <= (currentY + BUTTON_HEIGHT).float32:
      # Spawn the selected boss
      let boss = spawnBoss(screenWidth, screenHeight, game.difficulty, game.bossCount, bossId * 5)
      game.enemies.add(boss)
      return
    currentY += BUTTON_HEIGHT + BUTTON_SPACING

proc handleControlsTabClick(game: Game, mousePos: Vector2, sidebarX, screenWidth, screenHeight: int32) =
  let startY = 45 + TAB_HEIGHT + 5
  var currentY = startY + 10
  let contentX = sidebarX + SIDEBAR_PADDING
  let buttonWidth = SIDEBAR_WIDTH - SIDEBAR_PADDING * 2
  
  # God Mode toggle
  if mousePos.x >= contentX.float32 and mousePos.x <= (contentX + buttonWidth).float32 and
     mousePos.y >= currentY.float32 and mousePos.y <= (currentY + BUTTON_HEIGHT).float32:
    game.sandboxGodMode = not game.sandboxGodMode
    return
  currentY += BUTTON_HEIGHT + BUTTON_SPACING + 5
  
  # Freeze Enemies toggle
  if mousePos.x >= contentX.float32 and mousePos.x <= (contentX + buttonWidth).float32 and
     mousePos.y >= currentY.float32 and mousePos.y <= (currentY + BUTTON_HEIGHT).float32:
    game.sandboxFreezeEnemies = not game.sandboxFreezeEnemies
    return
  currentY += BUTTON_HEIGHT + BUTTON_SPACING + 5
  
  # Clear All Enemies
  if mousePos.x >= contentX.float32 and mousePos.x <= (contentX + buttonWidth).float32 and
     mousePos.y >= currentY.float32 and mousePos.y <= (currentY + BUTTON_HEIGHT).float32:
    game.enemies.setLen(0)
    return
  currentY += BUTTON_HEIGHT + BUTTON_SPACING + 10 + 25
  
  # Wave - button
  if mousePos.x >= contentX.float32 and mousePos.x <= (contentX + buttonWidth div 2 - 3).float32 and
     mousePos.y >= currentY.float32 and mousePos.y <= (currentY + BUTTON_HEIGHT).float32:
    if game.currentWave > 1:
      game.currentWave -= 1
    return
  
  # Wave + button
  if mousePos.x >= (contentX + buttonWidth div 2 + 3).float32 and mousePos.x <= (contentX + buttonWidth).float32 and
     mousePos.y >= currentY.float32 and mousePos.y <= (currentY + BUTTON_HEIGHT).float32:
    game.currentWave += 1
    return
  currentY += BUTTON_HEIGHT + BUTTON_SPACING + 10 + 25
  
  # Difficulty - button
  if mousePos.x >= contentX.float32 and mousePos.x <= (contentX + buttonWidth div 2 - 3).float32 and
     mousePos.y >= currentY.float32 and mousePos.y <= (currentY + BUTTON_HEIGHT).float32:
    game.difficulty = max(1.0, game.difficulty - 1.0)
    return
  
  # Difficulty + button
  if mousePos.x >= (contentX + buttonWidth div 2 + 3).float32 and mousePos.x <= (contentX + buttonWidth).float32 and
     mousePos.y >= currentY.float32 and mousePos.y <= (currentY + BUTTON_HEIGHT).float32:
    game.difficulty += 1.0
    return
  currentY += BUTTON_HEIGHT + BUTTON_SPACING + 10 + 20 + 20 + 20 + 25
  
  # Heal button
  if mousePos.x >= contentX.float32 and mousePos.x <= (contentX + buttonWidth).float32 and
     mousePos.y >= currentY.float32 and mousePos.y <= (currentY + BUTTON_HEIGHT).float32:
    game.player.hp = game.player.maxHp
    return
  currentY += BUTTON_HEIGHT + BUTTON_SPACING + 5
  
  # Add coins button
  if mousePos.x >= contentX.float32 and mousePos.x <= (contentX + buttonWidth).float32 and
     mousePos.y >= currentY.float32 and mousePos.y <= (currentY + BUTTON_HEIGHT).float32:
    game.player.coins += 1000
    return
  currentY += BUTTON_HEIGHT + BUTTON_SPACING + 10
  
  # Open Shop button
  if mousePos.x >= contentX.float32 and mousePos.x <= (contentX + buttonWidth).float32 and
     mousePos.y >= currentY.float32 and mousePos.y <= (currentY + BUTTON_HEIGHT).float32:
    game.state = gsShop
    game.selectedShopItem = 0
    return
  currentY += BUTTON_HEIGHT + BUTTON_SPACING + 5
  
  # Roll Power-Ups button
  if mousePos.x >= contentX.float32 and mousePos.x <= (contentX + buttonWidth).float32 and
     mousePos.y >= currentY.float32 and mousePos.y <= (currentY + BUTTON_HEIGHT).float32:
    game.powerUpChoices = generatePowerUpChoices(game.player, false)
    game.selectedPowerUp = 0
    initPowerUpRollAnimation(game)
    initializeRerollCost(game)
    game.state = gsPowerUpSelect

proc handleSandboxInput*(game: Game, screenWidth, screenHeight: int32) =
  if not game.sandboxSidebarOpen:
    # Check toggle button click
    if isMouseButtonPressed(Left):
      let mousePos = getMousePosition()
      let toggleX = screenWidth - 50
      let toggleY = screenHeight div 2 - 30
      if mousePos.x >= toggleX.float32 and mousePos.x <= (toggleX + 40).float32 and
         mousePos.y >= toggleY.float32 and mousePos.y <= (toggleY + 60).float32:
        game.sandboxSidebarOpen = true
    return
  
  # Handle scrolling
  let mouseWheel = getMouseWheelMove()
  if mouseWheel != 0:
    game.sandboxScrollOffset -= (mouseWheel * SCROLL_SPEED).int32
    if game.sandboxScrollOffset < 0:
      game.sandboxScrollOffset = 0
  
  if isMouseButtonPressed(Left):
    let mousePos = getMousePosition()
    let sidebarX = screenWidth - SIDEBAR_WIDTH
    
    # Check close button
    let closeX = sidebarX + SIDEBAR_WIDTH - 35
    if mousePos.x >= closeX.float32 and mousePos.x <= (closeX + 30).float32 and
       mousePos.y >= 5 and mousePos.y <= 35:
      game.sandboxSidebarOpen = false
      return
    
    # Check tabs
    let tabWidth = (SIDEBAR_WIDTH - SIDEBAR_PADDING * 4) div 3
    let tabY = 45
    for i in 0..2:
      let tabX = sidebarX + SIDEBAR_PADDING + i * (tabWidth + SIDEBAR_PADDING)
      if mousePos.x >= tabX.float32 and mousePos.x <= (tabX + tabWidth).float32 and
         mousePos.y >= tabY.float32 and mousePos.y <= (tabY + TAB_HEIGHT - 5).float32:
        game.sandboxSelectedTab = i
        game.sandboxScrollOffset = 0
        return
    
    # Handle content clicks based on selected tab
    case game.sandboxSelectedTab
    of 0:  # Enemies tab
      handleEnemiesTabClick(game, mousePos, sidebarX, screenWidth, screenHeight)
    of 1:  # Bosses tab
      handleBossesTabClick(game, mousePos, sidebarX, screenWidth, screenHeight)
    of 2:  # Controls tab
      handleControlsTabClick(game, mousePos, sidebarX, screenWidth, screenHeight)
    else:
      discard

# SANDBOX MODE UPDATES
proc updateSandboxMode*(game: Game, dt: float32) =
  # Apply god mode
  if game.sandboxGodMode:
    game.player.hp = game.player.maxHp
    game.player.invincibilityTimer = 1.0  # Keep invulnerable
  
  # Freeze enemies if enabled
  if game.sandboxFreezeEnemies:
    # Don't update enemy positions or timers
    return
