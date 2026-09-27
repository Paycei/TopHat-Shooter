## Gamemode Definitions System
## Centralizes gamemode configuration and behavior

import types, localization

type
  GameModeDefinition* = object
    mode*: GameMode
    name*: string
    description*: string
    usesWaves*: bool           # Uses wave-based spawning
    hasTimeLimit*: bool        # Has time-based gameplay
    allowsCheats*: bool        # Cheats menu available
    difficultyScale*: float32 # How fast difficulty increases
    playerStartCoins*: int    # Starting coins for player

proc getGameModeDefinition*(mode: GameMode): GameModeDefinition =
  ## Returns the definition for a specific game mode
  case mode
  of gmWaveBased:
    result = GameModeDefinition(
      mode: gmWaveBased,
      name: t(tkGameModeWaveBased),
      description: t(tkGameModeWaveBasedDesc),
      usesWaves: true,
      hasTimeLimit: false,
      allowsCheats: true,
      difficultyScale: 1.0,
      playerStartCoins: 0
    )

  of gmTimeSurvival:
    result = GameModeDefinition(
      mode: gmTimeSurvival,
      name: t(tkGameModeTimeSurvival),
      description: t(tkGameModeTimeSurvivalDesc),
      usesWaves: false,
      hasTimeLimit: false,
      allowsCheats: true,   # Enables the cheat menu's survival-specific tab (cmtSurvival)
      difficultyScale: 1.0,
      playerStartCoins: 0
    )

  of gmSandbox:
    result = GameModeDefinition(
      mode: gmSandbox,
      name: t(tkGameModeSandbox),
      description: t(tkGameModeSandboxDesc),
      usesWaves: false,
      hasTimeLimit: false,
      allowsCheats: true,
      difficultyScale: 0.0,  # No automatic difficulty scaling
      playerStartCoins: 0
    )

  of gmPvP:
    result = GameModeDefinition(
      mode: gmPvP,
      name: t(tkGameModePvP),
      description: t(tkGameModePvPDesc),
      usesWaves: false,
      hasTimeLimit: true,
      allowsCheats: false,
      difficultyScale: 0.0,
      playerStartCoins: 100
    )

  of gmRoguelite:
    result = GameModeDefinition(
      mode: gmRoguelite,
      name: t("gamemode_roguelite_name"),
      description: t("gamemode_roguelite_desc"),
      usesWaves: true,
      hasTimeLimit: false,
      allowsCheats: true,
      difficultyScale: 1.0,
      playerStartCoins: 0
    )

proc getAllGameModes*(): seq[GameModeDefinition] =
  ## Returns all available game modes
  result = @[
    getGameModeDefinition(gmWaveBased),
    getGameModeDefinition(gmTimeSurvival),
    getGameModeDefinition(gmRoguelite),
    getGameModeDefinition(gmSandbox)
  ]

proc getGameModeName*(mode: GameMode): string =
  ## Returns the display name for a game mode
  getGameModeDefinition(mode).name

proc shouldUseWaves*(mode: GameMode): bool =
  ## Check if this mode uses wave-based spawning
  getGameModeDefinition(mode).usesWaves

proc canUseCheats*(mode: GameMode): bool =
  ## Check if cheats are allowed in this mode
  getGameModeDefinition(mode).allowsCheats

proc hasTimeLimit*(mode: GameMode): bool =
  ## Check if this mode has time-based gameplay
  getGameModeDefinition(mode).hasTimeLimit

proc isSandboxMode*(mode: GameMode): bool =
  ## Quick check if this is sandbox mode
  mode == gmSandbox

proc isPvPMode*(mode: GameMode): bool =
  ## Quick check if this is PvP mode
  mode == gmPvP

proc isRogueliteMode*(mode: GameMode): bool =
  ## Quick check if this is roguelite mode
  mode == gmRoguelite

proc isWaveMode*(mode: GameMode): bool =
  ## Quick check if this is wave-based mode
  mode == gmWaveBased

proc isTimeSurvivalMode*(mode: GameMode): bool =
  ## Quick check if this is time survival mode
  mode == gmTimeSurvival
