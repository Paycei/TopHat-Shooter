## Field reflection for mod scripts: `enemy.hp`, `player.damage = 2`,
## `game.currentWave`...
##
## Built on `fieldPairs` (a system iterator, no macros): the loop unrolls at
## compile time into one name comparison per field, and `when compiles` keeps
## only fields of a type scripts can hold (numbers, booleans, strings, enums
## as their names, Vector2 as {x, y} tables and Color as {r, g, b, a}).
## Everything else (seqs, refs, nested objects) is simply not visible. A new
## field on Player/Enemy/Bullet/Game is therefore scriptable automatically.
##
## Vector and colour fields come back as COPIES: `e.pos.x = 5` edits a table,
## not the enemy. Assign the whole field (`e.pos = {x = 5, y = 0}`) or use the
## x/y shortcuts mod_api adds.

import std/[strutils, tables]
import raylib
import ../particle_types
import lua_bridge

# ---------------------------------------------------------------- to script ----
proc vec2Value(x, y: float64): ScriptValue =
  let t = newScriptTable()
  rawSet(t, vstr("x"), vnum(x))
  rawSet(t, vstr("y"), vnum(y))
  vtable(t)

proc colorValue*(c: Color): ScriptValue =
  let t = newScriptTable()
  rawSet(t, vstr("r"), vnum(c.r.int))
  rawSet(t, vstr("g"), vnum(c.g.int))
  rawSet(t, vstr("b"), vnum(c.b.int))
  rawSet(t, vstr("a"), vnum(c.a.int))
  vtable(t)

proc toScript*(v: SomeFloat): ScriptValue {.inline.} = vnum(v.float64)
proc toScript*(v: SomeInteger): ScriptValue {.inline.} =
  ScriptValue(kind: vkNumber, n: v.float64, isInt: true)   # a Lua integer
proc toScript*(v: bool): ScriptValue {.inline.} = vbool(v)
proc toScript*(v: string): ScriptValue {.inline.} = vstr(v)
proc toScript*[E: enum](v: E): ScriptValue {.inline.} = vstr($v)
proc toScript*(v: Vector2): ScriptValue = vec2Value(v.x, v.y)
proc toScript*(v: Color): ScriptValue = colorValue(v)
proc toScript*[E: enum](s: set[E]): ScriptValue =
  ## A set of enum values reads as a list of their names.
  let t = newScriptTable()
  for e in s: t.add(vstr($e))
  vtable(t)

# ---------------------------------------------------------- from script ----
proc numOf(vm: VM, v: ScriptValue, field: string): float64 =
  if v.kind == vkNumber:
    if v.n != v.n: vm.runtimeError("field '" & field & "' cannot be set to NaN")
    return v.n
  if v.kind == vkString:
    var ok = false
    let n = strToNum(v.str.s, ok)
    if ok: return n
  vm.runtimeError("field '" & field & "' expects a number, got " & typeName(v))

proc byteOf(n: float64): uint8 {.inline.} = uint8(clamp(n, 0.0, 255.0))

