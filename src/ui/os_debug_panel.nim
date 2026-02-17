## OS-Style Debug Panel
## System diagnostics and performance metrics

import raylib, ../types, strutils, ../powerup, ../localization, ui_constants

const
  DEBUG_PANEL_WIDTH = 200
  DEBUG_PANEL_PADDING = 3  # Reduced from 4
  DEBUG_PANEL_BORDER = 1
  DEBUG_SECTION_SPACING = 2  # Reduced from 4
  DEBUG_TITLE_HEIGHT = 14  # Reduced from 16
  DEBUG_LINE_HEIGHT = 11  # Reduced from 12
  HEADER_BG_COLOR: Color = Color(r: 0, g: 100, b: 120, a: 60)
  ACCENT_COLOR: Color = Color(r: 0, g: 220, b: 255, a: 255)

# State for panel minimization and dragging
var debugPanelMinimized* = false
var debugPanelPos* = Vector2(x: -1, y: 2)  # Default position (-1 means aligned to right edge)
var debugPanelDragging* = false
var debugPanelDragOffset* = Vector2(x: 0, y: 0)

# State for legendary power-ups panel
var legendaryPanelMinimized* = false
var legendaryPanelPos* = Vector2(x: 10, y: -1)  # Default position (-1 for y means bottom-aligned)
var legendaryPanelDragging* = false
var legendaryPanelDragOffset* = Vector2(x: 0, y: 0)

