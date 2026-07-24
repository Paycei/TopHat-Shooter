## OS-Style System Screens
## Game Over as Modern System Crash, Victory as System Secured

import raylib, math
import ../types, ../localization, ../render_context

const
  SCREEN_WIDTH = 900
  SCREEN_HEIGHT = 600
  BUTTON_WIDTH = 220
  BUTTON_HEIGHT = 48
  STAT_LINE_HEIGHT = 32

type ButtonAccent = enum
  baNeutral,  # standard blue/grey styling
  baGreen,    # positive action (e.g. Continue from checkpoint)
  baRed       # destructive/leaving action (e.g. Exit)

proc drawModernButton(x, y, width, height: int32, text: string,
                     hotkey: string = "", isPrimary: bool = false,
                     time: float32 = 0.0, accent: ButtonAccent = baNeutral) =
  ## Draw a modern styled button for system screens

  # Button shadow
  drawRectangle(x + 3, y + 3, width, height,
               Color(r: 0, g: 0, b: 0, a: 100))

  # Button background
  let bgColor = case accent
    of baNeutral:
      if isPrimary: Color(r: 0, g: 140, b: 255, a: 255)
      else: Color(r: 55, g: 70, b: 90, a: 255)
    of baGreen:
      if isPrimary: Color(r: 0, g: 155, b: 75, a: 255)
      else: Color(r: 0, g: 105, b: 55, a: 255)
    of baRed:
      if isPrimary: Color(r: 175, g: 45, b: 45, a: 255)
      else: Color(r: 115, g: 32, b: 36, a: 255)

  drawRectangle(x, y, width, height, bgColor)

  # Top highlight
  drawRectangle(x, y, width, 2,
               Color(r: 255, g: 255, b: 255, a: 40))

  # Border with pulse for primary
  let pulse = sin(time * 4.0) * 0.3 + 0.7
  let borderColor = case accent
    of baNeutral:
      if isPrimary: Color(r: 0, g: 200, b: 255, a: uint8(220 * pulse))
      else: Color(r: 100, g: 130, b: 160, a: 255)
    of baGreen:
      if isPrimary: Color(r: 60, g: 255, b: 140, a: uint8(220 * pulse))
      else: Color(r: 40, g: 190, b: 100, a: 255)
    of baRed:
      if isPrimary: Color(r: 255, g: 110, b: 110, a: uint8(220 * pulse))
      else: Color(r: 210, g: 80, b: 80, a: 255)

  let borderWidth = if isPrimary: 2.5 else: 2.0
  drawRectangleLines(Rectangle(x: x.float32, y: y.float32,
                                width: width.float32, height: height.float32),
                    borderWidth, borderColor)

  # Button text. When a hotkey hint is present we stack two centered lines
  # (16px label + 12px hint with a 4px gap); otherwise the label is vertically
  # centered on its own. Previously both were positioned independently and the
  # label (ending at y+30) collided with the hint (drawn at y+30).
  let textWidth = measureText(text, 16)
  let textX = x + (width - textWidth) div 2
  let labelY = if hotkey.len > 0: y + 7 else: y + (height - 16) div 2

  # Shadow for text
  drawText(text, textX + 1, labelY + 1, 16, Color(r: 0, g: 0, b: 0, a: 120))
  drawText(text, textX, labelY, 16, White)

  # Hotkey hint
  if hotkey.len > 0:
    let hkWidth = measureText(hotkey, 12)
    let hkX = x + (width - hkWidth) div 2
    drawText(hotkey, hkX, labelY + 20, 12,
            Color(r: 200, g: 210, b: 220, a: 255))

proc drawStat(x, y: int32, label, value: string, icon: string = "-",
              valueColor: Color = White) =
  ## Draw a formatted stat line with icon
  drawText(icon, x, y, 16, Color(r: 0, g: 180, b: 255, a: 255))
  drawText(label, x + 30, y + 2, 15, Color(r: 180, g: 190, b: 200, a: 255))

  drawText(value, x + 450, y + 2, 15, valueColor)

