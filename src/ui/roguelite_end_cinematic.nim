## Roguelite Ending Cinematic: Act III, BELOW THE PARTITION (DELVE 01 to 06).
## Plays once, the first time the final-floor boss falls. With root access,
## shooter.exe goes below the partition table and finds another desktop whose
## clock stopped years before TOPHAT existed. Its boot log lists the six
## legacy guardians, then TopHat-ShooterOS being installed over it. The other
## root was never an invader: it was here first. It gets the shutdown nobody
## gave it, and Disk Cleanup can finally finish.
##
## Timing: sound.nim's story timing (BelowShots, Below*), shared with the
## mtStoryBelow score in sound.nim.

import raylib, math
import ../draw_prims
import particle_types, background_fx, ../shapes, ../localization, ../sound, ../boss_definitions,
       cinematic_common, cutscene

const
  RogAccent* = Color(r: 255, g: 190, b: 70, a: 255)   # recovered-data amber/gold
  OldTeal = Color(r: 0, g: 92, b: 96, a: 255)
  OldGrey = Color(r: 178, g: 178, b: 170, a: 255)
  OldNavy = Color(r: 10, g: 20, b: 120, a: 255)
  SafeOrange = Color(r: 255, g: 140, b: 30, a: 255)
  IntruderCyan = Color(r: 0, g: 220, b: 235, a: 255)
  GuardianIds = [17, 18, 19, 20, 21, 22]   # the roguelite guardians: its services

# ---------------------------------------------------------------------------
# The old system's desktop: flat teal, grey bevels, an 8.3 world.

