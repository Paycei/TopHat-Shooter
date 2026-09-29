## The script-facing API of the 3D worlds (MODDING.md documents it for modders):
## the `world3d` library, the world / entity / projectile / pickup wrappers and
## the `draw3d` library.
##
## The engine (game3d/) fires the world3d* hooks and applies the 3D action
## queue; this module fills in what scripts see. It sits HIGH in the dependency
## DAG like mod_api (gameplay modules never import it): installMod3D is called
## by the loader right after installModApi, and it fills the wrap*3DImpl seams
## of mod_hooks that the engine's hook helpers use.
##
## Rules it keeps:
##  * Natives raise ScriptError (vm.runtimeError); lua_bridge's trampoline turns
##    that into a Lua error, so nothing here touches the C API.
##  * Field access goes through mod_deep (fieldPairs proxies), so a new field on
##    Game3D / Entity3D / ... is scriptable with no code here. Proxies reached
##    from a wrapper carry an `alive` guard: once the world (or the entity) is
##    gone they read "no longer exists" instead of showing stale data.
##  * Hooks fire inside the engine's loops, so anything structural (spawning an
##    entity, a projectile, a pickup) is queued through queueWorld3DAction and
##    applied between the frame's stages; removal marks things dead/removed and
##    the engine sweeps them.

import std/[strutils, math]
import raylib, rlgl
import ../game3d/[types_3d, engine_3d, game_3d]
import mod_assets
import lua_bridge, mod_hooks, mod_reflect, mod_deep, mod_api

type
  WorldBox = ref object of RootObj
    w: Game3D
  EntityBox = ref object of RootObj
    e: Entity3D
    w: Game3D          ## the world it was wrapped in
  ProjectileBox = ref object of RootObj
    p: Projectile3D
    w: Game3D
  PickupBox = ref object of RootObj
    p: Pickup3D
    w: Game3D

var
  worldClass, entityClass, projectileClass, pickupClass: UdClass
  worldMethods, entityMethods, projectileMethods, pickupMethods: ScriptTable

const
  Themes = ["default", "space", "empty"]
  AiNames = ["none", "chase", "orbit", "wander", "turret"]
  ShapeNames = ["none", "cube", "sphere", "cylinder", "model"]
  ModelFps = 60.0   ## animation frames per second (draw3d.model's `frame` option)

# ------------------------------------------------------------- helpers ----
proc requireWorld(vm: VM, fname: string): Game3D =
  result = activeWorld3D
  if result.isNil:
    vm.runtimeError(fname & " needs an active 3D world (world3d.active() is false)")

proc num(vm: VM, v: ScriptValue, what: string): float32 =
  ## A finite number (NaN and huge values are rejected).
  if v.kind == vkNumber and abs(v.n) < 1.0e9: return v.n.float32
  if v.kind == vkNumber: vm.runtimeError(what & " must be a finite number")
  vm.runtimeError(what & " must be a number, got " & typeName(v))

proc numArg(vm: VM, args: openArray[ScriptValue], i: int, fname: string): float32 =
  let v = arg(args, i)
  if v.kind == vkNumber and abs(v.n) < 1.0e9: return v.n.float32
  if v.kind == vkNumber: vm.argError(fname, i, "number must be finite")
  vm.checkNum(args, i, fname).float32   # strings that read as numbers, else the standard error

proc optNumArg(vm: VM, args: openArray[ScriptValue], i: int, fname: string, def: float32): float32 =
  if arg(args, i).kind == vkNil: def else: vm.numArg(args, i, fname)

proc numField(vm: VM, t: ScriptTable, key, what: string, def: float32): float32 =
  let v = rawGetStr(t, key)
  if v.kind == vkNil: def else: vm.num(v, what & "." & key)

proc boolField(t: ScriptTable, key: string, def: bool): bool =
  let v = rawGetStr(t, key)
  if v.kind == vkNil: def else: truthy(v)

proc hasField(t: ScriptTable, key: string): bool =
  rawGetStr(t, key).kind != vkNil

proc checkKeys(vm: VM, t: ScriptTable, allowed: openArray[string], what: string) =
  ## A typo in an option table is an error naming it, never a silent no-op.
  for (k, _) in pairsCursor(t):
    if k.kind != vkString:
      vm.runtimeError(what & ": keys must be field names")
    if k.str.s notin allowed:
      vm.runtimeError(what & ": unknown field '" & k.str.s & "' (fields: " & allowed.join(", ") & ")")

proc nameIndex(names: openArray[string], s: string, prefix: string): int =
  ## Position of `s` ("chase") or its enum spelling ("aiChase") in `names`.
  for i, n in names:
    if s.toLowerAscii == n or s == prefix & n.capitalizeAscii: return i
  -1

proc parseAi(vm: VM, v: ScriptValue, what: string): EntityAI3D =
  if v.kind != vkString: vm.runtimeError(what & " must be a name (" & AiNames.join(", ") & ")")
  let i = nameIndex(AiNames, v.str.s, "ai")
  if i < 0: vm.runtimeError(what & ": unknown ai '" & v.str.s & "' (" & AiNames.join(", ") & ")")
  EntityAI3D(i)

proc parseShape(vm: VM, v: ScriptValue, what: string): EntityShape3D =
  if v.kind != vkString: vm.runtimeError(what & " must be a name (" & ShapeNames.join(", ") & ")")
  let i = nameIndex(ShapeNames, v.str.s, "es")
  if i < 0: vm.runtimeError(what & ": unknown shape '" & v.str.s & "' (" & ShapeNames.join(", ") & ")")
  EntityShape3D(i)

proc modelValue(id: int): ScriptValue =
  if id <= 0 or modelClass.isNil: NilValue
  else: vud(Userdata(cls: modelClass, handle: id, key: cast[pointer](id + 300000)))

