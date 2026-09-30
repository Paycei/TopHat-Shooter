## Deep field access for mod scripts: every part of the game state, not just
## the top-level numbers.
##
##   game.survival.phase               -- nested objects
##   game.rogueliteRun.floorNumber     -- refs
##   player.powerUps[1].level          -- lists (1-based, like Lua)
##   #game.coins, ipairs(game.walls)   -- length and iteration
##   game.shopItems[2].baseCost = 5    -- writes, down to any depth
##
## A proxy never holds a raw pointer across calls: it holds a *resolver* that
## walks from its root (a Game/Player/Enemy/Bullet ref it keeps alive) to the
## field every time it is used, re-checking list bounds on the way. A list
## that grew or shrank, or a ref that was replaced, is therefore seen as it is
## now; an element that is gone reads as "no longer exists" instead of
## touching freed memory.
##
## Built on fieldPairs like mod_reflect, so any new field anywhere in the data
## model is scriptable with no code here. Game/Player/Enemy/Bullet refs met on
## the way come back as the regular wrappers (so their own rules, e.g. boss HP
## being read-only, still hold). Tables, deques, raw pointers, procs and GPU /
## audio resources stay invisible: scripts cannot corrupt them.

import std/[strutils, math, tables, deques, locks]
import raylib
import ../types, ../game3d/types_3d
import lua_bridge, mod_reflect, mod_hooks

type
  Resolver* = proc (): pointer {.closure.}
    ## Address of the proxied value right now, or nil if it no longer exists.

  DeepBox = ref object of RootObj
    get: Resolver
    readOnly: bool
    path: string          ## "game.survival", for messages and tostring

const
  HiddenFields = ["discordClient", "game3D"]
    ## Never shown: platform handles and raw pointers. Pruned at compile time,
    ## so their types are never walked at all.
  ReadOnlyRoots = ["rogueliteProfile"]
    ## Readable but frozen, with everything under it: the roguelite profile is
    ## the player's real meta progression, saved outside the (cheated) run.
  ReadOnlyPaths = ["world.active", "world.result", "world.pendingResult", "world.quitRequested",
                   "world.bossEnabled", "world.bossId", "world.modeKey", "world.resumed",
                   "world.carryHp", "world.startFired", "world.paused", "world.nextId",
                   "world.boss.health", "world.boss.maxHealth",
                   "entity.id", "entity.alive", "entity.removed",
                   "projectile.removed", "pickup.id", "pickup.removed"]
    ## Single fields (by path from a 3D-world root) a script may read but not
    ## write: the world's own bookkeeping, a boss's HP (world3d.damageBoss), ids.

template isOpaque(F: typedesc): bool =
  ## Types a script must never see inside of.
  F is Table or F is OrderedTable or F is CountTable or F is Deque or
    F is Texture or F is RenderTexture or F is Image or F is Font or F is Shader or
    F is Sound or F is Music or F is Wave or F is AudioStream or F is Mesh or
    F is Model or F is Material or F is ModelAnimation or
    F is pointer or F is ptr or F is proc or F is cstring or
    # OS sync/thread handles: importc structs whose Nim-side fields are a
    # stand-in (Linux's pthread_mutex_t has no `abi`), so touching them in
    # generated C does not even compile.
    F is Lock or F is Cond or F is Thread

proc keyStr(key: ScriptValue): string =
  case key.kind
  of vkString: "'" & key.str.s & "'"
  of vkNumber: numToStr(key.n)
  else: typeName(key)

proc offsetResolver(parent: Resolver, off: int): Resolver =
  ## A field `off` bytes into whatever `parent` resolves to.
  result = proc (): pointer =
    let a = parent()
    if a.isNil: nil else: cast[pointer](cast[int](a) + off)

proc deepObject[T](get: Resolver, ro: bool, path: string): ScriptValue
proc deepList[C](get: Resolver, ro: bool, path: string): ScriptValue

