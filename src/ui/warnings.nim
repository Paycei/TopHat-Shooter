import random, math, raylib
import types, particle_pool, boss_definitions, particle_types

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
    var farEnough = false
    while tries < 12:
      p = newVector2f(radius + rand(w - radius * 2.0),
                      radius + rand(h - radius * 2.0))
      inc tries
      if distance(p, player.pos) >= minDist:
        farEnough = true
        break
    if not farEnough:
      # Fail closed (mirrors the boss-teleport warnings): push the last roll out
      # to the legal ring instead of accepting a strike on top of the player.
      var away = p - player.pos
      if away.x == 0 and away.y == 0:
        away = newVector2f(1.0'f32, 0.0'f32)
      p = player.pos + away.normalize() * minDist
      p.x = clamp(p.x, radius, w - radius)
      p.y = clamp(p.y, radius, h - radius)
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
    var farEnough = false
    while tries < 12:
      p = newVector2f(radius + rand(w - radius * 2.0),
                      radius + rand(h - radius * 2.0))
      inc tries
      if distance(p, player.pos) >= minDist:
        farEnough = true
        break
    if not farEnough:
      # Fail closed (mirrors the boss-teleport warnings): push the last roll out
      # to the legal ring instead of collapsing a rift on top of the player.
      var away = p - player.pos
      if away.x == 0 and away.y == 0:
        away = newVector2f(1.0'f32, 0.0'f32)
      p = player.pos + away.normalize() * minDist
      p.x = clamp(p.x, radius, w - radius)
      p.y = clamp(p.y, radius, h - radius)
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
  # Heading offsets per wall in a volley. +2 is the perpendicular axis (the
  # order is right/left/down/up, so stepping by 2 changes axis); +1 reverses
  # the current axis. So a 3-wall volley reads rake -> crosswise -> reverse
  # rake, three distinct entry edges instead of repeating the first.
  const HEADING_OFFSETS = [0, 2, 1]
  for k in 0 ..< sweeps:
    let heading = (baseHeading + (if sweeps > 1: HEADING_OFFSETS[k] else: 0)) mod 4
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
  ## ring, and no mini ray points back through the spent primary focus, so
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
  # 7 rays saturated the arena, at most 6 minis (evenly picked ray ends) of
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
  # Sweep variants, flagged via laserPattern for clockSweepHandAngle:
  # "rewind" (phase 3) - mid-sweep freeze, then the sweep reverses faster and
  # the cast ends with a 12-ray chime. "tick" (phase 2) - escapement mode,
  # the hands snap forward in discrete jerks.
  if attack.specialData == "clock_sweep_rewind":
    warn.laserPattern = "rewind"
  elif attack.specialData == "clock_sweep_tick":
    warn.laserPattern = "tick"
  warnings.add(warn)

  spawnExplosionPooled(particlePool, enemy.pos.x, enemy.pos.y,
                       Color(r: 100, g: 240, b: 240, a: 255), 14)

