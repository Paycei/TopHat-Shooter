## Core Networking Layer for PvP Mode

import net, nativesockets, network_types, flatty_network, times, strutils

const
  DEFAULT_PORT* = 7777
  MAX_PACKET_SIZE = 8192
  NETWORK_VERSION* = "1.0.2"
  DISCONNECT_TIMEOUT* = 2.5  # Seconds without receiving any packet before considering disconnected
  MAX_PACKETS_PER_POLL = 100  # Maximum packets to process per poll (prevent infinite loop)

type
  NetworkEventKind* = enum
    neNone
    neConnect
    neReceive
    neDisconnect
    neError
  
  NetworkEvent* = object
    case kind*: NetworkEventKind
    of neConnect:
      connectPlayerIndex*: int  # Which player slot was assigned
      remoteAddress*: string
      # Remote player's cosmetics
      remoteSkinType*: int
      remoteBulletSkinType*: int
      remoteShapeType*: int
      remoteParticleSkinType*: int
    of neReceive:
      packet*: Packet
    of neDisconnect:
      disconnectPlayerIndex*: int  # Which player disconnected
      reason*: string
    else:
      discard
  
  ConnectedClient* = object
    address*: string
    port*: Port
    playerIndex*: int
    lastReceiveTime*: float64
    skinType*: int
    bulletSkinType*: int
    shapeType*: int
    particleSkinType*: int
    
  NetworkManager* = ref object
    role*: NetworkRole
    socket*: Socket
    # For clients (single remote connection)
    remoteAddr*: string
    remotePort*: Port
    # For hosts (multiple clients)
    clients*: seq[ConnectedClient]
    maxPlayers*: int  # Maximum number of players (2-16)
    isConnected*: bool
    lastPingTime*: float
    lastPongTime*: float
    lastReceiveTime*: float64  # Track last time we received ANY packet (MUST be float64 for precision)
    latency*: float32
    pendingEvents*: seq[NetworkEvent]
    timeoutDisabled*: bool  # Disable timeout check temporarily
    
proc newNetworkManager*(): NetworkManager =
  let currentTime = epochTime()
  result = NetworkManager(
    role: nrNone,
    socket: nil,
    remoteAddr: "",
    remotePort: Port(0),
    clients: @[],
    maxPlayers: 2,
    isConnected: false,
    lastPingTime: currentTime,
    lastPongTime: currentTime,
    lastReceiveTime: currentTime,  # Initialize to current time to prevent false timeout
    latency: 0,
    pendingEvents: @[],
    timeoutDisabled: false  # Initialize timeout check as enabled
  )

proc initHost*(nm: NetworkManager, port: int = DEFAULT_PORT, maxPlayers: int = 2) =
  ## Initialize as host (server) - bind to port and wait for connections
  nm.role = nrHost
  nm.maxPlayers = maxPlayers
  nm.clients = @[]
  nm.socket = newSocket(Domain.AF_INET, SockType.SOCK_DGRAM, Protocol.IPPROTO_UDP, buffered = false)
  nm.socket.setSockOpt(OptReuseAddr, true)
  nm.socket.getFd().setBlocking(false)  # Set non-blocking mode
  nm.socket.bindAddr(Port(port))
  echo "[NETWORK] Host initialized on port ", port, " for ", maxPlayers, " players"

proc initClient*(nm: NetworkManager) =
  ## Initialize as client - create socket for sending
  nm.role = nrClient
  nm.socket = newSocket(Domain.AF_INET, SockType.SOCK_DGRAM, Protocol.IPPROTO_UDP, buffered = false)
  nm.socket.setSockOpt(OptReuseAddr, true)
  nm.socket.getFd().setBlocking(false)  # Set non-blocking mode
  echo "[NETWORK] Client initialized"

