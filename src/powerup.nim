import raylib, types, random, math, tables, ui/os_powerup_installer

# Forward declarations for reroll system
proc attemptRerollPowerUps*(game: Game): bool

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
    # Single level only - LEGENDARY
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
    # Single level only - LEGENDARY
    "Bullets track nearest enemy"
  of puPiercingShots:
    case level
    of 1: "Bullets pierce 1 enemy (-33% damage per pierce)"
    of 2: "Bullets pierce 2 enemies (-33% damage per pierce)"
    else: "Bullets pierce 3 enemies (-33% damage per pierce)"
  of puMultiShot:
    # Single level only - 3 directions, no nerfs
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
    # Single level only - LEGENDARY
    "+40% fire rate"
  of puMaxHealth:
    # Single level only - LEGENDARY
    "+14 max HP"
  of puSpeedBoost:
    # Single level only - LEGENDARY
    "+50% movement speed"
  of puBulletDamage:
    # Single level only - LEGENDARY
    "+100% bullet damage"
  of puBulletSpeed:
    # Single level only - LEGENDARY
    "+35% bullet speed"
  of puLuckyCoins:
    # Single level only - LEGENDARY
    "Doubles all coins collected"
  of puWallMaster:
    # Single level only - LEGENDARY
    "Walls have +250% HP"
  of puAutoShoot:
    # Single level only - LEGENDARY
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
    # Single level only - LEGENDARY
    "Slow time 50% for 4s (2 uses/wave, 18s cd)"
  of puGravityWell:
    # Single level only - LEGENDARY passive pull
    "Pull enemies in 300 radius"
  of puPhaseShift:
    # Single level only - LEGENDARY teleport
    "Dash forward (5s cd, 0.5s invuln, scales with speed)"
  of puOvercharge:
    # Single level only - LEGENDARY
    "+5% dmg per 100 units traveled (max 100%, 80 range)"
  of puEchoShots:
    # Single level only - LEGENDARY echo trail
    "Bullets leave ghost trail (50% dmg)"
  of puRotatingOrbs:
    # Single level only - LEGENDARY power-up with all elements
    "All 6 elemental orbs (2.5 dmg/hit)"
  of puPoisonOrb:
    case level
    of 1: "2 poison orbs (0.3 dmg/s"
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
    # Single level only - LEGENDARY mastery
    "Fire effects: +150% dmg, +100% duration, +35% slow"
  of puPoisonMastery:
    # Single level only - LEGENDARY mastery
    "Poison effects: +150% dmg, +100% duration, +30% slow"
  of puFrostMastery:
    # Single level only - LEGENDARY mastery
    "Frost effects: +150% dmg, +100% duration, +20% slow"
  of puArcaneMastery:
    # Single level only - LEGENDARY mastery
    "Arcane effects: +200% dmg, +100% duration, piercing"
  of puLightningMastery:
    # Single level only - LEGENDARY mastery
    "Lightning effects: +150% dmg, +100% duration, +25% slow, +1 chain, +50% range"
  of puWindMastery:
    # Single level only - LEGENDARY mastery
    "Wind effects: +150% dmg, +100% duration, +40% slow, stronger push"
  of puParry:
    # Single level only - LEGENDARY active ability
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
    # Single level only - LEGENDARY mastery
    "Blood effects: +150% dmg, +100% duration, +50% lifesteal"

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
  # Generate 3 random power-up options with COMPLETELY SEPARATE pools
  # IMPORTANT: Only ONE orb type and ONE aura type maximum per roll
  var availablePowerUps: seq[PowerUp] = @[]
  
  # Define LEGENDARY-EXCLUSIVE powerups (ONLY appear after boss defeats)
  # ALL legendary powerups are SINGLE LEVEL ONLY
  let legendaryOnlyTypes = [
    puArcaneMastery, puAutoShoot, puBloodMastery, puBulletDamage, puBulletSpeed, 
    puDoubleShot, puEchoShots, puFireMastery, puFrostMastery, puGravityWell, 
    puLightningMastery, puLuckyCoins, puMagicalBullets, puMaxHealth, puMultiShot, 
    puOvercharge, puParry, puPhaseShift, puPoisonMastery, puRapidFire, 
    puRotatingOrbs, puSpeedBoost, puTimeWarp, puWallMaster, puWindMastery
  ]
  
  # Define NORMAL-ONLY powerups (ONLY appear after wave clears)
  let normalOnlyTypes = [
    puArcaneAura, puArcaneBullets, puArcaneOrb, puBerserker, puBloodAura, 
    puBloodOrb, puBulletRicochet, puBulletSize, puBulletSplit, puChainLightning,
    puCriticalHit, puDamageZone, puDodgeChance, puExplosiveBullets,
    puFireAura, puFireBullets, puFireOrb, puFrostOrb, puFrostShots,
    puLightningAura, puLightningOrb, puLifeSteal, puPiercingShots,
    puPoisonAura, puPoisonOrb, puPoisonShot, puRage, puRegeneration,
    puRotatingShield, puSlowField, puThorns, puBloodBullets, puWindAura,
    puWindBullets, puWindOrb
  ]
  
  # Define orb, aura, and bullet groups for exclusivity
  let orbTypes = [puPoisonOrb, puFireOrb, puLightningOrb, puWindOrb, puFrostOrb, puArcaneOrb, puBloodOrb, puRotatingOrbs]
  let auraTypes = [puFireAura, puLightningAura, puPoisonAura, puWindAura, puArcaneAura, puBloodAura, puDamageZone]
  let bulletTypes = [puFireBullets, puPoisonShot, puFrostShots, puWindBullets, puArcaneBullets]
  
  if isLegendary:
    # BOSS DEFEATED - offer ONLY legendary-exclusive power-ups
    # ALL LEGENDARY POWERUPS ARE SINGLE LEVEL ONLY
    for powerType in legendaryOnlyTypes:
      let currentLevel = getPowerUpLevel(player, powerType)
      if currentLevel == 0:
        # All legendaries are single-level, only offer if not owned
        availablePowerUps.add(PowerUp(powerType: powerType, level: 1, rarity: prLegendary))
  else:
    # NORMAL WAVE - offer ONLY normal power-ups (exclude legendary-exclusive types)
    for powerType in normalOnlyTypes:
      let currentLevel = getPowerUpLevel(player, powerType)
      if currentLevel == 0:
        availablePowerUps.add(PowerUp(powerType: powerType, level: 1, rarity: prCommon))
      elif currentLevel < 3:
        availablePowerUps.add(PowerUp(powerType: powerType, level: currentLevel + 1, rarity: prCommon))
  
  # Shuffle available power-ups
  for i in countdown(availablePowerUps.high, 1):
    let j = rand(i)
    swap(availablePowerUps[i], availablePowerUps[j])
  
  # NEW: Apply grouping logic - ensure at most 1 orb, 1 aura, and 1 elemental bullet
  var selectedPowerUps: seq[PowerUp] = @[]
  var hasOrb = false
  var hasAura = false
  var hasBullet = false
  
  for powerUp in availablePowerUps:
    if selectedPowerUps.len >= 3:
      break
    
    # Check if this is an orb type
    let isOrb = powerUp.powerType in orbTypes
    # Check if this is an aura type
    let isAura = powerUp.powerType in auraTypes
    # Check if this is an elemental bullet type
    let isBullet = powerUp.powerType in bulletTypes
    
    # Skip if we already have an orb and this is an orb
    if isOrb and hasOrb:
      continue
    
    # Skip if we already have an aura and this is an aura
    if isAura and hasAura:
      continue
    
    # Skip if we already have a bullet and this is a bullet
    if isBullet and hasBullet:
      continue
    
    # Add this power-up and mark categories
    selectedPowerUps.add(powerUp)
    if isOrb:
      hasOrb = true
    if isAura:
      hasAura = true
    if isBullet:
      hasBullet = true
  
  # Fill result with selected power-ups (up to 3)
  for i in 0..2:
    if i < selectedPowerUps.len:
      result[i] = selectedPowerUps[i]
    else:
      # If we run out, create random power-ups from the CORRECT pool
      # Make sure we don't violate orb/aura/bullet restrictions
      var attempts = 0
      while attempts < 100:  # Prevent infinite loop
        let randomPowerUp = if isLegendary:
          let randomType = legendaryOnlyTypes[rand(legendaryOnlyTypes.high)]
          PowerUp(powerType: randomType, level: 1, rarity: prLegendary)
        else:
          let randomType = normalOnlyTypes[rand(normalOnlyTypes.high)]
          PowerUp(powerType: randomType, level: 1, rarity: prCommon)
        
        let isOrb = randomPowerUp.powerType in orbTypes
        let isAura = randomPowerUp.powerType in auraTypes
        let isBullet = randomPowerUp.powerType in bulletTypes
        
        # Check if this violates our grouping rules
        if (isOrb and hasOrb) or (isAura and hasAura) or (isBullet and hasBullet):
          attempts += 1
          continue
        
        result[i] = randomPowerUp
        if isOrb:
          hasOrb = true
        if isAura:
          hasAura = true
        if isBullet:
          hasBullet = true
        break

