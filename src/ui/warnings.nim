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

proc addBossAttackWarningInto*(warnings: var seq[AttackWarning], player: Player,
                               enemy: Enemy, attack: BossAttack) =
  const WARNING_DURATION = 0.45'f32

  if attack.specialData in ["thunderstrike", "arc_lattice"]:
    return
  if attack.attackType in [bapLaser, bapTeleport, bapMeteor]:
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

  let warnPos = if attack.attackType == bapDash: enemy.pendingDashStart else: enemy.pos
  var w = newAttackWarning(warnPos.x, warnPos.y, warningType, WARNING_DURATION, enemy.id)
  w.targetPos = warningTargetPos
  warnings.add(w)
