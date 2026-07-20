import json, os, std/tables, strutils, raylib
import particle_types, run_statistics, types, utils

# Settings type definition (moved from settings_types.nim)
type
  MouseBondingMode* = enum
    mbmOff = "off"
    mbmWhileShooting = "while_shooting"
    mbmAlwaysInGame = "always_in_game"
    mbmAlways = "always"

  RenderResolutionMode* = enum
    rrmDisabled = "disabled"
    rrmEnabled = "enabled"
    rrmFullscreenOnly = "fullscreen_only"

  HudLayout* = enum
    hlClassic = "classic"
    hlWidescreen = "widescreen"

  Settings* = ref object
    fpsLimit*: int32
    volume*: float32
    musicVolume*: float32
    inputBuffer*: string
    editingFPS*: bool
    editingVolume*: bool
    editingMusicVolume*: bool
    fullscreen*: bool
    renderResolutionMode*: RenderResolutionMode
    showFPS*: bool
    mouseBondingMode*: MouseBondingMode
    showDebugStats*: bool
    showArenaVignette*: bool
    showLowHealthVignette*: bool
    showHints*: bool
    hudLayout*: HudLayout
    showEnemyLabels*: bool
    language*: string
    playerSkin*: int  # Current player skin (stored as int)
    bulletSkin*: int  # Current bullet skin (stored as int)
    playerShape*: int   # Current player shape (stored as int)
    bulletShape*: int   # Current bullet shape (stored as int)
    particleEffect*: int  # Current particle effect (stored as int)
    desktopBg*: int        # Current desktop background skin (stored as int)
    cubeSkin*: int         # Current cube skin (stored as int)
    pvpNickname*: string  # Player nickname shown in PvP lobbies
    hasSeenIntro*: bool   # True after the lore cinematic has been seen once
    hasSeenEnding*: bool  # True after the endgame cinematic has been seen once
    hasSeenRogueliteEnding*: bool  # True after the roguelite ending cinematic has been seen once
    hasSeenSurvivalEnding*: bool   # True after the survival ending cinematic has been seen once
    exitConfirmEnabled*: bool  # Show exit confirm dialogs (default: false)
    vsyncEnabled*: bool        # Lock framerate to monitor refresh rate
    kernelTophatUnlocked*: bool  # Secret cosmetic: earned by beating the wave-60 final boss
    kernelTophatEquipped*: bool  # Whether the unlocked kernel tophat is worn in-game
    orbitalCubeUnlocked*: bool  # Secret cosmetic: earned with the Escape Velocity advancement
    orbitalCubeEquipped*: bool  # Whether the mini desktop cube orbits the player in-game
    cheaterHatUnlocked*: bool   # Secret cosmetic: earned by opening the cd+ cheat menu on a run
    cheaterHatEquipped*: bool   # Whether the cheater hat is worn in-game
    rogueliteUnlocked*: bool    # Unlock flag: allows Roguelite mode from menu
    survivalUnlocked*: bool     # Unlock flag: allows Time Survival mode from menu
    lastDeathWave*: int         # Wave the player died on last non-cheated wave-based run (0 = none)
    keybinds*: KeyBindings      # Rebindable keyboard controls
    gamepadBinds*: GamepadBindings  # Rebindable gamepad controls (same actions)
    preferredGamepad*: int      # Chosen pad index, -1 = auto (first detected)
    aimAssistEnabled*: bool     # Gamepad aim assist (cone snap to nearest enemy)
    hasSeenWaveModeIntro*: bool    # First-time wave-based mode intro played
    hasSeenSurvivalIntro*: bool    # First-time time-survival mode intro played
    hasSeenRogueliteIntro*: bool   # First-time roguelite mode intro played
    hasSeenSandboxIntro*: bool     # First-time sandbox mode intro played
    hasSeenPvPIntro*: bool         # First-time pvp mode intro played
    discoveredPowerUps*: seq[string] # Power-ups seen for the first time (name-serialized)

# Save profiles: every save file lives inside one of MaxProfileSlots per-profile
# folders (<root>/profiles/<slot>/), the same isolation idea as the debug/release
# split below. A profile "exists" when its folder holds a profile.json meta file
# (which records the difficulty chosen at creation). The root profiles.json only
# remembers the last-used slot so boot can preload that profile's settings
# before the profile-select screen appears.
const MaxProfileSlots* = 3

var activeProfileSlot* = 1  # 1..MaxProfileSlots; all get*Path procs point here

proc getRootDataPath*(): string =
  ## Base save directory shared by all profiles (and holder of the last-used
  ## slot marker). Per-profile data must go through getAppDataPath instead.
  when defined(windows):
    result = getEnv("APPDATA")
  elif defined(macosx):
    result = getEnv("HOME") & "/Library/Application Support"
  else:  # Linux and other Unix-like systems
    result = getEnv("HOME") & "/.local/share"

  result = result / ".tophat" / "shooter"

  # Debug builds (nimble debug -> -d:debug) get an isolated save directory so
  # testers running release builds can't carry over progress cheated/unlocked
  # via the debug build (which exposes the cheat menu and other dev shortcuts).
  when defined(debug):
    result = result / "debug"

  if not dirExists(result):
    try:
      createDir(result)
      echo "Created save directory: ", result
    except:
      echo "Warning: Could not create save directory: ", result

proc getProfileDir*(slot: int): string =
  getRootDataPath() / "profiles" / $slot

# Get the active profile's data directory (all save files live here)
proc getAppDataPath*(): string =
  result = getProfileDir(activeProfileSlot)

  # Create directory if it doesn't exist
  if not dirExists(result):
    try:
      createDir(result)
      echo "Created save directory: ", result
    except:
      echo "Warning: Could not create save directory: ", result

proc getProfileMetaPath(slot: int): string =
  getProfileDir(slot) / "profile.json"

proc getLastUsedSlotPath(): string =
  getRootDataPath() / "profiles.json"