proc fieldValue[F](p: ptr F, get: Resolver, ro: bool, path: string): ScriptValue =
  ## What a script sees for the value at `p` (resolved again later by `get`).
  when F is Game: wrapGame(p[])
  elif F is Player: wrapPlayer(p[])
  elif F is Enemy: wrapEnemy(p[])
  elif F is Bullet: wrapBullet(p[])
  elif F is Game3D: wrapWorld3D(p[])
  elif F is Entity3D: wrapEntity3D(p[])
  elif F is Projectile3D: wrapProjectile3D(p[])
  elif F is Pickup3D: wrapPickup3D(p[])
  elif isOpaque(F): NilValue
  elif compiles(toScript(p[])): toScript(p[])
  elif F is ref:
    when typeof(p[][]) is object or typeof(p[][]) is tuple:
      if p[].isNil:
        NilValue
      else:
        let parent = get
        deepObject[typeof(p[][])](proc (): pointer =
          let a = parent()
          if a.isNil: return nil
          let r = cast[ptr F](a)[]
          if r.isNil: nil else: cast[pointer](r), ro, path)
    else:
      NilValue
  elif F is object or F is tuple: deepObject[F](get, ro, path)
  elif F is seq or F is array: deepList[F](get, ro, path)
  else: NilValue

proc visible[F](p: ptr F): bool =
  ## Whether fieldValue shows anything for this type (for fields() / pairs).
  when isOpaque(F): false
  elif F is Game or F is Player or F is Enemy or F is Bullet: true
  elif F is Game3D or F is Entity3D or F is Projectile3D or F is Pickup3D: true
  elif compiles(toScript(p[])): true
  elif F is ref: typeof(p[][]) is object or typeof(p[][]) is tuple
  elif F is object or F is tuple or F is seq or F is array: true
  else: false

proc fieldAssign[F](vm: VM, p: ptr F, val: ScriptValue, path: string) =
  when F is Game or F is Player or F is Enemy or F is Bullet or isOpaque(F) or F is ref:
    vm.runtimeError(path & " cannot be replaced (change its fields instead)")
  elif compiles(assignScript(vm, p[], val, path)):
    assignScript(vm, p[], val, path)
  elif F is object:
    if val.kind != vkTable:
      vm.runtimeError(path & " must be set from a table of its fields")
    applyTable(vm, p[], val.tbl, path)
  elif F is seq or F is array:
    # Element by element, into the list as it is (lists never change length
    # from a script: the game owns what they hold).
    if val.kind != vkTable:
      vm.runtimeError(path & " must be set from a list")
    let n = min(val.tbl.len, p[].len)
    for i in 0 ..< n:
      when F is array:
        fieldAssign(vm, addr p[][typeof(low(p[]))(ord(low(p[])) + i)], val.tbl.item(i + 1),
                    path & "[" & $(i + 1) & "]")
      else:
        fieldAssign(vm, addr p[][i], val.tbl.item(i + 1), path & "[" & $(i + 1) & "]")
  else:
    vm.runtimeError(path & " cannot be set from a script")

# --------------------------------------------------------------- objects ----
proc fieldNames[T](p: ptr T): seq[string] =
  for fname, f in fieldPairs(p[]):
    when fname notin HiddenFields and compiles(addr f):
      if visible(addr f):
        result.add(fname)

proc indexObj[T](p: ptr T, get: Resolver, name: string, ro: bool, path: string,
                 found: var bool): ScriptValue =
  found = false
  if name in HiddenFields:
    found = true   # exists, but reads as nil
    return NilValue
  for fname, f in fieldPairs(p[]):
    when fname notin HiddenFields:
      if fname == name:
        found = true
        when compiles(addr f):
          let off = cast[int](addr f) - cast[int](p)
          return fieldValue(addr f, offsetResolver(get, off),
                            ro or fname in ReadOnlyRoots, path & "." & fname)
        else:
          # A variant's discriminator: readable, never writable.
          when compiles(toScript(f)): return toScript(f)
          else: return NilValue
  NilValue

proc setObj[T](vm: VM, p: ptr T, name: string, val: ScriptValue, ro: bool, path: string): bool =
  if name in HiddenFields:
    vm.runtimeError(path & "." & name & " is not available to scripts")
  for fname, f in fieldPairs(p[]):
    when fname notin HiddenFields:
      if fname == name:
        if ro or fname in ReadOnlyRoots or (path & "." & fname) in ReadOnlyPaths:
          vm.runtimeError(path & "." & fname & " is read-only")
        when compiles(addr f):
          fieldAssign(vm, addr f, val, path & "." & fname)
          return true
        else:
          vm.runtimeError(path & "." & fname & " is read-only")
  false

proc namesValue(names: seq[string]): ScriptValue =
  let t = newScriptTable(names.len)
  for n in names: t.add(vstr(n))
  vtable(t)

