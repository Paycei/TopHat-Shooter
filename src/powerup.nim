import raylib, types, random, math, strutils

proc getPowerUpName*(powerType: PowerUpType): string =
  case powerType
  of puDoubleShot: "Double Shot"
  of puRotatingShield: "Rotating Shield"
  of puDamageZone: "Damage Aura"
  of puHomingBullets: "Homing Bullets"
  of puPiercingShots: "Piercing Shots"
  of puMultiShot: "Multi-Shot"
  of puExplosiveBullets: "Explosive Rounds"
  of puLifeSteal: "Life Steal"
  of puRapidFire: "Rapid Fire"
  of puMaxHealth: "Vitality"
  of puSpeedBoost: "Agility"
  of puBulletDamage: "Power"
  of puBulletSpeed: "Velocity"
  of puLuckyCoins: "Greed"
  of puWallMaster: "Fortify"
  of puAutoShoot: "Auto-Target"
  of puBulletSize: "Giant Bullets"
  of puRegeneration: "Regeneration"
  of puDodgeChance: "Evasion"
  of puCriticalHit: "Critical Strike"
  of puVampirism: "Vampirism"
  of puBulletRicochet: "Ricochet"
  of puSlowField: "Slow Field"
  of puRage: "Rage"
  of puBerserker: "Berserker"
  of puThorns: "Thorns"
  of puBulletSplit: "Split Shot"
  of puChainLightning: "Chain Lightning"
  of puFrostShots: "Frost Shots"
  of puPoisonDamage: "Poison"
