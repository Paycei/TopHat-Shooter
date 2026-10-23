## The active-player context: how one simulation runs several players.
##
## The gameplay code reads `game.player` everywhere (over a thousand places).
## Rather than thread a player through all of them, `game.player` means "the
## player being processed right now": withPlayer points it at one of
## `game.players` for a block and puts it back after. The per-player systems
## (movement, firing, auras, abilities) run once per player inside it; an
## enemy runs its AI and attacks with its target active; a bullet resolves its
## hits with its owner active, so on-hit power-ups use the shooter's build.
##
## A single-player run is `players = @[player]`, so every swap is a no-op and
## nothing here changes how it plays.
##
## This module sits low (types and run_statistics only): the game/ subsystems
## import it. It must never import game.nim.

import types, run_statistics

type CoopRole* = enum
  crNone    ## single player
  crHost    ## simulates the run and sends it to the clients
  crClient  ## draws the host's run and sends its player's input

var
  coopRole*: CoopRole     ## this machine's part in the run on screen
  localSlot*: int32       ## the slot this machine's keyboard/pad drives
  activeSlot*: int32      ## the slot being simulated or drawn right now
  slotRunStats*: array[MaxCoopPlayers, RunStatistics]
    ## Host: each slot's run statistics. withPlayer makes the active slot's the
    ## `currentRunStats` the track* calls write to; all nil in single player.

proc coopActive*(): bool {.inline.} = coopRole != crNone
proc coopHost*(): bool {.inline.} = coopRole == crHost
proc coopClient*(): bool {.inline.} = coopRole == crClient

proc isLocalPlayer*(p: Player): bool {.inline.} =
  ## Driven by this machine's devices (and drawn with its crosshair).
  p.slot == localSlot

proc isUp*(p: Player): bool {.inline.} =
  ## In the fight: not waiting out a respawn, not eliminated. Always true in
  ## single player, whose death is the run's death (gsDeathSequence).
  not p.eliminated and p.downTimer <= 0

template withPlayer*(game: Game, p: Player, body: untyped) =
  ## Run `body` with `p` as the active player (game.player, its slot, its run
  ## statistics), then restore the previous one, even if `body` raises.
  let ctxSavedPlayer = game.player
  let ctxSavedSlot = activeSlot
  let ctxSavedStats = currentRunStats
  let ctxPlayer = p
  game.player = ctxPlayer
  activeSlot = ctxPlayer.slot
  if not slotRunStats[ctxPlayer.slot].isNil:
    currentRunStats = slotRunStats[ctxPlayer.slot]
  try:
    body
  finally:
    game.player = ctxSavedPlayer
    activeSlot = ctxSavedSlot
    currentRunStats = ctxSavedStats

iterator livingPlayers*(game: Game): Player =
  ## The players in the fight (see isUp). A copy of the list is walked, so a
  ## body that changes it can't skip or repeat anyone.
  let ps = game.players
  for p in ps:
    if p.isUp: yield p

proc livingCount*(game: Game): int =
  for p in game.players:
    if p.isUp: inc result

proc playerOfSlot*(game: Game, slot: int): Player =
  ## The player in `slot`, or the active player when there is none.
  if slot >= 0 and slot < game.players.len: game.players[slot] else: game.player

proc nearestLivingPlayer*(game: Game, x, y: float32): Player =
  ## The living player closest to (x, y); with nobody up, the active player.
  ## In single player always that one player.
  if game.players.len <= 1: return game.player
  var best = float32.high
  for p in game.players:
    if not p.isUp: continue
    let dx = p.pos.x - x
    let dy = p.pos.y - y
    let d = dx * dx + dy * dy
    if d < best:
      best = d
      result = p
  if result.isNil: result = game.player

proc ownerSlot*(b: Bullet): int {.inline.} =
  ## The slot of the player who fired `b` (0 for single player and for
  ## anything that predates co-op owners).
  max(0, b.ownerPlayerIndex)
