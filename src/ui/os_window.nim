## OS Window Framework
## Base system for all OS-style windows (Settings, Stats, Help)

import raylib, math
import ../modding/mod_patch_core
import ../draw_prims
import ../render_context
import ui_theme, ../utils

type
  OSWindow* = ref object
    x*, y*: int
    width*, height*: int
    title*: string
    iconColor*: Color
    visible*: bool
    minimized*: bool
    focused*: bool
    dragging*: bool
    dragOffsetX*, dragOffsetY*: int
    time*: float32
    zOrder*: int  # Z-order for window stacking (higher = on top)
    handledClickThisFrame*: bool
      ## A click COMMITTED on this window this frame: buttons, toggles, tabs.
      ## On touch that is the tap's release, and never a drag's.
    handledPressThisFrame*: bool
      ## A press LANDED on this window this frame: what starts a drag (sliders,
      ## thumbs). Same frame as the click on desktop; the finger-down on touch,
      ## where committing on it would fire a toggle twice (down and up) and
      ## activate whatever a scroll started on.

    # Resizing
    resizable*: bool  # Whether this window can be resized
    resizing*: bool
    resizeEdge*: int  # 0=none, 1=right, 2=bottom, 3=corner

    savedWidth*, savedHeight*: int  # For minimize/restore

    # The UI scale this window is currently drawn and hit-tested at. Each window
    # gets its own (window_manager.windowUIScale caps the player's setting per
    # window), so x/y/width/height are in *this window's* logical pixels and are
    # only comparable with another window's after a trip through both scales.
    # The window manager refreshes it every frame; 1.0 until it does.
    uiScale*: float32

const
  TITLE_BAR_HEIGHT* = 30
  WINDOW_BORDER* = 2
  WINDOW_PADDING* = 10
  MIN_WINDOW_WIDTH* = 400
  MIN_WINDOW_HEIGHT* = 300

# Chrome buttons (close / minimize / restore).
#
# TITLE_BAR_HEIGHT stays 30 on every platform: 62 call sites across 15 modules
# derive their content offsets from it, and growing it would push every window's
# content down and overflow the tall ones (stats is 700 of 768). So mobile keeps
# the same bar and instead spreads the buttons out and gives each one a hit area
# much larger than its glyph -- which is where the touch problem actually was.
const
  CHROME_BTN_SIZE* = when defined(mobile): 24 else: 20
    ## Drawn size of the button square.
  CHROME_BTN_HIT_W* = when defined(mobile): 46 else: 20
    ## Hit width. Horizontal is the axis a thumb misses on, and unlike height it
    ## isn't capped by the title bar.
  CHROME_BTN_HIT_H* = when defined(mobile): TITLE_BAR_HEIGHT else: 20
  CLOSE_BTN_INSET* = when defined(mobile): 34 else: 25
    ## Distance from the window's right edge to the button's left edge.
  MIN_BTN_INSET* = when defined(mobile): 84 else: 50
    ## Far enough from close that the two hit areas cannot overlap.

proc chromeBtnHitRect(winX, winY, inset: int): Rectangle =
  ## Hit area centred on the drawn button, so it can be wider than the glyph.
  let pad = (CHROME_BTN_HIT_W - CHROME_BTN_SIZE) div 2
  Rectangle(x: (winX - inset - pad).float32, y: winY.float32,
            width: CHROME_BTN_HIT_W.float32, height: CHROME_BTN_HIT_H.float32)

proc uiScaleOfWindow*(window: OSWindow): float32 {.moddable.} =
  ## `window.uiScale`, guarded against a window the manager has not touched yet
  ## (and against a 0 that would make the conversions below divide by zero).
  if window.isNil or window.uiScale <= 0.0'f32: 1.0'f32
  else: window.uiScale

proc newOSWindow*(title: string, x, y, width, height: int,
                 iconColor: Color, resizable: bool = true): OSWindow {.moddable.} =
  result = OSWindow(
    x: x,
    y: y,
    width: width,
    height: height,
    title: title,
    iconColor: iconColor,
    visible: false,
    minimized: false,
    focused: true,
    dragging: false,
    resizable: resizable,
    resizing: false,
    handledClickThisFrame: false,
    handledPressThisFrame: false,
    time: 0,
    zOrder: 0,
    savedWidth: width,
    savedHeight: height,
    uiScale: 1.0'f32
  )

