## Enemy Configuration System
## Centralizes all enemy properties, behavior parameters, and attack patterns
## Similar to boss_definitions.nim but for regular enemies

import raylib, types, math, random

type
  EnemyAttackConfig* = object
    ## Configuration for enemy ranged attacks
    fireRate*: float32          # Cooldown between shots (seconds)
    bulletSpeed*: float32        # Speed of projectiles
    bulletCount*: int            # Number of bullets per attack
    spreadAngle*: float32        # Spread angle for multi-shot (radians)
    damage*: float32             # Ranged damage
    usesBurst*: bool             # Whether to fire multiple shots in quick succession
    burstCount*: int             # Number of shots in a burst
    burstDelay*: float32         # Delay between burst shots
    homingStrength*: float32     # 0.0 = no homing, 1.0 = full homing
    isPentagonBullet*: bool      # Special pentagon-shaped bullet
    bulletCountMin*: int         # Minimum bullets (for randomization)
    bulletCountMax*: int         # Maximum bullets (for randomization)
    randomizeBulletCount*: bool  # Whether to randomize bullet count
    inaccuracyAmount*: float32   # Random spread amount (0.0 = perfect aim)
    bulletRadius*: float32       # Bullet size (0 = use default)
    
  EnemyMovementConfig* = object
    ## Configuration for enemy movement behavior
    baseSpeed*: float32          # Base movement speed
    dashSpeed*: float32          # Speed during dash attacks
    dashCooldown*: float32       # Cooldown between dashes
    dashDuration*: float32       # How long dash lasts
    teleportCooldown*: float32   # Cooldown between teleports
    teleportRange*: float32      # Max teleport distance
    maintainsDistance*: bool     # Whether to keep distance from player
    optimalDistance*: float32    # Preferred distance from player
    retreatDistance*: float32    # Distance to start retreating
    
  EnemyConfig* = object
    ## Complete configuration for an enemy type
    enemyType*: EnemyType
    name*: string
    description*: string
    
    # Base stats
    baseHP*: float32
    baseRadius*: float32
    contactDamage*: int
    baseColor*: Color
    
    # Movement configuration
    movement*: EnemyMovementConfig
    
    # Attack configuration (optional - only for ranged enemies)
    hasRangedAttack*: bool
    attack*: EnemyAttackConfig
    
    # Special behaviors
    hasSpecialBehavior*: bool
    specialBehaviorType*: string  # "dash", "teleport", "clone", "warning_attack", etc.
    specialCooldown*: float32
    specialData*: string          # JSON-like data for special mechanics
    
    # Visual configuration
    requiresScreenEntry*: bool    # Must enter screen before attacking
    trailEffect*: bool            # Shows motion trail
    glowEffect*: bool             # Pulsing glow effect
    
    # Hit requirements (for star-type enemies)
    usesHitCount*: bool
    baseRequiredHits*: int

# =============================================================================
# ENEMY CONFIGURATION DEFINITIONS
# =============================================================================

