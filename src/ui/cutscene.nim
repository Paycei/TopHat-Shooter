## Generic cutscene framework.
## A Cutscene is an ordered seq[CutsceneShot]; each shot carries its duration,
## a draw callback, an audio sting, a VHS label, and optional shake/glitch overrides.
## The Cutscene object owns all runtime state (time, skip-hold, fast-forward).
## `updateCutscene` / `drawCutscene` are the per-frame entry points.
## Per-cinematic content (the actual shots) lives in the concrete factory modules
## (lore_cinematic.nim, endgame_cinematic.nim, mode_intros.nim).

import raylib, rlgl, math
import ../localization, ../sound, cinematic_common

when defined(mobile):
  const MobileSkipHold* = 1.5'f32
    ## Shorter than the desktop 3.0s hold: touch has no fast-forward to fall
    ## back on, so the skip is the only way out and shouldn't feel like a wait.

type
  CutsceneDrawProc*    = proc(local, duration: float32, sw, sh: int32, alpha: float32)
  CutsceneShakeProc*   = proc(time, local, duration, alpha: float32): float32
  CutsceneBackdropProc* = proc(time, totalDuration: float32, sw, sh: int32)

  CutsceneShot* = object
    duration*:    float32
    drawProc*:    CutsceneDrawProc
    soundCue*:    SoundType
    label*:       string
    iconIndex*:   int
    ## Frame-based tracking-glitch flicker: fires when (frame mod glitchMod) < glitchWindow.
    ## Set glitchMod = 0 to disable entirely.
    glitchMod*:    int
    glitchWindow*: int
    ## Per-shot camX shake.  nil -> cutscene-level swayAmp default.
    shakeProc*: CutsceneShakeProc

  Cutscene* = ref object
    shots*:         seq[CutsceneShot]
    totalDuration*: float32
    accentColor*:   Color
    titleCardText*: string     ## large title drawn on the opening card
    titleCardSub*:  string     ## subtitle under the title (already t()-resolved by caller)
    cornerTag*:     string     ## deck-status chip top-right; "" -> t(tkLoreLive)
    drawBackdropProc*: CutsceneBackdropProc
    swayAmp*:       float32    ## default camX/camY idle sway amplitude
    skipHoldRequired*:  float32
    fastForwardMult*:   float32
    musicTrack*:    MusicTrack
    ## Runtime state
    time*:             float32
    complete*:         bool
    scanlineOffset*:   float32
    frame*:            int
    fastForwardActive*: bool
    skipHoldTimer*:    float32
    lastShotPlayed*:   int

# ---------------------------------------------------------------------------

proc newCutscene*(shots: seq[CutsceneShot],
                  accentColor: Color,
                  titleCardText, titleCardSub: string,
                  drawBackdropProc: CutsceneBackdropProc,
                  swayAmp: float32 = 1.2'f32,
                  skipHoldRequired: float32 = 3.0'f32,
                  fastForwardMult: float32 = 2.0'f32,
                  musicTrack: MusicTrack = mtBoss,
                  cornerTag: string = ""): Cutscene =
  var total = 0.0'f32
  for s in shots: total += s.duration
  # Every cinematic factory takes the 3.0s default; capping here rather than
  # editing nine call sites keeps the mobile hold in one place.
  let holdRequired = when defined(mobile): min(skipHoldRequired, MobileSkipHold)
                     else: skipHoldRequired
  Cutscene(
    shots: shots, totalDuration: total, accentColor: accentColor,
    titleCardText: titleCardText, titleCardSub: titleCardSub, cornerTag: cornerTag,
    drawBackdropProc: drawBackdropProc, swayAmp: swayAmp,
    skipHoldRequired: holdRequired, fastForwardMult: fastForwardMult,
    musicTrack: musicTrack,
    time: 0, complete: false, scanlineOffset: 0, frame: 0,
    fastForwardActive: false, skipHoldTimer: 0, lastShotPlayed: -1
  )

proc resetCutscene*(c: Cutscene) =
  c.time = 0; c.complete = false; c.scanlineOffset = 0; c.frame = 0
  c.fastForwardActive = false; c.skipHoldTimer = 0; c.lastShotPlayed = -1

proc shotAt*(c: Cutscene, time: float32): tuple[idx: int, local: float32, duration: float32] =
  var cursor = 0.0'f32
  for i, shot in c.shots:
    if time < cursor + shot.duration:
      return (i, time - cursor, shot.duration)
    cursor += shot.duration
  let last = c.shots.high
  (last, c.shots[last].duration, c.shots[last].duration)

proc shotFade*(local, duration: float32): float32 =
  min(easeInOut(local / 1.35'f32), easeInOut((duration - local) / 1.55'f32))

# ---------------------------------------------------------------------------

