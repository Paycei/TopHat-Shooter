## Registries of mod content that gameplay code reads, and their typed
## call-site helpers: thing kinds and projectile kinds (more registries join it
## as the API grows).
##
## Sits LOW like mod_hooks: it imports types, the script VM, mod_hooks and
## mod_assets, never a gameplay module, so gameplay modules (game/things.nim,
## consumable, survival, dungeon...) may import it. The script-facing side
## (register.thing, spawn.thing, the thing wrapper) lives in the HIGH module
## mod_world2d.nim, which fills the wrapThingImpl seam at startup.
##
## Content is keyed "<mod id>:<id>" and instances carry only that key (plain
## strings and numbers on snapshotted objects); behaviour lives here, on the
## kind. Every table registers a teardown, so a reload or a failed load wipes it.

import std/[tables, sets, math, strutils, json, os, times]
import raylib
import ../draw_prims
import ../types, ../particle_types, ../localization, ../save_system, ../utils
import ../ui/hud_dock
import ../render_context
import lua_bridge, mod_hooks, mod_assets, mod_reflect, mod_state

# ---------------------------------------------------------------- things ----
type
  ThingWeapon* = object
    ## A turret's declarative weapon: no per-frame script needed.
    enabled*: bool
    interval*, range*, speed*, damage*: float32
    count*: int
    spread*: float32        ## degrees between shots of one volley
    radius*: float32        ## bullet radius (0 = the game's default)
    lifetime*: float32      ## bullet lifetime (0 = the game's default)
    kind*: string           ## a projectile kind's key ("" = a plain bullet)
    color*: Color           ## alpha 0 = the game's colours

  ThingKind* = object
    key*: string            ## "<mod id>:<id>"
    owner*: int
    proto*: ModThing        ## the template every spawn copies
    look*: BodyReplace      ## a texture or a model (none: the native shape)
    updateEvery*: float32   ## seconds between `update` calls (0 = every frame)
    hpBar*: bool
    weapon*: ThingWeapon
    update*, draw*, onSpawn*, onTouchPlayer*, onTouchEnemy*, onHit*, onDamaged*,
      onDeath*, onExpire*, onPickup*: ScriptValue

  ProjectileKind* = object
    key*: string
    owner*: int
    pierce*: int32          ## enemies passed through before the bullet stops
    homing*: float32        ## turn rate toward the nearest target (0 = straight)
    update*, draw*, onHit*, onHitPlayer*, onExpire*: ScriptValue

const HazardKind* = "@hazard"   ## spawn.hazard's built-in kind

var
  thingKinds*: seq[ThingKind]
  thingKindIndex: Table[string, int]
  projectileKinds*: seq[ProjectileKind]
  projectileKindIndex: Table[string, int]
  hazardTriggers*: Table[int, ScriptFn]
    ## spawn.hazard's onTrigger, per hazard id. Per-instance callbacks are never
    ## saved: a resumed run's hazards keep hurting, they just call nobody.
  wrapThingImpl*: proc (t: ModThing): ScriptValue {.nimcall.}
    ## Filled by mod_world2d; nil (no wrapper) until then.

proc isFn*(v: ScriptValue): bool {.inline.} = v.kind in {vkFunction, vkNative}

proc wrapThing*(t: ModThing): ScriptValue =
  if t.isNil or wrapThingImpl.isNil: NilValue else: wrapThingImpl(t)

proc addThingKind*(k: ThingKind) =
  thingKindIndex[k.key] = thingKinds.len
  thingKinds.add(k)

proc findThingKind*(key: string): int =
  thingKindIndex.getOrDefault(key, -1)

proc addProjectileKind*(k: ProjectileKind) =
  projectileKindIndex[k.key] = projectileKinds.len
  projectileKinds.add(k)

proc findProjectileKind*(key: string): int =
  projectileKindIndex.getOrDefault(key, -1)

proc kindAlive(owner: int): bool {.inline.} =
  owner < 0 or owner >= mods.len or not mods[owner].disabled

proc liveOwner(owner: int): bool {.inline.} = kindAlive(owner)

# ------------------------------------------------------------- calling ----
proc callKind*(owner: int, fn: ScriptValue, args: openArray[ScriptValue], r: var RetVals): bool =
  ## Run one of a kind's callbacks (false: none, or it failed).
  if not fn.isFn or not kindAlive(owner): return false
  callAs(owner, fn, args, r)

proc thingCall*(t: ModThing, which: proc (k: ThingKind): ScriptValue {.nimcall.},
                args: openArray[ScriptValue], r: var RetVals): bool =
  ## A thing's kind callback; false when the kind has none (or is gone).
  let i = findThingKind(t.kind)
  if i < 0: return false
  let k = thingKinds[i]
  callKind(k.owner, which(k), args, r)

proc thingHas*(t: ModThing, which: proc (k: ThingKind): ScriptValue {.nimcall.}): bool =
  let i = findThingKind(t.kind)
  i >= 0 and which(thingKinds[i]).isFn and kindAlive(thingKinds[i].owner)

proc numResult*(r: RetVals, fallback: float32): float32 =
  ## A callback's number result (NaN and non-numbers keep `fallback`).
  if r.count > 0 and r.first.kind == vkNumber and r.first.n == r.first.n: r.first.n.float32
  else: fallback

# ---------------------------------------------------- projectile routes ----
proc projectileOf*(b: Bullet): int {.inline.} =
  if b.modKind.len == 0 or projectileKinds.len == 0: -1 else: findProjectileKind(b.modKind)

proc steerToward(b: Bullet, target: Vector2f, rate, dt: float32) =
  let speed = sqrt(b.vel.x * b.vel.x + b.vel.y * b.vel.y)
  let dx = target.x - b.pos.x
  let dy = target.y - b.pos.y
  let d = sqrt(dx * dx + dy * dy)
  if speed <= 0 or d <= 0.001: return
  let t = clamp(rate * dt, 0'f32, 1'f32)
  var nx = b.vel.x / speed * (1 - t) + dx / d * t
  var ny = b.vel.y / speed * (1 - t) + dy / d * t
  let n = sqrt(nx * nx + ny * ny)
  if n <= 0.0001: return
  nx /= n
  ny /= n
  b.vel = Vector2f(x: nx * speed, y: ny * speed)

