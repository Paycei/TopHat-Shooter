import raylib, strutils
from std/unicode import runeLen, runeSubStr
import types, boss_definitions, localization, utils

type
  DamageDisplayType* = enum
    ddtNormal,      # Standard damage number
    ddtCritical,    # Critical hit - HUGE yellow with stars
    ddtOverkill,    # Overkill - Red "OVERKILL!" text
    ddtCombo,       # Combo hit - Stacking numbers
    ddtElemental    # Elemental - Color-coded with trails

proc getEnhancedDamageInfo*(damage: float32, maxHp: float32, isCrit: bool,
                            isCombo: bool, elementType: ElementType): tuple[
  displayType: DamageDisplayType,
  text: string,
  fontSize: int32,
  color: Color
] =
  ## Determine how damage should be displayed based on context

  # Check for overkill (damage > 150% of max HP)
  if damage > maxHp * 1.5:
    return (
      ddtOverkill,
      "OVERKILL!",
      36,
      Color(r: 255, g: 0, b: 0, a: 255)
    )

  # Check for critical
  if isCrit:
    let size = int32(24 + min(damage / 10.0, 20.0))  # Scale with damage
    return (
      ddtCritical,
      $int(damage),
      size,
      Color(r: 255, g: 255, b: 50, a: 255)
    )

  # Check for combo
  if isCombo:
    return (
      ddtCombo,
      $int(damage),
      22,
      Color(r: 255, g: 150, b: 0, a: 255)
    )

  # Elemental damage
  if elementType != etNone:
    # Use the canonical element color (types.elementColor) so damage-number tints
    # match orbs/auras; this previously held a drifted hand-written copy.
    let elemColor = elementColor(elementType)

    return (
      ddtElemental,
      $int(damage),
      18,
      elemColor
    )

  # Normal damage
  let size = int32(16 + min(damage / 20.0, 8.0))  # Slight scaling
  return (
    ddtNormal,
    $int(damage),
    size,
    White
  )

# WAVE CELEBRATION SYSTEM
proc newWaveCelebration*(): WaveCelebration =
  result = WaveCelebration(
    active: false,
    animationTimer: 0,
    maxAnimationTime: 1.5,
    waveNumber: 0,
    showStats: false,
    statsRevealTimer: 0
  )

proc startCelebration*(celebration: var WaveCelebration, waveNum: int, stats: WaveStats) =
  celebration.active = true
  celebration.animationTimer = 0
  celebration.waveNumber = waveNum
  celebration.stats = stats
  celebration.showStats = false
  celebration.statsRevealTimer = 0

proc updateCelebration*(celebration: var WaveCelebration, dt: float32): bool =
  ## Update celebration, returns true if still active
  if not celebration.active:
    return false

  celebration.animationTimer += dt

  # Show stats after 0.3 seconds (faster reveal)
  if celebration.animationTimer > 0.3:
    celebration.showStats = true
    celebration.statsRevealTimer = celebration.animationTimer - 0.3

  if celebration.animationTimer >= celebration.maxAnimationTime:
    celebration.active = false
    return false

  return true

