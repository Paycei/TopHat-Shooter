import raylib, math, strutils
import ../types, ../roguelite, ../powerup_data, ../dungeon, ../localization, ../render_context, icon_drawing

# Unlock card grid constants

const
  UnlockCardW* = 210
  UnlockCardH* = 190
  UnlockCardPad* = 18
  UnlockTabH* = 40

const
  RoguelitePanelW* = 920
  RoguelitePanelH* = 620
  RogueliteCardW* = 260
  RogueliteCardH* = 250
  RogueliteCardGap* = 28
  RogueliteTitleBarH* = 42
  RogueliteCloseButtonSize* = 28
  RogueliteHeatPanelXOffset* = 45
  RogueliteHeatPanelYOffset* = 386
  RogueliteHeatPanelW* = 830
  RogueliteHeatPanelH* = 122
  RogueliteHeatPipStartX* = 18
  RogueliteHeatPipY* = 48
  RogueliteHeatPipW* = 76
  RogueliteHeatPipH* = 28
  RogueliteHeatPipGap* = 10
  RogueliteHeatStepButtonW* = 42
  RogueliteHeatStepButtonH* = 34

  PanelW = RoguelitePanelW
  PanelH = RoguelitePanelH
  CardW = RogueliteCardW
  CardH = RogueliteCardH
  CardGap = RogueliteCardGap
  TitleBarH = RogueliteTitleBarH
  CloseButtonSize = RogueliteCloseButtonSize

proc softColor(base: Color, alpha: uint8): Color =
  Color(r: base.r, g: base.g, b: base.b, a: alpha)

