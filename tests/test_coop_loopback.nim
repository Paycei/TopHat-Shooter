# Co-op over real loopback UDP (src/coop/coop_session.nim): a host session and
# a client session in one process, each with its own side of the co-op globals
# swapped in around it. The client joins, readies with a kit, mirrors a wave
# run its bot plays from the client side (its input crosses the network and
# drives its player on the host), makes its own team-modal choices, receives
# its profile progress exactly once and in order, and gets its own statistics
# when the run ends. Then it rejoins a second run and leaves mid-run, which
# takes its player out on the host.
#   nim r --mm:orc tests/test_coop_loopback.nim
#   nim r --mm:orc -d:danger tests/test_coop_loopback.nim

import std/[os, random, json]
import ../src/[game, types, settings, run_statistics, input_intent, player, coin, save_system]
import ../src/game/abilities
import ../src/modding/mod_hooks
import ../src/network/network_types
import ../src/coop/[coop_context, coop_bot, coop_codec, coop_session]
from ../src/fx_rand import seedFxRand

let sandboxDir = getTempDir() / ("tophat_loopback_" & $getCurrentProcessId())
putEnv("APPDATA", sandboxDir)
putEnv("HOME", sandboxDir)

const Dt = 1.0'f32 / 60.0'f32
let port = 20000 + getCurrentProcessId() mod 20000

var failures = 0
var passed = 0

proc check(cond: bool, name: string) =
  if cond: inc passed
  else:
    echo "FAIL ", name
    inc failures

# ------------------------------------------------------- the two machines --

type Side = object
  role: CoopRole
  session: CoopSession
  send: proc (a: CoopAction) {.nimcall.}
  inbox: seq[ProfileEvent]

var hostSide = Side(role: crHost)
var clientSide = Side(role: crClient)

template on(side: var Side, body: untyped) =
  ## Run `body` as that machine: its role, seat, session and action sender.
  coopRole = side.role
  activeCoop = side.session
  localSlot = if side.session.isNil: 0'i32 else: side.session.mySlot
  coopSendAction = side.send
  coopProfileInbox = side.inbox
  body
  side.send = coopSendAction
  side.inbox = coopProfileInbox
  if not activeCoop.isNil: side.session = activeCoop

proc pump(host, mirror: Game, frames = 1, wait = false) =
  for _ in 0 ..< frames:
    on(clientSide): pollCoopSession(clientSide.session, mirror, Dt)
    on(hostSide): pollCoopSession(hostSide.session, host, Dt)
    if wait: sleep(1)

proc pumpUntil(host, mirror: Game, cond: proc (): bool, limit = 600): bool =
  for _ in 0 ..< limit:
    if cond(): return true
    pump(host, mirror, wait = true)
  cond()

# --------------------------------------------------------------- the runs --

proc buildHostRun(s: CoopSession): Game =
  ## As main.nim builds the host's run: the mode, then a seat per member.
  result = newGame(1024, 768)
  setGameMode(result, GameMode(s.config.mode))
  initializeRunTracking(result)
  result.state = gsPlaying
  for m in s.members:
    if m.slot != 0: discard addCoopPlayer(result, m.nickname)
  beginCoopRun(result)
  for p in result.players:
    p.maxHp = 400
    p.hp = 400
  s.startRequested = false

proc buildMirror(s: CoopSession): Game =
  ## As main.nim builds a client's: a shell the snapshots fill.
  result = newGame(1024, 768)
  setGameMode(result, GameMode(s.config.mode))
  for m in s.members:
    if m.slot != 0: discard addCoopPlayer(result, m.nickname)
  result.player = result.players[s.mySlot]
  s.startRequested = false

