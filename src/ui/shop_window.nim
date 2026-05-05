## Shop Window
## OS-themed window for player and bullet customization with tabs

import raylib, os_window, icon_drawing, ../skins, ../bullet_skins, ../bullet_shapes, ../shapes, ../particle_skins, ../types, math, strformat, strutils, ../settings, ../save_system, ../localization, ../render_context, ../roguelite

type
  ShopTab* = enum
    stPlayerSkins    # Player skins tab
    stBulletSkins    # Bullet color skins tab
    stBulletShapes   # Bullet shapes tab
    stShapes         # Player shapes tab
    stParticles      # Particle effects tab
  
  ShopWindow* = ref object
    window*: OSWindow
    currentTab*: ShopTab
    selectedPlayerSkin*: SkinType
    selectedBulletSkin*: BulletSkinType
    selectedShape*: ShapeType
    selectedBulletShape*: BulletShapeType
    selectedParticle*: ParticleSkinType
    rogueliteProfile*: RogueliteProfile
    hoveredSkin*: int  # -1 for none
    scrollOffset*: float32
    animationTime*: float32
    statusMessage*: string
    statusTimer*: float32
    playerSkinChanged*: bool
    bulletSkinChanged*: bool
    shapeChanged*: bool
    bulletShapeChanged*: bool
    particleChanged*: bool
    maxScrollOffset*: float32

const
  SKINS_PER_ROW = 3  # Reduced from 4 to 3 to prevent right-side clipping
  SKIN_BOX_WIDTH = 170  # Increased to give more space
  SKIN_BOX_HEIGHT = 140  # Increased to accommodate 2-line descriptions
  SKIN_BOX_PADDING = 15
  TAB_HEIGHT = 40

proc newShopWindow*(screenWidth, screenHeight: int, currentPlayerSkin: SkinType, currentBulletSkin: BulletSkinType, currentShape: ShapeType, currentParticle: ParticleSkinType, currentBulletShape: BulletShapeType = bshCircle, rogueliteProfile: RogueliteProfile = nil): ShopWindow =
  let windowWidth = 620
  let windowHeight = 450
  let windowX = (screenWidth - windowWidth) div 2
  let windowY = (screenHeight - windowHeight) div 2
  
  let osWin = newOSWindow(
    t("shop_window_title"),
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
    selectedBulletShape: currentBulletShape,
    selectedParticle: currentParticle,
    rogueliteProfile: rogueliteProfile,
    hoveredSkin: -1,
    scrollOffset: 0.0,
    animationTime: 0,
    statusMessage: "",
    statusTimer: 0.0,
    playerSkinChanged: false,
    bulletSkinChanged: false,
    shapeChanged: false,
    bulletShapeChanged: false,
    particleChanged: false,
    maxScrollOffset: 0.0
  )

proc saveSkinSelectionImmediately*(shop: ShopWindow) =
  ## Save skin selection to settings file immediately
  if shop.playerSkinChanged:
    globalSettings.playerSkin = shop.selectedPlayerSkin.int
  if shop.bulletSkinChanged:
    globalSettings.bulletSkin = shop.selectedBulletSkin.int
  if shop.shapeChanged:
    globalSettings.playerShape = shop.selectedShape.int
  if shop.bulletShapeChanged:
    globalSettings.bulletShape = shop.selectedBulletShape.int
  if shop.particleChanged:
    globalSettings.particleEffect = shop.selectedParticle.int
  
  if shop.playerSkinChanged or shop.bulletSkinChanged or shop.shapeChanged or shop.bulletShapeChanged or shop.particleChanged:
    discard saveSettings(globalSettings)
    # Reset change flags after saving
    shop.playerSkinChanged = false
    shop.bulletSkinChanged = false
    shop.shapeChanged = false
    shop.bulletShapeChanged = false
    shop.particleChanged = false

proc cosmeticCostLabel(cost: CosmeticCost): string =
  var parts: seq[string] = @[]
  if cost.dataShards > 0:
    parts.add($cost.dataShards & " " & t("roguelite_shards_short"))
  if cost.overheatCores > 0:
    parts.add($cost.overheatCores & " " & t("roguelite_overheat_short"))
  if cost.singularityCores > 0:
    parts.add($cost.singularityCores & " " & t("roguelite_singularity_short"))
  if parts.len == 0: "FREE" else: parts.join(" + ")

proc drawLockGlyph(x, y: int32, color: Color) =
  drawCircleLines(x + 10, y + 8, 7, color)
  drawRectangle(x + 2, y + 8, 16, 14, Color(r: 20, g: 24, b: 32, a: 235))
  drawRectangleLines(x + 2, y + 8, 16, 14, color)
  drawCircle(Vector2(x: (x + 10).float32, y: (y + 15).float32), 2, color)

proc fitTextSize(text: string, maxWidth: int32, startSize: int32, minSize: int32 = 7): int32 =
  result = startSize
  while result > minSize and measureText(text, result) > maxWidth:
    dec result