proc deathCauseVerbKey(cause: DeathCause): TranslationKey =
  ## Verb phrase describing how the player died.
  case cause
  of dcContact: tkDeathContact
  of dcBossContact: tkDeathBossContact
  of dcProjectile: tkDeathProjectile
  of dcLaser: tkDeathLaser
  of dcExplosion: tkDeathExplosion
  of dcMeteorite: tkDeathMeteorite
  of dcPoison: tkDeathPoison
  of dcHazard: tkDeathHazard
  of dcUnknown: tkDeathUnknown

proc composeDeathCause(game: Game): tuple[verb: string, killer: string, isBoss: bool] =
  ## Splits the death message into a verb phrase and a (possibly empty) killer name.
  ## Hazard/unknown are complete sentences with no killer. A name-requiring cause
  ## that resolved no name (e.g. 3D boss with no live boss) degrades to "unknown".
  let verbKey = deathCauseVerbKey(game.deathCause)
  if game.deathCause in {dcHazard, dcUnknown}:
    return (t(verbKey), "", false)
  if game.deathSourceName.len == 0:
    return (t(tkDeathUnknown), "", false)
  return (t(verbKey), game.deathSourceName, game.deathSourceWasBoss)

proc drawSystemCrash*(game: Game, selectedButton: int = 0,
                      showContinue: bool = false, continueWave: int = 1) =
  ## Draw the enhanced Game Over screen as a modern system crash.
  ## Without a checkpoint: 0=Restart, 1=Stats, 2=Exit.
  ## With a checkpoint (showContinue): 0=Continue, 1=Restart, 2=Stats, 3=Exit.
  let screenWidth = getVirtualScreenWidth()
  let screenHeight = getVirtualScreenHeight()

  # Animated scan lines effect
  for i in 0..<(screenHeight div 4):
    let lineY = i * 4 + int32(game.time * 100.0) mod 4
    let alpha = uint8(5 + sin(game.time * 2.0 + i.float32) * 5.0)
    drawRectangle(0, lineY, screenWidth, 2,
                 Color(r: 20, g: 50, b: 90, a: alpha))

  # Full screen dark blue background (modern BSOD style)
  drawRectangle(0, 0, screenWidth, screenHeight,
               Color(r: 12, g: 35, b: 68, a: 250))

  # Calculate center position
  let windowX = (screenWidth - SCREEN_WIDTH) div 2
  let windowY = (screenHeight - SCREEN_HEIGHT) div 2

  # Error window with modern styling
  drawRectangle(windowX - 10, windowY - 10, SCREEN_WIDTH + 20, SCREEN_HEIGHT + 20,
               Color(r: 18, g: 45, b: 85, a: 255))

  # Window border
  drawRectangleLines(Rectangle(x: (windowX - 10).float32, y: (windowY - 10).float32,
                                width: (SCREEN_WIDTH + 20).float32,
                                height: (SCREEN_HEIGHT + 20).float32),
                    3, Color(r: 60, g: 120, b: 200, a: 255))

  var yOffset = windowY + 28

  # Header row: glitchy sad face + title, with a danger icon on the right
  let pulse = sin(game.time * 2.0) * 0.2 + 0.8
  let faceX = windowX + 30
  drawText(":(", faceX, yOffset, 64,
          Color(r: uint8(210 * pulse), g: uint8(90 * pulse), b: uint8(95 * pulse), a: 255))

  drawText(t(tkGameOverCriticalFailure), faceX + 92, yOffset + 10, 34,
          Color(r: 255, g: 95, b: 95, a: 255))

  let iconBoxX = windowX + SCREEN_WIDTH - 108
  drawRectangle(iconBoxX, yOffset, 78, 78, Color(r: 60, g: 24, b: 28, a: 255))
  drawRectangleLines(Rectangle(x: iconBoxX.float32, y: yOffset.float32, width: 78.0, height: 78.0),
                    2, Color(r: 220, g: 80, b: 80, a: 255))
  drawText("[X]", iconBoxX + 15, yOffset + 17, 44, Color(r: 255, g: 120, b: 120, a: 255))

  yOffset += 86

  # Short subtitle
  drawText(t(tkGameOverErrorMsg), windowX + 30, yOffset, 16,
          Color(r: 210, g: 220, b: 235, a: 255))
  yOffset += 30

  # Cause of termination banner (headline of the redesign)
  let cause = composeDeathCause(game)
  const bannerH = 66
  let bannerPulse = sin(game.time * 3.0) * 0.25 + 0.75
  drawRectangle(windowX + 30, yOffset, SCREEN_WIDTH - 60, bannerH,
               Color(r: 46, g: 18, b: 22, a: 255))
  drawRectangleLines(Rectangle(x: (windowX + 30).float32, y: yOffset.float32,
                                width: (SCREEN_WIDTH - 60).float32, height: bannerH.float32),
                    2.0, Color(r: uint8(255 * bannerPulse), g: 70, b: 70, a: 255))
  drawText("[X]", windowX + 48, yOffset + 18, 30, Color(r: 255, g: 90, b: 90, a: 255))
  drawText(t(tkGameOverCauseLabel), windowX + 98, yOffset + 12, 13,
          Color(r: 205, g: 150, b: 150, a: 255))

  let verbX = windowX + 98
  drawText(cause.verb, verbX, yOffset + 32, 22, Color(r: 235, g: 235, b: 240, a: 255))
  if cause.killer.len > 0:
    let verbW = measureText(cause.verb, 22)
    let nameColor = if cause.isBoss: Color(r: 255, g: 170, b: 40, a: 255)
                    else: Color(r: 255, g: 120, b: 120, a: 255)
    drawText(cause.killer, verbX + verbW + 10, yOffset + 32, 22, nameColor)
    if cause.isBoss:
      # Boss tag pill after the name
      let nameW = measureText(cause.killer, 22)
      let tag = t(tkDeathBossTag)
      let tagX = verbX + verbW + 10 + nameW + 12
      let tagW = measureText(tag, 13) + 16
      drawRectangle(tagX, yOffset + 35, tagW, 20, Color(r: 255, g: 170, b: 40, a: 255))
      drawText(tag, tagX + 8, yOffset + 37, 13, Color(r: 40, g: 20, b: 0, a: 255))
  yOffset += bannerH + 18

  # Error code line (thin, themed)
  drawRectangle(windowX + 30, yOffset, SCREEN_WIDTH - 60, 30,
               Color(r: 25, g: 45, b: 75, a: 255))
  drawRectangleLines(Rectangle(x: (windowX + 30).float32, y: yOffset.float32,
                                width: (SCREEN_WIDTH - 60).float32, height: 30.0),
                    1, Color(r: 60, g: 100, b: 160, a: 255))
  drawText("[!]", windowX + 40, yOffset + 6, 16, Color(r: 255, g: 200, b: 100, a: 255))
  drawText(t(tkGameOverErrorCode), windowX + 66, yOffset + 8, 14,
          Color(r: 230, g: 235, b: 245, a: 255))
  yOffset += 46

  # Session diagnostics (the translation already includes the "=== ... ==="
  # decoration, mirroring the victory screen's report header).
  drawText(t(tkGameOverSessionDiagnostics), windowX + 30, yOffset, 16,
          Color(r: 150, g: 180, b: 220, a: 255))
  yOffset += 30

  # Format time
  let minutes = (game.time / 60.0).int
  let seconds = (game.time mod 60.0).int
  let timeText = (if minutes < 10: "0" else: "") & $minutes & ":" &
                 (if seconds < 10: "0" else: "") & $seconds

  drawStat(windowX + 40, yOffset, t(tkGameOverWaveReached), $game.currentWave, ">",
          Color(r: 255, g: 200, b: 100, a: 255))
  yOffset += STAT_LINE_HEIGHT
  drawStat(windowX + 40, yOffset, t(tkGameOverSystemUptime), timeText, "[T]",
          Color(r: 150, g: 200, b: 255, a: 255))
  yOffset += STAT_LINE_HEIGHT
  drawStat(windowX + 40, yOffset, t(tkGameOverThreatsEliminated), $game.player.kills, "[X]",
          Color(r: 255, g: 150, b: 150, a: 255))
  yOffset += STAT_LINE_HEIGHT
  drawStat(windowX + 40, yOffset, t(tkVictoryBossesDefeated), $game.bossCount, "[B]",
          Color(r: 255, g: 180, b: 120, a: 255))
  yOffset += STAT_LINE_HEIGHT
  drawStat(windowX + 40, yOffset, t(tkGameOverResourcesCollected), $game.player.coins, "[$]",
          Color(r: 255, g: 215, b: 0, a: 255))
  yOffset += STAT_LINE_HEIGHT

  # Action buttons section - Positioned at bottom with proper spacing.
  # A death-surviving block checkpoint prepends a "Continue (Wave N)" button,
  # shifting the other three indices up by one; the layout narrows to fit four.
  let buttonY = windowY + SCREEN_HEIGHT - 100  # 100px from bottom (plenty of space now)
  let buttonSpacing = if showContinue: 24 else: 40
  let buttonW = if showContinue: 200 else: BUTTON_WIDTH
  let buttonCount = if showContinue: 4 else: 3
  let idxOff = if showContinue: 1 else: 0
  let totalButtonWidth = buttonW * buttonCount + buttonSpacing * (buttonCount - 1)
  let buttonsX = (screenWidth - totalButtonWidth) div 2

  if showContinue:
    # Continue button (0)
    drawModernButton(int32(buttonsX), buttonY, int32(buttonW), int32(BUTTON_HEIGHT),
                    t(tkGameOverContinue) & " " & $continueWave & ")", "[C]",
                    selectedButton == 0, game.time, baGreen)

  # Restart button
  let restartX = buttonsX + idxOff * (buttonW + buttonSpacing)
  drawModernButton(int32(restartX), buttonY, int32(buttonW), int32(BUTTON_HEIGHT),
                  t(tkGameOverRestartSystem), "[R] [SPACE]", selectedButton == idxOff, game.time)

  # View Stats button
  let statsX = restartX + buttonW + buttonSpacing
  drawModernButton(int32(statsX), buttonY, int32(buttonW), int32(BUTTON_HEIGHT),
                  t(tkGameOverViewLogs), "[V] [TAB]", selectedButton == idxOff + 1, game.time)

  # Exit button
  let exitX = statsX + buttonW + buttonSpacing
  drawModernButton(int32(exitX), buttonY, int32(buttonW), int32(BUTTON_HEIGHT),
                  t(tkGameOverExit), "[ESC] [Q]", selectedButton == idxOff + 2, game.time,
                  baRed)

  # Footer warning text
  let footerY = windowY + SCREEN_HEIGHT - 35
  drawRectangle(windowX, footerY, SCREEN_WIDTH, 35,
               Color(r: 30, g: 60, b: 110, a: 255))

  let footerText = t(tkGameOverSystemFailedFooter)
  let footerWidth = measureText(footerText, 13)
  drawText(footerText, windowX + (SCREEN_WIDTH - footerWidth) div 2, footerY + 10, 13,
          Color(r: 180, g: 190, b: 200, a: 255))

