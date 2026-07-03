## Mode-intro cutscenes, one per GameMode.
## Each plays once the first time a player enters that mode; the flag is set in
## main.nim before activating gsCutscene.  All factories return a Cutscene built
## on the generic framework in cutscene.nim; shot content uses the same
## cinematic_common helpers as the lore and endgame cinematics.

import raylib, rlgl, math
import particle_types, background_fx, ../types, ../localization, ../sound, cinematic_common, cutscene

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
                       Color(r: accent.r, g: accent.g, b: accent.b, a: 30),
                       0.48, 0.42)

# ---------------------------------------------------------------------------
# Wave-Based intro shots

proc drawWaveShot1(local, duration: float32, sw, sh: int32, alpha: float32) =
  let cx = sw.float32 * 0.5'f32
  let cy = sh.float32 * 0.46'f32
  let open = easeOut(local / duration)

  # Expanding radar rings.
  for i in 0..<6:
    let r = (40.0'f32 + i.float32 * 48.0'f32) * open
    let a = alpha * (160.0'f32 - i.float32 * 18.0'f32) * (0.6'f32 + 0.4'f32 * sin(local * 3.0'f32 + i.float32))
    drawCircleLines(Vector2(x: cx, y: cy), r, colorA(WaveAccent, a))

  # Sweep line.
  let sweepA = local * 1.8'f32
  let sweepLen = 200.0'f32 * open
  drawLine(cx.int32, cy.int32,
           (cx + cos(sweepA) * sweepLen).int32,
           (cy + sin(sweepA) * sweepLen).int32,
           Color(r: 0, g: 235, b: 235, a: alphaByte(alpha * 210.0'f32)))
  drawSoftGlow(cx, cy, 120.0'f32 * open, colorA(WaveAccent, alpha * 55.0'f32), 1.0'f32)

  # Threat blips.
  for i in 0..<8:
    let a = i.float32 * PI * 2.0'f32 / 8.0'f32 + 0.4'f32
    let d = (70.0'f32 + (i mod 3).float32 * 50.0'f32) * open
    let bx = cx + cos(a) * d
    let by = cy + sin(a) * d
    let pulse = 0.5'f32 + 0.5'f32 * sin(local * 6.0'f32 + i.float32 * 1.3'f32)
    drawCircle(Vector2(x: bx, y: by), 4.0'f32 + pulse * 3.0'f32,
               Color(r: 255, g: 60, b: 60, a: alphaByte(alpha * pulse * 220.0'f32)))

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
      CutsceneShot(duration: 5.0'f32, drawProc: drawWaveShot1, soundCue: stTeleport,
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

proc drawSurvShot1(local, duration: float32, sw, sh: int32, alpha: float32) =
  let cx = sw.float32 * 0.5'f32
  let cy = sh.float32 * 0.42'f32
  let countdown = 5.0'f32 - local * (5.0'f32 / duration)
  let urgency = easeInOut(local / duration)

  # Pulsing countdown digits.
  let numStr = $countdown.int
  let pulse = 0.5'f32 + 0.5'f32 * sin(local * (4.0'f32 + urgency * 8.0'f32))
  let numSize = (64 + (pulse * 24.0'f32).int).int32
  let numW = measureText(numStr, numSize)
  drawText(numStr, cx.int32 - numW div 2, (cy - 40).int32, numSize,
           Color(r: SurvAccent.r, g: SurvAccent.g, b: SurvAccent.b,
                 a: alphaByte(alpha * (180.0'f32 + pulse * 75.0'f32))))
  drawSoftGlow(cx, cy, 90.0'f32 + pulse * 50.0'f32,
               colorA(SurvAccent, alpha * (40.0'f32 + urgency * 30.0'f32)), 1.0'f32)

  # Tick marks around the clock.
  for i in 0..<12:
    let a = i.float32 * PI * 2.0'f32 / 12.0'f32 - PI / 2.0'f32
    let r1 = 100.0'f32; let r2 = 116.0'f32
    drawLine((cx + cos(a) * r1).int32, (cy + sin(a) * r1).int32,
             (cx + cos(a) * r2).int32, (cy + sin(a) * r2).int32,
             colorA(SurvAccent, alpha * (if i mod 3 == 0: 200.0'f32 else: 120.0'f32)))

  drawSubtitles([t(tkModeIntroSurv1a), t(tkModeIntroSurv1b)], sw, sh, alpha)

proc drawSurvShot2(local, duration: float32, sw, sh: int32, alpha: float32) =
  let cx = sw.float32 * 0.5'f32
  let cy = sh.float32 * 0.45'f32
  let progress = easeInOut(local / duration)

  # Uptime progress bar.
  let barW = (sw.float32 * 0.55'f32).int32
  let barH = 14.int32
  let barX = (cx - barW.float32 * 0.5'f32).int32
  let barY = (cy - 20.0'f32).int32
  drawRectangle(barX, barY, barW, barH, Color(r: 20, g: 30, b: 40, a: 200))
  drawRectangle(barX, barY, (barW.float32 * progress).int32, barH,
                colorA(SurvAccent, alpha * 230.0'f32))
  drawRectangleLines(barX, barY, barW, barH, colorA(SurvAccent, alpha * 160.0'f32))

  # Scrolling score digits.
  for i in 0..<6:
    let digit = $((local * 1000.0'f32 * (i + 1).float32).int mod 10)
    drawText(digit, (barX + i.int32 * 22 + 10).int32, (barY + 24).int32, 20,
             colorA(SurvAccent, alpha * (120.0'f32 + i.float32 * 20.0'f32)))

  drawSoftGlow(cx, cy, 160.0'f32, colorA(SurvAccent, alpha * 30.0'f32), 1.0'f32)
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

proc drawRogueShot1(local, duration: float32, sw, sh: int32, alpha: float32) =
  let open = easeOut(local / duration)

  # Grid of dungeon-floor cells.
  let cellW = 80.int32; let cellH = 60.int32
  let cols = sw div cellW + 2; let rows = sh div cellH + 2
  for r in 0..<rows:
    for c in 0..<cols:
      let x = (c * cellW).int32 - 30
      let y = (r * cellH).int32 - 20
      let seed = (r * cols + c).float32 * 3.7'f32
      let lit = fractCoord(sin(seed + local * 0.4'f32) * 43758.5453'f32) > 0.55'f32
      let cellAlpha = alpha * (if lit: 80.0'f32 else: 28.0'f32) * open
      drawRectangleLines(x, y, cellW, cellH, colorA(RogueAccent, cellAlpha))
      if lit:
        drawSoftGlow((x + cellW div 2).float32, (y + cellH div 2).float32,
                     26.0'f32 * open, colorA(RogueAccent, alpha * 28.0'f32 * open), 1.0'f32)

  # Central sector label.
  let cx = sw.float32 * 0.5'f32
  let cy = sh.float32 * 0.44'f32
  drawSoftGlow(cx, cy, 100.0'f32 * open, colorA(RogueAccent, alpha * 60.0'f32), 1.0'f32)
  let markerStr = "SECTOR 01"
  let mw = measureText(markerStr, 28)
  drawText(markerStr, cx.int32 - mw div 2, (cy - 18).int32, 28,
           colorA(RogueAccent, alpha * 200.0'f32 * open))
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
  let lines = ["INIT TOPHAT_SANDBOX v0.9 ...",
               "LOADING ENV MODULES ........",
               "DISABLING SAFETY CHECKS .....",
               "UNRESTRICTED ACCESS GRANTED.",
               "WARNING: NO GUARDRAILS ACTIVE",
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

proc newSandboxIntroCutscene*(): Cutscene =
  newCutscene(
    shots = @[
      CutsceneShot(duration: 6.0'f32, drawProc: drawSandboxShot1, soundCue: stMenuSelect,
                   label: t(tkModeIntroSandboxRec1), iconIndex: 10),
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

proc newPvPIntroCutscene*(): Cutscene =
  newCutscene(
    shots = @[
      CutsceneShot(duration: 5.0'f32, drawProc: drawPvPShot1, soundCue: stTeleport,
                   label: t(tkModeIntroPvPRec1), iconIndex: 3),
      CutsceneShot(duration: 5.0'f32, drawProc: drawPvPShot2, soundCue: stBossSpawn,
                   label: t(tkModeIntroPvPRec2), iconIndex: 7),
    ],
    accentColor      = PvPAccent,
    titleCardText    = "TopHat-ShooterOS",
    titleCardSub     = t(tkModeIntroPvPTitle),
    drawBackdropProc = simpleBackdrop(PvPAccent),
    swayAmp          = 0.9'f32,
    musicTrack       = mtBoss,
  )
