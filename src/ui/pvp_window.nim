## PvP Lobby Window
## Network lobby interface as an OS-style window

import raylib, strutils, net, algorithm
import ../modding/mod_patch_core
import ../draw_prims
import os_window, ../network/network, ../network/network_types, ../types, ../localization, ../render_context, ../pvp_game
import ui_theme, text_field
from ui_helpers import fitWithEllipsis
from ../modding/mod_hooks import pvpModes, findPvPMode, pvpModeName, pvpModeDescription,
                                 applyPvPModeSettings, revertPvPModeSettings

type
  PvPWindow* = ref object
    window*: OSWindow
    networkManager*: NetworkManager
    state*: PvPLobbyState
    isHost*: bool
    hostIP*: string
    hostPort*: int
    nicknameField*: TextField  # Player's chosen nickname
    ipField*: TextField        # Join: the host's address
    portField*: TextField      # Join: the host's port
    errorMessage*: string
    connectionTimeout*: float32
    cursorBlink*: float32      # animation clock (the waiting dots, the spinner)
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
  ModeRowH = 46   ## the host config's Mode row: everything under it sits this much lower
  TaskbarH = 40   ## os_desktop's taskbar: the window stays clear of it
  LobbyField = TextFieldStyle(fontSize: 20, padX: 10, caretWidth: 2, ink: White,
                              caretInk: Color(r: 0, g: 210, b: 255, a: 255),
                              selectInk: Color(r: 100, g: 150, b: 255, a: 128))

proc getLocalIP(): string {.moddable.} =
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

proc censorIP(ip: string): string {.moddable.} =
  if ip == "127.0.0.1":
    return ip
  let parts = ip.split(".")
  if parts.len == 4:
    return "***.***.***.***"
  else:
    return ip

proc getTeamForPlayer(playerIndex: int, numTeams: int): PvPTeam {.moddable.} =
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

proc newPvPWindow*(screenWidth, screenHeight: int): PvPWindow {.moddable.} =
  let windowWidth = 600
  let windowHeight = 670 + ModeRowH # Sized to the hosting-config screen (the tallest state)
  let windowX = (screenWidth - windowWidth) div 2
  let windowY = max(0, (screenHeight - TaskbarH - windowHeight) div 2)
  let localIP = getLocalIP()
  result = PvPWindow(
    window: newOSWindow(t(tkPvPTitle), windowX, windowY, windowWidth, windowHeight,
                       Color(r: 100, g: 200, b: 100, a: 255), resizable = false),
    networkManager: newNetworkManager(),
    state: plsMainMenu,
    isHost: false,
    hostIP: "",
    hostPort: DEFAULT_PORT,
    nicknameField: newTextField(LobbyField, "Player", maxChars = 16),
    ipField: newTextField(LobbyField, "127.0.0.1", allowed = {'0' .. '9', '.'}),
    portField: newTextField(LobbyField, $DEFAULT_PORT, maxChars = 5, allowed = {'0' .. '9'}),
    errorMessage: "",
    connectionTimeout: 0,
    cursorBlink: 0,
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
    teamsEnabled: false,
    numTeams: 2,
    playerTeamAssignments: @[],
    interpolationEnabled: true,
    pvpConfig: defaultPvPConfig()
  )
  result.ipField.focused = true   # what the join screen types into first

proc pvpModeKeys(): seq[string] =
  ## What the host can pick: the game's own rules ("") and every mod's PvP mode.
  result = @[""]
  for m in pvpModes: result.add(m.key)

proc pickPvPMode(pvpWin: PvPWindow, key: string) =
  ## The host picked a mode: the last one's presets go back to the game's
  ## values, then the new one's go in (the host can still change them all).
  var teams = -1
  revertPvPModeSettings(pvpWin.pvpConfig.modMode, pvpWin.pvpConfig, teams)
  if teams == 0: pvpWin.teamsEnabled = false
  pvpWin.pvpConfig.modMode = key
  applyPvPModeSettings(key, pvpWin.pvpConfig, teams)
  if teams == 0:
    pvpWin.teamsEnabled = false
  elif teams > 0:
    pvpWin.teamsEnabled = true
    pvpWin.numTeams = teams

proc startHosting*(pvpWin: PvPWindow) {.moddable.} =
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
                   nickname: string = "Player") {.moddable.} =
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

proc updatePvPWindow*(pvpWin: PvPWindow, dt: float32, getCosmetics: proc(): tuple[skinType, bulletSkinType, shapeType, particleSkinType: int] = nil) {.moddable.} =
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
           nickname: pvpWin.nicknameField.text),
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
    var lobbyLeavers: seq[int] = @[]  # host: pre-renumber indices of clients that left
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
        elif event.packet.kind == ptConnectionAccept and not pvpWin.isHost:
          # The host renumbers the lobby when someone leaves, so this client's
          # player index can change before the match starts.
          pvpWin.connectedPlayers = event.packet.connectedPlayers
          pvpWin.assignedPlayerIndex = event.packet.assignedPlayerIndex
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
            lobbyLeavers.add(event.disconnectPlayerIndex)
            # Rebuilt from the network layer's client list: in the lobby the
            # remaining clients have just been renumbered, so filtering the old
            # entries by index would leave stale numbers behind.
            var newList: seq[ConnectedPlayerInfo] = @[]
            if pvpWin.connectedPlayers.len > 0 and pvpWin.connectedPlayers[0].index == 0:
              newList.add(pvpWin.connectedPlayers[0])
            for client in pvpWin.networkManager.clients:
              newList.add((index: client.playerIndex,
                           skinType: client.skinType,
                           bulletSkinType: client.bulletSkinType,
                           shapeType: client.shapeType,
                           particleSkinType: client.particleSkinType,
                           nickname: if client.nickname.len > 0: client.nickname
                                     else: t("pvp_player_num") & $client.playerIndex))
            pvpWin.connectedPlayers = newList
    # Team picks are stored per player index. In the lobby the network layer
    # closes the gap each leaver left by renumbering the clients after it, so
    # their picks have to shift down with them, or everyone behind a leaver
    # silently changed team. Highest index first: one poll can report several
    # timeouts, all in pre-renumber indices. (Mid-match indices are frozen.)
    if lobbyLeavers.len > 0 and not pvpWin.networkManager.matchStarted:
      lobbyLeavers.sort(Descending)
      for idx in lobbyLeavers:
        if idx > 0 and idx < pvpWin.playerTeamAssignments.len:
          pvpWin.playerTeamAssignments.delete(idx)
          # Keep one entry per slot; the freed last slot gets its default team.
          let slot = pvpWin.playerTeamAssignments.len
          pvpWin.playerTeamAssignments.add((slot mod max(1, pvpWin.numTeams)) + 1)
  else:
    discard

