## Lore Cinematic Module
## First-open cinematic that plays once, between the boot splash and the OS desktop.
## The sequence is a raylib-rendered video: timed shots, camera drift, animated
## geometry, subtitles, scanlines, letterbox bars, and a final boot handoff.

import raylib, rlgl, math, strutils
import background_fx, ../types, ../settings, ../save_system, ../skins, ../shapes, ../bullet_skins, ../bullet_shapes, ../enemy, ../enemy_config, ../localization, ../sound, icon_drawing

type
  LoreShot* = enum
    lsBreach
    lsSwarm
    lsAwaken
    lsBoss
    lsCounterattack
    lsDirective

  LoreCinematic* = ref object
    time*: float32
    complete*: bool
    scanlineOffset*: float32
    frame*: int
    fastForwardActive*: bool
    skipHoldTimer*: float32
    lastShotPlayed*: int  # Index of the shot whose audio cue last fired (-1 = none)

const
  LoreFastForwardMultiplier = 2.0'f32
  LoreSkipHoldRequired = 3.0'f32
  ShotDurations = [
    5.60'f32, # breach
    5.95'f32, # swarm
    5.75'f32, # TOPHAT awakens
    6.45'f32, # boss signal
    5.65'f32, # counterattack
    4.80'f32  # directive
  ]
  LoreDuration =
    ShotDurations[0] + ShotDurations[1] + ShotDurations[2] +
    ShotDurations[3] + ShotDurations[4] + ShotDurations[5]

proc newLoreCinematic*(): LoreCinematic =
  LoreCinematic(
    time: 0,
    complete: false,
    scanlineOffset: 0,
    frame: 0,
    fastForwardActive: false,
    skipHoldTimer: 0,
    lastShotPlayed: -1
  )

proc clamp01(v: float32): float32 =
  clamp(v, 0.0'f32, 1.0'f32)

proc easeInOut(t: float32): float32 =
  let x = clamp01(t)
  x * x * (3.0'f32 - 2.0'f32 * x)

proc easeOut(t: float32): float32 =
  let x = clamp01(t)
  1.0'f32 - pow(1.0'f32 - x, 3.0'f32)

proc alphaByte(v: float32): uint8 =
  uint8(clamp(v, 0.0'f32, 255.0'f32))

proc fractCoord(value: float32): float32 =
  value - floor(value).float32

proc colorA(color: Color, alpha: float32): Color =
  Color(r: color.r, g: color.g, b: color.b, a: alphaByte(alpha))

proc equippedSkin(): SkinType =
  if globalSettings.isNil:
    skDefault
  else:
    SkinType(clamp(globalSettings.playerSkin, ord(low(SkinType)), ord(high(SkinType))))

proc equippedShape(): ShapeType =
  if globalSettings.isNil:
    shHexagon
  else:
    ShapeType(clamp(globalSettings.playerShape, ord(low(ShapeType)), ord(high(ShapeType))))

proc equippedBulletSkin(): BulletSkinType =
  if globalSettings.isNil:
    bskDefault
  else:
    BulletSkinType(clamp(globalSettings.bulletSkin, ord(low(BulletSkinType)), ord(high(BulletSkinType))))

proc equippedBulletShape(): BulletShapeType =
  if globalSettings.isNil:
    bshCircle
  else:
    BulletShapeType(clamp(globalSettings.bulletShape, ord(low(BulletShapeType)), ord(high(BulletShapeType))))

