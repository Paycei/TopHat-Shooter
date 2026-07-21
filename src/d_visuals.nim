import raylib, math
import types, d_systems, localization, utils

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
    let glowColor = withAlpha(comboColor, glowAlpha)
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

# WAVE START BANNER
# Driven by the game's time elapsed since the wave started (waveAge).
# Call this every draw frame with waveAge = game.time - game.waveStartTime.
# Shows for the first 1.5 s of each wave.
proc drawWaveStartBanner*(waveNumber: int, waveAge: float32,
                           screenWidth, screenHeight: int32,
                           isBossWarning: bool = false) =
  const SHOW_DURATION = 1.5
  const SLIDE_TIME    = 0.22
  if waveAge < 0 or waveAge > SHOW_DURATION:
    return

  # Slide in from top, linger, then slide out
  let slideIn  = clamp(waveAge / SLIDE_TIME, 0.0, 1.0)
  let slideOut = clamp((SHOW_DURATION - waveAge) / SLIDE_TIME, 0.0, 1.0)
  let ease     = slideIn * slideOut  # 0->1->0

  let bannerH: int32 = 44
  let bannerY = int32((-bannerH.float32) + ease * (bannerH + 4).float32)
  let alpha = uint8(ease * 255)

  # Banner background strip
  let bgColor = if isBossWarning:
    Color(r: 160, g: 40, b: 0, a: uint8(ease * 200))
  else:
    Color(r: 10, g: 30, b: 50, a: uint8(ease * 200))
  drawRectangle(0, bannerY, screenWidth, bannerH, bgColor)

  # Accent lines top and bottom
  let accentColor = if isBossWarning:
    Color(r: 255, g: 100, b: 0, a: alpha)
  else:
    Color(r: 0, g: 200, b: 255, a: alpha)
  drawRectangle(0, bannerY, screenWidth, 2, accentColor)
  drawRectangle(0, bannerY + bannerH - 2, screenWidth, 2, accentColor)

  # Wave text, centred
  let waveLabel = if isBossWarning:
    "BOSS INCOMING -  WAVE " & $waveNumber
  else:
    "WAVE  " & $waveNumber
  let fontSize: int32 = 22
  let textW = measureText(waveLabel, fontSize)
  let textX = (screenWidth - textW) div 2
  let textY = bannerY + (bannerH - fontSize) div 2

  # Shadow
  drawText(waveLabel, textX + 1, textY + 1, fontSize,
    Color(r: 0, g: 0, b: 0, a: uint8(alpha.float32 * 0.6)))
  # Main
  drawText(waveLabel, textX, textY, fontSize, accentColor)

