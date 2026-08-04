import math, random, raylib
import types, particle_types, utils

const LIGHTNING_BOLT_DURATION* = 0.18'f32  # seconds the arc stays visible
const LIGHTNING_SEGMENTS*      = 8

const DEFAULT_BOLT_COLOR* = Color(r: 140, g: 200, b: 255, a: 255)  # pale blue chain lightning

proc spawnLightningBoltInto*(bolts: var seq[LightningBolt], fromPos, toPos: Vector2f,
                             color: Color = DEFAULT_BOLT_COLOR) =
  ## Spawn a short-lived jagged lightning arc between two world positions.
  ## `color` tints the glow only; the core stays near-white so every arc still
  ## reads as electricity regardless of which power-up spawned it.
  let dx = toPos.x - fromPos.x
  let dy = toPos.y - fromPos.y
  let len = sqrt(dx * dx + dy * dy)
  if len < 1.0: return

  # Perpendicular unit vector for jag offsets
  let px = -dy / len
  let py =  dx / len

  # Jag amplitude: ~15% of total length, decreasing toward endpoints
  let ampBase = len * 0.15'f32

  var segs: seq[Vector2f] = @[fromPos]
  for i in 1..<LIGHTNING_SEGMENTS:
    let t = float32(i) / float32(LIGHTNING_SEGMENTS)
    # Linear interpolation base point
    let bx = fromPos.x + dx * t
    let by = fromPos.y + dy * t
    # Random jag perpendicular: envelope tapers at both ends
    let env   = 1.0'f32 - abs(t * 2.0'f32 - 1.0'f32)
    let jag   = (rand(1.0) * 2.0 - 1.0).float32 * ampBase * env
    segs.add(newVector2f(bx + px * jag, by + py * jag))
  segs.add(toPos)

  bolts.add(LightningBolt(
    startPos:    fromPos,
    endPos:      toPos,
    lifetime:    LIGHTNING_BOLT_DURATION,
    maxLifetime: LIGHTNING_BOLT_DURATION,
    segments:    segs,
    color:       color
  ))

const SHOCKWAVE_RING_DURATION* = 0.45'f32  # seconds the boundary ring stays visible

proc spawnShockwaveRingInto*(rings: var seq[ShockwaveRing], pos: Vector2f,
                             maxRadius: float32, color: Color) =
  ## Spawn an expanding ring that marks the exact edge of an AoE blast.
  rings.add(ShockwaveRing(
    pos:         pos,
    maxRadius:   maxRadius,
    lifetime:    SHOCKWAVE_RING_DURATION,
    maxLifetime: SHOCKWAVE_RING_DURATION,
    color:       color
  ))

proc updateShockwaveRings*(rings: var seq[ShockwaveRing], dt: float32) =
  var i = 0
  while i < rings.len:
    rings[i].lifetime -= dt
    if rings[i].lifetime <= 0:
      rings.delete(i)
    else:
      inc i

