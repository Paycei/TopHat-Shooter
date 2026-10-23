## A co-op session: CO-OP.EXE's lobby, then the run, over the network.
##
## The host hosts (network.nim, lobby kind LobbyCoop), seats who joins, sends
## the lobby and the run's settings, then, once the run is on, the run itself:
## a snapshot (coop_codec) to each client about 30 times a second, as the
## change since the one it last confirmed, cut into fragments that fit a
## datagram. Each client sends its player's input (the intent), its team-modal
## actions and what it has confirmed, about 60 times a second.
##
## Reliable bits ride on the unreliable stream and are repeated until
## confirmed: a client's actions (the host confirms the newest it applied in
## each snapshot) and the profile progress the host owes each client (the
## client confirms the newest it applied). A lost datagram only delays them.
##
## main.nim polls the session every frame, whatever the state (pollCoopSession),
## and starts or mirrors the run when it says so. This module never imports
## game.nim: it reads and writes the Game it is handed.

import std/[tables, json]
import ../modding/mod_patch_core
import ../network/[network, network_types]
import ../types, ../save_system
import coop_context, coop_codec, coop_wire

const
  CoopDefaultPort* = 7778        ## (DUELINK uses 7777)
  SnapshotInterval = 1.0'f32 / 30.0'f32
  InputInterval = 1.0'f32 / 60.0'f32
  LobbyInterval = 0.5'f32        ## the host resends the lobby this often
  PingInterval = 1.0'f32
  JoinRetry = 1.0'f32            ## a join request is resent this often...
  JoinTimeout = 10.0'f32         ## ...until the host answers or this runs out
  FragmentPayload = 1150         ## bytes of snapshot per datagram (under a typical MTU)
  FragmentHeader = 12            ## magic(4) + seq(4) + index(2) + count(2)
  MaxFragments = 2048            ## a snapshot cut into more is refused
  MaxPartialSnapshots = 8        ## incomplete snapshots kept while their fragments arrive
  StartResend = 0.25'f32           ## the start goes out again this often until each client answers
  EndRepeats = 3
  EndAckTimeout = 5.0'f32        ## the end goes out after this even if progress is unconfirmed

type
  CoopPhase* = enum
    cpIdle         ## no session
    cpHostLobby    ## hosting: seating players, picking the run
    cpJoining      ## asked a host to join, waiting for the answer
    cpClientLobby  ## seated in a host's lobby
    cpRunning      ## the run is on
    cpEnding       ## host: the run is over; its last profile progress is being confirmed
    cpEnded        ## the run is over (results), back to the lobby next
    cpError        ## refused, timed out, or the host left: `errorText` says why

  CoopEndReason* = enum
    cerWiped       ## the whole team is out
    cerEnded       ## the host ended the run (won, left it for the desktop, a mod)
    cerHostLeft    ## the host closed the session

  FragBuf = object
    count: int
    have: int
    parts: seq[string]

  CoopSession* = ref object
    phase*: CoopPhase
    nm*: NetworkManager
    isHost*: bool
    mySlot*: int32                 ## this machine's seat (the host's is 0)
    maxPlayers*: int
    members*: seq[CoopMemberNet]   ## every seat, by slot (the host's first)
    config*: CoopRunConfigNet      ## the run the host picked
    errorText*: string
    run*: int32                    ## which run of this session (packets of an older one are dropped)
    startRequested*: bool          ## main.nim: build the run now (host: start it; client: mirror it)
    ended*: bool                   ## main.nim: the run is over (endReason / endStats)
    endReason*: CoopEndReason
    endStats*: string              ## this player's statistics (JSON, client)
    lobbyTimer, pingTimer, inputTimer, snapTimer: float32
    startResendTimer: float32
    endWait: float32
    endSent: array[MaxCoopPlayers, bool]
    # host
    readyByAddr: Table[string, tuple[ready: bool, kit: int32]]
      ## each client's ready flag and kit by its address: the network layer
      ## renumbers the seats when someone leaves the lobby
    snapSeq: int32
    hostRing: FrameRing
    clientAck: array[MaxCoopPlayers, int32]       ## newest snapshot each client confirmed
    actionApplied: array[MaxCoopPlayers, int32]   ## newest action of each client applied
    intentSeqIn: array[MaxCoopPlayers, int32]
    profileFirst: array[MaxCoopPlayers, int32]    ## seq of profileLog[slot][0]
    profileLog: array[MaxCoopPlayers, seq[ProfileEvent]]
    bytesSent: int
    bytesPerSecond*: int           ## snapshot bytes sent over the last second
    bytesClock: float32
    # client
    joinHost: string
    joinPort: int
    joinRequest: CoopMemberNet     ## nickname + cosmetics, resent until answered
    joinTimer, joinRetryTimer: float32
    clientRing: FrameRing
    frags: Table[int32, FragBuf]
    lastApplied*: int32            ## the newest snapshot applied to the mirror (0: none yet)
    snapshotAge*: float32          ## seconds since it arrived
    actionSeqOut: int32
    pendingActions: seq[CoopAction]
    intentSeqOut: int32
    profileApplied: int32

