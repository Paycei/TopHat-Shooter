import raylib, types, d_systems, math, localization

proc drawComboAtPosition*(combo: ComboSystem, screenWidth, screenHeight: int32,
                          currentTime: float32, posX, posY: int32) =
  ## Draw combo display at a custom position (used for power-up select screen)
  if not shouldShowCombo(combo):
    return
  
  let multiplier = getComboMultiplier(combo)
  if multiplier == "":
    return
  
  # Use custom position instead of default
  let baseX = posX
  let baseY = posY
  
  let scale = min(1.0 + (combo.killCount.float32 * 0.03), 1.5)
  let fontSize = int32(24.0 * scale)
  
  # Pulsing effect
  let pulse = (sin(combo.displayTimer * 8.0) + 1.0) * 0.5
  let pulseScale = 1.0 + (pulse * 0.05)
  let finalFontSize = int32(fontSize.float32 * pulseScale)
  
  # Color intensity based on combo - gradient from orange to red
  let intensity = min(combo.killCount * 8, 255)
  let fadeAlpha = uint8(min(combo.displayTimer, 1.0) * 255.0)
  let comboColor = Color(
    r: 255,
    g: uint8(max(0, 200 - intensity)),
    b: 0,
    a: fadeAlpha
  )
  
  # Draw glow effect (multiple layers)
  for i in countdown(3, 1):
    let glowAlpha = uint8((fadeAlpha.float32 * 0.3 * (4 - i).float32 / 3.0).int)
    let glowColor = Color(r: comboColor.r, g: comboColor.g, b: comboColor.b, a: glowAlpha)
    drawText(multiplier, (baseX - i).int32, (baseY - i).int32, finalFontSize, glowColor)
    drawText(multiplier, (baseX + i).int32, (baseY + i).int32, finalFontSize, glowColor)
  
  # Main multiplier text
  drawText(multiplier, baseX.int32, baseY.int32, finalFontSize, comboColor)
  
  # "COMBO!" text below with emphasis
  let comboLabelSize = int32(12.0 * scale)
  let comboText = if combo.killCount >= 20: t(tkComboInsane)
                  elif combo.killCount >= 15: t(tkComboCrazy)
                  elif combo.killCount >= 10: t(tkComboSick)
                  else: t(tkComboLabel)
  
  let labelWidth = measureText(comboText, comboLabelSize)
  let labelX = baseX.int32 + (finalFontSize div 2) - (labelWidth div 2)
  let labelY = baseY.int32 + finalFontSize + 4
  
  # Label glow
  drawText(comboText, labelX + 1, labelY + 1, comboLabelSize,
    Color(r: 0, g: 0, b: 0, a: uint8(fadeAlpha.float32 * 0.6)))
  drawText(comboText, labelX, labelY, comboLabelSize,
    Color(r: 255, g: 255, b: 100, a: fadeAlpha))
  
  # Track vertical offset for stacking notifications
  var notificationY = labelY + comboLabelSize + 8
  
  # Bonus coins notification (if earned)
  if combo.bonusCoins > 0 and combo.displayTimer > 1.5:
    let bonusText = "+" & $combo.bonusCoins & " " & t(tkComboCoins)
    let bonusWidth = measureText(bonusText, 16)
    let bonusX = baseX.int32 + (finalFontSize div 2) - (bonusWidth div 2)
    
    let bonusAlpha = uint8(min((combo.displayTimer - 1.5) * 255.0, 255.0))
    drawText(bonusText, bonusX + 1, notificationY + 1, 16,
      Color(r: 0, g: 0, b: 0, a: uint8(bonusAlpha.float32 * 0.7)))
    drawText(bonusText, bonusX, notificationY, 16,
      Color(r: 255, g: 215, b: 0, a: bonusAlpha))
    notificationY += 22
  
  # Perfect wave combo notification (if earned) - TONED DOWN VERSION
  if combo.lastPerfectWaveBonus > 0 and combo.displayTimer > 0.5:
    let perfectText = if combo.perfectWaveStreak > 1:
      t(tkComboPerfectStreak) & $combo.perfectWaveStreak & "! +" & $combo.lastPerfectWaveBonus & " " & t(tkComboCoins)
    else:
      t(tkComboPerfectWave) & " +" & $combo.lastPerfectWaveBonus & " " & t(tkComboCoins)
    
    # Less flashy - smaller size, no pulsing
    let perfectFontSize: int32 = 18
    let perfectWidth = measureText(perfectText, perfectFontSize)
    let perfectX = baseX.int32 + (finalFontSize div 2) - (perfectWidth div 2)
    
    let perfectAlpha = uint8(min(combo.displayTimer * 200.0, 255.0))
    
    # Simpler background - no glowing border
    let boxPadding: int32 = 8
    let boxWidth = perfectWidth + boxPadding * 2
    let boxHeight = perfectFontSize + boxPadding
    let boxX = perfectX - boxPadding
    let boxY = notificationY - 4
    
    # Subtle background
    drawRectangle(boxX, boxY, boxWidth, boxHeight,
      Color(r: 40, g: 60, b: 0, a: uint8(perfectAlpha.float32 * 0.5)))
    
    # Draw text with simple shadow - no pulsing
    drawText(perfectText, perfectX + 1, notificationY + 1, perfectFontSize,
      Color(r: 0, g: 0, b: 0, a: uint8(perfectAlpha.float32 * 0.7)))
    drawText(perfectText, perfectX, notificationY, perfectFontSize,
      Color(r: 255, g: 220, b: 80, a: perfectAlpha))  # Softer yellow
    notificationY += 24
  
  # TIMER BAR
  let timeSinceLastKill = currentTime - combo.lastKillTime
  let currentWindow = max(0.01, combo.comboWindow)  # Prevent division by zero
  let timeRemaining = max(0.0, currentWindow - timeSinceLastKill)
  let timePercent = clamp(timeRemaining / currentWindow, 0.0, 1.0)
  
  let barY = notificationY + 4
  let barWidth = 100.int32
  let barHeight = 6.int32
  let barX = baseX.int32 + (finalFontSize div 2) - (barWidth div 2)
  
  drawRectangle(barX, barY, barWidth, barHeight,
    Color(r: 20, g: 20, b: 20, a: uint8(fadeAlpha.float32 * 0.8)))
  
  let barFillWidth = int32(barWidth.float32 * timePercent)
  let barColor = if timePercent > 0.25:
    Color(r: 255, g: 215, b: 0, a: fadeAlpha)
  else:
    Color(r: 255, g: 80, b: 80, a: fadeAlpha)
  
  drawRectangle(barX, barY, barFillWidth, barHeight, barColor)

