import raylib, rlgl, random, math, types, enemy, bullet, boss_definitions, particle_pool, particle_types, d_systems, enemy_helpers, boss_weakpoints, ui/warnings
import game/bullets

const BOSS_PHASE_INVULNERABILITY_DURATION* = BossPhaseTransitionDuration

const RainbowPalette = [
  Color(r: 255, g: 0,   b: 0,   a: 255),  # Red
  Color(r: 255, g: 127, b: 0,   a: 255),  # Orange
  Color(r: 255, g: 255, b: 0,   a: 255),  # Yellow
  Color(r: 0,   g: 255, b: 0,   a: 255),  # Green
  Color(r: 0,   g: 0,   b: 255, a: 255),  # Blue
  Color(r: 75,  g: 0,   b: 130, a: 255),  # Indigo
  Color(r: 148, g: 0,   b: 211, a: 255),  # Violet
]

proc bossBehaviorRand(minValue, maxValue: float32): float32 =
  if maxValue <= minValue:
    return minValue
  return minValue + rand(maxValue - minValue)

proc resetBossBehaviorState(enemy: Enemy, specialBehavior: string) =
  ## Reset boss-only timers when a phase starts so movement accents do not carry
  ## burst windows or teleport cadences across unrelated behaviors.
  enemy.burstTimer = 0.0
  enemy.pendingDashLocked = false

  case specialBehavior
  of "critical_discharge":
    enemy.teleportTimer = 0.0
    enemy.shockwaveTimer = 0.0
  of "time_collapse":
    enemy.teleportTimer = 0.0
    enemy.shockwaveTimer = bossBehaviorRand(2.8, 3.6)
  of "total_chaos":
    enemy.teleportTimer = bossBehaviorRand(4.0, 5.4)
    enemy.shockwaveTimer = bossBehaviorRand(3.2, 4.2)
  of "final_form":
    enemy.teleportTimer = bossBehaviorRand(5.2, 6.3)
    enemy.shockwaveTimer = 0.0
  of "enraged":
    enemy.teleportTimer = 0.0
    enemy.shockwaveTimer = bossBehaviorRand(3.2, 4.0)
  else:
    enemy.teleportTimer = 0.0
    enemy.shockwaveTimer = 0.0