proc spawnChaosWeaveInto*(warnings: var seq[AttackWarning], particlePool: ParticlePool,
                          player: Player, screenWidth, screenHeight: int32,
                          enemy: Enemy, attack: BossAttack, phase: BossPhaseDefinition) =
  ## The Chaos Weaver's signature: jagged threads of raw entropy are stitched
  ## across the whole arena by a visible needle, pull taut, then snap lethal
  ## IN STITCH ORDER (per-thread stagger encoded as extra lifetime, like the
  ## fissure march). Each thread is one warning holding its polyline in
  ## ricochetPath. Threads run roughly screen-edge to screen-edge with random
  ## kinks, and one thread is aimed through the player's vicinity. Where two
  ## threads cross, a "knot" warning (laserPattern = "knot", empty path) is
  ## pinned: after the last thread snaps, the knots tear open into slow radial
  ## bullet rings - the weave's finale. Knot count is hard-capped.
  let threads = clamp(attack.projectileCount, 1, 4)
  let dmg   = attack.damage * phase.damageMultiplier
  let w = screenWidth.float32
  let h = screenHeight.float32

  proc edgePoint(): Vector2f =
    case rand(3)
    of 0: newVector2f(rand(w), 0.0'f32)
    of 1: newVector2f(rand(w), h)
    of 2: newVector2f(0.0'f32, rand(h))
    else: newVector2f(w, rand(h))

  proc segIntersect(a1, a2, b1, b2: Vector2f): (bool, Vector2f) =
    ## Proper segment-segment intersection; endpoints (outer 5%) excluded so
    ## knots never land exactly on a shared vertex.
    let r = a2 - a1
    let s = b2 - b1
    let denom = r.x * s.y - r.y * s.x
    if abs(denom) < 0.0001'f32: return (false, newVector2f(0, 0))
    let qp = b1 - a1
    let ti = (qp.x * s.y - qp.y * s.x) / denom
    let u = (qp.x * r.y - qp.y * r.x) / denom
    if ti < 0.05'f32 or ti > 0.95'f32 or u < 0.05'f32 or u > 0.95'f32:
      return (false, newVector2f(0, 0))
    (true, a1 + r * ti)

  var threadPaths: seq[seq[Vector2f]] = @[]
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

    # Stitch order = spawn order: thread t outlives thread t-1 by the stagger,
    # so the shared "fires when lifetime <= Active" resolution snaps them in
    # sequence with no bespoke timer.
    let total = ChaosWeaveTelegraph + ChaosWeaveActive + t.float32 * ChaosWeaveStagger
    var warn = newAttackWarning(a.x, a.y, awtChaosWeave, total, enemy.id)
    warn.targetPos = b
    warn.laserLength = 9.0'f32  # thread half-width
    warn.bulletDamage = dmg
    warn.ricochetPath = path
    warnings.add(warn)
    threadPaths.add(path)

  # Knots: pin a marker wherever two threads cross (deduped, hard-capped).
  # They tear open shortly after the LAST thread snaps.
  var knots: seq[Vector2f] = @[]
  for i in 0 ..< threadPaths.len:
    for j in i + 1 ..< threadPaths.len:
      for si in 0 ..< threadPaths[i].len - 1:
        for sj in 0 ..< threadPaths[j].len - 1:
          let (hit, p) = segIntersect(threadPaths[i][si], threadPaths[i][si + 1],
                                      threadPaths[j][sj], threadPaths[j][sj + 1])
          if hit:
            var tooClose = false
            for k in knots:
              if distance(k, p) < 60.0'f32:
                tooClose = true
                break
            if not tooClose:
              knots.add(p)
  if knots.len > ChaosKnotMax:
    # Keep an even spread of the crossings rather than the first N.
    var picked: seq[Vector2f] = @[]
    for n in 0 ..< ChaosKnotMax:
      picked.add(knots[(n * knots.len) div ChaosKnotMax])
    knots = picked

  let lastThreadTotal = ChaosWeaveTelegraph + ChaosWeaveActive +
                        (threads - 1).float32 * ChaosWeaveStagger
  for kp in knots:
    var knot = newAttackWarning(kp.x, kp.y, awtChaosWeave,
                                lastThreadTotal + ChaosKnotDelay, enemy.id)
    knot.laserPattern = "knot"     # empty ricochetPath: thread draw/hit skip it
    knot.bulletCount = ChaosKnotBullets
    knot.bulletSpeed = ChaosKnotBulletSpeed
    knot.bulletDamage = dmg * 0.6'f32
    warnings.add(knot)

  spawnExplosionPooled(particlePool, enemy.pos.x, enemy.pos.y,
                       Color(r: 255, g: 80, b: 255, a: 255), 16)

proc spawnOmegaQuadrantsInto*(warnings: var seq[AttackWarning], particlePool: ParticlePool,
                              player: Player, screenWidth, screenHeight: int32,
                              enemy: Enemy, attack: BossAttack, phase: BossPhaseDefinition,
                              lesson: bool = false) =
  ## The Omega Entity's judgement: the shelter HOPS. Every beat all grid cells
  ## but one erupt, and the surviving gold-marked shelter is a different,
  ## edge-adjacent cell each beat, so the player must migrate every beat while
  ## dodging the ember ring the vacated shelter fires after them. Movement
  ## between cells is FREE (no seam hazards); the beat pressure is the trial.
  ## After the last hop the final shelter is itself judged.
  ##
  ## Like seismic fissures, beat timing is encoded as extra lifetime so the
  ## shared resolution logic fires everything in order; laserLength carries each
  ## warning's telegraph SHOW window so only the upcoming beat is drawn.
  ##
  ## The boss channels (frozen, hardened, other attacks paused) throughout, and
  ## because it is frozen the cell its body stands over can NEVER be picked as a
  ## shelter - contact damage would make that pocket unsurvivable.
  ##
  ## `lesson` (Beta/Gamma phases, specialData "omega_judgement_lesson") is the
  ## rehearsal: identical rules on the four big quadrants (OmegaLessonGrid),
  ## fewer hops and a slower heartbeat, before the Omega phase runs the trial at
  ## full tempo on the OmegaJudgeGrid 3x3.
  let beats = if lesson: OmegaLessonBeats else: OmegaQuadBeats
  let stagger = if lesson: OmegaLessonStagger else: OmegaQuadStagger
  let grid = if lesson: OmegaLessonGrid else: OmegaJudgeGrid
  let dmg = attack.damage * phase.damageMultiplier
  let w = screenWidth.float32
  let h = screenHeight.float32
  let cellW = w / grid.float32
  let cellH = h / grid.float32
  let halfExt = newVector2f(cellW * 0.5'f32, cellH * 0.5'f32)

  proc centerOf(cell: (int, int)): Vector2f =
    newVector2f((cell[0].float32 + 0.5'f32) * cellW,
                (cell[1].float32 + 0.5'f32) * cellH)

  proc cellOf(p: Vector2f): (int, int) =
    (clamp(int(p.x / cellW), 0, grid - 1), clamp(int(p.y / cellH), 0, grid - 1))

  # The frozen boss squats on this cell for the whole channel - it is banned
  # from ever being the shelter.
  let bossCell = cellOf(enemy.pos)

  # The chain starts where the player stands - beat one erupts it, so the
  # first move is forced immediately (during the opening telegraph).
  var prev = cellOf(player.pos)
  var shelter = prev
  for beat in 1 .. beats:
    # Next shelter: edge-adjacent to the current one (never diagonal, so
    # every hop crosses a single border) and never the boss's cell. Corner
    # cells have two neighbours and the boss occupies at most one, so there
    # is always a candidate.
    var cands: seq[(int, int)] = @[]
    for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)]:
      let n = (shelter[0] + dx, shelter[1] + dy)
      if n[0] < 0 or n[0] >= grid or n[1] < 0 or n[1] >= grid: continue
      if n == bossCell: continue
      cands.add(n)
    shelter = cands[rand(cands.high)]
    let popAt = OmegaQuadTelegraph + (beat - 1).float32 * stagger
    # Telegraphs appear one beat ahead (the whole opening window for beat 1).
    let showWindow = if beat == 1: OmegaQuadTelegraph else: stagger

    # Every doomed cell of this beat.
    for cx in 0 ..< grid:
      for cy in 0 ..< grid:
        if (cx, cy) == shelter: continue
        let c = centerOf((cx, cy))
        var warn = newAttackWarning(c.x, c.y, awtOmegaQuadrant,
                                    popAt + OmegaQuadActive, enemy.id)
        warn.targetPos = halfExt      # rect half-extents (hit test is an AABB check)
        warn.bulletDamage = dmg
        warn.laserLength = showWindow
        if (cx, cy) == prev:
          # The vacated shelter erupts as the "chase": it alone hurls embers
          # and carries the beat's screen shake (density guard: one ring/beat).
          warn.laserPattern = "chase"
        warnings.add(warn)

    # Gold shelter marker: non-lethal "BE HERE" guide, expiring at the beat.
    let sc = centerOf(shelter)
    var mark = newAttackWarning(sc.x, sc.y, awtOmegaQuadrant, popAt, enemy.id)
    mark.targetPos = halfExt
    mark.laserPattern = "shelter"
    mark.laserLength = showWindow
    warnings.add(mark)
    prev = shelter

  # THE SHELTERED ARE JUDGED LAST: one beat after the final hop, the last
  # shelter itself detonates in gold - a full stagger to break out into
  # already-spent ground.
  let sparedPop = OmegaQuadTelegraph + beats.float32 * stagger
  let fc = centerOf(shelter)
  var sparedWarn = newAttackWarning(fc.x, fc.y, awtOmegaQuadrant,
                                    sparedPop + OmegaQuadActive, enemy.id)
  sparedWarn.targetPos = halfExt
  sparedWarn.bulletDamage = dmg
  sparedWarn.laserLength = stagger
  sparedWarn.laserPattern = "spared"
  warnings.add(sparedWarn)

  # Channel for the full sequence: frozen, hardened, other attacks paused
  # (same mega-cast contract as the Laser Architect's ricochet beam).
  # The gold judgement of the final shelter is the last event.
  let castTotal = sparedPop + OmegaQuadActive
  enemy.megaCastTimer = castTotal
  enemy.megaCastTotal = castTotal
  enemy.vel = newVector2f(0, 0)
  enemy.isDashing = false

  # Cast opening: judgement sparks bloom at every cell's heart.
  spawnExplosionPooled(particlePool, enemy.pos.x, enemy.pos.y,
                       Color(r: 255, g: 60, b: 90, a: 255), 20)
  # Every cell blooms red: nowhere is spared for long. The gold shelter
  # marker (drawn per beat) is the only promise of safety.
  for cx in 0 ..< grid:
    for cy in 0 ..< grid:
      let c = centerOf((cx, cy))
      spawnExplosionPooled(particlePool, c.x, c.y,
                           Color(r: 255, g: 70, b: 100, a: 255),
                           (if lesson: 8 else: 4))

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
