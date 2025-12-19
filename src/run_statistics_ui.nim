# ============================================================================
# RUN STATISTICS UI
# Visual rendering of per-run statistics with graphs and comparisons
# Displays on Game Over screen and Main Menu
# ============================================================================

import raylib, run_statistics_types, types, strutils, math, times, std/tables, algorithm

# ============================================================================
# UI CONSTANTS
# ============================================================================

const
  CARD_BG_COLOR = Color(r: 30, g: 30, b: 40, a: 230)
  CARD_BORDER_COLOR = Color(r: 80, g: 80, b: 100, a: 255)
  ACCENT_COLOR = Color(r: 255, g: 200, b: 50, a: 255)
  GOOD_COLOR = Color(r: 80, g: 255, b: 80, a: 255)
  BAD_COLOR = Color(r: 255, g: 80, b: 80, a: 255)
  GRAPH_LINE_COLOR = Color(r: 100, g: 200, b: 255, a: 255)
  GRAPH_GRID_COLOR = Color(r: 60, g: 60, b: 80, a: 100)

# ============================================================================
# HELPER PROCS FOR FORMATTING
# ============================================================================

proc formatPercent*(value: float32): string =
  ## Format percentage with 1 decimal place
  result = value.formatFloat(ffDecimal, 1) & "%"

proc formatLargeNumber*(value: float32): string =
  ## Format large numbers with K/M suffix
  if value >= 1_000_000:
    result = (value / 1_000_000).formatFloat(ffDecimal, 1) & "M"
  elif value >= 1_000:
    result = (value / 1_000).formatFloat(ffDecimal, 1) & "K"
  else:
    result = value.formatFloat(ffDecimal, 1)

proc formatDuration*(seconds: float32): string =
  ## Format time duration as MM:SS
  let mins = int(seconds) div 60
  let secs = int(seconds) mod 60
  result = align($mins, 2, '0') & ":" & align($secs, 2, '0')

proc getQualityColor*(value: float32, threshold: float32 = 50.0): Color =
  ## Return color based on quality (green=good, red=bad)
  if value >= threshold:
    return GOOD_COLOR
  elif value >= threshold * 0.5:
    return ACCENT_COLOR
  else:
    return BAD_COLOR

# ============================================================================
# CARD DRAWING HELPERS
# ============================================================================

proc drawStatCard*(x, y, width, height: int32, title: string, gameTime: float32) =
  ## Draw a background card for stats section
  let pulse = sin(gameTime * 2.0) * 5 + 5
  
  # Shadow
  drawRectangle(x + 3, y + 3, width, height, 
               Color(r: 0, g: 0, b: 0, a: 80))
  
  # Card background
  drawRectangle(x, y, width, height, CARD_BG_COLOR)
  
  # Border with slight glow
  drawRectangleLines(Rectangle(x: x.float32, y: y.float32, width: width.float32, height: height.float32), 
                      2, CARD_BORDER_COLOR)
  
  # Title bar
  drawRectangle(x, y, width, 30, 
               Color(r: 40, g: 40, b: 50, a: 255))
  drawText(title, x + 10, y + 5, 18, ACCENT_COLOR)

proc drawMetricRow*(x, y: int32, label: string, value: string, valueColor: Color = White) =
  ## Draw a labeled metric row
  drawText(label, x, y, 16, LightGray)
  let valueWidth = measureText(value, 16)
  drawText(value, x + 250 - valueWidth, y, 16, valueColor)

proc drawProgressBar*(x, y, width, height: int32, value, maxValue: float32, color: Color) =
  ## Draw a horizontal progress bar
  let fillWidth = int32((value / maxValue) * width.float32)
  
  # Background
  drawRectangle(x, y, width, height, Color(r: 40, g: 40, b: 50, a: 255))
  
  # Fill
  if fillWidth > 0:
    drawRectangle(x, y, fillWidth, height, color)
  
  # Border
  drawRectangleLines(Rectangle(x: x.float32, y: y.float32, width: width.float32, height: height.float32),
                      1, Color(r: 100, g: 100, b: 120, a: 255))

