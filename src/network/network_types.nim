## Network Types and Packet Definitions for PvP Mode
## Defines all network packet structures and a newPacket helper.
## Serialization and supersnappy compression are handled in network.nim.

import raylib, times
import particle_types, ../types

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
    ptPlayerRespawn       # Server -> Client: Player respawned at a spawn point
    ptPickupTaken         # Server -> Client: A package was grabbed from a port

  NetworkRole* = enum
    nrNone, nrHost, nrClient

  PlayerInput* = object
    tick*: int
    playerIndex*: int
    moveDir*: Vector2
    shooting*: bool
    mousePos*: Vector2
    placingWall*: bool
    wallPos*: Vector2
    timestamp*: float32
    dt*: float32   ## Frame delta-time when this input was captured, needed for accurate replay
    dashSeq*: int      ## Cumulative dash presses this match. A count, not a pressed flag:
                       ## every later input carries it, so one lost datagram can't drop a dash.
    dashDir*: Vector2  ## Direction locked in when the latest dash was pressed

  PlayerStateNet* = object
    playerIndex*: int
    isActive*: bool
    pos*: Vector2
    vel*: Vector2
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
    deaths*: int
    streak*: int               ## Kills since last death (drives the root-prompt badge)
    dashTimer*: float32        ## Remote dash state, for the dash ring on other players
    dashCooldown*: float32
    shieldHits*: int           ## FIREWALL.SYS charge
    speedBoostTimer*: float32  ## TURBO.DLL
    fireRateBoostTimer*: float32 ## OVERCLOCK.SYS
    spreadTimer*: float32      ## FORK.EXE
    modSkin*: int16            ## MODS.EXE cosmetics (index + 1, 0 = none). Lobbies are
    modBulletSkin*: int16      ## matched by mod fingerprint, so indices agree on every side.
    radius*: float32           ## Body size (mods may change it)
    warp*: int32               ## Teleports so far this match. A rise means "snap here now":
                               ## a mod's teleport must not be smoothed away as drift.

  PortStateNet* = object
    ## One arena port. Positions are not sent: both sides derive them from the
    ## arena size (portLayout in pvp_game.nim), in the same order.
    kind*: int        ## PvPPackageKind ordinal of the package it holds / will drop next
    active*: bool     ## A package is sitting on it
    timer*: float32   ## Seconds until the next drop while inactive

  PvPStatsNet* = object
    ## End-of-match line for one player, sent with ptGameOver.
    kills*: int
    deaths*: int
    bestStreak*: int
    shotsFired*: int
    shotsHit*: int
    damageDealt*: float32
    pickupsTaken*: int

  BulletStateNet* = object
    id*: int
    pos*: Vector2
    vel*: Vector2
    radius*: float32
    damage*: float32
    fromPlayerIndex*: int
    isPiercing*: bool
    isExplosive*: bool
    isHoming*: bool
    bulletSkin*: int
    life*: float32    ## Seconds left before it expires
    color*: Color     ## A mod's colour (alpha 0 = the shooter's bullet skin)
    kind*: string     ## A mod's tag for its own bullets (match:spawnBullet's kind), "" = none
    pierce*: int32    ## Players it still passes through

  ModNetMsg* = object
    ## One mod message (match:request / match:broadcast). The sender keeps
    ## re-sending it, piggybacked on its inputs or snapshots, until the other
    ## side acknowledges its `seq`, so a lost datagram can't drop it.
    seq*: int32
    name*: string
    data*: string     ## JSON (plain data only)

  WallStateNet* = object
    pos*: Vector2
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
    ports*: seq[PortStateNet]
    modMsgs*: seq[ModNetMsg]   ## Host broadcasts some client has not acknowledged yet
    modAcks*: seq[int32]       ## Per player: the newest request seq the host has handled

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
    matchId*: int   ## Rematch generation. Receivers drop packets from an older match
                    ## (a rebroadcast ptGameOver still in flight must not end the new
                    ## one) and treat a newer one as "the host already restarted".
    modData*: string  ## Host: mods' match.data (JSON), on game start / snapshots /
                      ## game over; "" = not included (unchanged)
    case kind*: PacketType
    of ptConnectionRequest:
      version*: string
      playerName*: string
      requestSkinType*: int
      requestBulletSkinType*: int
      requestShapeType*: int
      requestParticleSkinType*: int
      # MODS.EXE: matched mod lobbies. The host refuses a client whose mod set
      # (fingerprint) differs from its own; modList only makes the refusal
      # readable.
      modFingerprint*: string
      modList*: string
      requestModSkin*: int16       ## equipped mod cosmetics (see PlayerStateNet)
      requestModBulletSkin*: int16
    of ptConnectionAccept, ptConnectionDenied:
      connectionReason*: string
      assignedPlayerIndex*: int
      connectedPlayers*: seq[ConnectedPlayerInfo]
    of ptPlayerListUpdate:
      updatedPlayers*: seq[ConnectedPlayerInfo]
    of ptGameStart:
      countdownTime*: float32
      teamsEnabled*: bool
      teamAssignments*: seq[int]
      gameConnectedPlayers*: seq[ConnectedPlayerInfo]
      pvpConfig*: PvPConfig    ## Host game-settings broadcast to all clients
      spawnPositions*: seq[Vector2]  ## Where each player starts (a mod may move spawns)
    of ptPlayerInput:
      input*: PlayerInput
      modMsgs*: seq[ModNetMsg]  ## This client's requests the host has not acknowledged
      modAck*: int32            ## The newest host broadcast this client has handled
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
      attackerIndex*: int   ## Who landed it (-1 = none), drives the shooter's hit confirm
      blocked*: bool        ## Absorbed by FIREWALL.SYS, no HP lost
    of ptPlayerDeath:
      deadPlayerIndex*: int
      killerIndex*: int     ## -1 when nobody gets the kill
      killerStreak*: int    ## Killer's streak INCLUDING this kill
      multiKill*: int       ## 1 = single, 2 = double fault, 3+ = triple fault
      firstBlood*: bool
      shutdownStreak*: int  ## Victim's streak that this kill ended (0 = none worth calling)
    of ptWallPlace:
      wall*: WallStateNet
    of ptWallDestroy:
      wallIndex*: int
    of ptGameOver:
      winnerIndex*: int
      winnerTeam*: int      ## PvPTeam ordinal. Explicit: clients used to parse it out of
                            ## a localized reason string, which failed outside English.
      endReason*: int       ## PvPEndReason ordinal
      finalStats*: seq[PvPStatsNet]
      endText*: string      ## A mod's own reason line (match:finish), "" = none
    of ptDisconnect:
      disconnectReason*: string
    of ptPing, ptPong:
      pingId*: int
      sendTime*: float32
    of ptPlayerRespawn:
      respawnIndex*: int
      respawnPos*: Vector2
    of ptPickupTaken:
      pickupPort*: int
      pickupKind*: int      ## PvPPackageKind ordinal
      pickupTaker*: int
      pickupApplied*: bool  ## false: a mod took it in place of its effect (pvpPickup)

proc newPacket*(kind: PacketType, tick: int = 0): Packet {.inline.} =
  ## Create a Packet with the given kind, tick, and current timestamp.
  Packet(kind: kind, tick: tick, timestamp: epochTime().float32)