proc startMinimizeAnimation(window: OSWindow) {.moddable.} =
  ## Instantly minimize - no animation
  window.minimized = true
  window.savedWidth = window.width
  window.savedHeight = window.height

proc startRestoreAnimation(window: OSWindow) {.moddable.} =
  ## Instantly restore - no animation
  window.minimized = false

proc bringWindowToFront(window: OSWindow, allWindows: openArray[OSWindow]) {.moddable.} =
  ## Bring this window to the front of all other windows
  ## Updates z-order so this window is drawn on top
  if window.isNil or not window.visible:
    return

  # Find the highest z-order among all windows
  var maxZOrder = 0
  for w in allWindows:
    if not w.isNil and w.visible and w.zOrder > maxZOrder:
      maxZOrder = w.zOrder

  # Always bring this window to front by setting it higher than the max
  # This ensures even newly opened windows (with zOrder=0) come to front
  if window.zOrder <= maxZOrder:
    window.zOrder = maxZOrder + 1

  # Set focus
  window.focused = true

  # Unfocus all other windows
  for w in allWindows:
    if not w.isNil and w != window:
      w.focused = false

proc hasKeyboard*(window: OSWindow): bool {.moddable.} =
  ## Keystrokes go to the focused window, while it is open and not minimized.
  not window.isNil and window.visible and not window.minimized and window.focused

proc updateOSWindow*(window: OSWindow, dt: float32) {.moddable.} =
  window.time += dt

proc isPointInTitleBar(window: OSWindow, mouseX, mouseY: float32): bool {.moddable.} =
  if not window.visible:
    return false

  # If minimized, check against full-width title bar
  if window.minimized:
    result = mouseX >= window.x.float32 and
             mouseX <= (window.x + window.savedWidth).float32 and
             mouseY >= window.y.float32 and
             mouseY <= (window.y + TITLE_BAR_HEIGHT).float32
  else:
    result = mouseX >= window.x.float32 and
             mouseX <= (window.x + window.width).float32 and
             mouseY >= window.y.float32 and
             mouseY <= (window.y + TITLE_BAR_HEIGHT).float32

proc isPointInWindow*(window: OSWindow, mouseX, mouseY: float32): bool {.moddable.} =
  if not window.visible or window.minimized:
    return false

  result = mouseX >= window.x.float32 and
           mouseX <= (window.x + window.width).float32 and
           mouseY >= window.y.float32 and
           mouseY <= (window.y + window.height).float32

proc toWindowSpace(src, dst: OSWindow, x, y: float32): Vector2 =
  ## A point in `src`'s scale layer, re-expressed in `dst`'s. Windows whose UI
  ## scale was capped differently do not share a coordinate space, so a point
  ## has to travel out to virtual pixels (times src's scale) and back down (by
  ## dst's) before it can be tested against another window's rect. A no-op
  ## whenever the two ended up at the same scale.
  let k = uiScaleOfWindow(src) / uiScaleOfWindow(dst)
  Vector2(x: x * k, y: y * k)

proc isWindowTopmostAtPoint*(window: OSWindow, mouseX, mouseY: float32, allWindows: openArray[OSWindow]): bool {.moddable.} =
  ## Check if this window is the topmost window at the given point, which is in
  ## `window`'s own coordinates (what getVirtualMousePosition returns while that
  ## window's scale layer is active).
  if not window.visible:
    return false

  # Check if point is in this window's clickable area
  # For minimized windows, only the title bar counts
  # For normal windows, the entire window counts
  let pointInThisWindow = if window.minimized:
    isPointInTitleBar(window, mouseX, mouseY)
  else:
    isPointInWindow(window, mouseX, mouseY)

  if not pointInThisWindow:
    return false

  # Check if any other window is on top at this point
  # Minimized windows title bars should also block clicks to windows behind them
  for otherWindow in allWindows:
    if otherWindow != window and not otherWindow.isNil and otherWindow.visible:
      if otherWindow.zOrder > window.zOrder:
        # Check if the other window covers this point, asked in its own space
        # For minimized windows, only the title bar counts
        # For normal windows, the entire window counts
        let p = toWindowSpace(window, otherWindow, mouseX, mouseY)
        let otherWindowCoversPoint = if otherWindow.minimized:
          isPointInTitleBar(otherWindow, p.x, p.y)
        else:
          isPointInWindow(otherWindow, p.x, p.y)

        if otherWindowCoversPoint:
          return false

  return true