# ============================================================================
# GRAPH VISUALIZATION
# ============================================================================

proc drawTimelineGraph*(x, y, width, height: int32, title: string, 
                       dataPoints: seq[(float32, float32)], 
                       maxValue: float32, color: Color = GRAPH_LINE_COLOR) =
  ## Draw a line graph showing data over time
  if dataPoints.len == 0:
    return
  
  # Card background
  drawRectangle(x, y, width, height, CARD_BG_COLOR)
  drawRectangleLines(Rectangle(x: x.float32, y: y.float32, width: width.float32, height: height.float32),
                      2, CARD_BORDER_COLOR)
  
  # Title
  drawText(title, x + 10, y + 5, 14, ACCENT_COLOR)
  
  # Graph area
  let graphX = x + 20
  let graphY = y + 30
  let graphWidth = width - 40
  let graphHeight = height - 50
  
  # Grid lines
  for i in 0..4:
    let gridY = graphY + int32((i.float32 / 4.0) * graphHeight.float32)
    drawLine(Vector2(x: graphX.float32, y: gridY.float32),
            Vector2(x: (graphX + graphWidth).float32, y: gridY.float32),
            1, GRAPH_GRID_COLOR)
  
  # Find time range
  var minTime = float32.high
  var maxTime = 0.0'f32
  for point in dataPoints:
    minTime = min(minTime, point[0])
    maxTime = max(maxTime, point[0])
  
  let timeRange = max(maxTime - minTime, 0.1)
  
  # Draw line graph
  for i in 0..<dataPoints.len-1:
    let x1Norm = (dataPoints[i][0] - minTime) / timeRange
    let y1Norm = 1.0 - (dataPoints[i][1] / maxValue)
    let x2Norm = (dataPoints[i+1][0] - minTime) / timeRange
    let y2Norm = 1.0 - (dataPoints[i+1][1] / maxValue)
    
    let x1Px = graphX.float32 + x1Norm * graphWidth.float32
    let y1Px = graphY.float32 + y1Norm * graphHeight.float32
    let x2Px = graphX.float32 + x2Norm * graphWidth.float32
    let y2Px = graphY.float32 + y2Norm * graphHeight.float32
    
    drawLine(Vector2(x: x1Px, y: y1Px),
            Vector2(x: x2Px, y: y2Px),
            2, color)
  
  # Y-axis labels
  drawText("0", x + 5, graphY + graphHeight - 10, 10, LightGray)
  drawText(formatLargeNumber(maxValue), x + 5, graphY, 10, LightGray)

proc drawHeatmap*(x, y, width, height: int32, positions: seq[Vector2f], 
                 screenWidth, screenHeight: int32) =
  ## Draw a heatmap showing player positioning
  if positions.len == 0:
    return
  
  # Card background
  drawRectangle(x, y, width, height, CARD_BG_COLOR)
  drawRectangleLines(Rectangle(x: x.float32, y: y.float32, width: width.float32, height: height.float32),
                      2, CARD_BORDER_COLOR)
  
  # Title
  drawText("Position Heatmap", x + 10, y + 5, 14, ACCENT_COLOR)
  
  # Minimap area
  let mapX = x + 20
  let mapY = y + 30
  let mapWidth = width - 40
  let mapHeight = height - 50
  
  # Draw minimap border
  drawRectangle(mapX, mapY, mapWidth, mapHeight, Color(r: 20, g: 20, b: 30, a: 255))
  drawRectangleLines(Rectangle(x: mapX.float32, y: mapY.float32, 
                                width: mapWidth.float32, height: mapHeight.float32),
                      1, Color(r: 100, g: 100, b: 120, a: 255))
  
  # Draw position dots
  for pos in positions:
    let mapPosX = mapX.float32 + (pos.x / screenWidth.float32) * mapWidth.float32
    let mapPosY = mapY.float32 + (pos.y / screenHeight.float32) * mapHeight.float32
    drawCircle(Vector2(x: mapPosX, y: mapPosY), 2, 
              Color(r: 255, g: 200, b: 50, a: 100))

