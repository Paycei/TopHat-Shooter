## OS-Style HUD System

import raylib, types, math

const
  PANEL_PADDING = 10
  TITLE_BAR_HEIGHT = 24
  HEADER_BG_COLOR = Color(r: 15, g: 20, b: 30, a: 120)
  ACCENT_COLOR = Color(r: 0, g: 200, b: 255, a: 255)
  ACCENT_DIM = Color(r: 0, g: 150, b: 200, a: 180)

proc newOSHUD*(): OSHUDState =
  result = OSHUDState(
    notifications: @[],
    panelPulse: 0.0,
    minimized: false
  )

proc addNotification*(hud: var OSHUDState, message: string, notifType: NotificationType) =
  hud.notifications.add(OSNotification(
    message: message,
    notifType: notifType,
    lifetime: 0.0,
    fadeTime: 3.0
  ))
  
  # Keep only last 5 notifications
  if hud.notifications.len > 5:
    hud.notifications.delete(0)

proc updateOSHUD*(hud: var OSHUDState, dt: float32) =
  hud.panelPulse += dt
  
  # Update notifications
  var i = 0
  while i < hud.notifications.len:
    hud.notifications[i].lifetime += dt
    if hud.notifications[i].lifetime > hud.notifications[i].fadeTime:
      hud.notifications.delete(i)
    else:
      i += 1

