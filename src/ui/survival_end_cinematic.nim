## Survival Ending Cinematic: Act IV, UPTIME (LOG 01 to 05).
## Plays the first time a Time Survival run of 15+ minutes ends with no
## continue left (the trigger lives in game/death.nim). Years after root, there
## is no invader, only load, heat and age. The last surge gets through, the
## machine crashes, and from the outside that looks like a computer that keeps
## crashing, so someone reinstalls. A new OS boots clean on top, and from the
## unallocated space below it the hat types root's words from Act I. The cycle
## closes: TopHat-ShooterOS is now the system that was here first.
##
## Timing: sound.nim's story timing (UptimeShots, Uptime*), shared with the
## mtStoryUptime score in sound.nim.

import raylib, math, strutils
import ../draw_prims
import particle_types, background_fx, ../types, ../shapes, ../localization, ../sound,
       cinematic_common, cutscene, os_desktop

const
  SurAccent* = Color(r: 255, g: 120, b: 50, a: 255)   # ember-orange "uptime"
  HatCyan = Color(r: 0, g: 230, b: 230, a: 255)
  HalcyonBlue = Color(r: 60, g: 120, b: 210, a: 255)
  HalcyonInk = Color(r: 40, g: 50, b: 70, a: 255)
  HalcyonPaper = Color(r: 236, g: 240, b: 246, a: 255)

proc drawHatWearer(pos: Vector2f, radius, local, alpha, glow: float32) =
  ## shooter.exe as it is by now: root access, hat and all.
  drawEquippedPlayerModel(pos, radius, local, alpha, glow)
  drawTopHat(pos, radius, local, alpha)

# ---------------------------------------------------------------------------
# LOG 01: UPTIME. Days roll by on the dial while the load circles.

