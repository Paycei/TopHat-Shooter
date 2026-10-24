# Co-op in a 3D world (game3d/), over real loopback UDP: a host and a client in
# one process (each with its own side of the co-op globals, the world included),
# both played by the 3D bot. The pair enters the Orbital Commander's world from
# a sandbox run; the client mirrors it, plays its own player there (its input
# crosses the network; its movement is predicted), both players hurt the boss,
# a down spends a team life and comes back, and leaving the world hands each
# player's health back to their 2D self. Then a fresh world's first look (no
# jump, shot or skyward stare carried in from the 2D run), a mod's world (its
# spawn and view for the whole team, a teammate's aim and shake in their turn,
# run.data and hidden HUD parts reaching the client), and a client who leaves
# mid-world.
#   nim r --mm:orc tests/test_coop_3d.nim
#   nim r --mm:orc -d:danger tests/test_coop_3d.nim

import std/[os, random, math, strutils]
import raylib
import ../src/[game, types, settings, run_statistics, input_intent, vec]
import ../src/game3d/[types_3d, engine_3d, game_3d, player_3d]
import ../src/modding/[lua_bridge, mod_hooks, mod_loader, mod_catalog]
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
  host.coop.teamLives = 40   # (the bots carry 7 and 5 HP in: the boss downs them often)
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
  updateGame(host, Dt)   # (its first frame: a client takes the world once that has run)
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

proc teamFrame(clientYaw = NaN.float32, shoot = false) =
  ## One frame of both machines: the client as coopClient3DFrame plays it (its
  ## own view, turned to `clientYaw` when given; `shoot` pulls the trigger),
  ## the host as main.nim runs it.
  on(clientSide):
    pollCoopSession(cs, mirror, Dt)
    let cw = activeWorld3D
    if not cw.isNil and mirror.state == gs3DBoss:
      let me3 = cw.localPlayer3D()
      if not clientYaw.isNaN: cw.camera.yaw = clientYaw
      var it = me3.intent
      beginIntentFrame(it)
      it.view3D = true
      it.aim = Vector2(x: cw.camera.yaw, y: cw.camera.pitch)
      if shoot: pressEdge(it, Edge3DTrigger)
      me3.intent = it
      mirror.players[localSlot].intent = it
      predictLocal3D(mirror, Dt, cs.nextIntentSeq)
      smoothFrame3D(mirror, Dt, cs.snapshotAge)
      replayCoopFx(mirror)
  on(hostSide):
    pollCoopSession(hs, host, Dt)
    updateGame(host, Dt)
  sleep(1)

proc leaveWorldNow() =
  on(hostSide):
    if not activeWorld3D.isNil:
      finishWorld3D(activeWorld3D, w3Exit)
      updateGame(host, Dt)
  discard pumpUntil(host, mirror, proc (): bool = clientSide.world.isNil)

# ------------------------------------------------ a world's first look --
# The client's 2D input still aims at a point of the arena and carries presses
# its 2D self had: its seat must look where the world does (not at a pitch of
# 400 degrees, the sky), and neither jump, shoot nor reload on the way in.
var dashes: int32
on(clientSide):
  let me = mirror.players[cs.mySlot]
  me.intent.aim = Vector2(x: 600, y: 400)
  me.intent.view3D = false
  for e in IntentEdge: me.intent.edges[e] += 4
  dashes = me.intent.edges[ieDash]
check(pumpUntil(host, mirror, proc (): bool = host.players[1].intent.edges[ieDash] >= dashes and
                                             not host.players[1].intent.view3D),
      "the client's 2D input reaches the host")
on(hostSide):
  enterWorld3D(host, World3DOptions(bossEnabled: false))
  for _ in 0 ..< 3: updateGame(host, Dt)
  let w = activeWorld3D
  let seat = w.players[1]
  check(abs(seat.pitch - w.camera.pitch) < 0.01 and abs(seat.yaw - w.camera.yaw) < 0.01,
        "a client's seat looks where the world does (" & $seat.yaw & ", " & $seat.pitch & ")")
  check(w.projectiles.len == 0 and seat.vel.y < 10, "and its old presses neither shoot nor jump")
check(pumpUntil(host, mirror, proc (): bool = not clientSide.world.isNil), "the client gets the new world")
on(clientSide):
  check(abs(activeWorld3D.camera.pitch) < 0.01, "and starts looking ahead, not at the sky")
for f in 0 ..< 60: teamFrame(clientYaw = 30)
on(hostSide):
  check(abs(activeWorld3D.players[1].yaw - 30) < 0.01, "then its own view turns its seat")
leaveWorldNow()
on(hostSide):
  check(not consumeEdge(host.players[1], ieDash) and not consumeEdge(host.players[1], ieAbility),
        "and its 3D presses leave none pending for its 2D self")

