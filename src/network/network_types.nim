## Network Types and Packet Definitions for PvP Mode
## Defines all network packet structures
## Serialization handled by flatty_network.nim

import raylib, ../types

type
  PacketType* = enum
    ptConnectionRequest    # Client -> Server: Request to join
    ptConnectionAccept     # Server -> Client: Connection accepted
    ptConnectionDenied     # Server -> Client: Connection denied (full/version mismatch)
    ptGameStart           # Server -> Both: Game starting countdown
    ptPlayerInput         # Client -> Server: Player input data
    ptGameState           # Server -> Client: Full game state snapshot
    ptBulletSpawn         # Server -> Client: New bullet created
    ptBulletDestroy       # Server -> Client: Bullet destroyed
    ptPlayerDamage        # Server -> Client: Player took damage
    ptPlayerDeath         # Server -> Client: Player died
    ptPowerUpSpawn        # Server -> Client: Power-up spawned
    ptPowerUpCollect      # Server -> Client: Power-up collected
    ptWallPlace           # Server -> Client: Wall placed
    ptWallDestroy         # Server -> Client: Wall destroyed
    ptGameOver            # Server -> Both: Game ended
    ptDisconnect          # Either -> Other: Player disconnecting
    ptPing                # Both: Latency measurement
    ptPong                # Both: Latency response
    
  NetworkRole* = enum
    nrNone, nrHost, nrClient
    
  ConnectionState* = enum
    csDisconnected
    csConnecting
    csConnected
    csInGame
    
  PlayerInput* = object
    tick*: int
    playerIndex*: int  # Which player this input is from
    moveDir*: Vector2f
    shooting*: bool
    mousePos*: Vector2f
    placingWall*: bool
    wallPos*: Vector2f
    timestamp*: float32
    
  PlayerStateNet* = object
    playerIndex*: int  # Player index in the game
    isActive*: bool  # Whether this player slot is filled
    pos*: Vector2f
    vel*: Vector2f
    hp*: float32
    maxHp*: float32
    coins*: int
    kills*: int
    walls*: int
    damage*: float32
    speed*: float32
    invincibilityTimer*: float32
    teamId*: int  # Team assignment (0=None, 1=Red, 2=Blue, 3=Green, 4=Yellow)
    # Cosmetics
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
    fromPlayerIndex*: int  # 0-15
    isPiercing*: bool
    isExplosive*: bool
    isHoming*: bool
    bulletSkin*: int  # Bullet skin type
    
  WallStateNet* = object
    pos*: Vector2f
    radius*: float32
    hp*: float32
    maxHp*: float32
    ownerIndex*: int  # 0-15
    
  NetworkGameState* = object
    tick*: int
    timestamp*: float32
    maxPlayers*: int  # Total player slots (2-16)
    players*: seq[PlayerStateNet]  # Dynamic player list
    bullets*: seq[BulletStateNet]
    walls*: seq[WallStateNet]
    
  Packet* = object
    packetType*: PacketType
    tick*: int
    timestamp*: float32
    case kind*: PacketType
    of ptConnectionRequest:
      version*: string
      playerName*: string
      # Cosmetics from connecting player
      requestSkinType*: int
      requestBulletSkinType*: int
      requestShapeType*: int
      requestParticleSkinType*: int
    of ptConnectionAccept, ptConnectionDenied:
      connectionReason*: string
      assignedPlayerIndex*: int
      maxPlayersInRoom*: int  # Total max players for this room
      # All currently connected players' cosmetics
      connectedPlayers*: seq[tuple[
        index: int,
        skinType: int,
        bulletSkinType: int,
        shapeType: int,
        particleSkinType: int,
        nickname: string
      ]]
    of ptGameStart:
      countdownTime*: float32
      teamsEnabled*: bool  # Whether team mode is active
      teamAssignments*: seq[int]  # Team assignment per player (0-4, where 0=None)
      # Include final list of all connected players so clients have the complete roster
      gameConnectedPlayers*: seq[tuple[
        index: int,
        skinType: int,
        bulletSkinType: int,
        shapeType: int,
        particleSkinType: int,
        nickname: string
      ]]
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
    of ptPowerUpSpawn:
      powerUpPos*: Vector2f
      spawnedPowerUpType*: int
    of ptPowerUpCollect:
      collectingPlayerIndex*: int
      collectedPowerUpType*: int
    of ptWallPlace:
      wall*: WallStateNet
    of ptWallDestroy:
      wallIndex*: int
    of ptGameOver:
      winnerIndex*: int  # -1 for draw
      reason*: string
    of ptDisconnect:
      disconnectReason*: string
    of ptPing, ptPong:
      pingId*: int
      sendTime*: float32
    else:
      discard
