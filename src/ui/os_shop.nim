## OS-Style Shop System
## Shop screen redesigned as a modern OS storefront interface

import raylib, math, strutils
import ../types, ../localization, ../powerup_data, ../sound, ../run_statistics, icon_drawing, ../render_context

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
  SHOP_FIRE_RATE_GAIN = 0.075'f32
  SHOP_FIRE_RATE_EXPONENT = 0.42'f32
  SHOP_FIRE_RATE_CAP = 0.09'f32
  SHOP_MOVE_SPEED_GAIN = 15.0'f32
  SHOP_HEALTH_GAIN_BASE = 6
  SHOP_BULLET_SPEED_GAIN = 10.0'f32
  SHOP_WALL_GAIN = 10
  # Base costs per shop slot (damage, fire rate, move speed, max hp, bullet
  # speed, walls). Shared by initShopItems and the sandbox wave-average
  # simulation so the two can never disagree.
  SHOP_BASE_COSTS = [13, 13, 10, 14, 9, 18]

proc shopFitText(text: string, maxWidth, fontSize: int32,
                 minSize: int32 = 8): tuple[text: string, size: int32] =
  ## Shrinks font size first, then truncates with "..." so text fits within maxWidth pixels.
  var fs = fontSize
  while fs > minSize and measureText(text, fs) > maxWidth:
    dec fs
  if measureText(text, fs) <= maxWidth:
    return (text, fs)
  # Still too wide, truncate character by character
  var t = text
  while t.len > 0 and measureText(t & "...", fs) > maxWidth:
    t = t[0..^2]
  return (t & "...", fs)

proc shopWrapText(text: string, maxWidth, fontSize: int32): seq[string] =
  ## Word-wraps text into lines that each fit within maxWidth pixels at fontSize.
  ## Words that are individually wider than maxWidth are hard-broken at the character level.
  result = @[]
  var words: seq[string] = @[]
  for w in text.splitWhitespace():
    words.add(w)
  if words.len == 0:
    return

  var currentLine = ""
  for word in words:
    let candidate = if currentLine.len == 0: word else: currentLine & " " & word
    if measureText(candidate, fontSize) <= maxWidth:
      currentLine = candidate
    else:
      if currentLine.len > 0:
        result.add(currentLine)
      # If the bare word is still too wide, hard-break it character by character
      if measureText(word, fontSize) > maxWidth:
        var chunk = ""
        for ch in word:
          if measureText(chunk & $ch, fontSize) <= maxWidth:
            chunk &= $ch
          else:
            if chunk.len > 0:
              result.add(chunk)
            chunk = $ch
        currentLine = chunk
      else:
        currentLine = word
  if currentLine.len > 0:
    result.add(currentLine)

proc drawWrappedText(text: string, x, y, maxWidth, fontSize: int32,
                     color: Color, lineSpacing: int32 = 2): int32 =
  ## Draws word-wrapped text, returning the total pixel height consumed.
  let lines = shopWrapText(text, maxWidth, fontSize)
  let lineHeight = fontSize + lineSpacing
  for i, line in lines:
    drawText(line, x, y + int32(i) * lineHeight, fontSize, color)
  result = int32(lines.len) * lineHeight

proc initShopItems*(): array[6, ShopItem] =
  result[0] = ShopItem(name: t(tkShopDamagePlus), description: t(tkShopDamagePlusDesc), baseCost: SHOP_BASE_COSTS[0], bought: 0)
  result[1] = ShopItem(name: t(tkShopFireRatePlus), description: t(tkShopFireRatePlusDesc), baseCost: SHOP_BASE_COSTS[1], bought: 0)
  result[2] = ShopItem(name: t(tkShopMoveSpeedPlus), description: t(tkShopMoveSpeedPlusDesc), baseCost: SHOP_BASE_COSTS[2], bought: 0)
  result[3] = ShopItem(name: t(tkShopMaxHealthPlus), description: t(tkShopMaxHealthPlusDesc), baseCost: SHOP_BASE_COSTS[3], bought: 0)
  result[4] = ShopItem(name: t(tkShopBulletSpeedPlus), description: t(tkShopBulletSpeedPlusDesc), baseCost: SHOP_BASE_COSTS[4], bought: 0)
  result[5] = ShopItem(name: t(tkShopWallX4), description: t(tkShopWallX4Desc), baseCost: SHOP_BASE_COSTS[5], bought: 0)

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

