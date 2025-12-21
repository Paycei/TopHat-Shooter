# ============================================================================
# RUN STATISTICS UI
# Visual rendering of per-run statistics with graphs and comparisons
# Displays on Game Over screen and Main Menu
# ============================================================================

import raylib, run_statistics, types, strutils, math, std/tables, powerup

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
  
  # Ensure maxValue is non-zero to avoid division by zero
  let safeMaxValue = max(maxValue, 0.01)
  
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
    let y1Norm = 1.0 - (dataPoints[i][1] / safeMaxValue)
    let x2Norm = (dataPoints[i+1][0] - minTime) / timeRange
    let y2Norm = 1.0 - (dataPoints[i+1][1] / safeMaxValue)
    
    let x1Px = graphX.float32 + x1Norm * graphWidth.float32
    let y1Px = graphY.float32 + y1Norm * graphHeight.float32
    let x2Px = graphX.float32 + x2Norm * graphWidth.float32
    let y2Px = graphY.float32 + y2Norm * graphHeight.float32
    
    drawLine(Vector2(x: x1Px, y: y1Px),
            Vector2(x: x2Px, y: y2Px),
            2, color)
  
  # Y-axis labels
  drawText("0", x + 5, graphY + graphHeight - 10, 10, LightGray)
  drawText(formatLargeNumber(safeMaxValue), x + 5, graphY, 10, LightGray)

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
  drawStatCard(x, y, 300, 310, "RESOURCES", gameTime)
  
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
  drawMetricRow(x + 10, lineY, "Walls Damaged", $stats.wallsDamaged, Orange)
  lineY += 20
  drawMetricRow(x + 10, lineY, "Walls Destroyed", $stats.wallsDestroyed, Red)
  lineY += 20
  drawMetricRow(x + 10, lineY, "Damage Blocked", formatLargeNumber(stats.wallDamageBlocked), GOOD_COLOR)
  lineY += 20
  
  # Consumables
  drawMetricRow(x + 10, lineY, "Consumables", $stats.consumablesCollected)
  lineY += 18
  
  # Show breakdown by type if available
  if stats.consumablesByType.len > 0:
    for consumType, count in stats.consumablesByType:
      let consumName = case consumType
        of ctHealth: "HP"
        of ctCoin: "Coins"
        of ctSpeed: "Speed"
        of ctInvincibility: "Invuln"
        of ctFireRate: "Fire"
        of ctMagnet: "Magnet"
      let consumColor = case consumType
        of ctHealth: Green
        of ctCoin: Gold
        of ctSpeed: SkyBlue
        of ctInvincibility: Magenta
        of ctFireRate: Orange
        of ctMagnet: Purple
      drawText(consumName, x + 20, lineY, 14, LightGray)
      let countStr = $count
      let countWidth = measureText(countStr, 14)
      drawText(countStr, x + 250 - countWidth, lineY, 14, consumColor)
      lineY += 16

proc drawPowerUpStats*(stats: PowerUpStats, x, y: int32, gameTime: float32) =
  ## Draw power-up statistics
  drawStatCard(x, y, 300, 150, "POWER-UPS", gameTime)
  
  var lineY = y + 40
  
  drawMetricRow(x + 10, lineY, "Total Chosen", $stats.totalPowerUps)
  lineY += 20
  drawMetricRow(x + 10, lineY, "Common", $stats.commonPowerUps, White)
  lineY += 20
  drawMetricRow(x + 10, lineY, "Legendary", $stats.legendaryPowerUps, Gold)
  
  # Most effective power-up
  if stats.damageContribution.len > 0:
    lineY += 25
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