proc drawShockwaveRings*(rings: seq[ShockwaveRing]) =
  for ring in rings:
    let frac     = ring.lifetime / ring.maxLifetime   # 1.0 -> 0.0 over life
    let progress = 1.0'f32 - frac                       # 0.0 -> 1.0
    # Snap outward over the first 30% of life (ease-out), then HOLD at the true
    # radius for the rest while fading. A momentary flash at the edge isn't
    # readable; holding the boundary is what lets the player gauge the size.
    let expandT = clamp(progress / 0.30'f32, 0.0'f32, 1.0'f32)
    let eased   = 1.0'f32 - pow(1.0'f32 - expandT, 2.0'f32)
    let r       = ring.maxRadius * eased
    let cx = ring.pos.x.int32
    let cy = ring.pos.y.int32

    # Interior wash: a faint filled disc conveys the *area*, not just the edge.
    let fillA = uint8(clamp(frac * 55.0, 0.0, 55.0))
    drawCircle(Vector2(x: ring.pos.x, y: ring.pos.y), r,
               withAlpha(ring.color, fillA))

    # Bold boundary: three concentric outlines give a thick, unmistakable edge.
    let edgeA = uint8(clamp(frac * 255.0, 0.0, 255.0))
    let edge  = withAlpha(ring.color, edgeA)
    drawCircleLines(cx, cy, r - 1.0'f32, edge)
    drawCircleLines(cx, cy, r,          edge)
    drawCircleLines(cx, cy, r + 1.0'f32, edge)

    # Bright inner highlight just inside the edge for extra pop/contrast.
    let hiA = uint8(clamp(frac * 200.0, 0.0, 200.0))
    drawCircleLines(cx, cy, r - 3.0'f32, Color(r: 255, g: 255, b: 230, a: hiA))

proc updateLightningBolts*(bolts: var seq[LightningBolt], dt: float32) =
  var i = 0
  while i < bolts.len:
    bolts[i].lifetime -= dt
    if bolts[i].lifetime <= 0:
      bolts.delete(i)
    else:
      inc i

proc drawLightningBolts*(bolts: seq[LightningBolt]) =
  for bolt in bolts:
    let alpha = uint8(clamp(bolt.lifetime / bolt.maxLifetime * 255.0, 0.0, 255.0))
    # Bright core (white-yellow)
    let coreColor  = Color(r: 255, g: 255, b: 200, a: alpha)
    # Wider glow, tinted per bolt (pale blue by default)
    let glowColor  = Color(r: bolt.color.r, g: bolt.color.g, b: bolt.color.b,
                           a: uint8(alpha.int * 60 div 255))

    for i in 0..<bolt.segments.len - 1:
      let a = bolt.segments[i]
      let b = bolt.segments[i + 1]
      let ax = a.x.int32;  let ay = a.y.int32
      let bx = b.x.int32;  let by = b.y.int32
      # Glow pass (drawn first, wider conceptually: draw offset copies)
      drawLine(ax - 1, ay,     bx - 1, by,     glowColor)
      drawLine(ax + 1, ay,     bx + 1, by,     glowColor)
      drawLine(ax,     ay - 1, bx,     by - 1, glowColor)
      drawLine(ax,     ay + 1, bx,     by + 1, glowColor)
      # Core pass
      drawLine(ax, ay, bx, by, coreColor)

const
  PATH_SHOCKWAVE_DURATION* = 0.60'f32  # total seconds the corridor stays visible
  PATH_SHOCKWAVE_SWEEP*    = 0.45'f32  # fraction of life the crest takes to travel it

proc spawnPathShockwaveInto*(waves: var seq[PathShockwave], points: seq[Vector2f],
                             width: float32, color: Color) =
  ## Spawn a shockwave that sweeps along `points`. The caller passes the path in
  ## chronological order (oldest first); the crest travels from the newest end
  ## backwards, matching how Aftershock resolves its damage.
  if points.len < 2: return
  waves.add(PathShockwave(
    points:      points,
    width:       width,
    lifetime:    PATH_SHOCKWAVE_DURATION,
    maxLifetime: PATH_SHOCKWAVE_DURATION,
    color:       color
  ))

proc updatePathShockwaves*(waves: var seq[PathShockwave], dt: float32) =
  var i = 0
  while i < waves.len:
    waves[i].lifetime -= dt
    if waves[i].lifetime <= 0:
      waves.delete(i)
    else:
      inc i

proc drawPathShockwaves*(waves: seq[PathShockwave]) =
  for wave in waves:
    if wave.points.len < 2: continue
    let frac     = wave.lifetime / wave.maxLifetime   # 1.0 -> 0.0 over life
    let progress = 1.0'f32 - frac                     # 0.0 -> 1.0

    # Arc-length parametrise so the crest moves at a constant speed even though
    # the samples are unevenly spaced (the player moves at varying speeds).
    var segLens: seq[float32] = @[]
    var total = 0.0'f32
    for i in 0 ..< wave.points.len - 1:
      let dx = wave.points[i + 1].x - wave.points[i].x
      let dy = wave.points[i + 1].y - wave.points[i].y
      let l  = sqrt(dx * dx + dy * dy)
      segLens.add(l)
      total += l
    if total < 1.0: continue

    # Crest position measured BACKWARD from the newest end of the path.
    let sweepT   = clamp(progress / PATH_SHOCKWAVE_SWEEP, 0.0'f32, 1.0'f32)
    let travelled = total * sweepT

    # 1) Per-VERTEX corridor offsets, averaged from the two adjacent segment
    #    normals. Offsetting per SEGMENT instead leaves both the fill and the
    #    edges disconnected on every curve - the fill shows dark wedges on the
    #    outside of turns and the edges read as a comb rather than a boundary.
    let n = wave.points.len
    var offX = newSeq[float32](n)
    var offY = newSeq[float32](n)
    for i in 0 ..< n:
      var tx = 0.0'f32
      var ty = 0.0'f32
      if i > 0 and segLens[i - 1] > 0.001:
        tx += (wave.points[i].x - wave.points[i - 1].x) / segLens[i - 1]
        ty += (wave.points[i].y - wave.points[i - 1].y) / segLens[i - 1]
      if i < n - 1 and segLens[i] > 0.001:
        tx += (wave.points[i + 1].x - wave.points[i].x) / segLens[i]
        ty += (wave.points[i + 1].y - wave.points[i].y) / segLens[i]
      let tl = sqrt(tx * tx + ty * ty)
      if tl > 0.001:
        offX[i] = -ty / tl * wave.width
        offY[i] =  tx / tl * wave.width

    # 2) Corridor fill, as a strip between the two offset rails. Consecutive
    #    quads then share an edge exactly, so the interior is gap-free and the
    #    alpha does not accumulate the way overlapping thick lines would.
    #    Each triangle is issued in both windings because raylib back-face
    #    culls, and the corridor reverses handedness whenever the path turns.
    let fillA = uint8(clamp(frac * 34.0, 0.0, 34.0))
    let fill  = withAlpha(wave.color, fillA)
    for i in 0 ..< n - 1:
      let a = Vector2(x: wave.points[i].x + offX[i],         y: wave.points[i].y + offY[i])
      let b = Vector2(x: wave.points[i + 1].x + offX[i + 1], y: wave.points[i + 1].y + offY[i + 1])
      let c = Vector2(x: wave.points[i + 1].x - offX[i + 1], y: wave.points[i + 1].y - offY[i + 1])
      let d = Vector2(x: wave.points[i].x - offX[i],         y: wave.points[i].y - offY[i])
      drawTriangle(a, b, c, fill); drawTriangle(a, c, b, fill)
      drawTriangle(a, c, d, fill); drawTriangle(a, d, c, fill)

    # 3) Boundary rails: the exact edges of the damaged lane.
    let railA = uint8(clamp(frac * 200.0, 0.0, 200.0))
    let rail  = withAlpha(wave.color, railA)
    for i in 0 ..< n - 1:
      drawLine(Vector2(x: wave.points[i].x + offX[i],         y: wave.points[i].y + offY[i]),
               Vector2(x: wave.points[i + 1].x + offX[i + 1], y: wave.points[i + 1].y + offY[i + 1]),
               2.0'f32, rail)
      drawLine(Vector2(x: wave.points[i].x - offX[i],         y: wave.points[i].y - offY[i]),
               Vector2(x: wave.points[i + 1].x - offX[i + 1], y: wave.points[i + 1].y - offY[i + 1]),
               2.0'f32, rail)

    # 4) Centreline: the route the player actually ran, drawn bright so the
    #    corridor has a spine to follow even where the rails cross themselves.
    let coreA = uint8(clamp(frac * 230.0, 0.0, 230.0))
    for i in 0 ..< wave.points.len - 1:
      let a = Vector2(x: wave.points[i].x,     y: wave.points[i].y)
      let b = Vector2(x: wave.points[i + 1].x, y: wave.points[i + 1].y)
      drawLine(a, b, 4.0'f32, withAlpha(wave.color, coreA))
      drawLine(a, b, 1.5'f32, Color(r: 245, g: 250, b: 255, a: coreA))

    # 2) Travelling crest: walk backward accumulating length until we pass the
    #    distance the wave has covered, then interpolate inside that segment.
    if sweepT < 1.0:
      var remaining = travelled
      var idx = wave.points.len - 1
      var crest = wave.points[idx]
      var dirX = 0.0'f32
      var dirY = 0.0'f32
      while idx >= 1:
        let segLen = segLens[idx - 1]
        if remaining <= segLen or idx == 1:
          let t = if segLen > 0.001: clamp(remaining / segLen, 0.0'f32, 1.0'f32) else: 0.0'f32
          crest = newVector2f(
            wave.points[idx].x + (wave.points[idx - 1].x - wave.points[idx].x) * t,
            wave.points[idx].y + (wave.points[idx - 1].y - wave.points[idx].y) * t
          )
          if segLen > 0.001:
            dirX = (wave.points[idx - 1].x - wave.points[idx].x) / segLen
            dirY = (wave.points[idx - 1].y - wave.points[idx].y) / segLen
          break
        remaining -= segLen
        dec idx

      # Perpendicular bar sized to the corridor: a hard front edge sells the
      # "wave rolling through" read far better than a glow blob.
      let px = -dirY
      let py = dirX
      let crestA = uint8(clamp(frac * 255.0, 0.0, 255.0))
      let hot = Color(r: 255, g: 255, b: 240, a: crestA)
      let barA = Vector2(x: crest.x + px * wave.width, y: crest.y + py * wave.width)
      let barB = Vector2(x: crest.x - px * wave.width, y: crest.y - py * wave.width)
      drawLine(barA, barB, 5.0'f32, withAlpha(wave.color, crestA))
      drawLine(barA, barB, 2.0'f32, hot)
      drawCircle(Vector2(x: crest.x, y: crest.y), wave.width * 0.45'f32,
                 withAlpha(wave.color, uint8(crestA.int * 3 div 4)))
      drawCircle(Vector2(x: crest.x, y: crest.y), wave.width * 0.18'f32, hot)