proc connectToHost*(nm: NetworkManager, host: string, port: int = DEFAULT_PORT,
                   skinType: int = 0, bulletSkinType: int = 0, 
                   shapeType: int = 0, particleSkinType: int = 0) =
  ## Connect to a host as client, sending cosmetics
  nm.remoteAddr = host
  nm.remotePort = Port(port)
  
  # Send connection request with cosmetics
  var packet = Packet(kind: ptConnectionRequest)
  packet.packetType = ptConnectionRequest
  packet.tick = 0
  packet.timestamp = epochTime()
  packet.version = NETWORK_VERSION
  packet.playerName = "Player"
  packet.requestSkinType = skinType
  packet.requestBulletSkinType = bulletSkinType
  packet.requestShapeType = shapeType
  packet.requestParticleSkinType = particleSkinType
  
  let data = serializePacketFast(packet)  # Using flatty for speed!
  try:
    nm.socket.sendTo(host, Port(port), data)
    echo "[NETWORK] Connection request sent to ", host, ":", port
  except:
    echo "[NETWORK] Failed to send connection request: ", getCurrentExceptionMsg()

proc sendPacket*(nm: NetworkManager, packet: Packet) =
  ## Send a packet to the remote peer(s) using high-performance flatty serialization
  let data = serializePacketFast(packet)  # Using flatty for speed!
  
  if nm.role == nrHost:
    # Send to all connected clients
    for client in nm.clients:
      try:
        nm.socket.sendTo(client.address, client.port, data)
      except:
        echo "[NETWORK] Failed to send packet to ", client.address, ":", client.port.int
  elif nm.role == nrClient and nm.isConnected and nm.remoteAddr != "":
    # Send to host
    try:
      nm.socket.sendTo(nm.remoteAddr, nm.remotePort, data)
    except:
      echo "[NETWORK] Failed to send packet: ", getCurrentExceptionMsg()

proc sendPacketToPlayer*(nm: NetworkManager, packet: Packet, playerIndex: int) =
  ## Send a packet to a specific player (host only)
  if nm.role != nrHost:
    return
    
  let data = serializePacketFast(packet)
  for client in nm.clients:
    if client.playerIndex == playerIndex:
      try:
        nm.socket.sendTo(client.address, client.port, data)
      except:
        echo "[NETWORK] Failed to send packet to player ", playerIndex
      break

type
  CosmeticsCallback* = proc(): tuple[skinType, bulletSkinType, shapeType, particleSkinType: int]

