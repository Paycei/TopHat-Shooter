import raylib, types, sound, std/tables
from powerup import applyPowerUp, getPowerUpName

# TOGGLE THIS TO ENABLE/DISABLE CHEATS
const CHEATS_ENABLED* = true

type
  CheatMenuTab* = enum
    cmtWaves,
    cmtPowerUps,
    cmtStats,
    cmtPermanentPowerUps

  CheatMenu* = ref object
    active*: bool
    currentTab*: CheatMenuTab
    keySequence: seq[KeyboardKey]
    lastKeyTime: float32
    scrollOffset: int

# Key sequence for opening cheat menu: C, D, Plus(+)
const CHEAT_SEQUENCE = @[KeyboardKey.C, KeyboardKey.D, KeyboardKey.KpAdd]
const ALTERNATIVE_PLUS = KeyboardKey.Equal  # For keyboards without numpad

var globalCheatMenu*: CheatMenu

proc initCheatMenu*(): CheatMenu =
  result = CheatMenu(
    active: false,
    currentTab: cmtWaves,
    keySequence: @[],
    lastKeyTime: 0.0,
    scrollOffset: 0
  )
  globalCheatMenu = result

proc checkCheatSequence*(menu: CheatMenu, currentTime: float32) =
  if not CHEATS_ENABLED: return

  # Reset sequence if too much time has passed
  if currentTime - menu.lastKeyTime > 1.0:
    menu.keySequence.setLen(0)

  # Check for key presses
  for key in [KeyboardKey.C, KeyboardKey.D, KeyboardKey.KpAdd, ALTERNATIVE_PLUS]:
    if isKeyPressed(key):
      menu.lastKeyTime = currentTime

      # Normalize plus key
      var normalizedKey = key
      if key == KeyboardKey.KpAdd or key == ALTERNATIVE_PLUS:
        normalizedKey = KeyboardKey.KpAdd

      menu.keySequence.add(normalizedKey)

      # Check sequence
      if menu.keySequence.len == CHEAT_SEQUENCE.len:
        var matches = true
        for i in 0..<CHEAT_SEQUENCE.len:
          if menu.keySequence[i] != CHEAT_SEQUENCE[i]:
            matches = false
            break

        if matches:
          menu.active = not menu.active
          playSound(stMenuSelect)
          menu.keySequence.setLen(0)
          return

      # Reset if sequence gets too long
      if menu.keySequence.len > CHEAT_SEQUENCE.len:
        menu.keySequence.setLen(0)

proc updateCheatMenu*(menu: CheatMenu, game: var Game) =
  if not menu.active or not CHEATS_ENABLED:
    return
  
  # Close menu with Escape or clicking X
  if isKeyPressed(KeyboardKey.Escape):
    menu.active = false
    playSound(stMenuNav)
    return
  
  # Tab switching
  if isKeyPressed(KeyboardKey.One) or isKeyPressed(KeyboardKey.Kp1):
    menu.currentTab = cmtWaves
    playSound(stMenuNav)
  elif isKeyPressed(KeyboardKey.Two) or isKeyPressed(KeyboardKey.Kp2):
    menu.currentTab = cmtPowerUps
    playSound(stMenuNav)
  elif isKeyPressed(KeyboardKey.Three) or isKeyPressed(KeyboardKey.Kp3):
    menu.currentTab = cmtStats
    playSound(stMenuNav)
  elif isKeyPressed(KeyboardKey.Four) or isKeyPressed(KeyboardKey.Kp4):
    menu.currentTab = cmtPermanentPowerUps
    playSound(stMenuNav)
  
  # Handle scrolling for permanent power-ups tab
  if menu.currentTab == cmtPermanentPowerUps:
    if isKeyPressed(KeyboardKey.Up):
      menu.scrollOffset = max(0, menu.scrollOffset - 1)
    elif isKeyPressed(KeyboardKey.Down):
      menu.scrollOffset += 1