proc drawStatusPanel*(player: Player, x, y: int32, hud: OSHUDState) =
  let panelWidth: int32 = 280
  let panelHeight: int32 = if hud.minimized: TITLE_BAR_HEIGHT else: 170
  
  # Panel background with gradient effect
  drawRectangle(x, y, panelWidth, panelHeight,
               Color(r: 10, g: 15, b: 22, a: 85))
  
  # Accent stripe on right edge for symmetry with left panel
  drawRectangle(x + panelWidth - 3, y, 3, panelHeight, ACCENT_COLOR)
  
  # Title bar with header background
  drawRectangle(x, y, panelWidth - 3, TITLE_BAR_HEIGHT, HEADER_BG_COLOR)
  
  # Title text with shadow for readability
  drawText("SYSTEM STATUS", x + 9, y + 5, 13, Color(r: 0, g: 0, b: 0, a: 140))
  drawText("SYSTEM STATUS", x + 8, y + 4, 13, ACCENT_COLOR)
  
  # Border with glow effect
  drawRectangleLines(x, y, panelWidth, panelHeight, 
                    Color(r: 0, g: 200, b: 255, a: 140))
  
  if not hud.minimized:
    var yOffset = y + TITLE_BAR_HEIGHT + PANEL_PADDING
    
    # HP Bar (System Integrity) with enhanced styling
    drawText("INTEGRITY:", x + PANEL_PADDING + 1, yOffset + 1, 11, 
            Color(r: 0, g: 0, b: 0, a: 130))
    drawText("INTEGRITY:", x + PANEL_PADDING, yOffset, 11, 
            Color(r: 180, g: 200, b: 220, a: 255))
    yOffset += 16
    
    let hpPercent = player.hp / player.maxHp
    let barWidth: int32 = panelWidth - (PANEL_PADDING * 2) - 6
    let barHeight: int32 = 24
    
    # Bar background with depth
    drawRectangle(x + PANEL_PADDING + 3, yOffset, barWidth, barHeight,
                 Color(r: 10, g: 15, b: 20, a: 120))
    
    # Bar fill with gradient
    let fillWidth = (barWidth.float32 * hpPercent).int32
    let barColor = if hpPercent > 0.6: 
      Color(r: 0, g: 255, b: 100, a: 200)
    elif hpPercent > 0.3: 
      Color(r: 255, g: 220, b: 0, a: 200)
    else: 
      Color(r: 255, g: 80, b: 80, a: 200)
    
    drawRectangle(x + PANEL_PADDING + 3, yOffset, fillWidth, barHeight, barColor)
    
    # HP text with enhanced shadow
    let hpText = $player.hp.int & " / " & $player.maxHp.int
    let hpTextWidth = measureText(hpText, 14)
    let hpTextX = x + PANEL_PADDING + 3 + (barWidth div 2) - (hpTextWidth div 2)
    drawText(hpText, hpTextX + 1, yOffset + 6, 14, 
            Color(r: 0, g: 0, b: 0, a: 180))
    drawText(hpText, hpTextX, yOffset + 5, 14, 
            Color(r: 255, g: 255, b: 255, a: 255))
    
    # Bar border with glow
    drawRectangleLines(Rectangle(x: (x + PANEL_PADDING + 3).float32, y: yOffset.float32,
                                  width: barWidth.float32, height: barHeight.float32),
                      1, ACCENT_DIM)
    
    yOffset += barHeight + 12
    
    # Stats row with icons and enhanced layout
    # Background for stats section
    drawRectangle(x + PANEL_PADDING + 3, yOffset - 4, barWidth, 60,
                 Color(r: 15, g: 20, b: 28, a: 70))
    
    # Charges (Walls)
    drawText("CHARGES", x + PANEL_PADDING + 8, yOffset + 1, 10,
            Color(r: 0, g: 0, b: 0, a: 120))
    drawText("CHARGES", x + PANEL_PADDING + 7, yOffset, 10,
            Color(r: 180, g: 200, b: 220, a: 255))
    
    let chargesText = $player.walls & " / 6"
    let chargesColor = if player.walls > 3:
      Color(r: 0, g: 220, b: 140, a: 255)
    elif player.walls > 0:
      Color(r: 255, g: 220, b: 100, a: 255)
    else:
      Color(r: 160, g: 160, b: 160, a: 255)
    
    # Charges background indicator
    drawRectangle(x + PANEL_PADDING + 7, yOffset + 14, 80, 18,
                 Color(r: 0, g: 0, b: 0, a: 60))
    
    drawText(chargesText, x + PANEL_PADDING + 13, yOffset + 18, 14,
            Color(r: 0, g: 0, b: 0, a: 150))
    drawText(chargesText, x + PANEL_PADDING + 12, yOffset + 17, 14, chargesColor)
    
    # Processes count
    let processCount = player.powerUps.len
    let processX = x + PANEL_PADDING + 100
    
    drawText("PROCESSES", processX + 1, yOffset + 1, 10,
            Color(r: 0, g: 0, b: 0, a: 120))
    drawText("PROCESSES", processX, yOffset, 10,
            Color(r: 180, g: 200, b: 220, a: 255))
    
    let processText = $processCount & " active"
    let processColor = if processCount > 5:
      Color(r: 80, g: 160, b: 255, a: 255)
    elif processCount > 0:
      Color(r: 120, g: 255, b: 140, a: 255)
    else:
      Color(r: 160, g: 160, b: 160, a: 255)
    
    # Process background indicator
    drawRectangle(processX, yOffset + 14, 80, 18,
                 Color(r: 0, g: 0, b: 0, a: 60))
    
    drawText(processText, processX + 6, yOffset + 18, 12,
            Color(r: 0, g: 0, b: 0, a: 150))
    drawText(processText, processX + 5, yOffset + 17, 12, processColor)
    
    yOffset += 38
    
    # Coins (Cache) with enhanced styling
    drawText("CACHE", x + PANEL_PADDING + 8, yOffset + 1, 10,
            Color(r: 0, g: 0, b: 0, a: 120))
    drawText("CACHE", x + PANEL_PADDING + 7, yOffset, 10,
            Color(r: 180, g: 200, b: 220, a: 255))
    
    let coinText = $player.coins & " credits"
    
    # Coin background indicator
    drawRectangle(x + PANEL_PADDING + 7, yOffset + 14, 100, 18,
                 Color(r: 50, g: 40, b: 0, a: 60))
    
    drawText(coinText, x + PANEL_PADDING + 13, yOffset + 18, 13,
            Color(r: 0, g: 0, b: 0, a: 150))
    drawText(coinText, x + PANEL_PADDING + 12, yOffset + 17, 13,
            Color(r: 255, g: 220, b: 0, a: 255))

