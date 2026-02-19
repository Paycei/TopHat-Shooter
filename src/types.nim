import raylib, std/tables, discord_presence, particle_types

export Particle, ParticlePool, Vector2f
export newVector2f, `+`, `-`, `*`, length, normalize, distance

type
  GameState* = enum
    gsSplash, gsMenu, gsPlaying, gsPaused, gsShop, gsGameOver, gsCountdown, gsWaveCleared, gsPowerUpSelect, gsRunStats, gsPvPPlaying, gs3DBoss

  GameMode* = enum
    gmWaveBased,
    gmTimeSurvival,
    gmSandbox,
    gmPvP

  PvPTeam* = enum
    ptNone,      # No team (free-for-all)
    ptRed,       # Red team
    ptBlue,      # Blue team
    ptGreen,     # Green team (for 3 teams)
    ptYellow,    # Yellow team (for 4 teams)
    ptOrange,    # Orange team (for 5 teams)
    ptPurple     # Purple team (for 6 teams)

  PvPConfig* = object
    ## Host-configurable PvP game settings sent to all clients at game start
    startHp*: float32       ## Starting HP per player (default 3)
    startSpeed*: float32    ## Base movement speed (default 200)
    startDamage*: float32   ## Bullet damage per hit (default 1.0)
    fireRate*: float32      ## Seconds between shots – lower is faster (default 0.375)
    bulletSpeed*: float32   ## Bullet travel speed (default 425)
    bulletRadius*: float32  ## Bullet hitbox/visual radius (default 7.5)
    startCoins*: int        ## Coins at match start (default 100)
    startWalls*: int        ## Walls at match start (default 3)
    killLimit*: int         ## Kills needed to win (default 5)
    respawnTime*: float32   ## Seconds before respawn (default 3.0)
    timeLimit*: float32     ## Match time limit in seconds; 0 = unlimited (default 180)
    snapshotRate*: float32  ## Seconds between server→client state snapshots
    inputRate*: float32     ## Seconds between client→server input packets

  EnemyType* = enum
    etCircle,      # Normal chasers
    etCube,        # Stationary/slow shooters
    etTriangle,    # Fast dash attackers
    etStar,        # High HP, needs many hits, dashes when close
    etHexagon,     # Teleporting chaos enemy
    etCross,       # Shows visual warning before cross-shaped attack
    etDiamond,     # Shoots slow projectiles while dashing
    etOctagon,     # Ranged - many slow inaccurate projectiles
    etPentagon,    # Ranged - single fast bullet, low fire rate
    etTrickster,   # Shows false warning, attacks differently
    etPhantom,     # Unpredictable - teleports with fake clones
    etSniper,      # Rare - charges one-shot epic attack with warning
    etMage         # Summons meteorites and shoots homing magic bullets

  EliteType* = enum
    etNone,        # Not elite
    etSwift,       # 50% faster movement and attack speed
    etTank,        # 3x HP, 50% damage reduction
    etVenomous,    # Poisons player on contact
    etExplosive,   # Explodes on death, damaging player
    etRegenerative,# Slowly regenerates HP over time
    etShielded     # Has a damage-absorbing shield

  ConsumableType* = enum
    ctHealth,
    ctCoin,
    ctSpeed,
    ctInvincibility,
    ctFireRate,
    ctMagnet,
    ctShieldBoost,      # Temporary shield (absorbs hits)
    ctDoubleCoin,       # 2x coin value for duration
    ctDamageBoost,      # Increased damage
    ctLifesteal         # Heal on kill

  PowerUpType* = enum
    puDoubleShot,      # Shoots 2 bullets at once
    puRotatingShield,  # Orbiting protective shield
    puMagicalBullets,  # Bullets track enemies
    puPiercingShots,   # Bullets pass through enemies
    puMultiShot,       # Shoots in 3 directions
    puExplosiveBullets,# Bullets explode on impact
    puLifeSteal,       # Gain HP from kills
    puRapidFire,       # Increased fire rate
    puMaxHealth,       # Increase max HP
    puSpeedBoost,      # Permanent speed increase
    puBulletSpeed,     # Faster bullets
    puLuckyCoins,      # Doubles coins collected
    puWallMaster,      # Place stronger walls and increment turret damage
    puAutoShoot,       # Auto-target nearest enemy
    puRegeneration,    # Slowly restore HP
    puDodgeChance,     # Chance to evade damage
    puCriticalHit,     # Random critical damage
    puBloodBullets,    # Lifesteal on hit
    puBulletRicochet,  # Bullets ricochet off enemies
    puSlowField,       # Enemies move slower nearby
    puRage,            # Damage increases at low HP
    puBerserker,       # Attack speed at low HP
    puThorns,          # Reflect damage to attackers
    puBulletSplit,     # Bullets split on impact
    puChainLightning,  # Damage chains between enemies
    puFrostShots,      # Bullets slow enemies
    puPoisonShot,      # Poison bullets that apply DoT effect
    puFireBullets,     # Bullets apply fire damage over time
    puWindBullets,     # Bullets push enemies backwards
    puFireAura,        # Fire damage over time aura
    puLightningAura,   # Lightning damage that chains between enemies
    puPoisonAura,      # Poison damage over time aura (lower damage, longer duration)
    puWindAura,        # Pushes enemies away from player
    puTimeWarp,        # Slow down time globally
    puGravityWell,     # Pull enemies toward you
    puPhaseShift,      # Teleport dash through enemies
    puOvercharge,      # Bullets gain power over distance
    puEchoShots,       # Bullets leave damaging trails
    puRotatingOrbs,    # Rotating elemental orbs around player (LEGENDARY - all elements)
    puPoisonOrb,       # Poison elemental orb
    puFireOrb,         # Fire elemental orb
    puLightningOrb,    # Lightning elemental orb
    puWindOrb,         # Wind elemental orb
    puFrostOrb,        # Frost elemental orb
    puArcaneOrb,       # Arcane elemental orb
    puArcaneBullets,   # Arcane bullet version - enhanced damage
    puArcaneAura,      # Arcane aura version - enhanced damage
    puFireMastery,     # LEGENDARY: Enhance all fire effects (damage, duration, slow)
    puPoisonMastery,   # LEGENDARY: Enhance all poison effects (damage, duration, slow)
    puFrostMastery,    # LEGENDARY: Enhance all frost effects (damage, duration, slow)
    puArcaneMastery,   # LEGENDARY: Enhance all arcane effects (damage, priecing)
    puLightningMastery,# LEGENDARY: Enhance all lightning effects (damage, duration, slow)
    puWindMastery,     # LEGENDARY: Enhance all wind effects (damage, duration, slow)
    puParry,           # LEGENDARY: Active ability - invincible + bounce bullets
    puBloodOrb,        # Blood elemental orb
    puBloodAura,       # Blood damage aura with lifesteal
    puBloodMastery,    # LEGENDARY: Enhance all blood effects (damage, lifesteal)
    puRadialBurst,     # Shoots a circle of bullets periodically
    puWallTurrets,     # LEGENDARY: Walls become turrets that shoot enemies
    puPulseArmor,      # When you take damage, emit shockwave that pushes enemies back
    puHeavyRounds,     # Larger bullets with knockback
    puFortified,       # Reduce damage taken
    puSpecialRounds,   # Every Nth bullet has special on-hit effect
    puGiantSlayer      # Deal % of enemy HP as bonus damage

  PowerUpRarity* = enum
    prCommon,
    prLegendary

  PowerUp* = object
    powerType*: PowerUpType
    level*: int  # 1, 2, or 3
    rarity*: PowerUpRarity  # Common or Legendary

  AttackWarning* = ref object
    pos*: Vector2f
    attackType*: string  # "cross", "burst", "fake", "boss_laser", "satellite_laser", "teleport_warning"
    lifetime*: float32
    maxLifetime*: float32
    sourceEnemyId*: int          # ID of enemy that created this warning (for tracking movement)
    laserAngles*: seq[float32]   # Angles for each laser beam
    laserLength*: float32        # Length of laser beams
    laserCount*: int             # Number of laser beams
    laserDamage*: int            # Damage of lasers when fired
    laserDuration*: float32      # How long lasers stay active
    lasersCreated*: bool         # Flag to track if lasers were already created
    laserPattern*: string        # Pattern type: "cross_laser", "rotating_grid", "prismatic_cage"
    enemyType*: EnemyType        # Type of enemy creating this attack
    targetPos*: Vector2f         # Target coordinates for satellite laser
    fromSatellite*: bool         # Flag for satellite laser warnings
    # Teleport bullet data (for delayed bullet spawning)
    bulletCount*: int            # Number of bullets to spawn
    bulletSpeed*: float32        # Speed of bullets
    bulletDamage*: float32       # Damage of bullets
    bulletSpreadAngle*: float32  # Spread angle for bullets
    bulletsCreated*: bool        # Flag to track if bullets were spawned
    isBossTeleportTarget*: bool  # True if boss should teleport to this position

  ElementType* = enum
    etPoison,      # Green - poison damage over time
    etFire,        # Red/Orange - fire damage over time
    etLightning,   # Yellow/Blue - instant damage + chain
    etWind,        # Cyan - knockback
    etFrost,       # Light blue - slow effect
    etArcane,      # Purple - enhanced damage + magical effect
    etBlood,       # Dark red - damage + lifesteal
    etNone         # No element (shouldn't happen)

  RotatingOrb* = ref object
    angle*: float32                    # Current angle around player
    radius*: float32                   # Distance from player
    elementType*: ElementType          # Which element this orb has
    orbLevel*: int                     # 1-3 = elemental level, 4 = legendary tier
    hitEnemies*: seq[int]              # Track which enemies were hit (by index)
    lastHitTime*: Table[int, float32]  # Track when each enemy was last hit

  Player* = ref object
    pos*: Vector2f
    vel*: Vector2f
    radius*: float32
    baseRadius*: float32
    hp*: float32
    maxHp*: float32
    speed*: float32
    baseSpeed*: float32
    damage*: float32
    bulletDamageMult*: float32  # Multiplier applied only to bullet damage (e.g. Arcane Bullets)
    fireRate*: float32
    bulletSpeed*: float32
    lastShot*: float32
    coins*: int
    kills*: int
    walls*: int
    speedBoostTimer*: float32
    invincibilityTimer*: float32
    fireRateBoostTimer*: float32
    magnetTimer*: float32
    shieldBoostTimer*: float32     # Shield boost duration
    doubleCoinTimer*: float32      # Double coin duration
    damageBoostTimer*: float32     # Damage boost duration
    lifestealTimer*: float32       # Lifesteal duration
    shieldHits*: int               # Remaining shield absorptions
    powerUps*: seq[PowerUp]
    shieldAngle*: float32
    shieldHealths*: seq[float32]  # Health of each shield segment
    shieldMaxHealth*: float32     # Maximum health per shield
    shieldRegenTimers*: seq[float32]  # Regen timer for each shield
    shieldRegenDelay*: float32    # Time before shield starts regenerating
    killsSinceLastHeal*: int
    regenTimer*: float32
    lastDamageTaken*: float32
    rageStacks*: int
    critCharge*: float32
    autoShootEnabled*: bool
    auraRadius*: float32  # Invisible coin collection aura
    doubleShotDelay*: float32  # Timer for double-shot rapid succession
    bulletCounter*: int  # Counter for special rounds powerup
    timeWarpCooldown*: float32
    timeWarpActive*: bool
    timeWarpDuration*: float32
    timeWarpUsesThisWave*: int  # Track uses per wave
    timeWarpMaxUsesPerWave*: int  # Fixed at 2 uses per wave (single-level legendary)
    phaseShiftCooldown*: float32
    phaseShiftInvulnTimer*: float32
    lastPhaseShiftPos*: Vector2f
    rotatingOrbs*: seq[RotatingOrb]
    orbRotationAngle*: float32  # Base rotation angle for all orbs
    hasFireMastery*: bool
    hasPoisonMastery*: bool
    hasFrostMastery*: bool
    hasArcaneMastery*: bool
    hasLightningMastery*: bool
    hasWindMastery*: bool
    hasBloodMastery*: bool
    poisonTimer*: float32
    poisonDamage*: float32
    poisonAccumulator*: float32  # Accumulates fractional poison damage until it reaches 1.0
    parryActive*: bool  # True when actively parrying
    parryCooldown*: float32  # Cooldown timer between parries
    parryDuration*: float32  # How long the parry state lasts
    radialBurstTimer*: float32  # Timer for periodic radial burst
    pulseArmorCooldown*: float32  # Cooldown after triggering shockwave
    teamId*: PvPTeam  # Team assignment for PvP mode (ptNone for free-for-all)
    skinType*: int  # Current equipped skinHost
    bulletSkinType*: int  # Current equipped bullet skin
    bulletShapeType*: int  # Current equipped bullet shape (BulletShapeType ord)
    shapeType*: int  # Current equipped player shape
    particleSkinType*: int  # Current equipped particle effect

  EffectInstance* = object
    elementType*: ElementType
    damagePerSec*: float32
    remainingDuration*: float32
    maxDuration*: float32
    isActive*: bool
    source*: string

  ActiveEffect* = object
    primary*: EffectInstance
    fallback*: EffectInstance

  OrbitalSatellite* = object
    pos*: Vector2f
    angle*: float32
    radius*: float32
    rotationSpeed*: float32  # Speed of orbital rotation
    hp*: int
    shootTimer*: float32
    owner*: int  # Enemy ID
    laserActive*: bool
    laserTarget*: Vector2f  # Current player coordinates to target
    laserChargeTime*: float32  # Time to charge before firing

  Enemy* = ref object
    id*: int                      # Unique identifier for tracking bullet hits
    pos*: Vector2f
    vel*: Vector2f
    radius*: float32              # Combat hitbox (visual size, used for bullets/player collision)
    collisionRadius*: float32     # Enemy-to-enemy collision hitbox
    hp*: float32
    maxHp*: float32
    speed*: float32
    contactDamage*: int       # Damage dealt on contact/collision
    rangedDamage*: int        # Damage dealt by bullets/projectiles
    color*: Color
    enemyType*: EnemyType
    isBoss*: bool
    shootTimer*: float32
    spawnTimer*: float32
    dashTimer*: float32
    hitCount*: int
    requiredHits*: int
    lastContactDamageTime*: float32
    teleportTimer*: float32
    shockwaveTimer*: float32
    burstTimer*: float32
    lastWallDamageTime*: float32
    hexTeleportTimer*: float32
    entranceTimer*: float32
    startPos*: Vector2f            # Position at start of entrance animation
    targetPos*: Vector2f
    slowTimer*: float32
    entranceWait*: float32        # Brief wait after arrival before boss begins attacking
    slowAmount*: float32
    activeEffects*: Table[ElementType, ActiveEffect]  # Unified effect system
    chainLightningCooldown*: float32

    attackWarningTimer*: float32
    attackExecuteTimer*: float32
    attackPhase*: int  # 0=patrol, 1=warning, 2=execute
    dashCooldown*: float32
    fakeWarningTimer*: float32
    clonePositions*: seq[Vector2f]
    cloneTimer*: float32
    hasEnteredScreen*: bool  # Tracks if ranged enemy is fully inside screen
    isElite*: bool  # Whether this is an elite enemy
    eliteType*: EliteType  # Type of elite modifier
    eliteTypes*: seq[EliteType]  # Multiple elite types for high-wave elites
    eliteAuraPhase*: float32  # For animating the elite aura
    shieldHp*: float32  # For shielded elites
    maxShieldHp*: float32  # Maximum shield HP
    regenTimer*: float32  # For regenerative elites
    spawnedByBoss*: bool  # True if spawned by boss summon attack
    rotation*: float32  # Current rotation angle in radians
    bossDefinitionID*: int  # Which boss definition this uses
    currentPhaseIndex*: int  # Current phase index
    attackTimers*: seq[float32]  # Individual cooldown timer for each attack in current phase
    defenseMultiplier*: float32  # Damage reduction multiplier
    debuffResistance*: float32  # Stun/slow resistance multiplier
    isDashing*: bool  # Whether boss is currently executing a dash
    dashVelocity*: Vector2f  # Velocity during dash
    dashDuration*: float32  # Remaining dash duration
    dashMaxDuration*: float32  # Total dash duration for this attack
    satellites*: seq[OrbitalSatellite]  # Persistent satellites that can be destroyed
    invulnerabilityTimer*: float32  # Brief invulnerability during phase transitions
    auraDamageAccumulator*: float32  # Accumulates aura damage over time
    lastAuraDamageNumberTime*: float32  # Last time a damage number was shown for auras
    auraDamageHadCrit*: bool  # Track if any crit occurred during accumulation period
    lastAuraDamageType*: DamageType  # Track the damage type of accumulated aura damage
    contactDamageAccumulator*: float32  # Accumulates contact damage over time
    lastContactDamageNumberTime*: float32  # Last time a damage number was shown for contact

  Bullet* = ref object
    pos*: Vector2f
    vel*: Vector2f
    radius*: float32
    damage*: float32
    fromPlayer*: bool
    lifetime*: float32
    isHoming*: bool
    isPiercing*: bool
    isExplosive*: bool
    piercedEnemies*: int
    bounceCount*: int
    hasSplit*: bool
    slowAmount*: float32
    poisonDuration*: float32
    fireDuration*: float32  # Duration of fire effect applied on hit
    windPushForce*: float32  # Force to push enemies backwards
    isPentagon*: bool  # Special pentagon-shaped bullets
    hitEnemies*: seq[int]  # Track enemy indices already hit by this bullet
    sourceEnemyId*: int  # ID of the enemy that shot this bullet
    sourceEnemyPos*: Vector2f  # Position where the bullet was shot from
    sourceEnemyType*: EnemyType  # Type of enemy that shot this bullet
    travelDistance*: float32  # Track distance
    isEcho*: bool  # True if this is an echo clone bullet
    echoTrailTimer*: float32  # Timer for spawning echo clones
    particleTrailTimer*: float32  # Accumulator for explosive bullet trail particles
    parentBulletId*: int  # ID of parent bullet
    bulletId*: int  # Unique ID for this bullet
    isBossBullet*: bool  # True if this bullet was fired by a boss
    bossBulletShape*: int  # Boss bullet shape: 0=circle,1=diamond,2=triangle,3=star,4=cross,5=square
    bulletShape*: int  # Player cosmetic bullet shape (BulletShapeType ord)
    isArcaneBullet*: bool  # True if this bullet is from arcane bullet power-up
    isBonusFromMultiShot*: bool  # True if this is a bonus bullet from Multi-Shot
    isBonusFromDoubleShot*: bool  # True if this is a bonus bullet from Double Shot
    wasCrit*: bool  # True if this bullet rolled a critical hit
    isSpecialRound*: bool  # True if this is a special round (every Nth bullet)
    bulletSkin*: int  # Bullet skin typeHost
    ownerPlayerIndex*: int  # For PvP: which player shot this bullet (-1 for non-PvP)

  Coin* = ref object
    pos*: Vector2f
    radius*: float32
    value*: int
    lifetime*: float32
    isBossCoin*: bool  # Special coin from boss that must be collected to end wave

  Consumable* = ref object
    pos*: Vector2f
    radius*: float32
    consumableType*: ConsumableType
    lifetime*: float32

  Wall* = ref object
    pos*: Vector2f
    radius*: float32
    hp*: float32
    maxHp*: float32
    duration*: float32
    shootTimer*: float32  # Timer for turret shooting (puWallTurrets)

  DamageType* = enum
    dtDefault,      # White - regular contact damage
    dtFire,         # Red/Orange - fire damage
    dtPoison,       # Green - poison damage
    dtFrost,        # Light blue - frost/slow damage
    dtLaser,        # Blue/indigo - laser damage
    dtLightning,    # Yellow - lightning damage
    dtArcane,       # Purple - arcane damage
    dtExplosion,    # Orange - explosion damage
    dtCritical,     # Yellow - critical hits (from player)
    dtHeal          # Green - healing (positive numbers)

  DamageNumber* = ref object
    pos*: Vector2f          # Current position
    vel*: Vector2f          # Velocity (moves upward and fades)
    damage*: float32        # Amount of damage to display
    lifetime*: float32      # How long the number has existed
    maxLifetime*: float32   # Total duration before disappearing
    fromPlayer*: bool       # True if player dealt damage, false if enemy dealt damage
    isCritical*: bool       # True for critical hits (larger, different color)
    damageType*: DamageType # Type of damage for color coding

  Laser* = ref object
    pos*: Vector2f          # Center position
    direction*: int         # 0=horizontal, 1=vertical, 2=both (cross)
    length*: float32        # How far the laser extends
    thickness*: float32     # Width of the laser beam
    damage*: int            # Damage dealt
    lifetime*: float32      # How long the laser stays
    maxLifetime*: float32   # Original duration
    hasHitPlayer*: bool     # Track if already damaged player this laser
    rotation*: float32      # Rotation angle in radians (for rotating lasers)
    enemyType*: EnemyType   # Type of enemy that created this laser

  Meteorite* = ref object
    pos*: Vector2f          # Current position
    targetPos*: Vector2f    # Where it will land
    vel*: Vector2f          # Velocity (falling)
    radius*: float32        # Size of meteorite
    damage*: int            # Damage on impact
    warningTimer*: float32  # Time before impact
    maxWarningTime*: float32 # Total warning duration

  ShopItem* = object
    name*: string
    description*: string
    baseCost*: int
    bought*: int

  DataPacket* = object
    x*, y*: float32
    speed*: float32
    alpha*: uint8
    
  CircuitLine* = object
    y*: float32
    speed*: float32
    pulseOffset*: float32
    
  OSBackgroundState* = object
    dataPackets*: seq[DataPacket]
    circuitLines*: seq[CircuitLine]
    gridPulseTime*: float32
    alertLevel*: float32  # 0.0 = normal, 1.0 = critical

  NotificationType* = enum
    ntInfo,     # [INFO] messages
    ntWarning,  # [WARN] messages
    ntError,    # [ERR] messages
    ntCritical  # [CRITICAL] messages
    
  OSNotification* = object
    message*: string
    notifType*: NotificationType
    lifetime*: float32
    fadeTime*: float32
    
  OSHUDState* = object
    notifications*: seq[OSNotification]
    panelPulse*: float32
    minimized*: bool
  
  TaskManagerTab* = enum
    tmtProcesses,    # Active power-ups
    tmtPerformance,  # Stats and metrics
    tmtSettings      # Game settings access

  BossWaveManager* = object
    active*: bool        # True when a boss is currently spawned
    coinActive*: bool    # True when boss coin needs to be collected

  ScreenShake* = object
    offset*: Vector2f
    intensity*: float32
    duration*: float32
    maxDuration*: float32
    decayRate*: float32
    tintColor*: Color

  StreakLevel* = enum
    slNone, slSpree, slRampage, slUnstoppable, slGodlike

  KillStreak* = object
    kills*: int
    timer*: float32
    level*: StreakLevel
    lastLevelUpTime*: float32
    displayTimer*: float32

  ComboSystem* = object
    killCount*: int
    lastKillTime*: float32
    comboWindow*: float32
    displayTimer*: float32
    bonusCoins*: int
    # Perfect wave tracking (independent of combo)
    waveKillCount*: int           # Kills made this wave (excluding boss minions)
    waveComboBreaks*: int         # Number of times combo broke this wave
    perfectWaveStreak*: int       # Number of consecutive perfect waves
    lastPerfectWaveBonus*: int    # Last bonus earned for display

  MilestoneType* = enum
    mtWave, mtKills, mtCoins, mtPerfectWave, mtCloseCall, mtClutch

  Milestone* = object
    milestoneType*: MilestoneType
    threshold*: int
    reached*: bool
    displayTimer*: float32
    name*: string
    description*: string
    bonus*: string

  MilestoneManager* = object
    milestones*: seq[Milestone]
    recentMilestone*: Milestone
    showRecent*: bool

  MicroReward* = object
    message*: string
    coins*: int
    displayTimer*: float32
    pos*: Vector2f

  MicroRewardTracker* = object
    lastKills*: int
    lastDamageDealt*: float32
    rewards*: seq[MicroReward]

  SlowMotionType* = enum
    smtNone, smtKill, smtBossKill, smtPowerUp, smtWaveComplete

  SlowMotion* = object
    active*: bool
    timeScale*: float32
    duration*: float32
    maxDuration*: float32
    slowType*: SlowMotionType

  WaveStats* = object
    waveNumber*: int
    kills*: int
    accuracy*: float32
    topDamage*: float32
    survivalTime*: float32
    coinsEarned*: int
    damageTaken*: float32
    shotsFired*: int
    shotsHit*: int
    isPerfect*: bool
    maxCombo*: int

  CloseCall* = object
    detected*: bool
    displayTimer*: float32
    count*: int

  WaveCelebration* = object
    active*: bool
    animationTimer*: float32
    maxAnimationTime*: float32
    waveNumber*: int
    stats*: WaveStats
    showStats*: bool
    statsRevealTimer*: float32

  BossIntroduction* = object
    active*: bool
    timer*: float32
    maxTime*: float32
    bossName*: string
    bossTitle*: string
    bossHp*: float32
    phase*: int

  Achievement* = object
    id*: string
    name*: string
    description*: string
    icon*: string
    unlocked*: bool
    justUnlocked*: bool
    displayTimer*: float32

  AchievementManager* = object
    achievements*: seq[Achievement]
    recentAchievement*: Achievement
    showRecent*: bool

  RealTimeStats* = object
    dps*: float32
    damageDealt*: float32
    lastDamageTime*: float32
    kills*: int
    coinsPerMinute*: float32
    totalCoins*: int
    lastCoinTime*: float32
    powerLevel*: int
    damageHistory*: seq[(float32, float32)]  # (timestamp, damage) for rolling window

  DopamineState* = object
    screenShake*: ScreenShake
    comboSystem*: ComboSystem
    milestones*: MilestoneManager
    microRewards*: MicroRewardTracker
    slowMotion*: SlowMotion
    waveStats*: WaveStats
    currentTime*: float32
    waveCelebration*: WaveCelebration
    bossIntro*: BossIntroduction
    achievements*: AchievementManager
    realTimeStats*: RealTimeStats

  Game* = ref object
    state*: GameState
    mode*: GameMode
    player*: Player
    enemies*: seq[Enemy]
    bullets*: seq[Bullet]
    bulletIdCounter*: int  # Counter for generating unique bullet IDs
    coins*: seq[Coin]
    consumables*: seq[Consumable]
    walls*: seq[Wall]
    particlePool*: ParticlePool
    attackWarnings*: seq[AttackWarning]
    lasers*: seq[Laser]
    meteorites*: seq[Meteorite]
    damageNumbers*: seq[DamageNumber]
    time*: float32
    frameCount*: int  # Frame counter for satellite optimizations
    spawnTimer*: float32
    bossTimer*: float32
    bossCount*: int
    difficulty*: float32
    screenWidth*: int32
    screenHeight*: int32
    shopItems*: array[6, ShopItem]
    selectedShopItem*: int
    menuSelection*: int
    countdownTimer*: float32
    waveClearedTimer*: float32  # Timer for wave cleared transition
    powerUpChoices*: array[3, PowerUp]
    selectedPowerUp*: int
    rollAnimationActive*: bool
    rollAnimationTimer*: float32
    rollSpeed*: array[3, float32]  # Individual roll speeds for each slot
    rollPosition*: array[3, float32]  # Current scroll position for each slot
    rollPowerUpList*: array[3, seq[PowerUp]]  # List of power-ups scrolling in each slot
    canSelectPowerUp*: bool  # Whether player can select (false during animation)
    rerollCost*: int  # Cost of next reroll (increases after each use)
    bossWaveManager*: BossWaveManager  # Centralized boss wave and coin management
    bossSpawnTimer*: float32
    cameFromPowerUpSelect*: bool
    gameOverSoundPlayed*: bool
    currentWave*: int
    wavesUntilBoss*: int
    waveEnemiesRemaining*: int
    waveEnemiesTotal*: int
    waveInProgress*: bool
    waveStartTime*: float32  # Track when current wave started for statistics
    cheatsUsed*: bool  # Set to true if cheat menu opened during run
    lastMousePos*: Vector2f  # Track mouse position to detect movement
    mouseMovedRecently*: bool  # True if mouse has moved since last keyboard input
    keyboardUsedRecently*: bool  # True if keyboard was just used (disables mouse temporarily)
    previousState*: GameState  # Track where we came from to return correctly
    nextEnemyId*: int  # Counter for assigning unique IDs to enemies
    showRunStatsGraphs*: bool  # Toggle for showing graphs in run stats screen
    statsMenuTab*: int  # 0 = Lifetime stats, 1 = Last Run stats
    sandboxSidebarOpen*: bool  # Is the sandbox control sidebar visible
    sandboxTypingBuffer*: string  # Buffer for detecting "ttt" input
    sandboxSelectedTab*: int  # Current tab in sandbox UI (0=Enemies, 1=Bosses, 2=Controls)
    sandboxScrollOffset*: int32  # Scroll position in sidebar
    sandboxGodMode*: bool  # Player invulnerability
    sandboxFreezeEnemies*: bool  # Freeze all enemy movement
    discordClient*: DiscordClient  # Discord Rich Presence client
    osBackground*: OSBackgroundState  # Animated background system
    osHUD*: OSHUDState  # OS-style HUD and notifications
    pauseMenuTab*: TaskManagerTab  # Current tab in pause menu task manager
    selectedGameOverButton*: int  # Selected button on game over screen (0=Restart, 1=Stats, 2=Exit)
    dopamine*: DopamineState  # Dopamine enhancement systems
    game3D*: pointer  # Pointer to Game3D to avoid circular dependency
    transitioning*: bool  # Fade transition active
    fadeAlpha*: float32  # Fade opacity (0.0 to 1.0)