proc profileExists*(slot: int): bool =
  fileExists(getProfileMetaPath(slot))

proc loadProfileDifficulty*(slot: int): GameDifficulty =
  ## Difficulty recorded in the slot's profile.json; medium (the legacy
  ## balance) when the file is missing or unreadable.
  result = gdMedium
  try:
    let path = getProfileMetaPath(slot)
    if fileExists(path):
      let meta = parseJson(readFile(path))
      if meta.hasKey("difficulty"):
        result = parseEnumOr(meta["difficulty"].getStr(), gdMedium)
  except CatchableError:
    echo "Warning: could not read profile meta for slot ", slot

proc createProfile*(slot: int, difficulty: GameDifficulty): bool =
  ## Creates the slot folder and its profile.json meta. Safe to call on an
  ## existing slot (rewrites the meta only).
  try:
    createDir(getProfileDir(slot))
    writeFile(getProfileMetaPath(slot),
              pretty(%* {"difficulty": $difficulty}))
    echo "Created profile ", slot, " (", $difficulty, ")"
    true
  except CatchableError:
    echo "Error: could not create profile ", slot
    false

proc deleteProfile*(slot: int): bool =
  ## Removes the whole slot folder (all of that profile's save data).
  try:
    if dirExists(getProfileDir(slot)):
      removeDir(getProfileDir(slot))
      echo "Deleted profile ", slot
    true
  except CatchableError:
    echo "Error: could not delete profile ", slot
    false

proc getLastUsedProfileSlot*(): int =
  ## Slot the player used last session (for preloading settings at boot and
  ## highlighting on the profile-select screen). Defaults to 1.
  result = 1
  try:
    let path = getLastUsedSlotPath()
    if fileExists(path):
      let data = parseJson(readFile(path))
      if data.hasKey("lastUsedSlot"):
        result = clamp(data["lastUsedSlot"].getInt(1), 1, MaxProfileSlots)
  except CatchableError:
    echo "Warning: could not read last-used profile slot"

proc setLastUsedProfileSlot*(slot: int) =
  try:
    writeFile(getLastUsedSlotPath(), pretty(%* {"lastUsedSlot": slot}))
  except CatchableError:
    echo "Warning: could not persist last-used profile slot"

proc migrateLegacySaveFiles*() =
  ## One-time conversion from the pre-profile layout: save files that sit
  ## directly in the root data dir are moved into profile 1, which is stamped
  ## with medium difficulty (the balance those saves were played on).
  ## Idempotent: files are only moved when the destination doesn't have them,
  ## and profile.json is only written if missing.
  const legacyFiles = ["settings.json", "stats.json", "last_run.json",
                       "advancements.json", "roguelite_profile.json"]
  let root = getRootDataPath()
  var hasLegacy = false
  for f in legacyFiles:
    if fileExists(root / f):
      hasLegacy = true
      break
  if not hasLegacy:
    return

  try:
    createDir(getProfileDir(1))
    for f in legacyFiles:
      let src = root / f
      let dst = getProfileDir(1) / f
      if fileExists(src):
        if not fileExists(dst):
          moveFile(src, dst)
          echo "Migrated legacy save file ", f, " to profile 1"
        # If the destination already exists, leave the stray root copy alone
        # rather than destroy either version.
    if not profileExists(1):
      discard createProfile(1, gdMedium)
  except CatchableError as e:
    echo "Warning: legacy save migration failed: ", e.msg

# Path to the save files
proc getSettingsPath*(): string =
  getAppDataPath() / "settings.json"

proc getStatsPath*(): string =
  getAppDataPath() / "stats.json"

proc getLastRunStatsPath*(): string =
  getAppDataPath() / "last_run.json"

proc deleteLastRunStats*(): bool =
  try:
    let savePath = getLastRunStatsPath()
    if fileExists(savePath):
      removeFile(savePath)
      echo "Last run statistics deleted from ", savePath
    return true
  except IOError as e:
    echo "Error deleting last run stats: ", e.msg
    return false
  except Exception as e:
    echo "Unexpected error deleting last run stats: ", e.msg
    return false

# Convert Settings to JSON
proc settingsToJson*(settings: Settings): JsonNode =
  result = %* {
    "fpsLimit": settings.fpsLimit,
    "volume": settings.volume,
    "musicVolume": settings.musicVolume,
    "fullscreen": settings.fullscreen,
    "renderResolutionMode": $settings.renderResolutionMode,
    "showFPS": settings.showFPS,
    "mouseBondingMode": $settings.mouseBondingMode,
    "showDebugStats": settings.showDebugStats,
    "showArenaVignette": settings.showArenaVignette,
    "showLowHealthVignette": settings.showLowHealthVignette,
    "showHints": settings.showHints,
    "hudLayout": $settings.hudLayout,
    "showEnemyLabels": settings.showEnemyLabels,
    "language": settings.language,
    "playerSkin": settings.playerSkin,
    "bulletSkin": settings.bulletSkin,
    "playerShape": settings.playerShape,
    "bulletShape": settings.bulletShape,
    "particleEffect": settings.particleEffect,
    "desktopBg": settings.desktopBg,
    "cubeSkin": settings.cubeSkin,
    "pvpNickname": settings.pvpNickname,
    "hasSeenIntro": settings.hasSeenIntro,
    "hasSeenEnding": settings.hasSeenEnding,
    "hasSeenRogueliteEnding": settings.hasSeenRogueliteEnding,
    "hasSeenSurvivalEnding": settings.hasSeenSurvivalEnding,
    "exitConfirmEnabled": settings.exitConfirmEnabled,
    "vsyncEnabled": settings.vsyncEnabled,
    "kernelTophatUnlocked": settings.kernelTophatUnlocked,
    "kernelTophatEquipped": settings.kernelTophatEquipped,
    "orbitalCubeUnlocked": settings.orbitalCubeUnlocked,
    "orbitalCubeEquipped": settings.orbitalCubeEquipped,
    "cheaterHatUnlocked": settings.cheaterHatUnlocked,
    "cheaterHatEquipped": settings.cheaterHatEquipped,
    "rogueliteUnlocked": settings.rogueliteUnlocked,
    "survivalUnlocked": settings.survivalUnlocked,
    "lastDeathWave": settings.lastDeathWave,
    "hasSeenWaveModeIntro": settings.hasSeenWaveModeIntro,
    "hasSeenSurvivalIntro": settings.hasSeenSurvivalIntro,
    "hasSeenRogueliteIntro": settings.hasSeenRogueliteIntro,
    "hasSeenSandboxIntro": settings.hasSeenSandboxIntro,
    "hasSeenPvPIntro": settings.hasSeenPvPIntro,
    "discoveredPowerUps": settings.discoveredPowerUps
  }
  var bindsObj = newJObject()
  for action in KeyAction:
    bindsObj[$action] = %($ settings.keybinds[action])
  result["keybinds"] = bindsObj
  var padBindsObj = newJObject()
  for action in KeyAction:
    padBindsObj[$action] = %($ settings.gamepadBinds[action])
  result["gamepadBinds"] = padBindsObj
  result["preferredGamepad"] = %settings.preferredGamepad
  result["aimAssistEnabled"] = %settings.aimAssistEnabled