proc pollEvents*(nm: NetworkManager, getCosmeticsCallback: CosmeticsCallback = nil): seq[NetworkEvent] =
  ## Poll for network events (non-blocking) - PROCESSES ALL AVAILABLE PACKETS
  result = nm.pendingEvents
  nm.pendingEvents = @[]
  
  # Check for timeout-based disconnection (unless disabled)
  if nm.role == nrHost:
    # Check each client for timeout
    let currentTime = epochTime()
    var disconnectedIndices: seq[int] = @[]
    
    if not nm.timeoutDisabled:
      for i, client in nm.clients:
        let timeSinceLastReceive = currentTime - client.lastReceiveTime
        if timeSinceLastReceive > DISCONNECT_TIMEOUT:
          disconnectedIndices.add(i)
          result.add(NetworkEvent(kind: neDisconnect, disconnectPlayerIndex: client.playerIndex, reason: "Connection timeout"))
          echo "[NETWORK] Player ", client.playerIndex, " timed out"
    
    # Remove disconnected clients (reverse order to maintain indices)
    for i in countdown(disconnectedIndices.high, 0):
      nm.clients.delete(disconnectedIndices[i])
    
    # Update connected status
    nm.isConnected = nm.clients.len > 0
    
  elif nm.role == nrClient and nm.isConnected and not nm.timeoutDisabled:
    let currentTime = epochTime()
    let timeSinceLastReceive = currentTime - nm.lastReceiveTime
    
    if timeSinceLastReceive > DISCONNECT_TIMEOUT:
      nm.isConnected = false
      result.add(NetworkEvent(kind: neDisconnect, disconnectPlayerIndex: 0, reason: "Connection timeout"))
      return result
  
  # CRITICAL FIX: Process ALL available packets in one frame to prevent queue buildup
  if nm.socket != nil:
    var packetsProcessed = 0
    
    while packetsProcessed < MAX_PACKETS_PER_POLL:
      try:
        var data = ""
        var address = ""
        var port: Port
        
        # Try to receive data (non-blocking - will throw if no data available)
        let bytesRead = nm.socket.recvFrom(data, MAX_PACKET_SIZE, address, port)
        
        if bytesRead <= 0:
          break  # No more packets available
        
        packetsProcessed += 1
        
        # Update last receive time whenever we get ANY packet
        nm.lastReceiveTime = epochTime()
        
        try:
          let packet = deserializePacketFast(data)  # Using flatty for speed!
          
          # Handle connection for host
          if nm.role == nrHost:
            if packet.packetType == ptConnectionRequest:
              # Check if already connected or room is full
              var alreadyConnected = false
              for client in nm.clients:
                if client.address == address and client.port == port:
                  alreadyConnected = true
                  break
              
              if alreadyConnected:
                continue  # Ignore duplicate connection requests
              
              if nm.clients.len >= nm.maxPlayers - 1:  # -1 because host counts as one player
                # Room is full, send denial
                var denyPacket = Packet(kind: ptConnectionDenied)
                denyPacket.packetType = ptConnectionDenied
                denyPacket.tick = 0
                denyPacket.timestamp = epochTime()
                denyPacket.connectionReason = "Room is full (" & $nm.clients.len & "/" & $(nm.maxPlayers - 1) & " clients)"
                denyPacket.assignedPlayerIndex = -1
                denyPacket.maxPlayersInRoom = nm.maxPlayers
                denyPacket.connectedPlayers = @[]
                let data = serializePacketFast(denyPacket)
                nm.socket.sendTo(address, port, data)
                echo "[NETWORK] Connection denied (room full - ", nm.clients.len, " active, max ", nm.maxPlayers - 1, "): ", address, ":", port.int
                continue
              
              # Assign player index (host is always 0)
              let assignedIndex = nm.clients.len + 1
              
              # Add new client
              let newClient = ConnectedClient(
                address: address,
                port: port,
                playerIndex: assignedIndex,
                lastReceiveTime: epochTime(),
                skinType: packet.requestSkinType,
                bulletSkinType: packet.requestBulletSkinType,
                shapeType: packet.requestShapeType,
                particleSkinType: packet.requestParticleSkinType
              )
              nm.clients.add(newClient)
              nm.isConnected = true
              
              # Build list of all connected players' cosmetics
              var connectedPlayers: seq[tuple[
                index: int,
                skinType: int,
                bulletSkinType: int,
                shapeType: int,
                particleSkinType: int
              ]] = @[]
              
              # Add host (player 0)
              var hostCosmetics = (skinType: 0, bulletSkinType: 0, shapeType: 0, particleSkinType: 0)
              if getCosmeticsCallback != nil:
                hostCosmetics = getCosmeticsCallback()
              connectedPlayers.add((
                index: 0,
                skinType: hostCosmetics.skinType,
                bulletSkinType: hostCosmetics.bulletSkinType,
                shapeType: hostCosmetics.shapeType,
                particleSkinType: hostCosmetics.particleSkinType
              ))
              
              # Add all other clients
              for client in nm.clients:
                connectedPlayers.add((
                  index: client.playerIndex,
                  skinType: client.skinType,
                  bulletSkinType: client.bulletSkinType,
                  shapeType: client.shapeType,
                  particleSkinType: client.particleSkinType
                ))
              
              # Send acceptance to the new client
              var acceptPacket = Packet(kind: ptConnectionAccept)
              acceptPacket.packetType = ptConnectionAccept
              acceptPacket.tick = 0
              acceptPacket.timestamp = epochTime()
              acceptPacket.connectionReason = "Connection accepted"
              acceptPacket.assignedPlayerIndex = assignedIndex
              acceptPacket.maxPlayersInRoom = nm.maxPlayers
              acceptPacket.connectedPlayers = connectedPlayers
              
              let acceptData = serializePacketFast(acceptPacket)
              nm.socket.sendTo(address, port, acceptData)
              
              # Generate connection event
              result.add(NetworkEvent(
                kind: neConnect,
                connectPlayerIndex: assignedIndex,
                remoteAddress: address,
                remoteSkinType: packet.requestSkinType,
                remoteBulletSkinType: packet.requestBulletSkinType,
                remoteShapeType: packet.requestShapeType,
                remoteParticleSkinType: packet.requestParticleSkinType
              ))
              echo "[NETWORK] Player ", assignedIndex, " connected from ", address, ":", port.int
          
          # Handle connection acceptance for client
          elif nm.role == nrClient and not nm.isConnected:
            if packet.packetType == ptConnectionAccept:
              nm.isConnected = true
              nm.lastReceiveTime = epochTime()  # Reset timer on connection
              nm.timeoutDisabled = false  # Ensure timeout is enabled after connection

              # Generate connection event to signal connection
              result.add(NetworkEvent(
                kind: neConnect,
                connectPlayerIndex: packet.assignedPlayerIndex,
                remoteAddress: address,
                remoteSkinType: 0,
                remoteBulletSkinType: 0,
                remoteShapeType: 0,
                remoteParticleSkinType: 0
              ))

              # ALSO generate a receive event so pvp_window can access the full packet data
              result.add(NetworkEvent(kind: neReceive, packet: packet))

              echo "[NETWORK] Connected as player ", packet.assignedPlayerIndex
            elif packet.packetType == ptConnectionDenied:
              echo "[NETWORK] Connection denied: ", packet.connectionReason
              result.add(NetworkEvent(kind: neDisconnect, disconnectPlayerIndex: 0, reason: packet.connectionReason))
          
          # Handle regular packets
          if nm.isConnected or nm.role == nrHost:
            # Update last receive time for the specific client (host only)
            if nm.role == nrHost:
              for i in 0..<nm.clients.len:
                if nm.clients[i].address == address and nm.clients[i].port == port:
                  nm.clients[i].lastReceiveTime = epochTime()
                  break
            
            case packet.packetType
            of ptDisconnect:
              if nm.role == nrHost:
                # Find and remove the disconnected client
                var disconnectedIndex = -1
                for i, client in nm.clients:
                  if client.address == address and client.port == port:
                    disconnectedIndex = i
                    result.add(NetworkEvent(kind: neDisconnect, disconnectPlayerIndex: client.playerIndex, reason: packet.disconnectReason))
                    echo "[NETWORK] Player ", client.playerIndex, " disconnected: ", packet.disconnectReason
                    break
                if disconnectedIndex >= 0:
                  nm.clients.delete(disconnectedIndex)
                  nm.isConnected = nm.clients.len > 0
              else:
                # Client disconnecting from host
                nm.isConnected = false
                result.add(NetworkEvent(kind: neDisconnect, disconnectPlayerIndex: 0, reason: packet.disconnectReason))
                return result  # Exit immediately on disconnect
            of ptPong:
              nm.lastPongTime = epochTime()
              # Calculate latency with bounds checking to prevent overflow and negative values
              let rawLatency = (nm.lastPongTime - packet.sendTime.float) * 1000.0  # ms
              # Clamp to reasonable range: 0-9999ms (negative = clock skew, >9999 = connection issues)
              nm.latency = max(0.0, min(rawLatency, 9999.0)).float32
            of ptPing:
              # Respond with pong
              var pongPacket = Packet(kind: ptPong)
              pongPacket.packetType = ptPong
              pongPacket.tick = packet.tick
              pongPacket.timestamp = epochTime()
              pongPacket.pingId = packet.pingId
              pongPacket.sendTime = packet.sendTime
              if nm.role == nrHost:
                # Send only to the client who sent the ping
                let data = serializePacketFast(pongPacket)
                nm.socket.sendTo(address, port, data)
              else:
                nm.sendPacket(pongPacket)
            else:
              result.add(NetworkEvent(kind: neReceive, packet: packet))
        except:
          echo "[NETWORK] Error processing packet: ", getCurrentExceptionMsg()
          
      except OSError:
        # Expected for non-blocking socket when no data is available
        break  # Exit loop, no more packets
      except:
        # Other unexpected errors
        let msg = getCurrentExceptionMsg()
        if msg != "" and not msg.contains("would block"):
          echo "[NETWORK] Unexpected error in pollEvents: ", msg
        break  # Exit on error
    
    # Debug info if we hit the packet limit
    if packetsProcessed >= MAX_PACKETS_PER_POLL:
      echo "[NETWORK] Warning: Hit packet processing limit (", MAX_PACKETS_PER_POLL, " packets/frame)"

