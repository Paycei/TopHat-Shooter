## Shop Window
## OS-themed window for player and bullet customization with tabs

import raylib, os_window, ../skins, ../bullet_skins, ../shapes, ../particle_skins, ../types, math, strformat, strutils

type
  ShopTab* = enum
    stPlayerSkins    # Player skins tab
    stBulletSkins    # Bullet skins tab
    stShapes         # Player shapes tab
    stParticles      # Particle effects tab
  
  ShopWindow* = ref object
    window*: OSWindow
    currentTab*: ShopTab
    selectedPlayerSkin*: SkinType
    selectedBulletSkin*: BulletSkinType
    selectedShape*: ShapeType
    selectedParticle*: ParticleSkinType
    hoveredSkin*: int  # -1 for none
    scrollOffset*: float32
    animationTime*: float32
    playerSkinChanged*: bool
    bulletSkinChanged*: bool
    shapeChanged*: bool
    particleChanged*: bool
    maxScrollOffset*: float32

const
  SKINS_PER_ROW = 3  # Reduced from 4 to 3 to prevent right-side clipping
  SKIN_BOX_WIDTH = 170  # Increased to give more space
  SKIN_BOX_HEIGHT = 140  # Increased to accommodate 2-line descriptions
  SKIN_BOX_PADDING = 15
  TAB_HEIGHT = 40

proc newShopWindow*(screenWidth, screenHeight: int, currentPlayerSkin: SkinType, currentBulletSkin: BulletSkinType, currentShape: ShapeType, currentParticle: ParticleSkinType): ShopWindow =
  let windowWidth = 620
  let windowHeight = 450
  let windowX = (screenWidth - windowWidth) div 2
  let windowY = (screenHeight - windowHeight) div 2
  
  let osWin = newOSWindow(
    "Customization Shop",
    windowX, windowY,
    windowWidth, windowHeight,
    Color(r: 255, g: 150, b: 50, a: 255),  # Orange accent for shop
    owtSettings,
    resizable = false
  )
  
  osWin.visible = true
  
  result = ShopWindow(
    window: osWin,
    currentTab: stPlayerSkins,
    selectedPlayerSkin: currentPlayerSkin,
    selectedBulletSkin: currentBulletSkin,
    selectedShape: currentShape,
    selectedParticle: currentParticle,
    hoveredSkin: -1,
    scrollOffset: 0.0,
    animationTime: 0,
    playerSkinChanged: false,
    bulletSkinChanged: false,
    shapeChanged: false,
    particleChanged: false,
    maxScrollOffset: 0.0
  )

proc drawPlayerSkinPreview*(x, y: int, skinType: SkinType, time: float32, isSelected: bool, isHovered: bool) =
  ## Draw a preview of a player skin with shop icon style
  let (primaryColor, secondaryColor, coreColor) = getSkinColors(skinType, time)
  
  # Background box
  let bgColor = if isSelected:
    Color(r: 0, g: 60, b: 80, a: 255)
  elif isHovered:
    Color(r: 60, g: 60, b: 70, a: 255)
  else:
    Color(r: 40, g: 40, b: 50, a: 255)
  
  drawRectangle(x.int32, y.int32, SKIN_BOX_WIDTH.int32, SKIN_BOX_HEIGHT.int32, bgColor)
  
  # Border
  let borderColor = if isSelected:
    Color(r: 255, g: 150, b: 50, a: 255)  # Orange border when selected
  elif isHovered:
    Color(r: 120, g: 120, b: 140, a: 255)
  else:
    Color(r: 80, g: 80, b: 100, a: 255)
  
  drawRectangleLines(Rectangle(x: x.float32, y: y.float32,
                                width: SKIN_BOX_WIDTH.float32, height: SKIN_BOX_HEIGHT.float32),
                    2, borderColor)
  
  # Draw mini player with color palette (like shop icon)
  let centerX = (x + SKIN_BOX_WIDTH div 2).float32
  let centerY = (y + 50).float32
  let playerRadius = 15.0
  
  # Main player circle
  drawCircle(Vector2(x: centerX, y: centerY), playerRadius, primaryColor)
  drawCircle(Vector2(x: centerX, y: centerY), playerRadius * 0.6, coreColor)
  
  # Color palette swatches around player
  let swatchSize = 5.float32
  let swatchDist = 22.float32
  let colors = [primaryColor, secondaryColor, coreColor, 
                Color(r: (primaryColor.r + secondaryColor.r) div 2,
                      g: (primaryColor.g + secondaryColor.g) div 2,
                      b: (primaryColor.b + secondaryColor.b) div 2, a: 255)]
  for i in 0..<4:
    let angle = (i.float32 * PI / 2.0) + time * 1.5
    let swatchX = centerX + cos(angle) * swatchDist
    let swatchY = centerY + sin(angle) * swatchDist
    drawCircle(Vector2(x: swatchX, y: swatchY), swatchSize, colors[i])
  
  # Skin name
  let skinData = getSkinData(skinType)
  let nameWidth = measureText(skinData.name, 16)
  let nameX = x + (SKIN_BOX_WIDTH - nameWidth) div 2
  drawText(skinData.name, nameX.int32, (y + 80).int32, 16, White)
  
  # Skin description (2 lines max, wrapped)
  let desc = skinData.description
  let maxDescWidth = SKIN_BOX_WIDTH - 10
  var line1 = ""
  var line2 = ""
  
  # Simple word wrapping
  var words = desc.split(' ')
  var currentLine = ""
  for i, word in words:
    let testLine = if currentLine.len > 0: currentLine & " " & word else: word
    if measureText(testLine, 10) <= maxDescWidth:
      currentLine = testLine
    else:
      if line1.len == 0:
        # First line is full, save it and start second line
        line1 = currentLine
        currentLine = word
      else:
        # Second line would overflow, stop here
        line2 = currentLine
        break
  
  # Handle remaining content
  if line1.len == 0:
    line1 = currentLine
  elif line2.len == 0 and currentLine.len > 0:
    line2 = currentLine
  
  let desc1Width = measureText(line1, 10)
  let desc1X = x + (SKIN_BOX_WIDTH - desc1Width) div 2
  drawText(line1, desc1X.int32, (y + 100).int32, 10, Gray)
  
  if line2.len > 0:
    let desc2Width = measureText(line2, 10)
    let desc2X = x + (SKIN_BOX_WIDTH - desc2Width) div 2
    drawText(line2, desc2X.int32, (y + 112).int32, 10, Gray)
  
  # Selected indicator (moved up to avoid clipping)
  if isSelected:
    let equipText = "[EQUIPPED]"
    let equipWidth = measureText(equipText, 11)
    let equipX = x + (SKIN_BOX_WIDTH - equipWidth) div 2
    drawText(equipText, equipX.int32, (y + 125).int32, 11, Color(r: 255, g: 200, b: 100, a: 255))