# Load Settings from JSON
proc jsonToSettings*(jsonNode: JsonNode, settings: Settings) =
  if jsonNode.hasKey("fpsLimit"):
    settings.fpsLimit = jsonNode["fpsLimit"].getInt().int32

  if jsonNode.hasKey("volume"):
    settings.volume = jsonNode["volume"].getFloat()

  if jsonNode.hasKey("musicVolume"):
    settings.musicVolume = jsonNode["musicVolume"].getFloat()

  if jsonNode.hasKey("fullscreen"):
    settings.fullscreen = jsonNode["fullscreen"].getBool()

  if jsonNode.hasKey("renderResolutionMode"):
    try:
      settings.renderResolutionMode = parseEnum[RenderResolutionMode](jsonNode["renderResolutionMode"].getStr())
    except ValueError:
      settings.renderResolutionMode = rrmFullscreenOnly

  if jsonNode.hasKey("showFPS"):
    settings.showFPS = jsonNode["showFPS"].getBool()

  if jsonNode.hasKey("mouseBondingMode"):
    try:
      settings.mouseBondingMode = parseEnum[MouseBondingMode](jsonNode["mouseBondingMode"].getStr())
    except ValueError:
      settings.mouseBondingMode = mbmOff
  elif jsonNode.hasKey("mouseBonding"):
    # Migrate the old checkbox to the legacy equivalent mode.
    settings.mouseBondingMode = if jsonNode["mouseBonding"].getBool(): mbmWhileShooting else: mbmOff

  if jsonNode.hasKey("showDebugStats"):
    settings.showDebugStats = jsonNode["showDebugStats"].getBool()

  if jsonNode.hasKey("showArenaVignette"):
    settings.showArenaVignette = jsonNode["showArenaVignette"].getBool()

  if jsonNode.hasKey("showLowHealthVignette"):
    settings.showLowHealthVignette = jsonNode["showLowHealthVignette"].getBool()

  if jsonNode.hasKey("showHints"):
    settings.showHints = jsonNode["showHints"].getBool()

  if jsonNode.hasKey("hudLayout"):
    try:
      settings.hudLayout = parseEnum[HudLayout](jsonNode["hudLayout"].getStr())
    except ValueError:
      settings.hudLayout = hlClassic

  if jsonNode.hasKey("showEnemyLabels"):
    settings.showEnemyLabels = jsonNode["showEnemyLabels"].getBool()

  if jsonNode.hasKey("language"):
    settings.language = jsonNode["language"].getStr()

  if jsonNode.hasKey("playerSkin"):
    settings.playerSkin = jsonNode["playerSkin"].getInt()

  if jsonNode.hasKey("bulletSkin"):
    settings.bulletSkin = jsonNode["bulletSkin"].getInt()

  if jsonNode.hasKey("playerShape"):
    settings.playerShape = jsonNode["playerShape"].getInt()

  if jsonNode.hasKey("bulletShape"):
    settings.bulletShape = jsonNode["bulletShape"].getInt()

  if jsonNode.hasKey("particleEffect"):
    settings.particleEffect = jsonNode["particleEffect"].getInt()

  if jsonNode.hasKey("desktopBg"):
    settings.desktopBg = jsonNode["desktopBg"].getInt()

  if jsonNode.hasKey("cubeSkin"):
    settings.cubeSkin = jsonNode["cubeSkin"].getInt()

  if jsonNode.hasKey("pvpNickname"):
    settings.pvpNickname = jsonNode["pvpNickname"].getStr()

  if jsonNode.hasKey("hasSeenIntro"):
    settings.hasSeenIntro = jsonNode["hasSeenIntro"].getBool()

  if jsonNode.hasKey("hasSeenEnding"):
    settings.hasSeenEnding = jsonNode["hasSeenEnding"].getBool()

  if jsonNode.hasKey("hasSeenRogueliteEnding"):
    settings.hasSeenRogueliteEnding = jsonNode["hasSeenRogueliteEnding"].getBool()

  if jsonNode.hasKey("hasSeenSurvivalEnding"):
    settings.hasSeenSurvivalEnding = jsonNode["hasSeenSurvivalEnding"].getBool()

  if jsonNode.hasKey("exitConfirmEnabled"):
    settings.exitConfirmEnabled = jsonNode["exitConfirmEnabled"].getBool()

  if jsonNode.hasKey("vsyncEnabled"):
    settings.vsyncEnabled = jsonNode["vsyncEnabled"].getBool()

  if jsonNode.hasKey("kernelTophatUnlocked"):
    settings.kernelTophatUnlocked = jsonNode["kernelTophatUnlocked"].getBool()

  if jsonNode.hasKey("kernelTophatEquipped"):
    settings.kernelTophatEquipped = jsonNode["kernelTophatEquipped"].getBool()

  if jsonNode.hasKey("orbitalCubeUnlocked"):
    settings.orbitalCubeUnlocked = jsonNode["orbitalCubeUnlocked"].getBool()

  if jsonNode.hasKey("orbitalCubeEquipped"):
    settings.orbitalCubeEquipped = jsonNode["orbitalCubeEquipped"].getBool()

  if jsonNode.hasKey("cheaterHatUnlocked"):
    settings.cheaterHatUnlocked = jsonNode["cheaterHatUnlocked"].getBool()

  if jsonNode.hasKey("cheaterHatEquipped"):
    settings.cheaterHatEquipped = jsonNode["cheaterHatEquipped"].getBool()

  if jsonNode.hasKey("rogueliteUnlocked"):
    settings.rogueliteUnlocked = jsonNode["rogueliteUnlocked"].getBool()

  if jsonNode.hasKey("survivalUnlocked"):
    settings.survivalUnlocked = jsonNode["survivalUnlocked"].getBool()

  if jsonNode.hasKey("lastDeathWave"):
    settings.lastDeathWave = jsonNode["lastDeathWave"].getInt()

  if jsonNode.hasKey("hasSeenWaveModeIntro"):
    settings.hasSeenWaveModeIntro = jsonNode["hasSeenWaveModeIntro"].getBool()

  if jsonNode.hasKey("hasSeenSurvivalIntro"):
    settings.hasSeenSurvivalIntro = jsonNode["hasSeenSurvivalIntro"].getBool()

  if jsonNode.hasKey("hasSeenRogueliteIntro"):
    settings.hasSeenRogueliteIntro = jsonNode["hasSeenRogueliteIntro"].getBool()

  if jsonNode.hasKey("hasSeenSandboxIntro"):
    settings.hasSeenSandboxIntro = jsonNode["hasSeenSandboxIntro"].getBool()

  if jsonNode.hasKey("hasSeenPvPIntro"):
    settings.hasSeenPvPIntro = jsonNode["hasSeenPvPIntro"].getBool()

  if jsonNode.hasKey("discoveredPowerUps"):
    settings.discoveredPowerUps = @[]
    for item in jsonNode["discoveredPowerUps"]:
      settings.discoveredPowerUps.add(item.getStr())

  if jsonNode.hasKey("keybinds"):
    let binds = jsonNode["keybinds"]
    for action in KeyAction:
      let key = $action
      if binds.hasKey(key):
        try:
          settings.keybinds[action] = parseEnum[KeyboardKey](binds[key].getStr())
        except ValueError:
          discard

  if jsonNode.hasKey("gamepadBinds"):
    let binds = jsonNode["gamepadBinds"]
    for action in KeyAction:
      let key = $action
      if binds.hasKey(key):
        try:
          settings.gamepadBinds[action] = parseEnum[GamepadButton](binds[key].getStr())
        except ValueError:
          discard

  if jsonNode.hasKey("preferredGamepad"):
    settings.preferredGamepad = jsonNode["preferredGamepad"].getInt()

  if jsonNode.hasKey("aimAssistEnabled"):
    settings.aimAssistEnabled = jsonNode["aimAssistEnabled"].getBool()

