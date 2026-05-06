import raylib, math, strutils
import ../types, ../roguelite, ../localization, ../render_context
import icon_drawing

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

proc locModifierName(modifier: RogueliteSectorModifier): string =
  case modifier
  of rsmSafehouse: t("roguelite_modifier_safehouse")
  of rsmOverclocked: t("roguelite_modifier_overclocked")
  of rsmEliteCache: t("roguelite_modifier_elite_cache")
  of rsmFirewall: t("roguelite_modifier_firewall")
  of rsmVolatileMemory: t("roguelite_modifier_volatile")
  of rsmBlackMarket: t("roguelite_modifier_black_market")

proc locModifierDescription(modifier: RogueliteSectorModifier): string =
  case modifier
  of rsmSafehouse: t("roguelite_modifier_safehouse_desc")
  of rsmOverclocked: t("roguelite_modifier_overclocked_desc")
  of rsmEliteCache: t("roguelite_modifier_elite_cache_desc")
  of rsmFirewall: t("roguelite_modifier_firewall_desc")
  of rsmVolatileMemory: t("roguelite_modifier_volatile_desc")
  of rsmBlackMarket: t("roguelite_modifier_black_market_desc")

proc locRewardName(reward: RogueliteRewardType): string =
  case reward
  of rrwCredits: t("roguelite_reward_credits")
  of rrwRelic: t("roguelite_reward_relic")
  of rrwPowerFamily: t("roguelite_reward_family")
  of rrwShardCache: t("roguelite_reward_shards")

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

proc drawMiniGlyph(cx, cy: int32, modifier: RogueliteSectorModifier, color: Color) =
  case modifier
  of rsmSafehouse:
    drawRectangleLines(cx - 11, cy - 8, 22, 16, color)
    drawLine(cx - 13, cy - 8, cx, cy - 20, color)
    drawLine(cx, cy - 20, cx + 13, cy - 8, color)
  of rsmOverclocked:
    drawCircleLines(cx, cy, 17, color)
    drawLine(cx, cy - 19, cx, cy + 19, color)
    drawLine(cx - 19, cy, cx + 19, cy, color)
  of rsmEliteCache:
    drawCircle(Vector2(x: cx.float32, y: cy.float32), 16, softColor(color, 70))
    drawRectangleLines(cx - 12, cy - 12, 24, 24, color)
    drawCircle(Vector2(x: cx.float32, y: cy.float32), 5, color)
  of rsmFirewall:
    for i in 0..2:
      let ix = i.int32
      drawLine(cx - 16 + ix * 11, cy - 15, cx - 5 + ix * 11, cy + 15, color)
    drawRectangleLines(cx - 18, cy - 14, 36, 28, softColor(color, 180))
  of rsmVolatileMemory:
    drawTriangle(
      Vector2(x: cx.float32, y: (cy - 19).float32),
      Vector2(x: (cx - 17).float32, y: (cy + 14).float32),
      Vector2(x: (cx + 17).float32, y: (cy + 14).float32),
      softColor(color, 85))
    drawTriangleLines(
      Vector2(x: cx.float32, y: (cy - 19).float32),
      Vector2(x: (cx - 17).float32, y: (cy + 14).float32),
      Vector2(x: (cx + 17).float32, y: (cy + 14).float32),
      color)
  of rsmBlackMarket:
    drawRectangleLines(cx - 17, cy - 13, 34, 26, color)
    drawLine(cx - 9, cy - 17, cx + 9, cy - 17, color)
    drawLine(cx - 9, cy - 17, cx - 15, cy - 13, color)
    drawLine(cx + 9, cy - 17, cx + 15, cy - 13, color)

