## Network Types and Packet Definitions for PvP Mode
## Defines all network packet structures and serialization

import raylib, ../types, std/json, strutils

type
  PacketType* = enum
    ptConnectionRequest    # Client → Server: Request to join
    ptConnectionAccept     # Server → Client: Connection accepted
    ptConnectionDenied     # Server → Client: Connection denied (full/version mismatch)
    ptGameStart           # Server → Both: Game starting countdown
    ptPlayerInput         # Client → Server: Player input data
    ptGameState           # Server → Client: Full game state snapshot
    ptBulletSpawn         # Server → Client: New bullet created
    ptBulletDestroy       # Server → Client: Bullet destroyed
    ptPlayerDamage        # Server → Client: Player took damage
    ptPlayerDeath         # Server → Client: Player died
    ptPowerUpSpawn        # Server → Client: Power-up spawned
    ptPowerUpCollect      # Server → Client: Power-up collected
    ptWallPlace           # Server → Client: Wall placed
    ptWallDestroy         # Server → Client: Wall destroyed
    ptGameOver            # Server → Both: Game ended
    ptDisconnect          # Either → Other: Player disconnecting
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
    moveDir*: Vector2f
    shooting*: bool
    mousePos*: Vector2f
    placingWall*: bool
    wallPos*: Vector2f
    timestamp*: float32
    
  PlayerStateNet* = object
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
    # Cosmetics
    skinType*: int
    bulletSkinType*: int
    shapeType*: int
    particleSkinType*: int
    
  BulletStateNet* = object
    id*: int
    pos*: Vector2f
    vel*: Vector2f
    radius*: float32
    damage*: float32
    fromPlayerIndex*: int  # 0 or 1
    isPiercing*: bool
    isExplosive*: bool
    isHoming*: bool
    bulletSkin*: int  # Bullet skin type
    
  WallStateNet* = object
    pos*: Vector2f
    radius*: float32
    hp*: float32
    maxHp*: float32
    ownerIndex*: int  # 0 or 1
    
  NetworkGameState* = object
    tick*: int
    timestamp*: float32
    players*: array[2, PlayerStateNet]
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
      # Host's cosmetics sent back to client
      hostSkinType*: int
      hostBulletSkinType*: int
      hostShapeType*: int
      hostParticleSkinType*: int
    of ptGameStart:
      countdownTime*: float32
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

# Serialization functions (using JSON for simplicity)

proc serializeVector2f*(v: Vector2f): JsonNode =
  %* {"x": v.x, "y": v.y}

proc deserializeVector2f*(j: JsonNode): Vector2f =
  result.x = j["x"].getFloat()
  result.y = j["y"].getFloat()

proc serializePlayerInput*(input: PlayerInput): JsonNode =
  %* {
    "tick": input.tick,
    "moveDir": serializeVector2f(input.moveDir),
    "shooting": input.shooting,
    "mousePos": serializeVector2f(input.mousePos),
    "placingWall": input.placingWall,
    "wallPos": serializeVector2f(input.wallPos),
    "timestamp": input.timestamp
  }

proc deserializePlayerInput*(j: JsonNode): PlayerInput =
  result.tick = j["tick"].getInt()
  result.moveDir = deserializeVector2f(j["moveDir"])
  result.shooting = j["shooting"].getBool()
  result.mousePos = deserializeVector2f(j["mousePos"])
  result.placingWall = j["placingWall"].getBool()
  result.wallPos = deserializeVector2f(j["wallPos"])
  result.timestamp = j["timestamp"].getFloat()

proc serializePlayerState*(p: PlayerStateNet): JsonNode =
  %* {
    "pos": serializeVector2f(p.pos),
    "vel": serializeVector2f(p.vel),
    "hp": p.hp,
    "maxHp": p.maxHp,
    "coins": p.coins,
    "kills": p.kills,
    "walls": p.walls,
    "damage": p.damage,
    "speed": p.speed,
    "invincibilityTimer": p.invincibilityTimer,
    "skinType": p.skinType,
    "bulletSkinType": p.bulletSkinType,
    "shapeType": p.shapeType,
    "particleSkinType": p.particleSkinType
  }

proc deserializePlayerState*(j: JsonNode): PlayerStateNet =
  result.pos = deserializeVector2f(j["pos"])
  result.vel = deserializeVector2f(j["vel"])
  result.hp = j["hp"].getFloat()
  result.maxHp = j["maxHp"].getFloat()
  result.coins = j["coins"].getInt()
  result.kills = j["kills"].getInt()
  result.walls = j["walls"].getInt()
  result.damage = j["damage"].getFloat()
  result.speed = j["speed"].getFloat()
  result.invincibilityTimer = j["invincibilityTimer"].getFloat()
  result.skinType = j["skinType"].getInt()
  result.bulletSkinType = j["bulletSkinType"].getInt()
  result.shapeType = j["shapeType"].getInt()
  result.particleSkinType = j["particleSkinType"].getInt()

