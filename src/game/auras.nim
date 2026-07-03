import raylib, rlgl, math
import types, particle_types

# Unified aura configuration and rendering system

type
  AuraVisualStyle = enum
    avsFlames         # Fire aura - rising flames and wisps
    avsLightning      # Lightning aura - electric arcs and bolts
    avsPoison         # Poison aura - toxic bubbles and fog
    avsWind           # Wind aura - swirling air currents
    avsArcane         # Arcane aura - orbiting runes and sparkles
    avsBlood          # Blood aura - dripping blood and mist

type
  AuraConfig = object
    radius: float32
    coreColor: Color
    ringColor: Color
    borderColor: Color
    pulseSpeed: float32
    visualStyle: AuraVisualStyle

proc getAuraRadius*(level: int): float32 =
  ## Standard aura radius based on level (used by most aura effects)
  case level
  of 1: 187.5
  of 2: 250.0
  else: 312.5

# Aura configurations for each power-up type
proc getAuraConfig*(auraType: PowerUpType, level: int): AuraConfig =
  let radius = getAuraRadius(level)

  case auraType
  of puSlowField:
    result = AuraConfig(
      radius: radius,
      coreColor: Color(r: 100, g: 150, b: 255, a: 20),
      ringColor: Color(r: 120, g: 170, b: 255, a: 40),
      borderColor: Color(r: 100, g: 160, b: 255, a: 200),
      pulseSpeed: 1.5,
      visualStyle: avsWind  # Closest style, swirling currents fit a slow field
    )
  of puFireAura:
    result = AuraConfig(
      radius: radius,
      coreColor: Color(r: 255, g: 200, b: 100, a: 40),
      ringColor: Color(r: 255, g: 100, b: 0, a: 60),
      borderColor: Color(r: 255, g: 80, b: 0, a: 80),
      pulseSpeed: 3.0,
      visualStyle: avsFlames
    )
  of puLightningAura:
    result = AuraConfig(
      radius: radius,
      coreColor: Color(r: 150, g: 200, b: 255, a: 50),
      ringColor: Color(r: 150, g: 200, b: 255, a: 50),
      borderColor: Color(r: 100, g: 180, b: 255, a: 70),
      pulseSpeed: 5.0,
      visualStyle: avsLightning
    )
  of puPoisonAura:
    result = AuraConfig(
      radius: radius,
      coreColor: Color(r: 80, g: 200, b: 80, a: 30),
      ringColor: Color(r: 100, g: 255, b: 100, a: 50),
      borderColor: Color(r: 80, g: 220, b: 80, a: 75),
      pulseSpeed: 2.5,
      visualStyle: avsPoison
    )
  of puWindAura:
    result = AuraConfig(
      radius: radius,
      coreColor: Color(r: 220, g: 240, b: 255, a: 35),
      ringColor: Color(r: 200, g: 230, b: 255, a: 50),
      borderColor: Color(r: 180, g: 220, b: 255, a: 65),
      pulseSpeed: 2.5,
      visualStyle: avsWind
    )
  of puArcaneAura:
    result = AuraConfig(
      radius: radius,
      coreColor: Color(r: 200, g: 100, b: 255, a: 45),
      ringColor: Color(r: 200, g: 100, b: 255, a: 55),
      borderColor: Color(r: 200, g: 100, b: 255, a: 180),
      pulseSpeed: 3.5,
      visualStyle: avsArcane
    )
  of puBloodAura:
    result = AuraConfig(
      radius: radius,
      coreColor: Color(r: 150, g: 30, b: 30, a: 50),
      ringColor: Color(r: 255, g: 50, b: 50, a: 60),
      borderColor: Color(r: 200, g: 40, b: 40, a: 85),
      pulseSpeed: 2.8,
      visualStyle: avsBlood
    )
  else:
    # Default fallback (should never happen)
    result = AuraConfig(
      radius: radius,
      coreColor: Color(r: 255, g: 255, b: 255, a: 50),
      ringColor: Color(r: 255, g: 255, b: 255, a: 50),
      borderColor: Color(r: 255, g: 255, b: 255, a: 100),
      pulseSpeed: 3.0,
      visualStyle: avsFlames
    )

