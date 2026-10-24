## OS-Themed Co-op Window (CO-OP.exe)
##
## The lobby of a co-op run over the local network (src/coop/coop_session.nim).
## Before a session: a name, a port, then host (2-4 players) or join an
## address. In one: the seats with their ready flags and starter kits; the
## host picks the run (a mode, a mod mode, the roguelite's Heat) and starts it
## once everyone is ready, the others ready up. main.nim polls the session and
## builds the run when it starts; after it, the window shows the lobby again.
##
## The fields are text_field.nim's; while one is focused the window claims the
## keyboard through `wantsTextInput`.

import raylib, std/[strutils, net]
import ../modding/mod_patch_core
import ../modding/mod_hooks
import ../draw_prims
import os_window, ui_helpers, ../localization, ../render_context
import ui_theme, ../utils, text_field
import ../types, ../settings, ../save_system
import ../network/network_types
import ../coop/coop_session

type
  ModeChoice* = object
    mode*: GameMode
    modKey*: string    ## a mod game mode's key, "" for the built-in mode
    label: string
    locked: bool

  CoopWindow* = ref object
    window*: OSWindow
    nickname: TextField
    port: TextField
    address: TextField
    maxPlayers: int
    modeIndex: int     ## into modeChoices()
    heat: int
    kit: int
    highestHeat*: int  ## the roguelite Heat this profile reached (main.nim sets it)
    recursionBonus*: float32  ## this profile's banked Recursion (main.nim sets it; sent when ready)
    recursionLevel*: int32
    localIp: string
    status: string
    statusTimer: float32
    hover: int

  CoopLayout = object
    intro: Rectangle
    nameField, portField: Rectangle
    hostBox, joinBox: Rectangle
    seats: array[2 .. MaxCoopPlayers, Rectangle]
    hostButton, joinButton: Rectangle
    addressField: Rectangle
    roster: Rectangle
    runBox: Rectangle
    modePrev, modeNext: Rectangle
    heatMinus, heatPlus: Rectangle
    kits: array[3, Rectangle]
    primary, leave: Rectangle
    statusY: float32
    note: Rectangle

const
  COOP_WINDOW_WIDTH = 620
  COOP_WINDOW_HEIGHT = 560
  FIELD_FONT = 15'i32
  STATUS_SECONDS = 6.0'f32
  ROW_H = 30'f32

  # Hover ids
  HoverHost = 1
  HoverJoin = 2
  HoverModePrev = 3
  HoverModeNext = 4
  HoverHeatMinus = 5
  HoverHeatPlus = 6
  HoverPrimary = 7
  HoverLeave = 8
  HoverSeats = 10     # + 2..4
  HoverKits = 20      # + 0..2

template ColAccent: Color = uiInk(120, 235, 120)
template ColTitle: Color = uiInk(235, 245, 255)
template ColBody: Color = uiInk(205, 212, 222)
template ColMuted: Color = uiInk(150, 160, 175)
template ColHint: Color = uiInk(110, 120, 135)
template ColPanelBg: Color = uiSurface(10, 12, 18)
template ColFieldBg: Color = uiSurface(18, 22, 32)
template ColOk: Color = uiInk(120, 230, 150)
template ColWarn: Color = uiInk(255, 190, 90)

proc localAddress(): string =
  ## This machine's LAN address: the source of a route out (no packet is sent).
  result = "127.0.0.1"
  try:
    let sock = newSocket(Domain.AF_INET, SockType.SOCK_DGRAM, Protocol.IPPROTO_UDP)
    try:
      sock.connect("8.8.8.8", Port(80))
      let (ip, _) = sock.getLocalAddr()
      if ip.len > 0 and ip != "0.0.0.0": result = ip
    except CatchableError:
      discard
    sock.close()
  except CatchableError:
    discard

proc spanish(): bool = not globalSettings.isNil and globalSettings.language == "spanish"

