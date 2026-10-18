## Deep field access for mod scripts: every part of the game state, not just
## the top-level numbers.
##
##   game.survival.phase               -- nested objects
##   game.rogueliteRun.floorNumber     -- refs
##   player.powerUps[1].level          -- lists (1-based, like Lua)
##   #game.coins, ipairs(game.walls)   -- length and iteration
##   game.shopItems[2].baseCost = 5    -- writes, down to any depth
##   game.walls:add{...}, :remove(i)   -- lists grow and shrink (at safe points)
##   stats.killsByType.etCube          -- tables, by key
##   engine.globals.settings           -- the game's global state
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
## the way come back as the regular wrappers (so their own rules still hold).
## Mods are trusted, so everything is writable, the player's real progression
## included; what stays invisible is only what a script could not touch
## without corrupting memory: deques, raw pointers, procs, OS handles and
## GPU / audio resources. Tables are visible when their keys are strings,
## enums or integers. A list or table changes its length only at a safe point
## (mod_hooks.requireStructural), because the game may be walking it further
## down the stack.
##
## The cost of reaching every type is generated code, so it is kept per field
## *type*, not per field: an object type is a FieldTable (each field's name,
## offset and the reader / writer of its type, worked out once), a list type a
## ListOps, and every object proxy and every list proxy share one class each.
##
## scriptToNim is the one conversion of a script value into a Nim value of
## any type (writes, list:add, and the mixin layer's arguments).

import std/[strutils, math, tables, deques, locks]
import raylib
import ../types, ../game3d/types_3d
import lua_bridge, mod_reflect, mod_hooks, mod_patch_core

type
  Resolver* = proc (): pointer {.closure.}
    ## Address of the proxied value right now, or nil if it no longer exists.

  FieldGet = proc (p: pointer, get: Resolver, ro: bool, path: string): ScriptValue {.nimcall.}
  FieldSet = proc (vm: VM, p: pointer, val: ScriptValue, path: string, fresh: bool) {.nimcall.}

  FieldEntry = object
    name: string
    offset: int
    get: FieldGet
    set: FieldSet

  FieldTable = ref object
    ## An object type as scripts see it (one per type, made once).
    entries: seq[FieldEntry]
    byName: Table[string, int]
    visible: seq[string]   ## what fields() and pairs() list

  ElemAt = proc (c: pointer, i: int): pointer {.nimcall.}

  ListOps = ref object
    ## A list type as scripts see it (one per type, made once).
    len: proc (c: pointer): int {.nimcall.}
    at: ElemAt
    get: FieldGet          ## an element's value
    set: FieldSet          ## write an element
    byName: proc (name: string): int {.nimcall.}   ## arrays indexed by an enum; else nil
    put: proc (vm: VM, c: pointer, pos: int, val: ScriptValue, path: string) {.nimcall.}
      ## insert a new item at `pos` (-1: at the end); nil for fixed-size arrays
    remove: proc (c: pointer, pos: int) {.nimcall.}
    resize: proc (vm: VM, c: pointer, n: int) {.nimcall.}
    step: proc (c: pointer, i: var int): ScriptValue {.nimcall.}
      ## entity lists: calling the list iterates the live ones; else nil

  DeepBox = ref object of RootObj
    get: Resolver
    readOnly: bool
    path: string          ## "game.survival", for messages and tostring
    fields: FieldTable    ## an object proxy's type
    list: ListOps         ## a list proxy's type
    owner: RootRef        ## a resource a script made: its ResBox

const
  HiddenFields = ["discordClient", "game3D", "modThings", "networkManager"]
    ## Never shown: platform handles, raw pointers and sockets. Pruned at
    ## compile time, so their types are never walked at all.
  ReadOnlyPaths = ["world.active", "world.result", "world.pendingResult", "world.quitRequested",
                   "world.bossEnabled", "world.bossId", "world.modeKey", "world.resumed",
                   "world.carryHp", "world.startFired", "world.paused", "world.nextId",
                   "world.boss.health", "world.boss.maxHealth",
                   "entity.id", "entity.alive", "entity.removed",
                   "projectile.removed", "pickup.id", "pickup.removed"]
    ## Single fields (by path from a 3D-world root) a script may read but not
    ## write: the world's own bookkeeping, a boss's HP (world3d.damageBoss), ids.

template isResource*(F: typedesc): bool =
  ## raylib's GPU / audio resources: scripts hold them as handles (rl.*).
  F is Texture or F is RenderTexture or F is Font or F is Shader or F is Sound or
    F is Music or F is Wave or F is AudioStream or F is Mesh or F is Model or
    F is Material or F is ModelAnimation or F is Image

template tableKey(F: typedesc): untyped = typeof(keys(default(F)))
template tableVal(F: typedesc): untyped = typeof(values(default(F)))

proc isScriptTable[F](): bool {.compileTime.} =
  ## A Table / OrderedTable a script can index: string, enum or integer keys.
  when F is Table or F is OrderedTable:
    tableKey(F) is string or tableKey(F) is enum or tableKey(F) is SomeInteger
  else:
    false

template isOpaque(F: typedesc): bool =
  ## Types a script must never see inside of.
  ((F is Table or F is OrderedTable) and not isScriptTable[F]()) or
    F is CountTable or F is Deque or
    F is Texture or F is RenderTexture or F is Image or F is Font or F is Shader or
    F is Sound or F is Music or F is Wave or F is AudioStream or F is Mesh or
    F is Model or F is Material or F is ModelAnimation or
    F is pointer or F is ptr or F is proc or F is cstring or
    # the script runtime's own machinery (its values convert directly, below)
    F is VM or F is UdClass or
    # OS sync/thread handles: importc structs whose Nim-side fields are a
    # stand-in (Linux's pthread_mutex_t has no `abi`), so touching them in
    # generated C does not even compile.
    F is Lock or F is Cond or F is Thread

template copyHookAvailable(T: typedesc): bool =
  ## Whether T's own =copy can be called: false for a type that declares
  ## `=copy {.error.}` (raylib's resources, the script runtime's references,
  ## rlgl's batch, the Discord client...). An explicit call is checked in the
  ## semantic pass; `compiles(a = b)` is not (hooks are checked later), and
  ## neither is the hook lifted for a type that only *holds* such a field,
  ## hence copyable's walk.
  compiles(block:
    var a, b: T
    `=copy`(a, b))