proc drawBulletSkinPreview*(x, y: int, skinType: BulletSkinType, time: float32, isSelected: bool, isHovered: bool) =
  ## Draw a preview of a bullet skin
  let (primaryColor, glowColor, trailColor) = getBulletSkinColors(skinType, time)
  
  # Background box
  let bgColor = if isSelected:
    Color(r: 0, g: 60, b: 80, a: 255)
  elif isHovered:
    Color(r: 60, g: 60, b: 70, a: 255)
  else:
    Color(r: 40, g: 40, b: 50, a: 255)
  
  drawRectangle(x.int32, y.int32, SKIN_BOX_WIDTH.int32, SKIN_BOX_HEIGHT.int32, bgColor)
  
  # Border
  let borderColor = if isSelected:
    Color(r: 255, g: 150, b: 50, a: 255)
  elif isHovered:
    Color(r: 120, g: 120, b: 140, a: 255)
  else:
    Color(r: 80, g: 80, b: 100, a: 255)
  
  drawRectangleLines(Rectangle(x: x.float32, y: y.float32,
                                width: SKIN_BOX_WIDTH.float32, height: SKIN_BOX_HEIGHT.float32),
                    2, borderColor)
  
  # Draw bullet trail effect
  let centerX = (x + SKIN_BOX_WIDTH div 2).float32
  let centerY = (y + 50).float32
  let bulletRadius = 6.0
  
  # Trail
  for i in 0..4:
    let trailX = centerX - i.float32 * 8.0
    let trailRadius = bulletRadius * (1.0 - i.float32 * 0.15)
    let trailAlpha = uint8((1.0 - i.float32 * 0.2) * float32(trailColor.a))
    drawCircle(Vector2(x: trailX, y: centerY), trailRadius,
              Color(r: trailColor.r, g: trailColor.g, b: trailColor.b, a: trailAlpha))
  
  # Glow
  for i in 0..2:
    let glowRadius = bulletRadius + (i.float32 + 1) * 3.0
    let glowAlpha = uint8((1.0 - i.float32 / 3.0) * float32(glowColor.a))
    drawCircle(Vector2(x: centerX, y: centerY), glowRadius,
              Color(r: glowColor.r, g: glowColor.g, b: glowColor.b, a: glowAlpha))
  
  # Main bullet
  drawCircle(Vector2(x: centerX, y: centerY), bulletRadius, primaryColor)
  
  # Bullet highlight
  drawCircle(Vector2(x: centerX - 2, y: centerY - 2), bulletRadius * 0.3,
            Color(r: 255, g: 255, b: 255, a: 180))
  
  # Skin name
  let skinData = getBulletSkinData(skinType)
  let nameWidth = measureText(skinData.name, 16)
  let nameX = x + (SKIN_BOX_WIDTH - nameWidth) div 2
  drawText(skinData.name, nameX.int32, (y + 80).int32, 16, White)
  
  # Skin description (2 lines max, wrapped)
  let desc = skinData.description
  let maxDescWidth = SKIN_BOX_WIDTH - 10
  var line1 = ""
  var line2 = ""
  
  # Simple word wrapping
  var words = desc.split(' ')
  var currentLine = ""
  for i, word in words:
    let testLine = if currentLine.len > 0: currentLine & " " & word else: word
    if measureText(testLine, 10) <= maxDescWidth:
      currentLine = testLine
    else:
      if line1.len == 0:
        # First line is full, save it and start second line
        line1 = currentLine
        currentLine = word
      else:
        # Second line would overflow, stop here
        line2 = currentLine
        break
  
  # Handle remaining content
  if line1.len == 0:
    line1 = currentLine
  elif line2.len == 0 and currentLine.len > 0:
    line2 = currentLine
  
  let desc1Width = measureText(line1, 10)
  let desc1X = x + (SKIN_BOX_WIDTH - desc1Width) div 2
  drawText(line1, desc1X.int32, (y + 100).int32, 10, Gray)
  
  if line2.len > 0:
    let desc2Width = measureText(line2, 10)
    let desc2X = x + (SKIN_BOX_WIDTH - desc2Width) div 2
    drawText(line2, desc2X.int32, (y + 112).int32, 10, Gray)
  
  # Selected indicator (moved up to avoid clipping)
  if isSelected:
    let equipText = "[EQUIPPED]"
    let equipWidth = measureText(equipText, 11)
    let equipX = x + (SKIN_BOX_WIDTH - equipWidth) div 2
    drawText(equipText, equipX.int32, (y + 125).int32, 11, Color(r: 255, g: 200, b: 100, a: 255))

