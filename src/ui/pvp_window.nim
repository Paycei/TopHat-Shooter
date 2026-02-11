## PvP Lobby Window
## Network lobby interface as an OS-style window

import raylib, os_window, ../network/network, ../network/network_types, strutils, net, math, ../types

type
  PvPWindow* = ref object
    window*: OSWindow
    networkManager*: NetworkManager
    state*: PvPLobbyState
    isHost*: bool
    hostIP*: string
    hostPort*: int
    inputIP*: string
    inputPort*: string
    inputNickname*: string  # Player's chosen nickname
    editingNickname*: bool  # Whether the nickname field is active
    errorMessage*: string
    connectionTimeout*: float32
    cursorBlink*: float32
    editingIP*: bool
    editingPort*: bool
    readyToStart*: bool  # Flag when connection is established and ready to start game
    # Store remote player's cosmetics when connection is established
    remoteSkinType*: int
    remoteBulletSkinType*: int
    remoteShapeType*: int
    remoteParticleSkinType*: int
    cachedLocalIP*: string  # Pre-computed local IP to avoid blocking
    showIPs*: bool  # Whether to show uncensored IPs (checkbox)
    maxPlayers*: int  # Maximum number of players (2-16)
    # Store all connected players' info (populated from connection accept packet)
    connectedPlayers*: seq[tuple[index: int, skinType, bulletSkinType, shapeType, particleSkinType: int, nickname: string]]
    assignedPlayerIndex*: int  # Client's player index assigned by host (-1 if host)
    keepAliveTimer*: float32  # Timer for sending keep-alive pings
    connectedNicknames*: seq[string]  # Nicknames of all connected players (indexed by player index)
    # Text selection support
    selectionStart*: int  # Selection start position (-1 if no selection)
    selectionEnd*: int    # Selection end position
    mouseDownPos*: Vector2  # Mouse position when clicked in text field
    isDragging*: bool     # Whether currently dragging to select
    lastBackspaceTime*: float32  # For backspace repeat timing
    cursorPos*: int       # Current cursor position in text
    # Team mode configuration
    teamsEnabled*: bool   # Whether teams game mode is enabled
    numTeams*: int        # Number of teams (2, 3, or 4)
    playerTeamAssignments*: seq[int]  # Team assignment per player index (0=Red, 1=Blue, 2=Green, 3=Yellow)

  PvPLobbyState* = enum
    plsMainMenu           # Choose host or join
    plsHostingConfig      # Configure hosting settings
    plsHostingActive      # Waiting for opponent (actively hosting)
    plsJoining            # Entering IP and connecting
    plsConnecting         # Attempting connection
    plsConnected          # Connected, waiting for game start
    plsError              # Connection error

const
  DEFAULT_PORT* = 7777
  CONNECTION_TIMEOUT = 10.0

proc getLocalIP*(): string =
  ## Get local IP address
  ## Uses socket API instead of system commands
  result = "127.0.0.1"  # Safe fallback
  
  try:
    let sock = newSocket(Domain.AF_INET, SockType.SOCK_DGRAM, Protocol.IPPROTO_UDP)
    try:
      # Connect to Google DNS (8.8.8.8) to determine which local interface would be used
      # UDP connect doesn't actually send data - just determines routing
      sock.connect("8.8.8.8", Port(80))
      let (localIP, _) = sock.getLocalAddr()
      if localIP != "" and localIP != "0.0.0.0":
        result = localIP
    except:
      discard
    sock.close()
  except:
    discard
  
  # If all fails, return localhost (players can manually enter IP)
  return result

proc censorIP*(ip: string): string =
  ## Censor IP address for privacy: ***.***.***.***
  if ip == "127.0.0.1":
    return ip

  let parts = ip.split(".")
  if parts.len == 4:
    return "***.***.***.***"
  else:
    return ip

proc getTeamForPlayer*(playerIndex: int, numTeams: int): PvPTeam =
  ## Get team assignment for a player based on team count
  if numTeams == 2:
    return if playerIndex mod 2 == 0: ptRed else: ptBlue
  elif numTeams == 3:
    case playerIndex mod 3
    of 0: return ptRed
    of 1: return ptBlue
    else: return ptGreen
  else:  # 4 teams
    case playerIndex mod 4
    of 0: return ptRed
    of 1: return ptBlue
    of 2: return ptGreen
    else: return ptYellow

proc getTeamColor*(team: PvPTeam): Color =
  ## Get the display color for a team
  case team
  of ptRed:
    return Color(r: 255, g: 60, b: 60, a: 255)
  of ptBlue:
    return Color(r: 60, g: 120, b: 255, a: 255)
  of ptGreen:
    return Color(r: 60, g: 255, b: 120, a: 255)
  of ptYellow:
    return Color(r: 255, g: 220, b: 60, a: 255)
  of ptNone:
    return White

proc getTeamName*(team: PvPTeam): string =
  ## Get the display name for a team
  case team
  of ptRed: return "Red"
  of ptBlue: return "Blue"
  of ptGreen: return "Green"
  of ptYellow: return "Yellow"
  of ptNone: return "None"

proc newPvPWindow*(screenWidth, screenHeight: int): PvPWindow =
  let windowWidth = 600
  let windowHeight = 600
  let windowX = (screenWidth - windowWidth) div 2
  let windowY = (screenHeight - windowHeight) div 2
  
  # Pre-compute local IP using fast socket method
  let localIP = getLocalIP()
  
  result = PvPWindow(
    window: newOSWindow("PvP Network", windowX, windowY, windowWidth, windowHeight,
                       Color(r: 100, g: 200, b: 100, a: 255), owtHelp, resizable = false),
    networkManager: newNetworkManager(),
    state: plsMainMenu,
    isHost: false,
    hostIP: "",
    hostPort: DEFAULT_PORT,
    inputIP: "127.0.0.1",
    inputPort: $DEFAULT_PORT,
    errorMessage: "",
    connectionTimeout: 0,
    cursorBlink: 0,
    editingIP: true,
    editingPort: false,
    readyToStart: false,
    remoteSkinType: 0,
    remoteBulletSkinType: 0,
    remoteShapeType: 0,
    remoteParticleSkinType: 0,
    cachedLocalIP: localIP,
    showIPs: false,  # IPs censored by default
    maxPlayers: 2,  # Default to 2 players (1v1)
    connectedPlayers: @[],
    assignedPlayerIndex: -1,
    keepAliveTimer: 0.0,
    inputNickname: "Player",
    editingNickname: false,
    connectedNicknames: @[],
    selectionStart: -1,
    selectionEnd: -1,
    mouseDownPos: Vector2(x: 0, y: 0),
    isDragging: false,
    lastBackspaceTime: 0.0,
    cursorPos: 0,
    teamsEnabled: false,
    numTeams: 2,
    playerTeamAssignments: @[]
  )

proc startHosting*(pvpWin: PvPWindow) =
  pvpWin.isHost = true
  pvpWin.state = plsHostingActive
  pvpWin.hostIP = pvpWin.cachedLocalIP  # Use pre-computed IP
  pvpWin.hostPort = DEFAULT_PORT
  pvpWin.readyToStart = false
  pvpWin.keepAliveTimer = 0.0  # Reset keep-alive timer

  # Initialize player team assignments if teams are enabled
  if pvpWin.teamsEnabled:
    pvpWin.playerTeamAssignments = @[]
    # Pre-allocate space for team assignments for all potential players
    # Team assignments are stored as 1-4 (ptRed to ptYellow), skipping 0 (ptNone)
    for i in 0..<pvpWin.maxPlayers:
      pvpWin.playerTeamAssignments.add((i mod pvpWin.numTeams) + 1)  # +1 to skip ptNone (0)

  try:
    pvpWin.networkManager.initHost(pvpWin.hostPort, pvpWin.maxPlayers)
    echo "[LOBBY] Hosting on ", pvpWin.hostIP, ":", pvpWin.hostPort, " for ", pvpWin.maxPlayers, " players"
  except:
    pvpWin.state = plsError
    pvpWin.errorMessage = "Failed to start host: " & getCurrentExceptionMsg()

proc connectToGame*(pvpWin: PvPWindow, ip: string, port: int,
                   skinType: int = 0, bulletSkinType: int = 0,
                   shapeType: int = 0, particleSkinType: int = 0,
                   nickname: string = "Player") =
  pvpWin.isHost = false
  pvpWin.state = plsConnecting
  pvpWin.connectionTimeout = CONNECTION_TIMEOUT
  pvpWin.readyToStart = false
  pvpWin.keepAliveTimer = 0.0  # Reset keep-alive timer

  try:
    pvpWin.networkManager.initClient()
    pvpWin.networkManager.connectToHost(ip, port, skinType, bulletSkinType, shapeType, particleSkinType, nickname)
    echo "[LOBBY] Connecting to ", ip, ":", port, " as \"", nickname, "\""
  except:
    pvpWin.state = plsError
    pvpWin.errorMessage = "Failed to connect: " & getCurrentExceptionMsg()