proc applyWaveCheat*(game: var Game, action: string) =
  case action
  of "skip":
    if game.waveInProgress:
      # Kill all enemies to complete wave
      game.enemies.setLen(0)
      playSound(stWaveComplete)
  of "next":
    game.currentWave += 1
    playSound(stMenuSelect)
  of "prev":
    if game.currentWave > 1:
      game.currentWave -= 1
    playSound(stMenuSelect)
  of "boss":
    game.wavesUntilBoss = 1
    game.currentWave += 1
    playSound(stBossSpawn)
  else:
    discard

proc applyPowerUpCheat*(game: var Game, powerUpType: PowerUpType) =
  game.player.activePowerUps.add(powerUpType)
  game.player.powerUpTimers[powerUpType] = 30.0  # 30 seconds
  playSound(stPowerUp)

proc applyPermanentPowerUpCheat*(game: var Game, powerUpType: PowerUpType, level: int) =
  # Check if player already has this power-up
  var found = false
  for i in 0..<game.player.powerUps.len:
    if game.player.powerUps[i].powerType == powerUpType:
      game.player.powerUps[i].level = level
      found = true
      break
  
  if not found:
    # Add new power-up
    game.player.powerUps.add(PowerUp(powerType: powerUpType, level: level, rarity: prCommon))
  
  # Apply the power-up effect (using the existing applyPowerUp from powerup.nim)
  applyPowerUp(game.player, PowerUp(powerType: powerUpType, level: level, rarity: prCommon))
  playSound(stPowerUp)

proc applyStatCheat*(game: var Game, stat: string, value: float32) =
  case stat
  of "health":
    game.player.hp = min(value, game.player.maxHp)
  of "maxhealth":
    game.player.maxHp = value
    game.player.hp = min(game.player.hp, game.player.maxHp)
  of "coins":
    game.player.coins = int(value)  # coins are integers
  of "speed":
    game.player.baseSpeed = value
  else:
    discard
  playSound(stMenuSelect)

proc drawWavesTab(x, y, width, height: int32, game: var Game)
proc drawPowerUpsTab(x, y, width, height: int32, game: var Game)
proc drawStatsTab(x, y, width, height: int32, game: var Game)
proc drawPermanentPowerUpsTab(x, y, width, height: int32, game: var Game, menu: CheatMenu)

proc drawCheatMenu*(menu: CheatMenu, game: var Game, screenWidth, screenHeight: int32) =
  if not menu.active or not CHEATS_ENABLED:
    return
  
  # Semi-transparent overlay
  drawRectangle(0, 0, screenWidth, screenHeight, Color(r: 0, g: 0, b: 0, a: 180))
  
  # Main panel
  let panelWidth: int32 = 600
  let panelHeight: int32 = 500
  let panelX = (screenWidth - panelWidth) div 2
  let panelY = (screenHeight - panelHeight) div 2
  
  # Panel background
  drawRectangle(panelX, panelY, panelWidth, panelHeight, Color(r: 30, g: 30, b: 40, a: 255))
  drawRectangleLines(panelX, panelY, panelWidth, panelHeight, Yellow)
  
  # Title
  let title = "CHEAT MENU (TESTER BUILD)"
  let titleWidth = measureText(title, 20)
  drawText(title, panelX + (panelWidth - titleWidth) div 2, panelY + 10, 20, Yellow)
  
  # Close instruction
  drawText("Press ESC to close", panelX + 10, panelY + 35, 12, Gray)
  
  # Tab buttons
  let tabY = panelY + 60
  let tabWidth = panelWidth div 4
  
  let tabs = ["1. Waves", "2. Power-Ups", "3. Stats", "4. Permanent"]
  for i in 0'i32..3'i32:
    let tabX = panelX + (i * tabWidth)
    let tabColor = if CheatMenuTab(i) == menu.currentTab: Yellow else: Gray
    drawRectangle(tabX, tabY, tabWidth, 30, Color(r: 20, g: 20, b: 30, a: 255))
    drawRectangleLines(tabX, tabY, tabWidth, 30, tabColor)
    let tabText = tabs[i]
    let textWidth = measureText(tabText, 14)
    drawText(tabText, tabX + (tabWidth - textWidth) div 2, tabY + 8, 14, tabColor)
  
  # Content area
  let contentY = tabY + 40
  let contentHeight = panelHeight - 110
  
  case menu.currentTab
  of cmtWaves:
    drawWavesTab(panelX, contentY, panelWidth, contentHeight, game)
  of cmtPowerUps:
    drawPowerUpsTab(panelX, contentY, panelWidth, contentHeight, game)
  of cmtStats:
    drawStatsTab(panelX, contentY, panelWidth, contentHeight, game)
  of cmtPermanentPowerUps:
    drawPermanentPowerUpsTab(panelX, contentY, panelWidth, contentHeight, game, menu)