proc modeChoices*(): seq[ModeChoice] {.moddable.} =
  ## What a co-op run can be: the PvE modes, then the mod game modes (but those
  ## registered with coop = false). Locked as on the desktop.
  let s = globalSettings
  let survivalOpen = not s.isNil and s.survivalUnlocked
  let rogueliteOpen = not s.isNil and s.rogueliteUnlocked
  result.add ModeChoice(mode: gmWaveBased, label: t(tkGameModeWaveBased))
  result.add ModeChoice(mode: gmTimeSurvival, label: t(tkGameModeTimeSurvival), locked: not survivalOpen)
  result.add ModeChoice(mode: gmRoguelite, label: t("gamemode_roguelite_name"), locked: not rogueliteOpen)
  result.add ModeChoice(mode: gmSandbox, label: t(tkGameModeSandbox))
  for m in modModes:
    if not m.coop or m.base notin {gmWaveBased, gmTimeSurvival, gmRoguelite}: continue
    let locked = (m.base == gmTimeSurvival and not survivalOpen) or
                 (m.base == gmRoguelite and not rogueliteOpen)
    result.add ModeChoice(mode: m.base, modKey: m.key, label: modModeName(m.key, spanish()),
                          locked: locked)

proc choiceLabel(config: CoopRunConfigNet): string =
  ## The run a lobby shows (a client may not have the host's mod mode's name).
  if config.modMode.len > 0:
    let i = findModMode(config.modMode)
    return if i >= 0: modModeName(config.modMode, spanish()) else: config.modMode
  case GameMode(clamp(config.mode, 0, ord(high(GameMode))))
  of gmTimeSurvival: t(tkGameModeTimeSurvival)
  of gmRoguelite: t("gamemode_roguelite_name")
  of gmSandbox: t(tkGameModeSandbox)
  else: t(tkGameModeWaveBased)

proc kitName(k: int): string =
  case k
  of 1: t("roguelite_kit_bulwark")
  of 2: t("roguelite_kit_arcanist")
  else: t("roguelite_kit_operator")

proc newCoopWindow*(screenWidth, screenHeight: int): CoopWindow {.moddable.} =
  let osWin = newOSWindow(
    t(tkCoopWindowTitle),
    (screenWidth - COOP_WINDOW_WIDTH) div 2,
    (screenHeight - COOP_WINDOW_HEIGHT) div 2,
    COOP_WINDOW_WIDTH, COOP_WINDOW_HEIGHT,
    ColAccent,
    resizable = false
  )
  let style = fieldStyle(FIELD_FONT, Color(r: 235, g: 245, b: 255, a: 255),
                         Color(r: 120, g: 235, b: 120, a: 255))
  result = CoopWindow(window: osWin, maxPlayers: 2, heat: 1, hover: -1, highestHeat: 1,
                      nickname: newTextField(style, maxChars = 16),
                      port: newTextField(style, maxChars = 5, allowed = Digits),
                      address: newTextField(style, maxChars = 64))

proc resetCoopView*(cw: CoopWindow) {.moddable.} =
  ## Called on every open: the saved name, port and address, and the title in
  ## the current language.
  cw.window.title = t(tkCoopWindowTitle)
  let s = globalSettings
  if not s.isNil:
    if cw.nickname.text.len == 0: cw.nickname.setText(s.pvpNickname)
    if cw.port.text.len == 0:
      cw.port.setText($(if s.coopPort in 1 .. 65535: s.coopPort else: CoopDefaultPort))
    if cw.address.text.len == 0: cw.address.setText(s.coopLastHost)
  if cw.localIp.len == 0: cw.localIp = localAddress()
  cw.status = ""
  cw.statusTimer = 0

proc wantsTextInput*(cw: CoopWindow): bool {.moddable.} =
  typingIn(cw.window, cw.nickname) or typingIn(cw.window, cw.port) or
    typingIn(cw.window, cw.address)

