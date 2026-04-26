## Network Types and Packet Definitions for PvP Mode
## Defines all network packet structures and a newPacket helper.
## Serialization and supersnappy compression are handled in network.nim.

import raylib, ../types, times

type
  PacketType* = enum
    ptConnectionRequest    # Client -> Server: Request to join
    ptConnectionAccept     # Server -> Client: Connection accepted
    ptConnectionDenied     # Server -> Client: Connection denied (full/version mismatch)
    ptPlayerListUpdate     # Server -> Client: Updated list of connected players
    ptGameStart           # Server -> Both: Game starting countdown
    ptPlayerInput         # Client -> Server: Player input data
    ptGameState           # Server -> Client: Full game state snapshot
    ptBulletSpawn         # Server -> Client: New bullet created
    ptBulletDestroy       # Server -> Client: Bullet destroyed
    ptPlayerDamage        # Server -> Client: Player took damage
    ptPlayerDeath         # Server -> Client: Player died
    ptWallPlace           # Server -> Client: Wall placed
    ptWallDestroy         # Server -> Client: Wall destroyed
    ptGameOver            # Server -> Both: Game ended
    ptDisconnect          # Either -> Other: Player disconnecting
    ptPing                # Both: Latency measurement
    ptPong                # Both: Latency response

  NetworkRole* = enum
    nrNone, nrHost, nrClient

  PlayerInput* = object
    tick*: int
    playerIndex*: int
    moveDir*: Vector2f
    shooting*: bool
    mousePos*: Vector2f
    placingWall*: bool
    wallPos*: Vector2f
    timestamp*: float32
    dt*: float32   ## Frame delta-time when this input was captured; needed for accurate replay

  PlayerStateNet* = object
    playerIndex*: int
    isActive*: bool
    pos*: Vector2f
    vel*: Vector2f
    hp*: float32
    maxHp*: float32
    coins*: int
    kills*: int
    walls*: int
    damage*: float32
    speed*: float32
    fireRate*: float32
    bulletSpeed*: float32
    invincibilityTimer*: float32
    teamId*: int
    skinType*: int
    bulletSkinType*: int
    shapeType*: int
    particleSkinType*: int
    nickname*: string

  BulletStateNet* = object
    id*: int
    pos*: Vector2f
    vel*: Vector2f
    radius*: float32
    damage*: float32
    fromPlayerIndex*: int
    isPiercing*: bool
    isExplosive*: bool
    isHoming*: bool
    bulletSkin*: int

  WallStateNet* = object
    pos*: Vector2f
    radius*: float32
    hp*: float32
    maxHp*: float32
    ownerIndex*: int

  NetworkGameState* = object
    tick*: int
    timestamp*: float32
    maxPlayers*: int
    players*: seq[PlayerStateNet]
    bullets*: seq[BulletStateNet]
    walls*: seq[WallStateNet]

  ConnectedPlayerInfo* = tuple[
    index: int,
    skinType: int,
    bulletSkinType: int,
    shapeType: int,
    particleSkinType: int,
    nickname: string
  ]

  Packet* = object
    tick*: int
    timestamp*: float32
    case kind*: PacketType
    of ptConnectionRequest:
      version*: string
      playerName*: string
      requestSkinType*: int
      requestBulletSkinType*: int
      requestShapeType*: int
      requestParticleSkinType*: int
    of ptConnectionAccept, ptConnectionDenied:
      connectionReason*: string
      assignedPlayerIndex*: int
      maxPlayersInRoom*: int
      connectedPlayers*: seq[ConnectedPlayerInfo]
    of ptPlayerListUpdate:
      updatedPlayers*: seq[ConnectedPlayerInfo]
    of ptGameStart:
      countdownTime*: float32
      teamsEnabled*: bool
      teamAssignments*: seq[int]
      gameConnectedPlayers*: seq[ConnectedPlayerInfo]
      pvpConfig*: PvPConfig    ## Host game-settings broadcast to all clients
    of ptPlayerInput:
      input*: PlayerInput
    of ptGameState:
      state*: NetworkGameState
    of ptBulletSpawn:
      bullet*: BulletStateNet
    of ptBulletDestroy:
      bulletId*: int
    of ptPlayerDamage:
      damagedPlayerIndex*: int
      damageAmount*: float32
      newHp*: float32
    of ptPlayerDeath:
      deadPlayerIndex*: int
    of ptWallPlace:
      wall*: WallStateNet
    of ptWallDestroy:
      wallIndex*: int
    of ptGameOver:
      winnerIndex*: int
      reason*: string
    of ptDisconnect:
      disconnectReason*: string
    of ptPing, ptPong:
      pingId*: int
      sendTime*: float32
    else:
      discard

proc newPacket*(kind: PacketType, tick: int = 0): Packet {.inline.} =
  ## Create a Packet with the given kind, tick, and current timestamp.
  Packet(kind: kind, tick: tick, timestamp: epochTime().float32)
