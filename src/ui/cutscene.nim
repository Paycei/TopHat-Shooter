## Generic cutscene framework.
## A Cutscene is an ordered seq[CutsceneShot]; each shot carries its duration,
## a draw callback, an audio sting, a VHS label, and optional shake/glitch overrides.
## The Cutscene object owns all runtime state (time, skip-hold, fast-forward).
## `updateCutscene` / `drawCutscene` are the per-frame entry points.
## Per-cinematic content (the actual shots) lives in the concrete factory modules
## (lore_cinematic.nim, endgame_cinematic.nim, mode_intros.nim).

import raylib, rlgl, math
import ../localization, ../sound, ../gamepad_input, cinematic_common

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
    muteCue*: bool
      ## Skip `soundCue`: the shot's sound is written into its score instead.

  Cutscene* = ref object
    shots*:         seq[CutsceneShot]
    totalDuration*: float32
    accentColor*:   Color
    titleCardText*: string     ## large title drawn on the opening card; "" = cold open
    titleCardSub*:  string     ## subtitle under the title (already t()-resolved by caller)
    cornerTag*:     string     ## deck-status chip top-right; "" -> t(tkLoreLive)
    speaker*:       string     ## name chip above the captions ("" = none)
    captionCps*:    float32    ## base caption typing speed (characters per second)
    drawBackdropProc*: CutsceneBackdropProc
    swayAmp*:       float32    ## default camX/camY idle sway amplitude
    skipHoldRequired*:  float32
    fastForwardMult*:   float32
    playbackSpeed*:     float32  ## baseline pace; fast-forward multiplies on top
    musicTrack*:    MusicTrack
    ## Runtime state
    time*:             float32
    complete*:         bool
    scanlineOffset*:   float32
    frame*:            int
    fastForwardActive*: bool
    skipHoldTimer*:    float32
    lastShotPlayed*:   int
    scoreStarted:      bool

# ---------------------------------------------------------------------------

const
  CutscenePlaybackSpeed* = StoryPlaybackSpeed
    ## Every cinematic plays at this pace (sound.nim's story timing, because
    ## the story scores are composed against it). Tune there, not per shot.
  SkipHoldSeconds* = 1.5'f32
    ## Hold the skip button this long (real seconds) to leave a cutscene.
  StorySpeaker* = "TOPHAT"
    ## The narrator. Every caption is TOPHAT's incident log; a name, so it is
    ## not translated.