proc copyable*[T](): bool {.compileTime.} =
  ## Whether a T can be copied: false when it holds, anywhere inside, a type
  ## whose copy is forbidden.
  when T is Texture or T is RenderTexture or T is Font or T is Shader or T is Sound or
       T is Music or T is AudioStream or T is Mesh or T is Model or T is ModelAnimation or
       T is Material or T is MaterialMap or T is AutomationEventList:
    false
  elif T is ref or T is ptr or T is pointer or T is proc or T is cstring:
    true   # a reference: copying it copies no resource
  elif T is distinct:
    copyable[distinctBaseOf(T)]()   # (SoundAlias, naylib's views of a Mesh or a Font...)
  elif T is object or T is tuple:
    when not copyHookAvailable(T):
      false
    else:
      result = true
      var probe: T
      for name, f in fieldPairs(probe):
        when not copyable[typeof(f)](): result = false
  elif T is seq or T is array:
    copyable[typeof(items(default(T)))]()
  else:
    true

proc keyStr(key: ScriptValue): string =
  case key.kind
  of vkString: "'" & key.str.s & "'"
  of vkNumber: numToStr(key.n)
  else: typeName(key)

# ------------------------------------------------- shared closure makers ----
# A closure made inside a generic proc gets its own environment type (with
# destroy and trace hooks) for every type it is instantiated for; these are
# made once, and the per-type parts they call are plain nimcall procs.
proc offsetResolver(parent: Resolver, off: int): Resolver =
  ## A field `off` bytes into whatever `parent` resolves to.
  result = proc (): pointer =
    let a = parent()
    if a.isNil: nil else: cast[pointer](cast[int](a) + off)

proc derefResolver(parent: Resolver): Resolver =
  ## The object a ref (stored where `parent` resolves to) points at.
  result = proc (): pointer =
    let a = parent()
    if a.isNil: nil else: cast[ptr pointer](a)[]

proc elemResolver(parent: Resolver, i: int, at: ElemAt): Resolver =
  result = proc (): pointer =
    let a = parent()
    if a.isNil: nil else: at(a, i)

proc constNative(name: string, v: ScriptValue): ScriptValue =
  vnative(newNative(name, proc (vm: VM, a: openArray[ScriptValue], r: var RetVals) = r.setRet(v)))

proc deepObject[T](get: Resolver, ro: bool, path: string): ScriptValue
proc resView*[T](get: Resolver, path: string): ScriptValue
proc deepList[C](get: Resolver, ro: bool, path: string): ScriptValue
proc deepTable[T](get: Resolver, ro: bool, path: string): ScriptValue
proc fieldTable[T](): FieldTable
proc listOps[C](): ListOps

# ----------------------------------------------------------- reading ----
proc fieldValue*[F](p: ptr F, get: Resolver, ro: bool, path: string): ScriptValue =
  ## What a script sees for the value at `p` (resolved again later by `get`).
  when F is Game: wrapGame(p[])
  elif F is Player: wrapPlayer(p[])
  elif F is Enemy: wrapEnemy(p[])
  elif F is Bullet: wrapBullet(p[])
  elif F is Game3D: wrapWorld3D(p[])
  elif F is Entity3D: wrapEntity3D(p[])
  elif F is Projectile3D: wrapProjectile3D(p[])
  elif F is Pickup3D: wrapPickup3D(p[])
  elif F is ScriptValue: p[]   # (a script's own value, kept by the game)
  elif F is ScriptTable: (if p[].isNil: NilValue else: vtable(p[]))
  elif F is ScriptFunc: (if p[].isNil: NilValue else: vfunc(p[]))
  elif F is ScriptStr: (if p[].isNil: NilValue else: vstr(p[]))
  elif F is Userdata: (if p[].isNil: NilValue else: vud(p[]))
  elif isResource(F): resView[F](get, path)   # (the game's texture, font...: a view, never unloaded by a script)
  elif isOpaque(F): NilValue
  elif isScriptTable[F](): deepTable[F](get, ro, path)
  elif compiles(toScript(p[])): toScript(p[])
  elif F is ref:
    when typeof(p[][]) is object or typeof(p[][]) is tuple:
      if p[].isNil: NilValue
      else: deepObject[typeof(p[][])](derefResolver(get), ro, path)
    else:
      NilValue
  elif F is object or F is tuple: deepObject[F](get, ro, path)
  elif F is seq or F is array: deepList[F](get, ro, path)
  else: NilValue

template isVisible(F: typedesc): bool =
  ## Whether fieldValue shows anything for this type (for fields() / pairs).
  when isOpaque(F): false
  elif F is Game or F is Player or F is Enemy or F is Bullet: true
  elif F is Game3D or F is Entity3D or F is Projectile3D or F is Pickup3D: true
  elif F is ScriptValue or F is ScriptTable or F is ScriptFunc or F is ScriptStr or F is Userdata: true
  elif isResource(F): true
  elif compiles(toScript(default(F))): true
  elif F is ref: typeof(default(F)[]) is object or typeof(default(F)[]) is tuple
  elif F is object or F is tuple or F is seq or F is array: true
  else: false

template elemAt(c: untyped, i: int): untyped =
  when typeof(c) is array: c[typeof(low(c))(ord(low(c)) + i)]
  else: c[i]

template elemType(C: typedesc): untyped = typeof(items(default(C)))   # seqs and arrays alike

# ----------------------------------------------------------- writing ----
proc setFields(vm: VM, ft: FieldTable, raw: pointer, name: string, val: ScriptValue,
               ro: bool, path: string): bool =
  ## obj.name = val through the type's table; false if it has no such field.
  if name in HiddenFields:
    vm.runtimeError(path & "." & name & " is not available to scripts")
  let i = ft.byName.getOrDefault(name, -1)
  if i < 0: return false
  let e = ft.entries[i]
  if ro or (path & "." & name) in ReadOnlyPaths:
    vm.runtimeError(path & "." & name & " is read-only")
  e.set(vm, cast[pointer](cast[int](raw) + e.offset), val, path & "." & name, false)
  true

proc proxyFields(v: ScriptValue): FieldTable {.inline.} =
  ## The object type behind a proxy (nil if `v` is not an object proxy).
  if v.kind == vkUserdata and v.ud.box of DeepBox: DeepBox(v.ud.box).fields else: nil

