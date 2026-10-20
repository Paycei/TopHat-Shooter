## Per-theme animated wallpapers for the purchasable desktop backgrounds.
##
## The default desktop keeps its hand-crafted wallpaper in `os_desktop.nim`;
## every other `DesktopBgType` is a whole scene here, which `drawDesktopBgScene`
## draws for the desktop and for the shop's preview cards alike (the shop
## translates the matrix and clips with a scissor before calling in), so a
## card is the real background in miniature. Everything is stateless - derived
## purely from (width, height, time) - and sized from min(width, height), with
## floors where a detail would vanish in the 170x64 card.
##
## Light is drawn with draw_prims' gradients (drawGlow, drawRadialGradient,
## drawGlowLine, ...), never with stacked translucent discs, which band. The
## scene keeps the frame's alpha opaque (beginKeepAlpha, see ui_theme) so a
## translucent light adds to what is under it instead of darkening it.

import raylib, math
import ../modding/mod_patch_core
import ../draw_prims
import ../desktop_bg_skins, ../utils, ../vec
from ui_theme import beginKeepAlpha, endKeepAlpha

const
  CubeAnchorX* = 0.64'f32  ## where the desktop cube floats, as a fraction of the screen
  CubeAnchorY* = 0.46'f32

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

proc unitOf(w, h: float32): float32 {.inline.} =
  ## One pixel of the full-size desktop (768 tall), with a floor so hairlines
  ## and dots still show in the shop's 64-pixel card.
  max(min(w, h) / 768.0'f32, 0.3'f32)

