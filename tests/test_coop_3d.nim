# Co-op in a 3D world (game3d/), over real loopback UDP: a host and a client in
# one process (each with its own side of the co-op globals, the world included),
# both played by the 3D bot. The pair enters the Orbital Commander's world from
# a sandbox run; the client mirrors it, plays its own player there (its input
# crosses the network; its movement is predicted), both players hurt the boss,
# a down spends a team life and comes back, and leaving the world hands each
# player's health back to their 2D self.
#   nim r --mm:orc tests/test_coop_3d.nim
#   nim r --mm:orc -d:danger tests/test_coop_3d.nim

import std/[os, random, math, strutils]
import raylib
import ../src/[game, types, settings, run_statistics, input_intent, vec]
import ../src/game3d/[types_3d, game_3d]
import ../src/network/network_types
import ../src/coop/[coop_context, coop_bot, coop_session, coop_present, coop_smooth]
from ../src/fx_rand import seedFxRand

let sandboxDir = getTempDir() / ("tophat_coop3d_" & $getCurrentProcessId())
putEnv("APPDATA", sandboxDir)
putEnv("HOME", sandboxDir)

const Dt = 1.0'f32 / 60.0'f32
let port = 20000 + (getCurrentProcessId() + 7) mod 20000

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
  world: Game3D

var hostSide = Side(role: crHost)
var clientSide = Side(role: crClient)

template on(side: var Side, body: untyped) =
  ## Run `body` as that machine: its role, seat, session, sender and 3D world.
  coopRole = side.role
  activeCoop = side.session
  localSlot = if side.session.isNil: 0'i32 else: side.session.mySlot
  coopSendAction = side.send
  coopProfileInbox = side.inbox
  activeWorld3D = side.world
  block:
    body
  side.send = coopSendAction
  side.inbox = coopProfileInbox
  side.world = activeWorld3D
  if not activeCoop.isNil: side.session = activeCoop

proc pumpUntil(host, mirror: Game, cond: proc (): bool, limit = 600): bool =
  for _ in 0 ..< limit:
    if cond(): return true
    on(clientSide): pollCoopSession(clientSide.session, mirror, Dt)
    on(hostSide): pollCoopSession(hostSide.session, host, Dt)
    sleep(1)
  cond()

globalSettings = newDefaultSettings()
randomize(91)
seedFxRand(5)

var host, mirror: Game

on(hostSide):
  hostSide.session = hostCoop(port, 4, CoopMemberNet(nickname: "Host"),
                              CoopRunConfigNet(mode: int32(ord(gmSandbox))))
on(clientSide):
  clientSide.session = joinCoop("127.0.0.1", port, CoopMemberNet(nickname: "Guest"))
let hs = hostSide.session
let cs = clientSide.session
check(pumpUntil(host, mirror, proc (): bool = cs.phase == cpClientLobby and hs.members.len == 2),
      "the client is seated")
on(clientSide): cs.setReady(true, 0)
check(pumpUntil(host, mirror, proc (): bool = hs.readyToStart), "ready")

# A sandbox run, as main.nim builds it, but with a finite pool of team lives
# (a sandbox has unlimited ones) so a down spends one.
on(hostSide):
  hs.startCoopRun()
  host = newGame(1024, 768)
  setGameMode(host, gmSandbox)
  initializeRunTracking(host)
  host.state = gsPlaying
  discard addCoopPlayer(host, "Guest")
  beginCoopRun(host)
  host.coop.nicknames[0] = "Host"
  host.coop.teamLives = 3
  hs.startRequested = false
check(pumpUntil(host, mirror, proc (): bool = cs.startRequested), "the client is told the run started")
on(clientSide):
  mirror = newGame(1024, 768)
  setGameMode(mirror, gmSandbox)
  discard addCoopPlayer(mirror, "Guest")
  mirror.player = mirror.players[cs.mySlot]
  mirror.coop = CoopState()
  cs.startRequested = false
  resetCoopSmoothing()
check(pumpUntil(host, mirror, proc (): bool = cs.lastApplied > 0), "the client mirrors the run")

# ---------------------------------------------------------- into the world --

on(hostSide):
  host.players[0].hp = 7
  host.players[1].hp = 5
  enterWorld3D(host, World3DOptions(bossEnabled: true, bossId: 7, carryHp: true))
  check(not activeWorld3D.isNil and activeWorld3D.players.len == 2,
        "the host's world seats both players")
  check(activeWorld3D.players[0].health == 7 and activeWorld3D.players[1].health == 5,
        "each brings their own health")
