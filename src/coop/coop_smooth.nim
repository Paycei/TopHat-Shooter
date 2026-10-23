## Co-op client: motion between the host's snapshots.
##
## Snapshots come about 30 times a second, and a client draws at its own frame
## rate, so drawing each one as it lands would move everything in steps -- and
## this player's own movement would answer their keys only once the host had
## seen them and sent the result back. Two things fill the gap:
##
## * Everything else -- enemies, bullets, coins, orbs, teammates -- carries on
##   from its last snapshot at its velocity (a bullet's or a player's own, the
##   others' measured between snapshots), for a tenth of a second at most. Where
##   a new snapshot disagrees with what is on screen, the difference is bled out
##   over a few frames instead of jumped; a move too long to be one (a spawn, a
##   teleport) is jumped.
## * This player moves at once: each frame runs the same steering and movement
##   the host runs (player.steerPlayer / advancePlayer) on their own intent.
##   When a snapshot arrives, the host's position is taken and the inputs it
##   had not processed yet are played over it again; what is left of the
##   difference is bled out, or jumped when the host moved them (Player.warp)
##   or it is too large.
##
## A 3D world (gs3DBoss) is treated alike: this player's movement runs the
## world's own player_3d.updatePlayer, their teammates and the world's
## entities carry on at their velocity, and shots fly on from where the last
## snapshot saw them.
##
## Positions are only drawn from: a client never simulates, and the snapshots
## are decoded from bytes, never from these objects, so writing them is safe.
## The state here is keyed by object identity, which the decoder keeps for an
## entity while it lives; it is rebuilt from the run's lists each snapshot.

import std/[tables, math]
import raylib
import ../modding/mod_patch_core
import ../types, ../vec, ../player, ../input_intent
import ../game3d/[types_3d, player_3d, game_3d]
import coop_context

const
  MaxCarry = 0.1'f32        ## seconds a position is carried past its snapshot
  JumpDistance = 140'f32    ## farther between two snapshots: a jump, not a move
  MaxSpeed = 2500'f32       ## a measured velocity at most, px/s
  BleedRate = 14'f32        ## how fast a correction is bled out (1/s)
  LocalJump = 160'f32       ## this player's prediction this far off: jumped
  MaxHistory = 240          ## frames of this player's input kept for replay

type
  Track = object
    auth: Vector2    ## where the last snapshot put it
    vel: Vector2     ## px/s
    offset: Vector2  ## on screen minus `auth`, bled out
    stamp: float32   ## the run's clock at that snapshot

  LocalStep = object
    seq: int32       ## the input packet that carries this frame's intent
    dt: float32
    move: Vector2
    dashNow: bool

  LocalStep3D = object
    seq: int32
    dt: float32
    move, aim: Vector2
    sprint, jump: bool

  Track3D = object
    auth: Vector3    ## where the last snapshot put it
    offset: Vector3  ## on screen minus `auth`, bled out

var
  tracks: Table[pointer, Track]
  shown: Table[pointer, Vector2]   # positions on screen as a snapshot lands
  history: seq[LocalStep]
  predicting: bool                 # this player's movement is being predicted
  shownLocal: Vector2
  shownWarp: int32
  correction: Vector2
  # 3D
  history3D: seq[LocalStep3D]
  predicting3D: bool
  shown3D: Vector3
  correction3D: Vector3
  shownEntities3D: Table[int, Vector3]     # by entity id
  shownTeam3D: array[MaxCoopPlayers, tuple[seen: bool, pos: Vector3]]
  entityTracks3D: seq[Track3D]             # by index into world.entities
  teamTracks3D: array[MaxCoopPlayers, Track3D]
  shotAuth3D: seq[Vector3]                 # by index into world.projectiles

const
  JumpDistance3D = 40'f32   ## a 3D move longer than this between snapshots is a jump
  LocalJump3D = 30'f32      ## this player's 3D prediction this far off: jumped

proc resetCoopSmoothing*() =
  ## A new run (or none): nothing carried over.
  tracks.clear()
  shown.clear()
  history.setLen(0)
  predicting = false
  correction = Vector2()
  history3D.setLen(0)
  predicting3D = false
  correction3D = Vector3()
  shownEntities3D.clear()
  entityTracks3D.setLen(0)
  shotAuth3D.setLen(0)

proc ownWorld(game: Game): Game3D =
  ## The 3D world this run is in on this machine (nil when none).
  if not activeWorld3D.isNil and game.game3D == cast[pointer](activeWorld3D): activeWorld3D
  else: nil

proc key[T: ref](x: T): pointer {.inline.} = cast[pointer](x)

proc localPlayer(game: Game): Player =
  if localSlot >= 0 and localSlot < game.players.len: game.players[localSlot] else: nil

proc liveState(game: Game): bool =
  ## The host is moving the players (not a countdown, a room's fade or a
  ## team modal).
  game.state in {gsPlaying, gsWaveCleared} and not game.roomTransitionActive and
    (game.coop.isNil or game.coop.modal == cmkNone)

