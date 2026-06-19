proc cleanupGame*(game: Game) =
  ## Clean up game resources before creating a new game
  ## This prevents memory leaks and performance issues when returning to menu

  # Don't cleanup Discord client - it's global and persists across sessions
  # Just clear the reference
  game.discordClient = nil

  # Clear all game objects to help garbage collector
  game.enemies = @[]
  game.bullets = @[]
  game.coins = @[]
  game.consumables = @[]
  game.walls = @[]
  game.attackWarnings = @[]
  game.lasers = @[]
  game.meteorites = @[]
  game.damageNumbers = @[]
  game.currencyIndicators = @[]

  # Clear player rotating orbs
  if not game.player.isNil:
    game.player.rotatingOrbs = @[]

proc newGame*(screenWidth, screenHeight: int32, playerSkin: int = 0, bulletSkin: int = 0, playerShape: int = 0, particleSkin: int = 0, bulletShape: int = 0): Game =
  resetIntegritySnapshot()  # SACE: fresh last-good baseline; repopulates on first scanned frame
  let defaultMode = gmWaveBased  # Default to wave-based mode
  let modeDef = getGameModeDefinition(defaultMode)

  result = Game(
    state: gsPlaying,
    mode: defaultMode,
    player: newPlayer(screenWidth.float32 / 2, screenHeight.float32 / 2),
    enemies: @[],
    bullets: @[],
    bulletIdCounter: 0,  # Start at 0, increment with each bullet that needs tracking
    coins: @[],
    consumables: @[],
    walls: @[],
    particlePool: newParticlePool(2000),
    attackWarnings: @[],
    lasers: @[],
    meteorites: @[],
    damageNumbers: @[],
    currencyIndicators: @[],
    perkIndicators: @[],
    time: 0,
    spawnTimer: 0,
    bossTimer: 60.0,
    bossCount: 0,
    difficulty: 0,
    screenWidth: screenWidth,
    screenHeight: screenHeight,
    shopItems: initShopItems(),
    selectedShopItem: 0,
    menuSelection: 0,
    selectedPowerUp: 0,
    recentPowerUp: PowerUp(powerType: puDoubleShot, level: 0, rarity: prCommon),
    recentPowerUpTimer: 0.0,
    recentPowerUpMaxTimer: 0.0,
    countdownTimer: 0.3,  # Start with ready countdown
    waveClearedTimer: 0,
    rerollCost: 0,  # Initialize reroll cost (set properly when entering power-up selection)
    bossWaveManager: BossWaveManager(active: false, coinActive: false),
    bossSpawnTimer: 0,
    pendingBoss: nil,
    pendingBossTimer: 0.0,
    cameFromPowerUpSelect: false,
    gameOverSoundPlayed: false,
    # Wave-based mode fields
    currentWave: 1,
    wavesUntilBoss: 4,  # Boss appears at waves 5, 10, 15, etc.
    waveEnemiesRemaining: 0,
    waveEnemiesTotal: 0,
    waveInProgress: false,
    waveStartTime: 0.0,
    # Cheat tracking
    cheatsUsed: false,  # Reset to false at start of each run
    # Mouse tracking for menu navigation
    lastMousePos: newVector2f(0, 0),
    mouseMovedRecently: false,
    keyboardUsedRecently: false,
    # State tracking for settings return
    previousState: gsMenu,  # Default to menu
    # Enemy ID counter for unique tracking
    nextEnemyId: 0,  # Start at 0, increment with each enemy created
    # Statistics menu tab
    statsMenuTab: 0,  # 0 = Lifetime, 1 = Last Run
    selectedRogueliteStarter: 0,
    selectedRogueliteHeat: RogueliteMinHeat,
    rogueliteHeatPulseTimer: 0.0,
    rogueliteHeatPulseDirection: 0,
    selectedRogueliteTheme: 0,
    # OS-Style Visual System
    osBackground: newOSBackground(),
    osHUD: newOSHUD(),
    pauseMenuTab: tmtProcesses,  # Default to Processes tab in task manager
    selectedGameOverButton: 0,  # Default to Restart button
    deathSequenceTimer: 0.0,
    deathSequenceFadeAlpha: 0.0,
    deathSequenceTimeScale: 1.0,
    dopamine: newDopamineState()
  )

  initEnhancedDopamine(result.dopamine)

  # Apply gamemode-specific starting values
  result.player.coins = modeDef.playerStartCoins

  # Apply player skin from settings
  result.player.skinType = playerSkin
  result.player.bulletSkinType = bulletSkin
  result.player.shapeType = playerShape
  result.player.bulletShapeType = bulletShape
  result.player.particleSkinType = particleSkin
  # Secret cosmetics: active only while both unlocked and enabled in the shop
  let cheaterHatActive = not globalSettings.isNil and
    globalSettings.cheaterHatUnlocked and globalSettings.cheaterHatEquipped
  result.player.wearsTophat = not globalSettings.isNil and not cheaterHatActive and
    globalSettings.kernelTophatUnlocked and globalSettings.kernelTophatEquipped
  result.player.wearsCheaterHat = cheaterHatActive
  result.player.hasOrbitalCube = not globalSettings.isNil and
    globalSettings.orbitalCubeUnlocked and globalSettings.orbitalCubeEquipped
  result.player.cubeSkinType = if globalSettings.isNil: 0 else: globalSettings.cubeSkin

  # Note: initializeRunTracking is called explicitly when starting a game
  # (not in sandbox mode) to ensure correct mode is tracked

proc setGameMode*(game: Game, mode: GameMode) =
  ## Changes the game mode and applies mode-specific settings
  game.mode = mode
  let modeDef = getGameModeDefinition(mode)

  # Apply mode-specific starting values
  game.player.coins = modeDef.playerStartCoins
  game.bossTimer = if isTimeSurvivalMode(mode): TIME_SURVIVAL_BOSS_INTERVAL else: 0.0
  game.bossWaveManager.clearBossWave()

  # Reset wave-specific state if not using waves
  if not modeDef.usesWaves:
    game.currentWave = 1
    game.waveInProgress = false
    game.waveEnemiesRemaining = 0
    game.wavesUntilBoss = 4

