import raylib, types, random, math, strutils, settings, tables

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
  of puPoisonOrb: "Poison Orb"
  of puFireOrb: "Fire Orb"
  of puLightningOrb: "Lightning Orb"
  of puWindOrb: "Wind Orb"
  of puFrostOrb: "Frost Orb"
  of puMagicBullets: "Magic Bullets"
  of puMagicAura: "Magic Aura"
  of puMagicOrb: "Arcane Orbs"
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
    of 1: "3 dmg/sec in 120 radius"
    of 2: "6 dmg/sec in 160 radius"
    else: "12 dmg/sec in 200 radius"
  of puHomingBullets:
    # Single level only - balanced tracking
    "Bullets track enemies (10% dmg penalty)"
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
    case level
    of 1: "+25% fire rate"
    else: "+50% fire rate"
  of puMaxHealth:
    case level
    of 1: "+5 max HP"
    else: "+10 max HP"
  of puSpeedBoost:
    case level
    of 1: "+30% movement speed"
    else: "+60% movement speed"
  of puBulletDamage:
    case level
    of 1: "+70% bullet damage"
    else: "+140% bullet damage"
  of puBulletSpeed:
    case level
    of 1: "+20% bullet speed"
    else: "+40% bullet speed"
  of puLuckyCoins:
    case level
    of 1: "+50% coin drops"
    else: "+120% coin drops"
  of puWallMaster:
    case level
    of 1: "Walls have +80% HP"
    else: "Walls have +180% HP"
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
    of 1: "Regen 1 HP per 12s"
    of 2: "Regen 1 HP per 9s"
    else: "Regen 1 HP per 6s"
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
    of 1: "Heal 2% of bullet damage"
    of 2: "Heal 4% of bullet damage"
    else: "Heal 7% of bullet damage"
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
    of 1: "Hit chains to 1 enemy (70% dmg, 0.05s stun)"
    of 2: "Hit chains to 2 enemies (80% dmg, 0.05s stun)"
    else: "Hit chains to 3 enemies (90% dmg, 0.05s stun)"
  of puFrostShots:
    case level
    of 1: "Bullets slow enemies 25% (permanent)"
    of 2: "Bullets slow enemies 40% (permanent)"
    else: "Bullets slow enemies 60% (permanent)"
  of puPoisonShot:
    case level
    of 1: "Bullets poison (0.5 dmg/s, 4s, 5% slow)"
    of 2: "Bullets poison (1 dmg/s, 5s, 5% slow)"
    else: "Bullets poison (2 dmg/s, 6s, 5% slow)"
  of puFireBullets:
    case level
    of 1: "Bullets burn (0.3 dmg/s, 2s, 5% slow)"
    of 2: "Bullets burn (0.75 dmg/s, 3s, 5% slow)"
    else: "Bullets burn (1.5 dmg/s, 4s, 5% slow)"
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
    case level
    of 1: "Slow time 50% for 3.5s (1 use/wave, 20s cd)"
    of 2: "Slow time 50% for 3.5s (2 uses/wave, 20s cd)"
    else: "Slow time 50% for 3.5s (3 uses/wave, 20s cd)"
  of puGravityWell:
    # Single level only - balanced passive pull
    "Pull enemies in 300 radius"
  of puPhaseShift:
    # Single level only - balanced teleport (NERFED)
    "Dash forward (10s cd, 0.6s invuln, scales with speed)"
  of puOvercharge:
    case level
    of 1: "+4% dmg per 100 units (max 40%, 40 range)"
    of 2: "+4% dmg per 100 units (max 80%, 70 range)"
    else: "+4% dmg per 100 units (max 120%, 100 range)"
  of puEchoShots:
    # Single level only - balanced echo trail
    "Bullets leave ghost trail (40% dmg)"
  of puRotatingOrbs:
    # Single level only - legendary power-up with all elements
    "All 5 elemental orbs (2 dmg/hit)"
  of puPoisonOrb:
    case level
    of 1: "1 poison orb (0.3 dmg/s, DoT, scales)"
    of 2: "2 poison orbs (0.3 dmg/s, DoT, scales)"
    else: "3 poison orbs (0.3 dmg/s, DoT, scales)"
  of puFireOrb:
    case level
    of 1: "1 fire orb (0.4 dmg/s, DoT, scales)"
    of 2: "2 fire orbs (0.4 dmg/s, DoT, scales)"
    else: "3 fire orbs (0.4 dmg/s, DoT, scales)"
  of puLightningOrb:
    case level
    of 1: "1 lightning orb (1.5 dmg/hit)"
    of 2: "2 lightning orbs (2 dmg/hit)"
    else: "3 lightning orbs (2.5 dmg/hit)"
  of puWindOrb:
    case level
    of 1: "1 wind orb (1 dmg/hit, push)"
    of 2: "2 wind orbs (1.5 dmg/hit, push)"
    else: "3 wind orbs (2 dmg/hit, push)"
  of puFrostOrb:
    case level
    of 1: "1 frost orb (1 dmg/hit, slow)"
    of 2: "2 frost orbs (1.5 dmg/hit, slow)"
    else: "3 frost orbs (2 dmg/hit, slow)"
  of puMagicOrb:
    case level
    of 1: "1 magic orb (1.5 dmg/hit, arcane)"
    of 2: "2 magic orbs (2 dmg/hit, arcane)"
    else: "3 magic orbs (2.5 dmg/hit, arcane)"
  of puMagicBullets:
    case level
    of 1: "Bullets enhanced with arcane power (+50% damage, purple glow)"
    of 2: "Bullets enhanced with arcane power (+100% damage, purple glow)"
    else: "Bullets enhanced with arcane power (+150% damage, purple glow)"
  of puMagicAura:
    case level
    of 1: "Arcane aura 2 dmg/s in 120 radius (magical effect)"
    of 2: "Arcane aura 4 dmg/s in 160 radius (magical effect)"
    else: "Arcane aura 8 dmg/s in 200 radius (magical effect)"

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
  var availablePowerUps: seq[PowerUp] = @[]
  
  # Define LEGENDARY-EXCLUSIVE powerups (ONLY appear after boss defeats)
  # All legendary active abilities are SINGLE LEVEL ONLY
  let legendaryOnlyTypes = [puRapidFire, puMaxHealth, puSpeedBoost, puBulletDamage, 
                            puBulletSpeed, puLuckyCoins, puWallMaster, puTimeWarp,
                            puGravityWell, puPhaseShift, puOvercharge, puEchoShots, puMultiShot,
                            puRotatingOrbs]
  
  # Define NORMAL-ONLY powerups (ONLY appear after wave clears)
  let normalOnlyTypes = [puDoubleShot, puRotatingShield, puDamageZone, puHomingBullets,
                         puPiercingShots, puExplosiveBullets, puLifeSteal,
                         puAutoShoot, puBulletSize, puRegeneration, puDodgeChance,
                         puCriticalHit, puVampirism, puBulletRicochet, puSlowField,
                         puRage, puBerserker, puThorns, puBulletSplit, puChainLightning,
                         puFrostShots, puPoisonShot, puFireBullets, puWindBullets,
                         puFireAura, puLightningAura, puPoisonAura, puWindAura,
                         puPoisonOrb, puFireOrb, puLightningOrb, puWindOrb, puFrostOrb, puMagicOrb,
                         puMagicBullets, puMagicAura]
  
  if isLegendary:
    # BOSS DEFEATED - offer ONLY legendary-exclusive power-ups
    for powerType in legendaryOnlyTypes:
      let currentLevel = getPowerUpLevel(player, powerType)
      # Special handling for single-level legendary actives
      if powerType in [puPhaseShift, puGravityWell, puEchoShots, puMultiShot]:
        # These are SINGLE LEVEL ONLY
        if currentLevel == 0:
          availablePowerUps.add(PowerUp(powerType: powerType, level: 1, rarity: prLegendary))
      elif powerType in [puTimeWarp, puOvercharge]:
        # Time Warp and Overcharge have 3 levels
        if currentLevel == 0:
          availablePowerUps.add(PowerUp(powerType: powerType, level: 1, rarity: prLegendary))
        elif currentLevel < 3:
          availablePowerUps.add(PowerUp(powerType: powerType, level: currentLevel + 1, rarity: prLegendary))
      else:
        # Multi-level legendary passives (up to level 3)
        if currentLevel == 0:
          availablePowerUps.add(PowerUp(powerType: powerType, level: 1, rarity: prLegendary))
        elif currentLevel < 3:
          availablePowerUps.add(PowerUp(powerType: powerType, level: currentLevel + 1, rarity: prLegendary))
  else:
    # NORMAL WAVE - offer ONLY normal power-ups (exclude legendary-exclusive types)
    for powerType in normalOnlyTypes:
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
      # If we run out, create random power-ups from the CORRECT pool
      if isLegendary:
        let randomType = legendaryOnlyTypes[rand(legendaryOnlyTypes.high)]
        result[i] = PowerUp(powerType: randomType, level: 1, rarity: prLegendary)
      else:
        let randomType = normalOnlyTypes[rand(normalOnlyTypes.high)]
        result[i] = PowerUp(powerType: randomType, level: 1, rarity: prCommon)

