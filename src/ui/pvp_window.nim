## PvP Lobby Window
## Network lobby interface as an OS-style window

import raylib, os_window, ../network/network, strutils, osproc

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
  
  PvPLobbyState* = enum
    plsMainMenu      # Choose host or join
    plsHosting       # Waiting for opponent
    plsJoining       # Entering IP and connecting
    plsConnecting    # Attempting connection
    plsConnected     # Connected, waiting for game start
    plsError         # Connection error

const
  DEFAULT_PORT* = 7777
  CONNECTION_TIMEOUT = 10.0

proc newPvPWindow*(screenWidth, screenHeight: int): PvPWindow =
  let windowWidth = 600
  let windowHeight = 500
  let windowX = (screenWidth - windowWidth) div 2
  let windowY = (screenHeight - windowHeight) div 2
  
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
    remoteParticleSkinType: 0
  )

proc getLocalIP*(): string =
  ## Get local IP address by detecting network interface
  when defined(windows):
    # Windows: Use ipconfig and parse for IPv4 address
    try:
      let (output, exitCode) = execCmdEx("ipconfig")
      if exitCode == 0:
        # Parse for first non-loopback IPv4 address
        for line in output.splitLines():
          if "IPv4" in line and ":" in line:
            let parts = line.split(":")
            if parts.len > 1:
              let ip = parts[1].strip()
              # Skip loopback and validate IPv4 format
              if ip != "127.0.0.1" and ip.len > 0:
                let ipParts = ip.split(".")
                if ipParts.len == 4:
                  return ip
    except:
      discard
  elif defined(linux):
    # Linux: Try hostname -I first
    try:
      let (output, exitCode) = execCmdEx("hostname -I")
      if exitCode == 0:
        let ips = output.strip().split(" ")
        if ips.len > 0 and ips[0] != "127.0.0.1":
          return ips[0]
    except:
      discard
  elif defined(macosx):
    # macOS: Use ifconfig
    try:
      let (output, exitCode) = execCmdEx("ifconfig")
      if exitCode == 0:
        for line in output.splitLines():
          if "inet " in line and "127.0.0.1" notin line:
            let parts = line.strip().split(" ")
            for i, part in parts:
              if part == "inet" and i + 1 < parts.len:
                let ip = parts[i + 1]
                if not ip.startsWith("169.254."):  # Skip link-local
                  return ip
    except:
      discard
  
  # Fallback to localhost
  result = "127.0.0.1"

proc startHosting*(pvpWin: PvPWindow) =
  pvpWin.isHost = true
  pvpWin.state = plsHosting
  pvpWin.hostIP = getLocalIP()
  pvpWin.hostPort = DEFAULT_PORT
  pvpWin.readyToStart = false
  
  try:
    pvpWin.networkManager.initHost(pvpWin.hostPort)
    echo "[LOBBY] Hosting on ", pvpWin.hostIP, ":", pvpWin.hostPort
  except:
    pvpWin.state = plsError
    pvpWin.errorMessage = "Failed to start host: " & getCurrentExceptionMsg()

proc connectToGame*(pvpWin: PvPWindow, ip: string, port: int,
                   skinType: int = 0, bulletSkinType: int = 0,
                   shapeType: int = 0, particleSkinType: int = 0) =
  pvpWin.isHost = false
  pvpWin.state = plsConnecting
  pvpWin.connectionTimeout = CONNECTION_TIMEOUT
  pvpWin.readyToStart = false
  
  try:
    pvpWin.networkManager.initClient()
    pvpWin.networkManager.connectToHost(ip, port, skinType, bulletSkinType, shapeType, particleSkinType)
    echo "[LOBBY] Connecting to ", ip, ":", port
  except:
    pvpWin.state = plsError
    pvpWin.errorMessage = "Failed to connect: " & getCurrentExceptionMsg()

