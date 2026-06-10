## OS-Themed Statistics Window
## Full-featured stats display with graphs, analytics, and power-up breakdown

import raylib, math, strutils, std/tables, algorithm
import os_window, ../statistics, ../run_statistics, ../types, ../powerup_data, ../localization, ui_constants, ../render_context

type
  StatsTab* = enum
    stLifetime
    stLastRun
    stPowerUps
    stRoguelite

  StatsWindow* = ref object
    window*: OSWindow
    currentTab*: StatsTab
    stats*: Statistics
    animTime*: float32  # For animations

# HELPER PROCS (FORMATTING)
proc formatPercent*(value: float32): string =
  result = value.formatFloat(ffDecimal, 1) & "%"

proc formatLargeNumber*(value: float32): string =
  if value >= 1_000_000:
    result = (value / 1_000_000).formatFloat(ffDecimal, 1) & "M"
  elif value >= 1_000:
    result = (value / 1_000).formatFloat(ffDecimal, 1) & "K"
  else:
    result = value.formatFloat(ffDecimal, 1)

proc formatDuration*(seconds: float32): string =
  let mins = int(seconds) div 60
  let secs = int(seconds) mod 60
  result = align($mins, 2, '0') & ":" & align($secs, 2, '0')

proc getQualityColor*(value: float32, threshold: float32 = 50.0): Color =
  if value >= threshold:
    return Color(r: 80, g: 255, b: 80, a: 255)
  elif value >= threshold * 0.5:
    return Color(r: 255, g: 200, b: 50, a: 255)
  else:
    return Color(r: 255, g: 80, b: 80, a: 255)

proc newStatsWindow*(screenWidth, screenHeight: int, stats: Statistics): StatsWindow =
  let windowWidth = 1000
  let windowHeight = 700
  let windowX = (screenWidth - windowWidth) div 2
  let windowY = (screenHeight - windowHeight) div 2

  let osWin = newOSWindow(
    t(tkStatsWindowTitle),
    windowX, windowY,
    windowWidth, windowHeight,
    Color(r: 255, g: 200, b: 50, a: 255),
    owtStatistics,
    resizable = false
  )

  result = StatsWindow(
    window: osWin,
    currentTab: stLifetime,
    stats: stats,
    animTime: 0
  )

proc updateStatsWindow*(statsWin: StatsWindow, dt: float32, screenWidth, screenHeight: int, allWindows: openArray[OSWindow]): bool =
  updateOSWindow(statsWin.window, dt)
  statsWin.animTime += dt

  if not statsWin.window.visible:
    return false

  let shouldClose = handleOSWindowInput(statsWin.window, screenWidth, screenHeight, allWindows)
  if shouldClose:
    statsWin.window.visible = false
    return true

  if not statsWin.window.minimized:
    if isKeyPressed(One): statsWin.currentTab = stLifetime
    if isKeyPressed(Two): statsWin.currentTab = stLastRun
    if isKeyPressed(Three): statsWin.currentTab = stPowerUps
    if isKeyPressed(Four): statsWin.currentTab = stRoguelite

  # Only process content clicks if THIS window handled the click in handleOSWindowInput
  if not statsWin.window.minimized and statsWin.window.handledClickThisFrame:
    let mousePos = getVirtualMousePosition()
    let isTopmost = isWindowTopmostAtPoint(statsWin.window, mousePos.x, mousePos.y, allWindows)

    if isTopmost:
      let tabY = statsWin.window.y + TITLE_BAR_HEIGHT + 10
      let tabHeight = 35
      let tabWidth = 140
      let contentX = statsWin.window.x + WINDOW_PADDING
      var tabX = contentX

      for tab in [stLifetime, stLastRun, stPowerUps, stRoguelite]:
        if mousePos.x >= tabX.float32 and mousePos.x <= (tabX + tabWidth).float32 and
           mousePos.y >= tabY.float32 and mousePos.y <= (tabY + tabHeight).float32:
          statsWin.currentTab = tab
          break
        tabX += tabWidth + 10

  return false

# VISUAL HELPER PROCEDURES

proc drawSystemBar*(x, y, width, height: int, value: float32, label: string,
                   maxValue: float32, color: Color, animTime: float32) =
  let ratio = min(1.0, value / maxValue)

  drawRectangle(x.int32, y.int32, width.int32, height.int32,
               Color(r: 20, g: 20, b: 30, a: 255))

  let fillWidth = int(width.float32 * ratio)
  if fillWidth > 0:
    for i in 0..<fillWidth:
      let localRatio = i.float32 / width.float32
      let pulse = sin(animTime * 2.0 + localRatio * 3.14) * 0.15 + 0.85
      let r = uint8(float32(color.r) * localRatio * pulse)
      let g = uint8(float32(color.g) * localRatio * pulse)
      let b = uint8(float32(color.b) * pulse)
      drawRectangle((x + i).int32, y.int32, 1, height.int32,
                   Color(r: r, g: g, b: b, a: 200))

  drawRectangleLines(Rectangle(x: x.float32, y: y.float32,
                                width: width.float32, height: height.float32),
                    1, Color(r: 80, g: 80, b: 100, a: 255))

  drawText(label, (x + 5).int32, (y + (height - 14) div 2).int32, 14, White)

  let valueText = $int(value) & " / " & $int(maxValue)
  let textWidth = measureText(valueText, 14)
  drawText(valueText, (x + width - textWidth - 5).int32,
          (y + (height - 14) div 2).int32, 14, color)

  let percentText = $int(ratio * 100) & "%"
  let percentWidth = measureText(percentText, 12)
  drawText(percentText, (x + width div 2 - percentWidth div 2).int32,
          (y + height + 3).int32, 12, LightGray)

proc drawMetricCard*(x, y, width, height: int, title: string, value: string,
                    icon: char, color: Color) =
  drawRectangle(x.int32, y.int32, width.int32, height.int32,
               Color(r: 25, g: 25, b: 35, a: 255))
  drawRectangleLines(Rectangle(x: x.float32, y: y.float32,
                                width: width.float32, height: height.float32),
                    1, color)

  let iconX = x + 15
  let iconY = y + height div 2
  drawCircle(Vector2(x: iconX.float32, y: iconY.float32), 12, color)
  drawText($icon, (iconX - 6).int32, (iconY - 10).int32, 20, Black)

  drawText(title, (x + 40).int32, (y + 10).int32, 14, LightGray)
  drawText(value, (x + 40).int32, (y + 30).int32, 20, White)

