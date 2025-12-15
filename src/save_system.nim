import json, os, settings_types

# Get AppData directory path
proc getAppDataPath*(): string =
  when defined(windows):
    result = getEnv("APPDATA")
  elif defined(macosx):
    result = getEnv("HOME") & "/Library/Application Support"
  else:  # Linux and other Unix-like systems
    result = getEnv("HOME") & "/.local/share"
  
  # Add game folder
  result = result / ".tophat" / "shooter"
  
  # Create directory if it doesn't exist
  if not dirExists(result):
    try:
      createDir(result)
      echo "Created save directory: ", result
    except:
      echo "Warning: Could not create save directory: ", result

# Path to the save files
proc getSettingsPath*(): string =
  getAppDataPath() / "settings.json"

proc getStatsPath*(): string =
  getAppDataPath() / "stats.json"

# Convert Settings to JSON
proc settingsToJson*(settings: Settings): JsonNode =
  result = %* {
    "fpsLimit": settings.fpsLimit,
    "volume": settings.volume,
    "musicVolume": settings.musicVolume,
    "fullscreen": settings.fullscreen,
    "showFPS": settings.showFPS,
    "mouseSupport": settings.mouseSupport,
    "showCursorInMenus": settings.showCursorInMenus,
    "showDebugStats": settings.showDebugStats,
    "showHints": settings.showHints
  }

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
  
  if jsonNode.hasKey("showFPS"):
    settings.showFPS = jsonNode["showFPS"].getBool()
  
  if jsonNode.hasKey("mouseSupport"):
    settings.mouseSupport = jsonNode["mouseSupport"].getBool()
  
  if jsonNode.hasKey("showCursorInMenus"):
    settings.showCursorInMenus = jsonNode["showCursorInMenus"].getBool()
  
  if jsonNode.hasKey("showDebugStats"):
    settings.showDebugStats = jsonNode["showDebugStats"].getBool()
  
  if jsonNode.hasKey("showHints"):
    settings.showHints = jsonNode["showHints"].getBool()

# Save Settings to file
proc saveSettings*(settings: Settings): bool =
  try:
    let jsonData = settingsToJson(settings)
    let jsonString = jsonData.pretty()
    let savePath = getSettingsPath()
    writeFile(savePath, jsonString)
    echo "Settings saved successfully to ", savePath
    return true
  except IOError as e:
    echo "Error saving settings: ", e.msg
    return false
  except Exception as e:
    echo "Unexpected error saving settings: ", e.msg
    return false

# Load Settings from file
proc loadSettings*(settings: Settings): bool =
  try:
    let savePath = getSettingsPath()
    if not fileExists(savePath):
      echo "No save file found at ", savePath, ", using default settings"
      return false
    
    let jsonString = readFile(savePath)
    let jsonData = parseJson(jsonString)
    jsonToSettings(jsonData, settings)
    echo "Settings loaded successfully from ", savePath
    return true
  except IOError as e:
    echo "Error loading settings: ", e.msg
    return false
  except JsonParsingError as e:
    echo "Error parsing settings file: ", e.msg
    return false
  except Exception as e:
    echo "Unexpected error loading settings: ", e.msg
    return false
