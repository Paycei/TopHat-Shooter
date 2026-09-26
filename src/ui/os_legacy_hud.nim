## Legacy in-game STATUS panel (Settings > Interface > HUD Style: Legacy).
##
## The pre-rework combined status panel, kept as it was so players can switch
## back to it: a floating, draggable panel in classic, pinned to the top of the
## left gutter in widescreen. It shares its drag/minimize state and the
## published row rects (which the tutorial highlights) with os_combined_hud, so
## switching styles keeps the panel where the player left it and the tutorial
## keeps pointing at the right rows.

import raylib, math, strutils
import ../types, ../localization, ../powerup_data, ../patches, ../roguelite, ../dungeon, ../render_context, icon_drawing, ../utils, ui_helpers
from ../player import DashCooldownTime
from os_combined_hud import leftPanelMinimized, leftPanelPos, leftPanelDragging,
                            leftPanelDragOffset, lastStatusPanelRect, lastStatsRowRect,
                            lastDashRowRect, lastLevelBarRect

const
  COMBINED_PANEL_WIDTH = 238
  BORDER_PANEL_WIDTH = 171   # widescreen left-gutter width = (1366-1024)/2
  COMBINED_PANEL_PADDING = 6
  COMBINED_SECTION_SPACING = 6
  COMBINED_ITEM_HEIGHT = 24
  COMBINED_TITLE_HEIGHT = 18
  COMBINED_MAX_POWERUPS_VISIBLE = 3
  COMBINED_POWERUP_OVERFLOW_HEIGHT = 14
  COMBINED_XP_BAR_HEIGHT = 12       # one drawLevelXpBar row (label 9 + 2 shadow/pad)
  COMBINED_DASH_ROW_HEIGHT = 13     # one drawDashRow line (bar 5 + label 9 - overlap)
  HEADER_BG_COLOR = Color(r: 0, g: 100, b: 120, a: 60)
  ACCENT_COLOR = Color(r: 0, g: 220, b: 255, a: 255)

proc drawLevelXpBar(game: Game, panelX, panelW, yOffset: int32) =
  ## "LV n" label on the left, a thin XP progress bar filling the rest.
  ##
  ## Shared by the roguelite dungeon panel and wave mode. Wave mode grew an XP
  ## bar when run-leveling was extended to it: without a visible bar the orbs
  ## are just floating litter, because the reward loop only reads as a reward
  ## once the player can see it accumulating toward something.
  lastLevelBarRect = Rectangle(x: panelX.float32, y: yOffset.float32 - 1,
                               width: panelW.float32, height: COMBINED_XP_BAR_HEIGHT.float32)
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

