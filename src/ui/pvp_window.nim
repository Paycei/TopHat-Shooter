## PvP Lobby Window
## Network lobby interface as an OS-style window

import raylib, os_window, ../network/network, ../network/network_types, strutils, net, math, ../types, ../localization

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
    # Interpolation settings
    interpolationEnabled*: bool  # Whether client-side interpolation is enabled

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
  result = "127.0.0.1"
  try:
    let sock = newSocket(Domain.AF_INET, SockType.SOCK_DGRAM, Protocol.IPPROTO_UDP)
    try:
      sock.connect("8.8.8.8", Port(80))
      let (localIP, _) = sock.getLocalAddr()
      if localIP != "" and localIP != "0.0.0.0":
        result = localIP
    except:
      discard
    sock.close()
  except:
    discard
  return result

proc censorIP*(ip: string): string =
  if ip == "127.0.0.1":
    return ip
  let parts = ip.split(".")
  if parts.len == 4:
    return "***.***.***.***"
  else:
    return ip

proc getTeamForPlayer*(playerIndex: int, numTeams: int): PvPTeam =
  if numTeams == 2:
    return if playerIndex mod 2 == 0: ptRed else: ptBlue
  elif numTeams == 3:
    case playerIndex mod 3
    of 0: return ptRed
    of 1: return ptBlue
    else: return ptGreen
  elif numTeams == 4:
    case playerIndex mod 4
    of 0: return ptRed
    of 1: return ptBlue
    of 2: return ptGreen
    else: return ptYellow
  elif numTeams == 5:
    case playerIndex mod 5
    of 0: return ptRed
    of 1: return ptBlue
    of 2: return ptGreen
    of 3: return ptYellow
    else: return ptOrange
  else:
    case playerIndex mod 6
    of 0: return ptRed
    of 1: return ptBlue
    of 2: return ptGreen
    of 3: return ptYellow
    of 4: return ptOrange
    else: return ptPurple

proc getTeamColor*(team: PvPTeam): Color =
  case team
  of ptRed:    return Color(r: 255, g: 60,  b: 60,  a: 255)
  of ptBlue:   return Color(r: 60,  g: 120, b: 255, a: 255)
  of ptGreen:  return Color(r: 60,  g: 255, b: 120, a: 255)
  of ptYellow: return Color(r: 255, g: 220, b: 60,  a: 255)
  of ptOrange: return Color(r: 255, g: 165, b: 0,   a: 255)
  of ptPurple: return Color(r: 200, g: 100, b: 255, a: 255)
  of ptNone:   return White

proc getTeamName*(team: PvPTeam): string =
  case team
  of ptRed:    return "Red"
  of ptBlue:   return "Blue"
  of ptGreen:  return "Green"
  of ptYellow: return "Yellow"
  of ptOrange: return "Orange"
  of ptPurple: return "Purple"
  of ptNone:   return "None"

proc newPvPWindow*(screenWidth, screenHeight: int): PvPWindow =
  let windowWidth = 600
  let windowHeight = 600
  let windowX = (screenWidth - windowWidth) div 2
  let windowY = (screenHeight - windowHeight) div 2
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
    showIPs: false,
    maxPlayers: 2,
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
    playerTeamAssignments: @[],
    interpolationEnabled: true
  )

proc startHosting*(pvpWin: PvPWindow) =
  pvpWin.isHost = true
  pvpWin.state = plsHostingActive
  pvpWin.hostIP = pvpWin.cachedLocalIP
  pvpWin.hostPort = DEFAULT_PORT
  pvpWin.readyToStart = false
  pvpWin.keepAliveTimer = 0.0
  if pvpWin.teamsEnabled:
    pvpWin.playerTeamAssignments = @[]
    for i in 0..<pvpWin.maxPlayers:
      pvpWin.playerTeamAssignments.add((i mod pvpWin.numTeams) + 1)
  try:
    pvpWin.networkManager.initHost(pvpWin.hostPort, pvpWin.maxPlayers)
    echo "[LOBBY] Hosting on ", pvpWin.hostIP, ":", pvpWin.hostPort, " for ", pvpWin.maxPlayers, " players"
  except:
    pvpWin.state = plsError
    pvpWin.errorMessage = t("pvp_failed_start_host") & getCurrentExceptionMsg()

proc connectToGame*(pvpWin: PvPWindow, ip: string, port: int,
                   skinType: int = 0, bulletSkinType: int = 0,
                   shapeType: int = 0, particleSkinType: int = 0,
                   nickname: string = "Player") =
  pvpWin.isHost = false
  pvpWin.state = plsConnecting
  pvpWin.connectionTimeout = CONNECTION_TIMEOUT
  pvpWin.readyToStart = false
  pvpWin.keepAliveTimer = 0.0
  try:
    pvpWin.networkManager.initClient()
    pvpWin.networkManager.connectToHost(ip, port, skinType, bulletSkinType, shapeType, particleSkinType, nickname)
    echo "[LOBBY] Connecting to ", ip, ":", port, " as \"", nickname, "\""
  except:
    pvpWin.state = plsError
    pvpWin.errorMessage = t("pvp_failed_connect") & getCurrentExceptionMsg()

proc updatePvPWindow*(pvpWin: PvPWindow, dt: float32, getCosmetics: proc(): tuple[skinType, bulletSkinType, shapeType, particleSkinType: int] = nil) =
  pvpWin.cursorBlink += dt
  if pvpWin.state == plsConnected or pvpWin.state == plsHostingActive:
    pvpWin.keepAliveTimer += dt
    if pvpWin.keepAliveTimer >= 1.0:
      pvpWin.keepAliveTimer = 0.0
      pvpWin.networkManager.sendPing(0)
  case pvpWin.state
  of plsHostingActive:
    let events = pvpWin.networkManager.pollEvents(getCosmetics)
    for event in events:
      if event.kind == neConnect:
        pvpWin.state = plsConnected
        pvpWin.remoteSkinType = event.remoteSkinType
        pvpWin.remoteBulletSkinType = event.remoteBulletSkinType
        pvpWin.remoteShapeType = event.remoteShapeType
        pvpWin.remoteParticleSkinType = event.remoteParticleSkinType
        let (localSkin, localBullet, localShape, localParticle) = getCosmetics()
        pvpWin.connectedPlayers = @[
          (index: 0, skinType: localSkin, bulletSkinType: localBullet,
           shapeType: localShape, particleSkinType: localParticle,
           nickname: pvpWin.inputNickname),
          (index: event.connectPlayerIndex, skinType: event.remoteSkinType,
           bulletSkinType: event.remoteBulletSkinType, shapeType: event.remoteShapeType,
           particleSkinType: event.remoteParticleSkinType, nickname: t("pvp_player_num") & $event.connectPlayerIndex)
        ]
  of plsConnecting:
    pvpWin.connectionTimeout -= dt
    if pvpWin.connectionTimeout <= 0:
      pvpWin.state = plsError
      pvpWin.errorMessage = t("pvp_connection_timeout")
      return
    let events = pvpWin.networkManager.pollEvents(getCosmetics)
    for event in events:
      if event.kind == neConnect:
        pvpWin.state = plsConnected
        pvpWin.remoteSkinType = event.remoteSkinType
        pvpWin.remoteBulletSkinType = event.remoteBulletSkinType
        pvpWin.remoteShapeType = event.remoteShapeType
        pvpWin.remoteParticleSkinType = event.remoteParticleSkinType
      elif event.kind == neReceive:
        if event.packet.kind == ptConnectionAccept:
          pvpWin.connectedPlayers = event.packet.connectedPlayers
          pvpWin.assignedPlayerIndex = event.packet.assignedPlayerIndex
      elif event.kind == neDisconnect:
        pvpWin.state = plsError
        pvpWin.errorMessage = event.reason
  of plsConnected:
    let events = pvpWin.networkManager.pollEvents(getCosmetics)
    for event in events:
      if event.kind == neConnect:
        pvpWin.remoteSkinType = event.remoteSkinType
        pvpWin.remoteBulletSkinType = event.remoteBulletSkinType
        pvpWin.remoteShapeType = event.remoteShapeType
        pvpWin.remoteParticleSkinType = event.remoteParticleSkinType
        if pvpWin.isHost:
          pvpWin.connectedPlayers.add((
            index: event.connectPlayerIndex,
            skinType: event.remoteSkinType,
            bulletSkinType: event.remoteBulletSkinType,
            shapeType: event.remoteShapeType,
            particleSkinType: event.remoteParticleSkinType,
            nickname: t("pvp_player_num") & $event.connectPlayerIndex
          ))
      elif event.kind == neReceive:
        if event.packet.kind == ptPlayerListUpdate:
          pvpWin.connectedPlayers = event.packet.updatedPlayers
        elif event.packet.kind == ptGameStart:
          pvpWin.connectedPlayers = event.packet.gameConnectedPlayers
          pvpWin.teamsEnabled = event.packet.teamsEnabled
          pvpWin.playerTeamAssignments = event.packet.teamAssignments
          pvpWin.readyToStart = true
      elif event.kind == neDisconnect:
        if event.disconnectPlayerIndex == 0:
          pvpWin.state = plsError
          pvpWin.errorMessage = t("pvp_host_disconnected")
        else:
          if pvpWin.isHost:
            var newList: seq[ConnectedPlayerInfo] = @[]
            for cp in pvpWin.connectedPlayers:
              if cp.index != event.disconnectPlayerIndex:
                newList.add(cp)
            pvpWin.connectedPlayers = newList
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
  pvpWin.showIPs = false
  pvpWin.editingNickname = false

