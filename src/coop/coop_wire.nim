## Co-op wire codec: a symmetric binary writer/reader for the run's object graph.
##
## The host sends its whole simulation to co-op clients (coop_codec.nim), so the
## format has to cover every type the run holds -- refs, sets, tables, deques --
## and be safe to read from the network. flatty can write it, but its reader
## trusts every length and enum tag, and its writer's generic instances are
## shared with suspend.nim's (different) overloads for the same types. So co-op
## has its own pair, putW/getW, generic over the whole graph:
##
## * Fixed widths everywhere (numbers at their size, enums at theirs, lengths
##   as uint32, a set as a bitmask over its range). Two encodings of the same
##   entity then line up byte for byte, which is what the XOR deltas in
##   coop_codec.nim rely on: an unchanged field XORs to zeros.
## * Every read is checked against what is left of the input; a length may
##   allocate no more than the bytes that could fill it; every enum is checked
##   against its range. Anything malformed raises CoopWireError, never crashes
##   (including under -d:danger, which compiles Nim's own checks out).
## * A ref is a presence byte and then its fields. Reading into a ref that is
##   already set reuses that object, so a client decoding into its mirror keeps
##   its objects' identity (the 3D animation tracks and interpolation key on it).
## * Fields named in CoopSkipFields (process handles, per-machine UI state, the
##   `game.player` alias) are never written and never touched on read; types in
##   CoopSkipTypes are written as nothing wherever they appear.
## * A field type the codec does not know is a compile error: give it a branch.

import std/[tables, deques, typetraits]

type CoopWireError* = object of ValueError

proc wireFail*(what = "malformed co-op data") {.noinline, noreturn.} =
  raise newException(CoopWireError, what)

const
  CoopSkipTypes* = ["DiscordClient", "ParticlePool", "RogueliteProfile"]
    ## Process handles and the live meta profile: nothing to send, ever.

  CoopSkipFields* = [
    # The active-player alias: it points into game.players, and writing it
    # would send (and on read, duplicate) that player a second time. The
    # receiver re-points it at its own slot.
    "Game.player",
    # Process handles, per-machine buffers and timings.
    "Game.particlePool", "Game.discordClient", "Game.rogueliteProfile",
    "Game.game3D", "Game.perfUpdateMs", "Game.perfDrawMs",
    # Cursors, scroll offsets and input bookkeeping of each machine's own menus.
    "Game.selectedShopItem", "Game.shopItemsScroll", "Game.shopSidebarScroll",
    "Game.selectedPowerUp",
    "Game.rollAnimationActive", "Game.rollAnimationTimer", "Game.rollSpeed",
    "Game.rollPosition", "Game.rollBrakeStartPos", "Game.rollPowerUpList",
    "Game.canSelectPowerUp", "Game.draftInputGrace", "Game.draftAwaitRelease",
    "Game.lastMousePos", "Game.mouseMovedRecently", "Game.keyboardUsedRecently",
    "Game.previousState",
    "Game.sandboxSidebarOpen", "Game.sandboxSelectedTab", "Game.sandboxScrollOffset",
    "Game.sandboxScrollbarDragging", "Game.sandboxScrollbarDragOffsetY",
    "Game.pauseMenuTab", "Game.selectedGameOverButton", "Game.selectedVictoryButton",
    "Game.confirmQuitPending", "Game.pauseMenuExitCooldown", "Game.confirmQuitFrameGuard",
    "Game.selectedRogueliteStarter", "Game.selectedRogueliteHeat",
    "Game.selectedRogueliteTheme", "Game.rogueliteHeatPulseTimer",
    "Game.rogueliteHeatPulseDirection",
    # One-shot flags main.nim consumes on the machine that raised them.
    "Game.pendingToasts", "Game.tophatJustUnlocked", "Game.cheaterHatJustEarned",
    "Game.cheatRogueliteSkipFloor", "Game.cheatRogueliteDirectFloorSelect",
    # Each machine's own view of a team modal: its player's roll, prices and
    # cache reveal come from CoopState.seats and Player.shopBought.
    "Game.powerUpChoices", "Game.rerollCost", "Game.shopItems", "Game.modShopBought",
    "SurvivalState.reveal",
    # Presentation each machine animates itself: the desktop-style backdrop
    # (the boss-arena field travels in Game.bossArena and Player.arena), the
    # screen shake and the floating rewards, and the effect lists (the host's
    # effects arrive as events instead).
    "Game.osBackground", "DopamineState.screenShake", "DopamineState.microRewards",
    "Game.damageNumbers", "Game.currencyIndicators", "Game.perkIndicators",
    "Game.lightningBolts", "Game.shockwaveRings", "Game.pathShockwaves",
    # A player's input: a client keeps its own (its movement is predicted).
    "Player.intent",
    # A hit's one-frame signal, consumed by whichever machine draws it: it
    # travels as an effect (coop_fx), or a host that never draws as a
    # teammate would keep sending theirs.
    "Player.lastDamageEvent",
    # The power-up install card shows over each machine's own player, for its
    # own installs (an effect too).
    "Game.recentPowerUp", "Game.recentPowerUpTimer", "Game.recentPowerUpMaxTimer",
  ]

