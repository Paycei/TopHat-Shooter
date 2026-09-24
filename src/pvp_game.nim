## PvP Game Mode Logic
## Handles multiplayer player vs player combat with optional team support

import raylib, rlgl, math, times, strutils, sequtils, algorithm, random
from std/unicode import nil   # toUpper for accented team names, without its split/strip overloads
import types, player, bullet, wall, particle, particle_pool, particle_types, sound, network/network_types, network/network, settings, save_system, localization, render_context, ui/background_fx, d_systems

const
  PVP_KILL_LIMIT* = 5  # Default kill limit (actual value comes from PvPConfig at runtime)
  WALL_PLACEMENT_RANGE* = 250.0  # Max distance from player at which a wall can be placed

  # Game feel. Everything below is presentation or host-decided scoring; none of
  # it bends the simulation clock (no hit-stop: the match is networked).
  MultiKillWindow* = 3.0'f32      ## kills this close together chain into DOUBLE / TRIPLE FAULT
  StreakCalloutMin* = 3           ## streak that earns the root-prompt badge and can be SHUTDOWN
  KillFeedMax = 5
  KillFeedLife = 5.0'f32
  BannerTime = 1.6'f32
  ToastTime = 2.2'f32
  HitMarkerTime = 0.18'f32
  KillMarkerTime = 0.35'f32
  HurtFlashTime = 0.35'f32
  RespawnInvulnTime = 2.0'f32
  # Reliability for the handful of one-shot packets a match depends on. Over
  # UDP a single lost ptGameStart / ptGameOver used to strand a client.
  RebroadcastInterval = 0.5'f32
  # Dash sync. The host accepts a new dash if its own cooldown is this close to
  # ready (host and client clocks drift by a frame or two), and the client skips
  # soft position corrections for a moment after dashing: the host replays the
  # burst one latency later, so mid-dash snapshots legitimately lag behind.
  DashAcceptGrace = 0.2'f32
  DashCorrectionGrace = 0.25'f32
  # Once the local player has stood still this long (plus one round trip), the
  # host's final position for them has arrived, and the client settles onto it
  # even below the soft-correction threshold. Otherwise a stop could leave a
  # silent 20-50 px offset between where you see yourself and where the host
  # checks bullets against you.
  IdleSettleTime = 0.2'f32

# Arena packages: the pickups that spawn on the arena's PORTS. Pure tuning,
# data and drawing; the match logic further down owns every decision. Port
# positions derive purely from the arena size, so host and clients agree on
# them without a position ever going on the wire: snapshots only carry each
# port's kind, active flag and timer.

type
  PvPPackageKind* = enum
    pkChkdsk     ## restores integrity (heal)
    pkFirewall   ## absorbs the next hit
    pkTurbo      ## move speed burst
    pkOverclock  ## fire rate burst (power port)
    pkFork       ## 3-way shot (power port)

const
  PortRadius*           = 26.0'f32  ## socket ring drawn on the floor
  PortGrabPadding*      = 16.0'f32  ## grab when within player.radius + this of the port centre
  PortIncomingTime*     = 3.0'f32   ## the next package flickers in as a hologram this long before it lands

  # The centre power port is the one worth fighting over: slower cadence, and
  # its first drop lands well after the opening skirmish so the match has a
  # clear "go there now" moment. Quadrant ports feed the flanks.
  PowerPortFirstSpawn*   = 20.0'f32
  PowerPortRespawn*      = 25.0'f32
  UtilityPortFirstSpawn* = 6.0'f32
  UtilityPortRespawn*    = 14.0'f32

  ChkdskHealFraction* = 1.0'f32 / 3.0'f32  ## of max HP, never less than 1
  TurboDuration*      = 5.0'f32
  TurboSpeedMult*     = 1.4'f32
  OverclockDuration*  = 6.0'f32
  OverclockFireMult*  = 0.5'f32            ## multiplier on the shot interval (x2 fire rate)
  ForkDuration*       = 8.0'f32
  ForkSpreadDeg*      = 14.0'f32
  # Side bullets hit for half: with the default 3 HP a point-blank Fork volley
  # would otherwise be a guaranteed one-shot, which reads as unfair rather than
  # earned. At range only one bullet lands anyway.
  ForkSideDamageMult* = 0.5'f32

  PowerPackages*   = [pkOverclock, pkFork]
  UtilityPackages* = [pkChkdsk, pkFirewall, pkTurbo]

proc packageFromInt*(value: int): PvPPackageKind =
  ## Kind from a raw ordinal off the wire. A plain PvPPackageKind(value) is
  ## unchecked in release builds, so a bad value would become an invalid enum.
  if value < ord(low(PvPPackageKind)) or value > ord(high(PvPPackageKind)): pkChkdsk
  else: PvPPackageKind(value)

proc rollPackage*(isPower: bool): PvPPackageKind =
  ## Host only: the kind a port will drop next (clients learn it from snapshots).
  if isPower: PowerPackages[rand(PowerPackages.high)]
  else: UtilityPackages[rand(UtilityPackages.high)]

proc portLayout*(arenaW, arenaH: float32): seq[tuple[pos: Vector2f, isPower: bool]] =
  ## Centre power port plus four quadrant utility ports. Symmetric left/right
  ## and top/bottom, so neither the 1v1 spawns (x = 25% / 75%) nor the team
  ## spawns (left / right edges) start closer to anything than their rival.
  @[
    (pos: newVector2f(arenaW * 0.5'f32,  arenaH * 0.5'f32),  isPower: true),
    (pos: newVector2f(arenaW * 0.25'f32, arenaH * 0.25'f32), isPower: false),
    (pos: newVector2f(arenaW * 0.75'f32, arenaH * 0.25'f32), isPower: false),
    (pos: newVector2f(arenaW * 0.25'f32, arenaH * 0.75'f32), isPower: false),
    (pos: newVector2f(arenaW * 0.75'f32, arenaH * 0.75'f32), isPower: false)
  ]

proc packageDuration*(kind: PvPPackageKind): float32 =
  ## Timed buff length, 0 for instant / until-consumed packages.
  case kind
  of pkChkdsk, pkFirewall: 0.0'f32
  of pkTurbo: TurboDuration
  of pkOverclock: OverclockDuration
  of pkFork: ForkDuration

proc packageName*(kind: PvPPackageKind): string =
  case kind
  of pkChkdsk: t(tkPvPPkgChkdsk)
  of pkFirewall: t(tkPvPPkgFirewall)
  of pkTurbo: t(tkPvPPkgTurbo)
  of pkOverclock: t(tkPvPPkgOverclock)
  of pkFork: t(tkPvPPkgFork)

proc packageBlurb*(kind: PvPPackageKind): string =
  case kind
  of pkChkdsk: t(tkPvPPkgChkdskBlurb)
  of pkFirewall: t(tkPvPPkgFirewallBlurb)
  of pkTurbo: t(tkPvPPkgTurboBlurb)
  of pkOverclock: t(tkPvPPkgOverclockBlurb)
  of pkFork: t(tkPvPPkgForkBlurb)

proc packageColor*(kind: PvPPackageKind): Color =
  ## Firewall and Turbo match the player-body effects they switch on (the cyan
  ## shield bubble and the green-cyan speed trail in drawPlayer), so the pickup
  ## and its effect read as the same thing.
  case kind
  of pkChkdsk: Color(r: 90, g: 235, b: 120, a: 255)
  of pkFirewall: Color(r: 0, g: 220, b: 255, a: 255)
  of pkTurbo: Color(r: 0, g: 255, b: 200, a: 255)
  of pkOverclock: Color(r: 255, g: 185, b: 40, a: 255)
  of pkFork: Color(r: 255, g: 95, b: 205, a: 255)

