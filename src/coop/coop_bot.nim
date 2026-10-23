## A stand-in co-op teammate: fills a player's intent from the game state, so
## the multi-player simulation can be played and tested on one machine with no
## network (debug builds: `--coop-bot`; the headless tests). It keeps its
## distance from the nearest enemy, aims at it and holds fire, dashes and uses
## [Q] on a beat; in a quiet roguelite room it takes a pedestal's patch and
## heads for the door or the exit portal (dungeon's roomGoal). It draws no
## random numbers, so it never shifts the run's gameplay rolls.

import std/math
import raylib
import ../types, ../input_intent, ../dungeon, coop_context
import ../game3d/[types_3d, player_3d]

proc queueBotModalActions*(game: Game, frame: int, includeLocal = false, onlyLocal = false) =
  ## The bots' choices in the open team modal, after a short think: a card,
  ## one purchase (if they can afford it) and done, the reveal closed, the
  ## first floor. `includeLocal`: this machine's player is a bot too (tests);
  ## `onlyLocal`: only it is (an automated co-op session, --coop-auto).
  let coop = game.coop
  if coop.isNil or coop.modal == cmkNone: return
  if coop.modalTimer > CoopModalTimeout - 0.8'f32: return
  for p in game.players:
    if p.isLocalPlayer and not includeLocal: continue
    if onlyLocal and not p.isLocalPlayer: continue
    if coop.seats[p.slot].ready: continue
    case coop.modal
    of cmkDraft: queueBotAction(game, p.slot, cakPick, int32((frame + p.slot.int) mod 3))
    of cmkShop:
      queueBotAction(game, p.slot, cakBuy, 0)
      queueBotAction(game, p.slot, cakDone)
    of cmkCache: queueBotAction(game, p.slot, cakDone)
    of cmkFloorVote: queueBotAction(game, p.slot, cakVote, 0)
    of cmkNone: discard

proc botIntent*(game: Game, p: Player, frame: int) =
  ## This frame's intent for bot-driven player `p`.
  var it = p.intent
  beginIntentFrame(it)
  var nearest: Enemy = nil
  var best = float32.high
  for e in game.enemies:
    let dx = e.pos.x - p.pos.x
    let dy = e.pos.y - p.pos.y
    let d = dx * dx + dy * dy
    if d < best:
      best = d
      nearest = e
  var move = Vector2(x: 0, y: 0)
  let goal = if game.mode == gmRoguelite: roomGoal(game) else: RoomGoal()
  if goal.kind != rgNone:
    move = Vector2(x: goal.pos.x - p.pos.x, y: goal.pos.y - p.pos.y)
    if goal.kind == rgInteract and move.x * move.x + move.y * move.y < InteractRadius * InteractRadius and
       frame mod 20 == 0:
      pressEdge(it, ieInteract)
  elif not nearest.isNil and best < 220.0'f32 * 220.0'f32:
    move = Vector2(x: p.pos.x - nearest.pos.x, y: p.pos.y - nearest.pos.y)
  else:
    # Wander on a slow, slot-shifted circle so two bots don't stack.
    let a = float32(frame div 45) * 1.7'f32 + float32(p.slot) * 2.1'f32
    move = Vector2(x: cos(a), y: sin(a))
  if goal.kind == rgNone:
    # Drift back toward the centre near the edges.
    move.x += (game.screenWidth.float32 * 0.5'f32 - p.pos.x) / 400.0'f32
    move.y += (game.screenHeight.float32 * 0.5'f32 - p.pos.y) / 300.0'f32
  let len = sqrt(move.x * move.x + move.y * move.y)
  it.move = if len > 0.001'f32: Vector2(x: move.x / len, y: move.y / len) else: move
  it.aim = if nearest.isNil:
             Vector2(x: game.screenWidth.float32 * 0.5'f32, y: game.screenHeight.float32 * 0.4'f32)
           else: nearest.pos
  it.aimByDir = false
  it.fireHeld = not nearest.isNil
  it.fireKey = false
  it.wallHeld = false
  let beat = frame + int(p.slot) * 37
  if beat mod 97 == 0: pressEdge(it, ieDash)
  if beat mod 300 == 150: pressEdge(it, ieAbility)
  p.intent = it

proc botIntent3D*(world: Game3D, p: Player3D, frame: int) =
  ## A bot's intent in a 3D world: keep to the middle of the arena (the boss
  ## world's jump pad), aim at the boss -- its nearest satellite while any
  ## shield it -- or the nearest entity, pull the trigger, jump now and then.
  if world.isNil or p.isNil: return
  var it = p.intent
  beginIntentFrame(it)
  var target: Vector3
  var best = 1.0e30'f32
  if world.bossEnabled and world.boss.health > 0:
    target = world.boss.pos
    best = 0
    var satBest = 1.0e30'f32
    for sat in world.boss.satellites:
      if sat.active and distance(p.pos, sat.pos) < satBest:
        satBest = distance(p.pos, sat.pos)
        target = sat.pos
  for e in world.entities:
    if e.alive and distance(p.pos, e.pos) < best:
      best = distance(p.pos, e.pos)
      target = e.pos
  let has = best < 1.0e30'f32
  if has:
    let d = target - (p.pos + vec3(0, 2, 0))
    let flat = sqrt(d.x * d.x + d.z * d.z)
    it.aim = Vector2(x: radToDeg(arctan2(d.z, d.x)), y: radToDeg(arctan2(d.y, max(flat, 0.001'f32))))
  let side = if (frame div 150 + int(p.slot)) mod 2 == 0: 1'f32 else: -1'f32
  # Strafe a little, and head back to the middle when off it (facing it).
  let reach = sqrt(p.pos.x * p.pos.x + p.pos.z * p.pos.z)
  if reach > 12:
    it.move = Vector2(x: 0, y: 1)
    it.aim.x = radToDeg(arctan2(-p.pos.z, -p.pos.x))
  else:
    it.move = Vector2(x: side * 0.5'f32, y: 0)
  it.fireHeld = has
  it.wallHeld = false
  if has and frame mod 9 == 0: pressEdge(it, Edge3DTrigger)
  if (frame + int(p.slot) * 37) mod 240 == 0: pressEdge(it, Edge3DJump)
  p.intent = it