proc coopSkipsField*(owner, name: string): bool {.compileTime.} =
  ## Whether `owner.name` is never sent (see CoopSkipFields).
  (owner & "." & name) in CoopSkipFields

proc skippedField(owner, name: string): bool {.compileTime.} =
  (owner & "." & name) in CoopSkipFields

proc skippedType(name: string): bool {.compileTime.} =
  name in CoopSkipTypes

# ---------------------------------------------------------------- sizing ----

proc setBytes[E](x: set[E]): int =
  ## A set's bitmask size: one bit per value of its element range.
  (ord(high(E)) - ord(low(E)) + 8) div 8

proc wireMin*(T: typedesc): int =
  ## The fewest bytes one T takes on the wire: a declared count may not claim
  ## more elements than the input could hold at this size.
  when T is bool or T is char: 1
  elif T is SomeNumber or T is enum: sizeof(T)
  elif T is string or T is seq: 4
  elif T is pointer: 0
  elif T is ref:
    when skippedType($T): 0 else: 1
  elif T is set:
    var probe: T
    setBytes(probe)
  elif T is array:
    var probe: T
    probe.len * wireMin(typeof(probe[low(probe)]))
  elif T is Table or T is Deque: 4
  elif T is tuple:
    var n = 0
    var probe: T
    for f in probe.fields: n += wireMin(typeof(f))
    n
  elif T is object:
    when skippedType($T): 0
    else:
      var n = 0
      var probe: T
      for name, f in probe.fieldPairs:
        when not skippedField($T, name):
          n += wireMin(typeof(f))
      n
  else:
    {.error: "a co-op wire field type wireMin does not know: " & $T.}

# --------------------------------------------------------------- writing ----

proc putW*(s: var string, x: bool)
proc putW*(s: var string, x: char)
proc putW*[T: SomeNumber](s: var string, x: T)
proc putW*[T: enum](s: var string, x: T)
proc putW*(s: var string, x: string)
proc putW*(s: var string, x: pointer)
proc putW*[T](s: var string, x: seq[T])
proc putW*[I, T](s: var string, x: array[I, T])
proc putW*[T](s: var string, x: set[T])
proc putW*[K, V](s: var string, x: Table[K, V])
proc putW*[T](s: var string, x: Deque[T])
proc putW*[T: tuple](s: var string, x: T)
proc putW*[T: object](s: var string, x: T)
proc putW*[T: ref](s: var string, x: T)

template putRaw(s: var string, x: typed) =
  let at = s.len
  s.setLen(at + sizeof(x))
  copyMem(addr s[at], unsafeAddr x, sizeof(x))

