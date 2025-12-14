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
    totalGamesPlayed*: int
    totalPlayTime*: float32  # Total time across all modes
    firstPlayDate*: string
    lastPlayDate*: string