proc modProjectileUpdate*(b: Bullet, dt: float32): bool =
  ## True: the kind moved the bullet itself this frame. A homing kind steers
  ## first (toward the nearest enemy, or the player for an enemy's shot).
  let i = projectileOf(b)
  if i < 0 or modCtx.inPvP: return false
  let k = projectileKinds[i]
  let g = modCtx.game
  if k.homing > 0 and not g.isNil:
    if b.fromPlayer:
      var best: Enemy = nil
      var bestD = 360'f32 * 360'f32
      for e in g.enemies:
        if e.hp <= 0: continue
        let dx = e.pos.x - b.pos.x
        let dy = e.pos.y - b.pos.y
        let d = dx * dx + dy * dy
        if d < bestD:
          bestD = d
          best = e
      if not best.isNil: steerToward(b, best.pos, k.homing, dt)
    elif not g.player.isNil:
      steerToward(b, g.player.pos, k.homing, dt)
  var r: RetVals
  callKind(k.owner, k.update, [wrapBullet(b), vnum(dt.float64), wrapGame(modCtx.game)], r) and
    r.count > 0 and r.first.kind == vkBool and r.first.b

proc modProjectileDraw*(b: Bullet): bool =
  ## True: the kind drew the bullet.
  let i = projectileOf(b)
  if i < 0 or modCtx.inPvP or not projectileKinds[i].draw.isFn: return false
  let prev = modCtx.drawing
  modCtx.drawing = dtWorld
  defer: modCtx.drawing = prev
  var r: RetVals
  discard callKind(projectileKinds[i].owner, projectileKinds[i].draw, [wrapBullet(b)], r)
  true