proc getPowerUpDescription*(powerType: PowerUpType, level: int): string =
  case powerType
  of puDoubleShot:
    case level
    of 1: "Fire 2 bullets per shot"
    of 2: "Fire 3 bullets per shot"
    else: "Fire 4 bullets per shot"
  of puRotatingShield:
    case level
    of 1: "2 shields (20% coverage)"
    of 2: "3 shields (40% coverage)"
    else: "4 shields (70% coverage)"
  of puDamageZone:
    case level
    of 1: "2 dmg/sec in 50 radius"
    of 2: "5 dmg/sec in 100 radius"
    else: "10 dmg/sec in 150 radius"
  of puHomingBullets:
    case level
    of 1: "Bullets barely track enemies"
    of 2: "Bullets track enemies"
    else: "Bullets aggressively track"
  of puPiercingShots:
    case level
    of 1: "Bullets pierce 1 enemy"
    of 2: "Bullets pierce 2 enemies"
    else: "Bullets pierce 3 enemies"
  of puMultiShot:
    case level
    of 1: "Shoot in 3 directions (narrow)"
    of 2: "Shoot in 3 directions (wide)"
    else: "Shoot in 5 directions"
  of puExplosiveBullets:
    case level
    of 1: "Bullets explode (small radius)"
    of 2: "Bullets explode (medium radius)"
    else: "Bullets explode (large radius)"
  of puLifeSteal:
    case level
    of 1: "Heal 1 HP per 10 kills"
    of 2: "Heal 1 HP per 7 kills"
    else: "Heal 1 HP per 4 kills"
  of puRapidFire:
    case level
    of 1: "+25% fire rate"
    of 2: "+50% fire rate"
    else: "+80% fire rate"
  of puMaxHealth:
    case level
    of 1: "+2 max HP"
    of 2: "+4 max HP"
    else: "+7 max HP"
  of puSpeedBoost:
    case level
    of 1: "+20% movement speed"
    of 2: "+40% movement speed"
    else: "+70% movement speed"
  of puBulletDamage:
    case level
    of 1: "+50% bullet damage"
    of 2: "+100% bullet damage"
    else: "+180% bullet damage"
  of puBulletSpeed:
    case level
    of 1: "+30% bullet speed"
    of 2: "+60% bullet speed"
    else: "+100% bullet speed"
  of puLuckyCoins:
    case level
    of 1: "+30% coin drops"
    of 2: "+70% coin drops"
    else: "+150% coin drops"
  of puWallMaster:
    case level
    of 1: "Walls have +50% HP"
    of 2: "Walls have +120% HP"
    else: "Walls have +250% HP"
  of puAutoShoot:
    case level
    of 1: "Auto-fire (60% rate, 250 range)"
    of 2: "Auto-fire (80% rate, 350 range)"
    else: "Auto-fire (full rate, 450 range)"
  of puBulletSize:
    case level
    of 1: "+40% bullet size"
    of 2: "+80% bullet size"
    else: "+140% bullet size"
  of puRegeneration:
    case level
    of 1: "Regen 1 HP per 15s"
    of 2: "Regen 1 HP per 11s"
    else: "Regen 1 HP per 8s"
  of puDodgeChance:
    case level
    of 1: "12% chance to dodge hits"
    of 2: "20% chance to dodge hits"
    else: "30% chance to dodge hits"
  of puCriticalHit:
    case level
    of 1: "15% chance for 2x damage"
    of 2: "20% chance for 2.5x damage"
    else: "25% chance for 3x damage"
  of puVampirism:
    case level
    of 1: "Heal 5% of bullet damage"
    of 2: "Heal 10% of bullet damage"
    else: "Heal 18% of bullet damage"
  of puBulletRicochet:
    case level
    of 1: "Bullets ricochet once"
    of 2: "Bullets ricochet twice"
    else: "Bullets ricochet 3 times"
  of puSlowField:
    case level
    of 1: "Slow enemies 30% in 120 radius"
    of 2: "Slow enemies 45% in 160 radius"
    else: "Slow enemies 55% in 200 radius"
  of puRage:
    case level
    of 1: "+5% dmg per 10% HP lost"
    of 2: "+8% dmg per 10% HP lost"
    else: "+12% dmg per 10% HP lost"
  of puBerserker:
    case level
    of 1: "+5% fire rate per 10% HP lost"
    of 2: "+8% fire rate per 10% HP lost"
    else: "+15% fire rate per 10% HP lost"
  of puThorns:
    case level
    of 1: "Reflect 20% damage to attacker"
    of 2: "Reflect 40% damage to attacker"
    else: "Reflect 70% damage to attacker"
  of puBulletSplit:
    case level
    of 1: "Bullets split into 2 on hit"
    of 2: "Bullets split into 3 on hit"
    else: "Bullets split into 4 on hit"
  of puChainLightning:
    case level
    of 1: "Hit chains to 1 enemy (70% dmg)"
    of 2: "Hit chains to 2 enemies (80% dmg)"
    else: "Hit chains to 3 enemies (90% dmg)"
  of puFrostShots:
    case level
    of 1: "Bullets slow enemies 25% (permanent)"
    of 2: "Bullets slow enemies 40% (permanent)"
    else: "Bullets slow enemies 60% (permanent)"
  of puPoisonDamage:
    case level
    of 1: "Bullets poison (1 dmg/s, 4s)"
    of 2: "Bullets poison (2 dmg/s, 5s)"
    else: "Bullets poison (4 dmg/s, 6s)"

proc hasPowerUp*(player: Player, powerType: PowerUpType): bool =
  for p in player.powerUps:
    if p.powerType == powerType:
      return true
  return false

proc getPowerUpLevel*(player: Player, powerType: PowerUpType): int =
  for p in player.powerUps:
    if p.powerType == powerType:
      return p.level
  return 0