proc serializeBulletState*(b: BulletStateNet): JsonNode =
  %* {
    "id": b.id,
    "pos": serializeVector2f(b.pos),
    "vel": serializeVector2f(b.vel),
    "radius": b.radius,
    "damage": b.damage,
    "fromPlayerIndex": b.fromPlayerIndex,
    "isPiercing": b.isPiercing,
    "isExplosive": b.isExplosive,
    "isHoming": b.isHoming,
    "bulletSkin": b.bulletSkin
  }

proc deserializeBulletState*(j: JsonNode): BulletStateNet =
  result.id = j["id"].getInt()
  result.pos = deserializeVector2f(j["pos"])
  result.vel = deserializeVector2f(j["vel"])
  result.radius = j["radius"].getFloat()
  result.damage = j["damage"].getFloat()
  result.fromPlayerIndex = j["fromPlayerIndex"].getInt()
  result.isPiercing = j["isPiercing"].getBool()
  result.isExplosive = j["isExplosive"].getBool()
  result.isHoming = j["isHoming"].getBool()
  result.bulletSkin = j["bulletSkin"].getInt()

proc serializeWallState*(w: WallStateNet): JsonNode =
  %* {
    "pos": serializeVector2f(w.pos),
    "radius": w.radius,
    "hp": w.hp,
    "maxHp": w.maxHp,
    "ownerIndex": w.ownerIndex
  }

proc deserializeWallState*(j: JsonNode): WallStateNet =
  result.pos = deserializeVector2f(j["pos"])
  result.radius = j["radius"].getFloat()
  result.hp = j["hp"].getFloat()
  result.maxHp = j["maxHp"].getFloat()
  result.ownerIndex = j["ownerIndex"].getInt()

proc serializeGameState*(state: NetworkGameState): JsonNode =
  var bulletsArray = newJArray()
  for b in state.bullets:
    bulletsArray.add(serializeBulletState(b))
  
  var wallsArray = newJArray()
  for w in state.walls:
    wallsArray.add(serializeWallState(w))
  
  %* {
    "tick": state.tick,
    "timestamp": state.timestamp,
    "players": [
      serializePlayerState(state.players[0]),
      serializePlayerState(state.players[1])
    ],
    "bullets": bulletsArray,
    "walls": wallsArray
  }

proc deserializeGameState*(j: JsonNode): NetworkGameState =
  result.tick = j["tick"].getInt()
  result.timestamp = j["timestamp"].getFloat()
  result.players[0] = deserializePlayerState(j["players"][0])
  result.players[1] = deserializePlayerState(j["players"][1])
  
  result.bullets = @[]
  for bulletJson in j["bullets"]:
    result.bullets.add(deserializeBulletState(bulletJson))
  
  result.walls = @[]
  for wallJson in j["walls"]:
    result.walls.add(deserializeWallState(wallJson))

proc packetToJson*(packet: Packet): JsonNode =
  result = %* {
    "type": $packet.packetType,
    "tick": packet.tick,
    "timestamp": packet.timestamp
  }
  
  case packet.packetType
  of ptConnectionRequest:
    result["version"] = %packet.version
    result["playerName"] = %packet.playerName
    result["requestSkinType"] = %packet.requestSkinType
    result["requestBulletSkinType"] = %packet.requestBulletSkinType
    result["requestShapeType"] = %packet.requestShapeType
    result["requestParticleSkinType"] = %packet.requestParticleSkinType
  of ptConnectionAccept, ptConnectionDenied:
    result["reason"] = %packet.connectionReason
    result["assignedPlayerIndex"] = %packet.assignedPlayerIndex
    result["hostSkinType"] = %packet.hostSkinType
    result["hostBulletSkinType"] = %packet.hostBulletSkinType
    result["hostShapeType"] = %packet.hostShapeType
    result["hostParticleSkinType"] = %packet.hostParticleSkinType
  of ptGameStart:
    result["countdownTime"] = %packet.countdownTime
  of ptPlayerInput:
    result["input"] = serializePlayerInput(packet.input)
  of ptGameState:
    result["state"] = serializeGameState(packet.state)
  of ptBulletSpawn:
    result["bullet"] = serializeBulletState(packet.bullet)
  of ptBulletDestroy:
    result["bulletId"] = %packet.bulletId
  of ptPlayerDamage:
    result["playerIndex"] = %packet.damagedPlayerIndex
    result["damageAmount"] = %packet.damageAmount
    result["newHp"] = %packet.newHp
  of ptPlayerDeath:
    result["playerIndex"] = %packet.deadPlayerIndex
  of ptWallPlace:
    result["wall"] = serializeWallState(packet.wall)
  of ptWallDestroy:
    result["wallIndex"] = %packet.wallIndex
  of ptGameOver:
    result["winnerIndex"] = %packet.winnerIndex
    result["reason"] = %packet.reason
  of ptDisconnect:
    result["disconnectReason"] = %packet.disconnectReason
  of ptPing, ptPong:
    result["pingId"] = %packet.pingId
    result["sendTime"] = %packet.sendTime
  else:
    discard

