## PvP Lobby Window
## Network lobby interface as an OS-style window

import raylib, strutils, net, math
import os_window, ../network/network, ../network/network_types, ../types, ../localization, ../render_context

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
    pvpConfig*: PvPConfig        # Host-configurable game balance settings

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
  of ptRed:    return t(tkPvPTeamRed)
  of ptBlue:   return t(tkPvPTeamBlue)
  of ptGreen:  return t(tkPvPTeamGreen)
  of ptYellow: return t(tkPvPTeamYellow)
  of ptOrange: return t(tkPvPTeamOrange)
  of ptPurple: return t(tkPvPTeamPurple)
  of ptNone:   return t(tkPvPTeamNone)

proc newPvPWindow*(screenWidth, screenHeight: int): PvPWindow =
  let windowWidth = 600
  let windowHeight = 670 # Sized to the hosting-config screen (the tallest state)
  let windowX = (screenWidth - windowWidth) div 2
  let windowY = (screenHeight - windowHeight) div 2
  let localIP = getLocalIP()
  result = PvPWindow(
    window: newOSWindow(t(tkPvPTitle), windowX, windowY, windowWidth, windowHeight,
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
    interpolationEnabled: true,
    pvpConfig: defaultPvPConfig()
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
          pvpWin.pvpConfig = event.packet.pvpConfig
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
  ## A thin accent line that glows in the middle and fades out toward both ends.
  let w = x2 - x1
  let half = w div 2
  let edge = Color(r: 0, g: 200, b: 255, a: 0)
  let mid  = Color(r: 0, g: 200, b: 255, a: 130)
  drawRectangleGradientH(x1.int32, y.int32, half.int32, 1, edge, mid)
  drawRectangleGradientH((x1 + half).int32, y.int32, (w - half).int32, 1, mid, edge)

proc drawPrimaryButton(bx, by, bw, bh: int, label: string, hovered: bool,
                       baseColor = Color(r: 0, g: 60, b: 80, a: 255),
                       hoverColor = Color(r: 0, g: 95, b: 125, a: 255),
                       fontSize: int32 = 24) =
  drawRectangle(bx.int32, by.int32, bw.int32, bh.int32, if hovered: hoverColor else: baseColor)
  # Glossy top highlight for a bit of depth
  drawRectangle((bx + 1).int32, (by + 1).int32, (bw - 2).int32, (bh.float32 * 0.42'f32).int32,
                Color(r: 255, g: 255, b: 255, a: if hovered: 26 else: 14))
  let borderCol = if hovered: Color(r: 0, g: 220, b: 255, a: 255)
                  else: Color(r: 70, g: 95, b: 115, a: 255)
  drawRectangleLines(Rectangle(x: bx.float32, y: by.float32, width: bw.float32, height: bh.float32),
                     if hovered: 2.0'f32 else: 1.0'f32, borderCol)
  let tw = measureText(label, fontSize)
  drawText(label, (bx + (bw - tw) div 2).int32, (by + (bh - fontSize.int) div 2).int32, fontSize,
           if hovered: White else: Color(r: 220, g: 235, b: 245, a: 255))

proc drawDangerButton(bx, by, bw, bh: int, label: string, hovered: bool, fontSize: int32 = 22) =
  let col = if hovered: Color(r: 95, g: 35, b: 35, a: 255) else: Color(r: 50, g: 22, b: 22, a: 255)
  drawRectangle(bx.int32, by.int32, bw.int32, bh.int32, col)
  drawRectangle((bx + 1).int32, (by + 1).int32, (bw - 2).int32, (bh.float32 * 0.42'f32).int32,
                Color(r: 255, g: 255, b: 255, a: if hovered: 22 else: 12))
  let borderCol = if hovered: Color(r: 220, g: 90, b: 90, a: 255) else: Color(r: 110, g: 55, b: 55, a: 255)
  drawRectangleLines(Rectangle(x: bx.float32, y: by.float32, width: bw.float32, height: bh.float32),
                     if hovered: 2.0'f32 else: 1.0'f32, borderCol)
  let tw = measureText(label, fontSize)
  drawText(label, (bx + (bw - tw) div 2).int32, (by + (bh - fontSize.int) div 2).int32, fontSize,
           if hovered: Color(r: 255, g: 130, b: 130, a: 255) else: Color(r: 235, g: 210, b: 210, a: 255))

proc drawCheckbox(cbx, cby, cbSize: int, checked, hovered: bool, label: string, labelFontSize: int32 = 17) =
  let rect = Rectangle(x: cbx.float32, y: cby.float32, width: cbSize.float32, height: cbSize.float32)
  let bgColor = if checked: Color(r: 0, g: 70, b: 95, a: 255)
                elif hovered: Color(r: 75, g: 75, b: 95, a: 255)
                else: Color(r: 55, g: 55, b: 72, a: 255)
  drawRectangle(cbx.int32, cby.int32, cbSize.int32, cbSize.int32, bgColor)
  let borderCol = if checked: Color(r: 0, g: 200, b: 255, a: 255)
                  elif hovered: Color(r: 150, g: 150, b: 170, a: 255)
                  else: Color(r: 110, g: 110, b: 130, a: 255)
  drawRectangleLines(rect, 1.0'f32, borderCol)
  if checked:
    let chkCol = Color(r: 0, g: 230, b: 180, a: 255)
    drawLine(Vector2(x: (cbx + 5).float32, y: (cby + cbSize div 2).float32),
             Vector2(x: (cbx + cbSize div 2 - 2).float32, y: (cby + cbSize - 5).float32), 3, chkCol)
    drawLine(Vector2(x: (cbx + cbSize div 2 - 2).float32, y: (cby + cbSize - 5).float32),
             Vector2(x: (cbx + cbSize - 3).float32, y: (cby + 3).float32), 3, chkCol)
  drawText(label, (cbx + cbSize + 10).int32, (cby + (cbSize - labelFontSize.int) div 2).int32,
           labelFontSize, Color(r: 225, g: 225, b: 235, a: 255))

proc drawInputField(fx, fy, fw, fh, textOffX, textOffY, fontSize: int, active: bool,
                    text, textBefore: string, cursorBlink: float32,
                    selStart, selEnd: int) =
  let rect = Rectangle(x: fx.float32, y: fy.float32, width: fw.float32, height: fh.float32)
  let bgCol = if active: Color(r: 0, g: 55, b: 75, a: 255) else: Color(r: 38, g: 38, b: 50, a: 255)
  drawRectangle(fx.int32, fy.int32, fw.int32, fh.int32, bgCol)
  let borderCol = if active: Color(r: 0, g: 210, b: 255, a: 255) else: Color(r: 80, g: 80, b: 100, a: 255)
  drawRectangleLines(rect, 2.0'f32, borderCol)
  if active:
    drawTextSelection(text, fx, fy, fontSize, selStart, selEnd)
  drawText(text, (fx + textOffX).int32, (fy + textOffY).int32, fontSize.int32, White)
  if active and (cursorBlink.int mod 2) == 0:
    let cx = fx + textOffX + measureText(textBefore, fontSize.int32)
    drawLine(Vector2(x: cx.float32, y: (fy + textOffY - 2).float32),
             Vector2(x: cx.float32, y: (fy + fh - textOffY + 2).float32), 2,
             Color(r: 0, g: 210, b: 255, a: 255))

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
    fieldX = contentX + 20
    fontSize = 20
    if pvpWin.state == plsJoining:
      fieldY = contentY + 80
      fieldHeight = 36
    else:
      fieldY = contentY + 82
      fieldHeight = 32
  elif pvpWin.editingIP:
    activeText = addr pvpWin.inputIP
    fieldX = contentX + 20
    fieldY = contentY + 158
    fontSize = 20
    fieldHeight = 38
  elif pvpWin.editingPort:
    activeText = addr pvpWin.inputPort
    fieldX = contentX + 20
    fieldY = contentY + 226
    fontSize = 20
    fieldHeight = 38

  if activeText != nil:
    let mousePos = getVirtualMousePosition()
    if isPointerPressed():
      let cursorPos = getTextCursorPos(activeText[], fieldX, fieldY, fontSize, fieldHeight, mousePos.x, mousePos.y)
      if cursorPos >= 0:
        pvpWin.mouseDownPos = mousePos
        pvpWin.isDragging = true
        pvpWin.selectionStart = cursorPos
        pvpWin.selectionEnd = cursorPos
    if pvpWin.isDragging and isPointerDown():
      let cursorPos = getTextCursorPos(activeText[], fieldX, fieldY, fontSize, fieldHeight, mousePos.x, mousePos.y)
      if cursorPos >= 0:
        let dragDist = sqrt((mousePos.x - pvpWin.mouseDownPos.x) * (mousePos.x - pvpWin.mouseDownPos.x) +
                           (mousePos.y - pvpWin.mouseDownPos.y) * (mousePos.y - pvpWin.mouseDownPos.y))
        if dragDist > 3.0:
          pvpWin.selectionEnd = cursorPos
    if isPointerReleased():
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
      let text = getClipboardText()
      if text.len > 0:
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
  # The on-screen keyboard is the only way to fill these fields on Android:
  # NativeActivity never raises a soft keyboard, so getCharPressed stays silent
  # and PvP could not be joined at all. Numeric layout for IP/port.
  setTextInputActive(pvpWin.editingNickname or pvpWin.editingIP or pvpWin.editingPort,
                     if pvpWin.editingNickname: tikText else: tikNumeric)
  var key = pollCharPressed()
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
    key = pollCharPressed()

  # Backspace with repeat
  let backspacePressed = pollBackspacePressed()
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
  let mousePos = getVirtualMousePosition()

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

    let sub = t(tkPvPLocalNetMultiplayer)
    let subW = measureText(sub, 14)
    drawText(sub, (contentX + (contentWidth - subW) div 2).int32,
             (contentY + 68).int32, 14, Color(r: 120, g: 130, b: 140, a: 255))

    let btnW = 300
    let btnH = 54
    let btnX = contentX + (contentWidth - btnW) div 2
    let hostY = contentY + 150

    let hostHov = mousePos.x >= btnX.float32 and mousePos.x <= (btnX + btnW).float32 and
                  mousePos.y >= hostY.float32 and mousePos.y <= (hostY + btnH).float32
    drawPrimaryButton(btnX, hostY, btnW, btnH, t("pvp_host_game"), hostHov, fontSize = 24)
    drawText("[ H ]", (btnX + 10).int32, (hostY + (btnH - 16) div 2).int32, 16,
             Color(r: 100, g: 130, b: 160, a: 200))

    let joinY = hostY + btnH + 22
    let joinHov = mousePos.x >= btnX.float32 and mousePos.x <= (btnX + btnW).float32 and
                  mousePos.y >= joinY.float32 and mousePos.y <= (joinY + btnH).float32
    drawPrimaryButton(btnX, joinY, btnW, btnH, t("pvp_join_game"), joinHov, fontSize = 24)
    drawText("[ J ]", (btnX + 10).int32, (joinY + (btnH - 16) div 2).int32, 16,
             Color(r: 100, g: 130, b: 160, a: 200))

    let info = t(tkPvPShareIPInfo)
    let infoW = measureText(info, 13)
    drawText(info, (contentX + (contentWidth - infoW) div 2).int32,
             (contentY + contentHeight - 30).int32, 13,
             Color(r: 100, g: 110, b: 120, a: 200))

  of plsHostingConfig:
    drawRectangle(contentX.int32, (contentY + 46).int32, contentWidth.int32, 1,
                  Color(r: 0, g: 200, b: 255, a: 100))
    let titleText = t("pvp_configure_hosting")
    let titleW = measureText(titleText, 22)
    drawText(titleText, (contentX + (contentWidth - titleW) div 2).int32,
             (contentY + 14).int32, 22, Color(r: 0, g: 220, b: 255, a: 255))

    # --- Nickname ---
    drawText(t("pvp_nickname"), (contentX + 20).int32, (contentY + 60).int32, 16, White)
    let nfX = contentX + 20
    let nfY = contentY + 82
    let nfW = contentWidth - 40
    let nfH = 32
    let nickBefore = if pvpWin.cursorPos > 0 and pvpWin.cursorPos <= pvpWin.inputNickname.len:
                       pvpWin.inputNickname[0..<pvpWin.cursorPos] else: ""
    drawInputField(nfX, nfY, nfW, nfH, 10, 7, 20, pvpWin.editingNickname,
                   pvpWin.inputNickname, nickBefore, pvpWin.cursorBlink,
                   pvpWin.selectionStart, pvpWin.selectionEnd)

    drawSectionDivider(contentX + 15, contentX + contentWidth - 15, contentY + 132)

    # --- Max Players (label left, stepper right, on one row) ---
    drawText(t("pvp_max_players"), (contentX + 20).int32, (contentY + 150).int32, 16, White)
    let pcY = contentY + 146
    let mBoxX = contentX + contentWidth - 152
    let pBoxX = contentX + contentWidth - 46
    let cntCenterX = (mBoxX + 26 + pBoxX) div 2
    let canMinus = pvpWin.maxPlayers > 2
    let minusHov = mousePos.x >= mBoxX.float32 and mousePos.x <= (mBoxX + 26).float32 and
                   mousePos.y >= pcY.float32 and mousePos.y <= (pcY + 26).float32
    let minusBg = if canMinus and minusHov: Color(r: 80, g: 80, b: 100, a: 255)
                  elif canMinus: Color(r: 50, g: 50, b: 65, a: 255)
                  else: Color(r: 35, g: 35, b: 45, a: 255)
    drawRectangle(mBoxX.int32, pcY.int32, 26, 26, minusBg)
    drawRectangleLines(Rectangle(x: mBoxX.float32, y: pcY.float32, width: 26, height: 26),
                       1, if canMinus: Color(r: 80, g: 80, b: 100, a: 255) else: Color(r: 50, g: 50, b: 60, a: 255))
    let mW = measureText("-", 22)
    drawText("-", (mBoxX + (26 - mW) div 2).int32, (pcY + 2).int32, 22,
             if canMinus: White else: Color(r: 80, g: 80, b: 80, a: 255))

    let cntStr = $pvpWin.maxPlayers
    let cntW = measureText(cntStr, 22)
    drawText(cntStr, (cntCenterX - cntW div 2).int32, (pcY + 1).int32, 22, Color(r: 0, g: 200, b: 255, a: 255))

    let canPlus = pvpWin.maxPlayers < 16
    let plusHov = mousePos.x >= pBoxX.float32 and mousePos.x <= (pBoxX + 26).float32 and
                  mousePos.y >= pcY.float32 and mousePos.y <= (pcY + 26).float32
    let plusBg = if canPlus and plusHov: Color(r: 80, g: 80, b: 100, a: 255)
                 elif canPlus: Color(r: 50, g: 50, b: 65, a: 255)
                 else: Color(r: 35, g: 35, b: 45, a: 255)
    drawRectangle(pBoxX.int32, pcY.int32, 26, 26, plusBg)
    drawRectangleLines(Rectangle(x: pBoxX.float32, y: pcY.float32, width: 26, height: 26),
                       1, if canPlus: Color(r: 80, g: 80, b: 100, a: 255) else: Color(r: 50, g: 50, b: 60, a: 255))
    let pW = measureText("+", 22)
    drawText("+", (pBoxX + (26 - pW) div 2).int32, (pcY + 2).int32, 22,
             if canPlus: White else: Color(r: 80, g: 80, b: 80, a: 255))

    drawSectionDivider(contentX + 15, contentX + contentWidth - 15, contentY + 184)

    # --- Options (two checkboxes side by side) ---
    let cbSize = 20
    let cbX = contentX + 20
    let cbY1 = contentY + 200
    let showIPHov = mousePos.x >= cbX.float32 and mousePos.x <= (cbX + cbSize + 150).float32 and
                    mousePos.y >= cbY1.float32 and mousePos.y <= (cbY1 + cbSize).float32
    drawCheckbox(cbX, cbY1, cbSize, pvpWin.showIPs, showIPHov, t("pvp_show_ips"), 15)
    let cbX2 = contentX + contentWidth div 2 + 10
    let interpHov = mousePos.x >= cbX2.float32 and mousePos.x <= (cbX2 + cbSize + 180).float32 and
                    mousePos.y >= cbY1.float32 and mousePos.y <= (cbY1 + cbSize).float32
    drawCheckbox(cbX2, cbY1, cbSize, pvpWin.interpolationEnabled, interpHov, t("pvp_enable_interpolation"), 15)

    drawSectionDivider(contentX + 15, contentX + contentWidth - 15, contentY + 236)

    # --- Teams (checkbox left, team-count buttons right when enabled) ---
    let cbY2 = contentY + 252
    let teamEnHov = mousePos.x >= cbX.float32 and mousePos.x <= (cbX + cbSize + 150).float32 and
                    mousePos.y >= cbY2.float32 and mousePos.y <= (cbY2 + cbSize).float32
    drawCheckbox(cbX, cbY2, cbSize, pvpWin.teamsEnabled, teamEnHov, t("pvp_enable_teams"), 15)

    if pvpWin.teamsEnabled:
      let tbY = contentY + 248
      let tbW = 34
      let tbSp = 44
      let tbStartX = contentX + 240
      for tc in 2..6:
        let tbX = tbStartX + (tc - 2) * tbSp
        let isSel = pvpWin.numTeams == tc
        let tbHov = mousePos.x >= tbX.float32 and mousePos.x <= (tbX + tbW).float32 and
                    mousePos.y >= tbY.float32 and mousePos.y <= (tbY + 28).float32
        let tbBg = if isSel: Color(r: 0, g: 60, b: 80, a: 255)
                   elif tbHov: Color(r: 50, g: 50, b: 60, a: 255)
                   else: Color(r: 40, g: 40, b: 50, a: 255)
        drawRectangle(tbX.int32, tbY.int32, tbW.int32, 28.int32, tbBg)
        drawRectangleLines(Rectangle(x: tbX.float32, y: tbY.float32, width: tbW.float32, height: 28),
                           1, if isSel: Color(r: 0, g: 200, b: 255, a: 255) else: Color(r: 80, g: 80, b: 100, a: 255))
        let tStr = $tc
        let tW = measureText(tStr, 18)
        drawText(tStr, (tbX + (tbW - tW) div 2).int32, (tbY + 5).int32, 18,
                 if isSel: Gold else: White)

    # GAME STATS SECTION
    drawSectionDivider(contentX + 15, contentX + contentWidth - 15, contentY + 288)
    drawText(t(tkPvPGameStats), (contentX + 20).int32, (contentY + 296).int32, 14,
             Color(r: 0, g: 200, b: 255, a: 255))

    # Helper: draw a compact stat cell with label, minus, value, plus
    # Layout: 3 columns, 4 rows
    let colW = (contentWidth - 20) div 3
    let baseStatY = contentY + 320

    template drawStatCell(cx, cy: int, lbl: string, valStr: string,
                          canDec, canInc: bool) =
      drawText(lbl, (cx + 2).int32, cy.int32, 13,
               Color(r: 170, g: 170, b: 190, a: 255))
      let controlY = cy + 15
      # Minus button
      let mBg = if canDec: Color(r: 50, g: 50, b: 65, a: 255)
                else: Color(r: 35, g: 35, b: 45, a: 255)
      drawRectangle((cx).int32, controlY.int32, 22, 22, mBg)
      drawRectangleLines(Rectangle(x: cx.float32, y: controlY.float32,
        width: 22, height: 22), 1,
        if canDec: Color(r: 80, g: 80, b: 110, a: 255)
        else: Color(r: 50, g: 50, b: 60, a: 255))
      let mW = measureText("-", 20)
      drawText("-", (cx + (22 - mW) div 2).int32, (controlY + 1).int32, 20,
               if canDec: White else: Color(r: 70, g: 70, b: 70, a: 255))
      # Value
      let vw = measureText(valStr, 16)
      drawText(valStr, (cx + 26 + (colW - 56 - vw) div 2).int32,
               (controlY + 3).int32, 16, Color(r: 0, g: 220, b: 255, a: 255))
      # Plus button
      let pBg = if canInc: Color(r: 50, g: 50, b: 65, a: 255)
                else: Color(r: 35, g: 35, b: 45, a: 255)
      drawRectangle((cx + colW - 24).int32, controlY.int32, 22, 22, pBg)
      drawRectangleLines(Rectangle(x: (cx + colW - 24).float32,
        y: controlY.float32, width: 22, height: 22), 1,
        if canInc: Color(r: 80, g: 80, b: 110, a: 255)
        else: Color(r: 50, g: 50, b: 60, a: 255))
      let pW = measureText("+", 20)
      drawText("+", (cx + colW - 24 + (22 - pW) div 2).int32,
               (controlY + 1).int32, 20,
               if canInc: White else: Color(r: 70, g: 70, b: 70, a: 255))

    # Row 0: HP | Kill Limit | Respawn Time
    let row0Y = baseStatY
    let row1Y = baseStatY + 46
    drawStatCell(contentX + 10,                row0Y,
      t(tkPvPStatHp),      $pvpWin.pvpConfig.startHp.int,
      pvpWin.pvpConfig.startHp > 1.0, pvpWin.pvpConfig.startHp < 20.0)
    drawStatCell(contentX + 10 + colW,        row0Y,
      t(tkPvPStatKillLimit), $pvpWin.pvpConfig.killLimit,
      pvpWin.pvpConfig.killLimit > 1, pvpWin.pvpConfig.killLimit < 30)
    drawStatCell(contentX + 10 + colW * 2,    row0Y,
      t(tkPvPStatRespawn),
      if pvpWin.pvpConfig.respawnTime == 0.0: t(tkPvPValueOff)
      else: pvpWin.pvpConfig.respawnTime.formatFloat(ffDecimal, 1),
      pvpWin.pvpConfig.respawnTime > 0.0, pvpWin.pvpConfig.respawnTime < 15.0)

    # Row 1: Speed | Damage | Fire Rate
    drawStatCell(contentX + 10,                row1Y,
      t(tkPvPStatSpeed),   $pvpWin.pvpConfig.startSpeed.int,
      pvpWin.pvpConfig.startSpeed > 75.0, pvpWin.pvpConfig.startSpeed < 400.0)
    drawStatCell(contentX + 10 + colW,        row1Y,
      t(tkPvPStatDamage),  pvpWin.pvpConfig.startDamage.formatFloat(ffDecimal, 1),
      pvpWin.pvpConfig.startDamage > 0.5, pvpWin.pvpConfig.startDamage < 10.0)
    drawStatCell(contentX + 10 + colW * 2,    row1Y,
      t(tkPvPStatFireRate),
      pvpWin.pvpConfig.fireRate.formatFloat(ffDecimal, 2),
      pvpWin.pvpConfig.fireRate > 0.105, pvpWin.pvpConfig.fireRate < 1.50)

    # Row 2: Bullet Speed | Bullet Radius | Start Walls
    let row2Y = baseStatY + 92
    drawStatCell(contentX + 10,                row2Y,
      t(tkPvPStatBulletSpeed), $pvpWin.pvpConfig.bulletSpeed.int,
      pvpWin.pvpConfig.bulletSpeed > 100.0, pvpWin.pvpConfig.bulletSpeed < 800.0)
    drawStatCell(contentX + 10 + colW,        row2Y,
      t(tkPvPStatBulletRadius), pvpWin.pvpConfig.bulletRadius.formatFloat(ffDecimal, 1),
      pvpWin.pvpConfig.bulletRadius > 3.0, pvpWin.pvpConfig.bulletRadius < 25.0)
    drawStatCell(contentX + 10 + colW * 2,    row2Y,
      t(tkPvPStatStartWalls),   $pvpWin.pvpConfig.startWalls,
      pvpWin.pvpConfig.startWalls > 0, pvpWin.pvpConfig.startWalls < 10)

    # Row 3: Time Limit (col 0) | Net Quality (col 1)
    let row3Y = baseStatY + 138
    let timeLimitStr = if pvpWin.pvpConfig.timeLimit <= 0: t(tkPvPValueOff)
                       else:
                         let m = (pvpWin.pvpConfig.timeLimit / 60).int
                         let s = (pvpWin.pvpConfig.timeLimit.int mod 60)
                         if s == 0: $m & "m" else: $m & "m " & $s & "s"
    drawStatCell(contentX + 10,         row3Y,
      t(tkPvPStatTimeLimit), timeLimitStr,
      pvpWin.pvpConfig.timeLimit > 0.0, true)

    let canPrevNet = pvpWin.pvpConfig.snapshotRate < 0.04   # not already at Low (1/20 = 0.05)
    let canNextNet = pvpWin.pvpConfig.snapshotRate > 0.011  # not already at Ultra (1/128 = 0.0078)
    let netQualityStr =
      if pvpWin.pvpConfig.snapshotRate <= 1.0 / 128.0 + 0.001: t(tkPvPNetQualityUltra)
      elif pvpWin.pvpConfig.snapshotRate <= 1.0 / 64.0 + 0.001: t(tkPvPNetQualityHigh)
      elif pvpWin.pvpConfig.snapshotRate <= 1.0 / 32.0 + 0.001: t(tkPvPNetQualityMedium)
      else: t(tkPvPNetQualityLow)
    drawStatCell(contentX + 10 + colW,  row3Y,
      t(tkPvPStatNetQuality), netQualityStr,
      canPrevNet, canNextNet)

    # END GAME STATS

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
      let stripe = if i mod 2 == 0: Color(r: 255, g: 255, b: 255, a: 10)
                   else: Color(r: 0, g: 200, b: 255, a: 14)
      drawRectangle((contentX + 16).int32, (contentY + yOff - 3).int32,
        (contentWidth - 32).int32, 20, stripe)
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

      let rowX = contentX + 16
      let rowW = contentWidth - 32
      drawRectangle(rowX.int32, (contentY + 124).int32, rowW.int32, 24,
                    Color(r: 60, g: 50, b: 20, a: 90))
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
        let stripe = if i mod 2 == 0: Color(r: 255, g: 255, b: 255, a: 10)
                     else: Color(r: 0, g: 200, b: 255, a: 14)
        drawRectangle((contentX + 16).int32, (contentY + yOff - 4).int32,
          (contentWidth - 32).int32, 24, stripe)
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
                  Color(r: 30, g: 22, b: 26, a: 255))
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
  if not isPointerPressed():
    return 0
  let mousePos = getVirtualMousePosition()
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
    let nfY = contentY + 82
    let nfW = contentWidth - 40
    if mousePos.x >= nfX.float32 and mousePos.x <= (nfX + nfW).float32 and
       mousePos.y >= nfY.float32 and mousePos.y <= (nfY + 32).float32:
      pvpWin.editingNickname = true
      let cp = getTextCursorPos(pvpWin.inputNickname, nfX, nfY + 7, 20, 32, mousePos.x, mousePos.y)
      if cp >= 0:
        pvpWin.cursorPos = cp
        pvpWin.mouseDownPos = mousePos
        pvpWin.isDragging = true
        pvpWin.selectionStart = cp
        pvpWin.selectionEnd = cp
      return 0
    else:
      pvpWin.editingNickname = false

    let pcY = contentY + 146
    let mBoxX = contentX + contentWidth - 152
    let pBoxX = contentX + contentWidth - 46
    if mousePos.x >= mBoxX.float32 and mousePos.x <= (mBoxX + 26).float32 and
       mousePos.y >= pcY.float32 and mousePos.y <= (pcY + 26).float32:
      if pvpWin.maxPlayers > 2: pvpWin.maxPlayers -= 1
      return 0
    if mousePos.x >= pBoxX.float32 and mousePos.x <= (pBoxX + 26).float32 and
       mousePos.y >= pcY.float32 and mousePos.y <= (pcY + 26).float32:
      if pvpWin.maxPlayers < 16: pvpWin.maxPlayers += 1
      return 0

    let cbX = contentX + 20
    let cbSize = 20
    let cbX2 = contentX + contentWidth div 2 + 10
    if mousePos.x >= cbX.float32 and mousePos.x <= (cbX + cbSize + 150).float32 and
       mousePos.y >= (contentY + 200).float32 and mousePos.y <= (contentY + 220).float32:
      pvpWin.showIPs = not pvpWin.showIPs
      return 0
    if mousePos.x >= cbX2.float32 and mousePos.x <= (cbX2 + cbSize + 180).float32 and
       mousePos.y >= (contentY + 200).float32 and mousePos.y <= (contentY + 220).float32:
      pvpWin.interpolationEnabled = not pvpWin.interpolationEnabled
      return 0
    if mousePos.x >= cbX.float32 and mousePos.x <= (cbX + cbSize + 150).float32 and
       mousePos.y >= (contentY + 252).float32 and mousePos.y <= (contentY + 272).float32:
      pvpWin.teamsEnabled = not pvpWin.teamsEnabled
      return 0

    if pvpWin.teamsEnabled:
      let tbY = contentY + 248
      let tbW = 34
      let tbSp = 44
      let tbStartX = contentX + 240
      for tc in 2..6:
        let tbX = tbStartX + (tc - 2) * tbSp
        if mousePos.x >= tbX.float32 and mousePos.x <= (tbX + tbW).float32 and
           mousePos.y >= tbY.float32 and mousePos.y <= (tbY + 28).float32:
          pvpWin.numTeams = tc
          return 0

    # GAME STATS click handling
    let colWc = (contentWidth - 20) div 3
    let row0Yc = contentY + 320
    let row1Yc = row0Yc + 46
    let mx = mousePos.x
    let my = mousePos.y

    template statClick(cx, cy: int, val: var float32, step, minVal, maxVal: float32) =
      let ctrlY = cy + 15
      if mx >= cx.float32 and mx <= (cx + 22).float32 and
         my >= ctrlY.float32 and my <= (ctrlY + 22).float32:
        val = max(minVal, val - step)
      let plusXt = cx + colWc - 24
      if mx >= plusXt.float32 and mx <= (plusXt + 22).float32 and
         my >= ctrlY.float32 and my <= (ctrlY + 22).float32:
        val = min(maxVal, val + step)

    template statClickInt(cx, cy: int, val: var int, step, minVal, maxVal: int) =
      let ctrlYi = cy + 15
      if mx >= cx.float32 and mx <= (cx + 22).float32 and
         my >= ctrlYi.float32 and my <= (ctrlYi + 22).float32:
        val = max(minVal, val - step)
      let plusXi = cx + colWc - 24
      if mx >= plusXi.float32 and mx <= (plusXi + 22).float32 and
         my >= ctrlYi.float32 and my <= (ctrlYi + 22).float32:
        val = min(maxVal, val + step)

    # Row 0: HP | Kill Limit | Respawn
    statClick(contentX + 10,             row0Yc, pvpWin.pvpConfig.startHp,     1.0, 1.0, 20.0)
    statClickInt(contentX + 10 + colWc,  row0Yc, pvpWin.pvpConfig.killLimit,   1,   1,   30)
    statClick(contentX + 10 + colWc * 2, row0Yc, pvpWin.pvpConfig.respawnTime, 0.5, 0.0, 15.0)
    # Row 1: Speed | Damage | Fire Rate
    statClick(contentX + 10,             row1Yc, pvpWin.pvpConfig.startSpeed,  25.0, 75.0,  400.0)
    statClick(contentX + 10 + colWc,     row1Yc, pvpWin.pvpConfig.startDamage, 0.5,  0.5,   10.0)
    statClick(contentX + 10 + colWc * 2, row1Yc, pvpWin.pvpConfig.fireRate,    0.05, 0.10,  1.50)
    # Row 2: Bullet Speed | Bullet Radius | Start Walls
    let row2Yc = row1Yc + 46
    statClick(contentX + 10,             row2Yc, pvpWin.pvpConfig.bulletSpeed,  25.0, 100.0, 800.0)
    statClick(contentX + 10 + colWc,     row2Yc, pvpWin.pvpConfig.bulletRadius,  0.5,   3.0,  25.0)
    statClickInt(contentX + 10 + colWc * 2, row2Yc, pvpWin.pvpConfig.startWalls, 1, 0, 10)

    # Row 3: Time Limit (col 0) & Net Quality (col 1), same row
    let row3Yc = row2Yc + 46
    let ctrlY3 = row3Yc + 15
    if mx >= (contentX + 10).float32 and mx <= (contentX + 32).float32 and
       my >= ctrlY3.float32 and my <= (ctrlY3 + 22).float32:
      # Decrease: step down by 30s, 0 = unlimited
      if pvpWin.pvpConfig.timeLimit > 0:
        pvpWin.pvpConfig.timeLimit = max(0.0, pvpWin.pvpConfig.timeLimit - 30.0)
    let plusX3 = contentX + 10 + colWc - 24
    if mx >= plusX3.float32 and mx <= (plusX3 + 22).float32 and
       my >= ctrlY3.float32 and my <= (ctrlY3 + 22).float32:
      if pvpWin.pvpConfig.timeLimit <= 0:
        pvpWin.pvpConfig.timeLimit = 30.0
      else:
        pvpWin.pvpConfig.timeLimit = min(3600.0, pvpWin.pvpConfig.timeLimit + 30.0)

    # Net Quality, cols 1+2, same row as Time Limit
    let netPresets = [(1.0'f32 / 20.0'f32,  1.0'f32 / 20.0'f32),   # Low    20 ticks/s
                      (1.0'f32 / 32.0'f32,  1.0'f32 / 32.0'f32),   # Medium 32 ticks/s
                      (1.0'f32 / 64.0'f32,  1.0'f32 / 64.0'f32),   # High   64 ticks/s
                      (1.0'f32 / 128.0'f32, 1.0'f32 / 128.0'f32)]  # Ultra 128 ticks/s
    var curPreset = 2  # default: High
    for idx, p in netPresets:
      if abs(pvpWin.pvpConfig.snapshotRate - p[0]) < 0.005:
        curPreset = idx
        break
    let netCol1Xc = contentX + 10 + colWc
    if mx >= netCol1Xc.float32 and mx <= (netCol1Xc + 22).float32 and
       my >= ctrlY3.float32 and my <= (ctrlY3 + 22).float32:
      let next = max(0, curPreset - 1)
      pvpWin.pvpConfig.snapshotRate = netPresets[next][0]
      pvpWin.pvpConfig.inputRate    = netPresets[next][1]
    let plusX4 = contentX + 10 + colWc * 2 - 24   # end of col 1
    if mx >= plusX4.float32 and mx <= (plusX4 + 22).float32 and
       my >= ctrlY3.float32 and my <= (ctrlY3 + 22).float32:
      let next = min(netPresets.len - 1, curPreset + 1)
      pvpWin.pvpConfig.snapshotRate = netPresets[next][0]
      pvpWin.pvpConfig.inputRate    = netPresets[next][1]

    # END GAME STATS click handling

    let startBX = contentX + (contentWidth - 250) div 2
    let startBY = contentY + contentHeight - 118
    if mousePos.x >= startBX.float32 and mousePos.x <= (startBX + 250).float32 and
       mousePos.y >= startBY.float32 and mousePos.y <= (startBY + 50).float32:
      return 6
    let cancelBY = startBY + 58
    if mousePos.x >= startBX.float32 and mousePos.x <= (startBX + 250).float32 and
       mousePos.y >= cancelBY.float32 and mousePos.y <= (cancelBY + 42).float32:
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