proc tableKeyFrom[K](vm: VM, key: ScriptValue, ok: var bool): K
proc resName*[T](): string
proc takeOwnedRes[T](vm: VM, val: ScriptValue, path: string): T

proc refFromProxy[R: ref](vm: VM, val: ScriptValue, path: string): R =
  ## The object a proxy of R's type shows, as a counted ref of its own.
  let raw = DeepBox(val.ud.box).get()
  if raw.isNil: vm.runtimeError(path & ": that object no longer exists")
  var p = raw
  cast[ptr R](addr p)[]   # read through a ptr: a copy, so the count goes up

proc assignFields[F](vm: VM, p: ptr F, t: ScriptTable, path: string) =
  ## A table of fields into the object at `p`, field by field (never a copy
  ## of the whole object: some types forbid that).
  let ft = fieldTable[F]()
  for (k, v) in pairsCursor(t):
    if k.kind != vkString or not setFields(vm, ft, p, k.str.s, v, false, path):
      vm.runtimeError(path & " has no field " & keyStr(k))

proc assignValue*[F](vm: VM, p: ptr F, val: ScriptValue, path: string, fresh: bool) =
  ## Write a script value into the Nim value at `p`: entities take their
  ## wrappers, other objects a proxy of their type (a copy) or a table of
  ## fields, lists and tables a Lua table, plain values what assignScript
  ## takes. `fresh`: `p` is a value being built (list:add, a new table
  ## entry), so it may change length outside a safe point.
  template entity(unwrap: untyped, what: string) {.used.} =
    let x = unwrap(val)
    if x.isNil: vm.runtimeError(path & " expects " & what & ", got " & typeName(val))
    p[] = x
  when F is Game: entity(unwrapGame, "the game")
  elif F is Player: entity(unwrapPlayer, "a player")
  elif F is Enemy: entity(unwrapEnemy, "an enemy")
  elif F is Bullet: entity(unwrapBullet, "a bullet")
  elif F is Game3D: entity(unwrapWorld3D, "a 3D world")
  elif F is Entity3D: entity(unwrapEntity3D, "a 3D entity")
  elif F is Projectile3D: entity(unwrapProjectile3D, "a 3D projectile")
  elif F is Pickup3D: entity(unwrapPickup3D, "a 3D pickup")
  elif F is ScriptValue: p[] = val
  elif F is ScriptTable:
    if val.kind == vkTable: p[] = val.tbl
    elif val.kind == vkNil: p[] = nil
    else: vm.runtimeError(path & " expects a table, got " & typeName(val))
  elif F is ScriptFunc:
    if val.kind == vkFunction: p[] = val.fn
    elif val.kind == vkNil: p[] = nil
    else: vm.runtimeError(path & " expects a function, got " & typeName(val))
  elif F is ScriptStr:
    if val.kind == vkString: p[] = val.str
    elif val.kind == vkNil: p[] = nil
    else: vm.runtimeError(path & " expects a string, got " & typeName(val))
  elif F is Userdata:
    if val.kind == vkUserdata: p[] = val.ud
    elif val.kind == vkNil: p[] = nil
    else: vm.runtimeError(path & " expects a userdata, got " & typeName(val))
  elif isResource(F):
    # A resource a script made (rl.load...) moves into the field: the game
    # owns it from then on, and the script's handle is empty.
    p[] = takeOwnedRes[F](vm, val, path)
  elif isOpaque(F):
    vm.runtimeError(path & " cannot be set from a script")
  elif compiles(assignScript(vm, p[], val, path)):
    assignScript(vm, p[], val, path)
  elif F is ref:
    when typeof(p[][]) is object or typeof(p[][]) is tuple:
      if val.kind == vkNil:
        p[] = nil
      elif proxyFields(val) == fieldTable[typeof(p[][])]():
        p[] = refFromProxy[F](vm, val, path)
      elif val.kind == vkTable:
        var r: F
        new(r)
        assignFields(vm, addr r[], val.tbl, path)
        p[] = r
      else:
        vm.runtimeError(path & " expects an object of its kind (or a table of fields), got " & typeName(val))
    else:
      vm.runtimeError(path & " cannot be set from a script")
  elif isScriptTable[F]():
    if val.kind != vkTable: vm.runtimeError(path & " must be set from a table")
    if not fresh: requireStructural(vm, path)   # its whole contents change
    var t: F
    for (k, v) in pairsCursor(val.tbl):
      var ok = false
      let key = tableKeyFrom[tableKey(F)](vm, k, ok)
      if not ok: vm.runtimeError(path & ": " & keyStr(k) & " is not a key of this table")
      var x: tableVal(F)
      assignValue(vm, addr x, v, path & "[" & keyStr(k) & "]", true)
      t[key] = x
    p[] = t
  elif F is object or F is tuple:
    if val.kind == vkTable:
      assignFields(vm, p, val.tbl, path)   # into the object as it is
    elif proxyFields(val) == fieldTable[F]():
      let raw = DeepBox(val.ud.box).get()
      if raw.isNil: vm.runtimeError(path & ": that object no longer exists")
      when copyable[F]():
        p[] = cast[ptr F](raw)[]
      else:
        vm.runtimeError(path & " cannot be copied (it holds a GPU or audio resource)")
    else:
      vm.runtimeError(path & " must be set from a table of its fields, got " & typeName(val))
  elif F is seq or F is array:
    if val.kind == vkUserdata and val.ud.box of DeepBox and DeepBox(val.ud.box).list == listOps[F]():
      # Another list of its type (a proxy): a copy of it.
      let raw = DeepBox(val.ud.box).get()
      if raw.isNil: vm.runtimeError(path & ": that list no longer exists")
      when copyable[F]():
        if raw != cast[pointer](p):
          when F is seq:
            if cast[ptr F](raw)[].len != p[].len and not fresh: requireStructural(vm, path)
          p[] = cast[ptr F](raw)[]
        return
      else:
        vm.runtimeError(path & " cannot be copied (it holds a GPU or audio resource)")
    if val.kind != vkTable: vm.runtimeError(path & " must be set from a list")
    let n = val.tbl.len
    var kept = p[].len
    when F is seq:
      if n != p[].len:
        if not fresh: requireStructural(vm, path)
        kept = min(kept, n)
        p[].setLen(n)
    for i in 0 ..< min(n, p[].len):
      assignValue(vm, addr elemAt(p[], i), val.tbl.item(i + 1), path & "[" & $(i + 1) & "]",
                  fresh or i >= kept)
  else:
    vm.runtimeError(path & " cannot be set from a script")

