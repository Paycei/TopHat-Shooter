import raylib, types, random, math, strutils

proc getPowerUpName*(powerType: PowerUpType): string =
  case powerType
  of puDoubleShot: "Double Shot"
  of puRotatingShield: "Rotating Shield"
  of puDamageZone: "Damage Aura"
  of puHomingBullets: "Homing Bullets"
  of puPiercingShots: "Piercing Shots"
  of puMultiShot: "Multi-Shot"
  of puExplosiveBullets: "Explosive Rounds"
  of puLifeSteal: "Life Steal"

proc getPowerUpDescription*(powerType: PowerUpType, level: int): string =
  case powerType
  of puDoubleShot:
    case level
    of 1: "Shoot 2 bullets at once"
    of 2: "Shoot 3 bullets at once"
    else: "Shoot 4 bullets at once"
  of puRotatingShield:
    case level
    of 1: "2 shields block enemy bullets"
    of 2: "3 shields block enemy bullets"
    else: "4 shields block enemy bullets"
  of puDamageZone:
    case level
    of 1: "2 dmg/sec in 50 radius"
    of 2: "5 dmg/sec in 100 radius"
    else: "10 dmg/sec in 150 radius"
  of puHomingBullets:
    case level
    of 1: "Bullets slightly track enemies"
    of 2: "Bullets track enemies well"
    else: "Bullets aggressively track enemies"
  of puPiercingShots:
    case level
    of 1: "Bullets pierce 1 enemy"
    of 2: "Bullets pierce 2 enemies"
    else: "Bullets pierce 3 enemies"
  of puMultiShot:
    case level
    of 1: "Shoot in 3 directions (narrow)"
    of 2: "Shoot in 3 directions (wide)"
    else: "Shoot in 5 directions"
  of puExplosiveBullets:
    case level
    of 1: "Bullets explode (small radius)"
    of 2: "Bullets explode (medium radius)"
    else: "Bullets explode (large radius)"
  of puLifeSteal:
    case level
    of 1: "Heal 1 HP per 10 kills"
    of 2: "Heal 1 HP per 7 kills"
    else: "Heal 1 HP per 4 kills"

proc hasPowerUp*(player: Player, powerType: PowerUpType): bool =
  for p in player.powerUps:
    if p.powerType == powerType:
      return true
  return false

proc getPowerUpLevel*(player: Player, powerType: PowerUpType): int =
  for p in player.powerUps:
    if p.powerType == powerType:
      return p.level
  return 0

proc generatePowerUpChoices*(player: Player): array[3, PowerUp] =
  # Generate 3 random power-up options
  var availablePowerUps: seq[PowerUp] = @[]
  
  for powerType in PowerUpType:
    let currentLevel = getPowerUpLevel(player, powerType)
    
    if currentLevel == 0:
      # Can offer level 1
      availablePowerUps.add(PowerUp(powerType: powerType, level: 1))
    elif currentLevel < 3:
      # Can offer upgrade to next level
      availablePowerUps.add(PowerUp(powerType: powerType, level: currentLevel + 1))
    # If level 3, don't add to available options
  
  # Shuffle and pick 3
  for i in countdown(availablePowerUps.high, 1):
    let j = rand(i)
    swap(availablePowerUps[i], availablePowerUps[j])
  
  # Fill result with up to 3 power-ups
  for i in 0..2:
    if i < availablePowerUps.len:
      result[i] = availablePowerUps[i]
    else:
      # If we run out, offer random level 1 power-ups
      result[i] = PowerUp(powerType: PowerUpType(rand(7)), level: 1)

proc applyPowerUp*(player: Player, powerUp: PowerUp) =
  # Check if player already has this power-up
  var found = false
  for i in 0..<player.powerUps.len:
    if player.powerUps[i].powerType == powerUp.powerType:
      # Upgrade existing power-up
      player.powerUps[i].level = powerUp.level
      found = true
      break
  
  if not found:
    # Add new power-up
    player.powerUps.add(powerUp)

