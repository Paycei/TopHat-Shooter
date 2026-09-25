## Signature attacks of the Survival bosses (13-15), the Roguelite guardians
## (17-22) and the two Omega kits (16 / 23). executeCustomBossAttack
## (game/bosses.nim) routes every specialData listed in isModeBossAttack here
## before its attackType dispatch.
##
## Each attack either acts at once (rings, summons, the haste pulse) or lays
## AttackWarnings (awtEnemyDashLane..awtLastKnownGood) that
## game/mode_mechanics.nim resolves frame by frame and mode_visuals.nim draws.
## `attack.damage` arrives already scaled by the boss's damageTuning; the
## phase multiplier is applied here. How each attack reads the BossAttack
## fields is written next to its definition in boss_definitions_modes.nim.

import raylib, math, random, strutils, algorithm
import particle_types, types, enemy, bullet, boss_types, particle_pool, d_systems,
       mode_hazards, dungeon

const ModeBossAttacks* = [
  "fork_children", "exponential_fork", "exponential_fork_twin", "fork_ring",
  "payload_ring", "marching_orders", "priority_boost", "heat_trail",
  "thermal_vents", "safe_mode", "stateful_inspection", "port_guards",
  "empty_trash", "undelete", "audit_lock", "packet_switching", "page_fault",
  "stale_copy", "last_known_good"]

proc isModeBossAttack*(specialData: string): bool =
  specialData in ModeBossAttacks

proc arenaClamp(game: Game, p: Vector2f, pad: float32): Vector2f =
  newVector2f(clamp(p.x, pad, game.screenWidth.float32 - pad),
              clamp(p.y, pad, game.screenHeight.float32 - pad))

proc beginMegaCast(enemy: Enemy, total: float32) =
  ## Channel: frozen, hardened (MegaCastDamageTaken), every other attack
  ## countdown paused (the boss attack loop breaks while this runs).
  enemy.megaCastTimer = total
  enemy.megaCastTotal = total
  enemy.vel = newVector2f(0, 0)
  enemy.isDashing = false

proc livingGuards(game: Game): int =
  for e in game.enemies:
    if e.royalGuard and e.spawnedByBoss and e.hp > 0:
      inc result

