## PvP Lobby and Connection UI
## Handles hosting and joining PvP games

import raylib, network, network_types, asyncdispatch, strutils

type
  PvPLobbyState* = enum
    plsMainMenu      # Choose host or join
    plsHosting       # Waiting for opponent
    plsJoining       # Entering IP and connecting
    plsConnecting    # Attempting connection
    plsConnected     # Connected, waiting for game start
    plsError         # Connection error
  
  PvPLobby* = ref object
    state*: PvPLobbyState
    networkManager*: NetworkManager
    isHost*: bool
    hostIP*: string
    hostPort*: int
    inputIP*: string
    inputPort*: string
    errorMessage*: string
    connectionTimeout*: float32
    cursorBlink*: float32
    editingIP*: bool
    editingPort*: bool

const
  DEFAULT_PORT = 7777
  CONNECTION_TIMEOUT = 10.0

proc newPvPLobby*(): PvPLobby =
  result = PvPLobby(
    state: plsMainMenu,
    networkManager: newNetworkManager(),
    isHost: false,
    hostIP: "",
    hostPort: DEFAULT_PORT,
    inputIP: "127.0.0.1",
    inputPort: $DEFAULT_PORT,
    errorMessage: "",
    connectionTimeout: 0,
    cursorBlink: 0,
    editingIP: true,
    editingPort: false
  )

proc getLocalIP*(): string =
  ## Get local IP address (simple implementation)
  ## For production, you'd want to detect the actual network interface IP
  result = "127.0.0.1"  # Localhost for testing
  # TODO: Implement actual IP detection using system commands or network libs

proc startHosting*(lobby: PvPLobby) =
  ## Start hosting a game
  lobby.isHost = true
  lobby.state = plsHosting
  lobby.hostIP = getLocalIP()
  lobby.hostPort = DEFAULT_PORT
  
  try:
    lobby.networkManager.initHost(lobby.hostPort)
    echo "[LOBBY] Hosting on ", lobby.hostIP, ":", lobby.hostPort
  except:
    lobby.state = plsError
    lobby.errorMessage = "Failed to start host: " & getCurrentExceptionMsg()

proc connectToGame*(lobby: PvPLobby, ip: string, port: int,
                   skinType: int = 0, bulletSkinType: int = 0,
                   shapeType: int = 0, particleSkinType: int = 0) =
  ## Connect to a hosted game with cosmetics
  lobby.isHost = false
  lobby.state = plsConnecting
  lobby.connectionTimeout = CONNECTION_TIMEOUT
  
  try:
    lobby.networkManager.initClient()
    lobby.networkManager.connectToHost(ip, port, skinType, bulletSkinType, shapeType, particleSkinType)
    echo "[LOBBY] Connecting to ", ip, ":", port
  except:
    lobby.state = plsError
    lobby.errorMessage = "Failed to connect: " & getCurrentExceptionMsg()

proc updateLobby*(lobby: PvPLobby, dt: float32): bool =
  ## Update lobby state. Returns true if game should start
  lobby.cursorBlink += dt
  
  case lobby.state
  of plsHosting:
    # Check for incoming connection
    let events = lobby.networkManager.pollEvents()
    for event in events:
      if event.kind == neConnect:
        lobby.state = plsConnected
        return true
  
  of plsConnecting:
    lobby.connectionTimeout -= dt
    if lobby.connectionTimeout <= 0:
      lobby.state = plsError
      lobby.errorMessage = "Connection timeout"
      return false
    
    # Check if connected
    let events = lobby.networkManager.pollEvents()
    for event in events:
      if event.kind == neConnect:
        lobby.state = plsConnected
        return true
      elif event.kind == neDisconnect:
        lobby.state = plsError
        lobby.errorMessage = "Connection refused"
  
  of plsConnected:
    # Wait for game start signal
    let events = lobby.networkManager.pollEvents()
    for event in events:
      if event.kind == neReceive and event.packet.packetType == ptGameStart:
        return true
  
  else:
    discard
  
  return false

