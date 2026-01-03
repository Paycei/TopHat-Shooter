## OS-Style Background System for TopHat-Shooter

import raylib, math, random, types

const
  GRID_SIZE = 40
  MAX_DATA_PACKETS = 50
  NUM_CIRCUIT_LINES = 8

proc newOSBackground*(): OSBackgroundState =
  result = OSBackgroundState(
    dataPackets: @[],
    circuitLines: @[],
    gridPulseTime: 0.0,
    alertLevel: 0.0
  )
  
  # Initialize circuit lines
  for i in 0..<NUM_CIRCUIT_LINES:
    result.circuitLines.add(CircuitLine(
      y: (i * 100).float32,
      speed: 50.0 + (i.float32 * 10.0),
      pulseOffset: (i.float32 * 0.5)
    ))

proc updateOSBackground*(bg: var OSBackgroundState, dt: float32, playerHP: float32, maxHP: float32, bossActive: bool) =
  bg.gridPulseTime += dt
  
  # Update alert level based on player HP
  let hpPercent = playerHP / maxHP
  let targetAlert = if bossActive: 0.8
                   elif hpPercent < 0.2: 0.6
                   elif hpPercent < 0.5: 0.3
                   else: 0.0
  
  # Smooth transition to target alert level
  if bg.alertLevel < targetAlert:
    bg.alertLevel = min(bg.alertLevel + dt * 0.5, targetAlert)
  else:
    bg.alertLevel = max(bg.alertLevel - dt * 0.5, targetAlert)
  
  # Update circuit lines
  for line in bg.circuitLines.mitems:
    line.y += line.speed * dt
    if line.y > 800: line.y -= 800
  
  # Update data packets
  var i = 0
  while i < bg.dataPackets.len:
    bg.dataPackets[i].x += bg.dataPackets[i].speed * dt
    if bg.dataPackets[i].x > 1280:
      bg.dataPackets.delete(i)
    else:
      i += 1
  
  # Spawn new data packets
  if bg.dataPackets.len < MAX_DATA_PACKETS and (rand(100) < 5):
    bg.dataPackets.add(DataPacket(
      x: 0,
      y: rand(720).float32,
      speed: 50.0 + rand(100).float32,
      alpha: uint8(30 + rand(30))
    ))

proc drawOSBackground*(bg: OSBackgroundState, screenWidth, screenHeight: int32) =
  # Base gradient background (dark blue-gray)
  let topColor = Color(r: 10, g: 15, b: 25, a: 255)
  let bottomColor = Color(r: 20, g: 25, b: 40, a: 255)
  
  drawRectangleGradientV(0, 0, screenWidth, screenHeight, topColor, bottomColor)
  
  # Alert overlay (red tint when in danger)
  if bg.alertLevel > 0:
    let redAlpha = uint8(bg.alertLevel * 40)
    drawRectangle(0, 0, screenWidth, screenHeight, 
                 Color(r: 255, g: 0, b: 0, a: redAlpha))
  
  # Draw grid
  let gridAlpha = uint8(60 + sin(bg.gridPulseTime) * 20)
  let gridColor = Color(r: 30, g: 35, b: 50, a: gridAlpha)
  
  # Vertical grid lines
  var x: int32 = 0
  while x < screenWidth:
    drawLine(x, 0, x, screenHeight, gridColor)
    x += GRID_SIZE
  
  # Horizontal grid lines
  var y: int32 = 0
  while y < screenHeight:
    drawLine(0, y, screenWidth, y, gridColor)
    y += GRID_SIZE
  
  # Draw circuit lines (horizontal data streams)
  for line in bg.circuitLines:
    let pulse = sin(bg.gridPulseTime * 2 + line.pulseOffset) * 0.5 + 0.5
    let lineAlpha = uint8(30 + pulse * 20)
    let lineColor = Color(r: 0, g: 200, b: 200, a: lineAlpha)
    
    drawLine(0, line.y.int32, screenWidth, line.y.int32, lineColor)
    
    # Draw connecting vertical segments
    if int(line.y) mod 200 < 50:
      let segmentY = line.y - 20
      drawLine(100, segmentY.int32, 100, (segmentY + 40).int32, lineColor)
      drawLine(400, segmentY.int32, 400, (segmentY + 40).int32, lineColor)
      drawLine(700, segmentY.int32, 700, (segmentY + 40).int32, lineColor)
  
  # Draw data packets
  for packet in bg.dataPackets:
    drawCircle(Vector2(x: packet.x, y: packet.y), 3, 
              Color(r: 0, g: 200, b: 255, a: packet.alpha))
    
    # Trail effect
    for i in 1..3:
      let trailX = packet.x - (i * 5).float32
      let trailAlpha = packet.alpha div (i * 2).uint8
      drawCircle(Vector2(x: trailX, y: packet.y), 2, 
                Color(r: 0, g: 200, b: 255, a: trailAlpha))
  
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
