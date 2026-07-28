## OS-Themed Credits / About Window
## Short, non-scrolling credits roll with the optional "support the project"
## panel pinned to the bottom of the window, under the credits.
##
## The support panel is gated entirely on `SupportEnabled` (src/support.nim):
## when it is false the window is laid out shorter, the panel is never drawn and
## the buttons cannot be clicked. The credits above it are unaffected.

import raylib
import os_window, ui_helpers, ../localization, ../render_context, ../support

type
  CreditsWindow* = ref object
    window*: OSWindow
    hoveredLink*: int   ## index into supportLinks, -1 when none

const
  CREDITS_WINDOW_WIDTH = 520
  CREDITS_BODY_HEIGHT = 350     ## window height with the credits block alone
  SUPPORT_PANEL_HEIGHT = 132    ## added on top when support is compiled in
  SUPPORT_BUTTON_HEIGHT = 34
  SUPPORT_BUTTON_GAP = 10
  SUPPORT_BUTTON_OFFSET = 68    ## button row, measured down from the panel top
  SUPPORT_BLURB_MAX_LINES = 2

  ColHeading = Color(r: 255, g: 140, b: 180, a: 255)
  ColTitle = Color(r: 235, g: 245, b: 255, a: 255)
  ColBody = Color(r: 205, g: 212, b: 222, a: 255)
  ColMuted = Color(r: 150, g: 160, b: 175, a: 255)
  ColPanelBg = Color(r: 10, g: 12, b: 18, a: 255)

# Credit lines are data, not translation keys: they are mostly proper nouns
# (names, libraries, URLs) that read the same in every language. Only the
# section headings above them go through t().
const
  CreditAuthor = "Paycei"
  CreditBuiltWith = [
    "Nim + raylib (naylib)",
    "flatty + supersnappy",
    "Every icon drawn in code, no image assets"
  ]

proc supportPanelVisible(): bool =
  ## Single source of truth for whether the support block exists at all.
  when SupportEnabled: supportLinks.len > 0
  else: false

proc creditsWindowHeight(): int =
  result = CREDITS_BODY_HEIGHT
  if supportPanelVisible():
    result += SUPPORT_PANEL_HEIGHT

proc newCreditsWindow*(screenWidth, screenHeight: int): CreditsWindow =
  let windowWidth = CREDITS_WINDOW_WIDTH
  let windowHeight = creditsWindowHeight()
  let windowX = (screenWidth - windowWidth) div 2
  let windowY = (screenHeight - windowHeight) div 2

  let osWin = newOSWindow(
    t(tkCreditsWindowTitle),
    windowX, windowY,
    windowWidth, windowHeight,
    Color(r: 255, g: 110, b: 160, a: 255),  # pink
    owtHelp,
    resizable = false
  )

  result = CreditsWindow(window: osWin, hoveredLink: -1)

proc contentMetrics(cw: CreditsWindow): tuple[x, y, w, h: int] =
  let x = cw.window.x + WINDOW_PADDING
  let y = cw.window.y + TITLE_BAR_HEIGHT + WINDOW_PADDING
  let w = cw.window.width - WINDOW_PADDING * 2
  let h = cw.window.height - TITLE_BAR_HEIGHT - WINDOW_PADDING * 2
  (x, y, w, h)

proc supportPanelTop(cw: CreditsWindow): int =
  ## Y of the separator that starts the support panel; the panel always occupies
  ## the bottom SUPPORT_PANEL_HEIGHT pixels of the content area.
  let (_, contentY, _, contentH) = contentMetrics(cw)
  contentY + contentH - SUPPORT_PANEL_HEIGHT

proc supportButtonRects(cw: CreditsWindow): seq[Rectangle] =
  ## Rects for the support buttons, laid out as one row across the bottom of the
  ## window. Empty when support is compiled out, so hit-testing and drawing both
  ## become no-ops without any extra branching at the call sites.
  result = @[]
  if not supportPanelVisible():
    return

  let (contentX, _, contentW, _) = contentMetrics(cw)
  let count = supportLinks.len
  let totalGap = SUPPORT_BUTTON_GAP * (count - 1)
  let btnW = (contentW - 36 - totalGap) div count
  let rowY = supportPanelTop(cw) + SUPPORT_BUTTON_OFFSET
  var bx = contentX + 18
  for i in 0 ..< count:
    result.add(Rectangle(x: bx.float32, y: rowY.float32,
                         width: btnW.float32, height: SUPPORT_BUTTON_HEIGHT.float32))
    bx += btnW + SUPPORT_BUTTON_GAP

proc updateCreditsWindow*(cw: CreditsWindow, dt: float32,
                          screenWidth, screenHeight: int,
                          allWindows: openArray[OSWindow]) =
  ## Update window chrome and handle support-button clicks. Closing is signalled
  ## by setting cw.window.visible = false (handled here), like the help window.
  updateOSWindow(cw.window, dt)
  if not cw.window.visible:
    return

  let shouldClose = handleOSWindowInput(cw.window, screenWidth, screenHeight, allWindows)
  if shouldClose:
    cw.window.visible = false
    return

  cw.hoveredLink = -1
  if cw.window.minimized or not cw.window.focused:
    return

  let mp = getVirtualMousePosition()
  let rects = supportButtonRects(cw)
  for i in 0 ..< rects.len:
    if checkCollisionPointRec(mp, rects[i]):
      cw.hoveredLink = i
      if isPointerPressed():
        openSupportUrl(supportLinks[i].url)
      break

