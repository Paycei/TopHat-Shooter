## Endgame Cinematic Module
## Plays once, the first time the player beats the wave-60 final boss, between the
## kill and the victory ("system secured") screen. It is the narrative resolution
## of the opening lore cinematic: the root entity falls, the corruption is purged,
## the TOPHAT kernel is restored, the player is crowned, and the system signs off.
##
## Built on the same `cinematic_common.nim` rendering as the intro so the two read
## as a matched pair, same recorder chrome, same models, only the colour grade
## flips from corrupt magenta to a restored mint-green.

import raylib, rlgl, math
import particle_types
import background_fx, ../types, ../shapes, ../localization, ../sound,
       cinematic_common

type
  EndShot* = enum
    esFall        # the root entity shatters
    esPurge       # the corruption recedes, memory reclaimed
    esRestore     # the TOPHAT kernel reforms
    esCrown       # the player ascends and is crowned
    esSignoff     # final "system secured" card

  EndgameCinematic* = ref object
    time*: float32
    complete*: bool
    scanlineOffset*: float32
    frame*: int
    fastForwardActive*: bool
    skipHoldTimer*: float32
    lastShotPlayed*: int  # Index of the shot whose audio cue last fired (-1 = none)

const
  EndFastForwardMultiplier = 2.0'f32
  EndSkipHoldRequired = 3.0'f32
  EndAccent = Color(r: 60, g: 235, b: 160, a: 255)  # "restored" mint-green
  ShotDurations = [
    5.10'f32, # root entity falls
    5.30'f32, # system purge
    5.40'f32, # kernel restored
    5.60'f32, # crowned
    5.20'f32  # sign-off
  ]
  EndDuration =
    ShotDurations[0] + ShotDurations[1] + ShotDurations[2] +
    ShotDurations[3] + ShotDurations[4]

proc newEndgameCinematic*(): EndgameCinematic =
  EndgameCinematic(
    time: 0,
    complete: false,
    scanlineOffset: 0,
    frame: 0,
    fastForwardActive: false,
    skipHoldTimer: 0,
    lastShotPlayed: -1
  )

proc shotAt(time: float32): tuple[shot: EndShot, local: float32, duration: float32] =
  var cursor = 0.0'f32
  for i, duration in ShotDurations:
    if time < cursor + duration:
      return (EndShot(i), time - cursor, duration)
    cursor += duration
  (esSignoff, ShotDurations[^1], ShotDurations[^1])

proc shotFade(local, duration: float32): float32 =
  min(easeInOut(local / 1.35'f32), easeInOut((duration - local) / 1.55'f32))

proc drawVideoOverlay(endg: EndgameCinematic, screenWidth, screenHeight: int32,
                      shot: EndShot) =
  let shotLabel = case shot
    of esFall: t(tkEndRecFall)
    of esPurge: t(tkEndRecPurge)
    of esRestore: t(tkEndRecRestore)
    of esCrown: t(tkEndRecCrown)
    of esSignoff: t(tkEndRecSignoff)

  let iconIndex = case shot
    of esFall: 7
    of esPurge: 0
    of esRestore: 4
    of esCrown: 10
    of esSignoff: 5

  # The fall is the only unstable feed; once the purge runs the tracking settles.
  let glitchHot = shot == esFall and (endg.frame mod 67) < 5
  drawCinematicOverlay(screenWidth, screenHeight, endg.time, endg.frame,
                       endg.scanlineOffset, endg.fastForwardActive,
                       endg.skipHoldTimer, EndSkipHoldRequired, EndDuration,
                       shotLabel, t(tkLoreLive), t(tkLoreControlsFF),
                       t(tkLoreControlsFFActive), iconIndex, glitchHot, EndAccent)

