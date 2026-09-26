## Game-side mechanics of the Survival / Roguelite rosters: everything their
## enemies and bosses do that needs the whole Game (building enemies, hurting
## the player, reading the walls, the corpses, the player's recent history).
##
## game.nim calls in at fixed points of the frame:
##   updateModeMechanics  - top of the enemy update, OUTSIDE the enemy loop
##                          (splits, requests, husks, auras, tether hits)
##   onModeEnemyKilled    - the enemy death path, after trackEnemyKilled
##   resolveModeWarning   - inside the attack-warning loop, per warning
##   recordPlayerEcho     - end of updatePlayerFiring
## Like the other game/ modules it must never import game.
##
## Loop-safety rules the rest of game.nim relies on: enemies may be APPENDED
## here (the enemy passes are index loops), but only updateModeMechanics
## deletes them, and only outside every enemy loop. Hooks never delete: a
## dying enemy is left to the main loop.

import raylib, math, random
import particle_types, types, enemy, player, bullet, particle_pool, d_systems,
       run_statistics, sound, survival, xp_orb, gamemode_definitions,
       mode_hazards, game/combat, game/death

# ---------------------------------------------------------------------------
# Shared helpers

proc hazardHitPlayer*(game: var Game, damage: float32, cause: DeathCause,
                      dmgType: DamageType, source: Enemy = nil,
                      sourceType = etEnvironment, interval = 0.0'f32): bool {.discardable.} =
  ## One hit from a roster hazard. `interval` > 0 marks a continuous hazard,
  ## gated like every beam by the player's laserHitCooldown. Boss hazards
  ## pass dcLaser (the death screen credits the living boss).
  if game.player.invincibilityTimer > 0:
    return false
  if interval > 0 and game.player.laserHitCooldown > 0:
    return false
  let died = takeDamage(game.player, damage)
  trackDamageAvoided(game)
  trackPlayerDamage(game, if source != nil: source.enemyType else: sourceType)
  game.showPlayerDamageTaken(dmgType)
  if interval > 0:
    game.player.laserHitCooldown = interval
  if died:
    beginPlayerDeathSequence(game, cause, source = source, sourceType = sourceType)
  true

proc findLiving(game: Game, id: int): Enemy =
  if id <= 0: return nil
  for e in game.enemies:
    if e.id == id and e.hp > 0:
      return e
  nil

proc buildRosterEnemy(game: var Game, pos: Vector2f, et: EnemyType,
                      fromBoss: bool, tag = stgNone, allowElite = false): Enemy =
  ## A roster enemy born mid-fight (split, fork, revive). In survival it goes
  ## through the horde constructor (density rebate, soft girth); elsewhere it
  ## is a plain enemy at the live difficulty.
  if isTimeSurvivalMode(game.mode):
    result = newSurvivalEnemy(game, pos, et, tag, allowElite = allowElite)
  else:
    result = newEnemy(pos.x, pos.y, max(0.0'f32, game.difficulty), et, game)
  result.hasEnteredScreen = true
  result.spawnedByBoss = fromBoss
  if et == etThread:
    result.rotation = rand(-60.0'f32..60.0'f32)

proc offArenaOutbound(game: Game, e: Enemy, margin: float32): bool =
  let w = game.screenWidth.float32
  let h = game.screenHeight.float32
  let outside = e.pos.x < -margin or e.pos.y < -margin or
                e.pos.x > w + margin or e.pos.y > h + margin
  if not outside: return false
  let fromCenter = e.pos - newVector2f(w / 2, h / 2)
  fromCenter.x * e.ballisticVel.x + fromCenter.y * e.ballisticVel.y > 0

# ---------------------------------------------------------------------------
# Echo (Mirror Cache replays it)

proc recordPlayerEcho*(game: var Game, aimDir: Vector2f, firing: bool, dt: float32) =
  ## Sample the player's position, aim and trigger at EchoSampleRate Hz into a
  ## ring buffer. Also latches "fired this frame" for the Audit Lock.
  let mc = addr game.modeCombat
  mc.echoShotLatch = firing
  let cap = echoCapacity()
  if mc.echo.len != cap:
    mc.echo = newSeq[EchoSample](cap)
    for s in mc.echo.mitems:
      s.pos = game.player.pos
    mc.echoHead = 0
  mc.echoClock += dt
  let step = 1.0'f32 / EchoSampleRate
  var firedSince = firing
  while mc.echoClock >= step:
    mc.echoClock -= step
    mc.echoHead = (mc.echoHead + 1) mod cap
    mc.echo[mc.echoHead] = EchoSample(
      pos: game.player.pos,
      aim: if aimDir.length() > 0.01'f32: arctan2(aimDir.y, aimDir.x) else: 0.0'f32,
      fired: firedSince)
    firedSince = false

proc echoSampleAgo(game: Game, seconds: float32): EchoSample =
  let mc = game.modeCombat
  if mc.echo.len == 0:
    return EchoSample(pos: game.player.pos)
  let back = clamp(int(seconds * EchoSampleRate), 0, mc.echo.len - 1)
  mc.echo[(mc.echoHead - back + mc.echo.len) mod mc.echo.len]

proc resetModeCombat*(game: var Game) =
  ## Drop the transient roster state (a room/horde wipe or a new fight).
  game.modeCombat.corpses.setLen(0)
  game.modeCombat.husks.setLen(0)
  game.modeCombat.auditTimer = 0
  game.modeCombat.auditBreached = false

# ---------------------------------------------------------------------------
# Deaths

proc interruptBlast(game: var Game, e: Enemy, radius: float32) =
  ## An Interrupt going off: hurts the player and every horde body in reach.
  spawnExplosionPooled(game.particlePool, e.pos.x, e.pos.y, Color(r: 255, g: 150, b: 40, a: 255), 28)
  spawnShockwavePooled(game.particlePool, e.pos.x, e.pos.y, radius)
  addShake(game.dopamine.screenShake, siMedium)
  if distance(game.player.pos, e.pos) <= radius + game.player.radius:
    hazardHitPlayer(game, e.contactDamage * 1.5'f32, dcExplosion, dtExplosion, source = e)
  for other in game.enemies:
    if other.isBoss or other.hp <= 0 or other == e: continue
    if distance(other.pos, e.pos) <= radius + other.radius:
      discard applyEnemyHpDamage(other, other.maxHp * InterruptBlastEnemyFrac)

proc onModeEnemyKilled*(game: var Game, enemy: Enemy) =
  ## Death hooks of the roster (called from the main death path).
  if enemy.isBoss:
    return
  case enemy.enemyType
  of etForkBomb:
    # Splits into two Threads, flung apart.
    for s in [-1.0'f32, 1.0'f32]:
      if isTimeSurvivalMode(game.mode) and survivalAliveCount(game) >= SurvivalMaxAlive:
        break
      let a = rand(PI * 2.0).float32
      let off = newVector2f(cos(a), sin(a)) * (10.0'f32 * s)
      let t = buildRosterEnemy(game, enemy.pos + off, etThread, enemy.spawnedByBoss,
                               enemy.survivalTag)
      t.vel = off * 14.0'f32
      game.enemies.add(t)
    spawnExplosionPooled(game.particlePool, enemy.pos.x, enemy.pos.y, enemy.color, 12)
  of etZombie:
    if enemy.generation == 0:
      game.modeCombat.husks.add(HuskRecord(
        pos: enemy.pos, maxHp: enemy.maxHp, radius: enemy.radius, speed: enemy.speed,
        contactDamage: enemy.contactDamage, timer: ZombieReanimateTime,
        tag: enemy.survivalTag, fromBoss: enemy.spawnedByBoss))
  of etInterrupt:
    # Shot before it landed: a smaller pop where it fell.
    if enemy.attackPhase != RequestInterruptDetonate:
      interruptBlast(game, enemy, InterruptDeathBlastRadius)
  of etRestorer:
    for c in game.modeCombat.corpses.mitems:
      if c.claimedBy == enemy.id:
        c.claimedBy = 0
  else:
    discard
  # Roguelite corpses a Restorer can raise (never its own summons, never the
  # raised ones again).
  if enemy.enemyType in etFragment..etCorruptor and not enemy.spawnedByBoss and
     enemy.enemyType != etRestorer:
    game.modeCombat.corpses.add(CorpseRecord(
      pos: enemy.pos, enemyType: enemy.enemyType, maxHp: enemy.maxHp,
      radius: enemy.radius, age: 0))

# ---------------------------------------------------------------------------
# Per-frame (outside the enemy loop)

proc splitSeed(game: var Game, seed: Enemy) =
  ## A fork seed doubles: two children on either side of its heading.
  let speed = seed.ballisticVel.length()
  let heading = arctan2(seed.ballisticVel.y, seed.ballisticVel.x)
  let spread = seed.targetPos.x    # branch half-angle (radians), set at launch
  let beat = seed.targetPos.y      # seconds to the next split
  for s in [-1.0'f32, 1.0'f32]:
    let a = heading + s * spread
    let child = buildRosterEnemy(game, seed.pos, etThread, true)
    child.maxHp = seed.maxHp
    child.hp = seed.maxHp
    child.radius = seed.radius
    child.collisionRadius = seed.collisionRadius
    child.contactDamage = seed.contactDamage
    child.color = seed.color
    child.linkId = seed.linkId
    child.ballisticVel = newVector2f(cos(a), sin(a)) * speed
    child.generation = seed.generation - 1
    child.modeTimer = if child.generation > 0: beat else: beat * 1.4'f32
    child.targetPos = seed.targetPos
    game.enemies.add(child)
  spawnExplosionPooled(game.particlePool, seed.pos.x, seed.pos.y, seed.color, 8)

proc reviveCorpse(game: var Game, restorer: Enemy) =
  var idx = -1
  for i, c in game.modeCombat.corpses:
    if c.claimedBy == restorer.id:
      idx = i
      break
  restorer.attackPhase = 0
  restorer.modeTimer = RestorerCooldown
  if idx < 0:
    return
  let c = game.modeCombat.corpses[idx]
  game.modeCombat.corpses.delete(idx)
  let e = buildRosterEnemy(game, c.pos, c.enemyType, true)
  # Comes back a little worse for wear, and drops nothing (spawnedByBoss).
  e.maxHp = max(0.5'f32, c.maxHp * 0.6'f32)
  e.hp = e.maxHp
  e.radius = c.radius
  e.collisionRadius = c.radius * 0.4'f32
  if c.enemyType == etMimic:
    e.attackPhase = 2   # a raised Mimic is already awake
  game.enemies.add(e)
  spawnExplosionPooled(game.particlePool, c.pos.x, c.pos.y, Color(r: 120, g: 255, b: 160, a: 255), 18)

proc forkBombFork(game: var Game, bomb: Enemy) =
  bomb.attackPhase = 0
  bomb.modeTimer = 0
  if isTimeSurvivalMode(game.mode) and survivalAliveCount(game) >= SurvivalMaxAlive:
    return
  let a = rand(PI * 2.0).float32
  let copy = buildRosterEnemy(game, bomb.pos + newVector2f(cos(a), sin(a)) * (bomb.radius * 1.8'f32),
                              etForkBomb, bomb.spawnedByBoss, bomb.survivalTag)
  copy.generation = bomb.generation + 1
  bomb.generation = bomb.generation + 1   # the original has now forked too
  game.enemies.add(copy)
  spawnExplosionPooled(game.particlePool, bomb.pos.x, bomb.pos.y, bomb.color, 14)

proc fragmentSlam(game: var Game, frag: Enemy) =
  ## A Fragment crashing down on its pounce mark.
  frag.attackPhase = 4
  frag.modeTimer = FragmentRecoverTime
  # The slam is this landing's hit: no contact tick on top of it.
  frag.lastContactDamageTime = game.time
  spawnShockwavePooled(game.particlePool, frag.pos.x, frag.pos.y, FragmentSlamRadius)
  spawnExplosionPooled(game.particlePool, frag.pos.x, frag.pos.y, frag.color, 10)
  if distance(game.player.pos, frag.pos) <= FragmentSlamRadius + game.player.radius * 0.6'f32:
    if hazardHitPlayer(game, frag.contactDamage, dcContact, dtDefault, source = frag):
      addShake(game.dopamine.screenShake, siSmall)
      playSound(stPlayerHit, 0.4)

proc updateModeMechanics*(game: var Game, dt: float32) =
  ## Once per frame, before the enemy loop.
  let mc = addr game.modeCombat

  # Enemy requests + ballistic units.
  var i = 0
  while i < game.enemies.len:
    let e = game.enemies[i]
    if e.isBoss or e.hp <= 0:
      inc i
      continue
    var remove = false
    case e.attackPhase
    of RequestForkBombFork:
      if e.enemyType == etForkBomb: forkBombFork(game, e)
    of RequestInterruptDetonate:
      if e.enemyType == etInterrupt:
        interruptBlast(game, e, InterruptBlastRadius)
        remove = true
    of RequestRestorerRevive:
      if e.enemyType == etRestorer: reviveCorpse(game, e)
    of RequestFragmentSlam:
      if e.enemyType == etFragment: fragmentSlam(game, e)
    else:
      discard
    if not remove and isBallistic(e):
      if e.generation > 0 and e.modeTimer <= 0:
        splitSeed(game, e)
        remove = true
      elif offArenaOutbound(game, e, 60.0'f32):
        remove = true
    if remove:
      game.enemies.delete(i)
    else:
      inc i

  # Husks: stand back up unless the player walks over them.
  var h = 0
  while h < mc.husks.len:
    mc.husks[h].timer -= dt
    let husk = mc.husks[h]
    if distance(game.player.pos, husk.pos) <= ZombieReapRadius + game.player.radius:
      # Reaped: a small XP bonus for the walk.
      if game.mode in {gmWaveBased, gmRoguelite, gmTimeSurvival} and not husk.fromBoss:
        game.xpOrbs.add(newXpOrb(husk.pos.x, husk.pos.y, 2))
      spawnExplosionPooled(game.particlePool, husk.pos.x, husk.pos.y, Color(r: 200, g: 230, b: 120, a: 255), 12)
      mc.husks.delete(h)
      continue
    if husk.timer <= 0:
      let z = buildRosterEnemy(game, husk.pos, etZombie, husk.fromBoss, husk.tag)
      z.maxHp = max(0.5'f32, husk.maxHp * ZombieReviveHpFrac)
      z.hp = z.maxHp
      z.radius = husk.radius
      z.collisionRadius = husk.radius * 0.4'f32
      z.speed = husk.speed
      z.contactDamage = husk.contactDamage
      z.generation = 1
      game.enemies.add(z)
      spawnExplosionPooled(game.particlePool, husk.pos.x, husk.pos.y, Color(r: 150, g: 180, b: 110, a: 255), 16)
      mc.husks.delete(h)
      continue
    inc h

  # Corpses fade.
  var c = 0
  while c < mc.corpses.len:
    mc.corpses[c].age += dt
    if mc.corpses[c].age > CorpseLifetime and mc.corpses[c].claimedBy == 0:
      mc.corpses.delete(c)
    else:
      inc c

  # Priority Daemons haste the crowd around them.
  for d in game.enemies:
    if d.enemyType != etDaemon or d.hp <= 0 or d.isBoss: continue
    for o in game.enemies:
      if o == d or o.isBoss or o.hp <= 0 or o.enemyType == etDaemon: continue
      if distance(o.pos, d.pos) <= DaemonAuraRadius:
        o.hasteAmount = max(o.hasteAmount, DaemonHaste)
        o.hasteTimer = max(o.hasteTimer, 0.15'f32)

  # The mutex mesh: every two armed Deadlocks within DeadlockMaxTether of each
  # other are linked, and a link burns the player crossing it. One shared hit
  # cooldown, so standing in several links at once is still one hit per beat.
  block mesh:
    for i in 0..<game.enemies.len:
      let a = game.enemies[i]
      if a.enemyType != etDeadlock or a.hp <= 0 or a.isBoss or a.modeTimer < DeadlockArmDelay:
        continue
      for j in i + 1 ..< game.enemies.len:
        let b = game.enemies[j]
        if b.enemyType != etDeadlock or b.hp <= 0 or b.isBoss or b.modeTimer < DeadlockArmDelay:
          continue
        if distance(a.pos, b.pos) > DeadlockMaxTether: continue
        if pointSegmentDistance(game.player.pos, a.pos, b.pos) <=
             DeadlockTetherHalfWidth + game.player.radius * 0.6'f32:
          hazardHitPlayer(game, a.contactDamage, dcHazard, dtLaser, source = a,
                          interval = DeadlockTetherInterval)
          break mesh

  # Audit Lock countdown (the freeze itself is applied by game.nim).
  if mc.auditTimer > 0:
    mc.auditTimer = max(0.0'f32, mc.auditTimer - dt)

# ---------------------------------------------------------------------------
# Hazard resolution (one warning per call, inside game.nim's warning loop)

proc bossOf(game: Game, w: AttackWarning): Enemy =
  findLiving(game, w.sourceEnemyId)

proc spawnMarchRank(game: var Game, w: AttackWarning) =
  ## A rank of ballistic Threads across the lane, in two staggered rows so
  ## there is no gap to walk through: the player shoots one.
  let dir = (w.targetPos - w.pos).normalize()
  let perp = newVector2f(-dir.y, dir.x)
  let bodies = max(4, w.bulletCount)
  let halfSpan = w.laserLength
  let spacing = (halfSpan * 2.0'f32) / (bodies - 1).float32
  for row in 0..<MarchRankRows:
    for k in 0..<bodies:
      let along = -halfSpan + k.float32 * spacing + (if row == 1: spacing * 0.5'f32 else: 0.0'f32)
      if abs(along) > halfSpan + 1.0'f32: continue
      let p = w.pos + perp * along - dir * (row.float32 * MarchRankRowGap + 30.0'f32)
      let m = buildRosterEnemy(game, p, etThread, true)
      m.maxHp = max(0.5'f32, w.bulletRadius)
      m.hp = m.maxHp
      m.contactDamage = w.bulletDamage
      m.color = Color(r: 255, g: 170, b: 40, a: 255)
      m.ballisticVel = dir * w.bulletSpeed
      m.generation = BallisticMarcher
      m.hasEnteredScreen = true
      game.enemies.add(m)

proc pageInWall(game: var Game, w: AttackWarning) =
  ## The obstacle a Page Fault footprint lands as (tinted like the room's own).
  var tint = Color(r: 150, g: 95, b: 235, a: 255)
  var hp = 8.0'f32
  for wall in game.walls:
    if wall.permanent:
      tint = wall.obstacleTint
      hp = max(hp, wall.maxHp)
      break
  game.walls.add(Wall(pos: w.pos, radius: w.bulletRadius, hp: hp, maxHp: hp,
                      duration: 1.0, permanent: true, respawns: false,
                      obstacleTint: tint))
  spawnExplosionPooled(game.particlePool, w.pos.x, w.pos.y, Color(r: 200, g: 160, b: 255, a: 255), 20)

proc pageInQuietly*(game: var Game, w: AttackWarning) =
  ## A dead Supervisor's pending page-ins still land (no crush), so the room
  ## keeps its cover.
  if w.lasersCreated or w.lifetime > PageFaultActive:
    return
  w.lasersCreated = true
  pageInWall(game, w)

proc resolveModeWarning*(game: var Game, w: AttackWarning, dt: float32) =
  let age = warningAge(w)
  case w.attackType
  of awtCorruptTile:
    if w.lifetime <= CorruptTileActive:
      let d = game.player.pos - w.pos
      if abs(d.x) <= w.bulletRadius + game.player.radius * 0.5'f32 and
         abs(d.y) <= w.bulletRadius + game.player.radius * 0.5'f32:
        hazardHitPlayer(game, w.bulletDamage, dcHazard, dtPoison, sourceType = etCorruptor,
                        interval = CorruptTileInterval)

  of awtMarchLane:
    if not w.bulletsCreated and w.lifetime <= 0.05'f32:
      w.bulletsCreated = true
      spawnMarchRank(game, w)

  of awtHeatEmitter:
    # Rides the player, dropping a heat node every HeatNodeSpacing of travel.
    let boss = bossOf(game, w)
    if boss.isNil:
      w.lifetime = 0
      return
    if distance(game.player.pos, w.targetPos) >= HeatNodeSpacing or not w.bulletsCreated:
      w.bulletsCreated = true
      w.targetPos = game.player.pos
      var node = newAttackWarning(game.player.pos.x, game.player.pos.y, awtHeatTrail,
                                  HeatTrailArm + HeatTrailActive, w.sourceEnemyId)
      node.bulletRadius = w.bulletRadius
      node.bulletDamage = w.bulletDamage
      game.attackWarnings.add(node)
    w.pos = game.player.pos

  of awtHeatTrail:
    if age >= HeatTrailArm:
      if distance(game.player.pos, w.pos) <= w.bulletRadius + game.player.radius * 0.6'f32:
        hazardHitPlayer(game, w.bulletDamage, dcLaser, dtFire, interval = HeatTrailInterval)
      # ...and it burns the horde: lead them through it.
      for e in game.enemies:
        if e.isBoss or e.hp <= 0: continue
        if distance(e.pos, w.pos) <= w.bulletRadius + e.radius:
          discard applyEnemyHpDamage(e, e.maxHp * HeatTrailEnemyDps * dt)

  of awtThermalVent:
    if w.lifetime <= ThermalVentActive and not w.lasersCreated:
      w.lasersCreated = true
      spawnExplosionPooled(game.particlePool, w.pos.x, w.pos.y, Color(r: 255, g: 130, b: 30, a: 255), 26)
      addShake(game.dopamine.screenShake, siSmall)
      if distance(game.player.pos, w.pos) <= w.bulletRadius + game.player.radius:
        hazardHitPlayer(game, w.bulletDamage, dcLaser, dtFire)

  of awtSafeMode:
    if safeModeFlooding(w):
      let (c, r) = safeModeBubble(w)
      if distance(game.player.pos, c) > r - game.player.radius * 0.5'f32:
        hazardHitPlayer(game, w.bulletDamage, dcLaser, dtArcane, interval = SafeModeInterval)
      # The flood drags the horde into the bubble with the player.
      for e in game.enemies:
        if e.isBoss or e.hp <= 0: continue
        let d = distance(e.pos, c)
        if d > r * 0.8'f32 and d > 1.0'f32:
          e.pos = e.pos + (c - e.pos) * (SafeModePull * dt / d)

  of awtSearchlight:
    let boss = bossOf(game, w)
    if boss.isNil:
      w.lifetime = 0
      return
    w.pos = boss.pos
    if w.ricochetPath.len != w.laserAngles.len:
      w.ricochetPath = newSeq[Vector2f](w.laserAngles.len)
    for b in 0..<w.laserAngles.len:
      let a = searchlightAngle(w, b)
      let dir = newVector2f(cos(a), sin(a))
      let len = rayWallDistance(w.pos + dir * (boss.radius * 0.6'f32), dir, SearchlightLength, game.walls) +
                boss.radius * 0.6'f32
      w.ricochetPath[b] = w.pos + dir * len
      if searchlightLive(w) and
         pointSegmentDistance(game.player.pos, w.pos, w.ricochetPath[b]) <=
           SearchlightHalfWidth + game.player.radius * 0.6'f32:
        hazardHitPlayer(game, w.bulletDamage, dcLaser, dtLaser, interval = SearchlightInterval)

  of awtFileBomb:
    if w.lifetime > FileBombPurgeFlash:
      # Shred it: walk over it, or shoot it.
      var shredded = distance(game.player.pos, w.pos) <= FileBombShredRadius + game.player.radius
      if not shredded:
        for b in game.bullets:
          if b.fromPlayer and b.lifetime > 0 and distance(b.pos, w.pos) <= FileBombShredRadius * 0.6'f32:
            b.lifetime = 0
            shredded = true
            break
      if shredded:
        spawnExplosionPooled(game.particlePool, w.pos.x, w.pos.y, Color(r: 200, g: 230, b: 190, a: 255), 12)
        playSound(stCoinPickup, 0.4)
        w.lifetime = 0
    elif not w.lasersCreated:
      # The purge: every bomb still standing bursts at once.
      w.lasersCreated = true
      spawnExplosionPooled(game.particlePool, w.pos.x, w.pos.y, Color(r: 160, g: 255, b: 120, a: 255), 22)
      addShake(game.dopamine.screenShake, siSmall)
      if distance(game.player.pos, w.pos) <= FileBombBlastRadius + game.player.radius * 0.5'f32:
        hazardHitPlayer(game, w.bulletDamage, dcLaser, dtExplosion)
      let offset = rand(PI * 2.0).float32
      for k in 0..<FileBombShrapnel:
        let a = offset + k.float32 * PI * 2.0'f32 / FileBombShrapnel.float32
        game.bullets.add(newBullet(
          x = w.pos.x, y = w.pos.y, direction = newVector2f(cos(a), sin(a)),
          speed = w.bulletSpeed, damage = w.bulletDamage * 0.6'f32, fromPlayer = false,
          isBossBullet = true, sourceEnemyId = w.sourceEnemyId))

  of awtRestorePoint:
    let boss = bossOf(game, w)
    if boss.isNil or boss.currentPhaseIndex != w.bulletCount:
      w.lifetime = 0
      return
    w.pos = boss.pos
    w.bulletRadius = boss.radius
    # bulletDamage = HP snapshot, bulletSpreadAngle = HP the player must take off.
    let dealt = w.bulletDamage - boss.hp
    w.laserLength = if w.bulletSpreadAngle > 0: dealt / w.bulletSpreadAngle else: 1.0'f32
    if w.laserLength >= 1.0'f32 and not w.lasersCreated:
      w.lasersCreated = true
      spawnExplosionPooled(game.particlePool, boss.pos.x, boss.pos.y, Color(r: 255, g: 90, b: 90, a: 255), 30)
      addShake(game.dopamine.screenShake, siMedium)
      w.lifetime = 0
    elif w.lifetime <= 0.05'f32 and not w.lasersCreated:
      w.lasersCreated = true
      # Rolled back: the damage since the restore point is undone (capped).
      let cap = boss.maxHp * RestorePointHealCap
      let restored = clamp(w.bulletDamage - boss.hp, 0.0'f32, cap)
      if restored > 0 and boss.hp > 0:
        boss.hp = min(boss.maxHp, boss.hp + restored)
        showDamage(game, boss.pos, restored, false, false, dtHeal)
        spawnExplosionPooled(game.particlePool, boss.pos.x, boss.pos.y, Color(r: 120, g: 255, b: 170, a: 255), 30)

  of awtAuditLock:
    w.pos = game.player.pos
    if age >= AuditTelegraph:
      if not w.lasersCreated:
        # Lock: the room freezes; the player must too.
        w.lasersCreated = true
        w.targetPos = game.player.pos
        game.modeCombat.auditTimer = w.lifetime
        game.modeCombat.auditOrigin = game.player.pos
        game.modeCombat.auditBreached = false
        addShake(game.dopamine.screenShake, siSmall)
      game.modeCombat.auditTimer = max(game.modeCombat.auditTimer, w.lifetime)
      if not w.bulletsCreated and age >= AuditTelegraph + AuditGrace:
        let moved = distance(game.player.pos, w.targetPos) > AuditMoveTolerance
        if moved or game.modeCombat.echoShotLatch:
          w.bulletsCreated = true   # breach: one hit per audit
          game.modeCombat.auditBreached = true
          hazardHitPlayer(game, w.bulletDamage, dcLaser, dtArcane)
          spawnExplosionPooled(game.particlePool, game.player.pos.x, game.player.pos.y,
                               Color(r: 255, g: 80, b: 80, a: 255), 18)
    if w.lifetime <= 0.02'f32:
      game.modeCombat.auditTimer = 0

  of awtPacketLink:
    let train = packetTrain(w)
    if train.live:
      if not w.bulletsCreated:
        w.bulletsCreated = true
        spawnExplosionPooled(game.particlePool, w.pos.x, w.pos.y, Color(r: 0, g: 230, b: 255, a: 255), 8)
      if pointSegmentDistance(game.player.pos, train.tail, train.head) <=
           PacketRadius + game.player.radius * 0.7'f32:
        hazardHitPlayer(game, w.bulletDamage, dcLaser, dtLaser, interval = PacketHitInterval)

  of awtPageFault:
    if w.lifetime <= PageFaultActive and not w.lasersCreated:
      w.lasersCreated = true
      # The obstacle pages in. Anyone standing in the footprint is crushed
      # (and shoved out of it).
      if distance(game.player.pos, w.pos) <= w.bulletRadius + game.player.radius:
        hazardHitPlayer(game, w.bulletDamage, dcLaser, dtExplosion)
        var away = game.player.pos - w.pos
        if away.length() < 1.0'f32: away = newVector2f(1, 0)
        game.player.pos = w.pos + away.normalize() * (w.bulletRadius + game.player.radius + 4.0'f32)
      pageInWall(game, w)
      addShake(game.dopamine.screenShake, siSmall)

  of awtStaleCopy:
    let boss = bossOf(game, w)
    if boss.isNil:
      w.lifetime = 0
      return
    if age >= w.laserDuration:
      # laserDuration = replay delay; the echo walks the player's past.
      let s = echoSampleAgo(game, w.laserDuration)
      w.targetPos = s.pos
      if w.laserAngles.len == 0: w.laserAngles = @[0.0'f32]
      w.laserAngles[0] = s.aim
      w.bulletSpeed -= dt   # repurposed: echo fire cooldown
      if s.fired and w.bulletSpeed <= 0 and age >= w.laserDuration + EchoFadeIn:
        w.bulletSpeed = EchoShotInterval
        let dir = newVector2f(cos(s.aim), sin(s.aim))
        game.bullets.add(newBullet(
          x = s.pos.x + dir.x * EchoRadius, y = s.pos.y + dir.y * EchoRadius,
          direction = dir, speed = 260.0'f32, damage = w.bulletDamage * 0.6'f32,
          fromPlayer = false, isBossBullet = true, sourceEnemyId = w.sourceEnemyId,
          colorOverride = Color(r: 90, g: 230, b: 210, a: 255)))
      if age >= w.laserDuration + EchoFadeIn and
         distance(game.player.pos, s.pos) <= EchoRadius + game.player.radius * 0.6'f32:
        hazardHitPlayer(game, w.bulletDamage, dcLaser, dtArcane, interval = LaserHitInterval)

  of awtLastKnownGood:
    let sw = w.pos.x * 2.0'f32
    let sh = w.pos.y * 2.0'f32
    let safe = lkgInDoor(w.bulletCount, game.player.pos, sw, sh)
    if w.lifetime > LkgActive:
      # The purge front burns everything it has passed, except the true door.
      if age >= LkgReveal and not safe and distance(game.player.pos, w.pos) <= lkgPurgeRadius(w):
        hazardHitPlayer(game, w.bulletDamage * 0.5'f32, dcLaser, dtArcane, interval = 0.6'f32)
    elif not w.lasersCreated:
      w.lasersCreated = true
      addShake(game.dopamine.screenShake, siLarge)
      for door in 0..3:
        let r = lkgDoorRect(door, sw, sh)
        let col = if door == w.bulletCount: Color(r: 255, g: 215, b: 110, a: 255)
                  else: Color(r: 255, g: 50, b: 70, a: 255)
        spawnExplosionPooled(game.particlePool, r.x + r.w / 2, r.y + r.h / 2, col, 26)
      if not safe:
        hazardHitPlayer(game, w.bulletDamage, dcLaser, dtArcane)

  else:
    discard