proc updatePvPWindow*(pvpWin: PvPWindow, dt: float32, getCosmetics: proc(): tuple[skinType, bulletSkinType, shapeType, particleSkinType: int] = nil) =
  pvpWin.cursorBlink += dt

  # Keep-alive ping mechanism - send ping every 1 second when connected
  if pvpWin.state == plsConnected or pvpWin.state == plsHostingActive:
    pvpWin.keepAliveTimer += dt
    if pvpWin.keepAliveTimer >= 1.0:
      pvpWin.keepAliveTimer = 0.0
      # Send a ping to keep the connection alive
      pvpWin.networkManager.sendPing(0)

  case pvpWin.state
  of plsHostingActive:
    let events = pvpWin.networkManager.pollEvents(getCosmetics)
    for event in events:
      if event.kind == neConnect:
        # Host accepting first player connection - move to connected state to show lobby
        pvpWin.state = plsConnected
        # Store remote player's cosmetics from the connection event
        pvpWin.remoteSkinType = event.remoteSkinType
        pvpWin.remoteBulletSkinType = event.remoteBulletSkinType
        pvpWin.remoteShapeType = event.remoteShapeType
        pvpWin.remoteParticleSkinType = event.remoteParticleSkinType

  of plsConnecting:
    pvpWin.connectionTimeout -= dt
    if pvpWin.connectionTimeout <= 0:
      pvpWin.state = plsError
      pvpWin.errorMessage = "Connection timeout"
      return

    let events = pvpWin.networkManager.pollEvents(getCosmetics)
    for event in events:
      if event.kind == neConnect:
        pvpWin.state = plsConnected
        # Don't set readyToStart yet - wait for host's START GAME signal
        # Store remote player's cosmetics from the connection event
        pvpWin.remoteSkinType = event.remoteSkinType
        pvpWin.remoteBulletSkinType = event.remoteBulletSkinType
        pvpWin.remoteShapeType = event.remoteShapeType
        pvpWin.remoteParticleSkinType = event.remoteParticleSkinType
      elif event.kind == neReceive:
        # Extract connection accept packet data (player index, connected players list)
        if event.packet.packetType == ptConnectionAccept:
          pvpWin.connectedPlayers = event.packet.connectedPlayers
          pvpWin.assignedPlayerIndex = event.packet.assignedPlayerIndex
          echo "[PVP Window] Client assigned player index: ", pvpWin.assignedPlayerIndex
      elif event.kind == neDisconnect:
        pvpWin.state = plsError
        pvpWin.errorMessage = event.reason

  of plsConnected:
    # Host continues accepting more players until max is reached
    # Client waits here for host to click START GAME
    let events = pvpWin.networkManager.pollEvents(getCosmetics)
    for event in events:
      if event.kind == neConnect:
        # Host accepting another player
        echo "[PVP Window] Another player connected"
        # Store remote player's cosmetics from the connection event
        pvpWin.remoteSkinType = event.remoteSkinType
        pvpWin.remoteBulletSkinType = event.remoteBulletSkinType
        pvpWin.remoteShapeType = event.remoteShapeType
        pvpWin.remoteParticleSkinType = event.remoteParticleSkinType
      elif event.kind == neReceive:
        # Check for game start signal from host (client only)
        if event.packet.packetType == ptGameStart:
          # Extract the final player list from the game start packet
          pvpWin.connectedPlayers = event.packet.gameConnectedPlayers
          echo "[PVP Window] Game start signal received from host with ", pvpWin.connectedPlayers.len, " players"
          pvpWin.readyToStart = true
      elif event.kind == neDisconnect:
        pvpWin.state = plsError
        pvpWin.errorMessage = "Host disconnected"

  else:
    discard

proc resetPvPWindow*(pvpWin: PvPWindow) =
  if pvpWin.networkManager != nil:
    cleanup(pvpWin.networkManager)
  pvpWin.networkManager = newNetworkManager()
  pvpWin.state = plsMainMenu
  pvpWin.isHost = false
  pvpWin.errorMessage = ""
  pvpWin.readyToStart = false
  pvpWin.remoteSkinType = 0
  pvpWin.remoteBulletSkinType = 0
  pvpWin.remoteShapeType = 0
  pvpWin.remoteParticleSkinType = 0
  pvpWin.connectedPlayers = @[]
  pvpWin.connectedNicknames = @[]
  pvpWin.assignedPlayerIndex = -1
  pvpWin.keepAliveTimer = 0.0
  pvpWin.showIPs = false  # Reset to censored
  pvpWin.editingNickname = false

proc deleteSelection(text: var string, selStart, selEnd: int): int =
  ## Delete selected text and return new cursor position
  if selStart < 0 or selEnd < 0 or selStart == selEnd:
    return -1
  
  let startPos = min(selStart, selEnd)
  let endPos = max(selStart, selEnd)
  
  if startPos >= text.len or endPos > text.len:
    return -1
  
  # Delete the selection
  text = text[0..<startPos] & text[endPos..^1]
  return startPos

proc drawTextSelection(text: string, fieldX, fieldY, fontSize: int, selStart, selEnd: int) =
  ## Draw text selection highlight
  if selStart < 0 or selEnd < 0 or selStart == selEnd:
    return
  
  let startPos = min(selStart, selEnd)
  let endPos = max(selStart, selEnd)
  
  if startPos >= text.len or endPos > text.len or startPos < 0:
    return
  
  # Calculate selection bounds
  let beforeText = if startPos == 0: "" else: text[0..<startPos]
  let selectedText = text[startPos..<endPos]
  
  let beforeWidth = measureText(beforeText, fontSize.int32)
  let selectedWidth = measureText(selectedText, fontSize.int32)
  
  let selX = fieldX + 10 + beforeWidth
  let selY = fieldY + 6
  let selHeight = fontSize + 4
  
  # Draw selection background
  drawRectangle(selX.int32, selY.int32, selectedWidth.int32, selHeight.int32,
               Color(r: 100, g: 150, b: 255, a: 128))

proc getTextCursorPos(text: string, fieldX: int, fieldY: int, fontSize: int, fieldHeight: int, mouseX, mouseY: float32): int =
  ## Get cursor position from mouse coordinates
  ## Returns -1 if mouse is outside the field
  
  # Check if mouse is within field bounds (with small margin)
  if mouseY < (fieldY - 2).float32 or mouseY > (fieldY + fieldHeight + 2).float32:
    return -1
  
  if mouseX < (fieldX + 5).float32:
    return 0  # Before first character
  
  # Find character closest to mouse position
  var closestPos = 0
  var closestDist = 9999.0
  
  for i in 0..text.len:
    let substr = if i == 0: "" else: text[0..<i]
    let width = measureText(substr, fontSize.int32)
    let charX = fieldX + 10 + width
    let dist = abs(mouseX - charX.float32)
    
    if dist < closestDist:
      closestDist = dist
      closestPos = i
  
  return closestPos