proc drawWaveCelebration*(celebration: WaveCelebration, screenWidth, screenHeight: int32,
                          originX: int32 = 0) =
  ## Fullscreen celebration overlay. `originX`/`screenWidth` describe the column it
  ## fills: classic passes the whole screen, widescreen passes the 1024-wide world
  ## column so the overlay keeps its 4:3 proportions instead of stretching over the
  ## gutters.
  if not celebration.active:
    return

  let progress = celebration.animationTimer / celebration.maxAnimationTime

  # Draw darkened background
  drawRectangle(originX, 0, screenWidth, screenHeight,
    Color(r: 0, g: 0, b: 0, a: uint8(100 * (1.0 - progress))))

  # Main text with slide-in animation
  let slideProgress = min(1.0, celebration.animationTimer * 3.0)
  let waveText = if isBossWave(celebration.waveNumber):
    t(tkBossDefeatedText) & " " & $getCustomBossNumber(celebration.waveNumber) & " DEFEATED"
  else:
    t(tkWaveClearedText) & " " & $celebration.waveNumber & " CLEARED"
  let textWidth = measureText(waveText, 48.int32)
  let textX = originX + int32((screenWidth.float32 - textWidth.float32) * slideProgress)
  let textY = screenHeight div 2 - 100

  # Draw text with glow effect
  for offsetX in [-2, 0, 2]:
    for offsetY in [-2, 0, 2]:
      if offsetX != 0 or offsetY != 0:
        drawText(waveText, int32(textX + offsetX), int32(textY + offsetY), 48.int32,
          Color(r: 255, g: 215, b: 0, a: 50))

  drawText(waveText, textX, textY, 48.int32,
    Color(r: 255, g: 215, b: 0, a: 255))

  # Draw stats if revealed
  if celebration.showStats:
    let statsAlpha = uint8(min(celebration.statsRevealTimer * 255.0, 255.0))
    let statsY = textY + 80
    let centerX = originX + screenWidth div 2

    # Stats box background
    let boxWidth = 400
    let boxHeight = 200
    let boxX = centerX - (boxWidth div 2)

    drawRectangle(int32(boxX), statsY, int32(boxWidth), int32(boxHeight),
      Color(r: 20, g: 20, b: 40, a: uint8(min(statsAlpha, 200))))
    drawRectangleLines(int32(boxX), statsY, int32(boxWidth), int32(boxHeight),
      Color(r: 255, g: 215, b: 0, a: statsAlpha))

    # Draw stats
    var lineY = statsY + 20
    let lineHeight = 30.int32

    proc drawStat(label: string, value: string, y: int32, alpha: uint8) =
      let labelText = label & ":"
      let valueText = value
      drawText(labelText, int32(boxX + 20), y, 18.int32,
        Color(r: 200, g: 200, b: 200, a: alpha))
      let valueWidth = measureText(valueText, 18.int32)
      drawText(valueText, int32(boxX + boxWidth - valueWidth - 20), y, 18.int32,
        Color(r: 255, g: 255, b: 255, a: alpha))

    drawStat(t(tkWaveCelebKills), $celebration.stats.kills, lineY, statsAlpha)
    lineY += lineHeight
    drawStat(t(tkWaveCelebAccuracy), $(int(celebration.stats.accuracy)) & "%", lineY, statsAlpha)
    lineY += lineHeight
    drawStat(t(tkWaveCelebTime), $(int(celebration.stats.survivalTime)) & "s", lineY, statsAlpha)
    lineY += lineHeight
    drawStat(t(tkWaveCelebCoins), $celebration.stats.coinsEarned, lineY, statsAlpha)
    lineY += lineHeight

    if celebration.stats.maxCombo > 1:
      drawStat(t(tkWaveCelebMaxCombo), $(celebration.stats.maxCombo) & "x", lineY, statsAlpha)

# TEXT WRAPPING (shared by the fullscreen boss card and the gutter cards)
proc wrapTextToWidth(text: string, fontSize, maxWidth: int32): seq[string] =
  ## Greedy word-wrap so a label fits inside a card of the given width.
  result = @[]
  var current = ""
  for word in text.split(' '):
    if word.len == 0:
      continue
    let candidate = if current.len == 0: word else: current & " " & word
    if measureText(candidate, fontSize) <= maxWidth or current.len == 0:
      current = candidate
    else:
      result.add(current)
      current = word
  if current.len > 0:
    result.add(current)

proc balancedWrap(text: string, fontSize, maxWidth: int32): seq[string] =
  ## Fewest lines that fit maxWidth, then the narrowest width that keeps that
  ## count, so a two-line description splits evenly instead of leaving a
  ## one-word orphan on its last line. Greedy line count only grows as the
  ## width shrinks, so a binary search finds that width.
  result = wrapTextToWidth(text, fontSize, maxWidth)
  if result.len <= 1:
    return
  var lo = maxWidth div 3
  var hi = maxWidth
  while hi - lo > 4:
    let mid = (lo + hi) div 2
    if wrapTextToWidth(text, fontSize, mid).len <= result.len: hi = mid
    else: lo = mid
  result = wrapTextToWidth(text, fontSize, hi)

