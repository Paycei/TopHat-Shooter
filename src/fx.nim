import types, math, random, raylib
import particle_types

const LIGHTNING_BOLT_DURATION* = 0.18'f32  # seconds the arc stays visible
const LIGHTNING_SEGMENTS*      = 8

proc spawnLightningBoltInto*(bolts: var seq[LightningBolt], fromPos, toPos: Vector2f) =
  ## Spawn a short-lived jagged lightning arc between two world positions.
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
    segments:    segs
  ))

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
    # Wider glow (pale blue)
    let glowColor  = Color(r: 140, g: 200, b: 255, a: uint8(alpha.int * 60 div 255))

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
