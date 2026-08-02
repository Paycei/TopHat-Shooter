## OS-themed advancement tracker window.

import raylib, strutils, math
import os_window, ../advancement, ../render_context, ../localization, ../types, ../roguelite, ../utils, ui_helpers

type
  AdvancementsWindow* = ref object
    window*: OSWindow
    profile*: AdvancementProfile
    rogueliteProfile*: RogueliteProfile  # Persistent wallet credited by claims
    currentCategory*: AdvancementCategory
    selectedId*: string
    scrollOffset*: int  ## list scroll in pixels (rows have mixed heights)
    animTime*: float32

const
  SidebarWidth = 178
  ListWidth = 390
  HeaderHeight = 78
  # Card body is CardHeight - 8. It has to fit the title (16), a two-line
  # description (2x12 + 4 gap) and the progress bar row without them colliding,
  # which the old 72 did not -- descriptions ran under the bar.
  CardHeight = 86
  Gap = 12
  TierHeaderHeight = 24
  TierHeaderGap = 10
  LegendHeight = 130
  ScrollStep = 48

type
  AdvRowKind = enum
    arkTierHeader
    arkCard

  AdvRow = object
    kind: AdvRowKind
    tier: AdvancementTier
    defIndex: int  ## index into the category's definition seq; -1 for headers
    y: int         ## offset from the top of the scrolled content
    h: int

proc buildRows(defs: seq[AdvancementDefinition]): seq[AdvRow] =
  ## Single source of truth for list geometry. Both the update pass (hit tests,
  ## scrolling, keyboard nav) and the draw pass walk this seq, so the two can't
  ## drift apart the way parallel hand-computed layouts do.
  ## `defs` arrives already sorted by rarity, so a tier change means a new group.
  var y = 0
  for i, def in defs:
    if i == 0 or def.tier != defs[i - 1].tier:
      if i > 0:
        y += TierHeaderGap
      result.add(AdvRow(kind: arkTierHeader, tier: def.tier, defIndex: -1,
                        y: y, h: TierHeaderHeight))
      y += TierHeaderHeight + 4
    result.add(AdvRow(kind: arkCard, tier: def.tier, defIndex: i,
                      y: y, h: CardHeight - 8))
    y += CardHeight

proc contentHeight(rows: seq[AdvRow]): int =
  if rows.len == 0: 0 else: rows[^1].y + rows[^1].h

proc rowForDef(rows: seq[AdvRow], defIndex: int): AdvRow =
  for row in rows:
    if row.kind == arkCard and row.defIndex == defIndex:
      return row
  AdvRow(kind: arkCard, defIndex: -1, y: 0, h: 0)

proc tierColor*(tier: AdvancementTier): Color =
  case tier
  of atBronze:
    Color(r: 190, g: 120, b: 70, a: 255)
  of atSilver:
    Color(r: 180, g: 200, b: 220, a: 255)
  of atGold:
    Color(r: 255, g: 210, b: 70, a: 255)
  of atLegendary:
    Color(r: 120, g: 220, b: 255, a: 255)
  of atMythic:
    Color(r: 235, g: 110, b: 255, a: 255)

