## OS-Style Background System

import raylib, math, random
import ../draw_prims
import particle_types, ../types, background_fx, ../utils
from ui_theme import beginKeepAlpha, endKeepAlpha

const
  MAX_DATA_PACKETS = 50
  NUM_CIRCUIT_LINES = 8
  BOSS_ARENA_RING_COUNT = 3
  BOSS_ARENA_RING_HALF_WIDTH = 18.0'f32
  BOSS_ARENA_DAMAGE = 0.35'f32
  BOSS_ARENA_DAMAGE_INTERVAL = 0.85'f32

proc alphaFrom(value: float32): uint8 = clampByteF(value)  # delegate to utils.clampByteF

func v2(x, y: float32): Vector2 {.inline.} = Vector2(x: x, y: y)

func rgba(r, g, b: int, a = 255): Color {.inline.} =
  Color(r: clampByte(r), g: clampByte(g), b: clampByte(b), a: clampByte(a))

func rgbaF(r, g, b: int, a: float32): Color {.inline.} =
  Color(r: clampByte(r), g: clampByte(g), b: clampByte(b), a: clampByteF(a))

func clearOf(c: Color): Color {.inline.} = Color(r: c.r, g: c.g, b: c.b, a: 0)

func towards(c, accent: Color, k: float32): Color =
  ## `c` with its hue pulled `k` of the way to `accent`, its alpha kept.
  template ch(x, y: uint8): uint8 = clampByteF(x.float32 + (y.float32 - x.float32) * k)
  Color(r: ch(c.r, accent.r), g: ch(c.g, accent.g), b: ch(c.b, accent.b), a: c.a)

func deg(radians: float32): float32 {.inline.} = radians * 180.0'f32 / PI

proc edgeWash(w, h, depth: float32, col: Color) =
  ## Light (or shade) washing in `depth` from all four edges.
  let clear = clearOf(col)
  drawGradientQuad(v2(0, 0), v2(0, h), v2(depth, h), v2(depth, 0), col, col, clear, clear)
  drawGradientQuad(v2(w - depth, 0), v2(w - depth, h), v2(w, h), v2(w, 0), clear, clear, col, col)
  drawGradientQuad(v2(0, 0), v2(0, depth), v2(w, depth), v2(w, 0), col, clear, clear, col)
  drawGradientQuad(v2(0, h - depth), v2(0, h), v2(w, h), v2(w, h - depth), clear, col, col, clear)

proc bossArenaModeForWave(currentWave: int): BossArenaRingMode =
  if currentWave <= 0:
    return barmNone

  let bossTier = max(1, currentWave div BossWaveInterval)
  case bossTier mod 3
  of 1: barmBoon
  of 2: barmHazard
  else: barmRotating

proc arenaBaseRadius(screenWidth, screenHeight: int32): float32 =
  min(screenWidth.float32, screenHeight.float32) * 0.42

proc arenaRingRadius(screenWidth, screenHeight: int32, band: int): float32 =
  arenaBaseRadius(screenWidth, screenHeight) * (0.42 + band.float32 * 0.22)

proc angleDistance(a, b: float32): float32 =
  var diff = abs(a - b) mod (PI * 2.0)
  if diff > PI:
    diff = PI * 2.0 - diff
  diff

proc bandAtPosition(pos: Vector2f, playerRadius: float32, screenWidth, screenHeight: int32): int =
  let center = newVector2f(screenWidth.float32 * 0.5, screenHeight.float32 * 0.5)
  let d = distance(pos, center)
  let halfWidth = BOSS_ARENA_RING_HALF_WIDTH + playerRadius * 0.35
  result = -1

  for band in 0..<BOSS_ARENA_RING_COUNT:
    if abs(d - arenaRingRadius(screenWidth, screenHeight, band)) <= halfWidth:
      return band

proc insideHazardCircle(pos: Vector2f, screenWidth, screenHeight: int32, band: int): bool =
  ## Returns true if pos is anywhere inside the full circle of the given hazard band
  let center = newVector2f(screenWidth.float32 * 0.5, screenHeight.float32 * 0.5)
  let d = distance(pos, center)
  let outerR = arenaRingRadius(screenWidth, screenHeight, band) + BOSS_ARENA_RING_HALF_WIDTH
  d <= outerR

proc rotatingBandActive(bg: OSBackgroundState, playerPos: Vector2f,
                        screenWidth, screenHeight: int32, band: int): bool =
  if band < 0:
    return false

  let centerX = screenWidth.float32 * 0.5
  let centerY = screenHeight.float32 * 0.5
  let playerAngle = arctan2(playerPos.y - centerY, playerPos.x - centerX)
  let sweep = bg.bossArenaRotation + band.float32 * 0.72
  angleDistance(playerAngle, sweep) < 0.42 or angleDistance(playerAngle, sweep + PI) < 0.42