proc drawFallShot(local, duration: float32, screenWidth, screenHeight: int32,
                  alpha: float32) =
  ## The root entity collapses: shell shrinks, cracks radiate, a shock front
  ## blows outward, debris scatters, and a white flash punctuates the shatter.
  let cx = screenWidth.float32 * 0.5'f32
  let cy = screenHeight.float32 * 0.44'f32
  let collapse = easeInOut(local / duration)

  # Dying purple aura, shrinking as the entity loses cohesion.
  drawSoftGlow(cx, cy, 260.0'f32 * (1.0'f32 - collapse * 0.7'f32),
               Color(r: 170, g: 0, b: 255, a: alphaByte(alpha * 60.0'f32 * (1.0'f32 - collapse))), 1.0'f32)

  # The boss model itself, shrinking and draining as it dies.
  if collapse < 0.9'f32:
    let bossR = 92.0'f32 * (1.0'f32 - collapse * 0.85'f32)
    drawRealBossModel(cx, cy, bossR, local, screenWidth, screenHeight,
                      max(0.02'f32, 0.16'f32 * (1.0'f32 - collapse)))

  # Fracture lines tearing outward from the core.
  for i in 0..<12:
    let a = i.float32 * PI * 2.0'f32 / 12.0'f32 + local * 0.4'f32
    let len = 36.0'f32 + collapse * 230.0'f32
    drawLine(cx.int32, cy.int32,
             (cx + cos(a) * len).int32, (cy + sin(a) * len).int32,
             Color(r: 255, g: 60, b: 200, a: alphaByte(alpha * (1.0'f32 - collapse) * 150.0'f32)))

  # Expanding shock rings: the purge front being born.
  for k in 0..<3:
    let rp = clamp01(collapse * 1.3'f32 - k.float32 * 0.18'f32)
    if rp > 0.0'f32:
      drawCircleLines(Vector2(x: cx, y: cy), rp * 340.0'f32,
                      colorA(EndAccent, alpha * (1.0'f32 - rp) * 180.0'f32))

  # Debris fragments flung out from the shatter.
  for i in 0..<18:
    let ang = fractCoord(sin(i.float32 * 12.9898'f32) * 43758.5453'f32) * PI * 2.0'f32
    let dist = collapse * (110.0'f32 + fractCoord(i.float32 * 7.31'f32) * 230.0'f32)
    let px = cx + cos(ang) * dist
    let py = cy + sin(ang) * dist
    let sides = 3 + (i mod 4).int32
    drawPoly(Vector2(x: px, y: py), sides, 7.0'f32 * (1.0'f32 - collapse), local * 90.0'f32 + i.float32,
             Color(r: 230, g: 60, b: 200, a: alphaByte(alpha * (1.0'f32 - collapse) * 200.0'f32)))

  # White flash at the moment of shatter (~collapse 0.62).
  let flash = clamp01(1.0'f32 - abs(collapse - 0.62'f32) / 0.12'f32)
  if flash > 0.0'f32:
    drawRectangle(0, 0, screenWidth, screenHeight,
                  Color(r: 235, g: 255, b: 245, a: alphaByte(alpha * flash * 150.0'f32)))

  drawSubtitles([t(tkEndFall1), t(tkEndFall2)], screenWidth, screenHeight, alpha)

proc drawPurgeShot(local, duration: float32, screenWidth, screenHeight: int32,
                   alpha: float32) =
  ## A clean reclaim front sweeps left-to-right; corrupted shapes it passes
  ## dissolve into mint sparks, leaving reclaimed memory behind it.
  let progress = easeInOut(local / duration)
  let frontX = -120.0'f32 + progress * (screenWidth.float32 + 240.0'f32)

  # Reclaimed memory glows mint behind the front; corruption tints ahead of it.
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

  # The bright purge front bar and its glow.
  drawSoftGlow(frontX, screenHeight.float32 * 0.5'f32, 90.0'f32,
               colorA(EndAccent, alpha * 70.0'f32), 1.0'f32)
  drawRectangle((frontX - 3.0'f32).int32, 0, 6, screenHeight,
                colorA(EndAccent, alpha * 210.0'f32))

  drawSubtitles([t(tkEndPurge1), t(tkEndPurge2)], screenWidth, screenHeight, alpha)

proc drawRestoreShot(local, duration: float32, screenWidth, screenHeight: int32,
                     alpha: float32) =
  ## The TOPHAT kernel reforms: reclaim particles converge inward and the shell
  ## boots back up, containment arcs locking into a stable spin.
  let boot = easeOut(local / (duration * 0.62'f32))
  let cx = screenWidth.float32 * 0.5'f32
  let cy = screenHeight.float32 * 0.46'f32

  drawSoftGlow(cx, cy, 240.0'f32 * boot, colorA(EndAccent, alpha * 50.0'f32), 1.0'f32)

  # Inflowing reclaim particles converging on the reforming core.
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
  ## The player ascends and the tophat, the kernel's crown, drops onto them.
  let rise = easeInOut(local / duration)
  let cx = screenWidth.float32 * 0.5'f32
  let cy = screenHeight.float32 * (0.56'f32 - rise * 0.07'f32)

  # Light pillars rising behind the ascending player.
  for i in -2..2:
    let bx = cx + i.float32 * 44.0'f32
    drawRectangleGradientV(bx.int32 - 6, 0, 12, screenHeight,
                           colorA(EndAccent, 0.0'f32),
                           colorA(EndAccent, alpha * rise * 50.0'f32))
  drawSoftGlow(cx, cy, 200.0'f32 * rise + 70.0'f32,
               colorA(EndAccent, alpha * (40.0'f32 + rise * 40.0'f32)), 1.0'f32)

  # Sparks rising from below, carried up with the ascension.
  for i in 0..<20:
    let p = fractCoord(local * 0.4'f32 + i.float32 * 0.137'f32)
    let sx = cx + sin(i.float32 * 2.3'f32 + local) * (40.0'f32 + i.float32 * 4.0'f32)
    let sy = screenHeight.float32 * 0.92'f32 - p * screenHeight.float32 * 0.72'f32
    drawCircle(Vector2(x: sx, y: sy), 2.6'f32 * (1.0'f32 - p),
               colorA(EndAccent, alpha * (1.0'f32 - p) * 200.0'f32))

  let pr = 30.0'f32 * (0.82'f32 + rise * 0.18'f32)
  drawEquippedPlayerModel(newVector2f(cx, cy), pr, local, alpha, 0.3'f32 + rise * 0.3'f32)

  # The crown drops on from above as the final beat of the ascension.
  let hatT = easeOut(clamp01((rise - 0.35'f32) / 0.45'f32))
  if hatT > 0.0'f32:
    let hatPos = newVector2f(cx, cy - (1.0'f32 - hatT) * pr * 3.0'f32)
    drawTopHat(hatPos, pr, local, alpha * hatT)

  drawSubtitles([t(tkEndCrown1), t(tkEndCrown2)], screenWidth, screenHeight, alpha)

proc drawSignoffShot(local, duration: float32, screenWidth, screenHeight: int32,
                     alpha: float32) =
  ## Final card: the crowned player, calm now, under a "SYSTEM SECURED" title.
  let cx = screenWidth.float32 * 0.5'f32
  let cy = screenHeight.float32 * 0.42'f32
  let pulse = sin(local * 3.0'f32) * 0.5'f32 + 0.5'f32
  drawSoftGlow(cx, cy, 300.0'f32, colorA(EndAccent, alpha * (46.0'f32 + pulse * 30.0'f32)), 1.0'f32)

  let pr = 30.0'f32
  drawEquippedPlayerModel(newVector2f(cx, cy), pr * (1.0'f32 + pulse * 0.04'f32),
                          local, alpha, 0.3'f32)
  drawTopHat(newVector2f(cx, cy), pr, local, alpha)  # crown settled

  let titleAlpha = alpha * easeInOut(local / 0.85'f32)
  drawCenteredText(t(tkEndSignoffTitle), screenWidth div 2, (screenHeight * 2 div 3).int32,
                   32, Color(r: 255, g: 255, b: 255, a: alphaByte(titleAlpha * 255.0'f32)))
  drawCenteredText(t(tkEndSignoffSub), screenWidth div 2, (screenHeight * 2 div 3 + 46).int32,
                   21, colorA(EndAccent, titleAlpha * 220.0'f32))

proc shotCue(shot: EndShot): SoundType =
  ## Per-shot audio sting, fired once when a new shot begins.
  case shot
  of esFall: stExplosion
  of esPurge: stShield
  of esRestore: stPowerUp
  of esCrown: stWaveComplete
  of esSignoff: stMenuSelect

proc updateEndgameCinematic*(endg: EndgameCinematic, dt: float32) =
  if endg.complete:
    return

  endg.fastForwardActive = isKeyDown(Enter)
  if isKeyDown(Space):
    endg.skipHoldTimer = min(EndSkipHoldRequired, endg.skipHoldTimer + dt)
  else:
    endg.skipHoldTimer = 0.0'f32

  if endg.skipHoldTimer >= EndSkipHoldRequired:
    endg.complete = true
    return

  let playbackDt = dt * (if endg.fastForwardActive: EndFastForwardMultiplier else: 1.0'f32)
  endg.time += playbackDt
  endg.scanlineOffset += playbackDt * 118.0'f32
  inc endg.frame

  let (curShot, _, _) = shotAt(endg.time)
  if ord(curShot) != endg.lastShotPlayed:
    endg.lastShotPlayed = ord(curShot)
    playSound(shotCue(curShot), 0.6'f32)  # ducked so the sting sits under the score

  if endg.time >= EndDuration:
    endg.complete = true

proc drawTitleCard(endg: EndgameCinematic, screenWidth, screenHeight: int32) =
  ## Opening "incident resolved" card; appears as the boot fade clears, then leaves.
  let appear = clamp01((endg.time - 0.2'f32) / 0.5'f32)
  let leave = clamp01((1.95'f32 - endg.time) / 0.5'f32)
  let a = min(appear, leave)
  if a <= 0.0'f32:
    return
  let cx = screenWidth div 2
  let cy = screenHeight div 2 - 30
  let ruleW = (screenWidth.float32 * 0.32'f32 * a).int32
  drawRectangle(cx - ruleW, cy - 16, ruleW * 2, 2, colorA(EndAccent, a * 170.0'f32))
  drawRectangle(cx - ruleW, cy + 54, ruleW * 2, 2, colorA(EndAccent, a * 170.0'f32))
  drawCenteredText("TopHat-ShooterOS", cx.int32, (cy).int32, 40,
                   Color(r: 255, g: 255, b: 255, a: alphaByte(a * 255.0'f32)))
  drawCenteredText(t(tkEndTitleCardSub), cx.int32, (cy + 60).int32, 16,
                   colorA(EndAccent, a * 200.0'f32))

proc drawEndgameCinematic*(endg: EndgameCinematic, screenWidth, screenHeight: int) =
  let (shot, local, duration) = shotAt(endg.time)
  let alpha = shotFade(local, duration)
  let shake =
    if shot == esFall:
      sin(endg.time * 38.0'f32) * 2.6'f32 * alpha * (1.0'f32 - easeInOut(local / duration))
    else:
      sin(endg.time * 0.7'f32) * 1.0'f32 * alpha
  let sW = screenWidth.int32
  let sH = screenHeight.int32

  # As the system is reclaimed the backdrop brightens from a dark breach to a
  # calmer restored glow.
  let restore = clamp01(endg.time / EndDuration)
  drawSharedBackdrop(sW, sH, endg.time * 0.42'f32,
                     Color(r: 2, g: 6, b: 8, a: 255),
                     Color(r: 6, g: 16, b: 18, a: 255),
                     Color(r: 16, g: 40, b: 36, a: 30),
                     Color(r: 40, g: 120, b: 100, a: alphaByte(36.0'f32 + restore * 24.0'f32)),
                     Color(r: 0, g: 220, b: 170, a: alphaByte(30.0'f32 + restore * 26.0'f32)),
                     0.55, 0.5)

  let camX = shake
  let camY = cos(endg.time * 0.84'f32) * 1.0'f32 * alpha
  drawRectangle(camX.int32 - 8, camY.int32 - 8, sW + 16, sH + 16,
                Color(r: 0, g: 0, b: 0, a: 35))

  pushMatrix()
  translatef(camX, camY, 0.0'f32)
  case shot
  of esFall:
    drawFallShot(local, duration, sW, sH, alpha)
  of esPurge:
    drawPurgeShot(local, duration, sW, sH, alpha)
  of esRestore:
    drawRestoreShot(local, duration, sW, sH, alpha)
  of esCrown:
    drawCrownShot(local, duration, sW, sH, alpha)
  of esSignoff:
    drawSignoffShot(local, duration, sW, sH, alpha)
  popMatrix()

  drawTapeChange(sW, sH, local, endg.frame, endg.time)

  let fadeIn = 1.0'f32 - easeInOut(endg.time / 0.75'f32)
  let fadeOut = easeInOut((endg.time - (EndDuration - 0.9'f32)) / 0.9'f32)
  let fadeA = alphaByte(max(fadeIn, fadeOut) * 255.0'f32)
  drawVideoOverlay(endg, sW, sH, shot)
  drawTitleCard(endg, sW, sH)
  if fadeA > 0:
    drawRectangle(0, 0, sW, sH, Color(r: 0, g: 0, b: 0, a: fadeA))
