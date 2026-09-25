## AI of the Survival horde (etThread..etInterrupt) and the Roguelite room
## roster (etFragment..etCorruptor). updateEnemy (enemy.nim) delegates here.
##
## This module moves enemies, aims and fires, and lays their tells. Anything
## that must CREATE or REMOVE enemies (a Fork Bomb forking, an Interrupt
## detonating, a Restorer finishing its channel, fork seeds splitting) is
## raised as a request on `attackPhase` and carried out by
## game/mode_mechanics.nim outside the enemy loop, where enemies can be built
## (newEnemy) and damage can reach the player.

import raylib, math, random
import particle_types, types, wall, enemy_config, enemy_helpers, bullet, mode_hazards

const
  RequestForkBombFork* = 90      ## Fork Bomb: fork a copy (mode_mechanics)
  RequestInterruptDetonate* = 91 ## Interrupt: blow up where it stands
  RequestRestorerRevive* = 92    ## Restorer: channel finished, raise the corpse

proc isModeEnemy*(et: EnemyType): bool {.inline.} =
  et in etThread..etCorruptor

proc isBallistic*(enemy: Enemy): bool {.inline.} =
  enemy.ballisticVel.x != 0.0'f32 or enemy.ballisticVel.y != 0.0'f32

proc moveToward(enemy: var Enemy, target: Vector2f, speed, dt: float32,
                walls: seq[Wall], currentTime: float32, game: var Game): bool =
  ## Inertial step toward `target`. Returns true when a wall blocked it.
  let toT = target - enemy.pos
  let d = toT.length()
  let desired = if d > 1.0'f32: toT * (speed / d) else: newVector2f(0, 0)
  let nextPos = enemy.pos + applyEnemyInertia(enemy, desired, dt) * dt
  if checkWallCollision(enemy, nextPos, walls, currentTime, game):
    discard applyEnemyInertia(enemy, newVector2f(0, 0), dt)
    return true
  enemy.pos = nextPos
  false

proc keepInArena(enemy: var Enemy, game: Game, margin: float32) =
  enemy.pos.x = clamp(enemy.pos.x, margin, game.screenWidth.float32 - margin)
  enemy.pos.y = clamp(enemy.pos.y, margin, game.screenHeight.float32 - margin)

proc onScreen(enemy: Enemy, game: Game): bool {.inline.} =
  enemy.pos.x > 0 and enemy.pos.y > 0 and
    enemy.pos.x < game.screenWidth.float32 and enemy.pos.y < game.screenHeight.float32

proc addDashLane(game: var Game, enemy: Enemy, fromPos, toPos: Vector2f, duration, width: float32) =
  var w = newAttackWarning(fromPos.x, fromPos.y, awtEnemyDashLane, duration, enemy.id)
  w.targetPos = toPos
  w.bulletRadius = width
  w.enemyType = enemy.enemyType
  game.attackWarnings.add(w)

proc findEnemyById(game: Game, id: int): Enemy =
  if id <= 0: return nil
  for other in game.enemies:
    if other.id == id and other.hp > 0:
      return other
  nil

proc rangedStep(enemy: var Enemy, playerPos: Vector2f, dt, effectiveSpeed: float32,
                walls: seq[Wall], currentTime: float32, game: var Game) =
  ## The Cube-style loop: enter the arena, hold range, fire from the config.
  let config = getEnemyConfig(enemy.enemyType)
  enemy.shootTimer += dt
  checkScreenEntry(enemy, game)
  var nextPos =
    if not enemy.hasEnteredScreen: forceScreenEntry(enemy, playerPos, dt, effectiveSpeed, game)
    else: maintainOptimalDistance(enemy, playerPos, dt, effectiveSpeed, config)
  nextPos = nextInertialEnemyPos(enemy, nextPos, dt)
  if not checkWallCollision(enemy, nextPos, walls, currentTime, game) and
     not checkScreenBoundaryCollision(enemy, nextPos, game, config):
    enemy.pos = nextPos
  else:
    discard applyEnemyInertia(enemy, newVector2f(0, 0), dt)
  executeRangedAttack(enemy, playerPos, game)