proc modProjectileHit*(b: Bullet, e: Enemy, damage: float32): float32 =
  ## The kind's onHit(bullet, enemy, damage) -> damage.
  result = damage
  let i = projectileOf(b)
  if i < 0 or modCtx.inPvP: return
  var r: RetVals
  if callKind(projectileKinds[i].owner, projectileKinds[i].onHit,
              [wrapBullet(b), wrapEnemy(e), vnum(damage.float64)], r):
    result = max(0'f32, numResult(r, damage))

proc modProjectileHitPlayer*(b: Bullet, damage: float32): float32 =
  ## The kind's onHitPlayer(bullet, player, damage) -> damage.
  result = damage
  let i = projectileOf(b)
  if i < 0 or modCtx.inPvP or modCtx.game.isNil: return
  var r: RetVals
  if callKind(projectileKinds[i].owner, projectileKinds[i].onHitPlayer,
              [wrapBullet(b), wrapPlayer(modCtx.game.player), vnum(damage.float64)], r):
    result = max(0'f32, numResult(r, damage))

proc modProjectileExpire*(b: Bullet) =
  let i = projectileOf(b)
  if i < 0 or modCtx.inPvP: return
  var r: RetVals
  discard callKind(projectileKinds[i].owner, projectileKinds[i].onExpire, [wrapBullet(b)], r)

# ----------------------------------------------------------- thing hooks ----
var modPendingThings*: seq[ModThing]   ## spawn.thing handles not yet in game.modThings

proc modThingSpawn*(t: ModThing) =
  if hookActive(hkThingSpawn) and not modCtx.inPvP:
    fire(hkThingSpawn, [wrapThing(t)])

proc modThingDeath*(t: ModThing) =
  if hookActive(hkThingDeath) and not modCtx.inPvP:
    fire(hkThingDeath, [wrapThing(t)])

proc liveThingKeys(game: Game, keys: var HashSet[int64]) {.nimcall.} =
  for t in game.modThings: keys.incl(entityKey(EdThing, t.id))
  for t in modPendingThings: keys.incl(entityKey(EdThing, t.id))

# --------------------------------------------------------------- statuses ----
# register.status: a named effect with stacks and a duration on an enemy or the
# player. Instances (types.ModStatusInst) are plain data on the entity; the
# summed modifiers (statusSpeed / statusDamageTaken / statusDamageDealt) are
# kept current here and read at the game's choke points.
type
  StatusDef* = object
    key*: string
    owner*: int
    nameEn*, nameEs*: string
    color*: Color
    iconTex*: int            ## a texture for the pip (0 = a coloured dot)
    maxStacks*: int
    duration*: float32       ## seconds (<= 0: until cleared)
    tickInterval*: float32   ## seconds between onTick calls (0 = none)
    speed*, damageTaken*, damageDealt*: float32   ## fractions per stack (x magnitude)
    onApply*, onTick*, onExpire*, draw*: ScriptValue

var
  statusDefs*: seq[StatusDef]
  statusIndex: Table[string, int]

proc addStatusDef*(d: StatusDef) =
  statusIndex[d.key] = statusDefs.len
  statusDefs.add(d)

proc findStatus*(key: string): int =
  statusIndex.getOrDefault(key, -1)

proc recomputeStatuses(list: seq[ModStatusInst], speed, taken, dealt: var float32) =
  speed = 0
  taken = 0
  dealt = 0
  for inst in list:
    let i = findStatus(inst.key)
    if i < 0: continue
    let k = inst.stacks.float32 * inst.magnitude
    speed += statusDefs[i].speed * k
    taken += statusDefs[i].damageTaken * k
    dealt += statusDefs[i].damageDealt * k

proc refreshStatuses*(e: Enemy) =
  recomputeStatuses(e.modStatuses, e.statusSpeed, e.statusDamageTaken, e.statusDamageDealt)

proc refreshStatuses*(p: Player) =
  recomputeStatuses(p.modStatuses, p.statusSpeed, p.statusDamageTaken, p.statusDamageDealt)

proc statusAt(list: seq[ModStatusInst], key: string): int =
  for i, inst in list:
    if inst.key == key: return i
  -1

template statusOps(T: typedesc, wrap: untyped) =
  proc statusPos*(target: T, key: string): int = statusAt(target.modStatuses, key)

  proc applyModStatus*(target: T, key: string, duration, magnitude: float32,
                       stacks: int, sourceId: int = 0): bool =
    ## Add `stacks` (capped at maxStacks) and refresh the duration (< 0: the
    ## status's own). False: no such status.
    let di = findStatus(key)
    if di < 0 or modCtx.inPvP: return false
    let d = statusDefs[di]
    let dur = if duration < 0: d.duration else: duration
    var i = statusAt(target.modStatuses, key)
    if i < 0:
      target.modStatuses.add(ModStatusInst(key: key, magnitude: magnitude, tickTimer: d.tickInterval,
                                           sourceId: sourceId))
      i = target.modStatuses.high
    let maxS = max(1, d.maxStacks)
    target.modStatuses[i].stacks = min(maxS, target.modStatuses[i].stacks + max(1, stacks)).int32
    target.modStatuses[i].duration = dur
    target.modStatuses[i].remaining = max(target.modStatuses[i].remaining, dur)
    target.modStatuses[i].magnitude = magnitude
    if sourceId != 0: target.modStatuses[i].sourceId = sourceId
    let nowStacks = target.modStatuses[i].stacks
    refreshStatuses(target)
    var r: RetVals
    discard callKind(d.owner, d.onApply, [wrap(target), vnum(nowStacks.int), vnum(magnitude.float64)], r)
    if hookActive(hkStatusApplied):
      fire(hkStatusApplied, [wrap(target), vstr(key), vnum(nowStacks.int)])
    true

  proc clearModStatus*(target: T, key: string, expired = false) =
    let i = statusAt(target.modStatuses, key)
    if i < 0: return
    target.modStatuses.delete(i)
    refreshStatuses(target)
    let di = findStatus(key)
    if di >= 0:
      var r: RetVals
      discard callKind(statusDefs[di].owner, statusDefs[di].onExpire, [wrap(target)], r)
    if hookActive(hkStatusExpired):
      fire(hkStatusExpired, [wrap(target), vstr(key), vbool(expired)])

  proc tickModStatuses*(target: T, dt: float32) =
    ## Durations, onTick and expiry. Callbacks may change the list (by key).
    if target.modStatuses.len == 0 or modCtx.inPvP: return
    var keys: seq[string]
    for inst in target.modStatuses: keys.add(inst.key)
    for key in keys:
      let i = statusAt(target.modStatuses, key)
      if i < 0: continue
      let di = findStatus(key)
      if di < 0:
        target.modStatuses.delete(i)   # its mod is gone
        refreshStatuses(target)
        continue
      let d = statusDefs[di]
      if d.tickInterval > 0:
        target.modStatuses[i].tickTimer -= dt
        if target.modStatuses[i].tickTimer <= 0:
          target.modStatuses[i].tickTimer += d.tickInterval
          let inst = target.modStatuses[i]
          var r: RetVals
          discard callKind(d.owner, d.onTick, [wrap(target), vnum(inst.stacks.int), vnum(inst.magnitude.float64)], r)
      let j = statusAt(target.modStatuses, key)
      if j < 0: continue
      if target.modStatuses[j].duration > 0:
        target.modStatuses[j].remaining -= dt
        if target.modStatuses[j].remaining <= 0:
          clearModStatus(target, key, expired = true)

statusOps(Enemy, wrapEnemy)
statusOps(Player, wrapPlayer)

proc drawStatusPips*(pos: Vector2f, radius: float32, list: seq[ModStatusInst], wrapped: ScriptValue) =
  ## Small pips over an enemy (or the player): one per status, or the
  ## status's own `draw(target, x, y)` when it has one.
  if list.len == 0 or modCtx.inPvP: return
  let n = list.len
  var x = pos.x - (n - 1).float32 * 4.5'f32
  let y = pos.y - radius - 7
  for inst in list:
    let di = findStatus(inst.key)
    if di < 0: continue
    let d = statusDefs[di]
    if d.draw.isFn:
      let prev = modCtx.drawing
      modCtx.drawing = dtWorld
      var r: RetVals
      discard callKind(d.owner, d.draw, [wrapped, vnum(x.float64), vnum(y.float64), vnum(inst.stacks.int)], r)
      modCtx.drawing = prev
    elif d.iconTex > 0:
      drawModTexture(d.iconTex, x, y, 8, 8, 0, White)
    else:
      drawDisc(Vector2(x: x, y: y), 3.2, d.color)
      if inst.stacks > 1:
        drawCircleOutline(x.int32, y.int32, 4.4, d.color)
    x += 9

proc enemyDamageDealtMult*(e: Enemy): float32 {.inline.} =
  ## An enemy's damage-dealt status modifier (contact hits and its bullets).
  if e.isNil or e.modStatuses.len == 0: 1'f32 else: max(0'f32, 1 + e.statusDamageDealt)

# ------------------------------------------------------------- languages ----
proc pickText*(en, es: string): string {.inline.} =
  ## A mod's {en, es} text in the game's language (English when no Spanish).
  if getLanguage() == Spanish and es.len > 0: es else: en

# ------------------------------------------------------ the `stats` DSL ----
# Declarative stat changes for data-only content: {damage = "+10%",
# maxHp = "+2", fireRate = "x0.95", speed = 20, walls = "=10"} on the player's
# own numeric fields. One helper applies them for power-ups, shop items,
# consumables and patches.
type
  StatOp* = enum soAdd, soMul, soSet
  StatDelta* = object
    field*: string
    op*: StatOp
    value*: float32

proc statFieldOk*(field: string): bool =
  ## A numeric field of the player.
  var found = false
  let v = reflectGet(Player(), field, found)
  found and v.kind == vkNumber

proc parseStatDelta*(field: string, v: ScriptValue, err: var string): StatDelta =
  ## number: add it; "+N" / "-N": add; "+N%" / "-N%": scale; "xN" / "*N":
  ## multiply; "=N": set.
  result.field = field
  if not statFieldOk(field):
    err = "stats: '" & field & "' is not a number field of the player"
    return
  case v.kind
  of vkNumber:
    result.op = soAdd
    result.value = v.n.float32
  of vkString:
    var s = v.str.s.strip()
    var ok = false
    if s.len == 0: discard
    elif s.endsWith("%"):
      let n = strToNum(s[0 ..< s.high], ok)
      result.op = soMul
      result.value = 1'f32 + n.float32 / 100'f32
    elif s[0] in {'x', 'X', '*'}:
      let n = strToNum(s[1 .. ^1], ok)
      result.op = soMul
      result.value = n.float32
    elif s[0] == '=':
      let n = strToNum(s[1 .. ^1], ok)
      result.op = soSet
      result.value = n.float32
    else:
      let n = strToNum(s, ok)
      result.op = soAdd
      result.value = n.float32
    if not ok or result.value != result.value:
      err = "stats." & field & ": \"" & v.str.s & "\" is not a change (use 5, \"+10%\", \"x0.9\" or \"=3\")"
  else:
    err = "stats." & field & " must be a number or a text like \"+10%\""

proc applyStatDeltas*(p: Player, deltas: seq[StatDelta], times = 1) =
  ## Apply the changes `times` times. Max HP gains heal by the same amount.
  if p.isNil or deltas.len == 0: return
  for _ in 0 ..< max(1, times):
    for d in deltas:
      var found = false
      let cur = reflectGet(p, d.field, found)
      if not found or cur.kind != vkNumber: continue
      let before = cur.n.float32
      let after = case d.op
        of soAdd: before + d.value
        of soMul: before * d.value
        of soSet: d.value
      try:
        discard reflectSet(modVM, p, d.field, vnum(after.float64))
      except ScriptError: discard
      if d.field == "maxHp" and after > before:
        p.hp = min(p.hp + (after - before), max(after, p.hp))

# ------------------------------------------------------------ consumables ----
type ConsumableDef* = object
  key*: string
  owner*: int
  nameEn*, nameEs*: string
  color*: Color
  iconTex*: int
  icon*: ScriptValue         ## fn(x, y, radius, color) drawing its icon
  weight*: float32           ## against the game's own 100
  modes*: set[GameMode]      ## empty = every mode
  stats*: seq[StatDelta]
  onPickup*: ScriptValue     ## fn(player, game, x, y)

var
  consumableDefs*: seq[ConsumableDef]
  consumableIndex: Table[string, int]

proc addConsumableDef*(d: ConsumableDef) =
  consumableIndex[d.key] = consumableDefs.len
  consumableDefs.add(d)

proc findConsumable*(key: string): int = consumableIndex.getOrDefault(key, -1)

proc modeOk(modes: set[GameMode], mode: GameMode): bool {.inline.} =
  modes.card == 0 or mode in modes

proc modConsumableWeight*(mode: GameMode): float32 =
  ## The mod consumables' share of a random drop, next to the game's 100.
  for d in consumableDefs:
    if d.weight > 0 and modeOk(d.modes, mode) and (d.owner >= mods.len or not mods[d.owner].disabled):
      result += d.weight

proc rollModConsumable*(mode: GameMode, r: float32): string =
  ## The mod consumable a roll of `r` (0 ..< modConsumableWeight) lands on.
  var acc = 0'f32
  for d in consumableDefs:
    if d.weight > 0 and modeOk(d.modes, mode) and (d.owner >= mods.len or not mods[d.owner].disabled):
      acc += d.weight
      if r < acc: return d.key
  ""

proc modConsumableColor*(key: string): Color =
  let i = findConsumable(key)
  if i < 0: Color(r: 200, g: 200, b: 200, a: 255) else: consumableDefs[i].color

proc modConsumableName*(key: string): string =
  let i = findConsumable(key)
  if i < 0: key else: pickText(consumableDefs[i].nameEn, consumableDefs[i].nameEs)

proc drawModConsumableIcon*(key: string, x, y, radius: float32) =
  let i = findConsumable(key)
  if i < 0: return
  let d = consumableDefs[i]
  if d.iconTex > 0:
    drawModTexture(d.iconTex, x, y, radius * 1.6'f32, radius * 1.6'f32, 0, White)
  elif d.icon.isFn and not modCtx.inPvP:
    let prev = modCtx.drawing
    modCtx.drawing = dtWorld
    var r: RetVals
    discard callKind(d.owner, d.icon, [vnum(x.float64), vnum(y.float64), vnum(radius.float64),
                                       colorValue(d.color)], r)
    modCtx.drawing = prev
  else:
    let name = modConsumableName(key)
    let ch = if name.len > 0: $name[0].toUpperAscii else: "?"
    drawText(ch, int32(x - measureText(ch, 12).float32 / 2), int32(y - 6), 12, White)

proc modConsumablePickup*(game: Game, c: Consumable) =
  ## Its stats, then its onPickup(player, game, x, y).
  let i = findConsumable(c.modKey)
  if i < 0: return
  let d = consumableDefs[i]
  applyStatDeltas(game.player, d.stats)
  var r: RetVals
  discard callKind(d.owner, d.onPickup, [wrapPlayer(game.player), wrapGame(game),
                                         vnum(c.pos.x.float64), vnum(c.pos.y.float64)], r)

# ------------------------------------------------------------- shop rows ----
type ShopItemDef* = object
  key*: string
  owner*: int
  nameEn*, nameEs*, descEn*, descEs*: string
  color*: Color
  iconTex*: int
  icon*: ScriptValue         ## fn(x, y, size, color)
  cost*: int
  costMult*: float32         ## each purchase multiplies the price
  maxBuys*: int              ## 0 = unlimited
  modes*: set[GameMode]
  minWave*: int
  stats*: seq[StatDelta]
  onBuy*: ScriptValue        ## fn(player, game, bought)

var
  shopItemDefs*: seq[ShopItemDef]
  shopItemIndex: Table[string, int]

proc addShopItemDef*(d: ShopItemDef) =
  shopItemIndex[d.key] = shopItemDefs.len
  shopItemDefs.add(d)

proc findShopItem*(key: string): int = shopItemIndex.getOrDefault(key, -1)

proc modShopRows*(game: Game): seq[int] =
  ## The registered shop items this run's shop offers (indices into
  ## shopItemDefs), after the game's own six rows.
  if shopItemDefs.len == 0 or game.isNil or modCtx.inPvP: return
  for i, d in shopItemDefs:
    if d.owner < mods.len and mods[d.owner].disabled: continue
    if not modeOk(d.modes, game.mode): continue
    if game.mode == gmWaveBased and game.currentWave < d.minWave: continue
    result.add(i)

proc modShopBoughtCount*(game: Game, key: string): int =
  for e in game.modShopBought:
    if e.key == key: return e.bought
  0

proc setModShopBought*(game: Game, key: string, n: int) =
  for e in game.modShopBought.mitems:
    if e.key == key:
      e.bought = n
      return
  game.modShopBought.add((key, n))

proc modShopCost*(d: ShopItemDef, bought: int): int =
  int(d.cost.float32 * pow(max(1'f32, d.costMult), bought.float32))

proc modShopBuyDone*(game: Game, defIdx, bought: int) =
  ## A purchase went through: its stats, then onBuy(player, game, bought).
  let d = shopItemDefs[defIdx]
  applyStatDeltas(game.player, d.stats)
  var r: RetVals
  discard callKind(d.owner, d.onBuy, [wrapPlayer(game.player), wrapGame(game), vnum(bought)], r)

proc drawModShopIcon*(defIdx: int, x, y, size: float32): bool =
  ## Its texture or icon function (false: neither; the shop draws a letter).
  let d = shopItemDefs[defIdx]
  if d.iconTex > 0:
    drawModTexture(d.iconTex, x, y, size, size, 0, White)
    return true
  if d.icon.isFn and not modCtx.inPvP:
    let prev = modCtx.drawing
    modCtx.drawing = dtHud
    var r: RetVals
    result = callKind(d.owner, d.icon, [vnum(x.float64), vnum(y.float64), vnum(size.float64),
                                        colorValue(d.color)], r)
    modCtx.drawing = prev

# ---------------------------------------------------------------- patches ----
type PatchDef* = object
  key*: string
  owner*: int
  nameEn*, nameEs*, descEn*, descEs*: string
  color*: Color
  iconTex*: int
  icon*: ScriptValue         ## fn(x, y, size, color)
  weight*: float32           ## chance in a patch draft, against a game patch's 1
  minFloor*: int
  stats*: seq[StatDelta]
  onInstall*: ScriptValue    ## fn(player, game)
  update*: ScriptValue       ## fn(player, dt, game) every frame of a roguelite run that has it

var
  patchDefs*: seq[PatchDef]
  patchIndex: Table[string, int]

proc addPatchDef*(d: PatchDef) =
  patchIndex[d.key] = patchDefs.len
  patchDefs.add(d)

proc findPatch*(key: string): int = patchIndex.getOrDefault(key, -1)

proc livePatch(i: int): bool {.inline.} =
  patchDefs[i].owner >= mods.len or not mods[patchDefs[i].owner].disabled

proc modPatchName*(key: string): string =
  let i = findPatch(key)
  if i < 0: key else: pickText(patchDefs[i].nameEn, patchDefs[i].nameEs)

proc modPatchDescription*(key: string): string =
  let i = findPatch(key)
  if i < 0: "" else: pickText(patchDefs[i].descEn, patchDefs[i].descEs)

proc modPatchColor*(key: string): Color =
  let i = findPatch(key)
  if i < 0: Color(r: 180, g: 180, b: 200, a: 255) else: patchDefs[i].color

proc modPatchKb*(key: string): int =
  ## A stable KB number from the key (9000-9999), like the game's own patches.
  var h = 0
  for c in key: h = (h * 31 + ord(c)) mod 1000
  9000 + h

proc drawModPatchIcon*(key: string, x, y, size: float32): bool =
  ## False: no look of its own (draw the game's generic glyph).
  let i = findPatch(key)
  if i < 0: return false
  let d = patchDefs[i]
  if d.iconTex > 0:
    drawModTexture(d.iconTex, x, y, size, size, 0, White)
    return true
  if d.icon.isFn and not modCtx.inPvP:
    let prev = modCtx.drawing
    modCtx.drawing = dtHud
    var r: RetVals
    result = callKind(d.owner, d.icon, [vnum(x.float64), vnum(y.float64), vnum(size.float64),
                                        colorValue(d.color)], r)
    modCtx.drawing = prev

proc modPatchCandidates*(floor: int, owned: seq[string]): seq[tuple[key: string, weight: float32]] =
  ## The mod patches a draft may offer: loaded, unlocked by the floor, not owned.
  for i, d in patchDefs:
    if livePatch(i) and d.weight > 0 and floor >= d.minFloor and d.key notin owned:
      result.add((d.key, d.weight))

proc firePatchInstalled*(game: Game, name: string) =
  if hookActive(hkPatchInstalled) and not modCtx.inPvP:
    fire(hkPatchInstalled, [vstr(name), wrapGame(game)])

proc modPatchInstalled*(game: Game, key: string) =
  ## Its stats, its onInstall and the patchInstalled hook.
  let i = findPatch(key)
  if i < 0: return
  applyStatDeltas(game.player, patchDefs[i].stats)
  var r: RetVals
  discard callKind(patchDefs[i].owner, patchDefs[i].onInstall, [wrapPlayer(game.player), wrapGame(game)], r)
  firePatchInstalled(game, key)

proc modPatchesUpdate*(game: Game, dt: float32) =
  ## Every frame of a roguelite run: the update of each mod patch it has.
  if patchDefs.len == 0 or game.rogueliteRun.isNil or modCtx.inPvP: return
  var keys: seq[string]
  for rl in game.rogueliteRun.relics:
    if rl.relicType == rrtMod: keys.add(rl.modKey)
  for k in keys:
    let i = findPatch(k)
    if i >= 0 and patchDefs[i].update.isFn:
      var r: RetVals
      discard callKind(patchDefs[i].owner, patchDefs[i].update,
                       [wrapPlayer(game.player), vnum(dt.float64), wrapGame(game)], r)

# --------------------------------------------------------- survival events ----
type SurvivalEventDef* = object
  key*: string
  owner*: int
  nameEn*, nameEs*, hintEn*, hintEs*: string
  color*: Color
  weights*: array[4, float32]   ## per survival phase: boot, runtime, overload, panic
  duration*, warmup*: float32
  reward*: int                  ## a cache tier (ord) on success; -1 = none
  onStart*, update*, onFinish*, tracker*, fraction*: ScriptValue

var
  survivalEventDefs*: seq[SurvivalEventDef]
  survivalEventIndex: Table[string, int]

proc addSurvivalEventDef*(d: SurvivalEventDef) =
  survivalEventIndex[d.key] = survivalEventDefs.len
  survivalEventDefs.add(d)

proc findSurvivalEvent*(key: string): int = survivalEventIndex.getOrDefault(key, -1)

proc modEventName*(key: string): string =
  let i = findSurvivalEvent(key)
  if i < 0: key else: pickText(survivalEventDefs[i].nameEn, survivalEventDefs[i].nameEs)

proc modEventHint*(key: string): string =
  let i = findSurvivalEvent(key)
  if i < 0: "" else: pickText(survivalEventDefs[i].hintEn, survivalEventDefs[i].hintEs)

proc modEventColor*(key: string): Color =
  let i = findSurvivalEvent(key)
  if i < 0: Color(r: 200, g: 200, b: 255, a: 255) else: survivalEventDefs[i].color

proc modEventWeights*(phase: int): seq[tuple[key: string, weight: float32]] =
  for i, d in survivalEventDefs:
    if d.owner < mods.len and mods[d.owner].disabled: continue
    let w = d.weights[clamp(phase, 0, 3)]
    if w > 0: result.add((d.key, w))

proc modEventTable(game: Game, i: int): ScriptValue =
  ## What a mod event's callbacks get as `ev`: its name and clocks, and
  ## ev.data, the event's own table (kept with the per-entity data).
  let ev = game.survival.event
  let t = newScriptTable()
  rawSet(t, vstr("name"), vstr(ev.modKey))
  rawSet(t, vstr("elapsed"), vnum(ev.elapsed.float64))
  rawSet(t, vstr("live"), vnum((ev.elapsed - ev.warmup).float64))
  rawSet(t, vstr("warmup"), vnum(ev.warmup.float64))
  rawSet(t, vstr("limit"), vnum(ev.limit.float64))
  rawSet(t, vstr("phase"), vnum(survivalPhaseIndex(game)))
  rawSet(t, vstr("data"), vtable(entityDataFor(survivalEventDefs[i].owner,
                                               entityKey(EdEvent, game.survival.eventsStarted))))
  vtable(t)

proc modEventCall*(game: Game, which: proc (d: SurvivalEventDef): ScriptValue {.nimcall.},
                   extra: openArray[ScriptValue], r: var RetVals): bool =
  ## One of the running mod event's callbacks, with (ev, game, extra...).
  let i = findSurvivalEvent(game.survival.event.modKey)
  if i < 0 or not which(survivalEventDefs[i]).isFn: return false
  var args = @[modEventTable(game, i), wrapGame(game)]
  for a in extra: args.add(a)
  callKind(survivalEventDefs[i].owner, which(survivalEventDefs[i]), args, r)

proc modEventStarted*(game: Game) =
  var r: RetVals
  discard modEventCall(game, proc (d: SurvivalEventDef): ScriptValue {.nimcall.} = d.onStart, [], r)

proc modEventFinished*(game: Game, success: bool) =
  var r: RetVals
  discard modEventCall(game, proc (d: SurvivalEventDef): ScriptValue {.nimcall.} = d.onFinish,
                       [vbool(success)], r)

proc modEventUpdate*(game: Game, dt: float32): int =
  ## Its update(ev, game, dt): 1 = "success", 2 = "fail", 0 = still running.
  var r: RetVals
  if modEventCall(game, proc (d: SurvivalEventDef): ScriptValue {.nimcall.} = d.update,
                  [vnum(dt.float64)], r) and r.count > 0 and r.first.kind == vkString:
    if r.first.str.s == "success": return 1
    if r.first.str.s == "fail": return 2
  0

proc modEventTracker*(game: Game, detail: var string, frac: var float32) =
  ## Its tracker(ev, game) -> text and fraction(ev, game) -> 0..1, when it has them.
  var r: RetVals
  if modEventCall(game, proc (d: SurvivalEventDef): ScriptValue {.nimcall.} = d.tracker, [], r) and
     r.count > 0 and r.first.kind == vkString:
    detail = r.first.str.s
  if modEventCall(game, proc (d: SurvivalEventDef): ScriptValue {.nimcall.} = d.fraction, [], r) and
     r.count > 0 and r.first.kind == vkNumber and r.first.n == r.first.n:
    frac = clamp(r.first.n.float32, 0'f32, 1'f32)

# ---------------------------------------------------------- achievements ----
# register.advancement: a mod's own achievements, kept per profile in
# mod_data/@advancements.json. They never touch the game's advancement list or
# its rewards, so they unlock in cheated runs too.
type
  AdvancementDef* = object
    key*: string
    owner*: int
    nameEn*, nameEs*, descEn*, descEs*: string
    color*: Color
    iconTex*: int
    goal*: int
    hidden*: bool
  AdvancementState* = object
    progress*: int
    unlocked*: bool
    unlockedAt*: string

var
  advancementDefs*: seq[AdvancementDef]
  advancementIndex: Table[string, int]
  advStore: Table[string, AdvancementState]
  advStoreDir: string              ## the profile folder the store was read from
  advancementToasts*: seq[string]  ## unlock toasts for main.nim (a run's or the desktop's)

proc addAdvancementDef*(d: AdvancementDef) =
  advancementIndex[d.key] = advancementDefs.len
  advancementDefs.add(d)

proc findAdvancement*(key: string): int = advancementIndex.getOrDefault(key, -1)

proc advStorePath(dir: string): string = dir / "@advancements.json"

proc ensureAdvStore() =
  let dir = getAppDataPath() / "mod_data"
  if dir == advStoreDir: return
  advStoreDir = dir
  advStore.clear()
  try:
    let path = advStorePath(dir)
    if fileExists(path):
      let j = parseJson(readFile(path))
      if j.kind == JObject:
        for k, v in j.pairs:
          if v.kind == JObject:
            advStore[k] = AdvancementState(progress: v{"progress"}.getInt(0),
                                           unlocked: v{"unlocked"}.getBool(false),
                                           unlockedAt: v{"at"}.getStr(""))
  except CatchableError:
    modLogAdd(mlWarn, "", "mod achievements could not be read; starting empty")

proc saveAdvStore() =
  let j = newJObject()
  for k, v in advStore:
    j[k] = %*{"progress": v.progress, "unlocked": v.unlocked, "at": v.unlockedAt}
  try:
    createDir(advStoreDir)
    writeFile(advStorePath(advStoreDir), $j)
  except CatchableError:
    modLogAdd(mlWarn, "", "mod achievements could not be saved")

proc advancementState*(key: string): AdvancementState =
  ensureAdvStore()
  advStore.getOrDefault(key)

proc advancementName*(i: int): string = pickText(advancementDefs[i].nameEn, advancementDefs[i].nameEs)
proc advancementDescription*(i: int): string = pickText(advancementDefs[i].descEn, advancementDefs[i].descEs)

proc advancementProgress*(key: string, amount: int, absolute = false): bool =
  ## Add (or set) progress; true when this call unlocked it.
  let i = findAdvancement(key)
  if i < 0: return false
  ensureAdvStore()
  var st = advStore.getOrDefault(key)
  if st.unlocked: return false
  st.progress = if absolute: amount else: st.progress + amount
  st.progress = clamp(st.progress, 0, max(1, advancementDefs[i].goal))
  if st.progress >= max(1, advancementDefs[i].goal):
    st.unlocked = true
    st.unlockedAt = getDateStr()
    result = true
    advancementToasts.add(t("mods_achievement_unlocked") & ": " & advancementName(i))
    modLogAdd(mlInfo, mods[advancementDefs[i].owner].id, "achievement unlocked: " & advancementName(i))
  advStore[key] = st
  saveAdvStore()

proc resetAdvancementCache*() =
  ## Profile switch: read the new profile's store on next use.
  advStoreDir = ""
  advStore.clear()

# ============================================================== commands ====
# register.command: words the Help terminal (HELP.EXE) runs, on the desktop.
type CommandDef* = object
  name*: string               ## lowercase, no spaces
  owner*: int
  helpEn*, helpEs*: string
  run*: ScriptValue           ## fn(args) -> text | {lines...}

var commandDefs*: seq[CommandDef]

proc findCommand*(name: string): int =
  for i, c in commandDefs:
    if c.name == name and liveOwner(c.owner): return i
  -1

proc modCommandHelp*(): seq[tuple[cmd, desc: string]] =
  for c in commandDefs:
    if liveOwner(c.owner): result.add((c.name, pickText(c.helpEn, c.helpEs)))

proc runModCommand*(name: string, args: seq[string], lines: var seq[string]): bool =
  ## False: no mod has that command. Its result (a string, or a list of them)
  ## becomes the terminal's output lines.
  let i = findCommand(name)
  if i < 0: return false
  result = true
  let t = newScriptTable()
  for a in args: t.add(vstr(a))
  var r: RetVals
  if not callKind(commandDefs[i].owner, commandDefs[i].run, [vtable(t)], r):
    lines.add("(the command failed: see MODS.EXE > Log)")
    return
  if r.count == 0: return
  case r.first.kind
  of vkString:
    for l in r.first.str.s.splitLines: lines.add(l)
  of vkTable:
    for x in r.first.tbl:
      if x.kind == vkString: lines.add(x.str.s)
      elif x.kind == vkNumber: lines.add(numToStr(x.n))
  of vkNumber: lines.add(numToStr(r.first.n))
  of vkBool: lines.add($r.first.b)
  else: discard

# ======================================================== camera and time ====
proc modWorldTimeScale*(game: Game): float32 {.inline.} =
  ## time.scale: the whole world's clock (1 when no mod set it).
  if game.modWorld.timeScale > 0: clamp(game.modWorld.timeScale, 0.1'f32, 2'f32) else: 1'f32

proc updateModCamera*(game: Game, dt: float32) =
  ## camera.follow and the easing toward the camera's target (real time).
  let w = addr game.modWorld
  if w.camZoom <= 0: return
  var tx = w.camX
  var ty = w.camY
  if w.camFollow and not game.player.isNil:
    tx = game.player.pos.x
    ty = game.player.pos.y
  let target = clampedCamCentre(w.camZoom, tx, ty, game.screenWidth.float32, game.screenHeight.float32)
  if (w.camCurX == 0 and w.camCurY == 0) or w.camLerp <= 0:
    w.camCurX = target.x
    w.camCurY = target.y
  else:
    let k = 1'f32 - exp(-w.camLerp * dt)
    w.camCurX += (target.x - w.camCurX) * k
    w.camCurY += (target.y - w.camCurY) * k

# ============================================================= in-run UI ====
# ui.open modals, ui.banner, register.hudCard and register.pauseAction. None of
# it is ever saved: a resumed run reopens its screens from runStart.
type
  ModalLayer* = enum mlHud, mlScreen
  ModModal* = object
    id*: int
    owner*: int
    draw*, update*, click*, onClose*: ScriptValue
    pause*: bool              ## the run holds still while it is open
    closeOnBack*: bool        ## Esc / gamepad B closes it
    layer*: ModalLayer        ## "hud" (the HUD's scaled layer) or "screen" (raw virtual pixels)
  HudCardDef* = object
    key*: string
    owner*: int
    titleEn*, titleEs*: string
    color*: Color
    height*: int
    measure*, draw*: ScriptValue  ## measure(w) -> height; draw(x, y, w, h)
    classic*: bool            ## also drawn by the classic / legacy HUDs (top right)
  PauseActionDef* = object
    key*: string
    owner*: int
    nameEn*, nameEs*: string
    onClick*: ScriptValue

var
  modModals*: seq[ModModal]
  nextModalId = 1
  hudCardDefs*: seq[HudCardDef]
  pauseActionDefs*: seq[PauseActionDef]
  modBanner*: tuple[title, subtitle: string, color: Color, timer, duration: float32]

proc openModModal*(m: ModModal): int =
  var m = m
  m.id = nextModalId
  inc nextModalId
  modModals.add(m)
  m.id

proc closeModModal*(id: int, ranOnClose = true) =
  var i = -1
  for j, m in modModals:
    if m.id == id:
      i = j
      break
  if i < 0: return
  let m = modModals[i]
  modModals.delete(i)
  if ranOnClose:
    var r: RetVals
    discard callKind(m.owner, m.onClose, [], r)

proc modModalOpen*(id: int): bool =
  for m in modModals:
    if m.id == id: return true
  false

proc pruneModals() =
  ## A switched-off mod's screens go with it.
  var kept: seq[ModModal]
  for m in modModals:
    if liveOwner(m.owner): kept.add(m)
  modModals = kept

proc modUiHoldsInput*(): bool =
  ## A mod screen is open: gameplay input (shooting, dash, walls, [Q]) waits.
  if modModals.len == 0: return false
  pruneModals()
  modModals.len > 0

proc modUiPauses*(): bool =
  if modModals.len == 0: return false
  pruneModals()
  for m in modModals:
    if m.pause: return true
  false

proc modUiBack*(): bool =
  ## Esc / B: closes the top screen that allows it (true: it did).
  if modModals.len == 0: return false
  let top = modModals[^1]
  if not top.closeOnBack: return false
  closeModModal(top.id)
  true

proc clearModModals*() =
  modModals.setLen(0)
  modBanner.timer = 0

proc updateModUi*(dt: float32) =
  ## Every frame of a run: each open screen's update(dt), and the banner.
  if modBanner.timer > 0: modBanner.timer = max(0'f32, modBanner.timer - dt)
  if modModals.len == 0 or modCtx.inPvP: return
  pruneModals()
  for m in modModals:   # a copy: update may open or close screens
    if modModalOpen(m.id):
      var r: RetVals
      discard callKind(m.owner, m.update, [vnum(dt.float64)], r)

proc drawModUi*(layer: ModalLayer, w, h: int32, mx, my: float32) =
  ## The open screens of one layer (bottom to top), then (hud layer) the
  ## banner. The top screen gets this frame's click(x, y, button) unless a
  ## widget inside it took the press.
  if modCtx.inPvP: return
  let any = modModals.len > 0 or (layer == mlHud and modBanner.timer > 0)
  if not any: return
  let prevDraw = modCtx.drawing
  let prevArena = modCtx.hudArena
  modCtx.drawing = dtHud
  modCtx.hudArena = (0.0, 0.0, w.float64, h.float64)
  setUiPointer(mx, my)
  var topId = -1
  for i in countdown(modModals.high, 0):
    if modModals[i].layer == layer:
      topId = modModals[i].id
      break
  let snapshot = modModals
  for m in snapshot:
    if m.layer != layer or not modModalOpen(m.id): continue
    uiPointer.consumed = m.id != topId   # only the top screen takes input
    var r: RetVals
    discard callKind(m.owner, m.draw, [vnum(w.int), vnum(h.int)], r)
    if m.id == topId and not uiPointer.consumed and modModalOpen(m.id) and
       (uiPointer.pressed or uiPointer.rightPressed) and m.click.isFn:
      discard callKind(m.owner, m.click, [vnum(mx.float64), vnum(my.float64),
                                          vstr(if uiPointer.pressed: "left" else: "right")], r)
  if layer == mlHud and modBanner.timer > 0:
    let a = clamp(min(modBanner.timer, modBanner.duration - modBanner.timer + 0.01'f32) * 4, 0'f32, 1'f32)
    let bw = max(measureText(modBanner.title, 26), measureText(modBanner.subtitle, 14)) + 60
    let bx = (w - bw) div 2
    let by = h div 4
    drawRectangle(bx, by, bw, 70, Color(r: 6, g: 10, b: 18, a: uint8(210 * a)))
    drawRectangle(bx, by, bw, 3, withAlpha(modBanner.color, int(255 * a)))
    drawRectangle(bx, by + 67, bw, 3, withAlpha(modBanner.color, int(255 * a)))
    drawText(modBanner.title, (w - measureText(modBanner.title, 26)) div 2, by + 12, 26,
             withAlpha(modBanner.color, int(255 * a)))
    if modBanner.subtitle.len > 0:
      drawText(modBanner.subtitle, (w - measureText(modBanner.subtitle, 14)) div 2, by + 44, 14,
               Color(r: 220, g: 230, b: 240, a: uint8(255 * a)))
  modCtx.drawing = prevDraw
  modCtx.hudArena = prevArena

# ---- HUD cards
proc liveHudCards*(): seq[int] =
  for i, c in hudCardDefs:
    if liveOwner(c.owner): result.add(i)

proc hudCardHeight(i, w: int): int =
  let c = hudCardDefs[i]
  result = c.height
  if c.measure.isFn:
    var r: RetVals
    if callKind(c.owner, c.measure, [vnum(w)], r) and r.count > 0 and r.first.kind == vkNumber and
       r.first.n == r.first.n:
      result = clamp(int(r.first.n), 0, 600)

proc drawModHudCards*(x, y, w: int32, classic: bool, mx, my: float32): int32 =
  ## register.hudCard cards stacked from (x, y), `w` wide; the y below the
  ## last. `classic`: only the cards that opted into the classic/legacy HUDs.
  result = y
  if hudCardDefs.len == 0 or modCtx.inPvP: return
  let prevDraw = modCtx.drawing
  let prevArena = modCtx.hudArena
  modCtx.drawing = dtHud
  for i in liveHudCards():
    let c = hudCardDefs[i]
    if classic and not c.classic: continue
    let body = hudCardHeight(i, w.int)
    if body <= 0: continue
    let title = pickText(c.titleEn, c.titleEs)
    let headerH = if title.len > 0: DockHeaderH else: 0'i32
    let h = headerH + body.int32 + DockPad
    drawDockCard(x, result, w, h, c.color)
    if title.len > 0: drawDockHeader(x, result, w, title, c.color)
    let cx = x + DockPad
    let cy = result + headerH + DockPad div 2
    modCtx.hudArena = (cx.float64, cy.float64, (w - DockPad * 2).float64, body.float64)
    setUiPointer(mx, my)
    var r: RetVals
    discard callKind(c.owner, c.draw, [vnum(cx.int), vnum(cy.int), vnum(int(w - DockPad * 2)),
                                       vnum(body)], r)
    result += h + DockGap
  modCtx.drawing = prevDraw
  modCtx.hudArena = prevArena

# ---- pause-menu actions
proc livePauseActions*(): seq[int] =
  for i, a in pauseActionDefs:
    if liveOwner(a.owner): result.add(i)

proc runPauseAction*(i: int) =
  if i < 0 or i >= pauseActionDefs.len: return
  var r: RetVals
  discard callKind(pauseActionDefs[i].owner, pauseActionDefs[i].onClick, [wrapGame(modCtx.game)], r)

proc pauseActionName*(i: int): string = pickText(pauseActionDefs[i].nameEn, pauseActionDefs[i].nameEs)

# -------------------------------------------------------------- teardown ----
proc resetRegistry() {.nimcall.} =
  thingKinds.setLen(0)
  thingKindIndex.clear()
  projectileKinds.setLen(0)
  projectileKindIndex.clear()
  hazardTriggers.clear()
  modPendingThings.setLen(0)
  statusDefs.setLen(0)
  statusIndex.clear()
  consumableDefs.setLen(0)
  consumableIndex.clear()
  shopItemDefs.setLen(0)
  shopItemIndex.clear()
  patchDefs.setLen(0)
  patchIndex.clear()
  survivalEventDefs.setLen(0)
  survivalEventIndex.clear()
  advancementDefs.setLen(0)
  advancementIndex.clear()
  resetAdvancementCache()
  clearModModals()
  hudCardDefs.setLen(0)
  pauseActionDefs.setLen(0)
  commandDefs.setLen(0)

proc dropRegistryOf(owner: int) {.nimcall.} =
  var keptT: seq[ThingKind]
  for k in thingKinds:
    if k.owner != owner: keptT.add(k)
  thingKinds.setLen(0)
  thingKindIndex.clear()
  for k in keptT: addThingKind(k)
  var keptP: seq[ProjectileKind]
  for k in projectileKinds:
    if k.owner != owner: keptP.add(k)
  projectileKinds.setLen(0)
  projectileKindIndex.clear()
  for k in keptP: addProjectileKind(k)
  var keptS: seq[StatusDef]
  for d in statusDefs:
    if d.owner != owner: keptS.add(d)
  statusDefs.setLen(0)
  statusIndex.clear()
  for d in keptS: addStatusDef(d)
  template dropOwned(defs, index, adder: untyped) =
    var kept = defs
    kept.setLen(0)
    for d in defs:
      if d.owner != owner: kept.add(d)
    defs.setLen(0)
    index.clear()
    for d in kept: adder(d)
  dropOwned(consumableDefs, consumableIndex, addConsumableDef)
  dropOwned(shopItemDefs, shopItemIndex, addShopItemDef)
  dropOwned(patchDefs, patchIndex, addPatchDef)
  dropOwned(survivalEventDefs, survivalEventIndex, addSurvivalEventDef)
  dropOwned(advancementDefs, advancementIndex, addAdvancementDef)
  var keptCards: seq[HudCardDef]
  for c in hudCardDefs:
    if c.owner != owner: keptCards.add(c)
  hudCardDefs = keptCards
  var keptCommands: seq[CommandDef]
  for c in commandDefs:
    if c.owner != owner: keptCommands.add(c)
  commandDefs = keptCommands
  var keptActions: seq[PauseActionDef]
  for a in pauseActionDefs:
    if a.owner != owner: keptActions.add(a)
  pauseActionDefs = keptActions
  var keptModals: seq[ModModal]
  for m in modModals:
    if m.owner != owner: keptModals.add(m)
  modModals = keptModals

addModTeardown(resetRegistry, dropRegistryOf)
onNewRun.add(clearModModals)   # a new run starts with no mod screens open
liveEntityExtra = liveThingKeys
projectileHitRoute = modProjectileHit
projectileUpdateRoute = modProjectileUpdate
projectileDrawRoute = modProjectileDraw
projectileExpireRoute = modProjectileExpire
projectileHitPlayerRoute = proc (b: Bullet, damage: float32): float32 {.nimcall.} =
  modProjectileHitPlayer(b, damage)
