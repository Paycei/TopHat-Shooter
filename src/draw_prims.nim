## Batch-friendly replacements for raylib's stock 2D primitives.
##
## Two raylib habits made its stock shapes expensive here:
##
##   * drawCircle tessellates every circle into 36 segments (72 vertices, each
##     with its own sin/cos) whatever its size, and 90% of the circles a wave
##     draws are 1-8 px particles, sparks and bullet cores;
##   * drawLine, drawCircleLines, drawRectangleLines, ... emit GL_LINES, which
##     the rlgl batch can't share with filled shapes: every switch between the
##     two starts a new draw call. A GL line is also one *render-target* pixel
##     wide, so under the 2x supersample every outline came out half as wide as
##     it looks at 1x.
## The procs here keep raylib's signatures under new names. Circles take their
## segment count from the size they land at on the render target, and outlines
## are quads that join the fills' (and the default font's) batch.
##
## A 1 px outline is one *virtual* pixel at every supersample and under any
## transform, which is what a GL line looked like at 1x. It follows the rule
## raylib's own drawRectangleLines uses: lines run through pixel centres and
## outlines stroke just inside their shape. A stroke centred on a whole
## coordinate would straddle two pixel rows and come out as a soft double line
## at 2x.
##
## Use them instead of the raylib originals in game code:
##   drawCircle -> drawDisc             drawCircleLines   -> drawCircleOutline
##   drawLine   -> drawStroke           drawRectangleLines -> drawRectOutline
##   drawTriangleLines -> drawTriangleOutline
##   drawPolyLines     -> drawPolyOutline
##   drawEllipseLines  -> drawEllipseOutline

import raylib, rlgl, math
import render_context

type
  ShapesTextureView {.importc: "Texture", header: "raylib.h", completeStruct, bycopy.} = object
    ## raylib's shapes texture (the default font's atlas), looked at but not
    ## owned. naylib's Texture2D unloads itself when it goes out of scope, so
    ## `let t = getShapesTexture()` deletes the atlas every text and shape
    ## draw shares, and the whole frame turns black from then on.
    id: uint32
    width, height, mipmaps, format: int32

proc shapesTextureView(): ShapesTextureView {.importc: "GetShapesTexture", header: "raylib.h".}