proc isPointInCloseButton(window: OSWindow, mouseX, mouseY: float32): bool {.moddable.} =
  if not window.visible or window.minimized:
    return false
  checkCollisionPointRec(Vector2(x: mouseX, y: mouseY),
    chromeBtnHitRect(window.x + window.width, window.y, CLOSE_BTN_INSET))

proc isPointInMinimizeButton(window: OSWindow, mouseX, mouseY: float32): bool {.moddable.} =
  if not window.visible:
    return false
  # When minimized this is the restore button, which sits in the full-width
  # title bar and so measures from savedWidth.
  let rightEdge = if window.minimized: window.x + window.savedWidth
                  else: window.x + window.width
  let inset = if window.minimized: CLOSE_BTN_INSET else: MIN_BTN_INSET
  checkCollisionPointRec(Vector2(x: mouseX, y: mouseY),
    chromeBtnHitRect(rightEdge, window.y, inset))

proc getResizeEdge(window: OSWindow, mouseX, mouseY: float32): int {.moddable.} =
  ## Returns which edge is being hovered for resizing
  ## 0=none, 1=right, 2=bottom, 3=corner
  if not window.visible or window.minimized or not window.resizable:
    return 0

  let edgeThreshold = 8
  let rightEdge = window.x + window.width
  let bottomEdge = window.y + window.height

  let onRightEdge = abs(mouseX - rightEdge.float32) < edgeThreshold.float32
  let onBottomEdge = abs(mouseY - bottomEdge.float32) < edgeThreshold.float32

  if onRightEdge and onBottomEdge:
    return 3  # Corner
  elif onRightEdge:
    return 1  # Right edge
  elif onBottomEdge:
    return 2  # Bottom edge
  else:
    return 0  # No edge