proc generatePowerUpChoices*(player: Player, isLegendary: bool = false): array[3, PowerUp] =
  # Generate 3 random power-up options
  var availablePowerUps: seq[PowerUp] = @[]
  
  # Define legendary-only powerups (stronger versions)
  let legendaryTypes = [puRapidFire, puMaxHealth, puSpeedBoost, puBulletDamage, 
                        puBulletSpeed, puLuckyCoins, puWallMaster]
  
  if isLegendary:
    # Boss defeated - offer legendary upgrades ONLY
    # First prioritize legendary-exclusive types
    for powerType in legendaryTypes:
      let currentLevel = getPowerUpLevel(player, powerType)
      if currentLevel == 0:
        availablePowerUps.add(PowerUp(powerType: powerType, level: 1, rarity: prLegendary))
      elif currentLevel < 3:
        availablePowerUps.add(PowerUp(powerType: powerType, level: currentLevel + 1, rarity: prLegendary))
    
    # Then include common powerups as legendary versions (for upgrade paths)
    for powerType in PowerUpType:
      if powerType in legendaryTypes:
        continue
      let currentLevel = getPowerUpLevel(player, powerType)
      if currentLevel == 0:
        availablePowerUps.add(PowerUp(powerType: powerType, level: 1, rarity: prLegendary))
      elif currentLevel < 3:
        availablePowerUps.add(PowerUp(powerType: powerType, level: currentLevel + 1, rarity: prLegendary))
  else:
    # Normal wave - offer common upgrades (exclude legendary-only types)
    for powerType in PowerUpType:
      if powerType in legendaryTypes:
        continue
      
      let currentLevel = getPowerUpLevel(player, powerType)
      if currentLevel == 0:
        availablePowerUps.add(PowerUp(powerType: powerType, level: 1, rarity: prCommon))
      elif currentLevel < 3:
        availablePowerUps.add(PowerUp(powerType: powerType, level: currentLevel + 1, rarity: prCommon))
  
  # Shuffle and pick 3
  for i in countdown(availablePowerUps.high, 1):
    let j = rand(i)
    swap(availablePowerUps[i], availablePowerUps[j])
  
  # Fill result with up to 3 power-ups, maintaining rarity correctly
  for i in 0..2:
    if i < availablePowerUps.len:
      result[i] = availablePowerUps[i]
    else:
      # If we run out, create random power-ups with CORRECT rarity
      if isLegendary:
        let randomType = legendaryTypes[rand(legendaryTypes.high)]
        result[i] = PowerUp(powerType: randomType, level: 1, rarity: prLegendary)
      else:
        var randomType: PowerUpType
        while true:
          randomType = PowerUpType(rand(PowerUpType.high.ord))
          if randomType notin legendaryTypes:
            break
        result[i] = PowerUp(powerType: randomType, level: 1, rarity: prCommon)

proc applyPowerUp*(player: Player, powerUp: PowerUp) =
  # Apply immediate stat bonuses for new powerup types
  case powerUp.powerType
  of puRapidFire:
    let bonus = case powerUp.level
      of 1: 0.75
      of 2: 0.5
      else: 0.45
    player.fireRate *= bonus
  of puMaxHealth:
    let hpBonus = case powerUp.level
      of 1: 2.0
      of 2: 4.0
      else: 7.0
    player.maxHp += hpBonus
    player.hp += hpBonus
  of puSpeedBoost:
    let speedBonus = case powerUp.level
      of 1: 1.2
      of 2: 1.4
      else: 1.7
    player.speed *= speedBonus
    player.baseSpeed *= speedBonus
  of puBulletDamage:
    let damageBonus = case powerUp.level
      of 1: 1.5
      of 2: 2.0
      else: 2.8
    player.damage *= damageBonus
  of puBulletSpeed:
    let speedMultiplier = case powerUp.level
      of 1: 1.3
      of 2: 1.6
      else: 2.0
    player.bulletSpeed *= speedMultiplier
  else:
    discard
  
  # Check if player already has this power-up
  var found = false
  for i in 0..<player.powerUps.len:
    if player.powerUps[i].powerType == powerUp.powerType:
      # Upgrade existing power-up
      player.powerUps[i].level = powerUp.level
      player.powerUps[i].rarity = powerUp.rarity
      
      # Apply upgrade bonuses
      case powerUp.powerType
      of puRapidFire:
        let bonus = case powerUp.level
          of 2: 0.67  # Going from 0.75 to 0.5
          of 3: 0.9   # Going from 0.5 to 0.45
          else: 1.0
        player.fireRate *= bonus
      of puMaxHealth:
        let hpBonus = case powerUp.level
          of 2: 2.0  # Additional 2 HP
          of 3: 3.0  # Additional 3 HP
          else: 0.0
        player.maxHp += hpBonus
        player.hp += hpBonus
      of puSpeedBoost:
        let speedBonus = case powerUp.level
          of 2: 1.167  # 1.4 / 1.2
          of 3: 1.214  # 1.7 / 1.4
          else: 1.0
        player.speed *= speedBonus
        player.baseSpeed *= speedBonus
      of puBulletDamage:
        let damageBonus = case powerUp.level
          of 2: 1.333  # 2.0 / 1.5
          of 3: 1.4    # 2.8 / 2.0
          else: 1.0
        player.damage *= damageBonus
      of puBulletSpeed:
        let speedMultiplier = case powerUp.level
          of 2: 1.231  # 1.6 / 1.3
          of 3: 1.25   # 2.0 / 1.6
          else: 1.0
        player.bulletSpeed *= speedMultiplier
      else:
        discard
      
      found = true
      break
  
  if not found:
    # Add new power-up
    player.powerUps.add(powerUp)

