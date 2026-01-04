## Combined OS-Style HUD Panel
## Merges status and info panels into one compact, non-intrusive display

import raylib, types, math, powerup

const
  COMBINED_PANEL_WIDTH = 200
  COMBINED_PANEL_PADDING = 6
  COMBINED_SECTION_SPACING = 6
  COMBINED_ITEM_HEIGHT = 14
  COMBINED_TITLE_HEIGHT = 18
  HEADER_BG_COLOR = Color(r: 0, g: 100, b: 120, a: 60)
  ACCENT_COLOR = Color(r: 0, g: 220, b: 255, a: 255)

# State for panel minimization and dragging
var leftPanelMinimized* = false
var leftPanelPos* = Vector2(x: 10, y: 2)  # Default position
var leftPanelDragging* = false
var leftPanelDragOffset* = Vector2(x: 0, y: 0)

proc drawCombinedHUDPanel*(game: Game, x, y: int32) =
  ## Draw unified HUD panel combining status and wave/powerup info
  # Use stored position instead of parameters
  var yOffset = leftPanelPos.y.int32
  let panelX = leftPanelPos.x.int32
  
  # Handle dragging
  let mousePos = getMousePosition()
  let headerHeight = (COMBINED_PANEL_PADDING + COMBINED_TITLE_HEIGHT).float32
  let headerRect = Rectangle(
    x: panelX.float32,
    y: yOffset.float32,
    width: COMBINED_PANEL_WIDTH.float32,
    height: headerHeight
  )
  
  # Start dragging
  if isMouseButtonPressed(Left) and checkCollisionPointRec(mousePos, headerRect):
    # Check if clicking on minimize button area (right side of header)
    let minimizeButtonX = panelX + COMBINED_PANEL_WIDTH - COMBINED_PANEL_PADDING - 12
    let minimizeButtonRect = Rectangle(
      x: minimizeButtonX.float32,
      y: (yOffset + COMBINED_PANEL_PADDING).float32,
      width: 16,
      height: COMBINED_TITLE_HEIGHT.float32
    )
    
    if checkCollisionPointRec(mousePos, minimizeButtonRect):
      # Toggle minimize
      leftPanelMinimized = not leftPanelMinimized
    else:
      # Start dragging
      leftPanelDragging = true
      leftPanelDragOffset = Vector2(
        x: mousePos.x - panelX.float32,
        y: mousePos.y - yOffset.float32
      )
  
  # Update dragging
  if leftPanelDragging:
    if isMouseButtonDown(Left):
      leftPanelPos = Vector2(
        x: mousePos.x - leftPanelDragOffset.x,
        y: mousePos.y - leftPanelDragOffset.y
      )
      # Clamp to screen bounds
      leftPanelPos.x = clamp(leftPanelPos.x, 0, (game.screenWidth - COMBINED_PANEL_WIDTH).float32)
      leftPanelPos.y = clamp(leftPanelPos.y, 0, (game.screenHeight - 50).float32)
    else:
      leftPanelDragging = false
  
  # Update yOffset and panelX after potential dragging
  yOffset = leftPanelPos.y.int32
  let finalPanelX = leftPanelPos.x.int32
  
  # If minimized, only draw header bar
  if leftPanelMinimized:
    # Draw minimized panel (just header)
    drawRectangle(finalPanelX, yOffset, COMBINED_PANEL_WIDTH, COMBINED_PANEL_PADDING + COMBINED_TITLE_HEIGHT,
                 Color(r: 5, g: 15, b: 25, a: 45))
    
    # Cyan accent stripe on left edge
    drawRectangle(finalPanelX, yOffset, 2, COMBINED_PANEL_PADDING + COMBINED_TITLE_HEIGHT,
                 Color(r: 0, g: 220, b: 255, a: 180))
    
    # Panel border
    drawRectangleLines(Rectangle(x: finalPanelX.float32, y: yOffset.float32,
                                  width: COMBINED_PANEL_WIDTH.float32, 
                                  height: (COMBINED_PANEL_PADDING + COMBINED_TITLE_HEIGHT).float32),
                      1, Color(r: 0, g: 220, b: 255, a: 80))
    
    yOffset += COMBINED_PANEL_PADDING
    
    # Header with minimize indicator
    drawRectangle(finalPanelX + 2, yOffset, COMBINED_PANEL_WIDTH - 2, COMBINED_TITLE_HEIGHT,
                 HEADER_BG_COLOR)
    
    drawText("STATUS", finalPanelX + COMBINED_PANEL_PADDING + 5, yOffset + 3, 11,
            Color(r: 0, g: 0, b: 0, a: 140))
    drawText("STATUS", finalPanelX + COMBINED_PANEL_PADDING + 4, yOffset + 2, 11,
            ACCENT_COLOR)
    
    # Draw maximize icon (square)
    let iconX = finalPanelX + COMBINED_PANEL_WIDTH - COMBINED_PANEL_PADDING - 12
    let iconY = yOffset + 4
    drawRectangleLines(Rectangle(x: iconX.float32, y: iconY.float32, width: 10, height: 10),
                      1, ACCENT_COLOR)
    
    return  # Don't draw rest of panel
  
  # Calculate height based on content
  let numPowerUps = min(game.player.powerUps.len, 5)  # Limit to 5 visible
  let powerUpHeight = if numPowerUps > 0:
    COMBINED_ITEM_HEIGHT * numPowerUps + 22
  else:
    0
  
  let waveInfoHeight = if (game.mode == gmWaveBased):
    if game.waveInProgress and not game.bossWaveManager.active: 35
    elif game.bossWaveManager.active or game.bossWaveManager.coinActive: 32
    else: 28
  else:
    0
  
  let totalHeight = 82 + powerUpHeight + waveInfoHeight + (if powerUpHeight > 0: COMBINED_SECTION_SPACING else: 0)
  
  # Main panel background - more transparent and colorful
  drawRectangle(finalPanelX, yOffset, COMBINED_PANEL_WIDTH, totalHeight.int32,
               Color(r: 5, g: 15, b: 25, a: 45))
  
  # Cyan accent stripe on left edge
  drawRectangle(finalPanelX, yOffset, 2, totalHeight.int32,
               Color(r: 0, g: 220, b: 255, a: 180))
  
  # Panel border with cyan glow - more transparent
  drawRectangleLines(Rectangle(x: finalPanelX.float32, y: yOffset.float32,
                                width: COMBINED_PANEL_WIDTH.float32, height: totalHeight.float32),
                    1, Color(r: 0, g: 220, b: 255, a: 80))
  
  yOffset += COMBINED_PANEL_PADDING
  
  # ============ STATUS HEADER ============
  # Header bar background - colorful cyan (clickable to minimize)
  drawRectangle(finalPanelX + 2, yOffset, COMBINED_PANEL_WIDTH - 2, COMBINED_TITLE_HEIGHT,
               HEADER_BG_COLOR)
  
  drawText("STATUS", finalPanelX + COMBINED_PANEL_PADDING + 5, yOffset + 3, 11,
          Color(r: 0, g: 0, b: 0, a: 140))
  drawText("STATUS", finalPanelX + COMBINED_PANEL_PADDING + 4, yOffset + 2, 11,
          ACCENT_COLOR)
  
  # Draw minimize icon (horizontal line)
  let iconX = finalPanelX + COMBINED_PANEL_WIDTH - COMBINED_PANEL_PADDING - 12
  let iconY = yOffset + 9
  drawLine(Vector2(x: iconX.float32, y: iconY.float32),
          Vector2(x: (iconX + 10).float32, y: iconY.float32),
          2, ACCENT_COLOR)
  
  yOffset += COMBINED_TITLE_HEIGHT + 2
  
  # ============ HP BAR (Compact) ============
  let hpPercent = game.player.hp / game.player.maxHp
  let barWidth: int32 = COMBINED_PANEL_WIDTH - (COMBINED_PANEL_PADDING * 2)
  let barHeight: int32 = 10
  
  # HP label with shadow
  drawText("HP", finalPanelX + COMBINED_PANEL_PADDING + 1, yOffset + 1, 9, Color(r: 0, g: 0, b: 0, a: 120))
  drawText("HP", finalPanelX + COMBINED_PANEL_PADDING, yOffset, 9, Color(r: 220, g: 240, b: 255, a: 255))
  
  # HP value on right
  let hpText = $game.player.hp.int & "/" & $game.player.maxHp.int
  let hpTextWidth = measureText(hpText, 9)
  drawText(hpText, finalPanelX + COMBINED_PANEL_WIDTH - COMBINED_PANEL_PADDING - hpTextWidth + 1, yOffset + 1, 9, 
          Color(r: 0, g: 0, b: 0, a: 120))
  drawText(hpText, finalPanelX + COMBINED_PANEL_WIDTH - COMBINED_PANEL_PADDING - hpTextWidth, yOffset, 9,
          Color(r: 255, g: 255, b: 255, a: 255))
  
  yOffset += 10
  
  # HP bar background - semi-transparent
  drawRectangle(finalPanelX + COMBINED_PANEL_PADDING, yOffset, barWidth, barHeight,
               Color(r: 10, g: 20, b: 30, a: 60))
  
  # HP bar fill - vibrant colors
  let fillWidth = (barWidth.float32 * hpPercent).int32
  let barColor = if hpPercent > 0.6: Color(r: 0, g: 255, b: 120, a: 220)
                elif hpPercent > 0.3: Color(r: 255, g: 220, b: 0, a: 220)
                else: Color(r: 255, g: 80, b: 80, a: 220)
  drawRectangle(finalPanelX + COMBINED_PANEL_PADDING, yOffset, fillWidth, barHeight, barColor)
  
  # Bar border - cyan accent
  drawRectangleLines(Rectangle(x: (finalPanelX + COMBINED_PANEL_PADDING).float32, y: yOffset.float32,
                                width: barWidth.float32, height: barHeight.float32),
                    1, Color(r: 0, g: 220, b: 255, a: 120))
  
  yOffset += barHeight + 4
  
  # ============ COMPACT STATS ROW ============
  # Background box for stats - semi-transparent with cyan tint
  drawRectangle(finalPanelX + COMBINED_PANEL_PADDING + 2, yOffset - 1,
               COMBINED_PANEL_WIDTH - (COMBINED_PANEL_PADDING * 2) - 4, 12,
               Color(r: 0, g: 30, b: 40, a: 50))
  
  # Charges - bright cyan
  drawText("[#]", finalPanelX + COMBINED_PANEL_PADDING + 6, yOffset + 1, 9, Color(r: 0, g: 0, b: 0, a: 100))
  drawText("[#]", finalPanelX + COMBINED_PANEL_PADDING + 5, yOffset, 9, Color(r: 0, g: 220, b: 255, a: 255))
  let chargeText = $game.player.walls
  drawText(chargeText, finalPanelX + COMBINED_PANEL_PADDING + 17, yOffset, 10, 
          if game.player.walls > 0: Color(r: 255, g: 255, b: 255, a: 255) 
          else: Color(r: 120, g: 120, b: 120, a: 200))
  
  # Coins - bright gold
  drawText("$", finalPanelX + COMBINED_PANEL_WIDTH div 2 - 16 + 1, yOffset + 1, 9, Color(r: 0, g: 0, b: 0, a: 100))
  drawText("$", finalPanelX + COMBINED_PANEL_WIDTH div 2 - 16, yOffset, 9, Color(r: 255, g: 215, b: 0, a: 255))
  drawText($game.player.coins, finalPanelX + COMBINED_PANEL_WIDTH div 2 - 5, yOffset, 10, Color(r: 255, g: 255, b: 255, a: 255))
  
  # Processes - purple
  drawText("[*]", finalPanelX + COMBINED_PANEL_WIDTH - 40 + 1, yOffset + 1, 9, Color(r: 0, g: 0, b: 0, a: 100))
  drawText("[*]", finalPanelX + COMBINED_PANEL_WIDTH - 40, yOffset, 9, Color(r: 180, g: 100, b: 255, a: 255))
  drawText($game.player.powerUps.len, finalPanelX + COMBINED_PANEL_WIDTH - 27, yOffset, 10, Color(r: 255, g: 255, b: 255, a: 255))
  
  yOffset += 14
  
  # ============ WAVE INFO (if applicable) ============
  if (game.mode == gmWaveBased):
    # Separator line
    drawLine(Vector2(x: (finalPanelX + COMBINED_PANEL_PADDING + 3).float32, y: yOffset.float32),
            Vector2(x: (finalPanelX + COMBINED_PANEL_WIDTH - COMBINED_PANEL_PADDING - 3).float32, y: yOffset.float32),
            1, Color(r: 0, g: 200, b: 255, a: 100))
    yOffset += 3
    
    # Wave header - compact
    drawText("Wave Info:", finalPanelX + COMBINED_PANEL_PADDING + 6, yOffset + 1, 9,
            Color(r: 0, g: 0, b: 0, a: 100))
    drawText("Wave Info:", finalPanelX + COMBINED_PANEL_PADDING + 5, yOffset, 9,
            Color(r: 150, g: 150, b: 150, a: 255))
    yOffset += 10
    
    # Wave display - compact
    let waveDisplay = if game.bossWaveManager.active:
      "[!] BOSS W" & $game.currentWave
    else:
      "> Wave " & $game.currentWave
    
    let waveColor = if game.bossWaveManager.active:
      Color(r: 255, g: 80, b: 80, a: 255)
    else:
      Color(r: 120, g: 255, b: 120, a: 255)
    
    drawText(waveDisplay, finalPanelX + COMBINED_PANEL_PADDING + 8, yOffset + 1, 11,
            Color(r: 0, g: 0, b: 0, a: 130))
    drawText(waveDisplay, finalPanelX + COMBINED_PANEL_PADDING + 7, yOffset, 11, waveColor)
    yOffset += 13
    
    # Enemy Counter (single bar that empties as enemies are killed)
    if game.waveInProgress and not game.bossWaveManager.active:
      let currentEnemies = game.enemies.len  # Enemies currently on screen
      let toSpawn = game.waveEnemiesRemaining  # Enemies yet to spawn
      let totalRemaining = currentEnemies + toSpawn
      
      # Threat level colors based on remaining percentage
      let remainingPercent = totalRemaining.float32 / game.waveEnemiesTotal.float32
      let threatColor = if remainingPercent > 0.6:
        Color(r: 255, g: 50, b: 50, a: 255)
      elif remainingPercent > 0.3:
        Color(r: 255, g: 165, b: 0, a: 255)
      else:
        Color(r: 100, g: 220, b: 120, a: 255)
      
      # Warning icon with pulse for high threat
      let iconPulse = if remainingPercent > 0.5: sin(game.time * 8.0) * 0.3 + 0.7 else: 1.0
      let pulseColor = Color(
        r: uint8(threatColor.r.float32 * iconPulse),
        g: uint8(threatColor.g.float32 * iconPulse),
        b: uint8(threatColor.b.float32 * iconPulse),
        a: 255
      )
      
      drawText("[!]", finalPanelX + COMBINED_PANEL_PADDING + 8, yOffset + 1, 14,
              Color(r: 0, g: 0, b: 0, a: 130))
      drawText("[!]", finalPanelX + COMBINED_PANEL_PADDING + 7, yOffset, 14, pulseColor)
      
      # Enemy count display
      let countText = $totalRemaining & " left"
      let countWidth = measureText(countText, 12)
      let countX = finalPanelX + COMBINED_PANEL_WIDTH - COMBINED_PANEL_PADDING - countWidth - 5
      
      drawText(countText, countX + 1, yOffset + 2, 12, Color(r: 0, g: 0, b: 0, a: 130))
      drawText(countText, countX, yOffset + 1, 12, threatColor)
      
      yOffset += 14
      
      # Single bar that empties as enemies are killed
      let barWidth: int32 = COMBINED_PANEL_WIDTH - (COMBINED_PANEL_PADDING * 2)
      let barFillPercent = totalRemaining.float32 / game.waveEnemiesTotal.float32
      
      # Bar background (empty state)
      drawRectangle(finalPanelX + COMBINED_PANEL_PADDING, yOffset, barWidth, 6,
                   Color(r: 15, g: 20, b: 25, a: 120))
      
      # Bar fill (remaining enemies - starts full, decreases as you kill)
      let fillWidth = (barWidth.float32 * barFillPercent).int32
      drawRectangle(finalPanelX + COMBINED_PANEL_PADDING, yOffset, fillWidth, 6, threatColor)
      
      # Border
      drawRectangleLines(Rectangle(
        x: (finalPanelX + COMBINED_PANEL_PADDING).float32,
        y: yOffset.float32,
        width: barWidth.float32,
        height: 6.0
      ), 1, Color(r: 0, g: 200, b: 255, a: 140))
      
      yOffset += 8
    
    if game.bossWaveManager.active:
      drawText("[X] BOSS FIGHT", finalPanelX + COMBINED_PANEL_PADDING + 8, yOffset + 1, 10,
              Color(r: 0, g: 0, b: 0, a: 130))
      drawText("[X] BOSS FIGHT", finalPanelX + COMBINED_PANEL_PADDING + 7, yOffset, 10,
              Color(r: 255, g: 100, b: 100, a: 255))
      yOffset += 12
    
    elif game.bossWaveManager.coinActive:
      let pulseAlpha = (sin(game.time * 4.0) * 60 + 195).int.uint8
      drawText("[$] Collect", finalPanelX + COMBINED_PANEL_PADDING + 8, yOffset + 1, 10,
              Color(r: 0, g: 0, b: 0, a: 130))
      drawText("[$] Collect", finalPanelX + COMBINED_PANEL_PADDING + 7, yOffset, 10,
              Color(r: 255, g: 215, b: 0, a: pulseAlpha))
      yOffset += 12
  
  # ============ ACTIVE POWER-UPS (Compact List) ============
  if game.player.powerUps.len > 0:
    # Separator line
    drawLine(Vector2(x: (finalPanelX + COMBINED_PANEL_PADDING + 3).float32, y: yOffset.float32),
            Vector2(x: (finalPanelX + COMBINED_PANEL_WIDTH - COMBINED_PANEL_PADDING - 3).float32, y: yOffset.float32),
            1, Color(r: 0, g: 200, b: 255, a: 100))
    yOffset += 3
    
    # "Active Processes" header - compact
    let processCount = game.player.powerUps.len
    let processHeader = "Active [" & $processCount & "]:"
    drawText(processHeader, finalPanelX + COMBINED_PANEL_PADDING + 6, yOffset + 1, 9,
            Color(r: 0, g: 0, b: 0, a: 100))
    drawText(processHeader, finalPanelX + COMBINED_PANEL_PADDING + 5, yOffset, 9,
            Color(r: 200, g: 220, b: 240, a: 255))
    yOffset += 10
    
    # List power-ups (limit to 5) - with alternating backgrounds like debug panel
    for i in 0..<min(numPowerUps, 5):
      let powerUp = game.player.powerUps[i]
      
      # Alternating row background
      let rowBg = if i mod 2 == 0:
        Color(r: 18, g: 25, b: 35, a: 70)
      else:
        Color(r: 12, g: 18, b: 28, a: 50)
      
      drawRectangle(finalPanelX + COMBINED_PANEL_PADDING + 3, yOffset - 1,
                   COMBINED_PANEL_WIDTH - (COMBINED_PANEL_PADDING * 2) - 6, COMBINED_ITEM_HEIGHT,
                   rowBg)
      
      # Mini colored indicator
      let iconColor = if powerUp.rarity == prLegendary:
        Color(r: 255, g: 215, b: 0, a: 200)
      else:
        Color(r: 80, g: 140, b: 255, a: 200)
      
      drawRectangle(finalPanelX + COMBINED_PANEL_PADDING + 8, yOffset + 2, 10, 10, iconColor)
      drawRectangleLines(Rectangle(x: (finalPanelX + COMBINED_PANEL_PADDING + 8).float32, y: (yOffset + 2).float32,
                                    width: 10.0, height: 10.0),
                        1, Color(r: 255, g: 255, b: 255, a: 100))
      
      # Power-up name (shortened)
      let processName = getPowerUpName(powerUp.powerType)
      var displayName = processName
      let maxWidth = 140
      while measureText(displayName, 9) > maxWidth and displayName.len > 3:
        displayName = displayName[0..^2]
      if displayName.len < processName.len:
        displayName = displayName[0..^2] & ".."
      
      drawText(displayName, finalPanelX + COMBINED_PANEL_PADDING + 22, yOffset + 3, 9,
              Color(r: 230, g: 230, b: 230, a: 255))
      
      # Level indicator
      let levelText = "L" & $powerUp.level
      let levelWidth = measureText(levelText, 8)
      drawText(levelText, finalPanelX + COMBINED_PANEL_WIDTH - COMBINED_PANEL_PADDING - levelWidth - 5,
              yOffset + 4, 8, Color(r: 140, g: 140, b: 140, a: 255))
      
      yOffset += COMBINED_ITEM_HEIGHT
    
    # Show "+X more" if there are more than 5
    if game.player.powerUps.len > 5:
      let moreText = "+" & $(game.player.powerUps.len - 5) & " more"
      
      drawRectangle(finalPanelX + COMBINED_PANEL_PADDING + 3, yOffset - 1,
                   COMBINED_PANEL_WIDTH - (COMBINED_PANEL_PADDING * 2) - 6, 12,
                   Color(r: 20, g: 25, b: 35, a: 100))
      
      drawText(moreText, finalPanelX + COMBINED_PANEL_PADDING + 8, yOffset + 1, 8,
              Color(r: 0, g: 0, b: 0, a: 100))
      drawText(moreText, finalPanelX + COMBINED_PANEL_PADDING + 7, yOffset, 8,
              Color(r: 120, g: 120, b: 120, a: 255))
