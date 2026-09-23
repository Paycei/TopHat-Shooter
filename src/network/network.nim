## Core Networking Layer for PvP Mode

import net, nativesockets, flatty, supersnappy, times, strutils, math
import network_types, ../types

const
  DEFAULT_PORT* = 7777
  MAX_PACKET_SIZE = 8192
  NETWORK_VERSION* = "2.1.0"
  DISCONNECT_TIMEOUT* = 2.5
  MAX_PACKETS_PER_POLL = 100
  PACKET_MAGIC = "THS1"

# Serialization (flatty payloads wrapped with supersnappy compression)

proc serialize(packet: Packet): string {.inline.} =
  PACKET_MAGIC & supersnappy.compress(packet.toFlatty())

proc deserialize(data: string): Packet {.inline.} =
  if data.len <= PACKET_MAGIC.len or not data.startsWith(PACKET_MAGIC):
    raise newException(ValueError, "Unsupported packet encoding")
  supersnappy.uncompress(data[PACKET_MAGIC.len .. data.high]).fromFlatty(Packet)

type
  NetworkEventKind* = enum
    neConnect
    neReceive
    neDisconnect

  NetworkEvent* = object
    case kind*: NetworkEventKind
    of neConnect:
      connectPlayerIndex*: int
      remoteAddress*: string
      remoteSkinType*: int
      remoteBulletSkinType*: int
      remoteShapeType*: int
      remoteParticleSkinType*: int
    of neReceive:
      packet*: Packet
    of neDisconnect:
      disconnectPlayerIndex*: int
      reason*: string

  ConnectedClient* = object
    address*: string
    port*: Port
    playerIndex*: int
    lastReceiveTime*: float64
    skinType*: int
    bulletSkinType*: int
    shapeType*: int
    particleSkinType*: int
    nickname*: string

  NetworkManager* = ref object
    role*: NetworkRole
    socket*: Socket
    remoteAddr*: string
    remotePort*: Port
    clients*: seq[ConnectedClient]
    maxPlayers*: int
    isConnected*: bool
    lastReceiveTime*: float64
    latency*: float32
    timeoutDisabled*: bool
    hostNickname*: string
    matchStarted*: bool   ## Host: the game-start signal has gone out. Player
                          ## indices are frozen from then on (they key every
                          ## per-player array in the match), and no one may join.
    hostAddress*: string  ## Client: where the host actually answered from (set by
    hostPort*: Port       ## its connection accept). remoteAddr is whatever the
                          ## user typed -- possibly a hostname -- so it can't be
                          ## compared against a datagram's source.

# Construction

proc newNetworkManager*(): NetworkManager =
  NetworkManager(
    role: nrNone,
    socket: nil,
    remoteAddr: "",
    remotePort: Port(0),
    clients: @[],
    maxPlayers: 2,
    isConnected: false,
    lastReceiveTime: epochTime(),
    latency: 0,
    timeoutDisabled: false,
    hostNickname: "Player",
    matchStarted: false,
    hostAddress: "",
    hostPort: Port(0)
  )

proc initHost*(nm: NetworkManager, port: int = DEFAULT_PORT, maxPlayers: int = 2) =
  nm.role = nrHost
  nm.maxPlayers = maxPlayers
  nm.clients = @[]
  nm.socket = newSocket(Domain.AF_INET, SockType.SOCK_DGRAM, Protocol.IPPROTO_UDP, buffered = false)
  nm.socket.setSockOpt(OptReuseAddr, true)
  nm.socket.getFd().setBlocking(false)
  nm.socket.bindAddr(Port(port))
  echo "[NETWORK] Host initialized on port ", port, " for ", maxPlayers, " players"

proc initClient*(nm: NetworkManager) =
  nm.role = nrClient
  nm.socket = newSocket(Domain.AF_INET, SockType.SOCK_DGRAM, Protocol.IPPROTO_UDP, buffered = false)
  nm.socket.setSockOpt(OptReuseAddr, true)
  nm.socket.getFd().setBlocking(false)
  echo "[NETWORK] Client initialized"

