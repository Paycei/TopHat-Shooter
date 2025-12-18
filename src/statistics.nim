import json, os, times, statistics_types

export statistics_types

var globalStats*: Statistics

proc initStatistics*(): Statistics =
  result = Statistics(
    waveMode: GameModeStats(
      gamesPlayed: 0,
      totalKills: 0,
      totalCoins: 0,
      totalTimePlayed: 0.0,
      bestScore: 0,
      bestKills: 0,
      bestCoins: 0,
      averageWaveReached: 0.0,
      averageSurvivalTime: 0.0,
      totalDeaths: 0,
      bossesDefeated: 0,
      highestWaveReached: 0,
      longestSurvivalTime: 0.0
    ),
    timeMode: GameModeStats(
      gamesPlayed: 0,
      totalKills: 0,
      totalCoins: 0,
      totalTimePlayed: 0.0,
      bestScore: 0,
      bestKills: 0,
      bestCoins: 0,
      averageWaveReached: 0.0,
      averageSurvivalTime: 0.0,
      totalDeaths: 0,
      bossesDefeated: 0,
      highestWaveReached: 0,
      longestSurvivalTime: 0.0
    ),
    totalGamesPlayed: 0,
    totalPlayTime: 0.0,
    firstPlayDate: "",
    lastPlayDate: ""
  )
  globalStats = result

# Convert GameModeStats to JSON
proc gameModeStatsToJson(stats: GameModeStats): JsonNode =
  result = %* {
    "gamesPlayed": stats.gamesPlayed,
    "totalKills": stats.totalKills,
    "totalCoins": stats.totalCoins,
    "totalTimePlayed": stats.totalTimePlayed,
    "bestScore": stats.bestScore,
    "bestKills": stats.bestKills,
    "bestCoins": stats.bestCoins,
    "averageWaveReached": stats.averageWaveReached,
    "averageSurvivalTime": stats.averageSurvivalTime,
    "totalDeaths": stats.totalDeaths,
    "bossesDefeated": stats.bossesDefeated,
    "highestWaveReached": stats.highestWaveReached,
    "longestSurvivalTime": stats.longestSurvivalTime
  }

# Load GameModeStats from JSON
proc jsonToGameModeStats(jsonNode: JsonNode, stats: var GameModeStats) =
  if jsonNode.hasKey("gamesPlayed"):
    stats.gamesPlayed = jsonNode["gamesPlayed"].getInt()
  if jsonNode.hasKey("totalKills"):
    stats.totalKills = jsonNode["totalKills"].getInt()
  if jsonNode.hasKey("totalCoins"):
    stats.totalCoins = jsonNode["totalCoins"].getInt()
  if jsonNode.hasKey("totalTimePlayed"):
    stats.totalTimePlayed = jsonNode["totalTimePlayed"].getFloat()
  if jsonNode.hasKey("bestScore"):
    stats.bestScore = jsonNode["bestScore"].getInt()
  if jsonNode.hasKey("bestKills"):
    stats.bestKills = jsonNode["bestKills"].getInt()
  if jsonNode.hasKey("bestCoins"):
    stats.bestCoins = jsonNode["bestCoins"].getInt()
  if jsonNode.hasKey("averageWaveReached"):
    stats.averageWaveReached = jsonNode["averageWaveReached"].getFloat()
  if jsonNode.hasKey("averageSurvivalTime"):
    stats.averageSurvivalTime = jsonNode["averageSurvivalTime"].getFloat()
  if jsonNode.hasKey("totalDeaths"):
    stats.totalDeaths = jsonNode["totalDeaths"].getInt()
  if jsonNode.hasKey("bossesDefeated"):
    stats.bossesDefeated = jsonNode["bossesDefeated"].getInt()
  if jsonNode.hasKey("highestWaveReached"):
    stats.highestWaveReached = jsonNode["highestWaveReached"].getInt()
  if jsonNode.hasKey("longestSurvivalTime"):
    stats.longestSurvivalTime = jsonNode["longestSurvivalTime"].getFloat()

# Convert Statistics to JSON
proc statisticsToJson*(stats: Statistics): JsonNode =
  result = %* {
    "waveMode": gameModeStatsToJson(stats.waveMode),
    "timeMode": gameModeStatsToJson(stats.timeMode),
    "totalGamesPlayed": stats.totalGamesPlayed,
    "totalPlayTime": stats.totalPlayTime,
    "firstPlayDate": stats.firstPlayDate,
    "lastPlayDate": stats.lastPlayDate
  }

