# SANDBOX MODE - Testing and Development Tools

import raylib, types, enemy, powerup, powerup_data, boss_definitions, std/strutils, random, localization, render_context, ui/icon_drawing

const
  SIDEBAR_WIDTH = 300
  SIDEBAR_PADDING = 10
  BUTTON_HEIGHT = 35
  BUTTON_SPACING = 5
  TAB_HEIGHT = 40
  SCROLL_SPEED = 20
  POWERUP_ITEM_HEIGHT = 82
  POWERUP_ICON_SIZE = 34

const
  SCROLLBAR_WIDTH = 8
  SCROLLBAR_MIN_THUMB = 24

const sandboxLegendaryPowerUpTypes = [
  puArcaneMastery, puBloodMastery, puBulletSpeed,
  puCelestialVeil, puDoubleShot, puEchoShots, puFireMastery, puFrostMastery, puGravityWell,
  puLightningMastery, puLuckyCoins, puMagicalBullets, puMaxHealth, puMultiShot,
  puOvercharge, puParry, puPhaseShift, puPoisonMastery, puRapidFire,
  puRotatingOrbs, puSpeedBoost, puTimeWarp, puWallMaster, puWindMastery,
  puVolatile, puBloodPact, puConduit, puAftershock, puNova, puBountiful
]

proc isSandboxLegendaryPowerUp(powerType: PowerUpType): bool =
  for legendaryType in sandboxLegendaryPowerUpTypes:
    if powerType == legendaryType:
      return true
  false

proc fitSandboxText(text: string, maxWidth, fontSize: int32,
                    minSize: int32 = 8): tuple[text: string, size: int32] =
  var fs = fontSize
  while fs > minSize and measureText(text, fs) > maxWidth:
    dec fs
  if measureText(text, fs) <= maxWidth:
    return (text, fs)

  var fitted = text
  while fitted.len > 0 and measureText(fitted & "...", fs) > maxWidth:
    fitted = fitted[0..^2]
  (fitted & "...", fs)

proc wrapSandboxText(text: string, maxWidth, fontSize: int32): seq[string] =
  result = @[]
  var words: seq[string] = @[]
  for word in text.splitWhitespace():
    words.add(word)
  if words.len == 0:
    return

  var line = ""
  for word in words:
    let candidate = if line.len == 0: word else: line & " " & word
    if measureText(candidate, fontSize) <= maxWidth:
      line = candidate
    else:
      if line.len > 0:
        result.add(line)
      if measureText(word, fontSize) > maxWidth:
        var chunk = ""
        for ch in word:
          if measureText(chunk & $ch, fontSize) <= maxWidth:
            chunk &= $ch
          else:
            if chunk.len > 0:
              result.add(chunk)
            chunk = $ch
        line = chunk
      else:
        line = word
  if line.len > 0:
    result.add(line)

proc sandboxContentHeight(selectedTab: int): int32 =
  case selectedTab
  of 0:
    10'i32 + 25'i32 + 13'i32 * (BUTTON_HEIGHT + BUTTON_SPACING) + 10'i32 + BUTTON_HEIGHT
  of 1:
    10'i32 + 25'i32 + 12'i32 * (BUTTON_HEIGHT + BUTTON_SPACING)
  of 2:
    let powerUpCount = ord(high(PowerUpType)) - ord(low(PowerUpType)) + 1
    10'i32 + 24'i32 + 20'i32 + int32(powerUpCount) * (POWERUP_ITEM_HEIGHT + BUTTON_SPACING)
  of 3:
    560'i32
  else:
    0'i32