proc objClass[T](): UdClass =
  var cls {.global.}: UdClass
  if cls.isNil:
    cls = UdClass(name: "object")
    cls.index = proc (vm: VM, ud: Userdata, key: ScriptValue): ScriptValue =
      let box = DeepBox(ud.box)
      let raw = box.get()
      if raw.isNil: vm.runtimeError(box.path & " no longer exists")
      let p = cast[ptr T](raw)
      if key.kind != vkString: return NilValue
      var found = false
      result = indexObj(p, box.get, key.str.s, box.readOnly, box.path, found)
      if not found:
        if key.str.s == "fields":
          let names = fieldNames(p)
          return vnative(newNative("fields", proc (vm: VM, a: openArray[ScriptValue], r: var RetVals) =
            r.setRet(namesValue(names))))
        vm.runtimeError(box.path & " has no field '" & key.str.s & "'")
    cls.newindex = proc (vm: VM, ud: Userdata, key, val: ScriptValue) =
      let box = DeepBox(ud.box)
      let raw = box.get()
      if raw.isNil: vm.runtimeError(box.path & " no longer exists")
      if key.kind != vkString or
         not setObj(vm, cast[ptr T](raw), key.str.s, val, box.readOnly, box.path):
        vm.runtimeError(box.path & " has no field '" & keyStr(key) & "'")
    cls.next = proc (vm: VM, ud: Userdata, key: ScriptValue, k, v: var ScriptValue): bool =
      let box = DeepBox(ud.box)
      let raw = box.get()
      if raw.isNil: return false
      let p = cast[ptr T](raw)
      let names = fieldNames(p)
      var at = 0
      if key.kind == vkString:
        at = names.find(key.str.s) + 1
        if at == 0: return false
      if at >= names.len: return false
      var found = false
      k = vstr(names[at])
      v = indexObj(p, box.get, names[at], box.readOnly, box.path, found)
      true
    cls.tostr = proc (ud: Userdata): string = DeepBox(ud.box).path
  cls

proc deepObject[T](get: Resolver, ro: bool, path: string): ScriptValue =
  let raw = get()
  if raw.isNil: return NilValue
  vud(Userdata(cls: objClass[T](), box: DeepBox(get: get, readOnly: ro, path: path), key: raw))

# ----------------------------------------------------------------- lists ----
template elemAt(c: untyped, i: int): untyped =
  when typeof(c) is array: c[typeof(low(c))(ord(low(c)) + i)]
  else: c[i]

proc elemResolver[C](parent: Resolver, i: int): Resolver =
  result = proc (): pointer =
    let a = parent()
    if a.isNil: return nil
    let c = cast[ptr C](a)
    if i < 0 or i >= c[].len: nil else: cast[pointer](addr elemAt(c[], i))

proc listPos[C](vm: VM, c: ptr C, key: ScriptValue): int =
  ## 0-based position for a script key (1-based number, or an enum name for
  ## arrays indexed by an enum); -1 if there is no such element.
  if key.kind == vkNumber:
    let n = key.n
    if n != floor(n): return -1
    let i = int(n) - 1
    return if i >= 0 and i < c[].len: i else: -1
  when C is array:
    when typeof(low(c[])) is enum:
      if key.kind == vkString:
        try:
          let e = parseEnum[typeof(low(c[]))](key.str.s)
          return ord(e) - ord(low(c[]))
        except ValueError:
          return -1
  -1