template eachSmoothed(game: Game, body: untyped) =
  ## Every entity drawn smoothed (`it`, `ownVel`: its own velocity, or none to
  ## measure one). This player is predicted instead.
  block:
    const ownVel {.inject.} = false
    for it {.inject.} in game.enemies: body
    for it {.inject.} in game.coins: body
    for it {.inject.} in game.xpOrbs: body
  block:
    const ownVel {.inject.} = true
    for it {.inject.} in game.bullets: body
    for it {.inject.} in game.players:
      if it.slot != localSlot: body

proc beforeSnapshot*(game: Game) {.moddable.} =
  ## Client, a snapshot about to be applied: note what is on screen.
  if game.isNil: return
  shown.clear()
  eachSmoothed(game):
    shown[key(it)] = it.pos
  let me = game.localPlayer
  if not me.isNil:
    shownLocal = me.pos
    shownWarp = me.warp
  let world = game.ownWorld
  if not world.isNil:
    shownEntities3D.clear()
    for e in world.entities: shownEntities3D[e.id] = e.pos
    for x in shownTeam3D.mitems: x.seen = false
    for p in world.players:
      if p.slot >= 0 and p.slot < MaxCoopPlayers: shownTeam3D[p.slot] = (true, p.pos)
    let me3 = world.localPlayer3D()
    if not me3.isNil: shown3D = me3.pos