proc drawStatPanel*(x, y, width, height: int, title: string) =
  ## Draw a panel background with title
  drawRectangle(x.int32, y.int32, width.int32, height.int32,
               Color(r: 25, g: 25, b: 35, a: 255))
  drawRectangleLines(Rectangle(x: x.float32, y: y.float32,
                                width: width.float32, height: height.float32),
                    1, Color(r: 80, g: 80, b: 100, a: 255))

  drawRectangle(x.int32, y.int32, width.int32, 28,
               Color(r: 35, g: 35, b: 45, a: 255))
  drawText(title, (x + 8).int32, (y + 6).int32, 14, Color(r: 0, g: 180, b: 255, a: 255))

proc drawStatLine*(x, y: int, label: string, value: string, valueColor: Color = White) =
  ## Draw a single stat line
  drawText(label, x.int32, y.int32, 14, Color(r: 180, g: 190, b: 200, a: 255))
  let valueWidth = measureText(value, 14)
  drawText(value, (x + 260 - valueWidth).int32, y.int32, 14, valueColor)

proc drawMiniGraph*(x, y, width, height: int, title: string,
                   dataPoints: seq[(float32, float32)], maxValue: float32,
                   color: Color, animTime: float32) =
  ## Draw a time-series line graph
  drawRectangle(x.int32, y.int32, width.int32, height.int32,
               Color(r: 20, g: 20, b: 30, a: 255))
  drawRectangleLines(Rectangle(x: x.float32, y: y.float32,
                                width: width.float32, height: height.float32),
                    1, Color(r: 80, g: 80, b: 100, a: 255))

  drawText(title, (x + 8).int32, (y + 6).int32, 12, Color(r: 0, g: 180, b: 255, a: 255))

  if dataPoints.len < 2:
    let noDataY = y + height div 2
    drawText(t(tkGameNoData), (x + width div 2 - 30).int32, noDataY.int32, 12, Gray)
    return

  let graphX = x + 10
  let graphY = y + 28
  let graphWidth = width - 20
  let graphHeight = height - 38

  for i in 0..3:
    let gridY = graphY + int((i.float32 / 3.0) * graphHeight.float32)
    drawLine(Vector2(x: graphX.float32, y: gridY.float32),
            Vector2(x: (graphX + graphWidth).float32, y: gridY.float32),
            1, Color(r: 40, g: 40, b: 60, a: 255))

  var minTime = float32.high
  var maxTime = 0.0'f32
  for point in dataPoints:
    minTime = min(minTime, point[0])
    maxTime = max(maxTime, point[0])

  let timeRange = max(maxTime - minTime, 0.1)
  let safeMaxValue = max(maxValue, 0.01)

  for i in 0..<dataPoints.len-1:
    let x1Norm = (dataPoints[i][0] - minTime) / timeRange
    let y1Norm = 1.0 - (dataPoints[i][1] / safeMaxValue)
    let x2Norm = (dataPoints[i+1][0] - minTime) / timeRange
    let y2Norm = 1.0 - (dataPoints[i+1][1] / safeMaxValue)

    let x1Px = graphX.float32 + x1Norm * graphWidth.float32
    let y1Px = graphY.float32 + y1Norm * graphHeight.float32
    let x2Px = graphX.float32 + x2Norm * graphWidth.float32
    let y2Px = graphY.float32 + y2Norm * graphHeight.float32

    drawLine(Vector2(x: x1Px, y: y1Px), Vector2(x: x2Px, y: y2Px),
            3, Color(r: color.r, g: color.g, b: color.b, a: 60))
    drawLine(Vector2(x: x1Px, y: y1Px), Vector2(x: x2Px, y: y2Px),
            2, color)

  drawText("0", (x + 2).int32, (graphY + graphHeight - 12).int32, 10, Gray)
  drawText(formatLargeNumber(safeMaxValue), (x + 2).int32, graphY.int32, 10, Gray)

