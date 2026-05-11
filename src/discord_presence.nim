## Discord Rich Presence - Pure Nim Implementation
## Communicates with Discord via named pipes (IPC)
## Thread-safe implementation to prevent blocking the main game loop

import json, times, os, locks
when defined(windows):
  proc getCurrentProcessId(): uint32 {.stdcall, dynlib: "kernel32", importc: "GetCurrentProcessId".}
else:
  import posix

type
  DiscordButton* = object
    label*: string
    url*: string

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
    buttons*: seq[DiscordButton]
    clearActivity*: bool

  DiscordClient* = ref object
    clientId: string
    pipe: File
    connected: bool
    nonce: int
    lastHeartbeat: float
    connectionAttempted: bool
    lastUpdateTime: float
    # Threading support
    thread: Thread[DiscordClient]
    threadRunning: bool
    pendingPresence: DiscordRichPresence
    hasUpdate: bool
    updateLock: Lock
    shouldStop: bool

const
  OPCODES = (
    HANDSHAKE: 0,
    FRAME: 1,
    CLOSE: 2,
    PING: 3,
    PONG: 4
  )

proc getProcessId(): int =
  ## Get current process ID in a cross-platform way
  when defined(windows):
    result = getCurrentProcessId().int
  else:
    result = posix.getpid().int

proc newDiscordClient*(clientId: string): DiscordClient =
  ## Create a new Discord client with your application ID
  result = DiscordClient(
    clientId: clientId,
    connected: false,
    nonce: 0,
    lastHeartbeat: 0.0,
    connectionAttempted: false,
    lastUpdateTime: 0.0,
    threadRunning: false,
    hasUpdate: false,
    shouldStop: false
  )
  initLock(result.updateLock)

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

proc connectSync(client: DiscordClient): bool =
  ## Synchronous connection - called from background thread only
  if client.connected:
    return true

  when defined(windows):
    # Try to open the Discord IPC pipe on Windows
    for i in 0..2:
      let pipeName = r"\\.\pipe\discord-ipc-" & $i
      try:
        client.pipe = open(pipeName, fmReadWrite)
        client.connected = true
        break
      except IOError:
        continue
  else:
    # Unix/Linux pipe path
    for i in 0..2:
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

  try:
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
  except:
    discard

  # Handshake failed
  client.connected = false
  if not client.pipe.isNil:
    try:
      close(client.pipe)
    except:
      discard
  return false

proc putIfNotEmpty(node: JsonNode, key, value: string) =
  if value.len > 0:
    node[key] = %value

proc buildAssetsNode(presence: DiscordRichPresence): JsonNode =
  result = newJObject()
  result.putIfNotEmpty("large_image", presence.largeImageKey)
  result.putIfNotEmpty("large_text", presence.largeImageText)
  result.putIfNotEmpty("small_image", presence.smallImageKey)
  result.putIfNotEmpty("small_text", presence.smallImageText)

proc buildTimestampsNode(presence: DiscordRichPresence): JsonNode =
  result = newJObject()
  if presence.startTimestamp > 0:
    result["start"] = %presence.startTimestamp
  if presence.endTimestamp > 0:
    result["end"] = %presence.endTimestamp

proc buildPartyNode(presence: DiscordRichPresence): JsonNode =
  result = newJObject()
  result.putIfNotEmpty("id", presence.partyId)
  if presence.partySize > 0 or presence.partyMax > 0:
    result["size"] = %* [presence.partySize, presence.partyMax]

proc buildButtonsNode(buttons: openArray[DiscordButton]): JsonNode =
  result = newJArray()
  for button in buttons:
    if button.label.len == 0 or button.url.len == 0:
      continue

    var buttonNode = newJObject()
    buttonNode["label"] = %button.label
    buttonNode["url"] = %button.url
    result.add(buttonNode)

proc buildSetActivityPayload(client: DiscordClient, presence: DiscordRichPresence): JsonNode =
  result = newJObject()
  result["cmd"] = %"SET_ACTIVITY"
  result["nonce"] = %($client.nonce)

  var argsNode = newJObject()
  argsNode["pid"] = %getProcessId()

  if presence.clearActivity:
    argsNode["activity"] = newJNull()
  else:
    var activity = newJObject()
    activity.putIfNotEmpty("state", presence.state)
    activity.putIfNotEmpty("details", presence.details)

    let assets = buildAssetsNode(presence)
    if assets.len > 0:
      activity["assets"] = assets

    let timestamps = buildTimestampsNode(presence)
    if timestamps.len > 0:
      activity["timestamps"] = timestamps

    let party = buildPartyNode(presence)
    if party.len > 0:
      activity["party"] = party

    let buttons = buildButtonsNode(presence.buttons)
    if buttons.len > 0:
      activity["buttons"] = buttons

    argsNode["activity"] = activity

  result["args"] = argsNode