proc drawCosmeticCardStatus(x, y: int, isSelected, isUnlocked, canBuy: bool, costText: string) =
  if isUnlocked:
    if isSelected:
      let equipText = t("shop_equipped")
      let equipWidth = measureText(equipText, 11)
      let equipX = x + (SKIN_BOX_WIDTH - equipWidth) div 2
      drawText(equipText, equipX.int32, (y + 125).int32, 11, Color(r: 255, g: 200, b: 100, a: 255))
    return

  let statusColor = if canBuy:
    Color(r: 255, g: 215, b: 80, a: 255)
  else:
    Color(r: 150, g: 150, b: 165, a: 255)
  drawRectangle(x.int32, y.int32, SKIN_BOX_WIDTH.int32, SKIN_BOX_HEIGHT.int32,
                Color(r: 0, g: 0, b: 0, a: 82))
  drawLockGlyph((x + 10).int32, (y + 10).int32, statusColor)

  let statusText = if canBuy:
    t(tkShopBuy) & " " & costText
  else:
    t("roguelite_locked") & " " & costText
  drawRectangle((x + 6).int32, (y + 116).int32, (SKIN_BOX_WIDTH - 12).int32, 20,
                Color(r: 16, g: 20, b: 28, a: 230))
  drawRectangleLines(Rectangle(x: (x + 6).float32, y: (y + 116).float32,
                               width: (SKIN_BOX_WIDTH - 12).float32, height: 20.0),
                     1, statusColor)
  let fontSize = fitTextSize(statusText, (SKIN_BOX_WIDTH - 22).int32, 10, 6)
  let statusWidth = measureText(statusText, fontSize)
  drawText(statusText, (x + (SKIN_BOX_WIDTH - statusWidth) div 2).int32,
           (y + 121).int32, fontSize, statusColor)

proc equipCosmetic(shop: ShopWindow, kind: CosmeticKind, index: int) =
  case kind
  of ckPlayerSkin:
    shop.selectedPlayerSkin = SkinType(index)
    shop.playerSkinChanged = true
  of ckBulletSkin:
    shop.selectedBulletSkin = BulletSkinType(index)
    shop.bulletSkinChanged = true
  of ckPlayerShape:
    shop.selectedShape = ShapeType(index)
    shop.shapeChanged = true
  of ckBulletShape:
    shop.selectedBulletShape = BulletShapeType(index)
    shop.bulletShapeChanged = true
  of ckParticle:
    shop.selectedParticle = ParticleSkinType(index)
    shop.particleChanged = true
  saveSkinSelectionImmediately(shop)

proc handleCosmeticClick(shop: ShopWindow, kind: CosmeticKind, index: int) =
  if not isValidCosmeticIndex(kind, index):
    return
  if cosmeticIsUnlocked(shop.rogueliteProfile, kind, index):
    equipCosmetic(shop, kind, index)
    shop.statusMessage = t("shop_equipped")
    shop.statusTimer = 1.2
  elif purchaseCosmetic(shop.rogueliteProfile, kind, index):
    equipCosmetic(shop, kind, index)
    shop.statusMessage = t("roguelite_unlocked")
    shop.statusTimer = 1.6
  else:
    shop.statusMessage = t("roguelite_not_enough_shards")
    shop.statusTimer = 1.6

proc syncShopSelectionFromSettings(shop: ShopWindow) =
  if shop.isNil or globalSettings.isNil:
    return
  shop.selectedPlayerSkin = SkinType(globalSettings.playerSkin)
  shop.selectedBulletSkin = BulletSkinType(globalSettings.bulletSkin)
  shop.selectedShape = ShapeType(globalSettings.playerShape)
  shop.selectedBulletShape = BulletShapeType(globalSettings.bulletShape)
  shop.selectedParticle = ParticleSkinType(globalSettings.particleEffect)

proc drawPlayerSkinPreview*(x, y: int, skinType: SkinType, shapeType: ShapeType, time: float32, isSelected: bool, isHovered: bool, isUnlocked: bool = true, canBuy: bool = false, costText: string = "") =
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
  
  # Draw mini player with selected shape (like shop icon)
  let centerX = (x + SKIN_BOX_WIDTH div 2).float32
  let centerY = (y + 50).float32
  let playerRadius = 15.0
  
  # Draw player using the shape system
  drawPlayerShape(
    Vector2f(x: centerX, y: centerY),
    playerRadius,
    shapeType,
    primaryColor,
    secondaryColor,
    coreColor,
    time,
    time * 0.5,  # rotation
    0.5,         # pulse
    1.0          # glow intensity
  )
  
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
  
  drawCosmeticCardStatus(x, y, isSelected, isUnlocked, canBuy, costText)

proc drawBulletSkinPreview*(x, y: int, skinType: BulletSkinType, time: float32, isSelected: bool, isHovered: bool, isUnlocked: bool = true, canBuy: bool = false, costText: string = "") =
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
  
  drawCosmeticCardStatus(x, y, isSelected, isUnlocked, canBuy, costText)