proc drawScale(): float32 =
  ## Render-target pixels per local unit at this moment: the rlgl matrix stack
  ## (the frame's supersample, UI scale, world view, icon grids, ...) times the
  ## modelview. Rotation-safe; the larger axis wins under a non-uniform scale.
  template axisScale(m: Matrix): float32 =
    sqrt(max(m.m0 * m.m0 + m.m1 * m.m1, m.m4 * m.m4 + m.m5 * m.m5))
  max(axisScale(getMatrixTransform()) * axisScale(getMatrixModelview()), 1.0e-6'f32)

proc hairlineAt(scale: float32): float32 {.inline.} =
  ## One virtual pixel, in local units, at draw scale `scale`.
  getRenderSupersampleScale() / scale

proc segmentsAt(radius, scale: float32): int32 =
  ## Segments for a full circle of `radius` local units at draw scale `scale`.
  ## raylib's own rule (at most 0.5 px between the polygon and the true circle)
  ## works out to pi * sqrt(radius in pixels), taken at the size the circle
  ## lands on the render target. Kept even, since rlgl's quads hold two
  ## segments each, and capped so a screen-sized shockwave stays affordable.
  let px = max(radius * scale, 0.0'f32)
  var n = int32(ceil(PI.float32 * sqrt(px)))
  n += n and 1
  clamp(n, 6'i32, 64'i32)

proc circleSegments*(radius: float32): int32 =
  ## Segment count drawDisc and drawCircleOutline use for `radius` right now.
  segmentsAt(radius, drawScale())

# ---------------------------------------------------------------------------
# Filled circles
# ---------------------------------------------------------------------------

proc drawDisc*(center: Vector2, radius: float32, color: Color) =
  ## drawCircle with its segment count fitted to the drawn size.
  drawCircleSector(center, radius, 0.0'f32, 360.0'f32, circleSegments(radius), color)

proc drawDisc*(centerX, centerY: int32, radius: float32, color: Color) =
  drawDisc(Vector2(x: centerX.float32, y: centerY.float32), radius, color)

# ---------------------------------------------------------------------------
# Gradients and glows
#
# Light drawn as a stack of translucent discs bands: every disc's rim is a
# visible step. These blend per vertex instead, so a glow fades to nothing
# without contour lines and a lit surface rolls off smoothly. They are quads
# on the shapes texture, in the same batch as every other fill here.
# ---------------------------------------------------------------------------

type
  RadialEase* = enum
    reLinear  ## a straight blend from the centre colour to the rim colour
    reSmooth  ## smoothstep: a lit dome that rolls off toward the rim
    reGlow    ## light: a bright core, a long soft tail, gone exactly at the rim

proc lerpRgba(a, b: Color, t: float32): Color {.inline.} =
  template ch(x, y: uint8): uint8 =
    uint8(clamp(x.float32 + (y.float32 - x.float32) * t + 0.5'f32, 0.0'f32, 255.0'f32))
  Color(r: ch(a.r, b.r), g: ch(a.g, b.g), b: ch(a.b, b.b), a: ch(a.a, b.a))

proc clearOf(c: Color): Color {.inline.} = Color(r: c.r, g: c.g, b: c.b, a: 0)

proc easeAt(ease: RadialEase, t: float32): float32 {.inline.} =
  case ease
  of reLinear: t
  of reSmooth: t * t * (3.0'f32 - 2.0'f32 * t)
  of reGlow:
    # One minus a Gaussian, rescaled so the light reaches exactly 0 at the rim.
    const K = 3.6'f32
    let e0 = exp(-K)
    1.0'f32 - (exp(-K * t * t) - e0) / (1.0'f32 - e0)

template shapesQuads(body: untyped) =
  ## Open a quads batch on the shapes texture; `quadVtx` emits one corner.
  let shapesTex = shapesTextureView()
  let shapesRec = getShapesTextureRectangle()
  let shapesU {.inject.} = (shapesRec.x + shapesRec.width * 0.5'f32) / shapesTex.width.float32
  let shapesV {.inject.} = (shapesRec.y + shapesRec.height * 0.5'f32) / shapesTex.height.float32
  setTexture(shapesTex.id)
  rlBegin(Quads)
  body
  rlEnd()
  setTexture(0)

template quadVtx(px, py: float32, c: Color) =
  color4ub(c.r, c.g, c.b, c.a)
  texCoord2f(shapesU, shapesV)
  vertex2f(px, py)

template emitQuad(p0, p1, p2, p3: Vector2, c0, c1, c2, c3: Color) =
  ## One convex quad in either winding: rlgl culls back faces, and raylib's
  ## front face has a negative signed area in screen space (y down).
  let area = (p0.x * p1.y - p1.x * p0.y) + (p1.x * p2.y - p2.x * p1.y) +
             (p2.x * p3.y - p3.x * p2.y) + (p3.x * p0.y - p0.x * p3.y)
  if area > 0.0'f32:
    quadVtx(p0.x, p0.y, c0); quadVtx(p3.x, p3.y, c3)
    quadVtx(p2.x, p2.y, c2); quadVtx(p1.x, p1.y, c1)
  else:
    quadVtx(p0.x, p0.y, c0); quadVtx(p1.x, p1.y, c1)
    quadVtx(p2.x, p2.y, c2); quadVtx(p3.x, p3.y, c3)

proc drawGradientQuad*(p0, p1, p2, p3: Vector2, c0, c1, c2, c3: Color) =
  ## A convex quad, corners in order around it (either winding), its colour
  ## blended between the corners' colours.
  shapesQuads:
    emitQuad(p0, p1, p2, p3, c0, c1, c2, c3)

proc drawGradientTriangle*(p0, p1, p2: Vector2, c0, c1, c2: Color) =
  ## A triangle in either winding, its colour blended between its corners'.
  shapesQuads:
    emitQuad(p0, p1, p2, p2, c0, c1, c2, c2)

proc drawTaperedLine*(a, b: Vector2, widthA, widthB: float32, colorA, colorB: Color) =
  ## A stroke that changes width and colour along its length: comet tails,
  ## light rays, star spikes. Flat ends, like drawStroke.
  let dx = b.x - a.x
  let dy = b.y - a.y
  let len = sqrt(dx * dx + dy * dy)
  if len <= 0.0'f32: return
  let nx = -dy / len
  let ny = dx / len
  let ha = widthA * 0.5'f32
  let hb = widthB * 0.5'f32
  shapesQuads:
    emitQuad(Vector2(x: a.x - nx * ha, y: a.y - ny * ha), Vector2(x: a.x + nx * ha, y: a.y + ny * ha),
             Vector2(x: b.x + nx * hb, y: b.y + ny * hb), Vector2(x: b.x - nx * hb, y: b.y - ny * hb),
             colorA, colorA, colorB, colorB)

proc drawGlowLine*(a, b: Vector2, width: float32, color: Color) =
  ## A soft neon stroke: `color` along the segment, fading to nothing
  ## `width / 2` either side of it.
  let dx = b.x - a.x
  let dy = b.y - a.y
  let len = sqrt(dx * dx + dy * dy)
  if len <= 0.0'f32 or width <= 0.0'f32: return
  let nx = -dy / len * width * 0.5'f32
  let ny = dx / len * width * 0.5'f32
  let clear = clearOf(color)
  shapesQuads:
    emitQuad(Vector2(x: a.x - nx, y: a.y - ny), a, b, Vector2(x: b.x - nx, y: b.y - ny),
             clear, color, color, clear)
    emitQuad(a, Vector2(x: a.x + nx, y: a.y + ny), Vector2(x: b.x + nx, y: b.y + ny), b,
             color, clear, clear, color)

proc drawRadialGradient*(center: Vector2, radiusX, radiusY: float32,
                         inner, outer: Color, ease = reSmooth, rings = 0) =
  ## A filled ellipse blending from `inner` at its centre to `outer` at its
  ## rim along `ease`. `rings` (0 = the ease's default) sets how many bands
  ## approximate the curve; the colour is continuous across every band.
  if radiusX <= 0.0'f32 or radiusY <= 0.0'f32:
    return
  let scale = drawScale()
  let segs = segmentsAt(max(radiusX, radiusY), scale)
  # A small glow needs few bands to look smooth; a screen-sized one needs nine.
  let px = max(radiusX, radiusY) * scale
  let bands = if rings > 0: rings
              else: (case ease
                     of reLinear: 1
                     of reSmooth: (if px < 24.0'f32: 3 elif px < 80.0'f32: 4 else: 6)
                     of reGlow: (if px < 16.0'f32: 3 elif px < 48.0'f32: 5
                                 elif px < 140.0'f32: 7 else: 9))
  var cs, sn: array[65, float32]
  for i in 0 .. segs:
    let a = i.float32 / segs.float32 * (PI.float32 * 2.0'f32)
    cs[i] = cos(a)
    sn[i] = sin(a)
  shapesQuads:
    var t0 = 0.0'f32
    var c0 = inner
    for k in 1 .. bands:
      let t1 = k.float32 / bands.float32
      let c1 = lerpRgba(inner, outer, easeAt(ease, t1))
      for i in 0 ..< segs:
        # drawRing's corner order (outer, inner, inner next, outer next): front-facing.
        quadVtx(center.x + cs[i] * radiusX * t1, center.y + sn[i] * radiusY * t1, c1)
        quadVtx(center.x + cs[i] * radiusX * t0, center.y + sn[i] * radiusY * t0, c0)
        quadVtx(center.x + cs[i + 1] * radiusX * t0, center.y + sn[i + 1] * radiusY * t0, c0)
        quadVtx(center.x + cs[i + 1] * radiusX * t1, center.y + sn[i + 1] * radiusY * t1, c1)
      t0 = t1
      c0 = c1

proc drawGlow*(center: Vector2, radius: float32, color: Color) =
  ## Soft light: `color` (its alpha is the peak) at the centre, fading
  ## smoothly to nothing at `radius`.
  drawRadialGradient(center, radius, radius, color, clearOf(color), reGlow)

proc drawGlow*(center: Vector2, radiusX, radiusY: float32, color: Color) =
  ## An elliptical drawGlow.
  drawRadialGradient(center, radiusX, radiusY, color, clearOf(color), reGlow)

proc drawGradientRing*(center: Vector2, innerRX, innerRY, outerRX, outerRY: float32,
                       innerColor, outerColor: Color) =
  ## An elliptical band whose colour blends from its inner edge to its outer
  ## edge: a rim of light, a halo that starts away from its source.
  if outerRX <= 0.0'f32 or outerRY <= 0.0'f32:
    return
  let segs = segmentsAt(max(outerRX, outerRY), drawScale())
  shapesQuads:
    for i in 0 ..< segs:
      let a0 = i.float32 / segs.float32 * (PI.float32 * 2.0'f32)
      let a1 = (i + 1).float32 / segs.float32 * (PI.float32 * 2.0'f32)
      let (c0, s0) = (cos(a0), sin(a0))
      let (c1, s1) = (cos(a1), sin(a1))
      quadVtx(center.x + c0 * outerRX, center.y + s0 * outerRY, outerColor)
      quadVtx(center.x + c0 * innerRX, center.y + s0 * innerRY, innerColor)
      quadVtx(center.x + c1 * innerRX, center.y + s1 * innerRY, innerColor)
      quadVtx(center.x + c1 * outerRX, center.y + s1 * outerRY, outerColor)

proc drawGradientRing*(center: Vector2, innerRadius, outerRadius: float32,
                       innerColor, outerColor: Color) =
  drawGradientRing(center, innerRadius, innerRadius, outerRadius, outerRadius,
                   innerColor, outerColor)

proc drawSoftRing*(center: Vector2, radius, halfWidth: float32, color: Color) =
  ## A ring of light: `color` on `radius`, fading to nothing `halfWidth`
  ## either side of it.
  drawGradientRing(center, max(0.0'f32, radius - halfWidth), radius, clearOf(color), color)
  drawGradientRing(center, radius, radius + halfWidth, color, clearOf(color))

proc drawFadeStroke*(a, b: Vector2, width: float32, color: Color) =
  ## A line that fades in from `a`, is brightest halfway and fades out at `b`.
  let m = Vector2(x: (a.x + b.x) * 0.5'f32, y: (a.y + b.y) * 0.5'f32)
  drawTaperedLine(a, m, width, width, clearOf(color), color)
  drawTaperedLine(m, b, width, width, color, clearOf(color))

proc drawBandArc*(center: Vector2, innerRadius, outerRadius, startAngle, endAngle: float32,
                  edgeColor, midColor: Color) =
  ## A ring band from `startAngle` to `endAngle` (radians), `edgeColor` along
  ## its two edges and `midColor` through its middle: a zone of light whose
  ## crisp edges show exactly where it starts and ends.
  let segs = max(6, int(abs(endAngle - startAngle) / (PI.float32 * 2.0'f32) * 80.0'f32))
  let rMid = (innerRadius + outerRadius) * 0.5'f32
  template at(r, a: float32): Vector2 = Vector2(x: center.x + cos(a) * r, y: center.y + sin(a) * r)
  shapesQuads:
    for i in 0 ..< segs:
      let t0 = startAngle + (endAngle - startAngle) * i.float32 / segs.float32
      let t1 = startAngle + (endAngle - startAngle) * (i + 1).float32 / segs.float32
      emitQuad(at(innerRadius, t0), at(rMid, t0), at(rMid, t1), at(innerRadius, t1),
               edgeColor, midColor, midColor, edgeColor)
      emitQuad(at(rMid, t0), at(outerRadius, t0), at(outerRadius, t1), at(rMid, t1),
               midColor, edgeColor, edgeColor, midColor)

proc drawDashedRing*(center: Vector2, radius, halfWidth: float32, dashes: int,
                     fill, phase: float32, color: Color) =
  ## A ring cut into `dashes` arcs, each covering `fill` (0..1) of its slot,
  ## turned by `phase` radians.
  let slot = 360.0'f32 / max(1, dashes).float32
  let turn = phase * 180.0'f32 / PI.float32
  for k in 0 ..< dashes:
    let start = k.float32 * slot + turn
    drawRing(center, radius - halfWidth, radius + halfWidth, start, start + slot * fill, 4, color)

# ---------------------------------------------------------------------------
# Lines
# ---------------------------------------------------------------------------

proc strokeQuad(x1, y1, x2, y2, halfWidth: float32, color: Color) =
  ## One quad along the segment, `halfWidth` either side, no caps (the shape
  ## drawLineEx builds). It samples the shapes texture so it lands in the same
  ## batch as the fills and the text instead of forcing a mode or texture
  ## switch. The vertex order is drawRectanglePro's, which keeps the quad
  ## front-facing in any direction under the backface culling rlgl leaves on.
  let dx = x2 - x1
  let dy = y2 - y1
  let len = sqrt(dx * dx + dy * dy)
  if len <= 0.0'f32 or halfWidth <= 0.0'f32:
    return
  let nx = -dy / len * halfWidth
  let ny = dx / len * halfWidth
  let tex = shapesTextureView()
  let rec = getShapesTextureRectangle()
  let u = (rec.x + rec.width * 0.5'f32) / tex.width.float32
  let v = (rec.y + rec.height * 0.5'f32) / tex.height.float32
  setTexture(tex.id)
  rlBegin(Quads)
  color4ub(color.r, color.g, color.b, color.a)
  texCoord2f(u, v)
  vertex2f(x1 - nx, y1 - ny)
  texCoord2f(u, v)
  vertex2f(x1 + nx, y1 + ny)
  texCoord2f(u, v)
  vertex2f(x2 + nx, y2 + ny)
  texCoord2f(u, v)
  vertex2f(x2 - nx, y2 - ny)
  rlEnd()
  setTexture(0)

proc hairStroke(x1, y1, x2, y2: float32, color: Color) =
  ## A 1 px stroke through pixel centres.
  let half = hairlineAt(drawScale()) * 0.5'f32
  strokeQuad(x1 + half, y1 + half, x2 + half, y2 + half, half, color)

proc drawStroke*(startPos, endPos: Vector2, color: Color) =
  ## drawLine: a 1 px stroke.
  hairStroke(startPos.x, startPos.y, endPos.x, endPos.y, color)

proc drawStroke*(startPosX, startPosY, endPosX, endPosY: int32, color: Color) =
  hairStroke(startPosX.float32, startPosY.float32, endPosX.float32, endPosY.float32, color)

proc drawStroke*(startPos, endPos: Vector2, thick: float32, color: Color) =
  ## drawLine with a thickness: the quad drawLineEx builds, centred on the
  ## segment, but in the quads batch (drawLineEx emits triangles, which forces
  ## a mode switch).
  strokeQuad(startPos.x, startPos.y, endPos.x, endPos.y, thick * 0.5'f32, color)

# ---------------------------------------------------------------------------
# Outlines
# ---------------------------------------------------------------------------

proc drawCircleOutline*(center: Vector2, radius: float32, color: Color) =
  ## drawCircleLines: a 1 px ring just inside `radius`.
  let scale = drawScale()
  drawRing(center, radius - hairlineAt(scale), radius, 0.0'f32, 360.0'f32,
           segmentsAt(radius, scale), color)

proc drawCircleOutline*(centerX, centerY: int32, radius: float32, color: Color) =
  drawCircleOutline(Vector2(x: centerX.float32, y: centerY.float32), radius, color)

proc drawCircleOutline*(center: Vector2, radius, thick: float32, color: Color) =
  ## drawCircleLines with a thickness, raylib 6's rule included: a positive
  ## `thick` strokes inside the radius, a negative one outside.
  drawRing(center, radius - thick, radius, 0.0'f32, 360.0'f32,
           segmentsAt(max(radius, radius - thick), drawScale()), color)

proc drawRectOutline*(posX, posY, width, height: int32, color: Color) =
  ## drawRectangleLines: a 1 px border just inside the rectangle, the pixels
  ## the GL-line version lands on.
  drawRectangleLines(Rectangle(x: posX.float32, y: posY.float32,
                               width: width.float32, height: height.float32),
                     hairlineAt(drawScale()), color)

proc drawRectOutline*(rec: Rectangle, thick: float32, color: Color) =
  ## drawRectangleLines with a thickness (already quads in raylib).
  drawRectangleLines(rec, thick, color)

proc frontFacing(v1, v2, v3: var Vector2): float32 =
  ## raylib's quad outlines keep the triangle's winding, and rlgl culls the
  ## back faces, so a clockwise triangle would vanish (a GL line never cared).
  ## Swaps it into raylib's order; returns twice the signed area it had.
  result = (v2.x - v1.x) * (v3.y - v1.y) - (v2.y - v1.y) * (v3.x - v1.x)
  if result > 0.0'f32:
    swap(v2, v3)

proc drawTriangleOutline*(v1, v2, v3: Vector2, color: Color) =
  ## drawTriangleLines: a 1 px stroke just inside the edges, in either winding.
  var (a, b, c) = (v1, v2, v3)
  if abs(frontFacing(a, b, c)) < 1.0e-6'f32:
    # Collinear: no inside to stroke, so trace the edges like the GL line did.
    drawStroke(a, b, color)
    drawStroke(b, c, color)
    drawStroke(c, a, color)
    return
  drawTriangleLines(a, b, c, hairlineAt(drawScale()), color)

proc drawTriangleOutline*(v1, v2, v3: Vector2, thick: float32, color: Color) =
  ## drawTriangleLines with a thickness, in either winding.
  var (a, b, c) = (v1, v2, v3)
  discard frontFacing(a, b, c)
  drawTriangleLines(a, b, c, thick, color)

proc drawPolyOutline*(center: Vector2, sides: int32, radius, rotation: float32, color: Color) =
  ## drawPolyLines: a 1 px stroke just inside the edges.
  drawPolyLines(center, sides, radius, rotation, hairlineAt(drawScale()), color)

proc drawPolyOutline*(center: Vector2, sides: int32, radius, rotation, thick: float32, color: Color) =
  ## drawPolyLines with a thickness (already quads in raylib).
  drawPolyLines(center, sides, radius, rotation, thick, color)

proc drawEllipseOutline*(center: Vector2, radiusH, radiusV: float32, color: Color) =
  ## drawEllipseLines: a 1 px stroke just inside the ellipse.
  drawEllipseLines(center, radiusH, radiusV, hairlineAt(drawScale()), color)

proc drawEllipseOutline*(centerX, centerY: int32, radiusH, radiusV: float32, color: Color) =
  drawEllipseOutline(Vector2(x: centerX.float32, y: centerY.float32), radiusH, radiusV, color)

proc drawEllipseOutline*(center: Vector2, radiusH, radiusV, thick: float32, color: Color) =
  ## drawEllipseLines with a thickness (already quads in raylib).
  drawEllipseLines(center, radiusH, radiusV, thick, color)
