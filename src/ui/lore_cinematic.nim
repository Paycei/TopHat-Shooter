## Lore Cinematic: opening narrative (REC 00 to REC 05).
## Every shot stages the beat its caption narrates: the breach tears a real OS
## window, the flood corrupts the real desktop icons, the contained kernel boots
## the player, and the Root pulls TOPHAT's services into itself (the eleven
## hijacked services the bosses are made from; see getBossServiceTag).
## newLoreCutscene() assembles the shots on the generic framework in cutscene.nim.

import raylib, rlgl, math
from std/unicode import runeLen, runeSubStr
import particle_types, background_fx, ../types, ../localization, ../sound, ../boss_definitions,
       cinematic_common, cutscene, os_desktop

const
  LoreAccent = Color(r: 0, g: 230, b: 230, a: 255)
  RootMagenta = Color(r: 255, g: 40, b: 190, a: 255)
  HijackRed = Color(r: 255, g: 60, b: 90, a: 255)
  ServiceCount = 11   # bosses 1-11 are hijacked services; boss 12 is the Root

# ---------------------------------------------------------------------------
# Shared staging helpers

proc lerpF(a, b, t: float32): float32 = a + (b - a) * t

proc hash01(n: float32): float32 =
  ## Deterministic 0..1 noise so the staging is identical on every playback.
  fractCoord(sin(n * 12.9898'f32) * 43758.5453'f32)

proc triAny(a, b, c: Vector2, col: Color) =
  ## Winding-safe triangle: raylib culls one winding, and rift geometry flips.
  let cross = (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
  if cross < 0.0'f32: drawTriangle(a, b, c, col)
  else: drawTriangle(a, c, b, col)

proc drawRift(x, top, bottom, open, time, alpha: float32) =
  ## The breach itself: a jagged vertical tear, widest in the middle, with a
  ## magenta edge and a white-hot core. The jaggies crawl so it reads as live.
  if open <= 0.01'f32:
    return
  const steps = 16
  var prevL, prevR, prevCL, prevCR: Vector2
  let edge = colorA(RootMagenta, alpha * 225.0'f32)
  let core = Color(r: 255, g: 228, b: 250, a: alphaByte(alpha * 245.0'f32))
  for i in 0..steps:
    let u = i.float32 / steps.float32
    let y = lerpF(top, bottom, u)
    let jag = sin(u * 31.0'f32 + time * 6.0'f32) * 5.0'f32 + sin(u * 13.0'f32 + 1.7'f32) * 8.0'f32
    let w = open * (3.0'f32 + 24.0'f32 * sin(u * PI))
    let mid = x + jag * (0.35'f32 + open * 0.65'f32)
    let l = Vector2(x: mid - w, y: y)
    let r = Vector2(x: mid + w, y: y)
    let cl = Vector2(x: mid - w * 0.32'f32, y: y)
    let cr = Vector2(x: mid + w * 0.32'f32, y: y)
    if i > 0:
      triAny(prevL, prevR, r, edge)
      triAny(prevL, r, l, edge)
      triAny(prevCL, prevCR, cr, core)
      triAny(prevCL, cr, cl, core)
    prevL = l; prevR = r; prevCL = cl; prevCR = cr
  drawSoftGlow(x, (top + bottom) * 0.5'f32, 50.0'f32 + open * 95.0'f32,
               colorA(RootMagenta, alpha * open * 55.0'f32), 1.0'f32)

proc drawOSWindowFrame(x, y, w, h: float32, title: string, alpha: float32) =
  ## A TopHat-ShooterOS window in the desktop's own chrome language.
  let xi = x.int32
  let yi = y.int32
  let wi = w.int32
  let hi = h.int32
  drawRectangle(xi + 7, yi + 9, wi, hi, Color(r: 0, g: 0, b: 0, a: alphaByte(alpha * 110.0'f32)))
  drawRectangle(xi, yi, wi, hi, Color(r: 8, g: 14, b: 22, a: alphaByte(alpha * 238.0'f32)))
  drawRectangleGradientH(xi, yi, wi, 26, colorA(LoreAccent, alpha * 110.0'f32),
                         Color(r: 10, g: 28, b: 38, a: alphaByte(alpha * 225.0'f32)))
  drawText(title, xi + 10, yi + 6, 14, Color(r: 230, g: 250, b: 255, a: alphaByte(alpha * 235.0'f32)))
  for k in 0..2:
    let bx = xi + wi - 22 - k.int32 * 22
    drawRectangleLines(bx, yi + 6, 14, 14, colorA(LoreAccent, alpha * 170.0'f32))
    if k == 0:
      drawLine(bx + 3, yi + 9, bx + 11, yi + 17, colorA(LoreAccent, alpha * 200.0'f32))
      drawLine(bx + 11, yi + 9, bx + 3, yi + 17, colorA(LoreAccent, alpha * 200.0'f32))
  drawRectangleLines(xi, yi, wi, hi, colorA(LoreAccent, alpha * 200.0'f32))

proc drawContainment(pos: Vector2f, r, time, alpha: float32, strain: float32 = 0.0'f32) =
  ## The kernel's containment cage: two counter-turning hex rings and bars.
  ## `strain` tints it magenta where the Root is pressing on it.
  let cage = Color(r: uint8(lerpF(0, 255, strain)), g: uint8(lerpF(190, 60, strain)),
                   b: uint8(lerpF(210, 190, strain)), a: 255)
  let c = Vector2(x: pos.x, y: pos.y)
  drawPolyLines(c, 6, r, time * 9.0'f32, colorA(cage, alpha * 170.0'f32))
  drawPolyLines(c, 6, r + 6.0'f32, -time * 6.0'f32, colorA(cage, alpha * 110.0'f32))
  for i in 0..<6:
    let a = degToRad(time * 9.0'f32) + i.float32 * PI / 3.0'f32
    drawLine(Vector2(x: pos.x + cos(a) * r * 0.62'f32, y: pos.y + sin(a) * r * 0.62'f32),
             Vector2(x: pos.x + cos(a) * r, y: pos.y + sin(a) * r), 2.0'f32,
             colorA(cage, alpha * 120.0'f32))

proc drawTendril(a, b: Vector2, reach, time, seed, alpha: float32, col: Color) =
  ## A wavering line from `a` toward `b`, drawn out to `reach` (0..1).
  if reach <= 0.0'f32:
    return
  const segs = 18
  var prev = a
  for i in 1..segs:
    let u = i.float32 / segs.float32 * reach
    let wob = sin(u * 9.0'f32 + time * 5.0'f32 + seed) * 14.0'f32 * sin(u * PI)
    let dx = b.x - a.x
    let dy = b.y - a.y
    let len = max(1.0'f32, sqrt(dx * dx + dy * dy))
    let p = Vector2(x: a.x + dx * u - dy / len * wob, y: a.y + dy * u + dx / len * wob)
    drawLine(prev, p, 2.0'f32, colorA(col, alpha * (1.0'f32 - u * 0.4'f32)))
    prev = p

# ---------------------------------------------------------------------------
# REC 00: SYSTEM BREACH. The gate of TopHat-ShooterOS is forced open.

proc drawBreachShot(local, duration: float32, screenWidth, screenHeight: int32,
                    alpha: float32) =
  let t01 = local / duration
  let cx = screenWidth.float32 * 0.5'f32
  let cy = screenHeight.float32 * 0.44'f32
  drawDataRain(screenWidth, screenHeight, local, alpha * 0.55'f32)

  let winW = 470.0'f32
  let winH = 290.0'f32
  let force = easeOut(clamp01((t01 - 0.28'f32) / 0.42'f32))  # the gate giving way
  let impact = if t01 > 0.28'f32: sin(local * 47.0'f32) * 3.0'f32 * (1.0'f32 - force * 0.6'f32) else: 0.0'f32
  let wx = cx - winW * 0.5'f32 + impact
  let wy = cy - winH * 0.5'f32
  drawOSWindowFrame(wx, wy, winW, winH, "TopHat-ShooterOS", alpha)

  # The kernel, held in containment inside the window.
  let kpos = newVector2f(wx + winW * 0.34'f32, wy + 26.0'f32 + (winH - 26.0'f32) * 0.56'f32)
  let reach = easeInOut(clamp01((t01 - 0.6'f32) / 0.3'f32))
  drawContainment(kpos, 58.0'f32, local, alpha, reach)
  let jit = force * 1.8'f32
  drawKernelModel(newVector2f(kpos.x + sin(local * 43.0'f32) * jit, kpos.y + cos(local * 51.0'f32) * jit),
                  26.0'f32, local, 1.0'f32, alpha)
  drawCenteredText(t(tkLoreContainment), kpos.x.int32, (kpos.y + 74.0'f32).int32, 12,
                   colorA(LoreAccent, alpha * 150.0'f32))

  # The gate forced: a tear through the window that runs past its frame.
  let riftX = wx + winW * 0.76'f32
  drawRift(riftX, wy - 40.0'f32, wy + winH + 40.0'f32, force, local, alpha)
  # Fracture lines racing across the window from the tear.
  for k in 0..<6:
    let ang = PI + (hash01(k.float32 + 3.0'f32) - 0.5'f32) * 1.9'f32
    let len = force * (60.0'f32 + hash01(k.float32 + 9.0'f32) * 120.0'f32)
    let sy = wy + 50.0'f32 + hash01(k.float32 + 17.0'f32) * (winH - 70.0'f32)
    drawLine(Vector2(x: riftX, y: sy), Vector2(x: riftX + cos(ang) * len, y: sy + sin(ang) * len),
             1.5'f32, colorA(RootMagenta, alpha * force * 140.0'f32))
  # Shock rings off the tear.
  for i in 0..<5:
    let r = fractCoord(local * 0.45'f32 + i.float32 * 0.2'f32) * 300.0'f32 * force
    drawCircleLines(Vector2(x: riftX, y: cy), r,
                    colorA(RootMagenta, alpha * force * (1.0'f32 - r / 300.0'f32) * 120.0'f32))

  # The warning, drawn over the tear so it stays legible: an unknown host
  # knocking at the gate.
  if t01 > 0.1'f32:
    let blink = if sin(local * 11.0'f32) > -0.3'f32: 1.0'f32 else: 0.35'f32
    let stripY = (wy + 34.0'f32).int32
    drawRectangle((wx + 8.0'f32).int32, stripY, (winW - 16.0'f32).int32, 22,
                  Color(r: 120, g: 10, b: 40, a: alphaByte(alpha * blink * 215.0'f32)))
    drawCenteredText(t(tkLoreBreachAlert), (wx + winW * 0.5'f32).int32, stripY + 5, 12,
                     Color(r: 255, g: 200, b: 215, a: alphaByte(alpha * blink * 240.0'f32)))

  # Something came through: tendrils reach from the tear for the containment.
  for k in 0..<4:
    let from0 = Vector2(x: riftX, y: cy - 60.0'f32 + k.float32 * 40.0'f32)
    let to0 = Vector2(x: kpos.x + 62.0'f32, y: kpos.y - 30.0'f32 + k.float32 * 20.0'f32)
    drawTendril(from0, to0, reach, local, k.float32 * 1.7'f32, alpha * 210.0'f32, RootMagenta)

  drawSubtitles([t(tkLoreBreach1), t(tkLoreBreach2)], screenWidth, screenHeight, alpha)

# ---------------------------------------------------------------------------
# REC 01: HOSTILE PROCESS FLOOD. The corruption pours through the tear and
# rots the desktop icons it reaches.

const GlitchGlyphs = "#%@&$*01?!"

proc scrambleLabel(name: string, corruption, time: float32, seed: int): string =
  ## Letters flip to glitch glyphs as corruption rises; ASCII only.
  result = name
  for j in 0..<result.len:
    if result[j] in {'A'..'Z', 'a'..'z', '0'..'9'} and
       hash01(j.float32 * 3.1'f32 + seed.float32 * 7.7'f32) < corruption:
      let g = int(hash01(j.float32 + floor(time * 14.0'f32) + seed.float32) * GlitchGlyphs.len.float32)
      result[j] = GlitchGlyphs[clamp(g, 0, GlitchGlyphs.high)]

proc newFloodShot(): CutsceneDrawProc =
  ## Built per cutscene so the icon names are resolved in the current language.
  var icons: seq[DesktopIcon]
  for icon in newOSDesktop().icons:
    if icon.iconType != diCredits and icons.len < 12:
      icons.add(icon)

  result = proc(local, duration: float32, screenWidth, screenHeight: int32, alpha: float32) =
    let cx = screenWidth.float32 * 0.5'f32
    let riftTop = screenHeight.float32 * 0.15'f32
    let riftBottom = screenHeight.float32 * 0.72'f32
    let t01 = local / duration

    # The desktop: six icons each side of the tear, two rows.
    let rowY = [screenHeight.float32 * 0.2'f32, screenHeight.float32 * 0.43'f32]
    let front = easeInOut(clamp01(t01 * 1.12'f32)) * (cx - 60.0'f32)
    for i, base in icons:
      let side = if i < 6: -1.0'f32 else: 1.0'f32
      let col = (i mod 6) div 2
      let row = (i mod 6) mod 2
      let ix = cx + side * (150.0'f32 + col.float32 * 112.0'f32) - (if side < 0: ICON_SIZE.float32 else: 0.0'f32)
      let iy = rowY[row]
      let dist = abs(ix + ICON_SIZE.float32 * 0.5'f32 - cx)
      let c = clamp01((front - dist + 90.0'f32) / 110.0'f32)
      var icon = base
      icon.x = int(ix + sin(local * 41.0'f32 + i.float32) * 3.0'f32 * c)
      icon.y = int(iy + cos(local * 37.0'f32 + i.float32) * 2.0'f32 * c)
      icon.name = scrambleLabel(base.name, c, local, i)
      if c > 0.5'f32:
        icon.iconColor = HijackRed
      drawDesktopIcon(icon, local, false)
      if c > 0.0'f32:
        let x0 = icon.x.int32
        let y0 = icon.y.int32
        drawRectangle(x0, y0, ICON_SIZE, ICON_SIZE, colorA(RootMagenta, alpha * c * 70.0'f32))
        for k in 0..<3:
          let bandY = y0 + int32(hash01(k.float32 + floor(local * 9.0'f32) + i.float32) * (ICON_SIZE - 4).float32)
          let off = int32((hash01(k.float32 * 5.0'f32 + local) - 0.5'f32) * 14.0'f32 * c)
          drawRectangle(x0 + off, bandY, ICON_SIZE, 3,
                        if k mod 2 == 0: colorA(RootMagenta, alpha * c * 170.0'f32)
                        else: Color(r: 0, g: 255, b: 255, a: alphaByte(alpha * c * 120.0'f32)))
        drawRectangleLines(x0 - 2, y0 - 2, ICON_SIZE + 4, ICON_SIZE + 4, colorA(HijackRed, alpha * c * 200.0'f32))

    # The tear the flood pours from.
    drawRift(cx, riftTop, riftBottom, 1.0'f32, local, alpha)

    # Hostile processes spilling out of the tear and spreading across the desktop.
    let kinds = [etCircle, etCube, etTriangle, etStar, etCross, etDiamond, etOctagon, etPentagon, etHexagon]
    for i in 0..<34:
      let delay = i.float32 * 0.13'f32
      let p = easeOut(clamp01((local - delay) / 2.4'f32))
      if p <= 0.0'f32:
        continue
      let side = if i mod 2 == 0: -1.0'f32 else: 1.0'f32
      let ang = (if side < 0: PI else: 0.0'f32) + (hash01(i.float32 + 1.3'f32) - 0.5'f32) * 1.5'f32
      let dist = p * (140.0'f32 + hash01(i.float32 + 4.1'f32) * 300.0'f32)
      let sy = lerpF(riftTop + 40.0'f32, riftBottom - 30.0'f32, hash01(i.float32 + 8.9'f32))
      let ex = cx + cos(ang) * dist
      let ey = sy + sin(ang) * dist * 0.55'f32
      let sz = 8.0'f32 + (i mod 4).float32 * 2.0'f32
      drawRealEnemy(kinds[i mod kinds.len], ex, ey, sz * (0.4'f32 + p * 0.6'f32), local, i,
                    if i mod 8 == 0: 2 else: 0, newVector2f(cos(ang) * 90.0'f32, sin(ang) * 50.0'f32))

    let edge = (screenWidth.float32 * t01 * 0.3'f32).int32
    drawRectangleGradientH(0, 0, edge, screenHeight, colorA(HijackRed, alpha * 55.0'f32), colorA(HijackRed, 0.0'f32))
    drawRectangleGradientH(screenWidth - edge, 0, edge, screenHeight, colorA(HijackRed, 0.0'f32),
                           colorA(HijackRed, alpha * 55.0'f32))
    drawSubtitles([t(tkLoreSwarm1), t(tkLoreSwarm2)], screenWidth, screenHeight, alpha)

# ---------------------------------------------------------------------------
# REC 02: TOPHAT KERNEL WAKE. The contained kernel cannot fight, so it boots
# its last trusted process down a beam: the player.

proc drawAwakenShot(local, duration: float32, screenWidth, screenHeight: int32,
                    alpha: float32) =
  let t01 = local / duration
  let cx = screenWidth.float32 * 0.5'f32
  let ky = screenHeight.float32 * 0.25'f32
  let py = screenHeight.float32 * 0.58'f32

  # The kernel, still locked in its cage.
  let kpos = newVector2f(cx, ky)
  drawSoftGlow(cx, ky, 90.0'f32, colorA(LoreAccent, alpha * 30.0'f32), 1.0'f32)
  drawContainment(kpos, 54.0'f32, local, alpha)
  drawKernelModel(kpos, 26.0'f32, local, 1.0'f32, alpha)

  # The boot beam: the kernel reaching past its own containment.
  let beam = easeInOut(clamp01((t01 - 0.12'f32) / 0.24'f32))
  let beamTop = ky + 62.0'f32
  let beamBottom = lerpF(beamTop, py, beam)
  if beam > 0.0'f32:
    let bh = (beamBottom - beamTop).int32
    drawRectangleGradientV((cx - 7.0'f32).int32, beamTop.int32, 14, bh,
                           colorA(LoreAccent, alpha * 190.0'f32), colorA(LoreAccent, alpha * 70.0'f32))
    drawRectangle((cx - 1.5'f32).int32, beamTop.int32, 3, bh,
                  Color(r: 230, g: 255, b: 255, a: alphaByte(alpha * 230.0'f32)))
    for k in 0..<9:
      let p = fractCoord(local * 1.4'f32 + k.float32 / 9.0'f32)
      let yy = lerpF(beamTop, beamBottom, p)
      drawRectangle((cx - 4.0'f32).int32, yy.int32, 8, 6, colorA(LoreAccent, alpha * 220.0'f32 * (1.0'f32 - p * 0.5'f32)))

  # The process boots where the beam lands.
  let boot = easeOut(clamp01((t01 - 0.36'f32) / 0.3'f32))
  if beam >= 1.0'f32:
    let ring = clamp01((t01 - 0.36'f32) / 0.25'f32)
    drawCircleLines(Vector2(x: cx, y: py), 18.0'f32 + ring * 90.0'f32,
                    colorA(LoreAccent, alpha * (1.0'f32 - ring) * 220.0'f32))
  if boot > 0.0'f32:
    drawSoftGlow(cx, py, 105.0'f32 * boot, Color(r: 0, g: 220, b: 255, a: alphaByte(alpha * 40.0'f32)), 1.0'f32)
    for i in 0..<9:
      let a = local * 0.8'f32 + i.float32 * PI * 2.0'f32 / 9.0'f32
      let r = (80.0'f32 + sin(local * 3.0'f32 + i.float32) * 10.0'f32) * boot
      let dx = cx + cos(a) * r
      let dy = py + sin(a) * r * 0.62'f32
      drawCircle(Vector2(x: dx, y: dy), 3.0'f32 + boot * 2.0'f32,
                 Color(r: 0, g: 255, b: 220, a: alphaByte(alpha * boot * 150.0'f32)))
    drawEquippedPlayerModel(newVector2f(cx, py), 30.0'f32 * (0.3'f32 + boot * 0.7'f32),
                            local, alpha * boot, 0.22'f32)

  # The kernel's boot log, typed beside the new process.
  let logX = (cx + 90.0'f32).int32
  let logY = (py - 44.0'f32).int32
  let lines = [(t(tkLoreBoot1), 0.08'f32, Color(r: 120, g: 180, b: 190, a: 255)),
               (t(tkLoreBoot2), 0.2'f32, LoreAccent),
               (t(tkLoreBoot3), 0.5'f32, Color(r: 120, g: 255, b: 190, a: 255))]
  var shownAny = false
  for i, (text, at, col) in lines:
    let n = int((t01 - at) * duration * 44.0'f32)
    if n <= 0:
      continue
    shownAny = true
    let shown = text.runeSubStr(0, min(n, text.runeLen))
    drawText(shown, logX + 10, logY + 8 + i.int32 * 20, 14, colorA(col, alpha * 230.0'f32))
  if shownAny:
    drawRectangleLines(logX, logY, 360, 70, colorA(LoreAccent, alpha * 90.0'f32))

  drawSubtitles([t(tkLoreAwaken1), t(tkLoreAwaken2)], screenWidth, screenHeight, alpha)

# ---------------------------------------------------------------------------
# REC 03: THE ROOT. It takes form and pulls TOPHAT's services into itself, one
# by one. These are the eleven hijacked services the bosses are made from.

proc newRootShot(): CutsceneDrawProc =
  var services: seq[string]
  for id in 1..ServiceCount:
    services.add(getBossProcessName(id))

  result = proc(local, duration: float32, screenWidth, screenHeight: int32, alpha: float32) =
    let reveal = easeOut(local / (duration * 0.72'f32))
    let cx = screenWidth.float32 * 0.5'f32
    let cy = screenHeight.float32 * 0.45'f32
    drawSoftGlow(cx, cy, 280.0'f32 * reveal, Color(r: 180, g: 0, b: 255, a: alphaByte(alpha * 65.0'f32)), 1.0'f32)
    for ring in 0..<4:
      let r = 70.0'f32 + ring.float32 * 38.0'f32 + sin(local * 2.2'f32 + ring.float32) * 7.0'f32
      drawCircleLines(Vector2(x: cx, y: cy), r * reveal,
                      Color(r: 230, g: 80, b: 255, a: alphaByte(alpha * (120.0'f32 - ring.float32 * 20.0'f32))))

    let bossR = 84.0'f32 * reveal
    drawRealBossModel(cx, cy, bossR, local, screenWidth, screenHeight,
                      0.16'f32 + sin(local * 0.8'f32) * 0.03'f32)

    # The services, healthy cyan on a wide orbit, are seized one at a time:
    # a tendril reaches out, the name bleeds red, and it is dragged inward.
    var hijacked = 0
    for i, name in services:
      let startAt = 1.1'f32 + i.float32 * 0.34'f32
      let h = clamp01((local - startAt) / 0.55'f32)
      if h >= 0.5'f32:
        inc hijacked
      let pull = easeInOut(h)
      let ang = i.float32 * PI * 2.0'f32 / ServiceCount.float32 + local * 0.1'f32 - PI * 0.5'f32
      let rx = lerpF(335.0'f32, 255.0'f32, pull)
      let ry = lerpF(200.0'f32, 158.0'f32, pull)
      let px = cx + cos(ang) * rx
      let py = cy + sin(ang) * ry
      let col = Color(r: uint8(lerpF(140, 255, h)), g: uint8(lerpF(230, 60, h)),
                      b: uint8(lerpF(240, 90, h)), a: 255)
      if h > 0.0'f32:
        let edgePt = Vector2(x: cx + cos(ang) * bossR, y: cy + sin(ang) * bossR * 0.9'f32)
        drawTendril(edgePt, Vector2(x: px, y: py), min(1.0'f32, h * 1.6'f32), local, i.float32,
                    alpha * (if h < 1.0'f32: 210.0'f32 else: 70.0'f32), RootMagenta)
      let snap = clamp01((local - startAt - 0.3'f32) / 0.4'f32)
      if snap > 0.0'f32 and snap < 1.0'f32:
        drawCircleLines(Vector2(x: px, y: py), 10.0'f32 + snap * 34.0'f32,
                        colorA(HijackRed, alpha * (1.0'f32 - snap) * 200.0'f32))
      drawCircle(Vector2(x: px, y: py - 13.0'f32), 3.0'f32, colorA(col, alpha * reveal * 230.0'f32))
      drawCenteredText(name, px.int32 + 1, (py - 5.0'f32).int32, 14,
                       Color(r: 0, g: 0, b: 0, a: alphaByte(alpha * reveal * 200.0'f32)))
      drawCenteredText(name, px.int32, (py - 6.0'f32).int32, 14, colorA(col, alpha * reveal * 245.0'f32))

    let counter = t(tkLoreServicesHijacked) & ": " & $hijacked & "/" & $ServiceCount
    let counterA = alpha * clamp01((local - 0.9'f32) / 0.4'f32)
    drawCenteredText(counter, screenWidth div 2, (screenHeight div 9 + 14).int32, 16,
                     colorA(HijackRed, counterA * 230.0'f32))

    drawSubtitles([t(tkLoreBoss1), t(tkLoreBoss2)], screenWidth, screenHeight, alpha)

proc drawCounterShot(local, duration: float32, screenWidth, screenHeight: int32,
                     alpha: float32) =
  let x = screenWidth.float32 * 0.22'f32
  let y = screenHeight.float32 * 0.52'f32 + sin(local * 2.0'f32) * 12.0'f32
  drawEquippedPlayerModel(newVector2f(x, y), 24.0'f32, local, alpha, 0.2'f32)

  let muzzleX = x + 66.0'f32
  for i in 0..<16:
    let delay = i.float32 * 0.12'f32
    let p = fractCoord(local * 0.92'f32 - delay)
    let bx = muzzleX + p * screenWidth.float32 * 0.88'f32
    let by = y + sin(i.float32 * 1.9'f32) * 92.0'f32 + sin(local * 5.0'f32 + i.float32) * 8.0'f32
    let a = alpha * (1.0'f32 - p) * 220.0'f32
    drawLine((bx - 46.0'f32).int32, by.int32, bx.int32, by.int32,
             Color(r: 0, g: 255, b: 235, a: alphaByte(a * 0.45'f32)))
    drawEquippedBulletModel(newVector2f(bx, by), 8.0'f32, 0.0'f32, local + i.float32, alpha * (1.0'f32 - p))
  for i in 0..<18:
    let p = clamp01((local - i.float32 * 0.16'f32) / duration)
    let ex = screenWidth.float32 * (0.57'f32 + fractCoord(i.float32 * 0.37'f32) * 0.36'f32)
    let ey = screenHeight.float32 * (0.2'f32 + fractCoord(i.float32 * 0.51'f32) * 0.52'f32)
    let r = 9.0'f32 + sin((p + local) * 9.0'f32) * 5.0'f32 + p * 38.0'f32
    drawCircleLines(Vector2(x: ex, y: ey), r, Color(r: 255, g: 160, b: 45, a: alphaByte(alpha * (1.0'f32 - p) * 170.0'f32)))

  drawSubtitles([t(tkLoreCounter1), t(tkLoreCounter2)], screenWidth, screenHeight, alpha)

proc drawDirectiveShot(local, duration: float32, screenWidth, screenHeight: int32,
                       alpha: float32) =
  let cx = screenWidth.float32 * 0.5'f32
  let cy = screenHeight.float32 * 0.44'f32
  let pulse = sin(local * 4.0'f32) * 0.5'f32 + 0.5'f32
  drawSoftGlow(cx, cy, 300.0'f32, Color(r: 0, g: 255, b: 220, a: alphaByte(alpha * (46.0'f32 + pulse * 30.0'f32))), 1.0'f32)
  drawEquippedPlayerModel(newVector2f(cx, cy), 27.0'f32 * (1.0'f32 + pulse * 0.04'f32),
                          local, alpha, 0.28'f32)

  let titleAlpha = alpha * easeInOut(local / 0.85'f32)
  drawCenteredText(t(tkLoreDirectiveTitle), screenWidth div 2, (screenHeight * 2 div 3).int32,
                   32, Color(r: 255, g: 255, b: 255, a: alphaByte(titleAlpha * 255.0'f32)))
  drawCenteredText(t(tkLoreDirectiveSub), screenWidth div 2, (screenHeight * 2 div 3 + 46).int32,
                   21, Color(r: 0, g: 230, b: 230, a: alphaByte(titleAlpha * 210.0'f32)))

# ---------------------------------------------------------------------------
# Per-shot shake overrides

proc bossShake(time, local, duration, alpha: float32): float32 =
  sin(time * 36.0'f32) * 3.0'f32 * alpha

proc breachLateShake(time, local, duration, alpha: float32): float32 =
  if local > duration * 0.58'f32:
    sin(time * 44.0'f32) * 2.0'f32 * alpha
  else:
    sin(time * 0.7'f32) * 1.2'f32 * alpha

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
      CutsceneShot(duration: 5.60'f32, drawProc: drawBreachShot,   soundCue: stTeleport,
                   label: t(tkLoreRecBreach),   iconIndex: 3,  shakeProc: breachLateShake),
      CutsceneShot(duration: 5.95'f32, drawProc: newFloodShot(),   soundCue: stExplosion,
                   label: t(tkLoreRecSwarm),    iconIndex: 0),
      CutsceneShot(duration: 5.75'f32, drawProc: drawAwakenShot,   soundCue: stPowerUp,
                   label: t(tkLoreRecAwaken),   iconIndex: 4),
      CutsceneShot(duration: 6.45'f32, drawProc: newRootShot(),    soundCue: stBossSpawn,
                   label: t(tkLoreRecBoss),     iconIndex: 7,
                   glitchMod: 63, glitchWindow: 5, shakeProc: bossShake),
      CutsceneShot(duration: 5.65'f32, drawProc: drawCounterShot,  soundCue: stShoot,
                   label: t(tkLoreRecCounter),  iconIndex: 0),
      CutsceneShot(duration: 4.80'f32, drawProc: drawDirectiveShot, soundCue: stShield,
                   label: t(tkLoreRecDirective), iconIndex: 10),
    ],
    accentColor       = LoreAccent,
    titleCardText     = "TopHat-ShooterOS",
    titleCardSub      = t(tkLoreTitleCardSub),
    drawBackdropProc  = loreBackdrop,
    swayAmp           = 1.2'f32,
    musicTrack        = mtBoss,
    cornerTag         = t(tkLorePlayback),
  )

# Keep legacy proc names so main.nim doesn't need patching until Stage 2 migration.
type LoreCinematic* = Cutscene

proc newLoreCinematic*(): LoreCinematic = newLoreCutscene()

proc updateLoreCinematic*(lore: LoreCinematic, dt: float32) =
  updateCutscene(lore, dt)

proc drawLoreCinematic*(lore: LoreCinematic, screenWidth, screenHeight: int) =
  drawCutscene(lore, screenWidth, screenHeight)