proc newCutscene*(shots: seq[CutsceneShot],
                  accentColor: Color,
                  titleCardText, titleCardSub: string,
                  drawBackdropProc: CutsceneBackdropProc,
                  swayAmp: float32 = 1.2'f32,
                  skipHoldRequired: float32 = SkipHoldSeconds,
                  fastForwardMult: float32 = 2.0'f32,
                  musicTrack: MusicTrack = mtBoss,
                  cornerTag: string = "",
                  playbackSpeed: float32 = CutscenePlaybackSpeed,
                  speaker: string = StorySpeaker,
                  captionCps: float32 = 46.0'f32): Cutscene =
  var total = 0.0'f32
  for s in shots: total += s.duration
  Cutscene(
    shots: shots, totalDuration: total, accentColor: accentColor,
    titleCardText: titleCardText, titleCardSub: titleCardSub, cornerTag: cornerTag,
    speaker: speaker, captionCps: captionCps,
    drawBackdropProc: drawBackdropProc, swayAmp: swayAmp,
    skipHoldRequired: skipHoldRequired, fastForwardMult: fastForwardMult,
    playbackSpeed: playbackSpeed, musicTrack: musicTrack,
    time: 0, complete: false, scanlineOffset: 0, frame: 0,
    fastForwardActive: false, skipHoldTimer: 0, lastShotPlayed: -1
  )

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
  if c.complete: return
  # Keyboard ENTER / pad A fast-forward; keyboard SPACE / pad B hold to skip.
  c.fastForwardActive = isKeyDown(Enter) or isGamepadConfirmDown()
  if isKeyDown(Space) or isGamepadBackDown():
    c.skipHoldTimer = min(c.skipHoldRequired, c.skipHoldTimer + dt)
  else:
    c.skipHoldTimer = 0.0'f32
  if c.skipHoldTimer >= c.skipHoldRequired:
    c.complete = true; return
  # The skip hold above stays on real time: "hold 3s" means three real seconds.
  let rate = if c.fastForwardActive: c.fastForwardMult else: 1.0'f32
  let playbackDt = dt * c.playbackSpeed * rate
  c.time        += playbackDt
  c.scanlineOffset += playbackDt * 118.0'f32
  inc c.frame
  # A story score is composed against this clock: start it once (retrying
  # until the stream is ready), then keep it on the clock. Fast-forward raises
  # its pitch with its speed, like the tape it is pretending to be.
  if isScoreTrack(c.musicTrack):
    if not c.scoreStarted:
      c.scoreStarted = startScore(c.musicTrack)
    syncScore(c.musicTrack, c.time / c.playbackSpeed, rate)
  else:
    playMusic(c.musicTrack)
  let (idx, _, _) = c.shotAt(c.time)
  if idx != c.lastShotPlayed:
    c.lastShotPlayed = idx
    if not c.shots[idx].muteCue:
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
  # Captions inside the shot type out against the shot's own clock.
  captionClock = local
  captionShotDuration = duration
  captionSpeaker = c.speaker
  captionAccent = c.accentColor
  captionCharsPerSec = c.captionCps
  shot.drawProc(local, duration, sW, sH, alpha)
  captionClock = -1.0'f32
  captionSpeaker = ""
  popMatrix()

  drawTapeChange(sW, sH, local, c.frame, c.time)

  let fadeIn  = 1.0'f32 - easeInOut(c.time / 0.75'f32)
  let fadeOut = easeInOut((c.time - (c.totalDuration - 0.9'f32)) / 0.9'f32)
  let fadeA   = alphaByte(max(fadeIn, fadeOut) * 255.0'f32)

  let glitchHot = shot.glitchMod > 0 and (c.frame mod shot.glitchMod) < shot.glitchWindow
  let pad = isGamepadActive()
  let skipProgress = clamp01(c.skipHoldTimer / c.skipHoldRequired)
  let controls = CinematicControls(
    ffKey: (if pad: gamepadBindLabel(GamepadButton.RightFaceDown) else: t(tkLoreKeyEnter)),
    ffLabel: (if c.fastForwardActive: t(tkLoreFastForwarding) else: t(tkLoreHoldFastForward)),
    skipKey: (if pad: gamepadBindLabel(GamepadButton.RightFaceRight) else: t(tkLoreKeySpace)),
    skipLabel: (if skipProgress > 0.0'f32: t(tkLoreSkipping) else: t(tkLoreHoldSkip)),
    ffActive: c.fastForwardActive,
    skipProgress: skipProgress)
  drawCinematicOverlay(sW, sH, c.time, c.frame, c.scanlineOffset, c.totalDuration, shot.label,
                       (if c.cornerTag.len > 0: c.cornerTag else: t(tkLoreLive)),
                       shot.iconIndex, glitchHot, controls, c.accentColor)

  # Opening title card: slides in and out over the first ~2 s. A cold open
  # (empty title) skips it and drops its own title later.
  let appear = clamp01((c.time - 0.2'f32) / 0.5'f32)
  let leave  = clamp01((1.95'f32 - c.time) / 0.5'f32)
  let a = min(appear, leave)
  if a > 0.0'f32 and c.titleCardText.len > 0:
    let cx = sW div 2
    let cy = sH div 2 - 30
    # A dark band behind the card: it reads as the tape's label laid over the
    # scene, not as text competing with it.
    drawRectangle(0, cy - 34, sW, 128, Color(r: 0, g: 0, b: 0, a: alphaByte(a * 165.0'f32)))
    let ruleW = (sW.float32 * 0.32'f32 * a).int32
    drawRectangle(cx - ruleW, cy - 16, ruleW * 2, 2, colorA(c.accentColor, a * 170.0'f32))
    drawRectangle(cx - ruleW, cy + 54, ruleW * 2, 2, colorA(c.accentColor, a * 170.0'f32))
    drawCenteredText(c.titleCardText, cx, cy, 40,
                     Color(r: 255, g: 255, b: 255, a: alphaByte(a * 255.0'f32)))
    drawCenteredText(c.titleCardSub, cx, (cy + 60).int32, 16,
                     colorA(c.accentColor, a * 200.0'f32))

  if fadeA > 0:
    drawRectangle(0, 0, sW, sH, Color(r: 0, g: 0, b: 0, a: fadeA))
