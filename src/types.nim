import raylib, math, std/tables

type
  GameState* = enum
    gsMenu, gsPlaying, gsPaused, gsShop, gsGameOver, gsHelp, gsCountdown, gsWaveCleared, gsPowerUpSelect, gsSettings, gsStatistics
  
  GameMode* = enum
    gmWaveBased,      # New primary mode: waves → upgrades → boss → legendary
    gmTimeSurvival    # Old mode: time-based survival

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
    etSniper       # Rare - charges one-shot epic attack with warning

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
    ctMagnet

  PowerUpType* = enum
    puDoubleShot,      # Shoots 2 bullets at once
    puRotatingShield,  # Orbiting protective shield
    puDamageZone,      # Passive damage aura
    puMagicalBullets,  # Bullets track enemies
    puPiercingShots,   # Bullets pass through enemies
    puMultiShot,       # Shoots in 3 directions
    puExplosiveBullets,# Bullets explode on impact
    puLifeSteal,       # Gain HP from kills
    puRapidFire,       # Increased fire rate
    puMaxHealth,       # Increase max HP
    puSpeedBoost,      # Permanent speed increase
    puBulletDamage,    # Increased bullet damage
    puBulletSpeed,     # Faster bullets
    puLuckyCoins,      # Doubles coins collected
    puWallMaster,      # Place stronger walls
    puAutoShoot,       # Auto-target nearest enemy
    puBulletSize,      # Larger projectiles
    puRegeneration,    # Slowly restore HP
    puDodgeChance,     # Chance to evade damage
    puCriticalHit,     # Random critical damage
    puVampirism,       # Lifesteal on hit
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
    puArcaneMastery,   # LEGENDARY: Enhance all arcane effects (damage, duration)
    puLightningMastery,# LEGENDARY: Enhance all lightning effects (damage, duration, slow)
    puWindMastery,     # LEGENDARY: Enhance all wind effects (damage, duration, slow)
    puParry            # LEGENDARY: Active ability - invincible + bounce bullets (0.5s, 5s cd)
  
  PowerUpRarity* = enum
    prCommon,          # Normal upgrades after waves
    prLegendary        # Special upgrades after bosses

  PowerUp* = object
    powerType*: PowerUpType
    level*: int  # 1, 2, or 3
    rarity*: PowerUpRarity  # Common or Legendary

  Vector2f* = object
    x*, y*: float32

  AttackWarning* = ref object
    pos*: Vector2f
    attackType*: string  # "cross", "burst", "fake"
    lifetime*: float32
    maxLifetime*: float32

  ElementType* = enum
    etPoison,      # Green - poison damage over time
    etFire,        # Red/Orange - fire damage over time  
    etLightning,   # Yellow/Blue - instant damage + chain
    etWind,        # Cyan - knockback
    etFrost,       # Light blue - slow effect
    etArcane,       # Purple - enhanced damage + magical effect
    etNone         # No element (shouldn't happen)

  RotatingOrb* = ref object
    angle*: float32                    # Current angle around player
    radius*: float32                   # Distance from player
    elementType*: ElementType          # Which element this orb has
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
    powerUps*: seq[PowerUp]
    shieldAngle*: float32
    killsSinceLastHeal*: int
    regenTimer*: float32
    lastDamageTaken*: float32
    rageStacks*: int
    critCharge*: float32
    autoShootEnabled*: bool
    auraRadius*: float32  # Invisible coin collection aura
    doubleShotDelay*: float32  # Timer for double-shot rapid succession
    # New legendary power-up timers and states
    timeWarpCooldown*: float32
    timeWarpActive*: bool
    timeWarpDuration*: float32
    timeWarpUsesThisWave*: int  # Track uses per wave
    timeWarpMaxUsesPerWave*: int  # Depends on level (1, 2, or 3)
    phaseShiftCooldown*: float32
    phaseShiftInvulnTimer*: float32
    lastPhaseShiftPos*: Vector2f
    # Rotating orbs power-up
    rotatingOrbs*: seq[RotatingOrb]
    orbRotationAngle*: float32  # Base rotation angle for all orbs
    # Elemental Mastery power-ups (LEGENDARY - enhance elemental effects)
    hasFireMastery*: bool
    hasPoisonMastery*: bool
    hasFrostMastery*: bool
    hasArcaneMastery*: bool
    hasLightningMastery*: bool
    hasWindMastery*: bool
    # Poison tracking (for venomous elite enemies)
    poisonTimer*: float32
    poisonDamage*: float32
    poisonAccumulator*: float32  # Accumulates fractional poison damage until it reaches 1.0
    # Parry power-up (LEGENDARY - active ability)
    parryActive*: bool  # True when actively parrying
    parryCooldown*: float32  # Cooldown timer between parries
    parryDuration*: float32  # How long the parry state lasts

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

  Enemy* = ref object
    id*: int                      # Unique identifier for tracking bullet hits
    pos*: Vector2f
    vel*: Vector2f
    radius*: float32              # Combat hitbox (visual size, used for bullets/player collision)
    collisionRadius*: float32     # Enemy-to-enemy collision hitbox (~60% of radius)
    hp*: float32
    maxHp*: float32
    speed*: float32
    damage*: int
    color*: Color
    enemyType*: EnemyType
    isBoss*: bool
    isCustomBoss*: bool           # True for custom bosses
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
    # New fields for advanced enemies
    attackWarningTimer*: float32
    attackExecuteTimer*: float32
    attackPhase*: int  # 0=patrol, 1=warning, 2=execute
    dashCooldown*: float32
    fakeWarningTimer*: float32
    clonePositions*: seq[Vector2f]
    cloneTimer*: float32
    # Field for ranged enemy screen restriction
    hasEnteredScreen*: bool  # Tracks if ranged enemy is fully inside screen
    # Elite enemy fields
    isElite*: bool  # Whether this is an elite enemy
    eliteType*: EliteType  # Type of elite modifier (primary type for backward compatibility)
    eliteTypes*: seq[EliteType]  # Multiple elite types for high-wave elites (wave 25+)
    eliteAuraPhase*: float32  # For animating the elite aura
    shieldHp*: float32  # For shielded elites
    maxShieldHp*: float32  # Maximum shield HP
    regenTimer*: float32  # For regenerative elites
    # Cross enemy rotation during dash
    rotation*: float32  # Current rotation angle in radians
    # Custom boss fields (for boss_definitions system)
    bossDefinitionID*: int  # Which boss definition this uses (1-12)
    currentPhaseIndex*: int  # Current phase index (0, 1, 2, etc.)
    attackTimers*: seq[float32]  # Individual cooldown timer for each attack in current phase

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
    sourceEnemyId*: int  # ID of the enemy that shot this bullet (for parry)
    sourceEnemyPos*: Vector2f  # Position where the bullet was shot from (for parry fallback)
    # New legendary power-up bullet properties
    travelDistance*: float32  # Track distance for Overcharge
    isEcho*: bool  # True if this is an echo clone bullet
    echoTrailTimer*: float32  # Timer for spawning echo clones
    isBossBullet*: bool  # True if this bullet was fired by a boss (for glow effect)
    isArcaneBullet*: bool  # True if this bullet is from arcane bullet power-up

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

  Particle* = ref object
    pos*: Vector2f
    vel*: Vector2f
    color*: Color
    lifetime*: float32
    maxLifetime*: float32
    size*: float32

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

  ShopItem* = object
    name*: string
    description*: string
    baseCost*: int
    bought*: int

  Game* = ref object
    state*: GameState
    mode*: GameMode
    player*: Player
    enemies*: seq[Enemy]
    bullets*: seq[Bullet]
    coins*: seq[Coin]
    consumables*: seq[Consumable]
    walls*: seq[Wall]
    particles*: seq[Particle]
    attackWarnings*: seq[AttackWarning]
    lasers*: seq[Laser]  # Add laser tracking
    time*: float32
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
    # Power-up roll animation fields
    rollAnimationActive*: bool
    rollAnimationTimer*: float32
    rollSpeed*: array[3, float32]  # Individual roll speeds for each slot
    rollPosition*: array[3, float32]  # Current scroll position for each slot
    rollPowerUpList*: array[3, seq[PowerUp]]  # List of power-ups scrolling in each slot
    canSelectPowerUp*: bool  # Whether player can select (false during animation)
    bossActive*: bool
    bossSpawnTimer*: float32
    bossCoinActive*: bool  # True when boss coin needs to be collected to end wave
    cameFromPowerUpSelect*: bool
    gameOverSoundPlayed*: bool
    # Wave-based mode fields
    currentWave*: int
    wavesUntilBoss*: int
    waveEnemiesRemaining*: int
    waveEnemiesTotal*: int
    waveInProgress*: bool
    # Cheat tracking
    cheatsUsed*: bool  # Set to true if cheat menu opened during run
    # Mouse tracking for menu navigation
    lastMousePos*: Vector2f  # Track mouse position to detect movement
    mouseMovedRecently*: bool  # True if mouse has moved since last keyboard input
    keyboardUsedRecently*: bool  # True if keyboard was just used (disables mouse temporarily)
    # State tracking for settings return
    previousState*: GameState  # Track where we came from to return correctly
    # Enemy ID counter for unique tracking
    nextEnemyId*: int  # Counter for assigning unique IDs to enemies

