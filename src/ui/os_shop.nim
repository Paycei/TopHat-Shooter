## OS-Style Shop System
## Shop screen redesigned as a modern OS storefront interface

import raylib, ../types, ../localization, math, ../powerup_data, ../sound, ../settings, ../run_statistics, icon_drawing, ../render_context

const
  SHOP_WIDTH = 950
  SHOP_HEIGHT = 600
  TITLE_BAR_HEIGHT = 45
  ITEM_HEIGHT = 60
  ITEM_SPACING = 6
  SIDEBAR_WIDTH: int32 = 280
  SHOP_COST_MULTIPLIER = 1.8'f32
  SHOP_DAMAGE_GAIN = 0.32'f32
  SHOP_DAMAGE_SCALE = 1.06'f32
  SHOP_FIRE_RATE_GAIN = 0.085'f32
  SHOP_FIRE_RATE_EXPONENT = 0.42'f32
  SHOP_FIRE_RATE_CAP = 0.09'f32
  SHOP_MOVE_SPEED_GAIN = 15.0'f32
  SHOP_HEALTH_GAIN_BASE = 6
  SHOP_BULLET_SPEED_GAIN = 14.0'f32
  SHOP_WALL_GAIN = 10

proc initShopItems*(): array[6, ShopItem] =
  result[0] = ShopItem(name: t(tkShopDamagePlus), description: t(tkShopDamagePlusDesc), baseCost: 13, bought: 0)
  result[1] = ShopItem(name: t(tkShopFireRatePlus), description: t(tkShopFireRatePlusDesc), baseCost: 13, bought: 0)
  result[2] = ShopItem(name: t(tkShopMoveSpeedPlus), description: t(tkShopMoveSpeedPlusDesc), baseCost: 10, bought: 0)
  result[3] = ShopItem(name: t(tkShopMaxHealthPlus), description: t(tkShopMaxHealthPlusDesc), baseCost: 14, bought: 0)
  result[4] = ShopItem(name: t(tkShopBulletSpeedPlus), description: t(tkShopBulletSpeedPlusDesc), baseCost: 9, bought: 0)
  result[5] = ShopItem(name: t(tkShopWallX4), description: t(tkShopWallX4Desc), baseCost: 18, bought: 0)

proc getCurrentCost*(item: ShopItem): int =
  result = (item.baseCost.float32 * pow(SHOP_COST_MULTIPLIER.float32, item.bought.float32)).int

proc shopDamageGain*(purchaseNumber: int): float32 =
  SHOP_DAMAGE_GAIN * pow(SHOP_DAMAGE_SCALE, max(0, purchaseNumber - 1).float32)

proc shopHealthGain*(purchaseNumber: int): int =
  SHOP_HEALTH_GAIN_BASE + purchaseNumber

proc applyShopPurchaseEffect*(game: Game, index: int, purchaseNumber: int, healHealth: bool = true) =
  case index
  of 0:
    game.player.damage += shopDamageGain(purchaseNumber)
  of 1:
    game.player.fireRate = applyFireRateDiminished(game.player.fireRate, SHOP_FIRE_RATE_GAIN, SHOP_FIRE_RATE_EXPONENT, SHOP_FIRE_RATE_CAP)
  of 2:
    game.player.speed += SHOP_MOVE_SPEED_GAIN
    game.player.baseSpeed += SHOP_MOVE_SPEED_GAIN
  of 3:
    let healthGain = shopHealthGain(purchaseNumber).float32
    game.player.maxHp += healthGain
    if healHealth:
      game.player.hp += healthGain
  of 4:
    game.player.bulletSpeed = addBulletSpeedDiminished(game.player.bulletSpeed, SHOP_BULLET_SPEED_GAIN)
  of 5:
    game.player.walls += SHOP_WALL_GAIN
  else:
    discard

