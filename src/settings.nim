## Settings Backend Module
## Handles settings initialization, state management, and application

from save_system import Settings, mbmWhileShooting, rrmFullscreenOnly, saveSettings, loadSettings
from types import KeyAction, KeyBindings, kaMoveUp, kaMoveDown, kaMoveLeft, kaMoveRight, kaShoot, kaPlaceWall, kaLegendary, PowerUpType, GamepadBindings, defaultKeybinds, defaultGamepadBinds
import raylib, strutils
import sound, localization

var globalSettings*: Settings

proc isPowerUpDiscovered*(pt: PowerUpType): bool =
  ## True if `pt` is in the persistent discovery codex. The codex stores the enum
  ## symbol (`$pt`), matching how death.nim records a power-up's first install.
  ## When settings aren't loaded yet (nil), treat everything as discovered so the
  ## reference screens never hide content during early init or in tests.
  if globalSettings.isNil: return true
  $pt in globalSettings.discoveredPowerUps

proc newDefaultSettings*(): Settings =
  ## Fresh Settings object holding only the built-in defaults (no disk access,
  ## no global registration). Used both at first boot and to wipe leftover
  ## state before loading a different profile's settings file.
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
    keybinds: defaultKeybinds,
    gamepadBinds: defaultGamepadBinds,
    preferredGamepad: -1,  # Auto: use the first detected controller
    aimAssistEnabled: true,
    rogueliteUnlocked: false,
    survivalUnlocked: false
  )

proc reloadSettingsFromDisk*(settings: Settings) =
  ## Reset `settings` to defaults in place, then load the active profile's
  ## settings file over them and apply its language. In-place so every holder
  ## of the ref (globalSettings, the window manager, ...) sees the new values.
  ## Fields missing from the file (or a missing file) stay at their defaults,
  ## which is what makes profile switching safe: nothing leaks from the
  ## previously loaded profile.
  settings[] = newDefaultSettings()[]
  discard loadSettings(settings)
  try:
    setLanguage(parseEnum[Language](settings.language))
  except:
    setLanguage(English)
    settings.language = "english"

proc initSettings*(): Settings =
  ## Initialize settings with default values and load from save file
  result = newDefaultSettings()
  globalSettings = result
  reloadSettingsFromDisk(result)

proc applySettings*(settings: Settings) =
  ## Apply settings to the game engine and systems
  setTargetFPS(settings.fpsLimit)
  setGameVolume(settings.volume)
  setMusicVolume(settings.musicVolume)
  if settings.vsyncEnabled:
    setWindowState(flags(VsyncHint))
  else:
    clearWindowState(flags(VsyncHint))
