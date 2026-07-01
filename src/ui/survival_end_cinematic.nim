## Survival Ending Cinematic, "The Long Watch" epilogue.
## Plays on death in Time Survival once the run has lasted long enough to earn it
## (>= 15 minutes; the trigger lives in game/death.nim). Unlike the triumphant
## wave/roguelite outros this is a eulogy: the process is logged for how long it
## held the breach, even though it finally fell. Built from the generic framework
## in cutscene.nim so it shares the same archive chrome.

import raylib, rlgl, math
import particle_types
import background_fx, ../types, ../localization, ../sound,
       cinematic_common, cutscene

const
  SurAccent* = Color(r: 255, g: 120, b: 50, a: 255)   # ember-orange "long watch"

# ---------------------------------------------------------------------------
# Shot draw procs

proc drawWatchShot(local, duration: float32, screenWidth, screenHeight: int32,
                   alpha: float32) =
  ## The long watch: an uptime ring sweeps round and round while the swarm presses
  ## from the dark edges and the lone process holds the center.
  let cx = screenWidth.float32 * 0.5'f32
  let cy = screenHeight.float32 * 0.46'f32

  drawSoftGlow(cx, cy, 200.0'f32, colorA(SurAccent, alpha * 44.0'f32), 1.0'f32)

  # Uptime dial: a slow full sweep, ticked like a clock face.
  let sweep = (local / duration) * 360.0'f32
  drawRing(Vector2(x: cx, y: cy), 88.0'f32, 92.0'f32, -90.0'f32, -90.0'f32 + sweep, 48,
           colorA(SurAccent, alpha * 210.0'f32))
  drawCircleLines(Vector2(x: cx, y: cy), 90.0'f32, colorA(SurAccent, alpha * 70.0'f32))
  for i in 0..<12:
    let a = i.float32 * PI * 2.0'f32 / 12.0'f32 - PI * 0.5'f32
    drawLine((cx + cos(a) * 82.0'f32).int32, (cy + sin(a) * 82.0'f32).int32,
             (cx + cos(a) * 90.0'f32).int32, (cy + sin(a) * 90.0'f32).int32,
             colorA(SurAccent, alpha * 130.0'f32))

  # The swarm circling at the edge of the light, kept at bay minute after minute.
  let enemyKinds = [etCircle, etCube, etTriangle, etStar, etCross, etDiamond, etOctagon, etPentagon]
  for i in 0..<14:
    let a = i.float32 * PI * 2.0'f32 / 14.0'f32 + local * 0.3'f32
    let r = 150.0'f32 + sin(local * 1.4'f32 + i.float32) * 22.0'f32
    let ex = cx + cos(a) * r
    let ey = cy + sin(a) * r * 0.72'f32
    drawRealEnemy(enemyKinds[i mod enemyKinds.len], ex, ey, 11.0'f32, local, i,
                  if i mod 6 == 0: 1 else: 0)

  # The defender, steady at the heart of the dial.
  drawEquippedPlayerModel(newVector2f(cx, cy), 24.0'f32, local, alpha, 0.24'f32)

  drawSubtitles([t(tkSurEndWatch1), t(tkSurEndWatch2)], screenWidth, screenHeight, alpha)

proc drawSurgeShot(local, duration: float32, screenWidth, screenHeight: int32,
                   alpha: float32) =
  ## The final surge: the swarm collapses inward all at once and the line breaks.
  let cx = screenWidth.float32 * 0.5'f32
  let cy = screenHeight.float32 * 0.48'f32
  let close = easeInOut(local / duration)

  # Pressure vignette closing from every side.
  let vig = alphaByte(alpha * close * 90.0'f32)
  drawRectangleGradientH(0, 0, (screenWidth.float32 * 0.4'f32).int32, screenHeight,
                         Color(r: 255, g: 40, b: 20, a: vig), Color(r: 255, g: 40, b: 20, a: 0))
  drawRectangleGradientH(screenWidth - (screenWidth.float32 * 0.4'f32).int32, 0,
                         (screenWidth.float32 * 0.4'f32).int32, screenHeight,
                         Color(r: 255, g: 40, b: 20, a: 0), Color(r: 255, g: 40, b: 20, a: vig))

  # Enemies rushing the center from all directions.
  let enemyKinds = [etCircle, etCube, etTriangle, etStar, etCross, etDiamond, etOctagon]
  for i in 0..<24:
    let ang = fractCoord(sin(i.float32 * 7.13'f32) * 43758.5453'f32) * PI * 2.0'f32
    let startR = 360.0'f32 + fractCoord(i.float32 * 3.7'f32) * 160.0'f32
    let r = startR * (1.0'f32 - close * 0.86'f32)
    let ex = cx + cos(ang) * r
    let ey = cy + sin(ang) * r * 0.8'f32
    let sz = 10.0'f32 + (i mod 4).float32 * 3.0'f32
    let vx = -cos(ang) * 120.0'f32
    let vy = -sin(ang) * 120.0'f32
    drawRealEnemy(enemyKinds[i mod enemyKinds.len], ex, ey, sz, local, i,
                  if i mod 5 == 0: 2 else: 0, newVector2f(vx, vy))

  # The defender flaring under the pressure.
  let flare = 0.24'f32 + close * 0.5'f32 + sin(local * 9.0'f32) * 0.1'f32
  drawSoftGlow(cx, cy, 70.0'f32 + close * 30.0'f32, colorA(SurAccent, alpha * (60.0'f32 + close * 60.0'f32)), 1.0'f32)
  drawEquippedPlayerModel(newVector2f(cx, cy), 24.0'f32, local, alpha, flare)

  drawSubtitles([t(tkSurEndSurge1), t(tkSurEndSurge2)], screenWidth, screenHeight, alpha)

proc drawSurFallShot(local, duration: float32, screenWidth, screenHeight: int32,
                     alpha: float32) =
  ## Signal lost: the process flickers and goes dark, scattering into embers.
  let cx = screenWidth.float32 * 0.5'f32
  let cy = screenHeight.float32 * 0.46'f32
  let fade = easeInOut(local / duration)
  # Flicker collapses toward darkness.
  let flicker = (1.0'f32 - fade) * (0.55'f32 + 0.45'f32 * (sin(local * 17.0'f32) * 0.5'f32 + 0.5'f32))

  drawSoftGlow(cx, cy, 200.0'f32 * (1.0'f32 - fade * 0.6'f32),
               colorA(SurAccent, alpha * flicker * 60.0'f32), 1.0'f32)

  # Embers scattering outward as the process disperses.
  for i in 0..<26:
    let ang = fractCoord(sin(i.float32 * 9.71'f32) * 43758.5453'f32) * PI * 2.0'f32
    let dist = fade * (60.0'f32 + fractCoord(i.float32 * 4.3'f32) * 280.0'f32)
    let px = cx + cos(ang) * dist
    let py = cy + sin(ang) * dist - fade * 40.0'f32   # drift upward like sparks
    drawCircle(Vector2(x: px, y: py), 2.6'f32 * (1.0'f32 - fade) + 0.6'f32,
               colorA(SurAccent, alpha * (1.0'f32 - fade) * 200.0'f32))

  # The dimming process itself.
  if flicker > 0.02'f32:
    drawEquippedPlayerModel(newVector2f(cx, cy), 24.0'f32 * (1.0'f32 - fade * 0.4'f32),
                            local, alpha * flicker, 0.2'f32)

  # A brief whole-frame dim-out at the moment of loss.
  let dark = clamp01((fade - 0.55'f32) / 0.4'f32)
  if dark > 0.0'f32:
    drawRectangle(0, 0, screenWidth, screenHeight,
                  Color(r: 0, g: 0, b: 0, a: alphaByte(alpha * dark * 120.0'f32)))

  drawSubtitles([t(tkSurEndFall1), t(tkSurEndFall2)], screenWidth, screenHeight, alpha)

proc drawShutdownShot(local, duration: float32, screenWidth, screenHeight: int32,
                      alpha: float32) =
  ## SYSTEM HALTED: the kernel's status lights go dark one by one, then the display
  ## itself powers off with a CRT collapse - the bookend to the BIOS boot splash.
  let cx = screenWidth.float32 * 0.5'f32
  let cy = screenHeight.float32 * 0.46'f32
  let t01 = local / duration

  # The frame is already mostly dark and only gets darker.
  drawRectangle(0, 0, screenWidth, screenHeight,
                Color(r: 0, g: 0, b: 0, a: alphaByte(alpha * (110.0'f32 + t01 * 90.0'f32))))

  # Grid of kernel status lights extinguishing in sequence over the first ~70%.
  const cols = 6
  const rows = 3
  let total = cols * rows
  let lit = clamp01(t01 / 0.7'f32)   # lights finish extinguishing at 70% of the shot
  let gapX = 46.0'f32
  let gapY = 40.0'f32
  let originX = cx - (cols - 1).float32 * gapX * 0.5'f32
  let originY = cy - (rows - 1).float32 * gapY * 0.5'f32
  for r in 0..<rows:
    for c in 0..<cols:
      let idx = r * cols + c
      # Lights go out left-to-right, top-to-bottom as `lit` advances.
      let off = lit * total.float32 > idx.float32 + 1.0'f32
      let lx = originX + c.float32 * gapX
      let ly = originY + r.float32 * gapY
      if off:
        drawCircleLines(Vector2(x: lx, y: ly), 5.0'f32,
                        colorA(SurAccent, alpha * 28.0'f32))
      else:
        let flick = 0.7'f32 + 0.3'f32 * (sin(local * 12.0'f32 + idx.float32) * 0.5'f32 + 0.5'f32)
        drawSoftGlow(lx, ly, 16.0'f32, colorA(SurAccent, alpha * flick * 70.0'f32), 1.0'f32)
        drawCircle(Vector2(x: lx, y: ly), 5.0'f32, colorA(SurAccent, alpha * flick * 230.0'f32))

  # CRT power-off collapse over the final ~30%: image crushes to a bright scanline,
  # then to a center dot, then nothing.
  let off01 = clamp01((t01 - 0.7'f32) / 0.3'f32)
  if off01 > 0.0'f32:
    # Black out the grid region as the tube discharges.
    drawRectangle(0, 0, screenWidth, screenHeight,
                  Color(r: 0, g: 0, b: 0, a: alphaByte(alpha * off01 * 255.0'f32)))
    let collapse = easeInOut(off01)
    if collapse < 0.85'f32:
      # Horizontal scanline spanning a width that shrinks toward a point.
      let lineW = screenWidth.float32 * (1.0'f32 - collapse) + 4.0'f32
      let lineH = 3.0'f32 + (1.0'f32 - collapse) * 2.0'f32
      drawRectangle((cx - lineW * 0.5'f32).int32, (cy - lineH * 0.5'f32).int32,
                    lineW.int32, lineH.int32,
                    Color(r: 255, g: 255, b: 255, a: alphaByte(alpha * 235.0'f32)))
    else:
      # Final dying pinpoint.
      let dot = (1.0'f32 - (collapse - 0.85'f32) / 0.15'f32) * 4.0'f32
      if dot > 0.2'f32:
        drawCircle(Vector2(x: cx, y: cy), dot,
                   Color(r: 255, g: 255, b: 255, a: alphaByte(alpha * 235.0'f32)))

  drawSubtitles([t(tkSurEndShutdown1), t(tkSurEndShutdown2)], screenWidth, screenHeight, alpha)

proc drawSurSignoffShot(local, duration: float32, screenWidth, screenHeight: int32,
                        alpha: float32) =
  ## The watch remembered: a single ember holds against the dark while the log is
  ## recorded. The tone is quiet, not triumphant.
  let cx = screenWidth.float32 * 0.5'f32
  let cy = screenHeight.float32 * 0.42'f32
  let pulse = sin(local * 2.0'f32) * 0.5'f32 + 0.5'f32

  drawSoftGlow(cx, cy, 240.0'f32, colorA(SurAccent, alpha * (32.0'f32 + pulse * 22.0'f32)), 1.0'f32)

  # A lone, slowly-pulsing ember mark where the process stood.
  drawCircle(Vector2(x: cx, y: cy), 7.0'f32 + pulse * 2.0'f32, colorA(SurAccent, alpha * 230.0'f32))
  drawCircleLines(Vector2(x: cx, y: cy), 22.0'f32 + pulse * 6.0'f32, colorA(SurAccent, alpha * 140.0'f32))
  drawCircleLines(Vector2(x: cx, y: cy), 40.0'f32 + pulse * 10.0'f32, colorA(SurAccent, alpha * 70.0'f32))

  let titleAlpha = alpha * easeInOut(local / 0.85'f32)
  drawCenteredText(t(tkSurEndSignoffTitle), screenWidth div 2, (screenHeight * 2 div 3).int32,
                   32, Color(r: 255, g: 255, b: 255, a: alphaByte(titleAlpha * 255.0'f32)))
  drawCenteredText(t(tkSurEndSignoffSub), screenWidth div 2, (screenHeight * 2 div 3 + 46).int32,
                   21, colorA(SurAccent, titleAlpha * 220.0'f32))

# ---------------------------------------------------------------------------
# Per-shot shake overrides

proc surgeShake(time, local, duration, alpha: float32): float32 =
  sin(time * 40.0'f32) * 2.8'f32 * alpha * easeInOut(local / duration)

proc fallShake(time, local, duration, alpha: float32): float32 =
  sin(time * 30.0'f32) * 2.2'f32 * alpha * (1.0'f32 - easeInOut(local / duration))

# ---------------------------------------------------------------------------
# Backdrop, cools from ember toward ash over the eulogy.

proc survivalBackdrop(time, totalDuration: float32, sw, sh: int32) =
  let cool = clamp01(time / totalDuration)
  drawSharedBackdrop(sw, sh, time * 0.40'f32,
                     Color(r: 6, g: 3, b: 2, a: 255),
                     Color(r: 14, g: 8, b: 6, a: 255),
                     Color(r: 40, g: 20, b: 12, a: 30),
                     Color(r: 150, g: 70, b: 30, a: alphaByte(40.0'f32 - cool * 22.0'f32)),
                     Color(r: 255, g: 110, b: 40, a: alphaByte(34.0'f32 - cool * 20.0'f32)),
                     0.55, 0.5)

# ---------------------------------------------------------------------------
# Public factory

proc newSurvivalEndCutscene*(): Cutscene =
  newCutscene(
    shots = @[
      CutsceneShot(duration: 5.20'f32, drawProc: drawWatchShot,     soundCue: stShield,
                   label: t(tkSurEndRecWatch),   iconIndex: 4),
      CutsceneShot(duration: 4.80'f32, drawProc: drawSurgeShot,     soundCue: stExplosion,
                   label: t(tkSurEndRecSurge),   iconIndex: 0,
                   glitchMod: 59, glitchWindow: 6, shakeProc: surgeShake),
      CutsceneShot(duration: 4.60'f32, drawProc: drawSurFallShot,   soundCue: stTeleport,
                   label: t(tkSurEndRecFall),    iconIndex: 7,
                   glitchMod: 41, glitchWindow: 7, shakeProc: fallShake),
      CutsceneShot(duration: 5.00'f32, drawProc: drawShutdownShot,  soundCue: stMenuSelect,
                   label: t(tkSurEndRecShutdown), iconIndex: 5,
                   glitchMod: 37, glitchWindow: 9, shakeProc: fallShake),
      CutsceneShot(duration: 4.80'f32, drawProc: drawSurSignoffShot, soundCue: stMenuSelect,
                   label: t(tkSurEndRecSignoff), iconIndex: 5),
    ],
    accentColor      = SurAccent,
    titleCardText    = "TopHat-ShooterOS",
    titleCardSub     = t(tkSurEndTitleCardSub),
    drawBackdropProc = survivalBackdrop,
    swayAmp          = 1.0'f32,
    musicTrack       = mtMenu,
  )

# Legacy-style wrappers so main.nim mirrors the endgame-cinematic call sites.
type SurvivalEndCinematic* = Cutscene

proc newSurvivalEndCinematic*(): SurvivalEndCinematic = newSurvivalEndCutscene()

proc updateSurvivalEndCinematic*(c: SurvivalEndCinematic, dt: float32) =
  updateCutscene(c, dt)

proc drawSurvivalEndCinematic*(c: SurvivalEndCinematic, screenWidth, screenHeight: int) =
  drawCutscene(c, screenWidth, screenHeight)
