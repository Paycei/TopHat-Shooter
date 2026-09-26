## Drawing for the Survival / Roguelite rosters: the new enemies, the new boss
## bodies (13-15, 17-22; the Omega kits wear boss 12's body) and every
## awtEnemyDashLane..awtLastKnownGood warning. enemy.nim delegates here.
##
## Two passes per warning, like the wave bosses' signatures:
##   drawModeWarningTelegraph - the hint-gated wind-up cue (showHints)
##   drawModeWarningActive    - ungated: anything that can hurt, and every tell
##                              the mechanic itself depends on, is always drawn
## Everything is procedural (no image assets), in the house style: soft glow,
## solid body, dark rim, bright accent.

import raylib, math, strutils
import particle_types, types, utils, localization, mode_hazards

proc a8(v: float32): uint8 {.inline.} = clampByteF(v)

proc lighter(c: Color, amt: int): Color =
  Color(r: uint8(min(255, c.r.int + amt)), g: uint8(min(255, c.g.int + amt)),
        b: uint8(min(255, c.b.int + amt)), a: c.a)

proc darker(c: Color, divisor: int): Color =
  Color(r: uint8(c.r.int div divisor), g: uint8(c.g.int div divisor),
        b: uint8(c.b.int div divisor), a: c.a)

proc v2(x, y: float32): Vector2 {.inline.} = Vector2(x: x, y: y)

proc polyLines(cx, cy: float32, sides: int, radius, rot, thick: float32, col: Color) =
  for i in 0 ..< sides:
    let a0 = rot + i.float32 * (PI * 2.0 / sides.float32)
    let a1 = rot + (i + 1).float32 * (PI * 2.0 / sides.float32)
    drawLine(v2(cx + cos(a0) * radius, cy + sin(a0) * radius),
             v2(cx + cos(a1) * radius, cy + sin(a1) * radius), thick, col)

proc tri(a, b, c: Vector2, col: Color) =
  ## raylib culls clockwise triangles: draw both windings.
  drawTriangle(a, b, c, col)
  drawTriangle(a, c, b, col)