proc vec3Arg(vm: VM, args: openArray[ScriptValue], i: int, fname: string): Vector3f =
  vec3(vm.numArg(args, i, fname), vm.numArg(args, i + 1, fname), vm.numArg(args, i + 2, fname))

proc worldAlive(w: Game3D): proc (): bool {.closure.} =
  result = proc (): bool = activeWorld3D == w

# ---------------------------------------------------- wrappers (the seams) ----
proc wrapWorldImpl(w: Game3D): ScriptValue {.nimcall.} =
  if worldClass.isNil: NilValue
  else: vud(Userdata(cls: worldClass, box: WorldBox(w: w), key: cast[pointer](w)))

proc wrapEntityImpl(e: Entity3D): ScriptValue {.nimcall.} =
  if entityClass.isNil or activeWorld3D.isNil: NilValue
  else: vud(Userdata(cls: entityClass, box: EntityBox(e: e, w: activeWorld3D), key: cast[pointer](e)))

proc wrapProjectileImpl(p: Projectile3D): ScriptValue {.nimcall.} =
  if projectileClass.isNil or activeWorld3D.isNil: NilValue
  else: vud(Userdata(cls: projectileClass, box: ProjectileBox(p: p, w: activeWorld3D), key: cast[pointer](p)))

proc wrapPickupImpl(p: Pickup3D): ScriptValue {.nimcall.} =
  if pickupClass.isNil or activeWorld3D.isNil: NilValue
  else: vud(Userdata(cls: pickupClass, box: PickupBox(p: p, w: activeWorld3D), key: cast[pointer](p)))

proc unwrapEntity(v: ScriptValue): EntityBox =
  if v.kind == vkUserdata and v.ud.cls == entityClass: EntityBox(v.ud.box) else: nil

proc unwrapProjectile(v: ScriptValue): ProjectileBox =
  if v.kind == vkUserdata and v.ud.cls == projectileClass: ProjectileBox(v.ud.box) else: nil

proc unwrapPickup(v: ScriptValue): PickupBox =
  if v.kind == vkUserdata and v.ud.cls == pickupClass: PickupBox(v.ud.box) else: nil

# ---------------------------------------------------------- liveness ----
proc liveWorld(vm: VM, b: WorldBox): Game3D =
  if activeWorld3D != b.w: vm.runtimeError("world no longer exists (the 3D world has ended)")
  b.w

proc liveEntity(vm: VM, b: EntityBox): Entity3D =
  if activeWorld3D != b.w: vm.runtimeError("entity no longer exists (its 3D world has ended)")
  if b.e.removed: vm.runtimeError("entity no longer exists")
  b.e

proc liveProjectile(vm: VM, b: ProjectileBox): Projectile3D =
  if activeWorld3D != b.w: vm.runtimeError("projectile no longer exists (its 3D world has ended)")
  if b.p.removed: vm.runtimeError("projectile no longer exists")
  b.p

proc livePickup(vm: VM, b: PickupBox): Pickup3D =
  if activeWorld3D != b.w: vm.runtimeError("pickup no longer exists (its 3D world has ended)")
  if b.p.removed: vm.runtimeError("pickup no longer exists")
  b.p

proc selfEntity(vm: VM, args: openArray[ScriptValue], fname: string): EntityBox =
  result = unwrapEntity(arg(args, 0))
  if result.isNil: vm.runtimeError("entity:" & fname & "() needs an entity (call it with ':')")

proc selfProjectile(vm: VM, args: openArray[ScriptValue], fname: string): ProjectileBox =
  result = unwrapProjectile(arg(args, 0))
  if result.isNil: vm.runtimeError("projectile:" & fname & "() needs a projectile (call it with ':')")

proc selfPickup(vm: VM, args: openArray[ScriptValue], fname: string): PickupBox =
  result = unwrapPickup(arg(args, 0))
  if result.isNil: vm.runtimeError("pickup:" & fname & "() needs a pickup (call it with ':')")

# ------------------------------------------------------- position shortcuts ----
proc posGet(pos, vel: Vector3f, name: string, found: var bool): ScriptValue =
  found = true
  case name
  of "x": vnum(pos.x.float64)
  of "y": vnum(pos.y.float64)
  of "z": vnum(pos.z.float64)
  of "vx": vnum(vel.x.float64)
  of "vy": vnum(vel.y.float64)
  of "vz": vnum(vel.z.float64)
  else:
    found = false
    NilValue

proc posSet(vm: VM, pos, vel: var Vector3f, name: string, v: ScriptValue): bool =
  case name
  of "x": pos.x = vm.num(v, "x")
  of "y": pos.y = vm.num(v, "y")
  of "z": pos.z = vm.num(v, "z")
  of "vx": vel.x = vm.num(v, "vx")
  of "vy": vel.y = vm.num(v, "vy")
  of "vz": vel.z = vm.num(v, "vz")
  else: return false
  true