proc newAttackWarning*(x, y: float32, attackType: string, duration: float32, sourceEnemyId: int = -1): AttackWarning =
  AttackWarning(
    pos: newVector2f(x, y),
    attackType: attackType,
    lifetime: duration,
    maxLifetime: duration,
    sourceEnemyId: sourceEnemyId,
    laserAngles: @[],
    laserLength: 0.0,
    laserCount: 0,
    laserDamage: 0,
    laserDuration: 0.0,
    lasersCreated: false,
    targetPos: newVector2f(0, 0),
    fromSatellite: false,
    bulletCount: 0,
    bulletSpeed: 0.0,
    bulletDamage: 0.0,
    bulletSpreadAngle: 0.0,
    bulletsCreated: false,
    isBossTeleportTarget: false
  )

proc newBossLaserWarning*(x, y: float32, duration: float32, angles: seq[float32],
                         length: float32, damage: int, laserDuration: float32,
                         pattern: string = "", enemyType: EnemyType = etCircle,
                         sourceEnemyId: int = -1): AttackWarning =
  ## Creates a warning specifically for boss laser attacks with multiple beams
  AttackWarning(
    pos: newVector2f(x, y),
    attackType: "boss_laser",
    lifetime: duration,
    maxLifetime: duration,
    sourceEnemyId: sourceEnemyId,
    laserAngles: angles,
    laserLength: length,
    laserCount: angles.len,
    laserDamage: damage,
    laserDuration: laserDuration,
    lasersCreated: false,
    laserPattern: pattern,
    enemyType: enemyType,
    bulletCount: 0,
    bulletSpeed: 0.0,
    bulletDamage: 0.0,
    bulletSpreadAngle: 0.0,
    bulletsCreated: false,
    isBossTeleportTarget: false
  )