proc handleOSWindowInput*(window: OSWindow, screenWidth, screenHeight: int, allWindows: openArray[OSWindow]): bool {.moddable.} =
  ## Returns true if window should close
  if not window.visible:
    return false

  # Check ESC key to close window when focused
  if window.focused and isBackPressed():
    return true

  let mousePos = getVirtualMousePosition()

  # Handle dragging
  if window.dragging:
    if isPointerDown():
      window.x = int(mousePos.x) - window.dragOffsetX
      window.y = int(mousePos.y) - window.dragOffsetY
      window.x = max(0, min(window.x, screenWidth - window.width))
      window.y = max(0, min(window.y, screenHeight - 100))
    else:
      window.dragging = false
    return false

  # Handle resizing
  if window.resizing:
    if isPointerDown():
      case window.resizeEdge
      of 1:  # Right edge
        window.width = max(MIN_WINDOW_WIDTH, int(mousePos.x) - window.x)
      of 2:  # Bottom edge
        window.height = max(MIN_WINDOW_HEIGHT, int(mousePos.y) - window.y)
      of 3:  # Corner
        window.width = max(MIN_WINDOW_WIDTH, int(mousePos.x) - window.x)
        window.height = max(MIN_WINDOW_HEIGHT, int(mousePos.y) - window.y)
      else:
        discard
    else:
      window.resizing = false
      window.resizeEdge = 0
    return false

  # Two pointer signals, identical on desktop (both are the mouse-down frame) but
  # distinct on touch: a drag has to be *started* on press, while a button press
  # must only *commit* once the gesture is known to be a tap and not a scroll.
  let dragStart = isPointerDragStart()
  let tapped = isPointerPressed()

  if dragStart or tapped:
    let clickOnThisWindowArea = if window.minimized:
      isPointInTitleBar(window, mousePos.x, mousePos.y)
    else:
      isPointInWindow(window, mousePos.x, mousePos.y)

    if not clickOnThisWindowArea:
      return false  # Click is not on this window at all

    # Step 2: Find which window should handle this click (highest z-order at this point).
    # `mousePos` is in *this* window's scale layer, and a window whose scale was
    # capped differently does not share that space, so each candidate is asked in
    # its own coordinates (see toWindowSpace). Identical to the old single-space
    # test whenever every window ended up at the same scale (e.g. any scale <= 100%).
    var windowThatShouldHandle: OSWindow = nil
    var highestZ = -1

    for w in allWindows:
      if w.isNil or not w.visible:
        continue

      let p = toWindowSpace(window, w, mousePos.x, mousePos.y)

      # Check if this window covers the click point
      let windowCoversClick = if w.minimized:
        isPointInTitleBar(w, p.x, p.y)
      else:
        isPointInWindow(w, p.x, p.y)

      if windowCoversClick and w.zOrder > highestZ:
        highestZ = w.zOrder
        windowThatShouldHandle = w

    # Step 3: Only handle if WE are the topmost window at this click
    if windowThatShouldHandle != window:
      return false  # Another window should handle this

    # WE handled this click - bring window to front immediately
    window.handledClickThisFrame = tapped
    window.handledPressThisFrame = dragStart

    # Bring to front if not already focused
    if not window.focused:
      bringWindowToFront(window, allWindows)

    let onCloseButton = isPointInCloseButton(window, mousePos.x, mousePos.y)
    let onMinimizeButton = isPointInMinimizeButton(window, mousePos.x, mousePos.y)

    # Handle close button
    if tapped and onCloseButton:
      return true

    # Handle minimize/restore button
    if tapped and onMinimizeButton:
      if window.minimized:
        startRestoreAnimation(window)
      else:
        startMinimizeAnimation(window)
      window.dragging = false
      window.resizing = false
      window.resizeEdge = 0
      return false

    # The chrome buttons sit *inside* the title bar, so a press on one must not
    # also begin a drag: on touch the drag branch above would then swallow the
    # release frame and the button could never fire.
    if dragStart and not onCloseButton and not onMinimizeButton:
      # Handle resize edges
      let edge = getResizeEdge(window, mousePos.x, mousePos.y)
      if edge > 0:
        window.resizing = true
        window.resizeEdge = edge
        return false

      # Handle title bar dragging
      if isPointInTitleBar(window, mousePos.x, mousePos.y):
        window.dragging = true
        window.dragOffsetX = int(mousePos.x) - window.x
        window.dragOffsetY = int(mousePos.y) - window.y
        return false

  return false