proc drawPowerUpCard*(x, y, width, height: int32, powerUp: PowerUp, isSelected: bool) =
  # Card background - different colors for legendary
  let bgColor = if powerUp.rarity == prLegendary:
    if isSelected:
      Color(r: 150, g: 100, b: 200, a: 255)  # Legendary selected
    else:
      Color(r: 80, g: 40, b: 120, a: 255)    # Legendary base
  else:
    if isSelected:
      Color(r: 80, g: 120, b: 200, a: 255)  # Common selected
    else:
      Color(r: 50, g: 50, b: 70, a: 255)    # Common base
  
  drawRectangle(x, y, width, height, bgColor)
  
  # Border - golden for legendary
  let borderColor = if powerUp.rarity == prLegendary:
    if isSelected: Gold else: Color(r: 200, g: 150, b: 50, a: 255)
  else:
    if isSelected: Yellow else: Color(r: 150, g: 150, b: 150, a: 255)
  
  drawRectangleLines(x, y, width, height, borderColor)
  
  # Legendary glow effect
  if powerUp.rarity == prLegendary:
    drawRectangleLines(x - 2, y - 2, width + 4, height + 4, 
                      Color(r: 255, g: 215, b: 0, a: 100))
  
  # Power-up icon/visual indicator
  let iconY = y + 40
  let centerX = x + width div 2
  
  case powerUp.powerType
  of puDoubleShot:
    for i in 0..<powerUp.level + 1:
      let offsetX = (i - powerUp.level div 2) * 12
      drawCircle(Vector2(x: (centerX + offsetX).float32, y: iconY.float32), 8, Yellow)
  of puRotatingShield:
    # Draw the new curved shield visual
    let shieldRadius = 10.0
    let shieldCount = powerUp.level + 1
    for i in 0..<shieldCount:
      let angle1 = i.float32 * PI * 2.0 / shieldCount.float32
      let angle2 = (i + 1).float32 * PI * 2.0 / shieldCount.float32
      for j in 0..8:
        let t1 = j.float32 / 8.0
        let t2 = (j + 1).float32 / 8.0
        let a1 = angle1 + t1 * (angle2 - angle1) * 0.8
        let a2 = angle1 + t2 * (angle2 - angle1) * 0.8
        let x1 = centerX.float32 + cos(a1) * shieldRadius
        let y1 = iconY.float32 + sin(a1) * shieldRadius
        let x2 = centerX.float32 + cos(a2) * shieldRadius
        let y2 = iconY.float32 + sin(a2) * shieldRadius
        drawLine(Vector2(x: x1, y: y1), Vector2(x: x2, y: y2), 2, SkyBlue)
  of puDamageZone:
    let zoneRadius = 10 + powerUp.level * 8
    drawCircle(Vector2(x: centerX.float32, y: iconY.float32), zoneRadius.float32, 
              Color(r: 255, g: 100, b: 0, a: 100))
    drawCircleLines(centerX.int32, iconY.int32, zoneRadius.float32, Orange)
  of puHomingBullets:
    drawCircle(Vector2(x: centerX.float32, y: iconY.float32), 8, Magenta)
    for i in 0..5:
      let t = i.float32 / 5.0
      let curve = sin(t * PI) * 15.0
      drawCircle(Vector2(x: (centerX.float32 + i.float32 * 5), 
                        y: (iconY.float32 - curve)), 3, Purple)
  of puPiercingShots:
    for i in 0..<powerUp.level + 1:
      let offsetX = centerX - 20 + i * 20
      drawCircle(Vector2(x: offsetX.float32, y: iconY.float32), 8, Skyblue)
    drawLine(Vector2(x: (centerX - 30).float32, y: iconY.float32), 
            Vector2(x: (centerX + 30).float32, y: iconY.float32), 3, SkyBlue)
  of puMultiShot:
    let bulletCount = if powerUp.level == 3: 5 else: 3
    let spread = if powerUp.level == 2: 0.5 else: 0.3
    for i in 0..<bulletCount:
      let angle = (i - bulletCount div 2).float32 * spread
      let endX = centerX.float32 + sin(angle) * 25
      let endY = iconY.float32 - cos(angle) * 25
      drawLine(Vector2(x: centerX.float32, y: iconY.float32), 
              Vector2(x: endX, y: endY), 2, Yellow)
      drawCircle(Vector2(x: endX, y: endY), 4, Gold)
  of puExplosiveBullets:
    let explosionSize = 8 + powerUp.level * 4
    drawCircle(Vector2(x: centerX.float32, y: iconY.float32), explosionSize.float32, 
              Color(r: 255, g: 150, b: 0, a: 150))
    drawCircle(Vector2(x: centerX.float32, y: iconY.float32), 5, Orange)
  of puLifeSteal:
    drawCircle(Vector2(x: centerX.float32, y: iconY.float32), 12, Red)
    drawCircle(Vector2(x: (centerX - 5).float32, y: (iconY - 3).float32), 6, Pink)
    drawCircle(Vector2(x: (centerX + 5).float32, y: (iconY - 3).float32), 6, Pink)
  of puRapidFire:
    for i in 0..<3:
      let offsetX = (i - 1) * 15
      drawCircle(Vector2(x: (centerX + offsetX).float32, y: iconY.float32), 6, Orange)
    for i in 0..2:
      let lineY = iconY + (i - 1) * 10
      drawLine(Vector2(x: (centerX - 30).float32, y: lineY.float32),
              Vector2(x: (centerX - 15).float32, y: lineY.float32), 2, Yellow)
  of puMaxHealth:
    drawCircle(Vector2(x: (centerX - 5).float32, y: (iconY - 2).float32), 10, Red)
    drawCircle(Vector2(x: (centerX + 5).float32, y: (iconY - 2).float32), 10, Red)
    drawCircle(Vector2(x: centerX.float32, y: (iconY + 6).float32), 10, Red)
    drawText("+", centerX - 5, iconY - 8, 16, White)
  of puSpeedBoost:
    drawCircle(Vector2(x: centerX.float32, y: (iconY - 10).float32), 8, SkyBlue)
    drawLine(Vector2(x: centerX.float32, y: (iconY - 2).float32),
            Vector2(x: centerX.float32, y: (iconY + 15).float32), 3, SkyBlue)
    for i in 0..3:
      let lineX = centerX - 25 + i * 15
      drawLine(Vector2(x: lineX.float32, y: iconY.float32),
              Vector2(x: (lineX + 10).float32, y: iconY.float32), 2, White)
  of puBulletDamage:
    drawCircle(Vector2(x: centerX.float32, y: iconY.float32), 12, DarkGray)
    for i in 0..7:
      let angle = i.float32 * PI / 4.0
      let startDist = 15.0
      let endDist = 25.0
      let x1 = centerX.float32 + cos(angle) * startDist
      let y1 = iconY.float32 + sin(angle) * startDist
      let x2 = centerX.float32 + cos(angle) * endDist
      let y2 = iconY.float32 + sin(angle) * endDist
      drawLine(Vector2(x: x1, y: y1), Vector2(x: x2, y: y2), 2, Red)
  of puBulletSpeed:
    drawCircle(Vector2(x: (centerX + 20).float32, y: iconY.float32), 6, Yellow)
    for i in 0..4:
      let alpha = 255 - i * 50
      drawCircle(Vector2(x: (centerX + 20 - i * 8).float32, y: iconY.float32), 
                4, Color(r: 255, g: 255, b: 0, a: alpha.uint8))
  of puLuckyCoins:
    for i in 0..2:
      let offsetX = (i - 1) * 15
      drawCircle(Vector2(x: (centerX + offsetX).float32, y: iconY.float32), 8, Gold)
      drawText("$", int32(centerX + offsetX - 4), int32(iconY - 6), 12, DarkGray)
  of puWallMaster:
    for row in 0..2:
      for col in 0..2:
        let offsetX = (col - 1) * 12
        let offsetY = (row - 1) * 12
        drawRectangle(int32(centerX + offsetX - 5), int32(iconY + offsetY - 5), 10.int32, 10.int32, Brown)
        drawRectangleLines(int32(centerX + offsetX - 5), int32(iconY + offsetY - 5), 10.int32, 10.int32, Black)
  of puAutoShoot:
    drawCircle(Vector2(x: centerX.float32, y: iconY.float32), 10, Blue)
    for i in 0..3:
      let angle = i.float32 * PI / 2.0
      let x = centerX.float32 + cos(angle) * 20
      let y = iconY.float32 + sin(angle) * 20
      drawLine(Vector2(x: centerX.float32, y: iconY.float32), Vector2(x: x, y: y), 2, Yellow)
  of puBulletSize:
    drawCircle(Vector2(x: centerX.float32, y: iconY.float32), 6 + powerUp.level.float32 * 3.float32, Yellow)
    drawCircleLines(centerX.int32, iconY.int32, 6 + powerUp.level.float32 * 3.float32, Orange)
  of puRegeneration:
    drawCircle(Vector2(x: centerX.float32, y: iconY.float32), 12, Green)
    drawText("+", centerX - 6, iconY - 8, 18, White)
    for i in 0..3:
      let angle = i.float32 * PI / 2.0
      let dist = 18.0
      let x = centerX.float32 + cos(angle) * dist
      let y = iconY.float32 + sin(angle) * dist
      drawCircle(Vector2(x: x, y: y), 3, Green)
  of puDodgeChance:
    drawCircle(Vector2(x: centerX.float32, y: iconY.float32), 12, Color(r: 100, g: 100, b: 200, a: 150))
    drawCircle(Vector2(x: (centerX - 8).float32, y: iconY.float32), 5, Blue)
    drawCircle(Vector2(x: (centerX + 8).float32, y: iconY.float32), 5, Blue)
  of puCriticalHit:
    drawCircle(Vector2(x: centerX.float32, y: iconY.float32), 10, Red)
    drawText("!", centerX - 3, iconY - 8, 18, Yellow)
    for i in 0..7:
      let angle = i.float32 * PI / 4.0
      let dist = 18.0
      let x = centerX.float32 + cos(angle) * dist
      let y = iconY.float32 + sin(angle) * dist
      drawCircle(Vector2(x: x, y: y), 2, Orange)
  of puVampirism:
    drawCircle(Vector2(x: centerX.float32, y: iconY.float32), 12, Red)
    drawCircle(Vector2(x: (centerX - 5).float32, y: (iconY - 3).float32), 6, Red)
    drawCircle(Vector2(x: (centerX + 5).float32, y: (iconY - 3).float32), 6, Red)
    drawText("+", centerX - 4, iconY + 5, 12, Green)
  of puBulletRicochet:
    drawCircle(Vector2(x: centerX.float32, y: iconY.float32), 6, Yellow)
    let bounces = powerUp.level
    for i in 1..bounces:
      let offsetX = i * 15
      let offsetY = if i mod 2 == 0: -10 else: 10
      drawCircle(Vector2(x: (centerX + offsetX).float32, y: (iconY + offsetY).float32), 6, Yellow)
      drawLine(Vector2(x: (centerX + (i-1) * 15).float32, y: (iconY + (if (i-1) mod 2 == 0: -10 else: 10)).float32),
              Vector2(x: (centerX + offsetX).float32, y: (iconY + offsetY).float32), 2, Orange)
  of puSlowField:
    let radius = 10 + powerUp.level * 5
    drawCircle(Vector2(x: centerX.float32, y: iconY.float32), radius.float32, 
              Color(r: 100, g: 150, b: 255, a: 80))
    drawCircleLines(centerX.int32, iconY.int32, radius.float32, Blue)
    drawText("SLOW", centerX - 18, iconY - 6, 12, White)
  of puRage:
    drawCircle(Vector2(x: centerX.float32, y: iconY.float32), 12, Red)
    for i in 0..5:
      let angle = i.float32 * PI / 3.0
      let dist = 18.0
      let x = centerX.float32 + cos(angle) * dist
      let y = iconY.float32 + sin(angle) * dist
      drawLine(Vector2(x: centerX.float32, y: iconY.float32), Vector2(x: x, y: y), 3, Orange)
  of puBerserker:
    drawCircle(Vector2(x: centerX.float32, y: iconY.float32), 12, Red)
    for i in 0..<3:
      let offsetX = (i - 1) * 12
      drawCircle(Vector2(x: (centerX + offsetX).float32, y: (iconY - 15).float32), 4, Red)
  of puThorns:
    drawCircle(Vector2(x: centerX.float32, y: iconY.float32), 10, Brown)
    for i in 0..7:
      let angle = i.float32 * PI / 4.0
      let dist = 12.0
      let x = centerX.float32 + cos(angle) * dist
      let y = iconY.float32 + sin(angle) * dist
      drawLine(Vector2(x: centerX.float32, y: iconY.float32), Vector2(x: x, y: y), 2, Gray)
  of puBulletSplit:
    drawCircle(Vector2(x: centerX.float32, y: (iconY - 10).float32), 6, Yellow)
    let splits = powerUp.level + 1
    for i in 0..<splits:
      let angle = (i - splits div 2).float32 * 0.4
      let x = centerX.float32 + sin(angle) * 20
      let y = iconY.float32 + 10 + cos(angle) * 5
      drawCircle(Vector2(x: x, y: y), 4, Orange)
      drawLine(Vector2(x: centerX.float32, y: iconY.float32), Vector2(x: x, y: y), 2, Yellow)
  of puChainLightning:
    drawCircle(Vector2(x: centerX.float32, y: iconY.float32), 8, Yellow)
    let chains = powerUp.level
    for i in 1..chains:
      let offsetX = i * 15
      drawCircle(Vector2(x: (centerX + offsetX).float32, y: iconY.float32), 6, Color(r: 200, g: 200, b: 0, a: 200))
      for j in 0..3:
        let x1 = centerX.float32 + ((i-1) * 15).float32 + j.float32 * 3.75
        let y1 = iconY.float32 + (if j mod 2 == 0: -5 else: 5).float32
        let x2 = x1 + 3.75
        let y2 = iconY.float32 + (if j mod 2 == 0: 5 else: -5).float32
        drawLine(Vector2(x: x1, y: y1), Vector2(x: x2, y: y2), 2, Color(r: 255, g: 255, b: 100, a: 255))
  of puFrostShots:
    drawCircle(Vector2(x: centerX.float32, y: iconY.float32), 8, SkyBlue)
    for i in 0..5:
      let angle = i.float32 * PI / 3.0
      let dist = 16.0
      let x = centerX.float32 + cos(angle) * dist
      let y = iconY.float32 + sin(angle) * dist
      drawCircle(Vector2(x: x, y: y), 3, Color(r: 200, g: 230, b: 255, a: 255))
  of puPoisonDamage:
    drawCircle(Vector2(x: centerX.float32, y: iconY.float32), 10, Green)
    for i in 0..3:
      let offsetY = -15 + i * 5
      drawCircle(Vector2(x: centerX.float32, y: (iconY + offsetY).float32), 4, Color(r: 100, g: 255, b: 100, a: 180))
  
  # Rarity indicator
  if powerUp.rarity == prLegendary:
    let rarityText = "LEGENDARY"
    let rarityWidth = measureText(rarityText, 14)
    drawText(rarityText, x + (width - rarityWidth) div 2, y + 10, 14, Gold)
  
  # Power-up name
  let name = getPowerUpName(powerUp.powerType)
  let nameWidth = measureText(name, 20)
  drawText(name, x + (width - nameWidth) div 2, y + 90, 20, White)
  
  # Level indicator
  let levelText = "Level " & $powerUp.level
  let levelWidth = measureText(levelText, 16)
  let levelColor = if powerUp.rarity == prLegendary: Gold else: Yellow
  drawText(levelText, x + (width - levelWidth) div 2, y + 115, 16, levelColor)
  
  # Description
  let desc = getPowerUpDescription(powerUp.powerType, powerUp.level)
  let descWidth = measureText(desc, 14)
  # Wrap text if too long
  if descWidth > width - 20:
    let words = desc.split(' ')
    var line = ""
    var yOffset = 140
    for word in words:
      let testLine = if line == "": word else: line & " " & word
      if measureText(testLine, 14) > width - 20:
        let lineWidth = measureText(line, 14)
        drawText(line, (x + (width - lineWidth) div 2).int32, (y + yOffset).int32, 14.int32, LightGray)
        line = word
        yOffset += 18
      else:
        line = testLine
    if line != "":
      let lineWidth = measureText(line, 14)
      drawText(line, (x + (width - lineWidth) div 2).int32, (y + yOffset).int32, 14.int32, LightGray)
  else:
    drawText(desc, x + (width - descWidth) div 2, y + 140, 14, LightGray)

