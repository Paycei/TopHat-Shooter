import raylib, std/tables, std/deques, discord_presence, particle_types, math

export Particle, ParticlePool, Vector2f
export newVector2f, `+`, `-`, `*`, length, normalize, distance
export Deque

# Timing for the Chain Reactor's telegraphed electricity attacks. Shared so the
# warning-update logic (game.nim) and the telegraph drawing (enemy.nim) agree on
# exactly when the dodge window ends and the strike becomes lethal.
const
  TeslaStrikeTelegraph* = 0.95'f32  # dodge window before a ground strike lands
  TeslaStrikeActive*    = 0.18'f32  # how long the strike zone stays lethal
  ArcBeamTelegraph*     = 1.05'f32  # dodge window before a lightning wall fires
  ArcBeamActive*        = 0.30'f32  # how long the wall stays lethal

type
  GameState* = enum
    gsSplash, gsLanguageSelect, gsLoreIntro, gsMenu, gsPlaying, gsPaused, gsShop, gsGameOver, gsCountdown, gsWaveCleared, gsPowerUpSelect, gsRunStats, gsPvPPlaying, gs3DBoss,
    gsRogueliteFloorSelect, gsDeathSequence, gsVictory, gsEndgameCinematic

  GameMode* = enum
    gmWaveBased,
    gmTimeSurvival,
    gmSandbox,
    gmPvP,
    gmRoguelite

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
    fireRate*: float32      ## Seconds between shots: lower is faster (default 0.375)
    ## NOTE: PvP fire rate (0.375) is intentionally faster than singleplayer (0.425).
    ## The shorter TTK in PvP rewards mechanical skill and keeps matches snappy.
    bulletSpeed*: float32   ## Bullet travel speed (default 425)
    bulletRadius*: float32  ## Bullet hitbox/visual radius (default 7.5)
    startCoins*: int        ## Coins at match start (default 100)
    startWalls*: int        ## Walls at match start (default 3)
    killLimit*: int         ## Kills needed to win (default 5)
    respawnTime*: float32   ## Seconds before respawn (default 3.0)
    timeLimit*: float32     ## Match time limit in seconds, 0 = unlimited (default 180)
    snapshotRate*: float32  ## Seconds between server->client state snapshots
    inputRate*: float32     ## Seconds between client->server input packets

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
    etMage,        # Summons meteorites and shoots homing magic bullets
    etEnvironment  # Sentinel: damage from arena hazards, not an enemy

  DeathCause* = enum
    ## How the player was killed, used by the game-over screen to explain the death.
    ## dcUnknown MUST stay first so a freshly constructed Game zero-inits to it.
    dcUnknown,       # No attributable source (PvP, edge cases)
    dcContact,       # Touched a regular enemy
    dcBossContact,   # Touched a boss
    dcProjectile,    # Hit by an enemy bullet
    dcLaser,         # Caught in an enemy laser beam
    dcExplosion,     # Caught in an enemy/elite explosion
    dcMeteorite,     # Struck by a falling meteorite
    dcPoison,        # Poison damage-over-time finished the job
    dcHazard         # Arena/environmental hazard

  EliteType* = enum
    etNone,        # Not elite
    etSwift,       # 40% faster movement and attack speed
    etTank,        # 2x HP, 45% damage reduction
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
    puAftershock,      # LEGENDARY active: shockwave traces backward along movement path
    puArcaneAura,      # Arcane aura version - enhanced damage
    puArcaneBullets,   # Arcane bullet version - enhanced damage
    puArcaneMastery,   # LEGENDARY: Enhance all arcane effects (damage, priecing)
    puArcaneOrb,       # Arcane elemental orb
    puBerserker,       # Attack speed at low HP
    puBloodAura,       # Blood damage aura with lifesteal
    puBloodBullets,    # Lifesteal on hit
    puBloodMastery,    # LEGENDARY: Enhance all blood effects (damage, lifesteal)
    puBloodOrb,        # Blood elemental orb
    puBloodPact,       # LEGENDARY active: sacrifice 30% HP to deal it as split damage to all enemies
    puBountiful,       # LEGENDARY passive: greatly increase consumable drop rates, boost consumable effects, guarantee drops on kill milestones
    puBulletRicochet,  # Bullets ricochet off enemies
    puBulletSpeed,     # Faster bullets
    puBulletSplit,     # Bullets split on impact
    puCelestialVeil,   # LEGENDARY: Absorb 1 hit per wave
    puChainLightning,  # Damage chains between enemies
    puConduit,         # LEGENDARY active: detonate all active DoTs for 3x burst damage
    puCriticalHit,     # Random critical damage
    puCurse,           # Curse a % of random enemies; player deals bonus damage to cursed (greatly reduced vs bosses)
    puDodgeChance,     # Chance to evade damage
    puDoubleShot,      # Shoots 2 bullets at once
    puEchoShots,       # Bullets leave damaging trails
    puExplosiveBullets,# Bullets explode on impact
    puFireAura,        # Fire damage over time aura
    puFireBullets,     # Bullets apply fire damage over time
    puFireMastery,     # LEGENDARY: Enhance all fire effects (damage, duration, slow)
    puFireOrb,         # Fire elemental orb
    puFortified,       # Reduce damage taken
    puFrostMastery,    # LEGENDARY: Enhance all frost effects (damage, duration, slow)
    puFrostOrb,        # Frost elemental orb
    puFrostShots,      # Bullets slow enemies
    puGiantSlayer,     # Deal % of enemy HP as bonus damage
    puGravityWell,     # Pull enemies toward you
    puHealPower,       # Normal passive: increase healing received from all sources by a percentage
    puHeavyRounds,     # Larger bullets with knockback
    puLifeSteal,       # Gain HP from kills
    puLightningAura,   # Lightning damage that chains between enemies
    puLightningMastery,# LEGENDARY: Enhance all lightning effects (damage, duration, slow)
    puLightningOrb,    # Lightning elemental orb
    puLuckyCoins,      # Doubles coins collected
    puMagicalBullets,  # Bullets track enemies
    puMaxHealth,       # Increase max HP
    puMultiShot,       # Shoots in 3 directions
    puNova,            # LEGENDARY active: freeze all player bullets for 2s, then release at 1.5x speed
    puOvercharge,      # Bullets gain power over distance
    puParry,           # LEGENDARY: Active ability - invincible + bounce bullets
    puPhaseShift,      # Teleport dash through enemies
    puPiercingShots,   # Bullets pass through enemies
    puPoisonAura,      # Poison damage over time aura (lower damage, longer duration)
    puPoisonMastery,   # LEGENDARY: Enhance all poison effects (damage, duration, slow)
    puPoisonOrb,       # Poison elemental orb
    puPoisonShot,      # Poison bullets that apply DoT effect
    puPulseArmor,      # When you take damage, emit shockwave that pushes enemies back
    puRadialBurst,     # Shoots a circle of bullets periodically
    puRage,            # Damage increases at low HP
    puRapidFire,       # Increased fire rate
    puRegeneration,    # Slowly restore HP
    puResonance,       # Normal passive: bullets hitting DoT enemies deal bonus elemental damage
    puRotatingOrbs,    # Rotating elemental orbs around player (LEGENDARY - all 7 elements)
    puRotatingShield,  # Orbiting protective shield
    puSlowField,       # Enemies move slower nearby
    puSpecialRounds,   # Every Nth bullet has special on-hit effect
    puSpeedBoost,      # Permanent speed increase
    puThorns,          # Reflect damage to attackers
    puTimeWarp,        # Slow down time globally
    puVolatile,        # LEGENDARY passive: enemies with 2+ DoTs take +50% dmg, death pulse spreads elements
    puWallMaster,      # Place stronger walls and increment turret damage
    puWallTurrets,     # LEGENDARY: Walls become turrets that shoot enemies
    puWindAura,        # Pushes enemies away from player
    puWindBullets,     # Bullets push enemies backwards
    puWindMastery,     # LEGENDARY: Enhance all wind effects (damage, duration, slow)
    puWindOrb          # Wind elemental orb

  PowerUpRarity* = enum
    prCommon,
    prLegendary

  PowerUp* = object
    powerType*: PowerUpType
    level*: int  # 1, 2, or 3
    rarity*: PowerUpRarity  # Common or Legendary

  RogueliteStarterKit* = enum
    rskOperator,
    rskBulwark,
    rskArcanist

  RoguelitePowerFamily* = enum
    rpfCore,
    rpfShield,
    rpfArcane,
    rpfFire,
    rpfFrost,
    rpfPoison,
    rpfLightning,
    rpfWind,
    rpfBlood

  DungeonFloorTheme* = enum
    dftFirewall,
    dftRecycleBin,
    dftRegistry,
    dftNetwork,
    dftKernel,
    dftCache,
    dftCorruptedSector

  DungeonRoomKind* = enum
    drkStart,
    drkCombat,
    drkElite,
    drkTreasure,
    drkShop,
    drkBoss

  DoorDir* = enum
    ddUp,
    ddRight,
    ddDown,
    ddLeft

  DungeonPickupKind* = enum
    dpkKey,
    dpkCompass,
    dpkMap,
    dpkRelicPedestal,
    dpkShardCache

  DungeonPickup* = ref object
    pos*: Vector2f
    kind*: DungeonPickupKind
    costCredits*: int     # 0 = free on touch
    taken*: bool

  DungeonRoom* = ref object
    gridX*, gridY*: int
    kind*: DungeonRoomKind
    doors*: set[DoorDir]
    cleared*: bool        # Encounter finished (start/shop rooms are born cleared)
    visited*: bool        # Player has entered this room
    seen*: bool           # Adjacent to a visited room (shows as outline on minimap)
    locked*: bool         # Treasure rooms need a key to enter
    encounterBudget*: int # Enemies to spawn on first entry
    encounterSeed*: int
    bfsDepth*: int        # Distance from the start room
    obstacleSeed*: int
    pickups*: seq[DungeonPickup]

  DungeonFloor* = ref object
    theme*: DungeonFloorTheme
    floorNumber*: int
    rooms*: seq[DungeonRoom]
    currentRoom*: int
    startIdx*: int
    bossIdx*: int
    mapRevealed*: bool    # Map pickup: full layout visible on minimap
    compassFound*: bool   # Compass pickup: boss room marked on minimap

  RogueliteRelicType* = enum
    rrtNone,
    rrtDiscountProtocol,
    rrtShardMagnet,
    rrtEliteDividend,
    rrtEmergencyPatch,
    rrtDraftCache

  RogueliteRelic* = object
    relicType*: RogueliteRelicType
    name*: string
    description*: string

  RogueliteProfile* = ref object
    version*: int
    dataShards*: int
    cores*: int
    unlockedStarterKits*: set[RogueliteStarterKit]
    unlockedPowerFamilies*: set[RoguelitePowerFamily]
    unlockedRelics*: set[RogueliteRelicType]
    unlockedPlayerSkins*: seq[string]
    unlockedBulletSkins*: seq[string]
    unlockedPlayerShapes*: seq[string]
    unlockedBulletShapes*: seq[string]
    unlockedParticleSkins*: seq[string]
    unlockedDesktopBgs*: seq[string]
    unlockedCubeSkins*: seq[string]
    unlockedBossTier*: int
    highestHeat*: int
    bestFloor*: int
    bestRooms*: int
    bestEndlessLoop*: int
    totalRuns*: int
    wins*: int

  RogueliteRun* = ref object
    seed*: int
    starterKit*: RogueliteStarterKit
    heat*: int
    floorNumber*: int                # 1..RogueliteFloorsToWin, resets each endless loop
    floor*: DungeonFloor             # The active generated floor
    totalRoomsCleared*: int
    keys*: int                       # Opens locked treasure rooms
    combatRoomsSinceDraft*: int      # Draft offered every 2nd combat/elite clear
    usedThemes*: set[DungeonFloorTheme]
    nextThemeChoices*: array[3, DungeonFloorTheme]
    pendingFloorSelect*: bool
    relics*: seq[RogueliteRelic]
    shardsEarned*: int
    coresEarned*: int
    endlessLoop*: int
    completed*: bool
    died*: bool

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
    bulletRadius*: float32       # Bullet radius for delayed-spawn attacks (e.g. meteors)
    overrideColor*: Color        # Optional color tint for this warning (alpha=0 = use default)

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
    lastHitTime*: Table[int, float32]  # Track when each enemy was last hit (pruned on access)

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
    outOfCombatSpeedBoost*: bool  # Roguelite: +25% move speed while no encounter is active
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
    # Singularity (Gravity Well) regenerating HP-based shield
    singularityShield*: float32            # Current shield amount (absolute)
    singularityShieldMaxPct*: float32      # Fraction of max HP used as shield max (0.0-1.0)
    singularityShieldRegenTimer*: float32  # Time since last singularity-shield damage
    singularityShieldRegenDelay*: float32  # Delay before singularity shield starts regenerating
    singularityShieldRegenRatePct*: float32# Fraction of max HP regained per second when regenerating
    killsSinceLastHeal*: int
    regenTimer*: float32
    lastDamageEvent*: DamageEvent  # One-frame categorical signal set by takeDamage, consumed by drawPlayer
    rageStacks*: int
    critCharge*: float32
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
    poisonSourceType*: EnemyType  # Enemy type that applied the poison (for stats tracking)
    lastDamageAvoided*: float32  # Set by takeDamage when a hit is blocked, read by game.nim to record damageAvoided
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
    wearsTophat*: bool  # Secret kernel tophat cosmetic (unlocked by beating the wave-60 boss)
    hasOrbitalCube*: bool  # Secret orbital-cube cosmetic (Escape Velocity advancement reward)
    cubeSkinType*: int  # Equipped desktop-cube skin (colors the orbital cube companion)
    celestialVeilActive*: bool  # True if Celestial Veil can still absorb a hit this wave
    # Volatile (Legendary passive)
    hasVolatile*: bool          # Enemies with 2+ DoTs take +50% dmg and spread on death
    # Resonance (Normal passive)
    resonanceLevel*: int        # 0 = none, 1/2/3 = 20/30/40% bonus elemental DPS
    # Blood Pact (Legendary active)
    bloodPactCooldown*: float32 # Countdown to next use (0 = ready)
    # Conduit (Legendary active)
    conduitCooldown*: float32   # Countdown to next use (0 = ready)
    # Aftershock (Legendary active)
    aftershockCooldown*: float32    # Countdown to next use (0 = ready)
    aftershockPosHistory*: Deque[Vector2f]  # Last 2s of positions (sampled every 0.05s)
    aftershockSampleTimer*: float32       # Accumulator for position sampling
    # Nova (Legendary active)
    novaCooldown*: float32      # Countdown to next use (0 = ready)
    novaActive*: bool           # True while bullets are frozen
    novaFreezeTimer*: float32   # How long freeze remains
    healPowerMult*: float32     # Multiplier for all healing received (default 1.0, increased by puHealPower)
    hasBountiful*: bool         # True when Cornucopia legendary is active
    bountifulKillCounter*: int  # Counts kills for guaranteed-drop milestones (resets every 20)

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

  BossWeakObjectiveKind* = enum
    bwoNone,
    bwoSpiralAnchors,
    bwoSummonSigils,
    bwoMeteorCracks,
    bwoLaserPrisms,
    bwoVoidRifts,
    bwoCoilSequence,
    bwoSatelliteSet,
    bwoDashBackPlate,
    bwoPrismSequence,
    bwoClockNodes,
    bwoChaosAnomalies,
    bwoOmegaCycle

  BossWeakDamageSource* = enum
    bwdsPassive,
    bwdsDirectBody,
    bwdsDirectWeakCore

  BossWeakPointDefinition* = object
    kind*: BossWeakObjectiveKind
    requiredHits*: int
    targetCount*: int
    bodyDamageMultiplier*: float32
    weakCoreMultiplier*: float32
    exposureDuration*: float32
    cooldownDuration*: float32
    targetHitRadius*: float32

  BossWeakPointTarget* = object
    pos*: Vector2f
    angle*: float32
    orbitRadius*: float32
    orbitSpeed*: float32
    hitRadius*: float32
    life*: float32
    maxLife*: float32
    index*: int
    active*: bool
    hit*: bool
    decoy*: bool
    relativeToBoss*: bool
    color*: Color
    wrongHitFlash*: float32    ## Counts down (0.45 s) after hitting the wrong target, red flash overlay
    hitFlashTimer*: float32    ## Counts down (0.30 s) after a correct hit, expanding burst ring
    activeGraceTimer*: float32 ## Counts down (0.38 s) when a sequential target first becomes active, wider hitbox

  BossWeakPointState* = object
    enabled*: bool
    kind*: BossWeakObjectiveKind
    targets*: seq[BossWeakPointTarget]
    progress*: int
    required*: int
    sequenceIndex*: int
    exposedTimer*: float32
    cooldownTimer*: float32
    pulseTimer*: float32
    bodyDamageMultiplier*: float32
    weakCoreMultiplier*: float32
    exposureDuration*: float32
    cooldownDuration*: float32
    targetHitRadius*: float32
    phaseIndex*: int
    lastDashActive*: bool
    omegaWindowsCompleted*: int
    realTargetIndex*: int
    lastBossPos*: Vector2f

  Enemy* = ref object
    id*: int                      # Unique identifier for tracking bullet hits
    pos*: Vector2f
    vel*: Vector2f
    radius*: float32              # Combat hitbox (visual size, used for bullets/player collision)
    collisionRadius*: float32     # Enemy-to-enemy collision hitbox
    hp*: float32
    maxHp*: float32
    speed*: float32
    contactDamage*: float32       # Damage dealt on contact/collision
    rangedDamage*: float32        # Damage dealt by bullets/projectiles
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
    activeEffects*: array[ElementType, ActiveEffect]  # Unified effect system, indexed directly by ElementType
    chainLightningCooldown*: float32

    attackWarningTimer*: float32
    attackExecuteTimer*: float32
    attackPhase*: int  # 0=patrol, 1=warning, 2=execute
    dashCooldown*: float32
    fakeWarningTimer*: float32
    clonePositions*: seq[Vector2f]
    cloneTimer*: float32
    hasEnteredScreen*: bool  # Tracks if ranged enemy is fully inside screen
    cursed*: bool  # Marked by the Curse power-up; player deals bonus damage to this enemy
    curseRolled*: bool  # True once curse eligibility has been evaluated (roll happens once per enemy)
    isElite*: bool  # Whether this is an elite enemy
    eliteType*: EliteType  # Type of elite modifier
    eliteTypes*: seq[EliteType]  # Multiple elite types for high-wave elites
    eliteAuraPhase*: float32  # For animating the elite aura
    threatLevel*: int  # Visual threat tier used by high-heat roguelite/enemy scaling
    shieldHp*: float32  # For shielded elites
    maxShieldHp*: float32  # Maximum shield HP
    diamondShieldActive*: bool  # 1-hit shield for diamond enemies (like Celestial Veil)
    regenTimer*: float32  # For regenerative elites
    spawnedByBoss*: bool  # True if spawned by boss summon attack
    rotation*: float32  # Current rotation angle in radians
    bossDefinitionID*: int  # Which boss definition this uses
    currentPhaseIndex*: int  # Current phase index
    bossTotalMaxHp*: float32  # Total scaled boss HP split across phase pools
    bossPhaseHpPools*: seq[float32]  # Max HP for each boss phase pool
    bossPhaseBreakFlashTimer*: float32  # Short visual pulse after a phase pool breaks
    attackTimers*: seq[float32]  # Individual cooldown timer for each attack in current phase
    attackWarningFired*: seq[bool]  # True once the pre-fire warning has been shown for this cycle
    defenseMultiplier*: float32  # Damage reduction multiplier
    debuffResistance*: float32  # Stun/slow resistance multiplier
    isDashing*: bool  # Whether boss is currently executing a dash
    dashVelocity*: Vector2f  # Velocity during dash
    dashDuration*: float32  # Remaining dash duration
    dashMaxDuration*: float32  # Total dash duration for this attack
    dashTargetPos*: Vector2f  # Exact endpoint for the current committed dash
    pendingDashLocked*: bool  # True while a dash warning has locked the next dash line
    pendingDashStart*: Vector2f  # Exact start point shown by the dash warning
    pendingDashTarget*: Vector2f  # Exact endpoint shown by the dash warning
    satellites*: seq[OrbitalSatellite]  # Persistent satellites that can be destroyed
    weakPoint*: BossWeakPointState  # Boss objective weak-point state
    invulnerabilityTimer*: float32  # Brief invulnerability during phase transitions
    # Boss engagement mechanics (force conscious play, not just facetank-and-shoot)
    reflectShieldActive*: bool      # Body shots are reflected/blocked while this is up
    reflectShieldTimer*: float32    # Time remaining on the current reflect shield
    reflectShieldCooldown*: float32  # Time until the next reflect shield raises
    bossStallTimer*: float32        # Time the current weak-point objective has gone unbroken
    bossEnrageLevel*: float32       # 0 = calm; ramps while the objective is ignored (faster attacks)
    addsGateActive*: bool           # True while living boss-summoned adds make the boss damage-immune
    summonWaveActive*: bool         # Summoner King: a summoned wave is out; clearing it opens the window
    ignoreHealPending*: float32     # Queued heal from weak-point targets that expired unhit (applied next frame)
    windowDamageDealt*: float32     # Player damage dealt during the current vulnerability window
    windowWasOpen*: bool            # Tracks vulnerability-window open->close edge for heal-on-ignore
    auraDamageAccumulator*: float32  # Accumulates aura damage over time
    lastAuraDamageNumberTime*: float32  # Last time a damage number was shown for auras
    auraDamageHadCrit*: bool  # Track if any crit occurred during accumulation period
    lastAuraDamageType*: DamageType  # Track the damage type of accumulated aura damage
    contactDamageAccumulator*: float32  # Accumulates contact damage over time
    lastContactDamageNumberTime*: float32  # Last time a damage number was shown for contact
    damageTuning*: float32  # Dungeon: attack-damage compression factor (0 or 1 = untouched)

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
    echoSpawnCount*: int  # Echoes this parent (and its clones) have already spawned
    echoHitEnemies*: seq[int]  # Enemy IDs already damaged by echoes from this parent
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
    baseDamagePreCrit*: float32  # Damage before crit multiplier (for puCriticalHit tracking)
    isSpecialRound*: bool  # True if this is a special round (every Nth bullet)
    isFromWallTurret*: bool  # True if this bullet was fired by a Wall Turret
    isFromRadialBurst*: bool  # True if this bullet was fired by Radial Burst
    isFromBulletSplit*: bool  # True if this bullet was created by Bullet Split
    isRicochet*: bool  # True if this bullet has already ricocheted at least once
    isParried*: bool  # True if this was an enemy bullet bounced back by Parry
    colorOverride*: Color  # Custom bullet color (alpha=0 means use default coloring)
    bulletSkin*: int  # Bullet skin typeHost
    ownerPlayerIndex*: int  # For PvP: which player shot this bullet (-1 for non-PvP)
    isFrozenByNova*: bool  # True while Nova ability has this bullet frozen in place
    isFromNova*: bool      # True if this bullet was released by Nova (for damage tracking)
    rageMultiplier*: float32  # Rage damage multiplier baked in at fire time (1.0 = no bonus)

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
    permanent*: bool      # Dungeon obstacle: ignores duration decay, not player-placed
    respawns*: bool       # Boss-room obstacle: re-forms a while after being destroyed
    obstacleTint*: Color  # Theme accent for permanent dungeon obstacles

  PendingWallRespawn* = object
    ## A boss-room obstacle that was smashed and is waiting to re-form. Kept off
    ## game.walls so it stops colliding while broken; re-added when timer expires.
    pos*: Vector2f
    radius*: float32
    maxHp*: float32
    tint*: Color
    timer*: float32

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
    dtHeal,         # Green - healing (positive numbers)
    dtHitCount      # White - integer hit counter (no decimals, used for star hits)

  DamageEvent* = enum
    ## Categorical one-frame signals written by takeDamage and read by drawPlayer.
    ## Replaces the previous float-sentinel lastDamageTaken mechanism.
    ##
    ##  - deNone: no pending event (idle / already consumed)
    ##  - deDodged: player successfully dodged the hit
    ##  - deDamage: player took damage (UI/alert signal)
    ##  - deCelestialVeil: Celestial Veil absorbed the hit
    deNone,         # No pending event (idle / already consumed)
    deDodged,       # Player successfully dodged the hit
    deDamage,       # Player took damage (UI/alert signal)
    deCelestialVeil # Celestial Veil absorbed the hit

  DamageNumber* = ref object
    pos*: Vector2f          # Current position
    vel*: Vector2f          # Velocity (moves upward and fades)
    damage*: float32        # Amount of damage to display
    lifetime*: float32      # How long the number has existed
    maxLifetime*: float32   # Total duration before disappearing
    fromPlayer*: bool       # True if player dealt damage, false if enemy dealt damage
    isCritical*: bool       # True for critical hits (larger, different color)
    damageType*: DamageType # Type of damage for color coding

  CurrencyIndicatorKind* = enum
    cikCredits,
    cikDataShards,
    cikCores

  CurrencyIndicator* = ref object
    pos*: Vector2f
    vel*: Vector2f
    amount*: int
    lifetime*: float32
    maxLifetime*: float32
    kind*: CurrencyIndicatorKind

  LightningBolt* = ref object
    ## A short-lived jagged lightning arc drawn between two world positions.
    startPos*: Vector2f
    endPos*: Vector2f
    lifetime*: float32       # Remaining display time
    maxLifetime*: float32
    segments*: seq[Vector2f] # Pre-computed jagged waypoints (including start & end)

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

  WavePulseRing* = object
    centerX*: float32
    centerY*: float32
    radius*: float32
    maxRadius*: float32
    alpha*: float32
    color*: Color

  BossArenaRingMode* = enum
    barmNone,
    barmBoon,
    barmHazard,
    barmRotating

  OSBackgroundState* = object
    dataPackets*: seq[DataPacket]
    circuitLines*: seq[CircuitLine]
    gridPulseTime*: float32
    alertLevel*: float32  # 0.0 = normal, 1.0 = critical
    lowHealthVignetteLevel*: float32  # 0.0 = hidden, 1.0 = strongest low-health warning
    wavePulseRings*: seq[WavePulseRing]  # Expanding rings on wave events
    bossArenaMode*: BossArenaRingMode
    bossArenaPhase*: float32
    bossArenaRotation*: float32
    bossArenaDamageCooldown*: float32
    bossArenaPlayerBand*: int
    bossArenaPlayerOnActive*: bool
    bossArenaBonusIntensity*: float32
    bossArenaPlayerX*: float32
    bossArenaPlayerY*: float32

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
    pendingWallRespawns*: seq[PendingWallRespawn]  # Boss-room obstacles re-forming
    particlePool*: ParticlePool
    attackWarnings*: seq[AttackWarning]
    lasers*: seq[Laser]
    meteorites*: seq[Meteorite]
    damageNumbers*: seq[DamageNumber]
    currencyIndicators*: seq[CurrencyIndicator]
    time*: float32
    frameCount*: int  # Frame counter for satellite optimizations
    perfUpdateMs*: float32  # Smoothed wall-clock ms spent in updateGame (debug overlay)
    perfDrawMs*: float32    # Smoothed wall-clock ms spent in drawGame   (debug overlay)
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
    recentPowerUp*: PowerUp
    recentPowerUpTimer*: float32
    recentPowerUpMaxTimer*: float32
    rollAnimationActive*: bool
    rollAnimationTimer*: float32
    rollSpeed*: array[3, float32]       # Current scroll speed px/s (used by renderer for motion blur)
    rollPosition*: array[3, float32]    # Current scroll offset in px (0 = first card at top)
    rollBrakeStartPos*: array[3, float32] # Position recorded at the moment braking began (-1 = not braking yet)
    rollPowerUpList*: array[3, seq[PowerUp]]  # List of power-ups scrolling in each slot
    canSelectPowerUp*: bool  # Whether player can select (false during animation)
    rerollCost*: int  # Cost of next reroll (increases after each use)
    bossWaveManager*: BossWaveManager  # Centralized boss wave and coin management
    bossSpawnTimer*: float32
    pendingBoss*: Enemy           # Temporarily holds a boss scheduled to spawn after warning
    pendingBossTimer*: float32    # Time remaining until pending boss is actually spawned
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
    sandboxSelectedTab*: int  # Current tab in sandbox UI (0=Enemies, 1=Bosses, 2=PowerUps, 3=Controls)
    sandboxScrollOffset*: int32  # Scroll position in sidebar
    sandboxScrollbarDragging*: bool     # True while the user is dragging the scrollbar thumb
    sandboxScrollbarDragOffsetY*: float32  # Mouse Y offset within the thumb at drag start
    shopSidebarScroll*: int32   # Scroll offset (px) for the in-game shop left panel
    sandboxGodMode*: bool  # Player invulnerability
    sandboxFreezeEnemies*: bool  # Freeze all enemy movement
    discordClient*: DiscordClient  # Discord Rich Presence client
    rogueliteProfile*: RogueliteProfile
    rogueliteRun*: RogueliteRun
    selectedRogueliteStarter*: int
    selectedRogueliteHeat*: int
    rogueliteHeatPulseTimer*: float32
    rogueliteHeatPulseDirection*: int
    selectedRogueliteTheme*: int
    roomTransitionActive*: bool      # Fade between dungeon rooms in progress
    roomTransitionTimer*: float32
    roomTransitionDir*: DoorDir      # Door the player walked through
    osBackground*: OSBackgroundState  # Animated background system
    osHUD*: OSHUDState  # OS-style HUD and notifications
    pauseMenuTab*: TaskManagerTab  # Current tab in pause menu task manager
    selectedGameOverButton*: int  # Selected button on game over screen (0=Restart, 1=Stats, 2=Exit)
    selectedVictoryButton*: int  # Selected button on victory screen (0=Continue, 1=Stats, 2=Menu)
    hasWonGame*: bool  # True once the wave-60 final boss is beaten; gates the one-time victory screen
    tophatJustUnlocked*: bool  # True only on the run that first earned the kernel tophat (victory banner)
    deathCause*: DeathCause  # What killed the player (recorded once in beginPlayerDeathSequence)
    deathSourceName*: string  # Resolved name of the killer (enemy/boss); empty for hazards
    deathSourceWasBoss*: bool  # True if the killer was a boss (affects game-over styling)
    dopamine*: DopamineState  # Dopamine enhancement systems
    game3D*: pointer  # Pointer to Game3D to avoid circular dependency
    transitioning*: bool  # Fade transition active
    fadeAlpha*: float32  # Fade opacity (0.0 to 1.0)
    deathSequenceTimer*: float32  # Real-time timer for post-death slow/fast/fade playback
    deathSequenceFadeAlpha*: float32  # Fade opacity during death playback
    deathSequenceTimeScale*: float32  # Current playback time scale during death sequence
    lightningBolts*: seq[LightningBolt]  # Active lightning arc visuals
    confirmQuitPending*: bool  # True while the quit-confirmation dialog is open
    pauseMenuExitCooldown*: float32  # Countdown before Exit button/key becomes active (prevents accidental exit)
    confirmQuitFrameGuard*: float32  # Short guard so Q-open and Q-confirm can't fire on the same frame
    wallPlacementMode*: bool   # Whether the player is in wall-placement mode (E toggles, RMB/walls=0 exits)
    comebackBonusActive*: bool  # True while the +10% comeback stat bonus is in effect
    comebackEndWave*: int        # Wave number at which the comeback bonus expires (copied from settings on run start)

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