# ============================================================================
# MAIN STAT SECTIONS
# ============================================================================

proc drawCombatStats*(stats: CombatStats, x, y: int32, gameTime: float32) =
  ## Draw combat statistics section
  drawStatCard(x, y, 300, 340, "COMBAT", gameTime)
  
  var lineY = y + 40
  
  # Accuracy
  let accuracyColor = getQualityColor(stats.accuracyPercent, 60.0)
  drawMetricRow(x + 10, lineY, "Accuracy", formatPercent(stats.accuracyPercent), accuracyColor)
  lineY += 22
  
  drawMetricRow(x + 10, lineY, "Shots Fired", $stats.shotsFired)
  lineY += 20
  drawMetricRow(x + 10, lineY, "Shots Hit", $stats.shotsHit)
  lineY += 20
  drawMetricRow(x + 10, lineY, "Shots Missed", $stats.shotsMissed)
  lineY += 30
  
  # Damage
  drawMetricRow(x + 10, lineY, "Damage Dealt", formatLargeNumber(stats.totalDamageDealt))
  lineY += 20
  drawMetricRow(x + 10, lineY, "Damage Taken", formatLargeNumber(stats.totalDamageTaken))
  lineY += 20
  drawMetricRow(x + 10, lineY, "Largest Hit", formatLargeNumber(stats.largestSingleHit), ACCENT_COLOR)
  lineY += 30
  
  # Kills
  drawMetricRow(x + 10, lineY, "Total Kills", $stats.totalKills, Gold)
  lineY += 20
  drawMetricRow(x + 10, lineY, "Elite Kills", $stats.eliteKills, Orange)
  lineY += 20
  drawMetricRow(x + 10, lineY, "Boss Kills", $stats.bossKills, Red)
  lineY += 20
  drawMetricRow(x + 10, lineY, "Critical Hits", $stats.criticalHits, ACCENT_COLOR)

proc drawMovementStats*(stats: MovementStats, x, y: int32, gameTime: float32) =
  ## Draw movement and survivability statistics
  drawStatCard(x, y, 300, 340, "MOVEMENT & SURVIVAL", gameTime)
  
  var lineY = y + 40
  
  # Distance
  drawMetricRow(x + 10, lineY, "Distance", formatLargeNumber(stats.totalDistanceTraveled) & " px")
  lineY += 20
  drawMetricRow(x + 10, lineY, "Avg Speed", formatLargeNumber(stats.averageSpeed) & " px/s")
  lineY += 30
  
  # Legendary abilities
  drawMetricRow(x + 10, lineY, "Phase Shifts", $stats.phaseShiftsUsed, SkyBlue)
  lineY += 20
  drawMetricRow(x + 10, lineY, "Time Warps", $stats.timeWarpsUsed, Color(r: 138, g: 43, b: 226, a: 255))
  lineY += 20
  drawMetricRow(x + 10, lineY, "Parries", $stats.parriesUsed & " (" & $stats.successfulParries & ")", White)
  lineY += 30
  
  # Survivability
  drawMetricRow(x + 10, lineY, "Near Deaths", $stats.nearDeathCount, BAD_COLOR)
  lineY += 20
  drawMetricRow(x + 10, lineY, "Hits Taken", $stats.hitsTakenCount)
  lineY += 20
  drawMetricRow(x + 10, lineY, "Time at Low HP", formatDuration(stats.timeAtLowHP), Orange)
  lineY += 20
  drawMetricRow(x + 10, lineY, "Longest Streak", formatDuration(stats.longestNoDamageStreak), GOOD_COLOR)
  lineY += 20
  drawMetricRow(x + 10, lineY, "Invincible Time", formatDuration(stats.timeInvincible), SkyBlue)