proc stepLocal(me: Player, st: LocalStep, w, h: int32, walls: seq[Wall]) =
  ## One frame of this player's movement, as updatePlayer runs it.
  if me.dashCooldown > 0: me.dashCooldown = max(0'f32, me.dashCooldown - st.dt)
  if me.dashTimer > 0: me.dashTimer = max(0'f32, me.dashTimer - st.dt)
  let held = me.intent.move
  me.intent.move = st.move
  steerPlayer(me, st.dt, st.dashNow)
  advancePlayer(me, st.dt, w, h, walls)
  me.intent.move = held

proc stepLocal3D(world: Game3D, me: Player3D, st: LocalStep3D) =
  ## One frame of this player's 3D movement, as the world's frame runs it.
  let held = me.intent
  me.intent.move = st.move
  me.intent.aim = st.aim
  me.intent.wallHeld = st.sprint
  if st.jump: me.intent.edges[Edge3DJump] = me.intent.seen[Edge3DJump] + 1
  applyAim3D(me)
  discard updatePlayer(me, world.arena, st.dt)
  me.intent = held

proc afterSnapshot3D(world: Game3D, intentAck: int32) =
  ## A snapshot's world just decoded: the tracks from here, and this player
  ## put back ahead of the host.
  entityTracks3D.setLen(world.entities.len)
  for k, e in world.entities:
    var t = Track3D(auth: e.pos)
    if shownEntities3D.hasKey(e.id):
      let off = shownEntities3D[e.id] - e.pos
      if length(off) < JumpDistance3D: t.offset = off
    entityTracks3D[k] = t
  for p in world.players:
    if p.slot < 0 or p.slot >= MaxCoopPlayers: continue
    var t = Track3D(auth: p.pos)
    let was = shownTeam3D[p.slot]
    if was.seen and length(was.pos - p.pos) < JumpDistance3D: t.offset = was.pos - p.pos
    teamTracks3D[p.slot] = t
  shotAuth3D.setLen(world.projectiles.len)
  for k, s in world.projectiles: shotAuth3D[k] = s.pos

  let me = world.localPlayer3D()
  if me.isNil or not predicting3D or not me.isUp3D or not world.active:
    history3D.setLen(0)
    predicting3D = false
    correction3D = Vector3()
    return
  var keep: seq[LocalStep3D]
  for st in history3D:
    if st.seq > intentAck: keep.add st
  history3D = keep
  for st in history3D: stepLocal3D(world, me, st)
  let off = me.pos - shown3D
  if length(off) > LocalJump3D:
    correction3D = Vector3()
  else:
    me.pos = shown3D
    correction3D = off

proc predictLocal3D*(game: Game, dt: float32, seq: int32) {.moddable.} =
  ## Client, every frame in a 3D world: move this player at once on their own
  ## intent (just captured; `seq` is the input packet that will carry it).
  let world = game.ownWorld
  let me = if world.isNil: nil else: world.localPlayer3D()
  if me.isNil or not me.isUp3D or not world.active or dt <= 0:
    history3D.setLen(0)
    predicting3D = false
    correction3D = Vector3()
    return
  let st = LocalStep3D(seq: seq, dt: min(dt, 0.05'f32), move: me.intent.move, aim: me.intent.aim,
                       sprint: me.intent.wallHeld, jump: me.take3D(Edge3DJump))
  stepLocal3D(world, me, st)
  history3D.add st
  if history3D.len > MaxHistory: history3D.delete(0)
  predicting3D = true
  let bleed = correction3D * (1'f32 - exp(-BleedRate * dt))
  me.pos = me.pos + bleed
  correction3D = correction3D - bleed

proc smoothFrame3D*(game: Game, dt, age: float32) {.moddable.} =
  ## Client, every frame in a 3D world: where its teammates, entities and
  ## shots are drawn, `age` seconds after the last snapshot.
  let world = game.ownWorld
  if world.isNil: return
  let carry = clamp(age, 0'f32, MaxCarry)
  let keepShare = exp(-BleedRate * max(dt, 0'f32))
  if entityTracks3D.len == world.entities.len:
    for k, e in world.entities:
      let t = addr entityTracks3D[k]
      t.offset = t.offset * keepShare
      e.pos = t.auth + e.vel * carry + t.offset
  for p in world.players:
    if p.slot == localSlot or p.slot < 0 or p.slot >= MaxCoopPlayers: continue
    let t = addr teamTracks3D[p.slot]
    t.offset = t.offset * keepShare
    p.pos = t.auth + vec3(p.vel.x, 0, p.vel.z) * carry + t.offset
  if shotAuth3D.len == world.projectiles.len:
    for k, s in world.projectiles:
      s.pos = shotAuth3D[k] + s.vel * carry

proc afterSnapshot*(game: Game, intentAck: int32) {.moddable.} =
  ## Client, a snapshot just applied (the mirror holds the host's run): track
  ## each entity from here, and put this player back ahead of the host.
  if game.isNil: return
  let now = game.time
  var next = initTable[pointer, Track](tracks.len * 2 + 16)
  eachSmoothed(game):
    let k = key(it)
    var t = Track(auth: it.pos, stamp: now)
    let had = tracks.hasKey(k)
    let old = if had: tracks[k] else: Track()
    let moved = if had: it.pos - old.auth else: Vector2()
    let jumped = had and length(moved) > JumpDistance
    when ownVel:
      t.vel = it.vel
    else:
      if had and not jumped and now > old.stamp:
        t.vel = moved * (1'f32 / (now - old.stamp))
    if length(t.vel) > MaxSpeed or t.vel.x.isNaN or t.vel.y.isNaN:
      t.vel = Vector2()
    if shown.hasKey(k):
      let off = shown[k] - it.pos
      if length(off) < JumpDistance and not jumped: t.offset = off
    next[k] = t
  tracks = next
  shown.clear()
  let world = game.ownWorld
  if not world.isNil: afterSnapshot3D(world, intentAck)

  # This player: the host's position, then the inputs it has not seen yet.
  let me = game.localPlayer
  if me.isNil or not predicting or not me.isUp or not game.liveState:
    history.setLen(0)
    predicting = false
    correction = Vector2()
    return
  var keep: seq[LocalStep]
  for st in history:
    if st.seq > intentAck: keep.add st
  history = keep
  for st in history:
    stepLocal(me, st, game.screenWidth.int32, game.screenHeight.int32, game.walls)
  let off = me.pos - shownLocal
  if me.warp != shownWarp or length(off) > LocalJump:
    correction = Vector2()      # moved by the host, or too far off: jump
  else:
    me.pos = shownLocal         # stay put on screen and close the gap smoothly
    correction = off

proc predictLocal*(game: Game, dt: float32, seq: int32) {.moddable.} =
  ## Client, every frame of a live run: move this player on their own intent
  ## (just captured; `seq` is the input packet that will carry it).
  let me = game.localPlayer
  if me.isNil or not me.isUp or not game.liveState or dt <= 0:
    history.setLen(0)
    predicting = false
    correction = Vector2()
    return
  let dashNow = me.dashCooldown <= 0 and me.dashTimer <= 0 and consumeEdge(me, ieDash)
  let st = LocalStep(seq: seq, dt: min(dt, 0.05'f32), move: me.intent.move, dashNow: dashNow)
  stepLocal(me, st, game.screenWidth.int32, game.screenHeight.int32, game.walls)
  history.add st
  if history.len > MaxHistory: history.delete(0)
  predicting = true
  let bleed = correction * (1'f32 - exp(-BleedRate * dt))
  me.pos = me.pos + bleed
  correction = correction - bleed

proc smoothFrame*(game: Game, dt, age: float32) {.moddable.} =
  ## Client, every frame of a live run: where everything else is drawn,
  ## `age` seconds after the last snapshot.
  if game.isNil or tracks.len == 0: return
  let carry = clamp(age, 0'f32, MaxCarry)
  let keepShare = exp(-BleedRate * max(dt, 0'f32))
  eachSmoothed(game):
    let k = key(it)
    if tracks.hasKey(k):
      let t = addr tracks[k]
      t.offset = t.offset * keepShare
      it.pos = t.auth + t.vel * carry + t.offset
