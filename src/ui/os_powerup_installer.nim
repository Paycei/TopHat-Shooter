## OS-Style Process Installer Module
## Power-up selection screen as modern software installation interface
# The roll animation system is handled in powerup.nim

import raylib, math
import ../types, icon_drawing, ../localization, ../powerup_data, ../render_context, ../settings, ui_helpers, ../utils

const
  INSTALLER_BASE_WIDTH: int32 = 1000   # classic (4:3) width -- do not change
  INSTALLER_MAX_GROWTH: int32 = 260    # widescreen cap -> 1260 wide, ~53px gutters
  INSTALLER_HEIGHT: int32 = 650
  TITLE_BAR_HEIGHT: int32 = 45
  CARD_BASE_WIDTH: int32 = 280
  CARD_HEIGHT: int32 = 380             # fixed: powerup.nim's roll math scrolls by this
  CARD_BASE_SPACING: int32 = 35
  CARD_MAX_SPACING_GROWTH: int32 = 20
  PROGRESS_BAR_HEIGHT: int32 = 22
  CONTINUE_BTN_W: int32 = 300
  CONTINUE_BTN_H: int32 = 50
  REROLL_BTN_W: int32 = 220
  REROLL_BTN_H: int32 = 42
  CLOSE_BTN_SIZE: int32 = 28

type
  InstallerLayout* = object
    ## Resolved geometry of the power-up installer for the current virtual
    ## resolution. `installerLayout()` is the single source of truth: the draw
    ## pass here and the click hit-testing in main.nim both read it, so the two
    ## can never disagree the way the old duplicated const blocks could.
    winX*, winY*, winW*, winH*: int32
    closeX*, closeY*, closeSize*: int32
    cardsX*, cardsY*: int32              # top-left of the first card
    cardW*, cardH*, cardSpacing*: int32
    bottomY*: int32                      # top of the bottom control panel
    rerollX*, rerollY*, rerollW*, rerollH*: int32
    continueX*, continueY*, continueW*, continueH*: int32

proc installerLayout*(): InstallerLayout =
  ## Widescreen (16:9) hands the panel ~260 extra pixels. Rather than banking it
  ## as margin, it is split between the three cards (~73px each) and the gaps
  ## between them (+20px), so descriptions wrap into fewer lines and the icon /
  ## badge row breathes. In classic the growth term is 0 and every number below
  ## collapses to the original hand-tuned layout.
  let grow = min(getExtraVirtualWidth(), INSTALLER_MAX_GROWTH)
  let spacingGrow = min(grow div 10, CARD_MAX_SPACING_GROWTH)

  result.winW = INSTALLER_BASE_WIDTH + grow
  result.winH = INSTALLER_HEIGHT
  result.winX = (getVirtualScreenWidth() - result.winW) div 2
  result.winY = (getVirtualScreenHeight() - result.winH) div 2

  result.closeSize = CLOSE_BTN_SIZE
  result.closeX = result.winX + result.winW - result.closeSize - 10
  result.closeY = result.winY + (TITLE_BAR_HEIGHT - result.closeSize) div 2

  result.cardSpacing = CARD_BASE_SPACING + spacingGrow
  result.cardW = CARD_BASE_WIDTH + (grow - spacingGrow * 2) div 3
  result.cardH = CARD_HEIGHT
  let totalCardW = result.cardW * 3 + result.cardSpacing * 2
  result.cardsX = result.winX + (result.winW - totalCardW) div 2
  # Title bar, then a 20px gap + 40px instruction header above the card row.
  result.cardsY = result.winY + TITLE_BAR_HEIGHT + 60

  result.bottomY = result.winY + result.winH - 120
  result.rerollW = REROLL_BTN_W
  result.rerollH = REROLL_BTN_H
  result.rerollX = result.winX + (result.winW - result.rerollW) div 2
  result.rerollY = result.bottomY + 15

  result.continueW = CONTINUE_BTN_W
  result.continueH = CONTINUE_BTN_H
  result.continueX = result.winX + (result.winW - result.continueW) div 2
  result.continueY = result.winY + result.winH - 100

proc cardX*(l: InstallerLayout, i: int): int32 =
  ## Left edge of card `i` (0..2).
  l.cardsX + int32(i) * (l.cardW + l.cardSpacing)

proc cardRect*(l: InstallerLayout, i: int): Rectangle =
  Rectangle(x: l.cardX(i).float32, y: l.cardsY.float32,
            width: l.cardW.float32, height: l.cardH.float32)

proc closeRect*(l: InstallerLayout): Rectangle =
  Rectangle(x: l.closeX.float32, y: l.closeY.float32,
            width: l.closeSize.float32, height: l.closeSize.float32)

proc rerollRect*(l: InstallerLayout): Rectangle =
  Rectangle(x: l.rerollX.float32, y: l.rerollY.float32,
            width: l.rerollW.float32, height: l.rerollH.float32)

proc continueRect*(l: InstallerLayout): Rectangle =
  Rectangle(x: l.continueX.float32, y: l.continueY.float32,
            width: l.continueW.float32, height: l.continueH.float32)

