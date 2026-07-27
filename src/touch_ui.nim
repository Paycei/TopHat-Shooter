## Touch input seam for the MENU layer (the OS-desktop, its windows, and the
## fullscreen overlay states). The gameplay counterpart is `mobile_controls`.
##
## Compiled only into `-d:mobile` builds. `gamepad_input` imports and re-exports
## this module, so the touch behaviour reaches every existing call site through
## the pointer wrappers those call sites already use -- no per-window edits:
##   - getPointerWheelMove() picks up `touchWheelMove()`  -> drag-to-scroll
##   - isPointerPressed()    picks up `touchTapPressed()` -> tap-not-drag
##   - isBackPressed()       picks up `touchBackPressed()`-> on-screen back
##
## Dependency rule: `render_context` imports `gamepad_input`, which imports this
## module, so this module must NOT import render_context (that is the cycle).
## It therefore takes the letterbox transform as a `TouchViewport` parameter,
## which `main` fills in from render_context once per frame. Drawing is fine to
## do here: the draw pass is already in virtual space, so plain raylib calls
## with virtual coordinates land correctly.
##
## The pointer is read through raylib's mouse API rather than the touch API on
## purpose: Android's backend synthesizes mouse-left + position from touch point
## 0, and on desktop the real mouse drives the same path -- which is what makes
## `nim c -r -d:mobile` a usable single-finger simulator for the whole menu.

import raylib, math

type
  TouchViewport* = object
    ## The letterbox transform, mirrored from render_context so this module can
    ## stay a leaf. Built by main each frame via `touchViewport`.
    scale*: float32
    offsetX*, offsetY*: float32
    virtualW*, virtualH*: float32

const
  TapSlop = 14.0'f32
    ## Virtual-space travel that turns a press into a drag. Above this the
    ## gesture scrolls and will NOT emit a tap, so dragging a shop list past an
    ## item doesn't also buy it. Generous, because a thumb rolls several pixels
    ## on a deliberate tap.
  DetentPx = 34.0'f32
    ## Virtual pixels of drag per emitted wheel "notch".
    ##
    ## Notches are deliberately quantized instead of being a linear px->px
    ## mapping. The existing call sites interpret one notch wildly differently
    ## (x1 row in advancements_window, x3 lines in help_window, x20 px in
    ## os_shop, x400 px/s of velocity in shop_window), so no single linear
    ## factor can be right everywhere. Treating a drag as a series of detents --
    ## the same thing a physical wheel emits -- keeps every one of them within a
    ## sane range instead of making the velocity-based ones unusable.
  FlickDecay = 4.5'f32
    ## Per-second exponential decay of post-release momentum.
  FlickCutoff = 40.0'f32
    ## Momentum below this (virtual px/s) is dropped, ending the glide.
  MaxFlickSpeed = 4200.0'f32
    ## Clamp so a fast swipe can't fling a list thousands of rows.
  VelocitySmoothing = 0.75'f32
    ## Weight of the newest sample in the release-velocity estimate.

  BackBtnW = 104.0'f32
  BackBtnH = 64.0'f32
  BackBtnMargin = 20.0'f32

  # --- virtual keyboard geometry (virtual-canvas units) ---
  VkKeyH = 54.0'f32
  VkGap = 6.0'f32
  VkPadding = 10.0'f32
  VkUnitW = 106.0'f32      ## width of a one-unit key
  VkBackRepeatDelay = 0.40'f32
  VkBackRepeatRate = 0.07'f32

type
  TextInputKind* = enum
    tikText      ## full QWERTY (nicknames, search boxes, the help terminal)
    tikNumeric   ## digits and '.' only (IP, port, FPS cap)

  VKAction = enum
    vkaChar, vkaShift, vkaBack, vkaSpace, vkaEnter, vkaDone

  VKey = object
    label: string
    ch: int32          ## codepoint for vkaChar
    action: VKAction
    units: float32     ## width, in VkUnitW multiples

const
  VkTextRows = ["1234567890", "qwertyuiop", "asdfghjkl", "zxcvbnm"]
  VkNumRows = ["123", "456", "789", ".0"]

var
  vp = TouchViewport(scale: 1, virtualW: 1366, virtualH: 768)
  pointerWasDown = false
  gestureStart = Vector2(x: 0, y: 0)   ## virtual position of the touch-down
  gesturePrev = Vector2(x: 0, y: 0)
  gestureIsDrag = false
  scrollAccum: float32 = 0             ## un-emitted drag distance, virtual px
  frameNotches: float32 = 0            ## this frame's wheel value (non-consuming)
  flickVelocity: float32 = 0           ## virtual px/s, decaying after release
  tapPressed = false
  backTapped = false
  backVisible = false
  # --- virtual keyboard ---
  vkActive = false          ## a text field asked for input this frame
  vkRequested = false       ## set by setTextInputActive, consumed each frame
  vkKind = tikText
  vkShift = false
  vkDismissed = false       ## "done" was tapped; stays down until focus changes
  vkChars: seq[int32] = @[] ## FIFO drained by pollCharPressed
  vkBackQueued = false
  vkEnterQueued = false
  vkBackHeldTime: float32 = 0
  vkBackDown = false
  gestureOnKeyboard = false ## the live gesture started on the keyboard panel