proc putLen(s: var string, n: int) {.inline.} =
  if n < 0 or n > int(high(uint32)): wireFail("co-op data too large")
  let v = uint32(n)
  putRaw(s, v)

proc putW*(s: var string, x: bool) = s.add(if x: '\1' else: '\0')

proc putW*(s: var string, x: char) = s.add x

proc putW*[T: SomeNumber](s: var string, x: T) = putRaw(s, x)

proc putW*[T: enum](s: var string, x: T) = putRaw(s, x)

proc putW*(s: var string, x: string) =
  putLen(s, x.len)
  if x.len > 0:
    let at = s.len
    s.setLen(at + x.len)
    copyMem(addr s[at], unsafeAddr x[0], x.len)

proc putW*(s: var string, x: pointer) = discard

proc putW*[T](s: var string, x: seq[T]) =
  putLen(s, x.len)
  for e in x: putW(s, e)

proc putW*[I, T](s: var string, x: array[I, T]) =
  for e in x: putW(s, e)

proc putW*[T](s: var string, x: set[T]) =
  const lo = ord(low(T))
  const bytes = (ord(high(T)) - lo + 8) div 8
  var bits: array[bytes, uint8]
  for e in x:
    let k = ord(e) - lo
    bits[k shr 3] = bits[k shr 3] or uint8(1 shl (k and 7))
  for b in bits: s.add char(b)

proc putW*[K, V](s: var string, x: Table[K, V]) =
  putLen(s, x.len)
  for k, v in tables.pairs(x):
    putW(s, k)
    putW(s, v)

proc putW*[T](s: var string, x: Deque[T]) =
  putLen(s, x.len)
  for k in 0 ..< x.len: putW(s, x[k])   # (deques.items is not visible at every instantiation)

proc putW*[T: tuple](s: var string, x: T) =
  for f in x.fields: putW(s, f)

proc putFields[T](s: var string, x: T, owner: static string) =
  for name, f in x.fieldPairs:
    when not skippedField(owner, name):
      putW(s, f)

proc putW*[T: object](s: var string, x: T) =
  when not skippedType($T):
    putFields(s, x, $T)

proc putW*[T: ref](s: var string, x: T) =
  when not skippedType($T):
    if x.isNil:
      s.add '\0'
    else:
      s.add '\1'
      putFields(s, x[], $T)

# --------------------------------------------------------------- reading ----

proc getW*(s: string, i: var int, x: var bool)
proc getW*(s: string, i: var int, x: var char)
proc getW*[T: SomeNumber](s: string, i: var int, x: var T)
proc getW*[T: enum](s: string, i: var int, x: var T)
proc getW*(s: string, i: var int, x: var string)
proc getW*(s: string, i: var int, x: var pointer)
proc getW*[T](s: string, i: var int, x: var seq[T])
proc getW*[I, T](s: string, i: var int, x: var array[I, T])
proc getW*[T](s: string, i: var int, x: var set[T])
proc getW*[K, V](s: string, i: var int, x: var Table[K, V])
proc getW*[T](s: string, i: var int, x: var Deque[T])
proc getW*[T: tuple](s: string, i: var int, x: var T)
proc getW*[T: object](s: string, i: var int, x: var T)
proc getW*[T: ref](s: string, i: var int, x: var T)

template need(s: string, i, n: int) =
  if n < 0 or n > s.len - i: wireFail()

template getRaw(s: string, i: var int, x: typed) =
  need(s, i, sizeof(x))
  copyMem(addr x, unsafeAddr s[i], sizeof(x))
  i += sizeof(x)

proc getCount(s: string, i: var int, unit: int): int {.inline.} =
  ## A declared element count, refused if the rest of the input could not
  ## hold that many elements of at least `unit` bytes each.
  var v: uint32
  getRaw(s, i, v)
  result = int(v)
  if result > (s.len - i) div max(1, unit): wireFail()

proc getW*(s: string, i: var int, x: var bool) =
  need(s, i, 1)
  x = s[i] != '\0'
  inc i

