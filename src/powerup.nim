import raylib, types, random, math, tables, ui/os_powerup_installer, powerup_data, d_visuals

# Forward declarations for reroll system
proc attemptRerollPowerUps*(game: Game): bool

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
  # ALL legendary powerups are SINGLE LEVEL ONLY
  let legendaryOnlyTypes: array[0..24, PowerUpType] = [
    puArcaneMastery, puAutoShoot, puBloodMastery, puBulletSpeed,
    puDoubleShot, puEchoShots, puFireMastery, puFrostMastery, puGravityWell,
    puLightningMastery, puLuckyCoins, puMagicalBullets, puMaxHealth, puMultiShot,
    puOvercharge, puParry, puPhaseShift, puPoisonMastery, puRapidFire,
    puRotatingOrbs, puSpeedBoost, puTimeWarp, puWallMaster, puWallTurrets, puWindMastery
  ]

  # Define NORMAL-ONLY powerups (ONLY appear after wave clears)
  let normalOnlyTypes: array[0..38, PowerUpType] = [
    puArcaneAura, puArcaneBullets, puArcaneOrb, puBerserker, puBloodAura,
    puBloodBullets, puBloodOrb, puBulletRicochet, puBulletSplit,
    puChainLightning, puCriticalHit, puDodgeChance, puExplosiveBullets,
    puFireAura, puFireBullets, puFireOrb, puFortified, puFrostOrb, puFrostShots,
    puHeavyRounds, puLifeSteal, puLightningAura, puLightningOrb, puPiercingShots,
    puPoisonAura, puPoisonOrb, puPoisonShot, puPulseArmor, puRadialBurst, puRage,
    puRegeneration, puRotatingShield, puSlowField, puThorns, puWindAura,
    puWindBullets, puWindOrb, puSpecialRounds, puGiantSlayer
  ]
  
  # Define orb, aura, bullet, and mastery groups for exclusivity
  let orbTypes: array[0..7, PowerUpType] = [puPoisonOrb, puFireOrb, puLightningOrb, puWindOrb, puFrostOrb, puArcaneOrb, puBloodOrb, puRotatingOrbs]
  let auraTypes: array[0..5, PowerUpType] = [puFireAura, puLightningAura, puPoisonAura, puWindAura, puArcaneAura, puBloodAura]
  let bulletTypes: array[0..4, PowerUpType] = [puFireBullets, puPoisonShot, puFrostShots, puWindBullets, puArcaneBullets]
  let masteryTypes: array[0..6, PowerUpType] = [puFireMastery, puPoisonMastery, puFrostMastery, puArcaneMastery, puLightningMastery, puWindMastery, puBloodMastery]
  
  if isLegendary:
    # BOSS DEFEATED - offer ONLY legendary-exclusive power-ups
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
  
  # Apply grouping logic - ensure at most 1 orb, 1 aura, 1 elemental bullet, and 1 mastery
  var selectedPowerUps: seq[PowerUp] = @[]
  var hasOrb = false
  var hasAura = false
  var hasBullet = false
  var hasMastery = false
  
  for powerUp in availablePowerUps:
    if selectedPowerUps.len >= 3:
      break
    
    # Exceptions

    let isOrb = powerUp.powerType in orbTypes
    let isAura = powerUp.powerType in auraTypes
    let isBullet = powerUp.powerType in bulletTypes
    let isMastery = powerUp.powerType in masteryTypes
    
    if isOrb and hasOrb:
      continue
    
    if isAura and hasAura:
      continue
    
    if isBullet and hasBullet:
      continue
    
    if isMastery and hasMastery:
      continue
    
    # Add this power-up and mark categories
    selectedPowerUps.add(powerUp)
    if isOrb:
      hasOrb = true
    if isAura:
      hasAura = true
    if isBullet:
      hasBullet = true
    if isMastery:
      hasMastery = true
  
  # Fill result with selected power-ups (up to 3)
  for i in 0..2:
    if i < selectedPowerUps.len:
      result[i] = selectedPowerUps[i]
    else:
      # If we run out, create random power-ups from the CORRECT pool
      # Make sure to don't violate orb/aura/bullet/mastery pooling
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
        let isMastery = randomPowerUp.powerType in masteryTypes
        
        # Check if this violates our grouping rules
        if (isOrb and hasOrb) or (isAura and hasAura) or (isBullet and hasBullet) or (isMastery and hasMastery):
          attempts += 1
          continue
        
        result[i] = randomPowerUp
        if isOrb:
          hasOrb = true
        if isAura:
          hasAura = true
        if isBullet:
          hasBullet = true
        if isMastery:
          hasMastery = true
        break