proc handleLobbyInput*(lobby: PvPLobby) =
  ## Handle input in lobby
  case lobby.state
  of plsMainMenu:
    discard
  
  of plsJoining:
    # Handle text input for IP and port
    let key = getCharPressed()
    
    if key > 0:
      let ch = char(key)
      
      if lobby.editingIP:
        if ch in {'0'..'9', '.'}:
          lobby.inputIP &= ch
      elif lobby.editingPort:
        if ch in {'0'..'9'}:
          lobby.inputPort &= ch
    
    # Handle backspace
    if isKeyPressed(Backspace):
      if lobby.editingIP and lobby.inputIP.len > 0:
        lobby.inputIP = lobby.inputIP[0..^2]
      elif lobby.editingPort and lobby.inputPort.len > 0:
        lobby.inputPort = lobby.inputPort[0..^2]
    
    # Switch between fields with Tab
    if isKeyPressed(Tab):
      lobby.editingIP = not lobby.editingIP
      lobby.editingPort = not lobby.editingPort
  
  else:
    discard

proc drawLobby*(lobby: PvPLobby, screenWidth, screenHeight: int32) =
  ## Draw lobby UI
  clearBackground(Color(r: 20, g: 20, b: 30, a: 255))
  
  case lobby.state
  of plsMainMenu:
    # Main menu - choose host or join
    let titleText = "1v1 PVP MODE"
    let titleWidth = measureText(titleText, 60)
    drawText(titleText, screenWidth div 2 - titleWidth div 2, 100, 60, Yellow)
    
    # Host button
    let hostButtonX = screenWidth div 2 - 150
    let hostButtonY = screenHeight div 2 - 50
    let hostButtonWidth = 300
    let hostButtonHeight = 50
    
    let mousePos = getMousePosition()
    let hostHovered = mousePos.x >= hostButtonX.float32 and 
                      mousePos.x <= (hostButtonX + hostButtonWidth).float32 and
                      mousePos.y >= hostButtonY.float32 and
                      mousePos.y <= (hostButtonY + hostButtonHeight).float32
    
    drawRectangle(hostButtonX.int32, hostButtonY.int32, hostButtonWidth.int32, hostButtonHeight.int32,
                 if hostHovered: Color(r: 100, g: 150, b: 255, a: 255) 
                 else: Color(r: 70, g: 100, b: 200, a: 255))
    
    let hostText = "HOST GAME"
    let hostTextWidth = measureText(hostText, 30)
    drawText(hostText, screenWidth div 2 - hostTextWidth div 2, hostButtonY + 10, 30, White)
    
    # Join button
    let joinButtonY = hostButtonY + 80
    let joinHovered = mousePos.x >= hostButtonX.float32 and
                      mousePos.x <= (hostButtonX + hostButtonWidth).float32 and
                      mousePos.y >= joinButtonY.float32 and
                      mousePos.y <= (joinButtonY + hostButtonHeight).float32
    
    drawRectangle(hostButtonX.int32, joinButtonY.int32, hostButtonWidth.int32, hostButtonHeight.int32,
                 if joinHovered: Color(r: 100, g: 255, b: 150, a: 255)
                 else: Color(r: 70, g: 200, b: 100, a: 255))
    
    let joinText = "JOIN GAME"
    let joinTextWidth = measureText(joinText, 30)
    drawText(joinText, screenWidth div 2 - joinTextWidth div 2, joinButtonY + 10, 30, White)
    
    # Back button
    let backButtonY = joinButtonY + 80
    let backHovered = mousePos.x >= hostButtonX.float32 and
                      mousePos.x <= (hostButtonX + hostButtonWidth).float32 and
                      mousePos.y >= backButtonY.float32 and
                      mousePos.y <= (backButtonY + hostButtonHeight).float32
    
    drawRectangle(hostButtonX.int32, backButtonY.int32, hostButtonWidth.int32, hostButtonHeight.int32,
                 if backHovered: Color(r: 200, g: 100, b: 100, a: 255)
                 else: Color(r: 150, g: 70, b: 70, a: 255))
    
    let backText = "BACK TO MENU"
    let backTextWidth = measureText(backText, 30)
    drawText(backText, screenWidth div 2 - backTextWidth div 2, backButtonY + 10, 30, White)
  
  of plsHosting:
    # Waiting for opponent
    let titleText = "WAITING FOR OPPONENT..."
    let titleWidth = measureText(titleText, 40)
    drawText(titleText, screenWidth div 2 - titleWidth div 2, 150, 40, Yellow)
    
    # Show IP and port
    let ipText = "Your IP: " & lobby.hostIP
    let ipWidth = measureText(ipText, 30)
    drawText(ipText, screenWidth div 2 - ipWidth div 2, 250, 30, White)
    
    let portText = "Port: " & $lobby.hostPort
    let portWidth = measureText(portText, 30)
    drawText(portText, screenWidth div 2 - portWidth div 2, 290, 30, White)
    
    let instructionText = "Share this IP with your opponent"
    let instructionWidth = measureText(instructionText, 20)
    drawText(instructionText, screenWidth div 2 - instructionWidth div 2, 350, 20, 
             Color(r: 200, g: 200, b: 200, a: 255))
    
    # Animated waiting dots
    let dots = ".".repeat(((lobby.cursorBlink * 2).int mod 4))
    let dotsText = "Waiting" & dots
    let dotsWidth = measureText(dotsText, 25)
    drawText(dotsText, screenWidth div 2 - dotsWidth div 2, 420, 25, Green)
    
    # Cancel button
    let cancelButtonX = screenWidth div 2 - 100
    let cancelButtonY = screenHeight - 150
    drawRectangle(cancelButtonX.int32, cancelButtonY.int32, 200, 50, Color(r: 150, g: 70, b: 70, a: 255))
    let cancelText = "CANCEL"
    let cancelTextWidth = measureText(cancelText, 25)
    drawText(cancelText, screenWidth div 2 - cancelTextWidth div 2, cancelButtonY + 12, 25, White)
  
  of plsJoining:
    # Enter IP and port
    let titleText = "JOIN GAME"
    let titleWidth = measureText(titleText, 40)
    drawText(titleText, screenWidth div 2 - titleWidth div 2, 150, 40, Yellow)
    
    # IP input field
    let ipLabelText = "Host IP:"
    drawText(ipLabelText, screenWidth div 2 - 250, 250, 25, White)
    
    let ipFieldX = screenWidth div 2 - 150
    let ipFieldY = 280
    let ipFieldWidth = 300
    let ipFieldHeight = 40
    
    drawRectangle(ipFieldX.int32, ipFieldY.int32, ipFieldWidth.int32, ipFieldHeight.int32,
                 if lobby.editingIP: Color(r: 60, g: 60, b: 80, a: 255)
                 else: Color(r: 40, g: 40, b: 50, a: 255))
    drawRectangleLines(
      Rectangle(x: ipFieldX.float32, y: ipFieldY.float32, 
               width: ipFieldWidth.float32, height: ipFieldHeight.float32),
      2, if lobby.editingIP: Yellow else: Gray)
    
    let ipDisplayText = lobby.inputIP
    drawText(ipDisplayText, (ipFieldX + 10).int32, (ipFieldY + 10).int32, 20, White)
    
    # Cursor blink
    if lobby.editingIP and (lobby.cursorBlink.int mod 2) == 0:
      let cursorX = ipFieldX + 10 + measureText(lobby.inputIP, 20)
      drawLine(Vector2(x: cursorX.float32, y: (ipFieldY + 10).float32),
              Vector2(x: cursorX.float32, y: (ipFieldY + 30).float32), 2, White)
    
    # Port input field
    let portLabelText = "Port:"
    drawText(portLabelText, screenWidth div 2 - 250, 350, 25, White)
    
    let portFieldY = 380
    drawRectangle(ipFieldX.int32, portFieldY.int32, ipFieldWidth.int32, ipFieldHeight.int32,
                 if lobby.editingPort: Color(r: 60, g: 60, b: 80, a: 255)
                 else: Color(r: 40, g: 40, b: 50, a: 255))
    drawRectangleLines(
      Rectangle(x: ipFieldX.float32, y: portFieldY.float32,
               width: ipFieldWidth.float32, height: ipFieldHeight.float32),
      2, if lobby.editingPort: Yellow else: Gray)
    
    drawText(lobby.inputPort, (ipFieldX + 10).int32, (portFieldY + 10).int32, 20, White)
    
    if lobby.editingPort and (lobby.cursorBlink.int mod 2) == 0:
      let cursorX = ipFieldX + 10 + measureText(lobby.inputPort, 20)
      drawLine(Vector2(x: cursorX.float32, y: (portFieldY + 10).float32),
              Vector2(x: cursorX.float32, y: (portFieldY + 30).float32), 2, White)
    
    # Connect button
    let connectButtonX = screenWidth div 2 - 100
    let connectButtonY = 480
    drawRectangle(connectButtonX.int32, connectButtonY.int32, 200, 50, 
                 Color(r: 70, g: 200, b: 100, a: 255))
    let connectText = "CONNECT"
    let connectTextWidth = measureText(connectText, 25)
    drawText(connectText, (screenWidth div 2 - connectTextWidth div 2).int32, 
            (connectButtonY + 12).int32, 25, White)
    
    # Back button
    let backButtonY = connectButtonY + 70
    drawRectangle(connectButtonX.int32, backButtonY.int32, 200, 50,
                 Color(r: 150, g: 70, b: 70, a: 255))
    let backText = "BACK"
    let backTextWidth = measureText(backText, 25)
    drawText(backText, (screenWidth div 2 - backTextWidth div 2).int32,
            (backButtonY + 12).int32, 25, White)
  
  of plsConnecting:
    # Connecting animation
    let titleText = "CONNECTING..."
    let titleWidth = measureText(titleText, 40)
    drawText(titleText, screenWidth div 2 - titleWidth div 2, screenHeight div 2 - 50, 
            40, Yellow)
    
    let dots = ".".repeat(((lobby.cursorBlink * 2).int mod 4))
    let statusText = "Please wait" & dots
    let statusWidth = measureText(statusText, 25)
    drawText(statusText, screenWidth div 2 - statusWidth div 2, 
            screenHeight div 2 + 20, 25, White)
    
    let timeoutText = "Timeout in " & $lobby.connectionTimeout.int & "s"
    let timeoutWidth = measureText(timeoutText, 20)
    drawText(timeoutText, screenWidth div 2 - timeoutWidth div 2,
            screenHeight div 2 + 60, 20, Gray)
  
  of plsConnected:
    # Connected, waiting for game start
    let titleText = "CONNECTED!"
    let titleWidth = measureText(titleText, 50)
    drawText(titleText, screenWidth div 2 - titleWidth div 2, 
            screenHeight div 2 - 50, 50, Green)
    
    let statusText = "Waiting for host to start game..."
    let statusWidth = measureText(statusText, 25)
    drawText(statusText, screenWidth div 2 - statusWidth div 2,
            screenHeight div 2 + 30, 25, White)
  
  of plsError:
    # Error message
    let titleText = "CONNECTION ERROR"
    let titleWidth = measureText(titleText, 40)
    drawText(titleText, screenWidth div 2 - titleWidth div 2, 150, 40, Red)
    
    let errorWidth = measureText(lobby.errorMessage, 25)
    drawText(lobby.errorMessage, screenWidth div 2 - errorWidth div 2, 250, 25, White)
    
    # Back button
    let backButtonX = screenWidth div 2 - 100
    let backButtonY = screenHeight - 200
    drawRectangle(backButtonX, backButtonY, 200, 50,
                 Color(r: 150, g: 70, b: 70, a: 255))
    let backText = "BACK TO MENU"
    let backTextWidth = measureText(backText, 25)
    drawText(backText, (screenWidth div 2 - backTextWidth div 2).int32,
            (backButtonY + 12).int32, 25, White)