proc setTouchViewport*(v: TouchViewport) =
  vp = v

proc screenToVirtualLocal(p: Vector2): Vector2 =
  ## Local copy of render_context.screenToVirtual -- see the dependency note in
  ## the module doc for why this can't just call it.
  let s = max(vp.scale, 0.0001'f32)
  result.x = clamp((p.x - vp.offsetX) / s, 0.0'f32, vp.virtualW)
  result.y = clamp((p.y - vp.offsetY) / s, 0.0'f32, vp.virtualH)

# --- on-screen back button ---------------------------------------------------

proc backBtnRect*(): Rectangle =
  ## Top-left. Kept clear of the mobile pause button (top-right, mobile_controls)
  ## and only drawn in the fullscreen overlay states, where nothing else lives
  ## in this corner -- the OS-desktop's icon grid starts here, which is why
  ## gsMenu relies on its window close buttons instead.
  Rectangle(x: BackBtnMargin, y: BackBtnMargin, width: BackBtnW, height: BackBtnH)

proc setTouchBackVisible*(v: bool) =
  ## Arm the back button for this frame. Main sets it per game state; when it is
  ## false the button is neither drawn nor hit-tested.
  backVisible = v

proc pointInRect(p: Vector2, r: Rectangle): bool =
  p.x >= r.x and p.x <= r.x + r.width and p.y >= r.y and p.y <= r.y + r.height

proc drawTouchBackButton*() =
  ## Draw inside the virtual-canvas pass. No text, so it needs no localization.
  if not backVisible: return
  let r = backBtnRect()
  drawRectangleRounded(r, 0.35, 8, Color(r: 40, g: 46, b: 66, a: 170))
  drawRectangleRoundedLines(r, 0.35, 8, 2.0, Color(r: 180, g: 200, b: 255, a: 210))
  # Left-pointing chevron, drawn as two thick lines so there is no triangle
  # winding to worry about (same reasoning as the mobile ability button).
  let cx = r.x + r.width / 2
  let cy = r.y + r.height / 2
  drawLine(Vector2(x: cx + 10, y: cy - 14), Vector2(x: cx - 10, y: cy), 5.0, White)
  drawLine(Vector2(x: cx - 10, y: cy), Vector2(x: cx + 10, y: cy + 14), 5.0, White)

# --- virtual keyboard --------------------------------------------------------
#
# Drawn with raylib in virtual-canvas coordinates rather than bridged to the
# Android IME: NativeActivity shows no soft keyboard of its own, and reaching
# one would mean a Java Activity subclass plus JNI, which would cost the app its
# `android:hasCode="false"` native-only build.

proc setTextInputActive*(active: bool, kind: TextInputKind = tikText) =
  ## Called by whichever text field currently has focus, every frame it has it.
  ## Simply not calling it is equivalent to passing false; either way the
  ## keyboard re-arms, so a field closed with "done" reopens when refocused.
  vkRequested = active
  if active:
    vkKind = kind

proc textInputActive*(): bool =
  ## Whether the keyboard is on screen. Callers should not need this; it exists
  ## so layout code can shift a field out from under the panel if it wants to.
  vkActive

proc vkRows(): seq[seq[VKey]] =
  ## Build the current layout. Cheap enough to rebuild per frame, and it keeps
  ## the shift state from needing a cache to invalidate.
  result = @[]
  if vkKind == tikNumeric:
    for row in VkNumRows:
      var keys: seq[VKey] = @[]
      for c in row:
        keys.add VKey(label: $c, ch: c.int32, action: vkaChar, units: 1.0)
      result.add keys
    result[3].add VKey(label: "<", action: vkaBack, units: 1.0)
    result.add @[VKey(label: "OK", action: vkaEnter, units: 1.5),
                 VKey(label: "DONE", action: vkaDone, units: 1.5)]
  else:
    for i, row in VkTextRows:
      var keys: seq[VKey] = @[]
      if i == 3:
        keys.add VKey(label: (if vkShift: "^" else: "v"), action: vkaShift, units: 1.5)
      for c in row:
        let shown = if vkShift and c in {'a'..'z'}: char(c.ord - 32) else: c
        keys.add VKey(label: $shown, ch: shown.int32, action: vkaChar, units: 1.0)
      if i == 3:
        keys.add VKey(label: "<", action: vkaBack, units: 1.5)
      result.add keys
    result.add @[VKey(label: ".", ch: '.'.int32, action: vkaChar, units: 1.0),
                 VKey(label: "SPACE", action: vkaSpace, units: 4.0),
                 VKey(label: "ENTER", action: vkaEnter, units: 2.0),
                 VKey(label: "DONE", action: vkaDone, units: 2.0)]

proc vkPanelRect(rows: seq[seq[VKey]]): Rectangle =
  let h = rows.len.float32 * (VkKeyH + VkGap) - VkGap + VkPadding * 2
  Rectangle(x: 0, y: vp.virtualH - h, width: vp.virtualW, height: h)

proc vkKeyRect(rows: seq[seq[VKey]], r, k: int): Rectangle =
  ## Rows are centred independently, so a short row (zxcvbnm) sits under the
  ## middle of the long one above it the way a real keyboard does.
  let panel = vkPanelRect(rows)
  var totalUnits = 0.0'f32
  for key in rows[r]: totalUnits += key.units
  let rowW = totalUnits * VkUnitW + (rows[r].len - 1).float32 * VkGap
  var x = panel.x + (panel.width - rowW) / 2
  for i in 0 ..< k:
    x += rows[r][i].units * VkUnitW + VkGap
  Rectangle(x: x, y: panel.y + VkPadding + r.float32 * (VkKeyH + VkGap),
            width: rows[r][k].units * VkUnitW, height: VkKeyH)

proc vkPressKey(key: VKey) =
  case key.action
  of vkaChar:
    vkChars.add key.ch
    # One-shot shift, like a phone keyboard: capitalise a letter, not a word.
    if vkShift: vkShift = false
  of vkaSpace: vkChars.add ' '.int32
  of vkaShift: vkShift = not vkShift
  of vkaBack: vkBackQueued = true
  of vkaEnter: vkEnterQueued = true
  of vkaDone: vkDismissed = true

proc vkHandlePress(p: Vector2): bool =
  ## Route a press inside the panel. Returns true if the panel consumed it --
  ## including presses that hit the panel background between keys, so a clumsy
  ## tap never falls through and activates the UI underneath.
  let rows = vkRows()
  if not pointInRect(p, vkPanelRect(rows)):
    return false
  for r in 0 ..< rows.len:
    for k in 0 ..< rows[r].len:
      if pointInRect(p, vkKeyRect(rows, r, k)):
        vkPressKey(rows[r][k])
        vkBackDown = rows[r][k].action == vkaBack
        vkBackHeldTime = 0
        return true
  true

proc drawVirtualKeyboard*() =
  ## Draw inside the virtual-canvas pass, above the window layer.
  if not vkActive: return
  let rows = vkRows()
  let panel = vkPanelRect(rows)
  drawRectangle(panel, Color(r: 16, g: 20, b: 30, a: 240))
  drawLine(Vector2(x: panel.x, y: panel.y),
           Vector2(x: panel.x + panel.width, y: panel.y), 2.0,
           Color(r: 90, g: 130, b: 180, a: 200))
  for r in 0 ..< rows.len:
    for k in 0 ..< rows[r].len:
      let key = rows[r][k]
      let rect = vkKeyRect(rows, r, k)
      let lit = key.action == vkaShift and vkShift
      drawRectangleRounded(rect, 0.25, 6,
                           if lit: Color(r: 70, g: 110, b: 170, a: 255)
                           else: Color(r: 44, g: 52, b: 72, a: 255))
      drawRectangleRoundedLines(rect, 0.25, 6, 1.5,
                                Color(r: 110, g: 140, b: 190, a: 180))
      let size = if key.label.len > 1: 18'i32 else: 26'i32
      let w = measureText(key.label, size)
      drawText(key.label, (rect.x + (rect.width - w.float32) / 2).int32,
               (rect.y + (rect.height - size.float32) / 2).int32, size, White)

proc pollVkChar*(): int32 =
  ## Pop one queued character, 0 when empty -- same contract as getCharPressed,
  ## so the existing `while key > 0` drain loops work unchanged.
  if vkChars.len == 0: return 0
  result = vkChars[0]
  vkChars.delete(0)

proc pollVkBackspace*(): bool =
  result = vkBackQueued
  vkBackQueued = false

proc pollVkEnter*(): bool =
  result = vkEnterQueued
  vkEnterQueued = false

# --- per-frame gesture resolution --------------------------------------------

proc updateTouchUI*(dt: float32) =
  ## Resolve this frame's pointer gesture. Must run before the state machine so
  ## every pointer wrapper queried this frame sees the same answer. The viewport
  ## is pushed separately by render_context.updateRenderInputTransform, so it is
  ## always current by the time this runs.
  tapPressed = false
  backTapped = false
  frameNotches = 0

  # Resolve keyboard visibility from last frame's request. The UI sets it during
  # the state machine, i.e. after this runs, so it is always one frame behind --
  # which is invisible, and keeps the whole thing free of ordering constraints.
  vkActive = vkRequested and not vkDismissed
  if not vkRequested:
    # Focus lost (or never taken): re-arm, so the next field to take focus gets
    # a keyboard even if the previous one was closed with "done".
    vkDismissed = false
  vkRequested = false
  if not vkActive:
    vkShift = false
    vkBackDown = false
    vkChars.setLen(0)

  let down = isMouseButtonDown(MouseButton.Left)
  let cur = screenToVirtualLocal(getMousePosition())

  # Backspace auto-repeat while the key is held.
  if vkActive and vkBackDown and down:
    vkBackHeldTime += dt
    if vkBackHeldTime >= VkBackRepeatDelay:
      vkBackQueued = true
      vkBackHeldTime = VkBackRepeatDelay - VkBackRepeatRate
  elif not down:
    vkBackDown = false

  if down and not pointerWasDown:
    # Touch down: a new gesture cancels any glide still running.
    gestureStart = cur
    gesturePrev = cur
    gestureIsDrag = false
    flickVelocity = 0
    scrollAccum = 0
    # Keys fire on press, not release: a keyboard has to feel immediate, and it
    # is the one surface where a press can't be meant as the start of a scroll.
    gestureOnKeyboard = vkActive and vkHandlePress(cur)
  elif down and gestureOnKeyboard:
    discard  # the panel owns this gesture; no scrolling, no tap
  elif down:
    let dy = cur.y - gesturePrev.y
    if not gestureIsDrag:
      let moved = max(abs(cur.x - gestureStart.x), abs(cur.y - gestureStart.y))
      if moved > TapSlop:
        gestureIsDrag = true
        # Fold in the slop travel so the content doesn't jump when the drag
        # starts -- it should already be under the finger by then.
        scrollAccum += cur.y - gestureStart.y
    if gestureIsDrag:
      scrollAccum += dy
      if dt > 0:
        let sample = dy / dt
        flickVelocity = flickVelocity * (1.0'f32 - VelocitySmoothing) +
                        sample * VelocitySmoothing
    gesturePrev = cur
  elif pointerWasDown:
    # Touch up: a gesture that never became a drag is a tap.
    if gestureOnKeyboard:
      gestureOnKeyboard = false
      gestureIsDrag = false
      flickVelocity = 0
    elif gestureIsDrag:
      flickVelocity = clamp(flickVelocity, -MaxFlickSpeed, MaxFlickSpeed)
    else:
      flickVelocity = 0
      if backVisible and pointInRect(cur, backBtnRect()):
        backTapped = true
      else:
        tapPressed = true
    gestureIsDrag = false
  else:
    # Idle: glide.
    if flickVelocity != 0:
      scrollAccum += flickVelocity * dt
      flickVelocity *= pow(0.5'f32, dt * FlickDecay)
      if abs(flickVelocity) < FlickCutoff:
        flickVelocity = 0

  # Emit whole detents; the remainder carries to the next frame so slow drags
  # still accumulate instead of being rounded away.
  if abs(scrollAccum) >= DetentPx:
    # Content follows the finger: dragging up (negative dy) must scroll the list
    # down, and every call site is written as `offset -= wheel * k`.
    let whole = trunc(scrollAccum / DetentPx)
    frameNotches = whole
    scrollAccum -= whole * DetentPx

  pointerWasDown = down

# --- queries consumed by gamepad_input ---------------------------------------

proc touchWheelMove*(): float32 =
  ## This frame's scroll in wheel notches. Non-consuming: several windows call
  ## getPointerWheelMove() per frame and, like the real mouse wheel, they must
  ## all see the same value.
  frameNotches

proc touchTapPressed*(): bool =
  ## True on the frame a tap is *released* without having become a drag.
  ## Deliberately not the press frame: at press time it isn't yet known whether
  ## the finger is going to scroll. Drag handles need the raw press instead --
  ## see gamepad_input.isPointerDragStart.
  tapPressed

proc touchDragActive*(): bool =
  ## The pointer is currently scrolling. Hover/selection code can use this to
  ## avoid highlighting whatever the finger happens to be sliding over.
  gestureIsDrag

proc touchBackPressed*(): bool =
  ## The on-screen back chip was tapped, or the hardware back key fired.
  ## raylib's Android backend may consume AKEYCODE_BACK before it reaches the
  ## key state, which is exactly why the on-screen chip is the primary path and
  ## the key is only an additional one.
  backTapped or isKeyPressed(KeyboardKey.Back)
