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

const
  AuraWaveTravelTime* = 0.32'f32
    ## How long a pulse takes to travel from the player out to the aura border.
    ## Must stay well under the shortest pulse interval (~0.59s for a mastered
    ## level-3 arcane aura) so a wave always lands before the next one launches.
  AuraWaveAfterglow* = 0.18'f32
    ## How long the border stays lit after a wave arrives on it
  AuraFlashDuration* = AuraWaveTravelTime + AuraWaveAfterglow
    ## Total life of one pulse's visuals: the outbound travel plus the border
    ## afterglow. The renderer splits a single 1->0 timer back into those phases,
    ## so no extra per-slot state is needed on the player.

proc getAuraRadius*(level: int): float32 =
  ## Standard aura radius band based on level (before the per-aura share below).
  ## Chosen so that even the tightest aura's share beats the old flat
  ## 187.5/250/312.5 radii - every aura gained range, none lost it.
  case level
  of 1: 250.0
  of 2: 325.0
  else: 400.0

proc auraSlotOf*(auraType: PowerUpType): AuraSlot =
  ## Maps an aura power-up to its pulse-timer slot on the player
  case auraType
  of puFireAura: asFire
  of puLightningAura: asLightning
  of puPoisonAura: asPoison
  of puWindAura: asWind
  of puArcaneAura: asArcane
  of puBloodAura: asBlood
  else: asSlow

proc auraWaveEase*(travel: float32): float32 =
  ## Shape of the wavefront's outward run: fast off the player, settling into
  ## the border. Shared by the hit test and the renderer, so what sweeps an
  ## enemy is exactly the ring the player saw arrive - same contract as
  ## getAuraRadiusFor for the border itself.
  let t = clamp(travel, 0.0'f32, 1.0'f32)
  1.0'f32 - pow(1.0'f32 - t, 1.8'f32)

proc auraWaveFrontRadius*(elapsed, maxRadius: float32): float32 =
  ## Where this pulse's wavefront is, `elapsed` seconds after it launched.
  maxRadius * auraWaveEase(elapsed / AuraWaveTravelTime)

proc auraWaveAlreadyHit*(player: Player, enemy: Enemy, slot: AuraSlot): bool =
  ## Whether the current pulse of `slot` has already spent itself on this enemy
  enemy.auraWaveHitSeq[slot] == player.auraPulseSeq[slot]

proc markAuraWaveHit*(player: Player, enemy: Enemy, slot: AuraSlot) =
  ## Consume this enemy for the current pulse of `slot` so nothing else in the
  ## same wave can hit it again (chain lightning uses this on its chain targets).
  enemy.auraWaveHitSeq[slot] = player.auraPulseSeq[slot]

proc auraWaveCatches*(player: Player, enemy: Enemy, slot: AuraSlot,
                      frontRadius: float32): bool =
  ## True the first frame this pulse's wavefront has reached `enemy`, and never
  ## again for the same pulse. The per-enemy mark is what makes that guarantee
  ## hold even when the enemy moves: the front is only ~35 px/s as it settles
  ## into the rim, so a wind gust's knockback would otherwise shove an enemy
  ## back out through it and be hit over and over by a single gust.
  if enemy.auraWaveHitSeq[slot] == player.auraPulseSeq[slot]: return false
  let dx = player.pos.x - enemy.pos.x
  let dy = player.pos.y - enemy.pos.y
  if dx * dx + dy * dy > frontRadius * frontRadius: return false
  enemy.auraWaveHitSeq[slot] = player.auraPulseSeq[slot]
  true

proc getAuraRangeMult*(auraType: PowerUpType): float32 =
  ## Each aura takes a different share of the radius band so a player running
  ## several auras sees distinct concentric rings instead of one thick blob.
  ## Ordering is by role: control auras reach furthest, burst damage least.
  case auraType
  of puSlowField: 1.15
  of puWindAura: 1.08
  of puPoisonAura: 1.01
  of puFireAura: 0.95
  of puLightningAura: 0.89
  of puBloodAura: 0.84
  of puArcaneAura: 0.80
  else: 1.0

proc getAuraRadiusFor*(auraType: PowerUpType, level: int): float32 =
  ## The single radius used by BOTH the gameplay hit test and the drawn border,
  ## so the ring the player sees is exactly the ring that hits.
  getAuraRadius(level) * getAuraRangeMult(auraType)

