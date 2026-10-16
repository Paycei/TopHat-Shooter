## The script-facing API of the 2D arena's mod entities (MODDING.md "Things,
## hazards and projectiles"): register.thing, spawn.thing, spawn.hazard,
## register.projectile, spawn.bullet's kind/pierce/homing, game:explode,
## game:things / game:thingsNear and the thing wrapper.
##
## HIGH layer like mod_api (gameplay never imports it): the loader installs it
## right after mod_3d. The registries and call-site helpers it fills live in the
## LOW module mod_registry; the simulation in game/things.nim.
##
## Rules it keeps: every table here is strict (an unknown key is an error that
## names it); spawns build their object now, return the handle and join at the
## end of the frame through the mod action queue; thing fields go through
## mod_deep, so new ModThing fields are scriptable with no code here.

import std/[strutils, math, tables]
import raylib
import ../types, ../particle_types, ../player, ../particle_pool, ../d_systems, ../bullet
import ../game/[combat, death, things]
import mod_assets
import lua_bridge, mod_hooks, mod_reflect, mod_deep, mod_api, mod_registry

type
  ThingBox = ref object of RootObj
    t: ModThing
    g: Game              ## the run it was made in

var
  thingClass: UdClass
  thingMethods: ScriptTable

const
  ThingReadOnly = ["id", "kind"]
  FlagNames = ["solid", "blocksBullets", "hitByBullets", "pickup", "magnet", "persistent",
               "invulnerable"]
  ThingKindKeys = ["id", "tag", "shape", "radius", "w", "h", "team", "motion", "speed", "friction",
                   "bounce", "orbitRadius", "orbitAngle", "angle", "spin", "hp", "contactDamage",
                   "contactInterval", "lifetime", "layer", "color", "scale", "solid", "blocksBullets",
                   "hitByBullets", "pickup", "magnet", "persistent", "invulnerable", "texture", "model",
                   "look", "updateEvery", "hpBar", "weapon", "update", "draw", "onSpawn",
                   "onTouchPlayer", "onTouchEnemy", "onHit", "onDamaged", "onDeath", "onExpire", "onPickup"]
  SpawnThingKeys = ["tag", "shape", "radius", "w", "h", "team", "motion", "speed", "friction", "bounce",
                    "orbitRadius", "orbitAngle", "angle", "spin", "hp", "maxHp", "contactDamage",
                    "contactInterval", "lifetime", "layer", "color", "scale", "solid", "blocksBullets",
                    "hitByBullets", "pickup", "magnet", "persistent", "invulnerable", "vx", "vy",
                    "onSpawn"]
  WeaponKeys = ["interval", "range", "speed", "damage", "count", "spread", "kind", "radius",
                "lifetime", "color"]
  HazardKeys = ["shape", "x", "y", "r", "w", "h", "length", "angle", "inner", "warn", "active",
                "tick", "damage", "hurts", "color", "onTrigger", "layer", "tag"]
  ProjectileKeys = ["id", "update", "draw", "onHit", "onHitPlayer", "onExpire", "pierce", "homing"]
  ExplodeKeys = ["hurts", "color", "shake"]
  ShootKeys = ["speed", "damage", "kind", "radius", "lifetime", "color", "count", "spread", "pierce"]

# ------------------------------------------------------------- helpers ----
proc finite(vm: VM, v: ScriptValue, what: string): float32 =
  if v.kind == vkNumber and abs(v.n) < 1.0e9: return v.n.float32
  if v.kind == vkNumber: vm.runtimeError(what & " must be a finite number")
  vm.runtimeError(what & " must be a number, got " & typeName(v))

proc enumField[E: enum](vm: VM, v: ScriptValue, what: string): E =
  if v.kind != vkString: vm.runtimeError(what & " must be a name")
  for e in E:
    if $e == v.str.s: return e
  var names: seq[string]
  for e in E: names.add($e)
  vm.runtimeError(what & ": unknown value '" & v.str.s & "' (" & names.join(", ") & ")")

proc flagOf(name: string): ThingFlag =
  case name
  of "solid": tfSolid
  of "blocksBullets": tfBlocksBullets
  of "hitByBullets": tfHitByBullets
  of "pickup": tfPickup
  of "magnet": tfMagnet
  of "persistent": tfPersistent
  else: tfInvulnerable