proc connectToHost*(nm: NetworkManager, host: string, port: int = DEFAULT_PORT,
                   skinType: int = 0, bulletSkinType: int = 0,
                   shapeType: int = 0, particleSkinType: int = 0,
                   nickname: string = "Player") =
  nm.remoteAddr = host
  nm.remotePort = Port(port)
  var packet = newPacket(ptConnectionRequest)
  packet.version = NETWORK_VERSION
  packet.playerName = nickname
  packet.requestSkinType = skinType
  packet.requestBulletSkinType = bulletSkinType
  packet.requestShapeType = shapeType
  packet.requestParticleSkinType = particleSkinType
  try:
    nm.socket.sendTo(host, Port(port), serialize(packet))
    echo "[NETWORK] Connection request sent to ", host, ":", port
  except:
    echo "[NETWORK] Failed to send connection request: ", getCurrentExceptionMsg()

# Send helpers

proc sendPacket*(nm: NetworkManager, packet: Packet) =
  let data = serialize(packet)
  if nm.role == nrHost:
    for client in nm.clients:
      try: nm.socket.sendTo(client.address, client.port, data)
      except: echo "[NETWORK] Failed to send to ", client.address, ":", client.port.int
  elif nm.role == nrClient and nm.isConnected and nm.remoteAddr != "":
    try: nm.socket.sendTo(nm.remoteAddr, nm.remotePort, data)
    except: echo "[NETWORK] Failed to send packet: ", getCurrentExceptionMsg()

proc sendPing*(nm: NetworkManager, pingId: int) =
  var packet = newPacket(ptPing)
  packet.pingId = pingId
  # Store the epoch time wrapped to a 1000-second window rather than raw Unix
  # epoch, so float32 precision is sufficient (small number instead of ~1.7e9).
  # MUST match the time base the ptPong handler measures against (epochTime mod
  # 1000.0); otherwise the round-trip subtraction is garbage and latency reads 0.
  packet.sendTime = (epochTime() mod 1000.0).float32
  nm.sendPacket(packet)

proc sendGameStart*(nm: NetworkManager, countdownTime: float32 = 3.0,
                    connectedPlayers: seq[ConnectedPlayerInfo] = @[],
                    pvpConfig: PvPConfig = defaultPvPConfig()) =
  if nm.role != nrHost: return
  nm.matchStarted = true
  var packet = newPacket(ptGameStart)
  packet.countdownTime = countdownTime
  packet.gameConnectedPlayers = connectedPlayers
  packet.pvpConfig = pvpConfig
  nm.sendPacket(packet)
  echo "[NETWORK] Game start sent with ", connectedPlayers.len, " players"

proc disconnect*(nm: NetworkManager, reason: string = "User disconnected") =
  if nm.isConnected:
    var packet = newPacket(ptDisconnect)
    packet.disconnectReason = reason
    nm.sendPacket(packet)
    nm.isConnected = false
    echo "[NETWORK] Disconnected: ", reason

# Timeout helpers

proc resetReceiveTimer*(nm: NetworkManager) =
  nm.lastReceiveTime = epochTime()
  nm.timeoutDisabled = true
  if nm.role == nrHost:
    for i in 0..<nm.clients.len:
      nm.clients[i].lastReceiveTime = epochTime()

proc enableTimeoutCheck*(nm: NetworkManager) =
  nm.lastReceiveTime = epochTime()
  nm.timeoutDisabled = false
  if nm.role == nrHost:
    for i in 0..<nm.clients.len:
      nm.clients[i].lastReceiveTime = epochTime()

# Roster helpers (host)

type HostCosmeticsCallback = proc(): tuple[skinType, bulletSkinType, shapeType, particleSkinType: int]

proc buildRoster(nm: NetworkManager, getCosmeticsCallback: HostCosmeticsCallback): seq[ConnectedPlayerInfo] =
  var hostCosmetics = (skinType: 0, bulletSkinType: 0, shapeType: 0, particleSkinType: 0)
  if getCosmeticsCallback != nil:
    hostCosmetics = getCosmeticsCallback()
  result.add((index: 0,
    skinType: hostCosmetics.skinType,
    bulletSkinType: hostCosmetics.bulletSkinType,
    shapeType: hostCosmetics.shapeType,
    particleSkinType: hostCosmetics.particleSkinType,
    nickname: nm.hostNickname))
  for client in nm.clients:
    result.add((index: client.playerIndex,
      skinType: client.skinType,
      bulletSkinType: client.bulletSkinType,
      shapeType: client.shapeType,
      particleSkinType: client.particleSkinType,
      nickname: client.nickname))