proc deleteSelection(text: var string, selStart, selEnd: int): int =
  if selStart < 0 or selEnd < 0 or selStart == selEnd:
    return -1
  let startPos = min(selStart, selEnd)
  let endPos = max(selStart, selEnd)
  if startPos >= text.len or endPos > text.len:
    return -1
  text = text[0..<startPos] & text[endPos..^1]
  return startPos

proc drawTextSelection(text: string, fieldX, fieldY, fontSize: int, selStart, selEnd: int) =
  if selStart < 0 or selEnd < 0 or selStart == selEnd:
    return
  let startPos = min(selStart, selEnd)
  let endPos = max(selStart, selEnd)
  if startPos >= text.len or endPos > text.len or startPos < 0:
    return
  let beforeText = if startPos == 0: "" else: text[0..<startPos]
  let selectedText = text[startPos..<endPos]
  let beforeWidth = measureText(beforeText, fontSize.int32)
  let selectedWidth = measureText(selectedText, fontSize.int32)
  let selX = fieldX + 10 + beforeWidth
  let selY = fieldY + 6
  let selHeight = fontSize + 4
  drawRectangle(selX.int32, selY.int32, selectedWidth.int32, selHeight.int32,
               Color(r: 100, g: 150, b: 255, a: 128))

proc getTextCursorPos(text: string, fieldX: int, fieldY: int, fontSize: int, fieldHeight: int, mouseX, mouseY: float32): int =
  if mouseY < (fieldY - 2).float32 or mouseY > (fieldY + fieldHeight + 2).float32:
    return -1
  if mouseX < (fieldX + 5).float32:
    return 0
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

# UI helpers

proc drawSectionDivider(x1, x2, y: int) =
  drawRectangle(x1.int32, y.int32, (x2 - x1).int32, 1,
               Color(r: 0, g: 200, b: 255, a: 100))

proc drawPrimaryButton(bx, by, bw, bh: int, label: string, hovered: bool,
                       baseColor = Color(r: 0, g: 60, b: 80, a: 255),
                       hoverColor = Color(r: 50, g: 50, b: 60, a: 255),
                       fontSize: int32 = 24) =
  let col = if hovered: hoverColor else: baseColor
  drawRectangle(bx.int32, by.int32, bw.int32, bh.int32, col)
  let borderCol = if hovered: Color(r: 0, g: 200, b: 255, a: 255) else: Color(r: 80, g: 80, b: 100, a: 255)
  drawRectangleLines(Rectangle(x: bx.float32, y: by.float32, width: bw.float32, height: bh.float32), 1, borderCol)
  let tw = measureText(label, fontSize)
  drawText(label, (bx + (bw - tw) div 2).int32, (by + (bh - fontSize.int) div 2).int32, fontSize,
           if hovered: Gold else: White)

proc drawDangerButton(bx, by, bw, bh: int, label: string, hovered: bool, fontSize: int32 = 22) =
  let col = if hovered: Color(r: 80, g: 30, b: 30, a: 255) else: Color(r: 50, g: 20, b: 20, a: 255)
  drawRectangle(bx.int32, by.int32, bw.int32, bh.int32, col)
  let borderCol = if hovered: Color(r: 200, g: 80, b: 80, a: 255) else: Color(r: 100, g: 50, b: 50, a: 255)
  drawRectangleLines(Rectangle(x: bx.float32, y: by.float32, width: bw.float32, height: bh.float32), 1, borderCol)
  let tw = measureText(label, fontSize)
  drawText(label, (bx + (bw - tw) div 2).int32, (by + (bh - fontSize.int) div 2).int32, fontSize,
           if hovered: Color(r: 255, g: 100, b: 100, a: 255) else: White)

proc drawCheckbox(cbx, cby, cbSize: int, checked, hovered: bool, label: string, labelFontSize: int32 = 17) =
  let bgColor = if hovered: Color(r: 80, g: 80, b: 100, a: 255) else: Color(r: 60, g: 60, b: 80, a: 255)
  drawRectangle(cbx.int32, cby.int32, cbSize.int32, cbSize.int32, bgColor)
  drawRectangleLines(
    Rectangle(x: cbx.float32, y: cby.float32, width: cbSize.float32, height: cbSize.float32),
    1, Color(r: 120, g: 120, b: 140, a: 255))
  if checked:
    drawLine(Vector2(x: (cbx + 5).float32, y: (cby + cbSize div 2).float32),
             Vector2(x: (cbx + cbSize div 2 - 2).float32, y: (cby + cbSize - 5).float32), 3, Green)
    drawLine(Vector2(x: (cbx + cbSize div 2 - 2).float32, y: (cby + cbSize - 5).float32),
             Vector2(x: (cbx + cbSize - 3).float32, y: (cby + 3).float32), 3, Green)
  drawText(label, (cbx + cbSize + 10).int32, (cby + (cbSize - labelFontSize.int) div 2).int32,
           labelFontSize, Color(r: 220, g: 220, b: 220, a: 255))

proc drawInputField(fx, fy, fw, fh, textOffX, textOffY, fontSize: int, active: bool,
                    text, textBefore: string, cursorBlink: float32,
                    selStart, selEnd: int) =
  let borderCol = if active: Color(r: 0, g: 200, b: 255, a: 255) else: Color(r: 80, g: 80, b: 100, a: 255)
  let bgCol     = if active: Color(r: 0, g: 60, b: 80, a: 255) else: Color(r: 40, g: 40, b: 50, a: 255)
  drawRectangle(fx.int32, fy.int32, fw.int32, fh.int32, bgCol)
  drawRectangleLines(Rectangle(x: fx.float32, y: fy.float32,
    width: fw.float32, height: fh.float32), 2, borderCol)
  if active:
    drawTextSelection(text, fx, fy, fontSize, selStart, selEnd)
  drawText(text, (fx + textOffX).int32, (fy + textOffY).int32, fontSize.int32, White)
  if active and (cursorBlink.int mod 2) == 0:
    let cx = fx + textOffX + measureText(textBefore, fontSize.int32)
    drawLine(Vector2(x: cx.float32, y: (fy + textOffY - 2).float32),
             Vector2(x: cx.float32, y: (fy + fh - textOffY + 2).float32), 2,
             Color(r: 0, g: 200, b: 255, a: 255))

