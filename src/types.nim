import raylib, math, std/tables

type
  GameState* = enum
    gsMenu, gsPlaying, gsPaused, gsShop, gsGameOver, gsHelp, gsCountdown, gsPowerUpSelect, gsSettings
  
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
    etPhantom      # Unpredictable - teleports with fake clones

  BossType* = enum
    btShooter,   # Shoots spiral of bullets
    btSummoner,  # Spawns many minions
    btCharger,   # Dashes toward player
    btOrbit      # Shoots orbiting projectiles

  BossPhase* = enum
    bpCircle,    # Normal circular boss form
    bpCube,      # Cube form - defensive, shoots more
    bpTriangle,  # Triangle form - aggressive dashes
    bpStar       # Star form - bullet storm phase

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
    puHomingBullets,   # Bullets track enemies
    puPiercingShots,   # Bullets pass through enemies
    puMultiShot,       # Shoots in 3 directions
    puExplosiveBullets,# Bullets explode on impact
    puLifeSteal,       # Gain HP from kills
    puRapidFire,       # Increased fire rate
    puMaxHealth,       # Increase max HP
    puSpeedBoost,      # Permanent speed increase
    puBulletDamage,    # Increased bullet damage
    puBulletSpeed,     # Faster bullets
    puLuckyCoins,      # Enemies drop more coins
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
    puPoisonDamage     # Damage over time effect
  
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
    powerUpTimers*: Table[PowerUpType, float32]
    activePowerUps*: seq[PowerUpType]
    auraRadius*: float32  # Invisible coin collection aura
    doubleShotDelay*: float32  # Timer for double-shot rapid succession

  Enemy* = ref object
    pos*: Vector2f
    vel*: Vector2f
    radius*: float32
    hp*: float32
    maxHp*: float32
    speed*: float32
    damage*: int
    color*: Color
    enemyType*: EnemyType
    isBoss*: bool
    bossType*: BossType
    bossPhase*: BossPhase
    phaseChangeTimer*: float32
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
    targetPos*: Vector2f
    slowTimer*: float32
    slowAmount*: float32
    poisonTimer*: float32
    poisonDamage*: float32
    chainLightningCooldown*: float32
    # New fields for advanced enemies
    attackWarningTimer*: float32
    attackExecuteTimer*: float32
    attackPhase*: int  # 0=patrol, 1=warning, 2=execute
    dashCooldown*: float32
    fakeWarningTimer*: float32
    clonePositions*: seq[Vector2f]
    cloneTimer*: float32

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
    isPentagon*: bool  # Special pentagon-shaped bullets
    hitEnemies*: seq[int]  # Track enemy indices already hit by this bullet

  Coin* = ref object
    pos*: Vector2f
    radius*: float32
    value*: int
    lifetime*: float32

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
    powerUpChoices*: array[3, PowerUp]
    selectedPowerUp*: int
    bossActive*: bool
    bossSpawnTimer*: float32
    cameFromPowerUpSelect*: bool
    gameOverSoundPlayed*: bool
    # Wave-based mode fields
    currentWave*: int
    wavesUntilBoss*: int
    waveEnemiesRemaining*: int
    waveEnemiesTotal*: int
    waveInProgress*: bool

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

proc newLaser*(x, y: float32, direction: int, length, thickness: float32, damage: int, duration: float32): Laser =
  Laser(
    pos: newVector2f(x, y),
    direction: direction,
    length: length,
    thickness: thickness,
    damage: damage,
    lifetime: duration,
    maxLifetime: duration,
    hasHitPlayer: false
  )
