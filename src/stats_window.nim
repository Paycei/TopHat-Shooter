## OS-Themed Statistics Window
## Wraps existing statistics display in OS window

import raylib, os_window, statistics, run_statistics, run_statistics_ui, types, math, powerup

type
  StatsTab* = enum
    stLifetime
    stLastRun
    stPowerUps
  
  StatsWindow* = ref object
    window*: OSWindow
    currentTab*: StatsTab
    stats*: Statistics
    animTime*: float32  # For animations

proc newStatsWindow*(screenWidth, screenHeight: int, stats: Statistics): StatsWindow =
  let windowWidth = 1000
  let windowHeight = 700
  let windowX = (screenWidth - windowWidth) div 2
  let windowY = (screenHeight - windowHeight) div 2
  
  let osWin = newOSWindow(
    "System Monitor - Player Analytics",
    windowX, windowY,
    windowWidth, windowHeight,
    Color(r: 255, g: 200, b: 50, a: 255),  # Yellow/Gold
    owtStatistics
  )
  
  result = StatsWindow(
    window: osWin,
    currentTab: stLifetime,
    stats: stats,
    animTime: 0
  )

proc updateStatsWindow*(statsWin: StatsWindow, dt: float32, screenWidth, screenHeight: int): bool =
  ## Returns true if window should close
  updateOSWindow(statsWin.window, dt)
  statsWin.animTime += dt
  
  if not statsWin.window.visible:
    return false
  
  # Check if window should close
  let shouldClose = handleOSWindowInput(statsWin.window, screenWidth, screenHeight)
  if shouldClose:
    statsWin.window.visible = false
    return true
  
  # Tab switching with number keys (only when not minimized)
  if not statsWin.window.minimized:
    if isKeyPressed(One): statsWin.currentTab = stLifetime
    if isKeyPressed(Two): statsWin.currentTab = stLastRun
    if isKeyPressed(Three): statsWin.currentTab = stPowerUps
  
  # Tab switching with mouse (only when not minimized)
  if not statsWin.window.minimized and isMouseButtonPressed(Left):
    let mousePos = getMousePosition()
    let tabY = statsWin.window.y + TITLE_BAR_HEIGHT + 10
    let tabHeight = 35
    let tabWidth = 140
    let contentX = statsWin.window.x + WINDOW_PADDING
    var tabX = contentX
    
    for tab in [stLifetime, stLastRun, stPowerUps]:
      if mousePos.x >= tabX.float32 and mousePos.x <= (tabX + tabWidth).float32 and
         mousePos.y >= tabY.float32 and mousePos.y <= (tabY + tabHeight).float32:
        statsWin.currentTab = tab
        break
      tabX += tabWidth + 10
  
  return false

# Visual helper procedures for system monitor aesthetics
proc drawSystemBar*(x, y, width, height: int, value: float32, label: string, 
                   maxValue: float32, color: Color, animTime: float32) =
  ## Draw a system monitor-style usage bar
  let ratio = min(1.0, value / maxValue)
  
  # Background
  drawRectangle(x.int32, y.int32, width.int32, height.int32,
               Color(r: 20, g: 20, b: 30, a: 255))
  
  # Animated fill with gradient
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
  
  # Border
  drawRectangleLines(Rectangle(x: x.float32, y: y.float32,
                                width: width.float32, height: height.float32),
                    1, Color(r: 80, g: 80, b: 100, a: 255))
  
  # Label on left
  drawText(label, (x + 5).int32, (y + (height - 14) div 2).int32, 14, White)
  
  # Value on right
  let valueText = $int(value) & " / " & $int(maxValue)
  let textWidth = measureText(valueText, 14)
  drawText(valueText, (x + width - textWidth - 5).int32, 
          (y + (height - 14) div 2).int32, 14, color)
  
  # Percentage indicator
  let percentText = $int(ratio * 100) & "%"
  let percentWidth = measureText(percentText, 12)
  drawText(percentText, (x + width div 2 - percentWidth div 2).int32,
          (y + height + 3).int32, 12, LightGray)

