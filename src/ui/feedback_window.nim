## OS-Themed Feedback / Bug Report Window (FEEDBACK.exe)
##
## A small form: pick a kind (bug / idea / other), type a title and details,
## optionally attach system info, then send it as a pre-filled GitHub issue,
## copy it, or save it to a file. The report building and delivery live in
## src/feedback.nim; this module is only the form.
##
## Text entry is deliberately simple: the caret always sits at the end of the
## active field (append, backspace, paste). While a field is active the window
## claims the keyboard through `wantsTextInput`, so typing "e" or pressing
## Enter can never also drive the desktop's icon navigation behind it.

import raylib, std/[unicode, strutils, math]
import os_window, ui_helpers, ../localization, ../render_context, ../feedback

type
  FeedbackField = enum
    ffNone
    ffTitle
    ffDetails

  FeedbackWindow* = ref object
    window*: OSWindow
    kind: FeedbackKind
    title: string
    details: string
    includeInfo: bool
    active: FeedbackField
    caretBlink: float32
    backspaceHeld: float32
    status: string
    statusOk: bool
    statusTimer: float32
    hover: int   ## hovered control id (see the Hover* consts), -1 when none

  FeedbackLayout = object
    intro: Rectangle
    kinds: array[FeedbackKind, Rectangle]
    titleLabelY: float32
    titleField: Rectangle
    detailsLabelY: float32
    detailsField: Rectangle
    checkbox: Rectangle     ## the whole clickable row, box + label
    send, copy, save: Rectangle
    statusY: float32
    note: Rectangle

const
  FEEDBACK_WINDOW_WIDTH = 580
  FEEDBACK_WINDOW_HEIGHT = 548
  FIELD_FONT = 15'i32
  DETAILS_LINE_HEIGHT = 18
  STATUS_SECONDS = 6.0'f32

  # Hover ids: 0..2 are the kind pills (FeedbackKind ordinals).
  HoverCheckbox = 10
  HoverSend = 11
  HoverCopy = 12
  HoverSave = 13

  ColAccent = Color(r: 255, g: 130, b: 90, a: 255)
  ColTitle = Color(r: 235, g: 245, b: 255, a: 255)
  ColBody = Color(r: 205, g: 212, b: 222, a: 255)
  ColMuted = Color(r: 150, g: 160, b: 175, a: 255)
  ColHint = Color(r: 110, g: 120, b: 135, a: 255)
  ColPanelBg = Color(r: 10, g: 12, b: 18, a: 255)
  ColFieldBg = Color(r: 18, g: 22, b: 32, a: 255)
  ColOk = Color(r: 120, g: 230, b: 150, a: 255)
  ColWarn = Color(r: 255, g: 190, b: 90, a: 255)

proc kindColor(kind: FeedbackKind): Color =
  case kind
  of fkBug: Color(r: 255, g: 95, b: 95, a: 255)
  of fkIdea: Color(r: 255, g: 210, b: 80, a: 255)
  of fkOther: Color(r: 100, g: 190, b: 255, a: 255)

proc kindName(kind: FeedbackKind): string =
  case kind
  of fkBug: t(tkFeedbackKindBug)
  of fkIdea: t(tkFeedbackKindIdea)
  of fkOther: t(tkFeedbackKindOther)

proc kindHint(kind: FeedbackKind): string =
  case kind
  of fkBug: t(tkFeedbackHintBug)
  of fkIdea: t(tkFeedbackHintIdea)
  of fkOther: t(tkFeedbackHintOther)

proc newFeedbackWindow*(screenWidth, screenHeight: int): FeedbackWindow =
  let osWin = newOSWindow(
    t(tkFeedbackWindowTitle),
    (screenWidth - FEEDBACK_WINDOW_WIDTH) div 2,
    (screenHeight - FEEDBACK_WINDOW_HEIGHT) div 2,
    FEEDBACK_WINDOW_WIDTH, FEEDBACK_WINDOW_HEIGHT,
    ColAccent,
    owtHelp,
    resizable = false
  )
  FeedbackWindow(window: osWin, kind: fkBug, includeInfo: true,
                 active: ffTitle, hover: -1)

proc resetFeedbackView*(fw: FeedbackWindow) =
  ## Called on every open. The draft survives closing the window (Esc must not
  ## eat a half-written report); only focus and the stale status reset. The
  ## title is re-read so a language switch since startup shows up here too.
  fw.window.title = t(tkFeedbackWindowTitle)
  fw.active = if fw.title.len == 0: ffTitle else: ffDetails
  fw.status = ""
  fw.statusTimer = 0
  fw.backspaceHeld = 0

