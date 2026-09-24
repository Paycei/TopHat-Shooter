## ORIENTATION.EXE overlay -- everything the tutorial draws (its logic lives in
## ../tutorial.nim):
##   * world cues, in raw virtual space: a "YOU" locator, lock-on brackets on
##     the practice targets, rings on uncollected loot;
##   * inside the HUD's own UI-scale layer: highlights on the status-panel rows
##     the current step talks about (rects published by os_combined_hud, so they
##     can never drift from the real layout) and the instruction card.
##
## Instruction text carries {placeholders} that are swapped for the player's
## live bindings (keyboard or pad, whichever is active) and drawn as keycaps,
## so a rebound control is always taught under its real key.

import raylib, math, strutils
import ../types, ../particle_types, ../tutorial, ../localization, ../settings, ../render_context, ../utils, os_combined_hud

const
  Accent = Color(r: 0, g: 220, b: 255, a: 255)
  DoneColor = Color(r: 90, g: 255, b: 170, a: 255)
  ThreatColor = Color(r: 255, g: 90, b: 90, a: 255)
  CoinColor = Color(r: 255, g: 210, b: 60, a: 255)
  CardBg = Color(r: 8, g: 14, b: 24, a: 228)
  TitleBarBg = Color(r: 0, g: 70, b: 92, a: 235)
  BodyColor = Color(r: 215, g: 230, b: 240, a: 255)
  MutedColor = Color(r: 140, g: 160, b: 180, a: 255)
  KeyBg = Color(r: 24, g: 36, b: 52, a: 245)
  KeyText = Color(r: 235, g: 250, b: 255, a: 255)

  CardMaxWidth = 600'i32
  CardPad = 16'i32
  CardBottomMargin = 46'i32   # clears classic's bottom key hint (vh - 25)
  TitleBarH = 22'i32
  TitleSize = 20'i32
  BodySize = 16'i32
  BodyLineH = 24'i32          # tall enough for a keycap row
  RowSize = 14'i32
  FooterSize = 12'i32
  KeyPadX = 5'i32
  EnterTime = 0.25'f32        # card slide-in per step

proc easeOutCubic(x: float32): float32 =
  let c = clamp(x, 0.0'f32, 1.0'f32)
  1.0'f32 - pow(1.0'f32 - c, 3.0'f32)

# ---------------------------------------------------------------------------
# Binding labels

proc keyName(k: KeyboardKey): string = keyboardKeyLabel(k)

proc cap(label: string): string = "[" & label & "]"

proc bindCap(action: KeyAction): string =
  if isGamepadActive(): cap(gamepadBindLabel(globalSettings.gamepadBinds[action]))
  else: cap(keyName(globalSettings.keybinds[action]))

proc fillBindings(text: string): string =
  let pad = isGamepadActive()
  let kb = globalSettings.keybinds
  let moveCaps =
    if pad: cap(t(tkTutorialKeyLeftStick))
    else: cap(keyName(kb[kaMoveUp])) & " " & cap(keyName(kb[kaMoveLeft])) & " " &
          cap(keyName(kb[kaMoveDown])) & " " & cap(keyName(kb[kaMoveRight]))
  # The left mouse button always fires alongside the rebindable fire key.
  let fireCaps = if pad: bindCap(kaShoot)
                 else: cap(t(tkTutorialKeyLeftClick)) & " / " & cap(keyName(kb[kaShoot]))
  text.multiReplace(
    ("{move}", moveCaps),
    ("{aim}", cap(t(tkTutorialKeyRightStick))),
    ("{fire}", fireCaps),
    ("{dash}", bindCap(kaDash)),
    ("{wall}", bindCap(kaPlaceWall)),
    ("{legendary}", bindCap(kaLegendary)),
    ("{pause}", if pad: "[Start]" else: "[Esc]"),  # fixed, non-rebindable
    ("{interval}", $BossWaveInterval))

proc continueCap(): string =
  if isGamepadActive(): "[A]" else: "[Enter]"

proc skipCap(): string =
  if isGamepadActive(): "[Select]" else: "[Tab]"

# ---------------------------------------------------------------------------
# Keycap-aware rich text: "[...]" groups render as keycaps and wrap as a unit.