proc drawWavesTab(x, y, width, height: int32, game: var Game) =
  var currentY = y + 10
  
  # Current wave info
  drawText("Current Wave: " & $game.currentWave, x + 20, currentY, 16, White)
  currentY += 25
  drawText("Waves until Boss: " & $game.wavesUntilBoss, x + 20, currentY, 16, White)
  currentY += 25
  drawText("Enemies alive: " & $game.enemies.len, x + 20, currentY, 16, White)
  currentY += 40
  
  # Buttons
  let buttonWidth: int32 = 250
  let buttonHeight: int32 = 40
  let centerX = x + (width - buttonWidth) div 2
  
  # Skip current wave button
  let skipRect = Rectangle(x: centerX.float32, y: currentY.float32, width: buttonWidth.float32, height: buttonHeight.float32)
  let skipHovered = checkCollisionPointRec(getMousePosition(), skipRect)
  drawRectangle(centerX, currentY, buttonWidth, buttonHeight, 
                if skipHovered: Color(r: 80, g: 80, b: 0, a: 255) else: Color(r: 60, g: 60, b: 0, a: 255))
  drawRectangleLines(centerX, currentY, buttonWidth, buttonHeight, Yellow)
  drawText("Skip Current Wave", centerX + 30, currentY + 12, 16, White)
  
  if skipHovered and isMouseButtonPressed(Left):
    applyWaveCheat(game, "skip")
  
  currentY += buttonHeight + 10
  
  # Next wave button
  let nextRect = Rectangle(x: centerX.float32, y: currentY.float32, width: buttonWidth.float32, height: buttonHeight.float32)
  let nextHovered = checkCollisionPointRec(getMousePosition(), nextRect)
  drawRectangle(centerX, currentY, buttonWidth, buttonHeight,
                if nextHovered: Color(r: 0, g: 80, b: 80, a: 255) else: Color(r: 0, g: 60, b: 60, a: 255))
  drawRectangleLines(centerX, currentY, buttonWidth, buttonHeight, SkyBlue)
  drawText("Advance to Next Wave", centerX + 20, currentY + 12, 16, White)
  
  if nextHovered and isMouseButtonPressed(Left):
    applyWaveCheat(game, "next")
  
  currentY += buttonHeight + 10
  
  # Boss wave button
  let bossRect = Rectangle(x: centerX.float32, y: currentY.float32, width: buttonWidth.float32, height: buttonHeight.float32)
  let bossHovered = checkCollisionPointRec(getMousePosition(), bossRect)
  drawRectangle(centerX, currentY, buttonWidth, buttonHeight,
                if bossHovered: Color(r: 80, g: 0, b: 0, a: 255) else: Color(r: 60, g: 0, b: 0, a: 255))
  drawRectangleLines(centerX, currentY, buttonWidth, buttonHeight, Red)
  drawText("Trigger Boss Wave", centerX + 40, currentY + 12, 16, White)
  
  if bossHovered and isMouseButtonPressed(Left):
    applyWaveCheat(game, "boss")