proc drawStatsWindow*(statsWin: StatsWindow, game: Game) =
  if not statsWin.window.visible:
    return

  drawWindowChrome(statsWin.window)

  if statsWin.window.minimized:
    return

  let contentX = statsWin.window.x + WINDOW_PADDING
  let contentY = statsWin.window.y + TITLE_BAR_HEIGHT + 10
  let contentW = statsWin.window.width - WINDOW_PADDING * 2
  let contentH = statsWin.window.height - TITLE_BAR_HEIGHT - WINDOW_PADDING

  # Draw tab headers
  let tabY = contentY
  let tabHeight = 35
  let tabWidth = 140
  let mousePos = getVirtualMousePosition()

  var tabX = contentX
  for tab in [stLifetime, stLastRun, stPowerUps, stRoguelite]:
    let tabName = case tab
      of stLifetime: t(tkStatsTabLifetime)
      of stLastRun: t(tkStatsTabLastRun)
      of stPowerUps: t(tkStatsTabPowerUps)
      of stRoguelite: t("stats_tab_roguelite")

    let isActive = statsWin.currentTab == tab
    let isHovered = mousePos.x >= tabX.float32 and
                   mousePos.x <= (tabX + tabWidth).float32 and
                   mousePos.y >= tabY.float32 and
                   mousePos.y <= (tabY + tabHeight).float32

    let bgColor = if isActive:
      Color(r: 0, g: 60, b: 80, a: 255)
    elif isHovered:
      Color(r: 50, g: 50, b: 60, a: 255)
    else:
      Color(r: 40, g: 40, b: 50, a: 255)

    drawRectangle(tabX.int32, tabY.int32, tabWidth.int32, tabHeight.int32, bgColor)

    let borderColor = if isActive:
      Color(r: 0, g: 200, b: 255, a: 255)
    else:
      Color(r: 80, g: 80, b: 100, a: 255)

    drawRectangleLines(Rectangle(x: tabX.float32, y: tabY.float32,
                                  width: tabWidth.float32, height: tabHeight.float32),
                      1, borderColor)

    let textWidth = measureText(tabName, 16)
    let textX = tabX + (tabWidth - textWidth) div 2
    let textY = tabY + (tabHeight - 16) div 2

    let textColor = if isActive: Gold else: White
    drawText(tabName, textX.int32, textY.int32, 16, textColor)

    tabX += tabWidth + 10

  # Content area
  let tabContentY = contentY + tabHeight + 10
  let tabContentH = contentH - tabHeight - 20

  drawRectangle(contentX.int32, tabContentY.int32, contentW.int32, tabContentH.int32,
               Color(r: 15, g: 15, b: 25, a: 255))

  let hasLastRun = hasLastRunStats()

  case statsWin.currentTab
  of stLifetime:
    # Existing lifetime stats
    var y = tabContentY + 20

    drawText(t(tkStatsPerformanceMonitor), (contentX + 20).int32, y.int32,
            20, Color(r: 0, g: 200, b: 255, a: 255))
    y += 35

    let cardWidth = (contentW - 80) div 3
    let cardHeight = 70

    drawMetricCard(contentX + 20, y, cardWidth, cardHeight,
                  t(tkStatsTotalSessions), $statsWin.stats.totalGamesPlayed,
                  '#', Gold)

    drawMetricCard(contentX + 40 + cardWidth, y, cardWidth, cardHeight,
                  t(tkStatsPlaytime), formatTime(statsWin.stats.totalPlayTime),
                  '@', Color(r: 100, g: 200, b: 255, a: 255))

    let peakKills = max(statsWin.stats.waveMode.bestKills, max(statsWin.stats.timeMode.bestKills, statsWin.stats.rogueliteMode.bestKills))
    drawMetricCard(contentX + 60 + cardWidth * 2, y, cardWidth, cardHeight,
                  t(tkStatsPeakKills), $peakKills,
                  '*', Red)

    y += cardHeight + 25

    drawText(t(tkStatsWaveModeMetrics), (contentX + 20).int32, y.int32, 18,
            Color(r: 100, g: 200, b: 255, a: 255))
    y += 25

    let barWidth = contentW - 80
    let barHeight = 24

    drawSystemBar(contentX + 30, y, barWidth, barHeight,
                 statsWin.stats.waveMode.highestWaveReached.float32,
                 t("stats_bar_wave_max"), 50.0,
                 Color(r: 100, g: 220, b: 255, a: 255), statsWin.animTime)
    y += barHeight + 18

    drawSystemBar(contentX + 30, y, barWidth, barHeight,
                 statsWin.stats.waveMode.bestKills.float32,
                 t("stats_bar_kill_best"), 500.0,
                 Color(r: 255, g: 200, b: 100, a: 255), statsWin.animTime)
    y += barHeight + 18

    drawSystemBar(contentX + 30, y, barWidth, barHeight,
                 statsWin.stats.waveMode.bossesDefeated.float32,
                 t("stats_bar_boss_eliminated"), 20.0,
                 Color(r: 255, g: 100, b: 100, a: 255), statsWin.animTime)
    y += barHeight + 30

    drawText(t(tkStatsTimeSurvivalMetrics), (contentX + 20).int32, y.int32, 18,
            Color(r: 255, g: 150, b: 100, a: 255))
    y += 25

    let survivalMins = statsWin.stats.timeMode.longestSurvivalTime.float32 / 60.0
    drawSystemBar(contentX + 30, y, barWidth, barHeight,
                 survivalMins, t("stats_bar_time_survival"), 10.0,
                 Color(r: 255, g: 165, b: 0, a: 255), statsWin.animTime)
    y += barHeight + 18

    drawSystemBar(contentX + 30, y, barWidth, barHeight,
                 statsWin.stats.timeMode.bestKills.float32,
                 t("stats_bar_kill_best"), 500.0,
                 Color(r: 255, g: 200, b: 100, a: 255), statsWin.animTime)
    y += barHeight + 18

    drawSystemBar(contentX + 30, y, barWidth, barHeight,
                 statsWin.stats.timeMode.bossesDefeated.float32,
                 t("stats_bar_boss_eliminated"), 20.0,
                 Color(r: 255, g: 100, b: 100, a: 255), statsWin.animTime)

    y += barHeight + 30
    drawText(t("stats_roguelite_metrics"), (contentX + 20).int32, y.int32, 18,
            Color(r: 0, g: 220, b: 180, a: 255))
    y += 25
    drawSystemBar(contentX + 30, y, barWidth, barHeight,
                 statsWin.stats.rogueliteMode.highestWaveReached.float32,
                 t("stats_roguelite_best_sectors"), 30.0,
                 Color(r: 0, g: 220, b: 180, a: 255), statsWin.animTime)

  of stLastRun:
    if hasLastRun:
      let runStats = getLastRunStats()

      let col1Width = (contentW - 36) div 3
      let col1X = contentX + 12
      let col2X = col1X + col1Width + 12
      let col3X = col2X + col1Width + 12
      var y = tabContentY + 12

      # Combat Stats Panel (increased height for combo stats)
      drawStatPanel(col1X, y, col1Width, 300, t(tkStatsCombat))
      var lineY = y + 36

      drawStatLine(col1X + 10, lineY, t(tkStatsAccuracy), formatPercent(runStats.combat.accuracyPercent),
                  getQualityColor(runStats.combat.accuracyPercent, 60.0))
      lineY += 20
      drawStatLine(col1X + 10, lineY, t(tkStatsShotsFired), $runStats.combat.shotsFired)
      lineY += 20
      drawStatLine(col1X + 10, lineY, t(tkStatsShotsHit), $runStats.combat.shotsHit, Color(r: 80, g: 255, b: 80, a: 255))
      lineY += 20
      drawStatLine(col1X + 10, lineY, t(tkStatsDealedAbbrev), formatLargeNumber(runStats.combat.totalDamageDealt * BALANCE_MULTIPLIER), Orange)
      lineY += 20
      drawStatLine(col1X + 10, lineY, t(tkStatsTakenAbbrev), formatLargeNumber(runStats.combat.totalDamageTaken * BALANCE_MULTIPLIER), Red)
      lineY += 20
      drawStatLine(col1X + 10, lineY, t(tkStatsEliteKills), $runStats.combat.eliteKills, Orange)
      lineY += 20
      drawStatLine(col1X + 10, lineY, t(tkStatsBossKills), $runStats.combat.bossKills, Red)
      lineY += 20
      drawStatLine(col1X + 10, lineY, t(tkStatsCriticalHits), $runStats.combat.criticalHits, Color(r: 0, g: 180, b: 255, a: 255))
      lineY += 20
      drawStatLine(col1X + 10, lineY, "Chain Lightning Procs", $runStats.combat.chainLightningProcs, Color(r: 255, g: 255, b: 80, a: 255))
      lineY += 20
      if runStats.powerUps.totalHealingFromPowerUps > 0:
        drawStatLine(col1X + 10, lineY, "PU Healing Total",
                     formatLargeNumber(runStats.powerUps.totalHealingFromPowerUps * BALANCE_MULTIPLIER),
                     Color(r: 80, g: 255, b: 160, a: 255))
        lineY += 20
      # Combo stats
      drawStatLine(col1X + 10, lineY, t("stats_max_combo"), $runStats.combat.maxCombo, Color(r: 255, g: 200, b: 0, a: 255))
      lineY += 20
      let avgCombo = if runStats.combat.totalCombos > 0:
        (runStats.combat.comboSum.float32 / runStats.combat.totalCombos.float32)
      else:
        0.0
      drawStatLine(col1X + 10, lineY, t("stats_avg_combo"), formatFloat(avgCombo, ffDecimal, 1), Color(r: 255, g: 220, b: 100, a: 255))
      lineY += 20
      drawStatLine(col1X + 10, lineY, t("stats_perfect_waves"), $runStats.combat.perfectWaves, Color(r: 100, g: 255, b: 255, a: 255))

      # Movement Stats Panel
      drawStatPanel(col2X, y, col1Width, 240, t(tkStatsMovementSurvival))
      lineY = y + 36

      drawStatLine(col2X + 10, lineY, t(tkStatsDistance), formatLargeNumber(runStats.movement.totalDistanceTraveled) & "px")
      lineY += 20
      drawStatLine(col2X + 10, lineY, t(tkStatsPhaseShifts), $runStats.movement.phaseShiftsUsed, SkyBlue)
      lineY += 20
      drawStatLine(col2X + 10, lineY, t(tkStatsTimeWarps), $runStats.movement.timeWarpsUsed, Purple)
      lineY += 20
      drawStatLine(col2X + 10, lineY, t(tkStatsNearDeaths), $runStats.movement.nearDeathCount, Red)
      lineY += 20
      drawStatLine(col2X + 10, lineY, t("stats_no_hit_streak"), formatDuration(runStats.movement.longestNoDamageStreak), Color(r: 80, g: 255, b: 80, a: 255))
      lineY += 20
      drawStatLine(col2X + 10, lineY, t(tkStatsTimeAtLowHP), formatDuration(runStats.movement.timeAtLowHP), Orange)
      lineY += 20
      drawStatLine(col2X + 10, lineY, "Successful Parries", $runStats.movement.successfulParries, Gold)
      lineY += 20
      drawStatLine(col2X + 10, lineY, "Time Invincible", formatDuration(runStats.movement.timeInvincible), SkyBlue)

      # Performance Stats Panel
      drawStatPanel(col3X, y, col1Width, 240, t(tkStatsPerformance))
      lineY = y + 36

      drawStatLine(col3X + 10, lineY, t(tkStatsPeakDPS), formatLargeNumber(runStats.performance.peakDPS), Color(r: 0, g: 180, b: 255, a: 255))
      lineY += 20
      drawStatLine(col3X + 10, lineY, t(tkStatsAverageDPS), formatLargeNumber(runStats.performance.averageDPS))
      lineY += 20
      drawStatLine(col3X + 10, lineY, t(tkStatsKillsPerMin), formatLargeNumber(runStats.performance.killsPerMinute))
      lineY += 20
      # Kill streak display removed
      # drawStatLine(col3X + 10, lineY, t(tkGameBestStreak), $runStats.performance.longestKillStreak, Gold)
      # lineY += 20
      if runStats.performance.waveTimes.len > 0:
        drawStatLine(col3X + 10, lineY, t(tkStatsAvgWave), formatDuration(runStats.performance.averageWaveTime))
        lineY += 20
        drawStatLine(col3X + 10, lineY, t(tkStatsFastestWave), formatDuration(runStats.performance.fastestWave), Color(r: 80, g: 255, b: 80, a: 255))

      # Second row - Resources, Play Style, DPS Graph (adjusted for taller combat panel)
      y += 312  # Increased from 252 to account for taller combat panel

      # Resources Panel
      drawStatPanel(col1X, y, col1Width, 220, t(tkStatsResources))
      lineY = y + 36

      drawStatLine(col1X + 10, lineY, t(tkStatsCoinsEarned), $runStats.resources.coinsEarned, Gold)
      lineY += 20
      drawStatLine(col1X + 10, lineY, t(tkStatsCoinsSpent), $runStats.resources.coinsSpent)
      lineY += 20
      drawStatLine(col1X + 10, lineY, t(tkStatsCoinsSaved), $runStats.resources.coinsAtEnd,
                  if runStats.resources.coinsAtEnd > 50: Color(r: 80, g: 255, b: 80, a: 255) else: Gray)
      lineY += 20
      drawStatLine(col1X + 10, lineY, t(tkStatsWallsPlaced), $runStats.resources.wallsPlaced)
      lineY += 20
      drawStatLine(col1X + 10, lineY, "Wall Dmg Blocked",
                   formatLargeNumber(runStats.resources.wallDamageBlocked * BALANCE_MULTIPLIER),
                   Color(r: 180, g: 140, b: 100, a: 255))
      lineY += 20
      drawStatLine(col1X + 10, lineY, t(tkStatsConsumables), $runStats.resources.consumablesCollected, Color(r: 0, g: 180, b: 255, a: 255))
      lineY += 20
      drawStatLine(col1X + 10, lineY, "Health Consumables", $runStats.resources.healthConsumablesUsed, Color(r: 80, g: 255, b: 80, a: 255))
      lineY += 20
      drawStatLine(col1X + 10, lineY, t(tkStatsShopPurchases), $runStats.resources.shopVisits, Color(r: 255, g: 150, b: 50, a: 255))
      if runStats.gameMode == gmRoguelite:
        lineY += 20
        drawStatLine(col1X + 10, lineY, t("roguelite_data_shards"), $runStats.rogueliteShardsEarned, Gold)

      # Play Style Panel
      drawStatPanel(col2X, y, col1Width, 200, t(tkStatsPlayStyle))
      lineY = y + 36

      let styleColor = case runStats.comparison.playStyle
        of "Aggressive": Red
        of "Defensive": SkyBlue
        of "Mobile": Green
        of "Tank": Orange
        of "Balanced": White
        else: White

      let styleText = case runStats.comparison.playStyle
        of "Aggressive": t("stats_play_style_aggressive")
        of "Defensive": t("stats_play_style_defensive")
        of "Mobile": t("stats_play_style_mobile")
        of "Tank": t("stats_play_style_tank")
        of "Balanced": t("stats_play_style_balanced")
        else: runStats.comparison.playStyle

      drawText(styleText, (col2X + 10).int32, lineY.int32, 20, styleColor)
      lineY += 35

      drawText(t(tkStatsAggression), (col2X + 10).int32, lineY.int32, 14, White)
      lineY += 20
      let aggressionBar = int(runStats.comparison.aggressionRating * 2.4)
      drawRectangle((col2X + 10).int32, lineY.int32, aggressionBar.int32, 16,
                   Color(r: 255, g: 100, b: 100, a: 200))
      drawRectangleLines(Rectangle(x: (col2X + 10).float32, y: lineY.float32,
                                    width: 240.0, height: 16.0),
                        1, Color(r: 80, g: 80, b: 100, a: 255))
      lineY += 30

      drawText(t(tkStatsCaution), (col2X + 10).int32, lineY.int32, 14, White)
      lineY += 20
      let cautionBar = int(runStats.comparison.cautionRating * 2.4)
      drawRectangle((col2X + 10).int32, lineY.int32, cautionBar.int32, 16,
                   Color(r: 100, g: 200, b: 255, a: 200))
      drawRectangleLines(Rectangle(x: (col2X + 10).float32, y: lineY.float32,
                                    width: 240.0, height: 16.0),
                        1, Color(r: 80, g: 80, b: 100, a: 255))

      # DPS Graph
      if runStats.performance.dpsHistory.len > 0:
        drawMiniGraph(col3X, y, col1Width, 200, t(tkStatsDpsOverTime),
                     runStats.performance.dpsHistory,
                     max(runStats.performance.peakDPS, 1.0),
                     Color(r: 255, g: 150, b: 50, a: 255), statsWin.animTime)
      else:
        drawStatPanel(col3X, y, col1Width, 200, t("stats_dps_over_time_label"))
        drawText(t(tkGameNoGraphData), (col3X + col1Width div 2 - 50).int32, (y + 100).int32, 14, Gray)
    else:
      let y = tabContentY + tabContentH div 2 - 30
      drawText(t(tkGameNoPreviousRun),
              (contentX + contentW div 2 - 180).int32, y.int32, 18, LightGray)
      drawText(t(tkGameCompleteGameStats),
              (contentX + contentW div 2 - 200).int32, (y + 25).int32, 16, Gray)

  of stPowerUps:
    if hasLastRun:
      let runStats = getLastRunStats()
      var y = tabContentY + 20

      # Header with summary
      drawText(t(tkStatsPowerUpBreakdown), (contentX + 20).int32, y.int32, 24, Color(r: 255, g: 200, b: 50, a: 255))
      y += 30

      let summaryText = $runStats.powerUps.totalPowerUps & " " & t(tkStatsTotal) & " | " &
                       $runStats.powerUps.legendaryPowerUps & " " & t(tkStatsLegendaryCount) & " | " &
                       $runStats.powerUps.commonPowerUps & " " & t(tkStatsCommonCount)
      drawText(summaryText, (contentX + 20).int32, y.int32, 16, LightGray)
      y += 35

      # Two columns: Timeline and Effectiveness
      let col1Width = (contentW - 36) div 2
      let col1X = contentX + 12
      let col2X = col1X + col1Width + 12

      # Power-Up Timeline
      drawStatPanel(col1X, y, col1Width, 400, t(tkStatsTimeline))
      var lineY = y + 36

      if runStats.powerUps.powerUpsChosen.len > 0:
        for i, choice in runStats.powerUps.powerUpsChosen:
          if lineY > y + 380: break

          let timestamp = formatDuration(choice[0])
          let powerup = choice[1]
          let powerupName = getPowerUpName(powerup.powerType)

          let rarityColor = if powerup.rarity == prLegendary: Gold else: White

          drawText(timestamp, (col1X + 10).int32, lineY.int32, 13, LightGray)
          drawText(powerupName, (col1X + 80).int32, lineY.int32, 13, rarityColor)
          drawText(t(tkStatsLevelPrefix) & $powerup.level, (col1X + col1Width - 50).int32, lineY.int32, 13, Orange)
          lineY += 18
      else:
        drawText(t(tkStatsNoPowerUpsSelected), (col1X + 10).int32, lineY.int32, 14, Gray)

      # Effectiveness Ranking
      drawStatPanel(col2X, y, col1Width, 400, t(tkStatsEffectivenessRanking))
      lineY = y + 36

      # Sort by damage contribution
      var contributions: seq[(PowerUpType, float32)] = @[]
      for ptype, damage in runStats.powerUps.damageContribution:
        contributions.add((ptype, damage))

      # Sort by damage (descending) using efficient built-in sort
      if contributions.len > 1:
        contributions.sort(proc (a, b: (PowerUpType, float32)): int =
          cmp(b[1], a[1])  # Descending order: b[1] compared to a[1]
        )

      if contributions.len > 0:
        drawText(t(tkStatsRank), (col2X + 10).int32, lineY.int32, 12, Color(r: 0, g: 180, b: 255, a: 255))
        drawText(t(tkStatsPowerUp), (col2X + 50).int32, lineY.int32, 12, Color(r: 0, g: 180, b: 255, a: 255))
        drawText(t(tkStatsDamageColumnLabel), (col2X + 180).int32, lineY.int32, 12, Color(r: 0, g: 180, b: 255, a: 255))
        lineY += 20

        var sumContrib = 0.0'f32
        for contrib in contributions:
          sumContrib += contrib[1]

        for i, contrib in contributions:
          if lineY > y + 380: break

          let rank = i + 1
          let ptype = contrib[0]
          let damage = contrib[1]
          let percent = if sumContrib > 0: (damage / sumContrib) * 100.0 else: 0.0

          let medalColor = case rank
            of 1: Gold
            of 2: Color(r: 192, g: 192, b: 192, a: 255)
            of 3: Color(r: 205, g: 127, b: 50, a: 255)
            else: White

          drawText($rank & ".", (col2X + 15).int32, lineY.int32, 13, medalColor)
          drawText(getPowerUpName(ptype), (col2X + 50).int32, lineY.int32, 13, White)
          # Multiply damage by BALANCE_MULTIPLIER for display (keep as large number)
          drawText(formatLargeNumber(damage * BALANCE_MULTIPLIER), (col2X + 180).int32, lineY.int32, 13, Color(r: 0, g: 180, b: 255, a: 255))
          drawText(formatPercent(percent), (col2X + col1Width - 50).int32, lineY.int32, 13,
                  getQualityColor(percent, 10.0))

          lineY += 18
      else:
        drawText(t(tkStatsNoDamageData), (col2X + 10).int32, lineY.int32, 14, Gray)

      # Healing Sources sub-section
      lineY += 28
      drawText(t(tkStatsHealingSources), (col2X + 10).int32, lineY.int32, 14, Color(r: 80, g: 255, b: 160, a: 255))
      lineY += 20

      # Build combined list: power-up healing + health consumable healing
      var healList: seq[(string, float32)] = @[]
      for ptype, amount in runStats.powerUps.healingContribution:
        if amount > 0:
          healList.add((getPowerUpName(ptype), amount))
      let consumableHealing = float32(runStats.resources.healthConsumablesUsed) *
                              (0.75'f32 + 0.025'f32 * runStats.finalMaxHP)
      if consumableHealing > 0:
        healList.add((t(tkStatsHealthConsumable), consumableHealing))
      healList.sort(proc(a, b: (string, float32)): int = cmp(b[1], a[1]))

      if healList.len > 0:
        for hc in healList:
          if lineY > tabContentY + tabContentH - 20: break
          drawText(hc[0], (col2X + 10).int32, lineY.int32, 13, Color(r: 80, g: 255, b: 160, a: 255))
          drawText(formatLargeNumber(hc[1] * BALANCE_MULTIPLIER), (col2X + 180).int32, lineY.int32, 13, Color(r: 80, g: 255, b: 160, a: 255))
          lineY += 18
      else:
        drawText(t(tkStatsNoHealingData), (col2X + 10).int32, lineY.int32, 13, Gray)
    else:
      let y = tabContentY + tabContentH div 2 - 20
      drawText(t(tkGameNoPowerUpData),
              (contentX + contentW div 2 - 150).int32, y.int32, 18, LightGray)

  of stRoguelite:
    var y = tabContentY + 24
    drawText(t("stats_roguelite_metrics"), (contentX + 28).int32, y.int32, 22,
            Color(r: 0, g: 220, b: 180, a: 255))
    y += 44
    let cardWidth = (contentW - 80) div 3
    drawMetricCard(contentX + 20, y, cardWidth, 70,
                  t("stats_roguelite_runs"), $statsWin.stats.rogueliteMode.gamesPlayed,
                  '#', Color(r: 0, g: 220, b: 180, a: 255))
    drawMetricCard(contentX + 40 + cardWidth, y, cardWidth, 70,
                  t("stats_roguelite_best_sectors"), $statsWin.stats.rogueliteMode.highestWaveReached,
                  '>', Gold)
    drawMetricCard(contentX + 60 + cardWidth * 2, y, cardWidth, 70,
                  t(tkStatsBossKills), $statsWin.stats.rogueliteMode.bossesDefeated,
                  '*', Red)
    y += 100
    drawStatPanel(contentX + 25, y, contentW - 50, 220, t("stats_roguelite_lifetime"))
    var lineY = y + 42
    drawStatLine(contentX + 45, lineY, t(tkStatsPeakKills), $statsWin.stats.rogueliteMode.bestKills, Red)
    lineY += 24
    drawStatLine(contentX + 45, lineY, t(tkStatsTotalEarned), $statsWin.stats.rogueliteMode.totalCoins, Gold)
    lineY += 24
    drawStatLine(contentX + 45, lineY, t(tkStatsPlaytime), formatTime(statsWin.stats.rogueliteMode.totalTimePlayed))
    lineY += 24
    drawStatLine(contentX + 45, lineY, t(tkStatsAvgWave),
                 formatFloat(statsWin.stats.rogueliteMode.averageWaveReached, ffDecimal, 1))
    lineY += 24
    if hasLastRun and getLastRunStats().gameMode == gmRoguelite:
      let last = getLastRunStats()
      drawStatLine(contentX + 45, lineY, t("roguelite_heat"), $last.rogueliteHeat)
      lineY += 24
      drawStatLine(contentX + 45, lineY, t("roguelite_endless"), $last.rogueliteEndlessLoop)
      lineY += 24
      drawStatLine(contentX + 45, lineY, t("roguelite_relics"), $last.rogueliteRelics.len, Color(r: 0, g: 220, b: 180, a: 255))

  drawResizeIndicator(statsWin.window)

