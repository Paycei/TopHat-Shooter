## Co-op snapshots: the host's run, as a client receives it.
##
## The host never sends a per-mode description of its world: it sends the run
## itself -- the Game, every player, every enemy, bullet, coin and XP orb --
## written with coop_wire, and a client decodes it into its own Game and draws
## that with the normal drawGame. Whatever a mode, a boss or a mod puts in the
## run's state is on the client's screen with no code of its own.
##
## To keep that small, a snapshot is the CHANGE since a snapshot the client
## has confirmed (its `base`): the run is cut into sections -- the core (every
## Game field but the players and the busy lists), one per player, one per
## entity, keyed by its id -- and a section that did not change costs one
## byte; one that did is XORed against its base copy (an unchanged field turns
## into zeros) and its zero runs are counted instead of sent. A client that
## confirmed nothing recent gets the full sections. The host keeps the last
## SnapBaseRing frames as bases; a client keeps the frames it rebuilt.
##
## Everything a client reads goes through coop_wire's checked reader; a
## malformed snapshot raises CoopWireError and is dropped whole (the mirror is
## only touched once the snapshot has been read completely).

import std/tables
import supersnappy
import ../modding/mod_patch_core
import ../types, ../layout_fp, ../suspend
import coop_wire, coop_context

const
  SnapBaseRing* = 16                 ## frames a delta may be based on, both sides
  MaxSnapshotBytes = 16 * 1024 * 1024 ## largest decompressed snapshot accepted
  CoreLists = ["player", "players", "enemies", "bullets", "coins", "xpOrbs"]
    ## Game fields sent as their own sections, not in the core

  CoopLayoutHash* = fnv32(layoutSignature(Game,
    "DiscordClient", "ParticlePool", "RogueliteProfile"))
    ## The run state's whole type layout: two builds that disagree on it can't
    ## read each other's snapshots, so the lobby refuses the pairing.

type
  EntityList* = enum
    elEnemies, elBullets, elCoins, elXpOrbs

  WireFrame* = ref object
    ## One snapshot's sections as bytes: what later snapshots are deltas
    ## against (the host's as sent, a client's as rebuilt).
    seq*: int32
    core*: string
    players*: seq[string]
    ents*: array[EntityList, seq[tuple[id: int32, bytes: string]]]
    index: array[EntityList, Table[int32, int]]

  SnapExtras* = object
    ## The per-client part of a snapshot.
    actionAck*: int32                 ## the newest of this client's actions the host applied
    profileFirst*: int32              ## the seq of profileEvents[0]
    profileEvents*: seq[ProfileEvent] ## its profile progress not confirmed yet

  FrameRing* = object
    frames: array[SnapBaseRing, WireFrame]

  SnapStats* = object
    ## What the last encoded snapshot cost (the debug net overlay).
    rawBytes*, sentBytes*: int
    sections*, changed*: int

var lastSnapStats*: SnapStats

proc put*(r: var FrameRing, f: WireFrame) =
  r.frames[int(f.seq) mod SnapBaseRing] = f

proc find*(r: FrameRing, seq: int32): WireFrame =
  if seq <= 0: return nil
  let f = r.frames[int(seq) mod SnapBaseRing]
  if not f.isNil and f.seq == seq: f else: nil

proc clear*(r: var FrameRing) =
  for f in r.frames.mitems: f = nil

proc addEntity(f: WireFrame, kind: EntityList, id: int32, bytes: sink string) =
  f.index[kind][id] = f.ents[kind].len
  f.ents[kind].add((id, bytes))

proc entityBytes(f: WireFrame, kind: EntityList, id: int32): ptr string =
  if f.isNil: return nil
  let i = f.index[kind].getOrDefault(id, -1)
  if i < 0: nil else: addr f.ents[kind][i].bytes

# ------------------------------------------------------------- the core ----

proc putCore(s: var string, g: Game) =
  for name, f in g[].fieldPairs:
    when not coopSkipsField("Game", name) and name notin CoreLists:
      putW(s, f)

proc getCore(s: string, g: Game) =
  var i = 0
  for name, f in g[].fieldPairs:
    when not coopSkipsField("Game", name) and name notin CoreLists:
      getW(s, i, f)
  if i != s.len: wireFail()

# ----------------------------------------------------------- the frames ----

proc nextNetId(): int32 =
  ## Host: ids for the bullets, coins and orbs the snapshots carry.
  var counter {.global.}: int32 = 0
  inc counter
  if counter <= 0: counter = 1   # (wrapped: ids only need to be unique among the live)
  counter