proc sendPing*(nm: NetworkManager, pingId: int) =
  ## Send a ping to measure latency
  var packet = Packet(kind: ptPing)
  packet.packetType = ptPing
  packet.tick = 0
  packet.timestamp = epochTime()
  packet.pingId = pingId
  packet.sendTime = epochTime()
  nm.lastPingTime = epochTime()
  nm.sendPacket(packet)

proc sendGameStart*(nm: NetworkManager, countdownTime: float32 = 3.0,
                    connectedPlayers: seq[tuple[index: int, skinType, bulletSkinType, shapeType, particleSkinType: int]] = @[]) =
  ## Send game start signal to all connected players (host only)
  if nm.role != nrHost:
    return

  var packet = Packet(kind: ptGameStart)
  packet.packetType = ptGameStart
  packet.tick = 0
  packet.timestamp = epochTime()
  packet.countdownTime = countdownTime
  packet.gameConnectedPlayers = connectedPlayers
  nm.sendPacket(packet)
  echo "[NETWORK] Game start signal sent to all clients with ", connectedPlayers.len, " players"

proc disconnect*(nm: NetworkManager, reason: string = "User disconnected") =
  ## Disconnect from the remote peer
  if nm.isConnected:
    var packet = Packet(kind: ptDisconnect)
    packet.packetType = ptDisconnect
    packet.tick = 0
    packet.timestamp = epochTime()
    packet.disconnectReason = reason
    nm.sendPacket(packet)
    nm.isConnected = false
    echo "[NETWORK] Disconnected: ", reason