proc hostFrame(g: var Game, frame: int) =
  ## The host's frame: its own bot (slot 0 only: slot 1 plays over the
  ## network), the team modal, then the simulation as main.nim steps it.
  let coop = g.coop
  if not coop.isNil and coop.modal != cmkNone and not coop.seats[0].ready and
     coop.modalTimer < CoopModalTimeout - 0.5'f32:
    case coop.modal
    of cmkDraft: queueBotAction(g, 0, cakPick, 0)
    of cmkShop, cmkCache: queueBotAction(g, 0, cakDone)
    of cmkFloorVote: queueBotAction(g, 0, cakVote, 0)
    of cmkNone: discard
  updateCoopModal(g, Dt)
  case g.state
  of gsPlaying:
    botIntent(g, g.players[0], frame)
    for p in g.livingPlayers:
      withPlayer(g, p):
        if consumeEdge(g.player, ieAbility) and not modAbility(g):
          activateLegendaries(g)
    updateGame(g, Dt)
  of gsDeathSequence:
    updateGame(g, Dt)
  of gsWaveCleared:
    g.waveClearedTimer -= Dt
    discard updateGameCoins(g, Dt)
    if g.waveClearedTimer <= 0:
      g.state = gsPlaying
      startWave(g)
  of gsCountdown:
    g.countdownTimer -= Dt
    if g.countdownTimer <= 0: g.state = gsPlaying
  else: discard

proc clientFrame(mirror: Game, frame: int) =
  ## The client's frame: its bot's input for its own player, and its own
  ## choices in a team modal (the UI submits once; a bot repeats itself, which
  ## the host must shrug off).
  if mirror.players.len <= localSlot: return
  botIntent(mirror, mirror.players[localSlot], frame)
  let coop = mirror.coop
  if not coop.isNil and coop.modal != cmkNone and not coop.seats[localSlot].ready and
     frame mod 20 == 0:
    case coop.modal
    of cmkDraft: submitCoopAction(mirror, cakPick, 2)
    of cmkShop, cmkCache: submitCoopAction(mirror, cakDone)
    of cmkFloorVote: submitCoopAction(mirror, cakVote, 0)
    of cmkNone: discard

globalSettings = newDefaultSettings()
randomize(77)
seedFxRand(3)

var host, mirror: Game

# ------------------------------------------------------------- the lobby --

on(hostSide):
  hostSide.session = hostCoop(port, 4, CoopMemberNet(nickname: "Host"),
                              CoopRunConfigNet(mode: int32(ord(gmWaveBased))))
on(clientSide):
  clientSide.session = joinCoop("127.0.0.1", port, CoopMemberNet(nickname: "Guest"))
let hs = hostSide.session
let cs = clientSide.session

check(pumpUntil(host, mirror, proc (): bool = cs.phase == cpClientLobby and hs.members.len == 2),
      "the client is seated in the host's lobby")
check(cs.mySlot == 1, "the client has seat 1")
check(pumpUntil(host, mirror, proc (): bool = cs.members.len == 2),
      "the client sees the lobby: both seats")
on(clientSide): cs.setReady(true, 2)
check(pumpUntil(host, mirror, proc (): bool = hs.readyToStart),
      "the host sees the client ready")
check(hs.members[1].starterKit == 2, "the client's starter kit reached the host")

# --------------------------------------------------------- the first run --

on(hostSide):
  hs.startCoopRun()
  check(hs.startRequested, "starting asks main.nim to build the run")
  coopRole = crHost
  host = buildHostRun(hs)
check(pumpUntil(host, mirror, proc (): bool = cs.startRequested),
      "the client is told the run started")
on(clientSide):
  mirror = buildMirror(cs)
check(pumpUntil(host, mirror, proc (): bool = cs.lastApplied > 0),
      "the client mirrors its first snapshot")

var p1Start = host.players[1].pos
var p1Moved = false
var modalOpenedAt = -1
var modalSlowest = 0
var modalsDone = 0
var profileSent = 0
for f in 0 ..< 3600:
  on(clientSide):
    clientFrame(mirror, f)
    pollCoopSession(cs, mirror, Dt)
  on(hostSide):
    pollCoopSession(hs, host, Dt)
    let before = if host.coop.isNil: cmkNone else: host.coop.modal
    hostFrame(host, f)
    let after = host.coop.modal
    if before == cmkNone and after != cmkNone: modalOpenedAt = f
    if before != cmkNone and after == cmkNone and modalOpenedAt >= 0:
      inc modalsDone
      modalSlowest = max(modalSlowest, f - modalOpenedAt)
    # Progress for the client's profile, now and then.
    if f mod 400 == 100:
      inc profileSent
      pushProfileEvent(1, ProfileEvent(kind: pekMetaBank, a: int32(profileSent), b: -7))
  if host.players[1].pos.x != p1Start.x or host.players[1].pos.y != p1Start.y: p1Moved = true
  if host.state in {gsGameOver, gsVictory}: break