check(pumpUntil(host, mirror, proc (): bool = not clientSide.world.isNil),
      "the client gets the world")
on(clientSide):
  let w = activeWorld3D
  check(mirror.state == gs3DBoss and mirror.game3D == cast[pointer](w),
        "the client's run is in its own copy of it")
  check(w.player.slot == 1 and w.players.len == 2, "its player is its own seat")

let hostWorld = hostSide.world
proc bossPool(w: Game3D): float32 =
  ## The boss's health and its satellites' (the core can't be hurt while they're up).
  result = w.boss.health
  for sat in w.boss.satellites:
    if sat.active: result += sat.health
let bossStart = hostWorld.bossPool
var livesAtDown = 0
var livesAfterDown = 0
var p1Start = hostWorld.players[1].pos
var p1Moved = false
var clientErr, clientErrMax = 0.0
var samples = 0
var downSeen, respawned = false
var livesBefore = host.coop.teamLives
for f in 0 ..< 2400:
  on(clientSide):
    pollCoopSession(cs, mirror, Dt)
    let cw = activeWorld3D
    if not cw.isNil and mirror.state == gs3DBoss:
      let me3 = cw.localPlayer3D()
      botIntent3D(cw, me3, f)
      mirror.players[localSlot].intent = me3.intent
      predictLocal3D(mirror, Dt, cs.nextIntentSeq)
      smoothFrame3D(mirror, Dt, cs.snapshotAge)
      replayCoopFx(mirror)
      tickDamageNumbers3D(cw, Dt)
  on(hostSide):
    pollCoopSession(hs, host, Dt)
    let hw = activeWorld3D
    if not hw.isNil:
      botIntent3D(hw, hw.localPlayer3D(), f)
    updateGame(host, Dt)
  if f == 900:
    # The client's player goes down: a team life brings them back.
    on(hostSide):
      let hw = activeWorld3D
      let p = hw.players[1]
      p.invulnTimer = 0
      livesAtDown = host.coop.teamLives
      withPlayer3D(hw, p):
        discard damagePlayer3D(hw, 1.0e6, "test")
      livesAfterDown = host.coop.teamLives
      downSeen = p.downTimer > 0
  let hw = hostSide.world
  if not hw.isNil:
    if hw.players[1].pos != p1Start: p1Moved = true
    if downSeen and hw.players[1].isUp3D: respawned = true
    let cw = clientSide.world
    if not cw.isNil and f > 60 and hw.players[1].isUp3D and cw.players.len == 2:
      let d = length(cw.players[1].pos - hw.players[1].pos)
      clientErr += d
      clientErrMax = max(clientErrMax, d)
      inc samples
  if hostSide.world.isNil: break

echo "3D: boss and satellites ", int(bossStart), " -> ", int(hostWorld.bossPool), " phase ", hostWorld.boss.phase,
     "; lives ", livesBefore, " -> ", host.coop.teamLives,
     "; client's player off the host by ", formatFloat(clientErr / max(1, samples).float, ffDecimal, 2),
     " (", formatFloat(clientErrMax, ffDecimal, 1), " at most)"
check(p1Moved, "the client's input moves its player in the host's world")
check(hostWorld.bossPool < bossStart, "the team hurts the boss")
check(downSeen and respawned, "a down waits out its timer and comes back")
check(livesAfterDown == livesAtDown - 1, "and costs the team one life")
check(samples > 300 and clientErr / samples.float < 3.0, "the client's predicted player stays with the host's")

# ---------------------------------------------------------- out of it again --

check(not hostSide.world.isNil, "the team is still in the world")
if hostSide.world.isNil:
  echo passed, " passed, ", failures, " failed"
  quit 1
on(hostSide):
  let w = activeWorld3D
  w.players[0].health = 6
  w.players[1].health = 4
  finishWorld3D(w, w3Exit)
  updateGame(host, Dt)   # (leaves the finished world)
  check(activeWorld3D.isNil and host.state != gs3DBoss, "the host is back in the 2D run")
  check(host.players[0].hp == 6 and host.players[1].hp == 4,
        "each player takes their own health back")
check(pumpUntil(host, mirror, proc (): bool = clientSide.world.isNil), "the client drops its world")
on(clientSide):
  check(mirror.state != gs3DBoss and mirror.game3D.isNil, "and is back in the 2D run")

on(clientSide): cs.closeCoop()
on(hostSide): hs.closeCoop()
removeDir(sandboxDir)
echo passed, " passed, ", failures, " failed"
if failures > 0: quit 1
