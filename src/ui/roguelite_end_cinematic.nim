## Roguelite Ending Cinematic, "Deep Recovery" outro.
## Plays once the first time the final-floor boss falls (the DELVE archive). Built
## from the generic framework in cutscene.nim, exactly like the wave-mode outro in
## endgame_cinematic.nim, so it reads as a sibling of the other archive tapes.
## Theme: a descent through the corrupted recursion to the core, data extraction,
## and a climb back to the surface with the recovered cores in hand.

import raylib, rlgl, math
import particle_types, background_fx, ../shapes, ../localization, ../sound, cinematic_common, cutscene

const
  RogAccent* = Color(r: 255, g: 190, b: 70, a: 255)   # recovered-data amber/gold

# ---------------------------------------------------------------------------
# Shot draw procs

proc drawDescendShot(local, duration: float32, screenWidth, screenHeight: int32,
                     alpha: float32) =
  ## Falling inward through nested sector rings: concentric polygons rush past the
  ## camera toward a single vanishing point as the player-process descends.
  let cx = screenWidth.float32 * 0.5'f32
  let cy = screenHeight.float32 * 0.46'f32
  let dive = easeInOut(local / duration)

  drawSoftGlow(cx, cy, 200.0'f32, colorA(RogAccent, alpha * 46.0'f32), 1.0'f32)

  # Recursion stack: rings spiral inward, each one a deeper floor.
  for i in 0..<11:
    let phase = fractCoord(local * 0.32'f32 + i.float32 / 11.0'f32)
    let r = (28.0'f32 + phase * 360.0'f32)
    let sides = 4 + (i mod 4).int32
    let rot = local * (18.0'f32 + i.float32 * 4.0'f32) + i.float32 * 21.0'f32
    let ringA = alpha * (1.0'f32 - phase) * 150.0'f32
    drawPolyLines(Vector2(x: cx, y: cy), sides, r, rot,
                  Color(r: 255, g: 170, b: 60, a: alphaByte(ringA)))
    if i mod 2 == 0:
      drawPolyLines(Vector2(x: cx, y: cy), sides, r * 0.62'f32, -rot * 1.3'f32,
                    Color(r: 200, g: 90, b: 255, a: alphaByte(ringA * 0.5'f32)))

  # Falling shards streak past toward the vanishing point.
  for i in 0..<16:
    let ang = fractCoord(sin(i.float32 * 12.9898'f32) * 43758.5453'f32) * PI * 2.0'f32
    let p = fractCoord(local * 0.6'f32 + i.float32 * 0.063'f32)
    let dist = (1.0'f32 - p) * 320.0'f32 + 30.0'f32
    let px = cx + cos(ang) * dist
    let py = cy + sin(ang) * dist * 0.7'f32
    drawLine(px.int32, py.int32, cx.int32, cy.int32,
             colorA(RogAccent, alpha * (1.0'f32 - p) * 30.0'f32))
    drawCircle(Vector2(x: px, y: py), 2.4'f32 * (1.0'f32 - p) + 0.6'f32,
               colorA(RogAccent, alpha * (1.0'f32 - p) * 180.0'f32))

  # The descending process, shrinking as it falls deeper.
  let pr = 26.0'f32 * (1.0'f32 - dive * 0.35'f32)
  drawEquippedPlayerModel(newVector2f(cx, cy), pr, local, alpha, 0.25'f32)

  drawSubtitles([t(tkRogEndDescend1), t(tkRogEndDescend2)], screenWidth, screenHeight, alpha)

proc drawCoreShot(local, duration: float32, screenWidth, screenHeight: int32,
                  alpha: float32) =
  ## The corrupted core at the base of the recursion: a dark seed wrapped in
  ## fracturing containment, leaking corruption.
  let reveal = easeOut(local / (duration * 0.7'f32))
  let cx = screenWidth.float32 * 0.5'f32
  let cy = screenHeight.float32 * 0.44'f32
  let pulse = sin(local * 2.4'f32) * 0.5'f32 + 0.5'f32

  drawSoftGlow(cx, cy, 260.0'f32 * reveal, Color(r: 180, g: 40, b: 255, a: alphaByte(alpha * 60.0'f32)), 1.0'f32)

  # Containment arcs failing around the seed.
  for ring in 0..<4:
    let rr = (50.0'f32 + ring.float32 * 34.0'f32) * reveal
    let dir = if ring mod 2 == 0: 1.0'f32 else: -1.0'f32
    let base = local * dir * (24.0'f32 + ring.float32 * 12.0'f32)
    for seg in 0..<3:
      let start = base + seg.float32 * 120.0'f32
      drawRing(Vector2(x: cx, y: cy), rr - 1.5'f32, rr + 1.5'f32, start, start + 54.0'f32, 22,
               colorA(RogAccent, alpha * (130.0'f32 - ring.float32 * 22.0'f32)))

  # The seed: a dark hexagon with an amber fault-line core.
  let seedR = 40.0'f32 * reveal * (0.94'f32 + pulse * 0.06'f32)
  drawPoly(Vector2(x: cx, y: cy), 6, seedR, local * 16.0'f32,
           Color(r: 24, g: 8, b: 30, a: alphaByte(alpha * 245.0'f32)))
  drawPolyLines(Vector2(x: cx, y: cy), 6, seedR, local * 16.0'f32,
                Color(r: 230, g: 70, b: 255, a: alphaByte(alpha * 220.0'f32)))
  # Corruption fault-lines cracking outward.
  for i in 0..<6:
    let a = local * 0.6'f32 + i.float32 * PI / 3.0'f32
    let len = seedR * (1.2'f32 + pulse * 0.4'f32)
    drawLine(cx.int32, cy.int32, (cx + cos(a) * len).int32, (cy + sin(a) * len).int32,
             colorA(RogAccent, alpha * (90.0'f32 + pulse * 90.0'f32)))
  drawCircle(Vector2(x: cx, y: cy), seedR * 0.32'f32 * (0.8'f32 + pulse * 0.2'f32),
             colorA(RogAccent, alpha * 235.0'f32))

  drawSubtitles([t(tkRogEndCore1), t(tkRogEndCore2)], screenWidth, screenHeight, alpha)

proc drawExtractShot(local, duration: float32, screenWidth, screenHeight: int32,
                     alpha: float32) =
  ## Data extraction: shards (diamonds) tear loose from the core and stream out to
  ## the player as the loop unwinds; recovered cores orbit.
  let cx = screenWidth.float32 * 0.5'f32
  let cy = screenHeight.float32 * 0.46'f32
  let progress = easeInOut(local / duration)

  drawSoftGlow(cx, cy, 230.0'f32, colorA(RogAccent, alpha * 50.0'f32), 1.0'f32)

  # Shards streaming outward from the core, unwinding the loop.
  for i in 0..<22:
    let ang = i.float32 * PI * 2.0'f32 / 22.0'f32 + local * 0.5'f32
    let spread = fractCoord(local * 0.7'f32 + i.float32 * 0.045'f32)
    let dist = spread * (180.0'f32 + (i mod 3).float32 * 40.0'f32)
    let px = cx + cos(ang) * dist
    let py = cy + sin(ang) * dist
    let sz = 6.0'f32 * (1.0'f32 - spread) + 1.5'f32
    drawPoly(Vector2(x: px, y: py), 4, sz, local * 120.0'f32 + i.float32 * 40.0'f32,
             colorA(RogAccent, alpha * (1.0'f32 - spread) * 210.0'f32))

  # Orbiting recovered cores.
  for i in 0..<5:
    let a = local * 1.1'f32 + i.float32 * PI * 2.0'f32 / 5.0'f32
    let orx = cx + cos(a) * 96.0'f32
    let ory = cy + sin(a) * 96.0'f32 * 0.7'f32
    drawSoftGlow(orx, ory, 22.0'f32, colorA(RogAccent, alpha * 70.0'f32), 1.0'f32)
    drawPoly(Vector2(x: orx, y: ory), 6, 9.0'f32, local * 60.0'f32 + i.float32 * 30.0'f32,
             Color(r: 255, g: 210, b: 110, a: alphaByte(alpha * 235.0'f32)))

  # The process gathering the payload at the center.
  drawEquippedPlayerModel(newVector2f(cx, cy), 28.0'f32, local, alpha, 0.3'f32 + progress * 0.2'f32)

  drawSubtitles([t(tkRogEndExtract1), t(tkRogEndExtract2)], screenWidth, screenHeight, alpha)

proc drawRevealShot(local, duration: float32, screenWidth, screenHeight: int32,
                    alpha: float32) =
  ## ORIGIN EXPOSED: in the seed's dying light, the truth is laid bare. A single
  ## flash peaks mid-shot and burns away the seed to expose an ancient lattice
  ## behind it - a structure older than the OS, proof the breach only woke the Root.
  let cx = screenWidth.float32 * 0.5'f32
  let cy = screenHeight.float32 * 0.45'f32
  # Flash envelope: rises to a hard peak near the middle, then settles.
  let t01 = local / duration
  let flash = exp(-((t01 - 0.42'f32) * (t01 - 0.42'f32)) / 0.018'f32)
  let settle = easeOut(clamp01((t01 - 0.5'f32) / 0.5'f32))

  drawSoftGlow(cx, cy, 200.0'f32 + flash * 260.0'f32,
               colorA(RogAccent, alpha * (40.0'f32 + flash * 150.0'f32)), 1.0'f32)

  # The ancient lattice revealed behind the seed: nested rotating polygons in a
  # cold violet, fading up as the seed burns away. Older geometry than the gold.
  for i in 0..<7:
    let r = 40.0'f32 + i.float32 * 30.0'f32
    let sides = 6'i32
    let rot = local * (6.0'f32 + i.float32 * 2.0'f32) * (if i mod 2 == 0: 1.0'f32 else: -1.0'f32)
    let latA = alpha * settle * (140.0'f32 - i.float32 * 14.0'f32)
    drawPolyLines(Vector2(x: cx, y: cy), sides, r, rot,
                  Color(r: 150, g: 60, b: 255, a: alphaByte(latA)))

  # Radial truth-rays firing out at the flash peak.
  for i in 0..<24:
    let a = i.float32 * PI * 2.0'f32 / 24.0'f32 + local * 0.2'f32
    let len = 60.0'f32 + flash * 360.0'f32
    drawLine(cx.int32, cy.int32,
             (cx + cos(a) * len).int32, (cy + sin(a) * len).int32,
             colorA(RogAccent, alpha * flash * 120.0'f32))

  # The seed itself, dimming and shrinking as the flash consumes it.
  let seedR = 38.0'f32 * (1.0'f32 - settle * 0.55'f32)
  drawPoly(Vector2(x: cx, y: cy), 6, seedR, local * 16.0'f32,
           Color(r: 24, g: 8, b: 30, a: alphaByte(alpha * (1.0'f32 - settle) * 240.0'f32)))
  drawCircle(Vector2(x: cx, y: cy), seedR * 0.34'f32,
             colorA(RogAccent, alpha * (60.0'f32 + flash * 195.0'f32)))

  drawSubtitles([t(tkRogEndReveal1), t(tkRogEndReveal2)], screenWidth, screenHeight, alpha)

proc drawAscendShot(local, duration: float32, screenWidth, screenHeight: int32,
                    alpha: float32) =
  ## Climbing back up the collapsing stack: rings expand outward (the inverse of the
  ## descent) and light rises as the player surfaces with the cores.
  let rise = easeInOut(local / duration)
  let cx = screenWidth.float32 * 0.5'f32
  let cy = screenHeight.float32 * (0.54'f32 - rise * 0.08'f32)

  # Rising light columns.
  for i in -2..2:
    let bx = cx + i.float32 * 50.0'f32
    drawRectangleGradientV(bx.int32 - 5, 0, 10, screenHeight,
                           colorA(RogAccent, 0.0'f32),
                           colorA(RogAccent, alpha * rise * 46.0'f32))
  drawSoftGlow(cx, cy, 200.0'f32 * rise + 60.0'f32, colorA(RogAccent, alpha * (40.0'f32 + rise * 36.0'f32)), 1.0'f32)

  # Expanding rings: the recursion releasing its grip.
  for i in 0..<9:
    let phase = fractCoord(local * 0.4'f32 + i.float32 / 9.0'f32)
    let r = phase * 330.0'f32 + 20.0'f32
    let sides = 4 + (i mod 4).int32
    drawPolyLines(Vector2(x: cx, y: cy), sides, r, -local * 16.0'f32 + i.float32 * 18.0'f32,
                  colorA(RogAccent, alpha * (1.0'f32 - phase) * 130.0'f32))

  # Rising spark motes.
  for i in 0..<18:
    let p = fractCoord(local * 0.5'f32 + i.float32 * 0.117'f32)
    let sx = cx + sin(i.float32 * 2.1'f32 + local) * (40.0'f32 + i.float32 * 5.0'f32)
    let sy = screenHeight.float32 * 0.94'f32 - p * screenHeight.float32 * 0.78'f32
    drawCircle(Vector2(x: sx, y: sy), 2.4'f32 * (1.0'f32 - p),
               colorA(RogAccent, alpha * (1.0'f32 - p) * 200.0'f32))

  let pr = 28.0'f32 * (0.84'f32 + rise * 0.16'f32)
  drawEquippedPlayerModel(newVector2f(cx, cy), pr, local, alpha, 0.3'f32 + rise * 0.25'f32)

  drawSubtitles([t(tkRogEndAscend1), t(tkRogEndAscend2)], screenWidth, screenHeight, alpha)

proc drawRogSignoffShot(local, duration: float32, screenWidth, screenHeight: int32,
                        alpha: float32) =
  let cx = screenWidth.float32 * 0.5'f32
  let cy = screenHeight.float32 * 0.42'f32
  let pulse = sin(local * 3.0'f32) * 0.5'f32 + 0.5'f32
  drawSoftGlow(cx, cy, 300.0'f32, colorA(RogAccent, alpha * (46.0'f32 + pulse * 30.0'f32)), 1.0'f32)

  # A small constellation of recovered cores haloing the survivor.
  for i in 0..<6:
    let a = local * 0.7'f32 + i.float32 * PI * 2.0'f32 / 6.0'f32
    let orx = cx + cos(a) * 78.0'f32
    let ory = cy + sin(a) * 50.0'f32
    drawPoly(Vector2(x: orx, y: ory), 6, 6.0'f32, local * 50.0'f32 + i.float32 * 30.0'f32,
             colorA(RogAccent, alpha * 210.0'f32))

  let pr = 30.0'f32
  drawEquippedPlayerModel(newVector2f(cx, cy), pr * (1.0'f32 + pulse * 0.04'f32),
                          local, alpha, 0.3'f32)
  drawTopHat(newVector2f(cx, cy), pr, local, alpha)

  let titleAlpha = alpha * easeInOut(local / 0.85'f32)
  drawCenteredText(t(tkRogEndSignoffTitle), screenWidth div 2, (screenHeight * 2 div 3).int32,
                   32, Color(r: 255, g: 255, b: 255, a: alphaByte(titleAlpha * 255.0'f32)))
  drawCenteredText(t(tkRogEndSignoffSub), screenWidth div 2, (screenHeight * 2 div 3 + 46).int32,
                   21, colorA(RogAccent, titleAlpha * 220.0'f32))

# ---------------------------------------------------------------------------
# Per-shot shake override

proc coreShake(time, local, duration, alpha: float32): float32 =
  sin(time * 33.0'f32) * 2.4'f32 * alpha

# ---------------------------------------------------------------------------
# Backdrop, warms toward gold as the recovery succeeds.

proc rogueliteBackdrop(time, totalDuration: float32, sw, sh: int32) =
  let recover = clamp01(time / totalDuration)
  drawSharedBackdrop(sw, sh, time * 0.44'f32,
                     Color(r: 8, g: 4, b: 2, a: 255),
                     Color(r: 18, g: 10, b: 6, a: 255),
                     Color(r: 44, g: 28, b: 12, a: 30),
                     Color(r: 140, g: 90, b: 30, a: alphaByte(34.0'f32 + recover * 26.0'f32)),
                     Color(r: 255, g: 180, b: 60, a: alphaByte(28.0'f32 + recover * 28.0'f32)),
                     0.55, 0.5)

# ---------------------------------------------------------------------------
# Public factory

proc newRogueliteEndCutscene*(): Cutscene =
  newCutscene(
    shots = @[
      CutsceneShot(duration: 5.20'f32, drawProc: drawDescendShot, soundCue: stTeleport,
                   label: t(tkRogEndRecDescend), iconIndex: 7),
      CutsceneShot(duration: 5.40'f32, drawProc: drawCoreShot,    soundCue: stBossSpawn,
                   label: t(tkRogEndRecCore),    iconIndex: 3,
                   glitchMod: 67, glitchWindow: 5, shakeProc: coreShake),
      CutsceneShot(duration: 5.30'f32, drawProc: drawExtractShot, soundCue: stPowerUp,
                   label: t(tkRogEndRecExtract), iconIndex: 4),
      CutsceneShot(duration: 5.40'f32, drawProc: drawRevealShot,  soundCue: stBossSpawn,
                   label: t(tkRogEndRecReveal),  iconIndex: 3,
                   glitchMod: 53, glitchWindow: 6, shakeProc: coreShake),
      CutsceneShot(duration: 5.20'f32, drawProc: drawAscendShot,  soundCue: stShield,
                   label: t(tkRogEndRecAscend),  iconIndex: 0),
      CutsceneShot(duration: 5.40'f32, drawProc: drawRogSignoffShot, soundCue: stWaveComplete,
                   label: t(tkRogEndRecSignoff), iconIndex: 10),
    ],
    accentColor      = RogAccent,
    titleCardText    = "TopHat-ShooterOS",
    titleCardSub     = t(tkRogEndTitleCardSub),
    drawBackdropProc = rogueliteBackdrop,
    swayAmp          = 1.0'f32,
    musicTrack       = mtMenu,
    cornerTag        = t(tkLorePlayback),
  )

# Legacy-style wrappers so main.nim mirrors the endgame-cinematic call sites.
type RogueliteEndCinematic* = Cutscene

proc newRogueliteEndCinematic*(): RogueliteEndCinematic = newRogueliteEndCutscene()

proc updateRogueliteEndCinematic*(c: RogueliteEndCinematic, dt: float32) =
  updateCutscene(c, dt)

proc drawRogueliteEndCinematic*(c: RogueliteEndCinematic, screenWidth, screenHeight: int) =
  drawCutscene(c, screenWidth, screenHeight)
