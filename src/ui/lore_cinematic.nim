## Lore Cinematic: Act I, CLEANUP (REC 00 to REC 05), the first-launch intro.
## A cold open on the real desktop: Disk Cleanup cannot delete old_system,
## because its owner is a root that is not TOPHAT. Root's processes flood the
## Task Manager, root speaks for the first time (WHO ARE YOU? / THIS IS MY
## MACHINE.), TOPHAT spawns shooter.exe, root re-owns the eleven services the
## wave bosses are made from, and the title drops.
##
## Every beat's timing lives in sound.nim's story timing (IntroShots, Intro*): the
## score in sound.nim (mtStoryIntro) is composed against the same numbers, so
## change a beat there, never as a literal here.

import raylib, math
import ../draw_prims
from std/unicode import runeLen, runeSubStr
import particle_types, background_fx, ../types, ../localization, ../sound, ../boss_definitions,
       ../shapes, ../powerup_data, icon_drawing, cinematic_common, cutscene, os_desktop

const
  LoreAccent = Color(r: 0, g: 230, b: 230, a: 255)
  ServiceCount = 11   # bosses 1-11 are TOPHAT's services; boss 12 is root
  DesktopUptime = 14.0'f32 * 3600.0'f32 + 1325.0'f32
    ## The system monitor's uptime on the filmed desktop: a machine that has
    ## been running quietly for a while.

# ---------------------------------------------------------------------------
# The filmed desktop: the player's own, with their wallpaper, cube and icons.

type StoryDesktop = ref object
  desktop: OSDesktop
  baseNames: seq[string]
  baseColors: seq[Color]
  laidOutW: int32

proc newStoryDesktop(): StoryDesktop =
  StoryDesktop(desktop: newOSDesktop(), laidOutW: -1)

proc prep(sd: StoryDesktop, sw, sh: int32, time: float32) =
  if sd.laidOutW != sw:
    layoutDesktopIcons(sd.desktop, sw, sh)
    sd.laidOutW = sw
    sd.baseNames.setLen(0)
    sd.baseColors.setLen(0)
    for icon in sd.desktop.icons:
      sd.baseNames.add(icon.name)
      sd.baseColors.add(icon.iconColor)
  sd.desktop.time = DesktopUptime + time
  sd.desktop.cubeRotX = time * 0.35'f32 + 0.4'f32
  sd.desktop.cubeRotY = time * 0.5'f32 + 0.6'f32
  sd.desktop.cubeRotZ = 0.2'f32
  for i in 0..<sd.desktop.icons.len:
    sd.desktop.icons[i].selected = false
    sd.desktop.icons[i].name = sd.baseNames[i]
    sd.desktop.icons[i].iconColor = sd.baseColors[i]

const GlitchGlyphs = "#%@&$*01?!"