# Bullet-speed diminishing returns

const
  BulletSpeedDiminishStart* = 325.0'f32
  BulletSpeedDiminishScale* = 220.0'f32

  # Duration of the epic boss phase-change animation. The boss is invulnerable
  # and frozen for this whole window; the per-boss transition visuals in
  # `drawBossPhaseTransition` are driven by how much of it has elapsed.
  BossPhaseTransitionDuration* = 2.3'f32

proc diminishedBulletSpeedGain*(currentSpeed, gain: float32): float32 =
  ## Keeps early bullet-speed gains intact, then tapers later gains smoothly.
  if gain <= 0.0:
    return gain
  let excess = max(0.0'f32, currentSpeed - BulletSpeedDiminishStart)
  let factor = 1.0'f32 / (1.0'f32 + excess / BulletSpeedDiminishScale)
  gain * factor

proc addBulletSpeedDiminished*(currentSpeed, gain: float32): float32 =
  currentSpeed + diminishedBulletSpeedGain(currentSpeed, gain)

proc multiplyBulletSpeedDiminished*(currentSpeed, multiplier: float32): float32 =
  if multiplier <= 1.0:
    return currentSpeed * multiplier
  currentSpeed + diminishedBulletSpeedGain(currentSpeed, currentSpeed * (multiplier - 1.0))

