# SURVIVAL MODE - Time Survival specific logic

import raylib, random, math
import types, enemy, particle_pool, localization, utils

# During a boss fight difficulty is frozen at the boss's spawn value (an integer);
# introduction thresholds are also integers, so spawning at `difficulty - 0.5`
# guarantees no enemy type debuts mid-boss.
const SurvivalBossRosterEpsilon = 0.5'f32

proc spawnSurvivalEnemies*(game: Game) =
  ## Time-based enemy spawning for Survival mode.
  ## Spawn rate scales with difficulty, every 15 s a brief "wave burst" fires
  ## extra enemies (60 % chance of a double-spawn while waveProgress > 0.6).
  ## Boss waves double the spawn rate to maintain pressure.

  # Spawn-rate curve: slows logarithmically as difficulty climbs
  let baseSpawnRate =
    if game.difficulty < 1.5:
      3.0
    elif game.difficulty < 3.0:
      2.3 / (1.0 + (game.difficulty - 1.5) * 0.3)
    elif game.difficulty < 6.0:
      1.8 / (1.0 + (game.difficulty - 3.0) * 0.25)
    elif game.difficulty < 9.0:
      1.4 / (1.0 + (game.difficulty - 6.0) * 0.15)
    elif game.difficulty < 13.0:
      1.2 / (1.0 + (game.difficulty - 9.0) * 0.1)
    else:
      max(0.9, 1.0 / (1.0 + (game.difficulty - 13.0) * 0.05))

  # Every 15 s the last 40 % of the cycle is a "wave burst" with tighter rate.
  # Keyed off survivalTime so the cycle pauses with everything else during a boss.
  let waveSpawnRate  = baseSpawnRate * 0.7
  let waveProgress   = (game.survivalTime mod 15.0) / 15.0
  let isWaveActive   = waveProgress > 0.6

  var currentSpawnRate = if isWaveActive: waveSpawnRate else: baseSpawnRate
  # Double spawn pressure while a boss is alive
  if game.bossWaveManager.active:
    currentSpawnRate = currentSpawnRate * 2.0

  if game.spawnTimer > currentSpawnRate:
    # While a boss is alive, lock the type roster to what was already spawning so no
    # new enemy type debuts mid-boss; stats still scale with the live difficulty.
    let rosterDiff = if game.bossWaveManager.active:
      game.difficulty - SurvivalBossRosterEpsilon else: -1.0'f32
    let newEnemy = spawnEnemy(game.screenWidth, game.screenHeight, game.difficulty, game, rosterDiff)
    makeElite(newEnemy, (game.difficulty * 2).int)   # use difficulty as wave equivalent
    game.enemies.add(newEnemy)
    game.spawnTimer = 0

    # Extra spawn during wave burst (60 % chance, but not during boss fight)
    if isWaveActive and rand(100) < 60 and not game.bossWaveManager.active:
      let waveEnemy = spawnEnemy(game.screenWidth, game.screenHeight, game.difficulty, game)
      makeElite(waveEnemy, (game.difficulty * 2).int)
      game.enemies.add(waveEnemy)

    # Entrance particle burst for the latest enemy
    let newest = game.enemies[^1]
    for i in 0..<60:
      let angle = i.float32 * 0.1
      let dist  = i.float32 * 3.0
      spawnExplosionPooled(game.particlePool,
                           newest.pos.x + cos(angle) * dist,
                           newest.pos.y + sin(angle) * dist,
                           newest.color, 3)

# Fixed vertical footprint of the survival HUD card. Must mirror the layout
# constants inside drawSurvivalHUD (padY + timerSize + vGap + barH + padY).
# game.nim uses SurvivalHudBottomY to start boss health bars below the timer.
const
  SurvivalHudPanelY*: int32 = 8
  SurvivalHudBottomY*: int32 = SurvivalHudPanelY + 9 + 30 + 7 + 12 + 9

