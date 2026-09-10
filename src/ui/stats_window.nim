## OS-Themed Statistics Window
## Full-featured stats display with graphs, analytics, and power-up breakdown

import raylib, math, strutils, std/tables, algorithm
import os_window, ../statistics, ../run_statistics, ../types, ../powerup_data, ../localization, ui_constants, ../render_context, ../utils

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
    ## One scroll offset per list in the Power-Ups tab, in pixels:
    ## 0 = timeline, 1 = damage ranking, 2 = healing sources. Indexed so the
    ## wheel handler can clamp all three in a single loop against
    ## powerUpListGeometry / powerUpRowCounts.
    powerUpScroll*: array[3, int]

  ## Geometry of one scrollable list in the Power-Ups tab. Computed by
  ## powerUpListGeometry so the wheel hit-test (update) and the rendering (draw)
  ## can never disagree about where a list actually lives on screen.
  PowerUpListGeom* = object
    panelX*, panelY*, panelW*, panelH*: int
    listY*, listH*: int      # inner viewport, below the pinned column header
    footerY*, footerH*: int  # pinned total row at the panel bottom (0 = none)

const
  PowerUpRowHeight = 18
  PowerUpScrollStep = PowerUpRowHeight * 3  # one wheel notch = three rows
  ## Column offsets inside a ranking panel, measured back from its right edge.
  ## The numeric columns are right-aligned at fixed insets and the name column
  ## takes whatever is left, because the widest power-up name is 164px at 13px
  ## ("PROTOCOLO_SECTOR.exe" in Spanish) and a fixed left-aligned value column
  ## narrow enough to fit three columns would have been overwritten by it.
  RankColInset = 12       # left edge of the "1." rank marker
  NameColInset = 40       # left edge of the name/source column
  PercentColRight = 14    # right edge of the share-of-total percentage
  ValueColRight = 59      # right edge of the damage/healing figure
  ValueColMaxWidth = 46   # widest figure ("999.9K") plus its gutter
  ScrollbarInset = 6      # left edge of the 3px scrollbar track
  LevelTagWidth = 36      # right-hand "Lvl 3" slot in the timeline panel
  ## Height of the "POWER-UP BREAKDOWN" title plus the summary line above the
  ## three panels. Shared by the layout and the draw pass so moving one cannot
  ## silently overlap the other.
  PowerUpHeaderBlockH = 85

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

# POWER-UP TAB DATA + GEOMETRY
# Both the update pass (wheel hit-testing, scroll clamping) and the draw pass
# need the same three lists and the same three rectangles. They are built here
# once per call rather than inlined into the draw proc, so the two passes cannot
# drift apart -- a scrollbar that clamps against a different row count than the
# one being drawn is the classic way these lists end up unreachable at the end.

proc buildDamageRanking*(runStats: RunStatistics): seq[(PowerUpType, float32)] =
  ## Power-ups that dealt damage this run, highest first.
  result = @[]
  for ptype, damage in runStats.powerUps.damageContribution:
    if damage > 0:
      result.add((ptype, damage))
  if result.len > 1:
    result.sort(proc (a, b: (PowerUpType, float32)): int = cmp(b[1], a[1]))

proc buildHealingSources*(runStats: RunStatistics): seq[(string, float32)] =
  ## Every source that restored HP this run, highest first. Power-up healing is
  ## tracked exactly (recordPowerUpHealing); health consumables are reconstructed
  ## from the pickup count times the same formula the pickup itself uses.
  result = @[]
  for ptype, amount in runStats.powerUps.healingContribution:
    if amount > 0:
      result.add((getPowerUpName(ptype), amount))
  let consumableHealing = float32(runStats.resources.healthConsumablesUsed) *
                          (0.75'f32 + 0.025'f32 * runStats.finalMaxHP)
  if consumableHealing > 0:
    result.add((t(tkStatsHealthConsumable), consumableHealing))
  if result.len > 1:
    result.sort(proc (a, b: (string, float32)): int = cmp(b[1], a[1]))