proc drawDashRow(game: Game, panelX, panelW, yOffset: int32) =
  ## DASH recharge strip: glyph + label on the left, a thin bar, and either the
  ## remaining seconds or READY on the right.
  ##
  ## The legendary [Q] panel can never host this. That panel only exists once a
  ## legendary ability is installed, while the dash is a base verb owned from
  ## wave 1, so the one ability every run always has would have been the only
  ## one with no cooldown readout anywhere.
  const labelSize: int32 = 9
  const barH: int32 = 5
  lastDashRowRect = Rectangle(x: panelX.float32, y: yOffset.float32 - 1,
                              width: panelW.float32, height: COMBINED_DASH_ROW_HEIGHT.float32)
  let cd = game.player.dashCooldown
  let ready = cd <= 0.0'f32
  let progress = if ready: 1.0'f32
                 else: clamp(1.0'f32 - cd / DashCooldownTime, 0.0'f32, 1.0'f32)
  let pulse = 0.5'f32 + 0.5'f32 * sin(game.time * 4.0'f32)

  # Glyph token, same vocabulary as the [#] / [*] stats row above.
  let glyphColor = if ready: Color(r: 120, g: 255, b: 225, a: 255)
                   else: Color(r: 90, g: 140, b: 170, a: 220)
  drawText("[>]", panelX + COMBINED_PANEL_PADDING + 6, yOffset + 1, labelSize,
          Color(r: 0, g: 0, b: 0, a: 100))
  drawText("[>]", panelX + COMBINED_PANEL_PADDING + 5, yOffset, labelSize, glyphColor)

  let label = t(tkHUDDash)
  let labelX = panelX + COMBINED_PANEL_PADDING + 24
  drawText(label, labelX, yOffset, labelSize,
          if ready: Color(r: 200, g: 245, b: 255, a: 255)
          else: Color(r: 140, g: 165, b: 185, a: 230))

  # Right-hand readout: exact seconds while recharging (one decimal, rounded up
  # so it never shows 0.0 while still spent), READY once it is back. Formatted
  # by hand to keep this module free of a strutils dependency.
  let rightText = if ready:
    t(tkHUDDashReady)
  else:
    let tenths = max(1, int(ceil(cd * 10.0'f32)))
    $(tenths div 10) & "." & $(tenths mod 10) & "s"
  let rightW = measureText(rightText, labelSize)

  # Bar fills whatever is left between the label and the readout.
  let barX = labelX + measureText(label, labelSize) + 6
  let barRight = panelX + panelW - COMBINED_PANEL_PADDING - rightW - 5
  let barW = max(10'i32, barRight - barX)
  let barY = yOffset + 2

  drawRectangle(barX, barY, barW, barH, Color(r: 10, g: 20, b: 30, a: 110))
  let fillW = int32(barW.float32 * progress)
  if fillW > 0:
    let fillColor = if ready:
      Color(r: uint8(80.0'f32 + 60.0'f32 * pulse), g: 255,
            b: uint8(200.0'f32 + 55.0'f32 * pulse), a: 235)
    else:
      Color(r: uint8(40.0'f32 + 50.0'f32 * progress),
            g: uint8(140.0'f32 + 105.0'f32 * progress),
            b: uint8(190.0'f32 + 65.0'f32 * progress), a: 220)
    drawRectangle(barX, barY, fillW, barH, fillColor)
  drawRectangleLines(Rectangle(x: barX.float32, y: barY.float32,
                               width: barW.float32, height: barH.float32),
                    1, Color(r: 0, g: 220, b: 255, a: if ready: 150 else: 90))

  let rightX = panelX + panelW - COMBINED_PANEL_PADDING - rightW
  drawText(rightText, rightX + 1, yOffset + 1, labelSize, Color(r: 0, g: 0, b: 0, a: 120))
  drawText(rightText, rightX, yOffset, labelSize,
          if ready: Color(r: uint8(140.0'f32 + 100.0'f32 * pulse), g: 255, b: 225, a: 255)
          else: Color(r: 170, g: 200, b: 220, a: 235))

# ---------------------------------------------------------------------------
# Roguelite sector block: title, folder breadcrumb, progress pips to SERVICE,
# LV/XP, heat + shards, and the PATCHES icon rows. rogueliteHudHeight and
# drawRogueliteHudBlock share the row constants below, so the panel's height
# budget can never drift from what is drawn.

const
  RogueHudTitleH = 10'i32
  RogueHudPathH = 12'i32
  RogueHudPipsH = 12'i32
  RogueHudShardsH = 11'i32
  RogueHudPatchIcon = 14'i32
  RogueHudPatchPitch = 16'i32

proc rogueliteContentW(panelW: int32): int32 =
  panelW - (COMBINED_PANEL_PADDING * 2) - 6

proc roguelitePatchRows(count: int, contentW: int32): int32 =
  if count <= 0: return 0
  let perRow = max(1'i32, contentW div RogueHudPatchPitch)
  ((count.int32 + perRow - 1) div perRow)

proc rogueliteHudHeight(game: Game, panelW: int32): int32 =
  result = 3 + RogueHudTitleH + RogueHudPathH + RogueHudPipsH +
           COMBINED_XP_BAR_HEIGHT + RogueHudShardsH
  let rows = roguelitePatchRows(game.rogueliteRun.relics.len, rogueliteContentW(panelW))
  if rows > 0:
    result += rows * RogueHudPatchPitch + 2

proc drawShadowText(text: string, x, y, size: int32, color: Color) =
  drawText(text, x + 1, y + 1, size, Color(r: 0, g: 0, b: 0, a: 130))
  drawText(text, x, y, size, color)

proc drawRogueliteHudBlock(game: Game, panelX, panelW: int32, yOffset: var int32) =
  let run = game.rogueliteRun
  let contentW = rogueliteContentW(panelW)
  let textX = panelX + COMBINED_PANEL_PADDING + 6

  drawLine(Vector2(x: (panelX + COMBINED_PANEL_PADDING + 3).float32, y: yOffset.float32),
          Vector2(x: (panelX + panelW - COMBINED_PANEL_PADDING - 3).float32, y: yOffset.float32),
          1, Color(r: 0, g: 200, b: 255, a: 100))
  yOffset += 3

  # DEEP RECOVERY // SECTOR 2/4
  var title = t("roguelite_hud_title") & " // " & t("roguelite_sector_upper") & " " &
              $run.floorNumber & "/" & $RogueliteFloorsToWin
  if run.endlessLoop > 0:
    title &= "  +" & $run.endlessLoop
  let titleSize = bestFitFontSize(title, contentW, 9, 6)
  drawShadowText(title, textX - 1, yOffset, titleSize, ACCENT_COLOR)
  yOffset += RogueHudTitleH

  let floor = run.floor
  if floor.isNil:
    yOffset += RogueHudPathH + RogueHudPipsH
  else:
    # Breadcrumb, trimmed from the LEFT so the folder you are in stays visible.
    var path = sectorPath(floor)
    const pathSize: int32 = 9
    if measureText(path, pathSize) > contentW:
      # Drop whole leading folders, never half a name.
      var tail = path
      while measureText(".." & tail, pathSize) > contentW:
        let cut = tail.find('\\', 1)
        if cut < 0: break
        tail = tail[cut .. ^1]
      path = ".." & tail
    drawShadowText(path, textX, yOffset + 1, pathSize, themeAccent(floor.theme))
    yOffset += RogueHudPathH

    # Progress pips: one per reward layer, then the SERVICE.
    let layers = sectorRewardLayers(floor)
    let current = if floor.rooms.len > 0: floor.rooms[floor.rooms.high].layer else: 0
    var px = textX
    let py = yOffset + 2
    for layer in 1..layers:
      let rect = Rectangle(x: px.float32, y: py.float32, width: 9, height: 6)
      if layer < current or (layer == current and currentDungeonRoom(run).cleared):
        drawRectangle(rect, Color(r: 0, g: 200, b: 255, a: 200))
      elif layer == current:
        let pulse = uint8(150.0 + sin(game.time * 5.0) * 90.0)
        drawRectangle(rect, Color(r: 255, g: 255, b: 255, a: pulse))
      drawRectangleLines(rect, 1, Color(r: 0, g: 200, b: 255, a: 170))
      px += 12
    let atBoss = current > layers
    let service = "> " & t("room_reward_service")
    drawShadowText(service, px + 2, yOffset, 9,
                   if atBoss: Color(r: 255, g: 110, b: 90, a: 255)
                   else: Color(r: 255, g: 150, b: 120, a: 200))
    yOffset += RogueHudPipsH

  # Level + XP bar (shared with wave mode -- see drawLevelXpBar).
  drawLevelXpBar(game, panelX, panelW, yOffset)
  yOffset += COMBINED_XP_BAR_HEIGHT

  var shardText = t("roguelite_heat") & " " & $run.heat & "  " &
                  t("roguelite_shards") & " +" & $run.shardsEarned
  if run.coresEarned > 0:
    shardText &= "  " & t("roguelite_cores_short") & " +" & $run.coresEarned
  let shardSize = bestFitFontSize(shardText, contentW - 15, 9, 6)
  drawCurrencyIcon(panelX + COMBINED_PANEL_PADDING + 10, yOffset + 6, 12, ciHeat)
  drawShadowText(shardText, panelX + COMBINED_PANEL_PADDING + 21, yOffset, shardSize, Gold)
  yOffset += RogueHudShardsH

  # PATCHES: one icon per applied update, dimmed while its charge is spent.
  let rows = roguelitePatchRows(run.relics.len, contentW)
  if rows > 0:
    let perRow = max(1'i32, contentW div RogueHudPatchPitch)
    for i, relic in run.relics:
      let col = i.int32 mod perRow
      let row = i.int32 div perRow
      let ix = textX + col * RogueHudPatchPitch
      let iy = yOffset + 1 + row * RogueHudPatchPitch
      let accent = patchAccent(relic.relicType)
      let tint = if patchSpent(game, relic.relicType): withAlpha(accent, 90) else: accent
      drawPatchIcon(ix, iy, RogueHudPatchIcon, relic.relicType, tint)
    yOffset += rows * RogueHudPatchPitch + 2

proc drawHUDPanelContent(game: Game, panelX, panelY, panelW: int32, showMinimizeIcon: bool) =
  ## Draw the full status/wave/roguelite/power-up content column, parameterized
  ## by plain geometry so both the draggable classic panel and the fixed Border
  ## layout can share it. No input handling lives here.
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
    # Every wave-mode branch also draws a LV/XP bar row, so it is added to all
    # three budgets. Miss it and the bar hangs below the panel border whenever
    # nothing else extends the panel -- i.e. exactly when there are no power-ups.
    COMBINED_XP_BAR_HEIGHT + (
      if game.waveInProgress and not game.bossWaveManager.active: 35
      elif game.bossWaveManager.active or game.bossWaveManager.coinActive: 32
      else: 28)
  else:
    0

  let rogueliteInfoHeight = if game.mode == gmRoguelite and game.rogueliteRun != nil:
    rogueliteHudHeight(game, panelW)
  else:
    0

  let totalHeight = 82 + COMBINED_DASH_ROW_HEIGHT + powerUpHeight + waveInfoHeight +
                    rogueliteInfoHeight +
                    (if powerUpHeight > 0: COMBINED_SECTION_SPACING else: 0)
  lastStatusPanelRect = Rectangle(x: panelX.float32, y: yOffset.float32,
                                  width: panelW.float32, height: totalHeight.float32)
  lastLevelBarRect = Rectangle()  # re-published below only by the modes that draw it

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

  lastStatsRowRect = Rectangle(x: panelX.float32, y: yOffset.float32 - 2,
                               width: panelW.float32, height: 14)

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

  # DASH RECHARGE (always present -- the dash is owned from wave 1 in every mode)
  drawDashRow(game, panelX, panelW, yOffset)
  yOffset += COMBINED_DASH_ROW_HEIGHT

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

    # Wave mode earns power-ups from XP levels now, so it needs the same bar the
    # dungeon has.
    if game.mode == gmWaveBased:
      drawLevelXpBar(game, panelX, panelW, yOffset)
      yOffset += COMBINED_XP_BAR_HEIGHT

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

  # ROGUELITE SECTOR BLOCK (see drawRogueliteHudBlock)
  if game.mode == gmRoguelite and game.rogueliteRun != nil:
    drawRogueliteHudBlock(game, panelX, panelW, yOffset)

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

proc drawLegacyStatusPanel*(game: Game, x, y: int32) =
  ## Draw unified HUD panel combining status and wave/powerup info
  # Keep the remembered position inside the layer's logical viewport. Changing
  # the UI scale resizes that viewport under a panel that was dragged to fit the
  # old one, so this runs every frame rather than only while dragging.
  leftPanelPos.x = clamp(leftPanelPos.x, 0,
                         max(0'f32, (getVirtualScreenWidth() - COMBINED_PANEL_WIDTH).float32))
  leftPanelPos.y = clamp(leftPanelPos.y, 0,
                         max(0'f32, (getVirtualScreenHeight() - 50).float32))

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
  if isPointerPressed() and checkCollisionPointRec(mousePos, headerRect):
    # Check if clicking on minimize button area (right side of header)
    let minimizeButtonX = panelX + COMBINED_PANEL_WIDTH - COMBINED_PANEL_PADDING - 12
    let minimizeButtonRect = Rectangle(
      x: minimizeButtonX.float32,
      y: (yOffset + COMBINED_PANEL_PADDING).float32,
      width: 16,
      height: COMBINED_TITLE_HEIGHT.float32
    )

    if checkCollisionPointRec(mousePos, minimizeButtonRect):
      # Toggle minimize
      leftPanelMinimized = not leftPanelMinimized
    else:
      # Start dragging
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
      # Clamp to the layer's logical viewport (which is the world size at the
      # default UI scale, and smaller/larger at any other).
      leftPanelPos.x = clamp(leftPanelPos.x, 0,
                             max(0'f32, (getVirtualScreenWidth() - COMBINED_PANEL_WIDTH).float32))
      leftPanelPos.y = clamp(leftPanelPos.y, 0,
                             max(0'f32, (getVirtualScreenHeight() - 50).float32))
    else:
      leftPanelDragging = false

  # Update yOffset and panelX after potential dragging
  yOffset = leftPanelPos.y.int32
  let finalPanelX = leftPanelPos.x.int32

  # If minimized, only draw header bar
  if leftPanelMinimized:
    lastStatusPanelRect = Rectangle(x: finalPanelX.float32, y: yOffset.float32,
                                    width: COMBINED_PANEL_WIDTH.float32,
                                    height: (COMBINED_PANEL_PADDING + COMBINED_TITLE_HEIGHT).float32)
    lastStatsRowRect = Rectangle()
    lastDashRowRect = Rectangle()
    lastLevelBarRect = Rectangle()
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

proc drawLegacyBorderPanel*(game: Game) =
  ## Fixed-position status column for the Border HUD layout, pinned to the top-left
  ## screen edge. No dragging or minimize behavior.
  drawHUDPanelContent(game, 0, 0, BORDER_PANEL_WIDTH, showMinimizeIcon = false)