# ROTATING ORBS SYSTEM
proc newRotatingOrb*(angle: float32, radius: float32, elementType: ElementType, orbLevel: int = 1): RotatingOrb =
  result = RotatingOrb(
    angle: angle,
    radius: radius,
    elementType: elementType,
    orbLevel: orbLevel,
    hitEnemies: @[],
    lastHitTime: initTable[int, float32]()
  )

const ORB_ORBIT_RADIUS_BASE = 42.0
const ORB_ORBIT_RING_GAP    = 34.0

proc getOrbRingRadius*(player: Player, level: int): float32 =
  ## Level 1 → ring 1, level 2 → ring 2, level 3 → ring 3, level 4 (legendary) → ring 4.
  ## All orbs of the same level share exactly one ring; different levels never touch.
  result = player.radius * 4.5 + ORB_ORBIT_RADIUS_BASE +
           float32(level - 1) * ORB_ORBIT_RING_GAP

proc redistributeAllOrbs*(player: Player) =
  ## For each level tier: collect orbs, interleave by element type
  ## (1,2,3,1,2,3...), then assign evenly-spaced angles on that ring.
  for lv in 1..4:
    # Collect indices of every orb at this level, grouped by element
    var groups: seq[seq[int]]   # groups[g] = list of rotatingOrbs indices for one element
    var elementOrder: seq[ElementType]

    for i, orb in player.rotatingOrbs:
      if orb.orbLevel != lv: continue
      # Find or create group for this element
      var found = false
      for g in 0..<elementOrder.len:
        if elementOrder[g] == orb.elementType:
          groups[g].add(i)
          found = true
          break
      if not found:
        elementOrder.add(orb.elementType)
        groups.add(@[i])

    let totalOrbs = block:
      var s = 0
      for g in groups: s += g.len
      s
    if totalOrbs == 0: continue

    let r = getOrbRingRadius(player, lv)

    # Round-robin through groups to build interleaved order
    var interleaved: seq[int]
    var gPos: seq[int] = newSeq[int](groups.len)  # cursor per group
    var remaining = totalOrbs
    while remaining > 0:
      for g in 0..<groups.len:
        if gPos[g] < groups[g].len:
          interleaved.add(groups[g][gPos[g]])
          gPos[g] += 1
          remaining -= 1

    # Assign radius and evenly-spaced angles in interleaved order
    for j, idx in interleaved:
      player.rotatingOrbs[idx].radius = r
      player.rotatingOrbs[idx].angle  = float32(j) * PI * 2.0 / float32(totalOrbs)

proc createRotatingOrbs*(player: Player, level: int) =
  ## Legendary: adds 1 orb of each of the 6 base elements on ring 4 (outermost).
  ## Clears existing level-4 orbs first so reapply never duplicates them.
  var i = 0
  while i < player.rotatingOrbs.len:
    if player.rotatingOrbs[i].orbLevel == 4:
      player.rotatingOrbs.delete(i)
    else:
      i += 1
  let elements = [etPoison, etFire, etLightning, etWind, etFrost, etArcane]
  for element in elements:
    for _ in 0..1:  # 2 orbs per element = 12 total
      player.rotatingOrbs.add(RotatingOrb(
        angle: 0.0, radius: 0.0,
        elementType: element, orbLevel: 4,
        hitEnemies: @[], lastHitTime: initTable[int, float32]()
      ))
  redistributeAllOrbs(player)

proc createElementalOrbs*(player: Player, elementType: ElementType, level: int) =
  ## Replace all orbs of this element, tagged with the new level.
  ## Level 1 → 2 orbs on ring 1, level 2 → 4 orbs on ring 2, level 3 → 6 orbs on ring 3.
  ## All other elements' orbs are untouched; redistributeAllOrbs re-spaces every ring.

  # Remove existing orbs of this element (any level)
  var i = 0
  while i < player.rotatingOrbs.len:
    if player.rotatingOrbs[i].elementType == elementType:
      player.rotatingOrbs.delete(i)
    else:
      i += 1

  let orbCount = case level
    of 1: 4
    of 2: 8
    else: 12

  for _ in 0..<orbCount:
    player.rotatingOrbs.add(RotatingOrb(
      angle: 0.0, radius: 0.0,
      elementType: elementType, orbLevel: level,
      hitEnemies: @[], lastHitTime: initTable[int, float32]()
    ))

  redistributeAllOrbs(player)

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
  ## Get base damage per hit based on power-up level
  ## Compensated with reduced damage multiplier in game logic
  case level
  of 1: 4.5
  of 2: 7.5
  else: 11.0