proc handlePvPWindowInput*(pvpWin: PvPWindow) =
  if not pvpWin.window.visible or pvpWin.window.minimized:
    return
  if pvpWin.state != plsJoining and pvpWin.state != plsHostingConfig:
    return

  let contentX = pvpWin.window.x + 10
  let contentY = pvpWin.window.y + 30

  var activeText: ptr string = nil
  var fieldX, fieldY, fontSize, fieldHeight: int

  if pvpWin.editingNickname:
    activeText = addr pvpWin.inputNickname
    fieldX = contentX + 50
    fieldY = contentY + 96 + 8
    fontSize = 20
    fieldHeight = 28
  elif pvpWin.editingIP:
    activeText = addr pvpWin.inputIP
    fieldX = contentX + 50
    fieldY = contentY + 172 + 10
    fontSize = 20
    fieldHeight = 30
  elif pvpWin.editingPort:
    activeText = addr pvpWin.inputPort
    fieldX = contentX + 50
    fieldY = contentY + 250 + 10
    fontSize = 20
    fieldHeight = 30

  if activeText != nil:
    let mousePos = getMousePosition()
    if isMouseButtonPressed(Left):
      let cursorPos = getTextCursorPos(activeText[], fieldX, fieldY, fontSize, fieldHeight, mousePos.x, mousePos.y)
      if cursorPos >= 0:
        pvpWin.mouseDownPos = mousePos
        pvpWin.isDragging = true
        pvpWin.selectionStart = cursorPos
        pvpWin.selectionEnd = cursorPos
    if pvpWin.isDragging and isMouseButtonDown(Left):
      let cursorPos = getTextCursorPos(activeText[], fieldX, fieldY, fontSize, fieldHeight, mousePos.x, mousePos.y)
      if cursorPos >= 0:
        let dragDist = sqrt((mousePos.x - pvpWin.mouseDownPos.x) * (mousePos.x - pvpWin.mouseDownPos.x) +
                           (mousePos.y - pvpWin.mouseDownPos.y) * (mousePos.y - pvpWin.mouseDownPos.y))
        if dragDist > 3.0:
          pvpWin.selectionEnd = cursorPos
    if isMouseButtonReleased(Left):
      pvpWin.isDragging = false
      if pvpWin.selectionStart == pvpWin.selectionEnd:
        pvpWin.cursorPos = pvpWin.selectionStart
        pvpWin.selectionStart = -1
        pvpWin.selectionEnd = -1
      else:
        pvpWin.cursorPos = max(pvpWin.selectionStart, pvpWin.selectionEnd)

  let ctrlPressed = isKeyDown(LeftControl) or isKeyDown(RightControl)
  let cmdPressed = isKeyDown(LeftSuper) or isKeyDown(RightSuper)

  if (ctrlPressed or cmdPressed) and isKeyPressed(C):
    if pvpWin.selectionStart >= 0 and pvpWin.selectionEnd >= 0 and pvpWin.selectionStart != pvpWin.selectionEnd:
      if activeText != nil:
        let startPos = min(pvpWin.selectionStart, pvpWin.selectionEnd)
        let endPos = max(pvpWin.selectionStart, pvpWin.selectionEnd)
        setClipboardText(activeText[][startPos..<endPos])

  if (ctrlPressed or cmdPressed) and isKeyPressed(X):
    if pvpWin.selectionStart >= 0 and pvpWin.selectionEnd >= 0 and pvpWin.selectionStart != pvpWin.selectionEnd:
      if activeText != nil:
        let startPos = min(pvpWin.selectionStart, pvpWin.selectionEnd)
        let endPos = max(pvpWin.selectionStart, pvpWin.selectionEnd)
        setClipboardText(activeText[][startPos..<endPos])
        discard deleteSelection(activeText[], pvpWin.selectionStart, pvpWin.selectionEnd)
        pvpWin.selectionStart = -1
        pvpWin.selectionEnd = -1

  if (ctrlPressed or cmdPressed) and isKeyPressed(V):
    try:
      let clipboardCStr: cstring = getClipboardText()
      if not clipboardCStr.isNil:
        let text = $clipboardCStr
        if pvpWin.selectionStart >= 0 and pvpWin.selectionEnd >= 0 and pvpWin.selectionStart != pvpWin.selectionEnd:
          if activeText != nil:
            let newCursor = deleteSelection(activeText[], pvpWin.selectionStart, pvpWin.selectionEnd)
            if newCursor >= 0: pvpWin.cursorPos = newCursor
            pvpWin.selectionStart = -1
            pvpWin.selectionEnd = -1
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
            if ch in {'0'..'9', '.'}: pasteText &= ch
          if pasteText.len > 0:
            pvpWin.cursorPos = clamp(pvpWin.cursorPos, 0, pvpWin.inputIP.len)
            pvpWin.inputIP = pvpWin.inputIP[0..<pvpWin.cursorPos] & pasteText & pvpWin.inputIP[pvpWin.cursorPos..^1]
            pvpWin.cursorPos += pasteText.len
        elif pvpWin.editingPort:
          var pasteText = ""
          for ch in text:
            if ch in {'0'..'9'}: pasteText &= ch
          if pasteText.len > 0:
            pvpWin.cursorPos = clamp(pvpWin.cursorPos, 0, pvpWin.inputPort.len)
            pvpWin.inputPort = pvpWin.inputPort[0..<pvpWin.cursorPos] & pasteText & pvpWin.inputPort[pvpWin.cursorPos..^1]
            pvpWin.cursorPos += pasteText.len
    except:
      discard

  if (ctrlPressed or cmdPressed) and isKeyPressed(A):
    if activeText != nil:
      pvpWin.selectionStart = 0
      pvpWin.selectionEnd = activeText[].len

  # Character input
  var key = getCharPressed()
  while key > 0:
    if activeText != nil and pvpWin.selectionStart >= 0 and pvpWin.selectionEnd >= 0 and pvpWin.selectionStart != pvpWin.selectionEnd:
      let newCursor = deleteSelection(activeText[], pvpWin.selectionStart, pvpWin.selectionEnd)
      if newCursor >= 0: pvpWin.cursorPos = newCursor
      pvpWin.selectionStart = -1
      pvpWin.selectionEnd = -1
    if pvpWin.editingNickname:
      if pvpWin.inputNickname.len < 16 and key >= 32:
        try:
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
          pvpWin.cursorPos = clamp(pvpWin.cursorPos, 0, pvpWin.inputNickname.len)
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

  # Backspace with repeat
  let backspacePressed = isKeyPressed(Backspace)
  let backspaceDown = isKeyDown(Backspace)
  var shouldDelete = false
  if backspacePressed:
    shouldDelete = true
    pvpWin.lastBackspaceTime = 0.0
  elif backspaceDown:
    pvpWin.lastBackspaceTime += getFrameTime()
    if pvpWin.lastBackspaceTime >= 0.35:
      shouldDelete = true
      pvpWin.lastBackspaceTime = 0.31
  else:
    pvpWin.lastBackspaceTime = 0.0

  if shouldDelete:
    if pvpWin.selectionStart >= 0 and pvpWin.selectionEnd >= 0 and pvpWin.selectionStart != pvpWin.selectionEnd:
      if activeText != nil:
        let newCursor = deleteSelection(activeText[], pvpWin.selectionStart, pvpWin.selectionEnd)
        if newCursor >= 0: pvpWin.cursorPos = newCursor
        pvpWin.selectionStart = -1
        pvpWin.selectionEnd = -1
    else:
      if pvpWin.editingNickname and pvpWin.inputNickname.len > 0 and pvpWin.cursorPos > 0:
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

  if isKeyPressed(Escape):
    pvpWin.selectionStart = -1
    pvpWin.selectionEnd = -1

  if isKeyPressed(Tab):
    pvpWin.selectionStart = -1
    pvpWin.selectionEnd = -1
    if pvpWin.state == plsJoining:
      if pvpWin.editingNickname:
        pvpWin.editingNickname = false
        pvpWin.editingIP = true
        pvpWin.editingPort = false
        pvpWin.cursorPos = pvpWin.inputIP.len
      elif pvpWin.editingIP:
        pvpWin.editingIP = false
        pvpWin.editingPort = true
        pvpWin.editingNickname = false
        pvpWin.cursorPos = pvpWin.inputPort.len
      else:
        pvpWin.editingPort = false
        pvpWin.editingNickname = true
        pvpWin.cursorPos = pvpWin.inputNickname.len
    elif pvpWin.state == plsHostingConfig:
      pvpWin.editingNickname = not pvpWin.editingNickname
      if pvpWin.editingNickname:
        pvpWin.cursorPos = pvpWin.inputNickname.len