proc maxSandboxScrollOffset(selectedTab: int, screenHeight: int32): int32 =
  let contentStartY = 45'i32 + TAB_HEIGHT + 5'i32
  let visibleHeight = max(0'i32, screenHeight - contentStartY)
  max(0'i32, sandboxContentHeight(selectedTab) - visibleHeight)

proc clampSandboxScroll(game: Game, screenHeight: int32) =
  let maxScroll = maxSandboxScrollOffset(game.sandboxSelectedTab, screenHeight)
  if game.sandboxScrollOffset < 0:
    game.sandboxScrollOffset = 0
  elif game.sandboxScrollOffset > maxScroll:
    game.sandboxScrollOffset = maxScroll

# UI DRAWING
proc drawEnemiesTab(game: Game, sidebarX, startY, screenHeight: int32) =
  var currentY: int32 = startY + 10 - game.sandboxScrollOffset
  let contentX: int32 = sidebarX + SIDEBAR_PADDING
  let buttonWidth: int32 = SIDEBAR_WIDTH - SIDEBAR_PADDING * 2

  drawText(t(tkSandboxSpawnEnemies), contentX, currentY, 18, White)
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

  currentY += 10
  if currentY > startY - 50 and currentY < screenHeight - 50:
    drawRectangle(contentX, currentY, buttonWidth, BUTTON_HEIGHT, Color(r: 120, g: 70, b: 70, a: 255))
    drawText(t(tkSandboxSpawn10Random), contentX + 5, currentY + 10, 16, Yellow)

proc drawBossesTab(game: Game, sidebarX, startY, screenHeight: int32) =
  var currentY: int32 = startY + 10 - game.sandboxScrollOffset
  let contentX: int32 = sidebarX + SIDEBAR_PADDING
  let buttonWidth: int32 = SIDEBAR_WIDTH - SIDEBAR_PADDING * 2

  drawText(t(tkSandboxSpawnBosses), contentX, currentY, 18, White)
  currentY += 25

  for bossId in 1..12:
    let bossDef = getBossDefinition(bossId)

    if currentY > startY - 50 and currentY < screenHeight - 50:
      drawRectangle(contentX, currentY, buttonWidth, BUTTON_HEIGHT, Color(r: 120, g: 50, b: 50, a: 255))
      drawRectangleLines(contentX, currentY, buttonWidth, BUTTON_HEIGHT, Color(r: 150, g: 80, b: 80, a: 255))
      drawText($bossId & ". " & bossDef.name, contentX + 5, currentY + 5, 16, Red)
      drawText(bossDef.description, contentX + 5, currentY + 20, 12, Color(r: 200, g: 150, b: 150, a: 255))
    currentY += BUTTON_HEIGHT + BUTTON_SPACING

proc drawPowerUpsVisualsTab(game: Game, sidebarX, startY, screenHeight: int32) =
  var currentY: int32 = startY + 10 - game.sandboxScrollOffset
  let contentX: int32 = sidebarX + SIDEBAR_PADDING
  let cardWidth: int32 = SIDEBAR_WIDTH - SIDEBAR_PADDING * 2

  drawText("Power-Up Visuals", contentX, currentY, 18, White)
  currentY += 24
  drawText("Icon, rarity, and Lv.1 description preview", contentX, currentY, 10,
           Color(r: 170, g: 185, b: 200, a: 255))
  currentY += 20

  for powerOrdinal in ord(low(PowerUpType))..ord(high(PowerUpType)):
    let powerType = PowerUpType(powerOrdinal)
    let accent = getPowerUpColor(powerType)
    let isLegendary = isSandboxLegendaryPowerUp(powerType)

    if currentY > startY - POWERUP_ITEM_HEIGHT and currentY < screenHeight - 10:
      let bgColor = if isLegendary:
        Color(r: 58, g: 46, b: 20, a: 245)
      else:
        Color(r: 34, g: 42, b: 54, a: 245)
      let borderColor = if isLegendary:
        Color(r: 255, g: 215, b: 80, a: 220)
      else:
        Color(r: 80, g: 150, b: 200, a: 210)

      drawRectangle(contentX, currentY, cardWidth, POWERUP_ITEM_HEIGHT, bgColor)
      drawRectangle(contentX, currentY, 3, POWERUP_ITEM_HEIGHT, accent)
      drawRectangleLines(Rectangle(x: contentX.float32, y: currentY.float32,
                                   width: cardWidth.float32, height: POWERUP_ITEM_HEIGHT.float32),
                         1, borderColor)

      let iconX = contentX + 10
      let iconY = currentY + 11
      drawRectangle(iconX - 3, iconY - 3, POWERUP_ICON_SIZE + 6, POWERUP_ICON_SIZE + 6,
                    Color(r: 10, g: 16, b: 24, a: 190))
      drawRectangleLines(Rectangle(x: (iconX - 3).float32, y: (iconY - 3).float32,
                                   width: (POWERUP_ICON_SIZE + 6).float32,
                                   height: (POWERUP_ICON_SIZE + 6).float32),
                         1, Color(r: accent.r, g: accent.g, b: accent.b, a: 180))
      drawPowerUpIcon(iconX, iconY, POWERUP_ICON_SIZE, powerType, accent)

      let textX = contentX + 56
      let badgeText = if isLegendary: "LEGENDARY" else: "COMMON"
      let badgeWidth = measureText(badgeText, 9) + 8
      let badgeX = contentX + cardWidth - badgeWidth - 7
      drawRectangle(badgeX, currentY + 7, badgeWidth, 14,
                    if isLegendary: Color(r: 120, g: 86, b: 16, a: 230)
                    else: Color(r: 34, g: 88, b: 116, a: 230))
      drawText(badgeText, badgeX + 4, currentY + 10, 9,
               if isLegendary: Color(r: 255, g: 230, b: 120, a: 255)
               else: Color(r: 160, g: 225, b: 255, a: 255))

      let (nameText, nameSize) = fitSandboxText(getPowerUpName(powerType),
                                                badgeX - textX - 5, 13)
      drawText(nameText, textX, currentY + 8, nameSize, White)

      drawText("Lv.1 preview", textX, currentY + 25, 9,
               Color(r: 120, g: 200, b: 255, a: 255))

      let desc = getPowerUpDescription(powerType, 1, game.player.damage)
      let descLines = wrapSandboxText(desc, cardWidth - 64, 10)
      let maxLines = min(3, descLines.len)
      for i in 0..<maxLines:
        drawText(descLines[i], textX, currentY + 39 + int32(i * 12), 10,
                 Color(r: 185, g: 194, b: 205, a: 255))
      if descLines.len > maxLines:
        drawText("...", textX, currentY + 39 + int32(maxLines * 12), 10,
                 Color(r: 150, g: 160, b: 170, a: 255))

    currentY += POWERUP_ITEM_HEIGHT + BUTTON_SPACING

proc drawControlsTab(game: Game, sidebarX, startY, screenHeight: int32) =
  var currentY: int32 = startY + 10
  let contentX: int32 = sidebarX + SIDEBAR_PADDING
  let buttonWidth: int32 = SIDEBAR_WIDTH - SIDEBAR_PADDING * 2

  # God Mode toggle
  let godModeColor = if game.sandboxGodMode: Green else: Color(r: 80, g: 80, b: 80, a: 255)
  drawRectangle(contentX, currentY, buttonWidth, BUTTON_HEIGHT, godModeColor)
  drawText(t(tkSandboxGodMode) & " " & (if game.sandboxGodMode: "ON" else: "OFF"), contentX + 5, currentY + 10, 16, White)
  currentY += BUTTON_HEIGHT + BUTTON_SPACING + 5

  # Freeze Enemies toggle
  let freezeColor = if game.sandboxFreezeEnemies: Color(r: 100, g: 150, b: 255, a: 255) else: Color(r: 80, g: 80, b: 80, a: 255)
  drawRectangle(contentX, currentY, buttonWidth, BUTTON_HEIGHT, freezeColor)
  drawText(t(tkSandboxFreezeEnemies) & " " & (if game.sandboxFreezeEnemies: "ON" else: "OFF"), contentX + 5, currentY + 10, 16, White)
  currentY += BUTTON_HEIGHT + BUTTON_SPACING + 5

  # Clear All Enemies button
  drawRectangle(contentX, currentY, buttonWidth, BUTTON_HEIGHT, Color(r: 150, g: 50, b: 50, a: 255))
  drawText(t(tkSandboxClearAllEnemies), contentX + 5, currentY + 10, 16, White)
  currentY += BUTTON_HEIGHT + BUTTON_SPACING + 10

  # Wave controls
  drawText(t(tkSandboxWave) & " " & $game.currentWave, contentX, currentY, 16, White)
  currentY += 25
  drawRectangle(contentX, currentY, buttonWidth div 2 - 3, BUTTON_HEIGHT, Color(r: 80, g: 80, b: 120, a: 255))
  drawText(t(tkSandboxWaveMinus), contentX + 5, currentY + 10, 16, White)
  drawRectangle(contentX + buttonWidth div 2 + 3, currentY, buttonWidth div 2 - 3, BUTTON_HEIGHT, Color(r: 80, g: 80, b: 120, a: 255))
  drawText(t(tkSandboxWavePlus), contentX + buttonWidth div 2 + 8, currentY + 10, 16, White)
  currentY += BUTTON_HEIGHT + BUTTON_SPACING + 10

  # Difficulty controls
  drawText(t(tkSandboxDifficulty) & " " & formatFloat(game.difficulty, ffDecimal, 1), contentX, currentY, 16, White)
  currentY += 25
  drawRectangle(contentX, currentY, buttonWidth div 2 - 3, BUTTON_HEIGHT, Color(r: 120, g: 80, b: 80, a: 255))
  drawText(t(tkSandboxDiffMinus), contentX + 5, currentY + 10, 16, White)
  drawRectangle(contentX + buttonWidth div 2 + 3, currentY, buttonWidth div 2 - 3, BUTTON_HEIGHT, Color(r: 120, g: 80, b: 80, a: 255))
  drawText(t(tkSandboxDiffPlus), contentX + buttonWidth div 2 + 8, currentY + 10, 16, White)
  currentY += BUTTON_HEIGHT + BUTTON_SPACING + 10

  # Player stats
  drawText(t(tkSandboxHP) & " " & $game.player.hp & "/" & $game.player.maxHp, contentX, currentY, 14, White)
  currentY += 20
  drawText(t(tkSandboxCoins) & " " & $game.player.coins, contentX, currentY, 14, Gold)
  currentY += 20
  drawText(t(tkSandboxEnemies) & " " & $game.enemies.len, contentX, currentY, 14, White)
  currentY += 25

  # Heal button
  drawRectangle(contentX, currentY, buttonWidth, BUTTON_HEIGHT, Color(r: 50, g: 150, b: 50, a: 255))
  drawText(t(tkSandboxHealFull), contentX + 5, currentY + 10, 16, White)
  currentY += BUTTON_HEIGHT + BUTTON_SPACING + 5

  drawRectangle(contentX, currentY, buttonWidth, BUTTON_HEIGHT, Color(r: 180, g: 140, b: 0, a: 255))
  drawText(t(tkSandboxAddCoins), contentX + 5, currentY + 10, 16, White)
  currentY += BUTTON_HEIGHT + BUTTON_SPACING + 10

  drawRectangle(contentX, currentY, buttonWidth, BUTTON_HEIGHT, Color(r: 70, g: 120, b: 180, a: 255))
  drawText(t(tkSandboxOpenShop), contentX + 5, currentY + 10, 16, White)
  currentY += BUTTON_HEIGHT + BUTTON_SPACING + 5

  # Open Power-Up Selection button
  drawRectangle(contentX, currentY, buttonWidth, BUTTON_HEIGHT, Color(r: 120, g: 70, b: 180, a: 255))
  drawText(t(tkSandboxRollPowerUps), contentX + 5, currentY + 10, 16, White)
  currentY += BUTTON_HEIGHT + BUTTON_SPACING + 10

  # Enter Boss #7 3D Mode button
  drawRectangle(contentX, currentY, buttonWidth, BUTTON_HEIGHT, Color(r: 150, g: 100, b: 255, a: 255))
  drawText("Enter Boss #7 3D", contentX + 5, currentY + 5, 16, White)
  drawText("Test 3D Arena", contentX + 5, currentY + 20, 12, Color(r: 200, g: 200, b: 200, a: 255))

proc drawSandboxScrollbar(game: Game, sidebarX, contentStartY, screenHeight: int32) =
  ## Draws a draggable scrollbar on the right edge of the sidebar.
  ## Only visible when content exceeds the viewport.
  let maxScroll = maxSandboxScrollOffset(game.sandboxSelectedTab, screenHeight)
  if maxScroll <= 0:
    return

  let trackX    = sidebarX + SIDEBAR_WIDTH - SCROLLBAR_WIDTH - 2
  let trackY    = contentStartY + 2
  let trackH    = screenHeight - contentStartY - 4

  # Track background
  drawRectangle(trackX, trackY, SCROLLBAR_WIDTH, trackH,
                Color(r: 30, g: 30, b: 40, a: 180))
  drawRectangleLines(Rectangle(x: trackX.float32, y: trackY.float32,
                               width: SCROLLBAR_WIDTH.float32, height: trackH.float32),
                     1, Color(r: 60, g: 60, b: 80, a: 180))

  # Thumb size proportional to visible / total content
  let contentH  = sandboxContentHeight(game.sandboxSelectedTab)
  let thumbH    = max(SCROLLBAR_MIN_THUMB,
                      int32(trackH.float32 * (trackH.float32 / contentH.float32)))
  let thumbRange = trackH - thumbH
  let thumbY = if maxScroll > 0:
    trackY + int32(thumbRange.float32 * (game.sandboxScrollOffset.float32 / maxScroll.float32))
  else:
    trackY

  # Thumb colour — brighter while dragging
  let thumbColor = if game.sandboxScrollbarDragging:
    Color(r: 140, g: 190, b: 255, a: 240)
  else:
    Color(r: 90, g: 130, b: 190, a: 210)

  drawRectangle(trackX + 1, thumbY, SCROLLBAR_WIDTH - 2, thumbH, thumbColor)
  # Subtle grip lines
  let midY = thumbY + thumbH div 2
  for dy in [-4'i32, 0'i32, 4'i32]:
    drawLine(trackX + 2, midY + dy, trackX + SCROLLBAR_WIDTH - 3, midY + dy,
             Color(r: 200, g: 220, b: 255, a: 100))

proc drawSandboxSidebar*(game: Game, screenWidth, screenHeight: int32) =
  if not game.sandboxSidebarOpen:
    # Draw toggle button when closed
    let toggleX = screenWidth - 50
    let toggleY = screenHeight div 2 - 30
    drawRectangle(toggleX, toggleY, 40, 60, Color(r: 50, g: 50, b: 50, a: 200))
    drawText(t(tkSandboxToggle), toggleX + 8, toggleY + 18, 24, White)
    return

  # Draw sidebar background
  let sidebarX = screenWidth - SIDEBAR_WIDTH
  drawRectangle(sidebarX, 0, SIDEBAR_WIDTH, screenHeight, Color(r: 40, g: 40, b: 40, a: 230))

  # Draw close button
  let closeX = sidebarX + SIDEBAR_WIDTH - 35
  drawRectangle(closeX, 5, 30, 30, Color(r: 150, g: 50, b: 50, a: 255))
  drawText(t(tkSandboxClose), closeX + 8, 8, 20, White)

  # Draw title
  drawText(t(tkSandboxTitle), sidebarX + 10, 10, 20, Yellow)

  # Draw tabs
  let tabs = [t(tkSandboxTabEnemies), t(tkSandboxTabBosses), "Pwr", t(tkSandboxTabControls)]
  let tabWidth: int32 = (SIDEBAR_WIDTH - SIDEBAR_PADDING * 5) div 4
  var currentY: int32 = 45

  for i, tabName in tabs:
    let tabX = sidebarX + SIDEBAR_PADDING + i * (tabWidth + SIDEBAR_PADDING)
    let tabColor = if i == game.sandboxSelectedTab:
      Color(r: 70, g: 130, b: 180, a: 255)
    else:
      Color(r: 60, g: 60, b: 60, a: 255)
    drawRectangle(int32(tabX), int32(currentY), int32(tabWidth), int32(TAB_HEIGHT - 5), tabColor)
    let (fittedTabName, fittedTabSize) = fitSandboxText(tabName, tabWidth - 4, 14, 9)
    let textWidth = measureText(fittedTabName, fittedTabSize)
    drawText(fittedTabName, int32(tabX + (tabWidth - textWidth) div 2),
             int32(currentY + 10), fittedTabSize, White)

  currentY += TAB_HEIGHT + 5

  # Keep scrollable tab content from drawing back over the tab strip.
  beginVirtualScissorMode(sidebarX, currentY, SIDEBAR_WIDTH, screenHeight - currentY)

  # Draw content based on selected tab
  case game.sandboxSelectedTab
  of 0:  # Enemies tab
    drawEnemiesTab(game, sidebarX, currentY, screenHeight)
  of 1:  # Bosses tab
    drawBossesTab(game, sidebarX, currentY, screenHeight)
  of 2:  # Power-up visuals tab
    drawPowerUpsVisualsTab(game, sidebarX, currentY, screenHeight)
  of 3:  # Controls tab
    drawControlsTab(game, sidebarX, currentY, screenHeight)
  else:
    discard

  endScissorMode()

  # Draw scrollbar on top of (outside) the scissor region so it is always visible
  drawSandboxScrollbar(game, sidebarX, currentY, screenHeight)

# INPUT HANDLING
proc handleEnemiesTabClick(game: Game, mousePos: Vector2, sidebarX, screenWidth, screenHeight: int32) =
  let startY: int32 = 45 + TAB_HEIGHT + 5
  var currentY: int32 = startY + 10 + 25 - game.sandboxScrollOffset
  let contentX = sidebarX + SIDEBAR_PADDING
  let buttonWidth: int32 = SIDEBAR_WIDTH - SIDEBAR_PADDING * 2

  let enemyTypes = [etCircle, etCube, etTriangle, etStar, etHexagon, etCross,
                    etDiamond, etOctagon, etPentagon, etTrickster, etPhantom, etSniper, etMage]

  for enemyType in enemyTypes:
    if mousePos.x >= contentX.float32 and mousePos.x <= (contentX + buttonWidth).float32 and
       mousePos.y >= currentY.float32 and mousePos.y <= (currentY + BUTTON_HEIGHT).float32:
      # Spawn enemy from side of screen
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
    # Spawn 10 random enemies
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
  let startY: int32 = 45 + TAB_HEIGHT + 5
  var currentY: int32 = startY + 10 + 25 - game.sandboxScrollOffset
  let contentX: int32 = sidebarX + SIDEBAR_PADDING
  let buttonWidth: int32 = SIDEBAR_WIDTH - SIDEBAR_PADDING * 2

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
  let startY: int32 = 45 + TAB_HEIGHT + 5
  var currentY: int32 = startY + 10
  let contentX: int32 = sidebarX + SIDEBAR_PADDING
  let buttonWidth: int32 = SIDEBAR_WIDTH - SIDEBAR_PADDING * 2

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
  currentY += BUTTON_HEIGHT + BUTTON_SPACING + 10

  # Skip "Wave X" text (matches drawing code)
  currentY += 25

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
  currentY += BUTTON_HEIGHT + BUTTON_SPACING + 10

  # Skip "Difficulty X" text (matches drawing code)
  currentY += 25

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
  currentY += BUTTON_HEIGHT + BUTTON_SPACING + 10

  # Skip player stat text labels (matches drawing code)
  currentY += 20  # HP text
  currentY += 20  # Coins text
  currentY += 25  # Enemies text (last one is 25, not 20!)  # Spacing after stats

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

  # Open shop button
  if mousePos.x >= contentX.float32 and mousePos.x <= (contentX + buttonWidth).float32 and
     mousePos.y >= currentY.float32 and mousePos.y <= (currentY + BUTTON_HEIGHT).float32:
    game.state = gsShop
    game.selectedShopItem = 0
    game.shopSidebarScroll = 0
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
    return
  currentY += BUTTON_HEIGHT + BUTTON_SPACING + 10

  # Enter Boss #7 3D Mode button
  if mousePos.x >= contentX.float32 and mousePos.x <= (contentX + buttonWidth).float32 and
     mousePos.y >= currentY.float32 and mousePos.y <= (currentY + BUTTON_HEIGHT).float32:
    # Start transition to 3D mode
    game.transitioning = true
    game.fadeAlpha = 0.0
    return

proc handleSandboxInput*(game: Game, screenWidth, screenHeight: int32) =
  if not game.sandboxSidebarOpen:
    # Check toggle button click
    if isMouseButtonPressed(Left):
      let mousePos = getVirtualMousePosition()
      let toggleX = screenWidth - 50
      let toggleY = screenHeight div 2 - 30
      if mousePos.x >= toggleX.float32 and mousePos.x <= (toggleX + 40).float32 and
         mousePos.y >= toggleY.float32 and mousePos.y <= (toggleY + 60).float32:
        game.sandboxSidebarOpen = true
    return

  clampSandboxScroll(game, screenHeight)

  # Handle scrolling
  let mouseWheel = getMouseWheelMove()
  if mouseWheel != 0:
    game.sandboxScrollOffset -= (mouseWheel * SCROLL_SPEED).int32
    clampSandboxScroll(game, screenHeight)

  # Scrollbar drag
  let sidebarXSb = screenWidth - SIDEBAR_WIDTH
  let contentStartYSb: int32 = 45 + TAB_HEIGHT + 5
  let maxScrollSb = maxSandboxScrollOffset(game.sandboxSelectedTab, screenHeight)
  let contentHSb = sandboxContentHeight(game.sandboxSelectedTab)
  let trackXSb = sidebarXSb + SIDEBAR_WIDTH - SCROLLBAR_WIDTH - 2
  let trackYSb = contentStartYSb + 2
  let trackHSb = screenHeight - contentStartYSb - 4
  let thumbHSb = max(SCROLLBAR_MIN_THUMB,
                     int32(trackHSb.float32 * (trackHSb.float32 / contentHSb.float32)))
  let thumbRangeSb = trackHSb - thumbHSb

  if isMouseButtonPressed(Left):
    let mpSb = getVirtualMousePosition()
    if maxScrollSb > 0 and
       mpSb.x >= trackXSb.float32 and mpSb.x <= (trackXSb + SCROLLBAR_WIDTH).float32 and
       mpSb.y >= trackYSb.float32 and mpSb.y <= (trackYSb + trackHSb).float32:
      let thumbYSb = trackYSb.float32 + thumbRangeSb.float32 *
                     (game.sandboxScrollOffset.float32 / maxScrollSb.float32)
      game.sandboxScrollbarDragging = true
      game.sandboxScrollbarDragOffsetY = mpSb.y - thumbYSb

  if isMouseButtonReleased(Left):
    game.sandboxScrollbarDragging = false

  if game.sandboxScrollbarDragging and isMouseButtonDown(Left):
    let mpDrag = getVirtualMousePosition()
    if maxScrollSb > 0 and thumbRangeSb > 0:
      let newThumbY = mpDrag.y - game.sandboxScrollbarDragOffsetY - trackYSb.float32
      game.sandboxScrollOffset = int32(newThumbY / thumbRangeSb.float32 * maxScrollSb.float32)
      clampSandboxScroll(game, screenHeight)
  # End scrollbar drag

  if isMouseButtonPressed(Left):
    let mousePos = getVirtualMousePosition()
    let sidebarX = screenWidth - SIDEBAR_WIDTH

    # Only process clicks within the sidebar area
    if mousePos.x < sidebarX.float32:
      return

    # Check close button
    let closeX = sidebarX + SIDEBAR_WIDTH - 35
    if mousePos.x >= closeX.float32 and mousePos.x <= (closeX + 30).float32 and
       mousePos.y >= 5 and mousePos.y <= 35:
      game.sandboxSidebarOpen = false
      return

    # Check tabs
    let tabWidth = (SIDEBAR_WIDTH - SIDEBAR_PADDING * 5) div 4
    let tabY = 45
    for i in 0..3:
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
    of 2:  # Power-up visuals tab
      discard
    of 3:  # Controls tab
      handleControlsTabClick(game, mousePos, sidebarX, screenWidth, screenHeight)
    else:
      discard

proc updateSandboxMode*(game: Game, dt: float32) =
  # Apply god mode
  if game.sandboxGodMode:
    game.player.hp = game.player.maxHp
    game.player.invincibilityTimer = 1.0  # Keep invulnerable

  # Freeze enemies if enabled
  if game.sandboxFreezeEnemies:
    # Don't update enemy positions or timers
    return
