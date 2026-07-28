## Shop Window
## OS-themed window for player and bullet customization with tabs

import raylib, rlgl, math, strformat, strutils
import particle_types, os_window, os_desktop, background_fx, desktop_bg_fx, icon_drawing, ../skins, ../bullet_skins, ../bullet_shapes, ../shapes, ../particle_skins, ../desktop_bg_skins, ../cube_skins, ../types, ../settings, ../save_system, ../localization, ../render_context, ../roguelite, ../sound, ../utils

type
  ShopTab* = enum
    stPlayerSkins    # Player skins tab
    stBulletSkins    # Bullet color skins tab
    stBulletShapes   # Bullet shapes tab
    stShapes         # Player shapes tab
    stParticles      # Particle effects tab
    stDesktopBg      # Desktop background skins tab
    stCubeSkins      # Cube skins tab
    stSecret         # Secret items tab (victory-unlocked cosmetics)
    stPacks          # Cosmetic packs tab (discounted theme bundles)

  ShopWindow* = ref object
    window*: OSWindow
    currentTab*: ShopTab
    selectedPlayerSkin*: SkinType
    selectedBulletSkin*: BulletSkinType
    selectedShape*: ShapeType
    selectedBulletShape*: BulletShapeType
    selectedParticle*: ParticleSkinType
    selectedDesktopBg*: DesktopBgType
    selectedCubeSkin*: CubeSkinType
    rogueliteProfile*: RogueliteProfile
    hoveredSkin*: int  # -1 for none
    scrollOffset*: float32
    scrollVelocity*: float32
    searchQuery*: string
    searchFocused*: bool
    searchVisible*: bool
    focusIndex*: int    # Focused index within the filtered list (0..n-1)
    previewOpen*: bool
    previewKind*: CosmeticKind
    previewIndex*: int
    animationTime*: float32
    statusMessage*: string
    statusTimer*: float32
    playerSkinChanged*: bool
    bulletSkinChanged*: bool
    shapeChanged*: bool
    bulletShapeChanged*: bool
    particleChanged*: bool
    desktopBgChanged*: bool
    cubeSkinChanged*: bool
    maxScrollOffset*: float32

const
  SKIN_BOX_WIDTH = 170  # Increased to give more space
  SKIN_BOX_HEIGHT = 140  # Increased to accommodate 2-line descriptions
  SKIN_BOX_PADDING = 15
  TAB_HEIGHT = 40
  PREVIEW_BOX_WIDTH = 420
  PREVIEW_BOX_HEIGHT = 360
  SHOP_TAB_COUNT = 9
  SECRET_CARD_W = 240
  SECRET_CARD_H = 220
  SECRET_CARD_GAP = 40
  SECRET_ITEM_COUNT = 3  # 0 = kernel tophat, 1 = orbital cube, 2 = cheater hat
  PACK_CARD_W = 236      # Packs tab: bundle cards (wider than skin cards)
  PACK_CARD_H = 156
  PACK_CARD_PAD = 16
  PACK_HEADER_H = 46

proc newShopWindow*(screenWidth, screenHeight: int, currentPlayerSkin: SkinType, currentBulletSkin: BulletSkinType, currentShape: ShapeType, currentParticle: ParticleSkinType, currentBulletShape: BulletShapeType = bshCircle, rogueliteProfile: RogueliteProfile = nil): ShopWindow =
  let windowWidth = 820
  let windowHeight = 560
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
    selectedDesktopBg: DesktopBgType(0),
    selectedCubeSkin: CubeSkinType(0),
    rogueliteProfile: rogueliteProfile,
    hoveredSkin: -1,
    scrollOffset: 0.0,
    scrollVelocity: 0.0,
    searchQuery: "",
    searchFocused: false,
    searchVisible: false,
    focusIndex: 0,
    previewOpen: false,
    previewKind: ckPlayerSkin,
    previewIndex: -1,
    animationTime: 0,
    statusMessage: "",
    statusTimer: 0.0,
    playerSkinChanged: false,
    bulletSkinChanged: false,
    shapeChanged: false,
    bulletShapeChanged: false,
    particleChanged: false,
    desktopBgChanged: false,
    cubeSkinChanged: false,
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
  if shop.desktopBgChanged:
    globalSettings.desktopBg = shop.selectedDesktopBg.int
  if shop.cubeSkinChanged:
    globalSettings.cubeSkin = shop.selectedCubeSkin.int

  if shop.playerSkinChanged or shop.bulletSkinChanged or shop.shapeChanged or
     shop.bulletShapeChanged or shop.particleChanged or
     shop.desktopBgChanged or shop.cubeSkinChanged:
    discard saveSettings(globalSettings)
    shop.playerSkinChanged = false
    shop.bulletSkinChanged = false
    shop.shapeChanged = false
    shop.bulletShapeChanged = false
    shop.particleChanged = false
    shop.desktopBgChanged = false
    shop.cubeSkinChanged = false

proc cosmeticCostLabel(cost: CosmeticCost): string =
  var parts: seq[string] = @[]
  if cost.dataShards > 0:
    parts.add($cost.dataShards & " " & t("roguelite_shards_short"))
  if cost.cores > 0:
    parts.add($cost.cores & " " & t("roguelite_cores_short"))
  if parts.len == 0: "FREE" else: parts.join(" + ")

proc secretCardPos(contentX, contentY, contentWidth, index: int): tuple[x, y: int] =
  ## Layout for the SECRET tab's row of centered cards (shared by update/draw).
  let totalW = SECRET_ITEM_COUNT * SECRET_CARD_W + (SECRET_ITEM_COUNT - 1) * SECRET_CARD_GAP
  let left = contentX + (contentWidth - totalW) div 2
  (x: left + index * (SECRET_CARD_W + SECRET_CARD_GAP), y: contentY + TAB_HEIGHT + 60)

proc drawLockGlyph(x, y: int32, color: Color) =
  drawCircleLines(x + 10, y + 8, 7, color)
  drawRectangle(x + 2, y + 8, 16, 14, Color(r: 20, g: 24, b: 32, a: 235))
  drawRectangleLines(x + 2, y + 8, 16, 14, color)
  drawCircle(Vector2(x: (x + 10).float32, y: (y + 15).float32), 2, color)

proc fitTextSize(text: string, maxWidth: int32, startSize: int32, minSize: int32 = 7): int32 =
  result = startSize
  while result > minSize and measureText(text, result) > maxWidth:
    dec result

proc wrapTwoLines*(text: string, maxWidth: int32, fontSize: int32 = 10): tuple[line1: string, line2: string] =
  var line1 = ""
  var line2 = ""
  var words = text.split(' ')
  var currentLine = ""
  for w in words:
    let testLine = if currentLine.len > 0: currentLine & " " & w else: w
    if measureText(testLine, fontSize) <= maxWidth:
      currentLine = testLine
    else:
      if line1.len == 0:
        line1 = currentLine
        currentLine = w
      else:
        line2 = currentLine
        break
  if line1.len == 0:
    line1 = currentLine
  elif line2.len == 0 and currentLine.len > 0:
    line2 = currentLine
  return (line1: line1, line2: line2)

proc wrapIntoLines(text: string, maxWidth: int32, fontSize: int32, maxLines: int): seq[string] =
  result = @[]
  var cur = ""
  for w in text.split(' '):
    let test = if cur.len > 0: cur & " " & w else: w
    if measureText(test, fontSize) <= maxWidth:
      cur = test
    else:
      if result.len < maxLines - 1:
        if cur.len > 0: result.add(cur)
        cur = w
      else:
        break
  if cur.len > 0 and result.len < maxLines:
    result.add(cur)

proc wrapDescAutoSize*(text: string, maxWidth: int32, startSize: int32 = 11, minSize: int32 = 8): tuple[line1, line2, line3: string, fontSize: int32] =
  for size in countdown(startSize, minSize):
    let lines = wrapIntoLines(text, maxWidth, size, 3)
    if lines.join(" ").strip() == text.strip():
      return (line1: if lines.len > 0: lines[0] else: "",
              line2: if lines.len > 1: lines[1] else: "",
              line3: if lines.len > 2: lines[2] else: "",
              fontSize: size)
  let lines = wrapIntoLines(text, maxWidth, minSize, 3)
  return (line1: if lines.len > 0: lines[0] else: "",
          line2: if lines.len > 1: lines[1] else: "",
          line3: if lines.len > 2: lines[2] else: "",
          fontSize: minSize)

proc visibleCosmeticIndices*(kind: CosmeticKind, query: string): seq[int] =
  var q = query.toLowerAscii()
  result = @[]
  for i in 0..<cosmeticCount(kind):
    var name = ""
    case kind
    of ckPlayerSkin:
      name = getSkinData(SkinType(i)).name
    of ckBulletSkin:
      name = getBulletSkinData(BulletSkinType(i)).name
    of ckPlayerShape:
      name = getShapeData(ShapeType(i)).name
    of ckBulletShape:
      name = getBulletShapeData(BulletShapeType(i)).name
    of ckParticle:
      name = getParticleSkinData(ParticleSkinType(i)).name
    of ckDesktopBg:
      name = getDesktopBgData(DesktopBgType(i)).name
    of ckCubeSkin:
      name = getCubeSkinData(CubeSkinType(i)).name

    if q.len == 0 or name.toLowerAscii().contains(q):
      result.add(i)