proc drawSystemSecured*(game: Game, selectedButton: int = 0) =
  ## Draw the wave-60 final-boss Victory screen as "system secured".
  ## selectedButton: 0=Continue Endless, 1=View Stats, 2=Return to Menu
  let screenWidth = getVirtualScreenWidth()
  let screenHeight = getVirtualScreenHeight()

  # Animated background particles (success effect)
  for i in 0..30:
    let particleTime = game.time + i.float32 * 0.3
    let x = int32((sin(particleTime * 0.8 + i.float32) * 0.5 + 0.5) * screenWidth.float32)
    let y = int32(((particleTime * 50.0) mod screenHeight.float32))
    let alpha = uint8(30 + sin(particleTime * 3.0) * 20.0)

    drawRectangle(x, y, 2, 2, Color(r: 100, g: 255, b: 150, a: alpha))

  # Dark background with green tint
  drawRectangle(0, 0, screenWidth, screenHeight,
               Color(r: 10, g: 28, b: 18, a: 250))

  # Calculate center position
  let windowX = (screenWidth - SCREEN_WIDTH) div 2
  let windowY = (screenHeight - SCREEN_HEIGHT) div 2

  # Success window background with glow
  let glowPulse = sin(game.time * 2.5) * 0.15 + 0.85
  drawRectangle(windowX - 15, windowY - 15, SCREEN_WIDTH + 30, SCREEN_HEIGHT + 30,
               Color(r: uint8(0 * glowPulse), g: uint8(255 * glowPulse),
                     b: uint8(100 * glowPulse), a: 40))

  drawRectangle(windowX - 10, windowY - 10, SCREEN_WIDTH + 20, SCREEN_HEIGHT + 20,
               Color(r: 20, g: 40, b: 30, a: 255))

  # Window border with glow
  drawRectangleLines(Rectangle(x: (windowX - 10).float32, y: (windowY - 10).float32,
                                width: (SCREEN_WIDTH + 20).float32,
                                height: (SCREEN_HEIGHT + 20).float32),
                    3, Color(r: 0, g: 255, b: 120, a: 255))

  var yOffset = windowY + 30

  # Success checkmark with animated glow
  let checkSize = 80
  let checkX = windowX + 30
  let checkPulse = sin(game.time * 3.0) * 0.2 + 0.8

  # Glow effect: each larger layer is centered on the base glyph so the halo
  # stays symmetric instead of smearing down-right (text grows from its anchor).
  let baseW = measureText("[OK]", checkSize.int32)
  let centerX = checkX + baseW div 2
  let centerY = yOffset + checkSize.int32 div 2
  for i in 1..3:
    let layerSize = (checkSize + i * 10).int32
    let layerW = measureText("[OK]", layerSize)
    drawText("[OK]", centerX - layerW div 2, centerY - layerSize div 2,
            layerSize,
            Color(r: 0, g: uint8(255 * checkPulse), b: uint8(120 * checkPulse),
                  a: uint8(30 / i.float32)))

  drawText("[OK]", checkX, yOffset, checkSize.int32,
          Color(r: 0, g: 255, b: 120, a: 255))

  # Success icon box
  let iconBoxX = windowX + SCREEN_WIDTH - 120
  drawRectangle(iconBoxX, yOffset, 100, 100,
               Color(r: 25, g: 50, b: 35, a: 255))
  drawRectangleLines(Rectangle(x: iconBoxX.float32, y: yOffset.float32,
                                width: 100.0, height: 100.0),
                    2, Color(r: 0, g: 200, b: 100, a: 255))
  drawText("[OK]", iconBoxX + 25, yOffset + 20, 60,
          Color(r: 100, g: 255, b: 150, a: 255))

  yOffset += 110

  # Main victory message
  let successTitle = t(tkVictoryTitle)
  drawText(successTitle, windowX + 30, yOffset, 40,
          Color(r: 100, g: 255, b: 150, a: 255))
  yOffset += 50

  # Congratulatory subtitle
  drawText(t(tkVictorySubtitle), windowX + 30, yOffset, 18,
          Color(r: 200, g: 255, b: 220, a: 255))
  yOffset += 36

  # Status box
  drawRectangle(windowX + 30, yOffset, SCREEN_WIDTH - 60, 35,
               Color(r: 25, g: 45, b: 35, a: 255))
  drawRectangleLines(Rectangle(x: (windowX + 30).float32, y: yOffset.float32,
                                width: (SCREEN_WIDTH - 60).float32, height: 35.0),
                    1, Color(r: 0, g: 180, b: 100, a: 255))

  let statusIconX = windowX + 40
  drawText("[OK]", statusIconX, yOffset + 6, 20, Color(r: 100, g: 255, b: 150, a: 255))
  # Place the label after the measured icon width (+ padding) so the 4-char
  # "[OK]" token can't bleed into the status text.
  let statusTextX = statusIconX + measureText("[OK]", 20) + 14
  drawText(t(tkVictoryStatus),
          statusTextX, yOffset + 10, 14,
          Color(r: 200, g: 255, b: 220, a: 255))
  yOffset += 50

  # Final diagnostics header
  drawText(t(tkVictoryReportHeader), windowX + 30, yOffset, 16,
          Color(r: 150, g: 220, b: 180, a: 255))
  yOffset += 32

  # Format time
  let minutes = (game.time / 60.0).int
  let seconds = (game.time mod 60.0).int
  let timeText = (if minutes < 10: "0" else: "") & $minutes & ":" &
                 (if seconds < 10: "0" else: "") & $seconds

  # Draw statistics with icons and tree structure.
  # currentWave is already incremented past the boss wave when we get here,
  # so the cleared-wave count is currentWave - 1 (= 60 for the final boss).
  let wavesCleared = max(0, game.currentWave - 1)
  drawStat(windowX + 40, yOffset, t(tkGameOverWavesSurvived), $wavesCleared, "|-",
          Color(r: 150, g: 255, b: 180, a: 255))
  yOffset += STAT_LINE_HEIGHT

  drawStat(windowX + 40, yOffset, t(tkGameOverThreatsEliminated), $game.player.kills, "|-",
          Color(r: 150, g: 255, b: 180, a: 255))
  yOffset += STAT_LINE_HEIGHT

  drawStat(windowX + 40, yOffset, t(tkVictoryBossesDefeated), $game.bossCount, "|-",
          Color(r: 255, g: 180, b: 120, a: 255))
  yOffset += STAT_LINE_HEIGHT

  drawStat(windowX + 40, yOffset, t(tkGameOverResourcesCollected), $game.player.coins, "|-",
          Color(r: 255, g: 215, b: 0, a: 255))
  yOffset += STAT_LINE_HEIGHT

  drawStat(windowX + 40, yOffset, t(tkGameOverMissionDuration), timeText, "\\-",
          Color(r: 150, g: 200, b: 255, a: 255))
  yOffset += 40

  # Action buttons section
  let buttonY = windowY + SCREEN_HEIGHT - 100
  let buttonSpacing = 40
  let totalButtonWidth = BUTTON_WIDTH * 3 + buttonSpacing * 2
  let buttonsX = (screenWidth - totalButtonWidth) div 2

  # Continue Endless button (0)
  drawModernButton(int32(buttonsX), buttonY, int32(BUTTON_WIDTH), int32(BUTTON_HEIGHT),
                  t(tkVictoryContinueEndless), "[SPACE]", selectedButton == 0, game.time)

  # View Stats button (1)
  let statsX = buttonsX + BUTTON_WIDTH + buttonSpacing
  drawModernButton(int32(statsX), buttonY, int32(BUTTON_WIDTH), int32(BUTTON_HEIGHT),
                  t(tkVictoryViewStats), "[V] [TAB]", selectedButton == 1, game.time)

  # Return to Menu button (2)
  let exitX = statsX + BUTTON_WIDTH + buttonSpacing
  drawModernButton(int32(exitX), buttonY, int32(BUTTON_WIDTH), int32(BUTTON_HEIGHT),
                  t(tkVictoryReturnMenu), "[ESC] [Q]", selectedButton == 2, game.time)

  # Footer success text
  let footerY = windowY + SCREEN_HEIGHT - 35
  drawRectangle(windowX, footerY, SCREEN_WIDTH, 35,
               Color(r: 30, g: 60, b: 45, a: 255))

  # On the run that first earned the kernel tophat, the footer announces the
  # secret unlock instead of the endless-mode hint.
  if game.tophatJustUnlocked:
    let secretText = t("victory_secret_unlocked")
    let secretWidth = measureText(secretText, 13)
    let secretPulse = sin(game.time * 4.0) * 0.5 + 0.5
    drawText(secretText, windowX + (SCREEN_WIDTH - secretWidth) div 2, footerY + 10, 13,
            Color(r: uint8(120 + secretPulse * 135), g: 255, b: 255, a: 255))
  else:
    let footerText = t(tkVictoryFooter)
    let footerWidth = measureText(footerText, 13)
    drawText(footerText, windowX + (SCREEN_WIDTH - footerWidth) div 2, footerY + 10, 13,
            Color(r: 180, g: 220, b: 190, a: 255))