proc getW*(s: string, i: var int, x: var char) =
  need(s, i, 1)
  x = s[i]
  inc i

proc getW*[T: SomeNumber](s: string, i: var int, x: var T) = getRaw(s, i, x)

proc getW*[T: enum](s: string, i: var int, x: var T) =
  static: doAssert sizeof(T) in [1, 2, 4], "co-op wire: an enum wider than 4 bytes"
  when sizeof(T) == 1:
    var v: uint8
  elif sizeof(T) == 2:
    var v: uint16
  else:
    var v: int32
  getRaw(s, i, v)
  when T is HoleyEnum:
    var ok = false
    for e in T:
      if ord(e) == int(v):
        ok = true
        break
    if not ok: wireFail()
  else:
    if int(v) < ord(low(T)) or int(v) > ord(high(T)): wireFail()
  x = T(v)

proc getW*(s: string, i: var int, x: var string) =
  let n = getCount(s, i, 1)
  x.setLen(n)
  if n > 0:
    copyMem(addr x[0], unsafeAddr s[i], n)
    i += n

proc getW*(s: string, i: var int, x: var pointer) = x = nil

proc getW*[T](s: string, i: var int, x: var seq[T]) =
  const unit = wireMin(T)
  let n = getCount(s, i, unit)
  x.setLen(n)
  for e in x.mitems: getW(s, i, e)

proc getW*[I, T](s: string, i: var int, x: var array[I, T]) =
  for e in x.mitems: getW(s, i, e)

proc getW*[T](s: string, i: var int, x: var set[T]) =
  const lo = ord(low(T))
  const hi = ord(high(T))
  const bytes = (hi - lo + 8) div 8
  need(s, i, bytes)
  x = {}
  for k in 0 .. hi - lo:
    if (uint8(s[i + (k shr 3)]) and uint8(1 shl (k and 7))) != 0:
      when T is enum and T is HoleyEnum:
        var ok = false
        for e in T:
          if ord(e) == lo + k:
            ok = true
            break
        if not ok: wireFail()
      x.incl T(lo + k)
  # Bits past the range in the last byte must be clear (a re-encode would drop them).
  for k in hi - lo + 1 ..< bytes * 8:
    if (uint8(s[i + (k shr 3)]) and uint8(1 shl (k and 7))) != 0: wireFail()
  i += bytes

proc getW*[K, V](s: string, i: var int, x: var Table[K, V]) =
  const unit = wireMin(K) + wireMin(V)
  let n = getCount(s, i, unit)
  x.clear()
  for _ in 0 ..< n:
    var k: K
    var v: V
    getW(s, i, k)
    getW(s, i, v)
    x[k] = v

proc getW*[T](s: string, i: var int, x: var Deque[T]) =
  const unit = wireMin(T)
  let n = getCount(s, i, unit)
  x = initDeque[T]()
  for _ in 0 ..< n:
    var e: T
    getW(s, i, e)
    x.addLast(e)

proc getW*[T: tuple](s: string, i: var int, x: var T) =
  for f in x.fields: getW(s, i, f)

proc getFields[T](s: string, i: var int, x: var T, owner: static string) =
  for name, f in x.fieldPairs:
    when not skippedField(owner, name):
      getW(s, i, f)

proc getW*[T: object](s: string, i: var int, x: var T) =
  when not skippedType($T):
    getFields(s, i, x, $T)

proc getW*[T: ref](s: string, i: var int, x: var T) =
  when not skippedType($T):
    need(s, i, 1)
    let present = s[i]
    inc i
    case present
    of '\0': x = nil
    of '\1':
      if x.isNil: new(x)
      getFields(s, i, x[], $T)
    else: wireFail()

# ------------------------------------------------------------ whole values ----

proc toWire*[T](x: T): string =
  putW(result, x)

proc fromWire*[T](s: string, x: var T) =
  ## Decode a whole value, which must use up the input exactly.
  var i = 0
  getW(s, i, x)
  if i != s.len: wireFail()