proc nextFreePlayerIndex(nm: NetworkManager): int =
  ## Lowest client index (1+) nobody holds. `clients.len + 1` handed out an
  ## index that was still taken whenever an earlier player had left.
  result = 1
  while true:
    var taken = false
    for client in nm.clients:
      if client.playerIndex == result:
        taken = true
        break
    if not taken:
      return
    inc result

proc announceRosterAfterLeave(nm: NetworkManager, getCosmeticsCallback: HostCosmeticsCallback) =
  ## After a client leaves. In the lobby the remaining clients are renumbered
  ## 1..n and each is told its (possibly new) index: the match sizes its player
  ## arrays by player count, so a gap left some client's index past the end of
  ## them. Mid-match the indices key live per-player state, so they stay put
  ## and only the roster is refreshed.
  if nm.clients.len == 0:
    return
  if not nm.matchStarted:
    for i in 0..<nm.clients.len:
      nm.clients[i].playerIndex = i + 1
  let roster = nm.buildRoster(getCosmeticsCallback)
  if not nm.matchStarted:
    for client in nm.clients:
      var accept = newPacket(ptConnectionAccept)
      accept.connectionReason = "Player list updated"
      accept.assignedPlayerIndex = client.playerIndex
      accept.maxPlayersInRoom = nm.maxPlayers
      accept.connectedPlayers = roster
      try:
        nm.socket.sendTo(client.address, client.port, serialize(accept))
      except:
        echo "[NETWORK] Failed to send updated player index to ", client.address, ":", client.port.int
  else:
    var updatePacket = newPacket(ptPlayerListUpdate)
    updatePacket.updatedPlayers = roster
    let updateData = serialize(updatePacket)
    for client in nm.clients:
      try:
        nm.socket.sendTo(client.address, client.port, updateData)
      except:
        echo "[NETWORK] Failed to send player list update to ", client.address, ":", client.port.int

# Poll

