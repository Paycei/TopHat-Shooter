## Compile-time type-layout fingerprints.
##
## A binary format that writes a type graph positionally (no field names) is
## only readable under the exact layout that wrote it. layoutSignature turns a
## whole type graph into a string at compile time -- every field's name and
## type down to the leaves, and every enum's values -- so a hash of it changes
## whenever any type in the graph does, however deep. suspend.nim keys its
## snapshots on one; co-op refuses a peer whose run-state layout differs.

import std/macros

proc layoutOf*(t: NimNode, seen: var seq[string], skip: seq[string]): string {.compileTime.} =
  ## The serialized shape of type `t`. A named type met again is named, not
  ## expanded (refs can be recursive); a type in `skip` is only named.
  case t.kind
  of nnkSym:
    let name = $t
    case t.typeKind
    of ntyBool, ntyChar, ntyString, ntyCString, ntyPointer, ntyInt, ntyInt8, ntyInt16,
       ntyInt32, ntyInt64, ntyFloat, ntyFloat32, ntyFloat64, ntyUInt, ntyUInt8,
       ntyUInt16, ntyUInt32, ntyUInt64:
      return name
    else: discard
    if name in skip: return "~" & name
    let id = t.signatureHash
    if id in seen: return "@" & name
    seen.add id
    let impl = t.getTypeImpl
    if impl.kind == nnkSym and impl == t: return name
    result = name & "=" & layoutOf(impl, seen, skip)
  of nnkObjectTy:
    result = "object"
    if t[1].kind == nnkOfInherit:
      result.add " of " & layoutOf(t[1][0], seen, skip)
    result.add "{" & layoutOf(t[2], seen, skip) & "}"
  of nnkRecList:
    for f in t: result.add layoutOf(f, seen, skip) & ";"
  of nnkIdentDefs:
    let typ = layoutOf(t[^2], seen, skip)
    for i in 0 ..< t.len - 2: result.add $t[i] & ":" & typ & ","
  of nnkRecCase:
    result = "case " & layoutOf(t[0], seen, skip)
    for i in 1 ..< t.len: result.add layoutOf(t[i], seen, skip)
  of nnkOfBranch:
    result = "of "
    for i in 0 ..< t.len - 1: result.add t[i].repr & ","
    result.add "{" & layoutOf(t[^1], seen, skip) & "}"
  of nnkElse:
    result = "else{" & layoutOf(t[0], seen, skip) & "}"
  of nnkNilLit, nnkEmpty:
    result = ""
  of nnkEnumTy:
    result = "enum("
    for i in 1 ..< t.len: result.add t[i].repr & ","
    result.add ")"
  of nnkRefTy: result = "ref " & layoutOf(t[0], seen, skip)
  of nnkPtrTy: result = "ptr " & layoutOf(t[0], seen, skip)
  of nnkDistinctTy: result = "distinct " & layoutOf(t[0], seen, skip)
  of nnkTupleTy:
    result = "tuple["
    for f in t: result.add layoutOf(f, seen, skip)
    result.add "]"
  of nnkTupleConstr, nnkPar:
    result = "("
    for f in t: result.add layoutOf(f, seen, skip) & ","
    result.add ")"
  of nnkBracketExpr:
    # seq[T], array[R, T], set[T], a generic instance (Table[K, V], Deque[T]):
    # the container by name, its arguments expanded.
    result = $t[0] & "["
    for i in 1 ..< t.len:
      result.add (if t[i].kind in {nnkSym, nnkBracketExpr, nnkTupleConstr, nnkPar}:
                    layoutOf(t[i], seen, skip) else: t[i].repr) & ","
    result.add "]"
  else:
    result = t.repr

macro layoutSignature*(T: typedesc, skip: varargs[string]): string =
  var skipNames: seq[string]
  for s in skip: skipNames.add s.strVal
  var seen: seq[string]
  newLit(layoutOf(T.getTypeInst[1], seen, skipNames))   # (T arrives as typedesc[X])

proc fnv32*(s: string, h = 2166136261'u32): uint32 =
  result = h
  for c in s: result = (result xor uint32(ord(c))) * 16777619'u32

