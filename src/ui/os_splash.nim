## OS-Themed Splash Screen: TopHat-ShooterOS v6.0 Edition
## Two phases: BIOS amber POST -> kernel model reveal with title and press-any-key.

import raylib, math
import particle_types, ../localization, ../hardware_info, ../shapes, ../sound, background_fx, cinematic_common

const
  BIOS_DUR   = 3.0'f32   # POST phase length; any key fast-boots past it
  BIOS_PRINT = 0.68'f32  # fraction of the phase spent printing POST lines
  STATUS_LAG = 0.22'f32  # pause between a line printing and its status resolving
  BIOS_OFF   = 0.24'f32  # CRT collapse window at the end of the phase

type
  BiosLineKind = enum
    blPlain      ## printed verbatim (banner, copyright, spacing)
    blStatus     ## dotted leader; status resolves STATUS_LAG after the line prints
    blRamCount   ## blStatus whose value counts up while the probe is pending
    blCountdown  ## live "Booting in N seconds" line, driven by the phase clock

  BiosLine = object
    kind: BiosLineKind
    text: string
    status: string

  BootPhase* = enum
    bpBIOS
    bpComplete

  SplashScreen* = ref object
    phase*: BootPhase
    timer*: float32
    phaseTimer*: float32
    complete*: bool
    scanlineOffset*: float32
    kernelBoot*: float32
    biosLines: seq[BiosLine]  # POST report, built from detected hardware at boot
    biosVisible: int          # lines printed so far (advanced in update, read by draw)
    ramMB: int                # detected RAM, drives the count-up on the RAM line
    poweredOn: bool           # power-on beep fired
    seatSparked: bool         # kernel-seat spark sound fired

proc statusLine(text, status: string): BiosLine =
  BiosLine(kind: blStatus, text: text, status: status)

proc plainLine(text: string): BiosLine =
  BiosLine(kind: blPlain, text: text)

proc buildBiosLines(): (seq[BiosLine], int) =
  ## The POST report. CPU/RAM/GPU/DISK/HOST come from real hardware detection
  ## (`hardware_info`); each falls back to a themed placeholder if a probe fails,
  ## and NET/SND/USB/KRNL/BOOT stay as in-world flavour. Also returns the RAM MB
  ## so the draw pass can animate the classic memory-test count-up.
  let hw = getHardwareInfo()

  let cpu = if hw.cpuName.len > 0: hw.cpuName else: "TopHat ElementalCore Processor"
  var cpuLine = "CPU  : " & cpu
  if hw.logicalCores > 0:
    cpuLine.add("  [" & $hw.logicalCores & " Threads]")

  let ramMB = if hw.ramMB > 0: hw.ramMB else: 16384
  let ramGB = (ramMB + 512) div 1024
  let gpu   = if hw.gpuName.len > 0: hw.gpuName else: "TopHat Integrated Graphics"

  let diskLine =
    if hw.diskTotalGB > 0:
      "DISK : System Volume (" & $hw.diskTotalGB & " GB, " & $hw.diskFreeGB & " GB free)"
    else:
      "DISK : TOPHAT_SYSTEM_SSD (2 TB NVMe)"

  let host = if hw.hostName.len > 0: hw.hostName else: "TOPHAT-PC"
  let osn  = if hw.osName.len  > 0: hw.osName  else: "ShooterOS 6.0"

  result[0] = @[
    plainLine("TOPHAT SYSTEMS, INC.  -  BIOS v6.0.0  -  BUILD 20260616"),
    plainLine("Copyright (C) 2024-2026 TopHat Systems, Inc.  All Rights Reserved."),
    plainLine(""),
    statusLine(cpuLine, "OK"),
    BiosLine(kind: blRamCount,
             text: "RAM  : " & $ramMB & " MB (" & $ramGB & " GB)", status: "OK"),
    statusLine("GPU  : " & gpu, "OK"),
    statusLine(diskLine, "OK"),
    statusLine("HOST : " & host & "  /  " & osn, "OK"),
    statusLine("NET  : TopHat Gigabit Ethernet", "OK"),
    statusLine("SND  : TopHat Audio Pro", "OK"),
    statusLine("USB  : xHCI Host Controller v3.1", "OK"),
    statusLine("KRNL : TOPHAT.SYS v6.0", "LOADED"),
    statusLine("BOOT : shooteros-6.0  (Secure Boot)", "ENABLED"),
    plainLine(""),
    BiosLine(kind: blCountdown, text: "Booting TopHat-ShooterOS in"),
  ]
  result[1] = ramMB