var
  activeCoop*: CoopSession
    ## The session in progress, nil when none. Lives across the lobby, the
    ## run and back.
  coopProfileInbox*: seq[ProfileEvent]
    ## Client: progress the host sent for this machine's profile, each event
    ## once, for main.nim to apply (it owns the advancement profile).

proc memberIndex(s: CoopSession, slot: int32): int =
  for i, m in s.members:
    if m.slot == slot: return i
  -1

proc memberName*(s: CoopSession, slot: int32): string =
  let i = s.memberIndex(slot)
  if i >= 0: s.members[i].nickname else: ""

proc readyToStart*(s: CoopSession): bool {.moddable.} =
  ## Host: two players or more, every client ready.
  if s.isNil or not s.isHost or s.phase != cpHostLobby or s.members.len < 2:
    return false
  for m in s.members:
    if not m.ready: return false
  true

proc running*(s: CoopSession): bool {.inline.} =
  not s.isNil and s.phase == cpRunning

# ------------------------------------------------------------- opening ----

proc hostCoop*(port: int, maxPlayers: int, me: CoopMemberNet,
               config: CoopRunConfigNet): CoopSession {.moddable.} =
  ## Open a lobby on `port` for up to `maxPlayers` (2-4) and make it the
  ## active session; `me` is the host's nickname and cosmetics. Raises OSError
  ## if the port can't be opened.
  result = CoopSession(phase: cpHostLobby, isHost: true, config: config, mySlot: 0,
                       maxPlayers: clamp(maxPlayers, 2, MaxCoopPlayers))
  result.nm = newNetworkManager()
  result.nm.hostNickname = me.nickname
  result.nm.initHost(port, result.maxPlayers, LobbyCoop, CoopLayoutHash)
  var host = me
  host.slot = 0
  host.ready = true
  host.connected = true
  result.members = @[host]
  activeCoop = result

proc sendJoinRequest(s: CoopSession) =
  let me = s.joinRequest
  s.nm.connectToHost(s.joinHost, s.joinPort, me.skinType.int, me.bulletSkinType.int,
                     me.shapeType.int, me.particleSkinType.int,
                     me.nickname, LobbyCoop, CoopLayoutHash)

proc joinCoop*(host: string, port: int, me: CoopMemberNet): CoopSession {.moddable.} =
  ## Ask the host at `host`:`port` for a seat and make this the active session.
  result = CoopSession(phase: cpJoining, isHost: false, joinHost: host, joinPort: port,
                       joinRequest: me)
  result.nm = newNetworkManager()
  result.nm.initClient()
  result.sendJoinRequest()
  activeCoop = result

