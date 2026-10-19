## Shared Cinematic Rendering
## Shot-agnostic helpers used by both the opening lore cinematic (`lore_cinematic.nim`)
## and the endgame cinematic (`endgame_cinematic.nim`): easing/colour maths, the
## equipped player / kernel / bullet / enemy / boss models, subtitles, the VHS
## recorder chrome (scanlines, letterbox, skip-hold box) and the tape-change burst.
## Keeping these here means both cinematics render the exact same models and chrome,
## so the outro reads as a sibling of the intro.

import raylib, rlgl, math, strutils
import ../modding/mod_patch_core
import ../draw_prims
from std/unicode import runeLen, runeSubStr
import particle_types, background_fx, ../types, ../settings, ../save_system, ../skins, ../shapes, ../bullet_skins, ../bullet_shapes, ../enemy, ../enemy_config, icon_drawing, ../utils, ../localization, ui_helpers

# Equipped cosmetics (mirrors what the player has selected in the shop)

proc equippedSkin(): SkinType {.moddable.} =
  if globalSettings.isNil:
    skDefault
  else:
    SkinType(clamp(globalSettings.playerSkin, ord(low(SkinType)), ord(high(SkinType))))

proc equippedShape(): ShapeType {.moddable.} =
  if globalSettings.isNil:
    shHexagon
  else:
    ShapeType(clamp(globalSettings.playerShape, ord(low(ShapeType)), ord(high(ShapeType))))

proc equippedBulletSkin(): BulletSkinType {.moddable.} =
  if globalSettings.isNil:
    bskDefault
  else:
    BulletSkinType(clamp(globalSettings.bulletSkin, ord(low(BulletSkinType)), ord(high(BulletSkinType))))

proc equippedBulletShape(): BulletShapeType {.moddable.} =
  if globalSettings.isNil:
    bshCircle
  else:
    BulletShapeType(clamp(globalSettings.bulletShape, ord(low(BulletShapeType)), ord(high(BulletShapeType))))