proc handlePvPWindowInput*(pvpWin: PvPWindow) =
  if not pvpWin.window.visible or pvpWin.window.minimized:
    return

  if pvpWin.state != plsJoining and pvpWin.state != plsHostingConfig:
    return

  # Calculate content area position
  let contentX = pvpWin.window.x + 10  # Window border
  let contentY = pvpWin.window.y + 30  # Title bar

  # Get current active field text reference with correct coordinates
  var activeText: ptr string = nil
  var fieldX, fieldY, fontSize, fieldHeight: int

  if pvpWin.editingNickname:
    activeText = addr pvpWin.inputNickname
    fieldX = contentX + 50
    fieldY = contentY + 96 + 8  # Text Y position
    fontSize = 20
    fieldHeight = 28  # Remaining height for text area
  elif pvpWin.editingIP:
    activeText = addr pvpWin.inputIP
    fieldX = contentX + 50
    fieldY = contentY + 172 + 10  # Text Y position
    fontSize = 20
    fieldHeight = 30  # Remaining height for text area
  elif pvpWin.editingPort:
    activeText = addr pvpWin.inputPort
    fieldX = contentX + 50
    fieldY = contentY + 250 + 10  # Text Y position
    fontSize = 20
    fieldHeight = 30  # Remaining height for text area

  # Handle mouse selection and cursor positioning
  if activeText != nil:
    let mousePos = getMousePosition()

    # Start selection/cursor positioning on mouse down
    if isMouseButtonPressed(Left):
      let cursorPos = getTextCursorPos(activeText[], fieldX, fieldY, fontSize, fieldHeight, mousePos.x, mousePos.y)
      if cursorPos >= 0:  # Only start if mouse is within field
        pvpWin.mouseDownPos = mousePos
        pvpWin.isDragging = true
        pvpWin.selectionStart = cursorPos
        pvpWin.selectionEnd = cursorPos

    # Update selection while dragging
    if pvpWin.isDragging and isMouseButtonDown(Left):
      let cursorPos = getTextCursorPos(activeText[], fieldX, fieldY, fontSize, fieldHeight, mousePos.x, mousePos.y)
      if cursorPos >= 0:  # Only update if mouse is within field
        # Check if mouse has moved enough to start selecting (prevents accidental selection on click)
        let dragDist = sqrt((mousePos.x - pvpWin.mouseDownPos.x) * (mousePos.x - pvpWin.mouseDownPos.x) +
                           (mousePos.y - pvpWin.mouseDownPos.y) * (mousePos.y - pvpWin.mouseDownPos.y))
        if dragDist > 3.0:  # 3 pixel threshold
          pvpWin.selectionEnd = cursorPos

    # End selection on mouse up
    if isMouseButtonReleased(Left):
      pvpWin.isDragging = false
      # If no actual drag occurred (click without drag), clear selection and set cursor position
      if pvpWin.selectionStart == pvpWin.selectionEnd:
        pvpWin.cursorPos = pvpWin.selectionStart
        pvpWin.selectionStart = -1
        pvpWin.selectionEnd = -1
      else:
        # If text was selected, cursor should be at the end of selection
        pvpWin.cursorPos = max(pvpWin.selectionStart, pvpWin.selectionEnd)

  # Handle clipboard operations
  let ctrlPressed = isKeyDown(LeftControl) or isKeyDown(RightControl)
  let cmdPressed = isKeyDown(LeftSuper) or isKeyDown(RightSuper)

  # Copy (Ctrl+C)
  if (ctrlPressed or cmdPressed) and isKeyPressed(C):
    if pvpWin.selectionStart >= 0 and pvpWin.selectionEnd >= 0 and pvpWin.selectionStart != pvpWin.selectionEnd:
      if activeText != nil:
        let startPos = min(pvpWin.selectionStart, pvpWin.selectionEnd)
        let endPos = max(pvpWin.selectionStart, pvpWin.selectionEnd)
        let selectedText = activeText[][startPos..<endPos]
        setClipboardText(selectedText)

  # Cut (Ctrl+X)
  if (ctrlPressed or cmdPressed) and isKeyPressed(X):
    if pvpWin.selectionStart >= 0 and pvpWin.selectionEnd >= 0 and pvpWin.selectionStart != pvpWin.selectionEnd:
      if activeText != nil:
        let startPos = min(pvpWin.selectionStart, pvpWin.selectionEnd)
        let endPos = max(pvpWin.selectionStart, pvpWin.selectionEnd)
        let selectedText = activeText[][startPos..<endPos]
        setClipboardText(selectedText)
        discard deleteSelection(activeText[], pvpWin.selectionStart, pvpWin.selectionEnd)
        pvpWin.selectionStart = -1
        pvpWin.selectionEnd = -1

  # Paste (Ctrl+V)
  if (ctrlPressed or cmdPressed) and isKeyPressed(V):
    try:
      let clipboardCStr = getClipboardText()
      if not clipboardCStr.isNil:
        let text = $clipboardCStr

        # Delete selection if any
        if pvpWin.selectionStart >= 0 and pvpWin.selectionEnd >= 0 and pvpWin.selectionStart != pvpWin.selectionEnd:
          if activeText != nil:
            let newCursor = deleteSelection(activeText[], pvpWin.selectionStart, pvpWin.selectionEnd)
            if newCursor >= 0:
              pvpWin.cursorPos = newCursor
            pvpWin.selectionStart = -1
            pvpWin.selectionEnd = -1

        # Filter and paste text at cursor position
        if pvpWin.editingNickname:
          var pasteText = ""
          for ch in text:
            if pvpWin.inputNickname.len + pasteText.len < 16 and ch.ord >= 32 and ch != '\n' and ch != '\r' and ch != '\t':
              pasteText &= ch
          if pasteText.len > 0:
            pvpWin.cursorPos = clamp(pvpWin.cursorPos, 0, pvpWin.inputNickname.len)
            pvpWin.inputNickname = pvpWin.inputNickname[0..<pvpWin.cursorPos] & pasteText & pvpWin.inputNickname[pvpWin.cursorPos..^1]
            pvpWin.cursorPos += pasteText.len
        elif pvpWin.editingIP:
          var pasteText = ""
          for ch in text:
            if ch in {'0'..'9', '.'}:
              pasteText &= ch
          if pasteText.len > 0:
            pvpWin.cursorPos = clamp(pvpWin.cursorPos, 0, pvpWin.inputIP.len)
            pvpWin.inputIP = pvpWin.inputIP[0..<pvpWin.cursorPos] & pasteText & pvpWin.inputIP[pvpWin.cursorPos..^1]
            pvpWin.cursorPos += pasteText.len
        elif pvpWin.editingPort:
          var pasteText = ""
          for ch in text:
            if ch in {'0'..'9'}:
              pasteText &= ch
          if pasteText.len > 0:
            pvpWin.cursorPos = clamp(pvpWin.cursorPos, 0, pvpWin.inputPort.len)
            pvpWin.inputPort = pvpWin.inputPort[0..<pvpWin.cursorPos] & pasteText & pvpWin.inputPort[pvpWin.cursorPos..^1]
            pvpWin.cursorPos += pasteText.len
    except:
      discard

  # Select all (Ctrl+A)
  if (ctrlPressed or cmdPressed) and isKeyPressed(A):
    if activeText != nil:
      pvpWin.selectionStart = 0
      pvpWin.selectionEnd = activeText[].len

  # Handle character input
  var key = getCharPressed()
  while key > 0:
    # Delete selection before inserting new character
    if activeText != nil and pvpWin.selectionStart >= 0 and pvpWin.selectionEnd >= 0 and pvpWin.selectionStart != pvpWin.selectionEnd:
      let newCursor = deleteSelection(activeText[], pvpWin.selectionStart, pvpWin.selectionEnd)
      if newCursor >= 0:
        pvpWin.cursorPos = newCursor
      pvpWin.selectionStart = -1
      pvpWin.selectionEnd = -1

    if pvpWin.editingNickname:
      if pvpWin.inputNickname.len < 16 and key >= 32:
        try:
          # Insert at cursor position
          var charToInsert = ""
          if key < 128:
            charToInsert = $char(key)
          else:
            if key < 0x800:
              charToInsert &= char(0xC0 or (key shr 6))
              charToInsert &= char(0x80 or (key and 0x3F))
            elif key < 0x10000:
              charToInsert &= char(0xE0 or (key shr 12))
              charToInsert &= char(0x80 or ((key shr 6) and 0x3F))
              charToInsert &= char(0x80 or (key and 0x3F))
            else:
              charToInsert &= char(0xF0 or (key shr 18))
              charToInsert &= char(0x80 or ((key shr 12) and 0x3F))
              charToInsert &= char(0x80 or ((key shr 6) and 0x3F))
              charToInsert &= char(0x80 or (key and 0x3F))

          # Clamp cursor to valid range
          pvpWin.cursorPos = clamp(pvpWin.cursorPos, 0, pvpWin.inputNickname.len)
          # Insert character at cursor position
          pvpWin.inputNickname = pvpWin.inputNickname[0..<pvpWin.cursorPos] & charToInsert & pvpWin.inputNickname[pvpWin.cursorPos..^1]
          pvpWin.cursorPos += charToInsert.len
        except:
          if key < 256:
            pvpWin.cursorPos = clamp(pvpWin.cursorPos, 0, pvpWin.inputNickname.len)
            pvpWin.inputNickname = pvpWin.inputNickname[0..<pvpWin.cursorPos] & char(key) & pvpWin.inputNickname[pvpWin.cursorPos..^1]
            pvpWin.cursorPos += 1
    elif pvpWin.editingIP:
      if key >= 32 and key < 128:
        let ch = char(key)
        if ch in {'0'..'9', '.'}:
          pvpWin.cursorPos = clamp(pvpWin.cursorPos, 0, pvpWin.inputIP.len)
          pvpWin.inputIP = pvpWin.inputIP[0..<pvpWin.cursorPos] & ch & pvpWin.inputIP[pvpWin.cursorPos..^1]
          pvpWin.cursorPos += 1
    elif pvpWin.editingPort:
      if key >= 32 and key < 128:
        let ch = char(key)
        if ch in {'0'..'9'}:
          pvpWin.cursorPos = clamp(pvpWin.cursorPos, 0, pvpWin.inputPort.len)
          pvpWin.inputPort = pvpWin.inputPort[0..<pvpWin.cursorPos] & ch & pvpWin.inputPort[pvpWin.cursorPos..^1]
          pvpWin.cursorPos += 1

    key = getCharPressed()

  # Handle backspace with improved timing (faster repeat)
  let backspacePressed = isKeyPressed(Backspace)
  let backspaceDown = isKeyDown(Backspace)

  # Initial press or repeat after delay
  var shouldDelete = false
  if backspacePressed:
    # First press - delete immediately
    shouldDelete = true
    pvpWin.lastBackspaceTime = 0.0  # Reset timer
  elif backspaceDown:
    # Key held down - use repeat delay
    pvpWin.lastBackspaceTime += getFrameTime()

    # Initial delay of 0.35 seconds, then repeat every 0.04 seconds (faster)
    if pvpWin.lastBackspaceTime >= 0.35:
      shouldDelete = true
      pvpWin.lastBackspaceTime = 0.31  # Keep 0.04s interval (0.35 - 0.04 = 0.31)
  else:
    # Key released - reset timer
    pvpWin.lastBackspaceTime = 0.0

  if shouldDelete:
    # Delete selection or character before cursor
    if pvpWin.selectionStart >= 0 and pvpWin.selectionEnd >= 0 and pvpWin.selectionStart != pvpWin.selectionEnd:
      if activeText != nil:
        let newCursor = deleteSelection(activeText[], pvpWin.selectionStart, pvpWin.selectionEnd)
        if newCursor >= 0:
          pvpWin.cursorPos = newCursor
        pvpWin.selectionStart = -1
        pvpWin.selectionEnd = -1
    else:
      # Delete character before cursor
      if pvpWin.editingNickname and pvpWin.inputNickname.len > 0 and pvpWin.cursorPos > 0:
        # Handle UTF-8 multi-byte characters
        var deletePos = pvpWin.cursorPos - 1
        while deletePos > 0 and (pvpWin.inputNickname[deletePos].ord and 0xC0) == 0x80:
          deletePos -= 1
        pvpWin.inputNickname = pvpWin.inputNickname[0..<deletePos] & pvpWin.inputNickname[pvpWin.cursorPos..^1]
        pvpWin.cursorPos = deletePos
      elif pvpWin.editingIP and pvpWin.inputIP.len > 0 and pvpWin.cursorPos > 0:
        pvpWin.inputIP = pvpWin.inputIP[0..<(pvpWin.cursorPos - 1)] & pvpWin.inputIP[pvpWin.cursorPos..^1]
        pvpWin.cursorPos -= 1
      elif pvpWin.editingPort and pvpWin.inputPort.len > 0 and pvpWin.cursorPos > 0:
        pvpWin.inputPort = pvpWin.inputPort[0..<(pvpWin.cursorPos - 1)] & pvpWin.inputPort[pvpWin.cursorPos..^1]
        pvpWin.cursorPos -= 1

  # Clear selection on Escape
  if isKeyPressed(Escape):
    pvpWin.selectionStart = -1
    pvpWin.selectionEnd = -1

  # Tab navigation
  if isKeyPressed(Tab):
    pvpWin.selectionStart = -1
    pvpWin.selectionEnd = -1

    if pvpWin.state == plsJoining:
      if pvpWin.editingNickname:
        pvpWin.editingNickname = false
        pvpWin.editingIP = true
        pvpWin.editingPort = false
        pvpWin.cursorPos = pvpWin.inputIP.len  # Set cursor to end of IP field
      elif pvpWin.editingIP:
        pvpWin.editingIP = false
        pvpWin.editingPort = true
        pvpWin.editingNickname = false
        pvpWin.cursorPos = pvpWin.inputPort.len  # Set cursor to end of port field
      else:
        pvpWin.editingPort = false
        pvpWin.editingNickname = true
        pvpWin.cursorPos = pvpWin.inputNickname.len  # Set cursor to end of nickname field
    elif pvpWin.state == plsHostingConfig:
      pvpWin.editingNickname = not pvpWin.editingNickname
      if pvpWin.editingNickname:
        pvpWin.cursorPos = pvpWin.inputNickname.len  # Set cursor to end when activating