proc updatePvPWindow*(pvpWin: PvPWindow, dt: float32, getCosmetics: proc(): tuple[skinType, bulletSkinType, shapeType, particleSkinType: int] = nil) =
  pvpWin.cursorBlink += dt
  
  case pvpWin.state
  of plsHosting:
    let events = pvpWin.networkManager.pollEvents(getCosmetics)
    for event in events:
      if event.kind == neConnect:
        pvpWin.state = plsConnected
        pvpWin.readyToStart = true
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
        pvpWin.readyToStart = true
        # Store remote player's cosmetics from the connection event
        pvpWin.remoteSkinType = event.remoteSkinType
        pvpWin.remoteBulletSkinType = event.remoteBulletSkinType
        pvpWin.remoteShapeType = event.remoteShapeType
        pvpWin.remoteParticleSkinType = event.remoteParticleSkinType
      elif event.kind == neDisconnect:
        pvpWin.state = plsError
        pvpWin.errorMessage = "Connection refused"
  
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

proc handlePvPWindowInput*(pvpWin: PvPWindow) =
  if not pvpWin.window.visible or pvpWin.window.minimized:
    return
  
  if pvpWin.state != plsJoining:
    return
  
  let key = getCharPressed()
  
  if key > 0:
    let ch = char(key)
    
    if pvpWin.editingIP:
      if ch in {'0'..'9', '.'}:
        pvpWin.inputIP &= ch
    elif pvpWin.editingPort:
      if ch in {'0'..'9'}:
        pvpWin.inputPort &= ch
  
  if isKeyPressed(Backspace):
    if pvpWin.editingIP and pvpWin.inputIP.len > 0:
      pvpWin.inputIP = pvpWin.inputIP[0..^2]
    elif pvpWin.editingPort and pvpWin.inputPort.len > 0:
      pvpWin.inputPort = pvpWin.inputPort[0..^2]
  
  if isKeyPressed(Tab):
    pvpWin.editingIP = not pvpWin.editingIP
    pvpWin.editingPort = not pvpWin.editingPort