# Save Settings to file
proc saveSettings*(settings: Settings): bool =
  let savePath = getSettingsPath()
  try:
    writeFile(savePath, settingsToJson(settings).pretty())
    echo "Settings saved successfully to ", savePath
    return true
  except CatchableError:
    echo "Error saving settings to ", savePath
    return false

# Load Settings from file
proc loadSettings*(settings: Settings): bool =
  let savePath = getSettingsPath()
  if not fileExists(savePath):
    echo "No save file found at ", savePath, ", using default settings"
    return false
  try:
    jsonToSettings(parseJson(readFile(savePath)), settings)
    echo "Settings loaded successfully from ", savePath
    return true
  except Exception as e:
    echo "Error applying settings: ", e.msg
    return false

# Helper to convert Table[EnemyType, int] to JSON
proc enemyTypeIntTableToJson(table: Table[EnemyType, int]): JsonNode =
  result = newJObject()
  for key, val in table:
    result[$key] = %val

# Helper to convert Table[EnemyType, float32] to JSON
proc enemyTypeFloatTableToJson(table: Table[EnemyType, float32]): JsonNode =
  result = newJObject()
  for key, val in table:
    result[$key] = %val

# Helper to convert Table[ConsumableType, int] to JSON
proc consumableTypeTableToJson(table: Table[ConsumableType, int]): JsonNode =
  result = newJObject()
  for key, val in table:
    result[$key] = %val

# Helper to convert Table[PowerUpType, float32] to JSON
proc powerUpTypeFloatTableToJson(table: Table[PowerUpType, float32]): JsonNode =
  result = newJObject()
  for key, val in table:
    result[$key] = %val

# Helper to convert Table[PowerUpType, int] to JSON
proc powerUpTypeIntTableToJson(table: Table[PowerUpType, int]): JsonNode =
  result = newJObject()
  for key, val in table:
    result[$key] = %val

# Convert GameEvent to JSON
proc gameEventToJson(event: GameEvent): JsonNode =
  result = %* {
    "timestamp": event.timestamp,
    "eventType": $event.eventType,
    "value": event.value,
    "details": event.details,
    "position": {
      "x": event.position.x,
      "y": event.position.y
    }
  }

# Convert PowerUp to JSON
proc powerUpToJson(powerUp: PowerUp): JsonNode =
  result = %* {
    "powerType": $powerUp.powerType,
    "level": powerUp.level,
    "rarity": $powerUp.rarity
  }