proc dashedLine(a, b: Vector2f, dash, gap, thick: float32, col: Color, phase = 0.0'f32) =
  let d = b - a
  let len = d.length()
  if len < 0.5'f32: return
  let u = d * (1.0'f32 / len)
  var s = -(phase mod (dash + gap))
  while s < len:
    let s0 = max(0.0'f32, s)
    let s1 = min(len, s + dash)
    if s1 > s0:
      drawLine(v2(a.x + u.x * s0, a.y + u.y * s0), v2(a.x + u.x * s1, a.y + u.y * s1), thick, col)
    s += dash + gap

proc centeredText(text: string, x, y: float32, size: int32, col: Color) =
  let w = measureText(text, size)
  drawText(text, int32(x) - w div 2, int32(y), size, col)

# ---------------------------------------------------------------------------
# Enemies

proc drawModeEnemy*(enemy: Enemy) =
  let t = getTime().float32
  let cx = enemy.pos.x
  let cy = enemy.pos.y
  let r = enemy.radius
  let col = enemy.color
  let pulse = sin(t * 3.0'f32 + enemy.id.float32 * 0.7'f32) * 0.5'f32 + 0.5'f32
  let velLen = enemy.vel.length()
  let heading = if velLen > 1.0'f32: arctan2(enemy.vel.y, enemy.vel.x) else: enemy.rotation

  # Hasted by a Priority Daemon / Dispatcher: violet speed chevrons trail it.
  if enemy.hasteTimer > 0.0'f32:
    for k in 1..2:
      let back = newVector2f(cx, cy) - newVector2f(cos(heading), sin(heading)) * (r + k.float32 * 6.0'f32)
      let side = newVector2f(-sin(heading), cos(heading)) * (r * 0.6'f32)
      let tip = back + newVector2f(cos(heading), sin(heading)) * 4.0'f32
      let chev = Color(r: 210, g: 110, b: 255, a: a8(200.0 - k.float32 * 60.0))
      drawLine(v2(back.x + side.x, back.y + side.y), v2(tip.x, tip.y), 2.0, chev)
      drawLine(v2(back.x - side.x, back.y - side.y), v2(tip.x, tip.y), 2.0, chev)

  case enemy.enemyType
  of etThread:
    if enemy.generation > 0 and (enemy.ballisticVel.x != 0 or enemy.ballisticVel.y != 0):
      # Fork seed: a charged orb that visibly swells toward its split.
      let charge = clamp(1.0'f32 - enemy.modeTimer / 0.9'f32, 0.0'f32, 1.0'f32)
      drawCircle(v2(cx, cy), r + 6.0'f32 + charge * 6.0'f32, withAlpha(col, a8(40.0 + charge * 60.0)))
      drawCircle(v2(cx, cy), r + 1.0'f32, col)
      drawCircleLines(cx.int32, cy.int32, r + 3.0'f32 + charge * 4.0'f32, withAlpha(White, a8(120.0 + charge * 120.0)))
      drawLine(v2(cx - r * 0.5'f32, cy), v2(cx + r * 0.5'f32, cy), 2.0, White)
      return
    # A bright head dragging a thin filament along its heading.
    let dir = newVector2f(cos(heading), sin(heading))
    let tail = newVector2f(cx, cy) - dir * (r * 2.6'f32)
    drawLine(v2(tail.x, tail.y), v2(cx, cy), 2.0, withAlpha(col, 110))
    drawCircle(v2(cx, cy), r + 3.0'f32 + pulse * 2.0'f32, withAlpha(col, 45))
    drawCircle(v2(cx, cy), r * 0.8'f32, col)
    drawCircleLines(cx.int32, cy.int32, r * 0.8'f32, darker(col, 3))
    drawCircle(v2(cx + dir.x * r * 0.3'f32, cy + dir.y * r * 0.3'f32), r * 0.28'f32, White)

  of etForkBomb:
    let charging = enemy.modeTimer > ForkBombSelfForkTime - ForkBombChargeLead and
                   not enemy.spawnedByBoss and enemy.generation < ForkBombMaxCopies
    let jitter = if charging: sin(t * 40.0'f32) * 1.5'f32 else: 0.0'f32
    let bx = cx + jitter
    drawCircle(v2(bx, cy), r + 5.0'f32 + pulse * 3.0'f32, withAlpha(col, 40))
    drawCircle(v2(bx, cy), r, col)
    drawCircleLines(bx.int32, cy.int32, r, darker(col, 3))
    # The fork glyph: a Y splitting in two.
    let stem = v2(bx, cy + r * 0.45'f32)
    let joint = v2(bx, cy)
    drawLine(stem, joint, 2.5, White)
    drawLine(joint, v2(bx - r * 0.45'f32, cy - r * 0.45'f32), 2.5, White)
    drawLine(joint, v2(bx + r * 0.45'f32, cy - r * 0.45'f32), 2.5, White)
    # Fuse
    drawLine(v2(bx + r * 0.6'f32, cy - r * 0.7'f32), v2(bx + r * 0.95'f32, cy - r * 1.15'f32), 2.0, Gray)
    drawCircle(v2(bx + r * 0.95'f32, cy - r * 1.15'f32), 2.5'f32 + pulse * 1.5'f32,
               Color(r: 255, g: 220, b: 90, a: 255))
    if charging:
      let k = (enemy.modeTimer - (ForkBombSelfForkTime - ForkBombChargeLead)) / ForkBombChargeLead
      drawLine(v2(bx, cy - r), v2(bx, cy + r), 2.0, withAlpha(White, a8(120.0 + 120.0 * k)))
      drawCircleLines(bx.int32, cy.int32, r + 4.0'f32 + 8.0'f32 * k, withAlpha(White, a8(200.0 * k)))
    if enemy.linkId > 0:
      # Forkmother's child: a pink process-tree node ring.
      drawCircleLines(bx.int32, cy.int32, r + 7.0'f32, Color(r: 255, g: 90, b: 170, a: 220))
      drawCircleLines(bx.int32, cy.int32, r + 9.0'f32, Color(r: 255, g: 160, b: 210, a: a8(90.0 + pulse * 100.0)))

  of etWatchdog:
    let aim = heading
    drawCircle(v2(cx, cy), r + 5.0'f32, withAlpha(col, 35))
    drawPoly(v2(cx, cy), 4, r, 45.0'f32, col)
    drawPolyLines(v2(cx, cy), 4, r, 45.0'f32, darker(col, 3))
    # Ears
    for s in [-1.0'f32, 1.0'f32]:
      let ea = aim + PI + s * 0.7'f32
      tri(v2(cx + cos(ea) * r * 0.6'f32, cy + sin(ea) * r * 0.6'f32),
          v2(cx + cos(ea + 0.35'f32) * r * 1.35'f32, cy + sin(ea + 0.35'f32) * r * 1.35'f32),
          v2(cx + cos(ea - 0.35'f32) * r * 1.35'f32, cy + sin(ea - 0.35'f32) * r * 1.35'f32),
          darker(col, 2))
    # The eye tracks where it last moved / aims.
    let eye = v2(cx + cos(aim) * r * 0.35'f32, cy + sin(aim) * r * 0.35'f32)
    drawCircle(eye, r * 0.3'f32, White)
    drawCircle(eye, r * 0.14'f32, Color(r: 30, g: 20, b: 10, a: 255))

  of etZombie:
    let revived = enemy.generation >= 1
    let body = if revived: darker(col, 2) else: col
    drawCircle(v2(cx, cy), r + 4.0'f32, withAlpha(col, 30))
    drawRectangle(Rectangle(x: cx - r, y: cy - r * 0.9'f32, width: r * 2, height: r * 1.8'f32), body)
    drawRectangleLines(Rectangle(x: cx - r, y: cy - r * 0.9'f32, width: r * 2, height: r * 1.8'f32), 2, darker(col, 3))
    # X eyes (it is a defunct process)
    for ex in [-0.4'f32, 0.4'f32]:
      let px = cx + ex * r
      let py = cy - r * 0.2'f32
      drawLine(v2(px - 3, py - 3), v2(px + 3, py + 3), 2.0, Color(r: 30, g: 40, b: 25, a: 255))
      drawLine(v2(px - 3, py + 3), v2(px + 3, py - 3), 2.0, Color(r: 30, g: 40, b: 25, a: 255))
    drawLine(v2(cx - r * 0.5'f32, cy + r * 0.4'f32), v2(cx + r * 0.5'f32, cy + r * 0.4'f32), 2.0,
             Color(r: 30, g: 40, b: 25, a: 255))
    if revived:
      # Stitches across the body
      for k in -1..1:
        let sx = cx + k.float32 * r * 0.5'f32
        drawLine(v2(sx - 2, cy + r * 0.1'f32), v2(sx + 2, cy + r * 0.7'f32), 1.5,
                 Color(r: 230, g: 220, b: 200, a: 200))

  of etDeadlock:
    # A padlock: shackle arc over a solid body.
    drawCircle(v2(cx, cy), r + 5.0'f32 + pulse * 2.0'f32, withAlpha(col, 40))
    drawRing(v2(cx, cy - r * 0.35'f32), r * 0.45'f32, r * 0.65'f32, 180.0, 360.0, 16, lighter(col, 40))
    drawRectangle(Rectangle(x: cx - r * 0.8'f32, y: cy - r * 0.35'f32, width: r * 1.6'f32, height: r * 1.2'f32), col)
    drawRectangleLines(Rectangle(x: cx - r * 0.8'f32, y: cy - r * 0.35'f32, width: r * 1.6'f32, height: r * 1.2'f32), 2, darker(col, 3))
    drawCircle(v2(cx, cy + r * 0.2'f32), r * 0.18'f32, darker(col, 4))

  of etDaemon:
    # Aura it lends the horde, then a horned body.
    let aura = DaemonAuraRadius
    drawCircleLines(cx.int32, cy.int32, aura * (0.92'f32 + pulse * 0.08'f32), withAlpha(col, 40))
    drawRing(v2(cx, cy), aura - 3.0'f32, aura, t * 60.0'f32, t * 60.0'f32 + 60.0'f32, 12, withAlpha(col, 70))
    drawRing(v2(cx, cy), aura - 3.0'f32, aura, t * 60.0'f32 + 180.0'f32, t * 60.0'f32 + 240.0'f32, 12, withAlpha(col, 70))
    drawCircle(v2(cx, cy), r + 5.0'f32, withAlpha(col, 45))
    drawCircle(v2(cx, cy), r, col)
    drawCircleLines(cx.int32, cy.int32, r, darker(col, 3))
    for s in [-1.0'f32, 1.0'f32]:
      tri(v2(cx + s * r * 0.4'f32, cy - r * 0.7'f32),
          v2(cx + s * r * 0.95'f32, cy - r * 1.5'f32),
          v2(cx + s * r * 0.75'f32, cy - r * 0.45'f32), lighter(col, 50))
    drawCircle(v2(cx, cy), r * 0.3'f32, White)

  of etInterrupt:
    let marking = enemy.attackPhase == 1
    let blink = if marking and (int(t * 12.0'f32) mod 2 == 0): 80 else: 0
    let body = lighter(col, blink)
    drawCircle(v2(cx, cy), r + 5.0'f32, withAlpha(col, 45))
    let up = if enemy.attackPhase == 2: heading else: -PI / 2.0'f32
    let p0 = v2(cx + cos(up) * r * 1.2'f32, cy + sin(up) * r * 1.2'f32)
    let p1 = v2(cx + cos(up + 2.2'f32) * r, cy + sin(up + 2.2'f32) * r)
    let p2 = v2(cx + cos(up - 2.2'f32) * r, cy + sin(up - 2.2'f32) * r)
    tri(p0, p1, p2, body)
    drawLine(p0, p1, 2.0, darker(col, 3))
    drawLine(p1, p2, 2.0, darker(col, 3))
    drawLine(p2, p0, 2.0, darker(col, 3))
    # "!"
    drawLine(v2(cx, cy - r * 0.35'f32), v2(cx, cy + r * 0.1'f32), 2.5, Color(r: 40, g: 20, b: 0, a: 255))
    drawCircle(v2(cx, cy + r * 0.35'f32), 1.8, Color(r: 40, g: 20, b: 0, a: 255))

  of etFragment:
    # The pounce mark is drawn with the body, never hint-gated: it is the only
    # tell of the slam. Tracking = a wandering amber ring, locked = a red
    # ring that fills in as the Fragment comes down on it.
    var lift = 0.0'f32
    if enemy.attackPhase in 1..3:
      let m = enemy.targetPos
      let locked = enemy.attackPhase >= 2
      let markCol = if locked: Color(r: 255, g: 80, b: 60, a: 255)
                    else: Color(r: 255, g: 215, b: 140, a: 255)
      let fall = if enemy.attackPhase == 3: clamp(enemy.modeTimer / FragmentLeapTime, 0.0'f32, 1.0'f32)
                 else: 0.0'f32
      if locked:
        drawCircle(v2(m.x, m.y), FragmentSlamRadius * (0.3'f32 + 0.7'f32 * fall),
                   withAlpha(markCol, a8(50.0 + 60.0 * fall)))
      drawCircleLines(m.x.int32, m.y.int32, FragmentSlamRadius,
                      withAlpha(markCol, a8(if locked: 235.0 else: 110.0 + pulse * 90.0)))
      let tick = if locked: 0.0'f32 else: t * 3.0'f32
      for k in 0..3:
        let a = tick + k.float32 * PI / 2.0
        drawLine(v2(m.x + cos(a) * (FragmentSlamRadius - 7.0'f32), m.y + sin(a) * (FragmentSlamRadius - 7.0'f32)),
                 v2(m.x + cos(a) * (FragmentSlamRadius + 4.0'f32), m.y + sin(a) * (FragmentSlamRadius + 4.0'f32)),
                 2.0, withAlpha(markCol, 210))
      if enemy.attackPhase == 3:
        # Airborne: a shadow on the ground, the shard riding an arc above it.
        lift = sin(fall * PI) * 26.0'f32
        drawEllipse(cx.int32, cy.int32, r * (1.0'f32 - lift / 80.0'f32),
                    r * 0.45'f32, Color(r: 0, g: 0, b: 0, a: 80))
    # Crouched while it marks: flattened and flaring white on the lock.
    let crouched = enemy.attackPhase in 1..2
    let sq = if crouched: 0.72'f32 else: 1.0'f32
    let bodyY = cy - lift + (if crouched: r * 0.25'f32 else: 0.0'f32)
    let body = if enemy.attackPhase == 2: lighter(col, 60) else: col
    # A jagged shard that tumbles a little on every hop.
    let spin = enemy.id.float32 * 1.3'f32 + floor(t * 1.4'f32 + enemy.id.float32 * 0.3'f32) * 0.9'f32
    var pts: array[5, Vector2]
    for i in 0..4:
      let a = spin + i.float32 * PI * 2.0 / 5.0
      let rr = r * (if i mod 2 == 0: 1.15'f32 else: 0.7'f32)
      pts[i] = v2(cx + cos(a) * rr, bodyY + sin(a) * rr * sq)
    for i in 0..4:
      tri(v2(cx, bodyY), pts[i], pts[(i + 1) mod 5], body)
    for i in 0..4:
      drawLine(pts[i], pts[(i + 1) mod 5], 1.5, darker(col, 3))
    drawCircle(v2(cx, bodyY), r * 0.22'f32, White)

  of etPortGuard:
    drawCircle(v2(cx, cy), r + 4.0'f32, withAlpha(col, 35))
    drawCircle(v2(cx, cy), r, col)
    drawCircleLines(cx.int32, cy.int32, r, darker(col, 3))
    # The shield: a thick arc covering the blocked front.
    let deg = enemy.rotation * 180.0'f32 / PI
    let half = PortGuardShieldHalfArc * 180.0'f32 / PI
    drawRing(v2(cx, cy), r + 3.0'f32, r + 9.0'f32, deg - half, deg + half, 18,
             Color(r: 255, g: 220, b: 150, a: 235))
    drawRing(v2(cx, cy), r + 9.0'f32, r + 11.0'f32, deg - half, deg + half, 18,
             Color(r: 255, g: 255, b: 255, a: a8(120.0 + pulse * 100.0)))
    # Port number stencil
    drawCircle(v2(cx - cos(enemy.rotation) * r * 0.2'f32, cy - sin(enemy.rotation) * r * 0.2'f32),
               r * 0.3'f32, darker(col, 2))

  of etSentry:
    let rooted = enemy.attackPhase == 1
    if rooted:
      for k in 0..2:
        let la = enemy.id.float32 + k.float32 * PI * 2.0 / 3.0
        drawLine(v2(cx, cy), v2(cx + cos(la) * r * 1.6'f32, cy + sin(la) * r * 1.6'f32), 2.5,
                 darker(col, 2))
    drawCircle(v2(cx, cy), r + 4.0'f32, withAlpha(col, 35))
    drawPoly(v2(cx, cy), 6, r, 0.0, col)
    drawPolyLines(v2(cx, cy), 6, r, 0.0, darker(col, 3))
    let aim = if rooted: enemy.rotation else: heading
    drawLine(v2(cx, cy), v2(cx + cos(aim) * r * 1.5'f32, cy + sin(aim) * r * 1.5'f32), 4.0,
             Color(r: 40, g: 60, b: 40, a: 255))
    if rooted:
      let charge = clamp(enemy.shootTimer / 2.4'f32, 0.0'f32, 1.0'f32)
      drawCircle(v2(cx, cy), r * 0.35'f32, withAlpha(Color(r: 255, g: 255, b: 160, a: 255), a8(80.0 + charge * 175.0)))

  of etMimic:
    let awake = enemy.attackPhase != 0
    # A document with a folded corner...
    let w = r * 1.5'f32
    let h = r * 1.9'f32
    let x0 = cx - w / 2
    let y0 = cy - h / 2
    let paper = if awake: Color(r: 250, g: 235, b: 190, a: 255) else: Color(r: 225, g: 225, b: 215, a: 235)
    drawRectangle(Rectangle(x: x0, y: y0 + r * 0.35'f32, width: w, height: h - r * 0.35'f32), paper)
    drawRectangle(Rectangle(x: x0, y: y0, width: w - r * 0.4'f32, height: r * 0.4'f32), paper)
    tri(v2(x0 + w - r * 0.4'f32, y0), v2(x0 + w, y0 + r * 0.4'f32), v2(x0 + w - r * 0.4'f32, y0 + r * 0.4'f32),
        Color(r: 180, g: 180, b: 165, a: 255))
    drawRectangleLines(Rectangle(x: x0, y: y0, width: w, height: h), 1, Color(r: 90, g: 90, b: 80, a: 255))
    if not awake:
      for k in 0..2:
        let ly = y0 + r * 0.7'f32 + k.float32 * r * 0.35'f32
        drawLine(v2(x0 + 3, ly), v2(x0 + w - 4, ly), 1.0, Color(r: 120, g: 120, b: 110, a: 200))
      # A barely-there shimmer is the only tell.
      if int(t * 0.8'f32 + enemy.id.float32) mod 5 == 0:
        drawRectangleLines(Rectangle(x: x0 - 2, y: y0 - 2, width: w + 4, height: h + 4), 1,
                           Color(r: 255, g: 255, b: 255, a: a8(pulse * 60.0)))
    else:
      # ...with teeth.
      let my = cy + r * 0.15'f32
      for k in 0..4:
        let tx = x0 + 2 + k.float32 * (w - 4) / 5.0'f32
        tri(v2(tx, my - 4), v2(tx + (w - 4) / 10.0'f32, my + 4), v2(tx + (w - 4) / 5.0'f32, my - 4),
            Color(r: 160, g: 30, b: 30, a: 255))
      drawCircle(v2(cx - w * 0.2'f32, cy - r * 0.35'f32), 2.5, Color(r: 200, g: 20, b: 20, a: 255))
      drawCircle(v2(cx + w * 0.2'f32, cy - r * 0.35'f32), 2.5, Color(r: 200, g: 20, b: 20, a: 255))

  of etRestorer:
    if enemy.attackPhase == 2:
      # The channel: a green beam onto the corpse, filling as it completes.
      let k = clamp(1.0'f32 - enemy.attackExecuteTimer / RestorerChannelTime, 0.0'f32, 1.0'f32)
      dashedLine(enemy.pos, enemy.targetPos, 8, 5, 2.5, Color(r: 120, g: 255, b: 160, a: 220), t * 60.0'f32)
      drawRing(v2(enemy.targetPos.x, enemy.targetPos.y), 14.0, 18.0, -90.0, -90.0 + 360.0 * k, 24,
               Color(r: 140, g: 255, b: 170, a: 230))
      drawCircleLines(enemy.targetPos.x.int32, enemy.targetPos.y.int32, 16.0, withAlpha(White, 90))
    drawCircle(v2(cx, cy), r + 5.0'f32 + pulse * 2.0'f32, withAlpha(col, 45))
    drawCircle(v2(cx, cy), r, col)
    drawCircleLines(cx.int32, cy.int32, r, darker(col, 3))
    drawRectangle(Rectangle(x: cx - r * 0.18'f32, y: cy - r * 0.6'f32, width: r * 0.36'f32, height: r * 1.2'f32), White)
    drawRectangle(Rectangle(x: cx - r * 0.6'f32, y: cy - r * 0.18'f32, width: r * 1.2'f32, height: r * 0.36'f32), White)

  of etPacket:
    let dashing = enemy.attackPhase == 1
    if dashing and velLen > 1.0'f32:
      let dir = enemy.vel * (1.0'f32 / velLen)
      for k in 1..4:
        let p = newVector2f(cx, cy) - dir * (k.float32 * r * 0.9'f32)
        drawCircle(v2(p.x, p.y), r * (1.0'f32 - k.float32 * 0.18'f32), withAlpha(col, a8(120.0 - k.float32 * 25.0)))
    let windup = enemy.attackPhase == 0 and enemy.modeTimer > 0.0'f32
    let body = if windup and int(t * 14.0'f32) mod 2 == 0: lighter(col, 90) else: col
    drawCircle(v2(cx, cy), r + 4.0'f32, withAlpha(col, 40))
    drawPoly(v2(cx, cy), 4, r * 1.1'f32, heading * 180.0'f32 / PI, body)
    drawPolyLines(v2(cx, cy), 4, r * 1.1'f32, heading * 180.0'f32 / PI, darker(col, 3))
    # Envelope flap
    let rot = heading
    drawLine(v2(cx + cos(rot + 2.4'f32) * r * 0.7'f32, cy + sin(rot + 2.4'f32) * r * 0.7'f32),
             v2(cx + cos(rot) * r * 0.2'f32, cy + sin(rot) * r * 0.2'f32), 1.5, White)
    drawLine(v2(cx + cos(rot - 2.4'f32) * r * 0.7'f32, cy + sin(rot - 2.4'f32) * r * 0.7'f32),
             v2(cx + cos(rot) * r * 0.2'f32, cy + sin(rot) * r * 0.2'f32), 1.5, White)

  of etDriver:
    let stunned = enemy.attackPhase == 3
    let winding = enemy.attackPhase == 1
    let face = enemy.rotation
    let shake = if winding: sin(t * 50.0'f32) * 1.5'f32 else: 0.0'f32
    let bx = cx + shake
    drawCircle(v2(bx, cy), r + 5.0'f32, withAlpha(col, if stunned: 25 else: 45))
    # Heavy body with a front ram plate.
    let back = v2(bx - cos(face) * r, cy - sin(face) * r)
    let side = newVector2f(-sin(face), cos(face)) * r
    let front = v2(bx + cos(face) * r * 1.1'f32, cy + sin(face) * r * 1.1'f32)
    tri(v2(back.x + side.x, back.y + side.y), v2(back.x - side.x, back.y - side.y), front, col)
    drawCircle(v2(bx, cy), r * 0.75'f32, col)
    let plateC = v2(bx + cos(face) * r * 0.9'f32, cy + sin(face) * r * 0.9'f32)
    drawLine(v2(plateC.x + side.x * 0.9'f32, plateC.y + side.y * 0.9'f32),
             v2(plateC.x - side.x * 0.9'f32, plateC.y - side.y * 0.9'f32), 5.0,
             if stunned: Color(r: 120, g: 110, b: 140, a: 255) else: Color(r: 230, g: 220, b: 255, a: 255))
    drawCircle(v2(bx, cy), r * 0.25'f32, if stunned: Gray else: White)
    if stunned:
      # Dizzy stars orbiting: it is wide open.
      for k in 0..2:
        let sa = t * 5.0'f32 + k.float32 * PI * 2.0 / 3.0
        drawPoly(v2(bx + cos(sa) * r * 0.9'f32, cy - r * 1.3'f32 + sin(sa) * r * 0.3'f32), 5, 3.5, t * 200.0,
                 Color(r: 255, g: 240, b: 120, a: 255))

  of etCorruptor:
    # Glitch: RGB-split copies jitter around a dark core.
    let gj = sin(t * 23.0'f32 + enemy.id.float32) * 2.5'f32
    drawCircle(v2(cx + gj, cy), r, Color(r: 255, g: 0, b: 80, a: 120))
    drawCircle(v2(cx - gj, cy + 1), r, Color(r: 0, g: 220, b: 255, a: 110))
    drawCircle(v2(cx, cy), r * 0.9'f32, col)
    for k in 0..2:
      let sy = cy - r * 0.6'f32 + k.float32 * r * 0.55'f32 + (t * 30.0'f32 mod 6.0'f32)
      drawLine(v2(cx - r * 0.8'f32, sy), v2(cx + r * 0.8'f32, sy), 1.0, Color(r: 20, g: 0, b: 20, a: 160))
    drawRectangle(Rectangle(x: cx - 3, y: cy - 3, width: 6, height: 6), White)

  else:
    drawCircle(v2(cx, cy), r, col)

proc drawEnemyTethers*(enemies: seq[Enemy]) =
  ## Deadlock tethers (lethal once armed) and the Forkmother's process-tree
  ## lines to her children (harmless: they only show where the children are).
  ## Ungated: a tether is a hazard.
  let t = getTime().float32
  for e in enemies:
    if e.hp <= 0 or e.linkId <= 0: continue
    var partner: Enemy = nil
    for o in enemies:
      if o.id == e.linkId and o.hp > 0:
        partner = o
        break
    if partner.isNil: continue
    if e.enemyType == etDeadlock:
      if e.id > partner.id: continue   # draw each pair once
      let d = distance(e.pos, partner.pos)
      let armed = e.modeTimer >= DeadlockArmDelay and partner.modeTimer >= DeadlockArmDelay
      let slack = d > DeadlockMaxTether
      if slack:
        dashedLine(e.pos, partner.pos, 6, 10, 1.0, Color(r: 255, g: 120, b: 120, a: 70), t * 20.0'f32)
      elif not armed:
        dashedLine(e.pos, partner.pos, 8, 6, 1.5, Color(r: 255, g: 120, b: 120, a: 150), t * 40.0'f32)
      else:
        let flick = sin(t * 30.0'f32) * 0.5'f32 + 0.5'f32
        drawLine(v2(e.pos.x, e.pos.y), v2(partner.pos.x, partner.pos.y), DeadlockTetherHalfWidth * 2.0'f32 + 4.0'f32,
                 Color(r: 255, g: 40, b: 40, a: a8(60.0 + flick * 40.0)))
        drawLine(v2(e.pos.x, e.pos.y), v2(partner.pos.x, partner.pos.y), DeadlockTetherHalfWidth * 2.0'f32,
                 Color(r: 255, g: 70, b: 70, a: 230))
        drawLine(v2(e.pos.x, e.pos.y), v2(partner.pos.x, partner.pos.y), 2.0, Color(r: 255, g: 230, b: 230, a: 255))
    elif partner.isBoss:
      # Child -> mother: a thin pink process-tree branch (unless her seal's
      # legion chains already point at it).
      if partner.addsGateActive and partner.weakPoint.kind == bwoSummonSigils and
         partner.weakPoint.exposedTimer <= 0:
        continue
      dashedLine(e.pos, partner.pos, 5, 7, 1.2, Color(r: 255, g: 120, b: 190, a: 110), -t * 30.0'f32)

proc drawHusks*(husks: seq[HuskRecord]) =
  ## Fallen Zombie Processes waiting to stand back up: walk over one to reap it.
  let t = getTime().float32
  for h in husks:
    let k = clamp(1.0'f32 - h.timer / ZombieReanimateTime, 0.0'f32, 1.0'f32)
    let wob = sin(t * (6.0'f32 + k * 18.0'f32)) * k * 2.0'f32
    let r = h.radius
    drawCircle(v2(h.pos.x, h.pos.y), ZombieReapRadius, Color(r: 150, g: 180, b: 110, a: 26))
    drawRectangle(Rectangle(x: h.pos.x - r + wob, y: h.pos.y - r * 0.4'f32, width: r * 2, height: r * 0.8'f32),
                  Color(r: 90, g: 105, b: 70, a: 220))
    drawRing(v2(h.pos.x, h.pos.y), r + 4.0'f32, r + 7.0'f32, -90.0, -90.0 + 360.0 * k, 24,
             Color(r: 200, g: 230, b: 120, a: 230))

# ---------------------------------------------------------------------------
# Boss bodies (13-15, 17-22)

proc drawModeBossBody*(enemy: Enemy) =
  let t = getTime().float32
  let pulse = sin(t * 2.5'f32) * 0.5'f32 + 0.5'f32
  let breathe = sin(t * 1.0'f32) * 0.5'f32 + 0.5'f32
  let cx = enemy.pos.x
  let cy = enemy.pos.y
  let r = enemy.radius
  let col = enemy.color
  let phaseLvl = max(0, enemy.currentPhaseIndex).float32
  proc glow(radius: float32, c: Color) = drawCircle(v2(cx, cy), radius, c)

  case enemy.bossDefinitionID
  of 13:  # The Forkmother
    glow(r + 24 + breathe * 6, withAlpha(col, 35))
    glow(r + 12 + pulse * 4, withAlpha(col, 60))
    # A binary tree rotating out of her body: the processes she forks.
    proc branch(x, y, ang, len: float32, depth: int) =
      if depth <= 0 or len < 3: return
      let ex = x + cos(ang) * len
      let ey = y + sin(ang) * len
      drawLine(v2(x, y), v2(ex, ey), max(1.0'f32, depth.float32 * 0.8'f32),
               Color(r: 255, g: 170, b: 220, a: a8(90.0 + depth.float32 * 30.0)))
      branch(ex, ey, ang - 0.5'f32, len * 0.66'f32, depth - 1)
      branch(ex, ey, ang + 0.5'f32, len * 0.66'f32, depth - 1)
    for k in 0..2:
      let a = t * 0.4'f32 + k.float32 * PI * 2.0 / 3.0
      branch(cx + cos(a) * r * 0.7'f32, cy + sin(a) * r * 0.7'f32, a, r * 0.55'f32, 3 + int(phaseLvl))
    glow(r * 0.8'f32, col)
    drawCircleLines(cx.int32, cy.int32, r * 0.8'f32, darker(col, 3))
    polyLines(cx, cy, 3, r * 0.5'f32, t * 0.8'f32, 3, Color(r: 255, g: 230, b: 245, a: 230))
    glow(r * 0.2'f32 + pulse * 3, White)

  of 14:  # The Dispatcher
    glow(r + 20 + breathe * 5, withAlpha(col, 35))
    # The queue: tickets circulating on a conveyor ring.
    let slots = 12
    for i in 0..<slots:
      let a = t * 0.7'f32 + i.float32 * PI * 2.0 / slots.float32
      let px = cx + cos(a) * (r + 10)
      let py = cy + sin(a) * (r + 10)
      drawRectangle(Rectangle(x: px, y: py, width: 9, height: 6), v2(4.5, 3), a * 180.0'f32 / PI,
                       if i mod 3 == 0: Color(r: 255, g: 240, b: 200, a: 230) else: withAlpha(col, 170))
    drawPoly(v2(cx, cy), 8, r * 0.85'f32, t * 10.0'f32, col)
    drawPolyLines(v2(cx, cy), 8, r * 0.85'f32, t * 10.0'f32, darker(col, 3))
    # Clipboard with a ticking line
    drawRectangle(Rectangle(x: cx - r * 0.35'f32, y: cy - r * 0.45'f32, width: r * 0.7'f32, height: r * 0.9'f32),
                  Color(r: 255, g: 245, b: 220, a: 255))
    for k in 0..2:
      let ly = cy - r * 0.25'f32 + k.float32 * r * 0.22'f32
      drawLine(v2(cx - r * 0.25'f32, ly), v2(cx + r * 0.25'f32, ly), 2.0, Color(r: 120, g: 80, b: 20, a: 255))
    let sweep = cy - r * 0.4'f32 + ((t * 0.6'f32) mod 1.0'f32) * r * 0.8'f32
    drawLine(v2(cx - r * 0.35'f32, sweep), v2(cx + r * 0.35'f32, sweep), 1.5, Color(r: 255, g: 120, b: 0, a: 220))

  of 15:  # Thermal Runaway
    # Heat shimmer: flames licking up, a temperature gauge filling as it dies.
    for i in 0..13:
      let a = i.float32 * PI * 2.0 / 14.0 + sin(t * 3.0'f32 + i.float32) * 0.1'f32
      let flick = sin(t * (9.0'f32 + i.float32 * 1.3'f32)) * 0.5'f32 + 0.5'f32
      let base = v2(cx + cos(a) * r * 0.85'f32, cy + sin(a) * r * 0.85'f32)
      let tip = v2(cx + cos(a) * (r + 10 + flick * 14), cy + sin(a) * (r + 10 + flick * 14))
      let side = newVector2f(-sin(a), cos(a)) * 6.0'f32
      tri(v2(base.x + side.x, base.y + side.y), v2(base.x - side.x, base.y - side.y), tip,
          Color(r: 255, g: uint8(120 + flick * 100), b: 20, a: 200))
    glow(r * 0.95'f32, col)
    glow(r * 0.7'f32, Color(r: 255, g: 170, b: 60, a: 255))
    glow(r * 0.4'f32 + pulse * 4, Color(r: 255, g: 240, b: 180, a: 255))
    let hpPct = clamp(enemy.hp / max(0.01'f32, enemy.maxHp), 0.0'f32, 1.0'f32)
    let heat = (1.0'f32 - hpPct + phaseLvl) / 3.0'f32
    drawRing(v2(cx, cy), r + 2, r + 6, 135.0, 135.0 + 270.0 * clamp(heat, 0.05'f32, 1.0'f32), 32,
             Color(r: 255, g: 60, b: 20, a: 230))

  of 17:  # The Gatekeeper
    glow(r + 20 + breathe * 5, withAlpha(col, 30))
    # A keep: square wall with crenellations and gate bars.
    let s = r * 0.85'f32
    drawRectangle(Rectangle(x: cx - s, y: cy - s, width: s * 2, height: s * 2), darker(col, 2))
    for k in 0..3:
      let bx = cx - s + k.float32 * s * 0.66'f32
      drawRectangle(Rectangle(x: bx, y: cy - s - 8, width: s * 0.4'f32, height: 8), col)
    for k in -2..2:
      drawLine(v2(cx + k.float32 * s * 0.3'f32, cy - s * 0.2'f32), v2(cx + k.float32 * s * 0.3'f32, cy + s), 3.0,
               Color(r: 60, g: 30, b: 10, a: 255))
    drawRectangleLines(Rectangle(x: cx - s, y: cy - s, width: s * 2, height: s * 2), 3, col)
    # The inspection lens (turns with the beams)
    drawCircle(v2(cx, cy - s * 0.45'f32), s * 0.32'f32, Color(r: 255, g: 230, b: 150, a: 255))
    drawCircle(v2(cx + cos(t * 0.6'f32) * 3, cy - s * 0.45'f32 + sin(t * 0.6'f32) * 3), s * 0.14'f32,
               Color(r: 90, g: 30, b: 0, a: 255))

  of 18:  # The Compactor
    glow(r + 18 + breathe * 5, withAlpha(col, 35))
    # A bin: tapered body, ribbed, with a lid that jaws open and shut.
    let w = r * 1.3'f32
    let h = r * 1.5'f32
    let bite = (sin(t * 3.0'f32) * 0.5'f32 + 0.5'f32) * 8.0'f32
    let top = cy - h / 2 + bite
    tri(v2(cx - w / 2, top), v2(cx + w / 2, top), v2(cx + w * 0.38'f32, cy + h / 2), col)
    tri(v2(cx - w / 2, top), v2(cx + w * 0.38'f32, cy + h / 2), v2(cx - w * 0.38'f32, cy + h / 2), col)
    for k in -1..1:
      drawLine(v2(cx + k.float32 * w * 0.2'f32, top + 6), v2(cx + k.float32 * w * 0.16'f32, cy + h / 2 - 4), 2.0,
               darker(col, 2))
    drawRectangle(Rectangle(x: cx - w * 0.58'f32, y: top - 10 - bite, width: w * 1.16'f32, height: 8), lighter(col, 30))
    drawRectangle(Rectangle(x: cx - 8, y: top - 16 - bite, width: 16, height: 6), lighter(col, 30))
    # Recycle arrows
    for k in 0..2:
      let a = t * 1.2'f32 + k.float32 * PI * 2.0 / 3.0
      drawCircle(v2(cx + cos(a) * r * 0.3'f32, cy + r * 0.1'f32 + sin(a) * r * 0.3'f32), 3.5,
                 Color(r: 230, g: 255, b: 220, a: 230))

  of 19:  # The Hive
    glow(r + 20 + breathe * 5, withAlpha(col, 35))
    # Honeycomb of keys around a central cell.
    let cell = r * 0.36'f32
    for ring in 0..1:
      let count = if ring == 0: 1 else: 6
      for i in 0..<count:
        let a = i.float32 * PI / 3.0 + t * 0.15'f32
        let d = ring.float32 * cell * 1.75'f32
        let px = cx + cos(a) * d
        let py = cy + sin(a) * d
        let lit = (int(t * 2.0'f32) + i) mod 6 == 0
        drawPoly(v2(px, py), 6, cell, 30.0, if lit: lighter(col, 90) else: col)
        drawPolyLines(v2(px, py), 6, cell, 30.0, darker(col, 3))
    drawCircle(v2(cx, cy), cell * 0.4'f32 + pulse * 2, White)

  of 20:  # The Router
    glow(r + 18 + breathe * 5, withAlpha(col, 30))
    # Antennas and routing rings with packets orbiting.
    for k in 0..3:
      let a = k.float32 * PI / 2.0 + PI / 4.0
      drawLine(v2(cx + cos(a) * r * 0.6'f32, cy + sin(a) * r * 0.6'f32),
               v2(cx + cos(a) * (r + 14), cy + sin(a) * (r + 14)), 2.5, lighter(col, 40))
      drawCircle(v2(cx + cos(a) * (r + 14), cy + sin(a) * (r + 14)), 3.5 + pulse * 1.5, White)
    for ring in 1..2:
      drawCircleLines(cx.int32, cy.int32, r * (0.45'f32 + ring.float32 * 0.22'f32), withAlpha(col, 160))
      for p in 0..2:
        let a = t * (1.5'f32 - ring.float32 * 0.5'f32) * (if ring == 1: 1.0'f32 else: -1.0'f32) + p.float32 * PI * 2.0 / 3.0
        let rr = r * (0.45'f32 + ring.float32 * 0.22'f32)
        drawCircle(v2(cx + cos(a) * rr, cy + sin(a) * rr), 3.0, White)
    glow(r * 0.42'f32, col)
    glow(r * 0.18'f32, White)

  of 21:  # The Supervisor
    glow(r + 20 + breathe * 5, withAlpha(col, 30))
    # A rotating grid of memory pages; some flicker out (paged).
    let n = 4
    let cell = r * 0.4'f32
    for gx in 0..<n:
      for gy in 0..<n:
        let ox = (gx.float32 - (n - 1).float32 / 2.0) * cell * 1.1'f32
        let oy = (gy.float32 - (n - 1).float32 / 2.0) * cell * 1.1'f32
        let a = t * 0.2'f32
        let px = cx + ox * cos(a) - oy * sin(a)
        let py = cy + ox * sin(a) + oy * cos(a)
        let paged = (gx * 3 + gy * 5 + int(t * 1.5'f32)) mod 7 == 0
        drawRectangle(Rectangle(x: px, y: py, width: cell * 0.9'f32, height: cell * 0.9'f32),
                         v2(cell * 0.45'f32, cell * 0.45'f32), a * 180.0'f32 / PI,
                         if paged: withAlpha(col, 60) else: col)
    drawCircleLines(cx.int32, cy.int32, r, lighter(col, 50))
    glow(r * 0.18'f32 + pulse * 2, White)

  of 22:  # The Mirror Cache
    # A disk platter with a mirrored ghost trailing it.
    let off = newVector2f(sin(t * 1.3'f32), cos(t * 1.1'f32)) * 8.0'f32
    drawCircle(v2(cx - off.x, cy - off.y), r, withAlpha(col, 45))
    glow(r + 14 + breathe * 4, withAlpha(col, 35))
    glow(r, darker(col, 2))
    for ring in 1..4:
      drawCircleLines(cx.int32, cy.int32, r * ring.float32 / 4.6'f32, withAlpha(lighter(col, 60), 180))
    let arm = t * 1.8'f32
    drawLine(v2(cx + cos(arm) * r * 1.05'f32, cy + sin(arm) * r * 1.05'f32),
             v2(cx + cos(arm) * r * 0.25'f32, cy + sin(arm) * r * 0.25'f32), 4.0, Color(r: 230, g: 240, b: 240, a: 255))
    glow(r * 0.14'f32, White)

  else:
    glow(r + 12 + pulse * 5, withAlpha(White, 40))
    glow(r, col)

# ---------------------------------------------------------------------------
# Warnings

proc drawModeWarningTelegraph*(w: AttackWarning) =
  ## Hint-gated wind-up cues.
  let t = getTime().float32
  case w.attackType
  of awtMarchLane:
    # The lane the rank will sweep, chevrons pointing the way.
    let dir = (w.targetPos - w.pos).normalize()
    let perp = newVector2f(-dir.y, dir.x)
    let halfSpan = w.laserLength
    let a0 = w.pos - perp * halfSpan
    let a1 = w.pos + perp * halfSpan
    let k = clamp(warningAge(w) / max(0.01'f32, w.maxLifetime), 0.0'f32, 1.0'f32)
    drawLine(v2(a0.x, a0.y), v2(a1.x, a1.y), 10.0, Color(r: 255, g: 170, b: 40, a: a8(60.0 + 120.0 * k)))
    for i in -4..4:
      let base = w.pos + perp * (i.float32 * halfSpan / 4.5'f32) + dir * (18.0'f32 + ((t * 80.0'f32) mod 40.0'f32))
      let tip = base + dir * 14.0'f32
      drawLine(v2(base.x + perp.x * 8, base.y + perp.y * 8), v2(tip.x, tip.y), 3.0, Color(r: 255, g: 200, b: 90, a: 200))
      drawLine(v2(base.x - perp.x * 8, base.y - perp.y * 8), v2(tip.x, tip.y), 3.0, Color(r: 255, g: 200, b: 90, a: 200))
  of awtThermalVent:
    if w.lifetime > ThermalVentActive:
      let k = clamp(warningAge(w) / ThermalVentTelegraph, 0.0'f32, 1.0'f32)
      drawCircle(v2(w.pos.x, w.pos.y), w.bulletRadius * k, Color(r: 255, g: 80, b: 20, a: 60))
      drawCircleLines(w.pos.x.int32, w.pos.y.int32, w.bulletRadius, Color(r: 255, g: 120, b: 40, a: 200))
  of awtSafeMode:
    if not safeModeFlooding(w):
      # Where the bubble will start and where it will drift to.
      let k = clamp(warningAge(w) / SafeModeTelegraph, 0.0'f32, 1.0'f32)
      drawCircleLines(w.pos.x.int32, w.pos.y.int32, SafeModeStartRadius, Color(r: 120, g: 255, b: 200, a: a8(120.0 + 120.0 * k)))
      dashedLine(w.pos, w.targetPos, 14, 10, 3.0, Color(r: 120, g: 255, b: 200, a: 160), t * 50.0'f32)
      drawCircleLines(w.targetPos.x.int32, w.targetPos.y.int32, SafeModeEndRadius, Color(r: 120, g: 255, b: 200, a: 90))
  of awtSearchlight:
    if not searchlightLive(w):
      for b in 0..<w.laserAngles.len:
        let a = searchlightAngle(w, b)
        let tip = w.pos + newVector2f(cos(a), sin(a)) * 900.0'f32
        dashedLine(w.pos, tip, 18, 12, 2.0, Color(r: 255, g: 220, b: 140, a: 150), t * 80.0'f32)
  of awtPacketLink:
    if warningAge(w) < w.laserDuration:
      let k = clamp(warningAge(w) / max(0.01'f32, w.laserDuration), 0.0'f32, 1.0'f32)
      drawLine(v2(w.pos.x, w.pos.y), v2(w.targetPos.x, w.targetPos.y), 3.0 + 5.0 * k,
               Color(r: 0, g: 220, b: 255, a: a8(60.0 + 150.0 * k)))
  else:
    discard

proc drawModeWarningActive*(w: AttackWarning) =
  ## Ungated: every lethal state, and the tells a mechanic cannot work without.
  let t = getTime().float32
  case w.attackType
  of awtEnemyDashLane:
    let k = clamp(warningAge(w) / max(0.01'f32, w.maxLifetime), 0.0'f32, 1.0'f32)
    let col = case w.enemyType
              of etInterrupt: Color(r: 255, g: 150, b: 40, a: 255)
              of etDriver: Color(r: 190, g: 150, b: 255, a: 255)
              else: Color(r: 0, g: 220, b: 255, a: 255)
    if w.enemyType == etInterrupt:
      # Where it will land and blow.
      drawCircle(v2(w.targetPos.x, w.targetPos.y), w.bulletRadius * k, withAlpha(col, 45))
      drawCircleLines(w.targetPos.x.int32, w.targetPos.y.int32, w.bulletRadius, withAlpha(col, a8(150.0 + 100.0 * k)))
      dashedLine(w.pos, w.targetPos, 6, 6, 1.5, withAlpha(col, 140), t * 60.0'f32)
    else:
      drawLine(v2(w.pos.x, w.pos.y), v2(w.targetPos.x, w.targetPos.y), w.bulletRadius * 2.0'f32,
               withAlpha(col, a8(30.0 + 50.0 * k)))
      dashedLine(w.pos, w.targetPos, 10, 8, 2.0, withAlpha(col, a8(120.0 + 120.0 * k)), t * 90.0'f32)
  of awtCorruptTile:
    let h = w.bulletRadius
    let rect = Rectangle(x: w.pos.x - h, y: w.pos.y - h, width: h * 2, height: h * 2)
    if w.lifetime > CorruptTileActive:
      let k = clamp(warningAge(w) / CorruptTileArm, 0.0'f32, 1.0'f32)
      drawRectangleLines(rect, 1, Color(r: 255, g: 80, b: 200, a: a8(90.0 + 120.0 * k)))
    else:
      let fade = clamp(w.lifetime / 0.8'f32, 0.0'f32, 1.0'f32)
      drawRectangle(rect, Color(r: 120, g: 0, b: 90, a: a8(110.0 * fade)))
      for k in 0..3:
        let sy = w.pos.y - h + ((t * 40.0'f32 + k.float32 * h * 0.5'f32) mod (h * 2))
        drawLine(v2(w.pos.x - h, sy), v2(w.pos.x + h, sy), 1.0, Color(r: 255, g: 90, b: 220, a: a8(160.0 * fade)))
      drawRectangleLines(rect, 2, Color(r: 255, g: 60, b: 200, a: a8(220.0 * fade)))
  of awtForkTree:
    # The binary tree the seeds will take (ricochetPath = segment pairs).
    var i = 0
    while i + 1 < w.ricochetPath.len:
      dashedLine(w.ricochetPath[i], w.ricochetPath[i + 1], 7, 7, 1.5,
                 Color(r: 255, g: 130, b: 200, a: 110), t * 30.0'f32)
      i += 2
  of awtMarchLane:
    # A small ungated edge marker even with hints off.
    drawCircle(v2(w.pos.x, w.pos.y), 10.0 + sin(t * 10.0'f32) * 2.0, Color(r: 255, g: 170, b: 40, a: 200))
  of awtHeatEmitter:
    discard
  of awtHeatTrail:
    let age = warningAge(w)
    let r = w.bulletRadius
    if age < HeatTrailArm:
      let k = age / HeatTrailArm
      drawCircle(v2(w.pos.x, w.pos.y), r * (0.4'f32 + 0.6'f32 * k), Color(r: 255, g: 140, b: 40, a: a8(40.0 + 60.0 * k)))
    else:
      let fade = clamp(w.lifetime / 0.6'f32, 0.0'f32, 1.0'f32)
      let flick = sin(t * 18.0'f32 + w.pos.x * 0.1'f32) * 0.5'f32 + 0.5'f32
      drawCircle(v2(w.pos.x, w.pos.y), r + 3.0'f32, Color(r: 255, g: 60, b: 0, a: a8(90.0 * fade)))
      drawCircle(v2(w.pos.x, w.pos.y), r * 0.8'f32, Color(r: 255, g: uint8(140 + flick * 90), b: 30, a: a8(220.0 * fade)))
      drawCircle(v2(w.pos.x, w.pos.y), r * 0.35'f32, Color(r: 255, g: 240, b: 180, a: a8(230.0 * fade)))
  of awtThermalVent:
    if w.lifetime <= ThermalVentActive:
      let k = clamp(w.lifetime / ThermalVentActive, 0.0'f32, 1.0'f32)
      drawCircle(v2(w.pos.x, w.pos.y), w.bulletRadius, Color(r: 255, g: 120, b: 20, a: a8(200.0 * k)))
      drawCircle(v2(w.pos.x, w.pos.y), w.bulletRadius * 0.6'f32, Color(r: 255, g: 230, b: 150, a: a8(240.0 * k)))
  of awtSafeMode:
    if safeModeFlooding(w):
      let (c, r) = safeModeBubble(w)
      let shimmer = sin(t * 4.0'f32) * 0.5'f32 + 0.5'f32
      drawRing(v2(c.x, c.y), r, r + 2200.0, 0.0, 360.0, 72, Color(r: 90, g: 0, b: 70, a: a8(120.0 + shimmer * 30.0)))
      drawRing(v2(c.x, c.y), r, r + 10.0, 0.0, 360.0, 72, Color(r: 255, g: 60, b: 200, a: 150))
      drawCircleLines(c.x.int32, c.y.int32, r, Color(r: 150, g: 255, b: 210, a: 255))
      drawCircleLines(c.x.int32, c.y.int32, r - 3.0'f32, Color(r: 150, g: 255, b: 210, a: 120))
      centeredText(localization.t(tkModeSafeMode), c.x, c.y - r - 22.0'f32, 16, Color(r: 150, g: 255, b: 210, a: 255))
  of awtSearchlight:
    if searchlightLive(w):
      for b in 0..<w.laserAngles.len:
        let tip = if b < w.ricochetPath.len: w.ricochetPath[b]
                  else: w.pos + newVector2f(cos(searchlightAngle(w, b)), sin(searchlightAngle(w, b))) * 900.0'f32
        drawLine(v2(w.pos.x, w.pos.y), v2(tip.x, tip.y), SearchlightHalfWidth * 2.0'f32 + 8.0'f32,
                 Color(r: 255, g: 180, b: 60, a: 55))
        drawLine(v2(w.pos.x, w.pos.y), v2(tip.x, tip.y), SearchlightHalfWidth * 2.0'f32,
                 Color(r: 255, g: 220, b: 130, a: 170))
        drawLine(v2(w.pos.x, w.pos.y), v2(tip.x, tip.y), 3.0, Color(r: 255, g: 255, b: 230, a: 255))
        # The beam stops where cover stands: a hot splash on the obstacle.
        drawCircle(v2(tip.x, tip.y), 8.0 + sin(t * 20.0'f32) * 2.0, Color(r: 255, g: 240, b: 180, a: 220))
  of awtFileBomb:
    let purging = w.lifetime <= FileBombPurgeFlash
    if purging:
      let k = clamp(w.lifetime / FileBombPurgeFlash, 0.0'f32, 1.0'f32)
      drawCircle(v2(w.pos.x, w.pos.y), FileBombBlastRadius, Color(r: 160, g: 255, b: 120, a: a8(180.0 * k)))
    else:
      let warn = w.lifetime < 1.2'f32 and int(t * 10.0'f32) mod 2 == 0
      # A crumpled file with a fuse ring counting down to the purge.
      let pc = if warn: Color(r: 255, g: 255, b: 160, a: 255) else: Color(r: 210, g: 220, b: 200, a: 255)
      drawRectangle(Rectangle(x: w.pos.x, y: w.pos.y, width: 16, height: 20), v2(8, 10),
                       sin(w.pos.x) * 20.0, pc)
      drawLine(v2(w.pos.x - 5, w.pos.y - 3), v2(w.pos.x + 4, w.pos.y - 3), 1.5, Color(r: 90, g: 110, b: 80, a: 255))
      drawLine(v2(w.pos.x - 5, w.pos.y + 2), v2(w.pos.x + 3, w.pos.y + 2), 1.5, Color(r: 90, g: 110, b: 80, a: 255))
      let k = clamp(w.lifetime / max(0.01'f32, w.maxLifetime), 0.0'f32, 1.0'f32)
      drawRing(v2(w.pos.x, w.pos.y), 16.0, 19.0, -90.0, -90.0 + 360.0 * k, 24, Color(r: 150, g: 255, b: 120, a: 220))
      drawCircleLines(w.pos.x.int32, w.pos.y.int32, FileBombBlastRadius, Color(r: 150, g: 255, b: 120, a: if warn: 150 else: 45))
  of awtRestorePoint:
    let k = clamp(w.lifetime / max(0.01'f32, w.maxLifetime), 0.0'f32, 1.0'f32)
    let r = w.bulletRadius + 22.0'f32
    drawRing(v2(w.pos.x, w.pos.y), r, r + 5.0, -90.0, -90.0 + 360.0 * k, 48, Color(r: 120, g: 255, b: 170, a: 230))
    # Progress the player has made toward breaking it (laserLength = share done).
    let done = clamp(w.laserLength, 0.0'f32, 1.0'f32)
    drawRing(v2(w.pos.x, w.pos.y), r + 7.0, r + 10.0, -90.0, -90.0 + 360.0 * done, 48, Color(r: 255, g: 90, b: 90, a: 230))
    centeredText(localization.t(tkModeRestorePoint), w.pos.x, w.pos.y - r - 28.0'f32, 14, Color(r: 150, g: 255, b: 190, a: 255))
  of awtAuditLock:
    # pos follows the player; targetPos is where they stood when it locked.
    let age = warningAge(w)
    let locked = age >= AuditTelegraph
    if not locked:
      let k = clamp(age / AuditTelegraph, 0.0'f32, 1.0'f32)
      let count = int(ceil((AuditTelegraph - age) / (AuditTelegraph / 3.0'f32)))
      drawRing(v2(w.pos.x, w.pos.y), 34.0, 38.0, -90.0, -90.0 + 360.0 * k, 36, Color(r: 120, g: 180, b: 255, a: 230))
      centeredText($max(1, count), w.pos.x, w.pos.y - 62.0'f32, 22, Color(r: 170, g: 210, b: 255, a: 255))
    else:
      let c = w.targetPos
      let s = 30.0'f32
      let breach = w.bulletsCreated
      let lc = if breach: Color(r: 255, g: 70, b: 70, a: 255) else: Color(r: 140, g: 200, b: 255, a: 255)
      for sx in [-1.0'f32, 1.0'f32]:
        for sy in [-1.0'f32, 1.0'f32]:
          let px = c.x + sx * s
          let py = c.y + sy * s
          drawLine(v2(px, py), v2(px - sx * 10, py), 3.0, lc)
          drawLine(v2(px, py), v2(px, py - sy * 10), 3.0, lc)
      drawCircleLines(c.x.int32, c.y.int32, AuditMoveTolerance + 8.0'f32, withAlpha(lc, 120))
      # The whole room is frozen: a cold wash over everything.
      drawRectangle(0, 0, 4000, 4000, Color(r: 40, g: 80, b: 160, a: 26))
    let label = if w.bulletsCreated: localization.t(tkModeAuditBreach) else: localization.t(tkModeAuditLocked)
    centeredText(label, w.pos.x, w.pos.y - 92.0'f32, 16,
                 if w.bulletsCreated: Color(r: 255, g: 110, b: 110, a: 255) else: Color(r: 170, g: 210, b: 255, a: 255))
  of awtPacketLink:
    # Relay nodes at both ends; the link stays faintly lit while trains run.
    let live = warningAge(w) >= w.laserDuration
    drawLine(v2(w.pos.x, w.pos.y), v2(w.targetPos.x, w.targetPos.y), 1.5,
             Color(r: 0, g: 220, b: 255, a: if live: 90 else: 50))
    for p in [w.pos, w.targetPos]:
      drawPoly(v2(p.x, p.y), 4, 9.0, t * 90.0, Color(r: 0, g: 200, b: 255, a: 220))
      drawCircle(v2(p.x, p.y), 3.0, White)
    # The train: packets riding the link, a bright head and a fading tail.
    let train = packetTrain(w)
    if train.live:
      let dir = (w.targetPos - w.pos).normalize()
      let run = warningAge(w) - w.laserDuration
      let headD = run * w.bulletSpeed
      let len = packetLinkLength(w)
      for k in 0..<PacketCars:
        let d = headD - k.float32 * PacketCarSpacing
        if d < 0 or d > len: continue
        let p = w.pos + dir * d
        let fade = 1.0'f32 - k.float32 / PacketCars.float32 * 0.6'f32
        drawCircle(v2(p.x, p.y), PacketRadius + 4.0'f32, Color(r: 0, g: 200, b: 255, a: a8(70.0 * fade)))
        drawCircle(v2(p.x, p.y), PacketRadius, Color(r: 0, g: 230, b: 255, a: a8(255.0 * fade)))
        drawCircle(v2(p.x, p.y), PacketRadius * 0.45'f32, Color(r: 220, g: 255, b: 255, a: a8(255.0 * fade)))
  of awtPageFault:
    let r = w.bulletRadius
    if w.lifetime > PageFaultActive:
      # A ghost footprint where an obstacle is about to page in.
      let k = clamp(warningAge(w) / max(0.01'f32, w.maxLifetime - PageFaultActive), 0.0'f32, 1.0'f32)
      drawCircle(v2(w.pos.x, w.pos.y), r, Color(r: 150, g: 95, b: 235, a: a8(30.0 + 90.0 * k)))
      dashedLine(w.pos + newVector2f(-r, -r), w.pos + newVector2f(r, -r), 6, 5, 2.0, Color(r: 200, g: 160, b: 255, a: 230))
      dashedLine(w.pos + newVector2f(r, -r), w.pos + newVector2f(r, r), 6, 5, 2.0, Color(r: 200, g: 160, b: 255, a: 230))
      dashedLine(w.pos + newVector2f(r, r), w.pos + newVector2f(-r, r), 6, 5, 2.0, Color(r: 200, g: 160, b: 255, a: 230))
      dashedLine(w.pos + newVector2f(-r, r), w.pos + newVector2f(-r, -r), 6, 5, 2.0, Color(r: 200, g: 160, b: 255, a: 230))
      drawRing(v2(w.pos.x, w.pos.y), r + 4.0, r + 7.0, -90.0, -90.0 + 360.0 * k, 32, Color(r: 220, g: 190, b: 255, a: 230))
    else:
      drawCircle(v2(w.pos.x, w.pos.y), r + 6.0, Color(r: 230, g: 210, b: 255, a: 200))
  of awtStaleCopy:
    # The echo (targetPos = where it is, laserAngles[0] = its aim).
    if warningAge(w) >= w.laserDuration:
      let fadeIn = clamp((warningAge(w) - w.laserDuration) / EchoFadeIn, 0.0'f32, 1.0'f32)
      let fadeOut = clamp(w.lifetime / 0.5'f32, 0.0'f32, 1.0'f32)
      let al = fadeIn * fadeOut
      let p = w.targetPos
      let aim = if w.laserAngles.len > 0: w.laserAngles[0] else: 0.0'f32
      for k in 1..3:
        drawCircleLines(p.x.int32, p.y.int32, EchoRadius + k.float32 * 3.0'f32 + sin(t * 8.0'f32 + k.float32) * 1.5'f32,
                        Color(r: 70, g: 215, b: 195, a: a8(80.0 * al)))
      drawCircle(v2(p.x, p.y), EchoRadius, Color(r: 40, g: 160, b: 150, a: a8(200.0 * al)))
      drawCircleLines(p.x.int32, p.y.int32, EchoRadius, Color(r: 200, g: 255, b: 245, a: a8(255.0 * al)))
      drawLine(v2(p.x, p.y), v2(p.x + cos(aim) * EchoRadius * 1.6'f32, p.y + sin(aim) * EchoRadius * 1.6'f32), 3.0,
               Color(r: 200, g: 255, b: 245, a: a8(255.0 * al)))
  of awtLastKnownGood:
    let sw = w.pos.x * 2.0'f32
    let sh = w.pos.y * 2.0'f32
    let labels = w.laserPattern.split('|')
    let judging = w.lifetime <= LkgActive
    for door in 0..3:
      let rct = lkgDoorRect(door, sw, sh)
      let real = door == w.bulletCount
      let rect = Rectangle(x: rct.x, y: rct.y, width: rct.w, height: rct.h)
      if judging:
        if not real:
          drawRectangle(rect, Color(r: 255, g: 40, b: 60, a: 170))
        else:
          drawRectangle(rect, Color(r: 255, g: 215, b: 110, a: 120))
        continue
      let flicker = if real: 1.0'f32
                    else: (if int(t * 9.0'f32 + door.float32 * 1.7'f32) mod 3 == 0: 0.35'f32 else: 1.0'f32)
      let doorCol = Color(r: 255, g: 215, b: 110, a: a8(200.0 * flicker))
      drawRectangle(rect, Color(r: 255, g: 215, b: 110, a: a8(28.0 * flicker)))
      drawRectangleLines(rect, (if real: 3 else: 1), doorCol)
      let label = if door < labels.len: labels[door] else: ""
      let lx = rct.x + rct.w / 2
      let ly = if door == 0: rct.y + rct.h + 6 elif door == 2: rct.y - 20 else: rct.y + rct.h / 2 - 7
      let tx = if door == 1: rct.x - 6 - measureText(label, 14).float32 / 2 elif door == 3: rct.x + rct.w + 6 + measureText(label, 14).float32 / 2 else: lx
      centeredText(label, tx, ly, 14, doorCol)
    # The purge front sweeping out from the centre.
    let pr = lkgPurgeRadius(w)
    if pr > 1.0'f32 and not judging:
      drawCircle(v2(w.pos.x, w.pos.y), pr, Color(r: 150, g: 0, b: 60, a: 70))
      drawCircleLines(w.pos.x.int32, w.pos.y.int32, pr, Color(r: 255, g: 60, b: 120, a: 230))
      drawCircleLines(w.pos.x.int32, w.pos.y.int32, pr - 4.0'f32, Color(r: 255, g: 60, b: 120, a: 120))
    centeredText(localization.t(tkModeLastKnownGood), w.pos.x, LkgDoorDepth + 64.0'f32, 20, Color(r: 255, g: 215, b: 110, a: 255))
  else:
    discard