proc resetPvPWindow*(pvpWin: PvPWindow) {.moddable.} =
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
  pvpWin.assignedPlayerIndex = -1
  pvpWin.keepAliveTimer = 0.0
  pvpWin.showIPs = false
  pvpWin.nicknameField.focused = false

proc lobbyFieldBoxes(pvpWin: PvPWindow): tuple[nickname, ip, port: Rectangle] =
  ## The text fields of the screen shown (hosting config: the nickname; join:
  ## all three), from the origin drawPvPWindowContent gets: the input and the
  ## drawing share them.
  let cx = (pvpWin.window.x + WINDOW_BORDER + 20).float32
  let cy = (pvpWin.window.y + TITLE_BAR_HEIGHT + WINDOW_BORDER).float32
  let w = (pvpWin.window.width - WINDOW_BORDER * 2 - 40).float32
  if pvpWin.state == plsJoining:
    result.nickname = Rectangle(x: cx, y: cy + 80, width: w, height: 36)
    result.ip = Rectangle(x: cx, y: cy + 158, width: w, height: 38)
    result.port = Rectangle(x: cx, y: cy + 226, width: w, height: 38)
  else:
    result.nickname = Rectangle(x: cx, y: cy + 82, width: w, height: 32)

proc wantsTextInput*(pvpWin: PvPWindow): bool {.moddable.} =
  ## True while one of the lobby's fields takes the keystrokes.
  not pvpWin.isNil and pvpWin.state in {plsJoining, plsHostingConfig} and
    (typingIn(pvpWin.window, pvpWin.nicknameField) or
     (pvpWin.state == plsJoining and (typingIn(pvpWin.window, pvpWin.ipField) or
                                      typingIn(pvpWin.window, pvpWin.portField))))

# UI helpers

proc drawSectionDivider(x1, x2, y: int) =
  ## A thin accent line that glows in the middle and fades out toward both ends.
  let w = x2 - x1
  let half = w div 2
  let edge = uiLine(0, 200, 255, 0)
  let mid  = uiLine(0, 200, 255, 130)
  drawRectangleGradientH(x1.int32, y.int32, half.int32, 1, edge, mid)
  drawRectangleGradientH((x1 + half).int32, y.int32, (w - half).int32, 1, mid, edge)

