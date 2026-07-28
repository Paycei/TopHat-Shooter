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
  VkPreviewH = 40.0'f32
    ## Height of the strip drawn directly above the panel, echoing the focused
    ## field's text. The panel eats the bottom ~40% of a 768-tall canvas, and
    ## some fields live under it (the help terminal's prompt sits at y~594), so
    ## without this you would be typing blind.
  VkChipW = 112.0'f32
  VkChipH = 56.0'f32
    ## The "reopen keyboard" chip, shown when a field still has focus but the
    ## panel was closed with DONE. Without it that state is a trap: the field
    ## keeps requesting input every frame, so the dismiss latch never clears.

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
  vkBackKeyRect = Rectangle(x: 0, y: 0, width: 0, height: 0)
    ## Hit rect of the backspace key that armed the repeat, so the repeat stops
    ## when the finger slides off it instead of running until the touch ends.
  vkOverlayTop: float32 = 1e9
    ## Virtual y of the top of everything the keyboard occludes (preview strip
    ## included). 1e9 while it is hidden, so every "is the pointer on the
    ## keyboard" test below is simply `y >= vkOverlayTop` and costs nothing when
    ## there is no keyboard. Recomputed once per frame.
  vkChipVisible = false     ## the reopen chip is on screen this frame
  vkPreview = ""            ## focused field's text, echoed above the panel
  vkPreviewNext = ""
  vkHasPreview = false
  vkHasPreviewNext = false
  vkTouchIds: seq[int32] = @[]
    ## Touch ids seen last frame. Keys fire per *touch point*, not off the
    ## emulated mouse: Android holds MOUSE_LEFT down while any finger is down,
    ## so a second thumb landing while the first is still on a key produces no
    ## mouse press edge at all and its keystroke would simply vanish.
  gestureOnKeyboard = false ## the live gesture started on the keyboard panel
  keyboardOwnsPointer = false
    ## Like gestureOnKeyboard, but stays true through the release frame, so the
    ## press/release wrappers can suppress a whole keyboard-owned gesture.
  lastPointerOffKeyboard = Vector2(x: 0, y: 0)
    ## Last pointer position that was NOT on the keyboard. Reported in place of
    ## the real one while typing -- see touchKeyboardMaskPointer.

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
  ## Simply not calling it is equivalent to passing false.
  ##
  ## The request LATCHES for the frame: `false` never clears a `true` from
  ## another window. It has to, because every visible window is updated each
  ## frame and several call this unconditionally -- pvp_window passes
  ## `editingNickname or editingIP or editingPort`, which used to overwrite the
  ## shop's or the help terminal's request with `false` purely because it ran
  ## later in the loop, and the keyboard would never appear. The per-frame reset
  ## in updateTouchUI is what makes "stop calling it" still hide the panel.
  ##
  ## First caller wins, and window_manager updates windows topmost-first, so the
  ## front-most field picks the layout.
  if active and not vkRequested:
    vkRequested = true
    if kind != vkKind:
      # A different *kind* of field took focus: treat that as new focus and
      # clear the dismiss latch, so DONE on the nickname doesn't leave the IP
      # field with no keyboard.
      vkKind = kind
      vkDismissed = false

proc setTextInputPreview*(text: string) =
  ## Optional: the current contents of the focused field, echoed in a strip
  ## above the panel. Fields that sit under the keyboard (the help terminal's
  ## prompt) are otherwise invisible while being typed into. First caller wins,
  ## matching setTextInputActive.
  if not vkHasPreviewNext:
    vkHasPreviewNext = true
    vkPreviewNext = text

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
        # Constant label, lit while armed. The old "^"/"v" pair read as two more
        # letters sitting in the middle of the QWERTY block.
        keys.add VKey(label: "SHIFT", action: vkaShift, units: 1.5)
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

proc vkChipRect(): Rectangle =
  ## Top-right, mirroring the back chip at top-left -- deliberately NOT bottom
  ## anchored, where it would sit on the desktop taskbar.
  Rectangle(x: vp.virtualW - BackBtnMargin - VkChipW, y: BackBtnMargin,
            width: VkChipW, height: VkChipH)