proc drawSupportButton(r: Rectangle, link: SupportLink, hovered: bool) =
  let fill = if hovered:
      Color(r: min(255, link.fill.r.int + 30).uint8,
            g: min(255, link.fill.g.int + 30).uint8,
            b: min(255, link.fill.b.int + 30).uint8, a: link.fill.a)
    else: link.fill
  drawRectangle(r.x.int32, r.y.int32, r.width.int32, r.height.int32, fill)
  drawRectangleLines(r, (if hovered: 2.0 else: 1.5),
                     Color(r: 255, g: 255, b: 255, a: if hovered: 220 else: 120))
  # Shrink the caption until it fits so brand names never spill out of the pill.
  var fontSize = 15'i32
  while fontSize > 9 and measureText(link.label, fontSize) > r.width.int32 - 12:
    dec fontSize
  let tw = measureText(link.label, fontSize)
  drawText(link.label,
           r.x.int32 + (r.width.int32 - tw) div 2,
           r.y.int32 + (r.height.int32 - fontSize) div 2,
           fontSize, link.text)

proc drawCreditsWindow*(cw: CreditsWindow) =
  if not cw.window.visible:
    return

  drawWindowChrome(cw.window)
  if cw.window.minimized:
    return

  let (contentX, contentY, contentW, contentH) = contentMetrics(cw)

  drawRectangle(contentX.int32, contentY.int32, contentW.int32, contentH.int32,
                ColPanelBg)
  drawRectangleLines(Rectangle(x: contentX.float32, y: contentY.float32,
                               width: contentW.float32, height: contentH.float32),
                     1, Color(r: 255, g: 110, b: 160, a: 200))

  let baseX = contentX + 18
  let innerW = contentW - 36
  var y = contentY + 14

  # --- Title block ---
  drawText("TopHat-ShooterOS", baseX.int32, y.int32, 22, ColTitle)
  y += 26
  drawText(t(tkOSEdition), baseX.int32, y.int32, 13, ColMuted)
  y += 22
  drawLine(Vector2(x: baseX.float32, y: y.float32),
           Vector2(x: (baseX + innerW).float32, y: y.float32),
           1, Color(r: 255, g: 110, b: 160, a: 120))
  y += 14

  # --- Credits ---
  drawText(t(tkCreditsRole), baseX.int32, y.int32, 14, ColHeading)
  y += 19
  drawText(CreditAuthor, (baseX + 10).int32, y.int32, 16, ColBody)
  y += 26

  drawText(t(tkCreditsBuiltWith), baseX.int32, y.int32, 14, ColHeading)
  y += 19
  for line in CreditBuiltWith:
    drawText(line, (baseX + 10).int32, y.int32, 14, ColBody)
    y += 18
  y += 8

  drawText(t(tkCreditsThanks), baseX.int32, y.int32, 14, ColHeading)
  y += 19
  drawText(t(tkCreditsThanksBody), (baseX + 10).int32, y.int32, 14, ColBody)
  y += 24

  drawText(t(tkCreditsLicense), baseX.int32, y.int32, 12, ColMuted)
  y += 16
  drawText(ProjectRepoUrl, baseX.int32, y.int32, 12, ColMuted)

  # --- Support panel (pinned to the bottom, under the credits) ---
  let rects = supportButtonRects(cw)
  if rects.len > 0:
    let panelTop = supportPanelTop(cw).int32
    drawLine(Vector2(x: baseX.float32, y: panelTop.float32),
             Vector2(x: (baseX + innerW).float32, y: panelTop.float32),
             1, Color(r: 255, g: 110, b: 160, a: 120))
    drawText(t(tkSupportTitle), baseX.int32, panelTop + 10, 16, ColHeading)

    # Blurb: shrink until it wraps into the two lines the panel budgets for, so
    # the longer Spanish string can never push into the button row.
    let blurbSize = bestWrapFontSize(t(tkSupportBlurb), innerW.int32, 12,
                                     SUPPORT_BLURB_MAX_LINES)
    var lineY = panelTop + 34
    for line in wrapTextLines(t(tkSupportBlurb), innerW.int32, blurbSize):
      drawText(line, baseX.int32, lineY, blurbSize, ColMuted)
      lineY += blurbSize + 3

    for i in 0 ..< rects.len:
      drawSupportButton(rects[i], supportLinks[i], cw.hoveredLink == i)

    drawText(t(tkSupportNote), baseX.int32,
             rects[0].y.int32 + SUPPORT_BUTTON_HEIGHT + 6, 11, ColMuted)

  drawResizeIndicator(cw.window)