proc fnField(vm: VM, t: ScriptTable, key, what: string): ScriptValue =
  result = rawGetStr(t, key)
  if result.kind notin {vkNil, vkFunction, vkNative}:
    vm.runtimeError(what & "." & key & " must be a function")

proc applyThingFields(vm: VM, th: ModThing, t: ScriptTable, what: string) =
  ## The instance fields register.thing's template and spawn.thing's overrides
  ## share (validated by the caller's strict key list).
  for (k, v) in pairsCursor(t):
    let key = k.str.s
    case key
    of "tag":
      if v.kind != vkString: vm.runtimeError(what & ".tag must be a string")
      th.tag = v.str.s
    of "shape": th.shape = enumField[ThingShape](vm, v, what & ".shape")
    of "team": th.team = enumField[ThingTeam](vm, v, what & ".team")
    of "motion": th.motion = enumField[ThingMotion](vm, v, what & ".motion")
    of "layer": th.layer = enumField[ThingLayer](vm, v, what & ".layer")
    of "radius": th.radius = max(0'f32, vm.finite(v, what & ".radius"))
    of "w": th.w = max(0'f32, vm.finite(v, what & ".w"))
    of "h": th.h = max(0'f32, vm.finite(v, what & ".h"))
    of "speed": th.speed = vm.finite(v, what & ".speed")
    of "friction": th.friction = max(0'f32, vm.finite(v, what & ".friction"))
    of "bounce": th.bounce = max(0'f32, vm.finite(v, what & ".bounce"))
    of "orbitRadius": th.orbitRadius = max(0'f32, vm.finite(v, what & ".orbitRadius"))
    of "orbitAngle": th.orbitAngle = vm.finite(v, what & ".orbitAngle")
    of "angle": th.angle = vm.finite(v, what & ".angle")
    of "spin": th.spin = vm.finite(v, what & ".spin")
    of "hp":
      th.hp = max(0'f32, vm.finite(v, what & ".hp"))
      th.maxHp = th.hp
    of "maxHp": th.maxHp = max(0'f32, vm.finite(v, what & ".maxHp"))
    of "contactDamage": th.contactDamage = max(0'f32, vm.finite(v, what & ".contactDamage"))
    of "contactInterval": th.contactInterval = max(0'f32, vm.finite(v, what & ".contactInterval"))
    of "lifetime": th.lifetime = max(0'f32, vm.finite(v, what & ".lifetime"))
    of "color": th.color = parseColor(vm, v, what & ".color")
    of "scale": th.scale = max(0.01'f32, vm.finite(v, what & ".scale"))
    of "vx": th.vel.x = vm.finite(v, what & ".vx")
    of "vy": th.vel.y = vm.finite(v, what & ".vy")
    else:
      if key in FlagNames:
        if truthy(v): th.flags.incl(flagOf(key)) else: th.flags.excl(flagOf(key))

proc defaultThing(): ModThing =
  ModThing(radius: 16, w: 32, h: 32, motion: tmStatic, speed: 120, color: Color(r: 200, g: 200, b: 220, a: 255),
           scale: 1, layer: tlNormal, team: ttNeutral)

proc copyThing(src: ModThing): ModThing =
  result = ModThing()
  result[] = src[]

proc newThingId(g: Game): int =
  inc g.modWorld.nextThingId
  g.modWorld.nextThingId

# ------------------------------------------------------------- wrapper ----
proc wrapThingFor(t: ModThing): ScriptValue {.nimcall.} =
  if thingClass.isNil: NilValue
  else: vud(Userdata(cls: thingClass, box: ThingBox(t: t, g: modCtx.game), key: cast[pointer](t)))

proc unwrapThing*(v: ScriptValue): ModThing =
  if v.kind == vkUserdata and v.ud.cls == thingClass: ThingBox(v.ud.box).t else: nil

proc selfThing(vm: VM, args: openArray[ScriptValue], fname: string): ModThing =
  result = unwrapThing(arg(args, 0))
  if result.isNil: vm.runtimeError("thing:" & fname & "() needs a thing (call it with ':')")

proc thingValid(b: ThingBox): bool =
  let g = modCtx.game
  not g.isNil and b.g == g and b.t.alive and (b.t in g.modThings or b.t in modPendingThings)

proc makeThingClass() =
  thingClass = UdClass(name: "thing", cached: true)
  thingClass.index = proc (vm: VM, ud: Userdata, key: ScriptValue): ScriptValue =
    let m = rawGet(thingMethods, key)
    if m.kind != vkNil: return m
    let t = ThingBox(ud.box).t
    let name = keyName(key)
    if name == "data": return vm.entityDataValue(EdThing, t.id, "thing")
    if name in FlagNames: return vbool(flagOf(name) in t.flags)
    if name == "dead": return vbool(not t.alive)
    var found = false
    result = posGet(t.pos, t.vel, name, found)
    if found: return
    result = deepGet(t, name, "thing", found)
    if not found: vm.runtimeError("thing has no field '" & name & "'")
  thingClass.newindex = proc (vm: VM, ud: Userdata, key, val: ScriptValue) =
    let t = ThingBox(ud.box).t
    let name = keyName(key)
    if name == "data":
      vm.setEntityData(EdThing, t.id, val, "thing")
      return
    if name in ThingReadOnly or name == "flags":
      vm.runtimeError("thing." & name & " is read-only" &
                      (if name == "flags": " (set thing.solid, thing.pickup... instead)" else: ""))
    if name in FlagNames:
      if truthy(val): t.flags.incl(flagOf(name)) else: t.flags.excl(flagOf(name))
      return
    if posSet(vm, t.pos, t.vel, name, val): return
    if not deepSet(vm, t, name, val, "thing"):
      vm.runtimeError("thing has no field '" & name & "'")
  thingClass.tostr = proc (ud: Userdata): string =
    let t = ThingBox(ud.box).t
    "thing #" & $t.id & " (" & t.kind & ")"
  wrapThingImpl = wrapThingFor

# ----------------------------------------------------------- spawning ----
proc buildThing(vm: VM, kind: int, g: Game, x, y: float32): ModThing =
  result = if kind >= 0: copyThing(thingKinds[kind].proto) else: defaultThing()
  result.kind = if kind >= 0: thingKinds[kind].key else: HazardKind
  result.id = newThingId(g)
  result.pos = newVector2f(x, y)
  if result.maxHp <= 0 and result.hp > 0: result.maxHp = result.hp
  result.flags.excl({tfDead, tfRemoved})
  if kind >= 0 and thingKinds[kind].weapon.enabled:
    result.weaponTimer = thingKinds[kind].weapon.interval * 0.5'f32

proc queueThing(vm: VM, th: ModThing, owner: int, cb: ScriptValue, fname: string) =
  if modActionsFull(): vm.runtimeError(fname & ": too many spawns queued this frame")
  let g = modCtx.game
  if g.modThings.len + modPendingThings.len >= MaxModThings:
    vm.runtimeError(fname & ": the arena already holds " & $MaxModThings & " things")
  modPendingThings.add(th)
  queueModAction(ModAction(kind: makJoinThing, owner: owner, thing: th, callback: cb))

proc readWeapon(vm: VM, v: ScriptValue, what: string): ThingWeapon =
  if v.kind != vkTable: vm.runtimeError(what & " must be a table")
  vm.checkKeys(v.tbl, WeaponKeys, what)
  result = ThingWeapon(enabled: true, interval: 1, range: 300, speed: 320, damage: 1, count: 1, spread: 12)
  for (k, x) in pairsCursor(v.tbl):
    let key = k.str.s
    case key
    of "kind":
      if x.kind != vkString: vm.runtimeError(what & ".kind must be a projectile kind")
      if findProjectileKind(x.str.s) < 0:
        vm.runtimeError(what & ".kind: no projectile kind '" & x.str.s & "' (register.projectile it first)")
      result.kind = x.str.s
    of "color": result.color = parseColor(vm, x, what & ".color")
    of "count": result.count = clamp(int(vm.finite(x, what & ".count")), 1, 32)
    of "interval": result.interval = max(0.05'f32, vm.finite(x, what & ".interval"))
    of "range": result.range = max(0'f32, vm.finite(x, what & ".range"))
    of "speed": result.speed = vm.finite(x, what & ".speed")
    of "damage": result.damage = max(0'f32, vm.finite(x, what & ".damage"))
    of "spread": result.spread = vm.finite(x, what & ".spread")
    of "radius": result.radius = max(0'f32, vm.finite(x, what & ".radius"))
    of "lifetime": result.lifetime = max(0'f32, vm.finite(x, what & ".lifetime"))
    else: discard

proc scriptBullet(vm: VM, owner: int, x, y, angleDeg: float32, opts: ScriptTable,
                  fromPlayer: bool, what: string): ScriptValue =
  ## thing:shoot's bullets (handles, joining at the end of the frame).
  var speed = 320'f32
  var damage = 1'f32
  var radius, lifetime, spread = 0'f32
  var count = 1
  var color = Color()
  var kind = ""
  var pierce = -1
  if not opts.isNil:
    vm.checkKeys(opts, ShootKeys, what)
    for (k, v) in pairsCursor(opts):
      case k.str.s
      of "speed": speed = vm.finite(v, what & ".speed")
      of "damage": damage = max(0'f32, vm.finite(v, what & ".damage"))
      of "radius": radius = max(0'f32, vm.finite(v, what & ".radius"))
      of "lifetime": lifetime = max(0'f32, vm.finite(v, what & ".lifetime"))
      of "spread": spread = vm.finite(v, what & ".spread")
      of "count": count = clamp(int(vm.finite(v, what & ".count")), 1, 32)
      of "color": color = parseColor(vm, v, what & ".color")
      of "pierce": pierce = max(0, int(vm.finite(v, what & ".pierce")))
      of "kind":
        if v.kind != vkString or findProjectileKind(v.str.s) < 0:
          vm.runtimeError(what & ".kind: unknown projectile kind")
        kind = v.str.s
      else: discard
  for i in 0 ..< count:
    if modActionsFull(): vm.runtimeError(what & ": too many spawns queued this frame")
    let a = degToRad(angleDeg + spread * (i.float32 - (count - 1).float32 * 0.5'f32))
    let b = newBullet(x, y, newVector2f(cos(a), sin(a)), speed, damage, fromPlayer = fromPlayer)
    if radius > 0: b.radius = radius
    if lifetime > 0: b.lifetime = lifetime
    if color.a > 0: b.colorOverride = color
    b.modKind = kind
    if pierce >= 0: b.modPierce = pierce.int32
    elif kind.len > 0: b.modPierce = projectileKinds[findProjectileKind(kind)].pierce
    modPendingBullets.add(b)
    queueModAction(ModAction(kind: makJoinBullet, owner: owner, bullet: b))
    if i == 0: result = wrapBullet(b)

# ------------------------------------------------------------- explode ----
proc explodeAt*(game: Game, x, y, r, dmg: float32, hurtPlayer, hurtEnemies: bool, color: Color,
                shake: string) =
  ## game:explode: hurts what is inside the circle now (no list changes).
  let c = newVector2f(x, y)
  if hurtEnemies:
    for e in game.enemies:
      if e.hp <= 0: continue
      let dx = e.pos.x - x
      let dy = e.pos.y - y
      let rr = r + e.radius
      if dx * dx + dy * dy <= rr * rr:
        let dealt = damageEnemy(e, dmg, consumesDiamondShield = false)
        if dealt > 0: showDamage(game, e.pos, dealt, true)
  for t in game.modThings:
    if not t.alive or tfInvulnerable in t.flags: continue
    let side = if t.team == ttPlayer: hurtPlayer elif t.team == ttEnemy: hurtEnemies
               else: hurtPlayer or hurtEnemies
    if side and overlapsCircle(t, c, r):
      discard damageThing(game, t, dmg, "explosion")
  if hurtPlayer and game.state == gsPlaying and game.player.hp > 0:
    let p = game.player
    let dx = p.pos.x - x
    let dy = p.pos.y - y
    let rr = r + p.radius
    if dx * dx + dy * dy <= rr * rr:
      let died = takeDamage(p, dmg)
      if p.lastDamageTaken > 0.001: game.showPlayerDamageTaken(dtDefault)
      if died: beginPlayerDeathSequence(game, dcHazard)
  spawnExplosionPooled(game.particlePool, x, y, color, clamp(int(r / 3), 8, 60))
  if shake.len > 0:
    try: addShake(game.dopamine.screenShake, parseEnum[ShakeIntensity]("si" & shake.capitalizeAscii))
    except ValueError: discard

# ------------------------------------------------------------- install ----
proc installWorld2D*(base: ScriptTable) =
  makeThingClass()
  thingMethods = newScriptTable()

  # ---- thing methods
  thingMethods.reg("fields") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ret.setRet(namesTable(deepNames(vm.selfThing(args, "fields"))))
  thingMethods.reg("valid") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## Still in the arena (or a spawn handle about to join it).
    discard vm.selfThing(args, "valid")
    ret.setRet(vbool(thingValid(ThingBox(arg(args, 0).ud.box))))
  thingMethods.reg("damage") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## thing:damage(amount) -> damage dealt (its onDamaged may change it)
    let t = vm.selfThing(args, "damage")
    let g = vm.requireRunGame()
    ret.setRet(vnum(damageThing(g, t, max(0.0, vm.checkNum(args, 1, "damage")).float32).float64))
  thingMethods.reg("heal") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    let t = vm.selfThing(args, "heal")
    let before = t.hp
    t.hp = min(t.maxHp, t.hp + max(0.0, vm.checkNum(args, 1, "heal")).float32)
    ret.setRet(vnum((t.hp - before).float64))
  thingMethods.reg("kill") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## Dies now: onDeath and the thingDeath hook run; it is gone at the end of the frame.
    let t = vm.selfThing(args, "kill")
    killThing(vm.requireRunGame(), t)
  thingMethods.reg("remove") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## Vanishes at the end of the frame: no death.
    removeThing(vm.selfThing(args, "remove"))
  thingMethods.reg("distanceTo") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## thing:distanceTo(x, y) or thing:distanceTo(entity)
    let t = vm.selfThing(args, "distanceTo")
    var x, y: float32
    let a1 = arg(args, 1)
    if a1.kind == vkUserdata:
      let o = unwrapThing(a1)
      let e = unwrapEnemy(a1)
      let p = unwrapPlayer(a1)
      let b = unwrapBullet(a1)
      if not o.isNil: (x, y) = (o.pos.x, o.pos.y)
      elif not e.isNil: (x, y) = (e.pos.x, e.pos.y)
      elif not p.isNil: (x, y) = (p.pos.x, p.pos.y)
      elif not b.isNil: (x, y) = (b.pos.x, b.pos.y)
      else: vm.argError("distanceTo", 1, "a thing, enemy, bullet or the player")
    else:
      x = vm.checkNum(args, 1, "distanceTo").float32
      y = vm.checkNum(args, 2, "distanceTo").float32
    ret.setRet(vnum(sqrt((t.pos.x - x) * (t.pos.x - x) + (t.pos.y - y) * (t.pos.y - y)).float64))
  thingMethods.reg("moveToward") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## thing:moveToward(x, y, speed, dt) -> true once it arrived
    let t = vm.selfThing(args, "moveToward")
    let x = vm.checkNum(args, 1, "moveToward").float32
    let y = vm.checkNum(args, 2, "moveToward").float32
    let step = max(0'f32, vm.checkNum(args, 3, "moveToward").float32 * vm.checkNum(args, 4, "moveToward").float32)
    let dx = x - t.pos.x
    let dy = y - t.pos.y
    let d = sqrt(dx * dx + dy * dy)
    if d <= step or d < 0.001:
      t.pos = newVector2f(x, y)
      ret.setRet(TrueValue)
    else:
      t.pos.x += dx / d * step
      t.pos.y += dy / d * step
      ret.setRet(FalseValue)
  thingMethods.reg("shoot") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## thing:shoot(angleDeg | {x =, y =} [, {speed, damage, kind, radius, lifetime,
    ##   color, count, spread, pierce}]) -> the (first) bullet. Its side is the
    ##   thing's team (an enemy thing fires at the player).
    let t = vm.selfThing(args, "shoot")
    discard vm.requireRunGame()
    let owner = vm.requireOwner("thing:shoot")
    let a1 = arg(args, 1)
    var angle = t.angle
    if a1.kind == vkNumber: angle = a1.n.float32
    elif a1.kind == vkTable:
      let (x, y) = parseVec(vm, a1, "thing:shoot target")
      angle = radToDeg(arctan2(y.float32 - t.pos.y, x.float32 - t.pos.x))
    elif a1.kind != vkNil: vm.argError("shoot", 1, "an angle in degrees or a {x, y} target")
    let opts = arg(args, 2)
    if opts.kind notin {vkNil, vkTable}: vm.argError("shoot", 2, "options must be a table")
    ret.setRet(vm.scriptBullet(owner, t.pos.x, t.pos.y, angle,
                               if opts.kind == vkTable: opts.tbl else: nil,
                               t.team != ttEnemy, "thing:shoot"))

  # ---- game methods
  proc listThings(g: Game, kind: string, x, y, r: float64, near: bool): ScriptValue =
    let t = newScriptTable()
    for th in g.modThings:
      if not th.alive: continue
      if kind.len > 0 and th.kind != kind and th.tag != kind: continue
      if near:
        let dx = th.pos.x.float64 - x
        let dy = th.pos.y.float64 - y
        if dx * dx + dy * dy > r * r: continue
      t.add(wrapThing(th))
    vtable(t)
  gameMethods.reg("things") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## game:things([kind or tag]) -> the live things
    let g = unwrapGame(arg(args, 0))
    if g.isNil: vm.runtimeError("game:things() needs the game (call it with ':'), and a run in progress")
    ret.setRet(listThings(g, vm.optStr(args, 1, "things", ""), 0, 0, 0, false))
  gameMethods.reg("thingsNear") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## game:thingsNear(x, y, radius [, kind or tag])
    let g = unwrapGame(arg(args, 0))
    if g.isNil: vm.runtimeError("game:thingsNear() needs the game (call it with ':'), and a run in progress")
    ret.setRet(listThings(g, vm.optStr(args, 4, "thingsNear", ""), vm.checkNum(args, 1, "thingsNear"),
                          vm.checkNum(args, 2, "thingsNear"), vm.checkNum(args, 3, "thingsNear"), true))
  gameMethods.reg("explode") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## game:explode(x, y, radius, damage [, {hurts = "enemies" | "player" | "all",
    ##   color = "#ffa040", shake = "small" | "medium" | ...}])
    let g = unwrapGame(arg(args, 0))
    if g.isNil: vm.runtimeError("game:explode() needs the game (call it with ':'), and a run in progress")
    discard vm.requireRunGame()
    var hurts = htEnemies
    var color = Color(r: 255, g: 160, b: 64, a: 255)
    var shake = ""
    let opts = arg(args, 5)
    if opts.kind == vkTable:
      vm.checkKeys(opts.tbl, ExplodeKeys, "game:explode")
      let h = rawGetStr(opts.tbl, "hurts")
      if h.kind != vkNil: hurts = enumField[HazardTargets](vm, h, "game:explode.hurts")
      let c = rawGetStr(opts.tbl, "color")
      if c.kind != vkNil: color = parseColor(vm, c, "game:explode.color")
      let s = rawGetStr(opts.tbl, "shake")
      if s.kind == vkString: shake = s.str.s
      elif s.kind != vkNil: vm.runtimeError("game:explode.shake must be a name")
    elif opts.kind != vkNil:
      vm.argError("explode", 5, "options must be a table")
    explodeAt(g, vm.checkNum(args, 1, "explode").float32, vm.checkNum(args, 2, "explode").float32,
              max(0.0, vm.checkNum(args, 3, "explode")).float32,
              max(0.0, vm.checkNum(args, 4, "explode")).float32,
              hurts in {htPlayer, htAll}, hurts in {htEnemies, htAll}, color, shake)

  # ---- register.thing / register.projectile
  let registerT = rawGetStr(base, "register").tbl
  registerT.reg("thing") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## local KIND = register.thing{id = "turret", shape = "circle", radius = 14,
    ##   team = "player", motion = "static", hp = 20, solid = true,
    ##   weapon = {interval = 0.6, range = 320, damage = 1}, update = fn, draw = fn, ...}
    let owner = vm.requireLoading("register.thing")
    let t = vm.checkTable(args, 0, "register.thing")
    vm.checkKeys(t, ThingKindKeys, "register.thing")
    let key = mods[owner].id & ":" & vm.checkName(t, "register.thing")
    if findThingKind(key) >= 0: vm.runtimeError("register.thing: '" & key & "' is already registered")
    var k = ThingKind(key: key, owner: owner, proto: defaultThing(), hpBar: true)
    let fields = newScriptTable()
    for (fk, fv) in pairsCursor(t):
      if fk.str.s in SpawnThingKeys: rawSet(fields, fk, fv)
    vm.applyThingFields(k.proto, fields, "register.thing")
    for (field, dest) in [("update", addr k.update), ("draw", addr k.draw), ("onSpawn", addr k.onSpawn),
                          ("onTouchPlayer", addr k.onTouchPlayer), ("onTouchEnemy", addr k.onTouchEnemy),
                          ("onHit", addr k.onHit), ("onDamaged", addr k.onDamaged),
                          ("onDeath", addr k.onDeath), ("onExpire", addr k.onExpire),
                          ("onPickup", addr k.onPickup)]:
      dest[] = vm.fnField(t, field, "register.thing")
    let ue = rawGetStr(t, "updateEvery")
    if ue.kind != vkNil: k.updateEvery = max(0'f32, vm.finite(ue, "register.thing.updateEvery"))
    let hb = rawGetStr(t, "hpBar")
    if hb.kind != vkNil: k.hpBar = truthy(hb)
    let w = rawGetStr(t, "weapon")
    if w.kind != vkNil: k.weapon = vm.readWeapon(w, "register.thing.weapon")
    let look = rawGetStr(t, "look")
    if look.kind notin {vkNil, vkTable}: vm.runtimeError("register.thing.look must be a table")
    let tex = rawGetStr(t, "texture")
    if tex.kind != vkNil: k.look.id = vm.textureId(tex, "register.thing.texture")
    let mdl = rawGetStr(t, "model")
    if mdl.kind != vkNil:
      k.look.model = vm.modelId(mdl, "register.thing.model")
      k.look.pose = vm.readPose(look, k.look.model, "register.thing.look")
    readScaleRotate(look, k.look)
    addThingKind(k)
    ret.setRet(vstr(key))
  registerT.reg("projectile") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## local BOLT = register.projectile{id = "bolt", pierce = 2, homing = 3,
    ##   update = fn(bullet, dt, game) -> true moves it yourself,
    ##   draw = fn(bullet), onHit = fn(bullet, enemy, damage) -> damage,
    ##   onHitPlayer = fn(bullet, player, damage) -> damage, onExpire = fn(bullet)}
    let owner = vm.requireLoading("register.projectile")
    let t = vm.checkTable(args, 0, "register.projectile")
    vm.checkKeys(t, ProjectileKeys, "register.projectile")
    let key = mods[owner].id & ":" & vm.checkName(t, "register.projectile")
    if findProjectileKind(key) >= 0: vm.runtimeError("register.projectile: '" & key & "' is already registered")
    var k = ProjectileKind(key: key, owner: owner)
    for (field, dest) in [("update", addr k.update), ("draw", addr k.draw), ("onHit", addr k.onHit),
                          ("onHitPlayer", addr k.onHitPlayer), ("onExpire", addr k.onExpire)]:
      dest[] = vm.fnField(t, field, "register.projectile")
    let p = rawGetStr(t, "pierce")
    if p.kind != vkNil: k.pierce = clamp(int(vm.finite(p, "register.projectile.pierce")), 0, 1000).int32
    let h = rawGetStr(t, "homing")
    if h.kind != vkNil: k.homing = max(0'f32, vm.finite(h, "register.projectile.homing"))
    addProjectileKind(k)
    ret.setRet(vstr(key))

  # ---- spawn.thing / spawn.hazard / spawn.bullet's new options
  let spawnT = rawGetStr(base, "spawn").tbl
  spawnT.reg("thing") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## spawn.thing(kind, x, y [, {overrides..., onSpawn = fn}]) -> the thing, at once
    let owner = vm.requireOwner("spawn.thing")
    let g = vm.requireRunGame()
    let kindName = vm.checkStr(args, 0, "thing")
    let ki = findThingKind(kindName)
    if ki < 0: vm.argError("thing", 0, "no thing kind '" & kindName & "' (register.thing it first)")
    let th = vm.buildThing(ki, g, vm.checkNum(args, 1, "thing").float32, vm.checkNum(args, 2, "thing").float32)
    var cb = NilValue
    let opts = arg(args, 3)
    if opts.kind == vkTable:
      vm.checkKeys(opts.tbl, SpawnThingKeys, "spawn.thing")
      vm.applyThingFields(th, opts.tbl, "spawn.thing")
      cb = vm.fnField(opts.tbl, "onSpawn", "spawn.thing")
    elif opts.kind != vkNil:
      vm.argError("thing", 3, "options must be a table")
    vm.queueThing(th, owner, cb, "spawn.thing")
    ret.setRet(wrapThing(th))
  spawnT.reg("hazard") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## spawn.hazard{shape = "circle" | "rect" | "line" | "ring", x, y, r | w, h |
    ##   length, angle | inner, warn = 1, active = 0.3, tick = 0, damage = 1,
    ##   hurts = "player" | "enemies" | "all", color, onTrigger = fn(hazard, game)}
    let owner = vm.requireOwner("spawn.hazard")
    let g = vm.requireRunGame()
    let t = vm.checkTable(args, 0, "spawn.hazard")
    vm.checkKeys(t, HazardKeys, "spawn.hazard")
    proc num(key: string, def: float32): float32 =
      let v = rawGetStr(t, key)
      if v.kind == vkNil: def else: vm.finite(v, "spawn.hazard." & key)
    let th = vm.buildThing(-1, g, num("x", 0), num("y", 0))
    th.motion = tmStatic
    th.color = Color(r: 255, g: 60, b: 60, a: 255)
    th.layer = tlBelow
    let shapeV = rawGetStr(t, "shape")
    th.hazard.shape = if shapeV.kind == vkNil: hzCircle else: enumField[HazardShape](vm, shapeV, "spawn.hazard.shape")
    if th.hazard.shape == hzNone: vm.runtimeError("spawn.hazard.shape cannot be \"none\"")
    th.radius = max(1'f32, num("r", 60))
    th.w = max(1'f32, num("w", 120))
    th.h = max(1'f32, num("h", 120))
    if th.hazard.shape == hzLine and rawGetStr(t, "r").kind == vkNil: th.radius = 12
    if th.hazard.shape == hzRect: th.shape = tsRect
    th.hazard.length = max(0'f32, num("length", 400))
    th.angle = num("angle", 0)
    th.hazard.inner = clamp(num("inner", th.radius * 0.6'f32), 0'f32, th.radius)
    th.hazard.warn = max(0'f32, num("warn", 1))
    th.hazard.active = max(0.01'f32, num("active", 0.3))
    th.hazard.tick = max(0'f32, num("tick", 0))
    th.hazard.damage = max(0'f32, num("damage", 1))
    let h = rawGetStr(t, "hurts")
    if h.kind != vkNil: th.hazard.hurts = enumField[HazardTargets](vm, h, "spawn.hazard.hurts")
    let c = rawGetStr(t, "color")
    if c.kind != vkNil: th.color = parseColor(vm, c, "spawn.hazard.color")
    let lay = rawGetStr(t, "layer")
    if lay.kind != vkNil: th.layer = enumField[ThingLayer](vm, lay, "spawn.hazard.layer")
    let tg = rawGetStr(t, "tag")
    if tg.kind == vkString: th.tag = tg.str.s
    elif tg.kind != vkNil: vm.runtimeError("spawn.hazard.tag must be a string")
    let trig = vm.fnField(t, "onTrigger", "spawn.hazard")
    if trig.isFn: hazardTriggers[th.id] = ScriptFn(owner: owner, fn: trig)
    vm.queueThing(th, owner, NilValue, "spawn.hazard")
    ret.setRet(wrapThing(th))

  # spawn.bullet: kind, pierce and homing on top of mod_api's own fields
  # (explosive and bounce stay out on purpose: the game's own read the player's
  # power-up levels; game:explode and a kind's onHit cover them).
  spawnT.reg("bullet") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## spawn.bullet{x, y, vx, vy, damage, radius, lifetime, fromPlayer, color,
    ##              kind = projectile kind, pierce = n, homing = true}
    let owner = vm.requireOwner("spawn.bullet")
    discard vm.requireRunGame()
    let t = vm.checkTable(args, 0, "bullet")
    if modActionsFull(): vm.runtimeError("spawn.bullet: too many spawns queued this frame")
    let b = vm.buildScriptBullet(t)
    let k = rawGetStr(t, "kind")
    if k.kind == vkString:
      let ki = findProjectileKind(k.str.s)
      if ki < 0: vm.runtimeError("spawn.bullet: no projectile kind '" & k.str.s & "' (register.projectile it first)")
      b.modKind = k.str.s
      b.modPierce = projectileKinds[ki].pierce
    elif k.kind != vkNil: vm.runtimeError("spawn.bullet.kind must be a projectile kind")
    let p = rawGetStr(t, "pierce")
    if p.kind == vkNumber: b.modPierce = clamp(int(p.n), 0, 1000).int32
    elif p.kind != vkNil: vm.runtimeError("spawn.bullet.pierce must be a number")
    let h = rawGetStr(t, "homing")
    if h.kind != vkNil: b.isHoming = truthy(h)
    modPendingBullets.add(b)
    queueModAction(ModAction(kind: makJoinBullet, owner: owner, bullet: b))
    ret.setRet(wrapBullet(b))