proc layout(cw: CoopWindow): CoopLayout =
  let x = (cw.window.x + WINDOW_PADDING + 18).float32
  let w = (cw.window.width - WINDOW_PADDING * 2 - 36).float32
  var y = (cw.window.y + TITLE_BAR_HEIGHT + WINDOW_PADDING + 14).float32
  result.intro = Rectangle(x: x, y: y, width: w, height: 38)
  y += 50
  # Before a session: name + port, then the host and join boxes.
  result.nameField = Rectangle(x: x, y: y + 19, width: w - 130, height: 30)
  result.portField = Rectangle(x: x + w - 116, y: y + 19, width: 116, height: 30)
  let boxY = y + 66
  let boxW = (w - 14) / 2
  result.hostBox = Rectangle(x: x, y: boxY, width: boxW, height: 190)
  result.joinBox = Rectangle(x: x + boxW + 14, y: boxY, width: boxW, height: 190)
  for n in 2 .. MaxCoopPlayers:
    result.seats[n] = Rectangle(x: x + 14 + (n - 2).float32 * 56, y: boxY + 68,
                                width: 48, height: 28)
  result.hostButton = Rectangle(x: x + 14, y: boxY + 140, width: boxW - 28, height: 34)
  result.addressField = Rectangle(x: result.joinBox.x + 14, y: boxY + 66, width: boxW - 28, height: 30)
  result.joinButton = Rectangle(x: result.joinBox.x + 14, y: boxY + 140, width: boxW - 28, height: 34)
  # In a session: the seats, then the run.
  result.roster = Rectangle(x: x, y: y, width: w, height: ROW_H * MaxCoopPlayers.float32 + 34)
  let runY = y + result.roster.height + 14
  result.runBox = Rectangle(x: x, y: runY, width: w, height: 128)
  result.modePrev = Rectangle(x: x + 110, y: runY + 30, width: 30, height: 28)
  result.modeNext = Rectangle(x: x + w - 44, y: runY + 30, width: 30, height: 28)
  result.heatMinus = Rectangle(x: x + 110, y: runY + 64, width: 30, height: 26)
  result.heatPlus = Rectangle(x: x + 190, y: runY + 64, width: 30, height: 26)
  for k in 0 .. 2:
    result.kits[k] = Rectangle(x: x + 110 + k.float32 * 128, y: runY + 96, width: 120, height: 26)
  let btnY = runY + result.runBox.height + 16
  result.primary = Rectangle(x: x, y: btnY, width: (w - 14) * 0.6, height: 36)
  result.leave = Rectangle(x: x + (w - 14) * 0.6 + 14, y: btnY, width: (w - 14) * 0.4, height: 36)
  result.statusY = btnY + 46
  result.note = Rectangle(x: x, y: (cw.window.y + cw.window.height - WINDOW_PADDING - 44).float32,
                          width: w, height: 32)

proc setStatus(cw: CoopWindow, text: string) =
  cw.status = text
  cw.statusTimer = STATUS_SECONDS

proc myMember(cw: CoopWindow): CoopMemberNet =
  let s = globalSettings
  result.nickname = cw.nickname.text.strip
  if result.nickname.len == 0: result.nickname = "Player"
  if not s.isNil:
    result.skinType = int32(s.playerSkin)
    result.bulletSkinType = int32(s.bulletSkin)
    result.shapeType = int32(s.playerShape)
    result.particleSkinType = int32(s.particleEffect)
    result.bulletShape = int32(s.bulletShape)
  result.starterKit = int32(cw.kit)

proc portValue(cw: CoopWindow): int =
  try: parseInt(cw.port.text.strip)
  except ValueError: 0

proc currentConfig(cw: CoopWindow): CoopRunConfigNet =
  let choices = modeChoices()
  let c = choices[clamp(cw.modeIndex, 0, choices.high)]
  result.mode = int32(ord(c.mode))
  result.modMode = c.modKey
  result.difficulty = int32(ord(currentDifficulty))
  result.heat = int32(clamp(cw.heat, 1, max(1, cw.highestHeat)))

proc rememberFields(cw: CoopWindow, host: string) =
  let s = globalSettings
  if s.isNil: return
  s.pvpNickname = cw.myMember.nickname
  s.coopPort = cw.portValue
  if host.len > 0: s.coopLastHost = host
  discard saveSettings(s)

proc startHosting(cw: CoopWindow) =
  let port = cw.portValue
  if port notin 1 .. 65535:
    cw.setStatus(t(tkCoopBadPort))
    return
  cw.rememberFields("")
  try:
    discard hostCoop(port, cw.maxPlayers, cw.myMember, cw.currentConfig,
                     profileUid(activeProfileSlot))
  except CatchableError:
    cw.setStatus(t(tkCoopHostFailed).replace("$1", $port))

proc startJoining(cw: CoopWindow) =
  let port = cw.portValue
  let host = cw.address.text.strip
  if port notin 1 .. 65535:
    cw.setStatus(t(tkCoopBadPort))
    return
  if host.len == 0:
    cw.setStatus(t(tkCoopNoAddress))
    focusField(cw.address, [cw.nickname, cw.port, cw.address])
    return
  cw.rememberFields(host)
  try:
    discard joinCoop(host, port, cw.myMember, profileUid(activeProfileSlot))
  except CatchableError:
    cw.setStatus(t(tkCoopError).replace("$1", getCurrentExceptionMsg()))

