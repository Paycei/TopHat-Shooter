## OS-Style Process Installer Module
## Power-up selection screen as modern software installation interface
# The roll animation system is handled in powerup.nim

import raylib, ../types, math, strutils, icon_drawing, ../localization, ../powerup_data

const
  INSTALLER_WIDTH = 1000
  INSTALLER_HEIGHT = 650
  TITLE_BAR_HEIGHT = 45
  CARD_WIDTH = 280
  CARD_HEIGHT = 380
  CARD_SPACING = 35
  PROGRESS_BAR_HEIGHT = 22

proc drawModernButton(x, y, width, height: int32, text: string, 
                     enabled: bool = true, highlight: bool = false, 
                     time: float32 = 0.0) =
  let bgColor = if not enabled:
    Color(r: 35, g: 40, b: 50, a: 255)
  elif highlight:
    Color(r: 0, g: 140, b: 255, a: 255)
  else:
    Color(r: 45, g: 55, b: 70, a: 255)
  
  if enabled:
    drawRectangle(x + 2, y + 2, width, height,
                 Color(r: 0, g: 0, b: 0, a: 80))
  
  drawRectangle(x, y, width, height, bgColor)
  
  if enabled:
    drawRectangle(x, y, width, 2,
                 Color(r: 255, g: 255, b: 255, a: 30))
  
  let borderColor = if not enabled:
    Color(r: 70, g: 80, b: 90, a: 255)
  elif highlight:
    let pulse = sin(time * 5.0) * 0.3 + 0.7
    Color(r: 0, g: 200, b: 255, a: uint8(200 * pulse))
  else:
    Color(r: 100, g: 120, b: 140, a: 255)
  
  let borderWidth = if highlight: 2.5 else: 2.0
  drawRectangleLines(Rectangle(x: x.float32, y: y.float32,
                                width: width.float32, height: height.float32),
                    borderWidth, borderColor)
  
  let textColor = if not enabled: 
    Color(r: 100, g: 100, b: 110, a: 255)
  else: 
    White
  
  let textWidth = measureText(text, 15)
  drawText(text, x + (width - textWidth) div 2, y + (height - 15) div 2, 15, textColor)

