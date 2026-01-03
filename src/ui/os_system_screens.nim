## OS-Style System Screens - Enhanced Edition
## Game Over as Modern System Crash, Victory as System Secured
## REDESIGNED with improved visuals, animations, and polish

import raylib, types, math

const
  SCREEN_WIDTH = 900
  SCREEN_HEIGHT = 550
  BUTTON_WIDTH = 220
  BUTTON_HEIGHT = 48
  STAT_LINE_HEIGHT = 32

proc drawModernButton(x, y, width, height: int32, text: string, 
                     hotkey: string = "", isPrimary: bool = false,
                     time: float32 = 0.0) =
  ## Draw a modern styled button for system screens
  
  # Button shadow
  drawRectangle(x + 3, y + 3, width, height,
               Color(r: 0, g: 0, b: 0, a: 100))
  
  # Button background
  let bgColor = if isPrimary:
    Color(r: 0, g: 140, b: 255, a: 255)
  else:
    Color(r: 55, g: 70, b: 90, a: 255)
  
  drawRectangle(x, y, width, height, bgColor)
  
  # Top highlight
  drawRectangle(x, y, width, 2,
               Color(r: 255, g: 255, b: 255, a: 40))
  
  # Border with pulse for primary
  let borderColor = if isPrimary:
    let pulse = sin(time * 4.0) * 0.3 + 0.7
    Color(r: 0, g: 200, b: 255, a: uint8(220 * pulse))
  else:
    Color(r: 100, g: 130, b: 160, a: 255)
  
  let borderWidth = if isPrimary: 2.5 else: 2.0
  drawRectangleLines(Rectangle(x: x.float32, y: y.float32,
                                width: width.float32, height: height.float32),
                    borderWidth, borderColor)
  
  # Button text
  let textWidth = measureText(text, 16)
  let textX = x + (width - textWidth) div 2
  
  # Shadow for text
  drawText(text, textX + 1, y + 15, 16, Color(r: 0, g: 0, b: 0, a: 120))
  drawText(text, textX, y + 14, 16, White)
  
  # Hotkey hint
  if hotkey.len > 0:
    let hkWidth = measureText(hotkey, 12)
    let hkX = x + (width - hkWidth) div 2
    drawText(hotkey, hkX, y + height - 18, 12,
            Color(r: 200, g: 210, b: 220, a: 255))

proc drawStat(x, y: int32, label, value: string, icon: string = "•",
              valueColor: Color = White) =
  ## Draw a formatted stat line with icon
  drawText(icon, x, y, 16, Color(r: 0, g: 180, b: 255, a: 255))
  drawText(label, x + 30, y + 2, 15, Color(r: 180, g: 190, b: 200, a: 255))
  
  let valueWidth = measureText(value, 15)
  drawText(value, x + 450, y + 2, 15, valueColor)

