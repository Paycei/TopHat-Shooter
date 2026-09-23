import raylib, math, strutils
import ../types, ../roguelite, ../patches, ../powerup_data, ../dungeon, ../localization, ../render_context, ../utils, icon_drawing, ui_helpers
export ui_helpers

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

proc drawBackdrop(game: Game, accent: Color) =
  drawRectangle(0, 0, getVirtualScreenWidth(), getVirtualScreenHeight(), Color(r: 5, g: 9, b: 16, a: 255))
  for x in countup(0, getVirtualScreenWidth(), 48):
    drawLine(x.int32, 0, x.int32, getVirtualScreenHeight(), Color(r: 24, g: 42, b: 58, a: 80))
  for y in countup(0, getVirtualScreenHeight(), 48):
    drawLine(0, y.int32, getVirtualScreenWidth(), y.int32, Color(r: 24, g: 42, b: 58, a: 70))
  let cx = getVirtualScreenWidth() div 2
  let cy = getVirtualScreenHeight() div 2
  for i in 0..3:
    drawCircleLines(cx, cy, (150 + i * 72).float32, withAlpha(accent, uint8(34 - i * 6)))
  drawLine(cx - 380, cy, cx + 380, cy, withAlpha(accent, 38))
  drawLine(cx, cy - 260, cx, cy + 260, withAlpha(accent, 38))

