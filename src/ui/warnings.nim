import types, random, particle_pool, boss_definitions, math, raylib
import particle_types

proc spawnThunderstrikeInto*(warnings: var seq[AttackWarning], particlePool: ParticlePool,
                             player: Player, screenWidth, screenHeight: int32,
                             enemy: Enemy, attack: BossAttack, phase: BossPhaseDefinition) =
  ## Thunderstrike: predictive telegraphed ground strikes
  let count  = max(1, attack.projectileCount)
  let radius = if attack.durationOrRadius > 0: attack.durationOrRadius else: 70.0'f32
  let dmg    = attack.damage * phase.damageMultiplier
  let total  = TeslaStrikeTelegraph + TeslaStrikeActive
  let w = screenWidth.float32
  let h = screenHeight.float32

  var predicted = player.pos + player.vel * (TeslaStrikeTelegraph * 0.7'f32)
  predicted.x = clamp(predicted.x, radius, w - radius)
  predicted.y = clamp(predicted.y, radius, h - radius)

  var positions = @[predicted]
  let minDist = radius + player.radius + 80.0'f32
  for k in 1 ..< count:
    var p = predicted
    var tries = 0
    while tries < 12:
      p = newVector2f(radius + rand(w - radius * 2.0),
                      radius + rand(h - radius * 2.0))
      inc tries
      if distance(p, player.pos) >= minDist: break
    positions.add(p)

  for p in positions:
    var w = newAttackWarning(p.x, p.y, awtTeslaStrike, total, enemy.id)
    w.targetPos = p
    w.bulletRadius = radius
    w.bulletDamage = dmg
    warnings.add(w)

  spawnExplosionPooled(particlePool, enemy.pos.x, enemy.pos.y,
                       Color(r: 255, g: 255, b: 150, a: 255), 16)

proc spawnVoidRiftsInto*(warnings: var seq[AttackWarning], particlePool: ParticlePool,
                         player: Player, screenWidth, screenHeight: int32,
                         enemy: Enemy, attack: BossAttack, phase: BossPhaseDefinition) =
  ## The Void Dancer's signature: tear N rifts in space. Each rift is telegraphed
  ## (a cracking purple tear + expanding danger ring) for the full wind-up, then
  ## collapses into a lethal zone that spits a slow radial spray of void bullets.
  ## Escalates by variant: void_rift -> void_rift_storm -> void_collapse. Mirrors
  ## the thunderstrike path (deferred strike resolved in game.nim's warning loop).
  let riftCount = case attack.specialData
    of "void_rift_storm": 3
    of "void_collapse":   3 + rand(1)   # 3-4 converging tears
    else:                 2             # "void_rift"
  let radius = if attack.durationOrRadius > 0: attack.durationOrRadius else: 90.0'f32
  let burst  = max(1, attack.projectileCount)
  let dmg    = attack.damage * phase.damageMultiplier
  let total  = VoidRiftTelegraph + VoidRiftActive
  let w = screenWidth.float32
  let h = screenHeight.float32

  # First rift tears open where the player is drifting toward; the rest scatter,
  # spaced so they can't all collapse onto the same spot.
  var predicted = player.pos + player.vel * (VoidRiftTelegraph * 0.35'f32)
  predicted.x = clamp(predicted.x, radius, w - radius)
  predicted.y = clamp(predicted.y, radius, h - radius)

  var positions = @[predicted]
  let minDist = radius + player.radius + 70.0'f32
  for k in 1 ..< riftCount:
    var p = predicted
    var tries = 0
    while tries < 12:
      p = newVector2f(radius + rand(w - radius * 2.0),
                      radius + rand(h - radius * 2.0))
      inc tries
      if distance(p, player.pos) >= minDist: break
    positions.add(p)

  for p in positions:
    var warn = newAttackWarning(p.x, p.y, awtVoidRift, total, enemy.id)
    warn.targetPos = p
    warn.bulletRadius = radius
    warn.bulletDamage = dmg
    warn.bulletCount = burst   # radial void bullets released when the rift collapses
    warn.bulletSpeed = if attack.projectileSpeed > 0: attack.projectileSpeed else: 150.0'f32
    warnings.add(warn)

  spawnExplosionPooled(particlePool, enemy.pos.x, enemy.pos.y,
                       Color(r: 150, g: 40, b: 220, a: 255), 16)

proc spawnArcLatticeInto*(warnings: var seq[AttackWarning], particlePool: ParticlePool,
                          screenWidth, screenHeight: int32,
                          enemy: Enemy, attack: BossAttack, phase: BossPhaseDefinition) =
  ## Arc lattice: radial beams with a safe wedge
  let beams = clamp(attack.projectileCount, 6, 16)
  let dmg   = attack.damage * phase.damageMultiplier
  let total = ArcBeamTelegraph + ArcBeamActive
  let w = screenWidth.float32
  let h = screenHeight.float32
  let thick = if attack.durationOrRadius > 0: attack.durationOrRadius else: 16.0'f32
  let cx = enemy.pos.x
  let cy = enemy.pos.y
  let reach = sqrt(w * w + h * h)
  let gapStart = rand(beams - 1)
  let gapSize = max(2, beams div 5)

  for k in 0 ..< beams:
    var inGap = false
    for g in 0 ..< gapSize:
      if (gapStart + g) mod beams == k: inGap = true
    if inGap: continue
    let ang = k.float32 * (PI * 2.0) / beams.float32
    var w = newAttackWarning(cx, cy, awtArcBeam, total, enemy.id)
    w.targetPos = newVector2f(cx + cos(ang) * reach, cy + sin(ang) * reach)
    w.laserLength = thick
    w.bulletDamage = dmg
    warnings.add(w)

  spawnExplosionPooled(particlePool, enemy.pos.x, enemy.pos.y,
                       Color(r: 255, g: 255, b: 150, a: 255), 16)

proc computeRicochetPath*(startPos, startDir: Vector2f, bounces: int,
                          screenWidth, screenHeight: int32): seq[Vector2f] =
  ## Trace a beam from startPos along startDir, reflecting off the four screen
  ## edges, recording a vertex at every bounce. Returns the polyline
  ## [start, hit1, hit2, ... , end]. Pure screen-edge reflection (no walls).
  const EPS = 0.05'f32
  let w = screenWidth.float32
  let h = screenHeight.float32
  var o = startPos
  var d = startDir.normalize()
  if d.length() < 0.0001'f32:
    d = newVector2f(1, 0)
  result = @[o]

  for _ in 0 .. bounces:
    # Distance to the next vertical edge (x = 0 or x = w) and horizontal edge.
    var bestT = 1.0e9'f32
    var normal = newVector2f(0, 0)

    if d.x > EPS:
      let t = (w - o.x) / d.x
      if t > EPS and t < bestT:
        bestT = t; normal = newVector2f(-1, 0)
    elif d.x < -EPS:
      let t = (0.0'f32 - o.x) / d.x
      if t > EPS and t < bestT:
        bestT = t; normal = newVector2f(1, 0)

    if d.y > EPS:
      let t = (h - o.y) / d.y
      if t > EPS and t < bestT:
        bestT = t; normal = newVector2f(0, -1)
    elif d.y < -EPS:
      let t = (0.0'f32 - o.y) / d.y
      if t > EPS and t < bestT:
        bestT = t; normal = newVector2f(0, 1)

    if bestT >= 1.0e9'f32:
      break  # Beam is parallel to and inside both axes (shouldn't happen)

    let hit = o + d * bestT
    result.add(hit)

    # Reflect the direction about the edge normal: d' = d - 2(d·n)n
    let dot = d.x * normal.x + d.y * normal.y
    d = newVector2f(d.x - 2.0'f32 * dot * normal.x,
                    d.y - 2.0'f32 * dot * normal.y).normalize()
    # Nudge off the surface so the next iteration doesn't re-hit the same edge.
    o = hit + d * EPS

proc spawnRicochetLaserInto*(warnings: var seq[AttackWarning], particlePool: ParticlePool,
                             player: Player, screenWidth, screenHeight: int32,
                             enemy: Enemy, attack: BossAttack, phase: BossPhaseDefinition) =
  ## The Laser Architect's signature beam: a single ray aimed at the player that
  ## ricochets off the screen edges many times, telegraphed for the full wind-up
  ## then lethal along its whole length for a short active flash.
  let bounces = if attack.projectileCount > 0: attack.projectileCount else: 20
  let dmg     = attack.damage * phase.damageMultiplier
  let total   = RicochetLaserTelegraph + RicochetLaserActive

  var aim = (player.pos - enemy.pos).normalize()
  if aim.length() < 0.0001'f32:
    aim = newVector2f(1, 0)

  let path = computeRicochetPath(enemy.pos, aim, bounces, screenWidth, screenHeight)

  # Lock the boss into a mega-cast channel for the whole wind-up + active beam:
  # it freezes in place (movement skipped), its other attacks pause, and it
  # hardens (MegaCastDamageTaken). The phase-transition-style freeze sells the
  # "charging an ultimate" beat.
  enemy.megaCastTimer = total
  enemy.megaCastTotal = total
  enemy.vel = newVector2f(0, 0)
  enemy.isDashing = false

  var w = newAttackWarning(enemy.pos.x, enemy.pos.y, awtRicochetLaser, total, enemy.id)
  w.targetPos = player.pos
  w.laserLength = RicochetLaserHalfWidth
  w.bulletDamage = dmg
  w.enemyType = enemy.enemyType
  w.ricochetPath = path
  warnings.add(w)

  spawnExplosionPooled(particlePool, enemy.pos.x, enemy.pos.y,
                       Color(r: 100, g: 220, b: 255, a: 255), 18)

proc spawnOrbitalSweepInto*(warnings: var seq[AttackWarning], particlePool: ParticlePool,
                            player: Player, screenWidth, screenHeight: int32,
                            enemy: Enemy, attack: BossAttack, phase: BossPhaseDefinition) =
  ## The Orbital Commander's signature: a kill-satellite enters off one screen
  ## edge and drags a screen-spanning energy wall across the WHOLE arena at
  ## constant speed. The wall has one safe data-gap; because the gap sits at a
  ## fixed offset along the wall, it traces a clear LANE down the arena - the
  ## telegraph paints the doomed band and that lane, then the wall physically
  ## sweeps through (position resolved by orbitalSweepCenter, shared with the
  ## hit test). Unlike every zone/beam attack in the game, the hazard MOVES:
  ## the dodge is "reach the lane before the wall reaches you".
  ## Volleys (projectileCount > 1) send extra walls on perpendicular headings,
  ## staggered via the extra-lifetime trick.
  let sweeps  = clamp(attack.projectileCount, 1, 3)
  # Multi-wall volleys widen every wall's safe lane (+35% per extra wall):
  # the crosswise follow-up already makes the dodge a two-step re-route, so
  # the gap compensates rather than stacking difficulty twice.
  let baseGapHalf = if attack.durationOrRadius > 0: attack.durationOrRadius else: 90.0'f32
  let gapHalf = baseGapHalf * (1.0'f32 + 0.35'f32 * (sweeps - 1).float32)
  let dmg     = attack.damage * phase.damageMultiplier
  let w = screenWidth.float32
  let h = screenHeight.float32
  const MARGIN = 60.0'f32  # wall starts/ends fully off-screen

  let baseHeading = rand(3)  # 0 right, 1 left, 2 down, 3 up
  for k in 0 ..< sweeps:
    # Follow-up walls turn 90 degrees so a volley rakes the arena crosswise.
    let heading = (baseHeading + k * (if sweeps > 1: 1 else: 0) * 2) mod 4
    var startC, endC: Vector2f
    var travelAngle: float32
    var halfSpan: float32
    case heading
    of 0:  # entering left edge, travelling right; wall is vertical
      startC = newVector2f(-MARGIN, h * 0.5'f32)
      endC   = newVector2f(w + MARGIN, h * 0.5'f32)
      travelAngle = 0.0'f32
      halfSpan = h * 0.5'f32 + MARGIN
    of 1:  # entering right edge, travelling left
      startC = newVector2f(w + MARGIN, h * 0.5'f32)
      endC   = newVector2f(-MARGIN, h * 0.5'f32)
      travelAngle = PI
      halfSpan = h * 0.5'f32 + MARGIN
    of 2:  # entering top edge, travelling down; wall is horizontal
      startC = newVector2f(w * 0.5'f32, -MARGIN)
      endC   = newVector2f(w * 0.5'f32, h + MARGIN)
      travelAngle = PI * 0.5'f32
      halfSpan = w * 0.5'f32 + MARGIN
    else:  # entering bottom edge, travelling up
      startC = newVector2f(w * 0.5'f32, h + MARGIN)
      endC   = newVector2f(w * 0.5'f32, -MARGIN)
      travelAngle = PI * 1.5'f32
      halfSpan = w * 0.5'f32 + MARGIN

    # The safe lane lands somewhere in the middle 70% of the wall, re-rolled a
    # few times if it sits on the player: the scan must force movement, never
    # reward standing still.
    let u = newVector2f(-sin(travelAngle), cos(travelAngle))  # along the wall
    let playerAlong = (player.pos.x - startC.x) * u.x + (player.pos.y - startC.y) * u.y
    var gapOffset = 0.0'f32
    for tries in 0 ..< 6:
      gapOffset = (rand(2.0'f32) - 1.0'f32) * halfSpan * 0.7'f32
      if abs(gapOffset - playerAlong) > gapHalf + 50.0'f32: break

    let total = OrbitalSweepTelegraph + OrbitalSweepActive + k.float32 * OrbitalSweepStagger
    var warn = newAttackWarning(startC.x, startC.y, awtOrbitalSweep, total, enemy.id)
    warn.targetPos = endC
    warn.bulletSpreadAngle = travelAngle
    warn.laserLength = OrbitalSweepHalfThick     # wall half-thickness
    warn.bulletRadius = gapHalf                  # safe-gap half-width
    warn.bulletSpeed = halfSpan                  # wall half-span along u
    warn.laserAngles = @[gapOffset]              # gap centre, offset along u
    warn.bulletDamage = dmg
    warnings.add(warn)

  spawnExplosionPooled(particlePool, enemy.pos.x, enemy.pos.y,
                       Color(r: 150, g: 100, b: 255, a: 255), 14)

proc spawnSeismicFissureInto*(warnings: var seq[AttackWarning], particlePool: ParticlePool,
                              player: Player, screenWidth, screenHeight: int32,
                              enemy: Enemy, attack: BossAttack, phase: BossPhaseDefinition) =
  ## The Berserker Juggernaut's signature: the ground cracks from the boss
  ## toward the player and erupts step by step - a marching chain of staggered
  ## detonations. Each step is its own warning whose extra lifetime IS the
  ## stagger, so the shared resolution logic (fires when lifetime <= Active)
  ## pops them in sequence without any bespoke timer.
  let steps  = clamp(attack.projectileCount, 3, 10)
  let radius = if attack.durationOrRadius > 0: attack.durationOrRadius else: 55.0'f32
  let dmg    = attack.damage * phase.damageMultiplier
  let w = screenWidth.float32
  let h = screenHeight.float32

  # Phase-3 variant ("seismic_fissure_chase"): instead of a fixed chain, one
  # persistent crack head is released that pursues the player for the rest of
  # the fight, dropping telegraphed eruptions under itself (game.nim drives
  # the pursuit + drops). Cast once: re-casts while a chaser lives are no-ops.
  if attack.specialData == "seismic_fissure_chase":
    for existing in warnings:
      if existing.attackType == awtFissureChaser and existing.sourceEnemyId == enemy.id:
        return
    var chaser = newAttackWarning(enemy.pos.x, enemy.pos.y, awtFissureChaser,
                                  99999.0'f32, enemy.id)
    chaser.bulletRadius = radius
    chaser.bulletDamage = dmg
    chaser.laserDuration = 0.9'f32  # repurposed: countdown to the next eruption drop
    warnings.add(chaser)
    spawnExplosionPooled(particlePool, enemy.pos.x, enemy.pos.y,
                         Color(r: 255, g: 90, b: 30, a: 255), 24)
    return

  # Aim where the player is HEADED, not where they stand: strafing at cast
  # time no longer trivially invalidates the whole chain.
  let lead = player.pos + player.vel * 0.35'f32
  var dir = (lead - enemy.pos).normalize()
  if dir.length() < 0.0001'f32:
    dir = newVector2f(1, 0)
  let spacing = radius * 1.45'f32

  # spreadAngle > 0 makes the chain FORK: the first two steps are shared, then
  # the crack splits into two branches at +/- half the spread, so a sideways
  # dodge away from one branch walks toward the other.
  let forkHalf = attack.spreadAngle * PI / 360.0'f32
  let baseAng = arctan2(dir.y, dir.x)
  var branchDirs = @[dir]
  if forkHalf > 0.001'f32:
    branchDirs = @[newVector2f(cos(baseAng - forkHalf), sin(baseAng - forkHalf)),
                   newVector2f(cos(baseAng + forkHalf), sin(baseAng + forkHalf))]

  var stepIdx = 0
  for k in 0 ..< steps:
    # Shared trunk for the first two steps, then one warning per branch.
    let dirs = if k < 2 or branchDirs.len == 1: @[dir] else: branchDirs
    for bd in dirs:
      var p = enemy.pos + bd * (enemy.radius + spacing * (k.float32 + 0.6'f32))
      p.x = clamp(p.x, radius * 0.5'f32, w - radius * 0.5'f32)
      p.y = clamp(p.y, radius * 0.5'f32, h - radius * 0.5'f32)
      let total = FissureTelegraph + FissureActive + k.float32 * FissureStagger
      var warn = newAttackWarning(p.x, p.y, awtFissure, total, enemy.id)
      warn.targetPos = p
      warn.bulletRadius = radius
      warn.bulletDamage = dmg
      warn.bulletCount = stepIdx  # step index, used by the render for the marching cue
      warnings.add(warn)
      stepIdx += 1

  spawnExplosionPooled(particlePool, enemy.pos.x, enemy.pos.y,
                       Color(r: 255, g: 90, b: 30, a: 255), 16)

proc spawnPrismRaysInto*(warnings: var seq[AttackWarning], particlePool: ParticlePool,
                         player: Player, screenWidth, screenHeight: int32,
                         enemy: Enemy, attack: BossAttack, phase: BossPhaseDefinition) =
  ## The Prism Architect's signature, a two-beat REFRACTION CASCADE. Beat one:
  ## the boss feeds a beam into a focal prism conjured beside the player, which
  ## splits it into a FINITE star of rays. Beat two: every ray end ignites a
  ## mini prism that re-splits the light one beat later, rippling around the
  ## ring — and no mini ray points back through the spent primary focus, so
  ## the dodge verb is: sidestep the star, then dive INTO its dark wake.
  ## Each star is its own warning; geometry rides ricochetPath as
  ## [origin, focus, rayEnd1, .., rayEndN] and bulletCount is the generation
  ## (0 = primary, 1 = mini; a mini's feed vertex is cosmetic, never lethal).
  let rays = clamp(attack.projectileCount, 3, 12)
  let dmg  = attack.damage * phase.damageMultiplier
  let w = screenWidth.float32
  let h = screenHeight.float32
  let reach = min(w, h) * 0.5'f32    # rays stop where the mini prisms ignite
  let miniReach = reach * 0.7'f32

  # Focus lands beside the player, not on them: the danger is the ray star,
  # and a slight offset keeps "stand still" from being an accidental safe spot.
  var focus = player.pos + player.vel * (PrismRayTelegraph * 0.3'f32)
  let sideAng = rand(1.0) * PI * 2.0
  focus = focus + newVector2f(cos(sideAng), sin(sideAng)) * 60.0'f32
  focus.x = clamp(focus.x, 80.0'f32, w - 80.0'f32)
  focus.y = clamp(focus.y, 80.0'f32, h - 80.0'f32)

  let baseAng = rand(1.0) * PI * 2.0
  let spacing = (PI * 2.0) / rays.float32
  var path = @[enemy.pos, focus]
  for k in 0 ..< rays:
    let ang = baseAng + k.float32 * spacing
    path.add(newVector2f(focus.x + cos(ang) * reach, focus.y + sin(ang) * reach))

  var warn = newAttackWarning(enemy.pos.x, enemy.pos.y, awtPrismRays,
                              PrismRayTelegraph + PrismRayActive, enemy.id)
  warn.targetPos = focus
  warn.laserLength = 14.0'f32  # beam half-width
  warn.bulletDamage = dmg
  warn.ricochetPath = path
  warnings.add(warn)

  # Beat two: mini prisms at the ray ends. Their stars fan out from the ring
  # (the half-spacing offset keeps every mini ray off the primary focus, so
  # the wake stays a true shelter) and their extra lifetime staggers the pops
  # into a ripple instead of one simultaneous wall of light. Both counts are
  # CAPPED below the primary's density: a 9-ray primary igniting 9 stars of
  # 7 rays saturated the arena — at most 6 minis (evenly picked ray ends) of
  # at most 5 rays keeps beat two dodgeable at every phase.
  let minis = min(rays, 6)
  let miniRays = clamp(rays - 2, 3, 5)
  let miniSpacing = (PI * 2.0) / miniRays.float32
  for m in 0 ..< minis:
    let k = (m * rays) div minis  # evenly spaced pick of ray ends
    var mf = path[2 + k]
    mf.x = clamp(mf.x, 30.0'f32, w - 30.0'f32)
    mf.y = clamp(mf.y, 30.0'f32, h - 30.0'f32)
    var mpath = @[focus, mf]
    let backAng = baseAng + k.float32 * spacing + PI  # from mini back to focus
    for j in 0 ..< miniRays:
      let ang = backAng + (j.float32 + 0.5'f32) * miniSpacing
      mpath.add(newVector2f(mf.x + cos(ang) * miniReach, mf.y + sin(ang) * miniReach))
    let total = PrismRayTelegraph + PrismRayActive + PrismMiniTelegraph +
                PrismRayActive + m.float32 * PrismMiniStagger
    var mw = newAttackWarning(mf.x, mf.y, awtPrismRays, total, enemy.id)
    mw.targetPos = mf
    mw.laserLength = 10.0'f32
    mw.bulletDamage = dmg
    mw.ricochetPath = mpath
    mw.bulletCount = 1  # generation: mini
    warnings.add(mw)

  spawnExplosionPooled(particlePool, enemy.pos.x, enemy.pos.y,
                       Color(r: 255, g: 200, b: 255, a: 255), 14)

proc spawnClockSweepInto*(warnings: var seq[AttackWarning], particlePool: ParticlePool,
                          player: Player, screenWidth, screenHeight: int32,
                          enemy: Enemy, attack: BossAttack, phase: BossPhaseDefinition) =
  ## The Timekeeper's signature: clock hands materialize around a fixed pivot
  ## (the boss's position at cast time) and sweep the arena while lethal. The
  ## player survives by rotating with a gap between hands. The hands' angle is
  ## a pure function of the warning's remaining lifetime, so the render
  ## (enemy.nim) and the hit test (game.nim) recompute it identically.
  let hands = clamp(attack.projectileCount, 2, 4)
  let dmg   = attack.damage * phase.damageMultiplier
  let total = ClockSweepTelegraph + ClockSweepActive
  let w = screenWidth.float32
  let h = screenHeight.float32

  var warn = newAttackWarning(enemy.pos.x, enemy.pos.y, awtClockSweep, total, enemy.id)
  warn.targetPos = enemy.pos                     # frozen pivot
  warn.laserCount = hands
  warn.laserLength = ClockSweepHalfWidth
  warn.bulletRadius = sqrt(w * w + h * h)        # beam reach: past every corner
  warn.bulletDamage = dmg
  warn.bulletSpreadAngle = rand(1.0'f32) * PI * 2.0'f32  # starting hand angle
  # Sweep speed: sign alternates per cast so the safe direction isn't rote.
  warn.bulletSpeed = (if attack.projectileSpeed > 0: attack.projectileSpeed.degToRad()
                      else: 0.7'f32) * (if rand(1) == 0: 1.0'f32 else: -1.0'f32)
  warnings.add(warn)

  spawnExplosionPooled(particlePool, enemy.pos.x, enemy.pos.y,
                       Color(r: 100, g: 240, b: 240, a: 255), 14)

proc spawnChaosWeaveInto*(warnings: var seq[AttackWarning], particlePool: ParticlePool,
                          player: Player, screenWidth, screenHeight: int32,
                          enemy: Enemy, attack: BossAttack, phase: BossPhaseDefinition) =
  ## The Chaos Weaver's signature: jagged threads of raw entropy are stitched
  ## across the whole arena, shimmer through the telegraph, then snap taut and
  ## lethal for a flash. Each thread is one warning holding its polyline in
  ## ricochetPath. Threads run roughly screen-edge to screen-edge with random
  ## kinks, and one thread is aimed through the player's vicinity.
  let threads = clamp(attack.projectileCount, 1, 4)
  let dmg   = attack.damage * phase.damageMultiplier
  let total = ChaosWeaveTelegraph + ChaosWeaveActive
  let w = screenWidth.float32
  let h = screenHeight.float32

  proc edgePoint(): Vector2f =
    case rand(3)
    of 0: newVector2f(rand(w), 0.0'f32)
    of 1: newVector2f(rand(w), h)
    of 2: newVector2f(0.0'f32, rand(h))
    else: newVector2f(w, rand(h))

  for t in 0 ..< threads:
    var a = edgePoint()
    var b = edgePoint()
    # Re-roll near-degenerate threads that hug a single edge.
    var tries = 0
    while distance(a, b) < min(w, h) * 0.6'f32 and tries < 8:
      b = edgePoint()
      inc tries
    if t == 0:
      # First thread threatens the player's area: pass near (not through) them.
      let jitterAng = rand(1.0) * PI * 2.0
      let mid = player.pos + newVector2f(cos(jitterAng), sin(jitterAng)) * 70.0'f32
      let dir = (b - a).normalize()
      a = mid - dir * max(w, h)
      b = mid + dir * max(w, h)
      a.x = clamp(a.x, 0.0'f32, w); a.y = clamp(a.y, 0.0'f32, h)
      b.x = clamp(b.x, 0.0'f32, w); b.y = clamp(b.y, 0.0'f32, h)

    # Kink the thread: subdivide and jitter perpendicular to the main run.
    const KINKS = 5
    let run = b - a
    let perp = newVector2f(-run.y, run.x).normalize()
    var path = @[a]
    for k in 1 .. KINKS:
      let along = a + run * (k.float32 / (KINKS + 1).float32)
      path.add(along + perp * (rand(120.0'f32) - 60.0'f32))
    path.add(b)

    var warn = newAttackWarning(a.x, a.y, awtChaosWeave, total, enemy.id)
    warn.targetPos = b
    warn.laserLength = 9.0'f32  # thread half-width
    warn.bulletDamage = dmg
    warn.ricochetPath = path
    warnings.add(warn)

  spawnExplosionPooled(particlePool, enemy.pos.x, enemy.pos.y,
                       Color(r: 255, g: 80, b: 255, a: 255), 16)

proc spawnOmegaQuadrantsInto*(warnings: var seq[AttackWarning], particlePool: ParticlePool,
                              player: Player, screenWidth, screenHeight: int32,
                              enemy: Enemy, attack: BossAttack, phase: BossPhaseDefinition) =
  ## The Omega Entity's finale: a mega-cast "judgement" that detonates three of
  ## the four screen quadrants in sequence, sparing exactly one - the player
  ## must read the order and hop through the safe pocket. Like seismic
  ## fissures, the per-quadrant stagger is encoded as extra lifetime so the
  ## shared resolution logic fires them in order. The boss channels (frozen,
  ## hardened, other attacks paused) for the entire sequence.
  let dmg = attack.damage * phase.damageMultiplier
  let w = screenWidth.float32
  let h = screenHeight.float32
  let halfExt = newVector2f(w * 0.25'f32, h * 0.25'f32)
  let centers = [
    newVector2f(w * 0.25'f32, h * 0.25'f32),  # top-left
    newVector2f(w * 0.75'f32, h * 0.25'f32),  # top-right
    newVector2f(w * 0.25'f32, h * 0.75'f32),  # bottom-left
    newVector2f(w * 0.75'f32, h * 0.75'f32)]  # bottom-right

  # The spared quadrant is the one the player currently occupies - the attack
  # chases them OUT of the other three, it never spawns as an unavoidable hit.
  var safe = 0
  if player.pos.x >= w * 0.5'f32: safe += 1
  if player.pos.y >= h * 0.5'f32: safe += 2

  var order: seq[int] = @[]
  for q in 0 ..< 4:
    if q != safe: order.add(q)
  # Shuffle the eruption order so the sequence must be read each cast.
  for k in countdown(order.high, 1):
    let j = rand(k)
    swap(order[k], order[j])

  var slot = 0
  for q in order:
    let total = OmegaQuadTelegraph + OmegaQuadActive + slot.float32 * OmegaQuadStagger
    var warn = newAttackWarning(centers[q].x, centers[q].y, awtOmegaQuadrant, total, enemy.id)
    warn.targetPos = halfExt          # rect half-extents (hit test is an AABB check)
    warn.bulletDamage = dmg
    warn.bulletCount = slot           # eruption index, drawn as the sequence number
    warnings.add(warn)
    inc slot

  # Channel for the full sequence: frozen, hardened, other attacks paused
  # (same mega-cast contract as the Laser Architect's ricochet beam).
  let castTotal = OmegaQuadTelegraph + OmegaQuadActive +
                  (order.len - 1).float32 * OmegaQuadStagger
  enemy.megaCastTimer = castTotal
  enemy.megaCastTotal = castTotal
  enemy.vel = newVector2f(0, 0)
  enemy.isDashing = false

  spawnExplosionPooled(particlePool, enemy.pos.x, enemy.pos.y,
                       Color(r: 255, g: 60, b: 90, a: 255), 20)

proc addBossAttackWarningInto*(warnings: var seq[AttackWarning], player: Player,
                               enemy: Enemy, attack: BossAttack) =
  const WARNING_DURATION = 0.45'f32

  if attack.specialData in ["thunderstrike", "arc_lattice"]:
    return
  if attack.attackType in [bapLaser, bapTeleport, bapMeteor]:
    return
  # Snipe shots come from the boss's orbital satellites; with none alive the
  # attack itself is skipped (execBossAttackSnipe), so skip the reticle too.
  if attack.attackType == bapSnipe and enemy.satellites.len == 0:
    return

  let warningType = case attack.attackType
    of bapDash:    awtBossDash
    of bapBurst:   awtBossBurst
    of bapCircle:  awtBossCircle
    of bapSpiral:  awtBossSpiral
    of bapBarrage: awtBossBarrage
    of bapPulse:   awtBossPulse
    of bapChain:   awtBossChain
    of bapWave:    awtBossWave
    of bapSummon:  awtBossSummon
    of bapSnipe:   awtLaserPointer
    else:          return

  let warningTargetPos =
    if attack.attackType == bapDash:
      let toPlayer = player.pos - enemy.pos
      let d = sqrt(toPlayer.x * toPlayer.x + toPlayer.y * toPlayer.y)
      let dir = if d > 0.01: newVector2f(toPlayer.x / d, toPlayer.y / d)
                else: newVector2f(1.0'f32, 0.0'f32)
      let dashDist = case attack.specialData
        of "charge_attack": 350.0'f32
        of "double_charge": 300.0'f32
        of "rage_charge":   280.0'f32
        else:               350.0'f32
      newVector2f(enemy.pos.x + dir.x * dashDist, enemy.pos.y + dir.y * dashDist)
    else:
      player.pos

  if attack.attackType == bapDash:
    enemy.pendingDashLocked = true
    enemy.pendingDashStart = enemy.pos
    enemy.pendingDashTarget = warningTargetPos
    enemy.vel = newVector2f(0, 0)

  # The snipe reticle belongs ON the target: drawn at the boss it read as a
  # random marker that "did nothing". Other warnings stay boss-anchored.
  let warnPos =
    if attack.attackType == bapDash: enemy.pendingDashStart
    elif attack.attackType == bapSnipe: warningTargetPos
    else: enemy.pos
  var w = newAttackWarning(warnPos.x, warnPos.y, warningType, WARNING_DURATION, enemy.id)
  w.targetPos = warningTargetPos
  warnings.add(w)