proc drawSoftFill(x, y, w, h: int32, topColor, bottomColor: Color) =
  let bands: int32 = 8
  let bandH = max(1'i32, h div bands)
  for i in 0..<bands:
    let t = if bands <= 1: 0.0'f32 else: i.float32 / (bands - 1).float32
    let by = y + i * bandH
    let bh = if i == bands - 1: h - bandH * i else: bandH
    let color = Color(
      r: uint8(topColor.r.float32 * (1.0'f32 - t) + bottomColor.r.float32 * t),
      g: uint8(topColor.g.float32 * (1.0'f32 - t) + bottomColor.g.float32 * t),
      b: uint8(topColor.b.float32 * (1.0'f32 - t) + bottomColor.b.float32 * t),
      a: uint8(topColor.a.float32 * (1.0'f32 - t) + bottomColor.a.float32 * t))
    drawRectangle(x, by, w, bh, color)

proc drawCornerBrackets(x, y, w, h, length, thickness: int32, color: Color) =
  drawRectangle(x, y, length, thickness, color)
  drawRectangle(x, y, thickness, length, color)
  drawRectangle(x + w - length, y, length, thickness, color)
  drawRectangle(x + w - thickness, y, thickness, length, color)
  drawRectangle(x, y + h - thickness, length, thickness, color)
  drawRectangle(x, y + h - length, thickness, length, color)
  drawRectangle(x + w - length, y + h - thickness, length, thickness, color)
  drawRectangle(x + w - thickness, y + h - length, thickness, length, color)

proc drawCircuitLines(x, y, w, h: int32, color: Color) =
  let midY = y + h div 2
  drawLine(x + 18, midY, x + 78, midY, color)
  drawLine(x + 78, midY, x + 104, y + 18, color)
  drawLine(x + w - 18, midY, x + w - 86, midY, color)
  drawLine(x + w - 86, midY, x + w - 124, y + h - 18, color)
  drawCircle(Vector2(x: (x + 78).float32, y: midY.float32), 3, color)
  drawCircle(Vector2(x: (x + w - 86).float32, y: midY.float32), 3, color)

proc drawScanlines(x, y, w, h: int32, color: Color) =
  for yy in countup(y + 6, y + h - 4, 10):
    drawLine(x + 1, yy.int32, x + w - 2, yy.int32, color)

proc roguelitePanelRect*(screenWidth, screenHeight: int32): Rectangle =
  Rectangle(
    x: ((screenWidth - PanelW) div 2).float32,
    y: ((screenHeight - PanelH) div 2).float32,
    width: PanelW.float32,
    height: PanelH.float32)

proc rogueliteCloseButtonRect*(screenWidth, screenHeight: int32): Rectangle =
  let panel = roguelitePanelRect(screenWidth, screenHeight)
  Rectangle(
    x: panel.x + PanelW.float32 - CloseButtonSize.float32 - 10,
    y: panel.y + ((TitleBarH - CloseButtonSize) div 2).float32,
    width: CloseButtonSize.float32,
    height: CloseButtonSize.float32)

proc rogueliteHeatPanelRect*(screenWidth, screenHeight: int32): Rectangle =
  let panel = roguelitePanelRect(screenWidth, screenHeight)
  Rectangle(
    x: panel.x + RogueliteHeatPanelXOffset.float32,
    y: panel.y + RogueliteHeatPanelYOffset.float32,
    width: RogueliteHeatPanelW.float32,
    height: RogueliteHeatPanelH.float32)

proc rogueliteHeatPipRect*(screenWidth, screenHeight: int32, heatLevel: int): Rectangle =
  let panel = rogueliteHeatPanelRect(screenWidth, screenHeight)
  let idx = clamp(heatLevel, RogueliteMinHeat, RogueliteMaxHeat) - RogueliteMinHeat
  Rectangle(
    x: panel.x + RogueliteHeatPipStartX.float32 +
       idx.float32 * (RogueliteHeatPipW + RogueliteHeatPipGap).float32,
    y: panel.y + RogueliteHeatPipY.float32,
    width: RogueliteHeatPipW.float32,
    height: RogueliteHeatPipH.float32)

proc rogueliteHeatDecreaseRect*(screenWidth, screenHeight: int32): Rectangle =
  let panel = rogueliteHeatPanelRect(screenWidth, screenHeight)
  Rectangle(
    x: panel.x + panel.width - 112,
    y: panel.y + 44,
    width: RogueliteHeatStepButtonW.float32,
    height: RogueliteHeatStepButtonH.float32)

proc rogueliteHeatIncreaseRect*(screenWidth, screenHeight: int32): Rectangle =
  let panel = rogueliteHeatPanelRect(screenWidth, screenHeight)
  Rectangle(
    x: panel.x + panel.width - 60,
    y: panel.y + 44,
    width: RogueliteHeatStepButtonW.float32,
    height: RogueliteHeatStepButtonH.float32)

proc locStarterName(kit: RogueliteStarterKit): string =
  case kit
  of rskOperator: t("roguelite_kit_operator")
  of rskBulwark: t("roguelite_kit_bulwark")
  of rskArcanist: t("roguelite_kit_arcanist")

proc locStarterDescription(kit: RogueliteStarterKit): string =
  case kit
  of rskOperator: t("roguelite_kit_operator_desc")
  of rskBulwark: t("roguelite_kit_bulwark_desc")
  of rskArcanist: t("roguelite_kit_arcanist_desc")

proc locFamilyName(family: RoguelitePowerFamily): string =
  case family
  of rpfCore: t("roguelite_family_core")
  of rpfShield: t("roguelite_family_shield")
  of rpfArcane: t("roguelite_family_arcane")
  of rpfFire: t("roguelite_family_fire")
  of rpfFrost: t("roguelite_family_frost")
  of rpfPoison: t("roguelite_family_poison")
  of rpfLightning: t("roguelite_family_lightning")
  of rpfWind: t("roguelite_family_wind")
  of rpfBlood: t("roguelite_family_blood")

proc locRelicName(relicType: RogueliteRelicType): string =
  case relicType
  of rrtNone: t("roguelite_relic_none")
  of rrtDiscountProtocol: t("roguelite_relic_discount")
  of rrtShardMagnet: t("roguelite_relic_shard")
  of rrtEliteDividend: t("roguelite_relic_elite")
  of rrtEmergencyPatch: t("roguelite_relic_patch")
  of rrtDraftCache: t("roguelite_relic_draft")

proc locKitRequirement(kit: RogueliteStarterKit): string =
  if starterKitCost(kit) == 0:
    t("roguelite_req_default")
  else:
    t("roguelite_cost") & " " & $starterKitCost(kit) & " " & t("roguelite_shards_short")

proc drawBackdrop(game: Game, accent: Color) =
  drawRectangle(0, 0, game.screenWidth, game.screenHeight, Color(r: 5, g: 9, b: 16, a: 255))
  for x in countup(0, game.screenWidth, 48):
    drawLine(x.int32, 0, x.int32, game.screenHeight, Color(r: 24, g: 42, b: 58, a: 80))
  for y in countup(0, game.screenHeight, 48):
    drawLine(0, y.int32, game.screenWidth, y.int32, Color(r: 24, g: 42, b: 58, a: 70))
  let cx = game.screenWidth div 2
  let cy = game.screenHeight div 2
  for i in 0..3:
    drawCircleLines(cx, cy, (150 + i * 72).float32, softColor(accent, uint8(34 - i * 6)))
  drawLine(cx - 380, cy, cx + 380, cy, softColor(accent, 38))
  drawLine(cx, cy - 260, cx, cy + 260, softColor(accent, 38))

proc drawThemeGlyph(cx, cy: int32, theme: DungeonFloorTheme, color: Color) =
  ## Large card glyph for each floor theme, desktop-OS flavored.
  case theme
  of dftFirewall:
    for i in 0..2:
      let ix = i.int32
      drawLine(cx - 16 + ix * 11, cy - 15, cx - 5 + ix * 11, cy + 15, color)
    drawRectangleLines(cx - 18, cy - 14, 36, 28, softColor(color, 180))
  of dftRecycleBin:
    drawRectangleLines(cx - 12, cy - 8, 24, 24, color)
    drawLine(cx - 16, cy - 12, cx + 16, cy - 12, color)
    drawLine(cx - 4, cy - 17, cx + 4, cy - 17, color)
    drawLine(cx - 5, cy - 2, cx - 5, cy + 10, softColor(color, 200))
    drawLine(cx, cy - 2, cx, cy + 10, softColor(color, 200))
    drawLine(cx + 5, cy - 2, cx + 5, cy + 10, softColor(color, 200))
  of dftRegistry:
    drawLine(cx - 14, cy - 14, cx - 14, cy + 14, color)
    for i in 0..2:
      let iy = cy - 12 + i.int32 * 12
      drawLine(cx - 14, iy, cx - 2, iy, color)
      drawRectangleLines(cx - 2, iy - 5, 16, 10, softColor(color, 210))
  of dftNetwork:
    drawCircleLines(cx - 13, cy + 10, 6'f32, color)
    drawCircleLines(cx + 14, cy + 6, 6'f32, color)
    drawCircleLines(cx + 1, cy - 13, 6'f32, color)
    drawLine(cx - 9, cy + 6, cx - 2, cy - 8, color)
    drawLine(cx + 10, cy + 2, cx + 4, cy - 8, color)
    drawLine(cx - 7, cy + 11, cx + 8, cy + 8, color)
  of dftKernel:
    drawRectangleLines(cx - 16, cy - 16, 32, 32, softColor(color, 160))
    drawRectangleLines(cx - 10, cy - 10, 20, 20, color)
    drawRectangle(cx - 4, cy - 4, 8, 8, color)
  of dftCache:
    drawRectangleLines(cx - 16, cy - 12, 22, 18, softColor(color, 150))
    drawRectangleLines(cx - 8, cy - 5, 22, 18, color)
  of dftCorruptedSector:
    drawRectangleLines(cx - 14, cy - 12, 28, 24, color)
    drawRectangle(cx - 18, cy - 4, 12, 4, color)
    drawRectangle(cx + 4, cy + 2, 14, 4, softColor(color, 170))
    drawRectangle(cx - 6, cy - 16, 10, 3, softColor(color, 170))
    drawLine(cx - 10, cy + 16, cx + 12, cy + 16, softColor(color, 120))

proc drawKitGlyph(cx, cy: int32, kit: RogueliteStarterKit, color: Color,
                  compact: bool = false) =
  let s: int32 = if compact: 7 else: 10
  case kit
  of rskOperator:
    # House/base shape
    drawRectangleLines(cx - s + 2, cy - s div 2, (s - 2) * 2, s, color)
    drawLine(cx - s, cy - s div 2, cx, cy - s - 2, color)
    drawLine(cx, cy - s - 2, cx + s, cy - s div 2, color)
  of rskBulwark:
    # Firewall stripes
    for i in 0..2:
      let ix = i.int32
      drawLine(cx - s + ix * ((s * 2) div 3), cy - s + 2, cx - s + 4 + ix * ((s * 2) div 3), cy + s - 2, color)
    drawRectangleLines(cx - s - 1, cy - s div 2 - 2, (s + 1) * 2, s + 4, softColor(color, 180))
  of rskArcanist:
    # Arcane triangle
    drawTriangle(
      Vector2(x: cx.float32, y: (cy - s - 1).float32),
      Vector2(x: (cx - s).float32, y: (cy + s - 3).float32),
      Vector2(x: (cx + s).float32, y: (cy + s - 3).float32),
      softColor(color, 85))
    drawTriangleLines(
      Vector2(x: cx.float32, y: (cy - s - 1).float32),
      Vector2(x: (cx - s).float32, y: (cy + s - 3).float32),
      Vector2(x: (cx + s).float32, y: (cy + s - 3).float32),
      color)

proc drawSurgeGlyph(cx, cy: int32, color: Color, compact: bool = false) =
  let r: int32 = if compact: 7 else: 10
  drawCircleLines(cx, cy, r.float32, color)
  drawLine(cx, cy - r - 2, cx, cy + r + 2, color)
  drawLine(cx - r - 2, cy, cx + r + 2, cy, color)

proc drawMeter(x, y, w, h: int32, value: float32, color: Color) =
  drawRectangle(x, y, w, h, Color(r: 30, g: 36, b: 48, a: 255))
  drawRectangle(x, y, int32(w.float32 * clamp(value, 0.0'f32, 1.0'f32)), h, softColor(color, 210))
  drawRectangleLines(x, y, w, h, softColor(color, 210))

type TextAlign = enum
  taLeft, taCenter, taRight

proc bestFitFontSize(text: string, maxWidth, preferredSize: int32, minSize: int32 = 9): int32 =
  result = preferredSize
  if maxWidth <= 0:
    return
  while result > minSize and measureText(text, result) > maxWidth:
    dec result

proc drawTextFit(text: string, x, y, maxWidth, fontSize: int32, color: Color,
                 minSize: int32 = 9, align: TextAlign = taLeft): int32 {.discardable.} =
  result = bestFitFontSize(text, maxWidth, fontSize, minSize)
  let textW = measureText(text, result)
  let drawX = case align
    of taLeft: x
    of taCenter: x + max(0'i32, (maxWidth - textW) div 2)
    of taRight: x + max(0'i32, maxWidth - textW)
  drawText(text, drawX, y, result, color)

proc drawCenteredTextFit*(text: string, x, y, maxWidth, fontSize: int32, color: Color,
                          minSize: int32 = 9): int32 {.discardable.} =
  drawTextFit(text, x, y, maxWidth, fontSize, color, minSize, taCenter)

proc wrapTextLines(text: string, maxWidth, fontSize: int32): seq[string] =
  let words = text.splitWhitespace()
  if words.len == 0:
    return @[]

  var currentLine = ""
  for word in words:
    let candidate = if currentLine.len == 0: word else: currentLine & " " & word
    if currentLine.len == 0 or measureText(candidate, fontSize) <= maxWidth:
      currentLine = candidate
    else:
      result.add(currentLine)
      currentLine = word

  if currentLine.len > 0:
    result.add(currentLine)

proc bestWrapFontSize(text: string, maxWidth, preferredSize, maxLines: int32,
                      minSize: int32 = 9): int32 =
  result = preferredSize
  if maxWidth <= 0:
    return
  while result > minSize:
    let lines = wrapTextLines(text, maxWidth, result)
    if lines.len <= maxLines.int:
      break
    dec result

proc drawWrappedText(text: string, x, y, maxWidth, fontSize: int32,
                     color: Color, maxLines: int32 = 3, lineGap: int32 = 5,
                     minSize: int32 = 9): int32 =
  result = y
  if maxLines <= 0:
    return

  let wrappedFontSize = bestWrapFontSize(text, maxWidth, fontSize, maxLines, minSize)
  let lines = wrapTextLines(text, maxWidth, wrappedFontSize)
  let linesToDraw = min(lines.len, maxLines.int)
  for idx in 0..<linesToDraw:
    drawText(lines[idx], x, result, wrappedFontSize, color)
    result += wrappedFontSize + lineGap

proc rectAt(x, y, w, h: int32): Rectangle =
  Rectangle(x: x.float32, y: y.float32, width: w.float32, height: h.float32)

proc drawBetaBanner*(game: Game) =
  ## Centered translucent BETA banner drawn at the top of the screen.
  ## Signals to players that the roguelite mode is work-in-progress.
  let bannerW: int32 = 260
  let bannerX: int32 = (game.screenWidth - bannerW) div 2
  let bannerY: int32 = 8
  let pulse = (sin(game.time * 2.0'f32) * 0.5'f32 + 0.5'f32)
  let textAlpha = uint8(160 + int(pulse * 40.0'f32))
  let textColor = Color(r: 220, g: 205, b: 140, a: textAlpha)
  let label = t("roguelite_beta_banner")
  discard drawCenteredTextFit(label, bannerX + 6, bannerY + 8,
                               bannerW - 12, 12, textColor, 9)

proc drawCloseButton(x, y: int32, color: Color, hovered: bool = false) =
  let bg = if hovered:
    Color(r: 72, g: 36, b: 42, a: 255)
  else:
    Color(r: 38, g: 44, b: 56, a: 245)
  let lineColor = if hovered: Color(r: 255, g: 150, b: 150, a: 255) else: LightGray
  drawRectangle(x, y, CloseButtonSize, CloseButtonSize, bg)
  drawRectangleLines(rectAt(x, y, CloseButtonSize, CloseButtonSize),
                     if hovered: 2 else: 1,
                     if hovered: Color(r: 255, g: 110, b: 110, a: 255) else: softColor(color, 180))
  drawLine(x + 8, y + 8, x + CloseButtonSize - 8, y + CloseButtonSize - 8, lineColor)
  drawLine(x + CloseButtonSize - 8, y + 8, x + 8, y + CloseButtonSize - 8, lineColor)

proc drawStatChip*(x, y, w, h: int32, label, value: string, color: Color,
                  icon: CurrencyIconType = ciNone) =
  drawRectangle(x + 3, y + 3, w, h, Color(r: 0, g: 0, b: 0, a: 90))
  drawSoftFill(x, y, w, h, Color(r: 26, g: 36, b: 54, a: 244),
               Color(r: 12, g: 18, b: 30, a: 244))
  drawRectangle(x, y, w, 2, softColor(color, 145))
  drawRectangle(x, y, 5, h, softColor(color, 215))
  drawRectangleLines(rectAt(x, y, w, h), 1, softColor(color, 135))
  let textX = if icon == ciNone: x + 14 else: x + 46
  let textW = w - (textX - x) - 12
  if icon != ciNone:
    drawCircle(Vector2(x: (x + 24).float32, y: (y + h div 2).float32), 17, softColor(color, 26))
    drawCircleLines(x + 24, y + h div 2, 17.0'f32, softColor(color, 75))
    drawCurrencyIcon(x + 24, y + h div 2, 24, icon)
  drawTextFit(label, textX, y + 7, textW, 10, Color(r: 156, g: 172, b: 196, a: 255), 8)
  drawTextFit(value, textX, y + 22, textW, 19, color, 10)

proc drawPill(x, y, w, h: int32, label: string, color: Color, filled: bool = false) =
  drawRectangle(x, y, w, h,
                if filled: softColor(color, 70) else: Color(r: 19, g: 25, b: 36, a: 225))
  drawRectangleLines(rectAt(x, y, w, h), 1, softColor(color, 170))
  let fontSize = bestFitFontSize(label, w - 8, 12, 8)
  discard drawCenteredTextFit(label, x + 4, y + (h - fontSize) div 2, w - 8, 12, color, 8)

proc drawUnlockCostsRight*(profile: RogueliteProfile, category: RogueliteUnlockCategory, index: int,
                          rightX, topY, iconSize, fontSize: int32, color: Color) =
  ## Draw unlock costs right-aligned starting from rightX. Shows icons and amounts.
  var rx = rightX
  let shardCost = unlockCost(profile, category, index)
  let coreCost = unlockCoreCost(profile, category, index)
  var parts: seq[tuple[icon: CurrencyIconType, amount: int]] = @[]
  if coreCost > 0:
    parts.add((icon: ciCore, amount: coreCost))
  if shardCost > 0:
    parts.add((icon: ciDataShards, amount: shardCost))

  let paddingBetween: int32 = 6
  let interPartGap: int32 = 8
  for i in 0..<parts.len:
    let part = parts[i]
    let txt = $part.amount
    let txtW: int32 = int32(measureText(txt, fontSize))
    let partW: int32 = iconSize + paddingBetween + txtW + interPartGap
    rx -= partW
    let leftX: int32 = rx
    let iconCenterX: int32 = leftX + iconSize div 2
    let iconCY = topY + iconSize div 2
    drawCurrencyIcon(iconCenterX, iconCY, iconSize, part.icon)
    let txtX = leftX + iconSize + paddingBetween
    let txtY = topY
    drawText(txt, txtX, txtY, fontSize, color)

proc drawHeatStepButton(rect: Rectangle, label: string, enabled, hovered: bool, color: Color) =
  let x = rect.x.int32
  let y = rect.y.int32
  let w = rect.width.int32
  let h = rect.height.int32
  let bg = if enabled and hovered: Color(r: 70, g: 44, b: 36, a: 255)
           elif enabled: Color(r: 43, g: 37, b: 38, a: 255)
           else: Color(r: 30, g: 34, b: 43, a: 235)
  drawRectangle(x + 2, y + 2, w, h, Color(r: 0, g: 0, b: 0, a: if hovered: 110 else: 70))
  drawRectangle(x, y, w, h, bg)
  drawRectangleLines(rect, if enabled and hovered: 2 else: 1,
                     if enabled: color else: Color(r: 82, g: 88, b: 102, a: 255))
  discard drawCenteredTextFit(label, x + 4, y + 6, w - 8, 20,
                              if enabled: color else: Color(r: 110, g: 118, b: 132, a: 255), 12)

proc drawHeatPanel*(game: Game, x, y, w, h: int32) =
  let profile = game.rogueliteProfile
  let maxHeat = if profile.isNil: RogueliteMinHeat else: profile.highestHeat
  let selectedHeat = clamp(game.selectedRogueliteHeat, RogueliteMinHeat, maxHeat)
  let heatRank = heatChallengeRank(selectedHeat)
  let heatSpan = max(1, RogueliteMaxHeat - RogueliteMinHeat)
  let heatIntensity = heatRank.float32 / heatSpan.float32
  let heatColor = Color(r: 255, g: 150, b: 80, a: 255)
  let highHeatColor = Color(r: 255, g: 82, b: 66, a: 255)
  let canHover = game.mouseMovedRecently and not game.keyboardUsedRecently
  let mousePos = if canHover: getVirtualMousePosition() else: Vector2()
  let glowPulse = (sin(game.time * 6.0'f32) * 0.5'f32 + 0.5'f32)
  let glowAlpha = uint8(18 + heatRank * 28 + int(glowPulse * 22.0'f32))

  drawRectangle(x + 3, y + 3, w, h, Color(r: 0, g: 0, b: 0, a: 85))
  drawRectangle(x, y, w, h, Color(r: 20, g: 25, b: 37, a: 245))
  drawRectangle(x + 5, y + 5, w - 10, h - 10, Color(r: 95, g: 39, b: 26, a: glowAlpha))
  drawRectangle(x, y, 5, h, softColor(heatColor, 230))
  drawRectangleLines(x, y, w, h, Color(r: 255, g: 130, b: 80, a: 220))

  if game.rogueliteHeatPulseTimer > 0:
    let pulseT = clamp(game.rogueliteHeatPulseTimer / 0.45'f32, 0.0'f32, 1.0'f32)
    let pulseAlpha = uint8(max(0, min(190, int(pulseT * 190.0'f32))))
    let pulseColor = if game.rogueliteHeatPulseDirection >= 0: highHeatColor
                     else: Color(r: 120, g: 210, b: 255, a: 255)
    drawRectangleLines(Rectangle(x: (x - 2).float32, y: (y - 2).float32,
                                 width: (w + 4).float32, height: (h + 4).float32),
                       3, softColor(pulseColor, pulseAlpha))
    drawTextFit(if game.rogueliteHeatPulseDirection >= 0: "+HEAT" else: "-HEAT",
                x + w - 194, y + 14, 74, 15, softColor(pulseColor, pulseAlpha))

  drawCurrencyIcon(x + 29, y + 22, 24, ciHeat)
  drawTextFit(t("roguelite_heat") & " " & $selectedHeat,
              x + 46, y + 12, 92, 20, heatColor)
  drawTextFit($maxHeat & " / " & $RogueliteMaxHeat,
              x + 144, y + 14, 84, 13, LightGray)
  let heatDifficultyPercent = int(round(heatRank.float32 *
    RogueliteHeatDifficultyPerTier * 100.0'f32))
  let heatBossPercent = int(round(heatRank.float32 *
    RogueliteHeatBossDifficultyPerTier * 100.0'f32))
  drawTextFit(t("roguelite_heat_effects") & ": +" & $heatDifficultyPercent & "% " &
              t("roguelite_pressure") & ", +" & $heatBossPercent & "% " &
              t("roguelite_boss") & ", " & t("roguelite_cores"),
              x + 230, y + 13, w - 370, 13, LightGray)

  let pipStart = x + RogueliteHeatPipStartX
  let pipY = y + RogueliteHeatPipY
  for i in 0..<RogueliteMaxHeat:
    let heatLevel = RogueliteMinHeat + i
    let px = pipStart + i.int32 * (RogueliteHeatPipW + RogueliteHeatPipGap)
    let pipRect = rectAt(px, pipY, RogueliteHeatPipW, RogueliteHeatPipH)
    let unlocked = heatLevel <= maxHeat
    let selected = heatLevel == selectedHeat
    let active = heatLevel <= selectedHeat
    let hovered = canHover and checkCollisionPointRec(mousePos, pipRect)
    let pipColor = if selected: highHeatColor
                   elif active: heatColor
                   elif unlocked: Color(r: 190, g: 110, b: 70, a: 255)
                   else: Color(r: 78, g: 86, b: 102, a: 255)
    drawRectangle(px + 2, pipY + 2, RogueliteHeatPipW, RogueliteHeatPipH,
                  Color(r: 0, g: 0, b: 0, a: if hovered: 110 else: 70))
    drawRectangle(px, pipY, RogueliteHeatPipW, RogueliteHeatPipH,
                  if selected: Color(r: 76, g: 40, b: 32, a: 255)
                  elif hovered and unlocked: Color(r: 50, g: 43, b: 42, a: 255)
                  elif active: Color(r: 44, g: 36, b: 38, a: 245)
                  else: Color(r: 31, g: 37, b: 48, a: 245))
    drawRectangleLines(pipRect, if selected or hovered: 2 else: 1, pipColor)
    drawTextFit($heatLevel, px + 10, pipY + 5, 20, 17,
                if unlocked: White else: Color(r: 125, g: 132, b: 145, a: 255))
    drawTextFit(if heatLevel == RogueliteMinHeat: "BASE" else: "+" & $(heatLevel - RogueliteMinHeat),
                px + 33, pipY + 8, RogueliteHeatPipW - 42, 11,
                if unlocked: pipColor else: Color(r: 105, g: 112, b: 126, a: 255), 8)

    if selected and game.rogueliteHeatPulseTimer > 0:
      let pulseT = clamp(game.rogueliteHeatPulseTimer / 0.45'f32, 0.0'f32, 1.0'f32)
      let ringAlpha = uint8(max(0, min(180, int(pulseT * 180.0'f32))))
      drawCircleLines(px + RogueliteHeatPipW div 2, pipY + RogueliteHeatPipH div 2,
                      22.0'f32 + (1.0'f32 - pulseT) * 13.0'f32,
                      softColor(pipColor, ringAlpha))

  let meterX = x + 300
  let meterY = y + 54
  let meterW = w - 438
  drawTextFit(t("roguelite_pressure"), meterX, y + 39, 120, 11,
              Color(r: 180, g: 190, b: 205, a: 255))
  drawMeter(meterX, meterY, meterW, 12, heatIntensity, highHeatColor)

  let emberCount = 4 + heatRank * 4
  for ember in 0..<emberCount:
    let phase = game.time * (1.4'f32 + ember.float32 * 0.11'f32) + ember.float32 * 1.73'f32
    let ex = meterX + int32((sin(phase) * 0.5'f32 + 0.5'f32) * meterW.float32)
    let ey = y + 42 + int32((cos(phase * 1.31'f32) * 0.5'f32 + 0.5'f32) * 44.0'f32)
    let emberAlpha = uint8(70 + heatRank * 28)
    drawCircle(Vector2(x: ex.float32, y: ey.float32), (1 + heatRank).float32,
               Color(r: 255, g: 140, b: 75, a: emberAlpha))

  # Compute step-button rects relative to the panel's own x,y so they follow the window when dragged
  let decRect = Rectangle(
    x: (x + w - 112).float32,
    y: (y + 44).float32,
    width: RogueliteHeatStepButtonW.float32,
    height: RogueliteHeatStepButtonH.float32)
  let incRect = Rectangle(
    x: (x + w - 60).float32,
    y: (y + 44).float32,
    width: RogueliteHeatStepButtonW.float32,
    height: RogueliteHeatStepButtonH.float32)
  drawHeatStepButton(decRect, "-", selectedHeat > RogueliteMinHeat,
                     canHover and checkCollisionPointRec(mousePos, decRect), heatColor)
  drawHeatStepButton(incRect, "+", selectedHeat < maxHeat,
                     canHover and checkCollisionPointRec(mousePos, incRect), highHeatColor)

  if maxHeat >= RogueliteMaxHeat:
    drawTextFit(t("roguelite_heat_maxed"), x + 18, y + h - 42, w - 36, 13, Gold)
  else:
    let buyLabel = t("roguelite_heat_buy_next") & " " & $(maxHeat + 1)
    discard drawTextFit(buyLabel, x + 18, y + h - 42, 220, 13, Gold)
    # Draw the required currencies for the next heat to the right,
    # keeping clear of the -/+ step buttons (dec button starts at x + w - 112)
    drawUnlockCostsRight(profile, rucChallengeTiers, 0,
                         (x + w - 120).int32, (y + h - 44).int32, 16, 12, Gold)
  drawTextFit(t("roguelite_heat_core_rule"), x + 18, y + h - 22, w - 36, 12,
              Color(r: 180, g: 192, b: 210, a: 255), 8)

proc drawProgressRail(run: RogueliteRun, x, y, w: int32) =
  ## Floor progression: 4 themed floors, each capped by its boss.
  let totalNodes = RogueliteFloorsToWin
  let step = w div (totalNodes - 1).int32
  drawText(t("roguelite_run_flow"), x, y - 24, 15, Color(r: 150, g: 220, b: 255, a: 255))
  for i in 0..<totalNodes:
    let px = x + i.int32 * step
    if i < totalNodes - 1:
      drawLine(px, y, px + step, y, Color(r: 70, g: 95, b: 120, a: 255))
    let completed = run.floorNumber > i + 1
    let current = run.floorNumber == i + 1
    let color = if completed: Color(r: 0, g: 240, b: 160, a: 255)
                elif current: Color(r: 0, g: 220, b: 255, a: 255)
                else: Color(r: 90, g: 105, b: 125, a: 255)
    drawCircle(Vector2(x: px.float32, y: y.float32), if current: 10 else: 7, color)
    let label = t("roguelite_floor") & " " & $(i + 1)
    discard drawCenteredTextFit(label, px - (step div 2), y + 14, step, 11, LightGray, 8)

proc categoryByIndex(index: int): RogueliteUnlockCategory =
  RogueliteUnlockCategory(clamp(index, 0, 3))

proc locCategoryName(category: RogueliteUnlockCategory): string =
  case category
  of rucStarterKits: t("roguelite_unlock_cat_kits")
  of rucPowerFamilies: t("roguelite_unlock_cat_families")
  of rucRelics: t("roguelite_unlock_cat_relics")
  of rucChallengeTiers: t("roguelite_unlock_cat_challenge")

proc locUnlockName(profile: RogueliteProfile, category: RogueliteUnlockCategory, index: int): string =
  case category
  of rucStarterKits:
    locStarterName(starterByUnlockIndex(index))
  of rucPowerFamilies:
    locFamilyName(familyByUnlockIndex(index))
  of rucRelics:
    locRelicName(relicByUnlockIndex(index))
  of rucChallengeTiers:
    if index == 0:
      let nextHeat = if profile.isNil: RogueliteMinHeat + 1 else: min(RogueliteMaxHeat, profile.highestHeat + 1)
      t("roguelite_unlock_heat") & " " & $nextHeat
    else:
      let nextTier = if profile.isNil: 2 else: min(RogueliteMaxBossTier, profile.unlockedBossTier + 1)
      t("roguelite_unlock_wave_surge") & " " & $nextTier

proc locUnlockDescription(category: RogueliteUnlockCategory, index: int): string =
  case category
  of rucStarterKits:
    locStarterDescription(starterByUnlockIndex(index))
  of rucPowerFamilies:
    case familyByUnlockIndex(index)
    of rpfCore: t("roguelite_unlock_desc_family_core")
    of rpfShield: t("roguelite_unlock_desc_family_shield")
    of rpfArcane: t("roguelite_unlock_desc_family_arcane")
    of rpfFire: t("roguelite_unlock_desc_family_fire")
    of rpfFrost: t("roguelite_unlock_desc_family_frost")
    of rpfPoison: t("roguelite_unlock_desc_family_poison")
    of rpfLightning: t("roguelite_unlock_desc_family_lightning")
    of rpfWind: t("roguelite_unlock_desc_family_wind")
    of rpfBlood: t("roguelite_unlock_desc_family_blood")
  of rucRelics:
    case relicByUnlockIndex(index)
    of rrtDiscountProtocol: t("roguelite_unlock_desc_discount")
    of rrtShardMagnet: t("roguelite_unlock_desc_shard")
    of rrtDraftCache: t("roguelite_unlock_desc_draft")
    of rrtEmergencyPatch: t("roguelite_unlock_desc_patch")
    of rrtEliteDividend: t("roguelite_unlock_desc_elite")
    else: ""
  of rucChallengeTiers:
    if index == 0: t("roguelite_unlock_desc_heat")
    else: t("roguelite_unlock_desc_wave_surge")

proc drawPanel*(x, y, w, h: int32, title: string, color: Color, closeHovered: bool = false,
               omitTitleBar: bool = false) =
  drawRectangle(x + 7, y + 7, w, h, Color(r: 0, g: 0, b: 0, a: 115))
  drawSoftFill(x, y, w, h, Color(r: 17, g: 24, b: 38, a: 250),
               Color(r: 8, g: 13, b: 24, a: 250))
  drawRectangle(x + 10, y + 10, w - 20, h - 20, Color(r: 11, g: 18, b: 30, a: 52))
  drawScanlines(x + 8, y + 8, w - 16, h - 16, Color(r: 255, g: 255, b: 255, a: 6))
  drawCircuitLines(x + 14, y + 50, w - 28, h - 94, softColor(color, 24))
  if not omitTitleBar:
    drawSoftFill(x, y, w, TitleBarH, Color(r: 36, g: 54, b: 74, a: 255),
                 Color(r: 18, g: 27, b: 42, a: 255))
    drawRectangle(x, y + TitleBarH - 3, w, 3, softColor(color, 150))
  else:
    drawRectangle(x + 16, y + 13, w - 32, 34, Color(r: 16, g: 25, b: 40, a: 220))
    drawRectangle(x + 16, y + 45, w - 32, 2, softColor(color, 150))
    drawTextFit(title, x + 30, y + 21, w - 60, 18, color)
  drawRectangleLines(Rectangle(x: x.float32, y: y.float32, width: w.float32, height: h.float32), 2, softColor(color, 230))
  drawRectangleLines(Rectangle(x: (x + 5).float32, y: (y + 5).float32,
                               width: (w - 10).float32, height: (h - 10).float32),
                     1, softColor(color, 70))
  drawCornerBrackets(x + 8, y + 8, w - 16, h - 16, 28, 2, softColor(color, 185))
  if not omitTitleBar:
    drawTextFit(title, x + 18, y + 12, w - CloseButtonSize - 56, 18, color)
    drawCloseButton(x + w - CloseButtonSize - 10, y + (TitleBarH - CloseButtonSize) div 2,
                    color, closeHovered)

proc mouseHoverEnabled(game: Game): bool =
  game.mouseMovedRecently and not game.keyboardUsedRecently

proc isHovered(mousePos: Vector2, x, y, w, h: int32): bool =
  checkCollisionPointRec(mousePos, rectAt(x, y, w, h))

proc categoryColor(category: RogueliteUnlockCategory): Color =
  case category
  of rucStarterKits: Color(r: 0, g: 220, b: 255, a: 255)
  of rucPowerFamilies: Color(r: 160, g: 120, b: 255, a: 255)
  of rucRelics: Color(r: 0, g: 230, b: 170, a: 255)
  of rucChallengeTiers: Color(r: 255, g: 150, b: 80, a: 255)

proc familyColor(family: RoguelitePowerFamily): Color =
  case family
  of rpfCore: Color(r: 210, g: 220, b: 235, a: 255)
  of rpfShield: Color(r: 80, g: 200, b: 255, a: 255)
  of rpfArcane: Color(r: 190, g: 120, b: 255, a: 255)
  of rpfFire: Color(r: 255, g: 110, b: 70, a: 255)
  of rpfFrost: Color(r: 130, g: 230, b: 255, a: 255)
  of rpfPoison: Color(r: 120, g: 235, b: 110, a: 255)
  of rpfLightning: Color(r: 255, g: 235, b: 100, a: 255)
  of rpfWind: Color(r: 120, g: 245, b: 200, a: 255)
  of rpfBlood: Color(r: 255, g: 80, b: 110, a: 255)

proc drawFamilyGlyph(cx, cy: int32, family: RoguelitePowerFamily, color: Color,
                     compact: bool = false) =
  let outer: int32 = if compact: 8 else: 11
  let mid: int32 = if compact: 6 else: 8
  let inner: int32 = if compact: 2 else: 3
  let cross: int32 = if compact: 9 else: 12
  let diag: int32 = if compact: 7 else: 8
  let triTop: int32 = if compact: 9 else: 11
  let triBottom: int32 = if compact: 7 else: 9
  case family
  of rpfCore:
    drawCircleLines(cx, cy, outer.float32, color)
    drawCircle(Vector2(x: cx.float32, y: cy.float32), inner.float32, color)
  of rpfShield:
    let halfW: int32 = if compact: 7 else: 9
    let top: int32 = if compact: 8 else: 10
    let bodyH: int32 = if compact: 12 else: 15
    let pointY: int32 = if compact: 10 else: 12
    drawRectangleLines(cx - halfW, cy - top, halfW * 2, bodyH, color)
    drawLine(cx - halfW, cy + (if compact: 5 else: 8), cx, cy + pointY, color)
    drawLine(cx + halfW, cy + (if compact: 5 else: 8), cx, cy + pointY, color)
  of rpfArcane:
    drawTriangleLines(Vector2(x: cx.float32, y: (cy - triTop).float32),
                      Vector2(x: (cx - outer).float32, y: (cy + triBottom).float32),
                      Vector2(x: (cx + outer).float32, y: (cy + triBottom).float32), color)
    drawCircleLines(cx, cy, mid.float32, color)
  of rpfFire:
    let flameW: int32 = if compact: 6 else: 8
    let flameBottom: int32 = if compact: 8 else: 10
    drawTriangle(Vector2(x: cx.float32, y: (cy - triTop).float32),
                 Vector2(x: (cx - flameW).float32, y: (cy + flameBottom).float32),
                 Vector2(x: (cx + flameW).float32, y: (cy + flameBottom).float32), softColor(color, 80))
    drawTriangleLines(Vector2(x: cx.float32, y: (cy - triTop).float32),
                      Vector2(x: (cx - flameW).float32, y: (cy + flameBottom).float32),
                      Vector2(x: (cx + flameW).float32, y: (cy + flameBottom).float32), color)
  of rpfFrost:
    drawLine(cx - cross, cy, cx + cross, cy, color)
    drawLine(cx, cy - cross, cx, cy + cross, color)
    drawLine(cx - diag, cy - diag, cx + diag, cy + diag, color)
    drawLine(cx + diag, cy - diag, cx - diag, cy + diag, color)
  of rpfPoison:
    let orbOffset: int32 = if compact: 4 else: 5
    let orbRadius: int32 = if compact: 5 else: 6
    drawCircleLines(cx - orbOffset, cy + 1, orbRadius.float32, color)
    drawCircleLines(cx + orbOffset, cy + 1, orbRadius.float32, color)
    drawCircle(Vector2(x: cx.float32, y: (cy - (if compact: 7 else: 10)).float32),
               (if compact: 4 else: 4).float32, softColor(color, 160))
  of rpfLightning:
    let topY: int32 = if compact: 9 else: 11
    let leftX: int32 = if compact: 5 else: 6
    let bottomY: int32 = if compact: 9 else: 11
    drawLine(cx + 3, cy - topY, cx - leftX, cy + 1, color)
    drawLine(cx - leftX, cy + 1, cx + 3, cy + 1, color)
    drawLine(cx + 3, cy + 1, cx - 3, cy + bottomY, color)
  of rpfWind:
    let left1: int32 = if compact: 9 else: 12
    let right1: int32 = if compact: 7 else: 9
    let left2: int32 = if compact: 6 else: 8
    let right2: int32 = if compact: 9 else: 12
    let left3: int32 = if compact: 8 else: 10
    let right3: int32 = if compact: 5 else: 6
    drawLine(cx - left1, cy - (if compact: 5 else: 8), cx + right1, cy - (if compact: 5 else: 8), color)
    drawLine(cx - left2, cy + 1, cx + right2, cy + 1, color)
    drawLine(cx - left3, cy + (if compact: 7 else: 10), cx + right3, cy + (if compact: 7 else: 10), color)
  of rpfBlood:
    let dropY: int32 = if compact: 3 else: 4
    let radius: int32 = if compact: 6 else: 8
    let halfW: int32 = if compact: 5 else: 7
    let midY: int32 = if compact: 2 else: 3
    drawCircle(Vector2(x: cx.float32, y: (cy + dropY).float32), radius.float32, softColor(color, 80))
    drawTriangle(Vector2(x: cx.float32, y: (cy - triTop).float32),
                 Vector2(x: (cx - halfW).float32, y: (cy + midY).float32),
                 Vector2(x: (cx + halfW).float32, y: (cy + midY).float32), softColor(color, 110))
    drawCircleLines(cx, cy + dropY, radius.float32, color)

proc drawCategoryGlyph(cx, cy: int32, category: RogueliteUnlockCategory, color: Color,
                       compact: bool = false) =
  case category
  of rucStarterKits:
    drawKitGlyph(cx, cy, rskOperator, color, compact)
  of rucPowerFamilies:
    let outer: int32 = if compact: 9 else: 11
    let cross: int32 = if compact: 7 else: 9
    drawCircleLines(cx, cy, outer.float32, color)
    drawLine(cx - cross, cy, cx + cross, cy, color)
    drawLine(cx, cy - cross, cx, cy + cross, color)
  of rucRelics:
    let half: int32 = if compact: 7 else: 9
    drawRectangleLines(cx - half, cy - half, half * 2, half * 2, color)
    drawCircle(Vector2(x: cx.float32, y: cy.float32), if compact: 4 else: 4, color)
  of rucChallengeTiers:
    let top: int32 = if compact: 9 else: 11
    let half: int32 = if compact: 8 else: 10
    drawTriangle(Vector2(x: cx.float32, y: (cy - top).float32),
                 Vector2(x: (cx - half).float32, y: (cy + half).float32),
                 Vector2(x: (cx + half).float32, y: (cy + half).float32), softColor(color, 70))
    drawTriangleLines(Vector2(x: cx.float32, y: (cy - top).float32),
                      Vector2(x: (cx - half).float32, y: (cy + half).float32),
                      Vector2(x: (cx + half).float32, y: (cy + half).float32), color)

proc drawUnlockGlyph(profile: RogueliteProfile, category: RogueliteUnlockCategory,
                     index, cx, cy: int32, color: Color, compact: bool = false) =
  case category
  of rucStarterKits:
    drawKitGlyph(cx, cy, starterByUnlockIndex(index), color, compact)
  of rucPowerFamilies:
    let family = familyByUnlockIndex(index)
    drawFamilyGlyph(cx, cy, family, familyColor(family), compact)
  of rucRelics:
    drawCategoryGlyph(cx, cy, rucRelics, color, compact)
  of rucChallengeTiers:
    if index == 0:
      let heat = if profile.isNil: RogueliteMinHeat + 1 else: min(RogueliteMaxHeat, profile.highestHeat + 1)
      let ring: int32 = if compact: 8 else: 10
      let labelW: int32 = if compact: 10 else: 12
      let fontSize: int32 = if compact: 8 else: 10
      let textOffset: int32 = if compact: 5 else: 5
      drawCircleLines(cx, cy, ring.float32, color)
      drawTextFit($heat, cx - textOffset, cy - textOffset, labelW, fontSize, color)
    else:
      drawSurgeGlyph(cx, cy, color, compact)  # Wave Surge

proc drawSmallButton*(x, y, w, h: int32, label: string, active: bool, color: Color, hovered: bool = false) =
  let bgTop = if active: Color(r: 36, g: 86, b: 92, a: 255)
              elif hovered: Color(r: 48, g: 61, b: 82, a: 255)
              else: Color(r: 35, g: 43, b: 58, a: 255)
  let bgBottom = if active: Color(r: 18, g: 45, b: 55, a: 255)
                 elif hovered: Color(r: 29, g: 38, b: 54, a: 255)
                 else: Color(r: 22, g: 28, b: 40, a: 255)
  if hovered:
    drawRectangle(x + 3, y + 3, w, h, Color(r: 0, g: 0, b: 0, a: 105))
  drawSoftFill(x, y, w, h, bgTop, bgBottom)
  drawRectangle(x, y, w, 2, softColor(color, if active or hovered: 155 else: 80))
  drawRectangleLines(rectAt(x, y, w, h), if active or hovered: 2 else: 1,
                    if active or hovered: color else: Color(r: 82, g: 92, b: 108, a: 255))
  if active:
    drawCornerBrackets(x + 4, y + 4, w - 8, h - 8, 10, 1, softColor(color, 150))
  let fontSize = bestFitFontSize(label, w - 14, 15, 9)
  discard drawCenteredTextFit(label, x + 7, y + (h - fontSize) div 2, w - 14, 15,
                              if active or hovered: color else: LightGray, 9)

proc drawShopButton*(x, y, w, h: int32, label: string, time: float32,
                     hasDeal: bool, hovered: bool = false) =
  ## High-emphasis entry point to the Shard Unlocks shop. Unlike drawSmallButton
  ## this one is gold, breathes with a glow halo, carries a shard icon, and pops a
  ## red "!" badge when something is affordable, so it stops reading as just one
  ## of three equal-weight footer buttons.
  let gold = Color(r: 255, g: 210, b: 90, a: 255)
  let pulse = sin(time * 4.0'f32) * 0.5'f32 + 0.5'f32          # 0..1
  # Outer glow halo: a few expanding line-rects fading outward.
  let baseGlow = 46 + int(pulse * 60.0'f32) + (if hovered: 50 else: 0)
  for i in countdown(3, 1):
    let pad = i.int32 * 3
    let a = uint8(clamp(baseGlow - i * 12, 0, 255))
    drawRectangleLines(rectAt(x - pad, y - pad, w + pad * 2, h + pad * 2), 1, softColor(gold, a))
  # Drop shadow + warm body.
  drawRectangle(x + 3, y + 4, w, h, Color(r: 0, g: 0, b: 0, a: 130))
  let bgTop = if hovered: Color(r: 96, g: 72, b: 26, a: 255) else: Color(r: 74, g: 56, b: 22, a: 255)
  let bgBottom = if hovered: Color(r: 58, g: 41, b: 14, a: 255) else: Color(r: 44, g: 32, b: 12, a: 255)
  drawSoftFill(x, y, w, h, bgTop, bgBottom)
  drawScanlines(x + 4, y + 4, w - 8, h - 8, Color(r: 255, g: 255, b: 255, a: 6))
  drawRectangle(x, y, w, 3, softColor(gold, 235))
  drawRectangleLines(rectAt(x, y, w, h), if hovered: 3 else: 2,
                     softColor(gold, uint8(clamp(195 + int(pulse * 55.0'f32), 0, 255))))
  drawCornerBrackets(x + 4, y + 4, w - 8, h - 8, 12, 1, softColor(gold, 175))
  # Shard icon, left.
  let iconCX = x + 26
  let iconCY = y + h div 2
  drawCircle(Vector2(x: iconCX.float32, y: iconCY.float32), 15.0'f32,
             softColor(gold, uint8(28 + int(pulse * 30.0'f32))))
  drawCurrencyIcon(iconCX, iconCY, 22, ciDataShards)
  # Label.
  let fontSize = bestFitFontSize(label, w - 56, 16, 9)
  discard drawCenteredTextFit(label, x + 44, y + (h - fontSize) div 2, w - 56, fontSize, gold, 9)
  # Deal badge: pulsing red "!" in the upper-right corner.
  if hasDeal:
    let badgeR = 9.0'f32 + pulse * 2.0'f32
    let bx = x + w - 4
    let by = y - 2
    drawCircle(Vector2(x: bx.float32, y: by.float32), badgeR + 2.0'f32, Color(r: 0, g: 0, b: 0, a: 120))
    drawCircle(Vector2(x: bx.float32, y: by.float32), badgeR, Color(r: 255, g: 90, b: 80, a: 255))
    drawCircleLines(bx, by, badgeR, White)
    discard drawCenteredTextFit("!", bx - 7, by - 7, 14, 14, White, 12)

proc drawKitCard*(game: Game, kit: RogueliteStarterKit, x, y: int32, selected, unlocked: bool, hovered: bool = false) =
  let color = if selected: Color(r: 0, g: 220, b: 255, a: 255)
              elif hovered: Color(r: 120, g: 220, b: 255, a: 255)
              elif unlocked: Color(r: 120, g: 150, b: 180, a: 255)
              else: Color(r: 80, g: 80, b: 92, a: 255)
  drawRectangle(x + 5, y + 5, CardW, CardH, Color(r: 0, g: 0, b: 0, a: if selected or hovered: 120 else: 78))
  let bgTop = if selected: Color(r: 22, g: 52, b: 66, a: 255)
              elif hovered: Color(r: 32, g: 43, b: 62, a: 255)
              else: Color(r: 24, g: 31, b: 46, a: 255)
  let bgBottom = if selected: Color(r: 11, g: 27, b: 40, a: 255)
                 elif hovered: Color(r: 18, g: 26, b: 40, a: 255)
                 else: Color(r: 14, g: 20, b: 32, a: 255)
  drawSoftFill(x, y, CardW, CardH, bgTop, bgBottom)
  drawScanlines(x + 6, y + 6, CardW - 12, CardH - 12, Color(r: 255, g: 255, b: 255, a: 5))
  drawRectangle(x, y, CardW, 76, softColor(color, if selected: 42 elif hovered: 34 else: 24))
  drawRectangle(x, y, CardW, 3, softColor(color, if selected: 220 else: 125))
  drawRectangleLines(rectAt(x, y, CardW, CardH), if selected: 3 elif hovered: 2 else: 1, color)
  drawCornerBrackets(x + 7, y + 7, CardW - 14, CardH - 14, 18, 1, softColor(color, if selected: 155 else: 82))
  # Emblem medallion: fills the otherwise-empty mid-body so cards read as
  # deliberate panels rather than mostly blank. Drawn before the text/pills so
  # those stay crisp on top; faint + slowly rotating to add life without noise.
  block:
    let emblemCX = x + CardW div 2
    let emblemCY = y + 176
    let baseA: uint8 = if selected: 26 elif hovered: 18 else: 11
    let lineA: uint8 = if selected: 95 elif hovered: 60 else: 36
    drawCircle(Vector2(x: emblemCX.float32, y: emblemCY.float32), 34.0'f32, softColor(color, baseA))
    drawCircleLines(emblemCX, emblemCY, 34.0'f32, softColor(color, lineA))
    drawCircleLines(emblemCX, emblemCY, 27.0'f32, softColor(color, uint8(lineA.int * 2 div 3)))
    for i in 0..<8:
      let a = (i.float32 / 8.0'f32) * (PI.float32 * 2.0'f32) + game.time * 0.4'f32
      let r1 = 38.0'f32
      let r2 = 43.0'f32
      drawLine((emblemCX.float32 + cos(a) * r1).int32, (emblemCY.float32 + sin(a) * r1).int32,
               (emblemCX.float32 + cos(a) * r2).int32, (emblemCY.float32 + sin(a) * r2).int32,
               softColor(color, uint8(lineA.int * 3 div 4)))
    drawKitGlyph(emblemCX, emblemCY, kit, softColor(color, if unlocked: 235 else: 150))
  drawCircle(Vector2(x: (x + CardW - 44).float32, y: (y + 40).float32), 24, softColor(color, 28))
  drawCircleLines(x + CardW - 44, y + 40, 24.0'f32, softColor(color, 100))
  drawKitGlyph(x + CardW - 44, y + 40, kit, color)
  drawTextFit(locStarterName(kit), x + 18, y + 18, CardW - 92, 24, if unlocked: White else: Gray)
  let status = if unlocked: t("roguelite_unlocked") else: t("roguelite_locked")
  drawPill(x + 18, y + 52, 92, 22, status,
           if unlocked: Color(r: 100, g: 255, b: 150, a: 255) else: Color(r: 255, g: 120, b: 120, a: 255),
           unlocked)
  discard drawWrappedText(locStarterDescription(kit), x + 18, y + 96, CardW - 36, 14,
                          Color(r: 185, g: 198, b: 214, a: 255), 5, 6)
  if not unlocked:
    let pillX: int32 = x + 18
    let pillY: int32 = y + CardH - 38
    let pillW: int32 = CardW - 36
    let pillH: int32 = 24
    let pillColor = Color(r: 255, g: 210, b: 110, a: 255)
    # Pill background
    drawRectangle(pillX, pillY, pillW, pillH, Color(r: 19, g: 25, b: 36, a: 225))
    drawRectangleLines(Rectangle(x: pillX.float32, y: pillY.float32, width: pillW.float32, height: pillH.float32), 1, softColor(pillColor, 170))
    # Draw shard icon + amount
    let costVal = starterKitCost(kit)
    if costVal == 0:
      let lbl = locKitRequirement(kit)
      let fs = bestFitFontSize(lbl, pillW - 8, 12, 8)
      let lblW = measureText(lbl, fs)
      drawText(lbl, (pillX + (pillW - lblW) div 2).int32, pillY + 4, fs, Color(r: 220, g: 220, b: 200, a: 255))
    else:
      let iconSize: int32 = 18
      let iconCX = pillX + 12 + iconSize div 2
      let iconCY = pillY + pillH div 2
      drawCurrencyIcon(iconCX, iconCY, iconSize, ciDataShards)
      let amtText = $costVal
      drawText(amtText, pillX + 12 + iconSize + 8, pillY + 3, 14, Color(r: 255, g: 240, b: 100, a: 255))
  else:
    drawPill(x + 18, y + CardH - 38, CardW - 36, 24, t("roguelite_starter_ready"),
             Color(r: 100, g: 255, b: 170, a: 255), true)

proc drawRogueliteSetup*(game: Game) =
  let x = (game.screenWidth - PanelW) div 2
  let y = (game.screenHeight - PanelH) div 2
  let canHover = mouseHoverEnabled(game)
  let mousePos = if canHover: getVirtualMousePosition() else: Vector2()
  let closeHovered = canHover and checkCollisionPointRec(mousePos, rogueliteCloseButtonRect(game.screenWidth, game.screenHeight))
  drawBackdrop(game, Color(r: 0, g: 220, b: 255, a: 255))
  drawPanel(x, y, PanelW, PanelH, t("roguelite_setup_title"), Color(r: 0, g: 220, b: 255, a: 255), closeHovered)

  let profile = game.rogueliteProfile
  let shards = if profile.isNil: 0 else: profile.dataShards
  let cores = if profile.isNil: 0 else: profile.cores
  let maxHeat = if profile.isNil: RogueliteMinHeat else: profile.highestHeat
  let bossTier = if profile.isNil: 1 else: profile.unlockedBossTier
  drawStatChip(x + 26, y + 58, 164, 48, t("roguelite_data_shards"), $shards, Gold, ciDataShards)
  drawStatChip(x + 202, y + 58, 164, 48, t("roguelite_cores"), $cores,
               Color(r: 255, g: 130, b: 80, a: 255), ciCore)
  drawStatChip(x + 378, y + 58, 150, 48, t("roguelite_heat"), $maxHeat & " / " & $RogueliteMaxHeat,
               Color(r: 255, g: 150, b: 80, a: 255), ciHeat)
  drawStatChip(x + 540, y + 58, 178, 48, t("roguelite_boss_tier"), $bossTier,
               Color(r: 255, g: 120, b: 95, a: 255))

  # Permanent Recursion damage banked across runs. Only surfaces once earned, so
  # it reads as a reward the player has built up rather than dead UI at 0%.
  let recursionBonus = if profile.isNil: 0.0'f32 else: profile.recursionDamageBonus
  if recursionBonus > 0.0'f32:
    let pct = int(round(recursionBonus * 100.0'f32))
    let maxLv = getPowerUpMaxLevel(puRecursion)
    drawStatChip(x + 730, y + 58, 162, 48,
                 t("roguelite_recursion") & " " & t("roguelite_level") & $profile.recursionLevel & "/" & $maxLv,
                 "+" & $pct & "%", Color(r: 255, g: 140, b: 255, a: 255))

  let startX = x + 45
  let cardY = y + 122
  for idx, kit in [rskOperator, rskBulwark, rskArcanist]:
    let unlocked = profile.isNil or kit in profile.unlockedStarterKits
    let cardX = (startX + idx * (CardW + CardGap)).int32
    let hovered = canHover and isHovered(mousePos, cardX, cardY.int32, CardW, CardH)
    drawKitCard(game, kit, (startX + idx * (CardW + CardGap)).int32, cardY.int32,
                idx == game.selectedRogueliteStarter, unlocked, hovered)

  drawHeatPanel(game, x + RogueliteHeatPanelXOffset, y + RogueliteHeatPanelYOffset,
                RogueliteHeatPanelW, RogueliteHeatPanelH)

  let btnY = y + PanelH - 82
  let selectedStarterIndex = clamp(game.selectedRogueliteStarter, 0, 2)
  let selectedKit = starterByUnlockIndex(selectedStarterIndex)
  let selectedUnlocked = profile.isNil or selectedKit in profile.unlockedStarterKits
  let selectedCanBuy = not selectedUnlocked and
                       not profile.isNil and
                       canPurchaseUnlock(profile, rucStarterKits, selectedStarterIndex)
  let startLabel = if selectedUnlocked: t("roguelite_start")
                   elif selectedCanBuy: t("roguelite_buy_unlock")
                   else: t("roguelite_need_more_shards")
  drawSmallButton(x + 60, btnY, 180, 42, t("roguelite_unlocks"), false, Color(r: 120, g: 200, b: 255, a: 255),
                  canHover and isHovered(mousePos, x + 60, btnY, 180, 42))
  drawSmallButton(x + 370, btnY, 180, 42, startLabel, selectedUnlocked or selectedCanBuy, Color(r: 0, g: 240, b: 160, a: 255),
                  canHover and isHovered(mousePos, x + 370, btnY, 180, 42))
  drawSmallButton(x + 680, btnY, 180, 42, t("roguelite_back"), false, Color(r: 255, g: 120, b: 120, a: 255),
                  canHover and isHovered(mousePos, x + 680, btnY, 180, 42))
  drawCenteredTextFit(t("roguelite_setup_controls"), x + 180, y + PanelH - 30, PanelW - 360, 14, LightGray)
  drawBetaBanner(game)

proc drawThemeCard(theme: DungeonFloorTheme, x, y: int32, selected: bool, floorBossNumber: int, hovered: bool = false) =
  let accent = themeAccent(theme)
  let color = if selected: Color(r: 0, g: 220, b: 255, a: 255)
              elif hovered: Color(r: 130, g: 225, b: 255, a: 255)
              else: softColor(accent, 220)
  let def = themeDef(theme)
  if hovered:
    drawRectangle(x + 4, y + 4, CardW, CardH, Color(r: 0, g: 0, b: 0, a: 115))
  drawRectangle(x, y, CardW, CardH,
                if hovered: Color(r: 28, g: 38, b: 56, a: 255) else: Color(r: 22, g: 28, b: 42, a: 255))
  drawRectangle(x, y, CardW, 76, softColor(accent, 34))
  drawRectangleLines(rectAt(x, y, CardW, CardH), if selected: 3 elif hovered: 2 else: 1, color)
  drawCircle(Vector2(x: (x + CardW - 42).float32, y: (y + 40).float32), 18, softColor(accent, 36))
  drawThemeGlyph(x + CardW - 42, y + 40, theme, accent)
  drawTextFit(themeName(theme), x + 16, y + 16, CardW - 82, 21, White)
  drawPill(x + 16, y + 47, 92, 22, t("roguelite_floor"), accent, false)

  # Floor boss preview
  drawCategoryGlyph(x + 33, y + 98, rucChallengeTiers, Color(r: 255, g: 120, b: 95, a: 255))
  drawTextFit(t("dungeon_floor_boss"), x + 58, y + 90, CardW - 74, 13, Color(r: 255, g: 150, b: 120, a: 255))
  drawTextFit(t("boss_" & $floorBossNumber & "_name"), x + 58, y + 107, CardW - 74, 14, Gold)

  drawTextFit(t("roguelite_pressure") & ": " & $(int(def.pressureMod * 100)) & "%", x + 16, y + 139, 116, 13, LightGray)
  drawMeter(x + 136, y + 143, 104, 8, (def.pressureMod - 0.9) / 0.5, accent)
  drawTextFit(t("roguelite_elite") & ": +" & $def.eliteBonus, x + 16, y + 163, 116, 13, LightGray)
  drawMeter(x + 136, y + 167, 104, 8, def.eliteBonus.float32 / 10.0'f32, Color(r: 255, g: 130, b: 80, a: 255))
  drawTextFit(t("roguelite_shards") & ": x" & $round(def.shardMod * 100).int & "%", x + 16, y + 187, 116, 13, Gold)
  drawMeter(x + 136, y + 191, 104, 8, (def.shardMod - 0.9) / 0.6, Gold)
  discard drawWrappedText(themeDescription(theme), x + 16, y + 215, CardW - 32, 13,
                          Color(r: 180, g: 192, b: 210, a: 255), 2, 4)

proc finalBossCardRect*(screenWidth, screenHeight: int32): Rectangle =
  ## Geometry of the single special final-boss card. Shared by the renderer and
  ## the floor-select input handler so the hit-test matches what is drawn.
  let panelX = (screenWidth - PanelW) div 2
  let panelY = (screenHeight - PanelH) div 2
  const w = CardW * 2 + CardGap
  const h = CardH + 24
  Rectangle(
    x: (panelX + (PanelW - w) div 2).float32,
    y: (panelY + 180).float32,
    width: w.float32,
    height: h.float32)

proc drawFinalBossCard(game: Game, rect: Rectangle, hovered: bool) =
  ## The final floor's one-and-only choice: a wide, pulsing crimson/gold card for
  ## boss 12, deliberately styled apart from the regular theme cards.
  let x = rect.x.int32
  let y = rect.y.int32
  let w = rect.width.int32
  let h = rect.height.int32
  let pulse = sin(game.time.float32 * 3.2'f32) * 0.5'f32 + 0.5'f32
  let crimson = Color(r: 235, g: 50, b: 62, a: 255)
  let gold = Color(r: 255, g: 210, b: 110, a: 255)
  let accent = themeAccent(FinalFloorTheme)
  let borderA = uint8(150.0'f32 + pulse * 105.0'f32)

  # Shadow + dark crimson body with a brighter header band and top accent rule.
  drawRectangle(x + 6, y + 9, w, h, Color(r: 0, g: 0, b: 0, a: 160))
  drawRectangle(x, y, w, h, Color(r: 26, g: 8, b: 14, a: if hovered: 255 else: 248))
  drawRectangle(x, y, w, 96, softColor(crimson, if hovered: 44 else: 32))
  drawRectangle(x, y, w, 4, crimson)

  # Pulsing crimson border, inner gold trim, and corner brackets.
  drawRectangleLines(rectAt(x, y, w, h), 3,
                     Color(r: crimson.r, g: crimson.g, b: crimson.b, a: borderA))
  drawRectangleLines(rectAt(x + 4, y + 4, w - 8, h - 8), 1, softColor(gold, 110))
  drawCornerBrackets(x + 10, y + 10, w - 20, h - 20, 28, 2,
                     softColor(gold, uint8(120.0'f32 + pulse * 110.0'f32)))

  # FINAL BOSS pill.
  drawPill(x + 22, y + 24, 158, 32, t("dungeon_final_floor_label"), crimson, true)

  # Pulsing boss glyph on the right.
  let glyphX = x + w - 74
  let glyphY = y + 62
  drawCircle(Vector2(x: glyphX.float32, y: glyphY.float32), 30.0'f32 + pulse * 6.0'f32,
             softColor(crimson, 34))
  drawThemeGlyph(glyphX, glyphY, FinalFloorTheme, accent)

  # Boss label + name.
  drawTextFit(t("dungeon_floor_boss"), x + 24, y + 66, w - 150, 15,
              Color(r: 255, g: 150, b: 120, a: 255))
  drawTextFit(t("boss_12_name"), x + 24, y + 86, w - 150, 30, gold)

  # Flavor description.
  discard drawWrappedText(t("dungeon_final_floor_desc"), x + 24, y + 140, w - 48, 16,
                          Color(r: 222, g: 198, b: 208, a: 255), 2, 6)

  # Pulsing warning line near the bottom.
  drawCenteredTextFit(t("dungeon_final_floor_warning"), x + 20, y + h - 42, w - 40, 17,
                      Color(r: crimson.r, g: crimson.g, b: crimson.b,
                            a: uint8(170.0'f32 + pulse * 80.0'f32)))

proc drawRogueliteFloorSelect*(game: Game) =
  let x = (game.screenWidth - PanelW) div 2
  let y = (game.screenHeight - PanelH) div 2
  let canHover = mouseHoverEnabled(game)
  let mousePos = if canHover: getVirtualMousePosition() else: Vector2()
  let closeHovered = canHover and checkCollisionPointRec(mousePos, rogueliteCloseButtonRect(game.screenWidth, game.screenHeight))
  drawBackdrop(game, Color(r: 0, g: 220, b: 255, a: 255))
  drawPanel(x, y, PanelW, PanelH, t("dungeon_floor_select_title"), Color(r: 0, g: 220, b: 255, a: 255), closeHovered)

  if game.rogueliteRun.isNil:
    drawText(t("roguelite_no_run"), x + 40, y + 90, 22, Red)
    return

  let run = game.rogueliteRun
  drawStatChip(x + 28, y + 58, 190, 48, t("roguelite_floor"),
               $run.floorNumber & " / " & $RogueliteFloorsToWin,
               Color(r: 150, g: 220, b: 255, a: 255))
  drawStatChip(x + 236, y + 58, 210, 48, t("dungeon_rooms_cleared"),
               $run.totalRoomsCleared,
               Color(r: 0, g: 220, b: 255, a: 255))
  drawStatChip(x + 464, y + 58, 180, 48, t("roguelite_heat"), $run.heat,
               Color(r: 255, g: 150, b: 80, a: 255), ciHeat)
  drawStatChip(x + 662, y + 58, 230, 48, t("roguelite_endless"), $run.endlessLoop,
               Color(r: 255, g: 210, b: 110, a: 255))

  drawProgressRail(run, x + 120, y + 132, 680)

  if isFinalDungeonFloor(run):
    let cardRect = finalBossCardRect(game.screenWidth.int32, game.screenHeight.int32)
    drawFinalBossCard(game, cardRect,
                      canHover and checkCollisionPointRec(mousePos, cardRect))
  else:
    let startX = x + 45
    let cardY = y + 185
    let bossTier = if game.rogueliteProfile != nil: game.rogueliteProfile.unlockedBossTier else: 1
    for i in 0..2:
      let cardX = (startX + i * (CardW + CardGap)).int32
      let floorBoss = dungeonBossNumberFor(run.nextThemeChoices[i], run.floorNumber,
                                           run.endlessLoop, bossTier)
      drawThemeCard(run.nextThemeChoices[i], cardX, cardY.int32,
                    i == game.selectedRogueliteTheme, floorBoss,
                    canHover and isHovered(mousePos, cardX, cardY.int32, CardW, CardH))

  # Permanent Recursion damage carried across runs. The top chip row is already
  # full here, so it surfaces as a centred pill in the band below the cards.
  let recursionBonus = if game.rogueliteProfile.isNil: 0.0'f32
                       else: game.rogueliteProfile.recursionDamageBonus
  if recursionBonus > 0.0'f32:
    let pct = int(round(recursionBonus * 100.0'f32))
    let lv = if game.rogueliteProfile.isNil: 0 else: game.rogueliteProfile.recursionLevel
    let pillLabel = t("roguelite_recursion") & " " & t("roguelite_level") & $lv & "/" &
                    $getPowerUpMaxLevel(puRecursion) & "  +" & $pct & "% " & t("roguelite_recursion_dmg")
    const pillW = 400'i32
    drawPill(x + (PanelW - pillW) div 2, y + 462, pillW, 30, pillLabel,
             Color(r: 255, g: 140, b: 255, a: 255), filled = true)

  if not isFinalDungeonFloor(run):
    # The themed-roll tip is meaningless on the single-card final floor; the card's
    # own warning line carries the stakes there.
    drawCenteredTextFit(t("dungeon_floor_select_tip"), x + 60, y + PanelH - 63, PanelW - 120, 14, Color(r: 255, g: 210, b: 110, a: 255))
  drawCenteredTextFit(t("roguelite_sector_controls"), x + 60, y + PanelH - 35, PanelW - 120, 15, LightGray)
  drawBetaBanner(game)

proc rogueliteVictoryButtonRects*(screenWidth, screenHeight: int32): tuple[continueBtn, cashOut: Rectangle] =
  ## Shared geometry so the ending screen's click hit-tests (main.nim) match the draw.
  let panel = roguelitePanelRect(screenWidth, screenHeight)
  const BtnW = 300'i32
  const BtnH = 54'i32
  const Gap = 44'i32
  let totalW = BtnW * 2 + Gap
  let bx = panel.x.int32 + (PanelW - totalW) div 2
  let by = panel.y.int32 + PanelH - 96
  result.continueBtn = rectAt(bx, by, BtnW, BtnH)
  result.cashOut = rectAt(bx + BtnW + Gap, by, BtnW, BtnH)

proc drawRogueliteEndButton(rect: Rectangle, label: string, color: Color, highlighted: bool) =
  let x = rect.x.int32
  let y = rect.y.int32
  let w = rect.width.int32
  let h = rect.height.int32
  drawRectangle(x + 3, y + 4, w, h, Color(r: 0, g: 0, b: 0, a: 90))
  drawSoftFill(x, y, w, h,
    (if highlighted: softColor(color, 80) else: Color(r: 22, g: 30, b: 44, a: 245)),
    (if highlighted: softColor(color, 32) else: Color(r: 12, g: 18, b: 30, a: 245)))
  drawRectangleLines(rectAt(x, y, w, h), 2, softColor(color, if highlighted: 255 else: 150))
  let fs = bestFitFontSize(label, w - 24, 20, 12)
  discard drawCenteredTextFit(label, x + 12, y + (h - fs) div 2, w - 24, fs,
    (if highlighted: Color(r: 255, g: 255, b: 255, a: 255) else: color))

proc drawRogueliteVictory*(game: Game) =
  ## The roguelite ending screen: shown the moment the final floor boss falls
  ## (and on every subsequent endless-loop completion). Celebrates the win, recaps
  ## the run, and offers the cash-out / push-deeper decision.
  if game.rogueliteRun.isNil: return
  let run = game.rogueliteRun
  let accent = Color(r: 120, g: 255, b: 180, a: 255)   # "system secured" green
  drawBackdrop(game, accent)
  let x = (game.screenWidth - PanelW) div 2
  let y = (game.screenHeight - PanelH) div 2
  let isFirstWin = run.endlessLoop == 0
  let title = if isFirstWin: t("roguelite_victory_title") else: t("roguelite_loop_cleared_title")
  drawPanel(x, y, PanelW, PanelH, title, accent, omitTitleBar = true)

  discard drawCenteredTextFit(
    (if isFirstWin: t("roguelite_victory_subtitle") else: t("roguelite_loop_cleared_subtitle")),
    x + 60, y + 70, PanelW - 120, 18, Color(r: 180, g: 230, b: 205, a: 255))

  # Run recap chips
  let chipY = y + 120
  drawStatChip(x + 40, chipY, 200, 52, t("roguelite_floor"),
               $RogueliteFloorsToWin & " / " & $RogueliteFloorsToWin, accent)
  drawStatChip(x + 256, chipY, 200, 52, t("dungeon_rooms_cleared"),
               $run.totalRoomsCleared, Color(r: 0, g: 220, b: 255, a: 255))
  drawStatChip(x + 472, chipY, 180, 52, t("roguelite_heat"), $run.heat,
               Color(r: 255, g: 150, b: 80, a: 255), ciHeat)
  drawStatChip(x + 668, chipY, 212, 52, t("roguelite_endless"), $run.endlessLoop,
               Color(r: 255, g: 210, b: 110, a: 255))

  # Banked meta currency (run earnings already committed to the profile by now)
  let curY = chipY + 68
  if not game.rogueliteProfile.isNil:
    drawStatChip(x + 40, curY, 300, 52, t("roguelite_shards"),
                 $game.rogueliteProfile.dataShards,
                 Color(r: 0, g: 220, b: 255, a: 255), ciDataShards)
    drawStatChip(x + 356, curY, 300, 52, t("roguelite_cores"),
                 $game.rogueliteProfile.cores,
                 Color(r: 200, g: 160, b: 255, a: 255), ciCore)

  # Relics carried into the win
  let relicY = curY + 78
  drawText(t("roguelite_relics_carried"), x + 40, relicY, 16,
           Color(r: 156, g: 172, b: 196, a: 255))
  if run.relics.len == 0:
    drawText(t("roguelite_relics_none"), x + 40, relicY + 26, 14,
             Color(r: 120, g: 130, b: 150, a: 255))
  else:
    var px = x + 40
    let py = relicY + 26
    for relic in run.relics:
      let pillW = measureText(relic.name, 13).int32 + 26
      if px + pillW > x + PanelW - 40: break
      drawPill(px, py, pillW, 30, relic.name, Color(r: 0, g: 230, b: 170, a: 255))
      px += pillW + 10

  # Decision buttons
  let rects = rogueliteVictoryButtonRects(game.screenWidth.int32, game.screenHeight.int32)
  let canHover = mouseHoverEnabled(game)
  let mousePos = if canHover: getVirtualMousePosition() else: Vector2()
  let contHi = game.selectedVictoryButton == 0 or
               (canHover and checkCollisionPointRec(mousePos, rects.continueBtn))
  let cashHi = game.selectedVictoryButton == 1 or
               (canHover and checkCollisionPointRec(mousePos, rects.cashOut))
  drawRogueliteEndButton(rects.continueBtn, t("roguelite_continue_endless"), accent, contHi)
  drawRogueliteEndButton(rects.cashOut, t("roguelite_cash_out"),
                         Color(r: 255, g: 210, b: 110, a: 255), cashHi)

  drawCenteredTextFit(t("roguelite_victory_controls"), x + 60, y + PanelH - 34,
                      PanelW - 120, 14, LightGray)
  drawBetaBanner(game)

# Unlock card grid helpers

proc unlockLockGlyph(x, y: int32, color: Color) =
  drawCircleLines(x + 10, y + 8, 7, color)
  drawRectangle(x + 2, y + 8, 16, 14, Color(r: 20, g: 24, b: 32, a: 235))
  drawRectangleLines(x + 2, y + 8, 16, 14, color)
  drawCircle(Vector2(x: (x + 10).float32, y: (y + 15).float32), 2, color)

proc unlockFitText(text: string, maxWidth: int32, startSize: int32, minSize: int32 = 7): int32 =
  result = startSize
  while result > minSize and measureText(text, result) > maxWidth:
    dec result

proc unlockWrapLines(text: string, maxWidth, fontSize, maxLines: int32): seq[string] =
  var currentLine = ""
  for w in text.splitWhitespace():
    let candidate = if currentLine.len > 0: currentLine & " " & w else: w
    if measureText(candidate, fontSize) <= maxWidth:
      currentLine = candidate
    else:
      if currentLine.len > 0:
        result.add(currentLine)
      if result.len >= maxLines.int:
        return
      currentLine = w
  if currentLine.len > 0 and result.len < maxLines.int:
    result.add(currentLine)

proc drawUnlockDescriptionLines(text: string, x, y, maxWidth, fontSize, maxLines, lineGap: int32,
                                color: Color) =
  let lines = unlockWrapLines(text, maxWidth, fontSize, maxLines)
  for idx, line in lines:
    drawText(line, x, y + idx.int32 * (fontSize + lineGap), fontSize, color)

proc unlockBestDescriptionSize(text: string, maxWidth, maxHeight, preferredSize, maxLines, lineGap: int32,
                               minSize: int32 = 8): int32 =
  result = preferredSize
  while result > minSize:
    let lines = unlockWrapLines(text, maxWidth, result, maxLines + 1)
    let lineCount = min(lines.len.int32, maxLines)
    let textHeight = if lineCount <= 0: 0'i32 else: lineCount * result + (lineCount - 1) * lineGap
    if lines.len <= maxLines.int and textHeight <= maxHeight:
      break
    dec result

proc drawUnlockCostPill(x, y, w, h: int32, profile: RogueliteProfile,
                        category: RogueliteUnlockCategory, index: int,
                        statusText: string, statusColor: Color) =
  let shardCost = unlockCost(profile, category, index)
  let coreCost = unlockCoreCost(profile, category, index)
  var parts: seq[tuple[icon: CurrencyIconType, amount: int]] = @[]
  if coreCost > 0:  parts.add((icon: ciCore, amount: coreCost))
  if shardCost > 0: parts.add((icon: ciDataShards, amount: shardCost))

  let iconSize: int32 = 15
  let padBetween: int32 = 5
  let partGap: int32 = 8
  var costW: int32 = 0
  for p in parts:
    costW += iconSize + padBetween + int32(measureText($p.amount, 11)) + partGap

  let textLimit = max(34'i32, w - costW - 18)
  let fs = unlockFitText(statusText, textLimit, 11, 7)
  let textW = int32(measureText(statusText, fs))
  let totalW = if parts.len == 0: textW else: textW + 9 + costW
  var cursorX = x + max(0'i32, (w - totalW) div 2)
  drawText(statusText, cursorX, y + (h - fs) div 2, fs, statusColor)
  cursorX += textW + 9

  let iconCY = y + h div 2
  for p in parts:
    let txt = $p.amount
    drawCurrencyIcon(cursorX + iconSize div 2, iconCY, iconSize, p.icon)
    let txtX = cursorX + iconSize + padBetween
    drawText(txt, txtX, y + (h - 11) div 2, 11, statusColor)
    let txtW = int32(measureText(txt, 11))
    cursorX += iconSize + padBetween + txtW + partGap

proc drawUnlockCardStatus(x, y: int, isPurchased, canBuy: bool,
                           profile: RogueliteProfile,
                           category: RogueliteUnlockCategory, index: int) =
  ## Draw the lock/status overlay and bottom pill on an unlock card.
  const cW = UnlockCardW
  const cH = UnlockCardH

  # Purchased: badge is already drawn by drawUnlockCard, nothing extra needed here
  if isPurchased:
    return

  let statusColor = if canBuy: Color(r: 255, g: 215, b: 80, a: 255)
                    else: Color(r: 140, g: 142, b: 158, a: 255)

  # Dim overlay, two-pass for a subtle depth gradient (top lighter, bottom darker)
  if canBuy:
    drawRectangle(x.int32, (y + cH - 44).int32, cW, 44, Color(r: 0, g: 0, b: 0, a: 44))
    drawRectangle(x.int32, y.int32, cW, 3, softColor(statusColor, 135))
  else:
    drawRectangle(x.int32, y.int32, cW, cH div 2, Color(r: 0, g: 0, b: 0, a: 66))
    drawRectangle(x.int32, (y + cH div 2).int32, cW, cH div 2, Color(r: 0, g: 0, b: 0, a: 116))
    unlockLockGlyph((x + 10).int32, (y + 10).int32, statusColor)

  # Status pill
  let pillX = (x + 10).int32
  let pillY = (y + cH - 34).int32
  let pillW = (cW - 20).int32
  let pillH: int32 = 24
  # Pill fill
  let pillFill = if canBuy: Color(r: 46, g: 35, b: 12, a: 238)
                 else: Color(r: 16, g: 17, b: 24, a: 235)
  drawSoftFill(pillX, pillY, pillW, pillH, pillFill,
               if canBuy: Color(r: 23, g: 22, b: 18, a: 238)
               else: Color(r: 11, g: 13, b: 20, a: 238))
  drawLine(pillX + 2, pillY + 1, pillX + pillW - 3, pillY + 1, softColor(statusColor, 55))
  drawRectangleLines(Rectangle(x: pillX.float32, y: pillY.float32,
                               width: pillW.float32, height: pillH.float32),
                     1.5'f32, softColor(statusColor, 180))

  drawUnlockCostPill(pillX, pillY, pillW, pillH, profile, category, index,
                     if canBuy: t("roguelite_buy_unlock") else: t("roguelite_locked"),
                     statusColor)

proc drawUnlockCard*(profile: RogueliteProfile, category: RogueliteUnlockCategory,
                     index: int, x, y: int32, isSelected, isHovered: bool,
                     isPurchased, canBuy: bool, time: float32 = 0.0) =
  ## Draw a single unlock item as a richly-styled shop card.
  const cW = UnlockCardW
  const cH = UnlockCardH

  let catColor = categoryColor(category)
  # Each power family gets its own distinct color, everything else uses the category accent
  let itemColor = if category == rucPowerFamilies: familyColor(familyByUnlockIndex(index))
                  else: catColor

  # Drop shadow
  drawRectangle(x + 5, y + 5, cW, cH, Color(r: 0, g: 0, b: 0, a: if isSelected: 105 else: 70))

  # Card base background
  let bgTop = if isSelected: Color(r: 21, g: 48, b: 64, a: 255)
              elif isHovered: Color(r: 44, g: 47, b: 64, a: 255)
              elif canBuy: Color(r: 38, g: 36, b: 28, a: 255)
              else: Color(r: 26, g: 28, b: 40, a: 255)
  let bgBottom = if isSelected: Color(r: 9, g: 26, b: 40, a: 255)
                 elif isHovered: Color(r: 24, g: 28, b: 42, a: 255)
                 elif canBuy: Color(r: 23, g: 24, b: 30, a: 255)
                 else: Color(r: 17, g: 20, b: 31, a: 255)
  drawSoftFill(x, y, cW, cH, bgTop, bgBottom)
  drawScanlines(x + 5, y + 5, cW - 10, cH - 10, Color(r: 255, g: 255, b: 255, a: 5))

  # Header zone tint
  let hdrAlpha: uint8 = if isPurchased: 48 elif canBuy: 42 elif isSelected: 36 elif isHovered: 26 else: 16
  drawRectangle(x, y, cW, 72, softColor(itemColor, hdrAlpha))

  # Top accent stripe (3 px)
  let stripeAlpha: uint8 = if isPurchased: 230 elif canBuy: 215 elif isSelected: 205 elif isHovered: 155 else: 95
  drawRectangle(x, y, cW, 3, softColor(itemColor, stripeAlpha))
  drawCornerBrackets(x + 6, y + 6, cW - 12, cH - 12, 13, 1,
                     softColor(itemColor, if isSelected or canBuy: 120 else: 52))

  # Glyph halos
  let cx = x + cW div 2
  let cy = y + 42
  if isPurchased:
    drawCircle(Vector2(x: cx.float32, y: cy.float32), 27, softColor(itemColor, 18))
    drawCircle(Vector2(x: cx.float32, y: cy.float32), 20, softColor(itemColor, 42))
    drawCircleLines(cx, cy, 20.5'f32, softColor(itemColor, 105))
  elif isSelected:
    let p = sin(time * 4.5'f32) * 0.4'f32 + 0.6'f32
    drawCircle(Vector2(x: cx.float32, y: cy.float32), 25, softColor(itemColor, uint8(20.0'f32 * p)))
    drawCircle(Vector2(x: cx.float32, y: cy.float32), 18, softColor(itemColor, 38))
    drawCircleLines(cx, cy, 19.0'f32, softColor(itemColor, uint8(135.0'f32 * p)))
  elif isHovered:
    drawCircle(Vector2(x: cx.float32, y: cy.float32), 22, softColor(itemColor, 20))
    drawCircle(Vector2(x: cx.float32, y: cy.float32), 16, softColor(itemColor, 42))
  else:
    drawCircle(Vector2(x: cx.float32, y: cy.float32), 17, Color(r: 45, g: 48, b: 62, a: 170))

  # Glyph itself
  let glyphColor = if isPurchased: itemColor
                   elif isSelected:
                     let p = sin(time * 4.5'f32) * 0.15'f32 + 0.85'f32
                     Color(r: uint8(min(255, int(itemColor.r.float32 * p) + 30)),
                           g: uint8(min(255, int(itemColor.g.float32 * p) + 30)),
                           b: uint8(min(255, int(itemColor.b.float32 * p) + 30)), a: 255)
                   elif isHovered: Color(r: 218, g: 224, b: 236, a: 255)
                   else: Color(r: 118, g: 126, b: 145, a: 255)
  drawUnlockGlyph(profile, category, index.int32, cx, cy, glyphColor, false)

  # OWNED badge (top-right)
  if isPurchased:
    let bx = x + cW - 44
    let by = y + 5
    let bw: int32 = 40
    let bh: int32 = 15
    drawRectangle(bx, by, bw, bh, softColor(Color(r: 0, g: 195, b: 128, a: 255), 200))
    # Tiny top highlight on badge
    drawLine(bx + 2, by + 1, bx + bw - 3, by + 1, Color(r: 255, g: 255, b: 255, a: 38))
    let ot = "OWNED"
    let otW = measureText(ot, 8)
    drawText(ot, bx + (bw - otW) div 2, by + 4, 8, Color(r: 215, g: 255, b: 240, a: 255))

  # Hairline divider below header
  let divAlpha: uint8 = if isPurchased: 72 elif isSelected or isHovered: 52 else: 28
  drawLine(x + 10, y + 74, x + cW - 10, y + 74, softColor(itemColor, divAlpha))

  # Name
  let name = locUnlockName(profile, category, index)
  let nameColor = if isPurchased: itemColor
                  elif isSelected: White
                  elif isHovered: Color(r: 238, g: 241, b: 248, a: 255)
                  else: Color(r: 200, g: 206, b: 220, a: 255)
  let nameFS = unlockFitText(name, (cW - 22).int32, 15, 10)
  let nameW = measureText(name, nameFS)
  drawText(name, x + (cW - nameW) div 2, y + 82, nameFS, nameColor)

  # Description (2 lines)
  let desc = locUnlockDescription(category, index)
  let descColor = Color(r: 150, g: 160, b: 180, a: 255)
  let descX = x + 14
  let descY = y + 105
  let descW: int32 = cW - 28
  let descBottom = y + cH - 42
  let descH = max(10'i32, descBottom - descY)
  let descLineGap: int32 = 3
  let descMaxLines: int32 = 4
  let descFont = unlockBestDescriptionSize(desc, descW, descH, 11, descMaxLines, descLineGap, 7)
  drawUnlockDescriptionLines(desc, descX, descY, descW, descFont, descMaxLines, descLineGap, descColor)

  # Status pill / lock overlay
  drawUnlockCardStatus(x.int, y.int, isPurchased, canBuy, profile, category, index)

  # Card border
  let bColor = if isSelected: itemColor
               elif isHovered: Color(r: 122, g: 128, b: 148, a: 255)
               elif isPurchased: softColor(itemColor, 52)
               else: Color(r: 55, g: 58, b: 74, a: 255)
  let bThick = if isSelected: 2.5'f32 elif isHovered: 2.0'f32 else: 1.5'f32
  drawRectangleLines(Rectangle(x: x.float32, y: y.float32, width: cW.float32, height: cH.float32),
                     bThick, bColor)

  # 12. Outer selection glow 
  if isSelected:
    let p = sin(time * 4.5'f32) * 0.5'f32 + 0.5'f32
    drawRectangleLines(Rectangle(x: (x - 2).float32, y: (y - 2).float32,
                                  width: (cW + 4).float32, height: (cH + 4).float32),
                       1.5'f32, softColor(itemColor, uint8(58.0'f32 * p)))

proc drawUnlockTabs*(panelX, panelY, panelW, tabH: int32, activeCategory: int) =
  ## Draw 4 category tabs at the top of the unlock grid area.
  let tabW = panelW div 4
  drawRectangle(panelX + 16, panelY - 8, panelW - 32, tabH + 16, Color(r: 8, g: 13, b: 23, a: 170))
  for idx in 0..3:
    let cat = categoryByIndex(idx)
    let active = idx == activeCategory
    let tx = panelX + idx.int32 * tabW
    let ty = panelY
    let accent = categoryColor(cat)
    let tabColorTop = if active: softColor(accent, 64)
                      else: Color(r: 28, g: 32, b: 44, a: 255)
    let tabColorBottom = if active: Color(r: 27, g: 31, b: 45, a: 255)
                         else: Color(r: 18, g: 23, b: 34, a: 255)
    drawSoftFill(tx + 2, ty, tabW - 4, tabH, tabColorTop, tabColorBottom)
    drawRectangleLines(tx + 2, ty, tabW - 4, tabH,
                       if active: softColor(accent, 180) else: Color(r: 54, g: 62, b: 78, a: 255))
    drawCategoryGlyph(tx + 24, ty + tabH div 2, cat, if active: accent else: Color(r: 112, g: 124, b: 146, a: 255), true)
    if active:
      drawRectangle(tx + 2, ty + tabH - 4, tabW - 4, 4, accent)
      drawCornerBrackets(tx + 7, ty + 5, tabW - 14, tabH - 10, 10, 1, softColor(accent, 145))
    let catLabel = locCategoryName(cat)
    let fs: int32 = 12
    let labelW = measureText(catLabel, fs)
    let labelX = tx + (tabW - labelW) div 2 + 8
    drawText(catLabel, labelX, ty + (tabH - fs) div 2, fs,
             if active: White else: Color(r: 148, g: 158, b: 178, a: 255))

proc drawUnlocksContent*(game: Game, panelX, panelY: int32,
                         categoryIndex, itemIndex: int,
                         scrollOffset: float32 = 0.0) =
  ## Draw the inner unlocks UI at the given panel origin (no backdrop or outer panel chrome).
  ## Uses the same card-grid visual as the normal shop window.
  ## Used when the unlocks view is embedded inside the roguelite setup window.
  if game.rogueliteProfile.isNil:
    drawText(t("roguelite_no_profile"), panelX + 40, panelY + 90, 22, Red)
    return

  let profile = game.rogueliteProfile
  let category = categoryByIndex(categoryIndex)
  let itemCount = unlockCount(category)
  let selectedItem = clamp(itemIndex, 0, max(0, itemCount - 1))
  let selectedPurchased = isUnlockPurchased(profile, category, selectedItem)
  let selectedCanBuy = canPurchaseUnlock(profile, category, selectedItem)
  let catColor = categoryColor(category)
  let accent = Color(r: 255, g: 215, b: 0, a: 255)
  let canHover = game.mouseMovedRecently and not game.keyboardUsedRecently
  let mousePos = if canHover: getVirtualMousePosition() else: Vector2()

  # Stat chips
  drawStatChip(panelX + 26, panelY + 58, 164, 48, t("roguelite_data_shards"), $profile.dataShards, Gold, ciDataShards)
  drawStatChip(panelX + 202, panelY + 58, 164, 48, t("roguelite_cores"), $profile.cores,
               Color(r: 255, g: 130, b: 80, a: 255), ciCore)
  drawStatChip(panelX + 378, panelY + 58, 150, 48, t("roguelite_heat"), $profile.highestHeat & " / " & $RogueliteMaxHeat,
               Color(r: 255, g: 150, b: 80, a: 255), ciHeat)
  drawStatChip(panelX + 540, panelY + 58, 178, 48, t("roguelite_boss_tier"), $profile.unlockedBossTier & " / " & $RogueliteMaxBossTier,
               Color(r: 255, g: 120, b: 95, a: 255))

  # Tabs
  let tabY = panelY + 130
  drawUnlockTabs(panelX, tabY, PanelW, UnlockTabH, categoryIndex)

  # Card grid layout
  #   Grid sits directly below the tabs.
  #   An info panel sits below the grid, and the control bar is at the very bottom.
  let infoPanelH: int32 = 65
  let ctrlBarFootH: int32 = 72
  let gridY = tabY + UnlockTabH                          # panelY + 170
  let gridH: int32 = PanelH - 170 - infoPanelH - ctrlBarFootH  # 313

  let cardTotalW = UnlockCardW + UnlockCardPad
  let columns = max(1, PanelW div cardTotalW)
  let totalRows = if itemCount == 0: 0 else: (itemCount + columns - 1) div columns
  let totalContentH = totalRows * (UnlockCardH + UnlockCardPad) + 10
  let maxScroll = max(0.0'f32, totalContentH.float32 - gridH.float32)
  let clampedScroll = clamp(scrollOffset, 0.0'f32, maxScroll)
  let scrollInt = int(round(clampedScroll))
  let gridLeft = panelX + (PanelW - (columns * UnlockCardW + (columns - 1) * UnlockCardPad)) div 2

  drawSoftFill(panelX + 14, gridY - 8, PanelW - 28, gridH + infoPanelH + 16,
               Color(r: 17, g: 23, b: 36, a: 238),
               Color(r: 9, g: 13, b: 23, a: 238))
  drawRectangleLines(panelX + 14, gridY - 8, PanelW - 28, gridH + infoPanelH + 16,
                     softColor(catColor, 80))
  drawLine(panelX + 24, gridY - 1, panelX + PanelW - 24, gridY - 1, softColor(catColor, 115))

  # Scroll hint, shown inside the grid area, bottom-right, only when scrollable
  if maxScroll > 0:
    let hintText = t("roguelite_scroll_hint")
    let hintW = measureText(hintText, 10)
    drawText(hintText, panelX + PanelW - hintW - 20, gridY + gridH - 18, 10,
             Color(r: 180, g: 180, b: 190, a: 140))

  # Card grid (clipped to grid area)
  beginVirtualScissorMode(panelX, gridY, PanelW, gridH)
  for idx in 0..<itemCount:
    let col = idx mod columns
    let row = idx div columns
    let cx = gridLeft + col * cardTotalW
    let cy = gridY + 5 + row * (UnlockCardH + UnlockCardPad) - scrollInt

    if cy + UnlockCardH > gridY - 10 and cy < gridY + gridH + 10:
      let inGrid = cy + UnlockCardH > gridY and cy < gridY + gridH
      let purchased = isUnlockPurchased(profile, category, idx)
      let canBuy = canPurchaseUnlock(profile, category, idx)
      let isSelected = idx == selectedItem
      let isHov = inGrid and canHover and
                  checkCollisionPointRec(mousePos,
                    Rectangle(x: cx.float32, y: cy.float32,
                              width: UnlockCardW.float32, height: UnlockCardH.float32))
      drawUnlockCard(profile, category, idx, cx.int32, cy.int32, isSelected, isHov, purchased, canBuy, game.time)

    # Keyboard focus ring (drawn even when card is partially visible)
    if idx == selectedItem:
      let cy2 = gridY + 5 + (idx div columns) * (UnlockCardH + UnlockCardPad) - scrollInt
      let cx2 = gridLeft + (idx mod columns) * cardTotalW
      drawRectangleLines(Rectangle(x: cx2.float32, y: cy2.float32,
                                   width: UnlockCardW.float32, height: UnlockCardH.float32),
                         2.0'f32, Color(r: 255, g: 200, b: 100, a: 180))
  endScissorMode()

  # Scrollbar
  if maxScroll > 0:
    let sbX = panelX + PanelW - 14
    let sbW: int32 = 10
    drawRectangle(sbX, gridY + 8, sbW, gridH - 16, Color(r: 20, g: 24, b: 34, a: 255))
    let thumbH = max(30.0'f32, (gridH.float32 / totalContentH.float32) * gridH.float32)
    let thumbY = (gridY + 8).float32 + (clampedScroll / maxScroll) * ((gridH - 16).float32 - thumbH)
    drawRectangle(sbX, thumbY.int32, sbW, thumbH.int32, softColor(catColor, 200))

  # Info panel
  let infoPanelY = gridY + gridH
  drawSoftFill(panelX + 14, infoPanelY, PanelW - 28, infoPanelH,
               Color(r: 31, g: 38, b: 54, a: 252),
               Color(r: 17, g: 23, b: 36, a: 252))
  drawLine(panelX + 14, infoPanelY, panelX + PanelW - 14, infoPanelY, softColor(catColor, 145))
  drawCornerBrackets(panelX + 22, infoPanelY + 8, PanelW - 44, infoPanelH - 16, 16, 1, softColor(catColor, 95))

  let selName = locUnlockName(profile, category, selectedItem)
  let selDesc = locUnlockDescription(category, selectedItem)

  # Glyph
  let glyphCX = panelX + 42
  let glyphCY = infoPanelY + infoPanelH div 2
  drawCircle(Vector2(x: glyphCX.float32, y: glyphCY.float32), 23, softColor(catColor, 34))
  drawCircleLines(glyphCX, glyphCY, 23.0'f32, softColor(catColor, 105))
  drawUnlockGlyph(profile, category, selectedItem.int32, glyphCX, glyphCY, catColor, false)

  # Name + description + status
  let textX = panelX + 74
  let textMaxW: int32 = int32(PanelW - 380)
  drawTextFit(selName, textX, infoPanelY + 7, textMaxW, 15, White)
  drawTextFit(selDesc, textX, infoPanelY + 27, textMaxW, 12, Color(r: 155, g: 166, b: 188, a: 255), 8)
  let stateText = if selectedPurchased: t("roguelite_unlocked")
                  elif selectedCanBuy: t("roguelite_ready_to_buy")
                  else: t("roguelite_not_enough_shards")
  let stateColor = if selectedPurchased: Color(r: 0, g: 230, b: 150, a: 255)
                   elif selectedCanBuy: Gold
                   else: Color(r: 255, g: 120, b: 100, a: 255)
  drawTextFit(stateText, textX, infoPanelY + 47, textMaxW, 11, stateColor, 8)

  # Buy button (right side of info panel)
  let btnW: int32 = 210
  let btnH: int32 = 40
  let btnX = panelX + PanelW - btnW - 16
  let btnY = infoPanelY + (infoPanelH - btnH) div 2
  drawRectangle(btnX + 3, btnY + 3, btnW, btnH, Color(r: 0, g: 0, b: 0, a: if selectedCanBuy: 125 else: 70))
  let buyBgTop = if selectedCanBuy: Color(r: 0, g: 158, b: 214, a: 255)
                 else: Color(r: 58, g: 64, b: 78, a: 255)
  let buyBgBottom = if selectedCanBuy: Color(r: 0, g: 86, b: 146, a: 255)
                    else: Color(r: 35, g: 40, b: 52, a: 255)
  drawSoftFill(btnX, btnY, btnW, btnH, buyBgTop, buyBgBottom)
  if selectedCanBuy:
    drawRectangle(btnX, btnY, btnW, 2, Color(r: 255, g: 255, b: 255, a: 40))
  let buyBorderColor = if selectedCanBuy:
    let pulse = sin(game.time * 6.0'f32) * 0.3'f32 + 0.7'f32
    Color(r: 0, g: 200, b: 255, a: uint8(220.0'f32 * pulse))
  else: Color(r: 100, g: 110, b: 120, a: 255)
  drawRectangleLines(Rectangle(x: btnX.float32, y: btnY.float32,
                                width: btnW.float32, height: btnH.float32), 2.5'f32, buyBorderColor)
  if selectedCanBuy:
    drawCornerBrackets(btnX + 5, btnY + 5, btnW - 10, btnH - 10, 10, 1, Color(r: 210, g: 255, b: 255, a: 135))
  let buyText = if selectedPurchased: t("roguelite_already_unlocked")
                elif selectedCanBuy: t("roguelite_buy_unlock")
                else: t("roguelite_need_more_shards")
  let buyTextW = int32(measureText(buyText, 15))
  let buyTextX = btnX + (btnW - buyTextW) div 2
  drawText(buyText, buyTextX + 1, btnY + 13, 15, Color(r: 0, g: 0, b: 0, a: 120))
  drawText(buyText, buyTextX, btnY + 12, 15,
           if selectedCanBuy: White else: Color(r: 150, g: 155, b: 160, a: 255))

  # Cost summary to left of buy button (when not purchased)
  if not selectedPurchased:
    let costColor = if selectedCanBuy: Gold else: Color(r: 120, g: 120, b: 135, a: 255)
    drawUnlockCostsRight(profile, category, selectedItem, btnX - 16, infoPanelY + 24, 17, 12, costColor)

  # Control bar
  let ctrlBarY = panelY + PanelH - 72
  drawSoftFill(panelX + 42, ctrlBarY, PanelW - 84, 32,
               Color(r: 30, g: 38, b: 54, a: 235),
               Color(r: 16, g: 22, b: 34, a: 235))
  drawRectangleLines(panelX + 42, ctrlBarY, PanelW - 84, 32, softColor(accent, 130))
  drawCenteredTextFit(t("roguelite_unlock_shop_controls"), panelX + 58, ctrlBarY + 10,
                      PanelW - 116, 13, LightGray)

proc drawRogueliteUnlocks*(game: Game, categoryIndex: int = 0, itemIndex: int = 0) =
  let x = (game.screenWidth - PanelW) div 2
  let y = (game.screenHeight - PanelH) div 2
  let canHover = mouseHoverEnabled(game)
  let mousePos = if canHover: getVirtualMousePosition() else: Vector2()
  let closeHovered = canHover and checkCollisionPointRec(mousePos, rogueliteCloseButtonRect(game.screenWidth, game.screenHeight))
  let accent = Color(r: 255, g: 215, b: 0, a: 255)
  drawBackdrop(game, Color(r: 255, g: 215, b: 0, a: 255))
  drawPanel(x, y, PanelW, PanelH, t("roguelite_unlocks_title"), accent, closeHovered)
  drawUnlocksContent(game, x.int32, y.int32, categoryIndex, itemIndex, 0.0)
