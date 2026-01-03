## OS-Style Shop System - Enhanced Edition
## Shop screen redesigned as a modern OS storefront interface
## Matches the new OS theme from power-up installer and game over screens

import raylib, types, math, powerup, sound, settings, run_statistics

const
  SHOP_WIDTH = 950
  SHOP_HEIGHT = 600
  TITLE_BAR_HEIGHT = 45
  ITEM_HEIGHT = 60
  ITEM_SPACING = 6
  SIDEBAR_WIDTH: int32 = 280

proc initShopItems*(): array[6, ShopItem] =
  result[0] = ShopItem(name: "Damage +", description: "Increase bullet damage", baseCost: 8, bought: 0)
  result[1] = ShopItem(name: "Fire Rate +", description: "Shoot faster", baseCost: 10, bought: 0)
  result[2] = ShopItem(name: "Move Speed +", description: "Move faster", baseCost: 7, bought: 0)
  result[3] = ShopItem(name: "Max Health +", description: "Increase max HP", baseCost: 10, bought: 0)
  result[4] = ShopItem(name: "Bullet Speed +", description: "Faster bullets", baseCost: 6, bought: 0)
  result[5] = ShopItem(name: "Wall (x5)", description: "Buy 5 deployable walls", baseCost: 14, bought: 0)

proc getCurrentCost*(item: ShopItem): int =
  # More aggressive exponential cost scaling: baseCost * 1.5^bought
  (item.baseCost.float32 * pow(1.45, item.bought.float32)).int

