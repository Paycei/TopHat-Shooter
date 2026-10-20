# Tests for PvP packet decoding (src/network/network.nim), over real loopback
# UDP: anyone who can reach a host's port can send it a datagram, and every
# datagram is decoded before anything checks who sent it.
#   nim r --mm:orc tests/test_packet_decode.nim
#   nim r --mm:orc -d:danger tests/test_packet_decode.nim   (how releases decode)
# Hostile datagrams must be dropped without a crash or an event, and every
# packet kind must still arrive exactly as it was sent: readNet reads
# flatty's layout, so toFlatty of what arrives equals toFlatty of what left.

import std/[os, net, random, strutils]
import raylib
import flatty, flatty/binny, supersnappy
import ../src/network/[network, network_types]
import ../src/[types, particle_types]

var failures = 0
var passed = 0

proc check(cond: bool, name: string) =
  if cond: inc passed
  else:
    echo "FAIL ", name
    inc failures

const HostPort = 17391

let host = newNetworkManager()
host.initHost(HostPort, 4)
let client = newNetworkManager()
client.initClient()
client.connectToHost("127.0.0.1", HostPort, nickname = "tester")

var hostEvents, clientEvents: seq[NetworkEvent]

proc pump(rounds = 20) =
  for _ in 0 ..< rounds:
    hostEvents.add host.pollEvents()
    clientEvents.add client.pollEvents()
    sleep(5)

proc clearEvents() =
  hostEvents = @[]
  clientEvents = @[]

# ------------------------------------------------------------- connecting ----
pump()
var accepted = false
for e in hostEvents:
  if e.kind == neConnect and e.connectPlayerIndex == 1: accepted = true
check(accepted and client.isConnected, "a client connects (a ConnectionRequest decodes)")
host.resetReceiveTimer()     # no timeouts while the test takes its time
client.resetReceiveTimer()
clearEvents()

# ------------------------------------------------------- hostile datagrams ----
proc header(kind: int64, modDataLen: int64): string =
  result.addInt64(kind)          # flatty writes a variant's discriminator first
  result.addInt64(0)             # tick
  result.addFloat32(0)           # timestamp
  result.addInt64(0)             # matchId
  result.addInt64(modDataLen)    # modData

proc framed(raw: string): string = "THS1" & supersnappy.compress(raw)

proc snappyLen(n: int): string =
  ## The varint a snappy block opens with: the size it decompresses to.
  var v = n
  while v >= 0x80:
    result.add char((v and 0x7F) or 0x80)
    v = v shr 7
  result.add char(v)