proc drawProcessCard(x, y, width, height: int32, powerUp: PowerUp, 
                    selected: bool, time: float32, blurAmount: float32 = 1.0) =
  ## Draw power-up card with motion blur during roll
  
  # Card shadow (reduced during motion)
  if blurAmount > 0.5:
    for i in 0..2:
      let offset = (i + 1) * 2
      let alpha = uint8((40 - i * 10).float32 * blurAmount)
      drawRectangle(int32(x + offset), int32(y + offset), width, height,
                   Color(r: 0, g: 0, b: 0, a: alpha))
  
  # Card background
  let bgColor = if selected:
    Color(r: 35, g: 48, b: 65, a: 255)
  else:
    Color(r: 22, g: 28, b: 40, a: 255)
  
  drawRectangle(x, y, width, height, bgColor)
  
  # Top accent bar
  let accentColor = if powerUp.rarity == prLegendary:
    Color(r: 255, g: 215, b: 0, a: 255)
  else:
    Color(r: 0, g: 180, b: 255, a: 255)
  
  drawRectangle(x, y, width, 4, accentColor)
  
  # Selection glow
  if selected and blurAmount > 0.7:
    let pulse = sin(time * 4.5) * 0.25 + 0.75
    let glowAlpha = uint8(180 * pulse * blurAmount)
    
    for i in 1..3:
      let offset = i * 2
      drawRectangleLines(
        Rectangle(x: (x - offset).float32, y: (y - offset).float32,
                 width: (width + offset * 2).float32, height: (height + offset * 2).float32),
        1, Color(r: 0, g: 200, b: 255, a: uint8(glowAlpha div uint8(i * 2)))
      )
  
  # Card border
  let borderColor = if selected:
    Color(r: 0, g: 220, b: 255, a: 255)
  else:
    Color(r: 60, g: 75, b: 95, a: 255)
  
  let borderThickness = if selected: 3.0 else: 2.0
  drawRectangleLines(Rectangle(x: x.float32, y: y.float32,
                                width: width.float32, height: height.float32),
                    borderThickness, borderColor)
  
  var yOffset = y + 20
  
  # Enhanced Icon/Badge area with depth
  let iconSize = 60
  let iconX = x + (width - iconSize) div 2
  
  # Icon background with layered depth
  drawRectangle(int32(iconX + 2), yOffset + 2, int32(iconSize), int32(iconSize),
               Color(r: 0, g: 0, b: 0, a: 80))
  drawRectangle(int32(iconX), yOffset, int32(iconSize), int32(iconSize),
               Color(r: 30, g: 38, b: 52, a: 255))
  
  # Inner frame
  drawRectangle(int32(iconX + 3), yOffset + 3, int32(iconSize - 6), int32(iconSize - 6),
               Color(r: 40, g: 50, b: 65, a: 255))
  
  # Border with accent
  drawRectangleLines(Rectangle(x: iconX.float32, y: yOffset.float32,
                                width: iconSize.float32, height: iconSize.float32),
                    2, accentColor)
  drawRectangleLines(Rectangle(x: (iconX + 2).float32, y: (yOffset + 2).float32,
                                width: (iconSize - 4).float32, height: (iconSize - 4).float32),
                    1, Color(r: accentColor.r, g: accentColor.g, b: accentColor.b, a: 120))
  
  # Corner decorations for legendary
  if powerUp.rarity == prLegendary and blurAmount > 0.6:
    let pulse = sin(time * 3.0) * 0.3 + 0.7
    let cornerSize = int32(6)
    # Top-left corner
    drawRectangle(int32(iconX - 2), yOffset - 2, cornerSize, 2, Color(r: 255, g: 215, b: 0, a: uint8(255 * pulse)))
    drawRectangle(int32(iconX - 2), yOffset - 2, 2, cornerSize, Color(r: 255, g: 215, b: 0, a: uint8(255 * pulse)))
    # Top-right corner
    drawRectangle(int32(iconX + iconSize - cornerSize + 2), yOffset - 2, cornerSize, 2, Color(r: 255, g: 215, b: 0, a: uint8(255 * pulse)))
    drawRectangle(int32(iconX + iconSize), yOffset - 2, 2, cornerSize, Color(r: 255, g: 215, b: 0, a: uint8(255 * pulse)))
    # Bottom-left corner
    drawRectangle(int32(iconX - 2), yOffset + int32(iconSize), cornerSize, 2, Color(r: 255, g: 215, b: 0, a: uint8(255 * pulse)))
    drawRectangle(int32(iconX - 2), yOffset + int32(iconSize - cornerSize + 2), 2, cornerSize, Color(r: 255, g: 215, b: 0, a: uint8(255 * pulse)))
    # Bottom-right corner
    drawRectangle(int32(iconX + iconSize - cornerSize + 2), yOffset + int32(iconSize), cornerSize, 2, Color(r: 255, g: 215, b: 0, a: uint8(255 * pulse)))
    drawRectangle(int32(iconX + iconSize), yOffset + int32(iconSize - cornerSize + 2), 2, cornerSize, Color(r: 255, g: 215, b: 0, a: uint8(255 * pulse)))
  
  # Draw power-up specific icon using enhanced graphics (larger for better visibility)
  drawPowerUpIcon(int32(iconX + 5), yOffset + 5, int32(iconSize - 10), powerUp.powerType, accentColor)
  yOffset += int32(iconSize + 18)
  
  # Process name
  let processName = getPowerUpName(powerUp.powerType)
  let nameWidth = measureText(processName, 20)
  drawText(processName, (x + (width - nameWidth) div 2), yOffset, 20,
          if powerUp.rarity == prLegendary: Gold else: Color(r: 100, g: 200, b: 255, a: 255))
  yOffset += 30
  
  # Version and Rarity badges on same line (centered together)
  let versionText = "v" & $powerUp.level & ".0"
  let versionWidth = measureText(versionText, 14)
  let versionBadgeWidth = versionWidth + 28  # Match rarity badge padding
  
  let rarityText = if powerUp.rarity == prLegendary: "[*] LEGENDARY [*]" else: "STANDARD"
  let rarityWidth: int32 = measureText(rarityText, 14)
  let rarityBadgeWidth = rarityWidth + 28
  
  let badgeSpacing = 15
  let totalBadgeWidth = versionBadgeWidth + badgeSpacing + rarityBadgeWidth
  let badgesStartX: int32 = x + int32((width - totalBadgeWidth) div 2)
  
  let versionX: int32 = badgesStartX
  let badgeX: int32 = badgesStartX + versionBadgeWidth + badgeSpacing.int32
  let badgeHeight: int32 = 28
  
  # Version badge
  let versionBgColor = case powerUp.level
    of 1: Color(r: 45, g: 55, b: 80, a: 255)
    of 2: Color(r: 45, g: 70, b: 55, a: 255)
    else: Color(r: 70, g: 50, b: 45, a: 255)
  
  # Version badge shadow
  drawRectangle(versionX + 1, yOffset + 1, versionBadgeWidth, badgeHeight,
               Color(r: 0, g: 0, b: 0, a: 80))
  
  # Version badge background
  drawRectangle(versionX, yOffset, versionBadgeWidth, badgeHeight, versionBgColor)
  
  # Highlight stripe
  drawRectangle(versionX, yOffset, versionBadgeWidth, 2,
               Color(r: min(versionBgColor.r + 60, 255), g: min(versionBgColor.g + 60, 255), b: min(versionBgColor.b + 60, 255), a: 255))
  
  # Border with level color
  let versionBorderColor = case powerUp.level
    of 1: Color(r: 80, g: 120, b: 180, a: 255)
    of 2: Color(r: 80, g: 180, b: 120, a: 255)
    else: Color(r: 180, g: 120, b: 80, a: 255)
  
  drawRectangleLines(Rectangle(x: versionX.float32, y: yOffset.float32,
                                width: versionBadgeWidth.float32, height: badgeHeight.float32),
                    2, versionBorderColor)
  
  # Version text with shadow (centered horizontally and vertically in badge)
  let versionTextX = versionX + (versionBadgeWidth - versionWidth) div 2
  let versionTextY = yOffset + (badgeHeight - 14) div 2  # 14 is the font size
  drawText(versionText, versionTextX + 1, versionTextY + 1, 14, Color(r: 0, g: 0, b: 0, a: 150))
  drawText(versionText, versionTextX, versionTextY, 14, Color(r: 200, g: 210, b: 220, a: 255))
  
  # Rarity badge
  let rarityColor = if powerUp.rarity == prLegendary:
    Color(r: 255, g: 215, b: 0, a: 255)
  else:
    Color(r: 100, g: 180, b: 220, a: 255)
  
  # Legendary glow effect
  if powerUp.rarity == prLegendary and blurAmount > 0.6:
    let glowPulse = sin(time * 3.0) * 0.35 + 0.65
    # Multiple glow layers
    for i in 1..4:
      let glowSize: int32 = int32(i * 3)
      drawRectangle(badgeX.int32 - glowSize, yOffset - glowSize, 
                   rarityWidth + 28 + glowSize * 2, badgeHeight + glowSize * 2,
                   Color(r: 255, g: 215, b: 0, a: uint8((60.0 - i.float * 12.0) * glowPulse * blurAmount)))
    # Sparkle particles around badge
    for i in 0..5:
      let sparkAngle = time * 4.0 + i.float32 * 1.047  # 60 degrees apart
      let sparkDist = 25.0 + sin(time * 5.0 + i.float32) * 5.0
      let sparkX = badgeX + (rarityWidth + 28) div 2 + int32(cos(sparkAngle) * sparkDist)
      let sparkY = yOffset + badgeHeight div 2 + int32(sin(sparkAngle) * sparkDist * 0.6)
      let sparkSize = 2 + (sin(time * 6.0 + i.float32 * 0.5) * 1.5).int32
      drawCircle(Vector2(x: sparkX.float32, y: sparkY.float32), sparkSize.float32,
                Color(r: 255, g: 240, b: 150, a: uint8(200 * glowPulse)))
  
  # Badge shadow
  drawRectangle(badgeX + 2, yOffset + 2, rarityWidth + 28, int32(badgeHeight),
               Color(r: 0, g: 0, b: 0, a: 100))
  
  # Badge background with gradient
  drawRectangle(badgeX, yOffset, rarityWidth + 28, int32(badgeHeight),
               Color(r: 35, g: 40, b: 50, a: 255))
  if powerUp.rarity == prLegendary:
    # Gradient overlay for legendary
    drawRectangle(badgeX, yOffset, rarityWidth + 28, int32(badgeHeight div 2),
                 Color(r: 80, g: 70, b: 20, a: 100))
  
  # Badge border with double-line for legendary
  drawRectangleLines(Rectangle(x: badgeX.float32, y: yOffset.float32,
                                width: (rarityWidth + 28).float32, height: badgeHeight.float32),
                    2, rarityColor)
  if powerUp.rarity == prLegendary:
    drawRectangleLines(Rectangle(x: (badgeX + 3).float32, y: (yOffset + 3).float32,
                                  width: (rarityWidth + 22).float32, height: (badgeHeight - 6).float32),
                      1, Color(r: 255, g: 235, b: 100, a: 180))
  
  # Badge text with shadow
  drawText(rarityText, badgeX + 15, yOffset + 8, 14,
          Color(r: 0, g: 0, b: 0, a: 180))
  drawText(rarityText, badgeX + 14, yOffset + 7, 14, rarityColor)
  yOffset += 48
  
  # Legendary power-ups only have 1 tier, others have 3
  let maxTiers = if powerUp.rarity == prLegendary: 1 else: 3
  
  # Compact tier label
  drawText(t(tkPowerUpUpgradeTier), x + 12, yOffset, 12,  
          Color(r: 140, g: 160, b: 180, a: 255))
  yOffset += 18
  
  # Enhanced progress bar with segments
  let barWidth = width - 24
  
  # Bar shadow
  drawRectangle(x + 14, yOffset + 2, barWidth, PROGRESS_BAR_HEIGHT,
               Color(r: 0, g: 0, b: 0, a: 80))
  
  # Bar background with segments
  drawRectangle(x + 12, yOffset, barWidth, PROGRESS_BAR_HEIGHT,
               Color(r: 28, g: 32, b: 42, a: 255))
  
  # Draw segment dividers (only if there are multiple tiers)
  if maxTiers > 1:
    for i in 1..(maxTiers - 1):
      let segmentX: int32 = int32(x + 12 + (barWidth * i) div maxTiers)
      drawLine(segmentX, yOffset, segmentX, yOffset + PROGRESS_BAR_HEIGHT,
              Color(r: 50, g: 60, b: 75, a: 255))
  
  # Fill bar with gradient per level
  for level in 1..powerUp.level:
    let segmentStart: int32 = int32(x + 12 + (barWidth * (level - 1)) div maxTiers)
    let segmentEnd: int32 = int32(x + 12 + (barWidth * level) div maxTiers)
    let segmentWidth: int32 = segmentEnd - segmentStart
    
    let levelColor = case level
      of 1: Color(r: 80, g: 150, b: 255, a: 255)
      of 2: Color(r: 80, g: 255, b: 150, a: 255)
      else: Color(r: 255, g: 140, b: 80, a: 255)
    
    # Segment fill
    drawRectangle(segmentStart, yOffset, segmentWidth, PROGRESS_BAR_HEIGHT, levelColor)
    # Top highlight
    drawRectangle(segmentStart, yOffset, segmentWidth, 3,
                 Color(r: min(levelColor.r + 100, 255), g: min(levelColor.g + 100, 255), b: min(levelColor.b + 100, 255), a: 180))
    # Animated pulse for current level
    if level == powerUp.level and blurAmount > 0.7:
      let pulse = sin(time * 4.0) * 0.3 + 0.7
      drawRectangle(segmentStart, yOffset, segmentWidth, PROGRESS_BAR_HEIGHT,
                   Color(r: 255, g: 255, b: 255, a: uint8(40 * pulse)))
  
  # Bar border
  drawRectangleLines(Rectangle(x: (x + 12).float32, y: yOffset.float32,
                                width: barWidth.float32, height: PROGRESS_BAR_HEIGHT.float32),
                    2, Color(r: 80, g: 95, b: 115, a: 255))
  
  # Level text with better styling
  let levelText = "TIER " & $powerUp.level & " / " & $maxTiers
  let levelWidth = measureText(levelText, 12)
  # Text background
  let textBgX = x + 12 + (barWidth - levelWidth - 8) div 2
  drawRectangle(textBgX, yOffset + 3, levelWidth + 8, 16,
               Color(r: 20, g: 25, b: 35, a: 220))
  drawText(levelText, textBgX + 4, yOffset + 5, 12, White)
  yOffset += PROGRESS_BAR_HEIGHT + 18
  
  # Description section with expanded size and enhanced prominence
  let descBoxHeight: int32 = 105  # Slightly taller for better readability
  let descBoxY = yOffset
  
  # Description background box with border
  drawRectangle(x + 10, descBoxY, width - 20, descBoxHeight,
               Color(r: 18, g: 22, b: 32, a: 255))
  
  # Subtle inner glow
  drawRectangle(x + 10, descBoxY, width - 20, 2,
               Color(r: 0, g: 140, b: 200, a: 80))
  
  # Border
  drawRectangleLines(Rectangle(x: (x + 10).float32, y: descBoxY.float32,
                                width: (width - 20).float32, height: descBoxHeight.float32),
                    2, Color(r: 60, g: 80, b: 100, a: 255))
  
  # Description text (larger, more prominent)
  let desc = getPowerUpDescription(powerUp.powerType, powerUp.level)
  
  var descLines: seq[string] = @[]
  var currentLine = ""
  let maxLineWidth = width - 44  # More padding for readability
  
  for word in desc.split(' '):
    let testLine = if currentLine.len > 0: currentLine & " " & word else: word
    if measureText(testLine, 14) > maxLineWidth:
      if currentLine.len > 0:
        descLines.add(currentLine)
      currentLine = word
    else:
      currentLine = testLine
  
  if currentLine.len > 0:
    descLines.add(currentLine)
  
  # Draw description lines (top-aligned in the box, larger font, more space)
  let lineHeight = 20
  let textStartY = descBoxY + 12  # Fixed padding from top
  
  for i, line in descLines:
    if i < 4:  # Show up to 4 lines now with more space
      let lineY: int32 = textStartY.int32 + int32(i * lineHeight)
      drawText(line, x + 22, lineY, int32(14), Color(r: 220, g: 230, b: 240, a: 255))
  
  yOffset += descBoxHeight + 8  # Reduced spacing for better utilization
  
  # Bottom info - positioned right after description with minimal gap
  let bottomY = yOffset
  drawText("[P]", x + 10, bottomY, 14, Color(r: 100, g: 110, b: 120, a: 255))
  drawText(".exe", x + 30, bottomY + 2, 12, Color(r: 120, g: 130, b: 140, a: 255))
  
  let sizeText = $(128 + powerUp.level * 64) & " KB"
  let sizeWidth = measureText(sizeText, 11)
  drawText(sizeText, x + width - sizeWidth - 10, bottomY + 2, 11,
          Color(r: 110, g: 120, b: 130, a: 255))