proc drawShapePreview*(x, y: int, shapeType: ShapeType, time: float32, isSelected: bool, isHovered: bool) =
  ## Draw a preview of a player shape
  # Background box
  let bgColor = if isSelected:
    Color(r: 0, g: 60, b: 80, a: 255)
  elif isHovered:
    Color(r: 60, g: 60, b: 70, a: 255)
  else:
    Color(r: 40, g: 40, b: 50, a: 255)
  
  drawRectangle(x.int32, y.int32, SKIN_BOX_WIDTH.int32, SKIN_BOX_HEIGHT.int32, bgColor)
  
  # Border
  let borderColor = if isSelected:
    Color(r: 255, g: 150, b: 50, a: 255)  # Orange border when selected
  elif isHovered:
    Color(r: 120, g: 120, b: 140, a: 255)
  else:
    Color(r: 80, g: 80, b: 100, a: 255)
  
  drawRectangleLines(Rectangle(x: x.float32, y: y.float32,
                                width: SKIN_BOX_WIDTH.float32, height: SKIN_BOX_HEIGHT.float32),
                    2, borderColor)
  
  # Draw mini player shape
  let centerX = (x + SKIN_BOX_WIDTH div 2).float32
  let centerY = (y + 50).float32
  let shapeRadius = 15.0
  # Only rotate for hexagon shape
  let rotation = if shapeType == shHexagon: time * 0.5 else: 0.0
  let pulse = sin(time * 2.0) * 0.5 + 0.5
  
  let baseColor = Color(r: 0, g: 200, b: 200, a: 255)
  let secondaryColor = Color(r: 0, g: 150, b: 200, a: 255)
  let coreColor = Color(r: 255, g: 255, b: 255, a: 255)
  let glowIntensity = 0.4 + pulse * 0.2
  
  # Draw shape using the same rendering as in-game
  drawPlayerShape(newVector2f(centerX, centerY), shapeRadius, shapeType,
                 baseColor, secondaryColor, coreColor, time, rotation, pulse, glowIntensity)
  
  # Shape name
  let shapeData = getShapeData(shapeType)
  let nameWidth = measureText(shapeData.name, 16)
  let nameX = x + (SKIN_BOX_WIDTH - nameWidth) div 2
  drawText(shapeData.name, nameX.int32, (y + 80).int32, 16, White)
  
  # Shape description (2 lines max, wrapped)
  let desc = shapeData.description
  let maxDescWidth = SKIN_BOX_WIDTH - 10
  var line1 = ""
  var line2 = ""
  
  # Simple word wrapping
  var words = desc.split(' ')
  var currentLine = ""
  for i, word in words:
    let testLine = if currentLine.len > 0: currentLine & " " & word else: word
    if measureText(testLine, 10) <= maxDescWidth:
      currentLine = testLine
    else:
      if line1.len == 0:
        # First line is full, save it and start second line
        line1 = currentLine
        currentLine = word
      else:
        # Second line would overflow, stop here
        line2 = currentLine
        break
  
  # Handle remaining content
  if line1.len == 0:
    line1 = currentLine
  elif line2.len == 0 and currentLine.len > 0:
    line2 = currentLine
  
  let desc1Width = measureText(line1, 10)
  let desc1X = x + (SKIN_BOX_WIDTH - desc1Width) div 2
  drawText(line1, desc1X.int32, (y + 100).int32, 10, Gray)
  
  if line2.len > 0:
    let desc2Width = measureText(line2, 10)
    let desc2X = x + (SKIN_BOX_WIDTH - desc2Width) div 2
    drawText(line2, desc2X.int32, (y + 112).int32, 10, Gray)
  
  # Selected indicator (moved up to avoid clipping)
  if isSelected:
    let equipText = "[EQUIPPED]"
    let equipWidth = measureText(equipText, 11)
    let equipX = x + (SKIN_BOX_WIDTH - equipWidth) div 2
    drawText(equipText, equipX.int32, (y + 125).int32, 11, Color(r: 255, g: 200, b: 100, a: 255))