proc drawBulletShapePreview*(x, y: int, shapeType: BulletShapeType, time: float32, isSelected: bool, isHovered: bool, isUnlocked: bool = true, canBuy: bool = false, costText: string = "") =
  ## Draw a preview of a player bullet shape
  let bgColor = if isSelected: Color(r: 0, g: 60, b: 80, a: 255)
                elif isHovered: Color(r: 60, g: 60, b: 70, a: 255)
                else: Color(r: 40, g: 40, b: 50, a: 255)
  drawRectangle(x.int32, y.int32, SKIN_BOX_WIDTH.int32, SKIN_BOX_HEIGHT.int32, bgColor)

  let borderColor = if isSelected: Color(r: 255, g: 150, b: 50, a: 255)
                    elif isHovered: Color(r: 120, g: 120, b: 140, a: 255)
                    else: Color(r: 80, g: 80, b: 100, a: 255)
  drawRectangleLines(Rectangle(x: x.float32, y: y.float32,
                                width: SKIN_BOX_WIDTH.float32, height: SKIN_BOX_HEIGHT.float32),
                    2, borderColor)

  # Animated bullet preview: show the shape flying across the card
  let cx = (x + SKIN_BOX_WIDTH div 2).float32
  let cy = (y + 48).float32
  let r = 7.0
  let previewColor = Color(r: 0, g: 200, b: 200, a: 255)
  let glowColor   = Color(r: 0, g: 255, b: 255, a: 80)
  let travelAngle = 0.0  # flying right; arrow uses this for orientation
  drawPlayerBulletShape(Vector2f(x: cx, y: cy), r, shapeType, travelAngle, previewColor, glowColor)

  # Trail dots to give motion feel
  for i in 1..3:
    let tx = cx - i.float32 * 9.0
    let ta = uint8(180 - i * 50)
    drawCircle(Vector2(x: tx, y: cy), r * (1.0 - i.float32 * 0.2),
               Color(r: 0, g: 180, b: 180, a: ta))

  # Name
  let shapeData = getBulletShapeData(shapeType)
  let nameWidth = measureText(shapeData.name, 16)
  drawText(shapeData.name, (x + (SKIN_BOX_WIDTH - nameWidth) div 2).int32, (y + 80).int32, 16, White)

  # Description (wrapped, 2 lines max)
  let desc = shapeData.description
  let maxDescWidth = SKIN_BOX_WIDTH - 10
  var line1 = ""
  var line2 = ""
  var words = desc.split(' ')
  var currentLine = ""
  for word in words:
    let testLine = if currentLine.len > 0: currentLine & " " & word else: word
    if measureText(testLine, 10) <= maxDescWidth:
      currentLine = testLine
    else:
      if line1.len == 0:
        line1 = currentLine
        currentLine = word
      else:
        line2 = currentLine
        break
  if line1.len == 0: line1 = currentLine
  elif line2.len == 0 and currentLine.len > 0: line2 = currentLine

  let d1w = measureText(line1, 10)
  drawText(line1, (x + (SKIN_BOX_WIDTH - d1w) div 2).int32, (y + 100).int32, 10, Gray)
  if line2.len > 0:
    let d2w = measureText(line2, 10)
    drawText(line2, (x + (SKIN_BOX_WIDTH - d2w) div 2).int32, (y + 112).int32, 10, Gray)

  drawCosmeticCardStatus(x, y, isSelected, isUnlocked, canBuy, costText)

proc drawShapePreview*(x, y: int, shapeType: ShapeType, time: float32, isSelected: bool, isHovered: bool, isUnlocked: bool = true, canBuy: bool = false, costText: string = "") =
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
  
  drawCosmeticCardStatus(x, y, isSelected, isUnlocked, canBuy, costText)

proc drawParticlePreview*(x, y: int, particleType: ParticleSkinType, time: float32, isSelected: bool, isHovered: bool, isUnlocked: bool = true, canBuy: bool = false, costText: string = "") =
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
  
  drawCosmeticCardStatus(x, y, isSelected, isUnlocked, canBuy, costText)