proc powerUpListGeometry*(window: OSWindow): array[3, PowerUpListGeom] =
  ## Three equal columns -- timeline, damage ranking, healing sources -- filling
  ## the tab body below the title/summary header block.
  let contentX = window.x + WINDOW_PADDING
  let contentY = window.y + TITLE_BAR_HEIGHT + 10
  let contentW = window.width - WINDOW_PADDING * 2
  let contentH = window.height - TITLE_BAR_HEIGHT - WINDOW_PADDING
  let tabContentY = contentY + 35 + 10
  let tabContentH = contentH - 35 - 20

  let panelY = tabContentY + PowerUpHeaderBlockH
  let panelH = max(120, tabContentY + tabContentH - 12 - panelY)
  let colW = (contentW - 48) div 3

  for i in 0 .. 2:
    # The two ranking panels pin a column header at the top and a total at the
    # bottom; the timeline scrolls its whole body.
    let headerH = if i == 0: 0 else: 20
    let footerH = if i == 0: 0 else: 22
    let listY = panelY + 36 + headerH
    let listH = max(PowerUpRowHeight, panelH - 36 - headerH - footerH - 8)
    result[i] = PowerUpListGeom(
      panelX: contentX + 12 + i * (colW + 12),
      panelY: panelY,
      panelW: colW,
      panelH: panelH,
      listY: listY,
      listH: listH,
      # Derived from the list bottom, not the panel bottom, so the footer's
      # divider rule can never be drawn over the last visible row.
      footerY: listY + listH + 6,
      footerH: footerH)

proc powerUpRowCounts*(runStats: RunStatistics): array[3, int] =
  ## Row count of each list, used to derive the maximum scroll offset.
  if runStats.isNil:
    return [0, 0, 0]
  [runStats.powerUps.powerUpsChosen.len,
   buildDamageRanking(runStats).len,
   buildHealingSources(runStats).len]

proc rankingColumns*(g: PowerUpListGeom):
    tuple[rankX, nameX, nameMax, valueRight, percentRight, scrollbarX: int] =
  ## Column x-positions shared by the damage and healing ranking panels. Both
  ## panels are the same table shape, so the offsets live here once -- and the
  ## layout can be checked without rendering a frame.
  let valueRight = g.panelX + g.panelW - ValueColRight
  (rankX: g.panelX + RankColInset,
   nameX: g.panelX + NameColInset,
   nameMax: valueRight - ValueColMaxWidth - (g.panelX + NameColInset),
   valueRight: valueRight,
   percentRight: g.panelX + g.panelW - PercentColRight,
   scrollbarX: g.panelX + g.panelW - ScrollbarInset)

proc timelineColumns*(g: PowerUpListGeom):
    tuple[timeX, nameX, nameMax, levelRight, scrollbarX: int] =
  ## Column x-positions for the pick-timeline panel.
  let levelRight = g.panelX + g.panelW - PercentColRight
  (timeX: g.panelX + 10,
   nameX: g.panelX + 48,
   nameMax: levelRight - LevelTagWidth - (g.panelX + 48),
   levelRight: levelRight,
   scrollbarX: g.panelX + g.panelW - ScrollbarInset)

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
    animTime: 0,
    powerUpScroll: [0, 0, 0]
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

  # Power-Up tab list scrolling. The wheel is not a click, so this runs outside
  # the handledClickThisFrame gate -- but it still has to respect stacking order,
  # or scrolling a window buried under another would steal the gesture.
  if not statsWin.window.minimized and statsWin.currentTab == stPowerUps and
     hasLastRunStats():
    let runStats = getLastRunStats()
    let geoms = powerUpListGeometry(statsWin.window)
    let counts = powerUpRowCounts(runStats)
    let wheelPos = getVirtualMousePosition()
    let wheel = getPointerWheelMove()
    let overWindow = isWindowTopmostAtPoint(statsWin.window, wheelPos.x, wheelPos.y,
                                            allWindows)
    for i in 0 .. 2:
      let g = geoms[i]
      let maxScroll = max(0, counts[i] * PowerUpRowHeight - g.listH)
      if wheel != 0 and overWindow:
        # Hit-test the whole panel, not just the clipped viewport, so the wheel
        # still works when the pointer sits over the pinned header or footer.
        let panelRect = Rectangle(x: g.panelX.float32, y: g.panelY.float32,
                                  width: g.panelW.float32, height: g.panelH.float32)
        if checkCollisionPointRec(wheelPos, panelRect):
          statsWin.powerUpScroll[i] =
            statsWin.powerUpScroll[i] - int(wheel * PowerUpScrollStep.float32)
      statsWin.powerUpScroll[i] = clamp(statsWin.powerUpScroll[i], 0, maxScroll)

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