proc scrambleLabel(name: string, corruption, time: float32, seed: int): string =
  ## Letters flip to glitch glyphs as corruption rises; ASCII only.
  result = name
  for j in 0..<result.len:
    if result[j] in {'A'..'Z', 'a'..'z', '0'..'9'} and
       hash01(j.float32 * 3.1'f32 + seed.float32 * 7.7'f32) < corruption:
      let g = int(hash01(j.float32 + floor(time * 14.0'f32) + seed.float32) * GlitchGlyphs.len.float32)
      result[j] = GlitchGlyphs[clamp(g, 0, GlitchGlyphs.high)]

proc drawRedEdges(sw, sh: int32, strength: float32) =
  if strength <= 0.0'f32:
    return
  let edge = (sw.float32 * 0.22'f32).int32
  let c = colorA(RootRed, strength * 70.0'f32)
  let clear = colorA(RootRed, 0.0'f32)
  drawRectangleGradientH(0, 0, edge, sh, c, clear)
  drawRectangleGradientH(sw - edge, 0, edge, sh, clear, c)

proc drawCheck(x, y: int32, alpha: float32) =
  drawRectOutline(x, y, 14, 14, colorA(ChromeCyan, alpha * 220.0'f32))
  drawStroke(Vector2(x: x.float32 + 3.0'f32, y: y.float32 + 7.0'f32),
             Vector2(x: x.float32 + 6.0'f32, y: y.float32 + 11.0'f32), 2.0'f32, colorA(ChromeCyan, alpha * 255.0'f32))
  drawStroke(Vector2(x: x.float32 + 6.0'f32, y: y.float32 + 11.0'f32),
             Vector2(x: x.float32 + 12.0'f32, y: y.float32 + 3.0'f32), 2.0'f32, colorA(ChromeCyan, alpha * 255.0'f32))

# ---------------------------------------------------------------------------
# REC 00: MAINTENANCE. Disk Cleanup meets a folder it cannot delete.

proc newCleanupShot(): CutsceneDrawProc =
  let sd = newStoryDesktop()
  let title = t(tkLoreCleanupTitle)
  let header = t(tkLoreCleanupHeader)
  let rows = [(t(tkLoreCleanupTemp), "0.3 GB"), (t(tkLoreCleanupBin), "0.1 GB"), ("old_system", "3.8 GB")]
  let goLabel = t(tkLoreCleanupGo)
  let cancelLabel = t(tkLoreCleanupCancel)
  let deleting = t(tkLoreCleanupDeleting)
  let denied1 = t(tkLoreCleanupDenied1)
  let denied2 = t(tkLoreCleanupDenied2)
  let okLabel = t(tkLoreOk)

  result = proc(local, duration: float32, sw, sh: int32, alpha: float32) =
    sd.prep(sw, sh, local)
    let swf = sw.float32
    let shf = sh.float32
    const dw = 470.0'f32
    const dh = 270.0'f32
    let dx = swf * 0.5'f32 - dw * 0.5'f32
    let dy = shf * 0.5'f32 - dh * 0.5'f32 - 50.0'f32
    let errored = local >= IntroCleanupError

    # Wide on the whole desktop, then a slow push in on the dialog.
    let push = easeInOut(clamp01((local - 0.6'f32) / (duration - 0.6'f32)))
    let scale = lerpF(0.74'f32, 0.95'f32, push)
    beginStoryCamera(lerpF(swf * 0.5'f32, dx + dw * 0.5'f32, push),
                     lerpF(shf * 0.5'f32, dy + dh * 0.5'f32 + 40.0'f32, push),
                     swf * 0.5'f32, lerpF(shf * 0.5'f32, shf * 0.44'f32, push), scale)
    drawOSDesktop(sd.desktop, sw, sh)
    drawFootageFrame(sw, sh, scale, alpha)

    let open = easeOut(clamp01((local - IntroCleanupOpen) / 0.3'f32))
    if open > 0.0'f32:
      let a = alpha * open
      let y0 = dy + (1.0'f32 - open) * 14.0'f32
      let xi = dx.int32
      let yi = y0.int32
      drawStoryWindow(dx, y0, dw, dh, title, a, Color(r: 120, g: 200, b: 255, a: 255))
      drawText(header, xi + 20, yi + 44, fitFontSize(header, dw.int32 - 40, 15),
               Color(r: 200, g: 215, b: 230, a: alphaByte(a * 255.0'f32)))
      for i, (label, size) in rows:
        let ry = yi + 76 + i.int32 * 30
        let doomed = i == 2 and errored
        drawCheck(xi + 22, ry + 1, a)
        drawText(label, xi + 46, ry, 16,
                 if doomed: colorA(RootRed, a * 255.0'f32)
                 else: Color(r: 235, g: 240, b: 250, a: alphaByte(a * 255.0'f32)))
        drawText(size, xi + dw.int32 - 24 - measureText(size, 16), ry, 16,
                 Color(r: 150, g: 170, b: 190, a: alphaByte(a * 255.0'f32)))
      # Deleting: the bar crawls, then stops dead at the folder it cannot touch.
      let runStart = IntroCleanupClick + 0.2'f32
      if local >= runStart:
        let frac = 0.61'f32 * easeOut(clamp01((local - runStart) / (IntroCleanupStall - runStart)))
        let py = yi + 186
        let status = deleting & " old_system... " & $int(frac * 100.0'f32) & "%"
        drawText(status, xi + 20, py - 20, 14,
                 if errored: colorA(RootRed, a * 255.0'f32)
                 else: Color(r: 170, g: 200, b: 220, a: alphaByte(a * 255.0'f32)))
        drawStoryProgress(dx + 20.0'f32, py.float32, dw - 40.0'f32, 14.0'f32, frac, a,
                          if errored: RootRed else: ChromeCyan)
      let by = y0 + dh - 46.0'f32
      let pressed = local >= IntroCleanupClick and local < IntroCleanupClick + 0.15'f32
      drawStoryButton(dx + dw - 252.0'f32, by, 112.0'f32, 32.0'f32, goLabel, a, pressed, primary = true)
      drawStoryButton(dx + dw - 130.0'f32, by, 112.0'f32, 32.0'f32, cancelLabel, a)

      # The pointer: glides onto "Clean up", clicks, then drifts off.
      let target = Vector2(x: dx + dw - 196.0'f32, y: by + 18.0'f32)
      let start = Vector2(x: swf * 0.8'f32, y: shf * 0.76'f32)
      let glideAt = IntroCleanupOpen + 0.5'f32
      let travel = easeInOut(clamp01((local - glideAt) / (IntroCleanupClick - 0.08'f32 - glideAt)))
      let drift = easeInOut(clamp01((local - (IntroCleanupClick + 0.3'f32)) / 1.6'f32))
      let px = lerpF(start.x, target.x, travel) + drift * 46.0'f32
      let py = lerpF(start.y, target.y, travel) + drift * 34.0'f32
      drawStoryPointer(px, py, alpha * clamp01((local - (IntroCleanupOpen + 0.2'f32)) / 0.3'f32), pressed)

    # Permission denied, in a window of its own on top.
    let errA = easeOut(clamp01((local - IntroCleanupError) / 0.18'f32))
    if errA > 0.0'f32:
      let a = alpha * errA
      # Below the stalled bar, so the red old_system row and bar stay in view.
      const ew = 400.0'f32
      const eh = 150.0'f32
      let ex = dx + dw * 0.5'f32 - ew * 0.5'f32 + 40.0'f32
      let ey = dy + 206.0'f32 + (1.0'f32 - errA) * 10.0'f32
      drawStoryWindow(ex, ey, ew, eh, title, a, RootRed, RootRed)
      let ix = ex.int32 + 22
      let iy = ey.int32 + 48
      drawRectangle(ix, iy, 40, 40, Color(r: 70, g: 18, b: 26, a: alphaByte(a * 255.0'f32)))
      drawRectOutline(ix, iy, 40, 40, colorA(RootRed, a * 255.0'f32))
      drawText("X", ix + 13, iy + 9, 24, colorA(RootRed, a * 255.0'f32))
      let tw = ew.int32 - 104
      drawText(denied1, ix + 56, iy + 2, fitFontSize(denied1, tw, 16),
               Color(r: 235, g: 240, b: 250, a: alphaByte(a * 255.0'f32)))
      drawText(denied2, ix + 56, iy + 24, fitFontSize(denied2, tw, 16), colorA(RootRed, a * 255.0'f32))
      drawStoryButton(ex + ew * 0.5'f32 - 45.0'f32, ey + eh - 44.0'f32, 90.0'f32, 30.0'f32, okLabel, a, primary = true)
    endStoryCamera()

    drawRedEdges(sw, sh, alpha * errA * (0.6'f32 + 0.4'f32 * sin(local * 9.0'f32)))
    drawSubtitles([t(tkLoreCleanup1), t(tkLoreCleanup2)], sw, sh, alpha)

# ---------------------------------------------------------------------------
# REC 01: SECOND ROOT. Processes owned by a root that is not TOPHAT fill the
# Task Manager, rot the desktop icons, and crawl out of them.

proc newFloodShot(): CutsceneDrawProc =
  let sd = newStoryDesktop()
  const kinds = [etCircle, etCube, etTriangle, etStar, etCross, etDiamond, etOctagon,
                 etPentagon, etHexagon, etTrickster, etPhantom]
  const procNames = ["circle.exe", "cube.exe", "triangle.exe", "star.exe", "cross.exe", "diamond.exe",
                     "octagon.exe", "pentagon.exe", "hexagon.exe", "trickster.exe", "phantom.exe"]
  const ownRows = [("tophat.sys", "2%"), ("desktop.exe", "1%"), ("cleanup.exe", "0%")]
  let tmTitle = t(tkLoreTaskManager)
  let colProc = t(tkLoreColProcess)
  let colOwner = t(tkLoreColOwner)
  let colCpu = t(tkLoreColCpu)

  result = proc(local, duration: float32, sw, sh: int32, alpha: float32) =
    sd.prep(sw, sh, local + IntroShots[0])
    let swf = sw.float32
    let shf = sh.float32
    let scale = lerpF(0.8'f32, 0.86'f32, easeInOut(local / duration))
    beginStoryCamera(swf * 0.5'f32, shf * 0.47'f32, swf * 0.5'f32, shf * 0.42'f32, scale)

    # Icons rot one after another; the desktop draws them with the damage.
    let icons = sd.desktop.icons.len
    var rot = newSeq[float32](icons)
    for i in 0..<icons:
      rot[i] = clamp01((local - (0.8'f32 + i.float32 * 0.28'f32)) / 1.0'f32)
      sd.desktop.icons[i].name = scrambleLabel(sd.baseNames[i], rot[i], local, i)
      if rot[i] > 0.5'f32:
        sd.desktop.icons[i].iconColor = RootRed
    drawOSDesktop(sd.desktop, sw, sh)
    drawFootageFrame(sw, sh, scale, alpha)
    for i in 0..<icons:
      let c = rot[i]
      if c <= 0.0'f32:
        continue
      let x0 = sd.desktop.icons[i].x.int32
      let y0 = sd.desktop.icons[i].y.int32
      drawRectangle(x0, y0, ICON_SIZE, ICON_SIZE, colorA(RootRed, alpha * c * 60.0'f32))
      for k in 0..<3:
        let bandY = y0 + int32(hash01(k.float32 + floor(local * 9.0'f32) + i.float32) * (ICON_SIZE - 4).float32)
        let off = int32((hash01(k.float32 * 5.0'f32 + local) - 0.5'f32) * 14.0'f32 * c)
        drawRectangle(x0 + off, bandY, ICON_SIZE, 3,
                      if k mod 2 == 0: colorA(RootRed, alpha * c * 170.0'f32)
                      else: Color(r: 0, g: 255, b: 255, a: alphaByte(alpha * c * 110.0'f32)))

    # ...and the processes crawl out of them.
    if icons > 0:
      for i in 0..<20:
        let src = sd.desktop.icons[(i * 5) mod icons]
        let p = easeOut(clamp01((local - (1.5'f32 + i.float32 * 0.19'f32)) / 2.6'f32))
        if p <= 0.0'f32:
          continue
        let ang = hash01(i.float32 + 2.2'f32) * PI * 2.0'f32
        let dist = p * (90.0'f32 + hash01(i.float32 + 7.0'f32) * 170.0'f32)
        let ex = src.x.float32 + ICON_SIZE.float32 * 0.5'f32 + cos(ang) * dist
        let ey = src.y.float32 + ICON_SIZE.float32 * 0.5'f32 + sin(ang) * dist * 0.7'f32
        drawRealEnemy(kinds[i mod kinds.len], ex, ey, (9.0'f32 + (i mod 3).float32 * 2.0'f32) * (0.4'f32 + p * 0.6'f32),
                      local, i, if i mod 7 == 0: 2 else: 0, newVector2f(cos(ang) * 80.0'f32, sin(ang) * 50.0'f32))

    # Task Manager: TOPHAT's three processes, then rows it never started.
    let tw = min(450.0'f32, swf * 0.44'f32)
    let tx = swf * 0.53'f32
    let ty = 96.0'f32
    let th = 392.0'f32
    drawStoryWindow(tx, ty, tw, th, tmTitle, alpha, Color(r: 120, g: 220, b: 160, a: 255))
    let xi = tx.int32
    let yi = ty.int32
    let twi = tw.int32
    let ownerX = xi + twi - 150
    let cpuX = xi + twi - 62
    let hdr = Color(r: 140, g: 160, b: 180, a: alphaByte(alpha * 255.0'f32))
    drawText(colProc, xi + 40, yi + 40, 14, hdr)
    drawText(colOwner, ownerX, yi + 40, 14, hdr)
    drawText(colCpu, cpuX, yi + 40, 14, hdr)
    drawRectangle(xi + 10, yi + 58, twi - 20, 1, Color(r: 70, g: 80, b: 100, a: alphaByte(alpha * 200.0'f32)))
    var spawned = 0
    for i in 0..<IntroProcRows:
      if local >= IntroProcRowStart + i.float32 * IntroProcRowEvery:
        spawned = i + 1
    const rowH = 22'i32
    const visible = 12
    let total = ownRows.len + spawned
    let first = max(0, total - visible)
    for r in first..<total:
      let ry = yi + 66 + (r - first).int32 * rowH
      if r < ownRows.len:
        let (name, cpu) = ownRows[r]
        drawRectangle(xi + 18, ry + 3, 12, 12, colorA(LoreAccent, alpha * 200.0'f32))
        drawText(name, xi + 40, ry, 16, Color(r: 220, g: 235, b: 245, a: alphaByte(alpha * 255.0'f32)))
        drawText("tophat", ownerX, ry, 16, colorA(LoreAccent, alpha * 255.0'f32))
        drawText(cpu, cpuX, ry, 16, Color(r: 160, g: 180, b: 200, a: alphaByte(alpha * 255.0'f32)))
      else:
        let k = r - ownRows.len
        let bornAt = IntroProcRowStart + k.float32 * IntroProcRowEvery
        let fresh = 1.0'f32 - clamp01((local - bornAt) / 0.35'f32)
        if fresh > 0.0'f32:
          drawRectangle(xi + 6, ry - 2, twi - 12, rowH, colorA(RootRed, alpha * fresh * 90.0'f32))
        drawRealEnemy(kinds[k mod kinds.len], (xi + 24).float32, (ry + 8).float32, 6.0'f32, local, 500 + k)
        drawText(procNames[k mod procNames.len], xi + 40, ry, 16,
                 Color(r: 255, g: 215, b: 220, a: alphaByte(alpha * 255.0'f32)))
        drawText("root", ownerX, ry, 16, colorA(RootRed, alpha * 255.0'f32))
        drawText($(4 + (k * 7) mod 9) & "%", cpuX, ry, 16, colorA(RootRed, alpha * 220.0'f32))
    # Total load climbs to the red.
    let load = clamp01(0.06'f32 + spawned.float32 * 0.068'f32)
    let barY = (ty + th - 34.0'f32)
    drawText("CPU", xi + 16, barY.int32 + 1, 14, hdr)
    let loadCol = Color(r: uint8(lerpF(0, 255, load)), g: uint8(lerpF(200, 70, load)), b: uint8(lerpF(255, 90, load)), a: 255)
    drawStoryProgress(tx + 56.0'f32, barY, tw - 120.0'f32, 16.0'f32, load, alpha, loadCol)
    drawText($int(load * 100.0'f32) & "%", xi + twi - 54, barY.int32 + 1, 14, colorA(loadCol, alpha * 255.0'f32))
    endStoryCamera()

    drawRedEdges(sw, sh, alpha * clamp01((local - 1.2'f32) / 4.2'f32) * (0.7'f32 + 0.3'f32 * sin(local * 13.0'f32)))
    drawSubtitles([t(tkLoreFlood1), t(tkLoreFlood2)], sw, sh, alpha)

# ---------------------------------------------------------------------------
# REC 02: UNKNOWN USER. The other root speaks.

proc drawWhoShot(local, duration: float32, sw, sh: int32, alpha: float32) =
  # A hard cut to black: this shot ignores the usual fade-in.
  let a = clamp01((duration - local) / 0.9'f32)
  drawRectangle(-20, -20, sw + 40, sh + 40, Color(r: 0, g: 0, b: 0, a: 255))
  var y = sh div 9 + 8
  while y < sh - sh div 9:
    drawRectangle(0, y, sw, 1, Color(r: 255, g: 176, b: 40, a: alphaByte(a * 10.0'f32)))
    y += 3
  drawOldText("login: root", sw div 9, sh div 9 + 26, 16, revealOver(local, 0.1'f32, 0.45'f32), local,
              a * 0.55'f32, centered = false, cursor = false)

  let cy = (sh.float32 * 0.40'f32).int32
  let whoLands = IntroWhoAt + IntroWhoDur
  let machineLands = IntroMachineAt + IntroMachineDur
  # Each line glows as it lands, on the score's beep.
  for land in [whoLands, machineLands]:
    if local >= land:
      let flash = exp(-(local - land) * 4.0'f32)
      drawHalo(sw.float32 * 0.5'f32, cy.float32 + 40.0'f32, 190.0'f32,
                   colorA(OldAmber, a * flash * 22.0'f32), 1.0'f32)
  let second = local >= IntroMachineAt
  drawOldText(t(tkLoreWho), sw div 2, cy, 44, revealOver(local, IntroWhoAt, IntroWhoDur), local, a,
              cursor = not second)
  if second:
    drawOldText(t(tkLoreMachine), sw div 2, cy + 66, 44,
                revealOver(local, IntroMachineAt, IntroMachineDur), local, a)
  # TOPHAT explains what just spoke, once it has finished speaking.
  drawSubtitlesFrom([t(tkLoreWhoCaption1), t(tkLoreWhoCaption2)], IntroWhoCaptionAt, sw, sh, a)

# ---------------------------------------------------------------------------
# REC 03: SHOOTER.EXE. A kernel cannot fight, so it makes something that can.

proc drawSpawnShot(local, duration: float32, sw, sh: int32, alpha: float32) =
  let cx = sw.float32 * 0.5'f32
  let ky = sh.float32 * 0.26'f32
  let py = sh.float32 * 0.56'f32

  drawHalo(cx, ky, 110.0'f32, colorA(LoreAccent, alpha * 34.0'f32), 1.0'f32)
  drawKernelModel(newVector2f(cx, ky), 28.0'f32, local, 1.0'f32, alpha)

  # fork(): a beam from the kernel down to where the new process lands.
  let beam = easeInOut(clamp01((local - 1.4'f32) / (IntroBootAt - 1.4'f32)))
  let beamTop = ky + 60.0'f32
  let beamBottom = lerpF(beamTop, py, beam)
  if beam > 0.0'f32:
    let bh = (beamBottom - beamTop).int32
    drawRectangleGradientV((cx - 7.0'f32).int32, beamTop.int32, 14, bh,
                           colorA(LoreAccent, alpha * 190.0'f32), colorA(LoreAccent, alpha * 70.0'f32))
    drawRectangle((cx - 1.5'f32).int32, beamTop.int32, 3, bh,
                  Color(r: 230, g: 255, b: 255, a: alphaByte(alpha * 230.0'f32)))
    for k in 0..<9:
      let p = fractCoord(local * 1.4'f32 + k.float32 / 9.0'f32)
      drawRectangle((cx - 4.0'f32).int32, lerpF(beamTop, beamBottom, p).int32, 8, 6,
                    colorA(LoreAccent, alpha * 220.0'f32 * (1.0'f32 - p * 0.5'f32)))

  let boot = easeOut(clamp01((local - IntroBootAt) / 0.5'f32))
  if local >= IntroBootAt:
    let ring = clamp01((local - IntroBootAt) / 0.6'f32)
    drawCircleOutline(Vector2(x: cx, y: py), 18.0'f32 + ring * 80.0'f32,
                      colorA(LoreAccent, alpha * (1.0'f32 - ring) * 230.0'f32))
  if boot > 0.0'f32:
    drawHalo(cx, py, 100.0'f32 * boot, Color(r: 0, g: 220, b: 255, a: alphaByte(alpha * 40.0'f32)), 1.0'f32)
    drawEquippedPlayerModel(newVector2f(cx, py), 30.0'f32 * (0.3'f32 + boot * 0.7'f32), local, alpha * boot, 0.22'f32)
    drawCenteredText("shooter.exe", cx.int32, (py + 44.0'f32).int32, 16, colorA(LoreAccent, alpha * boot * 220.0'f32))

  # The kernel's own log of what it just did.
  let logX = (cx + 96.0'f32).int32
  let logY = (ky - 34.0'f32).int32
  let lines = [(t(tkLoreBoot1), 0.4'f32, Color(r: 130, g: 190, b: 200, a: 255)),
               (t(tkLoreBoot2), 1.3'f32, LoreAccent),
               (t(tkLoreBoot3), IntroBootAt + 0.2'f32, Color(r: 120, g: 255, b: 190, a: 255))]
  var shownAny = false
  for i, (text, at, col) in lines:
    let n = int((local - at) * 40.0'f32)
    if n <= 0:
      continue
    shownAny = true
    drawText(text.runeSubStr(0, min(n, text.runeLen)), logX + 12, logY + 10 + i.int32 * 22, 15,
             colorA(col, alpha * 235.0'f32))
  if shownAny:
    drawRectOutline(logX, logY, max(300'i32, sw - logX - 40).min(360), 80, colorA(LoreAccent, alpha * 90.0'f32))

  drawSubtitles([t(tkLoreSpawn1), t(tkLoreSpawn2)], sw, sh, alpha)

# ---------------------------------------------------------------------------
# REC 04: SERVICES. Root answers by re-owning TOPHAT's services, one by one.
# These are the eleven wave bosses; the last silhouette is root itself.

proc newHijackShot(): CutsceneDrawProc =
  var services: seq[string]
  for id in 1..ServiceCount:
    services.add(getBossProcessName(id))
  let winTitle = t(tkLoreServicesWindow)
  let colService = t(tkLoreColService)
  let colOwner = t(tkLoreColOwner)
  var flipTimes: seq[float32]
  for i in 0..<ServiceCount:
    flipTimes.add(IntroFlipStart + i.float32 * IntroFlipEvery)
  var bosses: seq[Enemy]
  var root: Enemy

  result = proc(local, duration: float32, sw, sh: int32, alpha: float32) =
    if bosses.len == 0:
      for id in 1..ServiceCount:
        bosses.add(newCinematicBoss(id, sw, sh))
      root = newCinematicBoss(12, sw, sh)
    var flipped = 0
    for i in 0..<ServiceCount:
      if local >= IntroFlipStart + i.float32 * IntroFlipEvery:
        flipped = i + 1

    # The service list.
    drawServiceWindow(sw.float32 * 0.07'f32, 96.0'f32, min(390.0'f32, sw.float32 * 0.4'f32),
                      winTitle, colService, colOwner, services, flipTimes, local, alpha,
                      "tophat", "root", LoreAccent, RootRed)

    # The newest loss, at full size: the boss that service has become.
    let bx = sw.float32 * 0.72'f32
    let by = sh.float32 * 0.37'f32
    let rootA = alpha * clamp01((local - (IntroFlipStart + ServiceCount.float32 * IntroFlipEvery)) / 0.8'f32)
    if rootA > 0.0'f32:
      drawHalo(bx, by, 220.0'f32, colorA(Color(r: 180, g: 40, b: 255, a: 255), rootA * 55.0'f32), 1.0'f32)
      drawCinematicBoss(root, bx, by, 96.0'f32, 0.9'f32, 0)
    if flipped > 0:
      let i = flipped - 1
      let age = local - (IntroFlipStart + i.float32 * IntroFlipEvery)
      let pop = easeOut(clamp01(age / 0.22'f32))
      let fade = 1.0'f32 - rootA / max(alpha, 0.001'f32) * 0.85'f32
      drawHalo(bx, by, 130.0'f32, colorA(RootRed, alpha * fade * 40.0'f32), 1.0'f32)
      drawCinematicBoss(bosses[i], bx, by, 62.0'f32 * (0.7'f32 + pop * 0.3'f32), 1.0'f32, 0)
      drawCenteredText(services[i], bx.int32, (by + 96.0'f32).int32, 20,
                       Color(r: 255, g: 220, b: 225, a: alphaByte(alpha * fade * 255.0'f32)))
      drawCenteredText(t(tkLoreServicesHijacked), bx.int32, (by + 122.0'f32).int32, 14,
                       colorA(RootRed, alpha * fade * 230.0'f32))

    drawSubtitles([t(tkLoreHijack1), t(tkLoreHijack2)], sw, sh, alpha)

# ---------------------------------------------------------------------------
# REC 05: DEFENSE PROTOCOL. What the job looks like, then the title.

proc drawDefenseShot(local, duration: float32, sw, sh: int32, alpha: float32) =
  let titleT = clamp01((local - IntroTitleAt) / 0.35'f32)
  let game = alpha * (1.0'f32 - 0.7'f32 * titleT)
  let ppx = sw.float32 * 0.24'f32
  let ppy = sh.float32 * 0.44'f32 + sin(local * 1.7'f32) * 10.0'f32
  let player = newVector2f(ppx, ppy)

  const kinds = [etCircle, etTriangle, etCube, etStar, etDiamond, etCircle, etPentagon, etTriangle, etCross]
  for i in 0..<kinds.len:
    let born = i.float32 * 0.6'f32   # keeps the field busy until the title drops
    if local < born:
      continue
    let lane = sh.float32 * (0.24'f32 + hash01(i.float32 * 1.7'f32) * 0.36'f32)
    let dies = born + 1.4'f32 + hash01(i.float32 + 4.0'f32) * 0.6'f32
    let ex = sw.float32 + 30.0'f32 - (min(local, dies) - born) * 150.0'f32
    let ey = lane + sin(local * 2.0'f32 + i.float32) * 8.0'f32
    if local < dies:
      drawRealEnemy(kinds[i], ex, ey, 11.0'f32 + (i mod 3).float32 * 2.0'f32, local, 700 + i, 0,
                    newVector2f(-150.0'f32, 0.0'f32))
      # A stream of shots walks onto it.
      for b in 0..<2:
        let p = fractCoord(local * 2.2'f32 + b.float32 * 0.5'f32 + i.float32 * 0.31'f32)
        let bx = lerpF(ppx + 30.0'f32, ex, p)
        let by = lerpF(ppy, ey, p)
        let back = 0.06'f32
        drawStroke(Vector2(x: bx - (ex - ppx) * back, y: by - (ey - ppy) * back), Vector2(x: bx, y: by), 2.0'f32,
                   Color(r: 0, g: 255, b: 235, a: alphaByte(game * 150.0'f32)))
        drawEquippedBulletModel(newVector2f(bx, by), 7.0'f32, arctan2(ey - ppy, ex - ppx), local + b.float32, game)
    else:
      # Ended: a burst, and what it carried flies home.
      let since = local - dies
      if since < 0.5'f32:
        drawCircleOutline(Vector2(x: ex, y: ey), 8.0'f32 + since * 70.0'f32,
                          Color(r: 255, g: 200, b: 120, a: alphaByte(game * (1.0'f32 - since / 0.5'f32) * 220.0'f32)))
      for k in 0..<2:
        let p = easeInOut(clamp01((since - 0.15'f32 - k.float32 * 0.12'f32) / 0.65'f32))
        if p <= 0.0'f32 or p >= 1.0'f32:
          continue
        let arc = sin(p * PI) * (40.0'f32 + k.float32 * 20.0'f32)
        let qx = lerpF(ex, ppx, p)
        let qy = lerpF(ey, ppy, p) - arc
        if k == 0:
          drawCurrencyIcon(qx.int32, qy.int32, 14, ciCredits, alphaByte(game * 255.0'f32))
        else:
          drawDisc(Vector2(x: qx, y: qy), 4.0'f32, Color(r: 90, g: 255, b: 160, a: alphaByte(game * 230.0'f32)))

  drawHalo(ppx, ppy, 70.0'f32, colorA(LoreAccent, game * 36.0'f32), 1.0'f32)
  drawEquippedPlayerModel(player, 24.0'f32, local, game, 0.24'f32)

  # Level up: TOPHAT installs a patch, the way the real installer does.
  let toastIn = clamp01((local - 2.4'f32) / 0.25'f32)
  let toastOut = clamp01((IntroTitleAt - 0.1'f32 - local) / 0.3'f32)
  let toastA = game * min(toastIn, toastOut)
  if toastA > 0.0'f32:
    let pt = puMultiShot
    let name = getPowerUpName(pt)
    let label = t(tkLorePatchInstalled)
    let tw = max(measureText(label, 13), measureText(name, 16)) + 70
    let tx = (ppx - 30.0'f32).int32
    let ty = (ppy - 110.0'f32 - (1.0'f32 - toastIn) * 10.0'f32).int32
    drawRectangle(tx, ty, tw, 50, Color(r: 12, g: 22, b: 34, a: alphaByte(toastA * 235.0'f32)))
    drawRectOutline(tx, ty, tw, 50, colorA(LoreAccent, toastA * 230.0'f32))
    drawPowerUpIcon(tx + 8, ty + 9, 32, pt, colorA(powerUpDef(pt).color, toastA * 255.0'f32))
    drawText(label, tx + 50, ty + 8, 13, colorA(LoreAccent, toastA * 230.0'f32))
    drawText(name, tx + 50, ty + 25, 16, Color(r: 240, g: 250, b: 255, a: alphaByte(toastA * 255.0'f32)))

  # The title drops.
  if titleT > 0.0'f32:
    let since = local - IntroTitleAt
    let flash = exp(-since * 5.0'f32)
    drawRectangle(0, 0, sw, sh, Color(r: 220, g: 250, b: 250, a: alphaByte(alpha * flash * 120.0'f32)))
    let drop = (1.0'f32 - easeOut(clamp01(since / 0.3'f32))) * -22.0'f32
    let ty = (sh.float32 * 0.38'f32 + drop).int32
    let a = alpha * titleT
    let title = "TopHat-ShooterOS"
    let size = fitFontSize(title, sw - 80, 58)
    drawHalo(sw.float32 * 0.5'f32, ty.float32 + 30.0'f32, 210.0'f32, colorA(LoreAccent, a * 26.0'f32), 1.0'f32)
    drawTopHat(newVector2f(sw.float32 * 0.5'f32, ty.float32 - 30.0'f32 + 26.0'f32 * 0.74'f32), 26.0'f32, local, a)
    drawCenteredText(title, sw div 2 + 2, ty + 3, size, Color(r: 0, g: 0, b: 0, a: alphaByte(a * 160.0'f32)))
    drawCenteredText(title, sw div 2, ty, size, Color(r: 255, g: 255, b: 255, a: alphaByte(a * 255.0'f32)))
    let ruleW = (sw.float32 * 0.3'f32 * easeOut(clamp01(since / 0.5'f32))).int32
    drawRectangle(sw div 2 - ruleW, ty + size + 14, ruleW * 2, 2, colorA(LoreAccent, a * 180.0'f32))
    drawCenteredText(t(tkLoreTryNotToCrash), sw div 2, ty + size + 28, 22, colorA(LoreAccent, a * 230.0'f32))

  drawSubtitles([t(tkLoreDefense1), t(tkLoreDefense2)], sw, sh, alpha * (1.0'f32 - titleT))

# ---------------------------------------------------------------------------
# Per-shot shake overrides

proc floodShake(time, local, duration, alpha: float32): float32 =
  sin(time * 31.0'f32) * 1.6'f32 * alpha * clamp01((local - 1.2'f32) / 3.6'f32)

proc hijackShake(time, local, duration, alpha: float32): float32 =
  sin(time * 36.0'f32) * 2.2'f32 * alpha

proc titleShake(time, local, duration, alpha: float32): float32 =
  let kick = if local >= IntroTitleAt: exp(-(local - IntroTitleAt) * 5.0'f32) * 6.0'f32 else: 0.0'f32
  sin(time * 52.0'f32) * kick + sin(time * 0.7'f32) * 1.0'f32 * alpha

# ---------------------------------------------------------------------------
# Backdrop

proc loreBackdrop(time, _: float32, sw, sh: int32) =
  drawSharedBackdrop(sw, sh, time * 0.48'f32,
                     Color(r: 2, g: 4, b: 8, a: 255),
                     Color(r: 8, g: 12, b: 20, a: 255),
                     Color(r: 16, g: 34, b: 44, a: 30),
                     Color(r: 40, g: 110, b: 120, a: 46),
                     Color(r: 0, g: 210, b: 210, a: 34),
                     0.55, 0.5)

# ---------------------------------------------------------------------------
# Public factory

proc newLoreCutscene*(): Cutscene =
  newCutscene(
    shots = @[
      CutsceneShot(duration: IntroShots[0], drawProc: newCleanupShot(), soundCue: stMenuSelect,
                   muteCue: true, label: t(tkLoreRecCleanup), iconIndex: 4),
      CutsceneShot(duration: IntroShots[1], drawProc: newFloodShot(), soundCue: stExplosion,
                   muteCue: true, label: t(tkLoreRecFlood), iconIndex: 0,
                   glitchMod: 71, glitchWindow: 4, shakeProc: floodShake),
      CutsceneShot(duration: IntroShots[2], drawProc: drawWhoShot, soundCue: stBossSpawn,
                   muteCue: true, label: t(tkLoreRecWho), iconIndex: 3, glitchMod: 53, glitchWindow: 3),
      CutsceneShot(duration: IntroShots[3], drawProc: drawSpawnShot, soundCue: stPowerUp,
                   muteCue: true, label: t(tkLoreRecSpawn), iconIndex: 4),
      CutsceneShot(duration: IntroShots[4], drawProc: newHijackShot(), soundCue: stBossSpawn,
                   muteCue: true, label: t(tkLoreRecHijack), iconIndex: 7,
                   glitchMod: 63, glitchWindow: 5, shakeProc: hijackShake),
      CutsceneShot(duration: IntroShots[5], drawProc: drawDefenseShot, soundCue: stShoot,
                   muteCue: true, label: t(tkLoreRecDefense), iconIndex: 10, shakeProc: titleShake),
    ],
    accentColor       = LoreAccent,
    titleCardText     = "",   # cold open: the title drops at the end of REC 05
    titleCardSub      = "",
    drawBackdropProc  = loreBackdrop,
    swayAmp           = 1.0'f32,
    musicTrack        = mtStoryIntro,
    cornerTag         = t(tkLorePlayback),
    captionCps        = IntroCaptionCps,
  )

# Keep legacy proc names so main.nim doesn't need patching.
type LoreCinematic* = Cutscene

proc newLoreCinematic*(): LoreCinematic = newLoreCutscene()

proc updateLoreCinematic*(lore: LoreCinematic, dt: float32) =
  updateCutscene(lore, dt)

proc drawLoreCinematic*(lore: LoreCinematic, screenWidth, screenHeight: int) =
  drawCutscene(lore, screenWidth, screenHeight)
