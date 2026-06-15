## Settings Backend Module
## Handles settings initialization, state management, and application

from save_system import Settings, mbmWhileShooting, rrmFullscreenOnly, saveSettings, loadSettings
from types import KeyAction, KeyBindings, kaMoveUp, kaMoveDown, kaMoveLeft, kaMoveRight, kaShoot, kaPlaceWall, kaLegendary
import raylib, strutils
import sound, localization

var globalSettings*: Settings

proc initSettings*(): Settings =
  ## Initialize settings with default values and load from save file
  result = Settings(
    fpsLimit: 60,
    volume: 0.5,
    musicVolume: 0.5,
    inputBuffer: "60",
    editingFPS: false,
    editingVolume: false,
    editingMusicVolume: false,
    fullscreen: false,
    renderResolutionMode: rrmFullscreenOnly,
    showFPS: false,
    mouseBondingMode: mbmWhileShooting,
    showDebugStats: true,
    showArenaVignette: true,
    showLowHealthVignette: true,
    showHints: true,
    showEnemyLabels: true,
    language: "english",  # Default language is English
    playerSkin: 0,  # Default to first skin (skDefault)
    bulletSkin: 0,  # Default to first bullet skin (bskDefault)
    playerShape: 0,  # Default to first shape (shHexagon)
    bulletShape: 0,  # Default to first bullet shape (bshCircle)
    particleEffect: 0,  # Default to first particle effect (pskDefault)
    desktopBg: 0,        # Default to first desktop background (dbgDefault)
    cubeSkin: 0,         # Default to first cube skin (cskDefault)
    pvpNickname: "Player",  # Default nickname for PvP
    exitConfirmEnabled: true,  # Exit confirm dialogs enabled by default
    keybinds: [
      kaMoveUp:    KeyboardKey.W,
      kaMoveDown:  KeyboardKey.S,
      kaMoveLeft:  KeyboardKey.A,
      kaMoveRight: KeyboardKey.D,
      kaShoot:     KeyboardKey.Space,
      kaPlaceWall: KeyboardKey.E,
      kaLegendary: KeyboardKey.Q
    ]
  )
  globalSettings = result

  # Try to load saved settings
  discard loadSettings(result)

  # Apply loaded language setting
  try:
    setLanguage(parseEnum[Language](result.language))
  except:
    setLanguage(English)
    result.language = "english"

proc applySettings*(settings: Settings) =
  ## Apply settings to the game engine and systems
  setTargetFPS(settings.fpsLimit)
  setGameVolume(settings.volume)
  setMusicVolume(settings.musicVolume)