proc drawPowerUpCard*(x, y, width, height: int32, powerUp: PowerUp, isSelected: bool) =
  # Card background
  let bgColor = if isSelected: 
    Color(r: 80, g: 120, b: 200, a: 255)
  else:
    Color(r: 50, g: 50, b: 70, a: 255)
  
  drawRectangle(x, y, width, height, bgColor)
  drawRectangleLines(x, y, width, height, 
    if isSelected: Yellow else: Color(r: 150, g: 150, b: 150, a: 255))
  
  # Power-up icon/visual indicator
  let iconY = y + 40
  let centerX = x + width div 2
  
  case powerUp.powerType
  of puDoubleShot:
    for i in 0..<powerUp.level + 1:
      let offsetX = (i - powerUp.level div 2) * 12
      drawCircle(Vector2(x: (centerX + offsetX).float32, y: iconY.float32), 8, Yellow)
  of puRotatingShield:
    drawCircle(Vector2(x: centerX.float32, y: iconY.float32), 15, Blue)
    for i in 0..<powerUp.level + 1:
      let angle = i.float32 * PI * 2.0 / (powerUp.level + 1).float32
      let shieldX = centerX.float32 + cos(angle) * 25
      let shieldY = iconY.float32 + sin(angle) * 25
      drawCircle(Vector2(x: shieldX, y: shieldY), 5, SkyBlue)
  of puDamageZone:
    let zoneRadius = 10 + powerUp.level * 8
    drawCircle(Vector2(x: centerX.float32, y: iconY.float32), zoneRadius.float32, 
              Color(r: 255, g: 100, b: 0, a: 100))
    drawCircleLines(centerX.int32, iconY.int32, zoneRadius.float32, Orange)
  of puHomingBullets:
    drawCircle(Vector2(x: centerX.float32, y: iconY.float32), 8, Magenta)
    # Draw curved path
    for i in 0..5:
      let t = i.float32 / 5.0
      let curve = sin(t * PI) * 15.0
      drawCircle(Vector2(x: (centerX.float32 + i.float32 * 5), 
                        y: (iconY.float32 - curve)), 3, Purple)
  of puPiercingShots:
    for i in 0..<powerUp.level + 1:
      let offsetX = centerX - 20 + i * 20
      drawCircle(Vector2(x: offsetX.float32, y: iconY.float32), 8, Skyblue)
    drawLine(Vector2(x: (centerX - 30).float32, y: iconY.float32), 
            Vector2(x: (centerX + 30).float32, y: iconY.float32), 3, SkyBlue)
  of puMultiShot:
    let bulletCount = if powerUp.level == 3: 5 else: 3
    let spread = if powerUp.level == 2: 0.5 else: 0.3
    for i in 0..<bulletCount:
      let angle = (i - bulletCount div 2).float32 * spread
      let endX = centerX.float32 + sin(angle) * 25
      let endY = iconY.float32 - cos(angle) * 25
      drawLine(Vector2(x: centerX.float32, y: iconY.float32), 
              Vector2(x: endX, y: endY), 2, Yellow)
      drawCircle(Vector2(x: endX, y: endY), 4, Gold)
  of puExplosiveBullets:
    let explosionSize = 8 + powerUp.level * 4
    drawCircle(Vector2(x: centerX.float32, y: iconY.float32), explosionSize.float32, 
              Color(r: 255, g: 150, b: 0, a: 150))
    drawCircle(Vector2(x: centerX.float32, y: iconY.float32), 5, Orange)
  of puLifeSteal:
    drawCircle(Vector2(x: centerX.float32, y: iconY.float32), 12, Red)
    # Draw heart shape approximation
    drawCircle(Vector2(x: (centerX - 5).float32, y: (iconY - 3).float32), 6, Pink)
    drawCircle(Vector2(x: (centerX + 5).float32, y: (iconY - 3).float32), 6, Pink)
  
  # Power-up name
  let name = getPowerUpName(powerUp.powerType)
  let nameWidth = measureText(name, 20)
  drawText(name, x + (width - nameWidth) div 2, y + 90, 20, White)
  
  # Level indicator
  let levelText = "Level " & $powerUp.level
  let levelWidth = measureText(levelText, 16)
  drawText(levelText, x + (width - levelWidth) div 2, y + 115, 16, Gold)
  
  # Description
  let desc = getPowerUpDescription(powerUp.powerType, powerUp.level)
  let descWidth = measureText(desc, 14)
  # Wrap text if too long
  if descWidth > width - 20:
    let words = desc.split(' ')
    var line = ""
    var yOffset = 140
    for word in words:
      let testLine = if line == "": word else: line & " " & word
      if measureText(testLine, 14) > width - 20:
        let lineWidth = measureText(line, 14)
        drawText(line, (x + (width - lineWidth) div 2).int32, (y + yOffset).int32, 14.int32, LightGray)
        line = word
        yOffset += 18
      else:
        line = testLine
    if line != "":
      let lineWidth = measureText(line, 14)
      drawText(line, (x + (width - lineWidth) div 2).int32, (y + yOffset).int32, 14.int32, LightGray)
  else:
    drawText(desc, x + (width - descWidth) div 2, y + 140, 14, LightGray)

proc drawPowerUpSelection*(game: Game) =
  let screenWidth = game.screenWidth
  let screenHeight = game.screenHeight
  
  # Dark overlay
  drawRectangle(0, 0, screenWidth, screenHeight, Color(r: 0, g: 0, b: 0, a: 220))
  
  # Title
  drawText("BOSS DEFEATED!", screenWidth div 2 - 200, 80, 50, Gold)
  drawText("Choose Your Power-Up", screenWidth div 2 - 180, 140, 30, White)
  
  # Draw 3 cards
  let cardWidth = 200
  let cardHeight = 240
  let spacing = 40
  let totalWidth = cardWidth * 3 + spacing * 2
  let startX = (screenWidth - totalWidth) div 2
  let cardY = 200
  
  for i in 0..2:
    let cardX = startX + i * (cardWidth + spacing)
    drawPowerUpCard(cardX.int32, cardY.int32, cardWidth.int32, cardHeight.int32,
                   game.powerUpChoices[i], i == game.selectedPowerUp)

  
  # Instructions
  drawText("Use ARROW KEYS to select, ENTER to choose", 
          screenWidth div 2 - 250, screenHeight - 100, 20, LightGray)