proc holdRange(enemy: var Enemy, playerPos: Vector2f, dt, effectiveSpeed: float32,
               optimal, retreat: float32, walls: seq[Wall], currentTime: float32,
               game: var Game) =
  ## Keep-away movement for support enemies (no config lookup per frame).
  let toP = playerPos - enemy.pos
  let d = max(0.001'f32, toP.length())
  let dir = toP * (1.0'f32 / d)
  let target =
    if d < retreat: enemy.pos - dir * 60.0'f32
    elif d > optimal: enemy.pos + dir * 60.0'f32
    else: enemy.pos + newVector2f(-dir.y, dir.x) * 30.0'f32
  let speed = if d > optimal: effectiveSpeed * 0.7'f32 else: effectiveSpeed
  discard moveToward(enemy, target, speed, dt, walls, currentTime, game)

proc fireRing(game: var Game, enemy: Enemy, count: int, speed, damage: float32,
              offset = 0.0'f32) =
  for i in 0..<count:
    let a = offset + i.float32 * PI * 2.0'f32 / count.float32
    game.bullets.add(newBullet(
      x = enemy.pos.x, y = enemy.pos.y, direction = newVector2f(cos(a), sin(a)),
      speed = speed, damage = damage, fromPlayer = false,
      sourceEnemyId = enemy.id, sourceEnemyType = enemy.enemyType))

# ---------------------------------------------------------------------------
# Survival horde

proc updateBallistic(enemy: var Enemy, dt: float32) =
  ## Fork seeds, payload orbs and marching ranks fly straight. Seeds split and
  ## marchers leave through game/mode_mechanics; a payload orb (generation 0)
  ## hatches into an ordinary chaser when its flight runs out.
  enemy.pos = enemy.pos + enemy.ballisticVel * dt
  enemy.vel = enemy.ballisticVel
  if enemy.generation >= 0:
    enemy.modeTimer -= dt
    if enemy.modeTimer <= 0 and enemy.generation == 0:
      enemy.ballisticVel = newVector2f(0, 0)
      enemy.hasEnteredScreen = true

proc updateThread(enemy: var Enemy, playerPos: Vector2f, dt, speed: float32,
                  walls: seq[Wall], currentTime: float32, game: var Game) =
  if isBallistic(enemy):
    updateBallistic(enemy, dt)
    return
  # Streams, not a blob: each Thread keeps a lane offset (rotation, px) that
  # folds in as it closes, so a swarm arrives as ribbons.
  let toP = playerPos - enemy.pos
  let d = max(0.001'f32, toP.length())
  let perp = newVector2f(-toP.y / d, toP.x / d)
  let lane = enemy.rotation * clamp(d / 260.0'f32, 0.0'f32, 1.0'f32)
  discard moveToward(enemy, playerPos + perp * lane, speed, dt, walls, currentTime, game)

proc updateForkBomb(enemy: var Enemy, playerPos: Vector2f, dt, speed: float32,
                    walls: seq[Wall], currentTime: float32, game: var Game) =
  discard moveToward(enemy, playerPos, speed, dt, walls, currentTime, game)
  # An ignored bomb forks a copy of itself (copies never fork again). Boss
  # children are the Forkmother's objective, not a population bomb.
  if not enemy.spawnedByBoss and enemy.generation < ForkBombMaxCopies and
     enemy.attackPhase != RequestForkBombFork:
    enemy.modeTimer += dt
    if enemy.modeTimer >= ForkBombSelfForkTime:
      enemy.attackPhase = RequestForkBombFork

proc updateDeadlock(enemy: var Enemy, playerPos: Vector2f, dt, speed: float32,
                    walls: seq[Wall], currentTime: float32, game: var Game) =
  enemy.modeTimer += dt
  let partner = findEnemyById(game, enemy.linkId)
  if partner.isNil:
    discard moveToward(enemy, playerPos, speed, dt, walls, currentTime, game)
    return
  # Each half takes the player's far side from its partner, so the tether
  # between them is dragged across the player.
  var side = enemy.pos - partner.pos
  if side.length() < 1.0'f32:
    side = newVector2f(1, 0)
  side = side.normalize()
  let target = playerPos + side * 150.0'f32
  discard moveToward(enemy, target, speed, dt, walls, currentTime, game)

proc updateInterrupt(enemy: var Enemy, playerPos: Vector2f, dt, speed: float32,
                     walls: seq[Wall], currentTime: float32, game: var Game) =
  case enemy.attackPhase
  of 0:
    discard moveToward(enemy, playerPos, speed, dt, walls, currentTime, game)
    if onScreen(enemy, game) and distance(enemy.pos, playerPos) < InterruptTriggerRange:
      # Mark where the player is heading, then commit.
      let lead = game.player.vel * 0.35'f32
      enemy.targetPos = playerPos + lead
      enemy.targetPos.x = clamp(enemy.targetPos.x, 20.0'f32, game.screenWidth.float32 - 20.0'f32)
      enemy.targetPos.y = clamp(enemy.targetPos.y, 20.0'f32, game.screenHeight.float32 - 20.0'f32)
      enemy.attackPhase = 1
      enemy.attackExecuteTimer = InterruptMarkTime
      enemy.vel = newVector2f(0, 0)
      addDashLane(game, enemy, enemy.pos, enemy.targetPos, InterruptMarkTime + 0.3'f32,
                  InterruptBlastRadius)
  of 1:
    enemy.attackExecuteTimer -= dt
    enemy.vel = newVector2f(0, 0)
    if enemy.attackExecuteTimer <= 0:
      enemy.attackPhase = 2
  of 2:
    let toT = enemy.targetPos - enemy.pos
    let d = toT.length()
    let step = InterruptDashSpeed * dt
    if d <= step + 2.0'f32:
      enemy.pos = enemy.targetPos
      enemy.attackPhase = RequestInterruptDetonate
    else:
      enemy.vel = toT * (InterruptDashSpeed / d)
      enemy.pos = enemy.pos + enemy.vel * dt
  else:
    discard

# ---------------------------------------------------------------------------
# Roguelite rooms

proc updateFragment(enemy: var Enemy, playerPos: Vector2f, dt, speed: float32,
                    walls: seq[Wall], currentTime: float32, game: var Game) =
  enemy.modeTimer += dt
  let cycle = FragmentHopTime + FragmentRestTime
  if enemy.modeTimer >= cycle:
    enemy.modeTimer -= cycle
  if enemy.modeTimer < FragmentHopTime:
    let toP = playerPos - enemy.pos
    let d = max(0.001'f32, toP.length())
    enemy.vel = toP * (speed / d)
    let nextPos = enemy.pos + enemy.vel * dt
    if not checkWallCollision(enemy, nextPos, walls, currentTime, game):
      enemy.pos = nextPos
  else:
    enemy.vel = enemy.vel * pow(0.02'f32, dt)

proc updatePortGuard(enemy: var Enemy, playerPos: Vector2f, dt, speed: float32,
                     walls: seq[Wall], currentTime: float32, game: var Game) =
  # rotation = shield facing. It turns slowly, so circling it works.
  let want = arctan2(playerPos.y - enemy.pos.y, playerPos.x - enemy.pos.x)
  var diff = want - enemy.rotation
  while diff > PI: diff -= 2.0'f32 * PI
  while diff < -PI: diff += 2.0'f32 * PI
  let turn = PortGuardTurnRate * dt
  enemy.rotation += clamp(diff, -turn, turn)
  # Advances only while roughly facing its target.
  let pace = if abs(diff) < 0.6'f32: speed else: speed * 0.25'f32
  discard moveToward(enemy, playerPos, pace, dt, walls, currentTime, game)

proc updateSentry(enemy: var Enemy, playerPos: Vector2f, dt, speed: float32,
                  walls: seq[Wall], currentTime: float32, game: var Game) =
  if enemy.attackPhase == 0:
    if enemy.modeTimer == 0.0'f32:
      # Pick a post 200-320 px from the player, clear of obstacles.
      var post = playerPos
      for attempt in 0..14:
        let a = rand(PI * 2.0)
        let r = 200.0'f32 + rand(120.0).float32
        let p = newVector2f(
          clamp(playerPos.x + cos(a) * r, 60.0'f32, game.screenWidth.float32 - 60.0'f32),
          clamp(playerPos.y + sin(a) * r, 60.0'f32, game.screenHeight.float32 - 60.0'f32))
        var blocked = false
        for wall in walls:
          if wallOverlapsCircle(wall, p, enemy.radius + 6.0'f32):
            blocked = true
            break
        post = p
        if not blocked: break
      enemy.targetPos = post
    enemy.modeTimer += dt
    let blocked = moveToward(enemy, enemy.targetPos, speed, dt, walls, currentTime, game)
    if blocked or distance(enemy.pos, enemy.targetPos) < 10.0'f32 or
       enemy.modeTimer > SentryPostTimeout:
      enemy.attackPhase = 1   # rooted
      enemy.vel = newVector2f(0, 0)
      enemy.hasEnteredScreen = true
      enemy.shootTimer = 1.0'f32
  else:
    enemy.vel = newVector2f(0, 0)
    enemy.rotation = arctan2(playerPos.y - enemy.pos.y, playerPos.x - enemy.pos.x)
    enemy.shootTimer += dt
    executeRangedAttack(enemy, playerPos, game)

proc updateMimic(enemy: var Enemy, playerPos: Vector2f, dt, speed: float32,
                 walls: seq[Wall], currentTime: float32, game: var Game) =
  case enemy.attackPhase
  of 0:
    # Dormant: a harmless-looking file. Contact never lands while it sleeps.
    enemy.vel = newVector2f(0, 0)
    enemy.lastContactDamageTime = currentTime
    if distance(enemy.pos, playerPos) < MimicWakeRadius or enemy.hp < enemy.maxHp - 0.0001'f32:
      enemy.attackPhase = 1
      enemy.modeTimer = MimicLungeTime
      let toP = playerPos - enemy.pos
      let d = max(0.001'f32, toP.length())
      enemy.ballisticVel = newVector2f(0, 0)
      enemy.vel = toP * (MimicLungeSpeed / d)
      let dmg = max(0.5'f32, enemy.contactDamage * 0.7'f32)
      fireRing(game, enemy, 6, 170.0'f32, dmg, arctan2(toP.y, toP.x))
  of 1:
    enemy.modeTimer -= dt
    let nextPos = enemy.pos + enemy.vel * dt
    if not checkWallCollision(enemy, nextPos, walls, currentTime, game):
      enemy.pos = nextPos
    keepInArena(enemy, game, enemy.radius)
    if enemy.modeTimer <= 0:
      enemy.attackPhase = 2
  else:
    discard moveToward(enemy, playerPos, speed, dt, walls, currentTime, game)

proc updateRestorer(enemy: var Enemy, playerPos: Vector2f, dt, speed: float32,
                    walls: seq[Wall], currentTime: float32, game: var Game) =
  proc corpseIndex(game: Game, id: int): int =
    for i, c in game.modeCombat.corpses:
      if c.claimedBy == id: return i
    -1
  case enemy.attackPhase
  of 0:
    holdRange(enemy, playerPos, dt, speed, 260.0'f32, 180.0'f32, walls, currentTime, game)
    enemy.modeTimer -= dt
    if enemy.modeTimer <= 0:
      var best = -1
      var bestD = RestorerSeekRange
      for i, c in game.modeCombat.corpses:
        if c.claimedBy != 0: continue
        let d = distance(enemy.pos, c.pos)
        if d < bestD:
          bestD = d
          best = i
      if best >= 0:
        game.modeCombat.corpses[best].claimedBy = enemy.id
        enemy.targetPos = game.modeCombat.corpses[best].pos
        enemy.attackPhase = 1
      else:
        enemy.modeTimer = 0.5'f32
  of 1:
    if corpseIndex(game, enemy.id) < 0:
      enemy.attackPhase = 0
      return
    discard moveToward(enemy, enemy.targetPos, speed, dt, walls, currentTime, game)
    if distance(enemy.pos, enemy.targetPos) < RestorerChannelRange:
      enemy.attackPhase = 2
      enemy.attackExecuteTimer = RestorerChannelTime
  of 2:
    enemy.vel = newVector2f(0, 0)
    let idx = corpseIndex(game, enemy.id)
    if idx < 0:
      enemy.attackPhase = 0
      enemy.modeTimer = RestorerCooldown
      return
    # Any hit breaks the channel (hitFlashTimer is only ever set by a hit).
    if enemy.hitFlashTimer > 0.0'f32:
      game.modeCombat.corpses[idx].claimedBy = 0
      enemy.attackPhase = 0
      enemy.modeTimer = RestorerCooldown
      return
    enemy.attackExecuteTimer -= dt
    if enemy.attackExecuteTimer <= 0:
      enemy.attackPhase = RequestRestorerRevive
  else:
    enemy.vel = newVector2f(0, 0)

proc bounceOffArena(enemy: var Enemy, game: Game): bool =
  let r = enemy.radius
  let w = game.screenWidth.float32
  let h = game.screenHeight.float32
  if enemy.pos.x < r and enemy.vel.x < 0:
    enemy.vel.x = -enemy.vel.x; enemy.pos.x = r; result = true
  elif enemy.pos.x > w - r and enemy.vel.x > 0:
    enemy.vel.x = -enemy.vel.x; enemy.pos.x = w - r; result = true
  if enemy.pos.y < r and enemy.vel.y < 0:
    enemy.vel.y = -enemy.vel.y; enemy.pos.y = r; result = true
  elif enemy.pos.y > h - r and enemy.vel.y > 0:
    enemy.vel.y = -enemy.vel.y; enemy.pos.y = h - r; result = true

proc updatePacket(enemy: var Enemy, playerPos: Vector2f, dt, speed: float32,
                  walls: seq[Wall], currentTime: float32, game: var Game) =
  case enemy.attackPhase
  of 0:
    # Wind-up: drift in, then lock a heading straight at the player.
    discard moveToward(enemy, playerPos, speed * 0.6'f32, dt, walls, currentTime, game)
    checkScreenEntry(enemy, game)
    if not enemy.hasEnteredScreen:
      return
    enemy.modeTimer += dt
    if enemy.modeTimer >= PacketWindup:
      let toP = playerPos - enemy.pos
      let d = max(0.001'f32, toP.length())
      let dashSpeed = getEnemyConfig(etPacket).movement.dashSpeed
      enemy.vel = toP * (dashSpeed / d)
      enemy.attackPhase = 1
      enemy.modeTimer = 0
      enemy.generation = PacketBounces
    elif enemy.modeTimer - dt < 0.0001'f32:
      addDashLane(game, enemy, enemy.pos, playerPos, PacketWindup, enemy.radius)
  of 1:
    enemy.modeTimer += dt
    enemy.pos = enemy.pos + enemy.vel * dt
    var bounced = bounceOffArena(enemy, game)
    for wall in walls:
      if wall.hp > 0 and wallOverlapsCircle(wall, enemy.pos, enemy.radius):
        let n = wallContactNormal(wall, enemy.pos)
        let vn = enemy.vel.x * n.x + enemy.vel.y * n.y
        if vn < 0:
          enemy.vel = enemy.vel - n * (2.0'f32 * vn)
        enemy.pos = enemy.pos + n * 3.0'f32
        bounced = true
        break
    if bounced:
      enemy.generation -= 1
    if enemy.generation < 0 or enemy.modeTimer > PacketMaxDash:
      enemy.attackPhase = 2
      enemy.modeTimer = PacketRest
  else:
    enemy.vel = enemy.vel * pow(0.05'f32, dt)
    enemy.pos = enemy.pos + enemy.vel * dt
    discard bounceOffArena(enemy, game)
    enemy.modeTimer -= dt
    if enemy.modeTimer <= 0:
      enemy.attackPhase = 0
      enemy.modeTimer = 0

proc updateDriver(enemy: var Enemy, playerPos: Vector2f, dt, speed: float32,
                  walls: seq[Wall], currentTime: float32, game: var Game) =
  case enemy.attackPhase
  of 0:
    let want = arctan2(playerPos.y - enemy.pos.y, playerPos.x - enemy.pos.x)
    var diff = want - enemy.rotation
    while diff > PI: diff -= 2.0'f32 * PI
    while diff < -PI: diff += 2.0'f32 * PI
    enemy.rotation += clamp(diff, -3.0'f32 * dt, 3.0'f32 * dt)
    discard moveToward(enemy, playerPos, speed, dt, walls, currentTime, game)
    checkScreenEntry(enemy, game)
    enemy.modeTimer -= dt
    if enemy.hasEnteredScreen and enemy.modeTimer <= 0 and
       distance(enemy.pos, playerPos) < DriverTriggerRange:
      let toP = (playerPos - enemy.pos).normalize()
      enemy.rotation = arctan2(toP.y, toP.x)
      enemy.targetPos = toP   # locked charge heading
      enemy.attackPhase = 1
      enemy.attackExecuteTimer = DriverWindup
      enemy.vel = newVector2f(0, 0)
      addDashLane(game, enemy, enemy.pos, enemy.pos + toP * 560.0'f32, DriverWindup,
                  enemy.radius)
  of 1:
    enemy.vel = newVector2f(0, 0)
    enemy.attackExecuteTimer -= dt
    if enemy.attackExecuteTimer <= 0:
      enemy.attackPhase = 2
      enemy.modeTimer = DriverMaxCharge
      let dashSpeed = getEnemyConfig(etDriver).movement.dashSpeed
      enemy.vel = enemy.targetPos * dashSpeed
  of 2:
    enemy.modeTimer -= dt
    let nextPos = enemy.pos + enemy.vel * dt
    var hitWall: Wall = nil
    for wall in walls:
      if wall.hp > 0 and wallOverlapsCircle(wall, nextPos, enemy.radius):
        hitWall = wall
        break
    let r = enemy.radius
    let offArena = nextPos.x < r or nextPos.y < r or
                   nextPos.x > game.screenWidth.float32 - r or
                   nextPos.y > game.screenHeight.float32 - r
    if not hitWall.isNil or offArena:
      # Slammed into something: stunned and exposed.
      if not hitWall.isNil:
        hitWall.takeDamage(2.0'f32)
      enemy.attackPhase = 3
      enemy.attackExecuteTimer = DriverStunTime
      enemy.vel = newVector2f(0, 0)
      keepInArena(enemy, game, r)
    elif enemy.modeTimer <= 0:
      enemy.attackPhase = 0
      enemy.modeTimer = DriverRecover
      enemy.vel = enemy.vel * 0.2'f32
    else:
      enemy.pos = nextPos
  else:
    enemy.vel = newVector2f(0, 0)
    enemy.attackExecuteTimer -= dt
    if enemy.attackExecuteTimer <= 0:
      enemy.attackPhase = 0
      enemy.modeTimer = DriverRecover

proc driverStunned*(enemy: Enemy): bool {.inline.} =
  enemy.enemyType == etDriver and enemy.attackPhase == 3

proc updateCorruptor(enemy: var Enemy, playerPos: Vector2f, dt, speed: float32,
                     walls: seq[Wall], currentTime: float32, game: var Game) =
  holdRange(enemy, playerPos, dt, speed, 200.0'f32, 120.0'f32, walls, currentTime, game)
  enemy.modeTimer += dt
  if enemy.modeTimer >= CorruptorDropInterval:
    enemy.modeTimer = 0
    var live = 0
    for w in game.attackWarnings:
      if w.attackType == awtCorruptTile and w.sourceEnemyId == enemy.id:
        inc live
    if live < CorruptorMaxTiles and onScreen(enemy, game):
      var tile = newAttackWarning(enemy.pos.x, enemy.pos.y, awtCorruptTile,
                                  CorruptTileArm + CorruptTileActive, enemy.id)
      tile.bulletDamage = enemy.contactDamage * 0.75'f32
      tile.bulletRadius = CorruptTileHalf
      game.attackWarnings.add(tile)

# ---------------------------------------------------------------------------

proc updateModeEnemy*(enemy: var Enemy, playerPos: Vector2f, dt, effectiveSpeed: float32,
                      walls: seq[Wall], currentTime: float32, game: var Game) =
  ## One frame of a Survival/Roguelite roster enemy (haste and slows are
  ## already folded into `effectiveSpeed` by updateEnemy).
  case enemy.enemyType
  of etThread:
    updateThread(enemy, playerPos, dt, effectiveSpeed, walls, currentTime, game)
  of etForkBomb:
    updateForkBomb(enemy, playerPos, dt, effectiveSpeed, walls, currentTime, game)
  of etWatchdog:
    rangedStep(enemy, playerPos, dt, effectiveSpeed, walls, currentTime, game)
  of etZombie:
    discard moveToward(enemy, playerPos, effectiveSpeed, dt, walls, currentTime, game)
  of etDeadlock:
    updateDeadlock(enemy, playerPos, dt, effectiveSpeed, walls, currentTime, game)
  of etDaemon:
    holdRange(enemy, playerPos, dt, effectiveSpeed, 320.0'f32, 240.0'f32, walls, currentTime, game)
  of etInterrupt:
    updateInterrupt(enemy, playerPos, dt, effectiveSpeed, walls, currentTime, game)
  of etFragment:
    updateFragment(enemy, playerPos, dt, effectiveSpeed, walls, currentTime, game)
  of etPortGuard:
    updatePortGuard(enemy, playerPos, dt, effectiveSpeed, walls, currentTime, game)
  of etSentry:
    updateSentry(enemy, playerPos, dt, effectiveSpeed, walls, currentTime, game)
  of etMimic:
    updateMimic(enemy, playerPos, dt, effectiveSpeed, walls, currentTime, game)
  of etRestorer:
    updateRestorer(enemy, playerPos, dt, effectiveSpeed, walls, currentTime, game)
  of etPacket:
    updatePacket(enemy, playerPos, dt, effectiveSpeed, walls, currentTime, game)
  of etDriver:
    updateDriver(enemy, playerPos, dt, effectiveSpeed, walls, currentTime, game)
  of etCorruptor:
    updateCorruptor(enemy, playerPos, dt, effectiveSpeed, walls, currentTime, game)
  else:
    discard

proc modeEnemyDamageTakenMult*(enemy: Enemy, hitFrom: Vector2f): float32 =
  ## Directional armour of the roster: Port Guards block the front outright
  ## (handled as a block by the caller, see portGuardBlocks), Drivers take
  ## little from the front and double while stunned. `hitFrom` is where the
  ## hit came from (bullet origin side).
  result = 1.0'f32
  if enemy.enemyType == etDriver:
    if enemy.attackPhase == 3:
      return DriverStunVulnerability
    let toSrc = hitFrom - enemy.pos
    if toSrc.length() > 0.001'f32:
      let a = arctan2(toSrc.y, toSrc.x)
      var diff = a - enemy.rotation
      while diff > PI: diff -= 2.0'f32 * PI
      while diff < -PI: diff += 2.0'f32 * PI
      if abs(diff) < 1.05'f32:
        return DriverFrontArmor

proc portGuardBlocks*(enemy: Enemy, hitFrom: Vector2f): bool =
  ## True when a hit arriving from `hitFrom` lands on a Port Guard's shield.
  if enemy.enemyType != etPortGuard or enemy.hp <= 0:
    return false
  let toSrc = hitFrom - enemy.pos
  if toSrc.length() < 0.001'f32:
    return false
  let a = arctan2(toSrc.y, toSrc.x)
  var diff = a - enemy.rotation
  while diff > PI: diff -= 2.0'f32 * PI
  while diff < -PI: diff += 2.0'f32 * PI
  abs(diff) < PortGuardShieldHalfArc