proc wantsTextInput*(fw: FeedbackWindow): bool =
  ## True while keystrokes belong to one of this window's fields.
  fw.window.visible and fw.window.focused and not fw.window.minimized and
    fw.active != ffNone

proc layout(fw: FeedbackWindow): FeedbackLayout =
  ## The single source of the form's geometry, for hit-testing and drawing.
  let x = (fw.window.x + WINDOW_PADDING + 18).float32
  let w = (fw.window.width - WINDOW_PADDING * 2 - 36).float32
  var y = (fw.window.y + TITLE_BAR_HEIGHT + WINDOW_PADDING + 14).float32

  result.intro = Rectangle(x: x, y: y, width: w, height: 34)
  y += 44

  let pillW = 104'f32
  for k in FeedbackKind:
    result.kinds[k] = Rectangle(x: x + k.ord.float32 * (pillW + 10), y: y,
                                width: pillW, height: 28)
  y += 42

  result.titleLabelY = y
  result.titleField = Rectangle(x: x, y: y + 19, width: w, height: 30)
  y += 62

  result.detailsLabelY = y
  result.detailsField = Rectangle(x: x, y: y + 19, width: w, height: 170)
  y += 200

  result.checkbox = Rectangle(x: x, y: y, width: w, height: 20)
  y += 34

  let gap = 12'f32
  let btnW = (w - gap * 2) / 3
  result.send = Rectangle(x: x, y: y, width: btnW, height: 34)
  result.copy = Rectangle(x: x + btnW + gap, y: y, width: btnW, height: 34)
  result.save = Rectangle(x: x + (btnW + gap) * 2, y: y, width: btnW, height: 34)
  y += 46

  result.statusY = y
  y += 24
  result.note = Rectangle(x: x, y: y, width: w, height: 30)

# ---------------------------------------------------------------------------
# Text editing
# ---------------------------------------------------------------------------

proc fieldText(fw: FeedbackWindow): string =
  if fw.active == ffTitle: fw.title else: fw.details

proc setFieldText(fw: FeedbackWindow, s: string) =
  if fw.active == ffTitle: fw.title = s
  elif fw.active == ffDetails: fw.details = s

proc fieldCap(field: FeedbackField): int =
  if field == ffTitle: FeedbackTitleMaxLen else: FeedbackBodyMaxLen

proc acceptRune(r: Rune, field: FeedbackField): string =
  ## What `r` becomes in `field`, or "" to drop it. The UI font stops at U+00FF,
  ## so anything past Latin-1 would render as boxes and is refused up front.
  let c = r.int
  if c == '\n'.ord:
    return if field == ffDetails: "\n" else: " "
  if c == '\t'.ord:
    return " "
  if c < 32 or c == 127 or c > 0xFF:
    return ""
  r.toUTF8

proc insertText(fw: FeedbackWindow, text: string) =
  if fw.active == ffNone:
    return
  let cap = fieldCap(fw.active)
  var s = fw.fieldText
  var count = s.runeLen
  for r in text.runes:
    if count >= cap:
      break
    if r.int == '\r'.ord:
      continue
    let piece = acceptRune(r, fw.active)
    if piece.len > 0:
      s.add(piece)
      inc count
  fw.setFieldText(s)

proc deleteLastRune(s: var string) =
  if s.len > 0:
    var i = s.high
    while i > 0 and (s[i].uint8 and 0xC0) == 0x80:  # step back over continuation bytes
      dec i
    s.setLen(i)

proc deleteLastWord(s: var string) =
  ## Ctrl+Backspace: trailing whitespace, then the word before it.
  while s.len > 0 and s[^1] in Whitespace:
    s.setLen(s.len - 1)
  while s.len > 0 and s[^1] notin Whitespace:
    deleteLastRune(s)

proc handleTyping(fw: FeedbackWindow, dt: float32) =
  let ctrl = isKeyDown(LeftControl) or isKeyDown(RightControl) or
             isKeyDown(LeftSuper) or isKeyDown(RightSuper)

  if isKeyPressed(Tab):
    fw.active = if fw.active == ffTitle: ffDetails else: ffTitle
    # getCharPressed does not queue Tab, so nothing to drain here.
    return

  if ctrl and isKeyPressed(V):
    try:
      fw.insertText($getClipboardText())
    except CatchableError:
      discard

  var key = getCharPressed()
  while key > 0:
    if not ctrl:
      fw.insertText(Rune(key).toUTF8)
    key = getCharPressed()

  if isKeyPressed(Enter) or isKeyPressed(KpEnter):
    if fw.active == ffTitle:
      fw.active = ffDetails
    else:
      fw.insertText("\n")

  # Backspace: one on press, then auto-repeat after a short hold.
  var deletes = 0
  if isKeyPressed(Backspace):
    deletes = 1
    fw.backspaceHeld = 0
  elif isKeyDown(Backspace):
    fw.backspaceHeld += dt
    if fw.backspaceHeld >= 0.4'f32:
      deletes = 1
      fw.backspaceHeld -= 0.035'f32
  else:
    fw.backspaceHeld = 0
  if deletes > 0:
    var s = fw.fieldText
    if ctrl: deleteLastWord(s) else: deleteLastRune(s)
    fw.setFieldText(s)

