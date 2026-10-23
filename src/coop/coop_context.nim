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

import std/math
import raylib
import types, run_statistics

type CoopRole* = enum
  crNone    ## single player
  crHost    ## simulates the run and sends it to the clients
  crClient  ## draws the host's run and sends its player's input

var
  coopRole*: CoopRole     ## this machine's part in the run on screen
  localSlot*: int32       ## the slot this machine's keyboard/pad drives
  slotRunStats*: array[MaxCoopPlayers, RunStatistics]
    ## Host: each slot's run statistics. withPlayer makes the active slot's the
    ## `currentRunStats` the track* calls write to; all nil in single player.

type
  ProfileEventKind* = enum
    ## Progress a co-op run makes for one player's own profile, which lives on
    ## their own machine (the host applies its own at once; see coop_profile).
    pekMetaBank       ## bank `a` Data Shards and `b` Cores (wave/survival rewards)
    pekRecursion      ## Recursion installed at level `a` (banks its damage)
    pekDiscovered     ## power-up `text` installed: the codex
    pekBossDefeated   ## boss `a` beaten: the codex
    pekUnlock         ## unlock `text`: "tophat", "roguelite" or "survival"
    pekAdvancement    ## advancement `text` earned outright
    pekRogueliteBank  ## roguelite run banks: `a` shards, `b` cores, `c` floor reached,
                      ## `d` rooms cleared, `e` endless loop; `flag`: counts as a run
    pekRogueliteWin   ## roguelite victory: `e` endless loop, `c` heat it was won at

  ProfileEvent* = object
    kind*: ProfileEventKind
    a*, b*, c*, d*, e*: int32
    flag*: bool
    text*: string

const CoopModalTimeout* = 60.0'f32
  ## Seconds a team modal (game.updateCoopModal) waits before it decides for
  ## whoever is still deciding.

var
  coopActionQueue*: seq[tuple[slot: int32, action: CoopAction]]
    ## Host: team-modal actions waiting to be applied (game.updateCoopModal) --
    ## this machine's own, the clients' (coop_session), the bots'.
  coopSendAction*: proc (a: CoopAction) {.nimcall.}
    ## Client: delivers this machine's actions to the host (set by coop_session).
  localRollSeq*: int32 = -1
    ## The draft roll this machine's reel is showing (CoopSeat.rollSeq).
  coopProfileOutbox*: array[MaxCoopPlayers, seq[ProfileEvent]]
    ## Host: progress waiting to reach each client's own profile (coop_session
    ## delivers it reliably).

proc resetCoopContext*() =
  ## Back to single player: no role, slot 0, one player, nothing pending. Every
  ## run that is not co-op starts from here (a stale per-player record would
  ## otherwise take a solo run's statistics).
  coopRole = crNone
  localSlot = 0
  activeSlot = 0
  coopPlayerCount = 1
  for s in slotRunStats.mitems: s = nil
  coopActionQueue.setLen(0)
  for o in coopProfileOutbox.mitems: o.setLen(0)
  localRollSeq = -1

proc coopActive*(): bool {.inline.} = coopRole != crNone
proc coopHost*(): bool {.inline.} = coopRole == crHost
proc coopClient*(): bool {.inline.} = coopRole == crClient

proc submitCoopAction*(kind: CoopActionKind, value: int32 = 0) =
  ## This machine's player acted in a team modal. The host applies it with
  ## everyone else's (updateCoopModal); a client sends it to the host.
  let a = CoopAction(kind: kind, value: value)
  if coopClient():
    if not coopSendAction.isNil: coopSendAction(a)
  else:
    coopActionQueue.add((localSlot, a))

proc pushProfileEvent*(slot: int32, ev: ProfileEvent) =
  ## Host: progress for player `slot`'s own profile, on their machine.
  if slot >= 0 and slot < MaxCoopPlayers:
    coopProfileOutbox[slot].add ev

proc pushTeamProfileEvent*(game: Game, ev: ProfileEvent) =
  ## Host: the same progress for every other player of the run (this
  ## machine's own has already been applied where it was earned).
  if not coopHost(): return
  for p in game.players:
    if p.slot != localSlot:
      pushProfileEvent(p.slot, ev)

proc queueBotAction*(slot: int32, kind: CoopActionKind, value: int32 = 0) =
  ## A bot teammate's action (coop_bot), applied like a player's.
  coopActionQueue.add((slot, CoopAction(kind: kind, value: value)))

proc localSeat*(game: Game): CoopSeat =
  ## This machine's player's part in the team modal (default when none).
  if game.coop.isNil or localSlot < 0 or localSlot >= MaxCoopPlayers: return
  game.coop.seats[localSlot]