proc closeCoop*(s: CoopSession, reason = "Left the game") {.moddable.} =
  ## Leave (a client) or close (the host) the session, and go back to single
  ## player.
  if s.isNil: return
  try:
    s.nm.disconnect(reason)
    s.nm.cleanup()
  except CatchableError:
    discard
  s.phase = cpIdle
  if activeCoop == s:
    activeCoop = nil
  coopSendAction = nil
  coopProfileInbox.setLen(0)
  resetCoopContext()

# --------------------------------------------------------------- lobby ----

proc lobbyPacket(s: CoopSession): Packet =
  result = newPacket(ptCoopLobby)
  result.lobbyMembers = s.members
  result.lobbyConfig = s.config
  result.lobbyMaxPlayers = int32(s.maxPlayers)

proc broadcastLobby*(s: CoopSession) {.moddable.} =
  ## Host: everyone's view of the lobby, now (also resent every LobbyInterval).
  if s.isNil or not s.isHost: return
  s.nm.sendPacket(s.lobbyPacket())
  s.lobbyTimer = 0

proc addrKey(c: ConnectedClient): string = c.address & ":" & $c.port.int

proc rebuildMembers(s: CoopSession) =
  ## Host, in the lobby: the seats are the network layer's clients (which it
  ## renumbers 1..n when someone leaves), each keeping its ready flag and kit.
  var seats = @[s.members[0]]
  for c in s.nm.clients:
    var m = CoopMemberNet(slot: int32(c.playerIndex), nickname: c.nickname, connected: true,
                          skinType: int32(c.skinType), bulletSkinType: int32(c.bulletSkinType),
                          shapeType: int32(c.shapeType), particleSkinType: int32(c.particleSkinType),
                          modSkin: c.modSkin, modBulletSkin: c.modBulletSkin)
    let r = s.readyByAddr.getOrDefault(c.addrKey)
    m.ready = r.ready
    m.starterKit = r.kit
    seats.add m
  # By slot, so seat k is the run's player k.
  for i in 1 ..< seats.len:
    var j = i
    while j > 1 and seats[j - 1].slot > seats[j].slot:
      swap(seats[j - 1], seats[j])
      dec j
  s.members = seats

proc setLobbyConfig*(s: CoopSession, config: CoopRunConfigNet) {.moddable.} =
  ## Host: the run it picked (mode, mod mode, Heat...), for the lobby to show.
  if s.isNil or not s.isHost: return
  s.config = config
  s.broadcastLobby()

proc setReady*(s: CoopSession, ready: bool, kit: int32) {.moddable.} =
  ## This player is (not) ready, with their roguelite starter kit.
  if s.isNil: return
  if s.isHost:
    if s.members.len > 0:
      s.members[0].starterKit = kit
      s.broadcastLobby()
  else:
    let i = s.memberIndex(s.mySlot)
    if i >= 0:
      s.members[i].ready = ready   # shown at once; the host's lobby confirms it
      s.members[i].starterKit = kit
    var p = newPacket(ptCoopReady)
    p.readyFlag = ready
    p.readyKit = kit
    s.nm.sendPacket(p)

proc startCoopRun*(s: CoopSession) {.moddable.} =
  ## Host: the run starts. main.nim builds it (startRequested) and the
  ## clients are told to mirror it.
  if not s.readyToStart: return
  inc s.run
  s.phase = cpRunning
  s.startRequested = true
  s.ended = false
  s.snapSeq = 0
  s.snapTimer = 0
  s.hostRing.clear()
  for k in 0 ..< MaxCoopPlayers:
    s.clientAck[k] = 0
    s.actionApplied[k] = 0
    s.intentSeqIn[k] = 0
    s.profileFirst[k] = 1
    s.profileLog[k].setLen(0)
  s.startResendTimer = StartResend   # (sent on the first poll)
  s.nm.matchStarted = true   # seats are frozen: no one joins a run under way

