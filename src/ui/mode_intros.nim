## Mode-intro cutscenes, one per GameMode.
## Each plays once the first time a player enters that mode; the flag is set in
## main.nim before activating gsCutscene.  All factories return a Cutscene built
## on the generic framework in cutscene.nim; shot content uses the same
## cinematic_common helpers as the lore and endgame cinematics.

import raylib, rlgl, math, strutils
from std/unicode import runeLen, runeSubStr
import particle_types, background_fx, ../types, ../localization, ../sound, ../boss_definitions,
       ../enemy_config, cinematic_common, cutscene, ../utils
from ../dungeon import themeName, themeAccent

# ---------------------------------------------------------------------------
# Shared accent colours

const
  WaveAccent    = Color(r: 0,   g: 230, b: 230, a: 255)  # cyan (matches lore)
  SurvAccent    = Color(r: 255, g: 160, b: 30,  a: 255)  # orange
  RogueAccent   = Color(r: 160, g: 80,  b: 255, a: 255)  # purple
  SandboxAccent = Color(r: 180, g: 180, b: 180, a: 255)  # gray
  PvPAccent     = Color(r: 230, g: 60,  b: 60,  a: 255)  # red

# ---------------------------------------------------------------------------
# Shared simple backdrop (dark field, accent sweep)

proc simpleBackdrop(accent: Color): CutsceneBackdropProc =
  proc(time, _: float32, sw, sh: int32) =
    drawSharedBackdrop(sw, sh, time * 0.38'f32,
                       Color(r: 2,  g: 4,  b: 8,  a: 255),
                       Color(r: 8,  g: 10, b: 16, a: 255),
                       Color(r: 14, g: 22, b: 28, a: 28),
                       Color(r: 30, g: 80, b: 90, a: 38),
                       withAlpha(accent, 30),
                       0.48, 0.42)

# ---------------------------------------------------------------------------
# Wave-Based intro shots

