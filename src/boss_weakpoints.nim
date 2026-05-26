import math, random, raylib, types

const TwoPi = PI * 2.0

type
  BossWeakPointHitResult* = object
    hit*: bool
    exposed*: bool
    wrongTarget*: bool
    completed*: bool
    bonusDamage*: float32
    pos*: Vector2f

proc effectiveWeakKind(enemy: Enemy): BossWeakObjectiveKind =
  if not enemy.isBoss:
    return bwoNone

  if enemy.weakPoint.kind == bwoOmegaCycle:
    case enemy.currentPhaseIndex
    of 0: bwoSpiralAnchors
    of 1: bwoVoidRifts
    of 2: bwoPrismSequence
    else: bwoChaosAnomalies
  else:
    enemy.weakPoint.kind

proc weakPointCoreRadius*(enemy: Enemy): float32 =
  max(18.0'f32, enemy.radius * 0.35'f32)

proc initBossWeakPointState*(spec: BossWeakPointDefinition, bossId: int): BossWeakPointState =
  result.enabled = spec.kind != bwoNone
  result.kind = spec.kind
  result.targets = @[]
  result.progress = 0
  result.required = max(1, spec.requiredHits)
  result.sequenceIndex = 0
  result.exposedTimer = 0
  result.cooldownTimer = if result.enabled: 0.8'f32 else: 0
  result.pulseTimer = bossId.float32 * 0.37'f32
  result.bodyDamageMultiplier = spec.bodyDamageMultiplier
  result.weakCoreMultiplier = spec.weakCoreMultiplier
  result.exposureDuration = spec.exposureDuration
  result.cooldownDuration = spec.cooldownDuration
  result.targetHitRadius = spec.targetHitRadius
  result.phaseIndex = 0
  result.lastDashActive = false
  result.omegaWindowsCompleted = 0
  result.realTargetIndex = -1
  result.lastBossPos = newVector2f(0, 0)