proc drawPvPWindowContent*(pvpWin: PvPWindow, contentX, contentY, contentWidth, contentHeight: int) =
  let mousePos = getMousePosition()

  case pvpWin.state
  of plsMainMenu:
    # Cyan accent bar matching other windows
    drawRectangle(contentX.int32, (contentY + 60).int32, contentWidth.int32, 2,
                  Color(r: 0, g: 200, b: 255, a: 100))

    let titleText = t("pvp_title")
    let titleW = measureText(titleText, 42)
    drawText(titleText,
             (contentX + (contentWidth - titleW) div 2).int32,
             (contentY + 10).int32, 42, Color(r: 0, g: 220, b: 255, a: 255))

    let sub = "[ LOCAL NETWORK MULTIPLAYER ]"
    let subW = measureText(sub, 14)
    drawText(sub, (contentX + (contentWidth - subW) div 2).int32,
             (contentY + 68).int32, 14, Color(r: 120, g: 130, b: 140, a: 255))

    let btnW = 300
    let btnH = 50
    let btnX = contentX + (contentWidth - btnW) div 2
    let hostY = contentY + 150

    let hostHov = mousePos.x >= btnX.float32 and mousePos.x <= (btnX + btnW).float32 and
                  mousePos.y >= hostY.float32 and mousePos.y <= (hostY + btnH).float32
    drawPrimaryButton(btnX, hostY, btnW, btnH, t("pvp_host_game"), hostHov, fontSize = 24)
    drawText("[ H ]", (btnX + 10).int32, (hostY + (btnH - 16) div 2).int32, 16,
             Color(r: 100, g: 130, b: 160, a: 200))

    let joinY = hostY + btnH + 16
    let joinHov = mousePos.x >= btnX.float32 and mousePos.x <= (btnX + btnW).float32 and
                  mousePos.y >= joinY.float32 and mousePos.y <= (joinY + btnH).float32
    drawPrimaryButton(btnX, joinY, btnW, btnH, t("pvp_join_game"), joinHov, fontSize = 24)
    drawText("[ J ]", (btnX + 10).int32, (joinY + (btnH - 16) div 2).int32, 16,
             Color(r: 100, g: 130, b: 160, a: 200))

    let info = "Share your Local IP with friends on the same network"
    let infoW = measureText(info, 13)
    drawText(info, (contentX + (contentWidth - infoW) div 2).int32,
             (contentY + contentHeight - 30).int32, 13,
             Color(r: 100, g: 110, b: 120, a: 200))

  of plsHostingConfig:
    drawRectangle(contentX.int32, (contentY + 50).int32, contentWidth.int32, 1,
                  Color(r: 0, g: 200, b: 255, a: 100))
    let titleText = t("pvp_configure_hosting")
    let titleW = measureText(titleText, 24)
    drawText(titleText, (contentX + (contentWidth - titleW) div 2).int32,
             (contentY + 16).int32, 24, Color(r: 0, g: 220, b: 255, a: 255))

    drawText(t("pvp_nickname"), (contentX + 20).int32, (contentY + 62).int32, 18, White)
    let nfX = contentX + 20
    let nfY = contentY + 84
    let nfW = contentWidth - 40
    let nfH = 36
    let nickBefore = if pvpWin.cursorPos > 0 and pvpWin.cursorPos <= pvpWin.inputNickname.len:
                       pvpWin.inputNickname[0..<pvpWin.cursorPos] else: ""
    drawInputField(nfX, nfY, nfW, nfH, 10, 8, 20, pvpWin.editingNickname,
                   pvpWin.inputNickname, nickBefore, pvpWin.cursorBlink,
                   pvpWin.selectionStart, pvpWin.selectionEnd)
    let nickHint = t("pvp_click_edit_tab")
    let nickHintW = measureText(nickHint, 12)
    drawText(nickHint, (contentX + (contentWidth - nickHintW) div 2).int32,
             (nfY + nfH + 4).int32, 12, Color(r: 120, g: 130, b: 140, a: 200))

    drawSectionDivider(contentX + 15, contentX + contentWidth - 15, contentY + 136)

    drawText(t("pvp_max_players"), (contentX + 20).int32, (contentY + 146).int32, 18, White)

    let pcY = contentY + 172
    let spacing = 110
    let centerX = contentX + contentWidth div 2

    let minusX = centerX - spacing
    let minusHov = mousePos.x >= (minusX - 20).float32 and mousePos.x <= (minusX + 20).float32 and
                   mousePos.y >= pcY.float32 and mousePos.y <= (pcY + 36).float32
    let canMinus = pvpWin.maxPlayers > 2
    let minusBg = if canMinus and minusHov: Color(r: 80, g: 80, b: 100, a: 255)
                  elif canMinus: Color(r: 50, g: 50, b: 65, a: 255)
                  else: Color(r: 35, g: 35, b: 45, a: 255)
    drawRectangle((minusX - 18).int32, pcY.int32, 36, 36, minusBg)
    drawRectangleLines(Rectangle(x: (minusX - 18).float32, y: pcY.float32, width: 36, height: 36),
                       1, if canMinus: Color(r: 80, g: 80, b: 100, a: 255) else: Color(r: 50, g: 50, b: 60, a: 255))
    let mW = measureText("-", 26)
    drawText("-", (minusX - mW div 2).int32, (pcY + 5).int32, 26,
             if canMinus: White else: Color(r: 80, g: 80, b: 80, a: 255))

    let cntStr = $pvpWin.maxPlayers
    let cntW = measureText(cntStr, 36)
    drawText(cntStr, (centerX - cntW div 2).int32, (pcY + 1).int32, 36, Color(r: 0, g: 200, b: 255, a: 255))

    let plusX = centerX + spacing
    let plusHov = mousePos.x >= (plusX - 20).float32 and mousePos.x <= (plusX + 20).float32 and
                  mousePos.y >= pcY.float32 and mousePos.y <= (pcY + 36).float32
    let canPlus = pvpWin.maxPlayers < 16
    let plusBg = if canPlus and plusHov: Color(r: 80, g: 80, b: 100, a: 255)
                 elif canPlus: Color(r: 50, g: 50, b: 65, a: 255)
                 else: Color(r: 35, g: 35, b: 45, a: 255)
    drawRectangle((plusX - 18).int32, pcY.int32, 36, 36, plusBg)
    drawRectangleLines(Rectangle(x: (plusX - 18).float32, y: pcY.float32, width: 36, height: 36),
                       1, if canPlus: Color(r: 80, g: 80, b: 100, a: 255) else: Color(r: 50, g: 50, b: 60, a: 255))
    let pW = measureText("+", 26)
    drawText("+", (plusX - pW div 2).int32, (pcY + 5).int32, 26,
             if canPlus: White else: Color(r: 80, g: 80, b: 80, a: 255))

    drawSectionDivider(contentX + 15, contentX + contentWidth - 15, contentY + 222)

    # Checkboxes
    let cbSize = 20
    let cbX = contentX + 20
    var cbY = contentY + 232

    let showIPHov = mousePos.x >= cbX.float32 and mousePos.x <= (cbX + cbSize + 200).float32 and
                    mousePos.y >= cbY.float32 and mousePos.y <= (cbY + cbSize).float32
    drawCheckbox(cbX, cbY, cbSize, pvpWin.showIPs, showIPHov, t("pvp_show_ips"))

    cbY += 28
    let interpHov = mousePos.x >= cbX.float32 and mousePos.x <= (cbX + cbSize + 250).float32 and
                    mousePos.y >= cbY.float32 and mousePos.y <= (cbY + cbSize).float32
    drawCheckbox(cbX, cbY, cbSize, pvpWin.interpolationEnabled, interpHov, t("pvp_enable_interpolation"))

    drawSectionDivider(contentX + 15, contentX + contentWidth - 15, contentY + 292)

    # Teams
    drawText(t("pvp_teams_mode"), (contentX + 20).int32, (contentY + 300).int32, 18, White)
    cbY = contentY + 325
    let teamEnHov = mousePos.x >= cbX.float32 and mousePos.x <= (cbX + cbSize + 230).float32 and
                    mousePos.y >= cbY.float32 and mousePos.y <= (cbY + cbSize).float32
    drawCheckbox(cbX, cbY, cbSize, pvpWin.teamsEnabled, teamEnHov, t("pvp_enable_teams"))

    if pvpWin.teamsEnabled:
      drawText(t("pvp_num_teams"), (contentX + 20).int32, (contentY + 354).int32, 16, LightGray)
      let tbY = contentY + 352
      let tbW = 42
      let tbSp = 56
      let tbStartX = contentX + 210
      for tc in 2..6:
        let tbX = tbStartX + (tc - 2) * tbSp
        let isSel = pvpWin.numTeams == tc
        let tbHov = mousePos.x >= tbX.float32 and mousePos.x <= (tbX + tbW).float32 and
                    mousePos.y >= tbY.float32 and mousePos.y <= (tbY + 30).float32
        let tbBg = if isSel: Color(r: 0, g: 60, b: 80, a: 255)
                   elif tbHov: Color(r: 50, g: 50, b: 60, a: 255)
                   else: Color(r: 40, g: 40, b: 50, a: 255)
        drawRectangle(tbX.int32, tbY.int32, tbW.int32, 30.int32, tbBg)
        drawRectangleLines(Rectangle(x: tbX.float32, y: tbY.float32, width: tbW.float32, height: 30),
                           1, if isSel: Color(r: 0, g: 200, b: 255, a: 255) else: Color(r: 80, g: 80, b: 100, a: 255))
        let tStr = $tc
        let tW = measureText(tStr, 18)
        drawText(tStr, (tbX + (tbW - tW) div 2).int32, (tbY + 6).int32, 18,
                 if isSel: Gold else: White)

    # Buttons
    let startBX = contentX + (contentWidth - 250) div 2
    let startBY = contentY + contentHeight - 118
    let startHov = mousePos.x >= startBX.float32 and mousePos.x <= (startBX + 250).float32 and
                   mousePos.y >= startBY.float32 and mousePos.y <= (startBY + 50).float32
    drawPrimaryButton(startBX, startBY, 250, 50, t("pvp_start_hosting"), startHov, fontSize = 20)

    let cancelBY = startBY + 58
    let cancelHov = mousePos.x >= startBX.float32 and mousePos.x <= (startBX + 250).float32 and
                    mousePos.y >= cancelBY.float32 and mousePos.y <= (cancelBY + 42).float32
    drawDangerButton(startBX, cancelBY, 250, 42, t("general_cancel"), cancelHov, 18)

  of plsHostingActive:
    drawRectangle(contentX.int32, (contentY + 48).int32, contentWidth.int32, 1,
                  Color(r: 0, g: 200, b: 255, a: 100))
    let titleText = t("pvp_hosting_game")
    let titleW = measureText(titleText, 26)
    drawText(titleText, (contentX + (contentWidth - titleW) div 2).int32,
             (contentY + 14).int32, 26, Color(r: 0, g: 220, b: 255, a: 255))

    # Connection info panel
    let panelX = contentX + 20
    let panelY = contentY + 58
    let panelW = contentWidth - 40
    drawRectangle(panelX.int32, panelY.int32, panelW.int32, 56,
                  Color(r: 25, g: 25, b: 35, a: 255))
    drawRectangle(panelX.int32, panelY.int32, panelW.int32, 2,
                  Color(r: 0, g: 200, b: 255, a: 255))
    drawRectangleLines(Rectangle(x: panelX.float32, y: panelY.float32,
      width: panelW.float32, height: 56), 1, Color(r: 60, g: 60, b: 80, a: 255))

    let localIPDisplay = if pvpWin.showIPs: pvpWin.hostIP else: censorIP(pvpWin.hostIP)
    let ipText = t("pvp_local_ip") & " " & localIPDisplay
    let ipW = measureText(ipText, 16)
    drawText(ipText, (panelX + (panelW - ipW) div 2).int32, (panelY + 8).int32, 16, White)

    let portText = t("pvp_port") & " " & $pvpWin.hostPort
    let portW = measureText(portText, 16)
    drawText(portText, (panelX + (panelW - portW) div 2).int32, (panelY + 30).int32, 16,
             Color(r: 0, g: 200, b: 255, a: 200))

    let connectedCount = pvpWin.networkManager.getConnectedPlayerCount()
    let mpText = t("pvp_players_count") & " " & $connectedCount & " / " & $pvpWin.maxPlayers
    let mpW = measureText(mpText, 18)
    drawText(mpText, (contentX + (contentWidth - mpW) div 2).int32, (contentY + 126).int32, 18,
             if connectedCount >= pvpWin.maxPlayers: Color(r: 0, g: 200, b: 255, a: 255)
             else: LightGray)

    drawSectionDivider(contentX + 15, contentX + contentWidth - 15, contentY + 148)

    drawText(t("pvp_connected_players"), (contentX + 20).int32, (contentY + 156).int32, 15, LightGray)
    let hostNick = if pvpWin.inputNickname.len > 0: pvpWin.inputNickname else: "Host"
    drawText("> " & hostNick & t("pvp_you_host"),
             (contentX + 35).int32, (contentY + 176).int32, 15,
             Color(r: 255, g: 200, b: 50, a: 255))
    var yOff = 176
    for i, client in pvpWin.networkManager.clients:
      yOff += 20
      let nick = if client.nickname.len > 0: client.nickname else: t("pvp_player_num") & $(client.playerIndex + 1)
      let label = if pvpWin.teamsEnabled:
        let pIdx = client.playerIndex
        var pTeam = getTeamForPlayer(pIdx, pvpWin.numTeams)
        if pIdx >= 0 and pIdx < pvpWin.playerTeamAssignments.len:
          pTeam = PvPTeam(pvpWin.playerTeamAssignments[pIdx])
        "> " & nick & "  [" & getTeamName(pTeam) & "]"
      else:
        "> " & nick
      drawText(label, (contentX + 35).int32, (contentY + yOff).int32, 15, White)

    let cbSize2 = 18
    let cbText = t("pvp_show_ip")
    let cbTextWidth = measureText(cbText, 15)
    let cbTotalWidth = cbSize2 + 10 + cbTextWidth
    let cbX2 = contentX + (contentWidth - cbTotalWidth) div 2
    let cbY2 = contentY + contentHeight - 118
    let cbHov = mousePos.x >= cbX2.float32 and mousePos.x <= (cbX2 + cbTotalWidth).float32 and
                mousePos.y >= cbY2.float32 and mousePos.y <= (cbY2 + cbSize2).float32
    drawCheckbox(cbX2, cbY2, cbSize2, pvpWin.showIPs, cbHov, cbText, 15)

    let cancelBX = contentX + (contentWidth - 200) div 2
    let cancelBY = contentY + contentHeight - 78
    let cancelHov2 = mousePos.x >= cancelBX.float32 and mousePos.x <= (cancelBX + 200).float32 and
                     mousePos.y >= cancelBY.float32 and mousePos.y <= (cancelBY + 44).float32
    drawDangerButton(cancelBX, cancelBY, 200, 44, t("general_cancel"), cancelHov2, 18)

  of plsJoining:
    drawRectangle(contentX.int32, (contentY + 48).int32, contentWidth.int32, 1,
                  Color(r: 0, g: 200, b: 255, a: 100))
    let titleText = t("pvp_join_game_title")
    let titleW = measureText(titleText, 24)
    drawText(titleText, (contentX + (contentWidth - titleW) div 2).int32,
             (contentY + 16).int32, 24, Color(r: 0, g: 220, b: 255, a: 255))

    let fX = contentX + 20
    let fW = contentWidth - 40

    drawText(t("pvp_nickname"), fX.int32, (contentY + 60).int32, 17, White)
    let jnfY = contentY + 80
    let jnfH = 36
    let jnickBefore = if pvpWin.cursorPos > 0 and pvpWin.cursorPos <= pvpWin.inputNickname.len:
                        pvpWin.inputNickname[0..<pvpWin.cursorPos] else: ""
    drawInputField(fX, jnfY, fW, jnfH, 10, 8, 20, pvpWin.editingNickname,
                   pvpWin.inputNickname, jnickBefore, pvpWin.cursorBlink,
                   pvpWin.selectionStart, pvpWin.selectionEnd)
    let jnickHint = t("pvp_click_cycle_tabs")
    let jnickHintW = measureText(jnickHint, 12)
    drawText(jnickHint, (contentX + (contentWidth - jnickHintW) div 2).int32,
             (jnfY + jnfH + 4).int32, 12, Color(r: 120, g: 130, b: 140, a: 200))

    drawSectionDivider(contentX + 15, contentX + contentWidth - 15, contentY + 130)

    drawText(t("pvp_host_ip"), fX.int32, (contentY + 138).int32, 17, White)
    let ipfY = contentY + 158
    let ipfH = 38
    let ipBefore = if pvpWin.cursorPos > 0 and pvpWin.cursorPos <= pvpWin.inputIP.len:
                     pvpWin.inputIP[0..<pvpWin.cursorPos] else: ""
    drawInputField(fX, ipfY, fW, ipfH, 10, 10, 20, pvpWin.editingIP,
                   pvpWin.inputIP, ipBefore, pvpWin.cursorBlink,
                   pvpWin.selectionStart, pvpWin.selectionEnd)

    drawText(t("pvp_port"), fX.int32, (contentY + 206).int32, 17, White)
    let portfY = contentY + 226
    let portBefore = if pvpWin.cursorPos > 0 and pvpWin.cursorPos <= pvpWin.inputPort.len:
                       pvpWin.inputPort[0..<pvpWin.cursorPos] else: ""
    drawInputField(fX, portfY, fW, ipfH, 10, 10, 20, pvpWin.editingPort,
                   pvpWin.inputPort, portBefore, pvpWin.cursorBlink,
                   pvpWin.selectionStart, pvpWin.selectionEnd)

    drawSectionDivider(contentX + 15, contentX + contentWidth - 15, contentY + 278)

    let connBX = contentX + (contentWidth - 220) div 2
    let connBY = contentY + 292
    let connHov = mousePos.x >= connBX.float32 and mousePos.x <= (connBX + 220).float32 and
                  mousePos.y >= connBY.float32 and mousePos.y <= (connBY + 46).float32
    drawPrimaryButton(connBX, connBY, 220, 46, t("pvp_connect"), connHov, fontSize = 22)

    let backBY = connBY + 54
    let backHov = mousePos.x >= connBX.float32 and mousePos.x <= (connBX + 220).float32 and
                  mousePos.y >= backBY.float32 and mousePos.y <= (backBY + 42).float32
    drawDangerButton(connBX, backBY, 220, 42, t("pvp_back"), backHov, 20)

  of plsConnecting:
    let titleText = t("pvp_connecting")
    let titleW = measureText(titleText, 28)
    drawText(titleText,
             (contentX + (contentWidth - titleW) div 2).int32,
             (contentY + contentHeight div 2 - 55).int32, 28,
             Color(r: 0, g: 220, b: 255, a: 255))

    let dots = ".".repeat(((pvpWin.cursorBlink * 2).int mod 4))
    let statusText = t("pvp_please_wait") & dots
    let statusW = measureText(statusText, 18)
    drawText(statusText, (contentX + (contentWidth - statusW) div 2).int32,
             (contentY + contentHeight div 2).int32, 18, White)

    let timeoutText = t("pvp_timeout_in") & " " & $pvpWin.connectionTimeout.int & "s"
    let timeoutW = measureText(timeoutText, 16)
    drawText(timeoutText, (contentX + (contentWidth - timeoutW) div 2).int32,
             (contentY + contentHeight div 2 + 30).int32, 16, LightGray)

  of plsConnected:
    if pvpWin.isHost:
      drawRectangle(contentX.int32, (contentY + 48).int32, contentWidth.int32, 1,
                    Color(r: 0, g: 200, b: 255, a: 100))
      let titleText = t("pvp_game_lobby")
      let titleW = measureText(titleText, 28)
      drawText(titleText, (contentX + (contentWidth - titleW) div 2).int32,
               (contentY + 12).int32, 28, Color(r: 0, g: 220, b: 255, a: 255))

      let playerCount = pvpWin.networkManager.getConnectedPlayerCount()
      let pctText = t("pvp_players_count") & " " & $playerCount & " / " & $pvpWin.maxPlayers
      let pctW = measureText(pctText, 18)
      drawText(pctText, (contentX + (contentWidth - pctW) div 2).int32,
               (contentY + 50).int32, 18,
               if playerCount >= 2: Color(r: 0, g: 200, b: 255, a: 255)
               else: LightGray)

      drawSectionDivider(contentX + 15, contentX + contentWidth - 15, contentY + 84)

      drawText(t("pvp_connected_label"), (contentX + 20).int32, (contentY + 92).int32, 16, LightGray)
      if pvpWin.teamsEnabled:
        drawText(t("pvp_click_badge_team"), (contentX + 20).int32, (contentY + 110).int32, 12,
                 Color(r: 120, g: 130, b: 140, a: 200))

      let hostNick = if pvpWin.inputNickname.len > 0: pvpWin.inputNickname else: "Host"
      drawText("> " & hostNick & t("pvp_you"),
               (contentX + 30).int32, (contentY + 128).int32, 16,
               Color(r: 255, g: 200, b: 50, a: 255))
      if pvpWin.teamsEnabled and pvpWin.playerTeamAssignments.len > 0:
        let hTeam = PvPTeam(pvpWin.playerTeamAssignments[0])
        let hTeamCol = getTeamColor(hTeam)
        let hBX = contentX + 270
        let hBY = contentY + 130
        drawRectangle(hBX.int32, hBY.int32, 60, 20, Color(r: 25, g: 25, b: 35, a: 255))
        drawRectangleLines(Rectangle(x: hBX.float32, y: hBY.float32, width: 60, height: 20), 1, hTeamCol)
        let hTN = getTeamName(hTeam)
        let hTNW = measureText(hTN, 13)
        drawText(hTN, (hBX + (60 - hTNW) div 2).int32, (hBY + 4).int32, 13, hTeamCol)
        drawText("▲", (hBX + 64).int32, (hBY + 3).int32, 12, LightGray)

      # Client rows
      var yOff = 130
      for i, client in pvpWin.networkManager.clients:
        yOff += 24
        let nick = if client.nickname.len > 0: client.nickname else: t("pvp_player_num") & $(client.playerIndex + 1)
        if pvpWin.teamsEnabled:
          let pIdx = client.playerIndex
          var pTeam = getTeamForPlayer(pIdx, pvpWin.numTeams)
          if pIdx >= 0 and pIdx < pvpWin.playerTeamAssignments.len:
            pTeam = PvPTeam(pvpWin.playerTeamAssignments[pIdx])
          let pCol = getTeamColor(pTeam)
          drawText("> " & nick, (contentX + 30).int32, (contentY + yOff).int32, 17, White)
          let pBX = contentX + 270
          let pBY = contentY + yOff
          drawRectangle(pBX.int32, pBY.int32, 60, 20, Color(r: 25, g: 25, b: 35, a: 255))
          drawRectangleLines(Rectangle(x: pBX.float32, y: pBY.float32, width: 60, height: 20), 1, pCol)
          let pTN = getTeamName(pTeam)
          let pTNW = measureText(pTN, 13)
          drawText(pTN, (pBX + (60 - pTNW) div 2).int32, (pBY + 4).int32, 13, pCol)
          drawText("▲", (pBX + 64).int32, (pBY + 3).int32, 12, LightGray)
        else:
          drawText("> " & nick & "  (P" & $(client.playerIndex + 1) & ")",
                   (contentX + 30).int32, (contentY + yOff).int32, 17, White)

      # Start / Cancel buttons
      let startBX = contentX + (contentWidth - 250) div 2
      let startBY = contentY + contentHeight - 118
      let canStart = playerCount >= 2
      let startHov = mousePos.x >= startBX.float32 and mousePos.x <= (startBX + 250).float32 and
                     mousePos.y >= startBY.float32 and mousePos.y <= (startBY + 50).float32
      if canStart:
        drawPrimaryButton(startBX, startBY, 250, 50, t("pvp_start_game"), startHov, fontSize = 22)
      else:
        drawRectangle(startBX.int32, startBY.int32, 250, 50, Color(r: 40, g: 40, b: 50, a: 255))
        drawRectangleLines(Rectangle(x: startBX.float32, y: startBY.float32, width: 250, height: 50),
                           1, Color(r: 60, g: 60, b: 80, a: 255))
        let ntW = measureText(t("pvp_need_2_players"), 16)
        drawText(t("pvp_need_2_players"),
                 (startBX + (250 - ntW) div 2).int32, (startBY + 17).int32, 16,
                 Color(r: 120, g: 120, b: 140, a: 255))

      let cancelBY = startBY + 58
      let cancelHov3 = mousePos.x >= startBX.float32 and mousePos.x <= (startBX + 250).float32 and
                       mousePos.y >= cancelBY.float32 and mousePos.y <= (cancelBY + 42).float32
      drawDangerButton(startBX, cancelBY, 250, 42, t("general_cancel"), cancelHov3, 18)

    else:
      # Client waiting view
      drawRectangle(contentX.int32, (contentY + 48).int32, contentWidth.int32, 1,
                    Color(r: 0, g: 200, b: 255, a: 100))
      let titleText = t("pvp_connected")
      let titleW = measureText(titleText, 28)
      drawText(titleText, (contentX + (contentWidth - titleW) div 2).int32,
               (contentY + 12).int32, 28, Color(r: 0, g: 220, b: 255, a: 255))

      drawSectionDivider(contentX + 15, contentX + contentWidth - 15, contentY + 60)

      if pvpWin.connectedPlayers.len > 0:
        drawText(t("pvp_players_in_lobby"), (contentX + 20).int32, (contentY + 70).int32, 17, White)
        var pY = 0
        for cp in pvpWin.connectedPlayers:
          let nick = if cp.nickname.len > 0: cp.nickname else: t("pvp_player_num") & $(cp.index + 1)
          let isMe = cp.index == pvpWin.assignedPlayerIndex
          let label = "> " & nick & (if isMe: t("pvp_you") else: "  (P" & $(cp.index + 1) & ")")
          drawText(label, (contentX + 35).int32, (contentY + 96 + pY).int32, 17,
                  if isMe: Gold else: White)
          pY += 24

      let waitText = t("pvp_waiting_for_host")
      let waitW = measureText(waitText, 18)
      drawText(waitText, (contentX + (contentWidth - waitW) div 2).int32,
               (contentY + contentHeight - 64).int32, 18, LightGray)
      let spinStr = if ((pvpWin.cursorBlink * 2).int mod 2) == 0: "◉  ◎  ◉  ◎" else: "◎  ◉  ◎  ◉"
      let spinW = measureText(spinStr, 14)
      drawText(spinStr, (contentX + (contentWidth - spinW) div 2).int32,
               (contentY + contentHeight - 38).int32, 14,
               Color(r: 0, g: 180, b: 255, a: 160))

  of plsError:
    drawRectangle(contentX.int32, (contentY + 54).int32, contentWidth.int32, 1,
                  Color(r: 180, g: 50, b: 50, a: 255))
    let titleText = t("pvp_connection_error")
    let titleW = measureText(titleText, 26)
    drawText(titleText, (contentX + (contentWidth - titleW) div 2).int32,
             (contentY + 16).int32, 26, Color(r: 255, g: 100, b: 100, a: 255))

    # Error panel
    let panelX = contentX + 20
    let panelY = contentY + 68
    let panelW = contentWidth - 40
    let panelH = 80
    drawRectangle(panelX.int32, panelY.int32, panelW.int32, panelH.int32,
                  Color(r: 25, g: 25, b: 35, a: 255))
    drawRectangle(panelX.int32, panelY.int32, panelW.int32, 2,
                  Color(r: 180, g: 50, b: 50, a: 255))
    drawRectangleLines(Rectangle(x: panelX.float32, y: panelY.float32,
      width: panelW.float32, height: panelH.float32), 1,
      Color(r: 80, g: 40, b: 40, a: 255))
    let errW = measureText(pvpWin.errorMessage, 16)
    drawText(pvpWin.errorMessage,
             (panelX + (panelW - errW) div 2).int32,
             (panelY + (panelH - 16) div 2).int32, 16, White)

    let backBX = contentX + (contentWidth - 200) div 2
    let backBY = contentY + contentHeight - 90
    let backHov2 = mousePos.x >= backBX.float32 and mousePos.x <= (backBX + 200).float32 and
                   mousePos.y >= backBY.float32 and mousePos.y <= (backBY + 48).float32
    drawDangerButton(backBX, backBY, 200, 48, t("pvp_back"), backHov2, 22)

