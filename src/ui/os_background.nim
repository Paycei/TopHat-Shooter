## OS-Style Background System

import raylib, math, random
import ../types, background_fx

const
  MAX_DATA_PACKETS = 50
  NUM_CIRCUIT_LINES = 8
  BOSS_ARENA_RING_COUNT = 3
  BOSS_ARENA_RING_HALF_WIDTH = 18.0'f32
  BOSS_ARENA_DAMAGE = 0.35'f32
  BOSS_ARENA_DAMAGE_INTERVAL = 0.85'f32

proc alphaFrom(value: float32): uint8 =
  uint8(clamp(value, 0.0'f32, 255.0'f32))

proc bossArenaModeForWave(currentWave: int): BossArenaRingMode =
  if currentWave <= 0:
    return barmNone

  let bossTier = max(1, currentWave div 5)
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

proc drawCombatGrid(bg: OSBackgroundState, screenWidth, screenHeight: int32) =
  let w = screenWidth.float32
  let h = screenHeight.float32
  let centerX = w * 0.5
  let centerY = h * 0.5
  let arenaRadius = min(w, h) * 0.42
  let pulse = sin(bg.gridPulseTime * 1.35) * 0.5 + 0.5
  let alertPulse = sin(bg.gridPulseTime * 4.8) * 0.5 + 0.5

  # Atmospheric fills
  # Large ambient centre glow, fills the dead centre of the arena
  drawSoftGlow(centerX, centerY, arenaRadius * 1.4,
               Color(r: 0, g: 100, b: 160, a: alphaFrom(28.0 + pulse * 12.0)), 0.55)
  # Mid-arena depth ring fill
  drawSoftGlow(centerX, centerY, arenaRadius * 0.9,
               Color(r: 10, g: 60, b: 120, a: alphaFrom(18.0 + pulse * 8.0)), 0.48)
  # Off-centre atmospheric accent blobs (fill empty quadrant corners)
  drawSoftGlow(w * 0.18, h * 0.78, arenaRadius * 0.60,
               Color(r: 95, g: 115, b: 255, a: alphaFrom(22.0 + pulse * 10.0)), 0.52)
  drawSoftGlow(w * 0.84, h * 0.22, arenaRadius * 0.55,
               Color(r: 0, g: 200, b: 170, a: alphaFrom(18.0 + pulse * 8.0)), 0.45)
  drawSoftGlow(w * 0.08, h * 0.38, arenaRadius * 0.40,
               Color(r: 60, g: 80, b: 200, a: alphaFrom(14.0 + pulse * 6.0)), 0.40)
  drawSoftGlow(w * 0.92, h * 0.62, arenaRadius * 0.45,
               Color(r: 0, g: 170, b: 220, a: alphaFrom(16.0 + pulse * 7.0)), 0.42)
  # Edge-fill sweeping light at top and bottom to break the void
  drawSoftGlow(w * 0.50, 0.0, arenaRadius * 0.70,
               Color(r: 20, g: 80, b: 160, a: alphaFrom(20.0 + pulse * 8.0)), 0.38)
  drawSoftGlow(w * 0.50, h, arenaRadius * 0.70,
               Color(r: 0, g: 70, b: 150, a: alphaFrom(18.0 + pulse * 7.0)), 0.38)

  for i in 0..4:
    let r = arenaRadius * (0.34 + i.float32 * 0.16)
    let ringAlpha = alphaFrom(10.0 + i.float32 * 3.0 + pulse * 6.0)  # Dimmed: gameplay rings must dominate
    drawCircleLines(centerX.int32, centerY.int32, r,
      Color(r: 40, g: 110, b: 155, a: ringAlpha))
    let sweepAngle = bg.gridPulseTime * (0.42 + i.float32 * 0.05) + i.float32 * PI * 0.34
    let sx = centerX + cos(sweepAngle) * r
    let sy = centerY + sin(sweepAngle) * r
    drawCircle(Vector2(x: sx, y: sy), 2.4 + i.float32 * 0.35,
      Color(r: 180, g: 250, b: 255, a: alphaFrom(118.0 + pulse * 62.0)))

  for i in 0..<12:
    let angle = i.float32 * PI / 6.0
    let inner = arenaRadius * 0.22
    let outer = arenaRadius * 1.03
    let alpha = alphaFrom(18.0 + (if i mod 3 == 0: 28.0 else: 0.0) + pulse * 8.0)
    drawLine(Vector2(x: centerX + cos(angle) * inner, y: centerY + sin(angle) * inner),
             Vector2(x: centerX + cos(angle) * outer, y: centerY + sin(angle) * outer),
             1, Color(r: 64, g: 185, b: 230, a: alpha))

  let laneColor = Color(r: 0, g: 220, b: 240, a: alphaFrom(28.0 + pulse * 18.0))
  for i in 0..<7:
    let t = (i.float32 - 3.0) / 3.0
    let topX = centerX + t * arenaRadius * 0.45
    let bottomX = centerX + t * arenaRadius * 1.25
    drawLine(Vector2(x: topX, y: centerY - arenaRadius * 0.9),
             Vector2(x: bottomX, y: centerY + arenaRadius * 1.05),
             1, laneColor)
    drawLine(Vector2(x: centerX - arenaRadius * 1.05, y: centerY + t * arenaRadius * 1.25),
             Vector2(x: centerX + arenaRadius * 1.05, y: centerY + t * arenaRadius * 0.45),
             1, withAlpha(laneColor, laneColor.a div 2))

  if bg.alertLevel > 0.0:
    let hazardAlpha = alphaFrom(bg.alertLevel * (36.0 + alertPulse * 40.0))
    for i in 0..<6:
      let angle = i.float32 * PI / 3.0 + bg.gridPulseTime * 0.22
      let x = centerX + cos(angle) * arenaRadius * 0.78
      let y = centerY + sin(angle) * arenaRadius * 0.78
      drawLine(Vector2(x: x - 12.0, y: y - 12.0),
               Vector2(x: x + 12.0, y: y + 12.0), 2,
               Color(r: 255, g: 62, b: 55, a: hazardAlpha))
      drawLine(Vector2(x: x + 12.0, y: y - 12.0),
               Vector2(x: x - 12.0, y: y + 12.0), 2,
               Color(r: 255, g: 62, b: 55, a: hazardAlpha))