# --------------------------------------------------------------- classes ----
proc makeClasses() =
  worldClass = UdClass(name: "world3d", cached: true)
  worldClass.index = proc (vm: VM, ud: Userdata, key: ScriptValue): ScriptValue =
    let m = rawGet(worldMethods, key)
    if m.kind != vkNil: return m
    let w = vm.liveWorld(WorldBox(ud.box))
    let name = keyName(key)
    var found = false
    result = deepGet(w, name, "world", found, worldAlive(w))
    if not found: vm.runtimeError("world has no field '" & name & "'")
  worldClass.newindex = proc (vm: VM, ud: Userdata, key, val: ScriptValue) =
    let w = vm.liveWorld(WorldBox(ud.box))
    let name = keyName(key)
    if not deepSet(vm, w, name, val, "world"):
      vm.runtimeError("world has no field '" & name & "'")
  worldClass.tostr = proc (ud: Userdata): string = "world3d"

  entityClass = UdClass(name: "entity3d", cached: true)
  entityClass.index = proc (vm: VM, ud: Userdata, key: ScriptValue): ScriptValue =
    let m = rawGet(entityMethods, key)
    if m.kind != vkNil: return m
    let b = EntityBox(ud.box)
    let e = vm.liveEntity(b)
    let name = keyName(key)
    var found = false
    result = posGet(e.pos, e.vel, name, found)
    if found: return
    case name
    of "model": return modelValue(e.modelId)
    of "ai": return vstr(AiNames[ord(e.ai)])
    of "shape": return vstr(ShapeNames[ord(e.shape)])
    else: discard
    let w = b.w
    result = deepGet(e, name, "entity", found,
                     proc (): bool = activeWorld3D == w and not e.removed)
    if not found: vm.runtimeError("entity has no field '" & name & "'")
  entityClass.newindex = proc (vm: VM, ud: Userdata, key, val: ScriptValue) =
    let b = EntityBox(ud.box)
    let e = vm.liveEntity(b)
    let name = keyName(key)
    if posSet(vm, e.pos, e.vel, name, val): return
    case name
    of "model":
      if val.kind == vkNil:
        e.modelId = -1
        if e.shape == esModel: e.shape = esSphere
      else:
        e.modelId = vm.modelId(val, "entity.model")
        e.shape = esModel
      return
    of "ai":
      e.ai = vm.parseAi(val, "entity.ai")
      return
    of "shape":
      e.shape = vm.parseShape(val, "entity.shape")
      return
    else: discard
    if not deepSet(vm, e, name, val, "entity"):
      vm.runtimeError("entity has no field '" & name & "'")
    if name == "hp" and e.alive and e.hp <= 0:
      killEntity3D(b.w, e)   # an entity at 0 hp dies, like from a hit
  entityClass.tostr = proc (ud: Userdata): string =
    let b = EntityBox(ud.box)
    "entity #" & $b.e.id & " (" & b.e.tag & ")"

  projectileClass = UdClass(name: "projectile3d", cached: true)
  projectileClass.index = proc (vm: VM, ud: Userdata, key: ScriptValue): ScriptValue =
    let m = rawGet(projectileMethods, key)
    if m.kind != vkNil: return m
    let b = ProjectileBox(ud.box)
    let p = vm.liveProjectile(b)
    let name = keyName(key)
    var found = false
    result = posGet(p.pos, p.vel, name, found)
    if found: return
    let w = b.w
    result = deepGet(p, name, "projectile", found,
                     proc (): bool = activeWorld3D == w and not p.removed)
    if not found: vm.runtimeError("projectile has no field '" & name & "'")
  projectileClass.newindex = proc (vm: VM, ud: Userdata, key, val: ScriptValue) =
    let p = vm.liveProjectile(ProjectileBox(ud.box))
    let name = keyName(key)
    if posSet(vm, p.pos, p.vel, name, val): return
    if not deepSet(vm, p, name, val, "projectile"):
      vm.runtimeError("projectile has no field '" & name & "'")
  projectileClass.tostr = proc (ud: Userdata): string = "projectile3d"

  pickupClass = UdClass(name: "pickup3d", cached: true)
  pickupClass.index = proc (vm: VM, ud: Userdata, key: ScriptValue): ScriptValue =
    let m = rawGet(pickupMethods, key)
    if m.kind != vkNil: return m
    let b = PickupBox(ud.box)
    let p = vm.livePickup(b)
    let name = keyName(key)
    var found = false
    result = posGet(p.pos, Vector3f(), name, found)
    if found and name in ["x", "y", "z"]: return
    let w = b.w
    result = deepGet(p, name, "pickup", found,
                     proc (): bool = activeWorld3D == w and not p.removed)
    if not found: vm.runtimeError("pickup has no field '" & name & "'")
  pickupClass.newindex = proc (vm: VM, ud: Userdata, key, val: ScriptValue) =
    let p = vm.livePickup(PickupBox(ud.box))
    let name = keyName(key)
    var noVel = Vector3f()
    if name in ["x", "y", "z"] and posSet(vm, p.pos, noVel, name, val): return
    if not deepSet(vm, p, name, val, "pickup"):
      vm.runtimeError("pickup has no field '" & name & "'")
  pickupClass.tostr = proc (ud: Userdata): string =
    "pickup3d (" & PickupBox(ud.box).p.kind & ")"

