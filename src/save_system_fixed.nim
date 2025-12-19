# Convert PowerUp to JSON
proc powerUpToJson(powerUp: PowerUp): JsonNode =
  result = %* {
    "powerType": $powerUp.powerType,
    "level": powerUp.level,
    "rarity": $powerUp.rarity
  }

# Helper to parse PowerUpRarity from string
proc parsePowerUpRarity(s: string): PowerUpRarity =
  case s
  of "prCommon": prCommon
  of "prLegendary": prLegendary
  else: prCommon

# Convert JSON to PowerUp  
proc jsonToPowerUp(j: JsonNode): PowerUp =
  result = PowerUp(
    powerType: parsePowerUpType(j["powerType"].getStr()),
    level: j["level"].getInt(),
    rarity: parsePowerUpRarity(j["rarity"].getStr())
  )