proc sendStart(s: CoopSession) =
  var p = newPacket(ptCoopStart)
  p.startMembers = s.members
  p.startConfig = s.config
  p.startRun = s.run
  s.nm.sendPacket(p)

proc sendEnd(s: CoopSession, slot: int32) =
  ## Host: the run is over, with player `slot`'s own statistics.
  var p = newPacket(ptCoopEnd)
  p.endRun = s.run
  p.coopEndReason = int32(ord(s.endReason))
  let stats = slotRunStats[slot]
  p.endStats = if stats.isNil: "" else: $runStatisticsToJson(stats)
  for _ in 0 ..< EndRepeats:
    s.nm.sendPacketToSlot(slot, p)
  s.endSent[slot] = true

proc endCoopRun*(s: CoopSession, reason: CoopEndReason) {.moddable.} =
  ## Host: the run is over (call it once its rewards are banked). Each client
  ## gets its own statistics once it has confirmed the last of its profile
  ## progress (or EndAckTimeout passed), and again whenever input for the
  ## finished run still arrives (the end was lost). Then the session waits in
  ## its lobby for the next run.
  if not s.running or not s.isHost: return
  s.phase = cpEnding
  s.ended = true
  s.endReason = reason
  s.endWait = 0
  for k in 0 ..< MaxCoopPlayers: s.endSent[k] = false
  s.nm.matchStarted = false
  for m in s.members.mitems:
    if m.slot != 0: m.ready = false
  for v in s.readyByAddr.mvalues:
    v.ready = false

proc flushEnds(s: CoopSession, force: bool) =
  ## Host, ending: the end goes to each client whose profile progress is all
  ## confirmed (`force`: to all). Ended once every client has it.
  var waiting = false
  for m in s.members:
    if m.slot == 0 or not m.connected or s.endSent[m.slot]: continue
    if force or (s.profileLog[m.slot].len == 0 and coopProfileOutbox[m.slot].len == 0):
      s.sendEnd(m.slot)
    else:
      waiting = true
  if not waiting: s.phase = cpEnded

proc backToLobby*(s: CoopSession) {.moddable.} =
  ## After the results: the lobby again, same seats.
  if s.isNil: return
  if s.isHost and s.phase == cpEnding:
    s.flushEnds(force = true)
  if s.phase in {cpEnded, cpRunning}:
    s.phase = if s.isHost: cpHostLobby else: cpClientLobby
  s.ended = false
  s.startRequested = false
  s.frags.clear()
  s.clientRing.clear()
  s.lastApplied = 0
  s.pendingActions.setLen(0)
  if s.isHost:
    s.nm.renumberSeats()   # seats 1..n again (a client may have left mid-run)
    s.rebuildMembers()
    s.broadcastLobby()

# ------------------------------------------------------------ the host ----

proc applyIntent(game: Game, slot: int32, it: PlayerIntent) =
  ## A client's newest input drives its player. Its press counters only ever
  ## grow, so a press the host hasn't seen yet is still pending however many
  ## inputs were lost on the way.
  if game.isNil or slot < 0 or slot >= game.players.len: return
  let p = game.players[slot]
  if p.eliminated: return
  var next = it
  next.seen = p.intent.seen
  for e in IntentEdge:
    if next.edges[e] < p.intent.edges[e]: next.edges[e] = p.intent.edges[e]
  p.intent = next

proc playerLeft(s: CoopSession, game: Game, slot: int32) =
  ## Host: a client left the run under way. Their player is out (it would
  ## otherwise stand still and spend the team's lives), and a team modal stops
  ## waiting for them.
  if game.isNil or slot <= 0 or slot >= game.players.len: return
  let p = game.players[slot]
  p.intent = PlayerIntent()
  p.eliminated = true
  p.downTimer = 0
  if not game.coop.isNil:
    game.coop.seats[slot].ready = true

