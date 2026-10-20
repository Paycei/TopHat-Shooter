## First-run language selection screen.
##
## Shown once, right after the splash and before the opening cinematic, so the
## player can pick the language the intro (and the rest of the game) plays in.
## This screen is the ONE intentional exception to the localization system: it
## renders before a language has been chosen, so every label is hard-coded and
## each option is written in its own language ("English" / "Espanol") plus a
## bilingual title, so a player of either language understands it.

import raylib, math
import ../modding/mod_patch_core
import ../draw_prims

const
  LangSpanish* = 1   ## the option index of Spanish (English is 0)

proc languageOptionRects*(screenWidth, screenHeight: int32): array[2, Rectangle] {.moddable.} =
  ## Geometry for the two selectable cards. Shared by the draw proc and the
  ## hit-testing in the main loop so they can never drift apart.
  const
    cardW = 300.0'f32
    cardH = 230.0'f32
    gap   = 70.0'f32
  let totalW = cardW * 2.0'f32 + gap
  let startX = (screenWidth.float32 - totalW) / 2.0'f32
  let y      = screenHeight.float32 / 2.0'f32 - cardH / 2.0'f32 + 30.0'f32
  result[0] = Rectangle(x: startX, y: y, width: cardW, height: cardH)
  result[1] = Rectangle(x: startX + cardW + gap, y: y, width: cardW, height: cardH)

proc modLanguageOptionRects*(screenWidth, screenHeight: int32, count: int): seq[Rectangle] {.moddable.} =
  ## The mods' languages (register.language): rows of small buttons under the
  ## two cards, centred, four to a row.
  const
    buttonW = 180.0'f32
    buttonH = 36.0'f32
    gap = 14.0'f32
    perRow = 4
  let cards = languageOptionRects(screenWidth, screenHeight)
  let top = cards[0].y + cards[0].height + 26.0'f32
  for i in 0 ..< count:
    let row = i div perRow
    let inRow = min(count - row * perRow, perRow)
    let rowW = inRow.float32 * buttonW + (inRow - 1).float32 * gap
    let x = (screenWidth.float32 - rowW) / 2.0'f32 + (i mod perRow).float32 * (buttonW + gap)
    result.add Rectangle(x: x, y: top + row.float32 * (buttonH + gap), width: buttonW, height: buttonH)

proc drawCenteredText(text: string, cx, y, size: int32, color: Color) =
  let w = measureText(text, size)
  drawText(text, cx - w div 2, y, size, color)

