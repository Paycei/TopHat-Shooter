## enemy_config.nim
## Single source of truth for all enemy definitions: stats, attack/movement config,
## and speed scaling. Which enemies spawn where is each mode's roster.
##
## Adding a new enemy:
##   1. types.nim        -> add the EnemyType variant (keep etEnvironment last)
##   2. enemy_config.nim -> add a block in getEnemyConfig  (stats, attack, movement, speedScaling)
##   3. enemy.nim        -> add the update case in updateEnemy and the draw case in
##                          drawEnemy (survival/roguelite types delegate to
##                          mode_enemies.nim / mode_visuals.nim)
##   4. localization.nim -> add tkEnemyXName / tkEnemyXDesc keys + both-language strings
##   5. put it in a roster: wave mode's ladder (spawnWaveEnemies in game.nim),
##      SurvivalRoster (survival.nim) or a folder theme (themeDef in dungeon.nim)
## The compiler then lists the remaining exhaustive sites (coin/XP values,
## dungeon tuning wave, cheat menu, in-world label).

import raylib, math, random
import types, localization

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
    bulletLifetime*: float32     # Seconds before the bullet despawns (0 = use default)

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
    contactDamage*: float32
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

    # Difficulty scaling
    speedScaling*: float32            ## Speed gained per 1 unit of difficulty

# Survival / Roguelite roster builders. These enemies keep their behaviour in
# mode_enemies.nim; the config only carries the numbers.
proc modeMelee(et: EnemyType, name, desc: string, hp, radius, contact: float32,
               color: Color, speed, speedScaling: float32): EnemyConfig =
  EnemyConfig(enemyType: et, name: name, description: desc,
              baseHP: hp, baseRadius: radius, contactDamage: contact, baseColor: color,
              movement: EnemyMovementConfig(baseSpeed: speed),
              speedScaling: speedScaling)

proc modeRanged(et: EnemyType, name, desc: string, hp, radius, contact: float32,
                color: Color, speed, speedScaling: float32,
                optimal, retreat: float32, attack: EnemyAttackConfig): EnemyConfig =
  result = modeMelee(et, name, desc, hp, radius, contact, color, speed, speedScaling)
  result.movement.maintainsDistance = true
  result.movement.optimalDistance = optimal
  result.movement.retreatDistance = retreat
  result.hasRangedAttack = true
  result.attack = attack
  result.requiresScreenEntry = true