proc drawSurvivalHUD*(game: Game, screenWidth, screenHeight: int32, alignRight: bool = false) =
  ## Top-center survival HUD: a single rounded "OS card" holding the survived-time
  ## stopwatch on top and the run level + XP progress bar below it (Vampire-
  ## Survivors-style leveling: kills fill the bar, which opens a power-up draft).
  ## The "WAVE INCOMING!" banner is drawn just under the card during the burst
  ## window of every 15-second cycle (only when no boss is active).

  # OS-accent palette shared across the card so it reads as one integrated panel.
  const xpFill    = Color(r: 90,  g: 255, b: 170, a: 235)   # XP green
  const inkShadow = Color(r: 0,   g: 0,   b: 0,   a: 140)

  # The survival clock pauses during a boss fight (survivalTime stops accumulating).
  # Gray the stopwatch out and show a pause glyph so the frozen clock reads as
  # intentional rather than a bug. `accent` follows suit so the whole row dims.
  # Matches the clock-pause condition in updateGame (boss alive OR its reward coin
  # still uncollected), so the gray-out/pause glyph tracks the frozen clock exactly.
  let bossActive = game.bossWaveManager.active or game.bossWaveManager.coinActive
  let accent     = if bossActive: Color(r: 120, g: 140, b: 150, a: 255)
                   else:          Color(r: 0,   g: 200, b: 255, a: 255)  # desktop cyan
  let digitColor = if bossActive: Color(r: 150, g: 165, b: 175, a: 255)
                   else:          Color(r: 225, g: 246, b: 255, a: 255)

  # --- Layout (centred horizontally near the top) -------------------------
  const padX: int32 = 16
  const padY: int32 = 9
  const vGap: int32 = 7          # space between the clock row and the XP bar row
  const timerSize: int32 = 30
  const centiSize: int32 = 17    # smaller centiseconds tucked after MM:SS
  const centiGap: int32 = 2      # gap between MM:SS and the .CC tenths
  const lblSize: int32 = 13
  const barW: int32 = 230
  const barH: int32 = 12
  const lblGap: int32 = 8        # gap between "LV n" and the bar
  const clockR: int32 = 10       # stopwatch icon radius
  const iconGap: int32 = 7       # gap between stopwatch icon and the digits

  # Stopwatch readout MM:SS.CC. MM:SS is laid against a fixed "00:00" slot and the
  # centiseconds against a fixed ".00" slot so the panel never jitters as the
  # proportional-width digits change. Centiseconds derive from survivalTime, so
  # they freeze with everything else during a boss fight.
  let clampedT = max(0.0'f32, game.survivalTime)
  let totalSecs = int(clampedT)
  let mins = totalSecs div 60
  let secs = totalSecs mod 60
  let centis = int(clampedT * 100.0'f32) mod 100
  let timeStr = (if mins < 10: "0" else: "") & $mins & ":" &
                (if secs < 10: "0" else: "") & $secs
  let centiStr = "." & (if centis < 10: "0" else: "") & $centis
  let timerSlotW = measureText("00:00", timerSize)
  let centiSlotW = measureText(".00", centiSize)
  let timerDigitsW = measureText(timeStr, timerSize)
  let clockBox = clockR * 2 + iconGap
  let timerRowW = clockBox + timerSlotW + centiGap + centiSlotW

  let lvlLabel = t("roguelite_level") & " " & $game.player.rogueliteLevel
  let lblW = measureText(lvlLabel, lblSize)
  let barRowW = lblW + lblGap + barW

  let contentW = max(timerRowW, barRowW)
  let panelW = contentW + padX * 2
  let panelH = padY + timerSize + vGap + barH + padY
  let panelX = if alignRight: screenWidth - panelW - 8
               else: screenWidth div 2 - panelW div 2
  const panelY: int32 = SurvivalHudPanelY

  # --- Card background ----------------------------------------------------
  let panelRect = Rectangle(x: panelX.float32, y: panelY.float32,
                            width: panelW.float32, height: panelH.float32)
  drawRectangleRounded(panelRect, 0.32'f32, 6, Color(r: 8, g: 18, b: 28, a: 205))
  drawRectangleRoundedLines(panelRect, 0.32'f32, 6, 1.5'f32,
                            withAlpha(accent, 150))

  # --- Row 1: stopwatch icon + MM:SS.CC -----------------------------------
  let timerRowX = panelX + (panelW - timerRowW) div 2
  let timerY = panelY + padY
  let cx = (timerRowX + clockR).float32
  let cy = (timerY + timerSize div 2).float32
  let faintAccent = withAlpha(accent, 90)
  # Crown: a little button + stem on top so the icon reads as a handheld stopwatch.
  drawRectangle((cx - 2.0).int32, (cy - clockR.float32 - 4.0).int32, 4, 4, accent)
  drawCircle(Vector2(x: cx, y: cy - clockR.float32 - 4.5), 2.0'f32, accent)
  # Face: dark fill, outer rim, faint inner rim, and 12/3/6/9 tick marks.
  drawCircle(Vector2(x: cx, y: cy), clockR.float32 + 1.0, Color(r: 6, g: 16, b: 24, a: 220))
  drawCircleLines(cx.int32, cy.int32, clockR.float32, accent)
  drawCircleLines(cx.int32, cy.int32, (clockR - 1).float32, faintAccent)
  for q in 0..<4:
    let ta = q.float32 * (PI.float32 / 2.0)
    drawLine(Vector2(x: cx + cos(ta) * (clockR.float32 - 2.4), y: cy + sin(ta) * (clockR.float32 - 2.4)),
             Vector2(x: cx + cos(ta) * (clockR.float32 - 0.6), y: cy + sin(ta) * (clockR.float32 - 0.6)),
             1.0'f32, withAlpha(accent, 130))
  # Hand sweeps once per minute of survival time; since survivalTime freezes during
  # a boss, the hand visibly stops there (reinforced by the gray-out + pause glyph).
  let handAng = (clampedT mod 60.0) / 60.0 * (PI.float32 * 2.0) - PI.float32 / 2.0
  let handLen = clockR.float32 * 0.72
  drawLine(Vector2(x: cx, y: cy),
           Vector2(x: cx + cos(handAng) * handLen, y: cy + sin(handAng) * handLen),
           2.0'f32, digitColor)
  drawCircle(Vector2(x: cx, y: cy), 1.6'f32, accent)
  # MM:SS digits, centred in the fixed slot. An accent glow (live only) + shadow
  # lift them off the card.
  let digitsX = timerRowX + clockBox + (timerSlotW - timerDigitsW) div 2
  if not bossActive:
    drawText(timeStr, digitsX, timerY - 1, timerSize,
             withAlpha(accent, 55))
  drawText(timeStr, digitsX + 1, timerY + 1, timerSize, inkShadow)
  drawText(timeStr, digitsX, timerY, timerSize, digitColor)
  # Centiseconds: smaller + dimmer, baseline-aligned under the big digits.
  let centiX = timerRowX + clockBox + timerSlotW + centiGap
  let centiY = timerY + (timerSize - centiSize)
  drawText(centiStr, centiX + 1, centiY + 1, centiSize, inkShadow)
  drawText(centiStr, centiX, centiY, centiSize,
           withAlpha(digitColor, 175))
  # Pause glyph (two bars) past the centiseconds while the clock is frozen by a boss.
  if bossActive:
    let pbX = centiX + centiSlotW + 8
    let pbY = timerY + 4
    let pbH = timerSize - 8
    drawRectangle(pbX, pbY, 4, pbH, accent)
    drawRectangle(pbX + 7, pbY, 4, pbH, accent)

  # --- Divider between the clock and the XP bar ---------------------------
  let divY = (timerY + timerSize + vGap div 2).float32
  drawLine(Vector2(x: (panelX + padX).float32, y: divY),
           Vector2(x: (panelX + panelW - padX).float32, y: divY),
           1.0'f32, withAlpha(accent, 55))

  # --- Row 2: level label + XP bar ----------------------------------------
  let barRowX = panelX + (panelW - barRowW) div 2
  let barY = panelY + padY + timerSize + vGap
  let lblY = barY + (barH - lblSize) div 2
  drawText(lvlLabel, barRowX + 1, lblY + 1, lblSize, inkShadow)
  drawText(lvlLabel, barRowX, lblY, lblSize, Color(r: 150, g: 255, b: 210, a: 255))
  let barX = barRowX + lblW + lblGap
  drawRectangle(barX, barY, barW, barH, Color(r: 10, g: 30, b: 25, a: 200))
  let ratio = clamp(game.player.xp.float32 /
                    max(1, game.player.xpToNextLevel).float32, 0.0, 1.0)
  let fillW = int32(barW.float32 * ratio)
  if fillW > 0:
    drawRectangle(barX, barY, fillW, barH, xpFill)
  drawRectangleLines(barX, barY, barW, barH, Color(r: 120, g: 220, b: 190, a: 170))

  # --- Wave-incoming banner (burst window, no boss), tucked under the card --
  let waveProgress = (game.survivalTime mod 15.0) / 15.0
  if waveProgress > 0.6 and not game.bossWaveManager.active:
    let banner = t(tkGameWaveAnnouncementMain)
    let bannerW = measureText(banner, 25)
    let bannerX = if alignRight: panelX + panelW div 2 - bannerW div 2
                  else: screenWidth div 2 - bannerW div 2
    drawText(banner, bannerX, panelY + panelH + 6, 25, Red)
