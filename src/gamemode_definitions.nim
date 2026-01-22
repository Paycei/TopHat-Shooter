## Gamemode Definitions System
## Centralizes gamemode configuration and behavior

import types

type
  GameModeDefinition* = object
    mode*: GameMode
    name*: string
    description*: string
    usesWaves*: bool           # Uses wave-based spawning
    usesBosses*: bool          # Has boss encounters
    hasTimeLimit*: bool        # Has time-based gameplay
    usesPowerUps*: bool        # Offers power-up selection
    usesShop*: bool           # Has shop between waves
    allowsCheats*: bool        # Cheats menu available
    spawnRate*: float32       # Base enemy spawn rate multiplier
    difficultyScale*: float32 # How fast difficulty increases
    playerStartCoins*: int    # Starting coins for player

proc getGameModeDefinition*(mode: GameMode): GameModeDefinition =
  ## Returns the definition for a specific game mode
  case mode
  of gmWaveBased:
    result = GameModeDefinition(
      mode: gmWaveBased,
      name: "Wave-Based",
      description: "Fight through waves of enemies. Defeat bosses every 5 waves for legendary upgrades.",
      usesWaves: true,
      usesBosses: true,
      hasTimeLimit: false,
      usesPowerUps: true,
      usesShop: true,
      allowsCheats: true,
      spawnRate: 1.0,
      difficultyScale: 1.0,
      playerStartCoins: 0
    )
  
  of gmTimeSurvival:
    result = GameModeDefinition(
      mode: gmTimeSurvival,
      name: "Time Survival",
      description: "Survive as long as possible. Difficulty increases over time.",
      usesWaves: false,
      usesBosses: true,
      hasTimeLimit: false,
      usesPowerUps: true,
      usesShop: true,
      allowsCheats: false,
      spawnRate: 1.0,
      difficultyScale: 1.0,
      playerStartCoins: 0
    )
  
  of gmSandbox:
    result = GameModeDefinition(
      mode: gmSandbox,
      name: "Sandbox",
      description: "Test and experiment with enemies, bosses, and game mechanics.",
      usesWaves: false,
      usesBosses: true,
      hasTimeLimit: false,
      usesPowerUps: true,
      usesShop: true,
      allowsCheats: true,
      spawnRate: 0.0,  # Manual spawning only
      difficultyScale: 0.0,  # No automatic difficulty scaling
      playerStartCoins: 0
    )

proc getAllGameModes*(): seq[GameModeDefinition] =
  ## Returns all available game modes
  result = @[
    getGameModeDefinition(gmWaveBased),
    getGameModeDefinition(gmTimeSurvival),
    getGameModeDefinition(gmSandbox)
  ]

proc getGameModeName*(mode: GameMode): string =
  ## Returns the display name for a game mode
  getGameModeDefinition(mode).name

proc getGameModeDescription*(mode: GameMode): string =
  ## Returns the description for a game mode
  getGameModeDefinition(mode).description

proc shouldUseWaves*(mode: GameMode): bool =
  ## Check if this mode uses wave-based spawning
  getGameModeDefinition(mode).usesWaves

proc shouldSpawnBosses*(mode: GameMode): bool =
  ## Check if this mode spawns bosses
  getGameModeDefinition(mode).usesBosses

proc canUseCheats*(mode: GameMode): bool =
  ## Check if cheats are allowed in this mode
  getGameModeDefinition(mode).allowsCheats

proc shouldUsePowerUps*(mode: GameMode): bool =
  ## Check if this mode uses power-ups
  getGameModeDefinition(mode).usesPowerUps

proc shouldUseShop*(mode: GameMode): bool =
  ## Check if this mode uses the shop system
  getGameModeDefinition(mode).usesShop

proc hasTimeLimit*(mode: GameMode): bool =
  ## Check if this mode has time-based gameplay
  getGameModeDefinition(mode).hasTimeLimit

proc getSpawnRate*(mode: GameMode): float32 =
  ## Get the spawn rate multiplier for this mode
  getGameModeDefinition(mode).spawnRate

proc getDifficultyScale*(mode: GameMode): float32 =
  ## Get the difficulty scaling factor for this mode
  getGameModeDefinition(mode).difficultyScale

proc getStartingCoins*(mode: GameMode): int =
  ## Get the starting coins for player in this mode
  getGameModeDefinition(mode).playerStartCoins

proc isSandboxMode*(mode: GameMode): bool =
  ## Quick check if this is sandbox mode
  mode == gmSandbox

proc isWaveMode*(mode: GameMode): bool =
  ## Quick check if this is wave-based mode
  mode == gmWaveBased

proc isTimeSurvivalMode*(mode: GameMode): bool =
  ## Quick check if this is time survival mode
  mode == gmTimeSurvival