# ============================================================================
# ROTATING ORBS POWER-UP SYSTEM
# ============================================================================

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
  
  let orbRadius = player.radius * 2.5 + 20  # Orbit radius around player
  
  # Clear existing orbs
  player.rotatingOrbs = @[]
  
  # Define the 6 element types and their base angles
  let elements = [etPoison, etFire, etLightning, etWind, etFrost, etMagic]
  
  # Each element gets a base angle (hexagon pattern: 60° apart)
  let baseAngles = [
    0.0,                # Poison: 0°
    PI / 3.0,           # Fire: 60°
    PI * 2.0 / 3.0,     # Lightning: 120°
    PI,                 # Wind: 180°
    PI * 4.0 / 3.0,     # Frost: 240°
    PI * 5.0 / 3.0      # Magic: 300°
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
  ## Level 1: 1 orb (top of triangle), Level 2: 2 orbs (top + bottom), Level 3: 3 orbs (full triangle)
  ## Each element has a predefined base angle so triangles don't overlap
  let orbRadius = player.radius * 2.5 + 20  # Orbit radius around player
  
  # Find existing orbs of this element and remove them
  var i = 0
  while i < player.rotatingOrbs.len:
    if player.rotatingOrbs[i].elementType == elementType:
      player.rotatingOrbs.delete(i)
    else:
      i += 1
  
  # Define fixed base angles for each element (in a hexagon pattern)
  # These angles position each element's triangle without overlapping
  let baseAngleForElement = case elementType
    of etPoison: 0.0                           # Poison triangle at 0°
    of etFire: PI / 3.0                        # Fire triangle at 60°
    of etLightning: PI * 2.0 / 3.0             # Lightning triangle at 120°
    of etWind: PI                              # Wind triangle at 180°
    of etFrost: PI * 4.0 / 3.0                 # Frost triangle at 240°
    of etMagic: PI * 5.0 / 3.0                 # Magic triangle at 300°
    of etNone: 0.0
  
  # Create orbs forming a triangle around the element's base angle
  # Triangle vertices are 120° apart
  case level
  of 1:
    # Level 1: Single orb at the top of the triangle (base angle)
    player.rotatingOrbs.add(newRotatingOrb(baseAngleForElement, orbRadius, elementType))
  of 2:
    # Level 2: Top + bottom-left of triangle
    player.rotatingOrbs.add(newRotatingOrb(baseAngleForElement, orbRadius, elementType))
    player.rotatingOrbs.add(newRotatingOrb(baseAngleForElement + PI * 2.0 / 3.0, orbRadius, elementType))
  else:  # 3 or more
    # Level 3: Full triangle (3 orbs at 120° intervals)
    for orbIdx in 0..2:
      let orbAngle = baseAngleForElement + (orbIdx.float32 * PI * 2.0 / 3.0)
      player.rotatingOrbs.add(newRotatingOrb(orbAngle, orbRadius, elementType))

proc getElementColor*(elementType: ElementType): Color =
  ## Get the visual color for each element type
  case elementType
  of etPoison: Color(r: 100, g: 255, b: 100, a: 255)
  of etFire: Color(r: 255, g: 100, b: 0, a: 255)
  of etLightning: Color(r: 255, g: 255, b: 100, a: 255)
  of etWind: Color(r: 200, g: 230, b: 255, a: 255)
  of etFrost: Color(r: 150, g: 200, b: 255, a: 255)
  of etMagic: Color(r: 200, g: 100, b: 255, a: 255)  # Purple for magic
  of etNone: White

proc getElementDamage*(level: int): float32 =
  ## Get base damage per hit based on power-up level (NERFED)
  case level
  of 1: 0.5
  of 2: 0.75
  else: 1.0

proc applyPowerUp*(player: Player, powerUp: PowerUp) =
  # Apply immediate stat bonuses for new powerup types
  case powerUp.powerType
  of puRapidFire:
    let bonus = case powerUp.level
      of 1: 0.8   # 20% faster (was 0.75 = 25% faster)
      of 2: 0.67  # 33% faster (was 0.5 = 50% faster)
      else: 0.67
    player.fireRate *= bonus
  of puMaxHealth:
    let hpBonus = case powerUp.level
      of 1: 5.0
      of 2: 10.0
      else: 10.0
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
      of 1: 1.2   # +20% (was 1.3 = +30%)
      of 2: 1.4   # +40% (was 1.6 = +60%)
      else: 1.4
    player.bulletSpeed *= speedMultiplier
  of puTimeWarp:
    # Time Warp uses are based on level: 1, 2, or 3 uses per wave
    player.timeWarpMaxUsesPerWave = powerUp.level
  of puRotatingOrbs:
    # Legendary: Create all 6 elemental orbs at their predefined positions
    createRotatingOrbs(player, powerUp.level)
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
  of puMagicOrb:
    createElementalOrbs(player, etMagic, powerUp.level)
  of puMagicBullets:
    # Magic bullets just increase damage
    let damageBonus = case powerUp.level
      of 1: 1.5   # +50% damage
      of 2: 2.0   # +100% damage
      else: 2.5   # +150% damage
    player.damage *= damageBonus
  of puMagicAura:
    # Magic aura is tracked via powerUps (pure damage effect applied in game.nim)
    discard
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
          of 2: 0.8375  # Going from 0.8 to 0.67 (0.67/0.8)
          of 3: 1.0     # Level 3 not used for legendary
          else: 1.0
        player.fireRate *= bonus
      of puMaxHealth:
        let hpBonus = case powerUp.level
          of 2: 5.0  # Additional 5 HP
          of 3: 5.0  # Additional 5 HP
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
          of 2: 1.167  # 1.4 / 1.2 (going from +20% to +40%)
          of 3: 1.0    # Level 3 not used for legendary
          else: 1.0
        player.bulletSpeed *= speedMultiplier
      of puRotatingOrbs:
        # Legendary: Always has all 6 elements at predefined positions (no upgrade)
        createRotatingOrbs(player, powerUp.level)
      of puPoisonOrb, puFireOrb, puLightningOrb, puWindOrb, puFrostOrb:
        # Recreate orbs with new level (more orbs of this element)
        let elementType = case powerUp.powerType
          of puPoisonOrb: etPoison
          of puFireOrb: etFire
          of puLightningOrb: etLightning
          of puWindOrb: etWind
          of puFrostOrb: etFrost
          else: etNone
        createElementalOrbs(player, elementType, powerUp.level)
      of puMagicOrb:
        # Recreate magic orbs with new level
        createElementalOrbs(player, etMagic, powerUp.level)
      of puMagicBullets:
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
    # Always 3 bullets for legendary Multi-Shot
    let bulletCount = 3
    let spread = 0.3
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
  of puPoisonShot:
    drawCircle(Vector2(x: centerX.float32, y: iconY.float32), 10, Green)
    for i in 0..3:
      let offsetY = -15 + i * 5
      drawCircle(Vector2(x: centerX.float32, y: (iconY + offsetY).float32), 4, Color(r: 100, g: 255, b: 100, a: 180))
  of puFireBullets:
    # Fire bullet with flame trail
    drawCircle(Vector2(x: centerX.float32, y: iconY.float32), 8, Red)
    drawCircle(Vector2(x: (centerX - 2).float32, y: (iconY - 2).float32), 4, Orange)
    drawCircle(Vector2(x: (centerX + 2).float32, y: (iconY - 2).float32), 4, Orange)
    # Flame trail
    for i in 1..4:
      let offsetX = -i * 6
      let size = 6 - i
      drawCircle(Vector2(x: (centerX + offsetX).float32, y: iconY.float32), size.float32, 
                Color(r: 255, g: (100 + i * 30).uint8, b: 0, a: uint8(200 - i * 40)))
  of puWindBullets:
    # Wind bullet with air currents
    drawCircle(Vector2(x: centerX.float32, y: iconY.float32), 8, Color(r: 200, g: 230, b: 255, a: 255))
    # Wind lines pushing backwards
    for i in 0..3:
      let offsetX = -10 - i * 8
      let offsetY = (i mod 2) * 6 - 3
      let lineLength = 8 - i.float * 1.5
      drawLine(Vector2(x: (centerX + offsetX).float32, y: (iconY + offsetY).float32),
              Vector2(x: (centerX.float + offsetX.float - lineLength).float32, y: (iconY + offsetY).float32),
              2, Color(r: 180, g: 220, b: 255, a: uint8(220 - i * 40)))
  of puFireAura:
    # Fire aura with flames
    let auraRadius = 10 + powerUp.level * 5
    drawCircle(Vector2(x: centerX.float32, y: iconY.float32), auraRadius.float32, 
              Color(r: 255, g: 100, b: 0, a: 100))
    drawCircleLines(centerX.int32, iconY.int32, auraRadius.float32, Orange)
    # Flame particles
    for i in 0..7:
      let angle = i.float32 * PI / 4.0
      let dist = 12.0 + (i mod 2).float32 * 4.0
      let x = centerX.float32 + cos(angle) * dist
      let y = iconY.float32 + sin(angle) * dist - 5.0
      drawCircle(Vector2(x: x, y: y), 3, Red)
      drawCircle(Vector2(x: x, y: y - 2), 2, Yellow)
  of puLightningAura:
    # Lightning aura with electric arcs
    let auraRadius = 10 + powerUp.level * 5
    drawCircle(Vector2(x: centerX.float32, y: iconY.float32), auraRadius.float32,
              Color(r: 100, g: 150, b: 255, a: 100))
    drawCircleLines(centerX.int32, iconY.int32, auraRadius.float32, Color(r: 150, g: 200, b: 255, a: 255))
    # Lightning bolts
    for i in 0..5:
      let angle = i.float32 * PI / 3.0
      let dist = 15.0
      let x1 = centerX.float32 + cos(angle) * 5.0
      let y1 = iconY.float32 + sin(angle) * 5.0
      let x2 = centerX.float32 + cos(angle) * dist
      let y2 = iconY.float32 + sin(angle) * dist
      # Zigzag lightning effect
      for j in 0..2:
        let t1 = j.float32 / 3.0
        let t2 = (j + 1).float32 / 3.0
        let mx1 = x1 + (x2 - x1) * t1 + (if j mod 2 == 0: 2.0 else: -2.0)
        let my1 = y1 + (y2 - y1) * t1 + (if j mod 2 == 0: -2.0 else: 2.0)
        let mx2 = x1 + (x2 - x1) * t2 + (if (j+1) mod 2 == 0: 2.0 else: -2.0)
        let my2 = y1 + (y2 - y1) * t2 + (if (j+1) mod 2 == 0: -2.0 else: 2.0)
        drawLine(Vector2(x: mx1, y: my1), Vector2(x: mx2, y: my2), 2, Color(r: 200, g: 220, b: 255, a: 255))
  of puPoisonAura:
    # Poison aura with toxic cloud
    let auraRadius = 10 + powerUp.level * 5
    drawCircle(Vector2(x: centerX.float32, y: iconY.float32), auraRadius.float32,
              Color(r: 100, g: 200, b: 100, a: 100))
    drawCircleLines(centerX.int32, iconY.int32, auraRadius.float32, Color(r: 100, g: 255, b: 100, a: 255))
    # Toxic bubbles floating up
    for i in 0..6:
      let angle = i.float32 * PI * 2.0 / 7.0
      let dist = 8.0 + (i mod 3).float32 * 4.0
      let x = centerX.float32 + cos(angle) * dist
      let y = iconY.float32 + sin(angle) * dist - (i mod 2).float32 * 5.0
      let bubbleSize = 3 - (i mod 3)
      drawCircle(Vector2(x: x, y: y), bubbleSize.float32, Color(r: 120, g: 255, b: 120, a: 200))
      drawCircleLines(x.int32, y.int32, bubbleSize.float32, Color(r: 80, g: 200, b: 80, a: 255))
  of puWindAura:
    # Wind aura with outward air currents
    let auraRadius = 10 + powerUp.level * 5
    drawCircle(Vector2(x: centerX.float32, y: iconY.float32), auraRadius.float32,
              Color(r: 220, g: 240, b: 255, a: 80))
    drawCircleLines(centerX.int32, iconY.int32, auraRadius.float32, Color(r: 200, g: 230, b: 255, a: 255))
    # Outward wind lines from center
    for i in 0..7:
      let angle = i.float32 * PI / 4.0
      let startDist = 3.0
      let endDist = 12.0 + (i mod 2).float32 * 3.0
      let x1 = centerX.float32 + cos(angle) * startDist
      let y1 = iconY.float32 + sin(angle) * startDist
      let x2 = centerX.float32 + cos(angle) * endDist
      let y2 = iconY.float32 + sin(angle) * endDist
      drawLine(Vector2(x: x1, y: y1), Vector2(x: x2, y: y2), 2, 
              Color(r: 200, g: 230, b: 255, a: uint8(200 - (i mod 3) * 40)))
  of puTimeWarp:
    # Clock with time distortion effect
    drawCircle(Vector2(x: centerX.float32, y: iconY.float32), 15, Color(r: 138, g: 43, b: 226, a: 150))
    drawCircleLines(centerX.int32, iconY.int32, 15, Color(r: 186, g: 85, b: 211, a: 255))
    # Clock hands
    drawLine(Vector2(x: centerX.float32, y: iconY.float32), 
            Vector2(x: centerX.float32, y: (iconY - 10).float32), 3, White)
    drawLine(Vector2(x: centerX.float32, y: iconY.float32), 
            Vector2(x: (centerX + 8).float32, y: iconY.float32), 2, White)
    # Time distortion waves
    for i in 1..3:
      let waveRadius = 15 + i * 8
      drawCircleLines(centerX.int32, iconY.int32, waveRadius.float32, 
                     Color(r: 138, g: 43, b: 226, a: uint8(100 - i * 25)))
  of puGravityWell:
    # Swirling vortex effect
    drawCircle(Vector2(x: centerX.float32, y: iconY.float32), 5, Color(r: 75, g: 0, b: 130, a: 255))
    for ring in 1..4:
      let ringRadius = 5 + ring * 6
      for i in 0..7:
        let angle = (i.float32 + ring.float32 * 0.5) * PI / 4.0
        let x = centerX.float32 + cos(angle) * ringRadius.float32
        let y = iconY.float32 + sin(angle) * ringRadius.float32
        let size = 3 - ring div 2
        drawCircle(Vector2(x: x, y: y), size.float32, 
                  Color(r: 138, g: 43, b: 226, a: uint8(200 - ring * 40)))
    # Inward arrows
    for i in 0..3:
      let angle = i.float32 * PI / 2.0
      let startX = centerX.float32 + cos(angle) * 25
      let startY = iconY.float32 + sin(angle) * 25
      let endX = centerX.float32 + cos(angle) * 12
      let endY = iconY.float32 + sin(angle) * 12
      drawLine(Vector2(x: startX, y: startY), Vector2(x: endX, y: endY), 2, Purple)
  of puPhaseShift:
    # Ghost trail effect with player silhouette
    for i in 0..3:
      let alpha = uint8(180 - i * 40)
      let offsetX = i * 6
      drawCircle(Vector2(x: (centerX - offsetX).float32, y: iconY.float32), 
                10, Color(r: 64, g: 224, b: 208, a: alpha))
    # Main player position with glow
    drawCircle(Vector2(x: centerX.float32, y: iconY.float32), 10, SkyBlue)
    drawCircle(Vector2(x: centerX.float32, y: iconY.float32), 12, 
              Color(r: 0, g: 255, b: 255, a: 100))
    # Phase shift lines
    for i in 0..2:
      let lineY = iconY - 8 + i * 8
      drawLine(Vector2(x: (centerX - 25).float32, y: lineY.float32),
              Vector2(x: (centerX - 15).float32, y: lineY.float32), 2, 
              Color(r: 64, g: 224, b: 208, a: 150))
  of puOvercharge:
    # Energy buildup with increasing size
    for i in 0..4:
      let size = 4 + i * 2
      let offsetX = -20 + i * 10
      let brightness = uint8(100 + i * 30)
      drawCircle(Vector2(x: (centerX + offsetX).float32, y: iconY.float32), 
                size.float32, Color(r: brightness, g: brightness, b: 0, a: 200))
      # Energy trail
      if i > 0:
        let prevX = centerX + offsetX - 10
        drawLine(Vector2(x: prevX.float32, y: iconY.float32),
                Vector2(x: (centerX + offsetX).float32, y: iconY.float32), 
                2, Color(r: 255, g: 200, b: 0, a: 150))
    # Power arrow
    drawLine(Vector2(x: (centerX - 28).float32, y: iconY.float32),
            Vector2(x: (centerX + 28).float32, y: iconY.float32), 3, Orange)
  of puEchoShots:
    # Main bullet
    drawCircle(Vector2(x: (centerX - 20).float32, y: iconY.float32), 8, Yellow)
    # Echo trail bullets
    for i in 1..7:
      let alpha = uint8(200 - i * 25)
      let offsetX = -20 + i * 6
      let size = 8 - i div 2
      drawCircle(Vector2(x: (centerX + offsetX).float32, y: iconY.float32), 
                size.float32, Color(r: 255, g: 255, b: 0, a: alpha))
    # Motion lines
    for i in 0..3:
      let lineY = iconY - 12 + i * 8
      drawLine(Vector2(x: (centerX - 30).float32, y: lineY.float32),
              Vector2(x: (centerX - 15).float32, y: lineY.float32), 2, 
              Color(r: 255, g: 215, b: 0, a: 100))
  of puRotatingOrbs:
    # Draw all 6 elemental orbs around center (legendary)
    let orbDistance = 15.0
    let elements = [etPoison, etFire, etLightning, etWind, etFrost, etMagic]
    
    for i in 0..<6:
      let angle = (i.float32 / 6.0) * PI * 2.0
      let x = centerX.float32 + cos(angle) * orbDistance
      let y = iconY.float32 + sin(angle) * orbDistance
      let color = getElementColor(elements[i])
      
      # Draw orb
      drawCircle(Vector2(x: x, y: y), 6, color)
      drawCircleLines(x.int32, y.int32, 6, 
                     Color(r: color.r div 2, g: color.g div 2, b: color.b div 2, a: 255))
    
    # Draw center (player)
    drawCircle(Vector2(x: centerX.float32, y: iconY.float32), 6, Blue)
    
    # Draw orbit path
    drawCircleLines(centerX.int32, iconY.int32, orbDistance, 
                   Color(r: 100, g: 100, b: 150, a: 100))
  of puPoisonOrb, puFireOrb, puLightningOrb, puWindOrb, puFrostOrb, puMagicOrb:
    # Draw specific element orbs based on level
    let elementType = case powerUp.powerType
      of puPoisonOrb: etPoison
      of puFireOrb: etFire
      of puLightningOrb: etLightning
      of puWindOrb: etWind
      of puFrostOrb: etFrost
      of puMagicOrb: etMagic
      else: etNone
    
    let color = getElementColor(elementType)
    let orbCount = powerUp.level
    let orbDistance = 15.0
    
    for i in 0..<orbCount:
      let angle = (i.float32 / orbCount.float32) * PI * 2.0
      let x = centerX.float32 + cos(angle) * orbDistance
      let y = iconY.float32 + sin(angle) * orbDistance
      
      # Draw orb
      drawCircle(Vector2(x: x, y: y), 6, color)
      drawCircleLines(x.int32, y.int32, 6, 
                     Color(r: color.r div 2, g: color.g div 2, b: color.b div 2, a: 255))
    
    # Draw center (player)
    drawCircle(Vector2(x: centerX.float32, y: iconY.float32), 6, Blue)
    
    # Draw orbit path
    drawCircleLines(centerX.int32, iconY.int32, orbDistance, 
                   Color(r: 100, g: 100, b: 150, a: 100))
  of puMagicBullets:
    # Magic bullets with arcane glow
    drawCircle(Vector2(x: centerX.float32, y: iconY.float32), 8, Color(r: 200, g: 100, b: 255, a: 255))
    drawCircleLines(centerX.int32, iconY.int32, 8, Color(r: 150, g: 50, b: 200, a: 255))
    # Arcane particles around the bullet
    for i in 0..5:
      let angle = i.float32 * PI / 3.0
      let dist = 16.0
      let x = centerX.float32 + cos(angle) * dist
      let y = iconY.float32 + sin(angle) * dist
      drawCircle(Vector2(x: x, y: y), 3, Color(r: 200, g: 100, b: 255, a: 200))
    # Arcane trail
    for i in 1..3:
      let offsetX = -i * 8
      drawCircle(Vector2(x: (centerX + offsetX).float32, y: iconY.float32), 
                (4 - i div 2).float32, Color(r: 180, g: 80, b: 220, a: uint8(150 - i * 40)))
  of puMagicAura:
    # Magic aura with arcane energy
    let auraRadius = 10 + powerUp.level * 5
    drawCircle(Vector2(x: centerX.float32, y: iconY.float32), auraRadius.float32,
              Color(r: 200, g: 100, b: 255, a: 100))
    drawCircleLines(centerX.int32, iconY.int32, auraRadius.float32, Color(r: 200, g: 100, b: 255, a: 255))
    # Arcane runes/symbols rotating around
    for i in 0..7:
      let angle = i.float32 * PI / 4.0  # Static animation in card view
      let dist = 12.0 + (i mod 2).float32 * 4.0
      let x = centerX.float32 + cos(angle) * dist
      let y = centerX.float32 + sin(angle) * dist - 5.0
      drawCircle(Vector2(x: x, y: y), 3, Color(r: 200, g: 100, b: 255, a: 220))
      drawCircleLines(x.int32, y.int32, 3, Color(r: 255, g: 150, b: 200, a: 200))
  
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
  
  # Determine if this is a legendary selection
  let isLegendary = game.powerUpChoices[0].rarity == prLegendary
  
  # Title
  if isLegendary:
    drawText("BOSS DEFEATED!", screenWidth div 2 - 200, 40, 50, Gold)
    drawText("Choose Your LEGENDARY Upgrade", screenWidth div 2 - 230, 100, 30, Gold)
  else:
    drawText("WAVE COMPLETE!", screenWidth div 2 - 180, 60, 50, Green)
    drawText("Choose Your Power-Up", screenWidth div 2 - 180, 120, 30, White)
  
  # Card dimensions
  let cardWidth = 200
  let cardHeight = 240
  let spacing = 40
  let totalWidth = cardWidth * 3 + spacing * 2
  let startX = (screenWidth - totalWidth) div 2
  let cardY = if isLegendary: 160 else: 180
  
  # Mouse hover detection (ONLY when selection enabled AND mouse support enabled AND mouse moved recently AND keyboard NOT used recently)
  if game.canSelectPowerUp and globalSettings.mouseSupport and game.mouseMovedRecently and not game.keyboardUsedRecently:
    let mousePos = getMousePosition()
    for i in 0..2:
      let cardX = startX + i * (cardWidth + spacing)
      if mousePos.x >= cardX.float32 and mousePos.x <= (cardX + cardWidth).float32 and
         mousePos.y >= cardY.float32 and mousePos.y <= (cardY + cardHeight).float32:
        game.selectedPowerUp = i
        break
  
  # Stop times for animation
  let stopTimes = [
    if isLegendary: 2.0 else: 1.5,  # Slot 1: back to original time
    if isLegendary: 3.0 else: 2.5,
    if isLegendary: 4.5 else: 3.5
  ]
  
  # Draw each slot
  for slotIdx in 0..2:
    let cardX = startX + slotIdx * (cardWidth + spacing)
    let slotStopped = game.rollAnimationTimer >= stopTimes[slotIdx]
    
    if game.rollAnimationActive:
      # ROLLING/STOPPED ANIMATION MODE - always use scissor + scroll rendering
      beginScissorMode(cardX.int32, cardY.int32, cardWidth.int32, cardHeight.int32)
      
      # Draw the scrolling list (works for both rolling and stopped states)
      for j in 0..<game.rollPowerUpList[slotIdx].len:
        let yPos = cardY.float32 - game.rollPosition[slotIdx] + (j.float32 * cardHeight.float32)
        
        # Only draw if visible (with some buffer for smooth scrolling)
        if yPos > (cardY - cardHeight).float32 and yPos < (cardY + cardHeight * 2).float32:
          drawPowerUpCard(cardX.int32, yPos.int32, cardWidth.int32, cardHeight.int32,
                         game.rollPowerUpList[slotIdx][j], false)
      
      endScissorMode()
      
      # Frame color changes when stopped
      let frameColor = if slotStopped:
        (if isLegendary: Gold else: Yellow)
      else:
        Color(r: 150, g: 150, b: 150, a: 255)
      
      # Draw thick frame when stopped
      if slotStopped:
        for t in 0..2:
          drawRectangleLines((cardX - t).int32, (cardY - t).int32,
                            (cardWidth + t*2).int32, (cardHeight + t*2).int32, frameColor)
      else:
        drawRectangleLines(cardX.int32, cardY.int32, cardWidth.int32, cardHeight.int32, frameColor)
      
      # Legendary glow
      if isLegendary and slotStopped:
        drawRectangleLines((cardX - 3).int32, (cardY - 3).int32,
                          (cardWidth + 6).int32, (cardHeight + 6).int32,
                          Color(r: 255, g: 215, b: 0, a: 150))
    
    else:
      # SELECTION MODE (animation completely finished)
      drawPowerUpCard(cardX.int32, cardY.int32, cardWidth.int32, cardHeight.int32,
                     game.powerUpChoices[slotIdx], 
                     slotIdx == game.selectedPowerUp and game.canSelectPowerUp)
  
  # Status messages
  if game.rollAnimationActive:
    var msg = "Rolling..."
    
    let w = measureText(msg, 24)
    drawText(msg, screenWidth div 2 - w div 2, screenHeight - 150, 24, Yellow)
  else:
    drawText("A/D or ARROW KEYS: select | MOUSE: hover/click | ENTER: choose", 
            screenWidth div 2 - 320, screenHeight - 120, 20, LightGray)
    drawText("ESC: skip", screenWidth div 2 - 60, screenHeight - 90, 18, Gray)
  
  # Coin count
  let coinText = "Coins: " & $game.player.coins
  drawText(coinText, screenWidth div 2 - 60, screenHeight - 55, 22, Gold)
  
  # Draw custom cursor (only if mouseSupport is enabled OR showCursorInMenus is enabled)
  if globalSettings.mouseSupport or globalSettings.showCursorInMenus:
    let mousePos = getMousePosition()
    let cursorPulse = sin(game.time * 8.0) * 2 + 8
    
    # Outer rotating ring
    for i in 0..<8:
      let angle = game.time * 4.0 + i.float32 * PI / 4.0
      let x = mousePos.x + cos(angle) * cursorPulse
      let y = mousePos.y + sin(angle) * cursorPulse
      drawCircle(Vector2(x: x, y: y), 2, Color(r: 255'u8, g: 200'u8, b: 50'u8, a: 200'u8))
    
    # Crosshair lines
    drawLine(Vector2(x: mousePos.x - 8, y: mousePos.y), 
            Vector2(x: mousePos.x - 3, y: mousePos.y), 2, White)
    drawLine(Vector2(x: mousePos.x + 3, y: mousePos.y), 
            Vector2(x: mousePos.x + 8, y: mousePos.y), 2, White)
    drawLine(Vector2(x: mousePos.x, y: mousePos.y - 8), 
            Vector2(x: mousePos.x, y: mousePos.y - 3), 2, White)
    drawLine(Vector2(x: mousePos.x, y: mousePos.y + 3), 
            Vector2(x: mousePos.x, y: mousePos.y + 8), 2, White)
    
    # Center dot
    drawCircle(Vector2(x: mousePos.x, y: mousePos.y), 2, Red)
# ============================================================================
# SLOT MACHINE ROLL ANIMATION SYSTEM
# ============================================================================

proc generateRandomPowerUpExcluding(player: Player, isLegendary: bool, excludeType: PowerUpType): PowerUp =
  ## Generate a random power-up for the roll animation display, excluding a specific type
  let legendaryTypes = [puRapidFire, puMaxHealth, puSpeedBoost, puBulletDamage, 
                        puBulletSpeed, puLuckyCoins, puWallMaster, puTimeWarp,
                        puGravityWell, puPhaseShift, puOvercharge, puEchoShots]
  
  let normalTypes = [puDoubleShot, puRotatingShield, puDamageZone, puHomingBullets,
                     puPiercingShots, puMultiShot, puExplosiveBullets, puLifeSteal,
                     puAutoShoot, puBulletSize, puRegeneration, puDodgeChance,
                     puCriticalHit, puVampirism, puBulletRicochet, puSlowField,
                     puRage, puBerserker, puThorns, puBulletSplit, puChainLightning,
                     puFrostShots, puPoisonShot, puFireBullets,
                     puFireAura, puLightningAura, puPoisonAura, puMagicBullets, puMagicAura,
                     puPoisonOrb, puFireOrb, puLightningOrb, puWindOrb, puFrostOrb, puMagicOrb]
  
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
  let cardHeight = 240.0  # Must match the cardHeight in drawPowerUpSelection
  
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