proc drawPowerUpsTab(x, y, width, height: int32, game: var Game) =
  var currentY = y + 10
  
  drawText("Click to activate power-up (30 seconds)", x + 20, currentY, 14, Gray)
  currentY += 30
  
  # Active power-ups display
  drawText("Active Power-Ups:", x + 20, currentY, 16, Yellow)
  currentY += 25
  
  if game.player.activePowerUps.len == 0:
    drawText("  None", x + 30, currentY, 14, Gray)
    currentY += 20
  else:
    for powerUp in game.player.activePowerUps:
      let timeLeft = game.player.powerUpTimers[powerUp]
      drawText("  " & $powerUp & " (" & $int(timeLeft) & "s)", x + 30, currentY, 14, Green)
      currentY += 20
  
  currentY += 20
  
  # Power-up buttons
  let buttonWidth: int32 = 250
  let buttonHeight: int32 = 35
  let centerX = x + (width - buttonWidth) div 2
  
  let powerUps = [
    (puRapidFire, "Rapid Fire", Color(r: 255, g: 100, b: 100, a: 255)),
    (puPiercingShots, "Piercing Shots", Color(r: 100, g: 150, b: 255, a: 255)),
    (puHomingBullets, "Homing Shots", Color(r: 255, g: 100, b: 255, a: 255)),
    (puRotatingShield, "Rotating Shield", Color(r: 100, g: 255, b: 255, a: 255)),
    (puSpeedBoost, "Speed Boost", Color(r: 255, g: 255, b: 100, a: 255))
  ]
  
  for powerUpData in powerUps:
    let (powerUpType, name, color) = powerUpData
    let rect = Rectangle(x: centerX.float32, y: currentY.float32, width: buttonWidth.float32, height: buttonHeight.float32)
    let hovered = checkCollisionPointRec(getMousePosition(), rect)
    
    var drawColor = color
    if hovered:
      drawColor = Color(
        r: min(uint8(255), color.r + 30),
        g: min(uint8(255), color.g + 30),
        b: min(uint8(255), color.b + 30),
        a: 255
      )

    
    drawRectangle(centerX, currentY, buttonWidth, buttonHeight, drawColor)
    drawRectangleLines(centerX, currentY, buttonWidth, buttonHeight, White)
    
    let textWidth = measureText(name, 14)
    drawText(name, centerX + (buttonWidth - textWidth) div 2, currentY + 10, 14, Black)
    
    if hovered and isMouseButtonPressed(Left):
      applyPowerUpCheat(game, powerUpType)
    
    currentY += buttonHeight + 8

