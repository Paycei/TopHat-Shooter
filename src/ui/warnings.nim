import types, random, particle_pool, boss_definitions, math, raylib

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
    warnings.add(AttackWarning(
      pos: p, targetPos: p,
      attackType: "tesla_strike",
      lifetime: total, maxLifetime: total,
      sourceEnemyId: enemy.id,
      laserAngles: @[],
      bulletRadius: radius,
      bulletDamage: dmg,
      bulletsCreated: false,
      lasersCreated: false
    ))

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
    warnings.add(AttackWarning(
      pos: newVector2f(cx, cy),
      targetPos: newVector2f(cx + cos(ang) * reach, cy + sin(ang) * reach),
      attackType: "arc_beam", lifetime: total, maxLifetime: total,
      sourceEnemyId: enemy.id, laserAngles: @[],
      laserLength: thick, bulletDamage: dmg,
      bulletsCreated: false, lasersCreated: false))

  spawnExplosionPooled(particlePool, enemy.pos.x, enemy.pos.y,
                       Color(r: 255, g: 255, b: 150, a: 255), 16)

proc addBossAttackWarningInto*(warnings: var seq[AttackWarning], player: Player,
                               enemy: Enemy, attack: BossAttack) =
  const WARNING_DURATION = 0.45'f32

  if attack.specialData in ["thunderstrike", "arc_lattice"]:
    return
  if attack.attackType in [bapLaser, bapTeleport, bapMeteor]:
    return

  let warningType = case attack.attackType
    of bapDash:    "boss_dash"
    of bapBurst:   "boss_burst"
    of bapCircle:  "boss_circle"
    of bapSpiral:  "boss_spiral"
    of bapBarrage: "boss_barrage"
    of bapPulse:   "boss_pulse"
    of bapChain:   "boss_chain"
    of bapWave:    "boss_wave"
    of bapSummon:  "boss_summon"
    of bapSnipe:   "laser_pointer"
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

  warnings.add(AttackWarning(
    pos:                  if attack.attackType == bapDash: enemy.pendingDashStart else: enemy.pos,
    attackType:           warningType,
    lifetime:             WARNING_DURATION,
    maxLifetime:          WARNING_DURATION,
    sourceEnemyId:        enemy.id,
    laserAngles:          @[],
    targetPos:            warningTargetPos,
    bulletsCreated:       false,
    isBossTeleportTarget: false
  ))