echo "run 1: wave=", host.currentWave, " state=", host.state, " modals=", modalsDone,
     " slowest=", modalSlowest, " frames; p1 kills=", host.players[1].kills,
     " pu=", host.players[1].powerUps.len, "; snapshot bytes/s=", hs.bytesPerSecond
check(p1Moved, "the client's input moves its player on the host")
check(host.players[1].kills > 0, "the client's player scores kills on the host")
check(modalsDone > 0, "team modals open and close")
check(modalSlowest < 10 * 60, "every team modal closed on both players' choices, not the timeout")

# Quiet: the mirror catches up and holds exactly the host's run.
for _ in 0 ..< 30: pump(host, mirror, wait = true)
var want, got: WireFrame
on(hostSide): want = captureFrame(host, 999_999)
on(clientSide): got = captureFrame(mirror, 999_999)
check(got.core == want.core and got.players == want.players,
      "at rest the mirror holds exactly the host's run")
check(mirror.player == mirror.players[1], "the mirror's player is the client's seat")
proc marked(): seq[int32] =
  ## The test's own events (the run sends the client its codex progress too).
  for ev in clientSide.inbox:
    if ev.kind == pekMetaBank and ev.b == -7: result.add ev.a
check(marked().len == profileSent, "every profile event arrived once (" &
      $marked().len & "/" & $profileSent & ")")
var inOrder = true
for k, a in marked():
  if a != int32(k + 1): inOrder = false
check(inOrder, "profile events arrive in order")

# The end: the last progress first, then the client's own statistics.
on(hostSide):
  pushProfileEvent(1, ProfileEvent(kind: pekMetaBank, a: int32(profileSent + 1), b: -7))
  hs.endCoopRun(cerWiped)
check(pumpUntil(host, mirror, proc (): bool = cs.ended), "the client learns the run ended")
check(cs.endReason == cerWiped, "with the reason")
check(marked().len == profileSent + 1, "the progress banked as it ended arrived first")
var stats: RunStatistics
try:
  stats = jsonToRunStatistics(parseJson(cs.endStats))
except CatchableError:
  stats = nil
check(not stats.isNil, "the client receives its own run statistics")
check(pumpUntil(host, mirror, proc (): bool = hs.phase == cpEnded), "the host's run is ended")

# ------------------------------------------- a second run, left midway --

on(hostSide): hs.backToLobby()
on(clientSide): cs.backToLobby()
check(pumpUntil(host, mirror, proc (): bool = cs.phase == cpClientLobby and not hs.readyToStart),
      "both are back in the lobby, the client not ready")
on(clientSide): cs.setReady(true, 0)
check(pumpUntil(host, mirror, proc (): bool = hs.readyToStart), "ready for the second run")
on(hostSide):
  hs.startCoopRun()
  host = buildHostRun(hs)
check(pumpUntil(host, mirror, proc (): bool = cs.startRequested), "the second run starts")
on(clientSide): mirror = buildMirror(cs)
check(pumpUntil(host, mirror, proc (): bool = cs.lastApplied > 0), "and is mirrored")
on(clientSide):
  cs.closeCoop()
  clientSide.session = nil
check(pumpUntil(host, mirror, proc (): bool = host.players[1].eliminated),
      "a client leaving takes its player out of the run")
check(not hs.members[1].connected, "its seat shows it left")

on(hostSide): hs.closeCoop()
removeDir(sandboxDir)
echo passed, " passed, ", failures, " failed"
if failures > 0: quit 1