proc drawPowerUpSelection*(game: Game) =
  let screenWidth = game.screenWidth
  let screenHeight = game.screenHeight
  
  # Dark overlay
  drawRectangle(0, 0, screenWidth, screenHeight, Color(r: 0, g: 0, b: 0, a: 220))
  
  # Determine if this is a legendary selection (after boss)
  let isLegendary = game.powerUpChoices[0].rarity == prLegendary
  
  # Title
  if isLegendary:
    drawText("BOSS DEFEATED!", screenWidth div 2 - 200, 40, 50, Gold)
    drawText("Choose Your LEGENDARY Upgrade", screenWidth div 2 - 230, 100, 30, Color(r: 255, g: 215, b: 0, a: 255))
  else:
    drawText("WAVE COMPLETE!", screenWidth div 2 - 180, 60, 50, Green)
    drawText("Choose Your Power-Up", screenWidth div 2 - 180, 120, 30, White)
  
  # Draw 3 cards
  let cardWidth = 200
  let cardHeight = 240
  let spacing = 40
  let totalWidth = cardWidth * 3 + spacing * 2
  let startX = (screenWidth - totalWidth) div 2
  let cardY = if isLegendary: 160 else: 180
  
  for i in 0..2:
    let cardX = startX + i * (cardWidth + spacing)
    drawPowerUpCard(cardX.int32, cardY.int32, cardWidth.int32, cardHeight.int32,
                   game.powerUpChoices[i], i == game.selectedPowerUp)
  
  # Combined Shop/Power-up instructions
  drawText("ARROW KEYS: select | ENTER: choose power-up", 
          screenWidth div 2 - 280, screenHeight - 120, 20, LightGray)
  drawText("ESC: skip power-up", 
          screenWidth div 2 - 200, screenHeight - 90, 18, Color(r: 180, g: 180, b: 180, a: 255))
  
  # Display coin count
  let coinText = "Coins: " & $game.player.coins
  drawText(coinText, screenWidth div 2 - 60, screenHeight - 55, 22, Gold)
