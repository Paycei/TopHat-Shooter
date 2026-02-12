## Discord Rich Presence Helper Functions
## Provides high-level functions to update Discord presence based on game state

import discord_presence, types, strformat, math, gamemode_definitions, pvp_game

proc updateDiscordForPlaying*(client: DiscordClient, game: Game) =
  ## Update Discord presence for active gameplay
  if not client.isConnected():
    return
  
  let modeText = getGameModeName(game.mode)
  
  var detailsText = ""
  if isWaveMode(game.mode):
    if game.bossWaveManager.active:
      detailsText = &"Fighting Boss (Wave {game.currentWave})"
    else:
      detailsText = &"Wave {game.currentWave} | {game.player.kills} Kills"
  elif isTimeSurvivalMode(game.mode):
    let minutes = (game.time / 60.0).int
    let seconds = (game.time.float32.mod(60.0'f32)).int
    let secondsStr = if seconds < 10: "0" & $seconds else: $seconds
    detailsText = &"{minutes}:{secondsStr} | {game.player.kills} Kills"
  else:  # Sandbox
    detailsText = &"Testing | {game.player.kills} Kills"
  
  let presence = createPresence(
    state = detailsText,
    details = &"Playing {modeText}",
    largeImage = "game_icon",
    largeText = "TopHat-ShooterOS",
    startTime = game.time.int64
  )
  
  updatePresence(client, presence)

proc updateDiscordForMenu*(client: DiscordClient) =
  ## Update Discord presence for main menu
  if not client.isConnected():
    return
  
  let presence = createPresence(
    state = "In Menu",
    details = "TopHat-ShooterOS",
    largeImage = "game_icon",
    largeText = "TopHat-ShooterOS"
  )
  
  updatePresence(client, presence)

proc updateDiscordForPaused*(client: DiscordClient, game: Game) =
  ## Update Discord presence when paused
  if not client.isConnected():
    return
  
  let modeText = getGameModeName(game.mode)
  
  let presence = createPresence(
    state = "Paused",
    details = &"{modeText} - Paused",
    largeImage = "game_icon",
    largeText = "TopHat-ShooterOS"
  )
  
  updatePresence(client, presence)

proc updateDiscordForPvP*(client: DiscordClient, pvpGame: PvPGameState) =
  ## Update Discord presence for PvP gameplay
  if not client.isConnected():
    return
  
  var detailsText = ""
  var stateText = ""
  
  # Determine game mode text (team-based or free-for-all)
  let modeText = if pvpGame.teamsEnabled: "Team PvP" else: "PvP"
  
  # Build presence based on game state
  if pvpGame.gameOver:
    # Game over state
    if pvpGame.teamsEnabled and pvpGame.winnerTeam != ptNone:
      detailsText = &"{modeText} - Game Over"
      stateText = &"Team {pvpGame.winnerTeam} Won!"
    elif pvpGame.winnerIndex >= 0:
      let isWinner = pvpGame.winnerIndex == pvpGame.localPlayerIndex
      detailsText = &"{modeText} - Game Over"
      if isWinner:
        stateText = "Victory!"
      else:
        stateText = "Defeated"
    else:
      detailsText = &"{modeText} - Game Over"
      stateText = pvpGame.gameOverReason
  
  elif pvpGame.isCountingDown:
    # Countdown state
    let countdown = pvpGame.countdownTimer.int + 1
    detailsText = &"{modeText} Starting"
    stateText = &"Starting in {countdown}..."
  
  else:
    # Active gameplay
    let localPlayer = pvpGame.players[pvpGame.localPlayerIndex]
    let kills = localPlayer.kills
    
    if pvpGame.teamsEnabled:
      # Team mode - show team score and personal kills
      let team = localPlayer.teamId
      let teamKills = pvpGame.teamScores[team].kills
      detailsText = &"Playing {modeText}"
      stateText = &"Team {team}: {teamKills}/{PVP_KILL_LIMIT} | {kills} Kills"
    else:
      # Free-for-all mode - show personal kills and time
      let minutes = (pvpGame.gameTime / 60.0).int
      let seconds = (pvpGame.gameTime.float32.mod(60.0'f32)).int
      let secondsStr = if seconds < 10: "0" & $seconds else: $seconds
      detailsText = &"Playing {modeText}"
      stateText = &"{kills}/{PVP_KILL_LIMIT} Kills | {minutes}:{secondsStr}"
  
  let presence = createPresence(
    state = stateText,
    details = detailsText,
    largeImage = "game_icon",
    largeText = "TopHat-ShooterOS",
    startTime = pvpGame.gameTime.int64
  )
  
  updatePresence(client, presence)

proc cleanupDiscord*(client: DiscordClient) =
  ## Cleanup Discord connection on exit
  if not client.isNil and client.isConnected():
    clearPresence(client)
    disconnect(client)
