## OS-Style Debug Panel
## System diagnostics and performance metrics

import raylib, types, strutils, powerup

const
  DEBUG_PANEL_WIDTH = 200
  DEBUG_PANEL_PADDING = 6
  DEBUG_PANEL_BORDER = 1
  DEBUG_SECTION_SPACING = 6
  DEBUG_TITLE_HEIGHT = 18
  DEBUG_LINE_HEIGHT = 14
  HEADER_BG_COLOR = Color(r: 0, g: 100, b: 120, a: 60)
  ACCENT_COLOR = Color(r: 0, g: 220, b: 255, a: 255)

# State for panel minimization and dragging
var debugPanelMinimized* = false
var debugPanelPos* = Vector2(x: -1, y: 2)  # Default position (-1 means aligned to right edge)
var debugPanelDragging* = false
var debugPanelDragOffset* = Vector2(x: 0, y: 0)

## Calculate basic combat stats for display
## This is a simplified version - the full calculation is in game.nim
proc getDisplayStats(player: Player): tuple[damage: float32, fireRate: float32, speed: float32] =
  result.damage = player.damage
  result.fireRate = player.fireRate  
  result.speed = player.speed
  
  # Apply simple modifiers for display
  # Fire rate boost
  if player.fireRateBoostTimer > 0:
    result.fireRate *= 0.6
  
  # Rage damage bonus
  if hasPowerUp(player, puRage):
    let hpPercent = player.hp / player.maxHp
    let hpLost = 1.0 - hpPercent
    let rageLevel = getPowerUpLevel(player, puRage)
    let bonusPerTenPercent = case rageLevel
      of 1: 0.05
      of 2: 0.08
      else: 0.12
    result.damage *= (1.0 + (hpLost * 10.0 * bonusPerTenPercent))
  
  # Berserker fire rate bonus
  if hasPowerUp(player, puBerserker):
    let hpPercent = player.hp / player.maxHp
    let hpLost = 1.0 - hpPercent
    let berserkLevel = getPowerUpLevel(player, puBerserker)
    let bonusPerTenPercent = case berserkLevel
      of 1: 0.05
      of 2: 0.08
      else: 0.15
    let fireRateBonus = 1.0 + (hpLost * 10.0 * bonusPerTenPercent)
    result.fireRate *= (1.0 / fireRateBonus)

