## OS-Style Debug Panel
## System diagnostics and performance metrics

import raylib, strutils, math
import ../types, ../powerup, ../localization, ui_constants, ../render_context, ../powerup_data, icon_drawing, ../utils

const
  DBG_FULL_W = 200        # classic debug panel width
  DBG_GUTTER_W = 171      # widescreen: must fit inside the 171px gutter
  DEBUG_PANEL_PADDING = 3  # Reduced from 4
  DEBUG_PANEL_BORDER = 1
  DEBUG_SECTION_SPACING = 2  # Reduced from 4
  DEBUG_TITLE_HEIGHT = 14  # Reduced from 16
  DEBUG_LINE_HEIGHT = 11  # Reduced from 12
  LEGENDARY_Q_ICON_SIZE = 30
  LEGENDARY_Q_ICON_GAP = 7
  LEGENDARY_Q_PADDING = 6
  LEGENDARY_Q_FOOTER_HEIGHT = 12
  HEADER_BG_COLOR: Color = Color(r: 0, g: 100, b: 120, a: 60)
  ACCENT_COLOR: Color = Color(r: 0, g: 220, b: 255, a: 255)

# Active debug panel width; set per-frame at the top of drawDebugPanel so the
# widescreen build can shrink it to fit the 171px gutter (classic keeps 200).
var debugPanelW: int32 = DBG_FULL_W

# State for panel minimization and dragging
var debugPanelMinimized* = false
var debugPanelPos* = Vector2(x: -1, y: 2)  # Default position (-1 means aligned to right edge)
var debugPanelDragging* = false
var debugPanelDragOffset* = Vector2(x: 0, y: 0)

# State for legendary power-ups panel
var legendaryPanelMinimized* = false
var legendaryPanelPos* = Vector2(x: -1, y: -1)  # Default position (-1 means bottom/right aligned)
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

