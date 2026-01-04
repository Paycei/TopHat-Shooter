## OS-Style Process Installer - Enhanced Edition
## Power-up selection screen as modern software installation interface
## REDESIGNED with improved visuals, animations, and polish
## NOW WITH SLOT MACHINE ROLL ANIMATION!

import raylib, types, math, strutils, icon_drawing

# Roll animation uses data from game.rollPosition, game.rollSpeed, game.rollPowerUpList
# No need for separate global state - the animation system in powerup.nim handles it

proc getPowerUpName*(powerType: PowerUpType): string =
  case powerType
  of puDoubleShot: "Double Shot"
  of puRotatingShield: "Rotating Shield"
  of puDamageZone: "Damage Aura"
  of puMagicalBullets: "Magical Bullets"
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
  of puBloodBullets: "Blood Bullets"
  of puBulletRicochet: "Ricochet"
  of puSlowField: "Slow Field"
  of puRage: "Rage"
  of puBerserker: "Berserker"
  of puThorns: "Thorns"
  of puBulletSplit: "Split Shot"
  of puChainLightning: "Chain Lightning"
  of puFrostShots: "Frost Shots"
  of puPoisonShot: "Poison Shots"
  of puFireBullets: "Fire Bullets"
  of puWindBullets: "Wind Bullets"
  of puFireAura: "Fire Aura"
  of puLightningAura: "Lightning Aura"
  of puPoisonAura: "Poison Aura"
  of puWindAura: "Wind Aura"
  of puTimeWarp: "Chronos"
  of puGravityWell: "Singularity"
  of puPhaseShift: "Phase Walker"
  of puOvercharge: "Momentum"
  of puEchoShots: "Echo Strike"
  of puRotatingOrbs: "Elemental Orbs"
  of puPoisonOrb: "Poison Orbs"
  of puFireOrb: "Fire Orbs"
  of puLightningOrb: "Lightning Orbs"
  of puWindOrb: "Wind Orbs"
  of puFrostOrb: "Frost Orbs"
  of puArcaneBullets: "Arcane Bullets"
  of puArcaneAura: "Arcane Aura"
  of puArcaneOrb: "Arcane Orbs"
  of puFireMastery: "Inferno Mastery"
  of puPoisonMastery: "Toxic Overlord"
  of puFrostMastery: "Frost King"
  of puArcaneMastery: "Arcane Ascension"
  of puLightningMastery: "Storm Lord"
  of puWindMastery: "Wind Master"
  of puParry: "Parry"
  of puBloodOrb: "Blood Orbs"
  of puBloodAura: "Blood Aura"
  of puBloodMastery: "Blood Lord"

