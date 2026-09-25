## Player HUD: the STATUS column and the mode objective blocks.
##
## Two presentations share one set of row drawers (HP, level, resources, dash,
## processes, wave, roguelite sector):
##   * classic (4:3) -- a floating, draggable, minimizable STATUS panel over the
##     arena. Classic has no second column, so the wave / roguelite blocks ride
##     inside it.
##   * widescreen (16:9) -- the left dock (drawPlayerDock): a STATUS card pinned
##     to the top of the band and a PROCESSES card that grows into whatever
##     height the band has left. The wave / roguelite blocks move to the top of
##     the right dock as objective cards (drawWaveDockCard / drawRogueliteDockCard).
##
## Every row drawer takes the content column (cx, cw) and a top y, and returns
## the y below itself; the *H constants are the heights they consume, which the
## classic panel sums up front to size its background.

import raylib, math, strutils
import ../types, ../localization, ../powerup_data, ../patches, ../roguelite, ../dungeon, ../settings, ui_constants, ../render_context, icon_drawing, ../utils, ui_helpers, hud_dock
from ../player import DashCooldownTime

const
  COMBINED_PANEL_WIDTH = 238
  COMBINED_PANEL_PADDING = 6
  COMBINED_TITLE_HEIGHT = 18
  COMBINED_MAX_POWERUPS_VISIBLE = 3
  HEADER_BG_COLOR = Color(r: 0, g: 100, b: 120, a: 60)
  ACCENT_COLOR = Color(r: 0, g: 220, b: 255, a: 255)

  # Row heights, each including the spacing below the row.
  HpBlockH = 36'i32
  LevelRowH = 15'i32
  ResourceRowH = 31'i32
  DashRowH = 14'i32
  ProcessRowH = 20'i32
  ProcessHeaderH = 15'i32
  WaveBodyH = 58'i32
  DividerH = 7'i32

  XpGreen = Color(r: 90, g: 255, b: 170, a: 235)
  XpGold = Color(r: 255, g: 215, b: 60, a: 245)
  LegendaryGold = Color(r: 255, g: 215, b: 0, a: 255)

# State for panel minimization and dragging
var leftPanelMinimized* = false
var leftPanelPos* = Vector2(x: 10, y: 2)  # Default position
var leftPanelDragging* = false
var leftPanelDragOffset* = Vector2(x: 0, y: 0)

# Where the status panel's rows landed on the most recent draw, in the HUD
# layer's coordinates. Published (rather than recomputed) so overlays that point
# at the panel -- the tutorial's row highlights -- can never drift from the real
# layout. A zero-width rect means the row wasn't drawn this frame.
var lastStatusPanelRect*: Rectangle
var lastStatsRowRect*: Rectangle   ## credits / walls row
var lastDashRowRect*: Rectangle
var lastLevelBarRect*: Rectangle   ## LV / XP bar (modes that level only)

proc modeShowsLevel(game: Game): bool =
  ## Modes whose runs level from XP orbs, i.e. the ones with an XP bar.
  game.mode in {gmWaveBased, gmRoguelite, gmTimeSurvival}

proc drawDivider(cx, cw, y: int32) =
  drawRectangle(cx, y + 3, cw, 1, withAlpha(DockAccent, 60))

# ---------------------------------------------------------------------------
# Status rows