proc getEnemyConfig*(enemyType: EnemyType): EnemyConfig =
  ## Returns the complete configuration for a given enemy type
  case enemyType
  
  of etCircle:  # Normal chaser - melee only
    result = EnemyConfig(
      enemyType: etCircle,
      name: "Circle Chaser",
      description: "Basic melee enemy that chases the player",
      
      baseHP: 1.0,
      baseRadius: 8.0,  # Reduced for proper size
      contactDamage: 1,
      baseColor: Red,
      
      movement: EnemyMovementConfig(
        baseSpeed: 100.0,
        dashSpeed: 0.0,
        dashCooldown: 0.0,
        dashDuration: 0.0,
        teleportCooldown: 0.0,
        teleportRange: 0.0,
        maintainsDistance: false,
        optimalDistance: 0.0,
        retreatDistance: 0.0
      ),
      
      hasRangedAttack: false,
      hasSpecialBehavior: false,
      requiresScreenEntry: false,
      trailEffect: false,
      glowEffect: false,
      usesHitCount: false
    )
  
  of etPentagon:  # Single fast bullet, low fire rate
    result = EnemyConfig(
      enemyType: etPentagon,
      name: "Pentagon Sniper",
      description: "Precision ranged enemy with powerful, fast projectiles",
      
      baseHP: 2.2,
      baseRadius: 11.0,
      contactDamage: 1,
      baseColor: Color(r: 0, g: 150, b: 100, a: 255),  # Teal
      
      movement: EnemyMovementConfig(
        baseSpeed: 55.0,
        dashSpeed: 0.0,
        dashCooldown: 0.0,
        dashDuration: 0.0,
        teleportCooldown: 0.0,
        teleportRange: 0.0,
        maintainsDistance: true,
        optimalDistance: 300.0,
        retreatDistance: 250.0
      ),
      
      hasRangedAttack: true,
      attack: EnemyAttackConfig(
        fireRate: 2.5,        # Low fire rate
        bulletSpeed: 400.0,   # Very fast
        bulletCount: 1,       # Single powerful shot
        spreadAngle: 0.0,     # No spread - precise
        damage: 2.0,
        usesBurst: false,
        burstCount: 0,
        burstDelay: 0.0,
        homingStrength: 0.0,
        isPentagonBullet: true,  # Special large pentagon bullet
        bulletCountMin: 0,
        bulletCountMax: 0,
        randomizeBulletCount: false,
        inaccuracyAmount: 0.0,  # Perfect aim
        bulletRadius: 10.0      # Large pentagon bullet
      ),
      
      hasSpecialBehavior: false,
      requiresScreenEntry: true,
      trailEffect: false,
      glowEffect: true,       # Charge-up glow before firing
      usesHitCount: false
    )
  
  of etTriangle:  # Dash + erratic movement
    result = EnemyConfig(
      enemyType: etTriangle,
      name: "Triangle Dasher",
      description: "Fast enemy with erratic zigzag movement and dash attacks",
      
      baseHP: 1.4,
      baseRadius: 10.5,
      contactDamage: 1,
      baseColor: Pink,
      
      movement: EnemyMovementConfig(
        baseSpeed: 155.0,
        dashSpeed: 542.5,     # 3.5x base speed
        dashCooldown: 2.0,
        dashDuration: 0.3,
        teleportCooldown: 0.0,
        teleportRange: 0.0,
        maintainsDistance: false,
        optimalDistance: 0.0,
        retreatDistance: 0.0
      ),
      
      hasRangedAttack: false,
      
      hasSpecialBehavior: true,
      specialBehaviorType: "erratic_dash",
      specialCooldown: 3.0,  # Random 2-3 seconds
      specialData: "zigzag_pattern|dash_range:150|dash_multiplier:3.0",
      
      requiresScreenEntry: false,
      trailEffect: true,      # Shows motion trail during dash
      glowEffect: true,       # Charge-up glow before dash
      usesHitCount: false
    )
  
  of etStar:  # Tank that dashes when close
    result = EnemyConfig(
      enemyType: etStar,
      name: "Star Tank",
      description: "Durable tank enemy that requires multiple hits to defeat",
      
      baseHP: 9999.0,  # Hit-count based, not HP based
      baseRadius: 14.0,
      contactDamage: 1,
      baseColor: Color(r: 255, g: 215, b: 0, a: 255),  # Gold
      
      movement: EnemyMovementConfig(
        baseSpeed: 70.0,
        dashSpeed: 210.0,     # 3x base speed
        dashCooldown: 2.0,
        dashDuration: 0.5,
        teleportCooldown: 0.0,
        teleportRange: 0.0,
        maintainsDistance: false,
        optimalDistance: 0.0,
        retreatDistance: 0.0
      ),
      
      hasRangedAttack: false,
      
      hasSpecialBehavior: true,
      specialBehaviorType: "proximity_dash",
      specialCooldown: 2.0,
      specialData: "dash_range:150",
      
      requiresScreenEntry: false,
      trailEffect: false,
      glowEffect: true,       # Pulsing glow + charge glow
      usesHitCount: true,
      baseRequiredHits: 5     # Base hits required (scales with difficulty)
    )
  
  of etCube:  # Ranged shooter
    result = EnemyConfig(
      enemyType: etCube,
      name: "Cube Shooter",
      description: "Ranged enemy that maintains distance and fires 3-shot bursts",
      
      baseHP: 3.0,
      baseRadius: 10.0,
      contactDamage: 1,
      baseColor: Purple,
      
      movement: EnemyMovementConfig(
        baseSpeed: 55.0,
        dashSpeed: 0.0,
        dashCooldown: 0.0,
        dashDuration: 0.0,
        teleportCooldown: 0.0,
        teleportRange: 0.0,
        maintainsDistance: true,
        optimalDistance: 250.0,
        retreatDistance: 150.0
      ),
      
      hasRangedAttack: true,
      attack: EnemyAttackConfig(
        fireRate: 1.75,        # Fires every 1.75 seconds
        bulletSpeed: 220.0,   # Fast projectiles
        bulletCount: 3,       # 3-shot burst
        spreadAngle: 0.33,     # Small spread
        damage: 2.0,          # Higher ranged damage
        usesBurst: true,
        burstCount: 3,
        burstDelay: 0.05,
        homingStrength: 0.0,
        isPentagonBullet: false,
        bulletCountMin: 0,
        bulletCountMax: 0,
        randomizeBulletCount: false,
        inaccuracyAmount: 0.0,
        bulletRadius: 0.0
      ),
      
      hasSpecialBehavior: false,
      requiresScreenEntry: true,  # Must enter screen before attacking
      trailEffect: false,
      glowEffect: false,
      usesHitCount: false
    )
  
  of etHexagon:  # Teleporting chaos
    result = EnemyConfig(
      enemyType: etHexagon,
      name: "Hexagon Warper",
      description: "Teleporting enemy that shoots chaotic bullet patterns",
      
      baseHP: 5.0,
      baseRadius: 10.0,
      contactDamage: 1,
      baseColor: Color(r: 128, g: 0, b: 255, a: 255),  # Purple
      
      movement: EnemyMovementConfig(
        baseSpeed: 70.0,
        dashSpeed: 0.0,
        dashCooldown: 0.0,
        dashDuration: 0.0,
        teleportCooldown: 2.5,  # Base cooldown (randomized)
        teleportRange: 200.0,   # Teleport distance from player
        maintainsDistance: false,
        optimalDistance: 0.0,
        retreatDistance: 0.0
      ),
      
      hasRangedAttack: true,
      attack: EnemyAttackConfig(
        fireRate: 0.75,       # Fast fire rate
        bulletSpeed: 220.0,
        bulletCount: 3,       # Average (2-4 random)
        spreadAngle: 6.28,    # Full circle (random directions)
        damage: 1.0,
        usesBurst: false,
        burstCount: 0,
        burstDelay: 0.0,
        homingStrength: 0.0,
        isPentagonBullet: false,
        bulletCountMin: 2,
        bulletCountMax: 4,
        randomizeBulletCount: true,
        inaccuracyAmount: 0.5,  # Chaotic aim
        bulletRadius: 0.0
      ),
      
      hasSpecialBehavior: true,
      specialBehaviorType: "teleport_chaos",
      specialCooldown: 3.5,   # Randomized 2.5-3.5
      specialData: "chaotic_shooting",
      
      requiresScreenEntry: false,
      trailEffect: false,
      glowEffect: true,       # Teleport warning glow
      usesHitCount: false
    )
  
  of etCross:  # Shows cross warning before attack
    result = EnemyConfig(
      enemyType: etCross,
      name: "Cross Striker",
      description: "Shows warning before executing spinning laser dash attack",
      
      baseHP: 10.0,
      baseRadius: 13.0,
      contactDamage: 4,      # High contact damage during attack
      baseColor: Color(r: 255, g: 100, b: 0, a: 255),  # Orange
      
      movement: EnemyMovementConfig(
        baseSpeed: 50.0,
        dashSpeed: 200.0,    # 4x base speed during attack
        dashCooldown: 0.0,
        dashDuration: 0.5,
        teleportCooldown: 0.0,
        teleportRange: 0.0,
        maintainsDistance: false,
        optimalDistance: 0.0,
        retreatDistance: 0.0
      ),
      
      hasRangedAttack: false,  # Uses laser during dash, not bullets
      
      hasSpecialBehavior: true,
      specialBehaviorType: "warning_laser_dash",
      specialCooldown: 3.0,    # Time between attack cycles
      specialData: "warning_duration:1.2|dash_duration:0.5|laser_length:120|rotation_speed:12.5",
      
      requiresScreenEntry: false,
      trailEffect: true,       # Motion blur during dash
      glowEffect: true,        # Pulsing warning glow
      usesHitCount: false
    )
  
  of etDiamond:  # Shoots while dashing
    result = EnemyConfig(
      enemyType: etDiamond,
      name: "Diamond Dasher",
      description: "Fast enemy that shoots projectiles during dash attacks",
      
      baseHP: 4.0,
      baseRadius: 9.0,
      contactDamage: 1,
      baseColor: Color(r: 0, g: 200, b: 255, a: 255),  # Cyan
      
      movement: EnemyMovementConfig(
        baseSpeed: 140.0,
        dashSpeed: 350.0,     # 2.5x base speed
        dashCooldown: 2.5,    # Randomized 2.5-3.5
        dashDuration: 0.4,
        teleportCooldown: 0.0,
        teleportRange: 0.0,
        maintainsDistance: false,
        optimalDistance: 0.0,
        retreatDistance: 0.0
      ),
      
      hasRangedAttack: true,
      attack: EnemyAttackConfig(
        fireRate: 1.0,        # Shoots during movement
        bulletSpeed: 140.0,   # Slow projectiles  
        bulletCount: 3,       # 3 bullets during dash
        spreadAngle: 0.3,     # Small spread (-1, 0, +1)
        damage: 1.0,
        usesBurst: false,
        burstCount: 0,
        burstDelay: 0.0,
        homingStrength: 0.0,
        isPentagonBullet: false,
        bulletCountMin: 0,
        bulletCountMax: 0,
        randomizeBulletCount: false,
        inaccuracyAmount: 0.0,
        bulletRadius: 0.0
      ),
      
      hasSpecialBehavior: true,
      specialBehaviorType: "dash_shooting",
      specialCooldown: 3.5,   # Randomized
      specialData: "shoots_on_dash|shoots_periodically",
      
      requiresScreenEntry: false,
      trailEffect: false,
      glowEffect: true,       # Dash indicator
      usesHitCount: false
    )
  
  of etOctagon:  # Many slow inaccurate projectiles
    result = EnemyConfig(
      enemyType: etOctagon,
      name: "Octagon Sprayer",
      description: "Ranged enemy with high fire rate but low accuracy",
      
      baseHP: 3.5,
      baseRadius: 12.0,
      contactDamage: 1,
      baseColor: Color(r: 150, g: 150, b: 0, a: 255),  # Yellow-brown
      
      movement: EnemyMovementConfig(
        baseSpeed: 90.0,
        dashSpeed: 0.0,
        dashCooldown: 0.0,
        dashDuration: 0.0,
        teleportCooldown: 0.0,
        teleportRange: 0.0,
        maintainsDistance: true,
        optimalDistance: 200.0,
        retreatDistance: 200.0
      ),
      
      hasRangedAttack: true,
      attack: EnemyAttackConfig(
        fireRate: 0.4,        # Very frequent shots
        bulletSpeed: 120.0,   # Slow projectiles
        bulletCount: 1,       # Single shot
        spreadAngle: 0.8,     # High inaccuracy (random ±0.4 radians)
        damage: 1.0,
        usesBurst: false,
        burstCount: 0,
        burstDelay: 0.0,
        homingStrength: 0.0,
        isPentagonBullet: false,
        bulletCountMin: 0,
        bulletCountMax: 0,
        randomizeBulletCount: false,
        inaccuracyAmount: 0.8,  # Very inaccurate
        bulletRadius: 0.0
      ),
      
      hasSpecialBehavior: false,
      requiresScreenEntry: true,
      trailEffect: false,
      glowEffect: true,       # Constant firing glow
      usesHitCount: false
    )
  
  of etTrickster:  # False warning, real attack elsewhere
    result = EnemyConfig(
      enemyType: etTrickster,
      name: "Trickster",
      description: "Deceptive enemy that shows fake warnings and teleports",
      
      baseHP: 4.0,
      baseRadius: 13.0,
      contactDamage: 1,
      baseColor: Color(r: 200, g: 0, b: 200, a: 255),  # Magenta
      
      movement: EnemyMovementConfig(
        baseSpeed: 65.0,
        dashSpeed: 0.0,
        dashCooldown: 0.0,
        dashDuration: 0.0,
        teleportCooldown: 3.0,  # Randomized 3-5 seconds
        teleportRange: 150.0,
        maintainsDistance: false,
        optimalDistance: 0.0,
        retreatDistance: 0.0
      ),
      
      hasRangedAttack: true,
      attack: EnemyAttackConfig(
        fireRate: 0.0,        # Fires during special behavior only
        bulletSpeed: 250.0,
        bulletCount: 6,       # 6-way circular burst after teleport
        spreadAngle: 1.047,   # 60 degrees between shots (PI/3)
        damage: 1.0,
        usesBurst: false,
        burstCount: 0,
        burstDelay: 0.0,
        homingStrength: 0.0,
        isPentagonBullet: false,
        bulletCountMin: 0,
        bulletCountMax: 0,
        randomizeBulletCount: false,
        inaccuracyAmount: 0.0,
        bulletRadius: 0.0
      ),
      
      hasSpecialBehavior: true,
      specialBehaviorType: "fake_warning_teleport",
      specialCooldown: 4.0,   # Randomized 3-5
      specialData: "fake_warning:1.0|teleport_shoot",
      
      requiresScreenEntry: false,
      trailEffect: false,
      glowEffect: true,       # Mysterious pulse
      usesHitCount: false
    )
  
  of etPhantom:  # Unpredictable teleporter with fake clones
    result = EnemyConfig(
      enemyType: etPhantom,
      name: "Phantom",
      description: "Teleporting enemy that creates fake clones to confuse",
      
      baseHP: 4.0,
      baseRadius: 11.0,
      contactDamage: 1,
      baseColor: Color(r: 100, g: 100, b: 255, a: 180),  # Semi-transparent blue
      
      movement: EnemyMovementConfig(
        baseSpeed: 80.0,
        dashSpeed: 0.0,
        dashCooldown: 0.0,
        dashDuration: 0.0,
        teleportCooldown: 2.0,  # Randomized 2-3.5 seconds
        teleportRange: 200.0,
        maintainsDistance: false,
        optimalDistance: 0.0,
        retreatDistance: 0.0
      ),
      
      hasRangedAttack: true,
      attack: EnemyAttackConfig(
        fireRate: 0.8,        # Fairly fast
        bulletSpeed: 260.0,
        bulletCount: 1,       # Single shot
        spreadAngle: 0.0,
        damage: 1.0,
        usesBurst: false,
        burstCount: 0,
        burstDelay: 0.0,
        homingStrength: 0.0,
        isPentagonBullet: false,
        bulletCountMin: 0,
        bulletCountMax: 0,
        randomizeBulletCount: false,
        inaccuracyAmount: 0.0,
        bulletRadius: 0.0
      ),
      
      hasSpecialBehavior: true,
      specialBehaviorType: "clone_teleport",
      specialCooldown: 3.0,   # Randomized 2-3.5
      specialData: "clone_count:3|shoot_from_clones:60%",
      
      requiresScreenEntry: false,
      trailEffect: false,
      glowEffect: true,       # Fade effect
      usesHitCount: false
    )
  
  of etSniper:  # Rare one-shot enemy with epic charging attack
    result = EnemyConfig(
      enemyType: etSniper,
      name: "Sniper",
      description: "Deadly enemy that charges a powerful one-shot kill attack",
      
      baseHP: 6.0,
      baseRadius: 10.0,
      contactDamage: 3,
      baseColor: Color(r: 200, g: 50, b: 200, a: 255),  # Bright magenta
      
      movement: EnemyMovementConfig(
        baseSpeed: 40.0,      # Very slow
        dashSpeed: 0.0,
        dashCooldown: 0.0,
        dashDuration: 0.0,
        teleportCooldown: 0.0,
        teleportRange: 0.0,
        maintainsDistance: false,
        optimalDistance: 0.0,
        retreatDistance: 0.0
      ),
      
      hasRangedAttack: true,
      attack: EnemyAttackConfig(
        fireRate: 0.0,        # Controlled by charge mechanic
        bulletSpeed: 400.0,   # Very fast
        bulletCount: 1,
        spreadAngle: 0.0,
        damage: 9999.0,       # One-shot kill
        usesBurst: false,
        burstCount: 0,
        burstDelay: 0.0,
        homingStrength: 0.0,
        isPentagonBullet: false,
        bulletCountMin: 0,
        bulletCountMax: 0,
        randomizeBulletCount: false,
        inaccuracyAmount: 0.0,
        bulletRadius: 12.0  # Massive bullet
      ),
      
      hasSpecialBehavior: true,
      specialBehaviorType: "charge_shot",
      specialCooldown: 2.0,   # Cooldown after firing
      specialData: "charge_time:3.0|trigger_range:300|cooldown:2.0|color_shift",
      
      requiresScreenEntry: false,
      trailEffect: false,
      glowEffect: true,       # Charging rings
      usesHitCount: false
    )
  
  of etMage:  # Summons meteorites and shoots homing magic bullets
    result = EnemyConfig(
      enemyType: etMage,
      name: "Mage",
      description: "Magical enemy that summons meteorites and fires homing projectiles",
      
      baseHP: 7.5,
      baseRadius: 12.0,
      contactDamage: 1,
      baseColor: Color(r: 138, g: 43, b: 226, a: 255),  # Purple/violet
      
      movement: EnemyMovementConfig(
        baseSpeed: 50.0,
        dashSpeed: 0.0,
        dashCooldown: 0.0,
        dashDuration: 0.0,
        teleportCooldown: 0.0,
        teleportRange: 0.0,
        maintainsDistance: true,
        optimalDistance: 250.0,
        retreatDistance: 180.0
      ),
      
      hasRangedAttack: true,
      attack: EnemyAttackConfig(
        fireRate: 2.5,        # Magic bullet cooldown
        bulletSpeed: 220.0,
        bulletCount: 1,
        spreadAngle: 0.0,
        damage: 2.0,
        usesBurst: false,
        burstCount: 0,
        burstDelay: 0.0,
        homingStrength: 1.0,  # Full homing
        isPentagonBullet: false,
        bulletCountMin: 0,
        bulletCountMax: 0,
        randomizeBulletCount: false,
        inaccuracyAmount: 0.0,
        bulletRadius: 8.0  # Larger magic bullets
      ),
      
      hasSpecialBehavior: true,
      specialBehaviorType: "summon_meteorites",
      specialCooldown: 4.0,   # Meteorite summon cooldown
      specialData: "meteorite_count:2|meteorite_count_random:1|warning_time:1.5|damage:3",
      
      requiresScreenEntry: true,
      trailEffect: false,
      glowEffect: true,       # Magical aura and casting glow
      usesHitCount: false
    )

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

proc getScaledEnemyStats*(config: EnemyConfig, difficulty: float32): tuple[hp: float32, radius: float32, speed: float32, requiredHits: int] =
  ## Calculate scaled stats based on difficulty (wave number)
  let strengthMultiplier = pow(1.185, difficulty)  # 0.5% more HP per wave
  
  let hp = config.baseHP * strengthMultiplier
  let radius = config.baseRadius + difficulty * 1.5 + rand(5).float32
  let speed = config.movement.baseSpeed + difficulty * (
    if config.enemyType == etTriangle: 10.0
    elif config.enemyType in [etCube, etOctagon, etPentagon, etMage]: 3.0
    elif config.enemyType == etStar: 6.0
    elif config.enemyType == etHexagon: 8.0
    elif config.enemyType == etCross: 4.0
    elif config.enemyType == etDiamond: 12.0
    elif config.enemyType == etTrickster: 5.0
    elif config.enemyType == etPhantom: 6.0
    elif config.enemyType == etSniper: 2.0
    else: 10.0
  )
  
  let requiredHits = if config.usesHitCount:
    config.baseRequiredHits + (difficulty * 1.8).int
  else:
    0
  
  return (hp: hp, radius: radius, speed: speed, requiredHits: requiredHits)
