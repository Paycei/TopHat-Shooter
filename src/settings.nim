## Settings Backend Module
## Handles settings initialization, state management, and application

from save_system import Settings, mbmWhileShooting, rrmEnabled, rrmFullscreenOnly, HudLayout, hlClassic, hlWidescreen, saveSettings, loadSettings, MinUIScale, MaxUIScale, MinDamageNumberScale, MaxDamageNumberScale, MinScreenShakeScale, MaxScreenShakeScale
from types import KeyAction, KeyBindings, kaMoveUp, kaMoveDown, kaMoveLeft, kaMoveRight, kaShoot, kaPlaceWall, kaLegendary, kaDash, PowerUpType, GamepadBindings, defaultKeybinds, defaultGamepadBinds
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
    renderResolutionMode: rrmEnabled,
    showFPS: false,
    mouseBondingMode: mbmWhileShooting,
    showDebugStats: true,
    showArenaVignette: true,
    showLowHealthVignette: true,
    showHints: true,
    hudLayout: hlWidescreen,
    uiScale: 1.0,             # 100%: the layout every panel was designed against
    showEnemyLabels: true,
    showDamageNumbers: true,
    damageNumberScale: 1.0,
    screenShakeScale: 1.0,
    changelogLegacyView: false,  # a page per version
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

proc uiScaleOf*(settings: Settings): float32 =
  ## The interface scale to draw with, tolerant of a nil/never-loaded Settings
  ## (early boot, tests) and of a value from before the field existed, where the
  ## JSON key is absent and the float defaults to 0.
  if settings.isNil or settings.uiScale <= 0.0'f32: 1.0'f32
  else: clamp(settings.uiScale, MinUIScale, MaxUIScale)

proc showDamageNumbersOf*(settings: Settings): bool =
  ## Whether floating damage text is drawn. Defaults to on when settings aren't
  ## loaded yet, so nothing silently disappears during early init.
  settings.isNil or settings.showDamageNumbers

proc damageNumberScaleOf*(settings: Settings): float32 =
  ## Size multiplier for floating damage text. Like uiScaleOf, a non-positive
  ## value means "never set" rather than "invisible".
  if settings.isNil or settings.damageNumberScale <= 0.0'f32: 1.0'f32
  else: clamp(settings.damageNumberScale, MinDamageNumberScale, MaxDamageNumberScale)

proc screenShakeScaleOf*(settings: Settings): float32 =
  ## Multiplier on all screen shake. Unlike the scales above, 0 is a real choice
  ## here (shake fully off), so it is passed through rather than treated as unset.
  if settings.isNil: 1.0'f32
  else: clamp(settings.screenShakeScale, MinScreenShakeScale, MaxScreenShakeScale)

proc applySettings*(settings: Settings) =
  ## Apply settings to the game engine and systems
  setTargetFPS(settings.fpsLimit)
  setGameVolume(settings.volume)
  setMusicVolume(settings.musicVolume)
  if settings.vsyncEnabled:
    setWindowState(flags(VsyncHint))
  else:
    clearWindowState(flags(VsyncHint))