# ---------------------------------------------------------------------------
# Update
# ---------------------------------------------------------------------------

proc setStatus(fw: FeedbackWindow, text: string, ok: bool) =
  fw.status = text
  fw.statusOk = ok
  fw.statusTimer = STATUS_SECONDS

proc runAction(fw: FeedbackWindow, id: int) =
  if not hasContent(fw.title, fw.details):
    fw.setStatus(t(tkFeedbackStatusEmpty), false)
    fw.active = if fw.title.strip().len == 0: ffTitle else: ffDetails
    return
  case id
  of HoverSend:
    case sendToGitHub(fw.kind, fw.title, fw.details, fw.includeInfo)
    of srOpened: fw.setStatus(t(tkFeedbackStatusOpened), true)
    of srTruncated: fw.setStatus(t(tkFeedbackStatusTruncated), false)
  of HoverCopy:
    copyReport(fw.kind, fw.title, fw.details, fw.includeInfo)
    fw.setStatus(t(tkFeedbackStatusCopied), true)
  of HoverSave:
    let path = saveReport(fw.kind, fw.title, fw.details, fw.includeInfo)
    if path.len > 0:
      fw.setStatus(t(tkFeedbackStatusSaved).replace("$1", path), true)
    else:
      fw.setStatus(t(tkFeedbackStatusSaveFailed), false)
  else: discard

proc updateFeedbackWindow*(fw: FeedbackWindow, dt: float32,
                           screenWidth, screenHeight: int,
                           allWindows: openArray[OSWindow]) =
  updateOSWindow(fw.window, dt)
  if not fw.window.visible:
    return

  if handleOSWindowInput(fw.window, screenWidth, screenHeight, allWindows):
    fw.window.visible = false
    return

  fw.caretBlink += dt
  if fw.statusTimer > 0:
    fw.statusTimer -= dt

  fw.hover = -1
  if fw.window.minimized or not fw.window.focused:
    return

  let lo = layout(fw)
  let mp = getVirtualMousePosition()
  for k in FeedbackKind:
    if checkCollisionPointRec(mp, lo.kinds[k]): fw.hover = k.ord
  if checkCollisionPointRec(mp, lo.checkbox): fw.hover = HoverCheckbox
  if checkCollisionPointRec(mp, lo.send): fw.hover = HoverSend
  if checkCollisionPointRec(mp, lo.copy): fw.hover = HoverCopy
  if checkCollisionPointRec(mp, lo.save): fw.hover = HoverSave

  if isPointerPressed() and not fw.window.dragging:
    if checkCollisionPointRec(mp, lo.titleField):
      fw.active = ffTitle
      fw.caretBlink = 0
    elif checkCollisionPointRec(mp, lo.detailsField):
      fw.active = ffDetails
      fw.caretBlink = 0
    elif fw.hover in 0 .. FeedbackKind.high.ord:
      fw.kind = FeedbackKind(fw.hover)
    elif fw.hover == HoverCheckbox:
      fw.includeInfo = not fw.includeInfo
    elif fw.hover in [HoverSend, HoverCopy, HoverSave]:
      fw.runAction(fw.hover)
    else:
      # A click on empty window space hands the keyboard back to the desktop.
      let body = Rectangle(x: fw.window.x.float32,
                           y: (fw.window.y + TITLE_BAR_HEIGHT).float32,
                           width: fw.window.width.float32,
                           height: (fw.window.height - TITLE_BAR_HEIGHT).float32)
      if checkCollisionPointRec(mp, body):
        fw.active = ffNone

  if fw.active != ffNone:
    fw.handleTyping(dt)

# ---------------------------------------------------------------------------
# Draw
# ---------------------------------------------------------------------------

proc textW(s: string, size: int32): int32 =
  ## Width of `s` including trailing spaces, which measureText drops in this
  ## font -- the caret has to move when you type a space.
  if s.len == 0: 0'i32
  else: measureText(s & "a", size) - measureText("a", size)

