import json, os, settings_types, run_statistics, types, std/tables

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

proc getLastRunStatsPath*(): string =
  getAppDataPath() / "last_run.json"

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


# ============================================================================
# RUN STATISTICS SAVE/LOAD
# ============================================================================

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
    "piercingShots": stats.piercingShots,
    "explosiveKills": stats.explosiveKills,
    "ricochets": stats.ricochets,
    "chainLightningProcs": stats.chainLightningProcs,
    "homingBullets": stats.homingBullets,
    "piercingBullets": stats.piercingBullets,
    "explosiveBullets": stats.explosiveBullets,
    "splitBullets": stats.splitBullets
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
    "finalPowerUps": finalPowerUpsArray
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

# Helper to parse EnemyType from string
proc parseEnemyType(s: string): EnemyType =
  case s
  of "etCircle": etCircle
  of "etCube": etCube
  of "etTriangle": etTriangle
  of "etStar": etStar
  of "etHexagon": etHexagon
  of "etCross": etCross
  of "etDiamond": etDiamond
  of "etOctagon": etOctagon
  of "etPentagon": etPentagon
  of "etTrickster": etTrickster
  of "etPhantom": etPhantom
  of "etSniper": etSniper
  else: etCircle

# Helper to parse PowerUpRarity from string
proc parsePowerUpRarity(s: string): PowerUpRarity =
  case s
  of "prCommon": prCommon
  of "prLegendary": prLegendary
  else: prCommon

# Helper to parse ConsumableType from string
proc parseConsumableType(s: string): ConsumableType =
  case s
  of "ctHealth": ctHealth
  of "ctSpeed": ctSpeed
  of "ctCoin": ctCoin
  of "ctInvincibility": ctInvincibility
  of "ctFireRate": ctFireRate
  of "ctMagnet": ctMagnet
  else: ctHealth

# Helper to parse PowerUpType from string
proc parsePowerUpType(s: string): PowerUpType =
  case s
  of "puDoubleShot": puDoubleShot
  of "puRotatingShield": puRotatingShield
  of "puDamageZone": puDamageZone
  of "puMagicalBullets": puMagicalBullets
  of "puPiercingShots": puPiercingShots
  of "puMultiShot": puMultiShot
  of "puExplosiveBullets": puExplosiveBullets
  of "puLifeSteal": puLifeSteal
  of "puRapidFire": puRapidFire
  of "puMaxHealth": puMaxHealth
  of "puSpeedBoost": puSpeedBoost
  of "puBulletDamage": puBulletDamage
  of "puBulletSpeed": puBulletSpeed
  of "puLuckyCoins": puLuckyCoins
  of "puWallMaster": puWallMaster
  of "puAutoShoot": puAutoShoot
  of "puBulletSize": puBulletSize
  of "puRegeneration": puRegeneration
  of "puDodgeChance": puDodgeChance
  of "puCriticalHit": puCriticalHit
  of "puBloodBullets": puBloodBullets
  of "puBulletRicochet": puBulletRicochet
  of "puSlowField": puSlowField
  of "puRage": puRage
  of "puBerserker": puBerserker
  of "puThorns": puThorns
  of "puBulletSplit": puBulletSplit
  of "puChainLightning": puChainLightning
  of "puFrostShots": puFrostShots
  of "puPoisonShot": puPoisonShot
  of "puFireBullets": puFireBullets
  of "puWindBullets": puWindBullets
  of "puFireAura": puFireAura
  of "puLightningAura": puLightningAura
  of "puPoisonAura": puPoisonAura
  of "puWindAura": puWindAura
  of "puTimeWarp": puTimeWarp
  of "puGravityWell": puGravityWell
  of "puPhaseShift": puPhaseShift
  of "puOvercharge": puOvercharge
  of "puEchoShots": puEchoShots
  of "puRotatingOrbs": puRotatingOrbs
  of "puPoisonOrb": puPoisonOrb
  of "puFireOrb": puFireOrb
  of "puLightningOrb": puLightningOrb
  of "puWindOrb": puWindOrb
  of "puFrostOrb": puFrostOrb
  of "puArcaneOrb": puArcaneOrb
  of "puArcaneBullets": puArcaneBullets
  of "puArcaneAura": puArcaneAura
  of "puFireMastery": puFireMastery
  of "puPoisonMastery": puPoisonMastery
  of "puFrostMastery": puFrostMastery
  of "puArcaneMastery": puArcaneMastery
  of "puLightningMastery": puLightningMastery
  of "puWindMastery": puWindMastery
  of "puParry": puParry
  of "puBloodOrb": puBloodOrb
  of "puBloodAura": puBloodAura
  of "puBloodMastery": puBloodMastery
  else: puDoubleShot

# Helper to parse GameMode from string
proc parseGameMode(s: string): GameMode =
  case s
  of "gmWaveBased": gmWaveBased
  of "gmTimeSurvival": gmTimeSurvival
  else: gmWaveBased

# Helper to parse GameEventType from string
proc parseGameEventType(s: string): GameEventType =
  case s
  of "geKill": geKill
  of "geDamageTaken": geDamageTaken
  of "geDamageDealt": geDamageDealt
  of "gePowerUpChosen": gePowerUpChosen
  of "geShopPurchase": geShopPurchase
  of "geWaveComplete": geWaveComplete
  of "geBossSpawn": geBossSpawn
  of "geBossDefeat": geBossDefeat
  of "geNearDeath": geNearDeath
  of "geLegendaryUsed": geLegendaryUsed
  of "geWallPlaced": geWallPlaced
  of "geCoinCollected": geCoinCollected
  of "geConsumableUsed": geConsumableUsed
  else: geKill

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
  result.piercingShots = j["piercingShots"].getInt()
  result.explosiveKills = j["explosiveKills"].getInt()
  result.ricochets = j["ricochets"].getInt()
  result.chainLightningProcs = j["chainLightningProcs"].getInt()
  result.homingBullets = j["homingBullets"].getInt()
  result.piercingBullets = j["piercingBullets"].getInt()
  result.explosiveBullets = j["explosiveBullets"].getInt()
  result.splitBullets = j["splitBullets"].getInt()

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
    finalPowerUps: @[]
  )
  
  # Parse events
  for event in j["events"]:
    result.events.add(jsonToGameEvent(event))
  
  # Parse final power-ups
  for powerUp in j["finalPowerUps"]:
    result.finalPowerUps.add(jsonToPowerUp(powerUp))

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
