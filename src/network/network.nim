## Core Networking Layer for PvP Mode
## Handles UDP socket communication using blocking sockets with timeouts

import net, nativesockets, network_types, times, strutils, json

const
  DEFAULT_PORT* = 7777
  MAX_PACKET_SIZE = 8192
  NETWORK_VERSION* = "1.0.0"
  DISCONNECT_TIMEOUT* = 2.5  # Seconds without receiving any packet before considering disconnected

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
      remoteAddress*: string
      # Remote player's cosmetics (only for host receiving connection)
      remoteSkinType*: int
      remoteBulletSkinType*: int
      remoteShapeType*: int
      remoteParticleSkinType*: int
    of neReceive:
      packet*: Packet
    of neDisconnect:
      reason*: string
    else:
      discard
    
  NetworkManager* = ref object
    role*: NetworkRole
    socket*: Socket
    remoteAddr*: string
    remotePort*: Port
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
    isConnected: false,
    lastPingTime: currentTime,
    lastPongTime: currentTime,
    lastReceiveTime: currentTime,  # Initialize to current time to prevent false timeout
    latency: 0,
    pendingEvents: @[],
    timeoutDisabled: false  # NEW: Initialize timeout check as enabled
  )

proc initHost*(nm: NetworkManager, port: int = DEFAULT_PORT) =
  ## Initialize as host (server) - bind to port and wait for connection
  nm.role = nrHost
  nm.socket = newSocket(Domain.AF_INET, SockType.SOCK_DGRAM, Protocol.IPPROTO_UDP, buffered = false)
  nm.socket.setSockOpt(OptReuseAddr, true)
  nm.socket.getFd().setBlocking(false)  # Set non-blocking mode
  nm.socket.bindAddr(Port(port))
  echo "[NETWORK] Host initialized on port ", port

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
  
  let data = serializePacket(packet)
  try:
    nm.socket.sendTo(host, Port(port), data)
    echo "[NETWORK] Connection request sent to ", host, ":", port
  except:
    echo "[NETWORK] Failed to send connection request: ", getCurrentExceptionMsg()

proc sendPacket*(nm: NetworkManager, packet: Packet) =
  ## Send a packet to the remote peer
  if not nm.isConnected and nm.role == nrClient:
    # For client, always send to stored remote address
    let data = serializePacket(packet)
    try:
      nm.socket.sendTo(nm.remoteAddr, nm.remotePort, data)
    except:
      echo "[NETWORK] Failed to send packet: ", getCurrentExceptionMsg()
  elif nm.isConnected and nm.role == nrHost:
    # For host, send to connected client
    let data = serializePacket(packet)
    try:
      nm.socket.sendTo(nm.remoteAddr, nm.remotePort, data)
    except:
      echo "[NETWORK] Failed to send packet: ", getCurrentExceptionMsg()
  elif nm.isConnected and nm.role == nrClient:
    # For connected client, send to host
    let data = serializePacket(packet)
    try:
      nm.socket.sendTo(nm.remoteAddr, nm.remotePort, data)
    except:
      echo "[NETWORK] Failed to send packet: ", getCurrentExceptionMsg()

type
  CosmeticsCallback* = proc(): tuple[skinType, bulletSkinType, shapeType, particleSkinType: int]

