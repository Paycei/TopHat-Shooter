## Discord Rich Presence - Pure Nim Implementation (No DLL Required)
## Communicates with Discord via named pipes (IPC)

import json, times, os
when defined(windows):
  import winlean

type
  DiscordRichPresence* = object
    state*: string
    details*: string
    startTimestamp*: int64
    endTimestamp*: int64
    largeImageKey*: string
    largeImageText*: string
    smallImageKey*: string
    smallImageText*: string
    partyId*: string
    partySize*: int
    partyMax*: int

  DiscordClient* = ref object
    clientId: string
    pipe: File
    connected: bool
    nonce: int
    lastHeartbeat: float

const
  DISCORD_PIPE_NAME = when defined(windows): r"\\.\pipe\discord-ipc-0" else: "/tmp/discord-ipc-0"
  OPCODES = (
    HANDSHAKE: 0,
    FRAME: 1,
    CLOSE: 2,
    PING: 3,
    PONG: 4
  )

proc newDiscordClient*(clientId: string): DiscordClient =
  ## Create a new Discord client with your application ID
  result = DiscordClient(
    clientId: clientId,
    connected: false,
    nonce: 0,
    lastHeartbeat: 0.0
  )

proc writeFrame(client: DiscordClient, opcode: int, data: string) =
  ## Write a frame to the Discord IPC pipe
  if not client.connected or client.pipe.isNil:
    return
  
  try:
    let payload = data
    let length = uint32(payload.len)
    
    # Write opcode (4 bytes)
    discard client.pipe.writeBuffer(addr opcode, sizeof(int32))
    # Write length (4 bytes)
    discard client.pipe.writeBuffer(unsafeAddr length, sizeof(uint32))
    # Write payload
    discard client.pipe.writeBuffer(unsafeAddr payload[0], payload.len)
    client.pipe.flushFile()
  except IOError:
    client.connected = false

proc readFrame(client: DiscordClient): tuple[opcode: int, data: string] =
  ## Read a frame from the Discord IPC pipe
  if not client.connected or client.pipe.isNil:
    return (0, "")
  
  try:
    var opcode: int32
    var length: uint32
    
    # Read opcode
    if client.pipe.readBuffer(addr opcode, sizeof(int32)) != sizeof(int32):
      client.connected = false
      return (0, "")
    
    # Read length
    if client.pipe.readBuffer(addr length, sizeof(uint32)) != sizeof(uint32):
      client.connected = false
      return (0, "")
    
    # Read data
    if length > 0:
      var data = newString(length)
      if client.pipe.readBuffer(addr data[0], length.int) != length.int:
        client.connected = false
        return (0, "")
      result = (opcode.int, data)
    else:
      result = (opcode.int, "")
  except IOError:
    client.connected = false
    result = (0, "")

proc connect*(client: DiscordClient): bool =
  ## Connect to Discord via named pipe
  if client.connected:
    return true
  
  when defined(windows):
    # Try to open the Discord IPC pipe on Windows
    for i in 0..9:
      let pipeName = r"\\.\pipe\discord-ipc-" & $i
      try:
        # Open pipe with read/write access
        client.pipe = open(pipeName, fmReadWrite)
        client.connected = true
        break
      except IOError:
        continue
  else:
    # Unix/Linux pipe path
    for i in 0..9:
      let pipeName = "/tmp/discord-ipc-" & $i
      if fileExists(pipeName):
        try:
          client.pipe = open(pipeName, fmReadWrite)
          client.connected = true
          break
        except IOError:
          continue
  
  if not client.connected:
    return false
  
  # Send handshake
  let handshake = %* {
    "v": 1,
    "client_id": client.clientId
  }
  
  client.writeFrame(OPCODES.HANDSHAKE, $handshake)
  
  # Read handshake response
  let response = client.readFrame()
  if response.opcode == OPCODES.FRAME:
    let json = parseJson(response.data)
    if json.hasKey("cmd") and json["cmd"].getStr() == "DISPATCH":
      client.lastHeartbeat = epochTime()
      return true
  
  client.connected = false
  if not client.pipe.isNil:
    close(client.pipe)
  return false

proc disconnect*(client: DiscordClient) =
  ## Disconnect from Discord
  if client.connected and not client.pipe.isNil:
    try:
      client.writeFrame(OPCODES.CLOSE, "{}")
      close(client.pipe)
    except:
      discard
  client.connected = false

proc updatePresence*(client: DiscordClient, presence: DiscordRichPresence) =
  ## Update the Discord Rich Presence
  if not client.connected:
    return
  
  client.nonce += 1
  
  var activity = %* {
    "state": presence.state,
    "details": presence.details,
    "timestamps": {},
    "assets": {}
  }
  
  # Add timestamps if provided
  if presence.startTimestamp > 0:
    activity["timestamps"]["start"] = %presence.startTimestamp
  if presence.endTimestamp > 0:
    activity["timestamps"]["end"] = %presence.endTimestamp
  
  # Add assets (images) if provided
  if presence.largeImageKey.len > 0:
    activity["assets"]["large_image"] = %presence.largeImageKey
  if presence.largeImageText.len > 0:
    activity["assets"]["large_text"] = %presence.largeImageText
  if presence.smallImageKey.len > 0:
    activity["assets"]["small_image"] = %presence.smallImageKey
  if presence.smallImageText.len > 0:
    activity["assets"]["small_text"] = %presence.smallImageText
  
  # Add party info if provided
  if presence.partySize > 0 and presence.partyMax > 0:
    activity["party"] = %* {
      "id": presence.partyId,
      "size": [presence.partySize, presence.partyMax]
    }
  
  let payload = %* {
    "cmd": "SET_ACTIVITY",
    "args": {
      "pid": getCurrentProcessId(),
      "activity": activity
    },
    "nonce": $client.nonce
  }
  
  client.writeFrame(OPCODES.FRAME, $payload)
  
  # Read response (but don't block)
  try:
    let response = client.readFrame()
    # Process response if needed
  except:
    discard

proc clearPresence*(client: DiscordClient) =
  ## Clear the Discord Rich Presence
  if not client.connected:
    return
  
  client.nonce += 1
  
  let payload = %* {
    "cmd": "SET_ACTIVITY",
    "args": {
      "pid": getCurrentProcessId(),
      "activity": nil
    },
    "nonce": $client.nonce
  }
  
  client.writeFrame(OPCODES.FRAME, $payload)

proc runCallbacks*(client: DiscordClient) =
  ## Process any pending messages from Discord (call this regularly in your game loop)
  if not client.connected:
    return
  
  # Send heartbeat every 30 seconds
  let now = epochTime()
  if now - client.lastHeartbeat > 30.0:
    try:
      client.writeFrame(OPCODES.PING, "{}")
      client.lastHeartbeat = now
    except:
      client.connected = false
      return
  
  # Try to read any pending responses (non-blocking check)
  # In a real implementation, you'd want to make this truly non-blocking
  # For now, we just update heartbeat

proc isConnected*(client: DiscordClient): bool =
  ## Check if the Discord client is connected
  if client.isNil:
    return false
  return client.connected

# Helper to create presence easily
proc createPresence*(state: string = "", details: string = "",
                    largeImage: string = "", largeText: string = "",
                    smallImage: string = "", smallText: string = "",
                    startTime: int64 = 0): DiscordRichPresence =
  result.state = state
  result.details = details
  result.largeImageKey = largeImage
  result.largeImageText = largeText
  result.smallImageKey = smallImage
  result.smallImageText = smallText
  result.startTimestamp = startTime