proc getPowerUpDescription*(powerType: PowerUpType, level: int): string =
  case powerType
  of puDoubleShot:
    "Fire 2 bullets per shot (-25% fire rate)"
  of puRotatingShield:
    case level
    of 1: "3 shields (30% coverage, 3 HP, 4s respawn)"
    of 2: "3 shields (35% coverage, 4 HP, 3s respawn)"
    else: "3 shields (40% coverage, 5 HP, 2s respawn)"
  of puDamageZone:
    case level
    of 1: "3 dmg/sec in 120 radius"
    of 2: "6 dmg/sec in 160 radius"
    else: "12 dmg/sec in 200 radius"
  of puMagicalBullets:
    "Bullets track nearest enemy"
  of puPiercingShots:
    case level
    of 1: "Bullets pierce 1 enemy (-33% damage per pierce)"
    of 2: "Bullets pierce 2 enemies (-33% damage per pierce)"
    else: "Bullets pierce 3 enemies (-33% damage per pierce)"
  of puMultiShot:
    "Shoot in 3 directions"
  of puExplosiveBullets:
    case level
    of 1: "Bullets explode (small radius)"
    of 2: "Bullets explode (medium radius)"
    else: "Bullets explode (large radius)"
  of puLifeSteal:
    case level
    of 1: "Heal 1 HP per 20 kills"
    of 2: "Heal 1 HP per 15 kills"
    else: "Heal 1 HP per 10 kills"
  of puRapidFire:
    "+40% fire rate"
  of puMaxHealth:
    "+14 max HP"
  of puSpeedBoost:
    "+50% movement speed"
  of puBulletDamage:
    "+100% bullet damage"
  of puBulletSpeed:
    "+35% bullet speed"
  of puLuckyCoins:
    "Doubles all coins collected"
  of puWallMaster:
    "Walls have +250% HP"
  of puAutoShoot:
    "Auto-fire at nearest enemy (90% fire rate, 450 range)"
  of puBulletSize:
    case level
    of 1: "+50% bullet size"
    of 2: "+100% bullet size"
    else: "+150% bullet size"
  of puRegeneration:
    case level
    of 1: "Regen 1-2 HP per wave"
    of 2: "Regen 2-4 HP per wave"
    else: "Regen 3-6 HP per wave"
  of puDodgeChance:
    case level
    of 1: "15% chance to dodge hits"
    of 2: "20% chance to dodge hits"
    else: "30% chance to dodge hits"
  of puCriticalHit:
    case level
    of 1: "20% chance for 2.5x damage (all sources)"
    of 2: "30% chance for 2.5x damage (all sources)"
    else: "40% chance for 2.5x damage (all sources)"
  of puBloodBullets:
    case level
    of 1: "Heal 2.5% of bullet damage (blood element)"
    of 2: "Heal 3.5% of bullet damage (blood element)"
    else: "Heal 5% of bullet damage (blood element)"
  of puBulletRicochet:
    case level
    of 1: "Bullets ricochet once (75% damage per ricochet)"
    of 2: "Bullets ricochet twice (75% damage per ricochet)"
    else: "Bullets ricochet 3 times (75% damage per ricochet)"
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
    else: "+12% fire rate per 10% HP lost"
  of puThorns:
    case level
    of 1: "Reflect 50% damage to attacker"
    of 2: "Reflect 100% damage to attacker"
    else: "Reflect 150% damage to attacker"
  of puBulletSplit:
    case level
    of 1: "Bullets split into 2 on hit"
    of 2: "Bullets split into 3 on hit"
    else: "Bullets split into 4 on hit"
  of puChainLightning:
    case level
    of 1: "Hit chains to 1 enemy (70% dmg, 120 range, 0.05s stun)"
    of 2: "Hit chains to 2 enemies (85% dmg, 140 range, 0.05s stun)"
    else: "Hit chains to 3 enemies (100% dmg, 160 range, 0.05s stun)"
  of puFrostShots:
    case level
    of 1: "Bullets slow enemies 25% (permanent)"
    of 2: "Bullets slow enemies 40% (permanent)"
    else: "Bullets slow enemies 60% (permanent)"
  of puPoisonShot:
    case level
    of 1: "Bullets poison (0.5 dmg/s, 4s)"
    of 2: "Bullets poison (1 dmg/s, 5s)"
    else: "Bullets poison (2 dmg/s, 6s)"
  of puFireBullets:
    case level
    of 1: "Bullets burn (0.3 dmg/s, 2s)"
    of 2: "Bullets burn (0.75 dmg/s, 3s)"
    else: "Bullets burn (1.5 dmg/s, 4s)"
  of puWindBullets:
    case level
    of 1: "Bullets knock back enemies (weak push)"
    of 2: "Bullets knock back enemies (medium push)"
    else: "Bullets knock back enemies (strong push)"
  of puFireAura:
    case level
    of 1: "Burn enemies 1.5 dmg/s in 120 radius (2s)"
    of 2: "Burn enemies 3 dmg/s in 160 radius (3s)"
    else: "Burn enemies 6 dmg/s in 200 radius (4s)"
  of puLightningAura:
    case level
    of 1: "Zap 0.8 dmg/s in 120 radius (chains 1x)"
    of 2: "Zap 1.6 dmg/s in 160 radius (chains 2x)"
    else: "Zap 3.2 dmg/s in 200 radius (chains 3x)"
  of puPoisonAura:
    case level
    of 1: "Poison 0.6 dmg/s in 120 radius (6s duration)"
    of 2: "Poison 1.2 dmg/s in 160 radius (8s duration)"
    else: "Poison 2.4 dmg/s in 200 radius (10s duration)"
  of puWindAura:
    case level
    of 1: "Push enemies away in 120 radius (weak)"
    of 2: "Push enemies away in 160 radius (medium)"
    else: "Push enemies away in 200 radius (strong)"
  of puTimeWarp:
    "Slow time 50% for 4s (2 uses/wave, 18s cd)"
  of puGravityWell:
    "Pull enemies in 300 radius"
  of puPhaseShift:
    "Dash forward (5s cd, 0.5s invuln, scales with speed)"
  of puOvercharge:
    "+5% dmg per 100 units traveled (max 100%, 80 range)"
  of puEchoShots:
    "Bullets leave ghost trail (50% dmg)"
  of puRotatingOrbs:
    "All 6 elemental orbs (2.5 dmg/hit)"
  of puPoisonOrb:
    case level
    of 1: "2 poison orbs (0.3 dmg/s)"
    of 2: "4 poison orbs (0.3 dmg/s)"
    else: "6 poison orbs (0.3 dmg/s)"
  of puFireOrb:
    case level
    of 1: "2 fire orbs (0.4 dmg/s)"
    of 2: "4 fire orbs (0.4 dmg/s)"
    else: "6 fire orbs (0.4 dmg/s)"
  of puLightningOrb:
    case level
    of 1: "2 lightning orbs (1.5 dmg/hit)"
    of 2: "4 lightning orbs (2 dmg/hit)"
    else: "6 lightning orbs (2.5 dmg/hit)"
  of puWindOrb:
    case level
    of 1: "2 wind orbs (1 dmg/hit, push)"
    of 2: "4 wind orbs (1.5 dmg/hit, push)"
    else: "6 wind orbs (2 dmg/hit, push)"
  of puFrostOrb:
    case level
    of 1: "2 frost orbs (1 dmg/hit, slow)"
    of 2: "4 frost orbs (1.5 dmg/hit, slow)"
    else: "6 frost orbs (2 dmg/hit, slow)"
  of puArcaneOrb:
    case level
    of 1: "2 arcane orbs (1.5 dmg/hit, arcane)"
    of 2: "4 arcane orbs (2 dmg/hit, arcane)"
    else: "6 arcane orbs (2.5 dmg/hit, arcane)"
  of puArcaneBullets:
    case level
    of 1: "Bullets enhanced with arcane power (+50% bullet damage, arcane)"
    of 2: "Bullets enhanced with arcane power (+100% bullet damage, arcane)"
    else: "Bullets enhanced with arcane power (+150% bullet damage, arcane)"
  of puArcaneAura:
    case level
    of 1: "Arcane aura 2 dmg/s in 120 radius, arcane"
    of 2: "Arcane aura 4 dmg/s in 160 radius, arcane"
    else: "Arcane aura 8 dmg/s in 200 radius, arcane"
  of puFireMastery:
    "Fire effects: +150% dmg, +100% duration, +35% slow"
  of puPoisonMastery:
    "Poison effects: +150% dmg, +100% duration, +30% slow"
  of puFrostMastery:
    "Frost effects: +150% dmg, +100% duration, +20% slow"
  of puArcaneMastery:
    "Arcane effects: +200% dmg, +100% duration, piercing"
  of puLightningMastery:
    "Lightning effects: +150% dmg, +100% duration, +25% slow, +1 chain, +50% range"
  of puWindMastery:
    "Wind effects: +150% dmg, +100% duration, +40% slow, stronger push"
  of puParry:
    "Active: Invincible for 0.5s, bounce enemy bullets (5s cooldown)"
  of puBloodOrb:
    case level
    of 1: "2 blood orbs (1.5 dmg/hit, lifesteal)"
    of 2: "4 blood orbs (2 dmg/hit, lifesteal)"
    else: "6 blood orbs (2.5 dmg/hit, lifesteal)"
  of puBloodAura:
    case level
    of 1: "Blood aura 1.5 dmg/s in 120 radius, heal 2.5% dealt"
    of 2: "Blood aura 3 dmg/s in 160 radius, heal 5% dealt"
    else: "Blood aura 6 dmg/s in 200 radius, heal 10% dealt"
  of puBloodMastery:
    "Blood effects: +150% dmg, +100% duration, +50% lifesteal"