# ROTATING ORBS SYSTEM
proc newRotatingOrb*(angle: float32, radius: float32, elementType: ElementType): RotatingOrb =
  ## Create a new rotating orb with specified angle, radius, and element
  result = RotatingOrb(
    angle: angle,
    radius: radius,
    elementType: elementType,
    hitEnemies: @[],
    lastHitTime: initTable[int, float32]()
  )

proc createRotatingOrbs*(player: Player, level: int) =
  ## Create rotating orbs based on power-up level (Legendary version)
  ## All 6 elements, each element forms a triangle around the player
  ## Triangles are positioned at different base angles to avoid overlaps
  ## Orb radius scales with player size to maintain distance
  
  # Dynamic orbit radius: scales with player size + fixed offset
  # player.radius * 3.5 ensures orbs scale MUCH MORE with player
  # + 25 maintains minimum distance from player
  let orbRadius = player.radius * 3.5 + 25
  
  # Clear existing orbs
  player.rotatingOrbs = @[]
  
  # Define the 6 element types and their base angles
  let elements = [etPoison, etFire, etLightning, etWind, etFrost, etArcane]
  
  # Each element gets a base angle (hexagon pattern: 60° apart)
  let baseAngles = [
    0.0,                # Poison: 0°
    PI / 3.0,           # Fire: 60°
    PI * 2.0 / 3.0,     # Lightning: 120°
    PI,                 # Wind: 180°
    PI * 4.0 / 3.0,     # Frost: 240°
    PI * 5.0 / 3.0      # Arcane: 300°
  ]
  
  # For legendary, create all 6 triangles with 3 orbs each
  for elementIdx in 0..<6:
    let baseAngle = baseAngles[elementIdx]
    let element = elements[elementIdx]
    
    # Create triangle with 3 orbs
    # Triangle spacing: 120° apart (forming equilateral triangle)
    for orbIdx in 0..2:
      let orbAngle = baseAngle + (orbIdx.float32 * PI * 2.0 / 3.0)
      player.rotatingOrbs.add(newRotatingOrb(orbAngle, orbRadius, element))