proc minion(game: var Game, boss: Enemy, pos: Vector2f, et: EnemyType): Enemy =
  ## A boss-spawned roster unit: no loot, engages at once. Its stats follow
  ## the live difficulty like any enemy; units that ARE the attack (seeds,
  ## orbs, ranks) take the attack's (slot-tuned) damage instead.
  result = newEnemy(pos.x, pos.y, max(0.0'f32, game.difficulty), et, game)
  result.spawnedByBoss = true
  result.hasEnteredScreen = true

proc bossShot(game: var Game, boss: Enemy, pos, dir: Vector2f, speed, damage: float32) =
  game.bullets.add(newBullet(
    x = pos.x, y = pos.y, direction = dir, speed = speed, damage = damage,
    fromPlayer = false, isBossBullet = true, sourceEnemyId = boss.id,
    bossBulletShape = bossBulletShapeFor(boss.bossDefinitionID)))

# ---------------------------------------------------------------------------
# Survival

proc forkChildren(game: var Game, boss: Enemy, attack: BossAttack, dmg: float32) =
  ## The Forkmother's children: Fork Bombs raised into the crowd, each a
  ## Royal-Guard style link of her seal (the adds gate) and her objective.
  let count = max(1, attack.projectileCount)
  let ring = max(60.0'f32, attack.durationOrRadius)
  let spin = rand(PI * 2.0).float32
  for i in 0..<count:
    let a = spin + i.float32 * PI * 2.0'f32 / count.float32
    let pos = arenaClamp(game, boss.pos + newVector2f(cos(a), sin(a)) * (boss.radius + ring), 30.0'f32)
    let child = minion(game, boss, pos, etForkBomb)
    child.royalGuard = true
    child.linkId = boss.id
    # Tough enough to be a target, not a wall: a few hits of the player's gun.
    child.maxHp = max(child.maxHp * 3.0'f32, game.player.damage * 5.0'f32)
    child.hp = child.maxHp
    child.radius *= 1.25'f32
    child.collisionRadius = child.radius * 0.4'f32
    child.contactDamage = max(child.contactDamage, dmg * 0.5'f32)
    game.enemies.add(child)
    spawnExplosionPooled(game.particlePool, pos.x, pos.y, Color(r: 255, g: 110, b: 190, a: 255), 12)
  if boss.weakPoint.kind == bwoSummonSigils:
    boss.summonWaveActive = true
    boss.weakPoint.required = max(1, livingGuards(game))
    boss.weakPoint.progress = 0

proc exponentialFork(game: var Game, boss: Enemy, attack: BossAttack, dmg: float32, twin: bool) =
  ## Seeds that double on every beat along a pre-drawn binary tree. Each seed
  ## is a real, one-shot enemy: shoot one before it splits and its whole
  ## subtree never exists. The leaves hatch into Threads.
  let toP = game.player.pos - boss.pos
  let aim = arctan2(toP.y, toP.x)
  let speed = max(60.0'f32, attack.projectileSpeed)
  let branch = attack.spreadAngle * PI / 180.0'f32
  let beat = max(0.3'f32, attack.durationOrRadius)
  let depth = max(1, attack.projectileCount)
  let roots = if twin: @[aim - 0.5'f32, aim + 0.5'f32] else: @[aim]
  var tree = newAttackWarning(boss.pos.x, boss.pos.y, awtForkTree,
                              beat * depth.float32 + beat * 1.4'f32, boss.id)
  proc grow(path: var seq[Vector2f], p: Vector2f, heading: float32, level: int) =
    let q = p + newVector2f(cos(heading), sin(heading)) * (speed * 1.25'f32 * beat)
    path.add(p)
    path.add(q)
    if level > 0:
      grow(path, q, heading - branch, level - 1)
      grow(path, q, heading + branch, level - 1)
  for r in roots:
    grow(tree.ricochetPath, boss.pos, r, depth)
    let seed = minion(game, boss, boss.pos, etThread)
    seed.maxHp = max(0.3'f32, game.player.damage * 0.9'f32)
    seed.hp = seed.maxHp
    seed.radius = ForkTreeSeedRadius
    seed.collisionRadius = seed.radius * 0.4'f32
    seed.contactDamage = dmg
    seed.color = boss.color
    seed.linkId = boss.id
    seed.ballisticVel = newVector2f(cos(r), sin(r)) * speed
    seed.generation = depth
    seed.modeTimer = beat
    seed.targetPos = newVector2f(branch, beat)   # carried to every child split
    game.enemies.add(seed)
  game.attackWarnings.add(tree)

proc forkRing(game: var Game, boss: Enemy, attack: BossAttack, dmg: float32) =
  ## A ring that reads as forking: the second ring leaves on the half-step,
  ## slower, so it peels away from the first.
  let n = max(4, attack.projectileCount)
  let speed = attack.projectileSpeed
  let offset = rand(PI * 2.0).float32
  for k in 0..<n:
    let a0 = offset + k.float32 * PI * 2.0'f32 / n.float32
    let a1 = a0 + PI / n.float32
    bossShot(game, boss, boss.pos, newVector2f(cos(a0), sin(a0)), speed, dmg)
    bossShot(game, boss, boss.pos, newVector2f(cos(a1), sin(a1)), speed * 0.72'f32, dmg)

proc payloadRing(game: var Game, boss: Enemy, attack: BossAttack, dmg: float32) =
  ## Slow orbs that hatch into Threads wherever they stop: the flood grows.
  let n = max(3, attack.projectileCount)
  let offset = rand(PI * 2.0).float32
  for k in 0..<n:
    let a = offset + k.float32 * PI * 2.0'f32 / n.float32
    let orb = minion(game, boss, boss.pos, etThread)
    orb.maxHp = max(0.3'f32, game.player.damage * 0.9'f32)
    orb.hp = orb.maxHp
    orb.radius = ForkTreeSeedRadius
    orb.collisionRadius = orb.radius * 0.4'f32
    orb.contactDamage = dmg * 0.5'f32
    orb.color = Color(r: 255, g: 60, b: 200, a: 255)
    orb.ballisticVel = newVector2f(cos(a), sin(a)) * (attack.projectileSpeed * 0.6'f32)
    orb.generation = 0
    orb.modeTimer = 1.1'f32
    orb.rotation = rand(-60.0'f32..60.0'f32)
    game.enemies.add(orb)

proc marchingOrders(game: var Game, boss: Enemy, attack: BossAttack, dmg: float32) =
  ## Ranks of real, low-HP bodies march across the arena as a wall, one after
  ## another from rotating sides. Two staggered rows: shoot your own gap.
  let w = game.screenWidth.float32
  let h = game.screenHeight.float32
  let ranks = max(1, attack.projectileCount)
  let bodies = max(4, int(attack.durationOrRadius))
  var side = rand(3)
  for r in 0..<ranks:
    var start, dir: Vector2f
    var halfSpan: float32
    let s = side mod 4
    if s == 0:
      start = newVector2f(-30, h / 2); dir = newVector2f(1, 0); halfSpan = h / 2 - 20
    elif s == 1:
      start = newVector2f(w / 2, -30); dir = newVector2f(0, 1); halfSpan = w / 2 - 20
    elif s == 2:
      start = newVector2f(w + 30, h / 2); dir = newVector2f(-1, 0); halfSpan = h / 2 - 20
    else:
      start = newVector2f(w / 2, h + 30); dir = newVector2f(0, -1); halfSpan = w / 2 - 20
    let lane = newAttackWarning(start.x, start.y, awtMarchLane,
                                MarchLaneTelegraph + r.float32 * MarchRankStagger, boss.id)
    lane.targetPos = start + dir * 100.0'f32
    lane.laserLength = halfSpan
    lane.bulletCount = bodies
    lane.bulletSpeed = max(40.0'f32, attack.projectileSpeed)
    lane.bulletDamage = dmg
    lane.bulletRadius = max(0.5'f32, game.player.damage * 1.5'f32)   # body HP: two shots
    game.attackWarnings.add(lane)
    side += 1 + rand(1)

proc priorityBoost(game: var Game, boss: Enemy, attack: BossAttack) =
  let radius = max(120.0'f32, attack.durationOrRadius)
  let amount = if attack.spreadAngle > 0: attack.spreadAngle else: 0.35'f32
  for e in game.enemies:
    if e.isBoss or e.hp <= 0: continue
    if distance(e.pos, boss.pos) <= radius:
      e.hasteAmount = max(e.hasteAmount, amount)
      e.hasteTimer = max(e.hasteTimer, PriorityBoostTime)
  spawnShockwavePooled(game.particlePool, boss.pos.x, boss.pos.y, radius)
  spawnExplosionPooled(game.particlePool, boss.pos.x, boss.pos.y, Color(r: 210, g: 110, b: 255, a: 255), 20)
  addShake(game.dopamine.screenShake, siSmall)

proc heatTrail(game: var Game, boss: Enemy, attack: BossAttack, dmg: float32) =
  var em = newAttackWarning(game.player.pos.x, game.player.pos.y, awtHeatEmitter,
                            max(1.0'f32, attack.durationOrRadius), boss.id)
  em.bulletRadius = if attack.bulletRadius > 0: attack.bulletRadius else: 16.0'f32
  em.bulletDamage = dmg
  em.targetPos = newVector2f(-9999, -9999)
  game.attackWarnings.add(em)
  spawnExplosionPooled(game.particlePool, game.player.pos.x, game.player.pos.y,
                       Color(r: 255, g: 120, b: 30, a: 255), 14)

proc thermalVents(game: var Game, boss: Enemy, attack: BossAttack, dmg: float32) =
  ## Vents erupt under the densest crowds: the horde marks the danger.
  let cols = max(1, int(game.screenWidth.float32 / ThermalVentCell) + 1)
  let rows = max(1, int(game.screenHeight.float32 / ThermalVentCell) + 1)
  var counts = newSeq[int](cols * rows)
  var sumX = newSeq[float32](cols * rows)
  var sumY = newSeq[float32](cols * rows)
  for e in game.enemies:
    if e.isBoss or e.hp <= 0: continue
    let cx = int(e.pos.x / ThermalVentCell)
    let cy = int(e.pos.y / ThermalVentCell)
    if cx < 0 or cy < 0 or cx >= cols or cy >= rows: continue
    let k = cy * cols + cx
    inc counts[k]
    sumX[k] += e.pos.x
    sumY[k] += e.pos.y
  let n = max(1, attack.projectileCount)
  var spots: seq[Vector2f] = @[]
  for _ in 0..<n:
    var best = -1
    for k in 0..<counts.len:
      if counts[k] >= 3 and (best < 0 or counts[k] > counts[best]):
        best = k
    if best < 0: break
    spots.add(newVector2f(sumX[best] / counts[best].float32, sumY[best] / counts[best].float32))
    counts[best] = 0
  # Too few crowds (a thin horde, the sandbox): vent around the player instead.
  while spots.len < n:
    let a = rand(PI * 2.0).float32
    spots.add(arenaClamp(game, game.player.pos + newVector2f(cos(a), sin(a)) * rand(40.0'f32..130.0'f32), 30.0'f32))
  for p in spots:
    var v = newAttackWarning(p.x, p.y, awtThermalVent, ThermalVentTelegraph + ThermalVentActive, boss.id)
    v.bulletRadius = max(40.0'f32, attack.durationOrRadius)
    v.bulletDamage = dmg
    game.attackWarnings.add(v)

proc safeMode(game: var Game, boss: Enemy, attack: BossAttack, dmg: float32) =
  ## The flood takes everything but a drifting Safe Mode bubble. A mega-cast:
  ## the Omega Entity channels it, frozen.
  let castLen = max(3.0'f32, attack.durationOrRadius)
  let total = SafeModeTelegraph + castLen
  let start = arenaClamp(game, game.player.pos, SafeModeStartRadius * 0.6'f32)
  let a = rand(PI * 2.0).float32
  let drift = min(max(40.0'f32, attack.projectileSpeed) * castLen, 320.0'f32)
  let finish = arenaClamp(game, start + newVector2f(cos(a), sin(a)) * drift, SafeModeEndRadius + 10.0'f32)
  var w = newAttackWarning(start.x, start.y, awtSafeMode, total, boss.id)
  w.targetPos = finish
  w.bulletDamage = dmg
  game.attackWarnings.add(w)
  beginMegaCast(boss, total)
  addShake(game.dopamine.screenShake, siLarge)

# ---------------------------------------------------------------------------
# Roguelite

proc statefulInspection(game: var Game, boss: Enemy, attack: BossAttack, dmg: float32) =
  ## Rotating searchlights from the boss, stopped by the room's obstacles.
  let beams = max(1, attack.projectileCount)
  let toP = game.player.pos - boss.pos
  let playerBearing = arctan2(toP.y, toP.x)
  let dir = if rand(1) == 0: 1.0'f32 else: -1.0'f32
  var w = newAttackWarning(boss.pos.x, boss.pos.y, awtSearchlight,
                           SearchlightTelegraph + max(1.0'f32, attack.durationOrRadius), boss.id)
  # The first beam starts a quarter turn behind the player's bearing and
  # sweeps toward them.
  let first = playerBearing - dir * (PI / 2.0'f32)
  for b in 0..<beams:
    w.laserAngles.add(first + b.float32 * PI * 2.0'f32 / beams.float32)
  w.bulletSpeed = dir * max(0.2'f32, attack.projectileSpeed)
  w.bulletDamage = dmg
  game.attackWarnings.add(w)

proc portGuards(game: var Game, boss: Enemy, attack: BossAttack) =
  let count = max(1, attack.projectileCount)
  for i in 0..<count:
    let a = rand(PI * 2.0).float32
    let pos = arenaClamp(game, boss.pos + newVector2f(cos(a), sin(a)) * (boss.radius + 50.0'f32), 30.0'f32)
    let g = minion(game, boss, pos, etPortGuard)
    g.rotation = arctan2(game.player.pos.y - pos.y, game.player.pos.x - pos.x)
    game.enemies.add(g)
    spawnExplosionPooled(game.particlePool, pos.x, pos.y, Color(r: 255, g: 150, b: 80, a: 255), 10)

proc emptyTrash(game: var Game, boss: Enemy, attack: BossAttack, dmg: float32) =
  ## Dormant file bombs strewn across the room; the ones left standing all
  ## burst together at the purge. Walk over or shoot them to shred them first.
  let count = max(1, attack.projectileCount)
  let fuse = max(1.5'f32, attack.durationOrRadius)
  var placed: seq[Vector2f] = @[]
  # One bomb lands at the player's feet: tidy it up or eat the purge.
  block:
    let a = rand(PI * 2.0).float32
    let near = arenaClamp(game, game.player.pos + newVector2f(cos(a), sin(a)) * 48.0'f32, 70.0'f32)
    if distance(near, boss.pos) > boss.radius + 30.0'f32:
      placed.add(near)
  var attempts = 0
  while placed.len < count and attempts < 80:
    inc attempts
    let p = newVector2f(rand(70.0'f32..(game.screenWidth.float32 - 70.0'f32)),
                        rand(70.0'f32..(game.screenHeight.float32 - 70.0'f32)))
    if distance(p, game.player.pos) < 140.0'f32: continue
    if distance(p, boss.pos) < boss.radius + 30.0'f32: continue
    var ok = true
    for q in placed:
      if distance(p, q) < FileBombBlastRadius * 1.3'f32:
        ok = false
        break
    if ok:
      for wall in game.walls:
        if wall.hp > 0 and wallOverlapsCircle(wall, p, 18.0'f32):
          ok = false
          break
    if ok: placed.add(p)
  for p in placed:
    var b = newAttackWarning(p.x, p.y, awtFileBomb, fuse + FileBombPurgeFlash, boss.id)
    b.bulletDamage = dmg
    b.bulletSpeed = max(80.0'f32, attack.projectileSpeed)
    game.attackWarnings.add(b)
    spawnExplosionPooled(game.particlePool, p.x, p.y, Color(r: 200, g: 230, b: 190, a: 255), 6)

proc undelete(game: var Game, boss: Enemy, attack: BossAttack) =
  ## A restore point: unless the player takes a share of the phase pool off
  ## in time, the boss rolls back to it.
  for w in game.attackWarnings:
    if w.attackType == awtRestorePoint and w.sourceEnemyId == boss.id and w.lifetime > 0:
      return
  var w = newAttackWarning(boss.pos.x, boss.pos.y, awtRestorePoint,
                           max(2.0'f32, attack.durationOrRadius), boss.id)
  w.bulletDamage = boss.hp
  w.bulletSpreadAngle = max(0.05'f32, attack.spreadAngle) * boss.maxHp
  w.bulletCount = boss.currentPhaseIndex
  w.bulletRadius = boss.radius
  game.attackWarnings.add(w)

proc auditLock(game: var Game, boss: Enemy, attack: BossAttack, dmg: float32) =
  ## The room locks: enemies, their shots and every other hazard freeze, and
  ## so must the player. A mega-cast (the Hive audits, it does nothing else).
  let total = AuditTelegraph + max(0.5'f32, attack.durationOrRadius)
  var w = newAttackWarning(game.player.pos.x, game.player.pos.y, awtAuditLock, total, boss.id)
  w.bulletDamage = dmg
  w.targetPos = game.player.pos
  game.attackWarnings.add(w)
  beginMegaCast(boss, total)

proc packetSwitching(game: var Game, boss: Enemy, attack: BossAttack, dmg: float32) =
  ## Lit links cross the room as traffic lanes; each carries two trains of
  ## real packets, one after the other. One lane always runs through the
  ## player: step off it, then cross between trains.
  let w = game.screenWidth.float32
  let h = game.screenHeight.float32
  let links = max(1, attack.projectileCount)
  let horizontal = rand(1) == 0
  let span = if horizontal: h else: w
  let playerCoord = if horizontal: game.player.pos.y else: game.player.pos.x
  let speed = max(120.0'f32, attack.projectileSpeed)
  let telegraph = max(0.5'f32, attack.durationOrRadius)
  let playerLane = rand(links - 1)
  for k in 0..<links:
    var c = (k.float32 + 0.5'f32 + rand(-0.25'f32..0.25'f32)) * span / links.float32
    if k == playerLane:
      c = playerCoord
    c = clamp(c, 30.0'f32, span - 30.0'f32)
    let forward = k mod 2 == 0
    var a, b: Vector2f
    if horizontal:
      a = newVector2f(if forward: 0.0'f32 else: w, c)
      b = newVector2f(if forward: w else: 0.0'f32, c)
    else:
      a = newVector2f(c, if forward: 0.0'f32 else: h)
      b = newVector2f(c, if forward: h else: 0.0'f32)
    let len = distance(a, b)
    let trainSpeed = speed * 1.25'f32   # enemy-bullet pace
    let travel = (len + PacketCars.float32 * PacketCarSpacing) / trainSpeed
    for train in 0..1:
      let lead = telegraph + k.float32 * PacketLinkStagger + train.float32 * (travel * 0.55'f32 + 0.4'f32)
      var link = newAttackWarning(a.x, a.y, awtPacketLink, lead + travel + 0.2'f32, boss.id)
      link.targetPos = b
      link.laserDuration = lead
      link.bulletSpeed = trainSpeed
      link.bulletDamage = dmg
      game.attackWarnings.add(link)

proc pageFault(game: var Game, boss: Enemy, attack: BossAttack, dmg: float32) =
  ## Obstacles page out, then page back in at new spots (one right where the
  ## player is heading). A ghost footprint marks each landing.
  let count = max(1, attack.projectileCount)
  let telegraph = max(0.6'f32, attack.durationOrRadius)
  # Page out: the obstacles farthest from the player go first.
  var outCount = 0
  while outCount < count:
    var far = -1
    var farD = -1.0'f32
    for i, wall in game.walls:
      if not wall.permanent or wall.hp <= 0: continue
      let d = distance(wall.pos, game.player.pos)
      if d > farD:
        farD = d
        far = i
    if far < 0: break
    let gone = game.walls[far]
    spawnExplosionPooled(game.particlePool, gone.pos.x, gone.pos.y, Color(r: 200, g: 160, b: 255, a: 255), 14)
    game.walls.delete(far)
    inc outCount
  # Page in.
  var wallsNow = 0
  for wall in game.walls:
    if wall.permanent: inc wallsNow
  let room = max(0, PageFaultMaxWalls - wallsNow)
  # One footprint where the player stands, one where they will be when it
  # lands: standing still and running on autopilot both get crushed.
  var targets: seq[Vector2f] = @[]
  for p in [game.player.pos, game.player.pos + game.player.vel * telegraph]:
    let q = arenaClamp(game, p, 60.0'f32)
    var clear = distance(q, boss.pos) > boss.radius + 70.0'f32
    for t in targets:
      if distance(q, t) < 90.0'f32: clear = false
    if clear and targets.len < min(count, room):
      targets.add(q)
  var attempts = 0
  while targets.len < min(count, room) and attempts < 60:
    inc attempts
    let p = newVector2f(rand(90.0'f32..(game.screenWidth.float32 - 90.0'f32)),
                        rand(90.0'f32..(game.screenHeight.float32 - 90.0'f32)))
    if distance(p, boss.pos) < boss.radius + 80.0'f32: continue
    var ok = true
    for q in targets:
      if distance(p, q) < 90.0'f32:
        ok = false
        break
    if ok:
      for wall in game.walls:
        if distance(p, wall.pos) < wall.radius + PageFaultRadiusMax + 20.0'f32:
          ok = false
          break
    if ok: targets.add(p)
  for p in targets:
    var f = newAttackWarning(p.x, p.y, awtPageFault, telegraph + PageFaultActive, boss.id)
    f.bulletRadius = rand(PageFaultRadiusMin..PageFaultRadiusMax)
    f.bulletDamage = dmg
    game.attackWarnings.add(f)

proc staleCopy(game: var Game, boss: Enemy, attack: BossAttack, dmg: float32) =
  ## Echoes that replay the player's own movement and shots, `delay` behind.
  let echoes = max(1, attack.projectileCount)
  let delay = max(0.8'f32, attack.spreadAngle)
  for k in 0..<echoes:
    let d = delay * (1.0'f32 - k.float32 / (echoes.float32 + 1.0'f32) * 1.0'f32)
    var w = newAttackWarning(boss.pos.x, boss.pos.y, awtStaleCopy,
                             d + max(2.0'f32, attack.durationOrRadius), boss.id)
    w.laserDuration = d
    w.bulletDamage = dmg
    w.targetPos = game.player.pos
    w.laserAngles = @[0.0'f32]
    game.attackWarnings.add(w)

proc glitchPath(path: string): string =
  ## A decoy door's label: the same kind of path, visibly corrupted.
  const junk = "#?%&@!~"
  result = path
  for i in 3..<result.len:
    if rand(99) < 45:
      result[i] = junk[rand(junk.len - 1)]

proc lastKnownGood(game: var Game, boss: Enemy, attack: BossAttack, dmg: float32) =
  ## Four doors light up at the room's four exits; only the one labelled with
  ## a folder this run really walked is safe. A purge ring sweeps out from the
  ## centre. A mega-cast: the Omega Entity channels the judgement.
  let w = game.screenWidth.float32
  let h = game.screenHeight.float32
  let run = game.rogueliteRun
  var themes: seq[string] = @[]
  var folders: seq[string] = @[]
  if not run.isNil:
    for th in run.usedThemes:
      if th != FinalFloorTheme:
        themes.add(themeFolder(th))
    if not run.floor.isNil:
      for room in run.floor.rooms:
        let f = rewardFolderName(room.reward)
        if f.len > 1:
          folders.add(f[1 .. ^1])
  if themes.len == 0: themes = @["SYSTEM"]
  if folders.len == 0: folders = @["restore"]
  let real = "C:\\" & themes[rand(themes.len - 1)] & "\\" & folders[rand(folders.len - 1)]
  # The true door is one of the two nearest: the test is reading the labels
  # under pressure, not an out-run of the purge across the whole room.
  var byDist: seq[tuple[d: float32, door: int]] = @[]
  for door in 0..3:
    let r = lkgDoorRect(door, w, h)
    byDist.add((distance(game.player.pos, newVector2f(r.x + r.w / 2, r.y + r.h / 2)), door))
  byDist.sort(proc (x, y: tuple[d: float32, door: int]): int = cmp(x.d, y.d))
  let realDoor = byDist[rand(1)].door
  var labels: seq[string] = @[]
  for door in 0..3:
    labels.add(if door == realDoor: real else: glitchPath(real))
  let total = LkgReveal + max(1.5'f32, attack.durationOrRadius) + LkgActive
  var lkg = newAttackWarning(w / 2, h / 2, awtLastKnownGood, total, boss.id)
  lkg.bulletCount = realDoor
  lkg.laserPattern = labels.join("|")
  lkg.laserLength = sqrt(w * w + h * h) / 2.0'f32
  lkg.bulletDamage = dmg
  game.attackWarnings.add(lkg)
  beginMegaCast(boss, total)
  addShake(game.dopamine.screenShake, siLarge)

# ---------------------------------------------------------------------------

proc executeModeBossAttack*(game: var Game, boss: Enemy, attack: BossAttack,
                            phase: BossPhaseDefinition) =
  let dmg = attack.damage * phase.damageMultiplier
  case attack.specialData
  of "fork_children": forkChildren(game, boss, attack, dmg)
  of "exponential_fork": exponentialFork(game, boss, attack, dmg, false)
  of "exponential_fork_twin": exponentialFork(game, boss, attack, dmg, true)
  of "fork_ring": forkRing(game, boss, attack, dmg)
  of "payload_ring": payloadRing(game, boss, attack, dmg)
  of "marching_orders": marchingOrders(game, boss, attack, dmg)
  of "priority_boost": priorityBoost(game, boss, attack)
  of "heat_trail": heatTrail(game, boss, attack, dmg)
  of "thermal_vents": thermalVents(game, boss, attack, dmg)
  of "safe_mode": safeMode(game, boss, attack, dmg)
  of "stateful_inspection": statefulInspection(game, boss, attack, dmg)
  of "port_guards": portGuards(game, boss, attack)
  of "empty_trash": emptyTrash(game, boss, attack, dmg)
  of "undelete": undelete(game, boss, attack)
  of "audit_lock": auditLock(game, boss, attack, dmg)
  of "packet_switching": packetSwitching(game, boss, attack, dmg)
  of "page_fault": pageFault(game, boss, attack, dmg)
  of "stale_copy": staleCopy(game, boss, attack, dmg)
  of "last_known_good": lastKnownGood(game, boss, attack, dmg)
  else: discard

proc retireModeBossHazards*(game: var Game, boss: Enemy) =
  ## A phase break ends the boss's standing casts (emitters, beams, echoes,
  ## restore points, mega-casts, dormant bombs). Nodes already laid (heat
  ## trail, footprints, lanes, vents) play out.
  const retired = {awtHeatEmitter, awtSearchlight, awtStaleCopy, awtRestorePoint,
                   awtAuditLock, awtSafeMode, awtLastKnownGood, awtFileBomb, awtForkTree}
  for i in countdown(game.attackWarnings.len - 1, 0):
    let w = game.attackWarnings[i]
    if w.sourceEnemyId == boss.id and w.attackType in retired:
      if w.attackType == awtAuditLock:
        game.modeCombat.auditTimer = 0
      game.attackWarnings.delete(i)