proc drawModernShopButton(x, y, width, height: int32, text: string, 
                         cost: int, canAfford: bool, isSelected: bool,
                         time: float32, icon: string = "📦", bought: int = 0, description: string = "") =
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
  
  # Icon - smaller for reduced item height
  drawText(icon, x + 8, y + int32(height div 2) - 12, 24,
          if canAfford: Color(r: 100, g: 200, b: 255, a: 255)
          else: Color(r: 80, g: 90, b: 100, a: 255))
  
  # Text color
  let textColor = if not canAfford: 
    Color(r: 100, g: 100, b: 110, a: 255)
  else: 
    White
  
  let textX = x + 45
  drawText(text, textX, y + 6, 15, textColor)
  
  # Description (if provided)
  if description.len > 0:
    let descColor = if canAfford:
      Color(r: 160, g: 170, b: 180, a: 255)
    else:
      Color(r: 90, g: 95, b: 100, a: 255)
    drawText(description, textX, y + 22, 10, descColor)
  
  # Cost display and owned count on same line to save space
  let costText = $cost & " CR"
  let costColor = if canAfford: 
    Color(r: 255, g: 215, b: 0, a: 255)
  else: 
    Color(r: 120, g: 120, b: 130, a: 255)
  
  drawText(costText, textX, y + 38, 11, costColor)
  
  # Purchase count on same line
  let countText = "Owned: " & $bought
  let costWidth = measureText(costText, 11)
  drawText(countText, textX + costWidth + 80, y + 38, 10,
          Color(r: 150, g: 160, b: 170, a: 255))

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
  let titleText = "💰 CREDIT STORE - UPGRADES AVAILABLE"
  let titleColor = Color(r: 100, g: 200, b: 255, a: 255)
  drawText(titleText, windowX + 17, windowY + 13, 22, Color(r: 0, g: 0, b: 0, a: 120))
  drawText(titleText, windowX + 15, windowY + 11, 22, titleColor)
  
  # Coin display in title bar
  let coinText = $game.player.coins & " CR"
  let coinWidth = measureText(coinText, 20)
  drawText(coinText, windowX + SHOP_WIDTH - coinWidth - 20, windowY + 12, 20, Gold)
  
  # Sidebar for owned upgrades - adjusted for new bottom panel height
  let sidebarX = windowX + 10
  let sidebarY = windowY + TITLE_BAR_HEIGHT + 10
  let sidebarHeight: int32 = SHOP_HEIGHT - TITLE_BAR_HEIGHT - 85  # Account for reduced bottom panel (65 + margins)
  
  drawRectangle(sidebarX, sidebarY, SIDEBAR_WIDTH, sidebarHeight,
               Color(r: 30, g: 38, b: 52, a: 255))
  drawRectangleLines(Rectangle(x: sidebarX.float32, y: sidebarY.float32,
                                width: SIDEBAR_WIDTH.float32, height: sidebarHeight.float32),
                    1, Color(r: 0, g: 140, b: 200, a: 255))
  
  # Sidebar header
  drawRectangle(sidebarX, sidebarY, SIDEBAR_WIDTH, 35,
               Color(r: 40, g: 50, b: 65, a: 255))
  drawText("📋 ACTIVE UPGRADES", sidebarX + 10, sidebarY + 9, 16,
          Color(r: 150, g: 200, b: 255, a: 255))
  
  # Display owned permanent upgrades
  var upgradeY = sidebarY + 45
  let upgradeX = sidebarX + 12
  
  if game.player.powerUps.len == 0:
    drawText("No permanent upgrades yet.", upgradeX, upgradeY, 13,
            Color(r: 150, g: 160, b: 170, a: 255))
    upgradeY += 18
    drawText("Defeat waves to unlock!", upgradeX, upgradeY, 12, LightGray)
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
      drawText("▸ " & name, upgradeX, upgradeY, 14, rarityColor)
      let levelWidth = measureText(levelText, 11)
      drawText(levelText, upgradeX + SIDEBAR_WIDTH - levelWidth - 24, upgradeY + 2, 11,
              Color(r: 100, g: 200, b: 255, a: 255))
      upgradeY += 18
      
      # Description
      let desc = getPowerUpDescription(powerUp.powerType, powerUp.level)
      drawText(desc, upgradeX + 8, upgradeY, 10, Color(r: 150, g: 160, b: 170, a: 255))
      upgradeY += 20
  
  # Shop items area
  let shopX = sidebarX + SIDEBAR_WIDTH + 15
  let shopY = sidebarY + 10
  let shopWidth = SHOP_WIDTH - SIDEBAR_WIDTH - 40
  
  drawText("▼ AVAILABLE PURCHASES:", shopX, shopY, 16,
          Color(r: 200, g: 220, b: 240, a: 255))
  
  let itemsStartY = shopY + 35
  
  # Mouse hover detection
  if globalSettings.mouseSupport and game.mouseMovedRecently and not game.keyboardUsedRecently:
    let mousePos = getMousePosition()
    
    for i in 0..5:
      let itemY = itemsStartY + i * (ITEM_HEIGHT + ITEM_SPACING)
      let itemRect = Rectangle(x: shopX.float32, y: itemY.float32,
                              width: shopWidth.float32, height: ITEM_HEIGHT.float32)
      
      if checkCollisionPointRec(mousePos, itemRect):
        game.selectedShopItem = i
  
  # Draw shop items
  let shopIcons = ["⚔", "⚡", "👟", "❤", "🚀", "🧱"]
  
  for i in 0..5:
    let itemY = itemsStartY + i * (ITEM_HEIGHT + ITEM_SPACING)
    let item = game.shopItems[i]
    let cost = getCurrentCost(item)
    let canAfford = game.player.coins >= cost
    let isSelected = i == game.selectedShopItem
    
    # Draw item button with description
    drawModernShopButton(shopX, itemY.int32, shopWidth, ITEM_HEIGHT,
                        item.name, cost, canAfford, isSelected,
                        game.time, shopIcons[i], item.bought, item.description)
  
  # Bottom panel with controls - reduced height
  let bottomY = windowY + SHOP_HEIGHT - 65
  drawRectangle(windowX, bottomY, SHOP_WIDTH, 65,
               Color(r: 30, g: 38, b: 52, a: 255))
  drawRectangle(windowX, bottomY, SHOP_WIDTH, 2,
               Color(r: 0, g: 140, b: 200, a: 255))
  
  # Control instructions with modern styling
  let ctrlY = bottomY + 10
  drawText("CONTROLS:", windowX + 20, ctrlY, 13,
          Color(r: 0, g: 180, b: 255, a: 255))
  
  let instructY = ctrlY + 18
  drawText("↑↓/W/S Navigate", windowX + 20, instructY, 11, Color(r: 200, g: 210, b: 220, a: 255))
  
  drawText("ENTER/CLICK Buy", windowX + 160, instructY, 11, Color(r: 200, g: 210, b: 220, a: 255))
  
  drawText("ESC Continue", windowX + 300, instructY, 11, Color(r: 200, g: 210, b: 220, a: 255))
  
  # Purchase button for selected item (large, prominent)
  let selectedItem = game.shopItems[game.selectedShopItem]
  let selectedCost = getCurrentCost(selectedItem)
  let canBuy = game.player.coins >= selectedCost
  
  let buyButtonWidth: int32 = 220
  let buyButtonHeight: int32 = 38
  let buyButtonX: int32 = (windowX + SHOP_WIDTH - buyButtonWidth - 20).int32
  let buyButtonY: int32 = bottomY + 12
  
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
  let buyText = if canBuy: "💳 BUY SELECTED" else: "⚠ INSUFFICIENT CREDITS"
  let buyTextWidth = measureText(buyText, 16)
  let buyTextX = buyButtonX + (buyButtonWidth - buyTextWidth) div 2
  
  drawText(buyText, buyTextX + 1, buyButtonY + 13, 16, Color(r: 0, g: 0, b: 0, a: 120))
  drawText(buyText, buyTextX, buyButtonY + 12, 16,
          if canBuy: White else: Color(r: 150, g: 155, b: 160, a: 255))
  
  # Draw custom cursor
  if globalSettings.mouseSupport or globalSettings.showCursorInMenus:
    let mousePos = getMousePosition()
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
  
  case index
  of 0: # Damage - Slightly reduced exponential scaling
    game.player.damage += 0.25 * pow(1.0375, item.bought.float32)
  of 1: # Fire Rate - Diminishing returns with reduced initial benefit
    let currentRate = game.player.fireRate
    let scalingFactor = 0.025
    let diminishingFactor = pow(currentRate / 0.415, 0.6)
    let effectiveReduction = currentRate * scalingFactor * diminishingFactor
    
    game.player.fireRate -= effectiveReduction
    if game.player.fireRate < 0.07: game.player.fireRate = 0.07  # Hard cap
  of 2: # Move Speed
    game.player.speed += 12
    game.player.baseSpeed += 12
  of 3: # Max Health - Scales with purchases: 3, 4, 5, 6, 7 HP (capped at +7)
    let healthGain = min(3 + game.shopItems[3].bought, 7)
    game.player.maxHp += healthGain.float32
    game.player.hp += healthGain.float32
  of 4: # Bullet Speed
    game.player.bulletSpeed += 10
  of 5: # Walls
    game.player.walls += 5
  else: discard