proc newWaveRosterShot(): CutsceneDrawProc =
  ## RADAR SWEEP as a threat roster: one sweep finds the eleven hijacked services
  ## the bosses are made from, and tags each blip with its process name.
  ## Built per cutscene so the names follow the current language.
  var services: seq[string]
  for id in 1..11:
    services.add(getBossProcessName(id))
  const blipDist = [0.46'f32, 0.82, 0.6, 0.9, 0.5, 0.76, 0.62, 0.9, 0.48, 0.8, 0.66]
  const sweepSpeed = 1.85'f32

  result = proc(local, duration: float32, sw, sh: int32, alpha: float32) =
    let cx = sw.float32 * 0.5'f32
    let cy = sh.float32 * 0.47'f32
    let radarR = 172.0'f32
    let open = easeOut(local / (duration * 0.3'f32))

    drawSoftGlow(cx, cy, 130.0'f32 * open, colorA(WaveAccent, alpha * 40.0'f32), 1.0'f32)
    for i in 1..4:
      drawCircleLines(Vector2(x: cx, y: cy), radarR * i.float32 / 4.0'f32 * open,
                      colorA(WaveAccent, alpha * (110.0'f32 - i.float32 * 14.0'f32)))
    drawLine((cx - radarR * open).int32, cy.int32, (cx + radarR * open).int32, cy.int32,
             colorA(WaveAccent, alpha * 45.0'f32))
    drawLine(cx.int32, (cy - radarR * open).int32, cx.int32, (cy + radarR * open).int32,
             colorA(WaveAccent, alpha * 45.0'f32))

    # The sweep starts at twelve o'clock and fades a trail behind it.
    let swept = local * sweepSpeed
    let sweepA = -PI * 0.5'f32 + swept
    for k in 0..<14:
      let a = sweepA - k.float32 * 0.035'f32
      drawLine(Vector2(x: cx, y: cy), Vector2(x: cx + cos(a) * radarR * open, y: cy + sin(a) * radarR * open),
               2.0'f32, colorA(WaveAccent, alpha * (150.0'f32 - k.float32 * 10.0'f32)))

    # Each service is found as the sweep crosses it: ping, blip, and its name.
    var found = 0
    for i, name in services:
      let rel = (i.float32 + 0.5'f32) / services.len.float32 * PI * 2.0'f32 * 0.94'f32
      if swept < rel:
        continue
      inc found
      let ang = -PI * 0.5'f32 + rel
      let bx = cx + cos(ang) * radarR * blipDist[i] * open
      let by = cy + sin(ang) * radarR * blipDist[i] * open
      let age = (swept - rel) / sweepSpeed
      if age < 0.6'f32:
        drawCircleLines(Vector2(x: bx, y: by), 6.0'f32 + age * 40.0'f32,
                        Color(r: 255, g: 70, b: 70, a: alphaByte(alpha * (1.0'f32 - age / 0.6'f32) * 220.0'f32)))
      let pulse = 0.6'f32 + 0.4'f32 * sin(local * 6.0'f32 + i.float32)
      drawCircle(Vector2(x: bx, y: by), 3.5'f32 + pulse * 2.0'f32,
                 Color(r: 255, g: 60, b: 60, a: alphaByte(alpha * 235.0'f32)))
      let w = measureText(name, 12)
      let lx = if cos(ang) >= 0.0'f32: bx.int32 + 10 else: bx.int32 - 10 - w
      let labelA = alpha * clamp01(age / 0.25'f32)
      drawText(name, lx + 1, by.int32 - 5, 12, Color(r: 0, g: 0, b: 0, a: alphaByte(labelA * 200.0'f32)))
      drawText(name, lx, by.int32 - 6, 12, Color(r: 255, g: 120, b: 120, a: alphaByte(labelA * 240.0'f32)))

    let header = t(tkModeIntroWaveRoster) & ": " & $found & "/" & $services.len
    drawCenteredText(header, sw div 2, (cy - radarR - 38.0'f32).int32, 16,
                     Color(r: 255, g: 110, b: 110, a: alphaByte(alpha * open * 230.0'f32)))

    drawSubtitles([t(tkModeIntroWave1a), t(tkModeIntroWave1b)], sw, sh, alpha)

proc drawWaveShot2(local, duration: float32, sw, sh: int32, alpha: float32) =
  let cx = sw.float32 * 0.5'f32
  let cy = sh.float32 * 0.48'f32
  let enter = easeInOut(local / (duration * 0.5'f32))

  # Player model drifting forward from the left.
  let px = sw.float32 * (0.15'f32 + enter * 0.2'f32)
  let py = cy + sin(local * 1.6'f32) * 14.0'f32
  drawEquippedPlayerModel(newVector2f(px, py), 26.0'f32, local, alpha, 0.2'f32)

  # Enemy swarm approaching from the right.
  for i in 0..<12:
    let seed = i.float32 * 0.77'f32
    let ex = sw.float32 * (0.95'f32 - enter * 0.22'f32) - seed * 18.0'f32
    let ey = sh.float32 * (0.28'f32 + fractCoord(seed * 2.3'f32) * 0.46'f32)
    let kind = case i mod 4
      of 0: etCircle
      of 1: etTriangle
      of 2: etStar
      else: etCube
    drawRealEnemy(kind, ex, ey, 10.0'f32 + (i mod 3).float32 * 3.0'f32, local, i, 0,
                  newVector2f(-60.0'f32, 0.0'f32))

  drawSoftGlow(cx, cy, 180.0'f32, colorA(WaveAccent, alpha * 30.0'f32), 1.0'f32)
  drawSubtitles([t(tkModeIntroWave2a), t(tkModeIntroWave2b)], sw, sh, alpha)

proc newWaveIntroCutscene*(): Cutscene =
  newCutscene(
    shots = @[
      CutsceneShot(duration: 5.0'f32, drawProc: newWaveRosterShot(), soundCue: stTeleport,
                   label: t(tkModeIntroWaveRec1), iconIndex: 3),
      CutsceneShot(duration: 5.0'f32, drawProc: drawWaveShot2, soundCue: stShoot,
                   label: t(tkModeIntroWaveRec2), iconIndex: 0),
    ],
    accentColor      = WaveAccent,
    titleCardText    = "TopHat-ShooterOS",
    titleCardSub     = t(tkModeIntroWaveTitle),
    drawBackdropProc = simpleBackdrop(WaveAccent),
    swayAmp          = 0.8'f32,
    musicTrack       = mtBoss,
  )

# ---------------------------------------------------------------------------
# Time Survival intro shots

proc formatUptime(totalSeconds: int): string =
  ## hh:mm:ss, the survival HUD's own clock format.
  let s = max(0, totalSeconds)
  intToStr(s div 3600, 2) & ":" & intToStr((s div 60) mod 60, 2) & ":" & intToStr(s mod 60, 2)

proc drawSurvShot1(local, duration: float32, sw, sh: int32, alpha: float32) =
  ## WATCH START: the uptime dial the survival ending's LOG 01 closes on, seen
  ## here at second zero. Survival never counts down, it only counts up, so the
  ## clock starts slow and accelerates while the swarm gathers at the light's edge.
  let cx = sw.float32 * 0.5'f32
  let cy = sh.float32 * 0.40'f32
  let open = easeOut(local / (duration * 0.4'f32))
  let dialR = 92.0'f32

  drawSoftGlow(cx, cy, 190.0'f32 * open, colorA(SurvAccent, alpha * 44.0'f32), 1.0'f32)

  # Uptime dial: one slow sweep across the shot, ticked like a clock face.
  let sweep = (local / duration) * 360.0'f32
  drawRing(Vector2(x: cx, y: cy), dialR - 2.0'f32, dialR + 2.0'f32, -90.0'f32, -90.0'f32 + sweep, 48,
           colorA(SurvAccent, alpha * 215.0'f32))
  drawCircleLines(Vector2(x: cx, y: cy), dialR, colorA(SurvAccent, alpha * 70.0'f32 * open))
  for i in 0..<12:
    let a = i.float32 * PI * 2.0'f32 / 12.0'f32 - PI * 0.5'f32
    let r1 = dialR - (if i mod 3 == 0: 12.0'f32 else: 7.0'f32)
    drawLine((cx + cos(a) * r1).int32, (cy + sin(a) * r1).int32,
             (cx + cos(a) * dialR).int32, (cy + sin(a) * dialR).int32,
             colorA(SurvAccent, alpha * (if i mod 3 == 0: 200.0'f32 else: 120.0'f32)))

  # The flood arriving: more processes circle the edge of the light as time runs.
  let enemyKinds = [etThread, etForkBomb, etThread, etZombie, etWatchdog, etThread, etDeadlock, etInterrupt]
  let arrived = min(12, 3 + int(local * 2.2'f32))
  for i in 0..<arrived:
    let a = i.float32 * PI * 2.0'f32 / 12.0'f32 + local * 0.28'f32
    let settle = easeOut(clamp01((local - i.float32 * 0.35'f32) / 0.9'f32))
    let r = 150.0'f32 + (1.0'f32 - settle) * 140.0'f32 + sin(local * 1.5'f32 + i.float32) * 14.0'f32
    drawRealEnemy(enemyKinds[i mod enemyKinds.len], cx + cos(a) * r, cy + sin(a) * r * 0.72'f32,
                  10.0'f32, local, i, 0)

  # The defender at the heart of the dial.
  drawEquippedPlayerModel(newVector2f(cx, cy), 20.0'f32 * (0.7'f32 + open * 0.3'f32), local, alpha, 0.22'f32)

  # Uptime readout below the swarm ring: starts at zero and accelerates. It
  # never counts down.
  let uptime = int(pow(local, 1.7'f32) * 36.0'f32)
  let label = t(tkModeIntroSurvUptime)
  let readA = alpha * open
  let readY = cy + 150.0'f32 * 0.72'f32 + 32.0'f32
  drawCenteredText(label, sw div 2, readY.int32, 14, colorA(SurvAccent, readA * 170.0'f32))
  drawCenteredText(formatUptime(uptime), sw div 2, (readY + 18.0'f32).int32, 30,
                   Color(r: 255, g: 235, b: 210, a: alphaByte(readA * 240.0'f32)))

  drawSubtitles([t(tkModeIntroSurv1a), t(tkModeIntroSurv1b)], sw, sh, alpha)

proc drawSurvShot2(local, duration: float32, sw, sh: int32, alpha: float32) =
  ## UPTIME LOG: the watch as a record. One "line held" entry per minute scrolls
  ## up the log while a heartbeat trace runs underneath: a log with no last line.
  let cx = sw.float32 * 0.5'f32
  const rowH = 24'i32
  const visibleRows = 7
  let panelW = 440'i32
  let panelX = (cx - panelW.float32 * 0.5'f32).int32
  let panelY = (sh.float32 * 0.17'f32).int32
  let panelH = rowH * visibleRows + 16

  drawSoftGlow(cx, panelY.float32 + panelH.float32 * 0.5'f32, 240.0'f32,
               colorA(SurvAccent, alpha * 26.0'f32), 1.0'f32)
  drawRectangle(panelX, panelY, panelW, panelH, Color(r: 12, g: 8, b: 6, a: alphaByte(alpha * 200.0'f32)))
  drawRectangleLines(panelX, panelY, panelW, panelH, colorA(SurvAccent, alpha * 150.0'f32))

  # Entries arrive on a steady cadence; once the panel is full it jumps a line
  # per entry, the way a real terminal log scrolls.
  let rate = 2.4'f32
  let written = local * rate
  let count = int(written)
  let frac = written - count.float32
  let firstRow = max(0, count - visibleRows + 1)
  let held = t(tkModeIntroSurvLogHeld)
  # Fixed message column: digit widths vary ("1" is narrow) so measuring each
  # row's own stamp made the column wobble.
  let msgX = panelX + 16 + measureText("[00:00:00]", 18) + 18
  for n in firstRow..count:
    let y = panelY + 8 + (n - firstRow).int32 * rowH
    let isNewest = n == count
    let appear = if isNewest: clamp01(frac / 0.2'f32) else: 1.0'f32
    let rowA = alpha * appear * (if isNewest: 245.0'f32 else: 150.0'f32)
    let stamp = "[" & formatUptime((n + 1) * 60) & "]"
    drawText(stamp, panelX + 16, y, 18, colorA(SurvAccent, rowA))
    drawText(held, msgX, y, 18,
             Color(r: 255, g: 235, b: 210, a: alphaByte(rowA)))
    if isNewest:
      drawRectangle(panelX + 4, y + 2, 3, 16, colorA(SurvAccent, rowA))

  # Heartbeat trace under the log, scrolling left: the process is still alive.
  let traceY = (panelY + panelH + 58).float32
  let traceW = panelW.float32
  var prev = Vector2(x: panelX.float32, y: traceY)
  const segments = 88
  for i in 1..segments:
    let u = i.float32 / segments.float32
    let phase = fractCoord(u * 3.0'f32 - local * 0.9'f32)
    let spike =
      if phase > 0.46'f32 and phase < 0.5'f32: -38.0'f32 * sin((phase - 0.46'f32) / 0.04'f32 * PI)
      elif phase > 0.5'f32 and phase < 0.53'f32: 16.0'f32 * sin((phase - 0.5'f32) / 0.03'f32 * PI)
      else: sin(phase * 40.0'f32) * 1.5'f32
    let p = Vector2(x: panelX.float32 + u * traceW, y: traceY + spike)
    drawLine(prev, p, 2.0'f32, colorA(SurvAccent, alpha * 200.0'f32 * (0.35'f32 + u * 0.65'f32)))
    prev = p
  drawCircle(prev, 3.5'f32, colorA(SurvAccent, alpha * 240.0'f32))

  drawSubtitles([t(tkModeIntroSurv2a), t(tkModeIntroSurv2b)], sw, sh, alpha)

proc newSurvivalIntroCutscene*(): Cutscene =
  newCutscene(
    shots = @[
      CutsceneShot(duration: 5.0'f32, drawProc: drawSurvShot1, soundCue: stShield,
                   label: t(tkModeIntroSurvRec1), iconIndex: 5),
      CutsceneShot(duration: 5.0'f32, drawProc: drawSurvShot2, soundCue: stWaveComplete,
                   label: t(tkModeIntroSurvRec2), iconIndex: 10),
    ],
    accentColor      = SurvAccent,
    titleCardText    = "TopHat-ShooterOS",
    titleCardSub     = t(tkModeIntroSurvTitle),
    drawBackdropProc = simpleBackdrop(SurvAccent),
    swayAmp          = 0.7'f32,
    musicTrack       = mtMenu,
  )

# ---------------------------------------------------------------------------
# Roguelite intro shots

proc hash01Mode(n: float32): float32 =
  ## Deterministic 0..1 noise, so every playback stages identically.
  fractCoord(sin(n * 12.9898'f32) * 43758.5453'f32)

proc triAny(a, b, c: Vector2, col: Color) =
  ## Winding-safe triangle (raylib culls one winding).
  let cross = (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
  if cross < 0.0'f32: drawTriangle(a, b, c, col)
  else: drawTriangle(a, c, b, col)

proc lerpV(a, b: Vector2, t: float32): Vector2 =
  Vector2(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)

proc drawRogueShot1(local, duration: float32, sw, sh: int32, alpha: float32) =
  ## STACK MAP as an actual descent: the camera falls with the process through
  ## the sector layers (the same themes the floor picker offers), toward the
  ## rot pulsing under the Corrupted Sector at the bottom of the stack.
  const themes = [dftFirewall, dftRecycleBin, dftRegistry, dftNetwork,
                  dftKernel, dftCache, dftCorruptedSector]
  const gap = 150.0'f32
  let cx = sw.float32 * 0.5'f32
  let playerY = sh.float32 * 0.38'f32
  let depth = easeInOut(local / duration) * gap * 5.4'f32
  let firstY = playerY + 100.0'f32
  let hw = 235.0'f32
  let hh = 52.0'f32

  # The rot below the stack, brighter the deeper we fall.
  let bottomY = firstY + themes.high.float32 * gap - depth
  let near = clamp01(depth / (gap * 5.4'f32))
  drawSoftGlow(cx, bottomY, 150.0'f32 + sin(local * 3.0'f32) * 20.0'f32,
               Color(r: 170, g: 40, b: 255, a: alphaByte(alpha * (25.0'f32 + near * 45.0'f32))), 1.0'f32)

  var passed = 0
  var nearest = 1.0e9'f32
  for k in countdown(themes.high, 0):
    let y = firstY + k.float32 * gap - depth
    if y < playerY:
      inc passed
    nearest = min(nearest, abs(y - playerY))
    if y < -hh or y > sh.float32 + hh:
      continue
    # Fade out approaching the caption band so the text keeps its contrast.
    let bandTop = (sh - sh div 9 - 100).float32
    let la = alpha * clamp01((bandTop - y) / 110.0'f32)
    if la <= 0.0'f32:
      continue
    let acc = themeAccent(themes[k])
    let left = Vector2(x: cx - hw, y: y)
    let top = Vector2(x: cx, y: y - hh)
    let right = Vector2(x: cx + hw, y: y)
    let bottom = Vector2(x: cx, y: y + hh)
    let fill = colorA(acc, la * 34.0'f32)
    triAny(left, top, right, fill)
    triAny(left, right, bottom, fill)
    for g in 1..3:
      let u = g.float32 / 4.0'f32
      drawLine(lerpV(left, top, u), lerpV(bottom, right, u), 1.0'f32, colorA(acc, la * 55.0'f32))
      drawLine(lerpV(top, right, u), lerpV(left, bottom, u), 1.0'f32, colorA(acc, la * 55.0'f32))
    for (a, b) in [(left, top), (top, right), (right, bottom), (bottom, left)]:
      drawLine(a, b, 2.0'f32, colorA(acc, la * 190.0'f32))
    let name = themeName(themes[k])
    let nw = measureText(name, 16)
    drawText(name, (cx - hw - 16.0'f32).int32 - nw, (y - 8.0'f32).int32, 16, colorA(acc, la * 230.0'f32))
    drawText(intToStr(k + 1, 2), (cx + hw + 14.0'f32).int32, (y - 8.0'f32).int32, 16,
             colorA(acc, la * 150.0'f32))

  # The falling process: speed streaks above, a flash at each layer it breaks.
  let flash = 1.0'f32 - clamp01(nearest / 28.0'f32)
  for i in 0..<10:
    let sx = cx + (hash01Mode(i.float32) - 0.5'f32) * 70.0'f32
    let p = fractCoord(local * 2.2'f32 + i.float32 * 0.1'f32)
    let sy = playerY - 30.0'f32 - p * 150.0'f32
    drawLine(sx.int32, sy.int32, sx.int32, (sy - 26.0'f32).int32,
             colorA(RogueAccent, alpha * (1.0'f32 - p) * 150.0'f32))
  if flash > 0.0'f32:
    drawCircleLines(Vector2(x: cx, y: playerY), 26.0'f32 + flash * 60.0'f32,
                    Color(r: 255, g: 255, b: 255, a: alphaByte(alpha * flash * 200.0'f32)))
  drawEquippedPlayerModel(newVector2f(cx, playerY), 22.0'f32, local, alpha, 0.25'f32 + flash * 0.5'f32)

  # Depth gauge on the right edge.
  let gx = (sw - 60).int32
  let gTop = sh div 9 + 40
  let gBottom = sh - sh div 9 - 150
  drawLine(gx, gTop, gx, gBottom, colorA(RogueAccent, alpha * 120.0'f32))
  for k in 0..themes.high:
    let ty = gTop + int32((gBottom - gTop).float32 * k.float32 / themes.high.float32)
    drawLine(gx - 5, ty, gx + 5, ty, colorA(themeAccent(themes[k]), alpha * 170.0'f32))
  let frac = clamp01((depth - 100.0'f32 + gap) / (themes.len.float32 * gap))
  let my = gTop.float32 + (gBottom - gTop).float32 * frac
  drawTriangle(Vector2(x: gx.float32 - 8.0'f32, y: my - 6.0'f32), Vector2(x: gx.float32 - 8.0'f32, y: my + 6.0'f32),
               Vector2(x: gx.float32 + 2.0'f32, y: my), colorA(RogueAccent, alpha * 240.0'f32))
  let sector = t(tkModeIntroRogueSector).replace("$1", intToStr(passed + 1, 2))
  let sw2 = measureText(sector, 16)
  drawText(sector, gx - 16 - sw2, my.int32 - 8, 16, colorA(RogueAccent, alpha * 230.0'f32))

  drawSubtitles([t(tkModeIntroRogue1a), t(tkModeIntroRogue1b)], sw, sh, alpha)

proc drawRogueShot2(local, duration: float32, sw, sh: int32, alpha: float32) =
  let cx = sw.float32 * 0.5'f32
  let cy = sh.float32 * 0.45'f32
  let progress = easeInOut(local / duration)

  # Orbiting relic pickups.
  for i in 0..<5:
    let a = i.float32 * PI * 2.0'f32 / 5.0'f32 + local * 0.9'f32
    let r = 90.0'f32 + sin(local * 2.0'f32 + i.float32) * 10.0'f32
    let rx = cx + cos(a) * r
    let ry = cy + sin(a) * r * 0.6'f32
    drawSoftGlow(rx, ry, 28.0'f32 * progress, colorA(RogueAccent, alpha * 55.0'f32 * progress), 1.0'f32)
    drawCircle(Vector2(x: rx, y: ry), 8.0'f32 * progress,
               colorA(RogueAccent, alpha * 200.0'f32 * progress))

  drawKernelModel(newVector2f(cx, cy), 34.0'f32, local, progress, alpha)
  drawSubtitles([t(tkModeIntroRogue2a), t(tkModeIntroRogue2b)], sw, sh, alpha)

proc newRogueliteIntroCutscene*(): Cutscene =
  newCutscene(
    shots = @[
      CutsceneShot(duration: 5.0'f32, drawProc: drawRogueShot1, soundCue: stTeleport,
                   label: t(tkModeIntroRogueRec1), iconIndex: 4),
      CutsceneShot(duration: 5.0'f32, drawProc: drawRogueShot2, soundCue: stPowerUp,
                   label: t(tkModeIntroRogueRec2), iconIndex: 7),
    ],
    accentColor      = RogueAccent,
    titleCardText    = "TopHat-ShooterOS",
    titleCardSub     = t(tkModeIntroRogueTitle),
    drawBackdropProc = simpleBackdrop(RogueAccent),
    swayAmp          = 0.9'f32,
    musicTrack       = mtBoss,
  )

# ---------------------------------------------------------------------------
# Sandbox intro (single shot)

proc drawSandboxShot1(local, duration: float32, sw, sh: int32, alpha: float32) =
  let cx = sw.float32 * 0.5'f32
  let cy = sh.float32 * 0.42'f32
  let open = easeOut(local / (duration * 0.6'f32))

  # Scrolling terminal text.
  let lines = [t(tkModeIntroSandboxTerm1),
               t(tkModeIntroSandboxTerm2),
               t(tkModeIntroSandboxTerm3),
               t(tkModeIntroSandboxTerm4),
               t(tkModeIntroSandboxTerm5),
               "> _"]
  for i, line in lines:
    let appear = clamp01((local - i.float32 * 0.48'f32) / 0.35'f32)
    if appear <= 0.0'f32: continue
    let yp = cy - 60.0'f32 + i.float32 * 22.0'f32
    drawText(line, (cx - 190.0'f32).int32, yp.int32, 16,
             Color(r: SandboxAccent.r, g: SandboxAccent.g, b: SandboxAccent.b,
                   a: alphaByte(alpha * appear * 200.0'f32)))

  drawSoftGlow(cx, cy, 110.0'f32 * open, colorA(SandboxAccent, alpha * 28.0'f32), 1.0'f32)
  drawSubtitles([t(tkModeIntroSandbox1a), t(tkModeIntroSandbox1b)], sw, sh, alpha)

proc drawSandboxCursor(x, y, alpha: float32, pressed: bool) =
  ## A plain OS pointer; it dips a pixel while "clicking".
  let d = if pressed: 1.0'f32 else: 0.0'f32
  let tip = Vector2(x: x + d, y: y + d)
  let a = Vector2(x: tip.x, y: tip.y + 20.0'f32)
  let b = Vector2(x: tip.x + 14.0'f32, y: tip.y + 14.0'f32)
  triAny(Vector2(x: tip.x - 1.5'f32, y: tip.y - 2.0'f32), Vector2(x: a.x - 1.5'f32, y: a.y + 2.5'f32),
         Vector2(x: b.x + 2.5'f32, y: b.y + 1.0'f32), Color(r: 0, g: 0, b: 0, a: alphaByte(alpha * 220.0'f32)))
  triAny(tip, a, b, Color(r: 245, g: 245, b: 245, a: alphaByte(alpha * 255.0'f32)))

proc fitText(text: string, size, maxW: int32): string =
  ## Clip a label to maxW with a trailing "...", rune-safe for accents.
  if measureText(text, size) <= maxW:
    return text
  var n = text.runeLen
  while n > 0 and measureText(text.runeSubStr(0, n) & "...", size) > maxW:
    dec n
  text.runeSubStr(0, n) & "..."

proc drawSandboxShot2(local, duration: float32, sw, sh: int32, alpha: float32) =
  ## SPAWN TOOLS, the way the real mode works: the pointer clicks a process in
  ## the spawn list and it enters from a screen edge, heading for the player.
  const sidebarW = 300'i32
  const btnH = 35'i32
  const btnGap = 5'i32
  const listKinds = [etCircle, etCube, etTriangle, etStar, etHexagon, etCross, etDiamond, etOctagon]
  const clicks = [0, 2, 3, 6, 1, 7]        # which list button each click hits
  const clickStart = 0.55'f32
  const clickEvery = 0.6'f32
  const travel = 0.4'f32                   # pointer travel time into each click
  # Where each spawn enters: 0 = top edge, 1 = left edge, 2 = bottom edge, and
  # how far along that edge (the real mode picks a random edge point).
  const entries = [(0, 0.3'f32), (2, 0.7'f32), (1, 0.3'f32), (0, 0.78'f32), (2, 0.22'f32), (1, 0.72'f32)]

  let sidebarX = sw - sidebarW
  let top = sh div 9
  let bottom = sh - sh div 9
  let panelBottom = bottom - 110
  let playCx = sidebarX.float32 * 0.5'f32
  let playCy = sh.float32 * 0.44'f32
  let bx = sidebarX + 10
  let bw = sidebarW - 20
  let listY = top + 44

  proc buttonY(i: int): int32 = listY + i.int32 * (btnH + btnGap)
  proc clickPoint(i: int): Vector2 =
    Vector2(x: (bx + bw div 2 + 40).float32, y: buttonY(i).float32 + btnH.float32 * 0.5'f32)

  # Test floor grid over the play area.
  let grid = colorA(SandboxAccent, alpha * 22.0'f32)
  var gx = 0'i32
  while gx < sidebarX:
    drawLine(gx, top, gx, bottom, grid)
    gx += 40
  var gy = top
  while gy < bottom:
    drawLine(0, gy, sidebarX, gy, grid)
    gy += 40

  drawEquippedPlayerModel(newVector2f(playCx, playCy), 20.0'f32, local, alpha, 0.2'f32)

  # Every click spawns its process just outside an edge; it walks in and
  # settles around the player.
  for k, idx in clicks:
    let tClick = clickStart + k.float32 * clickEvery
    if local < tClick:
      continue
    let (edge, f) = entries[k]
    let entry =
      case edge
      of 0: Vector2(x: sidebarX.float32 * f, y: top.float32 - 18.0'f32)
      of 1: Vector2(x: -18.0'f32, y: top.float32 + (panelBottom - top).float32 * f)
      else: Vector2(x: sidebarX.float32 * f, y: bottom.float32 + 18.0'f32)
    let ga = k.float32 * PI * 2.0'f32 / clicks.len.float32 + 0.4'f32
    let gather = Vector2(x: playCx + cos(ga) * 120.0'f32, y: playCy + sin(ga) * 88.0'f32)
    let p = easeOut(clamp01((local - tClick) / 1.5'f32))
    let pos = lerpV(entry, gather, p)
    let dx = gather.x - entry.x
    let dy = gather.y - entry.y
    let len = max(1.0'f32, sqrt(dx * dx + dy * dy))
    drawRealEnemy(listKinds[idx], pos.x, pos.y, 12.0'f32, local, 300 + k, 0,
                  newVector2f(dx / len * 90.0'f32 * (1.0'f32 - p), dy / len * 90.0'f32 * (1.0'f32 - p)))

  # The spawn list, drawn like the mode's own Enemies tab.
  drawRectangle(sidebarX, top, sidebarW, panelBottom - top, Color(r: 22, g: 22, b: 34, a: alphaByte(alpha * 240.0'f32)))
  drawLine(sidebarX, top, sidebarX, panelBottom, Color(r: 100, g: 100, b: 150, a: alphaByte(alpha * 220.0'f32)))
  drawText(t(tkSandboxSpawnEnemies), bx, top + 14, 18, Color(r: 255, g: 255, b: 255, a: alphaByte(alpha * 240.0'f32)))
  for i, kind in listKinds:
    let y = buttonY(i)
    var flash = 0.0'f32
    for k, idx in clicks:
      let tClick = clickStart + k.float32 * clickEvery
      if idx == i and local >= tClick:
        flash = max(flash, 1.0'f32 - clamp01((local - tClick) / 0.25'f32))
    let fill = Color(r: uint8(70.0'f32 + flash * 70.0'f32), g: uint8(70.0'f32 + flash * 70.0'f32),
                     b: uint8(120.0'f32 + flash * 90.0'f32), a: alphaByte(alpha * 245.0'f32))
    drawRectangle(bx, y, bw, btnH, fill)
    drawRectangleLines(bx, y, bw, btnH, Color(r: 100, g: 100, b: 150, a: alphaByte(alpha * 255.0'f32)))
    # Small radius: some enemies (Star, Diamond) draw halos well past it.
    drawRealEnemy(kind, (bx + 18).float32, (y + btnH div 2).float32, 6.0'f32, local, 400 + i, 0)
    let cfg = getEnemyConfig(kind)
    drawText(cfg.name, bx + 40, y + 4, 16, Color(r: 255, g: 255, b: 255, a: alphaByte(alpha * 245.0'f32)))
    drawText(fitText(cfg.description, 12, bw - 48), bx + 40, y + 21, 12,
             Color(r: 180, g: 180, b: 180, a: alphaByte(alpha * 230.0'f32)))

  # The pointer: glides onto each button just before its click.
  var cursor = Vector2(x: playCx + 150.0'f32, y: playCy + 90.0'f32)
  var pressed = false
  for k, idx in clicks:
    let tClick = clickStart + k.float32 * clickEvery
    let prev = if k == 0: Vector2(x: playCx + 150.0'f32, y: playCy + 90.0'f32) else: clickPoint(clicks[k - 1])
    if local >= tClick - travel:
      cursor = lerpV(prev, clickPoint(idx), easeInOut(clamp01((local - (tClick - travel)) / travel)))
    if local >= tClick and local < tClick + 0.12'f32:
      pressed = true
  drawSandboxCursor(cursor.x, cursor.y, alpha, pressed)

  drawSubtitles([t(tkModeIntroSandbox2a), t(tkModeIntroSandbox2b)], sw, sh, alpha)

proc newSandboxIntroCutscene*(): Cutscene =
  newCutscene(
    shots = @[
      CutsceneShot(duration: 5.2'f32, drawProc: drawSandboxShot1, soundCue: stMenuSelect,
                   label: t(tkModeIntroSandboxRec1), iconIndex: 10),
      CutsceneShot(duration: 5.4'f32, drawProc: drawSandboxShot2, soundCue: stPowerUp,
                   label: t(tkModeIntroSandboxRec2), iconIndex: 0),
    ],
    accentColor      = SandboxAccent,
    titleCardText    = "TopHat-ShooterOS",
    titleCardSub     = t(tkModeIntroSandboxTitle),
    drawBackdropProc = simpleBackdrop(SandboxAccent),
    swayAmp          = 0.5'f32,
    musicTrack       = mtMenu,
  )

# ---------------------------------------------------------------------------
# PvP intro shots

proc drawPvPShot1(local, duration: float32, sw, sh: int32, alpha: float32) =
  let cx = sw.float32 * 0.5'f32
  let cy = sh.float32 * 0.45'f32
  let scan = easeInOut(local / duration)

  # Network scan lines sweeping down.
  let scanY = (scan * (sh.float32 + 60.0'f32) - 40.0'f32).int32
  drawRectangle(0, scanY, sw, 2, colorA(PvPAccent, alpha * 200.0'f32))
  drawRectangleGradientV(0, max(0, scanY - 40), sw, min(40, scanY),
                         colorA(PvPAccent, 0.0'f32), colorA(PvPAccent, alpha * 50.0'f32))

  # Node connections.
  for i in 0..<6:
    let seed = i.float32 * 5.37'f32
    let nx = sw.float32 * (0.15'f32 + fractCoord(seed) * 0.7'f32)
    let ny = sh.float32 * (0.2'f32 + fractCoord(seed * 1.7'f32) * 0.55'f32)
    let passed = ny.int32 <= scanY
    let nodeAlpha = if passed: alpha * 200.0'f32 else: 0.0'f32
    if nodeAlpha > 0:
      drawCircle(Vector2(x: nx, y: ny), 6.0'f32, colorA(PvPAccent, nodeAlpha))
      if i > 0:
        let px = sw.float32 * (0.15'f32 + fractCoord((i - 1).float32 * 5.37'f32) * 0.7'f32)
        let py = sh.float32 * (0.2'f32 + fractCoord((i - 1).float32 * 5.37'f32 * 1.7'f32) * 0.55'f32)
        drawLine(nx.int32, ny.int32, px.int32, py.int32,
                 colorA(PvPAccent, nodeAlpha * 0.4'f32))

  drawSoftGlow(cx, cy, 100.0'f32, colorA(PvPAccent, alpha * 25.0'f32), 1.0'f32)
  drawSubtitles([t(tkModeIntroPvP1a), t(tkModeIntroPvP1b)], sw, sh, alpha)

proc drawPvPShot2(local, duration: float32, sw, sh: int32, alpha: float32) =
  let cy = sh.float32 * 0.48'f32
  let enter = easeInOut(local / (duration * 0.55'f32))

  # Two player models facing each other.
  let p1x = sw.float32 * (0.5'f32 - 0.18'f32 * enter)
  let p2x = sw.float32 * (0.5'f32 + 0.18'f32 * enter)
  drawEquippedPlayerModel(newVector2f(p1x, cy), 22.0'f32, local, alpha, 0.18'f32)
  drawEquippedPlayerModel(newVector2f(p2x, cy), 22.0'f32, -local, alpha, 0.18'f32)

  # VS label.
  let vsAlpha = alpha * easeInOut((local - 1.0'f32) / 0.6'f32)
  if vsAlpha > 0.0'f32:
    let vsW = measureText("VS", 40)
    drawText("VS", sw div 2 - vsW div 2, (cy - 22).int32, 40,
             colorA(PvPAccent, vsAlpha * 220.0'f32))

  drawSoftGlow(sw.float32 * 0.5'f32, cy, 110.0'f32 * enter, colorA(PvPAccent, alpha * 35.0'f32), 1.0'f32)
  drawSubtitles([t(tkModeIntroPvP2a), t(tkModeIntroPvP2b)], sw, sh, alpha)

proc drawPvPShot3(local, duration: float32, sw, sh: int32, alpha: float32) =
  ## LINK DUEL: both processes fire down one contested link. The clash point
  ## drifts back and forth: neither side owns the connection yet.
  let cy = sh.float32 * 0.46'f32
  let lx = sw.float32 * 0.2'f32
  let rx = sw.float32 * 0.8'f32
  let clashX = sw.float32 * 0.5'f32 + sin(local * 1.4'f32) * 55.0'f32
  let enter = easeOut(local / (duration * 0.3'f32))

  # The link itself: a flickering dashed line between the two nodes.
  var x = lx + 34.0'f32
  var k = 0
  while x < rx - 34.0'f32:
    let flick = hash01Mode(k.float32 + floor(local * 18.0'f32))
    drawLine(x.int32, cy.int32, (x + 9.0'f32).int32, cy.int32,
             colorA(PvPAccent, alpha * enter * (60.0'f32 + flick * 90.0'f32)))
    x += 16.0'f32
    inc k

  # Friendly stream (your bullet skin) and hostile stream, meeting at the clash.
  for i in 0..<7:
    let p = fractCoord(local * 1.1'f32 + i.float32 / 7.0'f32)
    let bx = lx + 34.0'f32 + (clashX - lx - 34.0'f32) * p
    let by = cy + sin(i.float32 * 2.1'f32 + local * 3.0'f32) * 16.0'f32 * (1.0'f32 - p)
    for tr in 1..3:
      drawCircle(Vector2(x: bx - tr.float32 * 9.0'f32, y: by), 6.0'f32 - tr.float32 * 1.4'f32,
                 Color(r: 0, g: 230, b: 230, a: alphaByte(alpha * enter * (120.0'f32 - tr.float32 * 30.0'f32))))
    drawEquippedBulletModel(newVector2f(bx, by), 7.0'f32, 0.0'f32, local + i.float32, alpha * enter)
  for i in 0..<7:
    let p = fractCoord(local * 1.1'f32 + (i.float32 + 0.5'f32) / 7.0'f32)
    let bx = rx - 34.0'f32 - (rx - 34.0'f32 - clashX) * p
    let by = cy + sin(i.float32 * 1.7'f32 + local * 3.0'f32) * 16.0'f32 * (1.0'f32 - p)
    for tr in 1..3:
      drawCircle(Vector2(x: bx + tr.float32 * 9.0'f32, y: by), 6.0'f32 - tr.float32 * 1.4'f32,
                 colorA(PvPAccent, alpha * enter * (120.0'f32 - tr.float32 * 30.0'f32)))
    drawCircle(Vector2(x: bx, y: by), 6.5'f32, Color(r: 255, g: 90, b: 90, a: alphaByte(alpha * enter * 240.0'f32)))
    drawCircle(Vector2(x: bx, y: by), 3.0'f32, Color(r: 255, g: 220, b: 220, a: alphaByte(alpha * enter * 240.0'f32)))

  # The clash: sparks where the streams cancel out.
  drawSoftGlow(clashX, cy, 42.0'f32 + sin(local * 11.0'f32) * 8.0'f32,
               Color(r: 255, g: 120, b: 220, a: alphaByte(alpha * enter * 70.0'f32)), 1.0'f32)
  for i in 0..<10:
    let a = hash01Mode(i.float32 + floor(local * 14.0'f32)) * PI * 2.0'f32
    let len = 10.0'f32 + hash01Mode(i.float32 * 3.3'f32 + floor(local * 14.0'f32)) * 26.0'f32
    drawLine(Vector2(x: clashX, y: cy), Vector2(x: clashX + cos(a) * len, y: cy + sin(a) * len), 2.0'f32,
             Color(r: 255, g: 235, b: 245, a: alphaByte(alpha * enter * 200.0'f32)))

  # The two processes.
  drawSoftGlow(lx, cy, 64.0'f32, Color(r: 0, g: 230, b: 230, a: alphaByte(alpha * 50.0'f32)), 1.0'f32)
  drawEquippedPlayerModel(newVector2f(lx, cy), 24.0'f32, local, alpha, 0.25'f32)
  drawCircleLines(Vector2(x: lx, y: cy), 34.0'f32 + sin(local * 5.0'f32 + 1.0'f32) * 2.0'f32,
                  Color(r: 0, g: 230, b: 230, a: alphaByte(alpha * 200.0'f32)))
  drawSoftGlow(rx, cy, 64.0'f32, colorA(PvPAccent, alpha * 50.0'f32), 1.0'f32)
  drawEquippedPlayerModel(newVector2f(rx, cy), 24.0'f32, -local, alpha, 0.25'f32)
  drawCircleLines(Vector2(x: rx, y: cy), 34.0'f32 + sin(local * 5.0'f32) * 2.0'f32, colorA(PvPAccent, alpha * 200.0'f32))

  drawSubtitles([t(tkModeIntroPvP3a), t(tkModeIntroPvP3b)], sw, sh, alpha)

proc newPvPIntroCutscene*(): Cutscene =
  newCutscene(
    shots = @[
      CutsceneShot(duration: 5.0'f32, drawProc: drawPvPShot1, soundCue: stTeleport,
                   label: t(tkModeIntroPvPRec1), iconIndex: 3),
      CutsceneShot(duration: 5.0'f32, drawProc: drawPvPShot2, soundCue: stBossSpawn,
                   label: t(tkModeIntroPvPRec2), iconIndex: 7),
      CutsceneShot(duration: 4.8'f32, drawProc: drawPvPShot3, soundCue: stShoot,
                   label: t(tkModeIntroPvPRec3), iconIndex: 0,
                   glitchMod: 71, glitchWindow: 5),
    ],
    accentColor      = PvPAccent,
    titleCardText    = "TopHat-ShooterOS",
    titleCardSub     = t(tkModeIntroPvPTitle),
    drawBackdropProc = simpleBackdrop(PvPAccent),
    swayAmp          = 0.9'f32,
    musicTrack       = mtBoss,
  )