proc hostReceive(s: CoopSession, game: Game, packet: Packet) =
  case packet.kind
  of ptCoopReady:
    let i = s.memberIndex(packet.readySlot)
    if i >= 0 and s.phase in {cpHostLobby, cpEnded}:
      s.members[i].ready = packet.readyFlag
      s.members[i].starterKit = packet.readyKit
      for c in s.nm.clients:
        if c.playerIndex == packet.readySlot:
          s.readyByAddr[c.addrKey] = (packet.readyFlag, packet.readyKit)
      s.broadcastLobby()
  of ptCoopInput:
    let slot = packet.inputSlot
    if slot <= 0 or slot >= MaxCoopPlayers or packet.inputRun != s.run: return
    if s.phase == cpEnded or (s.phase == cpEnding and s.endSent[slot]):
      s.sendEnd(slot)   # it still plays: the end was lost
      return
    if s.phase notin {cpRunning, cpEnding}:
      return
    s.clientAck[slot] = max(s.clientAck[slot], packet.snapAck)
    # Profile progress the client has applied: forget it.
    let done = packet.profileAck - s.profileFirst[slot] + 1
    if done > 0:
      let n = min(done.int, s.profileLog[slot].len)
      s.profileLog[slot] = s.profileLog[slot][n .. ^1]
      s.profileFirst[slot] += int32(n)
    if s.phase != cpRunning: return   # (ending: only the confirmations count)
    if packet.intentSeq > s.intentSeqIn[slot] and packet.intents.len > 0:
      s.intentSeqIn[slot] = packet.intentSeq
      applyIntent(game, slot, packet.intents[0])
    for a in packet.actions:
      if a.seq > s.actionApplied[slot]:
        s.actionApplied[slot] = a.seq
        coopActionQueue.add((slot, a))
  else:
    discard

proc hostSnapshots(s: CoopSession, game: Game, dt: float32) =
  s.snapTimer += dt
  if s.snapTimer < SnapshotInterval or game.isNil: return
  s.snapTimer = 0
  # Profile progress owed to each client joins its log until confirmed.
  for slot in 1 ..< MaxCoopPlayers:
    if coopProfileOutbox[slot].len > 0:
      s.profileLog[slot].add coopProfileOutbox[slot]
      coopProfileOutbox[slot].setLen(0)
  inc s.snapSeq
  let frame = captureFrame(game, s.snapSeq)
  s.hostRing.put(frame)
  for m in s.members:
    let slot = m.slot
    if slot == 0 or not m.connected: continue
    let base = s.hostRing.find(s.clientAck[slot])
    let extras = SnapExtras(actionAck: s.actionApplied[slot], profileFirst: s.profileFirst[slot],
                            profileEvents: s.profileLog[slot])
    let packed = encodeSnapshot(frame, base, extras)
    let count = (packed.len + FragmentPayload - 1) div FragmentPayload
    if count > MaxFragments: continue   # (never at any real size; the client would refuse it)
    for k in 0 ..< count:
      var d = RAW_MAGIC
      putW(d, s.snapSeq)
      putW(d, uint16(k))
      putW(d, uint16(count))
      d.add packed[k * FragmentPayload ..< min(packed.len, (k + 1) * FragmentPayload)]
      s.nm.sendRawToSlot(slot, d)
      s.bytesSent += d.len

# ---------------------------------------------------------- the client ----

proc clientSendAction(a: CoopAction) =
  ## coopSendAction for a client: kept (and resent) until the host confirms it.
  let s = activeCoop
  if s.isNil or s.isHost: return
  inc s.actionSeqOut
  var x = a
  x.seq = s.actionSeqOut
  s.pendingActions.add x

proc clientSendInput(s: CoopSession, game: Game) =
  if game.isNil or s.mySlot < 0 or s.mySlot >= game.players.len: return
  inc s.intentSeqOut
  var p = newPacket(ptCoopInput)
  p.inputRun = s.run
  p.intents = @[game.players[s.mySlot].intent]
  p.intentSeq = s.intentSeqOut
  p.actions = s.pendingActions
  p.snapAck = s.lastApplied
  p.profileAck = s.profileApplied
  s.nm.sendPacket(p)