template scriptToNim*(vm: VM, val: ScriptValue, dst: var typed, path: string) =
  ## A script value into a new Nim value (what list:add, new table entries
  ## and the mixin layer's arguments go through).
  assignValue(vm, addr dst, val, path, true)

# --------------------------------------------------------------- objects ----
proc getAt[F](p: pointer, get: Resolver, ro: bool, path: string): ScriptValue {.nimcall.} =
  fieldValue(cast[ptr F](p), get, ro, path)

proc setAt[F](vm: VM, p: pointer, val: ScriptValue, path: string, fresh: bool) {.nimcall.} =
  assignValue(vm, cast[ptr F](p), val, path, fresh)

proc fieldTable[T](): FieldTable =
  ## T's fields, worked out once from a zeroed stand-in (never constructed or
  ## destroyed): names, offsets, and the reader / writer of each field's type.
  var ft {.global.}: FieldTable
  if ft.isNil:
    ft = FieldTable()
    let probe = cast[ptr T](alloc0(sizeof(T)))
    for fname, f in fieldPairs(probe[]):
      when fname notin HiddenFields and compiles(addr f):
        ft.byName[fname] = ft.entries.len
        ft.entries.add(FieldEntry(name: fname, offset: cast[int](addr f) - cast[int](probe),
                                  get: getAt[typeof(f)], set: setAt[typeof(f)]))
        when isVisible(typeof(f)):
          ft.visible.add(fname)
    dealloc(probe)
  ft

proc indexFields(ft: FieldTable, raw: pointer, get: Resolver, name: string, ro: bool,
                 path: string, found: var bool): ScriptValue =
  found = false
  if name in HiddenFields:
    found = true   # exists, but reads as nil
    return NilValue
  let i = ft.byName.getOrDefault(name, -1)
  if i < 0: return NilValue
  found = true
  let e = ft.entries[i]
  e.get(cast[pointer](cast[int](raw) + e.offset), offsetResolver(get, e.offset), ro, path & "." & name)

proc namesValue(names: seq[string]): ScriptValue =
  let t = newScriptTable(names.len)
  for n in names: t.add(vstr(n))
  vtable(t)

proc snapshot(vm: VM, v: ScriptValue, depth: int): ScriptValue =
  ## A proxy's data as plain tables, walked through its own class: nested
  ## objects, lists and tables are copied too; entities (enemies, the
  ## player...) stay themselves.
  if v.kind != vkUserdata or not (v.ud.box of DeepBox) or v.ud.cls.next.isNil: return v
  if depth > 32: return NilValue   # (refs can point back up)
  let t = newScriptTable()
  var key = NilValue
  var k, x: ScriptValue
  while v.ud.cls.next(vm, v.ud, key, k, x):
    rawSet(t, k, snapshot(vm, x, depth + 1))
    key = k
  vtable(t)

proc copyNative(target: ScriptValue): ScriptValue =
  ## x:copy() -> a plain table of its data (it survives the object).
  vnative(newNative("copy", proc (vm: VM, a: openArray[ScriptValue], r: var RetVals) =
    if DeepBox(target.ud.box).get().isNil:
      vm.runtimeError(DeepBox(target.ud.box).path & " no longer exists")
    r.setRet(snapshot(vm, target, 0))))

var objectCls: UdClass

proc objectClass(): UdClass =
  ## The one class of every object proxy (its box says which type).
  if objectCls.isNil:
    objectCls = UdClass(name: "object")
    objectCls.index = proc (vm: VM, ud: Userdata, key: ScriptValue): ScriptValue =
      let box = DeepBox(ud.box)
      let raw = box.get()
      if raw.isNil: vm.runtimeError(box.path & " no longer exists")
      if key.kind != vkString: return NilValue
      var found = false
      result = indexFields(box.fields, raw, box.get, key.str.s, box.readOnly, box.path, found)
      if not found:
        if key.str.s == "fields": return constNative("fields", namesValue(box.fields.visible))
        if key.str.s == "copy": return copyNative(vud(ud))
        vm.runtimeError(box.path & " has no field '" & key.str.s & "'")
    objectCls.newindex = proc (vm: VM, ud: Userdata, key, val: ScriptValue) =
      let box = DeepBox(ud.box)
      let raw = box.get()
      if raw.isNil: vm.runtimeError(box.path & " no longer exists")
      if key.kind != vkString or
         not setFields(vm, box.fields, raw, key.str.s, val, box.readOnly, box.path):
        vm.runtimeError(box.path & " has no field '" & keyStr(key) & "'")
    objectCls.next = proc (vm: VM, ud: Userdata, key: ScriptValue, k, v: var ScriptValue): bool =
      let box = DeepBox(ud.box)
      let raw = box.get()
      if raw.isNil: return false
      let names = box.fields.visible
      var at = 0
      if key.kind == vkString:
        at = names.find(key.str.s) + 1
        if at == 0: return false
      if at >= names.len: return false
      var found = false
      k = vstr(names[at])
      v = indexFields(box.fields, raw, box.get, names[at], box.readOnly, box.path, found)
      true
    objectCls.tostr = proc (ud: Userdata): string = DeepBox(ud.box).path
  objectCls

proc deepObject[T](get: Resolver, ro: bool, path: string): ScriptValue =
  let raw = get()
  if raw.isNil: return NilValue
  vud(Userdata(cls: objectClass(), key: raw,
               box: DeepBox(get: get, readOnly: ro, path: path, fields: fieldTable[T]())))

# ----------------------------------------------------------------- lists ----
proc elemAddr[C](c: pointer, i: int): pointer {.nimcall.} =
  let s = cast[ptr C](c)
  if i < 0 or i >= s[].len: nil else: cast[pointer](addr elemAt(s[], i))

proc listLen[C](c: pointer): int {.nimcall.} = cast[ptr C](c)[].len

proc enumPos[C](name: string): int {.nimcall.} =
  ## An array indexed by an enum: the position of a name (a subrange too).
  ## (From the type alone: a default array could hold resources to destroy.)
  for e in low(C) .. high(C):
    if $e == name: return ord(e) - ord(low(C))
  -1