proc drawUptimeShot(local, duration: float32, screenWidth, screenHeight: int32,
                    alpha: float32) =
  let cx = screenWidth.float32 * 0.5'f32
  let cy = screenHeight.float32 * 0.40'f32
  drawHalo(cx, cy, 200.0'f32, colorA(SurAccent, alpha * 44.0'f32), 1.0'f32)
  let sweep = fractCoord(local * 0.9'f32) * 360.0'f32
  drawRing(Vector2(x: cx, y: cy), 88.0'f32, 92.0'f32, -90.0'f32, -90.0'f32 + sweep, 48,
           colorA(SurAccent, alpha * 210.0'f32))
  drawCircleOutline(Vector2(x: cx, y: cy), 90.0'f32, colorA(SurAccent, alpha * 70.0'f32))
  for i in 0..<12:
    let a = i.float32 * PI * 2.0'f32 / 12.0'f32 - PI * 0.5'f32
    drawStroke((cx + cos(a) * 82.0'f32).int32, (cy + sin(a) * 82.0'f32).int32,
               (cx + cos(a) * 90.0'f32).int32, (cy + sin(a) * 90.0'f32).int32,
               colorA(SurAccent, alpha * 130.0'f32))
  let kinds = [etThread, etForkBomb, etZombie, etThread, etWatchdog, etDaemon, etThread, etInterrupt]
  for i in 0..<14:
    let a = i.float32 * PI * 2.0'f32 / 14.0'f32 + local * 0.3'f32
    let r = 150.0'f32 + sin(local * 1.4'f32 + i.float32) * 22.0'f32
    drawRealEnemy(kinds[i mod kinds.len], cx + cos(a) * r, cy + sin(a) * r * 0.72'f32, 11.0'f32,
                  local, i, if i mod 6 == 0: 1 else: 0)
  drawHatWearer(newVector2f(cx, cy), 24.0'f32, local, alpha, 0.24'f32)

  # The counter that matters here: days, not seconds.
  let days = int(pow(clamp01(local / (duration * 0.85'f32)), 1.6'f32) * 1460.0'f32)
  let readY = (cy + 150.0'f32).int32
  drawCenteredText(t(tkSurEndUptimeLabel), screenWidth div 2, readY, 14, colorA(SurAccent, alpha * 170.0'f32))
  drawCenteredText(t(tkSurEndDays).replace("$1", $days), screenWidth div 2, readY + 18, 30,
                   Color(r: 255, g: 235, b: 210, a: alphaByte(alpha * 240.0'f32)))
  drawSubtitles([t(tkSurEndUptime1), t(tkSurEndUptime2)], screenWidth, screenHeight, alpha)

# ---------------------------------------------------------------------------
# LOG 02: THE LAST SURGE. Everything closes in; the heat climbs.

proc drawSurgeShot(local, duration: float32, screenWidth, screenHeight: int32,
                   alpha: float32) =
  let cx = screenWidth.float32 * 0.5'f32
  let cy = screenHeight.float32 * 0.42'f32
  let close = easeInOut(local / duration)
  let vig = alphaByte(alpha * close * 90.0'f32)
  let vw = (screenWidth.float32 * 0.4'f32).int32
  drawRectangleGradientH(0, 0, vw, screenHeight, Color(r: 255, g: 40, b: 20, a: vig), Color(r: 255, g: 40, b: 20, a: 0))
  drawRectangleGradientH(screenWidth - vw, 0, vw, screenHeight, Color(r: 255, g: 40, b: 20, a: 0),
                         Color(r: 255, g: 40, b: 20, a: vig))
  let kinds = [etThread, etForkBomb, etThread, etZombie, etInterrupt, etThread, etDeadlock]
  for i in 0..<24:
    let ang = hash01(i.float32 * 0.71'f32) * PI * 2.0'f32
    let startR = 360.0'f32 + hash01(i.float32 * 3.7'f32) * 160.0'f32
    let r = startR * (1.0'f32 - close * 0.86'f32)
    drawRealEnemy(kinds[i mod kinds.len], cx + cos(ang) * r, cy + sin(ang) * r * 0.8'f32,
                  10.0'f32 + (i mod 4).float32 * 3.0'f32, local, i, if i mod 5 == 0: 2 else: 0,
                  newVector2f(-cos(ang) * 120.0'f32, -sin(ang) * 120.0'f32))
  let flare = 0.24'f32 + close * 0.5'f32 + sin(local * 9.0'f32) * 0.1'f32
  drawHalo(cx, cy, 70.0'f32 + close * 30.0'f32, colorA(SurAccent, alpha * (60.0'f32 + close * 60.0'f32)), 1.0'f32)
  drawHatWearer(newVector2f(cx, cy), 24.0'f32, local, alpha, flare)

  # The machine's temperature, on the way to its trip point.
  let temp = lerpF(64.0'f32, 99.0'f32, close)
  let gx = screenWidth - 90
  let gTop = screenHeight div 9 + 50
  let gH = (screenHeight.float32 * 0.36'f32).int32
  let heat = clamp01((temp - 60.0'f32) / 40.0'f32)
  let heatCol = Color(r: 255, g: uint8(lerpF(200, 40, heat)), b: uint8(lerpF(80, 20, heat)), a: 255)
  drawRectangle(gx, gTop, 18, gH, Color(r: 20, g: 12, b: 10, a: alphaByte(alpha * 220.0'f32)))
  let fill = int32(gH.float32 * heat)
  drawRectangle(gx, gTop + gH - fill, 18, fill, colorA(heatCol, alpha * 230.0'f32))
  drawRectOutline(gx, gTop, 18, gH, colorA(SurAccent, alpha * 160.0'f32))
  let label = t(tkSurEndTemp)
  drawText(label, gx + 9 - measureText(label, 12) div 2, gTop - 32, 12, colorA(SurAccent, alpha * 200.0'f32))
  let reading = $int(temp) & "°C"   # UTF-8 degree sign; the font covers U+00B0
  drawCenteredText(reading, gx + 9, gTop - 16, 14, colorA(heatCol, alpha * 255.0'f32))
  drawSubtitles([t(tkSurEndSurge1), t(tkSurEndSurge2)], screenWidth, screenHeight, alpha)

# ---------------------------------------------------------------------------
# LOG 03: CRASH. The screen every run ends on, from the other side.

proc drawCrashShot(local, duration: float32, sw, sh: int32, alpha: float32) =
  drawCrashPanel(sw, sh, max(alpha, clamp01(local / 0.05'f32)), local)
  drawSubtitles([t(tkSurEndCrash1), t(tkSurEndCrash2)], sw, sh, alpha)

# ---------------------------------------------------------------------------
# LOG 04: REINSTALL. A cheerful installer formats the disk under us.

proc drawHalcyonLogo(cx, cy: float32, size, alpha: float32) =
  ## A rising sun over a line: pleasant, generic, nothing like a hat.
  drawRing(Vector2(x: cx, y: cy), size * 0.55'f32, size * 0.72'f32, 180.0'f32, 360.0'f32, 32,
           colorA(HalcyonBlue, alpha * 255.0'f32))
  drawDisc(Vector2(x: cx, y: cy), size * 0.3'f32, colorA(Color(r: 255, g: 190, b: 90, a: 255), alpha * 255.0'f32))
  drawRectangle((cx - size).int32, cy.int32, (size * 2.0'f32).int32, (size * 0.12'f32).int32 + 1,
                colorA(HalcyonBlue, alpha * 255.0'f32))

proc newReinstallShot(): CutsceneDrawProc =
  var icons: seq[DesktopIcon]
  for icon in newOSDesktop().icons:
    if icon.iconType notin {diCredits, diFeedback, diMods, diModApp, diModMode} and icons.len < 8:
      icons.add(icon)
  let title = t(tkSurEndInstallerTitle)
  let formatting = t(tkSurEndInstallerFormat)
  let warn = t(tkSurEndInstallerWarn)

  result = proc(local, duration: float32, sw, sh: int32, alpha: float32) =
    let frac = easeInOut(clamp01((local - UptimeFormatAt) / (duration - UptimeFormatAt - 1.0'f32)))
    # TopHat-ShooterOS's icons, wiped left to right as the format runs.
    let rowY = (sh.float32 * 0.52'f32).int32
    let spacing = min(100.0'f32, (sw.float32 * 0.84'f32) / icons.len.float32)
    let x0 = sw.float32 * 0.5'f32 - spacing * icons.len.float32 * 0.5'f32
    for i, base in icons:
      let ix = x0 + i.float32 * spacing + (spacing - ICON_SIZE.float32) * 0.5'f32
      let reach = frac * (icons.len.float32 + 1.0'f32) - i.float32
      if reach >= 1.0'f32:
        continue
      var icon = base
      icon.x = ix.int
      icon.y = rowY
      icon.selected = false
      drawDesktopIcon(icon, local, false)
      if reach > 0.0'f32:
        for k in 0..<10:
          let ny = rowY + int32(hash01(k.float32 + floor(local * 20.0'f32) + i.float32) * ICON_SIZE.float32)
          drawRectangle(ix.int32, ny, ICON_SIZE, 3, Color(r: 220, g: 230, b: 240, a: alphaByte(alpha * reach * 230.0'f32)))
        drawRectangle(ix.int32, rowY, ICON_SIZE, ICON_SIZE + 40, Color(r: 0, g: 0, b: 0, a: alphaByte(alpha * reach * 200.0'f32)))

    # The installer: light, rounded, polite. Not ours.
    let pw = min(560.0'f32, sw.float32 * 0.62'f32)
    let ph = 190.0'f32
    let px = sw.float32 * 0.5'f32 - pw * 0.5'f32
    let py = (sh div 9).float32 + 26.0'f32
    let rec = Rectangle(x: px, y: py, width: pw, height: ph)
    drawRectangleRounded(Rectangle(x: px + 4.0'f32, y: py + 6.0'f32, width: pw, height: ph), 0.08'f32, 8,
                         Color(r: 0, g: 0, b: 0, a: alphaByte(alpha * 90.0'f32)))
    drawRectangleRounded(rec, 0.08'f32, 8, colorA(HalcyonPaper, alpha * 255.0'f32))
    drawText(title, px.int32 + 84, py.int32 + 26, fitFontSize(title, pw.int32 - 110, 22), colorA(HalcyonInk, alpha * 255.0'f32))
    drawHalcyonLogo(px + 46.0'f32, py + 46.0'f32, 22.0'f32, alpha)
    drawText(formatting, px.int32 + 30, py.int32 + 86, fitFontSize(formatting, pw.int32 - 60, 16),
             colorA(HalcyonInk, alpha * 230.0'f32))
    let bx = px + 30.0'f32
    let by = py + 112.0'f32
    let bw = pw - 60.0'f32
    drawRectangleRounded(Rectangle(x: bx, y: by, width: bw, height: 12.0'f32), 0.5'f32, 6,
                         Color(r: 205, g: 214, b: 228, a: alphaByte(alpha * 255.0'f32)))
    if frac > 0.0'f32:
      drawRectangleRounded(Rectangle(x: bx, y: by, width: max(12.0'f32, bw * frac), height: 12.0'f32), 0.5'f32, 6,
                           colorA(HalcyonBlue, alpha * 255.0'f32))
    let pct = $int(frac * 100.0'f32) & "%"
    drawText(pct, (bx + bw).int32 - measureText(pct, 14), by.int32 + 18, 14, colorA(HalcyonInk, alpha * 200.0'f32))
    drawText(warn, px.int32 + 30, py.int32 + 150, fitFontSize(warn, pw.int32 - 120, 13),
             Color(r: 120, g: 128, b: 145, a: alphaByte(alpha * 255.0'f32)))
    drawSubtitles([t(tkSurEndReinstall1), t(tkSurEndReinstall2)], sw, sh, alpha)

# ---------------------------------------------------------------------------
# LOG 05: UNALLOCATED. The new system boots clean. Something below answers.

proc drawUnallocatedShot(local, duration: float32, sw, sh: int32, alpha: float32) =
  drawRectangle(-20, -20, sw + 40, sh + 40, Color(r: 0, g: 0, b: 0, a: 255))
  let endA = clamp01((duration - local) / 1.2'f32)
  # The new OS's welcome screen, then the camera sinks below it.
  let sink = easeInOut(clamp01((local - UptimeSinkAt) / 1.0'f32))
  let top = (sh div 9).float32
  let panelH = sh.float32 * 0.44'f32
  let panelY = top - sink * (panelH + 60.0'f32)
  let bootA = clamp01((local - UptimeNewBootAt) / 0.4'f32)
  if panelY + panelH > top:
    drawRectangle(0, panelY.int32, sw, panelH.int32, colorA(HalcyonPaper, bootA * 255.0'f32))
    drawHalcyonLogo(sw.float32 * 0.5'f32, panelY + panelH * 0.4'f32, 34.0'f32, bootA)
    drawCenteredText("HALCYON OS", sw div 2, (panelY + panelH * 0.4'f32 + 20.0'f32).int32, 30,
                     colorA(HalcyonInk, bootA * 255.0'f32))
    let welcome = t(tkSurEndWelcome)
    drawCenteredText(welcome, sw div 2, (panelY + panelH * 0.4'f32 + 60.0'f32).int32,
                     fitFontSize(welcome, sw - 80, 18), colorA(HalcyonInk, bootA * 200.0'f32))
    # Its partition table, the floor everything older now lives under.
    let floorY = (panelY + panelH + 18.0'f32).int32
    drawRectangle(0, floorY, sw, 2, colorA(HalcyonBlue, bootA * 200.0'f32))
    drawText(t(tkEndPartitionTable), sw div 9, floorY + 8, 13, colorA(HalcyonBlue, bootA * 180.0'f32))

  # Below it: the hat, and the words root said first.
  let cy = (sh.float32 * 0.38'f32).int32
  let a = endA * clamp01((local - (UptimeWhoAt - 0.6'f32)) / 0.5'f32)
  if a > 0.0'f32:
    let size = 40'i32
    let widest = max(measureText(t(tkLoreWho), size), measureText(t(tkLoreMachine), size))
    let hx = (sw div 2 - widest div 2 - 52).float32
    drawHalo(hx, cy.float32 + 18.0'f32, 70.0'f32, colorA(HatCyan, a * 80.0'f32), 1.0'f32)
    drawTopHat(newVector2f(hx, cy.float32 + 36.0'f32), 26.0'f32, local, a)
    let second = local >= UptimeMachineAt
    drawOldText(t(tkLoreWho), sw div 2, cy, size, revealOver(local, UptimeWhoAt, UptimeWhoDur), local, a,
                HatCyan, cursor = not second)
    if second:
      drawOldText(t(tkLoreMachine), sw div 2, cy + 60, size,
                  revealOver(local, UptimeMachineAt, UptimeMachineDur), local, a, HatCyan)

# ---------------------------------------------------------------------------
# Per-shot shake overrides

proc surgeShake(time, local, duration, alpha: float32): float32 =
  sin(time * 40.0'f32) * 2.8'f32 * alpha * easeInOut(local / duration)

proc crashShake(time, local, duration, alpha: float32): float32 =
  sin(time * 45.0'f32) * 7.0'f32 * exp(-local * 6.0'f32)

# ---------------------------------------------------------------------------
# Backdrop, cools from ember toward ash.

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
      CutsceneShot(duration: UptimeShots[0], drawProc: drawUptimeShot, soundCue: stShield,
                   muteCue: true, label: t(tkSurEndRecUptime), iconIndex: 4),
      CutsceneShot(duration: UptimeShots[1], drawProc: drawSurgeShot, soundCue: stExplosion,
                   muteCue: true, label: t(tkSurEndRecSurge), iconIndex: 0,
                   glitchMod: 59, glitchWindow: 6, shakeProc: surgeShake),
      CutsceneShot(duration: UptimeShots[2], drawProc: drawCrashShot, soundCue: stGameOver,
                   muteCue: true, label: t(tkSurEndRecCrash), iconIndex: 7,
                   glitchMod: 41, glitchWindow: 7, shakeProc: crashShake),
      CutsceneShot(duration: UptimeShots[3], drawProc: newReinstallShot(), soundCue: stMenuSelect,
                   muteCue: true, label: t(tkSurEndRecReinstall), iconIndex: 10),
      CutsceneShot(duration: UptimeShots[4], drawProc: drawUnallocatedShot, soundCue: stMenuSelect,
                   muteCue: true, label: t(tkSurEndRecUnallocated), iconIndex: 3,
                   glitchMod: 37, glitchWindow: 3),
    ],
    accentColor      = SurAccent,
    titleCardText    = "TopHat-ShooterOS",
    titleCardSub     = t(tkSurEndTitleCardSub),
    drawBackdropProc = survivalBackdrop,
    swayAmp          = 1.0'f32,
    musicTrack       = mtStoryUptime,
    cornerTag        = t(tkLorePlayback),
    captionCps       = EndingCaptionCps,
  )

# Legacy-style wrappers so main.nim mirrors the endgame-cinematic call sites.
type SurvivalEndCinematic* = Cutscene

proc newSurvivalEndCinematic*(): SurvivalEndCinematic = newSurvivalEndCutscene()

proc updateSurvivalEndCinematic*(c: SurvivalEndCinematic, dt: float32) =
  updateCutscene(c, dt)

proc drawSurvivalEndCinematic*(c: SurvivalEndCinematic, screenWidth, screenHeight: int) =
  drawCutscene(c, screenWidth, screenHeight)