# FULL-SCREEN STATS VIEW FOR GAME OVER
proc drawGameOverStatsScreen*(stats: RunStatistics, screenWidth, screenHeight: int32,
                              gameTime: float32, showGraphs: bool = true) =
  ## Draw full-screen OS-themed statistics for game over screen

  # Background with scan line effect
  clearBackground(Color(r: 20, g: 20, b: 30, a: 255))

  for i in 0..<(screenHeight div 3):
    let lineY = i * 3 + int32(gameTime * 50.0) mod 3
    let alpha = uint8(3 + sin(gameTime + i.float32) * 3.0)
    drawLine(Vector2(x: 0, y: lineY.float32),
            Vector2(x: screenWidth.float32, y: lineY.float32),
            1, Color(r: 40, g: 60, b: 80, a: alpha))

  # Main panel
  let panelWidth = min(screenWidth - 40, 1000)
  let panelHeight = min(screenHeight - 80, 700)
  let panelX = (screenWidth - panelWidth) div 2
  let panelY = (screenHeight - panelHeight) div 2 + 20

  # Panel shadow
  drawRectangle((panelX + 4).int32, (panelY + 4).int32, panelWidth, panelHeight,
               Color(r: 0, g: 0, b: 0, a: 100))

  # Panel background
  drawRectangle(panelX, panelY, panelWidth, panelHeight,
               Color(r: 30, g: 30, b: 40, a: 230))

  # Panel border with glow
  let glowPulse = sin(gameTime * 2.0) * 0.15 + 0.85
  drawRectangleLines(Rectangle(x: panelX.float32, y: panelY.float32,
                                width: panelWidth.float32, height: panelHeight.float32),
                    2, Color(r: uint8(80.0 * glowPulse), g: uint8(80.0 * glowPulse),
                            b: uint8(100.0 * glowPulse), a: 255))

  # Title bar
  drawRectangle(panelX, panelY, panelWidth, 32, Color(r: 40, g: 40, b: 50, a: 255))
  drawRectangle(panelX, panelY, panelWidth, 2, Color(r: 0, g: 180, b: 255, a: 255))
  drawText("[#] " & t(tkStatsAnalyticsReport), (panelX + 8).int32, (panelY + 8).int32, 16, White)

  # Content area
  let contentX = panelX + 15
  let contentY = panelY + 42
  let contentW = panelWidth - 30
  let contentH = panelHeight - 52

  # Header with key metrics
  let headerH: int32 = 70
  drawRectangle(contentX, contentY, contentW, headerH,
               Color(r: 25, g: 35, b: 50, a: 255))

  # Mode and wave
  let modeText = case stats.gameMode
    of gmWaveBased: t("stats_wave_mode")
    of gmTimeSurvival: t("stats_time_survival_mode")
    of gmSandbox: t("stats_sandbox_mode")
    of gmPvP: t("stats_pvp_mode")
    of gmRoguelite: t("stats_roguelite_mode")

  drawText(modeText, (contentX + 10).int32, (contentY + 8).int32, 12, Color(r: 0, g: 180, b: 255, a: 255))
  let scoreLabel = if stats.gameMode == gmRoguelite: t("roguelite_sector") else: t("stats_wave_label")
  drawText(scoreLabel & " " & $stats.waveReached, (contentX + 10).int32, (contentY + 24).int32, 24, Color(r: 255, g: 200, b: 50, a: 255))

  # Key stats
  var mx = contentX + 180
  drawText(t("stats_time_column_label"), mx.int32, (contentY + 8).int32, 10, Gray)
  drawText(formatDuration(stats.runDuration), mx.int32, (contentY + 24).int32, 18, White)
  mx += 120

  drawText(t("stats_kills_label"), mx.int32, (contentY + 8).int32, 10, Gray)
  drawText($stats.combat.totalKills, mx.int32, (contentY + 24).int32, 18, Color(r: 80, g: 255, b: 80, a: 255))
  mx += 100

  drawText(t("stats_accuracy_label").toUpper, mx.int32, (contentY + 8).int32, 10, Gray)
  drawText(formatPercent(stats.combat.accuracyPercent), mx.int32, (contentY + 24).int32, 18,
          getQualityColor(stats.combat.accuracyPercent, 60.0))
  mx += 120

  drawText(t("stats_avg_dps"), mx.int32, (contentY + 8).int32, 10, Gray)
  drawText(formatLargeNumber(stats.performance.averageDPS), mx.int32, (contentY + 24).int32, 18, Color(r: 255, g: 200, b: 50, a: 255))

  # Main content area
  let mainY = contentY + headerH + 10
  let mainH = contentH - headerH - 50

  # Three columns
  let colW = (contentW - 24) div 3
  let col1X = contentX
  let col2X = col1X + colW + 12
  let col3X = col2X + colW + 12
  var y = mainY

  # Combat stats
  drawStatPanel(col1X, y, colW, 220, t("stats_combat_label"))
  var lineY = y + 36
  drawStatLine(col1X + 8, lineY, t("stats_accuracy_label"), formatPercent(stats.combat.accuracyPercent),
              getQualityColor(stats.combat.accuracyPercent, 60.0))
  lineY += 18
  drawStatLine(col1X + 8, lineY, t("stats_shots_fired_label"), $stats.combat.shotsFired)
  lineY += 18
  drawStatLine(col1X + 8, lineY, t("stats_shots_hit_label"), $stats.combat.shotsHit, Color(r: 80, g: 255, b: 80, a: 255))
  lineY += 18
  drawStatLine(col1X + 8, lineY, t("stats_damage_dealt"), formatLargeNumber(stats.combat.totalDamageDealt * BALANCE_MULTIPLIER), Orange)
  lineY += 18
  drawStatLine(col1X + 8, lineY, t("stats_damage_taken"), formatLargeNumber(stats.combat.totalDamageTaken * BALANCE_MULTIPLIER), Red)
  lineY += 18
  drawStatLine(col1X + 8, lineY, t("stats_elite_kills"), $stats.combat.eliteKills, Orange)
  lineY += 18
  drawStatLine(col1X + 8, lineY, t("stats_boss_kills"), $stats.combat.bossKills, Red)
  lineY += 18
  drawStatLine(col1X + 8, lineY, t("stats_critical_hits"), $stats.combat.criticalHits, Color(r: 0, g: 180, b: 255, a: 255))

  # Movement stats
  drawStatPanel(col2X, y, colW, 220, t("stats_movement_label"))
  lineY = y + 36
  drawStatLine(col2X + 8, lineY, t("stats_distance_label"), formatLargeNumber(stats.movement.totalDistanceTraveled) & "px")
  lineY += 18
  drawStatLine(col2X + 8, lineY, t("stats_phase_shifts_label"), $stats.movement.phaseShiftsUsed, SkyBlue)
  lineY += 18
  drawStatLine(col2X + 8, lineY, t("stats_time_warps_label"), $stats.movement.timeWarpsUsed, Purple)
  lineY += 18
  drawStatLine(col2X + 8, lineY, t("stats_near_deaths_label"), $stats.movement.nearDeathCount, Red)
  lineY += 18
  drawStatLine(col2X + 8, lineY, t("stats_no_hit_streak"), formatDuration(stats.movement.longestNoDamageStreak), Color(r: 80, g: 255, b: 80, a: 255))
  lineY += 18
  drawStatLine(col2X + 8, lineY, t("stats_time_low_hp_label"), formatDuration(stats.movement.timeAtLowHP), Orange)

  # Performance stats
  drawStatPanel(col3X, y, colW, 220, t("stats_performance_label"))
  lineY = y + 36
  drawStatLine(col3X + 8, lineY, t("stats_peak_dps_label"), formatLargeNumber(stats.performance.peakDPS), Color(r: 0, g: 180, b: 255, a: 255))
  lineY += 18
  drawStatLine(col3X + 8, lineY, t("stats_avg_dps_label"), formatLargeNumber(stats.performance.averageDPS))
  lineY += 18
  drawStatLine(col3X + 8, lineY, t("stats_kills_min_label"), formatLargeNumber(stats.performance.killsPerMinute))
  lineY += 18
  # Kill streak display removed
  # drawStatLine(col3X + 8, lineY, "Best Streak", $stats.performance.longestKillStreak, Gold)
  # lineY += 18
  if stats.performance.waveTimes.len > 0:
    drawStatLine(col3X + 8, lineY, t("stats_avg_wave_label"), formatDuration(stats.performance.averageWaveTime))
    lineY += 18
    drawStatLine(col3X + 8, lineY, t("stats_fast_wave_label"), formatDuration(stats.performance.fastestWave), Color(r: 80, g: 255, b: 80, a: 255))

  # Second row
  y += 232
  let row2H = mainH - 232

  # Resources
  drawStatPanel(col1X, y, colW, row2H, t("stats_resources_label"))
  lineY = y + 36
  drawStatLine(col1X + 8, lineY, t("stats_coins_earned_label"), $stats.resources.coinsEarned, Gold)
  lineY += 18
  drawStatLine(col1X + 8, lineY, t("stats_coins_spent_label"), $stats.resources.coinsSpent)
  lineY += 18
  drawStatLine(col1X + 8, lineY, t("stats_coins_saved_label"), $stats.resources.coinsAtEnd,
              if stats.resources.coinsAtEnd > 50: Color(r: 80, g: 255, b: 80, a: 255) else: Gray)
  lineY += 18
  drawStatLine(col1X + 8, lineY, t("stats_walls_placed_label"), $stats.resources.wallsPlaced)
  lineY += 18
  drawStatLine(col1X + 8, lineY, "Wall Dmg Blocked",
               formatLargeNumber(stats.resources.wallDamageBlocked * BALANCE_MULTIPLIER),
               Color(r: 180, g: 140, b: 100, a: 255))
  lineY += 18
  drawStatLine(col1X + 8, lineY, t("stats_consumables_label"), $stats.resources.consumablesCollected, Color(r: 0, g: 180, b: 255, a: 255))
  lineY += 18
  drawStatLine(col1X + 8, lineY, t("stats_shop_purchases_label"), $stats.resources.shopVisits, Color(r: 255, g: 150, b: 50, a: 255))
  if stats.gameMode == gmRoguelite:
    lineY += 18
    drawStatLine(col1X + 8, lineY, t("roguelite_data_shards"), $stats.rogueliteShardsEarned, Gold)

  # Play style
  drawStatPanel(col2X, y, colW, row2H, t("stats_play_style_label"))
  lineY = y + 36
  let styleColor = case stats.comparison.playStyle
    of "Aggressive": Red
    of "Defensive": SkyBlue
    of "Mobile": Green
    of "Tank": Orange
    of "Balanced": White
    else: White
  let styleText = case stats.comparison.playStyle
    of "Aggressive": t("stats_play_style_aggressive")
    of "Defensive": t("stats_play_style_defensive")
    of "Mobile": t("stats_play_style_mobile")
    of "Tank": t("stats_play_style_tank")
    of "Balanced": t("stats_play_style_balanced")
    else: stats.comparison.playStyle
  drawText(styleText, (col2X + 8).int32, lineY.int32, 18, styleColor)
  lineY += 30
  drawText(t("stats_aggression_label"), (col2X + 8).int32, lineY.int32, 12, White)
  lineY += 16
  let aggrBar = int(stats.comparison.aggressionRating * 2.2)
  drawRectangle((col2X + 8).int32, lineY.int32, aggrBar.int32, 14,
               Color(r: 255, g: 100, b: 100, a: 200))
  drawRectangleLines(Rectangle(x: (col2X + 8).float32, y: lineY.float32,
                                width: 220.0, height: 14.0),
                    1, Color(r: 80, g: 80, b: 100, a: 255))
  lineY += 26
  drawText(t("stats_caution_label"), (col2X + 8).int32, lineY.int32, 12, White)
  lineY += 16
  let cautBar = int(stats.comparison.cautionRating * 2.2)
  drawRectangle((col2X + 8).int32, lineY.int32, cautBar.int32, 14,
               Color(r: 100, g: 200, b: 255, a: 200))
  drawRectangleLines(Rectangle(x: (col2X + 8).float32, y: lineY.float32,
                                width: 220.0, height: 14.0),
                    1, Color(r: 80, g: 80, b: 100, a: 255))

  # DPS graph
  if showGraphs and stats.performance.dpsHistory.len > 0:
    drawMiniGraph(col3X, y, colW, row2H, t("stats_dps_over_time_label"),
                 stats.performance.dpsHistory,
                 max(stats.performance.peakDPS, 1.0),
                 Color(r: 255, g: 150, b: 50, a: 255), gameTime)
  else:
    drawStatPanel(col3X, y, colW, row2H, t(tkStatsDPSOverTime))
    let noDataY = y + row2H div 2
    drawText(t(tkStatsNoGraphDataShort), (col3X + colW div 2 - 50).int32, noDataY.int32, 12, Gray)

  # Footer with controls
  let footerY = panelY + panelHeight - 40
  drawRectangle(panelX, footerY, panelWidth, 40,
               Color(r: 30, g: 40, b: 55, a: 255))
  drawRectangleLines(Rectangle(x: panelX.float32, y: footerY.float32,
                                width: panelWidth.float32, height: 40.0),
                    1, Color(r: 80, g: 80, b: 100, a: 255))

  let footerText = t(tkStatsControlsFooter)
  let footerWidth = measureText(footerText, 14)
  drawText(footerText, (panelX + (panelWidth - footerWidth) div 2).int32, (footerY + 12).int32, 14, Color(r: 0, g: 180, b: 255, a: 255))
