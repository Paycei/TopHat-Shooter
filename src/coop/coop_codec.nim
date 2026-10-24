## Co-op snapshots: the host's run, as a client receives it.
##
## The host never sends a per-mode description of its world: it sends the run
## itself -- the Game, every player, every enemy, bullet, coin and XP orb --
## written with coop_wire, and a client decodes it into its own Game and draws
## that with the normal drawGame. Whatever a mode, a boss or a mod puts in the
## run's state is on the client's screen with no code of its own.
##
## To keep that small, a snapshot is the CHANGE since a snapshot the client
## has confirmed (its `base`): the run is cut into sections -- each field of the
## Game (but the players and the busy lists), each field of each player, one
## per entity, keyed by its id -- and a section that did not change costs one
## byte; one that did is XORed against its base copy (an unchanged field turns
## into zeros) and its zero runs are counted instead of sent. A field is a
## section of its own so a list that grows or shrinks costs only itself: the
## rest of the run still goes as a change. A client that
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
import ../game3d/[types_3d, engine_3d]
import coop_wire, coop_context

const
  SnapBaseRing* = 16                 ## frames a delta may be based on, both sides
  MaxSnapshotBytes = 16 * 1024 * 1024 ## largest decompressed snapshot accepted
  CoreLists = ["player", "players", "enemies", "bullets", "coins", "xpOrbs"]
    ## Game fields sent as their own sections, not in the core
  NoSkip: array[0, string] = []

  CoopLayoutHash* = fnv32(layoutSignature(Game,
    "DiscordClient", "ParticlePool", "RogueliteProfile") & layoutSignature(Game3D))
    ## The run state's whole type layout: two builds that disagree on it can't
    ## read each other's snapshots, so the lobby refuses the pairing.

type
  EntityList* = enum
    elEnemies, elBullets, elCoins, elXpOrbs

  WireFrame* = ref object
    ## One snapshot's sections as bytes: what later snapshots are deltas
    ## against (the host's as sent, a client's as rebuilt).
    seq*: int32
    core*: seq[string]            ## the Game's fields, one section each
    players*: seq[seq[string]]    ## each player's fields, one section each
    world3d*: string     ## the 3D world the run is in ("" when none)
    ents*: array[EntityList, seq[tuple[id: int32, bytes: string]]]
    index: array[EntityList, Table[int32, int]]

  SnapExtras* = object
    ## The per-client part of a snapshot.
    actionAck*: int32                 ## the newest of this client's actions the host applied
    intentAck*: int32                 ## the newest of its input packets the host took
    profileFirst*: int32              ## the seq of profileEvents[0]
    profileEvents*: seq[ProfileEvent] ## its profile progress not confirmed yet
    fx*: seq[CoopFx]                  ## the effects since the last snapshot, and
                                      ## the last snapshot's again (coop_fx)

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

template sentFieldsOf(obj, owner, skip, body: untyped) {.dirty.} =
  ## `body` for each field of `obj` the snapshots carry (`f` the field).
  for name, f in obj.fieldPairs:
    when not coopSkipsField(owner, name) and name notin skip:
      body

proc fieldSections(g: Game): seq[string] =
  sentFieldsOf(g[], "Game", CoreLists):
    result.add toWire(f)

proc fieldSections(p: Player): seq[string] =
  sentFieldsOf(p[], "Player", NoSkip):
    result.add toWire(f)

proc applyFields(sections: seq[string], g: Game) =
  var n = 0
  sentFieldsOf(g[], "Game", CoreLists):
    inc n
  if sections.len != n: wireFail()
  var k = 0
  sentFieldsOf(g[], "Game", CoreLists):
    fromWire(sections[k], f)
    inc k

proc applyFields(sections: seq[string], p: Player) =
  var n = 0
  sentFieldsOf(p[], "Player", NoSkip):
    inc n
  if sections.len != n: wireFail()
  var k = 0
  sentFieldsOf(p[], "Player", NoSkip):
    fromWire(sections[k], f)
    inc k

proc fieldCounts(): tuple[game, player: int] =
  ## How many sections a Game and a Player are (what a snapshot must carry).
  let g = Game()
  sentFieldsOf(g[], "Game", CoreLists):
    inc result.game
  let p = Player()
  sentFieldsOf(p[], "Player", NoSkip):
    inc result.player

let sentFieldCounts = fieldCounts()

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
  result.core = fieldSections(game)
  for p in game.players:
    result.players.add fieldSections(p)
  for e in game.enemies:
    # An enemy's id is the game's own (scripts and links key on it), so a
    # duplicate goes under a key of its own instead.
    var key = int32(e.id)
    if result.index[elEnemies].hasKey(key): key = -nextNetId()
    result.addEntity(elEnemies, key, toWire(e))
  keyed(game.bullets, elBullets, x.netId)
  keyed(game.coins, elCoins, x.netId)
  keyed(game.xpOrbs, elXpOrbs, x.netId)
  if game.state == gs3DBoss and not activeWorld3D.isNil and
     game.game3D == cast[pointer](activeWorld3D):
    result.world3d = toWire(activeWorld3D)

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