proc drawSystemCrash*(game: Game) =
  ## Draw the enhanced Game Over screen as a modern system crash
  let screenWidth = game.screenWidth
  let screenHeight = game.screenHeight
  
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
  
  var yOffset = windowY + 30
  
  # Sad face emoticon with glow
  let faceSize = 80
  let faceX = windowX + 30
  let pulse = sin(game.time * 2.0) * 0.2 + 0.8
  
  drawText(":(", faceX, yOffset, int32(faceSize),
          Color(r: uint8(180 * pulse), g: uint8(200 * pulse), 
                b: uint8(220 * pulse), a: 255))
  
  # Error icon box
  let iconBoxX = windowX + SCREEN_WIDTH - 120
  drawRectangle(iconBoxX, yOffset, 100, 100,
               Color(r: 25, g: 55, b: 100, a: 255))
  drawRectangleLines(Rectangle(x: iconBoxX.float32, y: yOffset.float32,
                                width: 100.0, height: 100.0),
                    2, Color(r: 80, g: 140, b: 220, a: 255))
  drawText("[!]", iconBoxX + 25, yOffset + 20, 60,
          Color(r: 255, g: 200, b: 100, a: 255))
  
  yOffset += 110
  
  # Main error message with better typography
  let errorTitle = "CRITICAL SYSTEM FAILURE"
  drawText(errorTitle, windowX + 30, yOffset, 40,
          Color(r: 255, g: 100, b: 100, a: 255))
  yOffset += 55
  
  # Error subtitle
  drawText("Your system has encountered a critical error and needs to reboot.",
          windowX + 30, yOffset, 18, Color(r: 220, g: 230, b: 240, a: 255))
  yOffset += 28
  drawText("All defensive processes have been terminated.",
          windowX + 30, yOffset, 18, Color(r: 220, g: 230, b: 240, a: 255))
  yOffset += 50
  
  # Error code section
  drawRectangle(windowX + 30, yOffset, SCREEN_WIDTH - 60, 35,
               Color(r: 25, g: 45, b: 75, a: 255))
  drawRectangleLines(Rectangle(x: (windowX + 30).float32, y: yOffset.float32,
                                width: (SCREEN_WIDTH - 60).float32, height: 35.0),
                    1, Color(r: 60, g: 100, b: 160, a: 255))
  
  drawText("[!]", windowX + 40, yOffset + 8, 18, Color(r: 255, g: 200, b: 100, a: 255))
  drawText("ERROR CODE: INTEGRITY_DEPLETED_0x00000000", 
          windowX + 70, yOffset + 10, 14,
          Color(r: 255, g: 255, b: 255, a: 255))
  yOffset += 55
  
  # Session statistics header
  drawText("=== SESSION DIAGNOSTICS ===", windowX + 30, yOffset, 16,
          Color(r: 150, g: 180, b: 220, a: 255))
  yOffset += 35
  
  # Format time
  let minutes = (game.time / 60.0).int
  let seconds = (game.time mod 60.0).int
  let timeText = (if minutes < 10: "0" else: "") & $minutes & ":" & 
                 (if seconds < 10: "0" else: "") & $seconds
  
  # Draw statistics with icons
  drawStat(windowX + 40, yOffset, "Wave Reached:", $game.currentWave, ">",
          Color(r: 255, g: 200, b: 100, a: 255))
  yOffset += STAT_LINE_HEIGHT
  
  drawStat(windowX + 40, yOffset, "System Uptime:", timeText, "[T]",
          Color(r: 150, g: 200, b: 255, a: 255))
  yOffset += STAT_LINE_HEIGHT
  
  drawStat(windowX + 40, yOffset, "Threats Eliminated:", $game.player.kills, "[X]",
          Color(r: 255, g: 150, b: 150, a: 255))
  yOffset += STAT_LINE_HEIGHT
  
  drawStat(windowX + 40, yOffset, "Resources Collected:", $game.player.coins, "[$]",
          Color(r: 255, g: 215, b: 0, a: 255))
  yOffset += 50
  
  # Action buttons section
  let buttonY = windowY + SCREEN_HEIGHT - 100
  let buttonSpacing = 40
  let totalButtonWidth = BUTTON_WIDTH * 3 + buttonSpacing * 2
  let buttonsX = (screenWidth - totalButtonWidth) div 2
  
  # Restart button (primary)
  drawModernButton(int32(buttonsX), buttonY, int32(BUTTON_WIDTH), int32(BUTTON_HEIGHT),
                  "[R] RESTART SYSTEM", "[SPACE]", true, game.time)
  
  # View Stats button
  let statsX = buttonsX + BUTTON_WIDTH + buttonSpacing
  drawModernButton(int32(statsX), buttonY, int32(BUTTON_WIDTH), int32(BUTTON_HEIGHT),
                  "[V] VIEW LOGS", "[TAB]", false, game.time)
  
  # Exit button
  let exitX = statsX + BUTTON_WIDTH + buttonSpacing
  drawModernButton(int32(exitX), buttonY, int32(BUTTON_WIDTH), int32(BUTTON_HEIGHT),
                  "EXIT", "[ESC]", false, game.time)
  
  # Footer warning text
  let footerY = windowY + SCREEN_HEIGHT - 35
  drawRectangle(windowX, footerY, SCREEN_WIDTH, 35,
               Color(r: 30, g: 60, b: 110, a: 255))
  
  let footerText = "[!] System will remain in failed state until manual restart"
  let footerWidth = measureText(footerText, 13)
  drawText(footerText, windowX + (SCREEN_WIDTH - footerWidth) div 2, footerY + 10, 13,
          Color(r: 180, g: 190, b: 200, a: 255))