template keyed(list, kind, idExpr: untyped) =
  ## Each entity of `list` under its id. An id met twice in one frame (a
  ## bullet copied field for field carries its netId along) gets a fresh one,
  ## or two entities would land in one object on the client.
  for x {.inject.} in list:
    if idExpr == 0 or result.index[kind].hasKey(idExpr): idExpr = nextNetId()
    result.addEntity(kind, idExpr, toWire(x))

proc captureFrame*(game: Game, seq: int32): WireFrame {.moddable.} =
  ## Host: this frame of the run, as sections.
  result = WireFrame(seq: seq)
  putCore(result.core, game)
  for p in game.players:
    result.players.add toWire(p)
  for e in game.enemies:
    # An enemy's id is the game's own (scripts and links key on it), so a
    # duplicate goes under a key of its own instead.
    var key = int32(e.id)
    if result.index[elEnemies].hasKey(key): key = -nextNetId()
    result.addEntity(elEnemies, key, toWire(e))
  keyed(game.bullets, elBullets, x.netId)
  keyed(game.coins, elCoins, x.netId)
  keyed(game.xpOrbs, elXpOrbs, x.netId)

# ------------------------------------------------------ section deltas ----

proc putVar(s: var string, n: int) =
  ## A length as a little-endian base-128 varint (zero runs are mostly short).
  var v = uint64(n)
  while v >= 0x80'u64:
    s.add char((v and 0x7F) or 0x80)
    v = v shr 7
  s.add char(v)

proc getVar(s: string, i: var int): int =
  var shift = 0
  var v: uint64
  while true:
    if i >= s.len or shift > 35: wireFail()
    let b = uint64(ord(s[i]))
    inc i
    v = v or ((b and 0x7F) shl shift)
    if b < 0x80: break
    shift += 7
  if v > uint64(high(int32)): wireFail()
  int(v)

proc xorRle*(cur, base: string): string =
  ## `cur` XOR `base` (same length) as runs: zeros skipped (counted), the rest
  ## written as they are.
  var i = 0
  while i < cur.len:
    var z = i
    while z < cur.len and cur[z] == base[z]: inc z
    var lit = z
    while lit < cur.len and cur[lit] != base[lit]: inc lit
    result.putVar(z - i)
    result.putVar(lit - z)
    for k in z ..< lit:
      result.add char(ord(cur[k]) xor ord(base[k]))
    i = lit

proc unXorRle*(delta, base: string): string =
  ## Rebuild what xorRle encoded against `base`.
  result = base
  var i = 0
  var at = 0
  while i < delta.len:
    let zeros = getVar(delta, i)
    let lits = getVar(delta, i)
    if zeros > result.len - at: wireFail()
    at += zeros
    if lits > result.len - at or lits > delta.len - i: wireFail()
    for k in 0 ..< lits:
      result[at + k] = char(ord(result[at + k]) xor ord(delta[i + k]))
    at += lits
    i += lits

proc putSection(s: var string, cur: string, base: ptr string, stats: var SnapStats) =
  inc stats.sections
  if not base.isNil and cur == base[]:
    s.add '\0'                          # unchanged
    return
  inc stats.changed
  if not base.isNil and cur.len == base[].len:
    s.add '\1'                          # changed: XOR runs against the base
    putW(s, xorRle(cur, base[]))
  else:
    s.add '\2'                          # new, or a different size: whole
    putW(s, cur)

proc getSection(s: string, i: var int, base: ptr string): string =
  if i >= s.len: wireFail()
  let mode = s[i]
  inc i
  case mode
  of '\0':
    if base.isNil: wireFail()
    result = base[]
  of '\1':
    if base.isNil: wireFail()
    var delta: string
    getW(s, i, delta)
    result = unXorRle(delta, base[])
  of '\2':
    getW(s, i, result)
  else:
    wireFail()

# ------------------------------------------------------------ encoding ----

