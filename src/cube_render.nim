## The desktop cube: a small software-3D solid drawn through the 2D batch.
##
## One renderer for every place a cube skin shows: the desktop wallpaper's
## cube, the shop's cube cards, and the orbital-cube secret that circles the
## player (shapes.drawMiniCube). Points turn X, then Y, then Z, and project
## through a pinhole 4.2 units in front of the cube (the camera sits on +z).
##
## Shading. Each face is a grid of quads whose corners are lit one by one
## with a slightly bent normal, as if the faces were faintly pillowed: that is
## what makes light roll across a face instead of filling it flat.
##   * Diffuse light is fixed in MODEL space, so each side keeps its own
##     brightness as the cube tumbles: the shading is painted on.
##   * Gloss and the glass rim (fresnel) are fixed in VIEW space, so a
##     highlight slides across the faces as they turn toward it.
## Glass skins draw their far faces and hidden edges first, then whatever sits
## inside the glass, then the near faces over it, so the cube reads as one
## block of glass instead of a wireframe. Opaque skins only draw what faces
## the camera; a convex solid's front faces never overlap.
##
## Face-local decorations (hearts, pips, the jack's carving, HUD panels, ...)
## are laid out in each face's (right, up) basis and projected exactly, so
## they foreshorten and stay painted on. The basis is canonical, not read off
## the corner winding: the four side faces take up = -Y (screen up), the
## top and bottom faces +Z, and right = up x normal.

import raylib, math
import draw_prims, cube_skins, utils

type
  CubePoint* = object
    x*, y*, z*: float32

func cp(x, y, z: float32): CubePoint {.inline.} = CubePoint(x: x, y: y, z: z)
func `+`(a, b: CubePoint): CubePoint {.inline.} = cp(a.x + b.x, a.y + b.y, a.z + b.z)
func `-`(a, b: CubePoint): CubePoint {.inline.} = cp(a.x - b.x, a.y - b.y, a.z - b.z)
func `*`(a: CubePoint, k: float32): CubePoint {.inline.} = cp(a.x * k, a.y * k, a.z * k)
func dot(a, b: CubePoint): float32 {.inline.} = a.x * b.x + a.y * b.y + a.z * b.z
func cross(a, b: CubePoint): CubePoint {.inline.} =
  cp(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
func normalized(a: CubePoint): CubePoint {.inline.} =
  let l = sqrt(dot(a, a))
  if l > 1.0e-6'f32: a * (1.0'f32 / l) else: a

proc rotateCubePoint*(point: CubePoint, angleX, angleY, angleZ: float32): CubePoint =
  ## X, then Y, then Z: the order the desktop's drag-and-spin angles assume.
  let sinX = sin(angleX)
  let cosX = cos(angleX)
  let sinY = sin(angleY)
  let cosY = cos(angleY)
  let sinZ = sin(angleZ)
  let cosZ = cos(angleZ)
  var x = point.x
  var y = point.y * cosX - point.z * sinX
  var z = point.y * sinX + point.z * cosX
  let yRotX = x * cosY + z * sinY
  z = -x * sinY + z * cosY
  x = yRotX
  let zRotX = x * cosZ - y * sinZ
  y = x * sinZ + y * cosZ
  x = zRotX
  cp(x, y, z)

const CameraDistance = 4.2'f32