proc applyComplete(s: CoopSession, packed: string, game: Game) =
  try:
    var extras: SnapExtras
    let frame = readSnapshot(packed, s.clientRing, extras)
    applySnapshot(frame, game)
    s.clientRing.put(frame)
    s.lastApplied = frame.seq
    s.snapshotAge = 0
    # The host has applied our actions up to actionAck.
    var keep: seq[CoopAction]
    for a in s.pendingActions:
      if a.seq > extras.actionAck: keep.add a
    s.pendingActions = keep
    # Profile progress, each event once.
    for k, ev in extras.profileEvents:
      let evSeq = extras.profileFirst + int32(k)
      if evSeq == s.profileApplied + 1:
        coopProfileInbox.add ev
        s.profileApplied = evSeq
  except CoopWireError:
    discard   # malformed, or its base is gone: the next is based on what we confirmed

proc acceptFragment(s: CoopSession, data: string, game: Game) =
  ## One snapshot fragment; a complete snapshot is applied to the mirror.
  if data.len < FragmentHeader: return
  var i = RAW_MAGIC.len
  var seq: int32
  var index, count: uint16
  try:
    getW(data, i, seq)
    getW(data, i, index)
    getW(data, i, count)
  except CoopWireError:
    return
  if seq <= s.lastApplied or count == 0 or count.int > MaxFragments or index >= count:
    return
  if count == 1:
    s.applyComplete(data[FragmentHeader .. ^1], game)
    return
  if seq notin s.frags:
    if s.frags.len >= MaxPartialSnapshots:
      # The oldest incomplete one is the least use.
      var oldest = seq
      for k in s.frags.keys: oldest = min(oldest, k)
      if oldest == seq: return
      s.frags.del(oldest)
    s.frags[seq] = FragBuf(count: count.int, parts: newSeq[string](count.int))
  let buf = addr s.frags[seq]
  if buf.count != count.int or buf.parts[index].len > 0: return
  buf.parts[index] = data[FragmentHeader .. ^1]
  if buf.parts[index].len == 0: return   # (an empty tail: never sent)
  inc buf.have
  if buf.have < buf.count: return
  var packed = newStringOfCap(buf.count * FragmentPayload)
  for part in buf.parts: packed.add part
  # This and every older snapshot are done with.
  var stale: seq[int32]
  for k in s.frags.keys:
    if k <= seq: stale.add k
  for k in stale: s.frags.del(k)
  s.applyComplete(packed, game)

proc clientReceive(s: CoopSession, packet: Packet) =
  case packet.kind
  of ptConnectionAccept:
    # Also sent again when the lobby renumbers its seats.
    s.mySlot = int32(packet.assignedPlayerIndex)
    if s.phase == cpJoining: s.phase = cpClientLobby
  of ptCoopLobby:
    if s.phase in {cpJoining, cpClientLobby, cpEnded}:
      s.members = packet.lobbyMembers
      s.config = packet.lobbyConfig
      s.maxPlayers = packet.lobbyMaxPlayers.int
      if s.phase == cpJoining: s.phase = cpClientLobby
  of ptCoopStart:
    if packet.startRun > s.run and s.phase in {cpClientLobby, cpEnded}:
      s.run = packet.startRun
      s.members = packet.startMembers
      s.config = packet.startConfig
      s.phase = cpRunning
      s.startRequested = true
      s.ended = false
      s.lastApplied = 0
      s.profileApplied = 0
      s.snapshotAge = 0
      s.clientRing.clear()
      s.frags.clear()
      s.pendingActions.setLen(0)
      coopSendAction = clientSendAction
  of ptCoopEnd:
    if packet.endRun == s.run and s.phase == cpRunning:
      s.phase = cpEnded
      s.ended = true
      s.endReason = if packet.coopEndReason in 0'i32 .. int32(ord(high(CoopEndReason))):
                      CoopEndReason(packet.coopEndReason)
                    else: cerEnded
      s.endStats = packet.endStats
  else:
    discard