proc drawCosmeticCardStatus(x, y: int, isSelected, isUnlocked, canBuy: bool, cost: CosmeticCost, costText: string = "") =
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

  # Draw status pill and currency icons to the right
  let pillX = (x + 6).int32
  let pillY = (y + 116).int32
  let pillW = (SKIN_BOX_WIDTH - 12).int32
  let pillH: int32 = 20
  drawRectangle(pillX, pillY, pillW, pillH, Color(r: 16, g: 20, b: 28, a: 230))
  drawRectangleLines(Rectangle(x: pillX.float32, y: pillY.float32, width: pillW.float32, height: pillH.float32), 1.0'f32, statusColor)

  let statusText = if canBuy: t(tkShopBuy) else: t("roguelite_locked")

  var parts: seq[tuple[icon: CurrencyIconType, amount: int]] = @[]
  if cost.cores > 0:
    parts.add((icon: ciCore, amount: cost.cores))
  if cost.dataShards > 0:
    parts.add((icon: ciDataShards, amount: cost.dataShards))

  if parts.len == 0:
    let fontSize = fitTextSize(statusText, pillW - 8, 10, 6)
    let statusWidth = measureText(statusText, fontSize)
    drawText(statusText, (x + (SKIN_BOX_WIDTH - statusWidth) div 2).int32, (y + 121).int32, fontSize, statusColor)
    return

  # compute icon area width
  let iconSize: int32 = 14
  let paddingBetween: int32 = 6
  let interPartGap: int32 = 8
  var iconAreaWidth: int32 = 0
  for p in parts:
    let txtW = int32(measureText($p.amount, 11))
    iconAreaWidth += iconSize + paddingBetween + txtW + interPartGap

  let fontSize = fitTextSize(statusText, pillW - iconAreaWidth - 8, 10, 6)
  let statusWidth = measureText(statusText, fontSize)
  let statusX = x + (SKIN_BOX_WIDTH - statusWidth - iconAreaWidth) div 2
  drawText(statusText, statusX.int32, (y + 121).int32, fontSize, statusColor)

  var iconX = statusX.int32 + statusWidth + 8
  let iconCY = pillY + pillH div 2
  for p in parts:
    let txt = $p.amount
    drawCurrencyIcon(iconX + iconSize div 2, iconCY, iconSize, p.icon)
    let txtX = iconX + iconSize + paddingBetween
    drawText(txt, txtX, pillY + 3, 11, statusColor)
    let txtW = int32(measureText(txt, 11))
    iconX += iconSize + paddingBetween + txtW + interPartGap

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
  of ckDesktopBg:
    shop.selectedDesktopBg = DesktopBgType(index)
    shop.desktopBgChanged = true
  of ckCubeSkin:
    shop.selectedCubeSkin = CubeSkinType(index)
    shop.cubeSkinChanged = true
  saveSkinSelectionImmediately(shop)

proc handleCosmeticClick(shop: ShopWindow, kind: CosmeticKind, index: int) =
  if not isValidCosmeticIndex(kind, index):
    return
  if cosmeticIsUnlocked(shop.rogueliteProfile, kind, index):
    equipCosmetic(shop, kind, index)
    shop.statusMessage = t("shop_equipped")
    shop.statusTimer = 1.2
  elif purchaseCosmetic(shop.rogueliteProfile, kind, index):
    playSound(stBuy)
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
  shop.selectedDesktopBg = DesktopBgType(globalSettings.desktopBg)
  shop.selectedCubeSkin = CubeSkinType(globalSettings.cubeSkin)

proc drawPlayerSkinPreview*(x, y: int, skinType: SkinType, shapeType: ShapeType, time: float32, isSelected: bool, isHovered: bool, isUnlocked: bool = true, canBuy: bool = false, cost: CosmeticCost, costText: string = "") =
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

  let borderThickness = if isHovered or isSelected: 3.0'f32 else: 2.0'f32
  drawRectangleLines(Rectangle(x: x.float32, y: y.float32,
                                width: SKIN_BOX_WIDTH.float32, height: SKIN_BOX_HEIGHT.float32),
                    borderThickness, borderColor)

  # Draw mini player with selected shape (like shop icon)
  let centerX = (x + SKIN_BOX_WIDTH div 2).float32
  let centerY = (y + 50).float32
  let hoverScale = if isHovered: 1.06'f32 else: 1.0'f32
  let playerRadius = 15.0 * hoverScale

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
  let nameSize: int32 = if isHovered: 17 else: 16
  let nameWidth = measureText(skinData.name, nameSize)
  let nameX = x + (SKIN_BOX_WIDTH - nameWidth) div 2
  drawText(skinData.name, nameX.int32, (y + 80).int32, nameSize, White)

  # Skin description (2 lines max, auto-sized)
  let desc = skinData.description
  let maxDescWidth = SKIN_BOX_WIDTH - 10
  let wrapped = wrapDescAutoSize(desc, maxDescWidth.int32)
  let descFont = wrapped.fontSize
  let desc1Width = measureText(wrapped.line1, descFont)
  let desc1X = x + (SKIN_BOX_WIDTH - desc1Width) div 2
  drawText(wrapped.line1, desc1X.int32, (y + 100).int32, descFont, Gray)
  if wrapped.line2.len > 0:
    let desc2Width = measureText(wrapped.line2, descFont)
    let desc2X = x + (SKIN_BOX_WIDTH - desc2Width) div 2
    drawText(wrapped.line2, desc2X.int32, (y + 112).int32, descFont, Gray)
  if wrapped.line3.len > 0:
    let desc3Width = measureText(wrapped.line3, descFont)
    let desc3X = x + (SKIN_BOX_WIDTH - desc3Width) div 2
    drawText(wrapped.line3, desc3X.int32, (y + 124).int32, descFont, Gray)

  drawCosmeticCardStatus(x, y, isSelected, isUnlocked, canBuy, cost, costText)

proc drawBulletSkinPreview*(x, y: int, skinType: BulletSkinType, time: float32, isSelected: bool, isHovered: bool, isUnlocked: bool = true, canBuy: bool = false, cost: CosmeticCost, costText: string = "") =
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
  let borderThickness = if isHovered or isSelected: 3.0'f32 else: 2.0'f32
  drawRectangleLines(Rectangle(x: x.float32, y: y.float32,
                                width: SKIN_BOX_WIDTH.float32, height: SKIN_BOX_HEIGHT.float32),
                    borderThickness, borderColor)

  # Draw bullet trail effect
  let centerX = (x + SKIN_BOX_WIDTH div 2).float32
  let centerY = (y + 50).float32
  let hoverScale = if isHovered: 1.06'f32 else: 1.0'f32
  let bulletRadius = 6.0 * hoverScale

  # Trail
  for i in 0..4:
    let trailX = centerX - i.float32 * 8.0
    let trailRadius = bulletRadius * (1.0 - i.float32 * 0.15)
    let trailAlpha = uint8((1.0 - i.float32 * 0.2) * float32(trailColor.a))
    drawCircle(Vector2(x: trailX, y: centerY), trailRadius,
              withAlpha(trailColor, trailAlpha))

  # Glow
  for i in 0..2:
    let glowRadius = bulletRadius + (i.float32 + 1) * 3.0
    let glowAlpha = uint8((1.0 - i.float32 / 3.0) * float32(glowColor.a))
    drawCircle(Vector2(x: centerX, y: centerY), glowRadius,
              withAlpha(glowColor, glowAlpha))

  # Main bullet
  drawCircle(Vector2(x: centerX, y: centerY), bulletRadius, primaryColor)

  # Bullet highlight
  drawCircle(Vector2(x: centerX - 2, y: centerY - 2), bulletRadius * 0.3,
            Color(r: 255, g: 255, b: 255, a: 180))

  # Skin name
  let skinData = getBulletSkinData(skinType)
  let nameSize: int32 = if isHovered: 17 else: 16
  let nameWidth = measureText(skinData.name, nameSize)
  let nameX = x + (SKIN_BOX_WIDTH - nameWidth) div 2
  drawText(skinData.name, nameX.int32, (y + 80).int32, nameSize, White)

  # Skin description (2 lines max, auto-sized)
  let desc = skinData.description
  let maxDescWidth = SKIN_BOX_WIDTH - 10
  let wrapped = wrapDescAutoSize(desc, maxDescWidth.int32)
  let descFont = wrapped.fontSize
  let desc1Width = measureText(wrapped.line1, descFont)
  let desc1X = x + (SKIN_BOX_WIDTH - desc1Width) div 2
  drawText(wrapped.line1, desc1X.int32, (y + 100).int32, descFont, Gray)
  if wrapped.line2.len > 0:
    let desc2Width = measureText(wrapped.line2, descFont)
    let desc2X = x + (SKIN_BOX_WIDTH - desc2Width) div 2
    drawText(wrapped.line2, desc2X.int32, (y + 112).int32, descFont, Gray)
  if wrapped.line3.len > 0:
    let desc3Width = measureText(wrapped.line3, descFont)
    let desc3X = x + (SKIN_BOX_WIDTH - desc3Width) div 2
    drawText(wrapped.line3, desc3X.int32, (y + 124).int32, descFont, Gray)

  drawCosmeticCardStatus(x, y, isSelected, isUnlocked, canBuy, cost, costText)

proc drawBulletShapePreview*(x, y: int, shapeType: BulletShapeType, time: float32, isSelected: bool, isHovered: bool, isUnlocked: bool = true, canBuy: bool = false, cost: CosmeticCost, costText: string = "") =
  ## Draw a preview of a player bullet shape
  let bgColor = if isSelected: Color(r: 0, g: 60, b: 80, a: 255)
                elif isHovered: Color(r: 60, g: 60, b: 70, a: 255)
                else: Color(r: 40, g: 40, b: 50, a: 255)
  drawRectangle(x.int32, y.int32, SKIN_BOX_WIDTH.int32, SKIN_BOX_HEIGHT.int32, bgColor)

  let borderColor = if isSelected: Color(r: 255, g: 150, b: 50, a: 255)
                    elif isHovered: Color(r: 120, g: 120, b: 140, a: 255)
                    else: Color(r: 80, g: 80, b: 100, a: 255)
  let borderThickness = if isHovered or isSelected: 3.0'f32 else: 2.0'f32
  drawRectangleLines(Rectangle(x: x.float32, y: y.float32,
                                width: SKIN_BOX_WIDTH.float32, height: SKIN_BOX_HEIGHT.float32),
                    borderThickness, borderColor)

  # Animated bullet preview: show the shape flying across the card
  let cx = (x + SKIN_BOX_WIDTH div 2).float32
  let cy = (y + 48).float32
  let r = 7.0
  let hoverScale = if isHovered: 1.06'f32 else: 1.0'f32
  let rScaled = r * hoverScale
  let previewColor = Color(r: 0, g: 200, b: 200, a: 255)
  let glowColor   = Color(r: 0, g: 255, b: 255, a: 80)
  let travelAngle = 0.0  # flying right, arrow uses this for orientation
  drawPlayerBulletShape(Vector2f(x: cx, y: cy), rScaled, shapeType, travelAngle, previewColor, glowColor)

  # Trail dots to give motion feel
  for i in 1..3:
    let tx = cx - i.float32 * 9.0
    let ta = uint8(180 - i * 50)
    drawCircle(Vector2(x: tx, y: cy), r * (1.0 - i.float32 * 0.2),
               Color(r: 0, g: 180, b: 180, a: ta))

  # Name
  let shapeData = getBulletShapeData(shapeType)
  let nameSize: int32 = if isHovered: 17 else: 16
  let nameWidth = measureText(shapeData.name, nameSize)
  drawText(shapeData.name, (x + (SKIN_BOX_WIDTH - nameWidth) div 2).int32, (y + 80).int32, nameSize, White)

  # Description (wrapped, 2 lines max, auto-sized)
  let desc = shapeData.description
  let maxDescWidth = SKIN_BOX_WIDTH - 10
  let wrapped = wrapDescAutoSize(desc, maxDescWidth.int32)
  let descFont = wrapped.fontSize
  let d1w = measureText(wrapped.line1, descFont)
  drawText(wrapped.line1, (x + (SKIN_BOX_WIDTH - d1w) div 2).int32, (y + 100).int32, descFont, Gray)
  if wrapped.line2.len > 0:
    let d2w = measureText(wrapped.line2, descFont)
    drawText(wrapped.line2, (x + (SKIN_BOX_WIDTH - d2w) div 2).int32, (y + 112).int32, descFont, Gray)
  if wrapped.line3.len > 0:
    let d3w = measureText(wrapped.line3, descFont)
    drawText(wrapped.line3, (x + (SKIN_BOX_WIDTH - d3w) div 2).int32, (y + 124).int32, descFont, Gray)

  drawCosmeticCardStatus(x, y, isSelected, isUnlocked, canBuy, cost, costText)

proc drawShapePreview*(x, y: int, shapeType: ShapeType, time: float32, isSelected: bool, isHovered: bool, isUnlocked: bool = true, canBuy: bool = false, cost: CosmeticCost, costText: string = "") =
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

  let borderThickness = if isHovered or isSelected: 3.0'f32 else: 2.0'f32
  drawRectangleLines(Rectangle(x: x.float32, y: y.float32,
                                width: SKIN_BOX_WIDTH.float32, height: SKIN_BOX_HEIGHT.float32),
                    borderThickness, borderColor)

  # Draw mini player shape
  let centerX = (x + SKIN_BOX_WIDTH div 2).float32
  let centerY = (y + 50).float32
  let shapeRadius = 15.0
  # Only rotate for hexagon shape
  let hoverScale = if isHovered: 1.06'f32 else: 1.0'f32
  let rotation = if shapeType == shHexagon: time * 0.5 else: 0.0
  let pulse = sin(time * 2.0) * 0.5 + 0.5
  let shapeRadiusScaled = shapeRadius * hoverScale

  let baseColor = Color(r: 0, g: 200, b: 200, a: 255)
  let secondaryColor = Color(r: 0, g: 150, b: 200, a: 255)
  let coreColor = Color(r: 255, g: 255, b: 255, a: 255)
  let glowIntensity = 0.4 + pulse * 0.2

  # Draw shape using the same rendering as in-game
  drawPlayerShape(newVector2f(centerX, centerY), shapeRadiusScaled, shapeType,
                 baseColor, secondaryColor, coreColor, time, rotation, pulse, glowIntensity)

  # Shape name
  let shapeData = getShapeData(shapeType)
  let nameSize: int32 = if isHovered: 17 else: 16
  let nameWidth = measureText(shapeData.name, nameSize)
  let nameX = x + (SKIN_BOX_WIDTH - nameWidth) div 2
  drawText(shapeData.name, nameX.int32, (y + 80).int32, nameSize, White)

  # Shape description (2 lines max, auto-sized)
  let desc = shapeData.description
  let maxDescWidth = SKIN_BOX_WIDTH - 10
  let wrapped = wrapDescAutoSize(desc, maxDescWidth.int32)
  let descFont = wrapped.fontSize
  let desc1Width = measureText(wrapped.line1, descFont)
  let desc1X = x + (SKIN_BOX_WIDTH - desc1Width) div 2
  drawText(wrapped.line1, desc1X.int32, (y + 100).int32, descFont, Gray)
  if wrapped.line2.len > 0:
    let desc2Width = measureText(wrapped.line2, descFont)
    let desc2X = x + (SKIN_BOX_WIDTH - desc2Width) div 2
    drawText(wrapped.line2, desc2X.int32, (y + 112).int32, descFont, Gray)
  if wrapped.line3.len > 0:
    let desc3Width = measureText(wrapped.line3, descFont)
    let desc3X = x + (SKIN_BOX_WIDTH - desc3Width) div 2
    drawText(wrapped.line3, desc3X.int32, (y + 124).int32, descFont, Gray)

  drawCosmeticCardStatus(x, y, isSelected, isUnlocked, canBuy, cost, costText)

proc drawParticlePreview*(x, y: int, particleType: ParticleSkinType, time: float32, isSelected: bool, isHovered: bool, isUnlocked: bool = true, canBuy: bool = false, cost: CosmeticCost, costText: string = "") =
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
  let borderThickness = if isHovered or isSelected: 3.0'f32 else: 2.0'f32
  drawRectangleLines(Rectangle(x: x.float32, y: y.float32,
                                width: SKIN_BOX_WIDTH.float32, height: SKIN_BOX_HEIGHT.float32),
                    borderThickness, borderColor)

  # Draw particle effect preview
  let centerX = (x + SKIN_BOX_WIDTH div 2).float32
  let centerY = (y + 50).float32

  # Draw small bursts of particles radiating outward
  let particleData = getParticleSkinData(particleType)
  let particleCount = min(8, particleData.particleCount)
  let hoverScale = if isHovered: 1.06'f32 else: 1.0'f32

  for i in 0..<particleCount:
    let angle = (i.float32 / particleCount.float32) * PI * 2.0 + time * 2.0
    let distance = (20.0 + sin(time * 3.0 + i.float32) * 5.0) * hoverScale
    let px = centerX + cos(angle) * distance
    let py = centerY + sin(angle) * distance

    let useSecondary = (i mod 3) == 0
    let color = if useSecondary: secondaryColor else: primaryColor
    let particleSize = (3.0 + sin(time * 4.0 + i.float32) * 1.5) * hoverScale

    drawCircle(Vector2(x: px, y: py), particleSize, color)

  # Particle name
  let particleDataInfo = getParticleSkinData(particleType)
  let nameWidth = measureText(particleDataInfo.name, 16)
  let nameX = x + (SKIN_BOX_WIDTH - nameWidth) div 2
  drawText(particleDataInfo.name, nameX.int32, (y + 80).int32, 16, White)

  # Particle description (2 lines max, auto-sized)
  let desc = particleDataInfo.description
  let maxDescWidth = SKIN_BOX_WIDTH - 10
  let wrapped = wrapDescAutoSize(desc, maxDescWidth.int32)
  let descFont = wrapped.fontSize
  let desc1Width = measureText(wrapped.line1, descFont)
  let desc1X = x + (SKIN_BOX_WIDTH - desc1Width) div 2
  drawText(wrapped.line1, desc1X.int32, (y + 100).int32, descFont, Gray)
  if wrapped.line2.len > 0:
    let desc2Width = measureText(wrapped.line2, descFont)
    let desc2X = x + (SKIN_BOX_WIDTH - desc2Width) div 2
    drawText(wrapped.line2, desc2X.int32, (y + 112).int32, descFont, Gray)
  if wrapped.line3.len > 0:
    let desc3Width = measureText(wrapped.line3, descFont)
    let desc3X = x + (SKIN_BOX_WIDTH - desc3Width) div 2
    drawText(wrapped.line3, desc3X.int32, (y + 124).int32, descFont, Gray)

  drawCosmeticCardStatus(x, y, isSelected, isUnlocked, canBuy, cost, costText)

type PreviewClip = tuple[x, y, w, h: int32, hadParent: bool]

proc beginPreviewClip(x, y, w, h: int32): PreviewClip =
  ## Clip a live preview to its own rect intersected with the enclosing scissor
  ## (the scrolled grid viewport). raylib scissors don't nest, so naively opening
  ## a scissor here would replace the grid clip and let a partially-scrolled
  ## card's animated FX/cube bleed past the grid and thus past the bottom of
  ## the shop window. Returns what endPreviewClip needs to restore the parent.
  if currentVirtualScissorIsActive():
    let p = getCurrentVirtualScissor()
    let ix = max(x, p.x)
    let iy = max(y, p.y)
    let iw = max(0'i32, min(x + w, p.x + p.w) - ix)
    let ih = max(0'i32, min(y + h, p.y + p.h) - iy)
    beginVirtualScissorMode(ix, iy, iw, ih)
    result = (p.x, p.y, p.w, p.h, true)
  else:
    beginVirtualScissorMode(x, y, w, h)
    result = (x, y, w, h, false)

proc endPreviewClip(clip: PreviewClip) =
  ## Put the enclosing grid scissor back (instead of disabling scissoring), so
  ## the card chrome and the cards drawn after this one stay clipped to the grid.
  if clip.hadParent:
    beginVirtualScissorMode(clip.x, clip.y, clip.w, clip.h)
  else:
    endScissorMode()

proc drawDesktopBgPreview*(x, y: int, bgType: DesktopBgType, time: float32,
                            isSelected: bool, isHovered: bool,
                            isUnlocked: bool = true, canBuy: bool = false,
                            cost: CosmeticCost, costText: string = "") =
  ## Draw a card preview for a desktop background skin
  let bgData = getDesktopBgData(bgType)

  let cardBg = if isSelected: Color(r: 0, g: 60, b: 80, a: 255)
               elif isHovered: Color(r: 60, g: 60, b: 70, a: 255)
               else: Color(r: 40, g: 40, b: 50, a: 255)
  drawRectangle(x.int32, y.int32, SKIN_BOX_WIDTH.int32, SKIN_BOX_HEIGHT.int32, cardBg)

  # Mini background preview area (top portion of card), rendered using the
  # same backdrop helper and colours that the real desktop uses so the shop
  # card is a faithful thumbnail of the actual background.
  let previewH = 64
  let clip = beginPreviewClip(x.int32, y.int32, SKIN_BOX_WIDTH.int32, previewH.int32)

  if bgType == dbgDefault:
    # For the default skin draw the exact hardcoded wallpaper (including
    # the equipped cube). Use the running desktop's time/rotation when
    # available so the thumbnail matches the real desktop exactly.
    pushMatrix()
    translatef(x.float32, y.float32, 0.0'f32)
    if not activeDesktop.isNil:
      drawDesktopWallpaper(SKIN_BOX_WIDTH, previewH, activeDesktop.time,
                           activeDesktop.cubeRotX, activeDesktop.cubeRotY, activeDesktop.cubeRotZ)
    else:
      drawDesktopWallpaper(SKIN_BOX_WIDTH, previewH, time,
                           0.0'f32, 0.0'f32, 0.0'f32)
    popMatrix()
  else:
    # All other skins: fill with bgColor then overlay drawSharedBackdrop using
    # the skin palette, and draw a miniature wallpaper cube so the preview
    # matches the full desktop rendering for that theme.
    drawRectangle(x.int32, y.int32, SKIN_BOX_WIDTH.int32, previewH.int32, bgData.bgColor)
    let topColor    = bgData.bgColor
    let bottomColor = Color(r: uint8(clamp(topColor.r.int - 12, 0, 255)),
                            g: uint8(clamp(topColor.g.int - 12, 0, 255)),
                            b: uint8(clamp(topColor.b.int - 12, 0, 255)), a: 255)
    let gridColor   = Color(r: uint8((bgData.primaryColor.r.int + bgData.accentColor.r.int) div 2),
                            g: uint8((bgData.primaryColor.g.int + bgData.accentColor.g.int) div 2),
                            b: uint8((bgData.primaryColor.b.int + bgData.accentColor.b.int) div 2),
                            a: 34)
    pushMatrix()
    # Translate so drawSharedBackdrop treats (x,y) as its origin
    translatef(x.float32, y.float32, 0.0'f32)
    drawSharedBackdrop(SKIN_BOX_WIDTH.int32, previewH.int32, time * 0.62,
                       topColor, bottomColor,
                       gridColor, bgData.accentColor, bgData.primaryColor,
                       0.9, 0.8)

    # Soft glows and orbital rings scaled to the preview size
    let w = SKIN_BOX_WIDTH.float32
    let h = previewH.float32
    let nodeColor = bgData.accentColor
    let accentColor = bgData.primaryColor
    drawSoftGlow(w * 0.64, h * 0.46, min(w, h) * 0.42,
                 withAlpha(accentColor, 70), 0.7)
    drawSoftGlow(w * 0.18, h * 0.18, min(w, h) * 0.28,
                 withAlpha(nodeColor, 56), 0.55)
    drawSoftGlow(w * 0.88, h * 0.82, min(w, h) * 0.30,
                 withAlpha(bgData.primaryColor, 46), 0.5)

    # Signature theme effects so the card shows the real background look
    drawDesktopBgThemeFx(bgType, SKIN_BOX_WIDTH.int32, previewH.int32, time)

    for i in 0..3:
      let ringRadius = min(w, h) * (0.18 + i.float32 * 0.055)
      let alpha = uint8(26 + i * 9)
      drawCircleLines(Vector2(x: w * 0.64, y: h * 0.46), ringRadius,
                      withAlpha(accentColor, alpha))

    # Draw the wallpaper cube using the currently equipped cube skin so the
    # preview matches the full desktop. Prefer the running desktop's time
    # and rotation when available for a 1:1 match.
    let currentCubeSkin = if not globalSettings.isNil: CubeSkinType(globalSettings.cubeSkin) else: cskDefault
    if not activeDesktop.isNil:
      drawZeroGravityWallpaperCube(w * 0.64, h * 0.46, min(w, h) * 0.042'f32,
                                   activeDesktop.time,
                                   activeDesktop.cubeRotX, activeDesktop.cubeRotY, activeDesktop.cubeRotZ,
                                   currentCubeSkin)
    else:
      drawZeroGravityWallpaperCube(w * 0.64, h * 0.46, min(w, h) * 0.042'f32,
                                   time, 0.0'f32, 0.0'f32, 0.0'f32, currentCubeSkin)

    popMatrix()

  endPreviewClip(clip)

  # Border
  let borderColor = if isSelected: Color(r: 255, g: 150, b: 50, a: 255)
                    elif isHovered: Color(r: 120, g: 120, b: 140, a: 255)
                    else: Color(r: 80, g: 80, b: 100, a: 255)
  let borderThickness = if isHovered or isSelected: 3.0'f32 else: 2.0'f32
  drawRectangleLines(
    Rectangle(x: x.float32, y: y.float32, width: SKIN_BOX_WIDTH.float32, height: SKIN_BOX_HEIGHT.float32),
    borderThickness, borderColor)

  # Name
  let nameSize: int32 = if isHovered: 17 else: 16
  let nameWidth = measureText(bgData.name, nameSize)
  drawText(bgData.name, (x + (SKIN_BOX_WIDTH - nameWidth) div 2).int32,
           (y + 70).int32, nameSize, White)

  # Description (wrapped 2 lines, auto-sized)
  let maxDescWidth = SKIN_BOX_WIDTH - 10
  let wrapped = wrapDescAutoSize(bgData.description, maxDescWidth.int32)
  let descFont = wrapped.fontSize
  let d1w = measureText(wrapped.line1, descFont)
  drawText(wrapped.line1, (x + (SKIN_BOX_WIDTH - d1w) div 2).int32,
           (y + 90).int32, descFont, Gray)
  if wrapped.line2.len > 0:
    let d2w = measureText(wrapped.line2, descFont)
    drawText(wrapped.line2, (x + (SKIN_BOX_WIDTH - d2w) div 2).int32,
             (y + 102).int32, descFont, Gray)
  if wrapped.line3.len > 0:
    let d3w = measureText(wrapped.line3, descFont)
    drawText(wrapped.line3, (x + (SKIN_BOX_WIDTH - d3w) div 2).int32,
             (y + 114).int32, descFont, Gray)

  drawCosmeticCardStatus(x, y, isSelected, isUnlocked, canBuy, cost, costText)

proc drawCubeSkinPreview*(x, y: int, skinType: CubeSkinType, time: float32,
                           isSelected: bool, isHovered: bool,
                           isUnlocked: bool = true, canBuy: bool = false,
                           cost: CosmeticCost, costText: string = "") =
  ## Draw a card preview for a cube skin using simple 2-D isometric-style cube
  let skinData = getCubeSkinData(skinType)

  let cardBg = if isSelected: Color(r: 0, g: 60, b: 80, a: 255)
               elif isHovered: Color(r: 60, g: 60, b: 70, a: 255)
               else: Color(r: 40, g: 40, b: 50, a: 255)
  drawRectangle(x.int32, y.int32, SKIN_BOX_WIDTH.int32, SKIN_BOX_HEIGHT.int32, cardBg)

  let borderColor = if isSelected: Color(r: 255, g: 150, b: 50, a: 255)
                    elif isHovered: Color(r: 120, g: 120, b: 140, a: 255)
                    else: Color(r: 80, g: 80, b: 100, a: 255)
  let borderThickness = if isHovered or isSelected: 3.0'f32 else: 2.0'f32
  drawRectangleLines(
    Rectangle(x: x.float32, y: y.float32, width: SKIN_BOX_WIDTH.float32, height: SKIN_BOX_HEIGHT.float32),
    borderThickness, borderColor)

  # Render every cube skin using the same 3-D wallpaper cube so the shop
  # preview always matches what the player sees on the desktop.
  let previewH = 64
  let clip = beginPreviewClip(x.int32, y.int32, SKIN_BOX_WIDTH.int32, previewH.int32)
  let centerX = (x + SKIN_BOX_WIDTH div 2).float32
  # Move cube up slightly and reduce base size so it fits within the card area
  let centerY = (y + 40).float32
  let hoverScale = if isHovered: 1.03'f32 else: 1.0'f32
  let cubeSize = 13.0'f32 * hoverScale
  # Use slowly-drifting angles so the cube rotates in the shop card
  let aX = time * 0.171'f32
  let aY = time * 0.133'f32
  let aZ = time * 0.095'f32
  drawZeroGravityWallpaperCube(centerX, centerY, cubeSize, time, aX, aY, aZ, skinType)
  endPreviewClip(clip)

  # Name
  let nameSize: int32 = if isHovered: 17 else: 16
  let nameWidth = measureText(skinData.name, nameSize)
  drawText(skinData.name, (x + (SKIN_BOX_WIDTH - nameWidth) div 2).int32,
           (y + 80).int32, nameSize, White)

  # Description (wrapped 2 lines, auto-sized)
  let maxDescWidth = SKIN_BOX_WIDTH - 10
  let wrapped = wrapDescAutoSize(skinData.description, maxDescWidth.int32)
  let descFont = wrapped.fontSize
  let d1w = measureText(wrapped.line1, descFont)
  drawText(wrapped.line1, (x + (SKIN_BOX_WIDTH - d1w) div 2).int32,
           (y + 100).int32, descFont, Gray)
  if wrapped.line2.len > 0:
    let d2w = measureText(wrapped.line2, descFont)
    drawText(wrapped.line2, (x + (SKIN_BOX_WIDTH - d2w) div 2).int32,
             (y + 112).int32, descFont, Gray)
  if wrapped.line3.len > 0:
    let d3w = measureText(wrapped.line3, descFont)
    drawText(wrapped.line3, (x + (SKIN_BOX_WIDTH - d3w) div 2).int32,
             (y + 124).int32, descFont, Gray)

  drawCosmeticCardStatus(x, y, isSelected, isUnlocked, canBuy, cost, costText)

# ---- Cosmetic Packs tab ----
# The Packs tab is a special (non-CosmeticKind) tab like the Secret tab: it
# early-returns in both update and draw and reuses hoveredSkin/scrollOffset.

proc packCount(): int = ord(high(CosmeticPackId)) + 1

proc packGridMetrics(contentX, contentY, contentWidth, contentHeight: int):
    tuple[columns, gridLeft, gridTop, gridHeight: int] =
  ## Shared layout so the update hit-test and the draw agree on card positions.
  let columns = max(1, contentWidth div (PACK_CARD_W + PACK_CARD_PAD))
  let gridLeft = contentX + (contentWidth - (columns * PACK_CARD_W + (columns - 1) * PACK_CARD_PAD)) div 2
  let gridTop = contentY + TAB_HEIGHT + PACK_HEADER_H
  let gridHeight = contentHeight - TAB_HEIGHT - PACK_HEADER_H
  (columns, gridLeft, gridTop, gridHeight)

proc packCardXY(gridLeft, gridTop, columns, index, scrollInt: int): tuple[x, y: int] =
  let col = index mod columns
  let row = index div columns
  (gridLeft + col * (PACK_CARD_W + PACK_CARD_PAD),
   gridTop + row * (PACK_CARD_H + PACK_CARD_PAD) - scrollInt)

proc packMemberColor(member: CosmeticPackMember, time: float32): Color =
  ## Representative swatch colour for a pack member.
  case member.kind
  of ckPlayerSkin: getSkinColors(SkinType(member.index), time).primary
  of ckBulletSkin: getBulletSkinColors(BulletSkinType(member.index), time).primary
  of ckParticle:   getParticleSkinColors(ParticleSkinType(member.index), time).primary
  else:            Color(r: 200, g: 200, b: 200, a: 255)

proc drawPackCard(shop: ShopWindow, x, y: int, id: CosmeticPackId) =
  let pack = allCosmeticPacks[id]
  let profile = shop.rogueliteProfile
  let owned = packIsOwned(profile, id)
  let ownedCount = packOwnedCount(profile, id)
  let total = packMemberCount(id)
  let isHovered = shop.hoveredSkin == ord(id)
  let accent = Color(r: pack.accent.r, g: pack.accent.g, b: pack.accent.b, a: 255)

  let bg = if owned: Color(r: 30, g: 44, b: 34, a: 255)
           elif isHovered: Color(r: 52, g: 52, b: 64, a: 255)
           else: Color(r: 38, g: 38, b: 48, a: 255)
  drawRectangle(x.int32, y.int32, PACK_CARD_W.int32, PACK_CARD_H.int32, bg)
  drawRectangle(x.int32, y.int32, 5, PACK_CARD_H.int32, accent)  # accent stripe

  let borderColor = if owned: Color(r: 90, g: 200, b: 120, a: 255)
                    elif isHovered: accent
                    else: Color(r: 80, g: 80, b: 100, a: 255)
  let borderThick = if isHovered or owned: 3.0'f32 else: 2.0'f32
  drawRectangleLines(Rectangle(x: x.float32, y: y.float32,
                               width: PACK_CARD_W.float32, height: PACK_CARD_H.float32),
                     borderThick, borderColor)

  # Title + subtitle
  drawText(t(pack.nameKey), (x + 14).int32, (y + 10).int32, 17, White)
  drawText(t("pack_includes"), (x + 14).int32, (y + 32).int32, 10, Color(r: 160, g: 160, b: 175, a: 255))

  # Member swatches, with an owned marker on any already-unlocked member
  let swY = y + 66
  let swR = 13.0'f32
  var swX = x + 26
  for m in pack.members:
    drawCircle(Vector2(x: swX.float32, y: swY.float32), swR + 2.0'f32, Color(r: 0, g: 0, b: 0, a: 120))
    drawCircle(Vector2(x: swX.float32, y: swY.float32), swR, packMemberColor(m, shop.animationTime))
    drawCircleLines(swX.int32, swY.int32, swR, Color(r: 255, g: 255, b: 255, a: 60))
    if cosmeticIsUnlocked(profile, m.kind, m.index):
      drawCircle(Vector2(x: (swX + 9).float32, y: (swY - 9).float32), 6.0'f32, Color(r: 40, g: 180, b: 90, a: 255))
      drawText("+", (swX + 6).int32, (swY - 16).int32, 12, White)
    swX += 42

  # -40% deal badge
  if not owned:
    let pct = int(round((1.0'f32 - PackDiscount) * 100.0'f32))
    let badge = "-" & $pct & "%"
    let bw = measureText(badge, 13).int + 12
    let bx = x + PACK_CARD_W - bw - 10
    drawRectangle(bx.int32, (y + 8).int32, bw.int32, 20, Color(r: 220, g: 60, b: 60, a: 255))
    drawText(badge, (bx + 6).int32, (y + 10).int32, 13, White)

  drawRectangle((x + 12).int32, (y + 94).int32, (PACK_CARD_W - 24).int32, 1, Color(r: 70, g: 70, b: 85, a: 255))

  if owned:
    let ot = t("pack_owned")
    let ow = measureText(ot, 15)
    drawText(ot, (x + (PACK_CARD_W - ow) div 2).int32, (y + 120).int32, 15, Color(r: 110, g: 220, b: 140, a: 255))
    return

  # Struck-through retail of the members being bought, then the discounted price.
  let retail = packUnownedRetail(profile, id)
  let price = packPrice(profile, id)
  let canAfford = canAffordPack(profile, id)

  let retailText = cosmeticCostLabel(retail)
  drawText(retailText, (x + 14).int32, (y + 104).int32, 11, Color(r: 150, g: 150, b: 160, a: 255))
  let rtw = measureText(retailText, 11)
  drawRectangle((x + 14).int32, (y + 110).int32, rtw, 1, Color(r: 190, g: 90, b: 90, a: 255))

  let priceText = cosmeticCostLabel(price)
  let priceColor = if canAfford: Color(r: 255, g: 215, b: 90, a: 255) else: Color(r: 200, g: 110, b: 110, a: 255)
  drawText(priceText, (x + 14).int32, (y + 122).int32, 15, priceColor)

  if ownedCount > 0:
    let note = $ownedCount & "/" & $total
    let nw = measureText(note, 11)
    drawText(note, (x + PACK_CARD_W - nw - 12).int32, (y + 126).int32, 11, Color(r: 160, g: 160, b: 175, a: 255))

proc drawPacksTabContent(shop: ShopWindow, contentX, contentY, contentWidth, contentHeight: int) =
  ## The PACKS tab: a scrollable grid of discounted theme-bundle cards.
  let headerY = contentY + TAB_HEIGHT
  drawText(t("shop_customize_packs"), (contentX + 10).int32, (headerY + 5).int32, 18, Gold)

  if not shop.rogueliteProfile.isNil:
    let balanceY = headerY + 15
    let balanceX = contentX + contentWidth - 238
    drawCurrencyIcon(balanceX.int32, balanceY.int32, 16, ciDataShards)
    drawText($shop.rogueliteProfile.dataShards, (balanceX + 12).int32, (balanceY - 6).int32, 12, Gold)
    drawCurrencyIcon((balanceX + 72).int32, balanceY.int32, 16, ciCore)
    drawText($shop.rogueliteProfile.cores, (balanceX + 84).int32, (balanceY - 6).int32, 12,
             Color(r: 255, g: 130, b: 80, a: 255))
  elif shop.statusTimer <= 0:
    drawText(t("roguelite_no_profile"), (contentX + contentWidth - 150).int32, (headerY + 12).int32, 12, Red)
  if shop.statusTimer > 0 and shop.statusMessage.len > 0:
    drawText(shop.statusMessage, (contentX + contentWidth - 180).int32, (headerY + 31).int32, 11,
             Color(r: 255, g: 210, b: 110, a: 255))

  let (columns, gridLeft, gridTop, gridHeight) = packGridMetrics(contentX, contentY, contentWidth, contentHeight)
  let scrollInt = int(round(shop.scrollOffset))
  let total = packCount()

  beginVirtualScissorMode(contentX.int32, gridTop.int32, contentWidth.int32, gridHeight.int32)
  for i in 0..<total:
    let (cx, cy) = packCardXY(gridLeft, gridTop, columns, i, scrollInt)
    if cy + PACK_CARD_H > gridTop - 10 and cy < gridTop + gridHeight + 10:
      drawPackCard(shop, cx, cy, CosmeticPackId(i))
  endScissorMode()

  if shop.maxScrollOffset > 0:
    let sbX = contentX + contentWidth - 15
    drawRectangle(sbX.int32, gridTop.int32, 10, gridHeight.int32, Color(r: 40, g: 40, b: 50, a: 255))
    let rows = (total + columns - 1) div columns
    let totalH = (rows * (PACK_CARD_H + PACK_CARD_PAD) + 10).float32
    let thumbH = max(30.0'f32, (gridHeight.float32 / totalH) * gridHeight.float32)
    let thumbY = gridTop.float32 + (shop.scrollOffset / shop.maxScrollOffset) * (gridHeight.float32 - thumbH)
    drawRectangle(sbX.int32, thumbY.int32, 10, thumbH.int32, Color(r: 255, g: 150, b: 50, a: 200))

proc updateShopWindow*(shop: ShopWindow, dt: float32, screenWidth, screenHeight: int, allWindows: openArray[OSWindow]): bool =
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

  let shouldClose = handleOSWindowInput(shop.window, screenWidth, screenHeight, allWindows)
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
  let tabWidth = contentWidth div SHOP_TAB_COUNT

  if not shop.window.dragging and mouseY >= tabY and mouseY < tabY + TAB_HEIGHT and isTopmost:
    if shop.window.handledClickThisFrame:
      if mouseX >= contentX and mouseX < contentX + tabWidth:
        shop.currentTab = stPlayerSkins
        shop.scrollOffset = 0.0
        shop.scrollVelocity = 0.0
      elif mouseX >= contentX + tabWidth and mouseX < contentX + tabWidth * 2:
        shop.currentTab = stBulletSkins
        shop.scrollOffset = 0.0
        shop.scrollVelocity = 0.0
      elif mouseX >= contentX + tabWidth * 2 and mouseX < contentX + tabWidth * 3:
        shop.currentTab = stShapes
        shop.scrollOffset = 0.0
        shop.scrollVelocity = 0.0
      elif mouseX >= contentX + tabWidth * 3 and mouseX < contentX + tabWidth * 4:
        shop.currentTab = stBulletShapes
        shop.scrollOffset = 0.0
        shop.scrollVelocity = 0.0
      elif mouseX >= contentX + tabWidth * 4 and mouseX < contentX + tabWidth * 5:
        shop.currentTab = stParticles
        shop.scrollOffset = 0.0
        shop.scrollVelocity = 0.0
      elif mouseX >= contentX + tabWidth * 5 and mouseX < contentX + tabWidth * 6:
        shop.currentTab = stDesktopBg
        shop.scrollOffset = 0.0
        shop.scrollVelocity = 0.0
      elif mouseX >= contentX + tabWidth * 6 and mouseX < contentX + tabWidth * 7:
        shop.currentTab = stCubeSkins
        shop.scrollOffset = 0.0
        shop.scrollVelocity = 0.0
      elif mouseX >= contentX + tabWidth * 7 and mouseX < contentX + tabWidth * 8:
        shop.currentTab = stSecret
        shop.scrollOffset = 0.0
        shop.scrollVelocity = 0.0
      elif mouseX >= contentX + tabWidth * 8 and mouseX < contentX + contentWidth:
        shop.currentTab = stPacks
        shop.scrollOffset = 0.0
        shop.scrollVelocity = 0.0

  # The SECRET tab is a short row of victory/achievement-unlocked toggles,
  # not a CosmeticKind grid, handle it here and skip the grid machinery.
  if shop.currentTab == stSecret:
    shop.hoveredSkin = -1
    for i in 0..<SECRET_ITEM_COUNT:
      let (cardX, cardY) = secretCardPos(contentX, contentY, contentWidth, i)
      if isTopmost and mouseX >= cardX and mouseX < cardX + SECRET_CARD_W and
         mouseY >= cardY and mouseY < cardY + SECRET_CARD_H:
        shop.hoveredSkin = i
    let clicked = isTopmost and not shop.window.dragging and
                  shop.window.handledClickThisFrame and shop.hoveredSkin >= 0
    # Enter toggles the hovered card, defaulting to the first for keyboard use.
    let toggleIndex =
      if clicked: shop.hoveredSkin
      elif isTopmost and isKeyPressed(Enter): max(0, shop.hoveredSkin)
      else: -1
    if toggleIndex >= 0 and not globalSettings.isNil:
      var toggledOn = false
      var toggled = false
      if toggleIndex == 0 and globalSettings.kernelTophatUnlocked:
        globalSettings.kernelTophatEquipped = not globalSettings.kernelTophatEquipped
        if globalSettings.kernelTophatEquipped:
          globalSettings.cheaterHatEquipped = false
        toggledOn = globalSettings.kernelTophatEquipped
        toggled = true
      elif toggleIndex == 1 and globalSettings.orbitalCubeUnlocked:
        globalSettings.orbitalCubeEquipped = not globalSettings.orbitalCubeEquipped
        toggledOn = globalSettings.orbitalCubeEquipped
        toggled = true
      elif toggleIndex == 2 and globalSettings.cheaterHatUnlocked:
        globalSettings.cheaterHatEquipped = not globalSettings.cheaterHatEquipped
        if globalSettings.cheaterHatEquipped:
          globalSettings.kernelTophatEquipped = false
        toggledOn = globalSettings.cheaterHatEquipped
        toggled = true
      if toggled:
        discard saveSettings(globalSettings)
        playSound(stMenuSelect)
        shop.statusMessage =
          if toggledOn: t("shop_equipped") else: t("secret_tophat_unequipped")
        shop.statusTimer = 1.2
    if isTopmost and isKeyPressed(Escape):
      shop.window.visible = false
      return true
    return false

  # The PACKS tab sells discounted theme bundles with its own card grid and
  # purchase flow, so handle it here and skip the CosmeticKind grid machinery.
  if shop.currentTab == stPacks:
    shop.hoveredSkin = -1
    let (columns, gridLeft, gridTop, gridHeight) = packGridMetrics(contentX, contentY, contentWidth, contentHeight)
    let total = packCount()
    let rows = (total + columns - 1) div columns
    let totalH = rows * (PACK_CARD_H + PACK_CARD_PAD) + 10
    shop.maxScrollOffset = max(0.0, totalH.float32 - gridHeight.float32)

    let inGrid = mouseX >= contentX and mouseX < contentX + contentWidth and
                 mouseY >= gridTop and mouseY < gridTop + gridHeight
    if inGrid and not shop.window.dragging and isTopmost:
      let wheel = getPointerWheelMove()
      if wheel != 0:
        shop.scrollVelocity += -wheel * 400.0'f32
    if abs(shop.scrollVelocity) > 0.001'f32:
      shop.scrollOffset += shop.scrollVelocity * dt
      if shop.scrollOffset < 0.0'f32:
        shop.scrollOffset = 0.0'f32
        shop.scrollVelocity = 0.0'f32
      elif shop.scrollOffset > shop.maxScrollOffset:
        shop.scrollOffset = shop.maxScrollOffset
        shop.scrollVelocity = 0.0'f32
      else:
        shop.scrollVelocity *= clamp(1.0'f32 - dt * 8.0'f32, 0.0'f32, 1.0'f32)
    let scrollInt = int(round(shop.scrollOffset))

    for i in 0..<total:
      let (cx, cy) = packCardXY(gridLeft, gridTop, columns, i, scrollInt)
      if cy + PACK_CARD_H > gridTop and cy < gridTop + gridHeight and isTopmost and
         mouseX >= cx and mouseX < cx + PACK_CARD_W and mouseY >= cy and mouseY < cy + PACK_CARD_H:
        shop.hoveredSkin = i

    let activate = isTopmost and not shop.window.dragging and shop.hoveredSkin >= 0 and
                   (shop.window.handledClickThisFrame or isKeyPressed(Enter))
    if activate:
      let id = CosmeticPackId(shop.hoveredSkin)
      if shop.rogueliteProfile.isNil:
        shop.statusMessage = t("roguelite_no_profile")
        shop.statusTimer = 1.6
      elif packIsOwned(shop.rogueliteProfile, id):
        shop.statusMessage = t("pack_owned")
        shop.statusTimer = 1.2
      elif purchasePack(shop.rogueliteProfile, id):
        playSound(stBuy)
        shop.statusMessage = t("roguelite_unlocked")
        shop.statusTimer = 1.6
      else:
        shop.statusMessage = t("roguelite_not_enough_shards")
        shop.statusTimer = 1.6

    if isTopmost and isKeyPressed(Escape):
      shop.window.visible = false
      return true
    return false

  # Calculate grid area
  let headerHeight = 50
  let headerY = contentY + TAB_HEIGHT
  let gridY = headerY + headerHeight
  let infoPanelHeight = 50
  let gridHeight = contentHeight - TAB_HEIGHT - headerHeight - infoPanelHeight

  # Build filtered list and layout
  let curKind = if shop.currentTab == stPlayerSkins: ckPlayerSkin
                elif shop.currentTab == stBulletSkins: ckBulletSkin
                elif shop.currentTab == stShapes: ckPlayerShape
                elif shop.currentTab == stBulletShapes: ckBulletShape
                elif shop.currentTab == stDesktopBg: ckDesktopBg
                elif shop.currentTab == stCubeSkins: ckCubeSkin
                else: ckParticle

  var visible = visibleCosmeticIndices(curKind, shop.searchQuery)
  let items = visible.len

  let cardTotalW = SKIN_BOX_WIDTH + SKIN_BOX_PADDING
  let columns = max(1, contentWidth div cardTotalW)
  let totalRows = if items == 0: 0 else: (items + columns - 1) div columns
  let totalContentHeight = totalRows * (SKIN_BOX_HEIGHT + SKIN_BOX_PADDING) + 10
  shop.maxScrollOffset = max(0.0, totalContentHeight.float32 - gridHeight.float32)
  # Simple search box hit area in header (top-center)
  let searchW = min(200, contentWidth - 120)
  let searchX = contentX + (contentWidth - searchW) div 2
  let searchY = headerY + 8
  let searchH = 28

  # Toggle search visibility with Ctrl+F (topmost only)
  let ctrlPressed = isKeyDown(LeftControl) or isKeyDown(RightControl)
  if isTopmost and ctrlPressed and isKeyPressed(F):
    shop.searchVisible = not shop.searchVisible
    if shop.searchVisible:
      shop.searchFocused = true
    else:
      shop.searchFocused = false

  # Click handling only when search is visible
  if shop.searchVisible and isTopmost and shop.window.handledClickThisFrame:
    if mouseX >= searchX and mouseX < searchX + searchW and mouseY >= searchY and mouseY < searchY + searchH:
      shop.searchFocused = true
    else:
      # clicking outside search closes focus (unless clicking inside grid)
      if not (mouseX >= contentX and mouseX < contentX + contentWidth and mouseY >= gridY and mouseY < gridY + gridHeight):
        shop.searchFocused = false

  # Handle text input when search is focused
  if shop.searchFocused and isTopmost:
    setTextInputActive(true, tikText)
    setTextInputPreview(shop.searchQuery)
    # Drained in a loop -- one poll per frame dropped everything raylib had
    # already queued behind the first character.
    var key = pollCharPressed()
    while key > 0:
      if key < 256:
        let ch = char(key)
        if ch >= ' ' and ch <= '~' and shop.searchQuery.len < 60:
          shop.searchQuery.add(ch)
      key = pollCharPressed()
    if pollBackspacePressed() and shop.searchQuery.len > 0:
      shop.searchQuery.setLen(shop.searchQuery.len - 1)
    if pollEnterPressed():
      shop.searchFocused = false

  # Check if mouse is in grid area for wheel and hover
  let inGridArea = mouseX >= contentX and mouseX < contentX + contentWidth and
                   mouseY >= gridY and mouseY < gridY + gridHeight

  # Handle wheel -> add to scroll velocity (inertial scrolling)
  if inGridArea and not shop.window.dragging and isTopmost:
    let wheelMove = getPointerWheelMove()
    if wheelMove != 0:
      shop.scrollVelocity += -wheelMove * 400.0'f32

  # Apply velocity to offset, clamp and damp
  if abs(shop.scrollVelocity) > 0.001'f32:
    shop.scrollOffset += shop.scrollVelocity * dt
    if shop.scrollOffset < 0.0'f32:
      shop.scrollOffset = 0.0'f32
      shop.scrollVelocity = 0.0'f32
    elif shop.scrollOffset > shop.maxScrollOffset:
      shop.scrollOffset = shop.maxScrollOffset
      shop.scrollVelocity = 0.0'f32
    else:
      let damping = clamp(1.0'f32 - dt * 8.0'f32, 0.0'f32, 1.0'f32)
      shop.scrollVelocity *= damping

  let scrollInt = int(round(shop.scrollOffset))

  # Keyboard navigation & focus (only when topmost and not typing)
  if isTopmost and not shop.searchFocused and items > 0 and not shop.window.dragging:
    if shop.focusIndex >= items: shop.focusIndex = items - 1
    if shop.focusIndex < 0: shop.focusIndex = 0
    if isKeyPressed(Left):
      shop.focusIndex = max(0, shop.focusIndex - 1)
    if isKeyPressed(Right):
      shop.focusIndex = min(items - 1, shop.focusIndex + 1)
    if isKeyPressed(Up):
      shop.focusIndex = max(0, shop.focusIndex - columns)
    if isKeyPressed(Down):
      shop.focusIndex = min(items - 1, shop.focusIndex + columns)
    if isKeyPressed(PageUp):
      shop.scrollOffset = max(0.0'f32, shop.scrollOffset - gridHeight.float32)
      shop.focusIndex = max(0, shop.focusIndex - columns * max(1, gridHeight div (SKIN_BOX_HEIGHT + SKIN_BOX_PADDING)))
    if isKeyPressed(PageDown):
      shop.scrollOffset = min(shop.maxScrollOffset, shop.scrollOffset + gridHeight.float32)
      shop.focusIndex = min(items - 1, shop.focusIndex + columns * max(1, gridHeight div (SKIN_BOX_HEIGHT + SKIN_BOX_PADDING)))
    if isKeyPressed(Enter):
      let actual = visible[shop.focusIndex]
      handleCosmeticClick(shop, curKind, actual)
    if isKeyPressed(Space):
      let actual = visible[shop.focusIndex]
      shop.previewOpen = true
      shop.previewKind = curKind
      shop.previewIndex = actual

  # Reset hover state, keyboard focus will set hoveredSkin below
  shop.hoveredSkin = -1

  # Compute gridLeft
  let gridLeft = contentX + (contentWidth - (columns * SKIN_BOX_WIDTH + (columns - 1) * SKIN_BOX_PADDING)) div 2

  # If we have a focused index, reflect it as hovered (keyboard navigation)
  if items > 0:
    if shop.focusIndex < 0: shop.focusIndex = 0
    if shop.focusIndex >= items: shop.focusIndex = items - 1
    shop.hoveredSkin = visible[shop.focusIndex]

  # Handle mouse hover/click over visible items
  for vIndex in 0..<visible.len:
    let itemIndex = visible[vIndex]
    let col = vIndex mod columns
    let row = vIndex div columns
    let boxX = gridLeft + col * (SKIN_BOX_WIDTH + SKIN_BOX_PADDING)
    let boxY = gridY + 5 + row * (SKIN_BOX_HEIGHT + SKIN_BOX_PADDING) - scrollInt

    if boxY + SKIN_BOX_HEIGHT > gridY and boxY < gridY + gridHeight:
      if inGridArea and not shop.window.dragging and isTopmost:
        if mouseX >= boxX and mouseX < boxX + SKIN_BOX_WIDTH and
           mouseY >= boxY and mouseY < boxY + SKIN_BOX_HEIGHT:
          shop.hoveredSkin = itemIndex
          shop.focusIndex = vIndex
          if shop.window.handledClickThisFrame:
            handleCosmeticClick(shop, curKind, itemIndex)

  # Close preview modal if open via click outside or Escape
  if shop.previewOpen:
    let modalX = contentX + (contentWidth - PREVIEW_BOX_WIDTH) div 2
    let modalY = contentY + (contentHeight - PREVIEW_BOX_HEIGHT) div 2
    if isTopmost and shop.window.handledClickThisFrame:
      if not (mouseX >= modalX and mouseX < modalX + PREVIEW_BOX_WIDTH and mouseY >= modalY and mouseY < modalY + PREVIEW_BOX_HEIGHT):
        shop.previewOpen = false
    if isTopmost and isKeyPressed(Escape):
      shop.previewOpen = false
  elif isTopmost and isKeyPressed(Escape):
    # If search is focused, close search first; otherwise close the shop
    if shop.searchFocused:
      shop.searchFocused = false
    else:
      shop.window.visible = false
      return true

  return false

proc drawSecretCardChrome(cardX, cardY: int, unlocked, equipped, isHovered: bool) =
  ## Card background and border. Magenta accents set the secret stock apart
  ## from the regular tabs; equipped cards get the terminal-cyan border.
  let borderColor =
    if equipped: Color(r: 0, g: 230, b: 220, a: 255)
    elif isHovered and unlocked: Color(r: 255, g: 120, b: 230, a: 255)
    else: Color(r: 120, g: 60, b: 130, a: 255)
  drawRectangle(cardX.int32, cardY.int32, SECRET_CARD_W.int32, SECRET_CARD_H.int32,
                Color(r: 22, g: 18, b: 32, a: 255))
  drawRectangleLines(Rectangle(x: cardX.float32, y: cardY.float32,
                               width: SECRET_CARD_W.float32, height: SECRET_CARD_H.float32),
                     2.0'f32, borderColor)

proc drawSecretCardLabels(cardX, cardY: int, equipped: bool, name: string) =
  let nameW = measureText(name, 16)
  drawText(name, (cardX + (SECRET_CARD_W - nameW) div 2).int32, (cardY + 158).int32, 16, White)
  let statusText = if equipped: t("shop_equipped") else: t("secret_click_to_wear")
  let statusColor =
    if equipped: Color(r: 0, g: 230, b: 220, a: 255)
    else: Color(r: 200, g: 200, b: 210, a: 255)
  let statusW = measureText(statusText, 12)
  drawText(statusText, (cardX + (SECRET_CARD_W - statusW) div 2).int32,
           (cardY + 188).int32, 12, statusColor)

proc drawSecretCardLocked(cardX, cardY: int, hint: string) =
  drawLockGlyph((cardX + SECRET_CARD_W div 2 - 10).int32, (cardY + 56).int32,
                Color(r: 255, g: 120, b: 230, a: 255))
  let mystery = "???"
  let mysteryW = measureText(mystery, 24)
  drawText(mystery, (cardX + (SECRET_CARD_W - mysteryW) div 2).int32, (cardY + 110).int32, 24,
           Color(r: 170, g: 150, b: 185, a: 255))
  let hintLines = wrapTwoLines(hint, (SECRET_CARD_W - 20).int32, 12)
  let hint1W = measureText(hintLines.line1, 12)
  drawText(hintLines.line1, (cardX + (SECRET_CARD_W - hint1W) div 2).int32,
           (cardY + 172).int32, 12, Color(r: 150, g: 150, b: 165, a: 255))
  if hintLines.line2.len > 0:
    let hint2W = measureText(hintLines.line2, 12)
    drawText(hintLines.line2, (cardX + (SECRET_CARD_W - hint2W) div 2).int32,
             (cardY + 188).int32, 12, Color(r: 150, g: 150, b: 165, a: 255))

proc drawSecretTabContent(shop: ShopWindow, contentX, contentY, contentWidth, contentHeight: int) =
  ## The SECRET tab: one card per secret cosmetic. Card 0 is the kernel tophat
  ## (wave-60 victory); card 1 is the orbital cube (Escape Velocity advancement);
  ## card 2 is the cheater hat (cd+ menu advancement).
  ## Clicking an unlocked card toggles whether it is worn.
  let headerY = contentY + TAB_HEIGHT
  drawText(t("shop_customize_secret"), (contentX + 10).int32, (headerY + 5).int32, 18, Gold)
  if shop.statusTimer > 0 and shop.statusMessage.len > 0:
    drawText(shop.statusMessage, (contentX + contentWidth - 180).int32, (headerY + 31).int32, 11,
             Color(r: 255, g: 210, b: 110, a: 255))

  let hatUnlocked = not globalSettings.isNil and globalSettings.kernelTophatUnlocked
  let hatEquipped = hatUnlocked and globalSettings.kernelTophatEquipped
  let cubeUnlocked = not globalSettings.isNil and globalSettings.orbitalCubeUnlocked
  let cubeEquipped = cubeUnlocked and globalSettings.orbitalCubeEquipped
  let cheaterUnlocked = not globalSettings.isNil and globalSettings.cheaterHatUnlocked
  let cheaterEquipped = cheaterUnlocked and globalSettings.cheaterHatEquipped

  # Card 0: kernel tophat, previewed on the player's current skin and shape.
  let (hatX, hatY) = secretCardPos(contentX, contentY, contentWidth, 0)
  drawSecretCardChrome(hatX, hatY, hatUnlocked, hatEquipped, shop.hoveredSkin == 0)
  if hatUnlocked:
    let centerX = (hatX + SECRET_CARD_W div 2).float32
    let previewY = (hatY + 110).float32
    let (primary, secondary, core) = getSkinColors(shop.selectedPlayerSkin, shop.animationTime)
    let pulse = sin(shop.animationTime * 2.0'f32) * 0.5'f32 + 0.5'f32
    drawPlayerShape(newVector2f(centerX, previewY), 30.0'f32, shop.selectedShape,
                    primary, secondary, core, shop.animationTime,
                    shop.animationTime * 0.5'f32, pulse, 0.4'f32 + pulse * 0.2'f32)
    drawTopHat(newVector2f(centerX, previewY), 30.0'f32, shop.animationTime,
               1.0'f32, primary)
    drawSecretCardLabels(hatX, hatY, hatEquipped, t("secret_tophat_name"))
  else:
    drawSecretCardLocked(hatX, hatY, t("secret_locked_hint"))

  # Card 1: orbital cube, previewed as the player's shape with the mini
  # desktop cube (in the equipped cube skin's colors) circling it live.
  let (cubeX, cubeY) = secretCardPos(contentX, contentY, contentWidth, 1)
  drawSecretCardChrome(cubeX, cubeY, cubeUnlocked, cubeEquipped, shop.hoveredSkin == 1)
  if cubeUnlocked:
    let centerX = (cubeX + SECRET_CARD_W div 2).float32
    let previewY = (cubeY + 105).float32
    let (primary, secondary, core) = getSkinColors(shop.selectedPlayerSkin, shop.animationTime)
    let pulse = sin(shop.animationTime * 2.0'f32) * 0.5'f32 + 0.5'f32
    drawPlayerShape(newVector2f(centerX, previewY), 24.0'f32, shop.selectedShape,
                    primary, secondary, core, shop.animationTime,
                    shop.animationTime * 0.5'f32, pulse, 0.4'f32 + pulse * 0.2'f32)
    let cubeData = getCubeSkinData(shop.selectedCubeSkin)
    let orbitAngle = shop.animationTime * 1.3'f32
    let orbitDist = 24.0'f32 * 2.1'f32 + sin(shop.animationTime * 2.1'f32) * 3.0'f32
    let cubeHeart = if shop.selectedCubeSkin == cskCompanion: Color(r: 244, g: 116, b: 150, a: 255)
                    else: Color(r: 0, g: 0, b: 0, a: 0)
    drawMiniCube(Vector2(x: centerX + cos(orbitAngle) * orbitDist,
                         y: previewY + sin(orbitAngle) * orbitDist * 0.72'f32),
                 8.0'f32, shop.animationTime, cubeData.edgeColor, cubeData.glowColor, cubeHeart,
                 isD20 = shop.selectedCubeSkin == cskD20, skin = shop.selectedCubeSkin,
                 secretStyle = true)
    drawSecretCardLabels(cubeX, cubeY, cubeEquipped, t("secret_orbital_cube_name"))
  else:
    drawSecretCardLocked(cubeX, cubeY, t("secret_cube_locked_hint"))

  # Card 2: cheater hat, the shamefully pristine pointy hat.
  let (cheaterX, cheaterY) = secretCardPos(contentX, contentY, contentWidth, 2)
  drawSecretCardChrome(cheaterX, cheaterY, cheaterUnlocked, cheaterEquipped, shop.hoveredSkin == 2)
  if cheaterUnlocked:
    let centerX = (cheaterX + SECRET_CARD_W div 2).float32
    let previewY = (cheaterY + 110).float32
    let (primary, secondary, core) = getSkinColors(shop.selectedPlayerSkin, shop.animationTime)
    let pulse = sin(shop.animationTime * 2.0'f32) * 0.5'f32 + 0.5'f32
    drawPlayerShape(newVector2f(centerX, previewY), 30.0'f32, shop.selectedShape,
                    primary, secondary, core, shop.animationTime,
                    shop.animationTime * 0.5'f32, pulse, 0.4'f32 + pulse * 0.2'f32)
    drawCheaterHat(newVector2f(centerX, previewY), 30.0'f32, shop.animationTime)
    drawSecretCardLabels(cheaterX, cheaterY, cheaterEquipped, t("secret_cheater_hat_name"))
  else:
    drawSecretCardLocked(cheaterX, cheaterY, t("secret_unknown_locked_hint"))

  # Info panel mirrors the other tabs, describing the hovered card.
  let infoPanelHeight = 50
  let infoPanelY = contentY + contentHeight - infoPanelHeight
  drawRectangle(contentX.int32, infoPanelY.int32, contentWidth.int32, infoPanelHeight.int32,
                Color(r: 35, g: 35, b: 45, a: 255))
  let infoIsCube = shop.hoveredSkin == 1
  let infoIsCheater = shop.hoveredSkin == 2
  let infoUnlocked =
    if infoIsCheater: cheaterUnlocked
    elif infoIsCube: cubeUnlocked
    else: hatUnlocked
  if infoUnlocked:
    let infoEquipped =
      if infoIsCheater: cheaterEquipped
      elif infoIsCube: cubeEquipped
      else: hatEquipped
    let infoName =
      if infoIsCheater: t("secret_cheater_hat_name")
      elif infoIsCube: t("secret_orbital_cube_name")
      else: t("secret_tophat_name")
    let wornText = if infoEquipped: infoName else: "---"
    drawText(&"{t(\"shop_currently_equipped\")} {wornText}", (contentX + 10).int32,
             (infoPanelY + 8).int32, 15, White)
    let infoDesc =
      if infoIsCheater: t("secret_cheater_hat_desc")
      elif infoIsCube: t("secret_orbital_cube_desc")
      else: t("secret_tophat_desc")
    drawText(infoDesc, (contentX + 10).int32, (infoPanelY + 28).int32, 12, Gray)
  else:
    let lockedHint =
      if infoIsCheater: t("secret_unknown_locked_hint")
      elif infoIsCube: t("secret_cube_locked_hint")
      else: t("secret_locked_hint")
    drawText(lockedHint, (contentX + 10).int32, (infoPanelY + 18).int32, 13, Gray)

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
  let tabWidth = contentWidth div SHOP_TAB_COUNT
  let tabY = contentY

  # Player Skins tab
  let tab1Active = shop.currentTab == stPlayerSkins
  let tab1Color = if tab1Active: Color(r: 40, g: 40, b: 50, a: 255) else: Color(r: 30, g: 30, b: 40, a: 255)
  drawRectangle(contentX.int32, tabY.int32, tabWidth.int32, TAB_HEIGHT.int32, tab1Color)
  if tab1Active:
    drawRectangle(contentX.int32, (tabY + TAB_HEIGHT - 3).int32, tabWidth.int32, 3, Color(r: 255, g: 150, b: 50, a: 255))
  let tab1Label = t("shop_tab_player")
  let tab1LabelX = contentX + (tabWidth - measureText(tab1Label, 12)) div 2
  drawText(tab1Label, tab1LabelX.int32, (tabY + 13).int32, 12, if tab1Active: White else: Gray)

  # Bullet Skins tab
  let tab2Active = shop.currentTab == stBulletSkins
  let tab2Color = if tab2Active: Color(r: 40, g: 40, b: 50, a: 255) else: Color(r: 30, g: 30, b: 40, a: 255)
  drawRectangle((contentX + tabWidth).int32, tabY.int32, tabWidth.int32, TAB_HEIGHT.int32, tab2Color)
  if tab2Active:
    drawRectangle((contentX + tabWidth).int32, (tabY + TAB_HEIGHT - 3).int32, tabWidth.int32, 3, Color(r: 255, g: 150, b: 50, a: 255))
  let tab2Label = t("shop_tab_bullet")
  let tab2LabelX = contentX + tabWidth + (tabWidth - measureText(tab2Label, 12)) div 2
  drawText(tab2Label, tab2LabelX.int32, (tabY + 13).int32, 12, if tab2Active: White else: Gray)

  # Shapes tab
  let tab3Active = shop.currentTab == stShapes
  let tab3Color = if tab3Active: Color(r: 40, g: 40, b: 50, a: 255) else: Color(r: 30, g: 30, b: 40, a: 255)
  drawRectangle((contentX + tabWidth * 2).int32, tabY.int32, tabWidth.int32, TAB_HEIGHT.int32, tab3Color)
  if tab3Active:
    drawRectangle((contentX + tabWidth * 2).int32, (tabY + TAB_HEIGHT - 3).int32, tabWidth.int32, 3, Color(r: 255, g: 150, b: 50, a: 255))
  let tab3Label = t("shop_tab_shapes")
  let tab3LabelX = contentX + tabWidth * 2 + (tabWidth - measureText(tab3Label, 12)) div 2
  drawText(tab3Label, tab3LabelX.int32, (tabY + 13).int32, 12, if tab3Active: White else: Gray)

  # Bullet Shapes tab
  let tab4Active = shop.currentTab == stBulletShapes
  let tab4Color = if tab4Active: Color(r: 40, g: 40, b: 50, a: 255) else: Color(r: 30, g: 30, b: 40, a: 255)
  drawRectangle((contentX + tabWidth * 3).int32, tabY.int32, tabWidth.int32, TAB_HEIGHT.int32, tab4Color)
  if tab4Active:
    drawRectangle((contentX + tabWidth * 3).int32, (tabY + TAB_HEIGHT - 3).int32, tabWidth.int32, 3, Color(r: 255, g: 150, b: 50, a: 255))
  let tab4Label = t("shop_tab_bshapes")
  let tab4LabelX = contentX + tabWidth * 3 + (tabWidth - measureText(tab4Label, 12)) div 2
  drawText(tab4Label, tab4LabelX.int32, (tabY + 13).int32, 12, if tab4Active: White else: Gray)

  # Particles tab
  let tab5Active = shop.currentTab == stParticles
  let tab5Color = if tab5Active: Color(r: 40, g: 40, b: 50, a: 255) else: Color(r: 30, g: 30, b: 40, a: 255)
  drawRectangle((contentX + tabWidth * 4).int32, tabY.int32, tabWidth.int32, TAB_HEIGHT.int32, tab5Color)
  if tab5Active:
    drawRectangle((contentX + tabWidth * 4).int32, (tabY + TAB_HEIGHT - 3).int32, tabWidth.int32, 3, Color(r: 255, g: 150, b: 50, a: 255))
  let tab5Label = t("shop_tab_particles")
  let tab5LabelX = contentX + tabWidth * 4 + (tabWidth - measureText(tab5Label, 12)) div 2
  drawText(tab5Label, tab5LabelX.int32, (tabY + 13).int32, 12, if tab5Active: White else: Gray)

  # Desktop BG tab
  let tab6Active = shop.currentTab == stDesktopBg
  let tab6Color = if tab6Active: Color(r: 40, g: 40, b: 50, a: 255) else: Color(r: 30, g: 30, b: 40, a: 255)
  drawRectangle((contentX + tabWidth * 5).int32, tabY.int32, tabWidth.int32, TAB_HEIGHT.int32, tab6Color)
  if tab6Active:
    drawRectangle((contentX + tabWidth * 5).int32, (tabY + TAB_HEIGHT - 3).int32, tabWidth.int32, 3, Color(r: 255, g: 150, b: 50, a: 255))
  let tab6Label = t("shop_tab_desktop")
  let tab6LabelX = contentX + tabWidth * 5 + (tabWidth - measureText(tab6Label, 12)) div 2
  drawText(tab6Label, tab6LabelX.int32, (tabY + 13).int32, 12, if tab6Active: White else: Gray)

  # Cube Skins tab
  let tab7Active = shop.currentTab == stCubeSkins
  let tab7Color = if tab7Active: Color(r: 40, g: 40, b: 50, a: 255) else: Color(r: 30, g: 30, b: 40, a: 255)
  drawRectangle((contentX + tabWidth * 6).int32, tabY.int32, tabWidth.int32, TAB_HEIGHT.int32, tab7Color)
  if tab7Active:
    drawRectangle((contentX + tabWidth * 6).int32, (tabY + TAB_HEIGHT - 3).int32, tabWidth.int32, 3, Color(r: 255, g: 150, b: 50, a: 255))
  let tab7Label = t("shop_tab_cubeskins")
  let tab7LabelX = contentX + tabWidth * 6 + (tabWidth - measureText(tab7Label, 12)) div 2
  drawText(tab7Label, tab7LabelX.int32, (tabY + 13).int32, 12, if tab7Active: White else: Gray)

  # Secret items tab, magenta underline instead of the shop's orange
  let tab8Active = shop.currentTab == stSecret
  let tab8Color = if tab8Active: Color(r: 40, g: 40, b: 50, a: 255) else: Color(r: 30, g: 30, b: 40, a: 255)
  drawRectangle((contentX + tabWidth * 7).int32, tabY.int32, tabWidth.int32, TAB_HEIGHT.int32, tab8Color)
  if tab8Active:
    drawRectangle((contentX + tabWidth * 7).int32, (tabY + TAB_HEIGHT - 3).int32, tabWidth.int32, 3, Color(r: 255, g: 120, b: 230, a: 255))
  let tab8Label = t("shop_tab_secret")
  let tab8LabelX = contentX + tabWidth * 7 + (tabWidth - measureText(tab8Label, 12)) div 2
  drawText(tab8Label, tab8LabelX.int32, (tabY + 13).int32, 12, if tab8Active: White else: Gray)

  # Packs tab, green "deal" underline instead of the shop's orange
  let tab9Active = shop.currentTab == stPacks
  let tab9Color = if tab9Active: Color(r: 40, g: 40, b: 50, a: 255) else: Color(r: 30, g: 30, b: 40, a: 255)
  drawRectangle((contentX + tabWidth * 8).int32, tabY.int32, tabWidth.int32, TAB_HEIGHT.int32, tab9Color)
  if tab9Active:
    drawRectangle((contentX + tabWidth * 8).int32, (tabY + TAB_HEIGHT - 3).int32, tabWidth.int32, 3, Color(r: 90, g: 220, b: 120, a: 255))
  let tab9Label = t("shop_tab_packs")
  let tab9LabelX = contentX + tabWidth * 8 + (tabWidth - measureText(tab9Label, 12)) div 2
  drawText(tab9Label, tab9LabelX.int32, (tabY + 13).int32, 12, if tab9Active: White else: Gray)

  # The SECRET tab draws its own single-card layout instead of the grid.
  if shop.currentTab == stSecret:
    drawSecretTabContent(shop, contentX, contentY, contentWidth, contentHeight)
    return

  # The PACKS tab draws its own bundle-card grid instead of the CosmeticKind grid.
  if shop.currentTab == stPacks:
    drawPacksTabContent(shop, contentX, contentY, contentWidth, contentHeight)
    return

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
  elif shop.currentTab == stParticles:
    t("shop_customize_effects")
  elif shop.currentTab == stDesktopBg:
    t("shop_customize_desktop")
  elif shop.currentTab == stCubeSkins:
    t("shop_customize_cubeskins")
  else:
    t("shop_customize_effects")
  drawText(tabTitle, (contentX + 10).int32, (headerY + 5).int32, 18, Gold)
  if not shop.rogueliteProfile.isNil:
    let balanceY = headerY + 15
    let balanceX = contentX + contentWidth - 238
    drawCurrencyIcon(balanceX.int32, balanceY.int32, 16, ciDataShards)
    drawText($shop.rogueliteProfile.dataShards, (balanceX + 12).int32, (balanceY - 6).int32, 12, Gold)
    drawCurrencyIcon((balanceX + 72).int32, balanceY.int32, 16, ciCore)
    drawText($shop.rogueliteProfile.cores, (balanceX + 84).int32, (balanceY - 6).int32, 12,
             Color(r: 255, g: 130, b: 80, a: 255))
  elif shop.statusTimer <= 0:
    drawText(t("roguelite_no_profile"), (contentX + contentWidth - 150).int32, (headerY + 12).int32, 12, Red)
  if shop.statusTimer > 0 and shop.statusMessage.len > 0:
    drawText(shop.statusMessage, (contentX + contentWidth - 180).int32, (headerY + 31).int32, 11,
             Color(r: 255, g: 210, b: 110, a: 255))

  # Calculate grid area
  let gridY = headerY + headerHeight
  let infoPanelHeight = 50
  let gridHeight = contentHeight - TAB_HEIGHT - headerHeight - infoPanelHeight

  # Get skins for current tab and compute responsive grid
  let curKind = if shop.currentTab == stPlayerSkins: ckPlayerSkin
                elif shop.currentTab == stBulletSkins: ckBulletSkin
                elif shop.currentTab == stShapes: ckPlayerShape
                elif shop.currentTab == stBulletShapes: ckBulletShape
                elif shop.currentTab == stDesktopBg: ckDesktopBg
                elif shop.currentTab == stCubeSkins: ckCubeSkin
                else: ckParticle

  var visible = visibleCosmeticIndices(curKind, shop.searchQuery)
  let items = visible.len

  let cardTotalW = SKIN_BOX_WIDTH + SKIN_BOX_PADDING
  let columns = max(1, contentWidth div cardTotalW)
  let totalRows = if items == 0: 0 else: (items + columns - 1) div columns
  let totalContentHeight = totalRows * (SKIN_BOX_HEIGHT + SKIN_BOX_PADDING) + 10

  # Show scroll hint when content overflows
  if totalContentHeight.float32 > gridHeight.float32:
    drawText(t("shop_scroll_hint"), (contentX + 10).int32, (headerY + 30).int32, 12,
            Color(r: 255, g: 200, b: 100, a: 255))
  else:
    drawText(t("shop_click_equip"), (contentX + 10).int32, (headerY + 30).int32, 13, Gray)

  # Compute left offset and integer scroll
  let gridLeft = contentX + (contentWidth - (columns * SKIN_BOX_WIDTH + (columns - 1) * SKIN_BOX_PADDING)) div 2
  let scrollInt = int(round(shop.scrollOffset))
  shop.maxScrollOffset = max(0.0, totalContentHeight.float32 - gridHeight.float32)

  # Draw search box in header (top-center) only when visible
  let searchW = min(200, contentWidth - 120)
  let searchX = contentX + (contentWidth - searchW) div 2
  let searchY = headerY + 8
  let searchH = 28
  if shop.searchVisible:
    let searchBg = if shop.searchFocused: Color(r: 45, g: 45, b: 55, a: 255) else: Color(r: 35, g: 35, b: 45, a: 255)
    drawRectangle(searchX.int32, searchY.int32, searchW.int32, searchH.int32, searchBg)
    drawRectangleLines(Rectangle(x: searchX.float32, y: searchY.float32, width: searchW.float32, height: searchH.float32),
                       if shop.searchFocused: 2.0'f32 else: 1.0'f32, if shop.searchFocused: Color(r: 255, g: 150, b: 50, a: 255) else: Color(r: 60, g: 60, b: 70, a: 255))
    let searchLabel = if shop.searchQuery.len == 0: "Search..." else: shop.searchQuery
    drawText(searchLabel, (searchX + 8).int32, (searchY + 6).int32, 12, if shop.searchQuery.len == 0: Color(r: 120, g: 120, b: 130, a: 255) else: White)

  # Draw grid inside a single scissor region
  beginVirtualScissorMode(contentX.int32, gridY.int32, contentWidth.int32, gridHeight.int32)
  for vIndex in 0..<visible.len:
    let itemIndex = visible[vIndex]
    let col = vIndex mod columns
    let row = vIndex div columns
    let boxX = gridLeft + col * (SKIN_BOX_WIDTH + SKIN_BOX_PADDING)
    let boxY = gridY + 5 + row * (SKIN_BOX_HEIGHT + SKIN_BOX_PADDING) - scrollInt

    if boxY + SKIN_BOX_HEIGHT > gridY - 10 and boxY < gridY + gridHeight + 10:
      let isHovered = itemIndex == shop.hoveredSkin
      case shop.currentTab
      of stPlayerSkins:
        let skinType = SkinType(itemIndex)
        let isSelected = skinType == shop.selectedPlayerSkin
        let isUnlocked = cosmeticIsUnlocked(shop.rogueliteProfile, ckPlayerSkin, itemIndex)
        let canBuy = canAffordCosmetic(shop.rogueliteProfile, ckPlayerSkin, itemIndex)
        let cost = cosmeticCost(ckPlayerSkin, itemIndex)
        let costText = cosmeticCostLabel(cost)
        drawPlayerSkinPreview(boxX, boxY, skinType, shop.selectedShape, shop.animationTime, isSelected, isHovered, isUnlocked, canBuy, cost, costText)
      of stBulletSkins:
        let skinType = BulletSkinType(itemIndex)
        let isSelected = skinType == shop.selectedBulletSkin
        let isUnlocked = cosmeticIsUnlocked(shop.rogueliteProfile, ckBulletSkin, itemIndex)
        let canBuy = canAffordCosmetic(shop.rogueliteProfile, ckBulletSkin, itemIndex)
        let cost = cosmeticCost(ckBulletSkin, itemIndex)
        let costText = cosmeticCostLabel(cost)
        drawBulletSkinPreview(boxX, boxY, skinType, shop.animationTime, isSelected, isHovered, isUnlocked, canBuy, cost, costText)
      of stShapes:
        let shapeType = ShapeType(itemIndex)
        let isSelected = shapeType == shop.selectedShape
        let isUnlocked = cosmeticIsUnlocked(shop.rogueliteProfile, ckPlayerShape, itemIndex)
        let canBuy = canAffordCosmetic(shop.rogueliteProfile, ckPlayerShape, itemIndex)
        let cost = cosmeticCost(ckPlayerShape, itemIndex)
        let costText = cosmeticCostLabel(cost)
        drawShapePreview(boxX, boxY, shapeType, shop.animationTime, isSelected, isHovered, isUnlocked, canBuy, cost, costText)
      of stBulletShapes:
        let bshapeType = BulletShapeType(itemIndex)
        let isSelected = bshapeType == shop.selectedBulletShape
        let isUnlocked = cosmeticIsUnlocked(shop.rogueliteProfile, ckBulletShape, itemIndex)
        let canBuy = canAffordCosmetic(shop.rogueliteProfile, ckBulletShape, itemIndex)
        let cost = cosmeticCost(ckBulletShape, itemIndex)
        let costText = cosmeticCostLabel(cost)
        drawBulletShapePreview(boxX, boxY, bshapeType, shop.animationTime, isSelected, isHovered, isUnlocked, canBuy, cost, costText)
      of stParticles:
        let pType = ParticleSkinType(itemIndex)
        let isSelected = pType == shop.selectedParticle
        let isUnlocked = cosmeticIsUnlocked(shop.rogueliteProfile, ckParticle, itemIndex)
        let canBuy = canAffordCosmetic(shop.rogueliteProfile, ckParticle, itemIndex)
        let cost = cosmeticCost(ckParticle, itemIndex)
        let costText = cosmeticCostLabel(cost)
        drawParticlePreview(boxX, boxY, pType, shop.animationTime, isSelected, isHovered, isUnlocked, canBuy, cost, costText)
      of stDesktopBg:
        let bgType = DesktopBgType(itemIndex)
        let isSelected = bgType == shop.selectedDesktopBg
        let isUnlocked = cosmeticIsUnlocked(shop.rogueliteProfile, ckDesktopBg, itemIndex)
        let canBuy = canAffordCosmetic(shop.rogueliteProfile, ckDesktopBg, itemIndex)
        let cost = cosmeticCost(ckDesktopBg, itemIndex)
        let costText = cosmeticCostLabel(cost)
        drawDesktopBgPreview(boxX, boxY, bgType, shop.animationTime, isSelected, isHovered, isUnlocked, canBuy, cost, costText)
      of stCubeSkins:
        let cubeType = CubeSkinType(itemIndex)
        let isSelected = cubeType == shop.selectedCubeSkin
        let isUnlocked = cosmeticIsUnlocked(shop.rogueliteProfile, ckCubeSkin, itemIndex)
        let canBuy = canAffordCosmetic(shop.rogueliteProfile, ckCubeSkin, itemIndex)
        let cost = cosmeticCost(ckCubeSkin, itemIndex)
        let costText = cosmeticCostLabel(cost)
        drawCubeSkinPreview(boxX, boxY, cubeType, shop.animationTime, isSelected, isHovered, isUnlocked, canBuy, cost, costText)
      of stSecret:
        discard  # Handled by drawSecretTabContent (early return above)
      of stPacks:
        discard  # Handled by drawPacksTabContent (early return above)

    # Focus ring for keyboard navigation (drawn over card)
    if vIndex == shop.focusIndex:
      drawRectangleLines(Rectangle(x: boxX.float32, y: boxY.float32, width: SKIN_BOX_WIDTH.float32, height: SKIN_BOX_HEIGHT.float32), 2.0'f32, Color(r: 255, g: 200, b: 100, a: 180))
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
  elif shop.currentTab == stParticles:
    let selectedData = getParticleSkinData(shop.selectedParticle)
    drawText(&"{t(\"shop_currently_equipped\")} {selectedData.name}", (contentX + 10).int32, (infoPanelY + 8).int32, 15, White)
    drawText(selectedData.description, (contentX + 10).int32, (infoPanelY + 28).int32, 12, Gray)
  elif shop.currentTab == stDesktopBg:
    let selectedData = getDesktopBgData(shop.selectedDesktopBg)
    drawText(&"{t(\"shop_currently_equipped\")} {selectedData.name}", (contentX + 10).int32, (infoPanelY + 8).int32, 15, White)
    drawText(selectedData.description, (contentX + 10).int32, (infoPanelY + 28).int32, 12, Gray)
  elif shop.currentTab == stCubeSkins:
    let selectedData = getCubeSkinData(shop.selectedCubeSkin)
    drawText(&"{t(\"shop_currently_equipped\")} {selectedData.name}", (contentX + 10).int32, (infoPanelY + 8).int32, 15, White)
    drawText(selectedData.description, (contentX + 10).int32, (infoPanelY + 28).int32, 12, Gray)

  # Bottom-right hint for opening the search bar
  let hintText = "Press Ctrl+F to search"
  let hintW = measureText(hintText, 11)
  let hintX = contentX + contentWidth - int(hintW) - 10
  let hintY = contentY + contentHeight - 16
  drawText(hintText, hintX.int32, hintY.int32, 11, Color(r: 180, g: 180, b: 190, a: 200))