proc activeHazardBand(bg: OSBackgroundState): int =
  (floor(bg.bossArenaPhase / 2.65).int mod BOSS_ARENA_RING_COUNT)

proc getBossArenaCombatBonus*(bg: OSBackgroundState): tuple[damageMult: float32, fireRateMult: float32] =
  let activeBonus = bg.bossArenaMode in [barmBoon, barmRotating]
  if activeBonus and bg.bossArenaBonusIntensity > 0.01:
    result.damageMult = 1.0 + 0.08 * bg.bossArenaBonusIntensity
    result.fireRateMult = 1.0 - 0.06 * bg.bossArenaBonusIntensity
  else:
    result.damageMult = 1.0
    result.fireRateMult = 1.0

proc updateBossArenaField*(bg: var OSBackgroundState, dt: float32, playerPos: Vector2f,
                           playerRadius: float32, screenWidth, screenHeight: int32,
                           bossActive: bool, currentWave: int): tuple[damageTriggered: bool, damage: float32] =
  result = (damageTriggered: false, damage: 0.0'f32)

  bg.bossArenaPlayerX = playerPos.x
  bg.bossArenaPlayerY = playerPos.y
  bg.bossArenaDamageCooldown = max(0.0'f32, bg.bossArenaDamageCooldown - dt)

  if not bossActive:
    bg.bossArenaMode = barmNone
    bg.bossArenaPlayerBand = -1
    bg.bossArenaPlayerOnActive = false
    bg.bossArenaBonusIntensity = max(0.0'f32, bg.bossArenaBonusIntensity - dt * 4.0)
    return

  bg.bossArenaMode = bossArenaModeForWave(currentWave)
  bg.bossArenaPhase += dt
  bg.bossArenaRotation += dt * (0.62 + (currentWave mod 7).float32 * 0.035)

  let band = bandAtPosition(playerPos, playerRadius, screenWidth, screenHeight)
  bg.bossArenaPlayerBand = band

  case bg.bossArenaMode
  of barmBoon:
    bg.bossArenaPlayerOnActive = band in [1, 2]
  of barmHazard:
    let hazBand = activeHazardBand(bg)
    bg.bossArenaPlayerOnActive = insideHazardCircle(playerPos, screenWidth, screenHeight, hazBand)
    if bg.bossArenaPlayerOnActive and bg.bossArenaDamageCooldown <= 0:
      bg.bossArenaDamageCooldown = BOSS_ARENA_DAMAGE_INTERVAL
      result = (damageTriggered: true, damage: BOSS_ARENA_DAMAGE)
  of barmRotating:
    bg.bossArenaPlayerOnActive = rotatingBandActive(bg, playerPos, screenWidth, screenHeight, band)
  of barmNone:
    bg.bossArenaPlayerOnActive = false

  let targetBonus =
    if bg.bossArenaMode in [barmBoon, barmRotating] and bg.bossArenaPlayerOnActive: 1.0'f32 else: 0.0'f32
  if bg.bossArenaBonusIntensity < targetBonus:
    bg.bossArenaBonusIntensity = min(targetBonus, bg.bossArenaBonusIntensity + dt * 3.8)
  else:
    bg.bossArenaBonusIntensity = max(targetBonus, bg.bossArenaBonusIntensity - dt * 4.8)

proc drawArenaEdgeVignette(screenWidth, screenHeight: int32, intensity: float32) =
  let vigW = max(96'i32, min(screenWidth, screenHeight) div 6)
  let vigAlpha = alphaFrom(84.0 + intensity * 74.0)
  let edgeColor = Color(r: 0, g: 5, b: 15, a: vigAlpha)
  drawRectangleGradientH(0, 0, vigW, screenHeight,
    edgeColor, Color(r: 0, g: 0, b: 0, a: 0))
  drawRectangleGradientH(screenWidth - vigW, 0, vigW, screenHeight,
    Color(r: 0, g: 0, b: 0, a: 0), edgeColor)
  drawRectangleGradientV(0, 0, screenWidth, vigW,
    edgeColor, Color(r: 0, g: 0, b: 0, a: 0))
  drawRectangleGradientV(0, screenHeight - vigW, screenWidth, vigW,
    Color(r: 0, g: 0, b: 0, a: 0), edgeColor)

proc drawArenaFloor*(screenWidth, screenHeight: int32, time: float32, accent: Color,
                     tinted = false, alert = 0.0'f32) =
  ## The arena's floor, shared by every PvE mode and PvP: the deep backdrop
  ## with its drifting grid, light pooling at the centre and in the quadrants,
  ## a slow hexagon plate, concentric guide rings with nodes sweeping round
  ## them, radial spokes and perspective lanes. Kept dim on purpose: the
  ## gameplay rings, telegraphs and bullets must always read over it.
  ## `tinted` pulls the light toward `accent` (a dungeon floor's theme, a
  ## survival phase); `alert` (0..1) raises the boss-fight hazard markers.
  let w = screenWidth.float32
  let h = screenHeight.float32
  let c = v2(w * 0.5'f32, h * 0.5'f32)
  let arenaRadius = min(w, h) * 0.42'f32
  let pulse = sin(time * 1.35'f32) * 0.5'f32 + 0.5'f32
  let alertPulse = sin(time * 4.8'f32) * 0.5'f32 + 0.5'f32
  proc lit(col: Color): Color = (if tinted: towards(col, accent, 0.55'f32) else: col)

  drawSharedBackdrop(screenWidth, screenHeight, time * 0.82'f32,
                     Color(r: 4, g: 7, b: 16, a: 255), Color(r: 14, g: 16, b: 30, a: 255),
                     Color(r: 30, g: 44, b: 68, a: 26), Color(r: 92, g: 126, b: 175, a: 52),
                     withAlpha(accent, 40'u8), 0.55, 0.55)

  # Light: a pool at the centre, washes in the quadrants and along the top and
  # bottom edges, so the arena is never a flat void.
  drawGlow(c, arenaRadius * 1.45'f32, lit(rgbaF(0, 100, 160, 46.0'f32 + pulse * 16.0'f32)))
  drawGlow(c, arenaRadius * 0.9'f32, lit(rgbaF(10, 70, 130, 30.0'f32 + pulse * 10.0'f32)))
  drawGlow(v2(w * 0.18'f32, h * 0.78'f32), arenaRadius * 0.75'f32, rgbaF(95, 115, 255, 32.0'f32 + pulse * 12.0'f32))
  drawGlow(v2(w * 0.84'f32, h * 0.22'f32), arenaRadius * 0.7'f32, lit(rgbaF(0, 200, 170, 26.0'f32 + pulse * 10.0'f32)))
  drawGlow(v2(w * 0.08'f32, h * 0.38'f32), arenaRadius * 0.5'f32, rgbaF(60, 80, 200, 20.0'f32 + pulse * 8.0'f32))
  drawGlow(v2(w * 0.92'f32, h * 0.62'f32), arenaRadius * 0.55'f32, lit(rgbaF(0, 170, 220, 22.0'f32 + pulse * 8.0'f32)))
  drawGlow(v2(w * 0.5'f32, 0.0'f32), arenaRadius * 0.95'f32, arenaRadius * 0.45'f32,
           lit(rgbaF(20, 80, 160, 28.0'f32 + pulse * 10.0'f32)))
  drawGlow(v2(w * 0.5'f32, h), arenaRadius * 0.95'f32, arenaRadius * 0.45'f32,
           lit(rgbaF(0, 70, 150, 26.0'f32 + pulse * 9.0'f32)))

  # The centre plate: two hexagons turning slowly against each other.
  for k in 0 .. 1:
    let rot = deg(time * (0.08'f32 + k.float32 * 0.05'f32) * (if k == 0: 1.0'f32 else: -1.0'f32))
    drawPolyOutline(c, 6, arenaRadius * (0.2'f32 + k.float32 * 0.045'f32), rot,
                    lit(rgba(60, 170, 220, 24 - k * 8)))

  # Guide rings: soft rings of light, each with a node sweeping round it and
  # an arc trailing the node. Dim: the boss-arena zones must dominate them.
  for i in 0 .. 4:
    let r = arenaRadius * (0.34'f32 + i.float32 * 0.16'f32)
    let ringA = 10.0'f32 + i.float32 * 3.0'f32 + pulse * 6.0'f32
    drawSoftRing(c, r, 5.0'f32, lit(rgbaF(40, 140, 190, ringA * 0.9'f32)))
    drawCircleOutline(c, r, lit(rgbaF(60, 150, 200, ringA)))
    let sweepAngle = time * (0.42'f32 + i.float32 * 0.05'f32) + i.float32 * PI * 0.34'f32
    drawRing(c, r - 1.2'f32, r + 1.2'f32, deg(sweepAngle) - 34.0'f32, deg(sweepAngle), 14,
             lit(rgbaF(120, 230, 255, 36.0'f32 + pulse * 22.0'f32)))
    let node = v2(c.x + cos(sweepAngle) * r, c.y + sin(sweepAngle) * r)
    drawGlow(node, 11.0'f32, lit(rgbaF(120, 240, 255, 48.0'f32 + pulse * 28.0'f32)))
    drawDisc(node, 2.2'f32 + i.float32 * 0.3'f32, rgbaF(190, 250, 255, 150.0'f32 + pulse * 70.0'f32))

  # Radial spokes and perspective lanes, fading in and out along their length.
  for i in 0 ..< 12:
    let angle = i.float32 * PI / 6.0'f32
    let inner = arenaRadius * 0.22'f32
    let outer = arenaRadius * 1.03'f32
    let a = (18.0'f32 + (if i mod 3 == 0: 28.0'f32 else: 0.0'f32) + pulse * 8.0'f32) * 1.1'f32
    drawFadeStroke(v2(c.x + cos(angle) * inner, c.y + sin(angle) * inner),
               v2(c.x + cos(angle) * outer, c.y + sin(angle) * outer), 1.2'f32,
               lit(rgbaF(64, 185, 230, a)))
  let laneA = 28.0'f32 + pulse * 18.0'f32
  for i in 0 ..< 7:
    let t = (i.float32 - 3.0'f32) / 3.0'f32
    drawFadeStroke(v2(c.x + t * arenaRadius * 0.45'f32, c.y - arenaRadius * 0.9'f32),
               v2(c.x + t * arenaRadius * 1.25'f32, c.y + arenaRadius * 1.05'f32), 1.0'f32,
               lit(rgbaF(0, 220, 240, laneA)))
    drawFadeStroke(v2(c.x - arenaRadius * 1.05'f32, c.y + t * arenaRadius * 1.25'f32),
               v2(c.x + arenaRadius * 1.05'f32, c.y + t * arenaRadius * 0.45'f32), 1.0'f32,
               lit(rgbaF(0, 220, 240, laneA * 0.5'f32)))

  # Boss fight: hazard markers circling the arena.
  if alert > 0.0'f32:
    let hazardA = alert * (36.0'f32 + alertPulse * 40.0'f32)
    for i in 0 ..< 6:
      let angle = i.float32 * PI / 3.0'f32 + time * 0.22'f32
      let p = v2(c.x + cos(angle) * arenaRadius * 0.78'f32, c.y + sin(angle) * arenaRadius * 0.78'f32)
      drawGlow(p, 24.0'f32, rgbaF(255, 62, 55, hazardA * 0.7'f32))
      for d in [-1.0'f32, 1.0'f32]:
        drawGlowLine(v2(p.x - 12.0'f32, p.y - 12.0'f32 * d), v2(p.x + 12.0'f32, p.y + 12.0'f32 * d),
                     8.0'f32, rgbaF(255, 62, 55, hazardA * 0.6'f32))
        drawStroke(v2(p.x - 12.0'f32, p.y - 12.0'f32 * d), v2(p.x + 12.0'f32, p.y + 12.0'f32 * d),
                   2.0'f32, rgbaF(255, 90, 70, hazardA * 1.4'f32))

proc drawZoneLabel(text: string, centerX, centerY, radius: float32, fillAlpha: uint8,
                   labelColor: Color, fontSize: int32 = 11) =
  ## A small tag on a dark pill just above the top of a ring zone, so it reads
  ## over the zone's own light.
  let labelWidth = measureText(text, fontSize)
  let lx = (centerX - labelWidth.float32 * 0.5'f32).int32
  let ly = (centerY - radius - BOSS_ARENA_RING_HALF_WIDTH - fontSize.float32 - 7.0'f32).int32
  let pill = Rectangle(x: lx.float32 - 7.0'f32, y: ly.float32 - 4.0'f32,
                       width: labelWidth.float32 + 14.0'f32, height: fontSize.float32 + 8.0'f32)
  let k = fillAlpha.float32 / 255.0'f32
  drawRectangleRounded(pill, 0.5'f32, 6, rgbaF(6, 10, 18, 200.0'f32 * k))
  drawRectangleRoundedLines(pill, 0.5'f32, 6, -1.0'f32, withAlpha(labelColor, 150.0'f32 * k))
  drawText(text, lx + 1, ly + 1, fontSize, rgbaF(0, 0, 0, 170.0'f32 * k))
  drawText(text, lx, ly, fontSize, withAlpha(labelColor, fillAlpha))

proc drawGameplayRingOverlay(bg: OSBackgroundState, screenWidth, screenHeight: int32) =
  ## The boss-arena zones: boon bands, the hazard disc and the rotating bonus
  ## sectors. Drawn as force fields - bright, crisp edges over a softer fill,
  ## with motion along them - so they read at a glance against the dim floor.
  ## The geometry is exactly the gameplay's (arenaRingRadius, the half width).
  if bg.bossArenaMode == barmNone:
    return

  let center = v2(screenWidth.float32 * 0.5'f32, screenHeight.float32 * 0.5'f32)
  let cx = center.x
  let cy = center.y
  let pulse = sin(bg.bossArenaPhase * 4.2'f32) * 0.5'f32 + 0.5'f32
  let fastPulse = sin(bg.bossArenaPhase * 9.0'f32) * 0.5'f32 + 0.5'f32
  let flow = bg.bossArenaPhase
  let hazardBand = activeHazardBand(bg)

  for band in 0 ..< BOSS_ARENA_RING_COUNT:
    let radius = arenaRingRadius(screenWidth, screenHeight, band)
    let innerR = radius - BOSS_ARENA_RING_HALF_WIDTH
    let outerR = radius + BOSS_ARENA_RING_HALF_WIDTH
    let isPlayerHere =
      if bg.bossArenaMode == barmHazard:
        band == hazardBand and bg.bossArenaPlayerOnActive
      else:
        bg.bossArenaPlayerBand == band and bg.bossArenaPlayerOnActive

    case bg.bossArenaMode
    of barmBoon:
      if band in [1, 2]:
        # Active boon band: a green field, chevron dashes flowing round it,
        # crisp rims with a glow.
        let fillA = if isPlayerHere: 58.0'f32 + pulse * 30.0'f32 else: 22.0'f32 + pulse * 18.0'f32
        drawBandArc(center, innerR, outerR, 0.0'f32, PI * 2.0'f32,
                    rgbaF(70, 250, 150, min(255.0'f32, fillA * 2.4'f32)), rgbaF(50, 240, 130, fillA * 0.8'f32))
        let dir = if band == 1: 1.0'f32 else: -1.0'f32
        drawDashedRing(center, radius, 2.4'f32, 18 + band * 6, 0.45'f32, flow * (0.35'f32 + band.float32 * 0.1'f32) * dir,
                   rgbaF(150, 255, 200, 70.0'f32 + pulse * 70.0'f32))
        let rimA = 120.0'f32 + pulse * 80.0'f32
        let th = if isPlayerHere: 3.0'f32 else: 2.0'f32
        drawSoftRing(center, outerR + th * 0.5'f32, 10.0'f32, rgbaF(90, 255, 190, rimA * 0.4'f32))
        drawSoftRing(center, innerR - th * 0.5'f32, 10.0'f32, rgbaF(90, 255, 190, rimA * 0.4'f32))
        drawCircleOutline(center, outerR + th, th, rgbaF(110, 255, 200, rimA))
        drawCircleOutline(center, innerR, th, rgbaF(110, 255, 200, rimA))
        drawZoneLabel("+ BONUS ZONE", cx, cy, outerR, alphaFrom(160.0'f32 + pulse * 65.0'f32),
                      rgba(110, 255, 165))
      else:
        # Inactive band: a faint field with a dashed centre line.
        drawBandArc(center, innerR, outerR, 0.0'f32, PI * 2.0'f32, rgba(60, 110, 140, 24), rgba(40, 80, 100, 8))
        drawDashedRing(center, radius, 0.8'f32, 40, 0.5'f32, flow * 0.05'f32, rgba(70, 130, 170, 50))
        drawZoneLabel("neutral", cx, cy, outerR, 55, rgba(100, 140, 170), 9)

    of barmHazard:
      if band == hazardBand:
        # The active hazard covers the whole disc to its outer edge: a red dome
        # that deepens toward its rim (the edge to escape across), a caution
        # band rolling round that rim, and a hot outline throwing light out.
        let fillA = if isPlayerHere: 72.0'f32 + fastPulse * 45.0'f32 else: 30.0'f32 + pulse * 25.0'f32
        drawRadialGradient(center, outerR, outerR, rgbaF(255, 32, 22, fillA * 0.55'f32),
                           rgbaF(255, 40, 28, min(255.0'f32, fillA * 1.45'f32)), reSmooth)
        let outA = 145.0'f32 + fastPulse * 90.0'f32
        let stripeIn = outerR - 12.0'f32
        const Stripes = 56
        let roll = flow * 0.25'f32
        for k in 0 ..< Stripes:
          let a0 = k.float32 / Stripes.float32 * PI * 2.0'f32 + roll
          let a1 = (k + 1).float32 / Stripes.float32 * PI * 2.0'f32 + roll
          let slant = (a1 - a0) * 0.6'f32
          let col = if k mod 2 == 0: rgbaF(255, 74, 52, outA * 0.85'f32) else: rgbaF(70, 0, 0, outA * 0.5'f32)
          drawGradientQuad(v2(cx + cos(a0 + slant) * stripeIn, cy + sin(a0 + slant) * stripeIn),
                           v2(cx + cos(a0) * outerR, cy + sin(a0) * outerR),
                           v2(cx + cos(a1) * outerR, cy + sin(a1) * outerR),
                           v2(cx + cos(a1 + slant) * stripeIn, cy + sin(a1 + slant) * stripeIn),
                           col, col, col, col)
        let th = if isPlayerHere: 4.0'f32 else: 3.0'f32
        drawSoftRing(center, outerR + th, 16.0'f32, rgbaF(255, 60, 48, outA * 0.45'f32))
        drawCircleOutline(center, outerR + th, th, rgbaF(255, 70, 55, outA))
        drawCircleOutline(center, stripeIn, 1.5'f32, rgbaF(255, 90, 70, outA * 0.6'f32))
        drawZoneLabel("! HAZARD !", cx, cy, outerR, alphaFrom(180.0'f32 + fastPulse * 60.0'f32),
                      rgba(255, 80, 55))
      else:
        # A safe band: a dim reddish field hinting at the mode.
        drawBandArc(center, innerR, outerR, 0.0'f32, PI * 2.0'f32, rgba(130, 50, 55, 26), rgba(80, 30, 30, 8))
        drawDashedRing(center, radius, 0.8'f32, 40, 0.5'f32, -flow * 0.05'f32, rgba(130, 60, 65, 50))
        drawZoneLabel("safe", cx, cy, outerR, 55, rgba(160, 100, 100), 9)

    of barmRotating:
      # Dim base ring so the sectors stand out against it.
      drawDashedRing(center, radius, 0.8'f32, 48, 0.55'f32, 0.0'f32, rgba(60, 140, 200, 45))
      let sweep = bg.bossArenaRotation + band.float32 * 0.72'f32
      for sector in 0 .. 1:
        let angle = sweep + sector.float32 * PI
        let a0 = angle - 0.42'f32
        let a1 = angle + 0.42'f32
        let fillA = if isPlayerHere: 62.0'f32 + pulse * 38.0'f32 else: 26.0'f32 + pulse * 16.0'f32
        let outA = if isPlayerHere: 160.0'f32 + pulse * 80.0'f32 else: 100.0'f32 + pulse * 42.0'f32
        drawBandArc(center, innerR, outerR, a0, a1, rgbaF(90, 215, 255, min(255.0'f32, fillA * 2.2'f32)),
                    rgbaF(80, 210, 255, fillA * 0.9'f32))
        drawRing(center, radius - 3.0'f32, radius + 3.0'f32, deg(a0), deg(a1), 24, rgbaF(140, 235, 255, outA))
        # Crisp ends show the sector's exact span; the leading one glows.
        for (edgeA, lead) in [(a0, false), (a1, true)]:
          let p0 = v2(cx + cos(edgeA) * innerR, cy + sin(edgeA) * innerR)
          let p1 = v2(cx + cos(edgeA) * outerR, cy + sin(edgeA) * outerR)
          if lead:
            drawGlowLine(p0, p1, 10.0'f32, rgbaF(140, 235, 255, outA * 0.6'f32))
          drawStroke(p0, p1, 2.0'f32, rgbaF(180, 245, 255, outA))
      drawZoneLabel("+ BONUS SECTORS", cx, cy, outerR, alphaFrom(130.0'f32 + pulse * 55.0'f32),
                    rgba(120, 225, 255))

    of barmNone:
      discard

  # Player zone feedback glow
  if bg.bossArenaPlayerOnActive:
    let glowColor =
      case bg.bossArenaMode
      of barmHazard:
        rgbaF(255, 65, 48, 90.0'f32 + fastPulse * 60.0'f32)
      of barmBoon, barmRotating:
        rgbaF(80, 255, 190, 80.0'f32 + bg.bossArenaBonusIntensity * 90.0'f32)
      of barmNone:
        Color(r: 0, g: 0, b: 0, a: 0)
    let p = v2(bg.bossArenaPlayerX, bg.bossArenaPlayerY)
    drawGlow(p, 46.0'f32, glowColor)
    drawGlow(p, 86.0'f32, withAlpha(glowColor, glowColor.a.float32 * 0.45'f32))

proc newOSBackground*(): OSBackgroundState =
  result = OSBackgroundState(
    dataPackets: @[],
    circuitLines: @[],
    gridPulseTime: 0.0,
    alertLevel: 0.0,
    lowHealthVignetteLevel: 0.0,
    bossArenaMode: barmNone,
    bossArenaPhase: 0.0,
    bossArenaRotation: 0.0,
    bossArenaDamageCooldown: 0.0,
    bossArenaPlayerBand: -1,
    bossArenaPlayerOnActive: false,
    bossArenaBonusIntensity: 0.0,
    bossArenaPlayerX: 0.0,
    bossArenaPlayerY: 0.0
  )

  # Initialize circuit lines
  for i in 0..<NUM_CIRCUIT_LINES:
    result.circuitLines.add(CircuitLine(
      y: (i * 100).float32,
      speed: 50.0 + (i.float32 * 10.0),
      pulseOffset: (i.float32 * 0.5)
    ))

proc spawnWavePulse*(bg: var OSBackgroundState, cx, cy: float32, color: Color) =
  ## Call this at wave start/end to emit an expanding pulse ring.
  bg.wavePulseRings.add(WavePulseRing(
    centerX: cx,
    centerY: cy,
    radius: 10.0,
    maxRadius: 900.0,
    alpha: 1.0,
    color: color
  ))

proc updateOSBackground*(bg: var OSBackgroundState, dt: float32, playerHP: float32, maxHP: float32,
                         bossActive: bool, screenWidth, screenHeight: int32) =
  bg.gridPulseTime += dt

  let safeMaxHp = max(maxHP, 0.01'f32)
  let hpPercent = clamp(playerHP / safeMaxHp, 0.0, 1.0)
  let targetAlert = if bossActive: 0.8 else: 0.0
  let targetLowHealthVignette =
    if hpPercent <= 0.10:
      1.0
    elif hpPercent < 0.40:
      (0.40 - hpPercent) / 0.30
    else:
      0.0

  # Smooth transition to target alert level
  if bg.alertLevel < targetAlert:
    bg.alertLevel = min(bg.alertLevel + dt * 0.5, targetAlert)
  else:
    bg.alertLevel = max(bg.alertLevel - dt * 0.5, targetAlert)

  if bg.lowHealthVignetteLevel < targetLowHealthVignette:
    bg.lowHealthVignetteLevel = min(bg.lowHealthVignetteLevel + dt * 1.5, targetLowHealthVignette)
  else:
    bg.lowHealthVignetteLevel = max(bg.lowHealthVignetteLevel - dt * 1.5, targetLowHealthVignette)

  # Update wave pulse rings
  var ri = 0
  while ri < bg.wavePulseRings.len:
    bg.wavePulseRings[ri].radius += 400.0 * dt
    bg.wavePulseRings[ri].alpha  = 1.0 - (bg.wavePulseRings[ri].radius / bg.wavePulseRings[ri].maxRadius)
    if bg.wavePulseRings[ri].alpha <= 0.0:
      bg.wavePulseRings.delete(ri)
    else:
      ri += 1

  # Update circuit lines
  let circuitWrapHeight = screenHeight.float32 + 160.0
  for line in bg.circuitLines.mitems:
    line.y += line.speed * dt
    if line.y > screenHeight.float32 + 80.0:
      line.y -= circuitWrapHeight

  # Update data packets
  let packetCullX = screenWidth.float32 + 80.0
  var i = 0
  while i < bg.dataPackets.len:
    bg.dataPackets[i].x += bg.dataPackets[i].speed * dt
    if bg.dataPackets[i].x > packetCullX:
      bg.dataPackets.delete(i)
    else:
      i += 1

  # Spawn new data packets
  let spawnHeight = max(screenHeight.int - 1, 1)
  if bg.dataPackets.len < MAX_DATA_PACKETS and (rand(100) < 5):
    bg.dataPackets.add(DataPacket(
      x: -40.0,
      y: rand(spawnHeight).float32,
      speed: 55.0 + rand(120).float32,
      alpha: uint8(28 + rand(36))
    ))

proc drawOSBackground*(bg: OSBackgroundState, screenWidth, screenHeight: int32,
                       showArenaVignette: bool = true,
                       accentOverride: Color = Color(r: 0, g: 0, b: 0, a: 0)) =
  ## The arena behind the run: its floor, the boss-arena zones, the data
  ## streams crossing it, wave pulses and the danger washes. Translucent light
  ## adds to the floor instead of darkening the frame (see ui_theme).
  let w = screenWidth.float32
  let h = screenHeight.float32
  # Dungeon floors and survival phases tint the arena with their accent.
  let tinted = accentOverride.a > 0
  let accent = if tinted: accentOverride else: Color(r: 0, g: 198, b: 236, a: 255)
  beginKeepAlpha()
  defer: endKeepAlpha()

  drawArenaFloor(screenWidth, screenHeight, bg.gridPulseTime, accent, tinted, bg.alertLevel)
  drawGameplayRingOverlay(bg, screenWidth, screenHeight)

  # Boss alert: red light washing in from the edges over a faint tint.
  if bg.alertLevel > 0:
    drawRectangle(Rectangle(x: 0, y: 0, width: w, height: h), rgbaF(255, 0, 0, bg.alertLevel * 20.0'f32))
    edgeWash(w, h, min(w, h) * 0.24'f32, rgbaF(255, 20, 20, bg.alertLevel * 30.0'f32))

  # Soft arena edge vignette (4 gradient rectangles)
  if showArenaVignette:
    drawArenaEdgeVignette(screenWidth, screenHeight, bg.lowHealthVignetteLevel)

  # Circuit lines (horizontal data streams): a soft line, a crisp core and a
  # faint echo, with risers and glowing nodes where they cross the anchors.
  let circuitAnchors = [0.12'f32, 0.28'f32, 0.5'f32, 0.72'f32, 0.88'f32]
  for index, line in bg.circuitLines:
    let pulse = sin(bg.gridPulseTime * 2 + line.pulseOffset) * 0.5 + 0.5
    let shimmer = sin(bg.gridPulseTime * 4 + index.float32 * 0.5) * 0.5 + 0.5
    let lineAlpha = alphaFrom(18.0 + pulse * 28.0)
    let lineColor = Color(r: 0, g: uint8(150 + pulse * 40), b: uint8(188 + shimmer * 50), a: lineAlpha)
    drawGlowLine(v2(0, line.y), v2(w, line.y), 6.0'f32, withAlpha(lineColor, lineAlpha.float32 * 0.22'f32))
    drawStroke(0, line.y.int32, screenWidth, line.y.int32, lineColor)
    drawStroke(0, (line.y + 3.0).int32, screenWidth, (line.y + 3.0).int32,
             withAlpha(lineColor, lineAlpha div 3))
    if int(line.y) mod 180 < 64:
      for anchor in circuitAnchors:
        let x = screenWidth.float32 * anchor +
                sin(bg.gridPulseTime * 1.4 + line.pulseOffset + anchor * PI) * 18.0
        let segHeight = 24.0 + pulse * 18.0
        let nodeColor = Color(r: 70, g: 220, b: 255, a: uint8(70 + shimmer * 55))
        drawFadeStroke(v2(x, line.y - segHeight), v2(x, line.y + segHeight), 1.3'f32,
                   withAlpha(lineColor, min(255, lineColor.a.int + 40)))
        drawGlow(v2(x, line.y), 7.0'f32 + pulse * 2.0'f32, withAlpha(nodeColor, nodeColor.a.float32 * 0.5'f32))
        drawDisc(v2(x, line.y), 1.8 + pulse * 1.2, brighten(nodeColor, 40.0'f32))

  # Data packets: comets with a hot head.
  for packet in bg.dataPackets:
    let packetColor = Color(r: 0, g: 200, b: 255, a: packet.alpha)
    let streak = 16.0'f32 + packet.speed * 0.07'f32
    let head = v2(packet.x, packet.y)
    drawTaperedLine(v2(packet.x - streak, packet.y), head, 0.0'f32, 2.6'f32, clearOf(packetColor),
                    withAlpha(packetColor, packet.alpha.float32 * 0.9'f32))
    drawGlow(head, 8.0'f32, withAlpha(packetColor, packet.alpha.float32 * 0.9'f32))
    drawDisc(head, 2.0'f32, Color(r: 170, g: 240, b: 255, a: min(255, packet.alpha.int * 3).uint8))

  # Wave pulse rings: a front of light with a soft wake inside it.
  for ring in bg.wavePulseRings:
    let rAlpha = ring.alpha * 180.0'f32
    let c = v2(ring.centerX, ring.centerY)
    drawGradientRing(c, ring.radius * 0.55'f32, ring.radius, clearOf(ring.color),
                     withAlpha(ring.color, rAlpha * 0.25'f32))
    drawSoftRing(c, ring.radius, 9.0'f32, withAlpha(ring.color, rAlpha * 0.5'f32))
    drawCircleOutline(c, ring.radius, withAlpha(ring.color, rAlpha))

  # Critical status border pulse: red light from the edges and a fine frame.
  if bg.alertLevel > 0.5:
    let borderPulse = sin(bg.gridPulseTime * 4) * 0.5 + 0.5
    let borderAlpha = (bg.alertLevel - 0.5) * 2.0'f32 * 100.0'f32 * borderPulse
    edgeWash(w, h, 30.0'f32, rgbaF(255, 0, 0, borderAlpha * 0.9'f32))
    drawRectOutline(Rectangle(x: 0, y: 0, width: w, height: h), 2.0'f32, rgbaF(255, 40, 40, borderAlpha * 1.6'f32))

  # Low health: a red wash, deepest at the edges, beating faster when low.
  if bg.lowHealthVignetteLevel > 0.0:
    let dangerPulse = sin(bg.gridPulseTime * 5.6) * 0.5 + 0.5
    let lowAlpha = bg.lowHealthVignetteLevel * (34.0'f32 + dangerPulse * 30.0'f32)
    drawRectangle(Rectangle(x: 0, y: 0, width: w, height: h), rgbaF(255, 28, 24, lowAlpha * 0.3'f32))
    edgeWash(w, h, min(w, h) * 0.26'f32, rgbaF(255, 28, 24, lowAlpha * 0.75'f32))
