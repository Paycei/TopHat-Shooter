## Mod things: the one generic 2D arena entity behind register.thing /
## spawn.thing / spawn.hazard (allies, turrets, orbitals, auras, obstacles,
## zones, props, custom pickups and telegraphed hazards).
##
## A thing is plain data (types.ModThing); everything it does comes from its
## registered kind (mod_registry.ThingKind): a motion mode, contact damage,
## solidity, a declarative turret weapon, a hazard spec, and script callbacks.
##
## game.nim calls, once per frame of play:
##   updateThings      after enemy spawning, before the enemy loop (kills
##                     then resolve in that same frame's enemy loop);
##   collideThingBullets  right after, outside the bullet loop (which deletes
##                     bullets in place), so blocked bullets are gone before it;
##   drawThings        three times, one per ThingLayer.
## Like the other game/ modules it never imports game.

import std/[math, sets, tables]
import raylib
import ../draw_prims
import ../types, ../particle_types, ../player, ../bullet, ../enemy_helpers, ../run_statistics, ../particle_pool
import combat, death
import ../modding/[lua_bridge, mod_hooks, mod_registry, mod_assets]

const
  ThingGridCell = 96.0'f32
  ThingGridMargin = 200.0'f32
  DefaultContactInterval = 0.5'f32
  MagnetRange = 140.0'f32

var
  thingGrid: SpatialGrid
  thingGridMaxR: float32

# ---------------------------------------------------------------- helpers ----
proc alive*(t: ModThing): bool {.inline.} =
  tfDead notin t.flags and tfRemoved notin t.flags

proc extentRadius(t: ModThing): float32 {.inline.} =
  ## The radius of a circle that contains the thing (for grid queries).
  if t.shape == tsRect: 0.5'f32 * sqrt(t.w * t.w + t.h * t.h) else: t.radius

proc overlapsCircle*(t: ModThing, p: Vector2f, r: float32): bool =
  ## Does the thing's body touch the circle (p, r)?
  if t.shape == tsRect:
    let hw = t.w * 0.5'f32
    let hh = t.h * 0.5'f32
    let cx = clamp(p.x, t.pos.x - hw, t.pos.x + hw)
    let cy = clamp(p.y, t.pos.y - hh, t.pos.y + hh)
    let dx = p.x - cx
    let dy = p.y - cy
    dx * dx + dy * dy <= r * r
  else:
    let dx = p.x - t.pos.x
    let dy = p.y - t.pos.y
    let rr = r + t.radius
    dx * dx + dy * dy <= rr * rr

proc pushOut(t: ModThing, p: var Vector2f, r: float32) =
  ## Move the circle (p, r) out of a solid thing.
  if t.shape == tsRect:
    let hw = t.w * 0.5'f32
    let hh = t.h * 0.5'f32
    let cx = clamp(p.x, t.pos.x - hw, t.pos.x + hw)
    let cy = clamp(p.y, t.pos.y - hh, t.pos.y + hh)
    var dx = p.x - cx
    var dy = p.y - cy
    let d2 = dx * dx + dy * dy
    if d2 >= r * r: return
    if d2 > 0.0001:
      let d = sqrt(d2)
      p.x += dx / d * (r - d)
      p.y += dy / d * (r - d)
    else:
      # centre inside the rect: out through the nearest side
      let left = p.x - (t.pos.x - hw)
      let right = (t.pos.x + hw) - p.x
      let top = p.y - (t.pos.y - hh)
      let bottom = (t.pos.y + hh) - p.y
      let m = min(min(left, right), min(top, bottom))
      if m == left: p.x = t.pos.x - hw - r
      elif m == right: p.x = t.pos.x + hw + r
      elif m == top: p.y = t.pos.y - hh - r
      else: p.y = t.pos.y + hh + r
  else:
    let dx = p.x - t.pos.x
    let dy = p.y - t.pos.y
    let rr = r + t.radius
    let d2 = dx * dx + dy * dy
    if d2 >= rr * rr: return
    if d2 > 0.0001:
      let d = sqrt(d2)
      p.x = t.pos.x + dx / d * rr
      p.y = t.pos.y + dy / d * rr
    else:
      p.x = t.pos.x + rr