proc drawModernShopButton(x, y, width, height: int32, text: string,
                         cost: int, canAfford: bool, isSelected: bool,
                         time: float32, itemIndex: int = 0,
                         description: string = "", boughtCount: int = 0) =
  ## Draw a modern styled shop item button
  # Button shadow
  if canAfford:
    drawRectangle(x + 3, y + 3, width, height,
                 Color(r: 0, g: 0, b: 0, a: 100))
  
  # Button background
  let bgColor = if not canAfford:
    Color(r: 35, g: 40, b: 50, a: 255)
  elif isSelected:
    Color(r: 0, g: 120, b: 200, a: 255)
  else:
    Color(r: 45, g: 55, b: 70, a: 255)
  
  drawRectangle(x, y, width, height, bgColor)
  
  # Top highlight
  if canAfford:
    drawRectangle(x, y, width, 2,
                 Color(r: 255, g: 255, b: 255, a: 30))
  
  # Border with pulse for selected
  let borderColor = if not canAfford:
    Color(r: 70, g: 80, b: 90, a: 255)
  elif isSelected:
    let pulse = sin(time * 5.0) * 0.3 + 0.7
    Color(r: 0, g: 200, b: 255, a: uint8(200 * pulse))
  else:
    Color(r: 100, g: 120, b: 140, a: 255)
  
  let borderWidth = if isSelected: 2.5 else: 2.0
  drawRectangleLines(Rectangle(x: x.float32, y: y.float32,
                                width: width.float32, height: height.float32),
                    borderWidth, borderColor)
  
  # Icon - drawn programmatically
  let iconColor = if canAfford:
    Color(r: 100, g: 200, b: 255, a: 255)
  else:
    Color(r: 80, g: 90, b: 100, a: 255)
  
  drawShopIcon(x + 8, y + int32(height div 2) - 14, 28, itemIndex, iconColor)
  
  # Text color
  let textColor = if not canAfford:
    Color(r: 100, g: 100, b: 110, a: 255)
  else:
    White
  
  let textX = x + 50
  drawText(text, textX, y + 8, 14, textColor)
  
  # Description (if provided)
  if description.len > 0:
    let descColor = if canAfford:
      Color(r: 160, g: 170, b: 180, a: 255)
    else:
      Color(r: 90, g: 95, b: 100, a: 255)
    drawText(description, textX, y + 24, 10, descColor)
  
  # Cost display and owned count on same line to save space
  let costText = $cost & " " & t(tkShopCredits)
  let costColor = if canAfford:
    Color(r: 255, g: 215, b: 0, a: 255)
  else:
    Color(r: 120, g: 120, b: 130, a: 255)
  
  drawCurrencyIcon(textX + 7, y + 48, 14, ciCredits,
                   if canAfford: 255'u8 else: 130'u8)
  let costTextX = textX + 18
  drawText(costText, costTextX, y + 42, 11, costColor)
  
  # Bought counter badge (top-right of button)
  if boughtCount > 0:
    let badgeText = t(tkShopBought) & ": " & $boughtCount
    let badgeW = measureText(badgeText, 10) + 10
    let badgeX = x + width - badgeW - 6
    let badgeY = y + 5
    let badgeBg = Color(r: 0, g: 80, b: 40, a: 220)
    let badgeBorder = Color(r: 0, g: 200, b: 100, a: 255)
    let badgeText2Color = Color(r: 120, g: 255, b: 160, a: 255)
    drawRectangle(badgeX, badgeY, badgeW, 16.int32, badgeBg)
    drawRectangleLines(Rectangle(x: badgeX.float32, y: badgeY.float32,
                                  width: badgeW.float32, height: 16.0), 1.0, badgeBorder)
    drawText(badgeText, badgeX + 5, badgeY + 3, 10, badgeText2Color)