proc applyFireRateDiminished*(currentRate, scalingFactor, exponent, hardCap: float32): float32 =
  ## Applies one fire-rate upgrade step with tunable diminishing returns.
  ## Lower fireRate = faster shooting, so the result is always clamped above hardCap.
  ## scalingFactor: base reduction strength. exponent: DR curve steepness.
  ## Reference fireRate for the DR pivot is 0.415 (the unupgraded base).
  let diminishingFactor = pow(currentRate / 0.415'f32, exponent)
  let effectiveReduction = currentRate * scalingFactor * diminishingFactor
  max(hardCap, currentRate - effectiveReduction)

proc getEffectiveSpeed*(baseSpeed: float32, waveNumber: int): float32 =
  ## NATURAL SPEED REDUCTION: Pure mathematical scaling with NO hardcoded thresholds
  ## Reduction emerges naturally from wave progression and enemy speed
  ## Exponential scaling for fast enemies that grows stronger over time

  # Reference speed: typical wave 1 enemy speed
  const REFERENCE_SPEED = 100.0

  # Calculate speed excess over reference (how much faster than normal)
  let speedRatio = baseSpeed / REFERENCE_SPEED

  # Wave pressure: natural logarithmic growth that increases smoothly with waves
  # ln(1 + wave/10) creates unbounded growth without thresholds:
  # Wave 1 -> 0.095, Wave 10 -> 0.693, Wave 20 -> 1.099, Wave 50 -> 1.705
  let wavePressure = ln(1.0 + waveNumber.float32 / 10.0)

  # Speed excess factor: exponential penalty for being faster than reference
  # Uses sqrt to convert ratio to excess smoothly:
  # 1.5x speed -> 1.22x factor, 2x -> 1.41x, 3x -> 1.73x, 4x -> 2.0x
  # max(0, ...) ensures no penalty for slower enemies
  let speedExcessFactor = max(0.0, sqrt(speedRatio) - 1.0)

  # Combined reduction: (speed_excess)^1.8 * wave_pressure * 0.28
  # Power of 1.8 creates strong exponential scaling for fast enemies
  # Coefficient 0.28 provides balanced reduction that grows naturally
  # Result: fast enemies in late waves get heavily reduced, but it's gradual
  let reductionFactor = pow(speedExcessFactor, 1.8) * wavePressure * 0.28

  # Apply reduction with natural diminishing returns
  # Formula: speed / (1 + factor) can never reduce to 0
  baseSpeed / (1.0 + reductionFactor)