proc serializePacket*(packet: Packet): string =
  $packetToJson(packet)

proc deserializePacket*(data: string): Packet =
  let j = parseJson(data)
  
  let packetTypeStr = j["type"].getStr()
  let packetType = parseEnum[PacketType](packetTypeStr)
  
  # Create packet with correct discriminator first
  case packetType
  of ptConnectionRequest:
    result = Packet(kind: ptConnectionRequest)
    result.version = j["version"].getStr()
    result.playerName = j["playerName"].getStr()
    result.requestSkinType = j["requestSkinType"].getInt()
    result.requestBulletSkinType = j["requestBulletSkinType"].getInt()
    result.requestShapeType = j["requestShapeType"].getInt()
    result.requestParticleSkinType = j["requestParticleSkinType"].getInt()
  of ptConnectionAccept, ptConnectionDenied:
    result = Packet(kind: packetType)
    result.connectionReason = j["reason"].getStr()
    result.assignedPlayerIndex = j["assignedPlayerIndex"].getInt()
    result.hostSkinType = j["hostSkinType"].getInt()
    result.hostBulletSkinType = j["hostBulletSkinType"].getInt()
    result.hostShapeType = j["hostShapeType"].getInt()
    result.hostParticleSkinType = j["hostParticleSkinType"].getInt()
  of ptGameStart:
    result = Packet(kind: ptGameStart)
    result.countdownTime = j["countdownTime"].getFloat()
  of ptPlayerInput:
    result = Packet(kind: ptPlayerInput)
    result.input = deserializePlayerInput(j["input"])
  of ptGameState:
    result = Packet(kind: ptGameState)
    result.state = deserializeGameState(j["state"])
  of ptBulletSpawn:
    result = Packet(kind: ptBulletSpawn)
    result.bullet = deserializeBulletState(j["bullet"])
  of ptBulletDestroy:
    result = Packet(kind: ptBulletDestroy)
    result.bulletId = j["bulletId"].getInt()
  of ptPlayerDamage:
    result = Packet(kind: ptPlayerDamage)
    result.damagedPlayerIndex = j["playerIndex"].getInt()
    result.damageAmount = j["damageAmount"].getFloat()
    result.newHp = j["newHp"].getFloat()
  of ptPlayerDeath:
    result = Packet(kind: ptPlayerDeath)
    result.deadPlayerIndex = j["playerIndex"].getInt()
  of ptPowerUpSpawn:
    result = Packet(kind: ptPowerUpSpawn)
    result.powerUpPos = deserializeVector2f(j["powerUpPos"])
    result.spawnedPowerUpType = j["powerUpType"].getInt()
  of ptPowerUpCollect:
    result = Packet(kind: ptPowerUpCollect)
    result.collectingPlayerIndex = j["playerIndex"].getInt()
    result.collectedPowerUpType = j["powerUpType"].getInt()
  of ptWallPlace:
    result = Packet(kind: ptWallPlace)
    result.wall = deserializeWallState(j["wall"])
  of ptWallDestroy:
    result = Packet(kind: ptWallDestroy)
    result.wallIndex = j["wallIndex"].getInt()
  of ptGameOver:
    result = Packet(kind: ptGameOver)
    result.winnerIndex = j["winnerIndex"].getInt()
    result.reason = j["reason"].getStr()
  of ptDisconnect:
    result = Packet(kind: ptDisconnect)
    result.disconnectReason = j["disconnectReason"].getStr()
  of ptPing, ptPong:
    result = Packet(kind: packetType)
    result.pingId = j["pingId"].getInt()
    result.sendTime = j["sendTime"].getFloat()
  
  # Set common fields
  result.packetType = packetType
  result.tick = j["tick"].getInt()
  result.timestamp = j["timestamp"].getFloat()