proc wrapField(text: string, maxWidth, size: int32): seq[string] =
  ## Wrap typed text for display: hard newlines kept, soft breaks after the last
  ## space that fits, and a single over-long word broken wherever it overflows.
  ## Spaces are preserved so the caret lands where the next character will.
  for para in text.split('\n'):
    var line = ""
    for r in para.runes:
      let next = line & r.toUTF8
      if line.len > 0 and textW(next, size) > maxWidth:
        let cut = line.rfind(' ')
        if cut >= 0 and cut < line.high:
          result.add(line[0 .. cut])
          line = line[cut + 1 .. ^1] & r.toUTF8
        else:
          result.add(line)
          line = r.toUTF8
      else:
        line = next
    result.add(line)

proc drawField(r: Rectangle, active: bool, accent: Color) =
  drawRectangle(r.x.int32, r.y.int32, r.width.int32, r.height.int32, ColFieldBg)
  drawRectangleLines(r, (if active: 2.0 else: 1.0),
                     if active: accent else: Color(r: 70, g: 80, b: 100, a: 255))

proc drawButton(r: Rectangle, label: string, fill: Color, hovered: bool) =
  let f = if hovered:
      Color(r: min(255, fill.r.int + 28).uint8, g: min(255, fill.g.int + 28).uint8,
            b: min(255, fill.b.int + 28).uint8, a: 255)
    else: fill
  drawRectangle(r.x.int32, r.y.int32, r.width.int32, r.height.int32, f)
  drawRectangleLines(r, (if hovered: 2.0 else: 1.0),
                     Color(r: 255, g: 255, b: 255, a: if hovered: 210 else: 90))
  drawCenteredTextFit(label, r.x.int32 + 5, r.y.int32 + (r.height.int32 - 15) div 2,
                      r.width.int32 - 10, 15, White)