proc handleLobbyClick*(lobby: PvPLobby, screenWidth, screenHeight: int32): int =
  ## Handle mouse clicks in lobby. Returns:
  ## 0 = no action, 1 = host, 2 = join, 3 = back, 4 = connect, 5 = cancel
  if not isMouseButtonPressed(Left):
    return 0
  
  let mousePos = getMousePosition()
  
  case lobby.state
  of plsMainMenu:
    # Check host button
    let hostButtonX = screenWidth div 2 - 150
    let hostButtonY = screenHeight div 2 - 50
    let hostButtonWidth = 300
    let hostButtonHeight = 50
    
    if mousePos.x >= hostButtonX.float32 and
       mousePos.x <= (hostButtonX + hostButtonWidth).float32 and
       mousePos.y >= hostButtonY.float32 and
       mousePos.y <= (hostButtonY + hostButtonHeight).float32:
      return 1  # Host
    
    # Check join button
    let joinButtonY = hostButtonY + 80
    if mousePos.x >= hostButtonX.float32 and
       mousePos.x <= (hostButtonX + hostButtonWidth).float32 and
       mousePos.y >= joinButtonY.float32 and
       mousePos.y <= (joinButtonY + hostButtonHeight).float32:
      return 2  # Join
    
    # Check back button
    let backButtonY = joinButtonY + 80
    if mousePos.x >= hostButtonX.float32 and
       mousePos.x <= (hostButtonX + hostButtonWidth).float32 and
       mousePos.y >= backButtonY.float32 and
       mousePos.y <= (backButtonY + hostButtonHeight).float32:
      return 3  # Back
  
  of plsHosting:
    # Check cancel button
    let cancelButtonX = screenWidth div 2 - 100
    let cancelButtonY = screenHeight - 150
    if mousePos.x >= cancelButtonX.float32 and
       mousePos.x <= (cancelButtonX + 200).float32 and
       mousePos.y >= cancelButtonY.float32 and
       mousePos.y <= (cancelButtonY + 50).float32:
      return 5  # Cancel
  
  of plsJoining:
    # Check connect button
    let connectButtonX = screenWidth div 2 - 100
    let connectButtonY = 480
    if mousePos.x >= connectButtonX.float32 and
       mousePos.x <= (connectButtonX + 200).float32 and
       mousePos.y >= connectButtonY.float32 and
       mousePos.y <= (connectButtonY + 50).float32:
      return 4  # Connect
    
    # Check back button
    let backButtonY = connectButtonY + 70
    if mousePos.x >= connectButtonX.float32 and
       mousePos.x <= (connectButtonX + 200).float32 and
       mousePos.y >= backButtonY.float32 and
       mousePos.y <= (backButtonY + 50).float32:
      return 3  # Back
    
    # Check if clicking IP field
    let ipFieldX = screenWidth div 2 - 150
    let ipFieldY = 280
    let ipFieldWidth = 300
    let ipFieldHeight = 40
    if mousePos.x >= ipFieldX.float32 and
       mousePos.x <= (ipFieldX + ipFieldWidth).float32 and
       mousePos.y >= ipFieldY.float32 and
       mousePos.y <= (ipFieldY + ipFieldHeight).float32:
      lobby.editingIP = true
      lobby.editingPort = false
    
    # Check if clicking port field
    let portFieldY = 380
    if mousePos.x >= ipFieldX.float32 and
       mousePos.x <= (ipFieldX + ipFieldWidth).float32 and
       mousePos.y >= portFieldY.float32 and
       mousePos.y <= (portFieldY + ipFieldHeight).float32:
      lobby.editingIP = false
      lobby.editingPort = true
  
  of plsError:
    # Check back button
    let backButtonX = screenWidth div 2 - 100
    let backButtonY = screenHeight - 200
    if mousePos.x >= backButtonX.float32 and
       mousePos.x <= (backButtonX + 200).float32 and
       mousePos.y >= backButtonY.float32 and
       mousePos.y <= (backButtonY + 50).float32:
      return 3  # Back
  
  else:
    discard
  
  return 0