proc drawMetricCard*(x, y, width, height: int, title: string, value: string, 
                    icon: char, color: Color) =
  ## Draw a metric card with icon
  # Card background
  drawRectangle(x.int32, y.int32, width.int32, height.int32,
               Color(r: 25, g: 25, b: 35, a: 255))
  drawRectangleLines(Rectangle(x: x.float32, y: y.float32,
                                width: width.float32, height: height.float32),
                    1, color)
  
  # Icon circle
  let iconX = x + 15
  let iconY = y + height div 2
  drawCircle(Vector2(x: iconX.float32, y: iconY.float32), 12, color)
  drawText($icon, (iconX - 6).int32, (iconY - 10).int32, 20, Black)
  
  # Title
  drawText(title, (x + 40).int32, (y + 10).int32, 14, LightGray)
  
  # Value
  drawText(value, (x + 40).int32, (y + 30).int32, 20, White)

proc drawMiniGraph*(x, y, width, height: int, data: seq[float32], color: Color) =
  ## Draw a mini line graph
  if data.len < 2:
    return
  
  # Background
  drawRectangle(x.int32, y.int32, width.int32, height.int32,
               Color(r: 15, g: 15, b: 25, a: 255))
  
  # Find max value for scaling
  var maxVal = 0.01f
  for val in data:
    if val > maxVal:
      maxVal = val
  
  # Draw lines
  let stepX = width.float32 / float32(data.len - 1)
  for i in 0..<data.len - 1:
    let x1 = x.float32 + i.float32 * stepX
    let y1 = y.float32 + height.float32 - (data[i] / maxVal * height.float32)
    let x2 = x.float32 + (i + 1).float32 * stepX
    let y2 = y.float32 + height.float32 - (data[i + 1] / maxVal * height.float32)
    
    drawLine(Vector2(x: x1, y: y1), Vector2(x: x2, y: y2), 2, color)
  
  # Border
  drawRectangleLines(Rectangle(x: x.float32, y: y.float32,
                                width: width.float32, height: height.float32),
                    1, Color(r: 60, g: 60, b: 80, a: 255))