proc drawModernButton(x, y, width, height: int32, text: string,
                     enabled: bool = true, highlight: bool = false,
                     time: float32 = 0.0) =
  let bgColor = if not enabled:
    Color(r: 35, g: 40, b: 50, a: 255)
  elif highlight:
    Color(r: 0, g: 140, b: 255, a: 255)
  else:
    Color(r: 45, g: 55, b: 70, a: 255)

  if enabled:
    drawRectangle(x + 2, y + 2, width, height, Color(r: 0, g: 0, b: 0, a: 80))

  drawRectangle(x, y, width, height, bgColor)

  if enabled:
    drawRectangle(x, y, width, 2, Color(r: 255, g: 255, b: 255, a: 30))

  let borderColor = if not enabled:
    Color(r: 70, g: 80, b: 90, a: 255)
  elif highlight:
    let pulse = sin(time * 5.0) * 0.3 + 0.7
    Color(r: 0, g: 200, b: 255, a: uint8(200 * pulse))
  else:
    Color(r: 100, g: 120, b: 140, a: 255)

  let borderWidth = if highlight: 2.5 else: 2.0
  drawRectangleLines(Rectangle(x: x.float32, y: y.float32,
                                width: width.float32, height: height.float32),
                    borderWidth, borderColor)

  let textColor = if not enabled: Color(r: 100, g: 100, b: 110, a: 255) else: White
  let textWidth = measureText(text, 15)
  drawText(text, x + (width - textWidth) div 2, y + (height - 15) div 2, 15, textColor)