# The roll animation system is handled in powerup.nim
# This file only handles the visual drawing of the installer UI

const
  INSTALLER_WIDTH = 1000
  INSTALLER_HEIGHT = 650
  TITLE_BAR_HEIGHT = 45
  CARD_WIDTH = 280
  CARD_HEIGHT = 380
  CARD_SPACING = 35
  PROGRESS_BAR_HEIGHT = 22

proc drawModernButton(x, y, width, height: int32, text: string, 
                     enabled: bool = true, highlight: bool = false, 
                     time: float32 = 0.0) =
  let bgColor = if not enabled:
    Color(r: 35, g: 40, b: 50, a: 255)
  elif highlight:
    Color(r: 0, g: 140, b: 255, a: 255)
  else:
    Color(r: 45, g: 55, b: 70, a: 255)
  
  if enabled:
    drawRectangle(x + 2, y + 2, width, height,
                 Color(r: 0, g: 0, b: 0, a: 80))
  
  drawRectangle(x, y, width, height, bgColor)
  
  if enabled:
    drawRectangle(x, y, width, 2,
                 Color(r: 255, g: 255, b: 255, a: 30))
  
  let borderColor = if not enabled:
    Color(r: 70, g: 80, b: 90, a: 255)
  elif highlight:
    let pulse = sin(time * 5.0) * 0.3 + 0.7
    Color(r: 0, g: 200, b: 255, a: uint8(200 * pulse))
  else:
    Color(r: 100, g: 120, b: 140, a: 255)
  
  let borderWidth = if highlight: 2.5 else: 2.0
  drawRectangleLines(Rectangle(x: x.float32, y: y.float32,
                                width: width.float32, height: height.float32),
                    borderWidth, borderColor)
  
  let textColor = if not enabled: 
    Color(r: 100, g: 100, b: 110, a: 255)
  else: 
    White
  
  let textWidth = measureText(text, 15)
  drawText(text, x + (width - textWidth) div 2, y + (height - 15) div 2, 15, textColor)

