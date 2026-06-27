## Shared Cinematic Rendering
## Shot-agnostic helpers used by both the opening lore cinematic (`lore_cinematic.nim`)
## and the endgame cinematic (`endgame_cinematic.nim`): easing/colour maths, the
## equipped player / kernel / bullet / enemy / boss models, subtitles, the VHS
## recorder chrome (scanlines, letterbox, skip-hold box) and the tape-change burst.
## Keeping these here means both cinematics render the exact same models and chrome,
## so the outro reads as a sibling of the intro.

import raylib, rlgl, math, strutils
import particle_types
import background_fx, ../types, ../settings, ../save_system, ../skins, ../shapes,
       ../bullet_skins, ../bullet_shapes, ../enemy, ../enemy_config, icon_drawing

# ---------------------------------------------------------------------------
# Maths / colour helpers

proc clamp01*(v: float32): float32 =
  clamp(v, 0.0'f32, 1.0'f32)

proc easeInOut*(t: float32): float32 =
  let x = clamp01(t)
  x * x * (3.0'f32 - 2.0'f32 * x)

proc easeOut*(t: float32): float32 =
  let x = clamp01(t)
  1.0'f32 - pow(1.0'f32 - x, 3.0'f32)

proc alphaByte*(v: float32): uint8 = clampByteF(v)  # delegate to utils.clampByteF

proc fractCoord*(value: float32): float32 =
  value - floor(value).float32

proc colorA*(color: Color, alpha: float32): Color = withAlpha(color, alpha)  # delegate to utils.withAlpha

# ---------------------------------------------------------------------------
# Equipped cosmetics (mirrors what the player has selected in the shop)

proc equippedSkin*(): SkinType =
  if globalSettings.isNil:
    skDefault
  else:
    SkinType(clamp(globalSettings.playerSkin, ord(low(SkinType)), ord(high(SkinType))))

proc equippedShape*(): ShapeType =
  if globalSettings.isNil:
    shHexagon
  else:
    ShapeType(clamp(globalSettings.playerShape, ord(low(ShapeType)), ord(high(ShapeType))))

proc equippedBulletSkin*(): BulletSkinType =
  if globalSettings.isNil:
    bskDefault
  else:
    BulletSkinType(clamp(globalSettings.bulletSkin, ord(low(BulletSkinType)), ord(high(BulletSkinType))))

proc equippedBulletShape*(): BulletShapeType =
  if globalSettings.isNil:
    bshCircle
  else:
    BulletShapeType(clamp(globalSettings.bulletShape, ord(low(BulletShapeType)), ord(high(BulletShapeType))))