proc claimPulse(animTime: float32): float32 =
  ## 0..1 breathing curve used to draw attention to claimable rewards.
  sin(animTime * 4.0'f32) * 0.5'f32 + 0.5'f32

proc drawTierChip(x, y, w, h: int, tier: AdvancementTier, solid: bool) =
  ## Small rounded tier badge. `solid` fills with the tier color (dark text);
  ## otherwise it's a translucent outlined pill (tier-colored text).
  let c = tierColor(tier)
  let rect = Rectangle(x: x.float32, y: y.float32, width: w.float32, height: h.float32)
  let label = tierName(tier).toUpperAscii()
  let fs = (if h >= 18: 11'i32 else: 10'i32)
  let tw = measureText(label, fs)
  let tx = x + (w - tw) div 2
  let ty = y + (h - fs.int) div 2
  if solid:
    drawRectangleRounded(rect, 0.5'f32, 6, c)
    drawRectangleRounded(Rectangle(x: rect.x, y: rect.y, width: rect.width,
                                   height: rect.height * 0.5'f32), 0.5'f32, 6,
                         withAlpha(White, 38))
    drawText(label, tx.int32, ty.int32, fs, Color(r: 16, g: 19, b: 27, a: 255))
  else:
    drawRectangleRounded(rect, 0.5'f32, 6, withAlpha(c, 40))
    drawRectangleRoundedLines(rect, 0.5'f32, 6, 1.0'f32, c)
    drawText(label, tx.int32, ty.int32, fs, c)

proc statusColor(entry: AdvancementEntry): Color =
  if entry.claimed:
    Color(r: 90, g: 255, b: 150, a: 255)
  elif entry.unlocked:
    Color(r: 255, g: 210, b: 70, a: 255)
  else:
    Color(r: 150, g: 165, b: 185, a: 255)

proc statusLabel(entry: AdvancementEntry): string =
  if entry.claimed:
    "Claimed"
  elif entry.unlocked:
    "Unlocked"
  else:
    "In Progress"

proc drawWrappedText(text: string, x, y, maxWidth: int, fontSize: int32,
                     color: Color, maxLines: int = 6, lineGap: int = 6,
                     minSize: int32 = 9): int =
  var lineY = y
  let wrappedFontSize = bestWrapFontSize(text, maxWidth.int32, fontSize, maxLines, minSize)
  let lines = wrapTextLines(text, maxWidth.int32, wrappedFontSize)
  let linesToDraw = min(lines.len, maxLines)
  for idx in 0..<linesToDraw:
    drawText(lines[idx], x.int32, lineY.int32, wrappedFontSize, color)
    lineY += wrappedFontSize.int + lineGap
  result = lineY

proc drawProgressBar(x, y, width, height: int, ratio: float32, color: Color,
                     complete: bool = false, pulse: float32 = 0.0'f32) =
  let clamped = clamp(ratio, 0.0'f32, 1.0'f32)
  drawRectangle(x.int32, y.int32, width.int32, height.int32,
                Color(r: 12, g: 16, b: 24, a: 255))
  let fillWidth = int(width.float32 * clamped)
  if fillWidth > 0:
    drawRectangleGradientH(x.int32, y.int32, fillWidth.int32, height.int32,
                           Color(r: uint8(max(0, color.r.int - 45)),
                                 g: uint8(max(0, color.g.int - 45)),
                                 b: uint8(max(0, color.b.int - 45)),
                                 a: 220),
                           color)
    # Glossy highlight across the top third of the fill.
    if height >= 6:
      drawRectangle(x.int32, y.int32, fillWidth.int32, max(1, height div 3).int32,
                    withAlpha(White, 42))
  # Completed bars get a softly pulsing accent border; everyone else a flat one.
  let border =
    if complete: withAlpha(brighten(color, 30, color.a.int), 150 + int(90.0'f32 * pulse))
    else: Color(r: 70, g: 82, b: 102, a: 255)
  drawRectangleLines(Rectangle(x: x.float32, y: y.float32,
                               width: width.float32, height: height.float32),
                     1, border)

proc drawPanel(x, y, width, height: int, title: string = "") =
  drawRectangle(x.int32, y.int32, width.int32, height.int32,
                Color(r: 19, g: 23, b: 34, a: 238))
  drawRectangleLines(Rectangle(x: x.float32, y: y.float32,
                               width: width.float32, height: height.float32),
                     1, Color(r: 68, g: 82, b: 106, a: 255))
  if title.len > 0:
    drawRectangle(x.int32, y.int32, width.int32, 24,
                  Color(r: 28, g: 34, b: 48, a: 255))
    drawText(title, (x + 8).int32, (y + 5).int32, 13, Color(r: 120, g: 220, b: 255, a: 255))

proc drawButton(rect: Rectangle, label: string, enabled: bool, hovered: bool,
                pulse: float32 = 0.0'f32) =
  let bg =
    if not enabled:
      Color(r: 38, g: 42, b: 50, a: 255)
    elif hovered:
      Color(r: 0, g: 105, b: 130, a: 255)
    else:
      Color(r: 0, g: 70, b: 95, a: 255)
  let border =
    if not enabled: Color(r: 82, g: 90, b: 105, a: 255)
    elif pulse > 0.0'f32: Color(r: uint8(120 + int(135.0'f32 * pulse)), g: 210, b: 255, a: 255)
    else: Color(r: 0, g: 210, b: 255, a: 255)
  let text =
    if enabled: White
    else: Color(r: 140, g: 145, b: 155, a: 255)

  drawRectangle(rect.x.int32, rect.y.int32, rect.width.int32, rect.height.int32, bg)
  # Subtle vertical sheen so enabled buttons read as glassy rather than flat.
  if enabled:
    drawRectangleGradientV(rect.x.int32, rect.y.int32, rect.width.int32,
                           max(1, rect.height.int32 div 2),
                           withAlpha(White, 30), withAlpha(White, 0))
  drawRectangleLines(rect, (if enabled and pulse > 0.0'f32: 2 else: 1), border)
  let tw = measureText(label, 14)
  drawText(label, (rect.x.int32 + (rect.width.int32 - tw) div 2),
           (rect.y.int32 + 8), 14, text)

proc hoverEnabled(advWin: AdvancementsWindow, mousePos: Vector2): bool =
  not advWin.isNil and not advWin.window.isNil and advWin.window.focused and
    isPointInWindow(advWin.window, mousePos.x, mousePos.y)

proc payoutText*(def: AdvancementDefinition): string =
  ## Human-readable claim payout, e.g. "+90 Shards" or "+200 Shards, +1 Cores".
  result = "+" & $def.rewardShards & " " & t("roguelite_shards_short")
  if def.rewardCores > 0:
    result &= ", +" & $def.rewardCores & " " & t("roguelite_cores_short")

proc saveClaimedProfiles(advWin: AdvancementsWindow) =
  discard saveAdvancements(advWin.profile)
  if not advWin.rogueliteProfile.isNil:
    discard saveRogueliteProfile(advWin.rogueliteProfile)

proc newAdvancementsWindow*(screenWidth, screenHeight: int,
                            profile: AdvancementProfile,
                            rogueliteProfile: RogueliteProfile): AdvancementsWindow =
  let windowWidth = 940
  let windowHeight = 660
  let windowX = (screenWidth - windowWidth) div 2
  let windowY = (screenHeight - windowHeight) div 2

  let osWin = newOSWindow(
    "Advncmnts.exe",
    windowX, windowY,
    windowWidth, windowHeight,
    Color(r: 90, g: 220, b: 255, a: 255),
    owtStatistics,
    resizable = false
  )

  result = AdvancementsWindow(
    window: osWin,
    profile: profile,
    rogueliteProfile: rogueliteProfile,
    currentCategory: acCombat,
    selectedId: "",
    scrollOffset: 0,
    animTime: 0.0
  )

proc ensureSelection(advWin: AdvancementsWindow) =
  let defs = definitionsForCategory(advWin.currentCategory)
  if defs.len == 0:
    advWin.selectedId = ""
    return

  var found = false
  for def in defs:
    if def.id == advWin.selectedId:
      found = true
      break

  if not found:
    advWin.selectedId = defs[0].id
    advWin.scrollOffset = 0

proc updateAdvancementsWindow*(advWin: AdvancementsWindow, dt: float32,
                               screenWidth, screenHeight: int,
                               allWindows: openArray[OSWindow]): bool =
  if advWin.isNil or advWin.window.isNil:
    return false

  updateOSWindow(advWin.window, dt)
  advWin.animTime += dt

  if not advWin.window.visible:
    return false

  let shouldClose = handleOSWindowInput(advWin.window, screenWidth, screenHeight, allWindows)
  if shouldClose:
    advWin.window.visible = false
    return true

  if advWin.window.minimized:
    return false

  advWin.ensureSelection()

  let mousePos = getVirtualMousePosition()
  let topmost = isWindowTopmostAtPoint(advWin.window, mousePos.x, mousePos.y, allWindows)
  let contentX = advWin.window.x + WINDOW_PADDING
  let contentY = advWin.window.y + TITLE_BAR_HEIGHT + WINDOW_PADDING
  let contentW = advWin.window.width - WINDOW_PADDING * 2
  let bodyY = contentY + HeaderHeight + Gap
  let bodyH = advWin.window.height - TITLE_BAR_HEIGHT - WINDOW_PADDING * 2 - HeaderHeight - Gap
  let listX = contentX + SidebarWidth + Gap
  let listY = bodyY
  # Mirror draw function: derive cardStartY via the same wrapped-description logic
  let descLines = wrapTextLines(categoryDescription(advWin.currentCategory), (ListWidth - 18).int32, 12)
  let descLineCount = min(descLines.len, 2)
  let listDescEnd = (listY + 31) + descLineCount * (12 + 6)
  let cardStartY = max(listY + 52, listDescEnd + 10)
  let listH = bodyH - (cardStartY - listY) - 8
  let defs = definitionsForCategory(advWin.currentCategory)
  let rows = buildRows(defs)
  let maxScroll = max(0, rows.contentHeight() - listH)
  advWin.scrollOffset = clamp(advWin.scrollOffset, 0, maxScroll)

  proc scrollToDef(index: int) =
    ## Keep the keyboard selection inside the viewport, pulling the tier header
    ## in with the first card of a group so the row never looks orphaned.
    let row = rows.rowForDef(index)
    if row.defIndex < 0:
      return
    let top = (if row.y >= TierHeaderHeight + 4 and index > 0 and
                  defs[index].tier != defs[index - 1].tier:
                 row.y - TierHeaderHeight - 4
               else: row.y)
    if top < advWin.scrollOffset:
      advWin.scrollOffset = top
    elif row.y + row.h > advWin.scrollOffset + listH:
      advWin.scrollOffset = row.y + row.h - listH
    advWin.scrollOffset = clamp(advWin.scrollOffset, 0, maxScroll)

  if topmost:
    if isKeyPressed(KeyboardKey.One): advWin.currentCategory = acCombat
    if isKeyPressed(KeyboardKey.Two): advWin.currentCategory = acSurvival
    if isKeyPressed(KeyboardKey.Three): advWin.currentCategory = acResources
    if isKeyPressed(KeyboardKey.Four): advWin.currentCategory = acMastery
    if isKeyPressed(KeyboardKey.Five): advWin.currentCategory = acRoguelite

    if defs.len > 0 and (isKeyPressed(KeyboardKey.Down) or isKeyPressed(KeyboardKey.Up)):
      var selectedIndex = 0
      for i, def in defs:
        if def.id == advWin.selectedId:
          selectedIndex = i
          break
      selectedIndex =
        if isKeyPressed(KeyboardKey.Down): min(defs.high, selectedIndex + 1)
        else: max(0, selectedIndex - 1)
      advWin.selectedId = defs[selectedIndex].id
      scrollToDef(selectedIndex)

    let listRect = Rectangle(x: (listX + 8).float32, y: cardStartY.float32,
                             width: (ListWidth - 16).float32, height: listH.float32)
    if checkCollisionPointRec(mousePos, listRect):
      let wheel = getPointerWheelMove()
      if wheel != 0:
        advWin.scrollOffset = clamp(advWin.scrollOffset - int(wheel * ScrollStep.float32),
                                    0, maxScroll)

  if advWin.window.handledClickThisFrame and topmost:
    let sidebarX = contentX
    var catY = bodyY + 32
    for category in allAdvancementCategories():
      let rect = Rectangle(x: sidebarX.float32, y: catY.float32,
                           width: SidebarWidth.float32, height: 38.0)
      if checkCollisionPointRec(mousePos, rect):
        advWin.currentCategory = category
        advWin.selectedId = ""
        advWin.scrollOffset = 0
        advWin.ensureSelection()
        break
      catY += 44

    for row in rows:
      if row.kind != arkCard:
        continue
      let rowY = cardStartY + row.y - advWin.scrollOffset
      # Clipped-away rows must not be clickable, or the list would swallow
      # clicks meant for the panels above and below it.
      if rowY + row.h <= cardStartY or rowY >= cardStartY + listH:
        continue
      let rect = Rectangle(x: (listX + 8).float32, y: rowY.float32,
                           width: (ListWidth - 16).float32, height: row.h.float32)
      if checkCollisionPointRec(mousePos, rect):
        advWin.selectedId = defs[row.defIndex].id
        break

    let detailX = listX + ListWidth + Gap
    let detailW = contentW - SidebarWidth - ListWidth - Gap * 2
    let claimRect = Rectangle(x: (detailX + 14).float32,
                              y: (bodyY + bodyH - 52).float32,
                              width: (detailW - 28).float32,
                              height: 34.0)
    let claimAllRect = Rectangle(x: (contentX + contentW - 180).float32,
                                 y: (contentY + 22).float32,
                                 width: 160.0,
                                 height: 34.0)
    if checkCollisionPointRec(mousePos, claimAllRect):
      let granted = claimAllAdvancements(advWin.profile, advWin.rogueliteProfile)
      if granted.count > 0:
        advWin.saveClaimedProfiles()
    elif checkCollisionPointRec(mousePos, claimRect):
      let entry = advWin.profile.getAdvancementEntry(advWin.selectedId)
      if entry.unlocked and not entry.claimed:
        let granted = claimAdvancement(advWin.profile, advWin.selectedId,
                                       advWin.rogueliteProfile)
        if granted.claimed:
          advWin.saveClaimedProfiles()

  false

proc drawTierDiamond(cx, cy: int, size: float32, color: Color, filled: bool) =
  ## Small rotated square used as the rarity glyph (a poly with 4 sides is a
  ## diamond when rotated 45 degrees).
  let center = Vector2(x: cx.float32, y: cy.float32)
  if filled:
    drawPoly(center, 4, size, 45.0'f32, color)
  drawPolyLines(center, 4, size, 45.0'f32, 1.5'f32, color)

proc drawTierGroupHeader(x, y, w, h: int, tier: AdvancementTier,
                         totals: tuple[unlocked, total, unclaimed: int],
                         pulse: float32) =
  ## Section divider that opens each rarity group in the list.
  let c = tierColor(tier)
  drawRectangleGradientH(x.int32, y.int32, w.int32, h.int32,
                         withAlpha(c, 40), withAlpha(c, 0))
  drawRectangle(x.int32, y.int32, 3, h.int32, c)
  drawTierDiamond(x + 16, y + h div 2, 4.5'f32, c, totals.unlocked >= totals.total)
  let label = tierName(tier).toUpperAscii()
  drawText(label, (x + 26).int32, (y + (h - 12) div 2).int32, 12, c)
  let count = $totals.unlocked & " / " & $totals.total
  let cw = measureText(count, 11)
  drawText(count, (x + w - 10 - cw).int32, (y + (h - 11) div 2).int32, 11,
           if totals.unclaimed > 0: Color(r: 255, g: 210, b: 70, a: 255)
           elif totals.unlocked >= totals.total: c
           else: Color(r: 140, g: 155, b: 175, a: 255))
  if totals.unclaimed > 0:
    drawCircle(Vector2(x: (x + w - 18 - cw).float32, y: (y + h div 2).float32),
               3.0'f32 + pulse * 1.5'f32, Color(r: 255, g: 210, b: 70, a: 255))
  # Hairline under the label ties the group to the cards below it.
  drawRectangle(x.int32, (y + h - 1).int32, w.int32, 1, withAlpha(c, 70))

proc drawAdvancementCard(advWin: AdvancementsWindow, def: AdvancementDefinition,
                         x, y, width, height: int, selected, hovered: bool) =
  let entry = advWin.profile.getAdvancementEntry(def.id)
  let accent = tierColor(def.tier)
  let claimable = entry.unlocked and not entry.claimed
  let pulse = claimPulse(advWin.animTime)
  let bg = if selected:
    Color(r: 28, g: 36, b: 50, a: 255)
  elif hovered:
    Color(r: 26, g: 33, b: 47, a: 255)
  else:
    Color(r: 22, g: 26, b: 37, a: 255)
  let border = if claimable: withAlpha(brighten(accent, 20, accent.a.int), 170 + int(85.0'f32 * pulse))
               elif selected or hovered: accent
               else: Color(r: 62, g: 74, b: 96, a: 255)

  if hovered:
    drawRectangle((x + 3).int32, (y + 3).int32, width.int32, height.int32,
                  Color(r: 0, g: 0, b: 0, a: 85))
  drawRectangle(x.int32, y.int32, width.int32, height.int32, bg)
  # Claimable cards get a soft pulsing halo to pull the eye toward the reward.
  if claimable:
    drawRectangleLines(Rectangle(x: (x - 1).float32, y: (y - 1).float32,
                                 width: (width + 2).float32, height: (height + 2).float32),
                       2, withAlpha(accent, 35 + int(70.0'f32 * pulse)))
  # Untouched entries keep the rarity hue but at low alpha, so a group's
  # completed cards pop out of the stripe column at a glance.
  let untouched = not entry.unlocked and entry.progress <= 0.0'f32
  drawRectangle(x.int32, y.int32, 4, height.int32,
                if untouched: withAlpha(accent, 90) else: accent)
  drawRectangleLines(Rectangle(x: x.float32, y: y.float32,
                               width: width.float32, height: height.float32),
                     if claimable or selected or hovered: 2 else: 1, border)

  discard drawTextFit(def.name, (x + 12).int32, (y + 8).int32, (width - 136).int32, 16,
                      if hovered or selected: White else: Color(r: 220, g: 228, b: 240, a: 255), 11)
  drawTierChip(x + width - 72, y + 8, 64, 16, def.tier, false)
  # Payout preview sits between the title and the tier chip so the value of a
  # rarity is readable without opening the detail panel.
  let payout = "+" & $def.rewardShards
  let payoutW = measureText(payout, 11)
  drawText(payout, (x + width - 78 - payoutW).int32, (y + 10).int32, 11,
           if entry.claimed: Color(r: 90, g: 160, b: 120, a: 255)
           elif claimable: Color(r: 255, g: 210, b: 70, a: 255)
           else: Color(r: 132, g: 146, b: 166, a: 255))
  discard drawWrappedText(def.description, x + 12, y + 30, width - 26, 12,
                          if hovered: Color(r: 185, g: 198, b: 215, a: 255)
                          else: Color(r: 165, g: 178, b: 195, a: 255), 2, 4, 10)

  let barX = x + 12
  let barY = y + height - 16
  let barW = width - 88
  let ratio = advancementPercent(entry, def)
  drawProgressBar(barX, barY, barW, 8, ratio, accent, entry.unlocked, pulse)
  if entry.claimed:
    # Green check instead of a bare "100%" to mark the reward as collected.
    let cx = x + width - 66
    let cy = barY - 1
    let check = Color(r: 90, g: 255, b: 150, a: 255)
    # Two strokes drawn twice (1px offset) to read as a bold 2px checkmark.
    for off in 0..1:
      drawLine((cx - 4).int32, (cy + off).int32, (cx - 1).int32, (cy + 4 + off).int32, check)
      drawLine((cx - 1).int32, (cy + 4 + off).int32, (cx + 4).int32, (cy - 4 + off).int32, check)
    drawText(t(tkAdvDone), (x + width - 52).int32, (barY - 3).int32, 11, check)
  else:
    let pct = $int(ratio * 100.0'f32) & "%"
    drawText(pct, (x + width - 58).int32, (barY - 3).int32, 12, statusColor(entry))

proc drawAdvancementsWindow*(advWin: AdvancementsWindow) =
  if advWin.isNil or advWin.window.isNil or not advWin.window.visible:
    return

  drawWindowChrome(advWin.window)
  if advWin.window.minimized:
    return

  advWin.ensureSelection()

  let contentX = advWin.window.x + WINDOW_PADDING
  let contentY = advWin.window.y + TITLE_BAR_HEIGHT + WINDOW_PADDING
  let contentW = advWin.window.width - WINDOW_PADDING * 2
  let contentH = advWin.window.height - TITLE_BAR_HEIGHT - WINDOW_PADDING * 2
  let bodyY = contentY + HeaderHeight + Gap
  let bodyH = contentH - HeaderHeight - Gap

  drawPanel(contentX, contentY, contentW, HeaderHeight, "")
  drawText(t(tkAdvControlTitle), (contentX + 14).int32, (contentY + 10).int32, 20,
           Color(r: 120, g: 220, b: 255, a: 255))

  let totalDefs = getAdvancementDefinitions().len
  let unlocked = advWin.profile.totalUnlocked()
  let claimed = advWin.profile.totalClaimed()
  let walletShards = if advWin.rogueliteProfile.isNil: 0
                     else: advWin.rogueliteProfile.dataShards
  let pending = advWin.profile.unclaimedShards()

  let statX = contentX + 465
  discard drawWrappedText(t(tkAdvSyncDesc),
                          contentX + 14, contentY + 36, statX - contentX - 34, 13,
                          Color(r: 170, g: 185, b: 205, a: 255), 2, 4, 11)
  drawText(t(tkAdvUnlockedCount), statX.int32, (contentY + 12).int32, 12, LightGray)
  drawText($unlocked & " / " & $totalDefs, statX.int32, (contentY + 30).int32, 20, White)
  drawText(t(tkAdvClaimedCount), (statX + 112).int32, (contentY + 12).int32, 12, LightGray)
  drawText($claimed, (statX + 112).int32, (contentY + 30).int32, 20, Color(r: 90, g: 255, b: 150, a: 255))
  drawText(t(tkAdvShardBalance), (statX + 205).int32, (contentY + 12).int32, 12, LightGray)
  drawText($walletShards, (statX + 205).int32, (contentY + 30).int32, 20, Color(r: 255, g: 210, b: 70, a: 255))

  let claimAllRect = Rectangle(x: (contentX + contentW - 180).float32,
                               y: (contentY + 22).float32,
                               width: 160.0,
                               height: 34.0)
  let mousePos = getVirtualMousePosition()
  let canHover = advWin.hoverEnabled(mousePos)
  let pulse = claimPulse(advWin.animTime)
  drawButton(claimAllRect,
             if pending > 0: t(tkAdvClaimAll) & $pending else: t(tkAdvAllClaimed),
             pending > 0,
             canHover and pending > 0 and checkCollisionPointRec(mousePos, claimAllRect),
             if pending > 0: pulse else: 0.0'f32)

  # Master completion bar along the header's lower edge: how much of the whole
  # advancement set has been claimed. Fills gold and glows once 100% complete.
  let overall = if totalDefs > 0: claimed.float32 / totalDefs.float32 else: 0.0'f32
  let allDone = totalDefs > 0 and claimed >= totalDefs
  drawProgressBar(contentX + 14, contentY + HeaderHeight - 9, contentW - 28, 4,
                  overall, Color(r: 255, g: 210, b: 70, a: 255), allDone, pulse)

  drawPanel(contentX, bodyY, SidebarWidth, bodyH, t(tkAdvCategories))
  var catY = bodyY + 32
  for category in allAdvancementCategories():
    let totals = advWin.profile.categoryTotals(category)
    let active = category == advWin.currentCategory
    let catRect = Rectangle(x: contentX.float32, y: catY.float32,
                            width: SidebarWidth.float32, height: 38.0)
    let hovered = canHover and checkCollisionPointRec(mousePos, catRect)
    let bg = if active: Color(r: 0, g: 74, b: 100, a: 255)
             elif hovered: Color(r: 34, g: 45, b: 60, a: 255)
             else: Color(r: 24, g: 29, b: 40, a: 255)
    let border = if active: Color(r: 0, g: 210, b: 255, a: 255)
                 elif hovered: Color(r: 120, g: 220, b: 255, a: 255)
                 else: Color(r: 62, g: 74, b: 96, a: 255)
    drawRectangle(contentX.int32, catY.int32, SidebarWidth.int32, 38, bg)
    drawRectangleLines(catRect, if active or hovered: 2 else: 1, border)
    drawText(categoryName(category), (contentX + 9).int32, (catY + 7).int32, 14,
             if active or hovered: White else: Color(r: 210, g: 220, b: 235, a: 255))
    let countText = $totals.unlocked & " / " & $totals.total
    drawText(countText, (contentX + SidebarWidth - 58).int32, (catY + 8).int32, 12,
             if totals.unclaimed > 0: Color(r: 255, g: 210, b: 70, a: 255) else: LightGray)
    if totals.unclaimed > 0:
      let dotPos = Vector2(x: (contentX + SidebarWidth - 15).float32, y: (catY + 26).float32)
      let gold = Color(r: 255, g: 210, b: 70, a: 255)
      drawCircle(dotPos, 4.0'f32 + pulse * 2.5'f32, withAlpha(gold, 60))
      drawCircle(dotPos, 4.0'f32, gold)
    catY += 44

  # Rarity legend pinned to the bottom of the sidebar: the same ordering the
  # list is sorted by, doubling as a global per-tier completion readout.
  let legendY = bodyY + bodyH - LegendHeight - 8
  drawRectangle((contentX + 9).int32, (legendY - 10).int32, (SidebarWidth - 18).int32, 1,
                Color(r: 62, g: 74, b: 96, a: 255))
  drawText(t(tkAdvTierLegend).toUpperAscii(), (contentX + 10).int32, legendY.int32, 11,
           Color(r: 120, g: 220, b: 255, a: 255))
  var tierY = legendY + 18
  for tier in allAdvancementTiers():
    let totals = advWin.profile.tierTotals(tier)
    let complete = totals.total > 0 and totals.unlocked >= totals.total
    let c = tierColor(tier)
    drawTierDiamond(contentX + 15, tierY + 5, 4.0'f32, c, complete)
    drawText(tierName(tier), (contentX + 25).int32, tierY.int32, 11, c)
    let count = $totals.unlocked & "/" & $totals.total
    let cw = measureText(count, 11)
    drawText(count, (contentX + SidebarWidth - 10 - cw).int32, tierY.int32, 11,
             if totals.unclaimed > 0: Color(r: 255, g: 210, b: 70, a: 255)
             elif complete: c
             else: Color(r: 150, g: 165, b: 185, a: 255))
    let ratio = if totals.total > 0: totals.unlocked.float32 / totals.total.float32
                else: 0.0'f32
    drawProgressBar(contentX + 10, tierY + 14, SidebarWidth - 20, 3, ratio, c,
                    complete, pulse)
    tierY += 22

  let listX = contentX + SidebarWidth + Gap
  let listY = bodyY
  drawPanel(listX, listY, ListWidth, bodyH, categoryName(advWin.currentCategory))
  let listDescEnd = drawWrappedText(categoryDescription(advWin.currentCategory),
                                    listX + 9, listY + 31, ListWidth - 18, 12,
                                    Color(r: 160, g: 175, b: 195, a: 255), 2)

  let defs = definitionsForCategory(advWin.currentCategory)
  let cardStartY = max(listY + 52, listDescEnd + 10)
  let listH = bodyH - (cardStartY - listY) - 8
  let rows = buildRows(defs)
  let totalH = rows.contentHeight()
  let maxScroll = max(0, totalH - listH)
  advWin.scrollOffset = clamp(advWin.scrollOffset, 0, maxScroll)

  # Clip to the viewport so partially scrolled rows are cut cleanly at the
  # panel edges instead of spilling over the header and the window border.
  beginVirtualScissorMode((listX + 4).int32, cardStartY.int32,
                          (ListWidth - 8).int32, listH.int32)
  for row in rows:
    let rowY = cardStartY + row.y - advWin.scrollOffset
    if rowY + row.h <= cardStartY or rowY >= cardStartY + listH:
      continue
    case row.kind
    of arkTierHeader:
      drawTierGroupHeader(listX + 8, rowY, ListWidth - 16, row.h, row.tier,
                          advWin.profile.categoryTierTotals(advWin.currentCategory, row.tier),
                          pulse)
    of arkCard:
      let def = defs[row.defIndex]
      let cardRect = Rectangle(x: (listX + 8).float32, y: rowY.float32,
                               width: (ListWidth - 16).float32, height: row.h.float32)
      let hovered = canHover and checkCollisionPointRec(mousePos, cardRect)
      drawAdvancementCard(advWin, def, listX + 8, rowY, ListWidth - 16, row.h,
                          def.id == advWin.selectedId, hovered)
  endScissorMode()

  if totalH > listH:
    let trackX = listX + ListWidth - 8
    let trackY = cardStartY
    let trackH = listH
    # Thumb length tracks the visible fraction, so a long category reads as
    # long -- the old fixed 34px thumb hid how much was below the fold.
    let thumbH = max(26, int(trackH.float32 * listH.float32 / totalH.float32))
    let scrollRatio = advWin.scrollOffset.float32 / maxScroll.float32
    drawRectangle(trackX.int32, trackY.int32, 3, trackH.int32,
                  Color(r: 45, g: 52, b: 68, a: 255))
    drawRectangle(trackX.int32,
                  (trackY + int(scrollRatio * (trackH - thumbH).float32)).int32,
                  3, thumbH.int32, Color(r: 0, g: 210, b: 255, a: 255))

  let detailX = listX + ListWidth + Gap
  let detailW = contentW - SidebarWidth - ListWidth - Gap * 2
  drawPanel(detailX, bodyY, detailW, bodyH, t(tkAdvDetail))

  let selectedDef = getAdvancementDefinition(advWin.selectedId)
  if selectedDef.id.len > 0:
    let entry = advWin.profile.getAdvancementEntry(selectedDef.id)
    let accent = tierColor(selectedDef.tier)
    drawTierChip(detailX + 14, bodyY + 32, 78, 19, selectedDef.tier, true)
    discard drawTextFit(selectedDef.name, (detailX + 14).int32, (bodyY + 55).int32, (detailW - 28).int32, 22, White, 12)
    let descEnd = drawWrappedText(selectedDef.description, detailX + 14, bodyY + 90,
                                  detailW - 28, 14,
                                  Color(r: 180, g: 192, b: 210, a: 255), 4)

    let progressY = descEnd + 20
    drawText(t(tkAdvProgress), (detailX + 14).int32, progressY.int32, 13, LightGray)
    drawText(formatAdvancementProgress(entry, selectedDef),
             (detailX + detailW - 118).int32, progressY.int32, 13, statusColor(entry))
    drawProgressBar(detailX + 14, progressY + 22, detailW - 28, 14,
                    advancementPercent(entry, selectedDef), accent, entry.unlocked, pulse)

    var infoY = progressY + 54
    drawText(t(tkAdvStatus), (detailX + 14).int32, infoY.int32, 13, LightGray)
    drawText(statusLabel(entry), (detailX + 95).int32, infoY.int32, 13, statusColor(entry))
    infoY += 26
    drawText(t(tkAdvReward), (detailX + 14).int32, infoY.int32, 13, LightGray)
    drawText(payoutText(selectedDef), (detailX + 95).int32, infoY.int32, 13,
             if entry.claimed: Color(r: 90, g: 255, b: 150, a: 255)
             elif entry.unlocked: Color(r: 255, g: 210, b: 70, a: 255)
             else: Color(r: 190, g: 220, b: 235, a: 255))
    infoY += 26
    drawText(t(tkAdvCategoryLabel), (detailX + 14).int32, infoY.int32, 13, LightGray)
    drawText(categoryName(selectedDef.category), (detailX + 95).int32, infoY.int32, 13,
             Color(r: 210, g: 220, b: 235, a: 255))

    # Rarity context: where this entry's tier stands across the whole set, so
    # the payout above reads as "this is what this rarity is worth".
    let tierProgress = advWin.profile.tierTotals(selectedDef.tier)
    infoY += 26
    drawText(t(tkAdvTierLegend), (detailX + 14).int32, infoY.int32, 13, LightGray)
    drawText(tierName(selectedDef.tier) & "  " & $tierProgress.unlocked & " / " &
             $tierProgress.total, (detailX + 95).int32, infoY.int32, 13, accent)
    let tierRatio = if tierProgress.total > 0:
                      tierProgress.unlocked.float32 / tierProgress.total.float32
                    else: 0.0'f32
    drawProgressBar(detailX + 14, infoY + 22, detailW - 28, 6, tierRatio, accent,
                    tierProgress.total > 0 and tierProgress.unlocked >= tierProgress.total,
                    pulse)

    if entry.unlockedAt.len > 0:
      drawText(t(tkAdvUnlockedAt), (detailX + 14).int32, (bodyY + bodyH - 88).int32, 12, LightGray)
      discard drawTextFit(entry.unlockedAt, (detailX + 95).int32, (bodyY + bodyH - 88).int32, (detailW - 105).int32, 12,
                          Color(r: 160, g: 175, b: 195, a: 255))

    let claimRect = Rectangle(x: (detailX + 14).float32,
                              y: (bodyY + bodyH - 52).float32,
                              width: (detailW - 28).float32,
                              height: 34.0)
    drawButton(claimRect,
               if entry.claimed: t(tkAdvRewardClaimed)
               elif entry.unlocked: t(tkAdvClaimReward)
               else: t(tkAdvLockedBtn),
               entry.unlocked and not entry.claimed,
               canHover and entry.unlocked and not entry.claimed and checkCollisionPointRec(mousePos, claimRect),
               if entry.unlocked and not entry.claimed: pulse else: 0.0'f32)

  drawResizeIndicator(advWin.window)