proc drawShop*(game: Game) =
  let screenWidth = game.screenWidth
  let screenHeight = game.screenHeight
  
  # Animated scan lines effect
  for i in 0..<(screenHeight div 4):
    let lineY = i * 4 + int32(game.time * 80.0) mod 4
    let alpha = uint8(3 + sin(game.time * 2.0 + i.float32) * 3.0)
    drawRectangle(0, lineY, screenWidth, 2,
                 Color(r: 0, g: 100, b: 150, a: alpha))
  
  # Dark overlay
  drawRectangle(0, 0, screenWidth, screenHeight, Color(r: 0, g: 0, b: 0, a: 240))
  
  # Vignette effect
  let centerX = screenWidth div 2
  let centerY = screenHeight div 2
  for i in 0..20:
    let radius = i * 60
    let alpha = uint8(i * 2)
    drawRing(Vector2(x: centerX.float32, y: centerY.float32),
            radius.float32, (radius + 60).float32, 0, 360, 32,
            Color(r: 0, g: 0, b: 0, a: alpha))
  
  # Window position
  let windowX = (screenWidth - SHOP_WIDTH) div 2
  let windowY = (screenHeight - SHOP_HEIGHT) div 2
  
  # Window shadow
  for i in 1..4:
    let offset = i * 2
    let alpha = uint8(50 - i * 8)
    drawRectangle((windowX + offset).int32, (windowY + offset).int32,
                 SHOP_WIDTH, SHOP_HEIGHT,
                 Color(r: 0, g: 0, b: 0, a: alpha))
  
  # Window background
  drawRectangle(windowX, windowY, SHOP_WIDTH, SHOP_HEIGHT,
               Color(r: 26, g: 32, b: 44, a: 255))
  
  # Grid texture
  for i in 0..<(SHOP_HEIGHT div 40):
    let lineY = windowY + int32(i * 40)
    drawRectangle(windowX, lineY, SHOP_WIDTH, int32(1),
                 Color(r: 30, g: 36, b: 48, a: 255))
  
  # Window borders
  drawRectangleLines(Rectangle(x: windowX.float32, y: windowY.float32,
                                width: SHOP_WIDTH.float32, height: SHOP_HEIGHT.float32),
                    4, Color(r: 0, g: 180, b: 255, a: 255))
  drawRectangleLines(Rectangle(x: (windowX + 2).float32, y: (windowY + 2).float32,
                                width: (SHOP_WIDTH - 4).float32, height: (SHOP_HEIGHT - 4).float32),
                    1, Color(r: 60, g: 75, b: 95, a: 255))
  
  # Title bar
  drawRectangle(windowX, windowY, SHOP_WIDTH, TITLE_BAR_HEIGHT,
               Color(r: 40, g: 52, b: 70, a: 255))
  drawRectangle(windowX, windowY, SHOP_WIDTH, 2,
               Color(r: 80, g: 100, b: 130, a: 255))
  drawRectangle(windowX, windowY + TITLE_BAR_HEIGHT - 1, SHOP_WIDTH, 1,
               Color(r: 0, g: 140, b: 200, a: 255))
  
  # Title text
  let titleText = "[$] " & t(tkShopCreditStore)
  let titleColor = Color(r: 100, g: 200, b: 255, a: 255)
  drawText(titleText, windowX + 17, windowY + 13, 22, Color(r: 0, g: 0, b: 0, a: 120))
  drawText(titleText, windowX + 15, windowY + 11, 22, titleColor)
  
  # Close button
  let buttonSize = 28
  let closeButtonY = windowY + int32((TITLE_BAR_HEIGHT - buttonSize) div 2)
  let closeX = windowX + SHOP_WIDTH - int32(buttonSize) - 10
  drawRectangle(closeX, closeButtonY, int32(buttonSize), int32(buttonSize),
               Color(r: 220, g: 50, b: 50, a: 255))
  drawRectangleLines(Rectangle(x: closeX.float32, y: closeButtonY.float32,
                                width: buttonSize.float32, height: buttonSize.float32),
                    1, Color(r: 180, g: 30, b: 30, a: 255))
  drawText("X", closeX + 8, closeButtonY + 5, 18, White)
  
  # Sidebar for owned upgrades
  let sidebarX = windowX + 10
  let sidebarY = windowY + TITLE_BAR_HEIGHT + 10
  let sidebarHeight: int32 = SHOP_HEIGHT - TITLE_BAR_HEIGHT - 85  # Account for reduced bottom panel
  
  drawRectangle(sidebarX, sidebarY, SIDEBAR_WIDTH, sidebarHeight,
               Color(r: 30, g: 38, b: 52, a: 255))
  drawRectangleLines(Rectangle(x: sidebarX.float32, y: sidebarY.float32,
                                width: SIDEBAR_WIDTH.float32, height: sidebarHeight.float32),
                    1, Color(r: 0, g: 140, b: 200, a: 255))
  
  # Sidebar header
  drawRectangle(sidebarX, sidebarY, SIDEBAR_WIDTH, 35,
               Color(r: 40, g: 50, b: 65, a: 255))
  drawText("[L] " & t(tkShopActiveUpgrades), sidebarX + 10, sidebarY + 9, 16,
          Color(r: 150, g: 200, b: 255, a: 255))
  
  # Display owned permanent upgrades
  var upgradeY = sidebarY + 45
  let upgradeX = sidebarX + 12
  
  if game.player.powerUps.len == 0:
    drawText(t(tkShopNoPermanent), upgradeX, upgradeY, 13,
            Color(r: 150, g: 160, b: 170, a: 255))
    upgradeY += 18
    drawText(t(tkShopDefeatWaves), upgradeX, upgradeY, 12, LightGray)
  else:
    for powerUp in game.player.powerUps:
      if upgradeY > sidebarY + sidebarHeight - 60:
        drawText("...and more", upgradeX, upgradeY, 12, LightGray)
        break
      
      let name = getPowerUpName(powerUp.powerType)
      let levelText = "Lv." & $powerUp.level
      let rarityColor = if powerUp.rarity == prLegendary: Gold
                       else: Color(r: 200, g: 220, b: 255, a: 255)
      
      # Upgrade name with level
      drawText("> " & name, upgradeX, upgradeY, 14, rarityColor)
      let levelWidth = measureText(levelText, 11)
      drawText(levelText, upgradeX + SIDEBAR_WIDTH - levelWidth - 24, upgradeY + 2, 11,
              Color(r: 100, g: 200, b: 255, a: 255))
      upgradeY += 18
      
      # Description
      let desc = getPowerUpDescription(powerUp.powerType, powerUp.level, game.player.damage)
      drawText(desc, upgradeX + 8, upgradeY, 10, Color(r: 150, g: 160, b: 170, a: 255))
      upgradeY += 20
  
  # Shop items area
  let shopX = sidebarX + SIDEBAR_WIDTH + 15
  let shopY = sidebarY + 10
  let shopWidth = SHOP_WIDTH - SIDEBAR_WIDTH - 40
  
  drawText("v " & t(tkShopAvailablePurchases), shopX, shopY, 16,
          Color(r: 200, g: 220, b: 240, a: 255))
  
  let itemsStartY = shopY + 35
  
  # Mouse hover detection
  if globalSettings.mouseSupport and game.mouseMovedRecently and not game.keyboardUsedRecently:
    let mousePos = getVirtualMousePosition()
    
    for i in 0..5:
      let itemY = itemsStartY + i * (ITEM_HEIGHT + ITEM_SPACING)
      let itemRect = Rectangle(x: shopX.float32, y: itemY.float32,
                              width: shopWidth.float32, height: ITEM_HEIGHT.float32)
      
      if checkCollisionPointRec(mousePos, itemRect):
        game.selectedShopItem = i
  
  # Draw shop items with programmatic icons
  for i in 0..5:
    let itemY = itemsStartY + i * (ITEM_HEIGHT + ITEM_SPACING)
    let item = game.shopItems[i]
    let cost = getCurrentCost(item)
    let canAfford = game.player.coins >= cost
    let isSelected = i == game.selectedShopItem
    
    # Draw item button
    drawModernShopButton(shopX, itemY.int32, shopWidth, ITEM_HEIGHT,
                        item.name, cost, canAfford, isSelected,
                        game.time, i, item.description, item.bought)
  
  # Bottom panel with controls - reduced height
  let bottomY = windowY + SHOP_HEIGHT - 65
  drawRectangle(windowX, bottomY, SHOP_WIDTH, 65,
               Color(r: 30, g: 38, b: 52, a: 255))
  drawRectangle(windowX, bottomY, SHOP_WIDTH, 2,
               Color(r: 0, g: 140, b: 200, a: 255))
  
  # Control instructions with modern styling
  let ctrlY = bottomY + 10
  drawText(t(tkShopControls), windowX + 20, ctrlY, 13,
          Color(r: 0, g: 180, b: 255, a: 255))
  
  let instructY = ctrlY + 18
  drawText(t("os_shop_navigate") & t(tkShopNavigate), windowX + 20, instructY, 11, Color(r: 200, g: 210, b: 220, a: 255))
  
  drawText(t("os_shop_select") & t(tkShopBuy), windowX + 180, instructY, 11, Color(r: 200, g: 210, b: 220, a: 255))
  
  let exitHintText = if game.mode == gmRoguelite:
    t("os_shop_exit") & t("roguelite_back")
  else:
    t("os_shop_exit") & t(tkShopContinue)
  drawText(exitHintText, windowX + 300, instructY, 11, Color(r: 200, g: 210, b: 220, a: 255))
  
  # Purchase button for selected item (large, prominent)
  let selectedItem = game.shopItems[game.selectedShopItem]
  let selectedCost = getCurrentCost(selectedItem)
  let canBuy = game.player.coins >= selectedCost
  
  let buyButtonWidth: int32 = 220
  let buyButtonHeight: int32 = 38
  let buyButtonX: int32 = (windowX + SHOP_WIDTH - buyButtonWidth - 20).int32
  let buyButtonY: int32 = bottomY + 12
  
  # Calculate position for centered credits counter
  # Position it between the "ESC Continue" text (around x=300) and the buy button
  let escTextEndX = windowX + 380  # Moved left from 420 to 380
  let creditsBoxWidth: int32 = 180
  let creditsBoxHeight: int32 = 38
  # Center between ESC text and buy button
  let availableSpace = buyButtonX - escTextEndX
  let creditsBoxX: int32 = escTextEndX + (availableSpace - creditsBoxWidth) div 2
  let creditsBoxY: int32 = buyButtonY
  
  # Credits box background with shadow
  drawRectangle(creditsBoxX + 2, creditsBoxY + 2, creditsBoxWidth, creditsBoxHeight,
               Color(r: 0, g: 0, b: 0, a: 100))
  
  # Credits box background
  drawRectangle(creditsBoxX, creditsBoxY, creditsBoxWidth, creditsBoxHeight,
               Color(r: 40, g: 50, b: 30, a: 255))
  
  # Top highlight
  drawRectangle(creditsBoxX, creditsBoxY, creditsBoxWidth, 2,
               Color(r: 255, g: 220, b: 0, a: 60))
  
  # Border
  drawRectangleLines(Rectangle(x: creditsBoxX.float32, y: creditsBoxY.float32,
                                width: creditsBoxWidth.float32, height: creditsBoxHeight.float32),
                    2, Color(r: 255, g: 215, b: 0, a: 200))
  
  # Coin icon
  let coinIconX = creditsBoxX + 15
  let coinIconY = creditsBoxY + creditsBoxHeight div 2
  drawCurrencyIcon(coinIconX, coinIconY, 26, ciCredits)
  
  # Credits amount text
  let creditsText = $game.player.coins & " " & t(tkShopCredits)
  drawText(creditsText, creditsBoxX + 40, creditsBoxY + 7, 18,
          Color(r: 0, g: 0, b: 0, a: 120))
  drawText(creditsText, creditsBoxX + 38, creditsBoxY + 5, 18,
          Color(r: 255, g: 240, b: 100, a: 255))
  
  # Small label below
  drawText(t("shop_available_balance"), creditsBoxX + 40, creditsBoxY + 24, 9,
          Color(r: 180, g: 180, b: 150, a: 255))
  
  # Button shadow
  if canBuy:
    drawRectangle(buyButtonX + 2, buyButtonY + 2, buyButtonWidth, buyButtonHeight,
                 Color(r: 0, g: 0, b: 0, a: 100))
  
  # Button background
  let buyBgColor = if canBuy:
    Color(r: 0, g: 140, b: 255, a: 255)
  else:
    Color(r: 55, g: 60, b: 70, a: 255)
  
  drawRectangle(buyButtonX, buyButtonY, buyButtonWidth, buyButtonHeight, buyBgColor)
  
  # Top highlight
  if canBuy:
    drawRectangle(buyButtonX, buyButtonY, buyButtonWidth, 2,
                 Color(r: 255, g: 255, b: 255, a: 40))
  
  # Border with pulse
  let buyBorderColor = if canBuy:
    let pulse = sin(game.time * 6.0) * 0.3 + 0.7
    Color(r: 0, g: 200, b: 255, a: uint8(220 * pulse))
  else:
    Color(r: 100, g: 110, b: 120, a: 255)
  
  drawRectangleLines(Rectangle(x: buyButtonX.float32, y: buyButtonY.float32,
                                width: buyButtonWidth.float32, height: buyButtonHeight.float32),
                    2.5, buyBorderColor)
  
  # Button text
  let buyText = if canBuy:
    "[$] " & t(tkShopBuySelected)
  else:
    "[!] " & t(tkShopInsufficientCredits)
  let buyTextWidth = measureText(buyText, 16)
  let buyTextX = buyButtonX + (buyButtonWidth - buyTextWidth) div 2
  
  drawText(buyText, buyTextX + 1, buyButtonY + 13, 16, Color(r: 0, g: 0, b: 0, a: 120))
  drawText(buyText, buyTextX, buyButtonY + 12, 16,
          if canBuy: White else: Color(r: 150, g: 155, b: 160, a: 255))
  
  # Draw custom cursor
  if globalSettings.mouseSupport or globalSettings.showCursorInMenus:
    let mousePos = getVirtualMousePosition()
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
    drawCircle(Vector2(x: mousePos.x, y: mousePos.y), 2, Gold)

proc buyShopItem*(game: Game, index: int) =
  if index < 0 or index > 5: return
  
  let item = addr game.shopItems[index]

  let cost = getCurrentCost(item[])
  if game.player.coins < cost:
    # Play error sound (using menu nav sound at lower volume)
    playSound(stMenuNav, 0.3)
    return
  
  # Play purchase sound (using coin pickup)
  playSound(stCoinPickup, 0.8)
  
  game.player.coins -= cost
  item.bought += 1
  
  # Track shop purchase for statistics
  trackShopPurchase(game, item.name, cost)
  applyShopPurchaseEffect(game, index, item.bought)