# Convert CombatStats to JSON
proc combatStatsToJson(stats: CombatStats): JsonNode =
  result = %* {
    "shotsFired": stats.shotsFired,
    "shotsHit": stats.shotsHit,
    "shotsMissed": stats.shotsMissed,
    "accuracyPercent": stats.accuracyPercent,
    "totalDamageDealt": stats.totalDamageDealt,
    "totalDamageTaken": stats.totalDamageTaken,
    "largestSingleHit": stats.largestSingleHit,
    "damageTakenByType": enemyTypeFloatTableToJson(stats.damageTakenByType),
    "totalKills": stats.totalKills,
    "killsByType": enemyTypeIntTableToJson(stats.killsByType),
    "eliteKills": stats.eliteKills,
    "bossKills": stats.bossKills,
    "criticalHits": stats.criticalHits,
    "piercingHits": stats.piercingHits,
    "explosiveHits": stats.explosiveHits,
    "ricochets": stats.ricochets,
    "chainLightningProcs": stats.chainLightningProcs,
    "homingBullets": stats.homingBullets,
    "piercingBullets": stats.piercingBullets,
    "explosiveBullets": stats.explosiveBullets,
    "splitBullets": stats.splitBullets,
    "maxCombo": stats.maxCombo,
    "totalCombos": stats.totalCombos,
    "perfectWaves": stats.perfectWaves,
    "comboSum": stats.comboSum
  }

# Convert MovementStats to JSON
proc movementStatsToJson(stats: MovementStats): JsonNode =
  var positionsArray = newJArray()
  for pos in stats.positionHeatmap:
    positionsArray.add(%* {"x": pos.x, "y": pos.y})

  result = %* {
    "totalDistanceTraveled": stats.totalDistanceTraveled,
    "averageSpeed": stats.averageSpeed,
    "positionHeatmap": positionsArray,
    "phaseShiftsUsed": stats.phaseShiftsUsed,
    "totalPhaseShiftDistance": stats.totalPhaseShiftDistance,
    "timeWarpsUsed": stats.timeWarpsUsed,
    "totalTimeWarpDuration": stats.totalTimeWarpDuration,
    "parriesUsed": stats.parriesUsed,
    "successfulParries": stats.successfulParries,
    "timeInvincible": stats.timeInvincible,
    "timeAtCriticalHP": stats.timeAtCriticalHP,
    "timeAtLowHP": stats.timeAtLowHP,
    "nearDeathCount": stats.nearDeathCount,
    "damageAvoided": stats.damageAvoided,
    "longestNoDamageStreak": stats.longestNoDamageStreak,
    "currentNoDamageStreak": stats.currentNoDamageStreak,
    "hitsTakenCount": stats.hitsTakenCount,
    "averageTimeBetweenHits": stats.averageTimeBetweenHits
  }

# Convert ResourceStats to JSON
proc resourceStatsToJson(stats: ResourceStats): JsonNode =
  var purchasesArray = newJArray()
  for purchase in stats.shopPurchases:
    purchasesArray.add(%* {"timestamp": purchase[0], "item": purchase[1]})

  result = %* {
    "coinsEarned": stats.coinsEarned,
    "coinsSpent": stats.coinsSpent,
    "coinsAtEnd": stats.coinsAtEnd,
    "coinEfficiency": stats.coinEfficiency,
    "wallsPlaced": stats.wallsPlaced,
    "wallsDamaged": stats.wallsDamaged,
    "wallsDestroyed": stats.wallsDestroyed,
    "wallDamageBlocked": stats.wallDamageBlocked,
    "consumablesCollected": stats.consumablesCollected,
    "consumablesByType": consumableTypeTableToJson(stats.consumablesByType),
    "healthConsumablesUsed": stats.healthConsumablesUsed,
    "shopPurchases": purchasesArray,
    "totalSpentInShop": stats.totalSpentInShop,
    "shopVisits": stats.shopVisits
  }

# Convert PowerUpStats to JSON
proc powerUpStatsToJson(stats: PowerUpStats): JsonNode =
  var chosenArray = newJArray()
  for choice in stats.powerUpsChosen:
    chosenArray.add(%* {
      "timestamp": choice[0],
      "powerUp": powerUpToJson(choice[1])
    })

  var elementalArray = newJArray()
  for powerUpType in stats.elementalCombo:
    elementalArray.add(%($powerUpType))

  result = %* {
    "powerUpsChosen": chosenArray,
    "totalPowerUps": stats.totalPowerUps,
    "commonPowerUps": stats.commonPowerUps,
    "legendaryPowerUps": stats.legendaryPowerUps,
    "damageContribution": powerUpTypeFloatTableToJson(stats.damageContribution),
    "killContribution": powerUpTypeIntTableToJson(stats.killContribution),
    "healingContribution": powerUpTypeFloatTableToJson(stats.healingContribution),
    "totalHealingFromPowerUps": stats.totalHealingFromPowerUps,
    "mostEffectivePowerUp": $stats.mostEffectivePowerUp,
    "leastEffectivePowerUp": $stats.leastEffectivePowerUp,
    "synergyScore": stats.synergyScore,
    "elementalCombo": elementalArray,
    "hasSynergy": stats.hasSynergy,
    "level1PowerUps": stats.level1PowerUps,
    "level2PowerUps": stats.level2PowerUps,
    "level3PowerUps": stats.level3PowerUps
  }

# Convert PerformanceStats to JSON
proc performanceStatsToJson(stats: PerformanceStats): JsonNode =
  var waveTimesArray = newJArray()
  for time in stats.waveTimes:
    waveTimesArray.add(%time)

  var dpsHistoryArray = newJArray()
  for entry in stats.dpsHistory:
    dpsHistoryArray.add(%* {"timestamp": entry[0], "dps": entry[1]})

  var streakHistoryArray = newJArray()
  for entry in stats.killStreakHistory:
    streakHistoryArray.add(%* {"timestamp": entry[0], "streak": entry[1]})

  result = %* {
    "waveTimes": waveTimesArray,
    "averageWaveTime": stats.averageWaveTime,
    "fastestWave": stats.fastestWave,
    "slowestWave": stats.slowestWave,
    "peakDPS": stats.peakDPS,
    "averageDPS": stats.averageDPS,
    "dpsHistory": dpsHistoryArray,
    "killsPerMinute": stats.killsPerMinute,
    "damagePerShot": stats.damagePerShot,
    "shotEfficiency": stats.shotEfficiency,
    "longestKillStreak": stats.longestKillStreak,
    "currentKillStreak": stats.currentKillStreak,
    "killStreakHistory": streakHistoryArray
  }