proc pollEvents*(nm: NetworkManager, getCosmeticsCallback: CosmeticsCallback = nil): seq[NetworkEvent] =
  ## Poll for network events (non-blocking)
  result = nm.pendingEvents
  nm.pendingEvents = @[]
  
  # Check for timeout-based disconnection (unless disabled)
  if nm.isConnected and not nm.timeoutDisabled:
    let currentTime = epochTime()
    let timeSinceLastReceive = currentTime - nm.lastReceiveTime
    
    if timeSinceLastReceive > DISCONNECT_TIMEOUT:
      nm.isConnected = false
      result.add(NetworkEvent(kind: neDisconnect, reason: "Connection timeout"))
      return result  # Don't process more events after disconnect
  
  # Try to receive packets (non-blocking with timeout)
  if nm.socket != nil:
    try:
      var data = ""
      var address = ""
      var port: Port
      
      # Try to receive data (non-blocking - will throw if no data available)
      let bytesRead = nm.socket.recvFrom(data, MAX_PACKET_SIZE, address, port)
      
      if bytesRead > 0:
        # Update last receive time whenever we get ANY packet
        nm.lastReceiveTime = epochTime()
        
        try:
          let packet = deserializePacket(data)
          
          # Handle connection for host
          if nm.role == nrHost and not nm.isConnected:
            if packet.packetType == ptConnectionRequest:
              # Accept connection
              nm.remoteAddr = address
              nm.remotePort = port
              nm.isConnected = true
              nm.lastReceiveTime = epochTime()  # Reset timer on connection
              nm.timeoutDisabled = false  # Ensure timeout is enabled after connection
              
              # Get host's cosmetics if callback provided
              var hostCosmetics = (skinType: 0, bulletSkinType: 0, shapeType: 0, particleSkinType: 0)
              if getCosmeticsCallback != nil:
                hostCosmetics = getCosmeticsCallback()
              
              # Send acceptance with host's cosmetics
              var acceptPacket = Packet(kind: ptConnectionAccept)
              acceptPacket.packetType = ptConnectionAccept
              acceptPacket.tick = 0
              acceptPacket.timestamp = epochTime()
              acceptPacket.connectionReason = "Connection accepted"
              acceptPacket.assignedPlayerIndex = 1  # Host is 0, client is 1
              acceptPacket.hostSkinType = hostCosmetics.skinType
              acceptPacket.hostBulletSkinType = hostCosmetics.bulletSkinType
              acceptPacket.hostShapeType = hostCosmetics.shapeType
              acceptPacket.hostParticleSkinType = hostCosmetics.particleSkinType
              nm.sendPacket(acceptPacket)
              
              # Store client cosmetics in the network event so game can apply them
              result.add(NetworkEvent(
                kind: neConnect, 
                remoteAddress: address,
                remoteSkinType: packet.requestSkinType,
                remoteBulletSkinType: packet.requestBulletSkinType,
                remoteShapeType: packet.requestShapeType,
                remoteParticleSkinType: packet.requestParticleSkinType
              ))
              echo "[NETWORK] Client connected from ", address, ":", port.int
          
          # Handle connection acceptance for client
          elif nm.role == nrClient and not nm.isConnected:
            if packet.packetType == ptConnectionAccept:
              nm.isConnected = true
              nm.lastReceiveTime = epochTime()  # Reset timer on connection
              nm.timeoutDisabled = false  # Ensure timeout is enabled after connection
              # Client receives host's cosmetics in the acceptance packet
              result.add(NetworkEvent(
                kind: neConnect, 
                remoteAddress: address,
                remoteSkinType: packet.hostSkinType,
                remoteBulletSkinType: packet.hostBulletSkinType,
                remoteShapeType: packet.hostShapeType,
                remoteParticleSkinType: packet.hostParticleSkinType
              ))
          
          # Handle regular packets
          if nm.isConnected:
            case packet.packetType
            of ptDisconnect:
              nm.isConnected = false
              result.add(NetworkEvent(kind: neDisconnect, reason: packet.disconnectReason))
            of ptPong:
              nm.lastPongTime = epochTime()
              nm.latency = (nm.lastPongTime - packet.sendTime).float32 * 1000.0  # ms
            of ptPing:
              # Respond with pong
              var pongPacket = Packet(kind: ptPong)
              pongPacket.packetType = ptPong
              pongPacket.tick = packet.tick
              pongPacket.timestamp = epochTime()
              pongPacket.pingId = packet.pingId
              pongPacket.sendTime = packet.sendTime
              nm.sendPacket(pongPacket)
            else:
              result.add(NetworkEvent(kind: neReceive, packet: packet))
          
        except JsonParsingError:
          echo "[NETWORK] Failed to parse packet"
        except:
          echo "[NETWORK] Error processing packet: ", getCurrentExceptionMsg()
    except OSError:
      # Expected for non-blocking socket when no data is available
      # EWOULDBLOCK or EAGAIN on Windows/Unix
      discard
    except:
      # Other unexpected errors
      let msg = getCurrentExceptionMsg()
      if msg != "" and not msg.contains("would block"):
        echo "[NETWORK] Unexpected error in pollEvents: ", msg

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

proc enableTimeoutCheck*(nm: NetworkManager) =
  ## Re-enable timeout checking after countdown completes
  ## Reset the timer to prevent false timeout from countdown period
  nm.lastReceiveTime = epochTime()
  nm.timeoutDisabled = false