proc drawParticlePreview*(x, y: int, particleType: ParticleSkinType, time: float32, isSelected: bool, isHovered: bool) =
  ## Draw a preview of a particle effect
  let (primaryColor, secondaryColor) = getParticleSkinColors(particleType, time)
  
  # Background box
  let bgColor = if isSelected:
    Color(r: 0, g: 60, b: 80, a: 255)
  elif isHovered:
    Color(r: 60, g: 60, b: 70, a: 255)
  else:
    Color(r: 40, g: 40, b: 50, a: 255)
  
  drawRectangle(x.int32, y.int32, SKIN_BOX_WIDTH.int32, SKIN_BOX_HEIGHT.int32, bgColor)
  
  # Border
  let borderColor = if isSelected:
    Color(r: 255, g: 150, b: 50, a: 255)  # Orange border when selected
  elif isHovered:
    Color(r: 120, g: 120, b: 140, a: 255)
  else:
    Color(r: 80, g: 80, b: 100, a: 255)
  
  drawRectangleLines(Rectangle(x: x.float32, y: y.float32,
                                width: SKIN_BOX_WIDTH.float32, height: SKIN_BOX_HEIGHT.float32),
                    2, borderColor)
  
  # Draw particle effect preview
  let centerX = (x + SKIN_BOX_WIDTH div 2).float32
  let centerY = (y + 50).float32
  
  # Draw small bursts of particles radiating outward
  let particleData = getParticleSkinData(particleType)
  let particleCount = min(8, particleData.particleCount)
  
  for i in 0..<particleCount:
    let angle = (i.float32 / particleCount.float32) * PI * 2.0 + time * 2.0
    let distance = 20.0 + sin(time * 3.0 + i.float32) * 5.0
    let px = centerX + cos(angle) * distance
    let py = centerY + sin(angle) * distance
    
    let useSecondary = (i mod 3) == 0
    let color = if useSecondary: secondaryColor else: primaryColor
    let particleSize = 3.0 + sin(time * 4.0 + i.float32) * 1.5
    
    drawCircle(Vector2(x: px, y: py), particleSize, color)
  
  # Particle name
  let particleDataInfo = getParticleSkinData(particleType)
  let nameWidth = measureText(particleDataInfo.name, 16)
  let nameX = x + (SKIN_BOX_WIDTH - nameWidth) div 2
  drawText(particleDataInfo.name, nameX.int32, (y + 80).int32, 16, White)
  
  # Particle description (2 lines max, wrapped)
  let desc = particleDataInfo.description
  let maxDescWidth = SKIN_BOX_WIDTH - 10
  var line1 = ""
  var line2 = ""
  
  # Simple word wrapping
  var words = desc.split(' ')
  var currentLine = ""
  for i, word in words:
    let testLine = if currentLine.len > 0: currentLine & " " & word else: word
    if measureText(testLine, 10) <= maxDescWidth:
      currentLine = testLine
    else:
      if line1.len == 0:
        # First line is full, save it and start second line
        line1 = currentLine
        currentLine = word
      else:
        # Second line would overflow, stop here
        line2 = currentLine
        break
  
  # Handle remaining content
  if line1.len == 0:
    line1 = currentLine
  elif line2.len == 0 and currentLine.len > 0:
    line2 = currentLine
  
  let desc1Width = measureText(line1, 10)
  let desc1X = x + (SKIN_BOX_WIDTH - desc1Width) div 2
  drawText(line1, desc1X.int32, (y + 100).int32, 10, Gray)
  
  if line2.len > 0:
    let desc2Width = measureText(line2, 10)
    let desc2X = x + (SKIN_BOX_WIDTH - desc2Width) div 2
    drawText(line2, desc2X.int32, (y + 112).int32, 10, Gray)
  
  # Selected indicator (moved up to avoid clipping)
  if isSelected:
    let equipText = "[EQUIPPED]"
    let equipWidth = measureText(equipText, 11)
    let equipX = x + (SKIN_BOX_WIDTH - equipWidth) div 2
    drawText(equipText, equipX.int32, (y + 125).int32, 11, Color(r: 255, g: 200, b: 100, a: 255))