proc updateCutscene*(c: Cutscene, dt: float32) =
  ## The single input path for every cinematic in the game (the lore intro, the
  ## three endgame outros, and the five mode intros all route through here), so
  ## the mobile branch below is what makes all of them skippable at once.
  if c.complete: return
  when defined(mobile):
    # Hold anywhere on screen to skip. No fast-forward: it needs a second
    # simultaneous input to be worth anything, and a cinematic is not the place
    # to teach a two-finger gesture. MobileSkipHold shortens the hold to
    # compensate for losing it.
    c.fastForwardActive = false
    if isMouseButtonDown(MouseButton.Left):
      c.skipHoldTimer = min(c.skipHoldRequired, c.skipHoldTimer + dt)
    else:
      c.skipHoldTimer = 0.0'f32
  else:
    c.fastForwardActive = isKeyDown(Enter)
    if isKeyDown(Space):
      c.skipHoldTimer = min(c.skipHoldRequired, c.skipHoldTimer + dt)
    else:
      c.skipHoldTimer = 0.0'f32
  if c.skipHoldTimer >= c.skipHoldRequired:
    c.complete = true; return
  let playbackDt = dt * (if c.fastForwardActive: c.fastForwardMult else: 1.0'f32)
  c.time        += playbackDt
  c.scanlineOffset += playbackDt * 118.0'f32
  inc c.frame
  let (idx, _, _) = c.shotAt(c.time)
  if idx != c.lastShotPlayed:
    c.lastShotPlayed = idx
    playSound(c.shots[idx].soundCue, 0.6'f32)
  if c.time >= c.totalDuration:
    c.complete = true

proc drawCutscene*(c: Cutscene, sw, sh: int) =
  let (idx, local, duration) = c.shotAt(c.time)
  let alpha = shotFade(local, duration)
  let shot  = c.shots[idx]
  let sW = sw.int32
  let sH = sh.int32

  let camX =
    if not shot.shakeProc.isNil:
      shot.shakeProc(c.time, local, duration, alpha)
    else:
      sin(c.time * 0.7'f32) * c.swayAmp * alpha
  let camY = cos(c.time * 0.84'f32) * (c.swayAmp * 0.83'f32) * alpha

  c.drawBackdropProc(c.time, c.totalDuration, sW, sH)
  drawRectangle(camX.int32 - 8, camY.int32 - 8, sW + 16, sH + 16,
                Color(r: 0, g: 0, b: 0, a: 35))

  pushMatrix()
  translatef(camX, camY, 0.0'f32)
  shot.drawProc(local, duration, sW, sH, alpha)
  popMatrix()

  drawTapeChange(sW, sH, local, c.frame, c.time)

  let fadeIn  = 1.0'f32 - easeInOut(c.time / 0.75'f32)
  let fadeOut = easeInOut((c.time - (c.totalDuration - 0.9'f32)) / 0.9'f32)
  let fadeA   = alphaByte(max(fadeIn, fadeOut) * 255.0'f32)

  let glitchHot = shot.glitchMod > 0 and (c.frame mod shot.glitchMod) < shot.glitchWindow
  drawCinematicOverlay(sW, sH, c.time, c.frame, c.scanlineOffset,
                       c.fastForwardActive, c.skipHoldTimer, c.skipHoldRequired,
                       c.totalDuration, shot.label,
                       (if c.cornerTag.len > 0: c.cornerTag else: t(tkLoreLive)),
                       # Naming Enter/Space would be nonsense on a phone. Both
                       # slots get the same string because fastForwardActive is
                       # always false on mobile.
                       (when defined(mobile): t(tkLoreControlsTouch)
                        else: t(tkLoreControlsFF)),
                       (when defined(mobile): t(tkLoreControlsTouch)
                        else: t(tkLoreControlsFFActive)),
                       shot.iconIndex, glitchHot, c.accentColor)

  # Opening title card: slides in and out over the first ~2 s.
  let appear = clamp01((c.time - 0.2'f32) / 0.5'f32)
  let leave  = clamp01((1.95'f32 - c.time) / 0.5'f32)
  let a = min(appear, leave)
  if a > 0.0'f32:
    let cx = sW div 2
    let cy = sH div 2 - 30
    let ruleW = (sW.float32 * 0.32'f32 * a).int32
    drawRectangle(cx - ruleW, cy - 16, ruleW * 2, 2, colorA(c.accentColor, a * 170.0'f32))
    drawRectangle(cx - ruleW, cy + 54, ruleW * 2, 2, colorA(c.accentColor, a * 170.0'f32))
    drawCenteredText(c.titleCardText, cx, cy, 40,
                     Color(r: 255, g: 255, b: 255, a: alphaByte(a * 255.0'f32)))
    drawCenteredText(c.titleCardSub, cx, (cy + 60).int32, 16,
                     colorA(c.accentColor, a * 200.0'f32))

  if fadeA > 0:
    drawRectangle(0, 0, sW, sH, Color(r: 0, g: 0, b: 0, a: fadeA))
