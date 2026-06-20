## Endgame Cinematic — outro narrative.
## Plays once after the wave-60 boss falls. Shot content (drawXxxShot procs) is
## identical to before; EndgameCinematic is now a type alias for Cutscene, built by
## newEndgameCutscene() via the generic framework in cutscene.nim.

import raylib, rlgl, math
import particle_types
import background_fx, ../types, ../shapes, ../localization, ../sound,
       cinematic_common, cutscene

const
  EndAccent* = Color(r: 60, g: 235, b: 160, a: 255)  # "restored" mint-green

# ---------------------------------------------------------------------------
# Shot draw procs (unchanged content)

proc drawFallShot(local, duration: float32, screenWidth, screenHeight: int32,
                  alpha: float32) =
  let cx = screenWidth.float32 * 0.5'f32
  let cy = screenHeight.float32 * 0.44'f32
  let collapse = easeInOut(local / duration)

  drawSoftGlow(cx, cy, 260.0'f32 * (1.0'f32 - collapse * 0.7'f32),
               Color(r: 170, g: 0, b: 255, a: alphaByte(alpha * 60.0'f32 * (1.0'f32 - collapse))), 1.0'f32)

  if collapse < 0.9'f32:
    let bossR = 92.0'f32 * (1.0'f32 - collapse * 0.85'f32)
    drawRealBossModel(cx, cy, bossR, local, screenWidth, screenHeight,
                      max(0.02'f32, 0.16'f32 * (1.0'f32 - collapse)))

  for i in 0..<12:
    let a = i.float32 * PI * 2.0'f32 / 12.0'f32 + local * 0.4'f32
    let len = 36.0'f32 + collapse * 230.0'f32
    drawLine(cx.int32, cy.int32,
             (cx + cos(a) * len).int32, (cy + sin(a) * len).int32,
             Color(r: 255, g: 60, b: 200, a: alphaByte(alpha * (1.0'f32 - collapse) * 150.0'f32)))

  for k in 0..<3:
    let rp = clamp01(collapse * 1.3'f32 - k.float32 * 0.18'f32)
    if rp > 0.0'f32:
      drawCircleLines(Vector2(x: cx, y: cy), rp * 340.0'f32,
                      colorA(EndAccent, alpha * (1.0'f32 - rp) * 180.0'f32))

  for i in 0..<18:
    let ang = fractCoord(sin(i.float32 * 12.9898'f32) * 43758.5453'f32) * PI * 2.0'f32
    let dist = collapse * (110.0'f32 + fractCoord(i.float32 * 7.31'f32) * 230.0'f32)
    let px = cx + cos(ang) * dist
    let py = cy + sin(ang) * dist
    let sides = 3 + (i mod 4).int32
    drawPoly(Vector2(x: px, y: py), sides, 7.0'f32 * (1.0'f32 - collapse), local * 90.0'f32 + i.float32,
             Color(r: 230, g: 60, b: 200, a: alphaByte(alpha * (1.0'f32 - collapse) * 200.0'f32)))

  let flash = clamp01(1.0'f32 - abs(collapse - 0.62'f32) / 0.12'f32)
  if flash > 0.0'f32:
    drawRectangle(0, 0, screenWidth, screenHeight,
                  Color(r: 235, g: 255, b: 245, a: alphaByte(alpha * flash * 150.0'f32)))

  drawSubtitles([t(tkEndFall1), t(tkEndFall2)], screenWidth, screenHeight, alpha)

proc drawPurgeShot(local, duration: float32, screenWidth, screenHeight: int32,
                   alpha: float32) =
  let progress = easeInOut(local / duration)
  let frontX = -120.0'f32 + progress * (screenWidth.float32 + 240.0'f32)

  let reclaimW = clamp(frontX, 0.0'f32, screenWidth.float32).int32
  drawRectangleGradientH(0, 0, reclaimW, screenHeight,
                         colorA(EndAccent, alpha * 55.0'f32),
                         colorA(EndAccent, 0.0'f32))
  drawDataRain(screenWidth, screenHeight, local, alpha * 0.85'f32,
               Color(r: EndAccent.r, g: EndAccent.g, b: EndAccent.b, a: 255))

  let enemyKinds = [etCircle, etCube, etTriangle, etStar, etCross, etDiamond, etOctagon]
  for i in 0..<14:
    let ex = screenWidth.float32 * (0.08'f32 + fractCoord(i.float32 * 0.41'f32) * 0.84'f32)
    let ey = screenHeight.float32 * (0.22'f32 + fractCoord(i.float32 * 0.67'f32) * 0.52'f32)
    let passed = clamp01((frontX - ex) / 120.0'f32)
    let sz = (10.0'f32 + (i mod 4).float32 * 4.0'f32) * (1.0'f32 - passed)
    if sz > 0.6'f32:
      drawRealEnemy(enemyKinds[i mod enemyKinds.len], ex, ey, sz, local, i, 0)
    if passed > 0.0'f32 and passed < 1.0'f32:
      drawCircle(Vector2(x: ex, y: ey), 7.0'f32 * (1.0'f32 - passed),
                 colorA(EndAccent, alpha * 200.0'f32))

  drawSoftGlow(frontX, screenHeight.float32 * 0.5'f32, 90.0'f32,
               colorA(EndAccent, alpha * 70.0'f32), 1.0'f32)
  drawRectangle((frontX - 3.0'f32).int32, 0, 6, screenHeight,
                colorA(EndAccent, alpha * 210.0'f32))

  drawSubtitles([t(tkEndPurge1), t(tkEndPurge2)], screenWidth, screenHeight, alpha)

proc drawRestoreShot(local, duration: float32, screenWidth, screenHeight: int32,
                     alpha: float32) =
  let boot = easeOut(local / (duration * 0.62'f32))
  let cx = screenWidth.float32 * 0.5'f32
  let cy = screenHeight.float32 * 0.46'f32

  drawSoftGlow(cx, cy, 240.0'f32 * boot, colorA(EndAccent, alpha * 50.0'f32), 1.0'f32)

  for i in 0..<16:
    let ang = i.float32 * PI * 2.0'f32 / 16.0'f32 + local * 0.5'f32
    let inT = fractCoord(local * 0.5'f32 + i.float32 * 0.063'f32)
    let dist = (1.0'f32 - inT) * 270.0'f32 + 40.0'f32
    let px = cx + cos(ang) * dist
    let py = cy + sin(ang) * dist
    drawCircle(Vector2(x: px, y: py), 3.0'f32 * inT + 1.0'f32,
               colorA(EndAccent, alpha * inT * 170.0'f32))
    drawLine(px.int32, py.int32, cx.int32, cy.int32,
             colorA(EndAccent, alpha * inT * 28.0'f32))

  drawKernelModel(newVector2f(cx, cy), 46.0'f32, local, boot, alpha)

  drawSubtitles([t(tkEndRestore1), t(tkEndRestore2)], screenWidth, screenHeight, alpha)

proc drawCrownShot(local, duration: float32, screenWidth, screenHeight: int32,
                   alpha: float32) =
  let rise = easeInOut(local / duration)
  let cx = screenWidth.float32 * 0.5'f32
  let cy = screenHeight.float32 * (0.56'f32 - rise * 0.07'f32)

  for i in -2..2:
    let bx = cx + i.float32 * 44.0'f32
    drawRectangleGradientV(bx.int32 - 6, 0, 12, screenHeight,
                           colorA(EndAccent, 0.0'f32),
                           colorA(EndAccent, alpha * rise * 50.0'f32))
  drawSoftGlow(cx, cy, 200.0'f32 * rise + 70.0'f32,
               colorA(EndAccent, alpha * (40.0'f32 + rise * 40.0'f32)), 1.0'f32)

  for i in 0..<20:
    let p = fractCoord(local * 0.4'f32 + i.float32 * 0.137'f32)
    let sx = cx + sin(i.float32 * 2.3'f32 + local) * (40.0'f32 + i.float32 * 4.0'f32)
    let sy = screenHeight.float32 * 0.92'f32 - p * screenHeight.float32 * 0.72'f32
    drawCircle(Vector2(x: sx, y: sy), 2.6'f32 * (1.0'f32 - p),
               colorA(EndAccent, alpha * (1.0'f32 - p) * 200.0'f32))

  let pr = 30.0'f32 * (0.82'f32 + rise * 0.18'f32)
  drawEquippedPlayerModel(newVector2f(cx, cy), pr, local, alpha, 0.3'f32 + rise * 0.3'f32)

  let hatT = easeOut(clamp01((rise - 0.35'f32) / 0.45'f32))
  if hatT > 0.0'f32:
    let hatPos = newVector2f(cx, cy - (1.0'f32 - hatT) * pr * 3.0'f32)
    drawTopHat(hatPos, pr, local, alpha * hatT)

  drawSubtitles([t(tkEndCrown1), t(tkEndCrown2)], screenWidth, screenHeight, alpha)

proc drawSignoffShot(local, duration: float32, screenWidth, screenHeight: int32,
                     alpha: float32) =
  let cx = screenWidth.float32 * 0.5'f32
  let cy = screenHeight.float32 * 0.42'f32
  let pulse = sin(local * 3.0'f32) * 0.5'f32 + 0.5'f32
  drawSoftGlow(cx, cy, 300.0'f32, colorA(EndAccent, alpha * (46.0'f32 + pulse * 30.0'f32)), 1.0'f32)

  let pr = 30.0'f32
  drawEquippedPlayerModel(newVector2f(cx, cy), pr * (1.0'f32 + pulse * 0.04'f32),
                          local, alpha, 0.3'f32)
  drawTopHat(newVector2f(cx, cy), pr, local, alpha)

  let titleAlpha = alpha * easeInOut(local / 0.85'f32)
  drawCenteredText(t(tkEndSignoffTitle), screenWidth div 2, (screenHeight * 2 div 3).int32,
                   32, Color(r: 255, g: 255, b: 255, a: alphaByte(titleAlpha * 255.0'f32)))
  drawCenteredText(t(tkEndSignoffSub), screenWidth div 2, (screenHeight * 2 div 3 + 46).int32,
                   21, colorA(EndAccent, titleAlpha * 220.0'f32))

# ---------------------------------------------------------------------------
# Per-shot shake override

proc fallShake(time, local, duration, alpha: float32): float32 =
  sin(time * 38.0'f32) * 2.6'f32 * alpha * (1.0'f32 - easeInOut(local / duration))

# ---------------------------------------------------------------------------
# Backdrop — brightens as the run-time progresses (restore factor)

proc endgameBackdrop(time, totalDuration: float32, sw, sh: int32) =
  let restore = clamp01(time / totalDuration)
  drawSharedBackdrop(sw, sh, time * 0.42'f32,
                     Color(r: 2, g: 6, b: 8, a: 255),
                     Color(r: 6, g: 16, b: 18, a: 255),
                     Color(r: 16, g: 40, b: 36, a: 30),
                     Color(r: 40, g: 120, b: 100, a: alphaByte(36.0'f32 + restore * 24.0'f32)),
                     Color(r: 0, g: 220, b: 170, a: alphaByte(30.0'f32 + restore * 26.0'f32)),
                     0.55, 0.5)

# ---------------------------------------------------------------------------
# Public factory

proc newEndgameCutscene*(): Cutscene =
  newCutscene(
    shots = @[
      CutsceneShot(duration: 5.10'f32, drawProc: drawFallShot,    soundCue: stExplosion,
                   label: t(tkEndRecFall),    iconIndex: 7,
                   glitchMod: 67, glitchWindow: 5, shakeProc: fallShake),
      CutsceneShot(duration: 5.30'f32, drawProc: drawPurgeShot,   soundCue: stShield,
                   label: t(tkEndRecPurge),   iconIndex: 0),
      CutsceneShot(duration: 5.40'f32, drawProc: drawRestoreShot, soundCue: stPowerUp,
                   label: t(tkEndRecRestore), iconIndex: 4),
      CutsceneShot(duration: 5.60'f32, drawProc: drawCrownShot,   soundCue: stWaveComplete,
                   label: t(tkEndRecCrown),   iconIndex: 10),
      CutsceneShot(duration: 5.20'f32, drawProc: drawSignoffShot, soundCue: stMenuSelect,
                   label: t(tkEndRecSignoff), iconIndex: 5),
    ],
    accentColor      = EndAccent,
    titleCardText    = "TopHat-ShooterOS",
    titleCardSub     = t(tkEndTitleCardSub),
    drawBackdropProc = endgameBackdrop,
    swayAmp          = 1.0'f32,
    musicTrack       = mtMenu,
  )

# Keep legacy proc names so main.nim continues to compile without changes.
type EndgameCinematic* = Cutscene

proc newEndgameCinematic*(): EndgameCinematic = newEndgameCutscene()

proc updateEndgameCinematic*(endg: EndgameCinematic, dt: float32) =
  updateCutscene(endg, dt)

proc drawEndgameCinematic*(endg: EndgameCinematic, screenWidth, screenHeight: int) =
  drawCutscene(endg, screenWidth, screenHeight)