proc getAuraPulseInterval*(auraType: PowerUpType, level: int, hasMastery: bool): float32 =
  ## Seconds between pulses. Base values are deliberately spread (not multiples
  ## of each other) so stacked auras drift apart instead of re-syncing.
  var base = case auraType
    of puSlowField: 2.0'f32
    of puFireAura: 1.7'f32
    of puLightningAura: 1.3'f32
    of puPoisonAura: 2.3'f32
    of puWindAura: 3.0'f32
    of puArcaneAura: 1.1'f32
    of puBloodAura: 2.6'f32
    else: 2.0'f32
  base *= (case level
    of 1: 1.0'f32
    of 2: 0.85'f32
    else: 0.72'f32)
  if hasMastery:
    base *= 0.75  # mastery makes the aura beat faster, not just hit harder
  result = base

proc auraPhaseOffset*(slot: AuraSlot): float32 =
  ## Fraction of the first cycle an aura waits before its very first pulse.
  ## Without this, picking up three auras in one shop visit would leave them
  ## firing on the same frame forever.
  (ord(slot).float32 + 0.5) / (ord(AuraSlot.high).float32 + 1.5)

proc getAuraPulseColor*(auraType: PowerUpType): Color =
  ## Ring/particle color for an aura's pulse (AuraConfig fields stay private)
  case auraType
  of puSlowField: Color(r: 140, g: 190, b: 255, a: 255)
  of puFireAura: Color(r: 255, g: 130, b: 40, a: 255)
  of puLightningAura: Color(r: 170, g: 215, b: 255, a: 255)
  of puPoisonAura: Color(r: 120, g: 255, b: 120, a: 255)
  of puWindAura: Color(r: 200, g: 235, b: 255, a: 255)
  of puArcaneAura: Color(r: 210, g: 120, b: 255, a: 255)
  of puBloodAura: Color(r: 235, g: 60, b: 60, a: 255)
  else: White

# Aura configurations for each power-up type
proc getAuraConfig*(auraType: PowerUpType, level: int): AuraConfig =
  let radius = getAuraRadiusFor(auraType, level)

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

proc drawAuraWave(pos: Vector2f, config: AuraConfig, time: float32, travel: float32) =
  ## One outbound pulse: a wavefront that leaves the player and expands until it
  ## lands exactly on the aura border at travel == 1. `travel` is normalized
  ## progress, eased out so the wave launches fast and settles into the rim.
  ## Every style dresses the same moving circle differently, so a player running
  ## several auras can tell which one just fired by the shape of the wave alone.
  let r = config.radius * auraWaveEase(travel)
  if r < 4.0: return

  let br = config.borderColor.r
  let bg = config.borderColor.g
  let bb = config.borderColor.b
  # Bright on launch, easing off just enough that the arrival flash still reads
  # as the loudest moment of the beat.
  let strength = 1.0'f32 - 0.30'f32 * travel
  # NOTE: the parameter must not be called `a` - a template parameter with the
  # same name as a Color field gets substituted into the `a:` field label too.
  template edgeColor(alphaVal: float32): Color =
    Color(r: br, g: bg, b: bb,
          a: uint8(clamp(alphaVal * strength, 0.0'f32, 255.0'f32)))

  # Trailing wash between the wave and the ground it already covered. This is
  # what makes it read as a wave sweeping the field rather than a growing circle.
  let innerTrail = max(0.0'f32, r - 26.0'f32 - config.radius * 0.06'f32)
  drawRing(Vector2(x: pos.x, y: pos.y), innerTrail, r, 0.0, 360.0, 64,
           edgeColor(46.0'f32 * (1.0'f32 - travel * 0.5'f32)))

  # Core of the wavefront: three tight rings so the leading edge has weight.
  drawCircleLines(pos.x.int32, pos.y.int32, r, edgeColor(235.0))
  drawCircleLines(pos.x.int32, pos.y.int32, r - 2.0, edgeColor(170.0))
  drawCircleLines(pos.x.int32, pos.y.int32, r - 5.0, edgeColor(90.0))

  # Decoration count scales with circumference so the crest never looks sparse
  # at level 3 nor clogged in the first few frames after launch.
  let n = clamp(int(r / 20.0), 8, 44)

  case config.visualStyle
  of avsFlames:
    # Licking flame crest riding the front
    for i in 0..<n:
      let angle = i.float32 * PI * 2.0 / n.float32
      let flick = sin(time * 18.0 + i.float32 * 1.7) * 0.5 + 0.5
      let fx = pos.x + cos(angle) * (r + flick * 4.0)
      let fy = pos.y + sin(angle) * (r + flick * 4.0)
      let size = 3.0 + flick * 3.5
      drawCircle(Vector2(x: fx, y: fy), size,
                 Color(r: 255, g: uint8(120 + flick * 90), b: 40,
                       a: uint8(200.0 * (1.0 - travel * 0.35))))
      drawCircle(Vector2(x: fx, y: fy - 1.5), size * 0.45,
                 Color(r: 255, g: 245, b: 160, a: uint8(220.0 * (1.0 - travel * 0.4))))

  of avsLightning:
    # Jagged crest: the front itself is the bolt
    var prev = Vector2(x: pos.x + r, y: pos.y)
    for i in 1..n:
      let angle = i.float32 * PI * 2.0 / n.float32
      let jag = (if i mod 2 == 0: 7.0'f32 else: -7.0'f32) *
                (0.6 + 0.4 * sin(time * 25.0 + i.float32))
      let px = pos.x + cos(angle) * (r + jag)
      let py = pos.y + sin(angle) * (r + jag)
      let cur = Vector2(x: px, y: py)
      drawLine(prev, cur, 2.5, Color(r: 220, g: 240, b: 255,
                                     a: uint8(230.0 * (1.0 - travel * 0.3))))
      prev = cur
    # Sparks thrown ahead of the front
    for i in 0..5:
      let angle = i.float32 * PI * 2.0 / 6.0 + time * 3.0
      let sx = pos.x + cos(angle) * (r + 9.0)
      let sy = pos.y + sin(angle) * (r + 9.0)
      drawCircle(Vector2(x: sx, y: sy), 2.5,
                 Color(r: 255, g: 255, b: 255, a: uint8(200.0 * (1.0 - travel))))

  of avsPoison:
    # Bubbling front: the wave boils outward
    for i in 0..<n:
      let angle = i.float32 * PI * 2.0 / n.float32
      let wob = sin(time * 6.0 + i.float32 * 0.9) * 5.0
      let bx = pos.x + cos(angle) * (r + wob)
      let by = pos.y + sin(angle) * (r + wob)
      let size = 3.0 + (i mod 3).float32 * 1.5
      drawCircle(Vector2(x: bx, y: by), size,
                 Color(r: 120, g: 245, b: 120, a: uint8(170.0 * (1.0 - travel * 0.4))))
      drawCircleLines(bx.int32, by.int32, size,
                      Color(r: 190, g: 255, b: 190, a: uint8(200.0 * (1.0 - travel * 0.4))))

  of avsWind:
    # Raked gust: short tangential streaks smeared along the front
    for i in 0..<n:
      let angle = i.float32 * PI * 2.0 / n.float32 + time * 0.8
      let x1 = pos.x + cos(angle) * (r - 6.0)
      let y1 = pos.y + sin(angle) * (r - 6.0)
      let x2 = pos.x + cos(angle + 0.16) * (r + 4.0)
      let y2 = pos.y + sin(angle + 0.16) * (r + 4.0)
      drawLine(Vector2(x: x1, y: y1), Vector2(x: x2, y: y2), 2.0,
               Color(r: 225, g: 245, b: 255, a: uint8(190.0 * (1.0 - travel * 0.35))))

  of avsArcane:
    # Rune band: glyph dots on the crest plus a phase-shifted echo ring
    for i in 0..<n:
      let angle = i.float32 * PI * 2.0 / n.float32 - time * 1.2
      let rx = pos.x + cos(angle) * r
      let ry = pos.y + sin(angle) * r
      let size = (if i mod 2 == 0: 3.5'f32 else: 2.0'f32)
      drawCircle(Vector2(x: rx, y: ry), size,
                 Color(r: 235, g: 175, b: 255, a: uint8(215.0 * (1.0 - travel * 0.3))))
      drawCircle(Vector2(x: rx, y: ry), size * 2.0,
                 Color(r: 200, g: 100, b: 255, a: uint8(70.0 * (1.0 - travel * 0.5))))
    let echoR = config.radius * auraWaveEase(max(0.0'f32, travel - 0.18'f32))
    if echoR > 4.0:
      drawCircleLines(pos.x.int32, pos.y.int32, echoR,
                      Color(r: 210, g: 130, b: 255, a: uint8(110.0 * (1.0 - travel))))

  of avsBlood:
    # Splatter front: droplets flung outward, tails pointing back at the player
    for i in 0..<n:
      let angle = i.float32 * PI * 2.0 / n.float32
      let jitter = sin(time * 5.0 + i.float32 * 2.1) * 4.0
      let dx = pos.x + cos(angle) * (r + jitter)
      let dy = pos.y + sin(angle) * (r + jitter)
      let size = 3.0 + (i mod 2).float32 * 1.5
      drawCircle(Vector2(x: dx, y: dy), size,
                 Color(r: 215, g: 45, b: 45, a: uint8(210.0 * (1.0 - travel * 0.35))))
      drawCircle(Vector2(x: dx - cos(angle) * size, y: dy - sin(angle) * size), size * 0.55,
                 Color(r: 150, g: 25, b: 25, a: uint8(180.0 * (1.0 - travel * 0.35))))

proc drawAuraEffect*(pos: Vector2f, config: AuraConfig, time: float32,
                     charge: float32 = 1.0, flash: float32 = 0.0) =
  ## Unified aura drawing function that handles all visual styles.
  ## `charge` is progress toward the next pulse (0..1), drawn as a sweep along
  ## the border; `flash` (1 -> 0) is the single timer covering one whole pulse.
  ##
  ## That timer is split back into three phases here: an instant core kick at the
  ## player, the outbound wave travelling to the border, and the border afterglow
  ## once the wave lands. The ambient body of the aura deliberately does NOT
  ## breathe with the timer - the travelling wave is the only thing that moves
  ## with the beat, so what the player reads is a pulse leaving them, not a
  ## circle changing size.
  let pulse = (sin(time * config.pulseSpeed) * 0.2 + 0.8).float32
  let elapsed = (1.0'f32 - clamp(flash, 0.0'f32, 1.0'f32)) * AuraFlashDuration
  let travel = clamp(elapsed / AuraWaveTravelTime, 0.0'f32, 1.0'f32)
  let waveActive = flash > 0.001 and travel < 1.0
  let impact =
    if elapsed <= AuraWaveTravelTime: 0.0'f32
    else: clamp(1.0'f32 - (elapsed - AuraWaveTravelTime) / AuraWaveAfterglow,
                0.0'f32, 1.0'f32)
  # Short kick at the origin the moment the pulse fires - the "launch", not a
  # sustained bloom, so it stays visually attached to the outgoing wave.
  let burst = (if flash > 0.001: clamp(1.0'f32 - elapsed / 0.15'f32, 0.0'f32, 1.0'f32)
               else: 0.0'f32)

  # Draw core glow (common to all auras); firing briefly kicks it
  let coreAlpha = uint8(min(255.0'f32, config.coreColor.a.float32 * (1.0 + burst * 2.0)))
  drawCircle(Vector2(x: pos.x, y: pos.y),
             config.radius * 0.3 * pulse * (1.0 + burst * 0.35),
             Color(r: config.coreColor.r, g: config.coreColor.g,
                   b: config.coreColor.b, a: coreAlpha))

  # Draw style-specific visuals
  case config.visualStyle
  of avsFlames:
    # Fire aura: rotating flame wisps. The old breathing concentric rings are
    # gone - a pulse is a wave that leaves, not a circle that swells.
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

  # Pass 3: charge sweep just inside the border - a clock hand filling up to the
  # next pulse. This is what lets a player read several stacked auras at once:
  # each ring is at its own radius and fills at its own rate.
  let clamped = clamp(charge, 0.0'f32, 1.0'f32)
  if clamped > 0.001:
    drawRing(Vector2(x: pos.x, y: pos.y), config.radius - 6.0, config.radius - 1.5,
             -90.0, -90.0 + 360.0 * clamped, 48,
             Color(r: br, g: bg, b: bb, a: uint8(90 + 70.0 * clamped)))

  # Pass 4: the pulse itself, travelling from the player out to the border
  if waveActive:
    drawAuraWave(pos, config, time, travel)

  # Pass 5: impact - the wave has reached the rim, so the border lights up and
  # kicks slightly outward. This lands at the END of the travel, not at the
  # start, which is what sells the wave as having actually gone somewhere.
  if impact > 0.001:
    drawCircleLines(pos.x.int32, pos.y.int32, config.radius * (1.0 + 0.05 * impact),
                   Color(r: 255, g: 255, b: 255, a: uint8(min(200.0'f32, 200.0'f32 * impact))))
    drawCircleLines(pos.x.int32, pos.y.int32, config.radius,
                   Color(r: br, g: bg, b: bb, a: uint8(min(255.0'f32, 255.0'f32 * impact))))
    drawCircleLines(pos.x.int32, pos.y.int32, config.radius - 3.0,
                   Color(r: br, g: bg, b: bb, a: uint8(min(180.0'f32, 180.0'f32 * impact))))