proc createElementalOrbs*(player: Player, elementType: ElementType, level: int) =
  ## Create orbs of a specific element based on level
  ## Level 1: 2 orbs, Level 2: 4 orbs, Level 3: 6 orbs
  ## Distribuidos en círculo alrededor del jugador
  ## Orb radius scales with player size to maintain distance
  
  # Dynamic orbit radius: scales with player size + fixed offset
  # player.radius * 3.5 ensures orbs scale MUCH MORE with player
  # + 25 maintains minimum distance from player
  let orbRadius = player.radius * 3.5 + 25
  
  # Find existing orbs of this element and remove them
  var i = 0
  while i < player.rotatingOrbs.len:
    if player.rotatingOrbs[i].elementType == elementType:
      player.rotatingOrbs.delete(i)
    else:
      i += 1
  
  # Define fixed base angle for each element (offset para que no se solapen)
  let baseAngleForElement = case elementType
    of etPoison: 0.0                           # Poison at 0°
    of etFire: PI / 3.0                        # Fire at 60°
    of etLightning: PI * 2.0 / 3.0             # Lightning at 120°
    of etWind: PI                              # Wind at 180°
    of etFrost: PI * 4.0 / 3.0                 # Frost at 240°
    of etArcane: PI * 5.0 / 3.0                 # Arcane at 300°
    of etBlood: PI / 6.0                       # Blood at 30°
    of etNone: 0.0
  
  # Create orbs distributed in circle based on level
  let orbCount = case level
    of 1: 2
    of 2: 4
    else: 6
  
  # Distribute orbs evenly around the circle
  for orbIdx in 0..<orbCount:
    let orbAngle = baseAngleForElement + (orbIdx.float32 * PI * 2.0 / orbCount.float32)
    player.rotatingOrbs.add(newRotatingOrb(orbAngle, orbRadius, elementType))

