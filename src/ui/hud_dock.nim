## Widescreen HUD docks.
##
## The 16:9 layout reserves one band on each side of the arena (see
## render_context.WidescreenGutterWidth). This module paints those bands and
## owns the card vocabulary every panel docked in them is drawn with, so the
## player column (ui/os_combined_hud), the run column (game.nim, survival.nim)
## and the diagnostics section (ui/os_debug_panel) read as one surface.
##
## Near-leaf: raylib + utils + render_context only, so any HUD module can use
## it without dragging in the others.

import raylib, math
import ../utils, ../render_context

const
  DockMargin* = 4'i32
    ## Gap between a dock card and the edges of its band.
  DockCardW* = WidescreenGutterWidth - DockMargin * 2
    ## Width of a docked card (163 at the designed 171px band).
  DockPad* = 8'i32
    ## Inner horizontal padding of a docked card.
  DockContentW* = DockCardW - DockPad * 2
    ## Usable text width inside a docked card.
  DockGap* = 6'i32
    ## Vertical gap between stacked cards.
  DockHeaderH* = 16'i32
    ## Height of a card's title strip.

  DockAccent* = Color(r: 0, g: 220, b: 255, a: 255)
  DockInk* = Color(r: 228, g: 240, b: 250, a: 255)
  DockDim* = Color(r: 135, g: 160, b: 182, a: 255)
  DockShadow* = Color(r: 0, g: 0, b: 0, a: 150)
  DockCardBg* = Color(r: 9, g: 16, b: 26, a: 232)
  DockTrackBg* = Color(r: 4, g: 10, b: 16, a: 235)
    ## Unfilled part of a bar.

proc drawShadowText*(text: string, x, y, size: int32, color: Color) =
  ## Text lifted off the card by a 1px drop shadow.
  drawText(text, x + 1, y + 1, size, withAlpha(DockShadow, min(DockShadow.a, color.a)))
  drawText(text, x, y, size, color)

proc drawDockBands*(time: float32) =
  ## Paint the two side bands behind the docked HUD. Drawn in plain virtual
  ## coordinates (outside any UI-scale layer) and derived from the world view,
  ## so it covers exactly the strips the arena leaves at every interface scale.
  let vw = getVirtualScreenWidth().float32
  let vh = getVirtualScreenHeight()
  let leftEdge = getWorldViewOffsetX()
  let rightEdge = leftEdge + BaseVirtualWidth.float32 * getWorldViewScale()
  if leftEdge < 1.0'f32:
    return
  let lw = leftEdge.int32
  let rx = rightEdge.int32
  let rw = vw.int32 - rx
  const outer = Color(r: 10, g: 17, b: 28, a: 255)
  const inner = Color(r: 4, g: 8, b: 14, a: 255)
  drawRectangleGradientH(0, 0, lw, vh, outer, inner)
  drawRectangleGradientH(rx, 0, rw, vh, inner, outer)

  # Faint dot lattice so the bands read as a surface rather than letterboxing.
  const step = 16'i32
  let dot = Color(r: 60, g: 110, b: 150, a: 22)
  var y = step div 2
  while y < vh:
    var x = step div 2
    while x < lw - 2:
      drawRectangle(x, y, 1, 1, dot)
      x += step
    x = rx + step div 2
    while x < rx + rw:
      drawRectangle(x, y, 1, 1, dot)
      x += step
    y += step

  # Arena seam: a hairline on each inner edge with a slow light travelling
  # down it, and ticks every 64px like a rack rail.
  let seam = withAlpha(DockAccent, 70)
  drawRectangle(lw - 1, 0, 1, vh, seam)
  drawRectangle(rx, 0, 1, vh, seam)
  var ty = 32'i32
  while ty < vh:
    drawRectangle(lw - 4, ty, 3, 1, withAlpha(DockAccent, 60))
    drawRectangle(rx + 1, ty, 3, 1, withAlpha(DockAccent, 60))
    ty += 64
  let travel = ((time * 90.0'f32) mod (vh.float32 + 120.0'f32)) - 60.0'f32
  drawRectangleGradientV(lw - 1, travel.int32, 1, 60,
                         withAlpha(DockAccent, 0), withAlpha(DockAccent, 150))
  drawRectangleGradientV(rx, (vh.float32 - travel).int32 - 60, 1, 60,
                         withAlpha(DockAccent, 150), withAlpha(DockAccent, 0))

proc drawDockCard*(x, y, w, h: int32, accent: Color = DockAccent,
                   bg: Color = DockCardBg) =
  ## A docked card: solid body, an accent spine on the left and a thin rim.
  drawRectangle(x, y, w, h, bg)
  drawRectangle(x, y, 2, h, withAlpha(accent, 210))
  drawRectangleLines(Rectangle(x: x.float32, y: y.float32, width: w.float32, height: h.float32),
                     1, withAlpha(accent, 55))

proc drawDockHeader*(x, y, w: int32, title: string, accent: Color = DockAccent,
                     right: string = "", rightColor: Color = DockDim): int32 {.discardable.} =
  ## Title strip across the top of a card; returns the y just below it.
  drawRectangle(x + 2, y, w - 2, DockHeaderH, withAlpha(accent, 34))
  drawRectangle(x + 2, y + DockHeaderH - 1, w - 2, 1, withAlpha(accent, 70))
  drawShadowText(title, x + DockPad, y + 3, 10, accent)
  if right.len > 0:
    let rw = measureText(right, 10)
    drawShadowText(right, x + w - DockPad - rw, y + 3, 10, rightColor)
  y + DockHeaderH

proc drawDockBar*(x, y, w, h: int32, frac: float32, fill: Color,
                  rim: Color = Color(r: 0, g: 0, b: 0, a: 0)) =
  ## A horizontal meter: dark track, `frac` of it filled, a 1px highlight on
  ## top of the fill, and an optional rim.
  drawRectangle(x, y, w, h, DockTrackBg)
  let fw = int32(w.float32 * clamp(frac, 0.0'f32, 1.0'f32))
  if fw > 0:
    drawRectangle(x, y, fw, h, fill)
    if h >= 4:
      drawRectangle(x, y, fw, 1, withAlpha(Color(r: 255, g: 255, b: 255, a: 255), 70))
  if rim.a > 0:
    drawRectangleLines(Rectangle(x: x.float32, y: y.float32, width: w.float32, height: h.float32),
                       1, rim)