proc applyPowerUp*(player: Player, powerUp: PowerUp) =
  # Apply immediate stat bonuses for new powerup types
  case powerUp.powerType
  of puRapidFire:
    # Single level only - +40% fire rate
    player.fireRate *= 0.714  # 1 / 1.4
  of puMaxHealth:
    # Single level only - +14.5 HP
    player.maxHp += 14.5
    player.hp += 14.5
  of puSpeedBoost:
    # Single level only - +40% speed
    player.speed *= 1.4
    player.baseSpeed *= 1.4
  of puBulletSpeed:
    # Single level only - +40% speed
    player.bulletSpeed *= 1.4
  of puTimeWarp:
    # Single level only - 2 uses per wave
    player.timeWarpMaxUsesPerWave = 2
  of puRotatingOrbs:
    # Create all 6 elemental orbs at their predefined positions
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
    # Arcane bullets increase bullet damage only (not base player damage)
    let damageBonus = case powerUp.level
      of 1: 1.5   # +50% bullet damage
      of 2: 2.0   # +100% bullet damage
      else: 2.5   # +150% bullet damage
    player.bulletDamageMult *= damageBonus
  of puFireMastery:
    # Enhance fire effects
    player.hasFireMastery = true
  of puPoisonMastery:
    # Enhance poison effects
    player.hasPoisonMastery = true
  of puFrostMastery:
    # Enhance frost effects
    player.hasFrostMastery = true
  of puArcaneMastery:
    # Enhance arcane effects
    player.hasArcaneMastery = true
  of puLightningMastery:
    # Enhance lightning effects
    player.hasLightningMastery = true
  of puWindMastery:
    # Enhance wind effects
    player.hasWindMastery = true
  of puBloodMastery:
    # Enhance blood effects
    player.hasBloodMastery = true
  of puBloodOrb:
    createElementalOrbs(player, etBlood, powerUp.level)
  of puPulseArmor:
    # Pulse armor is passive - shockwave emitted when player takes damage
    # Cooldown timer initialized to 0 (ready to use)
    player.pulseArmorCooldown = 0.0
  of puHeavyRounds:
    let sizeBonus = case powerUp.level
      of 1: 1.5   # +50% size
      of 2: 2.0   # +100% size
      else: 2.5   # +150% size
    player.radius *= sizeBonus
  of puFortified:
    # Fortified reduces damage taken + increases max HP
    let hpBonus = case powerUp.level
      of 1: 4.0   # +4 HP
      of 2: 7.0  # +7 HP
      else: 10.0  # +10 HP
    player.maxHp += hpBonus
    player.hp += hpBonus
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
          of 1: 5.5
          of 2: 4.5
          else: 3.75
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
        player.bulletDamageMult *= damageBonus
      of puHeavyRounds:
        # When upgrading Heavy Rounds, increase size further
        let sizeBonus = case powerUp.level
          of 2: 1.333  # 2.0 / 1.5
          of 3: 1.25   # 2.5 / 2.0
          else: 1.0
        player.radius *= sizeBonus
      else:
        discard

      found = true
      break
  
  if not found:
    # Add new power-up
    player.powerUps.add(powerUp)

proc drawPowerUpSelection*(game: Game) =
  drawOSPowerUpInstaller(game)
  
  # Draw combo notification in BOTTOM RIGHT corner during power-up screen
  # Position it slightly higher to avoid being cut off at screen edge
  drawComboAtPosition(game.dopamine.comboSystem, game.screenWidth, game.screenHeight,
                      game.time, game.screenWidth - 250, game.screenHeight - 180)

# SLOT MACHINE ROLL ANIMATION SYSTEM
proc generateRandomPowerUpExcluding(player: Player, isLegendary: bool, excludeType: PowerUpType): PowerUp =
  ## Generate a random power-up for the roll animation display, excluding a specific type
  let legendaryTypes = [puRapidFire, puMaxHealth, puSpeedBoost,
                        puBulletSpeed, puLuckyCoins, puWallMaster, puTimeWarp,
                        puGravityWell, puPhaseShift, puOvercharge, puEchoShots,
                        puMagicalBullets]
  
  let normalTypes = [puDoubleShot, puRotatingShield,
                     puPiercingShots, puMultiShot, puExplosiveBullets, puLifeSteal,
                     puAutoShoot, puRegeneration, puDodgeChance,
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
    # The final position should show the LAST card in the list
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
      # Slot is stopped - FORCE exact final position every frame
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
  
  # Each slot i must use game.powerUpChoices[i], NOT game.powerUpChoices[0]
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
    
    # Last item MUST be THIS SLOT'S final power-up (slot i)
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
  
  # Increase cost for next reroll (adds 25 coins)
  game.rerollCost += 25
  
  return true

proc initializeRerollCost*(game: Game) =
  ## Initialize the reroll cost at the start of a power-up selection
  ## Base cost: 25 coins for first reroll, increases by 25 each time
  game.rerollCost = 25