proc leaveSession(cw: CoopWindow) =
  if not activeCoop.isNil:
    activeCoop.closeCoop()

# ---------------------------------------------------------------------------
# Update
# ---------------------------------------------------------------------------

proc updateCoopWindow*(cw: CoopWindow, dt: float32, screenWidth, screenHeight: int,
                       allWindows: openArray[OSWindow]) {.moddable.} =
  updateOSWindow(cw.window, dt)
  if not cw.window.visible:
    return
  if handleOSWindowInput(cw.window, screenWidth, screenHeight, allWindows):
    cw.window.visible = false   # (closing the window keeps the session)
    return
  if cw.statusTimer > 0: cw.statusTimer -= dt
  cw.hover = -1
  if cw.window.minimized or not cw.window.focused:
    return

  let s = activeCoop
  let lo = layout(cw)
  let mp = getVirtualMousePosition()
  let pressed = isPointerPressed() and not cw.window.dragging
  template hit(r: Rectangle, id: int) =
    if checkCollisionPointRec(mp, r): cw.hover = id

  if s.isNil:
    let fields = [cw.nickname, cw.port, cw.address]
    let typed = updateTextFields(fields, [lo.nameField, lo.portField, lo.addressField], dt, true)
    for n in 2 .. MaxCoopPlayers: hit(lo.seats[n], HoverSeats + n)
    hit(lo.hostButton, HoverHost)
    hit(lo.joinButton, HoverJoin)
    if typed.submitted and cw.address.focused: cw.startJoining()
    if pressed and not typed.clicked:
      if cw.hover in HoverSeats + 2 .. HoverSeats + MaxCoopPlayers:
        cw.maxPlayers = cw.hover - HoverSeats
      elif cw.hover == HoverHost: cw.startHosting()
      elif cw.hover == HoverJoin: cw.startJoining()
      else:
        for f in fields: f.focused = false
    return

  # A session.
  for f in [cw.nickname, cw.port, cw.address]: f.focused = false
  case s.phase
  of cpJoining, cpError:
    hit(lo.leave, HoverLeave)
    if pressed and cw.hover == HoverLeave:
      if s.phase == cpError: cw.setStatus(s.errorText)
      cw.leaveSession()
    return
  of cpRunning, cpEnding, cpIdle:
    return
  of cpHostLobby, cpClientLobby, cpEnded:
    discard

  let roguelite = GameMode(clamp(s.config.mode, 0, ord(high(GameMode)))) == gmRoguelite
  if s.isHost:
    hit(lo.modePrev, HoverModePrev)
    hit(lo.modeNext, HoverModeNext)
    if roguelite:
      hit(lo.heatMinus, HoverHeatMinus)
      hit(lo.heatPlus, HoverHeatPlus)
  if roguelite:
    for k in 0 .. 2: hit(lo.kits[k], HoverKits + k)
  hit(lo.primary, HoverPrimary)
  hit(lo.leave, HoverLeave)
  if not pressed: return
  let choices = modeChoices()
  case cw.hover
  of HoverModePrev, HoverModeNext:
    # Step to the next mode this profile has unlocked.
    let step = if cw.hover == HoverModeNext: 1 else: -1
    var i = cw.modeIndex
    for _ in 0 ..< choices.len:
      i = (i + step + choices.len) mod choices.len
      if not choices[i].locked: break
    cw.modeIndex = i
    s.setLobbyConfig(cw.currentConfig)
  of HoverHeatMinus, HoverHeatPlus:
    cw.heat = clamp(cw.heat + (if cw.hover == HoverHeatPlus: 1 else: -1), 1, max(1, cw.highestHeat))
    s.setLobbyConfig(cw.currentConfig)
  of HoverKits .. HoverKits + 2:
    cw.kit = cw.hover - HoverKits
    s.setReady(s.readyWanted or s.isHost, int32(cw.kit), cw.recursionBonus, cw.recursionLevel)
  of HoverPrimary:
    if s.isHost:
      if s.phase == cpHostLobby and s.readyToStart:
        s.config = cw.currentConfig
        s.startCoopRun()
        cw.window.visible = false
    elif s.phase == cpClientLobby:
      s.setReady(not s.readyWanted, int32(cw.kit), cw.recursionBonus, cw.recursionLevel)
  of HoverLeave:
    cw.leaveSession()
  else: discard