proc handlePvPWindowClick*(pvpWin: PvPWindow, contentX, contentY, contentWidth, contentHeight: int): int =
  ## Returns: 0 = no action, 1 = host config, 2 = join, 3 = back/cancel, 4 = connect, 5 = start game, 6 = start hosting
  if not isMouseButtonPressed(Left):
    return 0
  let mousePos = getMousePosition()
  case pvpWin.state
  of plsMainMenu:
    let btnW = 300
    let btnH = 54
    let btnX = contentX + (contentWidth - btnW) div 2
    let hostY = contentY + 150
    if mousePos.x >= btnX.float32 and mousePos.x <= (btnX + btnW).float32 and
       mousePos.y >= hostY.float32 and mousePos.y <= (hostY + btnH).float32:
      return 1
    let joinY = hostY + btnH + 22
    if mousePos.x >= btnX.float32 and mousePos.x <= (btnX + btnW).float32 and
       mousePos.y >= joinY.float32 and mousePos.y <= (joinY + btnH).float32:
      return 2

  of plsHostingConfig:
    let nfX = contentX + 20
    let nfY = contentY + 84
    let nfW = contentWidth - 40
    if mousePos.x >= nfX.float32 and mousePos.x <= (nfX + nfW).float32 and
       mousePos.y >= nfY.float32 and mousePos.y <= (nfY + 36).float32:
      pvpWin.editingNickname = true
      let cp = getTextCursorPos(pvpWin.inputNickname, nfX, nfY + 8, 20, 28, mousePos.x, mousePos.y)
      if cp >= 0:
        pvpWin.cursorPos = cp
        pvpWin.mouseDownPos = mousePos
        pvpWin.isDragging = true
        pvpWin.selectionStart = cp
        pvpWin.selectionEnd = cp
      return 0
    else:
      pvpWin.editingNickname = false

    let pcY = contentY + 172
    let spacing = 110
    let centerX = contentX + contentWidth div 2
    let minusX = centerX - spacing
    if mousePos.x >= (minusX - 20).float32 and mousePos.x <= (minusX + 20).float32 and
       mousePos.y >= pcY.float32 and mousePos.y <= (pcY + 40).float32:
      if pvpWin.maxPlayers > 2: pvpWin.maxPlayers -= 1
      return 0
    let plusX = centerX + spacing
    if mousePos.x >= (plusX - 20).float32 and mousePos.x <= (plusX + 20).float32 and
       mousePos.y >= pcY.float32 and mousePos.y <= (pcY + 40).float32:
      if pvpWin.maxPlayers < 16: pvpWin.maxPlayers += 1
      return 0

    let cbX = contentX + 20
    let cbSize = 20
    if mousePos.x >= cbX.float32 and mousePos.x <= (cbX + cbSize + 200).float32 and
       mousePos.y >= (contentY + 232).float32 and mousePos.y <= (contentY + 252).float32:
      pvpWin.showIPs = not pvpWin.showIPs
      return 0
    if mousePos.x >= cbX.float32 and mousePos.x <= (cbX + cbSize + 250).float32 and
       mousePos.y >= (contentY + 260).float32 and mousePos.y <= (contentY + 280).float32:
      pvpWin.interpolationEnabled = not pvpWin.interpolationEnabled
      return 0
    if mousePos.x >= cbX.float32 and mousePos.x <= (cbX + cbSize + 230).float32 and
       mousePos.y >= (contentY + 325).float32 and mousePos.y <= (contentY + 345).float32:
      pvpWin.teamsEnabled = not pvpWin.teamsEnabled
      return 0

    if pvpWin.teamsEnabled:
      let tbY = contentY + 352
      let tbW = 42
      let tbSp = 56
      let tbStartX = contentX + 210
      for tc in 2..6:
        let tbX = tbStartX + (tc - 2) * tbSp
        if mousePos.x >= tbX.float32 and mousePos.x <= (tbX + tbW).float32 and
           mousePos.y >= tbY.float32 and mousePos.y <= (tbY + 32).float32:
          pvpWin.numTeams = tc
          return 0

    let startBX = contentX + (contentWidth - 250) div 2
    let startBY = contentY + contentHeight - 118
    if mousePos.x >= startBX.float32 and mousePos.x <= (startBX + 250).float32 and
       mousePos.y >= startBY.float32 and mousePos.y <= (startBY + 56).float32:
      return 6
    let cancelBY = startBY + 64
    if mousePos.x >= startBX.float32 and mousePos.x <= (startBX + 250).float32 and
       mousePos.y >= cancelBY.float32 and mousePos.y <= (cancelBY + 46).float32:
      return 3

  of plsHostingActive:
    let cbSize2 = 18
    let cbText = t("pvp_show_ip")
    let cbTextWidth = measureText(cbText, 15)
    let cbTotalWidth = cbSize2 + 10 + cbTextWidth
    let cbX2 = contentX + (contentWidth - cbTotalWidth) div 2
    let cbY2 = contentY + contentHeight - 118
    if mousePos.x >= cbX2.float32 and mousePos.x <= (cbX2 + cbTotalWidth).float32 and
       mousePos.y >= cbY2.float32 and mousePos.y <= (cbY2 + cbSize2).float32:
      pvpWin.showIPs = not pvpWin.showIPs
      return 0

    if pvpWin.teamsEnabled:
      let playerListStartY = contentY + 176
      let playerEntryHeight = 20
      let playerListEndY = playerListStartY + (pvpWin.networkManager.clients.len + 1) * playerEntryHeight
      if mousePos.y >= playerListStartY.float32 and mousePos.y <= playerListEndY.float32:
        let relY = (mousePos.y - playerListStartY.float32).int
        let slot = relY div playerEntryHeight
        if slot > 0 and slot <= pvpWin.networkManager.clients.len:
          let clientIndex = slot - 1
          if clientIndex >= 0 and clientIndex < pvpWin.networkManager.clients.len:
            let client = pvpWin.networkManager.clients[clientIndex]
            let pIdx = client.playerIndex
            while pvpWin.playerTeamAssignments.len <= pIdx:
              pvpWin.playerTeamAssignments.add(1)
            let cur = pvpWin.playerTeamAssignments[pIdx]
            pvpWin.playerTeamAssignments[pIdx] = ((cur - 1 + 1) mod pvpWin.numTeams) + 1
            return 0

    let cancelBX = contentX + (contentWidth - 200) div 2
    let cancelBY2 = contentY + contentHeight - 78
    if mousePos.x >= cancelBX.float32 and mousePos.x <= (cancelBX + 200).float32 and
       mousePos.y >= cancelBY2.float32 and mousePos.y <= (cancelBY2 + 48).float32:
      return 3

  of plsJoining:
    let fX = contentX + 20
    let fW = contentWidth - 40

    if mousePos.x >= fX.float32 and mousePos.x <= (fX + fW).float32 and
       mousePos.y >= (contentY + 80).float32 and mousePos.y <= (contentY + 116).float32:
      pvpWin.editingNickname = true
      pvpWin.editingIP = false
      pvpWin.editingPort = false
      let cp = getTextCursorPos(pvpWin.inputNickname, fX, contentY + 88, 20, 28, mousePos.x, mousePos.y)
      if cp >= 0:
        pvpWin.cursorPos = cp
        pvpWin.mouseDownPos = mousePos
        pvpWin.isDragging = true
        pvpWin.selectionStart = cp
        pvpWin.selectionEnd = cp

    if mousePos.x >= fX.float32 and mousePos.x <= (fX + fW).float32 and
       mousePos.y >= (contentY + 158).float32 and mousePos.y <= (contentY + 198).float32:
      pvpWin.editingIP = true
      pvpWin.editingPort = false
      pvpWin.editingNickname = false
      let cp = getTextCursorPos(pvpWin.inputIP, fX, contentY + 168, 20, 30, mousePos.x, mousePos.y)
      if cp >= 0:
        pvpWin.cursorPos = cp
        pvpWin.mouseDownPos = mousePos
        pvpWin.isDragging = true
        pvpWin.selectionStart = cp
        pvpWin.selectionEnd = cp

    if mousePos.x >= fX.float32 and mousePos.x <= (fX + fW).float32 and
       mousePos.y >= (contentY + 228).float32 and mousePos.y <= (contentY + 268).float32:
      pvpWin.editingIP = false
      pvpWin.editingPort = true
      pvpWin.editingNickname = false
      let cp = getTextCursorPos(pvpWin.inputPort, fX, contentY + 238, 20, 30, mousePos.x, mousePos.y)
      if cp >= 0:
        pvpWin.cursorPos = cp
        pvpWin.mouseDownPos = mousePos
        pvpWin.isDragging = true
        pvpWin.selectionStart = cp
        pvpWin.selectionEnd = cp

    let connBX = contentX + (contentWidth - 220) div 2
    if mousePos.x >= connBX.float32 and mousePos.x <= (connBX + 220).float32 and
       mousePos.y >= (contentY + 294).float32 and mousePos.y <= (contentY + 344).float32:
      return 4
    let backBY = contentY + 352
    if mousePos.x >= connBX.float32 and mousePos.x <= (connBX + 220).float32 and
       mousePos.y >= backBY.float32 and mousePos.y <= (backBY + 46).float32:
      return 3

  of plsConnected:
    if pvpWin.isHost:
      if pvpWin.teamsEnabled:
        let listY = contentY + 130
        let hBX = contentX + 270
        if mousePos.x >= hBX.float32 and mousePos.x <= (hBX + 60).float32 and
           mousePos.y >= listY.float32 and mousePos.y <= (listY + 20).float32:
          while pvpWin.playerTeamAssignments.len <= 0:
            pvpWin.playerTeamAssignments.add(1)
          let cur = pvpWin.playerTeamAssignments[0]
          pvpWin.playerTeamAssignments[0] = ((cur - 1 + 1) mod pvpWin.numTeams) + 1
          return 0
        var yOff = 130
        for i, client in pvpWin.networkManager.clients:
          yOff += 24
          let pBX = contentX + 270
          let pBY = contentY + yOff
          if mousePos.x >= pBX.float32 and mousePos.x <= (pBX + 60).float32 and
             mousePos.y >= pBY.float32 and mousePos.y <= (pBY + 20).float32:
            let pIdx = client.playerIndex
            while pvpWin.playerTeamAssignments.len <= pIdx:
              pvpWin.playerTeamAssignments.add(1)
            let cur = pvpWin.playerTeamAssignments[pIdx]
            pvpWin.playerTeamAssignments[pIdx] = ((cur - 1 + 1) mod pvpWin.numTeams) + 1
            return 0

      let startBX = contentX + (contentWidth - 250) div 2
      let startBY = contentY + contentHeight - 118
      let playerCount = pvpWin.networkManager.getConnectedPlayerCount()
      if playerCount >= 2 and
         mousePos.x >= startBX.float32 and mousePos.x <= (startBX + 250).float32 and
         mousePos.y >= startBY.float32 and mousePos.y <= (startBY + 58).float32:
        pvpWin.readyToStart = true
        return 5
      let cancelBY3 = startBY + 66
      if mousePos.x >= startBX.float32 and mousePos.x <= (startBX + 250).float32 and
         mousePos.y >= cancelBY3.float32 and mousePos.y <= (cancelBY3 + 44).float32:
        return 3

  of plsError:
    let backBX = contentX + (contentWidth - 200) div 2
    let backBY = contentY + contentHeight - 90
    if mousePos.x >= backBX.float32 and mousePos.x <= (backBX + 200).float32 and
       mousePos.y >= backBY.float32 and mousePos.y <= (backBY + 48).float32:
      return 3

  else:
    discard

  return 0