proc pollEvents*(nm: NetworkManager,
                 getCosmeticsCallback: proc(): tuple[skinType, bulletSkinType, shapeType, particleSkinType: int] = nil): seq[NetworkEvent] =
  # Timeout checks
  if nm.role == nrHost:
    let now = epochTime()
    var disconnected: seq[int] = @[]
    if not nm.timeoutDisabled:
      for i, client in nm.clients:
        if now - client.lastReceiveTime > DISCONNECT_TIMEOUT:
          disconnected.add(i)
          result.add(NetworkEvent(kind: neDisconnect,
            disconnectPlayerIndex: client.playerIndex, reason: "Connection timeout"))
          echo "[NETWORK] Player ", client.playerIndex, " timed out"

    # Remove disconnected clients
    for i in countdown(disconnected.high, 0):
      nm.clients.delete(disconnected[i])
    nm.isConnected = nm.clients.len > 0

    # Send updated player list if anyone disconnected
    if disconnected.len > 0:
      nm.announceRosterAfterLeave(getCosmeticsCallback)

  elif nm.role == nrClient and nm.isConnected and not nm.timeoutDisabled:
    if epochTime() - nm.lastReceiveTime > DISCONNECT_TIMEOUT:
      nm.isConnected = false
      result.add(NetworkEvent(kind: neDisconnect,
        disconnectPlayerIndex: 0, reason: "Connection timeout"))
      return result

  if nm.socket == nil: return

  var processed = 0
  while processed < MAX_PACKETS_PER_POLL:
    var data, address = ""
    var port: Port
    try:
      if nm.socket.recvFrom(data, MAX_PACKET_SIZE, address, port) <= 0: break
    except OSError:
      break
    except:
      let msg = getCurrentExceptionMsg()
      if msg != "" and not msg.contains("would block"):
        echo "[NETWORK] Unexpected error in pollEvents: ", msg
      break

    processed += 1
    # A client's liveness clock is refreshed below, only by packets that pass
    # the host-source check; the host tracks each client's clock separately.
    if nm.role == nrHost:
      nm.lastReceiveTime = epochTime()

    var packet: Packet
    try:
      packet = deserialize(data)
    except:
      echo "[NETWORK] Error deserializing packet: ", getCurrentExceptionMsg()
      continue

    # Host: handle new connections
    if nm.role == nrHost and packet.kind == ptConnectionRequest:
      var alreadyConnected = false
      for client in nm.clients:
        if client.address == address and client.port == port:
          alreadyConnected = true; break
      if alreadyConnected: continue

      if packet.version != NETWORK_VERSION:
        var deny = newPacket(ptConnectionDenied)
        deny.connectionReason = "Version mismatch (host " & NETWORK_VERSION & ", client " & packet.version & ")"
        deny.assignedPlayerIndex = -1
        deny.maxPlayersInRoom = nm.maxPlayers
        deny.connectedPlayers = @[]
        nm.socket.sendTo(address, port, serialize(deny))
        echo "[NETWORK] Connection denied (version mismatch): host=", NETWORK_VERSION, " client=", packet.version
        continue

      if nm.matchStarted:
        # Player indices are frozen once the match starts; a joiner would get
        # an index the match has no slot for.
        var deny = newPacket(ptConnectionDenied)
        deny.connectionReason = "Match already in progress"
        deny.assignedPlayerIndex = -1
        deny.maxPlayersInRoom = nm.maxPlayers
        deny.connectedPlayers = @[]
        nm.socket.sendTo(address, port, serialize(deny))
        echo "[NETWORK] Connection denied (match in progress): ", address, ":", port.int
        continue

      if nm.clients.len >= nm.maxPlayers - 1:
        var deny = newPacket(ptConnectionDenied)
        deny.connectionReason = "Room is full (" & $nm.clients.len & "/" & $(nm.maxPlayers - 1) & " clients)"
        deny.assignedPlayerIndex = -1
        deny.maxPlayersInRoom = nm.maxPlayers
        deny.connectedPlayers = @[]
        nm.socket.sendTo(address, port, serialize(deny))
        echo "[NETWORK] Connection denied (full): ", address, ":", port.int
        continue

      let assignedIndex = nm.nextFreePlayerIndex()
      nm.clients.add(ConnectedClient(
        address: address, port: port,
        playerIndex: assignedIndex,
        lastReceiveTime: epochTime(),
        skinType: packet.requestSkinType,
        bulletSkinType: packet.requestBulletSkinType,
        shapeType: packet.requestShapeType,
        particleSkinType: packet.requestParticleSkinType,
        nickname: packet.playerName
      ))
      nm.isConnected = true

      # Build player roster for accept packet
      let roster = nm.buildRoster(getCosmeticsCallback)

      var accept = newPacket(ptConnectionAccept)
      accept.connectionReason = "Connection accepted"
      accept.assignedPlayerIndex = assignedIndex
      accept.maxPlayersInRoom = nm.maxPlayers
      accept.connectedPlayers = roster
      nm.socket.sendTo(address, port, serialize(accept))

      # Notify all OTHER existing clients about the updated player list
      if nm.clients.len > 1:  # Only if there are other clients besides the new one
        var updatePacket = newPacket(ptPlayerListUpdate)
        updatePacket.updatedPlayers = roster
        let updateData = serialize(updatePacket)
        for client in nm.clients:
          if client.playerIndex != assignedIndex:  # Don't send to the newly connected player
            try:
              nm.socket.sendTo(client.address, client.port, updateData)
            except:
              echo "[NETWORK] Failed to send player list update to ", client.address, ":", client.port.int

      result.add(NetworkEvent(kind: neConnect,
        connectPlayerIndex: assignedIndex,
        remoteAddress: address,
        remoteSkinType: packet.requestSkinType,
        remoteBulletSkinType: packet.requestBulletSkinType,
        remoteShapeType: packet.requestShapeType,
        remoteParticleSkinType: packet.requestParticleSkinType))
      echo "[NETWORK] Player ", assignedIndex, " connected from ", address, ":", port.int
      continue

    # Client: handle connection response
    if nm.role == nrClient and not nm.isConnected:
      if packet.kind == ptConnectionAccept:
        nm.isConnected = true
        nm.lastReceiveTime = epochTime()
        nm.timeoutDisabled = false
        nm.hostAddress = address
        nm.hostPort = port
        result.add(NetworkEvent(kind: neConnect,
          connectPlayerIndex: packet.assignedPlayerIndex,
          remoteAddress: address,
          remoteSkinType: 0, remoteBulletSkinType: 0,
          remoteShapeType: 0, remoteParticleSkinType: 0))
        result.add(NetworkEvent(kind: neReceive, packet: packet))
        echo "[NETWORK] Connected as player ", packet.assignedPlayerIndex
      elif packet.kind == ptConnectionDenied:
        echo "[NETWORK] Connection denied: ", packet.connectionReason
        result.add(NetworkEvent(kind: neDisconnect,
          disconnectPlayerIndex: 0, reason: packet.connectionReason))
      continue

    # Regular packets
    if not (nm.isConnected or nm.role == nrHost): continue

    if nm.role == nrHost:
      # Only connected clients may talk to the host, and only with the packets
      # a client actually sends. Anything else -- a stranger's datagram, or a
      # client forging host-only packets such as ptGameOver or ptPlayerDamage
      # -- used to be passed straight into the match.
      var senderIdx = -1
      for i in 0..<nm.clients.len:
        if nm.clients[i].address == address and nm.clients[i].port == port:
          nm.clients[i].lastReceiveTime = epochTime()
          senderIdx = i
          break
      if senderIdx < 0:
        continue
      if packet.kind notin {ptPlayerInput, ptDisconnect, ptPing, ptPong}:
        continue
      if packet.kind == ptPlayerInput:
        # A client drives its own player only, whatever index it claims.
        packet.input.playerIndex = nm.clients[senderIdx].playerIndex
    elif nm.role == nrClient:
      # Only the host speaks to a client. Anyone else's datagram -- a forged
      # ptGameOver, ptPlayerDamage or ptDisconnect -- is dropped.
      if address != nm.hostAddress or port != nm.hostPort:
        continue
      nm.lastReceiveTime = epochTime()

    case packet.kind
    of ptDisconnect:
      if nm.role == nrHost:
        for i, client in nm.clients:
          if client.address == address and client.port == port:
            let disconnectedIndex = client.playerIndex
            result.add(NetworkEvent(kind: neDisconnect,
              disconnectPlayerIndex: disconnectedIndex,
              reason: packet.disconnectReason))
            echo "[NETWORK] Player ", disconnectedIndex, " disconnected: ", packet.disconnectReason
            nm.clients.delete(i)
            nm.isConnected = nm.clients.len > 0

            # Send updated player list to all remaining clients
            nm.announceRosterAfterLeave(getCosmeticsCallback)
            break
      else:
        nm.isConnected = false
        result.add(NetworkEvent(kind: neDisconnect,
          disconnectPlayerIndex: 0, reason: packet.disconnectReason))
        return result
    of ptPong:
      let now = (epochTime() mod 1000.0).float32
      var elapsed = now - packet.sendTime
      # Handle the rare wrap-around (e.g. sendTime=999.99, now=0.01)
      if elapsed < 0: elapsed += 1000.0
      nm.latency = max(0.0, min(elapsed * 1000.0, 9999.0)).float32
    of ptPing:
      var pong = newPacket(ptPong, packet.tick)
      pong.pingId = packet.pingId
      pong.sendTime = packet.sendTime
      if nm.role == nrHost:
        nm.socket.sendTo(address, port, serialize(pong))
      else:
        nm.sendPacket(pong)
    else:
      result.add(NetworkEvent(kind: neReceive, packet: packet))

  if processed >= MAX_PACKETS_PER_POLL:
    echo "[NETWORK] Warning: hit packet limit (", MAX_PACKETS_PER_POLL, " packets/frame)"

# Cleanup / queries

proc cleanup*(nm: NetworkManager) =
  if nm.socket != nil: nm.socket.close()
  nm.isConnected = false
  echo "[NETWORK] Cleanup complete"

proc getLatency*(nm: NetworkManager): float32 = nm.latency
proc isHost*(nm: NetworkManager): bool = nm.role == nrHost
proc isClient*(nm: NetworkManager): bool = nm.role == nrClient

proc getConnectedPlayerCount*(nm: NetworkManager): int =
  if nm.role == nrHost: nm.clients.len + 1
  elif nm.isConnected: 2
  else: 0