type
  Token = object
    text: string
    key: bool
    spaceBefore: bool

proc keycapTokens(s: string): seq[Token] =
  var i = 0
  var space = false
  while i < s.len:
    let c = s[i]
    if c == ' ':
      space = true
      inc i
    elif c == '[':
      let close = s.find(']', i + 1)
      if close < 0:
        result.add Token(text: s[i .. ^1], spaceBefore: space)
        break
      result.add Token(text: s[i + 1 ..< close], key: true, spaceBefore: space)
      space = false
      i = close + 1
    else:
      var j = i
      while j < s.len and s[j] != ' ' and s[j] != '[':
        inc j
      result.add Token(text: s[i ..< j], spaceBefore: space)
      space = false
      i = j

proc spaceWidth(size: int32): int32 =
  ## The gap drawText really leaves between words. measureText(" ") alone is
  ## nearly zero in this font -- the visible gap is mostly glyph spacing -- so
  ## measure it the way a whole string is laid out.
  max(measureText("a a", size) - measureText("aa", size), size div 4)

proc tokenWidth(tok: Token, size: int32): int32 =
  if tok.key: measureText(tok.text, size - 2) + KeyPadX * 2
  else: measureText(tok.text, size)

proc layoutRich(s: string, maxW, size: int32): seq[seq[Token]] =
  ## Greedy wrap by token; a keycap never splits across lines.
  let spaceW = spaceWidth(size)
  var line: seq[Token]
  var x = 0'i32
  for tok in keycapTokens(s):
    var placed = tok
    let w = tokenWidth(tok, size)
    let gap = if tok.spaceBefore and line.len > 0: spaceW else: 0'i32
    if line.len > 0 and x + gap + w > maxW:
      result.add line
      line = @[]
      x = 0
    if line.len == 0:
      placed.spaceBefore = false
      x = w
    else:
      x += gap + w
    line.add placed
  if line.len > 0:
    result.add line

proc richWidth(line: seq[Token], size: int32): int32 =
  let spaceW = spaceWidth(size)
  for tok in line:
    if tok.spaceBefore: result += spaceW
    result += tokenWidth(tok, size)

