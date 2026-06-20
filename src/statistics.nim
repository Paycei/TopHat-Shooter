import json, times
import os
import save_system, types

type
  GameModeStats* = object
    gamesPlayed*: int
    totalKills*: int
    totalCoins*: int
    totalTimePlayed*: float32  # in seconds
    bestScore*: int  # Highest wave reached (wave mode) or longest time survived (time mode)
    bestKills*: int  # Most kills in a single run
    bestCoins*: int  # Most coins collected in a single run
    averageWaveReached*: float32  # Only for wave mode
    averageSurvivalTime*: float32  # Only for time mode
    totalDeaths*: int
    bossesDefeated*: int
    highestWaveReached*: int  # For wave mode
    longestSurvivalTime*: float32  # For time mode (in seconds)

  Statistics* = ref object
    waveMode*: GameModeStats
    timeMode*: GameModeStats
    rogueliteMode*: GameModeStats
    totalGamesPlayed*: int
    totalPlayTime*: float32  # Total time across all modes
    firstPlayDate*: string
    lastPlayDate*: string
    defeatedBossIDs*: seq[int]  # Boss definition IDs the player has defeated at least once

# GLOBAL STATISTICS INSTANCE
var globalStats*: Statistics

# INITIALIZATION
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
    rogueliteMode: GameModeStats(
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
    lastPlayDate: "",
    defeatedBossIDs: @[]
  )
  globalStats = result

proc resetStatistics*(stats: Statistics) =
  ## Reset an existing statistics object in place so any UI references stay valid.
  if stats.isNil:
    return

  let fresh = initStatistics()
  stats.waveMode = fresh.waveMode
  stats.timeMode = fresh.timeMode
  stats.rogueliteMode = fresh.rogueliteMode
  stats.totalGamesPlayed = fresh.totalGamesPlayed
  stats.totalPlayTime = fresh.totalPlayTime
  stats.firstPlayDate = fresh.firstPlayDate
  stats.lastPlayDate = fresh.lastPlayDate
  stats.defeatedBossIDs = fresh.defeatedBossIDs
  globalStats = stats

# JSON SERIALIZATION
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

proc statisticsToJson*(stats: Statistics): JsonNode =
  result = %* {
    "waveMode": gameModeStatsToJson(stats.waveMode),
    "timeMode": gameModeStatsToJson(stats.timeMode),
    "rogueliteMode": gameModeStatsToJson(stats.rogueliteMode),
    "totalGamesPlayed": stats.totalGamesPlayed,
    "totalPlayTime": stats.totalPlayTime,
    "firstPlayDate": stats.firstPlayDate,
    "lastPlayDate": stats.lastPlayDate,
    "defeatedBossIDs": stats.defeatedBossIDs
  }

proc jsonToStatistics*(jsonNode: JsonNode, stats: Statistics) =
  if jsonNode.hasKey("waveMode"):
    jsonToGameModeStats(jsonNode["waveMode"], stats.waveMode)
  if jsonNode.hasKey("timeMode"):
    jsonToGameModeStats(jsonNode["timeMode"], stats.timeMode)
  if jsonNode.hasKey("rogueliteMode"):
    jsonToGameModeStats(jsonNode["rogueliteMode"], stats.rogueliteMode)
  if jsonNode.hasKey("totalGamesPlayed"):
    stats.totalGamesPlayed = jsonNode["totalGamesPlayed"].getInt()
  if jsonNode.hasKey("totalPlayTime"):
    stats.totalPlayTime = jsonNode["totalPlayTime"].getFloat()
  if jsonNode.hasKey("firstPlayDate"):
    stats.firstPlayDate = jsonNode["firstPlayDate"].getStr()
  if jsonNode.hasKey("lastPlayDate"):
    stats.lastPlayDate = jsonNode["lastPlayDate"].getStr()
  if jsonNode.hasKey("defeatedBossIDs"):
    stats.defeatedBossIDs = @[]
    for idNode in jsonNode["defeatedBossIDs"]:
      stats.defeatedBossIDs.add(idNode.getInt())

# HELPER FUNCTIONS
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

# STATISTICS UPDATE

proc updateStatsForMode*(stats: Statistics, mode: GameMode, scoreReached: int,
                         timeSurvived: float32, kills: int, coins: int,
                         bossesKilled: int) =
  stats.lastPlayDate = $now()
  if stats.firstPlayDate == "":
    stats.firstPlayDate = stats.lastPlayDate

  stats.totalGamesPlayed += 1
  stats.totalPlayTime += timeSurvived

  var modeStats =
    case mode
    of gmWaveBased:
      addr stats.waveMode
    of gmRoguelite:
      addr stats.rogueliteMode
    else:
      addr stats.timeMode

  modeStats.gamesPlayed += 1
  modeStats.totalKills += kills
  modeStats.totalCoins += coins
  modeStats.totalTimePlayed += timeSurvived
  modeStats.totalDeaths += 1
  modeStats.bossesDefeated += bossesKilled

  if kills > modeStats.bestKills:
    modeStats.bestKills = kills
  if coins > modeStats.bestCoins:
    modeStats.bestCoins = coins

  if mode == gmTimeSurvival:
    if timeSurvived > modeStats.longestSurvivalTime:
      modeStats.longestSurvivalTime = timeSurvived
      modeStats.bestScore = int(timeSurvived)
    modeStats.averageSurvivalTime =
      (modeStats.averageSurvivalTime * float32(modeStats.gamesPlayed - 1) + timeSurvived) /
      float32(modeStats.gamesPlayed)
  else:
    if scoreReached > modeStats.highestWaveReached:
      modeStats.highestWaveReached = scoreReached
      modeStats.bestScore = scoreReached
    modeStats.averageWaveReached =
      (modeStats.averageWaveReached * float32(modeStats.gamesPlayed - 1) + float32(scoreReached)) /
      float32(modeStats.gamesPlayed)

proc markBossDefeated*(stats: Statistics, bossDefinitionID: int) =
  ## Record that the player has defeated this boss at least once. Used to decide
  ## whether the boss's full phase layout may be revealed in the phase HUD.
  if stats.isNil or bossDefinitionID <= 0:
    return
  if bossDefinitionID notin stats.defeatedBossIDs:
    stats.defeatedBossIDs.add(bossDefinitionID)

proc hasDefeatedBoss*(stats: Statistics, bossDefinitionID: int): bool =
  not stats.isNil and bossDefinitionID in stats.defeatedBossIDs

# SAVE/LOAD
proc saveStatistics*(stats: Statistics): bool =
  let savePath = getStatsPath()
  try:
    writeFile(savePath, statisticsToJson(stats).pretty())
    echo "Statistics saved successfully to ", savePath
    return true
  except CatchableError:
    echo "Error saving statistics to ", savePath
    return false

proc loadStatistics*(stats: Statistics): bool =
  let savePath = getStatsPath()
  if not fileExists(savePath):
    echo "No statistics file found at ", savePath, ", using default stats"
    return false
  try:
    jsonToStatistics(parseJson(readFile(savePath)), stats)
    echo "Statistics loaded successfully from ", savePath
    return true
  except Exception as e:
    echo "Error applying statistics: ", e.msg
    return false