proc getElementColor*(elementType: ElementType): Color =
  ## Get the visual color for each element type
  case elementType
  of etPoison: Color(r: 100, g: 255, b: 100, a: 255)
  of etFire: Color(r: 255, g: 100, b: 0, a: 255)
  of etLightning: Color(r: 255, g: 255, b: 100, a: 255)
  of etWind: Color(r: 200, g: 230, b: 255, a: 255)
  of etFrost: Color(r: 150, g: 200, b: 255, a: 255)
  of etArcane: Color(r: 200, g: 100, b: 255, a: 255)  # Purple for arcane
  of etBlood: Color(r: 255, g: 50, b: 50, a: 255)     # Red for blood
  of etNone: White

proc getElementDamage*(level: int): float32 =
  ## Get base damage per hit based on power-up level (BUFFED RANGE: 2-6)
  ## Compensated with reduced damage multiplier in game logic
  case level
  of 1: 2.0
  of 2: 4.0
  else: 6.0

proc applyPowerUp*(player: Player, powerUp: PowerUp) =
  # Apply immediate stat bonuses for new powerup types
  case powerUp.powerType
  of puRapidFire:
    # Single level only - +40% fire rate
    player.fireRate *= 0.714  # 1 / 1.4
  of puMaxHealth:
    # Single level only - +14 HP
    player.maxHp += 14.0
    player.hp += 14.0
  of puSpeedBoost:
    # Single level only - +50% speed
    player.speed *= 1.5
    player.baseSpeed *= 1.5
  of puBulletDamage:
    # Single level only - +100% damage
    player.damage *= 2.0
  of puBulletSpeed:
    # Single level only - +35% speed
    player.bulletSpeed *= 1.35
  of puTimeWarp:
    # Single level only - 2 uses per wave
    player.timeWarpMaxUsesPerWave = 2
  of puRotatingOrbs:
    # Legendary: Create all 6 elemental orbs at their predefined positions
    createRotatingOrbs(player, powerUp.level)
  of puRotatingShield:
    # Initialize shield health arrays - always 3 shields
    let shieldCount = 3
    player.shieldHealths = @[]
    player.shieldRegenTimers = @[]
    
    # Health increases with level: 3 HP, 4 HP, 5 HP
    let shieldHealth = case powerUp.level
      of 1: 3.0
      of 2: 4.0
      else: 5.0
    player.shieldMaxHealth = shieldHealth
    
    for i in 0..<shieldCount:
      player.shieldHealths.add(shieldHealth)
      player.shieldRegenTimers.add(0.0)
    
    # Reduce regen delay with upgrades: level 1=4s, level 2=3s, level 3=2s
    player.shieldRegenDelay = case powerUp.level
      of 1: 4.0
      of 2: 3.0
      else: 2.0
  of puPoisonOrb:
    createElementalOrbs(player, etPoison, powerUp.level)
  of puFireOrb:
    createElementalOrbs(player, etFire, powerUp.level)
  of puLightningOrb:
    createElementalOrbs(player, etLightning, powerUp.level)
  of puWindOrb:
    createElementalOrbs(player, etWind, powerUp.level)
  of puFrostOrb:
    createElementalOrbs(player, etFrost, powerUp.level)
  of puArcaneOrb:
    createElementalOrbs(player, etArcane, powerUp.level)
  of puArcaneBullets:
    # Arcane bullets just increase damage
    let damageBonus = case powerUp.level
      of 1: 1.5   # +50% damage
      of 2: 2.0   # +100% damage
      else: 2.5   # +150% damage
    player.damage *= damageBonus
  of puArcaneAura:
    # Arcane aura is tracked via powerUps (pure damage effect applied in game.nim)
    discard
  of puFireMastery:
    # LEGENDARY: Enhance fire effects
    player.hasFireMastery = true
  of puPoisonMastery:
    # LEGENDARY: Enhance poison effects
    player.hasPoisonMastery = true
  of puFrostMastery:
    # LEGENDARY: Enhance frost effects
    player.hasFrostMastery = true
  of puArcaneMastery:
    # LEGENDARY: Enhance arcane effects
    player.hasArcaneMastery = true
  of puLightningMastery:
    # LEGENDARY: Enhance lightning effects
    player.hasLightningMastery = true
  of puWindMastery:
    # LEGENDARY: Enhance wind effects
    player.hasWindMastery = true
  of puBloodMastery:
    # LEGENDARY: Enhance blood effects
    player.hasBloodMastery = true
  of puBloodOrb:
    createElementalOrbs(player, etBlood, powerUp.level)
  of puBloodAura:
    # Blood aura is tracked via powerUps (lifesteal effect applied in game.nim)
    discard
  else:
    discard
  
  # Check if player already has this power-up (should not happen for single-level legendaries)
  var found = false
  for i in 0..<player.powerUps.len:
    if player.powerUps[i].powerType == powerUp.powerType:
      # For multi-level power-ups only (normal ones)
      player.powerUps[i].level = powerUp.level
      player.powerUps[i].rarity = powerUp.rarity
      
      # Apply upgrade bonuses for normal power-ups that have levels
      case powerUp.powerType
      of puRotatingShield:
        # Update shield health and cooldown based on new level
        let shieldHealth = case powerUp.level
          of 1: 3.0
          of 2: 4.0
          else: 5.0
        player.shieldMaxHealth = shieldHealth
        
        # Restore all shields to new max health
        for i in 0..<player.shieldHealths.len:
          player.shieldHealths[i] = shieldHealth
        
        # Update regen delay
        player.shieldRegenDelay = case powerUp.level
          of 1: 4.0
          of 2: 3.0
          else: 2.0
      of puPoisonOrb, puFireOrb, puLightningOrb, puWindOrb, puFrostOrb, puBloodOrb:
        # Recreate orbs with new level (more orbs of this element)
        let elementType = case powerUp.powerType
          of puPoisonOrb: etPoison
          of puFireOrb: etFire
          of puLightningOrb: etLightning
          of puWindOrb: etWind
          of puFrostOrb: etFrost
          of puBloodOrb: etBlood
          else: etNone
        createElementalOrbs(player, elementType, powerUp.level)
      of puArcaneOrb:
        # Recreate arcane orbs with new level
        createElementalOrbs(player, etArcane, powerUp.level)
      of puArcaneBullets:
        let damageBonus = case powerUp.level
          of 2: 1.333  # 2.0 / 1.5
          of 3: 1.25   # 2.5 / 2.0
          else: 1.0
        player.damage *= damageBonus
      else:
        discard
      
      found = true
      break
  
  if not found:
    # Add new power-up
    player.powerUps.add(powerUp)