proc resetBossWeakPointForPhase*(enemy: Enemy, spec: BossWeakPointDefinition,
                                 phaseIndex: int, delay: float32 = 0.6'f32) =
  if not enemy.isBoss:
    return

  enemy.weakPoint.enabled = spec.kind != bwoNone
  enemy.weakPoint.kind = spec.kind
  enemy.weakPoint.targets = @[]
  enemy.weakPoint.progress = 0
  enemy.weakPoint.required = max(1, spec.requiredHits)
  enemy.weakPoint.sequenceIndex = 0
  enemy.weakPoint.exposedTimer = 0
  enemy.weakPoint.cooldownTimer = delay
  enemy.weakPoint.bodyDamageMultiplier =
    if spec.kind == bwoOmegaCycle and phaseIndex >= 3: 0.25'f32
    else: spec.bodyDamageMultiplier
  enemy.weakPoint.weakCoreMultiplier = spec.weakCoreMultiplier
  enemy.weakPoint.exposureDuration = spec.exposureDuration
  enemy.weakPoint.cooldownDuration = spec.cooldownDuration
  enemy.weakPoint.targetHitRadius = spec.targetHitRadius
  enemy.weakPoint.phaseIndex = phaseIndex
  enemy.weakPoint.lastDashActive = enemy.isDashing
  enemy.weakPoint.omegaWindowsCompleted = 0
  enemy.weakPoint.realTargetIndex = -1
  enemy.weakPoint.lastBossPos = enemy.pos

proc targetTint(kind: BossWeakObjectiveKind, idx: int, active, decoy: bool): Color =
  var color = case kind
    of bwoMeteorCracks, bwoDashBackPlate:
      Color(r: 255, g: 145, b: 45, a: 255)
    of bwoLaserPrisms, bwoPrismSequence:
      case idx mod 3
      of 0: Color(r: 80, g: 220, b: 255, a: 255)
      of 1: Color(r: 255, g: 90, b: 220, a: 255)
      else: Color(r: 255, g: 235, b: 80, a: 255)
    of bwoVoidRifts:
      if decoy: Color(r: 120, g: 80, b: 180, a: 255)
      else: Color(r: 210, g: 80, b: 255, a: 255)
    of bwoCoilSequence:
      if idx mod 2 == 0: Color(r: 255, g: 235, b: 80, a: 255)
      else: Color(r: 80, g: 210, b: 255, a: 255)
    of bwoClockNodes:
      Color(r: 120, g: 255, b: 245, a: 255)
    of bwoChaosAnomalies, bwoOmegaCycle:
      Color(r: 255, g: uint8(80 + (idx * 55) mod 150), b: 255, a: 255)
    else:
      Color(r: 255, g: 220, b: 80, a: 255)

  if not active:
    color.a = 110
  color

proc clampTargetPos(pos: Vector2f, screenWidth, screenHeight: int32, margin: float32): Vector2f =
  newVector2f(
    clamp(pos.x, margin, screenWidth.float32 - margin),
    clamp(pos.y, margin, screenHeight.float32 - margin)
  )

proc addTarget(enemy: Enemy, kind: BossWeakObjectiveKind, idx: int, pos: Vector2f,
               angle, orbitRadius, orbitSpeed, life: float32,
               active: bool, decoy: bool, relativeToBoss: bool) =
  enemy.weakPoint.targets.add(BossWeakPointTarget(
    pos: pos,
    angle: angle,
    orbitRadius: orbitRadius,
    orbitSpeed: orbitSpeed,
    hitRadius: enemy.weakPoint.targetHitRadius,
    life: life,
    maxLife: life,
    index: idx,
    active: active,
    hit: false,
    decoy: decoy,
    relativeToBoss: relativeToBoss,
    color: targetTint(kind, idx, active, decoy)
  ))

proc spawnOrbitTargets(enemy: Enemy, kind: BossWeakObjectiveKind, count: int,
                       orbitRadius, orbitSpeed: float32, sequence: bool,
                       angleOffset: float32 = 0.0'f32) =
  enemy.weakPoint.targets = @[]
  enemy.weakPoint.realTargetIndex = -1
  let safeCount = max(1, count)
  for i in 0..<safeCount:
    let angle = angleOffset + enemy.weakPoint.pulseTimer * 0.35'f32 +
                i.float32 * TwoPi.float32 / safeCount.float32
    let active = (not sequence) or i == enemy.weakPoint.sequenceIndex
    let pos = enemy.pos + newVector2f(cos(angle) * orbitRadius, sin(angle) * orbitRadius)
    addTarget(enemy, kind, i, pos, angle, orbitRadius, orbitSpeed, 0, active, false, true)

proc spawnStaticTargets(enemy: Enemy, kind: BossWeakObjectiveKind, count: int,
                        playerPos: Vector2f, screenWidth, screenHeight: int32,
                        life: float32) =
  enemy.weakPoint.targets = @[]
  enemy.weakPoint.realTargetIndex = -1
  let safeCount = max(1, count)
  for i in 0..<safeCount:
    let angle = enemy.weakPoint.pulseTimer * 0.9'f32 + i.float32 * TwoPi.float32 / safeCount.float32
    let center = if i mod 2 == 0: playerPos else: enemy.pos
    let offset = newVector2f(cos(angle) * 95.0'f32, sin(angle) * 72.0'f32)
    let pos = clampTargetPos(center + offset, screenWidth, screenHeight, 48.0'f32)
    addTarget(enemy, kind, i, pos, angle, 0, 0, life, true, false, false)

proc spawnVoidRifts(enemy: Enemy, playerPos: Vector2f, screenWidth, screenHeight: int32) =
  enemy.weakPoint.targets = @[]
  let count = max(3, enemy.weakPoint.required + 2)
  enemy.weakPoint.realTargetIndex = rand(count - 1)
  for i in 0..<count:
    let angle = enemy.weakPoint.pulseTimer * 1.1'f32 + i.float32 * TwoPi.float32 / count.float32
    let center = (enemy.pos + playerPos) * 0.5'f32
    let pos = clampTargetPos(center + newVector2f(cos(angle) * 130.0'f32,
                                                 sin(angle) * 90.0'f32),
                             screenWidth, screenHeight, 48.0'f32)
    addTarget(enemy, bwoVoidRifts, i, pos, angle, 0, 0, 4.0'f32,
              true, i != enemy.weakPoint.realTargetIndex, false)

proc spawnBackPlate(enemy: Enemy, playerPos: Vector2f) =
  enemy.weakPoint.targets = @[]
  var away = enemy.vel.normalize()
  if away.length() < 0.01'f32:
    away = (enemy.pos - playerPos).normalize()
  if away.length() < 0.01'f32:
    away = newVector2f(1, 0)

  let angle = arctan2(away.y, away.x)
  let orbitRadius = enemy.radius * 0.62'f32
  let pos = enemy.pos + away * orbitRadius
  addTarget(enemy, bwoDashBackPlate, 0, pos, angle, orbitRadius, 0, 2.8'f32,
            true, false, true)

proc syncTargetActivity(enemy: Enemy, kind: BossWeakObjectiveKind) =
  if enemy.weakPoint.targets.len == 0:
    return

  if kind == bwoClockNodes:
    enemy.weakPoint.sequenceIndex =
      (floor(enemy.weakPoint.pulseTimer / 1.15'f32).int) mod enemy.weakPoint.targets.len

  for target in enemy.weakPoint.targets.mitems:
    if target.hit:
      target.active = false
    else:
      target.active = case kind
        of bwoSpiralAnchors, bwoCoilSequence, bwoPrismSequence, bwoClockNodes:
          target.index == enemy.weakPoint.sequenceIndex
        else:
          true
    target.color = targetTint(kind, target.index, target.active, target.decoy)

proc weakPointCompletionDamage(enemy: Enemy, kind: BossWeakObjectiveKind): float32 =
  let pct = case kind
    of bwoSpiralAnchors: 0.020'f32
    of bwoSummonSigils: 0.030'f32
    of bwoMeteorCracks: 0.040'f32
    of bwoLaserPrisms: 0.026'f32
    of bwoVoidRifts: 0.050'f32
    of bwoCoilSequence: 0.035'f32
    of bwoSatelliteSet: 0.0'f32
    of bwoDashBackPlate: 0.055'f32
    of bwoPrismSequence: 0.045'f32
    of bwoClockNodes: 0.032'f32
    of bwoChaosAnomalies: 0.038'f32
    of bwoOmegaCycle: 0.045'f32
    else: 0.0'f32
  max(0.0'f32, enemy.maxHp * pct)

proc weakPointVulnerabilityDuration(enemy: Enemy, kind: BossWeakObjectiveKind): float32 =
  case kind
  of bwoSpiralAnchors: 1.5'f32
  of bwoSummonSigils: 2.2'f32
  of bwoMeteorCracks: 0.0'f32
  of bwoLaserPrisms: 2.8'f32
  of bwoVoidRifts: 1.5'f32
  of bwoCoilSequence: 1.8'f32
  of bwoSatelliteSet: 3.6'f32
  of bwoDashBackPlate: 1.25'f32
  of bwoPrismSequence: 2.0'f32
  of bwoClockNodes: 2.5'f32
  of bwoChaosAnomalies: 1.75'f32
  of bwoOmegaCycle: max(1.2'f32, enemy.weakPoint.exposureDuration * 0.7'f32)
  else: 0.0'f32

proc openVulnerabilityWindow(enemy: Enemy, duration: float32) =
  enemy.weakPoint.exposedTimer = duration
  enemy.weakPoint.cooldownTimer = 0
  enemy.weakPoint.targets = @[]
  enemy.weakPoint.progress = 0
  enemy.weakPoint.sequenceIndex = 0
  enemy.weakPoint.omegaWindowsCompleted = 0
  enemy.weakPoint.realTargetIndex = -1

proc completeObjectiveHit(enemy: Enemy): tuple[completed: bool, bonusDamage: float32] =
  enemy.weakPoint.progress += 1
  if enemy.weakPoint.progress < enemy.weakPoint.required:
    enemy.weakPoint.sequenceIndex = min(enemy.weakPoint.sequenceIndex + 1, max(0, enemy.weakPoint.required - 1))
    return (false, 0.0'f32)

  if enemy.weakPoint.kind == bwoOmegaCycle and enemy.currentPhaseIndex >= 3 and
     enemy.weakPoint.omegaWindowsCompleted < 1:
    enemy.weakPoint.omegaWindowsCompleted += 1
    enemy.weakPoint.targets = @[]
    enemy.weakPoint.progress = 0
    enemy.weakPoint.sequenceIndex = 0
    enemy.weakPoint.cooldownTimer = 0.45'f32
    return (false, 0.0'f32)

  let kind = effectiveWeakKind(enemy)
  let bonusDamage = weakPointCompletionDamage(enemy, kind)
  let vulnerableDuration = weakPointVulnerabilityDuration(enemy, kind)
  if vulnerableDuration > 0:
    openVulnerabilityWindow(enemy, vulnerableDuration)
  else:
    enemy.weakPoint.targets = @[]
    enemy.weakPoint.progress = 0
    enemy.weakPoint.sequenceIndex = 0
    enemy.weakPoint.cooldownTimer = enemy.weakPoint.cooldownDuration
  (true, bonusDamage)

proc resetSequencePenalty(enemy: Enemy) =
  enemy.weakPoint.progress = 0
  enemy.weakPoint.sequenceIndex = 0
  for target in enemy.weakPoint.targets.mitems:
    target.hit = false
  enemy.weakPoint.cooldownTimer = 0.2'f32

proc updateTargetPositions(enemy: Enemy, dt: float32) =
  var i = 0
  while i < enemy.weakPoint.targets.len:
    if enemy.weakPoint.targets[i].maxLife > 0:
      enemy.weakPoint.targets[i].life -= dt
      if enemy.weakPoint.targets[i].life <= 0:
        enemy.weakPoint.targets.delete(i)
        continue

    if enemy.weakPoint.targets[i].relativeToBoss:
      enemy.weakPoint.targets[i].angle += enemy.weakPoint.targets[i].orbitSpeed * dt
      let angle = enemy.weakPoint.targets[i].angle
      let orbitRadius = enemy.weakPoint.targets[i].orbitRadius
      enemy.weakPoint.targets[i].pos =
        enemy.pos + newVector2f(cos(angle) * orbitRadius, sin(angle) * orbitRadius)
    i += 1

proc updateBossWeakPoint*(enemy: Enemy, spec: BossWeakPointDefinition, playerPos: Vector2f,
                          screenWidth, screenHeight: int32, dt: float32) =
  if not enemy.isBoss or not enemy.weakPoint.enabled:
    return

  enemy.weakPoint.pulseTimer += dt
  updateTargetPositions(enemy, dt)

  if enemy.weakPoint.exposedTimer > 0:
    enemy.weakPoint.exposedTimer = max(0.0'f32, enemy.weakPoint.exposedTimer - dt)
    if enemy.weakPoint.exposedTimer <= 0:
      enemy.weakPoint.cooldownTimer = enemy.weakPoint.cooldownDuration
    enemy.weakPoint.lastBossPos = enemy.pos
    enemy.weakPoint.lastDashActive = enemy.isDashing
    return

  if enemy.weakPoint.cooldownTimer > 0:
    enemy.weakPoint.cooldownTimer = max(0.0'f32, enemy.weakPoint.cooldownTimer - dt)

  let kind = effectiveWeakKind(enemy)
  if kind == bwoNone or enemy.invulnerabilityTimer > 0 or enemy.weakPoint.cooldownTimer > 0:
    enemy.weakPoint.lastBossPos = enemy.pos
    enemy.weakPoint.lastDashActive = enemy.isDashing
    return

  if kind == bwoSatelliteSet:
    if enemy.satellites.len > 0 and enemy.weakPoint.progress == 0:
      enemy.weakPoint.required = max(1, enemy.satellites.len)
    enemy.weakPoint.lastBossPos = enemy.pos
    enemy.weakPoint.lastDashActive = enemy.isDashing
    return

  if kind == bwoDashBackPlate:
    if enemy.weakPoint.lastDashActive and not enemy.isDashing and enemy.weakPoint.targets.len == 0:
      spawnBackPlate(enemy, playerPos)
    enemy.weakPoint.lastBossPos = enemy.pos
    enemy.weakPoint.lastDashActive = enemy.isDashing
    syncTargetActivity(enemy, kind)
    return

  if enemy.weakPoint.targets.len == 0:
    enemy.weakPoint.required = max(1, spec.requiredHits)
    let targetCount = max(1, spec.targetCount)
    case kind
    of bwoSpiralAnchors:
      spawnOrbitTargets(enemy, kind, targetCount, enemy.radius * 0.92'f32, 1.35'f32, true)
    of bwoSummonSigils:
      spawnOrbitTargets(enemy, kind, targetCount, enemy.radius * 1.20'f32, -0.65'f32, false)
    of bwoMeteorCracks:
      spawnStaticTargets(enemy, kind, targetCount, playerPos, screenWidth, screenHeight, 4.2'f32)
    of bwoLaserPrisms:
      spawnOrbitTargets(enemy, kind, targetCount, enemy.radius * 1.45'f32, 0.18'f32, false, PI.float32 / 4.0'f32)
    of bwoVoidRifts:
      spawnVoidRifts(enemy, playerPos, screenWidth, screenHeight)
    of bwoCoilSequence:
      spawnOrbitTargets(enemy, kind, targetCount, enemy.radius * 1.05'f32, 0.95'f32, true)
    of bwoPrismSequence:
      spawnOrbitTargets(enemy, kind, targetCount, enemy.radius * 1.28'f32, 0.42'f32, true)
    of bwoClockNodes:
      spawnOrbitTargets(enemy, kind, targetCount, enemy.radius * 1.18'f32, -0.28'f32, true)
    of bwoChaosAnomalies:
      spawnStaticTargets(enemy, kind, targetCount, playerPos, screenWidth, screenHeight, 3.8'f32)
    else:
      discard

  syncTargetActivity(enemy, kind)
  enemy.weakPoint.lastBossPos = enemy.pos
  enemy.weakPoint.lastDashActive = enemy.isDashing

proc resolveBossWeakPointTargetHit*(enemy: Enemy, bulletPos: Vector2f,
                                    bulletRadius: float32): BossWeakPointHitResult =
  result.pos = bulletPos
  if not enemy.isBoss or not enemy.weakPoint.enabled or enemy.weakPoint.exposedTimer > 0:
    return

  let kind = effectiveWeakKind(enemy)
  if kind == bwoNone:
    return

  for i in 0..<enemy.weakPoint.targets.len:
    var target = enemy.weakPoint.targets[i]
    if target.hit:
      continue

    if distance(bulletPos, target.pos) <= bulletRadius + target.hitRadius:
      result.hit = true
      result.pos = target.pos

      if kind == bwoVoidRifts and target.decoy:
        enemy.weakPoint.targets[i].hit = true
        enemy.weakPoint.cooldownTimer = 0.25'f32
        result.wrongTarget = true
        return

      if kind in [bwoSpiralAnchors, bwoCoilSequence, bwoPrismSequence, bwoClockNodes] and
         target.index != enemy.weakPoint.sequenceIndex:
        result.wrongTarget = true
        if kind == bwoPrismSequence:
          resetSequencePenalty(enemy)
        return

      enemy.weakPoint.targets[i].hit = true
      let completion = completeObjectiveHit(enemy)
      result.completed = completion.completed
      result.bonusDamage = completion.bonusDamage
      return

proc registerBossSatelliteDestroyed*(enemy: Enemy): float32 =
  if not enemy.isBoss or not enemy.weakPoint.enabled:
    return 0.0'f32

  if enemy.invulnerabilityTimer > 0 or enemy.weakPoint.exposedTimer > 0 or
     effectiveWeakKind(enemy) != bwoSatelliteSet:
    return 0.0'f32

  if enemy.weakPoint.required <= 1:
    enemy.weakPoint.required = max(1, enemy.satellites.len)
  let completion = completeObjectiveHit(enemy)
  completion.bonusDamage

proc registerBossSummonDestroyed*(enemy: Enemy): float32 =
  if not enemy.isBoss or not enemy.weakPoint.enabled:
    return 0.0'f32

  if enemy.invulnerabilityTimer > 0 or enemy.weakPoint.exposedTimer > 0 or
     effectiveWeakKind(enemy) != bwoSummonSigils:
    return 0.0'f32

  let completion = completeObjectiveHit(enemy)
  completion.bonusDamage

proc bossWeakPointCoreHit*(enemy: Enemy, bulletPos: Vector2f, bulletRadius: float32): bool =
  false

proc bossWeakPointDamageMultiplier*(enemy: Enemy, source: BossWeakDamageSource): float32 =
  if not enemy.isBoss or not enemy.weakPoint.enabled:
    return 1.0'f32

  if enemy.weakPoint.exposedTimer > 0:
    return max(1.0'f32, enemy.weakPoint.weakCoreMultiplier)

  max(0.05'f32, enemy.weakPoint.bodyDamageMultiplier)

proc drawBossWeakPoints*(enemy: Enemy, showHints: bool = true) =
  if not enemy.isBoss or not enemy.weakPoint.enabled:
    return

  let time = getTime().float32
  let pulse = sin(time * 7.0'f32) * 0.5'f32 + 0.5'f32

  if enemy.weakPoint.exposedTimer > 0:
    let ringRadius = enemy.radius + 10.0'f32 + pulse * 5.0'f32
    let alpha = uint8(clamp(90.0'f32 + pulse * 95.0'f32, 0.0'f32, 220.0'f32))
    let color = Color(r: 255, g: 235, b: 90, a: alpha)
    drawCircleLines(enemy.pos.x.int32, enemy.pos.y.int32, ringRadius, color)
    drawCircleLines(enemy.pos.x.int32, enemy.pos.y.int32, ringRadius + 8.0'f32,
                    Color(r: 255, g: 255, b: 255, a: alpha div 3))
    return

  for target in enemy.weakPoint.targets:
    if target.hit:
      continue

    let activeAlpha = if target.active: uint8(220) else: uint8(90)
    var color = target.color
    color.a = activeAlpha
    let ringRadius = target.hitRadius * (0.72'f32 + pulse * 0.12'f32)
    drawCircle(Vector2(x: target.pos.x, y: target.pos.y), max(5.0'f32, ringRadius * 0.35'f32),
               Color(r: color.r, g: color.g, b: color.b, a: activeAlpha div 3))
    drawCircleLines(target.pos.x.int32, target.pos.y.int32, ringRadius, color)
    drawLine(Vector2(x: target.pos.x - 6.0'f32, y: target.pos.y),
             Vector2(x: target.pos.x + 6.0'f32, y: target.pos.y), 2.0'f32,
             Color(r: 255, g: 255, b: 255, a: activeAlpha))
    drawLine(Vector2(x: target.pos.x, y: target.pos.y - 6.0'f32),
             Vector2(x: target.pos.x, y: target.pos.y + 6.0'f32), 2.0'f32,
             Color(r: 255, g: 255, b: 255, a: activeAlpha))

    if showHints:
      drawCircleLines(target.pos.x.int32, target.pos.y.int32, target.hitRadius + 5.0'f32,
                      Color(r: color.r, g: color.g, b: color.b, a: activeAlpha div 4))

  if showHints and enemy.weakPoint.required > 1:
    let pipRadius = 3.5'f32
    let totalWidth = enemy.weakPoint.required.float32 * 10.0'f32
    let startX = enemy.pos.x - totalWidth * 0.5'f32
    let y = enemy.pos.y + enemy.radius + 14.0'f32
    for i in 0..<enemy.weakPoint.required:
      let filled = i < enemy.weakPoint.progress
      let pipColor = if filled:
        Color(r: 255, g: 235, b: 80, a: 220)
      else:
        Color(r: 120, g: 120, b: 130, a: 120)
      drawCircle(Vector2(x: startX + i.float32 * 10.0'f32, y: y), pipRadius, pipColor)