proc drawDebugPanel*(game: Game, x, y: int32) =
  ## Draw comprehensive debug and diagnostics panel
  # Use stored position - if x is -1, align to right edge
  let actualX = if debugPanelPos.x < 0:
    game.screenWidth.float32 - DEBUG_PANEL_WIDTH.float32
  else:
    debugPanelPos.x
  
  var yOffset = debugPanelPos.y.int32
  var finalPanelX = actualX.int32
  
  # Handle dragging
  let mousePos = getMousePosition()
  let headerHeight = (DEBUG_PANEL_PADDING + DEBUG_TITLE_HEIGHT).float32
  let headerRect = Rectangle(
    x: finalPanelX.float32,
    y: yOffset.float32,
    width: DEBUG_PANEL_WIDTH.float32,
    height: headerHeight
  )
  
  # Start dragging or minimize
  if isMouseButtonPressed(Left) and checkCollisionPointRec(mousePos, headerRect):
    # Check if clicking on minimize button area (right side of header)
    let minimizeButtonX = finalPanelX + DEBUG_PANEL_WIDTH - DEBUG_PANEL_PADDING - 12
    let minimizeButtonRect = Rectangle(
      x: minimizeButtonX.float32,
      y: (yOffset + DEBUG_PANEL_PADDING).float32,
      width: 16,
      height: DEBUG_TITLE_HEIGHT.float32
    )
    
    if checkCollisionPointRec(mousePos, minimizeButtonRect):
      # Toggle minimize
      debugPanelMinimized = not debugPanelMinimized
    else:
      # Start dragging
      debugPanelDragging = true
      debugPanelDragOffset = Vector2(
        x: mousePos.x - finalPanelX.float32,
        y: mousePos.y - yOffset.float32
      )
  
  # Update dragging
  if debugPanelDragging:
    if isMouseButtonDown(Left):
      debugPanelPos = Vector2(
        x: mousePos.x - debugPanelDragOffset.x,
        y: mousePos.y - debugPanelDragOffset.y
      )
      # Clamp to screen bounds
      debugPanelPos.x = clamp(debugPanelPos.x, 0, (game.screenWidth - DEBUG_PANEL_WIDTH).float32)
      debugPanelPos.y = clamp(debugPanelPos.y, 0, (game.screenHeight - 50).float32)
    else:
      debugPanelDragging = false
  
  # Update positions after potential dragging
  yOffset = debugPanelPos.y.int32
  finalPanelX = if debugPanelPos.x < 0:
    (game.screenWidth - DEBUG_PANEL_WIDTH)
  else:
    debugPanelPos.x.int32
  
  # If minimized, only draw header bar
  if debugPanelMinimized:
    # Draw minimized panel (just header)
    drawRectangle(finalPanelX, yOffset, DEBUG_PANEL_WIDTH, DEBUG_PANEL_PADDING + DEBUG_TITLE_HEIGHT,
                 Color(r: 5, g: 15, b: 25, a: 45))
    
    # Cyan accent stripe on right edge
    drawRectangle(finalPanelX + DEBUG_PANEL_WIDTH - 2, yOffset, 2, DEBUG_PANEL_PADDING + DEBUG_TITLE_HEIGHT,
                 Color(r: 0, g: 220, b: 255, a: 180))
    
    # Panel border
    drawRectangleLines(Rectangle(x: finalPanelX.float32, y: yOffset.float32,
                                  width: DEBUG_PANEL_WIDTH.float32,
                                  height: (DEBUG_PANEL_PADDING + DEBUG_TITLE_HEIGHT).float32),
                      DEBUG_PANEL_BORDER, Color(r: 0, g: 220, b: 255, a: 80))
    
    yOffset += DEBUG_PANEL_PADDING
    
    # Header with minimize indicator
    drawRectangle(finalPanelX, yOffset, DEBUG_PANEL_WIDTH - 2, DEBUG_TITLE_HEIGHT, HEADER_BG_COLOR)
    
    drawText("DIAGNOSTICS", finalPanelX + DEBUG_PANEL_PADDING + 5, yOffset + 3, 11,
            Color(r: 0, g: 0, b: 0, a: 140))
    drawText("DIAGNOSTICS", finalPanelX + DEBUG_PANEL_PADDING + 4, yOffset + 2, 11, ACCENT_COLOR)
    
    # Draw maximize icon (square)
    let iconX = finalPanelX + DEBUG_PANEL_WIDTH - DEBUG_PANEL_PADDING - 12
    let iconY = yOffset + 4
    drawRectangleLines(Rectangle(x: iconX.float32, y: iconY.float32, width: 10, height: 10),
                      1, ACCENT_COLOR)
    
    return  # Don't draw rest of panel
  
  # Calculate panel height based on content - FIXED: removed base height calculation
  var contentHeight: int32 = DEBUG_PANEL_PADDING * 2 + DEBUG_TITLE_HEIGHT + 4  # Header
  
  # FPS/Entity row
  contentHeight += 26
  
  # Add height for active timers
  var activeTimers = 0
  if game.player.speedBoostTimer > 0: activeTimers += 1
  if game.player.invincibilityTimer > 0: activeTimers += 1
  if game.player.fireRateBoostTimer > 0: activeTimers += 1
  if game.player.magnetTimer > 0: activeTimers += 1
  if game.player.timeWarpActive: activeTimers += 1
  if game.player.phaseShiftInvulnTimer > 0: activeTimers += 1
  if game.player.parryActive: activeTimers += 1
  
  if activeTimers > 0:
    contentHeight += int32(18 + (activeTimers * DEBUG_LINE_HEIGHT) + DEBUG_SECTION_SPACING)
  
  # Always show combat stats (FIXED: always add this)
  contentHeight += int32(18 + (DEBUG_LINE_HEIGHT * 3) + 8 + DEBUG_SECTION_SPACING)
  
  # Add height for rage/berserker bonuses if applicable
  let hpPercent = game.player.hp / game.player.maxHp
  if hpPercent < 0.7 and (hasPowerUp(game.player, puRage) or hasPowerUp(game.player, puBerserker)):
    var bonusCount = 0
    if hasPowerUp(game.player, puRage): bonusCount += 1
    if hasPowerUp(game.player, puBerserker): bonusCount += 1
    contentHeight += int32(18 + (bonusCount * DEBUG_LINE_HEIGHT) + 8)
  
  # Main panel background with gradient effect (matching other panels)
  drawRectangle(finalPanelX, yOffset, DEBUG_PANEL_WIDTH, contentHeight,
               Color(r: 5, g: 15, b: 25, a: 45))
  
  # Cyan accent stripe on right edge
  drawRectangle(finalPanelX + DEBUG_PANEL_WIDTH - 2, yOffset, 2, contentHeight,
               Color(r: 0, g: 220, b: 255, a: 180))
  
  # Panel border with glow effect (cyan theme matching other panels)
  drawRectangleLines(Rectangle(x: finalPanelX.float32, y: yOffset.float32,
                                width: DEBUG_PANEL_WIDTH.float32, height: contentHeight.float32),
                    DEBUG_PANEL_BORDER, Color(r: 0, g: 220, b: 255, a: 80))
  
  yOffset += DEBUG_PANEL_PADDING
  
  # ============ SYSTEM DIAGNOSTICS HEADER ============
  # Header bar background - colorful cyan (clickable to minimize)
  drawRectangle(finalPanelX, yOffset, DEBUG_PANEL_WIDTH - 2, DEBUG_TITLE_HEIGHT, HEADER_BG_COLOR)
  
  drawText("DIAGNOSTICS", finalPanelX + DEBUG_PANEL_PADDING + 5, yOffset + 3, 11,
          Color(r: 0, g: 0, b: 0, a: 140))
  drawText("DIAGNOSTICS", finalPanelX + DEBUG_PANEL_PADDING + 4, yOffset + 2, 11, ACCENT_COLOR)
  
  # Draw minimize icon (horizontal line)
  let iconX = finalPanelX + DEBUG_PANEL_WIDTH - DEBUG_PANEL_PADDING - 12
  let iconY = yOffset + 9
  drawLine(Vector2(x: iconX.float32, y: iconY.float32),
          Vector2(x: (iconX + 10).float32, y: iconY.float32),
          2, ACCENT_COLOR)
  
  yOffset += DEBUG_TITLE_HEIGHT + 2
  
  # FPS and entity count in compact single line
  let statsSectionWidth: int32 = DEBUG_PANEL_WIDTH - (DEBUG_PANEL_PADDING * 2) - 4
  drawRectangle(finalPanelX + DEBUG_PANEL_PADDING + 2, yOffset - 1, statsSectionWidth, 16,
               Color(r: 0, g: 30, b: 40, a: 50))
  
  # FPS display - green when good, yellow/red when bad
  let fps = getFPS()
  let fpsColor = if fps >= 55:
    Color(r: 0, g: 255, b: 120, a: 255)
  elif fps >= 30:
    Color(r: 255, g: 220, b: 100, a: 255)
  else:
    Color(r: 255, g: 100, b: 100, a: 255)
  
  drawText("FPS:", finalPanelX + DEBUG_PANEL_PADDING + 6, yOffset + 1, 9,
          Color(r: 0, g: 0, b: 0, a: 130))
  drawText("FPS:", finalPanelX + DEBUG_PANEL_PADDING + 5, yOffset, 9,
          Color(r: 180, g: 200, b: 220, a: 255))
  
  drawText($fps, finalPanelX + DEBUG_PANEL_PADDING + 32, yOffset + 1, 11,
          Color(r: 0, g: 0, b: 0, a: 150))
  drawText($fps, finalPanelX + DEBUG_PANEL_PADDING + 31, yOffset, 11, fpsColor)
  
  # Entity count - purple color
  let totalEntities = game.enemies.len + game.bullets.len + game.particles.len
  let entityX = finalPanelX + DEBUG_PANEL_WIDTH div 2 + 2
  
  drawText("Ent:", entityX + 1, yOffset + 1, 9,
          Color(r: 0, g: 0, b: 0, a: 130))
  drawText("Ent:", entityX, yOffset, 9,
          Color(r: 180, g: 200, b: 220, a: 255))
  
  drawText($totalEntities, entityX + 28, yOffset + 1, 11,
          Color(r: 0, g: 0, b: 0, a: 150))
  drawText($totalEntities, entityX + 27, yOffset, 11,
          Color(r: 180, g: 100, b: 255, a: 255))
  
  yOffset += 18
  
  # ============ ACTIVE EFFECTS SECTION ============
  if activeTimers > 0:
    # Section separator line - cyan
    drawLine(Vector2(x: (finalPanelX + DEBUG_PANEL_PADDING + 2).float32, y: yOffset.float32),
            Vector2(x: (finalPanelX + DEBUG_PANEL_WIDTH - DEBUG_PANEL_PADDING - 2).float32, y: yOffset.float32),
            1, Color(r: 0, g: 220, b: 255, a: 120))
    yOffset += 3
    
    drawText("Active Effects:", finalPanelX + DEBUG_PANEL_PADDING + 5, yOffset + 1, 9,
            Color(r: 0, g: 0, b: 0, a: 130))
    drawText("Active Effects:", finalPanelX + DEBUG_PANEL_PADDING + 4, yOffset, 9,
            Color(r: 200, g: 220, b: 240, a: 255))
    yOffset += 12
    
    # Speed boost - cyan color
    if game.player.speedBoostTimer > 0:
      drawRectangle(finalPanelX + DEBUG_PANEL_PADDING + 2, yOffset - 1,
                   DEBUG_PANEL_WIDTH - (DEBUG_PANEL_PADDING * 2) - 4, DEBUG_LINE_HEIGHT,
                   Color(r: 0, g: 30, b: 40, a: 50))
      
      let timeLeft = game.player.speedBoostTimer.int + 1
      drawText("⚡ Speed", finalPanelX + DEBUG_PANEL_PADDING + 6, yOffset + 1, 10,
              Color(r: 0, g: 0, b: 0, a: 140))
      drawText("⚡ Speed", finalPanelX + DEBUG_PANEL_PADDING + 5, yOffset, 10,
              Color(r: 100, g: 220, b: 255, a: 255))
      
      drawText($timeLeft & "s", finalPanelX + DEBUG_PANEL_WIDTH - DEBUG_PANEL_PADDING - 24,
              yOffset + 1, 9, Color(r: 0, g: 0, b: 0, a: 140))
      drawText($timeLeft & "s", finalPanelX + DEBUG_PANEL_WIDTH - DEBUG_PANEL_PADDING - 25,
              yOffset, 9, Color(r: 180, g: 200, b: 220, a: 255))
      yOffset += DEBUG_LINE_HEIGHT
    
    # Invincibility - magenta color
    if game.player.invincibilityTimer > 0:
      drawRectangle(finalPanelX + DEBUG_PANEL_PADDING + 2, yOffset - 1,
                   DEBUG_PANEL_WIDTH - (DEBUG_PANEL_PADDING * 2) - 4, DEBUG_LINE_HEIGHT,
                   Color(r: 30, g: 0, b: 30, a: 50))
      
      let timeLeft = game.player.invincibilityTimer.int + 1
      drawText("🛡 Invuln", finalPanelX + DEBUG_PANEL_PADDING + 6, yOffset + 1, 10,
              Color(r: 0, g: 0, b: 0, a: 140))
      drawText("🛡 Invuln", finalPanelX + DEBUG_PANEL_PADDING + 5, yOffset, 10,
              Color(r: 255, g: 100, b: 255, a: 255))
      
      drawText($timeLeft & "s", finalPanelX + DEBUG_PANEL_WIDTH - DEBUG_PANEL_PADDING - 24,
              yOffset + 1, 9, Color(r: 0, g: 0, b: 0, a: 140))
      drawText($timeLeft & "s", finalPanelX + DEBUG_PANEL_WIDTH - DEBUG_PANEL_PADDING - 25,
              yOffset, 9, Color(r: 180, g: 200, b: 220, a: 255))
      yOffset += DEBUG_LINE_HEIGHT
    
    # Fire rate boost - orange color
    if game.player.fireRateBoostTimer > 0:
      drawRectangle(finalPanelX + DEBUG_PANEL_PADDING + 2, yOffset - 1,
                   DEBUG_PANEL_WIDTH - (DEBUG_PANEL_PADDING * 2) - 4, DEBUG_LINE_HEIGHT,
                   Color(r: 30, g: 20, b: 0, a: 50))
      
      let timeLeft = game.player.fireRateBoostTimer.int + 1
      drawText("🔥 Fire", finalPanelX + DEBUG_PANEL_PADDING + 6, yOffset + 1, 10,
              Color(r: 0, g: 0, b: 0, a: 140))
      drawText("🔥 Fire", finalPanelX + DEBUG_PANEL_PADDING + 5, yOffset, 10,
              Color(r: 255, g: 150, b: 50, a: 255))
      
      drawText($timeLeft & "s", finalPanelX + DEBUG_PANEL_WIDTH - DEBUG_PANEL_PADDING - 24,
              yOffset + 1, 9, Color(r: 0, g: 0, b: 0, a: 140))
      drawText($timeLeft & "s", finalPanelX + DEBUG_PANEL_WIDTH - DEBUG_PANEL_PADDING - 25,
              yOffset, 9, Color(r: 180, g: 200, b: 220, a: 255))
      yOffset += DEBUG_LINE_HEIGHT
    
    # Magnet
    if game.player.magnetTimer > 0:
      drawRectangle(finalPanelX + DEBUG_PANEL_PADDING + 3, yOffset - 1,
                   DEBUG_PANEL_WIDTH - (DEBUG_PANEL_PADDING * 2) - 6, DEBUG_LINE_HEIGHT,
                   Color(r: 12, g: 18, b: 28, a: 50))
      
      let timeLeft = game.player.magnetTimer.int + 1
      drawText("🧲 Magnet", finalPanelX + DEBUG_PANEL_PADDING + 8, yOffset + 1, 11,
              Color(r: 0, g: 0, b: 0, a: 140))
      drawText("🧲 Magnet", finalPanelX + DEBUG_PANEL_PADDING + 7, yOffset, 11,
              Color(r: 200, g: 100, b: 255, a: 255))
      
      drawText($timeLeft & "s", finalPanelX + DEBUG_PANEL_WIDTH - DEBUG_PANEL_PADDING - 30,
              yOffset + 1, 10, Color(r: 0, g: 0, b: 0, a: 140))
      drawText($timeLeft & "s", finalPanelX + DEBUG_PANEL_WIDTH - DEBUG_PANEL_PADDING - 31,
              yOffset, 10, Color(r: 180, g: 200, b: 220, a: 255))
      yOffset += DEBUG_LINE_HEIGHT
    
    # Time Warp
    if game.player.timeWarpActive:
      drawRectangle(finalPanelX + DEBUG_PANEL_PADDING + 3, yOffset - 1,
                   DEBUG_PANEL_WIDTH - (DEBUG_PANEL_PADDING * 2) - 6, DEBUG_LINE_HEIGHT,
                   Color(r: 18, g: 25, b: 35, a: 70))
      
      let timeLeft = game.player.timeWarpDuration.int + 1
      drawText("⏱ Time Warp", finalPanelX + DEBUG_PANEL_PADDING + 8, yOffset + 1, 11,
              Color(r: 0, g: 0, b: 0, a: 140))
      drawText("⏱ Time Warp", finalPanelX + DEBUG_PANEL_PADDING + 7, yOffset, 11,
              Color(r: 100, g: 255, b: 255, a: 255))
      
      drawText($timeLeft & "s", finalPanelX + DEBUG_PANEL_WIDTH - DEBUG_PANEL_PADDING - 30,
              yOffset + 1, 10, Color(r: 0, g: 0, b: 0, a: 140))
      drawText($timeLeft & "s", finalPanelX + DEBUG_PANEL_WIDTH - DEBUG_PANEL_PADDING - 31,
              yOffset, 10, Color(r: 180, g: 200, b: 220, a: 255))
      yOffset += DEBUG_LINE_HEIGHT
    
    # Phase Shift invulnerability
    if game.player.phaseShiftInvulnTimer > 0:
      drawRectangle(finalPanelX + DEBUG_PANEL_PADDING + 3, yOffset - 1,
                   DEBUG_PANEL_WIDTH - (DEBUG_PANEL_PADDING * 2) - 6, DEBUG_LINE_HEIGHT,
                   Color(r: 12, g: 18, b: 28, a: 50))
      
      drawText("👻 Phase", finalPanelX + DEBUG_PANEL_PADDING + 8, yOffset + 1, 11,
              Color(r: 0, g: 0, b: 0, a: 140))
      drawText("👻 Phase", finalPanelX + DEBUG_PANEL_PADDING + 7, yOffset, 11,
              Color(r: 150, g: 255, b: 200, a: 255))
      
      drawText("Active", finalPanelX + DEBUG_PANEL_WIDTH - DEBUG_PANEL_PADDING - 40,
              yOffset + 1, 10, Color(r: 0, g: 0, b: 0, a: 140))
      drawText("Active", finalPanelX + DEBUG_PANEL_WIDTH - DEBUG_PANEL_PADDING - 41,
              yOffset, 10, Color(r: 180, g: 200, b: 220, a: 255))
      yOffset += DEBUG_LINE_HEIGHT
    
    # Parry
    if game.player.parryActive:
      drawRectangle(finalPanelX + DEBUG_PANEL_PADDING + 3, yOffset - 1,
                   DEBUG_PANEL_WIDTH - (DEBUG_PANEL_PADDING * 2) - 6, DEBUG_LINE_HEIGHT,
                   Color(r: 18, g: 25, b: 35, a: 70))
      
      drawText("⚔ Parry", finalPanelX + DEBUG_PANEL_PADDING + 8, yOffset + 1, 11,
              Color(r: 0, g: 0, b: 0, a: 140))
      drawText("⚔ Parry", finalPanelX + DEBUG_PANEL_PADDING + 7, yOffset, 11,
              Color(r: 255, g: 255, b: 100, a: 255))
      
      drawText("Active", finalPanelX + DEBUG_PANEL_WIDTH - DEBUG_PANEL_PADDING - 40,
              yOffset + 1, 10, Color(r: 0, g: 0, b: 0, a: 140))
      drawText("Active", finalPanelX + DEBUG_PANEL_WIDTH - DEBUG_PANEL_PADDING - 41,
              yOffset, 10, Color(r: 180, g: 200, b: 220, a: 255))
      yOffset += DEBUG_LINE_HEIGHT
    
    yOffset += DEBUG_SECTION_SPACING
  
  # ============ COMBAT STATS SECTION ============
  # Section separator line
  drawLine(Vector2(x: (finalPanelX + DEBUG_PANEL_PADDING + 3).float32, y: yOffset.float32),
          Vector2(x: (finalPanelX + DEBUG_PANEL_WIDTH - DEBUG_PANEL_PADDING - 3).float32, y: yOffset.float32),
          1, Color(r: 0, g: 200, b: 255, a: 100))
  yOffset += 4
  
  drawText("Combat Stats:", finalPanelX + DEBUG_PANEL_PADDING + 6, yOffset + 1, 10,
          Color(r: 0, g: 0, b: 0, a: 130))
  drawText("Combat Stats:", finalPanelX + DEBUG_PANEL_PADDING + 5, yOffset, 10,
          Color(r: 200, g: 220, b: 240, a: 255))
  yOffset += 14
  
  let stats = getDisplayStats(game.player)
  
  # Stats background box (compact)
  drawRectangle(finalPanelX + DEBUG_PANEL_PADDING + 3, yOffset - 1,
               DEBUG_PANEL_WIDTH - (DEBUG_PANEL_PADDING * 2) - 6, DEBUG_LINE_HEIGHT * 3 + 2,
               Color(r: 15, g: 20, b: 28, a: 70))
  
  # Damage
  let damageText = formatFloat(stats.damage, ffDecimal, 2)
  drawText("Damage:", finalPanelX + DEBUG_PANEL_PADDING + 8, yOffset + 1, 10,
          Color(r: 0, g: 0, b: 0, a: 130))
  drawText("Damage:", finalPanelX + DEBUG_PANEL_PADDING + 7, yOffset, 10,
          Color(r: 180, g: 200, b: 220, a: 255))
  
  drawText(damageText, finalPanelX + DEBUG_PANEL_WIDTH - DEBUG_PANEL_PADDING - 46,
          yOffset + 1, 11, Color(r: 0, g: 0, b: 0, a: 150))
  drawText(damageText, finalPanelX + DEBUG_PANEL_WIDTH - DEBUG_PANEL_PADDING - 47,
          yOffset, 11, Color(r: 255, g: 150, b: 100, a: 255))
  yOffset += DEBUG_LINE_HEIGHT
  
  # Fire rate (shots per second)
  let shotsPerSec = 1.0 / stats.fireRate
  let fireRateText = formatFloat(shotsPerSec, ffDecimal, 2) & "/s"
  drawText("Fire Rate:", finalPanelX + DEBUG_PANEL_PADDING + 8, yOffset + 1, 10,
          Color(r: 0, g: 0, b: 0, a: 130))
  drawText("Fire Rate:", finalPanelX + DEBUG_PANEL_PADDING + 7, yOffset, 10,
          Color(r: 180, g: 200, b: 220, a: 255))
  
  drawText(fireRateText, finalPanelX + DEBUG_PANEL_WIDTH - DEBUG_PANEL_PADDING - 46,
          yOffset + 1, 11, Color(r: 0, g: 0, b: 0, a: 150))
  drawText(fireRateText, finalPanelX + DEBUG_PANEL_WIDTH - DEBUG_PANEL_PADDING - 47,
          yOffset, 11, Color(r: 255, g: 200, b: 100, a: 255))
  yOffset += DEBUG_LINE_HEIGHT
  
  # Speed
  let speedText = formatFloat(stats.speed, ffDecimal, 2)
  drawText("Speed:", finalPanelX + DEBUG_PANEL_PADDING + 8, yOffset + 1, 10,
          Color(r: 0, g: 0, b: 0, a: 130))
  drawText("Speed:", finalPanelX + DEBUG_PANEL_PADDING + 7, yOffset, 10,
          Color(r: 180, g: 200, b: 220, a: 255))
  
  drawText(speedText, finalPanelX + DEBUG_PANEL_WIDTH - DEBUG_PANEL_PADDING - 46,
          yOffset + 1, 11, Color(r: 0, g: 0, b: 0, a: 150))
  drawText(speedText, finalPanelX + DEBUG_PANEL_WIDTH - DEBUG_PANEL_PADDING - 47,
          yOffset, 11, Color(r: 100, g: 200, b: 255, a: 255))
  yOffset += DEBUG_LINE_HEIGHT + 6
  
  # ============ LOW HP BONUSES SECTION ============
  if hpPercent < 0.7 and (hasPowerUp(game.player, puRage) or hasPowerUp(game.player, puBerserker)):
    # Section separator line
    drawLine(Vector2(x: (finalPanelX + DEBUG_PANEL_PADDING + 3).float32, y: yOffset.float32),
            Vector2(x: (finalPanelX + DEBUG_PANEL_WIDTH - DEBUG_PANEL_PADDING - 3).float32, y: yOffset.float32),
            1, Color(r: 255, g: 100, b: 100, a: 120))
    yOffset += 4
    
    drawText("Low HP Bonuses:", finalPanelX + DEBUG_PANEL_PADDING + 6, yOffset + 1, 10,
            Color(r: 0, g: 0, b: 0, a: 130))
    drawText("Low HP Bonuses:", finalPanelX + DEBUG_PANEL_PADDING + 5, yOffset, 10,
            Color(r: 255, g: 120, b: 120, a: 255))
    yOffset += 14
    
    # Background box for bonuses (compact)
    var bonusCount = 0
    if hasPowerUp(game.player, puRage): bonusCount += 1
    if hasPowerUp(game.player, puBerserker): bonusCount += 1
    
    drawRectangle(finalPanelX + DEBUG_PANEL_PADDING + 3, yOffset - 1,
                 DEBUG_PANEL_WIDTH - (DEBUG_PANEL_PADDING * 2) - 6, 
                 int32((DEBUG_LINE_HEIGHT * bonusCount) + 2),
                 Color(r: 25, g: 15, b: 15, a: 80))
    
    # Rage bonus
    if hasPowerUp(game.player, puRage):
      let rageLevel = getPowerUpLevel(game.player, puRage)
      let rageMultiplier = case rageLevel
        of 1: 0.5
        of 2: 0.8
        else: 1.2
      let rageBonus = ((1.0 - hpPercent) * 100.0 * rageMultiplier).int
      
      drawText("⚔ Rage:", finalPanelX + DEBUG_PANEL_PADDING + 8, yOffset + 1, 10,
              Color(r: 0, g: 0, b: 0, a: 130))
      drawText("⚔ Rage:", finalPanelX + DEBUG_PANEL_PADDING + 7, yOffset, 10,
              Color(r: 255, g: 100, b: 100, a: 255))
      
      let bonusText = "+" & $rageBonus & "% dmg"
      drawText(bonusText, finalPanelX + DEBUG_PANEL_WIDTH - DEBUG_PANEL_PADDING - 66,
              yOffset + 1, 10, Color(r: 0, g: 0, b: 0, a: 150))
      drawText(bonusText, finalPanelX + DEBUG_PANEL_WIDTH - DEBUG_PANEL_PADDING - 67,
              yOffset, 10, Color(r: 255, g: 150, b: 150, a: 255))
      yOffset += DEBUG_LINE_HEIGHT
    
    # Berserker bonus
    if hasPowerUp(game.player, puBerserker):
      let berserkLevel = getPowerUpLevel(game.player, puBerserker)
      let berserkMultiplier = case berserkLevel
        of 1: 0.5
        of 2: 0.8
        else: 1.2
      let berserkBonus = ((1.0 - hpPercent) * 100.0 * berserkMultiplier).int
      
      drawText("⚡ Berserk:", finalPanelX + DEBUG_PANEL_PADDING + 8, yOffset + 1, 10,
              Color(r: 0, g: 0, b: 0, a: 130))
      drawText("⚡ Berserk:", finalPanelX + DEBUG_PANEL_PADDING + 7, yOffset, 10,
              Color(r: 255, g: 150, b: 50, a: 255))
      
      let bonusText = "+" & $berserkBonus & "% rate"
      drawText(bonusText, finalPanelX + DEBUG_PANEL_WIDTH - DEBUG_PANEL_PADDING - 66,
              yOffset + 1, 10, Color(r: 0, g: 0, b: 0, a: 150))
      drawText(bonusText, finalPanelX + DEBUG_PANEL_WIDTH - DEBUG_PANEL_PADDING - 67,
              yOffset, 10, Color(r: 255, g: 200, b: 150, a: 255))
      yOffset += DEBUG_LINE_HEIGHT

proc drawMinimalDebugInfo*(game: Game, x, y: int32) =
  ## Draw minimal debug info (just FPS and entity count)
  let fps = getFPS()
  let fpsColor = if fps >= 55:
    Color(r: 150, g: 150, b: 150, a: 200)
  elif fps >= 30:
    Color(r: 180, g: 160, b: 100, a: 200)
  else:
    Color(r: 180, g: 120, b: 120, a: 200)
  
  drawText("FPS: " & $fps, x, y, 16, fpsColor)