proc newSatelliteLaserWarning*(satelliteX, satelliteY, targetX, targetY: float32,
                               duration: float32, sourceEnemyId: int = -1): AttackWarning =
  ## Creates a warning for satellite laser attacks that extend through a target point
  AttackWarning(
    pos: newVector2f(satelliteX, satelliteY),
    attackType: "satellite_laser",
    lifetime: duration,
    maxLifetime: duration,
    sourceEnemyId: sourceEnemyId,
    targetPos: newVector2f(targetX, targetY),
    fromSatellite: true,
    laserAngles: @[],
    laserLength: 0.0,
    laserCount: 0,
    laserDamage: 0,
    laserDuration: 0.0,
    lasersCreated: false,
    laserPattern: "",
    enemyType: etCircle,
    bulletCount: 0,
    bulletSpeed: 0.0,
    bulletDamage: 0.0,
    bulletSpreadAngle: 0.0,
    bulletsCreated: false,
    isBossTeleportTarget: false
  )

proc newLaser*(x, y: float32, direction: int, length, thickness: float32, damage: int, duration: float32, rotation: float32 = 0.0, enemyType: EnemyType = etCircle): Laser =
  Laser(
    pos: newVector2f(x, y),
    direction: direction,
    length: length,
    thickness: thickness,
    damage: damage,
    lifetime: duration,
    maxLifetime: duration,
    hasHitPlayer: false,
    rotation: rotation,
    enemyType: enemyType
  )

proc newMeteorite*(targetX, targetY: float32, spawnX, spawnY: float32, damage: int, warningTime: float32): Meteorite =
  ## Create a new meteorite that falls from the sky
  Meteorite(
    pos: newVector2f(spawnX, spawnY),
    targetPos: newVector2f(targetX, targetY),
    vel: newVector2f(0, 0),
    radius: 15.0,
    damage: damage,
    warningTimer: warningTime,
    maxWarningTime: warningTime
  )

proc defaultPvPConfig*(): PvPConfig =
  ## Returns the default/balanced PvP configuration
  PvPConfig(
    startHp: 3.0,
    startSpeed: 200.0,
    startDamage: 1.0,
    fireRate: 0.375,
    bulletSpeed: 425.0,
    bulletRadius: 7.5,
    startCoins: 100,
    startWalls: 3,
    killLimit: 5,
    respawnTime: 3.0,
    timeLimit: 180.0,
    snapshotRate: 1.0 / 32.0,   # 32 ticks (Medium)
    inputRate: 1.0 / 32.0       # match snapshot tick rate
  )
