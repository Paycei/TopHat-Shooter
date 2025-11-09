import raylib, types, math, powerup, sound

proc initShopItems*(): array[6, ShopItem] =
  result[0] = ShopItem(name: "Damage +", description: "Increase bullet damage", baseCost: 8, bought: 0)
  result[1] = ShopItem(name: "Fire Rate +", description: "Shoot faster", baseCost: 10, bought: 0)
  result[2] = ShopItem(name: "Move Speed +", description: "Move faster", baseCost: 7, bought: 0)
  result[3] = ShopItem(name: "Max Health +", description: "Increase max HP", baseCost: 12, bought: 0)
  result[4] = ShopItem(name: "Bullet Speed +", description: "Faster bullets", baseCost: 6, bought: 0)
  result[5] = ShopItem(name: "Wall (x4)", description: "Buy 4 deployable walls", baseCost: 15, bought: 0)

proc getCurrentCost*(item: ShopItem): int =
  # More aggressive exponential cost scaling: baseCost * 1.5^bought
  (item.baseCost.float32 * pow(1.5, item.bought.float32)).int

proc drawShop*(game: Game) =
  let screenWidth = game.screenWidth
  let screenHeight = game.screenHeight
  
  # Dark overlay
  drawRectangle(0, 0, screenWidth, screenHeight, Color(r: 0, g: 0, b: 0, a: 200))
  
  # Shop title
  drawText("SHOP (ESC to continue)", screenWidth div 2 - 150, 30, 30, Yellow)
  drawText("Coins: " & $game.player.coins, screenWidth div 2 - 100, 70, 20, Gold)
  
  # Add selection pointer on the left (matching main menu style)
  let pointerPulse = sin(getTime() * 6.0) * 0.3 + 0.7
  let pointerSize = 10 + (pointerPulse * 5).int32
  
  # Display owned permanent upgrades on the left side
  var upgradeY: int32 = 120
  let upgradeX: int32 = 30
  drawText("PERMANENT UPGRADES:", upgradeX, upgradeY, 18, Color(r: 100, g: 255, b: 100, a: 255))
  upgradeY += 30
  
  if game.player.powerUps.len == 0:
    drawText("None yet - defeat waves to earn!", upgradeX, upgradeY, 14, LightGray)
  else:
    for powerUp in game.player.powerUps:
      let name = getPowerUpName(powerUp.powerType)
      let levelText = "L" & $powerUp.level
      let rarityColor = if powerUp.rarity == prLegendary: Gold else: White
      
      # Draw power-up name with level
      drawText(name & " " & levelText, upgradeX, upgradeY, 16, rarityColor)
      upgradeY += 20
      
      # Show description in smaller text
      let desc = getPowerUpDescription(powerUp.powerType, powerUp.level)
      drawText(desc, upgradeX + 10, upgradeY, 12, Color(r: 180, g: 180, b: 180, a: 255))
      upgradeY += 24
      
      # Spacing between upgrades
      if upgradeY > screenHeight - 100:
        # Too many upgrades, indicate there are more
        drawText("... and more", upgradeX, upgradeY, 14, LightGray)
        break
  
  # Shop items on the right side
  let shopStartX = screenWidth div 2 - 200
  let startY = 120
  let itemHeight = 70
  
  for i in 0..5:
    let y = startY + i * itemHeight
    let item = game.shopItems[i]
    let cost = getCurrentCost(item)
    
    # Draw selection pointer (left of selected item)
    if i == game.selectedShopItem:
      let pointerX = shopStartX - 35
      let pointerY = y + 30
      drawCircle(Vector2(x: pointerX.float32, y: pointerY.float32), pointerSize.float32,
                Color(r: 255'u8, g: 200'u8, b: 0'u8, a: 200'u8))
      # Draw arrow pointing right
      drawText(">", (pointerX - 5).int32, (pointerY - 10).int32, 20, Gold)
    
    var bgColor = if i == game.selectedShopItem: DarkGray else: Gray
    if game.player.coins < cost:
      bgColor = Color(r: 60, g: 60, b: 60, a: 255)
    
    drawRectangle(shopStartX, y.int32, 400, 60, bgColor)
    drawRectangleLines(shopStartX, y.int32, 400, 60, White)
    
    let nameText = item.name & " (" & $item.bought & " bought)"
    drawText(nameText, shopStartX + 10, y.int32 + 10, 20, White)
    drawText(item.description, shopStartX + 10, y.int32 + 35, 16, LightGray)
    
    let costText = "Cost: " & $cost
    let costColor = if game.player.coins >= cost: Green else: Red
    drawText(costText, shopStartX + 270, y.int32 + 20, 18, costColor)
  
  drawText("ARROW KEYS: select | ENTER: buy | ESC: continue", 
          screenWidth div 2 - 280, screenHeight - 50, 18, LightGray)

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
  
  case index
  of 0: # Damage - NERFED scaling
    game.player.damage += 0.5 * pow(1.08, item.bought.float32)
  of 1: # Fire Rate - NERFED, better diminishing returns
    game.player.fireRate *= 0.88
    if game.player.fireRate < 0.05: game.player.fireRate = 0.05
  of 2: # Move Speed - NERFED gains
    game.player.speed += 18
    game.player.baseSpeed += 18
  of 3: # Max Health - NERFED HP per purchase
    game.player.maxHp += 2
    game.player.hp += 2
  of 4: # Bullet Speed - NERFED
    game.player.bulletSpeed += 50
  of 5: # Walls - Same as before
    game.player.walls += 4
  else: discard
