## Gamemode Definitions System
## Centralizes gamemode configuration and behavior

import types, localization
import modding/mod_patch_core

type
  GameModeDefinition* = object
    mode*: GameMode
    name*: string
    description*: string
    usesWaves*: bool           # Uses wave-based spawning
    allowsCheats*: bool        # Cheats menu available
    difficultyScale*: float32 # How fast difficulty increases
    playerStartCoins*: int    # Starting coins for player

proc getGameModeDefinition*(mode: GameMode): GameModeDefinition {.moddable.} =
  ## Returns the definition for a specific game mode
  case mode
  of gmWaveBased:
    result = GameModeDefinition(
      mode: gmWaveBased,
      name: t(tkGameModeWaveBased),
      description: t(tkGameModeWaveBasedDesc),
      usesWaves: true,
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
      allowsCheats: true,
      difficultyScale: 1.0,
      playerStartCoins: 0
    )

proc getAllGameModes*(): seq[GameModeDefinition] {.moddable.} =
  ## Returns all available game modes
  result = @[
    getGameModeDefinition(gmWaveBased),
    getGameModeDefinition(gmTimeSurvival),
    getGameModeDefinition(gmRoguelite),
    getGameModeDefinition(gmSandbox)
  ]

proc getGameModeName*(mode: GameMode): string {.moddable.} =
  ## Returns the display name for a game mode
  getGameModeDefinition(mode).name

proc shouldUseWaves*(mode: GameMode): bool {.moddable.} =
  ## Check if this mode uses wave-based spawning
  getGameModeDefinition(mode).usesWaves

proc canUseCheats*(mode: GameMode): bool {.moddable.} =
  ## Check if cheats are allowed in this mode
  getGameModeDefinition(mode).allowsCheats

proc isSandboxMode*(mode: GameMode): bool {.moddable.} =
  ## Quick check if this is sandbox mode
  mode == gmSandbox

proc isPvPMode*(mode: GameMode): bool {.moddable.} =
  ## Quick check if this is PvP mode
  mode == gmPvP

proc isRogueliteMode*(mode: GameMode): bool {.moddable.} =
  ## Quick check if this is roguelite mode
  mode == gmRoguelite

proc isWaveMode*(mode: GameMode): bool {.moddable.} =
  ## Quick check if this is wave-based mode
  mode == gmWaveBased

proc isTimeSurvivalMode*(mode: GameMode): bool {.moddable.} =
  ## Quick check if this is time survival mode
  mode == gmTimeSurvival