proc vkHitKey(p: Vector2) =
  ## Fire the key under `p`, if any. Presses that land on the panel background
  ## between keys do nothing but are still consumed by the caller, so a clumsy
  ## tap never falls through and activates the UI underneath.
  let rows = vkRows()
  for r in 0 ..< rows.len:
    for k in 0 ..< rows[r].len:
      let rect = vkKeyRect(rows, r, k)
      if pointInRect(p, rect):
        vkPressKey(rows[r][k])
        if rows[r][k].action == vkaBack:
          vkBackDown = true
          vkBackKeyRect = rect
          vkBackHeldTime = 0
        return

proc anyPointerInRect(r: Rectangle): bool =
  ## Is any live pointer inside `r`? Prefers the touch array (so the finger that
  ## actually owns the key is the one that counts, not whichever one the
  ## emulated mouse happens to be tracking) and falls back to the held mouse on
  ## desktop, where the touch array is never populated.
  let n = getTouchPointCount()
  if n > 0:
    for i in 0'i32 ..< n:
      if pointInRect(screenToVirtualLocal(getTouchPosition(i)), r):
        return true
    return false
  isMouseButtonDown(MouseButton.Left) and
    pointInRect(screenToVirtualLocal(getMousePosition()), r)

proc vkUpdateTouchKeys(): bool =
  ## Fire a key for every finger that went down on the panel this frame, and
  ## return whether the touch API reported any points at all -- which is how the
  ## mouse path knows to stand down. On Android each finger arrives here with
  ## its own stable id, so two-thumb typing works; desktop GLFW never fills the
  ## touch array (`pointCount` stays 0 there), so this returns false and the
  ## mouse press edge remains the only source, keeping `-d:mobile` on desktop a
  ## faithful single-finger simulator.
  let n = getTouchPointCount()
  var live: seq[int32] = @[]
  for i in 0'i32 ..< n:
    let id = getTouchPointId(i)
    live.add id
    var isNew = true
    for prev in vkTouchIds:
      if prev == id:
        isNew = false
        break
    # Fingers already down when the keyboard opened are not fresh presses.
    if isNew and vkActive:
      let p = screenToVirtualLocal(getTouchPosition(i))
      if p.y >= vkOverlayTop:
        vkHitKey(p)
  vkTouchIds = live
  n > 0