proc drawPvPWindowContent*(pvpWin: PvPWindow, contentX, contentY, contentWidth, contentHeight: int) =
  case pvpWin.state
  of plsMainMenu:
    let titleText = "PVP MODE"
    let titleWidth = measureText(titleText, 40)
    drawText(titleText, int32(contentX + (contentWidth - titleWidth) div 2), int32(contentY + 80), int32(40), Yellow)
    
    let buttonWidth = 300
    let buttonHeight = 50
    let buttonX = contentX + (contentWidth - buttonWidth) div 2
    let hostButtonY = contentY + 180
    
    let mousePos = getMousePosition()
    
    let hostHovered = mousePos.x >= buttonX.float32 and 
                      mousePos.x <= (buttonX + buttonWidth).float32 and
                      mousePos.y >= hostButtonY.float32 and
                      mousePos.y <= (hostButtonY + buttonHeight).float32
    
    drawRectangle(buttonX.int32, hostButtonY.int32, buttonWidth.int32, buttonHeight.int32,
                 if hostHovered: Color(r: 100, g: 150, b: 255, a: 255) 
                 else: Color(r: 70, g: 100, b: 200, a: 255))
    
    let hostText = "HOST GAME"
    let hostTextWidth = measureText(hostText, 30)
    drawText(hostText, (buttonX + (buttonWidth - hostTextWidth) div 2).int32, (hostButtonY + 10).int32, 30, White)
    
    let joinButtonY = hostButtonY + 80
    let joinHovered = mousePos.x >= buttonX.float32 and
                      mousePos.x <= (buttonX + buttonWidth).float32 and
                      mousePos.y >= joinButtonY.float32 and
                      mousePos.y <= (joinButtonY + buttonHeight).float32
    
    drawRectangle(buttonX.int32, joinButtonY.int32, buttonWidth.int32, buttonHeight.int32,
                 if joinHovered: Color(r: 100, g: 255, b: 150, a: 255)
                 else: Color(r: 70, g: 200, b: 100, a: 255))
    
    let joinText = "JOIN GAME"
    let joinTextWidth = measureText(joinText, 30)
    drawText(joinText, (buttonX + (buttonWidth - joinTextWidth) div 2).int32, (joinButtonY + 10).int32, 30, White)
  
  of plsHostingConfig:
    let titleText = "CONFIGURE HOSTING"
    let titleWidth = measureText(titleText, 30)
    drawText(titleText, (contentX + (contentWidth - titleWidth) div 2).int32, (contentY + 20).int32, 30, Yellow)

    # Nickname field
    drawText("Nickname:", (contentX + 50).int32, (contentY + 62).int32, 20, White)
    let nickFieldX = contentX + 50
    let nickFieldY = contentY + 85
    let nickFieldWidth = contentWidth - 100
    let nickFieldHeight = 36
    drawRectangle(nickFieldX.int32, nickFieldY.int32, nickFieldWidth.int32, nickFieldHeight.int32,
                 if pvpWin.editingNickname: Color(r: 60, g: 60, b: 80, a: 255)
                 else: Color(r: 40, g: 40, b: 50, a: 255))
    drawRectangleLines(
      Rectangle(x: nickFieldX.float32, y: nickFieldY.float32,
               width: nickFieldWidth.float32, height: nickFieldHeight.float32),
      2, if pvpWin.editingNickname: Yellow else: Gray)
    if pvpWin.editingNickname:
      drawTextSelection(pvpWin.inputNickname, nickFieldX, nickFieldY, 20, pvpWin.selectionStart, pvpWin.selectionEnd)
    drawText(pvpWin.inputNickname, (nickFieldX + 10).int32, (nickFieldY + 8).int32, 20, White)
    if pvpWin.editingNickname and (pvpWin.cursorBlink.int mod 2) == 0:
      let textBeforeCursor = if pvpWin.cursorPos > 0 and pvpWin.cursorPos <= pvpWin.inputNickname.len:
        pvpWin.inputNickname[0..<pvpWin.cursorPos] else: ""
      let cursorX = nickFieldX + 10 + measureText(textBeforeCursor, 20)
      drawLine(Vector2(x: cursorX.float32, y: (nickFieldY + 6).float32),
              Vector2(x: cursorX.float32, y: (nickFieldY + 28).float32), 2, White)
    let nickHintText = "Click to edit  |  Tab to toggle"
    let nickHintWidth = measureText(nickHintText, 13)
    drawText(nickHintText, (contentX + (contentWidth - nickHintWidth) div 2).int32,
            (nickFieldY + nickFieldHeight + 4).int32, 13, Color(r: 140, g: 140, b: 140, a: 255))

    # Max Players selector
    let maxPlayersLabelText = "Max Players:"
    let maxPlayersLabelWidth = measureText(maxPlayersLabelText, 22)
    drawText(maxPlayersLabelText, (contentX + (contentWidth - maxPlayersLabelWidth) div 2).int32,
            (contentY + 145).int32, 22, White)

    let playerCountY = contentY + 173
    let buttonSize = 40
    let spacing = 120
    let centerX = contentX + contentWidth div 2
    let mousePos = getMousePosition()

    # Minus button
    let minusButtonX = centerX - spacing
    let minusHovered = mousePos.x >= (minusButtonX - buttonSize div 2).float32 and
                      mousePos.x <= (minusButtonX + buttonSize div 2).float32 and
                      mousePos.y >= playerCountY.float32 and
                      mousePos.y <= (playerCountY + buttonSize).float32
    drawRectangle((minusButtonX - buttonSize div 2).int32, playerCountY.int32, buttonSize.int32, buttonSize.int32,
                 if minusHovered and pvpWin.maxPlayers > 2: Color(r: 150, g: 100, b: 100, a: 255)
                 elif pvpWin.maxPlayers <= 2: Color(r: 80, g: 80, b: 80, a: 255)
                 else: Color(r: 120, g: 70, b: 70, a: 255))
    let minusTextWidth = measureText("-", 30)
    drawText("-", (minusButtonX - minusTextWidth div 2).int32, (playerCountY + 5).int32, 30,
            if pvpWin.maxPlayers <= 2: Gray else: White)

    let countText = $pvpWin.maxPlayers
    let countWidth = measureText(countText, 40)
    drawText(countText, (centerX - countWidth div 2).int32, playerCountY.int32, 40, Yellow)

    # Plus button
    let plusButtonX = centerX + spacing
    let plusHovered = mousePos.x >= (plusButtonX - buttonSize div 2).float32 and
                     mousePos.x <= (plusButtonX + buttonSize div 2).float32 and
                     mousePos.y >= playerCountY.float32 and
                     mousePos.y <= (playerCountY + buttonSize).float32
    drawRectangle((plusButtonX - buttonSize div 2).int32, playerCountY.int32, buttonSize.int32, buttonSize.int32,
                 if plusHovered and pvpWin.maxPlayers < 16: Color(r: 100, g: 150, b: 100, a: 255)
                 elif pvpWin.maxPlayers >= 16: Color(r: 80, g: 80, b: 80, a: 255)
                 else: Color(r: 70, g: 120, b: 70, a: 255))
    let plusTextWidth = measureText("+", 30)
    drawText("+", (plusButtonX - plusTextWidth div 2).int32, (playerCountY + 5).int32, 30,
            if pvpWin.maxPlayers >= 16: Gray else: White)

    # Divider
    drawLine(Vector2(x: (contentX + 20).float32, y: (contentY + 225).float32),
            Vector2(x: (contentX + contentWidth - 20).float32, y: (contentY + 225).float32),
            1, Color(r: 80, g: 80, b: 80, a: 255))

    # Show IPs checkbox
    let checkboxX = contentX + 50
    let checkboxY = contentY + 237
    let checkboxSize = 20
    let checkboxHovered = mousePos.x >= checkboxX.float32 and
                         mousePos.x <= (checkboxX + checkboxSize + 200).float32 and
                         mousePos.y >= checkboxY.float32 and
                         mousePos.y <= (checkboxY + checkboxSize).float32
    drawRectangle(checkboxX.int32, checkboxY.int32, checkboxSize.int32, checkboxSize.int32,
                 Color(r: 40, g: 40, b: 50, a: 255))
    drawRectangleLines(Rectangle(x: checkboxX.float32, y: checkboxY.float32,
               width: checkboxSize.float32, height: checkboxSize.float32), 2,
               if checkboxHovered: Yellow else: Gray)
    if pvpWin.showIPs:
      drawLine(Vector2(x: (checkboxX + 4).float32, y: (checkboxY + 10).float32),
              Vector2(x: (checkboxX + 8).float32, y: (checkboxY + 14).float32), 2, Green)
      drawLine(Vector2(x: (checkboxX + 8).float32, y: (checkboxY + 14).float32),
              Vector2(x: (checkboxX + 16).float32, y: (checkboxY + 6).float32), 2, Green)
    drawText("Show IPs in lobby", (checkboxX + checkboxSize + 10).int32, checkboxY.int32, 18, White)

    # Divider
    drawLine(Vector2(x: (contentX + 20).float32, y: (contentY + 267).float32),
            Vector2(x: (contentX + contentWidth - 20).float32, y: (contentY + 267).float32),
            1, Color(r: 80, g: 80, b: 80, a: 255))

    # Teams section header
    drawText("Teams Mode", (contentX + 50).int32, (contentY + 277).int32, 20, White)

    # Enable Teams checkbox
    let teamCheckboxX = contentX + 50
    let teamCheckboxY = contentY + 303
    let teamCheckboxSize = 20
    let teamCheckboxHovered = mousePos.x >= teamCheckboxX.float32 and
                              mousePos.x <= (teamCheckboxX + teamCheckboxSize + 220).float32 and
                              mousePos.y >= teamCheckboxY.float32 and
                              mousePos.y <= (teamCheckboxY + teamCheckboxSize).float32
    drawRectangle(teamCheckboxX.int32, teamCheckboxY.int32, teamCheckboxSize.int32, teamCheckboxSize.int32,
                 Color(r: 40, g: 40, b: 50, a: 255))
    drawRectangleLines(Rectangle(x: teamCheckboxX.float32, y: teamCheckboxY.float32,
               width: teamCheckboxSize.float32, height: teamCheckboxSize.float32), 2,
               if teamCheckboxHovered: Yellow else: Gray)
    if pvpWin.teamsEnabled:
      drawLine(Vector2(x: (teamCheckboxX + 4).float32, y: (teamCheckboxY + 10).float32),
              Vector2(x: (teamCheckboxX + 8).float32, y: (teamCheckboxY + 14).float32), 2, Green)
      drawLine(Vector2(x: (teamCheckboxX + 8).float32, y: (teamCheckboxY + 14).float32),
              Vector2(x: (teamCheckboxX + 16).float32, y: (teamCheckboxY + 6).float32), 2, Green)
    drawText("Enable Teams Game Mode", (teamCheckboxX + teamCheckboxSize + 10).int32, teamCheckboxY.int32, 18, White)

    # Number of teams selector (only show if teams enabled)
    if pvpWin.teamsEnabled:
      drawText("Number of Teams:", (contentX + 50).int32, (contentY + 337).int32, 18, White)

      let teamButtonY = contentY + 335
      let teamButtonWidth = 44
      let teamButtonSpacing = 58
      let teamStartX = contentX + 220

      for teamCount in 2..4:
        let btnX = teamStartX + (teamCount - 2) * teamButtonSpacing
        let isSelected = pvpWin.numTeams == teamCount
        let isBtnHovered = mousePos.x >= btnX.float32 and
                        mousePos.x <= (btnX + teamButtonWidth).float32 and
                        mousePos.y >= teamButtonY.float32 and
                        mousePos.y <= (teamButtonY + 34).float32
        drawRectangle(btnX.int32, teamButtonY.int32, teamButtonWidth.int32, 34,
                     if isSelected: Color(r: 100, g: 200, b: 100, a: 255)
                     elif isBtnHovered: Color(r: 80, g: 160, b: 80, a: 255)
                     else: Color(r: 50, g: 110, b: 50, a: 255))
        let btnText = $teamCount
        let btnTextWidth = measureText(btnText, 22)
        drawText(btnText, (btnX + (teamButtonWidth - btnTextWidth) div 2).int32,
                (teamButtonY + 6).int32, 22, White)

    # START HOSTING button
    let startButtonX = contentX + (contentWidth - 250) div 2
    let startButtonY = contentY + contentHeight - 120
    let startHovered = mousePos.x >= startButtonX.float32 and
                      mousePos.x <= (startButtonX + 250).float32 and
                      mousePos.y >= startButtonY.float32 and
                      mousePos.y <= (startButtonY + 60).float32
    drawRectangle(startButtonX.int32, startButtonY.int32, 250, 60,
                 if startHovered: Color(r: 100, g: 200, b: 100, a: 255)
                 else: Color(r: 70, g: 150, b: 70, a: 255))
    let startText = "START HOSTING"
    let startTextWidth = measureText(startText, 26)
    drawText(startText, (startButtonX + (250 - startTextWidth) div 2).int32,
            (startButtonY + 17).int32, 26, White)

    # CANCEL button
    let cancelButtonY = startButtonY + 70
    let cancelHovered = mousePos.x >= startButtonX.float32 and
                       mousePos.x <= (startButtonX + 250).float32 and
                       mousePos.y >= cancelButtonY.float32 and
                       mousePos.y <= (cancelButtonY + 50).float32
    drawRectangle(startButtonX.int32, cancelButtonY.int32, 250, 50,
                 if cancelHovered: Color(r: 200, g: 100, b: 100, a: 255)
                 else: Color(r: 150, g: 70, b: 70, a: 255))
    let cancelText = "CANCEL"
    let cancelTextWidth = measureText(cancelText, 25)
    drawText(cancelText, (startButtonX + (250 - cancelTextWidth) div 2).int32,
            (cancelButtonY + 12).int32, 25, White)

  of plsHostingActive:
    let titleText = "HOSTING GAME"
    let titleWidth = measureText(titleText, 30)
    drawText(titleText, (contentX + (contentWidth - titleWidth) div 2).int32, (contentY + 30).int32, 30, Yellow)

    # Display local IP
    let localIPDisplay = if pvpWin.showIPs: pvpWin.hostIP else: censorIP(pvpWin.hostIP)
    let ipText = "Local IP: " & localIPDisplay
    let ipWidth = measureText(ipText, 16)
    drawText(ipText, (contentX + (contentWidth - ipWidth) div 2).int32, (contentY + 70).int32, 16, White)

    let portText = "Port: " & $pvpWin.hostPort
    let portWidth = measureText(portText, 16)
    drawText(portText, (contentX + (contentWidth - portWidth) div 2).int32, (contentY + 90).int32, 16, White)

    # Display max players and current count
    let connectedCount = pvpWin.networkManager.getConnectedPlayerCount()
    let maxPlayersText = "Players: " & $connectedCount & " / " & $pvpWin.maxPlayers
    let maxPlayersWidth = measureText(maxPlayersText, 16)
    drawText(maxPlayersText, (contentX + (contentWidth - maxPlayersWidth) div 2).int32,
            (contentY + 110).int32, 16,
            if connectedCount >= pvpWin.maxPlayers: Green else: Color(r: 200, g: 200, b: 200, a: 255))

    # Show player list with team assignments (if teams enabled)
    if pvpWin.teamsEnabled:
      drawText("Click player to assign team:", (contentX + 30).int32, (contentY + 140).int32, 14, White)

      # Host (you) — always on Red team
      let hostTeam = getTeamForPlayer(0, pvpWin.numTeams)
      let hostTeamColor = getTeamColor(hostTeam)
      drawText("- You (Host) - " & getTeamName(hostTeam), (contentX + 50).int32, (contentY + 160).int32, 14, hostTeamColor)

      # Connected clients with clickable team assignment
      var yOffset = 160
      for i, client in pvpWin.networkManager.clients:
        yOffset += 20
        let playerIndex = client.playerIndex  # playerIndex is already correct (host=0, first client=1, etc.)
        # Get assigned team for this player (default or manual assignment)
        var playerTeam = getTeamForPlayer(playerIndex, pvpWin.numTeams)
        if playerIndex >= 0 and playerIndex < pvpWin.playerTeamAssignments.len:
          playerTeam = PvPTeam(pvpWin.playerTeamAssignments[playerIndex])
        let playerTeamColor = getTeamColor(playerTeam)
        let nick = if client.nickname.len > 0: client.nickname else: "Player " & $(playerIndex + 1)
        let playerText = "- " & nick & " - " & getTeamName(playerTeam)
        drawText(playerText, (contentX + 50).int32, (contentY + yOffset).int32, 14, playerTeamColor)

      drawText("Teams mode enabled", (contentX + 30).int32, (contentY + contentHeight - 140).int32, 12,
               Color(r: 150, g: 150, b: 150, a: 255))
    else:
      # No teams - just show connected players
      drawText("Connected Players:", (contentX + 30).int32, (contentY + 140).int32, 14, White)

      # Host (you)
      let hostNick = if pvpWin.inputNickname.len > 0: pvpWin.inputNickname else: "Host"
      drawText("- " & hostNick & " (You - Host)", (contentX + 50).int32, (contentY + 160).int32, 14, Yellow)

      # Connected clients
      var yOffset = 160
      for i, client in pvpWin.networkManager.clients:
        yOffset += 20
        let nick = if client.nickname.len > 0: client.nickname else: "Player " & $(client.playerIndex + 1)
        let playerText = "- " & nick
        drawText(playerText, (contentX + 50).int32, (contentY + yOffset).int32, 14, Green)

    # Show IPs checkbox
    let checkboxX = contentX + (contentWidth - 200) div 2
    let checkboxY = contentY + contentHeight - 140
    let checkboxSize = 20
    let mousePos = getMousePosition()
    let checkboxHovered = mousePos.x >= checkboxX.float32 and
                         mousePos.x <= (checkboxX + checkboxSize + 150).float32 and
                         mousePos.y >= checkboxY.float32 and
                         mousePos.y <= (checkboxY + checkboxSize).float32

    # Draw checkbox
    drawRectangle(checkboxX.int32, checkboxY.int32, checkboxSize.int32, checkboxSize.int32,
                 Color(r: 40, g: 40, b: 50, a: 255))
    drawRectangleLines(
      Rectangle(x: checkboxX.float32, y: checkboxY.float32,
               width: checkboxSize.float32, height: checkboxSize.float32),
      2, if checkboxHovered: Yellow else: Gray)

    # Draw checkmark if checked
    if pvpWin.showIPs:
      drawLine(Vector2(x: (checkboxX + 4).float32, y: (checkboxY + 10).float32),
              Vector2(x: (checkboxX + 8).float32, y: (checkboxY + 14).float32), 2, Green)
      drawLine(Vector2(x: (checkboxX + 8).float32, y: (checkboxY + 14).float32),
              Vector2(x: (checkboxX + 16).float32, y: (checkboxY + 6).float32), 2, Green)

    # Checkbox label
    drawText("Show IP", (checkboxX + checkboxSize + 10).int32, checkboxY.int32, 16, White)

    # Cancel button
    let cancelButtonX = contentX + (contentWidth - 200) div 2
    let cancelButtonY = contentY + contentHeight - 80
    let cancelHovered2 = mousePos.x >= cancelButtonX.float32 and
                        mousePos.x <= (cancelButtonX + 200).float32 and
                        mousePos.y >= cancelButtonY.float32 and
                        mousePos.y <= (cancelButtonY + 50).float32

    drawRectangle(cancelButtonX.int32, cancelButtonY.int32, 200, 50,
                 if cancelHovered2: Color(r: 200, g: 100, b: 100, a: 255)
                 else: Color(r: 150, g: 70, b: 70, a: 255))
    let cancelText = "CANCEL"
    let cancelTextWidth = measureText(cancelText, 20)
    drawText(cancelText, (cancelButtonX + (200 - cancelTextWidth) div 2).int32,
            (cancelButtonY + 15).int32, 20, White)
  
  of plsJoining:
    let titleText = "JOIN GAME"
    let titleWidth = measureText(titleText, 30)
    drawText(titleText, (contentX + (contentWidth - titleWidth) div 2).int32, (contentY + 30).int32, 30, Yellow)

    # Nickname field
    let joinNickLabelText = "Nickname:"
    drawText(joinNickLabelText, (contentX + 50).int32, (contentY + 72).int32, 20, White)
    let joinNickFieldX = contentX + 50
    let joinNickFieldY = contentY + 96
    let joinNickFieldWidth = contentWidth - 100
    let joinNickFieldHeight = 36
    drawRectangle(joinNickFieldX.int32, joinNickFieldY.int32, joinNickFieldWidth.int32, joinNickFieldHeight.int32,
                 if pvpWin.editingNickname: Color(r: 60, g: 60, b: 80, a: 255)
                 else: Color(r: 40, g: 40, b: 50, a: 255))
    drawRectangleLines(
      Rectangle(x: joinNickFieldX.float32, y: joinNickFieldY.float32,
               width: joinNickFieldWidth.float32, height: joinNickFieldHeight.float32),
      2, if pvpWin.editingNickname: Yellow else: Gray)
    # Draw selection highlight if active
    if pvpWin.editingNickname:
      drawTextSelection(pvpWin.inputNickname, joinNickFieldX, joinNickFieldY, 20, pvpWin.selectionStart, pvpWin.selectionEnd)
    drawText(pvpWin.inputNickname, (joinNickFieldX + 10).int32, (joinNickFieldY + 8).int32, 20, White)
    if pvpWin.editingNickname and (pvpWin.cursorBlink.int mod 2) == 0:
      let textBeforeCursor = if pvpWin.cursorPos > 0 and pvpWin.cursorPos <= pvpWin.inputNickname.len:
        pvpWin.inputNickname[0..<pvpWin.cursorPos]
      else:
        ""
      let nickCursorX = joinNickFieldX + 10 + measureText(textBeforeCursor, 20)
      drawLine(Vector2(x: nickCursorX.float32, y: (joinNickFieldY + 6).float32),
              Vector2(x: nickCursorX.float32, y: (joinNickFieldY + 28).float32), 2, White)
    let joinNickHint = "Click to edit  |  Tab to cycle"
    let joinNickHintW = measureText(joinNickHint, 13)
    drawText(joinNickHint, (contentX + (contentWidth - joinNickHintW) div 2).int32,
            (joinNickFieldY + joinNickFieldHeight + 4).int32, 13, Color(r: 140, g: 140, b: 140, a: 255))

    let ipLabelText = "Host IP:"
    drawText(ipLabelText, (contentX + 50).int32, (contentY + 148).int32, 22, White)

    let ipFieldX = contentX + 50
    let ipFieldY = contentY + 172
    let ipFieldWidth = contentWidth - 100
    let ipFieldHeight = 40

    drawRectangle(ipFieldX.int32, ipFieldY.int32, ipFieldWidth.int32, ipFieldHeight.int32,
                 if pvpWin.editingIP: Color(r: 60, g: 60, b: 80, a: 255)
                 else: Color(r: 40, g: 40, b: 50, a: 255))
    drawRectangleLines(
      Rectangle(x: ipFieldX.float32, y: ipFieldY.float32,
               width: ipFieldWidth.float32, height: ipFieldHeight.float32),
      2, if pvpWin.editingIP: Yellow else: Gray)

    # Draw selection highlight if active
    if pvpWin.editingIP:
      drawTextSelection(pvpWin.inputIP, ipFieldX, ipFieldY, 20, pvpWin.selectionStart, pvpWin.selectionEnd)
    drawText(pvpWin.inputIP, (ipFieldX + 10).int32, (ipFieldY + 10).int32, 20, White)

    if pvpWin.editingIP and (pvpWin.cursorBlink.int mod 2) == 0:
      let textBeforeCursor = if pvpWin.cursorPos > 0 and pvpWin.cursorPos <= pvpWin.inputIP.len:
        pvpWin.inputIP[0..<pvpWin.cursorPos]
      else:
        ""
      let cursorX = ipFieldX + 10 + measureText(textBeforeCursor, 20)
      drawLine(Vector2(x: cursorX.float32, y: (ipFieldY + 10).float32),
              Vector2(x: cursorX.float32, y: (ipFieldY + 30).float32), 2, White)

    let portLabelText = "Port:"
    drawText(portLabelText, (contentX + 50).int32, (contentY + 224).int32, 22, White)

    let portFieldY = contentY + 250
    drawRectangle(ipFieldX.int32, portFieldY.int32, ipFieldWidth.int32, ipFieldHeight.int32,
                 if pvpWin.editingPort: Color(r: 60, g: 60, b: 80, a: 255)
                 else: Color(r: 40, g: 40, b: 50, a: 255))
    drawRectangleLines(
      Rectangle(x: ipFieldX.float32, y: portFieldY.float32,
               width: ipFieldWidth.float32, height: ipFieldHeight.float32),
      2, if pvpWin.editingPort: Yellow else: Gray)

    # Draw selection highlight if active
    if pvpWin.editingPort:
      drawTextSelection(pvpWin.inputPort, ipFieldX, portFieldY, 20, pvpWin.selectionStart, pvpWin.selectionEnd)
    drawText(pvpWin.inputPort, (ipFieldX + 10).int32, (portFieldY + 10).int32, 20, White)

    if pvpWin.editingPort and (pvpWin.cursorBlink.int mod 2) == 0:
      let textBeforeCursor = if pvpWin.cursorPos > 0 and pvpWin.cursorPos <= pvpWin.inputPort.len:
        pvpWin.inputPort[0..<pvpWin.cursorPos]
      else:
        ""
      let cursorX = ipFieldX + 10 + measureText(textBeforeCursor, 20)
      drawLine(Vector2(x: cursorX.float32, y: (portFieldY + 10).float32),
              Vector2(x: cursorX.float32, y: (portFieldY + 30).float32), 2, White)

    let connectButtonX = contentX + (contentWidth - 200) div 2
    let connectButtonY = contentY + 308
    let mousePos = getMousePosition()
    let connectHovered = mousePos.x >= connectButtonX.float32 and
                        mousePos.x <= (connectButtonX + 200).float32 and
                        mousePos.y >= connectButtonY.float32 and
                        mousePos.y <= (connectButtonY + 50).float32

    drawRectangle(connectButtonX.int32, connectButtonY.int32, 200, 50,
                 if connectHovered: Color(r: 100, g: 255, b: 150, a: 255)
                 else: Color(r: 70, g: 200, b: 100, a: 255))
    let connectText = "CONNECT"
    let connectTextWidth = measureText(connectText, 25)
    drawText(connectText, (connectButtonX + (200 - connectTextWidth) div 2).int32,
            (connectButtonY + 12).int32, 25, White)

    # Back button
    let backButtonY = connectButtonY + 62
    let backHovered = mousePos.x >= connectButtonX.float32 and
                     mousePos.x <= (connectButtonX + 200).float32 and
                     mousePos.y >= backButtonY.float32 and
                     mousePos.y <= (backButtonY + 50).float32

    drawRectangle(connectButtonX.int32, backButtonY.int32, 200, 50,
                 if backHovered: Color(r: 200, g: 100, b: 100, a: 255)
                 else: Color(r: 150, g: 70, b: 70, a: 255))
    let backText = "BACK"
    let backTextWidth = measureText(backText, 25)
    drawText(backText, (connectButtonX + (200 - backTextWidth) div 2).int32,
            (backButtonY + 12).int32, 25, White)
  
  of plsConnecting:
    let titleText = "CONNECTING..."
    let titleWidth = measureText(titleText, 30)
    drawText(titleText, (contentX + (contentWidth - titleWidth) div 2).int32, (contentY + contentHeight div 2 - 50).int32, 
            30, Yellow)
    
    let dots = ".".repeat(((pvpWin.cursorBlink * 2).int mod 4))
    let statusText = "Please wait" & dots
    let statusWidth = measureText(statusText, 22)
    drawText(statusText, (contentX + (contentWidth - statusWidth) div 2).int32, 
            (contentY + contentHeight div 2).int32, 22, White)
    
    let timeoutText = "Timeout in " & $pvpWin.connectionTimeout.int & "s"
    let timeoutWidth = measureText(timeoutText, 18)
    drawText(timeoutText, (contentX + (contentWidth - timeoutWidth) div 2).int32,
            (contentY + contentHeight div 2 + 40).int32, 18, Gray)
  
  of plsConnected:
    if pvpWin.isHost:
      # Host lobby - show connected players and START GAME button
      let titleText = "GAME LOBBY"
      let titleWidth = measureText(titleText, 35)
      drawText(titleText, (contentX + (contentWidth - titleWidth) div 2).int32, 
              (contentY + 20).int32, 35, Green)
      
      # Show player count
      let playerCount = pvpWin.networkManager.getConnectedPlayerCount()
      let playerCountText = "Players: " & $playerCount & " / " & $pvpWin.maxPlayers
      let playerCountWidth = measureText(playerCountText, 22)
      drawText(playerCountText, (contentX + (contentWidth - playerCountWidth) div 2).int32,
              (contentY + 70).int32, 22, if playerCount >= 2: Green else: Yellow)
      
      # List connected players
      let listY = contentY + 110
      drawText("Connected Players:", (contentX + 30).int32, listY.int32, 20, White)
      if pvpWin.teamsEnabled:
        drawText("(click badge to change team)", (contentX + 30).int32, (listY + 18).int32, 12,
                Color(r: 130, g: 130, b: 130, a: 255))

      # Host (you) — show own nickname with team badge
      let hostNick = if pvpWin.inputNickname.len > 0: pvpWin.inputNickname else: "Host"
      drawText("- " & hostNick & " (You)", (contentX + 50).int32, (listY + 35).int32, 18, Yellow)
      if pvpWin.teamsEnabled and pvpWin.playerTeamAssignments.len > 0:
        let hostTeam = PvPTeam(pvpWin.playerTeamAssignments[0])
        let hostTeamColor = getTeamColor(hostTeam)
        let hBadgeX = contentX + 260
        let hBadgeY = listY + 35
        drawRectangle(hBadgeX.int32, hBadgeY.int32, 58, 20, Color(r: 25, g: 25, b: 35, a: 255))
        drawRectangleLines(Rectangle(x: hBadgeX.float32, y: hBadgeY.float32, width: 58.0, height: 20.0), 2, hostTeamColor)
        let hTN = getTeamName(hostTeam)
        let hTNW = measureText(hTN, 13)
        drawText(hTN, (hBadgeX + (58 - hTNW) div 2).int32, (hBadgeY + 4).int32, 13, hostTeamColor)
        drawText("click", (hBadgeX + 62).int32, (hBadgeY + 4).int32, 11, Color(r: 130, g: 130, b: 130, a: 255))

      # Connected clients with their nicknames and team badges
      var yOffset = 35
      for i, client in pvpWin.networkManager.clients:
        yOffset += 25
        let nick = if client.nickname.len > 0: client.nickname else: "Player " & $(client.playerIndex + 1)
        if pvpWin.teamsEnabled:
          let playerIndex = client.playerIndex  # playerIndex is already correct (host=0, first client=1, etc.)
          var playerTeam = getTeamForPlayer(playerIndex, pvpWin.numTeams)
          if playerIndex >= 0 and playerIndex < pvpWin.playerTeamAssignments.len:
            playerTeam = PvPTeam(pvpWin.playerTeamAssignments[playerIndex])
          let playerTeamColor = getTeamColor(playerTeam)
          drawText("- " & nick, (contentX + 50).int32, (listY + yOffset).int32, 18, White)
          let pBadgeX = contentX + 260
          let pBadgeY = listY + yOffset
          drawRectangle(pBadgeX.int32, pBadgeY.int32, 58, 20, Color(r: 25, g: 25, b: 35, a: 255))
          drawRectangleLines(Rectangle(x: pBadgeX.float32, y: pBadgeY.float32, width: 58.0, height: 20.0), 2, playerTeamColor)
          let pTN = getTeamName(playerTeam)
          let pTNW = measureText(pTN, 13)
          drawText(pTN, (pBadgeX + (58 - pTNW) div 2).int32, (pBadgeY + 4).int32, 13, playerTeamColor)
          drawText("click", (pBadgeX + 62).int32, (pBadgeY + 4).int32, 11, Color(r: 130, g: 130, b: 130, a: 255))
        else:
          let playerText = "- " & nick & "  (P" & $(client.playerIndex + 1) & ")"
          drawText(playerText, (contentX + 50).int32, (listY + yOffset).int32, 18, Green)
      
      # START GAME button (only if at least 2 players)
      let startButtonX = contentX + (contentWidth - 250) div 2
      let startButtonY = contentY + contentHeight - 120
      let canStart = playerCount >= 2
      
      let mousePos = getMousePosition()
      let startHovered = mousePos.x >= startButtonX.float32 and
                        mousePos.x <= (startButtonX + 250).float32 and
                        mousePos.y >= startButtonY.float32 and
                        mousePos.y <= (startButtonY + 60).float32
      
      drawRectangle(startButtonX.int32, startButtonY.int32, 250, 60,
                   if not canStart: Color(r: 80, g: 80, b: 80, a: 255)
                   elif startHovered: Color(r: 100, g: 255, b: 100, a: 255)
                   else: Color(r: 70, g: 200, b: 70, a: 255))
      
      let startText = if canStart: "START GAME" else: "NEED 2+ PLAYERS"
      let startTextWidth = measureText(startText, 26)
      drawText(startText, (startButtonX + (250 - startTextWidth) div 2).int32,
              (startButtonY + 17).int32, 26, if canStart: White else: Gray)
      
      # CANCEL button
      let cancelButtonY = startButtonY + 70
      let cancelHovered = mousePos.x >= startButtonX.float32 and
                         mousePos.x <= (startButtonX + 250).float32 and
                         mousePos.y >= cancelButtonY.float32 and
                         mousePos.y <= (cancelButtonY + 50).float32
      
      drawRectangle(startButtonX.int32, cancelButtonY.int32, 250, 50,
                   if cancelHovered: Color(r: 200, g: 100, b: 100, a: 255)
                   else: Color(r: 150, g: 70, b: 70, a: 255))
      
      let cancelText = "CANCEL"
      let cancelTextWidth = measureText(cancelText, 25)
      drawText(cancelText, (startButtonX + (250 - cancelTextWidth) div 2).int32,
              (cancelButtonY + 12).int32, 25, White)
    else:
      # Client - show connected players and wait for host
      let titleText = "CONNECTED!"
      let titleWidth = measureText(titleText, 35)
      drawText(titleText, (contentX + (contentWidth - titleWidth) div 2).int32,
              (contentY + 20).int32, 35, Green)

      # Show player roster if we have it
      if pvpWin.connectedPlayers.len > 0:
        drawText("Players in lobby:", (contentX + 30).int32, (contentY + 75).int32, 20, White)
        var pYOffset = 0
        for cp in pvpWin.connectedPlayers:
          let nick = if cp.nickname.len > 0: cp.nickname else: "Player " & $(cp.index + 1)
          let isMe = cp.index == pvpWin.assignedPlayerIndex
          let label = "- " & nick & (if isMe: "  (You)" else: "  (P" & $(cp.index + 1) & ")")
          drawText(label, (contentX + 50).int32, (contentY + 105 + pYOffset).int32, 18,
                  if isMe: Yellow else: Green)
          pYOffset += 25

      let statusText = "Waiting for host to start..."
      let statusWidth = measureText(statusText, 20)
      drawText(statusText,
              (contentX + (contentWidth - statusWidth) div 2).int32,
              (contentY + contentHeight - 80).int32, 20,
              Color(r: 200, g: 200, b: 200, a: 255))
  
  of plsError:
    let titleText = "CONNECTION ERROR"
    let titleWidth = measureText(titleText, 30)
    drawText(titleText, (contentX + (contentWidth - titleWidth) div 2).int32, (contentY + 80).int32, 30, Red)
    
    let errorWidth = measureText(pvpWin.errorMessage, 20)
    drawText(pvpWin.errorMessage, (contentX + (contentWidth - errorWidth) div 2).int32, (contentY + 150).int32, 20, White)
    
    # Back button
    let backButtonX = contentX + (contentWidth - 200) div 2
    let backButtonY = contentY + contentHeight - 100
    let mousePos = getMousePosition()
    let backHovered = mousePos.x >= backButtonX.float32 and
                     mousePos.x <= (backButtonX + 200).float32 and
                     mousePos.y >= backButtonY.float32 and
                     mousePos.y <= (backButtonY + 50).float32
    
    drawRectangle(backButtonX.int32, backButtonY.int32, 200, 50,
                 if backHovered: Color(r: 200, g: 100, b: 100, a: 255)
                 else: Color(r: 150, g: 70, b: 70, a: 255))
    let backText = "BACK"
    let backTextWidth = measureText(backText, 25)
    drawText(backText, (backButtonX + (200 - backTextWidth) div 2).int32,
            (backButtonY + 12).int32, 25, White)

