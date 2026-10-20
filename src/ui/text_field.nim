## Text fields: the one editor behind every box the player types in (the
## MODS.EXE Console, HELP's terminal, the feedback form, the shop's search, the
## FPS limit and the PvP lobby's nickname / IP / port).
##
## A TextField holds the text, the caret and the selection. updateTextField
## edits it the way a desktop text box does, and drawTextField draws the text,
## the selection and the caret inside the box the window paints (each window
## keeps its own frame and placeholder). What it takes:
##   Left / Right, Home / End (Ctrl: a word / the whole text), Up / Down and
##   PageUp / PageDown in a multi-line field; Shift with any of them selects.
##   Backspace / Delete (Ctrl: a word), Ctrl+A, Ctrl+C / X / V (and Ctrl+Insert,
##   Shift+Delete, Shift+Insert), Ctrl+Z / Ctrl+Y (or Ctrl+Shift+Z).
##   A click places the caret, a drag or Shift+click selects, a double click
##   takes a word and a triple click everything (a paragraph, in a multi-line
##   field); the wheel scrolls a multi-line field.
## Enter submits a single-line field (with `keepHistory`, Up / Down then go
## through the lines submitted before); a multi-line one takes it as a newline.
## Held keys repeat at the OS's rate (isKeyPressedRepeat).
##
## Only characters the UI font draws are taken (U+0020..U+00FF, without the C1
## controls), stored as UTF-8; the caret and the selection are byte indices that
## always sit on a character boundary. Ctrl shortcuts never fire with Alt held:
## Windows reports AltGr as Ctrl+Alt, and it types @ [ ] { } on many layouts.
##
## A window passes `active` (hasKeyboard: visible, restored and focused), so a
## backgrounded window never takes keystrokes or clicks. By the time a window
## updates, handleWindowClick has already focused whichever window a press
## landed on, so `active` also says the press is this window's.
##
## On -d:mobile the focused field also raises the on-screen keyboard (numeric
## when the field only takes digits and '.') and echoes its text above it, since
## the panel can cover the box; its keys arrive through gamepad_input's poll*
## shims, OR-ed with the physical keyboard.

import raylib, std/[strutils, math]
from std/unicode import Rune, runes, toUTF8
import ../modding/mod_patch_core
import ../render_context, ../utils
import os_window, ui_helpers, ui_theme

type
  TextFieldStyle* = object
    ## How a field lays out and draws. The colours are stock values:
    ## drawTextField puts them through the interface theme.
    fontSize*: int32
    padX*, padY*: int32    ## the text's inset in the box (padY: multi-line only, a line is centred)
    lineHeight*: int32     ## a multi-line field's rows (0 = fontSize + 3)
    caretWidth*: int32
    ink*: Color            ## the text
    caretInk*: Color
    selectInk*: Color      ## the selection's highlight (translucent)
    align*: TextAlign      ## where single-line text that fits sits

  TextFieldInput* = object
    ## What a frame of updateTextField did besides editing.
    clicked*: bool         ## a press landed in the box (the field took the focus)
    submitted*: bool       ## Enter, in a single-line field
    changed*: bool         ## the text changed

  TextUndo = object
    text: string
    caret, anchor: int

  EditKind = enum
    ekNone, ekType, ekDelete

  TextField* = ref object
    text*: string          ## UTF-8, only characters the font draws
    caret*: int            ## byte index of the caret
    anchor*: int           ## the selection's other end (== caret: nothing selected)
    focused*: bool         ## the field its window's keystrokes go to
    maxChars*: int         ## character cap, 0 = none
    allowed*: set[char]    ## the ASCII the field takes; {} = every character the font draws
    multiline*: bool
    keepHistory*: bool     ## Up / Down recall submitted lines (single-line fields)
    history*: seq[string]  ## submitted lines, oldest first
    style*: TextFieldStyle
    blink*: float32        ## the caret's phase: 0 after an edit or a move, so it shows while typing
    scrollX: float32       ## single-line: px the text is scrolled left
    scrollLine: int        ## multi-line: the first row shown
    reveal: bool           ## scroll the caret into view on the next draw
    edited: bool           ## the text changed this frame
    dragging: bool
    clickAt: float64       ## when the last press was (double and triple clicks)
    clickPos: Vector2
    clicks: int
    goalX: float32         ## the column Up / Down keep (-1: take the caret's)
    undo, redo: seq[TextUndo]
    lastEdit: EditKind     ## a run of typing (or of deleting) is one undo step
    historyAt: int         ## the history entry shown (history.len: the line being typed)
    draft: string          ## that line, while Up / Down show older ones

  Row = tuple[a, b: int]   ## one shown row: a byte range of the text

