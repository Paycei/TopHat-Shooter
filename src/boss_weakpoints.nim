import math, random, raylib
import types

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
  ## Spawn 3 cracked armour-plate shards in a fan on the Juggernaut's back,
  ## exposed after a dash ends.  Centre shard + two flanking shards ±32°.
  enemy.weakPoint.targets = @[]
  enemy.weakPoint.realTargetIndex = -1

  # Direction pointing away from the player = boss's back
  var away = enemy.vel.normalize()
  if away.length() < 0.01'f32:
    away = (enemy.pos - playerPos).normalize()
  if away.length() < 0.01'f32:
    away = newVector2f(1, 0)

  let baseAngle = arctan2(away.y, away.x)
  let orbitR    = enemy.radius * 0.72'f32  # a bit further out for visibility
  let life      = 2.8'f32
  # Centre shard, left flank (~32°), right flank (~-32°)
  let offsets   = [0.0'f32, 0.56'f32, -0.56'f32]

  for i in 0..<3:
    let a   = baseAngle + offsets[i]
    let pos = enemy.pos + newVector2f(cos(a) * orbitR, sin(a) * orbitR)
    addTarget(enemy, bwoDashBackPlate, i, pos, a, orbitR, 0.0'f32, life,
              true, false, true)

proc syncTargetActivity(enemy: Enemy, kind: BossWeakObjectiveKind) =
  if enemy.weakPoint.targets.len == 0:
    return

  if kind == bwoClockNodes:
    enemy.weakPoint.sequenceIndex =
      (floor(enemy.weakPoint.pulseTimer / 1.15'f32).int) mod enemy.weakPoint.targets.len

  for target in enemy.weakPoint.targets.mitems:
    let wasActive = target.active
    if target.hit:
      target.active = false
    else:
      target.active = case kind
        of bwoSpiralAnchors, bwoCoilSequence, bwoPrismSequence, bwoClockNodes:
          target.index == enemy.weakPoint.sequenceIndex
        else:
          true
    # Grace window: when a sequential target first lights up, briefly widen its hitbox
    if not wasActive and target.active and
       kind in {bwoSpiralAnchors, bwoCoilSequence, bwoPrismSequence, bwoClockNodes}:
      target.activeGraceTimer = 0.38'f32
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
  # Completion burst scaled up alongside the heavier body resistance so a player
  # who actually does the mechanic kills the boss in ~the same time as before.
  const CompletionBurstScale = 1.4'f32
  max(0.0'f32, enemy.maxHp * pct * CompletionBurstScale)

proc weakPointVulnerabilityDuration(enemy: Enemy, kind: BossWeakObjectiveKind): float32 =
  case kind
  of bwoSpiralAnchors:   1.8'f32   # was 1.5 – extra window to spend damage
  of bwoSummonSigils:    2.4'f32   # was 2.2
  of bwoMeteorCracks:    0.0'f32   # no window – damage comes from crack hits
  of bwoLaserPrisms:     2.8'f32
  of bwoVoidRifts:       2.0'f32   # was 1.5 – reward for picking the real rift
  of bwoCoilSequence:    2.0'f32   # was 1.8
  of bwoSatelliteSet:    3.6'f32
  of bwoDashBackPlate:   1.4'f32   # was 1.25 – slightly more generous
  of bwoPrismSequence:   2.0'f32
  of bwoClockNodes:      2.8'f32   # was 2.5 – timing is hard, reward it
  of bwoChaosAnomalies:  1.9'f32   # was 1.75
  of bwoOmegaCycle:      max(1.4'f32, enemy.weakPoint.exposureDuration * 0.7'f32)
  else: 0.0'f32

proc openVulnerabilityWindow(enemy: Enemy, duration: float32) =
  enemy.weakPoint.exposedTimer     = duration
  enemy.weakPoint.exposureDuration = duration   # snapshot so draw arc has the true max
  enemy.weakPoint.cooldownTimer    = 0
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
        # Ignoring a weak-point target (letting it expire unhit) lets the boss
        # recover a little. Secondary pressure, not a main mechanic - decoys
        # (void-rift fakes) don't count, since hitting them is the wrong play.
        const HEAL_ON_TARGET_IGNORE_FRAC = 0.012'f32
        if not enemy.weakPoint.targets[i].hit and not enemy.weakPoint.targets[i].decoy and
           enemy.hp > 0:
          enemy.ignoreHealPending += enemy.maxHp * HEAL_ON_TARGET_IGNORE_FRAC
        enemy.weakPoint.targets.delete(i)
        continue

    # Tick visual / mechanical flash timers
    if enemy.weakPoint.targets[i].wrongHitFlash > 0:
      enemy.weakPoint.targets[i].wrongHitFlash =
        max(0.0'f32, enemy.weakPoint.targets[i].wrongHitFlash - dt)
    if enemy.weakPoint.targets[i].hitFlashTimer > 0:
      enemy.weakPoint.targets[i].hitFlashTimer =
        max(0.0'f32, enemy.weakPoint.targets[i].hitFlashTimer - dt)
    if enemy.weakPoint.targets[i].activeGraceTimer > 0:
      enemy.weakPoint.targets[i].activeGraceTimer =
        max(0.0'f32, enemy.weakPoint.targets[i].activeGraceTimer - dt)

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

  if kind == bwoSummonSigils:
    # Summoner King: the objective is to destroy the boss's summoned adds, not to
    # shoot orbiting targets. The wave is tracked in game.nim (required/progress
    # derived from the live add count); clearing it opens the window via
    # openBossSummonWindow. Spawn no orbit targets here.
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

    let effectiveRadius = target.hitRadius +
      (if target.activeGraceTimer > 0.0'f32: target.hitRadius * 0.28'f32 else: 0.0'f32)
    if distance(bulletPos, target.pos) <= bulletRadius + effectiveRadius:
      result.hit = true
      result.pos = target.pos

      if kind == bwoVoidRifts and target.decoy:
        enemy.weakPoint.targets[i].hit = true
        enemy.weakPoint.targets[i].wrongHitFlash = 0.45'f32
        enemy.weakPoint.cooldownTimer = 0.65'f32   # raised from 0.25 – punishes decoy hits more
        result.wrongTarget = true
        return

      if kind in [bwoSpiralAnchors, bwoCoilSequence, bwoPrismSequence, bwoClockNodes] and
         target.index != enemy.weakPoint.sequenceIndex:
        enemy.weakPoint.targets[i].wrongHitFlash = 0.45'f32
        result.wrongTarget = true
        if kind == bwoPrismSequence:
          resetSequencePenalty(enemy)
        else:
          # Small micro-cooldown: hitting out-of-order stalls the next spawn briefly
          enemy.weakPoint.cooldownTimer = max(enemy.weakPoint.cooldownTimer, 0.22'f32)
        return

      enemy.weakPoint.targets[i].hit = true
      enemy.weakPoint.targets[i].hitFlashTimer = 0.30'f32   # triggers burst ring in draw
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

proc openBossSummonWindow*(enemy: Enemy): tuple[opened: bool, bonusDamage: float32] =
  ## Called when the Summoner King's current summoned wave is fully cleared.
  ## Opens the vulnerability window directly (no orbit targets / per-hit progress),
  ## which is what makes this boss's objective distinct: clear the adds, not the sigils.
  if not enemy.isBoss or not enemy.weakPoint.enabled:
    return (false, 0.0'f32)
  if effectiveWeakKind(enemy) != bwoSummonSigils:
    return (false, 0.0'f32)
  if enemy.invulnerabilityTimer > 0 or enemy.weakPoint.exposedTimer > 0 or
     enemy.weakPoint.cooldownTimer > 0:
    return (false, 0.0'f32)

  let bonusDamage = weakPointCompletionDamage(enemy, bwoSummonSigils)
  let dur = weakPointVulnerabilityDuration(enemy, bwoSummonSigils)
  openVulnerabilityWindow(enemy, dur)
  (true, bonusDamage)

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

  let time      = getTime().float32
  let pulse     = sin(time * 7.0'f32) * 0.5'f32 + 0.5'f32
  let slowPulse = sin(time * 3.5'f32) * 0.5'f32 + 0.5'f32
  let kind      = effectiveWeakKind(enemy)

  # Cooldown arc: clockwise fill shows when next window opens
  # Drawn at all times so the player always knows the rhythm.
  if showHints and enemy.weakPoint.cooldownTimer > 0 and
     enemy.weakPoint.exposedTimer <= 0 and kind != bwoNone:
    let pct   = 1.0'f32 - (enemy.weakPoint.cooldownTimer /
                            max(0.01'f32, enemy.weakPoint.cooldownDuration))
    let arcR  = enemy.radius + 17.0'f32
    drawCircleLines(enemy.pos.x.int32, enemy.pos.y.int32, arcR,
                    Color(r: 50, g: 50, b: 50, a: 45))
    if pct > 0.015'f32:
      let segs    = max(4, int(pct * 44.0'f32))
      let arcSpan = pct * TwoPi.float32
      let startA  = -(PI.float32 * 0.5'f32)   # starts at the top
      let arcCol  = Color(r: 220, g: 200, b: 55,
                          a: uint8(95 + int(slowPulse * 55.0'f32)))
      for s in 0..<segs:
        let a1 = startA + s.float32 * arcSpan / segs.float32
        let a2 = startA + (s + 1).float32 * arcSpan / segs.float32
        drawLine(Vector2(x: enemy.pos.x + cos(a1) * arcR, y: enemy.pos.y + sin(a1) * arcR),
                 Vector2(x: enemy.pos.x + cos(a2) * arcR, y: enemy.pos.y + sin(a2) * arcR),
                 2.8'f32, arcCol)

  # Vulnerability window 
  if enemy.weakPoint.exposedTimer > 0:
    let tLeft   = enemy.weakPoint.exposedTimer / max(0.01'f32, enemy.weakPoint.exposureDuration)
    let nearEnd = tLeft < 0.28'f32
    let fastP   = abs(sin(time * 11.0'f32))
    let alpha   = if nearEnd: uint8(clamp(155.0'f32 + fastP * 95.0'f32,  0.0'f32, 255.0'f32))
                  else:       uint8(clamp(130.0'f32 + pulse * 85.0'f32,  0.0'f32, 255.0'f32))

    case kind
    of bwoDashBackPlate:
      # Berserker: spinning blood-red cog/gear (existing, kept as-is)
      let toothCount = 8
      let innerR    = enemy.radius + 8.0'f32 + slowPulse * 4.0'f32
      let outerR    = innerR + 14.0'f32 + pulse * 6.0'f32
      let spinAngle = time * 2.5'f32
      let coreCol   = Color(r: 220, g: 30,  b: 30,  a: alpha)
      let rimCol    = Color(r: 255, g: 80,  b: 0,   a: alpha)
      let glowCol   = Color(r: 255, g: 60,  b: 0,   a: alpha div 4)
      drawCircleLines(enemy.pos.x.int32, enemy.pos.y.int32, outerR + 10.0'f32, glowCol)
      drawCircleLines(enemy.pos.x.int32, enemy.pos.y.int32, outerR + 6.0'f32,  glowCol)
      for t in 0..<toothCount * 2:
        let a    = spinAngle + t.float32 * PI / toothCount.float32
        let rEnd = if t mod 2 == 0: outerR else: (innerR + outerR) * 0.5'f32
        drawLine(Vector2(x: enemy.pos.x + cos(a) * innerR, y: enemy.pos.y + sin(a) * innerR),
                 Vector2(x: enemy.pos.x + cos(a) * rEnd,   y: enemy.pos.y + sin(a) * rEnd),
                 if t mod 2 == 0: 3.5'f32 else: 1.8'f32, rimCol)
      drawCircleLines(enemy.pos.x.int32, enemy.pos.y.int32, innerR, coreCol)
      drawCircle(Vector2(x: enemy.pos.x, y: enemy.pos.y), innerR * 0.85'f32,
                 Color(r: 255, g: 40, b: 0,
                       a: uint8(clamp(40.0'f32 + pulse * 50.0'f32, 0.0'f32, 100.0'f32))))

    of bwoSpiralAnchors, bwoOmegaCycle:
      # Spiral Guardian / Omega: spinning vortex rings
      let col  = Color(r: 150, g: 75, b: 255, a: alpha)
      let r1   = enemy.radius + 9.0'f32 + slowPulse * 5.0'f32
      let r2   = r1 + 14.0'f32
      let spin = time * 3.2'f32
      drawCircleLines(enemy.pos.x.int32, enemy.pos.y.int32, r1, col)
      drawCircleLines(enemy.pos.x.int32, enemy.pos.y.int32, r2,
                      Color(r: col.r, g: col.g, b: col.b, a: alpha div 2))
      for s in 0..<4:
        let a = spin + s.float32 * PI * 0.5'f32
        drawLine(Vector2(x: enemy.pos.x + cos(a) * r1, y: enemy.pos.y + sin(a) * r1),
                 Vector2(x: enemy.pos.x + cos(a) * r2, y: enemy.pos.y + sin(a) * r2),
                 2.5'f32, col)
      drawCircle(Vector2(x: enemy.pos.x, y: enemy.pos.y), r1,
                 Color(r: col.r, g: col.g, b: col.b, a: alpha div 6))

    of bwoSummonSigils:
      # Summoner King: rotating hexagram sigil
      let col  = Color(r: 75, g: 215, b: 110, a: alpha)
      let r    = enemy.radius + 12.0'f32 + slowPulse * 5.0'f32
      let spin = time * 0.75'f32
      for tri in 0..<2:
        let off  = tri.float32 * PI / 3.0'f32 + spin
        var prev = Vector2(x: enemy.pos.x + cos(off) * r, y: enemy.pos.y + sin(off) * r)
        for v in 1..3:
          let a    = off + v.float32 * TwoPi.float32 / 3.0'f32
          let curr = Vector2(x: enemy.pos.x + cos(a) * r, y: enemy.pos.y + sin(a) * r)
          drawLine(prev, curr, 2.5'f32, col)
          prev = curr
      drawCircleLines(enemy.pos.x.int32, enemy.pos.y.int32, r + 7.0'f32,
                      Color(r: col.r, g: col.g, b: col.b, a: alpha div 3))
      drawCircle(Vector2(x: enemy.pos.x, y: enemy.pos.y), r,
                 Color(r: col.r, g: col.g, b: col.b, a: alpha div 8))

    of bwoMeteorCracks:
      # Meteor Striker: radiating crack lines
      let col = Color(r: 255, g: 130, b: 35, a: alpha)
      let r   = enemy.radius + 10.0'f32 + pulse * 8.0'f32
      for c in 0..<8:
        let a   = c.float32 * PI / 4.0'f32 + time * 0.25'f32
        let len = if c mod 2 == 0: r + 15.0'f32 else: r + 5.0'f32
        let jit = if c mod 3 == 1: 0.14'f32 else: 0.0'f32
        drawLine(Vector2(x: enemy.pos.x + cos(a + jit) * (r - 5.0'f32),
                         y: enemy.pos.y + sin(a + jit) * (r - 5.0'f32)),
                 Vector2(x: enemy.pos.x + cos(a) * len, y: enemy.pos.y + sin(a) * len),
                 if c mod 2 == 0: 3.0'f32 else: 1.5'f32, col)
      drawCircleLines(enemy.pos.x.int32, enemy.pos.y.int32, r, col)
      drawCircle(Vector2(x: enemy.pos.x, y: enemy.pos.y), r,
                 Color(r: col.r, g: col.g, b: col.b, a: alpha div 8))

    of bwoLaserPrisms, bwoPrismSequence:
      # Laser Architect / Prism Architect: rainbow arc segments
      let r        = enemy.radius + 10.0'f32 + slowPulse * 5.0'f32
      let spin     = time * 1.6'f32
      let pCols    = [ Color(r: 255, g: 60,  b: 60,  a: alpha),
                       Color(r: 255, g: 180, b: 60,  a: alpha),
                       Color(r: 60,  g: 255, b: 80,  a: alpha),
                       Color(r: 60,  g: 200, b: 255, a: alpha),
                       Color(r: 160, g: 60,  b: 255, a: alpha),
                       Color(r: 255, g: 60,  b: 200, a: alpha) ]
      for s in 0..<6:
        let a1 = spin + s.float32 * TwoPi.float32 / 6.0'f32
        let a2 = spin + (s.float32 + 0.82'f32) * TwoPi.float32 / 6.0'f32
        drawLine(Vector2(x: enemy.pos.x + cos(a1) * r, y: enemy.pos.y + sin(a1) * r),
                 Vector2(x: enemy.pos.x + cos(a2) * r, y: enemy.pos.y + sin(a2) * r),
                 3.8'f32, pCols[s])
      drawCircleLines(enemy.pos.x.int32, enemy.pos.y.int32, r + 8.0'f32,
                      Color(r: 200, g: 200, b: 255, a: alpha div 3))
      drawCircle(Vector2(x: enemy.pos.x, y: enemy.pos.y), r,
                 Color(r: 200, g: 200, b: 255, a: alpha div 10))

    of bwoVoidRifts:
      # Void Dancer: imploding counter-rotating rings
      let col  = Color(r: 205, g: 55, b: 255, a: alpha)
      let r1   = enemy.radius + 8.0'f32 + pulse * 10.0'f32
      let r2   = r1 + 13.0'f32
      let spin = -time * 2.1'f32   # counter-clockwise = implosion feel
      drawCircleLines(enemy.pos.x.int32, enemy.pos.y.int32, r1, col)
      drawCircleLines(enemy.pos.x.int32, enemy.pos.y.int32, r2,
                      Color(r: col.r, g: col.g, b: col.b, a: alpha div 2))
      for s in 0..<6:
        let a = spin + s.float32 * TwoPi.float32 / 6.0'f32
        drawLine(Vector2(x: enemy.pos.x + cos(a) * r1, y: enemy.pos.y + sin(a) * r1),
                 Vector2(x: enemy.pos.x + cos(a) * r2, y: enemy.pos.y + sin(a) * r2),
                 2.2'f32, col)
      drawCircle(Vector2(x: enemy.pos.x, y: enemy.pos.y), r1,
                 Color(r: col.r, g: col.g, b: col.b, a: alpha div 8))

    of bwoCoilSequence:
      # Chain Reactor: spinning double-arc coil discharge
      let col  = Color(r: 255, g: 240, b: 58, a: alpha)
      let r    = enemy.radius + 10.0'f32 + slowPulse * 5.0'f32
      let spin = time * 4.2'f32
      for arc in 0..<2:
        let dir = if arc == 0: 1.0'f32 else: -1.0'f32
        let sa  = spin * dir + arc.float32 * PI
        let ea  = sa + PI * 0.80'f32
        let sg  = 18
        for s in 0..<sg:
          let a1 = sa + s.float32 * (ea - sa) / sg.float32
          let a2 = sa + (s + 1).float32 * (ea - sa) / sg.float32
          drawLine(Vector2(x: enemy.pos.x + cos(a1) * r, y: enemy.pos.y + sin(a1) * r),
                   Vector2(x: enemy.pos.x + cos(a2) * r, y: enemy.pos.y + sin(a2) * r),
                   3.0'f32, col)
      drawCircle(Vector2(x: enemy.pos.x, y: enemy.pos.y), r,
                 Color(r: col.r, g: col.g, b: col.b, a: alpha div 7))

    of bwoSatelliteSet:
      # Orbital Commander: glowing orbit rings
      let col = Color(r: 175, g: 115, b: 255, a: alpha)
      let r   = enemy.radius + 12.0'f32 + slowPulse * 4.0'f32
      drawCircleLines(enemy.pos.x.int32, enemy.pos.y.int32, r, col)
      drawCircleLines(enemy.pos.x.int32, enemy.pos.y.int32, r + 10.0'f32,
                      Color(r: col.r, g: col.g, b: col.b, a: alpha div 2))
      drawCircle(Vector2(x: enemy.pos.x, y: enemy.pos.y), r,
                 Color(r: col.r, g: col.g, b: col.b, a: alpha div 8))

    of bwoClockNodes:
      # Timekeeper: animated clock face
      let col = Color(r: 75, g: 255, b: 225, a: alpha)
      let r   = enemy.radius + 10.0'f32 + slowPulse * 4.0'f32
      drawCircleLines(enemy.pos.x.int32, enemy.pos.y.int32, r, col)
      for t in 0..<12:
        let a   = t.float32 * TwoPi.float32 / 12.0'f32 - PI.float32 * 0.5'f32
        let len = if t mod 3 == 0: 9.0'f32 else: 4.5'f32
        drawLine(Vector2(x: enemy.pos.x + cos(a) * (r - len),
                         y: enemy.pos.y + sin(a) * (r - len)),
                 Vector2(x: enemy.pos.x + cos(a) * r, y: enemy.pos.y + sin(a) * r),
                 if t mod 3 == 0: 2.5'f32 else: 1.5'f32, col)
      let handA = time * PI * 2.0'f32 - PI.float32 * 0.5'f32
      drawLine(Vector2(x: enemy.pos.x, y: enemy.pos.y),
               Vector2(x: enemy.pos.x + cos(handA) * (r - 5.0'f32),
                       y: enemy.pos.y + sin(handA) * (r - 5.0'f32)),
               2.8'f32, col)
      drawCircle(Vector2(x: enemy.pos.x, y: enemy.pos.y), r,
                 Color(r: col.r, g: col.g, b: col.b, a: alpha div 8))

    of bwoChaosAnomalies:
      # Chaos Weaver: multi-colour chaotic rings
      let r        = enemy.radius + 10.0'f32 + pulse * 8.0'f32
      let spin     = time * 5.5'f32
      let cCols    = [ Color(r: 255, g: 60,  b: 180, a: alpha),
                       Color(r: 60,  g: 255, b: 120, a: alpha),
                       Color(r: 255, g: 200, b: 55,  a: alpha) ]
      for c in 0..<3:
        drawCircleLines(enemy.pos.x.int32, enemy.pos.y.int32,
                        r + c.float32 * 6.0'f32, cCols[c])
      for s in 0..<8:
        let a = spin + s.float32 * TwoPi.float32 / 8.0'f32
        drawLine(Vector2(x: enemy.pos.x + cos(a) * r,          y: enemy.pos.y + sin(a) * r),
                 Vector2(x: enemy.pos.x + cos(a) * (r + 20.0'f32), y: enemy.pos.y + sin(a) * (r + 20.0'f32)),
                 2.2'f32, cCols[s mod 3])
      drawCircle(Vector2(x: enemy.pos.x, y: enemy.pos.y), r,
                 Color(r: 200, g: 100, b: 200, a: alpha div 8))

    else:
      # Generic fallback
      let ringRadius = enemy.radius + 10.0'f32 + pulse * 5.0'f32
      let color = Color(r: 255, g: 235, b: 90, a: alpha)
      drawCircleLines(enemy.pos.x.int32, enemy.pos.y.int32, ringRadius, color)
      drawCircleLines(enemy.pos.x.int32, enemy.pos.y.int32, ringRadius + 8.0'f32,
                      Color(r: 255, g: 255, b: 255, a: alpha div 3))

    # Exposure time-left arc: green → yellow → red, drawn tight against the boss
    if showHints:
      let arcR     = enemy.radius + 6.0'f32
      let segs     = max(3, int(tLeft * 36.0'f32))
      let arcSpan  = tLeft * TwoPi.float32
      let startA   = -(PI.float32 * 0.5'f32)
      let timerCol = if tLeft > 0.55'f32: Color(r: 80,  g: 255, b: 80,  a: 210)
                     elif tLeft > 0.28'f32: Color(r: 255, g: 200, b: 40,  a: 210)
                     else:                  Color(r: 255, g: 50,  b: 50,  a: 235)
      for s in 0..<segs:
        let a1 = startA + s.float32 * arcSpan / segs.float32
        let a2 = startA + (s + 1).float32 * arcSpan / segs.float32
        drawLine(Vector2(x: enemy.pos.x + cos(a1) * arcR, y: enemy.pos.y + sin(a1) * arcR),
                 Vector2(x: enemy.pos.x + cos(a2) * arcR, y: enemy.pos.y + sin(a2) * arcR),
                 3.2'f32, timerCol)
    return

  # Target drawing
  # Sequential kinds need numbered dot indicators
  let isSeqKind = kind in {bwoSpiralAnchors, bwoCoilSequence, bwoPrismSequence, bwoClockNodes}

  for target in enemy.weakPoint.targets:
    # Hit-burst ring: correct hit just registered – expand then fade before gone
    if target.hit:
      if target.hitFlashTimer > 0.0'f32:
        let t    = target.hitFlashTimer / 0.30'f32          # 1.0 → 0.0
        let expR = target.hitRadius * (1.0'f32 + (1.0'f32 - t) * 1.9'f32)
        drawCircleLines(target.pos.x.int32, target.pos.y.int32, expR,
                        Color(r: 255, g: 255, b: 100,
                              a: uint8(clamp(t * 220.0'f32, 0.0'f32, 255.0'f32))))
        drawCircleLines(target.pos.x.int32, target.pos.y.int32, expR * 0.58'f32,
                        Color(r: 255, g: 200, b: 50,
                              a: uint8(clamp(t * 140.0'f32, 0.0'f32, 255.0'f32))))
      continue

    let activeAlpha = if target.active: uint8(230) else: uint8(68)
    let cr    = target.hitRadius
    let scale = 1.0'f32 + pulse * 0.08'f32
    let lw    = if target.active: 2.5'f32 else: 1.1'f32   # line weight shorthand

    case kind
    of bwoDashBackPlate:
      # Berserker Juggernaut: cracked armour-plate shard (unchanged, already great)
      let shardCol = case target.index
        of 0: Color(r: 255, g: 40,  b: 20,  a: activeAlpha)
        of 1: Color(r: 255, g: 100, b: 10,  a: activeAlpha)
        else: Color(r: 255, g: 130, b: 0,   a: activeAlpha)
      let glowCol  = Color(r: shardCol.r, g: shardCol.g, b: shardCol.b, a: uint8(activeAlpha.int div 4))
      let crackCol = Color(r: 255, g: 255, b: 220, a: uint8(activeAlpha.int * 3 div 4))
      let sc   = 1.0'f32 + pulse * 0.10'f32
      let ax   = enemy.pos.x - target.pos.x
      let ay   = enemy.pos.y - target.pos.y
      let aLen = sqrt(ax * ax + ay * ay)
      let nx   = if aLen > 0.01'f32: ax / aLen else: 0.0'f32
      let ny   = if aLen > 0.01'f32: ay / aLen else: 1.0'f32
      let tx   = -ny; let ty = nx
      let tipIn  = cr * 1.05'f32 * sc
      let tipOut = cr * 0.90'f32 * sc
      let side   = cr * 0.55'f32 * sc
      let pIn    = Vector2(x: target.pos.x + nx * tipIn,  y: target.pos.y + ny * tipIn)
      let pOut   = Vector2(x: target.pos.x - nx * tipOut, y: target.pos.y - ny * tipOut)
      let pLeft  = Vector2(x: target.pos.x + tx * side,   y: target.pos.y + ty * side)
      let pRight = Vector2(x: target.pos.x - tx * side,   y: target.pos.y - ty * side)
      drawCircle(Vector2(x: target.pos.x, y: target.pos.y), cr * sc, glowCol)
      let fillCol = Color(r: shardCol.r div 3, g: shardCol.g div 4, b: 0, a: uint8(min(180, activeAlpha.int)))
      drawTriangle(pIn, pLeft, pRight, fillCol)
      drawTriangle(pOut, pRight, pLeft, fillCol)
      drawLine(pIn,    pLeft,  2.5'f32, shardCol)
      drawLine(pLeft,  pOut,   2.5'f32, shardCol)
      drawLine(pOut,   pRight, 2.5'f32, shardCol)
      drawLine(pRight, pIn,    2.5'f32, shardCol)
      let midLeft  = Vector2(x: (pIn.x + pLeft.x)  * 0.5'f32, y: (pIn.y + pLeft.y)  * 0.5'f32)
      let midRight = Vector2(x: (pIn.x + pRight.x) * 0.5'f32, y: (pIn.y + pRight.y) * 0.5'f32)
      let midBotL  = Vector2(x: (pOut.x + pLeft.x) * 0.5'f32, y: (pOut.y + pLeft.y) * 0.5'f32)
      let midBotR  = Vector2(x: (pOut.x + pRight.x) * 0.5'f32, y: (pOut.y + pRight.y) * 0.5'f32)
      drawLine(midLeft,  midBotR, 1.5'f32, crackCol)
      drawLine(midRight, midBotL, 1.5'f32, crackCol)
      drawCircle(Vector2(x: target.pos.x, y: target.pos.y), 2.5'f32 * sc, crackCol)
      if showHints:
        drawCircleLines(target.pos.x.int32, target.pos.y.int32, cr * sc + 4.0'f32,
                        Color(r: shardCol.r, g: shardCol.g, b: shardCol.b, a: uint8(activeAlpha.int div 5)))

    of bwoSpiralAnchors:
      # Spiral Guardian: 4-spoke spinning vortex
      let col     = Color(r: 175, g: 90, b: 255, a: activeAlpha)
      let glowCol = Color(r: col.r, g: col.g, b: col.b, a: activeAlpha div 4)
      let spin    = time * (if target.active: 2.6'f32 else: 0.45'f32)
      drawCircle(Vector2(x: target.pos.x, y: target.pos.y), cr * scale, glowCol)
      for s in 0..<4:
        let a = spin + s.float32 * PI * 0.5'f32
        drawLine(Vector2(x: target.pos.x + cos(a) * cr * 0.22'f32 * scale,
                         y: target.pos.y + sin(a) * cr * 0.22'f32 * scale),
                 Vector2(x: target.pos.x + cos(a) * cr * 0.88'f32 * scale,
                         y: target.pos.y + sin(a) * cr * 0.88'f32 * scale),
                 lw, col)
      drawCircleLines(target.pos.x.int32, target.pos.y.int32, cr * 0.30'f32 * scale, col)
      drawCircleLines(target.pos.x.int32, target.pos.y.int32, cr * scale, glowCol)
      if showHints:
        drawCircleLines(target.pos.x.int32, target.pos.y.int32, cr + 5.0'f32,
                        Color(r: col.r, g: col.g, b: col.b, a: activeAlpha div 4))

    of bwoSummonSigils:
      # Summoner King: rotating two-triangle hexagram rune
      let col     = Color(r: 78, g: 218, b: 112, a: activeAlpha)
      let glowCol = Color(r: col.r, g: col.g, b: col.b, a: activeAlpha div 4)
      let spin    = time * (if target.active: 0.85'f32 else: 0.18'f32)
      let rune    = cr * 0.80'f32 * scale
      drawCircle(Vector2(x: target.pos.x, y: target.pos.y), cr * scale, glowCol)
      for tri in 0..<2:
        let off  = tri.float32 * PI / 3.0'f32 + spin
        var prev = Vector2(x: target.pos.x + cos(off) * rune, y: target.pos.y + sin(off) * rune)
        for v in 1..3:
          let a    = off + v.float32 * TwoPi.float32 / 3.0'f32
          let curr = Vector2(x: target.pos.x + cos(a) * rune, y: target.pos.y + sin(a) * rune)
          drawLine(prev, curr, lw, col)
          prev = curr
      drawCircle(Vector2(x: target.pos.x, y: target.pos.y), cr * 0.17'f32 * scale,
                 Color(r: col.r, g: col.g, b: col.b, a: uint8(activeAlpha.int * 3 div 4)))
      drawCircleLines(target.pos.x.int32, target.pos.y.int32, cr * scale, glowCol)
      if showHints:
        drawCircleLines(target.pos.x.int32, target.pos.y.int32, cr + 5.0'f32,
                        Color(r: col.r, g: col.g, b: col.b, a: activeAlpha div 4))

    of bwoMeteorCracks:
      # Meteor Striker: jagged impact burst – alternating long/short spikes
      let col     = Color(r: 255, g: 138, b: 38, a: activeAlpha)
      let glowCol = Color(r: col.r, g: col.g, b: col.b, a: activeAlpha div 4)
      let jit     = target.index.float32 * 0.7'f32   # each crack looks unique
      drawCircle(Vector2(x: target.pos.x, y: target.pos.y), cr * scale, glowCol)
      for c in 0..<8:
        let a     = c.float32 * PI / 4.0'f32 + jit
        let outer = cr * (if c mod 2 == 0: 0.92'f32 else: 0.60'f32) * scale
        let inner = cr * 0.22'f32 * scale
        drawLine(Vector2(x: target.pos.x + cos(a) * inner, y: target.pos.y + sin(a) * inner),
                 Vector2(x: target.pos.x + cos(a) * outer, y: target.pos.y + sin(a) * outer),
                 if c mod 2 == 0: lw else: lw * 0.55'f32, col)
      drawCircle(Vector2(x: target.pos.x, y: target.pos.y), cr * 0.19'f32 * scale,
                 Color(r: col.r, g: col.g, b: col.b, a: uint8(activeAlpha.int * 3 div 4)))
      drawCircleLines(target.pos.x.int32, target.pos.y.int32, cr * scale, glowCol)
      if showHints:
        drawCircleLines(target.pos.x.int32, target.pos.y.int32, cr + 5.0'f32,
                        Color(r: col.r, g: col.g, b: col.b, a: activeAlpha div 4))

    of bwoLaserPrisms:
      # Laser Architect: spinning equilateral triangle with coloured node
      let colIdx  = target.index mod 3
      let col     = case colIdx
        of 0: Color(r: 80,  g: 220, b: 255, a: activeAlpha)
        of 1: Color(r: 255, g: 90,  b: 220, a: activeAlpha)
        else: Color(r: 255, g: 235, b: 80,  a: activeAlpha)
      let glowCol = Color(r: col.r, g: col.g, b: col.b, a: activeAlpha div 4)
      let spin    = time * (if target.active: 0.65'f32 else: 0.12'f32)
      let triR    = cr * 0.82'f32 * scale
      drawCircle(Vector2(x: target.pos.x, y: target.pos.y), cr * scale, glowCol)
      var prev = Vector2(x: target.pos.x + cos(spin) * triR, y: target.pos.y + sin(spin) * triR)
      for v in 1..3:
        let a    = spin + v.float32 * TwoPi.float32 / 3.0'f32
        let curr = Vector2(x: target.pos.x + cos(a) * triR, y: target.pos.y + sin(a) * triR)
        drawLine(prev, curr, lw, col)
        prev = curr
      drawCircle(Vector2(x: target.pos.x, y: target.pos.y), cr * 0.19'f32 * scale,
                 Color(r: col.r, g: col.g, b: col.b, a: uint8(activeAlpha.int * 3 div 4)))
      drawCircleLines(target.pos.x.int32, target.pos.y.int32, cr * scale, glowCol)
      if showHints:
        drawCircleLines(target.pos.x.int32, target.pos.y.int32, cr + 5.0'f32,
                        Color(r: col.r, g: col.g, b: col.b, a: activeAlpha div 4))

    of bwoVoidRifts:
      # Void Dancer: real rift = fast spinning arcs; decoy = static dim X
      # Visual distinction is intentional: the real rift has obvious energy.
      let isDecoy = target.decoy
      let col     = if isDecoy: Color(r: 88, g: 58, b: 155, a: uint8(activeAlpha.int * 7 div 10))
                    else:       Color(r: 215, g: 58, b: 255, a: activeAlpha)
      let glowCol = Color(r: col.r, g: col.g, b: col.b, a: uint8(activeAlpha.int div 4))
      drawCircle(Vector2(x: target.pos.x, y: target.pos.y), cr * scale, glowCol)
      if isDecoy:
        # Decoy: slow cross + dim ring – clearly "wrong"
        let spinD = time * 0.5'f32
        for c in 0..<4:
          let a = c.float32 * PI * 0.5'f32 + spinD
          drawLine(Vector2(x: target.pos.x + cos(a) * cr * 0.72'f32 * scale,
                           y: target.pos.y + sin(a) * cr * 0.72'f32 * scale),
                   Vector2(x: target.pos.x - cos(a) * cr * 0.72'f32 * scale,
                           y: target.pos.y - sin(a) * cr * 0.72'f32 * scale),
                   1.5'f32, col)
        drawCircleLines(target.pos.x.int32, target.pos.y.int32, cr * 0.85'f32 * scale, col)
      else:
        # Real: three fast spinning vortex arcs + bright inner dot
        let spinR = time * 2.5'f32
        for arc in 0..<3:
          let sa   = spinR + arc.float32 * TwoPi.float32 / 3.0'f32
          let ea   = sa + TwoPi.float32 * 0.26'f32
          let sg   = 12
          for s in 0..<sg:
            let a1 = sa + s.float32 * (ea - sa) / sg.float32
            let a2 = sa + (s + 1).float32 * (ea - sa) / sg.float32
            let ri = cr * (0.44'f32 + 0.42'f32 * s.float32 / sg.float32) * scale
            drawLine(Vector2(x: target.pos.x + cos(a1) * ri, y: target.pos.y + sin(a1) * ri),
                     Vector2(x: target.pos.x + cos(a2) * ri, y: target.pos.y + sin(a2) * ri),
                     2.5'f32, col)
        drawCircle(Vector2(x: target.pos.x, y: target.pos.y), cr * 0.20'f32 * scale,
                   Color(r: col.r, g: col.g, b: col.b, a: uint8(activeAlpha.int * 3 div 4)))
        drawCircleLines(target.pos.x.int32, target.pos.y.int32, cr * scale, glowCol)
      if showHints:
        drawCircleLines(target.pos.x.int32, target.pos.y.int32, cr + 5.0'f32,
                        Color(r: col.r, g: col.g, b: col.b, a: activeAlpha div 4))

    of bwoCoilSequence:
      # Chain Reactor: two counter-rotating arcs (the coil)
      let col     = Color(r: 255, g: 238, b: 65, a: activeAlpha)
      let glowCol = Color(r: col.r, g: col.g, b: col.b, a: activeAlpha div 4)
      let spin    = time * (if target.active: 3.6'f32 else: 0.75'f32)
      drawCircle(Vector2(x: target.pos.x, y: target.pos.y), cr * scale, glowCol)
      for arc in 0..<2:
        let dir = if arc == 0: 1.0'f32 else: -1.0'f32
        let sa  = spin * dir + arc.float32 * PI
        let ea  = sa + PI * 0.80'f32
        let sg  = 16
        for s in 0..<sg:
          let a1 = sa + s.float32 * (ea - sa) / sg.float32
          let a2 = sa + (s + 1).float32 * (ea - sa) / sg.float32
          drawLine(Vector2(x: target.pos.x + cos(a1) * cr * 0.82'f32 * scale,
                           y: target.pos.y + sin(a1) * cr * 0.82'f32 * scale),
                   Vector2(x: target.pos.x + cos(a2) * cr * 0.82'f32 * scale,
                           y: target.pos.y + sin(a2) * cr * 0.82'f32 * scale),
                   lw, col)
      drawCircle(Vector2(x: target.pos.x, y: target.pos.y), cr * 0.18'f32 * scale,
                 Color(r: col.r, g: col.g, b: col.b, a: uint8(activeAlpha.int * 3 div 4)))
      drawCircleLines(target.pos.x.int32, target.pos.y.int32, cr * scale, glowCol)
      if showHints:
        drawCircleLines(target.pos.x.int32, target.pos.y.int32, cr + 5.0'f32,
                        Color(r: col.r, g: col.g, b: col.b, a: activeAlpha div 4))

    of bwoPrismSequence:
      # Prism Architect: spinning triangle, faster when active
      let colIdx  = target.index mod 3
      let col     = case colIdx
        of 0: Color(r: 80,  g: 220, b: 255, a: activeAlpha)
        of 1: Color(r: 255, g: 90,  b: 220, a: activeAlpha)
        else: Color(r: 255, g: 235, b: 80,  a: activeAlpha)
      let glowCol = Color(r: col.r, g: col.g, b: col.b, a: activeAlpha div 4)
      let spin    = time * (if target.active: 1.55'f32 else: 0.28'f32)
      let triR    = cr * 0.82'f32 * scale
      drawCircle(Vector2(x: target.pos.x, y: target.pos.y), cr * scale, glowCol)
      var prev = Vector2(x: target.pos.x + cos(spin) * triR, y: target.pos.y + sin(spin) * triR)
      for v in 1..3:
        let a    = spin + v.float32 * TwoPi.float32 / 3.0'f32
        let curr = Vector2(x: target.pos.x + cos(a) * triR, y: target.pos.y + sin(a) * triR)
        drawLine(prev, curr, lw, col)
        prev = curr
      drawCircle(Vector2(x: target.pos.x, y: target.pos.y), cr * 0.18'f32 * scale,
                 Color(r: col.r, g: col.g, b: col.b, a: uint8(activeAlpha.int * 3 div 4)))
      drawCircleLines(target.pos.x.int32, target.pos.y.int32, cr * scale, glowCol)
      if showHints:
        drawCircleLines(target.pos.x.int32, target.pos.y.int32, cr + 5.0'f32,
                        Color(r: col.r, g: col.g, b: col.b, a: activeAlpha div 4))

    of bwoClockNodes:
      # Timekeeper: miniature clock face – hand sweeps in sync with sequenceIndex advance
      let col     = Color(r: 75, g: 255, b: 225, a: activeAlpha)
      let glowCol = Color(r: col.r, g: col.g, b: col.b, a: activeAlpha div 4)
      drawCircle(Vector2(x: target.pos.x, y: target.pos.y), cr * scale, glowCol)
      drawCircleLines(target.pos.x.int32, target.pos.y.int32, cr * 0.85'f32 * scale, col)
      for t in 0..<4:
        let a = t.float32 * PI * 0.5'f32 - PI.float32 * 0.5'f32
        drawLine(Vector2(x: target.pos.x + cos(a) * cr * 0.60'f32 * scale,
                         y: target.pos.y + sin(a) * cr * 0.60'f32 * scale),
                 Vector2(x: target.pos.x + cos(a) * cr * 0.83'f32 * scale,
                         y: target.pos.y + sin(a) * cr * 0.83'f32 * scale),
                 2.0'f32, col)
      if target.active:
        let handA = time * PI * 2.0'f32 - PI.float32 * 0.5'f32
        drawLine(Vector2(x: target.pos.x, y: target.pos.y),
                 Vector2(x: target.pos.x + cos(handA) * cr * 0.60'f32 * scale,
                         y: target.pos.y + sin(handA) * cr * 0.60'f32 * scale),
                 2.5'f32, col)
      drawCircleLines(target.pos.x.int32, target.pos.y.int32, cr * scale, glowCol)
      if showHints:
        drawCircleLines(target.pos.x.int32, target.pos.y.int32, cr + 5.0'f32,
                        Color(r: col.r, g: col.g, b: col.b, a: activeAlpha div 4))

    of bwoChaosAnomalies:
      # Chaos Weaver: 6-pointed jagged star, each target a different colour
      let colIdx  = target.index mod 3
      let col     = case colIdx
        of 0: Color(r: 255, g: uint8(80 + (target.index * 55) mod 150), b: 255, a: activeAlpha)
        of 1: Color(r: 60,  g: 255, b: 120, a: activeAlpha)
        else: Color(r: 255, g: 200, b: 60,  a: activeAlpha)
      let glowCol = Color(r: col.r, g: col.g, b: col.b, a: activeAlpha div 4)
      let spin    = time * (if target.active: 3.1'f32 else: 0.5'f32) +
                    target.index.float32 * 1.3'f32
      drawCircle(Vector2(x: target.pos.x, y: target.pos.y), cr * scale, glowCol)
      # Star outline: alternate outer (tip) and inner (valley) radii
      for s in 0..<12:
        let a1  = spin + s.float32 * TwoPi.float32 / 12.0'f32
        let a2  = spin + (s + 1).float32 * TwoPi.float32 / 12.0'f32
        let r1  = cr * (if s mod 2 == 0: 0.90'f32 else: 0.44'f32) * scale
        let r2  = cr * (if (s+1) mod 2 == 0: 0.90'f32 else: 0.44'f32) * scale
        drawLine(Vector2(x: target.pos.x + cos(a1) * r1, y: target.pos.y + sin(a1) * r1),
                 Vector2(x: target.pos.x + cos(a2) * r2, y: target.pos.y + sin(a2) * r2),
                 lw, col)
      drawCircle(Vector2(x: target.pos.x, y: target.pos.y), cr * 0.18'f32 * scale,
                 Color(r: col.r, g: col.g, b: col.b, a: uint8(activeAlpha.int * 3 div 4)))
      drawCircleLines(target.pos.x.int32, target.pos.y.int32, cr * scale, glowCol)
      if showHints:
        drawCircleLines(target.pos.x.int32, target.pos.y.int32, cr + 5.0'f32,
                        Color(r: col.r, g: col.g, b: col.b, a: activeAlpha div 4))

    else:
      # Generic fallback (bwoOmegaCycle dispatches per-phase above; catches bwoNone)
      var color = target.color
      color.a = activeAlpha
      let ringRadius = target.hitRadius * (0.72'f32 + pulse * 0.12'f32)
      drawCircle(Vector2(x: target.pos.x, y: target.pos.y),
                 max(5.0'f32, ringRadius * 0.35'f32),
                 Color(r: color.r, g: color.g, b: color.b, a: activeAlpha div 3))
      drawCircleLines(target.pos.x.int32, target.pos.y.int32, ringRadius, color)
      drawLine(Vector2(x: target.pos.x - 6.0'f32, y: target.pos.y),
               Vector2(x: target.pos.x + 6.0'f32, y: target.pos.y), 2.0'f32,
               Color(r: 255, g: 255, b: 255, a: activeAlpha))
      drawLine(Vector2(x: target.pos.x, y: target.pos.y - 6.0'f32),
               Vector2(x: target.pos.x, y: target.pos.y + 6.0'f32), 2.0'f32,
               Color(r: 255, g: 255, b: 255, a: activeAlpha))
      if showHints:
        drawCircleLines(target.pos.x.int32, target.pos.y.int32,
                        target.hitRadius + 5.0'f32,
                        Color(r: color.r, g: color.g, b: color.b, a: activeAlpha div 4))

    # Wrong-hit flash overlay (drawn over whatever shape was just rendered)
    if target.wrongHitFlash > 0.0'f32:
      let ft   = target.wrongHitFlash / 0.45'f32
      let fA   = uint8(clamp(ft * 210.0'f32, 0.0'f32, 255.0'f32))
      let expO = (1.0'f32 - ft) * 10.0'f32
      drawCircle(Vector2(x: target.pos.x, y: target.pos.y), cr * scale * 1.05'f32,
                 Color(r: 255, g: 20, b: 20, a: uint8(clamp(ft * 72.0'f32, 0.0'f32, 100.0'f32))))
      drawCircleLines(target.pos.x.int32, target.pos.y.int32,
                      cr * scale + 3.0'f32 + expO,
                      Color(r: 255, g: 30, b: 30, a: fA))
      drawCircleLines(target.pos.x.int32, target.pos.y.int32,
                      cr * scale + 10.0'f32 + expO * 1.2'f32,
                      Color(r: 255, g: 80, b: 0, a: uint8(clamp(ft * 110.0'f32, 0.0'f32, 255.0'f32))))

    # Active-target focus ring (sequential kinds only)
    # A bright pulsing double ring that clearly screams "hit THIS one next"
    if target.active and isSeqKind:
      let fp       = sin(time * 9.5'f32) * 0.5'f32 + 0.5'f32
      let focusR   = cr * scale + 5.0'f32 + fp * 4.5'f32
      drawCircleLines(target.pos.x.int32, target.pos.y.int32, focusR,
                      Color(r: 255, g: 255, b: 255,
                            a: uint8(clamp(120.0'f32 + fp * 100.0'f32, 0.0'f32, 255.0'f32))))
      drawCircleLines(target.pos.x.int32, target.pos.y.int32, focusR + 5.5'f32,
                      Color(r: 255, g: 255, b: 200,
                            a: uint8(clamp(fp * 65.0'f32, 0.0'f32, 255.0'f32))))

    # Sequence-order dots (only for sequential kinds, only when hints on)
    # Drawn as a row of small dots below the target: 1 dot = hit first, 2 = second…
    # Already-hit entries simply vanish from the loop, so the dot count communicates
    # which un-hit target comes next.
    if showHints and isSeqKind:
      let numDots   = min(target.index + 1, 5)   # cap at 5 to avoid overflow
      let dotStep   = 7.0'f32
      let startDotX = target.pos.x - (numDots - 1).float32 * dotStep * 0.5'f32
      let dotY      = target.pos.y + cr * scale + 9.0'f32
      let dotAlpha  = if target.active: uint8(220) else: uint8(90)
      for d in 0..<numDots:
        drawCircle(
          Vector2(x: startDotX + d.float32 * dotStep, y: dotY),
          if d == numDots - 1: 3.2'f32 else: 2.2'f32,   # last dot bigger = "this one"
          Color(r: 255, g: 255, b: 255, a: dotAlpha))

  # Sequential next-target dashed arrow
  # A faint dashed line + arrowhead guides the player from the current active
  # target to the next un-hit one, making the order immediately obvious.
  if showHints and isSeqKind and enemy.weakPoint.exposedTimer <= 0 and
     enemy.weakPoint.targets.len > 1:
    let si = enemy.weakPoint.sequenceIndex
    var fromIdx = -1
    var toIdx   = -1
    for j in 0..<enemy.weakPoint.targets.len:
      if not enemy.weakPoint.targets[j].hit:
        if enemy.weakPoint.targets[j].index == si:       fromIdx = j
        if enemy.weakPoint.targets[j].index == si + 1:   toIdx   = j
    if fromIdx >= 0 and toIdx >= 0:
      let fp  = enemy.weakPoint.targets[fromIdx].pos
      let tp  = enemy.weakPoint.targets[toIdx].pos
      let hr  = enemy.weakPoint.targetHitRadius
      let dx  = tp.x - fp.x
      let dy  = tp.y - fp.y
      let d   = sqrt(dx * dx + dy * dy)
      if d > 4.0'f32:
        let nx = dx / d; let ny = dy / d
        let aAlpha = uint8(50 + int(slowPulse * 38.0'f32))
        let sP = Vector2(x: fp.x + nx * hr * 1.35'f32, y: fp.y + ny * hr * 1.35'f32)
        let eP = Vector2(x: tp.x - nx * hr * 1.45'f32, y: tp.y - ny * hr * 1.45'f32)
        let segLen = sqrt((eP.x - sP.x) * (eP.x - sP.x) + (eP.y - sP.y) * (eP.y - sP.y))
        if segLen > 5.0'f32:
          let numDash = max(2, int(segLen / 16.0'f32))
          for s in 0..<numDash:
            let t1 = (s.float32 + 0.15'f32) / numDash.float32
            let t2 = (s.float32 + 0.75'f32) / numDash.float32
            drawLine(Vector2(x: sP.x + (eP.x - sP.x) * t1, y: sP.y + (eP.y - sP.y) * t1),
                     Vector2(x: sP.x + (eP.x - sP.x) * t2, y: sP.y + (eP.y - sP.y) * t2),
                     1.5'f32, Color(r: 255, g: 255, b: 255, a: aAlpha))
          # Arrowhead at destination
          let perpX = -ny * 5.0'f32; let perpY = nx * 5.0'f32
          drawLine(eP, Vector2(x: eP.x - nx * 9.0'f32 + perpX, y: eP.y - ny * 9.0'f32 + perpY),
                   1.8'f32, Color(r: 255, g: 255, b: 255, a: aAlpha))
          drawLine(eP, Vector2(x: eP.x - nx * 9.0'f32 - perpX, y: eP.y - ny * 9.0'f32 - perpY),
                   1.8'f32, Color(r: 255, g: 255, b: 255, a: aAlpha))

  # Progress pips – wider spacing, per-type colour theme
  if showHints and enemy.weakPoint.required > 1:
    let pipStep   = 13.0'f32
    let pipR      = if kind == bwoDashBackPlate: 4.8'f32 else: 4.2'f32
    let startX    = enemy.pos.x - (enemy.weakPoint.required - 1).float32 * pipStep * 0.5'f32
    let y         = enemy.pos.y + enemy.radius + 18.0'f32
    let isSeqPips = kind in {bwoSpiralAnchors, bwoCoilSequence, bwoPrismSequence, bwoClockNodes}
    for i in 0..<enemy.weakPoint.required:
      let filled = i < enemy.weakPoint.progress
      let isNext = isSeqPips and i == enemy.weakPoint.progress
      let pipColor = case kind
        of bwoDashBackPlate:
          if filled: Color(r: 255, g: 80,  b: 0,   a: 230)
          else:      Color(r: 90,  g: 60,  b: 60,  a: 130)
        of bwoSpiralAnchors, bwoOmegaCycle:
          if filled: Color(r: 160, g: 80,  b: 255, a: 220)
          else:      Color(r: 80,  g: 60,  b: 120, a: 110)
        of bwoSummonSigils:
          if filled: Color(r: 80,  g: 220, b: 120, a: 220)
          else:      Color(r: 60,  g: 80,  b: 60,  a: 110)
        of bwoMeteorCracks:
          if filled: Color(r: 255, g: 140, b: 40,  a: 220)
          else:      Color(r: 100, g: 80,  b: 60,  a: 110)
        of bwoLaserPrisms, bwoPrismSequence:
          if filled: Color(r: 80,  g: 220, b: 255, a: 220)
          else:      Color(r: 60,  g: 80,  b: 100, a: 110)
        of bwoVoidRifts:
          if filled: Color(r: 210, g: 60,  b: 255, a: 220)
          else:      Color(r: 80,  g: 60,  b: 100, a: 110)
        of bwoCoilSequence:
          if filled: Color(r: 255, g: 240, b: 70,  a: 220)
          else:      Color(r: 100, g: 95,  b: 60,  a: 110)
        of bwoClockNodes:
          if filled: Color(r: 80,  g: 255, b: 230, a: 220)
          else:      Color(r: 60,  g: 100, b: 90,  a: 110)
        of bwoChaosAnomalies:
          if filled: Color(r: 255, g: 80,  b: 200, a: 220)
          else:      Color(r: 100, g: 60,  b: 90,  a: 110)
        else:
          if filled: Color(r: 255, g: 235, b: 80,  a: 220)
          else:      Color(r: 120, g: 120, b: 130, a: 120)
      # Filled and upcoming pips are larger
      let r = if filled: pipR + 1.8'f32 elif isNext: pipR + 1.0'f32 else: pipR
      drawCircle(Vector2(x: startX + i.float32 * pipStep, y: y), r, pipColor)
      # Upcoming pip gets a white halo so the player knows what's next
      if isNext:
        drawCircleLines(int32(startX + i.float32 * pipStep), int32(y),
                        r + 3.5'f32, Color(r: 255, g: 255, b: 255, a: 140))