proc cleanup*(nm: NetworkManager) =
  ## Clean up network resources
  if nm.socket != nil:
    nm.socket.close()
  nm.isConnected = false
  echo "[NETWORK] Cleanup complete"

proc getLatency*(nm: NetworkManager): float32 =
  ## Get current latency in milliseconds
  result = nm.latency

proc isHost*(nm: NetworkManager): bool =
  nm.role == nrHost

proc isClient*(nm: NetworkManager): bool =
  nm.role == nrClient

proc resetReceiveTimer*(nm: NetworkManager) =
  ## Reset the lastReceiveTime to prevent false timeout detection
  ## Call this when starting a game to reset the timer
  ## Also temporarily disables timeout check for countdown period
  nm.lastReceiveTime = epochTime()
  nm.timeoutDisabled = true  # Disable timeout during countdown
  
  # Also reset all client timers if host
  if nm.role == nrHost:
    for i in 0..<nm.clients.len:
      nm.clients[i].lastReceiveTime = epochTime()

proc enableTimeoutCheck*(nm: NetworkManager) =
  ## Re-enable timeout checking after countdown completes
  ## Reset the timer to prevent false timeout from countdown period
  nm.lastReceiveTime = epochTime()
  nm.timeoutDisabled = false
  
  # Also reset all client timers if host
  if nm.role == nrHost:
    for i in 0..<nm.clients.len:
      nm.clients[i].lastReceiveTime = epochTime()

proc getConnectedPlayerCount*(nm: NetworkManager): int =
  ## Get the number of connected players (including host if host)
  if nm.role == nrHost:
    return nm.clients.len + 1  # +1 for host
  elif nm.isConnected:
    return 2  # Client + host (we only know we're connected to host)
  else:
    return 0

proc getMaxPlayers*(nm: NetworkManager): int =
  ## Get the maximum number of players for this room
  return nm.maxPlayers