proc detailOf(w, h: float32): float32 {.inline.} =
  ## 1 on the desktop, down to 0.3 in the shop's 64-pixel card: particle and
  ## pattern counts scale with it there, where they would only add cost.
  clamp(min(w, h) / 420.0'f32, 0.3'f32, 1.0'f32)

proc counted(n: int, detail: float32): int {.inline.} = max(1, int(n.float32 * detail + 0.5'f32))

proc fillRect(x, y, w, h: float32, col: Color) {.inline.} =
  drawRectangle(Rectangle(x: x, y: y, width: w, height: h), col)

proc vGrad(x, y, w, h: float32, top, bottom: Color) =
  drawGradientQuad(vec2(x, y), vec2(x, y + h), vec2(x + w, y + h), vec2(x + w, y), top, bottom, bottom, top)

proc hGrad(x, y, w, h: float32, left, right: Color) =
  drawGradientQuad(vec2(x, y), vec2(x, y + h), vec2(x + w, y + h), vec2(x + w, y), left, left, right, right)

proc skyStops(w: float32, stops: openArray[(float32, Color)]) =
  ## A vertical gradient through several (y, colour) stops.
  for i in 0 ..< stops.len - 1:
    vGrad(0.0'f32, stops[i][0], w, stops[i + 1][0] - stops[i][0] + 0.5'f32, stops[i][1], stops[i + 1][1])

proc fillEllipse(c: Vector2, rx, ry: float32, col: Color) {.inline.} =
  ## A flat ellipse in the quads batch (raylib's drawEllipse emits triangles).
  drawRadialGradient(c, rx, ry, col, col, reLinear, 1)

proc edgeVignette(w, h, depth: float32, col: Color) =
  ## Edges fading inward. Corner glows are never used for this: a dark glow
  ## at a corner reads as an obvious dark dot.
  let clear = withAlpha(col, 0'u8)
  let d = min(w, h) * depth
  hGrad(0.0'f32, 0.0'f32, d, h, col, clear)
  hGrad(w - d, 0.0'f32, d, h, clear, col)
  vGrad(0.0'f32, 0.0'f32, w, d, col, clear)
  vGrad(0.0'f32, h - d, w, d, clear, col)

proc drawTri2(a, b, c: Vector2, col: Color) =
  ## Filled triangle in either winding, so face-local fills never cull.
  drawGradientTriangle(a, b, c, col, col, col)

proc drawLightCone(apex: Vector2, baseY, halfW: float32, col: Color, edge = 0.0'f32,
                   reach = 0.35'f32, topHalf = 0.0'f32) =
  ## A beam from a light at `apex` (`topHalf` wide either side: a lamp shade's
  ## mouth) down to `baseY`, brightest at its source and along its axis. Its
  ## sides fade out (`edge` keeps a little light at them), and so does its end
  ## (`reach` is how much is left there). Starting from a width rather than a
  ## point is what keeps the sides soft all the way up.
  let clear = withAlpha(col, 0'u8)
  let axis = scaleAlpha(col, reach)
  let side = scaleAlpha(col, edge)
  let top = if topHalf > 0.0'f32: clear else: col
  # Both halves split along apex -> outer base corner, mirror images of each
  # other: a quad's colour depends on its diagonal, and unmatched halves seam.
  drawGradientQuad(apex, vec2(apex.x, baseY), vec2(apex.x - halfW, baseY), vec2(apex.x - topHalf, apex.y),
                   col, axis, side, top)
  drawGradientQuad(apex, vec2(apex.x + topHalf, apex.y), vec2(apex.x + halfW, baseY), vec2(apex.x, baseY),
                   col, top, side, axis)

proc starCount(w, h, density: float32): int =
  clamp(int(w * h / 5200.0'f32 * density), 14, 320)

proc drawStarField(w, h, time: float32, count: int, seed, yMax, alphaK, brightShare: float32) =
  ## Crisp little stars of mixed colour temperature; a `brightShare` of them
  ## are big enough to flare with a soft glow and four diffraction spikes.
  let u = unitOf(w, h)
  for i in 0 ..< count:
    let sd = seed + i.float32 * 7.137'f32
    let x = hash01(sd) * w
    let y = hash01(sd + 1.3'f32) * yMax
    let tw = 0.55'f32 + 0.45'f32 * sin(time * (0.7'f32 + hash01(sd + 2.1'f32) * 2.2'f32) + sd * 3.0'f32)
    let temp = hash01(sd + 4.4'f32)
    let col = if temp < 0.22'f32: rgba(170, 196, 255)
              elif temp < 0.78'f32: rgba(236, 236, 255)
              elif temp < 0.93'f32: rgba(255, 232, 196)
              else: rgba(255, 186, 166)
    let big = hash01(sd + 5.9'f32)
    let r = max(0.35'f32, (0.45'f32 + big * big * 1.15'f32) * u)
    let a = (60.0'f32 + 170.0'f32 * tw * (0.4'f32 + 0.6'f32 * big)) * alphaK
    drawDisc(vec2(x, y), r, withAlpha(col, a))
    if big > 1.0'f32 - brightShare:
      let p = vec2(x, y)
      drawGlow(p, r * 6.0'f32, withAlpha(col, a * 0.35'f32))
      let arm = (5.0'f32 + 9.0'f32 * tw) * u
      let clear = withAlpha(col, 0'u8)
      let sw = max(0.5'f32, 0.9'f32 * u)
      drawTaperedLine(vec2(x - arm, y), p, 0.0'f32, sw, clear, withAlpha(col, a * 0.8'f32))
      drawTaperedLine(p, vec2(x + arm, y), sw, 0.0'f32, withAlpha(col, a * 0.8'f32), clear)
      drawTaperedLine(vec2(x, y - arm), p, 0.0'f32, sw, clear, withAlpha(col, a * 0.8'f32))
      drawTaperedLine(p, vec2(x, y + arm), sw, 0.0'f32, withAlpha(col, a * 0.8'f32), clear)

proc drawSoftLine(a, b: Vector2, u: float32, glow, core: Color, glowW = 7.0'f32, coreW = 1.2'f32) =
  ## A neon line: a soft halo and a crisp core.
  drawGlowLine(a, b, glowW * u, glow)
  drawStroke(a, b, max(0.5'f32, coreW * u), core)

# ---------------------------------------------------------------------------
# Rain glyphs (Data Rain's code, Neon City's signs)
# ---------------------------------------------------------------------------

const
  RainGlyphs: array[14, array[4, array[4, float32]]] = [
    [[0.0'f32, 0.0, 1.0, 0.0], [1.0, 0.0, 0.6, 0.45], [0.5, 0.3, 0.4, 1.0], [0, 0, 0, 0]],
    [[0.9'f32, 0.0, 0.2, 0.5], [0.55, 0.25, 0.55, 1.0], [0, 0, 0, 0], [0, 0, 0, 0]],
    [[0.5'f32, 0.0, 0.5, 0.2], [0.1, 0.25, 0.9, 0.25], [0.9, 0.25, 0.5, 1.0], [0.1, 0.25, 0.1, 0.45]],
    [[0.1'f32, 0.1, 0.9, 0.1], [0.5, 0.1, 0.5, 0.9], [0.0, 0.9, 1.0, 0.9], [0, 0, 0, 0]],
    [[0.1'f32, 0.3, 0.9, 0.3], [0.9, 0.3, 0.8, 1.0], [0.45, 0.0, 0.15, 1.0], [0, 0, 0, 0]],
    [[0.1'f32, 0.3, 0.9, 0.25], [0.05, 0.6, 0.95, 0.55], [0.4, 0.0, 0.6, 1.0], [0, 0, 0, 0]],
    [[0.4'f32, 0.0, 0.1, 0.4], [0.35, 0.12, 0.9, 0.12], [0.9, 0.12, 0.3, 1.0], [0, 0, 0, 0]],
    [[0.0'f32, 0.35, 1.0, 0.35], [0.3, 0.0, 0.3, 0.6], [0.75, 0.0, 0.75, 0.6], [0.75, 0.6, 0.4, 1.0]],
    [[0.1'f32, 0.1, 0.3, 0.25], [0.05, 0.45, 0.25, 0.6], [0.1, 1.0, 0.95, 0.3], [0, 0, 0, 0]],
    [[0.1'f32, 0.15, 0.2, 0.4], [0.45, 0.1, 0.55, 0.35], [0.9, 0.1, 0.4, 1.0], [0, 0, 0, 0]],
    [[0.2'f32, 0.0, 0.8, 0.0], [0.8, 0.0, 0.8, 1.0], [0.8, 1.0, 0.2, 1.0], [0.2, 1.0, 0.2, 0.0]],
    [[0.3'f32, 0.15, 0.55, 0.0], [0.55, 0.0, 0.55, 1.0], [0, 0, 0, 0], [0, 0, 0, 0]],
    [[0.5'f32, 0.0, 0.5, 1.0], [0.0, 0.4, 1.0, 0.4], [0.5, 0.4, 0.1, 0.8], [0, 0, 0, 0]],
    [[0.1'f32, 0.0, 0.9, 0.0], [0.9, 0.0, 0.1, 1.0], [0.1, 1.0, 0.9, 1.0], [0, 0, 0, 0]]]

proc drawRainGlyph(x, y, cw, ch: float32, glyph: int, mirror: bool, width: float32, col: Color) =
  ## One procedural glyph (mirrored half-width-katakana feel) in a cw x ch box.
  for seg in RainGlyphs[glyph mod RainGlyphs.len]:
    if seg[0] == seg[2] and seg[1] == seg[3]: continue
    let x0 = if mirror: 1.0'f32 - seg[0] else: seg[0]
    let x1 = if mirror: 1.0'f32 - seg[2] else: seg[2]
    drawStroke(vec2(x + x0 * cw, y + seg[1] * ch), vec2(x + x1 * cw, y + seg[3] * ch), width, col)

# ---------------------------------------------------------------------------
# Neon City
# ---------------------------------------------------------------------------

proc drawNeonSign(x, y, sw, sh, time, seed, u: float32, col: Color) =
  ## A vertical sign of glowing tubes: a frame and a few stacked glyph strokes,
  ## buzzing, and now and then a faulty one drops out for a beat.
  let flick = 0.75'f32 + 0.25'f32 * sin(time * (3.0'f32 + hash01(seed) * 4.0'f32) + seed)
  let broken = if hash01(seed + 5.1'f32) > 0.7'f32 and
                  fract01(time * 0.37'f32 + hash01(seed + 2.0'f32)) < 0.07'f32: 0.12'f32
               else: 1.0'f32
  let k = flick * broken
  let glow = withAlpha(col, 120.0'f32 * k)
  let core = withAlpha(colorLerp(col, rgba(255, 255, 255), 0.55'f32), 235.0'f32 * k)
  drawGlow(vec2(x + sw * 0.5'f32, y + sh * 0.5'f32), max(sw, sh) * 0.9'f32, withAlpha(col, 50.0'f32 * k))
  fillRect(x, y, sw, sh, rgba(10, 4, 18, 220))
  let pts = [vec2(x, y), vec2(x + sw, y), vec2(x + sw, y + sh), vec2(x, y + sh)]
  for i in 0 .. 3:
    drawSoftLine(pts[i], pts[(i + 1) mod 4], u, glow, core, 5.0'f32, 0.9'f32)
  let glyphs = clamp(int(sh / max(sw, 1.0'f32)), 2, 5)
  let gh = sh / glyphs.float32
  let gw = min(sw * 0.62'f32, gh * 0.75'f32)
  for g in 0 ..< glyphs:
    let gx = x + (sw - gw) * 0.5'f32
    let gy = y + gh * g.float32 + gh * 0.16'f32
    let gi = int(hash01(seed + g.float32 * 3.3'f32) * 97.0'f32)
    drawRainGlyph(gx, gy, gw, gh * 0.68'f32, gi, (gi and 1) == 1, max(1.6'f32, gw * 0.28'f32), glow)
    drawRainGlyph(gx, gy, gw, gh * 0.68'f32, gi, (gi and 1) == 1, max(0.5'f32, gw * 0.1'f32), core)

proc drawNeonCityFx(w, h, time: float32) =
  ## A rain-slick night skyline: a smoggy magenta sky, three depths of towers
  ## with lit windows and rim light, buzzing neon signs, a wet street that
  ## mirrors them, and rain.
  let u = unitOf(w, h)
  let horizon = h * 0.78'f32
  skyStops(w, [(0.0'f32, rgba(6, 3, 20)), (horizon * 0.45'f32, rgba(24, 8, 50)),
               (horizon * 0.8'f32, rgba(80, 16, 96)), (horizon, rgba(150, 30, 120))])
  drawStarField(w, h, time, starCount(w, h, 0.25'f32), 3.0'f32, horizon * 0.42'f32, 0.45'f32, 0.0'f32)

  # Light pollution pooling over the towers, and slow smog drifting through it.
  drawGlow(vec2(w * 0.5'f32, horizon), w * 0.8'f32, h * 0.45'f32, rgba(255, 40, 170, 90))
  drawGlow(vec2(w * 0.16'f32, horizon), w * 0.32'f32, h * 0.3'f32, rgba(130, 50, 255, 80))
  drawGlow(vec2(w * 0.84'f32, horizon), w * 0.32'f32, h * 0.26'f32, rgba(60, 150, 255, 60))
  for b in 0 ..< 4:
    let seed = b.float32 * 13.1'f32
    let bx = wrapCoord(hash01(seed) * w * 1.6'f32 + time * w * (0.004'f32 + hash01(seed + 1.0'f32) * 0.006'f32),
                       w * 1.6'f32) - w * 0.3'f32
    let by = horizon * (0.55'f32 + hash01(seed + 2.0'f32) * 0.35'f32)
    drawGlow(vec2(bx, by), w * 0.28'f32, h * 0.05'f32, rgba(255, 110, 220, 26))

  # Skyline, far to near. Towers stand on the horizon; the street goes on after.
  const LayerW = [0.034'f32, 0.05'f32, 0.078'f32]
  const RiseMin = [0.07'f32, 0.09'f32, 0.10'f32]
  const RiseMax = [0.24'f32, 0.30'f32, 0.34'f32]
  let bodies = [rgba(54, 22, 90), rgba(30, 11, 56), rgba(12, 5, 24)]
  let rims = [rgba(255, 90, 215, 50), rgba(255, 80, 205, 90), rgba(255, 70, 200, 150)]
  let windowCols = [rgba(255, 196, 130), rgba(255, 100, 215), rgba(120, 220, 255)]
  for layer in 0 .. 2:
    let baseW = w * LayerW[layer]
    var x = -baseW * hash01(layer.float32 * 11.0'f32 + 0.5'f32)
    var i = 0
    while x < w:
      let seed = i.float32 * 9.173'f32 + layer.float32 * 57.31'f32
      let bw = baseW * (0.6'f32 + hash01(seed) * 0.9'f32)
      let bh = h * (RiseMin[layer] + hash01(seed + 1.7'f32) * (RiseMax[layer] - RiseMin[layer]))
      let top = horizon - bh
      let gap = max(0.8'f32, bw * 0.06'f32)
      let bodyW = bw - gap
      fillRect(x, top, bodyW, bh + 0.5'f32, bodies[layer])
      let roof = int(hash01(seed + 3.1'f32) * 4.0'f32)
      case roof
      of 1:   # stepped crown
        fillRect(x + bodyW * 0.2'f32, top - bh * 0.06'f32, bodyW * 0.6'f32, bh * 0.06'f32 + 0.5'f32, bodies[layer])
      of 2:   # antenna mast with a warning light
        let mx = x + bodyW * 0.5'f32
        let mastTop = top - bh * 0.16'f32
        drawStroke(vec2(mx, top), vec2(mx, mastTop), max(0.5'f32, 1.0'f32 * u), bodies[layer])
        if layer > 0:
          let blink = sin(time * 2.2'f32 + seed) * 0.5'f32 + 0.5'f32
          drawGlow(vec2(mx, mastTop), 7.0'f32 * u, rgba(255, 50, 90, int(60.0'f32 + 120.0'f32 * blink)))
          drawDisc(vec2(mx, mastTop), max(0.4'f32, 1.3'f32 * u), rgba(255, 90, 120, int(120.0'f32 + 130.0'f32 * blink)))
      of 3:   # slanted roof
        drawTri2(vec2(x, top), vec2(x + bodyW, top), vec2(x + bodyW, top - bh * 0.08'f32), bodies[layer])
      else: discard
      # Rim light down the lit edge and along the roof line.
      drawStroke(vec2(x + 0.5'f32 * u, top), vec2(x + 0.5'f32 * u, horizon), max(0.5'f32, 1.0'f32 * u), rims[layer])
      drawStroke(vec2(x, top), vec2(x + bodyW, top), max(0.5'f32, 0.8'f32 * u), scaleAlpha(rims[layer], 0.7'f32))
      # Windows: a grid, sparsely lit, a few flickering.
      let ww = max(0.5'f32, (1.6'f32 + layer.float32 * 0.6'f32) * u)
      let wh = max(0.6'f32, (2.2'f32 + layer.float32 * 0.8'f32) * u)
      let cols = clamp(int(bodyW / (ww * 2.6'f32)), 1, 9)
      let rows = clamp(int(bh / (wh * 2.4'f32)), 1, 22)
      let litShare = [0.18'f32, 0.30'f32, 0.36'f32][layer]
      for cx in 0 ..< cols:
        for cy in 0 ..< rows:
          let ws = hash01(seed + cx.float32 * 3.7'f32 + cy.float32 * 11.3'f32)
          if ws > litShare: continue
          let flick = if ws < 0.02'f32: 0.5'f32 + 0.5'f32 * sin(time * 5.0'f32 + ws * 300.0'f32) else: 1.0'f32
          let wc = windowCols[int(hash01(seed + ws * 91.0'f32) * 3.0'f32) mod 3]
          let wa = (60.0'f32 + 50.0'f32 * layer.float32) * flick
          fillRect(x + bodyW * (cx.float32 + 0.3'f32) / cols.float32,
                   top + bh * (cy.float32 + 0.25'f32) / rows.float32, ww, wh, withAlpha(wc, wa))
      if layer >= 1 and hash01(seed + 8.8'f32) > 0.55'f32 and bh > h * 0.16'f32:
        let col = if hash01(seed + 9.9'f32) > 0.5'f32: rgba(255, 40, 200) else: rgba(80, 220, 255)
        let sw = max(2.0'f32, bodyW * 0.22'f32)
        drawNeonSign(x + bodyW * (0.12'f32 + hash01(seed + 4.2'f32) * 0.5'f32), top + bh * 0.14'f32,
                     sw, bh * 0.34'f32, time, seed, u, col)
      x += bw
      inc i
    # Haze between layers so the far towers sink into the smog.
    vGrad(0.0'f32, horizon - h * (0.18'f32 + 0.06'f32 * layer.float32), w, h * (0.18'f32 + 0.06'f32 * layer.float32),
          rgba(150, 30, 120, 0), rgba(150, 30, 120, 40 - layer * 12))

  # The wet street mirrors the city: smeared streaks of neon below the line.
  vGrad(0.0'f32, horizon, w, h - horizon, rgba(34, 10, 48), rgba(6, 2, 12))
  for k in 0 ..< counted(22, detailOf(w, h)):
    let seed = k.float32 * 5.71'f32
    let rx = hash01(seed) * w
    let col = [rgba(255, 50, 200), rgba(90, 220, 255), rgba(255, 190, 120)][int(hash01(seed + 1.0'f32) * 3.0'f32) mod 3]
    let len = (h - horizon) * (0.35'f32 + hash01(seed + 2.0'f32) * 0.55'f32)
    let rw = (1.5'f32 + hash01(seed + 3.0'f32) * 4.0'f32) * u
    let ra = 50.0'f32 + hash01(seed + 4.0'f32) * 70.0'f32
    var prev = vec2(rx, horizon)
    for s in 1 .. 4:
      let yy = horizon + len * s.float32 / 4.0'f32
      let cur = vec2(rx + sin(time * 2.4'f32 + yy * 0.08'f32 / u + seed) * 1.6'f32 * u, yy)
      drawTaperedLine(prev, cur, rw, rw * 0.8'f32, withAlpha(col, ra * (1.0'f32 - (s - 1).float32 / 4.0'f32)),
                      withAlpha(col, ra * (1.0'f32 - s.float32 / 4.0'f32)))
      prev = cur
  drawSoftLine(vec2(0.0'f32, horizon), vec2(w, horizon), u, rgba(255, 60, 200, 150), rgba(255, 180, 240, 210), 12.0'f32, 1.2'f32)

  # Rain, slanting through the light.
  for r in 0 ..< counted(80, detailOf(w, h)):
    let seed = r.float32 * 3.17'f32
    let speed = h * (0.9'f32 + hash01(seed) * 0.6'f32)
    let ry = wrapCoord(hash01(seed + 1.0'f32) * h * 1.2'f32 + time * speed, h * 1.2'f32) - h * 0.1'f32
    let rx = wrapCoord(hash01(seed + 2.0'f32) * w + ry * 0.18'f32, w)
    let len = (10.0'f32 + hash01(seed + 3.0'f32) * 14.0'f32) * u
    let a = 22.0'f32 + hash01(seed + 4.0'f32) * 36.0'f32
    drawTaperedLine(vec2(rx - len * 0.18'f32, ry - len), vec2(rx, ry), 0.0'f32, max(0.5'f32, 0.9'f32 * u),
                    rgba(200, 170, 255, 0), rgba(210, 190, 255, int(a)))

# ---------------------------------------------------------------------------
# Data Rain
# ---------------------------------------------------------------------------

proc drawDataRainFx(w, h, time: float32) =
  ## Cascading code in three depths: small dim far columns, bright near ones
  ## with white-hot heads, glyphs that mutate as they fall, a green fog low
  ## down and faint scanlines over it all.
  let s = min(w, h)
  vGrad(0.0'f32, 0.0'f32, w, h, rgba(0, 10, 3), rgba(0, 4, 1))
  drawGlow(vec2(w * 0.5'f32, h * 1.05'f32), w * 0.75'f32, h * 0.5'f32, rgba(0, 160, 50, 60))
  drawGlow(vec2(w * CubeAnchorX, h * CubeAnchorY), s * 0.55'f32, rgba(0, 120, 40, 40))
  const Scale = [0.55'f32, 0.8'f32, 1.15'f32]
  const Bright = [0.35'f32, 0.62'f32, 1.0'f32]
  const Share = [0.55'f32, 0.45'f32, 0.36'f32]
  for layer in 0 .. 2:
    let cell = max(2.6'f32, s * 0.024'f32 * Scale[layer] / detailOf(w, h))
    let slots = max(4, int(w / (cell * 1.25'f32)))
    let strokeW = max(0.45'f32, cell * 0.1'f32)
    for c in 0 ..< slots:
      let seed = c.float32 * 13.77'f32 + layer.float32 * 101.3'f32
      if hash01(seed + 0.3'f32) > Share[layer]: continue
      let colX = (c.float32 + 0.15'f32) * w / slots.float32
      let speed = h * (0.12'f32 + hash01(seed + 3.1'f32) * 0.4'f32) * Scale[layer]
      let trail = 6 + int(hash01(seed + 6.7'f32) * 12.0'f32)
      let span = h + cell * (trail.float32 + 2.0'f32)
      let headY = wrapCoord(hash01(seed + 9.2'f32) * span + time * speed, span) - cell * 2.0'f32
      for k in 0 .. trail:
        let gy = headY - k.float32 * cell
        if gy < -cell or gy > h: continue
        let fadeK = pow(1.0'f32 - k.float32 / (trail.float32 + 1.0'f32), 1.6'f32)
        let a = 255.0'f32 * Bright[layer] * fadeK
        if a < 6.0'f32: continue
        let shift = floor(time * (4.0'f32 + hash01(seed + k.float32) * 6.0'f32))
        let gi = int(hash01(seed * 1.71'f32 + k.float32 * 7.13'f32 + shift * 0.619'f32) * 97.0'f32)
        let col = if k == 0: rgba(215, 255, 220, int(250.0'f32 * Bright[layer]))
                  elif k <= 2: rgba(110, 255, 140, int(a))
                  else: rgba(0, 210, 70, int(a))
        drawRainGlyph(colX, gy, cell * 0.62'f32, cell * 0.82'f32, gi, (gi and 1) == 1, strokeW, col)
        if k == 0:
          drawGlow(vec2(colX + cell * 0.3'f32, gy + cell * 0.4'f32), cell * 1.6'f32,
                   rgba(80, 255, 130, int(90.0'f32 * Bright[layer])))
  var y = 0.0'f32
  let step = max(2.0'f32, 3.0'f32 * unitOf(w, h))
  while y < h:
    fillRect(0.0'f32, y, w, max(0.5'f32, step * 0.34'f32), rgba(0, 0, 0, 34))
    y += step
  edgeVignette(w, h, 0.22'f32, rgba(0, 0, 0, 130))

# ---------------------------------------------------------------------------
# Deep Void
# ---------------------------------------------------------------------------

proc drawDeepVoidFx(w, h, time: float32) =
  ## Deep space: a nebula band of layered coloured clouds with dark dust lanes
  ## across it, a sea of small stars (a few flaring), a dark planet's limb
  ## rising at the bottom edge, and the occasional shooting star.
  let s = min(w, h)
  let u = unitOf(w, h)
  vGrad(0.0'f32, 0.0'f32, w, h, rgba(3, 2, 12), rgba(7, 4, 18))
  drawStarField(w, h, time, starCount(w, h, 0.9'f32), 1.0'f32, h, 0.55'f32, 0.0'f32)

  # Nebula: overlapping coloured clouds along a diagonal band, breathing and
  # drifting a little, then dust lanes laid over them.
  let nebula = [rgba(130, 50, 230), rgba(210, 60, 180), rgba(50, 90, 230), rgba(40, 170, 210)]
  for n in 0 ..< 16:
    let seed = n.float32 * 31.7'f32
    let t = n.float32 / 15.0'f32
    let bx = w * (0.02'f32 + t * 0.98'f32) + (hash01(seed) - 0.5'f32) * w * 0.12'f32 +
             sin(time * 0.05'f32 + seed) * s * 0.02'f32
    let by = h * (0.92'f32 - t * 0.78'f32) + (hash01(seed + 2.2'f32) - 0.5'f32) * h * 0.28'f32 +
             cos(time * 0.04'f32 + seed * 1.3'f32) * s * 0.02'f32
    let r = s * (0.12'f32 + hash01(seed + 4.1'f32) * 0.2'f32)
    let breathe = 0.85'f32 + 0.15'f32 * sin(time * 0.3'f32 + seed)
    let col = nebula[int(hash01(seed + 6.0'f32) * 4.0'f32) mod 4]
    drawGlow(vec2(bx, by), r * 1.5'f32 * breathe, r * breathe, withAlpha(col, 52.0'f32 + hash01(seed + 7.0'f32) * 40.0'f32))
  for d in 0 ..< 6:
    let seed = d.float32 * 17.3'f32 + 5.0'f32
    let t = 0.1'f32 + d.float32 / 6.0'f32
    drawGlow(vec2(w * t + (hash01(seed) - 0.5'f32) * w * 0.08'f32, h * (0.86'f32 - t * 0.76'f32) + s * 0.04'f32),
             s * (0.16'f32 + hash01(seed + 1.0'f32) * 0.1'f32), s * 0.05'f32, rgba(3, 1, 8, 120))
  for c in 0 ..< 3:
    let t = 0.25'f32 + c.float32 * 0.25'f32
    drawGlow(vec2(w * t, h * (0.9'f32 - t * 0.78'f32)), s * 0.07'f32, rgba(235, 200, 255, 46))
  # The nearest stars, bright and flaring, over the clouds.
  drawStarField(w, h, time, starCount(w, h, 0.12'f32), 77.0'f32, h, 1.0'f32, 0.35'f32)

  # A dark planet rising at the bottom-left, its atmosphere lit along the limb.
  let pc = vec2(w * 0.2'f32, h * 1.5'f32)
  let pr = h * 0.68'f32
  drawGlow(pc, pr * 1.18'f32, rgba(90, 110, 255, 90))
  fillEllipse(pc, pr, pr, rgba(6, 5, 16))
  drawGradientRing(pc, pr * 0.9'f32, pr * 0.9'f32, pr, pr, rgba(60, 70, 190, 0), rgba(90, 120, 230, 130))
  drawGradientRing(pc, pr, pr, pr * 1.035'f32, pr * 1.035'f32, rgba(150, 190, 255, 180), rgba(90, 110, 255, 0))

  # Shooting stars on two interleaved cycles, with tapering tails.
  for lane in 0 .. 1:
    let period = 5.2'f32 + lane.float32 * 2.7'f32
    let phase = time / period + lane.float32 * 0.5'f32
    let t01 = fract01(phase)
    if t01 < 0.16'f32:
      let prog = t01 / 0.16'f32
      let seed = floor(phase) * 7.77'f32 + lane.float32 * 39.0'f32
      let dirX = (0.5'f32 + hash01(seed + 6.0'f32) * 0.5'f32) *
                 (if hash01(seed + 9.0'f32) > 0.5'f32: 1.0'f32 else: -1.0'f32)
      let px = hash01(seed) * w * 0.8'f32 + w * 0.1'f32 + dirX * prog * w * 0.45'f32
      let py = hash01(seed + 3.0'f32) * h * 0.4'f32 + prog * h * 0.35'f32
      let mvLen = sqrt(dirX * dirX * w * w * 0.2025'f32 + h * h * 0.1225'f32)
      let tailLen = s * 0.24'f32
      let fadeK = sin(prog * PI)
      let head = vec2(px, py)
      let tail = vec2(px - dirX * w * 0.45'f32 / mvLen * tailLen, py - h * 0.35'f32 / mvLen * tailLen)
      drawTaperedLine(tail, head, 0.0'f32, max(0.6'f32, 2.2'f32 * u), rgba(200, 200, 255, 0),
                      rgba(240, 236, 255, int(230.0'f32 * fadeK)))
      drawGlow(head, 10.0'f32 * u, rgba(220, 220, 255, int(150.0'f32 * fadeK)))

# ---------------------------------------------------------------------------
# System Sunrise
# ---------------------------------------------------------------------------

proc sunColorAt(t: float32): Color =
  ## The synthwave sun's banding, t = 0 at its crown to 1 at the horizon.
  if t < 0.5'f32: colorLerp(rgba(255, 238, 130), rgba(255, 150, 60), t / 0.5'f32)
  else: colorLerp(rgba(255, 150, 60), rgba(245, 50, 125), (t - 0.5'f32) / 0.5'f32)

proc drawSunriseFx(w, h, time: float32) =
  ## Synthwave dusk: a banded sun sliced by scrolling slits, neon mountains
  ## flanking it, and a glowing grid racing toward the viewer.
  let u = unitOf(w, h)
  let horizon = h * 0.64'f32
  let sunX = w * 0.5'f32
  let sunR = min(w, h) * 0.26'f32

  skyStops(w, [(0.0'f32, rgba(12, 4, 32)), (horizon * 0.35'f32, rgba(48, 12, 80)),
               (horizon * 0.72'f32, rgba(140, 30, 112)), (horizon, rgba(250, 112, 76))])
  drawStarField(w, h, time, starCount(w, h, 0.35'f32), 5.0'f32, horizon * 0.5'f32, 0.6'f32, 0.04'f32)

  # The sun: a halo, then horizontal slabs graded crown to base, with the
  # classic slits widening toward the horizon and scrolling down.
  drawGlow(vec2(sunX, horizon - sunR * 0.3'f32), sunR * 2.4'f32, rgba(255, 100, 70, 110))
  drawGlow(vec2(sunX, horizon - sunR * 0.4'f32), sunR * 1.35'f32, rgba(255, 190, 100, 90))
  let top = horizon - sunR
  const Slabs = 56
  for i in 0 ..< Slabs:
    let y0 = top + sunR * i.float32 / Slabs.float32
    let y1 = top + sunR * (i + 1).float32 / Slabs.float32
    let tm = (y0 + y1) * 0.5'f32 - top
    let t = tm / sunR
    # Slits occupy the lower 55%: a moving band pattern whose gap grows downward.
    if t > 0.45'f32:
      let band = fract01((t - 0.45'f32) * 6.0'f32 - time * 0.35'f32)
      if band < 0.12'f32 + (t - 0.45'f32) * 0.7'f32: continue
    let d0 = y0 - horizon
    let d1 = y1 - horizon
    let h0 = sqrt(max(0.0'f32, sunR * sunR - d0 * d0))
    let h1 = sqrt(max(0.0'f32, sunR * sunR - d1 * d1))
    let c0 = sunColorAt(i.float32 / Slabs.float32)
    let c1 = sunColorAt((i + 1).float32 / Slabs.float32)
    drawGradientQuad(vec2(sunX - h0, y0), vec2(sunX - h1, y1), vec2(sunX + h1, y1), vec2(sunX + h0, y0),
                     c0, c1, c1, c0)

  # Neon mountains either side, lower toward the sun so they frame it.
  for ridge in 0 .. 1:
    let body = if ridge == 0: rgba(52, 14, 74) else: rgba(22, 6, 36)
    let ridgeCol = if ridge == 0: rgba(255, 90, 200, 110) else: rgba(255, 70, 190, 200)
    const Peaks = 22
    var prev = vec2(0.0'f32, horizon)
    for p in 0 .. Peaks:
      let x = w * p.float32 / Peaks.float32
      let seed = p.float32 * 7.3'f32 + ridge.float32 * 31.0'f32
      let clearSun = smoothstep(sunR * 0.6'f32, sunR * 1.6'f32, abs(x - sunX))
      let peakH = h * (0.03'f32 + hash01(seed) * (if ridge == 0: 0.12'f32 else: 0.08'f32)) *
                  clearSun * (if (p and 1) == 0: 1.0'f32 else: 0.55'f32)
      let cur = vec2(x, horizon - peakH)
      if p > 0:
        drawGradientQuad(prev, vec2(prev.x, horizon), vec2(cur.x, horizon), cur, body, body, body, body)
        drawSoftLine(prev, cur, u, scaleAlpha(ridgeCol, 0.6'f32), ridgeCol, 6.0'f32, 1.0'f32)
      prev = cur

  # Ground, the horizon's glow, and the sun's smeared reflection.
  vGrad(0.0'f32, horizon, w, h - horizon, rgba(36, 6, 46), rgba(8, 2, 14))
  drawGlow(vec2(sunX, horizon), sunR * 2.0'f32, sunR * 0.5'f32, rgba(255, 120, 80, 120))
  for i in 0 ..< 6:
    let ry = horizon + (h - horizon) * (0.06'f32 + i.float32 * 0.07'f32)
    let half = sunR * (0.8'f32 - i.float32 * 0.1'f32) * (0.85'f32 + 0.15'f32 * sin(time * 1.7'f32 + i.float32))
    drawGlowLine(vec2(sunX - half, ry), vec2(sunX + half, ry), 4.0'f32 * u, rgba(255, 140, 90, 120 - i * 16))

  # The grid: rays fading out toward the horizon, rungs racing forward.
  for i in -9 .. 9:
    let bottom = vec2(sunX + i.float32 * w * 0.11'f32, h)
    let mid = vec2(sunX + (bottom.x - sunX) * 0.08'f32, horizon + (h - horizon) * 0.08'f32)
    drawTaperedLine(mid, bottom, max(0.5'f32, 0.6'f32 * u), max(0.6'f32, 2.2'f32 * u),
                    rgba(255, 70, 190, 0), rgba(255, 90, 200, 190))
  for i in 0 ..< 10:
    let t = fract01(time * 0.14'f32 + i.float32 / 10.0'f32)
    let gy = horizon + t * t * (h - horizon)
    drawSoftLine(vec2(0.0'f32, gy), vec2(w, gy), u, rgba(255, 60, 190, int(20.0'f32 + t * 90.0'f32)),
                 rgba(255, 110, 210, int(30.0'f32 + t * 170.0'f32)), 3.0'f32 + t * 6.0'f32, 0.6'f32 + t * 1.2'f32)
  drawSoftLine(vec2(0.0'f32, horizon), vec2(w, horizon), u, rgba(255, 160, 90, 170), rgba(255, 220, 160, 240), 12.0'f32, 1.4'f32)

# ---------------------------------------------------------------------------
# Neural Network
# ---------------------------------------------------------------------------

proc drawNeuralNetFx(w, h, time: float32) =
  ## A living network in two depths: soft bokeh far back, a dim far mesh, and
  ## the near neurons - glowing cells with dendrites, synapses carrying comet
  ## pulses, and now and then a cell firing a flash down its links.
  let s = min(w, h)
  let u = unitOf(w, h)
  vGrad(0.0'f32, 0.0'f32, w, h, rgba(2, 12, 30), rgba(1, 4, 13))
  for b in 0 ..< 10:
    let seed = b.float32 * 19.1'f32
    let bx = hash01(seed) * w + sin(time * 0.06'f32 + seed) * s * 0.03'f32
    let by = hash01(seed + 1.0'f32) * h + cos(time * 0.05'f32 + seed) * s * 0.03'f32
    let col = if b mod 2 == 0: rgba(0, 150, 220) else: rgba(0, 200, 180)
    drawGlow(vec2(bx, by), s * (0.06'f32 + hash01(seed + 2.0'f32) * 0.12'f32), withAlpha(col, 26.0'f32 + hash01(seed + 3.0'f32) * 20.0'f32))

  # The far mesh.
  const FarCount = 24
  let farShown = counted(FarCount, detailOf(w, h))
  var fx, fy: array[FarCount, float32]
  for i in 0 ..< farShown:
    let seed = i.float32 * 8.31'f32 + 300.0'f32
    fx[i] = hash01(seed) * w + sin(time * 0.1'f32 + seed) * w * 0.015'f32
    fy[i] = hash01(seed + 2.6'f32) * h + cos(time * 0.09'f32 + seed) * h * 0.02'f32
  let farDist = s * 0.22'f32
  for i in 0 ..< farShown:
    for j in (i + 1) ..< farShown:
      let d = sqrt((fx[i] - fx[j]) * (fx[i] - fx[j]) + (fy[i] - fy[j]) * (fy[i] - fy[j]))
      if d < farDist:
        drawStroke(vec2(fx[i], fy[i]), vec2(fx[j], fy[j]), max(0.4'f32, 0.7'f32 * u),
                   rgba(0, 120, 200, int(10.0'f32 + (1.0'f32 - d / farDist) * 40.0'f32)))
    drawDisc(vec2(fx[i], fy[i]), max(0.4'f32, 1.3'f32 * u), rgba(60, 170, 230, 110))

  # The near neurons.
  const NodeCount = 22
  var px, py: array[NodeCount, float32]
  for i in 0 ..< NodeCount:
    let seed = i.float32 * 12.93'f32
    px[i] = (0.05'f32 + hash01(seed) * 0.9'f32) * w +
            sin(time * (0.18'f32 + hash01(seed + 5.0'f32) * 0.2'f32) + seed) * w * 0.03'f32
    py[i] = (0.06'f32 + hash01(seed + 2.6'f32) * 0.88'f32) * h +
            cos(time * (0.15'f32 + hash01(seed + 7.7'f32) * 0.22'f32) + seed * 1.7'f32) * h * 0.04'f32
  var firing: array[NodeCount, float32]
  for i in 0 ..< NodeCount:
    let seed = i.float32 * 12.93'f32
    let ph = fract01(time / (5.0'f32 + hash01(seed + 11.0'f32) * 5.0'f32) + hash01(seed + 12.0'f32))
    firing[i] = if ph < 0.12'f32: sin(ph / 0.12'f32 * PI) else: 0.0'f32
  let maxDist = s * 0.36'f32
  for i in 0 ..< NodeCount:
    for j in (i + 1) ..< NodeCount:
      let dx = px[i] - px[j]
      let dy = py[i] - py[j]
      let d = sqrt(dx * dx + dy * dy)
      if d < maxDist and d > 1.0'f32:
        let closeness = 1.0'f32 - d / maxDist
        let lit = max(firing[i], firing[j])
        let a = vec2(px[i], py[i])
        let b = vec2(px[j], py[j])
        drawGlowLine(a, b, (3.0'f32 + lit * 5.0'f32) * u, rgba(0, 170, 255, int((10.0'f32 + closeness * 30.0'f32) * (1.0'f32 + lit * 2.0'f32))))
        drawStroke(a, b, max(0.4'f32, 0.9'f32 * u), rgba(60, 190, 255, int(20.0'f32 + closeness * 80.0'f32 + lit * 100.0'f32)))
        if (i * 7 + j * 13) mod 3 == 0:
          let tt = fract01(time * (0.25'f32 + hash01((i * 31 + j).float32) * 0.5'f32) +
                           hash01((i * 17 + j * 3).float32))
          let p = vec2(a.x + (b.x - a.x) * tt, a.y + (b.y - a.y) * tt)
          let back = max(0.0'f32, tt - 0.12'f32)
          let q = vec2(a.x + (b.x - a.x) * back, a.y + (b.y - a.y) * back)
          drawTaperedLine(q, p, 0.0'f32, max(0.6'f32, 2.0'f32 * u), rgba(120, 255, 230, 0),
                          rgba(160, 255, 235, int(140.0'f32 + closeness * 100.0'f32)))
          drawGlow(p, 6.0'f32 * u, rgba(120, 255, 230, 150))
  for i in 0 ..< NodeCount:
    let seed = i.float32 * 12.93'f32
    let pulse = sin(time * (0.8'f32 + hash01(seed + 9.0'f32)) + seed) * 0.5'f32 + 0.5'f32
    let r = (2.2'f32 + hash01(seed + 3.3'f32) * 2.6'f32 + pulse * 0.8'f32) * u
    let c = vec2(px[i], py[i])
    for dd in 0 ..< (if detailOf(w, h) < 0.6'f32: 0 else: 3):
      let ang = hash01(seed + dd.float32 * 4.0'f32) * PI * 2.0'f32
      let len = r * (3.0'f32 + hash01(seed + dd.float32 * 5.0'f32) * 4.0'f32)
      let mid = vec2(c.x + cos(ang) * len * 0.55'f32, c.y + sin(ang) * len * 0.55'f32)
      let tip = vec2(mid.x + cos(ang + 0.6'f32) * len * 0.45'f32, mid.y + sin(ang + 0.6'f32) * len * 0.45'f32)
      drawTaperedLine(c, mid, r * 0.6'f32, r * 0.25'f32, rgba(0, 190, 255, 90), rgba(0, 190, 255, 50))
      drawTaperedLine(mid, tip, r * 0.25'f32, 0.0'f32, rgba(0, 190, 255, 50), rgba(0, 190, 255, 0))
    let f = firing[i]
    drawGlow(c, r * (6.0'f32 + f * 8.0'f32), rgba(0, 200, 230, int(60.0'f32 + pulse * 30.0'f32 + f * 120.0'f32)))
    drawDisc(c, r, rgba(30, 150, 210, 230))
    drawCircleOutline(c, r, rgba(140, 240, 255, 200))
    drawDisc(c, r * 0.45'f32, rgba(200, 255, 250, int(180.0'f32 + f * 75.0'f32)))

# ---------------------------------------------------------------------------
# Inferno Core
# ---------------------------------------------------------------------------

proc drawInfernoFx(w, h, time: float32) =
  ## A volcanic cavern: smoke rolling under a red-black sky, lava light
  ## welling from below, a jagged ridge of black rock veined with magma, and
  ## embers streaming up through the heat.
  let s = min(w, h)
  let u = unitOf(w, h)
  skyStops(w, [(0.0'f32, rgba(8, 2, 2)), (h * 0.45'f32, rgba(34, 6, 3)), (h, rgba(120, 24, 2))])
  let surge = sin(time * 1.7'f32) * 0.5'f32 + 0.5'f32
  drawGlow(vec2(w * 0.5'f32, h * 1.02'f32), w * 0.85'f32, h * 0.55'f32, rgba(255, 80, 0, int(110.0'f32 + surge * 40.0'f32)))
  drawGlow(vec2(w * 0.2'f32, h * 0.95'f32), w * 0.3'f32, h * 0.25'f32, rgba(255, 130, 20, 70))
  drawGlow(vec2(w * 0.82'f32, h * 0.97'f32), w * 0.3'f32, h * 0.25'f32, rgba(255, 60, 10, 80))
  drawGlow(vec2(w * CubeAnchorX, h * CubeAnchorY), s * 0.4'f32, rgba(255, 110, 30, 46))

  # Smoke rolling across the upper dark.
  for m in 0 ..< 9:
    let seed = m.float32 * 21.7'f32
    let mx = wrapCoord(hash01(seed) * w * 1.5'f32 + time * w * (0.006'f32 + hash01(seed + 1.0'f32) * 0.01'f32),
                       w * 1.5'f32) - w * 0.25'f32
    let my = h * (0.08'f32 + hash01(seed + 2.0'f32) * 0.45'f32) + sin(time * 0.2'f32 + seed) * h * 0.02'f32
    let mr = s * (0.14'f32 + hash01(seed + 3.0'f32) * 0.16'f32)
    drawGlow(vec2(mx, my), mr * 1.6'f32, mr, rgba(14, 6, 5, int(90.0'f32 + hash01(seed + 4.0'f32) * 60.0'f32)))

  # Heat shimmer: faint wavering bands of light low over the rock.
  for b in 0 ..< 4:
    let by = h * (0.62'f32 + b.float32 * 0.05'f32) + sin(time * 0.9'f32 + b.float32 * 2.0'f32) * h * 0.01'f32
    drawGlow(vec2(w * (0.3'f32 + 0.4'f32 * hash01(b.float32 + 7.0'f32)) + sin(time * 0.4'f32 + b.float32) * w * 0.05'f32, by),
             w * 0.4'f32, h * 0.02'f32, rgba(255, 140, 50, 22))

  # The ridge: black rock with a lava rim along its top and veins glowing in it.
  const Peaks = 26
  var ridge: array[Peaks + 1, Vector2]
  for p in 0 .. Peaks:
    let x = w * p.float32 / Peaks.float32
    let seed = p.float32 * 5.9'f32
    let base = h * (0.84'f32 - 0.05'f32 * sin(p.float32 * 0.55'f32 + 1.0'f32))
    ridge[p] = vec2(x, base - h * hash01(seed) * (if (p and 1) == 0: 0.07'f32 else: 0.03'f32))
  for p in 0 ..< Peaks:
    let a = ridge[p]
    let b = ridge[p + 1]
    drawGradientQuad(a, vec2(a.x, h), vec2(b.x, h), b, rgba(16, 5, 3), rgba(6, 2, 2), rgba(6, 2, 2), rgba(16, 5, 3))
    drawSoftLine(a, b, u, rgba(255, 90, 10, 130), rgba(255, 170, 70, 200), 9.0'f32, 1.3'f32)
  let glowK = 0.6'f32 + 0.4'f32 * surge
  for c in 0 ..< 9:
    let seed = c.float32 * 47.13'f32
    let start = int(hash01(seed) * Peaks.float32) mod Peaks
    var p = ridge[start]
    let pulse = 0.5'f32 + 0.5'f32 * sin(time * (1.2'f32 + hash01(seed + 8.0'f32)) + seed)
    for st in 0 ..< (3 + int(hash01(seed + 2.2'f32) * 3.0'f32)):
      let n = vec2(p.x + (hash01(seed + st.float32 * 3.3'f32) - 0.5'f32) * w * 0.04'f32,
                 p.y + h * (0.012'f32 + hash01(seed + st.float32 * 5.9'f32) * 0.03'f32))
      drawSoftLine(p, n, u, rgba(255, 90, 0, int(110.0'f32 * pulse * glowK)),
                   rgba(255, 190, 90, int(200.0'f32 * pulse * glowK)), 6.0'f32, 1.1'f32)
      p = n
    drawGlow(p, 10.0'f32 * u, rgba(255, 120, 20, int(80.0'f32 * pulse)))

  # Embers rising, swaying, trailing sparks and burning out as they climb.
  for e in 0 ..< counted(60, detailOf(w, h)):
    let seed = e.float32 * 7.91'f32
    let speed = h * (0.06'f32 + hash01(seed + 2.0'f32) * 0.16'f32)
    let cycleSpan = h * 1.15'f32
    let yPos = h * 1.02'f32 - wrapCoord(hash01(seed + 4.0'f32) * cycleSpan + time * speed, cycleSpan)
    let swayF = 0.8'f32 + hash01(seed + 6.0'f32) * 1.4'f32
    let xPos = hash01(seed) * w + sin(time * swayF + seed) * w * 0.015'f32
    let lift = 1.0'f32 - clamp(yPos / h, 0.0'f32, 1.0'f32)
    let fadeK = clamp(1.0'f32 - lift * 1.1'f32, 0.0'f32, 1.0'f32)
    let flicker = 0.7'f32 + 0.3'f32 * sin(time * (5.0'f32 + hash01(seed + 9.0'f32) * 6.0'f32) + seed)
    let size = (0.9'f32 + hash01(seed + 5.5'f32) * 1.8'f32) * (0.6'f32 + fadeK * 0.4'f32) * u
    let heat = hash01(seed + 11.0'f32)
    let col = if heat > 0.7'f32: rgba(255, 232, 140) elif heat > 0.35'f32: rgba(255, 150, 40) else: rgba(255, 80, 20)
    let a = 220.0'f32 * fadeK * flicker
    let p = vec2(xPos, yPos)
    let vx = cos(time * swayF + seed) * w * 0.015'f32 * swayF
    let tail = vec2(p.x - vx * 0.05'f32, p.y + speed * 0.05'f32)
    drawTaperedLine(tail, p, 0.0'f32, size * 1.6'f32, withAlpha(col, 0'u8), withAlpha(col, a * 0.6'f32))
    if (e mod 3) == 0:
      drawGlow(p, size * 5.0'f32, withAlpha(col, a * 0.35'f32))
    drawDisc(p, size, withAlpha(col, a))

# ---------------------------------------------------------------------------
# Aperture Test
# ---------------------------------------------------------------------------

proc drawAperturePortal(cx, cy, rx, ry, time: float32, rim, core: Color, spin, u: float32) =
  ## One oval portal: light thrown onto the wall, a dark event horizon that
  ## brightens toward its edge, swirling bands of light inside, a white-hot
  ## rim, and sparks spitting off it.
  drawGlow(vec2(cx, cy), rx * 4.2'f32, ry * 2.1'f32, withAlpha(rim, 110'u8))
  drawGlow(vec2(cx, cy), rx * 2.0'f32, ry * 1.35'f32, withAlpha(rim, 120'u8))
  let deep = colorLerp(rgba(8, 10, 16), rim, 0.25'f32)
  drawRadialGradient(vec2(cx, cy), rx, ry, deep, colorLerp(rim, core, 0.2'f32), reSmooth)
  # Swirl: three arcs of light at different radii, turning at different rates.
  for k in 0 .. 2:
    let rr = 0.35'f32 + k.float32 * 0.2'f32
    let start = time * spin * (0.6'f32 + k.float32 * 0.25'f32) + k.float32 * 2.1'f32
    const Steps = 14
    var prev = vec2(cx + cos(start) * rx * rr, cy + sin(start) * ry * rr)
    for st in 1 .. Steps:
      let a = start + st.float32 / Steps.float32 * PI * 1.1'f32
      let cur = vec2(cx + cos(a) * rx * rr, cy + sin(a) * ry * rr)
      let t = st.float32 / Steps.float32
      drawStroke(prev, cur, max(0.5'f32, (1.0'f32 + 1.4'f32 * (1.0'f32 - t)) * u),
                 withAlpha(colorLerp(rim, core, 0.5'f32), 150.0'f32 * sin(t * PI)))
      prev = cur
  drawGradientRing(vec2(cx, cy), rx * 0.8'f32, ry * 0.86'f32, rx, ry, withAlpha(rim, 0'u8), withAlpha(core, 255'u8))
  drawGradientRing(vec2(cx, cy), rx, ry, rx + 9.0'f32 * u, ry + 9.0'f32 * u, withAlpha(core, 255'u8), withAlpha(rim, 0'u8))
  for sp in 0 ..< 10:
    let seed = sp.float32 * 7.7'f32 + spin
    let life = fract01(time * (0.5'f32 + hash01(seed) * 0.6'f32) + hash01(seed + 1.0'f32))
    let a = hash01(seed + 2.0'f32 + floor(time * (0.5'f32 + hash01(seed) * 0.6'f32) + hash01(seed + 1.0'f32))) * PI * 2.0'f32
    let reach = 1.0'f32 + life * 0.35'f32
    let p = vec2(cx + cos(a) * rx * reach, cy + sin(a) * ry * reach)
    drawDisc(p, max(0.4'f32, 1.4'f32 * u * (1.0'f32 - life)), withAlpha(core, 230.0'f32 * (1.0'f32 - life)))

proc drawWallPanel(px, py, size, gap, base: float32, recessed: bool,
                   tint: Color, tintAmt: float32) =
  ## One Aperture wall panel: a light tile inset in the dark grout, lit from
  ## above (a slight vertical gradient), with a bevel (lit top-left, shadowed
  ## bottom-right; reversed when recessed) and a colour bleed from a portal.
  let b = if recessed: base * 0.62'f32 else: base
  let plain = rgba(int(b * 0.95'f32), int(b * 0.98'f32), int(b * 1.06'f32))
  let topC = colorLerp(brighten(plain, 10.0'f32), tint, tintAmt)
  let botC = colorLerp(brighten(plain, -14.0'f32), tint, tintAmt)
  let x0 = px + gap
  let y0 = py + gap
  let s = size - gap * 2.0'f32
  if s < 1.0'f32: return
  vGrad(x0, y0, s, s, topC, botC)
  let bw = max(0.6'f32, size * 0.035'f32)
  let hi = rgba(255, 255, 255, if recessed: 22 else: 60)
  let sh = rgba(0, 0, 0, if recessed: 80 else: 60)
  let topLeft = if recessed: sh else: hi
  let botRight = if recessed: hi else: sh
  drawStroke(vec2(x0, y0), vec2(x0 + s, y0), bw, topLeft)
  drawStroke(vec2(x0, y0), vec2(x0, y0 + s), bw, topLeft)
  drawStroke(vec2(x0, y0 + s), vec2(x0 + s, y0 + s), bw, botRight)
  drawStroke(vec2(x0 + s, y0), vec2(x0 + s, y0 + s), bw, botRight)

proc drawPortalFx(w, h, time: float32) =
  ## An Aperture-style test chamber: a panelled wall lit from above, two
  ## portals facing each other across it (their light colouring the panels),
  ## and energy motes streaming between them.
  let u = unitOf(w, h)
  let rimBlue = rgba(60, 150, 255)
  let coreBlue = rgba(200, 236, 255)
  let rimOrange = rgba(255, 140, 30)
  let coreOrange = rgba(255, 226, 160)
  let portalRx = min(w, h) * 0.085'f32
  let portalRy = min(w, h) * 0.175'f32
  let breathe = 1.0'f32 + 0.03'f32 * sin(time * 1.3'f32)
  # Must match os_desktop's portal escape (the cube flies into these).
  let bx = w * 0.2'f32
  let by = h * 0.5'f32
  let ox = w * 0.8'f32
  let oy = h * 0.5'f32
  let glowR = portalRy * 1.7'f32

  fillRect(0.0'f32, 0.0'f32, w, h, rgba(24, 28, 35))
  const Cols = 10
  let tile = w / Cols.float32
  let rowsN = int(ceil(h / tile)) + 1
  let gap = max(0.6'f32, tile * 0.018'f32)
  for gyi in 0 ..< rowsN:
    for gxi in 0 ..< Cols:
      let cellX = gxi.float32 * tile
      let cellY = gyi.float32 * tile
      let ccx = cellX + tile * 0.5'f32
      let ccy = cellY + tile * 0.5'f32
      let seed = gxi.float32 * 12.7'f32 + gyi.float32 * 31.3'f32
      let recessed = hash01(seed + 5.0'f32) > 0.85'f32
      let base = 200.0'f32 + (hash01(seed) - 0.5'f32) * 16.0'f32
      let tB = clamp(1.0'f32 - sqrt((ccx - bx) * (ccx - bx) + (ccy - by) * (ccy - by)) / glowR, 0.0'f32, 1.0'f32)
      let tO = clamp(1.0'f32 - sqrt((ccx - ox) * (ccx - ox) + (ccy - oy) * (ccy - oy)) / glowR, 0.0'f32, 1.0'f32)
      let (tint, amt) = if tB >= tO: (rimBlue, tB * 0.3'f32) else: (rimOrange, tO * 0.3'f32)
      drawWallPanel(cellX, cellY, tile, gap, base, recessed, tint, amt)

  # Overhead lighting: bright up top, falling off to the floor and the sides.
  vGrad(0.0'f32, 0.0'f32, w, h, rgba(255, 255, 255, 26), rgba(10, 14, 22, 110))
  edgeVignette(w, h, 0.3'f32, rgba(8, 10, 16, 120))
  drawAperturePortal(bx, by, portalRx * breathe, portalRy * breathe, time, rimBlue, coreBlue, 2.2'f32, u)
  drawAperturePortal(ox, oy, portalRx * breathe, portalRy * breathe, time, rimOrange, coreOrange, -2.0'f32, u)

  # Energy motes along two bowed arcs, blue -> orange as they cross.
  const Motes = 18
  let cxp = (bx + ox) * 0.5'f32
  for m in 0 ..< Motes:
    let lane = m mod 2
    let bow = if lane == 0: -h * 0.20'f32 else: h * 0.18'f32
    var tt = fract01(time * 0.16'f32 + m.float32 / Motes.float32)
    if lane == 1: tt = 1.0'f32 - tt
    let q = 1.0'f32 - tt
    let px = q * q * bx + 2.0'f32 * q * tt * cxp + tt * tt * ox
    let py = q * q * by + 2.0'f32 * q * tt * (by + bow) + tt * tt * oy
    let col = colorLerp(coreBlue, coreOrange, tt)
    let edgeFade = sin(tt * PI)
    drawGlow(vec2(px, py), 8.0'f32 * u, withAlpha(col, 110.0'f32 * edgeFade))
    drawDisc(vec2(px, py), max(0.5'f32, 1.8'f32 * u), withAlpha(col, 230.0'f32 * edgeFade))

# ---------------------------------------------------------------------------
# Kernel Panic (horror)
# ---------------------------------------------------------------------------

proc drawHorrorFx(w, h, time: float32) =
  ## A suffocating dark room: one bare bulb swinging over the cube, failing
  ## now and then, its cone the only safe place. Beyond it, a heartbeat
  ## vignette, red mist, eyes that open when the light dies, grime running
  ## down the walls, the panic log scrawled faint in the dark, and ash.
  let s = min(w, h)
  let u = unitOf(w, h)
  vGrad(0.0'f32, 0.0'f32, w, h, rgba(9, 2, 3), rgba(4, 1, 2))
  let beat = fract01(time / 1.15'f32)
  let thump = exp(-beat * 9.0'f32) + 0.6'f32 * exp(-((beat - 0.20'f32) * (beat - 0.20'f32)) * 90.0'f32)
  let pulse = clamp(thump, 0.0'f32, 1.4'f32)

  # Grime streaks running down the walls.
  for g in 0 ..< counted(18, detailOf(w, h)):
    let seed = g.float32 * 9.3'f32
    let gx = hash01(seed) * w
    let len = h * (0.15'f32 + hash01(seed + 1.0'f32) * 0.5'f32)
    let gy = hash01(seed + 2.0'f32) * h * 0.3'f32
    drawTaperedLine(vec2(gx, gy), vec2(gx + (hash01(seed + 3.0'f32) - 0.5'f32) * 6.0'f32 * u, gy + len),
                    (2.0'f32 + hash01(seed + 4.0'f32) * 5.0'f32) * u, 0.0'f32, rgba(40, 6, 8, 60), rgba(30, 4, 6, 0))

  # The bulb: its flicker drives the light, and the dark beyond it.
  let bx = w * CubeAnchorX + sin(time * 0.7'f32) * s * 0.012'f32
  let by = h * 0.12'f32
  let dropout = fract01(time * 0.23'f32) < 0.07'f32
  let stutter = hash01(floor(time * 18.0'f32)) > 0.9'f32
  let light = (if dropout: 0.08'f32 elif stutter: 0.45'f32 else: 1.0'f32) *
              (0.9'f32 + 0.1'f32 * sin(time * 9.0'f32))
  drawStroke(vec2(w * CubeAnchorX, 0.0'f32), vec2(bx, by), max(0.5'f32, 1.0'f32 * u), rgba(20, 16, 16))
  let floorY = h * 0.86'f32
  let coneW = s * 0.36'f32
  drawLightCone(vec2(bx, by), floorY, coneW, rgba(220, 200, 140, int(90.0'f32 * light)), 0.25'f32,
                topHalf = s * 0.012'f32)
  drawGlow(vec2(bx, floorY), coneW * 1.1'f32, s * 0.06'f32, rgba(210, 190, 130, int(60.0'f32 * light)))
  drawGlow(vec2(bx, by), s * 0.25'f32, rgba(230, 210, 150, int(60.0'f32 * light)))
  drawGlow(vec2(bx, by), s * 0.04'f32, rgba(255, 240, 190, int(200.0'f32 * light)))
  drawDisc(vec2(bx, by + s * 0.004'f32), max(0.6'f32, s * 0.011'f32), rgba(255, 245, 210, int(80.0'f32 + 175.0'f32 * light)))
  # Dust turning in the cone.
  for d in 0 ..< counted(26, detailOf(w, h)):
    let seed = d.float32 * 4.7'f32
    let t = fract01(hash01(seed) + time * (0.02'f32 + hash01(seed + 1.0'f32) * 0.03'f32))
    let dy = by + (floorY - by) * t
    let spread = (dy - by) / (floorY - by) * coneW
    let dx = bx + (hash01(seed + 2.0'f32) - 0.5'f32) * 2.0'f32 * spread * 0.85'f32 + sin(time * 0.5'f32 + seed) * 4.0'f32 * u
    drawDisc(vec2(dx, dy), max(0.35'f32, 0.9'f32 * u), rgba(240, 220, 170, int(90.0'f32 * light * sin(t * PI))))

  # The panic log, scrawled faint across the dark.
  let fs = int32(clamp(s * 0.018'f32, 0.0'f32, 14.0'f32))
  if fs >= 7:
    const Log = ["kernel panic - not syncing: attempted to kill init!",
                 "CPU: 0 PID: 1 Comm: cube Tainted: G  D",
                 "Call Trace:",
                 " <IRQ> fear_handler+0x2f/0x40",
                 " ? dread_tick+0x13/0x1f",
                 "---[ end kernel panic ]---"]
    for i, line in Log:
      let jitter = if hash01(floor(time * 6.0'f32) + i.float32 * 3.0'f32) > 0.92'f32: 6.0'f32 * u else: 0.0'f32
      let a = 30.0'f32 + 20.0'f32 * sin(time * 0.7'f32 + i.float32)
      drawText(line, int32(w * 0.24'f32 + jitter), int32(h * 0.66'f32 + i.float32 * fs.float32 * 1.4'f32),
               fs, rgba(170, 20, 24, int(a)))

  # Heartbeat vignette, closing in on each thump.
  let va = 150.0'f32 + pulse * 70.0'f32
  edgeVignette(w, h, 0.32'f32 + pulse * 0.05'f32, rgba(0, 0, 0, int(va)))

  # Blood mist creeping along the floor.
  for m in 0 ..< 6:
    let seed = m.float32 * 27.3'f32
    let mx = wrapCoord(hash01(seed) * w + time * (8.0'f32 + hash01(seed + 1.0'f32) * 14.0'f32) * u, w * 1.4'f32) - w * 0.2'f32
    let my = (0.6'f32 + hash01(seed + 2.0'f32) * 0.35'f32) * h + sin(time * 0.3'f32 + seed) * h * 0.03'f32
    let mr = s * (0.14'f32 + hash01(seed + 3.0'f32) * 0.14'f32)
    let ma = 40.0'f32 + 26.0'f32 * (sin(time * 0.5'f32 + seed) * 0.5'f32 + 0.5'f32)
    drawGlow(vec2(mx, my), mr * 1.6'f32, mr * 0.7'f32, rgba(130, 8, 12, int(ma)))

  # Eyes in the dark, bolder when the bulb fails, never inside its cone.
  let dark = 1.25'f32 - light * 0.45'f32
  for e in 0 ..< 6:
    let seed = e.float32 * 41.7'f32 + 3.0'f32
    let cycle = 6.0'f32 + hash01(seed) * 5.0'f32
    let ph = fract01(time / cycle + hash01(seed + 9.0'f32))
    if ph >= 0.5'f32: continue
    let vis = sin(ph / 0.5'f32 * PI)
    if vis <= 0.02'f32: continue
    let ex = (0.1'f32 + hash01(seed + 1.0'f32) * 0.8'f32) * w
    let ey = (0.12'f32 + hash01(seed + 2.0'f32) * 0.68'f32) * h
    let coneHalf = if ey > by: (ey - by) / (floorY - by) * coneW else: 0.0'f32
    if abs(ex - bx) < coneHalf + s * 0.06'f32: continue
    let gap = s * (0.013'f32 + hash01(seed + 4.0'f32) * 0.01'f32)
    let er = s * 0.008'f32
    let blink = if fract01(time * 0.7'f32 + seed) > 0.93'f32: 0.12'f32 else: 1.0'f32
    let look = sin(time * 0.6'f32 + seed) * gap * 0.3'f32
    let col = if hash01(seed + 5.0'f32) > 0.6'f32: rgba(255, 40, 24) else: rgba(225, 215, 110)
    let a = 235.0'f32 * vis * min(1.0'f32, dark)
    for side in [-1.0'f32, 1.0'f32]:
      let p = vec2(ex + side * gap + look, ey)
      drawGlow(p, er * 7.0'f32, withAlpha(col, a * 0.35'f32))
      drawRadialGradient(p, er * 1.5'f32, max(0.3'f32, er * 0.75'f32 * blink),
                         withAlpha(colorLerp(col, rgba(255, 255, 255), 0.4'f32), a), withAlpha(col, a * 0.8'f32), reSmooth)
      fillEllipse(vec2(p.x + look * 0.3'f32, p.y), er * 0.3'f32, max(0.3'f32, er * 0.65'f32 * blink), rgba(10, 2, 2, int(a)))

  # Ash drifting down through everything.
  let span = h + 40.0'f32
  for d in 0 ..< counted(40, detailOf(w, h)):
    let seed = d.float32 * 6.1'f32
    let dy = wrapCoord(hash01(seed) * span + time * (h * (0.03'f32 + hash01(seed + 1.0'f32) * 0.06'f32)), span)
    let dx = hash01(seed + 2.0'f32) * w + sin(time * 0.4'f32 + seed) * w * 0.01'f32
    drawDisc(vec2(dx, dy), max(0.35'f32, (0.8'f32 + hash01(seed + 3.0'f32)) * u), rgba(90, 80, 80, 70))

# ---------------------------------------------------------------------------
# Cyberspace
# ---------------------------------------------------------------------------

proc drawCyberFx(w, h, time: float32) =
  ## A hacking console rather than a synthwave street: a faint hex lattice,
  ## Manhattan-routed neon traces with pads and comet-tailed data pulses,
  ## floating holographic HUD panels, chromatic glitch slices, rain streaks
  ## and CRT scanlines. Cyan/magenta duotone throughout.
  let cyan = rgba(80, 245, 255)
  let mag = rgba(255, 60, 200)
  let s = min(w, h)
  let u = unitOf(w, h)
  vGrad(0.0'f32, 0.0'f32, w, h, rgba(2, 12, 22), rgba(6, 4, 18))
  drawGlow(vec2(w * 0.3'f32, h * 0.3'f32), s * 0.6'f32, rgba(0, 120, 160, 50))
  drawGlow(vec2(w * 0.75'f32, h * 0.75'f32), s * 0.6'f32, rgba(140, 0, 120, 46))

  # Hex lattice, brightest around the cube.
  let hr = max(3.0'f32, s * 0.05'f32 / detailOf(w, h))
  let colsN = int(w / (hr * 1.5'f32)) + 2
  let rowsN = int(h / (hr * 1.732'f32)) + 2
  for c in 0 ..< colsN:
    for r in 0 ..< rowsN:
      let hx = c.float32 * hr * 1.5'f32
      let hy = r.float32 * hr * 1.732'f32 + (if (c and 1) == 1: hr * 0.866'f32 else: 0.0'f32)
      let dx = (hx - w * CubeAnchorX) / s
      let dy = (hy - h * CubeAnchorY) / s
      let near = clamp(1.0'f32 - sqrt(dx * dx + dy * dy) * 1.3'f32, 0.0'f32, 1.0'f32)
      let a = 8.0'f32 + near * 26.0'f32
      drawPolyOutline(vec2(hx, hy), 6, hr * 0.96'f32, 0.0'f32, rgba(60, 200, 255, int(a)))

  # Circuit traces: orthogonal polylines with node pads and a data pulse.
  let pad = max(1.2'f32, s * 0.007'f32)
  for ti in 0 ..< 10:
    let seed = ti.float32 * 21.7'f32
    let tint = if ti mod 2 == 0: cyan else: mag
    var pts: array[5, Vector2]
    let np = 4 + (if hash01(seed + 7.0'f32) > 0.5'f32: 1 else: 0)
    let edge = int(hash01(seed + 1.0'f32) * 4.0'f32) mod 4
    var horiz: bool
    case edge
    of 0: pts[0] = vec2(0.0'f32, hash01(seed + 2.0'f32) * h); horiz = true
    of 1: pts[0] = vec2(hash01(seed + 2.0'f32) * w, 0.0'f32); horiz = false
    of 2: pts[0] = vec2(w, hash01(seed + 2.0'f32) * h); horiz = true
    else: pts[0] = vec2(hash01(seed + 2.0'f32) * w, h); horiz = false
    for k in 1 ..< np:
      let prev = pts[k - 1]
      let stepLen = 0.12'f32 + hash01(seed + k.float32 * 3.3'f32) * 0.26'f32
      let dir = if hash01(seed + k.float32 * 3.3'f32 + 1.5'f32) > 0.5'f32: 1.0'f32 else: -1.0'f32
      if horiz:
        pts[k] = vec2(clamp(prev.x + dir * stepLen * w, 0.0'f32, w), prev.y)
      else:
        pts[k] = vec2(prev.x, clamp(prev.y + dir * stepLen * h, 0.0'f32, h))
      horiz = not horiz
    for k in 0 ..< (np - 1):
      drawSoftLine(pts[k], pts[k + 1], u, withAlpha(tint, 60'u8), withAlpha(tint, 170'u8), 8.0'f32, 1.3'f32)
    for k in 0 ..< np:
      drawGlow(pts[k], pad * 4.0'f32, withAlpha(tint, 70'u8))
      fillRect(pts[k].x - pad, pts[k].y - pad, pad * 2.0'f32, pad * 2.0'f32, withAlpha(tint, 220'u8))
      fillRect(pts[k].x - pad * 0.45'f32, pts[k].y - pad * 0.45'f32, pad * 0.9'f32, pad * 0.9'f32, rgba(4, 10, 20))
    let segCount = np - 1
    let tt = fract01(time * (0.18'f32 + hash01(seed + 5.0'f32) * 0.12'f32)) * segCount.float32
    let si = min(segCount - 1, int(tt))
    let lf = tt - si.float32
    let a = pts[si]
    let b = pts[si + 1]
    let pp = vec2(a.x + (b.x - a.x) * lf, a.y + (b.y - a.y) * lf)
    let tl = max(0.0'f32, lf - 0.3'f32)
    let tq = vec2(a.x + (b.x - a.x) * tl, a.y + (b.y - a.y) * tl)
    drawTaperedLine(tq, pp, 0.0'f32, max(0.8'f32, 3.0'f32 * u), withAlpha(tint, 0'u8), rgba(255, 255, 255, 230))
    drawGlow(pp, s * 0.03'f32, withAlpha(tint, 170'u8))
    drawDisc(pp, max(0.8'f32, s * 0.004'f32), rgba(255, 255, 255, 240))

  # Floating holographic HUD panels: header strip, live bars, a sparkline.
  for pi in 0 ..< 3:
    let seed = pi.float32 * 47.3'f32 + 4.0'f32
    let pw = w * (0.10'f32 + hash01(seed) * 0.06'f32)
    let ph = h * (0.08'f32 + hash01(seed + 1.0'f32) * 0.05'f32)
    let px = w * 0.25'f32 + hash01(seed + 2.0'f32) * (w * 0.66'f32 - pw)
    let py = (0.10'f32 + hash01(seed + 3.0'f32) * 0.70'f32) * (h - ph) + sin(time * 0.6'f32 + seed) * h * 0.006'f32
    let tint = if pi mod 2 == 0: cyan else: mag
    let flick = if hash01(floor(time * 9.0'f32) + seed) > 0.95'f32: 0.4'f32 else: 1.0'f32
    vGrad(px, py, pw, ph, withAlpha(tint, 34.0'f32 * flick), withAlpha(tint, 10.0'f32 * flick))
    fillRect(px, py, pw, max(0.8'f32, ph * 0.14'f32), withAlpha(tint, 90.0'f32 * flick))
    let bl = min(pw, ph) * 0.28'f32
    for cx2 in [0.0'f32, 1.0'f32]:
      for cy2 in [0.0'f32, 1.0'f32]:
        let cxp = px + cx2 * pw
        let cyp = py + cy2 * ph
        let sx = if cx2 < 0.5'f32: 1.0'f32 else: -1.0'f32
        let sy = if cy2 < 0.5'f32: 1.0'f32 else: -1.0'f32
        drawStroke(vec2(cxp, cyp), vec2(cxp + sx * bl, cyp), max(0.6'f32, 1.6'f32 * u), withAlpha(tint, 230.0'f32 * flick))
        drawStroke(vec2(cxp, cyp), vec2(cxp, cyp + sy * bl), max(0.6'f32, 1.6'f32 * u), withAlpha(tint, 230.0'f32 * flick))
    for r in 0 ..< 3:
      let byy = py + ph * (0.3'f32 + r.float32 * 0.17'f32)
      let frac = 0.3'f32 + 0.6'f32 * (sin(time * 1.5'f32 + seed + r.float32 * 1.3'f32) * 0.5'f32 + 0.5'f32)
      let barH = max(0.6'f32, ph * 0.07'f32)
      fillRect(px + pw * 0.1'f32, byy, pw * 0.5'f32, barH, withAlpha(tint, 40.0'f32 * flick))
      fillRect(px + pw * 0.1'f32, byy, pw * 0.5'f32 * frac, barH, withAlpha(tint, 170.0'f32 * flick))
    var prev = vec2(px + pw * 0.66'f32, py + ph * 0.75'f32)
    for k in 1 .. 8:
      let gx = px + pw * (0.66'f32 + k.float32 / 8.0'f32 * 0.28'f32)
      let gy = py + ph * (0.75'f32 - 0.4'f32 * (sin(time * 2.0'f32 + k.float32 * 0.9'f32 + seed) * 0.5'f32 + 0.5'f32))
      drawStroke(prev, vec2(gx, gy), max(0.5'f32, 1.0'f32 * u), withAlpha(tint, 200.0'f32 * flick))
      prev = vec2(gx, gy)

  # Rain streaks, slanting slightly.
  for r in 0 ..< counted(50, detailOf(w, h)):
    let seed = r.float32 * 3.91'f32
    let speed = h * (0.5'f32 + hash01(seed) * 0.5'f32)
    let ry = wrapCoord(hash01(seed + 1.0'f32) * h * 1.2'f32 + time * speed, h * 1.2'f32) - h * 0.1'f32
    let rx = wrapCoord(hash01(seed + 2.0'f32) * w + ry * 0.08'f32, w)
    let len = (12.0'f32 + hash01(seed + 3.0'f32) * 16.0'f32) * u
    let col = if r mod 3 == 0: mag else: cyan
    drawTaperedLine(vec2(rx - len * 0.08'f32, ry - len), vec2(rx, ry), 0.0'f32, max(0.5'f32, 0.9'f32 * u),
                    withAlpha(col, 0'u8), withAlpha(col, 60'u8))

  # Rare chromatic-aberration glitch slice.
  let gphase = fract01(time * 0.5'f32)
  if gphase < 0.10'f32:
    let f = sin(gphase / 0.10'f32 * PI)
    let sliceY = hash01(floor(time * 0.5'f32)) * h
    let sliceH = h * 0.04'f32
    let off = w * 0.012'f32 * f
    fillRect(-off, sliceY, w, max(0.6'f32, sliceH), rgba(0, 245, 255, int(45.0'f32 * f)))
    fillRect(off, sliceY + sliceH * 0.4'f32, w, max(0.6'f32, sliceH * 0.7'f32), rgba(255, 60, 200, int(45.0'f32 * f)))

  # Faint CRT scanlines.
  var y = 0.0'f32
  let step = max(2.0'f32, 3.0'f32 * u)
  while y < h:
    fillRect(0.0'f32, y, w, max(0.5'f32, step * 0.34'f32), rgba(0, 0, 0, 30))
    y += step
  edgeVignette(w, h, 0.2'f32, rgba(0, 0, 0, 110))

# ---------------------------------------------------------------------------
# High Roller (casino)
# ---------------------------------------------------------------------------

proc drawHeartSuit(cx, cy, r: float32, col: Color) =
  let cen = vec2(cx, cy)
  var prev = cen
  for i in 0 .. 26:
    let t = i.float32 / 26.0'f32 * PI * 2.0'f32
    let hx = 16.0'f32 * pow(sin(t), 3.0'f32)
    let hy = 13.0'f32 * cos(t) - 5.0'f32 * cos(2.0'f32 * t) - 2.0'f32 * cos(3.0'f32 * t) - cos(4.0'f32 * t)
    let p = vec2(cx + hx / 17.0'f32 * r, cy - hy / 17.0'f32 * r)
    if i > 0: drawTri2(cen, prev, p, col)
    prev = p

proc drawSpadeSuit(cx, cy, r: float32, col: Color) =
  # An inverted heart (point up) with a small stem.
  let cen = vec2(cx, cy)
  var prev = cen
  for i in 0 .. 26:
    let t = i.float32 / 26.0'f32 * PI * 2.0'f32
    let hx = 16.0'f32 * pow(sin(t), 3.0'f32)
    let hy = 13.0'f32 * cos(t) - 5.0'f32 * cos(2.0'f32 * t) - 2.0'f32 * cos(3.0'f32 * t) - cos(4.0'f32 * t)
    let p = vec2(cx + hx / 17.0'f32 * r, cy + hy / 17.0'f32 * r)
    if i > 0: drawTri2(cen, prev, p, col)
    prev = p
  drawTri2(vec2(cx, cy + r * 0.15'f32), vec2(cx - r * 0.32'f32, cy + r * 0.66'f32),
           vec2(cx + r * 0.32'f32, cy + r * 0.66'f32), col)

proc drawDiamondSuit(cx, cy, r: float32, col: Color) =
  drawTri2(vec2(cx, cy - r), vec2(cx - r * 0.72'f32, cy), vec2(cx + r * 0.72'f32, cy), col)
  drawTri2(vec2(cx, cy + r), vec2(cx - r * 0.72'f32, cy), vec2(cx + r * 0.72'f32, cy), col)

proc drawClubSuit(cx, cy, r: float32, col: Color) =
  let cr = r * 0.44'f32
  drawDisc(vec2(cx, cy - r * 0.34'f32), cr, col)
  drawDisc(vec2(cx - r * 0.42'f32, cy + r * 0.14'f32), cr, col)
  drawDisc(vec2(cx + r * 0.42'f32, cy + r * 0.14'f32), cr, col)
  drawTri2(vec2(cx, cy + r * 0.02'f32), vec2(cx - r * 0.30'f32, cy + r * 0.70'f32),
           vec2(cx + r * 0.30'f32, cy + r * 0.70'f32), col)

proc drawSuitAt(kind: int, cx, cy, r: float32, col: Color) =
  ## One of the four card suits by index (0 heart, 1 diamond, 2 spade, 3 club).
  case kind and 3
  of 0: drawHeartSuit(cx, cy, r, col)
  of 1: drawDiamondSuit(cx, cy, r, col)
  of 2: drawSpadeSuit(cx, cy, r, col)
  else: drawClubSuit(cx, cy, r, col)

proc drawChipStack(cx, cyBase, r: float32, count: int, base: Color, time, seed: float32) =
  ## A side-on stack of poker chips: each chip's rim darker below, edge spots
  ## around it, and a lit top face with its inlay.
  let rv = r * 0.42'f32
  let chipH = rv * 0.78'f32
  let bob = sin(time * 1.1'f32 + seed) * r * 0.06'f32
  let edgeLo = colorLerp(base, rgba(0, 0, 0, base.a.int), 0.5'f32)
  let band = colorLerp(base, rgba(245, 245, 248, base.a.int), 0.28'f32)
  let white = rgba(240, 240, 244, base.a.int)
  fillEllipse(vec2(cx, cyBase + bob + chipH * 0.9'f32), r * 1.15'f32, rv * 1.2'f32, rgba(0, 0, 0, 90))
  for k in 0 ..< count:
    let cy = cyBase + bob - k.float32 * chipH
    fillEllipse(vec2(cx, cy + chipH * 0.55'f32), r, rv, edgeLo)
    fillEllipse(vec2(cx, cy), r, rv, (if (k and 1) == 0: base else: band))
  let topY = cyBase + bob - count.float32 * chipH
  drawRadialGradient(vec2(cx, topY), r, rv, brighten(base, 30.0'f32), base, reSmooth)
  fillEllipse(vec2(cx, topY), r * 0.62'f32, rv * 0.62'f32, withAlpha(white, clampByteF(0.42'f32 * base.a.float32)))
  fillEllipse(vec2(cx, topY), r * 0.5'f32, rv * 0.5'f32, base)
  for kk in 0 ..< 6:
    let a = kk.float32 / 6.0'f32 * PI * 2.0'f32 + time * 0.2'f32 + seed
    drawDisc(vec2(cx + cos(a) * r * 0.8'f32, topY + sin(a) * rv * 0.8'f32), r * 0.12'f32, white)

proc drawPlayingCard(cx, cy, cw, ch: float32, suit: int, suitRed: bool) =
  ## An upright playing card: a soft shadow, a cream face lit from above, a
  ## centre pip and a corner pip.
  let sc = if suitRed: rgba(200, 36, 48) else: rgba(24, 24, 30)
  let x = cx - cw * 0.5'f32
  let y = cy - ch * 0.5'f32
  drawGlow(vec2(cx + cw * 0.08'f32, cy + ch * 0.1'f32), cw * 0.9'f32, ch * 0.75'f32, rgba(0, 0, 0, 110))
  fillRect(x - 1.0'f32, y - 1.0'f32, cw + 2.0'f32, ch + 2.0'f32, rgba(206, 200, 188))
  vGrad(x, y, cw, ch, rgba(250, 248, 242), rgba(226, 222, 212))
  drawSuitAt(suit, cx, cy, min(cw, ch) * 0.32'f32, sc)
  drawSuitAt(suit, cx - cw * 0.32'f32, cy - ch * 0.32'f32, min(cw, ch) * 0.13'f32, sc)

proc drawCasinoFx(w, h, time: float32) =
  ## A poker table under a hanging lamp: a cushioned leather rail with a gold
  ## trim, felt lit from above, gold betting arcs and inlaid suits, chips and
  ## two hole cards on the near felt, lucky suits drifting up and gold dust.
  ## The centre stays clear: the cube, its gold orbit rings and the dice-roll
  ## number all render there on top.
  let red = rgba(215, 32, 48)
  let gold = rgba(255, 205, 70)
  let s = min(w, h)
  let u = unitOf(w, h)
  let tcx = w * CubeAnchorX
  let tcy = h * CubeAnchorY
  let trh = s * 0.55'f32
  let trv = s * 0.42'f32
  let c = vec2(tcx, tcy)

  vGrad(0.0'f32, 0.0'f32, w, h, rgba(14, 22, 17), rgba(3, 6, 5))
  drawGlow(vec2(tcx, tcy - trv * 0.3'f32), trh * 1.5'f32, trv * 1.4'f32, rgba(255, 220, 150, 40))
  drawGlow(vec2(tcx, tcy + trv * 0.18'f32), trh * 1.25'f32, trv * 1.3'f32, rgba(0, 0, 0, 170))

  # The rail: a cushion shaded dark-lit-dark across its width, and the lamp's
  # highlight along its far side.
  let railIn = s * 0.014'f32
  let railOut = s * 0.055'f32
  let railMid = (railIn + railOut) * 0.5'f32
  drawGradientRing(c, trh + railIn, trv + railIn, trh + railMid, trv + railMid, rgba(26, 14, 7), rgba(92, 56, 30))
  drawGradientRing(c, trh + railMid, trv + railMid, trh + railOut, trv + railOut, rgba(92, 56, 30), rgba(34, 18, 9))
  drawGlow(vec2(tcx, tcy - trv - railMid), trh * 0.7'f32, s * 0.02'f32, rgba(255, 220, 170, 70))
  fillEllipse(c, trh + railIn, trv + railIn, rgba(20, 11, 6))
  drawEllipseOutline(c, trh + railIn, trv + railIn, max(0.6'f32, 1.6'f32 * u), withAlpha(gold, 150'u8))

  # The felt, lit from the lamp above centre.
  fillEllipse(c, trh, trv, rgba(12, 58, 34))
  drawRadialGradient(vec2(tcx, tcy - trv * 0.1'f32), trh * 0.92'f32, trv * 0.88'f32,
                     rgba(42, 122, 76), rgba(12, 58, 34), reSmooth)
  for sp in 0 ..< counted(90, detailOf(w, h)):
    let seed = sp.float32 * 3.3'f32 + 50.0'f32
    let a = hash01(seed) * PI * 2.0'f32
    let rr = sqrt(hash01(seed + 1.0'f32)) * 0.95'f32
    drawDisc(vec2(tcx + cos(a) * trh * rr, tcy + sin(a) * trv * rr), max(0.35'f32, 0.7'f32 * u),
             (if (sp and 1) == 0: rgba(0, 0, 0, 22) else: rgba(120, 200, 150, 18)))

  # Gold betting arcs and inlaid suits.
  drawEllipseOutline(c, trh * 0.8'f32, trv * 0.8'f32, max(0.5'f32, 1.4'f32 * u), withAlpha(gold, 160'u8))
  drawEllipseOutline(c, trh * 0.8'f32 + 3.0'f32 * u, trv * 0.8'f32 + 3.0'f32 * u, max(0.4'f32, 0.8'f32 * u), withAlpha(gold, 80'u8))
  drawEllipseOutline(c, trh * 0.6'f32, trv * 0.6'f32, max(0.4'f32, 0.9'f32 * u), withAlpha(gold, 60'u8))
  for k in 0 ..< 4:
    let a = k.float32 * (PI * 0.5'f32) - PI * 0.5'f32
    let col = if k < 2: red else: gold
    drawSuitAt(k, tcx + cos(a) * trh * 0.7'f32, tcy + sin(a) * trv * 0.7'f32, s * 0.022'f32, withAlpha(col, 105'u8))

  # The lamp: a green glass shade hanging over the table, its light falling.
  let lampY = s * 0.04'f32
  let shadeW = s * 0.16'f32
  let shadeH = s * 0.05'f32
  drawStroke(vec2(tcx, 0.0'f32), vec2(tcx, lampY), max(0.5'f32, 1.2'f32 * u), rgba(30, 30, 30))
  drawLightCone(vec2(tcx, lampY + shadeH), tcy + trv * 0.5'f32, shadeW * 3.6'f32, rgba(255, 230, 160, 60),
                0.0'f32, 0.0'f32, shadeW * 0.5'f32)
  drawGradientQuad(vec2(tcx - shadeW * 0.3'f32, lampY), vec2(tcx - shadeW * 0.5'f32, lampY + shadeH),
                   vec2(tcx + shadeW * 0.5'f32, lampY + shadeH), vec2(tcx + shadeW * 0.3'f32, lampY),
                   rgba(30, 90, 50), rgba(12, 50, 26), rgba(12, 50, 26), rgba(30, 90, 50))
  drawStroke(vec2(tcx - shadeW * 0.5'f32, lampY + shadeH), vec2(tcx + shadeW * 0.5'f32, lampY + shadeH),
             max(0.6'f32, 1.6'f32 * u), withAlpha(gold, 200'u8))
  drawGlow(vec2(tcx, lampY + shadeH), shadeW * 0.7'f32, s * 0.02'f32, rgba(255, 236, 180, 200))

  # Lucky suits drifting up and swaying, fading as they rise.
  for i in 0 ..< 11:
    let seed = i.float32 * 12.3'f32
    let span = h + 60.0'f32
    let yy = h + 30.0'f32 - wrapCoord(hash01(seed) * span + time * (h * (0.02'f32 + hash01(seed + 1.0'f32) * 0.045'f32)), span)
    let xx = hash01(seed + 2.0'f32) * w + sin(time * 0.4'f32 + seed) * w * 0.02'f32
    let sr = s * (0.015'f32 + hash01(seed + 3.0'f32) * 0.013'f32)
    let fadeK = clamp(yy / h * 1.15'f32, 0.0'f32, 1.0'f32)
    let a = clampByteF(26.0'f32 + 80.0'f32 * fadeK)
    case i mod 4
    of 0: drawHeartSuit(xx, yy, sr, withAlpha(red, a))
    of 1: drawDiamondSuit(xx, yy, sr, withAlpha(red, a))
    of 2: drawSpadeSuit(xx, yy, sr, withAlpha(gold, a))
    else: drawClubSuit(xx, yy, sr, withAlpha(gold, a))

  # Two hole cards and the chip stacks along the near rail.
  let cardW = s * 0.072'f32
  let cardH = s * 0.104'f32
  drawPlayingCard(tcx - trh * 0.36'f32, tcy + trv * 0.6'f32, cardW, cardH, 2, false)
  drawPlayingCard(tcx - trh * 0.36'f32 + cardW * 0.6'f32, tcy + trv * 0.56'f32, cardW, cardH, 0, true)
  let chipCols = [rgba(200, 40, 50), rgba(40, 90, 200), rgba(28, 28, 34), rgba(230, 180, 50), rgba(30, 140, 90)]
  for ci in 0 ..< 5:
    let seed = ci.float32 * 17.3'f32 + 3.0'f32
    let ang = PI * (0.58'f32 + 0.34'f32 * (ci.float32 / 4.0'f32))
    drawChipStack(tcx + cos(ang) * trh * 0.86'f32, tcy + sin(ang) * trv * 0.86'f32, s * 0.028'f32,
                  3 + (ci mod 3), chipCols[ci mod chipCols.len], time, seed)

  # Gold dust twinkling in the lamplight.
  for sp in 0 ..< counted(24, detailOf(w, h)):
    let seed = sp.float32 * 8.7'f32 + 2.0'f32
    let p = vec2(hash01(seed) * w, hash01(seed + 1.0'f32) * h)
    let tw = sin(time * (1.5'f32 + hash01(seed + 2.0'f32) * 2.5'f32) + seed) * 0.5'f32 + 0.5'f32
    let r = max(0.35'f32, (0.6'f32 + hash01(seed + 3.0'f32) * 1.2'f32) * (0.5'f32 + tw) * u)
    drawGlow(p, r * 5.0'f32, rgba(255, 215, 110, int(tw * 60.0'f32)))
    drawDisc(p, r, rgba(255, 225, 140, int(30.0'f32 + tw * 160.0'f32)))
  edgeVignette(w, h, 0.22'f32, rgba(0, 0, 0, 130))

# ---------------------------------------------------------------------------
# Dragon's Lair
# ---------------------------------------------------------------------------

proc drawRune(cx, cy, r: float32, col: Color) =
  ## A simple angular ward-glyph: a diamond outline crossed by a vertical
  ## tick, built from line primitives so it survives the small shop preview.
  let top = vec2(cx, cy - r)
  let right = vec2(cx + r * 0.7'f32, cy)
  let bot = vec2(cx, cy + r)
  let left = vec2(cx - r * 0.7'f32, cy)
  drawStroke(top, right, 1.4'f32, col)
  drawStroke(right, bot, 1.4'f32, col)
  drawStroke(bot, left, 1.4'f32, col)
  drawStroke(left, top, 1.4'f32, col)
  drawStroke(vec2(cx, cy - r * 1.35'f32), vec2(cx, cy + r * 1.35'f32), 1.2'f32, col)

proc drawDragonGameCard(cx, cy, cw, ch: float32, accent, ink: Color) =
  ## A fantasy ability card resting on the table. Axis-aligned, because the
  ## scene also renders in the small shop card where rotated rects get muddy.
  let edge = rgba(84, 48, 24, 245)
  drawGlow(vec2(cx + cw * 0.1'f32, cy + ch * 0.1'f32), cw * 0.85'f32, ch * 0.7'f32, rgba(0, 0, 0, 120))
  fillRect(cx - cw * 0.5'f32 - 1.0'f32, cy - ch * 0.5'f32 - 1.0'f32, cw + 2.0'f32, ch + 2.0'f32, edge)
  vGrad(cx - cw * 0.5'f32, cy - ch * 0.5'f32, cw, ch, rgba(238, 214, 158, 248), rgba(214, 186, 128, 248))
  drawRectOutline(int32(cx - cw * 0.41'f32), int32(cy - ch * 0.39'f32),
                  int32(cw * 0.82'f32), int32(ch * 0.78'f32), withAlpha(edge, 150'u8))
  drawRune(cx, cy - ch * 0.12'f32, min(cw, ch) * 0.18'f32, accent)
  drawStroke(vec2(cx - cw * 0.28'f32, cy + ch * 0.18'f32), vec2(cx + cw * 0.28'f32, cy + ch * 0.18'f32), 1.0'f32, ink)
  drawStroke(vec2(cx - cw * 0.22'f32, cy + ch * 0.28'f32), vec2(cx + cw * 0.22'f32, cy + ch * 0.28'f32), 1.0'f32,
             withAlpha(ink, 150'u8))

proc drawDragonToken(cx, cy, r, time, seed: float32, base, rim: Color) =
  ## A chunky wooden token, top-lit and stamped with a tiny rune.
  let bob = sin(time * 0.7'f32 + seed) * r * 0.05'f32
  fillEllipse(vec2(cx, cy + bob + r * 0.22'f32), r * 1.02'f32, r * 0.34'f32, rgba(0, 0, 0, 85))
  drawRadialGradient(vec2(cx - r * 0.2'f32, cy + bob - r * 0.2'f32), r * 1.15'f32, r * 1.15'f32,
                     brighten(base, 40.0'f32), base, reSmooth)
  fillEllipse(vec2(cx, cy + bob), r, r, base)
  drawRadialGradient(vec2(cx - r * 0.2'f32, cy + bob - r * 0.22'f32), r * 0.75'f32, r * 0.75'f32,
                     brighten(base, 45.0'f32), withAlpha(base, 0'u8), reSmooth)
  drawCircleOutline(vec2(cx, cy + bob), r, rim)
  drawRune(cx, cy + bob, r * 0.36'f32, withAlpha(rim, 170'u8))

proc drawDragonMini(cx, cy, s: float32, body, rim, ember: Color) =
  ## A tiny dragon miniature silhouette for the board.
  fillEllipse(vec2(cx, cy + s * 0.34'f32), s * 0.42'f32, s * 0.16'f32, rgba(0, 0, 0, 80))
  drawDisc(vec2(cx, cy), s * 0.32'f32, body)
  drawDisc(vec2(cx + s * 0.34'f32, cy - s * 0.12'f32), s * 0.18'f32, body)
  drawTri2(vec2(cx - s * 0.08'f32, cy - s * 0.12'f32), vec2(cx - s * 0.58'f32, cy - s * 0.42'f32),
           vec2(cx - s * 0.28'f32, cy + s * 0.04'f32), withAlpha(body, 230'u8))
  drawTri2(vec2(cx + s * 0.08'f32, cy - s * 0.12'f32), vec2(cx + s * 0.48'f32, cy - s * 0.48'f32),
           vec2(cx + s * 0.36'f32, cy + s * 0.02'f32), withAlpha(body, 230'u8))
  drawTri2(vec2(cx + s * 0.42'f32, cy - s * 0.24'f32), vec2(cx + s * 0.62'f32, cy - s * 0.34'f32),
           vec2(cx + s * 0.50'f32, cy - s * 0.12'f32), rim)
  drawDisc(vec2(cx + s * 0.40'f32, cy - s * 0.16'f32), max(0.8'f32, s * 0.035'f32), ember)

proc drawHexMapCell(cx, cy, r: float32, fill, line: Color) =
  if fill.a > 0'u8:
    drawPoly(vec2(cx, cy), 6, r, 30.0'f32, fill)
  drawPolyOutline(vec2(cx, cy), 6, r, 30.0'f32, line)

proc edgeX(localX, w, side: float32): float32 =
  ## Folds a coordinate measured inward from a screen edge to actual screen x:
  ## side<0 anchors to the left edge, side>0 mirrors the same plan to the right.
  if side < 0.0'f32: localX else: w - localX

proc drawDragonWing(shoulderX, shoulderY, s, time, side, seed: float32,
                    membrane, rim, ember: Color) =
  ## A bat-style wing mantled above the shoulder: five finger-bone struts sweep
  ## through the outward side (never crossing in front of the head or neck)
  ## from a trailing edge drooping outward-and-down to a leading edge sweeping
  ## outward-and-up. Each bay between two struts is two triangles meeting at a
  ## scallop point pulled back toward the shoulder, so the trailing edge dips
  ## between the bones like a real membrane; the fill is lightest near the
  ## struts and a faint warm glow bleeds through the web. `s` is min(w,h), the
  ## body's own scale, so the wing stays in proportion on wide screens.
  const Struts = 5
  let inward = if side < 0.0'f32: 1.0'f32 else: -1.0'f32
  let flex = 1.0'f32 + 0.05'f32 * sin(time * 0.35'f32 + seed)
  let shoulder = vec2(shoulderX, shoulderY)
  var tip: array[Struts, Vector2]
  for i in 0 ..< Struts:
    let f = i.float32 / (Struts - 1).float32
    let ang = 2.4'f32 + f * 1.98'f32
    let len = s * (0.12'f32 + f * 0.095'f32) * flex
    tip[i] = vec2(shoulderX + cos(ang) * len * inward, shoulderY + sin(ang) * len)

  proc dipOf(i: int): Vector2 =
    let mid = vec2((tip[i].x + tip[i + 1].x) * 0.5'f32, (tip[i].y + tip[i + 1].y) * 0.5'f32)
    vec2(mid.x + (shoulderX - mid.x) * 0.20'f32, mid.y + (shoulderY - mid.y) * 0.20'f32)

  drawGlow(vec2((shoulderX + tip[Struts div 2].x) * 0.5'f32, (shoulderY + tip[Struts div 2].y) * 0.5'f32),
           s * 0.12'f32, withAlpha(ember, 40'u8))
  for i in 0 ..< (Struts - 1):
    let f = (i.float32 + 0.5'f32) / (Struts - 1).float32
    let lit = colorLerp(membrane, rim, 0.09'f32 + f * 0.05'f32)
    let dip = dipOf(i)
    drawGradientTriangle(shoulder, tip[i], dip, membrane, lit, membrane)
    drawGradientTriangle(shoulder, dip, tip[i + 1], membrane, membrane, lit)
  for i in 0 ..< Struts:
    drawTaperedLine(shoulder, tip[i], 2.2'f32, 1.0'f32, rim, withAlpha(rim, 200'u8))
    drawDisc(tip[i], 1.6'f32, rim)
  for i in 0 ..< (Struts - 1):
    let dip = dipOf(i)
    drawStroke(tip[i], dip, 1.3'f32, withAlpha(rim, 150'u8))
    drawStroke(dip, tip[i + 1], 1.3'f32, withAlpha(rim, 150'u8))
  let lead = tip[Struts - 1]
  drawTri2(lead, vec2(lead.x + inward * s * 0.012'f32, lead.y - s * 0.004'f32),
           vec2(lead.x + inward * s * 0.028'f32, lead.y - s * 0.032'f32), rim)

proc drawDragonForeleg(hipX, hipY, s, time, side, seed: float32, body, rim: Color) =
  ## A short two-jointed foreleg dropping inward from the shoulder so a clawed
  ## hand rests over the board edge, three claws fanning off the wrist.
  let inward = if side < 0.0'f32: 1.0'f32 else: -1.0'f32
  let twitch = sin(time * 0.5'f32 + seed) * s * 0.006'f32
  let upperLen = s * 0.075'f32
  let lowerLen = s * 0.060'f32
  let hip = vec2(hipX, hipY)
  let elbow = vec2(hipX + inward * upperLen * 0.75'f32, hipY + upperLen * 0.55'f32)
  let wrist = vec2(elbow.x + inward * lowerLen * 0.55'f32 + twitch, elbow.y + lowerLen * 0.80'f32)
  let uW = s * 0.026'f32
  let lW = s * 0.019'f32
  drawTri2(vec2(hip.x - uW, hip.y), vec2(hip.x + uW, hip.y), vec2(elbow.x + inward * lW, elbow.y), body)
  drawTri2(vec2(hip.x + uW, hip.y), vec2(elbow.x + inward * lW, elbow.y), vec2(elbow.x - inward * lW, elbow.y), body)
  drawDisc(elbow, lW, body)
  drawTri2(vec2(elbow.x - inward * lW, elbow.y), vec2(elbow.x + inward * lW, elbow.y), wrist, body)
  for ck in 0 ..< 3:
    let spread = ck.float32 - 1.0'f32
    let clen = s * (0.030'f32 - abs(spread) * 0.004'f32)
    let ctip = vec2(wrist.x + inward * (0.15'f32 + spread * 0.35'f32) * clen, wrist.y + clen)
    let cw = s * 0.006'f32
    drawTri2(vec2(wrist.x - cw, wrist.y), vec2(wrist.x + cw, wrist.y), ctip, body)
    drawDisc(ctip, max(0.7'f32, s * 0.005'f32), rim)

proc drawDragonSilhouette(w, h, time, side: float32, body, rim, ember: Color) =
  ## One black dragon coiled up a screen edge: tail at the bottom corner,
  ## spine spikes climbing, a wing mantled above the shoulder, and a horned
  ## head turned inward to watch the desktop. `side` selects the edge (<0
  ## left, >0 right); every x is built inward from that edge via `edgeX`.
  let s = min(w, h)
  let inward = if side < 0.0'f32: 1.0'f32 else: -1.0'f32
  const Segs = 16
  var bx, by, br: array[Segs, float32]
  for i in 0 ..< Segs:
    let t = i.float32 / (Segs - 1).float32
    let sway = sin(time * 0.45'f32 + t * 4.0'f32) * s * 0.01'f32 * (1.0'f32 - t * 0.5'f32)
    let lean = sin(t * PI * 0.5'f32) * s * 0.20'f32
    bx[i] = edgeX(s * 0.045'f32 + lean + sway, w, side)
    by[i] = h * (0.97'f32 - t * 0.66'f32)
    br[i] = s * (0.018'f32 + 0.046'f32 * sin(t * PI * 0.85'f32 + 0.1'f32))

  # The wing first, so the neck occludes any strut passing behind it.
  let shIdx = int(0.60'f32 * (Segs - 1).float32)
  drawDragonWing(bx[shIdx], by[shIdx], s, time, side, side * 11.0'f32 + 3.0'f32,
                 withAlpha(body, 235'u8), rim, ember)

  # Body: a tapered ribbon, stitched from rim points either side of the spine,
  # shaded from its lit inward edge to its shadowed outer one.
  var lx, ly, rx, ry: array[Segs, float32]
  for i in 0 ..< Segs:
    let ax = if i < Segs - 1: bx[i + 1] else: bx[i]
    let ay = if i < Segs - 1: by[i + 1] else: by[i]
    let px = if i > 0: bx[i - 1] else: bx[i]
    let py = if i > 0: by[i - 1] else: by[i]
    var dx = ax - px
    var dy = ay - py
    let dl = max(0.0001'f32, sqrt(dx * dx + dy * dy))
    dx /= dl; dy /= dl
    lx[i] = bx[i] - dy * br[i]; ly[i] = by[i] + dx * br[i]
    rx[i] = bx[i] + dy * br[i]; ry[i] = by[i] - dx * br[i]
  let litBody = colorLerp(body, rim, 0.12'f32)
  # Which rim side faces inward (toward the desktop) decides where the light is.
  let leftLit = (lx[Segs div 2] - bx[Segs div 2]) * inward > 0.0'f32
  let cL = if leftLit: litBody else: body
  let cR = if leftLit: body else: litBody
  for i in 0 ..< (Segs - 1):
    drawGradientQuad(vec2(lx[i], ly[i]), vec2(rx[i], ry[i]), vec2(rx[i + 1], ry[i + 1]), vec2(lx[i + 1], ly[i + 1]),
                     cL, cR, cR, cL)
  for i in 0 ..< Segs:
    drawRadialGradient(vec2(bx[i], by[i]), br[i] * 0.98'f32, br[i] * 0.98'f32, colorLerp(cL, cR, 0.5'f32),
                       colorLerp(cL, cR, 0.5'f32), reLinear, 1)

  # Warm rim on the inward contour, brightest near the head.
  for i in 1 ..< Segs:
    let t = i.float32 / (Segs - 1).float32
    let lit = colorLerp(body, rim, 0.15'f32 + t * 0.45'f32)
    let ex = bx[i] + inward * br[i] * 0.92'f32
    let pex = bx[i - 1] + inward * br[i - 1] * 0.92'f32
    drawStroke(vec2(pex, by[i - 1]), vec2(ex, by[i]), max(1.2'f32, br[i] * 0.30'f32), lit)
  for i in 0 ..< Segs:
    let t = i.float32 / (Segs - 1).float32
    drawCircleOutline(vec2(bx[i], by[i]), br[i], withAlpha(rim, clampByteF(18.0'f32 + t * 42.0'f32)))

  # Spine spikes on alternating segments, angled outward and up.
  for i in 0 ..< Segs:
    if i mod 2 == 1 and i < Segs - 1:
      let spike = br[i] * 1.7'f32
      let outX = -inward * spike * 0.5'f32
      drawGradientTriangle(vec2(bx[i] - outX * 0.3'f32, by[i] + br[i] * 0.3'f32),
                           vec2(bx[i] + outX * 0.3'f32, by[i] - br[i] * 0.3'f32),
                           vec2(bx[i] + outX, by[i] - spike * 0.95'f32),
                           colorLerp(body, rim, 0.5'f32), colorLerp(body, rim, 0.5'f32), rim)

  drawDragonForeleg(bx[shIdx], by[shIdx] + br[shIdx] * 0.6'f32, s, time, side,
                    side * 5.0'f32 + 1.0'f32, body, rim)

  # Tail fin: a barbed arrowhead swaying at the tip.
  let tailSway = sin(time * 0.6'f32) * s * 0.01'f32
  let t0 = vec2(bx[0], by[0])
  let tdx = -inward * s * 0.055'f32 + tailSway
  let tdy = s * 0.05'f32
  let tailTip = vec2(t0.x + tdx, t0.y + tdy)
  let tailMid = vec2(t0.x + tdx * 0.62'f32, t0.y + tdy * 0.62'f32)
  drawTri2(vec2(t0.x, t0.y - br[0]), vec2(t0.x, t0.y + br[0]), tailTip, body)
  drawTri2(tailTip, tailMid, vec2(tailTip.x - inward * s * 0.024'f32, tailTip.y - s * 0.026'f32), body)
  drawTri2(tailTip, tailMid, vec2(tailTip.x + inward * s * 0.010'f32, tailTip.y + s * 0.022'f32), body)
  drawStroke(t0, tailTip, 1.3'f32, withAlpha(rim, 90'u8))

  # Head: cranium and snout with a brow ridge, a hinged jaw breathing open a
  # hair, gold fangs and a gold outline so it never blends into the neck.
  let hx = bx[Segs - 1]
  let hy = by[Segs - 1]
  let headLen = s * 0.11'f32
  let headW = s * 0.060'f32
  let gape = (sin(time * 0.9'f32 + side) * 0.5'f32 + 0.5'f32) * headW * 0.16'f32
  let hinge = vec2(hx, hy + headW * 0.10'f32)
  let brow = vec2(hx - inward * headW * 0.10'f32, hy - headW * 0.62'f32)
  let snoutTop = vec2(hx + inward * headLen * 0.86'f32, hy - headW * 0.28'f32)
  let snout = vec2(hx + inward * headLen, hy - headLen * 0.02'f32)
  let jawTip = vec2(hx + inward * headLen * 0.72'f32, hy + headW * 0.30'f32 + gape)
  drawGradientTriangle(hinge, brow, snoutTop, body, litBody, litBody)
  drawGradientTriangle(hinge, snoutTop, snout, body, litBody, litBody)
  drawTri2(hinge, snout, jawTip, body)
  for tk in 0 ..< 3:
    let tf = 0.24'f32 + tk.float32 * 0.26'f32
    let mx = snout.x + (hinge.x - snout.x) * tf
    let my = snout.y + (hinge.y - snout.y) * tf
    drawTri2(vec2(mx - inward * headW * 0.022'f32, my), vec2(mx + inward * headW * 0.022'f32, my),
             vec2(mx - inward * headW * 0.02'f32, my + headW * 0.17'f32 + gape * 0.4'f32), withAlpha(rim, 205'u8))
  drawStroke(hinge, brow, 1.5'f32, rim)
  drawStroke(brow, snoutTop, 1.5'f32, rim)
  drawStroke(snoutTop, snout, 1.5'f32, rim)
  drawStroke(snout, jawTip, 1.3'f32, withAlpha(rim, 160'u8))
  drawStroke(jawTip, hinge, 1.3'f32, withAlpha(rim, 120'u8))
  for hk in 0 ..< 2:
    let hf = hk.float32
    drawGradientTriangle(vec2(hx - inward * headW * (0.05'f32 + hf * 0.12'f32), hy - headW * (0.5'f32 + hf * 0.1'f32)),
                         vec2(hx + inward * headW * 0.08'f32, hy - headW * (0.35'f32 + hf * 0.1'f32)),
                         vec2(hx - inward * headLen * (0.45'f32 + hf * 0.25'f32), hy - headLen * (0.85'f32 + hf * 0.35'f32)),
                         colorLerp(body, rim, 0.4'f32), colorLerp(body, rim, 0.4'f32), rim)
  let chBase = vec2(hx + inward * headW * 0.02'f32, hy + headW * 0.16'f32)
  drawTri2(chBase, vec2(chBase.x + inward * headW * 0.12'f32, chBase.y + headW * 0.04'f32),
           vec2(chBase.x - inward * headLen * 0.26'f32, chBase.y + headLen * 0.16'f32), rim)

  # Ember eye under the brow, pulsing, with a soft bleed onto the hide.
  let eyePulse = sin(time * 1.4'f32 + side * 3.0'f32) * 0.5'f32 + 0.5'f32
  let eyePos = vec2(hx + inward * headLen * 0.34'f32, hy - headW * 0.34'f32)
  drawGlow(eyePos, headW * 0.9'f32, withAlpha(ember, clampByteF(70.0'f32 + eyePulse * 60.0'f32)))
  drawDisc(eyePos, headW * 0.1'f32, withAlpha(colorLerp(ember, rgba(255, 200, 120), 0.4'f32), clampByteF(200.0'f32 + eyePulse * 55.0'f32)))

  # Smouldering breath: a nostril glow with a few embers drifting up.
  drawGlow(snout, headW * 0.6'f32, withAlpha(ember, 90'u8))
  for ek in 0 ..< 3:
    let eseed = side * 7.0'f32 + ek.float32 * 5.3'f32
    let ePhase = fract01(time * 0.18'f32 + hash01(eseed))
    let ePos = vec2(snout.x + inward * ePhase * headLen * 0.6'f32, snout.y - ePhase * headLen * 1.4'f32)
    drawDisc(ePos, max(0.6'f32, headW * 0.05'f32 * (1.0'f32 - ePhase)),
             withAlpha(ember, clampByteF(160.0'f32 * (1.0'f32 - ePhase))))

proc drawCandle(x, baseY, s, time, seed: float32) =
  ## A stubby tavern candle: lit wax, a drip, a flickering teardrop flame and
  ## the warm pool of light it throws.
  let cw = s * 0.024'f32
  let ch = s * 0.06'f32
  let flick = 0.85'f32 + 0.15'f32 * sin(time * 9.0'f32 + seed) + 0.06'f32 * sin(time * 23.0'f32 + seed * 2.0'f32)
  let sway = sin(time * 2.3'f32 + seed) * cw * 0.12'f32
  let flame = vec2(x + sway, baseY - ch - cw * 0.9'f32)
  drawGlow(vec2(x, baseY - ch * 0.5'f32), s * 0.3'f32, rgba(255, 170, 80, int(70.0'f32 * flick)))
  drawGlow(flame, s * 0.08'f32, rgba(255, 210, 130, int(120.0'f32 * flick)))
  fillEllipse(vec2(x, baseY), cw * 1.1'f32, cw * 0.35'f32, rgba(0, 0, 0, 100))
  hGrad(x - cw * 0.5'f32, baseY - ch, cw, ch, rgba(255, 238, 200), rgba(196, 170, 128))
  fillEllipse(vec2(x, baseY - ch), cw * 0.5'f32, cw * 0.16'f32, rgba(255, 246, 220))
  drawTaperedLine(vec2(x + cw * 0.3'f32, baseY - ch), vec2(x + cw * 0.32'f32, baseY - ch * 0.62'f32),
                  cw * 0.22'f32, cw * 0.12'f32, rgba(255, 244, 214), rgba(240, 226, 190))
  drawStroke(vec2(x, baseY - ch), vec2(x + sway * 0.4'f32, baseY - ch - cw * 0.35'f32), max(0.5'f32, cw * 0.08'f32), rgba(30, 20, 14))
  let fh = cw * (1.3'f32 + 0.25'f32 * flick)
  drawGradientTriangle(vec2(flame.x + sway, flame.y - fh), vec2(flame.x - cw * 0.3'f32, flame.y + cw * 0.15'f32),
                       vec2(flame.x + cw * 0.3'f32, flame.y + cw * 0.15'f32),
                       rgba(255, 220, 120, 0), rgba(255, 150, 40, 230), rgba(255, 150, 40, 230))
  drawDisc(vec2(flame.x, flame.y + cw * 0.1'f32), cw * 0.3'f32, rgba(255, 236, 170, 240))
  drawDisc(vec2(flame.x, flame.y + cw * 0.18'f32), cw * 0.14'f32, rgba(120, 160, 255, 160))

proc drawDragonFx(w, h, time: float32) =
  ## Dragon's Lair: a fantasy tabletop game in a tavern. A plank table, a
  ## parchment battle map with dungeon markings, character sheets, tokens and
  ## dragon minis under candlelight, and two black dragons guarding the edges.
  let gold = rgba(205, 160, 60)
  let ember = rgba(200, 40, 20)
  let hide = rgba(20, 17, 22)
  let wood = rgba(69, 37, 18)
  let woodHi = rgba(114, 68, 34, 210)
  let ink = rgba(76, 49, 28, 185)
  let s = min(w, h)
  let u = unitOf(w, h)
  let tcx = w * CubeAnchorX
  let tcy = h * CubeAnchorY
  let mapW = s * 1.02'f32
  let mapH = s * 0.70'f32
  let mapX = tcx - mapW * 0.5'f32
  let mapY = tcy - mapH * 0.5'f32

  # Wooden planks with grain and knots.
  fillRect(0.0'f32, 0.0'f32, w, h, rgba(42, 23, 13))
  let plankH = max(4.0'f32, s * 0.085'f32)
  var plankY = -plankH * 0.5'f32
  var plankIndex = 0
  while plankY < h + plankH:
    let f = if (plankIndex and 1) == 0: 0.0'f32 else: 1.0'f32
    let plankCol = colorLerp(wood, woodHi, 0.18'f32 + f * 0.12'f32)
    vGrad(0.0'f32, plankY, w, plankH + 1.0'f32, brighten(plankCol, 8.0'f32), brighten(plankCol, -10.0'f32))
    drawStroke(vec2(0.0'f32, plankY), vec2(w, plankY), max(0.5'f32, 1.2'f32 * u), rgba(24, 12, 7, 170))
    for g in 0 ..< (if detailOf(w, h) < 0.6'f32: 0 else: 4):
      let seed = plankIndex.float32 * 9.7'f32 + g.float32 * 3.1'f32
      let gy = plankY + plankH * (0.15'f32 + hash01(seed) * 0.7'f32)
      var prev = vec2(0.0'f32, gy)
      for k in 1 .. 8:
        let gx = w * k.float32 / 8.0'f32
        let cur = vec2(gx, gy + sin(k.float32 * 1.3'f32 + seed) * plankH * 0.06'f32)
        drawStroke(prev, cur, max(0.4'f32, 0.8'f32 * u), rgba(30, 15, 8, 50))
        prev = cur
    for knot in 0 ..< 3:
      let seed = plankIndex.float32 * 9.7'f32 + knot.float32 * 18.1'f32
      fillEllipse(vec2(hash01(seed) * w, plankY + plankH * (0.25'f32 + hash01(seed + 1.0'f32) * 0.5'f32)),
                  s * 0.014'f32, s * 0.005'f32, rgba(28, 14, 8, 110))
    plankY += plankH
    plankIndex += 1

  # Tavern dark around a warm pool of light over the board.
  drawGlow(vec2(tcx, tcy), mapW * 0.95'f32, mapH * 1.1'f32, rgba(255, 196, 110, 50))
  edgeVignette(w, h, 0.3'f32, rgba(5, 3, 3, 170))

  # Parchment battle map: stained, folded at two corners, darker at its edges.
  drawGlow(vec2(tcx + s * 0.02'f32, tcy + s * 0.03'f32), mapW * 0.62'f32, mapH * 0.66'f32, rgba(0, 0, 0, 140))
  vGrad(mapX, mapY, mapW, mapH, rgba(232, 205, 142, 250), rgba(190, 156, 94, 250))
  for st in 0 ..< 7:
    let seed = st.float32 * 13.7'f32 + 2.0'f32
    drawGlow(vec2(mapX + mapW * hash01(seed), mapY + mapH * hash01(seed + 1.0'f32)),
             s * (0.05'f32 + hash01(seed + 2.0'f32) * 0.08'f32), rgba(120, 80, 30, 40))
  let burn = s * 0.04'f32
  vGrad(mapX, mapY, mapW, burn, rgba(110, 70, 30, 120), rgba(110, 70, 30, 0))
  vGrad(mapX, mapY + mapH - burn, mapW, burn, rgba(110, 70, 30, 0), rgba(110, 70, 30, 130))
  hGrad(mapX, mapY, burn, mapH, rgba(110, 70, 30, 120), rgba(110, 70, 30, 0))
  hGrad(mapX + mapW - burn, mapY, burn, mapH, rgba(110, 70, 30, 0), rgba(110, 70, 30, 120))
  drawRectOutline(int32(mapX), int32(mapY), int32(mapW), int32(mapH), rgba(93, 55, 25, 210))
  drawRectOutline(int32(mapX + s * 0.014'f32), int32(mapY + s * 0.014'f32),
                  int32(mapW - s * 0.028'f32), int32(mapH - s * 0.028'f32), rgba(115, 74, 33, 125))
  let fold = s * 0.055'f32
  drawGradientTriangle(vec2(mapX, mapY), vec2(mapX + fold, mapY), vec2(mapX, mapY + fold),
                       rgba(150, 116, 68, 235), rgba(186, 150, 96, 235), rgba(186, 150, 96, 235))
  drawGradientTriangle(vec2(mapX + mapW, mapY + mapH), vec2(mapX + mapW - fold, mapY + mapH),
                       vec2(mapX + mapW, mapY + mapH - fold),
                       rgba(150, 112, 64, 225), rgba(184, 146, 92, 225), rgba(184, 146, 92, 225))

  # Hex grid and dungeon-room strokes around a readable centre.
  let hexR = s * 0.031'f32
  for row in -3 .. 3:
    for col in -4 .. 4:
      let hx = tcx + col.float32 * hexR * 1.52'f32 + (if (row and 1) == 0: 0.0'f32 else: hexR * 0.76'f32)
      let hy = tcy + row.float32 * hexR * 1.28'f32
      if hx > mapX + hexR and hx < mapX + mapW - hexR and hy > mapY + hexR and hy < mapY + mapH - hexR:
        let fill = if (row + col) mod 3 == 0: rgba(108, 74, 38, 26) else: rgba(0, 0, 0, 0)
        drawHexMapCell(hx, hy, hexR, fill, withAlpha(ink, 60'u8))
  let roomCol = rgba(73, 43, 23, 150)
  drawRectOutline(int32(tcx - s * 0.31'f32), int32(tcy - s * 0.18'f32), int32(s * 0.22'f32), int32(s * 0.16'f32), roomCol)
  drawRectOutline(int32(tcx + s * 0.12'f32), int32(tcy + s * 0.03'f32), int32(s * 0.26'f32), int32(s * 0.18'f32), roomCol)
  drawStroke(vec2(tcx - s * 0.09'f32, tcy - s * 0.10'f32), vec2(tcx + s * 0.12'f32, tcy + s * 0.09'f32), 1.2'f32, roomCol)
  drawStroke(vec2(tcx - s * 0.02'f32, tcy + s * 0.15'f32), vec2(tcx + s * 0.25'f32, tcy + s * 0.15'f32), 1.2'f32, roomCol)
  drawRune(tcx - mapW * 0.36'f32, tcy - mapH * 0.29'f32, s * 0.021'f32, withAlpha(ember, 140'u8))
  drawRune(tcx + mapW * 0.35'f32, tcy + mapH * 0.27'f32, s * 0.018'f32, withAlpha(gold, 130'u8))

  # Cards, a character sheet, tokens and minis around the clear centre.
  let cardW = s * 0.074'f32
  let cardH = s * 0.112'f32
  drawDragonGameCard(mapX + mapW * 0.13'f32, mapY + mapH * 0.76'f32, cardW, cardH,
                     withAlpha(ember, 215'u8), rgba(65, 36, 20, 190))
  drawDragonGameCard(mapX + mapW * 0.22'f32, mapY + mapH * 0.82'f32, cardW, cardH,
                     withAlpha(gold, 220'u8), rgba(65, 36, 20, 170))
  drawDragonGameCard(mapX + mapW * 0.84'f32, mapY + mapH * 0.19'f32, cardW, cardH,
                     withAlpha(gold, 210'u8), rgba(65, 36, 20, 170))
  let sheetX = mapX + mapW * 0.73'f32
  let sheetY = mapY + mapH * 0.70'f32
  drawGlow(vec2(sheetX + s * 0.1'f32, sheetY + s * 0.07'f32), s * 0.12'f32, s * 0.08'f32, rgba(0, 0, 0, 90))
  vGrad(sheetX, sheetY, s * 0.18'f32, s * 0.12'f32, rgba(238, 214, 160, 235), rgba(216, 190, 136, 235))
  drawRectOutline(int32(sheetX), int32(sheetY), int32(s * 0.18'f32), int32(s * 0.12'f32), withAlpha(ink, 170'u8))
  for line in 0 ..< 4:
    let ly = mapY + mapH * 0.73'f32 + line.float32 * s * 0.022'f32
    drawStroke(vec2(mapX + mapW * 0.75'f32, ly), vec2(mapX + mapW * 0.88'f32, ly), 1.0'f32, withAlpha(ink, 115'u8))
  for tok in 0 ..< 5:
    let seed = tok.float32 * 12.7'f32 + 4.0'f32
    let base = if tok mod 2 == 0: rgba(112, 25, 22, 245) else: rgba(40, 52, 42, 245)
    drawDragonToken(mapX + mapW * (0.30'f32 + tok.float32 * 0.08'f32),
                    mapY + mapH * 0.19'f32 + sin(tok.float32) * s * 0.014'f32,
                    s * 0.018'f32, time, seed, base, withAlpha(gold, 220'u8))
  drawDragonMini(mapX + mapW * 0.68'f32, mapY + mapH * 0.67'f32, s * 0.052'f32, hide, gold, ember)
  drawDragonMini(mapX + mapW * 0.82'f32, mapY + mapH * 0.56'f32, s * 0.040'f32, hide, gold, ember)

  # Ward-runes flickering awake like active board spaces.
  for r in 0 ..< 8:
    let seed = r.float32 * 19.3'f32 + 2.0'f32
    let cycle = 5.0'f32 + hash01(seed) * 4.0'f32
    let ph = fract01(time / cycle + hash01(seed + 4.0'f32))
    let vis = sin(ph * PI)
    if vis <= 0.03'f32: continue
    let ang = hash01(seed + 1.0'f32) * PI * 2.0'f32
    let rr = 0.18'f32 + hash01(seed + 2.0'f32) * 0.46'f32
    let p = vec2(tcx + cos(ang) * mapW * rr, tcy + sin(ang) * mapH * rr)
    drawGlow(p, s * 0.03'f32, withAlpha(gold, clampByteF(60.0'f32 * vis)))
    drawRune(p.x, p.y, s * 0.013'f32, withAlpha(gold, clampByteF(140.0'f32 * vis)))

  # Candles on the table, then the lair's embers drifting up.
  drawCandle(mapX - s * 0.07'f32, mapY + mapH * 0.34'f32, s, time, 1.0'f32)
  drawCandle(mapX + mapW * 0.6'f32, mapY - s * 0.012'f32, s, time, 2.7'f32)
  for e in 0 ..< 16:
    let seed = e.float32 * 9.1'f32
    let span = h * 1.1'f32
    let ey = h * 1.05'f32 - wrapCoord(hash01(seed) * span + time * (h * (0.025'f32 + hash01(seed + 1.0'f32) * 0.05'f32)), span)
    let ex = hash01(seed + 2.0'f32) * w + sin(time * 0.3'f32 + seed) * w * 0.015'f32
    let fadeK = clamp(1.0'f32 - (h - ey) / h * 0.3'f32, 0.0'f32, 1.0'f32)
    let p = vec2(ex, ey)
    drawGlow(p, s * 0.01'f32, withAlpha(ember, clampByteF(60.0'f32 * fadeK)))
    drawDisc(p, s * (0.0025'f32 + hash01(seed + 3.0'f32) * 0.003'f32), withAlpha(rgba(255, 120, 50), clampByteF(150.0'f32 * fadeK)))

  drawDragonSilhouette(w, h, time, -1.0'f32, hide, gold, ember)
  drawDragonSilhouette(w, h, time, 1.0'f32, hide, gold, ember)

# ---------------------------------------------------------------------------
# The whole scene
# ---------------------------------------------------------------------------

proc drawCubeOrbit(w, h, time: float32, ringCol, nodeCol: Color, strength: float32) =
  ## The orbit rings the desktop cube floats in: thin rings, an arc of light
  ## running round each, and a glowing node riding it.
  let s = min(w, h)
  let u = unitOf(w, h)
  let c = vec2(w * CubeAnchorX, h * CubeAnchorY)
  for i in 0 .. 3:
    let r = s * (0.18'f32 + i.float32 * 0.055'f32)
    drawCircleOutline(c, r, withAlpha(ringCol, (22.0'f32 + i.float32 * 8.0'f32) * strength))
    let spin = time * (0.22'f32 + i.float32 * 0.04'f32) * (if (i and 1) == 0: 1.0'f32 else: -1.0'f32) + i.float32 * PI * 0.38'f32
    let arcStart = spin * 180.0'f32 / PI
    drawRing(c, r - max(0.4'f32, 0.8'f32 * u), r + max(0.4'f32, 0.8'f32 * u), arcStart, arcStart + 40.0'f32,
             16, withAlpha(ringCol, 70.0'f32 * strength))
    let node = vec2(c.x + cos(spin) * r, c.y + sin(spin) * r)
    drawGlow(node, 9.0'f32 * u, withAlpha(nodeCol, 110.0'f32 * strength))
    drawDisc(node, max(0.6'f32, (2.2'f32 + i.float32 * 0.3'f32) * u), withAlpha(colorLerp(nodeCol, rgba(255, 255, 255), 0.4'f32), 220.0'f32 * strength))

proc drawDesktopBgScene*(bgType: DesktopBgType, screenWidth, screenHeight: int32, time: float32) {.moddable.} =
  ## A purchasable background, whole: its scene, the cube's orbit rings and a
  ## shade behind the icon column. The desktop and the shop's preview card
  ## both draw this; the caller draws the cube on top. dbgDefault is the
  ## hand-crafted wallpaper in os_desktop.nim and draws nothing here.
  if bgType == dbgDefault: return
  let w = screenWidth.float32
  let h = screenHeight.float32
  let data = getDesktopBgData(bgType)
  beginKeepAlpha()
  fillRect(0.0'f32, 0.0'f32, w, h, data.bgColor)
  var orbit = 1.0'f32
  case bgType
  of dbgDefault: discard
  of dbgNeon: drawNeonCityFx(w, h, time)
  of dbgMatrix: drawDataRainFx(w, h, time)
  of dbgVoid: drawDeepVoidFx(w, h, time)
  of dbgSunrise: drawSunriseFx(w, h, time)
  of dbgOcean: drawNeuralNetFx(w, h, time)
  of dbgInferno: drawInfernoFx(w, h, time)
  of dbgPortal:
    drawPortalFx(w, h, time)
    orbit = 0.6'f32
  of dbgHorror:
    drawHorrorFx(w, h, time)
    orbit = 0.45'f32
  of dbgCyber: drawCyberFx(w, h, time)
  of dbgCasino: drawCasinoFx(w, h, time)
  of dbgDragon:
    drawDragonFx(w, h, time)
    orbit = 0.7'f32
  drawCubeOrbit(w, h, time, data.primaryColor, data.accentColor, orbit)
  # A soft shade behind the icon column keeps the labels readable on every scene.
  let shadeW = min(300.0'f32, w * 0.23'f32)
  hGrad(0.0'f32, 0.0'f32, shadeW, h, withAlpha(brighten(data.bgColor, -20.0'f32), 150'u8),
        withAlpha(brighten(data.bgColor, -20.0'f32), 0'u8))
  endKeepAlpha()