proc drawResourceStats*(stats: ResourceStats, x, y: int32, gameTime: float32) =
  ## Draw resource management statistics
  drawStatCard(x, y, 300, 270, "RESOURCES", gameTime)
  
  var lineY = y + 40
  
  # Coins
  drawMetricRow(x + 10, lineY, "Coins Earned", $stats.coinsEarned, Gold)
  lineY += 20
  drawMetricRow(x + 10, lineY, "Coins Spent", $stats.coinsSpent)
  lineY += 20
  drawMetricRow(x + 10, lineY, "Coins Saved", $stats.coinsAtEnd, 
               if stats.coinsAtEnd > 50: GOOD_COLOR else: LightGray)
  lineY += 20
  let efficiency = if stats.coinEfficiency > 0: formatLargeNumber(stats.coinEfficiency) else: "0.0"
  drawMetricRow(x + 10, lineY, "Coins/Kill", efficiency)
  lineY += 30
  
  # Walls
  drawMetricRow(x + 10, lineY, "Walls Placed", $stats.wallsPlaced)
  lineY += 20
  drawMetricRow(x + 10, lineY, "Walls Destroyed", $stats.wallsDestroyed)
  lineY += 20
  drawMetricRow(x + 10, lineY, "Damage Blocked", formatLargeNumber(stats.wallDamageBlocked), GOOD_COLOR)
  lineY += 30
  
  # Consumables
  drawMetricRow(x + 10, lineY, "Consumables", $stats.consumablesCollected)
  lineY += 20
  drawMetricRow(x + 10, lineY, "Health Potions", $stats.healthPotionsUsed, Green)

proc drawPowerUpStats*(stats: PowerUpStats, x, y: int32, gameTime: float32) =
  ## Draw power-up statistics
  drawStatCard(x, y, 300, 200, "POWER-UPS", gameTime)
  
  var lineY = y + 40
  
  drawMetricRow(x + 10, lineY, "Total Chosen", $stats.totalPowerUps)
  lineY += 20
  drawMetricRow(x + 10, lineY, "Common", $stats.commonPowerUps, White)
  lineY += 20
  drawMetricRow(x + 10, lineY, "Legendary", $stats.legendaryPowerUps, Gold)
  lineY += 30
  
  drawMetricRow(x + 10, lineY, "Level 1", $stats.level1PowerUps)
  lineY += 20
  drawMetricRow(x + 10, lineY, "Level 2", $stats.level2PowerUps)
  lineY += 20
  drawMetricRow(x + 10, lineY, "Level 3", $stats.level3PowerUps)
  
  # Most effective power-up
  if stats.damageContribution.len > 0:
    lineY += 30
    let mvp = $stats.mostEffectivePowerUp
    drawText("MVP: " & mvp, x + 10, lineY, 14, ACCENT_COLOR)

proc drawPerformanceStats*(stats: PerformanceStats, x, y: int32, gameTime: float32) =
  ## Draw performance metrics
  drawStatCard(x, y, 300, 230, "PERFORMANCE", gameTime)
  
  var lineY = y + 40
  
  # DPS
  drawMetricRow(x + 10, lineY, "Peak DPS", formatLargeNumber(stats.peakDPS), ACCENT_COLOR)
  lineY += 20
  drawMetricRow(x + 10, lineY, "Average DPS", formatLargeNumber(stats.averageDPS))
  lineY += 30
  
  # Efficiency
  drawMetricRow(x + 10, lineY, "Kills/Min", formatLargeNumber(stats.killsPerMinute))
  lineY += 20
  drawMetricRow(x + 10, lineY, "Damage/Shot", formatLargeNumber(stats.damagePerShot))
  lineY += 30
  
  # Streaks
  drawMetricRow(x + 10, lineY, "Best Streak", $stats.longestKillStreak, Gold)
  lineY += 30
  
  # Wave times
  if stats.waveTimes.len > 0:
    drawMetricRow(x + 10, lineY, "Avg Wave", formatDuration(stats.averageWaveTime))
    lineY += 20
    drawMetricRow(x + 10, lineY, "Fastest", formatDuration(stats.fastestWave), GOOD_COLOR)

