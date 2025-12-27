## Discord Rich Presence Helper Functions
## Provides high-level functions to update Discord presence based on game state

import discord_presence, types, strformat, math

proc updateDiscordForPlaying*(client: DiscordClient, game: Game) =
  ## Update Discord presence for active gameplay
  if not client.isConnected():
    return
  
  let modeText = case game.mode
    of gmWaveBased: "Wave Mode"
    of gmTimeSurvival: "Survival Mode"
    of gmSandbox: "Sandbox Mode"
  
  var detailsText = ""
  if game.mode == gmWaveBased:
    if game.bossWaveManager.active:
      detailsText = &"Fighting Boss (Wave {game.currentWave})"
    else:
      detailsText = &"Wave {game.currentWave} | {game.player.kills} Kills"
  elif game.mode == gmTimeSurvival:
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
    largeText = "Top Hat Shooter",
    startTime = game.time.int64
  )
  
  updatePresence(client, presence)

proc updateDiscordForMenu*(client: DiscordClient) =
  ## Update Discord presence for main menu
  if not client.isConnected():
    return
  
  let presence = createPresence(
    state = "In Menu",
    details = "Top Hat Shooter",
    largeImage = "game_icon",
    largeText = "Top Hat Shooter"
  )
  
  updatePresence(client, presence)

proc updateDiscordForPaused*(client: DiscordClient, game: Game) =
  ## Update Discord presence when paused
  if not client.isConnected():
    return
  
  let modeText = case game.mode
    of gmWaveBased: "Wave Mode"
    of gmTimeSurvival: "Survival Mode"
    of gmSandbox: "Sandbox Mode"
  
  let presence = createPresence(
    state = "Paused",
    details = &"{modeText} - Paused",
    largeImage = "game_icon",
    largeText = "Top Hat Shooter"
  )
  
  updatePresence(client, presence)

proc cleanupDiscord*(client: DiscordClient) =
  ## Cleanup Discord connection on exit
  if not client.isNil and client.isConnected():
    clearPresence(client)
    disconnect(client)