proc drawUSFlag(x, y, w, h: float32) =
  ## Simplified, recognizable US flag: 13 red/white stripes + blue canton with
  ## a small star grid. The flag stands in for the English language option.
  let stripeH = h / 13.0'f32
  for i in 0 ..< 13:
    let col = if i mod 2 == 0: Color(r: 178, g: 34, b: 52, a: 255)
              else: Color(r: 245, g: 245, b: 245, a: 255)
    drawRectangle(x.int32, (y + i.float32 * stripeH).int32,
                  w.int32, (stripeH + 1.0'f32).int32, col)
  let cantonW = w * 0.42'f32
  let cantonH = stripeH * 7.0'f32
  drawRectangle(x.int32, y.int32, cantonW.int32, cantonH.int32,
                Color(r: 38, g: 46, b: 110, a: 255))
  # Star field: a tidy 5x4 dot grid is more than enough to read as "stars".
  for row in 0 ..< 4:
    for c in 0 ..< 5:
      let sx = x + cantonW * (c.float32 + 1.0'f32) / 6.0'f32
      let sy = y + cantonH * (row.float32 + 1.0'f32) / 5.0'f32
      drawDisc(Vector2(x: sx, y: sy), 2.2'f32, Color(r: 255, g: 255, b: 255, a: 255))
  drawRectOutline(Rectangle(x: x, y: y, width: w, height: h),
                     1.5'f32, Color(r: 0, g: 0, b: 0, a: 120))

proc drawSpainFlag(x, y, w, h: float32) =
  ## Spain flag: red / (double-height) yellow / red horizontal bands, with a
  ## small simplified emblem on the yellow band. Stands in for Spanish.
  let red = Color(r: 198, g: 11, b: 30, a: 255)
  let yellow = Color(r: 255, g: 196, b: 0, a: 255)
  drawRectangle(x.int32, y.int32, w.int32, (h * 0.25'f32).int32, red)
  drawRectangle(x.int32, (y + h * 0.25'f32).int32, w.int32, (h * 0.5'f32).int32, yellow)
  drawRectangle(x.int32, (y + h * 0.75'f32).int32, w.int32, (h * 0.25'f32).int32, red)
  # Minimal emblem hint: a small crowned shield, drawn left-of-centre as the
  # real flag has it. Just enough shape to read as "the Spanish flag".
  let ex = x + w * 0.32'f32
  let ey = y + h * 0.5'f32
  drawRectangle((ex - 7.0'f32).int32, (ey - 9.0'f32).int32, 14, 18,
                Color(r: 178, g: 34, b: 40, a: 255))
  drawRectangle((ex - 7.0'f32).int32, (ey - 9.0'f32).int32, 7, 18,
                Color(r: 200, g: 150, b: 30, a: 255))
  drawRectangle((ex - 5.0'f32).int32, (ey - 14.0'f32).int32, 10, 4,
                Color(r: 230, g: 190, b: 40, a: 255))  # crown bar
  drawRectOutline(Rectangle(x: x, y: y, width: w, height: h),
                     1.5'f32, Color(r: 0, g: 0, b: 0, a: 120))

proc drawLanguageCard(rect: Rectangle, hovered: bool, time: float32,
                      flagDraw: proc(x, y, w, h: float32), name, hint: string) =
  let pulse = (sin(time * 3.0'f32) * 0.5'f32 + 0.5'f32)
  let bg = if hovered: Color(r: 30, g: 42, b: 60, a: 255)
           else: Color(r: 22, g: 28, b: 40, a: 255)
  let border = if hovered: Color(r: 0, g: uint8(190.0'f32 + pulse * 60.0'f32), b: 255, a: 255)
               else: Color(r: 70, g: 86, b: 110, a: 255)
  drawRectangle((rect.x + 4).int32, (rect.y + 5).int32, rect.width.int32, rect.height.int32,
                Color(r: 0, g: 0, b: 0, a: 120))  # drop shadow
  drawRectangle(rect.x.int32, rect.y.int32, rect.width.int32, rect.height.int32, bg)
  drawRectOutline(rect, if hovered: 3.0'f32 else: 1.5'f32, border)

  # Flag, centred near the top of the card.
  let flagW = rect.width * 0.55'f32
  let flagH = flagW * 0.62'f32
  let flagX = rect.x + (rect.width - flagW) / 2.0'f32
  let flagY = rect.y + 28.0'f32
  flagDraw(flagX, flagY, flagW, flagH)

  let cx = (rect.x + rect.width / 2.0'f32).int32
  drawCenteredText(name, cx, (flagY + flagH + 22.0'f32).int32, 30,
                   if hovered: White else: Color(r: 220, g: 230, b: 245, a: 255))
  drawCenteredText(hint, cx, (rect.y + rect.height - 28.0'f32).int32, 16,
                   Color(r: 130, g: 150, b: 170, a: 220))

proc drawLanguageSelect*(screenWidth, screenHeight: int32, time: float32,
                         mousePos: Vector2, modLanguageNames: seq[string] = @[]) {.moddable.} =
  ## Draw the whole first-run language picker. Hit-testing happens in the main
  ## loop using `languageOptionRects`.
  clearBackground(Color(r: 12, g: 15, b: 22, a: 255))

  # Faint scanlines to match the OS-desktop aesthetic.
  var ly = 0'i32
  while ly < screenHeight:
    drawRectangle(0, ly, screenWidth, 1, Color(r: 255, g: 255, b: 255, a: 6))
    ly += 3

  let cx = screenWidth div 2
  let titleY = (screenHeight.float32 * 0.5'f32 - 200.0'f32).int32
  drawCenteredText("Select Language", cx, titleY, 38,
                   Color(r: 0, g: 225, b: 255, a: 255))
  drawCenteredText("Selecciona tu idioma", cx, titleY + 44, 24,
                   Color(r: 180, g: 200, b: 220, a: 230))

  let rects = languageOptionRects(screenWidth, screenHeight)
  drawLanguageCard(rects[0], checkCollisionPointRec(mousePos, rects[0]), time,
                   drawUSFlag, "English", "[1]  Click")
  drawLanguageCard(rects[1], checkCollisionPointRec(mousePos, rects[1]), time,
                   drawSpainFlag, "Español", "[2]  Clic")

  # The mods' languages, by their own names (a mod's text, so no flag).
  for i, r in modLanguageOptionRects(screenWidth, screenHeight, modLanguageNames.len):
    let hovered = checkCollisionPointRec(mousePos, r)
    drawRectangle(r.x.int32, r.y.int32, r.width.int32, r.height.int32,
                  if hovered: Color(r: 30, g: 42, b: 60, a: 255) else: Color(r: 22, g: 28, b: 40, a: 255))
    drawRectOutline(r, if hovered: 2.0'f32 else: 1.0'f32,
                    if hovered: Color(r: 0, g: 220, b: 255, a: 255) else: Color(r: 70, g: 86, b: 110, a: 255))
    drawCenteredText(modLanguageNames[i], (r.x + r.width / 2.0'f32).int32, (r.y + 9.0'f32).int32, 18,
                     if hovered: White else: Color(r: 220, g: 230, b: 245, a: 255))