proc seqPut[C](vm: VM, c: pointer, pos: int, val: ScriptValue, path: string) {.nimcall.} =
  var x: elemType(C)
  assignValue(vm, addr x, val, path, true)
  let s = cast[ptr C](c)
  if pos < 0: s[].add(x) else: s[].insert(x, pos)

proc seqRemove[C](c: pointer, pos: int) {.nimcall.} = cast[ptr C](c)[].delete(pos)

proc seqResize[C](vm: VM, c: pointer, n: int) {.nimcall.} =
  let s = cast[ptr C](c)
  when elemType(C) is ref:
    if n > s[].len: vm.argError("resize", 1, "a list of objects grows with :add")
  s[].setLen(n)

proc entityStep[C](c: pointer, i: var int): ScriptValue {.nimcall.} =
  ## The next live entity of an entity list (calling it iterates).
  let s = cast[ptr C](c)
  while i < s[].len:
    let x = s[][i]
    inc i
    when C is seq[Enemy]:
      if x.hp > 0: return wrapEnemy(x)
    elif C is seq[Bullet]:
      return wrapBullet(x)
    elif C is seq[Entity3D]:
      if x.alive: return wrapEntity3D(x)
    elif C is seq[Projectile3D]:
      if x.active: return wrapProjectile3D(x)
    else:
      if x.alive: return wrapPickup3D(x)
  NilValue

proc listOps[C](): ListOps =
  var ops {.global.}: ListOps
  if ops.isNil:
    ops = ListOps(len: listLen[C], at: elemAddr[C], get: getAt[elemType(C)],
                  set: setAt[elemType(C)])
    when C is array:
      when typeof(low(C)) is enum: ops.byName = enumPos[C]
    else:
      ops.put = seqPut[C]
      ops.remove = seqRemove[C]
      ops.resize = seqResize[C]
    when C is seq[Enemy] or C is seq[Bullet] or C is seq[Entity3D] or C is seq[Projectile3D] or
         C is seq[Pickup3D]:
      # `for e in game:enemies() do`: calling a list of enemies (or bullets, or
      # a 3D world's entities / projectiles / pickups) iterates the live ones.
      ops.step = entityStep[C]
  ops

proc listPos(ops: ListOps, c: pointer, key: ScriptValue): int =
  ## 0-based position for a script key (1-based number, or an enum name for
  ## arrays indexed by an enum); -1 if there is no such element.
  if key.kind == vkNumber:
    let n = key.n
    if n != floor(n): return -1
    let i = int(n) - 1
    return if i >= 0 and i < ops.len(c): i else: -1
  if key.kind == vkString and not ops.byName.isNil:
    return ops.byName(key.str.s)
  -1

proc listMethod(ud: Userdata, name: string): ScriptValue =
  ## list:add(v), list:insert([pos,] v), list:remove([pos]), list:clear(),
  ## list:resize(n) (seqs only; they change its length, so only at a safe
  ## point) and list:copy() (a plain table of its items).
  let box = DeepBox(ud.box)
  let ops = box.list
  let get = box.get
  let path = box.path
  let ro = box.readOnly
  if name == "copy": return copyNative(vud(ud))
  if ops.put.isNil: return NilValue   # an array: fixed length
  proc target(vm: VM, what: string): pointer =
    if ro: vm.runtimeError(path & " is read-only")
    vm.requireStructural(path & ":" & what)
    result = get()
    if result.isNil: vm.runtimeError(path & " no longer exists")
  case name
  of "add":
    vnative(newNative("add", proc (vm: VM, a: openArray[ScriptValue], r: var RetVals) =
      ops.put(vm, target(vm, "add"), -1, arg(a, 1), path & "[+]")))
  of "insert":
    vnative(newNative("insert", proc (vm: VM, a: openArray[ScriptValue], r: var RetVals) =
      let c = target(vm, "insert")
      if a.len >= 3:
        let pos = vm.checkInt(a, 1, "insert") - 1
        if pos < 0 or pos > ops.len(c): vm.argError("insert", 1, "position out of bounds")
        ops.put(vm, c, pos, arg(a, 2), path & "[+]")
      else:
        ops.put(vm, c, -1, arg(a, 1), path & "[+]")))
  of "remove":
    vnative(newNative("remove", proc (vm: VM, a: openArray[ScriptValue], r: var RetVals) =
      let c = target(vm, "remove")
      let n = ops.len(c)
      if n == 0: return
      let pos = vm.optInt(a, 1, "remove", n) - 1
      if pos < 0 or pos >= n: vm.argError("remove", 1, "position out of bounds")
      ops.remove(c, pos)))
  of "clear":
    vnative(newNative("clear", proc (vm: VM, a: openArray[ScriptValue], r: var RetVals) =
      ops.resize(vm, target(vm, "clear"), 0)))
  of "resize":
    vnative(newNative("resize", proc (vm: VM, a: openArray[ScriptValue], r: var RetVals) =
      let c = target(vm, "resize")
      let n = vm.checkInt(a, 1, "resize")
      if n < 0: vm.argError("resize", 1, "a length cannot be negative")
      ops.resize(vm, c, n)))
  else: NilValue

proc elemValue(box: DeepBox, c: pointer, i: int): ScriptValue =
  box.list.get(box.list.at(c, i), elemResolver(box.get, i, box.list.at), box.readOnly,
               box.path & "[" & $(i + 1) & "]")

var listCls: UdClass