# ------------------------------------------------------------ per frame ----

proc pollCoopSession*(s: CoopSession, game: Game, dt: float32) {.moddable.} =
  ## Every frame, whatever the state: the network, the lobby, the run.
  if s.isNil or s.phase in {cpIdle, cpError}: return
  s.pingTimer += dt
  if s.pingTimer >= PingInterval and s.phase != cpJoining:
    s.pingTimer = 0
    s.nm.sendPing(0)
  s.bytesClock += dt
  if s.bytesClock >= 1.0'f32:
    s.bytesClock = 0
    s.bytesPerSecond = s.bytesSent
    s.bytesSent = 0
  if s.phase == cpJoining:
    s.joinTimer += dt
    s.joinRetryTimer += dt
    if s.joinTimer >= JoinTimeout:
      s.errorText = "No answer from the host"
      s.phase = cpError
      return
    if s.joinRetryTimer >= JoinRetry:
      s.joinRetryTimer = 0
      s.sendJoinRequest()
  for ev in s.nm.pollEvents():
    case ev.kind
    of neConnect:
      if s.isHost:
        if s.phase in {cpHostLobby, cpEnded}:
          s.rebuildMembers()
          s.broadcastLobby()
      else:
        s.mySlot = int32(ev.connectPlayerIndex)
        if s.phase == cpJoining: s.phase = cpClientLobby
    of neReceive:
      if s.isHost: s.hostReceive(game, ev.packet)
      else: s.clientReceive(ev.packet)
    of neDisconnect:
      if s.isHost:
        let slot = int32(ev.disconnectPlayerIndex)
        if s.phase in {cpRunning, cpEnding}:
          let i = s.memberIndex(slot)
          if i >= 0: s.members[i].connected = false   # the seat stays; the player is out
          s.playerLeft(game, slot)
        else:
          s.rebuildMembers()
          s.broadcastLobby()
      else:
        s.errorText = if ev.reason.len > 0: ev.reason else: "Disconnected"
        if s.phase == cpRunning:
          s.ended = true
          s.endReason = cerHostLeft
        s.phase = cpError
        return
  # Until main.nim has built the run (startRequested), `game` is still the
  # desktop's: nothing is sent from it or applied to it.
  let built = not game.isNil and not s.startRequested
  if s.isHost:
    case s.phase
    of cpHostLobby, cpEnded:
      s.lobbyTimer += dt
      if s.lobbyTimer >= LobbyInterval: s.broadcastLobby()
    of cpRunning:
      # The start goes out until every client has answered with input for
      # this run (a lost start would leave it in the lobby).
      s.startResendTimer += dt
      if s.startResendTimer >= StartResend:
        s.startResendTimer = 0
        for m in s.members:
          if m.slot != 0 and m.connected and s.intentSeqIn[m.slot] == 0:
            s.sendStart()
            break
      if built: s.hostSnapshots(game, dt)
    of cpEnding:
      # The results are up; snapshots still carry the last profile progress.
      if built: s.hostSnapshots(game, dt)
      s.endWait += dt
      s.flushEnds(force = s.endWait >= EndAckTimeout)
    else: discard
  else:
    if s.phase == cpRunning:
      if not built: return   # (the fragments wait in rawInbox for the mirror)
      s.snapshotAge += dt
      let inbox = move(s.nm.rawInbox)
      s.nm.rawInbox = @[]
      for data in inbox:
        s.acceptFragment(data, game)
      s.inputTimer += dt
      if s.inputTimer >= InputInterval:
        s.inputTimer = 0
        s.clientSendInput(game)
    else:
      s.nm.rawInbox.setLen(0)