# BOSS INTRODUCTION SYSTEM
# The card names the boss and, in the lore layer, the TOPHAT service the Root
# hijacked to make it (boss 12 is the Root itself). The world is frozen while it
# shows (only the player moves), so keep the lifetime short.
const
  BossIntroDuration = 1.8'f32   # card lifetime, seconds
  BossIntroTextIn = 0.3'f32     # text starts fading in here (phase 1)
  BossIntroFade = 0.25'f32      # text fade-in and fade-out length
  BossIntroTagCps = 70.0'f32    # service tag types out at this many chars/s

proc newBossIntroduction*(): BossIntroduction =
  result = BossIntroduction(
    active: false,
    timer: 0,
    maxTime: BossIntroDuration,
    bossName: "",
    bossTitle: "",
    bossTag: "",
    isRoot: false,
    bossHp: 0,
    phase: 0
  )

proc startIntroduction*(intro: var BossIntroduction, name: string, title: string, hp: float32,
                        tag: string = "", isRoot: bool = false) =
  intro.active = true
  intro.timer = 0
  intro.maxTime = BossIntroDuration
  intro.bossName = name
  intro.bossTitle = title
  intro.bossTag = tag
  intro.isRoot = isRoot
  intro.bossHp = hp
  intro.phase = 0

proc bossIntroTextAlpha(intro: BossIntroduction): float32 =
  ## 0..1 text opacity: in from BossIntroTextIn, out over the final BossIntroFade,
  ## so the card holds at full legibility for most of its life.
  let fadeIn = clamp((intro.timer - BossIntroTextIn) / BossIntroFade, 0.0'f32, 1.0'f32)
  let fadeOut = clamp((intro.maxTime - intro.timer) / BossIntroFade, 0.0'f32, 1.0'f32)
  min(fadeIn, fadeOut)

proc bossIntroTypedTag(intro: BossIntroduction): string =
  ## The service tag typed out like a terminal readout (rune-safe for accents).
  let shown = int((intro.timer - BossIntroTextIn) * BossIntroTagCps)
  intro.bossTag.runeSubStr(0, clamp(shown, 0, intro.bossTag.runeLen))

proc bossIntroPalette(intro: BossIntroduction): tuple[name, tag: Color] =
  ## Hijacked services read as alarm red with an amber tag; the Root itself
  ## wears the breach magenta the lore cinematics give it.
  if intro.isRoot:
    (Color(r: 255, g: 70, b: 200, a: 255), Color(r: 255, g: 160, b: 235, a: 255))
  else:
    (Color(r: 255, g: 100, b: 100, a: 255), Color(r: 255, g: 175, b: 70, a: 255))

proc updateIntroduction*(intro: var BossIntroduction, dt: float32): bool =
  ## Update introduction, returns true if still active
  if not intro.active:
    return false

  intro.timer += dt

  # Phase transitions (adjusted for 1.5s total duration)
  if intro.timer > 0.3 and intro.phase == 0:
    intro.phase = 1  # Name appears
  elif intro.timer > 1.0 and intro.phase == 1:
    intro.phase = 2  # Ready to fight

  if intro.timer >= intro.maxTime:
    intro.active = false
    return false

  return true

