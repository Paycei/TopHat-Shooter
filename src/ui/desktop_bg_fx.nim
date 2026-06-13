## Per-theme animated wallpaper effects for the purchasable desktop backgrounds.
##
## The default desktop keeps its hand-crafted wallpaper in `os_desktop.nim`;
## every other `DesktopBgType` gets its signature look here so the themes are
## more than palette swaps of the shared backdrop. All effects are stateless -
## they derive purely from (width, height, time) - which lets the same code
## render the fullscreen desktop and the small shop preview cards (the shop
## translates the matrix and clips with a scissor before calling in).

import raylib, math
import background_fx, ../desktop_bg_skins

proc fract01(value: float32): float32 =
  value - floor(value)

proc hash01(seed: float32): float32 =
  ## Deterministic pseudo-random in [0,1), same trick as the backdrop stars.
  fract01(sin(seed * 12.9898'f32) * 43758.5453'f32)

proc wrapF(value, limit: float32): float32 =
  if limit <= 0.0'f32:
    return 0.0'f32
  value - floor(value / limit) * limit

proc alphaU8(value: float32): uint8 =
  uint8(clamp(value, 0.0'f32, 255.0'f32))

# Neon City

proc drawNeonCityFx(w, h, time: float32) =
  let horizon = h * 0.80'f32

  # City-glow haze hugging the skyline
  drawSoftGlow(w * 0.30'f32, horizon, w * 0.26'f32,
               Color(r: 255, g: 0, b: 200, a: 30), 0.45)
  drawSoftGlow(w * 0.74'f32, horizon, w * 0.24'f32,
               Color(r: 110, g: 0, b: 255, a: 34), 0.45)

  # Two skyline layers: far towers in purple haze, near towers almost black
  for layer in 0..1:
    let count = if layer == 0: 16 else: 10
    let bw = w / count.float32
    let bodyColor = if layer == 0: Color(r: 26, g: 10, b: 48, a: 235)
                    else: Color(r: 10, g: 4, b: 20, a: 255)
    for i in 0..<count:
      let seed = i.float32 * 9.173'f32 + layer.float32 * 57.31'f32
      let maxRise = if layer == 0: 0.16'f32 else: 0.24'f32
      let bh = h * (0.05'f32 + hash01(seed) * maxRise)
      let bx = i.float32 * bw
      let topY = horizon - bh - layer.float32 * h * 0.012'f32
      let gap = max(2.0'f32, w * 0.004'f32)
      drawRectangle(bx.int32, topY.int32, int32(bw - gap), int32(h - topY), bodyColor)

      if layer == 1:
        # Blinking rooftop beacon on some near towers
        if hash01(seed + 4.4'f32) > 0.62'f32:
          let blink = sin(time * 2.2'f32 + seed) * 0.5'f32 + 0.5'f32
          drawCircle(Vector2(x: bx + bw * 0.5'f32, y: topY - 3.0'f32),
                     max(1.4'f32, w * 0.002'f32),
                     Color(r: 255, g: 60, b: 120, a: alphaU8(90.0'f32 + blink * 140.0'f32)))
        # Sparse lit windows, a few flickering
        let cols = max(2, int(bw / max(7.0'f32, w * 0.014'f32)))
        let rows = max(2, int(bh / max(8.0'f32, h * 0.022'f32)))
        let winSize = max(1'i32, int32(w * 0.002'f32))
        for wx in 0..<cols:
          for wy in 0..<rows:
            let ws = hash01(seed + wx.float32 * 3.7'f32 + wy.float32 * 11.3'f32)
            if ws > 0.56'f32:
              let flick = if ws > 0.93'f32:
                            sin(time * (3.0'f32 + ws * 4.0'f32) + ws * 40.0'f32) * 0.5'f32 + 0.5'f32
                          else: 1.0'f32
              let wxp = bx + (wx.float32 + 0.5'f32) * (bw - gap) / cols.float32
              let wyp = topY + (wy.float32 + 0.4'f32) * bh / rows.float32
              let wc = if hash01(seed + ws * 91.0'f32) > 0.5'f32:
                         Color(r: 255, g: 80, b: 210, a: alphaU8(70.0'f32 + flick * 110.0'f32))
                       else:
                         Color(r: 120, g: 200, b: 255, a: alphaU8(60.0'f32 + flick * 100.0'f32))
              drawRectangle(wxp.int32, wyp.int32, winSize, winSize, wc)

  # Buzzing neon signs over the skyline, one of them faulty
  for s in 0..<4:
    let seed = s.float32 * 23.91'f32 + 7.7'f32
    let sx = (0.08'f32 + hash01(seed) * 0.84'f32) * w
    let sy = horizon - h * (0.02'f32 + hash01(seed + 1.3'f32) * 0.14'f32)
    let signW = w * (0.02'f32 + hash01(seed + 2.6'f32) * 0.035'f32)
    let flick = 0.55'f32 + 0.45'f32 * sin(time * (3.0'f32 + s.float32 * 1.7'f32) + seed)
    let broken = if hash01(seed + 5.1'f32) > 0.7'f32 and
                    fract01(time * 0.4'f32 + s.float32 * 0.25'f32) < 0.06'f32: 0.15'f32
                 else: 1.0'f32
    let c = if s mod 2 == 0: Color(r: 255, g: 0, b: 200, a: 255)
            else: Color(r: 140, g: 60, b: 255, a: 255)
    drawRectangle(sx.int32, sy.int32, max(3'i32, signW.int32),
                  max(2'i32, int32(h * 0.006'f32)),
                  withAlpha(c, alphaU8(150.0'f32 * flick * broken)))
    drawSoftGlow(sx + signW * 0.5'f32, sy, signW * 1.6'f32,
                 withAlpha(c, alphaU8(46.0'f32 * flick * broken)), 0.6)

# Data Rain

proc drawDataRainFx(w, h, time: float32) =
  const glyphs = "01<>+#$%&=?*"
  let fontSize = clamp(int32(h / 44.0'f32), 8'i32, 20'i32)
  let cell = fontSize.float32 + 4.0'f32
  let cols = min(64, max(6, int(w / (fontSize.float32 * 1.9'f32))))
  for c in 0..<cols:
    let seed = c.float32 * 13.77'f32
    let colX = (c.float32 + 0.18'f32 + hash01(seed) * 0.5'f32) * (w / cols.float32)
    let speed = h * (0.22'f32 + hash01(seed + 3.1'f32) * 0.75'f32)
    let trail = 5 + int(hash01(seed + 6.7'f32) * 9.0'f32)
    let span = h + cell * (trail.float32 + 2.0'f32)
    let headY = wrapF(hash01(seed + 9.2'f32) * span + time * speed, span) - cell * 2.0'f32
    for k in 0..trail:
      let gy = headY - k.float32 * cell
      if gy < -cell or gy > h:
        continue
      # Glyphs mutate while they fall, each at its own cadence
      let shift = floor(time * (5.0'f32 + hash01(seed + k.float32) * 7.0'f32))
      let gi = int(hash01(seed * 1.71'f32 + k.float32 * 7.13'f32 + shift * 0.619'f32) *
                   glyphs.len.float32) mod glyphs.len
      let fade = 1.0'f32 - k.float32 / (trail.float32 + 1.0'f32)
      let col =
        if k == 0: Color(r: 200, g: 255, b: 200, a: 235)
        elif k == 1: Color(r: 90, g: 255, b: 110, a: alphaU8(40.0'f32 + 180.0'f32 * fade))
        else: Color(r: 0, g: 200, b: 70, a: alphaU8(36.0'f32 + 150.0'f32 * fade))
      drawText($glyphs[gi], colX.int32, gy.int32, fontSize, col)
    if c mod 6 == 0:
      drawSoftGlow(colX + fontSize.float32 * 0.4'f32, headY + cell * 0.5'f32, cell * 1.6'f32,
                   Color(r: 60, g: 255, b: 120, a: 36), 0.5)

# Deep Void

proc drawDeepVoidFx(w, h, time: float32) =
  # Slowly drifting, breathing nebulae
  for n in 0..<4:
    let seed = n.float32 * 31.7'f32
    let nx = (0.15'f32 + hash01(seed) * 0.7'f32) * w + sin(time * 0.05'f32 + seed) * w * 0.04'f32
    let ny = (0.12'f32 + hash01(seed + 2.2'f32) * 0.7'f32) * h + cos(time * 0.04'f32 + seed * 1.3'f32) * h * 0.05'f32
    let nr = min(w, h) * (0.16'f32 + hash01(seed + 4.1'f32) * 0.2'f32)
    let breathe = 0.8'f32 + 0.2'f32 * sin(time * 0.3'f32 + seed)
    let col = if n mod 2 == 0: Color(r: 110, g: 40, b: 220, a: 26)
              else: Color(r: 40, g: 70, b: 200, a: 22)
    drawSoftGlow(nx, ny, nr * breathe, col, 0.55)

  # Scale star size and count so they look as bright and dense at full
  # desktop as they do in the 170×64 shop preview card (reference: 64 px).
  let sScale = min(w, h) / 64.0'f32 * 0.5'f32 + 0.5'f32
  let starCount = int(22.0'f32 * sqrt(sScale))

  # Bright feature stars, some with cross sparkles
  for s in 0..<starCount:
    let seed = s.float32 * 17.31'f32 + 5.5'f32
    let sx = hash01(seed) * w
    let sy = hash01(seed + 1.7'f32) * h
    let tw = sin(time * (0.9'f32 + hash01(seed + 3.3'f32) * 1.6'f32) + seed) * 0.5'f32 + 0.5'f32
    let sr = (0.8'f32 + hash01(seed + 8.8'f32) * 1.6'f32) * sScale
    drawCircle(Vector2(x: sx, y: sy), sr + tw * 0.8'f32 * sScale,
               Color(r: 220, g: 215, b: 255, a: alphaU8(70.0'f32 + tw * 150.0'f32)))
    if hash01(seed + 12.0'f32) > 0.65'f32:
      let arm = (3.0'f32 + tw * 5.0'f32) * (0.6'f32 + sr * 0.3'f32)
      let armCol = Color(r: 200, g: 190, b: 255, a: alphaU8(40.0'f32 + tw * 90.0'f32))
      drawLine(Vector2(x: sx - arm, y: sy), Vector2(x: sx + arm, y: sy), 1.0'f32, armCol)
      drawLine(Vector2(x: sx, y: sy - arm), Vector2(x: sx, y: sy + arm), 1.0'f32, armCol)

  # Occasional shooting stars on two interleaved cycles
  for lane in 0..1:
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
      let tailLen = min(w, h) * 0.22'f32
      let fade = sin(prog * PI)
      let streakCol = Color(r: 235, g: 230, b: 255, a: alphaU8(220.0'f32 * fade))
      drawLine(Vector2(x: px - dirX * w * 0.45'f32 / mvLen * tailLen,
                       y: py - h * 0.35'f32 / mvLen * tailLen),
               Vector2(x: px, y: py), 2.0'f32, streakCol)
      drawSoftGlow(px, py, 9.0'f32 * sScale, withAlpha(streakCol, alphaU8(90.0'f32 * fade)), 0.7)

# System Sunrise

proc drawSunriseFx(w, h, time: float32) =
  let horizon = h * 0.64'f32
  let sunX = w * 0.5'f32
  let sunR = min(w, h) * 0.26'f32
  let sunCenter = Vector2(x: sunX, y: horizon)

  # Dusk-to-ember sky wash above the horizon
  drawRectangleGradientV(0, 0, w.int32, horizon.int32,
                         Color(r: 36, g: 10, b: 48, a: 140),
                         Color(r: 140, g: 38, b: 10, a: 110))

  # Sun: warm halo, banded disk, synthwave slits sweeping the lower half
  drawSoftGlow(sunX, horizon, sunR * 2.1'f32, Color(r: 255, g: 120, b: 30, a: 60), 0.8)
  drawCircle(sunCenter, sunR, Color(r: 255, g: 95, b: 40, a: 235))
  drawCircle(sunCenter, sunR * 0.86'f32, Color(r: 255, g: 150, b: 40, a: 240))
  drawCircle(sunCenter, sunR * 0.68'f32, Color(r: 255, g: 215, b: 110, a: 245))
  for k in 0..<8:
    let tt = fract01(time * 0.045'f32 + k.float32 / 8.0'f32)
    let sy = horizon - sunR + tt * sunR * 2.0'f32
    let dy = sy - horizon
    if sy < horizon and dy > -sunR * 0.62'f32:
      let halfChord = sqrt(max(0.0'f32, sunR * sunR - dy * dy))
      drawRectangle(int32(sunX - halfChord), sy.int32, int32(halfChord * 2.0'f32),
                    max(1'i32, int32(1.0'f32 + tt * sunR * 0.085'f32)),
                    Color(r: 20, g: 7, b: 6, a: 235))

  # Ground plane and glowing horizon line
  drawRectangle(0, horizon.int32, w.int32, int32(h - horizon) + 1, Color(r: 13, g: 5, b: 12, a: 255))
  drawSoftGlow(sunX, horizon, sunR * 1.3'f32, Color(r: 255, g: 140, b: 40, a: 56), 0.7)
  drawRectangle(0, int32(horizon - 1.0'f32), w.int32, 2, Color(r: 255, g: 170, b: 60, a: 200))

  # Scrolling perspective grid racing toward the viewer
  for i in -7..7:
    drawLine(Vector2(x: sunX, y: horizon),
             Vector2(x: sunX + i.float32 * w * 0.105'f32, y: h), 1.0'f32,
             Color(r: 255, g: 90, b: 170, a: 64))
  for i in 0..<9:
    let t = fract01(time * 0.14'f32 + i.float32 / 9.0'f32)
    let gy = horizon + t * t * (h - horizon)
    drawLine(Vector2(x: 0.0'f32, y: gy), Vector2(x: w, y: gy),
             1.0'f32 + t * 1.4'f32,
             Color(r: 255, g: 90, b: 170, a: alphaU8(26.0'f32 + t * 120.0'f32)))

# Neural Network

proc drawNeuralNetFx(w, h, time: float32) =
  const NodeCount = 18
  var px, py: array[NodeCount, float32]
  for i in 0..<NodeCount:
    let seed = i.float32 * 12.93'f32
    px[i] = (0.05'f32 + hash01(seed) * 0.9'f32) * w +
            sin(time * (0.18'f32 + hash01(seed + 5.0'f32) * 0.2'f32) + seed) * w * 0.03'f32
    py[i] = (0.06'f32 + hash01(seed + 2.6'f32) * 0.88'f32) * h +
            cos(time * (0.15'f32 + hash01(seed + 7.7'f32) * 0.22'f32) + seed * 1.7'f32) * h * 0.04'f32

  # Synapse lines between nearby nodes, with signal pulses on a subset
  let maxDist = min(w, h) * 0.34'f32
  for i in 0..<NodeCount:
    for j in (i + 1)..<NodeCount:
      let dx = px[i] - px[j]
      let dy = py[i] - py[j]
      let d = sqrt(dx * dx + dy * dy)
      if d < maxDist and d > 1.0'f32:
        let closeness = 1.0'f32 - d / maxDist
        drawLine(Vector2(x: px[i], y: py[i]), Vector2(x: px[j], y: py[j]), 1.0'f32,
                 Color(r: 0, g: 170, b: 255, a: alphaU8(14.0'f32 + closeness * 70.0'f32)))
        if (i * 7 + j * 13) mod 4 == 0:
          let tt = fract01(time * (0.25'f32 + hash01((i * 31 + j).float32) * 0.5'f32) +
                           hash01((i * 17 + j * 3).float32))
          drawCircle(Vector2(x: px[i] + (px[j] - px[i]) * tt, y: py[i] + (py[j] - py[i]) * tt),
                     2.0'f32,
                     Color(r: 120, g: 255, b: 230, a: alphaU8(120.0'f32 + closeness * 100.0'f32)))

  for i in 0..<NodeCount:
    let seed = i.float32 * 12.93'f32
    let pulse = sin(time * (0.8'f32 + hash01(seed + 9.0'f32)) + seed) * 0.5'f32 + 0.5'f32
    let r = 1.8'f32 + hash01(seed + 3.3'f32) * 2.2'f32 + pulse * 0.8'f32
    drawCircle(Vector2(x: px[i], y: py[i]), r,
               Color(r: 0, g: 200, b: 255, a: alphaU8(120.0'f32 + pulse * 100.0'f32)))
    if i mod 3 == 0:
      drawSoftGlow(px[i], py[i], r * 7.0'f32, Color(r: 0, g: 220, b: 200, a: 36), 0.5)

# Inferno Core

proc drawInfernoFx(w, h, time: float32) =
  # Pulsing heat welling up from the bottom of the screen
  let surge = sin(time * 1.7'f32) * 0.5'f32 + 0.5'f32
  drawSoftGlow(w * 0.5'f32, h * 1.05'f32, w * 0.5'f32,
               Color(r: 255, g: 70, b: 0, a: alphaU8(55.0'f32 + surge * 30.0'f32)), 0.7)
  drawSoftGlow(w * 0.16'f32, h * 0.98'f32, w * 0.22'f32, Color(r: 255, g: 120, b: 0, a: 40), 0.55)
  drawSoftGlow(w * 0.85'f32, h * 1.0'f32, w * 0.26'f32, Color(r: 255, g: 40, b: 10, a: 44), 0.6)

  # Jagged magma cracks glowing near the floor
  for c in 0..<5:
    let seed = c.float32 * 47.13'f32
    var cx = hash01(seed) * w
    var cy = h * (0.86'f32 + hash01(seed + 1.1'f32) * 0.12'f32)
    let glow = 0.45'f32 + 0.55'f32 * (sin(time * (1.2'f32 + hash01(seed + 8.0'f32)) + seed) * 0.5'f32 + 0.5'f32)
    for s in 0..<(4 + int(hash01(seed + 2.2'f32) * 3.0'f32)):
      let nx = cx + (hash01(seed + s.float32 * 3.3'f32) - 0.3'f32) * w * 0.045'f32
      let ny = cy + (hash01(seed + s.float32 * 5.9'f32) - 0.5'f32) * h * 0.02'f32
      drawLine(Vector2(x: cx, y: cy), Vector2(x: nx, y: ny), 2.0'f32,
               Color(r: 255, g: uint8(90.0'f32 + glow * 120.0'f32), b: 0,
                     a: alphaU8(90.0'f32 + glow * 120.0'f32)))
      cx = nx
      cy = ny
    drawSoftGlow(cx, cy, w * 0.02'f32,
                 Color(r: 255, g: 140, b: 30, a: alphaU8(20.0'f32 + 40.0'f32 * glow)), 0.5)

  # Embers rising, swaying, and burning out as they climb
  for e in 0..<42:
    let seed = e.float32 * 7.91'f32
    let speed = h * (0.06'f32 + hash01(seed + 2.0'f32) * 0.14'f32)
    let cycleSpan = h * 1.15'f32
    let yPos = h * 1.05'f32 - wrapF(hash01(seed + 4.0'f32) * cycleSpan + time * speed, cycleSpan)
    let xPos = hash01(seed) * w +
               sin(time * (0.8'f32 + hash01(seed + 6.0'f32) * 1.4'f32) + seed) * w * 0.015'f32
    let lift = 1.0'f32 - clamp(yPos / h, 0.0'f32, 1.0'f32)
    let fade = clamp(1.0'f32 - lift * 1.15'f32, 0.0'f32, 1.0'f32)
    let flicker = 0.7'f32 + 0.3'f32 * sin(time * (5.0'f32 + hash01(seed + 9.0'f32) * 6.0'f32) + seed)
    let size = (0.9'f32 + hash01(seed + 5.5'f32) * 1.8'f32) * (0.6'f32 + fade * 0.4'f32)
    let heat = hash01(seed + 11.0'f32)
    let col = if heat > 0.7'f32:
                Color(r: 255, g: 230, b: 120, a: alphaU8(200.0'f32 * fade * flicker))
              elif heat > 0.35'f32:
                Color(r: 255, g: 150, b: 30, a: alphaU8(190.0'f32 * fade * flicker))
              else:
                Color(r: 255, g: 70, b: 20, a: alphaU8(170.0'f32 * fade * flicker))
    drawCircle(Vector2(x: xPos, y: yPos), size, col)

# Aperture Test

proc mixCol(a, b: Color, t: float32): Color =
  ## Linear blend between two colours; t is clamped to [0,1].
  let k = clamp(t, 0.0'f32, 1.0'f32)
  Color(r: uint8(a.r.float32 + (b.r.float32 - a.r.float32) * k),
        g: uint8(a.g.float32 + (b.g.float32 - a.g.float32) * k),
        b: uint8(a.b.float32 + (b.b.float32 - a.b.float32) * k),
        a: uint8(a.a.float32 + (b.a.float32 - a.a.float32) * k))

proc drawAperturePortal(cx, cy, rx, ry, time: float32, rim, core: Color,
                        spin: float32) =
  ## A single oval portal: outer halo, a filled swirling event-horizon, and a
  ## bright rim of light rotating around the edge. Built from primitives
  ## (chord scanlines + perimeter dots) so it needs no ellipse API.
  let scale = max(rx, ry) / 70.0'f32   # keep detail proportional to screen size

  # Outer halo bleeding onto the chamber wall
  drawSoftGlow(cx, cy, max(rx, ry) * 2.0'f32, withAlpha(rim, 70'u8), 0.7)

  # Filled interior: horizontal chords of the ellipse, luminous toward the rim
  # and darker at the centre (the "depth"), with a faint vertical shimmer.
  const Rows = 30
  for i in 0..Rows:
    let fy = (i.float32 / Rows.float32) * 2.0'f32 - 1.0'f32   # -1 .. 1
    let half = rx * sqrt(max(0.0'f32, 1.0'f32 - fy * fy))
    if half < 0.5'f32: continue
    let yy = cy + fy * ry
    let edge = abs(fy)
    let shimmer = 0.5'f32 + 0.5'f32 * sin(fy * 6.0'f32 - time * spin * 1.4'f32)
    let bright = 0.85'f32 + 0.15'f32 * shimmer
    let baseCol = mixCol(core, rim, edge * 0.85'f32)
    # Fully opaque fill so the wall panels/seams never show through the portal;
    # the swirl animates via brightness instead of alpha. Thickness tracks the
    # chord spacing (scales with ry) so chords overlap into a solid fill from the
    # 64px shop card up to 4K fullscreen.
    let col = Color(r: alphaU8(baseCol.r.float32 * bright),
                    g: alphaU8(baseCol.g.float32 * bright),
                    b: alphaU8(baseCol.b.float32 * bright), a: 255)
    let lineW = 2.0'f32 * ry / Rows.float32 + 1.0'f32
    drawLine(Vector2(x: cx - half, y: yy), Vector2(x: cx + half, y: yy),
             lineW, col)

  # Rim of light: dots around the perimeter, brightness banded so the band spins
  const RimSegs = 60
  for k in 0..<RimSegs:
    let ang = k.float32 / RimSegs.float32 * (PI * 2.0'f32)
    let ex = cx + cos(ang) * rx
    let ey = cy + sin(ang) * ry
    let band = sin(ang * 3.0'f32 - time * spin) * 0.5'f32 + 0.5'f32
    drawCircle(Vector2(x: ex, y: ey), (0.9'f32 + 1.8'f32 * band) * scale,
               withAlpha(mixCol(rim, core, band * 0.6'f32),
                         alphaU8(110.0'f32 + 130.0'f32 * band)))

  # Two bright sparks orbiting just outside the rim
  for s in 0..<2:
    let ang = time * spin * 0.25'f32 + s.float32 * PI
    let ox = cx + cos(ang) * rx * 1.08'f32
    let oy = cy + sin(ang) * ry * 1.08'f32
    drawCircle(Vector2(x: ox, y: oy), 1.6'f32 * scale, withAlpha(core, 230'u8))
    drawSoftGlow(ox, oy, 8.0'f32 * scale, withAlpha(rim, 120'u8), 0.6)

proc drawWallPanel(px, py, size, gap, base: float32, recessed: bool,
                   tintR, tintG, tintB, tintAmt: float32) =
  ## One Aperture wall panel: a light tile inset in the dark grout, with a
  ## bevel (lit top-left / shadowed bottom-right, reversed when recessed) and
  ## an optional colour bleed from a nearby portal.
  let b = if recessed: base * 0.62'f32 else: base
  # Cool off-white, nudged toward the portal colour by tintAmt.
  let rr = b * 0.95'f32 + (tintR - b * 0.95'f32) * tintAmt
  let gg = b * 0.98'f32 + (tintG - b * 0.98'f32) * tintAmt
  let bb = b * 1.06'f32 + (tintB - b * 1.06'f32) * tintAmt
  let panelColor = Color(r: alphaU8(rr), g: alphaU8(gg), b: alphaU8(bb), a: 255)

  let x0 = px + gap
  let y0 = py + gap
  let s = size - gap * 2.0'f32
  if s < 1.0'f32: return
  drawRectangle(x0.int32, y0.int32, max(1'i32, s.int32), max(1'i32, s.int32), panelColor)

  # Bevel: highlight on two edges, shadow on the opposite two.
  let bw = max(1.0'f32, size * 0.035'f32)
  let hi = withAlpha(Color(r: 255, g: 255, b: 255, a: 255),
                     if recessed: 22'u8 else: 55'u8)
  let sh = withAlpha(Color(r: 0, g: 0, b: 0, a: 255),
                     if recessed: 80'u8 else: 55'u8)
  let topLeft  = if recessed: sh else: hi   # extruded panels catch light top-left
  let botRight = if recessed: hi else: sh
  drawLine(Vector2(x: x0, y: y0), Vector2(x: x0 + s, y: y0), bw, topLeft)        # top
  drawLine(Vector2(x: x0, y: y0), Vector2(x: x0, y: y0 + s), bw, topLeft)        # left
  drawLine(Vector2(x: x0, y: y0 + s), Vector2(x: x0 + s, y: y0 + s), bw, botRight) # bottom
  drawLine(Vector2(x: x0 + s, y: y0), Vector2(x: x0 + s, y: y0 + s), bw, botRight) # right

proc drawPortalFx(w, h, time: float32) =
  let rimBlue    = Color(r: 60,  g: 150, b: 255, a: 255)
  let coreBlue   = Color(r: 190, g: 230, b: 255, a: 255)
  let rimOrange  = Color(r: 255, g: 140, b: 30,  a: 255)
  let coreOrange = Color(r: 255, g: 220, b: 150, a: 255)

  # Portal geometry first, so the wall can pick up coloured light from them.
  let portalRx = min(w, h) * 0.085'f32
  let portalRy = min(w, h) * 0.175'f32
  let breathe = 1.0'f32 + 0.03'f32 * sin(time * 1.3'f32)   # gentle size pulse
  let bx = w * 0.2'f32
  let by = h * 0.5'f32
  let ox = w * 0.8'f32
  let oy = h * 0.5'f32
  let glowR = portalRy * 1.55'f32   # reach of each portal's light onto the wall

  # --- Aperture test-chamber wall ---
  # Dark grout fills the whole wall; the light panels are inset on top, so the
  # gaps between them read as recessed seams.
  drawRectangle(0, 0, w.int32, h.int32, Color(r: 24, g: 28, b: 35, a: 255))
  const Cols = 10
  let tile = w / Cols.float32
  let rowsN = int(ceil(h / tile)) + 1
  let gap = max(1.0'f32, tile * 0.018'f32)   # thin recessed seam between panels
  for gyi in 0..<rowsN:
    for gxi in 0..<Cols:
      let cellX = gxi.float32 * tile
      let cellY = gyi.float32 * tile
      let ccx = cellX + tile * 0.5'f32
      let ccy = cellY + tile * 0.5'f32
      let seed = gxi.float32 * 12.7'f32 + gyi.float32 * 31.3'f32
      let recessed = hash01(seed + 5.0'f32) > 0.85'f32
      let base = 198.0'f32 + (hash01(seed) - 0.5'f32) * 16.0'f32
      # Light bleed: nearer portal wins, blended into the panel tint.
      let tB = clamp(1.0'f32 - sqrt((ccx-bx)*(ccx-bx) + (ccy-by)*(ccy-by)) / glowR, 0.0'f32, 1.0'f32)
      let tO = clamp(1.0'f32 - sqrt((ccx-ox)*(ccx-ox) + (ccy-oy)*(ccy-oy)) / glowR, 0.0'f32, 1.0'f32)
      var tintR, tintG, tintB, tintAmt = 0.0'f32
      if tB >= tO and tB > 0.0'f32:
        tintR = rimBlue.r.float32; tintG = rimBlue.g.float32; tintB = rimBlue.b.float32
        tintAmt = tB * 0.33'f32
      elif tO > 0.0'f32:
        tintR = rimOrange.r.float32; tintG = rimOrange.g.float32; tintB = rimOrange.b.float32
        tintAmt = tO * 0.33'f32
      drawWallPanel(cellX, cellY, tile, gap, base, recessed,
                    tintR, tintG, tintB, tintAmt)

  # The two portals, facing each other across the chamber
  drawAperturePortal(bx, by, portalRx * breathe, portalRy * breathe, time,
                     rimBlue, coreBlue, 2.2'f32)
  drawAperturePortal(ox, oy, portalRx * breathe, portalRy * breathe, time,
                     rimOrange, coreOrange, -2.0'f32)

  # Energy motes streaming between the portals along two bowed arcs, colour
  # lerping blue -> orange so each reads as matter passing through.
  const Motes = 18
  let cxp = (bx + ox) * 0.5'f32
  for m in 0..<Motes:
    let lane = m mod 2
    let bow = if lane == 0: -h * 0.20'f32 else: h * 0.18'f32
    let dir = if lane == 0: 1.0'f32 else: -1.0'f32   # alternate flow direction
    var tt = fract01(time * 0.16'f32 + m.float32 / Motes.float32)
    if dir < 0.0'f32: tt = 1.0'f32 - tt
    # quadratic bezier from blue (bx,by) via (cxp, by+bow) to orange (ox,oy)
    let u = 1.0'f32 - tt
    let px = u * u * bx + 2.0'f32 * u * tt * cxp + tt * tt * ox
    let py = u * u * by + 2.0'f32 * u * tt * (by + bow) + tt * tt * oy
    let col = mixCol(coreBlue, coreOrange, tt)
    let edgeFade = sin(tt * PI)   # fade in/out near the portal mouths
    let sz = (1.4'f32 + 1.2'f32 * edgeFade) * (min(w, h) / 600.0'f32)
    drawCircle(Vector2(x: px, y: py), max(1.0'f32, sz),
               withAlpha(col, alphaU8(200.0'f32 * edgeFade)))
    if m mod 3 == 0:
      drawSoftGlow(px, py, 6.0'f32, withAlpha(col, alphaU8(80.0'f32 * edgeFade)), 0.5)

# Dispatcher

proc drawDesktopBgThemeFx*(bgType: DesktopBgType, screenWidth, screenHeight: int32,
                           time: float32) =
  ## Layered between the shared backdrop and the wallpaper cube.
  let w = screenWidth.float32
  let h = screenHeight.float32
  case bgType
  of dbgDefault: discard   # the hand-crafted wallpaper in os_desktop.nim
  of dbgNeon: drawNeonCityFx(w, h, time)
  of dbgMatrix: drawDataRainFx(w, h, time)
  of dbgVoid: drawDeepVoidFx(w, h, time)
  of dbgSunrise: drawSunriseFx(w, h, time)
  of dbgOcean: drawNeuralNetFx(w, h, time)
  of dbgInferno: drawInfernoFx(w, h, time)
  of dbgPortal: drawPortalFx(w, h, time)
