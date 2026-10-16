## Endgame Cinematic: Act II, ROOT ACCESS (REC 06 to REC 10).
## Plays once after the wave-60 boss falls. Root starts its sentence again and
## shooter.exe's last signal cuts it off; it falls below the partition table.
## TOPHAT's services come home, TOPHAT hands shooter.exe its hat (root access
## belongs to whoever keeps the machine running), and the system is secured.
## A last two-second shot leaves one cursor blinking in the unallocated dark,
## which is where Acts III and IV go.
##
## Timing: sound.nim's story timing (RootAccessShots, Root*), shared with the
## mtStoryRootAccess score in sound.nim.

import raylib, math
import ../draw_prims
import particle_types, background_fx, ../types, ../shapes, ../localization, ../sound,
       ../boss_definitions, cinematic_common, cutscene

const
  EndAccent* = Color(r: 60, g: 235, b: 160, a: 255)  # "restored" mint-green
  KernelCyan = Color(r: 0, g: 230, b: 230, a: 255)
  ServiceCount = 11

# ---------------------------------------------------------------------------
# REC 06: MID-SENTENCE. Root starts typing; the last signal lands first.

proc newCutOffShot(): CutsceneDrawProc =
  var root: Enemy
  result = proc(local, duration: float32, sw, sh: int32, alpha: float32) =
    if root.isNil:
      root = newCinematicBoss(12, sw, sh)
    let cx = sw.float32 * 0.56'f32
    let cy = sh.float32 * 0.36'f32
    let cut = RootCutOffAt
    let after = max(0.0'f32, local - cut)
    let fall = easeInOut(clamp01(after / 3.4'f32))
    let partY = sh.float32 * 0.6'f32

    # The partition table: everything root is falls through it.
    drawStroke(Vector2(x: sw.float32 * 0.08'f32, y: partY), Vector2(x: sw.float32 * 0.92'f32, y: partY),
               2.0'f32, colorA(EndAccent, alpha * 110.0'f32))
    drawText(t(tkEndPartitionTable), (sw.float32 * 0.08'f32).int32, (partY + 8.0'f32).int32, 13,
             colorA(EndAccent, alpha * 130.0'f32))

    if local < cut:
      let shake = sin(local * 41.0'f32) * 2.0'f32
      drawHalo(cx, cy, 200.0'f32, Color(r: 170, g: 0, b: 255, a: alphaByte(alpha * 55.0'f32)), 1.0'f32)
      drawCinematicBoss(root, cx + shake, cy, 84.0'f32, 0.05'f32, 3)
    else:
      # Root itself sinks and shrinks through the partition first...
      let sinkT = clamp01(after / 1.2'f32)
      if sinkT < 1.0'f32:
        let sinkY = lerpF(cy, partY + 30.0'f32, easeInOut(sinkT))
        drawCinematicBoss(root, cx, sinkY, 84.0'f32 * (1.0'f32 - sinkT * 0.85'f32), 0.02'f32, 3)
      # ...and where it went through, the partition table ripples for a while.
      for k in 0..<3:
        let rp = clamp01((after - 0.6'f32 - k.float32 * 0.6'f32) / 2.2'f32)
        if rp > 0.0'f32 and rp < 1.0'f32:
          let rw = 30.0'f32 + rp * 260.0'f32
          drawEllipseOutline(cx.int32, partY.int32, rw, rw * 0.14'f32,
                             Color(r: 230, g: 70, b: 210, a: alphaByte(alpha * (1.0'f32 - rp) * 200.0'f32)))
      # Shattered: fragments drop, and vanish as they pass the partition.
      for i in 0..<40:
        let ang = hash01(i.float32 + 3.0'f32) * PI * 2.0'f32
        let spread = after * (40.0'f32 + hash01(i.float32 * 2.3'f32) * 120.0'f32)
        let fx = cx + cos(ang) * spread
        let fy = cy + sin(ang) * spread * 0.5'f32 + after * after * (60.0'f32 + hash01(i.float32 + 9.0'f32) * 90.0'f32)
        if fy > partY:
          continue
        let sides = 3 + (i mod 4).int32
        let sz = (5.0'f32 + hash01(i.float32 + 1.0'f32) * 8.0'f32) * (1.0'f32 - fall * 0.5'f32)
        drawPoly(Vector2(x: fx, y: fy), sides, sz, local * 160.0'f32 + i.float32 * 40.0'f32,
                 Color(r: 230, g: 70, b: 210, a: alphaByte(alpha * 220.0'f32)))
      let flash = exp(-after * 6.0'f32)
      drawRectangle(0, 0, sw, sh, Color(r: 240, g: 255, b: 250, a: alphaByte(alpha * flash * 170.0'f32)))
      for k in 0..<3:
        let rp = clamp01(after * 0.9'f32 - k.float32 * 0.15'f32)
        if rp > 0.0'f32 and rp < 1.0'f32:
          drawCircleOutline(Vector2(x: cx, y: cy), rp * 320.0'f32, colorA(EndAccent, alpha * (1.0'f32 - rp) * 170.0'f32))

    # shooter.exe and its last shot, timed to land on the cut.
    let px = sw.float32 * 0.16'f32
    let py = sh.float32 * 0.42'f32
    drawEquippedPlayerModel(newVector2f(px, py), 22.0'f32, local, alpha, 0.25'f32)
    let shotT = clamp01((local - (cut - 0.55'f32)) / 0.55'f32)
    if shotT > 0.0'f32 and shotT < 1.0'f32:
      let bx = lerpF(px + 26.0'f32, cx, shotT)
      let by = lerpF(py, cy, shotT)
      drawStroke(Vector2(x: bx - (cx - px) * 0.08'f32, y: by - (cy - py) * 0.08'f32), Vector2(x: bx, y: by),
                 3.0'f32, Color(r: 220, g: 255, b: 250, a: alphaByte(alpha * 200.0'f32)))
      drawEquippedBulletModel(newVector2f(bx, by), 8.0'f32, arctan2(cy - py, cx - px), local, alpha)

    # Root's sentence, never finished: it types up to the cut, then breaks.
    let textY = sh div 9 + 26
    if local < cut + 0.35'f32:
      let breakA = 1.0'f32 - clamp01(after / 0.35'f32)
      let jitter = if local >= cut: int32((hash01(floor(local * 40.0'f32)) - 0.5'f32) * 18.0'f32) else: 0'i32
      drawOldText(t(tkEndRootTyped), sw div 2 + jitter, textY, 36,
                  revealOver(local, RootTypeAt, cut - RootTypeAt), local, alpha * breakA)

    drawSubtitles([t(tkEndCutOff1), t(tkEndCutOff2)], sw, sh, alpha)

# ---------------------------------------------------------------------------
# REC 07: SERVICES RESTORED. The list from REC 04, flipping back.

proc newHomeShot(): CutsceneDrawProc =
  var services: seq[string]
  var flipTimes: seq[float32]
  for id in 1..ServiceCount:
    services.add(getBossProcessName(id))
    flipTimes.add(RootHomeStart + (id - 1).float32 * RootHomeEvery)
  let winTitle = t(tkLoreServicesWindow)
  let colService = t(tkLoreColService)
  let colOwner = t(tkLoreColOwner)

  result = proc(local, duration: float32, sw, sh: int32, alpha: float32) =
    drawServiceWindow(sw.float32 * 0.07'f32, 96.0'f32, min(390.0'f32, sw.float32 * 0.4'f32),
                      winTitle, colService, colOwner, services, flipTimes, local, alpha,
                      "root", "tophat", RootRed, KernelCyan)
    var home = 0
    for ft in flipTimes:
      if local >= ft:
        inc home
    # TOPHAT steadies as each service reconnects: one ring per return.
    let kx = sw.float32 * 0.72'f32
    let ky = sh.float32 * 0.36'f32
    let warm = home.float32 / ServiceCount.float32
    drawHalo(kx, ky, 120.0'f32 + warm * 110.0'f32, colorA(KernelCyan, alpha * (25.0'f32 + warm * 45.0'f32)), 1.0'f32)
    for i in 0..<home:
      let age = local - flipTimes[i]
      let r = 46.0'f32 + i.float32 * 9.0'f32
      let a = alpha * (90.0'f32 + 120.0'f32 * exp(-age * 3.0'f32)) * (1.0'f32 - i.float32 * 0.05'f32)
      drawCircleOutline(Vector2(x: kx, y: ky), r, colorA(KernelCyan, a))
    drawKernelModel(newVector2f(kx, ky), 30.0'f32, local, 1.0'f32, alpha)
    drawCenteredText($home & "/" & $ServiceCount, kx.int32, (ky + 160.0'f32).int32, 20,
                     colorA(KernelCyan, alpha * 220.0'f32))
    drawSubtitles([t(tkEndHome1), t(tkEndHome2)], sw, sh, alpha)

# ---------------------------------------------------------------------------
# REC 08: ROOT ACCESS. The hat changes heads.

proc drawHatShot(local, duration: float32, sw, sh: int32, alpha: float32) =
  let kx = sw.float32 * 0.33'f32
  let ky = sh.float32 * 0.40'f32
  let px = sw.float32 * 0.67'f32
  let py = sh.float32 * 0.43'f32
  const kr = 30.0'f32
  const pr = 28.0'f32
  let liftAt = RootHatYesAt + 0.35'f32
  let travel = easeInOut(clamp01((local - liftAt) / (RootHatLandAt - liftAt)))
  let landed = local >= RootHatLandAt

  drawHalo(kx, ky, 110.0'f32, colorA(KernelCyan, alpha * 34.0'f32), 1.0'f32)
  drawKernelModel(newVector2f(kx, ky), kr, local, 1.0'f32, alpha, hat = local < liftAt)
  let glow = if landed: 0.5'f32 + 0.2'f32 * exp(-(local - RootHatLandAt) * 2.0'f32) else: 0.25'f32
  drawHalo(px, py, 90.0'f32 + (if landed: 50.0'f32 else: 0.0'f32), colorA(EndAccent, alpha * 40.0'f32), 1.0'f32)
  drawEquippedPlayerModel(newVector2f(px, py), pr, local, alpha, glow)

  if local >= liftAt:
    # An arc from one head to the other, shrinking to fit the new wearer.
    let hx = lerpF(kx, px, travel)
    let hy = lerpF(ky, py, travel) - sin(travel * PI) * 90.0'f32
    let hr = lerpF(kr, pr, travel)
    drawTopHat(newVector2f(hx, hy), hr, local, alpha)
    if landed:
      let ring = clamp01((local - RootHatLandAt) / 0.7'f32)
      drawCircleOutline(Vector2(x: px, y: py - pr), 20.0'f32 + ring * 70.0'f32,
                        colorA(EndAccent, alpha * (1.0'f32 - ring) * 220.0'f32))

  # TOPHAT asks itself, and answers.
  let dlgOut = clamp01((local - (RootHatYesAt + 0.5'f32)) / 0.4'f32)
  let dlgA = alpha * clamp01(local / 0.4'f32) * (1.0'f32 - dlgOut)
  if dlgA > 0.0'f32:
    const dw = 380.0'f32
    const dh = 128.0'f32
    let dx = sw.float32 * 0.5'f32 - dw * 0.5'f32
    let dy = (sh div 9).float32 + 14.0'f32
    drawStoryWindow(dx, dy, dw, dh, t(tkEndTransferTitle), dlgA, KernelCyan)
    let body = t(tkEndTransferBody)
    drawText(body, dx.int32 + 20, dy.int32 + 44, fitFontSize(body, dw.int32 - 40, 17),
             Color(r: 230, g: 240, b: 250, a: alphaByte(dlgA * 255.0'f32)))
    let pressed = local >= RootHatYesAt and local < RootHatYesAt + 0.15'f32
    drawStoryButton(dx + dw - 210.0'f32, dy + dh - 42.0'f32, 90.0'f32, 30.0'f32, t(tkEndYes), dlgA,
                    pressed, primary = true)
    drawStoryButton(dx + dw - 110.0'f32, dy + dh - 42.0'f32, 90.0'f32, 30.0'f32, t(tkEndNo), dlgA)

  drawSubtitles([t(tkEndHat1), t(tkEndHat2)], sw, sh, alpha)

# ---------------------------------------------------------------------------
# REC 09: SYSTEM SECURED.

proc drawSecuredShot(local, duration: float32, sw, sh: int32, alpha: float32) =
  let cx = sw.float32 * 0.5'f32
  let cy = sh.float32 * 0.36'f32
  let pulse = sin(local * 3.0'f32) * 0.5'f32 + 0.5'f32
  for i in -2..2:
    drawRectangleGradientV((cx + i.float32 * 46.0'f32).int32 - 6, 0, 12, sh,
                           colorA(EndAccent, 0.0'f32), colorA(EndAccent, alpha * 40.0'f32))
  drawHalo(cx, cy, 280.0'f32, colorA(EndAccent, alpha * (40.0'f32 + pulse * 26.0'f32)), 1.0'f32)
  const pr = 30.0'f32
  drawEquippedPlayerModel(newVector2f(cx, cy), pr * (1.0'f32 + pulse * 0.04'f32), local, alpha, 0.3'f32)
  drawTopHat(newVector2f(cx, cy), pr, local, alpha)
  # TOPHAT at its side, bare-headed and content.
  drawKernelModel(newVector2f(cx - 110.0'f32, cy + 18.0'f32), 16.0'f32, local, 1.0'f32, alpha * 0.85'f32, hat = false)

  let titleAlpha = alpha * easeInOut(local / 0.85'f32)
  drawCenteredText(t(tkEndSignoffTitle), sw div 2, (sh * 2 div 3 - 40).int32, 34,
                   Color(r: 255, g: 255, b: 255, a: alphaByte(titleAlpha * 255.0'f32)))
  let sub = t(tkEndSignoffSub)
  drawCenteredText(sub, sw div 2, (sh * 2 div 3 + 6).int32, fitFontSize(sub, sw - 80, 21),
                   colorA(EndAccent, titleAlpha * 225.0'f32))

# ---------------------------------------------------------------------------
# REC 10: UNALLOCATED. Something below is still awake.

proc drawUnallocatedShot(local, duration: float32, sw, sh: int32, alpha: float32) =
  drawRectangle(-20, -20, sw + 40, sh + 40, Color(r: 0, g: 0, b: 0, a: 255))
  let a = clamp01(local / 0.4'f32) * clamp01((duration - local) / 0.6'f32)
  let x = sw div 9
  let y = sh - sh div 9 - 70
  if local >= RootStingBeepAt:
    let glow = exp(-(local - RootStingBeepAt) * 3.0'f32)
    drawHalo(x.float32 + 10.0'f32, y.float32 + 12.0'f32, 60.0'f32, colorA(OldAmber, a * glow * 60.0'f32), 1.0'f32)
  drawOldText("", x, y, 24, 1.0'f32, local, a * 0.9'f32, centered = false)

# ---------------------------------------------------------------------------
# Per-shot shake override

proc cutShake(time, local, duration, alpha: float32): float32 =
  if local < RootCutOffAt:
    sin(time * 30.0'f32) * 1.4'f32 * alpha
  else:
    sin(time * 47.0'f32) * 6.0'f32 * exp(-(local - RootCutOffAt) * 3.5'f32)

# ---------------------------------------------------------------------------
# Backdrop, brightens as the run-time progresses

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
      CutsceneShot(duration: RootAccessShots[0], drawProc: newCutOffShot(), soundCue: stExplosion,
                   muteCue: true, label: t(tkEndRecCutOff), iconIndex: 7,
                   glitchMod: 67, glitchWindow: 5, shakeProc: cutShake),
      CutsceneShot(duration: RootAccessShots[1], drawProc: newHomeShot(), soundCue: stShield,
                   muteCue: true, label: t(tkEndRecHome), iconIndex: 0),
      CutsceneShot(duration: RootAccessShots[2], drawProc: drawHatShot, soundCue: stPowerUp,
                   muteCue: true, label: t(tkEndRecHat), iconIndex: 10),
      CutsceneShot(duration: RootAccessShots[3], drawProc: drawSecuredShot, soundCue: stWaveComplete,
                   muteCue: true, label: t(tkEndRecSecured), iconIndex: 5),
      CutsceneShot(duration: RootAccessShots[4], drawProc: drawUnallocatedShot, soundCue: stMenuSelect,
                   muteCue: true, label: t(tkEndRecUnallocated), iconIndex: 3, glitchMod: 41, glitchWindow: 3),
    ],
    accentColor      = EndAccent,
    titleCardText    = "",   # cold open: root is already typing
    titleCardSub     = "",
    drawBackdropProc = endgameBackdrop,
    swayAmp          = 1.0'f32,
    musicTrack       = mtStoryRootAccess,
    cornerTag        = t(tkLorePlayback),
    captionCps       = EndingCaptionCps,
  )

# Keep legacy proc names so main.nim continues to compile without changes.
type EndgameCinematic* = Cutscene

proc newEndgameCinematic*(): EndgameCinematic = newEndgameCutscene()

proc updateEndgameCinematic*(endg: EndgameCinematic, dt: float32) =
  updateCutscene(endg, dt)

proc drawEndgameCinematic*(endg: EndgameCinematic, screenWidth, screenHeight: int) =
  drawCutscene(endg, screenWidth, screenHeight)