proc waitingOnTeam*(game: Game): bool =
  ## A team modal is open and this machine's player is done with it: the
  ## screen waits for the rest of the team.
  not game.coop.isNil and game.coop.modal != cmkNone and game.localSeat.ready

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

proc teamSpawnOffset*(game: Game, p: Player): Vector2 =
  ## Where `p` stands relative to a shared spawn point (a room's door, the
  ## arena centre): side by side in co-op, on the point itself in single player.
  let n = game.players.len
  if n <= 1: return Vector2(x: 0, y: 0)
  Vector2(x: (p.slot.float32 - (n - 1).float32 * 0.5'f32) * 42.0'f32, y: 0)

const
  RetargetEvery = 0.75'f32     ## how long an enemy keeps its quarry before looking again
  BossRetargetEvery = 3.0'f32  ## bosses commit to a player for longer

proc huntedPlayer*(game: Game, enemy: Enemy, dt: float32): Player =
  ## The player `enemy` chases and aims at this frame. It keeps its quarry for
  ## a beat and then takes whoever is nearest, so a crowd splits between the
  ## players instead of flickering between them; a quarry that goes down is
  ## dropped at once. Single player: always the player, and nothing is stored.
  if game.players.len <= 1: return game.player
  enemy.retargetTimer -= dt
  let current = game.playerOfSlot(enemy.targetSlot)
  if current.isUp and enemy.retargetTimer > 0: return current
  result = nearestLivingPlayer(game, enemy.pos.x, enemy.pos.y)
  enemy.targetSlot = result.slot
  enemy.retargetTimer = if enemy.isBoss: BossRetargetEvery else: RetargetEvery

proc currentQuarry*(game: Game, enemy: Enemy): Player =
  ## The player `enemy` is already after (huntedPlayer chose it this frame).
  if game.players.len <= 1: return game.player
  let p = game.playerOfSlot(enemy.targetSlot)
  if p.isUp: p else: nearestLivingPlayer(game, enemy.pos.x, enemy.pos.y)

proc creditedPlayer*(game: Game, enemy: Enemy): Player =
  ## The player whose kill `enemy` is: whoever damaged it last.
  game.playerOfSlot(enemy.lastHitSlot)

proc lastContactWith*(e: Enemy, slot: int32): float32 {.inline.} =
  ## When `e` last hurt player `slot` by touch (each player has their own
  ## cooldown; slot 0's is the enemy's lastContactDamageTime).
  if slot <= 0 or slot >= MaxCoopPlayers: e.lastContactDamageTime
  else: e.coopContactTimes[slot - 1]

proc setLastContactWith*(e: Enemy, slot: int32, t: float32) {.inline.} =
  if slot <= 0 or slot >= MaxCoopPlayers: e.lastContactDamageTime = t
  else: e.coopContactTimes[slot - 1] = t

proc warningQuarry*(game: Game, w: AttackWarning): Player =
  ## The player a warning that follows someone (the Fissure chaser) is after:
  ## the one it was aimed at, or the nearest when they are down.
  if game.players.len <= 1: return game.player
  let p = game.playerOfSlot(w.targetSlot)
  if p.isUp: p else: nearestLivingPlayer(game, w.pos.x, w.pos.y)

proc zoneHit*(w: AttackWarning, slot: int32): bool {.inline.} =
  ## Whether a one-shot hazard zone has already struck player `slot`.
  if slot <= 0: w.lasersCreated   # (the field that has always been slot 0's latch)
  else: (w.coopZoneHits and (1'u8 shl slot)) != 0

proc markZoneHit*(w: AttackWarning, slot: int32) {.inline.} =
  if slot <= 0: w.lasersCreated = true
  else: w.coopZoneHits = w.coopZoneHits or (1'u8 shl slot)

proc ownerSlot*(b: Bullet): int {.inline.} =
  ## The slot of the player who fired `b` (0 for single player and for
  ## anything that predates co-op owners).
  max(0, b.ownerPlayerIndex)

proc bulletContext*(game: Game, b: Bullet): Player =
  ## Whose bullet loop turn `b` takes: a player's shot resolves as its owner
  ## (their build, their kills); an enemy's against the living player whose
  ## edge it is closest to -- the one it homes on and would hit first.
  if game.players.len <= 1: return game.player
  if b.fromPlayer: return game.playerOfSlot(ownerSlot(b))
  var best = float32.high
  for p in game.players:
    if not p.isUp: continue
    let dx = p.pos.x - b.pos.x
    let dy = p.pos.y - b.pos.y
    let edge = sqrt(dx * dx + dy * dy) - p.radius
    if edge < best:
      best = edge
      result = p
  if result.isNil: result = game.player