proc drawStatsTab(x, y, width, height: int32, game: var Game) =
  var currentY = y + 10
  
  drawText("Player Stats (Click buttons to modify)", x + 20, currentY, 14, Gray)
  currentY += 30
  
  let labelX = x + 40
  let valueX = x + 200
  let buttonStartX = x + 300
  let buttonWidth: int32 = 60
  let buttonHeight: int32 = 30
  let spacing: int32 = 8
  
  # Health
  drawText("Health:", labelX, currentY + 5, 16, White)
  drawText($game.player.hp & " / " & $game.player.maxHp, valueX, currentY + 5, 16, Green)
  
  # Health buttons
  let healthButtons = [
    ("Full", game.player.maxHp),
    ("Half", game.player.maxHp / 2.0),
    ("Low", 1.0.float32)
  ]

  var btnX = buttonStartX
  for btnData in healthButtons:
    let (label, value) = btnData
    let rect = Rectangle(x: btnX.float32, y: currentY.float32, width: buttonWidth.float32, height: buttonHeight.float32)
    let hovered = checkCollisionPointRec(getMousePosition(), rect)
    
    drawRectangle(btnX, currentY, buttonWidth, buttonHeight,
                  if hovered: Color(r: 0, g: 100, b: 0, a: 255) else: Color(r: 0, g: 70, b: 0, a: 255))
    drawRectangleLines(btnX, currentY, buttonWidth, buttonHeight, Green)
    
    let textWidth = measureText(label, 12)
    drawText(label, btnX + (buttonWidth - textWidth) div 2, currentY + 9, 12, White)
    
    if hovered and isMouseButtonPressed(Left):
      applyStatCheat(game, "health", value)
    
    btnX += buttonWidth + spacing
  
  currentY += buttonHeight + 20
  
  # Max Health
  drawText("Max Health:", labelX, currentY + 5, 16, White)
  drawText($game.player.maxHp, valueX, currentY + 5, 16, Yellow)
  
  let maxHealthButtons = [
    ("100", 100.0.float32),
    ("200", 200.0.float32),
    ("500", 500.0.float32)
  ]

  
  btnX = buttonStartX
  for btnData in maxHealthButtons:
    let (label, value) = btnData
    let rect = Rectangle(x: btnX.float32, y: currentY.float32, width: buttonWidth.float32, height: buttonHeight.float32)
    let hovered = checkCollisionPointRec(getMousePosition(), rect)
    
    drawRectangle(btnX, currentY, buttonWidth, buttonHeight,
                  if hovered: Color(r: 100, g: 100, b: 0, a: 255) else: Color(r: 70, g: 70, b: 0, a: 255))
    drawRectangleLines(btnX, currentY, buttonWidth, buttonHeight, Yellow)
    
    let textWidth = measureText(label, 12)
    drawText(label, btnX + (buttonWidth - textWidth) div 2, currentY + 9, 12, White)
    
    if hovered and isMouseButtonPressed(Left):
      applyStatCheat(game, "maxhealth", value)
    
    btnX += buttonWidth + spacing
  
  currentY += buttonHeight + 20
  
  # Coins
  drawText("Coins:", labelX, currentY + 5, 16, White)
  drawText($game.player.coins, valueX, currentY + 5, 16, Yellow)
  
  let coinButtons = [
    ("100", 100.0.float32),
    ("500", 500.0.float32),
    ("1000", 1000.0.float32),
    ("9999", 9999.0.float32)
  ]
  
  btnX = buttonStartX
  for btnData in coinButtons:
    let (label, value) = btnData
    let rect = Rectangle(x: btnX.float32, y: currentY.float32, width: buttonWidth.float32, height: buttonHeight.float32)
    let hovered = checkCollisionPointRec(getMousePosition(), rect)
    
    drawRectangle(btnX, currentY, buttonWidth, buttonHeight,
                  if hovered: Color(r: 100, g: 80, b: 0, a: 255) else: Color(r: 70, g: 60, b: 0, a: 255))
    drawRectangleLines(btnX, currentY, buttonWidth, buttonHeight, Gold)
    
    let textWidth = measureText(label, 12)
    drawText(label, btnX + (buttonWidth - textWidth) div 2, currentY + 9, 12, White)
    
    if hovered and isMouseButtonPressed(Left):
      applyStatCheat(game, "coins", value)
    
    btnX += buttonWidth + spacing
  
  currentY += buttonHeight + 20
  
  # Speed
  drawText("Speed:", labelX, currentY + 5, 16, White)
  drawText($int(game.player.baseSpeed), valueX, currentY + 5, 16, SkyBlue)
  
  let speedButtons = [
    ("Normal", 200.float32),
    ("Fast", 400.float32),
    ("Max", 600.float32)
  ]
  
  btnX = buttonStartX
  for btnData in speedButtons:
    let (label, value) = btnData
    let rect = Rectangle(x: btnX.float32, y: currentY.float32, width: buttonWidth.float32, height: buttonHeight.float32)
    let hovered = checkCollisionPointRec(getMousePosition(), rect)
    
    drawRectangle(btnX, currentY, buttonWidth, buttonHeight,
                  if hovered: Color(r: 0, g: 100, b: 150, a: 255) else: Color(r: 0, g: 70, b: 100, a: 255))
    drawRectangleLines(btnX, currentY, buttonWidth, buttonHeight, SkyBlue)
    
    let textWidth = measureText(label, 12)
    drawText(label, btnX + (buttonWidth - textWidth) div 2, currentY + 9, 12, White)
    
    if hovered and isMouseButtonPressed(Left):
      applyStatCheat(game, "speed", value)
    
    btnX += buttonWidth + spacing
  
  currentY += buttonHeight + 30
  
  # Instructions
  drawText("Tip: Modify stats to test different scenarios", x + 20, currentY, 12, Gray)