proc drawProcessCard(x, y, width, height: int32, powerUp: PowerUp,
                    selected: bool, time: float32, playerDamage: float32,
                    alpha: float32 = 1.0) =
  ## Draw a single power-up card. alpha 0..1 is used for motion-blur dimming.

  let a = clamp(alpha, 0.0'f32, 1.0'f32)

  # Shadow
  if a > 0.5:
    for i in 0..2:
      let off = int32(i + 1) * 2
      drawRectangle(x + off, y + off, width, height,
                   Color(r: 0, g: 0, b: 0, a: uint8(40.0 * a)))

  # Background
  let bgColor = if selected: Color(r: 35, g: 48, b: 65, a: 255)
                else:        Color(r: 22, g: 28, b: 40, a: 255)
  drawRectangle(x, y, width, height, bgColor)

  # Top accent bar
  let accentColor = if powerUp.rarity == prLegendary: Color(r: 255, g: 215, b: 0, a: 255)
                    else:                              Color(r: 0, g: 180, b: 255, a: 255)
  drawRectangle(x, y, width, 4, accentColor)

  # Selection glow rings
  if selected and a > 0.7:
    let pulse = sin(time * 4.5) * 0.25 + 0.75
    for i in 1..3:
      let off = int32(i) * 2
      drawRectangleLines(
        Rectangle(x: float32(x - off), y: float32(y - off),
                  width: float32(width + off * 2), height: float32(height + off * 2)),
        1.0, Color(r: 0, g: 200, b: 255, a: uint8(float32(180 div int32(i * 2)) * pulse * a)))

  # Border
  let borderColor = if selected: Color(r: 0, g: 220, b: 255, a: 255)
                    else:        Color(r: 60, g: 75, b: 95, a: 255)
  drawRectangleLines(Rectangle(x: x.float32, y: y.float32,
                                width: width.float32, height: height.float32),
                    if selected: 3.0 else: 2.0, borderColor)

  # "NEW" badge: a simple indicator for power-ups the player has never installed.
  # It reads the same codex (globalSettings.discoveredPowerUps, keyed by the enum
  # symbol via `$powerUp.powerType`) that death.nim records first-time installs
  # into, so it appears on every game mode's selection screen automatically.
  # `a > 0.5` keeps it hidden during the fast blur frames of the slot roll.
  if a > 0.5'f32 and not isPowerUpDiscovered(powerUp.powerType):
    let newText = t(tkPowerUpNewBadge)
    let newFont: int32 = 12
    let newTextW = measureText(newText, newFont)
    let nbW = newTextW + 14
    let nbH: int32 = 20
    let nbX = x + width - nbW - 8
    let nbY = y + 9
    let pulse = sin(time * 5.0) * 0.3 + 0.7
    # Pulsing glow rings (green reads as "new/unlocked", distinct from the blue
    # standard accent and the gold legendary accent).
    for gi in 1..3:
      let go = int32(gi) * 2
      drawRectangleLines(
        Rectangle(x: float32(nbX - go), y: float32(nbY - go),
                  width: float32(nbW + go * 2), height: float32(nbH + go * 2)),
        1.0, Color(r: 70, g: 240, b: 130, a: uint8(float32(90 div gi) * pulse * a)))
    drawRectangle(nbX + 1, nbY + 1, nbW, nbH, Color(r: 0, g: 0, b: 0, a: uint8(90.0 * a)))
    drawRectangle(nbX, nbY, nbW, nbH, Color(r: 22, g: 64, b: 38, a: uint8(255.0 * a)))
    drawRectangle(nbX, nbY, nbW, 2, Color(r: 120, g: 255, b: 170, a: uint8(160.0 * a)))
    drawRectangleLines(Rectangle(x: nbX.float32, y: nbY.float32,
                                  width: nbW.float32, height: nbH.float32),
                      2.0, Color(r: 80, g: 240, b: 130, a: uint8(255.0 * a * pulse)))
    let ntx = nbX + (nbW - newTextW) div 2
    drawText(newText, ntx + 1, nbY + 5, newFont, Color(r: 0, g: 0, b: 0, a: uint8(150.0 * a)))
    drawText(newText, ntx, nbY + 4, newFont, Color(r: 190, g: 255, b: 210, a: uint8(255.0 * a)))

  var yOff = y + 20

  # Icon area
  let iconSize: int32 = 60
  let iconX = x + (width - iconSize) div 2
  drawRectangle(iconX + 2, yOff + 2, iconSize, iconSize, Color(r: 0, g: 0, b: 0, a: 80))
  drawRectangle(iconX, yOff, iconSize, iconSize, Color(r: 30, g: 38, b: 52, a: 255))
  drawRectangle(iconX + 3, yOff + 3, iconSize - 6, iconSize - 6, Color(r: 40, g: 50, b: 65, a: 255))
  drawRectangleLines(Rectangle(x: iconX.float32, y: yOff.float32,
                                width: iconSize.float32, height: iconSize.float32), 2.0, accentColor)
  drawRectangleLines(Rectangle(x: float32(iconX + 2), y: float32(yOff + 2),
                                width: float32(iconSize - 4), height: float32(iconSize - 4)),
                    1.0, withAlpha(accentColor, 120))

  # Legendary corner decorations
  if powerUp.rarity == prLegendary and a > 0.6:
    let pulse = sin(time * 3.0) * 0.3 + 0.7
    let cA = uint8(255.0 * pulse)
    let cs: int32 = 6
    let gold = Color(r: 255, g: 215, b: 0, a: cA)
    # top-left
    drawRectangle(iconX - 2, yOff - 2, cs, 2, gold)
    drawRectangle(iconX - 2, yOff - 2, 2, cs, gold)
    # top-right
    drawRectangle(iconX + iconSize - cs + 2, yOff - 2, cs, 2, gold)
    drawRectangle(iconX + iconSize, yOff - 2, 2, cs, gold)
    # bottom-left
    drawRectangle(iconX - 2, yOff + iconSize, cs, 2, gold)
    drawRectangle(iconX - 2, yOff + iconSize - cs + 2, 2, cs, gold)
    # bottom-right
    drawRectangle(iconX + iconSize - cs + 2, yOff + iconSize, cs, 2, gold)
    drawRectangle(iconX + iconSize, yOff + iconSize - cs + 2, 2, cs, gold)

  drawPowerUpIcon(iconX + 5, yOff + 5, iconSize - 10, powerUp.powerType, accentColor)
  yOff += iconSize + 18

  # Name
  let processName = getPowerUpName(powerUp.powerType)
  let nameWidth = measureText(processName, 20)
  drawText(processName, x + (width - nameWidth) div 2, yOff, 20,
          if powerUp.rarity == prLegendary: Gold else: Color(r: 100, g: 200, b: 255, a: 255))
  yOff += 30

  # Version + Rarity badges
  let versionText = "v" & $powerUp.level & ".0"
  let versionWidth = measureText(versionText, 14)
  let versionBadgeWidth = versionWidth + 28
  let rarityText = if powerUp.rarity == prLegendary: "[*] LEGENDARY [*]" else: "STANDARD"
  let rarityWidth: int32 = measureText(rarityText, 14)
  let rarityBadgeWidth = rarityWidth + 28
  let badgeSpacing: int32 = 15
  let totalBadgeWidth = versionBadgeWidth + badgeSpacing + rarityBadgeWidth
  let badgesStartX: int32 = x + (width - totalBadgeWidth) div 2
  let versionX: int32 = badgesStartX
  let badgeX: int32 = badgesStartX + versionBadgeWidth + badgeSpacing
  let badgeHeight: int32 = 28

  # Version badge
  let vBg = case powerUp.level
    of 1: Color(r: 45, g: 55, b: 80, a: 255)
    of 2: Color(r: 45, g: 70, b: 55, a: 255)
    else: Color(r: 70, g: 50, b: 45, a: 255)
  drawRectangle(versionX + 1, yOff + 1, versionBadgeWidth, badgeHeight, Color(r: 0, g: 0, b: 0, a: 80))
  drawRectangle(versionX, yOff, versionBadgeWidth, badgeHeight, vBg)
  drawRectangle(versionX, yOff, versionBadgeWidth, 2,
               Color(r: min(vBg.r + 60, 255), g: min(vBg.g + 60, 255), b: min(vBg.b + 60, 255), a: 255))
  let vBorderColor = case powerUp.level
    of 1: Color(r: 80, g: 120, b: 180, a: 255)
    of 2: Color(r: 80, g: 180, b: 120, a: 255)
    else: Color(r: 180, g: 120, b: 80, a: 255)
  drawRectangleLines(Rectangle(x: versionX.float32, y: yOff.float32,
                                width: versionBadgeWidth.float32, height: badgeHeight.float32),
                    2.0, vBorderColor)
  let vTX = versionX + (versionBadgeWidth - versionWidth) div 2
  let vTY = yOff + (badgeHeight - 14) div 2
  drawText(versionText, vTX + 1, vTY + 1, 14, Color(r: 0, g: 0, b: 0, a: 150))
  drawText(versionText, vTX, vTY, 14, Color(r: 200, g: 210, b: 220, a: 255))

  # Rarity badge
  let rarityColor = if powerUp.rarity == prLegendary: Color(r: 255, g: 215, b: 0, a: 255)
                    else:                              Color(r: 100, g: 180, b: 220, a: 255)
  if powerUp.rarity == prLegendary and a > 0.6:
    let gp = sin(time * 3.0) * 0.35 + 0.65
    for i in 1..4:
      let gs: int32 = int32(i * 3)
      drawRectangle(badgeX - gs, yOff - gs,
                   rarityWidth + 28 + gs * 2, badgeHeight + gs * 2,
                   Color(r: 255, g: 215, b: 0, a: uint8((60.0 - i.float32 * 12.0) * gp * a)))
    for i in 0..5:
      let sA = time * 4.0 + i.float32 * 1.047
      let sD = 25.0 + sin(time * 5.0 + i.float32) * 5.0
      let sX = badgeX + (rarityWidth + 28) div 2 + int32(cos(sA) * sD)
      let sY = yOff + badgeHeight div 2 + int32(sin(sA) * sD * 0.6)
      let sS = 2.0'f32 + sin(time * 6.0 + i.float32 * 0.5) * 1.5'f32
      drawCircle(Vector2(x: sX.float32, y: sY.float32), max(1.0'f32, sS),
                Color(r: 255, g: 240, b: 150, a: uint8(200.0 * gp)))
  drawRectangle(badgeX + 2, yOff + 2, rarityWidth + 28, badgeHeight, Color(r: 0, g: 0, b: 0, a: 100))
  drawRectangle(badgeX, yOff, rarityWidth + 28, badgeHeight, Color(r: 35, g: 40, b: 50, a: 255))
  if powerUp.rarity == prLegendary:
    drawRectangle(badgeX, yOff, rarityWidth + 28, badgeHeight div 2, Color(r: 80, g: 70, b: 20, a: 100))
  drawRectangleLines(Rectangle(x: badgeX.float32, y: yOff.float32,
                                width: float32(rarityWidth + 28), height: badgeHeight.float32),
                    2.0, rarityColor)
  if powerUp.rarity == prLegendary:
    drawRectangleLines(Rectangle(x: float32(badgeX + 3), y: float32(yOff + 3),
                                  width: float32(rarityWidth + 22), height: float32(badgeHeight - 6)),
                      1.0, Color(r: 255, g: 235, b: 100, a: 180))
  drawText(rarityText, badgeX + 15, yOff + 8, 14, Color(r: 0, g: 0, b: 0, a: 180))
  drawText(rarityText, badgeX + 14, yOff + 7, 14, rarityColor)
  yOff += 48

  # Tier progress bar
  let maxTiers = if powerUp.rarity == prLegendary: 1 else: 3
  drawText(t(tkPowerUpUpgradeTier), x + 12, yOff, 12, Color(r: 140, g: 160, b: 180, a: 255))
  yOff += 18
  let barWidth = width - 24
  drawRectangle(x + 14, yOff + 2, barWidth, PROGRESS_BAR_HEIGHT, Color(r: 0, g: 0, b: 0, a: 80))
  drawRectangle(x + 12, yOff, barWidth, PROGRESS_BAR_HEIGHT, Color(r: 28, g: 32, b: 42, a: 255))
  if maxTiers > 1:
    for i in 1..(maxTiers - 1):
      let segX: int32 = x + 12 + barWidth * int32(i) div int32(maxTiers)
      drawLine(segX, yOff, segX, yOff + PROGRESS_BAR_HEIGHT, Color(r: 50, g: 60, b: 75, a: 255))
  for level in 1..powerUp.level:
    let sStart: int32 = x + 12 + barWidth * int32(level - 1) div int32(maxTiers)
    let sEnd:   int32 = x + 12 + barWidth * int32(level) div int32(maxTiers)
    let sW = sEnd - sStart
    let lc = case level
      of 1: Color(r: 80, g: 150, b: 255, a: 255)
      of 2: Color(r: 80, g: 255, b: 150, a: 255)
      else: Color(r: 255, g: 140, b: 80, a: 255)
    drawRectangle(sStart, yOff, sW, PROGRESS_BAR_HEIGHT, lc)
    drawRectangle(sStart, yOff, sW, 3,
                 Color(r: min(lc.r + 100, 255), g: min(lc.g + 100, 255), b: min(lc.b + 100, 255), a: 180))
    if level == powerUp.level and a > 0.7:
      let pulse = sin(time * 4.0) * 0.3 + 0.7
      drawRectangle(sStart, yOff, sW, PROGRESS_BAR_HEIGHT,
                   Color(r: 255, g: 255, b: 255, a: uint8(40.0 * pulse)))
  drawRectangleLines(Rectangle(x: float32(x + 12), y: yOff.float32,
                                width: barWidth.float32, height: PROGRESS_BAR_HEIGHT.float32),
                    2.0, Color(r: 80, g: 95, b: 115, a: 255))
  let levelText = "TIER " & $powerUp.level & " / " & $maxTiers
  let levelWidth = measureText(levelText, 12)
  let textBgX = x + 12 + (barWidth - levelWidth - 8) div 2
  drawRectangle(textBgX, yOff + 3, levelWidth + 8, 16, Color(r: 20, g: 25, b: 35, a: 220))
  drawText(levelText, textBgX + 4, yOff + 5, 12, White)
  yOff += PROGRESS_BAR_HEIGHT + 18

  # Description box
  let descBoxHeight: int32 = 105
  drawRectangle(x + 10, yOff, width - 20, descBoxHeight, Color(r: 18, g: 22, b: 32, a: 255))
  drawRectangle(x + 10, yOff, width - 20, 2, Color(r: 0, g: 140, b: 200, a: 80))
  drawRectangleLines(Rectangle(x: float32(x + 10), y: yOff.float32,
                                width: float32(width - 20), height: descBoxHeight.float32),
                    2.0, Color(r: 60, g: 80, b: 100, a: 255))
  let desc = getPowerUpDescription(powerUp.powerType, powerUp.level, playerDamage)
  let maxLineWidth = width - 44
  let availTextHeight = descBoxHeight - 20   # 12px top pad + ~8px bottom pad
  # Shrink the font (14 -> 9) until the wrapped description fits the box height,
  # so long descriptions (e.g. legendaries, longer languages) are never clipped.
  var descFont: int32 = 14
  var descLines: seq[string] = @[]
  for fs in countdown(14'i32, 9'i32):
    descFont = fs
    descLines = wrapTextLines(desc, maxLineWidth, fs)
    if int32(descLines.len) * (fs + 6) <= availTextHeight:
      break
  let lineH = descFont + 6
  let maxLines = max(1'i32, availTextHeight div lineH)
  # Center the block vertically: a wide (16:9) card wraps the same text into
  # fewer lines, and top-aligning them would leave a growing void underneath.
  let shownLines = min(int32(descLines.len), maxLines)
  let textTop = max(yOff + 10, yOff + (descBoxHeight - shownLines * lineH) div 2)
  for i, line in descLines:
    if int32(i) >= maxLines: break
    drawText(line, x + 22, textTop + int32(i) * lineH, descFont,
             Color(r: 220, g: 230, b: 240, a: 255))
  yOff += descBoxHeight + 8

  # Footer
  drawText("[P]", x + 10, yOff, 14, Color(r: 100, g: 110, b: 120, a: 255))
  drawText(".exe", x + 30, yOff + 2, 12, Color(r: 120, g: 130, b: 140, a: 255))
  let sizeText = $(128 + powerUp.level * 64) & " KB"
  let sizeWidth = measureText(sizeText, 11)
  drawText(sizeText, x + width - sizeWidth - 10, yOff + 2, 11, Color(r: 110, g: 120, b: 130, a: 255))

# Rolling effects

proc drawSlotLockEffect(cardX, cardY, cardW, cardH: int32,
                        tSinceLock: float32, isLegendary: bool,
                        powerUpName: string) =
  ## Called once per slot, outside scissor mode, to draw the lock-in burst.
  ## tSinceLock: seconds since this slot stopped (must be >= 0 and < ~1.2 to be visible)
  const dur = 1.1'f32
  if tSinceLock < 0.0'f32 or tSinceLock > dur: return

  # Accent colour
  let ac = if isLegendary: Color(r: 255, g: 215, b: 0, a: 255)
           else:           Color(r: 60, g: 210, b: 255, a: 255)

  # 1. Expanding outline ring
  let ringProgress = clamp(tSinceLock * 2.5'f32, 0.0'f32, 1.0'f32)
  let ringA = uint8(255.0 * (1.0 - ringProgress) * (1.0 - ringProgress))
  if ringA > 0:
    let expansion = ringProgress * 35.0'f32
    drawRectangleLines(
      Rectangle(x: float32(cardX) - expansion,
                y: float32(cardY) - expansion,
                width: float32(cardW) + expansion * 2.0,
                height: float32(cardH) + expansion * 2.0),
      max(1.0, 4.0 * (1.0 - ringProgress)),
      withAlpha(ac, ringA))

  # 3. Particle burst (16 particles radiating outward)
  let pFade = 1.0'f32 - clamp(tSinceLock * 1.8'f32, 0.0'f32, 1.0'f32)
  if pFade > 0.0:
    let cx = cardX.float32 + cardW.float32 * 0.5
    let cy = cardY.float32 + cardH.float32 * 0.5
    let dist = tSinceLock * 180.0
    for i in 0..<16:
      let angle = float32(i) / 16.0 * PI * 2.0
      let px = cx + cos(angle) * dist
      let py = cy + sin(angle) * dist * 0.55  # flatten ellipse
      let pSize = max(1.5, 5.5 * pFade)
      let pA = uint8(240.0 * pFade * pFade)
      drawCircle(Vector2(x: px, y: py), pSize, withAlpha(ac, pA))

  # 4. Rising name text (floats upward and fades)
  let textFade = 1.0'f32 - clamp(tSinceLock * 1.4'f32, 0.0'f32, 1.0'f32)
  if textFade > 0.0:
    let rise = tSinceLock * 60.0
    let tA = uint8(255.0 * textFade * textFade)
    let nameW = measureText(powerUpName, 18)
    let nx = cardX + (cardW - nameW) div 2
    let ny = int32(float32(cardY) + cardH.float32 * 0.42 - rise)
    drawText(powerUpName, nx + 2, ny + 2, 18, Color(r: 0, g: 0, b: 0, a: tA))
    drawText(powerUpName, nx, ny, 18, withAlpha(ac, tA))

proc drawOSPowerUpInstaller*(game: Game) =
  ## Draw the power-up selection screen with slot machine roll animation.
  let screenWidth  = getVirtualScreenWidth()
  let screenHeight = getVirtualScreenHeight()
  let isLegendary  = game.powerUpChoices[0].rarity == prLegendary

  # Stop times: must match powerup.nim exactly
  let stopTimes: array[3, float32] = [
    if isLegendary: 2.0'f32 else: 1.5'f32,
    if isLegendary: 3.0'f32 else: 2.5'f32,
    if isLegendary: 4.5'f32 else: 3.5'f32]

  # Per-slot: how many seconds since it locked (-1 = still rolling)
  var tSinceLock: array[3, float32]
  for i in 0..2:
    tSinceLock[i] =
      if not game.rollAnimationActive: 9999.0'f32
      elif game.rollAnimationTimer >= stopTimes[i]: game.rollAnimationTimer - stopTimes[i]
      else: -1.0'f32

  # Fastest current scroll speed across all slots (0 when idle)
  let maxSpeed: float32 =
    if game.rollAnimationActive:
      max(game.rollSpeed[0], max(game.rollSpeed[1], game.rollSpeed[2]))
    else: 0.0'f32
  let speedFrac = clamp(maxSpeed / 1000.0'f32, 0.0'f32, 1.0'f32)

  # Background overlay
  drawRectangle(0, 0, screenWidth, screenHeight, Color(r: 0, g: 0, b: 0, a: 180))

  # Window (widens in 16:9 -- see installerLayout)
  let L = installerLayout()
  let winX = L.winX
  let winY = L.winY
  let winW = L.winW
  let winH = L.winH

  # Shadow
  for i in 1..4:
    let off = int32(i * 2)
    drawRectangle(winX + off, winY + off, winW, winH,
                 Color(r: 0, g: 0, b: 0, a: uint8(50 - i * 8)))

  # Body
  drawRectangle(winX, winY, winW, winH, Color(r: 26, g: 32, b: 44, a: 255))

  # Subtle grid lines
  for i in 0..<(winH div 40):
    drawRectangle(winX, winY + int32(i * 40), winW, 1, Color(r: 30, g: 36, b: 48, a: 255))

  # Border: pulses chromatically while rolling
  if speedFrac > 0.02:
    let h = game.time * 4.0
    let r8 = uint8(127 + int(128.0 * sin(h)))
    let g8 = uint8(127 + int(128.0 * sin(h + 2.094)))
    let b8 = uint8(127 + int(128.0 * sin(h + 4.189)))
    for gi in 1..3:
      let go = gi.int32
      drawRectangleLines(
        Rectangle(x: float32(winX - go), y: float32(winY - go),
                  width: float32(winW + go * 2), height: float32(winH + go * 2)),
        1.0, Color(r: r8, g: g8, b: b8, a: uint8(int(50 * speedFrac) div gi)))
    drawRectangleLines(Rectangle(x: winX.float32, y: winY.float32,
                                  width: winW.float32, height: winH.float32),
                      4.0, Color(r: r8, g: g8, b: b8, a: 255))
  else:
    drawRectangleLines(Rectangle(x: winX.float32, y: winY.float32,
                                  width: winW.float32, height: winH.float32),
                      4.0, Color(r: 0, g: 180, b: 255, a: 255))
  drawRectangleLines(Rectangle(x: float32(winX + 2), y: float32(winY + 2),
                                width: float32(winW - 4), height: float32(winH - 4)),
                    1.0, Color(r: 60, g: 75, b: 95, a: 255))

  # Title bar
  drawRectangle(winX, winY, winW, TITLE_BAR_HEIGHT, Color(r: 40, g: 52, b: 70, a: 255))
  drawRectangle(winX, winY, winW, 2, Color(r: 80, g: 100, b: 130, a: 255))
  drawRectangle(winX, winY + TITLE_BAR_HEIGHT - 1, winW, 1, Color(r: 0, g: 140, b: 200, a: 255))

  let titleText = "[*] " & (if isLegendary: t(tkPowerUpInstallerTitle) else: t(tkPowerUpInstallerTitleGeneric))
  let titleColor = if isLegendary: Gold else: Color(r: 100, g: 200, b: 255, a: 255)
  drawText(titleText, winX + 17, winY + 13, 22, Color(r: 0, g: 0, b: 0, a: 120))
  drawText(titleText, winX + 15, winY + 11, 22, titleColor)

  let btnSz = L.closeSize
  let closeY = L.closeY
  let closeX = L.closeX
  drawRectangle(closeX, closeY, btnSz, btnSz, Color(r: 220, g: 50, b: 50, a: 255))
  drawRectangleLines(Rectangle(x: closeX.float32, y: closeY.float32,
                                width: btnSz.float32, height: btnSz.float32),
                    1.0, Color(r: 180, g: 30, b: 30, a: 255))
  drawText("X", closeX + 8, closeY + 5, 18, White)

  # Instruction header
  var yPos = winY + TITLE_BAR_HEIGHT + 20
  let headerText =
    if game.rollAnimationActive: t(tkPowerUpRolling)
    else:                        t(tkPowerUpSelectUpgrade)
  let hpulse = if game.rollAnimationActive:
                 0.55'f32 + 0.45'f32 * sin(game.time * 10.0)
               else: 1.0'f32
  let hColor =
    if game.rollAnimationActive:
      (if isLegendary: Color(r: 255, g: 220, b: 60, a: uint8(255.0 * hpulse))
       else:           Color(r: 60,  g: 210, b: 255, a: uint8(255.0 * hpulse)))
    else:
      Color(r: 200, g: 220, b: 240, a: 255)
  let headerW = measureText(headerText, 20)
  drawText(headerText, winX + (winW - headerW) div 2, yPos, 20, hColor)

  # Card area
  yPos = L.cardsY
  let cardW = L.cardW
  let cardHi = L.cardH

  # ROLLING MODE
  if game.rollAnimationActive:
    for i in 0..2:
      let cardX = L.cardX(i)
      let cardY = yPos

      let position = game.rollPosition[i]
      let cardH    = cardHi.float32

      # Index of the card whose top edge is at or just above the viewport top
      let firstIdx = int(position / cardH)
      # How many pixels the first card is scrolled above the top of the viewport
      let offsetY  = -(position - float32(firstIdx) * cardH)

      # Alpha: 1 when slow/stopped, fades toward 0.25 at full speed
      let cardAlpha = clamp(1.0'f32 - speedFrac * 0.75'f32, 0.25'f32, 1.0'f32)

      # Draw cards through the slot viewport
      beginVirtualScissorMode(cardX, cardY, cardW, cardHi)

      # j=0: card above viewport (needed when offsetY is non-zero)
      # j=1: primary card in viewport
      # j=2: card below viewport (fills gap at bottom)
      for j in 0..2:
        let idx = firstIdx + j - 1
        if idx >= 0 and idx < game.rollPowerUpList[i].len:
          let drawY = int32(float32(cardY) + offsetY + float32(j - 1) * cardH)
          drawProcessCard(cardX, drawY, cardW, cardHi,
                         game.rollPowerUpList[i][idx],
                         false, game.time, game.player.damage, cardAlpha)

      endScissorMode()

      # Speed streak lines along left edge of each slot when fast
      if speedFrac > 0.3:
        for s in 0..4:
          let streakOffset = int32(s) * (cardHi div 5)
          let streakA = uint8(70.0 * speedFrac * (1.0 - float32(s) / 5.0))
          let sc = if isLegendary: Color(r: 255, g: 215, b: 0, a: streakA)
                   else:           Color(r: 0, g: 180, b: 255, a: streakA)
          drawRectangle(cardX, cardY + streakOffset, 3, cardHi div 5, sc)
          drawRectangle(cardX + cardW - 3, cardY + streakOffset, 3, cardHi div 5, sc)

  # SETTLED MODE
  else:
    # Spotlight glow behind selected card
    let selX = L.cardX(game.selectedPowerUp)
    let glowCX = selX.float32 + cardW.float32 * 0.5
    let glowCY = yPos.float32 + cardHi.float32 * 0.5
    let gp = 0.55'f32 + 0.45'f32 * sin(game.time * 4.5)
    for gl in 1..6:
      let gR = 50.0'f32 + gl.float32 * 30.0'f32
      let gA = uint8(float32(55 - gl * 8) * gp)
      let gc = if isLegendary: Color(r: 255, g: 215, b: 0, a: gA)
               else:           Color(r: 0, g: 180, b: 255, a: gA)
      drawCircle(Vector2(x: glowCX, y: glowCY), gR, gc)

    for i in 0..2:
      drawProcessCard(L.cardX(i), yPos, cardW, cardHi,
                     game.powerUpChoices[i],
                     i == game.selectedPowerUp,
                     game.time, game.player.damage, 1.0)

  # Lock-in burst effects (drawn outside any scissor mode)
  for i in 0..2:
    let name = getPowerUpName(game.powerUpChoices[i].powerType)
    drawSlotLockEffect(L.cardX(i), yPos, cardW, cardHi, tSinceLock[i], isLegendary, name)

  # Bottom panel
  let bottomY = L.bottomY
  drawRectangle(winX, bottomY - 15, winW, 120, Color(r: 30, g: 38, b: 52, a: 255))
  drawRectangle(winX, bottomY - 15, winW, 2, Color(r: 0, g: 140, b: 200, a: 255))

  # Coin counter
  let coinBoxX: int32 = winX + 50
  let coinBoxY: int32 = bottomY + 15
  let coinBoxW: int32 = 200
  let coinBoxH: int32 = 50
  drawRectangle(coinBoxX, coinBoxY, coinBoxW, coinBoxH, Color(r: 40, g: 50, b: 30, a: 255))
  drawRectangle(coinBoxX, coinBoxY, coinBoxW, 2, Color(r: 255, g: 220, b: 0, a: 60))
  drawRectangleLines(Rectangle(x: coinBoxX.float32, y: coinBoxY.float32,
                                width: coinBoxW.float32, height: coinBoxH.float32),
                    2.0, Color(r: 255, g: 215, b: 0, a: 200))
  let cIX = coinBoxX + 15
  let cIY = coinBoxY + 25
  drawCurrencyIcon(cIX, cIY, 26, ciCredits)
  let coinText = $game.player.coins & " credits"
  drawText(coinText, coinBoxX + 40, coinBoxY + 10, 18, Color(r: 0, g: 0, b: 0, a: 120))
  drawText(coinText, coinBoxX + 38, coinBoxY + 8, 18, Color(r: 255, g: 240, b: 100, a: 255))
  drawText(t("shop_available_balance"), coinBoxX + 40, coinBoxY + 30, 10, Color(r: 180, g: 180, b: 150, a: 255))

  # Reroll button
  let buttonY    = L.rerollY
  let buttonH    = L.rerollH
  let rerollW    = L.rerollW
  let rerollX    = L.rerollX
  let canAfford  = game.player.coins >= game.rerollCost
  let mousePos   = getVirtualMousePosition()
  let rerollHovered = checkCollisionPointRec(mousePos, L.rerollRect())
  drawModernButton(rerollX, buttonY, rerollW, buttonH,
                  t(tkPowerUpRerollOptions), canAfford, canAfford and rerollHovered, game.time)
  let costText  = $game.rerollCost & " credits"
  let costW     = measureText(costText, 12)
  drawText(costText, rerollX + (rerollW - costW) div 2, buttonY + buttonH + 8, 12,
          if canAfford: Color(r: 255, g: 215, b: 0, a: 255) else: Color(r: 120, g: 120, b: 130, a: 255))
  drawText("[R]", rerollX + rerollW + 10, buttonY + 13, 14, Color(r: 200, g: 200, b: 200, a: 255))

proc drawPowerUpInstallerExhausted*(game: Game) =
  ## Shown in place of the normal installer when every power-up in the pool is
  ## already at its maximum level. Displays a completion badge and a Continue button.
  let screenWidth  = getVirtualScreenWidth()
  let screenHeight = getVirtualScreenHeight()

  drawRectangle(0, 0, screenWidth, screenHeight, Color(r: 0, g: 0, b: 0, a: 180))

  let L = installerLayout()
  let winX = L.winX
  let winY = L.winY
  let winW = L.winW
  let winH = L.winH

  # Shadow
  for i in 1..4:
    let off = int32(i * 2)
    drawRectangle(winX + off, winY + off, winW, winH,
                 Color(r: 0, g: 0, b: 0, a: uint8(50 - i * 8)))

  # Body
  drawRectangle(winX, winY, winW, winH, Color(r: 26, g: 32, b: 44, a: 255))

  # Subtle grid lines
  for i in 0..<(winH div 40):
    drawRectangle(winX, winY + int32(i * 40), winW, 1, Color(r: 30, g: 36, b: 48, a: 255))

  # Border, green pulse to signal completion
  let borderPulse = 0.7'f32 + 0.3'f32 * sin(game.time * 2.0)
  drawRectangleLines(Rectangle(x: winX.float32, y: winY.float32,
                                width: winW.float32, height: winH.float32),
                    4.0, Color(r: 50, g: 220, b: 120, a: uint8(255.0 * borderPulse)))
  drawRectangleLines(Rectangle(x: float32(winX + 2), y: float32(winY + 2),
                                width: float32(winW - 4), height: float32(winH - 4)),
                    1.0, Color(r: 60, g: 75, b: 95, a: 255))

  # Title bar
  drawRectangle(winX, winY, winW, TITLE_BAR_HEIGHT, Color(r: 40, g: 52, b: 70, a: 255))
  drawRectangle(winX, winY, winW, 2, Color(r: 80, g: 100, b: 130, a: 255))
  drawRectangle(winX, winY + TITLE_BAR_HEIGHT - 1, winW, 1, Color(r: 50, g: 220, b: 120, a: 255))

  let titleText = "[OK] " & t(tkPowerUpAllInstalled)
  let titleColor = Color(r: 80, g: 220, b: 140, a: 255)
  drawText(titleText, winX + 17, winY + 13, 22, Color(r: 0, g: 0, b: 0, a: 120))
  drawText(titleText, winX + 15, winY + 11, 22, titleColor)

  # Close (X) button
  let btnSz = L.closeSize
  let closeY = L.closeY
  let closeX = L.closeX
  drawRectangle(closeX, closeY, btnSz, btnSz, Color(r: 220, g: 50, b: 50, a: 255))
  drawRectangleLines(Rectangle(x: closeX.float32, y: closeY.float32,
                                width: btnSz.float32, height: btnSz.float32),
                    1.0, Color(r: 180, g: 30, b: 30, a: 255))
  drawText("X", closeX + 8, closeY + 5, 18, White)

  # --- Completion badge (large circle with a geometric checkmark) ---
  let badgeR  = 70.0'f32
  let badgeCX = winX.float32 + winW.float32 * 0.5
  let badgeCY = winY.float32 + TITLE_BAR_HEIGHT.float32 + 130.0
  let pulse   = 0.75'f32 + 0.25'f32 * sin(game.time * 2.5)

  # Glow rings
  for i in 1..5:
    let gr = badgeR + float32(i * 14)
    let ga = uint8(float32(35 - i * 6) * pulse)
    drawCircle(Vector2(x: badgeCX, y: badgeCY), gr,
              Color(r: 50, g: 220, b: 120, a: ga))

  # Badge fill
  drawCircle(Vector2(x: badgeCX, y: badgeCY), badgeR,
            Color(r: 20, g: 45, b: 30, a: 255))
  drawCircle(Vector2(x: badgeCX, y: badgeCY), badgeR,
            Color(r: 50, g: 220, b: 120, a: uint8(35.0 * pulse)))

  # Checkmark: two line segments with thickness
  let ck = Color(r: 80, g: 240, b: 150, a: 255)
  let ckMidX  = badgeCX - badgeR * 0.08
  let ckMidY  = badgeCY + badgeR * 0.18
  drawLine(
    Vector2(x: badgeCX - badgeR * 0.50, y: badgeCY + badgeR * 0.00),
    Vector2(x: ckMidX,                  y: ckMidY),
    4.0, ck)
  drawLine(
    Vector2(x: ckMidX,                  y: ckMidY),
    Vector2(x: badgeCX + badgeR * 0.48, y: badgeCY - badgeR * 0.42),
    4.0, ck)

  # Badge outline
  let outlinePulseA = uint8(200.0 * pulse)
  for di in [-1'i32, 0'i32, 1'i32]:
    drawCircle(Vector2(x: badgeCX, y: badgeCY), badgeR + float32(di) * 1.5,
              Color(r: 80, g: 220, b: 140, a: if di == 0: outlinePulseA else: 60))

  # --- Heading ---
  let headY = int32(badgeCY + badgeR + 28.0)
  let headText = t(tkPowerUpAllInstalled)
  let headW = measureText(headText, 26)
  drawText(headText, winX + (winW - headW) div 2 + 1, headY + 1, 26,
           Color(r: 0, g: 0, b: 0, a: 150))
  drawText(headText, winX + (winW - headW) div 2, headY, 26,
           Color(r: 80, g: 240, b: 150, a: 255))

  # --- Message text ---
  let msgY = headY + 40
  let msg = t(tkPowerUpAllInstalledMsg)
  let msgLines = wrapTextLines(msg, winW - 200, 14)
  for i, line in msgLines:
    let lineW = measureText(line, 14)
    drawText(line, winX + (winW - lineW) div 2, msgY + int32(i) * 22, 14,
             Color(r: 160, g: 190, b: 210, a: 255))

  # --- Continue button ---
  let continueBtnX = L.continueX
  let continueBtnY = L.continueY
  let mousePos = getVirtualMousePosition()
  let btnHovered = checkCollisionPointRec(mousePos, L.continueRect())
  drawModernButton(continueBtnX, continueBtnY, L.continueW, L.continueH,
                  t(tkPowerUpContinue), true, btnHovered, game.time)
  drawText("[ENTER]", continueBtnX + L.continueW + 12, continueBtnY + 17, 14,
           Color(r: 180, g: 180, b: 180, a: 255))

