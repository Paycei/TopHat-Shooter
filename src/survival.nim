# SURVIVAL MODE - Time Survival ("LASTSTAND.exe")
#
# A 20:00 run in four phases (Boot, Runtime, Overload, Kernel Panic), each
# closed by a boss on the survival clock, then optional Overtime (the schedule
# itself is in types.nim, next to densityRebate). game.nim calls the
# orchestrator procs below; this module holds every survival system:
#   * data tables and text keys          * the horde spawner
#   * Data Caches (the reward drops)      * System Events and their scheduler
#   * the per-frame orchestrator          * the cache reveal overlay and HUD
# Like the game/ modules, it must never import game.

import raylib, random, math, strutils
import particle_types, types, localization, utils, sound, d_systems, d_visuals, roguelite,
       enemy, enemy_config, enemy_helpers, particle_pool, consumable, coin, player, powerup,
       powerup_data, gamepad_input, game/bullets, game/death, ui/os_background, ui/icon_drawing,
       ui/hud_dock, ui/ui_helpers

# ============================================================================
# Data: per-phase tuning, events, caches, text
# ============================================================================

# --- Per-phase tuning ---------------------------------------------------------
# Arrays indexed by SurvivalPhase so adding a phase fails to compile until
# every table has a row for it.

const
  SurvivalPhaseAccent*: array[SurvivalPhase, Color] = [
    Color(r: 0,   g: 200, b: 255, a: 255),  # Boot: desktop cyan
    Color(r: 90,  g: 255, b: 170, a: 255),  # Runtime: green
    Color(r: 255, g: 175, b: 60,  a: 255),  # Overload: amber
    Color(r: 255, g: 70,  b: 70,  a: 255),  # Kernel Panic: red
    Color(r: 255, g: 60,  b: 255, a: 255)]  # Overtime: magenta

  # Alive-enemy target at the start and end of each phase. Overtime starts at
  # its first value and climbs per minute (see survivalDensityTarget).
  SurvivalTargetStart*: array[SurvivalPhase, float32] = [14.0'f32, 34, 55, 75, 95]
  SurvivalTargetEnd*: array[SurvivalPhase, float32] = [34.0'f32, 55, 75, 95, 135]
  # Spawns per second the density spawner may refill.
  SurvivalRefillStart*: array[SurvivalPhase, float32] = [3.0'f32, 4, 6, 7, 9]
  SurvivalRefillEnd*: array[SurvivalPhase, float32] = [4.0'f32, 6, 7, 9, 12]
  # Chance a refill arrives as a pack of 3-6 instead of a single enemy.
  SurvivalPackChance*: array[SurvivalPhase, float32] = [0.20'f32, 0.30, 0.35, 0.40, 0.40]
  # Seconds between set-piece formations (base, +/- jitter).
  SurvivalFormationGap*: array[SurvivalPhase, float32] = [28.0'f32, 24, 20, 17, 15]
  SurvivalFormationJitter*: array[SurvivalPhase, float32] = [4.0'f32, 4, 3, 3, 3]
  # Seconds between the end of one System Event and the next (base, jitter).
  SurvivalEventGap*: array[SurvivalPhase, float32] = [35.0'f32, 30, 27, 24, 20]
  SurvivalEventJitter*: array[SurvivalPhase, float32] = [6.0'f32, 5, 5, 4, 4]

type
  SurvivalFormation* = enum
    sfStream,  # a conga line released from one off-screen point
    sfSwarm,   # a cluster pouring in from a corner
    sfRing     # a ring around the player that closes in

const
  SurvivalFormationWeights*: array[SurvivalPhase, array[SurvivalFormation, int]] = [
    [60, 40, 0],    # Boot (rings join after 2:00, see pickFormation)
    [40, 30, 30],   # Runtime
    [35, 30, 35],   # Overload
    [30, 30, 40],   # Kernel Panic
    [30, 25, 45]]   # Overtime

  # Random-event weights. Rogue Process is never random: each phase schedules
  # one at its halfway mark.
  SurvivalEventWeights*: array[SurvivalPhase, array[SurvivalEventKind, int]] = [
    [0, 30, 15, 30, 0,  0, 25],   # Boot: no meteors yet
    [0, 25, 25, 20, 15, 0, 15],   # Runtime
    [0, 22, 25, 18, 20, 0, 15],   # Overload
    [0, 20, 25, 15, 25, 0, 15],   # Kernel Panic
    [0, 20, 25, 15, 25, 0, 15]]   # Overtime

proc survivalEventDuration*(kind: SurvivalEventKind): float32 =
  ## Warmup + live time + resolution beat, used to keep events from running
  ## into a boss.
  case kind
  of sekNone: 0.0'f32
  of sekMemoryLeak: 2.0'f32 + 12.0'f32 + 4.0'f32
  of sekFirewallBreach: 1.0'f32 + 25.0'f32
  of sekUploadZone: 30.0'f32
  of sekCorruptedSector: 1.5'f32 + 12.0'f32
  of sekRogueProcess: 1.2'f32 + 45.0'f32
  of sekOverclock: 15.0'f32

proc survivalEventColor*(kind: SurvivalEventKind): Color =
  case kind
  of sekNone: Color(r: 0, g: 200, b: 255, a: 255)
  of sekMemoryLeak: Color(r: 120, g: 255, b: 120, a: 255)
  of sekFirewallBreach: Color(r: 255, g: 90, b: 70, a: 255)
  of sekUploadZone: Color(r: 80, g: 200, b: 255, a: 255)
  of sekCorruptedSector: Color(r: 255, g: 150, b: 40, a: 255)
  of sekRogueProcess: Color(r: 220, g: 90, b: 255, a: 255)
  of sekOverclock: Color(r: 255, g: 215, b: 60, a: 255)

# --- Data Caches ---------------------------------------------------------------

proc survivalCacheLevels*(tier: SurvivalCacheTier): int =
  ## Free power-up levels a cache grants.
  case tier
  of sctMinor: 1
  of sctStandard: 2
  of sctRare: 2     # plus a 40% chance of a legendary (see openSurvivalCache)
  of sctKernel: 3

proc survivalCacheWalls*(tier: SurvivalCacheTier): int =
  ## Survival has no shop any more, and the shop was its only wall source.
  case tier
  of sctMinor: 1
  of sctStandard: 2
  of sctRare: 3
  of sctKernel: 5

proc survivalCacheFallbackShards*(tier: SurvivalCacheTier): int =
  ## Paid per level that finds nothing left to upgrade.
  case tier
  of sctMinor: 4
  of sctStandard: 5
  of sctRare: 6
  of sctKernel: 8

proc survivalCacheAccent*(tier: SurvivalCacheTier): Color =
  case tier
  of sctMinor: Color(r: 0, g: 210, b: 255, a: 255)
  of sctStandard: Color(r: 90, g: 255, b: 150, a: 255)
  of sctRare: Color(r: 190, g: 110, b: 255, a: 255)
  of sctKernel: Color(r: 255, g: 210, b: 60, a: 255)

# --- Text ------------------------------------------------------------------------
# Exhaustive, so a new phase, event or tier fails `nim check` until it has text.

proc survivalPhaseNameKey*(phase: SurvivalPhase): TranslationKey =
  case phase
  of spBoot: tkSurvivalPhaseBoot
  of spRuntime: tkSurvivalPhaseRuntime
  of spOverload: tkSurvivalPhaseOverload
  of spKernelPanic: tkSurvivalPhaseKernelPanic
  of spOvertime: tkSurvivalPhaseOvertime

proc survivalPhaseDescKey*(phase: SurvivalPhase): TranslationKey =
  case phase
  of spBoot: tkSurvivalPhaseBootDesc
  of spRuntime: tkSurvivalPhaseRuntimeDesc
  of spOverload: tkSurvivalPhaseOverloadDesc
  of spKernelPanic: tkSurvivalPhaseKernelPanicDesc
  of spOvertime: tkSurvivalPhaseOvertimeDesc

proc survivalEventNameKey*(kind: SurvivalEventKind): TranslationKey =
  case kind
  of sekNone: tkSurvivalTrackerIncoming
  of sekMemoryLeak: tkSurvivalEventMemoryLeak
  of sekFirewallBreach: tkSurvivalEventFirewallBreach
  of sekUploadZone: tkSurvivalEventUploadZone
  of sekCorruptedSector: tkSurvivalEventCorruptedSector
  of sekRogueProcess: tkSurvivalEventRogueProcess
  of sekOverclock: tkSurvivalEventOverclock

proc survivalEventHintKey*(kind: SurvivalEventKind): TranslationKey =
  case kind
  of sekNone: tkSurvivalTrackerIncoming
  of sekMemoryLeak: tkSurvivalEventMemoryLeakHint
  of sekFirewallBreach: tkSurvivalEventFirewallBreachHint
  of sekUploadZone: tkSurvivalEventUploadZoneHint
  of sekCorruptedSector: tkSurvivalEventCorruptedSectorHint
  of sekRogueProcess: tkSurvivalEventRogueProcessHint
  of sekOverclock: tkSurvivalEventOverclockHint

proc survivalCacheNameKey*(tier: SurvivalCacheTier): TranslationKey =
  case tier
  of sctMinor: tkSurvivalCacheMinor
  of sctStandard: tkSurvivalCacheStandard
  of sctRare: tkSurvivalCacheRare
  of sctKernel: tkSurvivalCacheKernel

proc formatSurvivalClock*(seconds: float32): string =
  ## "m:ss" (minutes unpadded), for countdowns and the phase row.
  let total = max(0, int(ceil(max(0.0'f32, seconds))))
  let m = total div 60
  let s = total mod 60
  $m & ":" & (if s < 10: "0" else: "") & $s

proc survivalPhaseReachedLabel*(game: Game): string =
  ## "KERNEL PANIC", or "OVERTIME +3:12" once the run is past 20:00.
  let ph = survivalPhase(game)
  result = t(survivalPhaseNameKey(ph))
  if ph == spOvertime:
    result &= " +" & formatSurvivalClock(game.survivalTime - survivalBossTime(SurvivalFinalBoss))

# ============================================================================
# Horde spawner
# ============================================================================
# Two layers keep the screen full:
#   * the density spawner tops the living horde up toward a target that rises
#     through each phase (single edge spawns, sometimes a pack of 3-6);
#   * set-piece formations arrive on their own timer: a stream released from
#     one point, a swarm pouring in from a corner, or a ring that closes in
#     around the player.
# Every survival enemy goes through newSurvivalEnemy, which applies the
# density rebate (survivalDensityRebate in types.nim) so a crowd costs and
# pays about what the old trickle did, just split across more bodies.

const
  SurvivalMaxAlive* = 150       ## Hard cap on living non-boss enemies (plus queued)
  SurvivalMaxPending = 48       ## Cap on queued spawns
  SurvivalEdgeMinGap = 160.0'f32  ## Edge spawns keep this far from the player
  SurvivalRingRadius = 360.0'f32
  SurvivalRingMinGap = 200.0'f32  ## Ring slots dragged closer than this are dropped
  SurvivalMarkerTime* = 0.9'f32   ## Telegraph before an in-arena spawn appears
  SurvivalBossRosterEpsilon = 0.5'f32
    ## During a boss fight difficulty is frozen at the boss's spawn value (an
    ## integer); introduction thresholds are also integers, so picking types at
    ## `difficulty - 0.5` guarantees no enemy type debuts mid-boss.

proc survivalAliveCount*(game: Game): int =
  ## Living non-boss enemies plus queued spawns: what the density target and
  ## the hard cap measure.
  result = game.survival.pending.len
  for e in game.enemies:
    if not e.isBoss:
      inc result

proc rosterDifficulty(game: Game): float32 =
  if game.bossWaveManager.active: game.difficulty - SurvivalBossRosterEpsilon
  else: game.difficulty

const RangedTypes = {etCube, etHexagon, etDiamond, etOctagon, etPentagon,
                     etTrickster, etPhantom, etSniper, etMage}

proc pickRosterType(game: Game): EnemyType =
  ## The live roster, leaning melee: a horde is a crowd of chasers with
  ## shooters mixed in, not a firing squad. Ranged picks are re-rolled once
  ## 40% of the time (the new pick stands, whatever it is).
  result = pickSpawnType(rosterDifficulty(game))
  if result in RangedTypes and rand(99) < 40:
    result = pickSpawnType(rosterDifficulty(game))

proc pickFodderType*(game: Game): EnemyType =
  ## Formations are made of melee chasers so they keep their shape as they
  ## close in: circles, with triangles (dashers) mixed in once they exist.
  let d = rosterDifficulty(game)
  if d >= allEnemyDefs[etTriangle].introductionDifficulty and rand(99) < 30:
    etTriangle
  else:
    etCircle

proc inArena(game: Game, pos: Vector2f): bool =
  pos.x >= 0 and pos.y >= 0 and
    pos.x <= game.screenWidth.float32 and pos.y <= game.screenHeight.float32

proc newSurvivalEnemy*(game: Game, pos: Vector2f, enemyType: EnemyType,
                       tag: SurvivalTag = stgNone, hpMult: float32 = 1.0'f32,
                       speedMult: float32 = 1.0'f32, allowElite: bool = true): Enemy =
  ## Build (but don't add) a survival enemy at the live difficulty, normalised
  ## for horde density.
  let d = game.difficulty
  result = newEnemy(pos.x, pos.y, d, enemyType, game)
  let rebate = densityRebate(game)
  if enemyType == etStar:
    # Stars are hit-count based (placeholder HP): trim the hit count instead.
    result.requiredHits = max(3, int(result.requiredHits.float32 * (0.4'f32 + 0.6'f32 * rebate)))
  else:
    result.maxHp = max(0.01'f32, result.maxHp * rebate * hpMult)
    result.hp = result.maxHp
  # Damage is only half-rebated: a crowd is meant to be more dangerous than the
  # handful it replaced (same rule as wave mode).
  let dmgScale = 0.65'f32 + 0.35'f32 * rebate
  result.contactDamage *= dmgScale
  result.rangedDamage *= dmgScale
  # Wave mode's soft girth: getScaledEnemyStats grows the radius linearly with
  # difficulty, which at 20:00 makes every enemy a 40 px blob that clogs the
  # horde. Re-shape it into a decelerating curve.
  let linearGirth = d * 1.5'f32
  let softGirth = pow(max(d, 0.0'f32), 0.6'f32) * 1.5'f32
  let girthCut = max(0.0'f32, linearGirth - softGirth)
  result.radius = max(result.radius - girthCut, result.radius * 0.5'f32)
  result.collisionRadius = result.radius * 0.4'f32
  result.speed *= speedMult
  result.survivalTag = tag
  if inArena(game, pos):
    result.hasEnteredScreen = true
  if allowElite:
    # Survival's wave equivalent is difficulty * 2; the chance is rebated so
    # elites per minute stay where the old spawner had them.
    makeElite(result, int(d * 2.0'f32), chanceScale = rebate)

proc addSurvivalEnemy*(game: Game, pos: Vector2f, enemyType: EnemyType,
                       tag: SurvivalTag = stgNone, hpMult: float32 = 1.0'f32,
                       speedMult: float32 = 1.0'f32, allowElite: bool = true): Enemy {.discardable.} =
  result = newSurvivalEnemy(game, pos, enemyType, tag, hpMult, speedMult, allowElite)
  game.enemies.add(result)

proc queueSurvivalSpawn*(game: Game, pos: Vector2f, enemyType: EnemyType, delay: float32,
                         tag: SurvivalTag = stgNone, hpMult: float32 = 1.0'f32,
                         speedMult: float32 = 1.0'f32, allowElite: bool = true,
                         telegraph: bool = false): bool {.discardable.} =
  ## Queue a spawn. False (nothing queued) when the queue or the horde is full.
  if game.survival.pending.len >= SurvivalMaxPending or
     survivalAliveCount(game) >= SurvivalMaxAlive:
    return false
  game.survival.pending.add(SurvivalPendingSpawn(
    pos: pos, enemyType: enemyType, delay: delay, tag: tag,
    hpMult: hpMult, speedMult: speedMult, allowElite: allowElite,
    telegraph: telegraph))
  true

proc updateSurvivalPending*(game: Game, dt: float32) =
  ## Materialize queued spawns whose delay has run out.
  var i = 0
  while i < game.survival.pending.len:
    game.survival.pending[i].delay -= dt
    if game.survival.pending[i].delay <= 0:
      let p = game.survival.pending[i]
      game.survival.pending.delete(i)
      addSurvivalEnemy(game, p.pos, p.enemyType, p.tag, p.hpMult, p.speedMult, p.allowElite)
      if p.telegraph:
        spawnExplosionPooled(game.particlePool, p.pos.x, p.pos.y,
                             Color(r: 255, g: 90, b: 70, a: 255), 6)
      continue
    inc i

proc edgePointAwayFromPlayer(game: Game, margin: float32 = 30): Vector2f =
  ## Random off-screen edge point, re-rolled a few times to keep new spawns
  ## from landing right on top of a player hugging that edge.
  var best = newVector2f(0, 0)
  var bestDist = -1.0'f32
  for _ in 0..3:
    let (x, y) = randomEdgeSpawnPos(game.screenWidth, game.screenHeight, margin)
    let p = newVector2f(x, y)
    let dist = distance(p, game.player.pos)
    if dist >= SurvivalEdgeMinGap:
      return p
    if dist > bestDist:
      best = p
      bestDist = dist
  best

proc edgeScatter(game: Game, anchor: Vector2f, spread: float32): Vector2f =
  ## A point near `anchor` pushed further off-screen, so a pack arrives as a
  ## clump rather than a line.
  let w = game.screenWidth.float32
  let h = game.screenHeight.float32
  var p = anchor + newVector2f(rand(-spread..spread), rand(-spread..spread))
  if anchor.x < 0: p.x = min(p.x, -10.0'f32)
  elif anchor.x > w: p.x = max(p.x, w + 10.0'f32)
  if anchor.y < 0: p.y = min(p.y, -10.0'f32)
  elif anchor.y > h: p.y = max(p.y, h + 10.0'f32)
  p

# --- Density spawner ------------------------------------------------------------

proc eventDensityMult(game: Game): tuple[target, refill: float32] =
  case game.survival.event.kind
  of sekOverclock: (1.35'f32, 1.5'f32)
  of sekUploadZone: (1.15'f32, 1.0'f32)
  else: (1.0'f32, 1.0'f32)

proc survivalDensityTarget*(game: Game): float32 =
  ## How many non-boss enemies the spawner keeps alive right now.
  let ph = survivalPhase(game)
  result =
    if ph == spOvertime:
      min(SurvivalTargetEnd[spOvertime],
          SurvivalTargetStart[spOvertime] + 5.0'f32 * survivalOvertimeMinutes(game))
    else:
      let t = survivalPhaseProgress(game)
      SurvivalTargetStart[ph] + (SurvivalTargetEnd[ph] - SurvivalTargetStart[ph]) * t
  if game.bossWaveManager.active:
    result *= 0.35'f32   # the fight is about the boss, not the crowd
  result *= eventDensityMult(game).target
  # Harder profiles field a bigger crowd too, at half the pace boost.
  result *= 1.0'f32 + (difficultySpawnPaceMult() - 1.0'f32) * 0.5'f32
  # Ease into the run: the first seconds build up instead of arriving full.
  result = min(result, 6.0'f32 + 0.8'f32 * game.survivalTime)

proc survivalRefillRate*(game: Game): float32 =
  ## Spawns per second the density spawner may add.
  let ph = survivalPhase(game)
  result =
    if ph == spOvertime:
      min(SurvivalRefillEnd[spOvertime],
          SurvivalRefillStart[spOvertime] + 0.5'f32 * survivalOvertimeMinutes(game))
    else:
      let t = survivalPhaseProgress(game)
      SurvivalRefillStart[ph] + (SurvivalRefillEnd[ph] - SurvivalRefillStart[ph]) * t
  if game.bossWaveManager.active:
    result *= 0.5'f32
  result *= eventDensityMult(game).refill
  result *= difficultySpawnPaceMult()

proc spawnPack(game: Game, count: int) =
  let anchor = edgePointAwayFromPlayer(game, 40)
  let packType = pickRosterType(game)
  for i in 0..<count:
    # Mostly one type so the pack reads as a unit, with the odd stray.
    let et = if i == 0 or rand(99) < 75: packType else: pickRosterType(game)
    addSurvivalEnemy(game, edgeScatter(game, anchor, 36), et)

proc updateSurvivalDensity*(game: Game, dt: float32) =
  ## Top the horde up toward the density target.
  let target = survivalDensityTarget(game)
  game.survival.debugTarget = target
  # Hold spawns while a boss makes its entrance.
  if game.bossSpawnTimer > 0 or game.pendingBoss != nil:
    return
  game.survival.spawnBudget = min(8.0'f32,
    game.survival.spawnBudget + survivalRefillRate(game) * dt)
  var alive = survivalAliveCount(game)
  let packChance = SurvivalPackChance[survivalPhase(game)]
  while alive.float32 < target and game.survival.spawnBudget >= 1.0'f32 and
        alive < SurvivalMaxAlive:
    let deficit = int(target) - alive
    if deficit >= 4 and game.survival.spawnBudget >= 4.0'f32 and rand(1.0'f32) < packChance:
      let n = min(min(3 + rand(3), deficit), int(game.survival.spawnBudget))
      spawnPack(game, n)
      alive += n
      game.survival.spawnBudget -= n.float32
    else:
      addSurvivalEnemy(game, edgePointAwayFromPlayer(game), pickRosterType(game))
      inc alive
      game.survival.spawnBudget -= 1.0'f32

# --- Set-piece formations ----------------------------------------------------------

proc clampNearArena(game: Game, pos: Vector2f, pad: float32): Vector2f =
  ## Clamp to the arena grown by `pad` (negative pad = inset).
  newVector2f(clamp(pos.x, -pad, game.screenWidth.float32 + pad),
              clamp(pos.y, -pad, game.screenHeight.float32 + pad))

proc slotBlocked(game: Game, pos: Vector2f, radius: float32): bool =
  for wall in game.walls:
    if wall.hp > 0 and wallOverlapsCircle(wall, pos, radius):
      return true

proc queueRing*(game: Game, count: int, radius: float32, delay: float32,
                tag: SurvivalTag = stgNone, allowElite: bool = true): int =
  ## A ring of chasers around the player. Slots squeezed against the arena
  ## edge clamp just outside it (they walk in); slots the clamp drags too close
  ## to the player, or into a wall, are dropped, so that side of the ring is
  ## simply open. In-arena slots are telegraphed. Returns the slots queued.
  if count <= 0:
    return 0
  let spin = rand(PI * 2.0)
  for i in 0..<count:
    let a = spin + i.float32 * PI * 2.0 / count.float32
    let raw = game.player.pos + newVector2f(cos(a), sin(a)) * radius
    let pos = clampNearArena(game, raw, 24.0'f32)
    if distance(pos, game.player.pos) < SurvivalRingMinGap or slotBlocked(game, pos, 14.0'f32):
      continue
    let inside = inArena(game, pos)
    if queueSurvivalSpawn(game, pos, pickFodderType(game), delay, tag,
                          allowElite = allowElite, telegraph = inside):
      inc result

proc spawnStream(game: Game, count: int) =
  ## A conga line: everyone leaves the same off-screen point 0.12 s apart and
  ## chases the player, so the line stretches out behind the leader.
  let origin = edgePointAwayFromPlayer(game, 40)
  let et = pickFodderType(game)
  for i in 0..<count:
    discard queueSurvivalSpawn(game, origin, et, 0.12'f32 * i.float32)

proc spawnSwarm(game: Game, count: int) =
  ## A cluster pouring in from the corner furthest from the player.
  let w = game.screenWidth.float32
  let h = game.screenHeight.float32
  let cx = if game.player.pos.x < w * 0.5'f32: w + 40.0'f32 else: -40.0'f32
  let cy = if game.player.pos.y < h * 0.5'f32: h + 40.0'f32 else: -40.0'f32
  let corner = newVector2f(cx, cy)
  for _ in 0..<count:
    discard queueSurvivalSpawn(game, edgeScatter(game, corner, 70), pickFodderType(game),
                               rand(0.4'f32))

proc pickFormation(game: Game): SurvivalFormation =
  let ph = survivalPhase(game)
  var weights = SurvivalFormationWeights[ph]
  if ph == spBoot and game.survivalTime >= 120.0'f32:
    weights[sfRing] = 15
  var total = 0
  for f in SurvivalFormation: total += weights[f]
  var roll = rand(max(0, total - 1))
  for f in SurvivalFormation:
    if roll < weights[f]: return f
    roll -= weights[f]
  sfStream

proc updateSurvivalFormations*(game: Game) =
  ## Fire the next set piece once its time comes. Runs on the survival clock,
  ## so it pauses with it during boss fights and drafts.
  if game.survivalTime < game.survival.formationClock:
    return
  let ph = survivalPhase(game)
  let ev = game.survival.event.kind
  # A formation on top of a breach ring or a leak would bury the event.
  if ev notin {sekNone, sekOverclock, sekUploadZone}:
    game.survival.formationClock = game.survivalTime + 3.0'f32
    return
  let p = ord(ph)
  case pickFormation(game)
  of sfStream: spawnStream(game, 8 + 2 * p)
  of sfSwarm: spawnSwarm(game, 8 + 2 * p)
  of sfRing: discard queueRing(game, 12 + 4 * p, SurvivalRingRadius, SurvivalMarkerTime)
  game.survival.formationClock = game.survivalTime + SurvivalFormationGap[ph] +
    rand(-SurvivalFormationJitter[ph]..SurvivalFormationJitter[ph])

proc reclaimSurvivalFodder*(game: Game, keep: int) =
  ## A boss is arriving: the OS reclaims most of the horde so the fight starts
  ## on a readable board. Keeps the `keep` plain enemies nearest the player (and
  ## every elite); the rest vanish with a small puff and drop nothing.
  game.survival.pending.setLen(0)
  var candidates: seq[tuple[dist: float32, id: int]]
  for e in game.enemies:
    if not e.isBoss and not e.isElite and e.survivalTag == stgNone:
      candidates.add((distance(e.pos, game.player.pos), e.id))
  if candidates.len <= keep:
    return
  # Partial selection: find the keep-th smallest distance as the cut-off.
  var dists: seq[float32]
  for c in candidates: dists.add(c.dist)
  for i in 0..<keep:
    var m = i
    for j in (i + 1)..<dists.len:
      if dists[j] < dists[m]: m = j
    swap(dists[i], dists[m])
  let cutoff = if keep > 0: dists[keep - 1] else: -1.0'f32
  var kept: seq[Enemy]
  var keptPlain = 0
  for e in game.enemies:
    if e.isBoss or e.isElite or e.survivalTag != stgNone:
      kept.add(e)
    elif keptPlain < keep and distance(e.pos, game.player.pos) <= cutoff:
      kept.add(e)
      inc keptPlain
    else:
      spawnExplosionPooled(game.particlePool, e.pos.x, e.pos.y, e.color, 3)
  game.enemies = kept

proc drawSurvivalSpawnMarkers*(game: Game) =
  ## Pulsing markers where telegraphed spawns are about to appear.
  let now = getTime().float32
  for p in game.survival.pending:
    if not p.telegraph:
      continue
    let prog = clamp(1.0'f32 - p.delay / SurvivalMarkerTime, 0.0'f32, 1.0'f32)
    let pulse = sin(now * 14.0'f32) * 0.5'f32 + 0.5'f32
    let r = 14.0'f32 - prog * 6.0'f32
    let a = uint8(clamp(90.0'f32 + prog * 140.0'f32 + pulse * 25.0'f32, 0.0'f32, 255.0'f32))
    drawCircleLines(p.pos.x.int32, p.pos.y.int32, r, Color(r: 255, g: 90, b: 70, a: a))
    drawLine(Vector2(x: p.pos.x - r * 0.6'f32, y: p.pos.y),
             Vector2(x: p.pos.x + r * 0.6'f32, y: p.pos.y), 1.5'f32,
             Color(r: 255, g: 120, b: 90, a: a))
    drawLine(Vector2(x: p.pos.x, y: p.pos.y - r * 0.6'f32),
             Vector2(x: p.pos.x, y: p.pos.y + r * 0.6'f32), 1.5'f32,
             Color(r: 255, g: 120, b: 90, a: a))

# ============================================================================
# Data Caches
# ============================================================================
# Time Survival Data Caches: the mode's reward drops, in place of the
# between-boss stat shop wave mode uses.
#
# Events, Rogue Processes, the odd elite and every boss drop a cache. Walking
# over one opens it: it installs 1-3 free power-up levels (upgrades of what the
# player already runs, falling back to new ones), hands out walls, and pops
# the reveal overlay (see below), which pauses the sim while
# it shows what was installed. Rewards are applied the moment the cache opens,
# so quitting mid-reveal loses nothing.

const
  CacheOpenRadius = 22.0'f32      # added to the player's radius
  CacheMagnetDelay = 0.8'f32      # a fresh drop stays put this long
  CacheMagnetSpeed = 280.0'f32
  CacheRareLegendaryChance = 40   # % chance a Rare cache adds a legendary
  CacheFallbackHeal = 0.15'f32    # of max HP, when nothing is left to upgrade

proc dropSurvivalCache*(game: var Game, pos: Vector2f, tier: SurvivalCacheTier) =
  let p = clampLootPosition(pos.x, pos.y, game.screenWidth, game.screenHeight)
  let at = newVector2f(p.x, p.y)
  game.survival.chests.add(SurvivalChest(pos: at, tier: tier, age: 0.0'f32))
  let accent = survivalCacheAccent(tier)
  spawnExplosionPooled(game.particlePool, at.x, at.y, accent, 18)
  spawnShockwaveRing(game, at, 46.0'f32, accent)
  playSound(stCoinPickup, 0.8, 0.8)

proc canOpenSurvivalCache*(game: Game): bool =
  ## Same gating as the dungeon's pedestals: only in live play, never on top of
  ## a boss fight or a level-up draft that is about to open.
  game.state == gsPlaying and game.player.hp > 0 and
    not game.bossWaveManager.active and not game.survival.reveal.active and
    game.pendingLevelDrafts <= 0 and game.levelDraftDelay <= 0

proc rollCacheLevel(game: var Game): PowerUp =
  ## One free level: an upgrade of an owned power-up, else a new one. Level 0
  ## when the normal pool has nothing left to give.
  var owned, fresh: seq[PowerUpType]
  for pt in normalPool:
    if game.player.isOfferable(pt, AllPowerFamilies, game.mode):
      if getPowerUpLevel(game.player, pt) > 0: owned.add(pt)
      else: fresh.add(pt)
  let pool = if owned.len > 0: owned else: fresh
  if pool.len == 0:
    return PowerUp(powerType: low(PowerUpType), level: 0, rarity: prCommon)
  let pt = pool[rand(pool.high)]
  PowerUp(powerType: pt, level: getPowerUpLevel(game.player, pt) + 1, rarity: prCommon)

proc openSurvivalCache*(game: var Game, tier: SurvivalCacheTier, at: Vector2f) =
  ## Apply a cache's rewards and start its reveal.
  var reveal = SurvivalCacheReveal(active: true, tier: tier)
  for _ in 0..<survivalCacheLevels(tier):
    # Rolled one at a time so each roll sees the level the previous one set.
    let pu = rollCacheLevel(game)
    if pu.level > 0:
      installPowerUp(game, pu, quiet = true)
      reveal.items.add(pu)
    else:
      reveal.shards += survivalCacheFallbackShards(tier)
      reveal.repaired = true
  if tier == sctRare and rand(99) < CacheRareLegendaryChance:
    let legendary = generatePowerUpChoices(game.player, true, AllPowerFamilies, game.mode)[0]
    if legendary.level > 0:
      installPowerUp(game, legendary, quiet = true)
      reveal.items.add(legendary)
  reveal.walls = survivalCacheWalls(tier)
  game.player.walls += reveal.walls
  if reveal.repaired:
    discard heal(game.player, game.player.maxHp * CacheFallbackHeal)
  if reveal.shards > 0:
    awardMetaCurrency(game, reveal.shards)
  game.survival.reveal = reveal
  inc game.survival.cachesOpened

  # Decryption burst, in the Bountiful jackpot's style but in the tier colour.
  let accent = survivalCacheAccent(tier)
  spawnNovaExplosionPooled(game.particlePool, at.x, at.y, 95.0'f32, accent,
                           Color(r: 255, g: 255, b: 255, a: 255))
  spawnShockwavePooled(game.particlePool, at.x, at.y, 55.0'f32)
  spawnShockwavePooled(game.particlePool, at.x, at.y, 110.0'f32)
  spawnSpiralExplosionPooled(game.particlePool, at.x, at.y, 75.0'f32, 5, accent)
  addShake(game.dopamine.screenShake, siMedium, accent)
  playSound(stRestoreAccess, 0.9)

proc updateSurvivalChests*(game: var Game, dt: float32) =
  ## Age, magnet and open the caches on the floor. At most one opens per frame
  ## (its reveal pauses the sim, so a pile opens one reveal after another).
  let canOpen = canOpenSurvivalCache(game)
  var i = 0
  while i < game.survival.chests.len:
    game.survival.chests[i].age += dt
    let chest = game.survival.chests[i]
    let dist = distance(chest.pos, game.player.pos)
    if chest.age >= CacheMagnetDelay and
       (dist < game.player.auraRadius or game.player.magnetTimer > 0) and dist > 1.0'f32:
      let dir = (game.player.pos - chest.pos).normalize()
      game.survival.chests[i].pos = chest.pos + dir * min(dist, CacheMagnetSpeed * dt)
    if canOpen and dist < CacheOpenRadius + game.player.radius:
      game.survival.chests.delete(i)
      openSurvivalCache(game, chest.tier, chest.pos)
      return
    inc i

proc drawSurvivalChests*(game: Game) =
  ## A Data Cache: a small bobbing crate in its tier colour with a glowing seam,
  ## a chip glyph, a light beam for the better tiers and a pulsing floor ring.
  let now = getTime().float32
  for chest in game.survival.chests:
    let accent = survivalCacheAccent(chest.tier)
    let bob = sin(now * 3.0'f32 + chest.pos.x * 0.05'f32) * 3.0'f32
    let pop = clamp(chest.age / 0.25'f32, 0.0'f32, 1.0'f32)
    let w = 26.0'f32 * pop
    let h = 20.0'f32 * pop
    let cx = chest.pos.x
    let cy = chest.pos.y + bob
    let pulse = sin(now * 5.0'f32) * 0.5'f32 + 0.5'f32
    # Floor ring and shadow
    drawCircleLines(chest.pos.x.int32, chest.pos.y.int32 + 12, 18.0'f32 + pulse * 6.0'f32,
                    withAlpha(accent, int(70.0'f32 + pulse * 60.0'f32)))
    drawEllipse(chest.pos.x.int32, chest.pos.y.int32 + 13, 14.0'f32, 4.0'f32,
                Color(r: 0, g: 0, b: 0, a: 90))
    # Light beam for the better tiers
    if chest.tier in {sctRare, sctKernel}:
      drawRectangle(int32(cx - 5.0'f32), int32(cy - 70.0'f32), 10, 60,
                    withAlpha(accent, int(35.0'f32 + pulse * 30.0'f32)))
      drawRectangle(int32(cx - 2.0'f32), int32(cy - 70.0'f32), 4, 60,
                    withAlpha(accent, int(60.0'f32 + pulse * 40.0'f32)))
    # Glow
    drawCircle(Vector2(x: cx, y: cy), 20.0'f32 + pulse * 3.0'f32, withAlpha(accent, 45))
    # Crate body
    let body = Rectangle(x: cx - w * 0.5'f32, y: cy - h * 0.5'f32, width: w, height: h)
    drawRectangleRounded(body, 0.25'f32, 4, Color(r: 14, g: 22, b: 34, a: 240))
    drawRectangleRoundedLines(body, 0.25'f32, 4, 2.0'f32, accent)
    # Lid seam
    drawLine(Vector2(x: cx - w * 0.5'f32 + 2.0'f32, y: cy - h * 0.12'f32),
             Vector2(x: cx + w * 0.5'f32 - 2.0'f32, y: cy - h * 0.12'f32), 2.0'f32,
             withAlpha(accent, int(160.0'f32 + pulse * 95.0'f32)))
    # Chip glyph
    let chip = 6.0'f32 * pop
    drawRectangle(int32(cx - chip * 0.5'f32), int32(cy + 1.0'f32), int32(chip), int32(chip * 0.8'f32),
                  withAlpha(accent, 230))
    # Tier label
    if pop >= 1.0'f32:
      let label = t(survivalCacheNameKey(chest.tier))
      let lw = measureText(label, 10)
      drawText(label, int32(cx) - lw div 2, int32(cy - h * 0.5'f32 - 14.0'f32), 10,
               withAlpha(accent, 220))

# ============================================================================
# System Events
# ============================================================================
# Between bosses the OS throws an event at the player every half minute or
# so; one runs at a time, on the survival clock (so it freezes with it):
#   Memory Leak       a torrent of weak, fast enemies from one edge; purge
#                     most of it for a Minor cache.
#   Firewall Breach   a ring of chasers closes in; wipe it out in time for a
#                     Data Cache.
#   Upload Zone       stand in a zone until its upload completes for a Data
#                     Cache (the fill decays outside from Overload on).
#   Corrupted Sector  telegraphed meteors rain around the player; outlast it
#                     for shards and a repair kit.
#   Rogue Process     a champion elite to hunt before it escapes, for a Rare
#                     cache. Guaranteed at the halfway mark of every phase.
#   Overclock         double XP and a denser horde for 15 s.
# Rewards also pay Data Shards (survivalEventShardReward in roguelite.nim).

const
  LeakWarmup = 2.0'f32
  LeakEmitTime = 12.0'f32
  LeakResolveTime = 4.0'f32
  LeakHpMult = 0.35'f32
  LeakDamageMult = 0.75'f32   # weak fodder: the threat is the volume

  BreachWarmup = 1.0'f32
  BreachLimit = 25.0'f32
  BreachRadius = 340.0'f32
  UploadLimit = 30.0'f32
  UploadRadius = 90.0'f32
  SectorWarmup = 1.5'f32
  SectorTime = 12.0'f32
  SectorRadius = 240.0'f32
  RogueWarmup = 1.2'f32
  RogueLimit = 45.0'f32
  OverclockTime = 15.0'f32
  RogueColor = Color(r: 220, g: 90, b: 255, a: 255)

proc survivalEventActive*(game: Game): bool {.inline.} =
  game.survival.event.kind != sekNone

proc setSurvivalBanner*(game: Game, kind: SurvivalBannerKind,
                        event: SurvivalEventKind = sekNone) =
  game.survival.bannerKind = kind
  game.survival.bannerEvent = event
  game.survival.bannerStart = game.time

proc leakInterval(phaseIndex: int): float32 =
  ## Seconds between leaked enemies: ~48 in Boot up to ~130 in Overtime.
  case phaseIndex
  of 0: 0.25'f32
  of 1: 0.15'f32
  of 2: 0.12'f32
  of 3: 0.11'f32
  else: 0.09'f32

proc leakSpeedMult(phaseIndex: int): float32 =
  if phaseIndex == 0: 1.2'f32 else: 1.35'f32

proc leakSuccessShare(phaseIndex: int): float32 =
  if phaseIndex == 0: 0.5'f32 else: 0.6'f32

proc uploadFillTime(phaseIndex: int): float32 =
  min(12.0'f32, 9.0'f32 + phaseIndex.float32)

proc countTagged(game: Game, tag: SurvivalTag): int =
  for e in game.enemies:
    if e.survivalTag == tag: inc result
  for p in game.survival.pending:
    if p.tag == tag: inc result

proc clearTag(game: Game, tag: SurvivalTag) =
  ## The event is over: its survivors become ordinary horde.
  for e in game.enemies:
    if e.survivalTag == tag: e.survivalTag = stgNone
  for i in 0..<game.survival.pending.len:
    if game.survival.pending[i].tag == tag:
      game.survival.pending[i].tag = stgNone

proc findEnemy(game: Game, id: int): Enemy =
  for e in game.enemies:
    if e.id == id: return e
  nil

proc removeEnemy(game: Game, id: int) =
  for i in 0..<game.enemies.len:
    if game.enemies[i].id == id:
      game.enemies.delete(i)
      return

proc arenaPointAround(game: Game, minDist, maxDist, margin: float32): Vector2f =
  ## A free point in the arena between minDist and maxDist from the player,
  ## re-rolled a few times; falls back to the arena point mirrored across the
  ## centre from the player.
  let w = game.screenWidth.float32
  let h = game.screenHeight.float32
  for _ in 0..15:
    let a = rand(PI * 2.0)
    let d = rand(minDist..maxDist)
    let p = game.player.pos + newVector2f(cos(a), sin(a)) * d
    if p.x < margin or p.y < margin or p.x > w - margin or p.y > h - margin:
      continue
    var blocked = false
    for wall in game.walls:
      if wall.hp > 0 and wallOverlapsCircle(wall, p, 30.0'f32):
        blocked = true
        break
    if not blocked:
      return p
  newVector2f(clamp(w - game.player.pos.x, margin, w - margin),
              clamp(h - game.player.pos.y, margin, h - margin))

proc lootPointNearPlayer(game: Game): Vector2f =
  let a = rand(PI * 2.0)
  game.player.pos + newVector2f(cos(a), sin(a)) * rand(60.0'f32..90.0'f32)

proc pickRogueType(game: Game): EnemyType =
  ## The current roster, minus Stars (hit-count based: HP scaling means nothing
  ## to them).
  for _ in 0..7:
    let et = pickSpawnType(game.difficulty)
    if et notin {etStar, etEnvironment}:
      return et
  etCube

# --- Lifecycle -------------------------------------------------------------------

proc startSurvivalEvent*(game: var Game, kind: SurvivalEventKind) =
  if kind == sekNone:
    return
  let p = survivalPhaseIndex(game)
  var ev = SurvivalEvent(kind: kind, rogueId: -1)
  case kind
  of sekNone: discard
  of sekMemoryLeak:
    ev.warmup = LeakWarmup
    ev.limit = LeakEmitTime
    ev.edge = rand(3)
  of sekFirewallBreach:
    ev.warmup = BreachWarmup
    ev.limit = BreachLimit
    ev.spawned = queueRing(game, 14 + 4 * p, BreachRadius, BreachWarmup, stgBreach,
                           allowElite = false)
    if ev.spawned == 0:
      return   # the horde cap left no room for a ring: skip it silently
  of sekUploadZone:
    ev.limit = UploadLimit
    ev.zonePos = arenaPointAround(game, 260.0'f32, 420.0'f32, 120.0'f32)
    ev.zoneRadius = UploadRadius
  of sekCorruptedSector:
    ev.warmup = SectorWarmup
    ev.limit = SectorTime
  of sekRogueProcess:
    ev.warmup = RogueWarmup
    ev.limit = RogueLimit
    ev.zonePos = arenaPointAround(game, 300.0'f32, 420.0'f32, 60.0'f32)
  of sekOverclock:
    ev.limit = OverclockTime
    game.survival.xpMult = 2.0'f32
  game.survival.event = ev
  game.survival.lastEventKind = kind
  inc game.survival.eventsStarted
  setSurvivalBanner(game, sbkEventStart, kind)
  playSound(stBossSpawn, 0.45, 1.5)

proc scheduleNextEvent(game: Game) =
  let ph = survivalPhase(game)
  game.survival.nextEventClock = game.survivalTime + SurvivalEventGap[ph] +
    rand(-SurvivalEventJitter[ph]..SurvivalEventJitter[ph])

proc finishSurvivalEvent(game: var Game, success: bool, rewardAt: Vector2f) =
  let kind = game.survival.event.kind
  let p = survivalPhaseIndex(game)
  if success:
    inc game.survival.eventsCleared
    case kind
    of sekNone, sekOverclock: discard
    of sekMemoryLeak:
      dropSurvivalCache(game, rewardAt, sctMinor)
      awardMetaCurrency(game, survivalEventShardReward(p, false))
    of sekFirewallBreach, sekUploadZone:
      dropSurvivalCache(game, rewardAt, sctStandard)
      awardMetaCurrency(game, survivalEventShardReward(p, false))
    of sekCorruptedSector:
      let at = lootPointNearPlayer(game)
      let lp = newVector2f(clamp(at.x, 50.0'f32, game.screenWidth.float32 - 50.0'f32),
                           clamp(at.y, 50.0'f32, game.screenHeight.float32 - 50.0'f32))
      game.consumables.add(newSpecificConsumable(lp.x, lp.y, ctHealth))
      awardMetaCurrency(game, survivalEventShardReward(p, false))
    of sekRogueProcess:
      dropSurvivalCache(game, rewardAt, sctRare)
      awardMetaCurrency(game, survivalEventShardReward(p, true))
    if kind != sekOverclock:
      setSurvivalBanner(game, sbkEventCleared, kind)
      playSound(stWaveComplete, 0.8)
  else:
    setSurvivalBanner(game, sbkEventFailed, kind)
    playSound(stTeleport, 0.6, 0.7)
  case kind
  of sekMemoryLeak: clearTag(game, stgLeak)
  of sekFirewallBreach: clearTag(game, stgBreach)
  of sekOverclock: game.survival.xpMult = 1.0'f32
  else: discard
  game.survival.event = SurvivalEvent(kind: sekNone, rogueId: -1)
  scheduleNextEvent(game)

proc cancelSurvivalEvent*(game: Game) =
  ## Drop the running event without reward or banner (a boss is arriving, a
  ## cheat forced another one, or the run is being restored).
  case game.survival.event.kind
  of sekRogueProcess:
    let rogue = findEnemy(game, game.survival.event.rogueId)
    if rogue != nil:
      spawnExplosionPooled(game.particlePool, rogue.pos.x, rogue.pos.y, RogueColor, 20)
      removeEnemy(game, rogue.id)
  of sekOverclock:
    game.survival.xpMult = 1.0'f32
  else: discard
  clearTag(game, stgLeak)
  clearTag(game, stgBreach)
  clearTag(game, stgRogue)
  game.survival.event = SurvivalEvent(kind: sekNone, rogueId: -1)

proc spawnRogueProcess(game: var Game) =
  let p = survivalPhaseIndex(game)
  let ev = addr game.survival.event
  let e = newSurvivalEnemy(game, ev.zonePos, pickRogueType(game), stgRogue, allowElite = false)
  makeElite(e, int(game.difficulty * 2.0'f32), force = true,
            forcedEffects = (if p >= 2: 3 else: 2))
  # Sized to the build it has to test: a fixed multiple of its own HP, or ten-
  # odd seconds of the player's measured damage output, whichever is larger.
  let dpsFloor = game.dopamine.realTimeStats.dps * (8.0'f32 + 2.0'f32 * p.float32)
  e.maxHp = max(e.maxHp * (8.0'f32 + 4.0'f32 * p.float32), dpsFloor)
  e.hp = e.maxHp
  if e.maxShieldHp > 0:
    e.maxShieldHp = e.maxHp * 0.25'f32
    e.shieldHp = e.maxShieldHp
  e.radius *= 1.6'f32
  e.collisionRadius = e.radius * 0.4'f32
  e.threatLevel = if p >= 2: 5 else: 4
  e.color = RogueColor
  e.hasEnteredScreen = true
  game.enemies.add(e)
  ev.rogueId = e.id
  ev.spawned = 1
  spawnExplosionPooled(game.particlePool, e.pos.x, e.pos.y, RogueColor, 36)
  spawnShockwaveRing(game, e.pos, 70.0'f32, RogueColor)
  addShake(game.dopamine.screenShake, siMedium, RogueColor)
  playSound(stTeleport, 0.8, 0.8)

proc spawnSectorMeteor(game: Game, phaseIndex: int) =
  let w = game.screenWidth.float32
  let h = game.screenHeight.float32
  var target: Vector2f
  if rand(99) < 45:
    # Aimed where the player is heading, so standing still is not an answer
    # and running in a straight line is not either.
    target = game.player.pos + game.player.vel * 0.5'f32 +
             newVector2f(rand(-40.0'f32..40.0'f32), rand(-40.0'f32..40.0'f32))
  else:
    let a = rand(PI * 2.0)
    target = game.player.pos + newVector2f(cos(a), sin(a)) * rand(SectorRadius)
  target = newVector2f(clamp(target.x, 30.0'f32, w - 30.0'f32),
                       clamp(target.y, 30.0'f32, h - 30.0'f32))
  let m = newMeteorite(target.x, target.y, target.x + rand(-80.0'f32..80.0'f32),
                       target.y - 650.0'f32, 1 + phaseIndex, 1.1'f32, -1)
  m.radius = 16.0'f32
  m.splashDamage = 0.5'f32 * (1 + phaseIndex).float32
  game.meteorites.add(m)
  inc game.survival.event.spawned

proc leakEmitPoint(game: Game, edge: int, frac: float32): Vector2f =
  ## A point just outside `edge` that sweeps across its middle 60% as the leak
  ## runs, so the torrent visibly travels.
  let w = game.screenWidth.float32
  let h = game.screenHeight.float32
  let s = clamp(0.2'f32 + 0.6'f32 * frac + rand(-0.04'f32..0.04'f32), 0.05'f32, 0.95'f32)
  case edge
  of 0: newVector2f(s * w, -30.0'f32)
  of 1: newVector2f(w + 30.0'f32, s * h)
  of 2: newVector2f(s * w, h + 30.0'f32)
  else: newVector2f(-30.0'f32, s * h)

proc updateSurvivalEvent*(game: var Game, dt: float32) =
  ## Advance the running event by `dt` survival-clock seconds.
  if not survivalEventActive(game):
    return
  let p = survivalPhaseIndex(game)
  let ev = addr game.survival.event
  ev.elapsed += dt
  let live = ev.elapsed - ev.warmup
  case ev.kind
  of sekNone: discard

  of sekMemoryLeak:
    if live >= 0 and not ev.emitDone:
      ev.emitTimer -= dt
      let interval = leakInterval(p)
      while ev.emitTimer <= 0:
        ev.emitTimer += interval
        if survivalAliveCount(game) < SurvivalMaxAlive:
          let et = if p >= 2 and rand(99) < 30: etTriangle else: etCircle
          let leaked = addSurvivalEnemy(game, leakEmitPoint(game, ev.edge, live / LeakEmitTime), et,
                                        stgLeak, LeakHpMult, leakSpeedMult(p), allowElite = false)
          leaked.contactDamage *= LeakDamageMult
          inc ev.spawned
      if live >= LeakEmitTime:
        ev.emitDone = true
    if ev.emitDone and live >= LeakEmitTime + LeakResolveTime:
      let success = ev.spawned > 0 and
        ev.killed.float32 >= leakSuccessShare(p) * ev.spawned.float32
      finishSurvivalEvent(game, success, lootPointNearPlayer(game))

  of sekFirewallBreach:
    if live >= 0.3'f32 and countTagged(game, stgBreach) == 0:
      finishSurvivalEvent(game, true, lootPointNearPlayer(game))
    elif live >= ev.limit:
      finishSurvivalEvent(game, false, game.player.pos)

  of sekUploadZone:
    let fill = uploadFillTime(p)
    if distance(game.player.pos, ev.zonePos) <= ev.zoneRadius:
      ev.progress = min(1.0'f32, ev.progress + dt / fill)
    elif p >= 2:
      ev.progress = max(0.0'f32, ev.progress - 0.25'f32 * dt / fill)
    let step = int(ev.progress * 4.0'f32)
    if step > ev.progressStep and step < 4:
      ev.progressStep = step
      playSound(stCoinPickup, 0.7, 1.0'f32 + 0.15'f32 * step.float32)
    elif step < ev.progressStep:
      ev.progressStep = step
    if ev.progress >= 1.0'f32:
      finishSurvivalEvent(game, true, ev.zonePos)
    elif ev.elapsed >= ev.limit:
      finishSurvivalEvent(game, false, ev.zonePos)

  of sekCorruptedSector:
    if live >= 0:
      ev.emitTimer -= dt
      while ev.emitTimer <= 0:
        ev.emitTimer += max(0.26'f32, 0.42'f32 - 0.04'f32 * p.float32)
        spawnSectorMeteor(game, p)
      if live >= ev.limit:
        finishSurvivalEvent(game, true, game.player.pos)

  of sekRogueProcess:
    if ev.spawned == 0:
      if live >= 0:
        spawnRogueProcess(game)
    else:
      let rogue = findEnemy(game, ev.rogueId)
      if rogue == nil:
        # Gone without the kill hook seeing it (e.g. swept by a cheat): no reward.
        finishSurvivalEvent(game, false, game.player.pos)
      elif live >= ev.limit:
        # Timed out: the process escapes.
        spawnExplosionPooled(game.particlePool, rogue.pos.x, rogue.pos.y, RogueColor, 30)
        spawnShockwaveRing(game, rogue.pos, 60.0'f32, RogueColor)
        removeEnemy(game, rogue.id)
        finishSurvivalEvent(game, false, game.player.pos)

  of sekOverclock:
    if ev.elapsed >= ev.limit:
      finishSurvivalEvent(game, true, game.player.pos)

proc onSurvivalEventKill*(game: var Game, enemy: Enemy) =
  ## Kill hook for event-tagged enemies.
  case enemy.survivalTag
  of stgNone: discard
  of stgLeak:
    if game.survival.event.kind == sekMemoryLeak:
      inc game.survival.event.killed
  of stgBreach: discard   # the breach counts what is left, not what died
  of stgRogue:
    if game.survival.event.kind == sekRogueProcess and
       enemy.id == game.survival.event.rogueId:
      finishSurvivalEvent(game, true, enemy.pos)

# --- Scheduling -------------------------------------------------------------------

proc eventFits(game: Game, kind: SurvivalEventKind, rogueAt: float32): bool =
  ## An event must finish 8 s before the next boss and must not overlap the
  ## upcoming guaranteed Rogue Process.
  let now = game.survivalTime
  let finish = now + survivalEventDuration(kind)
  if finish + 8.0'f32 > survivalNextBossTime(game):
    return false
  if kind != sekRogueProcess and rogueAt > now and finish + 4.0'f32 > rogueAt:
    return false
  true

proc pickRandomEvent(game: Game, rogueAt: float32): SurvivalEventKind =
  let weights = SurvivalEventWeights[survivalPhase(game)]
  var total = 0
  for k in SurvivalEventKind:
    if k in {sekNone, sekRogueProcess} or k == game.survival.lastEventKind or
       weights[k] <= 0 or not eventFits(game, k, rogueAt):
      continue
    total += weights[k]
  if total <= 0:
    return sekNone
  var roll = rand(total - 1)
  for k in SurvivalEventKind:
    if k in {sekNone, sekRogueProcess} or k == game.survival.lastEventKind or
       weights[k] <= 0 or not eventFits(game, k, rogueAt):
      continue
    if roll < weights[k]: return k
    roll -= weights[k]
  sekNone

proc updateSurvivalScheduler*(game: var Game) =
  ## Start the next event when its time comes. Called on frames where the
  ## survival clock is running (no boss alive).
  let s = addr game.survival
  # Cheat: start the requested event right now, replacing any running one.
  if s.cheatEventKind != sekNone:
    let kind = s.cheatEventKind
    s.cheatEventKind = sekNone
    if survivalEventActive(game):
      cancelSurvivalEvent(game)
    startSurvivalEvent(game, kind)
    return
  if survivalEventActive(game) or game.pendingBoss != nil or game.bossWaveManager.active:
    return
  let now = game.survivalTime
  # Skip Rogue slots left far behind (a resume, a clock cheat).
  while now > survivalRogueTime(s.nextRogueIndex) + SurvivalRogueStale:
    inc s.nextRogueIndex
  let rogueAt = survivalRogueTime(s.nextRogueIndex)
  if now >= rogueAt:
    inc s.nextRogueIndex
    if eventFits(game, sekRogueProcess, rogueAt):
      startSurvivalEvent(game, sekRogueProcess)
      return
  if now < s.nextEventClock:
    return
  let kind =
    if s.eventsStarted == 0: sekMemoryLeak   # the opener shows what events are
    else: pickRandomEvent(game, survivalRogueTime(s.nextRogueIndex))
  if kind == sekNone or not eventFits(game, kind, survivalRogueTime(s.nextRogueIndex)):
    s.nextEventClock = now + 5.0'f32   # nothing fits right now; look again shortly
    return
  startSurvivalEvent(game, kind)

# --- HUD tracker --------------------------------------------------------------------

proc survivalTrackerInfo*(game: Game): tuple[detail: string, frac: float32, remaining: float32] =
  ## What the HUD's event card shows: a status line, a 0..1 bar and the
  ## seconds left.
  let ev = game.survival.event
  let p = survivalPhaseIndex(game)
  let live = ev.elapsed - ev.warmup
  if live < 0:
    return (t(tkSurvivalTrackerIncoming), clamp(ev.elapsed / max(0.01'f32, ev.warmup), 0.0'f32, 1.0'f32),
            ev.warmup - ev.elapsed)
  case ev.kind
  of sekNone:
    ("", 0.0'f32, 0.0'f32)
  of sekMemoryLeak:
    let pct = if ev.spawned > 0: int(100.0'f32 * ev.killed.float32 / ev.spawned.float32) else: 0
    let total = LeakEmitTime + LeakResolveTime
    (t(tkSurvivalTrackerPurged).replace("$1", $pct) & " / " & $int(leakSuccessShare(p) * 100.0'f32) & "%",
     clamp(1.0'f32 - live / total, 0.0'f32, 1.0'f32), total - live)
  of sekFirewallBreach:
    (t(tkSurvivalTrackerRemaining).replace("$1", $countTagged(game, stgBreach)),
     clamp(1.0'f32 - live / ev.limit, 0.0'f32, 1.0'f32), ev.limit - live)
  of sekUploadZone:
    (t(tkSurvivalTrackerUploaded).replace("$1", $int(ev.progress * 100.0'f32)),
     ev.progress, ev.limit - ev.elapsed)
  of sekCorruptedSector:
    (t(tkSurvivalTrackerSurvive), clamp(1.0'f32 - live / ev.limit, 0.0'f32, 1.0'f32), ev.limit - live)
  of sekRogueProcess:
    let rogue = findEnemy(game, ev.rogueId)
    let hpPct = if rogue != nil and rogue.maxHp > 0: int(100.0'f32 * rogue.hp / rogue.maxHp) else: 0
    (t(tkSurvivalTrackerRemaining).replace("$1", $hpPct & "%"),
     clamp(1.0'f32 - live / ev.limit, 0.0'f32, 1.0'f32), ev.limit - live)
  of sekOverclock:
    (t(tkSurvivalTrackerXpBoost), clamp(1.0'f32 - ev.elapsed / ev.limit, 0.0'f32, 1.0'f32),
     ev.limit - ev.elapsed)

# --- World drawing ------------------------------------------------------------------

proc drawEdgeBand(game: Game, edge: int, color: Color, thickness: int32) =
  let w = game.screenWidth
  let h = game.screenHeight
  case edge
  of 0: drawRectangle(0, 0, w, thickness, color)
  of 1: drawRectangle(w - thickness, 0, thickness, h, color)
  of 2: drawRectangle(0, h - thickness, w, thickness, color)
  else: drawRectangle(0, 0, thickness, h, color)

proc drawSurvivalEventsUnder*(game: Game) =
  ## Event telegraphs and zones, drawn under the actors.
  let ev = game.survival.event
  if ev.kind == sekNone:
    return
  let now = getTime().float32
  let pulse = sin(now * 8.0'f32) * 0.5'f32 + 0.5'f32
  let color = survivalEventColor(ev.kind)
  let live = ev.elapsed - ev.warmup
  case ev.kind
  of sekNone: discard
  of sekMemoryLeak:
    if not ev.emitDone:
      let a = if live < 0: 70.0'f32 + pulse * 110.0'f32 else: 45.0'f32 + pulse * 30.0'f32
      drawEdgeBand(game, ev.edge, withAlpha(color, int(a)), 10)
      drawEdgeBand(game, ev.edge, withAlpha(color, int(a * 0.5'f32)), 26)
  of sekFirewallBreach:
    if live < 0.5'f32:
      let a = int(90.0'f32 + pulse * 120.0'f32)
      drawCircleLines(game.player.pos.x.int32, game.player.pos.y.int32, BreachRadius,
                      withAlpha(color, a))
      drawCircleLines(game.player.pos.x.int32, game.player.pos.y.int32, BreachRadius - 3.0'f32,
                      withAlpha(color, a div 2))
  of sekUploadZone:
    let inside = distance(game.player.pos, ev.zonePos) <= ev.zoneRadius
    let center = Vector2(x: ev.zonePos.x, y: ev.zonePos.y)
    drawCircle(center, ev.zoneRadius, withAlpha(color, if inside: 60 else: 32))
    drawCircleLines(ev.zonePos.x.int32, ev.zonePos.y.int32, ev.zoneRadius,
                    withAlpha(color, int(150.0'f32 + pulse * 100.0'f32)))
    # Progress arc around the rim, filling clockwise from the top.
    if ev.progress > 0.0'f32:
      drawRing(center, ev.zoneRadius + 3.0'f32, ev.zoneRadius + 9.0'f32, -90.0'f32,
               -90.0'f32 + 360.0'f32 * ev.progress, 48, withAlpha(color, 230))
    let label = $int(ev.progress * 100.0'f32) & "%"
    let lw = measureText(label, 22)
    drawText(label, ev.zonePos.x.int32 - lw div 2, ev.zonePos.y.int32 - 11, 22,
             withAlpha(color, if inside: 255 else: 190))
    let name = t(tkSurvivalEventUploadZone)
    let nw = measureText(name, 11)
    drawText(name, ev.zonePos.x.int32 - nw div 2, ev.zonePos.y.int32 + 14, 11,
             withAlpha(color, 200))
  of sekCorruptedSector:
    let a = if live < 0: int(80.0'f32 + pulse * 120.0'f32) else: int(35.0'f32 + pulse * 35.0'f32)
    drawCircleLines(game.player.pos.x.int32, game.player.pos.y.int32, SectorRadius,
                    withAlpha(color, a))
  of sekRogueProcess:
    if ev.spawned == 0:
      let prog = clamp(ev.elapsed / max(0.01'f32, ev.warmup), 0.0'f32, 1.0'f32)
      let r = 60.0'f32 - prog * 40.0'f32
      drawCircleLines(ev.zonePos.x.int32, ev.zonePos.y.int32, r,
                      withAlpha(RogueColor, int(120.0'f32 + pulse * 120.0'f32)))
      drawCircleLines(ev.zonePos.x.int32, ev.zonePos.y.int32, r * 0.6'f32,
                      withAlpha(RogueColor, int(80.0'f32 + pulse * 80.0'f32)))
  of sekOverclock:
    # Gold heat shimmer along the arena border.
    let a = int(25.0'f32 + pulse * 35.0'f32)
    for edge in 0..3:
      drawEdgeBand(game, edge, withAlpha(color, a), 6)

proc drawSurvivalEventsOver*(game: Game) =
  ## Rogue Process label, HP bar and a pointer from the player to it.
  let ev = game.survival.event
  if ev.kind != sekRogueProcess or ev.spawned == 0:
    return
  let rogue = findEnemy(game, ev.rogueId)
  if rogue == nil:
    return
  let now = getTime().float32
  let pulse = sin(now * 6.0'f32) * 0.5'f32 + 0.5'f32
  let name = t(tkSurvivalEventRogueProcess)
  let nw = measureText(name, 12)
  let top = rogue.pos.y - rogue.radius - 34.0'f32
  drawText(name, rogue.pos.x.int32 - nw div 2, top.int32, 12, RogueColor)
  const barW = 64'i32
  let bx = rogue.pos.x.int32 - barW div 2
  let by = top.int32 + 15
  drawRectangle(bx, by, barW, 5, Color(r: 30, g: 10, b: 40, a: 220))
  let frac = clamp(rogue.hp / max(0.01'f32, rogue.maxHp), 0.0'f32, 1.0'f32)
  drawRectangle(bx, by, int32(barW.float32 * frac), 5, RogueColor)
  drawRectangleLines(bx, by, barW, 5, withAlpha(RogueColor, 180))
  # Pointer: a chevron orbiting the player, aimed at the rogue.
  let toRogue = rogue.pos - game.player.pos
  let dist = toRogue.length()
  if dist > 180.0'f32:
    let dir = toRogue.normalize()
    let tip = game.player.pos + dir * (game.player.radius + 34.0'f32)
    let side = newVector2f(-dir.y, dir.x)
    let back = tip - dir * 12.0'f32
    let a = uint8(160.0'f32 + pulse * 95.0'f32)
    let c = Color(r: RogueColor.r, g: RogueColor.g, b: RogueColor.b, a: a)
    drawTriangle(Vector2(x: tip.x, y: tip.y),
                 Vector2(x: back.x - side.x * 7.0'f32, y: back.y - side.y * 7.0'f32),
                 Vector2(x: back.x + side.x * 7.0'f32, y: back.y + side.y * 7.0'f32), c)
    drawTriangle(Vector2(x: tip.x, y: tip.y),
                 Vector2(x: back.x + side.x * 7.0'f32, y: back.y + side.y * 7.0'f32),
                 Vector2(x: back.x - side.x * 7.0'f32, y: back.y - side.y * 7.0'f32), c)

# ============================================================================
# Orchestrator (called from game.nim)
# ============================================================================

const
  EliteCacheChance = 30          # per mille, per plain elite kill
  EliteCacheCooldown = 60.0'f32  # survival-clock seconds between elite caches
  BossArrivalKeep = 20           # plain enemies left standing when a boss arrives

proc updateSurvival*(game: var Game, dt: float32) =
  ## Per-frame survival step: banners, the horde, formations, events, caches.
  ## Runs after game.nim has ticked the survival clock for this frame.
  if game.state != gsPlaying:
    return
  let s = addr game.survival
  # Mirrors the clock gate in updateGame: events and formations only run while
  # the clock does.
  let clockRunning = not game.bossWaveManager.active and not game.bossWaveManager.coinActive

  # A new phase begins the first live frame after the boss that closed the
  # last one (after its reward draft), so its banner never fights the intro.
  let ph = survivalPhase(game)
  if ph != s.lastPhase:
    s.lastPhase = ph
    setSurvivalBanner(game, sbkPhase)
    playSound(stRestoreAccess, 0.8, 1.1)
    spawnWavePulse(game.osBackground, game.player.pos.x, game.player.pos.y,
                   SurvivalPhaseAccent[ph])

  # Ten-second warning before the next boss.
  let nextBoss = game.bossCount + 1
  if clockRunning and s.bossWarnedIndex < nextBoss and game.pendingBoss == nil:
    let lead = survivalBossTime(nextBoss) - game.survivalTime
    if lead > 0 and lead <= SurvivalBossWarnLead:
      s.bossWarnedIndex = nextBoss
      let isFinal = nextBoss == SurvivalFinalBoss and not s.victoryAchieved
      setSurvivalBanner(game, if isFinal: sbkFinalInbound else: sbkBossInbound)
      playSound(stBossSpawn, 0.35, 1.7)

  updateSurvivalPending(game, dt)
  updateSurvivalDensity(game, dt)
  if clockRunning:
    updateSurvivalFormations(game)
    updateSurvivalScheduler(game)
    updateSurvivalEvent(game, dt)
  updateSurvivalChests(game, dt)

proc prepareSurvivalBossArrival*(game: var Game) =
  ## A boss is about to spawn: end the running event and reclaim most of the
  ## horde so the fight starts on a readable board.
  cancelSurvivalEvent(game)
  reclaimSurvivalFodder(game, BossArrivalKeep)
  game.survival.spawnBudget = 0.0'f32

proc onSurvivalBossDefeated*(game: var Game, bossPos: Vector2f): bool =
  ## Boss bounty and its Kernel cache. True when this was the final boss (the
  ## run is won; the caller routes to the victory screen).
  let k = game.bossCount
  let s = addr game.survival
  awardMetaCurrency(game, survivalBossShardReward(k), survivalBossCoreReward(k))
  dropSurvivalCache(game, bossPos, sctKernel)
  # A breather: no event for 20 s, no set piece for 12 s.
  s.nextEventClock = max(s.nextEventClock, game.survivalTime + 20.0'f32)
  s.formationClock = max(s.formationClock, game.survivalTime + 12.0'f32)
  s.pending.setLen(0)
  s.spawnBudget = 0.0'f32
  if k >= SurvivalFinalBoss and not s.victoryAchieved:
    s.victoryAchieved = true
    awardMetaCurrency(game, SurvivalVictoryShards, SurvivalVictoryCores)
    game.survivalVictoryJustEarned = not game.cheatsUsed
    return true
  false

proc onSurvivalEnemyKilled*(game: var Game, enemy: Enemy) =
  ## Kill hook: event bookkeeping, and the occasional cache from an elite.
  if enemy.isBoss:
    return
  onSurvivalEventKill(game, enemy)
  let s = addr game.survival
  if enemy.isElite and enemy.survivalTag == stgNone and
     game.survivalTime - s.lastEliteCacheClock >= EliteCacheCooldown and
     rand(999) < EliteCacheChance:
    s.lastEliteCacheClock = game.survivalTime
    dropSurvivalCache(game, enemy.pos, sctMinor)

proc drawSurvivalWorldUnder*(game: Game) =
  ## Event zones and telegraphs, spawn markers and caches (under the actors).
  drawSurvivalEventsUnder(game)
  drawSurvivalSpawnMarkers(game)
  drawSurvivalChests(game)

proc drawSurvivalWorldOver*(game: Game) =
  ## Overlays that must sit on top of the enemies (the Rogue Process label).
  drawSurvivalEventsOver(game)

# ============================================================================
# Data Cache reveal overlay
# ============================================================================
# Time Survival Data Cache reveal: the overlay that shows what an opened cache
# installed. The rewards are already applied (openSurvivalCache); this only
# presents them, one card flipping over at a time, while updateGame keeps the
# simulation paused. It closes on its own a moment after the last card, or on
# confirm (the first press just finishes the flips).

const
  RevealFirstFlip = 0.35'f32
  RevealFlipStep = 0.35'f32
  RevealFlipTime = 0.25'f32
  RevealInputGrace = 0.6'f32   # the player is usually mid-fight when a cache opens
  RevealLinger = 2.5'f32       # auto-close this long after the last card
  CardW = 118'i32
  CardH = 150'i32
  CardGap = 14'i32

proc flipAt(i: int): float32 {.inline.} =
  RevealFirstFlip + RevealFlipStep * i.float32

proc allFlippedAt(r: SurvivalCacheReveal): float32 =
  flipAt(r.items.len) + 0.1'f32

proc updateSurvivalCacheReveal*(game: Game, dt: float32): bool =
  ## Advance the reveal. True on the frame it closes.
  let r = addr game.survival.reveal
  if not r.active:
    return false
  let before = r.timer
  r.timer += dt
  for i in 0..<r.items.len:
    let at = flipAt(i)
    if before < at and r.timer >= at:
      let legendary = r.items[i].rarity == prLegendary
      playSound(if legendary: stPowerUp else: stBuy, 0.75, 1.0'f32 + 0.12'f32 * i.float32)
  let done = allFlippedAt(r[])
  let confirm = isPointerPressed() or isKeyPressed(KeyboardKey.Enter) or
                isKeyPressed(KeyboardKey.Space) or isGamepadConfirmPressed()
  if r.timer >= RevealInputGrace and confirm:
    if r.timer < done:
      r.timer = done            # first press: finish the flips
    else:
      r.active = false
      return true
  if r.timer >= done + RevealLinger:
    r.active = false
    return true
  false

proc wrapCardText(text: string, maxWidth, fontSize: int32): seq[string] =
  var line = ""
  for word in text.split(' '):
    if word.len == 0: continue
    let candidate = if line.len == 0: word else: line & " " & word
    if line.len > 0 and measureText(candidate, fontSize) > maxWidth:
      result.add(line)
      line = word
    else:
      line = candidate
  if line.len > 0:
    result.add(line)

proc drawRevealCard(x, y: int32, pu: PowerUp, flip: float32, accent: Color, time: float32) =
  ## `flip` 0 = face down, 1 = face up; the card squeezes through edge-on.
  let squeeze = abs(cos(flip * PI.float32))
  let w = max(2'i32, int32(CardW.float32 * squeeze))
  let cx = x + CardW div 2
  let rx = cx - w div 2
  let faceUp = flip >= 0.5'f32
  let legendary = pu.rarity == prLegendary
  let edge = if legendary: Color(r: 255, g: 215, b: 0, a: 255) else: accent
  let rect = Rectangle(x: rx.float32, y: y.float32, width: w.float32, height: CardH.float32)
  if not faceUp:
    drawRectangleRounded(rect, 0.12'f32, 6, Color(r: 18, g: 26, b: 40, a: 250))
    drawRectangleRoundedLines(rect, 0.12'f32, 6, 2.0'f32, withAlpha(accent, 200))
    if w > 40:
      let pulse = sin(time * 6.0'f32) * 0.5'f32 + 0.5'f32
      let q = "?"
      let qw = measureText(q, 44)
      drawText(q, cx - qw div 2, y + CardH div 2 - 22, 44,
               withAlpha(accent, int(140.0'f32 + pulse * 100.0'f32)))
    return
  drawRectangleRounded(rect, 0.12'f32, 6, Color(r: 12, g: 20, b: 32, a: 250))
  drawRectangleRoundedLines(rect, 0.12'f32, 6, 2.0'f32, edge)
  if w < CardW - 10:
    return   # still mid-flip: only the frame reads at this width
  const iconSize = 56'i32
  let color = if legendary: Color(r: 255, g: 215, b: 0, a: 255) else: getPowerUpColor(pu.powerType)
  drawPowerUpIcon(cx - iconSize div 2, y + 12, iconSize, pu.powerType, color)
  var ny = y + 12 + iconSize + 8
  for ln in wrapCardText(getPowerUpName(pu.powerType), CardW - 12, 12):
    let lw = measureText(ln, 12)
    drawText(ln, cx - lw div 2, ny, 12, Color(r: 225, g: 235, b: 245, a: 255))
    ny += 14
  let tag =
    if legendary: t(tkSurvivalCacheLegendary)
    elif pu.level <= 1: t(tkSurvivalCacheNew)
    else: t(tkSurvivalCacheLevel).replace("$1", $pu.level)
  let tagW = measureText(tag, 13) + 12
  let tagX = cx - tagW div 2
  let tagY = y + CardH - 24
  drawRectangle(tagX, tagY, tagW, 17, withAlpha(edge, 60))
  drawRectangleLines(tagX, tagY, tagW, 17, edge)
  drawText(tag, tagX + 6, tagY + 2, 13, edge)

proc drawSurvivalCacheReveal*(game: Game, screenWidth, screenHeight: int32) =
  let r = game.survival.reveal
  if not r.active:
    return
  let accent = survivalCacheAccent(r.tier)
  let fadeIn = clamp(r.timer / 0.2'f32, 0.0'f32, 1.0'f32)
  drawRectangle(0, 0, screenWidth, screenHeight, Color(r: 0, g: 0, b: 0, a: uint8(150.0'f32 * fadeIn)))

  let n = r.items.len.int32
  let cardsW = if n > 0: n * CardW + (n - 1) * CardGap else: 0'i32
  let panelW = max(440'i32, cardsW + 60)
  let panelH = if n > 0: 300'i32 else: 150'i32
  let panelX = (screenWidth - panelW) div 2
  let panelY = (screenHeight - panelH) div 2 - int32((1.0'f32 - fadeIn) * 20.0'f32)
  let panel = Rectangle(x: panelX.float32, y: panelY.float32,
                        width: panelW.float32, height: panelH.float32)
  drawRectangleRounded(panel, 0.06'f32, 8, Color(r: 8, g: 14, b: 24, a: 240))
  drawRectangleRoundedLines(panel, 0.06'f32, 8, 2.0'f32, accent)
  # Title bar
  drawRectangle(panelX + 2, panelY + 2, panelW - 4, 34, withAlpha(accent, 40))
  let title = t(survivalCacheNameKey(r.tier)) & "  //  " & t(tkSurvivalCacheDecrypted)
  let titleW = measureText(title, 20)
  drawText(title, panelX + (panelW - titleW) div 2, panelY + 9, 20, accent)

  # Cards
  let cardsX = panelX + (panelW - cardsW) div 2
  let cardsY = panelY + 50
  for i in 0..<r.items.len:
    let flip = clamp((r.timer - flipAt(i)) / RevealFlipTime, 0.0'f32, 1.0'f32)
    drawRevealCard(cardsX + i.int32 * (CardW + CardGap), cardsY, r.items[i], flip, accent,
                   game.time)

  # Bonus line: walls, fallback shards / repair
  var bonus: seq[string]
  if r.walls > 0:
    bonus.add(t(tkSurvivalCacheWalls).replace("$1", $r.walls))
  if r.shards > 0:
    bonus.add("+" & $r.shards & " " & t("roguelite_data_shards"))
  if r.repaired:
    bonus.add(t(tkSurvivalCacheRepair))
  let bonusY = if n > 0: cardsY + CardH + 14 else: panelY + 56
  if bonus.len > 0:
    let line = bonus.join("   ")
    let bw = measureText(line, 15)
    drawText(line, panelX + (panelW - bw) div 2, bonusY, 15, Color(r: 200, g: 230, b: 245, a: 255))

  # Continue hint once everything is face up
  if r.timer >= allFlippedAt(r):
    let hint = t(tkSurvivalCacheContinue)
    let hw = measureText(hint, 12)
    let pulse = sin(game.time * 4.0'f32) * 0.5'f32 + 0.5'f32
    drawText(hint, panelX + (panelW - hw) div 2, panelY + panelH - 22, 12,
             Color(r: 160, g: 180, b: 200, a: uint8(150.0'f32 + pulse * 100.0'f32)))

# --- HUD ------------------------------------------------------------------------

# Fixed vertical footprint of the survival HUD card. Must mirror the layout
# constants inside drawSurvivalHUD (padY + timerSize + vGap + phaseRowH +
# rowGap + barH + padY). game.nim uses SurvivalHudBottomY to start boss health
# bars below the timer, and survivalHudStackBottom to clear the event card.
const
  SurvivalHudPanelY*: int32 = 8
  SurvivalHudBottomY*: int32 = SurvivalHudPanelY + 9 + 30 + 7 + 14 + 6 + 12 + 9
  SurvivalTrackerGap: int32 = 6
  SurvivalTrackerH: int32 = 52
  SurvivalDockTrackerH: int32 = 46   # widescreen: the event as a docked card

proc survivalHudStackBottom*(game: Game): int32 =
  ## Bottom of the survival HUD stack: the card, plus the event card when an
  ## event is running.
  if survivalEventActive(game):
    SurvivalHudBottomY + SurvivalTrackerGap + SurvivalTrackerH
  else:
    SurvivalHudBottomY

proc survivalCountdownLabel(game: Game): tuple[text: string, urgent: bool] =
  if game.bossWaveManager.active or game.pendingBoss != nil:
    return (t(tkSurvivalHudBossLive), true)
  let nextBoss = game.bossCount + 1
  let left = survivalBossTime(nextBoss) - game.survivalTime
  let key = if nextBoss == SurvivalFinalBoss and not game.survival.victoryAchieved:
              tkSurvivalHudFinalIn
            else: tkSurvivalHudBossIn
  (t(key) & " " & formatSurvivalClock(left), left <= SurvivalBossWarnLead)

proc drawSurvivalTracker(game: Game, x, y, w: int32) =
  ## The running event: name, time left, a bar and a status line.
  let ev = game.survival.event
  let color = survivalEventColor(ev.kind)
  let info = survivalTrackerInfo(game)
  let rect = Rectangle(x: x.float32, y: y.float32, width: w.float32, height: SurvivalTrackerH.float32)
  drawRectangleRounded(rect, 0.25'f32, 6, Color(r: 8, g: 18, b: 28, a: 205))
  drawRectangleRoundedLines(rect, 0.25'f32, 6, 1.5'f32, withAlpha(color, 170))
  const pad: int32 = 12
  let name = t(survivalEventNameKey(ev.kind))
  drawText(name, x + pad + 1, y + 7, 14, Color(r: 0, g: 0, b: 0, a: 140))
  drawText(name, x + pad, y + 6, 14, color)
  let clock = formatSurvivalClock(info.remaining)
  let cw = measureText(clock, 14)
  let urgent = info.remaining <= 5.0'f32 and ev.kind != sekOverclock
  let pulse = sin(game.time * 10.0'f32) * 0.5'f32 + 0.5'f32
  let clockColor = if urgent: Color(r: 255, g: uint8(90.0'f32 + pulse * 80.0'f32), b: 90, a: 255)
                   else: Color(r: 225, g: 240, b: 250, a: 255)
  drawText(clock, x + w - pad - cw, y + 6, 14, clockColor)
  let barX = x + pad
  let barY = y + 25
  let barW = w - pad * 2
  drawRectangle(barX, barY, barW, 7, Color(r: 10, g: 25, b: 35, a: 220))
  let fillW = int32(barW.float32 * clamp(info.frac, 0.0'f32, 1.0'f32))
  if fillW > 0:
    drawRectangle(barX, barY, fillW, 7, withAlpha(color, 230))
  drawRectangleLines(barX, barY, barW, 7, withAlpha(color, 120))
  drawText(info.detail, barX, y + 36, 11, Color(r: 190, g: 215, b: 230, a: 255))

proc drawSurvivalTrackerDock(game: Game, x, y: int32): int32 =
  ## The running event as a docked card (widescreen right band). Returns the y
  ## below it.
  const h = SurvivalDockTrackerH
  let ev = game.survival.event
  let color = survivalEventColor(ev.kind)
  let info = survivalTrackerInfo(game)
  drawDockCard(x, y, DockCardW, h, color)
  let cx = x + DockPad
  let cw = DockContentW
  let clock = formatSurvivalClock(info.remaining)
  let clockW = measureText(clock, 10)
  let urgent = info.remaining <= 5.0'f32 and ev.kind != sekOverclock
  let pulse = sin(game.time * 10.0'f32) * 0.5'f32 + 0.5'f32
  drawShadowText(clock, cx + cw - clockW, y + 6, 10,
                 if urgent: Color(r: 255, g: uint8(90.0'f32 + pulse * 80.0'f32), b: 90, a: 255)
                 else: DockInk)
  let name = t(survivalEventNameKey(ev.kind))
  drawShadowText(name, cx, y + 6, bestFitFontSize(name, cw - clockW - 6, 10, 7), color)
  drawDockBar(cx, y + 20, cw, 6, info.frac, withAlpha(color, 230), withAlpha(color, 120))
  drawShadowText(info.detail, cx, y + 31, bestFitFontSize(info.detail, cw, 10, 7),
                 Color(r: 190, g: 215, b: 230, a: 255))
  y + h

proc drawStopwatchIcon(cx, cy, r, survivedT: float32, accent, handColor: Color) =
  ## Handheld stopwatch glyph. The hand sweeps once per minute of survival time;
  ## since survivalTime freezes during a boss, the hand visibly stops there
  ## (reinforced by the gray-out + pause glyph at the call sites).
  # Crown: a little button + stem on top so the icon reads as a stopwatch.
  drawRectangle((cx - 2.0).int32, (cy - r - 4.0).int32, 4, 4, accent)
  drawCircle(Vector2(x: cx, y: cy - r - 4.5), 2.0'f32, accent)
  # Face: dark fill, outer rim, faint inner rim, and 12/3/6/9 tick marks.
  drawCircle(Vector2(x: cx, y: cy), r + 1.0, Color(r: 6, g: 16, b: 24, a: 220))
  drawCircleLines(cx.int32, cy.int32, r, accent)
  drawCircleLines(cx.int32, cy.int32, r - 1.0, withAlpha(accent, 90))
  for q in 0..<4:
    let ta = q.float32 * (PI.float32 / 2.0)
    drawLine(Vector2(x: cx + cos(ta) * (r - 2.4), y: cy + sin(ta) * (r - 2.4)),
             Vector2(x: cx + cos(ta) * (r - 0.6), y: cy + sin(ta) * (r - 0.6)),
             1.0'f32, withAlpha(accent, 130))
  let handAng = (survivedT mod 60.0) / 60.0 * (PI.float32 * 2.0) - PI.float32 / 2.0
  let handLen = r * 0.72
  drawLine(Vector2(x: cx, y: cy),
           Vector2(x: cx + cos(handAng) * handLen, y: cy + sin(handAng) * handLen),
           2.0'f32, handColor)
  drawCircle(Vector2(x: cx, y: cy), 1.6'f32, accent)

proc stopwatchReadout(survivedT: float32): tuple[mmss, centis: string] =
  ## "MM:SS" and ".CC" for the stopwatch. Centiseconds derive from survivalTime,
  ## so they freeze with everything else during a boss fight.
  let totalSecs = int(survivedT)
  let mins = totalSecs div 60
  let secs = totalSecs mod 60
  let centis = int(survivedT * 100.0'f32) mod 100
  ((if mins < 10: "0" else: "") & $mins & ":" & (if secs < 10: "0" else: "") & $secs,
   "." & (if centis < 10: "0" else: "") & $centis)

proc drawSurvivalHUD*(game: Game, screenWidth, screenHeight: int32) =
  ## Classic (4:3) survival HUD, top-centre: one rounded "OS card" holding the
  ## survived-time stopwatch, the phase row (phase name + countdown to the next
  ## boss) and the run level + XP bar. While a System Event runs, a second card
  ## under it tracks the event. Widescreen docks drawSurvivalDockCard instead.

  const xpFill    = Color(r: 90,  g: 255, b: 170, a: 235)   # XP green
  const xpGold    = Color(r: 255, g: 215, b: 60,  a: 245)   # Overclock
  const inkShadow = Color(r: 0,   g: 0,   b: 0,   a: 140)

  # The survival clock pauses during a boss fight (survivalTime stops accumulating).
  # Gray the stopwatch out and show a pause glyph so the frozen clock reads as
  # intentional rather than a bug. `accent` follows suit so the whole row dims.
  # Matches the clock-pause condition in updateGame (boss alive OR its reward coin
  # still uncollected), so the gray-out/pause glyph tracks the frozen clock exactly.
  let bossActive = game.bossWaveManager.active or game.bossWaveManager.coinActive
  let phase = survivalPhase(game)
  let phaseColor = SurvivalPhaseAccent[phase]
  let accent = if bossActive: Color(r: 120, g: 140, b: 150, a: 255)
               else: phaseColor
  let digitColor = if bossActive: Color(r: 150, g: 165, b: 175, a: 255)
                   else: Color(r: 225, g: 246, b: 255, a: 255)

  # --- Layout (centred horizontally near the top) -------------------------
  const padX: int32 = 16
  const padY: int32 = 9
  const vGap: int32 = 7          # space between the clock row and the phase row
  const phaseRowH: int32 = 14
  const rowGap: int32 = 6        # space between the phase row and the XP bar
  const timerSize: int32 = 30
  const centiSize: int32 = 17    # smaller centiseconds tucked after MM:SS
  const centiGap: int32 = 2      # gap between MM:SS and the .CC tenths
  const lblSize: int32 = 13
  const phaseSize: int32 = 13
  const barW: int32 = 230
  const barH: int32 = 12
  const lblGap: int32 = 8        # gap between "LV n" and the bar
  const clockR: int32 = 10       # stopwatch icon radius
  const iconGap: int32 = 7       # gap between stopwatch icon and the digits

  # Stopwatch readout MM:SS.CC. MM:SS is laid against a fixed "00:00" slot and the
  # centiseconds against a fixed ".00" slot so the panel never jitters as the
  # proportional-width digits change. Centiseconds derive from survivalTime, so
  # they freeze with everything else during a boss fight.
  let clampedT = max(0.0'f32, game.survivalTime)
  let (timeStr, centiStr) = stopwatchReadout(clampedT)
  let timerSlotW = measureText("00:00", timerSize)
  let centiSlotW = measureText(".00", centiSize)
  let timerDigitsW = measureText(timeStr, timerSize)
  let clockBox = clockR * 2 + iconGap
  let timerRowW = clockBox + timerSlotW + centiGap + centiSlotW

  let lvlLabel = t("roguelite_level") & " " & $game.player.rogueliteLevel
  let lblW = measureText(lvlLabel, lblSize)
  let barRowW = lblW + lblGap + barW

  let phaseName = t(survivalPhaseNameKey(phase))
  let countdown = survivalCountdownLabel(game)
  let phaseRowW = 12 + measureText(phaseName, phaseSize) + 16 + measureText(countdown.text, phaseSize)

  let contentW = max(max(timerRowW, barRowW), phaseRowW)
  let panelW = contentW + padX * 2
  let panelH = padY + timerSize + vGap + phaseRowH + rowGap + barH + padY
  let panelX = screenWidth div 2 - panelW div 2
  const panelY: int32 = SurvivalHudPanelY

  # --- Card background ----------------------------------------------------
  let panelRect = Rectangle(x: panelX.float32, y: panelY.float32,
                            width: panelW.float32, height: panelH.float32)
  drawRectangleRounded(panelRect, 0.28'f32, 6, Color(r: 8, g: 18, b: 28, a: 205))
  drawRectangleRoundedLines(panelRect, 0.28'f32, 6, 1.5'f32,
                            withAlpha(accent, 150))

  # --- Row 1: stopwatch icon + MM:SS.CC -----------------------------------
  let timerRowX = panelX + (panelW - timerRowW) div 2
  let timerY = panelY + padY
  drawStopwatchIcon((timerRowX + clockR).float32, (timerY + timerSize div 2).float32,
                    clockR.float32, clampedT, accent, digitColor)
  # MM:SS digits, centred in the fixed slot. An accent glow (live only) + shadow
  # lift them off the card.
  let digitsX = timerRowX + clockBox + (timerSlotW - timerDigitsW) div 2
  if not bossActive:
    drawText(timeStr, digitsX, timerY - 1, timerSize,
             withAlpha(accent, 55))
  drawText(timeStr, digitsX + 1, timerY + 1, timerSize, inkShadow)
  drawText(timeStr, digitsX, timerY, timerSize, digitColor)
  # Centiseconds: smaller + dimmer, baseline-aligned under the big digits.
  let centiX = timerRowX + clockBox + timerSlotW + centiGap
  let centiY = timerY + (timerSize - centiSize)
  drawText(centiStr, centiX + 1, centiY + 1, centiSize, inkShadow)
  drawText(centiStr, centiX, centiY, centiSize,
           withAlpha(digitColor, 175))
  # Pause glyph (two bars) past the centiseconds while the clock is frozen by a boss.
  if bossActive:
    let pbX = centiX + centiSlotW + 8
    let pbY = timerY + 4
    let pbH = timerSize - 8
    drawRectangle(pbX, pbY, 4, pbH, accent)
    drawRectangle(pbX + 7, pbY, 4, pbH, accent)

  # --- Divider between the clock and the phase row ------------------------
  let divY = (timerY + timerSize + vGap div 2).float32
  drawLine(Vector2(x: (panelX + padX).float32, y: divY),
           Vector2(x: (panelX + panelW - padX).float32, y: divY),
           1.0'f32, withAlpha(accent, 55))

  # --- Row 2: phase chip + name, countdown to the next boss ---------------
  let phaseY = timerY + timerSize + vGap
  let rowX = panelX + padX
  drawRectangle(rowX, phaseY + 3, 8, 8, phaseColor)
  drawText(phaseName, rowX + 12 + 1, phaseY + 1, phaseSize, inkShadow)
  drawText(phaseName, rowX + 12, phaseY, phaseSize, phaseColor)
  let cdW = measureText(countdown.text, phaseSize)
  let pulse = sin(game.time * 8.0'f32) * 0.5'f32 + 0.5'f32
  let cdColor = if countdown.urgent: Color(r: 255, g: uint8(80.0'f32 + pulse * 90.0'f32), b: 80, a: 255)
                else: Color(r: 190, g: 210, b: 225, a: 255)
  drawText(countdown.text, panelX + panelW - padX - cdW, phaseY, phaseSize, cdColor)

  # --- Row 3: level label + XP bar ----------------------------------------
  let overclock = game.survival.event.kind == sekOverclock
  let barRowX = panelX + (panelW - barRowW) div 2
  let barY = phaseY + phaseRowH + rowGap
  let lblY = barY + (barH - lblSize) div 2
  drawText(lvlLabel, barRowX + 1, lblY + 1, lblSize, inkShadow)
  drawText(lvlLabel, barRowX, lblY, lblSize,
           if overclock: xpGold else: Color(r: 150, g: 255, b: 210, a: 255))
  let barX = barRowX + lblW + lblGap
  drawRectangle(barX, barY, barW, barH, Color(r: 10, g: 30, b: 25, a: 200))
  let ratio = clamp(game.player.xp.float32 /
                    max(1, game.player.xpToNextLevel).float32, 0.0, 1.0)
  let fillW = int32(barW.float32 * ratio)
  if fillW > 0:
    drawRectangle(barX, barY, fillW, barH, if overclock: xpGold else: xpFill)
  drawRectangleLines(barX, barY, barW, barH,
                     if overclock: xpGold else: Color(r: 120, g: 220, b: 190, a: 170))

  # --- Event card ------------------------------------------------------------
  if survivalEventActive(game):
    drawSurvivalTracker(game, panelX, panelY + panelH + SurvivalTrackerGap, panelW)

proc drawRunTimeline(game: Game, x, y, w: int32, dim: bool) =
  ## The 20:00 run as four phase segments, each filling as its five minutes
  ## pass, with a boss notch closing every segment. Overtime has no end, so it
  ## becomes one segment filling toward the next Overtime boss.
  const h = 7'i32
  let pulse = 0.5'f32 + 0.5'f32 * sin(game.time * 5.0'f32)
  let st = max(0.0'f32, game.survivalTime)
  if survivalPhase(game) == spOvertime:
    let color = SurvivalPhaseAccent[spOvertime]
    let prev = survivalBossTime(max(SurvivalFinalBoss, game.bossCount))
    let next = survivalBossTime(max(SurvivalFinalBoss, game.bossCount) + 1)
    let frac = clamp((st - prev) / max(1.0'f32, next - prev), 0.0'f32, 1.0'f32)
    drawDockBar(x, y, w, h, frac, withAlpha(color, if dim: 110 else: 220), withAlpha(color, 140))
    return
  const segs = SurvivalFinalBoss
  const gap = 3'i32
  let segW = (w - gap * (segs - 1)) div segs
  for i in 0..<segs:
    let color = SurvivalPhaseAccent[SurvivalPhase(i)]
    let sx = x + i.int32 * (segW + gap)
    let start = i.float32 * SurvivalPhaseLength
    let frac = clamp((st - start) / SurvivalPhaseLength, 0.0'f32, 1.0'f32)
    drawRectangle(sx, y, segW, h, DockTrackBg)
    let fw = int32(segW.float32 * frac)
    if fw > 0:
      drawRectangle(sx, y, fw, h, withAlpha(color, if dim: 110 else: 215))
    drawRectangleLines(Rectangle(x: sx.float32, y: y.float32, width: segW.float32,
                                 height: h.float32), 1, withAlpha(color, 130))
    # Boss notch at the segment's end; lit once that boss is down.
    let beaten = game.bossCount - (if game.bossWaveManager.active: 1 else: 0) > i
    let live = not beaten and frac >= 1.0'f32
    let notch = if beaten: withAlpha(color, 255)
                elif live: Color(r: 255, g: 255, b: 255, a: uint8(140.0'f32 + 115.0'f32 * pulse))
                else: withAlpha(color, 110)
    drawRectangle(sx + segW - 2, y - 2, 2, h + 4, notch)

proc drawSurvivalDockCard*(game: Game, x, y: int32, withLevel: bool = false): int32 =
  ## Widescreen survival HUD, docked at the top of the right band: the phase,
  ## the stopwatch, the countdown to the next boss and the run timeline, sized
  ## to the band. The modern HUD shows the run level and XP bar in its left
  ## dock; the legacy one has nowhere else for them, so it passes `withLevel`
  ## to add that row here. A running System Event docks its own card
  ## underneath. Returns the y below the stack.
  let bossActive = game.bossWaveManager.active or game.bossWaveManager.coinActive
  let phase = survivalPhase(game)
  let phaseColor = SurvivalPhaseAccent[phase]
  let accent = if bossActive: Color(r: 120, g: 140, b: 150, a: 255) else: phaseColor
  let digitColor = if bossActive: Color(r: 150, g: 165, b: 175, a: 255)
                   else: Color(r: 225, g: 246, b: 255, a: 255)
  const levelRowH = 14'i32
  let h = DockHeaderH + 6 + 30 + 5 + 13 + 7 + 7 + (if withLevel: levelRowH else: 0'i32)
  drawDockCard(x, y, DockCardW, h, phaseColor)

  # Header: phase chip + name, "n/4" through the campaign.
  let right = if phase == spOvertime: "" else: $(ord(phase) + 1) & "/" & $SurvivalFinalBoss
  let phaseName = t(survivalPhaseNameKey(phase))
  let top = drawDockHeader(x, y, DockCardW, "", phaseColor, right, DockInk)
  drawRectangle(x + DockPad, y + 4, 7, 7, phaseColor)
  let nameW = DockContentW - 12 - measureText(right, 10) - 6
  drawShadowText(phaseName, x + DockPad + 12, y + 3, bestFitFontSize(phaseName, nameW, 10, 7),
                 phaseColor)

  let cx = x + DockPad
  let cw = DockContentW
  var cy = top + 6

  # Stopwatch: MM:SS against a fixed "00:00" slot, .CC against ".00", so the
  # card never jitters as the proportional digits change. While a boss holds
  # the clock the icon becomes a pause glyph.
  const timerSize = 30'i32
  const centiSize = 20'i32
  const iconBox = 24'i32
  let clampedT = max(0.0'f32, game.survivalTime)
  let (timeStr, centiStr) = stopwatchReadout(clampedT)
  let slotW = measureText("00:00", timerSize)
  let centiW = measureText(".00", centiSize)
  let rowW = iconBox + slotW + 2 + centiW
  let rowX = cx + max(0'i32, (cw - rowW) div 2)
  if bossActive:
    drawRectangle(rowX + 4, cy + 7, 5, 16, accent)
    drawRectangle(rowX + 12, cy + 7, 5, 16, accent)
  else:
    drawStopwatchIcon((rowX + 9).float32, (cy + 16).float32, 9.0'f32, clampedT, accent, digitColor)
  let digitsX = rowX + iconBox + (slotW - measureText(timeStr, timerSize)) div 2
  if not bossActive:
    drawText(timeStr, digitsX, cy - 1, timerSize, withAlpha(accent, 55))
  drawShadowText(timeStr, digitsX, cy, timerSize, digitColor)
  drawShadowText(centiStr, rowX + iconBox + slotW + 2, cy + timerSize - centiSize, centiSize,
                 withAlpha(digitColor, 175))
  cy += timerSize + 5

  # Countdown to the next boss (or BOSS ACTIVE).
  let countdown = survivalCountdownLabel(game)
  let pulse = sin(game.time * 8.0'f32) * 0.5'f32 + 0.5'f32
  let cdColor = if countdown.urgent: Color(r: 255, g: uint8(80.0'f32 + pulse * 90.0'f32), b: 80, a: 255)
                else: Color(r: 190, g: 210, b: 225, a: 255)
  let cdSize = bestFitFontSize(countdown.text, cw, 10, 7)
  drawShadowText(countdown.text, cx + (cw - measureText(countdown.text, cdSize)) div 2, cy,
                 cdSize, cdColor)
  cy += 13

  drawRunTimeline(game, cx, cy + 2, cw, bossActive)
  if withLevel:
    let lvY = cy + 16
    let overclock = game.survival.event.kind == sekOverclock
    let gold = Color(r: 255, g: 215, b: 60, a: 245)
    let label = t("roguelite_level") & " " & $game.player.rogueliteLevel
    drawShadowText(label, cx, lvY, 10,
                   if overclock: gold else: Color(r: 150, g: 255, b: 210, a: 255))
    let barX = cx + measureText(label, 10) + 7
    drawDockBar(barX, lvY + 2, cx + cw - barX, 6,
                game.player.xp.float32 / max(1, game.player.xpToNextLevel).float32,
                if overclock: gold else: Color(r: 90, g: 255, b: 170, a: 235),
                Color(r: 120, g: 220, b: 190, a: 150))
  result = y + h
  if survivalEventActive(game):
    result = drawSurvivalTrackerDock(game, x, result + DockGap)

proc survivalBannerContent(game: Game): tuple[title, subtitle: string, accent: Color, duration: float32] =
  let s = game.survival
  case s.bannerKind
  of sbkNone:
    ("", "", Color(), 0.0'f32)
  of sbkPhase:
    let ph = survivalPhase(game)
    (t(tkSurvivalPhaseBanner).replace("$1", $(ord(ph) + 1)) & "  //  " & t(survivalPhaseNameKey(ph)),
     t(survivalPhaseDescKey(ph)), SurvivalPhaseAccent[ph], 3.2'f32)
  of sbkEventStart:
    (t(survivalEventNameKey(s.bannerEvent)), t(survivalEventHintKey(s.bannerEvent)),
     survivalEventColor(s.bannerEvent), 3.0'f32)
  of sbkEventCleared:
    (t(survivalEventNameKey(s.bannerEvent)) & "  //  " & t(tkSurvivalEventCleared), "",
     Color(r: 90, g: 255, b: 150, a: 255), 2.2'f32)
  of sbkEventFailed:
    let title = if s.bannerEvent == sekRogueProcess: t(tkSurvivalRogueEscaped)
                else: t(survivalEventNameKey(s.bannerEvent)) & "  //  " & t(tkSurvivalEventFailed)
    (title, "", Color(r: 255, g: 90, b: 90, a: 255), 2.2'f32)
  of sbkBossInbound:
    (t(tkSurvivalBossInbound), t(tkSurvivalBossInboundSub),
     Color(r: 255, g: 140, b: 40, a: 255), 3.0'f32)
  of sbkFinalInbound:
    (t(tkSurvivalFinalInbound), t(tkSurvivalBossInboundSub),
     Color(r: 255, g: 60, b: 60, a: 255), 3.5'f32)

proc drawSurvivalBanner*(game: Game, screenWidth, topY: int32) =
  ## Classic layout: the latest announcement, centred under the HUD stack.
  let c = survivalBannerContent(game)
  if c.title.len == 0:
    return
  drawLabelBanner(c.title, c.subtitle, game.time - game.survival.bannerStart,
                  screenWidth, topY, c.accent, c.duration)

proc drawSurvivalBannerGutter*(game: Game, gutterX, gutterW, topY: int32): int32 =
  ## Widescreen layout: the same announcement as a right-gutter card.
  let c = survivalBannerContent(game)
  if c.title.len == 0:
    return topY
  drawLabelBannerGutter(c.title, c.subtitle, game.time - game.survival.bannerStart,
                        gutterX, gutterW, topY, c.accent, c.duration)