proc listClass(): UdClass =
  ## The one class of every list proxy (its box says which type).
  if listCls.isNil:
    listCls = UdClass(name: "list")
    listCls.len = proc (vm: VM, ud: Userdata): int =
      let box = DeepBox(ud.box)
      let raw = box.get()
      if raw.isNil: 0 else: box.list.len(raw)
    listCls.index = proc (vm: VM, ud: Userdata, key: ScriptValue): ScriptValue =
      let box = DeepBox(ud.box)
      let raw = box.get()
      if raw.isNil: vm.runtimeError(box.path & " no longer exists")
      if key.kind == vkString:
        let m = listMethod(ud, key.str.s)
        if m.kind != vkNil: return m
      let i = listPos(box.list, raw, key)
      if i < 0: return NilValue
      elemValue(box, raw, i)
    listCls.newindex = proc (vm: VM, ud: Userdata, key, val: ScriptValue) =
      let box = DeepBox(ud.box)
      if box.readOnly: vm.runtimeError(box.path & " is read-only")
      let raw = box.get()
      if raw.isNil: vm.runtimeError(box.path & " no longer exists")
      let i = listPos(box.list, raw, key)
      if i < 0:
        vm.runtimeError(box.path & ": no element " & keyStr(key) &
                        " (lists grow with :add / :insert, at a safe point)")
      box.list.set(vm, box.list.at(raw, i), val, box.path & "[" & $(i + 1) & "]", false)
    listCls.next = proc (vm: VM, ud: Userdata, key: ScriptValue, k, v: var ScriptValue): bool =
      let box = DeepBox(ud.box)
      let raw = box.get()
      if raw.isNil: return false
      let i = if key.kind == vkNumber: int(key.n) else: 0
      if i < 0 or i >= box.list.len(raw): return false
      k = vnum(i + 1)
      v = elemValue(box, raw, i)
      true
    listCls.tostr = proc (ud: Userdata): string =
      let box = DeepBox(ud.box)
      let raw = box.get()
      box.path & " (" & $(if raw.isNil: 0 else: box.list.len(raw)) & " items)"
    listCls.call = proc (vm: VM, ud: Userdata, args: openArray[ScriptValue], ret: var RetVals) =
      let box = DeepBox(ud.box)
      if box.list.step.isNil: vm.runtimeError("attempt to call a list value")
      let get = box.get
      let step = box.list.step
      var i = 0
      ret.setRet(vnative(newNative("list_iterator", proc (vm: VM, a: openArray[ScriptValue], r: var RetVals) =
        let raw = get()
        r.setRet(if raw.isNil: NilValue else: step(raw, i)))))
  listCls

proc deepList[C](get: Resolver, ro: bool, path: string): ScriptValue =
  let raw = get()
  if raw.isNil: return NilValue
  vud(Userdata(cls: listClass(), key: raw,
               box: DeepBox(get: get, readOnly: ro, path: path, list: listOps[C]())))

# ---------------------------------------------------------------- tables ----
proc tableKeyFrom[K](vm: VM, key: ScriptValue, ok: var bool): K =
  ## A script key as the table's key type (strings, enum names, integers).
  ok = true
  when K is string:
    if key.kind == vkString: return key.str.s
  elif K is enum:
    if key.kind == vkString:
      for e in K:
        if $e == key.str.s: return e
  elif K is SomeInteger:
    if key.kind == vkNumber and key.n == floor(key.n) and abs(key.n) < 9.0e15:
      return K(int64(key.n))
  ok = false

proc tableEntryResolver[T, K](parent: Resolver, k: K): Resolver =
  result = proc (): pointer =
    let a = parent()
    if a.isNil: return nil
    let t = cast[ptr T](a)
    if t[].hasKey(k): cast[pointer](addr t[][k]) else: nil

proc tableClass[T](): UdClass =
  var cls {.global.}: UdClass
  if cls.isNil:
    cls = UdClass(name: "table")
    cls.len = proc (vm: VM, ud: Userdata): int =
      let raw = DeepBox(ud.box).get()
      if raw.isNil: 0 else: cast[ptr T](raw)[].len
    cls.index = proc (vm: VM, ud: Userdata, key: ScriptValue): ScriptValue =
      let box = DeepBox(ud.box)
      let raw = box.get()
      if raw.isNil: vm.runtimeError(box.path & " no longer exists")
      let t = cast[ptr T](raw)
      var ok = false
      let k = tableKeyFrom[tableKey(T)](vm, key, ok)
      if not ok or not t[].hasKey(k): return NilValue
      fieldValue(addr t[][k], tableEntryResolver[T, tableKey(T)](box.get, k), box.readOnly,
                 box.path & "[" & keyStr(key) & "]")
    cls.newindex = proc (vm: VM, ud: Userdata, key, val: ScriptValue) =
      ## t[k] = v changes an entry; a new key adds one and nil removes one
      ## (both change the table's size, so only at a safe point).
      let box = DeepBox(ud.box)
      if box.readOnly: vm.runtimeError(box.path & " is read-only")
      let raw = box.get()
      if raw.isNil: vm.runtimeError(box.path & " no longer exists")
      let t = cast[ptr T](raw)
      var ok = false
      let k = tableKeyFrom[tableKey(T)](vm, key, ok)
      if not ok: vm.runtimeError(box.path & ": " & keyStr(key) & " is not a key of this table")
      let where = box.path & "[" & keyStr(key) & "]"
      if val.kind == vkNil:
        if t[].hasKey(k):
          vm.requireStructural(where & " = nil")
          t[].del(k)
      elif t[].hasKey(k):
        assignValue(vm, addr t[][k], val, where, false)
      else:
        vm.requireStructural(where)
        var v: tableVal(T)
        assignValue(vm, addr v, val, where, true)
        t[][k] = v
    cls.next = proc (vm: VM, ud: Userdata, key: ScriptValue, k, v: var ScriptValue): bool =
      let box = DeepBox(ud.box)
      let raw = box.get()
      if raw.isNil: return false
      let t = cast[ptr T](raw)
      var passed = key.kind == vkNil
      for tk in t[].keys:
        let sk = toScript(tk)
        if passed:
          k = sk
          v = fieldValue(addr t[][tk], tableEntryResolver[T, tableKey(T)](box.get, tk), box.readOnly,
                         box.path & "[" & keyStr(sk) & "]")
          return true
        if rawEquals(sk, key): passed = true
      false
    cls.tostr = proc (ud: Userdata): string =
      let box = DeepBox(ud.box)
      let raw = box.get()
      box.path & " (" & $(if raw.isNil: 0 else: cast[ptr T](raw)[].len) & " entries)"
  cls

proc deepTable[T](get: Resolver, ro: bool, path: string): ScriptValue =
  let raw = get()
  if raw.isNil: return NilValue
  vud(Userdata(cls: tableClass[T](), box: DeepBox(get: get, readOnly: ro, path: path), key: raw))

# --------------------------------------------------------------- globals ----
# engine.globals.<name>: the game's global state (module variables, and
# main()'s long-lived locals), shown like game.*: settings, statistics, the
# profile's progression, the desktop... Registered by address, so a global
# that is reassigned (a profile switch, a new run) is seen as it is now.
type ModGlobal = object
  name: string
  typeName: string            ## (for the generated API reference)
  get: proc (): ScriptValue {.closure.}
  set: proc (vm: VM, val: ScriptValue) {.closure.}

var modGlobals: seq[ModGlobal]