# Load Statistics from JSON
proc jsonToStatistics*(jsonNode: JsonNode, stats: Statistics) =
  if jsonNode.hasKey("waveMode"):
    jsonToGameModeStats(jsonNode["waveMode"], stats.waveMode)
  if jsonNode.hasKey("timeMode"):
    jsonToGameModeStats(jsonNode["timeMode"], stats.timeMode)
  if jsonNode.hasKey("totalGamesPlayed"):
    stats.totalGamesPlayed = jsonNode["totalGamesPlayed"].getInt()
  if jsonNode.hasKey("totalPlayTime"):
    stats.totalPlayTime = jsonNode["totalPlayTime"].getFloat()
  if jsonNode.hasKey("firstPlayDate"):
    stats.firstPlayDate = jsonNode["firstPlayDate"].getStr()
  if jsonNode.hasKey("lastPlayDate"):
    stats.lastPlayDate = jsonNode["lastPlayDate"].getStr()

# Helper to format time duration
proc formatTime*(seconds: float32): string =
  let totalSecs = int(seconds)
  let hours = totalSecs div 3600
  let minutes = (totalSecs mod 3600) div 60
  let secs = totalSecs mod 60
  
  if hours > 0:
    result = $hours & "h " & $minutes & "m " & $secs & "s"
  elif minutes > 0:
    result = $minutes & "m " & $secs & "s"
  else:
    result = $secs & "s"

# Update statistics after a game ends
proc updateStats*(stats: Statistics, isWaveMode: bool, waveReached: int, 
                  timeSurvived: float32, kills: int, coins: int, 
                  bossesKilled: int) =
  # Update last play date
  stats.lastPlayDate = $now()
  if stats.firstPlayDate == "":
    stats.firstPlayDate = stats.lastPlayDate
  
  # Update total stats
  stats.totalGamesPlayed += 1
  stats.totalPlayTime += timeSurvived
  
  # Select the appropriate mode stats
  var modeStats = if isWaveMode: addr stats.waveMode else: addr stats.timeMode
  
  # Update mode-specific stats
  modeStats.gamesPlayed += 1
  modeStats.totalKills += kills
  modeStats.totalCoins += coins
  modeStats.totalTimePlayed += timeSurvived
  modeStats.totalDeaths += 1
  modeStats.bossesDefeated += bossesKilled
  
  # Update best scores
  if kills > modeStats.bestKills:
    modeStats.bestKills = kills
  if coins > modeStats.bestCoins:
    modeStats.bestCoins = coins
  
  if isWaveMode:
    # Wave mode: track highest wave reached
    if waveReached > modeStats.highestWaveReached:
      modeStats.highestWaveReached = waveReached
      modeStats.bestScore = waveReached
    
    # Update average wave reached
    modeStats.averageWaveReached = 
      (modeStats.averageWaveReached * float32(modeStats.gamesPlayed - 1) + float32(waveReached)) / 
      float32(modeStats.gamesPlayed)
  else:
    # Time mode: track longest survival time
    if timeSurvived > modeStats.longestSurvivalTime:
      modeStats.longestSurvivalTime = timeSurvived
      modeStats.bestScore = int(timeSurvived)
    
    # Update average survival time
    modeStats.averageSurvivalTime = 
      (modeStats.averageSurvivalTime * float32(modeStats.gamesPlayed - 1) + timeSurvived) / 
      float32(modeStats.gamesPlayed)

# ====================
# STATISTICS SAVE/LOAD
# ====================

import save_system

# Save Statistics to file
proc saveStatistics*(stats: Statistics): bool =
  try:
    let jsonData = statisticsToJson(stats)
    let jsonString = jsonData.pretty()
    let savePath = getStatsPath()
    writeFile(savePath, jsonString)
    echo "Statistics saved successfully to ", savePath
    return true
  except IOError as e:
    echo "Error saving statistics: ", e.msg
    return false
  except Exception as e:
    echo "Unexpected error saving statistics: ", e.msg
    return false

# Load Statistics from file
proc loadStatistics*(stats: Statistics): bool =
  try:
    let savePath = getStatsPath()
    if not fileExists(savePath):
      echo "No statistics file found at ", savePath, ", using default stats"
      return false
    
    let jsonString = readFile(savePath)
    let jsonData = parseJson(jsonString)
    jsonToStatistics(jsonData, stats)
    echo "Statistics loaded successfully from ", savePath
    return true
  except IOError as e:
    echo "Error loading statistics: ", e.msg
    return false
  except JsonParsingError as e:
    echo "Error parsing statistics file: ", e.msg
    return false
  except Exception as e:
    echo "Unexpected error loading statistics: ", e.msg
    return false