proc handlePvPWindowClick*(pvpWin: PvPWindow, contentX, contentY, contentWidth, contentHeight: int): int =
  ## Returns: 0 = no action, 1 = host config, 2 = join, 3 = back/cancel, 4 = connect, 5 = start game, 6 = start hosting
  if not isMouseButtonPressed(Left):
    return 0

  let mousePos = getMousePosition()

  case pvpWin.state
  of plsMainMenu:
    let buttonWidth = 300
    let buttonHeight = 50
    let buttonX = contentX + (contentWidth - buttonWidth) div 2
    let hostButtonY = contentY + 180

    if mousePos.x >= buttonX.float32 and
       mousePos.x <= (buttonX + buttonWidth).float32 and
       mousePos.y >= hostButtonY.float32 and
       mousePos.y <= (hostButtonY + buttonHeight).float32:
      return 1  # Go to host config

    let joinButtonY = hostButtonY + 80
    if mousePos.x >= buttonX.float32 and
       mousePos.x <= (buttonX + buttonWidth).float32 and
       mousePos.y >= joinButtonY.float32 and
       mousePos.y <= (joinButtonY + buttonHeight).float32:
      return 2  # Join

  of plsHostingConfig:
    # Nickname field click
    let hostNickFieldX = contentX + 50
    let hostNickFieldY = contentY + 85
    let hostNickFieldW = contentWidth - 100
    if mousePos.x >= hostNickFieldX.float32 and
       mousePos.x <= (hostNickFieldX + hostNickFieldW).float32 and
       mousePos.y >= hostNickFieldY.float32 and
       mousePos.y <= (hostNickFieldY + 36).float32:
      pvpWin.editingNickname = true
      let cursorPos = getTextCursorPos(pvpWin.inputNickname, hostNickFieldX, hostNickFieldY + 8, 20, 28, mousePos.x, mousePos.y)
      if cursorPos >= 0:
        pvpWin.cursorPos = cursorPos
        pvpWin.mouseDownPos = mousePos
        pvpWin.isDragging = true
        pvpWin.selectionStart = cursorPos
        pvpWin.selectionEnd = cursorPos
      return 0
    else:
      pvpWin.editingNickname = false

    # Player count buttons (Y=173)
    let playerCountY = contentY + 173
    let buttonSize = 40
    let spacing = 120
    let centerX = contentX + contentWidth div 2

    let minusButtonX = centerX - spacing
    if mousePos.x >= (minusButtonX - buttonSize div 2).float32 and
       mousePos.x <= (minusButtonX + buttonSize div 2).float32 and
       mousePos.y >= playerCountY.float32 and
       mousePos.y <= (playerCountY + buttonSize).float32:
      if pvpWin.maxPlayers > 2: pvpWin.maxPlayers -= 1
      return 0

    let plusButtonX = centerX + spacing
    if mousePos.x >= (plusButtonX - buttonSize div 2).float32 and
       mousePos.x <= (plusButtonX + buttonSize div 2).float32 and
       mousePos.y >= playerCountY.float32 and
       mousePos.y <= (playerCountY + buttonSize).float32:
      if pvpWin.maxPlayers < 16: pvpWin.maxPlayers += 1
      return 0

    # Show IPs checkbox (Y=237)
    let checkboxX = contentX + 50
    let checkboxY = contentY + 237
    let checkboxSize = 20
    if mousePos.x >= checkboxX.float32 and
       mousePos.x <= (checkboxX + checkboxSize + 200).float32 and
       mousePos.y >= checkboxY.float32 and
       mousePos.y <= (checkboxY + checkboxSize).float32:
      pvpWin.showIPs = not pvpWin.showIPs
      return 0

    # Teams enable checkbox (Y=303)
    let teamCheckboxX = contentX + 50
    let teamCheckboxY = contentY + 303
    let teamCheckboxSize = 20
    if mousePos.x >= teamCheckboxX.float32 and
       mousePos.x <= (teamCheckboxX + teamCheckboxSize + 220).float32 and
       mousePos.y >= teamCheckboxY.float32 and
       mousePos.y <= (teamCheckboxY + teamCheckboxSize).float32:
      pvpWin.teamsEnabled = not pvpWin.teamsEnabled
      return 0

    # Team count buttons (only if teams enabled, Y=335)
    if pvpWin.teamsEnabled:
      let teamButtonY = contentY + 335
      let teamButtonWidth = 44
      let teamButtonSpacing = 58
      let teamStartX = contentX + 220
      for teamCount in 2..4:
        let btnX = teamStartX + (teamCount - 2) * teamButtonSpacing
        if mousePos.x >= btnX.float32 and
           mousePos.x <= (btnX + teamButtonWidth).float32 and
           mousePos.y >= teamButtonY.float32 and
           mousePos.y <= (teamButtonY + 34).float32:
          pvpWin.numTeams = teamCount
          return 0

    # START HOSTING button
    let startButtonX = contentX + (contentWidth - 250) div 2
    let startButtonY = contentY + contentHeight - 120
    if mousePos.x >= startButtonX.float32 and
       mousePos.x <= (startButtonX + 250).float32 and
       mousePos.y >= startButtonY.float32 and
       mousePos.y <= (startButtonY + 60).float32:
      return 6

    let cancelButtonY = startButtonY + 70
    if mousePos.x >= startButtonX.float32 and
       mousePos.x <= (startButtonX + 250).float32 and
       mousePos.y >= cancelButtonY.float32 and
       mousePos.y <= (cancelButtonY + 50).float32:
      return 3

  of plsHostingActive:
    # Check for checkbox click
    let checkboxX = contentX + (contentWidth - 200) div 2
    let checkboxY = contentY + contentHeight - 140
    let checkboxSize = 20
    if mousePos.x >= checkboxX.float32 and
       mousePos.x <= (checkboxX + checkboxSize + 150).float32 and
       mousePos.y >= checkboxY.float32 and
       mousePos.y <= (checkboxY + checkboxSize).float32:
      pvpWin.showIPs = not pvpWin.showIPs  # Toggle checkbox
      return 0

    # Check for player clicks (team assignment - only if teams enabled)
    if pvpWin.teamsEnabled:
      let playerListStartY = contentY + 160  # Where host is drawn
      let playerEntryHeight = 20
      let playerListEndY = playerListStartY + (pvpWin.networkManager.clients.len + 1) * playerEntryHeight

      # Check if click is in player list area
      if mousePos.y >= playerListStartY.float32 and mousePos.y <= playerListEndY.float32:
        # Determine which player was clicked
        let relativeY = (mousePos.y - playerListStartY.float32).int
        let clickedPlayerSlot = relativeY div playerEntryHeight

        # Slot 0 is the host - don't allow reassigning the host
        if clickedPlayerSlot > 0 and clickedPlayerSlot <= pvpWin.networkManager.clients.len:
          # This is a real player (not the host)
          let clientIndex = clickedPlayerSlot - 1
          if clientIndex >= 0 and clientIndex < pvpWin.networkManager.clients.len:
            let client = pvpWin.networkManager.clients[clientIndex]
            let playerIndex = client.playerIndex  # playerIndex is already correct (host=0, first client=1, etc.)

            # Ensure playerTeamAssignments is large enough
            while pvpWin.playerTeamAssignments.len <= playerIndex:
              pvpWin.playerTeamAssignments.add(1)  # Start at ptRed (1), not ptNone (0)

            # Cycle to next team (1-4 range, skipping 0 which is ptNone)
            let currentTeam = pvpWin.playerTeamAssignments[playerIndex]
            pvpWin.playerTeamAssignments[playerIndex] = ((currentTeam - 1 + 1) mod pvpWin.numTeams) + 1
            return 0

    # Check for cancel button
    let cancelButtonX = contentX + (contentWidth - 200) div 2
    let cancelButtonY = contentY + contentHeight - 80
    if mousePos.x >= cancelButtonX.float32 and
       mousePos.x <= (cancelButtonX + 200).float32 and
       mousePos.y >= cancelButtonY.float32 and
       mousePos.y <= (cancelButtonY + 50).float32:
      return 3  # Cancel

  of plsJoining:
    let ipFieldX = contentX + 50
    let ipFieldWidth = contentWidth - 100
    let ipFieldHeight = 40

    # Nickname field (contentY + 96, height 36)
    let joinNickFieldY = contentY + 96
    if mousePos.x >= ipFieldX.float32 and
       mousePos.x <= (ipFieldX + ipFieldWidth).float32 and
       mousePos.y >= joinNickFieldY.float32 and
       mousePos.y <= (joinNickFieldY + 36).float32:
      pvpWin.editingNickname = true
      pvpWin.editingIP = false
      pvpWin.editingPort = false
      # Set cursor position based on click location (text is drawn at fieldY + 8, remaining height = 28)
      let cursorPos = getTextCursorPos(pvpWin.inputNickname, ipFieldX, joinNickFieldY + 8, 20, 28, mousePos.x, mousePos.y)
      if cursorPos >= 0:
        pvpWin.cursorPos = cursorPos
        pvpWin.mouseDownPos = mousePos
        pvpWin.isDragging = true
        pvpWin.selectionStart = cursorPos
        pvpWin.selectionEnd = cursorPos

    # IP field (contentY + 172)
    let ipFieldY = contentY + 172
    if mousePos.x >= ipFieldX.float32 and
       mousePos.x <= (ipFieldX + ipFieldWidth).float32 and
       mousePos.y >= ipFieldY.float32 and
       mousePos.y <= (ipFieldY + ipFieldHeight).float32:
      pvpWin.editingIP = true
      pvpWin.editingPort = false
      pvpWin.editingNickname = false
      # Set cursor position based on click location (text is drawn at fieldY + 10, remaining height = 30)
      let cursorPos = getTextCursorPos(pvpWin.inputIP, ipFieldX, ipFieldY + 10, 20, 30, mousePos.x, mousePos.y)
      if cursorPos >= 0:
        pvpWin.cursorPos = cursorPos
        pvpWin.mouseDownPos = mousePos
        pvpWin.isDragging = true
        pvpWin.selectionStart = cursorPos
        pvpWin.selectionEnd = cursorPos

    # Port field (contentY + 250)
    let portFieldY = contentY + 250
    if mousePos.x >= ipFieldX.float32 and
       mousePos.x <= (ipFieldX + ipFieldWidth).float32 and
       mousePos.y >= portFieldY.float32 and
       mousePos.y <= (portFieldY + ipFieldHeight).float32:
      pvpWin.editingIP = false
      pvpWin.editingPort = true
      pvpWin.editingNickname = false
      # Set cursor position based on click location (text is drawn at fieldY + 10, remaining height = 30)
      let cursorPos = getTextCursorPos(pvpWin.inputPort, ipFieldX, portFieldY + 10, 20, 30, mousePos.x, mousePos.y)
      if cursorPos >= 0:
        pvpWin.cursorPos = cursorPos
        pvpWin.mouseDownPos = mousePos
        pvpWin.isDragging = true
        pvpWin.selectionStart = cursorPos
        pvpWin.selectionEnd = cursorPos

    let connectButtonX = contentX + (contentWidth - 200) div 2
    let connectButtonY = contentY + 308
    if mousePos.x >= connectButtonX.float32 and
       mousePos.x <= (connectButtonX + 200).float32 and
       mousePos.y >= connectButtonY.float32 and
       mousePos.y <= (connectButtonY + 50).float32:
      return 4  # Connect

    # Check for back button
    let backButtonY = connectButtonY + 62
    if mousePos.x >= connectButtonX.float32 and
       mousePos.x <= (connectButtonX + 200).float32 and
       mousePos.y >= backButtonY.float32 and
       mousePos.y <= (backButtonY + 50).float32:
      return 3  # Back
  
  of plsConnected:
    if pvpWin.isHost:
      # Check for team badge clicks (if teams enabled)
      if pvpWin.teamsEnabled:
        let listY = contentY + 110
        # Host team badge (row Y = listY + 35, badge X = contentX + 260, w=58, h=20)
        let hostBadgeX = contentX + 260
        let hostBadgeY = listY + 35
        if mousePos.x >= hostBadgeX.float32 and
           mousePos.x <= (hostBadgeX + 58).float32 and
           mousePos.y >= hostBadgeY.float32 and
           mousePos.y <= (hostBadgeY + 20).float32:
          while pvpWin.playerTeamAssignments.len <= 0:
            pvpWin.playerTeamAssignments.add(1)  # Start at ptRed (1), not ptNone (0)
          # Cycle to next team (1-4 range, skipping 0 which is ptNone)
          let currentTeam = pvpWin.playerTeamAssignments[0]
          pvpWin.playerTeamAssignments[0] = ((currentTeam - 1 + 1) mod pvpWin.numTeams) + 1
          return 0
        # Client team badges
        var yOffset = 35
        for i, client in pvpWin.networkManager.clients:
          yOffset += 25
          let pBadgeX = contentX + 260
          let pBadgeY = listY + yOffset
          if mousePos.x >= pBadgeX.float32 and
             mousePos.x <= (pBadgeX + 58).float32 and
             mousePos.y >= pBadgeY.float32 and
             mousePos.y <= (pBadgeY + 20).float32:
            let playerIndex = client.playerIndex  # playerIndex is already correct (host=0, first client=1, etc.)
            while pvpWin.playerTeamAssignments.len <= playerIndex:
              pvpWin.playerTeamAssignments.add(1)  # Start at ptRed (1), not ptNone (0)
            # Cycle to next team (1-4 range, skipping 0 which is ptNone)
            let currentTeam = pvpWin.playerTeamAssignments[playerIndex]
            pvpWin.playerTeamAssignments[playerIndex] = ((currentTeam - 1 + 1) mod pvpWin.numTeams) + 1
            return 0

      # Check for START GAME button
      let startButtonX = contentX + (contentWidth - 250) div 2
      let startButtonY = contentY + contentHeight - 120
      let playerCount = pvpWin.networkManager.getConnectedPlayerCount()
      
      if playerCount >= 2 and
         mousePos.x >= startButtonX.float32 and
         mousePos.x <= (startButtonX + 250).float32 and
         mousePos.y >= startButtonY.float32 and
         mousePos.y <= (startButtonY + 60).float32:
        pvpWin.readyToStart = true
        return 5  # Start game
      
      # Check for CANCEL button
      let cancelButtonY = startButtonY + 70
      if mousePos.x >= startButtonX.float32 and
         mousePos.x <= (startButtonX + 250).float32 and
         mousePos.y >= cancelButtonY.float32 and
         mousePos.y <= (cancelButtonY + 50).float32:
        return 3  # Cancel
  
  of plsError:
    # Check for back button
    let backButtonX = contentX + (contentWidth - 200) div 2
    let backButtonY = contentY + contentHeight - 100
    if mousePos.x >= backButtonX.float32 and
       mousePos.x <= (backButtonX + 200).float32 and
       mousePos.y >= backButtonY.float32 and
       mousePos.y <= (backButtonY + 50).float32:
      return 3  # Back
  
  else:
    discard
  
  return 0
