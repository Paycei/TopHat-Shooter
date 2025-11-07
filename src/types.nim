import raylib, math

type
  GameState* = enum
    gsMenu, gsPlaying, gsPaused, gsShop, gsGameOver, gsHelp, gsCountdown, gsPowerUpSelect, gsWaveTransition
  
  GameMode* = enum
    gmWaveBased,      # New primary mode: waves → upgrades → boss → legendary
    gmTimeSurvival    # Old mode: time-based survival

  EnemyType* = enum
    etCircle,    # Normal chasers
    etCube,      # Stationary/slow shooters
    etTriangle,  # Fast dash attackers
    etStar,      # High HP, needs many hits
    etHexagon    # Teleporting chaos enemy

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
    puWallMaster       # Place stronger walls
  
  PowerUpRarity* = enum
    prCommon,          # Normal upgrades after waves
    prLegendary        # Special upgrades after bosses

  PowerUp* = object
    powerType*: PowerUpType
    level*: int  # 1, 2, or 3
    rarity*: PowerUpRarity  # Common or Legendary

  Vector2f* = object
    x*, y*: float32

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
    autoShoot*: bool
    coins*: int
    kills*: int
    walls*: int
    speedBoostTimer*: float32
    invincibilityTimer*: float32
    fireRateBoostTimer*: float32
    magnetTimer*: float32
    powerUps*: seq[PowerUp]  # Active permanent power-ups
    shieldAngle*: float32     # For rotating shield
    killsSinceLastHeal*: int  # For life steal tracking

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
    hexTeleportTimer*: float32  # For hexagon enemy teleports
    entranceTimer*: float32      # For boss entrance animation
    targetPos*: Vector2f         # Target position for entrance

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

  ShopItem* = object
    name*: string
    description*: string
    baseCost*: int
    bought*: int

  Game* = ref object
    state*: GameState
    mode*: GameMode  # New: Track game mode
    player*: Player
    enemies*: seq[Enemy]
    bullets*: seq[Bullet]
    coins*: seq[Coin]
    consumables*: seq[Consumable]
    walls*: seq[Wall]
    particles*: seq[Particle]
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
    powerUpChoices*: array[3, PowerUp]  # Three power-ups to choose from
    selectedPowerUp*: int                # Currently selected card (0-2)
    bossActive*: bool                    # Is a boss currently alive?
    bossSpawnTimer*: float32             # Timer for boss entrance animation
    timerFrozen*: bool                   # Is the game timer frozen?
    frozenTimeDisplay*: float32          # Display value when timer is frozen
    # Wave-based mode fields
    currentWave*: int                    # Current wave number (1-based)
    wavesUntilBoss*: int                 # Waves remaining until boss (3 waves per boss)
    waveEnemiesRemaining*: int           # Enemies left to spawn in current wave
    waveEnemiesTotal*: int               # Total enemies in current wave
    waveInProgress*: bool                # Is a wave currently active?
    waveCompleteTimer*: float32          # Delay before showing upgrade selection

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
