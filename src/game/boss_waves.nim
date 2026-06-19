# Centralized boss wave and coin management
proc startBossWave*(manager: var BossWaveManager) =
  manager.active = true; manager.coinActive = false

proc bossDefeated*(manager: var BossWaveManager) =
  manager.active = false; manager.coinActive = true

proc bossCoinCollected*(manager: var BossWaveManager) =
  manager.coinActive = false

proc clearBossWave*(manager: var BossWaveManager) =
  manager.active = false
  manager.coinActive = false

proc canStartNewWave*(manager: BossWaveManager): bool =
  not manager.active and not manager.coinActive

proc canSpawnBoss*(manager: BossWaveManager): bool =
  not manager.active and not manager.coinActive

proc isBossActive*(manager: BossWaveManager): bool = manager.active

proc isBossCoinActive*(manager: BossWaveManager): bool = manager.coinActive

proc completeBossWave*(game: Game) =
  ## Centralized boss wave completion - handles cleanup, advancement, power-up
  # Captured BEFORE the increment below: this is the wave whose boss was just
  # beaten. getCustomBossNumber needs the boss-wave value (a multiple of 5), so
  # reading it post-increment would return 0 and silently disable the victory.
  let completedWave = game.currentWave
  for enemy in game.enemies:
    spawnExplosionPooled(game.particlePool, enemy.pos.x, enemy.pos.y,
                  Color(r: 255, g: 50, b: 50, a: 255), 15)

  game.enemies = @[]
  game.bullets = @[]
  game.waveEnemiesRemaining = 0
  game.waveInProgress = false
  game.currentWave += 1
  game.wavesUntilBoss -= 1

  if game.comebackBonusActive and game.currentWave >= game.comebackEndWave:
    removeComebackBonus(game)

  # Golden pulse on boss defeat
  spawnWavePulse(game.osBackground,
    game.screenWidth.float32 / 2.0,
    game.screenHeight.float32 / 2.0,
    Color(r: 255, g: 215, b: 0, a: 255))

  if game.wavesUntilBoss <= 0:
    game.wavesUntilBoss = 4  # Next boss in 5 waves

  # Reset combo after boss wave
  game.dopamine.comboSystem.killCount = 0
  game.dopamine.comboSystem.bonusCoins = 0
  game.dopamine.comboSystem.comboWindow = 4.0
  game.dopamine.comboSystem.displayTimer = 0
  game.dopamine.comboSystem.waveKillCount = 0
  game.dopamine.comboSystem.waveComboBreaks = 0

  # Calculate final wave stats for celebration
  calculateAccuracy(game.dopamine.waveStats)

  # Trigger wave celebration AFTER boss is defeated (every boss wave = every 5th wave)
  # Use currentWave - 1 because currentWave was just incremented above
  startCelebration(game.dopamine.waveCelebration, game.currentWave - 1, game.dopamine.waveStats)

  game.powerUpChoices = generatePowerUpChoices(game.player, true)
  game.selectedPowerUp = 0
  initPowerUpRollAnimation(game)

  # Final boss (boss tier 12 = wave 60) beaten for the first time: show the
  # one-time victory screen instead of the power-up select. The power-up reward
  # stays queued, so "Continue Endless" re-arms the roll and drops the player
  # straight into the selection. After this, hasWonGame keeps boss 12 (which
  # repeats every 5 waves in endless) from re-triggering the screen.
  if getCustomBossNumber(completedWave) == 12 and not game.hasWonGame:
    game.hasWonGame = true
    # First-ever victory unlocks the secret kernel tophat cosmetic. It is
    # equipped by default (and immediately, so it shows in endless) and can be
    # toggled off in the shop's SECRET tab.
    if runIsLegit(game) and not globalSettings.isNil and not globalSettings.kernelTophatUnlocked:
      globalSettings.kernelTophatUnlocked = true
      globalSettings.kernelTophatEquipped = true
      globalSettings.cheaterHatEquipped = false
      discard saveSettings(globalSettings)
      game.tophatJustUnlocked = true
      game.player.wearsTophat = true
      game.player.wearsCheaterHat = false
  
  # Unlock Roguelite when the wave-20 boss (custom boss number 4) is defeated
  if getCustomBossNumber(completedWave) == 4:
    if runIsLegit(game) and not globalSettings.isNil and not globalSettings.rogueliteUnlocked:
      globalSettings.rogueliteUnlocked = true
      discard saveSettings(globalSettings)
    game.selectedVictoryButton = 0
    playSound(stWaveComplete)
    # First-ever victory plays the one-time endgame cinematic; it hands off to
    # the "system secured" screen when it ends. If the player has already seen
    # the outro (e.g. a later session), drop straight onto the victory screen.
    if not globalSettings.isNil and not globalSettings.hasSeenEnding:
      game.state = gsEndgameCinematic
    else:
      game.state = gsVictory
  else:
    game.state = gsPowerUpSelect

proc spawnConfiguredBoss(game: Game, bossDifficulty: float32, bossBlockWave: int) =
  let bossNumber = getCustomBossNumber(bossBlockWave)

  # Check if this is Boss #7 (3D boss)
  if bossNumber == 13: # Disabled for now (7)
    game.transitioning = true
    game.fadeAlpha = 0.0
    game.bossWaveManager.startBossWave()
    playSound(stBossSpawn)
  else:
    # Schedule a pending boss spawn with a short warning period
    let pending = spawnBoss(game.screenWidth, game.screenHeight,
              bossDifficulty, game.bossCount, bossBlockWave)
    game.pendingBoss = pending
    game.pendingBossTimer = 0.2  # Show warning for 0.2s before adding boss to world
    # Mark boss wave active so UI shows boss-related hints during the warning
    game.bossWaveManager.startBossWave()

# Unified aura configuration and rendering system

type
  AuraVisualStyle = enum
    avsFlames         # Fire aura - rising flames and wisps
    avsLightning      # Lightning aura - electric arcs and bolts
    avsPoison         # Poison aura - toxic bubbles and fog
    avsWind           # Wind aura - swirling air currents
    avsArcane         # Arcane aura - orbiting runes and sparkles
    avsBlood          # Blood aura - dripping blood and mist

type
  AuraConfig = object
    radius: float32
    coreColor: Color
    ringColor: Color
    borderColor: Color
    pulseSpeed: float32
    visualStyle: AuraVisualStyle