proc drawPowerUpSelection*(game: Game) =
  # Use the new OS-style power-up installer interface
  drawOSPowerUpInstaller(game)

# SLOT MACHINE ROLL ANIMATION SYSTEM
proc generateRandomPowerUpExcluding(player: Player, isLegendary: bool, excludeType: PowerUpType): PowerUp =
  ## Generate a random power-up for the roll animation display, excluding a specific type
  let legendaryTypes = [puRapidFire, puMaxHealth, puSpeedBoost, puBulletDamage, 
                        puBulletSpeed, puLuckyCoins, puWallMaster, puTimeWarp,
                        puGravityWell, puPhaseShift, puOvercharge, puEchoShots,
                        puMagicalBullets]
  
  let normalTypes = [puDoubleShot, puRotatingShield, puDamageZone,
                     puPiercingShots, puMultiShot, puExplosiveBullets, puLifeSteal,
                     puAutoShoot, puBulletSize, puRegeneration, puDodgeChance,
                     puCriticalHit, puBloodBullets, puBulletRicochet, puSlowField,
                     puRage, puBerserker, puThorns, puBulletSplit, puChainLightning,
                     puFrostShots, puPoisonShot, puFireBullets,
                     puFireAura, puLightningAura, puPoisonAura, puArcaneBullets, puArcaneAura,
                     puPoisonOrb, puFireOrb, puLightningOrb, puWindOrb, puFrostOrb, puArcaneOrb]
  
  var availableTypes: seq[PowerUpType]
  if isLegendary:
    for t in legendaryTypes:
      if t != excludeType:
        availableTypes.add(t)
  else:
    for t in normalTypes:
      if t != excludeType:
        availableTypes.add(t)
  
  if availableTypes.len == 0:
    # Fallback if all types excluded (shouldn't happen)
    if isLegendary:
      let t = legendaryTypes[rand(legendaryTypes.high)]
      return PowerUp(powerType: t, level: rand(1..3), rarity: prLegendary)
    else:
      let t = normalTypes[rand(normalTypes.high)]
      return PowerUp(powerType: t, level: rand(1..3), rarity: prCommon)
  
  let t = availableTypes[rand(availableTypes.high)]
  if isLegendary:
    result = PowerUp(powerType: t, level: rand(1..3), rarity: prLegendary)
  else:
    result = PowerUp(powerType: t, level: rand(1..3), rarity: prCommon)