proc drawPvPWindowContent*(pvpWin: PvPWindow, contentX, contentY, contentWidth, contentHeight: int) =
  case pvpWin.state
  of plsMainMenu:
    let titleText = "1v1 PVP MODE"
    let titleWidth = measureText(titleText, 40)
    drawText(titleText, int32(contentX + (contentWidth - titleWidth) div 2), int32(contentY + 30), int32(40), Yellow)
    
    let buttonWidth = 300
    let buttonHeight = 50
    let buttonX = contentX + (contentWidth - buttonWidth) div 2
    let hostButtonY = contentY + 120
    
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
  
  of plsHosting:
    let titleText = "WAITING FOR OPPONENT..."
    let titleWidth = measureText(titleText, 30)
    drawText(titleText, (contentX + (contentWidth - titleWidth) div 2).int32, (contentY + 50).int32, 30, Yellow)
    
    let ipText = "Your IP: " & pvpWin.hostIP
    let ipWidth = measureText(ipText, 24)
    drawText(ipText, (contentX + (contentWidth - ipWidth) div 2).int32, (contentY + 120).int32, 24, White)
    
    let portText = "Port: " & $pvpWin.hostPort
    let portWidth = measureText(portText, 24)
    drawText(portText, (contentX + (contentWidth - portWidth) div 2).int32, (contentY + 155).int32, 24, White)
    
    let instructionText = "Share this IP with your opponent"
    let instructionWidth = measureText(instructionText, 18)
    drawText(instructionText, (contentX + (contentWidth - instructionWidth) div 2).int32, (contentY + 200).int32, 18, 
             Color(r: 200, g: 200, b: 200, a: 255))
    
    let dots = ".".repeat(((pvpWin.cursorBlink * 2).int mod 4))
    let dotsText = "Waiting" & dots
    let dotsWidth = measureText(dotsText, 22)
    drawText(dotsText, (contentX + (contentWidth - dotsWidth) div 2).int32, (contentY + 260).int32, 22, Green)
    
    # Cancel button
    let cancelButtonX = contentX + (contentWidth - 200) div 2
    let cancelButtonY = contentY + contentHeight - 100
    let mousePos = getMousePosition()
    let cancelHovered = mousePos.x >= cancelButtonX.float32 and
                       mousePos.x <= (cancelButtonX + 200).float32 and
                       mousePos.y >= cancelButtonY.float32 and
                       mousePos.y <= (cancelButtonY + 50).float32
    
    drawRectangle(cancelButtonX.int32, cancelButtonY.int32, 200, 50,
                 if cancelHovered: Color(r: 200, g: 100, b: 100, a: 255)
                 else: Color(r: 150, g: 70, b: 70, a: 255))
    let cancelText = "CANCEL"
    let cancelTextWidth = measureText(cancelText, 25)
    drawText(cancelText, (cancelButtonX + (200 - cancelTextWidth) div 2).int32,
            (cancelButtonY + 12).int32, 25, White)
  
  of plsJoining:
    let titleText = "JOIN GAME"
    let titleWidth = measureText(titleText, 30)
    drawText(titleText, (contentX + (contentWidth - titleWidth) div 2).int32, (contentY + 30).int32, 30, Yellow)
    
    let ipLabelText = "Host IP:"
    drawText(ipLabelText, (contentX + 50).int32, (contentY + 100).int32, 22, White)
    
    let ipFieldX = contentX + 50
    let ipFieldY = contentY + 130
    let ipFieldWidth = contentWidth - 100
    let ipFieldHeight = 40
    
    drawRectangle(ipFieldX.int32, ipFieldY.int32, ipFieldWidth.int32, ipFieldHeight.int32,
                 if pvpWin.editingIP: Color(r: 60, g: 60, b: 80, a: 255)
                 else: Color(r: 40, g: 40, b: 50, a: 255))
    drawRectangleLines(
      Rectangle(x: ipFieldX.float32, y: ipFieldY.float32, 
               width: ipFieldWidth.float32, height: ipFieldHeight.float32),
      2, if pvpWin.editingIP: Yellow else: Gray)
    
    drawText(pvpWin.inputIP, (ipFieldX + 10).int32, (ipFieldY + 10).int32, 20, White)
    
    if pvpWin.editingIP and (pvpWin.cursorBlink.int mod 2) == 0:
      let cursorX = ipFieldX + 10 + measureText(pvpWin.inputIP, 20)
      drawLine(Vector2(x: cursorX.float32, y: (ipFieldY + 10).float32),
              Vector2(x: cursorX.float32, y: (ipFieldY + 30).float32), 2, White)
    
    let portLabelText = "Port:"
    drawText(portLabelText, (contentX + 50).int32, (contentY + 190).int32, 22, White)
    
    let portFieldY = contentY + 220
    drawRectangle(ipFieldX.int32, portFieldY.int32, ipFieldWidth.int32, ipFieldHeight.int32,
                 if pvpWin.editingPort: Color(r: 60, g: 60, b: 80, a: 255)
                 else: Color(r: 40, g: 40, b: 50, a: 255))
    drawRectangleLines(
      Rectangle(x: ipFieldX.float32, y: portFieldY.float32,
               width: ipFieldWidth.float32, height: ipFieldHeight.float32),
      2, if pvpWin.editingPort: Yellow else: Gray)
    
    drawText(pvpWin.inputPort, (ipFieldX + 10).int32, (portFieldY + 10).int32, 20, White)
    
    if pvpWin.editingPort and (pvpWin.cursorBlink.int mod 2) == 0:
      let cursorX = ipFieldX + 10 + measureText(pvpWin.inputPort, 20)
      drawLine(Vector2(x: cursorX.float32, y: (portFieldY + 10).float32),
              Vector2(x: cursorX.float32, y: (portFieldY + 30).float32), 2, White)
    
    let connectButtonX = contentX + (contentWidth - 200) div 2
    let connectButtonY = contentY + 310
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
    let backButtonY = connectButtonY + 70
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
    let titleText = "CONNECTED!"
    let titleWidth = measureText(titleText, 40)
    drawText(titleText, (contentX + (contentWidth - titleWidth) div 2).int32, 
            (contentY + contentHeight div 2 - 50).int32, 40, Green)
    
    let statusText = if pvpWin.isHost: "Waiting for game start..." else: "Ready to play!"
    let statusWidth = measureText(statusText, 22)
    drawText(statusText, (contentX + (contentWidth - statusWidth) div 2).int32,
            (contentY + contentHeight div 2 + 20).int32, 22, White)
  
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
  ## Returns: 0 = no action, 1 = host, 2 = join, 3 = back/cancel, 4 = connect
  if not isMouseButtonPressed(Left):
    return 0
  
  let mousePos = getMousePosition()
  
  case pvpWin.state
  of plsMainMenu:
    let buttonWidth = 300
    let buttonHeight = 50
    let buttonX = contentX + (contentWidth - buttonWidth) div 2
    let hostButtonY = contentY + 120
    
    if mousePos.x >= buttonX.float32 and
       mousePos.x <= (buttonX + buttonWidth).float32 and
       mousePos.y >= hostButtonY.float32 and
       mousePos.y <= (hostButtonY + buttonHeight).float32:
      return 1  # Host
    
    let joinButtonY = hostButtonY + 80
    if mousePos.x >= buttonX.float32 and
       mousePos.x <= (buttonX + buttonWidth).float32 and
       mousePos.y >= joinButtonY.float32 and
       mousePos.y <= (joinButtonY + buttonHeight).float32:
      return 2  # Join
  
  of plsHosting:
    # Check for cancel button
    let cancelButtonX = contentX + (contentWidth - 200) div 2
    let cancelButtonY = contentY + contentHeight - 100
    if mousePos.x >= cancelButtonX.float32 and
       mousePos.x <= (cancelButtonX + 200).float32 and
       mousePos.y >= cancelButtonY.float32 and
       mousePos.y <= (cancelButtonY + 50).float32:
      return 3  # Cancel
  
  of plsJoining:
    let ipFieldX = contentX + 50
    let ipFieldY = contentY + 130
    let ipFieldWidth = contentWidth - 100
    let ipFieldHeight = 40
    
    if mousePos.x >= ipFieldX.float32 and
       mousePos.x <= (ipFieldX + ipFieldWidth).float32 and
       mousePos.y >= ipFieldY.float32 and
       mousePos.y <= (ipFieldY + ipFieldHeight).float32:
      pvpWin.editingIP = true
      pvpWin.editingPort = false
    
    let portFieldY = contentY + 220
    if mousePos.x >= ipFieldX.float32 and
       mousePos.x <= (ipFieldX + ipFieldWidth).float32 and
       mousePos.y >= portFieldY.float32 and
       mousePos.y <= (portFieldY + ipFieldHeight).float32:
      pvpWin.editingIP = false
      pvpWin.editingPort = true
    
    let connectButtonX = contentX + (contentWidth - 200) div 2
    let connectButtonY = contentY + 310
    if mousePos.x >= connectButtonX.float32 and
       mousePos.x <= (connectButtonX + 200).float32 and
       mousePos.y >= connectButtonY.float32 and
       mousePos.y <= (connectButtonY + 50).float32:
      return 4  # Connect
    
    # Check for back button
    let backButtonY = connectButtonY + 70
    if mousePos.x >= connectButtonX.float32 and
       mousePos.x <= (connectButtonX + 200).float32 and
       mousePos.y >= backButtonY.float32 and
       mousePos.y <= (backButtonY + 50).float32:
      return 3  # Back
  
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