proc drawDetailedPowerUpScreen*(stats: PowerUpStats, combat: CombatStats, 
                                screenWidth, screenHeight: int32, gameTime: float32) =
  ## Draw detailed power-up breakdown with per-powerup statistics
  clearBackground(Color(r: 20, g: 20, b: 30, a: 255))
  
  # Title - moved lower for better spacing
  drawText("POWER-UP BREAKDOWN", screenWidth div 2 - 200, 70, 36, ACCENT_COLOR)
  
  # Summary stats - moved lower
  let summaryText = $stats.totalPowerUps & " Total | " & 
                   $stats.legendaryPowerUps & " Legendary | " &
                   $stats.commonPowerUps & " Common"
  let summaryWidth = measureText(summaryText, 18)
  drawText(summaryText, screenWidth div 2 - summaryWidth div 2, 115, 18, LightGray)
  
  var currentY: int32 = 160
  
  # Power-up timeline (left side, narrower)
  drawStatCard(30, currentY, 500, 320, "POWER-UP TIMELINE", gameTime)
  var timelineY = currentY + 40
  
  if stats.powerUpsChosen.len > 0:
    for i, choice in stats.powerUpsChosen:
      let timestamp = formatDuration(choice[0])
      let powerup = choice[1]
      let powerupName = getPowerUpName(powerup.powerType)
      
      # Determine rarity color
      let rarityColor = if powerup.rarity == prLegendary: 
        Gold 
      else:
        case powerup.level
        of 1: White
        of 2: Color(r: 150, g: 200, b: 255, a: 255)
        of 3: Color(r: 200, g: 150, b: 255, a: 255)
        else: White
      
      # Draw power-up entry
      drawText(timestamp, 40, timelineY, 14, LightGray)
      drawText(powerupName, 120, timelineY, 14, rarityColor)
      drawText("Lvl " & $powerup.level, 300, timelineY, 14, Orange)
      
      # Show contribution if available
      if stats.damageContribution.hasKey(powerup.powerType):
        let damage = stats.damageContribution[powerup.powerType]
        let dmgStr = formatLargeNumber(damage)
        drawText(dmgStr & " dmg", 370, timelineY, 14, ACCENT_COLOR)
      
      if stats.killContribution.hasKey(powerup.powerType):
        let kills = stats.killContribution[powerup.powerType]
        drawText($kills & " kills", 460, timelineY, 14, Gold)
      
      timelineY += 18
      
      # Scroll warning if too many
      if timelineY > currentY + 300:
        drawText("... (" & $(stats.powerUpsChosen.len - i - 1) & " more)", 
                40, timelineY, 14, Color(r: 150, g: 150, b: 150, a: 255))
        break
  else:
    drawText("No power-ups selected", 40, timelineY, 16, LightGray)
  
  # Power-up effectiveness ranking (right side, adjusted position and width to fit screen)
  drawStatCard(540, currentY, 470, 320, "EFFECTIVENESS RANKING", gameTime)
  var rankY = currentY + 40
  
  # Sort by damage contribution
  var contributions: seq[(PowerUpType, float32)] = @[]
  for ptype, damage in stats.damageContribution:
    contributions.add((ptype, damage))
  
  # Simple bubble sort by damage (descending)
  for i in 0..<contributions.len:
    for j in 0..<contributions.len - i - 1:
      if contributions[j][1] < contributions[j + 1][1]:
        let temp = contributions[j]
        contributions[j] = contributions[j + 1]
        contributions[j + 1] = temp
  
  if contributions.len > 0:
    drawText("RANK", 550, rankY, 14, ACCENT_COLOR)
    drawText("POWER-UP", 600, rankY, 14, ACCENT_COLOR)
    drawText("DAMAGE", 770, rankY, 14, ACCENT_COLOR)
    drawText("% OF TOTAL", 890, rankY, 14, ACCENT_COLOR)
    rankY += 25
    
    let totalDamage = combat.totalDamageDealt
    
    for i, contrib in contributions:
      let rank = i + 1
      let ptype = contrib[0]
      let damage = contrib[1]
      let percent = if totalDamage > 0: (damage / totalDamage) * 100.0 else: 0.0
      
      # Medal for top 3
      let medalColor = case rank
        of 1: Gold
        of 2: Color(r: 192, g: 192, b: 192, a: 255)  # Silver
        of 3: Color(r: 205, g: 127, b: 50, a: 255)   # Bronze
        else: White
      
      drawText($rank & ".", 555, rankY, 14, medalColor)
      drawText(getPowerUpName(ptype), 600, rankY, 14, White)
      drawText(formatLargeNumber(damage), 770, rankY, 14, ACCENT_COLOR)
      drawText(formatPercent(percent), 890, rankY, 14, getQualityColor(percent, 10.0))
      
      # Draw progress bar for visual comparison (adjusted position and width)
      let barWidth = int32((damage / contributions[0][1]) * 150.0)
      drawRectangle(710, rankY + 2, barWidth, 10, 
                   Color(r: 100, g: 200, b: 255, a: 200))
      
      rankY += 22
      
      if rankY > currentY + 300:
        break
  else:
    drawText("No damage contribution data available", 550, rankY, 16, LightGray)
  
  # Summary cards at bottom (adjusted to fit on screen)
  currentY += 340
  
  # Synergy analysis
  drawStatCard(30, currentY, 350, 180, "SYNERGY ANALYSIS", gameTime)
  var synergyY = currentY + 40
  
  let synergyColor = getQualityColor(stats.synergyScore, 50.0)
  drawMetricRow(40, synergyY, "Synergy Score", 
               formatLargeNumber(stats.synergyScore), synergyColor)
  synergyY += 25
  
  drawMetricRow(40, synergyY, "Has Synergy", 
               if stats.hasSynergy: "Yes" else: "No",
               if stats.hasSynergy: GOOD_COLOR else: BAD_COLOR)
  synergyY += 25
  
  if stats.elementalCombo.len > 0:
    drawText("Active Elements:", 40, synergyY, 14, White)
    synergyY += 20
    for elem in stats.elementalCombo:
      drawText("  • " & $elem, 50, synergyY, 14, ACCENT_COLOR)
      synergyY += 18
  
  # Level distribution (adjusted width to fit screen)
  drawStatCard(400, currentY, 300, 180, "LEVEL DISTRIBUTION", gameTime)
  var levelY = currentY + 40
  
  let maxLevelCount = max(max(stats.level1PowerUps, stats.level2PowerUps), stats.level3PowerUps)
  
  drawText("Level 1", 410, levelY, 14, White)
  drawProgressBar(490, levelY, 170, 20, stats.level1PowerUps.float32, 
                 maxLevelCount.float32, White)
  drawText($stats.level1PowerUps, 670, levelY, 14, White)
  levelY += 30
  
  drawText("Level 2", 410, levelY, 14, White)
  drawProgressBar(490, levelY, 170, 20, stats.level2PowerUps.float32, 
                 maxLevelCount.float32, Color(r: 150, g: 200, b: 255, a: 255))
  drawText($stats.level2PowerUps, 670, levelY, 14, White)
  levelY += 30
  
  drawText("Level 3", 410, levelY, 14, White)
  drawProgressBar(490, levelY, 170, 20, stats.level3PowerUps.float32, 
                 maxLevelCount.float32, Color(r: 200, g: 150, b: 255, a: 255))
  drawText($stats.level3PowerUps, 670, levelY, 14, White)
  
  # MVP section (adjusted position and width to fit screen)
  drawStatCard(710, currentY, 300, 180, "MOST VALUABLE POWER-UP", gameTime)
  var mvpY = currentY + 50
  
  let mvpName = getPowerUpName(stats.mostEffectivePowerUp)
  let mvpSize: int32 = 20
  let mvpWidth = measureText(mvpName, mvpSize)
  drawText(mvpName, 860 - mvpWidth div 2, mvpY, mvpSize, Gold)
  mvpY += 40
  
  if stats.damageContribution.hasKey(stats.mostEffectivePowerUp):
    let mvpDamage = stats.damageContribution[stats.mostEffectivePowerUp]
    let dmgStr = formatLargeNumber(mvpDamage) & " damage"
    let dmgWidth = measureText(dmgStr, 16)
    drawText(dmgStr, 860 - dmgWidth div 2, mvpY, 16, ACCENT_COLOR)
    mvpY += 25
  
  if stats.killContribution.hasKey(stats.mostEffectivePowerUp):
    let mvpKills = stats.killContribution[stats.mostEffectivePowerUp]
    let killStr = $mvpKills & " kills"
    let killWidth = measureText(killStr, 16)
    drawText(killStr, 860 - killWidth div 2, mvpY, 16, Gold)

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
  
  # Layout: 3 columns with adjusted spacing
  let colWidth = 310
  let col1X = 20
  let col2X = col1X + colWidth + 15
  let col3X = col2X + colWidth + 15
  
  var currentY = 100
  
  # Column 1
  drawCombatStats(stats.combat, col1X.int32, currentY.int32, gameTime)
  
  # Column 2
  drawMovementStats(stats.movement, col2X.int32, currentY.int32, gameTime)
  
  # Column 3
  drawResourceStats(stats.resources, col3X.int32, currentY.int32, gameTime)
  
  # Second row - adjusted Y position to avoid overlap, removed power-ups section
  let row2Y = currentY + 360
  drawPerformanceStats(stats.performance, col1X.int32, row2Y.int32, gameTime)
  drawPlayStyleAnalysis(stats.comparison, col2X.int32, row2Y.int32, gameTime)
  
  # Graphs section (replacing power-ups section)
  if showGraphs:
    if stats.performance.dpsHistory.len > 0:
      # DPS over time graph
      let maxDPS = max(stats.performance.peakDPS, 1.0)  # Ensure non-zero
      drawTimelineGraph(col3X.int32, row2Y.int32, 310, 200, "DPS OVER TIME", 
                       stats.performance.dpsHistory, maxDPS, 
                       Color(r: 255, g: 150, b: 50, a: 255))
    else:
      # No graph data available
      drawStatCard(col3X.int32, row2Y.int32, 310, 200, "DPS OVER TIME", gameTime)
      drawText("No graph data recorded", col3X.int32 + 50, row2Y.int32 + 90, 14, LightGray)
  
  # Footer instructions - positioned at actual bottom
  let footerY = screenHeight - 30
  drawText("Press TAB or ESC to return to Game Over", 
          screenWidth div 2 - 200, footerY, 16, LightGray)