proc drawEquippedPlayerModel*(pos: Vector2, radius: float32, time: float32,
                             alpha: float32 = 1.0'f32, glowBoost: float32 = 0.0'f32) {.moddable.} =
  let pulse = sin(time * 2.0'f32) * 0.5'f32 + 0.5'f32
  let rotation = time * 0.5'f32
  let (primary, secondary, core) = getSkinColors(equippedSkin(), time)
  drawPlayerShape(pos, radius, equippedShape(),
                  withAlpha(primary, alpha * primary.a.float32),
                  withAlpha(secondary, alpha * secondary.a.float32),
                  withAlpha(core, alpha * core.a.float32),
                  time, rotation, pulse, 0.4'f32 + pulse * 0.2'f32 + glowBoost)

proc drawKernelModel*(pos: Vector2, radius: float32, time: float32,
                     boot: float32, alpha: float32 = 1.0'f32, hat: bool = true) {.moddable.} =
  ## The TOPHAT kernel itself: a hexagonal core wrapped in counter-rotating
  ## containment arcs. `boot` (0..1) drives the wake-up, the shell scales in,
  ## the core lens charges, and the tophat drops on as the final stage.
  ## `hat = false` once it has handed the hat to shooter.exe (Act II).
  let center = pos
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
               Color(r: 0, g: 215, b: 230, a: clampByteF(arcAlpha)))

  # Hexagonal shell with a slow spin; the hat stays upright on top.
  drawPoly(center, 6, r, spin, Color(r: 8, g: 20, b: 28, a: clampByteF(alpha * 240.0'f32)))
  drawPolyOutline(center, 6, r, spin,
                Color(r: 0, g: 225, b: 230, a: clampByteF(alpha * 230.0'f32)))
  drawPolyOutline(center, 6, r * 0.66'f32, -spin * 1.7'f32,
                Color(r: 0, g: 170, b: 190, a: clampByteF(alpha * 150.0'f32)))

  # Spokes from the shell vertices into the core.
  for i in 0..<6:
    let a = degToRad(spin) + i.float32 * PI / 3.0'f32
    drawStroke(Vector2(x: pos.x + cos(a) * r * 0.4'f32, y: pos.y + sin(a) * r * 0.4'f32),
             Vector2(x: pos.x + cos(a) * r, y: pos.y + sin(a) * r), 1.5'f32,
             Color(r: 0, g: 160, b: 180, a: clampByteF(alpha * 90.0'f32)))

  # Core lens: charges with boot, breathes once awake.
  let coreR = r * 0.34'f32 * (0.55'f32 + boot * 0.45'f32) * (0.92'f32 + pulse * 0.08'f32)
  drawSoftGlow(pos.x, pos.y, coreR * 3.2'f32,
               Color(r: 0, g: 240, b: 230, a: clampByteF(alpha * boot * 60.0'f32)), 1.0'f32)
  drawDisc(center, coreR, Color(r: 0, g: 235, b: 225, a: clampByteF(alpha * 235.0'f32)))
  drawDisc(center, coreR * 0.55'f32,
             Color(r: 235, g: 255, b: 255, a: clampByteF(alpha * (140.0'f32 + boot * 110.0'f32))))

  # The tophat drops on as the final stage of the wake-up.
  let hatT = easeOutCubic(clamp01((boot - 0.45'f32) / 0.45'f32))
  if hat and hatT > 0.0'f32:
    let hatPos = vec2(pos.x, pos.y - (1.0'f32 - hatT) * r * 3.2'f32)
    drawTopHat(hatPos, r, time, alpha * hatT)

proc drawEquippedBulletModel*(pos: Vector2, radius: float32, travelAngle: float32,
                             time: float32, alpha: float32 = 1.0'f32) {.moddable.} =
  let (primary, glow, trail) = getBulletSkinColors(equippedBulletSkin(), time)
  for i in 1..4:
    let tx = pos.x - cos(travelAngle) * i.float32 * radius * 1.45'f32
    let ty = pos.y - sin(travelAngle) * i.float32 * radius * 1.45'f32
    let trailAlpha = alpha * trail.a.float32 * (1.0'f32 - i.float32 * 0.18'f32)
    drawDisc(Vector2(x: tx, y: ty), radius * (1.0'f32 - i.float32 * 0.12'f32),
               withAlpha(trail, trailAlpha))
  drawPlayerBulletShape(pos, radius, equippedBulletShape(), travelAngle,
                        withAlpha(primary, alpha * primary.a.float32),
                        withAlpha(glow, alpha * glow.a.float32))

proc cinematicEnemy(enemyType: EnemyType, x, y: float32, difficulty: float32 = 12.0'f32,
                    id: int = 0, threat: int = 0): Enemy {.moddable.} =
  var dummyGame = Game(nextEnemyId: id)
  result = newEnemy(x, y, difficulty, enemyType, dummyGame)
  result.id = id
  result.pos = vec2(x, y)
  result.targetPos = result.pos
  result.startPos = result.pos
  result.hasEnteredScreen = true
  result.spawnTimer = 0
  result.entranceTimer = 0
  result.threatLevel = threat

proc drawRealEnemy*(enemyType: EnemyType, x, y, radius, time: float32,
                   id: int = 0, threat: int = 0, vel: Vector2 = vec2(0, 0)) {.moddable.} =
  let config = getEnemyConfig(enemyType)
  let e = cinematicEnemy(enemyType, x, y, 18.0'f32, id, threat)
  e.radius = radius
  e.collisionRadius = radius * 0.4'f32
  e.color = config.baseColor
  e.vel = vel
  e.dashCooldown = if enemyType in {etTriangle, etStar}: 0.25'f32 + abs(sin(time + id.float32)) * 0.25'f32 else: e.dashCooldown
  e.dashTimer = if enemyType == etTriangle: 0.35'f32 else: e.dashTimer
  drawEnemy(e)

proc newCinematicBoss*(bossId: int, screenWidth, screenHeight: int32): Enemy {.moddable.} =
  ## Boss `bossId` built once for a shot to pose; draw it with drawCinematicBoss.
  ## Campaign bosses use their own wave slot so they wear their real kit.
  spawnBossById(screenWidth, screenHeight, bossId, max(5, bossId * 5))

proc drawCinematicBoss*(boss: Enemy, x, y, radius: float32,
                        hpFraction: float32 = 1.0'f32, phaseIndex: int = 0) {.moddable.} =
  boss.pos = vec2(x, y)
  boss.targetPos = boss.pos
  boss.startPos = boss.pos
  boss.radius = radius
  boss.collisionRadius = radius * 0.4'f32
  boss.hp = boss.maxHp * clamp(hpFraction, 0.001'f32, 1.0'f32)
  boss.currentPhaseIndex = phaseIndex
  boss.entranceTimer = 0
  boss.spawnTimer = 0
  drawEnemy(boss)

# Text / atmosphere

proc drawCenteredText*(text: string, x, y: int32, size: int32, color: Color) {.moddable.} =
  let w = measureText(text, size)
  drawText(text, x - w div 2, y, size, color)

var
  captionClock* = -1.0'f32
    ## Local time of the shot being drawn, set by drawCutscene around each shot's
    ## drawProc so drawSubtitles can type its captions out. Negative = no clock
    ## (any caller outside the cutscene framework): captions draw fully revealed.
  captionShotDuration* = 0.0'f32
    ## Duration of that shot; caps the typing so every caption lands early.
  captionSpeaker* = ""
    ## Who the captions belong to, drawn as a chip above them ("" = none). The
    ## story is TOPHAT's incident log, so drawCutscene sets the cutscene's
    ## speaker around each shot the same way it sets captionClock.
  captionAccent* = Color(r: 0, g: 230, b: 230, a: 255)
  captionCharsPerSec* = 46.0'f32
    ## Base typing speed of the shot being drawn, set by drawCutscene from the
    ## cutscene (the story endings type slower than the intro).

const
  CaptionStartDelay = 0.3'f32   # first character appears this far into the shot
  CaptionLineGap = 0.2'f32      # pause between finishing one line and starting the next
  CaptionMaxShare = 0.5'f32     # all lines finish within this share of the shot

proc drawSpeakerChip(name: string, cx, y: int32, alpha: float32) =
  ## A small name tag with TOPHAT's hat beside it.
  const size = 13'i32
  let w = measureText(name, size)
  let chipW = w + 40
  let x = cx - chipW div 2
  drawRectangle(x, y, chipW, 20, Color(r: 6, g: 12, b: 18, a: clampByteF(alpha * 200.0'f32)))
  drawRectOutline(x, y, chipW, 20, withAlpha(captionAccent, alpha * 150.0'f32))
  drawTopHat(vec2((x + 14).float32, (y + 10).float32 + 7.0'f32 * 0.74'f32), 7.0'f32,
             0.0'f32, alpha, captionAccent)
  drawText(name, x + 28, y + 4, size, withAlpha(captionAccent, alpha * 235.0'f32))

proc drawSubtitles*(lines: openArray[string], screenWidth, screenHeight: int32,
                   alpha: float32) {.moddable.} =
  ## Captions type out left to right behind a blinking block cursor, like the
  ## incident log they are read from. Each line is laid out at its FINAL centered
  ## position, so the text never slides while it types.
  let baseY = screenHeight - screenHeight div 9 - 76
  var totalRunes = 0
  for line in lines: totalRunes += line.runeLen
  let typing = captionClock >= 0.0'f32
  # Speed up rather than overrun on long lines: finish by CaptionMaxShare.
  let budget = captionShotDuration * CaptionMaxShare - CaptionStartDelay -
               CaptionLineGap * max(0, lines.len - 1).float32
  let cps = if typing and budget > 0.0'f32: max(captionCharsPerSec, totalRunes.float32 / budget)
            else: captionCharsPerSec
  # A soft dark band keeps the log readable over busy scenes (the desktop,
  # crash screens, swarms), fading in with the first character.
  let bandA = alpha * (if typing: clamp01((captionClock - CaptionStartDelay + 0.2'f32) / 0.4'f32) else: 1.0'f32)
  if lines.len > 0 and bandA > 0.0'f32:
    let top = baseY - 34
    let h = screenHeight - screenHeight div 9 - top   # runs into the letterbox
    drawRectangleGradientV(0, top - 24, screenWidth, 24, Color(r: 0, g: 0, b: 0, a: 0),
                           Color(r: 0, g: 0, b: 0, a: clampByteF(bandA * 130.0'f32)))
    drawRectangle(0, top, screenWidth, h, Color(r: 0, g: 0, b: 0, a: clampByteF(bandA * 130.0'f32)))
    if captionSpeaker.len > 0:
      drawSpeakerChip(captionSpeaker, screenWidth div 2, baseY - 28, bandA)
  var lineStart = CaptionStartDelay
  for i, line in lines:
    # A long line (or a longer translation) shrinks instead of running off a 4:3 screen.
    let size = bestFitFontSize(line, screenWidth - 60, if i == 0: 22'i32 else: 17'i32, 14)
    let color =
      if i == 0:
        Color(r: 250, g: 255, b: 255, a: clampByteF(alpha * 245.0'f32))
      else:
        Color(r: 0, g: 225, b: 225, a: clampByteF(alpha * 210.0'f32))
    let y = baseY + i.int32 * 27
    if not typing:
      drawCenteredText(line, screenWidth div 2, y, size, color)
      continue
    let runes = line.runeLen
    let lineEnd = lineStart + runes.float32 / cps
    let shown = clamp(int((captionClock - lineStart) * cps), 0, runes)
    if shown > 0:
      let x = screenWidth div 2 - measureText(line, size) div 2
      let prefix = line.runeSubStr(0, shown)
      drawText(prefix, x, y, size, color)
      # Block cursor while this line types and briefly after it lands.
      let lingering = captionClock < lineEnd + 0.45'f32
      let nextStarted = i < lines.high and captionClock >= lineEnd + CaptionLineGap
      let cursorOn = captionClock < lineEnd or fract01(captionClock * 3.2'f32) < 0.6'f32
      if lingering and not nextStarted and cursorOn:
        var cx = x + measureText(prefix, size) + 3
        if prefix.endsWith(' '):
          # A lone trailing space measures ~0 in this font; add a real gap.
          cx += max(measureText("a a", size) - measureText("aa", size), size div 4)
        drawRectangle(cx, y + 2, max(4'i32, size div 2 - 2), size - 3, color)
    lineStart = lineEnd + CaptionLineGap

proc drawSubtitlesFrom*(lines: openArray[string], startAt: float32,
                        screenWidth, screenHeight: int32, alpha: float32) {.moddable.} =
  ## drawSubtitles held back until `startAt` into the shot, so a caption can
  ## follow the beat it explains instead of spoiling it.
  if captionClock < 0.0'f32:
    drawSubtitles(lines, screenWidth, screenHeight, alpha)
    return
  if captionClock < startAt:
    return
  let clock = captionClock
  let duration = captionShotDuration
  captionClock = clock - startAt
  captionShotDuration = duration - startAt
  drawSubtitles(lines, screenWidth, screenHeight, alpha)
  captionClock = clock
  captionShotDuration = duration

proc drawFilmGrain(screenWidth, screenHeight: int32, time: float32, alpha: float32) {.moddable.} =
  var i = 0
  while i < 150:
    let seed = i.float32 * 19.31'f32 + floor(time * 18.0'f32) * 7.13'f32
    let x = (fract01(sin(seed) * 43758.5453'f32) * screenWidth.float32).int32
    let y = (fract01(sin(seed + 12.7'f32) * 24634.6345'f32) * screenHeight.float32).int32
    let a = clampByteF(alpha * (0.35'f32 + fract01(sin(seed + 91.0'f32) * 91.3'f32)))
    drawRectangle(x, y, 1, 1, Color(r: 255, g: 255, b: 255, a: a))
    inc i

proc drawTapeChange*(screenWidth, screenHeight: int32, local: float32,
                    frame: int, time: float32) {.moddable.} =
  ## Brief VHS "channel switch" burst at the start of each shot. Transient by
  ## design (~0.18s) so it punctuates cuts without fighting the scene or subtitles.
  const window = 0.18'f32
  if local >= window:
    return
  let intensity = 1.0'f32 - local / window

  # Displaced static bands with alternating chroma tint.
  for i in 0..<7:
    let seed = i.float32 * 23.7'f32 + floor(time * 60.0'f32)
    let y = (fract01(sin(seed) * 43758.5453'f32) * screenHeight.float32).int32
    let h = (3 + (frame + i * 13) mod 14).int32
    let tint =
      if i mod 2 == 0:
        Color(r: 0, g: 235, b: 235, a: clampByteF(intensity * 120.0'f32))
      else:
        Color(r: 255, g: 40, b: 200, a: clampByteF(intensity * 110.0'f32))
    drawRectangle(0, y, screenWidth, h, tint)

  # Bright roll bar sweeping down fast.
  let rollY = (fract01(local * 6.0'f32) * screenHeight.float32).int32
  drawRectangle(0, rollY, screenWidth, 2, Color(r: 255, g: 255, b: 255, a: clampByteF(intensity * 180.0'f32)))
  # Quick whole-frame flash on the hardest part of the cut.
  drawRectangle(0, 0, screenWidth, screenHeight,
                Color(r: 210, g: 245, b: 245, a: clampByteF(intensity * intensity * 60.0'f32)))

# Recorder chrome (the "playback feed" UI around the scene)

type
  CinematicControls* = object
    ## What the bottom bar shows: the two hold actions and their live state.
    ffKey*, ffLabel*: string          ## keycap + label of hold-to-fast-forward
    skipKey*, skipLabel*: string      ## keycap + label of hold-to-skip
    ffActive*: bool                   ## fast-forward held right now
    skipProgress*: float32            ## 0..1 of the skip hold

proc drawKeycap(x, y: int32, key: string, pressed: bool, alpha: float32, accent: Color): int32 =
  ## A small key with a lip under it; pressed, it sinks and lights. Returns its width.
  const size = 12'i32
  let w = max(measureText(key, size) + 14, 26)
  let sink = if pressed: 2'i32 else: 0'i32
  if not pressed:
    drawRectangle(x, y + 18, w, 3, Color(r: 30, g: 40, b: 48, a: clampByteF(alpha * 255.0'f32)))
  drawRectangle(x, y + sink, w, 18, if pressed: withAlpha(accent, alpha * 235.0'f32)
                                     else: Color(r: 52, g: 64, b: 76, a: clampByteF(alpha * 255.0'f32)))
  drawRectOutline(x, y + sink, w, 18, Color(r: 110, g: 130, b: 145, a: clampByteF(alpha * 220.0'f32)))
  drawText(key, x + (w - measureText(key, size)) div 2, y + sink + 3, size,
           if pressed: Color(r: 6, g: 14, b: 18, a: clampByteF(alpha * 255.0'f32))
           else: Color(r: 225, g: 235, b: 240, a: clampByteF(alpha * 255.0'f32)))
  w

proc controlChipWidth(key, label: string): int32 =
  max(measureText(key, 12) + 14, 26) + measureText(label, 13) + 30

proc drawControlChip(x, y: int32, key, label: string, active: bool, fill: float32,
                     time, alpha: float32, accent: Color) =
  ## One hold action: a chip with its keycap and label. `fill` (0..1) floods
  ## the chip left to right; `active` lights it.
  let w = controlChipWidth(key, label)
  const h = 28'i32
  let lit = active or fill > 0.0'f32
  drawRectangle(x, y, w, h, Color(r: 8, g: 12, b: 18, a: clampByteF(alpha * 215.0'f32)))
  if fill > 0.0'f32:
    let fw = int32(w.float32 * clamp01(fill))
    drawRectangle(x, y, fw, h, withAlpha(accent, alpha * (115.0'f32 + 20.0'f32 * sin(time * 14.0'f32))))
    drawRectangle(x + fw - 2, y, 2, h, withAlpha(accent, alpha * 255.0'f32))
  drawRectOutline(x, y, w, h, if lit: withAlpha(accent, alpha * 230.0'f32)
                              else: Color(r: 60, g: 84, b: 96, a: clampByteF(alpha * 200.0'f32)))
  let kw = drawKeycap(x + 6, y + 4, key, lit, alpha, accent)
  drawText(label, x + 6 + kw + 10, y + 8, 13,
           if lit: Color(r: 240, g: 250, b: 255, a: clampByteF(alpha * 255.0'f32))
           else: Color(r: 150, g: 168, b: 178, a: clampByteF(alpha * 220.0'f32)))

proc drawCinematicOverlay*(screenWidth, screenHeight: int32,
                           time: float32, frame: int, scanlineOffset: float32,
                           totalDuration: float32, shotLabel, liveText: string,
                           iconIndex: int, glitchHot: bool, controls: CinematicControls,
                           accent: Color = Color(r: 0, g: 230, b: 230, a: 255)) {.moddable.} =
  ## The full VHS recorder UI: scanlines, tracking glitches, letterbox bars,
  ## shot label + LIVE marker, and the bottom bar (timeline, then the two hold
  ## actions as keycap chips). `accent` tints the active chrome so each
  ## cinematic can carry its own colour.
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

  drawShopIcon(24, 15, 22, iconIndex, withAlpha(accent, 185))
  drawText(shotLabel, 54, 18, 14, Color(r: 160, g: 220, b: 220, a: 155))
  drawRectangle(screenWidth - 86, 23, 10, 10, Color(r: 255, g: 40, b: 60, a: 220))
  drawText(liveText, screenWidth - 70, 17, 16, Color(r: 255, g: 210, b: 220, a: 180))

  # Bottom bar, row 1: the tape's timeline, edge to edge.
  let top = screenHeight - barH
  let lineX = 24'i32
  let lineW = screenWidth - 48
  let lineY = top + 14
  drawRectangle(lineX, lineY, lineW, 2, Color(r: 50, g: 70, b: 84, a: 170))
  let headX = lineX + int32(lineW.float32 * clamp01(time / totalDuration))
  drawRectangle(lineX, lineY, headX - lineX, 2, withAlpha(accent, 210))
  drawRectangle(headX - 1, lineY - 3, 3, 8, withAlpha(accent, 255))

  # Row 2: the two hold actions, fast-forward on the left, skip on the right.
  let chipY = lineY + 18
  drawControlChip(lineX, chipY, controls.ffKey, controls.ffLabel, controls.ffActive, 0.0'f32,
                  time, 1.0'f32, accent)
  let skipW = controlChipWidth(controls.skipKey, controls.skipLabel)
  drawControlChip(lineX + lineW - skipW, chipY, controls.skipKey, controls.skipLabel,
                  controls.skipProgress > 0.0'f32, controls.skipProgress, time, 1.0'f32, accent)

  drawFilmGrain(screenWidth, screenHeight, time, 24.0'f32)

# ---------------------------------------------------------------------------
# Story props
# The story is staged in the game's own interface, so these copy its look:
# window chrome from os_window.drawWindowChrome, the crash panel from
# os_system_screens.drawSystemCrash (and its localized text). None of them
# read input, so nothing on screen reacts to the real mouse.

const
  ChromeCyan* = Color(r: 0, g: 200, b: 255, a: 255)
  RootRed* = Color(r: 255, g: 70, b: 90, a: 255)
  OldAmber* = Color(r: 255, g: 176, b: 40, a: 255)
    ## The old system's phosphor: everything root writes is in this colour.

proc drawHalo*(centerX, centerY, radius: float32, color: Color, intensity: float32 = 1.0'f32) {.moddable.} =
  ## A glow that fades to nothing at its rim. background_fx.drawSoftGlow keeps
  ## its outermost disc at full alpha, which reads as a hard-edged plate at the
  ## sizes a cinematic uses; this spreads the same light over more, fainter
  ## layers. Same arguments, so the two swap freely.
  if radius <= 0.0'f32 or intensity <= 0.0'f32:
    return
  const layers = 12
  for i in countdown(layers, 1):
    let t = i.float32 / layers.float32
    let a = color.a.float32 * intensity * 0.32'f32 * (1.0'f32 - t + 1.0'f32 / layers.float32)
    drawDisc(Vector2(x: centerX, y: centerY), radius * t, withAlpha(color, clampByteF(a)))

proc triAny*(a, b, c: Vector2, col: Color) {.moddable.} =
  ## Winding-safe triangle: raylib culls one winding.
  let cross = (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
  if cross < 0.0'f32: drawTriangle(a, b, c, col)
  else: drawTriangle(a, c, b, col)

proc drawStoryWindow*(x, y, w, h: float32, title: string, alpha: float32,
                      iconColor: Color = ChromeCyan, border: Color = ChromeCyan) {.moddable.} =
  ## A focused TopHat-ShooterOS window, as drawWindowChrome draws one.
  let xi = x.int32
  let yi = y.int32
  let wi = w.int32
  let hi = h.int32
  drawRectangle(xi + 3, yi + 3, wi, hi, Color(r: 0, g: 0, b: 0, a: clampByteF(alpha * 100.0'f32)))
  for i in 1..5:
    drawRectOutline(xi - i.int32, yi - i.int32, wi + i.int32 * 2, hi + i.int32 * 2,
                    withAlpha(border, alpha * 30.0'f32 / i.float32))
  drawRectangle(xi, yi, wi, hi, Color(r: 20, g: 20, b: 30, a: clampByteF(alpha * 240.0'f32)))
  drawRectangle(xi, yi, wi, 30, Color(r: 40, g: 40, b: 50, a: clampByteF(alpha * 255.0'f32)))
  drawRectOutline(Rectangle(x: x, y: y, width: w, height: h), 2, withAlpha(border, alpha * 255.0'f32))
  drawRectangle(xi + 8, yi + 7, 16, 16, withAlpha(iconColor, alpha * 255.0'f32))
  drawText(title, xi + 32, yi + 6, bestFitFontSize(title, wi - 92, 18), withAlpha(border, alpha * 255.0'f32))
  let closeX = xi + wi - 25
  drawRectangle(closeX, yi + 5, 20, 20, Color(r: 60, g: 60, b: 70, a: clampByteF(alpha * 255.0'f32)))
  drawText("X", closeX + 6, yi + 7, 16, Color(r: 255, g: 255, b: 255, a: clampByteF(alpha * 255.0'f32)))
  let minX = xi + wi - 50
  drawRectangle(minX, yi + 5, 20, 20, Color(r: 60, g: 60, b: 70, a: clampByteF(alpha * 255.0'f32)))
  drawRectangle(minX + 5, yi + 19, 10, 2, Color(r: 255, g: 255, b: 255, a: clampByteF(alpha * 255.0'f32)))

proc drawStoryButton*(x, y, w, h: float32, label: string, alpha: float32,
                      pressed: bool = false, primary: bool = false) {.moddable.} =
  let xi = x.int32 + (if pressed: 1'i32 else: 0'i32)
  let yi = y.int32 + (if pressed: 1'i32 else: 0'i32)
  let fill =
    if pressed: Color(r: 0, g: 130, b: 165, a: 255)
    elif primary: Color(r: 0, g: 70, b: 95, a: 255)
    else: Color(r: 45, g: 45, b: 58, a: 255)
  drawRectangle(xi, yi, w.int32, h.int32, withAlpha(fill, alpha * 255.0'f32))
  drawRectOutline(Rectangle(x: xi.float32, y: yi.float32, width: w, height: h), 2,
                  withAlpha(if primary or pressed: ChromeCyan else: Color(r: 100, g: 100, b: 130, a: 255),
                         alpha * 255.0'f32))
  let size = bestFitFontSize(label, w.int32 - 12, 16)
  drawCenteredText(label, xi + w.int32 div 2, yi + (h.int32 - size) div 2, size,
                   Color(r: 240, g: 250, b: 255, a: clampByteF(alpha * 255.0'f32)))

proc drawStoryProgress*(x, y, w, h, frac, alpha: float32, color: Color = ChromeCyan) {.moddable.} =
  let xi = x.int32
  let yi = y.int32
  drawRectangle(xi, yi, w.int32, h.int32, Color(r: 12, g: 18, b: 26, a: clampByteF(alpha * 235.0'f32)))
  let fw = int32(w * clamp01(frac))
  if fw > 0:
    drawRectangleGradientV(xi, yi, fw, h.int32, withAlpha(color, alpha * 235.0'f32),
                           withAlpha(color, alpha * 150.0'f32))
  drawRectOutline(xi, yi, w.int32, h.int32, Color(r: 70, g: 120, b: 130, a: clampByteF(alpha * 200.0'f32)))

proc drawStoryPointer*(x, y, alpha: float32, pressed: bool = false) {.moddable.} =
  ## A plain OS arrow pointer; it dips a pixel while clicking.
  let d = if pressed: 1.0'f32 else: 0.0'f32
  let tip = Vector2(x: x + d, y: y + d)
  let a = Vector2(x: tip.x, y: tip.y + 20.0'f32)
  let b = Vector2(x: tip.x + 14.0'f32, y: tip.y + 14.0'f32)
  triAny(Vector2(x: tip.x - 1.5'f32, y: tip.y - 2.0'f32), Vector2(x: a.x - 1.5'f32, y: a.y + 2.5'f32),
         Vector2(x: b.x + 2.5'f32, y: b.y + 1.0'f32), Color(r: 0, g: 0, b: 0, a: clampByteF(alpha * 220.0'f32)))
  triAny(tip, a, b, Color(r: 245, g: 245, b: 245, a: clampByteF(alpha * 255.0'f32)))

proc revealOver*(local, startAt, dur: float32): float32 {.moddable.} =
  ## 0..1 progress of a line that types out from `startAt` over `dur` seconds.
  ## Fixed durations (not characters per second) keep the typing landing on
  ## the score's beep whatever the language.
  clamp01((local - startAt) / dur)

proc drawOldText*(text: string, x, y: int32, size: int32, reveal, local, alpha: float32,
                  color: Color = OldAmber, centered: bool = true, cursor: bool = true) {.moddable.} =
  ## Root's voice: phosphor text with a block cursor, typed out by `reveal`.
  ## Laid out at its final position so it never slides while it types.
  if alpha <= 0.0'f32:
    return
  let runes = text.runeLen
  let shown = clamp(int(reveal * runes.float32 + 0.001'f32), 0, runes)
  let x0 = if centered: x - measureText(text, size) div 2 else: x
  let prefix = text.runeSubStr(0, shown)
  if shown > 0:
    drawText(prefix, x0 + 2, y + 2, size, withAlpha(color, alpha * 60.0'f32))
    drawText(prefix, x0, y, size, withAlpha(color, alpha * 245.0'f32))
  if cursor and (reveal < 1.0'f32 or fract01(local * 2.2'f32) < 0.55'f32):
    var cx = x0 + measureText(prefix, size) + size div 6
    if prefix.endsWith(' '):
      cx += max(measureText("a a", size) - measureText("aa", size), size div 4)
    drawRectangle(cx, y + 1, max(4'i32, size div 2), size - 2, withAlpha(color, alpha * 230.0'f32))

proc drawCrashPanel*(sw, sh: int32, alpha, time: float32) {.moddable.} =
  ## The game's own crash screen, condensed: same blue, same sad face, same text.
  drawRectangle(0, 0, sw, sh, Color(r: 12, g: 35, b: 68, a: clampByteF(alpha * 250.0'f32)))
  for i in 0..<(sh div 4):
    drawRectangle(0, i * 4 + int32(time * 100.0'f32) mod 4, sw, 2,
                  Color(r: 20, g: 50, b: 90, a: clampByteF(alpha * (5.0'f32 + sin(time * 2.0'f32 + i.float32) * 5.0'f32))))
  let pw = min(720'i32, sw - 120)
  let ph = 250'i32
  let px = (sw - pw) div 2
  let py = sh div 2 - 185
  drawRectangle(px - 10, py - 10, pw + 20, ph + 20, Color(r: 18, g: 45, b: 85, a: clampByteF(alpha * 255.0'f32)))
  drawRectOutline(Rectangle(x: (px - 10).float32, y: (py - 10).float32,
                            width: (pw + 20).float32, height: (ph + 20).float32), 3,
                  Color(r: 60, g: 120, b: 200, a: clampByteF(alpha * 255.0'f32)))
  let pulse = sin(time * 2.0'f32) * 0.2'f32 + 0.8'f32
  drawText(":(", px + 30, py + 24, 64, Color(r: uint8(210.0'f32 * pulse), g: uint8(90.0'f32 * pulse),
                                             b: uint8(95.0'f32 * pulse), a: clampByteF(alpha * 255.0'f32)))
  let title = t(tkGameOverCriticalFailure)
  drawText(title, px + 122, py + 40, bestFitFontSize(title, pw - 150, 32),
           Color(r: 255, g: 95, b: 95, a: clampByteF(alpha * 255.0'f32)))
  let msg = t(tkGameOverErrorMsg)
  drawText(msg, px + 30, py + 112, bestFitFontSize(msg, pw - 60, 16),
           Color(r: 210, g: 220, b: 235, a: clampByteF(alpha * 255.0'f32)))
  drawRectangle(px + 30, py + 150, pw - 60, 30, Color(r: 25, g: 45, b: 75, a: clampByteF(alpha * 255.0'f32)))
  drawRectOutline(px + 30, py + 150, pw - 60, 30, Color(r: 60, g: 100, b: 160, a: clampByteF(alpha * 255.0'f32)))
  drawText("[!]", px + 40, py + 156, 16, Color(r: 255, g: 200, b: 100, a: clampByteF(alpha * 255.0'f32)))
  let code = t(tkGameOverErrorCode)
  drawText(code, px + 66, py + 158, bestFitFontSize(code, pw - 110, 14),
           Color(r: 230, g: 235, b: 245, a: clampByteF(alpha * 255.0'f32)))

proc serviceWindowHeight(rows: int): float32 {.moddable.} =
  30.0'f32 + 34.0'f32 + rows.float32 * 27.0'f32 + 10.0'f32

proc drawServiceWindow*(x, y, w: float32, title, colService, colOwner: string,
                        names: openArray[string], flipTimes: openArray[float32],
                        local, alpha: float32,
                        fromOwner, toOwner: string, fromColor, toColor: Color) {.moddable.} =
  ## TOPHAT's service list with an owner column. Row i changes owner from
  ## `fromOwner` to `toOwner` at `flipTimes[i]`, with a flash. Act I uses it
  ## for the hijack (tophat -> root), Act II for the return (root -> tophat).
  let h = serviceWindowHeight(names.len)
  drawStoryWindow(x, y, w, h, title, alpha, Color(r: 255, g: 200, b: 80, a: 255))
  let xi = x.int32
  let yi = y.int32
  let ownerX = xi + w.int32 - 110
  let hdr = Color(r: 140, g: 160, b: 180, a: clampByteF(alpha * 255.0'f32))
  drawText(colService, xi + 20, yi + 40, 14, hdr)
  drawText(colOwner, ownerX, yi + 40, 14, hdr)
  for i, name in names:
    let ry = yi + 64 + i.int32 * 27
    let flipped = local >= flipTimes[i]
    let flash = if flipped: 1.0'f32 - clamp01((local - flipTimes[i]) / 0.3'f32) else: 0.0'f32
    if flash > 0.0'f32:
      drawRectangle(xi + 6, ry - 3, w.int32 - 12, 25, withAlpha(toColor, alpha * flash * 110.0'f32))
    drawText(name, xi + 20, ry, 17, Color(r: 225, g: 235, b: 245, a: clampByteF(alpha * 255.0'f32)))
    drawText(if flipped: toOwner else: fromOwner, ownerX, ry, 17,
             withAlpha(if flipped: toColor else: fromColor, alpha * 255.0'f32))

proc beginStoryCamera*(focusX, focusY, screenX, screenY, scale: float32) {.moddable.} =
  ## Film a full-screen scene (the desktop) as footage: the scene point
  ## (focusX, focusY) lands on (screenX, screenY), scaled by `scale`. Moving
  ## the focus and scale over a shot pushes the camera in. Pair with
  ## endStoryCamera.
  pushMatrix()
  translatef(screenX, screenY, 0.0'f32)
  scalef(scale, scale, 1.0'f32)
  translatef(-focusX, -focusY, 0.0'f32)

proc endStoryCamera*() {.moddable.} =
  popMatrix()

proc drawFootageFrame*(sw, sh: int32, scale, alpha: float32) {.moddable.} =
  ## Inside a story camera: the edge of the filmed screen.
  drawRectOutline(Rectangle(x: 0.0'f32, y: 0.0'f32, width: sw.float32, height: sh.float32),
                  2.0'f32 / max(0.1'f32, scale), Color(r: 90, g: 150, b: 170, a: clampByteF(alpha * 150.0'f32)))