proc projectCubePoint*(point: CubePoint, centerX, centerY, scale: float32): Vector2 =
  let depth = max(1.35'f32, CameraDistance - point.z)
  let perspective = CameraDistance / depth
  Vector2(x: centerX + point.x * scale * perspective,
          y: centerY + point.y * scale * perspective)

# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------

func fract01(x: float32): float32 {.inline.} = x - floor(x)

func hash01(seed: float32): float32 {.inline.} =
  fract01(sin(seed * 12.9898'f32) * 43758.5453'f32)

func mixC(a, b: Color, t: float32): Color =
  let k = clamp(t, 0.0'f32, 1.0'f32)
  Color(r: clampByteF(a.r.float32 + (b.r.float32 - a.r.float32) * k),
        g: clampByteF(a.g.float32 + (b.g.float32 - a.g.float32) * k),
        b: clampByteF(a.b.float32 + (b.b.float32 - a.b.float32) * k),
        a: clampByteF(a.a.float32 + (b.a.float32 - a.a.float32) * k))

func rgba(r, g, b: int, a = 255): Color {.inline.} =
  Color(r: clampByte(r), g: clampByte(g), b: clampByte(b), a: clampByte(a))

func fade(c: Color, k: float32): Color {.inline.} =
  ## `c` with its alpha scaled by `k`.
  withAlpha(c, c.a.float32 * clamp(k, 0.0'f32, 1.0'f32))

let
  LightModel = normalized(cp(0.442'f32, -0.694'f32, 0.568'f32))
    ## Painted-on diffuse light, in the cube's own space (see the header).
  LightView = normalized(cp(-0.42'f32, -0.62'f32, 0.66'f32))
    ## The gloss light, in view space: up and to the left, in front.
  HalfView = normalized(LightView + cp(0.0'f32, 0.0'f32, 1.0'f32))

# ---------------------------------------------------------------------------
# Materials
# ---------------------------------------------------------------------------

type
  CubeLook = object
    base, lit: Color      ## a face's colour in shadow and in full light
    rim: Color            ## glass rim light at grazing angles (fresnel)
    spec: Color           ## the gloss highlight
    alpha, rimAlpha: float32  ## face opacity seen straight on / edge on (0..1)
    specPower, specAmt, rimAmt: float32
    bend: float32         ## how pillowed the faces light (0 = flat)
    edge, edgeGlow: Color ## the edge core line and its halo
    backEdge: float32     ## opacity of hidden edges seen through the glass
    halo: Color           ## the light the cube throws around itself

func glass(look: CubeLook): bool = look.alpha < 0.9'f32

proc lookFor(skin: CubeSkinType): CubeLook =
  let data = getCubeSkinData(skin)
  result = CubeLook(
    base: rgba(10, 30, 50), lit: data.faceColor, rim: data.edgeColor,
    spec: rgba(255, 255, 255), alpha: 0.4, rimAlpha: 0.85,
    specPower: 18, specAmt: 0.5, rimAmt: 0.6, bend: 0.45,
    edge: data.edgeColor, edgeGlow: withAlpha(data.glowColor, 150'u8),
    backEdge: 0.45, halo: data.glowColor)
  case skin
  of cskDefault:
    result.base = rgba(4, 34, 64); result.lit = rgba(34, 150, 205)
    result.rim = rgba(150, 240, 255); result.alpha = 0.30; result.rimAlpha = 0.80
    result.specAmt = 0.55; result.rimAmt = 0.75
  of cskNeon:
    result.base = rgba(24, 0, 40); result.lit = rgba(110, 0, 170)
    result.rim = rgba(255, 70, 225); result.spec = rgba(255, 210, 255)
    result.alpha = 0.42; result.rimAlpha = 0.88; result.specAmt = 0.35; result.rimAmt = 0.8
    result.edge = rgba(255, 150, 240); result.edgeGlow = rgba(255, 0, 210, 190)
  of cskIce:
    result.base = rgba(30, 96, 170); result.lit = rgba(140, 212, 255)
    result.rim = rgba(225, 248, 255); result.alpha = 0.5; result.rimAlpha = 0.94
    result.specPower = 34; result.specAmt = 0.85; result.rimAmt = 0.55
    result.edge = rgba(235, 250, 255); result.edgeGlow = rgba(140, 215, 255, 150)
    result.backEdge = 0.35
  of cskGold:
    result.base = rgba(84, 52, 4); result.lit = rgba(232, 176, 36)
    result.rim = rgba(255, 228, 140); result.spec = rgba(255, 250, 220)
    result.alpha = 1.0; result.rimAlpha = 1.0
    result.specPower = 12; result.specAmt = 0.95; result.rimAmt = 0.3; result.bend = 0.62
    result.edge = rgba(255, 236, 140); result.edgeGlow = rgba(255, 190, 40, 120)
    result.backEdge = 0.0
  of cskShadow:
    result.base = rgba(8, 8, 14); result.lit = rgba(42, 40, 60)
    result.rim = rgba(120, 100, 215); result.spec = rgba(180, 170, 255)
    result.alpha = 0.95; result.rimAlpha = 1.0
    result.specPower = 40; result.specAmt = 0.3; result.rimAmt = 0.55
    result.edge = rgba(130, 118, 185); result.edgeGlow = rgba(90, 70, 180, 90)
    result.backEdge = 0.0
  of cskPlasma:
    result.base = rgba(8, 8, 60); result.lit = rgba(56, 64, 232)
    result.rim = rgba(170, 130, 255); result.spec = rgba(225, 220, 255)
    result.alpha = 0.34; result.rimAlpha = 0.82; result.rimAmt = 0.75
    result.edge = rgba(200, 165, 255); result.edgeGlow = rgba(110, 100, 255, 170)
  of cskMatrix:
    result.base = rgba(0, 20, 6); result.lit = rgba(0, 96, 24)
    result.rim = rgba(90, 255, 120); result.spec = rgba(200, 255, 200)
    result.alpha = 0.5; result.rimAlpha = 0.88; result.specAmt = 0.35; result.rimAmt = 0.7
    result.edge = rgba(150, 255, 150); result.edgeGlow = rgba(0, 230, 40, 160)
  of cskCompanion:
    result.base = rgba(78, 80, 88); result.lit = rgba(190, 192, 200)
    result.rim = rgba(225, 227, 232); result.alpha = 1.0; result.rimAlpha = 1.0
    result.specPower = 22; result.specAmt = 0.35; result.rimAmt = 0.15
    result.edge = rgba(214, 216, 222); result.edgeGlow = rgba(244, 130, 160, 60)
    result.backEdge = 0.0
  of cskJack:
    result.base = rgba(120, 38, 2); result.lit = rgba(242, 118, 18)
    result.rim = rgba(255, 184, 76); result.spec = rgba(255, 232, 175)
    result.alpha = 0.86; result.rimAlpha = 0.97
    result.specPower = 16; result.specAmt = 0.45; result.rimAmt = 0.45; result.bend = 0.55
    result.edge = rgba(255, 190, 80); result.edgeGlow = rgba(255, 130, 0, 140)
    result.backEdge = 0.22
  of cskCyber:
    result.base = rgba(2, 34, 48); result.lit = rgba(18, 112, 142)
    result.rim = rgba(80, 245, 255); result.alpha = 0.4; result.rimAlpha = 0.84
    result.rimAmt = 0.65
    result.edge = rgba(255, 100, 215); result.edgeGlow = rgba(255, 60, 200, 170)
  of cskDice:
    result.base = rgba(150, 152, 164); result.lit = rgba(247, 248, 251)
    result.rim = rgba(255, 255, 255); result.alpha = 1.0; result.rimAlpha = 1.0
    result.specPower = 26; result.specAmt = 0.4; result.rimAmt = 0.08; result.bend = 0.55
    result.edge = rgba(222, 224, 230); result.edgeGlow = rgba(255, 255, 255, 40)
    result.backEdge = 0.0; result.halo = rgba(255, 255, 255, 120)
  of cskD20:
    result.base = rgba(12, 10, 14); result.lit = rgba(74, 56, 44)
    result.rim = rgba(205, 160, 60); result.spec = rgba(255, 216, 135)
    result.alpha = 1.0; result.rimAlpha = 1.0
    result.specPower = 20; result.specAmt = 0.8; result.rimAmt = 0.4
    result.edge = data.edgeColor; result.edgeGlow = rgba(200, 120, 30, 110)
    result.backEdge = 0.0

proc shadeAt(look: CubeLook, nModel, nView: CubePoint, alphaScale = 1.0'f32): Color =
  ## One lit corner: painted-on diffuse, then the view-space glass rim and gloss.
  let diffuse = clamp(dot(nModel, LightModel) * 0.5'f32 + 0.5'f32, 0.0'f32, 1.0'f32)
  let ndv = clamp(nView.z, 0.0'f32, 1.0'f32)
  let fres = pow(1.0'f32 - ndv, 2.4'f32)
  let spec = pow(max(0.0'f32, dot(nView, HalfView)), look.specPower) * look.specAmt
  template ch(f: untyped): uint8 =
    clampByteF(look.base.f.float32 + (look.lit.f.float32 - look.base.f.float32) * diffuse +
               look.rim.f.float32 * fres * look.rimAmt + look.spec.f.float32 * spec)
  let a = (look.alpha + (look.rimAlpha - look.alpha) * fres + spec * 0.5'f32) * alphaScale
  Color(r: ch(r), g: ch(g), b: ch(b), a: clampByteF(a * 255.0'f32))

# ---------------------------------------------------------------------------
# Geometry
# ---------------------------------------------------------------------------

const
  CubeVerts: array[8, CubePoint] = [
    CubePoint(x: -1, y: -1, z: -1), CubePoint(x: 1, y: -1, z: -1),
    CubePoint(x: 1, y: 1, z: -1), CubePoint(x: -1, y: 1, z: -1),
    CubePoint(x: -1, y: -1, z: 1), CubePoint(x: 1, y: -1, z: 1),
    CubePoint(x: 1, y: 1, z: 1), CubePoint(x: -1, y: 1, z: 1)]
  CubeFaceCorners: array[6, array[4, int]] = [
    [0, 1, 2, 3], [4, 7, 6, 5], [0, 4, 5, 1], [3, 2, 6, 7], [1, 5, 6, 2], [0, 3, 7, 4]]
  CubeEdges: array[12, array[2, int]] = [
    [0, 1], [1, 2], [2, 3], [3, 0], [4, 5], [5, 6], [6, 7], [7, 4],
    [0, 4], [1, 5], [2, 6], [3, 7]]
  CarvedFace = 1      ## the jack's face is carved into one fixed side (+Z)
  TopFace = 2         ## -Y: screen up when unturned; the jack's stem grows here
  NeonLoop = [0, 1, 2, 3, 7, 6, 5, 4]
    ## A closed walk over eight edges that the neon skin's light pulses chase.

func cubeEdgeFaces(): array[12, array[2, int]] =
  for e, edge in CubeEdges:
    var n = 0
    for f, corners in CubeFaceCorners:
      if edge[0] in corners and edge[1] in corners and n < 2:
        result[e][n] = f
        inc n

const CubeEdgeFacesTable = cubeEdgeFaces()

type
  CubeFace = object
    idx: int
    n, up, right: CubePoint      ## model-space frame
    rn, rUp, rRight: CubePoint   ## the same, turned
    facing: bool
    depth: float32

  CubeView = object
    cx, cy, size, k: float32     ## centre, half-width, line scale
    ax, ay, az: float32

proc turn(v: CubeView, p: CubePoint): CubePoint {.inline.} =
  rotateCubePoint(p, v.ax, v.ay, v.az)

proc proj(v: CubeView, p: CubePoint): Vector2 {.inline.} =
  projectCubePoint(p, v.cx, v.cy, v.size)

proc fp(v: CubeView, f: CubeFace, u, w: float32): Vector2 {.inline.} =
  ## The point (u, w) of face `f`'s own plane, on screen: u along its right
  ## axis, w along its up axis, both -1..1 across the face.
  v.proj(f.rn + f.rRight * u + f.rUp * w)

proc faceOf(v: CubeView, idx: int): CubeFace =
  var n = cp(0, 0, 0)
  for c in CubeFaceCorners[idx]:
    n = n + CubeVerts[c]
  n = n * 0.25'f32
  let up = if abs(n.y) < 0.5'f32: cp(0, -1, 0) else: cp(0, 0, 1)
  let right = cross(up, n)
  result = CubeFace(idx: idx, n: n, up: up, right: right,
                    rn: v.turn(n), rUp: v.turn(up), rRight: v.turn(right))
  # Seen from the pinhole, not just "normal points at +z": with perspective a
  # face is visible while the camera is anywhere in front of its plane.
  result.facing = dot(result.rn, cp(0, 0, CameraDistance) - result.rn) > 0.0'f32
  result.depth = result.rn.z

proc faceLine(v: CubeView, f: CubeFace, u0, w0, u1, w1, width: float32, col: Color) =
  drawStroke(v.fp(f, u0, w0), v.fp(f, u1, w1), width, col)

proc faceGlowLine(v: CubeView, f: CubeFace, u0, w0, u1, w1, width: float32, col: Color) =
  drawGlowLine(v.fp(f, u0, w0), v.fp(f, u1, w1), width, col)

proc faceFan(v: CubeView, f: CubeFace, u0, w0, ru, rw: float32, inner, outer: Color,
             segs = 16) =
  ## A filled ellipse painted on the face, `inner` at its centre to `outer` at its rim.
  let c = v.fp(f, u0, w0)
  var prev = v.fp(f, u0 + ru, w0)
  for s in 1 .. segs:
    let a = s.float32 / segs.float32 * (PI.float32 * 2.0'f32)
    let cur = v.fp(f, u0 + cos(a) * ru, w0 + sin(a) * rw)
    drawGradientTriangle(c, prev, cur, inner, outer, outer)
    prev = cur

proc faceRect(v: CubeView, f: CubeFace, u0, w0, u1, w1: float32, c0, c1: Color) =
  ## A face-space rectangle, `c0` along w0 blending to `c1` along w1.
  drawGradientQuad(v.fp(f, u0, w0), v.fp(f, u1, w0), v.fp(f, u1, w1), v.fp(f, u0, w1),
                   c0, c0, c1, c1)

proc faceFill(v: CubeView, f: CubeFace, look: CubeLook, cells: int, interior: bool) =
  ## The face itself: a cells x cells grid, every corner lit on its own.
  ## `interior` lights a far face from inside the glass.
  const MaxCells = 4
  var pts: array[MaxCells + 1, array[MaxCells + 1, Vector2]]
  var cols: array[MaxCells + 1, array[MaxCells + 1, Color]]
  let n = clamp(cells, 1, MaxCells)
  for i in 0 .. n:
    for j in 0 .. n:
      let u = -1.0'f32 + 2.0'f32 * i.float32 / n.float32
      let w = -1.0'f32 + 2.0'f32 * j.float32 / n.float32
      # The turn is linear, so the turned basis gives turned points and normals.
      let offs = f.right * u + f.up * w
      let rOffs = f.rRight * u + f.rUp * w
      pts[i][j] = v.proj(f.rn + rOffs)
      let nb = normalized(f.n + offs * look.bend)
      let rnb = normalized(f.rn + rOffs * look.bend)
      cols[i][j] = if interior: shadeAt(look, nb * -1.0'f32, rnb * -1.0'f32, 0.7'f32)
                   else: shadeAt(look, nb, rnb)
  for i in 0 ..< n:
    for j in 0 ..< n:
      drawGradientQuad(pts[i][j], pts[i + 1][j], pts[i + 1][j + 1], pts[i][j + 1],
                       cols[i][j], cols[i + 1][j], cols[i + 1][j + 1], cols[i][j + 1])

proc drawEdge(v: CubeView, a, b: Vector2, core, glow: Color, coreW, glowW: float32) =
  if glow.a > 0'u8:
    drawGlowLine(a, b, glowW, glow)
  if core.a > 0'u8:
    drawStroke(a, b, coreW, core)

# ---------------------------------------------------------------------------
# Skin details
# ---------------------------------------------------------------------------

proc drawStarGlint(p: Vector2, r: float32, col: Color) =
  ## A four-point sparkle: two tapered crossing rays and a soft core.
  let clear = withAlpha(col, 0'u8)
  let w = max(0.6'f32, r * 0.16'f32)
  drawTaperedLine(Vector2(x: p.x - r, y: p.y), p, 0.0'f32, w, clear, col)
  drawTaperedLine(p, Vector2(x: p.x + r, y: p.y), w, 0.0'f32, col, clear)
  drawTaperedLine(Vector2(x: p.x, y: p.y - r), p, 0.0'f32, w, clear, col)
  drawTaperedLine(p, Vector2(x: p.x, y: p.y + r), w, 0.0'f32, col, clear)
  drawGlow(p, r * 0.55'f32, fade(col, 0.7'f32))

proc drawBevel(v: CubeView, f: CubeFace, inset: float32, col: Color) =
  ## A thin line inset parallel to the face's edges: the glass's polished bevel.
  let p = inset
  v.faceLine(f, -p, -p, p, -p, 0.8'f32 * v.k, col)
  v.faceLine(f, p, -p, p, p, 0.8'f32 * v.k, col)
  v.faceLine(f, p, p, -p, p, 0.8'f32 * v.k, col)
  v.faceLine(f, -p, p, -p, -p, 0.8'f32 * v.k, col)

proc drawJackCarving(v: CubeView, f: CubeFace, time, glowBoost: float32) =
  ## Jack-O'-Node: a glowing face carved into one fixed side. Spinning the
  ## pumpkin on the Kernel Panic background fans the candle: glowBoost (0..1)
  ## brightens the light and warms the carving toward a white-hot grin.
  let gb = clamp(glowBoost, 0.0'f32, 1.0'f32)
  let glowMul = 1.0'f32 + gb * 2.6'f32
  let flick = (0.74'f32 + 0.26'f32 * sin(time * 6.3'f32 + f.idx.float32 * 1.7'f32)) *
              (1.0'f32 + gb * 0.35'f32 * sin(time * 13.0'f32 + f.idx.float32))
  let candle = rgba(255, int(225.0'f32 + gb * 30.0'f32), int(120.0'f32 + gb * 125.0'f32))
  let hot = rgba(255, 250, int(200.0'f32 + gb * 55.0'f32))
  # Candlelight baked onto the rind, deep orange at the rim to candle at the core.
  v.faceFan(f, 0.0'f32, 0.0'f32, 0.95'f32, 0.95'f32,
            rgba(255, 190, 70, int(min(255.0'f32, 70.0'f32 * flick * glowMul))),
            rgba(255, 120, 10, 0), 20)
  v.faceFan(f, 0.0'f32, 0.05'f32, 0.55'f32, 0.5'f32,
            rgba(255, 235, 150, int(min(255.0'f32, 80.0'f32 * flick * glowMul))),
            rgba(255, 160, 40, 0), 16)
  let rind = rgba(92, 28, 0, 235)
  proc carve(a, b, c: (float32, float32)) =
    # The cut's dark wall first, a hair larger, then the candlelit opening:
    # the carving reads as cut into the rind rather than painted on it.
    let cu = (a[0] + b[0] + c[0]) / 3.0'f32
    let cw = (a[1] + b[1] + c[1]) / 3.0'f32
    proc grow(p: (float32, float32)): Vector2 =
      v.fp(f, cu + (p[0] - cu) * 1.22'f32, cw + (p[1] - cw) * 1.22'f32)
    drawGradientTriangle(grow(a), grow(b), grow(c), rind, rind, rind)
    drawGradientTriangle(v.fp(f, a[0], a[1]), v.fp(f, b[0], b[1]), v.fp(f, c[0], c[1]),
                         candle, candle, hot)
  carve((-0.34'f32, 0.32'f32), (-0.12'f32, 0.32'f32), (-0.23'f32, 0.10'f32))
  carve((0.12'f32, 0.32'f32), (0.34'f32, 0.32'f32), (0.23'f32, 0.10'f32))
  carve((-0.08'f32, 0.06'f32), (0.08'f32, 0.06'f32), (0.0'f32, -0.07'f32))
  # Toothy grin: a smiling band whose lower edge zigzags into teeth.
  const MTeeth = 6
  var prevTop, prevBot: Vector2
  for i in 0 .. MTeeth:
    let t = i.float32 / MTeeth.float32
    let u = -0.40'f32 + 0.80'f32 * t
    let smile = (u / 0.40'f32) * (u / 0.40'f32)
    let wTop = -0.16'f32 - 0.14'f32 * (1.0'f32 - smile)
    let wBot = wTop - (if i mod 2 == 0: 0.12'f32 else: 0.05'f32)
    let curTop = v.fp(f, u, wTop)
    let curBot = v.fp(f, u, wBot)
    if i > 0:
      drawGradientQuad(prevTop, curTop, curBot, prevBot, hot, hot, candle, candle)
    prevTop = curTop
    prevBot = curBot

proc drawJackRibs(v: CubeView, f: CubeFace, look: CubeLook) =
  ## A pumpkin's ribs: bowed grooves down the sides, a star of them on top
  ## and bottom where they meet. Each groove has a lit lip beside it.
  let groove = rgba(120, 36, 0, 150)
  let lip = rgba(255, 176, 80, 60)
  let w = 1.3'f32 * v.k
  if abs(f.n.y) < 0.5'f32:
    for r in [-0.55'f32, 0.0'f32, 0.55'f32]:
      var prev = v.fp(f, r, -0.96'f32)
      var prevLip = v.fp(f, r + 0.07'f32, -0.96'f32)
      for s in 1 .. 6:
        let w0 = -0.96'f32 + s.float32 / 6.0'f32 * 1.92'f32
        let bow = r * 0.16'f32 * (1.0'f32 - w0 * w0)
        let cur = v.fp(f, r + bow, w0)
        let curLip = v.fp(f, r + bow + 0.07'f32, w0)
        drawStroke(prev, cur, w, groove)
        drawStroke(prevLip, curLip, w * 0.8'f32, lip)
        prev = cur
        prevLip = curLip
  else:
    for k in 0 ..< 8:
      let a = k.float32 / 8.0'f32 * (PI.float32 * 2.0'f32)
      let reach = if (k and 1) == 0: 0.95'f32 else: 1.25'f32
      v.faceLine(f, cos(a) * 0.18'f32, sin(a) * 0.18'f32,
                 clamp(cos(a) * reach, -0.97'f32, 0.97'f32),
                 clamp(sin(a) * reach, -0.97'f32, 0.97'f32), w, groove)

proc drawJackStem(v: CubeView, f: CubeFace, time: float32) =
  ## A short stem curling out of the top face from a dark collar in the rind.
  v.faceFan(f, 0.0'f32, 0.0'f32, 0.24'f32, 0.24'f32, rgba(70, 30, 4, 230), rgba(150, 60, 6, 0), 12)
  let sway = 0.05'f32 * sin(time * 0.8'f32)
  const Segs = 4
  var prev = v.proj(f.rn)
  for i in 1 .. Segs:
    let t = i.float32 / Segs.float32
    let p = f.n * (1.0'f32 + 0.42'f32 * t) + f.right * (0.2'f32 * t * t) + f.up * (sway * t)
    let cur = v.proj(v.turn(p))
    let w0 = v.size * (0.17'f32 - 0.05'f32 * (t - 1.0'f32 / Segs.float32))
    let w1 = v.size * (0.17'f32 - 0.05'f32 * t)
    let c0 = mixC(rgba(52, 60, 20), rgba(108, 118, 48), t - 0.25'f32)
    let c1 = mixC(rgba(52, 60, 20), rgba(108, 118, 48), t)
    drawDisc(prev, w0 * 0.5'f32, c0)   # round joints: a curled stalk, not a bar
    drawTaperedLine(prev, cur, w0, w1, c0, c1)
    prev = cur
  drawDisc(prev, v.size * 0.06'f32, rgba(126, 134, 62))

proc drawCyberPanel(v: CubeView, f: CubeFace, time: float32) =
  ## Cyberdeck: a holographic HUD panel projected on the face, a baked cyan
  ## glow, an inset neon frame with magenta brackets, scan ticks, a sweeping
  ## scanline and a pulsing centre node.
  let cyan = rgba(80, 245, 255)
  let mag = rgba(255, 60, 200)
  let pulse = 0.6'f32 + 0.4'f32 * sin(time * 3.0'f32 + f.idx.float32 * 2.0'f32)
  v.faceFan(f, 0.0'f32, 0.0'f32, 0.88'f32, 0.88'f32, rgba(60, 245, 255, int(70.0'f32 * pulse)),
            rgba(40, 200, 255, 0), 18)
  const pin = 0.6'f32
  let frame = [v.fp(f, -pin, -pin), v.fp(f, pin, -pin), v.fp(f, pin, pin), v.fp(f, -pin, pin)]
  for k in 0 .. 3:
    drawGlowLine(frame[k], frame[(k + 1) mod 4], 5.0'f32 * v.k, rgba(80, 245, 255, 110))
    drawStroke(frame[k], frame[(k + 1) mod 4], 1.2'f32 * v.k, cyan)
  const bl = 0.22'f32
  for c in [(-1.0'f32, -1.0'f32), (1.0'f32, -1.0'f32), (1.0'f32, 1.0'f32), (-1.0'f32, 1.0'f32)]:
    let cu = c[0] * pin
    let cw = c[1] * pin
    v.faceLine(f, cu, cw, cu - c[0] * bl, cw, 2.2'f32 * v.k, mag)
    v.faceLine(f, cu, cw, cu, cw - c[1] * bl, 2.2'f32 * v.k, mag)
  for r in 0 .. 2:
    let ww = -0.30'f32 + r.float32 * 0.30'f32
    let len = 0.25'f32 + 0.2'f32 * hash01(f.idx.float32 * 7.0'f32 + r.float32)
    v.faceLine(f, -0.45'f32, ww, -0.45'f32 + len, ww, 1.0'f32 * v.k, rgba(80, 245, 255, 90))
  let scan = pin - fract01(time * 0.45'f32 + f.idx.float32 * 0.31'f32) * pin * 2.0'f32
  v.faceGlowLine(f, -pin, scan, pin, scan, 4.0'f32 * v.k, rgba(120, 250, 255, 120))
  let c = v.fp(f, 0.0'f32, 0.0'f32)
  let nodeR = (3.0'f32 + 2.0'f32 * pulse) * (v.size / 60.0'f32)
  drawGlow(c, max(1.5'f32, nodeR * 3.2'f32), rgba(80, 245, 255, 150))
  drawDisc(c, max(0.7'f32, nodeR), mag)

proc diePips(n: CubePoint): int =
  ## The die's value on the face with normal `n`: 1:+Z 6:-Z 2:+X 5:-X 3:+Y 4:-Y
  ## (opposite faces sum to 7; os_desktop's dice-roll quaternions rely on it).
  if n.z > 0.5'f32: 1
  elif n.z < -0.5'f32: 6
  elif n.x > 0.5'f32: 2
  elif n.x < -0.5'f32: 5
  elif n.y > 0.5'f32: 3
  else: 4

proc drawDiePips(v: CubeView, f: CubeFace) =
  ## Concave pips: dark at the bottom of the dimple, lighter at its lip, with
  ## a small catch-light on the far wall.
  const d = 0.30'f32
  var spots: array[6, (float32, float32)]
  var count = 0
  template add(u, w: float32) =
    spots[count] = (u.float32, w.float32)
    inc count
  case diePips(f.n)
  of 1: add(0, 0)
  of 2: add(-d, -d); add(d, d)
  of 3: add(-d, -d); add(0, 0); add(d, d)
  of 4: add(-d, -d); add(d, -d); add(-d, d); add(d, d)
  of 5: add(-d, -d); add(d, -d); add(0, 0); add(-d, d); add(d, d)
  else: add(-d, -d); add(d, -d); add(-d, 0); add(d, 0); add(-d, d); add(d, d)
  const pr = 0.14'f32
  let segs = if v.size < 16.0'f32: 10 else: 16
  for i in 0 ..< count:
    let (u, w) = spots[i]
    v.faceFan(f, u, w, pr, pr, rgba(14, 14, 20), rgba(72, 72, 84), segs)
    v.faceFan(f, u + pr * 0.32'f32, w - pr * 0.32'f32, pr * 0.42'f32, pr * 0.42'f32,
              rgba(150, 150, 165, 120), rgba(150, 150, 165, 0), 8)

proc drawCompanionFace(v: CubeView, f: CubeFace) =
  ## The Weighted Companion Cube: darker corner caps, a light disc ringed by
  ## four pink segments, and the pink heart on it.
  let cap = rgba(104, 106, 114, 255)
  let capLine = rgba(205, 207, 214, 140)
  for su in [-1.0'f32, 1.0'f32]:
    for sw in [-1.0'f32, 1.0'f32]:
      v.faceRect(f, su * 0.64'f32, sw * 0.64'f32, su * 0.985'f32, sw * 0.985'f32, cap, cap)
      v.faceLine(f, su * 0.64'f32, sw * 0.64'f32, su * 0.985'f32, sw * 0.64'f32, 0.8'f32 * v.k, capLine)
      v.faceLine(f, su * 0.64'f32, sw * 0.64'f32, su * 0.64'f32, sw * 0.985'f32, 0.8'f32 * v.k, capLine)
  let pink = rgba(244, 116, 150)
  let segs = if v.size < 16.0'f32: 14 else: 24
  v.faceFan(f, 0.0'f32, 0.0'f32, 0.66'f32, 0.66'f32, rgba(150, 152, 160), rgba(150, 152, 160), segs)
  for q in 0 .. 3:
    let mid = q.float32 * (PI.float32 * 0.5'f32) + PI.float32 * 0.25'f32
    const span = 0.52'f32
    for s in 0 ..< 4:
      let a0 = mid - span + s.float32 / 4.0'f32 * span * 2.0'f32
      let a1 = mid - span + (s + 1).float32 / 4.0'f32 * span * 2.0'f32
      drawGradientQuad(v.fp(f, cos(a0) * 0.58'f32, sin(a0) * 0.58'f32),
                       v.fp(f, cos(a0) * 0.65'f32, sin(a0) * 0.65'f32),
                       v.fp(f, cos(a1) * 0.65'f32, sin(a1) * 0.65'f32),
                       v.fp(f, cos(a1) * 0.58'f32, sin(a1) * 0.58'f32), pink, pink, pink, pink)
  v.faceFan(f, 0.0'f32, 0.0'f32, 0.55'f32, 0.55'f32, rgba(236, 237, 241), rgba(206, 208, 215), segs)
  # Classic parametric heart: lobes toward the face's up axis.
  let c = v.fp(f, 0.0'f32, 0.0'f32)
  var prev: Vector2
  for i in 0 .. 24:
    let t = i.float32 / 24.0'f32 * (PI.float32 * 2.0'f32)
    let hx = 0.34'f32 * (16.0'f32 * pow(sin(t), 3.0'f32)) / 17.0'f32
    let yc = (13.0'f32 * cos(t) - 5.0'f32 * cos(2.0'f32 * t) -
              2.0'f32 * cos(3.0'f32 * t) - cos(4.0'f32 * t)) / 17.0'f32
    let cur = v.fp(f, hx, (yc + 0.15'f32) * 0.34'f32)
    if i > 0:
      drawGradientTriangle(c, prev, cur, rgba(255, 150, 178), pink, pink)
    prev = cur

proc drawGoldPanel(v: CubeView, f: CubeFace, time: float32) =
  ## Gold Standard: an embossed inset panel (lit lip on top and left, shadow
  ## on the bottom and right) around a polished stud.
  const p = 0.62'f32
  let hi = rgba(255, 244, 180, 175)
  let lo = rgba(70, 38, 0, 165)
  let w = 1.3'f32 * v.k
  v.faceLine(f, -p, p, p, p, w, hi)
  v.faceLine(f, -p, -p, -p, p, w, hi)
  v.faceLine(f, -p, -p, p, -p, w, lo)
  v.faceLine(f, p, -p, p, p, w, lo)
  v.faceLine(f, -p - 0.06'f32, p + 0.06'f32, p + 0.06'f32, p + 0.06'f32, w * 0.7'f32, lo)
  v.faceLine(f, -p - 0.06'f32, -p - 0.06'f32, -p - 0.06'f32, p + 0.06'f32, w * 0.7'f32, lo)
  # The stud: a domed coin with a highlight that drifts with the face's turn.
  let segs = if v.size < 16.0'f32: 12 else: 20
  v.faceFan(f, 0.0'f32, 0.0'f32, 0.26'f32, 0.26'f32, rgba(255, 226, 120), rgba(150, 96, 10), segs)
  v.faceFan(f, -0.07'f32, 0.08'f32, 0.1'f32, 0.1'f32, rgba(255, 252, 230, 220),
            rgba(255, 240, 180, 0), 10)

proc drawShadowFace(v: CubeView, f: CubeFace, time: float32) =
  ## Shadow Node: stealth facet lines around a dim violet sensor slit, and a
  ## faint sheen band sweeping the matte surface.
  let line = rgba(110, 92, 200, 80)
  let w = 0.9'f32 * v.k
  v.faceLine(f, 0.0'f32, 0.55'f32, 0.55'f32, 0.0'f32, w, line)
  v.faceLine(f, 0.55'f32, 0.0'f32, 0.0'f32, -0.55'f32, w, line)
  v.faceLine(f, 0.0'f32, -0.55'f32, -0.55'f32, 0.0'f32, w, line)
  v.faceLine(f, -0.55'f32, 0.0'f32, 0.0'f32, 0.55'f32, w, line)
  for c in [(-1.0'f32, -1.0'f32), (1.0'f32, -1.0'f32), (1.0'f32, 1.0'f32), (-1.0'f32, 1.0'f32)]:
    v.faceLine(f, c[0] * 0.92'f32, c[1] * 0.92'f32, c[0] * 0.38'f32, c[1] * 0.38'f32, w,
               rgba(110, 92, 200, 45))
  let s = 1.3'f32 - fract01(time * 0.16'f32 + f.idx.float32 * 0.37'f32) * 2.6'f32
  if abs(s) < 1.0'f32:
    let a0 = max(-1.0'f32, s - 0.22'f32)
    let a1 = min(1.0'f32, s + 0.22'f32)
    let clear = rgba(150, 130, 255, 0)
    let mid = rgba(150, 130, 255, 28)
    v.faceRect(f, -0.98'f32, a0, 0.98'f32, s, clear, mid)
    v.faceRect(f, -0.98'f32, s, 0.98'f32, a1, mid, clear)
  let pulse = 0.55'f32 + 0.45'f32 * sin(time * 1.6'f32 + f.idx.float32 * 1.3'f32)
  v.faceGlowLine(f, -0.24'f32, 0.0'f32, 0.24'f32, 0.0'f32, 6.0'f32 * v.k,
                 rgba(150, 110, 255, int(150.0'f32 * pulse)))
  v.faceLine(f, -0.2'f32, 0.0'f32, 0.2'f32, 0.0'f32, 1.1'f32 * v.k,
             rgba(220, 200, 255, int(230.0'f32 * pulse)))

proc drawMatrixRain(v: CubeView, f: CubeFace, time: float32) =
  ## Data Node: glyph columns streaming down the face, bright heads and
  ## fading trails, each cell a little block of "bits".
  const Cols = 5
  const Trail = 6
  const CellH = 0.2'f32
  for c in 0 ..< Cols:
    let seed = f.idx.float32 * 17.0'f32 + c.float32 * 3.7'f32
    let u = -0.72'f32 + c.float32 * 0.36'f32
    let speed = 0.35'f32 + hash01(seed) * 0.45'f32
    let head = 1.3'f32 - fract01(time * speed + hash01(seed + 2.0'f32)) * 2.9'f32
    for k in 0 ..< Trail:
      let w = head + k.float32 * CellH
      if w < -0.9'f32 or w > 0.9'f32: continue
      let fadeK = pow(1.0'f32 - k.float32 / Trail.float32, 1.4'f32)
      let col = if k == 0: rgba(215, 255, 215, 235)
                else: rgba(40, 255, 90, int(200.0'f32 * fadeK))
      let shape = int(hash01(seed + k.float32 * 5.1'f32 + floor(time * 7.0'f32 + seed)) * 3.0'f32)
      let hw = 0.09'f32
      let hh = 0.07'f32
      case shape
      of 0:
        v.faceRect(f, u - hw, w - hh, u + hw, w + hh, col, col)
      of 1:
        v.faceRect(f, u - hw, w + hh * 0.2'f32, u + hw, w + hh, col, col)
        v.faceRect(f, u - hw, w - hh, u + hw * 0.2'f32, w - hh * 0.3'f32, col, col)
      else:
        v.faceRect(f, u - hw, w - hh, u - hw * 0.2'f32, w + hh, col, col)
        v.faceRect(f, u - hw, w + hh * 0.3'f32, u + hw, w + hh, col, col)
      if k == 0:
        drawGlow(v.fp(f, u, w), max(1.5'f32, 0.22'f32 * v.size * 0.5'f32), rgba(80, 255, 120, 120))

proc drawIceFrost(v: CubeView, f: CubeFace, time: float32) =
  ## Cryo Core: frost cracks spidering in from the edges, a frosted rim, and
  ## glints that catch the light now and then.
  let crack = rgba(245, 253, 255, 175)
  let w = 0.8'f32 * v.k
  for c in 0 ..< 3:
    let seed = f.idx.float32 * 23.0'f32 + c.float32 * 7.3'f32
    let side = int(hash01(seed) * 4.0'f32)
    let along = -0.7'f32 + hash01(seed + 1.0'f32) * 1.4'f32
    var u, ww: float32
    var du, dw: float32
    case side
    of 0: u = along; ww = -0.98'f32; du = 0; dw = 1
    of 1: u = 0.98'f32; ww = along; du = -1; dw = 0
    of 2: u = along; ww = 0.98'f32; du = 0; dw = -1
    else: u = -0.98'f32; ww = along; du = 1; dw = 0
    for s in 0 ..< 4:
      let step = 0.14'f32 + hash01(seed + s.float32 * 2.3'f32) * 0.12'f32
      let jitter = (hash01(seed + s.float32 * 4.1'f32) - 0.5'f32) * 0.22'f32
      let nu = u + du * step + dw * jitter
      let nw = ww + dw * step + du * jitter
      v.faceLine(f, u, ww, nu, nw, w * (1.0'f32 - s.float32 * 0.18'f32), crack)
      if s == 1:
        let bu = nu + dw * 0.12'f32 + du * 0.06'f32
        let bw = nw + du * 0.12'f32 + dw * 0.06'f32
        v.faceLine(f, nu, nw, bu, bw, w * 0.6'f32, withAlpha(crack, 80'u8))
      u = nu
      ww = nw
  for g in 0 ..< 2:
    let seed = f.idx.float32 * 31.0'f32 + g.float32 * 11.0'f32
    let tw = pow(max(0.0'f32, sin(time * (1.1'f32 + hash01(seed) * 0.9'f32) + seed * 3.0'f32)), 10.0'f32)
    if tw < 0.05'f32: continue
    let p = v.fp(f, -0.6'f32 + hash01(seed + 1.0'f32) * 1.2'f32,
                    -0.6'f32 + hash01(seed + 2.0'f32) * 1.2'f32)
    drawStarGlint(p, (2.5'f32 + 4.0'f32 * tw) * v.k, rgba(255, 255, 255, int(230.0'f32 * tw)))

proc drawCoreCube(v: CubeView, time: float32, col: Color) =
  ## System Unit: a small core cube turning inside the glass on its own axes,
  ## lit from within.
  let c = Vector2(x: v.cx, y: v.cy)
  let pulse = 0.6'f32 + 0.4'f32 * sin(time * 1.8'f32)
  drawGlow(c, v.size * 0.95'f32, withAlpha(col, int(90.0'f32 * pulse)))
  var pts: array[8, Vector2]
  for i in 0 ..< 8:
    let inner = rotateCubePoint(CubeVerts[i] * 0.36'f32, time * 0.7'f32, time * 0.9'f32, 0.0'f32)
    pts[i] = v.proj(v.turn(inner))
  for e in CubeEdges:
    drawGlowLine(pts[e[0]], pts[e[1]], 4.0'f32 * v.k, withAlpha(col, 120'u8))
    drawStroke(pts[e[0]], pts[e[1]], 1.0'f32 * v.k, rgba(210, 252, 255, int(170.0'f32 + 60.0'f32 * pulse)))
  drawGlow(c, v.size * 0.32'f32, rgba(200, 250, 255, int(120.0'f32 * pulse)))

proc drawPlasmaCore(v: CubeView, time: float32) =
  ## Plasma Rig: a plasma orb with arcs crackling out to the corners,
  ## re-struck about thirteen times a second.
  let c = Vector2(x: v.cx, y: v.cy)
  let tick = floor(time * 13.0'f32)
  let pulse = 0.7'f32 + 0.3'f32 * sin(time * 5.0'f32)
  drawGlow(c, v.size * 1.25'f32, rgba(110, 90, 255, int(130.0'f32 * pulse)))
  for a in 0 ..< 5:
    let seed = tick * 1.37'f32 + a.float32 * 9.1'f32
    if hash01(seed + 0.5'f32) < 0.25'f32: continue
    let target = CubeVerts[int(hash01(seed) * 8.0'f32) mod 8] * 0.94'f32
    var prev = c
    const Segs = 6
    for s in 1 .. Segs:
      let t = s.float32 / Segs.float32
      var p = target * t
      if s < Segs:
        p = p + cp(hash01(seed + s.float32 * 2.1'f32) - 0.5'f32,
                   hash01(seed + s.float32 * 3.7'f32) - 0.5'f32,
                   hash01(seed + s.float32 * 5.3'f32) - 0.5'f32) * 0.32'f32
      let cur = v.proj(v.turn(p))
      drawGlowLine(prev, cur, 7.0'f32 * v.k, rgba(160, 120, 255, 190))
      drawStroke(prev, cur, 1.3'f32 * v.k, rgba(240, 236, 255, 245))
      prev = cur
    drawGlow(prev, 3.5'f32 * v.k, rgba(210, 190, 255, 200))
  drawGlow(c, v.size * 0.55'f32, rgba(205, 195, 255, int(220.0'f32 * pulse)))
  drawDisc(c, max(0.8'f32, v.size * 0.1'f32), rgba(255, 255, 255, 240))

# ---------------------------------------------------------------------------
# The D20
# ---------------------------------------------------------------------------

const
  D20InvPhi = 0.6180339887'f32 ## 1/phi: scales the classic (0,+-1,+-phi)
    ## icosahedron vertices so every vertex's largest axis component reaches
    ## exactly 1, matching the unit cube's own reach at the same `size`.
  D20Verts: array[12, CubePoint] = [
    CubePoint(x: -D20InvPhi, y: 1.0, z: 0.0), CubePoint(x: D20InvPhi, y: 1.0, z: 0.0),
    CubePoint(x: -D20InvPhi, y: -1.0, z: 0.0), CubePoint(x: D20InvPhi, y: -1.0, z: 0.0),
    CubePoint(x: 0.0, y: -D20InvPhi, z: 1.0), CubePoint(x: 0.0, y: D20InvPhi, z: 1.0),
    CubePoint(x: 0.0, y: -D20InvPhi, z: -1.0), CubePoint(x: 0.0, y: D20InvPhi, z: -1.0),
    CubePoint(x: 1.0, y: 0.0, z: -D20InvPhi), CubePoint(x: 1.0, y: 0.0, z: D20InvPhi),
    CubePoint(x: -1.0, y: 0.0, z: -D20InvPhi), CubePoint(x: -1.0, y: 0.0, z: D20InvPhi)]
  ## Standard indexed icosahedron face list (12 verts / 20 tri faces / 30
  ## edges, Euler check: 12 - 30 + 20 = 2).
  D20Faces: array[20, array[3, int]] = [
    [0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11],
    [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
    [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9],
    [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]]
  ## Face -> die value, indexed like D20Faces, in antipodal pairs summing to
  ## 21 like a real D20. os_desktop's d20TargetQuat/faceUpFromQuat mirror it.
  D20FaceNumbers: array[20, int] = [
    1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 17, 18, 19, 20, 16, 12, 11, 15, 14, 13]
  D20Edges: array[30, array[2, int]] = [
    [0, 11], [5, 11], [0, 5], [1, 5], [0, 1], [1, 7], [0, 7], [7, 10], [0, 10], [10, 11],
    [5, 9], [1, 9], [4, 11], [4, 5], [2, 10], [2, 11], [6, 7], [6, 10], [1, 8], [7, 8],
    [3, 9], [4, 9], [3, 4], [2, 4], [2, 3], [2, 6], [3, 6], [6, 8], [3, 8], [8, 9]]
  ## For each D20Edges entry, the two D20Faces that share it.
  D20EdgeFaces: array[30, array[2, int]] = [
    [0, 4], [0, 6], [0, 1], [1, 5], [1, 2], [2, 9], [2, 3], [3, 8], [3, 4], [4, 7],
    [5, 15], [5, 19], [6, 16], [6, 15], [7, 17], [7, 16], [8, 18], [8, 17], [9, 19], [9, 18],
    [10, 14], [10, 15], [10, 11], [11, 16], [11, 12], [12, 17], [12, 13], [13, 18], [13, 14], [14, 19]]
  SevenSeg: array[10, array[7, bool]] = [
    [true,  true,  true,  true,  true,  true,  false], # 0: a b c d e f
    [false, true,  true,  false, false, false, false], # 1: b c
    [true,  true,  false, true,  true,  false, true ], # 2: a b d e g
    [true,  true,  true,  true,  false, false, true ], # 3: a b c d g
    [false, true,  true,  false, false, true,  true ], # 4: b c f g
    [true,  false, true,  true,  false, true,  true ], # 5: a c d f g
    [true,  false, true,  true,  true,  true,  true ], # 6: a c d e f g
    [true,  true,  true,  false, false, false, false], # 7: a b c
    [true,  true,  true,  true,  true,  true,  true ], # 8: all
    [true,  true,  true,  true,  false, true,  true ]] # 9: a b c d f g

proc drawD20(v: CubeView, time: float32, look: CubeLook) =
  ## Dragon's Fang: a real icosahedron standing in for the cube. Obsidian
  ## facets with a gold sheen, gold inlaid edges, and engraved seven-segment
  ## numerals on every facet that faces the camera.
  var rotated: array[12, CubePoint]
  var projected: array[12, Vector2]
  for i in 0 ..< 12:
    rotated[i] = v.turn(D20Verts[i])
    projected[i] = v.proj(rotated[i])

  var normal: array[20, CubePoint]
  var facing: array[20, bool]
  for i in 0 ..< 20:
    var n = cp(0, 0, 0)
    var c = cp(0, 0, 0)
    for corner in D20Faces[i]:
      n = n + D20Verts[corner]
      c = c + rotated[corner]
    normal[i] = normalized(n)
    c = c * (1.0'f32 / 3.0'f32)
    facing[i] = dot(v.turn(normal[i]), cp(0, 0, CameraDistance) - c) > 0.0'f32

  let gold = look.edge
  let glow = look.edgeGlow
  # Facets: each corner lit with the facet normal bent toward the vertex, so
  # light rolls across a facet like polished stone.
  for i in 0 ..< 20:
    if not facing[i]: continue
    var cols: array[3, Color]
    for k, corner in D20Faces[i]:
      let nb = normalized(normal[i] * 0.72'f32 + normalized(D20Verts[corner]) * 0.28'f32)
      cols[k] = shadeAt(look, nb, v.turn(nb))
    drawGradientTriangle(projected[D20Faces[i][0]], projected[D20Faces[i][1]],
                         projected[D20Faces[i][2]], cols[0], cols[1], cols[2])
  for i in 0 ..< 30:
    let f0 = facing[D20EdgeFaces[i][0]]
    let f1 = facing[D20EdgeFaces[i][1]]
    if not (f0 or f1): continue
    let silhouette = f0 != f1
    v.drawEdge(projected[D20Edges[i][0]], projected[D20Edges[i][1]],
               withAlpha(gold, (if silhouette: 240'u8 else: 200'u8)), glow,
               (if silhouette: 1.3'f32 else: 0.9'f32) * v.k, 4.5'f32 * v.k)

  if v.size < 11.0'f32: return
  const dHw = 0.115'f32
  const dHh = 0.185'f32
  const dDc = dHw + 0.03'f32
  proc inkCentreU(digit: int, hw: float32): float32 =
    # The horizontal centre of a glyph's ink, not its cell: "1" lives in the
    # right column only, so centring the cell would jam it against the edge.
    let s = SevenSeg[digit]
    let left = s[0] or s[3] or s[4] or s[5] or s[6]
    let right = s[0] or s[1] or s[2] or s[3] or s[6]
    ((if left: -hw else: hw) + (if right: hw else: -hw)) * 0.5'f32

  for i in 0 ..< 20:
    if not facing[i]: continue
    let a = projected[D20Faces[i][0]]
    let b = projected[D20Faces[i][1]]
    let c = projected[D20Faces[i][2]]
    # The on-screen centroid, not the projected 3D one: a perspective divide
    # keeps cross-ratios, not centroids, and the glyph must sit centred on the
    # triangle actually drawn.
    let anchor = Vector2(x: (a.x + b.x + c.x) / 3.0'f32, y: (a.y + b.y + c.y) / 3.0'f32)
    let ndv = clamp(v.turn(normal[i]).z, 0.0'f32, 1.0'f32)
    let ink = 0.45'f32 + 0.55'f32 * ndv
    # Engraved bevel just inside the facet's edges.
    template inset(p: Vector2): Vector2 =
      Vector2(x: p.x * 0.84'f32 + anchor.x * 0.16'f32, y: p.y * 0.84'f32 + anchor.y * 0.16'f32)
    let bevel = withAlpha(gold, clampByteF(110.0'f32 * ink))
    drawStroke(inset(a), inset(b), 0.6'f32 * v.k, bevel)
    drawStroke(inset(b), inset(c), 0.6'f32 * v.k, bevel)
    drawStroke(inset(c), inset(a), 0.6'f32 * v.k, bevel)

    # Numeral basis: the facet's tangent frame, linearised at its centre.
    let n = normal[i]
    let refAxis = if abs(n.y) < 0.5'f32: cp(0, -1, 0) else: cp(0, 0, 1)
    let tanUp = normalized(refAxis - n * dot(n, refAxis))
    let right3d = cross(n, tanUp)
    var fc3d = cp(0, 0, 0)
    for corner in D20Faces[i]:
      fc3d = fc3d + rotated[corner]
    fc3d = fc3d * (1.0'f32 / 3.0'f32)
    let fcScreen = v.proj(fc3d)
    let rightEnd = v.proj(fc3d + v.turn(right3d))
    let upEnd = v.proj(fc3d + v.turn(tanUp))
    let sRx = rightEnd.x - fcScreen.x
    let sRy = rightEnd.y - fcScreen.y
    let sUx = upEnd.x - fcScreen.x
    let sUy = upEnd.y - fcScreen.y
    template np(u, w: float32): Vector2 =
      Vector2(x: anchor.x + sRx * (u) + sUx * (w), y: anchor.y + sRy * (u) + sUy * (w))
    let value = D20FaceNumbers[i]
    let cartR = if value < 10: 0.26'f32 else: 0.36'f32
    var prev = np(cartR, 0.0'f32)
    for s in 1 .. 18:
      let ang = s.float32 / 18.0'f32 * (PI.float32 * 2.0'f32)
      let cur = np(cos(ang) * cartR, sin(ang) * cartR)
      drawGradientTriangle(anchor, prev, cur, rgba(4, 3, 6, 120), rgba(10, 8, 10, 60), rgba(10, 8, 10, 60))
      drawStroke(prev, cur, 0.6'f32 * v.k, withAlpha(gold, clampByteF(120.0'f32 * ink)))
      prev = cur
    let digitGlow = withAlpha(glow, clampByteF(glow.a.float32 * ink))
    let digitInk = withAlpha(rgba(255, 222, 140), clampByteF(255.0'f32 * ink))
    template seg(u0, w0, u1, w1: float32) =
      drawGlowLine(np(u0, w0), np(u1, w1), 3.0'f32 * v.k, digitGlow)
      drawStroke(np(u0, w0), np(u1, w1), 1.0'f32 * v.k, digitInk)
    template drawDigit(digit: int, du, dv, hw, hh: float32) =
      let s = SevenSeg[digit]
      if s[0]: seg(du - hw, dv + hh, du + hw, dv + hh)
      if s[1]: seg(du + hw, dv, du + hw, dv + hh)
      if s[2]: seg(du + hw, dv - hh, du + hw, dv)
      if s[3]: seg(du - hw, dv - hh, du + hw, dv - hh)
      if s[4]: seg(du - hw, dv - hh, du - hw, dv)
      if s[5]: seg(du - hw, dv, du - hw, dv + hh)
      if s[6]: seg(du - hw, dv, du + hw, dv)
    if value < 10:
      drawDigit(value, -inkCentreU(value, dHw), 0.0'f32, dHw, dHh)
    else:
      let tens = value div 10
      let ones = value mod 10
      drawDigit(tens, -dDc - inkCentreU(tens, dHw), 0.0'f32, dHw, dHh)
      drawDigit(ones, dDc - inkCentreU(ones, dHw), 0.0'f32, dHw, dHh)

# ---------------------------------------------------------------------------
# The cube
# ---------------------------------------------------------------------------

proc drawZeroGravityWallpaperCube*(centerX, centerY, size, time,
                                   angleX, angleY, angleZ: float32,
                                   skin: CubeSkinType = cskDefault,
                                   glowBoost: float32 = 0.0'f32,
                                   compact = false) =
  ## The cube in skin `skin`, `size` its half-width. `glowBoost` (0..1) fans
  ## the Jack-O'-Node's candle. `compact` is the pocket-sized orbital cube: a
  ## tighter halo and no orbiting motes.
  let look = lookFor(skin)
  let v = CubeView(cx: centerX, cy: centerY, size: size,
                   k: clamp(size / 32.0'f32, 0.4'f32, 1.8'f32),
                   ax: angleX, ay: angleY, az: angleZ)
  let c = Vector2(x: centerX, y: centerY)
  let pulse = sin(time * 0.72'f32) * 0.5'f32 + 0.5'f32

  # The light the cube throws around itself, and the motes riding in it.
  if compact:
    drawGlow(c, size * 2.3'f32, fade(look.halo, 0.32'f32))
  else:
    drawGlow(c, size * 3.2'f32, fade(look.halo, (0.3'f32 + pulse * 0.1'f32)))
    drawGlow(c, size * 1.55'f32, fade(look.halo, 0.2'f32))
    for i in 0 ..< 5:
      let orbitAngle = time * (0.18'f32 + i.float32 * 0.018'f32) + i.float32 * PI.float32 * 0.42'f32
      let orbitRadius = size * (1.42'f32 + i.float32 * 0.09'f32)
      let mote = Vector2(x: centerX + cos(orbitAngle) * orbitRadius,
                         y: centerY + sin(orbitAngle * 0.78'f32) * orbitRadius * 0.28'f32)
      drawGlow(mote, (3.0'f32 + i.float32 * 0.4'f32) * v.k, fade(look.halo, 0.5'f32))
      drawDisc(mote, (1.0'f32 + i.float32 * 0.1'f32) * v.k,
               mixC(look.halo, rgba(255, 255, 255), 0.6'f32))

  if skin == cskD20:
    # A different solid entirely (12 verts / 20 faces), not a paint job.
    drawD20(v, time, look)
    return

  var faces: array[6, CubeFace]
  for i in 0 ..< 6:
    faces[i] = v.faceOf(i)
  for pass in 0 ..< faces.len:
    for i in 0 ..< faces.len - 1:
      if faces[i].depth > faces[i + 1].depth:
        swap(faces[i], faces[i + 1])
  var facingByIdx: array[6, bool]
  for f in faces:
    facingByIdx[f.idx] = f.facing

  var pts: array[8, Vector2]
  for i in 0 ..< 8:
    pts[i] = v.proj(v.turn(CubeVerts[i]))

  let coreW = 1.5'f32 * v.k
  let glowW = 8.0'f32 * v.k
  let cells = if size < 14.0'f32: 2 else: 3

  # Far side of the glass, seen through the near faces.
  if look.glass:
    for f in faces:
      if f.facing: continue
      v.faceFill(f, look, max(1, cells - 1), interior = true)
      if skin == cskJack and f.idx == CarvedFace:
        # The carving keeps glowing through the rind when it turns away.
        drawJackCarving(v, f, time, glowBoost)
      if skin == cskJack and f.idx == TopFace:
        drawJackStem(v, f, time)
    if look.backEdge > 0.0'f32:
      for e, edge in CubeEdges:
        let fs = CubeEdgeFacesTable[e]
        if facingByIdx[fs[0]] or facingByIdx[fs[1]]: continue
        v.drawEdge(pts[edge[0]], pts[edge[1]], fade(look.edge, look.backEdge),
                   fade(look.edgeGlow, look.backEdge * 0.6'f32), coreW * 0.8'f32, glowW * 0.7'f32)

  # Inside the glass.
  case skin
  of cskDefault: drawCoreCube(v, time, look.halo)
  of cskPlasma: drawPlasmaCore(v, time)
  of cskIce: drawGlow(c, size * 0.9'f32, rgba(200, 240, 255, 90))
  of cskJack:
    let gb = clamp(glowBoost, 0.0'f32, 1.0'f32)
    let flick = 0.8'f32 + 0.2'f32 * sin(time * 7.3'f32) + 0.06'f32 * sin(time * 17.0'f32)
    drawGlow(c, size * 1.0'f32, rgba(255, 170, 50, int(min(255.0'f32, (90.0'f32 + gb * 120.0'f32) * flick))))
  of cskNeon, cskMatrix, cskCyber:
    drawGlow(c, size * 0.8'f32, fade(look.halo, 0.25'f32))
  else: discard

  # Near faces, each with its painted details right after its own fill.
  for f in faces:
    if not f.facing: continue
    v.faceFill(f, look, cells, interior = false)
    case skin
    of cskDefault:
      v.drawBevel(f, 0.84'f32, rgba(170, 240, 255, 60))
    of cskNeon:
      let p = 0.74'f32
      let tube = rgba(255, 80, 230, 120)
      v.faceGlowLine(f, -p, -p, p, -p, 5.0'f32 * v.k, tube)
      v.faceGlowLine(f, p, -p, p, p, 5.0'f32 * v.k, tube)
      v.faceGlowLine(f, p, p, -p, p, 5.0'f32 * v.k, tube)
      v.faceGlowLine(f, -p, p, -p, -p, 5.0'f32 * v.k, tube)
      v.drawBevel(f, p, rgba(255, 170, 245, 120))
    of cskIce: drawIceFrost(v, f, time)
    of cskGold: drawGoldPanel(v, f, time)
    of cskShadow: drawShadowFace(v, f, time)
    of cskPlasma: v.drawBevel(f, 0.84'f32, rgba(190, 170, 255, 70))
    of cskMatrix:
      drawMatrixRain(v, f, time)
      v.drawBevel(f, 0.86'f32, rgba(120, 255, 140, 55))
    of cskCompanion: drawCompanionFace(v, f)
    of cskJack:
      if f.idx == CarvedFace:
        drawJackCarving(v, f, time, glowBoost)
      else:
        drawJackRibs(v, f, look)
      if f.idx == TopFace:
        drawJackStem(v, f, time)
    of cskCyber: drawCyberPanel(v, f, time)
    of cskDice: drawDiePips(v, f)
    of cskD20: discard

  # Near edges: silhouette edges brightest, a soft round joint at each corner.
  var cornerShown: array[8, bool]
  for e, edge in CubeEdges:
    let fs = CubeEdgeFacesTable[e]
    let f0 = facingByIdx[fs[0]]
    let f1 = facingByIdx[fs[1]]
    if not (f0 or f1): continue
    cornerShown[edge[0]] = true
    cornerShown[edge[1]] = true
    let silhouette = f0 != f1
    v.drawEdge(pts[edge[0]], pts[edge[1]],
               (if silhouette: look.edge else: fade(look.edge, 0.82'f32)),
               look.edgeGlow, (if silhouette: coreW * 1.15'f32 else: coreW), glowW)
  for i in 0 ..< 8:
    if cornerShown[i]:
      drawGlow(pts[i], glowW * 0.55'f32, fade(look.edgeGlow, 0.8'f32))
      drawDisc(pts[i], coreW * 0.55'f32, look.edge)

  # Neon Pulse: three sparks chasing round a loop of the edges.
  if skin == cskNeon:
    for p in 0 ..< 3:
      let t = fract01(time * 0.22'f32 + p.float32 / 3.0'f32) * NeonLoop.len.float32
      let seg = int(t) mod NeonLoop.len
      let lf = t - floor(t)
      let a = NeonLoop[seg]
      let b = NeonLoop[(seg + 1) mod NeonLoop.len]
      let pa = pts[a]
      let pb = pts[b]
      let spark = Vector2(x: pa.x + (pb.x - pa.x) * lf, y: pa.y + (pb.y - pa.y) * lf)
      let tail = Vector2(x: pa.x + (pb.x - pa.x) * max(0.0'f32, lf - 0.35'f32),
                         y: pa.y + (pb.y - pa.y) * max(0.0'f32, lf - 0.35'f32))
      drawTaperedLine(tail, spark, 0.0'f32, coreW * 2.2'f32, rgba(255, 120, 240, 0), rgba(255, 230, 255, 230))
      drawGlow(spark, glowW * 1.1'f32, rgba(255, 90, 235, 200))
      drawDisc(spark, coreW * 1.1'f32, rgba(255, 245, 255))

  # Polished metal and ice catch the light on the corner nearest it.
  if skin in {cskGold, cskIce, cskDice}:
    var best = -1
    var bestDot = -2.0'f32
    for i in 0 ..< 8:
      if not cornerShown[i]: continue
      let d = dot(normalized(v.turn(CubeVerts[i])), LightView)
      if d > bestDot:
        bestDot = d
        best = i
    if best >= 0:
      let tw = 0.55'f32 + 0.45'f32 * sin(time * 2.3'f32)
      drawStarGlint(pts[best], (5.0'f32 + 3.0'f32 * tw) * v.k,
                    rgba(255, 252, 235, int(150.0'f32 + 90.0'f32 * tw)))