proc updateShopWindow*(shop: ShopWindow, dt: float32, allWindows: openArray[OSWindow]): bool =
  ## Update shop window. Returns true if window should close
  if shop.isNil or shop.window.isNil:
    return true
  
  if not shop.window.visible:
    return true
  
  if not globalSettings.isNil:
    if sanitizeEquippedCosmetics(globalSettings, shop.rogueliteProfile):
      discard saveSettings(globalSettings)
    syncShopSelectionFromSettings(shop)

  shop.animationTime += dt
  if shop.statusTimer > 0:
    shop.statusTimer = max(0.0'f32, shop.statusTimer - dt)
  
  updateOSWindow(shop.window, dt)
  
  let shouldClose = handleOSWindowInput(shop.window, 1024, 768, allWindows)
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
  let mousePos = getVirtualMousePosition()
  let mouseX = mousePos.x.int
  let mouseY = mousePos.y.int
  let isTopmost = isWindowTopmostAtPoint(shop.window, mousePos.x, mousePos.y, allWindows)
  
  # Check tab clicks
  let tabY = contentY
  let tabWidth = contentWidth div 5  # 5 tabs
  
  if not shop.window.dragging and mouseY >= tabY and mouseY < tabY + TAB_HEIGHT and isTopmost:
    if shop.window.handledClickThisFrame:
      if mouseX >= contentX and mouseX < contentX + tabWidth:
        shop.currentTab = stPlayerSkins
        shop.scrollOffset = 0.0
      elif mouseX >= contentX + tabWidth and mouseX < contentX + tabWidth * 2:
        shop.currentTab = stBulletSkins
        shop.scrollOffset = 0.0
      elif mouseX >= contentX + tabWidth * 2 and mouseX < contentX + tabWidth * 3:
        shop.currentTab = stShapes
        shop.scrollOffset = 0.0
      elif mouseX >= contentX + tabWidth * 3 and mouseX < contentX + tabWidth * 4:
        shop.currentTab = stBulletShapes
        shop.scrollOffset = 0.0
      elif mouseX >= contentX + tabWidth * 4 and mouseX < contentX + contentWidth:
        shop.currentTab = stParticles
        shop.scrollOffset = 0.0
  
  # Calculate grid area
  let headerHeight = 50
  let gridY = contentY + TAB_HEIGHT + headerHeight
  let infoPanelHeight = 50
  let gridHeight = contentHeight - TAB_HEIGHT - headerHeight - infoPanelHeight
  
  # Get current skins list and calculate rows
  let totalRows = if shop.currentTab == stPlayerSkins:
    let skins = cosmeticCount(ckPlayerSkin)
    (skins + SKINS_PER_ROW - 1) div SKINS_PER_ROW
  elif shop.currentTab == stBulletSkins:
    let skins = cosmeticCount(ckBulletSkin)
    (skins + SKINS_PER_ROW - 1) div SKINS_PER_ROW
  elif shop.currentTab == stShapes:
    let shapes = cosmeticCount(ckPlayerShape)
    (shapes + SKINS_PER_ROW - 1) div SKINS_PER_ROW
  elif shop.currentTab == stBulletShapes:
    let bshapes = cosmeticCount(ckBulletShape)
    (bshapes + SKINS_PER_ROW - 1) div SKINS_PER_ROW
  else:  # stParticles
    let particles = cosmeticCount(ckParticle)
    (particles + SKINS_PER_ROW - 1) div SKINS_PER_ROW
  
  let totalContentHeight = totalRows * (SKIN_BOX_HEIGHT + SKIN_BOX_PADDING) + 10
  
  # Both tabs can scroll freely now
  shop.maxScrollOffset = max(0.0, totalContentHeight.float32 - gridHeight.float32)
  
  # Check if mouse is in grid area
  let inGridArea = mouseX >= contentX and mouseX < contentX + contentWidth and
                   mouseY >= gridY and mouseY < gridY + gridHeight
  
  # Handle scrolling
  if inGridArea and not shop.window.dragging and isTopmost:
    let wheelMove = getMouseWheelMove()
    if wheelMove != 0:
      shop.scrollOffset -= wheelMove * 30.0
      shop.scrollOffset = clamp(shop.scrollOffset, 0.0, shop.maxScrollOffset)
  
  # Reset hover state
  shop.hoveredSkin = -1
  
  # Handle skin selection based on current tab
  if shop.currentTab == stPlayerSkins:
    for skinIndex in 0..<cosmeticCount(ckPlayerSkin):
      let col = skinIndex mod SKINS_PER_ROW
      let row = skinIndex div SKINS_PER_ROW
      
      let boxX = contentX + 5 + col * (SKIN_BOX_WIDTH + SKIN_BOX_PADDING)
      let boxY = gridY + 5 + row * (SKIN_BOX_HEIGHT + SKIN_BOX_PADDING) - shop.scrollOffset.int
      
      if boxY + SKIN_BOX_HEIGHT > gridY and boxY < gridY + gridHeight:
        if inGridArea and not shop.window.dragging and isTopmost:
          if mouseX >= boxX and mouseX < boxX + SKIN_BOX_WIDTH and
             mouseY >= boxY and mouseY < boxY + SKIN_BOX_HEIGHT:
            shop.hoveredSkin = skinIndex
            
            if shop.window.handledClickThisFrame:
              handleCosmeticClick(shop, ckPlayerSkin, skinIndex)
  elif shop.currentTab == stBulletSkins:
    for skinIndex in 0..<cosmeticCount(ckBulletSkin):
      let col = skinIndex mod SKINS_PER_ROW
      let row = skinIndex div SKINS_PER_ROW
      
      let boxX = contentX + 5 + col * (SKIN_BOX_WIDTH + SKIN_BOX_PADDING)
      let boxY = gridY + 5 + row * (SKIN_BOX_HEIGHT + SKIN_BOX_PADDING) - shop.scrollOffset.int
      
      if boxY + SKIN_BOX_HEIGHT > gridY and boxY < gridY + gridHeight:
        if inGridArea and not shop.window.dragging and isTopmost:
          if mouseX >= boxX and mouseX < boxX + SKIN_BOX_WIDTH and
             mouseY >= boxY and mouseY < boxY + SKIN_BOX_HEIGHT:
            shop.hoveredSkin = skinIndex
            
            if shop.window.handledClickThisFrame:
              handleCosmeticClick(shop, ckBulletSkin, skinIndex)
  elif shop.currentTab == stShapes:
    for shapeIndex in 0..<cosmeticCount(ckPlayerShape):
      let col = shapeIndex mod SKINS_PER_ROW
      let row = shapeIndex div SKINS_PER_ROW
      
      let boxX = contentX + 5 + col * (SKIN_BOX_WIDTH + SKIN_BOX_PADDING)
      let boxY = gridY + 5 + row * (SKIN_BOX_HEIGHT + SKIN_BOX_PADDING) - shop.scrollOffset.int
      
      if boxY + SKIN_BOX_HEIGHT > gridY and boxY < gridY + gridHeight:
        if inGridArea and not shop.window.dragging and isTopmost:
          if mouseX >= boxX and mouseX < boxX + SKIN_BOX_WIDTH and
             mouseY >= boxY and mouseY < boxY + SKIN_BOX_HEIGHT:
            shop.hoveredSkin = shapeIndex
            
            if shop.window.handledClickThisFrame:
              handleCosmeticClick(shop, ckPlayerShape, shapeIndex)
  elif shop.currentTab == stBulletShapes:
    for bshapeIndex in 0..<cosmeticCount(ckBulletShape):
      let col = bshapeIndex mod SKINS_PER_ROW
      let row = bshapeIndex div SKINS_PER_ROW
      let boxX = contentX + 5 + col * (SKIN_BOX_WIDTH + SKIN_BOX_PADDING)
      let boxY = gridY + 5 + row * (SKIN_BOX_HEIGHT + SKIN_BOX_PADDING) - shop.scrollOffset.int
      if boxY + SKIN_BOX_HEIGHT > gridY and boxY < gridY + gridHeight:
        if inGridArea and not shop.window.dragging and isTopmost:
          if mouseX >= boxX and mouseX < boxX + SKIN_BOX_WIDTH and
             mouseY >= boxY and mouseY < boxY + SKIN_BOX_HEIGHT:
            shop.hoveredSkin = bshapeIndex
            if shop.window.handledClickThisFrame:
              handleCosmeticClick(shop, ckBulletShape, bshapeIndex)
  elif shop.currentTab == stParticles:
    for particleIndex in 0..<cosmeticCount(ckParticle):
      let col = particleIndex mod SKINS_PER_ROW
      let row = particleIndex div SKINS_PER_ROW
      
      let boxX = contentX + 5 + col * (SKIN_BOX_WIDTH + SKIN_BOX_PADDING)
      let boxY = gridY + 5 + row * (SKIN_BOX_HEIGHT + SKIN_BOX_PADDING) - shop.scrollOffset.int
      
      if boxY + SKIN_BOX_HEIGHT > gridY and boxY < gridY + gridHeight:
        if inGridArea and not shop.window.dragging and isTopmost:
          if mouseX >= boxX and mouseX < boxX + SKIN_BOX_WIDTH and
             mouseY >= boxY and mouseY < boxY + SKIN_BOX_HEIGHT:
            shop.hoveredSkin = particleIndex
            
            if shop.window.handledClickThisFrame:
              handleCosmeticClick(shop, ckParticle, particleIndex)
  
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
  let tabWidth = contentWidth div 5  # 5 tabs
  let tabY = contentY
  
  # Player Skins tab
  let tab1Active = shop.currentTab == stPlayerSkins
  let tab1Color = if tab1Active: Color(r: 40, g: 40, b: 50, a: 255) else: Color(r: 30, g: 30, b: 40, a: 255)
  drawRectangle(contentX.int32, tabY.int32, tabWidth.int32, TAB_HEIGHT.int32, tab1Color)
  if tab1Active:
    drawRectangle(contentX.int32, (tabY + TAB_HEIGHT - 3).int32, tabWidth.int32, 3, Color(r: 255, g: 150, b: 50, a: 255))
  drawText(t("shop_tab_player"), (contentX + tabWidth div 2 - 32).int32, (tabY + 12).int32, 14,
          if tab1Active: White else: Gray)
  
  # Bullet Skins tab
  let tab2Active = shop.currentTab == stBulletSkins
  let tab2Color = if tab2Active: Color(r: 40, g: 40, b: 50, a: 255) else: Color(r: 30, g: 30, b: 40, a: 255)
  drawRectangle((contentX + tabWidth).int32, tabY.int32, tabWidth.int32, TAB_HEIGHT.int32, tab2Color)
  if tab2Active:
    drawRectangle((contentX + tabWidth).int32, (tabY + TAB_HEIGHT - 3).int32, tabWidth.int32, 3, Color(r: 255, g: 150, b: 50, a: 255))
  drawText(t("shop_tab_bullet"), (contentX + tabWidth + tabWidth div 2 - 30).int32, (tabY + 12).int32, 14,
          if tab2Active: White else: Gray)
  
  # Shapes tab
  let tab3Active = shop.currentTab == stShapes
  let tab3Color = if tab3Active: Color(r: 40, g: 40, b: 50, a: 255) else: Color(r: 30, g: 30, b: 40, a: 255)
  drawRectangle((contentX + tabWidth * 2).int32, tabY.int32, tabWidth.int32, TAB_HEIGHT.int32, tab3Color)
  if tab3Active:
    drawRectangle((contentX + tabWidth * 2).int32, (tabY + TAB_HEIGHT - 3).int32, tabWidth.int32, 3, Color(r: 255, g: 150, b: 50, a: 255))
  drawText(t("shop_tab_shapes"), (contentX + tabWidth * 2 + tabWidth div 2 - 32).int32, (tabY + 12).int32, 14,
          if tab3Active: White else: Gray)
  
  # Bullet Shapes tab
  let tab4Active = shop.currentTab == stBulletShapes
  let tab4Color = if tab4Active: Color(r: 40, g: 40, b: 50, a: 255) else: Color(r: 30, g: 30, b: 40, a: 255)
  drawRectangle((contentX + tabWidth * 3).int32, tabY.int32, tabWidth.int32, TAB_HEIGHT.int32, tab4Color)
  if tab4Active:
    drawRectangle((contentX + tabWidth * 3).int32, (tabY + TAB_HEIGHT - 3).int32, tabWidth.int32, 3, Color(r: 255, g: 150, b: 50, a: 255))
  drawText(t("shop_tab_bshapes"), (contentX + tabWidth * 3 + tabWidth div 2 - 34).int32, (tabY + 12).int32, 14,
          if tab4Active: White else: Gray)

  # Particles tab
  let tab5Active = shop.currentTab == stParticles
  let tab5Color = if tab5Active: Color(r: 40, g: 40, b: 50, a: 255) else: Color(r: 30, g: 30, b: 40, a: 255)
  drawRectangle((contentX + tabWidth * 4).int32, tabY.int32, tabWidth.int32, TAB_HEIGHT.int32, tab5Color)
  if tab5Active:
    drawRectangle((contentX + tabWidth * 4).int32, (tabY + TAB_HEIGHT - 3).int32, tabWidth.int32, 3, Color(r: 255, g: 150, b: 50, a: 255))
  drawText(t("shop_tab_particles"), (contentX + tabWidth * 4 + tabWidth div 2 - 40).int32, (tabY + 12).int32, 14,
          if tab5Active: White else: Gray)
  
  # Draw header
  let headerHeight = 50
  let headerY = contentY + TAB_HEIGHT
  let tabTitle = if shop.currentTab == stPlayerSkins:
    t("shop_customize_appearance")
  elif shop.currentTab == stBulletSkins:
    t("shop_customize_bullets")
  elif shop.currentTab == stShapes:
    t("shop_choose_shape")
  elif shop.currentTab == stBulletShapes:
    t("shop_customize_bshapes")
  else:
    t("shop_customize_effects")
  drawText(tabTitle, (contentX + 10).int32, (headerY + 5).int32, 18, Gold)
  if not shop.rogueliteProfile.isNil:
    let balanceY = headerY + 15
    let balanceX = contentX + contentWidth - 238
    drawCurrencyIcon(balanceX.int32, balanceY.int32, 16, ciDataShards)
    drawText($shop.rogueliteProfile.dataShards, (balanceX + 12).int32, (balanceY - 6).int32, 12, Gold)
    drawCurrencyIcon((balanceX + 72).int32, balanceY.int32, 16, ciOverheatCore)
    drawText($shop.rogueliteProfile.overheatCores, (balanceX + 84).int32, (balanceY - 6).int32, 12,
             Color(r: 255, g: 130, b: 80, a: 255))
    drawCurrencyIcon((balanceX + 136).int32, balanceY.int32, 16, ciSingularityCore)
    drawText($shop.rogueliteProfile.singularityCores, (balanceX + 148).int32, (balanceY - 6).int32, 12,
             Color(r: 170, g: 110, b: 255, a: 255))
  elif shop.statusTimer <= 0:
    drawText(t("roguelite_no_profile"), (contentX + contentWidth - 150).int32, (headerY + 12).int32, 12, Red)
  if shop.statusTimer > 0 and shop.statusMessage.len > 0:
    drawText(shop.statusMessage, (contentX + contentWidth - 180).int32, (headerY + 31).int32, 11,
             Color(r: 255, g: 210, b: 110, a: 255))
  
  # Calculate grid area
  let gridY = headerY + headerHeight
  let infoPanelHeight = 50
  let gridHeight = contentHeight - TAB_HEIGHT - headerHeight - infoPanelHeight
  
  # Get skins for current tab
  let totalRows = if shop.currentTab == stPlayerSkins:
    let skins = cosmeticCount(ckPlayerSkin)
    (skins + SKINS_PER_ROW - 1) div SKINS_PER_ROW
  elif shop.currentTab == stBulletSkins:
    let skins = cosmeticCount(ckBulletSkin)
    (skins + SKINS_PER_ROW - 1) div SKINS_PER_ROW
  elif shop.currentTab == stShapes:
    let shapes = cosmeticCount(ckPlayerShape)
    (shapes + SKINS_PER_ROW - 1) div SKINS_PER_ROW
  elif shop.currentTab == stBulletShapes:
    let bshapes = cosmeticCount(ckBulletShape)
    (bshapes + SKINS_PER_ROW - 1) div SKINS_PER_ROW
  else:  # stParticles
    let particles = cosmeticCount(ckParticle)
    (particles + SKINS_PER_ROW - 1) div SKINS_PER_ROW
  
  let totalContentHeight = totalRows * (SKIN_BOX_HEIGHT + SKIN_BOX_PADDING) + 10
  
  # Show scroll hint when content overflows
  if totalContentHeight.float32 > gridHeight.float32:
    drawText(t("shop_scroll_hint"), (contentX + 10).int32, (headerY + 30).int32, 12,
            Color(r: 255, g: 200, b: 100, a: 255))
  else:
    drawText(t("shop_click_equip"), (contentX + 10).int32, (headerY + 30).int32, 13, Gray)
  
  # Draw grid based on current tab
  if shop.currentTab == stPlayerSkins:
    for skinIndex in 0..<cosmeticCount(ckPlayerSkin):
      let skinType = SkinType(skinIndex)
      let col = skinIndex mod SKINS_PER_ROW
      let row = skinIndex div SKINS_PER_ROW
      
      let boxX = contentX + 5 + col * (SKIN_BOX_WIDTH + SKIN_BOX_PADDING)
      let boxY = gridY + 5 + row * (SKIN_BOX_HEIGHT + SKIN_BOX_PADDING) - shop.scrollOffset.int
      
      if boxY + SKIN_BOX_HEIGHT > gridY - 10 and boxY < gridY + gridHeight + 10:
        let isSelected = skinType == shop.selectedPlayerSkin
        let isHovered = skinIndex == shop.hoveredSkin
        let isUnlocked = cosmeticIsUnlocked(shop.rogueliteProfile, ckPlayerSkin, skinIndex)
        let canBuy = canAffordCosmetic(shop.rogueliteProfile, ckPlayerSkin, skinIndex)
        let costText = cosmeticCostLabel(cosmeticCost(ckPlayerSkin, skinIndex))
        
        beginVirtualScissorMode(contentX.int32, gridY.int32, contentWidth.int32, gridHeight.int32)
        drawPlayerSkinPreview(boxX, boxY, skinType, shop.selectedShape, shop.animationTime,
                              isSelected, isHovered, isUnlocked, canBuy, costText)
        endScissorMode()
  elif shop.currentTab == stBulletSkins:
    for skinIndex in 0..<cosmeticCount(ckBulletSkin):
      let skinType = BulletSkinType(skinIndex)
      let col = skinIndex mod SKINS_PER_ROW
      let row = skinIndex div SKINS_PER_ROW
      
      let boxX = contentX + 5 + col * (SKIN_BOX_WIDTH + SKIN_BOX_PADDING)
      let boxY = gridY + 5 + row * (SKIN_BOX_HEIGHT + SKIN_BOX_PADDING) - shop.scrollOffset.int
      
      if boxY + SKIN_BOX_HEIGHT > gridY - 10 and boxY < gridY + gridHeight + 10:
        let isSelected = skinType == shop.selectedBulletSkin
        let isHovered = skinIndex == shop.hoveredSkin
        let isUnlocked = cosmeticIsUnlocked(shop.rogueliteProfile, ckBulletSkin, skinIndex)
        let canBuy = canAffordCosmetic(shop.rogueliteProfile, ckBulletSkin, skinIndex)
        let costText = cosmeticCostLabel(cosmeticCost(ckBulletSkin, skinIndex))
        
        beginVirtualScissorMode(contentX.int32, gridY.int32, contentWidth.int32, gridHeight.int32)
        drawBulletSkinPreview(boxX, boxY, skinType, shop.animationTime, isSelected, isHovered,
                              isUnlocked, canBuy, costText)
        endScissorMode()
  elif shop.currentTab == stShapes:
    for shapeIndex in 0..<cosmeticCount(ckPlayerShape):
      let shapeType = ShapeType(shapeIndex)
      let col = shapeIndex mod SKINS_PER_ROW
      let row = shapeIndex div SKINS_PER_ROW
      
      let boxX = contentX + 5 + col * (SKIN_BOX_WIDTH + SKIN_BOX_PADDING)
      let boxY = gridY + 5 + row * (SKIN_BOX_HEIGHT + SKIN_BOX_PADDING) - shop.scrollOffset.int
      
      if boxY + SKIN_BOX_HEIGHT > gridY - 10 and boxY < gridY + gridHeight + 10:
        let isSelected = shapeType == shop.selectedShape
        let isHovered = shapeIndex == shop.hoveredSkin
        let isUnlocked = cosmeticIsUnlocked(shop.rogueliteProfile, ckPlayerShape, shapeIndex)
        let canBuy = canAffordCosmetic(shop.rogueliteProfile, ckPlayerShape, shapeIndex)
        let costText = cosmeticCostLabel(cosmeticCost(ckPlayerShape, shapeIndex))
        
        beginVirtualScissorMode(contentX.int32, gridY.int32, contentWidth.int32, gridHeight.int32)
        drawShapePreview(boxX, boxY, shapeType, shop.animationTime, isSelected, isHovered,
                         isUnlocked, canBuy, costText)
        endScissorMode()
  elif shop.currentTab == stBulletShapes:
    for bshapeIndex in 0..<cosmeticCount(ckBulletShape):
      let bshapeType = BulletShapeType(bshapeIndex)
      let col = bshapeIndex mod SKINS_PER_ROW
      let row = bshapeIndex div SKINS_PER_ROW
      let boxX = contentX + 5 + col * (SKIN_BOX_WIDTH + SKIN_BOX_PADDING)
      let boxY = gridY + 5 + row * (SKIN_BOX_HEIGHT + SKIN_BOX_PADDING) - shop.scrollOffset.int
      if boxY + SKIN_BOX_HEIGHT > gridY - 10 and boxY < gridY + gridHeight + 10:
        let isSelected = bshapeType == shop.selectedBulletShape
        let isHovered = bshapeIndex == shop.hoveredSkin
        let isUnlocked = cosmeticIsUnlocked(shop.rogueliteProfile, ckBulletShape, bshapeIndex)
        let canBuy = canAffordCosmetic(shop.rogueliteProfile, ckBulletShape, bshapeIndex)
        let costText = cosmeticCostLabel(cosmeticCost(ckBulletShape, bshapeIndex))
        beginVirtualScissorMode(contentX.int32, gridY.int32, contentWidth.int32, gridHeight.int32)
        drawBulletShapePreview(boxX, boxY, bshapeType, shop.animationTime, isSelected, isHovered,
                               isUnlocked, canBuy, costText)
        endScissorMode()
  else:  # stParticles
    for particleIndex in 0..<cosmeticCount(ckParticle):
      let particleType = ParticleSkinType(particleIndex)
      let col = particleIndex mod SKINS_PER_ROW
      let row = particleIndex div SKINS_PER_ROW
      
      let boxX = contentX + 5 + col * (SKIN_BOX_WIDTH + SKIN_BOX_PADDING)
      let boxY = gridY + 5 + row * (SKIN_BOX_HEIGHT + SKIN_BOX_PADDING) - shop.scrollOffset.int
      
      if boxY + SKIN_BOX_HEIGHT > gridY - 10 and boxY < gridY + gridHeight + 10:
        let isSelected = particleType == shop.selectedParticle
        let isHovered = particleIndex == shop.hoveredSkin
        let isUnlocked = cosmeticIsUnlocked(shop.rogueliteProfile, ckParticle, particleIndex)
        let canBuy = canAffordCosmetic(shop.rogueliteProfile, ckParticle, particleIndex)
        let costText = cosmeticCostLabel(cosmeticCost(ckParticle, particleIndex))
        
        beginVirtualScissorMode(contentX.int32, gridY.int32, contentWidth.int32, gridHeight.int32)
        drawParticlePreview(boxX, boxY, particleType, shop.animationTime, isSelected, isHovered,
                            isUnlocked, canBuy, costText)
        endScissorMode()
  
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
    drawText(&"{t(\"shop_currently_equipped\")} {selectedData.name}", (contentX + 10).int32, (infoPanelY + 8).int32, 15, White)
    drawText(selectedData.description, (contentX + 10).int32, (infoPanelY + 28).int32, 12, Gray)
  elif shop.currentTab == stBulletSkins:
    let selectedData = getBulletSkinData(shop.selectedBulletSkin)
    drawText(&"{t(\"shop_currently_equipped\")} {selectedData.name}", (contentX + 10).int32, (infoPanelY + 8).int32, 15, White)
    drawText(selectedData.description, (contentX + 10).int32, (infoPanelY + 28).int32, 12, Gray)
  elif shop.currentTab == stShapes:
    let selectedData = getShapeData(shop.selectedShape)
    drawText(&"{t(\"shop_currently_equipped\")} {selectedData.name}", (contentX + 10).int32, (infoPanelY + 8).int32, 15, White)
    drawText(selectedData.description, (contentX + 10).int32, (infoPanelY + 28).int32, 12, Gray)
  elif shop.currentTab == stBulletShapes:
    let selectedData = getBulletShapeData(shop.selectedBulletShape)
    drawText(&"{t(\"shop_currently_equipped\")} {selectedData.name}", (contentX + 10).int32, (infoPanelY + 8).int32, 15, White)
    drawText(selectedData.description, (contentX + 10).int32, (infoPanelY + 28).int32, 12, Gray)
  else:  # stParticles
    let selectedData = getParticleSkinData(shop.selectedParticle)
    drawText(&"{t(\"shop_currently_equipped\")} {selectedData.name}", (contentX + 10).int32, (infoPanelY + 8).int32, 15, White)
    drawText(selectedData.description, (contentX + 10).int32, (infoPanelY + 28).int32, 12, Gray)