# --------------------------------------------------------------- methods ----
proc installMethods() =
  worldMethods = newScriptTable()
  entityMethods = newScriptTable()
  projectileMethods = newScriptTable()
  pickupMethods = newScriptTable()

  worldMethods.reg("fields") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    let v = arg(args, 0)
    if v.kind != vkUserdata or v.ud.cls != worldClass:
      vm.runtimeError("world:fields() needs the world (call it with ':')")
    ret.setRet(namesTable(deepNames(vm.liveWorld(WorldBox(v.ud.box)))))

  entityMethods.reg("fields") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ret.setRet(namesTable(deepNames(vm.liveEntity(vm.selfEntity(args, "fields")))))
  entityMethods.reg("valid") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## Still in play: in the world, alive, and the world still running.
    let b = vm.selfEntity(args, "valid")
    ret.setRet(vbool(activeWorld3D == b.w and not b.e.removed and b.e.alive))
  entityMethods.reg("damage") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## e:damage(n) -> damage dealt (0 when invulnerable or dead); kills it at 0 hp
    let b = vm.selfEntity(args, "damage")
    let e = vm.liveEntity(b)
    ret.setRet(vnum(damageEntity3D(b.w, e, vm.numArg(args, 1, "damage")).float64))
  entityMethods.reg("kill") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## e:kill([credit = true]) -- runs the death hook; credit adds its score/kill
    let b = vm.selfEntity(args, "kill")
    let e = vm.liveEntity(b)
    let credit = arg(args, 1).kind == vkNil or truthy(arg(args, 1))
    killEntity3D(b.w, e, credit)
  entityMethods.reg("remove") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## e:remove() -- gone at once, no death hook, no score
    let b = vm.selfEntity(args, "remove")
    let e = vm.liveEntity(b)
    e.alive = false
    e.removed = true
  entityMethods.reg("distanceTo") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## e:distanceTo(x, y, z) or e:distanceTo(otherEntity)
    let b = vm.selfEntity(args, "distanceTo")
    let e = vm.liveEntity(b)
    let other = unwrapEntity(arg(args, 1))
    let target = if not other.isNil: vm.liveEntity(other).pos else: vm.vec3Arg(args, 1, "distanceTo")
    ret.setRet(vnum(distance(e.pos, target).float64))

  projectileMethods.reg("fields") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ret.setRet(namesTable(deepNames(vm.liveProjectile(vm.selfProjectile(args, "fields")))))
  projectileMethods.reg("valid") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    let b = vm.selfProjectile(args, "valid")
    ret.setRet(vbool(activeWorld3D == b.w and not b.p.removed and b.p.active))
  projectileMethods.reg("remove") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    let p = vm.liveProjectile(vm.selfProjectile(args, "remove"))
    p.active = false
    p.removed = true

  pickupMethods.reg("fields") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ret.setRet(namesTable(deepNames(vm.livePickup(vm.selfPickup(args, "fields")))))
  pickupMethods.reg("valid") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    let b = vm.selfPickup(args, "valid")
    ret.setRet(vbool(activeWorld3D == b.w and not b.p.removed and b.p.alive))
  pickupMethods.reg("remove") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    let p = vm.livePickup(vm.selfPickup(args, "remove"))
    p.alive = false
    p.removed = true

# ------------------------------------------------------- world3d: content ----
const
  SpawnSpecials = ["x", "y", "z", "vx", "vy", "vz", "model", "ai", "shape", "onSpawn"]
  ProjectileFields = ["x", "y", "z", "vx", "vy", "vz", "damage", "fromPlayer", "radius", "color",
                      "lifetime", "homing", "gravity", "pierce", "tag", "owner"]
  PickupFields = ["x", "y", "z", "kind", "value", "radius", "color"]
  PlatformFields = ["x", "y", "z", "w", "h", "d", "color", "moving", "moveSpeed", "jumpPad",
                    "jumpForce", "rotationSpeed"]
  ArenaFields = ["radius", "bounds", "sky", "floor", "wall", "gravity", "deathPlaneY",
                 "floorVisible", "wallsVisible", "theme", "solidFloor", "floorY"]

proc spawnEntity(vm: VM, t: ScriptTable): ScriptValue =
  let w = vm.requireWorld("world3d.spawn")
  for name in ["id", "alive", "removed"]:
    if t.hasField(name): vm.runtimeError("world3d.spawn: '" & name & "' cannot be set")
  var skip = @SpawnSpecials
  let tagV = rawGetStr(t, "tag")
  if tagV.kind notin {vkNil, vkString}: vm.runtimeError("world3d.spawn.tag must be a string")
  let e = newEntity3D(w, if tagV.kind == vkString: tagV.str.s else: "")
  let sz = rawGetStr(t, "size")
  if sz.kind == vkNumber:            # a number = a cube / cylinder of that size
    let s = vm.num(sz, "world3d.spawn.size")
    e.size = vec3(s, s, s)
    skip.add("size")
  applyTable(vm, e[], t, "world3d.spawn", skip)
  for name in ["x", "y", "z", "vx", "vy", "vz"]:
    let v = rawGetStr(t, name)
    if v.kind != vkNil: discard posSet(vm, e.pos, e.vel, name, v)
  if t.hasField("model"):
    e.modelId = vm.modelId(rawGetStr(t, "model"), "world3d.spawn.model")
    e.shape = esModel
  if t.hasField("shape"): e.shape = vm.parseShape(rawGetStr(t, "shape"), "world3d.spawn.shape")
  if t.hasField("ai"): e.ai = vm.parseAi(rawGetStr(t, "ai"), "world3d.spawn.ai")
  if t.hasField("hp") and not t.hasField("maxHp"): e.maxHp = e.hp
  elif t.hasField("maxHp") and not t.hasField("hp"): e.hp = e.maxHp
  let cb = rawGetStr(t, "onSpawn")
  if cb.kind notin {vkNil, vkFunction, vkNative}:
    vm.runtimeError("world3d.spawn.onSpawn must be a function")
  queueWorld3DAction(World3DAction(kind: wkSpawnEntity, owner: currentModIdx, entity: e, callback: cb))
  wrapEntity3D(e)