proc drawPrimaryButton(bx, by, bw, bh: int, label: string, hovered: bool,
                       baseColor = Color(r: 0, g: 60, b: 80, a: 255),
                       hoverColor = Color(r: 0, g: 95, b: 125, a: 255),
                       fontSize: int32 = 24) =
  drawRectangle(bx.int32, by.int32, bw.int32, bh.int32,
                uiSurface(if hovered: hoverColor else: baseColor))
  # Glossy top highlight for a bit of depth
  drawRectangle((bx + 1).int32, (by + 1).int32, (bw - 2).int32, (bh.float32 * 0.42'f32).int32,
                uiGlow(Color(r: 255, g: 255, b: 255, a: if hovered: 26 else: 14)))
  let borderCol = if hovered: uiLine(0, 220, 255)
                  else: uiLine(70, 95, 115)
  drawRectOutline(Rectangle(x: bx.float32, y: by.float32, width: bw.float32, height: bh.float32),
                     if hovered: 2.0'f32 else: 1.0'f32, borderCol)
  let tw = measureText(label, fontSize)
  drawText(label, (bx + (bw - tw) div 2).int32, (by + (bh - fontSize.int) div 2).int32, fontSize,
           if hovered: uiInk(White) else: uiInk(220, 235, 245))

proc drawDangerButton(bx, by, bw, bh: int, label: string, hovered: bool, fontSize: int32 = 22) =
  let col = if hovered: uiSurface(95, 35, 35) else: uiSurface(50, 22, 22)
  drawRectangle(bx.int32, by.int32, bw.int32, bh.int32, col)
  drawRectangle((bx + 1).int32, (by + 1).int32, (bw - 2).int32, (bh.float32 * 0.42'f32).int32,
                uiGlow(Color(r: 255, g: 255, b: 255, a: if hovered: 22 else: 12)))
  let borderCol = if hovered: uiLine(220, 90, 90) else: uiLine(110, 55, 55)
  drawRectOutline(Rectangle(x: bx.float32, y: by.float32, width: bw.float32, height: bh.float32),
                     if hovered: 2.0'f32 else: 1.0'f32, borderCol)
  let tw = measureText(label, fontSize)
  drawText(label, (bx + (bw - tw) div 2).int32, (by + (bh - fontSize.int) div 2).int32, fontSize,
           if hovered: uiInk(255, 130, 130) else: uiInk(235, 210, 210))

proc drawCheckbox(cbx, cby, cbSize: int, checked, hovered: bool, label: string, labelFontSize: int32 = 17) =
  let rect = Rectangle(x: cbx.float32, y: cby.float32, width: cbSize.float32, height: cbSize.float32)
  let bgColor = if checked: uiSurface(0, 70, 95)
                elif hovered: uiSurface(75, 75, 95)
                else: uiSurface(55, 55, 72)
  drawRectangle(cbx.int32, cby.int32, cbSize.int32, cbSize.int32, bgColor)
  let borderCol = if checked: uiLine(0, 200, 255)
                  elif hovered: uiLine(150, 150, 170)
                  else: uiLine(110, 110, 130)
  drawRectOutline(rect, 1.0'f32, borderCol)
  if checked:
    let chkCol = uiInk(0, 230, 180)
    drawStroke(Vector2(x: (cbx + 5).float32, y: (cby + cbSize div 2).float32),
             Vector2(x: (cbx + cbSize div 2 - 2).float32, y: (cby + cbSize - 5).float32), 3, chkCol)
    drawStroke(Vector2(x: (cbx + cbSize div 2 - 2).float32, y: (cby + cbSize - 5).float32),
             Vector2(x: (cbx + cbSize - 3).float32, y: (cby + 3).float32), 3, chkCol)
  drawText(label, (cbx + cbSize + 10).int32, (cby + (cbSize - labelFontSize.int) div 2).int32,
           labelFontSize, uiInk(225, 225, 235))

proc drawLobbyField(pvpWin: PvPWindow, f: TextField, box: Rectangle) =
  let bgCol = if f.focused: uiSurface(0, 55, 75) else: uiSurface(38, 38, 50)
  drawRectangle(box, bgCol)
  let borderCol = if f.focused: uiLine(0, 210, 255) else: uiLine(80, 80, 100)
  drawRectOutline(box, 2.0'f32, borderCol)
  drawTextField(f, box, hasKeyboard(pvpWin.window))

proc handlePvPWindowInput*(pvpWin: PvPWindow) {.moddable.} =
  ## The lobby's text fields (text_field.nim). Join: a press or Tab /
  ## Shift+Tab picks the nickname, IP or port; hosting config: the nickname,
  ## which a press anywhere else in the window (or Tab) lets go of.
  if not pvpWin.window.visible or pvpWin.window.minimized:
    return
  if pvpWin.state != plsJoining and pvpWin.state != plsHostingConfig:
    return
  let active = hasKeyboard(pvpWin.window)
  let boxes = pvpWin.lobbyFieldBoxes()
  let dt = getFrameTime()
  if pvpWin.state == plsJoining:
    discard updateTextFields([pvpWin.nicknameField, pvpWin.ipField, pvpWin.portField],
                             [boxes.nickname, boxes.ip, boxes.port], dt, active)
  else:
    let nick = pvpWin.nicknameField
    if active and isPointerPressed() and
       not checkCollisionPointRec(getVirtualMousePosition(), boxes.nickname):
      nick.focused = false
    discard updateTextField(nick, boxes.nickname, dt, active)
    if active and isKeyPressed(Tab):
      if nick.focused: nick.focused = false
      else: focusNext([nick])

proc drawPvPWindowContent*(pvpWin: PvPWindow, contentX, contentY, contentWidth, contentHeight: int) {.moddable.} =
  let mousePos = getVirtualMousePosition()

  case pvpWin.state
  of plsMainMenu:
    # Cyan accent bar matching other windows
    drawRectangle(contentX.int32, (contentY + 60).int32, contentWidth.int32, 2,
                  uiSurface(0, 200, 255, 100))

    let titleText = t("pvp_title")
    let titleW = measureText(titleText, 42)
    drawText(titleText,
             (contentX + (contentWidth - titleW) div 2).int32,
             (contentY + 10).int32, 42, uiInk(0, 220, 255))

    let sub = t(tkPvPLocalNetMultiplayer)
    let subW = measureText(sub, 14)
    drawText(sub, (contentX + (contentWidth - subW) div 2).int32,
             (contentY + 68).int32, 14, uiInk(120, 130, 140))

    let btnW = 300
    let btnH = 54
    let btnX = contentX + (contentWidth - btnW) div 2
    let hostY = contentY + 150

    let hostHov = mousePos.x >= btnX.float32 and mousePos.x <= (btnX + btnW).float32 and
                  mousePos.y >= hostY.float32 and mousePos.y <= (hostY + btnH).float32
    drawPrimaryButton(btnX, hostY, btnW, btnH, t("pvp_host_game"), hostHov, fontSize = 24)
    drawText("[ H ]", (btnX + 10).int32, (hostY + (btnH - 16) div 2).int32, 16,
             uiInk(100, 130, 160, 200))

    let joinY = hostY + btnH + 22
    let joinHov = mousePos.x >= btnX.float32 and mousePos.x <= (btnX + btnW).float32 and
                  mousePos.y >= joinY.float32 and mousePos.y <= (joinY + btnH).float32
    drawPrimaryButton(btnX, joinY, btnW, btnH, t("pvp_join_game"), joinHov, fontSize = 24)
    drawText("[ J ]", (btnX + 10).int32, (joinY + (btnH - 16) div 2).int32, 16,
             uiInk(100, 130, 160, 200))

    let info = t(tkPvPShareIPInfo)
    let infoW = measureText(info, 13)
    drawText(info, (contentX + (contentWidth - infoW) div 2).int32,
             (contentY + contentHeight - 30).int32, 13,
             uiInk(100, 110, 120, 200))

  of plsHostingConfig:
    drawRectangle(contentX.int32, (contentY + 46).int32, contentWidth.int32, 1,
                  uiSurface(0, 200, 255, 100))
    let titleText = t("pvp_configure_hosting")
    let titleW = measureText(titleText, 22)
    drawText(titleText, (contentX + (contentWidth - titleW) div 2).int32,
             (contentY + 14).int32, 22, uiInk(0, 220, 255))

    # --- Nickname ---
    drawText(t("pvp_nickname"), (contentX + 20).int32, (contentY + 60).int32, 16, uiInk(White))
    pvpWin.drawLobbyField(pvpWin.nicknameField, pvpWin.lobbyFieldBoxes().nickname)

    drawSectionDivider(contentX + 15, contentX + contentWidth - 15, contentY + 132)

    # --- Max Players (label left, stepper right, on one row) ---
    drawText(t("pvp_max_players"), (contentX + 20).int32, (contentY + 150).int32, 16, uiInk(White))
    let pcY = contentY + 146
    let mBoxX = contentX + contentWidth - 152
    let pBoxX = contentX + contentWidth - 46
    let cntCenterX = (mBoxX + 26 + pBoxX) div 2
    let canMinus = pvpWin.maxPlayers > 2
    let minusHov = mousePos.x >= mBoxX.float32 and mousePos.x <= (mBoxX + 26).float32 and
                   mousePos.y >= pcY.float32 and mousePos.y <= (pcY + 26).float32
    let minusBg = if canMinus and minusHov: uiSurface(80, 80, 100)
                  elif canMinus: uiSurface(50, 50, 65)
                  else: uiSurface(35, 35, 45)
    drawRectangle(mBoxX.int32, pcY.int32, 26, 26, minusBg)
    drawRectOutline(Rectangle(x: mBoxX.float32, y: pcY.float32, width: 26, height: 26),
                       1, if canMinus: uiLine(80, 80, 100) else: uiLine(50, 50, 60))
    let mW = measureText("-", 22)
    drawText("-", (mBoxX + (26 - mW) div 2).int32, (pcY + 2).int32, 22,
             if canMinus: uiInk(White) else: uiInk(80, 80, 80))

    let cntStr = $pvpWin.maxPlayers
    let cntW = measureText(cntStr, 22)
    drawText(cntStr, (cntCenterX - cntW div 2).int32, (pcY + 1).int32, 22, uiInk(0, 200, 255))

    let canPlus = pvpWin.maxPlayers < 16
    let plusHov = mousePos.x >= pBoxX.float32 and mousePos.x <= (pBoxX + 26).float32 and
                  mousePos.y >= pcY.float32 and mousePos.y <= (pcY + 26).float32
    let plusBg = if canPlus and plusHov: uiSurface(80, 80, 100)
                 elif canPlus: uiSurface(50, 50, 65)
                 else: uiSurface(35, 35, 45)
    drawRectangle(pBoxX.int32, pcY.int32, 26, 26, plusBg)
    drawRectOutline(Rectangle(x: pBoxX.float32, y: pcY.float32, width: 26, height: 26),
                       1, if canPlus: uiLine(80, 80, 100) else: uiLine(50, 50, 60))
    let pW = measureText("+", 22)
    drawText("+", (pBoxX + (26 - pW) div 2).int32, (pcY + 2).int32, 22,
             if canPlus: uiInk(White) else: uiInk(80, 80, 80))

    drawSectionDivider(contentX + 15, contentX + contentWidth - 15, contentY + 184)

    # --- Mode: the game's own rules or a mod's PvP mode (register.pvpmode) ---
    if pvpWin.pvpConfig.modMode.len > 0 and findPvPMode(pvpWin.pvpConfig.modMode) < 0:
      pvpWin.pvpConfig.modMode = ""   # its mod is no longer loaded
    let spanish = getLanguage() == Spanish
    let modeKey = pvpWin.pvpConfig.modMode
    let canCycle = pvpModeKeys().len > 1
    let mdY = contentY + 190
    let mlX = contentX + 130
    let mrX = contentX + contentWidth - 46
    drawText(t(tkPvPModeLabel), (contentX + 20).int32, (mdY + 4).int32, 16, uiInk(White))
    for (bx, glyph) in [(mlX, "<"), (mrX, ">")]:
      let hov = canCycle and mousePos.x >= bx.float32 and mousePos.x <= (bx + 26).float32 and
                mousePos.y >= mdY.float32 and mousePos.y <= (mdY + 24).float32
      let bg = if hov: uiSurface(80, 80, 100)
               elif canCycle: uiSurface(50, 50, 65)
               else: uiSurface(35, 35, 45)
      drawRectangle(bx.int32, mdY.int32, 26, 24, bg)
      drawRectOutline(Rectangle(x: bx.float32, y: mdY.float32, width: 26, height: 24),
                      1, if canCycle: uiLine(80, 80, 100) else: uiLine(50, 50, 60))
      let gw = measureText(glyph, 20)
      drawText(glyph, (bx + (26 - gw) div 2).int32, (mdY + 2).int32, 20,
               if canCycle: uiInk(White) else: uiInk(80, 80, 80))
    let modeName = fitWithEllipsis(
      if modeKey.len == 0: t(tkPvPModeStandard) else: pvpModeName(modeKey, spanish),
      (mrX - mlX - 26 - 16).int32, 18)
    let modeNameW = measureText(modeName, 18)
    drawText(modeName, ((mlX + 26 + mrX) div 2 - modeNameW div 2).int32, (mdY + 3).int32, 18,
             if modeKey.len > 0: uiInk(Gold) else: uiInk(0, 200, 255))
    let modeDesc = if modeKey.len == 0: t(tkPvPModeStandardDesc) else: pvpModeDescription(modeKey, spanish)
    if modeDesc.len > 0:
      drawText(fitWithEllipsis(modeDesc, (contentWidth - 40).int32, 12), (contentX + 20).int32,
               (mdY + 26).int32, 12, uiInk(140, 150, 165))

    drawSectionDivider(contentX + 15, contentX + contentWidth - 15, contentY + 184 + ModeRowH)

    # --- Options (two checkboxes side by side) ---
    let cbSize = 20
    let cbX = contentX + 20
    let cbY1 = contentY + 200 + ModeRowH
    let showIPHov = mousePos.x >= cbX.float32 and mousePos.x <= (cbX + cbSize + 150).float32 and
                    mousePos.y >= cbY1.float32 and mousePos.y <= (cbY1 + cbSize).float32
    drawCheckbox(cbX, cbY1, cbSize, pvpWin.showIPs, showIPHov, t("pvp_show_ips"), 15)
    let cbX2 = contentX + contentWidth div 2 + 10
    let interpHov = mousePos.x >= cbX2.float32 and mousePos.x <= (cbX2 + cbSize + 180).float32 and
                    mousePos.y >= cbY1.float32 and mousePos.y <= (cbY1 + cbSize).float32
    drawCheckbox(cbX2, cbY1, cbSize, pvpWin.interpolationEnabled, interpHov, t("pvp_enable_interpolation"), 15)

    drawSectionDivider(contentX + 15, contentX + contentWidth - 15, contentY + 236 + ModeRowH)

    # --- Teams (checkbox left, team-count buttons right when enabled) ---
    let cbY2 = contentY + 252 + ModeRowH
    let teamEnHov = mousePos.x >= cbX.float32 and mousePos.x <= (cbX + cbSize + 150).float32 and
                    mousePos.y >= cbY2.float32 and mousePos.y <= (cbY2 + cbSize).float32
    drawCheckbox(cbX, cbY2, cbSize, pvpWin.teamsEnabled, teamEnHov, t("pvp_enable_teams"), 15)

    if pvpWin.teamsEnabled:
      let tbY = contentY + 248 + ModeRowH
      let tbW = 34
      let tbSp = 44
      let tbStartX = contentX + 240
      for tc in 2..6:
        let tbX = tbStartX + (tc - 2) * tbSp
        let isSel = pvpWin.numTeams == tc
        let tbHov = mousePos.x >= tbX.float32 and mousePos.x <= (tbX + tbW).float32 and
                    mousePos.y >= tbY.float32 and mousePos.y <= (tbY + 28).float32
        let tbBg = if isSel: uiSurface(0, 60, 80)
                   elif tbHov: uiSurface(50, 50, 60)
                   else: uiSurface(40, 40, 50)
        drawRectangle(tbX.int32, tbY.int32, tbW.int32, 28.int32, tbBg)
        drawRectOutline(Rectangle(x: tbX.float32, y: tbY.float32, width: tbW.float32, height: 28),
                           1, if isSel: uiLine(0, 200, 255) else: uiLine(80, 80, 100))
        let tStr = $tc
        let tW = measureText(tStr, 18)
        drawText(tStr, (tbX + (tbW - tW) div 2).int32, (tbY + 5).int32, 18,
                 if isSel: uiInk(Gold) else: uiInk(White))

    # GAME STATS SECTION
    drawSectionDivider(contentX + 15, contentX + contentWidth - 15, contentY + 288 + ModeRowH)
    drawText(t(tkPvPGameStats), (contentX + 20).int32, (contentY + 296 + ModeRowH).int32, 14,
             uiInk(0, 200, 255))

    # Helper: draw a compact stat cell with label, minus, value, plus
    # Layout: 3 columns, 4 rows
    let colW = (contentWidth - 20) div 3
    let baseStatY = contentY + 320 + ModeRowH

    template drawStatCell(cx, cy: int, lbl: string, valStr: string,
                          canDec, canInc: bool) =
      drawText(lbl, (cx + 2).int32, cy.int32, 13,
               uiInk(170, 170, 190))
      let controlY = cy + 15
      # Minus button
      let mBg = if canDec: uiSurface(50, 50, 65)
                else: uiSurface(35, 35, 45)
      drawRectangle((cx).int32, controlY.int32, 22, 22, mBg)
      drawRectOutline(Rectangle(x: cx.float32, y: controlY.float32,
        width: 22, height: 22), 1,
        if canDec: uiLine(80, 80, 110)
        else: uiLine(50, 50, 60))
      let mW = measureText("-", 20)
      drawText("-", (cx + (22 - mW) div 2).int32, (controlY + 1).int32, 20,
               if canDec: uiInk(White) else: uiInk(70, 70, 70))
      # Value
      let vw = measureText(valStr, 16)
      drawText(valStr, (cx + 26 + (colW - 56 - vw) div 2).int32,
               (controlY + 3).int32, 16, uiInk(0, 220, 255))
      # Plus button
      let pBg = if canInc: uiSurface(50, 50, 65)
                else: uiSurface(35, 35, 45)
      drawRectangle((cx + colW - 24).int32, controlY.int32, 22, 22, pBg)
      drawRectOutline(Rectangle(x: (cx + colW - 24).float32,
        y: controlY.float32, width: 22, height: 22), 1,
        if canInc: uiLine(80, 80, 110)
        else: uiLine(50, 50, 60))
      let pW = measureText("+", 20)
      drawText("+", (cx + colW - 24 + (22 - pW) div 2).int32,
               (controlY + 1).int32, 20,
               if canInc: uiInk(White) else: uiInk(70, 70, 70))

    # Row 0: HP | Kill Limit | Respawn Time
    let row0Y = baseStatY
    let row1Y = baseStatY + 46
    drawStatCell(contentX + 10,                row0Y,
      t(tkPvPStatHp),      $pvpWin.pvpConfig.startHp.int,
      pvpWin.pvpConfig.startHp > 1.0, pvpWin.pvpConfig.startHp < 20.0)
    drawStatCell(contentX + 10 + colW,        row0Y,
      t(tkPvPStatKillLimit),
      if pvpWin.pvpConfig.killLimit <= 0: t(tkPvPValueOff)   # a mod mode's "kills don't win"
      else: $pvpWin.pvpConfig.killLimit,
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

    # Arena packages on/off: either button flips it
    drawStatCell(contentX + 10 + colW * 2, row3Y,
      t(tkPvPStatPackages),
      if pvpWin.pvpConfig.pickupsEnabled: t(tkPvPValueOn) else: t(tkPvPValueOff),
      true, true)

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
                  uiSurface(0, 200, 255, 100))
    let titleText = t("pvp_hosting_game")
    let titleW = measureText(titleText, 26)
    drawText(titleText, (contentX + (contentWidth - titleW) div 2).int32,
             (contentY + 14).int32, 26, uiInk(0, 220, 255))

    # Connection info panel
    let panelX = contentX + 20
    let panelY = contentY + 58
    let panelW = contentWidth - 40
    drawRectangle(panelX.int32, panelY.int32, panelW.int32, 56,
                  uiSurface(25, 25, 35))
    drawRectangle(panelX.int32, panelY.int32, panelW.int32, 2,
                  uiSurface(0, 200, 255))
    drawRectOutline(Rectangle(x: panelX.float32, y: panelY.float32,
      width: panelW.float32, height: 56), 1, uiLine(60, 60, 80))

    let localIPDisplay = if pvpWin.showIPs: pvpWin.hostIP else: censorIP(pvpWin.hostIP)
    let ipText = t("pvp_local_ip") & " " & localIPDisplay
    let ipW = measureText(ipText, 16)
    drawText(ipText, (panelX + (panelW - ipW) div 2).int32, (panelY + 8).int32, 16, uiInk(White))

    let portText = t("pvp_port") & " " & $pvpWin.hostPort
    let portW = measureText(portText, 16)
    drawText(portText, (panelX + (panelW - portW) div 2).int32, (panelY + 30).int32, 16,
             uiInk(0, 200, 255, 200))

    let connectedCount = pvpWin.networkManager.getConnectedPlayerCount()
    let mpText = t("pvp_players_count") & " " & $connectedCount & " / " & $pvpWin.maxPlayers
    let mpW = measureText(mpText, 18)
    drawText(mpText, (contentX + (contentWidth - mpW) div 2).int32, (contentY + 126).int32, 18,
             if connectedCount >= pvpWin.maxPlayers: uiInk(0, 200, 255)
             else: uiInk(LightGray))

    drawSectionDivider(contentX + 15, contentX + contentWidth - 15, contentY + 148)

    drawText(t("pvp_connected_players"), (contentX + 20).int32, (contentY + 156).int32, 15, uiInk(LightGray))
    let hostNick = if pvpWin.nicknameField.text.len > 0: pvpWin.nicknameField.text else: "Host"
    drawText("> " & hostNick & t("pvp_you_host"),
             (contentX + 35).int32, (contentY + 176).int32, 15,
             uiInk(255, 200, 50))
    var yOff = 176
    for i, client in pvpWin.networkManager.clients:
      yOff += 20
      let stripe = if i mod 2 == 0: uiSurface(255, 255, 255, 10)
                   else: uiSurface(0, 200, 255, 14)
      drawRectangle((contentX + 16).int32, (contentY + yOff - 3).int32,
        (contentWidth - 32).int32, 20, stripe)
      let nick = if client.nickname.len > 0: client.nickname else: t("pvp_player_num") & $(client.playerIndex + 1)
      let label = if pvpWin.teamsEnabled:
        let pIdx = client.playerIndex
        var pTeam = getTeamForPlayer(pIdx, pvpWin.numTeams)
        if pIdx >= 0 and pIdx < pvpWin.playerTeamAssignments.len:
          pTeam = teamFromInt(pvpWin.playerTeamAssignments[pIdx])
        "> " & nick & "  [" & getTeamName(pTeam) & "]"
      else:
        "> " & nick
      drawText(label, (contentX + 35).int32, (contentY + yOff).int32, 15, uiInk(White))

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
                  uiSurface(0, 200, 255, 100))
    let titleText = t("pvp_join_game_title")
    let titleW = measureText(titleText, 24)
    drawText(titleText, (contentX + (contentWidth - titleW) div 2).int32,
             (contentY + 16).int32, 24, uiInk(0, 220, 255))

    let fX = contentX + 20

    drawText(t("pvp_nickname"), fX.int32, (contentY + 60).int32, 17, uiInk(White))
    let boxes = pvpWin.lobbyFieldBoxes()
    let jnfY = contentY + 80
    let jnfH = 36
    pvpWin.drawLobbyField(pvpWin.nicknameField, boxes.nickname)
    let jnickHint = t("pvp_click_cycle_tabs")
    let jnickHintW = measureText(jnickHint, 12)
    drawText(jnickHint, (contentX + (contentWidth - jnickHintW) div 2).int32,
             (jnfY + jnfH + 4).int32, 12, uiInk(120, 130, 140, 200))

    drawSectionDivider(contentX + 15, contentX + contentWidth - 15, contentY + 130)

    drawText(t("pvp_host_ip"), fX.int32, (contentY + 138).int32, 17, uiInk(White))
    pvpWin.drawLobbyField(pvpWin.ipField, boxes.ip)

    drawText(t("pvp_port"), fX.int32, (contentY + 206).int32, 17, uiInk(White))
    pvpWin.drawLobbyField(pvpWin.portField, boxes.port)

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
             uiInk(0, 220, 255))

    let dots = ".".repeat(((pvpWin.cursorBlink * 2).int mod 4))
    let statusText = t("pvp_please_wait") & dots
    let statusW = measureText(statusText, 18)
    drawText(statusText, (contentX + (contentWidth - statusW) div 2).int32,
             (contentY + contentHeight div 2).int32, 18, uiInk(White))

    let timeoutText = t("pvp_timeout_in") & " " & $pvpWin.connectionTimeout.int & "s"
    let timeoutW = measureText(timeoutText, 16)
    drawText(timeoutText, (contentX + (contentWidth - timeoutW) div 2).int32,
             (contentY + contentHeight div 2 + 30).int32, 16, uiInk(LightGray))

  of plsConnected:
    if pvpWin.isHost:
      drawRectangle(contentX.int32, (contentY + 48).int32, contentWidth.int32, 1,
                    uiSurface(0, 200, 255, 100))
      let titleText = t("pvp_game_lobby")
      let titleW = measureText(titleText, 28)
      drawText(titleText, (contentX + (contentWidth - titleW) div 2).int32,
               (contentY + 12).int32, 28, uiInk(0, 220, 255))

      let playerCount = pvpWin.networkManager.getConnectedPlayerCount()
      let pctText = t("pvp_players_count") & " " & $playerCount & " / " & $pvpWin.maxPlayers
      let pctW = measureText(pctText, 18)
      drawText(pctText, (contentX + (contentWidth - pctW) div 2).int32,
               (contentY + 50).int32, 18,
               if playerCount >= 2: uiInk(0, 200, 255)
               else: uiInk(LightGray))

      drawSectionDivider(contentX + 15, contentX + contentWidth - 15, contentY + 84)

      drawText(t("pvp_connected_label"), (contentX + 20).int32, (contentY + 92).int32, 16, uiInk(LightGray))
      if pvpWin.teamsEnabled:
        drawText(t("pvp_click_badge_team"), (contentX + 20).int32, (contentY + 110).int32, 12,
                 uiInk(120, 130, 140, 200))

      let rowX = contentX + 16
      let rowW = contentWidth - 32
      drawRectangle(rowX.int32, (contentY + 124).int32, rowW.int32, 24,
                    uiSurface(60, 50, 20, 90))
      let hostNick = if pvpWin.nicknameField.text.len > 0: pvpWin.nicknameField.text else: "Host"
      drawText("> " & hostNick & t("pvp_you"),
               (contentX + 30).int32, (contentY + 128).int32, 16,
               uiInk(255, 200, 50))
      if pvpWin.teamsEnabled and pvpWin.playerTeamAssignments.len > 0:
        let hTeam = teamFromInt(pvpWin.playerTeamAssignments[0])
        let hTeamCol = uiInk(getTeamColor(hTeam))
        let hBX = contentX + 270
        let hBY = contentY + 130
        drawRectangle(hBX.int32, hBY.int32, 60, 20, uiSurface(25, 25, 35))
        drawRectOutline(Rectangle(x: hBX.float32, y: hBY.float32, width: 60, height: 20), 1, hTeamCol)
        let hTN = getTeamName(hTeam)
        let hTNW = measureText(hTN, 13)
        drawText(hTN, (hBX + (60 - hTNW) div 2).int32, (hBY + 4).int32, 13, hTeamCol)
        drawText("▲", (hBX + 64).int32, (hBY + 3).int32, 12, uiInk(LightGray))

      # Client rows
      var yOff = 130
      for i, client in pvpWin.networkManager.clients:
        yOff += 24
        let stripe = if i mod 2 == 0: uiSurface(255, 255, 255, 10)
                     else: uiSurface(0, 200, 255, 14)
        drawRectangle((contentX + 16).int32, (contentY + yOff - 4).int32,
          (contentWidth - 32).int32, 24, stripe)
        let nick = if client.nickname.len > 0: client.nickname else: t("pvp_player_num") & $(client.playerIndex + 1)
        if pvpWin.teamsEnabled:
          let pIdx = client.playerIndex
          var pTeam = getTeamForPlayer(pIdx, pvpWin.numTeams)
          if pIdx >= 0 and pIdx < pvpWin.playerTeamAssignments.len:
            pTeam = teamFromInt(pvpWin.playerTeamAssignments[pIdx])
          let pCol = uiInk(getTeamColor(pTeam))
          drawText("> " & nick, (contentX + 30).int32, (contentY + yOff).int32, 17, uiInk(White))
          let pBX = contentX + 270
          let pBY = contentY + yOff
          drawRectangle(pBX.int32, pBY.int32, 60, 20, uiSurface(25, 25, 35))
          drawRectOutline(Rectangle(x: pBX.float32, y: pBY.float32, width: 60, height: 20), 1, pCol)
          let pTN = getTeamName(pTeam)
          let pTNW = measureText(pTN, 13)
          drawText(pTN, (pBX + (60 - pTNW) div 2).int32, (pBY + 4).int32, 13, pCol)
          drawText("▲", (pBX + 64).int32, (pBY + 3).int32, 12, uiInk(LightGray))
        else:
          drawText("> " & nick & "  (P" & $(client.playerIndex + 1) & ")",
                   (contentX + 30).int32, (contentY + yOff).int32, 17, uiInk(White))

      # Start / Cancel buttons
      let startBX = contentX + (contentWidth - 250) div 2
      let startBY = contentY + contentHeight - 118
      let canStart = playerCount >= 2
      let startHov = mousePos.x >= startBX.float32 and mousePos.x <= (startBX + 250).float32 and
                     mousePos.y >= startBY.float32 and mousePos.y <= (startBY + 50).float32
      if canStart:
        drawPrimaryButton(startBX, startBY, 250, 50, t("pvp_start_game"), startHov, fontSize = 22)
      else:
        drawRectangle(startBX.int32, startBY.int32, 250, 50, uiSurface(40, 40, 50))
        drawRectOutline(Rectangle(x: startBX.float32, y: startBY.float32, width: 250, height: 50),
                           1, uiLine(60, 60, 80))
        let ntW = measureText(t("pvp_need_2_players"), 16)
        drawText(t("pvp_need_2_players"),
                 (startBX + (250 - ntW) div 2).int32, (startBY + 17).int32, 16,
                 uiInk(120, 120, 140))

      let cancelBY = startBY + 58
      let cancelHov3 = mousePos.x >= startBX.float32 and mousePos.x <= (startBX + 250).float32 and
                       mousePos.y >= cancelBY.float32 and mousePos.y <= (cancelBY + 42).float32
      drawDangerButton(startBX, cancelBY, 250, 42, t("general_cancel"), cancelHov3, 18)

    else:
      # Client waiting view
      drawRectangle(contentX.int32, (contentY + 48).int32, contentWidth.int32, 1,
                    uiSurface(0, 200, 255, 100))
      let titleText = t("pvp_connected")
      let titleW = measureText(titleText, 28)
      drawText(titleText, (contentX + (contentWidth - titleW) div 2).int32,
               (contentY + 12).int32, 28, uiInk(0, 220, 255))

      drawSectionDivider(contentX + 15, contentX + contentWidth - 15, contentY + 60)

      if pvpWin.connectedPlayers.len > 0:
        drawText(t("pvp_players_in_lobby"), (contentX + 20).int32, (contentY + 70).int32, 17, uiInk(White))
        var pY = 0
        for cp in pvpWin.connectedPlayers:
          let nick = if cp.nickname.len > 0: cp.nickname else: t("pvp_player_num") & $(cp.index + 1)
          let isMe = cp.index == pvpWin.assignedPlayerIndex
          let label = "> " & nick & (if isMe: t("pvp_you") else: "  (P" & $(cp.index + 1) & ")")
          drawText(label, (contentX + 35).int32, (contentY + 96 + pY).int32, 17,
                  if isMe: uiInk(Gold) else: uiInk(White))
          pY += 24

      let waitText = t("pvp_waiting_for_host")
      let waitW = measureText(waitText, 18)
      drawText(waitText, (contentX + (contentWidth - waitW) div 2).int32,
               (contentY + contentHeight - 64).int32, 18, uiInk(LightGray))
      let spinStr = if ((pvpWin.cursorBlink * 2).int mod 2) == 0: "◉  ◎  ◉  ◎" else: "◎  ◉  ◎  ◉"
      let spinW = measureText(spinStr, 14)
      drawText(spinStr, (contentX + (contentWidth - spinW) div 2).int32,
               (contentY + contentHeight - 38).int32, 14,
               uiInk(0, 180, 255, 160))

  of plsError:
    drawRectangle(contentX.int32, (contentY + 54).int32, contentWidth.int32, 1,
                  uiSurface(180, 50, 50))
    let titleText = t("pvp_connection_error")
    let titleW = measureText(titleText, 26)
    drawText(titleText, (contentX + (contentWidth - titleW) div 2).int32,
             (contentY + 16).int32, 26, uiInk(255, 100, 100))

    # Error panel
    let panelX = contentX + 20
    let panelY = contentY + 68
    let panelW = contentWidth - 40
    let panelH = 80
    drawRectangle(panelX.int32, panelY.int32, panelW.int32, panelH.int32,
                  uiSurface(30, 22, 26))
    drawRectangle(panelX.int32, panelY.int32, panelW.int32, 2,
                  uiSurface(180, 50, 50))
    drawRectOutline(Rectangle(x: panelX.float32, y: panelY.float32,
      width: panelW.float32, height: panelH.float32), 1,
      uiLine(80, 40, 40))
    let errW = measureText(pvpWin.errorMessage, 16)
    drawText(pvpWin.errorMessage,
             (panelX + (panelW - errW) div 2).int32,
             (panelY + (panelH - 16) div 2).int32, 16, uiInk(White))

    let backBX = contentX + (contentWidth - 200) div 2
    let backBY = contentY + contentHeight - 90
    let backHov2 = mousePos.x >= backBX.float32 and mousePos.x <= (backBX + 200).float32 and
                   mousePos.y >= backBY.float32 and mousePos.y <= (backBY + 48).float32
    drawDangerButton(backBX, backBY, 200, 48, t("pvp_back"), backHov2, 22)

proc handlePvPWindowClick*(pvpWin: PvPWindow, contentX, contentY, contentWidth, contentHeight: int): int {.moddable.} =
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
    # (The nickname field takes its own presses: handlePvPWindowInput.)
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

    # Mode arrows: cycle the game's own rules and every mod PvP mode
    let modeKeys = pvpModeKeys()
    let mdY = contentY + 190
    if modeKeys.len > 1 and mousePos.y >= mdY.float32 and mousePos.y <= (mdY + 24).float32:
      let mlX = contentX + 130
      let mrX = contentX + contentWidth - 46
      let step = if mousePos.x >= mlX.float32 and mousePos.x <= (mlX + 26).float32: -1
                 elif mousePos.x >= mrX.float32 and mousePos.x <= (mrX + 26).float32: 1
                 else: 0
      if step != 0:
        let cur = max(0, modeKeys.find(pvpWin.pvpConfig.modMode))
        pvpWin.pickPvPMode(modeKeys[(cur + step + modeKeys.len) mod modeKeys.len])
        return 0

    let cbX = contentX + 20
    let cbSize = 20
    let cbX2 = contentX + contentWidth div 2 + 10
    if mousePos.x >= cbX.float32 and mousePos.x <= (cbX + cbSize + 150).float32 and
       mousePos.y >= (contentY + 200 + ModeRowH).float32 and mousePos.y <= (contentY + 220 + ModeRowH).float32:
      pvpWin.showIPs = not pvpWin.showIPs
      return 0
    if mousePos.x >= cbX2.float32 and mousePos.x <= (cbX2 + cbSize + 180).float32 and
       mousePos.y >= (contentY + 200 + ModeRowH).float32 and mousePos.y <= (contentY + 220 + ModeRowH).float32:
      pvpWin.interpolationEnabled = not pvpWin.interpolationEnabled
      return 0
    if mousePos.x >= cbX.float32 and mousePos.x <= (cbX + cbSize + 150).float32 and
       mousePos.y >= (contentY + 252 + ModeRowH).float32 and mousePos.y <= (contentY + 272 + ModeRowH).float32:
      pvpWin.teamsEnabled = not pvpWin.teamsEnabled
      return 0

    if pvpWin.teamsEnabled:
      let tbY = contentY + 248 + ModeRowH
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
    let row0Yc = contentY + 320 + ModeRowH
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
    # (Off, a mod mode's 0, only steps up: "-" must not turn it into 1)
    statClickInt(contentX + 10 + colWc,  row0Yc, pvpWin.pvpConfig.killLimit,   1,
                 (if pvpWin.pvpConfig.killLimit <= 0: 0 else: 1), 30)
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

    # Packages toggle, col 2 of the same row: - and + both flip it
    let pkgColX = contentX + 10 + colWc * 2
    if my >= ctrlY3.float32 and my <= (ctrlY3 + 22).float32 and
       ((mx >= pkgColX.float32 and mx <= (pkgColX + 22).float32) or
        (mx >= (pkgColX + colWc - 24).float32 and mx <= (pkgColX + colWc - 2).float32)):
      pvpWin.pvpConfig.pickupsEnabled = not pvpWin.pvpConfig.pickupsEnabled

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
    # (The three fields take their own presses: handlePvPWindowInput.)
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