proc sendPresenceNow(client: DiscordClient, presence: DiscordRichPresence) =
  client.nonce += 1
  client.writeFrame(OPCODES.FRAME, $buildSetActivityPayload(client, presence))

proc discordWorkerThread(client: DiscordClient) {.thread.} =
  ## Background thread that handles Discord IPC communication
  ## This runs independently and never blocks the main game thread

  # Try to connect
  discard client.connectSync()

  # Main loop - check for updates every 100ms
  while not client.shouldStop:
    sleep(100)

    # Check if there's a pending update
    var hasUpdate = false
    var presence: DiscordRichPresence

    acquire(client.updateLock)
    if client.hasUpdate:
      presence = client.pendingPresence
      hasUpdate = true
      client.hasUpdate = false
    release(client.updateLock)

    # Send update if we have one and are connected
    if hasUpdate and client.connected:
      let currentTime = epochTime()

      # Throttle to once per second
      if currentTime - client.lastUpdateTime >= 1.0:
        client.lastUpdateTime = currentTime

        try:
          client.sendPresenceNow(presence)
        except:
          # Connection lost
          client.connected = false

proc connect*(client: DiscordClient): bool =
  ## Start the background Discord thread (non-blocking)
  ## Returns immediately - connection happens in background
  if client.threadRunning:
    return true

  client.threadRunning = true
  createThread(client.thread, discordWorkerThread, client)
  return true

proc disconnect*(client: DiscordClient) =
  ## Disconnect from Discord and stop background thread
  if client.isNil:
    return

  if client.threadRunning:
    # Signal thread to stop
    client.shouldStop = true
    # Wait for thread to finish (with timeout protection)
    joinThread(client.thread)
    client.threadRunning = false

  # Close the connection
  if client.connected and not client.pipe.isNil:
    try:
      client.sendPresenceNow(DiscordRichPresence(clearActivity: true))
      client.writeFrame(OPCODES.CLOSE, "{}")
      close(client.pipe)
    except:
      discard

  client.connected = false

  # Clean up lock
  try:
    deinitLock(client.updateLock)
  except:
    discard

proc updatePresence*(client: DiscordClient, presence: DiscordRichPresence) =
  ## Update the Discord Rich Presence (non-blocking, thread-safe)
  ## Queues the update for the background thread to send
  if client.isNil:
    return

  # Queue the update for the background thread
  acquire(client.updateLock)
  client.pendingPresence = presence
  client.hasUpdate = true
  release(client.updateLock)

proc clearPresence*(client: DiscordClient) =
  ## Clear the Discord Rich Presence (non-blocking)
  if client.isNil or not client.threadRunning:
    return

  # Queue a clear command
  let emptyPresence = DiscordRichPresence(clearActivity: true)
  acquire(client.updateLock)
  client.pendingPresence = emptyPresence
  client.hasUpdate = true
  release(client.updateLock)

proc runCallbacks*(client: DiscordClient) =
  ## No-op for compatibility - thread handles everything
  discard

proc isConnected*(client: DiscordClient): bool =
  ## Check if the Discord client is connected
  if client.isNil:
    return false
  return client.connected

proc createButton*(label, url: string): DiscordButton =
  result.label = label
  result.url = url

# Helper to create presence easily
proc createPresence*(state: string = "", details: string = "",
                    largeImage: string = "", largeText: string = "",
                    smallImage: string = "", smallText: string = "",
                    startTime: int64 = 0, endTime: int64 = 0,
                    partyId: string = "", partySize: int = 0,
                    partyMax: int = 0,
                    buttons: seq[DiscordButton] = @[]): DiscordRichPresence =
  result.state = state
  result.details = details
  result.largeImageKey = largeImage
  result.largeImageText = largeText
  result.smallImageKey = smallImage
  result.smallImageText = smallText
  result.startTimestamp = startTime
  result.endTimestamp = endTime
  result.partyId = partyId
  result.partySize = partySize
  result.partyMax = partyMax
  result.buttons = buttons