proc drawPermanentPowerUpsTab(x, y, width, height: int32, game: var Game, menu: CheatMenu) =
  var currentY = y + 10
  
  drawText("Permanent Power-Ups (Click to add/upgrade)", x + 20, currentY, 14, Gray)
  currentY += 25
  
  # Show currently owned permanent power-ups
  drawText("Currently Owned:", x + 20, currentY, 14, Yellow)
  currentY += 20
  
  if game.player.powerUps.len == 0:
    drawText("  None", x + 30, currentY, 12, Gray)
    currentY += 18
  else:
    for powerUp in game.player.powerUps:
      let name = getPowerUpName(powerUp.powerType)
      drawText("  " & name & " - Level " & $powerUp.level, x + 30, currentY, 12, Green)
      currentY += 18
  
  currentY += 15
  drawText("All Available Power-Ups (scroll with UP/DOWN):", x + 20, currentY, 14, Yellow)
  currentY += 25
  
  # Define all power-up types
  let allPowerUpTypes = [
    puDoubleShot, puRotatingShield, puDamageZone, puHomingBullets, puPiercingShots,
    puMultiShot, puExplosiveBullets, puLifeSteal, puRapidFire, puMaxHealth,
    puSpeedBoost, puBulletDamage, puBulletSpeed, puLuckyCoins, puWallMaster,
    puAutoShoot, puBulletSize, puRegeneration, puDodgeChance, puCriticalHit,
    puVampirism, puBulletRicochet, puSlowField, puRage, puBerserker,
    puThorns, puBulletSplit, puChainLightning, puFrostShots, puPoisonDamage
  ]
  
  # Scrollable area setup
  let maxVisibleItems = 8
  let itemHeight: int32 = 30
  let buttonWidth: int32 = 45
  let buttonSpacing: int32 = 5
  
  # Calculate scroll bounds
  let maxScroll = max(0, allPowerUpTypes.len - maxVisibleItems)
  if menu.scrollOffset > maxScroll:
    menu.scrollOffset = maxScroll
  
  # Draw visible items
  let startIdx = menu.scrollOffset
  let endIdx = min(startIdx + maxVisibleItems, allPowerUpTypes.len)
  
  for i in startIdx..<endIdx:
    let powerType = allPowerUpTypes[i]
    let name = getPowerUpName(powerType)
    let itemY = currentY + (i - startIdx).int32 * itemHeight
    
    # Check if player has this power-up
    var currentLevel = 0
    for p in game.player.powerUps:
      if p.powerType == powerType:
        currentLevel = p.level
        break
    
    # Draw power-up name
    let nameColor = if currentLevel > 0: Green else: White
    drawText(name, x + 30, itemY + 7, 12, nameColor)
    
    # Draw level buttons (Lv1, Lv2, Lv3)
    let buttonStartX = x + width - 170
    
    for level in 1..3:
      let btnX = buttonStartX + (level - 1).int32 * (buttonWidth + buttonSpacing)
      let rect = Rectangle(x: btnX.float32, y: itemY.float32, width: buttonWidth.float32, height: (itemHeight - 5).float32)
      let hovered = checkCollisionPointRec(getMousePosition(), rect)
      
      # Button color based on current level
      var btnColor: Color
      if level == currentLevel:
        btnColor = if hovered: Color(r: 0, g: 150, b: 0, a: 255) else: Color(r: 0, g: 100, b: 0, a: 255)
      elif level < currentLevel:
        btnColor = Color(r: 0, g: 70, b: 0, a: 150)
      else:
        btnColor = if hovered: Color(r: 80, g: 80, b: 80, a: 255) else: Color(r: 50, g: 50, b: 50, a: 255)
      
      drawRectangle(btnX, itemY, buttonWidth, itemHeight - 5, btnColor)
      drawRectangleLines(btnX, itemY, buttonWidth, itemHeight - 5, 
                        if level == currentLevel: Yellow else: Gray)
      
      let btnText = "Lv" & $level
      let btnTextWidth = measureText(btnText, 10)
      drawText(btnText, btnX + (buttonWidth - btnTextWidth) div 2, itemY + 8, 10, White)
      
      if hovered and isMouseButtonPressed(Left):
        applyPermanentPowerUpCheat(game, powerType, level)
  
  # Draw scroll indicator
  if maxScroll > 0:
    let scrollY = y + height - 30
    drawText("Showing " & $(startIdx + 1) & "-" & $endIdx & " of " & $allPowerUpTypes.len, 
            x + 20, scrollY, 10, Gray)
    if menu.scrollOffset > 0:
      drawText("▲ UP to scroll up", x + width - 150, scrollY, 10, Yellow)
    if menu.scrollOffset < maxScroll:
      drawText("▼ DOWN to scroll down", x + width - 180, scrollY + 12, 10, Yellow)
