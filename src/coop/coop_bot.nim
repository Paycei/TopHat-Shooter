## A stand-in co-op teammate: fills a player's intent from the game state, so
## the multi-player simulation can be played and tested on one machine with no
## network (debug builds: `--coop-bot`; the headless tests). It keeps its
## distance from the nearest enemy, aims at it and holds fire, dashes and uses
## [Q] on a beat. It draws no random numbers, so it never shifts the run's
## gameplay rolls.

import std/math
import raylib
import ../types, ../input_intent

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
  if not nearest.isNil and best < 220.0'f32 * 220.0'f32:
    move = Vector2(x: p.pos.x - nearest.pos.x, y: p.pos.y - nearest.pos.y)
  else:
    # Wander on a slow, slot-shifted circle so two bots don't stack.
    let a = float32(frame div 45) * 1.7'f32 + float32(p.slot) * 2.1'f32
    move = Vector2(x: cos(a), y: sin(a))
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
