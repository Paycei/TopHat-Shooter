## Combined OS-Style HUD Panel
## Merges status and info panels into one compact, non-intrusive display

import raylib, rlgl, math
import ../types, ../localization, ../powerup_data, ../roguelite, ../dungeon, ui_constants, ../render_context, icon_drawing, ../utils, ui_helpers

const
  COMBINED_PANEL_WIDTH = 238
  BORDER_PANEL_WIDTH = 171   # widescreen left-gutter width = (1366-1024)/2
  COMBINED_PANEL_PADDING = 6
  COMBINED_SECTION_SPACING = 6
  COMBINED_ITEM_HEIGHT = 24
  COMBINED_TITLE_HEIGHT = 18
  COMBINED_MAX_POWERUPS_VISIBLE = 3
  COMBINED_POWERUP_OVERFLOW_HEIGHT = 14
  HEADER_BG_COLOR = Color(r: 0, g: 100, b: 120, a: 60)
  ACCENT_COLOR = Color(r: 0, g: 220, b: 255, a: 255)

# State for panel minimization and dragging
var leftPanelMinimized* = false
var leftPanelPos* = Vector2(x: 10, y: 2)  # Default position
var leftPanelDragging* = false
var leftPanelDragOffset* = Vector2(x: 0, y: 0)