## Calculate basic combat stats for display
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
    
    drawText(t("debug_panel_diagnostics"), finalPanelX + DEBUG_PANEL_PADDING + 5, yOffset + 3, 11,
            Color(r: 0, g: 0, b: 0, a: 140))
    drawText(t("debug_panel_diagnostics"), finalPanelX + DEBUG_PANEL_PADDING + 4, yOffset + 2, 11, ACCENT_COLOR)
    
    # Draw maximize icon (square)
    let iconX = finalPanelX + DEBUG_PANEL_WIDTH - DEBUG_PANEL_PADDING - 12
    let iconY = yOffset + 4
    drawRectangleLines(Rectangle(x: iconX.float32, y: iconY.float32, width: 10, height: 10),
                      1, ACCENT_COLOR)
    
    return  # Don't draw rest of panel
  
  # Calculate panel height based on content - COMPACT version
  var contentHeight: int32 = DEBUG_PANEL_PADDING * 2 + DEBUG_TITLE_HEIGHT + 2  # Header (reduced spacing)
  
  # FPS/Entity row
  contentHeight += 22  # Reduced from 26
  
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
    contentHeight += int32(12 + (activeTimers * DEBUG_LINE_HEIGHT) + DEBUG_SECTION_SPACING)  # Reduced header from 14
  
  # AutoShoot status if player has the power-up
  if hasPowerUp(game.player, puAutoShoot):
    contentHeight += int32(12 + DEBUG_LINE_HEIGHT + 4 + DEBUG_SECTION_SPACING)  # Reduced spacing
  
  # Always show combat stats
  contentHeight += int32(12 + (DEBUG_LINE_HEIGHT * 3) + 4 + DEBUG_SECTION_SPACING)  # Reduced spacing
  
  # Add height for rage/berserker bonuses if applicable
  let hpPercent = game.player.hp / game.player.maxHp
  if hpPercent < 0.7 and (hasPowerUp(game.player, puRage) or hasPowerUp(game.player, puBerserker)):
    var bonusCount = 0
    if hasPowerUp(game.player, puRage): bonusCount += 1
    if hasPowerUp(game.player, puBerserker): bonusCount += 1
    contentHeight += int32(12 + (bonusCount * DEBUG_LINE_HEIGHT) + 4)  # Reduced spacing
  
  var dopamineLines = 0
  # Streak mechanic removed
  if dopamineLines > 0:
    contentHeight += int32(12 + (DEBUG_LINE_HEIGHT * dopamineLines) + 3)  # Reduced spacing
  
  # Real-time stats section - make it compact (only show 2 most important stats)
  contentHeight += int32(11 + (DEBUG_LINE_HEIGHT * 2) + 4)  # Reduced spacing throughout
  
  # Add bottom padding so text doesn't sit on border
  contentHeight += 3  # Extra pixels at bottom
  
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
  
  # SYSTEM DIAGNOSTICS HEADER
  # Header bar background - colorful cyan (clickable to minimize)
  drawRectangle(finalPanelX, yOffset, DEBUG_PANEL_WIDTH - 2, DEBUG_TITLE_HEIGHT, HEADER_BG_COLOR)
  
  drawText(t(tkDebugPanelDiagnostics), finalPanelX + DEBUG_PANEL_PADDING + 5, yOffset + 3, 11,
          Color(r: 0, g: 0, b: 0, a: 140))
  drawText(t(tkDebugPanelDiagnostics), finalPanelX + DEBUG_PANEL_PADDING + 4, yOffset + 2, 11, ACCENT_COLOR)
  
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
  
  drawText(t(tkDebugPanelFPS) & ":", finalPanelX + DEBUG_PANEL_PADDING + 6, yOffset + 1, 9,
          Color(r: 0, g: 0, b: 0, a: 130))
  drawText(t(tkDebugPanelFPS) & ":", finalPanelX + DEBUG_PANEL_PADDING + 5, yOffset, 9,
          Color(r: 180, g: 200, b: 220, a: 255))
  
  drawText($fps, finalPanelX + DEBUG_PANEL_PADDING + 32, yOffset + 1, 11,
          Color(r: 0, g: 0, b: 0, a: 150))
  drawText($fps, finalPanelX + DEBUG_PANEL_PADDING + 31, yOffset, 11, fpsColor)
  
  # Entity count - purple color
  let totalEntities = game.enemies.len + game.bullets.len
  let entityX = finalPanelX + DEBUG_PANEL_WIDTH div 2 + 2
  
  drawText(t(tkDebugPanelEntities) & ":", entityX + 1, yOffset + 1, 9,
          Color(r: 0, g: 0, b: 0, a: 130))
  drawText(t(tkDebugPanelEntities) & ":", entityX, yOffset, 9,
          Color(r: 180, g: 200, b: 220, a: 255))
  
  drawText($totalEntities, entityX + 28, yOffset + 1, 11,
          Color(r: 0, g: 0, b: 0, a: 150))
  drawText($totalEntities, entityX + 27, yOffset, 11,
          Color(r: 180, g: 100, b: 255, a: 255))
  
  yOffset += 18
  
  # ACTIVE EFFECTS
  if activeTimers > 0:
    # Section separator line - cyan
    drawLine(Vector2(x: (finalPanelX + DEBUG_PANEL_PADDING + 2).float32, y: yOffset.float32),
            Vector2(x: (finalPanelX + DEBUG_PANEL_WIDTH - DEBUG_PANEL_PADDING - 2).float32, y: yOffset.float32),
            1, Color(r: 0, g: 220, b: 255, a: 120))
    yOffset += 3
    
    drawText(t(tkDebugPanelActiveEffects) & ":", finalPanelX + DEBUG_PANEL_PADDING + 5, yOffset + 1, 9,
            Color(r: 0, g: 0, b: 0, a: 130))
    drawText(t(tkDebugPanelActiveEffects) & ":", finalPanelX + DEBUG_PANEL_PADDING + 4, yOffset, 9,
            Color(r: 200, g: 220, b: 240, a: 255))
    yOffset += 12
    
    # Speed boost - cyan color
    if game.player.speedBoostTimer > 0:
      drawRectangle(finalPanelX + DEBUG_PANEL_PADDING + 2, yOffset - 1,
                   DEBUG_PANEL_WIDTH - (DEBUG_PANEL_PADDING * 2) - 4, DEBUG_LINE_HEIGHT,
                   Color(r: 0, g: 30, b: 40, a: 50))
      
      let timeLeft = game.player.speedBoostTimer.int + 1
      drawText("[>] Speed", finalPanelX + DEBUG_PANEL_PADDING + 6, yOffset + 1, 10,
              Color(r: 0, g: 0, b: 0, a: 140))
      drawText("[>] Speed", finalPanelX + DEBUG_PANEL_PADDING + 5, yOffset, 10,
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
      drawText("[S] Invuln", finalPanelX + DEBUG_PANEL_PADDING + 6, yOffset + 1, 10,
              Color(r: 0, g: 0, b: 0, a: 140))
      drawText("[S] Invuln", finalPanelX + DEBUG_PANEL_PADDING + 5, yOffset, 10,
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
      drawText("[F] Fire", finalPanelX + DEBUG_PANEL_PADDING + 6, yOffset + 1, 10,
              Color(r: 0, g: 0, b: 0, a: 140))
      drawText("[F] Fire", finalPanelX + DEBUG_PANEL_PADDING + 5, yOffset, 10,
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
      drawText("[M] Magnet", finalPanelX + DEBUG_PANEL_PADDING + 8, yOffset + 1, 11,
              Color(r: 0, g: 0, b: 0, a: 140))
      drawText("[M] Magnet", finalPanelX + DEBUG_PANEL_PADDING + 7, yOffset, 11,
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
      drawText("[T] Time Warp", finalPanelX + DEBUG_PANEL_PADDING + 8, yOffset + 1, 11,
              Color(r: 0, g: 0, b: 0, a: 140))
      drawText("[T] Time Warp", finalPanelX + DEBUG_PANEL_PADDING + 7, yOffset, 11,
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
      
      drawText(t(tkDebugPanelEffectPhase), finalPanelX + DEBUG_PANEL_PADDING + 8, yOffset + 1, 11,
              Color(r: 0, g: 0, b: 0, a: 140))
      drawText(t(tkDebugPanelEffectPhase), finalPanelX + DEBUG_PANEL_PADDING + 7, yOffset, 11,
              Color(r: 150, g: 255, b: 200, a: 255))
      
      drawText(t(tkDebugPanelActive), finalPanelX + DEBUG_PANEL_WIDTH - DEBUG_PANEL_PADDING - 40,
              yOffset + 1, 10, Color(r: 0, g: 0, b: 0, a: 140))
      drawText(t(tkDebugPanelActive), finalPanelX + DEBUG_PANEL_WIDTH - DEBUG_PANEL_PADDING - 41,
              yOffset, 10, Color(r: 180, g: 200, b: 220, a: 255))
      yOffset += DEBUG_LINE_HEIGHT
    
    # Parry
    if game.player.parryActive:
      drawRectangle(finalPanelX + DEBUG_PANEL_PADDING + 3, yOffset - 1,
                   DEBUG_PANEL_WIDTH - (DEBUG_PANEL_PADDING * 2) - 6, DEBUG_LINE_HEIGHT,
                   Color(r: 18, g: 25, b: 35, a: 70))
      
      drawText(t(tkDebugPanelEffectParry), finalPanelX + DEBUG_PANEL_PADDING + 8, yOffset + 1, 11,
              Color(r: 0, g: 0, b: 0, a: 140))
      drawText(t(tkDebugPanelEffectParry), finalPanelX + DEBUG_PANEL_PADDING + 7, yOffset, 11,
              Color(r: 255, g: 255, b: 100, a: 255))
      
      drawText(t(tkDebugPanelActive), finalPanelX + DEBUG_PANEL_WIDTH - DEBUG_PANEL_PADDING - 40,
              yOffset + 1, 10, Color(r: 0, g: 0, b: 0, a: 140))
      drawText(t(tkDebugPanelActive), finalPanelX + DEBUG_PANEL_WIDTH - DEBUG_PANEL_PADDING - 41,
              yOffset, 10, Color(r: 180, g: 200, b: 220, a: 255))
      yOffset += DEBUG_LINE_HEIGHT
    
    yOffset += DEBUG_SECTION_SPACING
  
  #  AUTOSHOOT STATUS
  if hasPowerUp(game.player, puAutoShoot):
    # Section separator line
    drawLine(Vector2(x: (finalPanelX + DEBUG_PANEL_PADDING + 3).float32, y: yOffset.float32),
            Vector2(x: (finalPanelX + DEBUG_PANEL_WIDTH - DEBUG_PANEL_PADDING - 3).float32, y: yOffset.float32),
            1, Color(r: 0, g: 200, b: 255, a: 100))
    yOffset += 4
    
    drawText(t(tkDebugPanelAutoShoot) & ":", finalPanelX + DEBUG_PANEL_PADDING + 6, yOffset + 1, 10,
            Color(r: 0, g: 0, b: 0, a: 130))
    drawText(t(tkDebugPanelAutoShoot) & ":", finalPanelX + DEBUG_PANEL_PADDING + 5, yOffset, 10,
            Color(r: 200, g: 220, b: 240, a: 255))
    yOffset += 14
    
    let autoLevel = getPowerUpLevel(game.player, puAutoShoot)
    let autoStatus = if game.player.autoShootEnabled and game.enemies.len > 0:
      t(tkDebugPanelAutoShootActive)
    else:
      t(tkDebugPanelAutoShootIdle)
    let autoColor = if game.player.autoShootEnabled and game.enemies.len > 0:
      Color(r: 100, g: 255, b: 150, a: 255)  # Green when active
    else:
      Color(r: 150, g: 150, b: 150, a: 200)  # Gray when idle
    
    drawRectangle(finalPanelX + DEBUG_PANEL_PADDING + 2, yOffset - 1,
                 DEBUG_PANEL_WIDTH - (DEBUG_PANEL_PADDING * 2) - 4, DEBUG_LINE_HEIGHT,
                 Color(r: 0, g: 30, b: 40, a: 50))
    
    drawText("[A] L" & $autoLevel, finalPanelX + DEBUG_PANEL_PADDING + 6, yOffset + 1, 10,
            Color(r: 0, g: 0, b: 0, a: 140))
    drawText("[A] L" & $autoLevel, finalPanelX + DEBUG_PANEL_PADDING + 5, yOffset, 10,
            Color(r: 100, g: 255, b: 100, a: 255))
    
    drawText(autoStatus, finalPanelX + DEBUG_PANEL_WIDTH - DEBUG_PANEL_PADDING - 48,
            yOffset + 1, 10, Color(r: 0, g: 0, b: 0, a: 140))
    drawText(autoStatus, finalPanelX + DEBUG_PANEL_WIDTH - DEBUG_PANEL_PADDING - 49,
            yOffset, 10, autoColor)
    yOffset += DEBUG_LINE_HEIGHT + 8
  
  # COMBAT STATS
  # Section separator line
  drawLine(Vector2(x: (finalPanelX + DEBUG_PANEL_PADDING + 3).float32, y: yOffset.float32),
          Vector2(x: (finalPanelX + DEBUG_PANEL_WIDTH - DEBUG_PANEL_PADDING - 3).float32, y: yOffset.float32),
          1, Color(r: 0, g: 200, b: 255, a: 100))
  yOffset += 4
  
  drawText(t(tkDebugPanelCombatStats) & ":", finalPanelX + DEBUG_PANEL_PADDING + 6, yOffset + 1, 10,
          Color(r: 0, g: 0, b: 0, a: 130))
  drawText(t(tkDebugPanelCombatStats) & ":", finalPanelX + DEBUG_PANEL_PADDING + 5, yOffset, 10,
          Color(r: 200, g: 220, b: 240, a: 255))
  yOffset += 14
  
  let stats = getDisplayStats(game.player)
  
  # Stats background box (compact)
  drawRectangle(finalPanelX + DEBUG_PANEL_PADDING + 3, yOffset - 1,
               DEBUG_PANEL_WIDTH - (DEBUG_PANEL_PADDING * 2) - 6, DEBUG_LINE_HEIGHT * 3 + 2,
               Color(r: 15, g: 20, b: 28, a: 70))
  
  # Damage (multiplied by 100, showing decimals with precision)
  let damageText = formatHealthDisplay(stats.damage)
  drawText(t(tkDebugPanelDamage) & ":", finalPanelX + DEBUG_PANEL_PADDING + 8, yOffset + 1, 10,
          Color(r: 0, g: 0, b: 0, a: 130))
  drawText(t(tkDebugPanelDamage) & ":", finalPanelX + DEBUG_PANEL_PADDING + 7, yOffset, 10,
          Color(r: 180, g: 200, b: 220, a: 255))
  
  drawText(damageText, finalPanelX + DEBUG_PANEL_WIDTH - DEBUG_PANEL_PADDING - 46,
          yOffset + 1, 11, Color(r: 0, g: 0, b: 0, a: 150))
  drawText(damageText, finalPanelX + DEBUG_PANEL_WIDTH - DEBUG_PANEL_PADDING - 47,
          yOffset, 11, Color(r: 255, g: 150, b: 100, a: 255))
  yOffset += DEBUG_LINE_HEIGHT
  
  # Fire rate (shots per second)
  let shotsPerSec = 1.0 / stats.fireRate
  let fireRateText = formatFloat(shotsPerSec, ffDecimal, 2) & "/s"
  drawText(t(tkDebugPanelFireRate) & ":", finalPanelX + DEBUG_PANEL_PADDING + 8, yOffset + 1, 10,
          Color(r: 0, g: 0, b: 0, a: 130))
  drawText(t(tkDebugPanelFireRate) & ":", finalPanelX + DEBUG_PANEL_PADDING + 7, yOffset, 10,
          Color(r: 180, g: 200, b: 220, a: 255))
  
  drawText(fireRateText, finalPanelX + DEBUG_PANEL_WIDTH - DEBUG_PANEL_PADDING - 46,
          yOffset + 1, 11, Color(r: 0, g: 0, b: 0, a: 150))
  drawText(fireRateText, finalPanelX + DEBUG_PANEL_WIDTH - DEBUG_PANEL_PADDING - 47,
          yOffset, 11, Color(r: 255, g: 200, b: 100, a: 255))
  yOffset += DEBUG_LINE_HEIGHT
  
  # Speed
  let speedText = formatFloat(stats.speed, ffDecimal, 2)
  drawText(t(tkDebugPanelSpeed) & ":", finalPanelX + DEBUG_PANEL_PADDING + 8, yOffset + 1, 10,
          Color(r: 0, g: 0, b: 0, a: 130))
  drawText(t(tkDebugPanelSpeed) & ":", finalPanelX + DEBUG_PANEL_PADDING + 7, yOffset, 10,
          Color(r: 180, g: 200, b: 220, a: 255))
  
  drawText(speedText, finalPanelX + DEBUG_PANEL_WIDTH - DEBUG_PANEL_PADDING - 46,
          yOffset + 1, 11, Color(r: 0, g: 0, b: 0, a: 150))
  drawText(speedText, finalPanelX + DEBUG_PANEL_WIDTH - DEBUG_PANEL_PADDING - 47,
          yOffset, 11, Color(r: 100, g: 200, b: 255, a: 255))
  yOffset += DEBUG_LINE_HEIGHT + 6
  
  # LOW HP BONUSES
  if hpPercent < 0.7 and (hasPowerUp(game.player, puRage) or hasPowerUp(game.player, puBerserker)):
    # Section separator line
    drawLine(Vector2(x: (finalPanelX + DEBUG_PANEL_PADDING + 3).float32, y: yOffset.float32),
            Vector2(x: (finalPanelX + DEBUG_PANEL_WIDTH - DEBUG_PANEL_PADDING - 3).float32, y: yOffset.float32),
            1, Color(r: 255, g: 100, b: 100, a: 120))
    yOffset += 4
    
    drawText(t(tkDebugPanelLowHPBonuses) & ":", finalPanelX + DEBUG_PANEL_PADDING + 6, yOffset + 1, 10,
            Color(r: 0, g: 0, b: 0, a: 130))
    drawText(t(tkDebugPanelLowHPBonuses) & ":", finalPanelX + DEBUG_PANEL_PADDING + 5, yOffset, 10,
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
      
      drawText("[X] " & t(tkDebugPanelRage) & ":", finalPanelX + DEBUG_PANEL_PADDING + 8, yOffset + 1, 10,
              Color(r: 0, g: 0, b: 0, a: 130))
      drawText("[X] " & t(tkDebugPanelRage) & ":", finalPanelX + DEBUG_PANEL_PADDING + 7, yOffset, 10,
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
      
      drawText("[!] " & t(tkDebugPanelBerserker) & ":", finalPanelX + DEBUG_PANEL_PADDING + 8, yOffset + 1, 10,
              Color(r: 0, g: 0, b: 0, a: 130))
      drawText("[!] " & t(tkDebugPanelBerserker) & ":", finalPanelX + DEBUG_PANEL_PADDING + 7, yOffset, 10,
              Color(r: 255, g: 150, b: 50, a: 255))
      
      let bonusText = "+" & $berserkBonus & "% rate"
      drawText(bonusText, finalPanelX + DEBUG_PANEL_WIDTH - DEBUG_PANEL_PADDING - 66,
              yOffset + 1, 10, Color(r: 0, g: 0, b: 0, a: 150))
      drawText(bonusText, finalPanelX + DEBUG_PANEL_WIDTH - DEBUG_PANEL_PADDING - 67,
              yOffset, 10, Color(r: 255, g: 200, b: 150, a: 255))
      yOffset += DEBUG_LINE_HEIGHT
  
  # REAL-TIME STATS
  # Section separator line
  drawLine(Vector2(x: (finalPanelX + DEBUG_PANEL_PADDING + 3).float32, y: yOffset.float32),
          Vector2(x: (finalPanelX + DEBUG_PANEL_WIDTH - DEBUG_PANEL_PADDING - 3).float32, y: yOffset.float32),
          1, Color(r: 100, g: 200, b: 255, a: 100))
  yOffset += 3
  
  drawText(t("debug_panel_run_stats") & ":", finalPanelX + DEBUG_PANEL_PADDING + 6, yOffset + 1, 9,
          Color(r: 0, g: 0, b: 0, a: 130))
  drawText(t("debug_panel_run_stats") & ":", finalPanelX + DEBUG_PANEL_PADDING + 5, yOffset, 9,
          Color(r: 200, g: 220, b: 240, a: 255))
  yOffset += 11
  
  # Background box for real-time stats (compact - only 2 stats)
  drawRectangle(finalPanelX + DEBUG_PANEL_PADDING + 3, yOffset - 1,
               DEBUG_PANEL_WIDTH - (DEBUG_PANEL_PADDING * 2) - 6,
               int32((DEBUG_LINE_HEIGHT * 2) + 2),
               Color(r: 15, g: 20, b: 25, a: 80))
  
  let rtStats = game.dopamine.realTimeStats
  
  # DPS (most important combat stat)
  drawText("[⚔] DPS:", finalPanelX + DEBUG_PANEL_PADDING + 8, yOffset + 1, 9,
          Color(r: 0, g: 0, b: 0, a: 130))
  drawText("[⚔] DPS:", finalPanelX + DEBUG_PANEL_PADDING + 7, yOffset, 9,
          Color(r: 180, g: 200, b: 220, a: 255))
  
  let dpsText = $(int(rtStats.dps))
  drawText(dpsText, finalPanelX + DEBUG_PANEL_WIDTH - DEBUG_PANEL_PADDING - 50,
          yOffset + 1, 9, Color(r: 0, g: 0, b: 0, a: 150))
  drawText(dpsText, finalPanelX + DEBUG_PANEL_WIDTH - DEBUG_PANEL_PADDING - 51,
          yOffset, 9, Color(r: 255, g: 100, b: 100, a: 255))
  yOffset += DEBUG_LINE_HEIGHT
  
  # Coins per minute (economy stat)
  drawText("[¢] C/min:", finalPanelX + DEBUG_PANEL_PADDING + 8, yOffset + 1, 9,
          Color(r: 0, g: 0, b: 0, a: 130))
  drawText("[¢] C/min:", finalPanelX + DEBUG_PANEL_PADDING + 7, yOffset, 9,
          Color(r: 180, g: 200, b: 220, a: 255))
  
  let cpmText = $(int(rtStats.coinsPerMinute))
  drawText(cpmText, finalPanelX + DEBUG_PANEL_WIDTH - DEBUG_PANEL_PADDING - 50,
          yOffset + 1, 9, Color(r: 0, g: 0, b: 0, a: 150))
  drawText(cpmText, finalPanelX + DEBUG_PANEL_WIDTH - DEBUG_PANEL_PADDING - 51,
          yOffset, 9, Color(r: 255, g: 215, b: 0, a: 255))

proc drawLegendaryPowerUpsPanel*(game: Game, screenWidth, screenHeight: int32) =
  ## Draw legendary power-ups status panel in OS style (bottom-left)
  ## Movable and minimizable like other OS panels
  let panelWidth: int32 = 220
  
  # Check if player has any legendary power-ups
  var hasAnyLegendary = false
  if hasPowerUp(game.player, puTimeWarp):
    hasAnyLegendary = true
  if hasPowerUp(game.player, puPhaseShift):
    hasAnyLegendary = true
  if hasPowerUp(game.player, puParry):
    hasAnyLegendary = true
  
  if not hasAnyLegendary:
    return
  
  # Calculate actual position
  var actualX = legendaryPanelPos.x.int32
  var actualY = if legendaryPanelPos.y < 0:
    screenHeight - 160  # Default bottom position
  else:
    legendaryPanelPos.y.int32
  
  # Handle dragging
  let mousePos = getMousePosition()
  let headerHeight = (DEBUG_PANEL_PADDING + DEBUG_TITLE_HEIGHT).float32
  let headerRect = Rectangle(
    x: actualX.float32,
    y: actualY.float32,
    width: panelWidth.float32,
    height: headerHeight
  )
  
  # Start dragging or minimize
  if isMouseButtonPressed(Left) and checkCollisionPointRec(mousePos, headerRect):
    # Check if clicking on minimize button area (right side of header)
    let minimizeButtonX = actualX + panelWidth - DEBUG_PANEL_PADDING - 12
    let minimizeButtonRect = Rectangle(
      x: minimizeButtonX.float32,
      y: (actualY + DEBUG_PANEL_PADDING).float32,
      width: 16,
      height: DEBUG_TITLE_HEIGHT.float32
    )
    
    if checkCollisionPointRec(mousePos, minimizeButtonRect):
      # Toggle minimize
      legendaryPanelMinimized = not legendaryPanelMinimized
    else:
      # Start dragging
      legendaryPanelDragging = true
      legendaryPanelDragOffset = Vector2(
        x: mousePos.x - actualX.float32,
        y: mousePos.y - actualY.float32
      )
  
  # Update dragging
  if legendaryPanelDragging:
    if isMouseButtonDown(Left):
      legendaryPanelPos = Vector2(
        x: mousePos.x - legendaryPanelDragOffset.x,
        y: mousePos.y - legendaryPanelDragOffset.y
      )
      # Clamp to screen bounds
      legendaryPanelPos.x = clamp(legendaryPanelPos.x, 0, (screenWidth - panelWidth).float32)
      legendaryPanelPos.y = clamp(legendaryPanelPos.y, 0, (screenHeight - 50).float32)
      actualX = legendaryPanelPos.x.int32
      actualY = legendaryPanelPos.y.int32
    else:
      legendaryPanelDragging = false
  
  # Calculate content height
  var contentHeight: int32 = DEBUG_PANEL_PADDING * 2 + DEBUG_TITLE_HEIGHT
  
  if hasPowerUp(game.player, puTimeWarp):
    contentHeight += DEBUG_LINE_HEIGHT + 2
  if hasPowerUp(game.player, puPhaseShift):
    contentHeight += DEBUG_LINE_HEIGHT + 2
  if hasPowerUp(game.player, puParry):
    contentHeight += DEBUG_LINE_HEIGHT + 2
  
  contentHeight += DEBUG_SECTION_SPACING
  
  # If minimized, only draw header bar
  if legendaryPanelMinimized:
    # Draw minimized panel (just header)
    drawRectangle(actualX, actualY, panelWidth, DEBUG_PANEL_PADDING + DEBUG_TITLE_HEIGHT,
                 Color(r: 5, g: 15, b: 25, a: 45))
    
    # Cyan accent stripe on right edge
    drawRectangle(actualX + panelWidth - 2, actualY, 2, DEBUG_PANEL_PADDING + DEBUG_TITLE_HEIGHT,
                 Color(r: 0, g: 220, b: 255, a: 180))
    
    # Panel border
    drawRectangleLines(Rectangle(x: actualX.float32, y: actualY.float32,
                                  width: panelWidth.float32,
                                  height: (DEBUG_PANEL_PADDING + DEBUG_TITLE_HEIGHT).float32),
                      DEBUG_PANEL_BORDER, Color(r: 0, g: 220, b: 255, a: 80))
    
    var yOffset = actualY + DEBUG_PANEL_PADDING
    
    # Header with minimize indicator
    drawRectangle(actualX, yOffset, panelWidth - 2, DEBUG_TITLE_HEIGHT, HEADER_BG_COLOR)
    
    drawText(t(tkLegendaryPanelTitle), actualX + DEBUG_PANEL_PADDING + 5, yOffset + 3, 11,
            Color(r: 0, g: 0, b: 0, a: 140))
    drawText(t(tkLegendaryPanelTitle), actualX + DEBUG_PANEL_PADDING + 4, yOffset + 2, 11, ACCENT_COLOR)
    
    # Draw maximize icon (square)
    let iconX = actualX + panelWidth - DEBUG_PANEL_PADDING - 12
    let iconY = yOffset + 4
    drawRectangleLines(Rectangle(x: iconX.float32, y: iconY.float32, width: 10, height: 10),
                      1, ACCENT_COLOR)
    
    return  # Don't draw rest of panel
  
  # Panel background
  drawRectangle(actualX, actualY, panelWidth, contentHeight,
               Color(r: 5, g: 15, b: 25, a: 45))
  
  # Cyan accent stripe on right edge
  drawRectangle(actualX + panelWidth - 2, actualY, 2, contentHeight,
               Color(r: 0, g: 220, b: 255, a: 180))
  
  # Panel border
  drawRectangleLines(Rectangle(x: actualX.float32, y: actualY.float32,
                                width: panelWidth.float32, height: contentHeight.float32),
                    DEBUG_PANEL_BORDER, Color(r: 0, g: 220, b: 255, a: 80))
  
  var yOffset = actualY + DEBUG_PANEL_PADDING
  
  # Header bar background
  drawRectangle(actualX, yOffset, panelWidth - 2, DEBUG_TITLE_HEIGHT, HEADER_BG_COLOR)
  
  drawText(t(tkLegendaryPanelTitle), actualX + DEBUG_PANEL_PADDING + 5, yOffset + 3, 11,
          Color(r: 0, g: 0, b: 0, a: 140))
  drawText(t(tkLegendaryPanelTitle), actualX + DEBUG_PANEL_PADDING + 4, yOffset + 2, 11, ACCENT_COLOR)
  
  # Draw minimize icon (horizontal line)
  let iconX = actualX + panelWidth - DEBUG_PANEL_PADDING - 12
  let iconY = yOffset + 9
  drawLine(Vector2(x: iconX.float32, y: iconY.float32),
          Vector2(x: (iconX + 10).float32, y: iconY.float32),
          2, ACCENT_COLOR)
  
  yOffset += DEBUG_TITLE_HEIGHT + 4
  
  # Time Warp
  if hasPowerUp(game.player, puTimeWarp):
    drawRectangle(actualX + DEBUG_PANEL_PADDING + 2, yOffset - 1,
                 panelWidth - (DEBUG_PANEL_PADDING * 2) - 4, DEBUG_LINE_HEIGHT,
                 Color(r: 18, g: 25, b: 35, a: 50))
    
    let timeWarpColor = if game.player.timeWarpActive:
      Color(r: 100, g: 255, b: 255, a: 255)  # Cyan when active
    elif game.player.timeWarpCooldown > 0:
      Color(r: 100, g: 100, b: 100, a: 200)  # Gray when on cooldown
    else:
      Color(r: 100, g: 220, b: 255, a: 255)  # Light cyan when ready
    
    drawText(t(tkLegendaryChronos), actualX + DEBUG_PANEL_PADDING + 6, yOffset + 1, 10,
            Color(r: 0, g: 0, b: 0, a: 140))
    drawText(t(tkLegendaryChronos), actualX + DEBUG_PANEL_PADDING + 5, yOffset, 10,
            timeWarpColor)
    
    # Get uses available
    let usesAvailable = game.player.timeWarpMaxUsesPerWave - game.player.timeWarpUsesThisWave
    let maxUses = game.player.timeWarpMaxUsesPerWave
    
    # Status on the right - showing cooldown in seconds and charges as current/max
    var statusText = ""
    if game.player.timeWarpActive:
      statusText = t(tkLegendaryActive) & " (" & $usesAvailable & "/" & $maxUses & ")"
    elif game.player.timeWarpCooldown > 0:
      let cooldownSecs = game.player.timeWarpCooldown.int + 1
      statusText = $cooldownSecs & "s (" & $usesAvailable & "/" & $maxUses & ")"
    else:
      statusText = t(tkLegendaryReady) & " (" & $usesAvailable & "/" & $maxUses & ")"
    
    drawText(statusText, actualX + panelWidth - DEBUG_PANEL_PADDING - 90,
            yOffset + 1, 9, Color(r: 0, g: 0, b: 0, a: 140))
    drawText(statusText, actualX + panelWidth - DEBUG_PANEL_PADDING - 91,
            yOffset, 9, timeWarpColor)
    yOffset += DEBUG_LINE_HEIGHT + 2
  
  # Phase Shift
  if hasPowerUp(game.player, puPhaseShift):
    drawRectangle(actualX + DEBUG_PANEL_PADDING + 2, yOffset - 1,
                 panelWidth - (DEBUG_PANEL_PADDING * 2) - 4, DEBUG_LINE_HEIGHT,
                 Color(r: 12, g: 28, b: 25, a: 50))
    
    let phaseColor = if game.player.phaseShiftInvulnTimer > 0:
      Color(r: 150, g: 255, b: 200, a: 255)  # Green when dashing
    elif game.player.phaseShiftCooldown > 0:
      Color(r: 100, g: 100, b: 100, a: 200)  # Gray when on cooldown
    else:
      Color(r: 100, g: 255, b: 200, a: 255)  # Light green when ready
    
    drawText(t(tkLegendaryPhase), actualX + DEBUG_PANEL_PADDING + 6, yOffset + 1, 10,
            Color(r: 0, g: 0, b: 0, a: 140))
    drawText(t(tkLegendaryPhase), actualX + DEBUG_PANEL_PADDING + 5, yOffset, 10,
            phaseColor)
    
    # Status on the right - showing cooldown in seconds
    var statusText = ""
    if game.player.phaseShiftInvulnTimer > 0:
      statusText = t(tkLegendaryDashing)
    elif game.player.phaseShiftCooldown > 0:
      let cooldownSecs = game.player.phaseShiftCooldown.int + 1
      statusText = $cooldownSecs & "s"
    else:
      statusText = t(tkLegendaryReady)
    
    drawText(statusText, actualX + panelWidth - DEBUG_PANEL_PADDING - 70,
            yOffset + 1, 10, Color(r: 0, g: 0, b: 0, a: 140))
    drawText(statusText, actualX + panelWidth - DEBUG_PANEL_PADDING - 71,
            yOffset, 10, phaseColor)
    yOffset += DEBUG_LINE_HEIGHT + 2
  
  # Parry
  if hasPowerUp(game.player, puParry):
    drawRectangle(actualX + DEBUG_PANEL_PADDING + 2, yOffset - 1,
                 panelWidth - (DEBUG_PANEL_PADDING * 2) - 4, DEBUG_LINE_HEIGHT,
                 Color(r: 25, g: 25, b: 12, a: 50))
    
    let parryColor = if game.player.parryActive:
      Color(r: 255, g: 255, b: 100, a: 255)  # Yellow when active
    elif game.player.parryCooldown > 0:
      Color(r: 100, g: 100, b: 100, a: 200)  # Gray when on cooldown
    else:
      Color(r: 255, g: 255, b: 150, a: 255)  # Light yellow when ready
    
    drawText(t(tkLegendaryParry), actualX + DEBUG_PANEL_PADDING + 6, yOffset + 1, 10,
            Color(r: 0, g: 0, b: 0, a: 140))
    drawText(t(tkLegendaryParry), actualX + DEBUG_PANEL_PADDING + 5, yOffset, 10,
            parryColor)
    
    # Status on the right - showing cooldown in seconds
    var statusText = ""
    if game.player.parryActive:
      statusText = t(tkLegendaryActive)
    elif game.player.parryCooldown > 0:
      let cooldownSecs = game.player.parryCooldown.int + 1
      statusText = $cooldownSecs & "s"
    else:
      statusText = t(tkLegendaryReady)
    
    drawText(statusText, actualX + panelWidth - DEBUG_PANEL_PADDING - 70,
            yOffset + 1, 10, Color(r: 0, g: 0, b: 0, a: 140))
    drawText(statusText, actualX + panelWidth - DEBUG_PANEL_PADDING - 71,
            yOffset, 10, parryColor)

proc drawMinimalDebugInfo*(game: Game, x, y: int32) =
  ## Draw minimal debug info (just FPS and entity count)
  let fps = getFPS()
  let fpsColor = if fps >= 55:
    Color(r: 150, g: 150, b: 150, a: 200)
  elif fps >= 30:
    Color(r: 180, g: 160, b: 100, a: 200)
  else:
    Color(r: 180, g: 120, b: 120, a: 200)
  
  drawText(t("debug_panel_fps") & ": " & $fps, x, y, 16, fpsColor)