proc drawBevel(x, y, w, h: int32, a: float32, sunken: bool = false) =
  drawRectangle(x, y, w, h, colorA(OldGrey, a * 255.0'f32))
  let light = Color(r: 240, g: 240, b: 232, a: alphaByte(a * 255.0'f32))
  let dark = Color(r: 80, g: 80, b: 76, a: alphaByte(a * 255.0'f32))
  let (tl, br) = if sunken: (dark, light) else: (light, dark)
  drawRectangle(x, y, w, 2, tl)
  drawRectangle(x, y, 2, h, tl)
  drawRectangle(x, y + h - 2, w, 2, br)
  drawRectangle(x + w - 2, y, 2, h, br)

proc drawOldIcon(kind: int, cx, y: int32, label: string, a: float32) =
  let ink = Color(r: 20, g: 20, b: 20, a: alphaByte(a * 255.0'f32))
  case kind
  of 0:   # computer
    drawRectangle(cx - 15, y, 30, 22, colorA(OldGrey, a * 255.0'f32))
    drawRectangle(cx - 11, y + 3, 22, 15, Color(r: 0, g: 60, b: 70, a: alphaByte(a * 255.0'f32)))
    drawRectangle(cx - 8, y + 24, 16, 5, colorA(OldGrey, a * 255.0'f32))
    drawRectOutline(cx - 15, y, 30, 22, ink)
  of 1:   # folder
    drawRectangle(cx - 15, y + 2, 12, 5, Color(r: 230, g: 200, b: 80, a: alphaByte(a * 255.0'f32)))
    drawRectangle(cx - 15, y + 6, 30, 21, Color(r: 245, g: 215, b: 90, a: alphaByte(a * 255.0'f32)))
    drawRectOutline(cx - 15, y + 6, 30, 21, ink)
  of 2:   # document
    drawRectangle(cx - 11, y, 22, 28, Color(r: 245, g: 245, b: 240, a: alphaByte(a * 255.0'f32)))
    drawRectOutline(cx - 11, y, 22, 28, ink)
    for k in 0..<4:
      drawRectangle(cx - 7, y + 6 + k.int32 * 5, 14, 1, ink)
  else:   # bin
    drawRectangle(cx - 11, y + 4, 22, 24, Color(r: 200, g: 205, b: 210, a: alphaByte(a * 255.0'f32)))
    drawRectangle(cx - 13, y + 2, 26, 3, Color(r: 150, g: 155, b: 160, a: alphaByte(a * 255.0'f32)))
    drawRectOutline(cx - 11, y + 4, 22, 24, ink)
  let w = measureText(label, 12)
  drawText(label, cx - w div 2 + 1, y + 35, 12, Color(r: 0, g: 0, b: 0, a: alphaByte(a * 200.0'f32)))
  drawText(label, cx - w div 2, y + 34, 12, Color(r: 255, g: 255, b: 255, a: alphaByte(a * 255.0'f32)))

proc oldScreenRect(sw, sh: int32): (int32, int32, int32, int32) =
  let w = (sw.float32 * 0.7'f32).int32
  let h = (sh.float32 * 0.5'f32).int32
  ((sw - w) div 2, sh div 9 + 26, w, h)

proc drawOldDesktop(sw, sh: int32, local, alpha: float32, iconsLeft: int = 5) =
  ## The desktop below the partition. Nothing moves except the dust; the
  ## clock in the corner stopped long ago and never blinks.
  let (x, y, w, h) = oldScreenRect(sw, sh)
  drawRectangle(x - 4, y - 4, w + 8, h + 8, Color(r: 30, g: 30, b: 28, a: alphaByte(alpha * 255.0'f32)))
  drawRectangle(x, y, w, h, colorA(OldTeal, alpha * 255.0'f32))
  const labels = ["SYSTEM", "DOCS", "GAMES", "README.TXT", "RECYCLED"]
  const kinds = [0, 1, 1, 2, 3]
  for i in 0..<min(iconsLeft, labels.len):
    drawOldIcon(kinds[i], x + 46, y + 18 + i.int32 * 62, labels[i], alpha)
  let barY = y + h - 28
  drawBevel(x, barY, w, 28, alpha)
  drawBevel(x + 4, barY + 4, 74, 20, alpha)
  drawRectangle(x + 10, barY + 9, 10, 10, Color(r: 0, g: 110, b: 110, a: alphaByte(alpha * 255.0'f32)))
  drawText("MENU", x + 26, barY + 9, 12, Color(r: 10, g: 10, b: 10, a: alphaByte(alpha * 255.0'f32)))
  drawBevel(x + w - 70, barY + 4, 66, 20, alpha, sunken = true)
  drawText("03:14", x + w - 56, barY + 9, 12, Color(r: 10, g: 10, b: 10, a: alphaByte(alpha * 255.0'f32)))
  # Dust and a tired picture: specks, slow rolling bars.
  for i in 0..<40:
    let sx = x + int32(hash01(i.float32 * 3.3'f32) * w.float32)
    let sy = y + int32(fractCoord(hash01(i.float32 + 0.7'f32) + local * 0.03'f32) * h.float32)
    drawRectangle(sx, sy, 1, 1, Color(r: 255, g: 255, b: 240, a: alphaByte(alpha * 60.0'f32)))
  let roll = y + int32(fractCoord(local * 0.12'f32) * h.float32)
  drawRectangle(x, roll, w, 10, Color(r: 0, g: 0, b: 0, a: alphaByte(alpha * 22.0'f32)))

# ---------------------------------------------------------------------------
# DELVE 01: BELOW THE PARTITION. Through the floor TOPHAT could never open.

proc drawDescendShot(local, duration: float32, screenWidth, screenHeight: int32,
                     alpha: float32) =
  let cx = screenWidth.float32 * 0.5'f32
  let cy = screenHeight.float32 * 0.44'f32
  let dive = easeInOut(local / duration)

  drawHalo(cx, cy, 200.0'f32, colorA(RogAccent, alpha * 46.0'f32), 1.0'f32)
  for i in 0..<11:
    let phase = fractCoord(local * 0.32'f32 + i.float32 / 11.0'f32)
    let r = 28.0'f32 + phase * 360.0'f32
    let sides = 4 + (i mod 4).int32
    let rot = local * (18.0'f32 + i.float32 * 4.0'f32) + i.float32 * 21.0'f32
    let ringA = alpha * (1.0'f32 - phase) * 150.0'f32
    drawPolyOutline(Vector2(x: cx, y: cy), sides, r, rot, Color(r: 255, g: 170, b: 60, a: alphaByte(ringA)))
  for i in 0..<16:
    let ang = hash01(i.float32) * PI * 2.0'f32
    let p = fractCoord(local * 0.6'f32 + i.float32 * 0.063'f32)
    let dist = (1.0'f32 - p) * 320.0'f32 + 30.0'f32
    let px = cx + cos(ang) * dist
    let py = cy + sin(ang) * dist * 0.7'f32
    drawStroke(px.int32, py.int32, cx.int32, cy.int32, colorA(RogAccent, alpha * (1.0'f32 - p) * 30.0'f32))
    drawDisc(Vector2(x: px, y: py), 2.4'f32 * (1.0'f32 - p) + 0.6'f32, colorA(RogAccent, alpha * (1.0'f32 - p) * 180.0'f32))

  # The partition table, passed on the way down: a bright plane sweeping up.
  let pass = clamp01((local - 0.6'f32) / 1.5'f32)
  if pass > 0.0'f32 and pass < 1.0'f32:
    let planeY = lerpF(screenHeight.float32 * 0.62'f32, screenHeight.float32 * 0.12'f32, easeInOut(pass))
    let pa = alpha * sin(pass * PI)
    drawRectangle(0, planeY.int32 - 1, screenWidth, 3, colorA(IntruderCyan, pa * 230.0'f32))
    drawRectangleGradientV(0, planeY.int32 + 2, screenWidth, 40, colorA(IntruderCyan, pa * 60.0'f32),
                           colorA(IntruderCyan, 0.0'f32))
    drawText(t(tkEndPartitionTable), screenWidth div 9, planeY.int32 - 18, 14, colorA(IntruderCyan, pa * 230.0'f32))

  let pr = 26.0'f32 * (1.0'f32 - dive * 0.35'f32)
  drawEquippedPlayerModel(newVector2f(cx, cy), pr, local, alpha, 0.25'f32)
  drawTopHat(newVector2f(cx, cy), pr, local, alpha)

  drawSubtitles([t(tkRogEndDescend1), t(tkRogEndDescend2)], screenWidth, screenHeight, alpha)

# ---------------------------------------------------------------------------
# DELVE 02: SOMEONE ELSE'S DESKTOP.

proc drawOldDesktopShot(local, duration: float32, sw, sh: int32, alpha: float32) =
  drawOldDesktop(sw, sh, local, alpha)
  let (x, y, w, h) = oldScreenRect(sw, sh)
  # shooter.exe, a visitor, small against someone else's wallpaper.
  let arrive = easeOut(clamp01(local / 2.2'f32))
  let px = (x + w div 2).float32
  let py = (y + h).float32 - 90.0'f32 - (1.0'f32 - arrive) * 40.0'f32
  drawHalo(px, py, 40.0'f32, colorA(IntruderCyan, alpha * 40.0'f32), 1.0'f32)
  drawEquippedPlayerModel(newVector2f(px, py), 14.0'f32, local, alpha * arrive, 0.2'f32)
  drawTopHat(newVector2f(px, py), 14.0'f32, local, alpha * arrive)
  drawSubtitles([t(tkRogEndDesktop1), t(tkRogEndDesktop2)], sw, sh, alpha)

# ---------------------------------------------------------------------------
# DELVE 03: BOOT LOG. Its services, then us, written over it.

proc newBootLogShot(): CutsceneDrawProc =
  var guardians: seq[string]
  for id in GuardianIds:
    guardians.add(getBossProcessName(id))
  let install = t(tkRogEndLogInstall)
  let overwrite = t(tkRogEndLogOverwrite)
  let suspend = t(tkRogEndLogSuspend)

  result = proc(local, duration: float32, sw, sh: int32, alpha: float32) =
    let x = (sw.float32 * 0.14'f32).int32
    let colW = min(sw - 2 * x, 560'i32)
    let y0 = sh div 9 + 28
    drawRectangle(x - 16, y0 - 14, colW + 32, BelowLogLines.int32 * 30 + 24,
                  Color(r: 4, g: 4, b: 2, a: alphaByte(alpha * 235.0'f32)))
    drawRectOutline(x - 16, y0 - 14, colW + 32, BelowLogLines.int32 * 30 + 24, colorA(OldAmber, alpha * 70.0'f32))
    let overwriteAt = BelowLogStart + 7.0'f32 * BelowLogEvery
    for i in 0..<BelowLogLines:
      let at = BelowLogStart + i.float32 * BelowLogEvery
      if local < at:
        break
      let ly = y0 + i.int32 * 30
      let reveal = revealOver(local, at, 0.3'f32)
      if i < GuardianIds.len:
        let name = guardians[i]
        drawOldText(name, x, ly, 20, reveal, local, alpha, centered = false, cursor = false)
        if reveal >= 1.0'f32:
          let okX = x + colW - measureText("OK", 20)
          var dx = x + measureText(name, 20) + 12
          while dx < okX - 14:
            drawRectangle(dx, ly + 14, 3, 3, colorA(OldAmber, alpha * 150.0'f32))
            dx += 12
          drawText("OK", okX, ly, 20, colorA(OldAmber, alpha * 245.0'f32))
      elif i < 8:
        drawOldText((if i == 6: install & "..." else: overwrite & "..."), x, ly, 20, reveal, local, alpha,
                    IntruderCyan, centered = false, cursor = false)
      else:
        drawOldText(suspend, x, ly, 20, reveal, local, alpha * 0.8'f32, centered = false)
    # The overwrite: TopHat-ShooterOS's cyan eats into the amber lines above.
    let eat = clamp01((local - overwriteAt) / 2.6'f32)
    if eat > 0.0'f32:
      for k in 0..<int(eat * 90.0'f32):
        let row = int(hash01(k.float32 * 1.7'f32) * GuardianIds.len.float32)
        let bx = x + int32(hash01(k.float32 * 4.1'f32 + 2.0'f32) * colW.float32)
        let flick = if fractCoord(local * 8.0'f32 + hash01(k.float32)) < 0.85'f32: 1.0'f32 else: 0.4'f32
        drawRectangle(bx, y0 + row.int32 * 30 + 2, 6 + int32(hash01(k.float32 + 9.0'f32) * 22.0'f32), 18,
                      colorA(IntruderCyan, alpha * flick * 150.0'f32))
    drawSubtitles([t(tkRogEndLog1), t(tkRogEndLog2)], sw, sh, alpha)

# ---------------------------------------------------------------------------
# DELVE 04: THE OTHER ROOT. No monster: a cursor on its own screen.

proc drawOtherRootShot(local, duration: float32, sw, sh: int32, alpha: float32) =
  drawRectangle(-20, -20, sw + 40, sh + 40, Color(r: 0, g: 0, b: 0, a: alphaByte(alpha * 200.0'f32)))
  let cy = (sh.float32 * 0.30'f32).int32
  let lands = BelowFirstAt + BelowFirstDur
  if local >= lands:
    drawHalo(sw.float32 * 0.5'f32, cy.float32 + 20.0'f32, 280.0'f32,
                 colorA(OldAmber, alpha * (20.0'f32 + 40.0'f32 * exp(-(local - lands) * 3.0'f32))), 1.0'f32)
  drawOldText(t(tkRogEndFirst), sw div 2, cy, 40, revealOver(local, BelowFirstAt, BelowFirstDur), local, alpha)
  # shooter.exe, hat and all, the intruder in this story.
  let px = sw.float32 * 0.5'f32
  let py = sh.float32 * 0.5'f32
  drawEquippedPlayerModel(newVector2f(px, py), 18.0'f32, local, alpha * 0.9'f32, 0.15'f32)
  drawTopHat(newVector2f(px, py), 18.0'f32, local, alpha * 0.9'f32)
  drawSubtitles([t(tkRogEndFirst1), t(tkRogEndFirst2)], sw, sh, alpha)

# ---------------------------------------------------------------------------
# DELVE 05: SHUTDOWN. The proper one.

proc drawShutdownShot(local, duration: float32, sw, sh: int32, alpha: float32) =
  let yes = BelowYesAt
  let safe = BelowSafeAt
  let goingDown = clamp01((local - (yes + 0.3'f32)) / (safe - yes - 0.6'f32))
  let iconsLeft = 5 - int(goingDown * 5.0'f32 + 0.001'f32)
  let deskA = alpha * (1.0'f32 - clamp01((local - (safe - 0.5'f32)) / 0.4'f32))
  if deskA > 0.0'f32:
    drawOldDesktop(sw, sh, local, deskA, iconsLeft)
    let (x, y, w, h) = oldScreenRect(sw, sh)
    let dlgA = deskA * (1.0'f32 - clamp01((local - (yes + 0.2'f32)) / 0.25'f32))
    if dlgA > 0.0'f32:
      let dw = 300'i32
      let dh = 120'i32
      let dx = x + (w - dw) div 2
      let dy = y + (h - dh) div 2 - 20
      drawBevel(dx, dy, dw, dh, dlgA)
      drawRectangle(dx + 3, dy + 3, dw - 6, 20, colorA(OldNavy, dlgA * 255.0'f32))
      drawText(t(tkRogEndShutdownTitle), dx + 8, dy + 7, 12, Color(r: 255, g: 255, b: 255, a: alphaByte(dlgA * 255.0'f32)))
      let body = t(tkRogEndShutdownBody)
      drawText(body, dx + 16, dy + 40, fitFontSize(body, dw - 32, 16), Color(r: 10, g: 10, b: 10, a: alphaByte(dlgA * 255.0'f32)))
      let pressed = local >= yes and local < yes + 0.15'f32
      let bx = dx + dw div 2 - 55
      let by = dy + dh - 36
      drawBevel(bx, by, 110, 26, dlgA, sunken = pressed)
      let go = t(tkRogEndShutdownGo)
      drawCenteredText(go, bx + 55, by + 7, fitFontSize(go, 100, 14), Color(r: 10, g: 10, b: 10, a: alphaByte(dlgA * 255.0'f32)))
      # The pointer that presses it is yours.
      let travel = easeInOut(clamp01((local - 0.15'f32) / (yes - 0.25'f32)))
      let ptx = lerpF((x + w - 40).float32, (bx + 60).float32, travel)
      let pty = lerpF((y + h - 50).float32, (by + 14).float32, travel)
      drawStoryPointer(ptx, pty, dlgA, pressed)

  # Black, and the line every old machine ended on.
  let safeA = alpha * clamp01((local - safe) / 0.8'f32)
  if local >= safe - 0.5'f32:
    drawRectangle(-20, -20, sw + 40, sh + 40,
                  Color(r: 0, g: 0, b: 0, a: alphaByte(alpha * clamp01((local - (safe - 0.5'f32)) / 0.4'f32) * 255.0'f32)))
  if safeA > 0.0'f32:
    let line = t(tkRogEndSafe)
    let size = fitFontSize(line, sw - 120, 26)
    drawCenteredText(line, sw div 2, (sh.float32 * 0.36'f32).int32, size, colorA(SafeOrange, safeA * 255.0'f32))

  drawSubtitles([t(tkRogEndShutdown1), t(tkRogEndShutdown2)], sw, sh, alpha)

# ---------------------------------------------------------------------------
# DELVE 06: CLEANUP COMPLETE. Back up, and the bar from REC 00 finishes.

proc drawRogSignoffShot(local, duration: float32, screenWidth, screenHeight: int32,
                        alpha: float32) =
  let cx = screenWidth.float32 * 0.5'f32
  let cy = screenHeight.float32 * 0.30'f32
  let rise = easeInOut(local / duration)
  for i in -2..2:
    drawRectangleGradientV((cx + i.float32 * 50.0'f32).int32 - 5, 0, 10, screenHeight,
                           colorA(RogAccent, 0.0'f32), colorA(RogAccent, alpha * rise * 46.0'f32))
  drawHalo(cx, cy, 260.0'f32, colorA(RogAccent, alpha * 50.0'f32), 1.0'f32)
  for i in 0..<18:
    let p = fractCoord(local * 0.5'f32 + i.float32 * 0.117'f32)
    let sx = cx + sin(i.float32 * 2.1'f32 + local) * (40.0'f32 + i.float32 * 5.0'f32)
    let sy = screenHeight.float32 * 0.94'f32 - p * screenHeight.float32 * 0.78'f32
    drawDisc(Vector2(x: sx, y: sy), 2.4'f32 * (1.0'f32 - p), colorA(RogAccent, alpha * (1.0'f32 - p) * 200.0'f32))
  const pr = 28.0'f32
  drawEquippedPlayerModel(newVector2f(cx, cy), pr, local, alpha, 0.3'f32)
  drawTopHat(newVector2f(cx, cy), pr, local, alpha)

  # Disk Cleanup, finishing the job it started in REC 00.
  let bw = min(420.0'f32, screenWidth.float32 * 0.5'f32)
  let bx = cx - bw * 0.5'f32
  let by = cy + 64.0'f32
  let frac = easeInOut(clamp01((local - 0.6'f32) / 1.8'f32))
  let barA = alpha * clamp01(local / 0.4'f32)
  drawText("old_system", bx.int32, by.int32 - 20, 14, Color(r: 230, g: 220, b: 200, a: alphaByte(barA * 230.0'f32)))
  let pct = $int(frac * 100.0'f32) & "%"
  drawText(pct, (bx + bw).int32 - measureText(pct, 14), by.int32 - 20, 14, colorA(RogAccent, barA * 230.0'f32))
  drawStoryProgress(bx, by, bw, 12.0'f32, frac, barA, RogAccent)

  let titleAlpha = alpha * easeInOut((local - 2.4'f32) / 0.8'f32)
  drawCenteredText(t(tkRogEndSignoffTitle), screenWidth div 2, (screenHeight * 2 div 3 - 40).int32,
                   34, Color(r: 255, g: 255, b: 255, a: alphaByte(titleAlpha * 255.0'f32)))
  let sub = t(tkRogEndSignoffSub)
  drawCenteredText(sub, screenWidth div 2, (screenHeight * 2 div 3 + 6).int32,
                   fitFontSize(sub, screenWidth - 80, 21), colorA(RogAccent, titleAlpha * 220.0'f32))

# ---------------------------------------------------------------------------
# Per-shot shake override

proc logShake(time, local, duration, alpha: float32): float32 =
  let hit = BelowLogStart + 6.0'f32 * BelowLogEvery
  if local >= hit:
    sin(time * 38.0'f32) * 3.0'f32 * exp(-(local - hit) * 2.0'f32)
  else:
    sin(time * 0.7'f32) * 1.0'f32 * alpha

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
      CutsceneShot(duration: BelowShots[0], drawProc: drawDescendShot, soundCue: stTeleport,
                   muteCue: true, label: t(tkRogEndRecDescend), iconIndex: 7),
      CutsceneShot(duration: BelowShots[1], drawProc: drawOldDesktopShot, soundCue: stMenuSelect,
                   muteCue: true, label: t(tkRogEndRecDesktop), iconIndex: 4),
      CutsceneShot(duration: BelowShots[2], drawProc: newBootLogShot(), soundCue: stMenuSelect,
                   muteCue: true, label: t(tkRogEndRecLog), iconIndex: 10,
                   glitchMod: 67, glitchWindow: 4, shakeProc: logShake),
      CutsceneShot(duration: BelowShots[3], drawProc: drawOtherRootShot, soundCue: stBossSpawn,
                   muteCue: true, label: t(tkRogEndRecFirst), iconIndex: 3,
                   glitchMod: 53, glitchWindow: 4),
      CutsceneShot(duration: BelowShots[4], drawProc: drawShutdownShot, soundCue: stMenuSelect,
                   muteCue: true, label: t(tkRogEndRecShutdown), iconIndex: 5),
      CutsceneShot(duration: BelowShots[5], drawProc: drawRogSignoffShot, soundCue: stWaveComplete,
                   muteCue: true, label: t(tkRogEndRecSignoff), iconIndex: 10),
    ],
    accentColor      = RogAccent,
    titleCardText    = "TopHat-ShooterOS",
    titleCardSub     = t(tkRogEndTitleCardSub),
    drawBackdropProc = rogueliteBackdrop,
    swayAmp          = 1.0'f32,
    musicTrack       = mtStoryBelow,
    cornerTag        = t(tkLorePlayback),
    captionCps       = EndingCaptionCps,
  )

# Legacy-style wrappers so main.nim mirrors the endgame-cinematic call sites.
type RogueliteEndCinematic* = Cutscene

proc newRogueliteEndCinematic*(): RogueliteEndCinematic = newRogueliteEndCutscene()

proc updateRogueliteEndCinematic*(c: RogueliteEndCinematic, dt: float32) =
  updateCutscene(c, dt)

proc drawRogueliteEndCinematic*(c: RogueliteEndCinematic, screenWidth, screenHeight: int) =
  drawCutscene(c, screenWidth, screenHeight)