proc drawOSPowerUpInstaller*(game: Game) =
  ## Draw the power-up selection screen with slot machine roll animation
  let screenWidth = game.screenWidth
  let screenHeight = game.screenHeight
  
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
  let windowX = (screenWidth - INSTALLER_WIDTH) div 2
  let windowY = (screenHeight - INSTALLER_HEIGHT) div 2
  
  # Window shadow
  for i in 1..4:
    let offset = i * 2
    let alpha = uint8(50 - i * 8)
    drawRectangle((windowX + offset).int32, (windowY + offset).int32,
                 INSTALLER_WIDTH, INSTALLER_HEIGHT,
                 Color(r: 0, g: 0, b: 0, a: alpha))
  
  # Window background
  drawRectangle(windowX, windowY, INSTALLER_WIDTH, INSTALLER_HEIGHT,
               Color(r: 26, g: 32, b: 44, a: 255))
  
  # Grid texture
  for i in 0..<(INSTALLER_HEIGHT div 40):
    let lineY = windowY + int32(i * 40)
    drawRectangle(windowX, lineY, INSTALLER_WIDTH, int32(1),
                 Color(r: 30, g: 36, b: 48, a: 255))
  
  # Window borders
  drawRectangleLines(Rectangle(x: windowX.float32, y: windowY.float32,
                                width: INSTALLER_WIDTH.float32, height: INSTALLER_HEIGHT.float32),
                    4, Color(r: 0, g: 180, b: 255, a: 255))
  drawRectangleLines(Rectangle(x: (windowX + 2).float32, y: (windowY + 2).float32,
                                width: (INSTALLER_WIDTH - 4).float32, height: (INSTALLER_HEIGHT - 4).float32),
                    1, Color(r: 60, g: 75, b: 95, a: 255))
  
  # Title bar
  drawRectangle(windowX, windowY, INSTALLER_WIDTH, TITLE_BAR_HEIGHT,
               Color(r: 40, g: 52, b: 70, a: 255))
  drawRectangle(windowX, windowY, INSTALLER_WIDTH, 2,
               Color(r: 80, g: 100, b: 130, a: 255))
  drawRectangle(windowX, windowY + TITLE_BAR_HEIGHT - 1, INSTALLER_WIDTH, 1,
               Color(r: 0, g: 140, b: 200, a: 255))
  
  # Title text
  let isLegendary = game.powerUpChoices[0].rarity == prLegendary
  let titleIcon = if isLegendary: "[*] " else: "[*] "
  let titleText = if isLegendary:
    titleIcon & t(tkPowerUpInstallerTitle)
  else:
    titleIcon & t(tkPowerUpInstallerTitleGeneric)
  
  let titleColor = if isLegendary: Gold else: Color(r: 100, g: 200, b: 255, a: 255)
  drawText(titleText, windowX + 17, windowY + 13, 22, Color(r: 0, g: 0, b: 0, a: 120))
  drawText(titleText, windowX + 15, windowY + 11, 22, titleColor)
  
  # Close button
  let buttonSize = 28
  let closeButtonY = windowY + int32((TITLE_BAR_HEIGHT - buttonSize) div 2)
  let closeX = windowX + INSTALLER_WIDTH - int32(buttonSize) - 10
  drawRectangle(closeX, closeButtonY, int32(buttonSize), int32(buttonSize), 
               Color(r: 220, g: 50, b: 50, a: 255))
  drawRectangleLines(Rectangle(x: closeX.float32, y: closeButtonY.float32,
                                width: buttonSize.float32, height: buttonSize.float32),
                    1, Color(r: 180, g: 30, b: 30, a: 255))
  drawText("X", closeX + 8, closeButtonY + 5, 18, White)
  
  # Instruction
  var yPos = windowY + TITLE_BAR_HEIGHT + 25
  drawText(t(tkPowerUpSelectUpgrade), windowX + 25, yPos, 17, 
          Color(r: 200, g: 220, b: 240, a: 255))
  yPos += 50
  
  # Draw cards with roll animation
  let totalCardWidth = CARD_WIDTH * 3 + CARD_SPACING * 2
  let startX = windowX + (INSTALLER_WIDTH - totalCardWidth) div 2
  
  for i in 0..2:
    let cardX = int32(startX + i * (CARD_WIDTH + CARD_SPACING))
    let cardY = yPos
    
    if game.rollAnimationActive:
      # ROLLING MODE - show scrolling list using game's animation data
      let position = game.rollPosition[i]
      let speed = game.rollSpeed[i]
      let cardHeight = CARD_HEIGHT.float32
      
      # Calculate which cards are visible based on scroll position
      let firstVisibleIndex = (position / cardHeight).int
      let offsetY = -(position mod cardHeight)
      
      # Motion blur based on speed
      let blur = if speed > 500.0: 0.3
                 elif speed > 200.0: 0.6
                 else: 1.0
      
      # ENABLE CLIPPING - constrain animation to card boundaries
      beginScissorMode(cardX, cardY, int32(CARD_WIDTH), int32(CARD_HEIGHT))
      
      # Draw multiple cards for smooth scrolling (3 visible at once)
      for j in -1..1:
        let cardIndex = firstVisibleIndex + j
        if cardIndex >= 0 and cardIndex < game.rollPowerUpList[i].len:
          let cardDrawY = int32(cardY.float32 + offsetY + j.float32 * cardHeight)
          
          # Draw card (clipping handles visibility)
          drawProcessCard(cardX, cardDrawY, int32(CARD_WIDTH), int32(CARD_HEIGHT),
                         game.rollPowerUpList[i][cardIndex],
                         i == game.selectedPowerUp,
                         game.time,
                         blur)
      
      # DISABLE CLIPPING
      endScissorMode()
    else:
      # Show final selection
      drawProcessCard(cardX, cardY, int32(CARD_WIDTH), int32(CARD_HEIGHT),
                     game.powerUpChoices[i],
                     i == game.selectedPowerUp,
                     game.time,
                     1.0)
  
  # "ROLLING..." overlay
  if game.rollAnimationActive:
    let rollingText = t(tkPowerUpRolling)
    let rollingWidth = measureText(rollingText, 32)
    let rollingX = windowX + (INSTALLER_WIDTH - rollingWidth) div 2
    let rollingY = windowY + INSTALLER_HEIGHT div 2 - 16
    
    let pulse = sin(game.time * 12.0) * 0.3 + 0.7
    drawRectangle(rollingX - 20, rollingY - 10, rollingWidth + 40, 52,
                 Color(r: 0, g: 0, b: 0, a: uint8(180 * pulse)))
    
    drawText(rollingText, rollingX + 2, rollingY + 2, 32,
            Color(r: 0, g: 0, b: 0, a: 200))
    drawText(rollingText, rollingX, rollingY, 32,
            Color(r: 255, g: 220, b: 0, a: uint8(255 * pulse)))
    
    beginScissorMode(windowX + 10, windowY + TITLE_BAR_HEIGHT + 10, 
                     INSTALLER_WIDTH - 20, INSTALLER_HEIGHT - TITLE_BAR_HEIGHT - 140)
    
    for i in 0..10:
      let sparkleAngle = game.time * 8.0 + i.float32 * 0.6
      let sparkleRadius = 120.0 + sin(game.time * 4.0 + i.float32) * 25.0
      let sparkleX = rollingX.float32 + rollingWidth.float32 / 2 + cos(sparkleAngle) * sparkleRadius
      let sparkleY = rollingY.float32 + 16 + sin(sparkleAngle) * sparkleRadius * 0.4
      let sparkleSize = 2 + (sin(game.time * 6.0 + i.float32) * 2).int32
      drawCircle(Vector2(x: sparkleX, y: sparkleY), sparkleSize.float32,
                Color(r: 255, g: 220, b: 100, a: uint8(150 * pulse)))
    
    endScissorMode()
  
  let bottomY = windowY + INSTALLER_HEIGHT - 120
  drawRectangle(windowX, bottomY - 15, INSTALLER_WIDTH, 120,
               Color(r: 30, g: 38, b: 52, a: 255))
  drawRectangle(windowX, bottomY - 15, INSTALLER_WIDTH, 2,
               Color(r: 0, g: 140, b: 200, a: 255))
  
  # COIN COUNTER - Bottom Left
  let coinBoxX = windowX + 50
  let coinBoxY = bottomY + 15
  let coinBoxWidth: int32 = 200
  let coinBoxHeight: int32 = 50
  
  # Coin counter background
  drawRectangle(coinBoxX, coinBoxY, coinBoxWidth, coinBoxHeight,
               Color(r: 40, g: 50, b: 30, a: 255))
  
  # Top highlight
  drawRectangle(coinBoxX, coinBoxY, coinBoxWidth, 2,
               Color(r: 255, g: 220, b: 0, a: 60))
  
  # Border
  drawRectangleLines(Rectangle(x: coinBoxX.float32, y: coinBoxY.float32,
                                width: coinBoxWidth.float32, height: coinBoxHeight.float32),
                    2, Color(r: 255, g: 215, b: 0, a: 200))
  
  # Coin icon (simple circle with $ symbol)
  let coinIconX = coinBoxX + 15
  let coinIconY = coinBoxY + 25
  drawCircle(Vector2(x: coinIconX.float32, y: coinIconY.float32), 12,
            Color(r: 255, g: 215, b: 0, a: 255))
  drawCircle(Vector2(x: coinIconX.float32, y: coinIconY.float32), 10,
            Color(r: 200, g: 170, b: 0, a: 255))
  drawText("$", coinIconX - 5, coinIconY - 8, 16,
          Color(r: 50, g: 40, b: 0, a: 255))
  
  # Coin amount text
  let coinText = $game.player.coins & " credits"
  drawText(coinText, coinBoxX + 40, coinBoxY + 10, 18,
          Color(r: 0, g: 0, b: 0, a: 120))
  drawText(coinText, coinBoxX + 38, coinBoxY + 8, 18,
          Color(r: 255, g: 240, b: 100, a: 255))
  
  # Small label below
  drawText("Available Balance", coinBoxX + 40, coinBoxY + 30, 10,
          Color(r: 180, g: 180, b: 150, a: 255))
  
  let buttonY = bottomY + 15
  let buttonHeight = 42
  
  let rerollWidth = 220
  let rerollX: int32 = windowX + int32((INSTALLER_WIDTH - rerollWidth) div 2)  # Center horizontally
  let canAffordReroll = game.player.coins >= game.rerollCost
  
  drawModernButton(rerollX, buttonY, int32(rerollWidth), int32(buttonHeight),
                  t(tkPowerUpRerollOptions), canAffordReroll, false, game.time)
  
  let rerollCostText = $game.rerollCost & " credits"
  let costWidth = measureText(rerollCostText, 12)
  drawText(rerollCostText, int32(rerollX + (rerollWidth - costWidth) div 2), 
          int32(buttonY + buttonHeight + 8), int32(12),
          if canAffordReroll: Color(r: 255, g: 215, b: 0, a: 255)
          else: Color(r: 120, g: 120, b: 130, a: 255))
  
  drawText("[R]", int32(rerollX + rerollWidth + 10), buttonY + int32(13), int32(14),
          Color(r: 200, g: 200, b: 200, a: 255))