proc drawFeedbackWindow*(fw: FeedbackWindow) =
  if not fw.window.visible:
    return

  drawWindowChrome(fw.window)
  if fw.window.minimized:
    return

  let cx = fw.window.x + WINDOW_PADDING
  let cy = fw.window.y + TITLE_BAR_HEIGHT + WINDOW_PADDING
  let cw = fw.window.width - WINDOW_PADDING * 2
  let ch = fw.window.height - TITLE_BAR_HEIGHT - WINDOW_PADDING * 2
  drawRectangle(cx.int32, cy.int32, cw.int32, ch.int32, ColPanelBg)
  drawRectangleLines(Rectangle(x: cx.float32, y: cy.float32,
                               width: cw.float32, height: ch.float32),
                     1, Color(r: ColAccent.r, g: ColAccent.g, b: ColAccent.b, a: 200))

  let lo = layout(fw)
  let caretOn = fw.window.focused and (fw.caretBlink mod 1.0'f32) < 0.55'f32
  let accent = kindColor(fw.kind)

  # --- Intro ---
  let introSize = bestWrapFontSize(t(tkFeedbackIntro), lo.intro.width.int32, 14, 2)
  var ly = lo.intro.y.int32
  for line in wrapTextLines(t(tkFeedbackIntro), lo.intro.width.int32, introSize):
    drawText(line, lo.intro.x.int32, ly, introSize, ColBody)
    ly += introSize + 3

  # --- Kind pills ---
  for k in FeedbackKind:
    let r = lo.kinds[k]
    let col = kindColor(k)
    let selected = fw.kind == k
    let bg = if selected: Color(r: col.r div 3, g: col.g div 3, b: col.b div 3, a: 255)
             elif fw.hover == k.ord: Color(r: 30, g: 36, b: 50, a: 255)
             else: ColFieldBg
    drawRectangle(r.x.int32, r.y.int32, r.width.int32, r.height.int32, bg)
    drawRectangleLines(r, (if selected: 2.0 else: 1.0),
                       if selected: col else: Color(r: 70, g: 80, b: 100, a: 255))
    drawCircle(Vector2(x: r.x + 14, y: r.y + r.height / 2), 4.5, col)
    drawTextFit(kindName(k), r.x.int32 + 25, r.y.int32 + 7, r.width.int32 - 30, 14,
                if selected: ColTitle else: ColMuted)

  # --- Title field ---
  drawText(t(tkFeedbackTitleLabel), lo.titleField.x.int32, lo.titleLabelY.int32, 14, accent)
  let tf = lo.titleField
  drawField(tf, fw.active == ffTitle, accent)
  let innerW = tf.width.int32 - 16
  if fw.title.len == 0:
    # Hint sits past the caret slot so the two never overlap.
    drawTextFit(t(tkFeedbackTitleHint), tf.x.int32 + 16, tf.y.int32 + 8, innerW - 8,
                FIELD_FONT, ColHint)
  # Show the tail when the title outgrows the box; the caret is always there.
  var shown = fw.title
  while shown.len > 0 and textW(shown, FIELD_FONT) > innerW - 4:
    shown = shown.runeSubStr(1)
  drawText(shown, tf.x.int32 + 8, tf.y.int32 + 8, FIELD_FONT, ColTitle)
  if fw.active == ffTitle and caretOn:
    let caretX = tf.x.int32 + 8 + textW(shown, FIELD_FONT) + 1
    drawRectangle(caretX, tf.y.int32 + 6, 2, 18, ColTitle)

  # --- Details field ---
  drawText(t(tkFeedbackDetailsLabel), lo.detailsField.x.int32, lo.detailsLabelY.int32,
           14, accent)
  let df = lo.detailsField
  drawField(df, fw.active == ffDetails, accent)
  let dInnerW = df.width.int32 - 16
  let counter = $fw.details.runeLen & "/" & $FeedbackBodyMaxLen
  drawText(counter, df.x.int32 + df.width.int32 - measureText(counter, 11) - 6,
           df.y.int32 + df.height.int32 - 15, 11, ColHint)
  if fw.details.len == 0:
    for i, line in wrapTextLines(kindHint(fw.kind), dInnerW - 10, 14):
      drawText(line, df.x.int32 + 16, df.y.int32 + 8 + (i * 18).int32, 14, ColHint)
    if fw.active == ffDetails and caretOn:
      drawRectangle(df.x.int32 + 8, df.y.int32 + 6, 2, 18, ColTitle)
  else:
    # The caret lives at the end, so keep the newest lines in view.
    let lines = wrapField(fw.details, dInnerW, FIELD_FONT)
    let maxVisible = (df.height.int - 24) div DETAILS_LINE_HEIGHT
    let first = max(0, lines.len - maxVisible)
    var yy = df.y.int32 + 8
    for i in first ..< lines.len:
      drawText(lines[i], df.x.int32 + 8, yy, FIELD_FONT, ColTitle)
      if i == lines.high and fw.active == ffDetails and caretOn:
        drawRectangle(df.x.int32 + 8 + textW(lines[i], FIELD_FONT) + 1, yy - 2, 2, 18,
                      ColTitle)
      yy += DETAILS_LINE_HEIGHT

  # --- System info checkbox ---
  let cb = lo.checkbox
  let box = Rectangle(x: cb.x, y: cb.y + 1, width: 18, height: 18)
  drawRectangle(box.x.int32, box.y.int32, 18, 18, ColFieldBg)
  drawRectangleLines(box, (if fw.hover == HoverCheckbox: 2.0 else: 1.0), accent)
  if fw.includeInfo:
    drawLine(Vector2(x: box.x + 4, y: box.y + 9), Vector2(x: box.x + 8, y: box.y + 13), 2.5, ColOk)
    drawLine(Vector2(x: box.x + 8, y: box.y + 13), Vector2(x: box.x + 14, y: box.y + 4), 2.5, ColOk)
  drawTextFit(t(tkFeedbackAttachInfo), cb.x.int32 + 28, cb.y.int32 + 3,
              cb.width.int32 - 28, 14, ColBody)

  # --- Actions ---
  drawButton(lo.send, t(tkFeedbackSend), Color(r: 46, g: 120, b: 70, a: 255),
             fw.hover == HoverSend)
  drawButton(lo.copy, t(tkFeedbackCopy), Color(r: 40, g: 64, b: 104, a: 255),
             fw.hover == HoverCopy)
  drawButton(lo.save, t(tkFeedbackSave), Color(r: 40, g: 64, b: 104, a: 255),
             fw.hover == HoverSave)

  # --- Status + note ---
  if fw.statusTimer > 0 and fw.status.len > 0:
    let a = uint8(255.0'f32 * min(1.0'f32, fw.statusTimer))
    let base = if fw.statusOk: ColOk else: ColWarn
    drawTextFit(fw.status, lo.note.x.int32, lo.statusY.int32, lo.note.width.int32, 14,
                Color(r: base.r, g: base.g, b: base.b, a: a))

  let noteSize = bestWrapFontSize(t(tkFeedbackNote), lo.note.width.int32, 12, 2)
  var ny = lo.note.y.int32
  for line in wrapTextLines(t(tkFeedbackNote), lo.note.width.int32, noteSize):
    drawText(line, lo.note.x.int32, ny, noteSize, ColMuted)
    ny += noteSize + 3

  drawResizeIndicator(fw.window)