proc drawEquippedPlayerModel*(pos: Vector2f, radius: float32, time: float32,
                             alpha: float32 = 1.0'f32, glowBoost: float32 = 0.0'f32) =
  let pulse = sin(time * 2.0'f32) * 0.5'f32 + 0.5'f32
  let rotation = time * 0.5'f32
  let (primary, secondary, core) = getSkinColors(equippedSkin(), time)
  drawPlayerShape(pos, radius, equippedShape(),
                  colorA(primary, alpha * primary.a.float32),
                  colorA(secondary, alpha * secondary.a.float32),
                  colorA(core, alpha * core.a.float32),
                  time, rotation, pulse, 0.4'f32 + pulse * 0.2'f32 + glowBoost)

proc drawKernelModel*(pos: Vector2f, radius: float32, time: float32,
                     boot: float32, alpha: float32 = 1.0'f32) =
  ## The TOPHAT kernel itself: a hexagonal core wrapped in counter-rotating
  ## containment arcs. `boot` (0..1) drives the wake-up, the shell scales in,
  ## the core lens charges, and the tophat drops on as the final stage.
  let center = Vector2(x: pos.x, y: pos.y)
  let pulse = sin(time * 2.6'f32) * 0.5'f32 + 0.5'f32
  let r = radius * (0.7'f32 + boot * 0.3'f32)
  let spin = time * 12.0'f32

  # Counter-rotating containment arcs around the shell.
  for ring in 0..<3:
    let rr = r * (1.55'f32 + ring.float32 * 0.4'f32)
    let dir = if ring mod 2 == 0: 1.0'f32 else: -1.0'f32
    let base = time * dir * (30.0'f32 + ring.float32 * 16.0'f32)
    let arcAlpha = alpha * boot * (130.0'f32 - ring.float32 * 30.0'f32)
    for seg in 0..<3:
      let start = base + seg.float32 * 120.0'f32
      drawRing(center, rr - 1.5'f32, rr + 1.5'f32, start, start + 62.0'f32, 24,
               Color(r: 0, g: 215, b: 230, a: alphaByte(arcAlpha)))

  # Hexagonal shell with a slow spin; the hat stays upright on top.
  drawPoly(center, 6, r, spin, Color(r: 8, g: 20, b: 28, a: alphaByte(alpha * 240.0'f32)))
  drawPolyLines(center, 6, r, spin,
                Color(r: 0, g: 225, b: 230, a: alphaByte(alpha * 230.0'f32)))
  drawPolyLines(center, 6, r * 0.66'f32, -spin * 1.7'f32,
                Color(r: 0, g: 170, b: 190, a: alphaByte(alpha * 150.0'f32)))

  # Spokes from the shell vertices into the core.
  for i in 0..<6:
    let a = degToRad(spin) + i.float32 * PI / 3.0'f32
    drawLine(Vector2(x: pos.x + cos(a) * r * 0.4'f32, y: pos.y + sin(a) * r * 0.4'f32),
             Vector2(x: pos.x + cos(a) * r, y: pos.y + sin(a) * r), 1.5'f32,
             Color(r: 0, g: 160, b: 180, a: alphaByte(alpha * 90.0'f32)))

  # Core lens: charges with boot, breathes once awake.
  let coreR = r * 0.34'f32 * (0.55'f32 + boot * 0.45'f32) * (0.92'f32 + pulse * 0.08'f32)
  drawSoftGlow(pos.x, pos.y, coreR * 3.2'f32,
               Color(r: 0, g: 240, b: 230, a: alphaByte(alpha * boot * 60.0'f32)), 1.0'f32)
  drawCircle(center, coreR, Color(r: 0, g: 235, b: 225, a: alphaByte(alpha * 235.0'f32)))
  drawCircle(center, coreR * 0.55'f32,
             Color(r: 235, g: 255, b: 255, a: alphaByte(alpha * (140.0'f32 + boot * 110.0'f32))))

  # The tophat drops on as the final stage of the wake-up.
  let hatT = easeOut(clamp01((boot - 0.45'f32) / 0.45'f32))
  if hatT > 0.0'f32:
    let hatPos = newVector2f(pos.x, pos.y - (1.0'f32 - hatT) * r * 3.2'f32)
    drawTopHat(hatPos, r, time, alpha * hatT)

proc drawEquippedBulletModel*(pos: Vector2f, radius: float32, travelAngle: float32,
                             time: float32, alpha: float32 = 1.0'f32) =
  let (primary, glow, trail) = getBulletSkinColors(equippedBulletSkin(), time)
  for i in 1..4:
    let tx = pos.x - cos(travelAngle) * i.float32 * radius * 1.45'f32
    let ty = pos.y - sin(travelAngle) * i.float32 * radius * 1.45'f32
    let trailAlpha = alpha * trail.a.float32 * (1.0'f32 - i.float32 * 0.18'f32)
    drawCircle(Vector2(x: tx, y: ty), radius * (1.0'f32 - i.float32 * 0.12'f32),
               colorA(trail, trailAlpha))
  drawPlayerBulletShape(pos, radius, equippedBulletShape(), travelAngle,
                        colorA(primary, alpha * primary.a.float32),
                        colorA(glow, alpha * glow.a.float32))

proc cinematicEnemy*(enemyType: EnemyType, x, y: float32, difficulty: float32 = 12.0'f32,
                    id: int = 0, threat: int = 0): Enemy =
  var dummyGame = Game(nextEnemyId: id)
  result = newEnemy(x, y, difficulty, enemyType, dummyGame)
  result.id = id
  result.pos = newVector2f(x, y)
  result.targetPos = result.pos
  result.startPos = result.pos
  result.hasEnteredScreen = true
  result.spawnTimer = 0
  result.entranceTimer = 0
  result.threatLevel = threat

proc drawRealEnemy*(enemyType: EnemyType, x, y, radius, time: float32,
                   id: int = 0, threat: int = 0, vel: Vector2f = newVector2f(0, 0)) =
  let config = getEnemyConfig(enemyType)
  let e = cinematicEnemy(enemyType, x, y, 18.0'f32, id, threat)
  e.radius = radius
  e.collisionRadius = radius * 0.4'f32
  e.color = config.baseColor
  e.vel = vel
  e.dashCooldown = if enemyType in {etTriangle, etStar}: 0.25'f32 + abs(sin(time + id.float32)) * 0.25'f32 else: e.dashCooldown
  e.dashTimer = if enemyType == etTriangle: 0.35'f32 else: e.dashTimer
  drawEnemy(e)

proc drawRealBossModel*(x, y, radius, time: float32, screenWidth, screenHeight: int32,
                        hpFraction: float32 = 0.16'f32, phaseIndex: int = 3) =
  let boss = spawnBoss(screenWidth, screenHeight, 25.0'f32, 12, 60)
  boss.pos = newVector2f(x, y)
  boss.targetPos = boss.pos
  boss.startPos = boss.pos
  boss.radius = radius
  boss.collisionRadius = radius * 0.4'f32
  boss.hp = boss.maxHp * clamp(hpFraction, 0.001'f32, 1.0'f32)
  boss.currentPhaseIndex = phaseIndex
  boss.entranceTimer = 0
  boss.spawnTimer = 0
  drawEnemy(boss)

# ---------------------------------------------------------------------------
# Text / atmosphere

proc drawCenteredText*(text: string, x, y: int32, size: int32, color: Color) =
  let w = measureText(text, size)
  drawText(text, x - w div 2, y, size, color)

proc drawSubtitles*(lines: openArray[string], screenWidth, screenHeight: int32,
                   alpha: float32) =
  let baseY = screenHeight - screenHeight div 9 - 76
  for i, line in lines:
    let size = if i == 0: 22.int32 else: 17.int32
    let color =
      if i == 0:
        Color(r: 250, g: 255, b: 255, a: alphaByte(alpha * 245.0'f32))
      else:
        Color(r: 0, g: 225, b: 225, a: alphaByte(alpha * 210.0'f32))
    drawCenteredText(line, screenWidth div 2, baseY + i.int32 * 27, size, color)

proc drawFilmGrain*(screenWidth, screenHeight: int32, time: float32, alpha: float32) =
  var i = 0
  while i < 150:
    let seed = i.float32 * 19.31'f32 + floor(time * 18.0'f32) * 7.13'f32
    let x = (fractCoord(sin(seed) * 43758.5453'f32) * screenWidth.float32).int32
    let y = (fractCoord(sin(seed + 12.7'f32) * 24634.6345'f32) * screenHeight.float32).int32
    let a = alphaByte(alpha * (0.35'f32 + fractCoord(sin(seed + 91.0'f32) * 91.3'f32)))
    drawRectangle(x, y, 1, 1, Color(r: 255, g: 255, b: 255, a: a))
    inc i

proc drawDataRain*(screenWidth, screenHeight: int32, time, intensity: float32,
                   color: Color = Color(r: 0, g: 235, b: 210, a: 255)) =
  var col = 0
  while col < screenWidth div 18 + 2:
    let x = (col * 18).int32 + int32(sin(col.float32 * 3.7'f32) * 4.0'f32)
    let speed = 55.0'f32 + (col mod 7).float32 * 18.0'f32
    let y = ((time * speed + col.float32 * 47.0'f32) mod (screenHeight.float32 + 140.0'f32)) - 120.0'f32
    let alpha = alphaByte(intensity * (55.0'f32 + (col mod 5).float32 * 24.0'f32))
    let digit = if (col + time.int) mod 2 == 0: "1" else: "0"
    drawText(digit, x, y.int32, 14, Color(r: color.r, g: color.g, b: color.b, a: alpha))
    if col mod 5 == 0:
      drawRectangle(x, (y + 20.0'f32).int32, 2, 46,
                    Color(r: color.r, g: color.g, b: color.b, a: alphaByte(intensity * 24.0'f32)))
    inc col

proc drawTapeChange*(screenWidth, screenHeight: int32, local: float32,
                    frame: int, time: float32) =
  ## Brief VHS "channel switch" burst at the start of each shot. Transient by
  ## design (~0.18s) so it punctuates cuts without fighting the scene or subtitles.
  const window = 0.18'f32
  if local >= window:
    return
  let intensity = 1.0'f32 - local / window

  # Displaced static bands with alternating chroma tint.
  for i in 0..<7:
    let seed = i.float32 * 23.7'f32 + floor(time * 60.0'f32)
    let y = (fractCoord(sin(seed) * 43758.5453'f32) * screenHeight.float32).int32
    let h = (3 + (frame + i * 13) mod 14).int32
    let tint =
      if i mod 2 == 0:
        Color(r: 0, g: 235, b: 235, a: alphaByte(intensity * 120.0'f32))
      else:
        Color(r: 255, g: 40, b: 200, a: alphaByte(intensity * 110.0'f32))
    drawRectangle(0, y, screenWidth, h, tint)

  # Bright roll bar sweeping down fast.
  let rollY = (fractCoord(local * 6.0'f32) * screenHeight.float32).int32
  drawRectangle(0, rollY, screenWidth, 2, Color(r: 255, g: 255, b: 255, a: alphaByte(intensity * 180.0'f32)))
  # Quick whole-frame flash on the hardest part of the cut.
  drawRectangle(0, 0, screenWidth, screenHeight,
                Color(r: 210, g: 245, b: 245, a: alphaByte(intensity * intensity * 60.0'f32)))

# ---------------------------------------------------------------------------
# Recorder chrome (the "playback feed" UI around the scene)

proc drawCinematicOverlay*(screenWidth, screenHeight: int32,
                           time: float32, frame: int, scanlineOffset: float32,
                           fastForwardActive: bool,
                           skipHoldTimer, skipHoldRequired, totalDuration: float32,
                           shotLabel, liveText, controlsText, controlsActiveText: string,
                           iconIndex: int, glitchHot: bool,
                           accent: Color = Color(r: 0, g: 230, b: 230, a: 255)) =
  ## The full VHS recorder UI: scanlines, tracking glitches, letterbox bars,
  ## shot label + LIVE marker, scrub bar, fast-forward hint, and the hold-to-skip
  ## box. `accent` tints the active chrome so each cinematic can carry its own
  ## colour (cyan for the intro, restored-green for the outro).
  # Rolling scanlines.
  let scanCount = screenHeight div 3
  for i in 0..<scanCount:
    let y = ((i.float32 * 3.0'f32 + scanlineOffset) mod screenHeight.float32).int32
    drawRectangle(0, y, screenWidth, 1, Color(r: 0, g: 0, b: 0, a: 24))

  # Analog tracking hits.
  if (frame mod 137) < 8 or glitchHot:
    let y = ((sin(time * 41.0'f32) * 0.5'f32 + 0.5'f32) * screenHeight.float32).int32
    let h = 8 + (frame mod 18)
    drawRectangle(0, y, screenWidth, h.int32, Color(r: 255, g: 30, b: 210, a: 34))
    drawRectangle(18, y + 3, screenWidth - 36, 2, Color(r: 0, g: 255, b: 255, a: 70))

  # Letterbox and recorder marks.
  let barH = screenHeight div 9
  drawRectangle(0, 0, screenWidth, barH, Black)
  drawRectangle(0, screenHeight - barH, screenWidth, barH, Black)

  drawShopIcon(24, 15, 22, iconIndex, Color(r: accent.r, g: accent.g, b: accent.b, a: 185))
  drawText(shotLabel, 54, 18, 14, Color(r: 160, g: 220, b: 220, a: 155))
  drawRectangle(screenWidth - 86, 23, 10, 10, Color(r: 255, g: 40, b: 60, a: 220))
  drawText(liveText, screenWidth - 70, 17, 16, Color(r: 255, g: 210, b: 220, a: 180))

  let progressX = 92.int32
  let progressY = screenHeight - barH div 2 + 1
  let progressW = screenWidth - 184.int32
  drawRectangle(progressX, progressY, progressW, 2, Color(r: 60, g: 85, b: 100, a: 150))
  let cursorX = progressX + int32(progressW.float32 * clamp01(time / totalDuration))
  drawRectangle(progressX, progressY, cursorX - progressX, 2,
                Color(r: accent.r, g: accent.g, b: accent.b, a: 210))

  let controlText = if fastForwardActive: controlsActiveText else: controlsText
  drawCenteredText(controlText, screenWidth div 2, screenHeight - 34, 14,
                   Color(r: 145, g: 160, b: 170, a: alphaByte(80.0'f32 + sin(time * 4.0'f32) * 36.0'f32)))

  let skipBoxW = 156.int32
  let skipBoxH = 34.int32
  let skipBoxX = screenWidth - skipBoxW - 24
  let skipBoxY = screenHeight - skipBoxH - 20
  let skipRemainingSeconds = max(0.0'f32, skipHoldRequired - skipHoldTimer)
  let skipProgress = clamp01(skipHoldTimer / skipHoldRequired)
  let skipText = skipRemainingSeconds.formatFloat(ffDecimal, 1) & "s"
  drawRectangle(skipBoxX, skipBoxY, skipBoxW, skipBoxH, Color(r: 8, g: 12, b: 18, a: 190))
  drawRectangleLines(skipBoxX, skipBoxY, skipBoxW, skipBoxH, Color(r: 70, g: 120, b: 130, a: 185))
  drawText(skipText, skipBoxX + 14, skipBoxY + 8, 16,
           Color(r: 220, g: 240, b: 245, a: 215))
  let barX = skipBoxX + 70
  let barY = skipBoxY + 13
  let barW = skipBoxW - 80
  drawRectangle(barX, barY, barW, 8, Color(r: 25, g: 35, b: 45, a: 210))
  drawRectangle(barX, barY, int32(barW.float32 * skipProgress), 8,
                Color(r: accent.r, g: accent.g, b: accent.b, a: 225))
  drawRectangleLines(barX, barY, barW, 8, Color(r: 70, g: 120, b: 130, a: 190))

  drawFilmGrain(screenWidth, screenHeight, time, 24.0'f32)
