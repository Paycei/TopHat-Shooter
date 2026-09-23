## Icon Drawing System - Modern OS Theme with detail
## All icons drawn programmatically using shapes with depth and polish

import raylib, rlgl, math
import ../types, ../utils

type
  CurrencyIconType* = enum
    ciNone,
    ciCredits,
    ciDataShards,
    ciCore,
    ciHeat,
    ciXp

proc drawLockIcon*(x, y, size: int32,
                   color: Color = Color(r: 170, g: 182, b: 198, a: 255)) =
  ## Programmatic padlock used to mark undiscovered / locked content. Drawn to
  ## fill the `size` x `size` box anchored at (x, y), mirroring drawPowerUpIcon's
  ## footprint so it slots into the same icon area.
  let fx = x.float32
  let fy = y.float32
  let s  = size.float32

  # Lock body: rounded rectangle filling the lower ~55% of the box.
  let bodyW = s * 0.74
  let bodyH = s * 0.52
  let bodyX = fx + (s - bodyW) * 0.5
  let bodyY = fy + s - bodyH
  drawRectangleRounded(Rectangle(x: bodyX, y: bodyY, width: bodyW, height: bodyH),
                       0.32, 6, color)

  # Shackle: the top half of a ring tucked into the body's top edge (180deg->360deg
  # passes through the top because raylib angles run clockwise with +Y down).
  let shackleR = s * 0.27
  let shackleW = s * 0.10
  drawRing(Vector2(x: fx + s * 0.5, y: bodyY),
           shackleR - shackleW, shackleR, 180.0, 360.0, 24, color)

  # Keyhole: a dark circle with a slit, centred on the body.
  let khColor = Color(r: 25, g: 30, b: 40, a: color.a)
  let khCX = fx + s * 0.5
  let khCY = bodyY + bodyH * 0.42
  drawCircle(Vector2(x: khCX, y: khCY), s * 0.085, khColor)
  drawRectangle(int32(khCX - s * 0.03), int32(khCY),
                max(1'i32, int32(s * 0.06)), int32(s * 0.17), khColor)

proc drawCurrencyIcon*(cx, cy, size: int32, iconType: CurrencyIconType,
                       alpha: uint8 = 255) =
  ## Draw compact currency/status icons for HUDs and shops.
  if iconType == ciNone:
    return

  let radius = max(5.0'f32, size.float32 * 0.42'f32)
  let shadow = Color(r: 0, g: 0, b: 0, a: uint8(min(150, alpha.int)))

  case iconType
  of ciCredits:
    let outer = Color(r: 255, g: 215, b: 0, a: alpha)
    let inner = Color(r: 205, g: 160, b: 0, a: alpha)
    drawCircle(Vector2(x: (cx + 1).float32, y: (cy + 2).float32), radius, shadow)
    drawCircle(Vector2(x: cx.float32, y: cy.float32), radius, outer)
    drawCircle(Vector2(x: cx.float32, y: cy.float32), radius * 0.72'f32, inner)
    drawCircleLines(cx, cy, radius, Color(r: 255, g: 242, b: 130, a: alpha))
    drawText("$", cx - size div 7, cy - size div 3, max(8'i32, size div 2),
             Color(r: 55, g: 42, b: 0, a: alpha))
  of ciDataShards:
    let edge = Color(r: 255, g: 215, b: 0, a: alpha)
    let fill = Color(r: 70, g: 215, b: 255, a: alpha)
    let glow = Color(r: 70, g: 215, b: 255, a: uint8(alpha.int div 3))
    let top = Vector2(x: cx.float32, y: cy.float32 - radius)
    let left = Vector2(x: cx.float32 - radius * 0.82'f32, y: cy.float32 + radius * 0.72'f32)
    let right = Vector2(x: cx.float32 + radius * 0.82'f32, y: cy.float32 + radius * 0.72'f32)
    drawCircle(Vector2(x: cx.float32, y: cy.float32), radius * 1.05'f32, glow)
    drawTriangle(top, left, right, fill)
    drawTriangleLines(top, left, right, edge)
    drawLine(cx, cy - (radius * 0.72'f32).int32, cx, cy + (radius * 0.45'f32).int32,
             Color(r: 220, g: 255, b: 255, a: alpha))
    drawCircle(Vector2(x: (cx - 2).float32, y: (cy - 3).float32), max(1.5'f32, radius * 0.16'f32),
               Color(r: 255, g: 255, b: 255, a: uint8(min(220, alpha.int))))
  of ciCore:
    let core = Color(r: 255, g: 95, b: 42, a: alpha)
    let hot = Color(r: 255, g: 214, b: 78, a: alpha)
    drawCircle(Vector2(x: (cx + 1).float32, y: (cy + 2).float32), radius, shadow)
    drawCircle(Vector2(x: cx.float32, y: cy.float32), radius, core)
    drawCircle(Vector2(x: cx.float32, y: cy.float32), radius * 0.52'f32, hot)
    drawCircleLines(cx, cy, radius * 1.16'f32, Color(r: 255, g: 130, b: 80, a: uint8(alpha.int div 2)))
    drawTriangle(
      Vector2(x: cx.float32, y: cy.float32 - radius * 0.98'f32),
      Vector2(x: cx.float32 - radius * 0.34'f32, y: cy.float32 - radius * 0.05'f32),
      Vector2(x: cx.float32 + radius * 0.32'f32, y: cy.float32 - radius * 0.08'f32),
      Color(r: 255, g: 245, b: 150, a: uint8(min(230, alpha.int))))
  of ciHeat:
    let heat = Color(r: 255, g: 120, b: 60, a: alpha)
    let bright = Color(r: 255, g: 222, b: 86, a: alpha)
    drawCircle(Vector2(x: cx.float32, y: cy.float32 + radius * 0.28'f32), radius * 0.58'f32, shadow)
    drawTriangle(
      Vector2(x: cx.float32, y: cy.float32 - radius),
      Vector2(x: cx.float32 - radius * 0.68'f32, y: cy.float32 + radius * 0.68'f32),
      Vector2(x: cx.float32 + radius * 0.68'f32, y: cy.float32 + radius * 0.68'f32),
      heat)
    drawCircle(Vector2(x: cx.float32, y: cy.float32 + radius * 0.28'f32), radius * 0.68'f32, heat)
    drawTriangle(
      Vector2(x: cx.float32, y: cy.float32 - radius * 0.42'f32),
      Vector2(x: cx.float32 - radius * 0.28'f32, y: cy.float32 + radius * 0.55'f32),
      Vector2(x: cx.float32 + radius * 0.26'f32, y: cy.float32 + radius * 0.55'f32),
      bright)
  of ciXp:
    # XP orb: soft cyan-green glow + bright core, matching the in-world drawXpOrb
    # so the floating "+N" indicator visually ties back to the orb that was picked up.
    let glow = Color(r: 80, g: 255, b: 200, a: uint8(alpha.int div 4))
    let body = Color(r: 90, g: 255, b: 170, a: alpha)
    let core = Color(r: 220, g: 255, b: 240, a: alpha)
    drawCircle(Vector2(x: cx.float32, y: cy.float32), radius * 1.18'f32, glow)
    drawCircle(Vector2(x: cx.float32, y: cy.float32), radius, body)
    drawCircle(Vector2(x: cx.float32, y: cy.float32), radius * 0.5'f32, core)
    drawCircleLines(cx, cy, radius, Color(r: 180, g: 255, b: 220, a: alpha))
  of ciNone:
    discard

# ---------------------------------------------------------------------------
# Glyph kit -- shared by the power-up and shop icons
# ---------------------------------------------------------------------------
# Glyphs are authored on a 32-unit grid inside an rlgl transform that scales
# them to the requested size, so every primitive here is triangle-based
# (drawCircleLines and the int drawLine emit 1px GL lines that ignore the
# scale). Colour comes from the caller's single tint, alpha included, so a
# greyed-out or fading icon dims as a whole, and every silhouette gets a dark
# ink rim so it reads on any card, row or HUD background.

const
  IconGrid = 32.0'f32
  IconEdge = 2.6'f32   ## ink rim stroke, in grid units

type
  IconPalette = object
    ink, base, light, pale, shade, deep: Color
    steel, steelLight, steelDark: Color   ## near-neutral metal/bone, barely tinted

proc mixShade(c, target: Color, t: float32): Color =
  ## Blend `c` toward `target` by `t` (0..1), keeping c's alpha. Stays inside
  ## the two colours, so unlike `min(c.r + n, 255)` on a uint8 it can't wrap
  ## (that wrap is what painted magenta/lime streaks on the old icons).
  Color(r: uint8(c.r.float32 + (target.r.float32 - c.r.float32) * t),
        g: uint8(c.g.float32 + (target.g.float32 - c.g.float32) * t),
        b: uint8(c.b.float32 + (target.b.float32 - c.b.float32) * t),
        a: c.a)

proc iconPalette(color: Color): IconPalette =
  ## Metal stays close to neutral steel instead of taking the accent: a
  ## blade tinted solid yellow or peach is what made the first pass look
  ## machine-made. The accent goes on hilts, bands and trim instead.
  IconPalette(ink: Color(r: 8, g: 11, b: 18, a: uint8(color.a.int * 220 div 255)),
              base: color,
              light: mixShade(color, White, 0.42'f32),
              pale: mixShade(color, White, 0.78'f32),
              shade: mixShade(color, Black, 0.22'f32),
              deep: mixShade(color, Black, 0.45'f32),
              steel: mixShade(Color(r: 184, g: 193, b: 208, a: color.a), color, 0.12'f32),
              steelLight: mixShade(Color(r: 234, g: 239, b: 246, a: color.a), color, 0.06'f32),
              steelDark: mixShade(Color(r: 98, g: 108, b: 126, a: color.a), color, 0.14'f32))

proc faded(c: Color, f: float32): Color =
  ## Scale alpha, relative to the caller's (possibly already faded) tint.
  withAlpha(c, int(c.a.float32 * f))

proc faded(p: IconPalette, f: float32): IconPalette =
  IconPalette(ink: faded(p.ink, f), base: faded(p.base, f), light: faded(p.light, f),
              pale: faded(p.pale, f), shade: faded(p.shade, f), deep: faded(p.deep, f),
              steel: faded(p.steel, f), steelLight: faded(p.steelLight, f),
              steelDark: faded(p.steelDark, f))

proc sv(x, y: float32): Vector2 {.inline.} = Vector2(x: x, y: y)

proc polar(c: Vector2, r, deg: float32): Vector2 =
  ## Point at distance `r` from `c`. Degrees run clockwise on screen, like
  ## raylib's ring/sector angles.
  let a = degToRad(deg)
  sv(c.x + cos(a) * r, c.y + sin(a) * r)

proc qbez(p0, p1, p2: Vector2, t: float32): Vector2 =
  let u = 1.0'f32 - t
  sv(u * u * p0.x + 2.0'f32 * u * t * p1.x + t * t * p2.x,
     u * u * p0.y + 2.0'f32 * u * t * p1.y + t * t * p2.y)

proc cbez(p0, p1, p2, p3: Vector2, t: float32): Vector2 =
  let u = 1.0'f32 - t
  let (a, b, c, d) = (u * u * u, 3.0'f32 * u * u * t, 3.0'f32 * u * t * t, t * t * t)
  sv(a * p0.x + b * p1.x + c * p2.x + d * p3.x,
     a * p0.y + b * p1.y + c * p2.y + d * p3.y)

proc scalePts(pts: openArray[Vector2], about: Vector2, s: float32): seq[Vector2] =
  for p in pts:
    result.add sv(about.x + (p.x - about.x) * s, about.y + (p.y - about.y) * s)

proc iconTri(a, b, c: Vector2, col: Color) =
  ## Winding-safe triangle. raylib culls clockwise triangles, which silently
  ## dropped the old heart's lower half and the rocket's fins.
  let cross = (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
  if cross < 0.0'f32: drawTriangle(a, b, c, col)
  else: drawTriangle(a, c, b, col)

proc iconFan(pts: openArray[Vector2], col: Color) =
  ## Fill a polygon that is convex (star-shaped around pts[0]).
  for i in 1 ..< pts.len - 1:
    iconTri(pts[0], pts[i], pts[i + 1], col)

proc iconFanAround(c: Vector2, pts: openArray[Vector2], col: Color) =
  ## Fill a closed polygon that is star-shaped around the interior point `c`.
  for i in 0 ..< pts.len:
    iconTri(c, pts[i], pts[(i + 1) mod pts.len], col)

proc iconOutline(pts: openArray[Vector2], thick: float32, col: Color) =
  ## Closed stroke with round joins. Drawn under a fill, half of it survives
  ## as the ink rim.
  for i in 0 ..< pts.len:
    drawLine(pts[i], pts[(i + 1) mod pts.len], thick, col)
    drawCircle(pts[i], thick * 0.5'f32, col)

proc iconStroke(pts: openArray[Vector2], thick: float32, col: Color) =
  ## Open polyline with round joins and caps (for opaque colours: the joins
  ## overlap, which a translucent colour would show).
  for i in 0 ..< pts.len - 1:
    drawLine(pts[i], pts[i + 1], thick, col)
  for p in pts:
    drawCircle(p, thick * 0.5'f32, col)

proc iconInkStroke(pts: openArray[Vector2], thick: float32, col, ink: Color) =
  iconStroke(pts, thick + IconEdge, ink)
  iconStroke(pts, thick, col)

proc iconShape(pts: openArray[Vector2], fill, ink: Color) =
  ## Ink-rimmed convex polygon.
  iconOutline(pts, IconEdge, ink)
  iconFan(pts, fill)

proc iconRect(x0, y0, x1, y1: float32, col: Color) {.inline.} =
  drawRectangle(Rectangle(x: x0, y: y0, width: x1 - x0, height: y1 - y0), col)

proc iconInkRect(x0, y0, x1, y1: float32, fill, ink: Color) =
  const e = IconEdge * 0.5'f32
  iconRect(x0 - e, y0 - e, x1 + e, y1 + e, ink)
  iconRect(x0, y0, x1, y1, fill)

proc iconBrick(x0, y0, x1, y1: float32, fill, top, bottom: Color) =
  iconRect(x0, y0, x1, y1, fill)
  iconRect(x0, y0, x1, y0 + 1.1'f32, top)
  iconRect(x0, y1 - 1.0'f32, x1, y1, bottom)

proc iconDisc(c: Vector2, r: float32, fill, ink: Color) =
  drawCircle(c, r + IconEdge * 0.5'f32, ink)
  drawCircle(c, r, fill)

proc iconArc(c: Vector2, r, a0, a1, thick: float32, col: Color) =
  ## Band of width `thick` along a circular arc (degrees, clockwise).
  drawRing(c, r - thick * 0.5'f32, r + thick * 0.5'f32, a0, a1, 32, col)

proc iconInkArc(c: Vector2, r, a0, a1, thick: float32, col, ink: Color) =
  ## Arc band with an ink rim and round ends.
  for (w, fill) in [(thick + IconEdge, ink), (thick, col)]:
    iconArc(c, r, a0, a1, w, fill)
    drawCircle(polar(c, r, a0), w * 0.5'f32, fill)
    drawCircle(polar(c, r, a1), w * 0.5'f32, fill)

proc iconArcPts(c: Vector2, r, a0, a1: float32, n: int): seq[Vector2] =
  ## n + 1 points along a circular arc from a0 to a1 (degrees, either way).
  for i in 0..n:
    result.add polar(c, r, a0 + (a1 - a0) * i.float32 / n.float32)

# Effect marks. There is deliberately no generic four-point "sparkle": dotted
# over every icon it was the loudest machine-made tell. Each effect gets a
# mark that says what happened -- an impact, a muzzle flash, a glint on glass.

proc iconImpact(c: Vector2, r0, r1: float32, rays: int, a0, span: float32, col, ink: Color) =
  ## Comic-book impact lines: straight rays of alternating reach around `c`,
  ## fanned over `span` degrees starting at a0 (360 = all the way round).
  let step = if span >= 360.0'f32: span / rays.float32
             else: span / max(1, rays - 1).float32
  for i in 0 ..< rays:
    let a = a0 + i.float32 * step
    let reach = if i mod 2 == 0: r1 else: r0 + (r1 - r0) * 0.6'f32
    iconInkStroke([polar(c, r0, a), polar(c, reach, a)], 1.5, col, ink)

proc iconGlint(c: Vector2, len: float32, col: Color) =
  ## Specular glint on glass or polished metal: a long and a short tick.
  const a = -55.0'f32
  drawLine(polar(c, len * 0.5'f32, a + 180.0'f32), polar(c, len * 0.5'f32, a), 1.3, col)
  let c2 = polar(c, 2.3, a + 90.0'f32)
  drawLine(polar(c2, len * 0.22'f32, a + 180.0'f32), polar(c2, len * 0.22'f32, a), 1.3, col)

proc iconFlash(p: Vector2, dirDeg, size: float32, fill, ink: Color) =
  ## Muzzle flash: one long forward prong between two swept side prongs.
  const Spec = [(-75.0'f32, 0.5'f32), (-40.0'f32, 0.22'f32), (0.0'f32, 1.0'f32),
                (40.0'f32, 0.22'f32), (75.0'f32, 0.5'f32), (140.0'f32, 0.18'f32),
                (220.0'f32, 0.18'f32)]
  var pts: seq[Vector2]
  for s in Spec: pts.add polar(p, size * s[1], dirDeg + s[0])
  iconOutline(pts, IconEdge, ink)
  iconFanAround(p, pts, fill)

proc iconTaper(p0, p1, p2: Vector2, width: float32, bothEnds: bool, fill, ink: Color) =
  ## Band swept along a curve. bothEnds: pointed at both ends and widest
  ## mid-way (cut marks); otherwise full width at p0 tapering to a point at
  ## p2 (horns, tails).
  const Steps = 12
  var left, right: array[Steps + 1, Vector2]
  for i in 0..Steps:
    let t = i.float32 / Steps.float32
    let p = qbez(p0, p1, p2, t)
    let q = qbez(p0, p1, p2, min(1.0'f32, t + 0.02'f32))
    let o = qbez(p0, p1, p2, max(0.0'f32, t - 0.02'f32))
    let len = max(0.0001'f32, sqrt((q.x - o.x) * (q.x - o.x) + (q.y - o.y) * (q.y - o.y)))
    let (dx, dy) = ((q.x - o.x) / len, (q.y - o.y) / len)
    let w = width * 0.5'f32 * (if bothEnds: sin(PI.float32 * t) else: 1.0'f32 - t)
    left[i] = sv(p.x - dy * w, p.y + dx * w)
    right[i] = sv(p.x + dy * w, p.y - dx * w)
  var rim: seq[Vector2]
  for p in left: rim.add p
  for i in countdown(Steps - 1, 0): rim.add right[i]
  iconOutline(rim, IconEdge, ink)
  for i in 0 ..< Steps:
    iconTri(left[i], left[i + 1], right[i + 1], fill)
    iconTri(left[i], right[i + 1], right[i], fill)

# Shading. Hard-edged cel shadows on the lower right, never a glossy white
# dot on the upper left (the other stock "sticker" tell).

proc iconShadedDisc(c: Vector2, r: float32, fill, shadow, ink: Color) =
  ## Disc with a crisp crescent of shadow: the lit disc sits inside the
  ## shadow disc, tangent to it at the upper left.
  drawCircle(c, r + IconEdge * 0.5'f32, ink)
  drawCircle(c, r, shadow)
  let d = r * 0.18'f32 * 0.7071'f32
  drawCircle(sv(c.x - d, c.y - d), r * 0.82'f32, fill)

proc iconCelFill(c: Vector2, pts: openArray[Vector2], fill, shadow: Color) =
  ## Fill a shape that is star-shaped around `c`, leaving a hard band of
  ## shadow on its lower right (a slightly smaller lit copy, nudged up-left).
  iconFanAround(c, pts, shadow)
  var lit: seq[Vector2]
  for p in scalePts(pts, c, 0.88'f32): lit.add sv(p.x - 0.9'f32, p.y - 0.9'f32)
  iconFanAround(sv(c.x - 0.9'f32, c.y - 0.9'f32), lit, fill)

proc iconArrowHead(tip: Vector2, dirDeg, size: float32, fill, ink: Color) =
  ## Filled arrowhead with its point at `tip`, facing dirDeg.
  let back = polar(tip, size, dirDeg + 180.0'f32)
  let l = polar(back, size * 0.62'f32, dirDeg - 90.0'f32)
  let r = polar(back, size * 0.62'f32, dirDeg + 90.0'f32)
  iconOutline([tip, l, r], IconEdge, ink)
  iconTri(tip, l, r, fill)

proc iconPlus(c: Vector2, s: float32, fill, ink: Color) =
  ## Chunky ink-rimmed plus sign, arms reaching `s` from the centre.
  let w = s * 0.42'f32
  const e = IconEdge * 0.5'f32
  iconRect(c.x - w - e, c.y - s - e, c.x + w + e, c.y + s + e, ink)
  iconRect(c.x - s - e, c.y - w - e, c.x + s + e, c.y + w + e, ink)
  iconRect(c.x - w, c.y - s, c.x + w, c.y + s, fill)
  iconRect(c.x - s, c.y - w, c.x + s, c.y + w, fill)

proc iconZigzag(a, b: Vector2, segments: int, amp: float32): seq[Vector2] =
  ## Jagged discharge path from a to b. The kinks alternate sides with
  ## uneven reach, so it reads as an arc of electricity, not a sawtooth.
  const Jitter = [1.0'f32, 0.55, 0.85, 0.4, 0.95, 0.6]
  let (dx, dy) = (b.x - a.x, b.y - a.y)
  let len = max(0.0001'f32, sqrt(dx * dx + dy * dy))
  let (nx, ny) = (-dy / len, dx / len)
  result.add a
  for i in 1 ..< segments:
    let t = i.float32 / segments.float32
    let off = amp * Jitter[i mod Jitter.len] * (if i mod 2 == 0: 1.0'f32 else: -1.0'f32)
    result.add sv(a.x + dx * t + nx * off, a.y + dy * t + ny * off)
  result.add b

proc iconOrbitPt(c: Vector2, rx, ry, tiltDeg, a: float32): Vector2 =
  ## Point at angle `a` on an ellipse (radii rx, ry) tilted by tiltDeg.
  let (lx, ly) = (rx * cos(degToRad(a)), ry * sin(degToRad(a)))
  let (ct, st) = (cos(degToRad(tiltDeg)), sin(degToRad(tiltDeg)))
  sv(c.x + lx * ct - ly * st, c.y + lx * st + ly * ct)

proc iconTiltedRing(c: Vector2, tiltDeg, squash, rIn, rOut, a0, a1: float32, col: Color) =
  ## Ring seen at an angle: squashed to an ellipse, then tilted.
  rlgl.pushMatrix()
  rlgl.translatef(c.x, c.y, 0.0'f32)
  rlgl.rotatef(tiltDeg, 0.0'f32, 0.0'f32, 1.0'f32)
  rlgl.scalef(1.0'f32, squash, 1.0'f32)
  drawRing(sv(0, 0), rIn, rOut, a0, a1, 40, col)
  rlgl.popMatrix()

proc iconHeartPts(c: Vector2, k: float32): array[40, Vector2] =
  ## Parametric heart (x = 16 sin^3 t, y = 13cos t - 5cos 2t - 2cos 3t -
  ## cos 4t) whose fan centre -- inside both lobes -- lands on `c`. At
  ## k = 0.8 it spans ~26 x 23 grid units.
  for i in 0 ..< 40:
    let t = i.float32 / 40.0'f32 * 2.0'f32 * PI.float32
    let st = sin(t)
    let hx = 16.0'f32 * st * st * st
    let hy = 13.0'f32 * cos(t) - 5.0'f32 * cos(2.0'f32 * t) -
             2.0'f32 * cos(3.0'f32 * t) - cos(4.0'f32 * t)
    result[i] = sv(c.x + hx * k, c.y - (hy + 2.5'f32) * k)

proc iconHeart(c: Vector2, k: float32, fill, shadow, ink: Color) =
  let pts = iconHeartPts(c, k)
  iconOutline(pts, IconEdge, ink)
  iconCelFill(c, pts, fill, shadow)

proc iconShieldPts(cx, top, w, h: float32): seq[Vector2] =
  ## Heater shield: flat top, straight shoulders, flanks curving to a point.
  let hw = w * 0.5'f32
  let shoulder = top + h * 0.4'f32
  let knee = top + h * 0.8'f32
  let point = sv(cx, top + h)
  result.add sv(cx - hw, top)
  result.add sv(cx + hw, top)
  for i in 0..6:
    result.add qbez(sv(cx + hw, shoulder), sv(cx + hw, knee), point, i.float32 / 6.0'f32)
  for i in 1..6:
    result.add qbez(sv(cx - hw, shoulder), sv(cx - hw, knee), point, 1.0'f32 - i.float32 / 6.0'f32)

proc iconShield(cx, top, w, h: float32, pal: IconPalette) =
  ## Ink-rimmed shield with a bevelled face, ready for an emblem on top.
  iconShape(iconShieldPts(cx, top, w, h), pal.base, pal.ink)
  iconFan(iconShieldPts(cx, top + h * 0.12'f32, w * 0.7'f32, h * 0.76'f32), pal.shade)
  drawLine(sv(cx - w * 0.5'f32 + 1.4'f32, top + 1.2'f32),
           sv(cx + w * 0.5'f32 - 1.4'f32, top + 1.2'f32), 1.1, pal.light)

const BoltPts = [(14.0'f32, 2.0'f32), (23.0'f32, 2.0'f32), (18.5'f32, 12.0'f32),
                 (25.0'f32, 12.0'f32), (11.0'f32, 30.0'f32), (14.5'f32, 18.0'f32),
                 (7.0'f32, 18.0'f32)]

proc iconBolt(c: Vector2, k: float32, fill, ink: Color) =
  ## Lightning bolt; at k = 1 it spans the full grid around `c`.
  var b: array[BoltPts.len, Vector2]
  for i, p in BoltPts:
    b[i] = sv(c.x + (p[0] - 16.0'f32) * k, c.y + (p[1] - 16.0'f32) * k)
  iconOutline(b, IconEdge, ink)
  # Concave, so triangulated by hand rather than fanned.
  for tri in [[0, 1, 2], [0, 2, 6], [2, 5, 6], [2, 3, 5], [3, 4, 5]]:
    iconTri(b[tri[0]], b[tri[1]], b[tri[2]], fill)

proc iconBullet(c: Vector2, dirDeg, length: float32, pal: IconPalette) =
  ## Round-nosed bullet centred on `c`, pointing along dirDeg.
  let r = length * 0.24'f32
  let back = -length * 0.5'f32
  let noseLen = r * 1.7'f32
  let noseBase = length * 0.5'f32 - noseLen
  var shell: array[11, Vector2]
  shell[0] = sv(back, r)
  shell[1] = sv(back, -r)
  for j in 0..8:
    let a = degToRad(-90.0'f32 + j.float32 * 22.5'f32)
    shell[2 + j] = sv(noseBase + noseLen * cos(a), r * sin(a))
  var nose: array[10, Vector2]
  nose[0] = sv(noseBase, 0)
  for j in 0..8:
    nose[1 + j] = shell[2 + j]
  rlgl.pushMatrix()
  rlgl.translatef(c.x, c.y, 0.0'f32)
  rlgl.rotatef(dirDeg, 0.0'f32, 0.0'f32, 1.0'f32)
  iconOutline(shell, IconEdge, pal.ink)
  iconRect(back - 1.9'f32, -r - 1.9'f32, back + 2.6'f32, r + 1.9'f32, pal.ink)
  iconFan(shell, pal.base)
  iconFan(nose, pal.light)
  iconRect(back - 0.6'f32, -r - 0.6'f32, back + 1.3'f32, r + 0.6'f32, pal.deep)   # rim
  drawLine(sv(back + 2.0'f32, -r * 0.45'f32), sv(noseBase + noseLen * 0.4'f32, -r * 0.45'f32),
           max(0.8'f32, r * 0.3'f32), pal.pale)
  rlgl.popMatrix()

proc iconSword(c: Vector2, rotDeg, s: float32, pal: IconPalette) =
  ## Arming sword, tip up before rotation, scaled by `s` about `c`: tapered
  ## steel blade with a fuller and a nicked edge, down-swept quillons in the
  ## accent colour, wrapped grip, faceted pommel.
  rlgl.pushMatrix()
  rlgl.translatef(c.x, c.y, 0.0'f32)
  rlgl.rotatef(rotDeg, 0.0'f32, 0.0'f32, 1.0'f32)
  rlgl.scalef(s, s, 1.0'f32)
  let blade = [sv(0, -15.5), sv(2.3, -10), sv(3.3, 3.5), sv(-3.3, 3.5), sv(-2.3, -10)]
  let guard = [sv(-9.8, 7.0), sv(-9.4, 4.6), sv(-2.6, 3.0), sv(2.6, 3.0), sv(9.4, 4.6),
               sv(9.8, 7.0), sv(2.6, 6.4), sv(-2.6, 6.4)]
  let pommel = [sv(0, 11.6), sv(2.4, 14), sv(0, 16.4), sv(-2.4, 14)]
  # Ink silhouette first, so the parts read as one object.
  iconOutline(blade, IconEdge, pal.ink)
  iconOutline(guard, IconEdge, pal.ink)
  iconRect(-3.0, 6.0, 3.0, 12.5, pal.ink)
  iconOutline(pommel, IconEdge, pal.ink)
  # Blade: steel with a darker trailing edge, one bright bevel line, a fuller
  # that stops short of the point, and a nick taken out of the edge.
  iconFan(blade, pal.steel)
  iconFan([sv(0, -15.5), sv(2.3, -10), sv(3.3, 3.5), sv(1.6, 3.5), sv(1.0, -10)], pal.steelDark)
  drawLine(sv(-1.5, -10), sv(-2.2, 2.5), 0.9, pal.steelLight)
  drawLine(sv(0, -8), sv(0, 2.5), 1.1, pal.steelDark)
  iconTri(sv(3.4, -4.3), sv(1.8, -3.2), sv(3.4, -2.1), pal.ink)
  # Down-swept crossguard.
  iconFanAround(sv(0, 5), guard, pal.base)
  drawLine(sv(-8.9, 5.0), sv(-2.6, 3.7), 0.9, pal.light)
  drawLine(sv(2.6, 3.7), sv(8.9, 5.0), 0.9, pal.light)
  # Leather-wrapped grip.
  iconRect(-1.7, 6.4, 1.7, 11.8, pal.deep)
  for yy in [7.5'f32, 9.2'f32, 10.9'f32]:
    drawLine(sv(-1.7, yy + 0.7'f32), sv(1.7, yy - 0.7'f32), 0.8, pal.ink)
  # Faceted pommel: lit facet up-left, shadowed facet down-right.
  iconFan(pommel, pal.base)
  iconFan([sv(0, 11.6), sv(0, 14), sv(-2.4, 14)], pal.light)
  iconFan([sv(0, 14), sv(2.4, 14), sv(0, 16.4)], pal.shade)
  rlgl.popMatrix()

const RaggedReach = [10.5'f32, 5.0, 8.0, 4.6, 11.5, 5.4, 7.2, 4.4, 9.4, 5.0, 8.4, 4.2]

proc iconRaggedBurst(c: Vector2, s, rotDeg: float32, pal: IconPalette) =
  ## Hand-cut blast: uneven spikes (never a regular star), a hot inner layer
  ## and a white core.
  var burst: seq[Vector2]
  for i, r in RaggedReach: burst.add polar(c, r * s, rotDeg + i.float32 * 30.0'f32)
  iconOutline(burst, IconEdge, pal.ink)
  iconFanAround(c, burst, pal.base)
  iconFanAround(c, scalePts(burst, c, 0.55'f32), pal.light)
  iconFanAround(c, scalePts(burst, c, 0.25'f32), pal.pale)

proc iconShard(foot: Vector2, tiltDeg, h, w: float32, lit, body, ink: Color) =
  ## Crystal prism standing on `foot`, leaning tiltDeg. The ridge sits off
  ## centre, so its lit face is narrower than its body face.
  rlgl.pushMatrix()
  rlgl.translatef(foot.x, foot.y, 0.0'f32)
  rlgl.rotatef(tiltDeg, 0.0'f32, 0.0'f32, 1.0'f32)
  let hw = w * 0.5'f32
  let tip = sv(w * 0.1'f32, -h)
  let ridge = sv(-w * 0.1'f32, 0)
  let rim = [sv(-hw, 0), sv(-hw, -h + w * 0.9'f32), tip, sv(hw, -h + w * 0.7'f32), sv(hw, 0)]
  iconOutline(rim, IconEdge, ink)
  iconFan([ridge, sv(-hw, 0), sv(-hw, -h + w * 0.9'f32), tip], lit)
  iconFan([ridge, tip, sv(hw, -h + w * 0.7'f32), sv(hw, 0)], body)
  rlgl.popMatrix()

proc iconBrickWall(pal: IconPalette) =
  ## Crenellated brick wall filling the grid.
  const Merlons = [(3.5'f32, 9.0'f32), (13.25'f32, 18.75'f32), (23.0'f32, 28.5'f32)]
  # Ink silhouette, then mortar, then bricks on top of it.
  iconRect(2.2, 8.7, 29.8, 29.8, pal.ink)
  for m in Merlons:
    iconRect(m[0] - 1.3'f32, 3.2, m[1] + 1.3'f32, 10, pal.ink)
  iconRect(3.5, 9, 28.5, 28.5, pal.deep)
  let warm = mixShade(pal.base, pal.light, 0.35'f32)
  for m in Merlons:
    iconBrick(m[0], 4.5, m[1], 9, pal.base, pal.light, pal.shade)
  iconBrick(3.5, 10, 15.5, 15.5, pal.base, pal.light, pal.shade)
  iconBrick(16.5, 10, 28.5, 15.5, warm, pal.pale, pal.shade)
  iconBrick(3.5, 16.5, 9, 22, pal.base, pal.light, pal.shade)
  iconBrick(10, 16.5, 22, 22, warm, pal.pale, pal.shade)
  iconBrick(23, 16.5, 28.5, 22, pal.base, pal.light, pal.shade)
  iconBrick(3.5, 23, 15.5, 28.5, pal.base, pal.light, pal.shade)
  iconBrick(16.5, 23, 28.5, 28.5, pal.base, pal.light, pal.shade)

proc iconChainLink(c: Vector2, rotDeg, len, wid, thick: float32, col, ink: Color) =
  ## Stadium-shaped chain link. raylib grows rounded-rect lines outward, so
  ## the ink pass starts from a rect shrunk by half the rim.
  rlgl.pushMatrix()
  rlgl.translatef(c.x, c.y, 0.0'f32)
  rlgl.rotatef(rotDeg, 0.0'f32, 0.0'f32, 1.0'f32)
  const e = IconEdge * 0.5'f32
  drawRectangleRoundedLines(Rectangle(x: -len * 0.5'f32 + e, y: -wid * 0.5'f32 + e,
                                      width: len - IconEdge, height: wid - IconEdge),
                            1.0, 10, thick + IconEdge, ink)
  drawRectangleRoundedLines(Rectangle(x: -len * 0.5'f32, y: -wid * 0.5'f32, width: len, height: wid),
                            1.0, 10, thick, col)
  rlgl.popMatrix()

# ---------------------------------------------------------------------------
# Power-up icons
# ---------------------------------------------------------------------------

proc drawPowerUpIcon*(x, y, size: int32, powerType: PowerUpType, color: Color) =
  ## Power-up glyph in the shared icon style (see the glyph kit above): one
  ## bold ink-rimmed silhouette per power-up, shaded only from `color`, so
  ## the registry hue, dimmed states and fades (death recap card) all carry.
  ## Elemental families share their element's glyph.
  if size <= 0:
    return

  # Callers frame the box themselves, so keep the glyph a little off its edge.
  let inset = max(1.0'f32, min(3.0'f32, size.float32 * 0.12'f32))
  let k = max(0.01'f32, (size.float32 - inset * 2.0'f32) / IconGrid)
  rlgl.pushMatrix()
  defer: rlgl.popMatrix()
  rlgl.translatef(x.float32 + inset, y.float32 + inset, 0.0'f32)
  rlgl.scalef(k, k, 1.0'f32)

  let pal = iconPalette(color)
  let (ink, base, light, pale, shade, deep) =
    (pal.ink, pal.base, pal.light, pal.pale, pal.shade, pal.deep)
  let mid = sv(16, 16)

  case powerType
  of puDoubleShot:
    # Two-round burst; the trailing round sits a step back.
    drawLine(sv(3, 10), sv(8.5, 10), 1.8, faded(light, 0.6))
    drawLine(sv(1.5, 22), sv(5.5, 22), 1.8, faded(light, 0.6))
    iconBullet(sv(19, 10), 0, 17, pal)
    iconBullet(sv(16, 22), 0, 17, pal)

  of puRotatingShield:
    # Three shields riding a tilted orbit round their wearer; the near one
    # passes in front of them.
    const Tilt = -15.0'f32
    iconTiltedRing(mid, Tilt, 0.5, 11.3, 12.7, 0, 360, faded(light, 0.55))
    for a in [215.0'f32, 330.0'f32]:
      let p = iconOrbitPt(mid, 12, 6, Tilt, a)
      iconShield(p.x, p.y - 4.6'f32, 8, 9.5, pal)
    iconShadedDisc(mid, 4.4, pal.steel, pal.steelDark, ink)
    let front = iconOrbitPt(mid, 12, 6, Tilt, 95)
    iconShield(front.x, front.y - 4.6'f32, 8, 9.5, pal)

  of puMagicalBullets:
    # Homing: a round bending along a dashed track into a locked-on target.
    let (p0, p1, p2) = (sv(3.5, 28.5), sv(4.5, 18), sv(11, 16.3))
    for i in countup(0, 8, 2):
      drawLine(qbez(p0, p1, p2, i.float32 / 10.0'f32),
               qbez(p0, p1, p2, (i + 1).float32 / 10.0'f32), 1.8, faded(light, 0.8))
    iconBullet(sv(16.5, 13.3), -29.5, 11, pal)
    let target = sv(25, 8.5)
    iconShape([sv(target.x, target.y - 2.8'f32), sv(target.x + 2.8'f32, target.y),
               sv(target.x, target.y + 2.8'f32), sv(target.x - 2.8'f32, target.y)], shade, ink)
    for (sx, sy) in [(-1.0'f32, -1.0'f32), (1.0'f32, -1.0'f32), (1.0'f32, 1.0'f32), (-1.0'f32, 1.0'f32)]:
      let corner = sv(target.x + sx * 5.5'f32, target.y + sy * 5.5'f32)
      iconInkStroke([sv(corner.x, corner.y - sy * 2.6'f32), corner,
                     sv(corner.x - sx * 2.6'f32, corner.y)], 1.5, pale, ink)

  of puPiercingShots:
    # One round punched straight through two foes standing in a row.
    let square = sv(7.5, 16)
    let diamond = sv(17.5, 16)
    let foes = [@[sv(3.25, 11.75), sv(11.75, 11.75), sv(11.75, 20.25), sv(3.25, 20.25)],
                @[sv(17.5, 10.5), sv(23, 16), sv(17.5, 21.5), sv(12, 16)]]
    for (c, pts) in [(square, foes[0]), (diamond, foes[1])]:
      iconOutline(pts, IconEdge, ink)
      iconCelFill(c, pts, pal.steel, pal.steelDark)
    drawLine(sv(1.5, 16), sv(23, 16), 2.6, ink)
    drawLine(sv(1.5, 16), sv(23, 16), 1.2, pale)
    for c in [square, diamond]:
      drawCircle(c, 1.7, ink)
    iconBullet(sv(26.5, 16), 0, 8, pal)

  of puMultiShot:
    # Three rounds fanning out of one muzzle.
    let muzzle = sv(5, 16)
    for a in [-36.0'f32, 0.0'f32, 36.0'f32]:
      drawLine(muzzle, polar(muzzle, 9, a), 1.4, faded(light, 0.55))
    for a in [-36.0'f32, 0.0'f32, 36.0'f32]:
      iconBullet(polar(muzzle, 16, a), a, 13, pal)
    iconDisc(muzzle, 3.4, light, ink)

  of puExplosiveBullets:
    # A round going off on contact: a ragged blast at its nose, debris flying.
    iconBullet(sv(11, 19.5), -28, 13, pal)
    iconRaggedBurst(sv(21, 12.5), 1.0, -80, pal)
    for (p, a) in [(sv(28.5, 25.5), 20.0'f32), (sv(30, 4.5), -30.0'f32), (sv(12.5, 4), 60.0'f32)]:
      iconShape([polar(p, 1.7, a), polar(p, 1.1, a + 100.0'f32), polar(p, 1.5, a + 190.0'f32),
                 polar(p, 1.0, a + 280.0'f32)], shade, ink)

  of puLifeSteal, puBloodBullets, puBloodOrb, puBloodAura, puBloodMastery:
    # Blood drop: the tip's flanks run tangent into the round belly.
    let drop = @[sv(16, 3)] & iconArcPts(sv(16, 19.5), 8.5, -31, 211, 18)
    iconOutline(drop, IconEdge, ink)
    iconCelFill(sv(16, 18), drop, base, shade)
    iconArc(sv(16, 19.5), 5.8, 110, 160, 1.4, light)

  of puRapidFire:
    # Overclock: a clock signal on a scope, its pulses crowding closer
    # together as the fire rate spins up.
    drawRectangleRounded(Rectangle(x: 1.7, y: 4.2, width: 28.6, height: 23.6), 0.2, 4, ink)
    drawRectangleRounded(Rectangle(x: 3, y: 5.5, width: 26, height: 21), 0.2, 4, deep)
    for gx in [9.5'f32, 16.0'f32, 22.5'f32]:
      drawLine(sv(gx, 7), sv(gx, 25), 0.7, shade)
    drawLine(sv(4.5, 16), sv(27.5, 16), 0.7, shade)
    var wave = @[sv(4.5, 21)]
    var wx = 4.5'f32
    for period in [7.4'f32, 5.8, 4.4, 3.4]:
      wave.add sv(wx, 10.5)
      wx += period * 0.5'f32
      wave.add sv(wx, 10.5)
      wave.add sv(wx, 21)
      wx += period * 0.5'f32
      wave.add sv(wx, 21)
    wave.add sv(27.5, 21)
    iconStroke(wave, 2.4, base)
    iconStroke(wave, 0.9, pale)

  of puOvercharge:
    # A round gathering power the farther it flies: charge bars rising
    # along its track.
    drawLine(sv(2.5, 22.5), sv(17.5, 22.5), 1.3, faded(light, 0.5))
    for (x, h, col) in [(4.5'f32, 4.0'f32, shade), (9.5'f32, 7.5'f32, base),
                        (14.5'f32, 11.5'f32, light)]:
      iconInkRect(x - 1.6'f32, 21 - h, x + 1.6'f32, 21, col, ink)
    iconBullet(sv(23.5, 14.5), -22, 12, pal)

  of puMaxHealth:
    # Juggernaut: armour-plated heart, riveted round its rim.
    let c = sv(16, 16.5)
    iconHeart(c, 0.82, light, base, ink)
    let plate = iconHeartPts(c, 0.56)
    iconOutline(plate, 1.2, deep)
    iconCelFill(c, plate, base, shade)
    let rivets = iconHeartPts(c, 0.7)
    for i in [5, 12, 17, 23, 28, 35]:
      drawCircle(rivets[i], 1.05, deep)

  of puSpeedBoost:
    # Momentum: Newton's cradle, the end ball swung out and about to drop.
    iconInkStroke([sv(3, 4.5), sv(29, 4.5)], 2.2, base, ink)
    iconInkRect(3.5, 26.2, 28.5, 28.2, shade, ink)
    let pivot = sv(10.8, 5)
    let swung = polar(pivot, 15, 115)
    iconArc(pivot, 15, 95, 108, 1.2, faded(light, 0.6))
    for px in [16.0'f32, 21.2'f32, 26.4'f32]:
      drawLine(sv(px, 5), sv(px, 19.5), 0.8, light)
    drawLine(pivot, swung, 0.8, light)
    for px in [16.0'f32, 21.2'f32, 26.4'f32]:
      iconShadedDisc(sv(px, 19.5), 2.6, pal.steel, pal.steelDark, ink)
    iconShadedDisc(swung, 2.6, base, shade, ink)

  of puCriticalHit:
    # Critical: a jagged hit balloon shouting "!!" -- double damage.
    const Reach = [13.5'f32, 10.0, 14.5, 9.6, 12.5, 10.2, 14.8, 9.8, 13.0, 10.4, 14.2, 9.4,
                   12.8, 10.0]
    var balloon: seq[Vector2]
    for i, r in Reach:
      balloon.add polar(mid, r, -80.0'f32 + i.float32 * (360.0'f32 / Reach.len.float32))
    iconOutline(balloon, IconEdge, ink)
    iconCelFill(mid, balloon, base, shade)
    for x in [12.8'f32, 19.2'f32]:
      iconFan([sv(x - 1.9'f32, 8.5), sv(x + 1.9'f32, 8.5), sv(x + 0.9'f32, 18.5),
               sv(x - 0.9'f32, 18.5)], ink)
      drawCircle(sv(x, 22.2), 1.9, ink)

  of puCurse:
    # Cursed skull with burning eyes.
    let crown = sv(16, 13.5)
    drawCircle(crown, 10.5 + IconEdge * 0.5'f32, ink)
    iconRect(8.7, 18, 23.3, 27.3, ink)
    drawCircle(crown, 10.5, shade)
    drawCircle(sv(crown.x - 1.34'f32, crown.y - 1.34'f32), 8.6, base)
    iconRect(10, 18, 22, 26, base)
    iconRect(19.2, 18, 22, 26, shade)
    iconRect(10, 22.6, 22, 26, shade)
    iconRect(10, 22, 22, 22.9, ink)
    for tx in [13.0'f32, 16.0'f32, 19.0'f32]:
      iconRect(tx - 0.55'f32, 22.6, tx + 0.55'f32, 26, ink)
    for ex in [11.8'f32, 20.2'f32]:
      drawCircle(sv(ex, 14.5), 3.3, ink)
      drawCircle(sv(ex, 14.8), 1.3, pale)
    iconTri(sv(16, 17.6), sv(14.6, 20.4), sv(17.4, 20.4), ink)

  of puBulletSpeed:
    # Lightspeed: an instant tracer beam flaring where it lands.
    drawLine(sv(5, 16), sv(25, 16), 7.0, faded(base, 0.28))
    drawLine(sv(5, 16), sv(25, 16), 4.6, ink)
    drawLine(sv(5, 16), sv(25, 16), 3.0, light)
    drawLine(sv(5, 16), sv(25, 16), 1.1, pale)
    drawLine(sv(9, 10.5), sv(16, 10.5), 1.4, faded(light, 0.55))
    drawLine(sv(12, 21.5), sv(19, 21.5), 1.4, faded(light, 0.55))
    iconDisc(sv(5, 16), 3.4, base, ink)
    iconImpact(sv(25, 16), 2.8, 6.4, 8, 0, 360, pale, ink)
    drawCircle(sv(25, 16), 1.8, pale)

  of puLuckyCoins:
    # Greed: a coin stack with a fresh coin landing on it.
    for i in 0..2:
      let y0 = 24.0'f32 - i.float32 * 3.8'f32
      drawRectangleRounded(Rectangle(x: 1.7, y: y0 - 1.3'f32, width: 17.6, height: 6.0), 0.9, 6, ink)
      drawRectangleRounded(Rectangle(x: 3, y: y0, width: 15, height: 3.4), 0.9, 6,
                           if i == 1: light else: base)
      iconRect(5, y0 + 0.5'f32, 16, y0 + 1.2'f32, faded(pale, 0.7))
    let coin = sv(21.5, 12.5)
    iconShadedDisc(coin, 8, base, shade, ink)
    iconArc(coin, 5.6, 0, 360, 1.3, light)
    iconRect(coin.x - 1.9'f32, coin.y - 1.9'f32, coin.x + 1.9'f32, coin.y + 1.9'f32, ink)

  of puWallMaster:
    # Fortify: sturdier walls.
    iconBrickWall(pal)

  of puRegeneration:
    # Regeneration: a sprout pushing up out of the soil, budding a plus.
    rlgl.pushMatrix()
    rlgl.translatef(16.0'f32, 29.0'f32, 0.0'f32)
    rlgl.scalef(1.0'f32, 0.4'f32, 1.0'f32)
    drawCircleSector(sv(0, 0), 11.0 + IconEdge, 180, 360, 24, ink)
    drawCircleSector(sv(0, 0), 11.0, 180, 360, 24, deep)
    rlgl.popMatrix()
    var stem: seq[Vector2]
    for i in 0..8: stem.add qbez(sv(16, 27), sv(14.5, 18), sv(16.5, 10), i.float32 / 8.0'f32)
    iconInkStroke(stem, 2.2, base, ink)
    for (p0, p1, p2, w, col) in [(sv(15.4, 19.5), sv(10, 13.5), sv(4.5, 15.5), 6.4'f32, light),
                                 (sv(16, 15), sv(22, 7.5), sv(27.5, 10), 7.2'f32, base)]:
      iconTaper(p0, p1, p2, w, true, col, ink)
      iconStroke([qbez(p0, p1, p2, 0.12), qbez(p0, p1, p2, 0.5), qbez(p0, p1, p2, 0.85)],
                 0.8, shade)
    iconPlus(sv(16.5, 7), 3.0, pale, ink)

  of puDodgeChance:
    # Evasion: the body sways clear as a round whizzes past.
    let body = sv(10, 19)
    iconArc(body, 9.5, -30, 30, 1.6, faded(light, 0.75))
    iconArc(body, 12.5, -20, 20, 1.4, faded(light, 0.45))
    iconShadedDisc(body, 6.5, base, shade, ink)
    drawLine(polar(sv(23.5, 10), 6.5, 115), polar(sv(23.5, 10), 16, 115), 1.6, faded(light, 0.6))
    iconBullet(sv(23.5, 10), -65, 12, pal)

  of puBulletRicochet:
    # Round glancing off a wall.
    iconInkRect(25.5, 3, 29, 29, deep, ink)
    for yy in [7.0'f32, 13.0'f32, 19.0'f32, 25.0'f32]:
      drawLine(sv(25.5, yy + 2.5'f32), sv(29, yy - 1.0'f32), 1.0, shade)
    iconInkStroke([sv(3.5, 27), sv(23.5, 16), sv(13.9, 10.6)], 2.0, light, ink)
    iconBullet(sv(9.1, 7.9), 209.3, 11, pal)
    iconImpact(sv(23.5, 16), 2.2, 5.6, 5, 120, 120, pale, ink)

  of puSlowField, puFrostShots, puFrostOrb, puFrostMastery:
    # Ice crystal: long barbed arms alternating with short plated ones
    # around a hollow hexagonal core.
    var segs: seq[(Vector2, Vector2, float32)]
    var plates: seq[Vector2]
    for i in 0..5:
      let a = i.float32 * 60.0'f32 - 90.0'f32
      if i mod 2 == 0:
        segs.add((mid, polar(mid, 13.5, a), 2.6'f32))
        let b = polar(mid, 8.5, a)
        segs.add((b, polar(b, 4.2, a - 45.0'f32), 2.0'f32))
        segs.add((b, polar(b, 4.2, a + 45.0'f32), 2.0'f32))
      else:
        segs.add((mid, polar(mid, 8.5, a), 2.6'f32))
        plates.add polar(mid, 10.2, a)
    for s in segs: iconStroke([s[0], s[1]], s[2] + IconEdge, ink)
    for s in segs: iconStroke([s[0], s[1]], s[2], base)
    for p in plates:
      var hexTip: seq[Vector2]
      for j in 0..5: hexTip.add polar(p, 2.4, j.float32 * 60.0'f32)
      iconShape(hexTip, light, ink)
    var hex: seq[Vector2]
    for i in 0..5: hex.add polar(mid, 4.4, i.float32 * 60.0'f32 - 90.0'f32)
    iconShape(hex, light, ink)
    iconFan(scalePts(hex, mid, 0.45'f32), deep)

  of puRage, puBerserker:
    # Berserker helm: horned, eye slits burning.
    for side in [-1.0'f32, 1.0'f32]:
      iconTaper(sv(16.0'f32 + side * 7.5'f32, 14.5), sv(16.0'f32 + side * 15.5'f32, 13),
                sv(16.0'f32 + side * 12.5'f32, 3), 4.6, false, pal.steelLight, ink)
    let dome = sv(16, 17)
    drawCircleSector(dome, 9.5 + IconEdge * 0.5'f32, 180, 360, 28, ink)
    iconRect(5.2, 16.5, 26.8, 26.3, ink)
    drawCircleSector(dome, 9.5, 180, 360, 28, shade)
    drawCircleSector(sv(15, 17), 8.5, 180, 360, 28, base)
    iconRect(6.5, 17, 25.5, 25, base)
    iconRect(21.5, 17, 25.5, 25, shade)
    iconRect(6.5, 15.8, 25.5, 17.8, pal.steel)       # brow band
    for rx in [8.5'f32, 23.5'f32]:
      drawCircle(sv(rx, 16.8), 0.7, deep)
    iconRect(14.8, 15.8, 17.2, 25.8, pal.steel)      # nose guard
    for side in [-1.0'f32, 1.0'f32]:
      let inner = 16.0'f32 + side * 2.2'f32
      let outer = 16.0'f32 + side * 8.8'f32
      iconFan([sv(outer, 18.6), sv(inner, 19.8), sv(inner, 21.8), sv(outer, 20.6)], ink)
      drawLine(sv(outer - side * 1.2'f32, 19.8), sv(inner + side * 0.6'f32, 20.9), 0.9, pale)

  of puThorns:
    # Spiked shell: whatever hits it gets hurt back.
    var spikes: seq[array[4, Vector2]]
    for i in 0..7:
      let a = i.float32 * 45.0'f32 - 90.0'f32
      spikes.add [polar(mid, 14, a), polar(mid, 8, a - 19.0'f32), polar(mid, 8, a + 19.0'f32),
                  polar(mid, 8, a)]
    for s in spikes: iconOutline([s[0], s[1], s[2]], IconEdge, ink)
    # Each spike is lit on one flank and shadowed on the other.
    for s in spikes:
      iconTri(s[0], s[1], s[3], light)
      iconTri(s[0], s[3], s[2], shade)
    iconShadedDisc(mid, 8.6, base, shade, ink)

  of puBulletSplit:
    # One round breaking into fragments.
    let split = sv(17, 16)
    for a in [-38.0'f32, 0.0'f32, 38.0'f32]:
      drawLine(split, polar(split, 8, a), 1.4, faded(light, 0.6))
    for a in [-38.0'f32, 0.0'f32, 38.0'f32]:
      let p = polar(split, 10.5, a)
      iconShape([polar(p, 3.4, a), polar(p, 1.7, a + 90.0'f32),
                 polar(p, 2.6, a + 180.0'f32), polar(p, 1.7, a - 90.0'f32)], light, ink)
    iconBullet(sv(9.5, 16), 0, 13, pal)
    iconImpact(split, 1.8, 4.4, 6, 0, 360, pale, ink)

  of puChainLightning, puLightningAura, puLightningOrb, puLightningMastery:
    # Chain lightning: jagged arcs jumping from one target to the next, with
    # a stray fork crackling off into the air.
    drawCircleGradient(16, 16, 15.0, faded(base, 0.25), faded(base, 0))
    let (a, b, c) = (sv(5.5, 24.5), sv(14.5, 8), sv(26.5, 21.5))
    let bc = iconZigzag(b, c, 5, 2.6)
    let arcs = [(iconZigzag(a, b, 5, 2.6), 2.4'f32), (bc, 2.4'f32),
                (iconZigzag(bc[2], sv(27.5, 6.5), 3, 1.5), 1.6'f32)]
    for (z, w) in arcs: iconStroke(z, w + IconEdge, ink)
    for (z, w) in arcs: iconStroke(z, w, base)
    for (z, w) in arcs: iconStroke(z, w * 0.4'f32, pale)
    for n in [a, b, c]:
      iconShadedDisc(n, 3.4, pal.steel, pal.steelDark, ink)

  of puPoisonShot, puPoisonAura, puPoisonOrb, puPoisonMastery:
    # Bubbling flask of toxin.
    let bulb = sv(16, 20.5)
    iconRect(11.9, 5.5, 20.1, 14, ink)
    drawRectangleRounded(Rectangle(x: 10.2, y: 1.9, width: 11.6, height: 6.0), 0.5, 4, ink)
    drawCircle(bulb, 8.5 + IconEdge * 0.5'f32, ink)
    drawCircle(bulb, 8.5, deep)
    iconRect(13.2, 5.5, 18.8, 14, deep)
    let liquid = iconArcPts(bulb, 8.5, -10, 190, 18)
    iconFan(liquid, base)
    drawLine(liquid[0], liquid[^1], 1.2, pale)
    drawRectangleRounded(Rectangle(x: 11.5, y: 3.2, width: 9, height: 3.4), 0.5, 4, light)
    iconArc(bulb, 6, 200, 250, 1.3, faded(light, 0.8))
    # Bubbles as rings, not dots, so they read as air in the liquid.
    for (p, r) in [(sv(13, 23.5), 1.8'f32), (sv(19, 25.3), 1.2'f32),
                   (sv(17.5, 15.5), 1.4'f32), (sv(15, 10.5), 1.0'f32)]:
      iconArc(p, r, 0, 360, 0.9, pale)

  of puFireBullets, puFireAura, puFireOrb, puFireMastery:
    # Flame: a leaning main tongue with a lick breaking off to the left, an
    # off-centre hot core (not a stack of scaled copies) and rising embers.
    iconTaper(sv(10, 23), sv(4, 18), sv(6.5, 9), 3.6, false, base, ink)
    const Flame = [(17.0'f32, 2.5'f32), (20.5'f32, 8.0'f32), (24.0'f32, 13.0'f32),
                   (25.3'f32, 18.5'f32), (24.0'f32, 23.5'f32), (20.8'f32, 27.5'f32),
                   (16.0'f32, 29.2'f32), (11.2'f32, 27.5'f32), (8.0'f32, 23.5'f32),
                   (6.8'f32, 18.5'f32), (8.3'f32, 13.5'f32), (10.8'f32, 10.0'f32),
                   (13.5'f32, 8.2'f32), (15.0'f32, 5.5'f32)]
    var outer: seq[Vector2]
    for p in Flame: outer.add sv(p[0], p[1])
    iconOutline(outer, IconEdge, ink)
    iconCelFill(sv(16, 20), outer, base, shade)
    iconFanAround(sv(16.5, 22.5), [sv(17.5, 12), sv(20.5, 18), sv(21, 23), sv(18.5, 27),
                                   sv(14, 27.5), sv(11.5, 24.5), sv(12.5, 20), sv(15.5, 17)], light)
    iconFanAround(sv(16.5, 24.5), [sv(17.2, 18.5), sv(19, 22.5), sv(18.4, 26), sv(15.2, 26.4),
                                   sv(14.2, 23.8)], pale)
    for (p, a) in [(sv(25, 6), -20.0'f32), (sv(28, 11.5), 25.0'f32)]:
      iconShape([polar(p, 1.4, a - 90.0'f32), polar(p, 1.4, a), polar(p, 1.4, a + 90.0'f32),
                 polar(p, 1.4, a + 180.0'f32)], light, ink)

  of puWindBullets, puWindAura, puWindOrb, puWindMastery:
    # Whirlwind: three gust blades curling round a calm eye.
    for k in 0..2:
      let a = k.float32 * 120.0'f32 - 90.0'f32
      iconTaper(polar(mid, 3.4, a), polar(mid, 12.5, a + 35.0'f32),
                polar(mid, 13.8, a + 118.0'f32), 5.4, false, if k == 0: light else: base, ink)
    iconShadedDisc(mid, 3.0, pale, light, ink)

  of puTimeWarp:
    # Chronos: a clock face gone soft and dripping -- time slowed to a sag.
    let c = sv(15.5, 12)
    var face: seq[Vector2]
    for i in 0 ..< 32:
      let a = -180.0'f32 + i.float32 * 11.25'f32
      var p = polar(c, 9.5, a)
      if a > 0.0'f32 and a < 180.0'f32:
        # Sag deepest at the bottom and heavier toward the left.
        let s = sin(degToRad(a))
        p.y += 4.5'f32 * pow(s, 1.5'f32) * (0.55'f32 + 0.45'f32 * a / 180.0'f32)
      face.add p
    # Drips run off the sagging edge (drawn first; the face covers their roots).
    for (x, y0, y1, r) in [(10.75'f32, 22.0'f32, 28.2'f32, 1.9'f32),
                           (18.0'f32, 23.0'f32, 26.4'f32, 1.5'f32)]:
      iconInkStroke([sv(x, y0), sv(x, y1)], 1.8, base, ink)
      iconDisc(sv(x, y1), r, base, ink)
    iconOutline(face, IconEdge + 2.2'f32, ink)
    iconOutline(face, 2.2, base)
    iconCelFill(sv(15.5, 14), face, pale, light)
    for a in [-90.0'f32, 0.0'f32, 180.0'f32]:
      drawLine(polar(c, 6.2, a), polar(c, 7.8, a), 1.2, deep)
    iconStroke([c, polar(c, 5.2, -115)], 1.5, ink)
    iconStroke([c, sv(c.x + 3.5'f32, c.y + 0.8'f32), sv(c.x + 5.2'f32, c.y + 4.2'f32)], 1.3, ink)

  of puGravityWell:
    # Singularity: a black hole wrapped in a tilted accretion disc.
    drawCircleGradient(16, 16, 15.0, faded(base, 0.25), faded(base, 0))
    iconTiltedRing(mid, -22, 0.42, 8.0, 15.0, 180, 360, ink)     # far half
    iconTiltedRing(mid, -22, 0.42, 9.3, 13.7, 180, 360, shade)
    drawCircle(mid, 7.9, ink)
    iconArc(mid, 6.8, 0, 360, 1.3, light)
    iconTiltedRing(mid, -22, 0.42, 8.0, 15.0, 0, 180, ink)       # near half
    iconTiltedRing(mid, -22, 0.42, 9.3, 13.7, 0, 180, base)
    iconTiltedRing(mid, -22, 0.42, 11.2, 12.2, 20, 160, pale)

  of puPhaseShift:
    # Phase Walker: dash forward out of a hollow afterimage.
    for yy in [12.5'f32, 17.0'f32, 21.5'f32]:
      drawLine(sv(10, yy), sv(20, yy), 1.5, faded(light, 0.55))
    let ghost = sv(8, 17)
    drawCircle(ghost, 5.5, faded(light, 0.22))
    for i in 0..7:
      let a = i.float32 * 45.0'f32
      iconArc(ghost, 5.5, a, a + 26.0'f32, 1.3, faded(pale, 0.75))
    iconShadedDisc(sv(23, 17), 6.5, base, shade, ink)

  of puEchoShots:
    # A round trailed by fading echoes of itself.
    iconBullet(sv(5.5, 16), 0, 8, faded(pal, 0.3))
    iconBullet(sv(13, 16), 0, 11, faded(pal, 0.55))
    iconBullet(sv(22.5, 16), 0, 13, pal)

  of puRotatingOrbs, puArcaneBullets, puArcaneAura, puArcaneOrb, puArcaneMastery:
    # Arcane crystal cluster: three prisms of different height and lean
    # growing out of one rock.
    iconShard(sv(10.5, 26.5), -24, 13, 6, light, shade, ink)
    iconShard(sv(21.5, 26.5), 20, 15, 6.5, light, shade, ink)
    iconShard(sv(15.5, 27), -4, 22, 8.5, pale, base, ink)
    iconGlint(sv(18, 12.5), 5, pale)
    iconShape([sv(4.5, 29), sv(27.5, 29), sv(25, 25.5), sv(19, 24.5), sv(11, 24.8),
               sv(6.5, 26)], deep, ink)

  of puParry:
    # Shield turning a shot straight back.
    iconShield(20.5, 5.5, 14, 20, pal)
    iconInkStroke([sv(3, 8), sv(11.5, 15.5), sv(5, 23)], 2.0, light, ink)
    iconArrowHead(sv(3.96, 24.2), 131, 5.5, light, ink)
    iconImpact(sv(12, 15.5), 1.8, 4.8, 5, 120, 120, pale, ink)

  of puRadialBurst:
    # Rounds bursting out in every direction.
    for i in 0..7:
      let a = i.float32 * 45.0'f32
      iconBullet(polar(mid, 10.3, a), a, 8.6, pal)
    iconShadedDisc(mid, 4.2, light, base, ink)

  of puWallTurrets:
    # Wall Sentinels: a turret dome mounted on a brick wall.
    let pivot = sv(16, 16.5)
    iconInkStroke([pivot, polar(pivot, 12, -38)], 3.4, light, ink)
    drawCircleSector(sv(16, 17.5), 7.0 + IconEdge * 0.5'f32, 180, 360, 24, ink)
    drawCircleSector(sv(16, 17.5), 7.0, 180, 360, 24, base)
    iconArc(sv(16, 17.5), 4.6, 200, 250, 1.4, light)
    iconRect(2.2, 16.2, 29.8, 29.8, ink)
    iconRect(3.5, 17.5, 28.5, 28.5, deep)
    iconBrick(3.5, 17.5, 15.5, 22.5, base, light, shade)
    iconBrick(16.5, 17.5, 28.5, 22.5, base, light, shade)
    iconBrick(3.5, 23.5, 9, 28.5, base, light, shade)
    iconBrick(10, 23.5, 22, 28.5, base, light, shade)
    iconBrick(23, 23.5, 28.5, 28.5, base, light, shade)
    iconFlash(polar(pivot, 12.5, -38), -38, 5.5, pale, ink)

  of puHeavyRounds:
    # Cannonball ploughing forward.
    for yy in [11.0'f32, 16.5'f32, 22.0'f32]:
      drawLine(sv(1.5, yy), sv(6.5, yy), 1.8, faded(light, 0.6))
    iconShadedDisc(sv(18.5, 16.5), 10.5, base, shade, ink)
    iconArc(sv(17.2, 15.2), 6.4, 195, 255, 1.3, light)

  of puPulseArmor:
    # Breastplate (pauldrons out at the shoulders) throwing off a shockwave.
    let c = sv(16, 17)
    for side in [0.0'f32, 180.0'f32]:
      iconInkArc(c, 14, side - 24.0'f32, side + 24.0'f32, 1.8, light, ink)
    let plate = [sv(9, 7), sv(13.5, 5.5), sv(16, 8), sv(18.5, 5.5), sv(23, 7), sv(26, 11),
                 sv(23, 13.5), sv(22, 21.5), sv(16, 26), sv(10, 21.5), sv(9, 13.5), sv(6, 11)]
    iconOutline(plate, IconEdge, ink)
    iconFanAround(sv(16, 15), plate, base)
    iconFan([sv(9, 7), sv(13.5, 5.5), sv(12, 9.5), sv(9, 13.5), sv(6, 11)], light)
    iconFan([sv(23, 7), sv(18.5, 5.5), sv(20, 9.5), sv(23, 13.5), sv(26, 11)], shade)
    drawLine(sv(16, 9.5), sv(16, 24.5), 1.1, deep)
    drawLine(sv(11, 16), sv(15, 17.5), 1.1, shade)
    drawLine(sv(21, 16), sv(17, 17.5), 1.1, shade)

  of puFortified:
    # Castle tower.
    const Merlons = [(7.5'f32, 11.5'f32), (14.0'f32, 18.0'f32), (20.5'f32, 24.5'f32)]
    for m in Merlons:
      iconRect(m[0] - 1.3'f32, 2.7, m[1] + 1.3'f32, 9, ink)
    iconRect(6.2, 7.2, 25.8, 13.3, ink)
    iconRect(8.2, 11, 23.8, 29.8, ink)
    iconRect(9.5, 12, 22.5, 28.5, base)
    iconRect(7.5, 8.5, 24.5, 12, light)
    for m in Merlons:
      iconRect(m[0], 4, m[1], 8.5, light)
      iconRect(m[0], 4, m[1], 4.9, pale)
    iconRect(9.5, 12, 22.5, 13, shade)
    drawLine(sv(9.5, 18), sv(13, 18), 1.0, shade)
    drawLine(sv(19, 22.5), sv(22.5, 22.5), 1.0, shade)
    iconRect(15, 14.5, 17, 18.5, ink)
    iconRect(13.5, 22, 18.5, 28.5, ink)
    drawCircle(sv(16, 22), 2.5, ink)

  of puBulwark:
    # Riveted plate, cracked down one side: the bonus is what's still intact.
    let plate = [sv(9, 4.5), sv(23, 4.5), sv(26.5, 8), sv(26.5, 21.5), sv(16, 28.5),
                 sv(5.5, 21.5), sv(5.5, 8)]
    iconShape(plate, base, ink)
    iconFan(scalePts(plate, sv(16, 15.5), 0.76), light)
    for r in [sv(9.5, 8.5), sv(22.5, 8.5), sv(9, 19.5), sv(23, 19.5)]:
      drawCircle(r, 1.4, deep)
    iconStroke([sv(21.5, 4.5), sv(19, 10), sv(22, 14), sv(19.5, 19), sv(21.5, 24.5)], 1.5, ink)

  of puSpecialRounds:
    # Every Nth round is special: three plain cartridges, then a painted one
    # riding a little higher, as if being chambered.
    for i in 0..3:
      let x0 = 3.5'f32 + i.float32 * 6.8'f32
      let special = i == 3
      let lift = if special: -2.0'f32 else: 0.0'f32
      let casing = if special: base else: deep
      let head = if special: light else: shade
      let shoulder = 14.0'f32 + lift
      var tip: seq[Vector2]   # half-ellipse nose, 5 wide and 7.5 tall
      for j in 0..8:
        let a = degToRad(180.0'f32 + j.float32 * 22.5'f32)
        tip.add sv(x0 + 2.5'f32 + 2.5'f32 * cos(a), shoulder + 7.5'f32 * sin(a))
      iconOutline(tip, IconEdge, ink)
      iconRect(x0 - 1.3'f32, 14 + lift, x0 + 6.3'f32, 28.3'f32 + lift, ink)
      iconFan(tip, head)
      iconRect(x0, 14 + lift, x0 + 5, 27 + lift, casing)
      iconRect(x0 - 0.4'f32, 25.6'f32 + lift, x0 + 5.4'f32, 27 + lift, if special: shade else: ink)
      if special:
        iconRect(x0, 15.6'f32 + lift, x0 + 5, 17.2'f32 + lift, pale)

  of puGiantSlayer:
    # A slice carved out of a giant's health: percentage damage.
    let c = sv(15, 17.5)
    drawCircleSector(c, 11.5 + IconEdge * 0.5'f32, 0, 300, 40, ink)
    drawLine(c, polar(c, 12.8, 0), IconEdge, ink)
    drawLine(c, polar(c, 12.8, 300), IconEdge, ink)
    drawCircleSector(c, 11.5, 0, 300, 40, base)
    iconArc(c, 9.6, 190, 250, 1.3, light)
    let w = polar(c, 3.8, -30)
    drawCircleSector(w, 11.5 + IconEdge * 0.5'f32, -60, 0, 12, ink)
    drawLine(w, polar(w, 12.8, 0), IconEdge, ink)
    drawLine(w, polar(w, 12.8, -60), IconEdge, ink)
    drawCircleSector(w, 11.5, -60, 0, 12, light)

  of puCelestialVeil:
    # A starlit veil domed over its wearer, with its two charges (the two
    # hits it turns aside each wave) shown as pips above.
    let foot = sv(16, 26)
    drawCircleSector(foot, 12, 180, 360, 32, faded(base, 0.45))
    iconArc(foot, 10.2, 200, 250, 1.2, faded(pale, 0.8))
    for (p, r) in [(sv(10.5, 19), 0.8'f32), (sv(21.5, 17), 0.9'f32), (sv(13, 15.5), 0.6'f32),
                   (sv(19.5, 21.5), 0.6'f32)]:
      drawCircle(p, r, pale)
    iconShadedDisc(sv(16, 22.5), 3.2, light, base, ink)
    iconInkArc(foot, 12, 180, 360, 2.2, light, ink)
    iconInkStroke([sv(2.5, 26), sv(29.5, 26)], 1.6, shade, ink)
    for px in [12.5'f32, 19.5'f32]:
      iconShape([sv(px, 3), sv(px + 2.4'f32, 6), sv(px, 9), sv(px - 2.4'f32, 6)], pale, ink)

  of puVolatile:
    # Unstable core: a cracked orb with energy flaring out through the splits.
    drawCircleGradient(16, 16, 15.0, faded(base, 0.35), faded(base, 0))
    for (a, len) in [(-60.0'f32, 15.0'f32), (70.0'f32, 13.5'f32), (185.0'f32, 14.5'f32)]:
      iconTaper(polar(mid, 5, a), polar(mid, 10.5, a + 14.0'f32), polar(mid, len, a - 6.0'f32),
                6.0, false, pale, ink)
    iconShadedDisc(mid, 9, base, shade, ink)
    iconStroke([polar(mid, 9, -60), sv(18, 12.5), sv(15, 15), sv(17.5, 18.5), polar(mid, 9, 70)],
               1.8, ink)
    iconStroke([sv(15, 15), sv(11, 16.5), polar(mid, 9, 185)], 1.8, ink)
    iconStroke([polar(mid, 9, -60), sv(18, 12.5), sv(15, 15), sv(17.5, 18.5), polar(mid, 9, 70)],
               0.8, pale)
    iconStroke([sv(15, 15), sv(11, 16.5), polar(mid, 9, 185)], 0.8, pale)

  of puResonance:
    # Tuning fork, ringing.
    for side in [-1.0'f32, 1.0'f32]:
      let a = if side < 0: 180.0'f32 else: 0.0'f32
      let src = sv(16.0'f32 + side * 4.0'f32, 10)
      iconArc(src, 7.5, a - 25.0'f32, a + 25.0'f32, 1.5, light)
      iconArc(src, 10.5, a - 18.0'f32, a + 18.0'f32, 1.3, faded(light, 0.6))
    iconRect(9.2, 3, 14.8, 16, ink)
    iconRect(17.2, 3, 22.8, 16, ink)
    drawRing(sv(16, 16), 1.2, 6.8, 0, 180, 20, ink)
    iconRect(13.3, 19, 18.7, 27, ink)
    drawCircle(sv(16, 27.5), 3.7, ink)
    iconRect(10.5, 4.3, 13.5, 16, base)
    iconRect(18.5, 4.3, 21.5, 16, base)
    drawRing(sv(16, 16), 2.5, 5.5, 0, 180, 20, base)
    iconRect(14.6, 21, 17.4, 27, base)
    drawCircle(sv(16, 27.5), 2.4, base)
    drawLine(sv(11.6, 5.5), sv(11.6, 15), 0.9, pale)

  of puBloodPact:
    # Cracked heart: health paid in for power.
    iconHeart(sv(16, 16.5), 0.8, base, shade, ink)
    iconStroke([sv(16, 10.5), sv(13.8, 14), sv(17.8, 17.5), sv(14.2, 21.5), sv(16, 25)], 1.7, ink)

  of puConduit:
    # A core wired to three charged nodes, ready to discharge them.
    let c = sv(16, 17)
    let nodes = [polar(c, 11.5, -90), polar(c, 11.5, 30), polar(c, 11.5, 150)]
    for n in nodes: iconInkStroke([c, n], 2.0, light, ink)
    for n in nodes:
      iconShadedDisc(n, 3.4, light, base, ink)
    var hex: seq[Vector2]
    for i in 0..5: hex.add polar(c, 6, i.float32 * 60.0'f32 - 90.0'f32)
    iconShape(hex, base, ink)
    iconFan(scalePts(hex, c, 0.55'f32), deep)
    iconFan(scalePts(hex, c, 0.3'f32), pale)

  of puAftershock:
    # Shockwaves rippling out to both sides of the path just travelled.
    let (p0, p1, p2) = (sv(3.5, 28), sv(5, 11), sv(21, 10.5))
    var path: seq[Vector2]
    for i in 0..12: path.add qbez(p0, p1, p2, i.float32 / 12.0'f32)
    iconInkStroke(path, 2.2, shade, ink)
    for t in [0.2'f32, 0.55'f32]:
      let p = qbez(p0, p1, p2, t)
      let d = sv(2.0'f32 * (1.0'f32 - t) * (p1.x - p0.x) + 2.0'f32 * t * (p2.x - p1.x),
                 2.0'f32 * (1.0'f32 - t) * (p1.y - p0.y) + 2.0'f32 * t * (p2.y - p1.y))
      let along = radToDeg(arctan2(d.y, d.x))
      for side in [-90.0'f32, 90.0'f32]:
        iconInkArc(p, 3.6, along + side - 38.0'f32, along + side + 38.0'f32, 1.5, light, ink)
        iconInkArc(p, 6.4, along + side - 26.0'f32, along + side + 26.0'f32, 1.3, base, ink)
    iconShadedDisc(sv(24, 10.5), 4.8, base, shade, ink)

  of puNova:
    # Rounds frozen in a ring around a pause mark, about to be released.
    iconArc(mid, 11.5, 0, 360, 1.0, faded(light, 0.35))
    for i in 0..7:
      let a = i.float32 * 45.0'f32 + 22.5'f32
      let p = polar(mid, 11.5, a)
      iconShape([polar(p, 3, a), polar(p, 1.6, a + 90.0'f32),
                 polar(p, 3, a + 180.0'f32), polar(p, 1.6, a - 90.0'f32)], light, ink)
    iconInkRect(11.5, 10.5, 14.5, 21.5, pale, ink)
    iconInkRect(17.5, 10.5, 20.5, 21.5, pale, ink)

  of puHealPower:
    # Vital Surge: a heart shedding pluses that grow as they rise --
    # healing amplified.
    iconHeart(sv(13, 19.5), 0.66, base, shade, ink)
    iconPlus(sv(24, 17), 2.2, light, ink)
    iconPlus(sv(26.5, 9.5), 2.8, pale, ink)
    iconPlus(sv(19.5, 5), 3.0, pale, ink)

  of puBountiful:
    # Cornucopia spilling its haul: a tapering horn swept along a curve.
    let (h0, h1, h2, h3) = (sv(21, 11), sv(12, 14), sv(4, 21), sv(8.5, 26.5))
    const Steps = 14
    var left, right: array[Steps + 1, Vector2]
    for i in 0..Steps:
      let t = i.float32 / Steps.float32
      let p = cbez(h0, h1, h2, h3, t)
      let q = cbez(h0, h1, h2, h3, min(1.0'f32, t + 0.01'f32))
      let o = cbez(h0, h1, h2, h3, max(0.0'f32, t - 0.01'f32))
      let len = max(0.0001'f32, sqrt((q.x - o.x) * (q.x - o.x) + (q.y - o.y) * (q.y - o.y)))
      let (dx, dy) = ((q.x - o.x) / len, (q.y - o.y) / len)
      let w = 7.0'f32 * pow(1.0'f32 - t, 0.85'f32) + 0.6'f32
      left[i] = sv(p.x - dy * w, p.y + dx * w)
      right[i] = sv(p.x + dy * w, p.y - dx * w)
    var rim: seq[Vector2]
    for p in left: rim.add p
    for i in countdown(Steps, 0): rim.add right[i]
    iconOutline(rim, IconEdge, ink)
    for i in 0 ..< Steps:
      iconTri(left[i], left[i + 1], right[i + 1], base)
      iconTri(left[i], right[i + 1], right[i], base)
    for i in [4, 8]:
      drawLine(left[i], right[i], 1.2, shade)
    # Mouth: an ellipse across the open end.
    let w0 = 7.6'f32
    rlgl.pushMatrix()
    rlgl.translatef(h0.x, h0.y, 0.0'f32)
    rlgl.rotatef(radToDeg(arctan2(right[0].y - left[0].y, right[0].x - left[0].x)),
                 0.0'f32, 0.0'f32, 1.0'f32)
    rlgl.scalef(1.0'f32, 0.36'f32, 1.0'f32)
    drawCircle(sv(0, 0), w0 + IconEdge * 0.5'f32, ink)
    drawCircle(sv(0, 0), w0, light)
    drawCircle(sv(0, 0), w0 - 1.8'f32, deep)
    rlgl.popMatrix()
    iconShadedDisc(sv(24.5, 6.5), 3.4, light, base, ink)
    iconShadedDisc(sv(27.5, 13), 2.8, pale, light, ink)
    iconShadedDisc(sv(19, 4), 2.2, base, shade, ink)

  of puGlitchField:
    # Glitched block: slices knocked out of alignment.
    const Offsets = [0.0'f32, 3.2, -2.6, 4.0, -1.2]
    let cols = [base, light, base, shade, light]
    for i, off in Offsets:
      let y0 = 5.5'f32 + i.float32 * 4.4'f32
      iconRect(4.7'f32 + off, y0 - 1.3'f32, 25.3'f32 + off, y0 + 5.7'f32, ink)
    for i, off in Offsets:
      let y0 = 5.5'f32 + i.float32 * 4.4'f32
      iconRect(6.0'f32 + off, y0 + 0.5'f32, 24.0'f32 + off, y0 + 4.4'f32, cols[i])
    iconInkRect(27, 6.5, 29, 8.5, pale, ink)
    iconInkRect(2.5, 18.5, 4.5, 20.5, light, ink)
    iconInkRect(28, 24, 29.8, 25.8, base, ink)

  of puTimeSurge:
    # Clock struck by lightning.
    let c = sv(14.5, 16)
    iconDisc(c, 11.5, deep, ink)
    iconArc(c, 10.3, 0, 360, 2.2, base)
    for i in 0..3:
      let a = i.float32 * 90.0'f32
      drawLine(polar(c, 5.8, a), polar(c, 8, a), 1.5, pale)
    iconStroke([c, polar(c, 7, -90)], 1.8, pale)
    iconStroke([c, polar(c, 5, 30)], 1.8, light)
    drawCircle(c, 1.6, pale)
    iconBolt(sv(24.5, 21.5), 0.46, pale, ink)

  of puLastStand:
    # Shield with a heartbeat still running across it.
    iconShield(16, 4, 22, 25, pal)
    iconInkStroke([sv(3.5, 16.5), sv(10, 16.5), sv(12.3, 12), sv(15.3, 22),
                   sv(18.3, 8.5), sv(20.8, 16.5), sv(28.5, 16.5)], 1.9, pale, ink)

  of puRecursion:
    # Nested squares, each a turned copy of the last.
    const Levels = [(25.0'f32, 0.0'f32), (17.5'f32, 18.0'f32), (12.0'f32, 36.0'f32), (6.5'f32, 54.0'f32)]
    let cols = [base, deep, light, pale]
    for i, lv in Levels:
      let s = lv[0]
      drawRectangle(Rectangle(x: 16, y: 16, width: s + IconEdge, height: s + IconEdge),
                    sv((s + IconEdge) * 0.5'f32, (s + IconEdge) * 0.5'f32), lv[1], ink)
      drawRectangle(Rectangle(x: 16, y: 16, width: s, height: s),
                    sv(s * 0.5'f32, s * 0.5'f32), lv[1], cols[i])

  of puSectorProtocol:
    # 3x3 sector map with a coin at its heart.
    iconRect(2.7, 2.7, 29.3, 29.3, ink)
    for row in 0..2:
      for col in 0..2:
        let x0 = 4.0'f32 + col.float32 * 8.5'f32
        let y0 = 4.0'f32 + row.float32 * 8.5'f32
        let fill = if row == 1 and col == 1: light
                   elif (row + col) mod 2 == 0: base
                   else: shade
        iconRect(x0, y0, x0 + 7.5'f32, y0 + 7.5'f32, fill)
        iconRect(x0, y0, x0 + 7.5'f32, y0 + 0.9'f32, faded(pale, 0.5))
    iconDisc(mid, 2.7, pale, ink)

  of puCrisisMode:
    # Crisis Mode: battery down to its last cell, output spiking anyway.
    iconInkRect(25, 12.5, 28.2, 19.5, pal.steel, ink)
    drawRectangleRounded(Rectangle(x: 1.7, y: 8.2, width: 24.6, height: 15.6), 0.25, 4, ink)
    drawRectangleRounded(Rectangle(x: 3, y: 9.5, width: 22, height: 13), 0.25, 4, pal.steelDark)
    iconRect(4.8, 11.3, 23.2, 20.7, deep)
    iconRect(5.8, 12.3, 9.4, 19.7, base)
    iconStroke([sv(10.8, 16), sv(12.9, 16), sv(14.6, 12.4), sv(16.8, 19.6), sv(18.8, 13.2),
                sv(20.3, 16), sv(22.2, 16)], 1.4, pale)

  of puAdaptiveFirewall:
    # Shield with a bolt: getting hit charges it up.
    iconShield(16, 4, 22, 25, pal)
    iconBolt(sv(16, 15.5), 0.5, pale, ink)

  of puLastTransmission:
    # Radio mast still pushing out a fading signal.
    let tip = sv(16, 10)
    for (r, col) in [(5.5'f32, light), (9.5'f32, shade)]:
      iconInkArc(tip, r, 205, 245, 1.8, col, ink)
      iconInkArc(tip, r, 295, 335, 1.8, col, ink)
    iconInkStroke([sv(10.5, 28.5), sv(16, 12)], 2.0, base, ink)
    iconInkStroke([sv(21.5, 28.5), sv(16, 12)], 2.0, base, ink)
    iconInkStroke([sv(12.6, 22), sv(19.4, 22)], 1.6, base, ink)
    iconDisc(tip, 2.6, pale, ink)

  of puKillChain:
    # Three linked chain rings.
    for i, c in [sv(9.5, 22.5), sv(16, 16), sv(22.5, 9.5)]:
      iconChainLink(c, -45, 12, 6.5, 2.2, if i == 1: light else: base, ink)

  of puCorruptedCore:
    # CPU die with a fracture running through it.
    var pins: seq[(float32, float32, float32, float32)]
    for i in 0..2:
      let p = 11.5'f32 + i.float32 * 4.5'f32
      pins.add((p - 1.1'f32, 4.0'f32, p + 1.1'f32, 8.5'f32))
      pins.add((p - 1.1'f32, 23.5'f32, p + 1.1'f32, 28.0'f32))
      pins.add((4.0'f32, p - 1.1'f32, 8.5'f32, p + 1.1'f32))
      pins.add((23.5'f32, p - 1.1'f32, 28.0'f32, p + 1.1'f32))
    for q in pins: iconRect(q[0] - 1.3'f32, q[1] - 1.3'f32, q[2] + 1.3'f32, q[3] + 1.3'f32, ink)
    for q in pins: iconRect(q[0], q[1], q[2], q[3], light)
    drawRectangleRounded(Rectangle(x: 6.7, y: 6.7, width: 18.6, height: 18.6), 0.2, 4, ink)
    drawRectangleRounded(Rectangle(x: 8, y: 8, width: 16, height: 16), 0.2, 4, base)
    iconRect(11.5, 11.5, 20.5, 20.5, deep)
    iconStroke([sv(9.5, 10), sv(13.5, 14.5), sv(12.5, 17), sv(17, 19), sv(16, 21.5),
                sv(21.5, 23)], 1.4, ink)
    iconRect(17.5, 12.5, 19.5, 14.5, pale)
    iconRect(13, 18.8, 14.4, 20.2, light)

  of puRoomEcho:
    # Cleared room sending a charged volley out through its door.
    iconInkStroke([sv(28, 12), sv(28, 4), sv(4, 4), sv(4, 28), sv(28, 28), sv(28, 20)],
                  2.4, base, ink)
    iconArc(sv(20.5, 16), 5, -40, 40, 1.4, faded(light, 0.9))
    iconArc(sv(20.5, 16), 8, -40, 40, 1.4, faded(light, 0.55))
    # Staggered volley (lined up flush, three rounds read as a letter E).
    iconBullet(sv(11.5, 22), -30, 9, pal)
    iconBullet(sv(12.5, 11.5), -30, 9, pal)
    iconBullet(sv(18, 17), -30, 9, pal)

  of puChainReaction:
    # A kill bursting and flinging out a bonus coin.
    iconRaggedBurst(sv(10, 21.5), 0.72, -50, pal)
    for i, t in [0.3'f32, 0.55'f32, 0.8'f32]:
      drawCircle(qbez(sv(12, 14), sv(13, 5), sv(20, 7), t), 1.0'f32 + i.float32 * 0.2'f32,
                 faded(light, 0.8))
    let coin = sv(23, 11.5)
    iconShadedDisc(coin, 6, base, shade, ink)
    iconArc(coin, 4, 0, 360, 1.2, light)
    iconRect(coin.x - 1.4'f32, coin.y - 1.4'f32, coin.x + 1.4'f32, coin.y + 1.4'f32, ink)

  of puKernelExploit:
    # Terminal with a root prompt.
    drawRectangleRounded(Rectangle(x: 1.7, y: 3.7, width: 28.6, height: 24.6), 0.18, 4, ink)
    drawRectangleRounded(Rectangle(x: 3, y: 5, width: 26, height: 22), 0.18, 4, base)
    iconRect(4.5, 10.5, 27.5, 25.5, deep)
    for i in 0..2:
      drawCircle(sv(6.8'f32 + i.float32 * 2.6'f32, 7.7), 0.9, deep)
    iconStroke([sv(8, 14), sv(12, 17.5), sv(8, 21)], 2.0, pale)
    iconRect(14, 20, 21, 22, light)

  of puDataHarvest:
    # Data Harvest: XP orbs streaming into a download tray.
    iconInkStroke([sv(4.5, 19.5), sv(4.5, 27), sv(27.5, 27), sv(27.5, 19.5)], 2.4, base, ink)
    iconInkStroke([sv(16, 3.5), sv(16, 15)], 3.0, light, ink)
    iconArrowHead(sv(16, 22.5), 90, 6.5, light, ink)
    for (p, r) in [(sv(8.5, 8), 2.2'f32), (sv(23.5, 6.5), 2.6'f32), (sv(23, 14.5), 1.7'f32),
                   (sv(9.5, 15.5), 1.5'f32)]:
      iconDisc(p, r, light, ink)
      drawCircle(p, r * 0.45'f32, pale)

# ---------------------------------------------------------------------------
# Shop upgrade icons
# ---------------------------------------------------------------------------

proc drawShopIcon*(x, y, size: int32, itemIndex: int, color: Color) =
  ## Shop upgrade glyph, indexed by shop slot: 0 damage, 1 fire rate, 2 move
  ## speed, 3 max health, 4 bullet speed, 5 walls. Any other index draws a
  ## gear, which the cinematic recorder overlay relies on. Same glyph kit and
  ## 32-unit grid as drawPowerUpIcon, but filling the whole box: the shop
  ## tile supplies its own padding.
  if size <= 0:
    return

  let k = size.float32 / IconGrid
  rlgl.pushMatrix()
  defer: rlgl.popMatrix()
  rlgl.translatef(x.float32, y.float32, 0.0'f32)
  rlgl.scalef(k, k, 1.0'f32)

  let pal = iconPalette(color)
  let (ink, base, light, pale, shade, deep) =
    (pal.ink, pal.base, pal.light, pal.pale, pal.shade, pal.deep)

  case itemIndex
  of 0: # Damage + -- sword angled up-right
    iconSword(sv(17, 15.5), 45, 1.0, pal)

  of 1: # Fire Rate + -- gatling barrel cluster, spinning up
    let c = sv(16, 16)
    # Spin blur: three comet arcs chasing clockwise round the housing.
    for a in [-80.0'f32, 40.0'f32, 160.0'f32]:
      for s in 0..4:
        let a0 = a + s.float32 * 10.0'f32
        iconArc(c, 13.9, a0, a0 + 10.5'f32, 0.6'f32 + s.float32 * 0.4'f32,
                faded(light, 0.3'f32 + s.float32 * 0.17'f32))
    iconShadedDisc(c, 11, pal.steel, pal.steelDark, ink)
    iconArc(c, 9.2, 0, 360, 1.0, pal.steelDark)
    for i in 0..5:
      let p = polar(c, 6.1, -78.0'f32 + i.float32 * 60.0'f32)
      iconDisc(p, 2.3, base, ink)
      drawCircle(p, 1.15, ink)
    iconDisc(c, 1.6, light, ink)

  of 2: # Move Speed + -- the kernel's top hat, dashing
    # Speed streaks thinning away behind it (drawn first; the hat covers
    # their roots).
    for (y0, x0, len) in [(9.0'f32, 16.8'f32, 10.0'f32), (14.5'f32, 16.2'f32, 13.5'f32),
                          (20.0'f32, 15.4'f32, 9.5'f32)]:
      iconTaper(sv(x0, y0), sv(x0 - len * 0.5'f32, y0), sv(x0 - len, y0), 2.6, false, light, ink)
    rlgl.pushMatrix()
    rlgl.translatef(20.0'f32, 24.0'f32, 0.0'f32)
    rlgl.rotatef(10.0'f32, 0.0'f32, 0.0'f32, 1.0'f32)   # leaning into the dash
    let crown = [sv(-6.6, -17), sv(6.6, -17), sv(5.8, -2), sv(-5.8, -2)]
    let brim = Rectangle(x: -10.5, y: -2.8, width: 21, height: 3.6)
    iconOutline(crown, IconEdge, ink)
    drawRectangleRounded(Rectangle(x: brim.x - 1.3'f32, y: brim.y - 1.3'f32,
                                   width: brim.width + 2.6'f32, height: brim.height + 2.6'f32),
                         1.0, 6, ink)
    iconFan(crown, pal.steelDark)
    iconRect(-5.9, -6.2, 5.9, -2.4, base)                        # hat band
    drawLine(sv(-5.3, -16), sv(-4.7, -7), 1.1, pal.steel)       # rim light on the lit edge
    iconRect(-6.4, -17, 6.4, -16, pal.steel)
    drawRectangleRounded(brim, 1.0, 6, pal.steelDark)
    drawLine(sv(-9, -2.2), sv(9, -2.2), 0.9, pal.steel)
    rlgl.popMatrix()

  of 3: # Max Health + -- heart with a plus
    iconHeart(sv(16, 16.5), 0.8, base, shade, ink)
    iconRect(11.8, 14.6, 21.8, 18.2, deep)  # plus, with a drop shadow
    iconRect(15.0, 11.4, 18.6, 21.4, deep)
    iconRect(11, 13.8, 21, 17.2, pale)
    iconRect(14.3, 10.5, 17.7, 20.5, pale)

  of 4: # Bullet Speed + -- bullet with speed streaks
    drawLine(sv(1.5, 16), sv(8.5, 16), 2.2, faded(light, 200.0'f32 / 255.0'f32))
    drawLine(sv(3.5, 11.5), sv(8.5, 11.5), 1.8, faded(light, 130.0'f32 / 255.0'f32))
    drawLine(sv(3.5, 20.5), sv(8.5, 20.5), 1.8, faded(light, 130.0'f32 / 255.0'f32))
    # Body + half-ellipse nose as one outline.
    var shell: array[11, Vector2]
    shell[0] = sv(11, 20)
    shell[1] = sv(11, 12)
    for j in 0..8:
      let a = degToRad(-90.0'f32 + j.float32 * 22.5'f32)
      shell[2 + j] = sv(21.0'f32 + 8.5'f32 * cos(a), 16.0'f32 + 4.0'f32 * sin(a))
    iconOutline(shell, IconEdge, ink)
    iconRect(8.7, 9.9, 13.5, 22.1, ink)     # rim
    iconFan(shell, base)
    var nose: array[10, Vector2]
    nose[0] = sv(21, 16)
    for j in 0..8:
      nose[1 + j] = shell[2 + j]
    iconFan(nose, light)                    # copper tip over the casing
    iconRect(20.4, 12.3, 21.6, 19.7, deep)  # crimp groove
    iconRect(10, 11.2, 12.2, 20.8, deep)
    drawLine(sv(13, 13.7), sv(24, 13.7), 1.2, pale)

  of 5: # Wall (x10) -- crenellated brick wall
    iconBrickWall(pal)

  else: # Gear
    for i in 0..3:
      drawRectangle(Rectangle(x: 16, y: 16, width: 6.4, height: 27.5),
                    sv(3.2, 13.75), i.float32 * 45.0'f32, ink)
    drawCircle(sv(16, 16), 11.3, ink)
    for i in 0..3:
      drawRectangle(Rectangle(x: 16, y: 16, width: 4, height: 25),
                    sv(2, 12.5), i.float32 * 45.0'f32, base)
    drawCircle(sv(16, 16), 10, base)
    drawRing(sv(16, 16), 6.2, 7.6, 0, 360, 24, light)
    drawCircle(sv(16, 16), 4.2, ink)

proc shopIconAccent*(itemIndex: int): Color =
  ## Signature hue per shop slot, so the rows read apart at a glance.
  case itemIndex
  of 0: Color(r: 255, g: 122, b: 72, a: 255)    # damage -- hot orange
  of 1: Color(r: 255, g: 208, b: 72, a: 255)    # fire rate -- amber
  of 2: Color(r: 104, g: 232, b: 140, a: 255)   # move speed -- green
  of 3: Color(r: 255, g: 92, b: 132, a: 255)    # max health -- rose
  of 4: Color(r: 88, g: 204, b: 255, a: 255)    # bullet speed -- cyan
  of 5: Color(r: 178, g: 150, b: 255, a: 255)   # walls -- violet
  else: Color(r: 100, g: 200, b: 255, a: 255)

proc drawShopIconTile*(x, y, size: int32, itemIndex: int, enabled, selected: bool) =
  ## App-style tile (dark glass square, accent frame) holding a shop glyph.
  ## Unaffordable rows drop to a dim grey, so the colour itself says whether
  ## the upgrade can be bought.
  let accent = if enabled: shopIconAccent(itemIndex)
               else: Color(r: 118, g: 126, b: 140, a: 150)
  let fx = x.float32
  let fy = y.float32
  let s = size.float32
  let tile = Rectangle(x: fx, y: fy, width: s, height: s)
  const Round = 0.22'f32
  drawRectangleRounded(Rectangle(x: fx + 2, y: fy + 2, width: s, height: s), Round, 6,
                       Color(r: 0, g: 0, b: 0, a: 90))
  drawRectangleRounded(tile, Round, 6, Color(r: 12, g: 16, b: 26, a: 255))
  # Accent light pooling at the top of the glass (the 2px inset keeps the
  # gradient's square corners inside the tile's rounded ones).
  drawRectangleGradientV(x + 2, y + 2, size - 4, size div 2,
                         withAlpha(accent, if enabled: 42 else: 12), withAlpha(accent, 0))
  if selected and enabled:
    drawCircleGradient(x + size div 2, y + size div 2, s * 0.46'f32,
                       withAlpha(accent, 70), withAlpha(accent, 0))
  drawRectangleRoundedLines(tile, Round, 6, if selected: 2.0'f32 else: 1.5'f32,
                            withAlpha(accent, if selected: 255 elif enabled: 150 else: 70))
  let pad = max(2'i32, size div 9)
  drawShopIcon(x + pad, y + pad, size - pad * 2, itemIndex, accent)