proc newVector2f*(x, y: float32): Vector2f =
  result.x = x
  result.y = y

proc `+`*(a, b: Vector2f): Vector2f =
  newVector2f(a.x + b.x, a.y + b.y)

proc `-`*(a, b: Vector2f): Vector2f =
  newVector2f(a.x - b.x, a.y - b.y)

proc `*`*(a: Vector2f, s: float32): Vector2f =
  newVector2f(a.x * s, a.y * s)

proc length*(v: Vector2f): float32 =
  sqrt(v.x * v.x + v.y * v.y)

proc normalize*(v: Vector2f): Vector2f =
  let l = v.length()
  if l > 0:
    newVector2f(v.x / l, v.y / l)
  else:
    newVector2f(0, 0)

proc distance*(a, b: Vector2f): float32 =
  (b - a).length()

proc newAttackWarning*(x, y: float32, attackType: string, duration: float32): AttackWarning =
  AttackWarning(
    pos: newVector2f(x, y),
    attackType: attackType,
    lifetime: duration,
    maxLifetime: duration
  )

proc newLaser*(x, y: float32, direction: int, length, thickness: float32, damage: int, duration: float32, rotation: float32 = 0.0): Laser =
  Laser(
    pos: newVector2f(x, y),
    direction: direction,
    length: length,
    thickness: thickness,
    damage: damage,
    lifetime: duration,
    maxLifetime: duration,
    hasHitPlayer: false,
    rotation: rotation
  )