proc drawCombo*(combo: ComboSystem, screenWidth, screenHeight: int32, currentTime: float32) =
  ## Default combo display in middle-right of screen
  let baseX = screenWidth - 120
  let baseY = screenHeight div 2
  drawComboAtPosition(combo, screenWidth, screenHeight, currentTime, baseX, baseY)

# MILESTONE POPUP

proc drawMilestone*(manager: MilestoneManager, screenWidth, screenHeight: int32) =
  if not manager.showRecent:
    return
  
  let milestone = manager.recentMilestone
  if milestone.displayTimer <= 0:
    return
  
  # Fade in/out
  let fadeAlpha = if milestone.displayTimer > 4.0:
    uint8((5.0 - milestone.displayTimer) * 255.0)
  elif milestone.displayTimer < 1.0:
    uint8(milestone.displayTimer * 255.0)
  else:
    255'u8
  
  # Small notification in top-right
  let x = screenWidth - 280
  let y = 160.int32
  
  # Compact background
  drawRectangle(x, y, 270, 60,
    Color(r: 20, g: 20, b: 40, a: uint8(fadeAlpha * 180 div 255)))
  drawRectangleLines(x, y, 270, 60,
    Color(r: 255, g: 215, b: 0, a: fadeAlpha))
  
  # Achievement text (small)
  drawText(t(tkMilestoneAchievement), x + 10, y + 8, 12.int32,
    Color(r: 255, g: 215, b: 0, a: fadeAlpha))
  
  # Milestone name (compact)
  drawText(milestone.name, x + 10, y + 25, 14.int32,
    Color(r: 255, g: 255, b: 255, a: fadeAlpha))
  
  # Description (very small)
  drawText(milestone.description, x + 10, y + 43, 10.int32,
    Color(r: 200, g: 200, b: 200, a: fadeAlpha))

# MICRO-REWARD DISPLAY
proc drawMicroRewards*(tracker: MicroRewardTracker) =
  # Micro-rewards are now very subtle - just small text floating up
  for reward in tracker.rewards:
    if reward.displayTimer <= 0:
      continue
    
    # Float upward effect
    let yOffset = (2.0 - reward.displayTimer) * 20.0
    let alpha = uint8(min(reward.displayTimer * 180.0, 180.0))
    
    # Small text near player
    let x = int32(reward.pos.x)
    let y = int32(reward.pos.y - yOffset)
    
    # Just show the coins, skip the message
    if reward.coins > 0:
      let coinText = "+" & $reward.coins
      drawText(coinText, x - 10, y - 20, 14.int32,
        Color(r: 255, g: 215, b: 0, a: alpha))

# WAVE STATS SUMMARY
proc drawWaveStats*(stats: WaveStats, screenWidth, screenHeight: int32) =
  let x = screenWidth - 250
  let y = 50.int32
  
  drawText(t(tkWaveStatsTitle) & " " & $stats.waveNumber, x, y, 20.int32, White)
  drawText(t(tkWaveStatsKillsLabel) & " " & $stats.kills, x, y + 25, 16.int32,
    Color(r: 200, g: 200, b: 200, a: 255))
  drawText(t(tkWaveStatsTimeLabel) & " " & $(int(stats.survivalTime)) & "s", x, y + 45, 16.int32,
    Color(r: 200, g: 200, b: 200, a: 255))
  
  if stats.isPerfect:
    drawText(t(tkWaveStatsFlawless), x, y + 65, 18.int32,
      Color(r: 255, g: 215, b: 0, a: 255))