proc drawPerformanceMetrics*(game: Game, x, y: int32) =
  let panelWidth: int32 = 180
  let panelHeight: int32 = 100
  
  # Panel background
  drawRectangle(x, y, panelWidth, panelHeight,
               Color(r: 15, g: 20, b: 30, a: 180))
  
  # Title bar
  drawRectangle(x, y, panelWidth, TITLE_BAR_HEIGHT,
               Color(r: 25, g: 30, b: 45, a: 220))
  
  drawText("Performance", x + 8, y + 5, 14, Color(r: 0, g: 200, b: 200, a: 255))
  
  # Border
  drawRectangleLines(x, y, panelWidth, panelHeight,
                    Color(r: 0, g: 200, b: 200, a: 255))
  
  var yOffset = y + TITLE_BAR_HEIGHT + PANEL_PADDING
  
  # Wave number
  drawText("WAVE: " & $game.currentWave, x + PANEL_PADDING, yOffset, 14, Color(r: 255, g: 255, b: 255, a: 255))
  yOffset += 18
  
  # Uptime
  let minutes = (game.time / 60.0).int
  let seconds = (game.time mod 60.0).int
  let timeText = (if minutes < 10: "0" else: "") & $minutes & ":" & 
                 (if seconds < 10: "0" else: "") & $seconds
  drawText("UPTIME: " & timeText, x + PANEL_PADDING, yOffset, 14, Color(r: 255, g: 255, b: 255, a: 255))
  yOffset += 18
  
  # Threat count
  let threatCount = game.enemies.len
  let threatColor = if threatCount > 20: Color(r: 255, g: 0, b: 0, a: 255)  # Red
                   elif threatCount > 10: Color(r: 255, g: 165, b: 0, a: 255)  # Orange
                   else: Color(r: 0, g: 255, b: 0, a: 255)  # Green
  drawText("THREATS: " & $threatCount, x + PANEL_PADDING, yOffset, 14, threatColor)

proc drawActionLog*(hud: OSHUDState, screenWidth, screenHeight: int32) =
  if hud.notifications.len == 0:
    return
  
  let logWidth: int32 = 400
  let logHeight: int32 = 30
  let logX = screenWidth div 2 - logWidth div 2
  
  # Draw from bottom up (newest at bottom)
  var yOffset: int32 = screenHeight - 60
  
  var i = hud.notifications.len - 1
  while i >= 0:
    let notif = hud.notifications[i]
    
    # Calculate fade
    let fadeStart = notif.fadeTime - 0.5
    let alpha = if notif.lifetime > fadeStart:
      uint8((1.0 - (notif.lifetime - fadeStart) / 0.5) * 255)
    else:
      uint8(255)
    
    # Background
    let bgColor = case notif.notifType
      of ntInfo: Color(r: 20, g: 40, b: 60, a: alpha div 2)
      of ntWarning: Color(r: 60, g: 50, b: 20, a: alpha div 2)
      of ntError: Color(r: 60, g: 20, b: 20, a: alpha div 2)
      of ntCritical: Color(r: 80, g: 10, b: 10, a: alpha div 2)
    
    drawRectangle(logX, yOffset, logWidth, logHeight, bgColor)
    
    # Text
    let prefix = case notif.notifType
      of ntInfo: "[LOG] "
      of ntWarning: "[WARN] "
      of ntError: "[ERR] "
      of ntCritical: "[CRITICAL] "
    
    let textColor = case notif.notifType
      of ntInfo: Color(r: 150, g: 200, b: 255, a: alpha)
      of ntWarning: Color(r: 255, g: 200, b: 100, a: alpha)
      of ntError: Color(r: 255, g: 100, b: 100, a: alpha)
      of ntCritical: Color(r: 255, g: 50, b: 50, a: alpha)
    
    drawText(prefix & notif.message, logX + 8, yOffset + 8, 14, textColor)
    
    yOffset -= logHeight + 5
    if yOffset < screenHeight div 2:
      break  # Don't draw too many
    
    i -= 1
