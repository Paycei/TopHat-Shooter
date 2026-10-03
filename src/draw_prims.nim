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