proc drawHUDPanelContent(game: Game, panelX, panelY, panelW: int32,
                         showMinimizeIcon: bool): int32 {.discardable.} =
  ## Draw the full status/wave/roguelite/power-up content column, parameterized
  ## by plain geometry so both the draggable classic panel and the fixed Border
  ## layout can share it. No input handling lives here.
  ##
  ## Returns the height the column actually consumed, in its own (unscaled)
  ## units. drawBorderHUDPanel uses that to pick a magnification that still fits
  ## the screen; callers that don't care can ignore it.
  var yOffset = panelY

  # Calculate height based on content
  let numPowerUps = min(game.player.powerUps.len, COMBINED_MAX_POWERUPS_VISIBLE)  # Newest installs stay visible.
  let hasPowerUpOverflow = game.player.powerUps.len > numPowerUps
  let powerUpHeight = if numPowerUps > 0:
    3 + 10 + (COMBINED_ITEM_HEIGHT * numPowerUps) +
      (if hasPowerUpOverflow: COMBINED_POWERUP_OVERFLOW_HEIGHT else: 0)
  else:
    0

  let waveInfoHeight = if (game.mode == gmWaveBased):
    if game.waveInProgress and not game.bossWaveManager.active: 35
    elif game.bossWaveManager.active or game.bossWaveManager.coinActive: 32
    else: 28
  else:
    0

  let rogueliteInfoHeight = if game.mode == gmRoguelite and game.rogueliteRun != nil:
    # Separator + title + route + LV/XP bar + shards + relics lines.
    var h: int32 = 47 + 12  # +12 for the LV/XP bar line added below the route
    if game.rogueliteRun.floor != nil:
      # Minimap rows: must match the cell/gap constants in the drawing block below.
      var minGY = DungeonGridSize
      var maxGY = 0
      for room in game.rogueliteRun.floor.rooms:
        minGY = min(minGY, room.gridY)
        maxGY = max(maxGY, room.gridY)
      h += (maxGY - minGY + 1).int32 * 13 + 5
    h
  else:
    0

  let totalHeight = 82 + powerUpHeight + waveInfoHeight + rogueliteInfoHeight +
                    (if powerUpHeight > 0: COMBINED_SECTION_SPACING else: 0)

  # Main panel background - more transparent and colorful
  drawRectangle(panelX, yOffset, panelW, totalHeight.int32,
               Color(r: 5, g: 15, b: 25, a: 45))

  # Cyan accent stripe on left edge
  drawRectangle(panelX, yOffset, 2, totalHeight.int32,
               Color(r: 0, g: 220, b: 255, a: 180))

  # Panel border with cyan glow - more transparent
  drawRectangleLines(Rectangle(x: panelX.float32, y: yOffset.float32,
                                width: panelW.float32, height: totalHeight.float32),
                    1, Color(r: 0, g: 220, b: 255, a: 80))

  yOffset += COMBINED_PANEL_PADDING

  # STATUS HEADER
  # Header bar background - colorful cyan (clickable to minimize)
  drawRectangle(panelX + 2, yOffset, panelW - 2, COMBINED_TITLE_HEIGHT,
               HEADER_BG_COLOR)

  drawText(t(tkGameStatus), panelX + COMBINED_PANEL_PADDING + 5, yOffset + 3, 11,
          Color(r: 0, g: 0, b: 0, a: 140))
  drawText(t(tkGameStatus), panelX + COMBINED_PANEL_PADDING + 4, yOffset + 2, 11,
          ACCENT_COLOR)

  # Draw minimize icon (horizontal line)
  if showMinimizeIcon:
    let iconX = panelX + panelW - COMBINED_PANEL_PADDING - 12
    let iconY = yOffset + 9
    drawLine(Vector2(x: iconX.float32, y: iconY.float32),
            Vector2(x: (iconX + 10).float32, y: iconY.float32),
            2, ACCENT_COLOR)

  yOffset += COMBINED_TITLE_HEIGHT + 2

  # HP BAR
  let hpPercent = game.player.hp / game.player.maxHp
  let barWidth: int32 = panelW - (COMBINED_PANEL_PADDING * 2)
  let barHeight: int32 = 10

  # HP label with shadow
  drawText("HP", panelX + COMBINED_PANEL_PADDING + 1, yOffset + 1, 9, Color(r: 0, g: 0, b: 0, a: 120))
  drawText("HP", panelX + COMBINED_PANEL_PADDING, yOffset, 9, Color(r: 220, g: 240, b: 255, a: 255))

  # HP value on right (multiplied by 100, showing decimals)
  let hpText = formatHealthDisplay(game.player.hp) & "/" & formatHealthDisplay(game.player.maxHp)
  let hpTextWidth = measureText(hpText, 9)
  drawText(hpText, panelX + panelW - COMBINED_PANEL_PADDING - hpTextWidth + 1, yOffset + 1, 9,
          Color(r: 0, g: 0, b: 0, a: 120))
  drawText(hpText, panelX + panelW - COMBINED_PANEL_PADDING - hpTextWidth, yOffset, 9,
          Color(r: 255, g: 255, b: 255, a: 255))

  yOffset += 10

  # HP bar background - semi-transparent
  drawRectangle(panelX + COMBINED_PANEL_PADDING, yOffset, barWidth, barHeight,
               Color(r: 10, g: 20, b: 30, a: 60))

  # HP bar fill - vibrant colors
  let fillWidth = (barWidth.float32 * hpPercent).int32
  let barColor = if hpPercent > 0.6: Color(r: 0, g: 255, b: 120, a: 220)
                elif hpPercent > 0.3: Color(r: 255, g: 220, b: 0, a: 220)
                else: Color(r: 255, g: 80, b: 80, a: 220)
  drawRectangle(panelX + COMBINED_PANEL_PADDING, yOffset, fillWidth, barHeight, barColor)

  # Singularity shield overlay, purple tint on the rightmost portion of the HP fill
  # covering however many HP points the shield currently protects
  if game.player.singularityShield > 0.0:
    let shieldCoveredHp = min(game.player.singularityShield, game.player.hp)
    let shieldBarWidth = (barWidth.float32 * (shieldCoveredHp / game.player.maxHp)).int32
    if shieldBarWidth > 0:
      let shieldBarX = panelX + COMBINED_PANEL_PADDING + fillWidth - shieldBarWidth
      drawRectangle(shieldBarX, yOffset, shieldBarWidth, barHeight,
                   Color(r: 155, g: 80, b: 255, a: 170))
      # Bright top-edge highlight for crispness
      drawRectangle(shieldBarX, yOffset, shieldBarWidth, 2,
                   Color(r: 210, g: 170, b: 255, a: 230))

  # Bar border - cyan accent
  drawRectangleLines(Rectangle(x: (panelX + COMBINED_PANEL_PADDING).float32, y: yOffset.float32,
                                width: barWidth.float32, height: barHeight.float32),
                    1, Color(r: 0, g: 220, b: 255, a: 120))

  yOffset += barHeight + 4

  # Background box for stats - semi-transparent with cyan tint
  drawRectangle(panelX + COMBINED_PANEL_PADDING + 2, yOffset - 1,
               panelW - (COMBINED_PANEL_PADDING * 2) - 4, 12,
               Color(r: 0, g: 30, b: 40, a: 50))

  # Charges - bright cyan
  drawText("[#]", panelX + COMBINED_PANEL_PADDING + 6, yOffset + 1, 9, Color(r: 0, g: 0, b: 0, a: 100))
  drawText("[#]", panelX + COMBINED_PANEL_PADDING + 5, yOffset, 9, Color(r: 0, g: 220, b: 255, a: 255))
  let chargeText = $game.player.walls
  drawText(chargeText, panelX + COMBINED_PANEL_PADDING + 17, yOffset, 10,
          if game.player.walls > 0: Color(r: 255, g: 255, b: 255, a: 255)
          else: Color(r: 120, g: 120, b: 120, a: 200))

  # Coins - bright gold
  drawCurrencyIcon(panelX + panelW div 2 - 11, yOffset + 6, 12, ciCredits)
  drawText($game.player.coins, panelX + panelW div 2 - 1, yOffset, 10, Color(r: 255, g: 255, b: 255, a: 255))

  # Processes - purple
  drawText("[*]", panelX + panelW - 40 + 1, yOffset + 1, 9, Color(r: 0, g: 0, b: 0, a: 100))
  drawText("[*]", panelX + panelW - 40, yOffset, 9, Color(r: 180, g: 100, b: 255, a: 255))
  drawText($game.player.powerUps.len, panelX + panelW - 27, yOffset, 10, Color(r: 255, g: 255, b: 255, a: 255))

  yOffset += 14

  # WAVE INFO (if applicable)
  if (game.mode == gmWaveBased):
    # Separator line
    drawLine(Vector2(x: (panelX + COMBINED_PANEL_PADDING + 3).float32, y: yOffset.float32),
            Vector2(x: (panelX + panelW - COMBINED_PANEL_PADDING - 3).float32, y: yOffset.float32),
            1, Color(r: 0, g: 200, b: 255, a: 100))
    yOffset += 3

    # Wave header - compact
    drawText(t(tkGameWaveInfo), panelX + COMBINED_PANEL_PADDING + 6, yOffset + 1, 9,
            Color(r: 0, g: 0, b: 0, a: 100))
    drawText(t(tkGameWaveInfo), panelX + COMBINED_PANEL_PADDING + 5, yOffset, 9,
            Color(r: 150, g: 150, b: 150, a: 255))
    yOffset += 10

    # Wave display - compact
    let waveDisplay = if game.bossWaveManager.active:
      "[!] " & t(tkGameBoss) & " W" & $game.currentWave
    else:
      "> " & t(tkGameWave) & " " & $game.currentWave

    let waveColor = if game.bossWaveManager.active:
      Color(r: 255, g: 80, b: 80, a: 255)
    else:
      Color(r: 120, g: 255, b: 120, a: 255)

    drawText(waveDisplay, panelX + COMBINED_PANEL_PADDING + 8, yOffset + 1, 11,
            Color(r: 0, g: 0, b: 0, a: 130))
    drawText(waveDisplay, panelX + COMBINED_PANEL_PADDING + 7, yOffset, 11, waveColor)
    yOffset += 13

    # Enemy Counter (single bar that empties as enemies are killed)
    if game.waveInProgress and not game.bossWaveManager.active:
      let currentEnemies = game.enemies.len  # Enemies currently on screen
      let toSpawn = game.waveEnemiesRemaining  # Enemies yet to spawn
      let totalRemaining = currentEnemies + toSpawn

      # Threat level colors based on remaining percentage
      let remainingPercent = totalRemaining.float32 / game.waveEnemiesTotal.float32
      let threatColor = if remainingPercent > 0.6:
        Color(r: 255, g: 50, b: 50, a: 255)
      elif remainingPercent > 0.3:
        Color(r: 255, g: 165, b: 0, a: 255)
      else:
        Color(r: 100, g: 220, b: 120, a: 255)

      # Warning icon with pulse for high threat
      let iconPulse = if remainingPercent > 0.5: sin(game.time * 8.0) * 0.3 + 0.7 else: 1.0
      let pulseColor = Color(
        r: uint8(threatColor.r.float32 * iconPulse),
        g: uint8(threatColor.g.float32 * iconPulse),
        b: uint8(threatColor.b.float32 * iconPulse),
        a: 255
      )

      drawText("[!]", panelX + COMBINED_PANEL_PADDING + 8, yOffset + 1, 14,
              Color(r: 0, g: 0, b: 0, a: 130))
      drawText("[!]", panelX + COMBINED_PANEL_PADDING + 7, yOffset, 14, pulseColor)

      # Enemy count display
      let countText = $totalRemaining & " " & t(tkGameLeft)
      let countWidth = measureText(countText, 12)
      let countX = panelX + panelW - COMBINED_PANEL_PADDING - countWidth - 5

      drawText(countText, countX + 1, yOffset + 2, 12, Color(r: 0, g: 0, b: 0, a: 130))
      drawText(countText, countX, yOffset + 1, 12, threatColor)

      yOffset += 14

      # Single bar that empties as enemies are killed
      let barWidth: int32 = panelW - (COMBINED_PANEL_PADDING * 2)
      let barFillPercent = totalRemaining.float32 / game.waveEnemiesTotal.float32

      # Bar background (empty state)
      drawRectangle(panelX + COMBINED_PANEL_PADDING, yOffset, barWidth, 6,
                   Color(r: 15, g: 20, b: 25, a: 120))

      # Bar fill (remaining enemies - starts full, decreases as you kill)
      let fillWidth = (barWidth.float32 * barFillPercent).int32
      drawRectangle(panelX + COMBINED_PANEL_PADDING, yOffset, fillWidth, 6, threatColor)

      # Border
      drawRectangleLines(Rectangle(
        x: (panelX + COMBINED_PANEL_PADDING).float32,
        y: yOffset.float32,
        width: barWidth.float32,
        height: 6.0
      ), 1, Color(r: 0, g: 200, b: 255, a: 140))

      yOffset += 8

    if game.bossWaveManager.active:
      drawText("[X] " & t(tkGameBossFight), panelX + COMBINED_PANEL_PADDING + 8, yOffset + 1, 10,
              Color(r: 0, g: 0, b: 0, a: 130))
      drawText("[X] " & t(tkGameBossFight), panelX + COMBINED_PANEL_PADDING + 7, yOffset, 10,
              Color(r: 255, g: 100, b: 100, a: 255))
      yOffset += 12

    elif game.bossWaveManager.coinActive:
      let pulseAlpha = (sin(game.time * 4.0) * 60 + 195).int.uint8
      drawText("[$] " & t(tkGameCollect), panelX + COMBINED_PANEL_PADDING + 8, yOffset + 1, 10,
              Color(r: 0, g: 0, b: 0, a: 130))
      drawText("[$] " & t(tkGameCollect), panelX + COMBINED_PANEL_PADDING + 7, yOffset, 10,
              Color(r: 255, g: 215, b: 0, a: pulseAlpha))
      yOffset += 12

  # ROGUELITE DUNGEON INFO + MINIMAP
  if game.mode == gmRoguelite and game.rogueliteRun != nil:
    let run = game.rogueliteRun
    let accent = ACCENT_COLOR
    let contentW: int32 = panelW - (COMBINED_PANEL_PADDING * 2) - 6

    drawLine(Vector2(x: (panelX + COMBINED_PANEL_PADDING + 3).float32, y: yOffset.float32),
            Vector2(x: (panelX + panelW - COMBINED_PANEL_PADDING - 3).float32, y: yOffset.float32),
            1, Color(r: 0, g: 200, b: 255, a: 100))
    yOffset += 3

    let combatTitle = t("roguelite_combat_title")
    let combatTitleSize = bestFitFontSize(combatTitle, contentW, 9, 6)
    drawText(combatTitle,
            panelX + COMBINED_PANEL_PADDING + 6, yOffset + 1, combatTitleSize,
            Color(r: 0, g: 0, b: 0, a: 100))
    drawText(combatTitle,
            panelX + COMBINED_PANEL_PADDING + 5, yOffset, combatTitleSize, accent)
    yOffset += max(10'i32, combatTitleSize + 1)

    let route = t("roguelite_floor") & " " & $run.floorNumber & "/" & $RogueliteFloorsToWin &
                "  " & t("dungeon_keys") & " " & $run.keys
    let routeSize = bestFitFontSize(route, contentW, 10, 6)
    drawText(route,
            panelX + COMBINED_PANEL_PADDING + 7, yOffset + 1, routeSize,
            Color(r: 0, g: 0, b: 0, a: 130))
    drawText(route,
            panelX + COMBINED_PANEL_PADDING + 6, yOffset, routeSize, White)
    yOffset += max(12'i32, routeSize + 2)

    # Level + XP bar: "LV n" label on the left, a thin progress bar filling the rest.
    block xpBar:
      let lvlLabel = t("roguelite_level") & " " & $game.player.rogueliteLevel
      const lvlSize: int32 = 9
      drawText(lvlLabel, panelX + COMBINED_PANEL_PADDING + 7, yOffset + 1, lvlSize,
              Color(r: 0, g: 0, b: 0, a: 130))
      drawText(lvlLabel, panelX + COMBINED_PANEL_PADDING + 6, yOffset, lvlSize,
              Color(r: 150, g: 255, b: 210, a: 255))
      let labelW = measureText(lvlLabel, lvlSize)
      let barX = panelX + COMBINED_PANEL_PADDING + 6 + labelW + 6
      let barRight = panelX + panelW - COMBINED_PANEL_PADDING - 6
      let barW = max(10'i32, barRight - barX)
      const barH: int32 = 6
      let barY = yOffset + (lvlSize - barH) div 2
      drawRectangle(barX, barY, barW, barH, Color(r: 10, g: 30, b: 25, a: 180))
      let ratio = clamp(game.player.xp.float32 /
                        max(1, game.player.xpToNextLevel).float32, 0.0, 1.0)
      let fillW = int32(barW.float32 * ratio)
      if fillW > 0:
        drawRectangle(barX, barY, fillW, barH, Color(r: 90, g: 255, b: 170, a: 230))
      drawRectangleLines(Rectangle(x: barX.float32, y: barY.float32,
                                   width: barW.float32, height: barH.float32),
                         1, Color(r: 120, g: 220, b: 190, a: 160))
    yOffset += max(12'i32, 9 + 2)

    # Floor minimap: filled = visited, outline = seen, everything if map found.
    if run.floor != nil:
      let floor = run.floor
      var minGX = DungeonGridSize
      var minGY = DungeonGridSize
      var maxGX = 0
      var maxGY = 0
      for room in floor.rooms:
        minGX = min(minGX, room.gridX)
        minGY = min(minGY, room.gridY)
        maxGX = max(maxGX, room.gridX)
        maxGY = max(maxGY, room.gridY)
      const cell: int32 = 11
      const gap: int32 = 2
      let mapW = (maxGX - minGX + 1).int32 * (cell + gap) - gap
      let mapX = panelX + COMBINED_PANEL_PADDING +
                 max(3'i32, (contentW - mapW) div 2)
      let mapY = yOffset + 2
      for i, room in floor.rooms:
        let known = room.visited or room.seen or floor.mapRevealed
        if not known:
          continue
        let cx = mapX + (room.gridX - minGX).int32 * (cell + gap)
        let cy = mapY + (room.gridY - minGY).int32 * (cell + gap)
        let isCurrent = i == floor.currentRoom
        var cellColor = Color(r: 70, g: 95, b: 125, a: 255)
        case room.kind
        of drkBoss:
          if room.visited or floor.mapRevealed or floor.compassFound:
            cellColor = Color(r: 255, g: 90, b: 90, a: 255)
        of drkShop:
          cellColor = Color(r: 255, g: 215, b: 0, a: 255)
        of drkTreasure:
          cellColor = Color(r: 190, g: 140, b: 255, a: 255)
        of drkElite:
          cellColor = Color(r: 255, g: 150, b: 80, a: 255)
        else:
          discard
        if room.visited or floor.mapRevealed:
          let fill = if room.cleared or room.kind in {drkStart, drkShop, drkTreasure}:
            withAlpha(cellColor, 180)
          else:
            withAlpha(cellColor, 90)
          drawRectangle(cx, cy, cell, cell, fill)
        drawRectangleLines(Rectangle(x: cx.float32, y: cy.float32,
                                     width: cell.float32, height: cell.float32),
                           1, cellColor)
        if isCurrent:
          let pulse = uint8(180 + sin(game.time * 5.0) * 60)
          drawRectangleLines(Rectangle(x: (cx - 1).float32, y: (cy - 1).float32,
                                       width: (cell + 2).float32, height: (cell + 2).float32),
                             1, Color(r: 255, g: 255, b: 255, a: pulse))
      yOffset += (maxGY - minGY + 1).int32 * (cell + gap) + 5

    var shardText = t("roguelite_heat") & " " & $run.heat & "  " &
                    t("roguelite_shards") & " +" & $run.shardsEarned
    if run.coresEarned > 0:
      shardText &= "  " & t("roguelite_cores_short") & " +" & $run.coresEarned
    let shardSize = bestFitFontSize(shardText, contentW - 15, 9, 6)
    drawCurrencyIcon(panelX + COMBINED_PANEL_PADDING + 10, yOffset + 6, 12, ciHeat)
    drawText(shardText,
            panelX + COMBINED_PANEL_PADDING + 22, yOffset + 1, shardSize,
            Color(r: 0, g: 0, b: 0, a: 130))
    drawText(shardText,
            panelX + COMBINED_PANEL_PADDING + 21, yOffset, shardSize, Gold)
    yOffset += max(11'i32, shardSize + 2)

    let relicText = t("roguelite_relics") & " " & $run.relics.len & "  " &
                    t("roguelite_endless") & " " & $run.endlessLoop
    let relicSize = bestFitFontSize(relicText, contentW, 9, 6)
    drawText(relicText,
            panelX + COMBINED_PANEL_PADDING + 7, yOffset + 1, relicSize,
            Color(r: 0, g: 0, b: 0, a: 130))
    drawText(relicText,
            panelX + COMBINED_PANEL_PADDING + 6, yOffset, relicSize,
            Color(r: 150, g: 220, b: 255, a: 255))
    yOffset += max(11'i32, relicSize + 2)

  # ACTIVE POWER-UPS LIST
  if game.player.powerUps.len > 0:
    # Separator line
    drawLine(Vector2(x: (panelX + COMBINED_PANEL_PADDING + 3).float32, y: yOffset.float32),
            Vector2(x: (panelX + panelW - COMBINED_PANEL_PADDING - 3).float32, y: yOffset.float32),
            1, Color(r: 0, g: 200, b: 255, a: 100))
    yOffset += 3

    # "Active Processes" header - compact
    let processCount = game.player.powerUps.len
    let processHeader = t(tkGameActive) & " [" & $processCount & "]:"
    drawText(processHeader, panelX + COMBINED_PANEL_PADDING + 6, yOffset + 1, 9,
            Color(r: 0, g: 0, b: 0, a: 100))
    drawText(processHeader, panelX + COMBINED_PANEL_PADDING + 5, yOffset, 9,
            Color(r: 200, g: 220, b: 240, a: 255))
    yOffset += 10

    # List newest power-ups first so the last install cannot vanish behind "+more".
    for i in 0..<numPowerUps:
      let powerUp = game.player.powerUps[game.player.powerUps.len - 1 - i]

      # Alternating row background
      let rowBg = if i mod 2 == 0:
        Color(r: 18, g: 25, b: 35, a: 70)
      else:
        Color(r: 12, g: 18, b: 28, a: 50)

      drawRectangle(panelX + COMBINED_PANEL_PADDING + 3, yOffset - 1,
                   panelW - (COMBINED_PANEL_PADDING * 2) - 6, COMBINED_ITEM_HEIGHT,
                   rowBg)

      let iconColor = if powerUp.rarity == prLegendary:
        Color(r: 255, g: 215, b: 0, a: 255)
      else:
        getPowerUpColor(powerUp.powerType)
      let pulse = if i == 0:
        0.5'f32 + 0.5'f32 * sin(game.time * 6.0'f32)
      else:
        0.0'f32
      let glowAlpha = if powerUp.rarity == prLegendary: 70 + int(pulse * 45.0'f32) else: 32 + int(pulse * 38.0'f32)

      drawRectangle(panelX + COMBINED_PANEL_PADDING + 7, yOffset + 3, 18, 18,
                    Color(r: 0, g: 0, b: 0, a: 125))
      drawRectangle(panelX + COMBINED_PANEL_PADDING + 6, yOffset + 2, 18, 18,
                    withAlpha(iconColor, glowAlpha))
      drawRectangleLines(Rectangle(x: (panelX + COMBINED_PANEL_PADDING + 6).float32,
                                    y: (yOffset + 2).float32,
                                    width: 18.0, height: 18.0),
                        1, withAlpha(iconColor, if powerUp.rarity == prLegendary: 240 else: 170))
      drawPowerUpIcon(panelX + COMBINED_PANEL_PADDING + 7, yOffset + 3, 16,
                      powerUp.powerType, iconColor)

      # Power-up name (shortened)
      let processName = getPowerUpName(powerUp.powerType)
      var displayName = processName
      let maxWidth = panelW - 84
      while measureText(displayName, 9) > maxWidth and displayName.len > 3:
        displayName = displayName[0..^2]
      if displayName.len < processName.len:
        displayName = displayName[0..^2] & ".."

      drawText(displayName, panelX + COMBINED_PANEL_PADDING + 31, yOffset + 3, 9,
              if powerUp.rarity == prLegendary:
                Color(r: 255, g: 232, b: 145, a: 255)
              else:
                Color(r: 230, g: 238, b: 245, a: 255))

      let hintText = if powerUp.rarity == prLegendary: "LEGENDARY" else: "PROCESS"
      drawText(hintText, panelX + COMBINED_PANEL_PADDING + 31, yOffset + 15, 6,
               withAlpha(iconColor, if powerUp.rarity == prLegendary: 230 else: 150))

      # Level indicator
      let levelText = if powerUp.rarity == prLegendary: "*" else: "L" & $powerUp.level
      let levelWidth = measureText(levelText, 10)
      drawText(levelText, panelX + panelW - COMBINED_PANEL_PADDING - levelWidth - 5,
              yOffset + 7, 10, withAlpha(iconColor, 235))

      yOffset += COMBINED_ITEM_HEIGHT

    # Show "+X more" if there are more than the visible stack
    if hasPowerUpOverflow:
      let moreText = "+" & $(game.player.powerUps.len - numPowerUps) & " more"

      drawRectangle(panelX + COMBINED_PANEL_PADDING + 3, yOffset - 1,
                   panelW - (COMBINED_PANEL_PADDING * 2) - 6, COMBINED_POWERUP_OVERFLOW_HEIGHT,
                   Color(r: 20, g: 25, b: 35, a: 100))

      drawText(moreText, panelX + COMBINED_PANEL_PADDING + 8, yOffset + 1, 8,
              Color(r: 0, g: 0, b: 0, a: 100))
      drawText(moreText, panelX + COMBINED_PANEL_PADDING + 7, yOffset, 8,
              Color(r: 120, g: 120, b: 120, a: 255))

      yOffset += COMBINED_POWERUP_OVERFLOW_HEIGHT

  result = yOffset - panelY

proc drawCombinedHUDPanel*(game: Game, x, y: int32) =
  ## Draw unified HUD panel combining status and wave/powerup info
  # Use stored position instead of parameters
  var yOffset = leftPanelPos.y.int32
  let panelX = leftPanelPos.x.int32

  # Handle dragging
  let mousePos = getVirtualMousePosition()
  let headerHeight = (COMBINED_PANEL_PADDING + COMBINED_TITLE_HEIGHT).float32
  let headerRect = Rectangle(
    x: panelX.float32,
    y: yOffset.float32,
    width: COMBINED_PANEL_WIDTH.float32,
    height: headerHeight
  )

  # Start dragging
  if isPointerDragStart() and checkCollisionPointRec(mousePos, headerRect):
    # Check if clicking on minimize button area (right side of header)
    let minimizeButtonX = panelX + COMBINED_PANEL_WIDTH - COMBINED_PANEL_PADDING - 12
    let minimizeButtonRect = Rectangle(
      x: minimizeButtonX.float32,
      y: (yOffset + COMBINED_PANEL_PADDING).float32,
      width: (when defined(mobile): 44 else: 16),
      height: COMBINED_TITLE_HEIGHT.float32
    )

    if checkCollisionPointRec(mousePos, minimizeButtonRect):
      # Toggle minimize
      leftPanelMinimized = not leftPanelMinimized
    else:
      # Repositioning the HUD is a mouse convenience that becomes a hazard on
      # touch: the panel sits in the left half, where the move joystick spawns,
      # so a mis-aimed thumb would drag the HUD instead of steering -- and it
      # clamps only to the screen, so it can be parked right on top of a stick.
      when not defined(mobile):
        leftPanelDragging = true
        leftPanelDragOffset = Vector2(
          x: mousePos.x - panelX.float32,
          y: mousePos.y - yOffset.float32
        )

  # Update dragging
  if leftPanelDragging:
    if isPointerDown():
      leftPanelPos = Vector2(
        x: mousePos.x - leftPanelDragOffset.x,
        y: mousePos.y - leftPanelDragOffset.y
      )
      # Clamp to screen bounds
      leftPanelPos.x = clamp(leftPanelPos.x, 0, (game.screenWidth - COMBINED_PANEL_WIDTH).float32)
      leftPanelPos.y = clamp(leftPanelPos.y, 0, (game.screenHeight - 50).float32)
    else:
      leftPanelDragging = false

  # Update yOffset and panelX after potential dragging
  yOffset = leftPanelPos.y.int32
  let finalPanelX = leftPanelPos.x.int32

  # If minimized, only draw header bar
  if leftPanelMinimized:
    # Draw minimized panel (just header)
    drawRectangle(finalPanelX, yOffset, COMBINED_PANEL_WIDTH, COMBINED_PANEL_PADDING + COMBINED_TITLE_HEIGHT,
                 Color(r: 5, g: 15, b: 25, a: 45))

    # Cyan accent stripe on left edge
    drawRectangle(finalPanelX, yOffset, 2, COMBINED_PANEL_PADDING + COMBINED_TITLE_HEIGHT,
                 Color(r: 0, g: 220, b: 255, a: 180))

    # Panel border
    drawRectangleLines(Rectangle(x: finalPanelX.float32, y: yOffset.float32,
                                  width: COMBINED_PANEL_WIDTH.float32,
                                  height: (COMBINED_PANEL_PADDING + COMBINED_TITLE_HEIGHT).float32),
                      1, Color(r: 0, g: 220, b: 255, a: 80))

    yOffset += COMBINED_PANEL_PADDING

    # Header with minimize indicator
    drawRectangle(finalPanelX + 2, yOffset, COMBINED_PANEL_WIDTH - 2, COMBINED_TITLE_HEIGHT,
                 HEADER_BG_COLOR)

    drawText(t(tkGameStatus), finalPanelX + COMBINED_PANEL_PADDING + 5, yOffset + 3, 11,
            Color(r: 0, g: 0, b: 0, a: 140))
    drawText(t(tkGameStatus), finalPanelX + COMBINED_PANEL_PADDING + 4, yOffset + 2, 11,
            ACCENT_COLOR)

    # Draw maximize icon (square)
    let iconX = finalPanelX + COMBINED_PANEL_WIDTH - COMBINED_PANEL_PADDING - 12
    let iconY = yOffset + 4
    drawRectangleLines(Rectangle(x: iconX.float32, y: iconY.float32, width: 10, height: 10),
                      1, ACCENT_COLOR)

    return  # Don't draw rest of panel

  drawHUDPanelContent(game, finalPanelX, yOffset, COMBINED_PANEL_WIDTH, showMinimizeIcon = true)

when defined(mobile):
  var lastBorderHudHeight = 512'i32
    ## Unscaled height the column used last frame. Unscaled, so feeding it back
    ## into the scale below cannot oscillate — the input is scale-independent.

proc drawBorderHUDPanel*(game: Game) =
  ## Fixed-position status column for the Border HUD layout, pinned to the top-left
  ## screen edge. No dragging or minimize behavior.
  when defined(mobile):
    # The column's ~50 text and gauge draws are hand-positioned against
    # BORDER_PANEL_WIDTH, so bumping font sizes individually would mean
    # re-laying out every row. Magnify the whole column with one matrix instead:
    # uniform, no reflow, and it can't desynchronize a label from its bar.
    #
    # The budget is the real gutter, which on mobile is wider than the desktop's
    # 171 because the canvas is fitted to the device aspect (main.mobileVirtualWidth).
    # Height is the other bound — a tall column (roguelite rows + a full power-up
    # stack) would otherwise run off the bottom.
    let gutterW = getWorldViewOffsetX()
    let widthCap = gutterW / BORDER_PANEL_WIDTH.float32
    let heightCap = (getVirtualScreenHeight().float32 - 8.0'f32) /
                    max(1.0'f32, lastBorderHudHeight.float32)
    let k = clamp(min(widthCap, heightCap), 1.0'f32, 2.0'f32)
    pushMatrix()
    scalef(k, k, 1.0'f32)
    lastBorderHudHeight = drawHUDPanelContent(game, 0, 0, BORDER_PANEL_WIDTH,
                                              showMinimizeIcon = false)
    popMatrix()
  else:
    drawHUDPanelContent(game, 0, 0, BORDER_PANEL_WIDTH, showMinimizeIcon = false)