proc waveEnemyCoinEstimate(wave: int): float32 =
  ## Expected coins from a single non-boss kill at `wave`: the per-tier spawn
  ## roll tables in spawnWaveEnemies (game.nim) folded with enemyCoinValue's
  ## per-type payouts (coin.nim). One entry per 5-wave roster tier; the last
  ## entry covers waves 56+ where the roster stops changing.
  const tierAvg = [1.0'f32, 1.0, 1.4, 1.85, 2.2, 2.35,
                   2.9, 3.0, 3.1, 3.4, 3.95, 4.7]
  tierAvg[min((wave - 1) div 5, tierAvg.high)]

proc sandboxWaveAverageConfig*(base: SandboxConfig, wave: int): SandboxConfig =
  ## Estimate the stat loadout a typical player would have *entering* `wave`,
  ## starting from `base` (the wave-1 baseline stats). Rather than assuming a
  ## fixed number of shop purchases, this replays the run wave by wave with the
  ## real progression formulas, so late-wave builds stay honest:
  ##   1. startWave's 1.012x passive scaling is applied once per wave *before*
  ##      that wave's shopping, so (like a real run) early purchases compound
  ##      for the rest of the run while late purchases barely do.
  ##   2. Coin income follows the real enemy-count curve, the spawn-mix coin
  ##      averages, and boss bounties (~90% of drops collected).
  ##   3. Shop purchases are constrained by that budget and the real 1.8x cost
  ##      curve: always buy the cheapest affordable upgrade, which keeps the
  ##      six upgrade tracks at roughly equal cost tiers (balanced spending).
  ## Still an approximation (elites, combo bonuses, and spending taste vary),
  ## but every stat gain flows through the live game's own formulas and every
  ## purchase had to be paid for at the real price.
  result = base
  let w = max(1, wave)
  var coins = base.coins.float32
  var bought: array[6, int]

  for n in 1 ..< w:
    # startWave's per-wave scaling for wave n (mirrors game.nim).
    const waveScaling = 1.012'f32
    result.maxHp *= waveScaling
    result.damage *= waveScaling
    result.speed *= waveScaling
    result.bulletSpeed = multiplyBulletSpeedDiminished(result.bulletSpeed, waveScaling)
    result.fireRate /= waveScaling   # lower = faster, so divide

    # Income from clearing wave n: enemy count mirrors calculateWaveEnemyCount
    # (game.nim), boss waves spawn 25% of normal but pay the boss bounty.
    var enemyCount = 8.0'f32 + 3.0'f32 * pow(float32(n - 1), 0.6'f32)
    let isBossWave = n mod 5 == 0
    if isBossWave:
      enemyCount *= 0.25'f32
    var income = enemyCount * waveEnemyCoinEstimate(n)
    if isBossWave:
      income += float32(50 + (n div 5) * 10)   # enemyCoinValue's boss payout
    coins += income * 0.9'f32   # some drops expire uncollected

    # Shop between waves: buy the cheapest affordable upgrade until broke,
    # at the real getCurrentCost price (baseCost * 1.8^bought).
    while true:
      var slot = 0
      var slotCost = high(int)
      for s in 0 ..< 6:
        let cost = int(SHOP_BASE_COSTS[s].float32 *
                       pow(SHOP_COST_MULTIPLIER, bought[s].float32))
        if cost < slotCost:
          slot = s
          slotCost = cost
      if slotCost.float32 > coins:
        break
      coins -= slotCost.float32
      inc bought[slot]
      case slot
      of 0: result.damage += shopDamageGain(bought[0])
      of 1: result.fireRate = applyFireRateDiminished(result.fireRate,
              SHOP_FIRE_RATE_GAIN, SHOP_FIRE_RATE_EXPONENT, SHOP_FIRE_RATE_CAP)
      of 2: result.speed += SHOP_MOVE_SPEED_GAIN
      of 3: result.maxHp += shopHealthGain(bought[3]).float32
      of 4: result.bulletSpeed = addBulletSpeedDiminished(result.bulletSpeed, SHOP_BULLET_SPEED_GAIN)
      of 5: result.walls += SHOP_WALL_GAIN
      else: discard

  # Whatever wasn't spent is the pocket money the build enters the wave with.
  result.coins = coins.int
  result.startWave = w

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

  # Description (if provided), fit within the button so it never overflows
  if description.len > 0:
    let descColor = if canAfford:
      Color(r: 160, g: 170, b: 180, a: 255)
    else:
      Color(r: 90, g: 95, b: 100, a: 255)
    let btnDescMaxW = width - (textX - x) - 8  # available pixels right of the icon
    let (fittedBtnDesc, fittedBtnDescSize) = shopFitText(description, btnDescMaxW, 10)
    drawText(fittedBtnDesc, textX, y + 24, fittedBtnDescSize, descColor)

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
  let HEADER_H: int32 = 35
  let contentAreaY  = sidebarY + HEADER_H
  let contentAreaH  = sidebarHeight - HEADER_H
  let SCROLLBAR_W: int32 = 6
  let contentInnerW: int32 = SIDEBAR_WIDTH - SCROLLBAR_W - 2  # leave room for scrollbar

  drawRectangle(sidebarX, sidebarY, SIDEBAR_WIDTH, sidebarHeight,
               Color(r: 30, g: 38, b: 52, a: 255))
  drawRectangleLines(Rectangle(x: sidebarX.float32, y: sidebarY.float32,
                                width: SIDEBAR_WIDTH.float32, height: sidebarHeight.float32),
                    1, Color(r: 0, g: 140, b: 200, a: 255))

  # Sidebar header (drawn above scissor region so it is always visible)
  drawRectangle(sidebarX, sidebarY, SIDEBAR_WIDTH, HEADER_H,
               Color(r: 40, g: 50, b: 65, a: 255))
  drawText("[L] " & t(tkShopActiveUpgrades), sidebarX + 10, sidebarY + 9, 16,
          Color(r: 150, g: 200, b: 255, a: 255))

  # measure total content height (dry run, no drawing)
  let upgradeX = sidebarX + 12
  let sidebarDescMaxW: int32 = contentInnerW - 20 - 4  # indent + right pad
  var totalContentH: int32 = 8   # top padding
  if game.player.powerUps.len == 0:
    totalContentH += 18 + 18
  else:
    for powerUp in game.player.powerUps:
      totalContentH += 18  # name row
      let desc = getPowerUpDescription(powerUp.powerType, powerUp.level, game.player.damage)
      let wrappedLines = shopWrapText(desc, sidebarDescMaxW, 10)
      totalContentH += int32(wrappedLines.len) * 12 + 4  # desc rows
  totalContentH += 8  # bottom padding

  # clamp scroll offset
  let maxScroll = max(0'i32, totalContentH - contentAreaH)
  game.shopSidebarScroll = clamp(game.shopSidebarScroll, 0'i32, maxScroll)

  # mouse-wheel scroll when cursor is over the sidebar
  let mp = getVirtualMousePosition()
  let sidebarRect = Rectangle(x: sidebarX.float32, y: contentAreaY.float32,
                               width: SIDEBAR_WIDTH.float32, height: contentAreaH.float32)
  if checkCollisionPointRec(mp, sidebarRect):
    let wheel = getPointerWheelMove()
    if wheel != 0.0:
      game.shopSidebarScroll = clamp(game.shopSidebarScroll - int32(wheel * 20.0),
                                      0'i32, maxScroll)

  # scissor clip the scrollable content
  beginVirtualScissorMode(sidebarX, contentAreaY, SIDEBAR_WIDTH - SCROLLBAR_W - 1, contentAreaH)

  var upgradeY: int32 = contentAreaY + 8 - game.shopSidebarScroll

  if game.player.powerUps.len == 0:
    drawText(t(tkShopNoPermanent), upgradeX, upgradeY, 13,
            Color(r: 150, g: 160, b: 170, a: 255))
    upgradeY += 18
    drawText(t(tkShopDefeatWaves), upgradeX, upgradeY, 12, LightGray)
  else:
    for powerUp in game.player.powerUps:
      let name = getPowerUpName(powerUp.powerType)
      let levelText = "Lv." & $powerUp.level
      let rarityColor = if powerUp.rarity == prLegendary: Gold
                       else: Color(r: 200, g: 220, b: 255, a: 255)

      drawText("> " & name, upgradeX, upgradeY, 14, rarityColor)
      let levelWidth = measureText(levelText, 11)
      drawText(levelText, sidebarX + SIDEBAR_WIDTH - SCROLLBAR_W - levelWidth - 10, upgradeY + 2, 11,
              Color(r: 100, g: 200, b: 255, a: 255))
      upgradeY += 18

      let desc = getPowerUpDescription(powerUp.powerType, powerUp.level, game.player.damage)
      let descHeight = drawWrappedText(desc, upgradeX + 8, upgradeY,
                                       sidebarDescMaxW, 10,
                                       Color(r: 150, g: 160, b: 170, a: 255))
      upgradeY += descHeight + 4

  endScissorMode()

  # scrollbar
  if maxScroll > 0:
    let sbX = sidebarX + SIDEBAR_WIDTH - SCROLLBAR_W - 1
    let sbTrackH = contentAreaH
    drawRectangle(sbX, contentAreaY, SCROLLBAR_W, sbTrackH,
                 Color(r: 20, g: 28, b: 40, a: 200))
    let thumbRatio = contentAreaH.float32 / totalContentH.float32
    let thumbH = max(20'i32, int32(sbTrackH.float32 * thumbRatio))
    let thumbY = contentAreaY + int32(float32(sbTrackH - thumbH) *
                   (game.shopSidebarScroll.float32 / maxScroll.float32))
    drawRectangle(sbX + 1, thumbY, SCROLLBAR_W - 2, thumbH,
                 Color(r: 0, g: 160, b: 220, a: 200))
    # top/bottom fade hints when content overflows
    if game.shopSidebarScroll > 0:
      for i in 0'i32..7'i32:
        drawRectangle(sidebarX, contentAreaY + i, SIDEBAR_WIDTH - SCROLLBAR_W - 1, 1,
                     Color(r: 30, g: 38, b: 52, a: uint8(200 - i * 25)))
    if game.shopSidebarScroll < maxScroll:
      for i in 0'i32..7'i32:
        let fy = contentAreaY + contentAreaH - 1 - i
        drawRectangle(sidebarX, fy, SIDEBAR_WIDTH - SCROLLBAR_W - 1, 1,
                     Color(r: 30, g: 38, b: 52, a: uint8(200 - i * 25)))

  # Re-draw the header border line on top of any content that bled through
  drawRectangle(sidebarX, sidebarY + HEADER_H - 1, SIDEBAR_WIDTH, 1,
               Color(r: 0, g: 100, b: 160, a: 180))

  # Shop items area
  let shopX = sidebarX + SIDEBAR_WIDTH + 15
  let shopY = sidebarY + 10
  let shopWidth = SHOP_WIDTH - SIDEBAR_WIDTH - 40

  drawText("v " & t(tkShopAvailablePurchases), shopX, shopY, 16,
          Color(r: 200, g: 220, b: 240, a: 255))

  let itemsStartY = shopY + 35

  # Mouse hover detection
  if game.mouseMovedRecently and not game.keyboardUsedRecently:
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
