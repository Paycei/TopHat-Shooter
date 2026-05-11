## Discord Rich Presence Helper Functions
## Provides high-level functions to update Discord presence based on game state

import discord_presence, types, strformat, math, gamemode_definitions, pvp_game

const
  PresenceAppName = "TopHat-ShooterOS"
  PresenceRepoUrl = "https://github.com/Paycei/TopHat-Shooter"
  PresenceReleasesUrl = "https://github.com/Paycei/TopHat-Shooter/releases"
  PresenceTagline = "Nim + Raylib bullet heaven"

proc formatClock(secondsElapsed: float): string =
  let minutes = (secondsElapsed / 60.0).int
  let seconds = (secondsElapsed.float32.mod(60.0'f32)).int
  let secondsStr = if seconds < 10: "0" & $seconds else: $seconds
  result = &"{minutes}:{secondsStr}"

proc projectButtons(): seq[DiscordButton] =
  result = @[
    createButton("Github Repo", PresenceRepoUrl),
    createButton("Download", PresenceReleasesUrl)
  ]

proc buildPresence(detailsText, stateText, hoverText: string,
                   startTime: int64 = 0): DiscordRichPresence =
  result = createPresence(
    state = stateText,
    details = detailsText,
    largeImage = "game_icon",
    largeText = hoverText,
    startTime = startTime,
    buttons = projectButtons()
  )

proc updateDiscordForPlaying*(client: DiscordClient, game: Game) =
  ## Update Discord presence for active gameplay
  if not client.isConnected():
    return

  let modeText = getGameModeName(game.mode)

  var detailsText = modeText
  var stateText = ""
  var hoverText = PresenceTagline

  if isWaveMode(game.mode):
    if game.bossWaveManager.active:
      stateText = &"Boss Wave {game.currentWave}"
      hoverText = &"{PresenceAppName} | Boss encounter"
    else:
      stateText = &"Wave {game.currentWave} | {game.player.kills} Kills"
      hoverText = &"{PresenceAppName} | Wave {game.currentWave}"
  elif isTimeSurvivalMode(game.mode):
    stateText = &"{formatClock(game.time)} | {game.player.kills} Kills"
    hoverText = &"{PresenceAppName} | Survival run"
  else:  # Sandbox
    stateText = &"Sandbox Mode | {game.player.kills} Kills"
    hoverText = &"{PresenceAppName} | Sandbox chaos"

  let presence = buildPresence(
    detailsText = detailsText,
    stateText = stateText,
    hoverText = hoverText,
    # Preserve the gloriously broken elapsed timer that players already love.
    startTime = game.time.int64
  )

  updatePresence(client, presence)

proc updateDiscordForMenu*(client: DiscordClient) =
  ## Update Discord presence for main menu
  if not client.isConnected():
    return

  let presence = buildPresence(
    detailsText = "Main Menu",
    stateText = "Choosing next run",
    hoverText = PresenceTagline
  )

  updatePresence(client, presence)

proc updateDiscordForPaused*(client: DiscordClient, game: Game) =
  ## Update Discord presence when paused
  if not client.isConnected():
    return

  let modeText = getGameModeName(game.mode)

  let presence = buildPresence(
    detailsText = modeText,
    stateText = "Paused",
    hoverText = &"{PresenceAppName} | Run suspended"
  )

  updatePresence(client, presence)

proc updateDiscordForPvP*(client: DiscordClient, pvpGame: PvPGameState) =
  ## Update Discord presence for PvP gameplay
  if not client.isConnected():
    return

  var detailsText = ""
  var stateText = ""
  var hoverText = &"{PresenceAppName} | Multiplayer mayhem"

  # Determine game mode text (team-based or free-for-all)
  let modeText = if pvpGame.teamsEnabled: "Team PvP" else: "PvP"

  # Build presence based on game state
  if pvpGame.gameOver:
    # Game over state
    if pvpGame.teamsEnabled and pvpGame.winnerTeam != ptNone:
      detailsText = modeText
      stateText = &"{getTeamName(pvpGame.winnerTeam)} Team Won!"
      hoverText = &"{PresenceAppName} | Match complete"
    elif pvpGame.winnerIndex >= 0:
      let isWinner = pvpGame.winnerIndex == pvpGame.localPlayerIndex
      detailsText = modeText
      if isWinner:
        stateText = "Victory!"
      else:
        stateText = "Defeated"
      hoverText = &"{PresenceAppName} | Match complete"
    else:
      detailsText = modeText
      stateText = pvpGame.gameOverReason
      hoverText = &"{PresenceAppName} | Match complete"

  elif pvpGame.isCountingDown:
    # Countdown state
    let countdown = pvpGame.countdownTimer.int + 1
    detailsText = modeText
    stateText = &"Match starts in {countdown}"
    hoverText = &"{PresenceAppName} | Lobby locked in"

  else:
    # Active gameplay
    let localPlayer = pvpGame.players[pvpGame.localPlayerIndex]
    let kills = localPlayer.kills

    if pvpGame.teamsEnabled:
      # Team mode - show team score and personal kills
      let teamId = localPlayer.teamId
      let teamName = getTeamName(teamId)
      let teamKills = pvpGame.teamScores[teamId].kills
      detailsText = modeText
      stateText = &"{teamName}: {teamKills}/{pvpGame.config.killLimit} | {kills} Kills"
      hoverText = &"{PresenceAppName} | {teamName} pressure"
    else:
      # Free-for-all mode - show personal kills and time
      detailsText = modeText
      stateText = &"{kills}/{pvpGame.config.killLimit} Kills | {formatClock(pvpGame.gameTime)}"
      hoverText = &"{PresenceAppName} | Free-for-all"

  let presence = buildPresence(
    detailsText = detailsText,
    stateText = stateText,
    hoverText = hoverText,
    # Gloriously broken elapsed timer that everyone loves.
    startTime = pvpGame.gameTime.int64
  )

  updatePresence(client, presence)