proc bossPhaseMaxHp*(enemy: Enemy, phaseIndex: int, phaseCount: int): float32 =
  if phaseIndex >= 0 and phaseIndex < enemy.bossPhaseHpPools.len:
    return max(enemy.bossPhaseHpPools[phaseIndex], 0.01'f32)

  if enemy.bossTotalMaxHp > 0.0'f32 and phaseCount > 0:
    return max(enemy.bossTotalMaxHp / phaseCount.float32, 0.01'f32)

  max(enemy.maxHp, 0.01'f32)

proc transitionBossToPhase*(game: var Game, enemy: Enemy, bossDef: BossDefinition,
                           nextPhaseIndex: int) =
  if nextPhaseIndex < 0 or nextPhaseIndex >= bossDef.phases.len:
    return

  let phase = bossDef.phases[nextPhaseIndex]
  enemy.currentPhaseIndex = nextPhaseIndex
  enemy.maxHp = bossPhaseMaxHp(enemy, nextPhaseIndex, bossDef.phases.len)
  enemy.hp = enemy.maxHp

  # Invulnerability for the full epic transition, and a punch to sell it. The
  # boss is frozen (see the movement guard in the boss update loop) and cannot
  # be hurt while drawBossPhaseTransition plays its per-boss animation.
  enemy.invulnerabilityTimer = BOSS_PHASE_INVULNERABILITY_DURATION
  enemy.bossPhaseBreakFlashTimer = 0.9'f32
  enemy.vel = newVector2f(0, 0)
  enemy.isDashing = false
  enemy.dashDuration = 0
  # Reset enrage so attack timers (seeded to the full invuln duration below) tick
  # at the base rate and only expire once the transition ends, no shots or
  # telegraphs leak into the frozen animation.
  enemy.bossEnrageLevel = 0.0'f32
  addShake(game.dopamine.screenShake, siLarge)

  for ring in 1..5:
    for j in 0..23:
      let angle = j.float32 * PI * 2.0 / 24.0
      let dist = ring.float32 * 35.0
      let px = enemy.pos.x + cos(angle) * dist
      let py = enemy.pos.y + sin(angle) * dist
      spawnExplosionPooled(game.particlePool, px, py, phase.color, 8)

  spawnExplosionPooled(game.particlePool, enemy.pos.x, enemy.pos.y,
                       Color(r: 255, g: 255, b: 255, a: 255), 40)

  if enemy.satellites.len > 0:
    for satellite in enemy.satellites:
      spawnExplosionPooled(game.particlePool, satellite.pos.x, satellite.pos.y,
                           Color(r: 100, g: 150, b: 255, a: 255), 12)
    enemy.satellites = @[]

  # Attacks stay silent for the whole transition, then resume the instant the
  # boss becomes vulnerable again (lead == invuln duration).
  const PHASE_TRANSITION_LEAD = BOSS_PHASE_INVULNERABILITY_DURATION
  enemy.attackTimers = @[]
  enemy.attackWarningFired = @[]
  for attack in phase.attacks:
    enemy.attackTimers.add(PHASE_TRANSITION_LEAD)
    enemy.attackWarningFired.add(false)

  # Bosses keep their spawn color across phases (phase recoloring was a legacy mechanic).
  let scaledBaseSpeed = getScaledBossSpeed(bossDef, game.currentWave)
  enemy.speed = scaledBaseSpeed * phase.speedMultiplier
  enemy.defenseMultiplier = phase.defenseMultiplier
  resetBossBehaviorState(enemy, phase.specialBehavior)
  resetBossWeakPointForPhase(enemy, bossDef.weakPoint, enemy.currentPhaseIndex)

proc tryAdvanceBossPhase*(game: var Game, enemy: Enemy): bool =
  if not enemy.isBoss or enemy.hp > 0.0'f32 or enemy.bossDefinitionID <= 0:
    return false

  let bossDef = getBossDefinition(enemy.bossDefinitionID)
  let nextPhaseIndex = enemy.currentPhaseIndex + 1
  if nextPhaseIndex >= bossDef.phases.len:
    return false

  transitionBossToPhase(game, enemy, bossDef, nextPhaseIndex)
  true

# Boss engagement mechanics
# These exist to stop "facetank and hold fire = win". They layer on top of the
# weak-point durability gate: the body is heavily resisted, and on top of that
# these mechanics demand the player consciously DO something (clear adds, stop
# firing into a shield, break the objective before it enrages, and actually
# spend the vulnerability window or the boss heals it back).
const
  REFLECT_SHIELD_DURATION  = 1.8'f32   # how long the overload shield stays up
  REFLECT_SHIELD_INTERVAL  = 9.0'f32   # gap between overload shields
  REFLECT_SHIELD_DAMAGE*     = 2.0'f32  # damage a reflected shot does to the player
  ENRAGE_STALL_THRESHOLD   = 5.0'f32   # seconds of ignoring an open objective before enrage builds
  ENRAGE_RAMP_PER_SEC      = 0.5'f32   # enrage growth once stalling
  ENRAGE_MAX*               = 1.2'f32   # cap: attacks fire up to (1 + this)x as fast
  ENRAGE_DECAY_PER_SEC     = 1.5'f32   # enrage falls off once the player re-engages
  HEAL_ON_IGNORE_FRAC      = 0.04'f32  # phase HP refunded when a window is wasted

proc bossLivingAddsCount(game: Game, enemy: Enemy): int =
  ## Count adds that belong to a boss: its orbital satellites plus any enemy it summoned.
  result = enemy.satellites.len
  for other in game.enemies:
    if other.spawnedByBoss and other.hp > 0:
      result += 1

proc updateBossMechanics*(game: var Game, enemy: Enemy, dt: float32) =
  if not enemy.isBoss:
    return

  let inWindow = enemy.weakPoint.exposedTimer > 0
  let invuln   = enemy.invulnerabilityTimer > 0

  # Adds-gate: while the boss's summoned adds/satellites live, its body is sealed.
  enemy.addsGateActive = bossLivingAddsCount(game, enemy) > 0

  # Overload shield: cycles up periodically and bounces body shots back.
  # Never raises during a vulnerability window, a phase transition, or an adds-gate
  # so the player always has a clear "do the mechanic" path.
  if enemy.reflectShieldActive:
    enemy.reflectShieldTimer -= dt
    # A vulnerability window always takes priority - drop the shield so the
    # player gets a clean window to burst the body.
    if enemy.reflectShieldTimer <= 0 or inWindow:
      enemy.reflectShieldActive = false
      enemy.reflectShieldCooldown = REFLECT_SHIELD_INTERVAL
  elif not inWindow and not invuln and not enemy.addsGateActive:
    enemy.reflectShieldCooldown -= dt
    if enemy.reflectShieldCooldown <= 0:
      enemy.reflectShieldActive = true
      enemy.reflectShieldTimer = REFLECT_SHIELD_DURATION

  # Enrage on stall: if the objective is open and being ignored, attacks speed up.
  let objectiveOpen = enemy.weakPoint.enabled and enemy.weakPoint.targets.len > 0 and
                      not inWindow and not invuln and not enemy.addsGateActive
  if objectiveOpen:
    enemy.bossStallTimer += dt
    if enemy.bossStallTimer > ENRAGE_STALL_THRESHOLD:
      enemy.bossEnrageLevel = min(ENRAGE_MAX, enemy.bossEnrageLevel + ENRAGE_RAMP_PER_SEC * dt)
  else:
    enemy.bossStallTimer = 0
    enemy.bossEnrageLevel = max(0.0'f32, enemy.bossEnrageLevel - ENRAGE_DECAY_PER_SEC * dt)

  # Heal-on-ignore: a vulnerability window the player barely uses is refunded.
  if inWindow and not enemy.windowWasOpen:
    enemy.windowWasOpen = true
    enemy.windowDamageDealt = 0
  elif not inWindow and enemy.windowWasOpen:
    enemy.windowWasOpen = false
    let wasted = enemy.windowDamageDealt < enemy.maxHp * 0.03'f32
    if wasted and enemy.hp > 0:
      enemy.hp = min(enemy.maxHp, enemy.hp + enemy.maxHp * HEAL_ON_IGNORE_FRAC)
      for ring in 0..1:
        spawnExplosionPooled(game.particlePool, enemy.pos.x, enemy.pos.y,
                             Color(r: 80, g: 255, b: 130, a: 220), 12)

  # Apply heals queued by weak-point targets that expired unhit (set in
  # updateBossWeakPoint). Same green-flash feedback as the window refund so the
  # player learns that ignored objectives let the boss recover.
  if enemy.ignoreHealPending > 0 and enemy.hp > 0:
    enemy.hp = min(enemy.maxHp, enemy.hp + enemy.ignoreHealPending)
    spawnExplosionPooled(game.particlePool, enemy.pos.x, enemy.pos.y,
                         Color(r: 80, g: 255, b: 130, a: 200), 9)
  enemy.ignoreHealPending = 0

proc isBossBehaviorBurstActive(enemy: Enemy, dt: float32,
                               activeDuration, cooldownMin, cooldownMax: float32): bool =
  if enemy.burstTimer > 0:
    enemy.burstTimer = max(0.0'f32, enemy.burstTimer - dt)
    return true

  enemy.shockwaveTimer = max(0.0'f32, enemy.shockwaveTimer - dt)
  if enemy.shockwaveTimer <= 0:
    enemy.burstTimer = max(0.0'f32, activeDuration - dt)
    enemy.shockwaveTimer = bossBehaviorRand(cooldownMin, cooldownMax)
    return true

  return false

proc performBossBehaviorTeleport(game: Game, enemy: Enemy, minRadius, maxRadius: float32,
                                 effectColor: Color, effectSize: int,
                                 minPlayerDistance: float32 = 125.0): bool =
  let margin = enemy.radius + 16.0
  let oldPos = enemy.pos
  var targetPos = enemy.pos
  var foundTarget = false

  for _ in 0..<8:
    let angle = rand(PI * 2.0)
    let radius = bossBehaviorRand(minRadius, maxRadius)
    let candidate = newVector2f(
      clamp(game.player.pos.x + cos(angle) * radius, margin, game.screenWidth.float32 - margin),
      clamp(game.player.pos.y + sin(angle) * radius, margin, game.screenHeight.float32 - margin)
    )

    if distance(candidate, game.player.pos) >= minPlayerDistance and
       distance(candidate, enemy.pos) >= 80.0:
      targetPos = candidate
      foundTarget = true
      break

  if not foundTarget:
    return false

  spawnExplosionPooled(game.particlePool, oldPos.x, oldPos.y, effectColor, max(6, effectSize div 2))
  enemy.pos = targetPos
  spawnExplosionPooled(game.particlePool, targetPos.x, targetPos.y, effectColor, effectSize)
  return true

proc tryBossBehaviorTeleport(game: Game, enemy: Enemy, dt: float32,
                             cooldownMin, cooldownMax, minRadius, maxRadius: float32,
                             effectColor: Color, effectSize: int,
                             minPlayerDistance: float32 = 125.0): bool =
  enemy.teleportTimer = max(0.0'f32, enemy.teleportTimer - dt)
  if enemy.teleportTimer > 0:
    return false

  enemy.teleportTimer = bossBehaviorRand(cooldownMin, cooldownMax)
  return performBossBehaviorTeleport(
    game, enemy, minRadius, maxRadius, effectColor, effectSize, minPlayerDistance
  )

proc updateCustomBossBehavior*(game: Game, enemy: var Enemy, phase: BossPhaseDefinition, dt: float32) =
  ## Updates boss movement based on phase specialBehavior
  if phase.specialBehavior == "":
    return
  if enemy.pendingDashLocked:
    enemy.vel = newVector2f(0, 0)
    enemy.pos = enemy.pendingDashStart
    return
  if enemy.isDashing:
    enemy.vel = enemy.dashVelocity
    return

  let startPos = enemy.pos
  let playerDist = distance(enemy.pos, game.player.pos)
  let toPlayer = (game.player.pos - enemy.pos).normalize()
  let centerX = game.screenWidth.float32 / 2.0
  let centerY = game.screenHeight.float32 / 2.0

  case phase.specialBehavior
  of "circle_movement":
    # Smooth velocity-based orbiting
    # Calculate target position on circle
    let orbitRadius = 200.0
    let orbitSpeed = 0.4  # Radians per second
    let angle = game.time * orbitSpeed
    let targetX = centerX + cos(angle) * orbitRadius
    let targetY = centerY + sin(angle) * orbitRadius

    # Move toward target position smoothly using velocity
    let toTarget = (newVector2f(targetX, targetY) - enemy.pos).normalize()
    enemy.pos = enemy.pos + toTarget * enemy.speed * dt

  of "circle_player":
    # Orbit around player, smooth velocity-based, constant natural speed
    let orbitRadius = 180.0
    let orbitAngularSpeed = 0.55  # radians per second
    let currentAngle = arctan2(enemy.pos.y - game.player.pos.y, enemy.pos.x - game.player.pos.x)
    let nextAngle = currentAngle + orbitAngularSpeed * dt
    let desiredX = game.player.pos.x + cos(nextAngle) * orbitRadius
    let desiredY = game.player.pos.y + sin(nextAngle) * orbitRadius
    let toDes = newVector2f(desiredX - enemy.pos.x, desiredY - enemy.pos.y)
    let desDist = sqrt(toDes.x * toDes.x + toDes.y * toDes.y)
    if desDist > 0.1:
      let step = min(enemy.speed * 1.2 * dt, desDist)
      enemy.pos.x += (toDes.x / desDist) * step
      enemy.pos.y += (toDes.y / desDist) * step

  of "aggressive":
    # Chase player directly
    enemy.pos = enemy.pos + toPlayer * enemy.speed * dt

  of "defensive":
    # Keep distance from player
    if playerDist < 250.0:
      let retreatDir = toPlayer * -1.0
      enemy.pos = enemy.pos + retreatDir * enemy.speed * 0.85 * dt
    else:
      let strafeDir = newVector2f(-toPlayer.y, toPlayer.x)
      let driftDir = (strafeDir * 0.75 + toPlayer * 0.25).normalize()
      enemy.pos = enemy.pos + driftDir * enemy.speed * 0.45 * dt

  of "geometric_movement":
    # Smooth lissajous/figure-eight movement, constant natural speed toward pattern target
    let patternPhase = game.time * 1.0
    let targetX = centerX + sin(patternPhase) * 150.0
    let targetY = centerY + cos(patternPhase) * 150.0
    let toDes = newVector2f(targetX - enemy.pos.x, targetY - enemy.pos.y)
    let desDist = sqrt(toDes.x * toDes.x + toDes.y * toDes.y)
    if desDist > 0.1:
      let step = min(enemy.speed * 1.1 * dt, desDist)
      enemy.pos.x += (toDes.x / desDist) * step
      enemy.pos.y += (toDes.y / desDist) * step

  of "teleport_pattern":
    # Occasionally teleport (handled via attacks, just face player here)
    if playerDist > 150.0:
      enemy.pos = enemy.pos + toPlayer * enemy.speed * dt * 0.5

  of "clone_assault":
    # Erratic movement toward player with smooth direction blending (sin-based, no frame dependency)
    let cloneBlend = sin(game.time * PI) * 0.5 + 0.5  # 0..1, completes one cycle per 2s
    let perpDir = newVector2f(-toPlayer.y, toPlayer.x)
    let blendedDir = (toPlayer * cloneBlend + perpDir * (1.0 - cloneBlend)).normalize()
    enemy.pos = enemy.pos + blendedDir * enemy.speed * dt

  of "reality_break":
    # Chaotic unpredictable movement, time-based multi-frequency angle, no per-frame rand
    let randomAngle = game.time * 1.3 + sin(game.time * 2.7 + enemy.pos.x * 0.01) * PI +
                      cos(game.time * 1.9 + enemy.pos.y * 0.01) * PI
    let randomDir = newVector2f(cos(randomAngle), sin(randomAngle))
    enemy.pos = enemy.pos + randomDir * enemy.speed * dt

  of "laser_web":
    let webPhase = game.time * 0.9
    let webTarget = newVector2f(centerX + sin(webPhase) * 135.0,
                                centerY + sin(webPhase * 2.0) * 80.0)
    let toWeb = (webTarget - enemy.pos).normalize()
    enemy.pos = enemy.pos + toWeb * enemy.speed * 0.55 * dt

  of "laser_chaos":
    # Rapid erratic movement
    let angle = game.time * 3.0 + enemy.pos.x * 0.01
    let chaosDir = newVector2f(cos(angle), sin(angle))
    enemy.pos = enemy.pos + chaosDir * enemy.speed * dt * 0.8

  of "slow_charge":
    # Slow movement toward player, charging up
    enemy.pos = enemy.pos + toPlayer * enemy.speed * 0.3 * dt

  of "electric_buildup":
    # Moves slowly with sudden micro-movements like electricity
    let chargeJitter = sin(game.time * 30.0 + cos(game.time * 40.0)) * 20.0 * dt
    let baseMove = toPlayer * enemy.speed * 0.6 * dt

    # Multiple jitter directions for electric feel
    let jitterAngle = game.time * 35.0
    let jitterX = cos(jitterAngle) * chargeJitter + cos(jitterAngle * 1.7) * chargeJitter * 0.5
    let jitterY = sin(jitterAngle) * chargeJitter + sin(jitterAngle * 1.3) * chargeJitter * 0.5

    enemy.pos = enemy.pos + baseMove + newVector2f(jitterX, jitterY)

    # Constant electric particles, timer-gated to ~6 spawns/sec regardless of fps
    if (game.time mod 0.15) < dt:
      let sparkX = enemy.pos.x + (rand(1.0) - 0.5) * enemy.radius * 2
      let sparkY = enemy.pos.y + (rand(1.0) - 0.5) * enemy.radius * 2
      spawnExplosionPooled(game.particlePool, sparkX, sparkY,
                     Color(r: 255, g: 255, b: 150, a: 255), 1)

  of "electric_surge":
    # Rapid zigzag movement like lightning bolt, smooth continuous direction, not discrete phase buckets
    let surgeAngle = arctan2(toPlayer.y, toPlayer.x) + sin(game.time * 15.0) * 0.5
    let surgeDir = newVector2f(cos(surgeAngle), sin(surgeAngle))
    enemy.pos = enemy.pos + surgeDir * enemy.speed * 1.0 * dt

    # Electric particles, gated to ~10 spawns/sec, not every frame
    if (game.time mod 0.1) < dt:
      spawnExplosionPooled(game.particlePool, enemy.pos.x, enemy.pos.y,
                     Color(r: 220, g: 230, b: 255, a: 200), 2)

  of "critical_discharge":
    # Ultra-chaotic movement without forced teleports; this phase should feel unstable,
    # but still preserve readable boss positioning.
    let dischargeAngle = game.time * 18.0 + sin(game.time * 37.0) * 0.7
    let chaosDir = newVector2f(cos(dischargeAngle), sin(dischargeAngle))
    let chaseBlend = sin(game.time * 2.6) * 0.5 + 0.5
    let dischargeDir = (chaosDir * (0.65 + chaseBlend * 0.25) + toPlayer * 0.35).normalize()
    enemy.pos = enemy.pos + dischargeDir * enemy.speed * 0.95 * dt
    if (game.time mod 0.12) < dt:
      spawnExplosionPooled(game.particlePool, enemy.pos.x, enemy.pos.y,
                     Color(r: 255, g: 255, b: 255, a: 220), 2)

  of "orbital_pattern":
    # Slow, calculated circular orbit (Orbital Commander phase 1)
    let orbitAngle = game.time * 0.8
    let orbitRadius = 200.0
    let orbitX = centerX + cos(orbitAngle) * orbitRadius
    let orbitY = centerY + sin(orbitAngle) * orbitRadius
    let toOrbit = (newVector2f(orbitX, orbitY) - enemy.pos).normalize()
    enemy.pos = enemy.pos + toOrbit * enemy.speed * dt

  of "satellite_swarm":
    # Complex multi-layer orbit (Orbital Commander phase 2)
    # Velocity-based movement toward the orbit target, no direct position assignment
    let swarmAngle1 = game.time * 1.2
    let swarmAngle2 = game.time * 0.6
    let innerRadius = 150.0 + sin(game.time * 2.0) * 30.0
    let outerRadius = 200.0
    let avgX = (cos(swarmAngle1) * innerRadius + cos(swarmAngle2) * outerRadius) / 2.0
    let avgY = (sin(swarmAngle1) * innerRadius + sin(swarmAngle2) * outerRadius) / 2.0
    var targetX = centerX + avgX
    var targetY = centerY + avgY
    let margin = enemy.radius + 10.0
    targetX = clamp(targetX, margin, game.screenWidth.float32 - margin)
    targetY = clamp(targetY, margin, game.screenHeight.float32 - margin)
    let toSwarm = (newVector2f(targetX, targetY) - enemy.pos).normalize()
    enemy.pos = enemy.pos + toSwarm * enemy.speed * 1.1 * dt

  of "electric_storm":
    # Fast erratic movement
    let angle = game.time * 2.5
    let stormDir = newVector2f(cos(angle + enemy.pos.x * 0.02), sin(angle + enemy.pos.y * 0.02))
    enemy.pos = enemy.pos + stormDir * enemy.speed * dt

  of "overcharged":
    # Very fast aggressive movement
    enemy.pos = enemy.pos + toPlayer * enemy.speed * 1.1 * dt

  of "deploy_satellites":
    # Hold a broad command orbit while satellites do the area control.
    let deployAngle = game.time * 0.55
    let deployTarget = newVector2f(centerX + cos(deployAngle) * 170.0,
                                   centerY + sin(deployAngle) * 115.0)
    let toDeploy = (deployTarget - enemy.pos).normalize()
    enemy.pos = enemy.pos + toDeploy * enemy.speed * 0.65 * dt

  of "multi_orbital":
    # Slow rotation around player - smooth constant-speed drift into orbit
    let moOrbitRadius = 150.0
    let moAngularSpeed = 0.35  # radians per second (slow, deliberate)
    let moCurrentAngle = arctan2(enemy.pos.y - game.player.pos.y, enemy.pos.x - game.player.pos.x)
    let moNextAngle = moCurrentAngle + moAngularSpeed * dt
    let moDesiredX = game.player.pos.x + cos(moNextAngle) * moOrbitRadius
    let moDesiredY = game.player.pos.y + sin(moNextAngle) * moOrbitRadius
    let moDes = newVector2f(moDesiredX - enemy.pos.x, moDesiredY - enemy.pos.y)
    let moDist = sqrt(moDes.x * moDes.x + moDes.y * moDes.y)
    if moDist > 0.1:
      let moStep = min(enemy.speed * 1.1 * dt, moDist)
      enemy.pos.x += (moDes.x / moDist) * moStep
      enemy.pos.y += (moDes.y / moDist) * moStep

  of "orbital_chaos":
    # Erratic orbital movement - smooth constant-speed with varying radius/angle
    let ocOrbitRadius = 200.0 + sin(game.time) * 50.0
    let ocAngularSpeed = 1.1 + sin(game.time * 1.7) * 0.4  # varies 0.7-1.5 rad/s
    let ocCurrentAngle = arctan2(enemy.pos.y - game.player.pos.y, enemy.pos.x - game.player.pos.x)
    let ocNextAngle = ocCurrentAngle + ocAngularSpeed * dt
    let ocDesiredX = game.player.pos.x + cos(ocNextAngle) * ocOrbitRadius
    let ocDesiredY = game.player.pos.y + sin(ocNextAngle) * ocOrbitRadius
    let ocDes = newVector2f(ocDesiredX - enemy.pos.x, ocDesiredY - enemy.pos.y)
    let ocDist = sqrt(ocDes.x * ocDes.x + ocDes.y * ocDes.y)
    if ocDist > 0.1:
      let ocStep = min(enemy.speed * 1.3 * dt, ocDist)
      enemy.pos.x += (ocDes.x / ocDist) * ocStep
      enemy.pos.y += (ocDes.y / ocDist) * ocStep

  of "aggressive_chase":
    # Fast aggressive chase
    enemy.pos = enemy.pos + toPlayer * enemy.speed * dt

  of "enraged_assault":
    # Rapid aggressive movement with smooth direction blending (sin-based, no frame dependency)
    # blend = 1 -> full chase, blend = 0 -> full strafe, cycles on a 3s period
    let enrageBlend = sin(game.time * (PI * 2.0 / 3.0)) * 0.5 + 0.5
    let sideDir = newVector2f(-toPlayer.y, toPlayer.x)
    let enrageDir = (toPlayer * enrageBlend + sideDir * (1.0 - enrageBlend)).normalize()
    enemy.pos = enemy.pos + enrageDir * enemy.speed * dt

  of "unstoppable":
    # Extremely fast movement toward player
    enemy.pos = enemy.pos + toPlayer * enemy.speed * 1.175 * dt

  of "meteor_storm":
    # Rapid circling movement with erratic patterns (Meteor Striker phase 2)
    let meteorAngle = game.time * 2.0 + sin(game.time * 3.0) * 0.5
    let meteorRadius = 180.0 + cos(game.time * 1.5) * 30.0
    let meteorX = game.player.pos.x + cos(meteorAngle) * meteorRadius
    let meteorY = game.player.pos.y + sin(meteorAngle) * meteorRadius
    let toTarget = (newVector2f(meteorX, meteorY) - enemy.pos).normalize()
    enemy.pos = enemy.pos + toTarget * enemy.speed * dt

  of "summon_frenzy":
    # Defensive positioning with occasional aggressive bursts (Summoner King phase 2)
    # sin-based blend: aggressive near peak, defensive near trough, 5s period, fps-independent
    let frenzyBlend = sin(game.time * (PI * 2.0 / 5.0)) * 0.5 + 0.5  # 0..1 over 5s
    if frenzyBlend > 0.92:
      # Aggressive burst near the peak of each 5s cycle
      enemy.pos = enemy.pos + toPlayer * enemy.speed * dt
    else:
      # Maintain defensive distance
      if playerDist < 220.0:
        let retreatDir = toPlayer * -1.0
        enemy.pos = enemy.pos + retreatDir * enemy.speed * 0.8 * dt
      else:
        let toCenter = (newVector2f(centerX, centerY) - enemy.pos).normalize()
        let strafeDir = newVector2f(-toPlayer.y, toPlayer.x)
        let holdDir = (strafeDir * 0.65 + toCenter * 0.35).normalize()
        enemy.pos = enemy.pos + holdDir * enemy.speed * 0.45 * dt

  of "berserk_rampage":
    # Extremely fast aggressive chase with wild movements (Berserker phase 3)
    let berserkerAngle = sin(game.time * 8.0) * 0.6
    let wildDir = newVector2f(
      toPlayer.x * cos(berserkerAngle) - toPlayer.y * sin(berserkerAngle),
      toPlayer.x * sin(berserkerAngle) + toPlayer.y * cos(berserkerAngle)
    )
    enemy.pos = enemy.pos + wildDir * enemy.speed * 1.1 * dt

  of "prism_defense":
    # Deliberate prism orbit around the arena, wide enough to avoid center parking.
    let prismOrbitRadius = 135.0
    let prismAngle = game.time * 0.5
    let prismX = centerX + cos(prismAngle) * prismOrbitRadius
    let prismY = centerY + sin(prismAngle) * prismOrbitRadius
    let toOrbit = (newVector2f(prismX, prismY) - enemy.pos).normalize()
    enemy.pos = enemy.pos + toOrbit * enemy.speed * 0.6 * dt

  of "prism_array":
    # Figure-8 movement pattern (Prism Architect phase 2)
    let figure8Time = game.time * 1.5
    let figure8X = centerX + sin(figure8Time) * 150.0
    let figure8Y = centerY + sin(figure8Time * 2.0) * 100.0
    let toFigure8 = (newVector2f(figure8X, figure8Y) - enemy.pos).normalize()
    enemy.pos = enemy.pos + toFigure8 * enemy.speed * dt

  of "light_cascade":
    # Rapid sweeping movement across the arena (Prism Architect phase 3)
    let sweepAngle = game.time * 2.5
    let sweepRadius = 180.0
    var sweepX = centerX + cos(sweepAngle) * sweepRadius
    var sweepY = centerY + sin(sweepAngle) * sweepRadius

    # Clamp within screen boundaries
    let margin = enemy.radius + 10.0
    sweepX = clamp(sweepX, margin, game.screenWidth.float32 - margin)
    sweepY = clamp(sweepY, margin, game.screenHeight.float32 - margin)

    # Smooth movement toward sweep target instead of instant position assignment
    let toSweep = (newVector2f(sweepX, sweepY) - enemy.pos).normalize()
    enemy.pos = enemy.pos + toSweep * enemy.speed * 1.1 * dt

  of "slow_time":
    # Very slow methodical movement (Timekeeper phase 1)
    enemy.pos = enemy.pos + toPlayer * enemy.speed * 0.4 * dt

  of "time_distortion":
    # Stuttering movement with temporal echoes (Timekeeper phase 2)
    # Smooth stutter: move fast during "on" half, freeze during "off" half of each 0.25s cycle
    let distortBlend = sin(game.time * PI * 4.0) * 0.5 + 0.5  # 0..1 at 4Hz, fully continuous
    enemy.pos = enemy.pos + toPlayer * enemy.speed * 0.95 * distortBlend * dt

  of "time_collapse":
    # Ultra-fast blinking movement (Timekeeper phase 3)
    # Smooth blend between charge-at-player and strafe on a 0.5s cycle
    let collapseBlend = sin(game.time * PI * 2.0) * 0.5 + 0.5  # 0..1 at 1Hz (0.5s per half)
    let strafeDir = newVector2f(-toPlayer.y, toPlayer.x)
    # High blend -> charge fast, low blend -> strafe
    let collapseBurst = isBossBehaviorBurstActive(enemy, dt, 0.4, 2.8, 3.6)
    let chaseContrib = toPlayer * (if collapseBurst: 1.15 else: 0.8) * collapseBlend
    let strafeContrib = strafeDir * (if collapseBurst: 0.75 else: 0.55) * (1.0 - collapseBlend)
    let collapseDir = (chaseContrib + strafeContrib).normalize()
    enemy.pos = enemy.pos + collapseDir * enemy.speed * dt

  of "chaotic_movement":
    # Unpredictable random movement (Chaos Weaver phase 1)
    # Multi-frequency time-based angle, looks chaotic but smooth, no per-frame rand
    let chaosFactor = sin(game.time * 7.0 + enemy.pos.x * 0.03) * 0.8
    let chaosAngle = game.time * 2.1 + sin(game.time * 5.3) * PI * 0.7
    let chaosDir = newVector2f(cos(chaosAngle + chaosFactor), sin(chaosAngle + chaosFactor))
    enemy.pos = enemy.pos + chaosDir * enemy.speed * 0.9 * dt

  of "entropy_field":
    # Erratic spiraling with sudden direction changes (Chaos Weaver phase 2)
    # Move toward a spiraling target instead of instant position set
    let entropySpiral = game.time * 3.0 + sin(game.time * 5.0)
    let entropyRadius = 160.0 + sin(game.time * 2.0) * 40.0
    var entropyX = game.player.pos.x + cos(entropySpiral) * entropyRadius
    var entropyY = game.player.pos.y + sin(entropySpiral) * entropyRadius

    # Clamp within screen boundaries
    let margin = enemy.radius + 10.0
    entropyX = clamp(entropyX, margin, game.screenWidth.float32 - margin)
    entropyY = clamp(entropyY, margin, game.screenHeight.float32 - margin)

    # Smooth movement toward orbit target instead of instant position assignment
    let toEntropy = (newVector2f(entropyX, entropyY) - enemy.pos).normalize()
    enemy.pos = enemy.pos + toEntropy * enemy.speed * 0.95 * dt

  of "total_chaos":
    # Maximum chaos - truly unpredictable
    # Time-based trigger (~once every 1.5s) instead of per-frame rand, fps-independent
    let chaosInterval = 1.5 + sin(game.time * 1.1) * 0.6  # 0.9-2.1s varying interval
    discard chaosInterval
    if tryBossBehaviorTeleport(game, enemy, dt, 4.0, 5.4, 150.0, 260.0, phase.color, 20, 140.0):
      let chaosAngle = rand(1.0) * PI * 2.0
      let chaosDist = 80.0 + rand(180.0)
      let newX = game.player.pos.x + cos(chaosAngle) * chaosDist
      let newY = game.player.pos.y + sin(chaosAngle) * chaosDist

      # Ensure within bounds
      enemy.pos = newVector2f(
        clamp(newX, 50.0, game.screenWidth.float32 - 50.0),
        clamp(newY, 50.0, game.screenHeight.float32 - 50.0)
      )

      # Chaotic teleport effect
      spawnExplosionPooled(game.particlePool, enemy.pos.x, enemy.pos.y,
                     Color(r: uint8(255 - rand(100)), g: uint8(rand(255)),
                           b: uint8(255 - rand(100)), a: 255), 25)
    else:
      # Erratic movement with random speed bursts
      let speedMult = 0.82 + rand(0.12)  # 82% to 94% speed between burst moments
      let wildAngle = game.time * 8.5 + sin(game.time * 4.0) * 1.2
      let wildDir = newVector2f(
        cos(wildAngle + sin(game.time * 8.0)),
        sin(wildAngle + cos(game.time * 11.0))
      )
      enemy.pos = enemy.pos + wildDir * enemy.speed * speedMult * dt

  of "balanced_assault":
    # Steady circling with balanced approach (Omega Entity phase 1)
    let balanceAngle = game.time * 1.2
    let balanceRadius = 190.0
    let balanceX = centerX + cos(balanceAngle) * balanceRadius
    let balanceY = centerY + sin(balanceAngle) * balanceRadius
    let toBalance = (newVector2f(balanceX, balanceY) - enemy.pos).normalize()
    enemy.pos = enemy.pos + toBalance * enemy.speed * dt

  of "aggressive_mixed":
    # Alternating between chase and strafe (Omega Entity phase 2), sin-based blend, no frame dependency
    # Completes one full chase->strafe cycle every 1.5s
    let mixedBlend = sin(game.time * (PI * 2.0 / 1.5)) * 0.5 + 0.5  # 0..1
    let mixedStrafe = newVector2f(-toPlayer.y, toPlayer.x)
    let mixedDir = (toPlayer * mixedBlend + mixedStrafe * ((1.0 - mixedBlend) * 0.75)).normalize()
    enemy.pos = enemy.pos + mixedDir * enemy.speed * dt

  of "adaptive_combat":
    # Smart positioning based on player distance (Omega Entity phase 3)
    if playerDist < 150.0:
      # Retreat and reposition
      let adaptRetreat = toPlayer * -1.0
      enemy.pos = enemy.pos + adaptRetreat * enemy.speed * 0.95 * dt
    elif playerDist > 280.0:
      # Close distance aggressively
      enemy.pos = enemy.pos + toPlayer * enemy.speed * dt
    else:
      # Optimal range - circle strafe
      let adaptStrafe = newVector2f(-toPlayer.y, toPlayer.x)
      enemy.pos = enemy.pos + adaptStrafe * enemy.speed * 0.9 * dt

  of "final_form":
    # Ultimate pattern - combines teleportation, aggression, and unpredictability (Omega Entity phase 4)
    let finalPhase = (game.time * 4.0).int mod 6
    case finalPhase
    of 0, 1:
      # Aggressive chase
      enemy.pos = enemy.pos + toPlayer * enemy.speed * dt
    of 2:
      # Rare reposition near the player; most of the phase stays movement-readable.
      let finalTeleportInterval = 5.5 + sin(game.time * 0.9) * 0.8
      if (game.time mod finalTeleportInterval) < dt:
        let finalAngle = rand(1.0) * PI * 2.0
        var newX = game.player.pos.x + cos(finalAngle) * 140.0
        var newY = game.player.pos.y + sin(finalAngle) * 140.0
        let margin = enemy.radius + 10.0
        newX = clamp(newX, margin, game.screenWidth.float32 - margin)
        newY = clamp(newY, margin, game.screenHeight.float32 - margin)
        enemy.pos = newVector2f(newX, newY)
      else:
        enemy.pos = enemy.pos + toPlayer * enemy.speed * 0.95 * dt
    of 3, 4:
      # Circle strafe at high speed (smooth velocity-based, not instant position set)
      let finalOrbitAngle = game.time * 2.5  # slowed from 5.0 to avoid jitter
      let finalOrbitRadius = 180.0
      let orbitTarget = newVector2f(
        game.player.pos.x + cos(finalOrbitAngle) * finalOrbitRadius,
        game.player.pos.y + sin(finalOrbitAngle) * finalOrbitRadius
      )
      let toOrbit = (orbitTarget - enemy.pos).normalize()
      enemy.pos = enemy.pos + toOrbit * enemy.speed * dt
    else:
      # Erratic chaos movement
      let chaosAngle = game.time * 8.0 + sin(game.time * 3.0)
      let chaosDir = newVector2f(cos(chaosAngle), sin(chaosAngle))
      enemy.pos = enemy.pos + chaosDir * enemy.speed * 0.95 * dt

  of "enraged":
    # Enraged behavior - Extremely aggressive meteor striker behavior (Apocalypse phase)
    # Ultra-fast aggressive pursuit with erratic movement patterns
    let enragedSpeed = enemy.speed * 0.95  # Phase speed already carries the pressure
    let enragedAngle = game.time * 4.0 + sin(game.time * 6.0) * 0.8

    # Primary movement: Aggressive chase with weaving patterns
    let baseChase = toPlayer * enragedSpeed * dt
    let weaveOffset = newVector2f(
      sin(enragedAngle) * 20.0 * dt,
      cos(enragedAngle * 1.3) * 20.0 * dt
    )

    # Combine chase and weave for unpredictable aggressive movement
    enemy.pos = enemy.pos + baseChase + weaveOffset

    # Occasional burst movement for added aggression
    if (game.time * 2.0).int mod 9 == 0 and (game.time mod 0.5) < dt:
      # Sudden burst toward player
      enemy.pos = enemy.pos + toPlayer * enemy.speed * 0.35 * dt

  else:
    discard

  if dt > 0 and not enemy.isDashing:
    let desiredPos = enemy.pos
    let frameMove = desiredPos - startPos
    let frameDistance = frameMove.length()
    let teleportDistance = max(90.0'f32, enemy.speed * dt * 5.0'f32)

    # Let deliberate long-range boss teleports snap, but give all regular
    # phase movement real mass by smoothing the velocity that reaches it.
    if frameDistance > 0.01'f32 and frameDistance <= teleportDistance:
      let desiredVel = frameMove * (1.0'f32 / dt)
      let isJuggernaut = enemy.bossDefinitionID == 8 # The Berserker Juggernaut
      let accel = if isJuggernaut: 2.8'f32 else: 1.7'f32
      let brake = if isJuggernaut: 0.55'f32 else: 0.8'f32
      enemy.pos = startPos
      discard applyEnemyInertia(enemy, desiredVel, dt, accel, brake)
      enemy.pos = enemy.pos + enemy.vel * dt
    elif frameDistance > teleportDistance:
      enemy.vel = newVector2f(0, 0)

proc pointSegmentDistance*(p, a, b: Vector2f): float32 =
  ## Shortest distance from point p to the segment a-b (for beam hit tests).
  let abx = b.x - a.x
  let aby = b.y - a.y
  let denom = abx * abx + aby * aby
  let t = if denom > 0.0001'f32:
            clamp(((p.x - a.x) * abx + (p.y - a.y) * aby) / denom, 0.0'f32, 1.0'f32)
          else: 0.0'f32
  let dx = p.x - (a.x + abx * t)
  let dy = p.y - (a.y + aby * t)
  sqrt(dx * dx + dy * dy)

proc spawnThunderstrike*(game: var Game, enemy: Enemy, attack: BossAttack, phase: BossPhaseDefinition) =
  warnings.spawnThunderstrikeInto(game.attackWarnings, game.particlePool, game.player, game.screenWidth, game.screenHeight, enemy, attack, phase)

proc spawnArcLattice*(game: var Game, enemy: Enemy, attack: BossAttack, phase: BossPhaseDefinition) =
  warnings.spawnArcLatticeInto(game.attackWarnings, game.particlePool, game.screenWidth, game.screenHeight, enemy, attack, phase)

proc spawnRicochetLaser*(game: var Game, enemy: Enemy, attack: BossAttack, phase: BossPhaseDefinition) =
  warnings.spawnRicochetLaserInto(game.attackWarnings, game.particlePool, game.player, game.screenWidth, game.screenHeight, enemy, attack, phase)

proc addBossAttackWarning*(game: var Game, enemy: Enemy, attack: BossAttack) =
  warnings.addBossAttackWarningInto(game.attackWarnings, game.player, enemy, attack)

proc spawnBossBullet(game: var Game, enemy: Enemy, attack: BossAttack,
                     phase: BossPhaseDefinition, dir: Vector2f,
                     speed = -1.0'f32, damage = -1.0'f32) =
  ## Canonical boss-bullet spawn from the boss's own position. A negative speed
  ## or damage means "use the default": attack.projectileSpeed and
  ## attack.damage * phase.damageMultiplier respectively.
  game.bullets.add(newBullet(
    x = enemy.pos.x, y = enemy.pos.y, direction = dir,
    speed = (if speed < 0: attack.projectileSpeed else: speed),
    damage = (if damage < 0: attack.damage * phase.damageMultiplier else: damage),
    fromPlayer = false, isBossBullet = true, sourceEnemyId = enemy.id,
    bossBulletShape = bossBulletShapeFor(enemy.bossDefinitionID),
    bulletRadius = attack.bulletRadius))

proc execBossAttackSpiral(game: var Game, enemy: Enemy, attack: BossAttack, phase: BossPhaseDefinition, bossDef: BossDefinition, toPlayer: Vector2f) =
  # A real spiral can't be fired in one instant from a single point - that is
  # always a ring. Instead we arm an emitter (updated each frame in
  # updateBossSpiralStream) that releases the volley's bullets one step at a
  # time while the emission angle steadily rotates. Earlier bullets are already
  # farther out at a smaller angle, so the live trail forms a spiral arm.
  const
    SpiralArms = 1                  # bullets per step (1 = single sweeping arm; raise for symmetric arms)
    SpiralWindTurnsDefault = 1.5'f32 # loops the arm makes when the attack doesn't override it
    SpiralWindowFrac = 0.6'f32      # fraction of the cooldown spent emitting (leaves a gap before the next volley)
  # Per-attack override: a spiral can set durationOrRadius to how many turns it
  # should wind (0 = use the default). Higher = a bigger, screen-filling coil.
  # durationOrRadius is otherwise unused by the spiral pattern.
  let windTurns = if attack.durationOrRadius > 0.0'f32: attack.durationOrRadius
                  else: SpiralWindTurnsDefault
  # The per-step angle must NOT evenly divide a full circle. With exactly
  # 2*PI/N spacing, every loop past the first stacks its bullets onto the same N
  # directions as the previous loop, collapsing the spiral into N straight radial
  # spokes. Using 2*PI/(N + 0.5) guarantees a non-divisor, and the half-step makes
  # each new loop interleave *between* the previous loop's bullets - so extra turns
  # thicken one continuous arm instead of stacking into spokes.
  let perTurn = max(2, attack.projectileCount).float32
  let steps = max(3, int(round((perTurn + 0.5'f32) * windTurns)))
  enemy.spiralEmitRemaining = steps
  enemy.spiralEmitTotal = steps
  enemy.spiralEmitArms = SpiralArms
  enemy.spiralEmitInterval = (attack.cooldown * SpiralWindowFrac) / steps.float32
  enemy.spiralEmitTimer = 0.0'f32  # fire the first step on the next stream update
  enemy.spiralEmitAngle = arctan2(toPlayer.y, toPlayer.x)  # start the arm aimed at the player
  enemy.spiralEmitAngleStep = (PI * 2.0) / (perTurn + 0.5'f32)  # off-ring spacing -> loops interleave, never align into spokes
  enemy.spiralEmitSpeed = attack.projectileSpeed          # full speed: slow bullets would time out mid-screen
  enemy.spiralEmitDamage = attack.damage * phase.damageMultiplier
  enemy.spiralEmitRadius = attack.bulletRadius

proc spiralBulletColor(progress: float32): Color =
  ## Gradient along the spiral arm: electric cyan at the leading (outer, first
  ## fired) end -> bright gold at the trailing (inner, last fired) end. The hue
  ## sweep makes the arm's winding direction read at a glance, and both ends
  ## contrast the bosses' usual pink bullets so the spiral pops off the field.
  let t = clamp(progress, 0.0'f32, 1.0'f32)
  proc mix(a, b: int): uint8 = uint8(a.float32 + (b - a).float32 * t)
  Color(r: mix(90, 255), g: mix(235, 215), b: mix(255, 60), a: 255)

proc updateBossSpiralStream*(game: var Game, enemy: Enemy, dt: float32) =
  ## Per-frame driver for the bapSpiral emitter armed by execBossAttackSpiral.
  ## Releases one spiral step (spiralEmitArms bullets) every spiralEmitInterval
  ## seconds, advancing the emission angle each step so the trail spirals.
  if enemy.spiralEmitRemaining <= 0: return
  enemy.spiralEmitTimer -= dt
  let arms = max(1, enemy.spiralEmitArms)
  # `while` (not `if`) so a long frame can release several overdue steps and the
  # leftover time carries into the next step, keeping the cadence even.
  while enemy.spiralEmitTimer <= 0.0'f32 and enemy.spiralEmitRemaining > 0:
    # Position along the arm (0 = first/outer bullet, 1 = last/inner) drives the
    # colour gradient so the whole volley reads as one continuous winding ribbon.
    let progress = if enemy.spiralEmitTotal > 1:
        (enemy.spiralEmitTotal - enemy.spiralEmitRemaining).float32 / (enemy.spiralEmitTotal - 1).float32
      else: 0.0'f32
    let col = spiralBulletColor(progress)
    for k in 0..<arms:
      let angle = enemy.spiralEmitAngle + k.float32 * (PI * 2.0 / arms.float32)
      let dir = newVector2f(cos(angle), sin(angle))
      game.bullets.add(newBullet(
        x = enemy.pos.x, y = enemy.pos.y, direction = dir,
        speed = enemy.spiralEmitSpeed, damage = enemy.spiralEmitDamage,
        fromPlayer = false, isBossBullet = true, sourceEnemyId = enemy.id,
        bossBulletShape = bossBulletShapeFor(enemy.bossDefinitionID),
        bulletRadius = enemy.spiralEmitRadius, colorOverride = col))
      # Colour-matched muzzle spark at the firing edge - a rotating flash that
      # traces the emission angle and reinforces the spiral's sweep.
      let muzzleX = enemy.pos.x + dir.x * (enemy.radius + 6.0'f32)
      let muzzleY = enemy.pos.y + dir.y * (enemy.radius + 6.0'f32)
      spawnExplosionPooled(game.particlePool, muzzleX, muzzleY, col, 2)
    enemy.spiralEmitAngle += enemy.spiralEmitAngleStep
    enemy.spiralEmitRemaining -= 1
    enemy.spiralEmitTimer += enemy.spiralEmitInterval


proc execBossAttackBurst(game: var Game, enemy: Enemy, attack: BossAttack, phase: BossPhaseDefinition, bossDef: BossDefinition, toPlayer: Vector2f) =
  # Rapid burst in spread pattern
  let baseAngle = arctan2(toPlayer.y, toPlayer.x)
  for i in 0..<attack.projectileCount:
    let offset = (i.float32 - attack.projectileCount.float32 / 2.0) * attack.spreadAngle.degToRad() / attack.projectileCount.float32
    let angle = baseAngle + offset
    let dir = newVector2f(cos(angle), sin(angle))
    spawnBossBullet(game, enemy, attack, phase, dir)


proc execBossAttackWave(game: var Game, enemy: Enemy, attack: BossAttack, phase: BossPhaseDefinition, bossDef: BossDefinition, toPlayer: Vector2f) =
  # SpecialData modes:
  # - "rainbow_wave": Colorful cascading pattern (Boss 9)
  # - "temporal_wave": Time-distorted slow bullets (Boss 10)
  # - Default: Standard sine wave pattern

  let waveMode = attack.specialData

  # Configure wave behavior based on mode
  let (speedMultiplier, colorScheme) = case waveMode
    of "rainbow_wave":
      (1.0, "rainbow")  # Normal speed, rainbow particles
    of "temporal_wave":
      (0.7, "temporal")  # 30% slower, cyan particles
    else:
      (1.0, "default")  # Standard

  for i in 0..<attack.projectileCount:
    let t = i.float32 / attack.projectileCount.float32
    let angle = t * attack.spreadAngle.degToRad() - attack.spreadAngle.degToRad() / 2.0 + arctan2(toPlayer.y, toPlayer.x)
    let dir = newVector2f(cos(angle), sin(angle))

    let bulletSpeed = attack.projectileSpeed * speedMultiplier

    spawnBossBullet(game, enemy, attack, phase, dir, speed = bulletSpeed)

    # Special visual effects per wave type
    case colorScheme
    of "rainbow":
      # Create rainbow trail particles
      let rainbowColor = RainbowPalette[i mod 7]
      spawnExplosionPooled(game.particlePool, enemy.pos.x, enemy.pos.y, rainbowColor, 4)
    of "temporal":
      # Cyan time-distortion particles
      spawnExplosionPooled(game.particlePool, enemy.pos.x, enemy.pos.y,
                    Color(r: 100, g: 220, b: 220, a: 255), 3)
    else:
      discard


proc execBossAttackTargeted(game: var Game, enemy: Enemy, attack: BossAttack, phase: BossPhaseDefinition, bossDef: BossDefinition, toPlayer: Vector2f) =
  # Direct shots at player
  # SpecialData modes:
  # - "royal_sigils": Summoner King - a fan of slow golden homing sigils that
  #   gently curve toward the player (reuses the enemy-homing path in game.nim).
  # - Default: plain aimed shots
  if attack.specialData == "royal_sigils":
    const sigilGold = Color(r: 255, g: 215, b: 90, a: 255)
    # Self-contained telegraph: a royal summon ring + gold charge burst at the boss.
    game.attackWarnings.add(newAttackWarning(enemy.pos.x, enemy.pos.y, awtBossSummon, 0.45, enemy.id))
    for i in 0..<12:
      let a = i.float32 * PI * 2.0 / 12.0
      spawnExplosionPooled(game.particlePool,
                           enemy.pos.x + cos(a) * 28.0, enemy.pos.y + sin(a) * 28.0,
                           sigilGold, 4)
    # Slow homing sigils fanned at the player; gentle tracking keeps them dodgeable.
    let baseAngle = arctan2(toPlayer.y, toPlayer.x)
    let count = max(1, attack.projectileCount)
    for i in 0..<count:
      let offset = (i.float32 - count.float32 / 2.0) * attack.spreadAngle.degToRad() / count.float32
      let dir = newVector2f(cos(baseAngle + offset), sin(baseAngle + offset))
      var sigil = newBullet(
        x = enemy.pos.x, y = enemy.pos.y, direction = dir,
        speed = attack.projectileSpeed, damage = attack.damage * phase.damageMultiplier,
        fromPlayer = false, isHoming = true, isBossBullet = true, sourceEnemyId = enemy.id,
        bossBulletShape = bossBulletShapeFor(enemy.bossDefinitionID),
        colorOverride = sigilGold, bulletRadius = attack.bulletRadius)
      sigil.lifetime = 5.0  # outlive the default 4s so they track the player longer
      game.bullets.add(sigil)
    return

  for i in 0..<attack.projectileCount:
    let spread = if attack.projectileCount > 1:
      (i.float32 - attack.projectileCount.float32 / 2.0) * attack.spreadAngle.degToRad() / attack.projectileCount.float32
    else: 0.0
    let angle = arctan2(toPlayer.y, toPlayer.x) + spread
    let dir = newVector2f(cos(angle), sin(angle))
    spawnBossBullet(game, enemy, attack, phase, dir)


proc execBossAttackCircle(game: var Game, enemy: Enemy, attack: BossAttack, phase: BossPhaseDefinition, bossDef: BossDefinition, toPlayer: Vector2f) =
  # Perfect ring of bullets with thematic variants
  # SpecialData modes:
  # - "time_ring": Temporal distortion ring with pulsing cyan bullets (Boss 10)
  # - Default: Standard perfect circle

  let circleMode = attack.specialData

  # Configure circle behavior based on mode
  let (bulletSpeed, particleColor, rotationOffset) = case circleMode
    of "time_ring":
      (attack.projectileSpeed * 0.85, Color(r: 100, g: 220, b: 220, a: 255), game.time * 0.5)  # Slower temporal bullets with rotation
    else:
      (attack.projectileSpeed, phase.color, 0.0)  # Standard

  # Create pre-fire visual effect for time_ring
  if circleMode == "time_ring":
    # Create temporal distortion rings before firing
    for ring in 0..2:
      let ringRadius = 30.0 + ring.float32 * 25.0
      for i in 0..<16:
        let angle = i.float32 * PI * 2.0 / 16.0
        let ringX = enemy.pos.x + cos(angle) * ringRadius
        let ringY = enemy.pos.y + sin(angle) * ringRadius
        spawnExplosionPooled(game.particlePool, ringX, ringY,
                      Color(r: 100, g: 220, b: 220, a: 255), 3)

  # Create circle of bullets
  for i in 0..<attack.projectileCount:
    let angle = i.float32 * PI * 2.0 / attack.projectileCount.float32 + rotationOffset
    let dir = newVector2f(cos(angle), sin(angle))
    spawnBossBullet(game, enemy, attack, phase, dir, speed = bulletSpeed)

    # Add temporal particle trail for time_ring
    if circleMode == "time_ring":
      let trailRadius = 20.0
      let trailX = enemy.pos.x + cos(angle) * trailRadius
      let trailY = enemy.pos.y + sin(angle) * trailRadius
      spawnExplosionPooled(game.particlePool, trailX, trailY, particleColor, 2)


proc execBossAttackLaser(game: var Game, enemy: Enemy, attack: BossAttack, phase: BossPhaseDefinition, bossDef: BossDefinition, toPlayer: Vector2f) =
  # Boss laser with proper warning system
  # Laser patterns customized via specialData
  # EXISTING: "cross_laser", "rotating_grid", "prismatic_cage", "laser_snipe"

  let patternType = attack.specialData
  let laserCount = case patternType
    of "rotating_grid": attack.projectileCount * 2  # Double density for grid
    of "prismatic_cage": attack.projectileCount * 3  # Triple density for cage
    of "splitting_laser": attack.projectileCount  # Triangle pattern
    of "hexagonal_prism": 6  # Always 6 beams
    of "prismatic_storm": attack.projectileCount * 2  # Massive light show!
    of "temporal_beam": attack.projectileCount  # Temporal cross pattern
    of "chaos_beam": rand(attack.projectileCount) + attack.projectileCount  # Random chaos
    of "omega_beam": attack.projectileCount  # Ultimate beams (count tuned in boss_definitions; was *2 = 8, an undodgeable web)
    else: attack.projectileCount

  # Calculate all laser angles for the warning system
  var warningAngles: seq[float32] = @[]

  # For cross_laser pattern, always create 4 beams (cardinal directions)
  let actualLaserCount = if patternType == "cross_laser": 4 else: laserCount

  for i in 0..<actualLaserCount:
    let angle = case patternType
      of "rotating_grid":
        # Grid pattern - two perpendicular sets
        if i.float < actualLaserCount / 2:
          i.float32 * attack.spreadAngle.degToRad() / (actualLaserCount / 2).float32
        else:
          (i.float32 - actualLaserCount.float / 2.0) * attack.spreadAngle.degToRad() / (actualLaserCount / 2).float32 + PI / 2.0

      of "splitting_laser":
        # Triangle pattern (120° apart) that appears to split/refract
        i.float32 * (PI * 2.0 / 3.0) + game.time * 0.5  # Slow rotation

      of "hexagonal_prism":
        # Perfect hexagonal pattern (60° apart) - geometric precision
        i.float32 * (PI / 3.0) + game.time * 0.3

      of "prismatic_storm":
        # Massive radial array with rainbow effect
        # Create dense radial pattern with slight randomization for light scatter
        let baseAngle = i.float32 * (PI * 2.0) / actualLaserCount.float32
        baseAngle + (rand(1.0) - 0.5) * 0.15  # Slight scatter for prismatic effect

      of "prismatic_cage":
        # Calculate angle biased toward player with radial spread
        let angleToPlayer = arctan2(game.player.pos.y - enemy.pos.y,
                                     game.player.pos.x - enemy.pos.x)

        # Create proper radial pattern with player bias
        let segmentAngle = (PI * 2.0) / actualLaserCount.float32
        let baseAngle = i.float32 * segmentAngle

        # 40% of lasers aim near player, 60% are radial
        if rand(100) < 40:
          # Aim toward player with spread
          angleToPlayer + (rand(1.0) - 0.5) * (PI / 3.0)  # ±60° spread
        else:
          # Radial distribution with slight randomization
          baseAngle + (rand(1.0) - 0.5) * 0.2  # ±6° randomization

      of "laser_snipe":
        # Rapid fire lasers aimed directly at player with minimal spread
        let angleToPlayer = arctan2(game.player.pos.y - enemy.pos.y, game.player.pos.x - enemy.pos.x)
        # Very tight spread around player position (5 degrees)
        angleToPlayer + (rand(1.0) - 0.5) * 0.175

      of "cross_laser":
        # Cross pattern - always 4 beams in cardinal directions (0°, 90°, 180°, 270°)
        i.float32 * (PI / 2.0) + game.time

      of "temporal_beam":
        # TEMPORAL BEAM - Time-distorted cross pattern with slow rotation
        # Creates 4 beams in rotating cardinal directions
        # Beams have temporal distortion effect (stuttering, phasing)
        i.float32 * (PI / 2.0) + game.time * 0.4  # Slower rotation for time effect

      of "chaos_beam":
        # CHAOS BEAM - Completely unpredictable laser angles with clustering
        # Create random cluster center for grouped chaos
        let clusterCenter = if i == 0: rand(PI * 2.0) else: warningAngles[0] + rand(0.5)
        let clusterSpread = 0.3 + rand(0.7)  # Variable clustering (0.3-1.0 radians)
        # Random angle with slight clustering around center for chaotic but not totally random
        clusterCenter + (rand(1.0) - 0.5) * clusterSpread

      of "omega_beam":
        # OMEGA BEAM - Ultimate laser pattern combining ALL previous mechanics
        # Three different sub-patterns: radial, player-tracking, and temporal spiral

        # Pattern 1: Rotating radial beams (Boss 4 style) - first third of lasers
        if i < actualLaserCount div 3:
          i.float32 * (PI * 2.0) / (actualLaserCount div 3).float32 + game.time * 0.8

        # Pattern 2: Player-tracking spread (Boss 9 style) - middle third
        elif i < (actualLaserCount * 2) div 3:
          let idx = i - (actualLaserCount div 3)
          let angleToPlayer = arctan2(game.player.pos.y - enemy.pos.y,
                                       game.player.pos.x - enemy.pos.x)
          let spread = (idx.float32 - (actualLaserCount div 3).float32 / 2.0) * 0.3
          angleToPlayer + spread

        # Pattern 3: Temporal spiraling beams (Boss 10 style) - last third
        else:
          let idx = i - (actualLaserCount * 2) div 3
          let spiral = idx.float32 * 0.5 + game.time * 0.6
          spiral + sin(game.time * 2.0) * 0.4  # Wavy temporal distortion

      else:
        # Default pattern - distribute evenly
        i.float32 * (PI * 2.0) / actualLaserCount.float32 + game.time
    warningAngles.add(angle)

  # Add boss laser warning with proper visual indicators
  # WARNING: Show for 1.2 seconds before firing (much longer than current 0.3s)
  const BOSS_LASER_WARNING_TIME = 1.2
  let laserDamage = (attack.damage * phase.damageMultiplier).int

  # PRE-FIRE VISUAL EFFECTS for special laser patterns
  if patternType == "chaos_beam":
    # Create flickering chaotic particles along laser paths
    for angle in warningAngles:
      for step in 1..8:
        let dist = step.float32 * 40.0
        let px = enemy.pos.x + cos(angle) * dist
        let py = enemy.pos.y + sin(angle) * dist
        # Flickering random colors for chaos
        let chaosColor = Color(
          r: (100 + rand(155)).uint8,
          g: (50 + rand(205)).uint8,
          b: (100 + rand(155)).uint8,
          a: 255
        )
        spawnExplosionPooled(game.particlePool, px, py, chaosColor, 3)

  elif patternType == "omega_beam":
    # MASSIVE rainbow particle explosion for ultimate laser
    for ring in 0..6:
      let ringRadius = 30.0 + ring.float32 * 28.0
      for i in 0..<24:
        let angle = i.float32 * PI * 2.0 / 24.0
        let px = enemy.pos.x + cos(angle) * ringRadius
        let py = enemy.pos.y + sin(angle) * ringRadius
        # Rainbow spectrum
        let rainbowColor = case i mod 7:
          of 0: Color(r: 255, g: 0, b: 0, a: 255)
          of 1: Color(r: 255, g: 127, b: 0, a: 255)
          of 2: Color(r: 255, g: 255, b: 0, a: 255)
          of 3: Color(r: 0, g: 255, b: 0, a: 255)
          of 4: Color(r: 0, g: 255, b: 255, a: 255)
          of 5: Color(r: 0, g: 0, b: 255, a: 255)
          else: Color(r: 255, g: 0, b: 255, a: 255)
        spawnExplosionPooled(game.particlePool, px, py, rainbowColor, 7)

    # Add electric arcs (Boss 6 style)
    for i in 0..<20:
      let angle = i.float32 * PI * 2.0 / 20.0
      let arcX = enemy.pos.x + cos(angle) * 70.0
      let arcY = enemy.pos.y + sin(angle) * 70.0
      spawnExplosionPooled(game.particlePool, arcX, arcY,
                    Color(r: 255, g: 255, b: 200, a: 255), 6)

  # Adjust laser length based on pattern type
  # For prismatic_cage and laser_snipe, calculate length to reach screen edge
  # Use diagonal distance from center to corner to ensure full coverage
  let laserLength = if patternType in ["prismatic_cage", "laser_snipe"]:
    # Calculate diagonal distance from center to corner for full screen coverage
    # Add extra margin to guarantee lasers always reach beyond screen edges
    let centerX = game.screenWidth.float32 / 2.0
    let centerY = game.screenHeight.float32 / 2.0
    let diagonalDistance = sqrt(centerX * centerX + centerY * centerY)
    # Use 1.5x diagonal distance to ensure lasers always extend beyond screen
    diagonalDistance * 1.5
  else:
    800.0

  game.attackWarnings.add(newBossLaserWarning(
    enemy.pos.x, enemy.pos.y,
    BOSS_LASER_WARNING_TIME,
    warningAngles,
    laserLength,  # Adjusted based on pattern type
    laserDamage,
    attack.durationOrRadius,  # Laser active duration
    patternType,  # Pass the pattern type for proper laser creation
    enemy.enemyType,  # Track which enemy type created this attack
    enemy.id  # Pass enemy ID so warning can follow boss
  ))


proc execBossAttackBarrage(game: var Game, enemy: Enemy, attack: BossAttack, phase: BossPhaseDefinition, bossDef: BossDefinition, toPlayer: Vector2f) =
  # Massive bullet spray with multiple themes
  # SpecialData modes:
  # - "voltage_burst": Electric explosion with yellow bullets (Boss 6)
  # - "blood_burst": Berserker rage explosion with red bullets (Boss 8)
  # - "orbital_bombardment": Space bombardment from above (Boss 7)
  # - "random_spread": Chaotic spread with random angles (Boss 11 Phase 1)
  # - "chaos_storm", "entropy_burst": Randomized chaos attacks (Boss 11)
  # - "chromatic_burst": Rainbow prismatic explosion (Boss 9 Phase 2)
  # - "light_burst": Pure brilliance explosion (Boss 9 Phase 3)
  # - "time_shatter": Reality-shattering temporal explosion (Boss 10 Phase 3)
  # - "omega_barrage": Ultimate massive barrage from final boss (Boss 12 Phase 4)

  let barrageMode = attack.specialData
  let isChaosAttack = barrageMode in ["chaos_storm", "entropy_burst", "random_spread"]
  let isElectricAttack = barrageMode == "voltage_burst"
  let isBerserkAttack = barrageMode == "blood_burst"
  let isOrbitalAttack = barrageMode == "orbital_bombardment"
  let isChromaticAttack = barrageMode == "chromatic_burst"
  let isLightAttack = barrageMode == "light_burst"
  let isTimeShatter = barrageMode == "time_shatter"
  let isOmegaBarrage = barrageMode == "omega_barrage"

  # Randomize count ±30% for chaos
  let bulletCount = if isChaosAttack:
    (attack.projectileCount.float32 * (0.7 + rand(0.6))).int
  elif isOmegaBarrage:
    # Honor the count from boss_definitions (already tuned to 30) instead of
    # doubling it. The old *2 re-inflated the ring to 60 bullets, at the boss's
    # firing radius that leaves no player-sized gap, which made the final phase
    # an undodgeable wall and silently cancelled every nerf made to the data.
    attack.projectileCount
  else:
    attack.projectileCount

  # Randomize spread for chaos
  let spreadAngle = if isChaosAttack:
    180.0 + rand(180.0)  # Might not even be 360!
  else:
    360.0

  # MODE-SPECIFIC PRE-EXPLOSION EFFECTS
  if isElectricAttack:
    # Create electric sparks radiating outward
    for i in 0..<bulletCount div 2:
      let angle = i.float32 * PI * 2.0 / (bulletCount div 2).float32
      let sparkX = enemy.pos.x + cos(angle) * 40.0
      let sparkY = enemy.pos.y + sin(angle) * 40.0
      spawnExplosionPooled(game.particlePool, sparkX, sparkY,
                    Color(r: 255, g: 255, b: 100, a: 255), 4)

  elif isBerserkAttack:
    # Create blood/rage particles in circular waves
    for ring in 0..2:
      let ringRadius = 35.0 + ring.float32 * 25.0
      for i in 0..<12:
        let angle = i.float32 * PI * 2.0 / 12.0
        let bloodX = enemy.pos.x + cos(angle) * ringRadius
        let bloodY = enemy.pos.y + sin(angle) * ringRadius
        spawnExplosionPooled(game.particlePool, bloodX, bloodY,
                      Color(r: 200 + rand(55).uint8, g: 0, b: 0, a: 255), 5)

    # Screen shake for rage
    addShake(game.dopamine.screenShake, siLarge)

  elif isOrbitalAttack:
    # Create star field effect - bullets rain from space
    for i in 0..<8:
      let angle = i.float32 * PI * 2.0 / 8.0
      let starX = enemy.pos.x + cos(angle) * 60.0
      let starY = enemy.pos.y + sin(angle) * 60.0
      spawnExplosionPooled(game.particlePool, starX, starY,
                    Color(r: 200, g: 150, b: 255, a: 255), 6)

  elif isChromaticAttack:
    # Create rainbow prismatic rings expanding outward
    for ring in 0..3:
      let ringRadius = 30.0 + ring.float32 * 20.0
      for i in 0..<12:
        let angle = i.float32 * PI * 2.0 / 12.0
        let prismX = enemy.pos.x + cos(angle) * ringRadius
        let prismY = enemy.pos.y + sin(angle) * ringRadius
        # Rainbow colors based on position
        let rainbowColor = RainbowPalette[i mod 7]
        spawnExplosionPooled(game.particlePool, prismX, prismY, rainbowColor, 5)

  elif isLightAttack:
    # Create brilliant white/rainbow light explosion
    for ring in 0..4:
      let ringRadius = 25.0 + ring.float32 * 18.0
      for i in 0..<16:
        let angle = i.float32 * PI * 2.0 / 16.0
        let lightX = enemy.pos.x + cos(angle) * ringRadius
        let lightY = enemy.pos.y + sin(angle) * ringRadius
        # Brilliant white with rainbow tint
        let tint = case (i + ring) mod 7
          of 0: Color(r: 255, g: 200, b: 200, a: 255)
          of 1: Color(r: 255, g: 230, b: 200, a: 255)
          of 2: Color(r: 255, g: 255, b: 200, a: 255)
          of 3: Color(r: 200, g: 255, b: 200, a: 255)
          of 4: Color(r: 200, g: 230, b: 255, a: 255)
          of 5: Color(r: 230, g: 200, b: 255, a: 255)
          else: Color(r: 255, g: 255, b: 255, a: 255)  # Pure white
        spawnExplosionPooled(game.particlePool, lightX, lightY, tint, 6)

    # Intense screen shake for brilliance
    addShake(game.dopamine.screenShake, siLarge)

  elif isTimeShatter:
    # TIME SHATTER - Reality-breaking temporal fracture explosion
    # Create massive expanding temporal cracks radiating outward
    for ring in 0..6:
      let ringRadius = 20.0 + ring.float32 * 25.0
      for i in 0..<20:
        let angle = i.float32 * PI * 2.0 / 20.0
        let shatterX = enemy.pos.x + cos(angle) * ringRadius
        let shatterY = enemy.pos.y + sin(angle) * ringRadius
        # Bright cyan-white temporal fracture particles
        let brightness = 100 + (ring * 20)
        spawnExplosionPooled(game.particlePool, shatterX, shatterY,
                      Color(r: brightness.uint8, g: 220 + (ring * 5).uint8, b: 220 + (ring * 5).uint8, a: 255), 5)

    # Create radiating time crack lines extending far outward
    for i in 0..<16:
      let angle = i.float32 * PI * 2.0 / 16.0
      for step in 1..20:
        let crackRadius = step.float32 * 20.0
        let crackX = enemy.pos.x + cos(angle) * crackRadius
        let crackY = enemy.pos.y + sin(angle) * crackRadius
        # Cyan temporal cracks with fading intensity
        let fade = (255 - step * 8).clamp(100, 255)
        spawnExplosionPooled(game.particlePool, crackX, crackY,
                      Color(r: 100, g: 220, b: 220, a: fade.uint8), 3)

    # Add swirling temporal distortion particles
    for spiral in 0..<8:
      for step in 0..15:
        let spiralAngle = (spiral.float32 * PI / 4.0) + (step.float32 * 0.3)
        let spiralRadius = step.float32 * 12.0
        let spiralX = enemy.pos.x + cos(spiralAngle) * spiralRadius
        let spiralY = enemy.pos.y + sin(spiralAngle) * spiralRadius
        spawnExplosionPooled(game.particlePool, spiralX, spiralY,
                      Color(r: 150, g: 255, b: 255, a: 255), 2)

    # MASSIVE screen shake for reality-shattering effect
    addShake(game.dopamine.screenShake, siMassive)

  elif barrageMode == "omega_barrage":
    # OMEGA BARRAGE - Ultimate final boss attack combining all elements
    # Creates massive multi-colored explosion with all previous boss themes
    # Rainbow prismatic rings (like Boss 9)
    for ring in 0..5:
      let ringRadius = 25.0 + ring.float32 * 30.0
      for i in 0..<18:
        let angle = i.float32 * PI * 2.0 / 18.0
        let omegaX = enemy.pos.x + cos(angle) * ringRadius
        let omegaY = enemy.pos.y + sin(angle) * ringRadius
        # Rainbow colors cycling through spectrum
        let rainbowColor = case i mod 7
          of 0: Color(r: 255, g: 0, b: 0, a: 255)     # Red
          of 1: Color(r: 255, g: 127, b: 0, a: 255)   # Orange
          of 2: Color(r: 255, g: 255, b: 0, a: 255)   # Yellow
          of 3: Color(r: 0, g: 255, b: 0, a: 255)     # Green
          of 4: Color(r: 0, g: 255, b: 255, a: 255)   # Cyan
          of 5: Color(r: 0, g: 0, b: 255, a: 255)     # Blue
          else: Color(r: 255, g: 0, b: 255, a: 255)   # Magenta
        spawnExplosionPooled(game.particlePool, omegaX, omegaY, rainbowColor, 6)

    # Electric crackling effects (like Boss 6)
    for i in 0..<bulletCount div 3:
      let angle = i.float32 * PI * 2.0 / (bulletCount div 3).float32
      let sparkX = enemy.pos.x + cos(angle) * 55.0
      let sparkY = enemy.pos.y + sin(angle) * 55.0
      spawnExplosionPooled(game.particlePool, sparkX, sparkY,
                    Color(r: 255, g: 255, b: 100, a: 255), 5)

    # Temporal rifts (like Boss 10)
    for i in 0..<12:
      let angle = i.float32 * PI * 2.0 / 12.0
      for step in 1..12:
        let riftRadius = step.float32 * 22.0
        let riftX = enemy.pos.x + cos(angle) * riftRadius
        let riftY = enemy.pos.y + sin(angle) * riftRadius
        spawnExplosionPooled(game.particlePool, riftX, riftY,
                      Color(r: 150, g: 255, b: 255, a: 255), 3)

    # ABSOLUTELY MASSIVE screen shake - this is the ultimate attack
    addShake(game.dopamine.screenShake, siMassive)

  for i in 0..<bulletCount:
    let angle = if isChaosAttack:
      (i.float32 / bulletCount.float32) * spreadAngle.degToRad() + rand(1.0)
    else:
      i.float32 * PI * 2.0 / bulletCount.float32

    let dir = newVector2f(cos(angle), sin(angle))

    # Randomize speed ±25% for chaos
    let speed = if isChaosAttack:
      attack.projectileSpeed * (0.75 + rand(0.5))
    else:
      attack.projectileSpeed

    # Randomize damage ±10% for chaos
    let damage = if isChaosAttack:
      attack.damage * phase.damageMultiplier * (0.9 + rand(0.2))
    else:
      attack.damage * phase.damageMultiplier

    spawnBossBullet(game, enemy, attack, phase, dir, speed = speed, damage = damage)

  # MODE-SPECIFIC EXPLOSIONS
  let (explosionSize, explosionColor) = case barrageMode
    of "voltage_burst":
      (45, Color(r: 255, g: 255, b: 200, a: 255))  # Bright yellow electric
    of "blood_burst":
      (50, Color(r: 255, g: 0, b: 0, a: 255))  # Massive red rage explosion
    of "orbital_bombardment":
      (40, Color(r: 180, g: 120, b: 255, a: 255))  # Purple space explosion
    of "chromatic_burst":
      (42, Color(r: 255, g: 150, b: 255, a: 255))  # Pink/magenta prismatic
    of "light_burst":
      (55, Color(r: 255, g: 255, b: 255, a: 255))  # Massive white brilliance
    of "time_shatter":
      (65, Color(r: 150, g: 255, b: 255, a: 255))  # Massive cyan temporal shatter
    of "random_spread":
      (32, Color(r: rand(200).uint8 + 55, g: rand(200).uint8 + 55, b: rand(200).uint8 + 55, a: 255))  # Random bright chaos
    of "chaos_storm", "entropy_burst":
      (35, Color(r: rand(255).uint8, g: rand(255).uint8, b: rand(255).uint8, a: 255))  # Random chaos
    of "omega_barrage":
      (70, Color(r: 255, g: 50, b: 255, a: 255))  # MASSIVE pink/magenta final boss explosion
    else:
      (30, phase.color)  # Standard

  spawnExplosionPooled(game.particlePool, enemy.pos.x, enemy.pos.y, explosionColor, explosionSize)


proc execBossAttackPulse(game: var Game, enemy: Enemy, attack: BossAttack, phase: BossPhaseDefinition, bossDef: BossDefinition, toPlayer: Vector2f) =
  # Expanding ring with multiple thematic variants
  # SpecialData modes:
  # - "electric_discharge": Electric shockwave with crackling particles (Boss 6)
  # - "ground_slam": Berserker impact with rocks/debris (Boss 8 Phase 2)
  # - "earthquake": MASSIVE berserker slam, screen shake, cracks (Boss 8 Phase 3)
  # - "overload_pulse": Intense electric overload (Boss 6 Phase 3)
  # - "gravity_pulse": Space-themed gravity wave (Boss 7)
  # - "blinding_pulse": Brilliant light explosion (Boss 9 Phase 3)
  # - "entropy_wave": Chaotic unstable shockwave (Boss 11 Phase 3)
  # - "omega_pulse": Ultimate combined shockwave (Boss 12 Phase 4)
  # - Default: Standard pulse

  let pulseMode = attack.specialData

  # Configure pulse behavior and visuals based on mode
  let (bulletCount, particleColor, explosionSize) = case pulseMode
    of "electric_discharge":
      (32, Color(r: 255, g: 255, b: 150, a: 255), 35)  # Dense electric pulse
    of "ground_slam":
      (28, Color(r: 150, g: 75, b: 30, a: 255), 40)  # Fewer but stronger, brown/rock color
    of "earthquake":
      (30, Color(r: 100, g: 50, b: 20, a: 255), 60)  # MASSIVE slam, huge shake
    of "overload_pulse":
      (32, Color(r: 255, g: 255, b: 255, a: 255), 50)  # Maximum density, white overload
    of "gravity_pulse":
      (30, Color(r: 150, g: 100, b: 255, a: 255), 45)  # Space purple
    of "blinding_pulse":
      (34, Color(r: 255, g: 255, b: 255, a: 255), 55)  # Brilliant white light explosion
    of "chrono_pulse":
      (28, Color(r: 100, g: 220, b: 220, a: 255), 42)  # Temporal shockwave, cyan
    of "chrono_break":
      (32, Color(r: 150, g: 255, b: 255, a: 255), 58)  # Massive time shattering pulse
    of "entropy_wave":
      (rand(20) + 20, Color(r: rand(255).uint8, g: rand(255).uint8, b: rand(255).uint8, a: 255), 50)  # Chaotic random pulse
    of "omega_pulse":
      (38, Color(r: 255, g: 100, b: 255, a: 255), 65)  # ULTIMATE pulse - huge and powerful
    of "banish_nova":
      (16, Color(r: 80, g: 220, b: 120, a: 255), 38)  # Summoner King: green banishment ring
    else:
      (24, phase.color, 35)  # Standard pulse

  # TRIGGER SCREEN SHAKE
  addShake(game.dopamine.screenShake, siLarge)

  # Create expanding pulse ring
  for i in 0..<bulletCount:
    let angle = i.float32 * PI * 2.0 / bulletCount.float32
    let dir = newVector2f(cos(angle), sin(angle))
    spawnBossBullet(game, enemy, attack, phase, dir)

  # MODE-SPECIFIC VISUAL ENHANCEMENTS
  case pulseMode:
    of "electric_discharge", "overload_pulse":
      # Create multiple expanding particle rings
      let ringCount = if pulseMode == "overload_pulse": 4 else: 3
      for ring in 0..<ringCount:
        let ringRadius = 30.0 + ring.float32 * 25.0
        for i in 0..<16:
          let angle = i.float32 * PI * 2.0 / 16.0
          let sparkX = enemy.pos.x + cos(angle) * ringRadius
          let sparkY = enemy.pos.y + sin(angle) * ringRadius
          spawnExplosionPooled(game.particlePool, sparkX, sparkY,
                        Color(r: 255, g: 255, b: 200, a: 255), 3)

    of "ground_slam", "earthquake":
      # Create rock/debris particles flying outward
      let debrisCount = if pulseMode == "earthquake": 32 else: 20
      for i in 0..<debrisCount:
        let angle = i.float32 * PI * 2.0 / debrisCount.float32
        let debrisRadius = 40.0 + rand(60.0)
        let debrisX = enemy.pos.x + cos(angle) * debrisRadius
        let debrisY = enemy.pos.y + sin(angle) * debrisRadius
        # Brown/orange debris colors
        spawnExplosionPooled(game.particlePool, debrisX, debrisY,
                      Color(r: 120 + rand(80).uint8, g: 60 + rand(40).uint8, b: 20, a: 255), 4)

      # Earthquake gets GROUND CRACKS (radial lines)
      if pulseMode == "earthquake":
        for i in 0..<8:
          let angle = i.float32 * PI * 2.0 / 8.0
          for step in 1..10:
            let crackRadius = step.float32 * 15.0
            let crackX = enemy.pos.x + cos(angle) * crackRadius
            let crackY = enemy.pos.y + sin(angle) * crackRadius
            spawnExplosionPooled(game.particlePool, crackX, crackY,
                          Color(r: 80, g: 40, b: 10, a: 255), 2)

    of "gravity_pulse":
      # Space-themed spiral particles
      for ring in 0..3:
        let ringRadius = 35.0 + ring.float32 * 30.0
        for i in 0..<12:
          let angle = i.float32 * PI * 2.0 / 12.0 + ring.float32 * 0.3  # Spiral offset
          let gravX = enemy.pos.x + cos(angle) * ringRadius
          let gravY = enemy.pos.y + sin(angle) * ringRadius
          spawnExplosionPooled(game.particlePool, gravX, gravY,
                        Color(r: 150, g: 100, b: 255, a: 255), 3)

    of "blinding_pulse":
      # Brilliant prismatic light explosion with rainbow rings
      for ring in 0..5:
        let ringRadius = 30.0 + ring.float32 * 25.0
        for i in 0..<20:
          let angle = i.float32 * PI * 2.0 / 20.0
          let lightX = enemy.pos.x + cos(angle) * ringRadius
          let lightY = enemy.pos.y + sin(angle) * ringRadius
          # Rainbow prismatic effect
          let lightColor = case (i + ring) mod 7
            of 0: Color(r: 255, g: 200, b: 200, a: 255)
            of 1: Color(r: 255, g: 230, b: 200, a: 255)
            of 2: Color(r: 255, g: 255, b: 200, a: 255)
            of 3: Color(r: 200, g: 255, b: 200, a: 255)
            of 4: Color(r: 200, g: 230, b: 255, a: 255)
            of 5: Color(r: 230, g: 200, b: 255, a: 255)
            else: Color(r: 255, g: 255, b: 255, a: 255)
          spawnExplosionPooled(game.particlePool, lightX, lightY, lightColor, 4)

    of "chrono_pulse":
      # Temporal distortion waves - expanding time rings
      for ring in 0..3:
        let ringRadius = 35.0 + ring.float32 * 28.0
        for i in 0..<14:
          let angle = i.float32 * PI * 2.0 / 14.0
          let timeX = enemy.pos.x + cos(angle) * ringRadius
          let timeY = enemy.pos.y + sin(angle) * ringRadius
          # Cyan/turquoise temporal particles with brightness variation
          let brightness = 100 + (ring * 35)
          spawnExplosionPooled(game.particlePool, timeX, timeY,
                        Color(r: brightness.uint8, g: 220, b: 220, a: 255), 3)

    of "chrono_break":
      # MASSIVE reality-breaking time shatter effect
      # Create multiple layers of temporal fractures
      for ring in 0..5:
        let ringRadius = 30.0 + ring.float32 * 30.0
        for i in 0..<18:
          let angle = i.float32 * PI * 2.0 / 18.0
          let shatterX = enemy.pos.x + cos(angle) * ringRadius
          let shatterY = enemy.pos.y + sin(angle) * ringRadius
          # Bright cyan-white time shatter particles
          spawnExplosionPooled(game.particlePool, shatterX, shatterY,
                        Color(r: 150, g: 255, b: 255, a: 255), 5)

      # Add radial time cracks extending outward
      for i in 0..<12:
        let angle = i.float32 * PI * 2.0 / 12.0
        for step in 1..15:
          let crackRadius = step.float32 * 18.0
          let crackX = enemy.pos.x + cos(angle) * crackRadius
          let crackY = enemy.pos.y + sin(angle) * crackRadius
          spawnExplosionPooled(game.particlePool, crackX, crackY,
                        Color(r: 100, g: 220, b: 220, a: 255), 2)

    of "entropy_wave":
      # ENTROPY WAVE - Chaotic unstable shockwave with randomized effects
      # Create multiple chaotic spiral patterns with random colors
      for spiral in 0..<rand(4) + 3:  # 3-6 spirals
        for ring in 0..rand(5) + 3:  # Variable rings per spiral
          let ringRadius = 25.0 + ring.float32 * (20.0 + rand(15.0))
          let spiralAngle = (spiral.float32 * PI * 2.0 / (spiral + 3).float32) + rand(PI)
          for i in 0..<rand(8) + 8:  # Variable particle count
            let angle = i.float32 * PI * 2.0 / (i + 8).float32 + spiralAngle
            let chaosX = enemy.pos.x + cos(angle) * ringRadius
            let chaosY = enemy.pos.y + sin(angle) * ringRadius
            # Completely random colors for pure chaos
            let chaosColor = Color(
              r: rand(200).uint8 + 55,
              g: rand(200).uint8 + 55,
              b: rand(200).uint8 + 55,
              a: 255
            )
            spawnExplosionPooled(game.particlePool, chaosX, chaosY, chaosColor, rand(5) + 2)

      # Add random crackling effects
      for i in 0..<rand(15) + 10:
        let randomAngle = rand(PI * 2.0)
        let randomRadius = rand(120.0) + 30.0
        let crackX = enemy.pos.x + cos(randomAngle) * randomRadius
        let crackY = enemy.pos.y + sin(randomAngle) * randomRadius
        spawnExplosionPooled(game.particlePool, crackX, crackY,
                      Color(r: rand(255).uint8, g: rand(255).uint8, b: rand(255).uint8, a: 255), 4)

    of "omega_pulse":
      # OMEGA PULSE - Ultimate shockwave combining all boss themes
      # Rainbow prismatic rings (like Boss 9)
      for ring in 0..6:
        let ringRadius = 30.0 + ring.float32 * 32.0
        for i in 0..<20:
          let angle = i.float32 * PI * 2.0 / 20.0
          let omegaX = enemy.pos.x + cos(angle) * ringRadius
          let omegaY = enemy.pos.y + sin(angle) * ringRadius
          # Rainbow spectrum
          let rainbowColor = case i mod 7
            of 0: Color(r: 255, g: 0, b: 0, a: 255)     # Red
            of 1: Color(r: 255, g: 127, b: 0, a: 255)   # Orange
            of 2: Color(r: 255, g: 255, b: 0, a: 255)   # Yellow
            of 3: Color(r: 0, g: 255, b: 0, a: 255)     # Green
            of 4: Color(r: 0, g: 255, b: 255, a: 255)   # Cyan
            of 5: Color(r: 0, g: 0, b: 255, a: 255)     # Blue
            else: Color(r: 255, g: 0, b: 255, a: 255)   # Magenta
          spawnExplosionPooled(game.particlePool, omegaX, omegaY, rainbowColor, 6)

      # Electric crackling (like Boss 6)
      for i in 0..<16:
        let angle = i.float32 * PI * 2.0 / 16.0
        let sparkX = enemy.pos.x + cos(angle) * 65.0
        let sparkY = enemy.pos.y + sin(angle) * 65.0
        spawnExplosionPooled(game.particlePool, sparkX, sparkY,
                      Color(r: 255, g: 255, b: 150, a: 255), 5)

      # Temporal rifts (like Boss 10)
      for i in 0..<14:
        let angle = i.float32 * PI * 2.0 / 14.0
        for step in 1..18:
          let riftRadius = step.float32 * 20.0
          let riftX = enemy.pos.x + cos(angle) * riftRadius
          let riftY = enemy.pos.y + sin(angle) * riftRadius
          spawnExplosionPooled(game.particlePool, riftX, riftY,
                        Color(r: 150, g: 255, b: 255, a: 255), 3)

      # Light brilliance bursts (like Boss 9)
      for burst in 0..4:
        let burstAngle = burst.float32 * PI * 2.0 / 5.0
        for step in 0..8:
          let burstRadius = step.float32 * 25.0
          let burstX = enemy.pos.x + cos(burstAngle) * burstRadius
          let burstY = enemy.pos.y + sin(burstAngle) * burstRadius
          spawnExplosionPooled(game.particlePool, burstX, burstY,
                        Color(r: 255, g: 255, b: 255, a: 255), 4)

    else:
      discard  # No extra effects for default

  # Central explosion (size varies by mode)
  spawnExplosionPooled(game.particlePool, enemy.pos.x, enemy.pos.y, particleColor, explosionSize)


proc execBossAttackSummon(game: var Game, enemy: Enemy, attack: BossAttack, phase: BossPhaseDefinition, bossDef: BossDefinition, toPlayer: Vector2f) =
  # Spawn minion enemies around the boss - customizable via specialData
  # Parse specialData to determine minion types: "minion_circle", "minion_triangle", "minion_mixed"
  var minionType = etCircle  # Default
  var useVariation = false

  if attack.specialData != "":
    case attack.specialData
    of "minion_circle":
      minionType = etCircle
    of "minion_triangle":
      minionType = etTriangle
    of "minion_cube":
      minionType = etCube
    of "minion_pentagon":
      minionType = etPentagon
    of "minion_mixed":
      useVariation = true  # Vary minion types
    else:
      minionType = etCircle

  # CAP: Count existing boss-spawned enemies to prevent overwhelming defensive builds
  var bossSpawnedCount = 0
  for e in game.enemies:
    if e.spawnedByBoss:
      bossSpawnedCount += 1

  # Maximum boss-spawned enemies allowed at once (configurable cap)
  const MAX_BOSS_SPAWNED_ENEMIES = 12

  # Calculate how many we can actually spawn
  let maxToSpawn = max(0, MAX_BOSS_SPAWNED_ENEMIES - bossSpawnedCount)
  let actualSpawnCount = min(attack.projectileCount, maxToSpawn)

  # Only proceed if we can spawn at least one enemy
  if actualSpawnCount <= 0:
    # Skip spawning but still show visual feedback
    spawnExplosionPooled(game.particlePool, enemy.pos.x, enemy.pos.y, phase.color, 8)
  else:
    for i in 0..<actualSpawnCount:
      let angle = i.float32 * PI * 2.0 / actualSpawnCount.float32
      let spawnDist = enemy.radius + 60.0  # Spawn outside boss radius
      let spawnX = enemy.pos.x + cos(angle) * spawnDist
      let spawnY = enemy.pos.y + sin(angle) * spawnDist

      # Determine this minion's type
      var thisType = minionType
      if useVariation:
        # Vary between circle, triangle, and cube based on index
        thisType = case i mod 3
          of 0: etCircle
          of 1: etTriangle
          else: etCube

      # Create minion with determined type
      # Use a fixed base difficulty so minions don't become stronger over time
      let minion = newEnemy(
        spawnX, spawnY,
        2.5,  # Fixed difficulty - does NOT scale with time
        thisType,
        game
      )
      # Mark as boss-spawned so it doesn't drop coins (prevent farming)
      minion.spawnedByBoss = true
      # Summoned enemies are already inside the arena, so they should engage immediately.
      minion.hasEnteredScreen = true

      case minion.enemyType
      of etTriangle:
        # Enter the triangle wind-up state right away instead of spawning "mid-dash".
        minion.dashCooldown = 0.0
        minion.dashTimer = 0.35 + rand(0.35)
      of etDiamond:
        minion.dashTimer = 0.0
        minion.dashCooldown = 0.75 + rand(0.5)
      else:
        discard

      # NERF: Make boss-summoned minions smaller and slower
      minion.radius = minion.radius * 1.0  # 35% smaller
      minion.collisionRadius = minion.collisionRadius * 1.0  # Keep collision consistent
      minion.speed = minion.speed * 0.70  # 30% slower

      game.enemies.add(minion)

    # Mark a summoned wave as active. Clearing every add in it opens the boss's
    # vulnerability window (Summoner King objective). Wave size drives the pips.
    # Gated to the bwoSummonSigils objective so a future summoner with a different
    # weak-point doesn't get its real objective's required/progress clobbered.
    if enemy.isBoss and enemy.weakPoint.kind == bwoSummonSigils:
      enemy.summonWaveActive = true
      enemy.weakPoint.required = max(1, actualSpawnCount)
      enemy.weakPoint.progress = 0

    # Visual feedback for summoning
    spawnExplosionPooled(game.particlePool, enemy.pos.x, enemy.pos.y, phase.color, 15)


proc execBossAttackMeteor(game: var Game, enemy: Enemy, attack: BossAttack, phase: BossPhaseDefinition, bossDef: BossDefinition, toPlayer: Vector2f) =
  # Falling projectiles from above, screen-wide barrage with a guaranteed dodge gap
  # SpecialData modes:
  # - "warn_impact":    Show warnings before meteors arrive
  # - "massive_impact": Larger meteorites, more coverage
  # - "apocalypse_mode": Maximum meteorites, longer warnings
  # - "satellite_strike": Purple space theme
  # Boss-3 signature modes (use the real falling-rock `Meteorite` system or
  # angled barrages instead of the plain vertical column):
  # - "meteor_volley":  Aimed cluster of large rocks slams the player's spot.
  # - "meteor_ring":    Rocks rain in a ring around the player (safe in the eye).
  # - "comet_cascade":  Diagonal comets sweep across the arena with one safe lane.

  let meteorMode = attack.specialData
  let sw = game.screenWidth.float32
  let sh = game.screenHeight.float32

  # --- Boss-3 signature meteor variants -------------------------------------
  # These give the Meteor Striker more identity than the basic vertical column.
  # meteor_volley / meteor_ring spawn genuine falling rocks (warning circle +
  # fast fall + impact burst) via game.meteorites, so they read very differently
  # from the bullet barrage. They return early; none of the column layout runs.
  let rockDamage = max(1, int(attack.damage * phase.damageMultiplier))
  case meteorMode
  of "meteor_volley":
    # AIMED STRIKE: a tight cluster of oversized meteors hammers the player's
    # current position, forcing a committed sideways dodge before they land.
    let count = max(3, attack.projectileCount)
    let warn = 0.9'f32
    let rockR = max(attack.bulletRadius, 12.0'f32) * 1.6'f32
    let baseX = game.player.pos.x
    let baseY = clamp(game.player.pos.y, sh * 0.40'f32, sh * 0.85'f32)
    # Shared incoming direction so the cluster reads as one barrage streaking in
    # from the sky (long diagonal fire-trails) rather than dots dropping straight
    # down. Enter from whichever side has the most room above the player.
    let spawnFromRight = baseX < sw * 0.5'f32
    let entryDx = (if spawnFromRight: 1.0'f32 else: -1.0'f32) * 540.0'f32
    for k in 0 ..< count:
      # Wider center-to-center spacing so the impacts read as a spread barrage,
      # not one overlapping clump (each rock gets its own clear warning circle).
      let spread = (k.float32 - (count - 1).float32 * 0.5'f32) * (rockR * 3.0'f32)
      let tx = clamp(baseX + spread + (rand(24.0'f32) - 12.0'f32), 40.0'f32, sw - 40.0'f32)
      let ty = clamp(baseY + (rand(60.0'f32) - 30.0'f32), sh * 0.35'f32, sh * 0.9'f32)
      # Spawn well off the top edge and offset sideways -> long visible streak.
      # Stagger the heights so the cluster lands as a quick drumroll, not a slap.
      let sx = tx + entryDx + (rand(60.0'f32) - 30.0'f32)
      let sy = -140.0'f32 - rand(120.0'f32) - k.float32 * 28.0'f32
      let m = newMeteorite(tx, ty, sx, sy, rockDamage, warn)
      m.radius = rockR
      m.splashDamage = rockDamage.float32 * 0.5'f32   # impact blast = 50% of center hit
      game.meteorites.add(m)
    addShake(game.dopamine.screenShake, siMedium)
    return
  of "meteor_ring":
    # ENCIRCLE: rocks slam down in a ring around the player. Standing still in
    # the eye is safe; the danger is being caught mid-traversal across the band.
    let count = max(6, attack.projectileCount)
    let warn = 1.0'f32
    let rockR = max(attack.bulletRadius, 11.0'f32) * 1.3'f32
    let ringR = 150.0'f32 + rand(30.0'f32)
    let startA = rand(TAU)
    for k in 0 ..< count:
      let a = startA + k.float32 * (TAU / count.float32)
      let tx = clamp(game.player.pos.x + cos(a) * ringR, 40.0'f32, sw - 40.0'f32)
      let ty = clamp(game.player.pos.y + sin(a) * ringR, sh * 0.18'f32, sh * 0.9'f32)
      # Spawn high above so the rock (and its fire-trail) is visible falling in.
      let m = newMeteorite(tx, ty, tx, -160.0'f32 - rand(80.0'f32), rockDamage, warn)
      m.radius = rockR
      m.splashDamage = rockDamage.float32 * 0.5'f32   # impact blast = 50% of center hit
      game.meteorites.add(m)
    addShake(game.dopamine.screenShake, siMedium)
    return
  of "comet_cascade":
    # DIAGONAL SWEEP: a single coherent slanted line of parallel comets streaks
    # across the arena at one shared angle. Every comet ENTERS FROM THE TOP edge
    # and travels the SAME distance down to the bottom, so they descend as one
    # front. (The previous geometry walked each comet back to whichever screen
    # edge it hit first -> the ones nearest the entry side spawned half-way down a
    # side wall and, sharing the spawn instant but not the travel length, arrived
    # out of sync. That read as a scattered, "weird" spawn.) Unlike the vertical
    # columns there is NO designated safe lane: the comets are spaced so the
    # player can thread between ANY adjacent pair. Uses the warning->bullet path;
    # the telegraph follows the real spawn->impact line (see drawMeteorWarning).
    let warn = 0.8'f32
    let rockR = (if attack.bulletRadius > 0: attack.bulletRadius else: 9.0'f32) * 1.25'f32
    let dirSign = if rand(1.0) < 0.5: 1.0'f32 else: -1.0'f32   # sweep left or right
    let ang = 0.45'f32 * dirSign                               # ~26deg from vertical
    let dir = newVector2f(sin(ang), cos(ang))                  # down-and-sideways
    # Anchor BOTH endpoints screen-relative and SOLVE the travel length, so the
    # spawn->impact distance is identical for every comet at any resolution (see
    # the boss-meteor resolution-scaling note). CRITICAL: the comet bullet is
    # culled the instant it sits beyond |50px| off-screen, so spawns live just
    # above the top edge (-48px). The entry band is then restricted so each
    # comet's bottom impact also lands back inside the arena, keeping the impact
    # ring / arrowhead telegraph on-screen.
    const cullM   = 48.0'f32                                   # stay inside |50px| cull
    const marginX = 30.0'f32                                   # keep entries/impacts off the edge
    let spawnY = -cullM                                        # just above the top edge
    let exitY  = sh * 0.92'f32                                 # bottom impact line
    let travel = (exitY - spawnY) / dir.y                      # identical for every comet
    let drift  = dir.x * travel                                # horizontal shift top->bottom
    # Top-edge entry band whose comets all land back inside [marginX, sw-marginX].
    let bandLo = max(marginX, marginX - drift)
    let bandHi = min(sw - marginX, sw - marginX - drift)
    let bandWidth = max(0.0'f32, bandHi - bandLo)
    # Dodge corridor: the comet lines are tilted by `ang`, so a horizontal spacing
    # `dx` opens a PERPENDICULAR gap of `dx*cos(ang)` between neighbours. Size that
    # gap to the player plus a rock on each side (+ clearance) and solve for `dx`,
    # so the player can slip between any two adjacent comets without a safe lane.
    let corridor = 2.0'f32 * (game.player.radius + rockR) + 24.0'f32
    let dx = corridor / cos(ang)                              # cos(ang) == cos(-ang) > 0
    # Fit as many comets as the band allows at that spacing, capped by the def's
    # projectileCount; spacing then only widens (never tightens) the corridor.
    let count = clamp(int(bandWidth / dx) + 1, 3, max(3, attack.projectileCount))
    let spacing = if count > 1: bandWidth / (count - 1).float32 else: 0.0'f32
    for k in 0 ..< count:
      let sx = bandLo + k.float32 * spacing                    # on-screen top entry
      let spawn = newVector2f(sx, spawnY)
      let impact = spawn + dir * travel                        # on-screen bottom impact
      var w = newAttackWarning(impact.x, impact.y, awtMeteor, warn, enemy.id)
      w.targetPos = spawn
      w.bulletSpeed = attack.projectileSpeed
      w.bulletDamage = attack.damage * phase.damageMultiplier
      w.bulletRadius = rockR
      w.overrideColor = Color(r: 255, g: 170, b: 60, a: 255)
      game.attackWarnings.add(w)
    addShake(game.dopamine.screenShake, siSmall)
    return
  else: discard

  # Resolve bullet radius: 0 means "use default 6" (see BossAttack type comment).
  # A zero radius would make spacing = 0, causing an infinite loop in the layout loop below.
  let rawMeteorRadius = if attack.bulletRadius > 0: attack.bulletRadius else: 6.0'f32

  # Configure per-mode parameters
  let (warningTime, meteorColor, bRadius) = case meteorMode
    of "massive_impact":
      (0.65'f32, Color(r: 255, g: 100, b: 0, a: 255),
       rawMeteorRadius * 1.4)
    of "apocalypse_mode":
      (0.85'f32, Color(r: 255, g: 50, b: 0, a: 255),
       rawMeteorRadius * 1.6)
    of "satellite_strike":
      (0.75'f32, Color(r: 180, g: 120, b: 255, a: 255),
       rawMeteorRadius)
    else:  # "warn_impact" and everything else
      (0.55'f32, Color(r: 255, g: 150, b: 50, a: 255),
       rawMeteorRadius)

  # Layout: distribute meteors across 50% of the screen width (sw defined above)
  let margin    = 15.0'f32                       # keep away from edges
  let spacing   = bRadius * 5.0'f32              # center-to-center distance (2.5x->5.0x = 50% fewer meteors)

  # Barrage zone: half the screen width, randomly offset so it isn't always on one side
  let zoneWidth = sw * 0.5'f32
  let zoneStart = margin + rand(max(0.0'f32, sw - 2.0'f32 * margin - zoneWidth))
  let zoneEnd   = zoneStart + zoneWidth

  # Guaranteed safe gap: player must physically fit through it
  let gapHalf   = game.player.radius + bRadius + 28.0'f32  # 28 px clearance each side
  let gapMin    = zoneStart + gapHalf
  let gapMax    = zoneEnd   - gapHalf
  let gapCenter = gapMin + rand(max(0.0'f32, gapMax - gapMin))

  # Collect all meteor X positions inside the zone that fall outside the gap
  var meteorXs: seq[float32] = @[]
  var mx = zoneStart + bRadius
  while mx <= zoneEnd - bRadius:
    if abs(mx - gapCenter) >= gapHalf:
      meteorXs.add(mx)
    mx += spacing

  # For each position, place a timed warning, bullet spawns when warning expires
  let impactY = clamp(game.player.pos.y + 80.0'f32,
                      game.screenHeight.float32 * 0.5'f32,
                      game.screenHeight.float32 * 0.85'f32)

  for targetX in meteorXs:
    var w = newAttackWarning(targetX, impactY, awtMeteor, warningTime, enemy.id)
    w.targetPos = newVector2f(targetX, -50.0)   # bullet spawn point
    w.bulletSpeed = attack.projectileSpeed
    w.bulletDamage = attack.damage * phase.damageMultiplier
    w.bulletRadius = bRadius
    w.overrideColor = meteorColor
    game.attackWarnings.add(w)


proc execBossAttackOrbit(game: var Game, enemy: Enemy, attack: BossAttack, phase: BossPhaseDefinition, bossDef: BossDefinition, toPlayer: Vector2f) =
  # ORBITAL SATELLITE SYSTEM
  # Creates persistent satellites that orbit, shoot, and can be destroyed
  # SpecialData modes:
  # - "electric_charges": Electric Boss 6 - yellow sparking satellites
  # - "satellite_orbit": Orbital Boss 7 - space theme, slower, methodical
  # - "dual_layer_orbit": Two concentric rings of satellites
  # - "orbital_storm": Three concentric rings (maximum chaos)

  # Only create satellites if they don't already exist AND the boss isn't
  # currently in its vulnerability window (all satellites were just destroyed)
  # AND the post-vulnerability cooldown has fully expired.
  # Without this guard the bapOrbit attack fires again on its cooldown and
  # immediately repopulates satellites, cutting the exposure window short.
  if enemy.satellites.len == 0 and enemy.weakPoint.exposedTimer <= 0 and
     enemy.weakPoint.cooldownTimer <= 0:
    let orbitMode = attack.specialData
    let satelliteCount = attack.projectileCount
    let baseOrbitRadius = attack.durationOrRadius

    # Configure layers based on mode
    let (layerCount, rotationSpeed, satelliteColor) = case orbitMode
      of "electric_charges":
        (1, 1.2, Color(r: 255, g: 255, b: 100, a: 255))  # Single fast layer, yellow
      of "satellite_orbit":
        (1, 0.6, Color(r: 150, g: 100, b: 255, a: 255))  # Single slow layer, purple
      of "dual_layer_orbit":
        (2, 1.0, Color(r: 200, g: 150, b: 255, a: 255))  # Two layers, medium speed
      of "orbital_storm":
        (3, 1.3, Color(r: 180, g: 120, b: 255, a: 255))  # Three layers, fast
      else:
        (1, 1.0, phase.color)  # Default single layer

    # Create satellites in multiple orbital layers
    for layer in 0..<layerCount:
      # Distribute satellites across layers, spreading any remainder onto the
      # first layers so the full authored projectileCount actually spawns.
      # Plain `div` silently dropped satellites (8/3 -> 6, 5/2 -> 4), which
      # under-delivered the boss AND shrank its all-satellites-down window.
      let satsThisLayer = satelliteCount div layerCount +
        (if layer < satelliteCount mod layerCount: 1 else: 0)
      let layerRadius = baseOrbitRadius + (layer.float32 * 50.0)  # Each layer 50px apart
      let angleOffset = if layer mod 2 == 0: 0.0 else: (PI / satsThisLayer.float32)  # Stagger alternating layers
      # Alternating layers rotate in opposite directions for visual complexity
      let layerRotationSpeed = if layer mod 2 == 0: rotationSpeed else: -rotationSpeed

      for i in 0..<satsThisLayer:
        let angle = i.float32 * (PI * 2.0 / satsThisLayer.float32) + angleOffset
        enemy.satellites.add(OrbitalSatellite(
          pos: newVector2f(
            enemy.pos.x + cos(angle) * layerRadius,
            enemy.pos.y + sin(angle) * layerRadius
          ),
          angle: angle,
          radius: layerRadius,
          rotationSpeed: layerRotationSpeed,
          hp: 1,  # 1-hit kill, satellites are glass-cannon threats, not tanks
          shootTimer: 0.5 + rand(1.0) + (layer.float32 * 0.3),  # Later layers shoot slightly later
          owner: enemy.id,
          laserActive: false,
          laserTarget: game.player.pos,  # Initialize with current player position
          laserChargeTime: 0.0
        ))

    # Visual effects based on mode
    let (explosionSize, explosionColor) = case orbitMode
      of "electric_charges":
        (35, Color(r: 255, g: 255, b: 150, a: 255))  # Bright yellow sparks
      of "satellite_orbit":
        (30, Color(r: 150, g: 100, b: 255, a: 255))  # Purple space theme
      of "dual_layer_orbit":
        (40, Color(r: 200, g: 150, b: 255, a: 255))  # Bright purple
      of "orbital_storm":
        (50, Color(r: 255, g: 200, b: 255, a: 255))  # Massive pink explosion
      else:
        (30, phase.color)

    spawnExplosionPooled(game.particlePool, enemy.pos.x, enemy.pos.y, explosionColor, explosionSize)

    # Extra ring effects for multi-layer
    if layerCount > 1:
      for layer in 0..<layerCount:
        let ringRadius = baseOrbitRadius + (layer.float32 * 50.0)
        for i in 0..<8:
          let angle = i.float32 * (PI * 2.0 / 8.0)
          let ringX = enemy.pos.x + cos(angle) * ringRadius
          let ringY = enemy.pos.y + sin(angle) * ringRadius
          spawnExplosionPooled(game.particlePool, ringX, ringY, satelliteColor, 3)


proc execBossAttackChain(game: var Game, enemy: Enemy, attack: BossAttack, phase: BossPhaseDefinition, bossDef: BossDefinition, toPlayer: Vector2f) =
  # CHAIN LIGHTNING SYSTEM
  # Chain mechanics with visual lightning arcs
  # SpecialData modes:
  # - "chain_basic": Simple 3-chain lightning (Phase 1)
  # - "chain_storm": Multi-target chain web (Phase 2)
  # - "chain_overload": Maximum chain lightning chaos (Phase 3)

  let chainMode = attack.specialData

  # Configure chain behavior based on mode
  let (chainCount, chainsPerDirection, chainDecay) = case chainMode
    of "chain_basic":
      (attack.projectileCount, 2, 0.75)  # 3 directions, 2 chains each, 75% decay
    of "chain_storm":
      (attack.projectileCount, 3, 0.65)  # 5 directions, 3 chains each, 65% decay
    of "chain_overload":
      (attack.projectileCount, 4, 0.6)   # 8 directions, 4 chains each, 60% decay
    else:
      (attack.projectileCount, 2, 0.75)  # Default to basic

  # Create chain lightning in multiple directions
  for i in 0..<chainCount:
    let baseAngle = i.float32 * (PI * 2.0 / chainCount.float32) + rand(0.3)
    let dir = newVector2f(cos(baseAngle), sin(baseAngle))

    var currentDamage = attack.damage * phase.damageMultiplier
    var lastX = enemy.pos.x
    var lastY = enemy.pos.y

    # Create chain sequence in this direction
    for chainStep in 1..chainsPerDirection:
      let distance = chainStep.float32 * 80.0  # Distance between chain points
      let chainX = enemy.pos.x + dir.x * distance
      let chainY = enemy.pos.y + dir.y * distance

      # Check if chain is still on screen
      if chainX < 0 or chainX > game.screenWidth.float32 or
         chainY < 0 or chainY > game.screenHeight.float32:
        break

      # VISUAL: Persistent jagged lightning arc between chain points
      spawnLightningBolt(game, newVector2f(lastX, lastY), newVector2f(chainX, chainY))

      # Create bullet at chain point
      game.bullets.add(newBullet(
        x = chainX, y = chainY,
        direction = dir,
        speed = 180.0 + rand(40.0),  # Slightly randomized speed
        damage = currentDamage,
        fromPlayer = false,
        isBossBullet = true,
        sourceEnemyId = enemy.id,
        bossBulletShape = bossBulletShapeFor(enemy.bossDefinitionID)
      ))

      # Chain impact explosion
      spawnExplosionPooled(game.particlePool, chainX, chainY,
                    Color(r: 255, g: 255, b: 150, a: 255), 8)

      # Decay damage for next chain
      currentDamage *= chainDecay
      lastX = chainX
      lastY = chainY

    # SPECIAL: Chain storm creates branching
    if chainMode == "chain_storm" and rand(100) < 40:
      # 40% chance to create a branch
      let branchAngle = baseAngle + (if rand(2) == 0: 0.6 else: -0.6)
      let branchDir = newVector2f(cos(branchAngle), sin(branchAngle))
      let branchDist = 120.0
      let branchX = enemy.pos.x + branchDir.x * branchDist
      let branchY = enemy.pos.y + branchDir.y * branchDist

      if branchX > 0 and branchX < game.screenWidth.float32 and
         branchY > 0 and branchY < game.screenHeight.float32:
        # VISUAL: Persistent lightning arc for branch
        spawnLightningBolt(game, enemy.pos, newVector2f(branchX, branchY))

        game.bullets.add(newBullet(
          x = branchX, y = branchY,
          direction = branchDir,
          speed = 200.0,
          damage = attack.damage * phase.damageMultiplier * 0.5,
          fromPlayer = false, isBossBullet = true, sourceEnemyId = enemy.id,
      bossBulletShape = bossBulletShapeFor(enemy.bossDefinitionID),
      bulletRadius = attack.bulletRadius
        ))

  # Central explosion - varies by mode
  let (explosionSize, explosionColor) = case chainMode
    of "chain_overload": (40, Color(r: 255, g: 255, b: 255, a: 255))  # White overload
    of "chain_storm": (30, Color(r: 255, g: 255, b: 150, a: 255))     # Bright yellow
    else: (20, Color(r: 255, g: 255, b: 100, a: 255))                 # Yellow

  spawnExplosionPooled(game.particlePool, enemy.pos.x, enemy.pos.y, explosionColor, explosionSize)


proc execBossAttackTeleport(game: var Game, enemy: Enemy, attack: BossAttack, phase: BossPhaseDefinition, bossDef: BossDefinition, toPlayer: Vector2f) =
  # Teleport to new location and shoot - customized via specialData
  # "afterimage_burst" = creates multiple images with burst effect
  # "triple_clone" = teleports to 3 locations simultaneously
  # "dimensional_rift" = creates rift visual effect

  let teleportMode = attack.specialData
  let teleportCount = case teleportMode
    of "triple_clone": 3
    of "time_echo": 2
    of "echo_burst": 4
    of "temporal_collapse": 6
    of "afterimage_burst": 3 + rand(2)  # 3-4 ghost images with rapid bursts
    of "chaos_blink": rand(2) + 1  # 1-2 random teleports with unstable reality tears
    of "reality_shift": rand(2) + 2  # 2-3 reality shifts with dimensional bridges
    of "dimensional_rift": 2  # 2 major dimensional rifts
    of "dimensional_chaos": rand(3) + 3  # 3-5 chaotic dimension portals with vortexes
    of "omega_blink": rand(2) + 4  # 4-5 ultimate teleports combining all effects
    else: 1

  # TELEPORT WARNING SYSTEM - Show player where boss will appear BEFORE bullets spawn
  # Pre-calculate all teleport positions and create warning indicators
  const BOSS_TELEPORT_MIN_DIST = 150.0  # Minimum distance boss can teleport near player
  var teleportWarningPositions: seq[Vector2f] = @[]
  for t in 0..<teleportCount:
    var newX, newY: float32
    var attempts = 0
    while true:
      newX = game.screenWidth.float32 * (0.2 + rand(0.6))
      newY = game.screenHeight.float32 * (0.2 + rand(0.6))
      let dx = newX - game.player.pos.x
      let dy = newY - game.player.pos.y
      let distSq = dx * dx + dy * dy
      inc attempts
      if distSq >= BOSS_TELEPORT_MIN_DIST * BOSS_TELEPORT_MIN_DIST or attempts >= 10:
        break  # Accept position if far enough or after max retries
    teleportWarningPositions.add(newVector2f(newX, newY))

  # Create pre-warning indicators at each teleport location
  let warningDuration = case teleportMode
    of "afterimage_burst": 0.6
    of "triple_clone": 0.7
    of "time_echo": 0.5
    of "echo_burst": 0.5
    of "temporal_collapse": 0.6
    of "chaos_blink": 0.5
    of "reality_shift": 0.7
    of "dimensional_rift": 0.8
    of "dimensional_chaos": 0.7
    of "omega_blink": 1.0
    else: 0.5

  # Create visual warnings for each teleport position
  # Calculate bullet spawn parameters BEFORE creating warnings
  let (bulletSpeed, bulletDamageMultiplier) = case teleportMode
    of "time_echo":
      (160.0, 0.65)  # Slower temporal echoes, reduced damage
    of "echo_burst":
      (200.0, 0.6)  # Many rapid echoes, lower damage
    of "temporal_collapse":
      (180.0, 0.7)  # Moderate speed reality-breaking shots
    of "afterimage_burst":
      (190.0 + rand(40.0), 0.65)  # Variable speed ghost shots
    of "chaos_blink":
      (170.0 + rand(60.0), 0.7)  # Random speed chaos
    of "reality_shift":
      (160.0 + rand(80.0), 0.65)  # Highly variable speed
    of "dimensional_rift":
      (180.0 + rand(50.0), 0.72)  # Dimensional rift shots with variance
    of "dimensional_chaos":
      (150.0 + rand(100.0), 0.75)  # Maximum speed variation
    of "omega_blink":
      (220.0, 0.8)  # Fast ultimate shots
    else:
      (200.0, 0.7)  # Default

  for idx in 0..<teleportWarningPositions.len:
    let warningPos = teleportWarningPositions[idx]
    # Create warning with bullet spawn data stored
    let warning = newAttackWarning(warningPos.x, warningPos.y, awtTeleportWarning,
                                   warningDuration, enemy.id)
    warning.laserPattern = teleportMode   # Store mode for visual rendering
    warning.targetPos = warningPos
    # Store bullet spawn data for delayed creation
    warning.bulletCount = attack.projectileCount
    warning.bulletSpeed = bulletSpeed
    warning.bulletDamage = attack.damage * phase.damageMultiplier * bulletDamageMultiplier
    warning.bulletSpreadAngle = 360.0   # Full circle
    # Mark first position as where boss should teleport
    warning.isBossTeleportTarget = (idx == 0)
    game.attackWarnings.add(warning)


proc execBossAttackDash(game: var Game, enemy: Enemy, attack: BossAttack, phase: BossPhaseDefinition, bossDef: BossDefinition, toPlayer: Vector2f) =
  # BERSERKER DASH SYSTEM with multi-charge mechanics
  # SpecialData modes:
  # - "charge_attack": Basic charge with screen shake
  # - "double_charge": Charges twice in rapid succession
  # - "rage_charge": THREE charges in combo! Maximum aggression!

  let dashMode = attack.specialData
  var dashStart = enemy.pos
  var dashTarget: Vector2f
  var dashDist: float32
  if enemy.pendingDashLocked:
    dashStart = enemy.pendingDashStart
    dashTarget = enemy.pendingDashTarget
    # Clamp the locked target too (it was set in a prior frame, same check)
    let lockedPad = enemy.radius
    dashTarget.x = clamp(dashTarget.x, lockedPad, game.screenWidth.float32 - lockedPad)
    dashTarget.y = clamp(dashTarget.y, lockedPad, game.screenHeight.float32 - lockedPad)
    dashDist = distance(dashStart, dashTarget)
  else:
    dashDist = case dashMode
      of "charge_attack": 350.0'f32
      of "double_charge": 300.0'f32
      of "rage_charge":   280.0'f32
      else:               350.0'f32
    dashTarget = dashStart + toPlayer * dashDist

  # Clamp dash target to screen bounds so the boss can't leave the play area
  let dashPad = enemy.radius
  dashTarget.x = clamp(dashTarget.x, dashPad, game.screenWidth.float32 - dashPad)
  dashTarget.y = clamp(dashTarget.y, dashPad, game.screenHeight.float32 - dashPad)
  # Recompute actual distance after clamping (affects duration + trail spacing)
  dashDist = distance(dashStart, dashTarget)

  let dashDir = if dashDist > 0.01'f32:
    (dashTarget - dashStart).normalize()
  else:
    toPlayer
  var dashSpeed = attack.projectileSpeed

  # Cap dash speed to player speed for fairness
  # Bosses can charge at you, but never faster than you can move away
  if dashSpeed > game.player.speed:
    dashSpeed = game.player.speed

  # Configure dash visuals based on mode. Distance is locked by the warning
  # above so execution cannot retarget after the marker appears.
  let trailColor = case dashMode
    of "charge_attack":
      Color(r: 255, g: 50, b: 0, a: 255)  # Single charge, red trail
    of "double_charge":
      Color(r: 255, g: 100, b: 0, a: 255)  # Double charge, bright red
    of "rage_charge":
      Color(r: 255, g: 0, b: 0, a: 255)  # TRIPLE charge, pure red
    else:
      phase.color  # Default

  let dashTime = dashDist / dashSpeed  # Calculate duration based on speed

  # Set up dash state with charge count
  enemy.isDashing = true
  enemy.pos = dashStart
  enemy.dashVelocity = dashDir * dashSpeed
  enemy.vel = enemy.dashVelocity
  enemy.dashDuration = dashTime
  enemy.dashMaxDuration = dashTime
  enemy.dashTargetPos = dashTarget
  enemy.pendingDashLocked = false

  # Store remaining charges (will re-trigger after current dash finishes)
  # This is handled in boss update logic by checking dashChargesRemaining

  # SCREEN SHAKE based on mode
  addShake(game.dopamine.screenShake, siLarge)

  # Create MORE impressive trail effects for rage charges
  let trailCount = if dashMode == "rage_charge": 8 elif dashMode == "double_charge": 6 else: 4
  for i in 0..<trailCount:
    let trailPos = i.float32 * (dashDist / trailCount.float32)
    game.bullets.add(newBullet(
      x = dashStart.x + dashDir.x * trailPos,
      y = dashStart.y + dashDir.y * trailPos,
      direction = dashDir,
      speed = dashSpeed * 0.4,  # Trail effect
      damage = attack.damage * phase.damageMultiplier * 0.6,  # Trail damage
      fromPlayer = false, isBossBullet = true, sourceEnemyId = enemy.id,
      bossBulletShape = bossBulletShapeFor(enemy.bossDefinitionID),
      bulletRadius = attack.bulletRadius
    ))

  # Rage charges get FIRE RING on activation
  if dashMode == "rage_charge":
    for i in 0..<16:
      let angle = i.float32 * (PI * 2.0 / 16.0)
      let ringX = enemy.pos.x + cos(angle) * 60.0
      let ringY = enemy.pos.y + sin(angle) * 60.0
      spawnExplosionPooled(game.particlePool, ringX, ringY,
                    Color(r: 255, g: 50, b: 0, a: 255), 5)

  # Initial visual explosion with colors
  let (explosionSize, explosionColor) = case dashMode
    of "rage_charge": (40, Color(r: 255, g: 0, b: 0, a: 255))
    of "double_charge": (30, Color(r: 255, g: 100, b: 0, a: 255))
    else: (20, trailColor)

  spawnExplosionPooled(game.particlePool, enemy.pos.x, enemy.pos.y, explosionColor, explosionSize)


proc execBossAttackSnipe(game: var Game, enemy: Enemy, attack: BossAttack, phase: BossPhaseDefinition, bossDef: BossDefinition, toPlayer: Vector2f) =
  # PRECISION SNIPE SYSTEM - Boss 7 Orbital Commander
  # SpecialData modes:
  # - "orbital_snipe": Aimed shot from satellite position (shows laser pointer warning)
  # - "precision_strike": Double snipe with warning indicators
  # - "satellite_barrage": Multiple rapid snipes from different angles
  # - Default: Standard snipe

  let snipeMode = attack.specialData

  # Configure snipe behavior
  let (showWarning, warningTime, bulletColor) = case snipeMode
    of "orbital_snipe":
      (true, 0.8, Color(r: 150, g: 100, b: 255, a: 255))  # Purple space snipe with warning
    of "precision_strike":
      (true, 0.6, Color(r: 200, g: 150, b: 255, a: 255))  # Bright purple, shorter warning
    of "satellite_barrage":
      (true, 0.4, Color(r: 180, g: 120, b: 255, a: 255))  # Quick warnings for rapid fire
    else:
      (false, 0.0, phase.color)  # No warning for default

  # Show warning indicators at the TARGET position (near player), not at the enemy
  if showWarning:
    for i in 0..<attack.projectileCount:
      let spread = if attack.projectileCount > 1:
        (i.float32 - attack.projectileCount.float32 / 2.0) * attack.spreadAngle.degToRad() / attack.projectileCount.float32
      else: 0.0
      let aimAngle = arctan2(toPlayer.y, toPlayer.x) + spread
      # Project from enemy toward player to approximate impact point (capped at screen edge)
      let maxDist = min(distance(enemy.pos, game.player.pos) + 80.0, 600.0)
      let warnX = enemy.pos.x + cos(aimAngle) * maxDist
      let warnY = enemy.pos.y + sin(aimAngle) * maxDist
      game.attackWarnings.add(newAttackWarning(warnX, warnY, awtLaserPointer, warningTime))

  # Fire the actual snipe shots
  for i in 0..<attack.projectileCount:
    let spread = if attack.projectileCount > 1:
      (i.float32 - attack.projectileCount.float32 / 2.0) * attack.spreadAngle.degToRad() / attack.projectileCount.float32
    else: 0.0
    let angle = arctan2(toPlayer.y, toPlayer.x) + spread
    let dir = newVector2f(cos(angle), sin(angle))

    # Enhanced bullet for special snipes
    spawnBossBullet(game, enemy, attack, phase, dir)

    # Visual muzzle flash per shot
    spawnExplosionPooled(game.particlePool, enemy.pos.x, enemy.pos.y, bulletColor, 8)

  # Special visual effects for satellite snipes
  if snipeMode == "satellite_barrage":
    # Create star pattern around boss
    for i in 0..<8:
      let angle = i.float32 * PI * 2.0 / 8.0
      let starX = enemy.pos.x + cos(angle) * 50.0
      let starY = enemy.pos.y + sin(angle) * 50.0
      spawnExplosionPooled(game.particlePool, starX, starY,
                    Color(r: 200, g: 150, b: 255, a: 255), 4)


proc execBossAttackMinionVolley(game: var Game, enemy: Enemy, attack: BossAttack, phase: BossPhaseDefinition, bossDef: BossDefinition, toPlayer: Vector2f) =
  # LEGION VOLLEY (Summoner King) - every living summoned add fires a single shot
  # at the player in unison. This turns ignored adds into active pressure while the
  # boss is sealed. Single shot per add
  # keeps the worst case bounded by MAX_BOSS_SPAWNED_ENEMIES. If the wave is already
  # cleared, the boss fires a fan itself so the attack still does something.
  var firedFromAdds = 0
  for other in game.enemies:
    if other.spawnedByBoss and other.hp > 0:
      let dir = (game.player.pos - other.pos).normalize()
      game.bullets.add(newBullet(
        x = other.pos.x, y = other.pos.y, direction = dir,
        speed = attack.projectileSpeed, damage = attack.damage * phase.damageMultiplier,
        fromPlayer = false, isBossBullet = true, sourceEnemyId = enemy.id,
        bossBulletShape = bossBulletShapeFor(enemy.bossDefinitionID),
        bulletRadius = attack.bulletRadius
      ))
      spawnExplosionPooled(game.particlePool, other.pos.x, other.pos.y,
                           Color(r: 120, g: 230, b: 140, a: 255), 6)
      firedFromAdds += 1

  if firedFromAdds == 0:
    # Fallback: fan from the boss aimed at the player
    let baseAngle = arctan2(toPlayer.y, toPlayer.x)
    let count = max(3, attack.projectileCount)
    for i in 0..<count:
      let offset = (i.float32 - count.float32 / 2.0) * attack.spreadAngle.degToRad() / count.float32
      let dir = newVector2f(cos(baseAngle + offset), sin(baseAngle + offset))
      spawnBossBullet(game, enemy, attack, phase, dir)
  else:
    # Green command pulse from the boss telegraphs that the legion just fired.
    spawnExplosionPooled(game.particlePool, enemy.pos.x, enemy.pos.y,
                         Color(r: 80, g: 220, b: 120, a: 220), 12)


proc executeCustomBossAttack*(game: var Game, enemy: Enemy, attack: BossAttack, phase: BossPhaseDefinition, bossDef: BossDefinition) =
  ## Executes a single boss attack based on its pattern type
  # Dungeon mode compresses boss attack damage toward the floor's threat
  # (boss definitions assume the player power of their wave-mode slot).
  # Shadowing the attack keeps every pattern below reading tuned damage.
  var attack = attack
  if enemy.damageTuning > 0.0'f32 and enemy.damageTuning < 1.0'f32:
    attack.damage *= enemy.damageTuning
  let toPlayer = (game.player.pos - enemy.pos).normalize()

  # Special telegraphed electricity attacks build their own warnings and defer
  # the strike to the warning-update loop; no bullets are spawned here.
  case attack.specialData
  of "thunderstrike":
    spawnThunderstrike(game, enemy, attack, phase)
    return
  of "arc_lattice":
    spawnArcLattice(game, enemy, attack, phase)
    return
  of "ricochet_laser":
    spawnRicochetLaser(game, enemy, attack, phase)
    return
  else: discard

  case attack.attackType
  of bapSpiral:
    execBossAttackSpiral(game, enemy, attack, phase, bossDef, toPlayer)
  of bapBurst:
    execBossAttackBurst(game, enemy, attack, phase, bossDef, toPlayer)
  of bapWave:
    execBossAttackWave(game, enemy, attack, phase, bossDef, toPlayer)
  of bapTargeted:
    execBossAttackTargeted(game, enemy, attack, phase, bossDef, toPlayer)
  of bapCircle:
    execBossAttackCircle(game, enemy, attack, phase, bossDef, toPlayer)
  of bapLaser:
    execBossAttackLaser(game, enemy, attack, phase, bossDef, toPlayer)
  of bapBarrage:
    execBossAttackBarrage(game, enemy, attack, phase, bossDef, toPlayer)
  of bapPulse:
    execBossAttackPulse(game, enemy, attack, phase, bossDef, toPlayer)
  of bapSummon:
    execBossAttackSummon(game, enemy, attack, phase, bossDef, toPlayer)
  of bapMeteor:
    execBossAttackMeteor(game, enemy, attack, phase, bossDef, toPlayer)
  of bapOrbit:
    execBossAttackOrbit(game, enemy, attack, phase, bossDef, toPlayer)
  of bapChain:
    execBossAttackChain(game, enemy, attack, phase, bossDef, toPlayer)
  of bapTeleport:
    execBossAttackTeleport(game, enemy, attack, phase, bossDef, toPlayer)
  of bapDash:
    execBossAttackDash(game, enemy, attack, phase, bossDef, toPlayer)
  of bapSnipe:
    execBossAttackSnipe(game, enemy, attack, phase, bossDef, toPlayer)
  of bapMinionVolley:
    execBossAttackMinionVolley(game, enemy, attack, phase, bossDef, toPlayer)