const
  UndoDepth = 200
  HistoryDepth = 200
  MultiClickSeconds = 0.4
  CaretOnPart = 0.55'f32   ## of each second, the part the caret shows

proc fieldStyle*(fontSize: int32, ink: Color, accent: Color, padX: int32 = 8,
                 align = taLeft): TextFieldStyle {.moddable.} =
  ## The usual style: `ink` text and a 2 px caret of it, and a translucent
  ## `accent` selection (stock colours).
  TextFieldStyle(fontSize: fontSize, padX: padX, caretWidth: 2, ink: ink, caretInk: ink,
                 selectInk: withAlpha(accent, 90), align: align)

# ---------------------------------------------------------------- text ----
proc isCont(c: char): bool {.inline.} = (c.uint8 and 0xC0'u8) == 0x80'u8

proc prevChar(s: string, i: int): int =
  ## The start of the character before byte `i`.
  result = max(0, i - 1)
  while result > 0 and isCont(s[result]): dec result

proc nextChar(s: string, i: int): int =
  ## The byte after the character that starts at `i`.
  result = min(s.len, i + 1)
  while result < s.len and isCont(s[result]): inc result

proc snapToChar(s: string, i: int): int =
  result = clamp(i, 0, s.len)
  while result > 0 and result < s.len and isCont(s[result]): dec result

proc charCount(s: string): int =
  for c in s:
    if not isCont(c): inc result

type CharClass = enum ccSpace, ccWord, ccPunct

proc classAt(s: string, i: int): CharClass =
  ## What Ctrl+arrows and double clicks treat as one word: a run of letters
  ## (accented ones too), digits and _, or a run of other symbols.
  let c = s[i]
  if c in Whitespace: ccSpace
  elif c.uint8 >= 0x80'u8 or c in IdentChars: ccWord
  else: ccPunct

proc wordLeft(s: string, i: int): int =
  ## Ctrl+Left: back over spaces, then over the run before them.
  result = i
  while result > 0 and classAt(s, prevChar(s, result)) == ccSpace: result = prevChar(s, result)
  if result > 0:
    let k = classAt(s, prevChar(s, result))
    while result > 0 and classAt(s, prevChar(s, result)) == k: result = prevChar(s, result)

proc wordRight(s: string, i: int): int =
  ## Ctrl+Right: over the run at the caret, then over the spaces after it.
  result = i
  if result < s.len and classAt(s, result) != ccSpace:
    let k = classAt(s, result)
    while result < s.len and classAt(s, result) == k: result = nextChar(s, result)
  while result < s.len and classAt(s, result) == ccSpace: result = nextChar(s, result)

proc wordAt(s: string, i: int): Row =
  ## The run a double click at `i` selects.
  if s.len == 0: return (0, 0)
  let p = if i >= s.len: prevChar(s, s.len) else: i
  let k = classAt(s, p)
  result = (p, nextChar(s, p))
  while result.a > 0 and classAt(s, prevChar(s, result.a)) == k: result.a = prevChar(s, result.a)
  while result.b < s.len and classAt(s, result.b) == k: result.b = nextChar(s, result.b)

proc advanceOf(s: string, size: int32): float32 =
  ## Where the glyph after `s` starts, from the left of `s` (its width plus the
  ## font's letter spacing, which is what drawText moves on by).
  if s.len == 0: 0'f32
  else: float32(measureText(s & "a", size) - measureText("a", size))

proc hitIndex(s: string, a, b: int, x: float32, size: int32): int =
  ## The character boundary of s[a ..< b] nearest to `x` (from a's left edge).
  var bounds: seq[int]
  var i = a
  while i < b:
    bounds.add i
    i = nextChar(s, i)
  bounds.add b
  var lo = 0
  var hi = bounds.high
  while lo < hi:   # the first boundary at or past x
    let mid = (lo + hi) div 2
    if advanceOf(s[a ..< bounds[mid]], size) < x: lo = mid + 1
    else: hi = mid
  if lo > 0 and x - advanceOf(s[a ..< bounds[lo - 1]], size) <
                advanceOf(s[a ..< bounds[lo]], size) - x:
    dec lo
  bounds[lo]

# ------------------------------------------------------------ geometry ----
proc innerRect(f: TextField, box: Rectangle): Rectangle =
  Rectangle(x: box.x + f.style.padX.float32, y: box.y + f.style.padY.float32,
            width: max(1'f32, box.width - 2 * f.style.padX.float32),
            height: max(1'f32, box.height - 2 * f.style.padY.float32))

proc lineH(f: TextField): float32 =
  float32(if f.style.lineHeight > 0: f.style.lineHeight else: f.style.fontSize + 3)

proc visibleRows(f: TextField, inner: Rectangle): int =
  max(1, int(inner.height / f.lineH))

proc lineTop(f: TextField, box: Rectangle): float32 =
  ## A single line's top: centred in the box.
  floor(box.y + (box.height - f.style.fontSize.float32) / 2)

proc originX(f: TextField, inner: Rectangle, textW: float32): float32 =
  ## Where a single line starts: aligned while it fits, scrolled once it does not.
  let room = inner.width - f.style.caretWidth.float32
  if textW > room: return floor(inner.x - f.scrollX)
  case f.style.align
  of taLeft: inner.x
  of taCenter: floor(inner.x + (room - textW) / 2)
  of taRight: floor(inner.x + room - textW)

proc rowsOf(f: TextField, width: float32): seq[Row] =
  ## The text wrapped to `width`: newlines kept, a row broken after its last
  ## space (which may hang past the edge), and a word longer than a row broken
  ## where it overflows. A single-line field is one row.
  let s = f.text
  if not f.multiline: return @[(0, s.len)]
  let size = f.style.fontSize
  var p = 0
  while true:
    var stop = s.find('\n', p)
    if stop < 0: stop = s.len
    var a = p
    var space = -1   # the row's last space
    var j = p
    while j < stop:
      let k = nextChar(s, j)
      if j > a and s[j] == ' ' and measureText(s[a ..< k], size).float32 > width:
        result.add (a, k)   # a space may hang past the edge: the row ends after it
        a = k
        space = -1
        j = k
        continue
      if j > a and measureText(s[a ..< k], size).float32 > width:
        if space >= a and space + 1 < j:
          result.add (a, space + 1)
          a = space + 1
        if a < j and measureText(s[a ..< k], size).float32 > width:
          result.add (a, j)
          a = j
        space = -1
      if s[j] == ' ': space = j
      j = k
    result.add (a, stop)
    if stop >= s.len: break
    p = stop + 1

proc rowOf(rows: seq[Row], c: int): int =
  ## The row the caret at `c` shows on (where the wrap broke a row, the next one).
  result = rows.high
  while result > 0 and rows[result].a > c: dec result

proc rowEnd(s: string, rows: seq[Row], i: int): int =
  ## The last caret position on row `i`: a row the wrap broke ends before its
  ## last character, since past it the caret shows on the next row.
  if i < rows.high and rows[i + 1].a == rows[i].b and rows[i].b > rows[i].a:
    prevChar(s, rows[i].b)
  else:
    rows[i].b

proc indexAt(f: TextField, box: Rectangle, p: Vector2): int =
  ## The caret position a press at `p` means.
  let inner = f.innerRect(box)
  let size = f.style.fontSize
  if not f.multiline:
    return hitIndex(f.text, 0, f.text.len,
                    p.x - f.originX(inner, advanceOf(f.text, size)), size)
  let rows = f.rowsOf(inner.width)
  let r = clamp(f.scrollLine + int(floor((p.y - inner.y) / f.lineH)), 0, rows.high)
  hitIndex(f.text, rows[r].a, rowEnd(f.text, rows, r), p.x - inner.x, size)

# --------------------------------------------------------------- state ----
proc selRange(f: TextField): Row =
  (min(f.caret, f.anchor), max(f.caret, f.anchor))

proc hasSelection*(f: TextField): bool {.moddable.} =
  not f.isNil and f.caret != f.anchor

proc selectedText*(f: TextField): string {.moddable.} =
  if f.isNil: return
  let (lo, hi) = f.selRange
  f.text[lo ..< hi]

proc settle(f: TextField) =
  ## Keep the caret and the selection on the text (a script may have set it).
  f.caret = snapToChar(f.text, f.caret)
  f.anchor = snapToChar(f.text, f.anchor)

proc place(f: TextField, to: int, extend: bool, keepGoal = false) =
  ## Move the caret (extend: keep the selection's other end where it is).
  f.caret = to
  if not extend: f.anchor = to
  f.blink = 0
  f.reveal = true
  f.lastEdit = ekNone
  if not keepGoal: f.goalX = -1

proc accepted(f: TextField, s: string, room: int): string =
  ## `s` as this field takes it: characters the font draws (and the field
  ## allows), a newline only in a multi-line field (a space elsewhere), tabs as
  ## spaces, at most `room` characters (-1: no limit).
  var n = 0
  for r in s.runes:
    if room >= 0 and n >= room: break
    var c = int(r)
    if c == '\t'.ord or (c == '\n'.ord and not f.multiline): c = ' '.ord
    if c != '\n'.ord and (c < 0x20 or c == 0x7F or (c >= 0x80 and c < 0xA0) or c > 0xFF):
      continue
    if f.allowed != {} and (c >= 0x80 or char(c) notin f.allowed): continue
    result.add Rune(c).toUTF8
    inc n

proc setText*(f: TextField, s: string) {.moddable.} =
  ## Replace the text (as the field takes it), the caret at its end. Undo
  ## starts over.
  if f.isNil: return
  f.text = f.accepted(s, if f.maxChars > 0: f.maxChars else: -1)
  f.undo.setLen(0)
  f.redo.setLen(0)
  f.scrollX = 0
  f.scrollLine = 0
  f.place(f.text.len, extend = false)

proc newTextField*(style: TextFieldStyle, text = "", maxChars = 0, allowed: set[char] = {},
                   multiline = false, keepHistory = false): TextField {.moddable.} =
  result = TextField(style: style, maxChars: maxChars, allowed: allowed, multiline: multiline,
                     keepHistory: keepHistory, goalX: -1)
  result.setText(text)

proc selectAll*(f: TextField) {.moddable.} =
  if f.isNil: return
  f.anchor = 0
  f.place(f.text.len, extend = true)

proc letGo(f: TextField) =
  f.focused = false
  f.dragging = false
  f.anchor = f.caret

proc focusField*(f: TextField, fields: openArray[TextField]) {.moddable.} =
  ## Give `f` its window's keystrokes: every other field of `fields` lets go.
  for g in fields:
    if not g.isNil and g != f: g.letGo()
  if not f.isNil:
    f.focused = true
    f.blink = 0

proc focusNext*(fields: openArray[TextField], backwards = false) {.moddable.} =
  ## Tab (Shift+Tab: backwards): the next field takes the keystrokes, its caret
  ## at the end.
  if fields.len == 0: return
  var at = -1
  for i, g in fields:
    if not g.isNil and g.focused: at = i
  let step = if backwards: fields.len - 1 else: 1
  let next = if at < 0: (if backwards: fields.high else: 0) else: (at + step) mod fields.len
  focusField(fields[next], fields)
  if not fields[next].isNil: fields[next].place(fields[next].text.len, extend = false)

proc remember(f: TextField, kind: EditKind) =
  ## Save what an edit is about to change, for Ctrl+Z. A run of typing (or of
  ## deleting) is a single step.
  if kind == ekNone or kind != f.lastEdit:
    f.undo.add TextUndo(text: f.text, caret: f.caret, anchor: f.anchor)
    if f.undo.len > UndoDepth: f.undo.delete(0)
  f.redo.setLen(0)
  f.lastEdit = kind

proc splice(f: TextField, a, b: int, s: string) =
  f.text = f.text[0 ..< a] & s & f.text[b .. ^1]
  f.caret = a + s.len
  f.anchor = f.caret
  f.blink = 0
  f.reveal = true
  f.goalX = -1
  f.edited = true

proc typeIn(f: TextField, s: string, kind: EditKind) =
  ## `s` at the caret, over the selection, as far as the field takes it.
  let (lo, hi) = f.selRange
  let room = if f.maxChars > 0: max(0, f.maxChars - charCount(f.text) + charCount(f.text[lo ..< hi]))
             else: -1
  let piece = f.accepted(s, room)
  if piece.len == 0: return
  f.remember(if lo < hi: ekNone else: kind)
  f.lastEdit = kind
  f.splice(lo, hi, piece)

proc deleteRange(f: TextField, a, b: int) =
  if a >= b: return
  f.remember(ekDelete)
  f.splice(a, b, "")

proc insertText*(f: TextField, s: string) {.moddable.} =
  ## Type (or paste) `s` at the caret, over the selection.
  if f.isNil: return
  f.settle()
  f.typeIn(s, ekNone)

proc restore(f: TextField, u: TextUndo) =
  f.text = u.text
  f.caret = u.caret
  f.anchor = u.anchor
  f.settle()
  f.lastEdit = ekNone
  f.blink = 0
  f.reveal = true
  f.goalX = -1
  f.edited = true

proc undoEdit(f: TextField) =
  if f.undo.len == 0: return
  f.redo.add TextUndo(text: f.text, caret: f.caret, anchor: f.anchor)
  f.restore(f.undo.pop())

proc redoEdit(f: TextField) =
  if f.redo.len == 0: return
  f.undo.add TextUndo(text: f.text, caret: f.caret, anchor: f.anchor)
  f.restore(f.redo.pop())

proc copySelection(f: TextField) =
  if f.hasSelection: setClipboardText(f.selectedText)

proc cutSelection(f: TextField) =
  if not f.hasSelection: return
  f.copySelection()
  let (lo, hi) = f.selRange
  f.remember(ekNone)
  f.splice(lo, hi, "")

proc recall(f: TextField, dir: int) =
  ## Up / Down: an older (newer) submitted line in place of the one typed.
  f.historyAt = clamp(f.historyAt, 0, f.history.len)
  let at = clamp(f.historyAt + dir, 0, f.history.len)
  if at == f.historyAt: return
  if f.historyAt == f.history.len: f.draft = f.text
  f.historyAt = at
  f.remember(ekNone)
  f.splice(0, f.text.len, if at == f.history.len: f.draft else: f.history[at])

proc submitLine*(f: TextField): string {.moddable.} =
  ## The line Enter submitted. The field empties (and, with keepHistory,
  ## remembers it for Up / Down).
  if f.isNil: return
  result = f.text
  if f.keepHistory and strutils.strip(result).len > 0 and
     (f.history.len == 0 or f.history[^1] != result):
    f.history.add result
    if f.history.len > HistoryDepth: f.history.delete(0)
  f.historyAt = f.history.len
  f.draft = ""
  f.setText("")

proc typingIn*(window: OSWindow, f: TextField): bool {.moddable.} =
  ## Whether keystrokes go to `f` now: it is its window's focused field and the
  ## window has the keyboard.
  not f.isNil and f.focused and hasKeyboard(window)

# -------------------------------------------------------------- update ----
proc movePointer(f: TextField, box: Rectangle, active: bool): bool =
  ## The pointer's part of a frame: true when a press landed in `box`.
  if not active:
    f.dragging = false
    return
  let mouse = getVirtualMousePosition()
  if isPointerPressed():
    f.dragging = false
    if not checkCollisionPointRec(mouse, box): return
    result = true
    f.focused = true
    let now = getTime()
    if now - f.clickAt <= MultiClickSeconds and abs(mouse.x - f.clickPos.x) <= 4 and
       abs(mouse.y - f.clickPos.y) <= 4:
      f.clicks = f.clicks mod 3 + 1
    else:
      f.clicks = 1
    f.clickAt = now
    f.clickPos = mouse
    let at = f.indexAt(box, mouse)
    case f.clicks
    of 2:
      let w = wordAt(f.text, at)
      f.anchor = w.a
      f.place(w.b, extend = true)
    of 3:
      if f.multiline:
        f.anchor = (if at > 0: f.text.rfind('\n', 0, at - 1) + 1 else: 0)
        let stop = f.text.find('\n', at)
        f.place(if stop < 0: f.text.len else: stop, extend = true)
      else:
        f.anchor = 0
        f.place(f.text.len, extend = true)
    else:
      f.place(at, extend = isKeyDown(KeyboardKey.LeftShift) or isKeyDown(KeyboardKey.RightShift))
      f.dragging = true
  elif f.dragging:
    if isPointerDown():
      let at = f.indexAt(box, mouse)
      if at != f.caret: f.place(at, extend = true)
    else:
      f.dragging = false
  if f.multiline and checkCollisionPointRec(mouse, box):
    let wheel = getPointerWheelMove()
    if wheel != 0: f.scrollLine -= int(round(wheel * 3))   # (clamped by the draw)

proc moveRows(f: TextField, box: Rectangle, delta: int, extend: bool) =
  ## Up / Down / PageUp / PageDown in a multi-line field, keeping the column.
  let inner = f.innerRect(box)
  let rows = f.rowsOf(inner.width)
  let r = rowOf(rows, f.caret)
  if f.goalX < 0: f.goalX = advanceOf(f.text[rows[r].a ..< f.caret], f.style.fontSize)
  let t = r + delta
  let to = if t < 0: 0
           elif t > rows.high: f.text.len
           else: hitIndex(f.text, rows[t].a, rowEnd(f.text, rows, t), f.goalX, f.style.fontSize)
  f.place(to, extend, keepGoal = true)

proc raiseKeyboard(f: TextField) =
  ## Ask for the on-screen keyboard this frame (a no-op on desktop). It latches
  ## per frame, so a field nobody is typing in simply does not call this.
  let numeric = f.allowed != {} and f.allowed <= {'0'..'9', '.'} and not f.multiline
  setTextInputActive(true, if numeric: tikNumeric else: tikText)
  setTextInputPreview(f.text)

proc takeKeys(f: TextField, box: Rectangle, dt: float32): TextFieldInput =
  ## The keyboard's part of a frame, for the focused field.
  f.blink += dt
  f.raiseKeyboard()
  let shift = isKeyDown(KeyboardKey.LeftShift) or isKeyDown(KeyboardKey.RightShift)
  let ctrl = isKeyDown(KeyboardKey.LeftControl) or isKeyDown(KeyboardKey.RightControl) or
             isKeyDown(KeyboardKey.LeftSuper) or isKeyDown(KeyboardKey.RightSuper)
  let cmd = ctrl and not (isKeyDown(KeyboardKey.LeftAlt) or isKeyDown(KeyboardKey.RightAlt))
  template hit(k: KeyboardKey): bool = isKeyPressed(k) or isKeyPressedRepeat(k)

  # Typed characters (raylib queues several a frame when typing fast), and the
  # on-screen keyboard's.
  var c = pollCharPressed()
  while c > 0:
    if not cmd: f.typeIn(Rune(c).toUTF8, ekType)
    c = pollCharPressed()

  var cut = false
  if cmd:
    if isKeyPressed(KeyboardKey.A): f.selectAll()
    elif isKeyPressed(KeyboardKey.C) or isKeyPressed(KeyboardKey.Insert): f.copySelection()
    elif isKeyPressed(KeyboardKey.X): f.cutSelection()
    elif hit(KeyboardKey.V): f.typeIn(getClipboardText(), ekNone)
    elif hit(KeyboardKey.Z):
      if shift: f.redoEdit() else: f.undoEdit()
    elif hit(KeyboardKey.Y): f.redoEdit()
  elif shift and hit(KeyboardKey.Insert):
    f.typeIn(getClipboardText(), ekNone)
  elif shift and f.hasSelection and isKeyPressed(KeyboardKey.Delete):
    f.cutSelection()
    cut = true

  let (lo, hi) = f.selRange
  if hit(KeyboardKey.Left):
    if lo < hi and not shift: f.place(lo, extend = false)
    else: f.place(if cmd: wordLeft(f.text, f.caret) else: prevChar(f.text, f.caret), shift)
  elif hit(KeyboardKey.Right):
    if lo < hi and not shift: f.place(hi, extend = false)
    else: f.place(if cmd: wordRight(f.text, f.caret) else: nextChar(f.text, f.caret), shift)
  elif hit(KeyboardKey.Home) or hit(KeyboardKey.End):
    let home = hit(KeyboardKey.Home)
    if f.multiline and not cmd:
      let rows = f.rowsOf(f.innerRect(box).width)
      let r = rowOf(rows, f.caret)
      f.place(if home: rows[r].a else: rowEnd(f.text, rows, r), shift)
    else:
      f.place(if home: 0 else: f.text.len, shift)
  elif f.multiline:
    let page = f.visibleRows(f.innerRect(box))
    if hit(KeyboardKey.Up): f.moveRows(box, -1, shift)
    elif hit(KeyboardKey.Down): f.moveRows(box, 1, shift)
    elif hit(KeyboardKey.PageUp): f.moveRows(box, -page, shift)
    elif hit(KeyboardKey.PageDown): f.moveRows(box, page, shift)
  elif f.keepHistory:
    if hit(KeyboardKey.Up): f.recall(-1)
    elif hit(KeyboardKey.Down): f.recall(1)

  if hit(KeyboardKey.Backspace) or pollBackspacePressed():
    let sel = f.selRange
    if sel.a < sel.b: f.deleteRange(sel.a, sel.b)
    else: f.deleteRange(if cmd: wordLeft(f.text, f.caret) else: prevChar(f.text, f.caret), f.caret)
  elif hit(KeyboardKey.Delete) and not cut:
    let sel = f.selRange
    if sel.a < sel.b: f.deleteRange(sel.a, sel.b)
    else: f.deleteRange(f.caret, if cmd: wordRight(f.text, f.caret) else: nextChar(f.text, f.caret))

  if f.multiline:
    if hit(KeyboardKey.Enter) or hit(KeyboardKey.KpEnter) or pollEnterPressed(): f.typeIn("\n", ekNone)
  elif pollEnterPressed() or isKeyPressed(KeyboardKey.KpEnter):
    result.submitted = true

proc updateTextField*(f: TextField, box: Rectangle, dt: float32,
                      active: bool): TextFieldInput {.moddable.} =
  ## A frame of one field: the pointer in `box` (the box its window paints)
  ## and, while it is focused, the keyboard. `active`: its window has the
  ## keyboard (hasKeyboard); without it the field does nothing.
  if f.isNil: return
  f.settle()
  f.edited = false
  result.clicked = f.movePointer(box, active)
  if active and f.focused:
    let keys = f.takeKeys(box, dt)
    result.submitted = keys.submitted
  result.changed = f.edited

proc updateTextFields*(fields: openArray[TextField], boxes: openArray[Rectangle], dt: float32,
                       active: bool): TextFieldInput {.moddable.} =
  ## A window's fields as one group (boxes[i] is fields[i]'s): a press focuses
  ## the field it lands in and the others let go, Tab / Shift+Tab move between
  ## them, and the keys go to the focused one. Its result, with `clicked` for a
  ## press in any of them.
  let n = min(fields.len, boxes.len)
  var hitAt = -1
  for i in 0 ..< n:
    let f = fields[i]
    if f.isNil: continue
    f.settle()
    f.edited = false
    if f.movePointer(boxes[i], active): hitAt = i
  if hitAt >= 0:
    focusField(fields[hitAt], fields)
    result.clicked = true
  if not active: return
  if isKeyPressed(KeyboardKey.Tab) and n > 0:
    focusNext(toOpenArray(fields, 0, n - 1),
              backwards = isKeyDown(KeyboardKey.LeftShift) or isKeyDown(KeyboardKey.RightShift))
  for i in 0 ..< n:
    let f = fields[i]
    if not f.isNil and f.focused:
      result.submitted = f.takeKeys(boxes[i], dt).submitted
      result.changed = f.edited
      break

# ---------------------------------------------------------------- draw ----
proc beginFieldClip(r: Rectangle): tuple[x, y, w, h: int32, parent: bool] =
  ## Clip to `r` inside whatever clip is already open (raylib's do not nest).
  var x = floor(r.x).int32
  var y = floor(r.y).int32
  var w = ceil(r.width).int32
  var h = ceil(r.height).int32
  if currentVirtualScissorIsActive():
    let p = getCurrentVirtualScissor()
    let ix = max(x, p.x)
    let iy = max(y, p.y)
    w = max(0'i32, min(x + w, p.x + p.w) - ix)
    h = max(0'i32, min(y + h, p.y + p.h) - iy)
    x = ix
    y = iy
    result = (p.x, p.y, p.w, p.h, true)
  beginVirtualScissorMode(x, y, w, h)

proc endFieldClip(clip: tuple[x, y, w, h: int32, parent: bool]) =
  if clip.parent: beginVirtualScissorMode(clip.x, clip.y, clip.w, clip.h)
  else: endVirtualScissorMode()

proc drawTextField*(f: TextField, box: Rectangle, active: bool) {.moddable.} =
  ## The text, the selection and (while `active`, as for updateTextField) the
  ## caret, clipped to `box` less the padding. The window draws the box itself,
  ## and the placeholder of an empty field.
  if f.isNil: return
  f.settle()
  let st = f.style
  let size = st.fontSize
  let inner = f.innerRect(box)
  let (lo, hi) = f.selRange
  let showSel = f.focused and lo < hi
  let caretOn = f.focused and active and f.blink mod 1.0'f32 < CaretOnPart
  let ink = uiInk(st.ink)
  let selInk = uiGlow(st.selectInk)
  let caretInk = uiInk(st.caretInk)
  let cw = st.caretWidth.float32
  let clip = beginFieldClip(Rectangle(x: inner.x - 1, y: box.y, width: inner.width + 2,
                                      height: box.height))
  if not f.multiline:
    let textW = advanceOf(f.text, size)
    let room = inner.width - cw
    if f.reveal:   # the caret in view
      let cx = advanceOf(f.text[0 ..< f.caret], size)
      if cx - f.scrollX > room: f.scrollX = cx - room
      if cx < f.scrollX: f.scrollX = cx
      f.reveal = false
    f.scrollX = clamp(f.scrollX, 0'f32, max(0'f32, textW - room))
    let ox = f.originX(inner, textW)
    let ty = f.lineTop(box)
    if showSel:
      let x0 = ox + advanceOf(f.text[0 ..< lo], size)
      let x1 = ox + advanceOf(f.text[0 ..< hi], size)
      drawRectangle(Rectangle(x: x0, y: ty - 2, width: x1 - x0, height: size.float32 + 4), selInk)
    if f.text.len > 0: drawText(f.text, ox.int32, ty.int32, size, ink)
    if caretOn:
      let cx = ox + advanceOf(f.text[0 ..< f.caret], size)
      drawRectangle(Rectangle(x: cx, y: ty - 2, width: cw, height: size.float32 + 4), caretInk)
  else:
    let rows = f.rowsOf(inner.width)
    let lh = f.lineH
    let shown = f.visibleRows(inner)
    let cr = rowOf(rows, f.caret)
    if f.reveal:
      if cr < f.scrollLine: f.scrollLine = cr
      if cr >= f.scrollLine + shown: f.scrollLine = cr - shown + 1
      f.reveal = false
    f.scrollLine = clamp(f.scrollLine, 0, max(0, rows.len - shown))
    for i in f.scrollLine ..< min(rows.len, f.scrollLine + shown):
      let (a, b) = rows[i]
      let y = floor(inner.y + float32(i - f.scrollLine) * lh)
      if showSel and lo <= b and hi > a:
        let sa = max(lo, a)
        let sb = min(hi, b)
        let x0 = inner.x + advanceOf(f.text[a ..< sa], size)
        var x1 = inner.x + advanceOf(f.text[a ..< sb], size)
        if hi > b and b < f.text.len and f.text[b] == '\n':
          x1 += advanceOf(" ", size)   # the newline is selected too
        if x1 > x0:
          drawRectangle(Rectangle(x: x0, y: y - 2, width: x1 - x0, height: size.float32 + 4), selInk)
      if b > a: drawText(f.text[a ..< b], inner.x.int32, y.int32, size, ink)
      if caretOn and i == cr:
        let cx = inner.x + advanceOf(f.text[a ..< f.caret], size)
        drawRectangle(Rectangle(x: cx, y: y - 2, width: cw, height: size.float32 + 4), caretInk)
  endFieldClip(clip)