proc drawBossIntroduction*(intro: BossIntroduction, screenWidth, screenHeight: int32) =
  if not intro.active:
    return

  # Darken the frozen world; eases off with the text so the release isn't a hard cut.
  let dimOut = clamp((intro.maxTime - intro.timer) / BossIntroFade, 0.0'f32, 1.0'f32)
  let dim = min(intro.timer * 400.0'f32, 100.0'f32) * dimOut
  drawRectangle(0, 0, screenWidth, screenHeight, Color(r: 0, g: 0, b: 0, a: clampByteF(dim)))

  if intro.phase < 1:
    return

  let a = bossIntroTextAlpha(intro)
  let (nameColor, tagColor) = bossIntroPalette(intro)
  let cx = screenWidth div 2
  let centerY = screenHeight div 2

  # Service tag above the name, flanked by short rules and typed out.
  if intro.bossTag.len > 0:
    const tagSize = 16'i32
    let tagY = centerY - 68
    let fullW = measureText(intro.bossTag, tagSize)
    let tagX = cx - fullW div 2
    let typed = bossIntroTypedTag(intro)
    drawText(typed, tagX, tagY, tagSize, withAlpha(tagColor, clampByteF(a * 235.0'f32)))
    let ruleA = clampByteF(a * 150.0'f32)
    drawRectangle(tagX - 44, tagY + tagSize div 2 - 1, 32, 2, withAlpha(tagColor, ruleA))
    drawRectangle(tagX + fullW + 12, tagY + tagSize div 2 - 1, 32, 2, withAlpha(tagColor, ruleA))

  # Boss name with a drop shadow.
  let nameW = measureText(intro.bossName, 48'i32)
  let nameX = cx - nameW div 2
  drawText(intro.bossName, nameX + 2, centerY - 38, 48'i32,
    Color(r: 0, g: 0, b: 0, a: clampByteF(a * 128.0'f32)))
  drawText(intro.bossName, nameX, centerY - 40, 48'i32, withAlpha(nameColor, clampByteF(a * 255.0'f32)))

  # Lore description, wrapped so the longer dossier lines stay on screen.
  const descSize = 20'i32
  let descLines = balancedWrap(intro.bossTitle, descSize, min(screenWidth - 120, 760'i32))
  var dy = centerY + 20
  for ln in descLines:
    let w = measureText(ln, descSize)
    drawText(ln, cx - w div 2, dy, descSize, Color(r: 190, g: 190, b: 195, a: clampByteF(a * 255.0'f32)))
    dy += descSize + 4

# WIDESCREEN GUTTER VARIANTS
# Compact cards that fit inside a 171px gutter column. They keep the timing /
# alpha animation logic of the fullscreen versions but drop the fullscreen
# darken (which would cover the centered gameplay world) and wrap their text.
proc drawWaveCelebrationGutter*(celebration: WaveCelebration,
                                gutterX, gutterW, topY: int32): int32 =
  ## Right-gutter card. Returns the next stack Y (== topY when nothing is drawn).
  if not celebration.active:
    return topY

  let progress = celebration.animationTimer / celebration.maxAnimationTime
  let slideProgress = min(1.0'f32, celebration.animationTimer * 3.0'f32)
  let cardW: int32 = min(gutterW - 8, 163'i32)
  let slideOff = int32((1.0'f32 - slideProgress) * (cardW.float32 + 12.0'f32))
  let cardX = gutterX + (gutterW - cardW) div 2 + slideOff
  let cardY: int32 = topY
  let titleAlpha = uint8(clamp((1.0'f32 - progress) * 255.0'f32 + 40.0'f32, 0.0, 255.0))

  let waveText = if isBossWave(celebration.waveNumber):
    t(tkBossDefeatedText) & " " & $getCustomBossNumber(celebration.waveNumber) & " DEFEATED"
  else:
    t(tkWaveClearedText) & " " & $celebration.waveNumber & " CLEARED"
  let titleFont: int32 = 15
  let titleLines = wrapTextToWidth(waveText, titleFont, cardW - 10)

  # Stat rows (only when revealed).
  var statRows: seq[(string, string)] = @[]
  if celebration.showStats:
    statRows.add((t(tkWaveCelebKills), $celebration.stats.kills))
    statRows.add((t(tkWaveCelebAccuracy), $(int(celebration.stats.accuracy)) & "%"))
    statRows.add((t(tkWaveCelebTime), $(int(celebration.stats.survivalTime)) & "s"))
    statRows.add((t(tkWaveCelebCoins), $celebration.stats.coinsEarned))
    if celebration.stats.maxCombo > 1:
      statRows.add((t(tkWaveCelebMaxCombo), $(celebration.stats.maxCombo) & "x"))

  let titleH = titleLines.len.int32 * (titleFont + 3)
  let statH = if statRows.len > 0: 6'i32 + statRows.len.int32 * 16'i32 else: 0'i32
  let cardH = 10'i32 + titleH + statH
  let statsAlpha = uint8(min(celebration.statsRevealTimer * 255.0, 255.0))

  drawRectangle(cardX, cardY, cardW, cardH, Color(r: 20, g: 20, b: 40, a: uint8(min(titleAlpha, 210))))
  drawRectangle(cardX, cardY, 2, cardH, Color(r: 255, g: 215, b: 0, a: titleAlpha))
  drawRectangle(cardX + cardW - 2, cardY, 2, cardH, Color(r: 255, g: 215, b: 0, a: titleAlpha))

  var ty = cardY + 5
  for ln in titleLines:
    let tw = measureText(ln, titleFont)
    drawText(ln, cardX + (cardW - tw) div 2, ty, titleFont,
      Color(r: 255, g: 215, b: 0, a: titleAlpha))
    ty += titleFont + 3

  if statRows.len > 0:
    ty += 4
    for row in statRows:
      drawText(row[0], cardX + 8, ty, 12,
        Color(r: 200, g: 200, b: 200, a: statsAlpha))
      let vw = measureText(row[1], 12)
      drawText(row[1], cardX + cardW - 8 - vw, ty, 12,
        Color(r: 255, g: 255, b: 255, a: statsAlpha))
      ty += 16
  return cardY + cardH + 6

proc drawBossIntroductionGutter*(intro: BossIntroduction,
                                 gutterX, gutterW, topY: int32): int32 =
  ## Right-gutter card. Returns the next stack Y (== topY when nothing is drawn).
  if not intro.active:
    return topY
  if intro.phase < 1:
    return topY

  let a = bossIntroTextAlpha(intro)
  let nameAlpha = clampByteF(a * 255.0'f32)
  let (nameColor, tagColor) = bossIntroPalette(intro)
  let cardW: int32 = min(gutterW - 8, 163'i32)
  let cardX = gutterX + (gutterW - cardW) div 2
  let cardY: int32 = topY

  # The tag is laid out on its full text so the card height doesn't grow while it
  # types. Too wide for one line, it breaks after the label so a process name
  # like "root (uid 0)" never splits.
  let tagFont: int32 = 11
  let tagCut = intro.bossTag.find(": ")
  let tagLines =
    if intro.bossTag.len == 0: newSeq[string]()
    elif measureText(intro.bossTag, tagFont) <= cardW - 10: @[intro.bossTag]
    elif tagCut > 0: @[intro.bossTag[0 .. tagCut], intro.bossTag[tagCut + 2 .. ^1]]
    else: wrapTextToWidth(intro.bossTag, tagFont, cardW - 10)
  let nameFont: int32 = 22
  let nameLines = wrapTextToWidth(intro.bossName, nameFont, cardW - 10)
  let titleFont: int32 = 13
  let titleLines = wrapTextToWidth(intro.bossTitle, titleFont, cardW - 10)

  let tagH = if tagLines.len > 0: tagLines.len.int32 * (tagFont + 2) + 4'i32 else: 0'i32
  let nameH = nameLines.len.int32 * (nameFont + 3)
  let titleH = titleLines.len.int32 * (titleFont + 2)
  let cardH = 12'i32 + tagH + nameH + 6'i32 + titleH

  let bg = if intro.isRoot: Color(r: 28, g: 6, b: 24, a: 255) else: Color(r: 25, g: 8, b: 8, a: 255)
  drawRectangle(cardX, cardY, cardW, cardH, withAlpha(bg, clampByteF(a * 200.0'f32)))
  drawRectangle(cardX, cardY, 2, cardH, withAlpha(nameColor, nameAlpha))
  drawRectangle(cardX + cardW - 2, cardY, 2, cardH, withAlpha(nameColor, nameAlpha))

  var ty = cardY + 6
  if tagLines.len > 0:
    # Reveal the typed prefix line by line across the pre-wrapped layout.
    var remaining = bossIntroTypedTag(intro).runeLen
    for ln in tagLines:
      let lnLen = ln.runeLen
      let shown = ln.runeSubStr(0, clamp(remaining, 0, lnLen))
      remaining -= lnLen + 1   # +1 for the space the line break consumed
      let tw = measureText(ln, tagFont)
      drawText(shown, cardX + (cardW - tw) div 2, ty, tagFont,
        withAlpha(tagColor, clampByteF(a * 235.0'f32)))
      ty += tagFont + 2
    ty += 4
  for ln in nameLines:
    let tw = measureText(ln, nameFont)
    let tx = cardX + (cardW - tw) div 2
    drawText(ln, tx + 1, ty + 1, nameFont, Color(r: 0, g: 0, b: 0, a: uint8(nameAlpha div 2)))
    drawText(ln, tx, ty, nameFont, withAlpha(nameColor, nameAlpha))
    ty += nameFont + 3
  ty += 6
  for ln in titleLines:
    let tw = measureText(ln, titleFont)
    drawText(ln, cardX + (cardW - tw) div 2, ty, titleFont,
      Color(r: 180, g: 180, b: 180, a: nameAlpha))
    ty += titleFont + 2
  return cardY + cardH + 6

# REAL-TIME STATS HUD
proc newRealTimeStats*(): RealTimeStats =
  result = RealTimeStats(
    dps: 0,
    damageDealt: 0,
    lastDamageTime: 0,
    kills: 0,
    coinsPerMinute: 0,
    totalCoins: 0,
    lastCoinTime: 0,
    powerLevel: 100
  )
  # Initialize damage history for rolling window
  result.damageHistory = @[]

proc recordDamage*(stats: var RealTimeStats, damage: float32, currentTime: float32) =
  stats.damageDealt += damage

  # Add damage event to history with timestamp
  stats.damageHistory.add((currentTime, damage))

  # Remove damage events older than 5 seconds (rolling window)
  while stats.damageHistory.len > 0 and
        currentTime - stats.damageHistory[0][0] > 5.0:
    stats.damageHistory.delete(0)

  # Calculate DPS from rolling 5-second window
  var windowDamage = 0.0
  for entry in stats.damageHistory:
    windowDamage += entry[1]

  # Use actual window duration (up to 5 seconds)
  let windowDuration = if stats.damageHistory.len > 0:
    min(5.0, currentTime - stats.damageHistory[0][0])
  else:
    1.0

  stats.dps = windowDamage / max(windowDuration, 1.0)
  stats.lastDamageTime = currentTime

proc recordKill*(stats: var RealTimeStats) =
  stats.kills += 1

proc recordCoin*(stats: var RealTimeStats, currentTime: float32) =
  stats.totalCoins += 1
  stats.lastCoinTime = currentTime

  # Calculate coins per minute
  if currentTime > 0:
    stats.coinsPerMinute = (stats.totalCoins.float32 / currentTime) * 60.0

proc calculatePowerLevel*(stats: var RealTimeStats, player: Player) =
  ## Calculate overall power level based on stats and upgrades
  var power = 100
  power += player.powerUps.len * 50
  power += int(player.damage * 10.0)
  power += int(player.maxHp * 5.0)
  stats.powerLevel = power

proc drawRealTimeStats*(stats: RealTimeStats, screenWidth, screenHeight: int32) =
  let panelX = screenWidth - 230
  let panelY = 50.int32
  let lineHeight = 25.int32
  var currentY = panelY

  # Semi-transparent background
  drawRectangle(panelX - 10, panelY - 10, 220.int32, 170.int32,
    Color(r: 0, g: 0, b: 0, a: 150))
  drawRectangleLines(panelX - 10, panelY - 10, 220.int32, 170.int32,
    Color(r: 100, g: 100, b: 100, a: 200))

  # Power Level with glow if high
  let powerText = t(tkRealStatsPower) & ": " & $stats.powerLevel
  let powerColor = if stats.powerLevel > 500:
    Color(r: 255, g: 215, b: 0, a: 255)
  else:
    Color(r: 200, g: 200, b: 200, a: 255)

  drawText(powerText, panelX, currentY, 20.int32, powerColor)
  currentY += lineHeight

  # DPS
  let dpsText = t(tkRealStatsDPS) & ": " & $(int(stats.dps))
  drawText(dpsText, panelX, currentY, 18.int32,
    Color(r: 255, g: 100, b: 100, a: 255))
  currentY += lineHeight

  # Kills
  let killsText = t(tkRealStatsKills) & ": " & $stats.kills
  drawText(killsText, panelX, currentY, 18.int32,
    Color(r: 200, g: 200, b: 200, a: 255))
  currentY += lineHeight

  # Coins per minute
  let cpmText = t(tkRealStatsCPM) & ": " & $(int(stats.coinsPerMinute))
  drawText(cpmText, panelX, currentY, 18.int32,
    Color(r: 255, g: 215, b: 0, a: 255))