# Convert ComparisonStats to JSON
proc comparisonStatsToJson(stats: ComparisonStats): JsonNode =
  result = %* {
    "accuracyVsOptimal": stats.accuracyVsOptimal,
    "dpsVsOptimal": stats.dpsVsOptimal,
    "survivalVsPredicted": stats.survivalVsPredicted,
    "powerUpQualityScore": stats.powerUpQualityScore,
    "resourceUsageScore": stats.resourceUsageScore,
    "positioningScore": stats.positioningScore,
    "playStyle": stats.playStyle,
    "aggressionRating": stats.aggressionRating,
    "cautionRating": stats.cautionRating
  }

# Convert RunStatistics to JSON
proc runStatisticsToJson*(runStats: RunStatistics): JsonNode =
  if runStats.isNil:
    return newJNull()

  var eventsArray = newJArray()
  for event in runStats.events:
    eventsArray.add(gameEventToJson(event))

  var finalPowerUpsArray = newJArray()
  for powerUp in runStats.finalPowerUps:
    finalPowerUpsArray.add(powerUpToJson(powerUp))
  var rogueliteRelicsArray = newJArray()
  for relicName in runStats.rogueliteRelics:
    rogueliteRelicsArray.add(%relicName)

  result = %* {
    "gameMode": $runStats.gameMode,
    "startTime": runStats.startTime,
    "endTime": runStats.endTime,
    "runDuration": runStats.runDuration,
    "waveReached": runStats.waveReached,
    "finalScore": runStats.finalScore,
    "cheatsUsed": runStats.cheatsUsed,
    "died": runStats.died,
    "combat": combatStatsToJson(runStats.combat),
    "movement": movementStatsToJson(runStats.movement),
    "resources": resourceStatsToJson(runStats.resources),
    "powerUps": powerUpStatsToJson(runStats.powerUps),
    "performance": performanceStatsToJson(runStats.performance),
    "comparison": comparisonStatsToJson(runStats.comparison),
    "events": eventsArray,
    "finalHP": runStats.finalHP,
    "finalMaxHP": runStats.finalMaxHP,
    "finalCoins": runStats.finalCoins,
    "finalPowerUps": finalPowerUpsArray,
    "rogueliteFloorReached": runStats.rogueliteFloorReached,
    "rogueliteRoomsCleared": runStats.rogueliteRoomsCleared,
    "rogueliteHeat": runStats.rogueliteHeat,
    "rogueliteEndlessLoop": runStats.rogueliteEndlessLoop,
    "rogueliteShardsEarned": runStats.rogueliteShardsEarned,
    "rogueliteStarterKit": runStats.rogueliteStarterKit,
    "rogueliteRelics": rogueliteRelicsArray
  }

# Save last run statistics to file
proc saveLastRunStats*(runStats: RunStatistics): bool =
  try:
    if runStats.isNil:
      echo "No run stats to save"
      return false

    let jsonData = runStatisticsToJson(runStats)
    let jsonString = jsonData.pretty()
    let savePath = getLastRunStatsPath()
    writeFile(savePath, jsonString)
    echo "Last run statistics saved successfully to ", savePath
    return true
  except IOError as e:
    echo "Error saving last run stats: ", e.msg
    return false
  except Exception as e:
    echo "Unexpected error saving last run stats: ", e.msg
    return false

# Enum parse helpers. The on-disk format is the Nim symbol name (`$value`), so a
# generic name-based parse round-trips byte-for-byte; `parseEnumOr` (utils.nim)
# preserves the old silent fallback-to-default behavior on unknown input.
proc parseEnemyType(s: string): EnemyType = parseEnumOr(s, etCircle)
proc parsePowerUpRarity(s: string): PowerUpRarity = parseEnumOr(s, prCommon)
proc parseConsumableType(s: string): ConsumableType = parseEnumOr(s, ctHealth)
proc parsePowerUpType(s: string): PowerUpType = parseEnumOr(s, puDoubleShot)
proc parseGameMode(s: string): GameMode = parseEnumOr(s, gmWaveBased)
proc parseGameEventType(s: string): GameEventType = parseEnumOr(s, geKill)

# Convert JSON to GameEvent
proc jsonToGameEvent(j: JsonNode): GameEvent =
  result = GameEvent(
    timestamp: j["timestamp"].getFloat().float32,
    eventType: parseGameEventType(j["eventType"].getStr()),
    value: j["value"].getFloat().float32,
    details: j["details"].getStr(),
    position: newVector2f(
      j["position"]["x"].getFloat().float32,
      j["position"]["y"].getFloat().float32
    )
  )

# Convert JSON to PowerUp
proc jsonToPowerUp(j: JsonNode): PowerUp =
  result = PowerUp(
    powerType: parsePowerUpType(j["powerType"].getStr()),
    level: j["level"].getInt(),
    rarity: parsePowerUpRarity(j["rarity"].getStr())
  )