proc drawAuraEffect*(pos: Vector2f, config: AuraConfig, time: float32) =
  ## Unified aura drawing function that handles all visual styles
  let pulse = (sin(time * config.pulseSpeed) * 0.2 + 0.8).float32

  # Draw core glow (common to all auras)
  drawCircle(Vector2(x: pos.x, y: pos.y),
             config.radius * 0.3 * pulse, config.coreColor)

  # Draw style-specific visuals
  case config.visualStyle
  of avsFlames:
    # Fire aura: animated fire rings with gradient
    let flicker = (sin(time * 15.0) * 0.1 + 0.9).float32
    for ring in 1..5:
      let progress = ring.float32 / 5.0
      let ringRadius = config.radius * progress * pulse * flicker
      let alpha = uint8((60 - ring * 8).float32 * flicker)
      let redShift = uint8(255 - progress * 50)
      let greenShift = uint8(100 + progress * 50)
      drawCircleLines(pos.x.int32, pos.y.int32, ringRadius,
                     Color(r: redShift, g: greenShift, b: 0, a: alpha))

    # Rotating flame wisps
    for i in 0..7:
      let angle = time * 2.0 + i.float32 * PI / 4.0
      let dist = config.radius * 0.7 + sin(time * 3.0 + i.float32) * 15.0
      let x = pos.x + cos(angle) * dist
      let y = pos.y + sin(angle) * dist - abs(sin(time * 4.0 + i.float32)) * 8.0
      drawCircle(Vector2(x: x, y: y), 4 + sin(time * 5.0 + i.float32) * 2,
                Color(r: 255, g: 150, b: 50, a: 180))
      drawCircle(Vector2(x: x, y: y - 2), 2, Color(r: 255, g: 255, b: 100, a: 220))

  of avsLightning:
    # Lightning aura: electric arcs and bolts
    let crackle = (sin(time * 20.0) * 0.5 + 0.5).float32

    # Animated electric arcs
    for arc in 1..4:
      let arcRadius = config.radius * (arc.float32 / 4.0) * pulse
      let alpha = uint8((50 - arc * 8).float32 * (0.7 + crackle * 0.3))
      drawCircleLines(pos.x.int32, pos.y.int32, arcRadius,
                     Color(r: 150, g: 200, b: 255, a: alpha))

    # Lightning bolts shooting outward
    for i in 0..11:
      if (time * 10.0).int mod (i + 2) == 0:
        let angle = i.float32 * PI * 2.0 / 12.0 + time * 0.5
        let startDist = config.radius * 0.4
        let endDist = config.radius * 0.95
        let x1 = pos.x + cos(angle) * startDist
        let y1 = pos.y + sin(angle) * startDist
        let x2 = pos.x + cos(angle) * endDist
        let y2 = pos.y + sin(angle) * endDist

        # Jagged lightning effect
        var segments = 4
        var prevX = x1
        var prevY = y1
        for seg in 1..segments:
          let t = seg.float32 / segments.float32
          let nextX = x1 + (x2 - x1) * t + (if seg mod 2 == 0: -5.0 else: 5.0)
          let nextY = y1 + (y2 - y1) * t + (if seg mod 2 == 0: 5.0 else: -5.0)
          drawLine(Vector2(x: prevX, y: prevY), Vector2(x: nextX, y: nextY), 2,
                  Color(r: 200, g: 220, b: 255, a: 200))
          prevX = nextX
          prevY = nextY

  of avsPoison:
    # Poison aura: toxic cloud with floating bubbles
    let drift = time * 0.8

    # Multiple toxic cloud layers
    for ring in 1..4:
      let ringRadius = config.radius * (ring.float32 / 4.0) * pulse
      let alpha = uint8((50 - ring * 10))
      drawCircleLines(pos.x.int32, pos.y.int32, ringRadius,
                     Color(r: 100, g: 255, b: 100, a: alpha))

    # Floating toxic bubbles rising
    for i in 0..15:
      let angle = i.float32 * PI * 2.0 / 16.0
      let baseDist = config.radius * 0.6
      let floatOffset = sin(drift + i.float32 * 0.5) * 20.0
      let dist = baseDist + floatOffset
      let riseOffset = (time * 15.0 + i.float32 * 10.0) mod 30.0 - 15.0
      let x = pos.x + cos(angle) * dist
      let y = pos.y + sin(angle) * dist - riseOffset
      let bubbleSize = 3 + (i mod 3).float32

      drawCircle(Vector2(x: x, y: y), bubbleSize, Color(r: 120, g: 255, b: 120, a: 160))
      drawCircle(Vector2(x: x - 1, y: y - 1), bubbleSize * 0.4, Color(r: 180, g: 255, b: 180, a: 200))
      drawCircleLines(x.int32, y.int32, bubbleSize, Color(r: 80, g: 200, b: 80, a: 200))

  of avsWind:
    # Wind aura: swirling cyclone effect
    let rotationSpeed = time * 2.5
    let turbulence = sin(time * 3.0) * 0.1

    # Spiraling wind streams
    for ring in 1..4:
      let ringRadius = config.radius * (ring.float32 / 4.0)
      let spiralOffset = rotationSpeed * (1.0 + ring.float32 * 0.2)

      for streak in 0..15:
        let baseAngle = (streak.float32 / 16.0) * PI * 2.0 + spiralOffset
        let angleVariation = turbulence * sin(streak.float32 * 0.5)
        let angle = baseAngle + angleVariation

        let segments = 3
        for seg in 0..<segments:
          let segProgress = seg.float32 / segments.float32
          let startDist = ringRadius * (0.9 + segProgress * 0.1)
          let endDist = ringRadius * (0.95 + segProgress * 0.15)
          let angleOffset = 0.15 + segProgress * 0.1

          let x1 = pos.x + cos(angle) * startDist
          let y1 = pos.y + sin(angle) * startDist
          let x2 = pos.x + cos(angle + angleOffset) * endDist
          let y2 = pos.y + sin(angle + angleOffset) * endDist

          let alpha = uint8((50 - ring * 8 - seg * 5).float32)
          drawLine(Vector2(x: x1, y: y1), Vector2(x: x2, y: y2), 2,
                  Color(r: 200, g: 230, b: 255, a: alpha))

    # Floating air particles
    for i in 0..11:
      let angle = i.float32 * PI * 2.0 / 12.0 + rotationSpeed * 0.3
      let dist = config.radius * 0.7 + sin(time * 2.0 + i.float32) * 25.0
      let x = pos.x + cos(angle) * dist
      let y = pos.y + sin(angle) * dist
      drawCircle(Vector2(x: x, y: y), 2, Color(r: 220, g: 240, b: 255, a: 150))

  of avsArcane:
    # Arcane aura: orbiting runes and sparkles
    let runeRotation = time * 1.5

    # Pulsing arcane rings with gradient
    for ring in 1..5:
      let progress = ring.float32 / 5.0
      let ringRadius = config.radius * progress * pulse
      let alpha = uint8((55 - ring * 8).float32 * pulse)
      let colorShift = uint8(200 - progress * 50)
      drawCircleLines(pos.x.int32, pos.y.int32, ringRadius,
                     Color(r: colorShift, g: 100, b: 255, a: alpha))

    # Orbiting arcane runes
    for i in 0..11:
      let angle = i.float32 * PI * 2.0 / 12.0 + runeRotation
      let dist = config.radius * (0.85 + sin(time * 4.0 + angle) * 0.15)
      let x = pos.x + cos(angle) * dist
      let y = pos.y + sin(angle) * dist

      let runeSize = 4 + sin(time * 5.0 + i.float32) * 2
      drawCircle(Vector2(x: x, y: y), runeSize, Color(r: 220, g: 150, b: 255, a: 220))
      drawCircle(Vector2(x: x, y: y), runeSize * 1.5, Color(r: 200, g: 100, b: 255, a: 80))

    # Floating sparkles
    for i in 0..7:
      let angle = i.float32 * PI * 2.0 / 8.0 - runeRotation * 0.7
      let dist = config.radius * 0.5 + sin(time * 3.0 + i.float32) * 20.0
      let x = pos.x + cos(angle) * dist
      let y = pos.y + sin(angle) * dist
      let sparkleSize = 2 + (sin(time * 6.0 + i.float32) * 1.5)
      drawCircle(Vector2(x: x, y: y), sparkleSize.float32, Color(r: 255, g: 200, b: 255, a: 180))

  of avsBlood:
    # Blood aura: dripping blood and mist
    let heartbeat = abs(sin(time * 4.0))

    # Pulsing blood rings
    for ring in 1..4:
      let progress = ring.float32 / 4.0
      let ringRadius = config.radius * progress * pulse * (1.0 + heartbeat * 0.1)
      let alpha = uint8((60 - ring * 10).float32 * (0.8 + heartbeat * 0.2))
      let colorIntensity = uint8(255 - progress * 100)
      drawCircleLines(pos.x.int32, pos.y.int32, ringRadius,
                     Color(r: colorIntensity, g: 50, b: 50, a: alpha))

    # Floating blood droplets
    for i in 0..13:
      let angle = i.float32 * PI * 2.0 / 14.0 + time * 0.5
      let dist = config.radius * 0.65 + sin(time * 2.5 + i.float32) * 15.0
      let dropFall = (time * 25.0 + i.float32 * 5.0) mod 40.0
      let x = pos.x + cos(angle) * dist
      let y = pos.y + sin(angle) * dist + dropFall - 20.0

      let dropSize = 4 - (dropFall / 20.0)
      if dropSize > 1.0:
        drawCircle(Vector2(x: x, y: y), dropSize.float32, Color(r: 200, g: 50, b: 50, a: 200))
        drawCircle(Vector2(x: x, y: y + 1), dropSize.float32 * 0.7, Color(r: 150, g: 30, b: 30, a: 200))

    # Swirling blood mist particles
    for i in 0..9:
      let angle = i.float32 * PI * 2.0 / 10.0 - time * 1.2
      let dist = config.radius * 0.8 + sin(time * 3.0 + i.float32) * 20.0
      let x = pos.x + cos(angle) * dist
      let y = pos.y + sin(angle) * dist
      drawCircle(Vector2(x: x, y: y), 3, Color(r: 255, g: 80, b: 80, a: 140))

    # Lifesteal heart symbols
    for corner in 0..3:
      let angle = corner.float32 * PI / 2.0 + PI / 4.0
      let dist = config.radius * 0.4
      let x = pos.x + cos(angle) * dist
      let y = pos.y + sin(angle) * dist
      let heartSize = 3 + heartbeat * 2

      drawCircle(Vector2(x: x - heartSize, y: y), heartSize, Color(r: 255, g: 100, b: 100, a: 180))
      drawCircle(Vector2(x: x + heartSize, y: y), heartSize, Color(r: 255, g: 100, b: 100, a: 180))
      drawCircle(Vector2(x: x, y: y + heartSize), heartSize * 1.2, Color(r: 255, g: 100, b: 100, a: 180))

  # Draw outer border, 2 passes: soft outer glow, then solid ring at exact radius
  let br = config.borderColor.r
  let bg = config.borderColor.g
  let bb = config.borderColor.b
  # Pass 1: wide soft glow halo outside the ring
  drawCircleLines(pos.x.int32, pos.y.int32, config.radius + 4.0,
                 Color(r: br, g: bg, b: bb, a: 55))
  drawCircleLines(pos.x.int32, pos.y.int32, config.radius + 2.0,
                 Color(r: br, g: bg, b: bb, a: 90))
  # Pass 2: solid bright ring at exact radius
  drawCircleLines(pos.x.int32, pos.y.int32, config.radius,
                 Color(r: br, g: bg, b: bb, a: 220))