# WAVE START BANNER - WIDESCREEN GUTTER VARIANT
# Compact vertical card that lives inside the right gutter instead of a
# full-width top strip. Slides in from the right edge (mirroring the classic
# banner's slide-in feel) so nothing draws over the centered gameplay world.
# gutterX/gutterW describe the right gutter (x start and width) in virtual coords.
proc drawWaveStartBannerGutter*(waveNumber: int, waveAge: float32,
                                gutterX, gutterW, topY: int32,
                                isBossWarning: bool = false): int32 =
  ## Compact vertical card in the right gutter. Returns the next stack Y (== topY
  ## when nothing is drawn) so the caller can flow the column from a running cursor.
  const SHOW_DURATION = 1.5
  const SLIDE_TIME    = 0.22
  if waveAge < 0 or waveAge > SHOW_DURATION:
    return topY

  let slideIn  = clamp(waveAge / SLIDE_TIME, 0.0, 1.0)
  let slideOut = clamp((SHOW_DURATION - waveAge) / SLIDE_TIME, 0.0, 1.0)
  let ease     = slideIn * slideOut  # 0->1->0
  let alpha = uint8(ease * 255)

  let cardW: int32 = min(gutterW - 8, 163'i32)
  # Boss variant needs an extra text line.
  let lines = if isBossWarning:
    @["BOSS", "INCOMING", "WAVE " & $waveNumber]
  else:
    @["WAVE", $waveNumber]
  let fontSize: int32 = 22
  let lineH: int32 = fontSize + 4
  let cardH: int32 = 12 + lines.len.int32 * lineH

  # Slide in horizontally from the right edge of the gutter.
  let slideOff = int32((1.0 - ease) * (cardW.float32 + 12.0))
  let cardX = gutterX + (gutterW - cardW) div 2 + slideOff
  let cardY: int32 = topY

  let bgColor = if isBossWarning:
    Color(r: 160, g: 40, b: 0, a: uint8(ease * 210))
  else:
    Color(r: 10, g: 30, b: 50, a: uint8(ease * 210))
  drawRectangle(cardX, cardY, cardW, cardH, bgColor)

  let accentColor = if isBossWarning:
    Color(r: 255, g: 100, b: 0, a: alpha)
  else:
    Color(r: 0, g: 200, b: 255, a: alpha)
  # Vertical accent bars on the card sides.
  drawRectangle(cardX, cardY, 2, cardH, accentColor)
  drawRectangle(cardX + cardW - 2, cardY, 2, cardH, accentColor)

  var ty = cardY + 6
  for ln in lines:
    let tw = measureText(ln, fontSize)
    let tx = cardX + (cardW - tw) div 2
    drawText(ln, tx + 1, ty + 1, fontSize,
      Color(r: 0, g: 0, b: 0, a: uint8(alpha.float32 * 0.6)))
    drawText(ln, tx, ty, fontSize, accentColor)
    ty += lineH
  return cardY + cardH + 6

# COMBO GUTTER CARD (widescreen)
# A proper right-gutter section card: big punchy combo count with the existing
# scale/pulse feel, a decay/timer bar underneath, and tier-escalating colors.
# Styled to match the OS border-HUD language (dark bg, accent stripe, thin edge).
proc drawComboGutterCard*(combo: ComboSystem, gutterX, gutterW, topY: int32,
                          currentTime: float32) =
  if not shouldShowCombo(combo):
    return
  let multiplier = getComboMultiplier(combo)
  if multiplier == "":
    return

  let cardW: int32 = min(gutterW - 8, 163'i32)
  let cardX = gutterX + (gutterW - cardW) div 2
  let cardH: int32 = 70
  let kc = combo.killCount
  # Tier color escalates gold -> orange -> red -> magenta.
  let tierColor = if kc >= 20: Color(r: 255, g: 60, b: 200, a: 255)
                  elif kc >= 15: Color(r: 255, g: 70, b: 60, a: 255)
                  elif kc >= 10: Color(r: 255, g: 130, b: 30, a: 255)
                  else: Color(r: 255, g: 190, b: 40, a: 255)
  let fadeAlpha = uint8(min(combo.displayTimer, 1.0) * 255.0)
  let accA = fadeAlpha.int

  drawRectangle(cardX, topY, cardW, cardH, Color(r: 8, g: 14, b: 22, a: uint8(min(accA, 210))))
  drawRectangle(cardX, topY, 2, cardH, withAlpha(tierColor, fadeAlpha))
  drawRectangleLines(Rectangle(x: cardX.float32, y: topY.float32, width: cardW.float32, height: cardH.float32),
                     1, withAlpha(tierColor, uint8(accA * 90 div 255)))

  let comboText = if kc >= 20: t(tkComboInsane)
                  elif kc >= 15: t(tkComboCrazy)
                  elif kc >= 10: t(tkComboSick)
                  else: t(tkComboLabel)
  drawText(comboText, cardX + 8, topY + 6, 11,
    withAlpha(tierColor, fadeAlpha))

  let pulse = (sin(combo.displayTimer * 8.0) + 1.0) * 0.5
  let baseSize = min(30.0 + kc.float32 * 1.2, 46.0)
  let mult = int32(baseSize * (1.0 + pulse * 0.06))
  let mw = measureText(multiplier, mult)
  let mx = cardX + (cardW - mw) div 2
  let my = topY + 20
  drawText(multiplier, mx + 2, my + 2, mult, Color(r: 0, g: 0, b: 0, a: uint8(accA * 60 div 255)))
  drawText(multiplier, mx, my, mult, withAlpha(tierColor, fadeAlpha))

  # Decay bar underneath (displayTimer runs 5 -> 0).
  let barY = topY + cardH - 10
  let barW = cardW - 16
  let frac = clamp(combo.displayTimer / 5.0'f32, 0.0'f32, 1.0'f32)
  drawRectangle(cardX + 8, barY, barW, 5, Color(r: 20, g: 26, b: 36, a: fadeAlpha))
  drawRectangle(cardX + 8, barY, int32(barW.float32 * frac), 5,
    withAlpha(tierColor, fadeAlpha))