proc putSections(s: var string, cur: seq[string], base: ptr seq[string], stats: var SnapStats) =
  putW(s, int32(cur.len))
  for j, x in cur:
    putSection(s, x, (if base.isNil or j >= base[].len: nil else: addr base[][j]), stats)

proc getSections(s: string, i: var int, base: ptr seq[string], expected: int): seq[string] =
  var n: int32
  getW(s, i, n)
  if n != expected: wireFail()   # (another layout, or a malformed snapshot)
  for j in 0 ..< n.int:
    result.add getSection(s, i, (if base.isNil or j >= base[].len: nil else: addr base[][j]))

# ------------------------------------------------------------ encoding ----

proc encodeSnapshot*(cur, base: WireFrame, extras: SnapExtras): string {.moddable.} =
  ## Host: snapshot `cur` for one client, as the change since `base` (nil:
  ## everything), compressed.
  var stats: SnapStats
  var s = ""
  putW(s, cur.seq)
  putW(s, if base.isNil: 0'i32 else: base.seq)
  putW(s, extras)
  putSections(s, cur.core, (if base.isNil: nil else: addr base.core), stats)
  putW(s, int32(cur.players.len))
  for k, p in cur.players:
    let b = if base.isNil or k >= base.players.len: nil else: addr base.players[k]
    putSections(s, p, b, stats)
  putSection(s, cur.world3d, (if base.isNil: nil else: addr base.world3d), stats)
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
  result.core = getSections(s, i, (if base.isNil: nil else: addr base.core), sentFieldCounts.game)
  var nPlayers: int32
  getW(s, i, nPlayers)
  if nPlayers < 0 or nPlayers > MaxCoopPlayers: wireFail()
  for k in 0 ..< nPlayers.int:
    let b = if base.isNil or k >= base.players.len: nil else: addr base.players[k]
    result.players.add getSections(s, i, b, sentFieldCounts.player)
  result.world3d = getSection(s, i, (if base.isNil: nil else: addr base.world3d))
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
    if x.isNil: wireFail()   # (an empty entry: the run's loops would trip on it)
    result.add x

proc isWhole(world: Game3D): bool =
  ## A decoded world this machine can run its frames on: someone in it, and no
  ## empty entry in its lists.
  if world.isNil or world.players.len == 0: return false
  for p in world.players:
    if p.isNil: return false
  for e in world.entities:
    if e.isNil: return false
  for p in world.projectiles:
    if p.isNil: return false
  for p in world.pickups:
    if p.isNil: return false
  true

proc applySnapshot*(frame: WireFrame, game: Game) {.moddable.} =
  ## Client: make the mirror the host's run of `frame` (already read whole).
  ## Decoded into the mirror's own objects, which keep their identity; the
  ## fields each machine keeps for itself (CoopSkipFields) are left alone.
  var players = game.players
  players.setLen(frame.players.len)
  for k in 0 ..< frame.players.len:
    if players[k].isNil: players[k] = Player()
    applyFields(frame.players[k], players[k])
  # Lists first (decodeList reads the old ones), then the core and the players.
  let enemies = decodeList(frame, elEnemies, game.enemies,
                           proc (e: Enemy): int32 {.nimcall.} = int32(e.id))
  let bullets = decodeList(frame, elBullets, game.bullets,
                           proc (b: Bullet): int32 {.nimcall.} = b.netId)
  let coins = decodeList(frame, elCoins, game.coins,
                         proc (c: Coin): int32 {.nimcall.} = c.netId)
  let orbs = decodeList(frame, elXpOrbs, game.xpOrbs,
                        proc (o: XpOrb): int32 {.nimcall.} = o.netId)
  applyFields(frame.core, game)
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
  # The 3D world the run is in, decoded into this machine's copy (made on the
  # way in, dropped on the way out); its camera stays this machine's own.
  let ours = not activeWorld3D.isNil and game.game3D == cast[pointer](activeWorld3D)
  if frame.world3d.len > 0:
    var world = if ours: activeWorld3D else: nil
    let fresh = world.isNil
    fromWire(frame.world3d, world)
    if not world.isWhole:
      # (nobody in it, or a hole in a list: nothing this machine could draw)
      if ours:
        activeWorld3D = nil
        game.game3D = nil
      return
    if fresh and not world.startFired:
      return   # (its first frame hasn't run: the scripts haven't built it or set the view yet)
    world.coop = game.coop
    world.player = world.players[0]
    for p in world.players:
      if p.slot == localSlot: world.player = p
    if fresh:
      # This machine's view starts where the host seated its player looking,
      # and its presses count on from its 2D self's: the host keeps one count
      # per player, and a count that went back to 0 would be no press at all.
      world.camera = initCamera3D(world.player.pos + vec3(0, 2, 0))
      world.camera.yaw = world.player.yaw
      world.camera.pitch = world.player.pitch
      if localSlot >= 0 and localSlot < game.players.len:
        let counts = game.players[localSlot].intent.edges
        world.player.intent.edges = counts
        world.player.intent.seen = counts
      activeWorld3D = world
      game.game3D = cast[pointer](world)
  elif ours:
    activeWorld3D = nil
    game.game3D = nil
