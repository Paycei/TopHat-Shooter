import raylib, types, math, powerup, strutils

proc initShopItems*(): array[6, ShopItem] =
  result[0] = ShopItem(name: "Damage +", description: "Increase bullet damage", baseCost: 7, bought: 0)
  result[1] = ShopItem(name: "Fire Rate +", description: "Shoot faster", baseCost: 9, bought: 0)
  result[2] = ShopItem(name: "Move Speed +", description: "Move faster", baseCost: 7, bought: 0)
  result[3] = ShopItem(name: "Max Health +", description: "Increase max HP", baseCost: 12, bought: 0)
  result[4] = ShopItem(name: "Bullet Speed +", description: "Faster bullets", baseCost: 6, bought: 0)
  result[5] = ShopItem(name: "Wall (x4)", description: "Buy 4 deployable walls", baseCost: 15, bought: 0)

proc getCurrentCost*(item: ShopItem): int =
  # Slightly lower exponential cost scaling: baseCost * 1.3^bought
  (item.baseCost.float32 * pow(1.3, item.bought.float32)).int

proc drawShop*(game: Game) =
  let screenWidth = game.screenWidth
  let screenHeight = game.screenHeight
  
  # Dark overlay
  drawRectangle(0, 0, screenWidth, screenHeight, Color(r: 0, g: 0, b: 0, a: 200))
  
  # Shop title
  drawText("SHOP (TAB to close)", screenWidth div 2 - 150, 30, 30, Yellow)
  drawText("Coins: " & $game.player.coins, screenWidth div 2 - 100, 70, 20, Gold)
  
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
  
  drawText("ARROW KEYS: select | ENTER: buy | TAB/ESC: close", 
          screenWidth div 2 - 280, screenHeight - 50, 18, LightGray)

proc buyShopItem*(game: Game, index: int) =
  if index < 0 or index > 5: return
  
  let item = addr game.shopItems[index]
  let cost = getCurrentCost(item[])
  if game.player.coins < cost: return
  
  game.player.coins -= cost
  item.bought += 1
  
  case index
  of 0: # Damage - MORE POWERFUL scaling
    game.player.damage += 0.7 * pow(1.12, item.bought.float32)
  of 1: # Fire Rate - better diminishing returns, more impactful
    game.player.fireRate *= 0.82
    if game.player.fireRate < 0.04: game.player.fireRate = 0.04
  of 2: # Move Speed - MUCH FASTER gains
    game.player.speed += 28
    game.player.baseSpeed += 28
  of 3: # Max Health - MORE HP per purchase
    game.player.maxHp += 3
    game.player.hp += 3
  of 4: # Bullet Speed - SIGNIFICANTLY faster
    game.player.bulletSpeed += 80
  of 5: # Walls - MORE walls per purchase
    game.player.walls += 4
  else: discard
