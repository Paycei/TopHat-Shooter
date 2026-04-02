## OS-Style Background System

import raylib, math, random, ../types, background_fx

const
  MAX_DATA_PACKETS = 50
  NUM_CIRCUIT_LINES = 8

proc newOSBackground*(): OSBackgroundState =
  result = OSBackgroundState(
    dataPackets: @[],
    circuitLines: @[],
    gridPulseTime: 0.0,
    alertLevel: 0.0,
    lowHealthVignetteLevel: 0.0
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
  let topColor = Color(r: 6, g: 10, b: 22, a: 255)
  let bottomColor = Color(r: 16, g: 22, b: 36, a: 255)
  let gridColor = Color(r: 26, g: 34, b: 58, a: 48)
  let dotColor = Color(r: 72, g: 104, b: 165, a: 96)
  let accentColor = Color(r: 0, g: 188, b: 228, a: 64)

  drawSharedBackdrop(screenWidth, screenHeight, bg.gridPulseTime,
                     topColor, bottomColor,
                     gridColor, dotColor, accentColor,
                     0.75, 0.8)
  
  # Alert overlay (red tint when in danger)
  if bg.alertLevel > 0:
    let redAlpha = uint8(bg.alertLevel * 48)
    drawRectangle(0, 0, screenWidth, screenHeight,
                 Color(r: 255, g: 0, b: 0, a: redAlpha))
  
  # Soft arena edge vignette (4 gradient rectangles)
  if showArenaVignette:
    let vigW: int32 = 120
    let vigAlpha: uint8 = 96
    drawRectangleGradientH(0, 0, vigW, screenHeight,
      Color(r: 0, g: 5, b: 15, a: vigAlpha), Color(r: 0, g: 0, b: 0, a: 0))
    drawRectangleGradientH(screenWidth - vigW, 0, vigW, screenHeight,
      Color(r: 0, g: 0, b: 0, a: 0), Color(r: 0, g: 5, b: 15, a: vigAlpha))
    drawRectangleGradientV(0, 0, screenWidth, vigW,
      Color(r: 0, g: 5, b: 15, a: vigAlpha), Color(r: 0, g: 0, b: 0, a: 0))
    drawRectangleGradientV(0, screenHeight - vigW, screenWidth, vigW,
      Color(r: 0, g: 0, b: 0, a: 0), Color(r: 0, g: 5, b: 15, a: vigAlpha))
  
  # Draw circuit lines (horizontal data streams)
  let circuitAnchors = [0.12'f32, 0.28'f32, 0.5'f32, 0.72'f32, 0.88'f32]
  for index, line in bg.circuitLines:
    let pulse = sin(bg.gridPulseTime * 2 + line.pulseOffset) * 0.5 + 0.5
    let shimmer = sin(bg.gridPulseTime * 4 + index.float32 * 0.5) * 0.5 + 0.5
    let lineAlpha = uint8(24 + pulse * 22)
    let lineColor = Color(r: 0, g: uint8(150 + pulse * 40), b: uint8(188 + shimmer * 50), a: lineAlpha)
    
    drawLine(0, line.y.int32, screenWidth, line.y.int32, lineColor)
    
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
    let streak = 12.0 + packet.speed * 0.04
    drawLine((packet.x - streak).int32, packet.y.int32, packet.x.int32, packet.y.int32,
             withAlpha(packetColor, packet.alpha div 2))
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
