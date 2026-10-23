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
## Positions are only drawn from: a client never simulates, and the snapshots
## are decoded from bytes, never from these objects, so writing them is safe.
## The state here is keyed by object identity, which the decoder keeps for an
## entity while it lives; it is rebuilt from the run's lists each snapshot.

import std/[tables, math]
import raylib
import ../modding/mod_patch_core
import ../types, ../vec, ../player, ../input_intent
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

var
  tracks: Table[pointer, Track]
  shown: Table[pointer, Vector2]   # positions on screen as a snapshot lands
  history: seq[LocalStep]
  predicting: bool                 # this player's movement is being predicted
  shownLocal: Vector2
  shownWarp: int32
  correction: Vector2

proc resetCoopSmoothing*() =
  ## A new run (or none): nothing carried over.
  tracks.clear()
  shown.clear()
  history.setLen(0)
  predicting = false
  correction = Vector2()

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

proc stepLocal(me: Player, st: LocalStep, w, h: int32, walls: seq[Wall]) =
  ## One frame of this player's movement, as updatePlayer runs it.
  if me.dashCooldown > 0: me.dashCooldown = max(0'f32, me.dashCooldown - st.dt)
  if me.dashTimer > 0: me.dashTimer = max(0'f32, me.dashTimer - st.dt)
  let held = me.intent.move
  me.intent.move = st.move
  steerPlayer(me, st.dt, st.dashNow)
  advancePlayer(me, st.dt, w, h, walls)
  me.intent.move = held

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