proc modeFan(fireRate, bulletSpeed: float32, count: int, spread, damage: float32,
             lifetime = 3.0'f32): EnemyAttackConfig =
  EnemyAttackConfig(fireRate: fireRate, bulletSpeed: bulletSpeed, bulletCount: count,
                    spreadAngle: spread, damage: damage, bulletLifetime: lifetime)

# Per-enemy stat and behaviour configuration
proc getEnemyConfig*(enemyType: EnemyType): EnemyConfig =
  ## Returns the complete configuration for a given enemy type
  case enemyType

  of etCircle:  # Normal chaser - melee only
    result = EnemyConfig(
      enemyType: etCircle,
      name: t(tkEnemyCircleName),
      description: t(tkEnemyCircleDesc),

      baseHP: 1.0,
      baseRadius: 8.0,
      contactDamage: 2,
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
      usesHitCount: false,
      speedScaling: 10.0
    )

  of etPentagon:  # Single fast bullet, low fire rate
    result = EnemyConfig(
      enemyType: etPentagon,
      name: t(tkEnemyPentagonName),
      description: t(tkEnemyPentagonDesc),

      baseHP: 2.5,
      baseRadius: 11.0,
      contactDamage: 2,
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
        spreadAngle: 0.0,
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
      usesHitCount: false,
      speedScaling: 3.0
    )

  of etTriangle:  # Dash + erratic movement
    result = EnemyConfig(
      enemyType: etTriangle,
      name: t(tkEnemyTriangleName),
      description: t(tkEnemyTriangleDesc),

      baseHP: 3.0,
      baseRadius: 10.5,
      contactDamage: 2.5,
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
      usesHitCount: false,
      speedScaling: 10.0
    )

  of etStar:  # Tank that dashes when close
    result = EnemyConfig(
      enemyType: etStar,
      name: t(tkEnemyStarName),
      description: t(tkEnemyStarDesc),

      baseHP: 9999.0,  # Hit-count based, not HP based
      baseRadius: 14.0,
      contactDamage: 2.5,
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
      baseRequiredHits: 10,    # Base hits required (scales with difficulty)
      speedScaling: 6.0
    )

  of etCube:  # Ranged shooter
    result = EnemyConfig(
      enemyType: etCube,
      name: t(tkEnemyCubeName),
      description: t(tkEnemyCubeDesc),

      baseHP: 3.0,
      baseRadius: 10.0,
      contactDamage: 3,
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
        damage: 3.5,          # Higher ranged damage
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
      usesHitCount: false,
      speedScaling: 3.0
    )

  of etHexagon:  # Teleporting chaos
    result = EnemyConfig(
      enemyType: etHexagon,
      name: t(tkEnemyHexagonName),
      description: t(tkEnemyHexagonDesc),

      baseHP: 7.5,
      baseRadius: 10.0,
      contactDamage: 3,
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
        damage: 5.0,
        usesBurst: false,
        burstCount: 0,
        burstDelay: 0.0,
        homingStrength: 0.0,
        isPentagonBullet: false,
        bulletCountMin: 2,
        bulletCountMax: 4,
        randomizeBulletCount: true,
        inaccuracyAmount: 0.0,  # spreadAngle:6.28 already randomises over full circle; extra inaccuracy is redundant
        bulletRadius: 0.0
      ),

      hasSpecialBehavior: true,
      specialBehaviorType: "teleport_chaos",
      specialCooldown: 3.5,   # Randomized 2.5-3.5
      specialData: "chaotic_shooting",

      requiresScreenEntry: false,
      trailEffect: false,
      glowEffect: true,       # Teleport warning glow
      usesHitCount: false,
      speedScaling: 8.0
    )

  of etCross:  # Shows cross warning before attack
    result = EnemyConfig(
      enemyType: etCross,
      name: t(tkEnemyCrossName),
      description: t(tkEnemyCrossDesc),

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
      usesHitCount: false,
      speedScaling: 4.0
    )

  of etDiamond:  # Shoots while dashing
    result = EnemyConfig(
      enemyType: etDiamond,
      name: t(tkEnemyDiamondName),
      description: t(tkEnemyDiamondDesc),

      baseHP: 7.5,
      baseRadius: 9.0,
      contactDamage: 4,
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
        damage: 4.5,
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
      usesHitCount: false,
      speedScaling: 12.0
    )

  of etOctagon:  # Many slow inaccurate projectiles
    result = EnemyConfig(
      enemyType: etOctagon,
      name: t(tkEnemyOctagonName),
      description: t(tkEnemyOctagonDesc),

      baseHP: 10.0,
      baseRadius: 12.0,
      contactDamage: 4,
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
        fireRate: 0.5,        # Very frequent shots (was 0.4: tuned for the old
                              # sparse waves, it carpeted the screen in swarms)
        bulletSpeed: 120.0,   # Slow projectiles
        bulletCount: 1,       # Single shot
        spreadAngle: 0.8,     # High inaccuracy (random ±0.4 radians)
        damage: 5.0,
        usesBurst: false,
        burstCount: 0,
        burstDelay: 0.0,
        homingStrength: 0.0,
        isPentagonBullet: false,
        bulletCountMin: 0,
        bulletCountMax: 0,
        randomizeBulletCount: false,
        inaccuracyAmount: 0.45,  # Reduced inaccuracy - shots land more often
        bulletRadius: 0.0,
        # ~450px of travel: over twice the 200px Octagons hold from the player,
        # so every aimed shot still arrives, but misses fade out instead of
        # drifting across the whole arena at this crawl for the default 4s.
        bulletLifetime: 3.0
      ),

      hasSpecialBehavior: false,
      requiresScreenEntry: true,
      trailEffect: false,
      glowEffect: true,       # Constant firing glow
      usesHitCount: false,
      speedScaling: 3.0
    )

  of etTrickster:  # False warning, real attack elsewhere
    result = EnemyConfig(
      enemyType: etTrickster,
      name: t(tkEnemyTricksterName),
      description: t(tkEnemyTricksterDesc),

      baseHP: 15.0,
      baseRadius: 13.0,
      contactDamage: 4,
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
        damage: 7.5,
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
      usesHitCount: false,
      speedScaling: 5.0
    )

  of etPhantom:  # Unpredictable teleporter with fake clones
    result = EnemyConfig(
      enemyType: etPhantom,
      name: t(tkEnemyPhantomName),
      description: t(tkEnemyPhantomDesc),

      baseHP: 15.0,
      baseRadius: 11.0,
      contactDamage: 4,
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
        damage: 5.0,
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
      usesHitCount: false,
      speedScaling: 6.0
    )

  of etSniper:  # Rare one-shot enemy with epic charging attack
    result = EnemyConfig(
      enemyType: etSniper,
      name: t(tkEnemySniperName),
      description: t(tkEnemySniperDesc),

      baseHP: 15.0,
      baseRadius: 10.0,
      contactDamage: 5,
      baseColor: Color(r: 220, g: 0, b: 0, a: 255),  # Glowing red

      movement: EnemyMovementConfig(
        baseSpeed: 40.0,      # Very slow
        dashSpeed: 0.0,
        dashCooldown: 0.0,
        dashDuration: 0.0,
        teleportCooldown: 0.0,
        teleportRange: 0.0,
        maintainsDistance: true,
        optimalDistance: 500.0,  # Much further away (was 300)
        retreatDistance: 400.0   # Retreat if player gets close (was 225)
      ),

      hasRangedAttack: true,
      attack: EnemyAttackConfig(
        fireRate: 0.0,        # Controlled by charge mechanic
        bulletSpeed: 450.0,   # Slightly faster for long range (was 400)
        bulletCount: 1,
        spreadAngle: 0.0,
        damage: 9999.9,       # One-shot kill
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
      specialData: "charge_time:3.0|trigger_range:500|cooldown:2.0|color_shift",  # Trigger range increased to 500 (was 300)

      requiresScreenEntry: true,
      trailEffect: false,
      glowEffect: true,       # Charging rings
      usesHitCount: false,
      speedScaling: 2.0
    )

  of etMage:  # Summons meteorites and shoots homing magic bullets
    result = EnemyConfig(
      enemyType: etMage,
      name: t(tkEnemyMageName),
      description: t(tkEnemyMageDesc),

      baseHP: 20.0,
      baseRadius: 12.0,
      contactDamage: 5,
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
        damage: 10.0,
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
      usesHitCount: false,
      speedScaling: 3.0
    )

  # ---- Survival horde (the flood) ----------------------------------------
  # Built for 100+ bodies on screen: cheap, readable, and almost no bullets
  # (fire rate is not density-rebated, so only the Watchdog shoots).
  of etThread:
    result = modeMelee(etThread, t(tkEnemyThreadName), t(tkEnemyThreadDesc),
                       0.8, 7.0, 2.0, Color(r: 90, g: 220, b: 255, a: 255), 118.0, 8.0)
  of etForkBomb:
    result = modeMelee(etForkBomb, t(tkEnemyForkBombName), t(tkEnemyForkBombDesc),
                       2.6, 12.0, 2.0, Color(r: 255, g: 120, b: 200, a: 255), 72.0, 5.0)
  of etWatchdog:
    result = modeRanged(etWatchdog, t(tkEnemyWatchdogName), t(tkEnemyWatchdogDesc),
                        2.5, 11.0, 2.0, Color(r: 255, g: 200, b: 80, a: 255), 62.0, 3.0,
                        280.0, 200.0, modeFan(3.0, 210.0, 3, 0.36, 2.0))
  of etZombie:
    result = modeMelee(etZombie, t(tkEnemyZombieName), t(tkEnemyZombieDesc),
                       4.5, 13.0, 3.0, Color(r: 150, g: 180, b: 110, a: 255), 46.0, 3.0)
  of etDeadlock:
    result = modeMelee(etDeadlock, t(tkEnemyDeadlockName), t(tkEnemyDeadlockDesc),
                       2.0, 10.0, 2.0, Color(r: 255, g: 80, b: 90, a: 255), 88.0, 6.0)
  of etDaemon:
    result = modeMelee(etDaemon, t(tkEnemyDaemonName), t(tkEnemyDaemonDesc),
                       3.0, 11.0, 1.0, Color(r: 190, g: 120, b: 255, a: 255), 58.0, 3.0)
    result.movement.maintainsDistance = true
    result.movement.optimalDistance = 320.0
    result.movement.retreatDistance = 240.0
  of etInterrupt:
    result = modeMelee(etInterrupt, t(tkEnemyInterruptName), t(tkEnemyInterruptDesc),
                       1.4, 10.0, 2.0, Color(r: 255, g: 150, b: 40, a: 255), 92.0, 6.0)
    result.hasSpecialBehavior = true
    result.specialBehaviorType = "kamikaze"

  # ---- Roguelite rooms (legacy processes) ---------------------------------
  # Written for sector 1 (tuneDungeonEnemyStats barely touches them) and
  # room play: cover, walls and obstacles are part of every behaviour.
  of etFragment:
    result = modeMelee(etFragment, t(tkEnemyFragmentName), t(tkEnemyFragmentDesc),
                       1.2, 8.0, 2.0, Color(r: 200, g: 205, b: 215, a: 255), 240.0, 8.0)
  of etPortGuard:
    result = modeMelee(etPortGuard, t(tkEnemyPortGuardName), t(tkEnemyPortGuardDesc),
                       3.5, 13.0, 2.0, Color(r: 255, g: 130, b: 60, a: 255), 55.0, 3.0)
  of etSentry:
    result = modeRanged(etSentry, t(tkEnemySentryName), t(tkEnemySentryDesc),
                        2.6, 12.0, 2.0, Color(r: 120, g: 200, b: 120, a: 255), 70.0, 3.0,
                        300.0, 160.0, modeFan(2.4, 200.0, 3, 0.30, 2.0, 3.2))
  of etMimic:
    result = modeMelee(etMimic, t(tkEnemyMimicName), t(tkEnemyMimicDesc),
                       3.0, 12.0, 3.0, Color(r: 235, g: 225, b: 180, a: 255), 125.0, 5.0)
  of etRestorer:
    result = modeMelee(etRestorer, t(tkEnemyRestorerName), t(tkEnemyRestorerDesc),
                       2.8, 11.0, 1.0, Color(r: 110, g: 235, b: 160, a: 255), 62.0, 3.0)
    result.movement.maintainsDistance = true
    result.movement.optimalDistance = 260.0
    result.movement.retreatDistance = 180.0
  of etPacket:
    result = modeMelee(etPacket, t(tkEnemyPacketName), t(tkEnemyPacketDesc),
                       1.6, 9.0, 2.0, Color(r: 0, g: 220, b: 255, a: 255), 60.0, 4.0)
    result.movement.dashSpeed = 430.0
  of etDriver:
    result = modeMelee(etDriver, t(tkEnemyDriverName), t(tkEnemyDriverDesc),
                       6.0, 15.0, 3.0, Color(r: 160, g: 110, b: 255, a: 255), 50.0, 3.0)
    result.movement.dashSpeed = 420.0
  of etCorruptor:
    result = modeMelee(etCorruptor, t(tkEnemyCorruptorName), t(tkEnemyCorruptorDesc),
                       3.0, 11.0, 2.0, Color(r: 255, g: 80, b: 200, a: 255), 66.0, 4.0)
    result.movement.maintainsDistance = true
    result.movement.optimalDistance = 200.0
    result.movement.retreatDistance = 120.0

  of etEnvironment:  # Non-combat entity, no movement, no attack
    result = EnemyConfig(
      enemyType: etEnvironment,
      name: "Environment",
      description: "Environmental object",

      baseHP: 0.0,
      baseRadius: 0.0,
      contactDamage: 0,
      baseColor: Gray,

      movement: EnemyMovementConfig(
        baseSpeed: 0.0,
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
      usesHitCount: false,
      speedScaling: 0.0
    )

# HELPER FUNCTIONS

proc getScaledEnemyStats*(config: EnemyConfig, difficulty: float32): tuple[hp: float32, radius: float32, speed: float32, requiredHits: int] =
  ## Calculate scaled stats based on difficulty (wave number).
  ## Speed scaling is driven by config.speedScaling, set it in getEnemyConfig.
  # Wave-mode midgame was spiking too hard, so regular HP now ramps more gently.
  let strengthMultiplier = pow(1.15, difficulty)  # ~15% more HP per difficulty unit

  let hp = config.baseHP * strengthMultiplier
  let radius = config.baseRadius + difficulty * 1.5 + rand(5).float32
  let speed = config.movement.baseSpeed + difficulty * config.speedScaling

  let requiredHits = if config.usesHitCount:
    config.baseRequiredHits + (difficulty * 1.5).int
  else:
    0

  return (hp: hp, radius: radius, speed: speed, requiredHits: requiredHits)