proc drawCknCaptionButton(x, y: int, hovered: bool, hoverFill: Color) =
  ## The square behind a CKN caption glyph: only there while hovered.
  if hovered:
    drawRectangleRounded(Rectangle(x: x.float32, y: y.float32, width: 20, height: 20),
                         0.3'f32, 6, hoverFill)

proc drawCknWindowChrome(window: OSWindow, th: UiTheme) =
  ## The CKN shell's window: rounded, a soft shadow instead of a glow, the
  ## focus shown by an accent border and an accent-tinted title bar, all from
  ## the theme's anchors. Hit-testing is the stock chrome's (same title bar
  ## and button rects).
  const Radius = 8.0'f32
  let w = if window.minimized: window.savedWidth else: window.width
  let h = if window.minimized: TITLE_BAR_HEIGHT else: window.height
  let x = window.x.float32
  let y = window.y.float32
  let hairline = colorLerp(th.surface, th.raised, 0.75'f32)
  let titleFill = if window.focused: colorLerp(th.surface, th.accent, 0.12'f32)
                  else: colorLerp(th.surface, th.raised, 0.25'f32)
  let border = if window.focused: withAlpha(th.accent, 190) else: hairline
  drawCknPanel(Rectangle(x: x, y: y, width: w.float32, height: h.float32), Radius,
               if window.minimized: titleFill else: th.surface, border,
               shadowAlpha = if window.focused: 80.0'f32 else: 45.0'f32)
  if not window.minimized:
    # The title band: rounded on top, squared off where it meets the body.
    let band = Rectangle(x: x, y: y, width: w.float32, height: TITLE_BAR_HEIGHT.float32 + Radius)
    drawRectangleRounded(band, cornerRoundness(band.width, band.height, Radius), 10, titleFill)
    drawRectangle(window.x.int32, (window.y + TITLE_BAR_HEIGHT).int32, w.int32, Radius.int32 + 1, th.surface)
    drawRectangle(window.x.int32, (window.y + TITLE_BAR_HEIGHT).int32, w.int32, 1, hairline)

  drawRectangleRounded(Rectangle(x: x + 9.0'f32, y: y + 8.0'f32, width: 14, height: 14),
                       0.45'f32, 6, window.iconColor)
  let glyph = if window.focused: th.text else: th.muted
  drawText(window.title, (window.x + 32).int32, (window.y + 6).int32, 18, glyph)

  let mousePos = getVirtualMousePosition()
  let buttonY = window.y + 5
  let hoverFill = colorLerp(th.surface, th.raised, 0.5'f32)
  if window.minimized:
    let restoreX = window.x + window.savedWidth - CLOSE_BTN_INSET
    let hoverRestore = isPointInMinimizeButton(window, mousePos.x, mousePos.y)
    drawCknCaptionButton(restoreX, buttonY, hoverRestore, hoverFill)
    drawRectOutline(Rectangle(x: (restoreX + 5).float32, y: (buttonY + 5).float32,
                              width: 10, height: 10), 2, glyph)
    return

  let closeX = window.x + window.width - CLOSE_BTN_INSET
  let hoverClose = isPointInCloseButton(window, mousePos.x, mousePos.y)
  drawCknCaptionButton(closeX, buttonY, hoverClose, Color(r: 226, g: 72, b: 72, a: 255))
  let cross = if hoverClose: White else: glyph
  let cx = (closeX + 10).float32
  let cy = (buttonY + 10).float32
  drawStroke(Vector2(x: cx - 4.5'f32, y: cy - 4.5'f32), Vector2(x: cx + 4.5'f32, y: cy + 4.5'f32), 2, cross)
  drawStroke(Vector2(x: cx + 4.5'f32, y: cy - 4.5'f32), Vector2(x: cx - 4.5'f32, y: cy + 4.5'f32), 2, cross)

  let minX = window.x + window.width - MIN_BTN_INSET
  let hoverMin = isPointInMinimizeButton(window, mousePos.x, mousePos.y)
  drawCknCaptionButton(minX, buttonY, hoverMin, hoverFill)
  drawRectangle((minX + 5).int32, (buttonY + 13).int32, 10, 2, glyph)

proc drawWindowChrome*(window: OSWindow) {.moddable.} =
  if not window.visible:
    return

  let th = activeTheme()
  if th.shell == ssCkn:
    drawCknWindowChrome(window, th)
    return

  # If minimized, only draw full-width title bar (handled here)
  if window.minimized:
    let miniHeight = TITLE_BAR_HEIGHT

    # Draw minimized window as full-width title bar
    drawRectangle(window.x.int32, window.y.int32,
                 window.savedWidth.int32, miniHeight.int32,
                 uiSurface(40, 40, 50, 240))

    let borderColor = if window.focused:
      uiLine(0, 200, 255)
    else:
      uiLine(80, 80, 100)

    drawRectOutline(Rectangle(x: window.x.float32, y: window.y.float32,
                                  width: window.savedWidth.float32, height: miniHeight.float32),
                      WINDOW_BORDER, borderColor)

    # Icon
    let iconSize = 16
    let iconX = window.x + 8
    let iconY = window.y + 7
    drawRectangle(iconX.int32, iconY.int32, iconSize.int32, iconSize.int32, window.iconColor)

    # Title text
    drawText(window.title, (window.x + 32).int32, (window.y + 6).int32, 18,
            uiInk(0, 200, 255))

    # Restore button
    let buttonSize = CHROME_BTN_SIZE
    let buttonY = window.y + (TITLE_BAR_HEIGHT - buttonSize) div 2
    let restoreX = window.x + window.savedWidth - CLOSE_BTN_INSET
    let glyphInset = buttonSize div 4
    let glyphSize = buttonSize div 2

    let mousePos = getVirtualMousePosition()
    let hoverRestore = isPointInMinimizeButton(window, mousePos.x, mousePos.y)

    drawRectangle(restoreX.int32, buttonY.int32, buttonSize.int32, buttonSize.int32,
                 if hoverRestore: uiSurface(100, 200, 100)
                 else: uiSurface(60, 60, 70))
    drawRectangle((restoreX + glyphInset).int32, (buttonY + glyphInset).int32,
                 glyphSize.int32, glyphSize.int32,
                 uiInk(200, 200, 200))
    drawRectOutline(Rectangle(x: (restoreX + glyphInset).float32,
                              y: (buttonY + glyphInset).float32,
                              width: glyphSize.float32, height: glyphSize.float32),
                      1, uiInk(White))
    return

  # Draw full window (not minimized)
  # Enhanced shadow
  drawRectangle((window.x + 3).int32, (window.y + 3).int32,
               window.width.int32, window.height.int32,
               Color(r: 0, g: 0, b: 0, a: 100))

  # Panel glow effect when focused
  if window.focused:
    let glowPulse = sin(window.time * 3.0) * 0.3 + 0.7
    let glowSize = 6
    for i in 1..glowSize:
      let glowAlpha = uint8((30.0 / i.float32) * glowPulse)
      drawRectOutline(Rectangle(
        x: (window.x - i).float32,
        y: (window.y - i).float32,
        width: (window.width + i * 2).float32,
        height: (window.height + i * 2).float32
      ), 1, uiGlow(0, 200, 255, glowAlpha.int))

  # Main window background
  drawRectangle(window.x.int32, window.y.int32,
               window.width.int32, window.height.int32,
               uiSurface(20, 20, 30, 240))

  # Border with glow if focused
  let borderColor = if window.focused:
    uiLine(0, 200, 255)
  else:
    uiLine(80, 80, 100)

  drawRectOutline(Rectangle(x: window.x.float32, y: window.y.float32,
                                width: window.width.float32, height: window.height.float32),
                    WINDOW_BORDER, borderColor)

  # Title bar
  drawRectangle(window.x.int32, window.y.int32,
               window.width.int32, TITLE_BAR_HEIGHT.int32,
               uiSurface(40, 40, 50))

  # Icon
  let iconSize = 16
  let iconX = window.x + 8
  let iconY = window.y + 7
  drawRectangle(iconX.int32, iconY.int32, iconSize.int32, iconSize.int32, window.iconColor)

  # Title text
  drawText(window.title, (window.x + 32).int32, (window.y + 6).int32, 18,
          uiInk(0, 200, 255))

  # Window buttons
  let buttonSize = CHROME_BTN_SIZE
  let buttonY = window.y + (TITLE_BAR_HEIGHT - buttonSize) div 2

  # Close button
  let closeX = window.x + window.width - CLOSE_BTN_INSET
  let mousePos = getVirtualMousePosition()
  let hoverClose = isPointInCloseButton(window, mousePos.x, mousePos.y)

  drawRectangle(closeX.int32, buttonY.int32, buttonSize.int32, buttonSize.int32,
               if hoverClose: uiSurface(255, 80, 80)
               else: uiSurface(60, 60, 70))
  let xWidth = measureText("X", 16)
  drawText("X", (closeX + (buttonSize - xWidth) div 2).int32,
           (buttonY + (buttonSize - 16) div 2).int32, 16, uiInk(White))

  # Minimize button
  let minX = window.x + window.width - MIN_BTN_INSET
  let hoverMin = isPointInMinimizeButton(window, mousePos.x, mousePos.y)

  drawRectangle(minX.int32, buttonY.int32, buttonSize.int32, buttonSize.int32,
               if hoverMin: uiSurface(100, 150, 200)
               else: uiSurface(60, 60, 70))
  drawRectangle((minX + buttonSize div 4).int32, (buttonY + buttonSize - 6).int32,
               (buttonSize div 2).int32, 2, uiInk(White))

proc drawResizeIndicator*(window: OSWindow) {.moddable.} =
  ## Draw resize indicators on edges
  if not window.visible or window.minimized:
    return

  let mousePos = getVirtualMousePosition()
  let edge = getResizeEdge(window, mousePos.x, mousePos.y)

  if window.resizable and (edge > 0 or window.resizing):
    # Draw resize grip in bottom-right corner
    let gripX = window.x + window.width - 12
    let gripY = window.y + window.height - 12

    for i in 0..<3:
      let offset = i * 4
      drawStroke(Vector2(x: (gripX + offset).float32, y: (gripY + 8).float32),
              Vector2(x: (gripX + 8).float32, y: (gripY + offset).float32),
              2, uiLine(100, 100, 120))
