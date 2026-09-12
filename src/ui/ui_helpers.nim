## Shared text-layout helpers and small shared glyphs for the OS-style UI.
## Near-leaf module: imports only raylib plus localization and types, neither of
## which knows anything about ui/, so it is safe to use from any ui/ module.

import raylib, strutils, math
import ../localization, ../types

type TextAlign* = enum
  taLeft, taCenter, taRight

proc bestFitFontSize*(text: string, maxWidth, preferredSize: int32,
                      minSize: int32 = 9): int32 =
  ## Shrink from preferredSize until `text` fits in `maxWidth` (or minSize).
  result = preferredSize
  if maxWidth <= 0:
    return
  while result > minSize and measureText(text, result) > maxWidth:
    dec result

proc drawTextFit*(text: string, x, y, maxWidth, fontSize: int32, color: Color,
                  minSize: int32 = 9, align: TextAlign = taLeft): int32 {.discardable.} =
  ## Draw `text` at the largest size that fits `maxWidth`; returns the size used.
  result = bestFitFontSize(text, maxWidth, fontSize, minSize)
  let textW = measureText(text, result)
  let drawX = case align
    of taLeft: x
    of taCenter: x + max(0'i32, (maxWidth - textW) div 2)
    of taRight: x + max(0'i32, maxWidth - textW)
  drawText(text, drawX, y, result, color)

proc drawCenteredTextFit*(text: string, x, y, maxWidth, fontSize: int32, color: Color,
                          minSize: int32 = 9): int32 {.discardable.} =
  drawTextFit(text, x, y, maxWidth, fontSize, color, minSize, taCenter)

proc wrapTextLines*(text: string, maxWidth, fontSize: int32): seq[string] =
  ## Greedy word-wrap to lines no wider than `maxWidth` at `fontSize`.
  let words = text.splitWhitespace()
  if words.len == 0:
    return @[]

  var currentLine = ""
  for word in words:
    let candidate = if currentLine.len == 0: word else: currentLine & " " & word
    if currentLine.len == 0 or measureText(candidate, fontSize) <= maxWidth:
      currentLine = candidate
    else:
      result.add(currentLine)
      currentLine = word

  if currentLine.len > 0:
    result.add(currentLine)

proc bestWrapFontSize*(text: string, maxWidth, preferredSize: int32,
                       maxLines: int, minSize: int32 = 9): int32 =
  ## Largest size at which the wrapped text needs at most `maxLines` lines.
  result = preferredSize
  if maxWidth <= 0:
    return
  while result > minSize:
    if wrapTextLines(text, maxWidth, result).len <= maxLines:
      return
    dec result

# ---------------------------------------------------------------------------
# Restore-point glyph.
#
# The wave-mode lives budget (difficultyMaxLives in types.nim) is shown to the
# player as RESTORE POINTS rather than lives, because that is literally what one
# is in this fiction: pressing "Continue (Wave 21)" restores a saved system
# state off disk (run_checkpoint.json), and spending one burns that save.
#
# The glyph is a save-state platter -- disc, recessed face, spindle hub and a
# write LED -- drawn in the shadow / body / bright-core layering that
# drawCurrencyIcon uses for credits and cores, so it reads as one more piece of
# the OS iconography instead of an imported symbol.
#
# Callers pass the budget in rather than this module reading currentDifficulty,
# so the same row can be rendered for any tier.
# ---------------------------------------------------------------------------

const
  IconGap = 10'i32       ## px between adjacent glyphs
  IconLabelGap = 12'i32  ## px between the label and the first glyph
  SectorTicks = 6        ## marks around the platter rim; the part that spins

proc iconAdvance(size: float32): int32 =
  ## Horizontal step from one glyph's center to the next.
  int32(size * 2.0) + IconGap

proc shade(c: Color, f: float32): Color =
  ## Scale a colour's brightness, keeping its alpha.
  Color(r: uint8(clamp(c.r.float32 * f, 0.0, 255.0)),
        g: uint8(clamp(c.g.float32 * f, 0.0, 255.0)),
        b: uint8(clamp(c.b.float32 * f, 0.0, 255.0)), a: c.a)

proc drawRestorePointIcon*(cx, cy, size: float32, body, accent, led: Color,
                           spin: float32 = 0.0) =
  ## One restore point. `size` is the radius, so the glyph spans 2*size.
  ## `spin` rotates the rim ticks: static in the meters, spinning down to a stop
  ## in the loss animation, which is what makes a dying platter read as dying.
  let ctr = Vector2(x: cx, y: cy)

  # Drop shadow, skipped once the glyph is fading or it muddies the fade.
  if body.a > 200:
    drawCircle(Vector2(x: cx + 1.0, y: cy + 2.0), size, Color(r: 0, g: 0, b: 0, a: 90))

  # Disc body + rim.
  drawCircle(ctr, size, body)
  drawCircleLines(int32(cx), int32(cy), size, accent)

  # Recessed platter face: a darker inset so the rim reads as a raised edge.
  drawCircle(ctr, size * 0.66, shade(body, 0.62))

  # Rim sector ticks.
  for i in 0 ..< SectorTicks:
    let a = spin + (PI * 2.0) * i.float32 / SectorTicks.float32
    drawLine(Vector2(x: cx + cos(a) * size * 0.70, y: cy + sin(a) * size * 0.70),
             Vector2(x: cx + cos(a) * size * 0.93, y: cy + sin(a) * size * 0.93),
             max(1.0'f32, size * 0.09), accent)

  # Spindle hub.
  drawCircle(ctr, size * 0.30, accent)
  drawCircle(ctr, size * 0.12, shade(body, 0.35))

  # Write LED on the housing, fixed at the upper right (it does not spin).
  let lx = cx + size * 0.78 * cos(-0.85'f32)
  let ly = cy + size * 0.78 * sin(-0.85'f32)
  if led.a > 0:
    drawCircle(Vector2(x: lx, y: ly), size * 0.20, shade(led, 0.45))
    drawCircle(Vector2(x: lx, y: ly), size * 0.13, led)

# ---------------------------------------------------------------------------
# Restore-point meter.
#
# A framed, captioned strip that reads as a system resource readout rather than
# one more diagnostics line. All three screens that show the budget (death,
# victory, pause) use it, so it looks the same wherever the player checks it,
# and the frame goes red once it is spent.
# ---------------------------------------------------------------------------

const
  LivesPanelHeight* = 46'i32  ## default panel height; glyphs are sized from it
  PanelIconSize = 15.0'f32    ## radius of a glyph inside the panel
  PanelFontSize = 16'i32

  # Palette. Cyan-steel for a live save, dead grey for a spent one, amber for
  # the last one standing -- the same escalation the panel border uses.
  RpBody     = Color(r: 30, g: 104, b: 152, a: 255)
  RpAccent   = Color(r: 96, g: 226, b: 255, a: 255)
  RpLed      = Color(r: 130, g: 255, b: 190, a: 255)
  RpLowBody  = Color(r: 150, g: 96, b: 24, a: 255)
  RpLowAccent = Color(r: 255, g: 196, b: 92, a: 255)
  RpLowLed   = Color(r: 255, g: 220, b: 120, a: 255)
  RpDeadBody = Color(r: 38, g: 44, b: 55, a: 255)
  RpDeadAccent = Color(r: 78, g: 88, b: 102, a: 255)
  RpDeadLed  = Color(r: 70, g: 34, b: 40, a: 255)

proc livesStatusText(used, maxLives, unlimitedSentinel: int): string =
  ## Trailing word for the meter: only the states worth calling out get one, so
  ## a healthy budget is just glyphs.
  if maxLives == unlimitedSentinel: t(tkRestorePointsUnlimited)
  elif maxLives <= 0: t(tkRestorePointsNone)
  else:
    let remaining = max(0, maxLives - used)
    if remaining == 0: t(tkRestorePointsNone)
    elif remaining == 1: t(tkRestorePointsLast)
    else: ""

proc drawLivesPanel*(x, y, width: int32, used, maxLives, unlimitedSentinel: int,
                     time: float32, height: int32 = LivesPanelHeight) =
  ## Framed restore-point meter. Contents are centered as one group so the panel
  ## reads the same at any width.
  let remaining = if maxLives == unlimitedSentinel: unlimitedSentinel
                  else: max(0, maxLives - used)
  let critical = remaining == 0
  let low = remaining == 1

  # The border pulses while the budget is critical or down to its last save --
  # the two states the player needs to notice without reading.
  let pulse = sin(time * 4.0) * 0.25 + 0.75
  let bg = if critical: Color(r: 46, g: 16, b: 20, a: 255)
           else: Color(r: 22, g: 40, b: 66, a: 255)
  let border = if critical or low:
      Color(r: uint8(255.0 * pulse), g: uint8(70.0 * pulse), b: uint8(80.0 * pulse), a: 255)
    else:
      Color(r: 70, g: 115, b: 175, a: 255)
  drawRectangle(x, y, width, height, bg)
  drawRectangleLines(Rectangle(x: x.float32, y: y.float32,
                               width: width.float32, height: height.float32),
                     2.0, border)
  # Left accent bar, so the strip is identifiable from the corner of the eye.
  drawRectangle(x, y, 4'i32, height,
                if critical: Color(r: 190, g: 40, b: 55, a: 255) else: RpAccent)

  # Centered group: RESTORE POINTS  <glyphs>  [status]
  let label = t(tkRestorePointsLabel)
  let status = livesStatusText(used, maxLives, unlimitedSentinel)
  let labelW = measureText(label, PanelFontSize)
  let glyphsW =
    if maxLives == unlimitedSentinel: int32(PanelIconSize * 2.0)
    elif maxLives <= 0: 0'i32
    else: iconAdvance(PanelIconSize) * int32(maxLives) - IconGap
  let statusW = if status.len > 0: measureText(status, PanelFontSize) else: 0'i32
  var groupW = labelW + IconLabelGap + glyphsW
  if statusW > 0:
    groupW += IconLabelGap + statusW

  var cursor = x + (width - groupW) div 2
  let cy = y.float32 + height.float32 * 0.5
  drawText(label, cursor, int32(cy) - PanelFontSize div 2, PanelFontSize,
           Color(r: 190, g: 202, b: 216, a: 255))
  cursor += labelW + IconLabelGap

  if maxLives == unlimitedSentinel:
    drawRestorePointIcon(cursor.float32 + PanelIconSize, cy, PanelIconSize,
                         RpBody, RpAccent, RpLed)
    cursor += iconAdvance(PanelIconSize)
  elif maxLives > 0:
    for i in 0 ..< maxLives:
      let gx = cursor.float32 + PanelIconSize
      if i < remaining:
        # The last save breathes, so "one mistake left" needs no reading.
        if low:
          drawRestorePointIcon(gx, cy, PanelIconSize, RpLowBody, RpLowAccent,
                               shade(RpLowLed, pulse))
        else:
          drawRestorePointIcon(gx, cy, PanelIconSize, RpBody, RpAccent, RpLed)
      else:
        drawRestorePointIcon(gx, cy, PanelIconSize, RpDeadBody, RpDeadAccent, RpDeadLed)
      cursor += iconAdvance(PanelIconSize)
    cursor -= IconGap

  if statusW > 0:
    cursor += IconLabelGap
    drawText(status, cursor, int32(cy) - PanelFontSize div 2, PanelFontSize,
             if critical or low: Color(r: 255, g: 120, b: 120, a: 255)
             else: Color(r: 120, g: 235, b: 160, a: 255))

# ---------------------------------------------------------------------------
# "Restore point spent" animation.
#
# Played full-screen over the reorientation countdown when a run resumes from
# its block checkpoint, i.e. at the exact moment a restore point is consumed.
# The platter spins down, its write LED dies, the surface fractures and the
# save scatters as data shards -- so the cost is something the player watches
# happen rather than a number that quietly moved.
#
# Everything here is a pure function of `progress` (0 -> 1 across
# LifeLostAnimDuration): no per-frame state and no rand, so the animation is
# identical every time and a preview harness can scrub it frame by frame.
# ---------------------------------------------------------------------------

const
  BigIconSize = 36.0'f32  ## radius of the glyphs in the overlay
  BigIconGap = 26.0'f32
  FragmentCount = 16
  SpinRate = 7.0'f32      ## radians/unit-progress while the platter is alive
  FocusZoom = 1.7'f32     ## how much closer the camera holds before pulling back

proc withAlphaF(c: Color, mult: float32): Color =
  Color(r: c.r, g: c.g, b: c.b, a: uint8(clamp(c.a.float32 * mult, 0.0, 255.0)))

proc easeOutBack(t: float32): float32 =
  ## Overshoot-and-settle, used for the entrance slam and the unlimited re-form.
  let u = t - 1.0
  1.0 + u * u * (2.70158'f32 * u + 1.70158'f32)

proc phaseT(progress, startP, endP: float32): float32 =
  ## Progress within one phase, clamped to 0..1 outside it.
  if endP <= startP: return 0.0
  clamp((progress - startP) / (endP - startP), 0.0'f32, 1.0'f32)

proc drawShard(px, py, size, rot: float32, color: Color) =
  ## One piece of the scattered save: a small triangle, drawn both windings past
  ## raylib's back-face cull, echoing the data-shard currency icon.
  var pts: array[3, Vector2]
  for k in 0 .. 2:
    let ang = rot + (PI * 2.0) * k.float32 / 3.0
    pts[k] = Vector2(x: px + cos(ang) * size, y: py + sin(ang) * size)
  drawTriangle(pts[0], pts[1], pts[2], color)
  drawTriangle(pts[0], pts[2], pts[1], color)

proc drawFracture(cx, cy, size, reveal, jitter, alpha: float32) =
  ## Jagged fault creeping across the platter. The zigzag is a fixed table
  ## rather than rand() so the fracture is the same shape every run.
  const jit = [0.0'f32, 0.30'f32, -0.26'f32, 0.34'f32, -0.30'f32, 0.22'f32,
               -0.12'f32, 0.0'f32]
  let x0 = cx - size * 0.86
  let y0 = cy - size * 0.52
  let dx = (cx + size * 0.80) - x0
  let dy = (cy + size * 0.58) - y0
  # Unit normal to the fault, so the zigzag runs across its travel.
  let length = max(0.001'f32, sqrt(dx * dx + dy * dy))
  let nx = -dy / length
  let ny = dx / length

  let segs = jit.len - 1
  let shown = reveal * segs.float32
  for i in 0 ..< segs:
    if shown <= i.float32: break
    let tA = i.float32 / segs.float32
    let tB = tA + min(1.0'f32, shown - i.float32) / segs.float32
    let ax = x0 + dx * tA + nx * jit[i] * size + jitter
    let ay = y0 + dy * tA + ny * jit[i] * size
    let bx = x0 + dx * tB + nx * jit[i + 1] * size + jitter
    let by = y0 + dy * tB + ny * jit[i + 1] * size
    drawLine(Vector2(x: ax, y: ay), Vector2(x: bx, y: by), 3.0,
             Color(r: 8, g: 12, b: 18, a: uint8(235.0 * alpha)))
    drawLine(Vector2(x: ax, y: ay - 1.0), Vector2(x: bx, y: by - 1.0), 1.0,
             Color(r: 200, g: 245, b: 255, a: uint8(160.0 * alpha)))
proc smoothStep(t: float32): float32 =
  ## Ease in and out, for the camera pull-back.
  let u = clamp(t, 0.0'f32, 1.0'f32)
  u * u * (3.0 - 2.0 * u)

proc drawLifeLostOverlay*(screenW, screenH: int32, used, maxLives,
                          unlimitedSentinel: int, progress: float32) =
  ## Full-screen "you just spent a restore point" sequence. `used` is the count
  ## AFTER the spend, so the platter that dies is the one at index `remaining`.
  ##
  ## Staging: the sequence opens held ON the platter being consumed, alone and
  ## enlarged at screen centre, so the spin-down and the break happen where the
  ## eye already is. Only once it is dead does the camera pull back, sliding
  ## that platter into its slot while the rest of the row fades in around it --
  ## which is what turns "a disc broke" into "and here is what you have left".
  let p = clamp(progress, 0.0'f32, 1.0'f32)
  let unlimited = maxLives == unlimitedSentinel
  let remaining = if unlimited: 1 else: max(0, maxLives - used)
  let slots = if unlimited: 1 else: max(1, maxLives)
  let target = if unlimited: 0 else: min(remaining, slots - 1)

  # Global fade: in over the entrance, out at the tail.
  let alpha = min(phaseT(p, 0.0, LifeLostCrackStart * 0.6),
                  1.0 - phaseT(p, LifeLostFadeStart, 1.0))

  drawRectangle(0, 0, screenW, screenH,
                Color(r: 0, g: 0, b: 0, a: uint8(205.0 * alpha)))

  let cx = screenW.float32 * 0.5
  let cy = screenH.float32 * 0.5

  # Entrance slam: the platter arrives oversized and settles.
  let entrance = phaseT(p, 0.0, LifeLostCrackStart)
  let slam = if entrance >= 1.0: 1.0'f32
             else: 1.0 + (1.0 - easeOutBack(entrance)) * 0.55

  # Camera pull-back. 0 = held on the dead platter, 1 = the full row of slots.
  let reveal = smoothStep(phaseT(p, LifeLostSettleStart, LifeLostRevealEnd))
  let zoom = (FocusZoom + (1.0 - FocusZoom) * reveal) * slam
  let size = BigIconSize * zoom

  # Row geometry at the final scale, and where the target sits inside it.
  let advance = (BigIconSize * 2.0 + BigIconGap) * zoom
  let rowW = advance * slots.float32 - BigIconGap * zoom
  let targetRowX = cx - rowW * 0.5 + size + advance * target.float32
  # The target slides from screen centre to its slot as the camera pulls back.
  let targetX = cx + (targetRowX - cx) * reveal
  # Siblings only exist once the row is being revealed.
  let siblingAlpha = alpha * reveal

  let crackT = phaseT(p, LifeLostCrackStart, LifeLostShatterStart)
  let shatterT = phaseT(p, LifeLostShatterStart, LifeLostSettleStart)
  let reformT = phaseT(p, LifeLostSettleStart, LifeLostRevealEnd)

  # Title, auto-fitted: the Spanish string is a good deal longer than the
  # English one and would otherwise run off a narrow screen. It sits further out
  # while the camera is close, so the enlarged platter never crowds it.
  let title = t(tkRestorePointLost)
  let titleSize = bestFitFontSize(title, screenW - 80'i32, int32(44.0 * slam), 18'i32)
  let titleW = measureText(title, titleSize)
  let titleY = cy - (128.0 + 46.0 * (1.0 - reveal)) * slam
  drawText(title, int32(cx) - titleW div 2, int32(titleY), titleSize,
           Color(r: 255, g: 120, b: 110, a: uint8(255.0 * alpha)))

  # --- siblings (drawn first, so shards from the break pass over them) ---
  if siblingAlpha > 0.0:
    for i in 0 ..< slots:
      if i == target: continue
      let gx = targetX + (i - target).float32 * advance
      let live = i < remaining
      drawRestorePointIcon(gx, cy, size,
                           withAlphaF(if live: RpBody else: RpDeadBody, siblingAlpha),
                           withAlphaF(if live: RpAccent else: RpDeadAccent, siblingAlpha),
                           withAlphaF(if live: RpLed else: RpDeadLed, siblingAlpha),
                           if live: p * SpinRate else: 0.0)

  # --- the restore point being consumed ---
  if shatterT <= 0.0:
    # Spinning down: the platter slows to a halt, the surface goes cold and the
    # write LED gutters out as the fracture creeps across it.
    let decel = 1.0 - crackT * crackT
    let shudder = sin(p * 120.0) * 3.0 * crackT
    let ledFlicker = if crackT > 0.35: abs(sin(p * 45.0)) * (1.0 - crackT) else: 1.0
    drawRestorePointIcon(targetX + shudder, cy, size,
                         withAlphaF(shade(RpBody, 1.0 - 0.55 * crackT), alpha),
                         withAlphaF(shade(RpAccent, 1.0 - 0.5 * crackT), alpha),
                         withAlphaF(RpLed, alpha * ledFlicker * (1.0 - crackT)),
                         p * SpinRate * decel)
    if crackT > 0.0:
      drawFracture(targetX, cy, size, crackT, shudder, alpha)
  else:
    # Gone: the dead socket stays put, and rides the pull-back into its slot.
    drawRestorePointIcon(targetX, cy, size, withAlphaF(RpDeadBody, alpha),
                         withAlphaF(RpDeadAccent, alpha),
                         withAlphaF(RpDeadLed, alpha))

    if shatterT < 1.0:
      # Read-failure ring: marks the instant the platter gave way. Capped just
      # outside the platter -- held this close to it, a wider ring sweeps up
      # through the title.
      if shatterT < 0.55:
        let rt = shatterT / 0.55
        drawCircleLines(int32(targetX), int32(cy), size * (0.6 + rt * 1.9),
                        withAlphaF(RpAccent, alpha * (1.0 - rt)))
      # The save scatters. Alpha falls off quadratically so the shards stay
      # solid through most of the arc and only thin out at the very end.
      for f in 0 ..< FragmentCount:
        let ang = (PI * 2.0) * (f.float32 / FragmentCount.float32) +
                  (f mod 3).float32 * 0.37
        let dist = (120.0 + ((f * 37) mod 110).float32) * shatterT * zoom
        let fx = targetX + cos(ang) * dist
        let fy = cy + sin(ang) * dist + 260.0 * shatterT * shatterT * zoom
        drawShard(fx, fy, size * 0.28 * (1.0 - shatterT * 0.45),
                  ang + shatterT * 7.0,
                  withAlphaF(RpAccent, alpha * (1.0 - shatterT * shatterT)))

    # Unlimited never really spends one: the save rebuilds itself.
    if unlimited and reformT > 0.0:
      drawRestorePointIcon(targetX, cy, size * clamp(easeOutBack(reformT), 0.0'f32, 1.4'f32),
                           withAlphaF(RpBody, alpha * reformT),
                           withAlphaF(RpAccent, alpha * reformT),
                           withAlphaF(RpLed, alpha * reformT),
                           reformT * SpinRate)

  # Impact flash on the break.
  if shatterT > 0.0 and shatterT < 0.22:
    let f = 1.0 - shatterT / 0.22
    drawRectangle(0, 0, screenW, screenH,
                  Color(r: 205, g: 240, b: 255, a: uint8(135.0 * f * alpha)))

  # Status readout, held until the row has actually arrived so it describes what
  # is on screen rather than pre-empting it.
  if p >= LifeLostRevealEnd:
    let status = livesStatusText(used, maxLives, unlimitedSentinel)
    if status.len > 0:
      let statusW = measureText(status, 30)
      let sa = alpha * phaseT(p, LifeLostRevealEnd, LifeLostRevealEnd + 0.06)
      let col = if unlimited: Color(r: 120, g: 235, b: 160, a: uint8(255.0 * sa))
                else: Color(r: 255, g: 120, b: 120, a: uint8(255.0 * sa))
      drawText(status, int32(cx) - statusW div 2, int32(cy + 112.0), 30, col)