# ---------------------------------------------------------------------------
# Draw
# ---------------------------------------------------------------------------

proc drawField(r: Rectangle, active: bool) =
  drawRectangle(r.x.int32, r.y.int32, r.width.int32, r.height.int32, ColFieldBg)
  drawRectOutline(r, (if active: 2.0 else: 1.0), if active: ColAccent else: uiLine(70, 80, 100))

proc drawButton(r: Rectangle, label: string, fill: Color, hovered: bool, enabled = true) =
  ## `fill` is the stock colour; the button draws it in the theme.
  var f = if not enabled: Color(r: 40, g: 44, b: 52, a: 255)
          elif hovered: Color(r: min(255, fill.r.int + 28).uint8, g: min(255, fill.g.int + 28).uint8,
                              b: min(255, fill.b.int + 28).uint8, a: 255)
          else: fill
  drawRectangle(r.x.int32, r.y.int32, r.width.int32, r.height.int32, uiSurface(f))
  drawRectOutline(r, (if hovered and enabled: 2.0 else: 1.0),
                     uiLine(Color(r: 255, g: 255, b: 255, a: if hovered and enabled: 210 else: 90)))
  drawCenteredTextFit(label, r.x.int32 + 5, r.y.int32 + (r.height.int32 - 15) div 2,
                      r.width.int32 - 10, 15, if enabled: uiInk(White) else: ColMuted)

proc drawPill(r: Rectangle, label: string, selected, hovered: bool) =
  let bg = if selected: uiSurface(30, 70, 40) elif hovered: uiSurface(30, 36, 50) else: ColFieldBg
  drawRectangle(r.x.int32, r.y.int32, r.width.int32, r.height.int32, bg)
  drawRectOutline(r, (if selected: 2.0 else: 1.0), if selected: ColAccent else: uiLine(70, 80, 100))
  drawCenteredTextFit(label, r.x.int32 + 3, r.y.int32 + (r.height.int32 - 14) div 2,
                      r.width.int32 - 6, 14, if selected: ColTitle else: ColMuted)

proc drawWrapped(text: string, r: Rectangle, size: int32, color: Color) =
  let fs = bestWrapFontSize(text, r.width.int32, size, 2)
  var y = r.y.int32
  for line in wrapTextLines(text, r.width.int32, fs):
    drawText(line, r.x.int32, y, fs, color)
    y += fs + 3

proc drawRoster(cw: CoopWindow, s: CoopSession, r: Rectangle) =
  drawRectangle(r.x.int32, r.y.int32, r.width.int32, r.height.int32, ColFieldBg)
  drawRectOutline(r, 1, uiLine(70, 80, 100))
  let header = if s.isHost: t(tkCoopHostingOn).replace("$1", cw.localIp & ":" & cw.port.text)
               else: t(tkCoopConnectedTo).replace("$1", s.memberName(0))
  drawTextFit(header, r.x.int32 + 10, r.y.int32 + 8, r.width.int32 - 20, 14, ColAccent)
  let roguelite = GameMode(clamp(s.config.mode, 0, ord(high(GameMode)))) == gmRoguelite
  for k in 0 ..< max(s.maxPlayers, s.members.len):
    let y = r.y + 30 + k.float32 * ROW_H
    var member: CoopMemberNet
    var seated = false
    for m in s.members:
      if m.slot == int32(k): member = m; seated = true
    let rowY = y.int32 + 6
    if not seated:
      drawText(t(tkCoopEmptySeat), r.x.int32 + 34, rowY, 14, ColHint)
      continue
    drawDisc(Vector2(x: r.x + 18, y: y + 13), 5, if member.ready: ColOk else: ColWarn)
    var name = member.nickname
    if k == 0: name.add "  [" & t(tkCoopHostTag) & "]"
    if int32(k) == s.mySlot: name.add "  (" & t(tkCoopYouTag) & ")"
    drawTextFit(name, r.x.int32 + 34, rowY, (r.width * 0.55).int32, 14, ColTitle)
    var right = if member.ready: t(tkCoopReady) else: t(tkCoopNotReady)
    if roguelite: right = kitName(member.starterKit) & "  -  " & right
    let rw = measureText(right, 13)
    drawText(right, r.x.int32 + r.width.int32 - rw - 12, rowY + 1, 13,
             if member.ready: ColOk else: ColMuted)