proc drawRichLine(line: seq[Token], x, y, size: int32, textColor: Color, alpha: float32) =
  let spaceW = spaceWidth(size)
  var cx = x
  for tok in line:
    if tok.spaceBefore: cx += spaceW
    let w = tokenWidth(tok, size)
    if tok.key:
      let kh = size + 4
      let ky = y - 3
      drawRectangle(cx, ky, w, kh, withAlpha(KeyBg, KeyBg.a.float32 * alpha))
      drawRectangle(cx, ky + kh - 2, w, 2, withAlpha(Accent, 120.0'f32 * alpha))  # keycap lip
      drawRectangleLines(Rectangle(x: cx.float32, y: ky.float32, width: w.float32, height: kh.float32),
                         1, withAlpha(Accent, 180.0'f32 * alpha))
      drawText(tok.text, cx + KeyPadX, y - 1, size - 2, withAlpha(KeyText, 255.0'f32 * alpha))
    else:
      drawText(tok.text, cx, y, size, withAlpha(textColor, textColor.a.float32 * alpha))
    cx += w

proc drawRich(s: string, x, y, size: int32, textColor: Color, alpha: float32) =
  ## Single-line convenience (labels, footer): no wrapping.
  for line in layoutRich(s, int32.high, size):
    drawRichLine(line, x, y, size, textColor, alpha)

# ---------------------------------------------------------------------------
# Step content

proc stepTitle(step: TutorialStep): string =
  case step
  of tsMove:    t(tkTutorialMoveTitle)
  of tsFire:    t(tkTutorialFireTitle)
  of tsDash:    t(tkTutorialDashTitle)
  of tsTargets: t(tkTutorialTargetsTitle)
  of tsLoot:    t(tkTutorialLootTitle)
  of tsStatus:  t(tkTutorialStatusTitle)
  of tsWalls:   t(tkTutorialWallsTitle)
  of tsReady:   t(tkTutorialReadyTitle)

proc stepBody(step: TutorialStep): string =
  let raw = case step
    of tsMove:    t(tkTutorialMoveBody)
    of tsFire:    (if isGamepadActive(): t(tkTutorialFireBodyPad) else: t(tkTutorialFireBodyKb))
    of tsDash:    t(tkTutorialDashBody)
    of tsTargets: t(tkTutorialTargetsBody)
    of tsLoot:    t(tkTutorialLootBody)
    of tsStatus:  t(tkTutorialStatusBody)
    of tsWalls:   t(tkTutorialWallsBody)
    of tsReady:   t(tkTutorialReadyBody)
  fillBindings(raw)

# ---------------------------------------------------------------------------
# World cues (raw virtual space: drawn after drawGame's world pass closed)

proc toScreen(p: Vector2f): Vector2 =
  worldToVirtual(Vector2(x: p.x, y: p.y))

proc drawCornerBrackets(c: Vector2, half, arm: float32, color: Color) =
  for sx in [-1.0'f32, 1.0'f32]:
    for sy in [-1.0'f32, 1.0'f32]:
      let corner = Vector2(x: c.x + sx * half, y: c.y + sy * half)
      drawLine(corner, Vector2(x: corner.x - sx * arm, y: corner.y), 2, color)
      drawLine(corner, Vector2(x: corner.x, y: corner.y - sy * arm), 2, color)

proc drawWorldCues(game: Game, s: TutorialState) =
  let scale = getWorldViewScale()
  let time = game.time
  let pulse = 0.5'f32 + 0.5'f32 * sin(time * 5.0'f32)
  case s.step
  of tsMove:
    # Point the player at themselves; fades as they get moving.
    let fade = 1.0'f32 - s.progress * 0.6'f32
    let c = toScreen(game.player.pos)
    let r = (game.player.radius + 16.0'f32 + pulse * 6.0'f32) * scale
    drawCircleLines(c.x.int32, c.y.int32, r, withAlpha(Accent, (140.0'f32 + 90.0'f32 * pulse) * fade))
    drawCircleLines(c.x.int32, c.y.int32, r + 5.0'f32 * scale, withAlpha(Accent, 60.0'f32 * fade))
    let label = t(tkTutorialYou)
    let lw = measureText(label, 14)
    let ly = (c.y - r - 22.0'f32).int32
    drawText(label, c.x.int32 - lw div 2 + 1, ly + 1, 14, withAlpha(Black, 160.0'f32 * fade))
    drawText(label, c.x.int32 - lw div 2, ly, 14, withAlpha(Accent, 255.0'f32 * fade))
  of tsTargets:
    for enemy in game.enemies:
      if enemy.id in s.targetIds:
        let c = toScreen(enemy.pos)
        let half = (enemy.radius + 9.0'f32 + pulse * 4.0'f32) * scale
        drawCornerBrackets(c, half, half * 0.45'f32,
                           withAlpha(ThreatColor, 170.0'f32 + 85.0'f32 * pulse))
  of tsLoot:
    for orb in game.xpOrbs:
      let c = toScreen(orb.pos)
      drawCircleLines(c.x.int32, c.y.int32, (9.0'f32 + pulse * 4.0'f32) * scale,
                      withAlpha(DoneColor, 120.0'f32 + 100.0'f32 * pulse))
    for coin in game.coins:
      let c = toScreen(coin.pos)
      drawCircleLines(c.x.int32, c.y.int32, (10.0'f32 + pulse * 4.0'f32) * scale,
                      withAlpha(CoinColor, 120.0'f32 + 100.0'f32 * pulse))
  else:
    discard

# ---------------------------------------------------------------------------
# HUD highlights (inside the HUD's UI-scale layer, same space as the panel)

proc highlightRow(r: Rectangle, color: Color, time: float32) =
  if r.width <= 0 or r.height <= 0:
    return
  let pulse = 0.5'f32 + 0.5'f32 * sin(time * 6.0'f32)
  let grow = 2.0'f32 + pulse * 2.0'f32
  drawRectangle(r.x.int32, r.y.int32, r.width.int32, r.height.int32,
                withAlpha(color, 22.0'f32 + 22.0'f32 * pulse))
  drawRectangleLines(Rectangle(x: r.x - grow, y: r.y - grow,
                               width: r.width + grow * 2.0'f32, height: r.height + grow * 2.0'f32),
                     2, withAlpha(color, 150.0'f32 + 100.0'f32 * pulse))

proc rowOrPanel(r: Rectangle): Rectangle =
  ## A minimized classic panel draws no rows; point at what is left of it.
  if r.width > 0: r else: lastStatusPanelRect

proc drawHudHighlights(game: Game, s: TutorialState) =
  case s.step
  of tsDash:
    highlightRow(rowOrPanel(lastDashRowRect), Accent, game.time)
  of tsLoot:
    highlightRow(rowOrPanel(lastStatsRowRect), CoinColor, game.time)
    highlightRow(rowOrPanel(lastLevelBarRect), DoneColor, game.time)
  of tsStatus:
    highlightRow(lastStatusPanelRect, Accent, game.time)
  of tsWalls:
    highlightRow(rowOrPanel(lastStatsRowRect), Accent, game.time)
  else:
    discard

# ---------------------------------------------------------------------------
# Instruction card

proc drawCheck(x, y: float32, color: Color) =
  drawLine(Vector2(x: x, y: y + 6), Vector2(x: x + 5, y: y + 11), 3, color)
  drawLine(Vector2(x: x + 5, y: y + 11), Vector2(x: x + 14, y: y), 3, color)

proc drawCard(game: Game, s: TutorialState) =
  let vw = getVirtualScreenWidth()
  let vh = getVirtualScreenHeight()
  let cardW = min(CardMaxWidth, vw - 32)
  let textW = cardW - CardPad * 2
  let lines = layoutRich(stepBody(s.step), textW, BodySize)
  let bodyH = lines.len.int32 * BodyLineH
  let cardH = TitleBarH + 10 + TitleSize + 12 + bodyH + 8 + RowSize + 12 + FooterSize + 12

  let enter = easeOutCubic(s.stepTime / EnterTime)
  let cardX = (vw - cardW) div 2
  let cardY = vh - cardH - CardBottomMargin + ((1.0'f32 - enter) * 18.0'f32).int32

  # Fade the card while the player is underneath it, so it never hides them.
  let scale = getActiveUIScale()
  let pv = worldToVirtual(Vector2(x: game.player.pos.x, y: game.player.pos.y))
  let pl = Vector2(x: pv.x / scale, y: pv.y / scale)
  let cardRect = Rectangle(x: cardX.float32 - 20, y: cardY.float32 - 20,
                           width: cardW.float32 + 40, height: cardH.float32 + 40)
  let alpha = enter * (if checkCollisionPointRec(pl, cardRect): 0.35'f32 else: 1.0'f32)

  let done = s.doneTimer > 0
  let edge = if done: DoneColor else: Accent

  # Body + chrome
  drawRectangle(cardX, cardY, cardW, cardH, withAlpha(CardBg, CardBg.a.float32 * alpha))
  drawRectangle(cardX, cardY, cardW, TitleBarH, withAlpha(TitleBarBg, TitleBarBg.a.float32 * alpha))
  drawRectangle(cardX, cardY, 2, cardH, withAlpha(edge, 220.0'f32 * alpha))
  drawRectangleLines(Rectangle(x: cardX.float32, y: cardY.float32,
                               width: cardW.float32, height: cardH.float32),
                     1, withAlpha(edge, 120.0'f32 * alpha))

  # Title bar: process name + step pips (done / current / pending)
  drawText(t(tkTutorialHeader), cardX + 10, cardY + 6, 12, withAlpha(Accent, 255.0'f32 * alpha))
  const pip = 8'i32
  const pipGap = 4'i32
  let stepCount = TutorialStep.high.ord + 1
  var px = cardX + cardW - 10 - stepCount.int32 * (pip + pipGap) + pipGap
  let py = cardY + (TitleBarH - pip) div 2
  for st in TutorialStep:
    let r = Rectangle(x: px.float32, y: py.float32, width: pip.float32, height: pip.float32)
    if st < s.step or (st == s.step and done):
      drawRectangle(r, withAlpha(DoneColor, 200.0'f32 * alpha))
    elif st == s.step:
      let blink = 0.5'f32 + 0.5'f32 * sin(game.time * 6.0'f32)
      drawRectangle(r, withAlpha(Accent, (140.0'f32 + 110.0'f32 * blink) * alpha))
    else:
      drawRectangleLines(r, 1, withAlpha(MutedColor, 160.0'f32 * alpha))
    px += pip + pipGap

  # Step title, with a DONE stamp while an action step's beat plays
  var y = cardY + TitleBarH + 10
  drawText(stepTitle(s.step), cardX + CardPad, y, TitleSize,
           withAlpha(if done: DoneColor else: White, 255.0'f32 * alpha))
  if done:
    let doneText = t(tkTutorialDone)
    let dw = measureText(doneText, 16)
    let dx = cardX + cardW - CardPad - dw
    drawText(doneText, dx, y + 2, 16, withAlpha(DoneColor, 255.0'f32 * alpha))
    drawCheck((dx - 22).float32, (y + 3).float32, withAlpha(DoneColor, 255.0'f32 * alpha))
  y += TitleSize + 12

  for line in lines:
    drawRichLine(line, cardX + CardPad, y, BodySize, BodyColor, alpha)
    y += BodyLineH
  y += 8

  # Progress row: a bar toward the step's goal, or, on a read-only card, the
  # auto-advance timer beside the "continue" prompt.
  var label = ""
  if s.step.isRead:
    let action = if s.step != TutorialStep.high: t(tkTutorialNext)
                 elif s.practice: t(tkTutorialFinish)
                 else: t(tkTutorialStartWave)
    label = continueCap() & " " & action
  elif s.step == tsTargets:
    let destroyed = int(round(s.progress * TargetCount.float32))
    label = t(tkTutorialTargetsCount) & " " & $destroyed & "/" & $TargetCount
  let labelW = if label.len > 0: richWidth(layoutRich(label, int32.high, RowSize)[0], RowSize) + 12
               else: 0'i32
  let barW = max(40'i32, textW - labelW)
  let barY = y + RowSize div 2 - 3
  let barColor = if done: DoneColor elif s.step.isRead: MutedColor else: Accent
  drawRectangle(cardX + CardPad, barY, barW, 6, withAlpha(Color(r: 20, g: 32, b: 44, a: 255), 220.0'f32 * alpha))
  let fillW = int32(barW.float32 * clamp(s.progress, 0.0'f32, 1.0'f32))
  if fillW > 0:
    drawRectangle(cardX + CardPad, barY, fillW, 6, withAlpha(barColor, 230.0'f32 * alpha))
  drawRectangleLines(Rectangle(x: (cardX + CardPad).float32, y: barY.float32,
                               width: barW.float32, height: 6),
                     1, withAlpha(barColor, 140.0'f32 * alpha))
  if label.len > 0:
    drawRich(label, cardX + CardPad + barW + 12, y, RowSize,
             if s.step.isRead: BodyColor else: Accent, alpha)
  y += RowSize + 12

  # Footer: hold-to-skip, with the hold filling underneath it.
  let footer = t(tkTutorialHoldSkip).replace("{key}", skipCap())
  drawRich(footer, cardX + CardPad, y, FooterSize, MutedColor, alpha)
  if s.skipHold > 0:
    let fw = richWidth(layoutRich(footer, int32.high, FooterSize)[0], FooterSize)
    let hold = clamp(s.skipHold / SkipHoldTime, 0.0'f32, 1.0'f32)
    drawRectangle(cardX + CardPad, y + FooterSize + 3, int32(fw.float32 * hold), 2,
                  withAlpha(ThreatColor, 230.0'f32 * alpha))

proc drawTutorialOverlay*(game: Game, hudScale: float32) =
  ## Call right after drawGame, outside any UI-scale layer.
  if not isTutorialActive(game):
    return
  let s = tutorialState()
  drawWorldCues(game, s)
  beginUIScaleMode(hudScale)
  drawHudHighlights(game, s)
  drawCard(game, s)
  endUIScaleMode()