# --------------------------------------------- a mod's world, in co-op --
# The script builds the world around the player it sees (the host's): it moves
# the spawn and that player onto its ground, turns the camera and hides a HUD
# part. A shot it takes over reads the shooter's aim and shakes their view.
let modDir = modsRootDir() / "coopworld"
createDir(modDir)
writeFile(modDir / "mod.json", """{"id": "coopworld", "name": "Co-op world", "version": "1.0.0"}""")
writeFile(modDir / "main.lua", """
hooks.on("world3dStart", function(world, resumed)
  world3d.platform{x = 0, y = -1, z = 0, w = 400, h = 2, d = 400}
  world.spawnPos = {x = 40, y = 1, z = 70}
  world.player.pos = {x = 40, y = 1, z = 70}
  world.camera.yaw = -90
  run.data.built = true
  hud.hide("crosshair")
  for _, p in ipairs(world.players) do p.weapon.fireRate = 0.3 end
end)
hooks.on("world3dShoot", function(world)
  local p = world.player
  if run.data["eye" .. p.slot] ~= nil then return end   -- (a seat's later shots fire)
  local x, y, z = world3d.aim()
  run.data["eye" .. p.slot] = math.abs(x - p.pos.x) < 0.01 and math.abs(z - p.pos.z) < 0.01
  world3d.shake(0.5)
  return true
end)
hooks.on("world3dEntityDeath", function(e)
  if e.tag == "target" then run.data.killedBy = world3d.player.slot end
end)
""")
reloadMods(@["coopworld"])
check(mods.len == 1, "the test mod loads")
on(hostSide):
  enterWorld3D(host, World3DOptions(bossEnabled: false))
  updateGame(host, Dt)
  let w = activeWorld3D
  let seat = w.players[1]
  check(abs(seat.pos.x - 48) < 0.5 and abs(seat.pos.z - 70) < 0.5 and seat.pos.y > 0,
        "the client's seat goes to the script's spawn, on its ground (" & $seat.pos & ")")
  check(abs(seat.yaw + 90) < 0.01, "looking where the script turned the camera")
  check(w.players[0].weapon.fireRate == 0.3'f32 and seat.weapon.fireRate == 0.3'f32,
        "a script reaches every seat through world.players")
check(pumpUntil(host, mirror, proc (): bool = not clientSide.world.isNil), "the client gets the mod's world")
on(clientSide):
  check(abs(activeWorld3D.camera.yaw + 90) < 0.01, "and its view starts there too")
for f in 0 ..< 30: teamFrame()
teamFrame(shoot = true)
for f in 0 ..< 30: teamFrame()
on(hostSide):
  check(truthy(rawGetStr(mods[0].runData, "eye1")),
        "the client's shot reads the client's own aim (world3d.aim)")
  check(activeWorld3D.camera.shakeTime <= 0, "and shakes no one's view but theirs")
on(clientSide):
  check(activeWorld3D.camera.shakeTime > 0, "the client's view shakes")
# A target right in front of the client: the kill its shot makes is the client's.
on(hostSide):
  let w = activeWorld3D
  let seat = w.players[1]
  let target = newEntity3D(w, "target")
  target.hp = 1
  target.maxHp = 1
  target.pos = seat.pos + vec3(0, 1.5, 0) + seat.viewOf().getForward() * 12
  queueWorld3DAction(World3DAction(kind: wkSpawnEntity, entity: target))
var killedBy = NilValue
for f in 0 ..< 120:
  teamFrame(shoot = f mod 10 == 0)
  killedBy = rawGetStr(mods[0].runData, "killedBy")
  if killedBy.kind != vkNil: break
check(killedBy.kind == vkNumber and killedBy.n == 1,
      "a client's kill runs in the client's turn (world3dEntityDeath)")
check(pumpUntil(host, mirror, proc (): bool = mirror.modRunData == host.modRunData and
                                             "built" in mirror.modRunData),
      "run.data travels with the snapshots")
hiddenHud = {}
mods[0].runData = newScriptTable()
on(clientSide): modCoopClientFrame(mirror)
check(truthy(rawGetStr(mods[0].runData, "built")) and hpCrosshair in hiddenHud,
      "a client's scripts read the host's run.data and HUD")

# ------------------------------------------- a client leaves the world --
on(clientSide): cs.closeCoop()
for _ in 0 ..< 10:
  on(hostSide):
    pollCoopSession(hs, host, Dt)
    updateGame(host, Dt)
  sleep(1)
on(hostSide):
  check(activeWorld3D.players[1].eliminated, "a client who leaves is out of the world too")
  check(not activeWorld3D.teamOut3D, "while the host plays on")

on(hostSide): hs.closeCoop()
removeDir(sandboxDir)
echo passed, " passed, ", failures, " failed"
if failures > 0: quit 1