proc drawModifierGlyph(cx, cy: int32, modifier: RogueliteSectorModifier, color: Color,
                       compact: bool = false) =
  if not compact:
    case modifier
    of rsmSafehouse:
      drawRectangleLines(cx - 8, cy - 6, 16, 12, color)
      drawLine(cx - 9, cy - 6, cx, cy - 13, color)
      drawLine(cx, cy - 13, cx + 9, cy - 6, color)
    of rsmOverclocked:
      drawCircleLines(cx, cy, 10, color)
      drawLine(cx, cy - 12, cx, cy + 12, color)
      drawLine(cx - 12, cy, cx + 12, cy, color)
    of rsmEliteCache:
      drawCircle(Vector2(x: cx.float32, y: cy.float32), 9, softColor(color, 70))
      drawRectangleLines(cx - 7, cy - 7, 14, 14, color)
      drawCircle(Vector2(x: cx.float32, y: cy.float32), 3, color)
    of rsmFirewall:
      for i in 0..2:
        let ix = i.int32
        drawLine(cx - 9 + ix * 6, cy - 8, cx - 3 + ix * 6, cy + 8, color)
      drawRectangleLines(cx - 11, cy - 7, 22, 14, softColor(color, 180))
    of rsmVolatileMemory:
      drawTriangle(
        Vector2(x: cx.float32, y: (cy - 11).float32),
        Vector2(x: (cx - 9).float32, y: (cy + 7).float32),
        Vector2(x: (cx + 9).float32, y: (cy + 7).float32),
        softColor(color, 85))
      drawTriangleLines(
        Vector2(x: cx.float32, y: (cy - 11).float32),
        Vector2(x: (cx - 9).float32, y: (cy + 7).float32),
        Vector2(x: (cx + 9).float32, y: (cy + 7).float32),
        color)
    of rsmBlackMarket:
      drawRectangleLines(cx - 10, cy - 7, 20, 14, color)
      drawLine(cx - 5, cy - 10, cx + 5, cy - 10, color)
      drawLine(cx - 5, cy - 10, cx - 8, cy - 7, color)
      drawLine(cx + 5, cy - 10, cx + 8, cy - 7, color)
    return

  case modifier
  of rsmSafehouse:
    drawRectangleLines(cx - 6, cy - 4, 12, 8, color)
    drawLine(cx - 7, cy - 4, cx, cy - 9, color)
    drawLine(cx, cy - 9, cx + 7, cy - 4, color)
  of rsmOverclocked:
    drawCircleLines(cx, cy, 7, color)
    drawLine(cx, cy - 9, cx, cy + 9, color)
    drawLine(cx - 9, cy, cx + 9, cy, color)
  of rsmEliteCache:
    drawCircle(Vector2(x: cx.float32, y: cy.float32), 6, softColor(color, 70))
    drawRectangleLines(cx - 5, cy - 5, 10, 10, color)
    drawCircle(Vector2(x: cx.float32, y: cy.float32), 2, color)
  of rsmFirewall:
    for i in 0..2:
      let ix = i.int32
      drawLine(cx - 7 + ix * 4, cy - 6, cx - 3 + ix * 4, cy + 6, color)
    drawRectangleLines(cx - 7, cy - 5, 14, 10, softColor(color, 180))
  of rsmVolatileMemory:
    drawTriangle(
      Vector2(x: cx.float32, y: (cy - 8).float32),
      Vector2(x: (cx - 7).float32, y: (cy + 5).float32),
      Vector2(x: (cx + 7).float32, y: (cy + 5).float32),
      softColor(color, 85))
    drawTriangleLines(
      Vector2(x: cx.float32, y: (cy - 8).float32),
      Vector2(x: (cx - 7).float32, y: (cy + 5).float32),
      Vector2(x: (cx + 7).float32, y: (cy + 5).float32),
      color)
  of rsmBlackMarket:
    drawRectangleLines(cx - 7, cy - 5, 14, 10, color)
    drawLine(cx - 4, cy - 7, cx + 4, cy - 7, color)
    drawLine(cx - 4, cy - 7, cx - 6, cy - 5, color)
    drawLine(cx + 4, cy - 7, cx + 6, cy - 5, color)

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
  drawRectangle(x + 2, y + 2, w, h, Color(r: 0, g: 0, b: 0, a: 70))
  drawRectangle(x, y, w, h, Color(r: 22, g: 29, b: 42, a: 235))
  drawRectangle(x, y, 4, h, softColor(color, 220))
  drawRectangleLines(rectAt(x, y, w, h), 1, softColor(color, 120))
  let textX = if icon == ciNone: x + 13 else: x + 42
  let textW = w - (textX - x) - 11
  if icon != ciNone:
    drawCurrencyIcon(x + 23, y + h div 2, 26, icon)
  drawTextFit(label, textX, y + 7, textW, 11, Color(r: 150, g: 166, b: 186, a: 255))
  drawTextFit(value, textX, y + 23, textW, 18, color)

proc drawPill(x, y, w, h: int32, label: string, color: Color, filled: bool = false) =
  drawRectangle(x, y, w, h,
                if filled: softColor(color, 70) else: Color(r: 19, g: 25, b: 36, a: 225))
  drawRectangleLines(rectAt(x, y, w, h), 1, softColor(color, 170))
  let fontSize = bestFitFontSize(label, w - 8, 12, 8)
  discard drawCenteredTextFit(label, x + 4, y + (h - fontSize) div 2, w - 8, 12, color, 8)

proc unlockCostLabel(profile: RogueliteProfile, category: RogueliteUnlockCategory, index: int): string =
  var parts: seq[string] = @[]
  let shardCost = unlockCost(profile, category, index)
  let overheatCost = unlockOverheatCoreCost(profile, category, index)
  let singularityCost = unlockSingularityCoreCost(profile, category, index)
  if shardCost > 0:
    parts.add($shardCost & " " & t("roguelite_shards_short"))
  if overheatCost > 0:
    parts.add($overheatCost & " " & t("roguelite_overheat_short"))
  if singularityCost > 0:
    parts.add($singularityCost & " " & t("roguelite_singularity_short"))
  if parts.len == 0:
    t("roguelite_unlocked")
  else:
    parts.join(" + ")