var hostile: seq[(string, string)]
hostile.add(("a string claiming 2^40 bytes", framed(header(0, 1'i64 shl 40))))
block:
  var r = header(ord(ptGameState), 0)
  r.addInt64(0); r.addFloat32(0); r.addInt64(2)    # tick, timestamp, maxPlayers
  r.addInt64(1'i64 shl 31)                         # players: 2^31 entries
  hostile.add(("a list claiming 2^31 entries", framed(r)))
block:
  var r = header(ord(ptGameState), 0)
  r.addInt64(0); r.addFloat32(0); r.addInt64(2)
  r.addInt64(1_000_000)                            # more players than the bytes could hold
  r.add(repeat('\0', 1_200_000))                   # (compresses into one datagram)
  hostile.add(("a list longer than its bytes", framed(r)))
hostile.add(("a packet kind that does not exist", framed(header(77, 0))))
hostile.add(("a negative packet kind", framed(header(-1, 0))))
hostile.add(("snappy declaring 4 GB", "THS1\xff\xff\xff\xff\x0f"))
hostile.add(("snappy declaring 3 MB", "THS1" & snappyLen(3_000_000) & "\0\0\0\0"))
block:
  var p = newPacket(ptGameOver, 5)
  p.finalStats = @[PvPStatsNet(kills: 3), PvPStatsNet(kills: 1)]
  p.endText = "a valid packet"
  let raw = p.toFlatty()
  hostile.add(("a valid packet cut short", framed(raw[0 ..< raw.len div 2])))
  let whole = framed(raw)
  hostile.add(("a compressed stream cut short", whole[0 ..< whole.len div 2]))
hostile.add(("no magic", "garbage"))
var rng = initRand(20261018)
for n in 0 ..< 300:
  var raw = newString(rng.rand(1 .. 300))
  for c in raw.mitems: c = char(rng.rand(255))
  hostile.add(("random bytes", if n mod 2 == 0: framed(raw) else: "THS1" & raw))

let evil = newSocket(AF_INET, SOCK_DGRAM, IPPROTO_UDP, buffered = false)
let clientPort = client.socket.getLocalAddr()[1]
for (name, data) in hostile:
  doAssert data.len <= 65507, "hostile datagram must fit one datagram: " & name
  try:
    evil.sendTo("127.0.0.1", Port(HostPort), data)
    evil.sendTo("127.0.0.1", clientPort, data)
  except OSError:
    discard
  pump(1)
pump()
check(hostEvents.len == 0, "hostile datagrams reach the host as nothing (" & $hostEvents.len & " events)")
check(clientEvents.len == 0, "hostile datagrams reach the client as nothing (" & $clientEvents.len & " events)")
check(host.clients.len == 1 and client.isConnected, "the match is still there")
clearEvents()

# --------------------------------------------------------------- round trip ----
let col = Color(r: 1, g: 2, b: 3, a: 4)
let roster: seq[ConnectedPlayerInfo] = @[
  (index: 0, skinType: 1, bulletSkinType: 2, shapeType: 3, particleSkinType: 4, nickname: "host"),
  (index: 1, skinType: 5, bulletSkinType: 6, shapeType: 7, particleSkinType: 8, nickname: "ñandú")]

proc playerNet(i: int): PlayerStateNet =
  PlayerStateNet(playerIndex: i, isActive: i mod 2 == 0, pos: vec2(1.5, -2),
                 vel: vec2(3, 4), hp: 2.5, maxHp: 3, coins: 7, kills: i, walls: 2,
                 damage: 1.25, speed: 200, fireRate: 0.375, bulletSpeed: 425,
                 invincibilityTimer: 0.5, teamId: 2, skinType: 3, bulletSkinType: 4,
                 shapeType: 5, particleSkinType: 6, nickname: "p" & $i, deaths: 1,
                 streak: 2, dashTimer: 0.1, dashCooldown: 0.2, shieldHits: 1,
                 speedBoostTimer: 0.3, fireRateBoostTimer: 0.4, spreadTimer: 0.5,
                 modSkin: 2, modBulletSkin: -1, radius: 12, warp: 3)

proc bulletNet(i: int): BulletStateNet =
  BulletStateNet(id: 1_000_000 + i, pos: vec2(i.float32, 2), vel: vec2(3, 4),
                 radius: 7.5, damage: 1, fromPlayerIndex: i mod 2, isPiercing: true,
                 isExplosive: i mod 3 == 0, isHoming: false, bulletSkin: 2, life: 1.5,
                 color: col, kind: (if i mod 2 == 0: "laser" else: ""), pierce: 2)

proc wallNet(i: int): WallStateNet =
  WallStateNet(pos: vec2(i.float32, 5), radius: 20, hp: 3, maxHp: 4, ownerIndex: i mod 2)

proc sample(kind: PacketType): Packet =
  result = newPacket(kind, 42)
  result.matchId = 3
  result.modData = """{"mymod":{"score":[1,2]}}"""
  case kind
  of ptConnectionRequest:
    result.version = NETWORK_VERSION
    result.playerName = "tester"
    result.requestSkinType = 1
    result.modFingerprint = "abc"
    result.modList = "a, b"
    result.requestModSkin = 3
    result.requestModBulletSkin = -2
  of ptConnectionAccept, ptConnectionDenied:
    result.connectionReason = "Player list updated"
    result.assignedPlayerIndex = 1
    result.connectedPlayers = roster
  of ptPlayerListUpdate:
    result.updatedPlayers = roster
  of ptGameStart:
    result.countdownTime = 3.5
    result.teamsEnabled = true
    result.teamAssignments = @[1, 2]
    result.gameConnectedPlayers = roster
    var cfg = defaultPvPConfig()
    cfg.killLimit = 0
    cfg.pickupsEnabled = false
    cfg.modMode = "mymod:king"
    result.pvpConfig = cfg
    result.spawnPositions = @[vec2(1, 2), vec2(3, 4)]
  of ptPlayerInput:
    result.input = PlayerInput(tick: 7, playerIndex: 1, moveDir: vec2(0.6, -0.8),
                               shooting: true, mousePos: vec2(100, 200),
                               placingWall: true, wallPos: vec2(5, 6), timestamp: 1.5,
                               dt: 0.016, dashSeq: 2, dashDir: vec2(1, 0))
    result.modMsgs = @[ModNetMsg(seq: 1, name: "hi", data: "{}"),
                       ModNetMsg(seq: 2, name: "buy", data: """{"item":3}""")]
    result.modAck = 4
  of ptGameState:
    var s = NetworkGameState(tick: 9, timestamp: 1.5, maxPlayers: 2)
    for i in 0 ..< 2: s.players.add(playerNet(i))
    for i in 0 ..< 3: s.bullets.add(bulletNet(i))
    for i in 0 ..< 2: s.walls.add(wallNet(i))
    s.ports = @[PortStateNet(kind: 2, active: true, timer: 1.5),
                PortStateNet(kind: 0, active: false, timer: 4)]
    s.modMsgs = @[ModNetMsg(seq: 5, name: "zone", data: """{"x":1}""")]
    s.modAcks = @[0'i32, 2]
    result.state = s
  of ptBulletSpawn: result.bullet = bulletNet(7)
  of ptBulletDestroy: result.bulletId = 1_000_005
  of ptPlayerDamage:
    result.damagedPlayerIndex = 1
    result.damageAmount = 2.5
    result.newHp = 0.5
    result.attackerIndex = 0
    result.blocked = true
  of ptPlayerDeath:
    result.deadPlayerIndex = 1
    result.killerIndex = 0
    result.killerStreak = 3
    result.multiKill = 2
    result.firstBlood = true
    result.shutdownStreak = 5
  of ptWallPlace: result.wall = wallNet(3)
  of ptWallDestroy: result.wallIndex = 2
  of ptGameOver:
    result.winnerIndex = 0
    result.winnerTeam = 1
    result.endReason = 2
    result.finalStats = @[PvPStatsNet(kills: 3, deaths: 1, bestStreak: 2, shotsFired: 40,
                                      shotsHit: 12, damageDealt: 9.5, pickupsTaken: 2)]
    result.endText = "gg"
  of ptDisconnect: result.disconnectReason = "bye"
  of ptPing, ptPong:
    result.pingId = 3
    result.sendTime = 1.25
  of ptPlayerRespawn:
    result.respawnIndex = 1
    result.respawnPos = vec2(10, 20)
  of ptPickupTaken:
    result.pickupPort = 2
    result.pickupKind = 1
    result.pickupTaker = 1
    result.pickupApplied = true

proc received(events: seq[NetworkEvent], kind: PacketType): seq[Packet] =
  for e in events:
    if e.kind == neReceive and e.packet.kind == kind: result.add(e.packet)

# Host to client: every kind the client hands on as a packet (it answers
# pings and reads pongs itself; a disconnect is tested last).
for kind in PacketType:
  if kind in {ptConnectionRequest, ptPing, ptPong, ptDisconnect}: continue
  let sent = sample(kind)
  host.sendPacket(sent)
  pump(4)
  let got = received(clientEvents, kind)
  check(got.len == 1 and got[0].toFlatty() == sent.toFlatty(), "host -> client: " & $kind)
  clearEvents()

# A big snapshot: many bullets (decoded one by one) and walls (copied raw).
block:
  var big = sample(ptGameState)
  for i in 0 ..< 250: big.state.bullets.add(bulletNet(i))
  for i in 0 ..< 120: big.state.walls.add(wallNet(i))
  host.sendPacket(big)
  pump(4)
  let got = received(clientEvents, ptGameState)
  check(got.len == 1 and got[0].toFlatty() == big.toFlatty(), "host -> client: a big snapshot")
  clearEvents()

# Client to host: an input (the host sets its playerIndex to the sender's slot).
block:
  var input = sample(ptPlayerInput)
  input.input.playerIndex = 3
  client.sendPacket(input)
  pump(4)
  let got = received(hostEvents, ptPlayerInput)
  var expected = input
  expected.input.playerIndex = 1
  check(got.len == 1 and got[0].toFlatty() == expected.toFlatty(), "client -> host: an input")
  # a host-only packet from a client is dropped
  client.sendPacket(sample(ptGameOver))
  pump(4)
  check(received(hostEvents, ptGameOver).len == 0, "client -> host: a forged game over is dropped")
  clearEvents()

# Last: the host leaves.
host.sendPacket(sample(ptDisconnect))
pump(4)
var bye = false
for e in clientEvents:
  if e.kind == neDisconnect and e.reason == "bye": bye = true
check(bye and not client.isConnected, "host -> client: a disconnect")

evil.close()
host.cleanup()
client.cleanup()
echo passed, " passed, ", failures, " failed"
if failures > 0: quit(1)