proc drawEquippedPlayerModel(pos: Vector2f, radius: float32, time: float32,
                             alpha: float32 = 1.0'f32, glowBoost: float32 = 0.0'f32) =
  let pulse = sin(time * 2.0'f32) * 0.5'f32 + 0.5'f32
  let rotation = time * 0.5'f32
  let (primary, secondary, core) = getSkinColors(equippedSkin(), time)
  drawPlayerShape(pos, radius, equippedShape(),
                  colorA(primary, alpha * primary.a.float32),
                  colorA(secondary, alpha * secondary.a.float32),
                  colorA(core, alpha * core.a.float32),
                  time, rotation, pulse, 0.4'f32 + pulse * 0.2'f32 + glowBoost)

proc drawKernelModel(pos: Vector2f, radius: float32, time: float32,
                     boot: float32, alpha: float32 = 1.0'f32) =
  ## The TOPHAT kernel itself: a hexagonal core wrapped in counter-rotating
  ## containment arcs. `boot` (0..1) drives the wake-up — the shell scales in,
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

proc drawEquippedBulletModel(pos: Vector2f, radius: float32, travelAngle: float32,
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

proc cinematicEnemy(enemyType: EnemyType, x, y: float32, difficulty: float32 = 12.0'f32,
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

proc drawRealEnemy(enemyType: EnemyType, x, y, radius, time: float32,
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

proc drawRealBossModel(x, y, radius, time: float32, screenWidth, screenHeight: int32) =
  let boss = spawnBoss(screenWidth, screenHeight, 25.0'f32, 12, 60)
  boss.pos = newVector2f(x, y)
  boss.targetPos = boss.pos
  boss.startPos = boss.pos
  boss.radius = radius
  boss.collisionRadius = radius * 0.4'f32
  boss.hp = boss.maxHp * (0.16'f32 + sin(time * 0.8'f32) * 0.03'f32)
  boss.currentPhaseIndex = 3
  boss.entranceTimer = 0
  boss.spawnTimer = 0
  drawEnemy(boss)

proc shotAt(time: float32): tuple[shot: LoreShot, local: float32, duration: float32] =
  var cursor = 0.0'f32
  for i, duration in ShotDurations:
    if time < cursor + duration:
      return (LoreShot(i), time - cursor, duration)
    cursor += duration
  (lsDirective, ShotDurations[^1], ShotDurations[^1])

proc shotFade(local, duration: float32): float32 =
  min(easeInOut(local / 1.35'f32), easeInOut((duration - local) / 1.55'f32))

proc drawCenteredText(text: string, x, y: int32, size: int32, color: Color) =
  let w = measureText(text, size)
  drawText(text, x - w div 2, y, size, color)

proc drawFilmGrain(screenWidth, screenHeight: int32, time: float32, alpha: float32) =
  var i = 0
  while i < 150:
    let seed = i.float32 * 19.31'f32 + floor(time * 18.0'f32) * 7.13'f32
    let x = (fractCoord(sin(seed) * 43758.5453'f32) * screenWidth.float32).int32
    let y = (fractCoord(sin(seed + 12.7'f32) * 24634.6345'f32) * screenHeight.float32).int32
    let a = alphaByte(alpha * (0.35'f32 + fractCoord(sin(seed + 91.0'f32) * 91.3'f32)))
    drawRectangle(x, y, 1, 1, Color(r: 255, g: 255, b: 255, a: a))
    inc i

proc drawVideoOverlay(lore: LoreCinematic, screenWidth, screenHeight: int32,
                      shot: LoreShot, local, duration: float32) =
  # Rolling scanlines.
  let scanCount = screenHeight div 3
  for i in 0..<scanCount:
    let y = ((i.float32 * 3.0'f32 + lore.scanlineOffset) mod screenHeight.float32).int32
    drawRectangle(0, y, screenWidth, 1, Color(r: 0, g: 0, b: 0, a: 24))

  # Analog tracking hits.
  let glitchPulse =
    if (lore.frame mod 137) < 8 or (shot == lsBoss and (lore.frame mod 63) < 5):
      1.0'f32
    else:
      0.0'f32
  if glitchPulse > 0.0:
    let y = ((sin(lore.time * 41.0'f32) * 0.5'f32 + 0.5'f32) * screenHeight.float32).int32
    let h = 8 + (lore.frame mod 18)
    drawRectangle(0, y, screenWidth, h.int32, Color(r: 255, g: 30, b: 210, a: 34))
    drawRectangle(18, y + 3, screenWidth - 36, 2, Color(r: 0, g: 255, b: 255, a: 70))

  # Letterbox and recorder marks.
  let barH = screenHeight div 9
  drawRectangle(0, 0, screenWidth, barH, Black)
  drawRectangle(0, screenHeight - barH, screenWidth, barH, Black)

  let shotLabel = case shot
    of lsBreach: t(tkLoreRecBreach)
    of lsSwarm: t(tkLoreRecSwarm)
    of lsAwaken: t(tkLoreRecAwaken)
    of lsBoss: t(tkLoreRecBoss)
    of lsCounterattack: t(tkLoreRecCounter)
    of lsDirective: t(tkLoreRecDirective)

  let iconIndex = case shot
    of lsBreach: 3
    of lsSwarm: 0
    of lsAwaken: 4
    of lsBoss: 7
    of lsCounterattack: 0
    of lsDirective: 10
  drawShopIcon(24, 15, 22, iconIndex, Color(r: 0, g: 225, b: 225, a: 185))
  drawText(shotLabel, 54, 18, 14, Color(r: 160, g: 220, b: 220, a: 155))
  drawRectangle(screenWidth - 86, 23, 10, 10, Color(r: 255, g: 40, b: 60, a: 220))
  drawText(t(tkLoreLive), screenWidth - 70, 17, 16, Color(r: 255, g: 210, b: 220, a: 180))

  let progressX = 92.int32
  let progressY = screenHeight - barH div 2 + 1
  let progressW = screenWidth - 184.int32
  drawRectangle(progressX, progressY, progressW, 2, Color(r: 60, g: 85, b: 100, a: 150))
  let cursorX = progressX + int32(progressW.float32 * clamp01(lore.time / LoreDuration))
  drawRectangle(progressX, progressY, cursorX - progressX, 2, Color(r: 0, g: 230, b: 230, a: 210))

  let controlText =
    if lore.fastForwardActive:
      t(tkLoreControlsFFActive)
    else:
      t(tkLoreControlsFF)
  drawCenteredText(controlText, screenWidth div 2, screenHeight - 34, 14,
                   Color(r: 145, g: 160, b: 170, a: alphaByte(80.0'f32 + sin(lore.time * 4.0'f32) * 36.0'f32)))

  let skipBoxW = 156.int32
  let skipBoxH = 34.int32
  let skipBoxX = screenWidth - skipBoxW - 24
  let skipBoxY = screenHeight - skipBoxH - 20
  let skipRemainingSeconds = max(0.0'f32, LoreSkipHoldRequired - lore.skipHoldTimer)
  let skipProgress = clamp01(lore.skipHoldTimer / LoreSkipHoldRequired)
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
                Color(r: 0, g: 230, b: 230, a: 225))
  drawRectangleLines(barX, barY, barW, 8, Color(r: 70, g: 120, b: 130, a: 190))

  drawFilmGrain(screenWidth, screenHeight, lore.time, 24.0'f32)

proc drawSubtitles(lines: openArray[string], screenWidth, screenHeight: int32,
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

proc drawDataRain(screenWidth, screenHeight: int32, time, intensity: float32) =
  var col = 0
  while col < screenWidth div 18 + 2:
    let x = (col * 18).int32 + int32(sin(col.float32 * 3.7'f32) * 4.0'f32)
    let speed = 55.0'f32 + (col mod 7).float32 * 18.0'f32
    let y = ((time * speed + col.float32 * 47.0'f32) mod (screenHeight.float32 + 140.0'f32)) - 120.0'f32
    let alpha = alphaByte(intensity * (55.0'f32 + (col mod 5).float32 * 24.0'f32))
    let digit = if (col + time.int) mod 2 == 0: "1" else: "0"
    drawText(digit, x, y.int32, 14, Color(r: 0, g: 235, b: 210, a: alpha))
    if col mod 5 == 0:
      drawRectangle(x, (y + 20.0'f32).int32, 2, 46, Color(r: 0, g: 235, b: 210, a: alphaByte(intensity * 24.0'f32)))
    inc col

proc drawBreachShot(local, duration: float32, screenWidth, screenHeight: int32,
                    alpha: float32) =
  let cx = screenWidth.float32 * (0.5'f32 + sin(local * 0.55'f32) * 0.025'f32)
  let cy = screenHeight.float32 * 0.46'f32
  drawDataRain(screenWidth, screenHeight, local, alpha)

  let open = easeOut(local / duration)
  for i in 0..<8:
    let r = (24.0'f32 + i.float32 * 30.0'f32) * (0.45'f32 + open * 0.95'f32)
    let a = alpha * (150.0'f32 - i.float32 * 13.0'f32)
    drawCircleLines(Vector2(x: cx, y: cy), r + sin(local * 5.0'f32 + i.float32) * 4.0'f32,
                    Color(r: 255, g: 40, b: 190, a: alphaByte(a)))
  drawSoftGlow(cx, cy, 210.0'f32 * open, Color(r: 255, g: 20, b: 170, a: alphaByte(alpha * 95.0'f32)), 1.0'f32)
  drawRectangle((cx - 170.0'f32 * open).int32, (cy - 5.0'f32).int32,
                (340.0'f32 * open).int32, 10, Color(r: 255, g: 230, b: 255, a: alphaByte(alpha * 190.0'f32)))
  drawRectangle((cx - 5.0'f32).int32, (cy - 120.0'f32 * open).int32,
                10, (240.0'f32 * open).int32, Color(r: 0, g: 245, b: 245, a: alphaByte(alpha * 135.0'f32)))

  # The kernel — the OS core the breach is tearing into — trembles harder as
  # the rupture widens around it.
  let jx = sin(local * 43.0'f32) * 2.4'f32 * open
  let jy = cos(local * 51.0'f32) * 2.0'f32 * open
  drawKernelModel(newVector2f(cx + jx, cy + jy), 36.0'f32, local, 1.0'f32, alpha)
  # Corruption flicker crawling over the shell during breach spikes.
  let spike = sin(local * 9.0'f32)
  if spike > 0.55'f32:
    drawPolyLines(Vector2(x: cx + jx, y: cy + jy), 6, 36.0'f32, local * 12.0'f32,
                  Color(r: 255, g: 40, b: 190, a: alphaByte(alpha * (spike - 0.55'f32) * 380.0'f32)))

  drawSubtitles([t(tkLoreBreach1), t(tkLoreBreach2)], screenWidth, screenHeight, alpha)

proc drawSwarmShot(local, duration: float32, screenWidth, screenHeight: int32,
                   alpha: float32) =
  let centerY = screenHeight.float32 * 0.48'f32
  let rush = easeInOut(local / duration)
  for i in 0..<42:
    let lane = (i mod 9).float32
    let seed = i.float32 * 0.733'f32
    let side = if i mod 2 == 0: -1.0'f32 else: 1.0'f32
    let startX = if side < 0.0: -90.0'f32 - seed * 30.0'f32 else: screenWidth.float32 + 90.0'f32 + seed * 30.0'f32
    let targetX = screenWidth.float32 * (0.18'f32 + fractCoord(seed * 3.1'f32) * 0.64'f32)
    let x = startX + (targetX - startX) * easeOut(clamp01((local - seed * 0.12'f32) / (duration * 0.82'f32)))
    let y = centerY + (lane - 4.0'f32) * 42.0'f32 + sin(local * 2.2'f32 + seed) * 18.0'f32
    let sz = 9.0'f32 + (i mod 4).float32 * 3.0'f32 + rush * 6.0'f32
    let c =
      if i mod 3 == 0:
        Color(r: 255, g: 60, b: 120, a: alphaByte(alpha * 185.0'f32))
      elif i mod 3 == 1:
        Color(r: 255, g: 140, b: 45, a: alphaByte(alpha * 172.0'f32))
      else:
        Color(r: 190, g: 80, b: 255, a: alphaByte(alpha * 175.0'f32))
    drawLine((x - side * 42.0'f32).int32, y.int32, x.int32, y.int32,
             colorA(c, c.a.float32 * 0.34'f32))
    let enemyKind = case i mod 9
      of 0: etCircle
      of 1: etCube
      of 2: etTriangle
      of 3: etStar
      of 4: etCross
      of 5: etDiamond
      of 6: etOctagon
      of 7: etPentagon
      else: etHexagon
    drawRealEnemy(enemyKind, x, y, sz, local, i, if i mod 8 == 0: 2 else: 0,
                  newVector2f(side * -80.0'f32, sin(seed) * 45.0'f32))

  drawRectangleGradientH(0, 0, (screenWidth.float32 * rush * 0.35'f32).int32, screenHeight,
                         Color(r: 255, g: 20, b: 80, a: alphaByte(alpha * 60.0'f32)),
                         Color(r: 255, g: 20, b: 80, a: 0))
  drawRectangleGradientH(screenWidth - (screenWidth.float32 * rush * 0.35'f32).int32, 0,
                         (screenWidth.float32 * rush * 0.35'f32).int32, screenHeight,
                         Color(r: 255, g: 20, b: 80, a: 0),
                         Color(r: 255, g: 20, b: 80, a: alphaByte(alpha * 60.0'f32)))
  drawSubtitles([t(tkLoreSwarm1), t(tkLoreSwarm2)], screenWidth, screenHeight, alpha)

proc drawAwakenShot(local, duration: float32, screenWidth, screenHeight: int32,
                    alpha: float32) =
  let boot = easeOut(local / (duration * 0.55'f32))
  let x = screenWidth.float32 * 0.5'f32
  let y = screenHeight.float32 * (0.48'f32 - (1.0'f32 - boot) * 0.08'f32)
  drawSoftGlow(x, y, 220.0'f32 * boot, Color(r: 0, g: 220, b: 255, a: alphaByte(alpha * 52.0'f32)), 1.0'f32)
  for i in 0..<9:
    let a = local * 0.8'f32 + i.float32 * PI * 2.0'f32 / 9.0'f32
    let r = (86.0'f32 + sin(local * 3.0'f32 + i.float32) * 10.0'f32) * boot
    let px = x + cos(a) * r
    let py = y + sin(a) * r * 0.62'f32
    drawCircle(Vector2(x: px, y: py), 3.0'f32 + boot * 2.0'f32,
               Color(r: 0, g: 255, b: 220, a: alphaByte(alpha * 150.0'f32)))
    drawLine(x.int32, y.int32, px.int32, py.int32, Color(r: 0, g: 200, b: 220, a: alphaByte(alpha * 45.0'f32)))

  drawEquippedPlayerModel(newVector2f(x, y), 31.0'f32 * (0.65'f32 + boot * 0.35'f32),
                          local, alpha, 0.22'f32)
  drawSubtitles([t(tkLoreAwaken1), t(tkLoreAwaken2)], screenWidth, screenHeight, alpha)

proc drawBossShot(local, duration: float32, screenWidth, screenHeight: int32,
                  alpha: float32) =
  let reveal = easeOut(local / (duration * 0.72'f32))
  let cx = screenWidth.float32 * 0.5'f32
  let cy = screenHeight.float32 * 0.44'f32
  drawSoftGlow(cx, cy, 280.0'f32 * reveal, Color(r: 180, g: 0, b: 255, a: alphaByte(alpha * 65.0'f32)), 1.0'f32)
  for ring in 0..<5:
    let r = 70.0'f32 + ring.float32 * 42.0'f32 + sin(local * 2.2'f32 + ring.float32) * 7.0'f32
    drawCircleLines(Vector2(x: cx, y: cy), r * reveal,
                    Color(r: 230, g: 80, b: 255, a: alphaByte(alpha * (128.0'f32 - ring.float32 * 16.0'f32))))

  let bossR = 88.0'f32 * reveal
  drawRealBossModel(cx, cy, bossR, local, screenWidth, screenHeight)

  for i in 0..<10:
    let a = local * 0.9'f32 + i.float32 * PI * 2.0'f32 / 10.0'f32
    let sx = cx + cos(a) * (bossR + 80.0'f32)
    let sy = cy + sin(a) * (bossR + 54.0'f32)
    drawCircle(Vector2(x: sx, y: sy), 10.0'f32 * reveal, Color(r: 255, g: 80, b: 220, a: alphaByte(alpha * 190.0'f32)))
    if i mod 2 == 0:
      drawLine(sx.int32, sy.int32, (cx + cos(a + 0.3'f32) * 360.0'f32).int32,
               (cy + sin(a + 0.3'f32) * 260.0'f32).int32,
               Color(r: 255, g: 40, b: 120, a: alphaByte(alpha * 55.0'f32)))

  drawSubtitles([t(tkLoreBoss1), t(tkLoreBoss2)], screenWidth, screenHeight, alpha)

proc drawCounterShot(local, duration: float32, screenWidth, screenHeight: int32,
                     alpha: float32) =
  let x = screenWidth.float32 * 0.22'f32
  let y = screenHeight.float32 * 0.52'f32 + sin(local * 2.0'f32) * 12.0'f32
  drawEquippedPlayerModel(newVector2f(x, y), 24.0'f32, local, alpha, 0.2'f32)

  let muzzleX = x + 66.0'f32
  for i in 0..<16:
    let delay = i.float32 * 0.12'f32
    let p = fractCoord(local * 0.92'f32 - delay)
    let bx = muzzleX + p * screenWidth.float32 * 0.88'f32
    let by = y + sin(i.float32 * 1.9'f32) * 92.0'f32 + sin(local * 5.0'f32 + i.float32) * 8.0'f32
    let a = alpha * (1.0'f32 - p) * 220.0'f32
    drawLine((bx - 46.0'f32).int32, by.int32, bx.int32, by.int32,
             Color(r: 0, g: 255, b: 235, a: alphaByte(a * 0.45'f32)))
    drawEquippedBulletModel(newVector2f(bx, by), 8.0'f32, 0.0'f32, local + i.float32, alpha * (1.0'f32 - p))
  for i in 0..<18:
    let p = clamp01((local - i.float32 * 0.16'f32) / duration)
    let ex = screenWidth.float32 * (0.57'f32 + fractCoord(i.float32 * 0.37'f32) * 0.36'f32)
    let ey = screenHeight.float32 * (0.2'f32 + fractCoord(i.float32 * 0.51'f32) * 0.52'f32)
    let r = 9.0'f32 + sin((p + local) * 9.0'f32) * 5.0'f32 + p * 38.0'f32
    drawCircleLines(Vector2(x: ex, y: ey), r, Color(r: 255, g: 160, b: 45, a: alphaByte(alpha * (1.0'f32 - p) * 170.0'f32)))

  drawSubtitles([t(tkLoreCounter1), t(tkLoreCounter2)], screenWidth, screenHeight, alpha)

proc drawDirectiveShot(local, duration: float32, screenWidth, screenHeight: int32,
                       alpha: float32) =
  let cx = screenWidth.float32 * 0.5'f32
  let cy = screenHeight.float32 * 0.44'f32
  let pulse = sin(local * 4.0'f32) * 0.5'f32 + 0.5'f32
  drawSoftGlow(cx, cy, 300.0'f32, Color(r: 0, g: 255, b: 220, a: alphaByte(alpha * (46.0'f32 + pulse * 30.0'f32))), 1.0'f32)
  drawEquippedPlayerModel(newVector2f(cx, cy), 27.0'f32 * (1.0'f32 + pulse * 0.04'f32),
                          local, alpha, 0.28'f32)

  let titleAlpha = alpha * easeInOut(local / 0.85'f32)
  drawCenteredText(t(tkLoreDirectiveTitle), screenWidth div 2, (screenHeight * 2 div 3).int32,
                   32, Color(r: 255, g: 255, b: 255, a: alphaByte(titleAlpha * 255.0'f32)))
  drawCenteredText(t(tkLoreDirectiveSub), screenWidth div 2, (screenHeight * 2 div 3 + 46).int32,
                   21, Color(r: 0, g: 230, b: 230, a: alphaByte(titleAlpha * 210.0'f32)))

proc shotCue(shot: LoreShot): SoundType =
  ## Per-shot audio sting, fired once when a new shot begins.
  case shot
  of lsBreach: stTeleport
  of lsSwarm: stExplosion
  of lsAwaken: stPowerUp
  of lsBoss: stBossSpawn
  of lsCounterattack: stShoot
  of lsDirective: stShield

proc updateLoreCinematic*(lore: LoreCinematic, dt: float32) =
  if lore.complete:
    return

  lore.fastForwardActive = isKeyDown(Enter)
  if isKeyDown(Space):
    lore.skipHoldTimer = min(LoreSkipHoldRequired, lore.skipHoldTimer + dt)
  else:
    lore.skipHoldTimer = 0.0'f32

  if lore.skipHoldTimer >= LoreSkipHoldRequired:
    lore.complete = true
    return

  let playbackDt = dt * (if lore.fastForwardActive: LoreFastForwardMultiplier else: 1.0'f32)
  lore.time += playbackDt
  lore.scanlineOffset += playbackDt * 118.0'f32
  inc lore.frame

  # Fire a one-shot audio sting whenever playback crosses into a new shot.
  let (curShot, _, _) = shotAt(lore.time)
  if ord(curShot) != lore.lastShotPlayed:
    lore.lastShotPlayed = ord(curShot)
    playSound(shotCue(curShot), 0.6'f32)  # ducked so the sting sits under the score

  if lore.time >= LoreDuration:
    lore.complete = true

proc drawTapeChange(screenWidth, screenHeight: int32, local: float32,
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

proc drawTitleCard(lore: LoreCinematic, screenWidth, screenHeight: int32) =
  ## Opening "archive playback" card; appears as the boot fade clears, then leaves.
  let appear = clamp01((lore.time - 0.2'f32) / 0.5'f32)
  let leave = clamp01((1.95'f32 - lore.time) / 0.5'f32)
  let a = min(appear, leave)
  if a <= 0.0'f32:
    return
  let cx = screenWidth div 2
  let cy = screenHeight div 2 - 30
  # Thin framing rules above and below the title.
  let ruleW = (screenWidth.float32 * 0.32'f32 * a).int32
  drawRectangle(cx - ruleW, cy - 16, ruleW * 2, 2,
                Color(r: 0, g: 230, b: 230, a: alphaByte(a * 170.0'f32)))
  drawRectangle(cx - ruleW, cy + 54, ruleW * 2, 2,
                Color(r: 0, g: 230, b: 230, a: alphaByte(a * 170.0'f32)))
  drawCenteredText("TopHat-ShooterOS", cx.int32, (cy).int32, 40,
                   Color(r: 255, g: 255, b: 255, a: alphaByte(a * 255.0'f32)))
  drawCenteredText(t(tkLoreTitleCardSub), cx.int32, (cy + 60).int32, 16,
                   Color(r: 0, g: 230, b: 230, a: alphaByte(a * 200.0'f32)))

proc drawLoreCinematic*(lore: LoreCinematic, screenWidth, screenHeight: int) =
  let (shot, local, duration) = shotAt(lore.time)
  let alpha = shotFade(local, duration)
  let shake =
    if shot == lsBoss:
      sin(lore.time * 36.0'f32) * 3.0'f32 * alpha
    elif shot == lsBreach and local > duration * 0.58'f32:
      sin(lore.time * 44.0'f32) * 2.0'f32 * alpha
    else:
      sin(lore.time * 0.7'f32) * 1.2'f32 * alpha
  let sW = screenWidth.int32
  let sH = screenHeight.int32

  drawSharedBackdrop(sW, sH, lore.time * 0.48'f32,
                     Color(r: 2, g: 4, b: 8, a: 255),
                     Color(r: 8, g: 12, b: 20, a: 255),
                     Color(r: 16, g: 34, b: 44, a: 30),
                     Color(r: 40, g: 110, b: 120, a: 46),
                     Color(r: 0, g: 210, b: 210, a: 34),
                     0.55, 0.5)

  # Camera drift is deliberately tiny so the scene reads as a video feed without
  # making subtitles or UI hard to track.
  let camX = shake
  let camY = cos(lore.time * 0.84'f32) * 1.2'f32 * alpha
  drawRectangle(camX.int32 - 8, camY.int32 - 8, sW + 16, sH + 16,
                Color(r: 0, g: 0, b: 0, a: 35))

  pushMatrix()
  translatef(camX, camY, 0.0'f32)
  case shot
  of lsBreach:
    drawBreachShot(local, duration, sW, sH, alpha)
  of lsSwarm:
    drawSwarmShot(local, duration, sW, sH, alpha)
  of lsAwaken:
    drawAwakenShot(local, duration, sW, sH, alpha)
  of lsBoss:
    drawBossShot(local, duration, sW, sH, alpha)
  of lsCounterattack:
    drawCounterShot(local, duration, sW, sH, alpha)
  of lsDirective:
    drawDirectiveShot(local, duration, sW, sH, alpha)
  popMatrix()

  # Cut punctuation sits over the scene but under the recorder chrome.
  drawTapeChange(sW, sH, local, lore.frame, lore.time)

  let fadeIn = 1.0'f32 - easeInOut(lore.time / 0.75'f32)
  let fadeOut = easeInOut((lore.time - (LoreDuration - 0.9'f32)) / 0.9'f32)
  let fadeA = alphaByte(max(fadeIn, fadeOut) * 255.0'f32)
  drawVideoOverlay(lore, sW, sH, shot, local, duration)
  drawTitleCard(lore, sW, sH)
  if fadeA > 0:
    drawRectangle(0, 0, sW, sH, Color(r: 0, g: 0, b: 0, a: fadeA))