proc updatePowerUpRollAnimation*(game: Game, deltaTime: float32) =
  ## Update the slot machine roll animation with velocity-based scrolling
  if not game.rollAnimationActive:
    return
  
  game.rollAnimationTimer += deltaTime
  
  let isLegendary = game.powerUpChoices[0].rarity == prLegendary
  let cardHeight = 380.0  # Must match CARD_HEIGHT in os_powerup_installer.nim
  
  # Stop times for each slot
  let stopTimes = [
    if isLegendary: 2.0 else: 1.5,  # Slot 1: back to original time
    if isLegendary: 3.0 else: 2.5,
    if isLegendary: 4.5 else: 3.5
  ]
  
  # Define shared constant speed for all slots (pixels per second)
  let sharedSpeed = 1000.0  # Adjust this value to control roll speed
  
  for i in 0..2:
    # CRITICAL: The final position should show the LAST card in the list
    let finalIndex = game.rollPowerUpList[i].len - 1
    let finalPosition = finalIndex.float32 * cardHeight
    
    let slotShouldBeStopped = game.rollAnimationTimer >= stopTimes[i]
    
    if not slotShouldBeStopped:
      # Calculate how much time this slot has been rolling
      let rollingTime = game.rollAnimationTimer
      
      # Define braking phase duration (time to decelerate to stop)
      let brakeDuration = 0.6  # 0.6 seconds to brake
      let timeUntilStop = stopTimes[i] - rollingTime
      
      if timeUntilStop > brakeDuration:
        # CONSTANT SPEED PHASE - all slots move at same speed
        game.rollPosition[i] += sharedSpeed * deltaTime
        game.rollSpeed[i] = sharedSpeed
        
        # Clamp to not overshoot into brake zone
        let maxPosBeforeBrake = finalPosition - (sharedSpeed * brakeDuration * 0.5)  # 0.5 accounts for deceleration average
        if game.rollPosition[i] > maxPosBeforeBrake:
          game.rollPosition[i] = maxPosBeforeBrake
      else:
        # BRAKING PHASE - ease-out to smooth stop
        let brakeProgress = 1.0 - (timeUntilStop / brakeDuration)  # 0 to 1
        let easedBrake = 1.0 - (1.0 - brakeProgress) * (1.0 - brakeProgress)  # ease-out quad
        
        # Calculate where brake started
        let posAtBrakeStart = finalPosition - (sharedSpeed * brakeDuration * 0.5)
        let brakeDistance = finalPosition - posAtBrakeStart
        
        game.rollPosition[i] = posAtBrakeStart + brakeDistance * easedBrake
        
        # Calculate speed during brake (derivative of ease-out)
        game.rollSpeed[i] = (brakeDistance / brakeDuration) * 2.0 * (1.0 - brakeProgress)
    else:
      # CRITICAL: Slot is stopped - FORCE exact final position every frame
      game.rollPosition[i] = finalPosition
      game.rollSpeed[i] = 0.0
  
  # Complete when all stopped
  if game.rollAnimationTimer >= stopTimes[2] + 0.3:
    game.rollAnimationActive = false
    game.canSelectPowerUp = true