proc encodeSnapshot*(cur, base: WireFrame, extras: SnapExtras): string {.moddable.} =
  ## Host: snapshot `cur` for one client, as the change since `base` (nil:
  ## everything), compressed.
  var stats: SnapStats
  var s = ""
  putW(s, cur.seq)
  putW(s, if base.isNil: 0'i32 else: base.seq)
  putW(s, extras)
  putSection(s, cur.core, (if base.isNil: nil else: addr base.core), stats)
  putW(s, int32(cur.players.len))
  for k, p in cur.players:
    let b = if base.isNil or k >= base.players.len: nil else: addr base.players[k]
    putSection(s, p, b, stats)
  for kind in EntityList:
    putW(s, int32(cur.ents[kind].len))
    for e in cur.ents[kind]:
      putW(s, e.id)
      putSection(s, e.bytes, base.entityBytes(kind, e.id), stats)
  stats.rawBytes = s.len
  result = supersnappy.compress(s)
  stats.sentBytes = result.len
  lastSnapStats = stats

# ------------------------------------------------------------ decoding ----

proc snappyDeclaredLen(data: string): int64 =
  var shift = 0
  for i in 0 ..< min(data.len, 5):
    let b = ord(data[i])
    result = result or (int64(b and 0x7F) shl shift)
    if b < 0x80: return
    shift += 7
  result = -1

proc readSnapshot*(packed: string, ring: FrameRing,
                   extras: var SnapExtras): WireFrame {.moddable.} =
  ## Client: rebuild a snapshot's sections against the base it names (which
  ## must be one of the frames this client kept). Raises CoopWireError when it
  ## is malformed or its base is gone; nothing is applied yet.
  let declared = snappyDeclaredLen(packed)
  if declared < 0 or declared > MaxSnapshotBytes: wireFail()
  let s = try: supersnappy.uncompress(packed)
          except CatchableError: wireFail()
  var i = 0
  var seq, baseSeq: int32
  getW(s, i, seq)
  getW(s, i, baseSeq)
  let base = if baseSeq == 0: nil else: ring.find(baseSeq)
  if baseSeq != 0 and base.isNil: wireFail("snapshot base no longer kept")
  getW(s, i, extras)
  result = WireFrame(seq: seq)
  result.core = getSection(s, i, (if base.isNil: nil else: addr base.core))
  var nPlayers: int32
  getW(s, i, nPlayers)
  if nPlayers < 0 or nPlayers > MaxCoopPlayers: wireFail()
  for k in 0 ..< nPlayers.int:
    let b = if base.isNil or k >= base.players.len: nil else: addr base.players[k]
    result.players.add getSection(s, i, b)
  for kind in EntityList:
    var n: int32
    getW(s, i, n)
    if n < 0 or n > (s.len - i) div 5: wireFail()
    for _ in 0 ..< n.int:
      var id: int32
      getW(s, i, id)
      result.addEntity(kind, id, getSection(s, i, base.entityBytes(kind, id)))
  if i != s.len: wireFail()

proc decodeList[T](frame: WireFrame, kind: EntityList, old: seq[T],
                   idOf: proc (x: T): int32 {.nimcall.}): seq[T] =
  ## A list in the host's order, decoded into the objects the mirror already
  ## has for those ids (they keep their identity), new ones for the rest.
  var byId = initTable[int32, T]()
  for x in old:
    if not x.isNil: byId[idOf(x)] = x
  for e in frame.ents[kind]:
    var x = byId.getOrDefault(e.id)
    fromWire(e.bytes, x)
    result.add x

proc applySnapshot*(frame: WireFrame, game: Game) {.moddable.} =
  ## Client: make the mirror the host's run of `frame` (already read whole).
  ## Decoded into the mirror's own objects, which keep their identity; the
  ## fields each machine keeps for itself (CoopSkipFields) are left alone.
  var players = game.players
  players.setLen(frame.players.len)
  for k in 0 ..< frame.players.len:
    fromWire(frame.players[k], players[k])
  # Lists first (decodeList reads the old ones), then the core and the players.
  let enemies = decodeList(frame, elEnemies, game.enemies,
                           proc (e: Enemy): int32 {.nimcall.} = int32(e.id))
  let bullets = decodeList(frame, elBullets, game.bullets,
                           proc (b: Bullet): int32 {.nimcall.} = b.netId)
  let coins = decodeList(frame, elCoins, game.coins,
                         proc (c: Coin): int32 {.nimcall.} = c.netId)
  let orbs = decodeList(frame, elXpOrbs, game.xpOrbs,
                        proc (o: XpOrb): int32 {.nimcall.} = o.netId)
  getCore(frame.core, game)
  game.players = players
  game.enemies = enemies
  game.bullets = bullets
  game.coins = coins
  game.xpOrbs = orbs
  # A hazard two things point at (a Cross enemy's dash laser, a satellite's
  # beam) arrived as two copies: make them one again, as a restore does.
  relinkSharedRefs(game)
  # This machine's player is the active one between frames.
  if localSlot >= 0 and localSlot < game.players.len:
    game.player = game.players[localSlot]