proc updateShopWindow*(shop: ShopWindow, dt: float32): bool =
  ## Update shop window. Returns true if window should close
  if shop.isNil or shop.window.isNil:
    return true
  
  if not shop.window.visible:
    return true
  
  shop.animationTime += dt
  
  updateOSWindow(shop.window, dt)
  
  let shouldClose = handleOSWindowInput(shop.window, 1024, 768)
  if shouldClose:
    shop.window.visible = false
    return true
  
  if shop.window.minimized:
    return false
  
  # Get content area
  let contentX = shop.window.x + 10
  let contentY = shop.window.y + TITLE_BAR_HEIGHT + 10
  let contentWidth = shop.window.width - 20
  let contentHeight = shop.window.height - TITLE_BAR_HEIGHT - 20
  
  # Get mouse position
  let mousePos = getMousePosition()
  let mouseX = mousePos.x.int
  let mouseY = mousePos.y.int
  
  # Check tab clicks
  let tabY = contentY
  let tabWidth = contentWidth div 4  # Changed to div 4 for 4 tabs
  
  if not shop.window.dragging and mouseY >= tabY and mouseY < tabY + TAB_HEIGHT:
    if isMouseButtonPressed(MouseButton.Left):
      if mouseX >= contentX and mouseX < contentX + tabWidth:
        shop.currentTab = stPlayerSkins
        shop.scrollOffset = 0.0
      elif mouseX >= contentX + tabWidth and mouseX < contentX + tabWidth * 2:
        shop.currentTab = stBulletSkins
        shop.scrollOffset = 0.0
      elif mouseX >= contentX + tabWidth * 2 and mouseX < contentX + tabWidth * 3:
        shop.currentTab = stShapes
        shop.scrollOffset = 0.0
      elif mouseX >= contentX + tabWidth * 3 and mouseX < contentX + contentWidth:
        shop.currentTab = stParticles
        shop.scrollOffset = 0.0
  
  # Calculate grid area
  let headerHeight = 50
  let gridY = contentY + TAB_HEIGHT + headerHeight
  let infoPanelHeight = 50
  let gridHeight = contentHeight - TAB_HEIGHT - headerHeight - infoPanelHeight
  
  # Get current skins list and calculate rows
  let (totalRows, totalSkins) = if shop.currentTab == stPlayerSkins:
    let skins = getUnlockedSkins().len
    let rows = (skins + SKINS_PER_ROW - 1) div SKINS_PER_ROW
    (rows, skins)
  elif shop.currentTab == stBulletSkins:
    let skins = getUnlockedBulletSkins().len
    let rows = (skins + SKINS_PER_ROW - 1) div SKINS_PER_ROW
    (rows, skins)
  elif shop.currentTab == stShapes:
    let shapes = getUnlockedShapes().len
    let rows = (shapes + SKINS_PER_ROW - 1) div SKINS_PER_ROW
    (rows, shapes)
  else:  # stParticles
    let particles = getUnlockedParticleSkins().len
    let rows = (particles + SKINS_PER_ROW - 1) div SKINS_PER_ROW
    (rows, particles)
  
  let totalContentHeight = totalRows * (SKIN_BOX_HEIGHT + SKIN_BOX_PADDING) + 10
  
  # Both tabs can scroll freely now
  shop.maxScrollOffset = max(0.0, totalContentHeight.float32 - gridHeight.float32)
  
  # Check if mouse is in grid area
  let inGridArea = mouseX >= contentX and mouseX < contentX + contentWidth and
                   mouseY >= gridY and mouseY < gridY + gridHeight
  
  # Handle scrolling
  if inGridArea and not shop.window.dragging:
    let wheelMove = getMouseWheelMove()
    if wheelMove != 0:
      shop.scrollOffset -= wheelMove * 30.0
      shop.scrollOffset = clamp(shop.scrollOffset, 0.0, shop.maxScrollOffset)
  
  # Reset hover state
  shop.hoveredSkin = -1
  
  # Handle skin selection based on current tab
  if shop.currentTab == stPlayerSkins:
    let unlockedPlayerSkins = getUnlockedSkins()
    var skinIndex = 0
    
    for skinType in unlockedPlayerSkins:
      let col = skinIndex mod SKINS_PER_ROW
      let row = skinIndex div SKINS_PER_ROW
      
      let boxX = contentX + 5 + col * (SKIN_BOX_WIDTH + SKIN_BOX_PADDING)
      let boxY = gridY + 5 + row * (SKIN_BOX_HEIGHT + SKIN_BOX_PADDING) - shop.scrollOffset.int
      
      if boxY + SKIN_BOX_HEIGHT > gridY and boxY < gridY + gridHeight:
        if inGridArea and not shop.window.dragging:
          if mouseX >= boxX and mouseX < boxX + SKIN_BOX_WIDTH and
             mouseY >= boxY and mouseY < boxY + SKIN_BOX_HEIGHT:
            shop.hoveredSkin = skinIndex
            
            if isMouseButtonPressed(MouseButton.Left):
              shop.selectedPlayerSkin = skinType
              shop.playerSkinChanged = true
      
      skinIndex += 1
  elif shop.currentTab == stBulletSkins:
    let unlockedBulletSkins = getUnlockedBulletSkins()
    var skinIndex = 0
    
    for skinType in unlockedBulletSkins:
      let col = skinIndex mod SKINS_PER_ROW
      let row = skinIndex div SKINS_PER_ROW
      
      let boxX = contentX + 5 + col * (SKIN_BOX_WIDTH + SKIN_BOX_PADDING)
      let boxY = gridY + 5 + row * (SKIN_BOX_HEIGHT + SKIN_BOX_PADDING) - shop.scrollOffset.int
      
      if boxY + SKIN_BOX_HEIGHT > gridY and boxY < gridY + gridHeight:
        if inGridArea and not shop.window.dragging:
          if mouseX >= boxX and mouseX < boxX + SKIN_BOX_WIDTH and
             mouseY >= boxY and mouseY < boxY + SKIN_BOX_HEIGHT:
            shop.hoveredSkin = skinIndex
            
            if isMouseButtonPressed(MouseButton.Left):
              shop.selectedBulletSkin = skinType
              shop.bulletSkinChanged = true
      
      skinIndex += 1
  elif shop.currentTab == stShapes:
    let unlockedShapes = getUnlockedShapes()
    var shapeIndex = 0
    
    for shapeType in unlockedShapes:
      let col = shapeIndex mod SKINS_PER_ROW
      let row = shapeIndex div SKINS_PER_ROW
      
      let boxX = contentX + 5 + col * (SKIN_BOX_WIDTH + SKIN_BOX_PADDING)
      let boxY = gridY + 5 + row * (SKIN_BOX_HEIGHT + SKIN_BOX_PADDING) - shop.scrollOffset.int
      
      if boxY + SKIN_BOX_HEIGHT > gridY and boxY < gridY + gridHeight:
        if inGridArea and not shop.window.dragging:
          if mouseX >= boxX and mouseX < boxX + SKIN_BOX_WIDTH and
             mouseY >= boxY and mouseY < boxY + SKIN_BOX_HEIGHT:
            shop.hoveredSkin = shapeIndex
            
            if isMouseButtonPressed(MouseButton.Left):
              shop.selectedShape = shapeType
              shop.shapeChanged = true
      
      shapeIndex += 1
  elif shop.currentTab == stParticles:
    let unlockedParticles = getUnlockedParticleSkins()
    var particleIndex = 0
    
    for particleType in unlockedParticles:
      let col = particleIndex mod SKINS_PER_ROW
      let row = particleIndex div SKINS_PER_ROW
      
      let boxX = contentX + 5 + col * (SKIN_BOX_WIDTH + SKIN_BOX_PADDING)
      let boxY = gridY + 5 + row * (SKIN_BOX_HEIGHT + SKIN_BOX_PADDING) - shop.scrollOffset.int
      
      if boxY + SKIN_BOX_HEIGHT > gridY and boxY < gridY + gridHeight:
        if inGridArea and not shop.window.dragging:
          if mouseX >= boxX and mouseX < boxX + SKIN_BOX_WIDTH and
             mouseY >= boxY and mouseY < boxY + SKIN_BOX_HEIGHT:
            shop.hoveredSkin = particleIndex
            
            if isMouseButtonPressed(MouseButton.Left):
              shop.selectedParticle = particleType
              shop.particleChanged = true
      
      particleIndex += 1
  
  return false