proc spawnProjectile(vm: VM, t: ScriptTable): ScriptValue =
  let w = vm.requireWorld("world3d.projectile")
  discard w
  vm.checkKeys(t, ProjectileFields, "world3d.projectile")
  let pos = vec3(vm.numField(t, "x", "world3d.projectile", 0), vm.numField(t, "y", "world3d.projectile", 0),
                 vm.numField(t, "z", "world3d.projectile", 0))
  let vel = vec3(vm.numField(t, "vx", "world3d.projectile", 0), vm.numField(t, "vy", "world3d.projectile", 0),
                 vm.numField(t, "vz", "world3d.projectile", 0))
  let p = newProjectile3D(pos, vel, vm.numField(t, "damage", "world3d.projectile", 10),
                          t.boolField("fromPlayer", false))
  p.radius = max(0'f32, vm.numField(t, "radius", "world3d.projectile", 0))
  if t.hasField("color"): p.color = parseColor(vm, rawGetStr(t, "color"), "world3d.projectile.color")
  p.lifetime = vm.numField(t, "lifetime", "world3d.projectile", p.lifetime)
  p.gravity = vm.numField(t, "gravity", "world3d.projectile", 0)
  p.pierce = max(0, int(vm.numField(t, "pierce", "world3d.projectile", 0)))
  let h = rawGetStr(t, "homing")
  if h.kind == vkNumber:
    p.isHoming = h.n > 0
    p.homingStrength = vm.num(h, "world3d.projectile.homing")
  elif h.kind != vkNil and truthy(h):
    p.isHoming = true
    p.homingStrength = 200.0
  let tg = rawGetStr(t, "tag")
  if tg.kind == vkString: p.tag = tg.str.s
  elif tg.kind != vkNil: vm.runtimeError("world3d.projectile.tag must be a string")
  let owner = rawGetStr(t, "owner")
  if owner.kind != vkNil:
    let ob = unwrapEntity(owner)
    if ob.isNil: vm.runtimeError("world3d.projectile.owner must be an entity")
    p.ownerId = ob.e.id
  queueWorld3DAction(World3DAction(kind: wkSpawnProjectile, owner: currentModIdx, projectile: p))
  wrapProjectile3D(p)

proc spawnPickup(vm: VM, t: ScriptTable): ScriptValue =
  let w = vm.requireWorld("world3d.pickup")
  vm.checkKeys(t, PickupFields, "world3d.pickup")
  let kindV = rawGetStr(t, "kind")
  if kindV.kind notin {vkNil, vkString}: vm.runtimeError("world3d.pickup.kind must be a string")
  let p = newPickup3D(w, vec3(vm.numField(t, "x", "world3d.pickup", 0),
                              vm.numField(t, "y", "world3d.pickup", 0),
                              vm.numField(t, "z", "world3d.pickup", 0)),
                      if kindV.kind == vkString: kindV.str.s else: "health",
                      vm.numField(t, "value", "world3d.pickup", 25))
  p.radius = max(0.1'f32, vm.numField(t, "radius", "world3d.pickup", p.radius))
  if t.hasField("color"): p.color = parseColor(vm, rawGetStr(t, "color"), "world3d.pickup.color")
  queueWorld3DAction(World3DAction(kind: wkSpawnPickup, owner: currentModIdx, pickup: p))
  wrapPickup3D(p)

proc addPlatform(vm: VM, t: ScriptTable): int =
  ## Adds a platform now (nothing iterates the platform list while a hook runs);
  ## w/h/d are full extents, stored as the half extents Platform3D keeps.
  let w = vm.requireWorld("world3d.platform")
  vm.checkKeys(t, PlatformFields, "world3d.platform")
  var p = Platform3D(color: Color(r: 80, g: 80, b: 80, a: 255))
  p.pos = vec3(vm.numField(t, "x", "world3d.platform", 0), vm.numField(t, "y", "world3d.platform", 0),
               vm.numField(t, "z", "world3d.platform", 0))
  p.size = vec3(max(0.1'f32, vm.numField(t, "w", "world3d.platform", 20)) / 2,
                max(0.1'f32, vm.numField(t, "h", "world3d.platform", 2)) / 2,
                max(0.1'f32, vm.numField(t, "d", "world3d.platform", 20)) / 2)
  if t.hasField("color"): p.color = parseColor(vm, rawGetStr(t, "color"), "world3d.platform.color")
  p.moving = t.boolField("moving", false)
  p.moveSpeed = vm.numField(t, "moveSpeed", "world3d.platform", 0.3)
  p.jumpPad = t.boolField("jumpPad", false)
  p.jumpForce = vm.numField(t, "jumpForce", "world3d.platform", if p.jumpPad: 800 else: 0)
  p.rotationSpeed = vm.numField(t, "rotationSpeed", "world3d.platform", 0)
  w.arena.platforms.add(p)
  w.arena.platforms.len

proc applyArena(vm: VM, t: ScriptTable) =
  let w = vm.requireWorld("world3d.arena")
  vm.checkKeys(t, ArenaFields, "world3d.arena")
  let radiusGiven = t.hasField("radius")
  let radius = vm.numField(t, "radius", "world3d.arena", w.arena.radius)
  if radius <= 0: vm.runtimeError("world3d.arena.radius must be positive")
  let theme = rawGetStr(t, "theme")
  if theme.kind != vkNil:
    if theme.kind != vkString or theme.str.s notin Themes:
      vm.runtimeError("world3d.arena.theme must be one of: " & Themes.join(", "))
    w.arena = generateArena(theme.str.s, radius)   # a fresh arena of that theme
  w.arena.radius = radius
  if t.hasField("bounds"):
    w.arena.boundsRadius = max(1'f32, vm.numField(t, "bounds", "world3d.arena", 0))
  elif radiusGiven:
    w.arena.boundsRadius = radius * 0.9'f32
  if t.hasField("sky"): w.arena.skyColor = parseColor(vm, rawGetStr(t, "sky"), "world3d.arena.sky")
  if t.hasField("floor"): w.arena.floorColor = parseColor(vm, rawGetStr(t, "floor"), "world3d.arena.floor")
  if t.hasField("wall"): w.arena.wallColor = parseColor(vm, rawGetStr(t, "wall"), "world3d.arena.wall")
  if t.hasField("gravity"): w.arena.gravity = vm.numField(t, "gravity", "world3d.arena", 0)
  if t.hasField("deathPlaneY"): w.arena.deathPlaneY = vm.numField(t, "deathPlaneY", "world3d.arena", 0)
  if t.hasField("floorVisible"): w.arena.drawFloor = t.boolField("floorVisible", true)
  if t.hasField("wallsVisible"): w.arena.drawWalls = t.boolField("wallsVisible", true)
  if t.hasField("solidFloor"): w.arena.solidFloor = t.boolField("solidFloor", false)
  if t.hasField("floorY"): w.arena.floorY = vm.numField(t, "floorY", "world3d.arena", 0)

proc hitTable(w: Game3D, hit: RayHit3D): ScriptValue =
  let t = newScriptTable()
  rawSet(t, vstr("kind"), vstr(hit.kind))
  rawSet(t, vstr("dist"), vnum(hit.dist.float64))
  rawSet(t, vstr("x"), vnum(hit.pos.x.float64))
  rawSet(t, vstr("y"), vnum(hit.pos.y.float64))
  rawSet(t, vstr("z"), vnum(hit.pos.z.float64))
  if hit.kind == "entity": rawSet(t, vstr("entity"), wrapEntity3D(hit.entity))
  if hit.kind == "platform": rawSet(t, vstr("platform"), vnum(hit.platform + 1))
  vtable(t)

# --------------------------------------------------------------- world3d ----
proc installWorld3dLibrary(base: ScriptTable) =
  let t = newScriptTable()

  t.reg("active") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## world3d.active() -> is a 3D world being played?
    ret.setRet(vbool(not activeWorld3D.isNil and activeWorld3D.active))
  t.reg("enter") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## world3d.enter{boss = false, bossId = 7, keepHp = true} -- from a 2D run; the
    ## 3D world opens at the end of the frame (through the fade to black).
    if modCtx.game.isNil:
      vm.runtimeError("world3d.enter needs a run in progress")
    if not activeWorld3D.isNil:
      vm.runtimeError("world3d.enter: a 3D world is already active")
    if modModeIs3D(modCtx.game.modMode):
      vm.runtimeError("world3d.enter: this run is a 3D mode already")
    let o = arg(args, 0)
    var opts = World3DOptions(bossId: 7, carryHp: true)
    if o.kind == vkTable:
      vm.checkKeys(o.tbl, ["boss", "bossId", "keepHp"], "world3d.enter")
      opts.bossEnabled = o.tbl.boolField("boss", false)
      opts.bossId = int(vm.numField(o.tbl, "bossId", "world3d.enter", 7))
      opts.carryHp = o.tbl.boolField("keepHp", true)
    elif o.kind != vkNil:
      vm.argError("enter", 0, "options must be a table")
    queueModAction(ModAction(kind: makEnter3D, owner: currentModIdx, enter3d: opts))
  t.reg("exit") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## world3d.exit() -- leave the world ("exit"; the 2D run carries on, a 3D mode's run ends)
    requestFinish3D(vm.requireWorld("world3d.exit"), w3Exit)
  t.reg("finish") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## world3d.finish(won) -- end the world as "won" / "lost" (true / false, or the names)
    let w = vm.requireWorld("world3d.finish")
    let v = arg(args, 0)
    var won = true
    case v.kind
    of vkBool: won = v.b
    of vkString:
      if v.str.s == "won": won = true
      elif v.str.s == "lost": won = false
      else: vm.argError("finish", 0, "use true, false, \"won\" or \"lost\"")
    of vkNil: discard
    else: vm.argError("finish", 0, "use true, false, \"won\" or \"lost\"")
    requestFinish3D(w, if won: w3Won else: w3Lost)

  t.reg("spawn") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ret.setRet(spawnEntity(vm, vm.checkTable(args, 0, "spawn")))
  t.reg("entities") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## world3d.entities([tag]) -> array of the live entities (those already in the world)
    let w = vm.requireWorld("world3d.entities")
    let tag = vm.optStr(args, 0, "entities", "\0")
    let list = newScriptTable()
    for e in w.entities:
      if e.alive and (tag == "\0" or e.tag == tag): list.add(wrapEntity3D(e))
    ret.setRet(vtable(list))
  t.reg("projectile") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ret.setRet(spawnProjectile(vm, vm.checkTable(args, 0, "projectile")))
  t.reg("pickup") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ret.setRet(spawnPickup(vm, vm.checkTable(args, 0, "pickup")))
  t.reg("platform") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## world3d.platform{x, y, z, w, h, d, ...} -> its 1-based index in world.arena.platforms
    ret.setRet(vnum(addPlatform(vm, vm.checkTable(args, 0, "platform"))))
  t.reg("clearPlatforms") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    vm.requireWorld("world3d.clearPlatforms").arena.platforms.setLen(0)
  t.reg("arena") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    applyArena(vm, vm.checkTable(args, 0, "arena"))

  t.reg("damagePlayer") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## world3d.damagePlayer(n [, source = "script"]) -> damage taken (difficulty, invulnerability and hooks apply)
    let w = vm.requireWorld("world3d.damagePlayer")
    ret.setRet(vnum(damagePlayer3D(w, vm.numArg(args, 0, "damagePlayer"),
                                   vm.optStr(args, 1, "damagePlayer", "script")).float64))
  t.reg("healPlayer") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    healPlayer3D(vm.requireWorld("world3d.healPlayer"), vm.numArg(args, 0, "healPlayer"))
  t.reg("shake") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## world3d.shake(intensity) -- the camera trembles for `intensity` seconds (max 5)
    let w = vm.requireWorld("world3d.shake")
    w.camera.shakeTime = clamp(vm.numArg(args, 0, "shake"), 0'f32, 5'f32)
  t.reg("damageBoss") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## world3d.damageBoss(n) -> true if this world has a boss to hurt (its HP is not writable)
    let w = vm.requireWorld("world3d.damageBoss")
    let n = vm.numArg(args, 0, "damageBoss")
    let has = w.bossEnabled and w.boss.health > 0
    if has: damageBoss3D(w, n)
    ret.setRet(vbool(has))
  t.reg("boss") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## world3d.boss() -> a snapshot table of the boss (read-only copy), nil without one
    let w = vm.requireWorld("world3d.boss")
    ret.setRet(if w.bossEnabled: objToValue(w.boss) else: NilValue)
  t.reg("raycast") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## world3d.raycast(x, y, z, dx, dy, dz [, maxDist = 1000]) -> {kind, dist, x, y, z, entity, platform}
    let w = vm.requireWorld("world3d.raycast")
    let origin = vm.vec3Arg(args, 0, "raycast")
    let dir = vm.vec3Arg(args, 3, "raycast")
    if dir.length() <= 0: vm.argError("raycast", 3, "the direction cannot be zero")
    let maxDist = vm.optNumArg(args, 6, "raycast", 1000)
    ret.setRet(hitTable(w, raycast3D(w, origin, dir, maxDist)))
  t.reg("aim") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## world3d.aim() -> x, y, z, dx, dy, dz: the camera position and where it looks
    let w = vm.requireWorld("world3d.aim")
    let f = getForward(w.camera)
    ret.setRet([vnum(w.camera.position.x.float64), vnum(w.camera.position.y.float64),
                vnum(w.camera.position.z.float64), vnum(f.x.float64), vnum(f.y.float64),
                vnum(f.z.float64)])
  t.reg("toScreen") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## world3d.toScreen(x, y, z) -> screen x, y, visible (in front of the camera and on screen)
    let w = vm.requireWorld("world3d.toScreen")
    let s = worldToScreen3D(w.camera, vm.vec3Arg(args, 0, "toScreen"))
    ret.setRet([vnum(s.x.float64), vnum(s.y.float64), vbool(s.visible)])
  t.reg("damageNumber") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## world3d.damageNumber(x, y, z, amount [, color]) -- a floating number
    let w = vm.requireWorld("world3d.damageNumber")
    let color = if arg(args, 4).kind == vkNil: Color()
                else: parseColor(vm, arg(args, 4), "world3d.damageNumber")
    spawnDamageNumber3D(w.damageNumbers, vm.vec3Arg(args, 0, "damageNumber"),
                        vm.numArg(args, 3, "damageNumber"), color)

  # world3d.world / world3d.player: read live, so they always name the current world
  let meta = newScriptTable()
  rawSet(meta, vstr("__index"), vnative(newNative("world3d_index",
    proc (vm: VM, args: openArray[ScriptValue], ret: var RetVals) =
      let name = keyName(arg(args, 1))
      case name
      of "world":
        ret.setRet(wrapWorld3D(vm.requireWorld("world3d.world")))
      of "player":
        let w = vm.requireWorld("world3d.player")
        var found = false
        ret.setRet(deepGet(w, "player", "world", found, worldAlive(w)))
      else:
        ret.setRet(NilValue))))
  t.meta = meta
  rawSet(base, vstr("world3d"), vtable(t))

# ---------------------------------------------------------------- draw3d ----
proc requireDrawing3D(vm: VM, fname: string) =
  if modCtx.drawing != dtWorld3D or activeWorld3D.isNil:
    vm.runtimeError("draw3d." & fname & " only works inside world3dDraw and world3dEntityDraw " &
                    "(2D drawing goes in world3dDrawHud, with the draw library)")

proc installDraw3dLibrary(base: ScriptTable) =
  let t = newScriptTable()

  t.reg("cube") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## draw3d.cube(x, y, z, w, h, d, color) -- centred on x, y, z
    vm.requireDrawing3D("cube")
    let p = vm.vec3Arg(args, 0, "cube")
    let size = vm.vec3Arg(args, 3, "cube")
    drawCube(Vector3(x: p.x, y: p.y, z: p.z), size.x, size.y, size.z, parseColor(vm, arg(args, 6), "draw3d.cube"))
  t.reg("cubeWires") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    vm.requireDrawing3D("cubeWires")
    let p = vm.vec3Arg(args, 0, "cubeWires")
    let size = vm.vec3Arg(args, 3, "cubeWires")
    drawCubeWires(Vector3(x: p.x, y: p.y, z: p.z), size.x, size.y, size.z,
                  parseColor(vm, arg(args, 6), "draw3d.cubeWires"))
  t.reg("sphere") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## draw3d.sphere(x, y, z, radius, color)
    vm.requireDrawing3D("sphere")
    let p = vm.vec3Arg(args, 0, "sphere")
    let r = vm.numArg(args, 3, "sphere")
    drawSphere(Vector3(x: p.x, y: p.y, z: p.z), r, parseColor(vm, arg(args, 4), "draw3d.sphere"))
  t.reg("sphereWires") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## draw3d.sphereWires(x, y, z, radius, color [, rings = 8, slices = 8])
    vm.requireDrawing3D("sphereWires")
    let p = vm.vec3Arg(args, 0, "sphereWires")
    let r = vm.numArg(args, 3, "sphereWires")
    let rings = clamp(vm.optInt(args, 5, "sphereWires", 8), 3, 64).int32
    let slices = clamp(vm.optInt(args, 6, "sphereWires", 8), 3, 64).int32
    drawSphereWires(Vector3(x: p.x, y: p.y, z: p.z), r, rings, slices,
                    parseColor(vm, arg(args, 4), "draw3d.sphereWires"))
  t.reg("cylinder") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## draw3d.cylinder(x, y, z, radius, height, color [, slices = 16]) -- centred on x, y, z
    vm.requireDrawing3D("cylinder")
    let p = vm.vec3Arg(args, 0, "cylinder")
    let r = vm.numArg(args, 3, "cylinder")
    let h = vm.numArg(args, 4, "cylinder")
    let slices = clamp(vm.optInt(args, 6, "cylinder", 16), 3, 64).int32
    drawCylinder(Vector3(x: p.x, y: p.y - h / 2, z: p.z), r, r, h, slices,
                 parseColor(vm, arg(args, 5), "draw3d.cylinder"))
  t.reg("cylinderWires") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    vm.requireDrawing3D("cylinderWires")
    let p = vm.vec3Arg(args, 0, "cylinderWires")
    let r = vm.numArg(args, 3, "cylinderWires")
    let h = vm.numArg(args, 4, "cylinderWires")
    let slices = clamp(vm.optInt(args, 6, "cylinderWires", 16), 3, 64).int32
    drawCylinderWires(Vector3(x: p.x, y: p.y - h / 2, z: p.z), r, r, h, slices,
                      parseColor(vm, arg(args, 5), "draw3d.cylinderWires"))
  t.reg("line") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## draw3d.line(x1, y1, z1, x2, y2, z2, color)
    vm.requireDrawing3D("line")
    let a = vm.vec3Arg(args, 0, "line")
    let b = vm.vec3Arg(args, 3, "line")
    drawLine3D(Vector3(x: a.x, y: a.y, z: a.z), Vector3(x: b.x, y: b.y, z: b.z),
               parseColor(vm, arg(args, 6), "draw3d.line"))
  t.reg("grid") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## draw3d.grid([slices = 10, spacing = 1, y = 0]) -- a grid on the floor plane around the origin
    vm.requireDrawing3D("grid")
    let slices = clamp(vm.optInt(args, 0, "grid", 10), 1, 500).int32
    let spacing = vm.optNumArg(args, 1, "grid", 1)
    let y = vm.optNumArg(args, 2, "grid", 0)
    rlgl.pushMatrix()
    rlgl.translatef(0, y, 0)
    drawGrid(slices, spacing)
    rlgl.popMatrix()
  t.reg("plane") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## draw3d.plane(x, y, z, w, d, color) -- a flat quad centred on x, y, z, w wide on x, d deep on z
    vm.requireDrawing3D("plane")
    let p = vm.vec3Arg(args, 0, "plane")
    let sw = vm.numArg(args, 3, "plane")
    let sd = vm.numArg(args, 4, "plane")
    drawPlane(Vector3(x: p.x, y: p.y, z: p.z), Vector2(x: sw, y: sd),
              parseColor(vm, arg(args, 5), "draw3d.plane"))
  t.reg("model") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## draw3d.model(mdl, x, y, z [, {scale, size, yaw, pitch, roll, spin, animation,
    ##   time, frame, speed, tint, lit}]) -- centred on x, y, z. scale = world units
    ##   per model unit; size = fit its footprint to that many units (default 8).
    vm.requireDrawing3D("model")
    let id = vm.modelId(arg(args, 0), "draw3d.model")
    let p = vm.vec3Arg(args, 1, "model")
    let opts = arg(args, 4)
    if opts.kind notin {vkNil, vkTable}: vm.argError("model", 4, "options must be a table")
    var pose = vm.readPose(opts, id, "draw3d.model")
    var scale = 8.0'f32 / modelFootprint(id)
    var time = if activeWorld3D.isNil: getTime() else: activeWorld3D.timeElapsed.float
    if opts.kind == vkTable:
      let sc = rawGetStr(opts.tbl, "scale")
      let sz = rawGetStr(opts.tbl, "size")
      if sc.kind != vkNil:
        scale = vm.num(sc, "draw3d.model.scale")
        if not (scale > 0): vm.runtimeError("draw3d.model.scale must be positive")
      elif sz.kind != vkNil:
        let s = vm.num(sz, "draw3d.model.size")
        if not (s > 0): vm.runtimeError("draw3d.model.size must be positive")
        scale = s / modelFootprint(id)
      let fr = rawGetStr(opts.tbl, "frame")
      let tm = rawGetStr(opts.tbl, "time")
      if fr.kind != vkNil and pose.anim > 0:
        let f = vm.num(fr, "draw3d.model.frame")
        pose.speed = 1
        time = floorMod(f.float - 1.0, modelAnimFrames(id, pose.anim).float) / ModelFps
      elif tm.kind != vkNil:
        time = vm.num(tm, "draw3d.model.time").float
    drawModelWorld3D(id, p.x, p.y, p.z, scale, pose.yaw, pose.pitch, pose.roll, pose, White, time)
  t.reg("billboard") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## draw3d.billboard(texture, x, y, z [, size = 8, tint]) -- a sprite that always faces the camera
    vm.requireDrawing3D("billboard")
    let id = vm.textureId(arg(args, 0), "draw3d.billboard")
    let p = vm.vec3Arg(args, 1, "billboard")
    let size = vm.optNumArg(args, 4, "billboard", 8)
    let tint = if arg(args, 5).kind == vkNil: White else: parseColor(vm, arg(args, 5), "draw3d.billboard")
    drawTextureBillboard(id, raylibCamera(activeWorld3D.camera), p.x, p.y, p.z, size, tint)
  t.reg("text") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## draw3d.text(text, x, y, z [, size = 20, color]) -- a label at a world point, drawn over the scene
    vm.requireDrawing3D("text")
    let s = vm.checkStr(args, 0, "text")
    let p = vm.vec3Arg(args, 1, "text")
    let size = clamp(vm.optInt(args, 4, "text", 20), 10, 120).int32
    let color = if arg(args, 5).kind == vkNil: White else: parseColor(vm, arg(args, 5), "draw3d.text")
    if world3dLabels.len < MaxWorld3DLabels:
      world3dLabels.add(World3DLabel(pos: p, text: s, size: size, color: color))

  rawSet(base, vstr("draw3d"), vtable(t))

# ---------------------------------------------------------------- install ----
proc installMod3D*(base: ScriptTable) =
  ## Build the 3D classes and libraries (once per reload, after installModApi:
  ## it needs the model / texture classes and helpers from there).
  makeClasses()
  installMethods()
  installWorld3dLibrary(base)
  installDraw3dLibrary(base)
  wrapWorld3DImpl = wrapWorldImpl
  wrapEntity3DImpl = wrapEntityImpl
  wrapProjectile3DImpl = wrapProjectileImpl
  wrapPickup3DImpl = wrapPickupImpl