proc registerModGlobal*[T](name: string, p: ptr T) =
  let resolve: Resolver = proc (): pointer = p
  for i in 0 ..< modGlobals.len:
    if modGlobals[i].name == name:
      modGlobals.delete(i)
      break
  modGlobals.add(ModGlobal(name: name, typeName: $T,
    get: proc (): ScriptValue = fieldValue(p, resolve, false, name),
    set: proc (vm: VM, val: ScriptValue) = assignValue(vm, p, val, name, false)))

proc modGlobalNames*(): seq[string] =
  for g in modGlobals: result.add(g.name)

proc modGlobalTypes*(): seq[tuple[name, typeName: string]] =
  for g in modGlobals: result.add((g.name, g.typeName))

proc modGlobalGet*(name: string, found: var bool): ScriptValue =
  found = false
  for g in modGlobals:
    if g.name == name:
      found = true
      return g.get()
  NilValue

proc modGlobalSet*(vm: VM, name: string, val: ScriptValue): bool =
  for g in modGlobals:
    if g.name == name:
      g.set(vm, val)
      return true
  false

# ---------------------------------------------------- raylib resources ----
# A script holds a texture, font, sound... as a handle. One it made
# (rl.loadTexture...) is *owned*: it is unloaded once nothing holds it, after
# the frame being drawn (raylib batches draws, and the batch may still use it).
# One that is someone else's (the game's, a mod asset, raylib's default font)
# is a *view*: it never unloads anything.

proc resName*[T](): string =
  when T is Texture: "Texture"
  elif T is RenderTexture: "RenderTexture"
  elif T is Font: "Font"
  elif T is Shader: "Shader"
  elif T is Sound: "Sound"
  elif T is Music: "Music"
  elif T is Wave: "Wave"
  elif T is AudioStream: "AudioStream"
  elif T is Mesh: "Mesh"
  elif T is Model: "Model"
  elif T is Material: "Material"
  elif T is ModelAnimation: "ModelAnimation"
  else: "Image"

type
  ResBaseObj = object of RootObj
    gone: bool                                 ## unloaded, or moved into the game
    release: proc (b: ResBase) {.nimcall.}     ## rl.unload: unload it now
  ResBase = ref ResBaseObj
  ResBoxObj[T] = object of ResBaseObj
    v: T
  ResBox[T] = ref ResBoxObj[T]

var pendingUnloads: seq[proc () {.closure.}]

proc deferUnload[T](x: sink T) =
  var keep = x
  pendingUnloads.add(proc () =
    `=destroy`(keep)
    wasMoved(keep))

proc `=destroy`[T](b: var ResBoxObj[T]) =
  if not b.gone: deferUnload(move(b.v))

proc releaseScriptResources*() =
  ## Unload what scripts let go of: after each frame is drawn (main.nim), and
  ## at shutdown before the window closes.
  if pendingUnloads.len == 0: return
  let batch = move pendingUnloads
  pendingUnloads = @[]
  for f in batch: f()

proc releaseBox[T](b: ResBase) {.nimcall.} =
  let rb = ResBox[T](b)
  if not rb.gone:
    rb.gone = true
    deferUnload(move(rb.v))

proc resClass*[T](): UdClass =
  ## The class of every handle to a T (owned or a view).
  var cls {.global.}: UdClass
  if cls.isNil:
    cls = UdClass(name: resName[T]())
    cls.index = proc (vm: VM, ud: Userdata, key: ScriptValue): ScriptValue =
      let box = DeepBox(ud.box)
      let raw = box.get()
      if raw.isNil: vm.runtimeError(box.path & " no longer exists (unloaded)")
      if key.kind != vkString: return NilValue
      var found = false
      result = indexFields(box.fields, raw, box.get, key.str.s, true, box.path, found)
      if not found:
        if key.str.s == "owned": return vbool(not box.owner.isNil)
        vm.runtimeError(resName[T]() & " has no field '" & key.str.s & "'")
    cls.newindex = proc (vm: VM, ud: Userdata, key, val: ScriptValue) =
      vm.runtimeError(resName[T]() & " handles are read-only (raylib's own procs change them)")
    cls.next = proc (vm: VM, ud: Userdata, key: ScriptValue, k, v: var ScriptValue): bool =
      let box = DeepBox(ud.box)
      let raw = box.get()
      if raw.isNil: return false
      let names = box.fields.visible
      var at = 0
      if key.kind == vkString:
        at = names.find(key.str.s) + 1
        if at == 0: return false
      if at >= names.len: return false
      var found = false
      k = vstr(names[at])
      v = indexFields(box.fields, raw, box.get, names[at], true, box.path, found)
      true
    cls.tostr = proc (ud: Userdata): string =
      let box = DeepBox(ud.box)
      resName[T]() & (if box.owner.isNil: " (view)" else: "") &
        (if box.get().isNil: " (unloaded)" else: "")
  cls

proc resOwned*[T](x: sink T, path: string): ScriptValue =
  ## A handle that owns `x` (a resource a script made).
  let rb = ResBox[T](v: x, release: releaseBox[T])
  let get: Resolver = proc (): pointer =
    if rb.gone: nil else: cast[pointer](addr rb.v)
  vud(Userdata(cls: resClass[T](), key: cast[pointer](rb),
               box: DeepBox(get: get, path: path, fields: fieldTable[T](), owner: rb, readOnly: true)))

proc resView*[T](get: Resolver, path: string): ScriptValue =
  ## A handle to a T someone else owns (resolved again on each use).
  let raw = get()
  if raw.isNil: return NilValue
  vud(Userdata(cls: resClass[T](), key: raw,
               box: DeepBox(get: get, path: path, fields: fieldTable[T](), readOnly: true)))

proc resPointer*[T](v: ScriptValue): ptr T =
  ## The T a handle shows (nil: not a handle to a T, or unloaded).
  if v.kind != vkUserdata or v.ud.cls != resClass[T](): return nil
  cast[ptr T](DeepBox(v.ud.box).get())

proc takeOwnedRes[T](vm: VM, val: ScriptValue, path: string): T =
  ## Move the resource out of a script's own handle (it is empty after).
  if val.kind == vkUserdata and val.ud.cls == resClass[T]() and
     not DeepBox(val.ud.box).owner.isNil:
    let rb = ResBox[T](DeepBox(val.ud.box).owner)
    if rb.gone: vm.runtimeError(path & ": that " & resName[T]() & " was unloaded")
    rb.gone = true
    return move(rb.v)
  vm.runtimeError(path & " takes a " & resName[T]() & " a script made (rl.load...), " &
                  "not one that belongs to the game")