proc hazardHits*(t: ModThing, p: Vector2f, r: float32): bool =
  ## Is the circle (p, r) inside the hazard's area?
  let hz = t.hazard
  case hz.shape
  of hzNone: false
  of hzCircle:
    let dx = p.x - t.pos.x
    let dy = p.y - t.pos.y
    let rr = t.radius + r
    dx * dx + dy * dy <= rr * rr
  of hzRect:
    let hw = t.w * 0.5'f32 + r
    let hh = t.h * 0.5'f32 + r
    abs(p.x - t.pos.x) <= hw and abs(p.y - t.pos.y) <= hh
  of hzLine:
    # a beam of width 2 * radius from pos, `length` along `angle`
    let a = degToRad(t.angle)
    let ux = cos(a)
    let uy = sin(a)
    let dx = p.x - t.pos.x
    let dy = p.y - t.pos.y
    let along = clamp(dx * ux + dy * uy, 0'f32, hz.length)
    let ex = dx - ux * along
    let ey = dy - uy * along
    let rr = t.radius + r
    ex * ex + ey * ey <= rr * rr
  of hzRing:
    let d = sqrt((p.x - t.pos.x) * (p.x - t.pos.x) + (p.y - t.pos.y) * (p.y - t.pos.y))
    d + r >= hz.inner and d - r <= t.radius

proc kindOf(t: ModThing): int {.inline.} = findThingKind(t.kind)

proc hurtsPlayer(t: ModThing): bool {.inline.} = t.team != ttPlayer
proc hurtsEnemies(t: ModThing): bool {.inline.} = t.team != ttEnemy

proc thingWrapArgs(t: ModThing): ScriptValue {.inline.} = wrapThing(t)

# ------------------------------------------------------- damage and death ----
proc killThing*(game: Game, t: ModThing) =
  ## Its HP ran out (or a script killed it): onDeath, the thingDeath hook, gone.
  if not t.alive: return
  t.flags.incl(tfDead)
  t.hp = 0
  var r: RetVals
  discard thingCall(t, proc (k: ThingKind): ScriptValue {.nimcall.} = k.onDeath,
                    [wrapThing(t), wrapGame(game)], r)
  modThingDeath(t)
  spawnExplosionPooled(game.particlePool, t.pos.x, t.pos.y, t.color, 10)

proc damageThing*(game: Game, t: ModThing, amount: float32, source: string = "script"): float32 =
  ## Damage actually dealt (its kind's onDamaged may change it). `source`:
  ## "bullet", "enemy", "explosion" or "script".
  if not t.alive or amount <= 0 or tfInvulnerable in t.flags or t.maxHp <= 0:
    return 0
  var dmg = amount
  var r: RetVals
  if thingCall(t, proc (k: ThingKind): ScriptValue {.nimcall.} = k.onDamaged,
               [wrapThing(t), vnum(dmg.float64), vstr(source)], r):
    dmg = max(0'f32, numResult(r, dmg))
  if dmg <= 0: return 0
  result = min(dmg, t.hp)
  t.hp -= dmg
  t.hitFlash = 0.12
  if t.hp <= 0: killThing(game, t)

proc removeThing*(t: ModThing) =
  ## Gone at the end of the frame: no death, no onDeath.
  t.flags.incl(tfRemoved)

# ----------------------------------------------------------------- turret ----
proc fireWeapon(game: Game, t: ModThing, w: ThingWeapon): bool =
  ## False: nothing in range (the turret stays ready).
  var target: Vector2f
  var found = false
  var bestD = w.range * w.range
  if t.team == ttEnemy:
    let dx = game.player.pos.x - t.pos.x
    let dy = game.player.pos.y - t.pos.y
    if dx * dx + dy * dy <= bestD:
      target = game.player.pos
      found = true
  else:
    for e in game.enemies:
      if e.hp <= 0: continue
      let dx = e.pos.x - t.pos.x
      let dy = e.pos.y - t.pos.y
      let d = dx * dx + dy * dy
      if d < bestD:
        bestD = d
        target = e.pos
        found = true
  if not found: return false
  result = true
  let base = arctan2(target.y - t.pos.y, target.x - t.pos.x)
  t.angle = radToDeg(base)
  let n = max(1, w.count)
  let pierce = block:
    let pk = findProjectileKind(w.kind)
    if pk >= 0: projectileKinds[pk].pierce else: 0'i32
  for i in 0 ..< n:
    let off = degToRad(w.spread) * (i.float32 - (n - 1).float32 * 0.5'f32)
    let a = base + off
    let b = newBullet(t.pos.x, t.pos.y, newVector2f(cos(a), sin(a)), w.speed, w.damage,
                      fromPlayer = t.team != ttEnemy)
    if w.radius > 0: b.radius = w.radius
    if w.lifetime > 0: b.lifetime = w.lifetime
    if w.color.a > 0: b.colorOverride = w.color
    b.modKind = w.kind
    b.modPierce = pierce
    game.bullets.add(b)

# ----------------------------------------------------------------- hazards ----
proc applyHazard(game: Game, t: ModThing, grid: SpatialGrid, maxEnemyR: float32) =
  let hz = t.hazard
  if hz.hurts in {htPlayer, htAll} and game.state == gsPlaying and game.player.hp > 0 and
     hazardHits(t, game.player.pos, game.player.radius):
    let died = takeDamage(game.player, hz.damage)
    if game.player.lastDamageTaken > 0.001:
      trackPlayerDamage(game, etEnvironment)
      game.showPlayerDamageTaken(dtDefault)
    if died: beginPlayerDeathSequence(game, dcHazard)
  if hz.hurts in {htEnemies, htAll}:
    let reach = max(max(t.radius, hz.length), 0.5'f32 * sqrt(t.w * t.w + t.h * t.h)) + maxEnemyR
    for idx in grid.nearby(t.pos, reach):
      if idx >= game.enemies.len: continue
      let e = game.enemies[idx]
      if e.hp <= 0 or not hazardHits(t, e.pos, e.radius): continue
      let dealt = damageEnemy(e, hz.damage, consumesDiamondShield = false)
      if dealt > 0: showDamage(game, e.pos, dealt, true)

proc tickHazard(game: Game, t: ModThing, dt: float32, grid: SpatialGrid, maxEnemyR: float32) =
  t.hazard.timer += dt
  var stepDt = dt
  if t.hazard.phase == 0:
    if t.hazard.timer < t.hazard.warn: return
    # the warning is over: it goes live this very frame
    t.hazard.phase = 1
    t.hazard.timer = 0
    t.hazard.tickTimer = 0
    stepDt = 0
    let f = hazardTriggers.getOrDefault(t.id)
    if f.fn.isFn:
      var r: RetVals
      discard callKind(f.owner, f.fn, [wrapThing(t), wrapGame(game)], r)
  if t.hazard.phase == 1:
    t.hazard.tickTimer -= stepDt
    if t.hazard.tickTimer <= 0:
      applyHazard(game, t, grid, maxEnemyR)
      t.hazard.tickTimer = if t.hazard.tick > 0: t.hazard.tick else: 1.0e9'f32
    if t.hazard.timer >= t.hazard.active:
      t.hazard.phase = 2
  if t.hazard.phase >= 2:
    removeThing(t)

# ------------------------------------------------------------------ update ----
proc nearestEnemy(game: Game, p: Vector2f): Enemy =
  var bestD = 1.0e12'f32
  for e in game.enemies:
    if e.hp <= 0: continue
    let dx = e.pos.x - p.x
    let dy = e.pos.y - p.y
    let d = dx * dx + dy * dy
    if d < bestD:
      bestD = d
      result = e

proc moveThing(game: Game, t: ModThing, dt: float32) =
  case t.motion
  of tmStatic: discard
  of tmFree:
    t.pos.x += t.vel.x * dt
    t.pos.y += t.vel.y * dt
    if t.friction > 0:
      let k = max(0'f32, 1 - t.friction * dt)
      t.vel.x *= k
      t.vel.y *= k
    if t.bounce > 0:
      let r = t.extentRadius
      let w = game.screenWidth.float32
      let h = game.screenHeight.float32
      if (t.pos.x < r and t.vel.x < 0) or (t.pos.x > w - r and t.vel.x > 0): t.vel.x = -t.vel.x * t.bounce
      if (t.pos.y < r and t.vel.y < 0) or (t.pos.y > h - r and t.vel.y > 0): t.vel.y = -t.vel.y * t.bounce
  of tmFollowPlayer, tmChasePlayer, tmChaseEnemy:
    var target = game.player.pos
    var stopAt = if t.motion == tmFollowPlayer: max(t.orbitRadius, 1'f32) else: 0'f32
    if t.motion == tmChaseEnemy:
      let e = nearestEnemy(game, t.pos)
      if e.isNil:
        t.vel = newVector2f(0, 0)
        return
      target = e.pos
      stopAt = e.radius * 0.5'f32
    let dx = target.x - t.pos.x
    let dy = target.y - t.pos.y
    let d = sqrt(dx * dx + dy * dy)
    if d > stopAt and d > 0.001:
      let step = min(t.speed * dt, d - stopAt)
      t.vel = newVector2f(dx / d * t.speed, dy / d * t.speed)
      t.pos.x += dx / d * step
      t.pos.y += dy / d * step
    else:
      t.vel = newVector2f(0, 0)
  of tmOrbitPlayer:
    t.orbitAngle += t.speed * dt   # degrees per second
    let a = degToRad(t.orbitAngle)
    t.pos = newVector2f(game.player.pos.x + cos(a) * t.orbitRadius,
                        game.player.pos.y + sin(a) * t.orbitRadius)
  t.angle += t.spin * dt

proc updateThings*(game: Game, simDt, effectiveDt: float32, grid: SpatialGrid, maxEnemyR: float32) =
  ## One frame of every thing (see the module comment for the order). `grid`
  ## holds game.enemies as of this frame; nothing here adds or deletes enemies.
  if game.modThings.len == 0: return
  let player = game.player
  var i = 0
  while i < game.modThings.len:   # index loop: a callback may not add (spawns queue)
    let t = game.modThings[i]
    inc i
    if not t.alive: continue
    let dt = if t.team == ttPlayer: simDt else: effectiveDt
    let ki = kindOf(t)
    if t.hitFlash > 0: t.hitFlash = max(0'f32, t.hitFlash - dt)
    # 1. motion
    moveThing(game, t, dt)
    # 2. lifetime
    t.age += dt
    if t.lifetime > 0 and t.age >= t.lifetime and t.hazard.shape == hzNone:
      var r: RetVals
      discard thingCall(t, proc (k: ThingKind): ScriptValue {.nimcall.} = k.onExpire,
                        [wrapThing(t), wrapGame(game)], r)
      removeThing(t)
      continue
    # 3. hazard phases (the telegraph is always drawn: hazards must be fair)
    if t.hazard.shape != hzNone:
      tickHazard(game, t, dt, grid, maxEnemyR)
      if not t.alive: continue
    # 4. turret fire
    if ki >= 0 and thingKinds[ki].weapon.enabled:
      t.weaponTimer -= dt
      if t.weaponTimer <= 0:
        if fireWeapon(game, t, thingKinds[ki].weapon):
          t.weaponTimer = max(0.05'f32, thingKinds[ki].weapon.interval)
        else:
          t.weaponTimer = 0
    if t.contactTimer > 0: t.contactTimer -= dt
    let interval = if t.contactInterval > 0: t.contactInterval else: DefaultContactInterval
    # 5. contact with the player
    if tfPickup notin t.flags and game.state == gsPlaying and player.hp > 0 and
       overlapsCircle(t, player.pos, player.radius):
      var touched = false
      if t.contactTimer <= 0:
        if ki >= 0 and thingKinds[ki].onTouchPlayer.isFn:
          var r: RetVals
          discard callKind(thingKinds[ki].owner, thingKinds[ki].onTouchPlayer,
                           [wrapThing(t), wrapPlayer(player), wrapGame(game)], r)
          touched = true
        if t.contactDamage > 0 and t.hurtsPlayer:
          let died = takeDamage(player, t.contactDamage)
          if player.lastDamageTaken > 0.001:
            trackPlayerDamage(game, etEnvironment)
            game.showPlayerDamageTaken(dtDefault)
          if died: beginPlayerDeathSequence(game, dcHazard)
          touched = true
      if touched: t.contactTimer = interval
      if not t.alive: continue
    # 6. contact with enemies
    if t.hurtsEnemies and (t.contactDamage > 0 or (ki >= 0 and thingKinds[ki].onTouchEnemy.isFn)) and
       t.contactTimer <= 0:
      var touched = false
      for idx in grid.nearby(t.pos, t.extentRadius + maxEnemyR):
        if idx >= game.enemies.len: continue
        let e = game.enemies[idx]
        if e.hp <= 0 or not overlapsCircle(t, e.pos, e.radius): continue
        touched = true
        if ki >= 0 and thingKinds[ki].onTouchEnemy.isFn:
          var r: RetVals
          discard callKind(thingKinds[ki].owner, thingKinds[ki].onTouchEnemy,
                           [wrapThing(t), wrapEnemy(e), wrapGame(game)], r)
        if t.contactDamage > 0:
          let dealt = damageEnemy(e, t.contactDamage, consumesDiamondShield = false)
          if dealt > 0: showDamage(game, e.pos, dealt, true)
        if not t.alive: break
      if touched: t.contactTimer = interval
      if not t.alive: continue
    # 7. solid: push the player and regular enemies out
    if tfSolid in t.flags:
      if overlapsCircle(t, player.pos, player.radius):
        pushOut(t, player.pos, player.radius)
      for idx in grid.nearby(t.pos, t.extentRadius + maxEnemyR):
        if idx >= game.enemies.len: continue
        let e = game.enemies[idx]
        if e.isBoss or e.hp <= 0: continue
        if overlapsCircle(t, e.pos, e.collisionRadius):
          pushOut(t, e.pos, e.collisionRadius)
    # 8. pickup and magnet
    if tfPickup in t.flags and game.state == gsPlaying:
      let dx = player.pos.x - t.pos.x
      let dy = player.pos.y - t.pos.y
      let d = sqrt(dx * dx + dy * dy)
      if tfMagnet in t.flags and d < MagnetRange and d > 0.001:
        let pull = max(t.speed, 320'f32) * dt
        t.pos.x += dx / d * min(pull, d)
        t.pos.y += dy / d * min(pull, d)
      if overlapsCircle(t, player.pos, player.radius):
        var keep = false
        if ki >= 0 and thingKinds[ki].onPickup.isFn:
          var r: RetVals
          if callKind(thingKinds[ki].owner, thingKinds[ki].onPickup,
                      [wrapThing(t), wrapPlayer(player), wrapGame(game)], r) and
             r.count > 0 and r.first.kind == vkBool and not r.first.b:
            keep = true   # onPickup returned false: not taken (yet)
        if not keep:
          removeThing(t)
          continue
    # 9. the kind's own update
    if ki >= 0 and thingKinds[ki].update.isFn:
      t.updateTimer += dt
      let every = thingKinds[ki].updateEvery
      if every <= 0 or t.updateTimer >= every:
        let step = t.updateTimer
        t.updateTimer = 0
        var r: RetVals
        discard callKind(thingKinds[ki].owner, thingKinds[ki].update,
                         [wrapThing(t), vnum(step.float64), wrapGame(game)], r)

proc sweepThings*(game: Game) =
  ## Drop dead and removed things (and what was kept about them).
  if game.modThings.len == 0: return
  var gone = false
  for t in game.modThings:
    if not t.alive:
      gone = true
      break
  if not gone: return
  var kept = newSeqOfCap[ModThing](game.modThings.len)
  for t in game.modThings:
    if t.alive: kept.add(t)
    else:
      dropEntityData(entityKey(EdThing, t.id))
      hazardTriggers.del(t.id)
  game.modThings = kept

# --------------------------------------------------------- bullets vs things ----
proc blocks(t: ModThing, b: Bullet): bool {.inline.} =
  ## A blocker stops the other side's bullets (a neutral one stops all).
  tfBlocksBullets in t.flags and
    (t.team == ttNeutral or (t.team == ttPlayer) != b.fromPlayer)

proc hitBy(t: ModThing, b: Bullet): bool {.inline.} =
  tfHitByBullets in t.flags and
    (t.team == ttNeutral or (t.team == ttPlayer) != b.fromPlayer)

proc collideThingBullets*(game: Game) =
  ## Bullets against things, outside the bullet loop: build a grid over the
  ## things, walk the bullets once, mark the ones that hit, compact once.
  if game.modThings.len == 0 or game.bullets.len == 0: return
  var any = false
  thingGridMaxR = 0
  for t in game.modThings:
    if t.alive and (tfBlocksBullets in t.flags or tfHitByBullets in t.flags):
      any = true
      thingGridMaxR = max(thingGridMaxR, t.extentRadius)
  if not any: return
  thingGrid.rebuild(game.modThings, ThingGridCell, -ThingGridMargin, -ThingGridMargin,
                    game.screenWidth.float32 + ThingGridMargin,
                    game.screenHeight.float32 + ThingGridMargin)
  var spent = initHashSet[int]()
  for bi, b in game.bullets:
    if b.isFrozenByNova: continue
    for ti in thingGrid.nearby(b.pos, b.radius + thingGridMaxR):
      let t = game.modThings[ti]
      if not t.alive or not (blocks(t, b) or hitBy(t, b)): continue
      if not overlapsCircle(t, b.pos, b.radius): continue
      if hitBy(t, b):
        var dmg = b.damage
        let ki = kindOf(t)
        if ki >= 0 and thingKinds[ki].onHit.isFn:
          var r: RetVals
          if callKind(thingKinds[ki].owner, thingKinds[ki].onHit,
                      [wrapThing(t), wrapBullet(b), vnum(dmg.float64)], r):
            dmg = max(0'f32, numResult(r, dmg))
        let dealt = damageThing(game, t, dmg, "bullet")
        if dealt > 0 and b.fromPlayer: showDamage(game, t.pos, dealt, true)
      spawnExplosionPooled(game.particlePool, b.pos.x, b.pos.y, t.color, 3)
      spent.incl(bi)
      break
  if spent.len == 0: return
  var kept = newSeqOfCap[Bullet](game.bullets.len)
  for bi, b in game.bullets:
    if bi in spent:
      if b.fromPlayer: trackBulletDespawn(game, b, true)
    else:
      kept.add(b)
  game.bullets = kept

# ------------------------------------------------------------------- draw ----
proc drawHazard(t: ModThing, time: float32) =
  let hz = t.hazard
  var c = t.color
  let pulse = 0.5'f32 + 0.5'f32 * sin(time * 12)
  let fillA = if hz.phase == 0: uint8(40 + 50 * pulse) else: 170'u8
  let lineA = if hz.phase == 0: 230'u8 else: 255'u8
  let fill = Color(r: c.r, g: c.g, b: c.b, a: fillA)
  c.a = lineA
  # how far the warning has run, as a growing inner shape
  let progress = if hz.phase == 0 and hz.warn > 0: clamp(hz.timer / hz.warn, 0'f32, 1'f32) else: 1'f32
  case hz.shape
  of hzNone: discard
  of hzCircle:
    drawDisc(Vector2(x: t.pos.x, y: t.pos.y), t.radius * (if hz.phase == 0: progress else: 1), fill)
    drawCircleOutline(t.pos.x.int32, t.pos.y.int32, t.radius, c)
  of hzRect:
    let r = Rectangle(x: t.pos.x - t.w * 0.5'f32, y: t.pos.y - t.h * 0.5'f32, width: t.w, height: t.h)
    let inner = Rectangle(x: t.pos.x - t.w * 0.5'f32 * progress, y: t.pos.y - t.h * 0.5'f32 * progress,
                          width: t.w * progress, height: t.h * progress)
    drawRectangle(if hz.phase == 0: inner else: r, fill)
    drawRectOutline(r, 1, c)
  of hzLine:
    let a = degToRad(t.angle)
    let e = Vector2(x: t.pos.x + cos(a) * hz.length, y: t.pos.y + sin(a) * hz.length)
    let s = Vector2(x: t.pos.x, y: t.pos.y)
    drawLine(s, e, max(1'f32, t.radius * 2 * (if hz.phase == 0: progress else: 1)), fill)
    drawStroke(s, e, 1, c)
  of hzRing:
    drawRing(Vector2(x: t.pos.x, y: t.pos.y), hz.inner, t.radius, 0, 360, 48, fill)
    drawCircleOutline(t.pos.x.int32, t.pos.y.int32, t.radius, c)
    drawCircleOutline(t.pos.x.int32, t.pos.y.int32, max(1'f32, hz.inner), c)

proc drawThingBody(t: ModThing, k: int) =
  let tint = if t.hitFlash > 0: Color(r: 255, g: 255, b: 255, a: 255) else: t.color
  let scale = if t.scale > 0: t.scale else: 1'f32
  if k >= 0 and thingKinds[k].look.hasLook:
    let size = (if t.shape == tsRect: max(t.w, t.h) else: t.radius * 2) * scale
    drawReplacement(thingKinds[k].look, t.pos.x, t.pos.y, size, t.angle,
                    if t.hitFlash > 0: Color(r: 255, g: 200, b: 200, a: 255) else: White,
                    animPhase = t.id.float * 0.618, key = animKey(cast[pointer](t)))
    return
  if t.shape == tsRect:
    let w = t.w * scale
    let h = t.h * scale
    drawRectangle(Rectangle(x: t.pos.x, y: t.pos.y, width: w, height: h),
                  Vector2(x: w * 0.5'f32, y: h * 0.5'f32), t.angle, tint)
  else:
    drawDisc(Vector2(x: t.pos.x, y: t.pos.y), t.radius * scale, tint)
    let rim = Color(r: uint8(min(255, t.color.r.int + 60)), g: uint8(min(255, t.color.g.int + 60)),
                    b: uint8(min(255, t.color.b.int + 60)), a: t.color.a)
    drawCircleOutline(t.pos.x.int32, t.pos.y.int32, t.radius * scale, rim)

proc drawThings*(game: Game, layer: ThingLayer) =
  ## World coordinates. Hazards always draw their telegraph, whatever their
  ## kind or a script does: hazards must be fair.
  if game.modThings.len == 0: return
  for t in game.modThings:
    if not t.alive or t.layer != layer: continue
    if t.hazard.shape != hzNone:
      drawHazard(t, game.time)
      continue
    let k = kindOf(t)
    var drawn = false
    if k >= 0 and thingKinds[k].draw.isFn and not modCtx.inPvP:
      let prev = modCtx.drawing
      modCtx.drawing = dtWorld
      var r: RetVals
      drawn = callKind(thingKinds[k].owner, thingKinds[k].draw, [wrapThing(t)], r)
      modCtx.drawing = prev
    if not drawn: drawThingBody(t, k)
    if k >= 0 and thingKinds[k].hpBar and t.maxHp > 0 and t.hp < t.maxHp:
      let w = max(20'f32, t.extentRadius * 2)
      let y = t.pos.y - t.extentRadius - 8
      drawRectangle(Rectangle(x: t.pos.x - w * 0.5'f32, y: y, width: w, height: 3),
                    Color(r: 20, g: 20, b: 20, a: 200))
      drawRectangle(Rectangle(x: t.pos.x - w * 0.5'f32, y: y,
                              width: w * clamp(t.hp / t.maxHp, 0'f32, 1'f32), height: 3), t.color)

# ---------------------------------------------------------------- joining ----
proc joinThing*(game: Game, t: ModThing, callback: ScriptValue, owner: int): bool =
  ## processModActions: a built thing joins the arena (false: the cap is full).
  let p = modPendingThings.find(t)
  if p >= 0: modPendingThings.delete(p)
  if not t.alive: return false
  if game.modThings.len >= MaxModThings: return false
  game.modThings.add(t)
  var r: RetVals
  discard thingCall(t, proc (k: ThingKind): ScriptValue {.nimcall.} = k.onSpawn,
                    [wrapThing(t), wrapGame(game)], r)
  if callback.isFn: discard callKind(owner, callback, [wrapThing(t)], r)
  modThingSpawn(t)
  true

proc keepPersistentThings*(game: Game) =
  ## A roguelite room change: only `persistent` things follow the player.
  if game.modThings.len == 0: return
  var kept: seq[ModThing]
  for t in game.modThings:
    if tfPersistent in t.flags and t.alive: kept.add(t)
    else:
      dropEntityData(entityKey(EdThing, t.id))
      hazardTriggers.del(t.id)
  game.modThings = kept