proc drawProcessCard(x, y, width, height: int32, powerUp: PowerUp, 
                    selected: bool, time: float32, blurAmount: float32 = 1.0) =
  ## Draw power-up card with motion blur during roll
  
  # Card shadow (reduced during motion)
  if blurAmount > 0.5:
    for i in 0..2:
      let offset = (i + 1) * 2
      let alpha = uint8((40 - i * 10).float32 * blurAmount)
      drawRectangle(int32(x + offset), int32(y + offset), width, height,
                   Color(r: 0, g: 0, b: 0, a: alpha))
  
  # Card background
  let bgColor = if selected:
    Color(r: 35, g: 48, b: 65, a: 255)
  else:
    Color(r: 22, g: 28, b: 40, a: 255)
  
  drawRectangle(x, y, width, height, bgColor)
  
  # Top accent bar
  let accentColor = if powerUp.rarity == prLegendary:
    Color(r: 255, g: 215, b: 0, a: 255)
  else:
    Color(r: 0, g: 180, b: 255, a: 255)
  
  drawRectangle(x, y, width, 4, accentColor)
  
  # Selection glow
  if selected and blurAmount > 0.7:
    let pulse = sin(time * 4.5) * 0.25 + 0.75
    let glowAlpha = uint8(180 * pulse * blurAmount)
    
    for i in 1..3:
      let offset = i * 2
      drawRectangleLines(
        Rectangle(x: (x - offset).float32, y: (y - offset).float32,
                 width: (width + offset * 2).float32, height: (height + offset * 2).float32),
        1, Color(r: 0, g: 200, b: 255, a: uint8(glowAlpha div uint8(i * 2)))
      )
  
  # Card border
  let borderColor = if selected:
    Color(r: 0, g: 220, b: 255, a: 255)
  else:
    Color(r: 60, g: 75, b: 95, a: 255)
  
  let borderThickness = if selected: 3.0 else: 2.0
  drawRectangleLines(Rectangle(x: x.float32, y: y.float32,
                                width: width.float32, height: height.float32),
                    borderThickness, borderColor)
  
  var yOffset = y + 20
  
  # Enhanced Icon/Badge area with depth
  let iconSize = 60
  let iconX = x + (width - iconSize) div 2
  
  # Icon background with layered depth
  drawRectangle(int32(iconX + 2), yOffset + 2, int32(iconSize), int32(iconSize),
               Color(r: 0, g: 0, b: 0, a: 80))
  drawRectangle(int32(iconX), yOffset, int32(iconSize), int32(iconSize),
               Color(r: 30, g: 38, b: 52, a: 255))
  
  # Inner frame
  drawRectangle(int32(iconX + 3), yOffset + 3, int32(iconSize - 6), int32(iconSize - 6),
               Color(r: 40, g: 50, b: 65, a: 255))
  
  # Border with accent
  drawRectangleLines(Rectangle(x: iconX.float32, y: yOffset.float32,
                                width: iconSize.float32, height: iconSize.float32),
                    2, accentColor)
  drawRectangleLines(Rectangle(x: (iconX + 2).float32, y: (yOffset + 2).float32,
                                width: (iconSize - 4).float32, height: (iconSize - 4).float32),
                    1, Color(r: accentColor.r, g: accentColor.g, b: accentColor.b, a: 120))
  
  # Corner decorations for legendary
  if powerUp.rarity == prLegendary and blurAmount > 0.6:
    let pulse = sin(time * 3.0) * 0.3 + 0.7
    let cornerSize = int32(6)
    # Top-left corner
    drawRectangle(int32(iconX - 2), yOffset - 2, cornerSize, 2, Color(r: 255, g: 215, b: 0, a: uint8(255 * pulse)))
    drawRectangle(int32(iconX - 2), yOffset - 2, 2, cornerSize, Color(r: 255, g: 215, b: 0, a: uint8(255 * pulse)))
    # Top-right corner
    drawRectangle(int32(iconX + iconSize - cornerSize + 2), yOffset - 2, cornerSize, 2, Color(r: 255, g: 215, b: 0, a: uint8(255 * pulse)))
    drawRectangle(int32(iconX + iconSize), yOffset - 2, 2, cornerSize, Color(r: 255, g: 215, b: 0, a: uint8(255 * pulse)))
    # Bottom-left corner
    drawRectangle(int32(iconX - 2), yOffset + int32(iconSize), cornerSize, 2, Color(r: 255, g: 215, b: 0, a: uint8(255 * pulse)))
    drawRectangle(int32(iconX - 2), yOffset + int32(iconSize - cornerSize + 2), 2, cornerSize, Color(r: 255, g: 215, b: 0, a: uint8(255 * pulse)))
    # Bottom-right corner
    drawRectangle(int32(iconX + iconSize - cornerSize + 2), yOffset + int32(iconSize), cornerSize, 2, Color(r: 255, g: 215, b: 0, a: uint8(255 * pulse)))
    drawRectangle(int32(iconX + iconSize), yOffset + int32(iconSize - cornerSize + 2), 2, cornerSize, Color(r: 255, g: 215, b: 0, a: uint8(255 * pulse)))
  
  # Draw power-up specific icon using enhanced graphics (larger for better visibility)
  drawPowerUpIcon(int32(iconX + 5), yOffset + 5, int32(iconSize - 10), powerUp.powerType, accentColor)
  yOffset += int32(iconSize + 18)
  
  # Process name
  let processName = getPowerUpName(powerUp.powerType)
  let nameWidth = measureText(processName, 20)
  drawText(processName, (x + (width - nameWidth) div 2), yOffset, 20,
          if powerUp.rarity == prLegendary: Gold else: Color(r: 100, g: 200, b: 255, a: 255))
  yOffset += 30
  
  # Enhanced Version badge with styling
  let versionText = "v" & $powerUp.level & ".0"
  let versionWidth = measureText(versionText, 14)
  let versionX = x + (width - versionWidth - 20) div 2
  let versionBgColor = case powerUp.level
    of 1: Color(r: 45, g: 55, b: 80, a: 255)
    of 2: Color(r: 45, g: 70, b: 55, a: 255)
    else: Color(r: 70, g: 50, b: 45, a: 255)
  
  # Version badge shadow
  drawRectangle(versionX + 1, yOffset + 1, versionWidth + 20, 26,
               Color(r: 0, g: 0, b: 0, a: 80))
  
  # Version badge background
  drawRectangle(versionX, yOffset, versionWidth + 20, 26, versionBgColor)
  
  # Highlight stripe
  drawRectangle(versionX, yOffset, versionWidth + 20, 2,
               Color(r: min(versionBgColor.r + 60, 255), g: min(versionBgColor.g + 60, 255), b: min(versionBgColor.b + 60, 255), a: 255))
  
  # Border with level color
  let versionBorderColor = case powerUp.level
    of 1: Color(r: 80, g: 120, b: 180, a: 255)
    of 2: Color(r: 80, g: 180, b: 120, a: 255)
    else: Color(r: 180, g: 120, b: 80, a: 255)
  
  drawRectangleLines(Rectangle(x: versionX.float32, y: yOffset.float32,
                                width: (versionWidth + 20).float32, height: 26.0),
                    2, versionBorderColor)
  
  # Version text with shadow
  drawText(versionText, versionX + 11, yOffset + 7, 14, Color(r: 0, g: 0, b: 0, a: 150))
  drawText(versionText, versionX + 10, yOffset + 6, 14, Color(r: 200, g: 210, b: 220, a: 255))
  yOffset += 34
  
  # Enhanced Rarity badge with effects
  let rarityText = if powerUp.rarity == prLegendary: "[*] LEGENDARY [*]" else: "STANDARD"
  let rarityColor = if powerUp.rarity == prLegendary:
    Color(r: 255, g: 215, b: 0, a: 255)
  else:
    Color(r: 100, g: 180, b: 220, a: 255)
  
  let rarityWidth: int32 = measureText(rarityText, 14)
  let badgeX: int32 = x + (width - rarityWidth - 28) div 2
  let badgeHeight: int32 = 28
  
  # Legendary glow effect
  if powerUp.rarity == prLegendary and blurAmount > 0.6:
    let glowPulse = sin(time * 3.0) * 0.35 + 0.65
    # Multiple glow layers
    for i in 1..4:
      let glowSize: int32 = int32(i * 3)
      drawRectangle(badgeX - glowSize, yOffset - glowSize, 
                   rarityWidth + 28 + glowSize * 2, badgeHeight + glowSize * 2,
                   Color(r: 255, g: 215, b: 0, a: uint8((60.0 - i.float * 12.0) * glowPulse * blurAmount)))
    # Sparkle particles around badge
    for i in 0..5:
      let sparkAngle = time * 4.0 + i.float32 * 1.047  # 60 degrees apart
      let sparkDist = 25.0 + sin(time * 5.0 + i.float32) * 5.0
      let sparkX = badgeX + (rarityWidth + 28) div 2 + int32(cos(sparkAngle) * sparkDist)
      let sparkY = yOffset + badgeHeight div 2 + int32(sin(sparkAngle) * sparkDist * 0.6)
      let sparkSize = 2 + (sin(time * 6.0 + i.float32 * 0.5) * 1.5).int32
      drawCircle(Vector2(x: sparkX.float32, y: sparkY.float32), sparkSize.float32,
                Color(r: 255, g: 240, b: 150, a: uint8(200 * glowPulse)))
  
  # Badge shadow
  drawRectangle(badgeX + 2, yOffset + 2, rarityWidth + 28, int32(badgeHeight),
               Color(r: 0, g: 0, b: 0, a: 100))
  
  # Badge background with gradient
  drawRectangle(badgeX, yOffset, rarityWidth + 28, int32(badgeHeight),
               Color(r: 35, g: 40, b: 50, a: 255))
  if powerUp.rarity == prLegendary:
    # Gradient overlay for legendary
    drawRectangle(badgeX, yOffset, rarityWidth + 28, int32(badgeHeight div 2),
                 Color(r: 80, g: 70, b: 20, a: 100))
  
  # Badge border with double-line for legendary
  drawRectangleLines(Rectangle(x: badgeX.float32, y: yOffset.float32,
                                width: (rarityWidth + 28).float32, height: badgeHeight.float32),
                    2, rarityColor)
  if powerUp.rarity == prLegendary:
    drawRectangleLines(Rectangle(x: (badgeX + 3).float32, y: (yOffset + 3).float32,
                                  width: (rarityWidth + 22).float32, height: (badgeHeight - 6).float32),
                      1, Color(r: 255, g: 235, b: 100, a: 180))
  
  # Badge text with shadow
  drawText(rarityText, badgeX + 15, yOffset + 8, 14,
          Color(r: 0, g: 0, b: 0, a: 180))
  drawText(rarityText, badgeX + 14, yOffset + 7, 14, rarityColor)
  yOffset += 42
  
  # Enhanced Progress section with level badges
  # Legendary power-ups only have 1 tier, others have 3
  let maxTiers = if powerUp.rarity == prLegendary: 1 else: 3
  
  drawText("UPGRADE TIER:", x + 12, yOffset, 12,  
          Color(r: 140, g: 160, b: 180, a: 255))
  yOffset += 20
  
  # Level indicator badges (visual tier system)
  let badgeSize: int32 = 18
  let badgeSpacing: int32 = 8
  let totalBadgeWidth: int32 = (badgeSize * maxTiers).int32 + (badgeSpacing * (maxTiers - 1)).int32
  let badgeStartX: int32 = x + (width - totalBadgeWidth) div 2
  
  for tier in 1..maxTiers:
    let badgeX: int32 = int32(badgeStartX + (tier - 1) * (badgeSize + badgeSpacing))
    let isActive = tier <= powerUp.level
    
    if isActive:
      # Active tier badge with glow
      let tierColor = case tier
        of 1: Color(r: 80, g: 150, b: 255, a: 255)
        of 2: Color(r: 80, g: 255, b: 150, a: 255)
        else: Color(r: 255, g: 140, b: 80, a: 255)
      
      # Glow effect for active badges
      if blurAmount > 0.7:
        drawRectangle(badgeX - 2, yOffset - 2, badgeSize + 4, badgeSize + 4,
                     Color(r: tierColor.r, g: tierColor.g, b: tierColor.b, a: 80))
      
      # Badge body
      drawRectangle(badgeX, yOffset, badgeSize, badgeSize, tierColor)
      # Highlight shine
      drawRectangle(badgeX, yOffset, badgeSize, 2,
                   Color(r: min(tierColor.r + 100, 255), g: min(tierColor.g + 100, 255), b: min(tierColor.b + 100, 255), a: 200))
      drawRectangle(badgeX, yOffset, 2, badgeSize,
                   Color(r: min(tierColor.r + 60, 255), g: min(tierColor.g + 60, 255), b: min(tierColor.b + 60, 255), a: 150))
      # Border
      drawRectangleLines(Rectangle(x: badgeX.float32, y: yOffset.float32,
                                   width: badgeSize.float32, height: badgeSize.float32),
                        2, Color(r: min(tierColor.r + 120, 255), g: min(tierColor.g + 120, 255), b: min(tierColor.b + 120, 255), a: 255))
      # Star/checkmark indicator
      let centerX = badgeX + badgeSize div 2
      let centerY = yOffset + badgeSize div 2
      drawCircle(Vector2(x: centerX.float32, y: centerY.float32), 4, White)
      drawText("v", centerX - 3, centerY - 5, 10, tierColor)
    else:
      # Inactive tier badge (grayed out)
      drawRectangle(badgeX, yOffset, badgeSize, badgeSize,
                   Color(r: 35, g: 40, b: 50, a: 255))
      drawRectangleLines(Rectangle(x: badgeX.float32, y: yOffset.float32,
                                   width: badgeSize.float32, height: badgeSize.float32),
                        1, Color(r: 60, g: 70, b: 85, a: 255))
      # Empty circle
      let centerX = badgeX + badgeSize div 2
      let centerY = yOffset + badgeSize div 2
      drawCircleLines(Vector2(x: centerX.float32, y: centerY.float32), 4, 
                     Color(r: 80, g: 90, b: 100, a: 255))
  
  yOffset += badgeSize + 15
  
  # Enhanced progress bar with segments
  let barWidth = width - 24
  
  # Bar shadow
  drawRectangle(x + 14, yOffset + 2, barWidth, PROGRESS_BAR_HEIGHT,
               Color(r: 0, g: 0, b: 0, a: 80))
  
  # Bar background with segments
  drawRectangle(x + 12, yOffset, barWidth, PROGRESS_BAR_HEIGHT,
               Color(r: 28, g: 32, b: 42, a: 255))
  
  # Draw segment dividers (only if there are multiple tiers)
  if maxTiers > 1:
    for i in 1..(maxTiers - 1):
      let segmentX: int32 = int32(x + 12 + (barWidth * i) div maxTiers)
      drawLine(segmentX, yOffset, segmentX, yOffset + PROGRESS_BAR_HEIGHT,
              Color(r: 50, g: 60, b: 75, a: 255))
  
  # Fill bar with gradient per level
  for level in 1..powerUp.level:
    let segmentStart: int32 = int32(x + 12 + (barWidth * (level - 1)) div maxTiers)
    let segmentEnd: int32 = int32(x + 12 + (barWidth * level) div maxTiers)
    let segmentWidth: int32 = segmentEnd - segmentStart
    
    let levelColor = case level
      of 1: Color(r: 80, g: 150, b: 255, a: 255)
      of 2: Color(r: 80, g: 255, b: 150, a: 255)
      else: Color(r: 255, g: 140, b: 80, a: 255)
    
    # Segment fill
    drawRectangle(segmentStart, yOffset, segmentWidth, PROGRESS_BAR_HEIGHT, levelColor)
    # Top highlight
    drawRectangle(segmentStart, yOffset, segmentWidth, 3,
                 Color(r: min(levelColor.r + 100, 255), g: min(levelColor.g + 100, 255), b: min(levelColor.b + 100, 255), a: 180))
    # Animated pulse for current level
    if level == powerUp.level and blurAmount > 0.7:
      let pulse = sin(time * 4.0) * 0.3 + 0.7
      drawRectangle(segmentStart, yOffset, segmentWidth, PROGRESS_BAR_HEIGHT,
                   Color(r: 255, g: 255, b: 255, a: uint8(40 * pulse)))
  
  # Bar border
  drawRectangleLines(Rectangle(x: (x + 12).float32, y: yOffset.float32,
                                width: barWidth.float32, height: PROGRESS_BAR_HEIGHT.float32),
                    2, Color(r: 80, g: 95, b: 115, a: 255))
  
  # Level text with better styling
  let levelText = "TIER " & $powerUp.level & " / " & $maxTiers
  let levelWidth = measureText(levelText, 12)
  # Text background
  let textBgX = x + 12 + (barWidth - levelWidth - 8) div 2
  drawRectangle(textBgX, yOffset + 3, levelWidth + 8, 16,
               Color(r: 20, g: 25, b: 35, a: 220))
  drawText(levelText, textBgX + 4, yOffset + 5, 12, White)
  yOffset += PROGRESS_BAR_HEIGHT + 28
  
  # Separator
  drawRectangle(x + 15, yOffset, width - 30, 1,
               Color(r: 60, g: 70, b: 85, a: 255))
  yOffset += 10
  
  # Description
  let desc = getPowerUpDescription(powerUp.powerType, powerUp.level)
  
  var descLines: seq[string] = @[]
  var currentLine = ""
  let maxLineWidth = width - 24
  
  for word in desc.split(' '):
    let testLine = if currentLine.len > 0: currentLine & " " & word else: word
    if measureText(testLine, 13) > maxLineWidth:
      if currentLine.len > 0:
        descLines.add(currentLine)
      currentLine = word
    else:
      currentLine = testLine
  
  if currentLine.len > 0:
    descLines.add(currentLine)
  
  for i, line in descLines:
    let lineY = yOffset + int32(i * 18)
    drawText(line, x + 12, lineY, int32(13), Color(r: 190, g: 200, b: 210, a: 255))
  
  # Bottom info
  let bottomY = y + height - 30
  drawText("[P]", x + 10, bottomY, 14, Color(r: 100, g: 110, b: 120, a: 255))
  drawText(".exe", x + 30, bottomY + 2, 12, Color(r: 120, g: 130, b: 140, a: 255))
  
  let sizeText = $(128 + powerUp.level * 64) & " KB"
  let sizeWidth = measureText(sizeText, 11)
  drawText(sizeText, x + width - sizeWidth - 10, bottomY + 2, 11,
          Color(r: 110, g: 120, b: 130, a: 255))