proc drawCoopWindow*(cw: CoopWindow) {.moddable.} =
  if not cw.window.visible:
    return
  drawWindowChrome(cw.window)
  if cw.window.minimized:
    return
  let cx = cw.window.x + WINDOW_PADDING
  let cy = cw.window.y + TITLE_BAR_HEIGHT + WINDOW_PADDING
  let cwid = cw.window.width - WINDOW_PADDING * 2
  let ch = cw.window.height - TITLE_BAR_HEIGHT - WINDOW_PADDING * 2
  drawRectangle(cx.int32, cy.int32, cwid.int32, ch.int32, ColPanelBg)
  drawRectOutline(Rectangle(x: cx.float32, y: cy.float32, width: cwid.float32, height: ch.float32),
                  1, withAlpha(ColAccent, 200))
  let lo = layout(cw)
  let typing = hasKeyboard(cw.window)
  let s = activeCoop

  if s.isNil:
    drawWrapped(t(tkCoopIntro), lo.intro, 14, ColBody)
    drawText(t(tkCoopNickname), lo.nameField.x.int32, (lo.nameField.y - 19).int32, 14, ColAccent)
    drawText(t(tkCoopPort), lo.portField.x.int32, (lo.portField.y - 19).int32, 14, ColAccent)
    drawField(lo.nameField, cw.nickname.focused)
    drawTextField(cw.nickname, lo.nameField, typing)
    drawField(lo.portField, cw.port.focused)
    drawTextField(cw.port, lo.portField, typing)
    for (box, title) in [(lo.hostBox, t(tkCoopHostTitle)), (lo.joinBox, t(tkCoopJoinTitle))]:
      drawRectangle(box.x.int32, box.y.int32, box.width.int32, box.height.int32, ColFieldBg)
      drawRectOutline(box, 1, uiLine(70, 80, 100))
      drawText(title, box.x.int32 + 14, box.y.int32 + 12, 16, ColTitle)
    drawText(t(tkCoopPlayers), lo.hostBox.x.int32 + 14, lo.hostBox.y.int32 + 46, 13, ColMuted)
    for n in 2 .. MaxCoopPlayers:
      drawPill(lo.seats[n], $n, cw.maxPlayers == n, cw.hover == HoverSeats + n)
    drawTextFit(t(tkCoopYourAddress).replace("$1", cw.localIp), lo.hostBox.x.int32 + 14,
                lo.hostBox.y.int32 + 108, lo.hostBox.width.int32 - 28, 13, ColMuted)
    drawButton(lo.hostButton, t(tkCoopHostButton), Color(r: 46, g: 120, b: 70, a: 255),
               cw.hover == HoverHost)
    drawText(t(tkCoopAddress), lo.addressField.x.int32, lo.joinBox.y.int32 + 46, 13, ColMuted)
    drawField(lo.addressField, cw.address.focused)
    if cw.address.text.len == 0 and not cw.address.focused:
      drawText("192.168.1.20", lo.addressField.x.int32 + 10, lo.addressField.y.int32 + 8,
               FIELD_FONT, ColHint)
    drawTextField(cw.address, lo.addressField, typing)
    drawButton(lo.joinButton, t(tkCoopJoinButton), Color(r: 40, g: 64, b: 104, a: 255),
               cw.hover == HoverJoin)
  else:
    case s.phase
    of cpJoining, cpError:
      let text = if s.phase == cpError: t(tkCoopError).replace("$1", s.errorText)
                 else: t(tkCoopConnecting).replace("$1", cw.address.text.strip)
      drawWrapped(text, lo.intro, 16, if s.phase == cpError: ColWarn else: ColBody)
      drawButton(lo.leave, (if s.phase == cpError: t(tkCoopBack) else: t(tkCoopLeaveButton)),
                 Color(r: 110, g: 50, b: 50, a: 255), cw.hover == HoverLeave)
    of cpRunning, cpEnding, cpIdle:
      drawWrapped(t(tkCoopSyncing), lo.intro, 16, ColBody)
    of cpHostLobby, cpClientLobby, cpEnded:
      cw.drawRoster(s, lo.roster)
      let rb = lo.runBox
      drawRectangle(rb.x.int32, rb.y.int32, rb.width.int32, rb.height.int32, ColFieldBg)
      drawRectOutline(rb, 1, uiLine(70, 80, 100))
      drawText(t(tkCoopRunTitle), rb.x.int32 + 10, rb.y.int32 + 8, 14, ColAccent)
      drawText(t(tkCoopMode), rb.x.int32 + 14, rb.y.int32 + 36, 14, ColMuted)
      let modeBox = Rectangle(x: lo.modePrev.x + 36, y: lo.modePrev.y,
                              width: lo.modeNext.x - lo.modePrev.x - 42, height: 28)
      drawCenteredTextFit(choiceLabel(s.config), modeBox.x.int32, modeBox.y.int32 + 6,
                          modeBox.width.int32, 15, ColTitle)
      if s.isHost:
        drawButton(lo.modePrev, "<", Color(r: 40, g: 64, b: 104, a: 255), cw.hover == HoverModePrev)
        drawButton(lo.modeNext, ">", Color(r: 40, g: 64, b: 104, a: 255), cw.hover == HoverModeNext)
      let roguelite = GameMode(clamp(s.config.mode, 0, ord(high(GameMode)))) == gmRoguelite
      if roguelite:
        drawText(t("roguelite_heat"), rb.x.int32 + 14, rb.y.int32 + 68, 14, ColMuted)
        if s.isHost:
          drawButton(lo.heatMinus, "-", Color(r: 40, g: 64, b: 104, a: 255), cw.hover == HoverHeatMinus)
          drawButton(lo.heatPlus, "+", Color(r: 40, g: 64, b: 104, a: 255), cw.hover == HoverHeatPlus)
        drawCenteredTextFit($s.config.heat, lo.heatMinus.x.int32 + 30, lo.heatMinus.y.int32 + 5,
                            50, 15, ColTitle)
        drawText(t(tkCoopKit), rb.x.int32 + 14, rb.y.int32 + 100, 14, ColMuted)
        for k in 0 .. 2:
          drawPill(lo.kits[k], kitName(k), cw.kit == k, cw.hover == HoverKits + k)
      else:
        drawTextFit(t(tkCoopDifficultyNote), rb.x.int32 + 14, rb.y.int32 + 70, rb.width.int32 - 28,
                    13, ColHint)
      # The main button: the host starts, a client readies.
      if s.isHost:
        let can = s.readyToStart
        drawButton(lo.primary, t(tkCoopStartButton), Color(r: 46, g: 120, b: 70, a: 255),
                   cw.hover == HoverPrimary, can)
        let wait = if s.members.len < 2: t(tkCoopWaitingPlayers)
                   elif not can: t(tkCoopWaitingReady) else: ""
        if wait.len > 0:
          drawTextFit(wait, lo.primary.x.int32, lo.statusY.int32, lo.note.width.int32, 14, ColMuted)
      else:
        drawButton(lo.primary, (if s.readyWanted: t(tkCoopNotReadyButton) else: t(tkCoopReadyButton)),
                   (if s.readyWanted: Color(r: 90, g: 80, b: 40, a: 255) else: Color(r: 46, g: 120, b: 70, a: 255)),
                   cw.hover == HoverPrimary, s.phase == cpClientLobby)
        if s.readyWanted:
          drawTextFit(t(tkCoopWaitingHost), lo.primary.x.int32, lo.statusY.int32,
                      lo.note.width.int32, 14, ColMuted)
      drawButton(lo.leave, t(tkCoopLeaveButton), Color(r: 110, g: 50, b: 50, a: 255),
                 cw.hover == HoverLeave)

  if cw.statusTimer > 0 and cw.status.len > 0:
    let a = uint8(255.0'f32 * min(1.0'f32, cw.statusTimer))
    drawTextFit(cw.status, lo.note.x.int32, (lo.note.y - 22).int32, lo.note.width.int32, 14,
                withAlpha(ColWarn, a))
  drawWrapped(t(tkCoopNote), lo.note, 12, ColMuted)
  drawResizeIndicator(cw.window)