proc drawVirtualKeyboard*() =
  ## Draw inside the virtual-canvas pass, above the window layer.
  if vkChipVisible:
    let c = vkChipRect()
    drawRectangleRounded(c, 0.35, 8, Color(r: 40, g: 46, b: 66, a: 190))
    drawRectangleRoundedLines(c, 0.35, 8, 2.0, Color(r: 180, g: 200, b: 255, a: 210))
    # A keyboard glyph: three rows of keys, drawn rather than written so it
    # needs no localization (same reasoning as the back chevron).
    let gx = c.x + 22
    let gy = c.y + 16
    for row in 0 ..< 3:
      for col in 0 ..< 5:
        drawRectangle(Rectangle(x: gx + col.float32 * 14, y: gy + row.float32 * 10,
                                width: 10, height: 7), White)
    drawRectangle(Rectangle(x: gx + 14, y: gy + 30, width: 38, height: 7), White)
  if not vkActive: return
  let rows = vkRows()
  let panel = vkPanelRect(rows)
  if vkHasPreview:
    # Echo of the focused field, so a field hidden behind the panel is still
    # readable. Right-aligned once the text outgrows the strip, which keeps the
    # caret -- the end you are typing at -- on screen.
    let strip = Rectangle(x: 0, y: panel.y - VkPreviewH,
                          width: vp.virtualW, height: VkPreviewH)
    drawRectangle(strip, Color(r: 10, g: 14, b: 22, a: 240))
    const previewSize = 22'i32
    let textW = measureText(vkPreview, previewSize).float32
    let avail = vp.virtualW - 32
    let tx = if textW > avail: 16 - (textW - avail) else: 16.0'f32
    let ty = strip.y + (VkPreviewH - previewSize.float32) / 2
    drawText(vkPreview, tx.int32, ty.int32, previewSize,
             Color(r: 220, g: 235, b: 255, a: 255))
    drawRectangle(Rectangle(x: tx + textW + 3, y: ty, width: 3,
                            height: previewSize.float32),
                  Color(r: 0, g: 210, b: 255, a: 255))
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
  vkChipVisible = vkRequested and vkDismissed
  if not vkRequested:
    # Focus lost (or never taken): re-arm, so the next field to take focus gets
    # a keyboard even if the previous one was closed with "done".
    vkDismissed = false
  vkRequested = false
  vkPreview = vkPreviewNext
  vkHasPreview = vkHasPreviewNext
  vkPreviewNext = ""
  vkHasPreviewNext = false
  if vkActive:
    vkOverlayTop = vkPanelRect(vkRows()).y
    if vkHasPreview:
      # The strip is opaque too, so it occludes -- and consumes -- like the panel.
      vkOverlayTop -= VkPreviewH
  else:
    vkOverlayTop = 1e9
    vkShift = false
    vkBackDown = false
    vkChars.setLen(0)
    # Edges must not survive the panel that produced them, or a stale ENTER
    # lands in whatever field takes focus next.
    vkBackQueued = false
    vkEnterQueued = false

  # Per-finger key presses (Android). Runs unconditionally so the id set stays
  # current even while the keyboard is hidden; it only fires keys when active.
  let touchDrivesKeys = vkUpdateTouchKeys()

  let down = isMouseButtonDown(MouseButton.Left)
  let cur = screenToVirtualLocal(getMousePosition())
  if cur.y < vkOverlayTop and not (vkChipVisible and pointInRect(cur, vkChipRect())):
    lastPointerOffKeyboard = cur

  # Backspace auto-repeat, only while a pointer is still on the key itself. Held
  # against `down` alone it kept firing after the finger slid off, which on a
  # phone is most of the way to wiping the field.
  if vkActive and vkBackDown and anyPointerInRect(vkBackKeyRect):
    vkBackHeldTime += dt
    if vkBackHeldTime >= VkBackRepeatDelay:
      vkBackQueued = true
      vkBackHeldTime = VkBackRepeatDelay - VkBackRepeatRate
  else:
    vkBackDown = false
    vkBackHeldTime = 0

  if down and not pointerWasDown:
    # Touch down: a new gesture cancels any glide still running.
    gestureStart = cur
    gesturePrev = cur
    gestureIsDrag = false
    flickVelocity = 0
    scrollAccum = 0
    # Keys fire on press, not release: a keyboard has to feel immediate, and it
    # is the one surface where a press can't be meant as the start of a scroll.
    gestureOnKeyboard = false
    if vkChipVisible and pointInRect(cur, vkChipRect()):
      vkDismissed = false
      gestureOnKeyboard = true
    elif vkActive and cur.y >= vkOverlayTop:
      gestureOnKeyboard = true
      if not touchDrivesKeys:
        vkHitKey(cur)
    keyboardOwnsPointer = gestureOnKeyboard
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
    # Idle: glide. The keyboard's claim on the pointer outlives the gesture by
    # exactly one frame (the release frame above), and is dropped here.
    keyboardOwnsPointer = false
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

proc touchKeyboardOwnsPointer*(): bool =
  ## True for every frame of a gesture that started on the keyboard overlay,
  ## including its release frame. The pointer wrappers suppress press/down/
  ## release for these, so tapping a key can't also grab a window title bar, a
  ## scrollbar thumb or a slider that happens to sit under the panel.
  keyboardOwnsPointer

proc touchKeyboardMaskPointer*(raw: Vector2): Vector2 =
  ## Report the last position that wasn't on the keyboard, in place of one that
  ## is. This is what keeps a field alive while you type into it: the menu layer
  ## decides "is this window topmost / was this click mine" from the pointer
  ## POSITION (isWindowTopmostAtPoint), and on touch the pointer is wherever the
  ## last finger landed. Unmasked, the first key tap moves the pointer onto the
  ## panel, the owning window stops being topmost, its input block stops running
  ## -- so it stops calling setTextInputActive -- and the keyboard vanishes one
  ## frame later with the keystroke still queued. Masking makes the whole menu
  ## layer see a pointer that never left the field.
  if raw.y >= vkOverlayTop or (vkChipVisible and pointInRect(raw, vkChipRect())):
    lastPointerOffKeyboard
  else:
    raw

proc touchBackPressed*(): bool =
  ## The on-screen back chip was tapped, or the hardware back key fired.
  ## raylib's Android backend may consume AKEYCODE_BACK before it reaches the
  ## key state, which is exactly why the on-screen chip is the primary path and
  ## the key is only an additional one.
  backTapped or isKeyPressed(KeyboardKey.Back)