proc drawShopWindow*(shop: ShopWindow) =
  ## Draw the shop window
  if shop.isNil or shop.window.isNil:
    return
  
  if not shop.window.visible:
    return
  
  drawWindowChrome(shop.window)
  
  if shop.window.minimized:
    return
  
  # Get content area
  let contentX = shop.window.x + 10
  let contentY = shop.window.y + TITLE_BAR_HEIGHT + 10
  let contentWidth = shop.window.width - 20
  let contentHeight = shop.window.height - TITLE_BAR_HEIGHT - 20
  
  # Draw content background
  drawRectangle(contentX.int32, contentY.int32, contentWidth.int32, contentHeight.int32,
                Color(r: 25, g: 25, b: 35, a: 255))
  
  # Draw tabs
  let tabWidth = contentWidth div 4  # Changed to div 4 for 4 tabs
  let tabY = contentY
  
  # Player Skins tab
  let tab1Active = shop.currentTab == stPlayerSkins
  let tab1Color = if tab1Active: Color(r: 40, g: 40, b: 50, a: 255) else: Color(r: 30, g: 30, b: 40, a: 255)
  drawRectangle(contentX.int32, tabY.int32, tabWidth.int32, TAB_HEIGHT.int32, tab1Color)
  if tab1Active:
    drawRectangle(contentX.int32, (tabY + TAB_HEIGHT - 3).int32, tabWidth.int32, 3, Color(r: 255, g: 150, b: 50, a: 255))
  drawText("PLAYER", (contentX + tabWidth div 2 - 32).int32, (tabY + 12).int32, 14, 
          if tab1Active: White else: Gray)
  
  # Bullet Skins tab
  let tab2Active = shop.currentTab == stBulletSkins
  let tab2Color = if tab2Active: Color(r: 40, g: 40, b: 50, a: 255) else: Color(r: 30, g: 30, b: 40, a: 255)
  drawRectangle((contentX + tabWidth).int32, tabY.int32, tabWidth.int32, TAB_HEIGHT.int32, tab2Color)
  if tab2Active:
    drawRectangle((contentX + tabWidth).int32, (tabY + TAB_HEIGHT - 3).int32, tabWidth.int32, 3, Color(r: 255, g: 150, b: 50, a: 255))
  drawText("BULLET", (contentX + tabWidth + tabWidth div 2 - 30).int32, (tabY + 12).int32, 14,
          if tab2Active: White else: Gray)
  
  # Shapes tab
  let tab3Active = shop.currentTab == stShapes
  let tab3Color = if tab3Active: Color(r: 40, g: 40, b: 50, a: 255) else: Color(r: 30, g: 30, b: 40, a: 255)
  drawRectangle((contentX + tabWidth * 2).int32, tabY.int32, tabWidth.int32, TAB_HEIGHT.int32, tab3Color)
  if tab3Active:
    drawRectangle((contentX + tabWidth * 2).int32, (tabY + TAB_HEIGHT - 3).int32, tabWidth.int32, 3, Color(r: 255, g: 150, b: 50, a: 255))
  drawText("SHAPES", (contentX + tabWidth * 2 + tabWidth div 2 - 32).int32, (tabY + 12).int32, 14,
          if tab3Active: White else: Gray)
  
  # Particles tab
  let tab4Active = shop.currentTab == stParticles
  let tab4Color = if tab4Active: Color(r: 40, g: 40, b: 50, a: 255) else: Color(r: 30, g: 30, b: 40, a: 255)
  drawRectangle((contentX + tabWidth * 3).int32, tabY.int32, tabWidth.int32, TAB_HEIGHT.int32, tab4Color)
  if tab4Active:
    drawRectangle((contentX + tabWidth * 3).int32, (tabY + TAB_HEIGHT - 3).int32, tabWidth.int32, 3, Color(r: 255, g: 150, b: 50, a: 255))
  drawText("PARTICLES", (contentX + tabWidth * 3 + tabWidth div 2 - 40).int32, (tabY + 12).int32, 14,
          if tab4Active: White else: Gray)
  
  # Draw header
  let headerHeight = 50
  let headerY = contentY + TAB_HEIGHT
  let tabTitle = if shop.currentTab == stPlayerSkins: 
    "CUSTOMIZE YOUR APPEARANCE"
  elif shop.currentTab == stBulletSkins:
    "CUSTOMIZE YOUR BULLETS"
  elif shop.currentTab == stShapes:
    "CHOOSE YOUR SHAPE"
  else:
    "CUSTOMIZE SHOOTING EFFECTS"
  drawText(tabTitle, (contentX + 10).int32, (headerY + 5).int32, 18, Gold)
  
  # Calculate grid area
  let gridY = headerY + headerHeight
  let infoPanelHeight = 50
  let gridHeight = contentHeight - TAB_HEIGHT - headerHeight - infoPanelHeight
  
  # Get skins for current tab
  let (totalSkins, totalRows) = if shop.currentTab == stPlayerSkins:
    let skins = getUnlockedSkins().len
    let rows = (skins + SKINS_PER_ROW - 1) div SKINS_PER_ROW
    (skins, rows)
  elif shop.currentTab == stBulletSkins:
    let skins = getUnlockedBulletSkins().len
    let rows = (skins + SKINS_PER_ROW - 1) div SKINS_PER_ROW
    (skins, rows)
  elif shop.currentTab == stShapes:
    let shapes = getUnlockedShapes().len
    let rows = (shapes + SKINS_PER_ROW - 1) div SKINS_PER_ROW
    (shapes, rows)
  else:  # stParticles
    let particles = getUnlockedParticleSkins().len
    let rows = (particles + SKINS_PER_ROW - 1) div SKINS_PER_ROW
    (particles, rows)
  
  let totalContentHeight = totalRows * (SKIN_BOX_HEIGHT + SKIN_BOX_PADDING) + 10
  
  # Show scroll hint when content overflows
  if totalContentHeight.float32 > gridHeight.float32:
    drawText("Scroll with mouse wheel to see all skins", (contentX + 10).int32, (headerY + 30).int32, 12, 
            Color(r: 255, g: 200, b: 100, a: 255))
  else:
    drawText("Click to equip", (contentX + 10).int32, (headerY + 30).int32, 13, Gray)
  
  # Draw grid based on current tab
  if shop.currentTab == stPlayerSkins:
    let unlockedPlayerSkins = getUnlockedSkins()
    var skinIndex = 0
    
    for skinType in unlockedPlayerSkins:
      let col = skinIndex mod SKINS_PER_ROW
      let row = skinIndex div SKINS_PER_ROW
      
      let boxX = contentX + 5 + col * (SKIN_BOX_WIDTH + SKIN_BOX_PADDING)
      let boxY = gridY + 5 + row * (SKIN_BOX_HEIGHT + SKIN_BOX_PADDING) - shop.scrollOffset.int
      
      if boxY + SKIN_BOX_HEIGHT > gridY - 10 and boxY < gridY + gridHeight + 10:
        let isSelected = skinType == shop.selectedPlayerSkin
        let isHovered = skinIndex == shop.hoveredSkin
        
        beginScissorMode(contentX.int32, gridY.int32, contentWidth.int32, gridHeight.int32)
        drawPlayerSkinPreview(boxX, boxY, skinType, shop.animationTime, isSelected, isHovered)
        endScissorMode()
      
      skinIndex += 1
  elif shop.currentTab == stBulletSkins:
    let unlockedBulletSkins = getUnlockedBulletSkins()
    var skinIndex = 0
    
    for skinType in unlockedBulletSkins:
      let col = skinIndex mod SKINS_PER_ROW
      let row = skinIndex div SKINS_PER_ROW
      
      let boxX = contentX + 5 + col * (SKIN_BOX_WIDTH + SKIN_BOX_PADDING)
      let boxY = gridY + 5 + row * (SKIN_BOX_HEIGHT + SKIN_BOX_PADDING) - shop.scrollOffset.int
      
      if boxY + SKIN_BOX_HEIGHT > gridY - 10 and boxY < gridY + gridHeight + 10:
        let isSelected = skinType == shop.selectedBulletSkin
        let isHovered = skinIndex == shop.hoveredSkin
        
        beginScissorMode(contentX.int32, gridY.int32, contentWidth.int32, gridHeight.int32)
        drawBulletSkinPreview(boxX, boxY, skinType, shop.animationTime, isSelected, isHovered)
        endScissorMode()
      
      skinIndex += 1
  elif shop.currentTab == stShapes:
    let unlockedShapes = getUnlockedShapes()
    var shapeIndex = 0
    
    for shapeType in unlockedShapes:
      let col = shapeIndex mod SKINS_PER_ROW
      let row = shapeIndex div SKINS_PER_ROW
      
      let boxX = contentX + 5 + col * (SKIN_BOX_WIDTH + SKIN_BOX_PADDING)
      let boxY = gridY + 5 + row * (SKIN_BOX_HEIGHT + SKIN_BOX_PADDING) - shop.scrollOffset.int
      
      if boxY + SKIN_BOX_HEIGHT > gridY - 10 and boxY < gridY + gridHeight + 10:
        let isSelected = shapeType == shop.selectedShape
        let isHovered = shapeIndex == shop.hoveredSkin
        
        beginScissorMode(contentX.int32, gridY.int32, contentWidth.int32, gridHeight.int32)
        drawShapePreview(boxX, boxY, shapeType, shop.animationTime, isSelected, isHovered)
        endScissorMode()
      
      shapeIndex += 1
  else:  # stParticles
    let unlockedParticles = getUnlockedParticleSkins()
    var particleIndex = 0
    
    for particleType in unlockedParticles:
      let col = particleIndex mod SKINS_PER_ROW
      let row = particleIndex div SKINS_PER_ROW
      
      let boxX = contentX + 5 + col * (SKIN_BOX_WIDTH + SKIN_BOX_PADDING)
      let boxY = gridY + 5 + row * (SKIN_BOX_HEIGHT + SKIN_BOX_PADDING) - shop.scrollOffset.int
      
      if boxY + SKIN_BOX_HEIGHT > gridY - 10 and boxY < gridY + gridHeight + 10:
        let isSelected = particleType == shop.selectedParticle
        let isHovered = particleIndex == shop.hoveredSkin
        
        beginScissorMode(contentX.int32, gridY.int32, contentWidth.int32, gridHeight.int32)
        drawParticlePreview(boxX, boxY, particleType, shop.animationTime, isSelected, isHovered)
        endScissorMode()
      
      particleIndex += 1
  
  # Draw scrollbar if needed
  if shop.maxScrollOffset > 0:
    let scrollbarX = contentX + contentWidth - 15
    let scrollbarWidth = 10
    
    drawRectangle(scrollbarX.int32, gridY.int32, scrollbarWidth.int32, gridHeight.int32,
                  Color(r: 40, g: 40, b: 50, a: 255))
    
    let thumbHeight = max(30.0, (gridHeight.float32 / totalContentHeight.float32) * gridHeight.float32)
    let thumbY = gridY.float32 + (shop.scrollOffset / shop.maxScrollOffset) * (gridHeight.float32 - thumbHeight)
    
    drawRectangle(scrollbarX.int32, thumbY.int32, scrollbarWidth.int32, thumbHeight.int32,
                  Color(r: 255, g: 150, b: 50, a: 200))
  
  # Draw info panel
  let infoPanelY = contentY + contentHeight - infoPanelHeight
  drawRectangle(contentX.int32, infoPanelY.int32, contentWidth.int32, infoPanelHeight.int32,
                Color(r: 35, g: 35, b: 45, a: 255))
  
  # Show selected info
  if shop.currentTab == stPlayerSkins:
    let selectedData = getSkinData(shop.selectedPlayerSkin)
    drawText(&"Currently Equipped: {selectedData.name}", (contentX + 10).int32, (infoPanelY + 8).int32, 15, White)
    drawText(selectedData.description, (contentX + 10).int32, (infoPanelY + 28).int32, 12, Gray)
  elif shop.currentTab == stBulletSkins:
    let selectedData = getBulletSkinData(shop.selectedBulletSkin)
    drawText(&"Currently Equipped: {selectedData.name}", (contentX + 10).int32, (infoPanelY + 8).int32, 15, White)
    drawText(selectedData.description, (contentX + 10).int32, (infoPanelY + 28).int32, 12, Gray)
  elif shop.currentTab == stShapes:
    let selectedData = getShapeData(shop.selectedShape)
    drawText(&"Currently Equipped: {selectedData.name}", (contentX + 10).int32, (infoPanelY + 8).int32, 15, White)
    drawText(selectedData.description, (contentX + 10).int32, (infoPanelY + 28).int32, 12, Gray)
  else:  # stParticles
    let selectedData = getParticleSkinData(shop.selectedParticle)
    drawText(&"Currently Equipped: {selectedData.name}", (contentX + 10).int32, (infoPanelY + 8).int32, 15, White)
    drawText(selectedData.description, (contentX + 10).int32, (infoPanelY + 28).int32, 12, Gray)