proc drawStatsWindow*(statsWin: StatsWindow, game: Game) =
  if not statsWin.window.visible:
    return
  
  # Draw window chrome
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
  let mousePos = getMousePosition()
  
  var tabX = contentX
  for tab in [stLifetime, stLastRun, stPowerUps]:
    let tabName = case tab
      of stLifetime: "Lifetime"
      of stLastRun: "Last Run"
      of stPowerUps: "Power-Ups"
    
    let isActive = statsWin.currentTab == tab
    let isHovered = mousePos.x >= tabX.float32 and 
                   mousePos.x <= (tabX + tabWidth).float32 and
                   mousePos.y >= tabY.float32 and 
                   mousePos.y <= (tabY + tabHeight).float32
    
    # Draw tab
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
  
  # Draw content background
  drawRectangle(contentX.int32, tabContentY.int32, contentW.int32, tabContentH.int32,
               Color(r: 15, g: 15, b: 25, a: 255))
  
  # Render appropriate tab content
  # We'll use the existing statistics rendering with adjusted coordinates
  let hasLastRun = hasLastRunStats()
  
  case statsWin.currentTab
  of stLifetime:
    # System Monitor style display
    var y = tabContentY + 20
    
    # Header
    drawText("═══ SYSTEM PERFORMANCE MONITOR ═══", (contentX + 20).int32, y.int32, 
            20, Color(r: 0, g: 200, b: 255, a: 255))
    y += 35
    
    # Metric cards row
    let cardWidth = (contentW - 80) div 3
    let cardHeight = 70
    
    drawMetricCard(contentX + 20, y, cardWidth, cardHeight,
                  "TOTAL SESSIONS", $statsWin.stats.totalGamesPlayed,
                  '#', Gold)
    
    drawMetricCard(contentX + 40 + cardWidth, y, cardWidth, cardHeight,
                  "PLAYTIME", formatTime(statsWin.stats.totalPlayTime),
                  '@', Color(r: 100, g: 200, b: 255, a: 255))
    
    let totalKills = statsWin.stats.waveMode.bestKills + statsWin.stats.timeMode.bestKills
    drawMetricCard(contentX + 60 + cardWidth * 2, y, cardWidth, cardHeight,
                  "PEAK KILLS", $totalKills,
                  '*', Red)
    
    y += cardHeight + 25
    
    # Wave Mode section
    drawText("WAVE MODE METRICS", (contentX + 20).int32, y.int32, 18,
            Color(r: 100, g: 200, b: 255, a: 255))
    y += 25
    
    # System-style bars
    let barWidth = contentW - 80
    let barHeight = 24
    
    drawSystemBar(contentX + 30, y, barWidth, barHeight,
                 statsWin.stats.waveMode.highestWaveReached.float32, 
                 "[WAVE] Max Reached", 50.0,
                 Color(r: 100, g: 220, b: 255, a: 255), statsWin.animTime)
    y += barHeight + 18
    
    drawSystemBar(contentX + 30, y, barWidth, barHeight,
                 statsWin.stats.waveMode.bestKills.float32,
                 "[KILL] Best Performance", 500.0,
                 Color(r: 255, g: 200, b: 100, a: 255), statsWin.animTime)
    y += barHeight + 18
    
    drawSystemBar(contentX + 30, y, barWidth, barHeight,
                 statsWin.stats.waveMode.bossesDefeated.float32,
                 "[BOSS] Eliminated", 20.0,
                 Color(r: 255, g: 100, b: 100, a: 255), statsWin.animTime)
    y += barHeight + 30
    
    # Time Survival section
    drawText("TIME SURVIVAL METRICS", (contentX + 20).int32, y.int32, 18,
            Color(r: 255, g: 150, b: 100, a: 255))
    y += 25
    
    let survivalMins = statsWin.stats.timeMode.longestSurvivalTime.float32 / 60.0
    drawSystemBar(contentX + 30, y, barWidth, barHeight,
                 survivalMins, "[TIME] Longest Survival", 10.0,
                 Color(r: 255, g: 165, b: 0, a: 255), statsWin.animTime)
    y += barHeight + 18
    
    drawSystemBar(contentX + 30, y, barWidth, barHeight,
                 statsWin.stats.timeMode.bestKills.float32,
                 "[KILL] Best Performance", 500.0,
                 Color(r: 255, g: 200, b: 100, a: 255), statsWin.animTime)
    y += barHeight + 18
    
    drawSystemBar(contentX + 30, y, barWidth, barHeight,
                 statsWin.stats.timeMode.bossesDefeated.float32,
                 "[BOSS] Eliminated", 20.0,
                 Color(r: 255, g: 100, b: 100, a: 255), statsWin.animTime)
  
  of stLastRun:
    if hasLastRun:
      let runStats = getLastRunStats()
      var y = tabContentY + 20
      
      # Header
      drawText("═══ LAST SESSION REPORT ═══", (contentX + 20).int32, y.int32, 
              20, Color(r: 255, g: 200, b: 50, a: 255))
      y += 35
      
      # Key metrics cards
      let cardWidth = (contentW - 80) div 4
      let cardHeight = 65
      
      drawMetricCard(contentX + 20, y, cardWidth, cardHeight,
                    "WAVE", $runStats.waveReached, 'W',
                    Color(r: 100, g: 200, b: 255, a: 255))
      
      drawMetricCard(contentX + 30 + cardWidth, y, cardWidth, cardHeight,
                    "TIME", formatTime(runStats.runDuration), 'T',
                    Color(r: 255, g: 165, b: 0, a: 255))
      
      drawMetricCard(contentX + 40 + cardWidth * 2, y, cardWidth, cardHeight,
                    "KILLS", $runStats.combat.totalKills, 'K',
                    Color(r: 255, g: 100, b: 100, a: 255))
      
      drawMetricCard(contentX + 50 + cardWidth * 3, y, cardWidth, cardHeight,
                    "ACCURACY", formatPercent(runStats.combat.accuracyPercent), 'A',
                    Gold)
      
      y += cardHeight + 30
      
      # Combat stats
      drawText("COMBAT ANALYTICS", (contentX + 20).int32, y.int32, 18,
              Color(r: 255, g: 200, b: 50, a: 255))
      y += 25
      
      let barWidth = contentW - 80
      let barHeight = 22
      
      # Shots fired bar
      drawSystemBar(contentX + 30, y, barWidth, barHeight,
                   runStats.combat.shotsFired.float32,
                   "[FIRE] Shots Fired", 
                   max(runStats.combat.shotsFired.float32, 1000.0),
                   Color(r: 255, g: 200, b: 100, a: 255), statsWin.animTime)
      y += barHeight + 16
      
      # Shots hit bar
      drawSystemBar(contentX + 30, y, barWidth, barHeight,
                   runStats.combat.shotsHit.float32,
                   "[HIT] Shots Connected",
                   max(runStats.combat.shotsHit.float32, 500.0),
                   Color(r: 100, g: 255, b: 100, a: 255), statsWin.animTime)
      y += barHeight + 16
      
      # Damage dealt
      drawSystemBar(contentX + 30, y, barWidth, barHeight,
                   runStats.combat.totalDamageDealt,
                   "[DMG] Total Damage",
                   max(runStats.combat.totalDamageDealt, 5000.0),
                   Color(r: 255, g: 100, b: 100, a: 255), statsWin.animTime)
      y += barHeight + 25
      
      # Additional stats in two columns
      let colX2 = contentX + contentW div 2 + 20
      var y2 = y
      
      drawText("PERFORMANCE", (contentX + 20).int32, y.int32, 16, LightGray)
      drawText("Critical Hits: " & $runStats.combat.criticalHits, 
              (contentX + 30).int32, (y + 20).int32, 14, Orange)
      drawText("Elite Kills: " & $runStats.combat.eliteKills,
              (contentX + 30).int32, (y + 38).int32, 14, Gold)
      drawText("Boss Kills: " & $runStats.combat.bossKills,
              (contentX + 30).int32, (y + 56).int32, 14, Red)
      
      drawText("SURVIVAL", colX2.int32, y2.int32, 16, LightGray)
      drawText("Damage Taken: " & $int(runStats.combat.totalDamageTaken),
              (colX2 + 10).int32, (y2 + 20).int32, 14, Red)
      drawText("Near Deaths: " & $runStats.movement.nearDeathCount,
              (colX2 + 10).int32, (y2 + 38).int32, 14, Orange)
      drawText("Coins Earned: " & $runStats.resources.coinsEarned,
              (colX2 + 10).int32, (y2 + 56).int32, 14, Gold)
    else:
      let y = tabContentY + tabContentH div 2 - 30
      drawText("No previous run statistics available", 
              (contentX + contentW div 2 - 180).int32, y.int32, 18, LightGray)
      drawText("Complete a game to see detailed run statistics", 
              (contentX + contentW div 2 - 200).int32, (y + 25).int32, 16, Gray)
  
  of stPowerUps:
    if hasLastRun:
      let runStats = getLastRunStats()
      # Draw simplified power-up list
      var y = tabContentY + 20
      drawText("Power-Ups Selected", (contentX + 20).int32, y.int32, 24, Color(r: 255, g: 200, b: 50, a: 255))
      y += 35
      
      if runStats.powerUps.powerUpsChosen.len > 0:
        for i, choice in runStats.powerUps.powerUpsChosen:
          if i > 15: break  # Limit display
          let timestamp = formatDuration(choice[0])
          let powerup = choice[1]
          let powerupName = getPowerUpName(powerup.powerType)
          
          let rarityColor = if powerup.rarity == prLegendary: Gold else: White
          
          drawText(timestamp, (contentX + 30).int32, y.int32, 14, LightGray)
          drawText(powerupName, (contentX + 120).int32, y.int32, 14, rarityColor)
          drawText("Lvl " & $powerup.level, (contentX + 320).int32, y.int32, 14, Orange)
          y += 20
      else:
        drawText("No power-ups selected", (contentX + 30).int32, y.int32, 16, LightGray)
    else:
      let y = tabContentY + tabContentH div 2 - 20
      drawText("No power-up data available", 
              (contentX + contentW div 2 - 150).int32, y.int32, 18, LightGray)
  
  # Draw resize indicator
  drawResizeIndicator(statsWin.window)