proc biosRevealTime(splash: SplashScreen, i: int): float32 =
  ## When line `i` prints: lines are spaced evenly across the print window.
  i.float32 / splash.biosLines.len.float32 * (BIOS_DUR * BIOS_PRINT)

proc drawSplashScanlines(sw, sh: int32, offset: float32, color: Color) =
  let count = sh div 4
  for i in 0..<count:
    let y = ((i.float32 * 4.0'f32 + offset) mod sh.float32).int32
    drawRectangle(0, y, sw, 1, color)

proc drawCRTAperture(sw, sh: int32, openFrac: float32, beam: Color) =
  ## Masks the screen to a centred horizontal slit whose height is
  ## `openFrac` * screen height: 1.0 = fully open (scene fully visible), 0.0 =
  ## collapsed to a single bright line. Opaque black bars fill the masked
  ## region and a `beam` line rides each leading edge, the classic CRT
  ## power-on (open from a line) / power-off (collapse to a line). Draw it
  ## last so it masks the content beneath.
  let half    = (sh.float32 * 0.5'f32) * clamp01(openFrac)
  let cy      = sh.float32 * 0.5'f32
  let topEdge = (cy - half).int32
  let botEdge = (cy + half).int32
  if topEdge > 0:
    drawRectangle(0, 0, sw, topEdge, Color(r: 0, g: 0, b: 0, a: 255))
  if botEdge < sh:
    drawRectangle(0, botEdge, sw, sh - botEdge, Color(r: 0, g: 0, b: 0, a: 255))
  if openFrac < 0.985'f32:
    drawRectangle(0, max(0'i32, topEdge - 1), sw, 2, beam)
    drawRectangle(0, min(sh - 2, botEdge - 1), sw, 2, beam)

proc drawSplashBIOS(splash: SplashScreen, sw, sh: int32) =
  drawRectangle(0, 0, sw, sh, Color(r: 0, g: 0, b: 8, a: 255))
  drawSplashScanlines(sw, sh, splash.scanlineOffset, Color(r: 24, g: 8, b: 0, a: 18))

  drawRectangleLines(Rectangle(x: 4.0'f32, y: 4.0'f32,
                               width: (sw - 8).float32, height: (sh - 8).float32),
                     2.0'f32, Color(r: 180, g: 120, b: 20, a: 200))

  # Inverted amber header bar
  let hH = 44
  drawRectangle(4, 4, sw - 8, hH.int32, Color(r: 160, g: 100, b: 10, a: 255))
  let hTitle = "TOPHAT SYSTEMS, INC.  BIOS VERSION 6.0.0"
  let hTitleW = measureText(hTitle, 22)
  drawText(hTitle, sw div 2 - hTitleW div 2, 14, 22, Color(r: 10, g: 6, b: 0, a: 255))
  let hDate = "06/16/2026"
  let hDateW = measureText(hDate, 18)
  drawText(hDate, sw - 20 - hDateW, 17, 18, Color(r: 10, g: 6, b: 0, a: 255))
  drawText("POST", 20, 17, 18, Color(r: 10, g: 6, b: 0, a: 255))
  drawRectangle(4, (4 + hH).int32, sw - 8, 2, Color(r: 220, g: 150, b: 30, a: 255))

  # POST lines print on the update clock; each probe's status resolves a beat
  # after its line, so the report reads as live checks instead of a done deal.
  let postAmber = Color(r: 255, g: 170, b: 20, a: 255)
  var yPos = 4 + hH + 16
  for i in 0..<splash.biosVisible:
    let line = splash.biosLines[i]
    if line.kind == blPlain and line.text.len == 0:
      yPos += 10
      continue
    case line.kind
    of blPlain:
      let col = if i == 0: Color(r: 255, g: 220, b: 80, a: 255) else: postAmber
      drawText(line.text, 20, yPos.int32, 18, col)
    of blCountdown:
      let secsLeft = max(0, int(ceil(BIOS_DUR - BIOS_OFF - splash.phaseTimer)))
      let txt = line.text & " " & $secsLeft &
                (if secsLeft == 1: " second..." else: " seconds...")
      drawText(txt, 20, yPos.int32, 18, Color(r: 200, g: 130, b: 15, a: 220))
    of blStatus, blRamCount:
      let sinceReveal = splash.phaseTimer - splash.biosRevealTime(i)
      let resolved = sinceReveal >= STATUS_LAG
      var body = line.text
      if line.kind == blRamCount and not resolved:
        # The classic memory-test count-up, racing to the detected total.
        let f = clamp01(sinceReveal / STATUS_LAG)
        body = "RAM  : " & $int(splash.ramMB.float32 * f) & " MB"
      # Pad the dotted leader by measured pixel width (the font is not
      # monospace), so every status lands in one aligned column.
      var padded = body & " "
      while measureText(padded, 18) < 452 and padded.len < 96: padded.add('.')
      drawText(padded, 20, yPos.int32, 18, postAmber)
      let statusX = 20 + max(measureText(padded, 18), 452) + 8
      if resolved:
        # Fresh statuses flash white for a beat, then settle green.
        let col =
          if sinceReveal - STATUS_LAG < 0.12'f32:
            Color(r: 245, g: 255, b: 245, a: 255)
          else:
            Color(r: 80, g: 255, b: 80, a: 255)
        drawText(line.status, statusX, yPos.int32, 18, col)
      else:
        # Probe spinner while the check is in flight.
        const spinner = ["|", "/", "-", "\\"]
        drawText(spinner[int(splash.timer * 12.0'f32) mod 4], statusX, yPos.int32, 18,
                 Color(r: 255, g: 210, b: 90, a: 230))
    yPos += 22

  # Blinking block cursor at the print head while the report is still printing.
  if splash.biosVisible < splash.biosLines.len and int(splash.timer * 3.0'f32) mod 2 == 0:
    drawRectangle(20, yPos.int32 + 2, 10, 15, postAmber)

  # Setup hints pinned to the bottom edge, where real firmware puts them.
  drawText("Press <DEL> to enter BIOS Setup  |  <F11> to select Boot Device",
           20, sh - 32, 18, Color(r: 215, g: 140, b: 20, a: 210))
  if splash.phaseTimer > 0.9'f32:
    let hint  = t(tkBiosFastBoot)
    let hintW = measureText(hint, 16)
    drawText(hint, sw - hintW - 20, sh - 30, 16,
             Color(r: 255, g: 200, b: 80,
                   a: alphaByte(140.0'f32 + sin(splash.timer * 4.0'f32) * 60.0'f32)))

  # Brand column on the right: a hero TOPHAT emblem above an etched version plate.
  # This is the protagonist of the BIOS screen and a cold-amber foreshadow of the
  # cyan kernel-with-tophat that headlines the next splash.
  let bFade  = clamp01(splash.phaseTimer * 4.0'f32)
  let bA     = alphaByte(bFade * 255.0'f32)
  let bW     = 240'i32
  let bH     = 138'i32
  let cx     = (sw.float32 * 0.74'f32).int32
  let pulse  = sin(splash.timer * 2.2'f32) * 0.5'f32 + 0.5'f32

  # Hero emblem: the amber firmware tophat, presented on a glowing pedestal.
  let heroIn = easeOut(clamp01(splash.phaseTimer * 2.2'f32))
  let heroR  = min(sw, sh).float32 * 0.092'f32 * (0.74'f32 + heroIn * 0.26'f32)
  let heroY  = (sh.float32 * 0.30'f32) - (1.0'f32 - heroIn) * 26.0'f32
  let amber  = Color(r: 255, g: 188, b: 56, a: 255)
  # Faint aura behind the dark crown so the silhouette reads against the panel.
  drawSoftGlow(cx.float32, heroY - heroR * 0.5'f32, heroR * (1.12'f32 + pulse * 0.1'f32),
               Color(r: 225, g: 135, b: 18, a: alphaByte(heroIn * (24.0'f32 + pulse * 8.0'f32))), 1.0'f32)
  # Stage pedestal: a bright base line under the brim grounds the emblem.
  drawRectangle((cx.float32 - heroR).int32, heroY.int32, (heroR * 2.0'f32).int32, 2,
                Color(r: 235, g: 170, b: 50, a: alphaByte(heroIn * 220.0'f32)))
  drawTopHat(newVector2f(cx.float32, heroY), heroR, splash.timer, heroIn, amber)

  let badgeX = cx - bW div 2
  let badgeY = (sh.float32 * 0.47'f32).int32

  # Amber bloom behind the plate so it reads as a lit element, not a flat decal.
  drawSoftGlow(cx.float32, (badgeY + bH div 2).float32, (bW.float32 * 0.78'f32),
               Color(r: 200, g: 120, b: 10, a: alphaByte(bFade * (40.0'f32 + pulse * 20.0'f32))), 1.3'f32)

  # Recessed panel: dark fill, then a top-down sheen so the plate looks beveled.
  drawRectangle(badgeX, badgeY, bW.int32, bH.int32,
                Color(r: 26, g: 16, b: 2, a: alphaByte(bFade * 244.0'f32)))
  drawRectangleGradientV(badgeX, badgeY, bW.int32, (bH div 2).int32,
                         Color(r: 90, g: 56, b: 8, a: alphaByte(bFade * 70.0'f32)),
                         Color(r: 26, g: 16, b: 2, a: 0))

  # Double bevel border: bright outer rule + a dimmer inset rule.
  drawRectangleLines(Rectangle(x: badgeX.float32, y: badgeY.float32,
                               width: bW.float32, height: bH.float32),
                     2.0'f32, Color(r: 235, g: 165, b: 40, a: bA))
  drawRectangleLines(Rectangle(x: badgeX.float32 + 6.0'f32, y: badgeY.float32 + 6.0'f32,
                               width: bW.float32 - 12.0'f32, height: bH.float32 - 12.0'f32),
                     1.0'f32, Color(r: 150, g: 95, b: 18, a: alphaByte(bFade * 180.0'f32)))

  # L-shaped registration ticks at each corner, like a socketed chip.
  let tk = 14
  for (ox, oy, dx, dy) in [(8, 8, 1, 1), (bW - 8, 8, -1, 1),
                           (8, bH - 8, 1, -1), (bW - 8, bH - 8, -1, -1)]:
    let px = badgeX + ox
    let py = badgeY + oy
    drawRectangle(px.int32, py.int32, (tk * dx).int32, 2,
                  Color(r: 255, g: 200, b: 70, a: bA))
    drawRectangle(px.int32, py.int32, 2, (tk * dy).int32,
                  Color(r: 255, g: 200, b: 70, a: bA))

  # Micro header so the plate reads as certified firmware, not just a version.
  let hdr  = "FIRMWARE REV"
  let hdrW = measureText(hdr, 12)
  drawText(hdr, cx - hdrW div 2, badgeY + 16, 12,
           Color(r: 210, g: 150, b: 40, a: alphaByte(bFade * 210.0'f32)))

  # The headline version, with a soft amber halo to lift it off the plate.
  drawSoftGlow(cx.float32, (badgeY + 62).float32, 46.0'f32,
               Color(r: 255, g: 190, b: 40, a: alphaByte(bFade * 70.0'f32)), 1.0'f32)
  let v6W = measureText("6.0", 56)
  drawText("6.0", cx - v6W div 2, badgeY + 32, 56,
           Color(r: 255, g: 224, b: 96, a: bA))

  # Divider rule with diamond end-caps separating version from edition tag.
  let lineY = badgeY + 98
  let halfW = 64
  drawRectangle((cx - halfW).int32, lineY.int32, (halfW * 2).int32, 1,
                Color(r: 180, g: 120, b: 30, a: alphaByte(bFade * 200.0'f32)))
  for sx in [-halfW, halfW]:
    drawPoly(Vector2(x: (cx + sx).float32, y: (lineY + 1).float32), 4, 3.0'f32, 45.0'f32,
             Color(r: 235, g: 170, b: 50, a: bA))

  let ed  = "EDITION"
  let edW = measureText(ed, 18)
  drawText(ed, cx - edW div 2, badgeY + 108, 18,
           Color(r: 215, g: 150, b: 30, a: bA))

  # Phosphor shimmer: the whole tube breathes slightly, like a warm CRT.
  let flick = sin(splash.timer * 11.0'f32) * 0.5'f32 + sin(splash.timer * 6.7'f32) * 0.5'f32
  drawRectangle(0, 0, sw, sh,
                Color(r: 255, g: 180, b: 60, a: alphaByte(4.0'f32 + flick * 3.0'f32)))

  # CRT power-on: the amber monitor warms up, opening from a centre line.
  let warm = clamp01(splash.phaseTimer / 0.32'f32)
  if warm < 1.0'f32:
    drawCRTAperture(sw, sh, easeOut(warm), Color(r: 255, g: 225, b: 130, a: 255))
    let flash = 1.0'f32 - warm
    drawRectangle(0, 0, sw, sh,
                  Color(r: 255, g: 235, b: 180, a: alphaByte(flash * flash * 120.0'f32)))

  # CRT power-off: collapse back to a bright line as the BIOS hands off to the
  # kernel reveal. The kernel phase re-opens from this same line (in cyan), so
  # the amber->cyan cut reads as one continuous monitor switch.
  let tLeft = BIOS_DUR - splash.phaseTimer
  if tLeft < BIOS_OFF:
    let cf = clamp01(1.0'f32 - tLeft / BIOS_OFF)
    drawCRTAperture(sw, sh, 1.0'f32 - easeInOut(cf),
                    Color(r: 255, g: 230, b: 150, a: 255))
    drawRectangle(0, 0, sw, sh,
                  Color(r: 255, g: 210, b: 140, a: alphaByte(cf * cf * 70.0'f32)))

proc drawSplashComplete(splash: SplashScreen, sw, sh: int32) =
  let cx = sw.float32 * 0.5'f32
  let cy = sh.float32 * 0.44'f32

  # Deep space background
  drawRectangle(0, 0, sw, sh, Color(r: 0, g: 1, b: 10, a: 255))

  # Large radial glow behind the kernel, the dominant light source
  drawSoftGlow(cx, cy, sh.float32 * 0.65'f32,
               Color(r: 0, g: 50, b: 110, a: 55), 1.6'f32)
  drawSoftGlow(cx, cy, sh.float32 * 0.30'f32,
               Color(r: 0, g: 120, b: 200, a: 35), 1.4'f32)

  # Starfield / drifting grid over the glow (transparent gradient so bg shows through)
  drawSharedBackdrop(sw, sh, splash.timer * 0.5'f32,
                     Color(r: 0, g: 0, b: 0, a: 0),
                     Color(r: 0, g: 0, b: 0, a: 0),
                     Color(r: 14, g: 34, b: 50, a: 20),
                     Color(r: 30, g: 100, b: 140, a: 38),
                     Color(r: 0, g: 200, b: 210, a: 28),
                     0.55'f32, 0.35'f32)

  # Vignette, darkens top and bottom edges
  drawRectangleGradientV(0, 0, sw, sh div 5,
                         Color(r: 0, g: 0, b: 0, a: 160),
                         Color(r: 0, g: 0, b: 0, a: 0))
  drawRectangleGradientV(0, sh - sh div 4, sw, sh div 4,
                         Color(r: 0, g: 0, b: 0, a: 0),
                         Color(r: 0, g: 0, b: 0, a: 200))

  # Kernel model materialising
  let kernelR = min(sw, sh).float32 * 0.12'f32
  drawKernelModel(newVector2f(cx, cy), kernelR, splash.timer, splash.kernelBoot, 1.0'f32)

  # Spark + shockwave as the tophat seats onto the kernel (the wake-up finale).
  # Keyed to kernelBoot, which is monotonic and freezes at 1.0, so this fires
  # exactly once during the reveal and never again once the scene settles.
  let seat = clamp01((splash.kernelBoot - 0.82'f32) / 0.16'f32)
  if seat > 0.0'f32 and seat < 1.0'f32:
    let s = sin(seat * PI)  # 0 -> 1 -> 0 bell over the seat window
    drawSoftGlow(cx, cy, kernelR * (1.6'f32 + s * 1.4'f32),
                 Color(r: 210, g: 255, b: 250, a: alphaByte(s * 95.0'f32)), 1.2'f32)
    let ringR = kernelR * (1.1'f32 + seat * 2.2'f32)
    drawRing(Vector2(x: cx, y: cy), ringR - 2.0'f32, ringR + 2.0'f32,
             0.0'f32, 360.0'f32, 48,
             Color(r: 180, g: 255, b: 250, a: alphaByte(s * 150.0'f32)))

  # Title fades in with the kernel
  let titleA = alphaByte(clamp01(splash.kernelBoot / 0.7'f32) * 230.0'f32)
  if titleA > 0:
    let tY = (cy + kernelR * 3.3'f32).int32
    drawSoftGlow(cx, tY.float32 + 16.0'f32, 100.0'f32,
                 Color(r: 0, g: 220, b: 210, a: 28), 1.0'f32)
    let mainLabel = "TopHat-ShooterOS"
    let mainW     = measureText(mainLabel, 34)
    drawText(mainLabel, sw div 2 - mainW div 2, tY, 34,
             Color(r: 0, g: 230, b: 220, a: titleA))
    let subLabel = "[ v6.0 Edition ]"
    let subW     = measureText(subLabel, 22)
    drawText(subLabel, sw div 2 - subW div 2, tY + 42, 22,
             Color(r: 180, g: 60, b: 255, a: titleA))

  # Blue spotlight at bottom + "press any key" centered on it
  if splash.kernelBoot >= 0.85'f32:
    let pkFade  = clamp01((splash.kernelBoot - 0.85'f32) / 0.15'f32)
    let pulse   = sin(splash.timer * 3.2'f32) * 0.5'f32 + 0.5'f32
    let lightY  = sh.float32 - 38.0'f32

    let pkA   = alphaByte(pkFade * (150.0'f32 + pulse * 100.0'f32))
    let pkStr = t(tkSystemPressAnyKey)
    let pkW   = measureText(pkStr, 20)
    drawText(pkStr, sw div 2 - pkW div 2, (lightY - 10.0'f32).int32, 20,
             Color(r: 255, g: 240, b: 100, a: pkA))

  drawSplashScanlines(sw, sh, splash.scanlineOffset, Color(r: 0, g: 20, b: 30, a: 10))

  # CRT power-on: the kernel scene opens from the same centre line the BIOS
  # collapsed to, but now in cyan, completing the monitor-switch bridge.
  let on = clamp01(splash.phaseTimer / 0.30'f32)
  if on < 1.0'f32:
    drawCRTAperture(sw, sh, easeOut(on), Color(r: 150, g: 240, b: 245, a: 255))
    let flash = 1.0'f32 - on
    drawRectangle(0, 0, sw, sh,
                  Color(r: 120, g: 230, b: 240, a: alphaByte(flash * flash * 90.0'f32)))

# ---------------------------------------------------------------------------
# Public API

proc newSplashScreen*(): SplashScreen =
  let (lines, ramMB) = buildBiosLines()  # detect real hardware once, at construction
  SplashScreen(
    phase: bpBIOS, timer: 0, phaseTimer: 0,
    complete: false,  # skip enabled only after the kernel reveal settles
    scanlineOffset: 0, kernelBoot: 0,
    biosLines: lines, ramMB: ramMB
  )

proc handOffToKernel(splash: SplashScreen) =
  splash.phase      = bpComplete
  splash.phaseTimer = 0
  playSound(stMenuSelect, 0.55'f32, 0.9'f32)  # boot handoff blip

proc fastForwardSplash*(splash: SplashScreen) =
  ## Any key during the boot fast-forwards it: skip the rest of the POST, then
  ## snap the kernel reveal to its settled (press-any-key) state.
  case splash.phase
  of bpBIOS:
    if splash.phaseTimer > 0.25'f32:  # ignore keypress residue from launch
      splash.handOffToKernel()
  of bpComplete:
    splash.phaseTimer = max(splash.phaseTimer, 1.5'f32 * 0.85'f32)

proc updateSplashScreen*(splash: SplashScreen, dt: float32) =
  splash.timer          += dt
  splash.scanlineOffset += dt * 90.0'f32
  splash.phaseTimer     += dt

  case splash.phase
  of bpBIOS:
    if not splash.poweredOn:
      splash.poweredOn = true
      playSound(stMenuSelect, 0.5'f32, 1.45'f32)  # POST beep as the CRT warms
    var vis = 0
    while vis < splash.biosLines.len and
          splash.phaseTimer >= splash.biosRevealTime(vis):
      inc vis
    if vis > splash.biosVisible:
      splash.biosVisible = vis
      if splash.biosLines[vis - 1].text.len > 0:
        playSound(stMenuNav, 0.18'f32, 1.5'f32)   # teletype tick per printed line
    if splash.phaseTimer >= BIOS_DUR:
      splash.handOffToKernel()

  of bpComplete:
    splash.kernelBoot = min(splash.phaseTimer / 1.5'f32, 1.0'f32)
    if not splash.seatSparked and splash.kernelBoot >= 0.82'f32:
      splash.seatSparked = true
      playSound(stPowerUp, 0.5'f32)  # tophat seats onto the kernel
    if splash.kernelBoot >= 0.85'f32:
      splash.complete = true  # enable skip only once "press any key" is visible

proc drawSplashScreen*(splash: SplashScreen, screenWidth, screenHeight: int) =
  let sw = screenWidth.int32
  let sh = screenHeight.int32
  case splash.phase
  of bpBIOS:     drawSplashBIOS(splash, sw, sh)
  of bpComplete: drawSplashComplete(splash, sw, sh)