proc drawPackageIcon*(kind: PvPPackageKind, cx, cy, size: float32, color: Color) =
  ## Programmatic glyph centred on (cx, cy); `size` is the half-extent. Shapes
  ## are chunky on purpose: the icon has to read at ~10 px on a HUD pill.
  let s = size
  let thick = max(1.5'f32, s * 0.24'f32)
  # Params must not be called x/y: a template substitutes them into the
  # constructor's field names too.
  template p(u, v: float32): Vector2 = Vector2(x: cx + u * s, y: cy + v * s)
  case kind
  of pkChkdsk:
    # Repair cross
    drawRectangle(Rectangle(x: cx - s * 0.2'f32, y: cy - s * 0.75'f32,
                            width: s * 0.4'f32, height: s * 1.5'f32), color)
    drawRectangle(Rectangle(x: cx - s * 0.75'f32, y: cy - s * 0.2'f32,
                            width: s * 1.5'f32, height: s * 0.4'f32), color)
  of pkFirewall:
    # Brick wall: the universal firewall glyph
    let gap = max(1.0'f32, s * 0.1'f32)
    let rowH = s * 0.55'f32
    let top = cy - rowH - gap * 0.5'f32
    let bottom = cy + gap * 0.5'f32
    drawRectangle(Rectangle(x: cx - s * 0.85'f32, y: top, width: s * 0.85'f32 - gap * 0.5'f32, height: rowH), color)
    drawRectangle(Rectangle(x: cx + gap * 0.5'f32, y: top, width: s * 0.85'f32 - gap * 0.5'f32, height: rowH), color)
    drawRectangle(Rectangle(x: cx - s * 0.85'f32, y: bottom, width: s * 0.4'f32 - gap, height: rowH), color)
    drawRectangle(Rectangle(x: cx - s * 0.45'f32, y: bottom, width: s * 0.9'f32, height: rowH), color)
    drawRectangle(Rectangle(x: cx + s * 0.45'f32 + gap, y: bottom, width: s * 0.4'f32 - gap, height: rowH), color)
  of pkTurbo:
    # Double chevron
    for ox in [-0.4'f32, 0.2'f32]:
      drawLine(p(ox - 0.2'f32, -0.65'f32), p(ox + 0.3'f32, 0.0'f32), thick, color)
      drawLine(p(ox + 0.3'f32, 0.0'f32), p(ox - 0.2'f32, 0.65'f32), thick, color)
  of pkOverclock:
    # Lightning bolt
    drawLine(p(0.3'f32, -0.9'f32), p(-0.3'f32, 0.08'f32), thick, color)
    drawLine(p(-0.3'f32, 0.08'f32), p(0.3'f32, -0.08'f32), thick, color)
    drawLine(p(0.3'f32, -0.08'f32), p(-0.3'f32, 0.9'f32), thick, color)
  of pkFork:
    # One process splitting into three
    let root = p(0.0'f32, 0.8'f32)
    let tips = [p(-0.72'f32, -0.62'f32), p(0.0'f32, -0.85'f32), p(0.72'f32, -0.62'f32)]
    for tip in tips:
      drawLine(root, tip, thick * 0.8'f32, color)
      drawCircle(tip, thick * 0.8'f32, color)
    drawCircle(root, thick, color)

type
  TeamScore* = object
    kills*: int
    deaths*: int

  # Interpolation state for remote players
  PlayerInterpState = object
    prevPos*: Vector2f
    targetPos*: Vector2f
    prevVel*: Vector2f
    targetVel*: Vector2f
    prevTime*: float32
    targetTime*: float32
    hasData*: bool

  PvPEndReason* = enum
    ## Why the match ended. Sent as an ordinal and turned into text only at
    ## draw time, so every client shows it in its own language.
    erNone,
    erKillLimit,
    erTimeLimit,
    erOpponentDisconnected,   # 1v1: the other side timed out
    erOpponentForfeited,      # 1v1: the other side left on purpose
    erLastStanding,           # everyone else left / was eliminated
    erHostLeft                # client only: the server is gone

  PvPPlayerStats* = object
    ## Host-authoritative per-match scoring. Deaths and streak ride in every
    ## snapshot; the rest reaches clients once, in ptGameOver.finalStats.
    deaths*: int
    streak*: int
    bestStreak*: int
    shotsFired*: int
    shotsHit*: int
    damageDealt*: float32
    pickupsTaken*: int
    lastKillTime*: float32   ## host: multi-kill chaining
    multiCount*: int

  PvPPort* = object
    pos*: Vector2f
    isPower*: bool
    kind*: PvPPackageKind    ## what is on it, or what drops next while inactive
    active*: bool
    timer*: float32          ## seconds until the next drop while inactive

  KillFeedKind = enum
    kfKill, kfLeft, kfPackage

  KillFeedEntry = object
    kind: KillFeedKind
    actor: int               ## killer / leaver / package taker (-1 = none)
    target: int              ## victim (kills only)
    pkg: PvPPackageKind      ## kfPackage only
    tag: string              ## localized callout suffix, "" for none
    age: float32

  HitMarker = object
    pos: Vector2f
    age: float32
    isKill: bool

  PvPGameState* = ref object
    networkManager*: NetworkManager
    localPlayerIndex*: int  # 0-15
    maxPlayers*: int  # Maximum number of players (2-16)
    players*: seq[Player]  # Dynamic player list
    bullets*: seq[Bullet]
    walls*: seq[Wall]
    particlePool*: ParticlePool
    serverTick*: int
    gameTime*: float32
    gameStarted*: bool
    gameOver*: bool
    winnerIndex*: int
    winnerTeam*: PvPTeam  # Winning team for team-based mode
    endReason*: PvPEndReason  # Why the match ended
    inputBuffer*: seq[PlayerInput]
    lastSnapshotTime*: float32
    lastInputSendTime*: float32
    # Unacknowledged inputs for client-side replay. `vel` is the velocity the
    # input ACTUALLY moved the player with locally (dash / TURBO included), so the
    # replay reproduces the same path instead of re-deriving it from moveDir.
    pendingInputs*: seq[tuple[capturedAt: float32, input: PlayerInput, vel: Vector2f]]
    screenWidth*: int32
    screenHeight*: int32
    bulletIdCounter*: int  # Local bullet ID counter
    countdownTimer*: float32
    isCountingDown*: bool
    damageNumbers*: seq[DamageNumber]
    lastPingTime*: float32
    respawnTimers*: seq[float32]  # Respawn timers for each player
    playerConnected*: seq[bool]   # Whether each player slot is still connected
    lastInputs*: seq[PlayerInput]  # Store last input for each player (server processing)
    playerNicknames*: seq[string]  # Display nicknames, indexed by player index
    teamsEnabled*: bool  # Whether team-based gameplay is enabled
    playerTeamAssignments*: seq[int]  # Team assignment per player (0-3)
    teamScores*: array[PvPTeam, TeamScore]  # Track scores per team
    # Client-side interpolation for remote players
    playerInterpStates*: seq[PlayerInterpState]  # Interpolation state per player
    interpDelay*: float32  # Render delay for interpolation (in seconds)
    interpolationEnabled*: bool  # Whether interpolation is enabled
    recentlyDestroyedBullets*: seq[int]  # Recently destroyed bullet IDs (to prevent snapshot resurrection)
    localPosCorrection*: Vector2f  # Accumulated position error, blended per-frame toward zero
    config*: PvPConfig                  # Host-configurable game settings
    wallPlacementMode*: bool            # Whether the local player is in wall-placement mode (toggled by E)
    # Rematch generation, stamped on every packet (see Packet.matchId)
    matchId*: int
    rebroadcastTimer*: float32          # host: resend ptGameStart / ptGameOver while they matter
    # Scoring
    stats*: seq[PvPPlayerStats]
    firstBloodDone*: bool
    # Dash sync
    lastDashSeq*: seq[int]              # last dashSeq applied per player (both roles)
    localDashSeq*: int                  # local player's cumulative dash presses this match
    pendingDashDir*: Vector2f           # direction locked at the latest press, repeated in every input
    lastSentDashSeq: int                # client: newest dashSeq already pushed out immediately
    keepAliveTimer: float32             # pings on the result screen (gameTime is frozen there)
    lastRemoteShotSound: float32        # client: throttles other players' shot sounds
    dashCorrectionGrace*: float32       # client: skip soft corrections while this runs
    localIdleTime*: float32             # client: how long the local player has been standing still
    # Arena packages
    ports*: seq[PvPPort]
    spreadTimers*: seq[float32]         # FORK.EXE per player (no Player field for it)
    # Presentation only (never sent, never affects the simulation)
    killFeed: seq[KillFeedEntry]
    hitMarkers: seq[HitMarker]
    bannerText: string
    bannerSub: string
    bannerColor: Color
    bannerAge: float32
    toastText: string
    toastColor: Color
    toastAge: float32
    killedBy: seq[int]                  # who last killed each player (respawn caption)
    shake: ScreenShake
    hurtFlash: float32

proc getTeamName*(team: PvPTeam): string =
  ## Get the display name for a team
  case team
  of ptRed:
    return t(tkPvPTeamRed)
  of ptBlue:
    return t(tkPvPTeamBlue)
  of ptGreen:
    return t(tkPvPTeamGreen)
  of ptYellow:
    return t(tkPvPTeamYellow)
  of ptOrange:
    return t(tkPvPTeamOrange)
  of ptPurple:
    return t(tkPvPTeamPurple)
  of ptNone:
    return t(tkPvPTeamNone)

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
  of ptOrange:
    return Color(r: 255, g: 165, b: 0, a: 255)
  of ptPurple:
    return Color(r: 200, g: 100, b: 255, a: 255)
  of ptNone:
    return White

proc assignPlayerToTeam*(playerIndex: int, maxPlayers: int, teamsEnabled: bool): PvPTeam =
  ## Assign a player to a team based on their index
  if not teamsEnabled:
    return ptNone

  # For 2-4 players: 2 teams (Red vs Blue)
  # For 5-8 players: 2 teams (Red vs Blue) with more per team
  # For 9-12 players: 3 teams (Red vs Blue vs Green)
  # For 13-16 players: 4 teams (Red vs Blue vs Green vs Yellow)
  # For 17+ players: could add 5-6 teams but games are likely smaller

  if maxPlayers <= 8:
    # 2 teams
    if playerIndex mod 2 == 0:
      return ptRed
    else:
      return ptBlue
  elif maxPlayers <= 12:
    # 3 teams
    case playerIndex mod 3
    of 0: return ptRed
    of 1: return ptBlue
    else: return ptGreen
  else:
    # 4 teams for default assignment
    case playerIndex mod 4
    of 0: return ptRed
    of 1: return ptBlue
    of 2: return ptGreen
    else: return ptYellow

proc getTeamSpawnPosition(playerIndex: int, team: PvPTeam, totalPlayers: int, screenWidth, screenHeight: float32): Vector2f =
  ## Calculate spawn position for a player based on their team
  ## Teams spawn grouped together in different quadrants

  let centerX = screenWidth * 0.5
  let centerY = screenHeight * 0.5
  let spawnRadius = min(screenWidth, screenHeight) * 0.35

  case team
  of ptNone:
    # Free-for-all: distribute evenly around circle
    let angle = (playerIndex.float / totalPlayers.float) * 2.0 * PI
    return newVector2f(
      centerX + cos(angle) * spawnRadius,
      centerY + sin(angle) * spawnRadius
    )

  of ptRed:
    # Left side
    let teamOffset = (playerIndex div 2).float * 80.0  # Vertical spacing between teammates
    return newVector2f(
      screenWidth * 0.15,
      centerY + teamOffset - 80.0
    )

  of ptBlue:
    # Right side
    let teamOffset = (playerIndex div 2).float * 80.0
    return newVector2f(
      screenWidth * 0.85,
      centerY + teamOffset - 80.0
    )

  of ptGreen:
    # Top side
    let teamOffset = (playerIndex div 3).float * 80.0
    return newVector2f(
      centerX + teamOffset - 80.0,
      screenHeight * 0.15
    )

  of ptYellow:
    # Bottom side
    let teamOffset = (playerIndex div 4).float * 80.0
    return newVector2f(
      centerX + teamOffset - 80.0,
      screenHeight * 0.85
    )

  of ptOrange:
    # Top-left side
    let teamOffset = (playerIndex div 5).float * 80.0
    return newVector2f(
      screenWidth * 0.25,
      screenHeight * 0.15 + teamOffset
    )

  of ptPurple:
    # Top-right side
    let teamOffset = (playerIndex div 6).float * 80.0
    return newVector2f(
      screenWidth * 0.75,
      screenHeight * 0.15 + teamOffset
    )

proc getSpawnPosition(playerIndex, totalPlayers: int, screenWidth, screenHeight: float32): Vector2f =
  ## Calculate spawn position for a player based on their index (free-for-all)
  ## Distributes players evenly around the screen
  if totalPlayers == 2:
    # 1v1 positioning
    if playerIndex == 0:
      return newVector2f(screenWidth * 0.25, screenHeight * 0.5)
    else:
      return newVector2f(screenWidth * 0.75, screenHeight * 0.5)
  else:
    # Distribute players in a circle
    let angle = (playerIndex.float / totalPlayers.float) * 2.0 * PI
    let radius = min(screenWidth, screenHeight) * 0.35
    let centerX = screenWidth * 0.5
    let centerY = screenHeight * 0.5
    return newVector2f(
      centerX + cos(angle) * radius,
      centerY + sin(angle) * radius
    )

proc spawnPositionFor(pvp: PvPGameState, playerIndex: int): Vector2f =
  ## Team-aware spawn point, the same on host and clients.
  if pvp.teamsEnabled:
    getTeamSpawnPosition(playerIndex, pvp.players[playerIndex].teamId, pvp.players.len,
                         pvp.screenWidth.float32, pvp.screenHeight.float32)
  else:
    getSpawnPosition(playerIndex, pvp.players.len,
                     pvp.screenWidth.float32, pvp.screenHeight.float32)

proc resetPorts(pvp: PvPGameState) =
  ## Fresh port set for a new match (empty when the host turned packages off).
  ## Kinds are rolled up front so the INCOMING hologram can show the right one;
  ## on clients the rolls are placeholders until the first snapshot lands.
  pvp.ports = @[]
  if not pvp.config.pickupsEnabled:
    return
  for slot in portLayout(pvp.screenWidth.float32, pvp.screenHeight.float32):
    pvp.ports.add(PvPPort(
      pos: slot.pos,
      isPower: slot.isPower,
      kind: rollPackage(slot.isPower),
      active: false,
      timer: if slot.isPower: PowerPortFirstSpawn else: UtilityPortFirstSpawn))

proc clearCombatBuffs(pvp: PvPGameState, playerIndex: int) =
  ## Death and rematch wipe every package effect and the dash state, so a
  ## respawn always starts from the same baseline (dash ready, no buffs).
  let p = pvp.players[playerIndex]
  p.shieldHits = 0
  p.speedBoostTimer = 0
  p.fireRateBoostTimer = 0
  p.dashTimer = 0
  p.dashCooldown = 0
  p.dashReadyFlash = 0
  if playerIndex < pvp.spreadTimers.len:
    pvp.spreadTimers[playerIndex] = 0

proc pvpPacket(pvp: PvPGameState, kind: PacketType): Packet {.inline.} =
  ## Every PvP packet goes out through here so it carries the match generation.
  result = newPacket(kind, pvp.serverTick)
  result.matchId = pvp.matchId

proc playerName*(pvp: PvPGameState, playerIndex: int): string =
  if playerIndex >= 0 and playerIndex < pvp.playerNicknames.len and
     pvp.playerNicknames[playerIndex].len > 0:
    pvp.playerNicknames[playerIndex]
  else:
    "P" & $(playerIndex + 1)

proc playerColor(pvp: PvPGameState, playerIndex: int): Color =
  ## Name colour everywhere (overhead tag, feed, scoreboard): team colour in
  ## team mode, else green for you and amber for everyone else.
  if playerIndex < 0 or playerIndex >= pvp.players.len:
    return Color(r: 200, g: 200, b: 200, a: 255)
  if pvp.teamsEnabled and pvp.players[playerIndex].teamId != ptNone:
    getTeamColor(pvp.players[playerIndex].teamId)
  elif playerIndex == pvp.localPlayerIndex:
    Color(r: 100, g: 255, b: 100, a: 255)
  else:
    Color(r: 255, g: 200, b: 100, a: 255)

proc newPvPGameState*(screenWidth, screenHeight: int32, isHost: bool, maxPlayers: int, connectedPlayers: seq[tuple[index: int, skinType, bulletSkinType, shapeType, particleSkinType: int, nickname: string]], teamsEnabled: bool = false, playerTeamAssignments: seq[int] = @[], interpolationEnabled: bool = true, config: PvPConfig = defaultPvPConfig()): PvPGameState =
  let emptyInput = PlayerInput(
    tick: 0,
    playerIndex: 0,
    moveDir: newVector2f(0, 0),
    shooting: false,
    mousePos: newVector2f(0, 0),
    placingWall: false,
    wallPos: newVector2f(0, 0),
    timestamp: 0
  )

  result = PvPGameState(
    networkManager: nil,  # Will be assigned from the window's network manager
    localPlayerIndex: if isHost: 0 else: -1,  # Will be set properly for clients
    maxPlayers: maxPlayers,
    players: @[],
    serverTick: 0,
    gameTime: 0,
    gameStarted: false,
    gameOver: false,
    winnerIndex: -1,
    winnerTeam: ptNone,
    endReason: erNone,
    inputBuffer: @[],
    lastSnapshotTime: 0,
    lastInputSendTime: 0,
    pendingInputs: @[],
    screenWidth: screenWidth,
    screenHeight: screenHeight,
    bulletIdCounter: 0,
    countdownTimer: 0,
    isCountingDown: false,
    damageNumbers: @[],
    lastPingTime: 0,
    respawnTimers: @[],
    playerConnected: @[],
    lastInputs: @[],
    playerNicknames: @[],
    teamsEnabled: teamsEnabled,
    playerTeamAssignments: playerTeamAssignments,
    # Initialize interpolation
    playerInterpStates: @[],
    interpDelay: 0.033,  # 33ms interpolation delay
    interpolationEnabled: interpolationEnabled,
    recentlyDestroyedBullets: @[],  # Track bullets destroyed to prevent snapshot resurrection
    localPosCorrection: newVector2f(0, 0),
    config: config
  )

  # Initialize team scores
  for team in PvPTeam:
    result.teamScores[team] = TeamScore(kills: 0, deaths: 0)

  # Initialize player slots
  for i in 0..<maxPlayers:
    # Use manual team assignments if provided, otherwise use automatic assignment
    let team = if teamsEnabled and playerTeamAssignments.len > i:
      teamFromInt(playerTeamAssignments[i])
    else:
      assignPlayerToTeam(i, maxPlayers, teamsEnabled)

    # Get spawn position based on team mode
    let spawnPos = if teamsEnabled:
      getTeamSpawnPosition(i, team, maxPlayers, screenWidth.float32, screenHeight.float32)
    else:
      getSpawnPosition(i, maxPlayers, screenWidth.float32, screenHeight.float32)

    let player = newPlayer(spawnPos.x, spawnPos.y)
    player.hp = config.startHp
    player.maxHp = config.startHp
    player.baselineMaxHp = config.startHp  # Match rules HP: nothing invested yet
    player.coins = config.startCoins
    player.walls = config.startWalls
    player.damage = config.startDamage
    player.bulletSpeed = config.bulletSpeed
    player.fireRate = config.fireRate
    player.speed = config.startSpeed
    player.teamId = team

    # Set cosmetics and nickname for connected players
    var cosmeticsSet = false
    var playerNick = "P" & $(i + 1)  # fallback
    for connectedPlayer in connectedPlayers:
      if connectedPlayer.index == i:
        player.skinType = connectedPlayer.skinType
        player.bulletSkinType = connectedPlayer.bulletSkinType
        player.shapeType = connectedPlayer.shapeType
        player.particleSkinType = connectedPlayer.particleSkinType
        if connectedPlayer.nickname.len > 0:
          playerNick = connectedPlayer.nickname
        cosmeticsSet = true
        break

    # If no cosmetics were set and this is the local player (host), use global settings
    if not cosmeticsSet and isHost and i == 0:
      player.skinType = globalSettings.playerSkin
      player.bulletSkinType = globalSettings.bulletSkin
      player.shapeType = globalSettings.playerShape
      player.particleSkinType = globalSettings.particleEffect
      playerNick = globalSettings.pvpNickname

    result.players.add(player)
    result.respawnTimers.add(0.0)
    result.playerConnected.add(true)
    result.lastInputs.add(emptyInput)
    result.playerNicknames.add(playerNick)
    result.stats.add(PvPPlayerStats())
    result.lastDashSeq.add(0)
    result.spreadTimers.add(0.0)
    result.killedBy.add(-1)

    # Initialize interpolation state for this player
    result.playerInterpStates.add(PlayerInterpState(
      prevPos: player.pos,
      targetPos: player.pos,
      prevVel: newVector2f(0, 0),
      targetVel: newVector2f(0, 0),
      prevTime: 0,
      targetTime: 0,
      hasData: false
    ))

  result.bullets = @[]
  result.walls = @[]
  result.particlePool = newParticlePool(2000)
  result.shake = newScreenShake()
  result.bannerAge = BannerTime
  result.toastAge = ToastTime
  resetPorts(result)

proc resetMatchState*(pvp: PvPGameState) =
  ## Put the arena back to the opening state of a match, keeping the roster
  ## (nicknames, cosmetics, teams, who is still connected). Shared by the host's
  ## rematch and by clients adopting it, so both sides start from identical state.
  for i in 0..<pvp.players.len:
    let p = pvp.players[i]
    let connected = i >= pvp.playerConnected.len or pvp.playerConnected[i]
    # Disconnected slots stay dead: nobody can rejoin a started match.
    p.hp = if connected: pvp.config.startHp else: 0.0
    p.maxHp = pvp.config.startHp
    p.pos = spawnPositionFor(pvp, i)
    p.vel = newVector2f(0, 0)
    p.kills = 0
    p.walls = pvp.config.startWalls
    # Far in the past, so the first trigger pull of the new match always fires
    # even though gameTime has gone back to 0.
    p.lastShot = -1000.0
    p.invincibilityTimer = 0
    clearCombatBuffs(pvp, i)
    pvp.respawnTimers[i] = 0
    pvp.stats[i] = PvPPlayerStats()
    pvp.lastDashSeq[i] = 0
    pvp.killedBy[i] = -1
    pvp.lastInputs[i].tick = -1  # stale input from the last match must not be replayed
    pvp.lastInputs[i].shooting = false
    pvp.lastInputs[i].placingWall = false
    pvp.lastInputs[i].moveDir = newVector2f(0, 0)
    pvp.lastInputs[i].dashSeq = 0
    if i < pvp.playerInterpStates.len:
      pvp.playerInterpStates[i].hasData = false
      pvp.playerInterpStates[i].prevPos = p.pos
      pvp.playerInterpStates[i].targetPos = p.pos
  for team in PvPTeam:
    pvp.teamScores[team] = TeamScore(kills: 0, deaths: 0)
  pvp.bullets = @[]
  pvp.walls = @[]
  pvp.recentlyDestroyedBullets = @[]
  pvp.damageNumbers = @[]
  pvp.pendingInputs = @[]
  pvp.localPosCorrection = newVector2f(0, 0)
  pvp.localDashSeq = 0
  pvp.localIdleTime = 0
  pvp.lastSentDashSeq = 0
  pvp.keepAliveTimer = 0
  pvp.pendingDashDir = newVector2f(0, -1)
  pvp.dashCorrectionGrace = 0
  pvp.wallPlacementMode = false
  pvp.firstBloodDone = false
  pvp.killFeed = @[]
  pvp.hitMarkers = @[]
  pvp.bannerAge = BannerTime
  pvp.toastAge = ToastTime
  pvp.hurtFlash = 0
  pvp.shake = newScreenShake()
  resetPorts(pvp)
  # Every throttle is "gameTime - lastX >= rate": with the clock back at 0 and
  # these left at the old match's values, the difference stays negative and no
  # snapshot / input / ping would go out for the length of the previous match.
  pvp.gameTime = 0
  pvp.lastSnapshotTime = 0
  pvp.lastInputSendTime = 0
  pvp.lastPingTime = 0
  pvp.rebroadcastTimer = 0
  pvp.gameOver = false
  pvp.gameStarted = false
  pvp.winnerIndex = -1
  pvp.winnerTeam = ptNone
  pvp.endReason = erNone

proc sendGameStartPacket(pvp: PvPGameState) =
  ## Host: game-start signal with teams, roster and rules. Sent when the
  ## countdown starts and re-sent through the countdown (it carries the time
  ## left, so a late copy also re-syncs the client's countdown).
  # Build team assignments array to send to clients
  var teamAssignments: seq[int] = @[]
  for i in 0..<pvp.maxPlayers:
    teamAssignments.add(pvp.players[i].teamId.ord)

  # Build connected players list to send to clients
  var gameConnectedPlayers: seq[ConnectedPlayerInfo] = @[]
  for i in 0..<pvp.maxPlayers:
    gameConnectedPlayers.add((
      index: i,
      skinType: pvp.players[i].skinType,
      bulletSkinType: pvp.players[i].bulletSkinType,
      shapeType: pvp.players[i].shapeType,
      particleSkinType: pvp.players[i].particleSkinType,
      nickname: pvp.playerNicknames[i]
    ))

  # Send game start packet with team information and game config
  var packet = pvpPacket(pvp, ptGameStart)
  packet.countdownTime = pvp.countdownTimer
  packet.teamsEnabled = pvp.teamsEnabled
  packet.teamAssignments = teamAssignments
  packet.gameConnectedPlayers = gameConnectedPlayers
  packet.pvpConfig = pvp.config
  pvp.networkManager.sendPacket(packet)

proc startCountdown*(pvp: PvPGameState) =
  pvp.isCountingDown = true
  pvp.countdownTimer = 3.0
  pvp.rebroadcastTimer = RebroadcastInterval  # first copy goes out below

  # Reset the receive timer to prevent false timeout from lobby waiting time
  pvp.networkManager.resetReceiveTimer()

  if pvp.networkManager.isHost():
    sendGameStartPacket(pvp)

proc capturePlayerInput*(pvp: PvPGameState, dt: float32): PlayerInput =
  var moveDir = newVector2f(0, 0)
  let kb = globalSettings.keybinds
  if isKeyDown(kb[kaMoveUp]): moveDir.y -= 1
  if isKeyDown(kb[kaMoveDown]): moveDir.y += 1
  if isKeyDown(kb[kaMoveLeft]): moveDir.x -= 1
  if isKeyDown(kb[kaMoveRight]): moveDir.x += 1

  if isGamepadActive():
    let ls = leftStick()
    moveDir.x += ls.x
    moveDir.y += ls.y
    let gb = globalSettings.gamepadBinds
    if isGamepadBindDown(gb, kaMoveUp): moveDir.y -= 1
    if isGamepadBindDown(gb, kaMoveDown): moveDir.y += 1
    if isGamepadBindDown(gb, kaMoveLeft): moveDir.x -= 1
    if isGamepadBindDown(gb, kaMoveRight): moveDir.x += 1

  # Clamp instead of normalize so partial stick deflection keeps its magnitude
  if moveDir.length() > 1:
    moveDir = moveDir.normalize()

  var mousePos = getWorldMousePosition()
  if isGamepadActive():
    # Twin-stick aim at a fixed radius. Deliberately NO aim assist in PvP:
    # snapping onto other players would be a fairness problem. Walls are
    # placed at the same stick-aimed point.
    let dir = aimDir()
    const AimPointRadius = 240.0'f32
    let localPos = pvp.players[pvp.localPlayerIndex].pos
    mousePos = Vector2(x: localPos.x + dir.x * AimPointRadius,
                       y: localPos.y + dir.y * AimPointRadius)
    setGamepadAimPointWorld(mousePos)

  # Toggle wall-placement mode with wall key, right-click cancels it
  if (isKeyPressed(globalSettings.keybinds[kaPlaceWall]) or
      isGamepadBindPressed(globalSettings.gamepadBinds, kaPlaceWall)) and
     pvp.players[pvp.localPlayerIndex].walls > 0:
    pvp.wallPlacementMode = not pvp.wallPlacementMode
  if isMouseButtonPressed(Right) and pvp.wallPlacementMode:
    pvp.wallPlacementMode = false
  # Auto-exit mode when player runs out of walls
  if pvp.players[pvp.localPlayerIndex].walls <= 0:
    pvp.wallPlacementMode = false

  # In wall-placement mode: left-click places a wall instead of shooting
  let placingWall = pvp.wallPlacementMode and isPointerPressed()
  let shooting    = (not pvp.wallPlacementMode) and
                    (isMouseButtonDown(Left) or isKeyDown(kb[kaShoot]) or
                     gamepadFireDown(globalSettings.gamepadBinds))

  # BASE DASH, same verb and tuning as PvE (player.nim). Only a press that the
  # local cooldown would actually honour bumps the count, so a mashed key can't
  # queue up dashes the host would then fire the moment the cooldown ends.
  let localPlayer = pvp.players[pvp.localPlayerIndex]
  if localPlayer.hp > 0 and localPlayer.dashCooldown <= 0 and localPlayer.dashTimer <= 0 and
     (isKeyPressed(kb[kaDash]) or
      (isGamepadActive() and isGamepadBindPressed(globalSettings.gamepadBinds, kaDash))):
    inc pvp.localDashSeq
    # Held direction, else current travel, else straight up (as in PvE).
    pvp.pendingDashDir =
      if moveDir.length() >= 0.01'f32: moveDir.normalize()
      elif localPlayer.vel.length() > 1.0'f32: localPlayer.vel.normalize()
      else: newVector2f(0, -1)

  result = PlayerInput(
    tick: pvp.serverTick,
    playerIndex: pvp.localPlayerIndex,
    moveDir: moveDir,
    shooting: shooting,
    mousePos: newVector2f(mousePos.x, mousePos.y),
    placingWall: placingWall,
    wallPos: newVector2f(mousePos.x, mousePos.y),
    timestamp: epochTime(),
    dt: dt,
    dashSeq: pvp.localDashSeq,
    dashDir: pvp.pendingDashDir
  )

proc areTeammates*(pvp: PvPGameState, playerIdx1, playerIdx2: int): bool =
  ## Check if two players are on the same team
  if not pvp.teamsEnabled:
    return false
  if playerIdx1 < 0 or playerIdx1 >= pvp.players.len:
    return false
  if playerIdx2 < 0 or playerIdx2 >= pvp.players.len:
    return false
  if pvp.players[playerIdx1].teamId == ptNone:
    return false
  return pvp.players[playerIdx1].teamId == pvp.players[playerIdx2].teamId

proc effectiveMoveSpeed(player: Player): float32 =
  ## TURBO.DLL-aware movement speed. The live step and the reconcile replay both
  ## read it, so a boosted client doesn't rubber-band against its own prediction.
  if player.speedBoostTimer > 0: player.speed * TurboSpeedMult else: player.speed

proc effectiveFireInterval(player: Player): float32 =
  ## OVERCLOCK.SYS-aware seconds between shots.
  if player.fireRateBoostTimer > 0: player.fireRate * OverclockFireMult else: player.fireRate

proc movePlayerBy(pvp: PvPGameState, player: Player, delta: Vector2f) =
  ## One movement step with wall blocking and arena clamping. Shared by live
  ## input and reconcile replay so both resolve collisions identically.
  let nextPos = player.pos + delta
  var canMove = true
  for wall in pvp.walls:
    if checkPlayerWallCollision(nextPos, player.radius, wall):
      canMove = false
      break
  if canMove:
    player.pos = nextPos
  player.pos.x = clamp(player.pos.x, player.radius, pvp.screenWidth.float32 - player.radius)
  player.pos.y = clamp(player.pos.y, player.radius, pvp.screenHeight.float32 - player.radius)

proc replayMovementInput(pvp: PvPGameState, playerIndex: int, vel: Vector2f, dt: float32) =
  ## Replay only the movement component of a past input during reconciliation.
  ## Side-effects (shooting, wall placement, starting a dash) are deliberately
  ## skipped to avoid duplicates. `vel` is what that input really moved the
  ## player with, so a replayed dash frame covers dash distance, not walk distance.
  if playerIndex < 0 or playerIndex >= pvp.players.len: return
  let player = pvp.players[playerIndex]
  if player.hp <= 0: return
  if vel.x != 0 or vel.y != 0:
    movePlayerBy(pvp, player, vel * dt)

proc rotated(v: Vector2f, angle: float32): Vector2f =
  let c = cos(angle)
  let s = sin(angle)
  newVector2f(v.x * c - v.y * s, v.x * s + v.y * c)

# Presentation. These only touch the presentation fields (feed, markers,
# banners, sounds, particles, shake). The host calls each one where it decides
# the event, clients when the matching packet arrives, so both sides feel
# every hit and kill the same way.

proc pushFeed(pvp: PvPGameState, entry: KillFeedEntry) =
  pvp.killFeed.add(entry)
  if pvp.killFeed.len > KillFeedMax:
    pvp.killFeed.delete(0)

proc showBanner(pvp: PvPGameState, text, sub: string, color: Color) =
  pvp.bannerText = text
  pvp.bannerSub = sub
  pvp.bannerColor = color
  pvp.bannerAge = 0

proc showToast(pvp: PvPGameState, text: string, color: Color) =
  pvp.toastText = text
  pvp.toastColor = color
  pvp.toastAge = 0

proc killCallouts(multiKill, killerStreak: int, firstBlood: bool,
                  shutdownStreak: int): seq[string] =
  ## Callouts one kill earned, most exciting first: the banner headlines the
  ## first and lists the rest under it, the kill feed tags the first.
  if multiKill >= 3: result.add(t(tkPvPCallTriple))
  elif multiKill == 2: result.add(t(tkPvPCallDouble))
  # Streak tiers fire once on the kill that reaches them; past 7 every second
  # kill repeats KERNEL MODE so a runaway leader keeps getting called out.
  if killerStreak >= 7 and killerStreak mod 2 == 1: result.add(t(tkPvPCallStreak7))
  elif killerStreak == 5: result.add(t(tkPvPCallStreak5))
  elif killerStreak == StreakCalloutMin: result.add(t(tkPvPCallStreak3))
  if shutdownStreak >= StreakCalloutMin: result.add(t(tkPvPCallShutdown))
  if firstBlood: result.add(t(tkPvPCallFirstBlood))

proc fxHit(pvp: PvPGameState, victim, attacker: int, amount: float32, blocked: bool) =
  ## One bullet landing on a player.
  if victim < 0 or victim >= pvp.players.len: return
  let pos = pvp.players[victim].pos
  let local = pvp.localPlayerIndex
  if blocked:
    spawnExplosionPooled(pvp.particlePool, pos.x, pos.y, packageColor(pkFirewall), 16)
    playSound(stShield, if victim == local or attacker == local: 1.0'f32 else: 0.5'f32)
  else:
    spawnExplosionPooled(pvp.particlePool, pos.x, pos.y, Red, 10)
    # Must go through newDamageNumber: building the object field-by-field would
    # leave the randomized arc fields at zero (no drift, invisible text).
    pvp.damageNumbers.add(newDamageNumber(pos.x, pos.y, amount, fromPlayer = false))
  if attacker == local and victim != local:
    # Hit confirm: the shooter needs to know it landed, not just the victim.
    pvp.hitMarkers.add(HitMarker(pos: pos, age: 0, isKill: false))
    if not blocked:
      playSound(stEnemyHit, 0.8'f32, 1.35'f32)
  if victim == local:
    if not blocked:
      playSound(stPlayerHit)
      addShake(pvp.shake, siMedium)
      pvp.hurtFlash = HurtFlashTime
  elif attacker != local and not blocked:
    playSound(stPlayerHit, 0.45'f32)

proc fxKill(pvp: PvPGameState, victim, killer, killerStreak, multiKill: int,
            firstBlood: bool, shutdownStreak: int) =
  ## A player going down: feed row, callouts, and the local reactions.
  if victim < 0 or victim >= pvp.players.len: return
  let pos = pvp.players[victim].pos
  let local = pvp.localPlayerIndex
  spawnExplosionPooled(pvp.particlePool, pos.x, pos.y, Red, 30)
  if victim < pvp.killedBy.len:
    pvp.killedBy[victim] = killer
  let callouts = killCallouts(multiKill, killerStreak, firstBlood, shutdownStreak)
  pvp.pushFeed(KillFeedEntry(kind: kfKill, actor: killer, target: victim,
                             tag: (if callouts.len > 0: callouts[0] else: ""), age: 0))
  if killer == local and victim != local:
    pvp.hitMarkers.add(HitMarker(pos: pos, age: 0, isKill: true))
    playSound(stEnemyDeath, 1.0'f32, 1.1'f32)
    addShake(pvp.shake, siSmall)
    if callouts.len > 0:
      pvp.showBanner(callouts[0], callouts[1 .. ^1].join("  +  "), Gold)
      playSound(stWaveComplete, 0.7'f32)
  elif victim == local:
    addShake(pvp.shake, siLarge)
    pvp.hurtFlash = HurtFlashTime * 1.6'f32
    playSound(stExplosion, 0.8'f32)
  else:
    playSound(stEnemyDeath, 0.5'f32)

proc fxPickup(pvp: PvPGameState, portIdx, taker: int, kind: PvPPackageKind) =
  ## A package leaving its port.
  let local = pvp.localPlayerIndex
  let col = packageColor(kind)
  let validPort = portIdx >= 0 and portIdx < pvp.ports.len
  if validPort:
    spawnExplosionPooled(pvp.particlePool, pvp.ports[portIdx].pos.x,
                         pvp.ports[portIdx].pos.y, col, 22)
  if taker == local:
    playSound(stPowerUp)
    pvp.showToast(packageName(kind) & ": " & packageBlurb(kind), col)
  else:
    playSound(stCoinPickup, 0.5'f32)
  # Only the contested centre drop is worth a feed row; quadrant grabs would
  # drown out the kills.
  if validPort and pvp.ports[portIdx].isPower:
    pvp.pushFeed(KillFeedEntry(kind: kfPackage, actor: taker, target: -1, pkg: kind, age: 0))

proc fxRespawn(pvp: PvPGameState, idx: int) =
  if idx < 0 or idx >= pvp.players.len: return
  let pos = pvp.players[idx].pos
  spawnExplosionPooled(pvp.particlePool, pos.x, pos.y, Color(r: 120, g: 230, b: 255, a: 255), 18)
  if idx == pvp.localPlayerIndex:
    playSound(stTeleport, 0.7'f32)

proc localResult*(pvp: PvPGameState): int =
  ## 1 = the local player (or their team) won, -1 = lost, 0 = draw / no winner.
  if pvp.teamsEnabled:
    if pvp.winnerTeam == ptNone: return 0
    let localTeam = pvp.players[pvp.localPlayerIndex].teamId
    return (if localTeam == pvp.winnerTeam: 1 else: -1)
  if pvp.winnerIndex < 0: 0
  elif pvp.winnerIndex == pvp.localPlayerIndex: 1
  else: -1

proc fxMatchEnd(pvp: PvPGameState) =
  pvp.wallPlacementMode = false
  pvp.bannerAge = BannerTime  # the result screen replaces any pending callout
  case localResult(pvp)
  of 1: playSound(stWaveComplete)
  of -1: playSound(stGameOver)
  else: playSound(stGameOver, 0.6'f32)

# Packages

proc applyPackageEffect(pvp: PvPGameState, playerIndex: int, kind: PvPPackageKind) =
  ## Authoritative on the host. Clients mirror it when ptPickupTaken arrives so
  ## the buff shows up at once, except the heal: HP is additive and the next
  ## snapshot may already carry it, so clients wait for the snapshot.
  if playerIndex < 0 or playerIndex >= pvp.players.len: return
  let p = pvp.players[playerIndex]
  case kind
  of pkChkdsk:
    if pvp.networkManager.isHost():
      let heal = max(1.0'f32, ceil(p.maxHp * ChkdskHealFraction))
      p.hp = min(p.maxHp, p.hp + heal)
  of pkFirewall:
    p.shieldHits = 1
  of pkTurbo:
    p.speedBoostTimer = TurboDuration
  of pkOverclock:
    p.fireRateBoostTimer = OverclockDuration
  of pkFork:
    pvp.spreadTimers[playerIndex] = ForkDuration

proc updatePortsServer(pvp: PvPGameState, dt: float32) =
  ## Host: count down empty ports, drop packages, hand them to whoever touches
  ## them first. The next kind is rolled the moment a package is taken, so the
  ## INCOMING hologram (driven by snapshots on clients) always shows the truth.
  for portIdx in 0..<pvp.ports.len:
    if not pvp.ports[portIdx].active:
      pvp.ports[portIdx].timer = max(0.0'f32, pvp.ports[portIdx].timer - dt)
      if pvp.ports[portIdx].timer <= 0:
        pvp.ports[portIdx].active = true
      continue
    for playerIdx in 0..<pvp.players.len:
      let player = pvp.players[playerIdx]
      if player.hp <= 0:
        continue
      if distance(player.pos, pvp.ports[portIdx].pos) > player.radius + PortGrabPadding:
        continue
      let kind = pvp.ports[portIdx].kind
      applyPackageEffect(pvp, playerIdx, kind)
      inc pvp.stats[playerIdx].pickupsTaken
      pvp.ports[portIdx].active = false
      pvp.ports[portIdx].timer =
        if pvp.ports[portIdx].isPower: PowerPortRespawn else: UtilityPortRespawn
      pvp.ports[portIdx].kind = rollPackage(pvp.ports[portIdx].isPower)
      var pkt = pvpPacket(pvp, ptPickupTaken)
      pkt.pickupPort = portIdx
      pkt.pickupKind = kind.ord
      pkt.pickupTaker = playerIdx
      pvp.networkManager.sendPacket(pkt)
      fxPickup(pvp, portIdx, playerIdx, kind)
      break

# Match end

proc buildFinalStats(pvp: PvPGameState): seq[PvPStatsNet] =
  for i in 0..<pvp.players.len:
    let s = pvp.stats[i]
    result.add(PvPStatsNet(
      kills: pvp.players[i].kills,
      deaths: s.deaths,
      bestStreak: s.bestStreak,
      shotsFired: s.shotsFired,
      shotsHit: s.shotsHit,
      damageDealt: s.damageDealt,
      pickupsTaken: s.pickupsTaken))

proc sendGameOverPacket(pvp: PvPGameState) =
  var pkt = pvpPacket(pvp, ptGameOver)
  pkt.winnerIndex = pvp.winnerIndex
  pkt.winnerTeam = pvp.winnerTeam.ord
  pkt.endReason = pvp.endReason.ord
  pkt.finalStats = buildFinalStats(pvp)
  pvp.networkManager.sendPacket(pkt)

proc endMatch(pvp: PvPGameState, winnerIndex: int, winnerTeam: PvPTeam, reason: PvPEndReason) =
  ## The single place a match ends. On the host it is broadcast here and then
  ## re-sent every RebroadcastInterval until a rematch starts (see updatePvP);
  ## a client only calls it itself when the host is gone.
  if pvp.gameOver:
    return
  pvp.gameOver = true
  pvp.gameStarted = true
  pvp.isCountingDown = false
  pvp.winnerIndex = winnerIndex
  pvp.winnerTeam = winnerTeam
  pvp.endReason = reason
  pvp.rebroadcastTimer = RebroadcastInterval
  if pvp.networkManager.isHost():
    sendGameOverPacket(pvp)
  fxMatchEnd(pvp)

proc topPlayer(pvp: PvPGameState): tuple[idx, kills: int, tied: bool] =
  ## Connected player with the most kills; `tied` when first place is shared.
  result = (idx: -1, kills: -1, tied: false)
  for i in 0..<pvp.players.len:
    if i < pvp.playerConnected.len and not pvp.playerConnected[i]:
      continue
    let k = pvp.players[i].kills
    if k > result.kills:
      result = (idx: i, kills: k, tied: false)
    elif k == result.kills:
      result.tied = true

proc topTeam(pvp: PvPGameState): tuple[team: PvPTeam, kills: int, tied: bool] =
  result = (team: ptNone, kills: -1, tied: false)
  for team in [ptRed, ptBlue, ptGreen, ptYellow, ptOrange, ptPurple]:
    let k = pvp.teamScores[team].kills
    if k > result.kills:
      result = (team: team, kills: k, tied: false)
    elif k == result.kills:
      result.tied = true

proc checkKillWin(pvp: PvPGameState) =
  ## After a kill: the kill limit. One kill moves one score, so whoever reaches
  ## the limit reaches it alone.
  if pvp.teamsEnabled:
    let top = topTeam(pvp)
    if top.team != ptNone and top.kills >= pvp.config.killLimit:
      endMatch(pvp, -1, top.team, erKillLimit)
  else:
    let top = topPlayer(pvp)
    if top.idx >= 0 and top.kills >= pvp.config.killLimit:
      endMatch(pvp, top.idx, ptNone, erKillLimit)

proc checkEliminationWin(pvp: PvPGameState) =
  ## Respawn set to OFF turns the match into elimination: without this a 1v1
  ## sat on one dead player until the clock ran out.
  var aliveTeams: seq[PvPTeam] = @[]
  var alivePlayers: seq[int] = @[]
  for i in 0..<pvp.players.len:
    if i < pvp.playerConnected.len and not pvp.playerConnected[i]:
      continue
    if pvp.players[i].hp <= 0:
      continue
    alivePlayers.add(i)
    if pvp.players[i].teamId notin aliveTeams:
      aliveTeams.add(pvp.players[i].teamId)
  if pvp.teamsEnabled:
    if aliveTeams.len <= 1:
      endMatch(pvp, -1, (if aliveTeams.len == 1: aliveTeams[0] else: ptNone), erLastStanding)
  elif alivePlayers.len <= 1:
    endMatch(pvp, (if alivePlayers.len == 1: alivePlayers[0] else: -1), ptNone, erLastStanding)

proc endOnTimeLimit(pvp: PvPGameState) =
  ## Most kills wins; a shared first place is a draw rather than a win for
  ## whoever happens to have the lower player index.
  if pvp.teamsEnabled:
    let top = topTeam(pvp)
    endMatch(pvp, -1, (if top.tied: ptNone else: top.team), erTimeLimit)
  else:
    let top = topPlayer(pvp)
    endMatch(pvp, (if top.tied: -1 else: top.idx), ptNone, erTimeLimit)

# Host combat resolution

proc registerKill(pvp: PvPGameState, killer, victim: int) =
  ## Host only. Everything a death decides: score, streaks, callout flags,
  ## the respawn timer, the broadcast, and whether the match is over.
  let victimStats = addr pvp.stats[victim]
  let shutdownStreak = if victimStats.streak >= StreakCalloutMin: victimStats.streak else: 0
  victimStats.streak = 0
  victimStats.multiCount = 0
  inc victimStats.deaths
  clearCombatBuffs(pvp, victim)
  pvp.respawnTimers[victim] = pvp.config.respawnTime

  let validKiller = killer >= 0 and killer < pvp.players.len and killer != victim
  var killerStreak = 0
  var multiKill = 0
  var firstBlood = false
  if validKiller:
    inc pvp.players[killer].kills
    let ks = addr pvp.stats[killer]
    inc ks.streak
    ks.bestStreak = max(ks.bestStreak, ks.streak)
    ks.multiCount =
      if ks.multiCount > 0 and pvp.gameTime - ks.lastKillTime <= MultiKillWindow: ks.multiCount + 1
      else: 1
    ks.lastKillTime = pvp.gameTime
    killerStreak = ks.streak
    multiKill = ks.multiCount
    firstBlood = not pvp.firstBloodDone
    pvp.firstBloodDone = true
    if pvp.teamsEnabled:
      let killerTeam = pvp.players[killer].teamId
      if killerTeam != ptNone:
        inc pvp.teamScores[killerTeam].kills
  if pvp.teamsEnabled:
    let victimTeam = pvp.players[victim].teamId
    if victimTeam != ptNone:
      inc pvp.teamScores[victimTeam].deaths

  var pkt = pvpPacket(pvp, ptPlayerDeath)
  pkt.deadPlayerIndex = victim
  pkt.killerIndex = if validKiller: killer else: -1
  pkt.killerStreak = killerStreak
  pkt.multiKill = multiKill
  pkt.firstBlood = firstBlood
  pkt.shutdownStreak = shutdownStreak
  pvp.networkManager.sendPacket(pkt)
  fxKill(pvp, victim, pkt.killerIndex, killerStreak, multiKill, firstBlood, shutdownStreak)

  checkKillWin(pvp)
  if not pvp.gameOver and pvp.config.respawnTime <= 0:
    checkEliminationWin(pvp)

proc applyHit(pvp: PvPGameState, victim, attacker: int, damage: float32) =
  ## Host only: one bullet reaching a player. FIREWALL.SYS eats the hit whole.
  let p = pvp.players[victim]
  let validAttacker = attacker >= 0 and attacker < pvp.players.len
  if validAttacker:
    inc pvp.stats[attacker].shotsHit
  var pkt = pvpPacket(pvp, ptPlayerDamage)
  pkt.damagedPlayerIndex = victim
  pkt.attackerIndex = if validAttacker: attacker else: -1
  if p.shieldHits > 0:
    dec p.shieldHits
    pkt.damageAmount = 0
    pkt.newHp = p.hp
    pkt.blocked = true
    pvp.networkManager.sendPacket(pkt)
    fxHit(pvp, victim, pkt.attackerIndex, 0, true)
    return

  let dealt = min(damage, max(0.0'f32, p.hp))
  p.hp -= damage
  if validAttacker:
    pvp.stats[attacker].damageDealt += dealt
  pkt.damageAmount = damage
  pkt.newHp = p.hp
  pkt.blocked = false
  pvp.networkManager.sendPacket(pkt)
  fxHit(pvp, victim, pkt.attackerIndex, damage, false)
  if p.hp <= 0:
    registerKill(pvp, pkt.attackerIndex, victim)

proc spawnPvPBullet(pvp: PvPGameState, owner: int, dir: Vector2f, damage: float32) =
  ## Host only: create one bullet and broadcast it.
  let player = pvp.players[owner]
  # Player-specific ID ranges prevent collisions:
  # Player 0 (host): IDs 0-999999, Player 1 (client): IDs 1000000-1999999
  let bulletId = owner * 1000000 + pvp.bulletIdCounter
  let newBullet = Bullet(
    pos: player.pos + dir * (player.radius + 5),
    vel: dir * player.bulletSpeed,
    radius: pvp.config.bulletRadius,
    damage: damage,
    fromPlayer: true,
    lifetime: 0,
    isHoming: false,
    isPiercing: false,
    isExplosive: false,
    bulletId: bulletId,
    bulletSkin: player.bulletSkinType,
    ownerPlayerIndex: owner
  )
  pvp.bulletIdCounter += 1
  pvp.bullets.add(newBullet)
  inc pvp.stats[owner].shotsFired

  # Broadcast bullet spawn to all clients
  var packet = pvpPacket(pvp, ptBulletSpawn)
  packet.bullet = BulletStateNet(
    id: newBullet.bulletId,
    pos: newBullet.pos,
    vel: newBullet.vel,
    radius: newBullet.radius,
    damage: newBullet.damage,
    fromPlayerIndex: owner,
    isPiercing: newBullet.isPiercing,
    isExplosive: newBullet.isExplosive,
    isHoming: newBullet.isHoming,
    bulletSkin: newBullet.bulletSkin
  )
  pvp.networkManager.sendPacket(packet)

proc fireShot(pvp: PvPGameState, owner: int, aimPos: Vector2f) =
  ## Host only: one trigger pull, three bullets under FORK.EXE.
  let player = pvp.players[owner]
  var dir = (aimPos - player.pos).normalize()
  if dir.x == 0 and dir.y == 0:
    dir = newVector2f(0, -1)  # aiming at your own centre: don't spawn a frozen bullet
  spawnPvPBullet(pvp, owner, dir, player.damage)
  if pvp.spreadTimers[owner] > 0:
    let spread = ForkSpreadDeg * PI / 180.0'f32
    spawnPvPBullet(pvp, owner, rotated(dir, -spread), player.damage * ForkSideDamageMult)
    spawnPvPBullet(pvp, owner, rotated(dir, spread), player.damage * ForkSideDamageMult)
  playSound(stShoot, if owner == pvp.localPlayerIndex: 1.0'f32 else: 0.35'f32)

proc applyPlayerInput*(pvp: PvPGameState, playerIndex: int, input: PlayerInput,
                       dt: float32): Vector2f {.discardable.} =
  ## Apply input to a player (used by both client and server). Returns the
  ## velocity the player actually moved with, which the client records for
  ## reconcile replay.

  # Validate player index
  if playerIndex < 0 or playerIndex >= pvp.players.len:
    echo "[PVP ERROR] Invalid player index in applyPlayerInput: ", playerIndex
    return

  let player = pvp.players[playerIndex]

  # Dash presses are consumed even while dead, so a press made during the
  # respawn wait can't fire the instant the player is back.
  let newDash = input.dashSeq > pvp.lastDashSeq[playerIndex]
  if newDash:
    pvp.lastDashSeq[playerIndex] = input.dashSeq

  # Don't process input if player is dead
  if player.hp <= 0:
    return

  if newDash and player.dashTimer <= 0 and player.dashCooldown <= DashAcceptGrace:
    player.dashDir = if input.dashDir.length() >= 0.01'f32: input.dashDir.normalize()
                     else: newVector2f(0, -1)
    player.dashTimer = DashDuration
    player.dashCooldown = DashCooldownTime
    player.dashReadyFlash = 0
    if playerIndex == pvp.localPlayerIndex:
      pvp.dashCorrectionGrace = DashDuration + DashCorrectionGrace

  # Movement. The dash drives velocity directly for its short burst, exactly
  # like PvE; otherwise zero input means zero velocity so snapshots and
  # extrapolation don't carry a stale direction forward after stopping.
  let speed = effectiveMoveSpeed(player)
  if player.dashTimer > 0:
    player.vel = player.dashDir * (speed * DashSpeedMult)
  elif input.moveDir.length() > 0:
    player.vel = input.moveDir * speed
  else:
    player.vel = newVector2f(0, 0)
  if player.vel.x != 0 or player.vel.y != 0:
    movePlayerBy(pvp, player, player.vel * dt)
  result = player.vel

  # Shooting - Only create bullets on the server (host)
  # Clients will receive bullets via ptBulletSpawn packets
  if input.shooting and (pvp.gameTime - player.lastShot) >= effectiveFireInterval(player):
    player.lastShot = pvp.gameTime
    if pvp.networkManager.isHost():
      fireShot(pvp, playerIndex, input.mousePos)
    else:
      # Client: just play sound for local feedback
      playSound(stShoot)

  # Wall placement
  if input.placingWall and player.walls > 0:
    let placingPlayerPos = pvp.players[playerIndex].pos
    # Must be within placement range of the placing player
    let inRange = distance(input.wallPos, placingPlayerPos) <= WALL_PLACEMENT_RANGE
    # Reuse waves-mode validation: not too close to placing player, no overlap with existing walls
    # Pass empty enemy seq, PvP has no enemies
    let validPos = isValidWallPlacement(input.wallPos, placingPlayerPos, pvp.walls, @[], 25,
                                        pvp.screenWidth, pvp.screenHeight)

    if inRange and validPos:
      let newWall = Wall(
        pos: input.wallPos,
        radius: 25,
        hp: 10,
        maxHp: 10,
        duration: 999,
        shootTimer: 0
      )

      # Only the host (authority) mutates the wall list and broadcasts.
      # Clients receive the wall via ptWallPlace to avoid ghost walls from
      # rejected placements.
      if pvp.networkManager.isHost():
        pvp.walls.add(newWall)
        player.walls -= 1

        spawnExplosionPooled(pvp.particlePool, input.wallPos.x, input.wallPos.y, Brown, 15)
        playSound(stPowerUp)

        let wallState = WallStateNet(
          pos: newWall.pos,
          radius: newWall.radius,
          hp: newWall.hp,
          maxHp: newWall.maxHp,
          ownerIndex: playerIndex
        )

        var packet = pvpPacket(pvp, ptWallPlace)
        packet.wall = wallState
        pvp.networkManager.sendPacket(packet)
      else:
        # Client: play sound optimistically, the wall itself appears when
        # ptWallPlace arrives from the host (typically within one RTT).
        playSound(stPowerUp)

proc updateBullets*(pvp: PvPGameState, dt: float32) =
  ## Update bullets (server-side authoritative)
  var i = 0
  while i < pvp.bullets.len:
    # A hit earlier in this pass may have ended the match; nothing after the
    # final kill may score.
    if pvp.gameOver:
      return
    let bullet = pvp.bullets[i]
    bullet.pos = bullet.pos + bullet.vel * dt
    bullet.lifetime += dt

    # Remove if out of bounds or lifetime exceeded
    if bullet.pos.x < 0 or bullet.pos.x > pvp.screenWidth.float32 or
       bullet.pos.y < 0 or bullet.pos.y > pvp.screenHeight.float32 or
       bullet.lifetime > 5.0:

      if pvp.networkManager.isHost():
        var packet = pvpPacket(pvp, ptBulletDestroy)
        packet.bulletId = bullet.bulletId
        pvp.networkManager.sendPacket(packet)

      pvp.bullets.delete(i)
      continue

    # Check player collisions with FRIENDLY FIRE PREVENTION
    var bulletConsumed = false
    for playerIdx in 0..<pvp.players.len:
      let player = pvp.players[playerIdx]
      if player.hp <= 0 or player.invincibilityTimer > 0:
        continue

      # Prevent bullets from hitting their own shooter
      if bullet.ownerPlayerIndex == playerIdx:
        continue  # Skip collision check for the player who shot this bullet

      # PREVENT FRIENDLY FIRE IN TEAM MODE
      if pvp.teamsEnabled and areTeammates(pvp, bullet.ownerPlayerIndex, playerIdx):
        continue  # Skip collision check for teammates

      if distance(bullet.pos, player.pos) < (bullet.radius + player.radius):
        if pvp.networkManager.isHost():
          applyHit(pvp, playerIdx, bullet.ownerPlayerIndex, bullet.damage)
        pvp.bullets.delete(i)
        bulletConsumed = true
        break

    # The bullet was consumed by a player hit; it no longer exists, so skip the
    # wall pass (which would otherwise run against the stale ref and delete the
    # wrong bullet / index -1). delete(i) already shifted the next bullet into i.
    if bulletConsumed:
      continue

    # Check wall collisions
    var hitWall = false
    var wallIdx = 0
    while wallIdx < pvp.walls.len:
      let wall = pvp.walls[wallIdx]
      if distance(bullet.pos, wall.pos) < (bullet.radius + wall.radius):
        if pvp.networkManager.isHost():
          wall.hp -= bullet.damage

          if wall.hp <= 0:
            var packet = pvpPacket(pvp, ptWallDestroy)
            packet.wallIndex = wallIdx
            pvp.networkManager.sendPacket(packet)
            pvp.walls.delete(wallIdx)
          else:
            wallIdx += 1

        hitWall = true
        break
      wallIdx += 1

    if hitWall:
      pvp.bullets.delete(i)
      continue

    i += 1

proc tickPvPTimers(pvp: PvPGameState, dt: float32) =
  ## Buff, dash and invulnerability clocks. Runs on host AND clients so HUD
  ## bars and dash rings drain smoothly between snapshots; the host's values
  ## are authoritative and each snapshot re-syncs them.
  for i in 0..<pvp.players.len:
    let p = pvp.players[i]
    if p.invincibilityTimer > 0:
      p.invincibilityTimer -= dt
    if p.speedBoostTimer > 0:
      p.speedBoostTimer = max(0.0'f32, p.speedBoostTimer - dt)
    if p.fireRateBoostTimer > 0:
      p.fireRateBoostTimer = max(0.0'f32, p.fireRateBoostTimer - dt)
    if pvp.spreadTimers[i] > 0:
      pvp.spreadTimers[i] = max(0.0'f32, pvp.spreadTimers[i] - dt)
    if p.dashTimer > 0:
      p.dashTimer = max(0.0'f32, p.dashTimer - dt)
    if p.dashCooldown > 0:
      p.dashCooldown -= dt
      if p.dashCooldown <= 0:
        # Snap to 0 and arm the recharged flash (see updatePlayer in player.nim).
        p.dashCooldown = 0
        p.dashReadyFlash = DashReadyFlashTime
    if p.dashReadyFlash > 0:
      p.dashReadyFlash = max(0.0'f32, p.dashReadyFlash - dt)

proc respawnPlayer(pvp: PvPGameState, idx: int) =
  ## Host only. Back at the spawn point with full HP, the starting wall stock,
  ## a ready dash and brief invulnerability.
  let p = pvp.players[idx]
  p.hp = pvp.config.startHp
  p.pos = spawnPositionFor(pvp, idx)
  p.vel = newVector2f(0, 0)
  p.walls = pvp.config.startWalls
  p.invincibilityTimer = RespawnInvulnTime
  clearCombatBuffs(pvp, idx)
  var pkt = pvpPacket(pvp, ptPlayerRespawn)
  pkt.respawnIndex = idx
  pkt.respawnPos = p.pos
  pvp.networkManager.sendPacket(pkt)
  fxRespawn(pvp, idx)

proc updatePvPServer*(pvp: PvPGameState, dt: float32) =
  ## Server-side update (host only)
  pvp.serverTick += 1
  pvp.gameTime += dt

  # NOTE: Host does NOT use interpolation for display - host is the server with authoritative state
  # Only clients interpolate remote players to smooth network latency

  # Blend out any accumulated host-side correction every frame (same mechanism as client)
  let localIdx = pvp.localPlayerIndex
  if abs(pvp.localPosCorrection.x) > 0.01 or abs(pvp.localPosCorrection.y) > 0.01:
    let corrRate = min(dt * 15.0, 1.0)
    pvp.players[localIdx].pos.x += pvp.localPosCorrection.x * corrRate
    pvp.players[localIdx].pos.y += pvp.localPosCorrection.y * corrRate
    pvp.localPosCorrection.x *= (1.0 - corrRate)
    pvp.localPosCorrection.y *= (1.0 - corrRate)
    if abs(pvp.localPosCorrection.x) < 0.01: pvp.localPosCorrection.x = 0
    if abs(pvp.localPosCorrection.y) < 0.01: pvp.localPosCorrection.y = 0

  # Update respawn timers
  for i in 0..<pvp.players.len:
    # Disconnected players never respawn
    if i < pvp.playerConnected.len and not pvp.playerConnected[i]: continue
    if pvp.players[i].hp <= 0 and pvp.respawnTimers[i] > 0:
      pvp.respawnTimers[i] -= dt
      if pvp.respawnTimers[i] <= 0:
        respawnPlayer(pvp, i)

  # Buff / dash / invulnerability clocks
  tickPvPTimers(pvp, dt)

  # NOTE: Host's input is NOT applied here - it's already applied via prediction in main update
  # This ensures fairness: both host and client use the same predict->reconcile flow
  # Server simulation just processes all remote clients' inputs

  # Apply all clients' inputs (stored from network)
  for i in 0..<pvp.players.len:
    if i < pvp.playerConnected.len and not pvp.playerConnected[i]: continue
    if i != pvp.localPlayerIndex and pvp.lastInputs[i].tick >= 0:
      applyPlayerInput(pvp, i, pvp.lastInputs[i], dt)
      # The stored input is re-applied every host frame until the next one
      # arrives, so one-shot actions must be consumed here or a single click
      # would retry the wall placement for every frame of that gap. (Dashes
      # are immune by design: dashSeq only fires when it goes up.)
      pvp.lastInputs[i].placingWall = false

  # Check time limit (0 = unlimited)
  if pvp.config.timeLimit > 0 and pvp.gameTime >= pvp.config.timeLimit and not pvp.gameOver:
    endOnTimeLimit(pvp)

  # Update bullets
  updateBullets(pvp, dt)

  # Arena packages
  if not pvp.gameOver:
    updatePortsServer(pvp, dt)

  # Decay PvP walls over time (server-authoritative)
  # Walls lose 1 HP/sec passively, destroyed walls are broadcast immediately.
  const PVP_WALL_DECAY_RATE = 0.3  # HP per second
  var wallIdx = 0
  while wallIdx < pvp.walls.len:
    let wall = pvp.walls[wallIdx]
    wall.hp -= PVP_WALL_DECAY_RATE * dt
    if wall.hp <= 0:
      spawnExplosionPooled(pvp.particlePool, wall.pos.x, wall.pos.y, Brown, 10)
      var pkt = pvpPacket(pvp, ptWallDestroy)
      pkt.wallIndex = wallIdx
      pvp.networkManager.sendPacket(pkt)
      pvp.walls.delete(wallIdx)
    else:
      wallIdx += 1

  # Update particles
  updateParticlePool(pvp.particlePool, dt)

  # Send game state snapshot at fixed rate (configured per-match)
  if pvp.gameTime - pvp.lastSnapshotTime >= pvp.config.snapshotRate:
    pvp.lastSnapshotTime = pvp.gameTime

    # Build state snapshot
    var bulletStates: seq[BulletStateNet] = @[]
    for bullet in pvp.bullets:
      bulletStates.add(BulletStateNet(
        id: bullet.bulletId,
        pos: bullet.pos,
        vel: bullet.vel,
        radius: bullet.radius,
        damage: bullet.damage,
        fromPlayerIndex: bullet.ownerPlayerIndex,
        isPiercing: bullet.isPiercing,
        isExplosive: bullet.isExplosive,
        isHoming: bullet.isHoming,
        bulletSkin: bullet.bulletSkin
      ))

    var wallStates: seq[WallStateNet] = @[]
    for wall in pvp.walls:
      wallStates.add(WallStateNet(
        pos: wall.pos,
        radius: wall.radius,
        hp: wall.hp,
        maxHp: wall.maxHp,
        ownerIndex: 0  # Track owner if needed
      ))

    # Build player states dynamically
    var playerStates: seq[PlayerStateNet] = @[]
    for i in 0..<pvp.players.len:
      let snap_nick = if i < pvp.playerNicknames.len: pvp.playerNicknames[i] else: "P" & $(i + 1)
      playerStates.add(PlayerStateNet(
        playerIndex: i,
        isActive: pvp.players[i].hp > 0,  # Mark if player is alive
        pos: pvp.players[i].pos,
        vel: pvp.players[i].vel,
        hp: pvp.players[i].hp,
        maxHp: pvp.players[i].maxHp,
        coins: pvp.players[i].coins,
        kills: pvp.players[i].kills,
        walls: pvp.players[i].walls,
        damage: pvp.players[i].damage,
        speed: pvp.players[i].speed,
        fireRate: pvp.players[i].fireRate,
        bulletSpeed: pvp.players[i].bulletSpeed,
        invincibilityTimer: pvp.players[i].invincibilityTimer,
        teamId: pvp.players[i].teamId.ord,  # Send as int
        skinType: pvp.players[i].skinType,
        bulletSkinType: pvp.players[i].bulletSkinType,
        shapeType: pvp.players[i].shapeType,
        particleSkinType: pvp.players[i].particleSkinType,
        nickname: snap_nick,
        deaths: pvp.stats[i].deaths,
        streak: pvp.stats[i].streak,
        dashTimer: pvp.players[i].dashTimer,
        dashCooldown: pvp.players[i].dashCooldown,
        shieldHits: pvp.players[i].shieldHits,
        speedBoostTimer: pvp.players[i].speedBoostTimer,
        fireRateBoostTimer: pvp.players[i].fireRateBoostTimer,
        spreadTimer: pvp.spreadTimers[i]
      ))

    var portStates: seq[PortStateNet] = @[]
    for port in pvp.ports:
      portStates.add(PortStateNet(kind: port.kind.ord, active: port.active, timer: port.timer))

    let gameState = NetworkGameState(
      tick: pvp.serverTick,
      timestamp: pvp.gameTime,
      maxPlayers: pvp.maxPlayers,
      players: playerStates,
      bullets: bulletStates,
      walls: wallStates,
      ports: portStates
    )

    var packet = pvpPacket(pvp, ptGameState)
    packet.state = gameState
    pvp.networkManager.sendPacket(packet)

    # Host should also reconcile their own state for fairness
    # This ensures host experiences same prediction+reconciliation as client
    # Apply server state to host (inline reconciliation for simplicity)
    let localIdx = pvp.localPlayerIndex

    # Update interpolation states for all remote players (clients)
    for i in 0..<pvp.players.len:
      if i != localIdx and i < gameState.players.len and i < pvp.playerInterpStates.len:
        let interpState = addr pvp.playerInterpStates[i]

        # Move current target to previous
        if interpState.hasData:
          interpState.prevPos = interpState.targetPos
          interpState.prevVel = interpState.targetVel
          interpState.prevTime = interpState.targetTime
        else:
          # First snapshot - initialize with current position
          interpState.prevPos = gameState.players[i].pos
          interpState.prevVel = gameState.players[i].vel
          interpState.prevTime = gameState.timestamp

        # Set new target from game state
        interpState.targetPos = gameState.players[i].pos
        interpState.targetVel = gameState.players[i].vel
        interpState.targetTime = gameState.timestamp
        interpState.hasData = true

        # Update non-positional data immediately
        pvp.players[i].vel = gameState.players[i].vel
        pvp.players[i].hp = gameState.players[i].hp
        pvp.players[i].maxHp = gameState.players[i].maxHp
        pvp.players[i].coins = gameState.players[i].coins
        pvp.players[i].kills = gameState.players[i].kills
        pvp.players[i].walls = gameState.players[i].walls
        pvp.players[i].damage = gameState.players[i].damage
        pvp.players[i].speed = gameState.players[i].speed
        pvp.players[i].fireRate = gameState.players[i].fireRate
        pvp.players[i].bulletSpeed = gameState.players[i].bulletSpeed
        pvp.players[i].invincibilityTimer = gameState.players[i].invincibilityTimer

    # Reconcile host's own player - TRUST CLIENT PREDICTION
    # Even the host should trust their local prediction to maintain consistency.
    # Thresholds scale with player speed so fast-moving players don't trigger
    # constant correction from normal prediction drift.
    if localIdx >= 0 and localIdx < gameState.players.len:
      let serverPos = gameState.players[localIdx].pos
      let clientPos = pvp.players[localIdx].pos
      let posDiff = sqrt((serverPos.x - clientPos.x) * (serverPos.x - clientPos.x) +
                         (serverPos.y - clientPos.y) * (serverPos.y - clientPos.y))

      # Scale thresholds proportionally to speed (baseline 200 px/s)
      let speedFactor = max(1.0, pvp.players[localIdx].speed / 200.0)
      let snapThreshold = 150.0 * speedFactor
      let corrThreshold = 50.0 * speedFactor

      if posDiff > snapThreshold:
        # LARGE desync - snap immediately
        pvp.players[localIdx].pos = serverPos
        pvp.localPosCorrection = newVector2f(0, 0)
      elif posDiff > corrThreshold:
        # MEDIUM desync: accumulate for per-frame blending (replaces old one-shot lerp)
        pvp.localPosCorrection.x = serverPos.x - pvp.players[localIdx].pos.x
        pvp.localPosCorrection.y = serverPos.y - pvp.players[localIdx].pos.y
      # else: SMALL desync - trust prediction completely

      # Always update other host data from server
      pvp.players[localIdx].vel = gameState.players[localIdx].vel
      pvp.players[localIdx].hp = gameState.players[localIdx].hp
      pvp.players[localIdx].maxHp = gameState.players[localIdx].maxHp
      pvp.players[localIdx].coins = gameState.players[localIdx].coins
      pvp.players[localIdx].kills = gameState.players[localIdx].kills
      pvp.players[localIdx].walls = gameState.players[localIdx].walls
      pvp.players[localIdx].damage = gameState.players[localIdx].damage
      pvp.players[localIdx].speed = gameState.players[localIdx].speed
      pvp.players[localIdx].fireRate = gameState.players[localIdx].fireRate
      pvp.players[localIdx].bulletSpeed = gameState.players[localIdx].bulletSpeed
      pvp.players[localIdx].invincibilityTimer = gameState.players[localIdx].invincibilityTimer

proc updatePvPClient*(pvp: PvPGameState, dt: float32) =
  ## Client-side update (prediction + reconciliation)
  ## Input is now applied immediately in main updatePvP for responsive feel
  ## This function handles additional client-only updates
  pvp.gameTime += dt

  # Mirror server-side wall decay locally so the health bar drains smoothly
  # every frame rather than jumping at each snapshot interval.
  # The snapshot will correct any drift, ptWallDestroy handles actual removal.
  const PVP_WALL_DECAY_RATE = 0.3
  for wall in pvp.walls:
    wall.hp = max(0.01, wall.hp - PVP_WALL_DECAY_RATE * dt)

  # Buff / dash clocks between snapshots, and the port countdowns (a port only
  # becomes active when a snapshot says so: the drop is the host's decision).
  tickPvPTimers(pvp, dt)
  for port in pvp.ports.mitems:
    if not port.active:
      port.timer = max(0.0'f32, port.timer - dt)
  if pvp.dashCorrectionGrace > 0:
    pvp.dashCorrectionGrace = max(0.0'f32, pvp.dashCorrectionGrace - dt)

  # Smoothly bleed out any accumulated position correction from reconcileState.
  # Running this every frame (rather than once per snapshot) prevents the
  # 33ms-interval jitter that the old per-snapshot lerp caused at high speeds.
  let localIdx = pvp.localPlayerIndex
  if abs(pvp.localPosCorrection.x) > 0.01 or abs(pvp.localPosCorrection.y) > 0.01:
    let corrRate = min(dt * 15.0, 1.0)  # ~15 corrections/sec blend rate
    pvp.players[localIdx].pos.x += pvp.localPosCorrection.x * corrRate
    pvp.players[localIdx].pos.y += pvp.localPosCorrection.y * corrRate
    pvp.localPosCorrection.x *= (1.0 - corrRate)
    pvp.localPosCorrection.y *= (1.0 - corrRate)
    if abs(pvp.localPosCorrection.x) < 0.01: pvp.localPosCorrection.x = 0
    if abs(pvp.localPosCorrection.y) < 0.01: pvp.localPosCorrection.y = 0

  # Update interpolation for remote players (only if enabled)
  if pvp.interpolationEnabled:
    let renderTime = pvp.gameTime - pvp.interpDelay

    for i in 0..<pvp.players.len:
      if i == pvp.localPlayerIndex:
        continue  # Skip local player (uses prediction)

      if i >= pvp.playerInterpStates.len:
        continue

      let interpState = addr pvp.playerInterpStates[i]

      if not interpState.hasData:
        continue  # No interpolation data yet

      # Calculate interpolation factor between prev and target
      let timeDiff = interpState.targetTime - interpState.prevTime
      if timeDiff <= 0:
        # Invalid time diff, just use target
        pvp.players[i].pos = interpState.targetPos
        continue

      let t = (renderTime - interpState.prevTime) / timeDiff

      if t < 0:
        # Render time is before prev, use prev
        pvp.players[i].pos = interpState.prevPos
      elif t > 1.0:
        # Render time is past the latest snapshot: dead-reckon with velocity.
        # Cap at 1.5x snapshot interval, enough to cover one late packet without
        # letting bad extrapolation run wild when the connection is poor.
        let extraDt = min((t - 1.0) * timeDiff, pvp.config.snapshotRate * 1.5)
        pvp.players[i].pos.x = interpState.targetPos.x + interpState.targetVel.x * extraDt
        pvp.players[i].pos.y = interpState.targetPos.y + interpState.targetVel.y * extraDt
        # Clamp to arena
        pvp.players[i].pos.x = clamp(pvp.players[i].pos.x, pvp.players[i].radius, pvp.screenWidth.float32 - pvp.players[i].radius)
        pvp.players[i].pos.y = clamp(pvp.players[i].pos.y, pvp.players[i].radius, pvp.screenHeight.float32 - pvp.players[i].radius)
      else:
        # Interpolate between prev and target
        pvp.players[i].pos.x = interpState.prevPos.x + (interpState.targetPos.x - interpState.prevPos.x) * t
        pvp.players[i].pos.y = interpState.prevPos.y + (interpState.targetPos.y - interpState.prevPos.y) * t

  # Update bullets locally for smooth interpolation between server snapshots
  # Server will reconcile with authoritative state
  var i = 0
  while i < pvp.bullets.len:
    let bullet = pvp.bullets[i]
    bullet.pos = bullet.pos + bullet.vel * dt
    bullet.lifetime += dt

    # Remove if out of bounds or lifetime exceeded (will be reconciled by server)
    if bullet.pos.x < 0 or bullet.pos.x > pvp.screenWidth.float32 or
       bullet.pos.y < 0 or bullet.pos.y > pvp.screenHeight.float32 or
       bullet.lifetime > 5.0:
      pvp.bullets.delete(i)
      continue

    # Client-side collision detection: check if remote bullets hit players or walls
    # This provides immediate visual feedback without waiting for server reconciliation
    var shouldRemove = false

    # Check collision with all players (not just local player). Same filters as
    # the host: a bullet the host lets through (teammate, respawn-invulnerable)
    # would otherwise vanish here and pop back in with the next snapshot.
    for playerIdx in 0..<pvp.players.len:
      let player = pvp.players[playerIdx]
      if player.hp <= 0 or bullet.ownerPlayerIndex == playerIdx:
        continue  # Skip dead players and the shooter
      if player.invincibilityTimer > 0:
        continue
      if pvp.teamsEnabled and areTeammates(pvp, bullet.ownerPlayerIndex, playerIdx):
        continue

      if distance(bullet.pos, player.pos) < (bullet.radius + player.radius):
        shouldRemove = true
        break

    # Check collision with walls
    if not shouldRemove:
      for wall in pvp.walls:
        if distance(bullet.pos, wall.pos) < (bullet.radius + wall.radius):
          shouldRemove = true
          break

    if shouldRemove:
      pvp.bullets.delete(i)
      continue

    i += 1

  # Update particles locally
  updateParticlePool(pvp.particlePool, dt)

proc reconcileState*(pvp: PvPGameState, serverState: NetworkGameState) =
  ## Reconcile client state with authoritative server state
  ## Server is ALWAYS authoritative - client just renders smoothly

  let localIdx = pvp.localPlayerIndex
  # The host sends every player slot, and both sides size their slots from the
  # same roster, so a snapshot shorter than ours is malformed. Drop it rather
  # than index past its end (unchecked in -d:danger builds).
  if serverState.players.len < pvp.players.len or
     localIdx < 0 or localIdx >= pvp.players.len:
    return

  # Sync client's server tick and game time from the authoritative server snapshot
  pvp.serverTick = serverState.tick
  pvp.gameTime = serverState.timestamp

  # Update all remote players - use interpolation instead of direct snap
  for i in 0..<pvp.players.len:
    if i != localIdx:
      # Update interpolation state for this remote player
      if i < pvp.playerInterpStates.len:
        let interpState = addr pvp.playerInterpStates[i]

        # Move current target to previous
        if interpState.hasData:
          interpState.prevPos = interpState.targetPos
          interpState.prevVel = interpState.targetVel
          interpState.prevTime = interpState.targetTime
        else:
          # First snapshot - initialize with current position
          interpState.prevPos = serverState.players[i].pos
          interpState.prevVel = serverState.players[i].vel
          interpState.prevTime = serverState.timestamp

        # Set new target from server
        interpState.targetPos = serverState.players[i].pos
        interpState.targetVel = serverState.players[i].vel
        interpState.targetTime = serverState.timestamp
        interpState.hasData = true

      # Update non-positional data immediately (no interpolation needed)
      pvp.players[i].vel = serverState.players[i].vel
      pvp.players[i].hp = serverState.players[i].hp
      pvp.players[i].maxHp = serverState.players[i].maxHp
      pvp.players[i].coins = serverState.players[i].coins
      pvp.players[i].kills = serverState.players[i].kills
      pvp.players[i].walls = serverState.players[i].walls
      pvp.players[i].damage = serverState.players[i].damage
      pvp.players[i].speed = serverState.players[i].speed
      pvp.players[i].fireRate = serverState.players[i].fireRate
      pvp.players[i].bulletSpeed = serverState.players[i].bulletSpeed
      pvp.players[i].invincibilityTimer = serverState.players[i].invincibilityTimer
      pvp.players[i].skinType = serverState.players[i].skinType
      pvp.players[i].bulletSkinType = serverState.players[i].bulletSkinType
      pvp.players[i].shapeType = serverState.players[i].shapeType
      pvp.players[i].particleSkinType = serverState.players[i].particleSkinType
      pvp.players[i].teamId = teamFromInt(serverState.players[i].teamId)  # Sync team
      pvp.players[i].dashTimer = serverState.players[i].dashTimer
      pvp.players[i].dashCooldown = serverState.players[i].dashCooldown
      pvp.players[i].shieldHits = serverState.players[i].shieldHits
      pvp.players[i].speedBoostTimer = serverState.players[i].speedBoostTimer
      pvp.players[i].fireRateBoostTimer = serverState.players[i].fireRateBoostTimer
      pvp.spreadTimers[i] = serverState.players[i].spreadTimer
      pvp.stats[i].deaths = serverState.players[i].deaths
      pvp.stats[i].streak = serverState.players[i].streak
      # Sync nickname if server provides it and we don't have it yet
      if serverState.players[i].nickname.len > 0:
        while pvp.playerNicknames.len <= i:
          pvp.playerNicknames.add("P" & $(pvp.playerNicknames.len + 1))
        if pvp.playerNicknames[i].len == 0 or pvp.playerNicknames[i] == "P" & $(i + 1):
          pvp.playerNicknames[i] = serverState.players[i].nickname

  # Local player - TRUST CLIENT PREDICTION, only reconcile on large desyncs.
  # After applying the server's authoritative position we re-apply any inputs
  # the server hasn't seen yet (client-side prediction replay), so the player
  # stays responsive and doesn't rubber-band at high speeds.
  let serverPos = serverState.players[localIdx].pos
  let clientPos = pvp.players[localIdx].pos

  let posDiff = sqrt((serverPos.x - clientPos.x) * (serverPos.x - clientPos.x) +
                     (serverPos.y - clientPos.y) * (serverPos.y - clientPos.y))

  # Scale thresholds proportionally to speed (baseline 200 px/s)
  let speedFactor = max(1.0, effectiveMoveSpeed(pvp.players[localIdx]) / 200.0)
  let snapThreshold = 150.0 * speedFactor
  let corrThreshold = 50.0 * speedFactor

  if posDiff > snapThreshold:
    # LARGE desync - snap immediately to fix severe issues, clear pending correction
    pvp.players[localIdx].pos = serverPos
    pvp.localPosCorrection = newVector2f(0, 0)
  elif posDiff > corrThreshold and pvp.dashCorrectionGrace <= 0:
    # MEDIUM desync: accumulate the full error into localPosCorrection so that
    # updatePvPClient can bleed it out smoothly every frame instead of jumping.
    # This replaces the old one-shot per-snapshot lerp that caused jitter.
    # Skipped just after a dash: the host replays the burst one latency later,
    # so these snapshots trail the dash and "correcting" toward them would
    # yank the player back mid-dodge. Real drift is caught once the grace ends.
    pvp.localPosCorrection.x = serverPos.x - pvp.players[localIdx].pos.x
    pvp.localPosCorrection.y = serverPos.y - pvp.players[localIdx].pos.y
  elif posDiff > 1.0 and
       pvp.localIdleTime >= IdleSettleTime + pvp.networkManager.getLatency() / 1000.0'f32:
    # SMALL desync while standing still: the host has caught up with the stop,
    # so settle onto its position (bled out smoothly like any correction).
    pvp.localPosCorrection.x = serverPos.x - pvp.players[localIdx].pos.x
    pvp.localPosCorrection.y = serverPos.y - pvp.players[localIdx].pos.y
  # else: SMALL desync while moving - trust client prediction completely

  # Replay unacknowledged inputs (movement only) so the client stays ahead of
  # the acknowledged server position rather than snapping backward.
  # Keep inputs captured AFTER the server snapshot was taken.
  var replayCount = 0
  for pending in pvp.pendingInputs:
    if pending.capturedAt > serverState.timestamp:
      replayMovementInput(pvp, localIdx, pending.vel, pending.input.dt)
      inc replayCount
  # Discard inputs the server has already processed
  pvp.pendingInputs = pvp.pendingInputs.filterIt(it.capturedAt > serverState.timestamp)

  # Always update all other data from server
  pvp.players[localIdx].vel = serverState.players[localIdx].vel
  pvp.players[localIdx].hp = serverState.players[localIdx].hp
  pvp.players[localIdx].maxHp = serverState.players[localIdx].maxHp
  pvp.players[localIdx].coins = serverState.players[localIdx].coins
  pvp.players[localIdx].kills = serverState.players[localIdx].kills
  pvp.players[localIdx].walls = serverState.players[localIdx].walls
  pvp.players[localIdx].damage = serverState.players[localIdx].damage
  pvp.players[localIdx].speed = serverState.players[localIdx].speed
  pvp.players[localIdx].fireRate = serverState.players[localIdx].fireRate
  pvp.players[localIdx].bulletSpeed = serverState.players[localIdx].bulletSpeed
  pvp.players[localIdx].invincibilityTimer = serverState.players[localIdx].invincibilityTimer
  pvp.players[localIdx].teamId = teamFromInt(serverState.players[localIdx].teamId)
  # Buffs are the host's call; the dash timers are NOT copied. Like position,
  # the local dash is predicted, and a snapshot taken before the host saw the
  # press would reset the cooldown and let the player "dash" twice.
  pvp.players[localIdx].shieldHits = serverState.players[localIdx].shieldHits
  pvp.players[localIdx].speedBoostTimer = serverState.players[localIdx].speedBoostTimer
  pvp.players[localIdx].fireRateBoostTimer = serverState.players[localIdx].fireRateBoostTimer
  pvp.spreadTimers[localIdx] = serverState.players[localIdx].spreadTimer
  pvp.stats[localIdx].deaths = serverState.players[localIdx].deaths
  pvp.stats[localIdx].streak = serverState.players[localIdx].streak

  # Ports. A length mismatch means the rules disagree (packages toggled), so
  # rebuild from the layout and adopt the host's view.
  if serverState.ports.len != pvp.ports.len:
    pvp.config.pickupsEnabled = serverState.ports.len > 0
    resetPorts(pvp)
  for portIdx in 0..<min(serverState.ports.len, pvp.ports.len):
    let ps = serverState.ports[portIdx]
    pvp.ports[portIdx].kind = packageFromInt(ps.kind)
    pvp.ports[portIdx].active = ps.active
    pvp.ports[portIdx].timer = ps.timer

  # Update bullets from server, preserving locally-predicted bullets.
  #
  # The server snapshot is always a few frames behind the client due to network
  # latency.  If we blindly replace pvp.bullets with the snapshot contents, any
  # bullet the local player fired in the last RTT/2 ms gets destroyed for one
  # frame and then reappears, producing the visible "laggy start" stutter.
  #
  # Strategy:
  #   1. Collect the set of bullet IDs that the server knows about.
  #   2. Keep any locally-owned predicted bullet that the server hasn't yet
  #      acknowledged (its ID is absent from the snapshot).
  #   3. Add/update everything the server knows about.
  #
  # "Locally-owned" means ownerPlayerIndex == localIdx, which is the only
  # player whose bullets the client predicts.  Remote bullets are always
  # authoritative from the server.

  # Step 1: build the set of server-known IDs
  var serverBulletIds: seq[int] = @[]
  for bulletState in serverState.bullets:
    serverBulletIds.add(bulletState.id)

  # Step 2: keep predicted bullets not yet in the snapshot
  var predictedBullets: seq[Bullet] = @[]
  for existingBullet in pvp.bullets:
    if existingBullet.ownerPlayerIndex == localIdx and
       existingBullet.bulletId notin serverBulletIds:
      predictedBullets.add(existingBullet)

  # Step 3: rebuild from server state, then append surviving predictions
  pvp.bullets = @[]
  for bulletState in serverState.bullets:
    # Skip bullets that were recently destroyed (to prevent snapshot resurrection)
    if bulletState.id in pvp.recentlyDestroyedBullets:
      continue

    let bullet = Bullet(
      pos: bulletState.pos,
      vel: bulletState.vel,
      radius: bulletState.radius,
      damage: bulletState.damage,
      fromPlayer: true,
      lifetime: 0,
      isHoming: bulletState.isHoming,
      isPiercing: bulletState.isPiercing,
      isExplosive: bulletState.isExplosive,
      bulletId: bulletState.id,
      bulletSkin: bulletState.bulletSkin,
      ownerPlayerIndex: bulletState.fromPlayerIndex  # Preserve owner from server
    )
    pvp.bullets.add(bullet)

  for predictedBullet in predictedBullets:
    pvp.bullets.add(predictedBullet)

  # Clear recently destroyed bullets after reconciling (they're old now)
  pvp.recentlyDestroyedBullets = @[]

  # Update walls from server (authoritative full-replace)
  pvp.walls = @[]
  for wallState in serverState.walls:
    let wall = Wall(
      pos: wallState.pos,
      radius: wallState.radius,
      hp: wallState.hp,
      maxHp: wallState.maxHp,
      duration: 999,
      shootTimer: 0
    )
    pvp.walls.add(wall)

  # Recalculate team scores from player data
  if pvp.teamsEnabled:
    for team in PvPTeam:
      pvp.teamScores[team] = TeamScore(kills: 0, deaths: 0)

    for i in 0..<pvp.players.len:
      let team = pvp.players[i].teamId
      if team != ptNone:
        pvp.teamScores[team].kills += pvp.players[i].kills

proc connectedPlayerCount*(pvp: PvPGameState): int =
  ## Count how many players are still connected (not disconnected)
  for i in 0..<pvp.players.len:
    if i < pvp.playerConnected.len and pvp.playerConnected[i]:
      result += 1

proc connectedTeams*(pvp: PvPGameState): seq[PvPTeam] =
  ## Return list of teams that still have at least one connected player
  for i in 0..<pvp.players.len:
    if i < pvp.playerConnected.len and pvp.playerConnected[i]:
      let team = pvp.players[i].teamId
      if team != ptNone and team notin result:
        result.add(team)

proc disconnectPlayer*(pvp: PvPGameState, playerIndex: int) =
  ## Remove a player from active play without ending the game.
  if playerIndex < 0 or playerIndex >= pvp.players.len: return
  pvp.playerConnected[playerIndex] = false
  pvp.players[playerIndex].hp = 0
  pvp.respawnTimers[playerIndex] = 0  # Stop any pending respawn
  echo "[PVP] Player ", playerIndex, " removed from active play"

proc checkLastSideStanding*(pvp: PvPGameState): bool =
  ## Returns true if the game should end because only one side remains.
  if pvp.teamsEnabled:
    return pvp.connectedTeams().len <= 1
  else:
    return pvp.connectedPlayerCount() <= 1

proc markLeft(pvp: PvPGameState, playerIndex: int) =
  ## Feed row + slot bookkeeping for a player who dropped out.
  if playerIndex < 0 or playerIndex >= pvp.players.len: return
  if playerIndex < pvp.playerConnected.len and pvp.playerConnected[playerIndex]:
    pvp.pushFeed(KillFeedEntry(kind: kfLeft, actor: playerIndex, target: -1, age: 0))
  pvp.disconnectPlayer(playerIndex)

proc canRematch*(pvp: PvPGameState): bool =
  ## Host: a rematch needs someone left to play against.
  pvp.networkManager.isHost() and pvp.gameOver and not pvp.checkLastSideStanding()

proc restartMatch*(pvp: PvPGameState) =
  ## Host: next match, same lobby. Clients follow the moment any packet with
  ## the new matchId reaches them, normally the ptGameStart sent right here.
  if not canRematch(pvp): return
  inc pvp.matchId
  resetMatchState(pvp)
  startCountdown(pvp)
  playSound(stMenuSelect)

proc adoptMatch(pvp: PvPGameState, newMatchId: int) =
  ## Client: the host has moved on to a newer match; reset and join it. The
  ## caller decides whether that match is still counting down or already live.
  pvp.matchId = newMatchId
  resetMatchState(pvp)
  pvp.isCountingDown = false
  echo "[PVP] Joining rematch ", newMatchId

proc handleDisconnect*(pvp: PvPGameState, disconnectedIndex: int, reason: string) =
  ## Handle a player disconnecting - either end the game (2-player) or
  ## remove them and continue (3+ player).
  let wasTimeout = reason == "Connection timeout"
  let alreadyOver = pvp.gameOver

  # The slot is marked even after the match: the rematch roster reads it, and
  # a client on the result screen needs to know the host is gone. Only the
  # outcome of a finished match stays untouched.
  pvp.markLeft(disconnectedIndex)
  if alreadyOver:
    return

  # In a 2-player game there's no one left to play against, end immediately.
  if pvp.maxPlayers <= 2:
    endMatch(pvp, pvp.localPlayerIndex, ptNone,
             if wasTimeout: erOpponentDisconnected else: erOpponentForfeited)
    return

  # A client only ever talks to the host, so any disconnect it sees means the
  # server itself is gone: nothing can keep the match going.
  if pvp.networkManager.isClient():
    endMatch(pvp, -1, ptNone, erHostLeft)
    return

  # 3+ player game: check if a winner has emerged now that someone left.
  if pvp.checkLastSideStanding():
    if pvp.teamsEnabled:
      let remaining = pvp.connectedTeams()
      endMatch(pvp, -1, (if remaining.len == 1: remaining[0] else: ptNone), erLastStanding)
    else:
      # Find the last connected player
      var lastPlayer = -1
      for i in 0..<pvp.players.len:
        if i < pvp.playerConnected.len and pvp.playerConnected[i]:
          lastPlayer = i
          break
      endMatch(pvp, lastPlayer, ptNone, erLastStanding)
  else:
    # Game continues, log who dropped out
    echo "[PVP] ", pvp.playerName(disconnectedIndex), " dropped out, game continues with ",
         pvp.connectedPlayerCount(), " players remaining"

proc endReasonFromInt(value: int): PvPEndReason =
  if value < ord(low(PvPEndReason)) or value > ord(high(PvPEndReason)): erNone
  else: PvPEndReason(value)

proc handleNetworkEvents*(pvp: PvPGameState) =
  ## Process all network events
  # Create callback to provide host's cosmetics when accepting connections
  proc getHostCosmetics(): tuple[skinType, bulletSkinType, shapeType, particleSkinType: int] =
    return (
      skinType: pvp.players[0].skinType,
      bulletSkinType: pvp.players[0].bulletSkinType,
      shapeType: pvp.players[0].shapeType,
      particleSkinType: pvp.players[0].particleSkinType
    )

  let events = pvp.networkManager.pollEvents(getHostCosmetics)

  for event in events:
    case event.kind
    of neConnect:
      echo "[PVP] Player ", event.connectPlayerIndex, " connected"
      # Apply remote player's cosmetics
      let playerIdx = event.connectPlayerIndex
      if playerIdx >= 0 and playerIdx < pvp.players.len:
        pvp.players[playerIdx].skinType = event.remoteSkinType
        pvp.players[playerIdx].bulletSkinType = event.remoteBulletSkinType
        pvp.players[playerIdx].shapeType = event.remoteShapeType
        pvp.players[playerIdx].particleSkinType = event.remoteParticleSkinType

    of neReceive:
      let packet = event.packet

      # Match generation gate. Older = still in flight from a finished match
      # (a rebroadcast ptGameOver must not end the new one). Newer = the host
      # already restarted; a client joins it on the spot, even if the
      # ptGameStart itself was the datagram that got lost.
      if packet.matchId < pvp.matchId:
        continue
      if packet.matchId > pvp.matchId:
        if not pvp.networkManager.isClient():
          continue
        adoptMatch(pvp, packet.matchId)
        if packet.kind != ptGameStart:
          pvp.gameStarted = true
          pvp.networkManager.enableTimeoutCheck()

      case packet.kind
      of ptGameStart:
        # Re-sent through the whole countdown. Once ours has finished, a late
        # copy is stale and would restart it.
        if pvp.gameStarted and not pvp.isCountingDown:
          continue
        pvp.countdownTimer = packet.countdownTime
        pvp.isCountingDown = true
        # Client also needs to disable timeout during countdown
        pvp.networkManager.resetReceiveTimer()

        # Apply authoritative game config from host (contains timeLimit, killLimit, etc.)
        let portsWanted = packet.pvpConfig.pickupsEnabled != pvp.config.pickupsEnabled
        pvp.config = packet.pvpConfig
        if portsWanted:
          resetPorts(pvp)

        # Apply team settings from host
        pvp.teamsEnabled = packet.teamsEnabled

        # Apply team assignments from host to all players
        if pvp.teamsEnabled and packet.teamAssignments.len > 0:
          for i in 0..<min(pvp.players.len, packet.teamAssignments.len):
            let teamId = teamFromInt(packet.teamAssignments[i])
            pvp.players[i].teamId = teamId

            # Update spawn position based on team
            pvp.players[i].pos = getTeamSpawnPosition(i, teamId, pvp.maxPlayers,
                                                      pvp.screenWidth.float32, pvp.screenHeight.float32)

      of ptPlayerInput:
        # Server receives client input - store it, don't apply immediately
        if pvp.networkManager.isHost():
          # Store the latest client input to apply in next server update
          let playerIndex = packet.input.playerIndex
          if playerIndex >= 0 and playerIndex < pvp.lastInputs.len:
            # A wall click travels in its own packet; if a later input landed
            # in the same poll it must not erase the not-yet-applied click.
            let pendingWall = pvp.lastInputs[playerIndex].placingWall
            let pendingWallPos = pvp.lastInputs[playerIndex].wallPos
            pvp.lastInputs[playerIndex] = packet.input
            if pendingWall and not packet.input.placingWall:
              pvp.lastInputs[playerIndex].placingWall = true
              pvp.lastInputs[playerIndex].wallPos = pendingWallPos

      of ptGameState:
        # Client receives server state
        if pvp.networkManager.isClient():
          reconcileState(pvp, packet.state)

      of ptBulletSpawn:
        # Spawn bullet from packet - check for duplicates first (client-side prediction)
        let bulletState = packet.bullet

        # Check if bullet already exists (client may have predicted it)
        var bulletExists = false
        for existingBullet in pvp.bullets:
          if existingBullet.bulletId == bulletState.id:
            bulletExists = true
            break

        # Only add if it doesn't exist (prevents duplicates from client prediction)
        if not bulletExists:
          let bullet = Bullet(
            pos: bulletState.pos,
            vel: bulletState.vel,
            radius: bulletState.radius,
            damage: bulletState.damage,
            fromPlayer: true,
            lifetime: 0,
            isHoming: bulletState.isHoming,
            isPiercing: bulletState.isPiercing,
            isExplosive: bulletState.isExplosive,
            bulletId: bulletState.id,
            bulletSkin: bulletState.bulletSkin,
            ownerPlayerIndex: bulletState.fromPlayerIndex  # Preserve owner
          )
          pvp.bullets.add(bullet)
          # Hear other players' fire (quietly). One sound per frame at most, so
          # a FORK.EXE volley's three spawn packets don't stack into a blast.
          if bulletState.fromPlayerIndex != pvp.localPlayerIndex and
             pvp.gameTime - pvp.lastRemoteShotSound > 0.03'f32:
            pvp.lastRemoteShotSound = pvp.gameTime
            playSound(stShoot, 0.35'f32)

      of ptBulletDestroy:
        # Remove bullet and track it as recently destroyed
        var i = 0
        while i < pvp.bullets.len:
          if pvp.bullets[i].bulletId == packet.bulletId:
            # Track this bullet as destroyed to prevent snapshot resurrection
            if packet.bulletId notin pvp.recentlyDestroyedBullets:
              pvp.recentlyDestroyedBullets.add(packet.bulletId)
            pvp.bullets.delete(i)
            break
          i += 1

      of ptPlayerDamage:
        # Indices from the wire are never trusted: out of range they indexed
        # past the player list (memory corruption in -d:danger builds).
        let playerIdx = packet.damagedPlayerIndex
        if playerIdx < 0 or playerIdx >= pvp.players.len:
          continue
        if packet.blocked:
          pvp.players[playerIdx].shieldHits = max(0, pvp.players[playerIdx].shieldHits - 1)
        else:
          pvp.players[playerIdx].hp = packet.newHp
        fxHit(pvp, playerIdx, packet.attackerIndex, packet.damageAmount, packet.blocked)

      of ptPlayerDeath:
        let playerIdx = packet.deadPlayerIndex
        if playerIdx < 0 or playerIdx >= pvp.players.len:
          continue
        pvp.players[playerIdx].hp = 0
        clearCombatBuffs(pvp, playerIdx)
        pvp.stats[playerIdx].streak = 0
        let killer = packet.killerIndex
        if killer >= 0 and killer < pvp.players.len:
          pvp.stats[killer].streak = packet.killerStreak
        fxKill(pvp, playerIdx, (if killer >= 0 and killer < pvp.players.len: killer else: -1),
               packet.killerStreak, packet.multiKill, packet.firstBlood, packet.shutdownStreak)

      of ptPlayerRespawn:
        let playerIdx = packet.respawnIndex
        if playerIdx < 0 or playerIdx >= pvp.players.len:
          continue
        let p = pvp.players[playerIdx]
        p.hp = pvp.config.startHp
        p.pos = packet.respawnPos
        p.vel = newVector2f(0, 0)
        p.walls = pvp.config.startWalls
        p.invincibilityTimer = RespawnInvulnTime
        clearCombatBuffs(pvp, playerIdx)
        if playerIdx < pvp.playerInterpStates.len:
          # Restart interpolation at the spawn point instead of gliding there
          # from where the player died.
          pvp.playerInterpStates[playerIdx].hasData = false
          pvp.playerInterpStates[playerIdx].prevPos = p.pos
          pvp.playerInterpStates[playerIdx].targetPos = p.pos
        if playerIdx == pvp.localPlayerIndex:
          pvp.pendingInputs = @[]
          pvp.localPosCorrection = newVector2f(0, 0)
        fxRespawn(pvp, playerIdx)

      of ptPickupTaken:
        let portIdx = packet.pickupPort
        let taker = packet.pickupTaker
        let kind = packageFromInt(packet.pickupKind)
        if portIdx >= 0 and portIdx < pvp.ports.len:
          pvp.ports[portIdx].active = false
          pvp.ports[portIdx].timer =
            if pvp.ports[portIdx].isPower: PowerPortRespawn else: UtilityPortRespawn
        if taker >= 0 and taker < pvp.players.len:
          applyPackageEffect(pvp, taker, kind)
          fxPickup(pvp, portIdx, taker, kind)

      of ptWallPlace:
        let wallState = packet.wall
        let wall = Wall(
          pos: wallState.pos,
          radius: wallState.radius,
          hp: wallState.hp,
          maxHp: wallState.maxHp,
          duration: 999,
          shootTimer: 0
        )
        pvp.walls.add(wall)

      of ptWallDestroy:
        if packet.wallIndex >= 0 and packet.wallIndex < pvp.walls.len:
          pvp.walls.delete(packet.wallIndex)

      of ptGameOver:
        if pvp.networkManager.isHost():
          continue
        # The host re-sends this every RebroadcastInterval; each copy just
        # refreshes the final table, only the first one ends the match.
        for i in 0..<min(packet.finalStats.len, pvp.players.len):
          let s = packet.finalStats[i]
          pvp.players[i].kills = s.kills
          pvp.stats[i].deaths = s.deaths
          pvp.stats[i].bestStreak = s.bestStreak
          pvp.stats[i].shotsFired = s.shotsFired
          pvp.stats[i].shotsHit = s.shotsHit
          pvp.stats[i].damageDealt = s.damageDealt
          pvp.stats[i].pickupsTaken = s.pickupsTaken
        if pvp.teamsEnabled:
          for team in PvPTeam:
            pvp.teamScores[team] = TeamScore(kills: 0, deaths: 0)
          for i in 0..<pvp.players.len:
            let team = pvp.players[i].teamId
            if team != ptNone:
              pvp.teamScores[team].kills += pvp.players[i].kills
        endMatch(pvp, packet.winnerIndex, teamFromInt(packet.winnerTeam),
                 endReasonFromInt(packet.endReason))

      of ptPlayerListUpdate:
        # Host roster after someone left mid-match: mark the missing slots so
        # the scoreboard and feed know (the host handles its own side).
        if pvp.networkManager.isClient():
          var present: seq[int] = @[]
          for entry in packet.updatedPlayers:
            present.add(entry.index)
          for i in 0..<pvp.players.len:
            if i notin present and i < pvp.playerConnected.len and pvp.playerConnected[i]:
              pvp.markLeft(i)

      else:
        discard

    of neDisconnect:
      echo "[PVP] Player ", event.disconnectPlayerIndex, " disconnected: ", event.reason
      handleDisconnect(pvp, event.disconnectPlayerIndex, event.reason)

proc updatePresentation(pvp: PvPGameState, dt: float32) =
  ## Ages every purely visual element. Runs in every phase, result screen
  ## included, so nothing freezes mid-animation when the match ends.
  var i = 0
  while i < pvp.damageNumbers.len:
    if not updateDamageNumber(pvp.damageNumbers[i], dt):
      pvp.damageNumbers.delete(i)
    else:
      i += 1
  i = 0
  while i < pvp.killFeed.len:
    pvp.killFeed[i].age += dt
    if pvp.killFeed[i].age >= KillFeedLife:
      pvp.killFeed.delete(i)
    else:
      i += 1
  i = 0
  while i < pvp.hitMarkers.len:
    pvp.hitMarkers[i].age += dt
    let life = if pvp.hitMarkers[i].isKill: KillMarkerTime else: HitMarkerTime
    if pvp.hitMarkers[i].age >= life:
      pvp.hitMarkers.delete(i)
    else:
      i += 1
  if pvp.bannerAge < BannerTime:
    pvp.bannerAge += dt
  if pvp.toastAge < ToastTime:
    pvp.toastAge += dt
  if pvp.hurtFlash > 0:
    pvp.hurtFlash = max(0.0'f32, pvp.hurtFlash - dt)
  updateShake(pvp.shake, dt)

proc tickPvP*(pvp: PvPGameState, input: PlayerInput, dt: float32, rematchPressed = false) =
  ## One frame of the match given an already-captured local input. Split out of
  ## updatePvP so a headless harness can drive the real netcode with scripted
  ## input (updatePvP only adds the keyboard / pad capture on top).

  # Validate local player index
  if pvp.localPlayerIndex < 0 or pvp.localPlayerIndex >= pvp.players.len:
    echo "[PVP ERROR] Invalid local player index: ", pvp.localPlayerIndex, " (max: ", pvp.players.len - 1, ")"
    return

  # Handle network events FIRST
  handleNetworkEvents(pvp)
  updatePresentation(pvp, dt)

  # Update countdown
  if pvp.isCountingDown:
    pvp.gameTime += dt  # Update time FIRST
    pvp.countdownTimer -= dt
    # Host: keep re-sending the start signal while it matters. It carries the
    # time left, so a late copy also re-syncs the client's countdown.
    if pvp.networkManager.isHost():
      pvp.rebroadcastTimer -= dt
      if pvp.rebroadcastTimer <= 0:
        pvp.rebroadcastTimer = RebroadcastInterval
        sendGameStartPacket(pvp)
    if pvp.countdownTimer <= 0:
      pvp.isCountingDown = false
      pvp.gameStarted = true
      # Re-enable timeout check now that countdown is over
      pvp.networkManager.enableTimeoutCheck()

    # During countdown, send periodic pings to keep connection alive
    if pvp.gameTime - pvp.lastPingTime >= 1.0:
      pvp.lastPingTime = pvp.gameTime
      pvp.networkManager.sendPing(pvp.serverTick)

    return  # Don't process game logic during countdown

  if pvp.gameOver:
    # Result screen. The connection has to stay alive for a rematch: a
    # finished match used to go silent and time everyone out after
    # DISCONNECT_TIMEOUT. The host also keeps re-sending the result, so a
    # client that lost the first ptGameOver isn't left mid-match forever.
    pvp.keepAliveTimer += dt
    if pvp.keepAliveTimer >= 1.0'f32:
      pvp.keepAliveTimer = 0
      pvp.networkManager.sendPing(pvp.serverTick)
    if pvp.networkManager.isHost():
      pvp.rebroadcastTimer -= dt
      if pvp.rebroadcastTimer <= 0:
        pvp.rebroadcastTimer = RebroadcastInterval
        sendGameOverPacket(pvp)
      if rematchPressed:
        restartMatch(pvp)
    updateParticlePool(pvp.particlePool, dt)
    return

  # Server will reconcile with authoritative state for both players
  let appliedVel = applyPlayerInput(pvp, pvp.localPlayerIndex, input, dt)
  if appliedVel.x != 0 or appliedVel.y != 0:
    pvp.localIdleTime = 0
  else:
    pvp.localIdleTime += dt

  # Wall placement and dash presses: send immediately (not throttled) so a
  # one-shot press is never lost between input-rate windows
  if pvp.networkManager.isClient() and
     (input.placingWall or input.dashSeq != pvp.lastSentDashSeq):
    pvp.lastSentDashSeq = input.dashSeq
    var urgentPacket = pvpPacket(pvp, ptPlayerInput)
    urgentPacket.input = input
    pvp.networkManager.sendPacket(urgentPacket)

  # Send input to server at configured rate
  if pvp.gameTime - pvp.lastInputSendTime >= pvp.config.inputRate:
    pvp.lastInputSendTime = pvp.gameTime

    # Store local player's input for server processing
    if pvp.localPlayerIndex >= 0 and pvp.localPlayerIndex < pvp.lastInputs.len:
      pvp.lastInputs[pvp.localPlayerIndex] = input

    # Send to server if client, also record for replay after reconciliation
    if pvp.networkManager.isClient():
      var packet = pvpPacket(pvp, ptPlayerInput)
      packet.input = input
      pvp.networkManager.sendPacket(packet)
      # Store the sent input so reconcileState can re-apply unacknowledged movement
      pvp.pendingInputs.add((capturedAt: pvp.gameTime, input: input, vel: appliedVel))
      # Cap buffer to ~2 seconds of inputs at 30 Hz to prevent unbounded growth
      const MAX_PENDING_INPUTS = 60
      if pvp.pendingInputs.len > MAX_PENDING_INPUTS:
        pvp.pendingInputs = pvp.pendingInputs[pvp.pendingInputs.len - MAX_PENDING_INPUTS .. ^1]

  # Update based on role
  if pvp.networkManager.isHost():
    updatePvPServer(pvp, dt)
  else:
    updatePvPClient(pvp, dt)

  # Send periodic pings
  if pvp.gameTime - pvp.lastPingTime >= 1.0:
    pvp.lastPingTime = pvp.gameTime
    pvp.networkManager.sendPing(pvp.serverTick)

proc updatePvP*(pvp: PvPGameState, dt: float32) =
  ## Main PvP update function: capture the local input, then run the frame.
  if pvp.localPlayerIndex < 0 or pvp.localPlayerIndex >= pvp.players.len:
    echo "[PVP ERROR] Invalid local player index: ", pvp.localPlayerIndex, " (max: ", pvp.players.len - 1, ")"
    return

  let playing = pvp.gameStarted and not pvp.isCountingDown and not pvp.gameOver
  let input =
    if playing: capturePlayerInput(pvp, dt)
    else:
      # Outside live play nothing reads the input; keep the dash count so no
      # press looks new once play resumes.
      PlayerInput(tick: pvp.serverTick, playerIndex: pvp.localPlayerIndex, dt: dt,
                  dashSeq: pvp.localDashSeq, dashDir: pvp.pendingDashDir)
  let rematchPressed = pvp.gameOver and pvp.networkManager.isHost() and
    (isKeyPressed(KeyboardKey.Enter) or isKeyPressed(KeyboardKey.KpEnter) or
     isGamepadConfirmPressed())
  tickPvP(pvp, input, dt, rematchPressed)

# Drawing

proc formatDamage(amount: float32): string =
  ## Whole numbers stay whole; fractional hits (FORK.EXE side bullets, a 0.5
  ## damage rule) keep one decimal instead of rendering as "0".
  let rounded = round(amount)
  if abs(amount - rounded) < 0.05'f32: $int(rounded)
  else: formatFloat(amount, ffDecimal, 1)

proc spaceWidth(size: int32): int32 =
  ## Gap between separately drawn text tokens. A lone " " measures ~0 in this
  ## font (the visible gap in a whole string comes from glyph spacing).
  max(measureText("a a", size) - measureText("aa", size), size div 4)

proc fadeAlpha(age, life, fadeTime: float32, peak = 255.0'f32): float32 =
  ## Full strength until the last `fadeTime` seconds of `life`, then linear out.
  let remaining = life - age
  if remaining >= fadeTime: peak
  else: peak * clamp(remaining / fadeTime, 0.0'f32, 1.0'f32)

proc drawTextCentered(text: string, cx, y, size: int32, color: Color) =
  drawText(text, cx - measureText(text, size) div 2, y, size, color)

proc drawPorts(pvp: PvPGameState) =
  ## Floor sockets, the package on each, and the INCOMING hologram before a drop.
  let time = raylib.getTime().float32  # wall clock: the client's gameTime jumps at snapshots
  for port in pvp.ports:
    let c = Vector2(x: port.pos.x, y: port.pos.y)
    let r = if port.isPower: PortRadius * 1.2'f32 else: PortRadius
    let socketCol = if port.isPower: Color(r: 255, g: 200, b: 80, a: 170)
                    else: Color(r: 120, g: 150, b: 200, a: 130)
    drawPoly(c, 6, r, 30, Color(r: 12, g: 16, b: 28, a: 150))
    drawPolyLines(c, 6, r, 30, 2, socketCol)
    if port.isPower:
      drawPolyLines(c, 6, r + 6, 30, 1, withAlpha(socketCol, 70))
    if port.active:
      let col = packageColor(port.kind)
      let cy = c.y - 4 + sin(time * 3.2'f32 + port.pos.x * 0.01'f32) * 3.0'f32
      drawSoftGlow(c.x, cy, r * 1.6'f32, withAlpha(col, 60), 0.9'f32)
      const box = 13.0'f32
      let rect = Rectangle(x: c.x - box, y: cy - box, width: box * 2, height: box * 2)
      drawRectangleRounded(rect, 0.3, 6, Color(r: 18, g: 22, b: 34, a: 235))
      drawRectangleRoundedLines(rect, 0.3, 6, 2, col)
      drawPackageIcon(port.kind, c.x, cy, 8.0, col)
      drawTextCentered(packageName(port.kind), c.x.int32, (c.y + r + 4).int32, 10,
                       withAlpha(col, 210))
    else:
      let total = if port.isPower: PowerPortRespawn else: UtilityPortRespawn
      let progress = clamp(1.0'f32 - port.timer / total, 0.0'f32, 1.0'f32)
      drawRing(c, r - 4, r - 1.5'f32, -90, -90 + 360 * progress, 36, withAlpha(socketCol, 150))
      if port.timer <= PortIncomingTime:
        # Hologram of the next drop, flickering like a bad signal
        let col = packageColor(port.kind)
        let flick = if (floor(time * 14.0'f32).int mod 5) == 0: 0.3'f32 else: 1.0'f32
        drawPackageIcon(port.kind, c.x, c.y - 4, 8.0, withAlpha(col, 120.0'f32 * flick))
        drawTextCentered(t(tkPvPPortIncoming) & " " & $max(1, ceil(port.timer).int),
                         c.x.int32, (c.y + r + 4).int32, 10, withAlpha(col, 200))

proc drawHitMarkers(pvp: PvPGameState) =
  ## The shooter's X at the victim: white for a hit, larger red for the kill.
  for m in pvp.hitMarkers:
    let life = if m.isKill: KillMarkerTime else: HitMarkerTime
    let k = clamp(1.0'f32 - m.age / life, 0.0'f32, 1.0'f32)
    let size = (if m.isKill: 14.0'f32 else: 9.0'f32) + (1.0'f32 - k) * 4.0'f32
    const gap = 4.0'f32
    let col = if m.isKill: Color(r: 255, g: 70, b: 70, a: uint8(255 * k))
              else: Color(r: 255, g: 255, b: 255, a: uint8(235 * k))
    for d in [(1.0'f32, 1.0'f32), (-1.0'f32, 1.0'f32), (1.0'f32, -1.0'f32), (-1.0'f32, -1.0'f32)]:
      drawLine(Vector2(x: m.pos.x + d[0] * gap, y: m.pos.y + d[1] * gap),
               Vector2(x: m.pos.x + d[0] * size, y: m.pos.y + d[1] * size), 2.5, col)

proc drawEdgeVignette(viewW, viewH: int32, alpha: float32, thickness = 90'i32) =
  let a = uint8(clamp(alpha, 0.0'f32, 255.0'f32))
  if a == 0: return
  let c = Color(r: 200, g: 20, b: 20, a: a)
  let clear = Color(r: 200, g: 20, b: 20, a: 0)
  drawRectangleGradientV(0, 0, viewW, thickness, c, clear)
  drawRectangleGradientV(0, viewH - thickness, viewW, thickness, clear, c)
  drawRectangleGradientH(0, 0, thickness, viewH, c, clear)
  drawRectangleGradientH(viewW - thickness, 0, thickness, viewH, clear, c)

proc drawKillFeed(pvp: PvPGameState, rightX, topY: int32) =
  ## Newest on top, right-aligned: "killer [bullet] victim  CALLOUT".
  const size = 16'i32
  const rowH = 24'i32
  let gap = spaceWidth(size)
  let local = pvp.localPlayerIndex
  var y = topY
  for idx in countdown(pvp.killFeed.high, 0):
    let e = pvp.killFeed[idx]
    let a = fadeAlpha(e.age, KillFeedLife, 0.6'f32)
    var leftText, rightText: string
    var leftCol, rightCol: Color
    var glyphW = 0'i32
    case e.kind
    of kfKill:
      if e.actor >= 0:
        leftText = pvp.playerName(e.actor)
        leftCol = pvp.playerColor(e.actor)
      rightText = pvp.playerName(e.target)
      rightCol = pvp.playerColor(e.target)
      glyphW = 18
    of kfLeft:
      leftText = pvp.playerName(e.actor)
      leftCol = pvp.playerColor(e.actor)
      rightText = t(tkPvPFeedLeft)
      rightCol = Color(r: 170, g: 170, b: 185, a: 255)
    of kfPackage:
      leftText = pvp.playerName(e.actor)
      leftCol = pvp.playerColor(e.actor)
      rightText = packageName(e.pkg)
      rightCol = packageColor(e.pkg)
      glyphW = 16
    let wL = if leftText.len > 0: measureText(leftText, size) else: 0'i32
    let wR = measureText(rightText, size)
    let wT = if e.tag.len > 0: measureText(e.tag, 14) else: 0'i32
    var total = wR
    if wL > 0: total += wL + gap
    if glyphW > 0: total += glyphW + gap
    if wT > 0: total += wT + gap * 2
    const pad = 8'i32
    let x0 = rightX - total - pad * 2
    let involvesLocal = e.actor == local or (e.kind == kfKill and e.target == local)
    drawRectangle(x0, y, total + pad * 2, rowH - 2,
                  if involvesLocal: Color(r: 20, g: 50, b: 70, a: uint8(a * 0.75'f32))
                  else: Color(r: 0, g: 0, b: 0, a: uint8(a * 0.55'f32)))
    if involvesLocal:
      drawRectangleLines(Rectangle(x: x0.float32, y: y.float32, width: (total + pad * 2).float32,
                                   height: (rowH - 2).float32), 1,
                         Color(r: 0, g: 200, b: 255, a: uint8(a * 0.6'f32)))
    var x = x0 + pad
    let ty = y + (rowH - 2 - size) div 2
    if wL > 0:
      drawText(leftText, x, ty, size, withAlpha(leftCol, a))
      x += wL + gap
    if glyphW > 0:
      let gy = (y + (rowH - 2) div 2).float32
      if e.kind == kfKill:
        # A bullet with a short trail
        drawLine(Vector2(x: x.float32, y: gy), Vector2(x: (x + glyphW - 6).float32, y: gy), 2,
                 Color(r: 255, g: 220, b: 150, a: uint8(a * 0.6'f32)))
        drawCircle(Vector2(x: (x + glyphW - 4).float32, y: gy), 3.5, Color(r: 255, g: 240, b: 200, a: uint8(a)))
      else:
        drawPackageIcon(e.pkg, (x + glyphW div 2).float32, gy, 6.5, withAlpha(packageColor(e.pkg), a))
      x += glyphW + gap
    drawText(rightText, x, ty, size, withAlpha(rightCol, a))
    x += wR
    if wT > 0:
      x += gap * 2
      drawText(e.tag, x, y + (rowH - 2 - 14) div 2, 14, withAlpha(Gold, a))
    y += rowH

proc drawBanner(pvp: PvPGameState, viewW, viewH: int32) =
  ## The local player's own callout, popping in at the top of the arena.
  if pvp.bannerAge >= BannerTime or pvp.bannerText.len == 0:
    return
  let age = pvp.bannerAge
  let pop = if age < 0.15'f32: 1.0'f32 + (1.0'f32 - age / 0.15'f32) * 0.35'f32 else: 1.0'f32
  let a = fadeAlpha(age, BannerTime, 0.4'f32)
  let size = int32(36.0'f32 * pop)
  let w = measureText(pvp.bannerText, size)
  let hasSub = pvp.bannerSub.len > 0
  let y = int32(viewH.float32 * 0.2'f32) - size div 2
  let bandW = max(w, if hasSub: measureText(pvp.bannerSub, 18) else: 0'i32) + 60
  drawRectangle(viewW div 2 - bandW div 2, y - 10, bandW, size + 20 + (if hasSub: 24'i32 else: 0'i32),
                Color(r: 0, g: 0, b: 0, a: uint8(a * 0.5'f32)))
  drawText(pvp.bannerText, viewW div 2 - w div 2 + 2, y + 2, size, Color(r: 0, g: 0, b: 0, a: uint8(a * 0.7'f32)))
  drawText(pvp.bannerText, viewW div 2 - w div 2, y, size, withAlpha(pvp.bannerColor, a))
  if hasSub:
    drawTextCentered(pvp.bannerSub, viewW div 2, y + size + 6, 18,
                     withAlpha(Color(r: 255, g: 235, b: 170, a: 255), a))

proc drawToast(pvp: PvPGameState, viewW, viewH: int32) =
  ## "OVERCLOCK.SYS: fire rate x2" when the local player grabs a package.
  if pvp.toastAge >= ToastTime or pvp.toastText.len == 0:
    return
  let a = fadeAlpha(pvp.toastAge, ToastTime, 0.5'f32)
  const size = 18'i32
  let w = measureText(pvp.toastText, size)
  let x = viewW div 2 - w div 2
  let y = viewH - 104
  drawRectangle(x - 12, y - 6, w + 24, size + 12, Color(r: 0, g: 0, b: 0, a: uint8(a * 0.65'f32)))
  drawRectangleLines(Rectangle(x: (x - 12).float32, y: (y - 6).float32, width: (w + 24).float32,
                               height: (size + 12).float32), 1, withAlpha(pvp.toastColor, a))
  drawText(pvp.toastText, x, y, size, withAlpha(pvp.toastColor, a))

proc drawBuffPills(pvp: PvPGameState, x, bottomY: int32) =
  ## Active package effects on the local player, stacked upward from bottomY,
  ## each with a draining bar for its remaining time.
  let p = pvp.players[pvp.localPlayerIndex]
  if p.hp <= 0: return
  var buffs: seq[tuple[kind: PvPPackageKind, remaining: float32]] = @[]
  if p.shieldHits > 0: buffs.add((pkFirewall, 0.0'f32))
  if p.speedBoostTimer > 0: buffs.add((pkTurbo, p.speedBoostTimer))
  if p.fireRateBoostTimer > 0: buffs.add((pkOverclock, p.fireRateBoostTimer))
  if pvp.spreadTimers[pvp.localPlayerIndex] > 0:
    buffs.add((pkFork, pvp.spreadTimers[pvp.localPlayerIndex]))
  const size = 16'i32
  const h = 26'i32
  var y = bottomY
  for b in buffs:
    y -= h + 6
    let col = packageColor(b.kind)
    let total = packageDuration(b.kind)
    let label = if total > 0: packageName(b.kind) & "  " & formatFloat(b.remaining, ffDecimal, 1) & "s"
                else: packageName(b.kind)
    let w = 28 + measureText(label, size) + 10
    drawRectangle(x, y, w, h, Color(r: 0, g: 0, b: 0, a: 160))
    drawRectangleLines(Rectangle(x: x.float32, y: y.float32, width: w.float32, height: h.float32), 1,
                       withAlpha(col, 170))
    drawPackageIcon(b.kind, (x + 14).float32, (y + h div 2).float32, 7.0, col)
    drawText(label, x + 28, y + (h - size) div 2, size, col)
    if total > 0:
      let frac = clamp(b.remaining / total, 0.0'f32, 1.0'f32)
      drawRectangle(x + 2, y + h - 4, int32((w - 4).float32 * frac), 2, col)

proc boardOrder(pvp: PvPGameState): seq[int] =
  ## Kills descending, then fewest deaths, then slot order.
  result = toSeq(0..<pvp.players.len)
  result.sort(proc(a, b: int): int =
    if pvp.players[a].kills != pvp.players[b].kills:
      return cmp(pvp.players[b].kills, pvp.players[a].kills)
    if pvp.stats[a].deaths != pvp.stats[b].deaths:
      return cmp(pvp.stats[a].deaths, pvp.stats[b].deaths)
    cmp(a, b))

proc accuracyText(s: PvPPlayerStats): string =
  if s.shotsFired <= 0: "-"
  else: $int(round(s.shotsHit.float32 / s.shotsFired.float32 * 100.0'f32)) & "%"

proc drawScoreBoard(pvp: PvPGameState, centerX, top: int32, final: bool): int32 =
  ## The process table: live (kills / deaths / current streak) on Tab, or the
  ## full end-of-match line. Team mode groups rows under their team with its
  ## total. Returns the y just below the panel.
  const headerSize = 14'i32
  let local = pvp.localPlayerIndex
  let headers =
    if final: @[t(tkPvPBoardKills), t(tkPvPBoardDeaths), t(tkPvPBoardBest), t(tkPvPBoardAcc), t(tkPvPBoardDmg)]
    else: @[t(tkPvPBoardKills), t(tkPvPBoardDeaths), t(tkPvPBoardStreak)]

  # Rows: team header rows (team mode) followed by that team's players.
  var rows: seq[tuple[isTeam: bool, idx: int, team: PvPTeam]] = @[]
  let order = boardOrder(pvp)
  if pvp.teamsEnabled:
    var teams: seq[PvPTeam] = @[]
    for i in order:
      if pvp.players[i].teamId notin teams:
        teams.add(pvp.players[i].teamId)
    teams.sort(proc(a, b: PvPTeam): int = cmp(pvp.teamScores[b].kills, pvp.teamScores[a].kills))
    for team in teams:
      rows.add((isTeam: true, idx: -1, team: team))
      for i in order:
        if pvp.players[i].teamId == team:
          rows.add((isTeam: false, idx: i, team: team))
  else:
    for i in order:
      rows.add((isTeam: false, idx: i, team: ptNone))

  let rowH = if rows.len > 12: 20'i32 else: 26'i32
  let valueSize = if rowH < 24: 16'i32 else: 18'i32

  # Column widths from the real text (Spanish headers run wider).
  var nameW = measureText(t(tkPvPBoardPlayer), headerSize)
  for i in 0..<pvp.players.len:
    nameW = max(nameW, measureText(pvp.playerName(i), valueSize))
  if pvp.teamsEnabled:
    for row in rows:
      if row.isTeam:
        nameW = max(nameW, measureText(getTeamName(row.team), valueSize))
  nameW += 28
  var colWs: seq[int32] = @[]
  for h in headers:
    colWs.add(max(measureText(h, headerSize), measureText("100%", valueSize)) + 22)
  const rankW = 34'i32
  var tableW = rankW + nameW
  for w in colWs: tableW += w
  let x0 = centerX - tableW div 2
  let panelH = 24 + rows.len.int32 * rowH + 8

  drawRectangle(x0 - 12, top - 10, tableW + 24, panelH + 16, Color(r: 10, g: 14, b: 24, a: 225))
  drawRectangleLines(Rectangle(x: (x0 - 12).float32, y: (top - 10).float32,
                               width: (tableW + 24).float32, height: (panelH + 16).float32),
                     1, Color(r: 70, g: 100, b: 150, a: 210))

  let headerCol = Color(r: 150, g: 160, b: 185, a: 255)
  drawText("#", x0 + 10, top, headerSize, headerCol)
  drawText(t(tkPvPBoardPlayer), x0 + rankW, top, headerSize, headerCol)
  var cx = x0 + rankW + nameW
  for k, h in headers:
    drawText(h, cx + colWs[k] - 10 - measureText(h, headerSize), top, headerSize, headerCol)
    cx += colWs[k]

  template cell(k: int, text: string, col: Color) =
    var colX = x0 + rankW + nameW
    for j in 0..<k: colX += colWs[j]
    drawText(text, colX + colWs[k] - 10 - measureText(text, valueSize), textY, valueSize, col)

  var y = top + 24
  var rank = 0
  for row in rows:
    let textY = y + (rowH - 2 - valueSize) div 2
    if row.isTeam:
      let col = getTeamColor(row.team)
      drawRectangle(x0 - 6, y, tableW + 12, rowH - 2, withAlpha(col, 38))
      drawText(getTeamName(row.team), x0 + 10, textY, valueSize, col)
      cell(0, $pvp.teamScores[row.team].kills, col)
      rank = 0
      y += rowH
      continue
    inc rank
    let i = row.idx
    let connected = i >= pvp.playerConnected.len or pvp.playerConnected[i]
    let rowAlpha = if connected: 255 else: 110
    if i == local:
      drawRectangle(x0 - 6, y, tableW + 12, rowH - 2, Color(r: 0, g: 200, b: 255, a: 34))
    let valueCol = withAlpha(Color(r: 235, g: 240, b: 250, a: 255), rowAlpha)
    drawText($rank, x0 + 10, textY, valueSize, withAlpha(headerCol, rowAlpha))
    drawText(pvp.playerName(i), x0 + rankW, textY, valueSize, withAlpha(pvp.playerColor(i), rowAlpha))
    let s = pvp.stats[i]
    cell(0, $pvp.players[i].kills, valueCol)
    cell(1, $s.deaths, valueCol)
    if final:
      cell(2, $s.bestStreak, valueCol)
      cell(3, accuracyText(s), valueCol)
      cell(4, formatDamage(s.damageDealt), valueCol)
    else:
      cell(2, $s.streak, if s.streak >= StreakCalloutMin: withAlpha(Gold, rowAlpha) else: valueCol)
    y += rowH
  top + panelH + 6

proc computeAwards(pvp: PvPGameState): seq[tuple[title, desc: string, player: int]] =
  ## Fun end-of-match honours. Ties go to whoever ranks higher on the board.
  let order = boardOrder(pvp)
  var sharp = -1
  var bestAcc = -1.0'f32
  var tank = -1
  var hoarder = -1
  var uptime = -1
  for i in order:
    let s = pvp.stats[i]
    if s.shotsFired >= 10:
      let acc = s.shotsHit.float32 / s.shotsFired.float32
      if acc > bestAcc:
        bestAcc = acc
        sharp = i
    if tank < 0 or s.deaths < pvp.stats[tank].deaths:
      tank = i
    if s.pickupsTaken > 0 and (hoarder < 0 or s.pickupsTaken > pvp.stats[hoarder].pickupsTaken):
      hoarder = i
    if s.bestStreak >= 2 and (uptime < 0 or s.bestStreak > pvp.stats[uptime].bestStreak):
      uptime = i
  if sharp >= 0: result.add((t(tkPvPAwardSharpshooter), t(tkPvPAwardSharpshooterDesc), sharp))
  if tank >= 0: result.add((t(tkPvPAwardUnkillable), t(tkPvPAwardUnkillableDesc), tank))
  if hoarder >= 0: result.add((t(tkPvPAwardHoarder), t(tkPvPAwardHoarderDesc), hoarder))
  if uptime >= 0: result.add((t(tkPvPAwardUptime), t(tkPvPAwardUptimeDesc), uptime))

const AwardCardH = 58'i32

proc drawAwards(pvp: PvPGameState, viewW, top: int32) =
  let awards = computeAwards(pvp)
  if awards.len == 0: return
  const gap = 12'i32
  let n = awards.len.int32
  let cardW = min(210'i32, (viewW - 40 - gap * (n - 1)) div n)
  var x = viewW div 2 - (cardW * n + gap * (n - 1)) div 2
  for a in awards:
    drawRectangle(x, top, cardW, AwardCardH, Color(r: 14, g: 18, b: 30, a: 230))
    drawRectangleLines(Rectangle(x: x.float32, y: top.float32, width: cardW.float32,
                                 height: AwardCardH.float32), 1, Color(r: 255, g: 203, b: 0, a: 150))
    let cx = x + cardW div 2
    drawTextCentered(a.title, cx, top + 6, 14, Gold)
    drawTextCentered(pvp.playerName(a.player), cx, top + 23, 16, pvp.playerColor(a.player))
    drawTextCentered(a.desc, cx, top + 42, 12, Color(r: 160, g: 165, b: 185, a: 255))
    x += cardW + gap

proc keyPromptWidth(key, label: string): int32 =
  measureText(key, 16) + 14 + 8 + measureText(label, 18)

proc drawKeyPrompt(x, y: int32, key, label: string, enabled = true) =
  ## "[KEY] Label" with the key as a keycap.
  let kw = measureText(key, 16) + 14
  let a = if enabled: 255 else: 110
  drawRectangleRounded(Rectangle(x: x.float32, y: y.float32, width: kw.float32, height: 24), 0.25, 4,
                       Color(r: 40, g: 46, b: 62, a: uint8(a)))
  drawRectangleRoundedLines(Rectangle(x: x.float32, y: y.float32, width: kw.float32, height: 24), 0.25, 4,
                            1, withAlpha(Color(r: 150, g: 170, b: 210, a: 255), a))
  drawText(key, x + 7, y + 4, 16, withAlpha(White, a))
  drawText(label, x + kw + 8, y + 3, 18, withAlpha(White, a))

proc drawResultScreen(pvp: PvPGameState, viewW, viewH: int32) =
  drawRectangle(0, 0, viewW, viewH, Color(r: 0, g: 0, b: 0, a: 200))
  let res = localResult(pvp)
  var headline: string
  var headCol: Color
  if pvp.endReason == erHostLeft:
    headline = t(tkPvPEndHostLeft)
    headCol = Yellow
  elif pvp.teamsEnabled and pvp.winnerTeam != ptNone:
    headline = if res == 1: t(tkPvPResultTeamWin)
               else: t(tkPvPResultTeamOther).replace("{team}", unicode.toUpper(getTeamName(pvp.winnerTeam)))
    headCol = if res == 1: Green else: getTeamColor(pvp.winnerTeam)
  else:
    headline = case res
      of 1: t(tkPvPResultWin)
      of -1: t(tkPvPResultLose)
      else: t(tkPvPResultDraw)
    headCol = case res
      of 1: Green
      of -1: Red
      else: Yellow
  var headSize = 50'i32
  if measureText(headline, headSize) > viewW - 40: headSize = 34
  drawTextCentered(headline, viewW div 2, 40, headSize, headCol)

  let reasonText = case pvp.endReason
    of erTimeLimit: t(tkPvPEndTimeLimit)
    of erOpponentDisconnected: t(tkPvPEndOpponentDisconnected)
    of erOpponentForfeited: t(tkPvPEndOpponentForfeited)
    of erLastStanding: t(tkPvPEndLastStanding)
    of erNone, erKillLimit, erHostLeft: ""
  if reasonText.len > 0:
    drawTextCentered(reasonText, viewW div 2, 40 + headSize + 8, 20, Color(r: 200, g: 200, b: 200, a: 255))

  let tableBottom = drawScoreBoard(pvp, viewW div 2, 138, final = true)

  # Prompts along the bottom
  let promptY = viewH - 44
  let pad = isGamepadActive()
  let leaveKey = if pad: "B" else: "ESC"
  let hostGone = pvp.networkManager.isClient() and pvp.playerConnected.len > 0 and
                 not pvp.playerConnected[0]
  var noteY = promptY - 30
  if pvp.networkManager.isHost():
    if canRematch(pvp):
      let rematchKey = if pad: "A" else: "ENTER"
      let w1 = keyPromptWidth(rematchKey, t(tkPvPPromptRematch))
      let w2 = keyPromptWidth(leaveKey, t(tkPvPPromptLeave))
      let x = viewW div 2 - (w1 + 48 + w2) div 2
      drawKeyPrompt(x, promptY, rematchKey, t(tkPvPPromptRematch))
      drawKeyPrompt(x + w1 + 48, promptY, leaveKey, t(tkPvPPromptLeave))
      noteY = promptY
    else:
      drawTextCentered(t(tkPvPRematchNeedsPlayers), viewW div 2, noteY, 18,
                       Color(r: 170, g: 170, b: 185, a: 255))
      drawKeyPrompt(viewW div 2 - keyPromptWidth(leaveKey, t(tkPvPPromptLeave)) div 2, promptY,
                    leaveKey, t(tkPvPPromptLeave))
  else:
    let note = if hostGone and pvp.endReason != erHostLeft: t(tkPvPEndHostLeft)
               elif hostGone: ""
               else: t(tkPvPWaitingHost)
    if note.len > 0:
      # Pulse so it reads as "working", not frozen
      let pulse = 0.6'f32 + 0.4'f32 * sin(raylib.getTime().float32 * 3.0'f32)
      drawTextCentered(note, viewW div 2, noteY, 18,
                       withAlpha(Color(r: 170, g: 190, b: 220, a: 255), 255.0'f32 * pulse))
    drawKeyPrompt(viewW div 2 - keyPromptWidth(leaveKey, t(tkPvPPromptLeave)) div 2, promptY,
                  leaveKey, t(tkPvPPromptLeave))

  # Awards only when they fit between the table and the prompts
  let awardsTop = tableBottom + 14
  if awardsTop + AwardCardH <= noteY - 12:
    drawAwards(pvp, viewW, awardsTop)

proc drawMatchHud(pvp: PvPGameState, viewW, viewH: int32) =
  ## Everything on screen during live play and the countdown: scores, clock,
  ## ping, kill feed, walls / buff pills, the respawn caption and the callout
  ## banner. The result screen replaces all of it.
  let localPlayer = pvp.players[pvp.localPlayerIndex]
  # Draw HUD - TEAM MODE or FREE-FOR-ALL
  if pvp.teamsEnabled:
    # Team mode: Show team scores
    # First, determine which teams have players assigned
    var activeTeams: seq[PvPTeam] = @[]
    for i in 0..<pvp.players.len:
      let team = pvp.players[i].teamId
      if team != ptNone and team notin activeTeams:
        activeTeams.add(team)

    # Build scoreboard showing all active teams
    var scoreText = ""
    for team in activeTeams:
      if scoreText.len > 0:
        scoreText &= "  |  "
      scoreText &= getTeamName(team) & ": " & $pvp.teamScores[team].kills

    drawTextCentered(scoreText, viewW div 2, 10, 20, White)
  else:
    # Free-for-all: individual scores. Big lobbies used to run this line off
    # both screen edges, so past 4 players it shows the top 3 plus you (the
    # full table is on Tab).
    var shown: seq[int] = @[]
    if pvp.players.len <= 4:
      for i in 0..<pvp.players.len: shown.add(i)
    else:
      let order = boardOrder(pvp)
      for k in 0..<3: shown.add(order[k])
      if pvp.localPlayerIndex notin shown: shown.add(pvp.localPlayerIndex)
    var scoreText = ""
    for i in shown:
      if scoreText.len > 0:
        scoreText &= " | "
      let disconnected = i < pvp.playerConnected.len and not pvp.playerConnected[i]
      scoreText &= pvp.playerName(i) & ": " & $pvp.players[i].kills &
                   (if disconnected: " (x)" else: "")

    drawTextCentered(scoreText, viewW div 2, 10, 20, White)

  # Time, use only ASCII so raylib's default bitmap font can render it
  let timeText = if pvp.config.timeLimit <= 0:
    "INF"
  else:
    let timeRemaining = max(0.0, pvp.config.timeLimit - pvp.gameTime)
    let minutes = (timeRemaining / 60).int
    let seconds = (timeRemaining.int mod 60)
    $minutes & ":" & (if seconds < 10: "0" else: "") & $seconds
  let timeTextW = measureText(timeText, 20)
  let timeX = viewW div 2 - timeTextW div 2
  let timeY = 35
  # Background pill for readability on any background
  drawRectangle((timeX - 6).int32, (timeY - 3).int32, (timeTextW + 12).int32, 26,
                Color(r: 0, g: 0, b: 0, a: 140))
  drawText(timeText, timeX.int32, timeY.int32, 20, White)

  # Latency
  if pvp.networkManager.isClient():
    # Clamp latency to prevent int overflow (float32 -> int conversion can overflow)
    let pingValue = min(pvp.networkManager.getLatency(), 9999.0).int
    let latencyText = "Ping: " & $pingValue & "ms"
    drawText(latencyText, 10, 10, 20, Yellow)

  # Kill feed (top-right, under the score line's height)
  drawKillFeed(pvp, viewW - 10, 66)

  # Wall count for local player (bottom-left), highlights when in placement mode
  let localIdx = pvp.localPlayerIndex
  let wallCount = pvp.players[localIdx].walls
  let modeActive = pvp.wallPlacementMode and wallCount > 0
  let wallLabel = if modeActive: t(tkPvPWallsLabel) & ": " & $wallCount & "  [" & t(tkPvPPlaceMode) & "]"
                  else: t(tkPvPWallsLabel) & ": " & $wallCount
  let wallLabelW = measureText(wallLabel, 20)
  let pillColor = if modeActive: Color(r: 0, g: 60, b: 20, a: 200)
                  else: Color(r: 0, g: 0, b: 0, a: 140)
  drawRectangle(8, viewH - 38, wallLabelW + 14, 28, pillColor)
  if modeActive:
    drawRectangleLines(Rectangle(x: 8, y: (viewH - 38).float32,
                                 width: (wallLabelW + 14).float32, height: 28), 1,
                       Color(r: 80, g: 255, b: 80, a: 200))
  drawText(wallLabel, 15, viewH - 32, 20,
           if wallCount > 0: Color(r: 100, g: 220, b: 100, a: 255)
           else: Color(r: 180, g: 180, b: 180, a: 160))

  # Active package effects, stacked above the walls pill
  drawBuffPills(pvp, 8, viewH - 38)

  # Respawn caption for the local player: who got you, and when you're back
  if localPlayer.hp <= 0 and not pvp.isCountingDown and
     localIdx < pvp.respawnTimers.len and pvp.respawnTimers[localIdx] > 0:
    let killer = if localIdx < pvp.killedBy.len: pvp.killedBy[localIdx] else: -1
    var y = int32(viewH.float32 * 0.42'f32)
    if killer >= 0 and killer != localIdx:
      let lead = t(tkPvPTerminatedBy)
      let name = pvp.playerName(killer)
      let gap = spaceWidth(28)
      let w = measureText(lead, 28) + gap + measureText(name, 28)
      let x = viewW div 2 - w div 2
      drawText(lead, x, y, 28, Color(r: 255, g: 90, b: 90, a: 255))
      drawText(name, x + measureText(lead, 28) + gap, y, 28, pvp.playerColor(killer))
      y += 38
    drawTextCentered(t(tkPvPRespawningIn) & " " & $(pvp.respawnTimers[localIdx].int + 1) & "...",
                     viewW div 2, y, 20, Color(r: 100, g: 200, b: 255, a: 255))

  # Callout banner and package toast
  drawBanner(pvp, viewW, viewH)
  drawToast(pvp, viewW, viewH)


proc drawPvP*(pvp: PvPGameState, uiScale: float32 = 1.0'f32) =
  ## `uiScale` is the in-game interface scale for the HUD pass at the bottom.
  ## The caller resolves it (game.hudInterfaceScale), so PvP and PvE HUDs can
  ## never disagree about it.
  ## Draw PvP game state
  # updatePvP already refuses to run with an invalid local index; drawing must
  # too, since the HUD below indexes the player list with it.
  if pvp.localPlayerIndex < 0 or pvp.localPlayerIndex >= pvp.players.len:
    return
  let accentColor =
    if pvp.teamsEnabled and pvp.localPlayerIndex >= 0 and pvp.localPlayerIndex < pvp.playerTeamAssignments.len:
      getTeamColor(teamFromInt(pvp.playerTeamAssignments[pvp.localPlayerIndex]))
    else:
      Color(r: 0, g: 200, b: 255, a: 255)

  # World pass: everything below draws in gameplay WORLD space (fixed 1024x768,
  # pvp.screenWidth/Height). In widescreen the world is centered inside the wider
  # virtual screen, so translate by the world view offset and clip to the world
  # rect (spawns/effects in the gutters stay hidden). The networked world size
  # must never depend on the local interface layout, so this offset is purely a
  # local presentation shift. In classic mode worldOffX is 0 (behavior-neutral).
  let worldOffX = getWorldViewOffsetX()
  let worldOffY = getWorldViewOffsetY()
  let worldViewScale = getWorldViewScale()
  let worldClipped = worldOffX > 0 or worldOffY > 0
  # Screen shake moves the world only (as in PvE); the Interface tab's shake
  # slider scales the offset, so 0% is a true off.
  let shakeScale = screenShakeScaleOf(globalSettings)
  let shakeOffset = getShakeOffset(pvp.shake)
  if worldClipped:
    beginVirtualScissorMode(worldOffX.int32, worldOffY.int32,
                            int32(pvp.screenWidth.float32 * worldViewScale),
                            int32(pvp.screenHeight.float32 * worldViewScale))
  pushMatrix()
  translatef(worldOffX + shakeOffset.x * shakeScale, worldOffY + shakeOffset.y * shakeScale, 0)
  scalef(worldViewScale, worldViewScale, 1.0'f32)
  applyTextFilterFor(worldViewScale)   # keeps shrunken world labels legible

  drawSharedBackdrop(pvp.screenWidth, pvp.screenHeight, pvp.gameTime * 0.8,
                     Color(r: 5, g: 7, b: 16, a: 255),
                     Color(r: 18, g: 15, b: 30, a: 255),
                     Color(r: 34, g: 42, b: 68, a: 36),
                     Color(r: 92, g: 116, b: 168, a: 76),
                     withAlpha(accentColor, 58),
                     0.62, 0.68)
  let arenaCenterX = pvp.screenWidth.float32 * 0.5
  let arenaCenterY = pvp.screenHeight.float32 * 0.5
  let arenaPulse = sin(pvp.gameTime * 0.9) * 0.5 + 0.5
  let arenaRadius = min(pvp.screenWidth, pvp.screenHeight).float32 * 0.38
  drawSoftGlow(arenaCenterX, arenaCenterY, arenaRadius * 0.9,
               withAlpha(accentColor, 28), 0.88)
  drawSoftGlow(pvp.screenWidth.float32 * 0.2, pvp.screenHeight.float32 * 0.22,
               arenaRadius * 0.55, Color(r: 90, g: 105, b: 255, a: 26), 0.55)
  drawSoftGlow(pvp.screenWidth.float32 * 0.82, pvp.screenHeight.float32 * 0.78,
               arenaRadius * 0.58, Color(r: 0, g: 235, b: 175, a: 24), 0.5)

  for i in 0..3:
    let r = arenaRadius * (0.44 + i.float32 * 0.17)
    let alpha = uint8(26 + i * 9 + int(arenaPulse * 16.0))
    drawCircleLines(arenaCenterX.int32, arenaCenterY.int32, r,
                    withAlpha(accentColor, alpha))
    let angle = pvp.gameTime * (0.34 + i.float32 * 0.06) + i.float32 * PI * 0.48
    drawCircle(Vector2(x: arenaCenterX + cos(angle) * r,
                       y: arenaCenterY + sin(angle) * r),
               2.8 + i.float32 * 0.35, Color(r: 230, g: 250, b: 255, a: 148))

  for i in 0..<10:
    let angle = i.float32 * PI / 5.0
    let inner = arenaRadius * 0.25
    let outer = arenaRadius * 1.05
    drawLine(Vector2(x: arenaCenterX + cos(angle) * inner, y: arenaCenterY + sin(angle) * inner),
             Vector2(x: arenaCenterX + cos(angle) * outer, y: arenaCenterY + sin(angle) * outer),
             1, withAlpha(accentColor, if i mod 2 == 0: 48'u8 else: 26'u8))

  for i in 0..<6:
    let t = (i.float32 - 2.5) / 2.5
    drawLine(Vector2(x: arenaCenterX - arenaRadius * 1.04, y: arenaCenterY + t * arenaRadius * 0.82),
             Vector2(x: arenaCenterX + arenaRadius * 1.04, y: arenaCenterY + t * arenaRadius * 1.08),
             1, withAlpha(accentColor, 24))

  # Draw arena bounds
  drawRectangleLines(
    Rectangle(x: 0, y: 0, width: pvp.screenWidth.float32, height: pvp.screenHeight.float32),
    2, Color(r: 112, g: 136, b: 180, a: 235)
  )

  # Ports sit on the floor, under walls and everything that moves
  drawPorts(pvp)

  # Draw walls
  for wall in pvp.walls:
    let healthPercent = wall.hp / wall.maxHp
    let wallColor = Color(
      r: uint8(100 + (1.0 - healthPercent) * 155),
      g: uint8(70 * healthPercent),
      b: 50,
      a: 255
    )
    drawCircle(Vector2(x: wall.pos.x, y: wall.pos.y), wall.radius, wallColor)
    drawCircleLines(wall.pos.x.int32, wall.pos.y.int32, wall.radius, Brown)
    # Wall health bar, drawn above the wall
    let wallHealthPercent = wall.hp / wall.maxHp
    let wallBarWidth = (wall.radius * 2).int32
    let wallBarHeight: int32 = 4
    let wallBarX = (wall.pos.x - wall.radius).int32
    let wallBarY = (wall.pos.y - wall.radius - 7).int32
    drawRectangle(wallBarX, wallBarY, wallBarWidth, wallBarHeight,
                  Color(r: 40, g: 40, b: 40, a: 200))
    drawRectangle(wallBarX, wallBarY,
                  (wallBarWidth.float32 * wallHealthPercent).int32, wallBarHeight,
                  if wallHealthPercent > 0.5: Color(r: 80, g: 200, b: 80, a: 230)
                  else: Color(r: 220, g: 80, b: 80, a: 230))

  # Wall placement preview: only shown when in wallPlacementMode
  let localPlayer = pvp.players[pvp.localPlayerIndex]
  if localPlayer.hp > 0 and pvp.wallPlacementMode and not pvp.isCountingDown and not pvp.gameOver:
    # Faint ring showing max placement range
    drawCircleLines(localPlayer.pos.x.int32, localPlayer.pos.y.int32,
                    WALL_PLACEMENT_RANGE, Color(r: 180, g: 180, b: 255, a: 60))
    # Ghost wall at cursor, green if placeable, red if not
    let mousePos = getWorldMousePosition()
    let cursorPos = newVector2f(mousePos.x, mousePos.y)
    let inRange = distance(cursorPos, localPlayer.pos) <= WALL_PLACEMENT_RANGE
    let validPos = isValidWallPlacement(cursorPos, localPlayer.pos, pvp.walls, @[], 25,
                                        pvp.screenWidth, pvp.screenHeight)
    let ghostColor = if inRange and validPos:
      Color(r: 80, g: 200, b: 80, a: 100)
    else:
      Color(r: 200, g: 60, b: 60, a: 100)
    drawCircle(Vector2(x: cursorPos.x, y: cursorPos.y), 25, ghostColor)
    drawCircleLines(cursorPos.x.int32, cursorPos.y.int32, 25,
                    if inRange and validPos: Color(r: 80, g: 255, b: 80, a: 200)
                    else: Color(r: 255, g: 60, b: 60, a: 200))

  # Draw bullets with skin support
  for bullet in pvp.bullets:
    drawBullet(bullet, false, false, pvp.gameTime)

  # Draw players with cosmetics and TEAM COLORS
  for i in 0..<pvp.maxPlayers:
    if i >= pvp.players.len:
      break
    let player = pvp.players[i]
    if player.hp <= 0:
      continue

    # Draw player using their cosmetics
    drawPlayer(player)

    # Draw team indicator ring if teams enabled
    if pvp.teamsEnabled and player.teamId != ptNone:
      let teamColor = getTeamColor(player.teamId)
      drawCircleLines(player.pos.x.int32, player.pos.y.int32, player.radius + 5, teamColor)

    # Nickname above the player in its name colour. A streak of 3+ earns a gold
    # root prompt ("#") in front, so everyone can see who is worth hunting.
    if i < pvp.playerNicknames.len and pvp.playerNicknames[i].len > 0:
      let nick = pvp.playerNicknames[i]
      let nickSize: int32 = 14
      let nickW = measureText(nick, nickSize)
      let onStreak = i < pvp.stats.len and pvp.stats[i].streak >= StreakCalloutMin
      let promptW = if onStreak: measureText("#", nickSize) + 4 else: 0'i32
      let nickX = player.pos.x.int32 - (nickW + promptW) div 2
      let nickY = (player.pos.y - player.radius - 26).int32
      if onStreak:
        drawText("#", nickX, nickY, nickSize, Gold)
      drawText(nick, nickX + promptW, nickY, nickSize, withAlpha(pvp.playerColor(i), 220))

    # Health bar
    let barWidth = 50.0
    let barHeight = 5.0
    let healthPercent = player.hp / player.maxHp

    drawRectangle(
      player.pos.x.int32 - (barWidth / 2).int32,
      (player.pos.y - player.radius - 15).int32,
      barWidth.int32,
      barHeight.int32,
      Color(r: 50, g: 50, b: 50, a: 255)
    )

    drawRectangle(
      player.pos.x.int32 - (barWidth / 2).int32,
      (player.pos.y - player.radius - 15).int32,
      (barWidth * healthPercent).int32,
      barHeight.int32,
      if healthPercent > 0.5: Green else: Red
    )

  # Hit confirms for the local shooter
  drawHitMarkers(pvp)

  # Draw particles
  drawParticlePoolLayer(pvp.particlePool, plBackground)
  drawParticlePoolLayer(pvp.particlePool, plForeground)

  # Draw damage numbers (honouring the Interface tab's toggle + size slider,
  # same as the PvE paths -- PvP rolls its own simpler labels).
  if showDamageNumbersOf(globalSettings):
    let dmgFontSize = max(8'i32, int32(20.0'f32 * damageNumberScaleOf(globalSettings)))
    for dn in pvp.damageNumbers:
      let alpha = uint8((1.0 - dn.lifetime / dn.maxLifetime) * 255)
      let textColor = Color(r: 255, g: 255, b: 100, a: alpha)
      let damageText = formatDamage(dn.damage)
      drawText(damageText, dn.pos.x.int32 - 10, dn.pos.y.int32, dmgFontSize, textColor)

  # End world pass: HUD/overlays below draw in VIRTUAL screen space (no world
  # offset, no clip), anchored to the full virtual width/height.
  applyTextFilterFor(1.0'f32)
  popMatrix()
  if worldClipped:
    endScissorMode()
  # Interface layer: the whole PvP HUD honours the Interface tab's UI scale,
  # exactly as the PvE HUD does. viewW/viewH below are this layer's logical
  # viewport.
  let hudScale = max(uiScale, 0.0001'f32)
  beginUIScaleMode(hudScale)
  let viewW = getVirtualScreenWidth()
  let viewH = getVirtualScreenHeight()

  # Damage feedback on the screen edges: a flash when hit, and a slow pulse
  # while the local player is down to the last third of their HP.
  if not pvp.gameOver:
    var edge = pvp.hurtFlash / HurtFlashTime * 150.0'f32
    if localPlayer.hp > 0 and localPlayer.hp <= localPlayer.maxHp / 3.0'f32:
      edge = max(edge, 45.0'f32 + 35.0'f32 * sin(raylib.getTime().float32 * 5.0'f32))
    drawEdgeVignette(viewW, viewH, edge)

  if not pvp.gameOver:
    drawMatchHud(pvp, viewW, viewH)

  # Live process table while Tab (pad: Select) is held
  let boardHeld = isKeyDown(KeyboardKey.Tab) or
                  (isGamepadActive() and isGamepadButtonDown(activeGamepad(), GamepadButton.MiddleLeft))
  if boardHeld and not pvp.gameOver:
    drawRectangle(0, 0, viewW, viewH, Color(r: 0, g: 0, b: 0, a: 110))
    drawTextCentered(t(tkPvPBoardTitle), viewW div 2, 92, 22, Color(r: 0, g: 200, b: 255, a: 255))
    discard drawScoreBoard(pvp, viewW div 2, 130, final = false)

  # Countdown overlay (don't show if game is over)
  if pvp.isCountingDown and not pvp.gameOver and not boardHeld:
    let countdownValue = max(pvp.countdownTimer, 0.0).int + 1
    let countdownText = $countdownValue
    let textWidth = measureText(countdownText, 80)

    drawRectangle(0, 0, viewW, viewH,
                 Color(r: 0, g: 0, b: 0, a: 150))
    drawText(countdownText,
            viewW div 2 - textWidth div 2,
            viewH div 2 - 40,
            80, Yellow)

    # Controls reminder: the dash and the scoreboard are easy to miss otherwise.
    let kb = globalSettings.keybinds
    let gb = globalSettings.gamepadBinds
    let pad = isGamepadActive()
    let dashKey = if pad: gamepadBindLabel(gb[kaDash]) else: keyboardKeyLabel(kb[kaDash])
    let wallKey = if pad: gamepadBindLabel(gb[kaPlaceWall]) else: keyboardKeyLabel(kb[kaPlaceWall])
    let boardKey = if pad: gamepadBindLabel(GamepadButton.MiddleLeft) else: "Tab"
    let hint = "[" & dashKey & "] " & t("keybind_dash") & "      [" & wallKey & "] " &
               t(tkPvPHintWall) & "      [" & boardKey & "] " & t(tkPvPHintScores)
    drawTextCentered(hint, viewW div 2, viewH div 2 + 70, 18, Color(r: 190, g: 200, b: 220, a: 255))

    # Draw arrow pointing to local player with "YOU" label. The arrow anchors to
    # a WORLD entity (player position) but is drawn in the HUD pass, so shift its
    # X by the world view offset to line up with the on-screen player.
    # Anchored to a world position, so it is converted into this layer's
    # coordinates; the gap and bounce below stay in layer units so the marker
    # grows with the rest of the HUD.
    let arrowAnchor = worldToVirtual(
      Vector2(x: localPlayer.pos.x, y: localPlayer.pos.y - localPlayer.radius))
    let arrowX = arrowAnchor.x / hudScale

    # Use team color if teams enabled, otherwise bright green
    let arrowColor = if pvp.teamsEnabled and localPlayer.teamId != ptNone:
      getTeamColor(localPlayer.teamId)
    else:
      Color(r: 100, g: 255, b: 100, a: 255)  # Bright green

    # Animated bouncing arrow
    let bounceOffset = sin(pvp.gameTime * 5) * 10
    let arrowY = arrowAnchor.y / hudScale - 50 + bounceOffset

    # Draw "YOU" text above arrow
    let youText = t(tkPvPYouMarker)
    let youWidth = measureText(youText, 30)
    drawText(youText,
            arrowX.int32 - youWidth div 2,
            (arrowY - 40).int32,
            30, arrowColor)

    # Draw downward pointing arrow (triangle)
    let arrowSize = 20.0
    let arrowTipX = arrowX
    let arrowTipY = arrowY + arrowSize
    let arrowLeftX = arrowX - arrowSize * 0.6
    let arrowRightX = arrowX + arrowSize * 0.6
    let arrowTopY = arrowY

    drawTriangle(
      Vector2(x: arrowTipX, y: arrowTipY),      # Bottom tip
      Vector2(x: arrowLeftX, y: arrowTopY),     # Top left
      Vector2(x: arrowRightX, y: arrowTopY),    # Top right
      arrowColor
    )

    # Draw arrow outline for better visibility
    drawTriangleLines(
      Vector2(x: arrowTipX, y: arrowTipY),
      Vector2(x: arrowLeftX, y: arrowTopY),
      Vector2(x: arrowRightX, y: arrowTopY),
      White
    )

  # Game over: result, the final process table, awards, rematch / leave
  if pvp.gameOver:
    drawResultScreen(pvp, viewW, viewH)

  endUIScaleMode()   # closes the PvP interface layer