proc unloadHandle*(v: ScriptValue): bool =
  ## rl.unload(handle): an owned resource goes now (after this frame); false
  ## for a view or anything else.
  if v.kind != vkUserdata or not (v.ud.box of DeepBox): return false
  let owner = DeepBox(v.ud.box).owner
  if owner.isNil or not (owner of ResBase): return false
  let b = ResBase(owner)
  if b.gone: return false
  b.release(b)
  true

proc resultView*[R](r: sink R, path: string): ScriptValue =
  ## A resource a raylib getter hands out but keeps (its default font, its
  ## shapes texture): a view of a copy of its handle, never unloaded.
  var keep {.global.}: ptr R
  if keep.isNil: keep = cast[ptr R](alloc0(sizeof(R)))
  copyMem(keep, addr r, sizeof(R))
  wasMoved(r)
  let p = keep
  resView[R](proc (): pointer = p, path)

# ----------------------------------------------- for the mixin layer ----
# Values handed to scripts by mixins (a wrapped proc's arguments and results)
# and taken back from them.

type ValueBox[T] = ref object of RootObj
  v: T

proc keepResolver(keep: RootRef, p: pointer): Resolver =
  ## `p` (inside `keep`, which this keeps alive).
  result = proc (): pointer =
    if keep.isNil: nil else: p

proc gatedResolver(alive: proc (): bool {.closure.}, p: pointer): Resolver =
  ## `p` while `alive()` says so (a call's argument, borrowed for the call).
  result = proc (): pointer =
    if alive(): p else: nil

proc rootResolver[T: ref object](obj: T, alive: proc (): bool {.closure.}): Resolver

proc resourceType*[T](): bool {.compileTime.} = isResource(T)
  ## (For generated code: a template's typedesc parameter cannot take a typed type node.)

proc scriptable*[T](): bool {.compileTime.} =
  ## Whether scripts can hold a T at all (not a raw pointer, a proc or an OS
  ## handle; raylib's resources as handles; raylib's arrays as lists, when
  ## their items can be copied out).
  when T is RArray: copyable[typeof(default(T)[0])]()
  else: not isOpaque(T) or isResource(T)

proc nimToScript*[T](v: sink T, path: string): ScriptValue =
  ## A Nim value given to a script that may keep it: plain values as
  ## themselves, entities as their wrappers, other refs as proxies that keep
  ## the object alive, value objects / lists / tables as proxies of a copy.
  when T is ScriptValue: v
  elif T is ScriptTable or T is ScriptFunc or T is ScriptStr or T is Userdata:
    var x = v
    fieldValue(addr x, nil, false, path)
  elif isResource(T): resOwned(v, path)   # (made for the script: it owns it)
  elif T is RArray:   # raylib's arrays as lists (of copies)
    when copyable[typeof(v[0])](): nimToScript(@v, path) else: NilValue
  elif isOpaque(T): NilValue
  elif T is Game or T is Player or T is Enemy or T is Bullet or T is Game3D or
       T is Entity3D or T is Projectile3D or T is Pickup3D:
    var x = v
    fieldValue(addr x, nil, false, path)
  elif compiles(toScript(v)): toScript(v)
  elif T is ref:
    when typeof(v[]) is object or typeof(v[]) is tuple:
      if v.isNil: NilValue
      else: deepObject[typeof(v[])](rootResolver(v, nil), false, path)
    else:
      NilValue
  else:
    when copyable[T]():
      let b = ValueBox[T](v: v)
      fieldValue(addr b.v, keepResolver(b, addr b.v), false, path)
    else:
      NilValue

proc proxyAt*[T](p: ptr T, alive: proc (): bool {.closure.}, path: string): ScriptValue =
  ## The value at `p` as a live proxy for as long as `alive()` (a mixin's
  ## borrowed argument: writes reach the variable itself).
  when isResource(T):
    resView[T](gatedResolver(alive, p), path)
  elif T is ScriptValue or isOpaque(T) or compiles(toScript(p[])) or T is ref:
    nimToScript(p[], path)   # (refs, ScriptTable / ScriptFunc... included)
  else:
    fieldValue(p, gatedResolver(alive, p), false, path)

proc proxyPointer*(v: ScriptValue): pointer =
  ## Where a proxy points right now (nil: not a proxy, or gone).
  if v.kind == vkUserdata and v.ud.box of DeepBox: DeepBox(v.ud.box).get() else: nil

proc proxyOf*[T](v: ScriptValue): ptr T =
  ## The T a proxy of T's own type shows (nil otherwise): passing game data
  ## by reference to a var parameter.
  if v.kind != vkUserdata or not (v.ud.box of DeepBox): return nil
  let box = DeepBox(v.ud.box)
  when T is object or T is tuple:
    if box.fields != fieldTable[T](): return nil
  elif T is seq or T is array:
    if box.list != listOps[T](): return nil
  else:
    return nil
  cast[ptr T](box.get())

# ------------------------------------------------------------ top level ----
# The game / player / enemy / bullet classes (mod_api) fall back to these for
# every field their own rules do not cover.

proc rootResolver[T: ref object](obj: T, alive: proc (): bool {.closure.}): Resolver =
  ## `alive` (optional) says whether the root is still the thing it was: a proxy
  ## reached from it then reads "no longer exists" once it is not (a 3D world
  ## that ended), rather than showing a stale object. The root itself is kept
  ## alive for as long as a proxy reached from it exists.
  let keep = obj
  result = proc (): pointer =
    if not alive.isNil and not alive(): nil else: cast[pointer](keep)

proc deepGet*[T: ref object](obj: T, name, path: string, found: var bool,
                             alive: proc (): bool {.closure.} = nil): ScriptValue =
  indexFields(fieldTable[typeof(obj[])](), cast[pointer](obj), rootResolver(obj, alive),
              name, false, path, found)

proc deepSet*[T: ref object](vm: VM, obj: T, name: string, val: ScriptValue, path: string): bool =
  setFields(vm, fieldTable[typeof(obj[])](), cast[pointer](obj), name, val, false, path)

proc deepNames*[T: ref object](obj: T): seq[string] =
  fieldTable[typeof(obj[])]().visible