proc drawPlayStyleAnalysis*(stats: ComparisonStats, x, y: int32, gameTime: float32) =
  ## Draw play style analysis
  drawStatCard(x, y, 300, 200, "PLAY STYLE", gameTime)
  
  var lineY = y + 50
  
  # Main classification
  let styleColor = case stats.playStyle
    of "Aggressive": Red
    of "Defensive": SkyBlue
    of "Tank": Orange
    of "Mobile": Green
    else: White
  
  let styleSize = 24
  let styleWidth = measureText(stats.playStyle, styleSize.int32)
  drawText(stats.playStyle, x + 150 - styleWidth div 2, lineY, styleSize.int32, styleColor)
  lineY += 50
  
  # Rating bars
  drawText("Aggression", x + 10, lineY, 14, White)
  lineY += 20
  drawProgressBar(x + 10, lineY, 280, 20, stats.aggressionRating, 100.0, Red)
  lineY += 35
  
  drawText("Caution", x + 10, lineY, 14, White)
  lineY += 20
  drawProgressBar(x + 10, lineY, 280, 20, stats.cautionRating, 100.0, SkyBlue)

# ============================================================================
# COMPOSITE SCREENS
# ============================================================================

proc drawRunStatisticsScreen*(stats: RunStatistics, screenWidth, screenHeight: int32, 
                              gameTime: float32, showGraphs: bool = true) =
  ## Draw complete run statistics screen (for Game Over)
  clearBackground(Color(r: 20, g: 20, b: 30, a: 255))
  
  # Title
  drawText("RUN STATISTICS", screenWidth div 2 - 150, 20, 36, ACCENT_COLOR)
  
  # Summary line
  let summaryText = "Wave " & $stats.waveReached & " | " & formatDuration(stats.runDuration) & 
                   " | " & $stats.combat.totalKills & " Kills"
  let summaryWidth = measureText(summaryText, 18)
  drawText(summaryText, screenWidth div 2 - summaryWidth div 2, 65, 18, LightGray)
  
  # Layout: 3 columns
  let colWidth = 310
  let col1X = 30
  let col2X = col1X + colWidth + 20
  let col3X = col2X + colWidth + 20
  
  var currentY = 100
  
  # Column 1
  drawCombatStats(stats.combat, col1X.int32, currentY.int32, gameTime)
  drawResourceStats(stats.resources, col1X.int32, (currentY + 360).int32, gameTime)
  
  # Column 2
  drawMovementStats(stats.movement, col2X.int32, currentY.int32, gameTime)
  drawPlayStyleAnalysis(stats.comparison, col2X.int32, (currentY + 360).int32, gameTime)
  
  # Column 3
  drawPerformanceStats(stats.performance, col3X.int32, currentY.int32, gameTime)
  drawPowerUpStats(stats.powerUps, col3X.int32, (currentY + 250).int32, gameTime)
  
  # Graphs at bottom if enabled
  if showGraphs and screenHeight > 700:
    let graphY = 590
    if stats.performance.dpsHistory.len > 0:
      drawTimelineGraph(col1X.int32, graphY.int32, 300, 140, "DPS Over Time", 
                       stats.performance.dpsHistory, stats.performance.peakDPS * 1.1, GRAPH_LINE_COLOR)
    
    if stats.movement.positionHeatmap.len > 0:
      drawHeatmap(col2X.int32, graphY.int32, 300, 140, stats.movement.positionHeatmap, 
                 1024, 768)  # Assuming screen size, should pass actual
  
  # Footer instructions
  let footerY = screenHeight - 35
  drawText("Press TAB to toggle graphs | ESC to return", 
          screenWidth div 2 - 250, footerY, 16, LightGray)