proc drawThemeGlyph(cx, cy: int32, theme: DungeonFloorTheme, color: Color) =
  ## Large card glyph for each floor theme, desktop-OS flavored.
  case theme
  of dftFirewall:
    for i in 0..2:
      let ix = i.int32
      drawLine(cx - 16 + ix * 11, cy - 15, cx - 5 + ix * 11, cy + 15, color)
    drawRectangleLines(cx - 18, cy - 14, 36, 28, withAlpha(color, 180))
  of dftRecycleBin:
    drawRectangleLines(cx - 12, cy - 8, 24, 24, color)
    drawLine(cx - 16, cy - 12, cx + 16, cy - 12, color)
    drawLine(cx - 4, cy - 17, cx + 4, cy - 17, color)
    drawLine(cx - 5, cy - 2, cx - 5, cy + 10, withAlpha(color, 200))
    drawLine(cx, cy - 2, cx, cy + 10, withAlpha(color, 200))
    drawLine(cx + 5, cy - 2, cx + 5, cy + 10, withAlpha(color, 200))
  of dftRegistry:
    drawLine(cx - 14, cy - 14, cx - 14, cy + 14, color)
    for i in 0..2:
      let iy = cy - 12 + i.int32 * 12
      drawLine(cx - 14, iy, cx - 2, iy, color)
      drawRectangleLines(cx - 2, iy - 5, 16, 10, withAlpha(color, 210))
  of dftNetwork:
    drawCircleLines(cx - 13, cy + 10, 6'f32, color)
    drawCircleLines(cx + 14, cy + 6, 6'f32, color)
    drawCircleLines(cx + 1, cy - 13, 6'f32, color)
    drawLine(cx - 9, cy + 6, cx - 2, cy - 8, color)
    drawLine(cx + 10, cy + 2, cx + 4, cy - 8, color)
    drawLine(cx - 7, cy + 11, cx + 8, cy + 8, color)
  of dftKernel:
    drawRectangleLines(cx - 16, cy - 16, 32, 32, withAlpha(color, 160))
    drawRectangleLines(cx - 10, cy - 10, 20, 20, color)
    drawRectangle(cx - 4, cy - 4, 8, 8, color)
  of dftCache:
    drawRectangleLines(cx - 16, cy - 12, 22, 18, withAlpha(color, 150))
    drawRectangleLines(cx - 8, cy - 5, 22, 18, color)
  of dftCorruptedSector:
    drawRectangleLines(cx - 14, cy - 12, 28, 24, color)
    drawRectangle(cx - 18, cy - 4, 12, 4, color)
    drawRectangle(cx + 4, cy + 2, 14, 4, withAlpha(color, 170))
    drawRectangle(cx - 6, cy - 16, 10, 3, withAlpha(color, 170))
    drawLine(cx - 10, cy + 16, cx + 12, cy + 16, withAlpha(color, 120))

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
    drawRectangleLines(cx - s - 1, cy - s div 2 - 2, (s + 1) * 2, s + 4, withAlpha(color, 180))
  of rskArcanist:
    # Arcane triangle
    drawTriangle(
      Vector2(x: cx.float32, y: (cy - s - 1).float32),
      Vector2(x: (cx - s).float32, y: (cy + s - 3).float32),
      Vector2(x: (cx + s).float32, y: (cy + s - 3).float32),
      withAlpha(color, 85))
    drawTriangleLines(
      Vector2(x: cx.float32, y: (cy - s - 1).float32),
      Vector2(x: (cx - s).float32, y: (cy + s - 3).float32),
      Vector2(x: (cx + s).float32, y: (cy + s - 3).float32),
      color)

proc drawMeter(x, y, w, h: int32, value: float32, color: Color) =
  drawRectangle(x, y, w, h, Color(r: 30, g: 36, b: 48, a: 255))
  drawRectangle(x, y, int32(w.float32 * clamp(value, 0.0'f32, 1.0'f32)), h, withAlpha(color, 210))
  drawRectangleLines(x, y, w, h, withAlpha(color, 210))

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

proc drawCloseButton(x, y: int32, color: Color, hovered: bool = false) =
  let bg = if hovered:
    Color(r: 72, g: 36, b: 42, a: 255)
  else:
    Color(r: 38, g: 44, b: 56, a: 245)
  let lineColor = if hovered: Color(r: 255, g: 150, b: 150, a: 255) else: LightGray
  drawRectangle(x, y, CloseButtonSize, CloseButtonSize, bg)
  drawRectangleLines(rectAt(x, y, CloseButtonSize, CloseButtonSize),
                     if hovered: 2 else: 1,
                     if hovered: Color(r: 255, g: 110, b: 110, a: 255) else: withAlpha(color, 180))
  drawLine(x + 8, y + 8, x + CloseButtonSize - 8, y + CloseButtonSize - 8, lineColor)
  drawLine(x + CloseButtonSize - 8, y + 8, x + 8, y + CloseButtonSize - 8, lineColor)

proc drawStatChip*(x, y, w, h: int32, label, value: string, color: Color,
                  icon: CurrencyIconType = ciNone) =
  drawRectangle(x + 3, y + 3, w, h, Color(r: 0, g: 0, b: 0, a: 90))
  drawSoftFill(x, y, w, h, Color(r: 26, g: 36, b: 54, a: 244),
               Color(r: 12, g: 18, b: 30, a: 244))
  drawRectangle(x, y, w, 2, withAlpha(color, 145))
  drawRectangle(x, y, 5, h, withAlpha(color, 215))
  drawRectangleLines(rectAt(x, y, w, h), 1, withAlpha(color, 135))
  let textX = if icon == ciNone: x + 14 else: x + 46
  let textW = w - (textX - x) - 12
  if icon != ciNone:
    drawCircle(Vector2(x: (x + 24).float32, y: (y + h div 2).float32), 17, withAlpha(color, 26))
    drawCircleLines(x + 24, y + h div 2, 17.0'f32, withAlpha(color, 75))
    drawCurrencyIcon(x + 24, y + h div 2, 24, icon)
  drawTextFit(label, textX, y + 7, textW, 10, Color(r: 156, g: 172, b: 196, a: 255), 8)
  drawTextFit(value, textX, y + 22, textW, 19, color, 10)

proc drawPill(x, y, w, h: int32, label: string, color: Color, filled: bool = false) =
  drawRectangle(x, y, w, h,
                if filled: withAlpha(color, 70) else: Color(r: 19, g: 25, b: 36, a: 225))
  drawRectangleLines(rectAt(x, y, w, h), 1, withAlpha(color, 170))
  let fontSize = bestFitFontSize(label, w - 8, 12, 8)
  discard drawCenteredTextFit(label, x + 4, y + (h - fontSize) div 2, w - 8, 12, color, 8)

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
  drawRectangle(x, y, 5, h, withAlpha(heatColor, 230))
  drawRectangleLines(x, y, w, h, Color(r: 255, g: 130, b: 80, a: 220))

  if game.rogueliteHeatPulseTimer > 0:
    let pulseT = clamp(game.rogueliteHeatPulseTimer / 0.45'f32, 0.0'f32, 1.0'f32)
    let pulseAlpha = uint8(max(0, min(190, int(pulseT * 190.0'f32))))
    let pulseColor = if game.rogueliteHeatPulseDirection >= 0: highHeatColor
                     else: Color(r: 120, g: 210, b: 255, a: 255)
    drawRectangleLines(Rectangle(x: (x - 2).float32, y: (y - 2).float32,
                                 width: (w + 4).float32, height: (h + 4).float32),
                       3, withAlpha(pulseColor, pulseAlpha))
    drawTextFit(if game.rogueliteHeatPulseDirection >= 0: t("roguelite_heat_up") else: t("roguelite_heat_down"),
                x + w - 194, y + 14, 74, 15, withAlpha(pulseColor, pulseAlpha))

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
    drawTextFit(if heatLevel == RogueliteMinHeat: t("roguelite_heat_base") else: "+" & $(heatLevel - RogueliteMinHeat),
                px + 33, pipY + 8, RogueliteHeatPipW - 42, 11,
                if unlocked: pipColor else: Color(r: 105, g: 112, b: 126, a: 255), 8)

    if selected and game.rogueliteHeatPulseTimer > 0:
      let pulseT = clamp(game.rogueliteHeatPulseTimer / 0.45'f32, 0.0'f32, 1.0'f32)
      let ringAlpha = uint8(max(0, min(180, int(pulseT * 180.0'f32))))
      drawCircleLines(px + RogueliteHeatPipW div 2, pipY + RogueliteHeatPipH div 2,
                      22.0'f32 + (1.0'f32 - pulseT) * 13.0'f32,
                      withAlpha(pipColor, ringAlpha))

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
    # Heat is EARNED: winning a run at your highest Heat unlocks the next one.
    drawTextFit(t("roguelite_heat_earn_next").replace("$1", $maxHeat).replace("$2", $(maxHeat + 1)),
                x + 18, y + h - 42, w - 140, 13, Gold)
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

proc drawPanel*(x, y, w, h: int32, title: string, color: Color, closeHovered: bool = false,
               omitTitleBar: bool = false) =
  drawRectangle(x + 7, y + 7, w, h, Color(r: 0, g: 0, b: 0, a: 115))
  drawSoftFill(x, y, w, h, Color(r: 17, g: 24, b: 38, a: 250),
               Color(r: 8, g: 13, b: 24, a: 250))
  drawRectangle(x + 10, y + 10, w - 20, h - 20, Color(r: 11, g: 18, b: 30, a: 52))
  drawScanlines(x + 8, y + 8, w - 16, h - 16, Color(r: 255, g: 255, b: 255, a: 6))
  drawCircuitLines(x + 14, y + 50, w - 28, h - 94, withAlpha(color, 24))
  if not omitTitleBar:
    drawSoftFill(x, y, w, TitleBarH, Color(r: 36, g: 54, b: 74, a: 255),
                 Color(r: 18, g: 27, b: 42, a: 255))
    drawRectangle(x, y + TitleBarH - 3, w, 3, withAlpha(color, 150))
  else:
    drawRectangle(x + 16, y + 13, w - 32, 34, Color(r: 16, g: 25, b: 40, a: 220))
    drawRectangle(x + 16, y + 45, w - 32, 2, withAlpha(color, 150))
    drawTextFit(title, x + 30, y + 21, w - 60, 18, color)
  drawRectangleLines(Rectangle(x: x.float32, y: y.float32, width: w.float32, height: h.float32), 2, withAlpha(color, 230))
  drawRectangleLines(Rectangle(x: (x + 5).float32, y: (y + 5).float32,
                               width: (w - 10).float32, height: (h - 10).float32),
                     1, withAlpha(color, 70))
  drawCornerBrackets(x + 8, y + 8, w - 16, h - 16, 28, 2, withAlpha(color, 185))
  if not omitTitleBar:
    drawTextFit(title, x + 18, y + 12, w - CloseButtonSize - 56, 18, color)
    drawCloseButton(x + w - CloseButtonSize - 10, y + (TitleBarH - CloseButtonSize) div 2,
                    color, closeHovered)

proc mouseHoverEnabled(game: Game): bool =
  game.mouseMovedRecently and not game.keyboardUsedRecently

proc isHovered(mousePos: Vector2, x, y, w, h: int32): bool =
  checkCollisionPointRec(mousePos, rectAt(x, y, w, h))

proc drawBossGlyph(cx, cy: int32, color: Color) =
  ## Warning-triangle mark for a sector's SERVICE on the theme cards.
  drawTriangle(Vector2(x: cx.float32, y: (cy - 11).float32),
               Vector2(x: (cx - 10).float32, y: (cy + 10).float32),
               Vector2(x: (cx + 10).float32, y: (cy + 10).float32), withAlpha(color, 70))
  drawTriangleLines(Vector2(x: cx.float32, y: (cy - 11).float32),
                    Vector2(x: (cx - 10).float32, y: (cy + 10).float32),
                    Vector2(x: (cx + 10).float32, y: (cy + 10).float32), color)

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
  drawRectangle(x, y, w, 2, withAlpha(color, if active or hovered: 155 else: 80))
  drawRectangleLines(rectAt(x, y, w, h), if active or hovered: 2 else: 1,
                    if active or hovered: color else: Color(r: 82, g: 92, b: 108, a: 255))
  if active:
    drawCornerBrackets(x + 4, y + 4, w - 8, h - 8, 10, 1, withAlpha(color, 150))
  let fontSize = bestFitFontSize(label, w - 14, 15, 9)
  discard drawCenteredTextFit(label, x + 7, y + (h - fontSize) div 2, w - 14, 15,
                              if active or hovered: color else: LightGray, 9)

proc drawKitCard*(game: Game, kit: RogueliteStarterKit, x, y: int32, selected: bool, hovered: bool = false) =
  ## A boot profile. All three are always available: the roguelite no longer
  ## sells them ("earn, don't buy").
  let color = if selected: Color(r: 0, g: 220, b: 255, a: 255)
              elif hovered: Color(r: 120, g: 220, b: 255, a: 255)
              else: Color(r: 120, g: 150, b: 180, a: 255)
  drawRectangle(x + 5, y + 5, CardW, CardH, Color(r: 0, g: 0, b: 0, a: if selected or hovered: 120 else: 78))
  let bgTop = if selected: Color(r: 22, g: 52, b: 66, a: 255)
              elif hovered: Color(r: 32, g: 43, b: 62, a: 255)
              else: Color(r: 24, g: 31, b: 46, a: 255)
  let bgBottom = if selected: Color(r: 11, g: 27, b: 40, a: 255)
                 elif hovered: Color(r: 18, g: 26, b: 40, a: 255)
                 else: Color(r: 14, g: 20, b: 32, a: 255)
  drawSoftFill(x, y, CardW, CardH, bgTop, bgBottom)
  drawScanlines(x + 6, y + 6, CardW - 12, CardH - 12, Color(r: 255, g: 255, b: 255, a: 5))
  drawRectangle(x, y, CardW, 76, withAlpha(color, if selected: 42 elif hovered: 34 else: 24))
  drawRectangle(x, y, CardW, 3, withAlpha(color, if selected: 220 else: 125))
  drawRectangleLines(rectAt(x, y, CardW, CardH), if selected: 3 elif hovered: 2 else: 1, color)
  drawCornerBrackets(x + 7, y + 7, CardW - 14, CardH - 14, 18, 1, withAlpha(color, if selected: 155 else: 82))
  # Emblem medallion: fills the otherwise-empty mid-body so cards read as
  # deliberate panels rather than mostly blank. Drawn before the text/pills so
  # those stay crisp on top; faint + slowly rotating to add life without noise.
  block:
    let emblemCX = x + CardW div 2
    let emblemCY = y + 176
    let baseA: uint8 = if selected: 26 elif hovered: 18 else: 11
    let lineA: uint8 = if selected: 95 elif hovered: 60 else: 36
    drawCircle(Vector2(x: emblemCX.float32, y: emblemCY.float32), 34.0'f32, withAlpha(color, baseA))
    drawCircleLines(emblemCX, emblemCY, 34.0'f32, withAlpha(color, lineA))
    drawCircleLines(emblemCX, emblemCY, 27.0'f32, withAlpha(color, uint8(lineA.int * 2 div 3)))
    for i in 0..<8:
      let a = (i.float32 / 8.0'f32) * (PI.float32 * 2.0'f32) + game.time * 0.4'f32
      let r1 = 38.0'f32
      let r2 = 43.0'f32
      drawLine((emblemCX.float32 + cos(a) * r1).int32, (emblemCY.float32 + sin(a) * r1).int32,
               (emblemCX.float32 + cos(a) * r2).int32, (emblemCY.float32 + sin(a) * r2).int32,
               withAlpha(color, uint8(lineA.int * 3 div 4)))
    drawKitGlyph(emblemCX, emblemCY, kit, withAlpha(color, 235))
  drawCircle(Vector2(x: (x + CardW - 44).float32, y: (y + 40).float32), 24, withAlpha(color, 28))
  drawCircleLines(x + CardW - 44, y + 40, 24.0'f32, withAlpha(color, 100))
  drawKitGlyph(x + CardW - 44, y + 40, kit, color)
  drawTextFit(locStarterName(kit), x + 18, y + 18, CardW - 92, 24, White)
  drawPill(x + 18, y + 52, 132, 22, t("roguelite_boot_profile"),
           Color(r: 100, g: 255, b: 150, a: 255), true)
  discard drawWrappedText(locStarterDescription(kit), x + 18, y + 96, CardW - 36, 14,
                          Color(r: 185, g: 198, b: 214, a: 255), 5, 6)
  drawPill(x + 18, y + CardH - 38, CardW - 36, 24,
           if selected: t("roguelite_starter_selected") else: t("roguelite_starter_ready"),
           Color(r: 100, g: 255, b: 170, a: 255), selected)

proc drawThemeCard(theme: DungeonFloorTheme, x, y: int32, selected: bool, floorBossNumber: int, hovered: bool = false) =
  let accent = themeAccent(theme)
  let color = if selected: Color(r: 0, g: 220, b: 255, a: 255)
              elif hovered: Color(r: 130, g: 225, b: 255, a: 255)
              else: withAlpha(accent, 220)
  let def = themeDef(theme)
  if hovered:
    drawRectangle(x + 4, y + 4, CardW, CardH, Color(r: 0, g: 0, b: 0, a: 115))
  drawRectangle(x, y, CardW, CardH,
                if hovered: Color(r: 28, g: 38, b: 56, a: 255) else: Color(r: 22, g: 28, b: 42, a: 255))
  drawRectangle(x, y, CardW, 76, withAlpha(accent, 34))
  drawRectangleLines(rectAt(x, y, CardW, CardH), if selected: 3 elif hovered: 2 else: 1, color)
  drawCircle(Vector2(x: (x + CardW - 42).float32, y: (y + 40).float32), 18, withAlpha(accent, 36))
  drawThemeGlyph(x + CardW - 42, y + 40, theme, accent)
  drawTextFit(themeName(theme), x + 16, y + 16, CardW - 82, 21, White)
  drawPill(x + 16, y + 47, 92, 22, t("roguelite_floor"), accent, false)

  # Floor boss preview
  drawBossGlyph(x + 33, y + 98, Color(r: 255, g: 120, b: 95, a: 255))
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
  drawRectangle(x, y, w, 96, withAlpha(crimson, if hovered: 44 else: 32))
  drawRectangle(x, y, w, 4, crimson)

  # Pulsing crimson border, inner gold trim, and corner brackets.
  drawRectangleLines(rectAt(x, y, w, h), 3,
                     withAlpha(crimson, borderA))
  drawRectangleLines(rectAt(x + 4, y + 4, w - 8, h - 8), 1, withAlpha(gold, 110))
  drawCornerBrackets(x + 10, y + 10, w - 20, h - 20, 28, 2,
                     withAlpha(gold, uint8(120.0'f32 + pulse * 110.0'f32)))

  # FINAL BOSS pill.
  drawPill(x + 22, y + 24, 158, 32, t("dungeon_final_floor_label"), crimson, true)

  # Pulsing boss glyph on the right.
  let glyphX = x + w - 74
  let glyphY = y + 62
  drawCircle(Vector2(x: glyphX.float32, y: glyphY.float32), 30.0'f32 + pulse * 6.0'f32,
             withAlpha(crimson, 34))
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
  let x = (getVirtualScreenWidth() - PanelW) div 2
  let y = (getVirtualScreenHeight() - PanelH) div 2
  let canHover = mouseHoverEnabled(game)
  let mousePos = if canHover: getVirtualMousePosition() else: Vector2()
  let closeHovered = canHover and checkCollisionPointRec(mousePos, rogueliteCloseButtonRect(getVirtualScreenWidth(), getVirtualScreenHeight()))
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
    let cardRect = finalBossCardRect(getVirtualScreenWidth().int32, getVirtualScreenHeight().int32)
    drawFinalBossCard(game, cardRect,
                      canHover and checkCollisionPointRec(mousePos, cardRect))
  else:
    let startX = x + 45
    let cardY = y + 185
    for i in 0..2:
      let cardX = (startX + i * (CardW + CardGap)).int32
      let floorBoss = dungeonBossNumberFor(run.nextThemeChoices[i], run.floorNumber,
                                           run.endlessLoop, run.heat)
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
    (if highlighted: withAlpha(color, 80) else: Color(r: 22, g: 30, b: 44, a: 245)),
    (if highlighted: withAlpha(color, 32) else: Color(r: 12, g: 18, b: 30, a: 245)))
  drawRectangleLines(rectAt(x, y, w, h), 2, withAlpha(color, if highlighted: 255 else: 150))
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
  let x = (getVirtualScreenWidth() - PanelW) div 2
  let y = (getVirtualScreenHeight() - PanelH) div 2
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

  # What this run paid into the wallet (never-reset tallies: by now the
  # win has already been banked, which zeroes the per-commit counters).
  let curY = chipY + 68
  drawStatChip(x + 40, curY, 300, 52, t("roguelite_run_shards"),
               "+" & $(run.totalShardsBanked + run.shardsEarned),
               Color(r: 0, g: 220, b: 255, a: 255), ciDataShards)
  drawStatChip(x + 356, curY, 260, 52, t("roguelite_run_cores"),
               "+" & $(run.totalCoresBanked + run.coresEarned),
               Color(r: 200, g: 160, b: 255, a: 255), ciCore)
  if run.heatUnlocked > 0:
    let pulse = uint8(190.0'f32 + 60.0'f32 * sin(game.time * 4.0'f32))
    drawStatChip(x + 632, curY, 248, 52, t("roguelite_heat_unlocked_label"),
                 t("roguelite_heat") & " " & $run.heatUnlocked,
                 Color(r: 255, g: 150, b: 80, a: pulse), ciHeat)

  # Patches applied during the run
  let relicY = curY + 78
  drawText(t("roguelite_relics_carried"), x + 40, relicY, 16,
           Color(r: 156, g: 172, b: 196, a: 255))
  if run.relics.len == 0:
    drawText(t("roguelite_relics_none"), x + 40, relicY + 26, 14,
             Color(r: 120, g: 130, b: 150, a: 255))
  else:
    var px = x + 40
    var py = relicY + 26
    for relic in run.relics:
      let name = patchName(relic.relicType)
      let pillW = measureText(name, 13).int32 + 50
      if px + pillW > x + PanelW - 40:
        px = x + 40
        py += 38
        if py > y + PanelH - 150: break
      let accent = patchAccent(relic.relicType)
      drawPill(px, py, pillW, 30, "", accent)
      drawPatchIcon(px + 4, py + 3, 24, relic.relicType, accent)
      drawText(name, px + 32, py + 9, 13, accent)
      px += pillW + 10

  # Decision buttons
  let rects = rogueliteVictoryButtonRects(getVirtualScreenWidth().int32, getVirtualScreenHeight().int32)
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
