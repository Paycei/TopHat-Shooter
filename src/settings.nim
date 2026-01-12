## Settings Backend Module
## Handles settings initialization, state management, and application
## UI is in ui/settings_window.nim

from save_system import Settings, saveSettings, loadSettings
import raylib, sound, localization, strutils
export Settings

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
    showFPS: false,
    mouseSupport: true,
    showCursorInMenus: true,
    showDebugStats: false,
    showHints: true,
    showEnemyLabels: true,
    language: "english"  # Default language is English
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