proc drawHpBlock(game: Game, cx, cw, y: int32): int32 =
  ## HP label, "current / max" readout and a segmented bar. Below 30% the
  ## label and rim pulse red so a glance at the band is enough.
  let p = game.player
  let frac = clamp(p.hp / max(p.maxHp, 0.01'f32), 0.0'f32, 1.0'f32)
  let low = frac <= 0.3'f32
  let pulse = 0.5'f32 + 0.5'f32 * sin(game.time * 7.0'f32)
  let fill = if frac > 0.6'f32: Color(r: 0, g: 235, b: 125, a: 235)
             elif frac > 0.3'f32: Color(r: 255, g: 210, b: 0, a: 235)
             else: Color(r: 255, g: uint8(60.0'f32 + 40.0'f32 * pulse), b: 70, a: 240)

  let labelColor = if low: Color(r: 255, g: uint8(90.0'f32 + 90.0'f32 * pulse), b: 90, a: 255)
                   else: DockDim
  drawShadowText("HP", cx, y + 9, 10, labelColor)

  let curText = formatHealthDisplay(p.hp)
  let maxText = "/" & formatHealthDisplay(p.maxHp)
  let maxW = measureText(maxText, 10)
  let curSize = bestFitFontSize(curText, cw - 24 - maxW - 3, 20, 10)
  let curW = measureText(curText, curSize)
  drawShadowText(maxText, cx + cw - maxW, y + 9, 10, DockDim)
  drawShadowText(curText, cx + cw - maxW - 3 - curW, y + 19 - curSize, curSize,
                 if low: Color(r: 255, g: 150, b: 150, a: 255) else: DockInk)

  let barY = y + 22
  const barH = 10'i32
  drawDockBar(cx, barY, cw, barH, frac, fill)
  let fillW = int32(cw.float32 * frac)

  # Singularity shield: purple over the rightmost part of the fill, covering
  # however many HP points the shield currently protects.
  if p.singularityShield > 0.0'f32:
    let covered = min(p.singularityShield, p.hp)
    let shieldW = int32(cw.float32 * (covered / max(p.maxHp, 0.01'f32)))
    if shieldW > 0:
      let sx = cx + fillW - shieldW
      drawRectangle(sx, barY, shieldW, barH, Color(r: 155, g: 80, b: 255, a: 185))
      drawRectangle(sx, barY, shieldW, 2, Color(r: 210, g: 170, b: 255, a: 235))

  # One notch per 100 displayed HP while they stay readable.
  let segs = int(p.maxHp)
  if segs > 1 and cw div segs.int32 >= 6:
    for s in 1..<segs:
      let tx = cx + int32(cw.float32 * (s.float32 / p.maxHp))
      drawRectangle(tx, barY + 1, 1, barH - 2, Color(r: 0, g: 0, b: 0, a: 90))

  let rim = if low: Color(r: 255, g: 80, b: 80, a: uint8(120.0'f32 + 120.0'f32 * pulse))
            else: withAlpha(DockAccent, 110)
  drawRectangleLines(Rectangle(x: cx.float32, y: barY.float32, width: cw.float32,
                               height: barH.float32), 1, rim)
  y + HpBlockH

proc drawLevelRow(game: Game, cx, cw, y: int32): int32 =
  ## "LV n" and a thin XP bar filling the rest of the row.
  ##
  ## Wave mode grew an XP bar when run-leveling was extended to it: without a
  ## visible bar the orbs are just floating litter, because the reward loop only
  ## reads as a reward once the player can see it accumulating toward something.
  lastLevelBarRect = Rectangle(x: (cx - 3).float32, y: (y - 2).float32,
                               width: (cw + 6).float32, height: (LevelRowH - 1).float32)
  let overclock = game.mode == gmTimeSurvival and game.survival.event.kind == sekOverclock
  let label = t("roguelite_level") & " " & $game.player.rogueliteLevel
  drawShadowText(label, cx, y, 10,
                 if overclock: XpGold else: Color(r: 150, g: 255, b: 210, a: 255))
  let barX = cx + measureText(label, 10) + 7
  let barW = max(10'i32, cx + cw - barX)
  let ratio = game.player.xp.float32 / max(1, game.player.xpToNextLevel).float32
  drawDockBar(barX, y + 2, barW, 6, ratio, if overclock: XpGold else: XpGreen,
              if overclock: withAlpha(XpGold, 170) else: Color(r: 120, g: 220, b: 190, a: 150))
  y + LevelRowH

proc drawWallGlyph(x, y: int32, color: Color) =
  ## A little two-course brick wall, 13x10.
  drawRectangle(x, y, 6, 4, color)
  drawRectangle(x + 7, y, 6, 4, color)
  drawRectangle(x, y + 5, 2, 4, color)
  drawRectangle(x + 3, y + 5, 6, 4, color)
  drawRectangle(x + 10, y + 5, 3, 4, color)

proc drawResourceTiles(game: Game, cx, cw, y: int32): int32 =
  ## Credits and wall charges as two tiles: an icon and a big number each.
  const tileH = 27'i32
  const gap = 4'i32
  let creditW = (cw - gap) * 3 div 5
  let wallW = cw - gap - creditW
  lastStatsRowRect = Rectangle(x: (cx - 3).float32, y: (y - 2).float32,
                               width: (cw + 6).float32, height: (tileH + 4).float32)
  let tileBg = Color(r: 0, g: 26, b: 38, a: 150)

  # Credits
  drawRectangle(cx, y, creditW, tileH, tileBg)
  drawRectangleLines(Rectangle(x: cx.float32, y: y.float32, width: creditW.float32,
                               height: tileH.float32), 1, Color(r: 255, g: 215, b: 0, a: 60))
  drawCurrencyIcon(cx + 12, y + tileH div 2, 15, ciCredits)
  let coinText = $game.player.coins
  let coinSize = bestFitFontSize(coinText, creditW - 30, 20, 10)
  let coinW = measureText(coinText, coinSize)
  drawShadowText(coinText, cx + creditW - 6 - coinW, y + (tileH - coinSize) div 2 + 1,
                 coinSize, Color(r: 255, g: 228, b: 120, a: 255))

  # Wall charges
  let wx = cx + creditW + gap
  let hasWalls = game.player.walls > 0
  let wallColor = if hasWalls: DockAccent else: Color(r: 90, g: 110, b: 125, a: 220)
  drawRectangle(wx, y, wallW, tileH, tileBg)
  drawRectangleLines(Rectangle(x: wx.float32, y: y.float32, width: wallW.float32,
                               height: tileH.float32), 1, withAlpha(wallColor, 70))
  drawWallGlyph(wx + 6, y + (tileH - 9) div 2, wallColor)
  let wallText = $game.player.walls
  let wallSize = bestFitFontSize(wallText, wallW - 26, 20, 10)
  let wallTextW = measureText(wallText, wallSize)
  drawShadowText(wallText, wx + wallW - 6 - wallTextW, y + (tileH - wallSize) div 2 + 1,
                 wallSize, if hasWalls: DockInk else: DockDim)
  y + ResourceRowH

proc drawDashRow(game: Game, cx, cw, y: int32): int32 =
  ## DASH recharge strip: glyph + label, a bar, and the remaining seconds or
  ## READY on the right.
  ##
  ## The legendary [Q] panel can never host this. That panel only exists once a
  ## legendary ability is installed, while the dash is a base verb owned from
  ## wave 1, so the one ability every run always has would have been the only
  ## one with no cooldown readout anywhere.
  lastDashRowRect = Rectangle(x: (cx - 3).float32, y: (y - 2).float32,
                              width: (cw + 6).float32, height: DashRowH.float32)
  let cd = game.player.dashCooldown
  let ready = cd <= 0.0'f32
  let progress = if ready: 1.0'f32
                 else: clamp(1.0'f32 - cd / DashCooldownTime, 0.0'f32, 1.0'f32)
  let pulse = 0.5'f32 + 0.5'f32 * sin(game.time * 4.0'f32)

  let label = t(tkHUDDash)
  drawShadowText(label, cx, y, 10,
                 if ready: Color(r: 200, g: 245, b: 255, a: 255)
                 else: Color(r: 140, g: 165, b: 185, a: 230))

  # Exact seconds while recharging (one decimal, rounded up so it never shows
  # 0.0 while still spent), READY once it is back.
  let rightText = if ready:
    t(tkHUDDashReady)
  else:
    let tenths = max(1, int(ceil(cd * 10.0'f32)))
    $(tenths div 10) & "." & $(tenths mod 10) & "s"
  let rightW = measureText(rightText, 10)
  drawShadowText(rightText, cx + cw - rightW, y, 10,
                 if ready: Color(r: uint8(140.0'f32 + 100.0'f32 * pulse), g: 255, b: 225, a: 255)
                 else: Color(r: 170, g: 200, b: 220, a: 235))

  let barX = cx + measureText(label, 10) + 7
  let barW = max(10'i32, cx + cw - rightW - 6 - barX)
  let fill = if ready:
    Color(r: uint8(80.0'f32 + 60.0'f32 * pulse), g: 255, b: uint8(200.0'f32 + 55.0'f32 * pulse), a: 235)
  else:
    Color(r: uint8(40.0'f32 + 50.0'f32 * progress), g: uint8(140.0'f32 + 105.0'f32 * progress),
          b: uint8(190.0'f32 + 65.0'f32 * progress), a: 220)
  drawDockBar(barX, y + 2, barW, 6, progress, fill,
              withAlpha(DockAccent, if ready: 150 else: 80))
  y + DashRowH

# ---------------------------------------------------------------------------
# Processes (installed power-ups) and patches (roguelite)

proc drawLevelPips(pu: PowerUp, rightX, y: int32, color: Color): int32 =
  ## Level as filled pips out of the power-up's max, right-aligned at rightX;
  ## legendaries (single-level) get a gold diamond. Returns the width used.
  if pu.rarity == prLegendary:
    let c = Vector2(x: (rightX - 5).float32, y: (y + 5).float32)
    drawPoly(c, 4, 5.0'f32, 0.0'f32, LegendaryGold)
    drawPolyLines(c, 4, 5.5'f32, 0.0'f32, Color(r: 255, g: 245, b: 190, a: 255))
    return 11
  let total = max(pu.level, getPowerUpMaxLevel(pu.powerType))
  if total > 5:
    let txt = "L" & $pu.level
    let w = measureText(txt, 10)
    drawShadowText(txt, rightX - w, y, 10, color)
    return w
  const pipW = 4'i32
  const pipGap = 2'i32
  let w = total.int32 * pipW + (total.int32 - 1) * pipGap
  for i in 0..<total:
    let px = rightX - w + i.int32 * (pipW + pipGap)
    if i < pu.level:
      drawRectangle(px, y + 1, pipW, 8, withAlpha(color, 235))
    else:
      drawRectangleLines(Rectangle(x: px.float32, y: (y + 1).float32, width: pipW.float32,
                                   height: 8.0'f32), 1, withAlpha(color, 90))
  w

proc drawProcessRow(game: Game, pu: PowerUp, cx, cw, y: int32, fresh: bool, shade: bool) =
  let legendary = pu.rarity == prLegendary
  let color = if legendary: LegendaryGold else: getPowerUpColor(pu.powerType)
  if shade:
    drawRectangle(cx - 2, y, cw + 4, ProcessRowH, Color(r: 255, g: 255, b: 255, a: 7))
  # Newest install breathes so the last pick is easy to find.
  let pulse = if fresh: 0.5'f32 + 0.5'f32 * sin(game.time * 6.0'f32) else: 0.0'f32
  let glow = if legendary: 70 + int(pulse * 45.0'f32) else: 34 + int(pulse * 40.0'f32)
  const box = 16'i32
  let by = y + (ProcessRowH - box) div 2
  drawRectangle(cx, by, box, box, withAlpha(color, glow))
  drawRectangleLines(Rectangle(x: cx.float32, y: by.float32, width: box.float32,
                               height: box.float32), 1,
                     withAlpha(color, if legendary: 240 else: 170))
  drawPowerUpIcon(cx + 1, by + 1, box - 2, pu.powerType, color)

  let pipsW = drawLevelPips(pu, cx + cw, y + (ProcessRowH - 10) div 2, color)
  let nameX = cx + box + 6
  let maxW = cx + cw - pipsW - 6 - nameX
  drawShadowText(fitWithEllipsis(getPowerUpName(pu.powerType), maxW, 10), nameX,
                 y + (ProcessRowH - 10) div 2, 10,
                 if legendary: Color(r: 255, g: 232, b: 145, a: 255) else: DockInk)

proc drawProcessRows(game: Game, cx, cw, y: int32, maxRows: int): int32 =
  ## Up to maxRows rows, newest install first so the last pick can never vanish
  ## behind the overflow line. When they don't all fit the last row becomes
  ## "+N more".
  let pus = game.player.powerUps
  let n = pus.len
  if n == 0 or maxRows <= 0:
    return y
  let shown = if n > maxRows: max(0, maxRows - 1) else: n
  var ry = y
  for i in 0..<shown:
    drawProcessRow(game, pus[n - 1 - i], cx, cw, ry, fresh = i == 0, shade = i mod 2 == 1)
    ry += ProcessRowH
  if shown < n:
    let more = "+" & $(n - shown) & " " & t(tkHUDMore)
    drawShadowText(more, cx + 22, ry + (ProcessRowH - 10) div 2, 10, DockDim)
    ry += ProcessRowH
  ry

proc processHeaderText(game: Game): string =
  t(tkHUDProcesses) & " [" & $game.player.powerUps.len & "]"

const PatchCardAccent = Color(r: 120, g: 200, b: 255, a: 255)
  ## The /updates folder's colour: that is where patches come from.

proc runPatchCount(game: Game): int =
  if game.mode == gmRoguelite and not game.rogueliteRun.isNil: game.rogueliteRun.relics.len
  else: 0

proc drawPatchRow(game: Game, patch: RogueliteRelicType, cx, cw, y: int32,
                  fresh: bool, shade: bool) =
  ## Same shape as a process row: the patch glyph in its category colour, the
  ## patch's name, and a READY / USED / STALLED tag for the ones with a charge.
  ## A spent patch dims, so the tag explains why.
  let status = patchStatus(game, patch)
  let spent = status in {psUsed, psStalled}
  let color = patchAccent(patch)
  if shade:
    drawRectangle(cx - 2, y, cw + 4, ProcessRowH, Color(r: 255, g: 255, b: 255, a: 7))
  let pulse = if fresh: 0.5'f32 + 0.5'f32 * sin(game.time * 6.0'f32) else: 0.0'f32
  const box = 16'i32
  let by = y + (ProcessRowH - box) div 2
  drawRectangle(cx, by, box, box, withAlpha(color, if spent: 18 else: 34 + int(pulse * 40.0'f32)))
  drawRectangleLines(Rectangle(x: cx.float32, y: by.float32, width: box.float32,
                               height: box.float32), 1, withAlpha(color, if spent: 80 else: 170))
  drawPatchIcon(cx + 1, by + 1, box - 2, patch, if spent: withAlpha(color, 90) else: color)

  let textY = y + (ProcessRowH - 10) div 2
  var tagW = 0'i32
  if status != psPassive:
    let tag = patchStatusLabel(status)
    tagW = measureText(tag, 10)
    drawShadowText(tag, cx + cw - tagW, textY, 10, patchStatusColor(status))
  let nameX = cx + box + 6
  let maxW = cx + cw - nameX - (if tagW > 0: tagW + 6 else: 0)
  drawShadowText(fitWithEllipsis(patchName(patch), maxW, 10), nameX, textY, 10,
                 if spent: DockDim else: DockInk)

proc drawPatchRows(game: Game, cx, cw, y: int32, maxRows: int): int32 =
  ## The run's patches in up to maxRows rows; when they don't all fit the last
  ## row becomes "+N more" (the pause menu lists them all). Charge patches come
  ## first, so a READY / USED tag never hides behind the overflow row, then the
  ## rest; each group newest first. The newest install breathes.
  let n = runPatchCount(game)
  if n == 0 or maxRows <= 0:
    return y
  let relics = game.rogueliteRun.relics
  var order: seq[RogueliteRelicType]
  for i in countdown(n - 1, 0):
    if relics[i].relicType in ChargePatches: order.add relics[i].relicType
  for i in countdown(n - 1, 0):
    if relics[i].relicType notin ChargePatches: order.add relics[i].relicType
  let newest = relics[^1].relicType
  let shown = if n > maxRows: max(0, maxRows - 1) else: n
  var ry = y
  for i in 0..<shown:
    drawPatchRow(game, order[i], cx, cw, ry, fresh = order[i] == newest, shade = i mod 2 == 1)
    ry += ProcessRowH
  if shown < n:
    let more = "+" & $(n - shown) & " " & t(tkHUDMore)
    drawShadowText(more, cx + 22, ry + (ProcessRowH - 10) div 2, 10, DockDim)
    ry += ProcessRowH
  ry

# ---------------------------------------------------------------------------
# Wave block (classic: inside the panel; widescreen: right-dock objective card)

proc drawWaveBody(game: Game, cx, cw, y: int32): int32 =
  ## Wave number, what is left of it, and the march to the next boss: one cell
  ## per wave of the boss block, the last one being the boss wave.
  let bossFight = game.bossWaveManager.active
  let collect = game.bossWaveManager.coinActive and not bossFight
  let pulse = 0.5'f32 + 0.5'f32 * sin(game.time * 6.0'f32)

  let num = (if game.currentWave < 10: "0" else: "") & $game.currentWave
  let numColor = if bossFight: Color(r: 255, g: 95, b: 95, a: 255)
                 else: Color(r: 130, g: 255, b: 160, a: 255)
  drawShadowText(num, cx, y, 30, numColor)
  let numW = measureText(num, 30)
  let sideW = cw - numW - 8

  # Right of the number: what the wave wants from you right now.
  let remaining = game.enemies.len + game.waveEnemiesRemaining
  let remFrac = if game.waveEnemiesTotal > 0:
                  remaining.float32 / game.waveEnemiesTotal.float32
                else: 0.0'f32
  let threat = if remFrac > 0.6'f32: Color(r: 255, g: 70, b: 60, a: 255)
               elif remFrac > 0.3'f32: Color(r: 255, g: 165, b: 0, a: 255)
               else: Color(r: 100, g: 225, b: 125, a: 255)
  if bossFight:
    let s = t(tkGameBossFight)
    let size = bestFitFontSize(s, sideW, 10, 8)
    drawShadowText(s, cx + cw - measureText(s, size), y + 11, size,
                   Color(r: 255, g: uint8(70.0'f32 + 90.0'f32 * pulse), b: 80, a: 255))
  elif collect:
    let s = "[$] " & t(tkGameCollect).toUpperAscii
    let size = bestFitFontSize(s, sideW, 10, 8)
    drawShadowText(s, cx + cw - measureText(s, size), y + 11, size,
                   Color(r: 255, g: 215, b: 0, a: uint8(170.0'f32 + 85.0'f32 * pulse)))
  elif game.waveInProgress:
    let count = $remaining
    let cw20 = measureText(count, 20)
    drawShadowText(count, cx + cw - cw20, y, 20, threat)
    let caption = t(tkGameLeft).toUpperAscii
    let capSize = bestFitFontSize(caption, sideW, 10, 8)
    drawShadowText(caption, cx + cw - measureText(caption, capSize), y + 21, capSize, DockDim)

  # Enemies-left bar (a boss owns the right dock's boss card instead).
  let barY = y + 34
  if game.waveInProgress and not bossFight:
    drawDockBar(cx, barY, cw, 6, remFrac, threat, withAlpha(DockAccent, 90))
  else:
    drawDockBar(cx, barY, cw, 6, if bossFight: 1.0'f32 else: 0.0'f32,
                Color(r: 255, g: 80, b: 80, a: uint8(90.0'f32 + 80.0'f32 * pulse)),
                withAlpha(DockAccent, 60))

  # Boss track.
  let trackY = y + 46
  let slot = clamp(BossWaveInterval - 1 - game.wavesUntilBoss, 0, BossWaveInterval - 1)
  const cellW = 13'i32
  const cellH = 7'i32
  const cellGap = 3'i32
  for i in 0..<BossWaveInterval:
    let bx = cx + i.int32 * (cellW + cellGap)
    let isBossCell = i == BossWaveInterval - 1
    let base = if isBossCell: Color(r: 255, g: 90, b: 70, a: 255) else: DockAccent
    if i < slot:
      drawRectangle(bx, trackY, cellW, cellH, withAlpha(base, 170))
    elif i == slot:
      drawRectangle(bx, trackY, cellW, cellH, withAlpha(base, uint8(120.0'f32 + 120.0'f32 * pulse)))
    else:
      drawRectangle(bx, trackY, cellW, cellH, DockTrackBg)
    drawRectangleLines(Rectangle(x: bx.float32, y: trackY.float32, width: cellW.float32,
                                 height: cellH.float32), 1, withAlpha(base, 150))
  let trackText = if game.wavesUntilBoss <= 0: t(tkHUDBossWave)
                  else: t(tkHUDBossInWaves).replace("$1", $game.wavesUntilBoss)
  let trackX = cx + BossWaveInterval.int32 * (cellW + cellGap) + 3
  let trackSize = bestFitFontSize(trackText, cx + cw - trackX, 10, 8)
  drawShadowText(trackText, cx + cw - measureText(trackText, trackSize), trackY - 1, trackSize,
                 if game.wavesUntilBoss <= 0: Color(r: 255, g: 130, b: 90, a: 255) else: DockDim)
  y + WaveBodyH

proc drawWaveDockCard*(game: Game, x, y: int32): int32 =
  ## Widescreen right-dock objective card for wave mode. Returns the y below it.
  let h = DockHeaderH + 6 + WaveBodyH + 2
  let accent = if game.bossWaveManager.active: Color(r: 255, g: 90, b: 90, a: 255) else: DockAccent
  drawDockCard(x, y, DockCardW, h, accent)
  let top = drawDockHeader(x, y, DockCardW, t(tkGameWave).toUpperAscii, accent)
  discard drawWaveBody(game, x + DockPad, DockContentW, top + 6)
  y + h

# ---------------------------------------------------------------------------
# Roguelite sector block: the sector's root folder, the breadcrumb, a progress
# track to SERVICE with its FOLDER n/N caption, LV/XP (classic only --
# widescreen shows it in the left dock) and labelled heat / shards / cores
# rows. The run's patches are listed by name in their own card under this one
# (drawPatchDockCard; classic: right below this block). rogueliteBlockHeight and
# drawRogueliteBlock share the row constants below, so the height budget can
# never drift from the draw.
#
# Everything here is drawn at 10px or larger: raylib clamps the default font to
# 10px, so a bestFitFontSize floor below that never shrinks anything and a
# too-long line just runs off the card.

const
  RogueHudTitleH = 12'i32       ## classic only: DEEP RECOVERY // SECTOR 2/4
  RogueHudNameH = 25'i32        ## folder glyph + sector root at 20px
  RogueHudPathH = 14'i32
  RogueHudTrackH = 16'i32
  RogueHudCaptionH = 13'i32     ## FOLDER 2/5 .......... SERVICE
  RogueHudStatH = 22'i32        ## icon + label + 20px value

  RogueHeatColor = Color(r: 255, g: 150, b: 80, a: 255)
  RogueShardColor = Color(r: 90, g: 225, b: 255, a: 255)
  RogueCoreColor = Color(r: 200, g: 160, b: 255, a: 255)
  RogueServiceColor = Color(r: 255, g: 90, b: 70, a: 255)

proc rogueliteStatRows(run: RogueliteRun): int32 =
  ## Heat and shards always; cores only once the run has earned one.
  if run.coresEarned > 0: 3 else: 2

proc rogueliteBlockHeight(game: Game, withTitle, withLevel: bool): int32 =
  result = RogueHudNameH + RogueHudPathH + RogueHudTrackH + RogueHudCaptionH +
           DividerH + rogueliteStatRows(game.rogueliteRun) * RogueHudStatH
  if withTitle: result += RogueHudTitleH
  if withLevel: result += LevelRowH

proc rogueliteTitle(run: RogueliteRun, maxW: int32): string =
  ## DEEP RECOVERY // SECTOR 2/4, or just SECTOR 2/4 when the whole thing
  ## would overflow `maxW` (Spanish in an endless loop does).
  result = t("roguelite_sector_upper") & " " & $run.floorNumber & "/" & $RogueliteFloorsToWin
  if run.endlessLoop > 0:
    result &= "  +" & $run.endlessLoop
  let full = t("roguelite_hud_title") & " // " & result
  if measureText(full, 10) <= maxW:
    result = full

proc drawFolderGlyph(x, y: int32, color: Color) =
  ## A 16x13 folder: a tab on the top-left over a filled body.
  drawRectangle(x, y, 7, 3, color)
  drawRectangle(x, y + 2, 16, 11, withAlpha(color, 90))
  drawRectangleLines(Rectangle(x: x.float32, y: (y + 2).float32, width: 16, height: 11), 1, color)
  drawRectangle(x + 1, y + 5, 14, 1, withAlpha(color, 150))

proc drawSectorName(floor: DungeonFloor, cx, cw, y: int32) =
  ## The sector's root folder in big type: the one thing a glance must find.
  let accent = themeAccent(floor.theme)
  drawFolderGlyph(cx, y + 4, accent)
  let name = themeFolder(floor.theme)
  drawShadowText(name, cx + 22, y, bestFitFontSize(name, cw - 22, 20, 10), accent)

proc drawSectorPath(floor: DungeonFloor, cx, cw, y: int32) =
  ## Breadcrumb, trimmed from the LEFT so the folder you are in stays visible.
  var path = sectorPath(floor)
  if measureText(path, 10) > cw:
    # Drop whole leading folders, never half a name.
    var tail = path
    while measureText(".." & tail, 10) > cw:
      let cut = tail.find('\\', 1)
      if cut < 0: break
      tail = tail[cut .. ^1]
    path = ".." & tail
  drawShadowText(path, cx, y, 10, withAlpha(themeAccent(floor.theme), 215))

proc drawSectorTrack(game: Game, floor: DungeonFloor, cx, cw, y: int32) =
  ## One cell per reward folder, then a red SERVICE cell, spread over the full
  ## width, with FOLDER n/N under the left end and SERVICE under the right.
  let run = game.rogueliteRun
  let layers = sectorRewardLayers(floor)
  let current = if floor.rooms.len > 0: floor.rooms[floor.rooms.high].layer else: 0
  let atBoss = current > layers
  let pulse = 0.5'f32 + 0.5'f32 * sin(game.time * 5.0'f32)

  const cellH = 12'i32
  const gap = 3'i32
  let cells = layers.int32 + 1
  let cellW = max(4'i32, (cw - gap * (cells - 1)) div cells)
  for i in 0..<cells:
    let bx = cx + i * (cellW + gap)
    # The last cell absorbs the rounding so the track ends flush with the card.
    let w = if i == cells - 1: cx + cw - bx else: cellW
    let rect = Rectangle(x: bx.float32, y: (y + 1).float32, width: w.float32, height: cellH.float32)
    let layer = i + 1
    if layer > layers:
      # SERVICE
      drawRectangle(rect, if atBoss: withAlpha(RogueServiceColor, uint8(110.0'f32 + 130.0'f32 * pulse))
                          else: DockTrackBg)
      drawRectangleLines(rect, 1, withAlpha(RogueServiceColor, if atBoss: 255 else: 170))
    else:
      if layer < current or (layer == current and currentDungeonRoom(run).cleared):
        drawRectangle(rect, withAlpha(DockAccent, 200))
        drawRectangle(bx, y + 1, w, 1, Color(r: 255, g: 255, b: 255, a: 70))
      elif layer == current:
        drawRectangle(rect, Color(r: 255, g: 255, b: 255, a: uint8(90.0'f32 + 150.0'f32 * pulse)))
      else:
        drawRectangle(rect, DockTrackBg)
      drawRectangleLines(rect, 1, withAlpha(DockAccent, 170))

  let capY = y + RogueHudTrackH
  let folder = t("roguelite_hud_folder").replace("$1", $clamp(current, 0, layers))
                                         .replace("$2", $layers)
  drawShadowText(folder, cx, capY, 10, DockInk)
  let service = t("room_reward_service")
  drawShadowText(service, cx + cw - measureText(service, 10), capY, 10,
                 if atBoss: Color(r: 255, g: uint8(90.0'f32 + 100.0'f32 * pulse), b: 80, a: 255)
                 else: withAlpha(Color(r: 255, g: 140, b: 115, a: 255), 210))

proc drawRogueStatRow(cx, cw, y: int32, icon: CurrencyIconType, label, value: string,
                      color: Color): int32 =
  ## Icon, a small label, and the value in big type on the right.
  drawCurrencyIcon(cx + 7, y + RogueHudStatH div 2, 15, icon)
  let valueSize = bestFitFontSize(value, cw - 18 - 6 - measureText(label, 10), 20, 10)
  let valueW = measureText(value, valueSize)
  drawShadowText(fitWithEllipsis(label, cw - 18 - 6 - valueW, 10), cx + 18,
                 y + (RogueHudStatH - 10) div 2, 10, DockDim)
  drawShadowText(value, cx + cw - valueW, y + (RogueHudStatH - valueSize) div 2, valueSize, color)
  y + RogueHudStatH

proc drawRogueliteBlock(game: Game, cx, cw, y: int32, withTitle, withLevel: bool): int32 =
  let run = game.rogueliteRun
  var yOffset = y

  if withTitle:
    drawShadowText(rogueliteTitle(run, cw), cx, yOffset, 10, ACCENT_COLOR)
    yOffset += RogueHudTitleH

  let floor = run.floor
  if not floor.isNil:
    drawSectorName(floor, cx, cw, yOffset)
    drawSectorPath(floor, cx, cw, yOffset + RogueHudNameH)
    drawSectorTrack(game, floor, cx, cw, yOffset + RogueHudNameH + RogueHudPathH)
  yOffset += RogueHudNameH + RogueHudPathH + RogueHudTrackH + RogueHudCaptionH

  if withLevel:
    yOffset = drawLevelRow(game, cx, cw, yOffset)

  drawDivider(cx, cw, yOffset)
  yOffset += DividerH
  yOffset = drawRogueStatRow(cx, cw, yOffset, ciHeat, t("roguelite_hud_heat"),
                             $run.heat, RogueHeatColor)
  yOffset = drawRogueStatRow(cx, cw, yOffset, ciDataShards, t("roguelite_hud_shards"),
                             "+" & $run.shardsEarned, RogueShardColor)
  if run.coresEarned > 0:
    yOffset = drawRogueStatRow(cx, cw, yOffset, ciCore, t("roguelite_hud_cores"),
                               "+" & $run.coresEarned, RogueCoreColor)
  yOffset

proc drawRogueliteDockCard*(game: Game, x, y: int32): int32 =
  ## Widescreen right-dock objective card for a dungeon run. Returns the y below it.
  let run = game.rogueliteRun
  if run.isNil:
    return y
  let h = DockHeaderH + 6 + rogueliteBlockHeight(game, false, false) + 2
  drawDockCard(x, y, DockCardW, h)
  var right = $run.floorNumber & "/" & $RogueliteFloorsToWin
  if run.endlessLoop > 0:
    right &= " +" & $run.endlessLoop
  let title = t("roguelite_sector_upper")
  let top = drawDockHeader(x, y, DockCardW, title, DockAccent, right, DockInk)
  discard drawRogueliteBlock(game, x + DockPad, DockContentW, top + 6,
                             withTitle = false, withLevel = false)
  y + h

proc drawPatchDockCard*(game: Game, x, y, bottom, floorBottom: int32): int32 =
  ## Widescreen right-dock PATCHES card, stacked under the SECTOR card: the
  ## run's patches by name, in as many rows as fit above `bottom` (the caller
  ## keeps the boss cards' room below that). When that leaves nothing, the
  ## charge patches (listed first, see drawPatchRows) may still reach down to
  ## `floorBottom`, so their READY / USED tag survives a cramped boss fight.
  ## The left dock is the power-ups'. Returns the y below the card, or `y`
  ## when there is nothing to draw.
  let n = runPatchCount(game)
  if n == 0:
    return y
  const chrome = DockHeaderH + 6'i32
  template rowsAbove(limit: int32): int = max(0, int((limit - y - chrome) div ProcessRowH))
  var charged = 0
  for relic in game.rogueliteRun.relics:
    if relic.relicType in ChargePatches: inc charged
  let essential = if charged == 0: 0
                  else: min(n, charged + (if n > charged: 1 else: 0))
  var rows = min(n, rowsAbove(bottom))
  if rows < essential and rowsAbove(floorBottom) >= essential:
    rows = essential
  # A lone row would only say "+N more": not worth squeezing the boss for.
  if rows <= 0 or (rows == 1 and n > 1):
    return y
  let h = chrome + rows.int32 * ProcessRowH
  drawDockCard(x, y, DockCardW, h, PatchCardAccent)
  let listTop = drawDockHeader(x, y, DockCardW, t("roguelite_hud_patches"), PatchCardAccent,
                               $n, DockInk)
  discard drawPatchRows(game, x + DockPad, DockContentW, listTop + 3, rows)
  y + h

# ---------------------------------------------------------------------------
# Widescreen left dock

const
  StatusCardPadTop = 6'i32
  StatusCardPadBottom = 3'i32

proc statusCardHeight*(game: Game): int32 =
  DockHeaderH + StatusCardPadTop + HpBlockH +
    (if modeShowsLevel(game): LevelRowH else: 0) +
    ResourceRowH + DashRowH + StatusCardPadBottom

proc drawPlayerDock*(game: Game, x, top, bottom: int32) =
  ## The left dock's STATUS card (pinned to `top`) and PROCESSES card (filling
  ## down to `bottom`, which the caller moves up to make room for whatever it
  ## docks under it). The left dock is the power-ups'; a roguelite run's
  ## patches list in the right dock (drawPatchDockCard).
  let cx = x + DockPad
  let cw = DockContentW
  let statusH = statusCardHeight(game)
  lastStatusPanelRect = Rectangle(x: x.float32, y: top.float32,
                                  width: DockCardW.float32, height: statusH.float32)
  lastLevelBarRect = Rectangle()  # re-published below only by the modes that level

  drawDockCard(x, top, DockCardW, statusH)
  var y = drawDockHeader(x, top, DockCardW, t(tkGameStatus))
  y += StatusCardPadTop
  y = drawHpBlock(game, cx, cw, y)
  if modeShowsLevel(game):
    y = drawLevelRow(game, cx, cw, y)
  y = drawResourceTiles(game, cx, cw, y)
  y = drawDashRow(game, cx, cw, y)

  # PROCESSES: as many rows as the band has room for.
  let n = game.player.powerUps.len
  if n == 0:
    return
  let procTop = top + statusH + DockGap
  let avail = bottom - procTop - DockHeaderH - 6
  let maxRows = int(avail div ProcessRowH)
  if maxRows <= 0:
    return
  let rows = min(n, maxRows)
  let procH = DockHeaderH + 3 + rows.int32 * ProcessRowH + 3
  let accent = Color(r: 180, g: 110, b: 255, a: 255)
  drawDockCard(x, procTop, DockCardW, procH, accent)
  let listTop = drawDockHeader(x, procTop, DockCardW, t(tkHUDProcesses), accent,
                               $n, Color(r: 215, g: 185, b: 255, a: 255))
  discard drawProcessRows(game, cx, cw, listTop + 3, rows)

proc shortKeyLabel(k: KeyboardKey): string =
  ## Keycap text short enough for a half-width dock cell.
  case k
  of KeyboardKey.LeftShift: "LShift"
  of KeyboardKey.RightShift: "RShift"
  of KeyboardKey.LeftControl: "LCtrl"
  of KeyboardKey.RightControl: "RCtrl"
  of KeyboardKey.LeftAlt: "LAlt"
  of KeyboardKey.RightAlt: "RAlt"
  of KeyboardKey.Escape: "Esc"
  of KeyboardKey.Enter: "Enter"
  else: keyboardKeyLabel(k)

proc bindLabel(action: KeyAction): string =
  if globalSettings.isNil: return "---"
  if isGamepadActive(): gamepadBindLabel(globalSettings.gamepadBinds[action])
  else: shortKeyLabel(globalSettings.keybinds[action])

proc drawKeyHint(x, y, w: int32, key, label: string, active: bool, keyMaxW: int32 = 0) =
  ## A keycap followed by what it does, fitted into `w`. The keycap may take up
  ## to `keyMaxW` (half the cell when 0) before its text shrinks.
  let keySize = bestFitFontSize(key, (if keyMaxW > 0: keyMaxW else: w div 2) - 8, 10, 7)
  let capW = measureText(key, keySize) + 8
  let rim = if active: withAlpha(DockAccent, 170) else: withAlpha(DockDim, 90)
  drawRectangle(x, y, capW, 13, Color(r: 22, g: 36, b: 52, a: 245))
  drawRectangle(x, y + 12, capW, 1, rim)
  drawRectangleLines(Rectangle(x: x.float32, y: y.float32, width: capW.float32, height: 13), 1, rim)
  drawText(key, x + 4, y + 2 + (10 - keySize) div 2, keySize,
           if active: DockInk else: DockDim)
  let labelW = w - capW - 4
  if labelW > 8:
    drawShadowText(label, x + capW + 4, y + 2, bestFitFontSize(label, labelW, 10, 7),
                   if active: Color(r: 190, g: 210, b: 225, a: 255) else: withAlpha(DockDim, 170))

type KeyHint = tuple[key, label: string, active: bool]

proc controlHints(game: Game): array[4, KeyHint] =
  ## Wall, dash, ability, pause -- the keys the HUD reminds the player of.
  var hasAbility = false
  for pu in game.player.powerUps:
    if allPowerUpDefs[pu.powerType].inLegendaryPanel:
      hasAbility = true
      break
  let pause = if isGamepadActive(): "Start" else: "Esc"
  [(bindLabel(kaPlaceWall), t(tkHUDKeyWall), game.player.walls > 0),
   (bindLabel(kaDash), t(tkHUDKeyDash), true),
   (bindLabel(kaLegendary), t(tkHUDKeyAbility), hasAbility),
   (pause, t(tkHUDKeyPause), true)]

proc keyHintWidth(h: KeyHint): int32 =
  ## Natural width of a hint: keycap + 4 + label.
  measureText(h.key, 10) + 8 + 4 + measureText(h.label, 10) + 2

proc wallPlacementText(game: Game): string =
  t(tkGameWallPlace) & "  (" & $game.player.walls & " " & t(tkGameWallPlaceRemaining) & ")"

proc drawControlsDockCard*(game: Game, x, bottom: int32): int32 =
  ## Bottom-anchored key hints for the left dock, read from the live bindings
  ## (keyboard or pad, whichever is active) so a rebound control is shown under
  ## its real key. Two to a row when they fit, otherwise one per row. While a
  ## wall is being placed it turns into the placement prompt. Returns the
  ## card's top y.
  let cx = x + DockPad
  let cw = DockContentW
  if game.wallPlacementMode and game.player.walls > 0:
    let lines = wrapTextLines(wallPlacementText(game), cw, 10)
    let h = 8 + lines.len.int32 * 13 + 4
    let y = bottom - h
    let green = Color(r: 120, g: 225, b: 140, a: 255)
    drawDockCard(x, y, DockCardW, h, green)
    var ly = y + 7
    for ln in lines:
      drawShadowText(ln, cx, ly, 10, Color(r: 180, g: 235, b: 185, a: 255))
      ly += 13
    return y

  const rowPitch = 17'i32
  const colGap = 6'i32
  let hints = controlHints(game)
  let leftW = max(keyHintWidth(hints[0]), keyHintWidth(hints[2]))
  let rightW = max(keyHintWidth(hints[1]), keyHintWidth(hints[3]))
  let paired = leftW + colGap + rightW <= cw
  let rows = if paired: 2'i32 else: 4'i32
  let h = 6 + rows * rowPitch + 2
  let y = bottom - h
  drawDockCard(x, y, DockCardW, h)
  if paired:
    let colW = (cw - colGap) div 2
    # Split the width in proportion to need, so a long label keeps its room.
    let lw = max(leftW, min(colW, cw - colGap - rightW))
    for i, hint in hints:
      let col = i mod 2
      let hx = if col == 0: cx else: cx + lw + colGap
      let hw = if col == 0: lw else: cw - lw - colGap
      drawKeyHint(hx, y + 6 + (i div 2).int32 * rowPitch, hw, hint.key, hint.label,
                  hint.active, keyMaxW = hw)
  else:
    for i, hint in hints:
      drawKeyHint(cx, y + 6 + i.int32 * rowPitch, cw, hint.key, hint.label, hint.active,
                  keyMaxW = cw div 2)
  y

proc drawControlsStrip*(game: Game, centerX, y: int32) =
  ## Classic layout: the same live key hints as the dock card, as one row
  ## centred on `centerX`, or the wall-placement prompt while placing.
  if game.wallPlacementMode and game.player.walls > 0:
    let text = wallPlacementText(game)
    let w = measureText(text, 20)
    drawShadowText(text, centerX - w div 2, y - 3, 20, Color(r: 180, g: 235, b: 185, a: 255))
    return
  const gap = 14'i32
  let hints = controlHints(game)
  var total = -gap
  for h in hints:
    total += keyHintWidth(h) + gap
  var x = centerX - total div 2
  for h in hints:
    let w = keyHintWidth(h)
    drawKeyHint(x, y, w, h.key, h.label, h.active, keyMaxW = w)
    x += w + gap

# ---------------------------------------------------------------------------
# Classic floating panel

proc classicListRows(n: int): int =
  ## The newest few, plus a "+N more" row once there are more than that.
  if n > COMBINED_MAX_POWERUPS_VISIBLE: COMBINED_MAX_POWERUPS_VISIBLE + 1 else: n

proc drawHUDPanelContent(game: Game, panelX, panelY, panelW: int32) =
  ## The classic panel body below its title bar. No input handling lives here.
  let cx = panelX + COMBINED_PANEL_PADDING + 4
  let cw = panelW - (COMBINED_PANEL_PADDING + 4) * 2
  let wave = game.mode == gmWaveBased
  let rogue = game.mode == gmRoguelite and game.rogueliteRun != nil
  # Survival shows its XP bar in the top-centre card in this layout.
  let levelRow = wave

  var totalH = COMBINED_PANEL_PADDING + COMBINED_TITLE_HEIGHT + 6 + HpBlockH +
               (if levelRow: LevelRowH else: 0) + ResourceRowH + DashRowH
  if wave:
    totalH += DividerH + WaveBodyH
  if rogue:
    totalH += DividerH + rogueliteBlockHeight(game, true, true)
  let procRows = classicListRows(game.player.powerUps.len)
  if procRows > 0:
    totalH += DividerH + ProcessHeaderH + procRows.int32 * ProcessRowH
  let patchRows = classicListRows(runPatchCount(game))
  if patchRows > 0:
    totalH += DividerH + ProcessHeaderH + patchRows.int32 * ProcessRowH
  totalH += 4

  lastStatusPanelRect = Rectangle(x: panelX.float32, y: panelY.float32,
                                  width: panelW.float32, height: totalH.float32)
  lastLevelBarRect = Rectangle()  # re-published below only by the modes that level

  drawRectangle(panelX, panelY, panelW, totalH, Color(r: 5, g: 13, b: 22, a: 150))
  drawRectangle(panelX, panelY, 2, totalH, Color(r: 0, g: 220, b: 255, a: 180))
  drawRectangleLines(Rectangle(x: panelX.float32, y: panelY.float32,
                               width: panelW.float32, height: totalH.float32),
                     1, Color(r: 0, g: 220, b: 255, a: 80))

  var y = panelY + COMBINED_PANEL_PADDING + COMBINED_TITLE_HEIGHT + 6
  y = drawHpBlock(game, cx, cw, y)
  if levelRow:
    y = drawLevelRow(game, cx, cw, y)
  y = drawResourceTiles(game, cx, cw, y)
  y = drawDashRow(game, cx, cw, y)

  if wave:
    drawDivider(cx, cw, y)
    y = drawWaveBody(game, cx, cw, y + DividerH)
  if rogue:
    drawDivider(cx, cw, y)
    y = drawRogueliteBlock(game, cx, cw, y + DividerH, withTitle = true, withLevel = true)

  # Classic has no right column, so the patches ride with the sector block they
  # sit under in widescreen, above the power-ups.
  if patchRows > 0:
    drawDivider(cx, cw, y)
    y += DividerH
    drawShadowText(t("roguelite_hud_patches") & " [" & $runPatchCount(game) & "]", cx, y, 10,
                   PatchCardAccent)
    y += ProcessHeaderH
    y = drawPatchRows(game, cx, cw, y, patchRows)

  if procRows > 0:
    drawDivider(cx, cw, y)
    y += DividerH
    drawShadowText(processHeaderText(game), cx, y, 10, Color(r: 200, g: 180, b: 255, a: 255))
    y += ProcessHeaderH
    discard drawProcessRows(game, cx, cw, y, procRows)

proc drawClassicTitleBar(x, y: int32, minimized: bool) =
  drawRectangle(x + 2, y + COMBINED_PANEL_PADDING, COMBINED_PANEL_WIDTH - 2,
                COMBINED_TITLE_HEIGHT, HEADER_BG_COLOR)
  drawShadowText(t(tkGameStatus), x + COMBINED_PANEL_PADDING + 4,
                 y + COMBINED_PANEL_PADDING + 4, 10, ACCENT_COLOR)
  let iconX = x + COMBINED_PANEL_WIDTH - COMBINED_PANEL_PADDING - 12
  if minimized:
    # Maximize glyph (square)
    drawRectangleLines(Rectangle(x: iconX.float32, y: (y + COMBINED_PANEL_PADDING + 4).float32,
                                 width: 10, height: 10), 1, ACCENT_COLOR)
  else:
    # Minimize glyph (horizontal line)
    let iconY = y + COMBINED_PANEL_PADDING + 9
    drawLine(Vector2(x: iconX.float32, y: iconY.float32),
             Vector2(x: (iconX + 10).float32, y: iconY.float32), 2, ACCENT_COLOR)

proc drawCombinedHUDPanel*(game: Game, x, y: int32) =
  ## Classic floating STATUS panel (draggable by its title, minimizable).
  # Keep the remembered position inside the layer's logical viewport. Changing
  # the UI scale resizes that viewport under a panel that was dragged to fit the
  # old one, so this runs every frame rather than only while dragging.
  leftPanelPos.x = clamp(leftPanelPos.x, 0,
                         max(0'f32, (getVirtualScreenWidth() - COMBINED_PANEL_WIDTH).float32))
  leftPanelPos.y = clamp(leftPanelPos.y, 0,
                         max(0'f32, (getVirtualScreenHeight() - 50).float32))

  let panelX = leftPanelPos.x.int32
  let panelY = leftPanelPos.y.int32

  # Handle dragging
  let mousePos = getVirtualMousePosition()
  let headerHeight = (COMBINED_PANEL_PADDING + COMBINED_TITLE_HEIGHT).float32
  let headerRect = Rectangle(x: panelX.float32, y: panelY.float32,
                             width: COMBINED_PANEL_WIDTH.float32, height: headerHeight)

  if isPointerPressed() and checkCollisionPointRec(mousePos, headerRect):
    # Right side of the header is the minimize button.
    let minimizeButtonX = panelX + COMBINED_PANEL_WIDTH - COMBINED_PANEL_PADDING - 12
    let minimizeButtonRect = Rectangle(
      x: minimizeButtonX.float32,
      y: (panelY + COMBINED_PANEL_PADDING).float32,
      width: 16,
      height: COMBINED_TITLE_HEIGHT.float32
    )
    if checkCollisionPointRec(mousePos, minimizeButtonRect):
      leftPanelMinimized = not leftPanelMinimized
    else:
      leftPanelDragging = true
      leftPanelDragOffset = Vector2(x: mousePos.x - panelX.float32,
                                    y: mousePos.y - panelY.float32)

  if leftPanelDragging:
    if isPointerDown():
      leftPanelPos = Vector2(x: mousePos.x - leftPanelDragOffset.x,
                             y: mousePos.y - leftPanelDragOffset.y)
      # Clamp to the layer's logical viewport (which is the world size at the
      # default UI scale, and smaller/larger at any other).
      leftPanelPos.x = clamp(leftPanelPos.x, 0,
                             max(0'f32, (getVirtualScreenWidth() - COMBINED_PANEL_WIDTH).float32))
      leftPanelPos.y = clamp(leftPanelPos.y, 0,
                             max(0'f32, (getVirtualScreenHeight() - 50).float32))
    else:
      leftPanelDragging = false

  let finalX = leftPanelPos.x.int32
  let finalY = leftPanelPos.y.int32

  if leftPanelMinimized:
    let h: int32 = COMBINED_PANEL_PADDING + COMBINED_TITLE_HEIGHT
    lastStatusPanelRect = Rectangle(x: finalX.float32, y: finalY.float32,
                                    width: COMBINED_PANEL_WIDTH.float32, height: h.float32)
    lastStatsRowRect = Rectangle()
    lastDashRowRect = Rectangle()
    lastLevelBarRect = Rectangle()
    drawRectangle(finalX, finalY, COMBINED_PANEL_WIDTH, h, Color(r: 5, g: 13, b: 22, a: 150))
    drawRectangle(finalX, finalY, 2, h, Color(r: 0, g: 220, b: 255, a: 180))
    drawRectangleLines(Rectangle(x: finalX.float32, y: finalY.float32,
                                 width: COMBINED_PANEL_WIDTH.float32, height: h.float32),
                       1, Color(r: 0, g: 220, b: 255, a: 80))
    drawClassicTitleBar(finalX, finalY, minimized = true)
    return

  drawHUDPanelContent(game, finalX, finalY, COMBINED_PANEL_WIDTH)
  drawClassicTitleBar(finalX, finalY, minimized = false)