proc drawOSPowerUpInstaller*(game: Game) =
  ## Draw the power-up selection screen with slot machine roll animation
  let screenWidth = game.screenWidth
  let screenHeight = game.screenHeight
  
  # Dark overlay
  drawRectangle(0, 0, screenWidth, screenHeight, Color(r: 0, g: 0, b: 0, a: 240))
  
  # Vignette effect
  let centerX = screenWidth div 2
  let centerY = screenHeight div 2
  for i in 0..20:
    let radius = i * 60
    let alpha = uint8(i * 2)
    drawRing(Vector2(x: centerX.float32, y: centerY.float32), 
            radius.float32, (radius + 60).float32, 0, 360, 32,
            Color(r: 0, g: 0, b: 0, a: alpha))
  
  # Window position
  let windowX = (screenWidth - INSTALLER_WIDTH) div 2
  let windowY = (screenHeight - INSTALLER_HEIGHT) div 2
  
  # Window shadow
  for i in 1..4:
    let offset = i * 2
    let alpha = uint8(50 - i * 8)
    drawRectangle((windowX + offset).int32, (windowY + offset).int32,
                 INSTALLER_WIDTH, INSTALLER_HEIGHT,
                 Color(r: 0, g: 0, b: 0, a: alpha))
  
  # Window background
  drawRectangle(windowX, windowY, INSTALLER_WIDTH, INSTALLER_HEIGHT,
               Color(r: 26, g: 32, b: 44, a: 255))
  
  # Grid texture
  for i in 0..<(INSTALLER_HEIGHT div 40):
    let lineY = windowY + int32(i * 40)
    drawRectangle(windowX, lineY, INSTALLER_WIDTH, int32(1),
                 Color(r: 30, g: 36, b: 48, a: 255))
  
  # Window borders
  drawRectangleLines(Rectangle(x: windowX.float32, y: windowY.float32,
                                width: INSTALLER_WIDTH.float32, height: INSTALLER_HEIGHT.float32),
                    4, Color(r: 0, g: 180, b: 255, a: 255))
  drawRectangleLines(Rectangle(x: (windowX + 2).float32, y: (windowY + 2).float32,
                                width: (INSTALLER_WIDTH - 4).float32, height: (INSTALLER_HEIGHT - 4).float32),
                    1, Color(r: 60, g: 75, b: 95, a: 255))
  
  # Title bar
  drawRectangle(windowX, windowY, INSTALLER_WIDTH, TITLE_BAR_HEIGHT,
               Color(r: 40, g: 52, b: 70, a: 255))
  drawRectangle(windowX, windowY, INSTALLER_WIDTH, 2,
               Color(r: 80, g: 100, b: 130, a: 255))
  drawRectangle(windowX, windowY + TITLE_BAR_HEIGHT - 1, INSTALLER_WIDTH, 1,
               Color(r: 0, g: 140, b: 200, a: 255))
  
  # Title text
  let isLegendary = game.powerUpChoices[0].rarity == prLegendary
  let titleIcon = if isLegendary: "[*] " else: "[*] "
  let titleText = if isLegendary:
    titleIcon & "LEGENDARY UPGRADE INSTALLER"
  else:
    titleIcon & "Process Upgrade Manager"
  
  let titleColor = if isLegendary: Gold else: Color(r: 100, g: 200, b: 255, a: 255)
  drawText(titleText, windowX + 17, windowY + 13, 22, Color(r: 0, g: 0, b: 0, a: 120))
  drawText(titleText, windowX + 15, windowY + 11, 22, titleColor)
  
  # Close button
  let buttonSize = 28
  let closeButtonY = windowY + int32((TITLE_BAR_HEIGHT - buttonSize) div 2)
  let closeX = windowX + INSTALLER_WIDTH - int32(buttonSize) - 10
  drawRectangle(closeX, closeButtonY, int32(buttonSize), int32(buttonSize), 
               Color(r: 220, g: 50, b: 50, a: 255))
  drawRectangleLines(Rectangle(x: closeX.float32, y: closeButtonY.float32,
                                width: buttonSize.float32, height: buttonSize.float32),
                    1, Color(r: 180, g: 30, b: 30, a: 255))
  drawText("X", closeX + 8, closeButtonY + 5, 18, White)
  
  # Instruction
  var yPos = windowY + TITLE_BAR_HEIGHT + 25
  drawText("v SELECT UPGRADE TO INSTALL:", windowX + 25, yPos, 17, 
          Color(r: 200, g: 220, b: 240, a: 255))
  yPos += 50
  
  # Draw cards with roll animation
  let totalCardWidth = CARD_WIDTH * 3 + CARD_SPACING * 2
  let startX = windowX + (INSTALLER_WIDTH - totalCardWidth) div 2
  
  for i in 0..2:
    let cardX = int32(startX + i * (CARD_WIDTH + CARD_SPACING))
    let cardY = yPos
    
    if game.rollAnimationActive:
      # ROLLING MODE - show scrolling list using game's animation data
      let position = game.rollPosition[i]
      let speed = game.rollSpeed[i]
      let cardHeight = CARD_HEIGHT.float32
      
      # Calculate which cards are visible based on scroll position
      let firstVisibleIndex = (position / cardHeight).int
      let offsetY = -(position mod cardHeight)
      
      # Motion blur based on speed
      let blur = if speed > 500.0: 0.3
                 elif speed > 200.0: 0.6
                 else: 1.0
      
      # ENABLE CLIPPING - constrain animation to card boundaries
      beginScissorMode(cardX, cardY, int32(CARD_WIDTH), int32(CARD_HEIGHT))
      
      # Draw multiple cards for smooth scrolling (3 visible at once)
      for j in -1..1:
        let cardIndex = firstVisibleIndex + j
        if cardIndex >= 0 and cardIndex < game.rollPowerUpList[i].len:
          let cardDrawY = int32(cardY.float32 + offsetY + j.float32 * cardHeight)
          
          # Draw card (clipping handles visibility)
          drawProcessCard(cardX, cardDrawY, int32(CARD_WIDTH), int32(CARD_HEIGHT),
                         game.rollPowerUpList[i][cardIndex],
                         i == game.selectedPowerUp,
                         game.time,
                         blur)
      
      # DISABLE CLIPPING
      endScissorMode()
    else:
      # STATIC MODE - show final selection
      drawProcessCard(cardX, cardY, int32(CARD_WIDTH), int32(CARD_HEIGHT),
                     game.powerUpChoices[i],
                     i == game.selectedPowerUp,
                     game.time,
                     1.0)
  
  # "ROLLING..." overlay
  if game.rollAnimationActive:
    let rollingText = "[!] ROLLING..."
    let rollingWidth = measureText(rollingText, 32)
    let rollingX = windowX + (INSTALLER_WIDTH - rollingWidth) div 2
    let rollingY = windowY + INSTALLER_HEIGHT div 2 - 16
    
    let pulse = sin(game.time * 12.0) * 0.3 + 0.7
    drawRectangle(rollingX - 20, rollingY - 10, rollingWidth + 40, 52,
                 Color(r: 0, g: 0, b: 0, a: uint8(180 * pulse)))
    
    drawText(rollingText, rollingX + 2, rollingY + 2, 32,
            Color(r: 0, g: 0, b: 0, a: 200))
    drawText(rollingText, rollingX, rollingY, 32,
            Color(r: 255, g: 220, b: 0, a: uint8(255 * pulse)))
    
    # Sparkles - constrained to window area
    beginScissorMode(windowX + 10, windowY + TITLE_BAR_HEIGHT + 10, 
                     INSTALLER_WIDTH - 20, INSTALLER_HEIGHT - TITLE_BAR_HEIGHT - 140)
    
    for i in 0..10:
      let sparkleAngle = game.time * 8.0 + i.float32 * 0.6
      let sparkleRadius = 120.0 + sin(game.time * 4.0 + i.float32) * 25.0
      let sparkleX = rollingX.float32 + rollingWidth.float32 / 2 + cos(sparkleAngle) * sparkleRadius
      let sparkleY = rollingY.float32 + 16 + sin(sparkleAngle) * sparkleRadius * 0.4
      let sparkleSize = 2 + (sin(game.time * 6.0 + i.float32) * 2).int32
      drawCircle(Vector2(x: sparkleX, y: sparkleY), sparkleSize.float32,
                Color(r: 255, g: 220, b: 100, a: uint8(150 * pulse)))
    
    endScissorMode()
  
  # Control panel
  let bottomY = windowY + INSTALLER_HEIGHT - 120
  drawRectangle(windowX, bottomY - 15, INSTALLER_WIDTH, 120,
               Color(r: 30, g: 38, b: 52, a: 255))
  drawRectangle(windowX, bottomY - 15, INSTALLER_WIDTH, 2,
               Color(r: 0, g: 140, b: 200, a: 255))
  
  # Buttons
  let buttonY = bottomY + 15
  let buttonHeight = 42
  
  # Reroll button
  let rerollX = windowX + 50
  let rerollWidth = 220
  let canAffordReroll = game.player.coins >= game.rerollCost
  
  drawModernButton(rerollX, buttonY, int32(rerollWidth), int32(buttonHeight),
                  "[R] Reroll Options", canAffordReroll, false, game.time)
  
  let rerollCostText = $game.rerollCost & " credits"
  let costWidth = measureText(rerollCostText, 12)
  drawText(rerollCostText, int32(rerollX + (rerollWidth - costWidth) div 2), 
          int32(buttonY + buttonHeight + 8), int32(12),
          if canAffordReroll: Color(r: 255, g: 215, b: 0, a: 255)
          else: Color(r: 120, g: 120, b: 130, a: 255))
  
  drawText("[R]", int32(rerollX + rerollWidth + 10), buttonY + int32(13), int32(14),
          Color(r: 200, g: 200, b: 200, a: 255))