proc drawSystemSecured*(game: Game) =
  ## Draw the enhanced Victory screen as system secured
  let screenWidth = game.screenWidth
  let screenHeight = game.screenHeight
  
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
  
  # Glow effect
  for i in 1..3:
    let offset = i * 10
    drawText("✓", int32(checkX - offset div 2), int32(yOffset - offset div 2), 
            int32(checkSize + offset), 
            Color(r: 0, g: uint8(255 * checkPulse), b: uint8(120 * checkPulse), 
                  a: uint8(30 / i.float32)))
  
  drawText("✓", checkX, yOffset, checkSize.int32,
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
  
  # Main success message
  let successTitle = "ALL THREATS NEUTRALIZED"
  drawText(successTitle, windowX + 30, yOffset, 40,
          Color(r: 100, g: 255, b: 150, a: 255))
  yOffset += 55
  
  # Success subtitle
  let statusLine = "SYSTEM STATUS: ● SECURE"
  drawText(statusLine, windowX + 30, yOffset, 24,
          Color(r: 150, g: 255, b: 180, a: 255))
  yOffset += 50
  
  # Status box
  drawRectangle(windowX + 30, yOffset, SCREEN_WIDTH - 60, 35,
               Color(r: 25, g: 45, b: 35, a: 255))
  drawRectangleLines(Rectangle(x: (windowX + 30).float32, y: yOffset.float32,
                                width: (SCREEN_WIDTH - 60).float32, height: 35.0),
                    1, Color(r: 0, g: 180, b: 100, a: 255))
  
  drawText("✓", windowX + 40, yOffset + 6, 20, Color(r: 100, g: 255, b: 150, a: 255))
  drawText("SECURITY LEVEL: MAXIMUM | ALL PROCESSES STABLE", 
          windowX + 70, yOffset + 10, 14,
          Color(r: 200, g: 255, b: 220, a: 255))
  yOffset += 55
  
  # Performance report header
  drawText("=== PERFORMANCE REPORT ===", windowX + 30, yOffset, 16,
          Color(r: 150, g: 220, b: 180, a: 255))
  yOffset += 35
  
  # Format time
  let minutes = (game.time / 60.0).int
  let seconds = (game.time mod 60.0).int
  let timeText = (if minutes < 10: "0" else: "") & $minutes & ":" & 
                 (if seconds < 10: "0" else: "") & $seconds
  
  # Draw statistics with icons and tree structure
  drawStat(windowX + 40, yOffset, "Waves Survived:", $game.currentWave, "├",
          Color(r: 150, g: 255, b: 180, a: 255))
  yOffset += STAT_LINE_HEIGHT
  
  drawStat(windowX + 40, yOffset, "Threats Eliminated:", $game.player.kills, "├",
          Color(r: 150, g: 255, b: 180, a: 255))
  yOffset += STAT_LINE_HEIGHT
  
  drawStat(windowX + 40, yOffset, "Resources Collected:", $game.player.coins, "├",
          Color(r: 255, g: 215, b: 0, a: 255))
  yOffset += STAT_LINE_HEIGHT
  
  drawStat(windowX + 40, yOffset, "Mission Duration:", timeText, "└",
          Color(r: 150, g: 200, b: 255, a: 255))
  yOffset += 50
  
  # Action buttons section
  let buttonY = windowY + SCREEN_HEIGHT - 100
  let buttonSpacing = 40
  let totalButtonWidth = BUTTON_WIDTH * 3 + buttonSpacing * 2
  let buttonsX = (screenWidth - totalButtonWidth) div 2
  
  # Continue button (primary)
  drawModernButton(int32(buttonsX), buttonY, int32(BUTTON_WIDTH), int32(BUTTON_HEIGHT),
                  "> CONTINUE", "[SPACE]", true, game.time)
  
  # Save Stats button
  let saveX = buttonsX + BUTTON_WIDTH + buttonSpacing
  drawModernButton(int32(saveX), buttonY, int32(BUTTON_WIDTH), int32(BUTTON_HEIGHT),
                  "[S] SAVE LOG", "[TAB]", false, game.time)
  
  # Exit button
  let exitX = saveX + BUTTON_WIDTH + buttonSpacing
  drawModernButton(int32(exitX), buttonY, int32(BUTTON_WIDTH), int32(BUTTON_HEIGHT),
                  "EXIT", "[ESC]", false, game.time)
  
  # Footer success text
  let footerY = windowY + SCREEN_HEIGHT - 35
  drawRectangle(windowX, footerY, SCREEN_WIDTH, 35,
               Color(r: 30, g: 60, b: 45, a: 255))
  
  let footerText = "✓ All systems operational | Defensive grid at maximum efficiency"
  let footerWidth = measureText(footerText, 13)
  drawText(footerText, windowX + (SCREEN_WIDTH - footerWidth) div 2, footerY + 10, 13,
          Color(r: 180, g: 220, b: 190, a: 255))