proc drawUnlockCostsRight*(profile: RogueliteProfile, category: RogueliteUnlockCategory, index: int,
                          rightX, topY, iconSize, fontSize: int32, color: Color) =
  ## Draw unlock costs right-aligned starting from `rightX`. Shows icons and amounts.
  var rx = rightX
  let shardCost = unlockCost(profile, category, index)
  let overheatCost = unlockOverheatCoreCost(profile, category, index)
  let singularityCost = unlockSingularityCoreCost(profile, category, index)
  var parts: seq[tuple[icon: CurrencyIconType, amount: int]] = @[]
  if singularityCost > 0:
    parts.add((icon: ciSingularityCore, amount: singularityCost))
  if overheatCost > 0:
    parts.add((icon: ciOverheatCore, amount: overheatCost))
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
  let heatPressurePercent = int(round(heatRank.float32 *
    RogueliteHeatPressurePerTier * 100.0'f32))
  let heatShardPercent = int(round(heatRank.float32 *
    RogueliteHeatShardMultiplierPerTier * 100.0'f32))
  drawTextFit(t("roguelite_heat_effects") & ": +" & $heatPressurePercent & "% " &
              t("roguelite_pressure") & ", +" &
              $(heatRank * RogueliteHeatEliteBonusPerTier) & " " &
              t("roguelite_elite") & ", +" & $heatShardPercent & "% " &
              t("roguelite_shards"), x + 230, y + 13, w - 370, 13, LightGray)

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
    # Draw the required currencies for the next heat to the right
    drawUnlockCostsRight(profile, rucChallengeTiers, 0,
                         (x + w - 36).int32, (y + h - 44).int32, 16, 12, Gold)
  drawTextFit(t("roguelite_heat_core_rule"), x + 18, y + h - 22, w - 36, 12,
              Color(r: 180, g: 192, b: 210, a: 255), 8)

proc drawProgressRail(run: RogueliteRun, x, y, w: int32) =
  let totalNodes = RogueliteSectorsPerAct + 1
  let step = w div (totalNodes - 1).int32
  drawText(t("roguelite_run_flow"), x, y - 24, 15, Color(r: 150, g: 220, b: 255, a: 255))
  for i in 0..<totalNodes:
    let px = x + i.int32 * step
    if i < totalNodes - 1:
      drawLine(px, y, px + step, y, Color(r: 70, g: 95, b: 120, a: 255))
    let completed = run.sectorsThisAct > i
    let current = run.sectorsThisAct == i
    let color = if i == totalNodes - 1: Color(r: 255, g: 120, b: 80, a: 255)
                elif completed: Color(r: 0, g: 240, b: 160, a: 255)
                elif current: Color(r: 0, g: 220, b: 255, a: 255)
                else: Color(r: 90, g: 105, b: 125, a: 255)
    drawCircle(Vector2(x: px.float32, y: y.float32), if current: 10 else: 7, color)
    let label = if i == totalNodes - 1: t("roguelite_boss") else: t("roguelite_sector") & " " & $(i + 1)
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
      t("roguelite_unlock_boss_tier") & " " & $nextTier

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
    else: t("roguelite_unlock_desc_boss_tier")

proc drawPanel*(x, y, w, h: int32, title: string, color: Color, closeHovered: bool = false,
               omitTitleBar: bool = false) =
  drawRectangle(x + 4, y + 4, w, h, Color(r: 0, g: 0, b: 0, a: 110))
  drawRectangle(x, y, w, h, Color(r: 18, g: 24, b: 36, a: 245))
  if not omitTitleBar:
    drawRectangle(x, y, w, TitleBarH, Color(r: 28, g: 44, b: 62, a: 255))
    drawRectangle(x, y + TitleBarH - 2, w, 2, softColor(color, 130))
  drawRectangleLines(Rectangle(x: x.float32, y: y.float32, width: w.float32, height: h.float32), 2, color)
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
    drawModifierGlyph(cx, cy, rsmSafehouse, color, compact)
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
    let kit = starterByUnlockIndex(index)
    drawModifierGlyph(cx, cy, if kit == rskBulwark: rsmFirewall elif kit == rskArcanist: rsmVolatileMemory else: rsmSafehouse, color, compact)
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
      drawModifierGlyph(cx, cy, rsmEliteCache, color, compact)

proc drawRewardGlyph(cx, cy: int32, reward: RogueliteRewardType, color: Color) =
  case reward
  of rrwCredits:
    drawCurrencyIcon(cx, cy, 24, ciCredits)
  of rrwRelic:
    drawCategoryGlyph(cx, cy, rucRelics, color)
  of rrwPowerFamily:
    drawCategoryGlyph(cx, cy, rucPowerFamilies, color)
  of rrwShardCache:
    drawCurrencyIcon(cx, cy, 24, ciDataShards)

proc drawSmallButton*(x, y, w, h: int32, label: string, active: bool, color: Color, hovered: bool = false) =
  let bg = if active: Color(r: 38, g: 76, b: 92, a: 255)
           elif hovered: Color(r: 48, g: 60, b: 76, a: 255)
           else: Color(r: 38, g: 44, b: 56, a: 255)
  if hovered:
    drawRectangle(x + 2, y + 2, w, h, Color(r: 0, g: 0, b: 0, a: 95))
  drawRectangle(x, y, w, h, bg)
  drawRectangleLines(rectAt(x, y, w, h), if active or hovered: 2 else: 1,
                    if active or hovered: color else: Color(r: 82, g: 92, b: 108, a: 255))
  let fontSize = bestFitFontSize(label, w - 14, 15, 9)
  discard drawCenteredTextFit(label, x + 7, y + (h - fontSize) div 2, w - 14, 15,
                              if active or hovered: color else: LightGray, 9)

proc drawKitCard*(game: Game, kit: RogueliteStarterKit, x, y: int32, selected, unlocked: bool, hovered: bool = false) =
  let color = if selected: Color(r: 0, g: 220, b: 255, a: 255)
              elif hovered: Color(r: 120, g: 220, b: 255, a: 255)
              elif unlocked: Color(r: 120, g: 150, b: 180, a: 255)
              else: Color(r: 80, g: 80, b: 92, a: 255)
  if hovered:
    drawRectangle(x + 4, y + 4, CardW, CardH, Color(r: 0, g: 0, b: 0, a: 115))
  drawRectangle(x, y, CardW, CardH,
                if hovered: Color(r: 30, g: 40, b: 58, a: 255) else: Color(r: 24, g: 30, b: 44, a: 255))
  drawRectangle(x, y, CardW, 76, softColor(color, 28))
  drawRectangleLines(rectAt(x, y, CardW, CardH), if selected: 3 elif hovered: 2 else: 1, color)
  drawCircle(Vector2(x: (x + CardW - 44).float32, y: (y + 40).float32), 18, softColor(color, 36))
  drawMiniGlyph(x + CardW - 44, y + 40, if kit == rskBulwark: rsmFirewall elif kit == rskArcanist: rsmVolatileMemory else: rsmSafehouse, color)
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
  let overheatCores = if profile.isNil: 0 else: profile.overheatCores
  let singularityCores = if profile.isNil: 0 else: profile.singularityCores
  let maxHeat = if profile.isNil: RogueliteMinHeat else: profile.highestHeat
  let bossTier = if profile.isNil: 1 else: profile.unlockedBossTier
  drawStatChip(x + 26, y + 58, 164, 48, t("roguelite_data_shards"), $shards, Gold, ciDataShards)
  drawStatChip(x + 202, y + 58, 164, 48, t("roguelite_overheat_cores"), $overheatCores,
               Color(r: 255, g: 130, b: 80, a: 255), ciOverheatCore)
  drawStatChip(x + 378, y + 58, 164, 48, t("roguelite_singularity_cores"), $singularityCores,
               Color(r: 170, g: 110, b: 255, a: 255), ciSingularityCore)
  drawStatChip(x + 554, y + 58, 150, 48, t("roguelite_heat"), $maxHeat & " / " & $RogueliteMaxHeat,
               Color(r: 255, g: 150, b: 80, a: 255), ciHeat)
  drawStatChip(x + 716, y + 58, 178, 48, t("roguelite_boss_tier"), $bossTier,
               Color(r: 255, g: 120, b: 95, a: 255))

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

proc drawSectorCard(sector: RogueliteSector, x, y: int32, selected: bool, hovered: bool = false) =
  let color = if selected: Color(r: 0, g: 220, b: 255, a: 255)
              elif hovered: Color(r: 130, g: 225, b: 255, a: 255)
              elif sector.isElite: Color(r: 255, g: 120, b: 80, a: 255)
              else: Color(r: 120, g: 150, b: 180, a: 255)
  if hovered:
    drawRectangle(x + 4, y + 4, CardW, CardH, Color(r: 0, g: 0, b: 0, a: 115))
  drawRectangle(x, y, CardW, CardH,
                if hovered: Color(r: 28, g: 38, b: 56, a: 255) else: Color(r: 22, g: 28, b: 42, a: 255))
  drawRectangle(x, y, CardW, 76, softColor(color, 34))
  drawRectangleLines(rectAt(x, y, CardW, CardH), if selected: 3 elif hovered: 2 else: 1, color)
  drawCircle(Vector2(x: (x + CardW - 42).float32, y: (y + 40).float32), 18, softColor(color, 36))
  drawMiniGlyph(x + CardW - 42, y + 40, sector.modifier, color)
  drawTextFit(locModifierName(sector.modifier), x + 16, y + 16, CardW - 82, 21, White)
  drawPill(x + 16, y + 47, 92, 22, if sector.isElite: t("roguelite_elite") else: t("roguelite_sector"),
           color, sector.isElite)

  drawRewardGlyph(x + 33, y + 98, sector.rewardType, Gold)
  drawTextFit(locRewardName(sector.rewardType), x + 58, y + 90, CardW - 74, 15, Gold)
  drawTextFit(t("roguelite_waves") & ": " & $sector.waveCount, x + 58, y + 110, CardW - 74, 13, LightGray)

  drawTextFit(t("roguelite_pressure") & ": " & $(int(sector.enemyPressure * 100)) & "%", x + 16, y + 139, 116, 13, LightGray)
  drawMeter(x + 136, y + 143, 104, 8, (sector.enemyPressure - 0.9) / 1.8, color)
  drawTextFit(t("roguelite_elite") & ": +" & $sector.eliteChanceBonus, x + 16, y + 163, 116, 13, LightGray)
  drawMeter(x + 136, y + 167, 104, 8, sector.eliteChanceBonus.float32 / 60.0'f32, Color(r: 255, g: 130, b: 80, a: 255))
  drawTextFit(t("roguelite_shards") & ": x" & $round(sector.shardMultiplier * 100).int & "%", x + 16, y + 187, 116, 13, Gold)
  drawMeter(x + 136, y + 191, 104, 8, (sector.shardMultiplier - 0.8) / 1.3, Gold)
  discard drawWrappedText(locModifierDescription(sector.modifier), x + 16, y + 215, CardW - 32, 13,
                          Color(r: 180, g: 192, b: 210, a: 255), 2, 4)

proc drawRogueliteSectorSelect*(game: Game) =
  let x = (game.screenWidth - PanelW) div 2
  let y = (game.screenHeight - PanelH) div 2
  let canHover = mouseHoverEnabled(game)
  let mousePos = if canHover: getVirtualMousePosition() else: Vector2()
  let closeHovered = canHover and checkCollisionPointRec(mousePos, rogueliteCloseButtonRect(game.screenWidth, game.screenHeight))
  drawBackdrop(game, Color(r: 0, g: 220, b: 255, a: 255))
  drawPanel(x, y, PanelW, PanelH, t("roguelite_sector_title"), Color(r: 0, g: 220, b: 255, a: 255), closeHovered)

  if game.rogueliteRun.isNil:
    drawText(t("roguelite_no_run"), x + 40, y + 90, 22, Red)
    return

  let run = game.rogueliteRun
  drawStatChip(x + 28, y + 58, 190, 48, t("roguelite_act"), $run.act,
               Color(r: 150, g: 220, b: 255, a: 255))
  drawStatChip(x + 236, y + 58, 210, 48, t("roguelite_sector"),
               $(run.sectorsThisAct + 1) & " / " & $RogueliteSectorsPerAct,
               Color(r: 0, g: 220, b: 255, a: 255))
  drawStatChip(x + 464, y + 58, 180, 48, t("roguelite_heat"), $run.heat,
               Color(r: 255, g: 150, b: 80, a: 255), ciHeat)
  drawStatChip(x + 662, y + 58, 230, 48, t("roguelite_endless"), $run.endlessLoop,
               Color(r: 255, g: 210, b: 110, a: 255))

  drawProgressRail(run, x + 120, y + 132, 680)

  let startX = x + 45
  let cardY = y + 185
  for i in 0..2:
    let cardX = (startX + i * (CardW + CardGap)).int32
    drawSectorCard(run.nextSectorChoices[i], cardX, cardY.int32,
                   i == game.selectedRogueliteSector,
                   canHover and isHovered(mousePos, cardX, cardY.int32, CardW, CardH))

  drawCenteredTextFit(t("roguelite_sector_tip"), x + 60, y + PanelH - 63, PanelW - 120, 14, Color(r: 255, g: 210, b: 110, a: 255))
  drawCenteredTextFit(t("roguelite_sector_controls"), x + 60, y + PanelH - 35, PanelW - 120, 15, LightGray)

proc drawRogueliteUnlocks*(game: Game, categoryIndex: int = 0, itemIndex: int = 0) =
  let x = (game.screenWidth - PanelW) div 2
  let y = (game.screenHeight - PanelH) div 2
  let canHover = mouseHoverEnabled(game)
  let mousePos = if canHover: getVirtualMousePosition() else: Vector2()
  let closeHovered = canHover and checkCollisionPointRec(mousePos, rogueliteCloseButtonRect(game.screenWidth, game.screenHeight))
  let accent = Color(r: 255, g: 215, b: 0, a: 255)
  drawBackdrop(game, Color(r: 255, g: 215, b: 0, a: 255))
  drawPanel(x, y, PanelW, PanelH, t("roguelite_unlocks_title"), accent, closeHovered)
  if game.rogueliteProfile.isNil:
    drawText(t("roguelite_no_profile"), x + 40, y + 90, 22, Red)
    return

  let profile = game.rogueliteProfile
  let category = categoryByIndex(categoryIndex)
  let itemCount = unlockCount(category)
  let selectedItem = clamp(itemIndex, 0, max(0, itemCount - 1))
  let selectedName = locUnlockName(profile, category, selectedItem)
  let selectedPurchased = isUnlockPurchased(profile, category, selectedItem)
  let selectedCanBuy = canPurchaseUnlock(profile, category, selectedItem)
  let categoryAccent = categoryColor(category)

  drawStatChip(x + 26, y + 58, 164, 48, t("roguelite_data_shards"), $profile.dataShards, Gold, ciDataShards)
  drawStatChip(x + 202, y + 58, 164, 48, t("roguelite_overheat_cores"), $profile.overheatCores,
               Color(r: 255, g: 130, b: 80, a: 255), ciOverheatCore)
  drawStatChip(x + 378, y + 58, 164, 48, t("roguelite_singularity_cores"), $profile.singularityCores,
               Color(r: 170, g: 110, b: 255, a: 255), ciSingularityCore)
  drawStatChip(x + 554, y + 58, 150, 48, t("roguelite_heat"), $profile.highestHeat & " / " & $RogueliteMaxHeat,
               Color(r: 255, g: 150, b: 80, a: 255), ciHeat)
  drawStatChip(x + 716, y + 58, 178, 48, t("roguelite_boss_tier"), $profile.unlockedBossTier & " / " & $RogueliteMaxBossTier,
               Color(r: 255, g: 120, b: 95, a: 255))

  let contentY = y + 130
  let navX = x + 30
  let navW: int32 = 184
  let listX = x + 232
  let listW: int32 = 340
  let detailsX = x + 594
  let detailsW: int32 = 296
  let sectionH: int32 = 378

  drawRectangle(navX, contentY, navW, sectionH, Color(r: 18, g: 25, b: 38, a: 220))
  drawRectangleLines(navX, contentY, navW, sectionH, softColor(accent, 120))
  drawTextFit(t("roguelite_unlock_categories"), navX + 14, contentY + 12, navW - 28, 14, accent)
  for idx in 0..3:
    let cat = categoryByIndex(idx)
    let rowY = contentY + 44 + idx.int32 * 72
    let active = idx == categoryIndex
    let hovered = canHover and isHovered(mousePos, navX + 12, rowY, navW - 24, 58)
    let color = categoryColor(cat)
    drawRectangle(navX + 12, rowY, navW - 24, 58,
                  if active: softColor(color, 58)
                  elif hovered: Color(r: 32, g: 40, b: 55, a: 240)
                  else: Color(r: 23, g: 30, b: 43, a: 230))
    drawRectangleLines(navX + 12, rowY, navW - 24, 58,
                       if active or hovered: color else: Color(r: 82, g: 94, b: 112, a: 255))
    drawCategoryGlyph(navX + 36, rowY + 29, cat, color)
    drawTextFit(locCategoryName(cat), navX + 62, rowY + 12, navW - 86, 15,
                if active or hovered: White else: LightGray)
    var ownedCount = 0
    for unlockIdx in 0..<unlockCount(cat):
      if isUnlockPurchased(profile, cat, unlockIdx):
        inc ownedCount
    drawTextFit($ownedCount & " / " & $unlockCount(cat), navX + 62, rowY + 34, navW - 86, 11,
                if active: color else: Color(r: 125, g: 140, b: 160, a: 255))

  drawRectangle(listX, contentY, listW, sectionH, Color(r: 18, g: 25, b: 38, a: 220))
  drawRectangleLines(listX, contentY, listW, sectionH, softColor(categoryAccent, 130))
  drawCategoryGlyph(listX + 26, contentY + 26, category, categoryAccent)
  drawTextFit(locCategoryName(category), listX + 52, contentY + 14, listW - 66, 17, categoryAccent)
  discard drawWrappedText(t("roguelite_unlock_shop_hint"), listX + 16, contentY + 41, listW - 32, 11,
                          Color(r: 170, g: 182, b: 202, a: 255), 2, 3, 8)
  for idx in 0..<itemCount:
    let rowY = contentY + 80 + idx.int32 * 33
    let purchased = isUnlockPurchased(profile, category, idx)
    let canBuy = canPurchaseUnlock(profile, category, idx)
    let active = idx == selectedItem
    let hovered = canHover and isHovered(mousePos, listX + 12, rowY, listW - 24, 28)
    let color = if active: Color(r: 0, g: 220, b: 255, a: 255)
                elif hovered: Color(r: 120, g: 225, b: 255, a: 255)
                elif purchased: Color(r: 0, g: 210, b: 140, a: 255)
                elif canBuy: Gold
                else: Color(r: 95, g: 112, b: 135, a: 255)
    drawRectangle(listX + 12, rowY, listW - 24, 28,
                  if active: Color(r: 25, g: 48, b: 62, a: 240)
                  elif hovered: Color(r: 28, g: 40, b: 56, a: 235)
                  else: Color(r: 22, g: 29, b: 42, a: 220))
    drawRectangleLines(listX + 12, rowY, listW - 24, 28, color)
    drawUnlockGlyph(profile, category, idx.int32, listX + 30, rowY + 14, color, true)
    drawTextFit(locUnlockName(profile, category, idx), listX + 50, rowY + 8, 142, 12,
                if purchased or active or hovered: White else: LightGray)
    if purchased:
      discard drawTextFit(t("roguelite_unlocked"), listX + listW - 156, rowY + 9, 130, 11, color, 8, taRight)
    else:
      # show currency icons and amounts right-aligned instead of plain text
      drawUnlockCostsRight(profile, category, idx, (listX + listW - 24).int32, (rowY + 8).int32, 14, 11, color)

  drawRectangle(detailsX, contentY, detailsW, sectionH, Color(r: 20, g: 27, b: 40, a: 240))
  drawRectangleLines(detailsX, contentY, detailsW, sectionH, softColor(categoryAccent, 165))
  drawCircle(Vector2(x: (detailsX + 40).float32, y: (contentY + 44).float32), 18, softColor(categoryAccent, 42))
  drawUnlockGlyph(profile, category, selectedItem.int32, detailsX + 40, contentY + 44, categoryAccent)
  drawTextFit(t("roguelite_unlock_details"), detailsX + 82, contentY + 18, detailsW - 100, 13, Gold)
  drawTextFit(selectedName, detailsX + 82, contentY + 42, detailsW - 100, 21, White)
  let stateText = if selectedPurchased: t("roguelite_unlocked")
                  elif selectedCanBuy: t("roguelite_ready_to_buy")
                  else: t("roguelite_not_enough_shards")
  let stateColor = if selectedPurchased: Color(r: 0, g: 230, b: 150, a: 255)
                   elif selectedCanBuy: Gold
                   else: Color(r: 255, g: 120, b: 100, a: 255)
  drawPill(detailsX + 18, contentY + 90, 128, 24, stateText, stateColor, selectedPurchased or selectedCanBuy)
  drawPill(detailsX + 156, contentY + 90, detailsW - 174, 24,
           if selectedPurchased: t("roguelite_unlocked") else: unlockCostLabel(profile, category, selectedItem), Gold)
  discard drawWrappedText(locUnlockDescription(category, selectedItem), detailsX + 18, contentY + 134, detailsW - 36, 13,
                          Color(r: 190, g: 204, b: 220, a: 255), 6, 5)

  let buyY = contentY + sectionH - 58
  let buyButtonWidth: int32 = 220
  let buyButtonHeight: int32 = 38
  let buyButtonX: int32 = detailsX + detailsW - buyButtonWidth - 24
  let buyButtonY: int32 = buyY
  # buy button area

  # Buy button (modern shop style)
  let canBuy = selectedCanBuy
  if canBuy:
    drawRectangle(buyButtonX + 2, buyButtonY + 2, buyButtonWidth, buyButtonHeight,
                  Color(r: 0, g: 0, b: 0, a: 100))

  let buyBgColor = if canBuy: Color(r: 0, g: 140, b: 255, a: 255) else: Color(r: 55, g: 60, b: 70, a: 255)
  drawRectangle(buyButtonX, buyButtonY, buyButtonWidth, buyButtonHeight, buyBgColor)
  if canBuy:
    drawRectangle(buyButtonX, buyButtonY, buyButtonWidth, 2, Color(r: 255, g: 255, b: 255, a: 40))

  let buyBorderColor = if canBuy:
    let pulse = sin(game.time * 6.0) * 0.3 + 0.7
    Color(r: 0, g: 200, b: 255, a: uint8(220 * pulse))
  else:
    Color(r: 100, g: 110, b: 120, a: 255)

  drawRectangleLines(Rectangle(x: buyButtonX.float32, y: buyButtonY.float32,
                                width: buyButtonWidth.float32, height: buyButtonHeight.float32),
                    2.5, buyBorderColor)

  let buyText = if selectedPurchased: t("roguelite_already_unlocked")
                elif selectedCanBuy: t("roguelite_buy_unlock")
                else: t("roguelite_need_more_shards")
  let buyTextWidth: int32 = int32(measureText(buyText, 16))
  let buyTextX: int32 = buyButtonX + (buyButtonWidth - buyTextWidth) div 2
  drawText(buyText, buyTextX + 1, buyButtonY + 13, 16, Color(r: 0, g: 0, b: 0, a: 120))
  drawText(buyText, buyTextX, buyButtonY + 12, 16, if canBuy: White else: Color(r: 150, g: 155, b: 160, a: 255))

  drawRectangle(x + 42, y + PanelH - 72, PanelW - 84, 32, Color(r: 25, g: 32, b: 45, a: 230))
  drawRectangleLines(x + 42, y + PanelH - 72, PanelW - 84, 32, softColor(accent, 130))
  drawCenteredTextFit(t("roguelite_unlock_shop_controls"), x + 58, y + PanelH - 62, PanelW - 116, 13, LightGray)

proc drawUnlocksContent*(game: Game, panelX, panelY: int32, categoryIndex, itemIndex: int) =
  ## Draw the inner unlocks UI at the given panel origin (no backdrop or outer panel chrome).
  ## Used when the unlocks view is embedded inside the roguelite setup window.
  if game.rogueliteProfile.isNil:
    drawText(t("roguelite_no_profile"), panelX + 40, panelY + 90, 22, Red)
    return

  let profile = game.rogueliteProfile
  let category = categoryByIndex(categoryIndex)
  let itemCount = unlockCount(category)
  let selectedItem = clamp(itemIndex, 0, max(0, itemCount - 1))
  let selectedName = locUnlockName(profile, category, selectedItem)
  let selectedPurchased = isUnlockPurchased(profile, category, selectedItem)
  let selectedCanBuy = canPurchaseUnlock(profile, category, selectedItem)
  let categoryAccent = categoryColor(category)
  let accent = Color(r: 255, g: 215, b: 0, a: 255)
  let canHover = game.mouseMovedRecently and not game.keyboardUsedRecently
  let mousePos = if canHover: getVirtualMousePosition() else: Vector2()

  # Stat chips (same as the setup view)
  drawStatChip(panelX + 26, panelY + 58, 164, 48, t("roguelite_data_shards"), $profile.dataShards, Gold, ciDataShards)
  drawStatChip(panelX + 202, panelY + 58, 164, 48, t("roguelite_overheat_cores"), $profile.overheatCores,
               Color(r: 255, g: 130, b: 80, a: 255), ciOverheatCore)
  drawStatChip(panelX + 378, panelY + 58, 164, 48, t("roguelite_singularity_cores"), $profile.singularityCores,
               Color(r: 170, g: 110, b: 255, a: 255), ciSingularityCore)
  drawStatChip(panelX + 554, panelY + 58, 150, 48, t("roguelite_heat"), $profile.highestHeat & " / " & $RogueliteMaxHeat,
               Color(r: 255, g: 150, b: 80, a: 255), ciHeat)
  drawStatChip(panelX + 716, panelY + 58, 178, 48, t("roguelite_boss_tier"), $profile.unlockedBossTier & " / " & $RogueliteMaxBossTier,
               Color(r: 255, g: 120, b: 95, a: 255))

  let contentY = panelY + 130
  let navX = panelX + 30
  let navW: int32 = 184
  let listX = panelX + 232
  let listW: int32 = 340
  let detailsX = panelX + 594
  let detailsW: int32 = 296
  let sectionH: int32 = 378

  drawRectangle(navX, contentY, navW, sectionH, Color(r: 18, g: 25, b: 38, a: 220))
  drawRectangleLines(navX, contentY, navW, sectionH, softColor(accent, 120))
  drawTextFit(t("roguelite_unlock_categories"), navX + 14, contentY + 12, navW - 28, 14, accent)
  for idx in 0..3:
    let cat = categoryByIndex(idx)
    let rowY = contentY + 44 + idx.int32 * 72
    let active = idx == categoryIndex
    let hovered = canHover and isHovered(mousePos, navX + 12, rowY, navW - 24, 58)
    let color = categoryColor(cat)
    drawRectangle(navX + 12, rowY, navW - 24, 58,
                  if active: softColor(color, 58)
                  elif hovered: Color(r: 32, g: 40, b: 55, a: 240)
                  else: Color(r: 23, g: 30, b: 43, a: 230))
    drawRectangleLines(navX + 12, rowY, navW - 24, 58,
                       if active or hovered: color else: Color(r: 82, g: 94, b: 112, a: 255))
    drawCategoryGlyph(navX + 36, rowY + 29, cat, color)
    drawTextFit(locCategoryName(cat), navX + 62, rowY + 12, navW - 86, 15,
                if active or hovered: White else: LightGray)
    var ownedCount = 0
    for unlockIdx in 0..<unlockCount(cat):
      if isUnlockPurchased(profile, cat, unlockIdx):
        inc ownedCount
    drawTextFit($ownedCount & " / " & $unlockCount(cat), navX + 62, rowY + 34, navW - 86, 11,
                if active: color else: Color(r: 125, g: 140, b: 160, a: 255))

  drawRectangle(listX, contentY, listW, sectionH, Color(r: 18, g: 25, b: 38, a: 220))
  drawRectangleLines(listX, contentY, listW, sectionH, softColor(categoryAccent, 130))
  drawCategoryGlyph(listX + 26, contentY + 26, category, categoryAccent)
  drawTextFit(locCategoryName(category), listX + 52, contentY + 14, listW - 66, 17, categoryAccent)
  discard drawWrappedText(t("roguelite_unlock_shop_hint"), listX + 16, contentY + 41, listW - 32, 11,
                          Color(r: 170, g: 182, b: 202, a: 255), 2, 3, 8)
  for idx in 0..<itemCount:
    let rowY = contentY + 80 + idx.int32 * 33
    let purchased = isUnlockPurchased(profile, category, idx)
    let canBuy = canPurchaseUnlock(profile, category, idx)
    let active = idx == selectedItem
    let hovered = canHover and isHovered(mousePos, listX + 12, rowY, listW - 24, 28)
    let color = if active: Color(r: 0, g: 220, b: 255, a: 255)
                elif hovered: Color(r: 120, g: 225, b: 255, a: 255)
                elif purchased: Color(r: 0, g: 210, b: 140, a: 255)
                elif canBuy: Gold
                else: Color(r: 95, g: 112, b: 135, a: 255)
    drawRectangle(listX + 12, rowY, listW - 24, 28,
                  if active: Color(r: 25, g: 48, b: 62, a: 240)
                  elif hovered: Color(r: 28, g: 40, b: 56, a: 235)
                  else: Color(r: 22, g: 29, b: 42, a: 220))
    drawRectangleLines(listX + 12, rowY, listW - 24, 28, color)
    drawUnlockGlyph(profile, category, idx.int32, listX + 30, rowY + 14, color, true)
    drawTextFit(locUnlockName(profile, category, idx), listX + 50, rowY + 8, 142, 12,
                if purchased or active or hovered: White else: LightGray)
    if purchased:
      discard drawTextFit(t("roguelite_unlocked"), listX + listW - 156, rowY + 9, 130, 11, color, 8, taRight)
    else:
      drawUnlockCostsRight(profile, category, idx, (listX + listW - 24).int32, (rowY + 8).int32, 14, 11, color)

  drawRectangle(detailsX, contentY, detailsW, sectionH, Color(r: 20, g: 27, b: 40, a: 240))
  drawRectangleLines(detailsX, contentY, detailsW, sectionH, softColor(categoryAccent, 165))
  drawCircle(Vector2(x: (detailsX + 40).float32, y: (contentY + 44).float32), 18, softColor(categoryAccent, 42))
  drawUnlockGlyph(profile, category, selectedItem.int32, detailsX + 40, contentY + 44, categoryAccent)
  drawTextFit(t("roguelite_unlock_details"), detailsX + 82, contentY + 18, detailsW - 100, 13, Gold)
  drawTextFit(selectedName, detailsX + 82, contentY + 42, detailsW - 100, 21, White)
  let stateText = if selectedPurchased: t("roguelite_unlocked")
                  elif selectedCanBuy: t("roguelite_ready_to_buy")
                  else: t("roguelite_not_enough_shards")
  let stateColor = if selectedPurchased: Color(r: 0, g: 230, b: 150, a: 255)
                   elif selectedCanBuy: Gold
                   else: Color(r: 255, g: 120, b: 100, a: 255)
  drawPill(detailsX + 18, contentY + 90, 128, 24, stateText, stateColor, selectedPurchased or selectedCanBuy)
  drawPill(detailsX + 156, contentY + 90, detailsW - 174, 24,
           if selectedPurchased: t("roguelite_unlocked") else: unlockCostLabel(profile, category, selectedItem), Gold)
  discard drawWrappedText(locUnlockDescription(category, selectedItem), detailsX + 18, contentY + 134, detailsW - 36, 13,
                          Color(r: 190, g: 204, b: 220, a: 255), 6, 5)

  let buyY = contentY + sectionH - 58
  let buyButtonWidth: int32 = 220
  let buyButtonHeight: int32 = 38
  let buyButtonX: int32 = detailsX + detailsW - buyButtonWidth - 24
  let buyButtonY: int32 = buyY
  let canBuy = selectedCanBuy
  if canBuy:
    drawRectangle(buyButtonX + 2, buyButtonY + 2, buyButtonWidth, buyButtonHeight,
                  Color(r: 0, g: 0, b: 0, a: 100))
  let buyBgColor = if canBuy: Color(r: 0, g: 140, b: 255, a: 255) else: Color(r: 55, g: 60, b: 70, a: 255)
  drawRectangle(buyButtonX, buyButtonY, buyButtonWidth, buyButtonHeight, buyBgColor)
  if canBuy:
    drawRectangle(buyButtonX, buyButtonY, buyButtonWidth, 2, Color(r: 255, g: 255, b: 255, a: 40))
  let buyBorderColor = if canBuy:
    let pulse = sin(game.time * 6.0) * 0.3 + 0.7
    Color(r: 0, g: 200, b: 255, a: uint8(220 * pulse))
  else:
    Color(r: 100, g: 110, b: 120, a: 255)
  drawRectangleLines(Rectangle(x: buyButtonX.float32, y: buyButtonY.float32,
                                width: buyButtonWidth.float32, height: buyButtonHeight.float32),
                    2.5, buyBorderColor)
  let buyText = if selectedPurchased: t("roguelite_already_unlocked")
                elif selectedCanBuy: t("roguelite_buy_unlock")
                else: t("roguelite_need_more_shards")
  let buyTextWidth: int32 = int32(measureText(buyText, 16))
  let buyTextX: int32 = buyButtonX + (buyButtonWidth - buyTextWidth) div 2
  drawText(buyText, buyTextX + 1, buyButtonY + 13, 16, Color(r: 0, g: 0, b: 0, a: 120))
  drawText(buyText, buyTextX, buyButtonY + 12, 16, if canBuy: White else: Color(r: 150, g: 155, b: 160, a: 255))

  let ctrlBarY = panelY + PanelH - 72
  drawRectangle(panelX + 42, ctrlBarY, PanelW - 84, 32, Color(r: 25, g: 32, b: 45, a: 230))
  drawRectangleLines(panelX + 42, ctrlBarY, PanelW - 84, 32, softColor(accent, 130))
  drawCenteredTextFit(t("roguelite_unlock_shop_controls"), panelX + 58, ctrlBarY + 10, PanelW - 116, 13, LightGray)