proc fitText*(text: string, maxWidth: int, fontSize: int32 = 13): string =
  ## Text truncated with ".." until it fits maxWidth. Guards the name columns:
  ## a long power-up name (or a wider Spanish translation of a future one) must
  ## never smear across the right-aligned figures next to it. ASCII ".." rather
  ## than a single ellipsis character because the raylib default font stops at
  ## U+00FF and has no ellipsis glyph.
  if maxWidth <= 0:
    return ""
  if measureText(text, fontSize) <= maxWidth.int32:
    return text
  var cut = text.len
  while cut > 0:
    dec cut
    # Never cut inside a multi-byte UTF-8 sequence -- the Spanish tables carry
    # accented characters and half a codepoint renders as garbage.
    while cut > 0 and (text[cut].uint8 and 0xC0'u8) == 0x80'u8:
      dec cut
    let candidate = text[0 ..< cut] & ".."
    if measureText(candidate, fontSize) <= maxWidth.int32:
      return candidate
  result = ""

proc drawListScrollbar*(x, y, height: int, scrollOffset, contentHeight, viewportHeight: int) =
  ## Thin track + proportional thumb along a list's right edge. Nothing is drawn
  ## when everything already fits, so short lists stay visually clean.
  if contentHeight <= viewportHeight or height <= 0:
    return
  let maxScroll = max(1, contentHeight - viewportHeight)
  # Thumb length is the visible fraction, so a long list reads as long instead of
  # hiding how much is still below the fold behind a fixed-size thumb.
  let thumbH = max(20, int(height.float32 * viewportHeight.float32 / contentHeight.float32))
  let travel = max(0, height - thumbH)
  let thumbY = y + int(travel.float32 * (clamp(scrollOffset, 0, maxScroll).float32 / maxScroll.float32))
  drawRectangle(x.int32, y.int32, 3, height.int32, Color(r: 40, g: 40, b: 55, a: 255))
  drawRectangle(x.int32, thumbY.int32, 3, thumbH.int32, Color(r: 0, g: 180, b: 255, a: 220))

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
            3, withAlpha(color, 60))
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

    y += cardHeight + 20

    let col1Width = (contentW - 36) div 3
    let col1X = contentX + 12
    let col2X = col1X + col1Width + 12
    let col3X = col2X + col1Width + 12
    let panelH = 210

    let wm = statsWin.stats.waveMode
    let tm = statsWin.stats.timeMode
    let rl = statsWin.stats.rogueliteMode

    # Wave Mode panel
    drawStatPanel(col1X, y, col1Width, panelH, t(tkStatsWaveModeMetrics))
    var ly = y + 36
    drawStatLine(col1X + 10, ly, "Best Wave",
                (if wm.highestWaveReached > 0: $wm.highestWaveReached else: "--"),
                Color(r: 100, g: 220, b: 255, a: 255))
    ly += 22
    drawStatLine(col1X + 10, ly, t(tkStatsAvgWave),
                (if wm.gamesPlayed > 0: formatFloat(wm.averageWaveReached, ffDecimal, 1) else: "--"))
    ly += 22
    drawStatLine(col1X + 10, ly, "Total Kills",
                formatLargeNumber(wm.totalKills.float32),
                Color(r: 255, g: 200, b: 100, a: 255))
    ly += 22
    drawStatLine(col1X + 10, ly, "Best Kills",
                $wm.bestKills)
    ly += 22
    drawStatLine(col1X + 10, ly, "Bosses Defeated",
                $wm.bossesDefeated,
                Color(r: 255, g: 100, b: 100, a: 255))
    ly += 22
    drawStatLine(col1X + 10, ly, "Runs Played", $wm.gamesPlayed)
    ly += 22
    drawStatLine(col1X + 10, ly, t(tkStatsPlaytime),
                formatTime(wm.totalTimePlayed))

    # Time Survival panel
    drawStatPanel(col2X, y, col1Width, panelH, t(tkStatsTimeSurvivalMetrics))
    ly = y + 36
    drawStatLine(col2X + 10, ly, "Best Survival",
                (if tm.longestSurvivalTime > 0: formatTime(tm.longestSurvivalTime) else: "--"),
                Color(r: 255, g: 165, b: 0, a: 255))
    ly += 22
    drawStatLine(col2X + 10, ly, "Avg Survival",
                (if tm.gamesPlayed > 0: formatTime(tm.averageSurvivalTime) else: "--"))
    ly += 22
    drawStatLine(col2X + 10, ly, "Total Kills",
                formatLargeNumber(tm.totalKills.float32),
                Color(r: 255, g: 200, b: 100, a: 255))
    ly += 22
    drawStatLine(col2X + 10, ly, "Best Kills", $tm.bestKills)
    ly += 22
    drawStatLine(col2X + 10, ly, "Bosses Defeated",
                $tm.bossesDefeated,
                Color(r: 255, g: 100, b: 100, a: 255))
    ly += 22
    drawStatLine(col2X + 10, ly, "Runs Played", $tm.gamesPlayed)
    ly += 22
    drawStatLine(col2X + 10, ly, t(tkStatsPlaytime),
                formatTime(tm.totalTimePlayed))

    # Roguelite panel
    drawStatPanel(col3X, y, col1Width, panelH, t("stats_roguelite_metrics"))
    ly = y + 36
    drawStatLine(col3X + 10, ly, "Best Sector",
                (if rl.highestWaveReached > 0: $rl.highestWaveReached else: "--"),
                Color(r: 0, g: 220, b: 180, a: 255))
    ly += 22
    drawStatLine(col3X + 10, ly, "Avg Sector",
                (if rl.gamesPlayed > 0: formatFloat(rl.averageWaveReached, ffDecimal, 1) else: "--"))
    ly += 22
    drawStatLine(col3X + 10, ly, "Total Kills",
                formatLargeNumber(rl.totalKills.float32),
                Color(r: 255, g: 200, b: 100, a: 255))
    ly += 22
    drawStatLine(col3X + 10, ly, "Best Kills", $rl.bestKills)
    ly += 22
    drawStatLine(col3X + 10, ly, "Bosses Defeated",
                $rl.bossesDefeated,
                Color(r: 255, g: 100, b: 100, a: 255))
    ly += 22
    drawStatLine(col3X + 10, ly, "Runs Played", $rl.gamesPlayed)
    ly += 22
    drawStatLine(col3X + 10, ly, t(tkStatsPlaytime),
                formatTime(rl.totalTimePlayed))

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
      drawStatLine(col2X + 10, lineY, t("stats_successful_parries"), $runStats.movement.successfulParries, Gold)
      lineY += 20
      drawStatLine(col2X + 10, lineY, t("stats_time_invincible"), formatDuration(runStats.movement.timeInvincible), SkyBlue)

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
      # Title + summary fill the top PowerUpHeaderBlockH pixels of the tab body;
      # powerUpListGeometry starts the panels immediately below that.
      var y = tabContentY + 20

      drawText(t(tkStatsPowerUpBreakdown), (contentX + 20).int32, y.int32, 24, Color(r: 255, g: 200, b: 50, a: 255))
      y += 30

      let summaryText = $runStats.powerUps.totalPowerUps & " " & t(tkStatsTotal) & " | " &
                       $runStats.powerUps.legendaryPowerUps & " " & t(tkStatsLegendaryCount) & " | " &
                       $runStats.powerUps.commonPowerUps & " " & t(tkStatsCommonCount)
      drawText(summaryText, (contentX + 20).int32, y.int32, 16, LightGray)

      # Three independently scrollable columns: what was picked, what it dealt,
      # and what it healed. Geometry comes from the same proc the wheel handler
      # uses, so hit-testing and rendering stay in lockstep.
      let geoms = powerUpListGeometry(statsWin.window)
      let headerColor = Color(r: 0, g: 180, b: 255, a: 255)
      let healColor = Color(r: 80, g: 255, b: 160, a: 255)

      # --- Column 1: pick timeline ---------------------------------------
      block timelineColumn:
        let g = geoms[0]
        drawStatPanel(g.panelX, g.panelY, g.panelW, g.panelH, t(tkStatsTimeline))
        let picks = runStats.powerUps.powerUpsChosen
        if picks.len == 0:
          drawText(t(tkStatsNoPowerUpsSelected), (g.panelX + 10).int32, g.listY.int32, 14, Gray)
          break timelineColumn

        let col = timelineColumns(g)
        let contentH = picks.len * PowerUpRowHeight
        let scroll = clamp(statsWin.powerUpScroll[0], 0, max(0, contentH - g.listH))

        beginVirtualScissorMode((g.panelX + 2).int32, g.listY.int32,
                                (g.panelW - 4).int32, g.listH.int32)
        for i, choice in picks:
          let rowY = g.listY + i * PowerUpRowHeight - scroll
          if rowY + PowerUpRowHeight <= g.listY or rowY >= g.listY + g.listH:
            continue
          let powerup = choice[1]
          let rarityColor = if powerup.rarity == prLegendary: Gold else: White
          drawText(formatDuration(choice[0]), col.timeX.int32, rowY.int32, 13, LightGray)
          drawText(fitText(getPowerUpName(powerup.powerType), col.nameMax),
                  col.nameX.int32, rowY.int32, 13, rarityColor)
          let levelText = t(tkStatsLevelPrefix) & $powerup.level
          drawText(levelText, (col.levelRight - measureText(levelText, 13)).int32,
                  rowY.int32, 13, Orange)
        endScissorMode()

        drawListScrollbar(col.scrollbarX, g.listY, g.listH, scroll, contentH, g.listH)

      # --- Column 2: damage contribution ---------------------------------
      block damageColumn:
        let g = geoms[1]
        drawStatPanel(g.panelX, g.panelY, g.panelW, g.panelH, t(tkStatsEffectivenessRanking))
        let ranking = buildDamageRanking(runStats)
        if ranking.len == 0:
          drawText(t(tkStatsNoDamageData), (g.panelX + 10).int32, (g.panelY + 36).int32, 14, Gray)
          break damageColumn

        let col = rankingColumns(g)
        let headerY = g.panelY + 36
        drawText("#", col.rankX.int32, headerY.int32, 12, headerColor)
        drawText(fitText(t(tkStatsPowerUp), col.nameMax, 12), col.nameX.int32, headerY.int32, 12, headerColor)
        let dmgHeader = t(tkStatsDamageColumnLabel)
        drawText(dmgHeader, (col.valueRight - measureText(dmgHeader, 12)).int32,
                headerY.int32, 12, headerColor)

        var totalDamage = 0.0'f32
        for entry in ranking:
          totalDamage += entry[1]

        let contentH = ranking.len * PowerUpRowHeight
        let scroll = clamp(statsWin.powerUpScroll[1], 0, max(0, contentH - g.listH))

        beginVirtualScissorMode((g.panelX + 2).int32, g.listY.int32,
                                (g.panelW - 4).int32, g.listH.int32)
        for i, entry in ranking:
          let rowY = g.listY + i * PowerUpRowHeight - scroll
          if rowY + PowerUpRowHeight <= g.listY or rowY >= g.listY + g.listH:
            continue
          let rank = i + 1
          let percent = if totalDamage > 0: (entry[1] / totalDamage) * 100.0 else: 0.0
          let medalColor = case rank
            of 1: Gold
            of 2: Color(r: 192, g: 192, b: 192, a: 255)
            of 3: Color(r: 205, g: 127, b: 50, a: 255)
            else: White

          drawText($rank & ".", col.rankX.int32, rowY.int32, 13, medalColor)
          drawText(fitText(getPowerUpName(entry[0]), col.nameMax), col.nameX.int32, rowY.int32, 13, White)
          # Damage is stored in internal units; BALANCE_MULTIPLIER scales it to
          # the same numbers the floating damage text shows in-game.
          let valueText = formatLargeNumber(entry[1] * BALANCE_MULTIPLIER)
          drawText(valueText, (col.valueRight - measureText(valueText, 13)).int32,
                  rowY.int32, 13, headerColor)
          let percentText = formatPercent(percent)
          drawText(percentText, (col.percentRight - measureText(percentText, 13)).int32,
                  rowY.int32, 13, getQualityColor(percent, 10.0))
        endScissorMode()

        drawListScrollbar(col.scrollbarX, g.listY, g.listH, scroll, contentH, g.listH)

        drawRectangle((g.panelX + 8).int32, (g.footerY - 5).int32,
                     (g.panelW - 16).int32, 1, Color(r: 70, g: 70, b: 90, a: 255))
        drawText(t(tkStatsTotal), col.rankX.int32, (g.footerY + 3).int32, 13, LightGray)
        let damageTotalText = formatLargeNumber(totalDamage * BALANCE_MULTIPLIER)
        drawText(damageTotalText, (col.percentRight - measureText(damageTotalText, 13)).int32,
                (g.footerY + 3).int32, 13, headerColor)

      # --- Column 3: healing sources -------------------------------------
      block healingColumn:
        let g = geoms[2]
        drawStatPanel(g.panelX, g.panelY, g.panelW, g.panelH, t(tkStatsHealingRanking))
        let healList = buildHealingSources(runStats)
        if healList.len == 0:
          drawText(t(tkStatsNoHealingData), (g.panelX + 10).int32, (g.panelY + 36).int32, 14, Gray)
          break healingColumn

        let col = rankingColumns(g)
        let headerY = g.panelY + 36
        drawText("#", col.rankX.int32, headerY.int32, 12, healColor)
        drawText(fitText(t(tkStatsSourceColumnLabel), col.nameMax, 12), col.nameX.int32, headerY.int32, 12, healColor)
        let healHeader = t(tkStatsHealingColumnLabel)
        drawText(healHeader, (col.valueRight - measureText(healHeader, 12)).int32,
                headerY.int32, 12, healColor)

        var totalHealing = 0.0'f32
        for entry in healList:
          totalHealing += entry[1]

        let contentH = healList.len * PowerUpRowHeight
        let scroll = clamp(statsWin.powerUpScroll[2], 0, max(0, contentH - g.listH))

        beginVirtualScissorMode((g.panelX + 2).int32, g.listY.int32,
                                (g.panelW - 4).int32, g.listH.int32)
        for i, entry in healList:
          let rowY = g.listY + i * PowerUpRowHeight - scroll
          if rowY + PowerUpRowHeight <= g.listY or rowY >= g.listY + g.listH:
            continue
          let rank = i + 1
          let percent = if totalHealing > 0: (entry[1] / totalHealing) * 100.0 else: 0.0
          let medalColor = case rank
            of 1: Gold
            of 2: Color(r: 192, g: 192, b: 192, a: 255)
            of 3: Color(r: 205, g: 127, b: 50, a: 255)
            else: White

          drawText($rank & ".", col.rankX.int32, rowY.int32, 13, medalColor)
          drawText(fitText(entry[0], col.nameMax), col.nameX.int32, rowY.int32, 13, White)
          let valueText = formatLargeNumber(entry[1] * BALANCE_MULTIPLIER)
          drawText(valueText, (col.valueRight - measureText(valueText, 13)).int32,
                  rowY.int32, 13, healColor)
          let percentText = formatPercent(percent)
          drawText(percentText, (col.percentRight - measureText(percentText, 13)).int32,
                  rowY.int32, 13, getQualityColor(percent, 10.0))
        endScissorMode()

        drawListScrollbar(col.scrollbarX, g.listY, g.listH, scroll, contentH, g.listH)

        drawRectangle((g.panelX + 8).int32, (g.footerY - 5).int32,
                     (g.panelW - 16).int32, 1, Color(r: 70, g: 70, b: 90, a: 255))
        drawText(t(tkStatsTotalHealed), col.rankX.int32, (g.footerY + 3).int32, 13, LightGray)
        let healTotalText = formatLargeNumber(totalHealing * BALANCE_MULTIPLIER)
        drawText(healTotalText, (col.percentRight - measureText(healTotalText, 13)).int32,
                (g.footerY + 3).int32, 13, healColor)
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