proc drawZoneLabel(text: string, centerX, centerY, radius: float32, fillAlpha: uint8,
                   labelColor: Color, fontSize: int32 = 11) =
  ## Draws a small label just above the top of a ring zone.
  let labelWidth = measureText(text, fontSize)
  let lx = (centerX - labelWidth.float32 * 0.5).int32
  let ly = (centerY - radius - BOSS_ARENA_RING_HALF_WIDTH - fontSize.float32 - 3.0).int32
  # Shadow
  drawText(text, lx + 1, ly + 1, fontSize, Color(r: 0, g: 0, b: 0, a: uint8(fillAlpha.float32 * 0.65)))
  drawText(text, lx, ly, fontSize, withAlpha(labelColor, fillAlpha))

proc drawGameplayRingOverlay(bg: OSBackgroundState, screenWidth, screenHeight: int32) =
  ## Draws the boss-arena interactive ring zones with fills, thick outlines, and labels
  ## so players can immediately distinguish them from the decorative grid.
  if bg.bossArenaMode == barmNone:
    return

  let center = Vector2(x: screenWidth.float32 * 0.5, y: screenHeight.float32 * 0.5)
  let cx = center.x
  let cy = center.y
  let pulse = sin(bg.bossArenaPhase * 4.2) * 0.5 + 0.5
  let fastPulse = sin(bg.bossArenaPhase * 9.0) * 0.5 + 0.5
  let hazardBand = activeHazardBand(bg)

  for band in 0..<BOSS_ARENA_RING_COUNT:
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
        # Active boon zone: green fill + thick outline + label
        let fillA = alphaFrom(if isPlayerHere: 58.0 + pulse * 30.0 else: 22.0 + pulse * 18.0)
        drawRing(center, innerR, outerR, 0.0, 360.0, 80,
          Color(r: 50, g: 240, b: 130, a: fillA))

        # Pulsing inner highlight stripe
        drawRing(center, radius - 3.0, radius + 3.0, 0.0, 360.0, 80,
          Color(r: 100, g: 255, b: 185, a: alphaFrom(70.0 + pulse * 60.0)))

        # Multi-pixel outline
        let outA = alphaFrom(120.0 + pulse * 80.0)
        let thickness = if isPlayerHere: 5 else: 3
        for i in 0..<thickness:
          drawCircleLines(cx.int32, cy.int32, (outerR + i.float32),
            Color(r: 90, g: 255, b: 190, a: alphaFrom(outA.float32 - i.float32 * 28.0)))
          drawCircleLines(cx.int32, cy.int32, (innerR - i.float32),
            Color(r: 90, g: 255, b: 190, a: alphaFrom(outA.float32 - i.float32 * 28.0)))

        drawZoneLabel("+ BONUS ZONE", cx, cy, outerR,
          alphaFrom(160.0 + pulse * 65.0),
          Color(r: 110, g: 255, b: 165, a: 255))
      else:
        # Inactive band, subtle dim outline, tiny label
        drawRing(center, innerR, outerR, 0.0, 360.0, 64,
          Color(r: 40, g: 80, b: 100, a: 14))
        drawCircleLines(cx.int32, cy.int32, radius,
          Color(r: 70, g: 130, b: 170, a: 36))
        drawZoneLabel("neutral", cx, cy, outerR, 55,
          Color(r: 100, g: 140, b: 170, a: 255), 9)

    of barmHazard:
      if band == hazardBand:
        # Active hazard zone: red fill covering entire circle interior + thick pulsing outline + label
        let fillA = alphaFrom(if isPlayerHere: 72.0 + fastPulse * 45.0 else: 30.0 + pulse * 25.0)
        # Fill the full disk from center to outerR
        drawCircle(center, outerR,
          Color(r: 255, g: 32, b: 22, a: fillA))

        # Multi-pixel outline, flashes urgently
        let outA = alphaFrom(145.0 + fastPulse * 90.0)
        let thickness = if isPlayerHere: 6 else: 4
        for i in 0..<thickness:
          drawCircleLines(cx.int32, cy.int32, (outerR + i.float32),
            Color(r: 255, g: 60, b: 48, a: alphaFrom(outA.float32 - i.float32 * 24.0)))

        drawZoneLabel("! HAZARD !", cx, cy, outerR,
          alphaFrom(180.0 + fastPulse * 60.0),
          Color(r: 255, g: 80, b: 55, a: 255))
      else:
        # Safe non-hazard band, dim reddish tint to hint at the mode
        drawRing(center, innerR, outerR, 0.0, 360.0, 64,
          Color(r: 80, g: 30, b: 30, a: 14))
        drawCircleLines(cx.int32, cy.int32, radius,
          Color(r: 110, g: 50, b: 55, a: 36))
        drawZoneLabel("safe", cx, cy, outerR, 55,
          Color(r: 160, g: 100, b: 100, a: 255), 9)

    of barmRotating:
      # Dim base ring so sectors stand out against it
      drawCircleLines(cx.int32, cy.int32, radius,
        Color(r: 60, g: 140, b: 200, a: 35))

      let sweep = bg.bossArenaRotation + band.float32 * 0.72
      for sector in 0..1:
        let angle = sweep + sector.float32 * PI
        let startDeg = (angle - 0.42) * 180.0 / PI
        let endDeg   = (angle + 0.42) * 180.0 / PI

        # Fill the active sector arc
        let sectorFillA = alphaFrom(
          if isPlayerHere: 62.0 + pulse * 38.0 else: 26.0 + pulse * 16.0)
        drawRing(center, innerR, outerR, startDeg, endDeg, 24,
          Color(r: 80, g: 210, b: 255, a: sectorFillA))

        # Highlight stripe inside sector
        let sectorOutA = alphaFrom(
          if isPlayerHere: 160.0 + pulse * 80.0 else: 100.0 + pulse * 42.0)
        drawRing(center, radius - 4.0, radius + 4.0, startDeg, endDeg, 24,
          Color(r: 140, g: 235, b: 255, a: sectorOutA))

      # Label above the ring, note it rotates conceptually so we always put it at top
      drawZoneLabel("+ BONUS SECTORS", cx, cy, outerR,
        alphaFrom(130.0 + pulse * 55.0),
        Color(r: 120, g: 225, b: 255, a: 255))

    of barmNone:
      discard

  # Player zone feedback glow
  if bg.bossArenaPlayerOnActive:
    let glowColor =
      case bg.bossArenaMode
      of barmHazard:
        Color(r: 255, g: 65, b: 48,
              a: alphaFrom(90.0 + fastPulse * 60.0))
      of barmBoon, barmRotating:
        Color(r: 80, g: 255, b: 190,
              a: alphaFrom(80.0 + bg.bossArenaBonusIntensity * 90.0))
      of barmNone:
        Color(r: 0, g: 0, b: 0, a: 0)
    # Inner tight glow around player
    drawSoftGlow(bg.bossArenaPlayerX, bg.bossArenaPlayerY, 38.0, glowColor, 0.55)
    # Wider ambient halo
    drawSoftGlow(bg.bossArenaPlayerX, bg.bossArenaPlayerY, 72.0,
      withAlpha(glowColor, uint8(glowColor.a.float32 * 0.4)), 0.30)

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
                       showArenaVignette: bool = true) =
  let topColor = Color(r: 4, g: 7, b: 16, a: 255)
  let bottomColor = Color(r: 14, g: 16, b: 30, a: 255)
  let gridColor = Color(r: 30, g: 44, b: 68, a: 36)
  let dotColor = Color(r: 92, g: 126, b: 175, a: 78)
  let accentColor = Color(r: 0, g: 198, b: 236, a: 58)

  drawSharedBackdrop(screenWidth, screenHeight, bg.gridPulseTime * 0.82,
                     topColor, bottomColor,
                     gridColor, dotColor, accentColor,
                     0.62, 0.62)
  drawCombatGrid(bg, screenWidth, screenHeight)
  drawGameplayRingOverlay(bg, screenWidth, screenHeight)

  # Alert overlay (red tint when in danger)
  if bg.alertLevel > 0:
    let redAlpha = alphaFrom(bg.alertLevel * 38.0)
    drawRectangle(0, 0, screenWidth, screenHeight,
                 Color(r: 255, g: 0, b: 0, a: redAlpha))

  # Soft arena edge vignette (4 gradient rectangles)
  if showArenaVignette:
    drawArenaEdgeVignette(screenWidth, screenHeight, bg.lowHealthVignetteLevel)

  # Draw circuit lines (horizontal data streams)
  let circuitAnchors = [0.12'f32, 0.28'f32, 0.5'f32, 0.72'f32, 0.88'f32]
  for index, line in bg.circuitLines:
    let pulse = sin(bg.gridPulseTime * 2 + line.pulseOffset) * 0.5 + 0.5
    let shimmer = sin(bg.gridPulseTime * 4 + index.float32 * 0.5) * 0.5 + 0.5
    let lineAlpha = alphaFrom(18.0 + pulse * 28.0)
    let lineColor = Color(r: 0, g: uint8(150 + pulse * 40), b: uint8(188 + shimmer * 50), a: lineAlpha)

    drawLine(0, line.y.int32, screenWidth, line.y.int32, lineColor)
    drawLine(0, (line.y + 3.0).int32, screenWidth, (line.y + 3.0).int32,
             withAlpha(lineColor, lineAlpha div 3))

    # Draw connecting vertical segments and node pulses
    if int(line.y) mod 180 < 64:
      for anchor in circuitAnchors:
        let x = screenWidth.float32 * anchor +
                sin(bg.gridPulseTime * 1.4 + line.pulseOffset + anchor * PI) * 18.0
        let segHeight = 24.0 + pulse * 18.0
        let nodeColor = Color(r: 70, g: 220, b: 255, a: uint8(70 + shimmer * 55))
        drawLine(x.int32, (line.y - segHeight).int32, x.int32, (line.y + segHeight).int32,
                 withAlpha(lineColor, uint8(min(255, lineColor.a.int + 18))))
        drawCircle(Vector2(x: x, y: line.y), 2.2 + pulse * 1.8, nodeColor)

  # Draw data packets
  for packet in bg.dataPackets:
    let packetColor = Color(r: 0, g: 200, b: 255, a: packet.alpha)
    let streak = 16.0 + packet.speed * 0.055
    drawLine((packet.x - streak).int32, packet.y.int32, packet.x.int32, packet.y.int32,
             withAlpha(packetColor, packet.alpha div 2))
    drawLine((packet.x - streak * 0.55).int32, (packet.y - 4.0).int32,
             packet.x.int32, packet.y.int32,
             withAlpha(packetColor, packet.alpha div 3))
    drawCircle(Vector2(x: packet.x, y: packet.y), 3.0, packetColor)

    # Trail effect
    for i in 1..3:
      let trailX = packet.x - (i * 5).float32
      let trailAlpha = packet.alpha div (i * 2).uint8
      drawCircle(Vector2(x: trailX, y: packet.y), 2,
                Color(r: 0, g: 200, b: 255, a: trailAlpha))

  # Wave pulse rings
  for ring in bg.wavePulseRings:
    let rAlpha = uint8(ring.alpha * 180)
    drawSoftGlow(ring.centerX, ring.centerY, ring.radius * 0.85,
                 Color(r: ring.color.r, g: ring.color.g, b: ring.color.b, a: uint8(rAlpha.float32 * 0.25)), 0.55)
    drawCircleLines(ring.centerX.int32, ring.centerY.int32, ring.radius,
      Color(r: ring.color.r, g: ring.color.g, b: ring.color.b, a: rAlpha))
    # Double-ring for thickness feel
    if ring.radius > 4:
      drawCircleLines(ring.centerX.int32, ring.centerY.int32, ring.radius - 3,
        Color(r: ring.color.r, g: ring.color.g, b: ring.color.b, a: uint8(rAlpha.float32 * 0.5)))

  # Critical status border pulse
  if bg.alertLevel > 0.5:
    let borderPulse = sin(bg.gridPulseTime * 4) * 0.5 + 0.5
    let borderAlpha = uint8((bg.alertLevel - 0.5) * 2 * 100 * borderPulse)
    let borderThickness: int32 = 5

    # Top
    drawRectangle(0, 0, screenWidth, borderThickness,
                 Color(r: 255, g: 0, b: 0, a: borderAlpha))
    # Bottom
    drawRectangle(0, screenHeight - borderThickness, screenWidth, borderThickness,
                 Color(r: 255, g: 0, b: 0, a: borderAlpha))
    # Left
    drawRectangle(0, 0, borderThickness, screenHeight,
                 Color(r: 255, g: 0, b: 0, a: borderAlpha))
    # Right
    drawRectangle(screenWidth - borderThickness, 0, borderThickness, screenHeight,
                 Color(r: 255, g: 0, b: 0, a: borderAlpha))

  if bg.lowHealthVignetteLevel > 0.0:
    let dangerPulse = sin(bg.gridPulseTime * 5.6) * 0.5 + 0.5
    let lowAlpha = alphaFrom(bg.lowHealthVignetteLevel * (34.0 + dangerPulse * 30.0))
    drawRectangle(0, 0, screenWidth, screenHeight,
                  Color(r: 255, g: 28, b: 24, a: lowAlpha))