# Convert JSON to CombatStats
proc jsonToCombatStats(j: JsonNode): CombatStats =
  result = initCombatStats()
  result.shotsFired = j["shotsFired"].getInt()
  result.shotsHit = j["shotsHit"].getInt()
  result.shotsMissed = j["shotsMissed"].getInt()
  result.accuracyPercent = j["accuracyPercent"].getFloat().float32
  result.totalDamageDealt = j["totalDamageDealt"].getFloat().float32
  result.totalDamageTaken = j["totalDamageTaken"].getFloat().float32
  result.largestSingleHit = j["largestSingleHit"].getFloat().float32

  # Parse tables
  for key, val in j["damageTakenByType"]:
    result.damageTakenByType[parseEnemyType(key)] = val.getFloat().float32

  result.totalKills = j["totalKills"].getInt()

  for key, val in j["killsByType"]:
    result.killsByType[parseEnemyType(key)] = val.getInt()

  result.eliteKills = j["eliteKills"].getInt()
  result.bossKills = j["bossKills"].getInt()
  result.criticalHits = j["criticalHits"].getInt()
  result.piercingHits = (if j.hasKey("piercingHits"): j["piercingHits"] elif j.hasKey("piercingShots"): j["piercingShots"] else: newJInt(0)).getInt()
  result.explosiveHits = (if j.hasKey("explosiveHits"): j["explosiveHits"] elif j.hasKey("explosiveKills"): j["explosiveKills"] else: newJInt(0)).getInt()
  result.ricochets = j["ricochets"].getInt()
  result.chainLightningProcs = j["chainLightningProcs"].getInt()
  result.homingBullets = j["homingBullets"].getInt()
  result.piercingBullets = j["piercingBullets"].getInt()
  result.explosiveBullets = j["explosiveBullets"].getInt()
  result.splitBullets = j["splitBullets"].getInt()

  # Load combo stats (with defaults for backwards compatibility)
  result.maxCombo = j.getOrDefault("maxCombo").getInt(0)
  result.totalCombos = j.getOrDefault("totalCombos").getInt(0)
  result.perfectWaves = j.getOrDefault("perfectWaves").getInt(0)
  result.comboSum = j.getOrDefault("comboSum").getInt(0)

# Convert JSON to MovementStats
proc jsonToMovementStats(j: JsonNode): MovementStats =
  result = initMovementStats()
  result.totalDistanceTraveled = j["totalDistanceTraveled"].getFloat().float32
  result.averageSpeed = j["averageSpeed"].getFloat().float32

  # Parse position heatmap
  for pos in j["positionHeatmap"]:
    result.positionHeatmap.add(newVector2f(
      pos["x"].getFloat().float32,
      pos["y"].getFloat().float32
    ))

  result.phaseShiftsUsed = j["phaseShiftsUsed"].getInt()
  result.totalPhaseShiftDistance = j["totalPhaseShiftDistance"].getFloat().float32
  result.timeWarpsUsed = j["timeWarpsUsed"].getInt()
  result.totalTimeWarpDuration = j["totalTimeWarpDuration"].getFloat().float32
  result.parriesUsed = j["parriesUsed"].getInt()
  result.successfulParries = j["successfulParries"].getInt()
  result.timeInvincible = j["timeInvincible"].getFloat().float32
  result.timeAtCriticalHP = j["timeAtCriticalHP"].getFloat().float32
  result.timeAtLowHP = j["timeAtLowHP"].getFloat().float32
  result.nearDeathCount = j["nearDeathCount"].getInt()
  result.damageAvoided = j["damageAvoided"].getFloat().float32
  result.longestNoDamageStreak = j["longestNoDamageStreak"].getFloat().float32
  result.currentNoDamageStreak = j["currentNoDamageStreak"].getFloat().float32
  result.hitsTakenCount = j["hitsTakenCount"].getInt()
  result.averageTimeBetweenHits = j["averageTimeBetweenHits"].getFloat().float32

# Convert JSON to ResourceStats
proc jsonToResourceStats(j: JsonNode): ResourceStats =
  result = initResourceStats()
  result.coinsEarned = j["coinsEarned"].getInt()
  result.coinsSpent = j["coinsSpent"].getInt()
  result.coinsAtEnd = j["coinsAtEnd"].getInt()
  result.coinEfficiency = j["coinEfficiency"].getFloat().float32
  result.wallsPlaced = j["wallsPlaced"].getInt()
  result.wallsDamaged = j["wallsDamaged"].getInt()
  result.wallsDestroyed = j["wallsDestroyed"].getInt()
  result.wallDamageBlocked = j["wallDamageBlocked"].getFloat().float32
  result.consumablesCollected = j["consumablesCollected"].getInt()

  # Parse consumables table
  for key, val in j["consumablesByType"]:
    result.consumablesByType[parseConsumableType(key)] = val.getInt()

  result.healthConsumablesUsed = j["healthConsumablesUsed"].getInt()

  # Parse shop purchases
  for purchase in j["shopPurchases"]:
    result.shopPurchases.add((
      purchase["timestamp"].getFloat().float32,
      purchase["item"].getStr()
    ))

  result.totalSpentInShop = j["totalSpentInShop"].getInt()
  result.shopVisits = j["shopVisits"].getInt()

# Convert JSON to PowerUpStats
proc jsonToPowerUpStats(j: JsonNode): PowerUpStats =
  result = initPowerUpStats()

  # Parse power-ups chosen
  for choice in j["powerUpsChosen"]:
    result.powerUpsChosen.add((
      choice["timestamp"].getFloat().float32,
      jsonToPowerUp(choice["powerUp"])
    ))

  result.totalPowerUps = j["totalPowerUps"].getInt()
  result.commonPowerUps = j["commonPowerUps"].getInt()
  result.legendaryPowerUps = j["legendaryPowerUps"].getInt()

  # Parse damage contribution table
  for key, val in j["damageContribution"]:
    result.damageContribution[parsePowerUpType(key)] = val.getFloat().float32

  # Parse kill contribution table
  for key, val in j["killContribution"]:
    result.killContribution[parsePowerUpType(key)] = val.getInt()

  # Parse healing contribution table
  if j.hasKey("healingContribution"):
    for key, val in j["healingContribution"]:
      result.healingContribution[parsePowerUpType(key)] = val.getFloat().float32
  if j.hasKey("totalHealingFromPowerUps"):
    result.totalHealingFromPowerUps = j["totalHealingFromPowerUps"].getFloat().float32

  result.mostEffectivePowerUp = parsePowerUpType(j["mostEffectivePowerUp"].getStr())
  result.leastEffectivePowerUp = parsePowerUpType(j["leastEffectivePowerUp"].getStr())
  result.synergyScore = j["synergyScore"].getFloat().float32

  # Parse elemental combo
  for element in j["elementalCombo"]:
    result.elementalCombo.add(parsePowerUpType(element.getStr()))

  result.hasSynergy = j["hasSynergy"].getBool()
  result.level1PowerUps = j["level1PowerUps"].getInt()
  result.level2PowerUps = j["level2PowerUps"].getInt()
  result.level3PowerUps = j["level3PowerUps"].getInt()

