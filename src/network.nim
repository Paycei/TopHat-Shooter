## Core Networking Layer for PvP Mode
## Handles UDP socket communication using blocking sockets with timeouts

import net, nativesockets, network_types, times, strutils, json

const
  DEFAULT_PORT* = 7777
  MAX_PACKET_SIZE = 8192
  NETWORK_VERSION* = "1.0.0"
  CONNECTION_TIMEOUT = 10.0  # Seconds
  RECEIVE_TIMEOUT_MS = 1     # 1ms timeout for non-blocking behavior

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
    lastPingTime*: float32
    lastPongTime*: float32
    latency*: float32
    pendingEvents*: seq[NetworkEvent]
    
proc newNetworkManager*(): NetworkManager =
  result = NetworkManager(
    role: nrNone,
    socket: nil,
    remoteAddr: "",
    remotePort: Port(0),
    isConnected: false,
    lastPingTime: 0,
    lastPongTime: 0,
    latency: 0,
    pendingEvents: @[]
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

proc connectToHost*(nm: NetworkManager, host: string, port: int = DEFAULT_PORT) =
  ## Connect to a host as client
  nm.remoteAddr = host
  nm.remotePort = Port(port)
  
  # Send connection request
  var packet = Packet(kind: ptConnectionRequest)
  packet.packetType = ptConnectionRequest
  packet.tick = 0
  packet.timestamp = epochTime()
  packet.version = NETWORK_VERSION
  packet.playerName = "Player"
  
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

proc pollEvents*(nm: NetworkManager): seq[NetworkEvent] =
  ## Poll for network events (non-blocking)
  result = nm.pendingEvents
  nm.pendingEvents = @[]
  
  # Try to receive packets (non-blocking with timeout)
  if nm.socket != nil:
    try:
      var data = ""
      var address = ""
      var port: Port
      
      # Try to receive data (non-blocking - will throw if no data available)
      let bytesRead = nm.socket.recvFrom(data, MAX_PACKET_SIZE, address, port)
      
      if bytesRead > 0:
        try:
          let packet = deserializePacket(data)
          
          # Handle connection for host
          if nm.role == nrHost and not nm.isConnected:
            if packet.packetType == ptConnectionRequest:
              # Accept connection
              nm.remoteAddr = address
              nm.remotePort = port
              nm.isConnected = true
              
              # Send acceptance
              var acceptPacket = Packet(kind: ptConnectionAccept)
              acceptPacket.packetType = ptConnectionAccept
              acceptPacket.tick = 0
              acceptPacket.timestamp = epochTime()
              acceptPacket.connectionReason = "Connection accepted"
              acceptPacket.assignedPlayerIndex = 1  # Host is 0, client is 1
              nm.sendPacket(acceptPacket)
              
              result.add(NetworkEvent(kind: neConnect, remoteAddress: address))
              echo "[NETWORK] Client connected from ", address, ":", port.int
          
          # Handle connection acceptance for client
          elif nm.role == nrClient and not nm.isConnected:
            if packet.packetType == ptConnectionAccept:
              nm.isConnected = true
              result.add(NetworkEvent(kind: neConnect, remoteAddress: address))
              echo "[NETWORK] Connected to host"
          
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
    except OSError as e:
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