proc drawDebugPanel*(game: Game, x, y: int32, anchorLeftDefault: bool = false) =
  ## Draw comprehensive debug and diagnostics panel
  # Widescreen (anchorLeftDefault) lives in the 171px left gutter, so shrink the
  # panel to fit; classic keeps its full 200px width.
  debugPanelW = if anchorLeftDefault: DBG_GUTTER_W else: DBG_FULL_W
  # Use stored position - if x is -1, auto-position (right edge, or left edge when
  # anchorLeftDefault so the Border HUD layout keeps it clear of the left panel).
  let sentinelX = debugPanelPos.x < 0
  let actualX = if sentinelX:
    (if anchorLeftDefault: 0.0'f32
     else: game.screenWidth.float32 - debugPanelW.float32)
  else:
    debugPanelPos.x

  var yOffset = if sentinelX and anchorLeftDefault:
    max(debugPanelPos.y.int32, 340'i32)
  else:
    debugPanelPos.y.int32
  var finalPanelX = actualX.int32

  # Handle dragging
  let mousePos = getVirtualMousePosition()
  let headerHeight = (DEBUG_PANEL_PADDING + DEBUG_TITLE_HEIGHT).float32
  let headerRect = Rectangle(
    x: finalPanelX.float32,
    y: yOffset.float32,
    width: debugPanelW.float32,
    height: headerHeight
  )

  # Start dragging or minimize. Widescreen renders the panel as a plain, fixed
  # section of the border-HUD column: NO click behavior at all (no drag, no
  # minimize). Classic keeps the fully draggable + minimizable floating window.
  if not anchorLeftDefault and isPointerPressed() and checkCollisionPointRec(mousePos, headerRect):
    # Check if clicking on minimize button area (right side of header)
    let minimizeButtonX = finalPanelX + debugPanelW - DEBUG_PANEL_PADDING - 12
    let minimizeButtonRect = Rectangle(
      x: minimizeButtonX.float32,
      y: (yOffset + DEBUG_PANEL_PADDING).float32,
      width: 16,
      height: DEBUG_TITLE_HEIGHT.float32
    )

    if checkCollisionPointRec(mousePos, minimizeButtonRect):
      # Toggle minimize (classic only).
      debugPanelMinimized = not debugPanelMinimized
    else:
      # Start dragging (classic only)
      debugPanelDragging = true
      debugPanelDragOffset = Vector2(
        x: mousePos.x - finalPanelX.float32,
        y: mousePos.y - yOffset.float32
      )

  # Update dragging (classic only; never drags in widescreen)
  if debugPanelDragging and not anchorLeftDefault:
    if isPointerDown():
      debugPanelPos = Vector2(
        x: mousePos.x - debugPanelDragOffset.x,
        y: mousePos.y - debugPanelDragOffset.y
      )
      # Clamp to world bounds.
      debugPanelPos.x = clamp(debugPanelPos.x, 0, (game.screenWidth - debugPanelW).float32)
      debugPanelPos.y = clamp(debugPanelPos.y, 0, (game.screenHeight - 50).float32)
    else:
      debugPanelDragging = false

  # Update positions after potential dragging. Widescreen pins the panel to a
  # fixed slot in the left gutter (below the border HUD status column).
  let sentinelX2 = debugPanelPos.x < 0
  yOffset = if anchorLeftDefault:
    340'i32
  elif sentinelX2:
    debugPanelPos.y.int32
  else:
    debugPanelPos.y.int32
  finalPanelX = if anchorLeftDefault:
    0'i32
  elif sentinelX2:
    game.screenWidth - debugPanelW
  else:
    debugPanelPos.x.int32

  # If minimized, only draw header bar (classic only; widescreen is never
  # collapsible so it always renders as a full integrated section).
  if debugPanelMinimized and not anchorLeftDefault:
    # Draw minimized panel (just header)
    drawRectangle(finalPanelX, yOffset, debugPanelW, DEBUG_PANEL_PADDING + DEBUG_TITLE_HEIGHT,
                 Color(r: 5, g: 15, b: 25, a: 45))

    # Cyan accent stripe (left edge in widescreen to match the border HUD column).
    drawRectangle((if anchorLeftDefault: finalPanelX else: finalPanelX + debugPanelW - 2),
                 yOffset, 2, DEBUG_PANEL_PADDING + DEBUG_TITLE_HEIGHT,
                 Color(r: 0, g: 220, b: 255, a: 180))

    # Panel border
    drawRectangleLines(Rectangle(x: finalPanelX.float32, y: yOffset.float32,
                                  width: debugPanelW.float32,
                                  height: (DEBUG_PANEL_PADDING + DEBUG_TITLE_HEIGHT).float32),
                      DEBUG_PANEL_BORDER, Color(r: 0, g: 220, b: 255, a: 80))

    yOffset += DEBUG_PANEL_PADDING

    # Header with minimize indicator
    drawRectangle(finalPanelX, yOffset, debugPanelW - 2, DEBUG_TITLE_HEIGHT, HEADER_BG_COLOR)

    drawText(t("debug_panel_diagnostics"), finalPanelX + DEBUG_PANEL_PADDING + 5, yOffset + 3, 11,
            Color(r: 0, g: 0, b: 0, a: 140))
    drawText(t("debug_panel_diagnostics"), finalPanelX + DEBUG_PANEL_PADDING + 4, yOffset + 2, 11, ACCENT_COLOR)

    # Draw maximize icon (square)
    let iconX = finalPanelX + debugPanelW - DEBUG_PANEL_PADDING - 12
    let iconY = yOffset + 4
    drawRectangleLines(Rectangle(x: iconX.float32, y: iconY.float32, width: 10, height: 10),
                      1, ACCENT_COLOR)

    return  # Don't draw rest of panel

  # Calculate panel height based on content - COMPACT version
  var contentHeight: int32 = DEBUG_PANEL_PADDING * 2 + DEBUG_TITLE_HEIGHT + 2  # Header (reduced spacing)

  # FPS/Entity row
  contentHeight += 18
  # upd/draw timing row
  contentHeight += 16

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
    # separator(3) + header(12) + rows + section spacing
    contentHeight += int32(15 + (activeTimers * DEBUG_LINE_HEIGHT) + DEBUG_SECTION_SPACING)

  # Always show combat stats: separator(4) + header(14) + 3 lines + trailing 6
  contentHeight += int32(18 + (DEBUG_LINE_HEIGHT * 3) + 4 + DEBUG_SECTION_SPACING)

  # Add height for rage/berserker bonuses if applicable
  let hpPercent = game.player.hp / game.player.maxHp
  if hpPercent < 0.7 and (hasPowerUp(game.player, puRage) or hasPowerUp(game.player, puBerserker)):
    var bonusCount = 0
    if hasPowerUp(game.player, puRage): bonusCount += 1
    if hasPowerUp(game.player, puBerserker): bonusCount += 1
    # separator(4) + header(14) + rows
    contentHeight += int32(18 + (bonusCount * DEBUG_LINE_HEIGHT))

  var dopamineLines = 0
  # Streak mechanic removed
  if dopamineLines > 0:
    contentHeight += int32(12 + (DEBUG_LINE_HEIGHT * dopamineLines) + 3)  # Reduced spacing

  # Real-time stats section - make it compact (only show 2 most important stats)
  contentHeight += int32(11 + (DEBUG_LINE_HEIGHT * 2) + 4)  # Reduced spacing throughout

  # Add bottom padding so text doesn't sit on border
  contentHeight += 3  # Extra pixels at bottom

  # Main panel background with gradient effect (matching other panels)
  drawRectangle(finalPanelX, yOffset, debugPanelW, contentHeight,
               Color(r: 5, g: 15, b: 25, a: 45))

  # Cyan accent stripe (left edge in widescreen to match the border HUD column).
  drawRectangle((if anchorLeftDefault: finalPanelX else: finalPanelX + debugPanelW - 2),
               yOffset, 2, contentHeight,
               Color(r: 0, g: 220, b: 255, a: 180))

  # Panel border with glow effect (cyan theme matching other panels)
  drawRectangleLines(Rectangle(x: finalPanelX.float32, y: yOffset.float32,
                                width: debugPanelW.float32, height: contentHeight.float32),
                    DEBUG_PANEL_BORDER, Color(r: 0, g: 220, b: 255, a: 80))

  yOffset += DEBUG_PANEL_PADDING

  # SYSTEM DIAGNOSTICS HEADER
  # Section header bar - same treatment as the border HUD status headers.
  drawRectangle(finalPanelX, yOffset, debugPanelW - 2, DEBUG_TITLE_HEIGHT, HEADER_BG_COLOR)

  drawText(t(tkDebugPanelDiagnostics), finalPanelX + DEBUG_PANEL_PADDING + 5, yOffset + 3, 11,
          Color(r: 0, g: 0, b: 0, a: 140))
  drawText(t(tkDebugPanelDiagnostics), finalPanelX + DEBUG_PANEL_PADDING + 4, yOffset + 2, 11, ACCENT_COLOR)

  # Draw minimize icon (horizontal line) - classic only; widescreen is a plain
  # non-interactive section, so it carries no window affordances.
  if not anchorLeftDefault:
    let iconX = finalPanelX + debugPanelW - DEBUG_PANEL_PADDING - 12
    let iconY = yOffset + 9
    drawLine(Vector2(x: iconX.float32, y: iconY.float32),
            Vector2(x: (iconX + 10).float32, y: iconY.float32),
            2, ACCENT_COLOR)

  yOffset += DEBUG_TITLE_HEIGHT + 2

  # FPS and entity count in compact single line
  let statsSectionWidth: int32 = debugPanelW - (DEBUG_PANEL_PADDING * 2) - 4
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
  let entityX = finalPanelX + debugPanelW div 2 + 2

  drawText(t(tkDebugPanelEntities) & ":", entityX + 1, yOffset + 1, 9,
          Color(r: 0, g: 0, b: 0, a: 130))
  drawText(t(tkDebugPanelEntities) & ":", entityX, yOffset, 9,
          Color(r: 180, g: 200, b: 220, a: 255))

  drawText($totalEntities, entityX + 28, yOffset + 1, 11,
          Color(r: 0, g: 0, b: 0, a: 150))
  drawText($totalEntities, entityX + 27, yOffset, 11,
          Color(r: 180, g: 100, b: 255, a: 255))

  yOffset += 18

  # Update / draw timing split (ms): shows whether simulation or rendering owns
  # the frame. The spatial-grid-accelerated loops (collision, separation, homing)
  # live in 'upd', so their effect shows there; if 'draw' dominates, the frame
  # ceiling is draw-calls, not simulation -- threading the sim would do nothing.
  block:
    let updMs = game.perfUpdateMs
    let drawMs = game.perfDrawMs
    let updColor =
      if updMs <= 4.0'f32: Color(r: 0, g: 255, b: 120, a: 255)
      elif updMs <= 9.0'f32: Color(r: 255, g: 220, b: 100, a: 255)
      else: Color(r: 255, g: 100, b: 100, a: 255)
    let drawColor =
      if drawMs <= 6.0'f32: Color(r: 0, g: 255, b: 120, a: 255)
      elif drawMs <= 12.0'f32: Color(r: 255, g: 220, b: 100, a: 255)
      else: Color(r: 255, g: 100, b: 100, a: 255)
    drawText("upd", finalPanelX + DEBUG_PANEL_PADDING + 5, yOffset, 9,
            Color(r: 180, g: 200, b: 220, a: 255))
    drawText(formatFloat(updMs.float, ffDecimal, 1) & "ms",
            finalPanelX + DEBUG_PANEL_PADDING + 30, yOffset, 10, updColor)
    drawText("draw", entityX, yOffset, 9, Color(r: 180, g: 200, b: 220, a: 255))
    drawText(formatFloat(drawMs.float, ffDecimal, 1) & "ms",
            entityX + 32, yOffset, 10, drawColor)
  yOffset += 16

  # ACTIVE EFFECTS
  if activeTimers > 0:
    # Section separator line - cyan
    drawLine(Vector2(x: (finalPanelX + DEBUG_PANEL_PADDING + 2).float32, y: yOffset.float32),
            Vector2(x: (finalPanelX + debugPanelW - DEBUG_PANEL_PADDING - 2).float32, y: yOffset.float32),
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
                   debugPanelW - (DEBUG_PANEL_PADDING * 2) - 4, DEBUG_LINE_HEIGHT,
                   Color(r: 0, g: 30, b: 40, a: 50))

      let timeLeft = game.player.speedBoostTimer.int + 1
      drawText("[>] " & t(tkDebugPanelEffectSpeed), finalPanelX + DEBUG_PANEL_PADDING + 6, yOffset + 1, 10,
              Color(r: 0, g: 0, b: 0, a: 140))
      drawText("[>] " & t(tkDebugPanelEffectSpeed), finalPanelX + DEBUG_PANEL_PADDING + 5, yOffset, 10,
              Color(r: 100, g: 220, b: 255, a: 255))

      drawText($timeLeft & "s", finalPanelX + debugPanelW - DEBUG_PANEL_PADDING - 24,
              yOffset + 1, 9, Color(r: 0, g: 0, b: 0, a: 140))
      drawText($timeLeft & "s", finalPanelX + debugPanelW - DEBUG_PANEL_PADDING - 25,
              yOffset, 9, Color(r: 180, g: 200, b: 220, a: 255))
      yOffset += DEBUG_LINE_HEIGHT

    # Invincibility - magenta color
    if game.player.invincibilityTimer > 0:
      drawRectangle(finalPanelX + DEBUG_PANEL_PADDING + 2, yOffset - 1,
                   debugPanelW - (DEBUG_PANEL_PADDING * 2) - 4, DEBUG_LINE_HEIGHT,
                   Color(r: 30, g: 0, b: 30, a: 50))

      let timeLeft = game.player.invincibilityTimer.int + 1
      drawText("[S] " & t(tkDebugPanelEffectInvuln), finalPanelX + DEBUG_PANEL_PADDING + 6, yOffset + 1, 10,
              Color(r: 0, g: 0, b: 0, a: 140))
      drawText("[S] " & t(tkDebugPanelEffectInvuln), finalPanelX + DEBUG_PANEL_PADDING + 5, yOffset, 10,
              Color(r: 255, g: 100, b: 255, a: 255))

      drawText($timeLeft & "s", finalPanelX + debugPanelW - DEBUG_PANEL_PADDING - 24,
              yOffset + 1, 9, Color(r: 0, g: 0, b: 0, a: 140))
      drawText($timeLeft & "s", finalPanelX + debugPanelW - DEBUG_PANEL_PADDING - 25,
              yOffset, 9, Color(r: 180, g: 200, b: 220, a: 255))
      yOffset += DEBUG_LINE_HEIGHT

    # Fire rate boost - orange color
    if game.player.fireRateBoostTimer > 0:
      drawRectangle(finalPanelX + DEBUG_PANEL_PADDING + 2, yOffset - 1,
                   debugPanelW - (DEBUG_PANEL_PADDING * 2) - 4, DEBUG_LINE_HEIGHT,
                   Color(r: 30, g: 20, b: 0, a: 50))

      let timeLeft = game.player.fireRateBoostTimer.int + 1
      drawText("[F] " & t(tkDebugPanelEffectFire), finalPanelX + DEBUG_PANEL_PADDING + 6, yOffset + 1, 10,
              Color(r: 0, g: 0, b: 0, a: 140))
      drawText("[F] " & t(tkDebugPanelEffectFire), finalPanelX + DEBUG_PANEL_PADDING + 5, yOffset, 10,
              Color(r: 255, g: 150, b: 50, a: 255))

      drawText($timeLeft & "s", finalPanelX + debugPanelW - DEBUG_PANEL_PADDING - 24,
              yOffset + 1, 9, Color(r: 0, g: 0, b: 0, a: 140))
      drawText($timeLeft & "s", finalPanelX + debugPanelW - DEBUG_PANEL_PADDING - 25,
              yOffset, 9, Color(r: 180, g: 200, b: 220, a: 255))
      yOffset += DEBUG_LINE_HEIGHT

    # Magnet
    if game.player.magnetTimer > 0:
      drawRectangle(finalPanelX + DEBUG_PANEL_PADDING + 3, yOffset - 1,
                   debugPanelW - (DEBUG_PANEL_PADDING * 2) - 6, DEBUG_LINE_HEIGHT,
                   Color(r: 12, g: 18, b: 28, a: 50))

      let timeLeft = game.player.magnetTimer.int + 1
      drawText("[M] " & t(tkDebugPanelEffectMagnet), finalPanelX + DEBUG_PANEL_PADDING + 8, yOffset + 1, 11,
              Color(r: 0, g: 0, b: 0, a: 140))
      drawText("[M] " & t(tkDebugPanelEffectMagnet), finalPanelX + DEBUG_PANEL_PADDING + 7, yOffset, 11,
              Color(r: 200, g: 100, b: 255, a: 255))

      drawText($timeLeft & "s", finalPanelX + debugPanelW - DEBUG_PANEL_PADDING - 30,
              yOffset + 1, 10, Color(r: 0, g: 0, b: 0, a: 140))
      drawText($timeLeft & "s", finalPanelX + debugPanelW - DEBUG_PANEL_PADDING - 31,
              yOffset, 10, Color(r: 180, g: 200, b: 220, a: 255))
      yOffset += DEBUG_LINE_HEIGHT

    # Time Warp
    if game.player.timeWarpActive:
      drawRectangle(finalPanelX + DEBUG_PANEL_PADDING + 3, yOffset - 1,
                   debugPanelW - (DEBUG_PANEL_PADDING * 2) - 6, DEBUG_LINE_HEIGHT,
                   Color(r: 18, g: 25, b: 35, a: 70))

      let timeLeft = game.player.timeWarpDuration.int + 1
      drawText("[T] " & t(tkDebugPanelEffectTimeWarp), finalPanelX + DEBUG_PANEL_PADDING + 8, yOffset + 1, 11,
              Color(r: 0, g: 0, b: 0, a: 140))
      drawText("[T] " & t(tkDebugPanelEffectTimeWarp), finalPanelX + DEBUG_PANEL_PADDING + 7, yOffset, 11,
              Color(r: 100, g: 255, b: 255, a: 255))

      drawText($timeLeft & "s", finalPanelX + debugPanelW - DEBUG_PANEL_PADDING - 30,
              yOffset + 1, 10, Color(r: 0, g: 0, b: 0, a: 140))
      drawText($timeLeft & "s", finalPanelX + debugPanelW - DEBUG_PANEL_PADDING - 31,
              yOffset, 10, Color(r: 180, g: 200, b: 220, a: 255))
      yOffset += DEBUG_LINE_HEIGHT

    # Phase Shift invulnerability
    if game.player.phaseShiftInvulnTimer > 0:
      drawRectangle(finalPanelX + DEBUG_PANEL_PADDING + 3, yOffset - 1,
                   debugPanelW - (DEBUG_PANEL_PADDING * 2) - 6, DEBUG_LINE_HEIGHT,
                   Color(r: 12, g: 18, b: 28, a: 50))

      drawText(t(tkDebugPanelEffectPhase), finalPanelX + DEBUG_PANEL_PADDING + 8, yOffset + 1, 11,
              Color(r: 0, g: 0, b: 0, a: 140))
      drawText(t(tkDebugPanelEffectPhase), finalPanelX + DEBUG_PANEL_PADDING + 7, yOffset, 11,
              Color(r: 150, g: 255, b: 200, a: 255))

      drawText(t(tkDebugPanelActive), finalPanelX + debugPanelW - DEBUG_PANEL_PADDING - 40,
              yOffset + 1, 10, Color(r: 0, g: 0, b: 0, a: 140))
      drawText(t(tkDebugPanelActive), finalPanelX + debugPanelW - DEBUG_PANEL_PADDING - 41,
              yOffset, 10, Color(r: 180, g: 200, b: 220, a: 255))
      yOffset += DEBUG_LINE_HEIGHT

    # Parry
    if game.player.parryActive:
      drawRectangle(finalPanelX + DEBUG_PANEL_PADDING + 3, yOffset - 1,
                   debugPanelW - (DEBUG_PANEL_PADDING * 2) - 6, DEBUG_LINE_HEIGHT,
                   Color(r: 18, g: 25, b: 35, a: 70))

      drawText(t(tkDebugPanelEffectParry), finalPanelX + DEBUG_PANEL_PADDING + 8, yOffset + 1, 11,
              Color(r: 0, g: 0, b: 0, a: 140))
      drawText(t(tkDebugPanelEffectParry), finalPanelX + DEBUG_PANEL_PADDING + 7, yOffset, 11,
              Color(r: 255, g: 255, b: 100, a: 255))

      drawText(t(tkDebugPanelActive), finalPanelX + debugPanelW - DEBUG_PANEL_PADDING - 40,
              yOffset + 1, 10, Color(r: 0, g: 0, b: 0, a: 140))
      drawText(t(tkDebugPanelActive), finalPanelX + debugPanelW - DEBUG_PANEL_PADDING - 41,
              yOffset, 10, Color(r: 180, g: 200, b: 220, a: 255))
      yOffset += DEBUG_LINE_HEIGHT

    yOffset += DEBUG_SECTION_SPACING

  # COMBAT STATS
  # Section separator line
  drawLine(Vector2(x: (finalPanelX + DEBUG_PANEL_PADDING + 3).float32, y: yOffset.float32),
          Vector2(x: (finalPanelX + debugPanelW - DEBUG_PANEL_PADDING - 3).float32, y: yOffset.float32),
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
               debugPanelW - (DEBUG_PANEL_PADDING * 2) - 6, DEBUG_LINE_HEIGHT * 3 + 2,
               Color(r: 15, g: 20, b: 28, a: 70))

  # Damage (multiplied by 100, showing decimals with precision)
  let damageText = formatHealthDisplay(stats.damage)
  drawText(t(tkDebugPanelDamage) & ":", finalPanelX + DEBUG_PANEL_PADDING + 8, yOffset + 1, 10,
          Color(r: 0, g: 0, b: 0, a: 130))
  drawText(t(tkDebugPanelDamage) & ":", finalPanelX + DEBUG_PANEL_PADDING + 7, yOffset, 10,
          Color(r: 180, g: 200, b: 220, a: 255))

  drawText(damageText, finalPanelX + debugPanelW - DEBUG_PANEL_PADDING - 46,
          yOffset + 1, 11, Color(r: 0, g: 0, b: 0, a: 150))
  drawText(damageText, finalPanelX + debugPanelW - DEBUG_PANEL_PADDING - 47,
          yOffset, 11, Color(r: 255, g: 150, b: 100, a: 255))
  yOffset += DEBUG_LINE_HEIGHT

  # Fire rate (shots per second)
  let shotsPerSec = 1.0 / stats.fireRate
  let fireRateText = formatFloat(shotsPerSec, ffDecimal, 2) & "/s"
  drawText(t(tkDebugPanelFireRate) & ":", finalPanelX + DEBUG_PANEL_PADDING + 8, yOffset + 1, 10,
          Color(r: 0, g: 0, b: 0, a: 130))
  drawText(t(tkDebugPanelFireRate) & ":", finalPanelX + DEBUG_PANEL_PADDING + 7, yOffset, 10,
          Color(r: 180, g: 200, b: 220, a: 255))

  drawText(fireRateText, finalPanelX + debugPanelW - DEBUG_PANEL_PADDING - 46,
          yOffset + 1, 11, Color(r: 0, g: 0, b: 0, a: 150))
  drawText(fireRateText, finalPanelX + debugPanelW - DEBUG_PANEL_PADDING - 47,
          yOffset, 11, Color(r: 255, g: 200, b: 100, a: 255))
  yOffset += DEBUG_LINE_HEIGHT

  # Speed
  let speedText = formatFloat(stats.speed, ffDecimal, 2)
  drawText(t(tkDebugPanelSpeed) & ":", finalPanelX + DEBUG_PANEL_PADDING + 8, yOffset + 1, 10,
          Color(r: 0, g: 0, b: 0, a: 130))
  drawText(t(tkDebugPanelSpeed) & ":", finalPanelX + DEBUG_PANEL_PADDING + 7, yOffset, 10,
          Color(r: 180, g: 200, b: 220, a: 255))

  drawText(speedText, finalPanelX + debugPanelW - DEBUG_PANEL_PADDING - 46,
          yOffset + 1, 11, Color(r: 0, g: 0, b: 0, a: 150))
  drawText(speedText, finalPanelX + debugPanelW - DEBUG_PANEL_PADDING - 47,
          yOffset, 11, Color(r: 100, g: 200, b: 255, a: 255))
  yOffset += DEBUG_LINE_HEIGHT + 6

  # LOW HP BONUSES
  if hpPercent < 0.7 and (hasPowerUp(game.player, puRage) or hasPowerUp(game.player, puBerserker)):
    # Section separator line
    drawLine(Vector2(x: (finalPanelX + DEBUG_PANEL_PADDING + 3).float32, y: yOffset.float32),
            Vector2(x: (finalPanelX + debugPanelW - DEBUG_PANEL_PADDING - 3).float32, y: yOffset.float32),
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
                 debugPanelW - (DEBUG_PANEL_PADDING * 2) - 6,
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
      drawText(bonusText, finalPanelX + debugPanelW - DEBUG_PANEL_PADDING - 66,
              yOffset + 1, 10, Color(r: 0, g: 0, b: 0, a: 150))
      drawText(bonusText, finalPanelX + debugPanelW - DEBUG_PANEL_PADDING - 67,
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
      drawText(bonusText, finalPanelX + debugPanelW - DEBUG_PANEL_PADDING - 66,
              yOffset + 1, 10, Color(r: 0, g: 0, b: 0, a: 150))
      drawText(bonusText, finalPanelX + debugPanelW - DEBUG_PANEL_PADDING - 67,
              yOffset, 10, Color(r: 255, g: 200, b: 150, a: 255))
      yOffset += DEBUG_LINE_HEIGHT

  # REAL-TIME STATS
  # Section separator line
  drawLine(Vector2(x: (finalPanelX + DEBUG_PANEL_PADDING + 3).float32, y: yOffset.float32),
          Vector2(x: (finalPanelX + debugPanelW - DEBUG_PANEL_PADDING - 3).float32, y: yOffset.float32),
          1, Color(r: 100, g: 200, b: 255, a: 100))
  yOffset += 3

  drawText(t("debug_panel_run_stats") & ":", finalPanelX + DEBUG_PANEL_PADDING + 6, yOffset + 1, 9,
          Color(r: 0, g: 0, b: 0, a: 130))
  drawText(t("debug_panel_run_stats") & ":", finalPanelX + DEBUG_PANEL_PADDING + 5, yOffset, 9,
          Color(r: 200, g: 220, b: 240, a: 255))
  yOffset += 11

  # Background box for real-time stats (compact - only 2 stats)
  drawRectangle(finalPanelX + DEBUG_PANEL_PADDING + 3, yOffset - 1,
               debugPanelW - (DEBUG_PANEL_PADDING * 2) - 6,
               int32((DEBUG_LINE_HEIGHT * 2) + 2),
               Color(r: 15, g: 20, b: 25, a: 80))

  let rtStats = game.dopamine.realTimeStats

  # DPS (most important combat stat)
  drawText("[X] " & t(tkDebugPanelDps) & ":", finalPanelX + DEBUG_PANEL_PADDING + 8, yOffset + 1, 9,
          Color(r: 0, g: 0, b: 0, a: 130))
  drawText("[X] " & t(tkDebugPanelDps) & ":", finalPanelX + DEBUG_PANEL_PADDING + 7, yOffset, 9,
          Color(r: 180, g: 200, b: 220, a: 255))

  let dpsText = $(int(rtStats.dps))
  drawText(dpsText, finalPanelX + debugPanelW - DEBUG_PANEL_PADDING - 50,
          yOffset + 1, 9, Color(r: 0, g: 0, b: 0, a: 150))
  drawText(dpsText, finalPanelX + debugPanelW - DEBUG_PANEL_PADDING - 51,
          yOffset, 9, Color(r: 255, g: 100, b: 100, a: 255))
  yOffset += DEBUG_LINE_HEIGHT

  # Coins per minute (economy stat)
  drawText("[$] " & t(tkDebugPanelCmin) & ":", finalPanelX + DEBUG_PANEL_PADDING + 8, yOffset + 1, 9,
          Color(r: 0, g: 0, b: 0, a: 130))
  drawText("[$] " & t(tkDebugPanelCmin) & ":", finalPanelX + DEBUG_PANEL_PADDING + 7, yOffset, 9,
          Color(r: 180, g: 200, b: 220, a: 255))

  let cpmText = $(int(rtStats.coinsPerMinute))
  drawText(cpmText, finalPanelX + debugPanelW - DEBUG_PANEL_PADDING - 50,
          yOffset + 1, 9, Color(r: 0, g: 0, b: 0, a: 150))
  drawText(cpmText, finalPanelX + debugPanelW - DEBUG_PANEL_PADDING - 51,
          yOffset, 9, Color(r: 255, g: 215, b: 0, a: 255))

proc drawLegendaryPowerUpsPanel*(game: Game, screenWidth, screenHeight: int32,
                                 alignRightGutter: bool = false) =
  ## Draw compact legendary Q ability cooldown strip.
  ## Widescreen (alignRightGutter): 2-column vertical grid confined to the
  ## right gutter. Classic: single horizontal row (unchanged).
  var panelWidth: int32 = 220

  # Check if player has any power-ups shown in the legendary panel
  var hasAnyLegendary = false
  for pt in legendaryPanelTypes:
    if hasPowerUp(game.player, pt):
      hasAnyLegendary = true
      break

  if not hasAnyLegendary:
    return

  var abilities: seq[PowerUp] = @[]
  for powerUp in game.player.powerUps:
    for pt in legendaryPanelTypes:
      if powerUp.powerType == pt:
        abilities.add(powerUp)
        break
  if abilities.len == 0:
    return

  let shownCount = min(abilities.len, 7)
  let cols: int32 = if alignRightGutter: 2'i32 else: shownCount.int32
  let rows: int32 = (shownCount.int32 + cols - 1) div cols
  let gridWidth = cols * LEGENDARY_Q_ICON_SIZE + (cols - 1) * LEGENDARY_Q_ICON_GAP
  let iconsBlockH = rows * LEGENDARY_Q_ICON_SIZE + (rows - 1) * LEGENDARY_Q_ICON_GAP
  panelWidth = if alignRightGutter:
    163'i32
  else:
    max(178'i32, gridWidth + LEGENDARY_Q_PADDING * 2 + 10)
  let qContentHeight: int32 =
    (DEBUG_PANEL_PADDING * 2 + DEBUG_TITLE_HEIGHT + 9 +
     iconsBlockH + LEGENDARY_Q_FOOTER_HEIGHT).int32

  var readyCount = 0
  for powerUp in abilities:
    let cooldown = case powerUp.powerType
      of puTimeWarp: game.player.timeWarpCooldown
      of puPhaseShift: game.player.phaseShiftCooldown
      of puParry: game.player.parryCooldown
      of puBloodPact: game.player.bloodPactCooldown
      of puConduit: game.player.conduitCooldown
      of puAftershock: game.player.aftershockCooldown
      of puNova: game.player.novaCooldown
      else: 0.0'f32
    let ready = cooldown <= 0.0'f32 and
                (case powerUp.powerType
                 of puTimeWarp: game.player.timeWarpUsesThisWave < game.player.timeWarpMaxUsesPerWave
                 of puBloodPact: game.player.hp > 1.0'f32
                 of puNova: not game.player.novaActive
                 else: true)
    if ready:
      inc readyCount

  # Calculate actual position
  # Right gutter starts just past the centered 1024-wide world.
  let rightGutterX = getWorldViewOffsetX().int32 + 1024'i32
  # Widescreen: a FIXED right-gutter section, ignoring any stored drag position.
  var actualX: int32 = if alignRightGutter:
    rightGutterX + 4'i32
  elif legendaryPanelPos.x < 0:
    screenWidth - panelWidth - 10'i32
  else:
    legendaryPanelPos.x.int32
  var actualY: int32 = if alignRightGutter:
    screenHeight - qContentHeight - 10'i32
  elif legendaryPanelPos.y < 0:
    screenHeight - qContentHeight - 10'i32  # Default bottom position
  else:
    legendaryPanelPos.y.int32

  # Handle dragging
  let mousePos = getVirtualMousePosition()
  let headerHeight = (DEBUG_PANEL_PADDING + DEBUG_TITLE_HEIGHT).float32
  let headerRect = Rectangle(
    x: actualX.float32,
    y: actualY.float32,
    width: panelWidth.float32,
    height: headerHeight
  )

  # Start dragging or minimize
  if isPointerPressed() and checkCollisionPointRec(mousePos, headerRect):
    # Check if clicking on minimize button area (right side of header)
    let minimizeButtonX = actualX + panelWidth - DEBUG_PANEL_PADDING - 12
    let minimizeButtonRect = Rectangle(
      x: minimizeButtonX.float32,
      y: (actualY + DEBUG_PANEL_PADDING).float32,
      width: 16,
      height: DEBUG_TITLE_HEIGHT.float32
    )

    if checkCollisionPointRec(mousePos, minimizeButtonRect):
      # Toggle minimize (allowed in both layouts).
      legendaryPanelMinimized = not legendaryPanelMinimized
    elif not alignRightGutter:
      # Start dragging (classic only; widescreen is a fixed gutter section).
      legendaryPanelDragging = true
      legendaryPanelDragOffset = Vector2(
        x: mousePos.x - actualX.float32,
        y: mousePos.y - actualY.float32
      )

  # Update dragging (classic only; never drags in widescreen)
  if legendaryPanelDragging and not alignRightGutter:
    if isPointerDown():
      legendaryPanelPos = Vector2(
        x: mousePos.x - legendaryPanelDragOffset.x,
        y: mousePos.y - legendaryPanelDragOffset.y
      )
      # Clamp: widescreen confines to the right gutter; classic uses full width.
      if alignRightGutter:
        legendaryPanelPos.x = clamp(legendaryPanelPos.x, rightGutterX.float32, (screenWidth - panelWidth).float32)
      else:
        legendaryPanelPos.x = clamp(legendaryPanelPos.x, 0, (screenWidth - panelWidth).float32)
      legendaryPanelPos.y = clamp(legendaryPanelPos.y, 0, (screenHeight - 50).float32)
      actualX = legendaryPanelPos.x.int32
      actualY = legendaryPanelPos.y.int32
    else:
      legendaryPanelDragging = false

  # If minimized, only draw header bar
  if legendaryPanelMinimized:
    drawRectangle(actualX, actualY, panelWidth, DEBUG_PANEL_PADDING + DEBUG_TITLE_HEIGHT,
                 Color(r: 5, g: 15, b: 25, a: 58))
    drawRectangle(actualX + panelWidth - 2, actualY, 2, DEBUG_PANEL_PADDING + DEBUG_TITLE_HEIGHT,
                 Color(r: 255, g: 215, b: 80, a: 165))
    drawRectangleLines(Rectangle(x: actualX.float32, y: actualY.float32,
                                  width: panelWidth.float32,
                                  height: (DEBUG_PANEL_PADDING + DEBUG_TITLE_HEIGHT).float32),
                      DEBUG_PANEL_BORDER, Color(r: 255, g: 215, b: 80, a: 75))
    var qYOffset = actualY + DEBUG_PANEL_PADDING
    drawRectangle(actualX, qYOffset, panelWidth - 2, DEBUG_TITLE_HEIGHT,
                  Color(r: 120, g: 86, b: 0, a: 55))
    drawText("[Q] " & t(tkDebugPanelAbilities), actualX + DEBUG_PANEL_PADDING + 5, qYOffset + 3, 11,
            Color(r: 0, g: 0, b: 0, a: 140))
    drawText("[Q] " & t(tkDebugPanelAbilities), actualX + DEBUG_PANEL_PADDING + 4, qYOffset + 2, 11,
            Color(r: 255, g: 230, b: 145, a: 255))
    let countText = $readyCount & "/" & $abilities.len
    let countW = measureText(countText, 10)
    drawText(countText, actualX + panelWidth - DEBUG_PANEL_PADDING - 24 - countW,
             qYOffset + 2, 10, Color(r: 255, g: 238, b: 170, a: 230))
    let miniIconX = actualX + panelWidth - DEBUG_PANEL_PADDING - 12
    let miniIconY = qYOffset + 4
    drawRectangleLines(Rectangle(x: miniIconX.float32, y: miniIconY.float32, width: 10, height: 10),
                      1, Color(r: 255, g: 230, b: 145, a: 255))
    return

  drawRectangle(actualX, actualY, panelWidth, qContentHeight,
                Color(r: 5, g: 15, b: 25, a: 58))
  drawRectangle(actualX, actualY + qContentHeight - 1, panelWidth, 1,
                Color(r: 255, g: 215, b: 80, a: 95))
  drawRectangle(actualX + panelWidth - 2, actualY, 2, qContentHeight,
                Color(r: 255, g: 215, b: 80, a: 165))
  drawRectangleLines(Rectangle(x: actualX.float32, y: actualY.float32,
                                width: panelWidth.float32, height: qContentHeight.float32),
                    DEBUG_PANEL_BORDER, Color(r: 255, g: 215, b: 80, a: 75))

  var qYOffset = actualY + DEBUG_PANEL_PADDING
  drawRectangle(actualX, qYOffset, panelWidth - 2, DEBUG_TITLE_HEIGHT,
                Color(r: 120, g: 86, b: 0, a: 55))
  drawText("[Q] " & t(tkDebugPanelAbilities), actualX + DEBUG_PANEL_PADDING + 5, qYOffset + 3, 11,
          Color(r: 0, g: 0, b: 0, a: 140))
  drawText("[Q] " & t(tkDebugPanelAbilities), actualX + DEBUG_PANEL_PADDING + 4, qYOffset + 2, 11,
          Color(r: 255, g: 230, b: 145, a: 255))
  let countText = $readyCount & "/" & $abilities.len
  let countW = measureText(countText, 10)
  drawText(countText, actualX + panelWidth - DEBUG_PANEL_PADDING - 24 - countW + 1,
           qYOffset + 3, 10, Color(r: 0, g: 0, b: 0, a: 130))
  drawText(countText, actualX + panelWidth - DEBUG_PANEL_PADDING - 24 - countW,
           qYOffset + 2, 10, Color(r: 255, g: 238, b: 170, a: 235))

  let miniIconX = actualX + panelWidth - DEBUG_PANEL_PADDING - 12
  let miniIconY = qYOffset + 9
  drawLine(Vector2(x: miniIconX.float32, y: miniIconY.float32),
          Vector2(x: (miniIconX + 10).float32, y: miniIconY.float32),
          2, Color(r: 255, g: 230, b: 145, a: 255))

  qYOffset += DEBUG_TITLE_HEIGHT + 6
  let iconsTop = qYOffset
  let startX = actualX + (panelWidth - gridWidth) div 2
  var hoverText = ""

  for i in 0..<shownCount:
    let powerUp = abilities[i]
    let col = i.int32 mod cols
    let row = i.int32 div cols
    let iconX = startX + col * (LEGENDARY_Q_ICON_SIZE + LEGENDARY_Q_ICON_GAP)
    let iconY = iconsTop + row * (LEGENDARY_Q_ICON_SIZE + LEGENDARY_Q_ICON_GAP)
    let accent = getPowerUpColor(powerUp.powerType)
    let cooldown = case powerUp.powerType
      of puTimeWarp: game.player.timeWarpCooldown
      of puPhaseShift: game.player.phaseShiftCooldown
      of puParry: game.player.parryCooldown
      of puBloodPact: game.player.bloodPactCooldown
      of puConduit: game.player.conduitCooldown
      of puAftershock: game.player.aftershockCooldown
      of puNova: game.player.novaCooldown
      else: 0.0'f32
    let active = (powerUp.powerType == puTimeWarp and game.player.timeWarpActive) or
                 (powerUp.powerType == puPhaseShift and game.player.phaseShiftInvulnTimer > 0.0'f32) or
                 (powerUp.powerType == puParry and game.player.parryActive) or
                 (powerUp.powerType == puNova and game.player.novaActive)
    let cooldownMax = case powerUp.powerType
      of puTimeWarp: 10.0'f32
      of puPhaseShift: 5.0'f32
      of puParry: 5.0'f32
      of puBloodPact: 3.0'f32
      of puConduit: 15.0'f32
      of puAftershock: 14.0'f32
      of puNova: 16.0'f32
      else: 1.0'f32
    let ready = cooldown <= 0.0'f32 and
                (case powerUp.powerType
                 of puTimeWarp: game.player.timeWarpUsesThisWave < game.player.timeWarpMaxUsesPerWave
                 of puBloodPact: game.player.hp > 1.0'f32
                 of puNova: not game.player.novaActive
                 else: true)
    let pulse = if ready:
      0.5'f32 + 0.5'f32 * sin(game.time * 5.0'f32 + i.float32)
    else:
      0.0'f32
    let exhausted = powerUp.powerType == puTimeWarp and
                    game.player.timeWarpUsesThisWave >= game.player.timeWarpMaxUsesPerWave
    let bgColor = if active:
      Color(r: accent.r, g: accent.g, b: accent.b, a: 96)
    elif ready:
      Color(r: accent.r, g: accent.g, b: accent.b, a: clampByte(58 + int(pulse * 32.0'f32)))
    else:
      Color(r: 12, g: 16, b: 23, a: 145)
    let borderColor = if ready or active:
      Color(r: accent.r, g: accent.g, b: accent.b, a: 220)
    else:
      Color(r: accent.r, g: accent.g, b: accent.b, a: 95)

    drawRectangle(iconX + 1, iconY + 1, LEGENDARY_Q_ICON_SIZE, LEGENDARY_Q_ICON_SIZE,
                  Color(r: 0, g: 0, b: 0, a: 85))
    drawRectangle(iconX, iconY, LEGENDARY_Q_ICON_SIZE, LEGENDARY_Q_ICON_SIZE, bgColor)
    drawRectangleLines(Rectangle(x: iconX.float32, y: iconY.float32,
                                  width: LEGENDARY_Q_ICON_SIZE.float32,
                                  height: LEGENDARY_Q_ICON_SIZE.float32),
                       1, borderColor)
    drawPowerUpIcon(iconX + 3, iconY + 3, LEGENDARY_Q_ICON_SIZE - 6, powerUp.powerType,
                    if ready or active: accent else: Color(r: accent.r, g: accent.g, b: accent.b, a: 145))

    let progress = if ready or active:
      1.0'f32
    elif cooldownMax > 0.0'f32:
      clamp(1.0'f32 - cooldown / cooldownMax, 0.0'f32, 1.0'f32)
    else:
      0.0'f32
    let progressW = max(0'i32, (LEGENDARY_Q_ICON_SIZE.float32 * progress).int32)
    if progressW > 0:
      drawRectangle(iconX, iconY + LEGENDARY_Q_ICON_SIZE - 3,
                    progressW, 3, Color(r: accent.r, g: accent.g, b: accent.b, a: 215))

    if not ready and not active:
      drawRectangle(iconX, iconY, LEGENDARY_Q_ICON_SIZE, LEGENDARY_Q_ICON_SIZE,
                    Color(r: 0, g: 0, b: 0, a: 118))
      let statusText = if exhausted:
        "0"
      elif cooldown > 0.0'f32:
        $max(1, ceil(cooldown).int)
      else:
        "--"
      let textW = measureText(statusText, 12)
      drawText(statusText, iconX + LEGENDARY_Q_ICON_SIZE div 2 - textW div 2 + 1,
               iconY + 8, 12, Color(r: 0, g: 0, b: 0, a: 200))
      drawText(statusText, iconX + LEGENDARY_Q_ICON_SIZE div 2 - textW div 2,
               iconY + 7, 12, Color(r: 230, g: 236, b: 245, a: 235))

    let iconRect = Rectangle(x: iconX.float32, y: iconY.float32,
                             width: LEGENDARY_Q_ICON_SIZE.float32,
                             height: LEGENDARY_Q_ICON_SIZE.float32)
    if checkCollisionPointRec(mousePos, iconRect):
      let stateText = if active:
        "ACTIVE"
      elif ready:
        "READY"
      elif exhausted:
        "OUT"
      elif cooldown > 0.0'f32:
        $max(1, ceil(cooldown).int) & "s"
      else:
        "--"
      hoverText = getPowerUpName(powerUp.powerType) & "  " & stateText

  qYOffset = iconsTop + iconsBlockH + 4
  let footerText = if hoverText.len > 0:
    hoverText
  elif readyCount > 0:
    $readyCount & " ready"
  else:
    "cooling down"
  var displayFooter = footerText
  let footerMaxW = panelWidth - LEGENDARY_Q_PADDING * 2
  while measureText(displayFooter, 9) > footerMaxW and displayFooter.len > 3:
    displayFooter = displayFooter[0..^2]
  if displayFooter.len < footerText.len:
    displayFooter = displayFooter[0..^2] & ".."
  let footerW = measureText(displayFooter, 9)
  drawText(displayFooter, actualX + panelWidth div 2 - footerW div 2 + 1,
           qYOffset + 1, 9, Color(r: 0, g: 0, b: 0, a: 125))
  drawText(displayFooter, actualX + panelWidth div 2 - footerW div 2,
           qYOffset, 9, Color(r: 210, g: 220, b: 235, a: 210))

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