# Convert JSON to PerformanceStats
proc jsonToPerformanceStats(j: JsonNode): PerformanceStats =
  result = initPerformanceStats()

  # Parse wave times
  for time in j["waveTimes"]:
    result.waveTimes.add(time.getFloat().float32)

  result.averageWaveTime = j["averageWaveTime"].getFloat()
  result.fastestWave = j["fastestWave"].getFloat()
  result.slowestWave = j["slowestWave"].getFloat()
  result.peakDPS = j["peakDPS"].getFloat()
  result.averageDPS = j["averageDPS"].getFloat()

  # Parse DPS history
  for entry in j["dpsHistory"]:
    result.dpsHistory.add((
      entry["timestamp"].getFloat().float32,
      entry["dps"].getFloat().float32
    ))

  result.killsPerMinute = j["killsPerMinute"].getFloat()
  result.damagePerShot = j["damagePerShot"].getFloat()
  result.shotEfficiency = j["shotEfficiency"].getFloat()
  result.longestKillStreak = j["longestKillStreak"].getInt()
  result.currentKillStreak = j["currentKillStreak"].getInt()

  # Parse kill streak history
  for entry in j["killStreakHistory"]:
    result.killStreakHistory.add((
      entry["timestamp"].getFloat().float32,
      entry["streak"].getInt()
    ))

# Convert JSON to ComparisonStats
proc jsonToComparisonStats(j: JsonNode): ComparisonStats =
  result = initComparisonStats()
  result.accuracyVsOptimal = j["accuracyVsOptimal"].getFloat()
  result.dpsVsOptimal = j["dpsVsOptimal"].getFloat()
  result.survivalVsPredicted = j["survivalVsPredicted"].getFloat()
  result.powerUpQualityScore = j["powerUpQualityScore"].getFloat()
  result.resourceUsageScore = j["resourceUsageScore"].getFloat()
  result.positioningScore = j["positioningScore"].getFloat()
  result.playStyle = j["playStyle"].getStr()
  result.aggressionRating = j["aggressionRating"].getFloat()
  result.cautionRating = j["cautionRating"].getFloat()

# Convert JSON to RunStatistics
proc jsonToRunStatistics(j: JsonNode): RunStatistics =
  result = RunStatistics(
    gameMode: parseGameMode(j["gameMode"].getStr()),
    startTime: j["startTime"].getStr(),
    endTime: j["endTime"].getStr(),
    runDuration: j["runDuration"].getFloat(),
    waveReached: j["waveReached"].getInt(),
    finalScore: j["finalScore"].getInt(),
    cheatsUsed: j["cheatsUsed"].getBool(),
    died: j["died"].getBool(),
    combat: jsonToCombatStats(j["combat"]),
    movement: jsonToMovementStats(j["movement"]),
    resources: jsonToResourceStats(j["resources"]),
    powerUps: jsonToPowerUpStats(j["powerUps"]),
    performance: jsonToPerformanceStats(j["performance"]),
    comparison: jsonToComparisonStats(j["comparison"]),
    events: @[],
    finalHP: j["finalHP"].getFloat(),
    finalMaxHP: j["finalMaxHP"].getFloat(),
    finalCoins: j["finalCoins"].getInt(),
    finalPowerUps: @[],
    # Old saves used act/sector names for these run stats; fall back to them.
    rogueliteFloorReached: j.getOrDefault("rogueliteFloorReached").getInt(
      j.getOrDefault("rogueliteActReached").getInt(0)),
    rogueliteRoomsCleared: j.getOrDefault("rogueliteRoomsCleared").getInt(
      j.getOrDefault("rogueliteSectorsCleared").getInt(0)),
    rogueliteHeat: j.getOrDefault("rogueliteHeat").getInt(0),
    rogueliteEndlessLoop: j.getOrDefault("rogueliteEndlessLoop").getInt(0),
    rogueliteShardsEarned: j.getOrDefault("rogueliteShardsEarned").getInt(0),
    rogueliteStarterKit: j.getOrDefault("rogueliteStarterKit").getStr(""),
    rogueliteRelics: @[]
  )

  # Recompute coinsAtEnd from the authoritative finalCoins to fix old saves that stored a wrong value
  result.resources.coinsAtEnd = result.finalCoins

  # Parse events
  for event in j["events"]:
    result.events.add(jsonToGameEvent(event))

  # Parse final power-ups
  for powerUp in j["finalPowerUps"]:
    result.finalPowerUps.add(jsonToPowerUp(powerUp))

  if j.hasKey("rogueliteRelics"):
    for relicName in j["rogueliteRelics"]:
      result.rogueliteRelics.add(relicName.getStr())

# Load last run statistics from file
proc loadLastRunStats*(): RunStatistics =
  try:
    let savePath = getLastRunStatsPath()
    if not fileExists(savePath):
      echo "No last run stats file found at ", savePath
      return nil

    let jsonString = readFile(savePath)
    let jsonData = parseJson(jsonString)
    result = jsonToRunStatistics(jsonData)
    echo "Last run statistics loaded successfully from ", savePath
    return result
  except IOError as e:
    echo "Error loading last run stats: ", e.msg
    return nil
  except JsonParsingError as e:
    echo "Error parsing last run stats file: ", e.msg
    return nil
  except Exception as e:
    echo "Unexpected error loading last run stats: ", e.msg
    return nil