proc parseColor*(vm: VM, v: ScriptValue, what: string): Color =
  ## A colour argument: {r=, g=, b=, a=}, {r, g, b[, a]} or "#rrggbb[aa]".
  case v.kind
  of vkTable:
    let t = v.tbl
    var r = rawGetStr(t, "r")
    var g = rawGetStr(t, "g")
    var b = rawGetStr(t, "b")
    var a = rawGetStr(t, "a")
    if r.kind == vkNil and t.len >= 3:
      r = t.item(1)
      g = t.item(2)
      b = t.item(3)
      a = if t.len >= 4: t.item(4) else: NilValue
    if r.kind != vkNumber or g.kind != vkNumber or b.kind != vkNumber:
      vm.runtimeError(what & ": colour needs numeric r, g and b (0-255)")
    Color(r: byteOf(r.n), g: byteOf(g.n), b: byteOf(b.n),
          a: if a.kind == vkNumber: byteOf(a.n) else: 255'u8)
  of vkString:
    var s = v.str.s
    if s.startsWith("#"): s = s[1 .. ^1]
    if s.len notin {6, 8}:
      vm.runtimeError(what & ": colour string must look like \"#rrggbb\" or \"#rrggbbaa\"")
    try:
      let n = parseHexInt(s)
      if s.len == 6:
        Color(r: uint8((n shr 16) and 255), g: uint8((n shr 8) and 255), b: uint8(n and 255), a: 255)
      else:
        Color(r: uint8((n shr 24) and 255), g: uint8((n shr 16) and 255),
              b: uint8((n shr 8) and 255), a: uint8(n and 255))
    except ValueError:
      vm.runtimeError(what & ": colour string is not valid hex")
  else:
    vm.runtimeError(what & ": colour expected (table or \"#rrggbb\"), got " & typeName(v))

# A script's number becomes a float32 position, speed or size, and some of
# them are cast to int further on. NaN and huge values are refused here, at
# the edge, so nothing downstream ever sees one: every native that reads a
# number out of a script table goes through these.

proc finite*(vm: VM, v: ScriptValue, what: string): float32 =
  ## A finite number (NaN and huge values are rejected).
  if v.kind == vkNumber and abs(v.n) < 1.0e9: return v.n.float32
  vm.runtimeError(what & " must be a finite number" &
                  (if v.kind == vkNumber: "" else: ", got " & typeName(v)))

proc numField*(vm: VM, t: ScriptTable, key, what: string, def: float32): float32 =
  ## t[key] as a finite number, or `def` when it is absent (errors say what.key).
  let v = rawGetStr(t, key)
  if v.kind == vkNil: def else: vm.finite(v, what & "." & key)

proc colorField*(vm: VM, t: ScriptTable, key, what: string, def: Color): Color =
  ## t[key] as a colour (see parseColor), or `def` when it is absent.
  let v = rawGetStr(t, key)
  if v.kind == vkNil: def else: parseColor(vm, v, what & "." & key)

proc parseVec*(vm: VM, v: ScriptValue, what: string): tuple[x, y: float64] =
  if v.kind == vkTable:
    var x = rawGetStr(v.tbl, "x")
    var y = rawGetStr(v.tbl, "y")
    if x.kind == vkNil and v.tbl.len >= 2:
      x = v.tbl.item(1)
      y = v.tbl.item(2)
    if x.kind == vkNumber and y.kind == vkNumber:
      return (x.n, y.n)
  vm.runtimeError(what & ": vector expected ({x = .., y = ..})")

proc assignScript*(vm: VM, dest: var SomeFloat, v: ScriptValue, field: string) =
  dest = typeof(dest)(numOf(vm, v, field))

proc assignScript*(vm: VM, dest: var SomeInteger, v: ScriptValue, field: string) =
  let n = numOf(vm, v, field)
  if abs(n) > 2.0e9:
    vm.runtimeError("field '" & field & "' value out of range")
  dest = typeof(dest)(int64(n))

proc assignScript*(vm: VM, dest: var bool, v: ScriptValue, field: string) =
  dest = truthy(v)

proc assignScript*(vm: VM, dest: var string, v: ScriptValue, field: string) =
  if v.kind notin {vkString, vkNumber}:
    vm.runtimeError("field '" & field & "' expects a string, got " & typeName(v))
  dest = if v.kind == vkString: v.str.s else: numToStr(v.n)

proc findName(names: var Table[string, int], s: string, o: var int): bool =
  names.withValue(nimIdentNormalize(s), v):
    o = v[]
    return true
  false

proc enumByName[E: enum](s: string): E =
  ## parseEnum[E](s) (style-insensitive, ValueError when no value has that
  ## name) through a table built on first use: parseEnum is a `case` over
  ## every name, ~100 KB of code for TranslationKey alone.
  when E is Ordinal:
    var names {.global.}: Table[string, int]
    if names.len == 0:
      for e in E: names[nimIdentNormalize($e)] = ord(e)
    var o: int
    if not names.findName(s, o): raise newException(ValueError, "Invalid enum value: " & s)
    E(o)
  else:   # (a holey enum)
    parseEnum[E](s)

proc assignScript*[E: enum](vm: VM, dest: var E, v: ScriptValue, field: string) =
  if v.kind != vkString:
    vm.runtimeError("field '" & field & "' expects a name, got " & typeName(v))
  try:
    dest = enumByName[E](v.str.s)
  except ValueError:
    vm.runtimeError("field '" & field & "' has no value named '" & v.str.s & "'")

proc assignScript*(vm: VM, dest: var Vector2, v: ScriptValue, field: string) =
  let (x, y) = parseVec(vm, v, field)
  dest = Vector2(x: x.float32, y: y.float32)

proc assignScript*(vm: VM, dest: var Color, v: ScriptValue, field: string) =
  dest = parseColor(vm, v, field)

proc assignScript*[E: enum](vm: VM, dest: var set[E], v: ScriptValue, field: string) =
  if v.kind != vkTable:
    vm.runtimeError("field '" & field & "' expects a list of names")
  var s: set[E]
  for x in v.tbl:
    if x.kind != vkString:
      vm.runtimeError("field '" & field & "' expects a list of names")
    try:
      s.incl(enumByName[E](x.str.s))
    except ValueError:
      vm.runtimeError("field '" & field & "' has no value named '" & x.str.s & "'")
  dest = s

proc checkKeys*(vm: VM, t: ScriptTable, allowed: openArray[string], what: string) =
  ## A typo in an option table is an error naming it, never a silent no-op
  ## (every register.* and spawn.* table added since the 3D API is strict).
  for (k, _) in pairsCursor(t):
    if k.kind != vkString:
      vm.runtimeError(what & ": keys must be field names")
    if k.str.s notin allowed:
      vm.runtimeError(what & ": unknown field '" & k.str.s & "' (fields: " & allowed.join(", ") & ")")

# --------------------------------------------------------------- generic ----
proc reflectGet*[T: ref object](obj: T, name: string, found: var bool): ScriptValue =
  found = false
  for fname, v in fieldPairs(obj[]):
    when compiles(toScript(v)):
      if fname == name:
        found = true
        return toScript(v)
  NilValue

proc reflectSet*[T: ref object](vm: VM, obj: T, name: string, val: ScriptValue): bool =
  for fname, v in fieldPairs(obj[]):
    when compiles(assignScript(vm, v, val, fname)):
      if fname == name:
        assignScript(vm, v, val, fname)
        return true
  false

# ------------------------------------------------------ whole objects ----
proc objToValue*[T](v: T): ScriptValue =
  ## A plain-data snapshot of any object (configs, boss definitions): nested
  ## objects become tables, seqs become arrays. For reading and copying only.
  when T is Vector2 or T is Vector2:
    vec2Value(v.x, v.y)
  elif T is Color:
    colorValue(v)
  elif T is object:
    let t = newScriptTable()
    for name, f in fieldPairs(v):
      let x = objToValue(f)
      if x.kind != vkNil:
        rawSet(t, vstr(name), x)
    vtable(t)
  elif T is seq:
    let t = newScriptTable()
    for i, x in v:   # by index: a nil must not shift what follows
      let e = objToValue(x)
      if e.kind != vkNil: rawSet(t, vnum(i + 1), e)
    vtable(t)
  elif compiles(toScript(v)):
    toScript(v)
  else:
    NilValue

proc applyTable*[T: object](vm: VM, obj: var T, t: ScriptTable, what: string,
                            skip: openArray[string] = []) =
  ## Write a script table's fields into `obj` (nested objects from nested
  ## tables). An unknown or unsettable field name is an error that names it,
  ## so a typo in a mod's override never silently does nothing.
  for (k, v) in pairsCursor(t):
    if k.kind != vkString:
      vm.runtimeError(what & ": keys must be field names")
    let name = k.str.s
    if name in skip: continue
    var done = false
    for fname, f in fieldPairs(obj):
      if not done and fname == name:
        when f is object and not (f is Vector2 or f is Vector2 or f is Color):
          if v.kind != vkTable:
            vm.runtimeError(what & "." & name & " must be a table")
          applyTable(vm, f, v.tbl, what & "." & name)
          done = true
        elif compiles(assignScript(vm, f, v, fname)):
          assignScript(vm, f, v, fname)
          done = true
    if not done:
      vm.runtimeError(what & " has no settable field '" & name & "'")