proc listClass[C](): UdClass =
  var cls {.global.}: UdClass
  if cls.isNil:
    cls = UdClass(name: "list")
    cls.len = proc (vm: VM, ud: Userdata): int =
      let raw = DeepBox(ud.box).get()
      if raw.isNil: 0 else: cast[ptr C](raw)[].len
    cls.index = proc (vm: VM, ud: Userdata, key: ScriptValue): ScriptValue =
      let box = DeepBox(ud.box)
      let raw = box.get()
      if raw.isNil: vm.runtimeError(box.path & " no longer exists")
      let c = cast[ptr C](raw)
      let i = listPos(vm, c, key)
      if i < 0: return NilValue
      fieldValue(addr elemAt(c[], i), elemResolver[C](box.get, i), box.readOnly,
                 box.path & "[" & $(i + 1) & "]")
    cls.newindex = proc (vm: VM, ud: Userdata, key, val: ScriptValue) =
      let box = DeepBox(ud.box)
      if box.readOnly: vm.runtimeError(box.path & " is read-only")
      let raw = box.get()
      if raw.isNil: vm.runtimeError(box.path & " no longer exists")
      let c = cast[ptr C](raw)
      let i = listPos(vm, c, key)
      if i < 0:
        vm.runtimeError(box.path & ": no element " & keyStr(key) &
                        " (lists keep their length; use the game's API to add or remove)")
      fieldAssign(vm, addr elemAt(c[], i), val, box.path & "[" & $(i + 1) & "]")
    cls.next = proc (vm: VM, ud: Userdata, key: ScriptValue, k, v: var ScriptValue): bool =
      let box = DeepBox(ud.box)
      let raw = box.get()
      if raw.isNil: return false
      let c = cast[ptr C](raw)
      let i = if key.kind == vkNumber: int(key.n) else: 0
      if i < 0 or i >= c[].len: return false
      k = vnum(i + 1)
      v = fieldValue(addr elemAt(c[], i), elemResolver[C](box.get, i), box.readOnly,
                     box.path & "[" & $(i + 1) & "]")
      true
    cls.tostr = proc (ud: Userdata): string =
      let box = DeepBox(ud.box)
      let raw = box.get()
      box.path & " (" & $(if raw.isNil: 0 else: cast[ptr C](raw)[].len) & " items)"
    when C is seq[Enemy] or C is seq[Bullet] or C is seq[Entity3D] or C is seq[Projectile3D] or
         C is seq[Pickup3D]:
      # `for e in game:enemies() do` -- calling a list of enemies (or bullets, or a
      # 3D world's entities / projectiles / pickups) iterates it, skipping what is
      # already dead.
      cls.call = proc (vm: VM, ud: Userdata, args: openArray[ScriptValue], ret: var RetVals) =
        let get = DeepBox(ud.box).get
        var i = 0
        ret.setRet(vnative(newNative("list_iterator", proc (vm: VM, a: openArray[ScriptValue], r: var RetVals) =
          let raw = get()
          if raw.isNil:
            r.setRet(NilValue)
            return
          let c = cast[ptr C](raw)
          while i < c[].len:
            let x = c[][i]
            inc i
            when C is seq[Enemy]:
              if x.hp > 0:
                r.setRet(wrapEnemy(x))
                return
            elif C is seq[Bullet]:
              r.setRet(wrapBullet(x))
              return
            elif C is seq[Entity3D]:
              if x.alive:
                r.setRet(wrapEntity3D(x))
                return
            elif C is seq[Projectile3D]:
              if x.active:
                r.setRet(wrapProjectile3D(x))
                return
            else:
              if x.alive:
                r.setRet(wrapPickup3D(x))
                return
          r.setRet(NilValue))))
  cls

proc deepList[C](get: Resolver, ro: bool, path: string): ScriptValue =
  let raw = get()
  if raw.isNil: return NilValue
  vud(Userdata(cls: listClass[C](), box: DeepBox(get: get, readOnly: ro, path: path), key: raw))

# ------------------------------------------------------------ top level ----
# The game / player / enemy / bullet classes (mod_api) fall back to these for
# every field their own rules do not cover.

proc rootResolver[T: ref object](obj: T, alive: proc (): bool {.closure.} = nil): Resolver =
  ## `alive` (optional) says whether the root is still the thing it was: a proxy
  ## reached from it then reads "no longer exists" once it is not (a 3D world
  ## that ended), rather than showing a stale object.
  let keep = obj
  result = proc (): pointer =
    if not alive.isNil and not alive(): nil else: cast[pointer](keep)

proc deepGet*[T: ref object](obj: T, name, path: string, found: var bool,
                             alive: proc (): bool {.closure.} = nil): ScriptValue =
  indexObj(cast[ptr typeof(obj[])](cast[pointer](obj)), rootResolver(obj, alive), name, false, path, found)

proc deepSet*[T: ref object](vm: VM, obj: T, name: string, val: ScriptValue, path: string): bool =
  setObj(vm, cast[ptr typeof(obj[])](cast[pointer](obj)), name, val, false, path)

proc deepNames*[T: ref object](obj: T): seq[string] =
  fieldNames(cast[ptr typeof(obj[])](cast[pointer](obj)))
