## High-Performance Flatty Serializer for PvP game mode

import flatty
import ../types
import network_types

# Re-export network_types for compatibility
export network_types

proc serializePacketFast*(packet: Packet): string {.inline.} =
  packet.toFlatty()

proc deserializePacketFast*(data: string): Packet {.inline.} =
  data.fromFlatty(Packet)

proc estimatePacketSize*(packet: Packet): int =
  ## Estimate serialized size in bytes
  case packet.packetType
  of ptConnectionRequest:
    result = 200  # Name + version + cosmetics
  of ptConnectionAccept, ptConnectionDenied:
    result = 150
  of ptGameStart:
    result = 20
  of ptPlayerInput:
    result = 60  # Very small
  of ptGameState:
    let bulletCount = packet.state.bullets.len
    let wallCount = packet.state.walls.len
    result = 200 + (bulletCount * 50) + (wallCount * 40)
  of ptBulletSpawn:
    result = 80
  of ptBulletDestroy:
    result = 20
  of ptPlayerDamage:
    result = 30
  of ptPlayerDeath:
    result = 20
  of ptWallPlace:
    result = 50
  of ptWallDestroy:
    result = 20
  of ptGameOver:
    result = 100
  of ptDisconnect:
    result = 50
  of ptPing, ptPong:
    result = 24
  else:
    result = 50