proc initPowerUpRollAnimation*(game: Game) =
  ## Initialize roll animation - each slot gets its OWN final power-up
  game.rollAnimationActive = true
  game.rollAnimationTimer = 0
  game.canSelectPowerUp = false
  
  let isLegendary = game.powerUpChoices[0].rarity == prLegendary
  
  # DEBUG: Print what power-ups we're setting up
  echo "=== INIT ROLL ANIMATION ==="
  echo "Slot 0 final: ", getPowerUpName(game.powerUpChoices[0].powerType)
  echo "Slot 1 final: ", getPowerUpName(game.powerUpChoices[1].powerType)
  echo "Slot 2 final: ", getPowerUpName(game.powerUpChoices[2].powerType)
  
  # CRITICAL: Each slot i must use game.powerUpChoices[i], NOT game.powerUpChoices[0]
  for i in 0..2:
    game.rollPosition[i] = 0
    game.rollSpeed[i] = 0
    game.rollPowerUpList[i] = @[]
    
    # Different lengths for each slot - slot 0 is shorter (slower roll)
    let listLength = case i
      of 0: 8   # Slot 1: fewer items = slower visible roll
      of 1: 12  # Slot 2: medium
      else: 15  # Slot 3: longest
    
    # Build list: show THIS SLOT'S final power-up every 3rd position
    # IMPORTANT: Exclude the final power-up type from random generation
    for j in 0..<listLength:
      if j mod 3 == 2:
        # Every 3rd item: the ACTUAL final power-up FOR THIS SLOT (slot i)
        game.rollPowerUpList[i].add(game.powerUpChoices[i])
      else:
        # Other items: random (but NEVER the same as the final power-up)
        game.rollPowerUpList[i].add(generateRandomPowerUpExcluding(game.player, isLegendary, game.powerUpChoices[i].powerType))
    
    # CRITICAL: Last item MUST be THIS SLOT'S final power-up (slot i)
    game.rollPowerUpList[i].add(game.powerUpChoices[i])
    
    # DEBUG: Verify the last item
    let lastIdx = game.rollPowerUpList[i].len - 1
    echo "Slot ", i, " list length: ", game.rollPowerUpList[i].len
    echo "Slot ", i, " last item (idx ", lastIdx, "): ", getPowerUpName(game.rollPowerUpList[i][lastIdx].powerType)

proc attemptRerollPowerUps*(game: Game): bool =
  ## Try to reroll the power-up options
  ## Returns true if successful, false if insufficient coins
  
  # Check if player has enough coins
  if game.player.coins < game.rerollCost:
    return false
  
  # Deduct coins
  game.player.coins -= game.rerollCost
  
  # Generate new power-up choices (same legendary/normal status)
  let isLegendary = game.powerUpChoices[0].rarity == prLegendary
  game.powerUpChoices = generatePowerUpChoices(game.player, isLegendary)
  
  # Reset selection to first option
  game.selectedPowerUp = 0
  
  # Initialize reroll animation (same as new power-up selection)
  initPowerUpRollAnimation(game)
  
  # Increase cost for next reroll (adds 50 coins for difficulty)
  game.rerollCost += 50
  
  return true

proc initializeRerollCost*(game: Game) =
  ## Initialize the reroll cost at the start of a power-up selection
  ## Base cost: 50 coins for first reroll, increases by 50 each time
  game.rerollCost = 50
