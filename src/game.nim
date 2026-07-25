import raylib, rlgl, random, math, strutils, algorithm
import types, settings, save_system, player, enemy, bullet, consumable, coin, xp_orb, wall, boss_definitions, particle, particle_pool, particle_types, effects, powerup, sound, d_systems, d_visuals, d_enhancements, survival, render_context, roguelite, dungeon, gamemode_definitions, run_statistics, statistics, enemy_config, enemy_helpers, localization, game3d/game_3d, ui/os_shop, ui/os_background, ui/os_hud, ui/os_debug_panel, ui/os_combined_hud, ui/os_system_screens, ui/os_enemy_labels, ui/ui_constants, ui/ui_helpers, boss_weakpoints

# Gameplay subsystem modules. game.nim is the top of the dependency DAG.

import game/combat, game/auras, game/bullets, game/death, game/bosses, game/orbitals, game/shooting, run_save, suspend, utils

const ECHO_MAX_SPAWNS = 5  # Cap echo trail bullets per parent so piercing/ricochet/etc. can't spawn an unbounded trail
const BOSS_WAVE_SPAWN_MULTIPLIER = 0.25  # 25% of normal spawn
const TIME_SURVIVAL_BOSS_INTERVAL = 90.0  # survival boss every 1.5 min
const SurvivalDifficultyRamp = 45.0'f32   # seconds of survival per +1 difficulty

# Spatial-grid acceleration (SpatialGrid is in enemy_helpers.nim): buckets
# game.enemies by screen cell so the proximity loops run in ~O(n) instead of
# O(bullets*enemies). Module-global so steady-state rebuilds allocate nothing.
const GRID_CELL_SIZE = 96.0'f32  # px. Comfortably exceeds any hit radius, so the
                                 # neighbourhood query is a non-lossy superset,
                                 # while staying small enough that buckets are sparse.
const GRID_MARGIN = 200.0'f32    # world bounds extend this far past the screen so
                                 # enemies spawning just off-screen still bin exactly.
const GRID_MIN_ENEMIES = 24      # below this the per-bullet grid query + sort costs
                                 # more than a plain full scan, so the bullet loop
                                 # falls back to checking all enemies (it's already
                                 # cheap at low counts, and the frame has headroom).

var enemyGrid: SpatialGrid
var gridBossIndices: seq[int]       # bosses are always force-checked: their weak-point
                                    # targets can sit beyond the body hit radius.
var gridMaxEnemyRadius: float32     # max enemy.radius          -> bullet-hit query reach
var gridMaxCollisionRadius: float32 # max enemy.collisionRadius -> separation query reach
var gridCandidates: seq[int]        # reused per-bullet candidate buffer (sorted+deduped)

proc rebuildEnemyGrid(game: Game) =
  ## Re-bucket every enemy and recompute the per-frame query reaches + boss list
  ## in a single O(enemy count) pass. The resulting indices are valid only until
  ## game.enemies is next mutated, so rebuild *immediately* before a query batch.
  enemyGrid.rebuild(game.enemies, GRID_CELL_SIZE,
                    -GRID_MARGIN, -GRID_MARGIN,
                    game.screenWidth.float32 + GRID_MARGIN,
                    game.screenHeight.float32 + GRID_MARGIN)
  gridBossIndices.setLen(0)
  gridMaxEnemyRadius = 0.0'f32
  gridMaxCollisionRadius = 0.0'f32
  for idx in 0 ..< game.enemies.len:
    let e = game.enemies[idx]
    if e.radius > gridMaxEnemyRadius: gridMaxEnemyRadius = e.radius
    if e.collisionRadius > gridMaxCollisionRadius: gridMaxCollisionRadius = e.collisionRadius
    if e.isBoss: gridBossIndices.add(idx)

# Boss wave manager accessors, hoisted above lifecycle/waves which call them.
proc startBossWave(manager: var BossWaveManager) =
  manager.active = true; manager.coinActive = false

proc bossDefeated*(manager: var BossWaveManager) =
  manager.active = false; manager.coinActive = true

proc clearBossWave*(manager: var BossWaveManager) =
  manager.active = false
  manager.coinActive = false

proc canStartNewWave*(manager: BossWaveManager): bool =
  not manager.active and not manager.coinActive

proc canSpawnBoss*(manager: BossWaveManager): bool =
  manager.canStartNewWave()

proc isBossActive*(manager: BossWaveManager): bool = manager.active

proc isBossCoinActive*(manager: BossWaveManager): bool = manager.coinActive

# Lifecycle
proc cleanupGame*(game: Game) =
  ## Release game object references before creating a new game.
  # Only drop the Discord reference - the client is global and persists across sessions.
  game.discordClient = nil
  game.enemies = @[]
  game.bullets = @[]
  game.coins = @[]
  game.xpOrbs = @[]
  game.pendingLevelDrafts = 0
  game.survivalLevelDraftActive = false
  game.survivalTime = 0
  game.consumables = @[]
  game.walls = @[]
  game.attackWarnings = @[]
  game.lasers = @[]
  game.meteorites = @[]
  game.damageNumbers = @[]
  game.currencyIndicators = @[]

  if not game.player.isNil:
    game.player.rotatingOrbs = @[]

proc applyLevelUpStatBoost*(player: Player) =
  ## Roguelite per-level reward: a small balanced stat bundle plus a partial heal.
  const LevelMaxHpGain = 2.0'f32      # +max HP (radius/aura scale follow via refreshPlayerSize)
  const LevelDamageMult = 1.04'f32    # +4% damage, compounding
  const LevelHealFraction = 0.25'f32  # heal a quarter of the (new) max HP
  player.maxHp += LevelMaxHpGain
  player.damage *= LevelDamageMult
  heal(player, player.maxHp * LevelHealFraction)

proc bankRunLevelUps*(game: Game) =
  ## Cash in any levels the accumulated XP affords in one pass (multi-level),
  ## apply the stat boosts immediately, and queue one power-up draft per level
  ## gained. The drafts themselves are opened by checkPendingLevelDraft on
  ## subsequent frames, so this proc never changes game.state.
  ##
  ## Roguelite calls this once per ROOM clear (levels never cash in mid-fight);
  ## time-survival calls it every frame, so survival levels pop the instant the
  ## XP bar fills (Vampire-Survivors style).
  if game.mode notin {gmRoguelite, gmTimeSurvival}: return
  # Survival: freeze leveling during a boss fight. The XP bar may fill to 100%,
  # but the level-up (and its draft) is deferred until the boss is dead. XP earned
  # past the threshold while the boss lives is discarded, the bar caps at full, so
  # at most one level is banked the instant the boss falls.
  if isTimeSurvivalMode(game.mode) and game.bossWaveManager.isBossActive():
    game.player.xp = min(game.player.xp, game.player.xpToNextLevel)
    return
  var levelsGained = 0
  while game.player.xp >= game.player.xpToNextLevel:
    game.player.xp -= game.player.xpToNextLevel
    inc game.player.rogueliteLevel
    game.player.xpToNextLevel = xpRequiredForLevel(game.player.rogueliteLevel)
    applyLevelUpStatBoost(game.player)
    inc levelsGained
  if levelsGained > 0:
    game.pendingLevelDrafts += levelsGained
    # Juice: one sound, burst, and banner summarizing the room's level gains.
    playSound(stPowerUp)
    spawnExplosionPooled(game.particlePool, game.player.pos.x, game.player.pos.y,
                         Color(r: 120, g: 255, b: 180, a: 255), 24)
    showPerk(game, newVector2f(game.player.pos.x, game.player.pos.y - 28),
             t("roguelite_level_up") & " " & $game.player.rogueliteLevel,
             Color(r: 120, g: 255, b: 180, a: 255))

proc checkPendingLevelDraft*(game: Game) =
  ## Opens one queued level-up draft, but only in normal play (gsPlaying), never
  ## while a modal is up. Opening the queued drafts one-per-frame chains
  ## multi-level-ups: each draft pauses the sim, the player picks,
  ## continueAfterDraft returns to gsPlaying, and the next frame opens the
  ## following draft. Because the sim is frozen between consecutive drafts, the
  ## whole stack resolves before the player can re-enter combat.
  ##
  ## Survival shares this path but flags the draft (survivalLevelDraftActive) so
  ## continueAfterDraft routes back to play rather than the post-boss shop, and
  ## draws from all power families since survival has no per-run unlock set.
  if game.mode notin {gmRoguelite, gmTimeSurvival} or game.state != gsPlaying: return
  # Survival: never open a level-up draft while a boss is alive, leveling is
  # deferred until the fight ends (matches the XP freeze in bankRunLevelUps).
  if isTimeSurvivalMode(game.mode) and game.bossWaveManager.isBossActive(): return
  if game.pendingLevelDrafts <= 0: return
  dec game.pendingLevelDrafts
  let families = if game.mode == gmRoguelite:
    unlockedFamilySet(game.rogueliteProfile)
  else:
    {rpfCore..rpfBlood}
  game.powerUpChoices = generatePowerUpChoices(game.player, false, families, game.mode)
  game.selectedPowerUp = 0
  initPowerUpRollAnimation(game)
  initializeRerollCost(game)
  if isTimeSurvivalMode(game.mode):
    game.survivalLevelDraftActive = true
    saveRunState(game)  # Survival autosave checkpoint at each level draft.
    deleteSuspendSnapshot()  # Boundary reached: the pre-exit snapshot is stale.
  game.state = gsPowerUpSelect

proc newGame*(screenWidth, screenHeight: int32, playerSkin: int = 0, bulletSkin: int = 0, playerShape: int = 0, particleSkin: int = 0, bulletShape: int = 0): Game =
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
    wavesUntilBoss: BossWaveInterval - 1,  # Boss appears at waves 5, 10, 15, etc.
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
  game.survivalTime = 0
  game.bossWaveManager.clearBossWave()

  # Reset wave-specific state if not using waves
  if not modeDef.usesWaves:
    game.currentWave = 1
    game.waveInProgress = false
    game.waveEnemiesRemaining = 0
    game.wavesUntilBoss = BossWaveInterval - 1

# Waves
proc calculateWaveEnemyCount(waveNumber: int): int =
  ## Enemy count per wave: uncapped but decelerating, pairing with the compounding
  ## late-game HP buff in spawnWaveEnemies (few beefy threats, not a mowable swarm).
  ##   wave 1 -> 8, wave 10 -> ~19, wave 40 -> ~35, wave 100 -> ~55
  result = int(8 + 3.0 * pow(float(waveNumber - 1), 0.6))

proc startWave*(game: Game) =
  # Death-surviving block checkpoint, written at the START of each boss block
  # (waves 5, 9, 13, ... for a BossWaveInterval of 4 -- wavesUntilBoss is only
  # back at its full value on a block's first wave). Two reasons for the timing:
  #   * it runs AFTER the previous boss's reward draft and shop visit, so those
  #     are part of the checkpoint instead of being lost on a Continue;
  #   * it runs BEFORE the per-wave stat scaling below, so resuming replays this
  #     exact startWave call once rather than compounding the scaling.
  if game.mode == gmWaveBased and game.currentWave > 1 and
     game.wavesUntilBoss == BossWaveInterval - 1:
    saveBlockCheckpoint(game)

  game.waveInProgress = true
  game.waveStartTime = game.time  # Track when this wave started
  # Visual pulse ring, cyan for normal waves, orange for boss-lead waves
  let wavePulseColor = if game.wavesUntilBoss == 0:
    Color(r: 255, g: 160, b: 0, a: 255)
  else:
    Color(r: 0, g: 200, b: 255, a: 255)
  spawnWavePulse(game.osBackground,
    game.screenWidth.float32 / 2.0,
    game.screenHeight.float32 / 2.0,
    wavePulseColor)
  var waveEnemyCount = calculateWaveEnemyCount(game.currentWave)

  # Apply boss wave reduction if this is a boss wave
  if game.wavesUntilBoss == 0:
    waveEnemyCount = (waveEnemyCount.float32 * BOSS_WAVE_SPAWN_MULTIPLIER).int

  game.waveEnemiesTotal = waveEnemyCount
  game.waveEnemiesRemaining = waveEnemyCount
  game.spawnTimer = 0

  # Mark wave start for combo tracking
  startWaveCombo(game.dopamine.comboSystem)

  # PLAYER SCALING: Multiply current stats by 1.2% per wave (preserves shop purchases and power-ups)
  # This applies scaling multiplicatively to whatever stats the player has built up
  let waveScaling: float32 = 1.012  # 1.2% increase per wave

  # Apply multiplicative scaling to current stats (preserves all upgrades)
  game.player.maxHp *= waveScaling
  game.player.hp = min(game.player.hp * waveScaling, game.player.maxHp)  # Scale current HP but cap at maxHp
  game.player.damage *= waveScaling
  game.player.speed *= waveScaling
  game.player.baseSpeed *= waveScaling
  game.player.bulletSpeed = multiplyBulletSpeedDiminished(game.player.bulletSpeed, waveScaling)
  # Fire rate gets faster (lower number = faster), so we divide instead of multiply
  game.player.fireRate /= waveScaling

  # Reset all active ability cooldowns for new wave
  game.player.timeWarpUsesThisWave = 0
  game.player.timeWarpCooldown = 0
  game.player.phaseShiftCooldown = 0
  game.player.bloodPactCooldown = 0
  game.player.conduitCooldown = 0
  game.player.aftershockCooldown = 0
  game.player.novaCooldown = 0
  # Release any frozen Nova bullets before resetting
  if game.player.novaActive:
    for bullet in game.bullets:
      if bullet.isFrozenByNova and bullet.fromPlayer:
        bullet.vel = bullet.vel * 1.5
        bullet.isFrozenByNova = false
        bullet.isFromNova = true  # Mark for damage tracking
    game.player.novaActive = false
    game.player.novaFreezeTimer = 0
  # Reset Celestial Veil charges for new wave
  if hasPowerUp(game.player, puCelestialVeil):
    game.player.celestialVeilCharges = 2

proc spawnWaveEnemies*(game: Game, count: int) =
  # Spawn multiple enemies at once
  for _ in 0..<count:
    if game.waveEnemiesRemaining > 0:
      let wave: int = game.currentWave
      let roll: int = rand(100)
      var enemyType: EnemyType

      # NEW ENEMY EVERY 5 WAVES with high spawn rate for that enemy
      if wave <= 5:
        # Waves 1-5: Only CIRCLES
        enemyType = etCircle

      elif wave <= 10:
        # Waves 6-10: Introduce PENTAGON
        if roll < 40: enemyType = etPentagon
        elif roll < 75: enemyType = etCircle
        else: enemyType = etCircle  # Keep it simple

      elif wave <= 15:
        # Waves 11-15: Introduce TRIANGLE
        if roll < 40: enemyType = etTriangle
        elif roll < 65: enemyType = etCircle
        else: enemyType = etPentagon

      elif wave <= 20:
        # Waves 16-20: Introduce CUBE
        if roll < 25: enemyType = etCube
        elif roll < 40: enemyType = etCircle
        elif roll < 65: enemyType = etPentagon
        else: enemyType = etTriangle

      elif wave <= 25:
        # Waves 21-25: Introduce STAR, but keep the first tanky roster step gentler
        if roll < 12: enemyType = etStar
        elif roll < 28: enemyType = etCircle
        elif roll < 48: enemyType = etCube
        elif roll < 68: enemyType = etPentagon
        else: enemyType = etTriangle

      elif wave <= 30:
        # Waves 26-30: Introduce CROSS with a shallower composition swing
        if roll < 15: enemyType = etCross
        elif roll < 30: enemyType = etCircle
        elif roll < 45: enemyType = etCube
        elif roll < 57: enemyType = etStar
        elif roll < 75: enemyType = etPentagon
        else: enemyType = etTriangle

      elif wave <= 35:
        # Waves 31-35: Introduce DIAMOND, circles removed from wave 30+
        if roll < 16: enemyType = etDiamond
        elif roll < 33: enemyType = etCube
        elif roll < 47: enemyType = etStar
        elif roll < 63: enemyType = etCross
        elif roll < 80: enemyType = etPentagon
        else: enemyType = etTriangle

      elif wave <= 40:
        # Waves 36-40: Introduce OCTAGON
        if roll < 17: enemyType = etOctagon
        elif roll < 33: enemyType = etCube
        elif roll < 44: enemyType = etStar
        elif roll < 60: enemyType = etCross
        elif roll < 74: enemyType = etDiamond
        elif roll < 85: enemyType = etPentagon
        else: enemyType = etTriangle

      elif wave <= 45:
        # Waves 41-45: Introduce HEXAGON
        if roll < 18: enemyType = etHexagon
        elif roll < 25: enemyType = etCube
        elif roll < 35: enemyType = etStar
        elif roll < 55: enemyType = etCross
        elif roll < 73: enemyType = etDiamond
        elif roll < 81: enemyType = etOctagon
        elif roll < 89: enemyType = etPentagon
        else: enemyType = etTriangle

      elif wave <= 50:
        # Waves 46-50: Introduce TRICKSTER
        if roll < 20: enemyType = etTrickster
        elif roll < 33: enemyType = etCube
        elif roll < 39: enemyType = etStar
        elif roll < 48: enemyType = etCross
        elif roll < 56: enemyType = etDiamond
        elif roll < 64: enemyType = etOctagon
        elif roll < 72: enemyType = etHexagon
        elif roll < 85: enemyType = etPentagon
        else: enemyType = etTriangle

      elif wave <= 55:
        # Waves 51-55: Introduce PHANTOM
        if roll < 15: enemyType = etPhantom
        elif roll < 26: enemyType = etCube
        elif roll < 35: enemyType = etStar
        elif roll < 43: enemyType = etCross
        elif roll < 51: enemyType = etDiamond
        elif roll < 59: enemyType = etOctagon
        elif roll < 67: enemyType = etHexagon
        elif roll < 80: enemyType = etTrickster
        elif roll < 99: enemyType = etPentagon
        else: enemyType = etSniper

      else:
        # Waves 56+: Introduce MAGE + balanced roster
        if roll < 10: enemyType = etMage
        elif roll < 20: enemyType = etCube
        elif roll < 30: enemyType = etStar
        elif roll < 40: enemyType = etCross
        elif roll < 50: enemyType = etDiamond
        elif roll < 60: enemyType = etOctagon
        elif roll < 70: enemyType = etHexagon
        elif roll < 80: enemyType = etTrickster
        elif roll < 90: enemyType = etPhantom
        elif roll < 99: enemyType = etTriangle
        else: enemyType = etSniper

      # Wave enemies now use a softer difficulty slope so midgame HP does not outrun builds.
      # SMOOTH LATE-GAME DECELERATION: the stat curves (base HP pow, the per-wave
      # HP/damage multipliers below, and elite stat bonuses) compound on the wave
      # number, so late waves were outpacing player growth. Feed them a smoothly
      # compressed wave instead: w / (1 + w/150) tracks the raw wave almost 1:1
      # early (wave 5 -> 4.8), then decelerates continuously with no threshold or
      # kink (wave 45 -> ~34.6, wave 60 -> ~42.9), staying strictly increasing
      # forever for endless play. Elite *chance* and spawn counts still use the
      # raw wave, so the late game stays busy, just not spongy.
      let statWave: float32 = wave.float32 / (1.0'f32 + wave.float32 / 150.0'f32)
      let baseDifficulty = (statWave - 1.0'f32) / 4.0

      let (x, y) = randomEdgeSpawnPos(game.screenWidth, game.screenHeight)
      let enemy = newEnemy(x, y, baseDifficulty, enemyType, game)

      # CONTINUOUS LATE-GAME SCALING:
      # The player's damage compounds every wave (startWave's *= 1.012) on top of
      # shop/power-up multipliers, so the enemy HP curve naturally falls behind and
      # late-wave enemies get one-tapped before they ever threaten the player.
      # Rather than a hard wave threshold, fold in a smooth per-wave multiplier that
      # compounds exactly like the player's own growth: a fraction of a percent per
      # wave, invisible early (a wave-3 circle gains <0.1 HP) and a large buff late,
      # with no threshold, ceiling, or kink anywhere. Wave mode only, roguelite and
      # survival scale through their own spawn paths.
      block:
        # Tankier: ~1.5% extra HP per wave, compounding. Stars are hit-count based
        # (placeholder maxHp), so their durability is left to requiredHits.
        if enemy.enemyType != etStar:
          let hpScale = pow(1.015'f32, statWave)
          enemy.maxHp *= hpScale
          enemy.hp *= hpScale
        # Stronger: ~0.5% extra damage per wave so the survivors that now reach the
        # player keep pace as genuine threats instead of harmless chip damage.
        let dmgScale = pow(1.005'f32, statWave)
        enemy.contactDamage *= dmgScale
        enemy.rangedDamage *= dmgScale

        # Softer SIZE growth (wave mode only): getScaledEnemyStats grows the
        # radius LINEARLY (`difficulty * 1.5`), so by the late game enemies
        # balloon into huge, easy-to-hit blobs. Re-shape just the wave-driven
        # girth into a decelerating curve and subtract the difference, so high
        # waves keep adding size ever more slowly. Early waves are untouched
        # (the gap is ~0 until the midgame); a floor of half the original radius
        # guards against over-shrinking on the very largest enemies.
        let linearGirth = baseDifficulty * 1.5'f32
        let softGirth = pow(max(baseDifficulty, 0.0'f32), 0.6'f32) * 1.5'f32
        let girthCut = max(0.0'f32, linearGirth - softGirth)
        enemy.radius = max(enemy.radius - girthCut, enemy.radius * 0.5'f32)
        enemy.collisionRadius = enemy.radius * 0.4'f32

      # Elite chance still rolls on the raw wave; stat bonuses use the softened wave.
      makeElite(enemy, wave, scalingWave = statWave.int)
      game.enemies.add(enemy)
      game.waveEnemiesRemaining -= 1

proc spawnDungeonEnemies(game: Game, count: int) =
  ## Roguelite dungeon rooms: spawn from the floor theme's roster, scaled by
  ## floor/room depth/heat instead of the wave number.
  let run = game.rogueliteRun
  if run == nil or run.floor == nil:
    return
  let room = currentDungeonRoom(run)
  if room == nil:
    return
  let baseDifficulty = dungeonEnemyDifficulty(run, room)
  let eliteRoll = dungeonEliteRoll(run, room)
  for _ in 0..<count:
    if game.waveEnemiesRemaining <= 0:
      break
    let enemyType = rollEncounterEnemyType(run, room)
    let (x, y) = randomEdgeSpawnPos(game.screenWidth, game.screenHeight)
    let enemy = newEnemy(x, y, baseDifficulty, enemyType, game)
    # Compress advanced types' stats toward the room threat before elite
    # bonuses so elites scale relative to the tuned baseline. The elite roll
    # only drives the CHANCE; stat magnitudes follow the room's wave
    # equivalent so elite-room guarantees don't inflate elite damage.
    tuneDungeonEnemyStats(enemy, run, room)
    makeElite(enemy, eliteRoll,
              scalingWave = int(dungeonRoomWaveEquivalent(run, room)))
    var visualThreat = 1 + (run.floorNumber - 1) + (run.heat div 2) + run.endlessLoop
    if room.kind == drkElite:
      visualThreat += 1
    if enemy.isElite:
      visualThreat += 1
    if enemy.contactDamage >= game.player.maxHp * 0.45:
      visualThreat = max(visualThreat, 4)
    enemy.threatLevel = max(enemy.threatLevel, clamp(visualThreat, 1, 5))
    game.enemies.add(enemy)
    game.waveEnemiesRemaining -= 1

proc checkWaveComplete(game: Game): bool =
  # Wave is complete when all enemies are defeated, none remain to spawn,
  # AND boss coin has been collected (if there was one)
  return game.waveEnemiesRemaining == 0 and game.enemies.len == 0 and not game.bossWaveManager.isBossCoinActive()

# Boss waves
# (BossWaveManager accessors are hoisted above the lifecycle section so the
# lifecycle/wave procs that call them are defined after their definitions.)
proc completeBossWave*(game: Game) =
  ## Centralized boss wave completion - handles cleanup, advancement, power-up
  # Captured BEFORE the increment below: this is the wave whose boss was just
  # beaten. getCustomBossNumber needs the boss-wave value (a multiple of
  # BossWaveInterval), so reading it post-increment would return 0 and silently
  # disable the victory.
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
    game.wavesUntilBoss = BossWaveInterval - 1  # Next boss BossWaveInterval waves later

  # (The death-surviving block checkpoint is NOT written here: at this point the
  # boss reward draft and the between-wave shop have not happened yet. It is
  # written at the top of startWave for the block's first wave instead, so the
  # checkpoint carries the reward power-up and any shop purchases.)

  # Reset combo after boss wave
  game.dopamine.comboSystem.killCount = 0
  game.dopamine.comboSystem.bonusCoins = 0
  game.dopamine.comboSystem.comboWindow = 4.0
  game.dopamine.comboSystem.displayTimer = 0
  game.dopamine.comboSystem.waveKillCount = 0
  game.dopamine.comboSystem.waveComboBreaks = 0

  # Calculate final wave stats for celebration
  calculateAccuracy(game.dopamine.waveStats)

  # Trigger wave celebration AFTER boss is defeated (every boss wave = every BossWaveInterval-th wave)
  # Use currentWave - 1 because currentWave was just incremented above
  startCelebration(game.dopamine.waveCelebration, game.currentWave - 1, game.dopamine.waveStats)

  game.powerUpChoices = generatePowerUpChoices(game.player, true, mode = game.mode)
  game.selectedPowerUp = 0
  initPowerUpRollAnimation(game)

  # Final boss (boss number 12 = wave 60) beaten for the first time: show the
  # one-time victory screen instead of the power-up select. The power-up reward
  # stays queued, so "Continue Endless" re-arms the roll and drops the player
  # straight into the selection. After this, hasWonGame keeps boss 12 (which
  # repeats every 5 waves in endless) from re-triggering the screen.
  if getCustomBossNumber(completedWave) == 12 and not game.hasWonGame:
    game.hasWonGame = true
    deleteRunSave()  # Run is won: no longer resumable.
    deleteBlockCheckpoint()  # Won run: drop the block checkpoint too.
    deleteSuspendSnapshot()  # Drop the exact snapshot too.
    # First-ever victory unlocks the secret kernel tophat cosmetic. It is
    # equipped by default (and immediately, so it shows in endless) and can be
    # toggled off in the shop's SECRET tab.
    if not game.cheatsUsed and not globalSettings.isNil and not globalSettings.kernelTophatUnlocked:
      globalSettings.kernelTophatUnlocked = true
      globalSettings.kernelTophatEquipped = true
      globalSettings.cheaterHatEquipped = false
      discard saveSettings(globalSettings)
      game.tophatJustUnlocked = true
      game.player.wearsTophat = true
      game.player.wearsCheaterHat = false
    game.selectedVictoryButton = 0
    playSound(stWaveComplete)
    # First-ever victory plays the one-time endgame cinematic; it hands off to
    # the "system secured" screen when it ends. If the player has already seen
    # the outro (e.g. a later session), drop straight onto the victory screen.
    if not globalSettings.isNil and not globalSettings.hasSeenEnding:
      game.state = gsEndgameCinematic
    else:
      game.state = gsVictory

  # Unlock Roguelite when the wave-16 boss (custom boss number 4) is defeated
  elif getCustomBossNumber(completedWave) == 4:
    if not game.cheatsUsed and not globalSettings.isNil and not globalSettings.rogueliteUnlocked:
      globalSettings.rogueliteUnlocked = true
      discard saveSettings(globalSettings)
      game.pendingToasts.add(t(tkGameModeUnlocked) & " " & t(tkRogueliteUnlockedNotif))
    game.state = gsPowerUpSelect

  else:
    game.state = gsPowerUpSelect

proc spawnConfiguredBoss*(game: Game, bossDifficulty: float32, bossBlockWave: int) =
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

# Update
proc currentBossArenaWave(game: Game): int =
  for enemy in game.enemies:
    if enemy.isBoss:
      return max(BossWaveInterval, enemy.bossDefinitionID * BossWaveInterval)

  if game.bossWaveManager.isBossActive():
    return max(BossWaveInterval, ((game.currentWave - 1) div BossWaveInterval + 1) * BossWaveInterval)

  game.currentWave

proc updateBossArenaGameplay(game: var Game, dt: float32) =
  let arenaEvent = updateBossArenaField(
    game.osBackground,
    dt,
    game.player.pos,
    game.player.radius,
    game.screenWidth,
    game.screenHeight,
    game.bossWaveManager.isBossActive(),
    currentBossArenaWave(game)
  )

  if arenaEvent.damageTriggered and game.state == gsPlaying:
    let hpBefore = game.player.hp
    let playerDied = takeDamage(game.player, arenaEvent.damage)
    trackDamageAvoided(game)
    let actualDamage = max(0.0'f32, hpBefore - game.player.hp)

    if actualDamage > 0.001:
      trackPlayerDamage(game, actualDamage, etEnvironment)
      game.showDamage(game.player.pos, actualDamage, fromPlayer = false,
                      isCritical = false, damageType = dtArcane)
      spawnExplosionPooled(game.particlePool, game.player.pos.x, game.player.pos.y,
                           Color(r: 255, g: 65, b: 55, a: 220), 8)
      playSound(stPlayerHit, 0.38)

    if playerDied:
      beginPlayerDeathSequence(game, dcHazard)

proc updateAttackWarningsAndLasers(game: var Game, dt: float32, effectiveDt: float32) =
  var i = 0
  while i < game.attackWarnings.len:
    game.attackWarnings[i].lifetime -= dt

    # Only laser-beam warnings follow their source enemy during wind-up;
    # every other warning is stamped at a fixed world position.
    let warnType = game.attackWarnings[i].attackType
    if game.attackWarnings[i].sourceEnemyId >= 0 and
       (warnType == awtBossLaser or warnType == awtSatelliteLaser):
      for enemy in game.enemies:
        if enemy.id == game.attackWarnings[i].sourceEnemyId:
          game.attackWarnings[i].pos = enemy.pos
          break

    # SEISMIC CHASER (Berserker Juggernaut phase 3): the crack head is the one
    # deliberately mobile warning - it pursues the player at FissureChaseSpeed
    # (just under base move speed, so running works but stopping never does)
    # and drops a normally-telegraphed awtFissure eruption under itself every
    # FissureChaseInterval. It is not lethal itself; only the pops it drops
    # are. It lives until its boss dies.
    if warnType == awtFissureChaser:
      let w = game.attackWarnings[i]
      var bossAlive = false
      for enemy in game.enemies:
        if enemy.id == w.sourceEnemyId:
          bossAlive = true
          break
      if not bossAlive:
        w.lifetime = 0
      else:
        var chaseDir = game.player.pos - w.pos
        if chaseDir.length() > 1.0'f32:
          chaseDir = chaseDir.normalize()
          w.pos = w.pos + chaseDir * (FissureChaseSpeed * dt)
        w.laserDuration -= dt  # repurposed: countdown to the next eruption
        if w.laserDuration <= 0:
          w.laserDuration = FissureChaseInterval
          w.bulletCount += 1  # running step index, varies each pop's crack render
          # Chaser pops erupt on a much shorter fuse than chain steps: the
          # pursuit itself is the long-range warning, so each drop only needs
          # a snap "get off this spot" cue.
          var pop = newAttackWarning(w.pos.x, w.pos.y, awtFissure,
                                     FissureChasePopWarn + FissureActive, w.sourceEnemyId)
          pop.targetPos = w.pos
          pop.bulletRadius = w.bulletRadius
          pop.bulletDamage = w.bulletDamage
          pop.bulletCount = w.bulletCount
          game.attackWarnings.add(pop)

    # BOSS LASER SYSTEM: Create lasers when warning expires (at 0.1s remaining for smooth transition)
    if game.attackWarnings[i].attackType == awtBossLaser and
       not game.attackWarnings[i].lasersCreated and
       game.attackWarnings[i].lifetime <= 0.1:

      # Find the boss to get current position for laser spawn
      var laserSpawnPos = game.attackWarnings[i].pos
      if game.attackWarnings[i].sourceEnemyId >= 0:
        for enemy in game.enemies:
          if enemy.id == game.attackWarnings[i].sourceEnemyId:
            laserSpawnPos = enemy.pos
            break

      # Determine laser direction type based on pattern
      # direction = 2: Cross pattern (two perpendicular beams) - for cross_laser, rotating_grid
      # direction = 3: Single rotated beam - for prismatic_cage, laser_snipe, and other radial patterns
      let laserDirection = if game.attackWarnings[i].laserPattern in ["cross_laser", "rotating_grid"]:
        2  # Cross pattern
      else:
        3  # Single rotated beam (for prismatic_cage, laser_snipe, and other radial patterns)

      # Beams are hitscan walls, so their whole cost to the player is how long
      # a lane stays deleted. bossLaserActiveDuration is the shared formula
      # (scale + hard cap) that bossLaserThreatRemaining also reads.
      let reducedDuration = bossLaserActiveDuration(game.attackWarnings[i].laserDuration)

      # Create all the lasers for this warning at boss's current position
      for angle in game.attackWarnings[i].laserAngles:
        game.lasers.add(newLaser(
          laserSpawnPos.x,
          laserSpawnPos.y,
          direction = laserDirection,
          length = game.attackWarnings[i].laserLength,
          thickness = 15.0,
          damage = game.attackWarnings[i].laserDamage,
          duration = reducedDuration,  # Reduced duration
          rotation = angle,
          enemyType = game.attackWarnings[i].enemyType
        ))

      # Mark lasers as created
      game.attackWarnings[i].lasersCreated = true

    # TELEPORT WARNING SYSTEM: Spawn bullets when warning expires
    if game.attackWarnings[i].attackType == awtTeleportWarning and
       not game.attackWarnings[i].bulletsCreated and
       game.attackWarnings[i].lifetime <= 0.1:

      let warningPos = game.attackWarnings[i].pos
      let teleportMode = game.attackWarnings[i].laserPattern  # Mode stored in laserPattern field

      # Teleport boss to this position if this is the marked teleport target
      if game.attackWarnings[i].isBossTeleportTarget:
        for enemy in game.enemies:
          if enemy.id == game.attackWarnings[i].sourceEnemyId:
            # Teleport boss to this warning position
            enemy.pos = warningPos

            # Create dramatic teleport arrival effect
            let arrivalExplosionSize = case teleportMode
              of "time_echo": 18
              of "echo_burst": 20
              of "temporal_collapse": 25
              of "afterimage_burst": 16
              of "chaos_blink": 22
              of "reality_shift": 26
              of "dimensional_rift": 24
              of "dimensional_chaos": 30
              of "omega_blink": 35
              else: 15

            spawnExplosionPooled(game.particlePool, warningPos.x, warningPos.y,
                          Color(r: 150, g: 100, b: 255, a: 255), arrivalExplosionSize)
            break

      # Spawn bullets at warning position
      if game.attackWarnings[i].bulletCount > 0:
        for bulletIdx in 0..<game.attackWarnings[i].bulletCount:
          # Randomize angle for chaos modes
          let angle = if teleportMode in ["chaos_blink", "reality_shift", "dimensional_rift", "dimensional_chaos"]:
            bulletIdx.float32 * PI * 2.0 / game.attackWarnings[i].bulletCount.float32 + rand(0.4)
          else:
            bulletIdx.float32 * PI * 2.0 / game.attackWarnings[i].bulletCount.float32
          let dir = newVector2f(cos(angle), sin(angle))

          # Spawn bullet from this teleport location
          let warnSourceId = game.attackWarnings[i].sourceEnemyId
          var warnBossShape = 0
          for be in game.enemies:
            if be.id == warnSourceId:
              warnBossShape = bossBulletShapeFor(be.bossDefinitionID)
              break
          game.bullets.add(newBullet(
            x = warningPos.x, y = warningPos.y,
            direction = dir,
            speed = game.attackWarnings[i].bulletSpeed,
            damage = game.attackWarnings[i].bulletDamage,
            fromPlayer = false, isBossBullet = true,
            sourceEnemyId = warnSourceId,
            bossBulletShape = warnBossShape
          ))

      # Mark bullets as created
      game.attackWarnings[i].bulletsCreated = true

    # METEOR SYSTEM: Spawn bullet when warning expires
    if game.attackWarnings[i].attackType == awtMeteor and
       not game.attackWarnings[i].bulletsCreated and
       game.attackWarnings[i].lifetime <= 0.05:
      let w = game.attackWarnings[i]
      var bossShape = 0
      for be in game.enemies:
        if be.id == w.sourceEnemyId:
          bossShape = bossBulletShapeFor(be.bossDefinitionID)
          break
      # Travel along the telegraphed spawn->impact line. For the classic vertical
      # columns this resolves to straight down; for diagonal comets it follows the
      # angled path the warning drew, keeping the telegraph honest.
      let mDelta = w.pos - w.targetPos
      let mDir = if mDelta.x == 0 and mDelta.y == 0: newVector2f(0, 1)
                 else: mDelta.normalize()
      game.bullets.add(newBullet(
        x = w.targetPos.x, y = w.targetPos.y,
        direction = mDir,
        speed = w.bulletSpeed,
        damage = w.bulletDamage,
        fromPlayer = false, isBossBullet = true,
        sourceEnemyId = w.sourceEnemyId,
        bossBulletShape = bossShape,
        bulletRadius = w.bulletRadius,
        colorOverride = w.overrideColor
      ))
      # Satellite strike entry flash
      if w.overrideColor.r < 200 and w.overrideColor.b > 200:  # purple = satellite
        for step in 0..4:
          spawnExplosionPooled(game.particlePool, w.targetPos.x, -50.0 - step.float32 * 25.0,
                              Color(r: 150, g: 100, b: 255, a: 255), 3)
      else:
        # Orange meteor "sky-crack" spark as the rock punches into the arena.
        spawnExplosionPooled(game.particlePool, w.targetPos.x, w.targetPos.y,
                            Color(r: 255, g: 160, b: 40, a: 255), 3)
      game.attackWarnings[i].bulletsCreated = true

    # TESLA STRIKE: telegraph expires -> a bolt slams the marked ground spot.
    if game.attackWarnings[i].attackType == awtTeslaStrike:
      let w = game.attackWarnings[i]
      if w.lifetime <= TeslaStrikeActive:
        if not w.bulletsCreated:
          for b in 0..<3:
            spawnLightningBolt(game,
              newVector2f(w.targetPos.x + (rand(24.0) - 12.0), -40.0),
              w.targetPos)
          spawnExplosionPooled(game.particlePool, w.targetPos.x, w.targetPos.y,
                               Color(r: 255, g: 255, b: 190, a: 255), 30)
          addShake(game.dopamine.screenShake, siMedium)
          w.bulletsCreated = true
        if not w.lasersCreated and game.player.invincibilityTimer <= 0 and
           distance(game.player.pos, w.targetPos) <= w.bulletRadius + game.player.radius:
          if takeDamage(game.player, w.bulletDamage):
            beginPlayerDeathSequence(game, dcHazard)
          trackDamageAvoided(game)
          trackPlayerDamage(game, w.bulletDamage, etCircle)
          game.showDamage(game.player.pos, w.bulletDamage, fromPlayer = false,
                          isCritical = false, damageType = dtLightning)
          w.lasersCreated = true

    # ARC LATTICE: telegraph expires -> a lightning wall segment goes live.
    if game.attackWarnings[i].attackType == awtArcBeam:
      let w = game.attackWarnings[i]
      if w.lifetime <= ArcBeamActive:
        if not w.bulletsCreated:
          spawnLightningBolt(game, w.pos, w.targetPos)
          spawnLightningBolt(game, w.pos, w.targetPos)
          spawnExplosionPooled(game.particlePool,
                               (w.pos.x + w.targetPos.x) * 0.5'f32,
                               (w.pos.y + w.targetPos.y) * 0.5'f32,
                               Color(r: 255, g: 255, b: 190, a: 255), 12)
          w.bulletsCreated = true
        if not w.lasersCreated and game.player.invincibilityTimer <= 0 and
           pointSegmentDistance(game.player.pos, w.pos, w.targetPos) <=
             w.laserLength + game.player.radius:
          if takeDamage(game.player, w.bulletDamage):
            beginPlayerDeathSequence(game, dcHazard)
          trackDamageAvoided(game)
          trackPlayerDamage(game, w.bulletDamage, etCircle)
          game.showDamage(game.player.pos, w.bulletDamage, fromPlayer = false,
                          isCritical = false, damageType = dtLightning)
          w.lasersCreated = true

    # VOID RIFT (Void Dancer): telegraph expires -> the dimensional tear collapses,
    # dealing zone damage at the rift and releasing a slow radial spray of void
    # bullets. Mirrors the tesla strike: a one-shot eruption (bulletsCreated gate)
    # plus a one-shot zone hit (lasersCreated gate). The bullets + implosion
    # particles are the ungated lethal visual, so the collapse reads even with
    # hints off.
    if game.attackWarnings[i].attackType == awtVoidRift:
      let w = game.attackWarnings[i]
      if w.lifetime <= VoidRiftActive:
        if not w.bulletsCreated:
          var bossShape = 0
          for be in game.enemies:
            if be.id == w.sourceEnemyId:
              bossShape = bossBulletShapeFor(be.bossDefinitionID)
              break
          let burst = max(1, w.bulletCount)
          for b in 0..<burst:
            let ang = b.float32 * (PI * 2.0) / burst.float32
            game.bullets.add(newBullet(
              x = w.targetPos.x, y = w.targetPos.y,
              direction = newVector2f(cos(ang), sin(ang)),
              speed = w.bulletSpeed,
              damage = w.bulletDamage,
              fromPlayer = false, isBossBullet = true,
              sourceEnemyId = w.sourceEnemyId,
              bossBulletShape = bossShape,
              colorOverride = Color(r: 150, g: 40, b: 220, a: 255)
            ))
          spawnExplosionPooled(game.particlePool, w.targetPos.x, w.targetPos.y,
                               Color(r: 160, g: 50, b: 230, a: 255), 26)
          addShake(game.dopamine.screenShake, siMedium)
          w.bulletsCreated = true
        if not w.lasersCreated and game.player.invincibilityTimer <= 0 and
           distance(game.player.pos, w.targetPos) <= w.bulletRadius + game.player.radius:
          if takeDamage(game.player, w.bulletDamage):
            beginPlayerDeathSequence(game, dcHazard)
          trackDamageAvoided(game)
          trackPlayerDamage(game, w.bulletDamage, etCircle)
          game.showDamage(game.player.pos, w.bulletDamage, fromPlayer = false,
                          isCritical = false, damageType = dtArcane)
          w.lasersCreated = true

    # RICOCHET LASER (boss 4 final phase): telegraph expires -> the beam-front
    # races along the bounce route (RicochetLaserSweep). The swept-so-far portion
    # is lethal; the player can only be struck ONCE (lasersCreated gate), so being
    # caught by the leading edge is a single big hit, never a repeated burn.
    if game.attackWarnings[i].attackType == awtRicochetLaser:
      let w = game.attackWarnings[i]
      if w.lifetime <= RicochetLaserActive and w.ricochetPath.len >= 2:
        if not w.bulletsCreated:
          # Muzzle flash at the boss + a shake at the instant the beam launches.
          spawnExplosionPooled(game.particlePool, w.ricochetPath[0].x, w.ricochetPath[0].y,
                               Color(r: 200, g: 245, b: 255, a: 255), 14)
          addShake(game.dopamine.screenShake, siMedium)
          w.bulletsCreated = true
        if not w.lasersCreated and game.player.invincibilityTimer <= 0:
          # Only test the portion the beam-front has actually reached so far.
          let activeElapsed = RicochetLaserActive - w.lifetime
          let sweepFrac = clamp(activeElapsed / RicochetLaserSweep, 0.0'f32, 1.0'f32)
          let frontDist = sweepFrac * polylineLength(w.ricochetPath)
          let swept = ricochetSweptPath(w.ricochetPath, frontDist)
          var hit = false
          for s in 0 ..< swept.len - 1:
            if pointSegmentDistance(game.player.pos, swept[s], swept[s + 1]) <=
               w.laserLength + game.player.radius:
              hit = true
              break
          if hit:
            if takeDamage(game.player, w.bulletDamage):
              beginPlayerDeathSequence(game, dcLaser, sourceType = w.enemyType)
            trackDamageAvoided(game)
            trackPlayerDamage(game, w.bulletDamage, w.enemyType)
            game.showDamage(game.player.pos, w.bulletDamage, fromPlayer = false,
                            isCritical = false, damageType = dtLaser)
            # Impact burst where the beam caught the player.
            spawnExplosionPooled(game.particlePool, game.player.pos.x, game.player.pos.y,
                                 Color(r: 230, g: 250, b: 255, a: 255), 20)
            addShake(game.dopamine.screenShake, siLarge)
            w.lasersCreated = true

    # ORBITAL SWEEP (Orbital Commander): while active, a screen-spanning energy
    # wall travels across the arena (its centre resolved per-frame by
    # orbitalSweepCenter, the same function the render uses). The player is hit
    # if the wall reaches them while they are NOT inside its safe gap - a
    # moving hazard, tested every frame, one hit max per wall.
    if game.attackWarnings[i].attackType == awtOrbitalSweep:
      let w = game.attackWarnings[i]
      if w.lifetime <= OrbitalSweepActive:
        if not w.bulletsCreated:
          # Entry flash where the satellite breaches the arena edge.
          spawnExplosionPooled(game.particlePool, w.pos.x, w.pos.y,
                               Color(r: 190, g: 150, b: 255, a: 255), 16)
          addShake(game.dopamine.screenShake, siSmall)
          w.bulletsCreated = true
        if not w.lasersCreated and game.player.invincibilityTimer <= 0:
          let c = orbitalSweepCenter(w)
          let ang = w.bulletSpreadAngle
          let v = newVector2f(cos(ang), sin(ang))    # travel direction
          let u = newVector2f(-sin(ang), cos(ang))   # along the wall
          let rel = game.player.pos - c
          let dAcross = rel.x * v.x + rel.y * v.y
          let dAlong = rel.x * u.x + rel.y * u.y
          let gapOffset = if w.laserAngles.len > 0: w.laserAngles[0] else: 0.0'f32
          if abs(dAcross) <= w.laserLength + game.player.radius and
             abs(dAlong) <= w.bulletSpeed and
             abs(dAlong - gapOffset) > w.bulletRadius:
            if takeDamage(game.player, w.bulletDamage):
              beginPlayerDeathSequence(game, dcLaser, sourceType = w.enemyType)
            trackDamageAvoided(game)
            trackPlayerDamage(game, w.bulletDamage, etCircle)
            game.showDamage(game.player.pos, w.bulletDamage, fromPlayer = false,
                            isCritical = false, damageType = dtLaser)
            spawnExplosionPooled(game.particlePool, game.player.pos.x, game.player.pos.y,
                                 Color(r: 200, g: 160, b: 255, a: 255), 14)
            w.lasersCreated = true

    # SEISMIC FISSURE (Berserker Juggernaut): each step of the marching crack
    # pops when ITS lifetime enters the active window - the per-step stagger is
    # baked into the lifetimes at spawn, so this shared check fires the chain
    # in sequence automatically.
    if game.attackWarnings[i].attackType == awtFissure:
      let w = game.attackWarnings[i]
      if w.lifetime <= FissureActive:
        if not w.bulletsCreated:
          spawnExplosionPooled(game.particlePool, w.targetPos.x, w.targetPos.y,
                               Color(r: 255, g: 140, b: 50, a: 255), 18)
          addShake(game.dopamine.screenShake, siSmall)
          w.bulletsCreated = true
        if not w.lasersCreated and game.player.invincibilityTimer <= 0 and
           distance(game.player.pos, w.targetPos) <= w.bulletRadius + game.player.radius:
          if takeDamage(game.player, w.bulletDamage):
            beginPlayerDeathSequence(game, dcHazard)
          trackDamageAvoided(game)
          trackPlayerDamage(game, w.bulletDamage, etCircle)
          game.showDamage(game.player.pos, w.bulletDamage, fromPlayer = false,
                          isCritical = false, damageType = dtExplosion)
          w.lasersCreated = true

    # PRISM REFRACTION (Prism Architect): each star (primary AND every cascade
    # mini, staggered) goes lethal for a short flash. Geometry lives in
    # ricochetPath as [origin, focus, rayEnd...]; bulletCount is the generation
    # and a mini's feed vertex (parent focus -> mini) is cosmetic, never lethal
    #, the spent primary focus must stay a safe shelter. One strike per star.
    if game.attackWarnings[i].attackType == awtPrismRays:
      let w = game.attackWarnings[i]
      if w.lifetime <= PrismRayActive and w.ricochetPath.len >= 3:
        if not w.bulletsCreated:
          spawnExplosionPooled(game.particlePool, w.ricochetPath[1].x, w.ricochetPath[1].y,
                               Color(r: 255, g: 230, b: 255, a: 255),
                               if w.bulletCount == 0: 36 else: 12)
          addShake(game.dopamine.screenShake,
                   if w.bulletCount == 0: siLarge else: siSmall,
                   Color(r: 235, g: 210, b: 255, a: 255))
          w.bulletsCreated = true
        if not w.lasersCreated and game.player.invincibilityTimer <= 0:
          let focus = w.ricochetPath[1]
          var hit = w.bulletCount == 0 and
                    pointSegmentDistance(game.player.pos, w.ricochetPath[0], focus) <=
                    w.laserLength + game.player.radius
          if not hit:
            for k in 2 ..< w.ricochetPath.len:
              if pointSegmentDistance(game.player.pos, focus, w.ricochetPath[k]) <=
                 w.laserLength + game.player.radius:
                hit = true
                break
          if hit:
            if takeDamage(game.player, w.bulletDamage):
              beginPlayerDeathSequence(game, dcLaser, sourceType = w.enemyType)
            trackDamageAvoided(game)
            trackPlayerDamage(game, w.bulletDamage, etCircle)
            game.showDamage(game.player.pos, w.bulletDamage, fromPlayer = false,
                            isCritical = false, damageType = dtLaser)
            w.lasersCreated = true

    # CLOCK SWEEP (Timekeeper): while active the hands rotate around the frozen
    # pivot (angles recomputed from lifetime via clockSweepHandAngle, the same
    # function the render uses). Being caught by a hand is a single big hit.
    if game.attackWarnings[i].attackType == awtClockSweep:
      let w = game.attackWarnings[i]
      if w.lifetime <= ClockSweepActive:
        if not w.bulletsCreated:
          spawnExplosionPooled(game.particlePool, w.pos.x, w.pos.y,
                               Color(r: 150, g: 255, b: 255, a: 255), 16)
          addShake(game.dopamine.screenShake, siSmall)
          w.bulletsCreated = true
        # Rewind cast: one amber jolt the instant time starts flowing backward
        # (bulletCount doubles as the one-shot gate; the sweep never uses it).
        if w.laserPattern == "rewind" and w.bulletCount == 0 and
           ClockSweepActive - w.lifetime > ClockSweepActive * ClockRewindPoint:
          w.bulletCount = 1
          spawnExplosionPooled(game.particlePool, w.pos.x, w.pos.y,
                               Color(r: 255, g: 200, b: 110, a: 255), 18)
          addShake(game.dopamine.screenShake, siMedium)
        # Rewind finale: as the sweep expires the clock STRIKES - 12 chime
        # bullets fire down the tick rays the render has been charging amber.
        if w.laserPattern == "rewind" and w.bulletCount == 1 and
           w.lifetime <= 0.05:
          w.bulletCount = 2
          var chimeShape = 0
          for be in game.enemies:
            if be.id == w.sourceEnemyId:
              chimeShape = bossBulletShapeFor(be.bossDefinitionID)
              break
          for k in 0..<12:
            let ca = k.float32 * PI / 6.0'f32
            game.bullets.add(newBullet(
              x = w.pos.x + cos(ca) * 22.0'f32,
              y = w.pos.y + sin(ca) * 22.0'f32,
              direction = newVector2f(cos(ca), sin(ca)),
              speed = ClockChimeSpeed,
              damage = w.bulletDamage * 0.6'f32,
              fromPlayer = false, isBossBullet = true,
              sourceEnemyId = w.sourceEnemyId,
              bossBulletShape = chimeShape
            ))
          spawnExplosionPooled(game.particlePool, w.pos.x, w.pos.y,
                               Color(r: 255, g: 210, b: 130, a: 255), 24)
          addShake(game.dopamine.screenShake, siMedium)
        if not w.lasersCreated and game.player.invincibilityTimer <= 0:
          for hand in 0 ..< max(1, w.laserCount):
            let ang = clockSweepHandAngle(w, hand)
            let tip = newVector2f(w.pos.x + cos(ang) * w.bulletRadius,
                                  w.pos.y + sin(ang) * w.bulletRadius)
            if pointSegmentDistance(game.player.pos, w.pos, tip) <=
               w.laserLength + game.player.radius:
              if takeDamage(game.player, w.bulletDamage):
                beginPlayerDeathSequence(game, dcLaser, sourceType = w.enemyType)
              trackDamageAvoided(game)
              trackPlayerDamage(game, w.bulletDamage, etCircle)
              game.showDamage(game.player.pos, w.bulletDamage, fromPlayer = false,
                              isCritical = false, damageType = dtFrost)
              w.lasersCreated = true
              break

    # CHAOS WEAVE (Chaos Weaver): threads snap taut and lethal in stitch order
    # (staggered lifetimes); hit test walks the polyline segments, one hit per
    # thread. Knot warnings (laserPattern == "knot", empty path) tear open
    # after the last snap and release a slow radial ring of REAL bullets - the
    # ungated finale, visible with hints off.
    if game.attackWarnings[i].attackType == awtChaosWeave:
      let w = game.attackWarnings[i]
      if w.lifetime <= ChaosWeaveActive and w.laserPattern == "knot":
        if not w.bulletsCreated:
          var knotBossShape = 0
          for be in game.enemies:
            if be.id == w.sourceEnemyId:
              knotBossShape = bossBulletShapeFor(be.bossDefinitionID)
              break
          let ringCount = max(1, w.bulletCount)
          let ringOffset = rand(1.0'f32) * PI * 2.0'f32
          for b in 0 ..< ringCount:
            let ang = ringOffset + b.float32 * (PI * 2.0) / ringCount.float32
            game.bullets.add(newBullet(
              x = w.pos.x, y = w.pos.y,
              direction = newVector2f(cos(ang), sin(ang)),
              speed = w.bulletSpeed, damage = w.bulletDamage,
              fromPlayer = false, isBossBullet = true,
              sourceEnemyId = w.sourceEnemyId,
              bossBulletShape = knotBossShape))
          spawnExplosionPooled(game.particlePool, w.pos.x, w.pos.y,
                               Color(r: 255, g: 140, b: 255, a: 255), 10)
          addShake(game.dopamine.screenShake, siMedium)
          w.bulletsCreated = true
      elif w.lifetime <= ChaosWeaveActive and w.ricochetPath.len >= 2:
        if not w.bulletsCreated:
          # Snap sparks at the kinks - the ungated lethal cue alongside the beam.
          for v in w.ricochetPath:
            spawnExplosionPooled(game.particlePool, v.x, v.y,
                                 Color(r: 255, g: 90, b: 255, a: 255), 4)
          addShake(game.dopamine.screenShake, siSmall)
          w.bulletsCreated = true
        if not w.lasersCreated and game.player.invincibilityTimer <= 0:
          var hit = false
          for s in 0 ..< w.ricochetPath.len - 1:
            if pointSegmentDistance(game.player.pos, w.ricochetPath[s], w.ricochetPath[s + 1]) <=
               w.laserLength + game.player.radius:
              hit = true
              break
          if hit:
            if takeDamage(game.player, w.bulletDamage):
              beginPlayerDeathSequence(game, dcLaser, sourceType = w.enemyType)
            trackDamageAvoided(game)
            trackPlayerDamage(game, w.bulletDamage, etCircle)
            game.showDamage(game.player.pos, w.bulletDamage, fromPlayer = false,
                            isCritical = false, damageType = dtArcane)
            w.lasersCreated = true

    # OMEGA JUDGEMENT (Omega Entity): every heartbeat three quadrants erupt
    # and the gold shelter hops (lifetimes encode the beats, like the
    # fissure). The hit is an AABB test against the quadrant rect; one hit
    # per warning. Gold "shelter" guide markers are non-lethal and never
    # erupt.
    if game.attackWarnings[i].attackType == awtOmegaQuadrant:
      let w = game.attackWarnings[i]
      if w.laserPattern != "shelter" and w.lifetime <= OmegaQuadActive:
        if not w.bulletsCreated:
          # Scattered eruption bursts across the quadrant sell the scale; the
          # spared-quadrant finale erupts in gold, matching its telegraph.
          let spared = w.laserPattern == "spared"
          let chase = w.laserPattern == "chase"
          let popCol = if spared: Color(r: 255, g: 210, b: 110, a: 255)
                       else: Color(r: 255, g: 80, b: 110, a: 255)
          # Up to 8 cells erupt per beat on the Omega 3x3 grid - only the
          # featured cells (chase/finale) get the full burst count.
          let bursts = if chase or spared: 5 else: 3
          for b in 0..<bursts:
            spawnExplosionPooled(game.particlePool,
                                 w.pos.x + (rand(2.0'f32) - 1.0'f32) * w.targetPos.x * 0.8'f32,
                                 w.pos.y + (rand(2.0'f32) - 1.0'f32) * w.targetPos.y * 0.8'f32,
                                 popCol, 8)
          # Judgement embers: only the CHASE eruption (the shelter the player
          # just vacated) and the gold finale hurl a sparse ring of slow REAL
          # bullets - drifting debris to weave mid-migration. Three rings per
          # beat would be soup; one ring chasing the player is pressure.
          if chase or spared:
            var emberShape = 0
            for be in game.enemies:
              if be.id == w.sourceEnemyId:
                emberShape = bossBulletShapeFor(be.bossDefinitionID)
                break
            let emberN = if spared: OmegaEmberCount + 2 else: OmegaEmberCount
            let emberOfs = rand(1.0'f32) * PI * 2.0'f32
            for b in 0 ..< emberN:
              let ang = emberOfs + b.float32 * (PI * 2.0) / emberN.float32
              game.bullets.add(newBullet(
                x = w.pos.x, y = w.pos.y,
                direction = newVector2f(cos(ang), sin(ang)),
                speed = OmegaEmberSpeed, damage = w.bulletDamage * 0.5'f32,
                fromPlayer = false, isBossBullet = true,
                sourceEnemyId = w.sourceEnemyId, bossBulletShape = emberShape,
                colorOverride = popCol))
            addShake(game.dopamine.screenShake, siLarge)
          w.bulletsCreated = true
        if not w.lasersCreated and game.player.invincibilityTimer <= 0 and
           abs(game.player.pos.x - w.pos.x) <= w.targetPos.x + game.player.radius and
           abs(game.player.pos.y - w.pos.y) <= w.targetPos.y + game.player.radius:
          if takeDamage(game.player, w.bulletDamage):
            beginPlayerDeathSequence(game, dcHazard)
          trackDamageAvoided(game)
          trackPlayerDamage(game, w.bulletDamage, etCircle)
          game.showDamage(game.player.pos, w.bulletDamage, fromPlayer = false,
                          isCritical = false, damageType = dtFire)
          w.lasersCreated = true

    if game.attackWarnings[i].lifetime <= 0:
      game.attackWarnings.delete(i)
      continue
    i += 1

  # Update lasers and check collision with player
  var j = 0
  while j < game.lasers.len:
    game.lasers[j].lifetime -= dt

    # Check if player is hit by laser (only once per laser)
    if not game.lasers[j].hasHitPlayer and game.player.invincibilityTimer <= 0:
      let laser = game.lasers[j]

      # Transform player position into laser's local space (accounting for rotation)
      let dx = game.player.pos.x - laser.pos.x
      let dy = game.player.pos.y - laser.pos.y

      # Rotate point by -rotation to get local coordinates
      let cosR = cos(-laser.rotation)
      let sinR = sin(-laser.rotation)
      let localX = dx * cosR - dy * sinR
      let localY = dx * sinR + dy * cosR

      var hit = false
      case laser.direction
      of 0:  # Horizontal laser (extends along X axis in local space)
        if abs(localY) < laser.thickness and abs(localX) < laser.length:
          hit = true
      of 1:  # Vertical laser (extends along Y axis in local space)
        if abs(localX) < laser.thickness and abs(localY) < laser.length:
          hit = true
      of 2:  # Cross (both horizontal and vertical in local space)
        if (abs(localY) < laser.thickness and abs(localX) < laser.length) or
           (abs(localX) < laser.thickness and abs(localY) < laser.length):
          hit = true
      of 3:  # Single radial beam (extends outward along rotation angle)
        # Check if player is in the beam: within thickness and from center to length
        if abs(localY) < laser.thickness and localX >= 0 and localX < laser.length:
          hit = true
      else:
        discard

      if hit:
        if takeDamage(game.player, laser.damage.float32):
          beginPlayerDeathSequence(game, dcLaser, sourceType = laser.enemyType)
        trackDamageAvoided(game)
        trackPlayerDamage(game, laser.damage.float32, laser.enemyType)

        # Create damage number for laser damage
        game.showDamage(game.player.pos, laser.damage.float32, fromPlayer = false,
                        isCritical = false, damageType = dtLaser)

        game.lasers[j].hasHitPlayer = true

    # Remove expired lasers
    if game.lasers[j].lifetime <= 0:
      game.lasers.delete(j)
      continue
    j += 1

proc updatePlayerAuras(game: var Game, dt: float32) =
  # ALL auras are pulse-based: instead of applying a sliver of effect every
  # frame (invisible, and indistinguishable when several auras overlap), each
  # aura fires a discrete beat on its own timer, announced by a shockwave ring
  # in its own color at its own radius. See src/game/auras.nim for the shared
  # radius bands, cadences and colors that the renderer reads back.
  template auraPulse(auraType: PowerUpType, mastery: bool, body: untyped) =
    ## Runs `body` on every frame this aura's wavefront is sweeping outward,
    ## injecting `level`, `radius`, `interval`, `slot`, `front` (how far the
    ## wave has got this frame) and `justFired` (true only on the launch frame).
    ##
    ## The pulse is NOT instant-in-radius any more: the body must gate each
    ## enemy on `auraWaveCatches(game.player, enemy, slot, front)`, which is
    ## true exactly once per enemy per pulse, on the frame the ring reaches it.
    ## So damage lands as the ring passes, matching what is drawn - an enemy at
    ## the rim is hit ~0.3s after one standing on top of the player. Anything
    ## that should happen once for the whole pulse (screen shake, a burst at the
    ## player) belongs under `justFired`.
    ##
    ## Each aura owns a slot timer on the player, and the first tick is
    ## phase-offset, so stacked auras beat independently rather than all landing
    ## on the same frame.
    if hasPowerUp(game.player, auraType):
      let level {.inject.} = getPowerUpLevel(game.player, auraType)
      let radius {.inject.} = getAuraRadiusFor(auraType, level)
      let interval {.inject.} = getAuraPulseInterval(auraType, level, mastery)
      let slot {.inject.} = auraSlotOf(auraType)
      # The flash timer doubles as the wave clock: it runs AuraFlashDuration ->
      # 0, and the first AuraWaveTravelTime of that is the outbound trip. Its
      # value before and after this frame's decrement gives the wave's previous
      # and current position - no separate wave state to keep in sync.
      let prevFlash = game.player.auraFlashTimers[slot]
      if prevFlash > 0:
        game.player.auraFlashTimers[slot] = max(0.0'f32, prevFlash - dt)
      if slot notin game.player.auraPulsePrimed:
        game.player.auraPulsePrimed.incl(slot)
        game.player.auraPulseTimers[slot] = interval * auraPhaseOffset(slot)
      game.player.auraPulseTimers[slot] -= dt
      var justFired {.inject.} = false
      if game.player.auraPulseTimers[slot] <= 0:
        game.player.auraPulseTimers[slot] = interval
        game.player.auraFlashTimers[slot] = AuraFlashDuration
        # Bumping the sequence retires every enemy's mark at once, which is what
        # re-arms them for this new wave. No shockwave ring here: those snap to
        # full radius in ~0.13s and would outrun the wave that actually hits.
        inc game.player.auraPulseSeq[slot]
        justFired = true
      let prevElapsed =
        if prevFlash > 0: AuraFlashDuration - prevFlash else: AuraFlashDuration
      let curElapsed = AuraFlashDuration - game.player.auraFlashTimers[slot]
      # Sweep while the front is still in flight. The `prevElapsed` guard is what
      # gives the final frame a full-radius sweep (clamped below) and then stops:
      # without it, a long frame could retire the wave with its outermost shell
      # never swept, and enemies at the rim would be skipped.
      let sweeping = prevElapsed < AuraWaveTravelTime and curElapsed > 0.0'f32
      if justFired or sweeping:
        let front {.inject.} =
          if sweeping: auraWaveFrontRadius(min(curElapsed, AuraWaveTravelTime), radius)
          else: 0.0'f32
        body

  # Per-pulse particle budget. The ring already carries the beat, so the
  # per-enemy bursts are pure garnish - unbounded, a 100-enemy wave under
  # several auras would spawn thousands of particles on a single frame.
  const AuraFxBudget = 20

  # Slow Field - chills everything in range on the beat
  auraPulse(puSlowField, false):
    var fxBudget = AuraFxBudget
    let slowPercent = case level
      of 1: 0.30'f32
      of 2: 0.45'f32
      else: 0.55'f32
    # Slow is this aura's whole identity, so the debuff is held until the next
    # pulse (plus a little overlap) instead of lapsing between beats.
    let holdTime = interval * 1.15
    let chipDamage = 0.4'f32 * interval

    for enemy in game.enemies:
      if auraWaveCatches(game.player, enemy, slot, front):
        enemy.slowTimer = holdTime
        enemy.slowAmount = slowPercent
        let slowChipDamage = damageEnemy(enemy, chipDamage)
        if slowChipDamage > 0:
          accumulateAndShowAuraDamage(game, enemy, slowChipDamage, dtFrost, false)
        if fxBudget > 0:
          dec fxBudget
          spawnExplosionPooled(game.particlePool, enemy.pos.x, enemy.pos.y,
                               getAuraPulseColor(puSlowField), 4)

  # Fire Aura - the beat ignites everything in range. Hot burn: higher dps than
  # poison, but the after-burn fades quickly once enemies leave the aura.
  auraPulse(puFireAura, game.player.hasFireMastery):
    var fxBudget = AuraFxBudget
    let damageScaling = game.player.damage * 0.35
    let fireDamagePerSec = case level
      of 1: 1.5 + damageScaling
      of 2: 3.5 + damageScaling
      else: 6.5 + damageScaling
    # Burn must outlast the gap between beats or the aura's dps would drop just
    # from being pulsed, so the level duration is floored at one cycle + 20%.
    let fireDuration = max(case level
      of 1: 2.0'f32
      of 2: 3.0'f32
      else: 4.0'f32, interval * 1.2)

    for enemy in game.enemies:
      if auraWaveCatches(game.player, enemy, slot, front):
        applyMasteryDoT(enemy, etFire, fireDamagePerSec, fireDuration,
                        game.player.hasFireMastery,
                        masteryDmgMult = FireMasteryDmgMult, masteryDurMult = FireMasteryDurMult,
                        masterySlowAmount = 0.45, source = "aura")

        # Ignition burst on the beat, then the DoT keeps its own small flames
        if fxBudget > 0:
          dec fxBudget
          spawnExplosionPooled(game.particlePool, enemy.pos.x, enemy.pos.y,
                               getAuraPulseColor(puFireAura), 5)

  # Lightning Aura - one arc storm per beat. Pulsing suits this aura best: the
  # chains are now a single readable burst instead of one-frame flickers.
  auraPulse(puLightningAura, game.player.hasLightningMastery):
    var fxBudget = AuraFxBudget
    let damageScaling = game.player.damage * 0.3
    # Per-beat damage = the old per-second value times the cycle length, so the
    # sustained dps is preserved and each hit is a number you can actually read.
    var lightningDamage = (case level
      of 1: 1.0'f32 + damageScaling
      of 2: 2.5'f32 + damageScaling
      else: 5.0'f32 + damageScaling) * interval
    var maxChains = case level
      of 1: 1
      of 2: 2
      else: 4
    let chainRange = 80.0  # Distance lightning can chain between enemies

    # Apply Lightning Mastery bonuses if owned
    if game.player.hasLightningMastery:
      lightningDamage *= MasteryDamageMult  # +150% damage
      maxChains += 1  # +1 chain

    # Only the enemies the arc front reached this frame - the storm rolls
    # outward with the ring instead of striking the whole field at once.
    var enemiesInRange: seq[Enemy] = @[]
    for enemy in game.enemies:
      if auraWaveCatches(game.player, enemy, slot, front):
        enemiesInRange.add(enemy)

    # Calculate combat stats once before loop
    let stats = calculateCombatStats(game.player)

    # Apply damage and chain lightning
    var processedEnemies: seq[Enemy] = @[]
    for enemy in enemiesInRange:
      if enemy notin processedEnemies:
        # Apply initial damage with crit chance using centralized stats
        let (damageWithCrit, wasCrit) = applyCriticalHitWithFlag(stats, lightningDamage)
        let actualDamage = damageEnemy(enemy, damageWithCrit)
        processedEnemies.add(enemy)

        # Track lightning aura damage for statistics
        trackPowerUpDamage(game, puLightningAura, actualDamage)
        # Track LightningMastery bonus (mastery doubles lightning damage; bonus = base)
        if game.player.hasLightningMastery:
          trackPowerUpDamage(game, puLightningMastery, actualDamage)

        # Use accumulation system for reliable damage numbers
        accumulateAndShowAuraDamage(game, enemy, actualDamage, dtLightning, wasCrit)

        # Apply slow ONLY if player has Lightning Mastery (held until next beat)
        if game.player.hasLightningMastery:
          enemy.slowTimer = interval * 1.15
          if enemy.slowAmount < 0.25:
            enemy.slowAmount = 0.25  # 25% slow

        # Visual lightning spark
        if fxBudget > 0:
          dec fxBudget
          spawnExplosionPooled(game.particlePool, enemy.pos.x, enemy.pos.y,
                               getAuraPulseColor(puLightningAura), 5)

        # Chain to nearby enemies
        var currentEnemy = enemy
        for chainNum in 1..maxChains:
          # Find nearest unchained enemy within chain range
          var nearestDist = chainRange + 1.0
          var nearestEnemy: Enemy = nil

          for other in game.enemies:
            # Skip anything this pulse already spent itself on, whether the
            # front swept it earlier or an earlier link chained to it
            if other != currentEnemy and other notin processedEnemies and
               not auraWaveAlreadyHit(game.player, other, slot):
              let chainDist = distance(currentEnemy.pos, other.pos)
              if chainDist < chainRange and chainDist < nearestDist:
                nearestDist = chainDist
                nearestEnemy = other

          if nearestEnemy != nil:
            # Chaining consumes the target for this pulse, so the front cannot
            # reach it later and hit it a second time
            markAuraWaveHit(game.player, nearestEnemy, slot)
            # Apply chained damage (same as initial) with crit chance using centralized stats
            let (chainDamageWithCrit, chainWasCrit) = applyCriticalHitWithFlag(stats, lightningDamage)
            let chainedDamage = damageEnemy(nearestEnemy, chainDamageWithCrit)
            processedEnemies.add(nearestEnemy)

            # Track chained lightning damage for statistics
            trackPowerUpDamage(game, puLightningAura, chainedDamage)
            if game.player.hasLightningMastery:
              trackPowerUpDamage(game, puLightningMastery, chainedDamage)

            # Use accumulation system for chained lightning to prevent spam
            accumulateAndShowAuraDamage(game, nearestEnemy, chainedDamage, dtLightning, chainWasCrit)

            # Apply 5% slow effect to chained enemy
            nearestEnemy.slowTimer = interval * 1.15
            if nearestEnemy.slowAmount < 0.05:
              nearestEnemy.slowAmount = 0.05

            # Lightning arc visual
            spawnLightningBolt(game, currentEnemy.pos, nearestEnemy.pos)

            currentEnemy = nearestEnemy
          else:
            break  # No more enemies to chain to

  # Arcane Aura - pure arcane damage, the fastest and tightest of the beats
  auraPulse(puArcaneAura, game.player.hasArcaneMastery):
    var fxBudget = AuraFxBudget
    let damageScaling = game.player.damage * 0.3
    var arcaneDamage = (case level
      of 1: 3.5'f32 + damageScaling
      of 2: 7.5'f32 + damageScaling
      else: 10.0'f32 + damageScaling) * interval

    # Apply Arcane Mastery bonuses if owned
    if game.player.hasArcaneMastery:
      arcaneDamage *= ArcaneMasteryDmgMult  # +75% damage

    # Calculate combat stats once before loop
    let arcaneStats = calculateCombatStats(game.player)

    for enemy in game.enemies:
      if auraWaveCatches(game.player, enemy, slot, front):
        let (damageWithCrit, wasCrit) = applyCriticalHitWithFlag(arcaneStats, arcaneDamage)
        let actualDamage = damageEnemy(enemy, damageWithCrit)

        # Track arcane aura damage for statistics
        trackPowerUpDamage(game, puArcaneAura, actualDamage)
        # Track ArcaneMastery bonus
        if game.player.hasArcaneMastery:
          trackPowerUpDamage(game, puArcaneMastery, actualDamage)

        # Use accumulation system for reliable damage numbers
        accumulateAndShowAuraDamage(game, enemy, actualDamage, dtArcane, wasCrit)

        # Visual arcane particles (purple sparkles)
        if fxBudget > 0:
          dec fxBudget
          spawnExplosionPooled(game.particlePool, enemy.pos.x, enemy.pos.y,
                               getAuraPulseColor(puArcaneAura), 5)

  # Poison Aura - slow drip: lower dps than fire but the venom keeps ticking for
  # up to 10s after enemies leave the aura, so it barely notices being pulsed
  auraPulse(puPoisonAura, game.player.hasPoisonMastery):
    var fxBudget = AuraFxBudget
    let damageScaling = game.player.damage * 0.25
    let poisonDamagePerSec = case level
      of 1: 0.8 + damageScaling
      of 2: 2.0 + damageScaling
      else: 4.0 + damageScaling
    let poisonDuration = max(case level
      of 1: 6.0'f32
      of 2: 8.0'f32
      else: 10.0'f32, interval * 1.2)

    for enemy in game.enemies:
      if auraWaveCatches(game.player, enemy, slot, front):
        applyMasteryDoT(enemy, etPoison, poisonDamagePerSec, poisonDuration,
                        game.player.hasPoisonMastery,
                        masteryDmgMult = PoisonMasteryDmgMult, masteryDurMult = PoisonMasteryDurMult,
                        masterySlowAmount = 0.40, source = "aura")

        # Visual poison particles
        if fxBudget > 0:
          dec fxBudget
          spawnExplosionPooled(game.particlePool, enemy.pos.x, enemy.pos.y,
                               getAuraPulseColor(puPoisonAura), 4)

  # Wind Aura - the gust blasts every enemy in radius outward (Pulse Armor style
  # shove). This is the one aura whose beat also moves the battlefield.
  auraPulse(puWindAura, game.player.hasWindMastery):
    # Launch speed fed into enemy.knockbackVel (a shove that coasts to a stop),
    # not a per-frame nudge, so the gust reads as a single hit of force.
    var pushForce = case level
      of 1: 420.0'f32
      of 2: 560.0'f32
      else: 700.0'f32
    var gustDamage = (case level
      of 1: 2.0'f32
      of 2: 4.0'f32
      else: 7.0'f32) + game.player.damage * 0.25'f32
    if game.player.hasWindMastery:
      pushForce *= 2.2  # the gust is wind's identity, so mastery leans on it
      gustDamage *= MasteryDamageMult  # +150% damage, same as every other mastery

    for enemy in game.enemies:
      if auraWaveCatches(game.player, enemy, slot, front):
        let dist = distance(game.player.pos, enemy.pos)
        # Deterministic fallback direction when the enemy overlaps the player
        let delta = enemy.pos - game.player.pos
        let awayFromPlayer =
          if delta.length() > 0.01'f32: delta.normalize()
          else: newVector2f(0, -1)

        # Stronger up close, with a floor so enemies at the rim still get moved.
        # Bosses barely budge so they can't be kited around by the aura alone.
        let proximity = 0.4'f32 + 0.6'f32 * (1.0'f32 - dist / radius)
        let resistance = if enemy.isBoss: 0.12'f32 else: 1.0'f32
        # Overwrite rather than accumulate so repeated gusts feel consistent
        enemy.knockbackVel = awayFromPlayer * (pushForce * proximity * resistance)

        let dmg = if enemy.isBoss: gustDamage * 0.25'f32 else: gustDamage
        let windDamage = damageEnemy(enemy, dmg)
        if windDamage > 0:
          trackPowerUpDamage(game, puWindAura, windDamage)
          if game.player.hasWindMastery:
            trackPowerUpDamage(game, puWindMastery, windDamage)
          game.showDamage(enemy.pos, windDamage, fromPlayer = true,
                          isCritical = false, damageType = dtDefault)

        # Apply slow ONLY if player has Wind Mastery - held until the next gust
        if game.player.hasWindMastery:
          enemy.slowTimer = interval * 1.15
          if enemy.slowAmount < 0.45:
            enemy.slowAmount = 0.45  # 45% slow

    # Extra juice, launch frame only: the air burst is the gust leaving the
    # player, so it fires once with the wave rather than every sweep frame.
    # Shake/sound need a look-ahead over the full radius - the front has not
    # reached anyone yet on this frame, but we still want one shake per gust
    # instead of one per enemy the ring later catches. Wind is the only aura
    # that shakes: it is the only one that physically moves enemies.
    if justFired:
      let gustColor = getAuraPulseColor(puWindAura)
      spawnExplosionPooled(game.particlePool, game.player.pos.x, game.player.pos.y,
                    gustColor, 24)
      var willHit = false
      for enemy in game.enemies:
        if distance(game.player.pos, enemy.pos) < radius:
          willHit = true
          break
      if willHit:
        addShake(game.dopamine.screenShake, siSmall, gustColor)
        playSound(stExplosion, 0.35)

  # Blood Aura - damage with lifesteal, drained in one bite per beat
  auraPulse(puBloodAura, game.player.hasBloodMastery):
    var fxBudget = AuraFxBudget
    let damageScaling = game.player.damage * 0.275
    var bloodDamage = (case level
      of 1: 1.0'f32 + damageScaling
      of 2: 2.5'f32 + damageScaling
      else: 5.0'f32 + damageScaling) * interval
    let lifestealPercent = case level
      of 1: 0.025  # 2.5% lifesteal
      of 2: 0.05   # 5% lifesteal
      else: 0.075  # 7.5% lifesteal

    # Apply Blood Mastery bonuses if owned
    var actualLifestealPercent: float64 = lifestealPercent
    if game.player.hasBloodMastery:
      bloodDamage *= 2.0  # +100% damage
      actualLifestealPercent *= 2.0  # +100% lifesteal

    # The beat is its own display throttle, so the drain heals and shows once
    # per pulse - no global timestamp needed to keep the numbers readable.
    var totalHealing = 0.0

    # Calculate combat stats once before loop
    let bloodStats = calculateCombatStats(game.player)

    for enemy in game.enemies:
      if auraWaveCatches(game.player, enemy, slot, front):
        # Apply blood damage with crit chance using centralized stats
        let (damageWithCrit, wasCrit) = applyCriticalHitWithFlag(bloodStats, bloodDamage)
        let actualDamage = damageEnemy(enemy, damageWithCrit)

        # Track blood aura damage for statistics
        trackPowerUpDamage(game, puBloodAura, actualDamage)
        # Track BloodMastery bonus
        if game.player.hasBloodMastery:
          trackPowerUpDamage(game, puBloodMastery, actualDamage)

        # Accumulate healing based on damage dealt
        totalHealing += actualDamage * actualLifestealPercent

        # Use accumulation system for reliable damage numbers (use dtFire for red blood damage)
        accumulateAndShowAuraDamage(game, enemy, actualDamage, dtFire, wasCrit)

        # Visual blood particles
        if fxBudget > 0:
          dec fxBudget
          spawnExplosionPooled(game.particlePool, enemy.pos.x, enemy.pos.y,
                               getAuraPulseColor(puBloodAura), 5)

    # Apply accumulated healing to player (scaled by healPowerMult)
    if totalHealing > 0:
      let actualHeal = totalHealing * game.player.healPowerMult
      game.player.hp = min(game.player.hp + actualHeal, game.player.maxHp)
      # Attribute base healing to the Blood Aura and any multiplier bonus to puHealPower
      trackPowerUpHealing(game, puBloodAura, totalHealing)
      let bonusHealing = totalHealing * (game.player.healPowerMult - 1.0)
      if bonusHealing > 0.001 and hasPowerUp(game.player, puHealPower):
        trackPowerUpHealing(game, puHealPower, bonusHealing)

      # One healing number per beat
      game.showDamage(game.player.pos, totalHealing, fromPlayer = true,
                      isCritical = false, damageType = dtHeal)

proc updatePulseArmor(game: var Game) =
  # Pulse Armor - emit a real shove when taking damage. takeDamage() in player.nim
  # sets pulseArmorTriggered as a one-frame flag; we consume it here.
  if game.player.pulseArmorTriggered:
    game.player.pulseArmorTriggered = false
    let level = getPowerUpLevel(game.player, puPulseArmor)
    if level > 0:
      # pushForce feeds enemy.knockbackVel (a launch speed), not a per-frame nudge,
      # so enemies visibly fly outward and coast to a stop over ~0.3s.
      # Near-zero cooldown: Pulse Armor is a reactive on-hit effect, so it should
      # fire on essentially every hit. The player's post-hit invincibility window
      # naturally throttles how often it can actually trigger.
      let (pushRadius, pushForce, baseDamage, cooldown) = case level
        of 1: (130.0'f32, 520.0'f32, 0.0'f32, 0.01'f32)   # small radius, firm shove, no damage
        of 2: (175.0'f32, 680.0'f32, 2.0'f32, 0.01'f32)   # medium radius, strong shove, light damage
        else: (220.0'f32, 850.0'f32, 4.0'f32, 0.01'f32)   # large radius, hard shove, real damage

      # Damage scales with max HP so it stays relevant on tank builds
      let damageScaling = game.player.maxHp * 0.01  # 1% of max HP
      let damage = baseDamage + damageScaling

      var anyHit = false
      for enemy in game.enemies:
        let dist = distance(game.player.pos, enemy.pos)
        if dist < pushRadius:
          anyHit = true
          # Direction away from player; pick a deterministic fallback when overlapping
          let delta = enemy.pos - game.player.pos
          let awayFromPlayer =
            if delta.length() > 0.01'f32: delta.normalize()
            else: newVector2f(0, -1)

          # Stronger when closer, but with a floor so edge enemies still get launched.
          # Bosses resist the shove heavily so they don't get yanked around.
          let proximity = 0.4'f32 + 0.6'f32 * (1.0'f32 - dist / pushRadius)
          let resistance = if enemy.isBoss: 0.18'f32 else: 1.0'f32
          let launch = pushForce * proximity * resistance
          # Overwrite rather than accumulate so repeated pulses feel consistent
          enemy.knockbackVel = awayFromPlayer * launch

          # Damage for level 2 and 3 (bosses take reduced damage)
          if baseDamage > 0:
            let dmg = if enemy.isBoss: damage * 0.25'f32 else: damage
            let actualDamage = damageEnemy(enemy, dmg)
            trackPowerUpDamage(game, puPulseArmor, actualDamage)
            game.showDamage(enemy.pos, actualDamage, fromPlayer = true,
                          isCritical = false, damageType = dtDefault)

      # Juice: expanding ring sized to the push radius, plus impact shake. Shake/sound
      # only when the pulse actually catches something so empty pulses stay quiet.
      let ringColor = Color(r: 120, g: 210, b: 255, a: 255)
      spawnShockwaveRing(game, game.player.pos, pushRadius, ringColor)
      spawnExplosionPooled(game.particlePool, game.player.pos.x, game.player.pos.y,
                    ringColor, 36)
      if anyHit:
        addShake(game.dopamine.screenShake, siMedium, ringColor)
        playSound(stExplosion, 0.6)

      # Set cooldown (counted down by updatePlayer in player.nim)
      game.player.pulseArmorCooldown = cooldown

proc updatePlayerFiring(game: var Game, dt: float32) =
  # Check shooting
  let pointerPos = getWorldMousePosition()
  var mousePos = newVector2f(pointerPos.x, pointerPos.y)
  if isGamepadActive():
    # Twin-stick aim: the right stick gives a direction, not a position, so
    # project an aim point at a fixed radius from the player. With aim assist
    # on, snap onto the best enemy within a narrow cone of that direction
    # (angular offset scored with a small distance tiebreak) so the crosshair
    # visibly locks on.
    let dir = aimDir()
    const AimPointRadius = 240.0'f32
    const AssistMaxRange = 600.0'f32
    const AssistConeHalfAngle = PI.float32 / 10.0'f32  # 18 degrees
    mousePos = newVector2f(game.player.pos.x + dir.x * AimPointRadius,
                           game.player.pos.y + dir.y * AimPointRadius)
    if globalSettings.aimAssistEnabled:
      var bestScore = float32.high
      for enemy in game.enemies:
        let toEnemy = newVector2f(enemy.pos.x - game.player.pos.x,
                                  enemy.pos.y - game.player.pos.y)
        let dist = toEnemy.length()
        if dist < 1.0'f32 or dist > AssistMaxRange:
          continue
        let angleOffset = abs(arctan2(
          dir.x * toEnemy.y - dir.y * toEnemy.x,
          dir.x * toEnemy.x + dir.y * toEnemy.y))
        if angleOffset > AssistConeHalfAngle:
          continue
        let score = angleOffset + dist * 0.001'f32
        if score < bestScore:
          bestScore = score
          mousePos = newVector2f(enemy.pos.x, enemy.pos.y)
    mousePos.x = clamp(mousePos.x, 0.0'f32, game.screenWidth.float32)
    mousePos.y = clamp(mousePos.y, 0.0'f32, game.screenHeight.float32)
    setGamepadAimPointWorld(Vector2(x: mousePos.x, y: mousePos.y))
  let shootDir = newVector2f(mousePos.x - game.player.pos.x, mousePos.y - game.player.pos.y)

  # Handle delayed double-shot bursts (rapid succession)
  # LEGENDARY Double Shot: Only 1 additional burst after 0.08s delay
  if game.player.doubleShotDelay > 0:
    game.player.doubleShotDelay -= dt

    # Fire second burst when delay reaches 0 (after 0.08s has elapsed)
    if game.player.doubleShotDelay <= 0:
      let hasMultiShot = hasPowerUp(game.player, puMultiShot)
      fireDoubleShotBurst(game, shootDir, hasMultiShot)
      game.player.doubleShotDelay = 0  # Reset to 0

  let isFiring = (isMouseButtonDown(Left) and not game.wallPlacementMode) or
                 isKeyDown(globalSettings.keybinds[kaShoot]) or
                 (not game.wallPlacementMode and
                  gamepadFireDown(globalSettings.gamepadBinds))

  # Rapid Fire (Legendary) spin-up: holding fire ramps the meter to full in ~1.5s;
  # releasing decays it in ~0.8s. calculateCombatStats reads it for the bonus rate.
  if hasPowerUp(game.player, puRapidFire):
    if isFiring:
      game.player.rapidFireSpinup = min(1.0'f32, game.player.rapidFireSpinup + dt / 1.5'f32)
    else:
      game.player.rapidFireSpinup = max(0.0'f32, game.player.rapidFireSpinup - dt / 0.8'f32)

  if isFiring:
    if shootDir.length() > 0:
      shootBullet(game, shootDir)

proc updatePlayerAndAuras(game: var Game, dt: float32, effectiveDt: float32) =
  # Update player (with wall collision)
  game.player.outOfCombatSpeedBoost = game.mode == gmRoguelite and not game.waveInProgress
  updatePlayer(game.player, dt, game.screenWidth, game.screenHeight, game.walls)
  updateBossArenaGameplay(game, dt)

  # Nova freeze expiry: when novaActive becomes false, release bullets
  if not game.player.novaActive:
    for bullet in game.bullets:
      if bullet.isFrozenByNova and bullet.fromPlayer:
        bullet.vel = bullet.vel * 1.5
        bullet.isFrozenByNova = false
        bullet.isFromNova = true  # Mark for damage tracking

  # Radial Burst power-up - periodic circle of bullets
  if hasPowerUp(game.player, puRadialBurst):
    game.player.radialBurstTimer -= dt
    if game.player.radialBurstTimer <= 0:
      let level = getPowerUpLevel(game.player, puRadialBurst)
      let (bulletCount, cooldown) = case level
        of 1: (8, 3.5)
        of 2: (10, 3.0)
        else: (14, 2.0)

      # Calculate combat stats for radial burst bullets
      var stats = calculateCombatStats(game.player)
      applyBossArenaCombatBonus(game, stats)

      # Fire circle of bullets
      for i in 0..<bulletCount:
        let angle = (i.float32 / bulletCount.float32) * PI * 2.0
        let direction = newVector2f(cos(angle), sin(angle))

        # Create bullet with player's current stats
        let damageWithCrit = applyCriticalHitFromStats(stats, stats.damage)

        game.bullets.add(newBullet(
          x = game.player.pos.x,
          y = game.player.pos.y,
          direction = direction,
          speed = game.player.bulletSpeed,
          damage = damageWithCrit,
          fromPlayer = true,
          isHoming = false,
          isPiercing = hasPowerUp(game.player, puPiercingShots),
          isExplosive = hasPowerUp(game.player, puExplosiveBullets),
          hasBounce = hasPowerUp(game.player, puBulletRicochet),
          canSplit = hasPowerUp(game.player, puBulletSplit),
          slowAmount = 0.0,  # Add elemental effects if player has them
          poisonDuration = 0.0,
          fireDuration = 0.0,
          windPushForce = 0.0,
          bulletSkin = game.player.bulletSkinType,
          bulletShape = game.player.bulletShapeType,
          isFromRadialBurst = true
        ))

      # Visual feedback
      spawnExplosionPooled(game.particlePool, game.player.pos.x, game.player.pos.y,
                    Color(r: 100, g: 200, b: 255, a: 255), 25)

      game.player.radialBurstTimer = cooldown

  # Player poison damage from venomous elites
  # Uses accumulator system to ensure only whole number damage is applied
  if game.player.poisonTimer > 0:
    game.player.poisonTimer -= dt

    # Accumulate fractional damage
    game.player.poisonAccumulator += game.player.poisonDamage * dt

    # Apply damage in whole number increments
    if game.player.poisonAccumulator >= 1.0:
      let wholeDamage = game.player.poisonAccumulator.int.float32  # Floor to whole number
      game.player.poisonAccumulator -= wholeDamage  # Keep remainder

      if takeDamage(game.player, wholeDamage):
        beginPlayerDeathSequence(game, dcPoison, sourceType = game.player.poisonSourceType)
      trackDamageAvoided(game)

      # Track poison damage for statistics
      trackPlayerDamage(game, wholeDamage, game.player.poisonSourceType)

      # Create damage number for poison damage
      game.showDamage(game.player.pos, wholeDamage, fromPlayer = false,
                      isCritical = false, damageType = dtPoison)

      # Additional safety check: ensure game ends if HP reaches 0
      if game.player.hp <= 0:
        beginPlayerDeathSequence(game, dcPoison, sourceType = game.player.poisonSourceType)

    # Poison visual effect
    # Spawn ~20 particles/sec
    spawnTimedParticlesPooled(game.particlePool, game.player.pos.x, game.player.pos.y, 20.0, Green, 2, dt)

  # Regeneration power-up is now handled per wave completion, not per time interval
  # See wave completion code for regeneration logic

  updatePlayerAuras(game, dt)

  # Gravity Well (Singularity) - Pull enemies toward player with bonus effect on ranged
  if hasPowerUp(game.player, puGravityWell):
    let pullRadius = 300.0  # Single level - balanced radius
    let basePullStrength = 100.0

    for enemy in game.enemies:
      let dist = distance(game.player.pos, enemy.pos)
      if dist < pullRadius and dist > 10.0:  # Don't pull if too close
        # Calculate direction to player
        let toPlayer = (game.player.pos - enemy.pos).normalize()

        # Check if this is a ranged enemy (gets 50% extra pull)
        let isRanged = enemy.enemyType in [etCube, etPentagon, etOctagon, etHexagon, etSniper]
        let pullMultiplier = if isRanged: 1.5 else: 1.0

        # Apply pull force (stronger when closer)
        let pullForce = basePullStrength * pullMultiplier * (1.0 - (dist / pullRadius))
        enemy.pos.x += toPlayer.x * pullForce * dt
        enemy.pos.y += toPlayer.y * pullForce * dt

        # Spawn visual particles for gravity effect (more for ranged enemies)
        let particleRate = if isRanged: 15.0 else: 9.0
        let particleColor = if isRanged: Color(r: 138, g: 43, b: 226, a: 220) else: Color(r: 75, g: 0, b: 130, a: 200)
        spawnTimedParticlesAroundPooled(game.particlePool, game.player.pos.x, game.player.pos.y,
                                 pullRadius, particleRate, particleColor, 2, dt)
    # Gravity Well deliberately does not pull coins.

  updatePulseArmor(game)

  # Rotating Orbs power-up - elemental orbs that orbit the player and damage enemies
  updateOrbitalWeapons(game, dt)

  # Decay active lightning bolt visuals
  updateLightningBolts(game, dt)

  # Animate/expire AoE blast boundary rings (Star death, etc.)
  updateShockwaveRings(game, dt)

  updatePlayerFiring(game, dt)

proc updateEnemySpawning(game: var Game, dt: float32, effectiveDt: float32) =
  # MODE-SPECIFIC ENEMY SPAWNING
  if not isSandboxMode(game.mode):
    if shouldUseWaves(game.mode):
      # WAVE-BASED MODE: Spawn enemies in defined waves.
      # Roguelite dungeon rooms arm their own encounters in enterRoom, so
      # only the classic wave modes auto-start waves here.
      if game.mode != gmRoguelite and not game.waveInProgress and
         game.bossWaveManager.canStartNewWave() and game.state == gsPlaying:
        # Start a new wave
        startWave(game)

    if game.waveInProgress and game.bossSpawnTimer <= 0:
      # DYNAMIC MULTIPLE ENEMY SPAWNING - scales more with wave number
      # (in the dungeon, room threat plays the role of the wave number)
      let cadenceWave = if game.mode == gmRoguelite and game.rogueliteRun != nil and
                           game.rogueliteRun.floor != nil:
        let room = currentDungeonRoom(game.rogueliteRun)
        if room != nil: dungeonEffectiveThreat(game.rogueliteRun, room) + 4
        else: game.currentWave
      else:
        game.currentWave

      var spawnCount = if cadenceWave <= 3: 1
                       elif cadenceWave <= 8: (if rand(100) < 50: 1 else: 2)
                       elif cadenceWave <= 15: (if rand(100) < 30: 2 elif rand(100) < 70: 3 else: 4)
                       elif cadenceWave <= 25: (if rand(100) < 35: 2 elif rand(100) < 75: 3 else: 4)
                       else: (if rand(100) < 15: 3 elif rand(100) < 45: 4 elif rand(100) < 75: 5 else: 6)

      var baseSpawnRate = if cadenceWave <= 3: 1.0
                          elif cadenceWave <= 7: 1.1
                          elif cadenceWave <= 12: 1.15
                          else: 1.2

      # Wave enemies spawn faster (shorter delay between spawn ticks).
      baseSpawnRate *= 0.65

      if game.mode == gmRoguelite and game.rogueliteRun != nil and
         game.rogueliteRun.floor != nil:
        let run = game.rogueliteRun
        let pressure = themeDef(run.floor.theme).pressureMod
        let heatRank = heatChallengeRank(run.heat)
        spawnCount = max(spawnCount, int(ceil(spawnCount.float32 *
          min(2.0'f32, 0.82'f32 + pressure * 0.15'f32 +
          heatRank.float32 * RogueliteHeatSpawnBurstPerTier +
          run.endlessLoop.float32 * 0.10'f32))))
        baseSpawnRate = max(0.32'f32, baseSpawnRate / (
          1.0'f32 + (pressure - 1.0'f32) * 0.32'f32 +
          heatRank.float32 * RogueliteHeatSpawnRatePerTier +
          run.endlessLoop.float32 * 0.14'f32))

      if game.spawnTimer > baseSpawnRate and game.waveEnemiesRemaining > 0:
        if game.mode == gmRoguelite:
          spawnDungeonEnemies(game, spawnCount)
        else:
          spawnWaveEnemies(game, spawnCount)
        game.spawnTimer = 0

      # Check if wave is complete.
      # Dungeon boss rooms are excluded: they look "empty" between entering
      # and the boss actually spawning, and their clear is handled by the
      # boss-defeated path instead.
      let inDungeonBossRoom = game.mode == gmRoguelite and
        game.rogueliteRun != nil and game.rogueliteRun.floor != nil and
        currentDungeonRoom(game.rogueliteRun) != nil and
        currentDungeonRoom(game.rogueliteRun).kind == drkBoss
      if checkWaveComplete(game) and not inDungeonBossRoom:
        game.waveInProgress = false

        # Track wave completion for statistics
        let waveTime = game.time - game.waveStartTime
        trackWaveCompletion(game, game.currentWave, waveTime)

        # Regeneration power-up - heal variable HP per wave based on level
        if hasPowerUp(game.player, puRegeneration):
          let level = getPowerUpLevel(game.player, puRegeneration)
          var healAmount = 0.0

          case level
          of 1:
            # Level 1: 1.5-2.5 health (base)
            healAmount = 1.5 + rand(1.0)  # 1.5 to 2.5
          of 2:
            # Level 2: 2.5-4.5 health
            healAmount = 2.5 + rand(2.0)  # 2.5 to 4.5
          else:
            # Level 3: 3.5-6.5 health
            healAmount = 3.5 + rand(3.0)  # 3.5 to 6.5

          heal(game.player, healAmount)
          # Attribute base healing to regeneration and multiplier bonus to puHealPower
          trackPowerUpHealing(game, puRegeneration, healAmount)
          let bonusHealing = healAmount * (game.player.healPowerMult - 1.0)
          if bonusHealing > 0.001 and hasPowerUp(game.player, puHealPower):
            trackPowerUpHealing(game, puHealPower, bonusHealing)
          spawnExplosionPooled(game.particlePool, game.player.pos.x, game.player.pos.y, Green, 15)
        playSound(stWaveComplete)

        var shouldOfferPowerUp = false
        if game.mode == gmRoguelite:
          # Dungeon room cleared: bank coins/shards and open the doors.
          let outcome = onRoomCleared(game)
          shouldOfferPowerUp = outcome == dcoDraft
          # Cash in any levels earned from XP collected during this room.
          bankRunLevelUps(game)
          # RoomEcho: grant charged bullets on room clear
          if hasPowerUp(game.player, puRoomEcho):
            let echoLevel = getPowerUpLevel(game.player, puRoomEcho)
            let charges = case echoLevel
              of 1: 8
              of 2: 12
              else: 16
            game.player.roomEchoCharges += charges
        else:
          # DON'T advance wave here if we're waiting for boss coin
          # The wave will advance when the boss coin is collected
          if not game.bossWaveManager.isBossCoinActive():
            # Advance wave counters so the next wave uses the next wave number
            game.currentWave += 1
            game.wavesUntilBoss -= 1
            if game.comebackBonusActive and game.currentWave >= game.comebackEndWave:
              removeComebackBonus(game)

          # Power-ups are offered on a subset of waves, not every wave. Note
          # game.currentWave was just incremented, so this reads the *upcoming*
          # wave number.
          #
          # Wave mode: offer on every wave of a boss cycle except the first, i.e.
          # the 2nd, 3rd and 4th of each 5-wave block. The 5th is the boss wave,
          # which always grants a selection via completeBossWave. That's 3
          # selections per cycle (36 over the 60-wave campaign), matching the
          # pacing of the old every-2-waves rule.
          #
          # Other modes have no 5-wave boss cycle, so they keep the every-2 rule.
          shouldOfferPowerUp =
            if game.mode == gmWaveBased: (game.currentWave mod BossWaveInterval) >= 2
            else: (game.currentWave mod 2) == 0

        # Calculate final wave stats
        calculateAccuracy(game.dopamine.waveStats)

        # Check for perfect wave combo bonus
        let perfectWaveBonus = checkPerfectWaveCombo(game.dopamine.comboSystem, game.waveEnemiesTotal)
        if perfectWaveBonus > 0:
          game.player.coins += perfectWaveBonus
          playSound(stCoinPickup)  # Play coin sound for bonus
          trackCoinPickup(game, perfectWaveBonus)
          trackPerfectWave()  # Track for statistics

        # Wave celebration removed from here - now only happens after boss defeat

        if game.mode == gmRoguelite:
          # Stay in the room: doors are open now; the draft (if any) pops
          # immediately and returns straight to gameplay.
          if shouldOfferPowerUp:
            game.powerUpChoices = generatePowerUpChoices(
              game.player, false, unlockedFamilySet(game.rogueliteProfile), game.mode)
            game.selectedPowerUp = 0
            initPowerUpRollAnimation(game)
            initializeRerollCost(game)
            game.state = gsPowerUpSelect
          # Autosave checkpoint: room cleared, doors open.
          saveRunState(game)
          deleteSuspendSnapshot()  # Boundary: the pre-exit snapshot is stale.
        else:
          # Transition to wave cleared state for 0.3s to let players collect coins
          game.waveClearedTimer = 0.3
          game.state = gsWaveCleared
          # Autosave checkpoint: wave cleared (about to start the next wave).
          saveRunState(game)
          deleteSuspendSnapshot()  # Boundary: the pre-exit snapshot is stale.

          # Store whether we should offer power-up after the timer
          # Store this in cameFromPowerUpSelect as a temporary flag
          game.cameFromPowerUpSelect = shouldOfferPowerUp or (game.wavesUntilBoss <= 0)

    # Boss wave spawning - don't spawn if there's a boss coin waiting to be collected
    if game.wavesUntilBoss == 0 and game.bossWaveManager.canSpawnBoss() and game.state == gsPlaying:
      game.bossCount += 1
      # Scale boss difficulty based on wave number (every 3 waves = +1 difficulty)
      let bossDifficulty = if game.mode == gmRoguelite and game.rogueliteRun != nil and
                              game.rogueliteRun.floor != nil:
        dungeonBossDifficulty(game.rogueliteRun)
      else:
        (game.currentWave - 1).float32 / 3.0
      # Use a boss wave that maps to the boss block (ceil to next multiple of
      # BossWaveInterval). This allows debug spawns when wavesUntilBoss is forced
      # to 0 (boss appears for the current boss block: waves 1-4 => boss 1,
      # 5-8 => boss 2, etc.)
      let bossBlockWave = if game.mode == gmRoguelite and game.rogueliteRun != nil and
                             game.rogueliteRun.floor != nil:
        # The floor theme picks the boss; the unlocked tier and endless loop
        # shift it toward the harder definitions.
        max(BossWaveInterval, dungeonBossNumber(game) * BossWaveInterval)
      else:
        ((game.currentWave - 1) div BossWaveInterval + 1) * BossWaveInterval
      spawnConfiguredBoss(game, bossDifficulty, bossBlockWave)
      # Compress the scheduled boss's stats toward the floor's threat: the
      # definition (and spawnBoss's wave scaling) assume its wave-mode slot.
      if game.mode == gmRoguelite and game.rogueliteRun != nil and
         game.pendingBoss != nil:
        tuneDungeonBossStats(game.pendingBoss, game.rogueliteRun)

    elif isTimeSurvivalMode(game.mode):
      if game.bossTimer <= 0 and game.bossWaveManager.canSpawnBoss() and game.state == gsPlaying:
        game.bossCount += 1
        let bossBlockWave = max(BossWaveInterval, game.bossCount * BossWaveInterval)
        let bossDifficulty = max(game.difficulty, (bossBlockWave - 1).float32 / 3.0)
        spawnConfiguredBoss(game, bossDifficulty, bossBlockWave)
      # TIME SURVIVAL MODE: delegate to survival.nim
      spawnSurvivalEnemies(game)

proc updateEnemiesAndBossAttacks(game: var Game, dt: float32, effectiveDt: float32) =
  # Update enemies

  var enemyIdx = 0
  var bossDefeated = false
  while enemyIdx < game.enemies.len:
    var enemy = game.enemies[enemyIdx]

    # Curse power-up: evaluate curse eligibility once per enemy. Bosses are always
    # cursed (so the greatly-reduced bonus reliably applies); normal enemies are
    # cursed at random based on the power-up level.
    if not enemy.curseRolled and hasPowerUp(game.player, puCurse):
      enemy.curseRolled = true
      if enemy.isBoss:
        enemy.cursed = true
      else:
        let curseChance = case getPowerUpLevel(game.player, puCurse)
          of 1: 0.25
          of 2: 0.35
          else: 0.50
        enemy.cursed = rand(1.0) < curseChance

    # Update elite effects (regeneration, etc.)
    updateEliteEffects(enemy, dt)

    if enemy.isBoss and enemy.bossPhaseBreakFlashTimer > 0:
      enemy.bossPhaseBreakFlashTimer = max(0.0'f32, enemy.bossPhaseBreakFlashTimer - dt)

    # Update all active DoT effects for this enemy, remembering each element's
    # share of the tick so damage numbers and statistics can stay per-element.
    var elemTickDamage: array[ElementType, float32]
    var totalTickDamage = 0.0'f32
    for et in ElementType:
      if hasActiveEffect(enemy, et):
        elemTickDamage[et] = enemy.activeEffects[et].primary.damagePerSec * effectiveDt
        if et == etPoison:
          # Keep the display/statistics share in sync with the stacked tick
          # that updateEffects is about to deal
          elemTickDamage[et] *= poisonStackMultiplier(enemy)
        totalTickDamage += elemTickDamage[et]
    let poisonTickDamage = elemTickDamage[etPoison]
    let fireTickDamage = elemTickDamage[etFire]

    let effectDamage = updateEffects(enemy, effectiveDt)
    if effectDamage > 0:
      # Stars use hitCount instead of HP; only register a hit when the 0.5s
      # aura-accumulation window flushes, not every frame (~60x/sec).
      let actualDamage = if enemy.enemyType == etStar:
        let timeSinceFlush = game.time - enemy.auraAcc.lastTime
        if timeSinceFlush >= 0.5 or enemy.auraAcc.lastTime == 0:
          enemy.hitCount += 1
          accumulateAndShowAuraDamage(game, enemy, 0.01, dtHitCount, false)
        0.0'f32
      else:
        damageEnemy(enemy, effectDamage)
      let trackedTickDamage = poisonTickDamage + fireTickDamage

      # Track DoT damage for power-up statistics; attribute each element's tick
      # to whichever power-up applied the effect (its primary source).
      if poisonTickDamage > 0:
        let poisonActualDamage =
          if trackedTickDamage > 0: actualDamage * (poisonTickDamage / trackedTickDamage)
          else: actualDamage
        var attributed = true
        case enemy.activeEffects[etPoison].primary.source
        of "aura": trackPowerUpDamage(game, puPoisonAura, poisonActualDamage)
        of "shot", "bullet": trackPowerUpDamage(game, puPoisonShot, poisonActualDamage)
        of "orb": trackPowerUpDamage(game, puPoisonOrb, poisonActualDamage)
        else: attributed = false
        if attributed and game.player.hasPoisonMastery:
          trackPowerUpDamage(game, puPoisonMastery, poisonActualDamage)
      if fireTickDamage > 0:
        let fireActualDamage =
          if trackedTickDamage > 0: actualDamage * (fireTickDamage / trackedTickDamage)
          else: actualDamage
        var attributed = true
        case enemy.activeEffects[etFire].primary.source
        of "aura": trackPowerUpDamage(game, puFireAura, fireActualDamage)
        of "shot", "bullet": trackPowerUpDamage(game, puFireBullets, fireActualDamage)
        of "orb": trackPowerUpDamage(game, puFireOrb, fireActualDamage)
        else: attributed = false
        if attributed and game.player.hasFireMastery:
          trackPowerUpDamage(game, puFireMastery, fireActualDamage)

      # Per-element damage numbers: each element accumulates separately so a
      # burning+poisoned enemy shows fast orange ticks AND slow green chunks
      # instead of one merged number in whichever color happened to win.
      if enemy.enemyType != etStar and totalTickDamage > 0:
        for et in ElementType:
          if elemTickDamage[et] > 0:
            let elemShare = actualDamage * (elemTickDamage[et] / totalTickDamage)
            accumulateDotDamage(game, enemy, et, elemShare)

    # Update chain lightning cooldown
    if enemy.chainLightningCooldown > 0:
      enemy.chainLightningCooldown -= effectiveDt  # Use slowed time

    # Update slow timer (from Chain Lightning stun and other effects)
    if enemy.slowTimer > 0:
      enemy.slowTimer -= effectiveDt
      if enemy.slowTimer <= 0:
        enemy.slowAmount = 0

    if enemy.hitFlashTimer > 0:
      enemy.hitFlashTimer -= dt
    if enemy.spawnRingTimer > 0:
      enemy.spawnRingTimer -= dt

    discard tryAdvanceBossPhase(game, enemy)

    # Knockback impulse (Pulse Armor, etc.): integrated into position and decayed
    # on its own timeline so the chase AI in updateEnemy can't instantly cancel it.
    # This is what makes a shove read as a real launch-back rather than a nudge.
    if enemy.knockbackVel.x != 0.0 or enemy.knockbackVel.y != 0.0:
      enemy.pos.x += enemy.knockbackVel.x * effectiveDt
      enemy.pos.y += enemy.knockbackVel.y * effectiveDt
      # Keep knocked-back enemies on screen
      enemy.pos.x = clamp(enemy.pos.x, enemy.radius, game.screenWidth.float32 - enemy.radius)
      enemy.pos.y = clamp(enemy.pos.y, enemy.radius, game.screenHeight.float32 - enemy.radius)
      # Exponential falloff: punchy launch that settles in ~0.3s, framerate-independent
      let decay = pow(0.015'f32, effectiveDt)
      enemy.knockbackVel.x *= decay
      enemy.knockbackVel.y *= decay
      if enemy.knockbackVel.length() < 5.0:
        enemy.knockbackVel = newVector2f(0, 0)

    if not updateEnemy(enemy, game.player.pos, effectiveDt, game.walls, game.time, game):  # Use slowed time
      # Enemy died - show any accumulated aura/DoT damage before death
      flushAccumulatedAuraDamage(game, enemy)
      flushAccumulatedDotDamage(game, enemy)

      # Enemy died - drop coins and particles

      # Play enemy death sound; pitch creeps up with the kill combo so
      # chained kills feel escalating (bosses keep their full deep sound)
      if enemy.isBoss:
        playSound(stEnemyDeath, 1.0)
      else:
        let comboPitch = 1.0'f32 + min(game.dopamine.comboSystem.killCount, 12).float32 * 0.015
        playSound(stEnemyDeath, 0.4, comboPitch)

      # Summoner King's window now opens when its whole summoned wave is cleared
      # (handled in the boss update loop via openBossSummonWindow), so individual
      # add deaths no longer advance a separate objective counter.

      # Boss-spawned minions don't drop coins (prevent farming)
      if not enemy.spawnedByBoss:
        dropEnemyCoin(game, enemy)

      # Run-leveling modes (roguelite + survival): enemies also drop auto-homing
      # XP orbs (dropEnemyXp guards mode + spawnedByBoss internally).
      dropEnemyXp(game, enemy)

      # Elite Explosive death effect
      # Handles multiple elite types (wave 25+)
      if enemy.isElite and etExplosive in enemy.eliteTypes:
        const eliteExplosionRadius = 100.0
        const eliteExplosionDamage = 2.0

        # Play explosion sound
        playSound(stExplosion, 0.7)

        # Check if player is in explosion radius
        let distToPlayer = distance(enemy.pos, game.player.pos)
        if distToPlayer < eliteExplosionRadius:
          if takeDamage(game.player, eliteExplosionDamage):
            beginPlayerDeathSequence(game, dcExplosion, source = enemy)
          trackDamageAvoided(game)

          # Track explosion damage for statistics
          trackPlayerDamage(game, eliteExplosionDamage, enemy.enemyType)

          # Create damage number for explosion damage
          game.showDamage(game.player.pos, eliteExplosionDamage, fromPlayer = false,
                          isCritical = false, damageType = dtExplosion)

        # Create explosion visual
        spawnExplosionPooled(game.particlePool, enemy.pos.x, enemy.pos.y,
                      Color(r: 255, g: 128, b: 0, a: 255), 40)
        spawnShockwavePooled(game.particlePool, enemy.pos.x, enemy.pos.y, eliteExplosionRadius)

      # Star explosion on death - damages player if too close
      if enemy.enemyType == etStar:
        const explosionRadius = 120.0  # LARGER explosion radius
        const explosionDamage = 3.0

        # Play explosion sound
        playSound(stExplosion, 0.8)

        # Check if player is in explosion radius
        let distToPlayer = distance(enemy.pos, game.player.pos)
        if distToPlayer < explosionRadius:
          if takeDamage(game.player, explosionDamage):
            beginPlayerDeathSequence(game, dcExplosion, source = enemy)
          trackDamageAvoided(game)

          # Track boss explosion damage for statistics
          trackPlayerDamage(game, explosionDamage, enemy.enemyType)

          # Create damage number for boss explosion damage
          game.showDamage(game.player.pos, explosionDamage, fromPlayer = false,
                          isCritical = false, damageType = dtExplosion)

        # Create MASSIVE explosion visual with multiple layers
        spawnExplosionPooled(game.particlePool, enemy.pos.x, enemy.pos.y,
                      Color(r: 255, g: 150, b: 0, a: 255), 60)  # More particles
        spawnExplosionPooled(game.particlePool, enemy.pos.x, enemy.pos.y,
                      Color(r: 255, g: 220, b: 100, a: 255), 40)  # Bright inner core
        # Boundary ring that snaps out to *exactly* the lethal radius and holds
        # there while fading, so the player can read the blast size. Scattered
        # particles alone fly past the edge and never show where damage ends.
        spawnShockwaveRing(game, enemy.pos, explosionRadius,
                           Color(r: 255, g: 140, b: 40, a: 255))
        # A single spark ring at the boundary adds crackle without hiding the edge
        spawnShockwavePooled(game.particlePool, enemy.pos.x, enemy.pos.y, explosionRadius)

      # Death particles, rich multi-layer burst
      spawnEnemyDeathBurst(game.particlePool, enemy.pos.x, enemy.pos.y,
                           enemy.color, enemy.radius, enemy.isBoss)

      # Drop consumable
      if enemy.isBoss:
        # BOSSES ALWAYS DROP HEALTH - offset from coin position so it's visible
        let clampedPos = clampLootPosition(enemy.pos.x, enemy.pos.y, game.screenWidth, game.screenHeight)
        # Offset health drop 40 pixels to the right of the coin
        let healthX = clampedPos.x + 40.0
        let healthY = clampedPos.y
        let healthPos = clampLootPosition(healthX, healthY, game.screenWidth, game.screenHeight)
        game.consumables.add(newSpecificConsumable(healthPos.x, healthPos.y, ctHealth))
      elif not enemy.spawnedByBoss:
        # Cornucopia (puBountiful): increased drop rate + kill-milestone drops
        let clampedPos = clampLootPosition(enemy.pos.x, enemy.pos.y, game.screenWidth, game.screenHeight)
        let consumableDifficulty = if game.mode == gmWaveBased: 1.0 else: game.difficulty

        if game.player.hasBountiful:
          game.player.bountifulKillCounter += 1

          # Every 15th kill: jackpot burst, 3 consumables scattered around the enemy
          if game.player.bountifulKillCounter >= 15:
            game.player.bountifulKillCounter = 0
            for j in 0..<3:
              let scatter = float32(j) * (PI * 2.0'f32 / 3.0'f32)
              let bx = clampedPos.x + cos(scatter) * 28.0'f32
              let by = clampedPos.y + sin(scatter) * 28.0'f32
              let bp = clampLootPosition(bx, by, game.screenWidth, game.screenHeight)
              game.consumables.add(newConsumable(bp.x, bp.y, consumableDifficulty))
            # JACKPOT! A golden celebratory burst that's distinct from a normal
            # kill explosion: a layered nova core, two expanding shockwave rings,
            # and a coin-gold spiral, capped with a short screen pop.
            let jackpotGold  = Color(r: 255, g: 215, b: 70, a: 255)
            let jackpotAmber = Color(r: 255, g: 150, b: 30, a: 255)
            spawnNovaExplosionPooled(game.particlePool, clampedPos.x, clampedPos.y,
                                     95.0'f32, jackpotGold, jackpotAmber)
            spawnShockwavePooled(game.particlePool, clampedPos.x, clampedPos.y, 55.0'f32)
            spawnShockwavePooled(game.particlePool, clampedPos.x, clampedPos.y, 110.0'f32)
            spawnSpiralExplosionPooled(game.particlePool, clampedPos.x, clampedPos.y,
                                       75.0'f32, 5, jackpotGold)
            addShake(game.dopamine.screenShake, siMedium, jackpotGold)

          # Base 30% drop chance for all other kills
          elif rand(99) < 30:
            game.consumables.add(newConsumable(clampedPos.x, clampedPos.y, consumableDifficulty))

        else:
          # Regular enemies have 15% chance to drop a consumable
          if rand(99) < 15:
            # Clamp consumable position to be in bounds (for enemies killed out-of-bounds)
            game.consumables.add(newConsumable(clampedPos.x, clampedPos.y, consumableDifficulty))

      game.player.kills += 1

      # Lifesteal consumable - heal 50 HP per kill
      if game.player.lifestealTimer > 0:
        heal(game.player, 0.5)
        # Show heal damage number
        showDamage(game, game.player.pos, 1.0, true, false, dtHeal)

      recordKill(game.dopamine.realTimeStats)

      if enemy.isBoss:
        # Boss kill - MASSIVE effects
        addShake(game.dopamine.screenShake, siMassive)
        activateSlowMo(game.dopamine.slowMotion, smtBossKill)
        # Record kill with high damage for stats
        let bossKillHp = if enemy.bossTotalMaxHp > 0.0'f32: enemy.bossTotalMaxHp else: enemy.maxHp
        recordKill(game.dopamine.waveStats, bossKillHp)
      else:
        # Regular enemy kill - standard effects
        addShake(game.dopamine.screenShake, siMedium)
        activateSlowMo(game.dopamine.slowMotion, smtKill)
        recordKill(game.dopamine.waveStats, 0)  # Don't track individual enemy damage for non-bosses

      # Track combo and award bonus coins (but not for boss minions)
      if not enemy.spawnedByBoss:
        let comboBonus = addComboKill(game.dopamine.comboSystem, game.dopamine.currentTime)
        if comboBonus > 0:
          game.player.coins += comboBonus
          trackCoinPickup(game, comboBonus)
          recordCombo(game.dopamine.waveStats, game.dopamine.comboSystem.killCount)

        # Track combo statistics for run stats
        trackCombo(game, game.dopamine.comboSystem.killCount)

      # Track enemy kill for statistics
      trackEnemyKilled(game, enemy)

      # Life steal power-up effect
      if hasPowerUp(game.player, puLifeSteal):
        let level = getPowerUpLevel(game.player, puLifeSteal)
        game.player.killsSinceLastHeal += 1
        let healsPerKills = case level
          of 1: 10
          of 2: 7
          else: 5

        if game.player.killsSinceLastHeal >= healsPerKills:
          heal(game.player, 1.0)  # Heal 100 HP
          # Attribute base healing to the lifesteal source and bonus to puHealPower
          trackPowerUpHealing(game, puLifeSteal, 1.0)
          let bonusHealing = 1.0 * (game.player.healPowerMult - 1.0)
          if bonusHealing > 0.001 and hasPowerUp(game.player, puHealPower):
            trackPowerUpHealing(game, puHealPower, bonusHealing)
          game.player.killsSinceLastHeal = 0
          spawnExplosionPooled(game.particlePool, game.player.pos.x, game.player.pos.y, Green, 15)

      # TimeSurge: each kill extends the fire rate boost timer (survival only)
      if hasPowerUp(game.player, puTimeSurge):
        let surgeBonus = case getPowerUpLevel(game.player, puTimeSurge)
          of 1: 0.5'f32
          of 2: 0.75'f32
          else: 1.0'f32
        game.player.fireRateBoostTimer = min(game.player.fireRateBoostTimer + surgeBonus, 10.0'f32)

      # SectorProtocol: each kill grants +1 coin
      if game.player.hasSectorProtocol and not enemy.isBoss:
        game.player.coins += 1

      # LastTransmission: chance to heal 0.5 HP on kill
      if hasPowerUp(game.player, puLastTransmission) and not enemy.isBoss:
        let ltLevel = getPowerUpLevel(game.player, puLastTransmission)
        let healChance = case ltLevel
          of 1: 12
          of 2: 18
          else: 25
        if rand(99) < healChance:
          heal(game.player, 0.5)
          # Attribute base healing to Last Transmission and bonus to puHealPower
          trackPowerUpHealing(game, puLastTransmission, 0.5)
          let bonusHealing = 0.5 * (game.player.healPowerMult - 1.0)
          if bonusHealing > 0.001 and hasPowerUp(game.player, puHealPower):
            trackPowerUpHealing(game, puHealPower, bonusHealing)
          showDamage(game, game.player.pos, 0.5, true, false, dtHeal)

      # KillChain: 5 kills in 3s triggers a shockwave
      if hasPowerUp(game.player, puKillChain) and not enemy.isBoss:
        game.player.killChainCount += 1
        game.player.killChainTimer = 3.0'f32
        if game.player.killChainCount >= 5:
          game.player.killChainCount = 0
          game.player.killChainTimer = 0
          const killChainRadius = 350.0'f32
          let chainStats = calculateCombatStats(game.player)
          let chainDamage = chainStats.damage * 1.5'f32
          for otherEnemy in game.enemies:
            let dist = distance(game.player.pos, otherEnemy.pos)
            if dist <= killChainRadius:
              let actual = damageEnemy(otherEnemy, chainDamage)
              trackPowerUpDamage(game, puKillChain, actual)
              game.showDamage(otherEnemy.pos, actual, fromPlayer = true, isCritical = false, damageType = dtDefault)
          spawnExplosionPooled(game.particlePool, game.player.pos.x, game.player.pos.y,
                               Color(r: 255, g: 120, b: 50, a: 255), 50)
          spawnShockwavePooled(game.particlePool, game.player.pos.x, game.player.pos.y, killChainRadius)
          addShake(game.dopamine.screenShake, siMedium, Color(r: 255, g: 120, b: 50, a: 255))
          playSound(stExplosion, 0.8)

      # ChainReaction: chance to drop a bonus coin on kill
      if hasPowerUp(game.player, puChainReaction) and not enemy.isBoss:
        let crLevel = getPowerUpLevel(game.player, puChainReaction)
        let coinChance = case crLevel
          of 1: 20
          of 2: 30
          else: 40
        if rand(99) < coinChance:
          let clampedPos = clampLootPosition(enemy.pos.x, enemy.pos.y, game.screenWidth, game.screenHeight)
          game.coins.add(newCoin(clampedPos.x, clampedPos.y))

      # CorruptedCore: elite kills grant max HP
      if hasPowerUp(game.player, puCorruptedCore) and enemy.isElite and not enemy.isBoss:
        let ccLevel = getPowerUpLevel(game.player, puCorruptedCore)
        let hpGain = case ccLevel
          of 1: 1.0'f32
          of 2: 1.5'f32
          else: 2.0'f32
        game.player.maxHp += hpGain
        heal(game.player, hpGain)
        spawnExplosionPooled(game.particlePool, game.player.pos.x, game.player.pos.y,
                             Color(r: 120, g: 255, b: 120, a: 255), 20)
        showDamage(game, game.player.pos, hpGain, true, false, dtHeal)

      # Check if boss was defeated
      if enemy.isBoss:
        bossDefeated = true
        # Remember this boss so its full phase layout may be revealed next time.
        if globalStats != nil and not game.cheatsUsed and enemy.bossDefinitionID > 0 and
           not globalStats.hasDefeatedBoss(enemy.bossDefinitionID):
          globalStats.markBossDefeated(enemy.bossDefinitionID)
          discard saveStatistics(globalStats)
        if game.mode == gmRoguelite:
          game.bossWaveManager.clearBossWave()
        elif shouldUseWaves(game.mode):
          game.bossWaveManager.bossDefeated()
        else:
          game.bossWaveManager.clearBossWave()
          game.bossTimer = TIME_SURVIVAL_BOSS_INTERVAL

        # Mode-specific boss defeat handling - NO longer advance wave here
        # Wave will advance when boss coin is collected

      # Volatile: death pulse spreads active elements to nearby enemies
      if game.player.hasVolatile:
        var activeEffectCount = 0
        for et, ae in enemy.activeEffects:
          if ae.primary.isActive:
            activeEffectCount += 1
        if activeEffectCount >= 2:
          const volatilePulseRadius = 120.0
          for otherEnemy in game.enemies:
            if otherEnemy.id != enemy.id:
              let dist = distance(enemy.pos, otherEnemy.pos)
              if dist <= volatilePulseRadius:
                # Spread each active element at 60% DPS and 50% duration
                for et, ae in enemy.activeEffects:
                  if ae.primary.isActive:
                    applyEffect(otherEnemy, ae.primary.elementType,
                                ae.primary.damagePerSec * 0.6,
                                ae.primary.remainingDuration * 0.5,
                                "volatile_pulse")
          spawnExplosionPooled(game.particlePool, enemy.pos.x, enemy.pos.y,
                        Color(r: 255, g: 150, b: 50, a: 255), 20)

      game.enemies.delete(enemyIdx)
      continue

    # Write back modified enemy to array
    game.enemies[enemyIdx] = enemy
    enemyIdx += 1

  # Enemy-to-enemy collision detection (prevents overlapping)
  # Uses smaller collisionRadius for more natural-feeling spacing.
  #
  # Spatial-grid accelerated: instead of testing every enemy against every other
  # (O(enemies^2)), each enemy only tests neighbours in nearby cells. The query
  # radius -- this enemy's reach plus the largest collision radius on screen --
  # is guaranteed to be >= the minDist of any genuinely overlapping pair, so no
  # overlap that the old loop would resolve is skipped. The `j > i` guard keeps
  # every unordered pair processed exactly once, and the push math is unchanged.
  # (Like the original it stays a single-pass relaxation -- it reads live, already
  # pushed positions -- so the soft spacing converges over frames exactly as before.)
  rebuildEnemyGrid(game)
  for i in 0..<game.enemies.len:
    let queryRadius = game.enemies[i].collisionRadius + gridMaxCollisionRadius
    for j in enemyGrid.nearby(game.enemies[i].pos, queryRadius):
      if j <= i: continue
      let dist = distance(game.enemies[i].pos, game.enemies[j].pos)
      let minDist = game.enemies[i].collisionRadius + game.enemies[j].collisionRadius

      if dist < minDist and dist > 0:
        # Enemies are overlapping - push them apart
        let overlap = minDist - dist
        let pushDir = (game.enemies[j].pos - game.enemies[i].pos).normalize()

        # Push each enemy half the overlap distance (equal force)
        let pushAmount = overlap * 0.5
        game.enemies[i].pos = game.enemies[i].pos - pushDir * pushAmount
        game.enemies[j].pos = game.enemies[j].pos + pushDir * pushAmount

  # Boss attack loop
  enemyIdx = 0
  while enemyIdx < game.enemies.len:
    var enemy = game.enemies[enemyIdx]

    # BOSS SPECIAL ATTACKS
    if enemy.isBoss:
      # CUSTOM BOSS ATTACKS - Full pattern system from boss_definitions.nim
      # Get boss definition and update phase-shield timing.
      let bossDef = getBossDefinition(enemy.bossDefinitionID)

      # Update invulnerability timer
      if enemy.invulnerabilityTimer > 0:
        enemy.invulnerabilityTimer -= dt
        if enemy.invulnerabilityTimer < 0:
          enemy.invulnerabilityTimer = 0

      # Mega-cast channel (e.g. boss 4's ricochet beam): tick it down and keep
      # the boss frozen in place while it charges.
      if enemy.megaCastTimer > 0:
        enemy.megaCastTimer -= dt
        if enemy.megaCastTimer <= 0:
          enemy.megaCastTimer = 0
          enemy.megaCastTotal = 0
        else:
          enemy.vel = newVector2f(0, 0)

      # Update boss behavior based on specialBehavior. The boss holds completely
      # still during a phase-change transition (and while channelling a mega
      # special) so the animation reads as a dramatic "charge up" beat rather
      # than a moving target.
      if enemy.invulnerabilityTimer <= 0 and enemy.megaCastTimer <= 0 and
         enemy.currentPhaseIndex < bossDef.phases.len:
        let phase = bossDef.phases[enemy.currentPhaseIndex]

        # Ranged-pattern bosses maintain a safe preferred distance from the player.
        # Within the preferred radius they slow noticeably; inside the inner radius
        # a retreat push is applied AFTER movement so pattern-based paths
        # (figure-8, orbits, lasers) can't accidentally pin the player in a corner.
        const RANGED_BOSS_PREFERRED_DIST = 150.0'f32  # Start slowing inside this
        const RANGED_BOSS_INNER_DIST     =  80.0'f32  # Apply retreat push inside this
        const RANGED_BOSS_CLOSE_DIST     =  20.0'f32  # Original hard-close slow for melee

        let isRangedBossPhase = phase.specialBehavior in [
          "geometric_movement", "laser_web",      "laser_chaos",
          "defensive",          "summon_frenzy",
          "prism_defense",      "prism_array",     "light_cascade",
          "slow_time",          "time_distortion", "time_collapse",
          "orbital_pattern",    "satellite_swarm", "deploy_satellites", "multi_orbital",
          "orbital_chaos",                          # Boss 7 P3: zone like its earlier phases (was omitted)
          "electric_buildup",   "electric_surge",
          "critical_discharge"                      # Boss 6 P3: zone like its earlier phases (was omitted)
        ]

        let distToPlayer = distance(enemy.pos, game.player.pos)
        let savedSpeed = enemy.speed
        if not enemy.isDashing:
          if isRangedBossPhase:
            if distToPlayer < RANGED_BOSS_INNER_DIST:
              # Very close: slow to 50%, noticeable but not a wall
              enemy.speed *= 0.5
            elif distToPlayer < RANGED_BOSS_PREFERRED_DIST:
              # Gradual taper: full speed at preferred dist, 50% at inner dist
              let t = (distToPlayer - RANGED_BOSS_INNER_DIST) /
                      (RANGED_BOSS_PREFERRED_DIST - RANGED_BOSS_INNER_DIST)
              enemy.speed *= 0.5 + t * 0.5
          elif distToPlayer < RANGED_BOSS_CLOSE_DIST:
            enemy.speed *= 0.5  # Original melee-boss hard-close slow

        updateCustomBossBehavior(game, enemy, phase, dt)
        enemy.speed = savedSpeed  # Always restore the real speed

        # Post-movement retreat push: gently nudge ranged bosses away from
        # the player after pattern movement to prevent unintended pin-downs.
        if isRangedBossPhase and not enemy.isDashing:
          let postDist = distance(enemy.pos, game.player.pos)
          if postDist < RANGED_BOSS_INNER_DIST and postDist > 0.1'f32:
            let awayDir = (enemy.pos - game.player.pos).normalize()
            let pushStrength = (1.0'f32 - postDist / RANGED_BOSS_INNER_DIST) * 50.0'f32
            enemy.pos.x += awayDir.x * pushStrength * dt
            enemy.pos.y += awayDir.y * pushStrength * dt

      # Handle boss dash movement (overrides normal movement)
      if enemy.isDashing:
        enemy.dashDuration -= dt
        if enemy.dashDuration > 0:
          # Apply dash velocity strictly along the committed warning line.
          # Projection keeps inertia/other systems from nudging the boss off-path.
          let dashStart = enemy.pendingDashStart
          let dashEnd = enemy.dashTargetPos
          let dashPath = dashEnd - dashStart
          let dashLenSq = dashPath.x * dashPath.x + dashPath.y * dashPath.y
          if dashLenSq > 0.01'f32:
            let proposedPos = enemy.pos + enemy.dashVelocity * dt
            let fromStart = proposedPos - dashStart
            let progress = clamp((fromStart.x * dashPath.x + fromStart.y * dashPath.y) / dashLenSq,
                                 0.0'f32, 1.0'f32)
            enemy.pos = dashStart + dashPath * progress
            if progress >= 1.0'f32:
              enemy.dashDuration = 0
          else:
            enemy.dashDuration = 0

          # Create dash trail particles ~15 times/sec regardless of fps
          if (enemy.dashDuration mod (1.0 / 15.0)) < dt:
            let trailColor = if enemy.currentPhaseIndex < bossDef.phases.len:
              bossDef.phases[enemy.currentPhaseIndex].color
            else:
              Red
            spawnExplosionPooled(game.particlePool, enemy.pos.x, enemy.pos.y, trailColor, 5)
        else:
          # Dash complete
          enemy.vel = enemy.dashVelocity
          enemy.isDashing = false
          enemy.dashDuration = 0
          if enemy.currentPhaseIndex < bossDef.phases.len:
            let endColor = bossDef.phases[enemy.currentPhaseIndex].color
            spawnExplosionPooled(game.particlePool, enemy.pos.x, enemy.pos.y, endColor, 20)

      # Boss smashes through dungeon obstacles. Custom bosses move by directly
      # setting enemy.pos (above) and never run the enemy/wall collision path, so
      # contact damage can't reach walls - destroy any obstacle the boss now
      # overlaps. Setting hp to 0 lets the wall-update loop handle the explosion
      # and queue the boss-room respawn (no self-damage to the boss). Skipped
      # during the fly-in entrance so the boss doesn't clear a swath on arrival.
      if enemy.entranceTimer <= 0:
        for wall in game.walls:
          if wall.permanent and wall.hp > 0 and
             distance(enemy.pos, wall.pos) < enemy.radius + wall.radius:
            wall.hp = 0

      updateBossWeakPoint(enemy, bossDef.weakPoint, game.player.pos, game.screenWidth, game.screenHeight, dt)
      updateBossMechanics(game, enemy, dt)

      # Count this boss's still-living summoned adds. While any survive, the
      # summon attack's countdown is frozen, so the loop is: summon -> player
      # clears the adds -> countdown starts -> countdown ends -> summon again.
      # This prevents an unkillable pile-up and keeps the adds-gate fair.
      var livingSummons = 0
      for other in game.enemies:
        if other.spawnedByBoss and other.hp > 0:
          livingSummons += 1
      let hasSummonPhase = enemy.currentPhaseIndex < bossDef.phases.len

      # Summoner King: drive the objective from the live add count (single source of
      # truth - no desync). Pips show how much of the wave is cleared; clearing the
      # whole wave opens the vulnerability window. Gated to the summon objective.
      if enemy.summonWaveActive and enemy.weakPoint.kind == bwoSummonSigils:
        enemy.weakPoint.progress = max(0, enemy.weakPoint.required - livingSummons)
        if livingSummons == 0:
          let summonWindow = openBossSummonWindow(enemy)
          if summonWindow.opened:
            enemy.summonWaveActive = false
            enemy.weakPoint.required = 0  # hide the cleared pips during the window
            if summonWindow.bonusDamage > 0:
              let dealt = applyEnemyHpDamage(enemy, summonWindow.bonusDamage)
              if dealt > 0:
                showDamage(game, enemy.pos, dealt, true, false, dtArcane)
                recordDamage(game.dopamine.realTimeStats, dealt, game.time)
                addShake(game.dopamine.screenShake, siLarge)

      # Update attack timers. Enrage (from ignoring an open objective) makes them
      # tick down faster, so a stalled boss attacks more frequently.
      let enrageRate = 1.0'f32 + enemy.bossEnrageLevel
      for i in 0..<enemy.attackTimers.len:
        # While channelling a mega special the boss commits fully: every other
        # attack countdown is paused so nothing else fires during the beam.
        if enemy.megaCastTimer > 0:
          break
        # Freeze the summon countdown until every summoned add is dead.
        if livingSummons > 0 and hasSummonPhase and
            i < bossDef.phases[enemy.currentPhaseIndex].attacks.len and
            bossDef.phases[enemy.currentPhaseIndex].attacks[i].attackType == bapSummon:
          continue
        enemy.attackTimers[i] -= dt * enrageRate

      # Execute attacks when timers expire, emit pre-fire warning ~0.4 s before each shot
      if enemy.currentPhaseIndex < bossDef.phases.len:
        let phase = bossDef.phases[enemy.currentPhaseIndex]
        const WARNING_LEAD_TIME = 0.4'f32
        for i, attack in phase.attacks:
          # Once a mega cast is underway (including the moment it just started
          # this frame), suppress every other attack's warning/fire.
          if enemy.megaCastTimer > 0:
            break
          if i < enemy.attackTimers.len:
            # Show pre-fire warning once per cycle, fires as soon as the timer
            # enters the warning window, regardless of cooldown length.
            # This works even when cooldown <= WARNING_LEAD_TIME.
            if enemy.attackTimers[i] <= WARNING_LEAD_TIME and
               not enemy.attackWarningFired[i]:
              addBossAttackWarning(game, enemy, attack)
              enemy.attackWarningFired[i] = true
            # Fire attack when timer reaches zero; reset for next cycle
            if enemy.attackTimers[i] <= 0:
              # Beams already own part of the floor. Stacking an *aimed* volley
              # on top of one takes away the lane the beam left open, which is
              # what makes beam phases read as undodgeable. A beam that is
              # nearly spent just delays the volley (re-telegraphed on the way
              # back in); a beam with real time left lets it through at half
              # density so the boss is never fully muzzled.
              let beamRemain = bossLaserThreatRemaining(game)
              if beamRemain > 0 and attack.attackType in LaserOverlapSuppressed:
                if beamRemain <= LaserOverlapDeferMax:
                  enemy.attackTimers[i] = beamRemain
                  enemy.attackWarningFired[i] = false
                  continue
                executeCustomBossAttack(game, enemy, thinnedForLaserOverlap(attack),
                                        phase, bossDef)
              else:
                executeCustomBossAttack(game, enemy, attack, phase, bossDef)
              enemy.attackTimers[i] = attack.cooldown
              enemy.attackWarningFired[i] = false

      # Drive any in-flight spiral volley armed by bapSpiral. This emits one step
      # per frame independent of the attack cooldown, which is what makes the
      # bullet trail an actual spiral rather than a ring.
      updateBossSpiralStream(game, enemy, dt)

    # Regular enemy shooting (config-driven system)
    if enemy.enemyType in [etCube, etHexagon, etOctagon, etPentagon, etPhantom, etDiamond, etMage]:
      let config = getEnemyConfig(enemy.enemyType)

      # Only shoot if enemy has ranged attack configured
      if config.hasRangedAttack:
        let attackConfig = config.attack
        # Per-enemy damage so elite bonuses and dungeon tuning reach bullets
        let enemyBulletDamage = if enemy.rangedDamage > 0: enemy.rangedDamage
                                else: attackConfig.damage

        # Check shoot timer
        if enemy.shootTimer > attackConfig.fireRate:
          let dir = (game.player.pos - enemy.pos).normalize()

          # Handle burst shooting
          if attackConfig.usesBurst:
            for i in 0..<attackConfig.burstCount:
              let spreadAngle = (i - (attackConfig.burstCount div 2)).float32 * attackConfig.spreadAngle
              let spreadDir = newVector2f(
                dir.x * cos(spreadAngle) - dir.y * sin(spreadAngle),
                dir.x * sin(spreadAngle) + dir.y * cos(spreadAngle)
              )

              let bullet = newBullet(
                x = enemy.pos.x,
                y = enemy.pos.y,
                direction = spreadDir,
                speed = attackConfig.bulletSpeed,
                damage = enemyBulletDamage,
                fromPlayer = false,
                isHoming = attackConfig.homingStrength > 0,
                sourceEnemyId = enemy.id,
                sourceEnemyType = enemy.enemyType
              )

              # Apply special bullet properties
              if attackConfig.isPentagonBullet:
                bullet.radius = 10  # Larger pentagon bullet

              game.bullets.add(bullet)
          else:
            # Non-burst shooting
            for i in 0..<attackConfig.bulletCount:
              var shootDir: Vector2f

              if attackConfig.spreadAngle >= 6.0:  # Full circle (chaotic)
                # Random direction for chaotic enemies like Hexagon
                let angle = rand(1.0) * PI * 2.0
                shootDir = newVector2f(cos(angle), sin(angle))
              else:
                # Spread pattern
                let spreadAngle = (i - (attackConfig.bulletCount div 2)).float32 * attackConfig.spreadAngle
                shootDir = newVector2f(
                  dir.x * cos(spreadAngle) - dir.y * sin(spreadAngle),
                  dir.x * sin(spreadAngle) + dir.y * cos(spreadAngle)
                )

              # Add inaccuracy for Octagon
              if enemy.enemyType == etOctagon:
                let inaccuracy = (rand(1.0) - 0.5) * attackConfig.spreadAngle
                shootDir = newVector2f(
                  shootDir.x * cos(inaccuracy) - shootDir.y * sin(inaccuracy),
                  shootDir.x * sin(inaccuracy) + shootDir.y * cos(inaccuracy)
                )

              let bullet = newBullet(
                x = enemy.pos.x,
                y = enemy.pos.y,
                direction = shootDir,
                speed = attackConfig.bulletSpeed,
                damage = enemyBulletDamage,
                fromPlayer = false,
                isHoming = attackConfig.homingStrength > 0,
                sourceEnemyId = enemy.id,
                sourceEnemyType = enemy.enemyType
              )

              # Apply special bullet properties
              if attackConfig.isPentagonBullet:
                bullet.radius = 10  # Larger pentagon bullet

              game.bullets.add(bullet)

          enemy.shootTimer = 0

    # Check collision with player (with small coyote/forgiveness zone on edges)
    # Reduce effective collision radius by 10% for slight edge forgiveness
    let effectivePlayerRadius = game.player.radius * 0.90  # 10% reduction = coyote
    if distance(enemy.pos, game.player.pos) < enemy.radius + effectivePlayerRadius:
      if enemy.isBoss:
        # Boss deals continuous damage: 10% of the player's max HP per second.
        # Damage applied each tick is DPS * elapsed_time (capped to the intended interval)
        if game.time - enemy.lastContactDamageTime >= 0.5:
          let elapsed = min(game.time - enemy.lastContactDamageTime, 0.5'f32)
          let bossDps = 0.10'f32 * game.player.maxHp
          var bossContactDamage = bossDps * elapsed

          # Thorns reflection damage
          discard applyThornsReflection(game, game.player, bossContactDamage, enemy, "boss")

          let playerDied = takeDamage(game.player, bossContactDamage)
          trackDamageAvoided(game)

          # Pulse Armor knockback is handled centrally by the trigger block in
          # updateGame (takeDamage above sets the -1 trigger flag).

          if playerDied:
            beginPlayerDeathSequence(game, dcBossContact, source = enemy)

          # Track boss contact damage for statistics
          trackPlayerDamage(game, bossContactDamage, enemy.enemyType)

          # Create damage number for boss contact damage
          game.showDamage(game.player.pos, bossContactDamage, fromPlayer = false,
                          isCritical = false, damageType = dtDefault)

          playSound(stPlayerHit, 0.6)
          enemy.lastContactDamageTime = game.time
          spawnExplosionPooled(game.particlePool, game.player.pos.x, game.player.pos.y, Red, 10)
      else:
        # Regular enemies deal contact damage with cooldown
        if game.time - enemy.lastContactDamageTime >= 0.33:  # Contact damage cooldown
          var enemyContactDamage = enemy.contactDamage.float32  # Damage enemy deals to player

          # Venomous elite effect - applies poison to player
          # Handles multiple elite types (wave 25+)
          if enemy.isElite and etVenomous in enemy.eliteTypes:
            game.player.poisonTimer = 3.0  # 3 seconds of poison
            game.player.poisonDamage = 0.5  # 0.5 DPS = 1.5 total damage
            game.player.poisonAccumulator = 0.0  # Reset accumulator for new poison application
            game.player.poisonSourceType = enemy.enemyType  # Track source for stats
            spawnExplosionPooled(game.particlePool, game.player.pos.x, game.player.pos.y, Green, 10)

          # Thorns reflection damage - damages enemy but doesn't kill instantly
          discard applyThornsReflection(game, game.player, enemyContactDamage, enemy, "contact")

          let playerDied = takeDamage(game.player, enemyContactDamage)
          trackDamageAvoided(game)

          # Pulse Armor knockback is handled centrally by the trigger block in
          # updateGame (takeDamage above sets the -1 trigger flag).

          if playerDied:
            beginPlayerDeathSequence(game, dcContact, source = enemy)

          # Track enemy contact damage for statistics
          trackPlayerDamage(game, enemyContactDamage, enemy.enemyType)

          # Create damage number for player taking damage
          showDamage(game, game.player.pos, enemyContactDamage, false, false, dtDefault)

          playSound(stPlayerHit, 0.5)

          # Deal contact damage to enemy based on player damage stat, speed, and crits
          let (contactDamageToEnemy, contactWasCrit) = calculateContactDamageToEnemy(game.player, enemy)

          # Stars use hit counter for all damage sources
          if enemy.enemyType == etStar:
            enemy.hitCount += 1
          else:
            discard damageEnemy(enemy, contactDamageToEnemy)

          enemy.lastContactDamageTime = game.time

          # Accumulate damage for damage number display (shows every 0.5s)
          # Crits shown immediately and in the right color
          if contactWasCrit:
            showDamage(game, enemy.pos, contactDamageToEnemy, true, true, dtCritical)
          else:
            accumulateAndShowContactDamage(game, enemy, contactDamageToEnemy)

          # Visual feedback, more particles for crits
          let contactParticleCount = if contactWasCrit: 8 else: 3
          spawnExplosionPooled(game.particlePool, enemy.pos.x, enemy.pos.y, enemy.color, contactParticleCount)

          # Remove enemy if HP reaches 0. Bosses are never deleted here: a boss
          # at 0 HP may still have phases left, and full defeat bookkeeping
          # (bossDefeated, wave flow, rewards) lives in the main enemy update
          # loop, so a contact kill must funnel through it instead.
          if enemy.hp <= 0:
            if enemy.isBoss:
              discard tryAdvanceBossPhase(game, enemy)
            else:
              # Flush any accumulated contact damage before death
              flushAccumulatedContactDamage(game, enemy)
              game.enemies.delete(enemyIdx)
              continue

    enemyIdx += 1

  if bossDefeated and game.mode == gmRoguelite:
    # Boss room counts as a completed room: bank levels from XP collected in the
    # fight. Stat boosts apply now; the queued drafts (pendingLevelDrafts) open
    # once the player is back in normal play, after the post-boss legendary draft.
    bankRunLevelUps(game)
    # KernelExploit: boss defeat grants +20% permanent damage
    if hasPowerUp(game.player, puKernelExploit):
      game.player.damage *= 1.20'f32
      spawnExplosionPooled(game.particlePool, game.player.pos.x, game.player.pos.y,
                           Color(r: 180, g: 80, b: 255, a: 255), 40)
      addShake(game.dopamine.screenShake, siMedium, Color(r: 180, g: 80, b: 255, a: 255))
    let prevShards = game.rogueliteRun.shardsEarned
    let prevCores  = game.rogueliteRun.coresEarned
    let survivalWasUnlocked = not globalSettings.isNil and globalSettings.survivalUnlocked
    markBossRoomCleared(game)
    completeRogueliteBoss(game)
    saveRunState(game)  # Checkpoint next floor, or delete the save on a win.
    deleteSuspendSnapshot()  # Boundary: the pre-exit snapshot is stale.
    if not survivalWasUnlocked and not globalSettings.isNil and globalSettings.survivalUnlocked:
      game.pendingToasts.add(t(tkGameModeUnlocked) & " " & t(tkSurvivalUnlockedNotif))
    let shardDelta = game.rogueliteRun.shardsEarned - prevShards
    let coreDelta  = game.rogueliteRun.coresEarned  - prevCores
    if shardDelta > 0:
      showCurrency(game, game.player.pos + newVector2f(0, -40), shardDelta, cikDataShards)
    if coreDelta > 0:
      showCurrency(game, game.player.pos + newVector2f(28, -26), coreDelta, cikCores)
    game.powerUpChoices = generatePowerUpChoices(game.player, true, unlockedFamilySet(game.rogueliteProfile), game.mode)
    game.selectedPowerUp = 0
    initPowerUpRollAnimation(game)
    initializeRerollCost(game)
    # Clear all enemies and bullets for clean screen
    game.enemies = @[]
    game.bullets = @[]
    # Final floor cleared: show the ending screen first. The queued draft above is
    # held in reserve and only consumed if the player chooses to loop deeper.
    if game.rogueliteRun.awaitingVictoryScreen:
      game.selectedVictoryButton = 0
      # First final-floor clear plays the one-time "Deep Recovery" outro, which
      # hands off to the roguelite victory screen when it ends. Already-seen runs
      # drop straight onto the victory screen.
      if not globalSettings.isNil and not globalSettings.hasSeenRogueliteEnding:
        game.state = gsRogueliteEndCinematic
      else:
        game.state = gsRogueliteVictory
    else:
      game.state = gsPowerUpSelect

  # If boss was defeated in TIME SURVIVAL mode, trigger power-up selection
  # In WAVE mode, power-ups are only given between waves, not on boss defeat.
  # Sandbox is excluded: its bosses are spawned freely as a testing tool, so
  # killing one must not pop a power-up draft (or any reward flow).
  if bossDefeated and not shouldUseWaves(game.mode) and game.mode != gmSandbox:
    # Time survival: a defeated boss is a major milestone, so offer a LEGENDARY
    # draft (isLegendary = true) to match the wave-mode boss reward in
    # completeBossWave, not a common upgrade.
    game.powerUpChoices = generatePowerUpChoices(game.player, true, mode = game.mode)
    game.selectedPowerUp = 0
    initPowerUpRollAnimation(game)
    game.state = gsPowerUpSelect
    # Clear all enemies and bullets for clean screen
    game.enemies = @[]
    game.bullets = @[]

proc cheatCompleteRogueliteFloor*(game: var Game) =
  ## Cheat-menu "Skip Floor": replicate the floor-boss-defeated path (see the
  ## bossDefeated/gmRoguelite block above) so the run banks rewards, advances the
  ## floor, and routes into the post-boss draft -> floor-select flow. Routed
  ## through a request flag (cheatRogueliteSkipFloor) consumed by main.nim so the
  ## cheat module never has to import game.nim.
  if game.mode != gmRoguelite or game.rogueliteRun.isNil:
    return
  markBossRoomCleared(game)
  completeRogueliteBoss(game)
  saveRunState(game)  # Checkpoint next floor, or delete the save on a win.
  deleteSuspendSnapshot()  # Boundary: the pre-exit snapshot is stale.
  game.powerUpChoices = generatePowerUpChoices(game.player, true,
                          unlockedFamilySet(game.rogueliteProfile), game.mode)
  game.selectedPowerUp = 0
  initPowerUpRollAnimation(game)
  initializeRerollCost(game)
  game.enemies = @[]
  game.bullets = @[]
  if game.rogueliteRun.awaitingVictoryScreen:
    game.selectedVictoryButton = 0
    if not globalSettings.isNil and not globalSettings.hasSeenRogueliteEnding:
      game.state = gsRogueliteEndCinematic
    else:
      game.state = gsRogueliteVictory
  else:
    # Unlike the real boss-defeat path, the cheat can fire from any room, so the
    # boss-room exit portal would be unreachable. Request that the draft route
    # straight into floor select instead (consumed in main.nim continueAfterDraft).
    game.cheatRogueliteDirectFloorSelect = true
    game.state = gsPowerUpSelect

proc updateBossSatellites(game: var Game, dt: float32, effectiveDt: float32) =
  # Update boss satellites (persistent orbiting satellites)
  # Screen dims are frame-constant, so the laser's max reach is computed once here
  # rather than per satellite per frame.
  let maxScreenDist = sqrt(game.screenWidth.float32 * game.screenWidth.float32 +
                           game.screenHeight.float32 * game.screenHeight.float32)
  for enemy in game.enemies:
    if enemy.isBoss and enemy.satellites.len > 0:
      var i = enemy.satellites.len - 1
      while i >= 0:
        # Update orbit position using individual satellite rotation speed
        enemy.satellites[i].angle += dt * enemy.satellites[i].rotationSpeed
        enemy.satellites[i].pos.x = enemy.pos.x + cos(enemy.satellites[i].angle) * enemy.satellites[i].radius
        enemy.satellites[i].pos.y = enemy.pos.y + sin(enemy.satellites[i].angle) * enemy.satellites[i].radius

        # LASER TARGETING SYSTEM - Continuous lasers with player coordinate tracking
        enemy.satellites[i].shootTimer -= dt

        # Update laser charge/target system
        if enemy.satellites[i].shootTimer <= 0:
          if not enemy.satellites[i].laserActive:
            # Start charging laser - lock onto current player position
            enemy.satellites[i].laserActive = true
            enemy.satellites[i].laserTarget = game.player.pos
            enemy.satellites[i].laserChargeTime = 0.0
            enemy.satellites[i].shootTimer = 4.5 + rand(1.0)  # Time until next laser cycle
          else:
            # Laser cycle complete, deactivate and prepare for next shot
            enemy.satellites[i].laserActive = false

        # Laser active - warning phase then fire
        if enemy.satellites[i].laserActive:
          enemy.satellites[i].laserChargeTime += dt

          # OPTIMIZATION: Only calculate laser geometry every 3 frames during warning
          let shouldUpdateLaser = (game.frameCount mod 3 == 0) or (enemy.satellites[i].laserChargeTime >= 1.5)

          if shouldUpdateLaser:
            # Calculate direction through locked target position to screen edge
            let toTarget = (enemy.satellites[i].laserTarget - enemy.satellites[i].pos).normalize()
            let targetAngle = arctan2(toTarget.y, toTarget.x)

            # WARNING PHASE (first 1.5 seconds)
            if enemy.satellites[i].laserChargeTime < 1.5:
              # Update existing warning position to follow satellite, or create new one
              var warningFound = false
              for warning in game.attackWarnings:
                if warning.attackType == awtSatelliteLaser and
                   warning.sourceEnemyId == enemy.id and
                   warning.fromSatellite:
                  # Update warning position to follow satellite
                  warning.pos = enemy.satellites[i].pos
                  warningFound = true
                  break

              # Create new warning if doesn't exist
              if not warningFound:
                game.attackWarnings.add(newSatelliteLaserWarning(
                  enemy.satellites[i].pos.x,
                  enemy.satellites[i].pos.y,
                  enemy.satellites[i].laserTarget.x,
                  enemy.satellites[i].laserTarget.y,
                  1.5 - enemy.satellites[i].laserChargeTime,
                  enemy.id
                ))

            # FIRING PHASE (after warning)
            else:
              # OPTIMIZATION: Only create laser every 2 frames instead of every frame
              # Lasers last 2 frames so this maintains continuous beam appearance
              if game.frameCount mod 2 == 0:
                game.lasers.add(newLaser(
                  enemy.satellites[i].pos.x,
                  enemy.satellites[i].pos.y,
                  3,                    # direction: 3 = single rotated beam
                  maxScreenDist,        # length: extend all the way across screen
                  12.0,                 # thickness: visible laser beam
                  2,                    # damage
                  dt * 3.0,             # duration: 3 frames worth for smooth overlap
                  targetAngle,          # rotation: angle through target point
                  enemy.enemyType       # enemyType: track source
                ))

              # Visual feedback for laser firing - reduced frequency
              if game.frameCount mod 8 == 0:  # Reduced from every 2 frames to every 8
                spawnExplosionPooled(game.particlePool, enemy.satellites[i].pos.x, enemy.satellites[i].pos.y,
                              Color(r: 255, g: 200, b: 100, a: 255), 6)

        # Off-screen satellites skip the bullet-collision scan entirely.
        var satelliteDestroyed = false
        let onScreen = enemy.satellites[i].pos.x > -50 and enemy.satellites[i].pos.x < game.screenWidth.float32 + 50 and
                       enemy.satellites[i].pos.y > -50 and enemy.satellites[i].pos.y < game.screenHeight.float32 + 50

        if onScreen:
          for bullet in game.bullets:
            if bullet.fromPlayer:
              # Quick AABB check before distance calculation
              let dx = abs(bullet.pos.x - enemy.satellites[i].pos.x)
              let dy = abs(bullet.pos.y - enemy.satellites[i].pos.y)
              if dx < 25.0 and dy < 25.0:
                if dx * dx + dy * dy < 484.0:  # 22.0^2
                  enemy.satellites[i].hp -= 1
                  spawnExplosionPooled(game.particlePool, enemy.satellites[i].pos.x, enemy.satellites[i].pos.y,
                                Color(r: 255, g: 150, b: 0, a: 255), 6)
                  if enemy.satellites[i].hp <= 0:
                    # Satellite destroyed!
                    spawnExplosionPooled(game.particlePool, enemy.satellites[i].pos.x, enemy.satellites[i].pos.y,
                                  Red, 20)
                    playSound(stEnemyDeath, 0.4)
                    let satelliteBonusDamage = registerBossSatelliteDestroyed(enemy)
                    if satelliteBonusDamage > 0:
                      let dealtSatelliteDamage = applyEnemyHpDamage(enemy, satelliteBonusDamage)
                      if dealtSatelliteDamage > 0:
                        showDamage(game, enemy.pos, dealtSatelliteDamage, true, false, dtArcane)
                    enemy.satellites.delete(i)
                    # Last satellite down: a snipe reticle already telegraphing
                    # has lost its firing platform (the shot will be skipped),
                    # so retire it instead of leaving an orphan warning.
                    if enemy.satellites.len == 0:
                      for w in countdown(game.attackWarnings.high, 0):
                        if game.attackWarnings[w].attackType == awtLaserPointer and
                           game.attackWarnings[w].sourceEnemyId == enemy.id:
                          game.attackWarnings.delete(w)
                    satelliteDestroyed = true
                    break

        if not satelliteDestroyed:
          i -= 1
        else:
          # Already deleted, continue
          i -= 1

proc updateBulletsAndHits(game: var Game, dt: float32, effectiveDt: float32) =
  # Rebuild the spatial grid now that all enemy movement for this frame is done.
  # The bullet loop below queries it instead of scanning every enemy per bullet.
  # game.enemies is never added-to or deleted-from inside the bullet loop (enemy
  # removal happens earlier, in the enemy-update loop), so these indices stay
  # valid for the whole loop, and enemy positions only drift by knockback (a
  # couple of pixels) -- far less than a cell -- so the buckets stay accurate.
  rebuildEnemyGrid(game)

  # Update bullets
  var i = 0
  while i < game.bullets.len:
    let bullet = game.bullets[i]

    # Homing bullet logic
    if bullet.isHoming:
      if bullet.fromPlayer and game.enemies.len > 0:
        # Player homing bullets track enemies (LEGENDARY - Single Level)
        # Deliberately weak homing: short range and a low turn rate.
        let trackingRange = 120.0

        # Find nearest enemy that HASN'T been hit by this bullet yet.
        # Spatial-grid query: only enemies whose cell is within trackingRange can
        # qualify, so we test a handful instead of every enemy. The query radius
        # equals the (centre-to-centre) trackingRange, a non-lossy superset, so the
        # nearest qualifying enemy is exactly the one the old full scan would pick.
        var nearestEnemy: Enemy = nil
        var nearestDist = 999999.0

        for enemyIdx in enemyGrid.nearby(bullet.pos, trackingRange.float32):
          let enemy = game.enemies[enemyIdx]
          let dist = distance(bullet.pos, enemy.pos)

          # Only track if within range AND not already hit by this bullet (using enemy ID)
          if dist < trackingRange and dist < nearestDist and enemy.id notin bullet.hitEnemies:
            nearestDist = dist
            nearestEnemy = enemy

        if nearestEnemy != nil:
          let turnRate = 0.02

          let toEnemy = (nearestEnemy.pos - bullet.pos).normalize()
          let currentDir = bullet.vel.normalize()
          let newDir = (currentDir * (1.0 - turnRate) + toEnemy * turnRate).normalize()
          bullet.vel = newDir * bullet.vel.length()

      elif not bullet.fromPlayer:
        # Enemy homing bullets track the player (etMage magic bullets)
        let trackingRange = 400.0  # Longer range for enemy homing
        let dist = distance(bullet.pos, game.player.pos)

        if dist < trackingRange:
          # Gentle tracking strength for enemy bullets - dodgeable.
          # Boss homing bullets (Summoner King's Royal Sigils) curve a touch harder
          # than regular mage bullets, but still stay dodgeable.
          let turnRate = if bullet.isBossBullet: 0.013'f32 else: 0.009'f32

          let toPlayer = (game.player.pos - bullet.pos).normalize()
          let currentDir = bullet.vel.normalize()
          let newDir = (currentDir * (1.0 - turnRate) + toPlayer * turnRate).normalize()
          bullet.vel = newDir * bullet.vel.length()

    # Use effectiveDt for enemy bullets (slowed by Time Warp), normal dt for player bullets
    let bulletDt = if bullet.fromPlayer: dt else: effectiveDt

    # Nova: frozen player bullets don't move or expire
    if bullet.isFrozenByNova and bullet.fromPlayer:
      i += 1
      continue

    if not updateBullet(bullet, bulletDt) or isOffScreen(bullet, game.screenWidth, game.screenHeight):
      # Track bullet despawn (missed shot) for player bullets only
      if bullet.fromPlayer:
        trackBulletDespawn(game, bullet, false)
      game.bullets.delete(i)
      continue

    if bullet.fromPlayer and bullet.isExplosive and not bullet.isEcho:
      let level = getPowerUpLevel(game.player, puExplosiveBullets)
      # Accumulator-based spawning: no rand() call per frame, deterministic interval
      let spawnInterval = case level
        of 1: 0.20   # 5 spawns/sec
        of 2: 0.13   # ~7.5 spawns/sec
        else: 0.10   # 10 spawns/sec
      let particleCount = case level
        of 1: 2
        of 2: 2
        else: 3
      bullet.particleTrailTimer += bulletDt
      if bullet.particleTrailTimer >= spawnInterval:
        bullet.particleTrailTimer -= spawnInterval
        spawnTrailParticlePooled(game.particlePool, bullet.pos.x, bullet.pos.y,
                                 Color(r: 255, g: 150, b: 50, a: 200), particleCount)

    # Update sourceEnemyPos to track the enemy's current position
    # This ensures parried bullets go to where the enemy last was, not where it shot from
    if not bullet.fromPlayer and bullet.sourceEnemyId >= 0:
      for enemy in game.enemies:
        if enemy.id == bullet.sourceEnemyId:
          bullet.sourceEnemyPos = enemy.pos
          break

    # Echo Shots - spawn ghost trail bullets (LEGENDARY)
    # Capped per parent bullet: echo output otherwise scales with bullet lifetime,
    # so piercing/ricochet (which keep a bullet alive for the whole screen) would
    # trail an unbounded number of 25% echoes. The count is inherited by clones
    # (split fragments) so those can't reset the budget either.
    if bullet.fromPlayer and not bullet.isEcho and bullet.echoSpawnCount < ECHO_MAX_SPAWNS and
        hasPowerUp(game.player, puEchoShots):
      # Ensure parent bullet has an ID for tracking
      if bullet.bulletId == 0:
        assignBulletId(game, bullet)

      bullet.echoTrailTimer += bulletDt

      let spawnInterval = 0.10
      let echoDamageMultiplier = 0.25

      if bullet.echoTrailTimer >= spawnInterval:
        bullet.echoTrailTimer = 0.0

        # Create echo bullet
        createEchoBullet(game, bullet, echoDamageMultiplier, 0.7, 0.45)
        bullet.echoSpawnCount += 1

    # Check rotating shield collision
    if not bullet.fromPlayer and hasPowerUp(game.player, puRotatingShield):
      let level = getPowerUpLevel(game.player, puRotatingShield)
      let shieldCount = 3  # Always 3 shields regardless of level
      let shieldRadius = game.player.radius * 2.5 + 15  # Reduced from +15 to +10
      var hitShield = false
      var hitShieldIndex = -1

      # Level-based coverage
      let arcCoverage = case level
        of 1: 0.30  # 30% coverage
        of 2: 0.35  # 35% coverage
        else: 0.40  # 40% coverage

      # Check collision with shield arcs (with gaps)
      for j in 0..<shieldCount:
        # Skip destroyed shields
        if j < game.player.shieldHealths.len and game.player.shieldHealths[j] <= 0:
          continue

        let baseAngle = game.player.shieldAngle + (j.float32 * PI * 2.0 / shieldCount.float32)
        let fullArcLength = PI * 2.0 / shieldCount.float32
        let activeArcLength = fullArcLength * arcCoverage

        # Center the active arc portion, leaving gaps at the edges
        let gapSize = (fullArcLength - activeArcLength) / 2.0
        let angle1 = baseAngle + gapSize
        let angle2 = angle1 + activeArcLength

        # Check multiple points along the ACTIVE portion of the arc
        for k in 0..12:  # Reduced from 16 to 12 points for thinner coverage
          let t = k.float32 / 12.0
          let angle = angle1 + t * (angle2 - angle1)
          let shieldX = game.player.pos.x + cos(angle) * shieldRadius
          let shieldY = game.player.pos.y + sin(angle) * shieldRadius
          let shieldPos = newVector2f(shieldX, shieldY)

          if distance(bullet.pos, shieldPos) < bullet.radius + 4:  # Reduced from +6 to +4
            hitShield = true
            hitShieldIndex = j
            playSound(stShield, 0.4)
            spawnExplosionPooled(game.particlePool, shieldX, shieldY, Color(r: 0, g: 255, b: 255, a: 255), 8)  # Cyan explosion
            break

        if hitShield:
          break

      if hitShield and hitShieldIndex >= 0:
        # Damage the specific shield
        if hitShieldIndex < game.player.shieldHealths.len:
          game.player.shieldHealths[hitShieldIndex] -= 1.0
          # Reset regen timer for this shield
          if hitShieldIndex < game.player.shieldRegenTimers.len:
            game.player.shieldRegenTimers[hitShieldIndex] = 0.0
        game.bullets.delete(i)
        continue

    # Check bullet-enemy collision
    var hitEnemy = false
    if bullet.fromPlayer:
      # Candidate enemies for this bullet, from the spatial grid: those whose cell
      # is within hit range (bullet.radius + the largest enemy radius on screen),
      # PLUS every boss. Bosses are always included because a boss weak-point target
      # can sit beyond the body radius the grid keys on. After sorting + de-duping,
      # iterating `gridCandidates` is identical to the old `0..<enemies.len` scan
      # *restricted to in-range enemies*, in the same ascending index order -- and
      # that is the same behaviour as the full scan, because the only gate before
      # any state change is the distance test, which every skipped (far) enemy fails.
      gridCandidates.setLen(0)
      if game.enemies.len <= GRID_MIN_ENEMIES:
        # Few enemies on screen: a full scan is already cheap, and skipping the
        # grid query + sort + dedup avoids any per-bullet overhead. The resulting
        # 0..<len index list is inherently sorted and unique -- so this branch is
        # byte-for-byte the original loop.
        for idx in 0 ..< game.enemies.len:
          gridCandidates.add(idx)
      else:
        for cand in enemyGrid.nearby(bullet.pos, bullet.radius + gridMaxEnemyRadius):
          gridCandidates.add(cand)
        for bossIdx in gridBossIndices:
          gridCandidates.add(bossIdx)
        sort(gridCandidates)
        var uniqueLen = 0
        var prevCand = -1
        for k in 0 ..< gridCandidates.len:
          let v = gridCandidates[k]
          if v != prevCand:
            gridCandidates[uniqueLen] = v
            inc uniqueLen
            prevCand = v
        gridCandidates.setLen(uniqueLen)

      # The echo parent is keyed only by bullet.parentBulletId, which does not depend on
      # the candidate enemy, so resolve it once per bullet rather than rescanning
      # game.bullets for every candidate. Bullet is a ref, so the two uses below still
      # see (and can mutate) the live parent. nil = the parent already despawned, which
      # matches the old "no match found" path.
      var echoParent: Bullet = nil
      if bullet.isEcho and bullet.parentBulletId > 0:
        for parentBullet in game.bullets:
          if parentBullet.bulletId == bullet.parentBulletId:
            echoParent = parentBullet
            break

      for j in gridCandidates:
        # Enemy is a ref and the bullet loop never adds or deletes enemies while the
        # grid is live (see the spatial-grid notes in enemy_helpers), so binding the
        # candidate once is free and identical to indexing it 79 times.
        let target = game.enemies[j]
        # Skip if this bullet already hit this enemy (using enemy ID)
        if target.id in bullet.hitEnemies:
          continue
        if echoParent != nil and
           (target.id in echoParent.hitEnemies or
            target.id in echoParent.echoHitEnemies):
          continue

        if target.isBoss:
          let objectiveHit = resolveBossWeakPointTargetHit(target, bullet.pos, bullet.radius)
          if objectiveHit.hit:
            bullet.hitEnemies.add(target.id)
            playSound(stEnemyHit, if objectiveHit.wrongTarget: 0.2 else: 0.35)
            let particleColor = if objectiveHit.wrongTarget:
              Color(r: 120, g: 80, b: 180, a: 255)
            elif objectiveHit.completed:
              Color(r: 255, g: 235, b: 90, a: 255)
            else:
              target.color
            spawnExplosionPooled(game.particlePool, objectiveHit.pos.x, objectiveHit.pos.y,
                                 particleColor, if objectiveHit.completed: 18 else: 8)
            if objectiveHit.completed:
              if objectiveHit.bonusDamage > 0:
                let dealtObjectiveDamage = applyEnemyHpDamage(target, objectiveHit.bonusDamage)
                if dealtObjectiveDamage > 0:
                  showDamage(game, target.pos, dealtObjectiveDamage, true, false, dtArcane)
                  recordDamage(game.dopamine.realTimeStats, dealtObjectiveDamage, game.time)
              addShake(game.dopamine.screenShake, siLarge)
            hitEnemy = true
            break

        # Overload shield: bounce body shots back at the player instead of letting
        # them through. Only the body is shielded - weak-point targets above still
        # register - so the player's path is "stop firing into the shield / dodge".
        if target.isBoss and target.reflectShieldActive and
            target.weakPoint.exposedTimer <= 0 and not bullet.isEcho and
            checkBulletEnemyCollision(bullet, target):
          let dir = (game.player.pos - bullet.pos).normalize()
          # Parried shots rocket back at 150% of their incoming speed (220 floor keeps slow shots dangerous).
          bullet.vel = dir * max(220.0'f32, bullet.vel.length() * 1.5'f32)
          bullet.fromPlayer = false
          bullet.damage = REFLECT_SHIELD_DAMAGE
          bullet.sourceEnemyId = target.id
          bullet.sourceEnemyPos = target.pos
          bullet.isParried = false
          spawnExplosionPooled(game.particlePool, bullet.pos.x, bullet.pos.y,
                               Color(r: 120, g: 200, b: 255, a: 255), 6)
          break  # leave hitEnemy false so the reflected shot survives as an enemy bullet

        if checkBulletEnemyCollision(bullet, target):
          # Mark this enemy as hit by this bullet (using enemy ID, not index)
          bullet.hitEnemies.add(target.id)
          if echoParent != nil and target.id notin echoParent.echoHitEnemies:
            echoParent.echoHitEnemies.add(target.id)

          # Play enemy hit sound
          playSound(stEnemyHit, 0.3)

          # Calculate final damage with Overcharge modifier
          var finalDamage = bullet.damage
          var overchargeExtraDamage = 0.0
          if not bullet.isEcho and hasPowerUp(game.player, puOvercharge):
            # Overcharge: bullets ramp up with distance travelled, capping at 2.5x
            # total damage (reached at 1000 units).
            let damagePerUnit = 0.0015  # 0.15% per unit, 1.5% per 10 units
            let maxBonus = 1.5  # Max +150% damage (2.5x total)
            let bonusMultiplier = min(bullet.travelDistance * damagePerUnit, maxBonus)

            finalDamage = bullet.damage * (1.0 + bonusMultiplier)
            overchargeExtraDamage = finalDamage - bullet.damage

          # Use the bullet's stored crit status (rolled when bullet was created)
          let isCrit = bullet.wasCrit
          let weakCoreHit = bossWeakPointCoreHit(target, bullet.pos, bullet.radius)
          let bossIsInvulnerable =
            target.isBoss and target.invulnerabilityTimer > 0

          if target.enemyType == etStar:
            # Stars use hit counter, show "1" per hit dealt
            target.hitCount += 1
            showDamage(game, target.pos, 0.01, true, false, dtHitCount)
          else:
            # Apply elite modifiers to damage
            var actualDamage = finalDamage

            # Higher defenseMultiplier = MORE defense (takes LESS damage)
            # 0.5 = half defense (takes 2x damage), 1.0 = normal, 2.0 = double defense (takes 0.5x damage)
            if target.isBoss and target.defenseMultiplier > 0:
              actualDamage /= target.defenseMultiplier

            # Mega-cast hardening: the boss is armored while channelling its
            # signature beam, so bursting it down mid-cast is heavily resisted.
            if target.isBoss and target.megaCastTimer > 0:
              actualDamage *= MegaCastDamageTaken

            # Tank elite: 50% damage reduction
            # Handles multiple elite types
            if target.isElite and etTank in target.eliteTypes:
              actualDamage *= 0.5  # 50% damage taken

            # Shielded elite: shield absorbs damage first
            var shieldDamage = 0.0  # Track damage absorbed by shield
            if target.isElite and etShielded in target.eliteTypes and target.shieldHp > 0:
              if target.shieldHp >= actualDamage:
                # Shield absorbs all damage
                shieldDamage = actualDamage
                target.shieldHp -= actualDamage
                actualDamage = 0
              else:
                # Shield breaks, remaining damage goes to HP
                shieldDamage = target.shieldHp
                actualDamage -= target.shieldHp
                target.shieldHp = 0

            # Diamond enemy: 1-hit shield absorbs the first bullet entirely (like Celestial Veil)
            if target.enemyType == etDiamond and target.diamondShieldActive:
              target.diamondShieldActive = false
              shieldDamage += actualDamage
              actualDamage = 0

            let weakDamageSource = if weakCoreHit: bwdsDirectWeakCore else: bwdsDirectBody
            actualDamage *= bossWeakPointDamageMultiplier(target, weakDamageSource)
            # Engagement gates: while adds are alive or the overload shield is up (and
            # no vulnerability window is open), body damage barely leaks through, so
            # the player must resolve the mechanic instead of shooting the body.
            let bossWindowOpen = target.weakPoint.exposedTimer > 0
            if target.isBoss and not bossWindowOpen and
                (target.addsGateActive or target.reflectShieldActive):
              actualDamage *= GATE_DAMAGE_LEAK
            if bossIsInvulnerable:
              actualDamage = 0

            actualDamage = applyEnemyHpDamage(target, actualDamage)
            # Track damage spent inside a vulnerability window for the heal-on-ignore check.
            if target.isBoss and bossWindowOpen:
              target.windowDamageDealt += actualDamage

            # Volatile: enemies with 2+ active DoTs take +50% bullet damage
            var volatileBonusDamage = 0.0
            if game.player.hasVolatile and bullet.fromPlayer and not bullet.isEcho:
              var activeEffectCount = 0
              for et, ae in target.activeEffects:
                if ae.primary.isActive:
                  activeEffectCount += 1
              if activeEffectCount >= 2:
                volatileBonusDamage = actualDamage * 0.5
                volatileBonusDamage = applyEnemyHpDamage(target, volatileBonusDamage)
                trackPowerUpDamage(game, puVolatile, volatileBonusDamage)
                if volatileBonusDamage > 0:
                  showDamage(game, target.pos, volatileBonusDamage, true, false, dtArcane)

            # Resonance: bullets hitting DoT enemies deal bonus damage equal to % of combined DPS
            var resonanceBonusDamage = 0.0
            if game.player.resonanceLevel > 0 and bullet.fromPlayer and
                not bullet.isEcho and not bossIsInvulnerable:
              var totalDoTDps = 0.0
              for et, ae in target.activeEffects:
                if ae.primary.isActive:
                  totalDoTDps += ae.primary.damagePerSec
              if totalDoTDps > 0:
                let resonancePct = case game.player.resonanceLevel
                  of 1: 0.20
                  of 2: 0.30
                  else: 0.40
                resonanceBonusDamage = totalDoTDps * resonancePct
                resonanceBonusDamage *= bossWeakPointDamageMultiplier(target, bwdsPassive)
                resonanceBonusDamage = applyEnemyHpDamage(target, resonanceBonusDamage)
                trackPowerUpDamage(game, puResonance, resonanceBonusDamage)
                if resonanceBonusDamage > 0:
                  showDamage(game, target.pos, resonanceBonusDamage, true, false, dtPoison)

            # Giant Slayer: Deal % of enemy current HP as bonus damage
            var giantSlayerDamage = 0.0
            if not bullet.isEcho and hasPowerUp(game.player, puGiantSlayer) and
                not bossIsInvulnerable:
              let giantSlayerLevel = getPowerUpLevel(game.player, puGiantSlayer)
              var percentDamage = case giantSlayerLevel
                of 1: 0.025  # 2.5% of current HP vs normal enemies
                of 2: 0.04   # 4% of current HP vs normal enemies
                else: 0.06   # 6% of current HP vs normal enemies

              # Giant Slayer hunts the rank-and-file: heavy against normal enemies,
              # but far weaker against bosses.
              if target.isBoss:
                percentDamage *= 0.2  # reduced effect vs bosses

              giantSlayerDamage = target.hp * percentDamage

              # Apply elite modifiers to Giant Slayer damage too
              if target.isBoss and target.defenseMultiplier > 0:
                giantSlayerDamage /= target.defenseMultiplier

              # Tank elite: 50% damage reduction
              if target.isElite and etTank in target.eliteTypes:
                giantSlayerDamage *= 0.5  # 50% damage taken

              giantSlayerDamage *= bossWeakPointDamageMultiplier(target, bwdsPassive)

              # Shielded elite: Giant Slayer damage goes through shield to HP
              giantSlayerDamage = applyEnemyHpDamage(target, giantSlayerDamage)

              # Track Giant Slayer damage contribution
              trackPowerUpDamage(game, puGiantSlayer, giantSlayerDamage)

              # Show Giant Slayer damage number in distinct color (purple/arcane)
              if giantSlayerDamage > 0:
                showDamage(game, target.pos, giantSlayerDamage, true, false, dtArcane)

            # Curse: cursed enemies take a % of this hit's damage as bonus damage.
            # Based on actualDamage, which already includes mitigation and the direct
            # weak-point multiplier, so no extra multipliers are applied here.
            # Greatly reduced against bosses.
            var curseDamage = 0.0
            if not bullet.isEcho and bullet.fromPlayer and target.cursed and
                hasPowerUp(game.player, puCurse) and not bossIsInvulnerable and actualDamage > 0:
              var curseBonusPct = case getPowerUpLevel(game.player, puCurse)
                of 1: 0.30'f32
                of 2: 0.45'f32
                else: 0.60'f32
              if target.isBoss:
                curseBonusPct *= 0.15  # greatly reduced against bosses
              curseDamage = actualDamage * curseBonusPct
              curseDamage = applyEnemyHpDamage(target, curseDamage)
              trackPowerUpDamage(game, puCurse, curseDamage)
              if curseDamage > 0:
                showDamage(game, target.pos, curseDamage, true, false, dtArcane)

            # GlitchField: chance to scramble enemy navigation (slow them)
            if game.player.glitchChance > 0 and not target.isBoss and actualDamage > 0:
              if rand(1.0) < game.player.glitchChance:
                target.slowTimer  = 0.5'f32
                target.slowAmount = 0.15'f32  # move at 15% speed

            # Track bullet hit for statistics (now includes Giant Slayer + Curse damage)
            trackBulletHit(game, bullet, target, actualDamage + shieldDamage + giantSlayerDamage + curseDamage)

            # Track damage for real-time DPS display
            recordDamage(game.dopamine.realTimeStats, actualDamage + shieldDamage + giantSlayerDamage + curseDamage, game.time)

            # Track power-up damage contributions (only ACTUAL extra damage they caused)

            # Track Overcharge damage contribution (only extra damage from distance)
            if overchargeExtraDamage > 0:
              trackPowerUpDamage(game, puOvercharge, overchargeExtraDamage)

            # Track Rage damage contribution, use multiplier baked in at fire time
            if bullet.rageMultiplier > 1.0:
              let rageBonusDamage = actualDamage * (1.0 - 1.0 / bullet.rageMultiplier)
              trackPowerUpDamage(game, puRage, rageBonusDamage)

            # Track Multi-Shot contribution (only from bonus bullets)
            if bullet.isBonusFromMultiShot:
              trackPowerUpDamage(game, puMultiShot, actualDamage)

            # Track Double Shot contribution (only from bonus bullets)
            if bullet.isBonusFromDoubleShot:
              trackPowerUpDamage(game, puDoubleShot, actualDamage)

            # Track Special Rounds contribution (bonus damage from every Nth bullet)
            if bullet.isSpecialRound:
              # Special rounds deal +75%, so the bonus share is 0.75 / 1.75 of the final damage.
              let specialRoundsBonusDamage = actualDamage * (0.75 / 1.75)
              trackPowerUpDamage(game, puSpecialRounds, specialRoundsBonusDamage)

            # Track Wall Turrets contribution (all damage from turret-fired bullets)
            if bullet.isFromWallTurret:
              trackPowerUpDamage(game, puWallTurrets, actualDamage)

            # Track Radial Burst contribution (all damage from Radial Burst bullets)
            if bullet.isFromRadialBurst:
              trackPowerUpDamage(game, puRadialBurst, actualDamage)

            # Track Critical Hit contribution (bonus damage from crits)
            if bullet.wasCrit and hasPowerUp(game.player, puCriticalHit):
              # Crit multiplier is 2x, so bonus is exactly half the post-crit damage
              let critBonusDamage = actualDamage * 0.5
              trackPowerUpDamage(game, puCriticalHit, critBonusDamage)

            # Track Arcane Bullets contribution (all arcane bullet damage)
            if bullet.isArcaneBullet:
              trackPowerUpDamage(game, puArcaneBullets, actualDamage)

            # Track only the damage wind actually added. Wind push itself is
            # utility, and windPushForce can also include Heavy Rounds knockback.
            if bullet.windPushForce > 0 and hasPowerUp(game.player, puWindBullets):
              # Share of the final hit that one point of pre-crit damage is worth
              let dmgShare = if finalDamage > 0: actualDamage / finalDamage else: 0.0'f32
              let windFlatDamage = WindBulletFlatDamageBonus * dmgShare
              if windFlatDamage > 0:
                trackPowerUpDamage(game, puWindBullets, windFlatDamage)
              if game.player.hasWindMastery:
                # Mastery owns only the extra flat damage it added on top
                let windMasteryDamage =
                  (windBulletFlatBonus(game.player) - WindBulletFlatDamageBonus) * dmgShare
                if windMasteryDamage > 0:
                  trackPowerUpDamage(game, puWindMastery, windMasteryDamage)

            # Piercing Shots: extra hits are enabled by this power-up, but the damage
            # is already captured by the base bullet damage tracking above.
            # Attributing full actualDamage per pierce hit would inflate it to #1 source.
            # The power-up's value is visible in the higher total kill/damage numbers.

            # Track Echo Shots contribution (all echo bullet damage)
            if bullet.isEcho:
              trackPowerUpDamage(game, puEchoShots, actualDamage)

            # Track Bullet Split contribution (all split bullet damage)
            if bullet.isFromBulletSplit:
              trackPowerUpDamage(game, puBulletSplit, actualDamage)

            # Track Bullet Ricochet contribution (all ricochet bullet damage)
            if bullet.isRicochet:
              trackPowerUpDamage(game, puBulletRicochet, actualDamage)

            # Track Parry contribution (all parried bullet damage)
            if bullet.isParried:
              trackPowerUpDamage(game, puParry, actualDamage)

            # Track Nova contribution (all damage from nova-released bullets)
            if bullet.isFromNova:
              trackPowerUpDamage(game, puNova, actualDamage)

            # Create damage number for shield damage (blue colored for shields)
            if shieldDamage > 0:
              showDamage(game, target.pos, shieldDamage, true, isCrit, dtLaser)

            # Create damage number for HP damage (player damage to enemy) - only if damage was dealt
            if actualDamage > 0:
              let bulletDmgType = getBulletDamageType(bullet)
              showDamage(game, target.pos, actualDamage, true, isCrit, bulletDmgType)
          hitEnemy = true

          # Drop the whole echo trail when the main bullet hits, so the trail
          # can't stack damage on one target.
          if not bullet.isEcho and bullet.bulletId > 0:
            for k in countdown(game.bullets.high, 0):
              if game.bullets[k].isEcho and game.bullets[k].parentBulletId == bullet.bulletId:
                game.bullets.delete(k)

          # Heavy Rounds knockback effect
          if not bullet.isEcho and hasPowerUp(game.player, puHeavyRounds):
            let heavyLevel = getPowerUpLevel(game.player, puHeavyRounds)
            let knockbackForce = case heavyLevel
              of 1: 50.0   # Slight knockback
              of 2: 100.0  # Increased knockback
              else: 150.0  # Strong knockback

            # Calculate knockback direction (away from bullet trajectory)
            let pushDir = bullet.vel.normalize()
            let bossResistance = if target.isBoss: 0.2 else: 1.0

            # Apply knockback to enemy
            target.pos.x += pushDir.x * knockbackForce * 0.016 * bossResistance
            target.pos.y += pushDir.y * knockbackForce * 0.016 * bossResistance

            # Clamp to screen boundaries - enemies can't be pushed through borders
            target.pos.x = clamp(target.pos.x, target.radius, game.screenWidth.float32 - target.radius)
            target.pos.y = clamp(target.pos.y, target.radius, game.screenHeight.float32 - target.radius)

          # Special Rounds stun effect
          if not bullet.isEcho and bullet.isSpecialRound:
            # Apply brief stun (80% slow for 0.5 seconds)
            let stunDuration = 0.5
            let baseStunAmount = 0.8  # 80% slow
            let stunAmount = baseStunAmount * (1.0 - target.debuffResistance)
            target.slowTimer = stunDuration
            target.slowAmount = max(target.slowAmount, stunAmount)

            # Visual feedback - extra particles in gold color
            spawnExplosionPooled(game.particlePool, bullet.pos.x, bullet.pos.y,
                          Color(r: 255, g: 215, b: 0, a: 255), 15)

          # UNIFIED BULLET EFFECT SYSTEM
          applyBulletEffects(game, bullet, target, dt)

          # Impact particles + hit flash
          spawnExplosionPooled(game.particlePool, bullet.pos.x, bullet.pos.y,
                        target.color, 10)
          spawnShockwavePooled(game.particlePool, bullet.pos.x, bullet.pos.y,
                        target.radius * 0.6)
          target.hitFlashTimer = 0.10'f32

          # Explosive bullets create area damage
          if not bullet.isEcho and bullet.isExplosive:
            playSound(stExplosion, 0.5)
            let level = getPowerUpLevel(game.player, puExplosiveBullets)
            let explosionRadius = getExplosionRadius(level)

            # Damage all enemies in radius
            for k in 0..<game.enemies.len:
              let dist = distance(bullet.pos, game.enemies[k].pos)
              if dist < explosionRadius:
                let explosionDmg = finalDamage * 0.5
                let actualDamage = damageEnemy(game.enemies[k], explosionDmg)

                # Track explosive bullet damage contribution
                if actualDamage > 0:
                  trackPowerUpDamage(game, puExplosiveBullets, actualDamage)

                # Create damage number for explosive bullet area damage
                if actualDamage > 0:
                  showDamage(game, game.enemies[k].pos, actualDamage, true, isCrit, dtExplosion)

            # Level-based visual scaling similar to satellites
            case level
            of 1:
              # Basic explosion - single nova burst
              spawnNovaExplosionPooled(game.particlePool, bullet.pos.x, bullet.pos.y,
                                       explosionRadius, Orange, Yellow)
              spawnShockwavePooled(game.particlePool, bullet.pos.x, bullet.pos.y, explosionRadius)
            of 2:
              spawnNovaExplosionPooled(game.particlePool, bullet.pos.x, bullet.pos.y,
                                       explosionRadius, Orange, Yellow)
              spawnExplosiveRingPooled(game.particlePool, bullet.pos.x, bullet.pos.y,
                                       explosionRadius, 2, Color(r: 255, g: 180, b: 0, a: 255))
              spawnShockwavePooled(game.particlePool, bullet.pos.x, bullet.pos.y, explosionRadius)
            of 3:
              # Maximum explosion - nova + rings + spiral (satellite-like complexity)
              spawnNovaExplosionPooled(game.particlePool, bullet.pos.x, bullet.pos.y,
                                       explosionRadius, Orange, Yellow)
              spawnExplosiveRingPooled(game.particlePool, bullet.pos.x, bullet.pos.y,
                                       explosionRadius, 2, Color(r: 255, g: 180, b: 0, a: 255))
              spawnSpiralExplosionPooled(game.particlePool, bullet.pos.x, bullet.pos.y,
                                         explosionRadius, 3, Color(r: 255, g: 100, b: 0, a: 255))
              spawnShockwavePooled(game.particlePool, bullet.pos.x, bullet.pos.y, explosionRadius)
            else:
              # Fallback to basic
              spawnExplosionPooled(game.particlePool, bullet.pos.x, bullet.pos.y, Orange, 35)
              spawnExplosionPooled(game.particlePool, bullet.pos.x, bullet.pos.y, Yellow, 20)
              spawnShockwavePooled(game.particlePool, bullet.pos.x, bullet.pos.y, explosionRadius)

          # Bullet ricochet off enemies - SYNERGY: Works with piercing, split, and can trigger split on each hit
          var didRicochet = false
          if not bullet.isEcho and bullet.bounceCount >= 0:
            let ricochetLevel = getPowerUpLevel(game.player, puBulletRicochet)
            let maxRicochets = ricochetLevel  # 1, 2, or 3 ricochets

            if bullet.bounceCount < maxRicochets:
              # Ricochet toward the NEAREST enemy that hasn't been hit yet
              var ricochetTarget: Enemy = nil
              var targetIndex = -1
              var nearestDist = 999999.0

              for k in 0..<game.enemies.len:
                # Skip current enemy and already-hit enemies (using enemy ID)
                if k != j and game.enemies[k].id notin bullet.hitEnemies:
                  let dist = distance(bullet.pos, game.enemies[k].pos)
                  if dist < nearestDist:
                    nearestDist = dist
                    ricochetTarget = game.enemies[k]
                    targetIndex = k

              if ricochetTarget != nil:
                let ricochetDir = (ricochetTarget.pos - bullet.pos).normalize()
                bullet.vel = ricochetDir * bullet.vel.length()
                bullet.bounceCount += 1
                bullet.isRicochet = true  # Mark for statistics tracking

                # Reduce damage by 50% per ricochet
                bullet.damage = bullet.damage * 0.50

                hitEnemy = false  # Don't delete bullet
                didRicochet = true
                spawnExplosionPooled(game.particlePool, bullet.pos.x, bullet.pos.y, Yellow, 8)

          # Piercing happens after available ricochets are spent or no ricochet target exists.
          if not didRicochet:
            if bullet.isPiercing:
              let level = getPowerUpLevel(game.player, puPiercingShots)
              bullet.piercedEnemies += 1
              bullet.damage *= 0.67  # Reduce damage by 33% per pierce
              # Level 1 = pierce 1 (hit 2 total), Level 2 = pierce 2 (hit 3 total), etc.
              if bullet.piercedEnemies > level:
                hitEnemy = true  # Delete bullet after hitting level+1 enemies
              else:
                hitEnemy = false  # Don't delete bullet yet, continue piercing
            elif bullet.bounceCount >= 0:
              hitEnemy = true

          # Bullet split on the TERMINAL hit - the bullet divides on its final hit,
          # once all pierces and ricochets are spent, shedding damage-only fragments
          # where it dies. Gated on hitEnemy so a still-flying piercing/ricochet bullet
          # doesn't split mid-path, and on `not bullet.hasSplit` so the fragments
          # (which carry hasSplit=true) can never split again.
          if hitEnemy and not bullet.isEcho and not bullet.hasSplit and
              hasPowerUp(game.player, puBulletSplit):
            let splitLevel = getPowerUpLevel(game.player, puBulletSplit)
            let splitCount = splitLevel + 1  # 2, 3, or 4 fragments
            createSplitBullets(game, bullet, splitCount, 0.5, 0.7)

          if hitEnemy:
            break
    else:
      # Enemy bullet hitting player
      if checkBulletPlayerCollision(bullet, game.player):
        # Parry - bounce bullets back
        if game.player.parryActive:
          # Bounce toward the enemy that shot the bullet
          # If enemy is dead, bounce toward where it was when it shot
          var targetPos: Vector2f
          var foundTarget = false

          # Try to find the living enemy that shot this bullet by ID
          if bullet.sourceEnemyId >= 0:
            for enemy in game.enemies:
              if enemy.id == bullet.sourceEnemyId:
                targetPos = enemy.pos
                foundTarget = true
                break

          # If source enemy is dead, use the position where bullet was shot from
          if not foundTarget:
            targetPos = bullet.sourceEnemyPos
            foundTarget = true

          # Calculate bounce direction toward target position
          let bounceDir = if foundTarget:
            (targetPos - bullet.pos).normalize()
          else:
            # Ultimate fallback: bounce away from player (should never happen)
            (bullet.pos - game.player.pos).normalize()

          bullet.vel = bounceDir * bullet.vel.length()
          bullet.fromPlayer = true  # Mark as player bullet so it can damage enemies
          bullet.isParried = true  # Mark for statistics tracking

          # Visual effect for parry bounce
          spawnExplosionPooled(game.particlePool, bullet.pos.x, bullet.pos.y,
                        Color(r: 255, g: 255, b: 200, a: 255), 12)

          # Bullet continues bouncing, don't delete it
          i += 1
          continue

        var bulletDamage = bullet.damage

        # Thorns reflection - damage the originating enemy (the one that shot the bullet)
        if hasPowerUp(game.player, puThorns):
          # Find the enemy that shot this bullet using sourceEnemyId
          var sourceEnemy: Enemy = nil
          for enemy in game.enemies:
            if enemy.id == bullet.sourceEnemyId:
              sourceEnemy = enemy
              break

          if sourceEnemy != nil:
            discard applyThornsReflection(game, game.player, bulletDamage, sourceEnemy, "bullet")

        if takeDamage(game.player, bulletDamage):
          # Resolve the real shooter so a minion's bullet isn't blamed on the boss.
          var bulletKiller: Enemy = nil
          for e in game.enemies:
            if e.id == bullet.sourceEnemyId:
              bulletKiller = e
              break
          beginPlayerDeathSequence(game, dcProjectile, source = bulletKiller,
                                   sourceType = bullet.sourceEnemyType)
        # Pulse Armor knockback (on non-lethal hits) is handled centrally by the
        # trigger block in updateGame (takeDamage sets the -1 trigger flag).

        trackDamageAvoided(game)

        # Track bullet damage for statistics
        var sourceEnemyType = etEnvironment  # sentinel: no attributable source
        if bullet.sourceEnemyId >= 0:
          for enemy in game.enemies:
            if enemy.id == bullet.sourceEnemyId:
              sourceEnemyType = enemy.enemyType
              break
        trackPlayerDamage(game, bulletDamage, sourceEnemyType)

        # Create damage number (enemy to player)
        # Determine bullet damage type based on bullet properties
        var bulletDamageType = dtDefault
        if bullet.isBossBullet:
          bulletDamageType = dtCritical  # Boss bullets use yellow/critical color
        elif bullet.isPentagon:
          bulletDamageType = dtLaser  # Pentagon bullets use purple/laser color

        showDamage(game, game.player.pos, bulletDamage, false, false, bulletDamageType)

        hitEnemy = true
        spawnExplosionPooled(game.particlePool, bullet.pos.x, bullet.pos.y, Red, 8)

    # Check bullet-wall collision (enemy bullets)
    if not bullet.fromPlayer:
      for wall in game.walls:
        if checkBulletWallCollision(bullet, wall):
          hitEnemy = true
          wall.takeDamage(bullet.damage)  # Full bullet damage
          trackWallDamaged(game)
          # Show wall damage number (red to indicate enemy damage to structures)
          showDamage(game, bullet.pos, bullet.damage, fromPlayer = false,
                     isCritical = false, damageType = dtDefault)
          spawnExplosionPooled(game.particlePool, bullet.pos.x, bullet.pos.y, Brown, 4)
          break

    if hitEnemy:
      game.bullets.delete(i)
      continue

    i += 1

proc updateProjectilesAndCleanup(game: var Game, dt: float32, effectiveDt: float32) =
  # Update meteorites (from etMage enemy)
  var i = 0
  while i < game.meteorites.len:
    let meteorite = game.meteorites[i]

    # Update warning timer
    if meteorite.warningTimer > 0:
      meteorite.warningTimer -= dt
    else:
      # Warning finished - meteorite starts falling
      # Calculate velocity toward target
      let direction = (meteorite.targetPos - meteorite.pos).normalize()
      meteorite.vel = direction * 800.0  # Fast falling speed

      # Update position
      meteorite.pos = meteorite.pos + meteorite.vel * dt

      # Check collision with player while falling
      if distance(meteorite.pos, game.player.pos) < meteorite.radius + game.player.radius:
        if takeDamage(game.player, meteorite.damage.float32):
          beginPlayerDeathSequence(game, dcMeteorite, sourceType = etMage)
        trackDamageAvoided(game)

        # Track meteorite damage
        trackPlayerDamage(game, meteorite.damage.float32, etMage)

        # Create damage number
        showDamage(game, game.player.pos, meteorite.damage.float32, false, false, dtExplosion)

        playSound(stPlayerHit, 0.6)

        # Direct hit: scaled blast + shockwave + heavy shake.
        let burst = clamp(int(meteorite.radius * 2.2'f32), 24, 90)
        spawnExplosionPooled(game.particlePool, meteorite.pos.x, meteorite.pos.y, Orange, burst)
        spawnShockwaveRing(game, meteorite.pos, meteorite.radius * 4.0'f32,
                           Color(r: 255, g: 120, b: 0, a: 255))
        addShake(game.dopamine.screenShake, siLarge)

        # Remove meteorite after hitting player
        game.meteorites.delete(i)
        continue

      # Check if meteorite reached target (or went past it)
      let distToTarget = distance(meteorite.pos, meteorite.targetPos)
      if distToTarget < 20.0 or meteorite.pos.y > meteorite.targetPos.y:
        # Meteorite impact at ground - use appropriate color based on damage
        let impactColor = if meteorite.damage.float > 50.0:
          Color(r: 255, g: 50, b: 0, a: 255)   # Dark orange for apocalypse
        elif meteorite.damage.float > 30.0:
          Color(r: 255, g: 100, b: 0, a: 255)  # Orange for massive impact
        else:
          Color(r: 255, g: 150, b: 50, a: 255) # Default peachy orange
        # Impact scales with rock size: bigger rock -> bigger boom, ring, and shake.
        let impactPos = meteorite.targetPos
        let burst = clamp(int(meteorite.radius * 2.2'f32), 24, 90)
        spawnExplosionPooled(game.particlePool, impactPos.x, impactPos.y, impactColor, burst)
        # Hot white-gold core flash layered over the colored debris.
        spawnExplosionPooled(game.particlePool, impactPos.x, impactPos.y,
                             Color(r: 255, g: 230, b: 160, a: 255), burst div 3)
        # Expanding shockwave ring + ground sparks sell the slam.
        spawnShockwaveRing(game, impactPos, meteorite.radius * 4.0'f32, impactColor)
        spawnShockwavePooled(game.particlePool, impactPos.x, impactPos.y, meteorite.radius * 3.0'f32)
        addShake(game.dopamine.screenShake,
                 if meteorite.radius >= 18.0'f32: siLarge else: siMedium)

        # Impact blast: deal splash damage (50% of the center hit, set at spawn)
        # to the player if caught within the explosion radius. Mage meteorites
        # leave splashDamage at 0, so only the boss rocks blast on landing.
        if meteorite.splashDamage > 0:
          let blastR = meteorite.radius * 3.0'f32
          if distance(impactPos, game.player.pos) < blastR + game.player.radius:
            if takeDamage(game.player, meteorite.splashDamage):
              beginPlayerDeathSequence(game, dcMeteorite, sourceType = etMage)
            trackPlayerDamage(game, meteorite.splashDamage, etMage)
            showDamage(game, game.player.pos, meteorite.splashDamage, false, false, dtExplosion)
            playSound(stPlayerHit, 0.5)

        # Remove meteorite after impact
        game.meteorites.delete(i)
        continue

    i += 1

  # Update coins
  if updateGameCoins(game, dt):
    game.completeBossWave()

  # Run-leveling: collect XP orbs every frame. Roguelite banks levels at room
  # clear (see bankRunLevelUps), so here it only OPENS already-queued drafts.
  # Survival has no room clear, so it banks levels continuously every frame and
  # opens the draft the instant the XP bar fills.
  if game.mode == gmRoguelite:
    updateGameXpOrbs(game, dt)
    checkPendingLevelDraft(game)
  elif isTimeSurvivalMode(game.mode):
    updateGameXpOrbs(game, dt)
    bankRunLevelUps(game)
    checkPendingLevelDraft(game)

  # Update consumables
  i = 0
  while i < game.consumables.len:
    if not updateConsumable(game.consumables[i], dt):
      game.consumables.delete(i)
      continue

    # Check if consumable is in player's collection aura (auto-collect)
    if isInPlayerAura(game.consumables[i], game.player):
      # Pull consumable toward player with magnet animation
      moveConsumableToPlayer(game.consumables[i], game.player.pos, dt)

      # Add subtle particle trail for magnet effect
      spawnTimedParticlesPooled(game.particlePool, game.consumables[i].pos.x, game.consumables[i].pos.y,
                         18.0, Purple, 1, dt)

    if checkPlayerCollision(game.consumables[i], game.player):
      playSound(stPowerUp, 0.6)

      # Track consumable pickup for statistics
      trackConsumablePickup(game, game.consumables[i].consumableType)

      case game.consumables[i].consumableType
      of ctHealth:
        # Cornucopia: +40% extra healing on health consumables
        let baseHeal = 0.75'f32 + 0.025'f32 * game.player.maxHp
        let healAmount = if game.player.hasBountiful: baseHeal * 1.4'f32 else: baseHeal
        heal(game.player, healAmount)
        # Track the bonus healing contributed by puHealPower (the multiplied delta)
        if hasPowerUp(game.player, puHealPower):
          let bonusHealing = healAmount * (game.player.healPowerMult - 1.0)
          trackPowerUpHealing(game, puHealPower, bonusHealing)
        # Create heal damage number (green, floating up)
        showDamage(game, game.player.pos, healAmount, true, false, dtHeal)
      of ctCoin:
        # Double coin multiplier applies here; Cornucopia gives 8 coins instead of 5
        let baseCoin = if game.player.hasBountiful: 8 else: 5
        let coinValue = if game.player.doubleCoinTimer > 0: baseCoin * 2 else: baseCoin
        game.player.coins += coinValue
        showCurrency(game, game.consumables[i].pos, coinValue, cikCredits)
      of ctSpeed:
        activateSpeedBoost(game.player)
        if game.player.hasBountiful:
          game.player.speedBoostTimer *= 1.5'f32
        showPerk(game, game.player.pos, "+SPEED", Cyan)
      of ctInvincibility:
        activateInvincibility(game.player)
        if game.player.hasBountiful:
          game.player.invincibilityTimer *= 1.5'f32
        showPerk(game, game.player.pos, "+INVINCIBLE", Magenta)
      of ctFireRate:
        activateFireRateBoost(game.player)
        if game.player.hasBountiful:
          game.player.fireRateBoostTimer *= 1.5'f32
        showPerk(game, game.player.pos, "+FIRE RATE", Orange)
      of ctMagnet:
        activateMagnet(game.player)
        spawnMagnetCoins(game)
        showPerk(game, game.player.pos, "+MAGNET", Purple)
      of ctShieldBoost:
        # Cornucopia: 3 hits (up from 2), 15s duration (up from 10s)
        if game.player.hasBountiful:
          game.player.shieldBoostTimer = 15.0
          game.player.shieldHits = 3
        else:
          game.player.shieldBoostTimer = 10.0
          game.player.shieldHits = 2
        showPerk(game, game.player.pos, "+SHIELD", Color(r: 100, g: 200, b: 255, a: 255))
      of ctDoubleCoin:
        game.player.doubleCoinTimer = if game.player.hasBountiful: 15.0 else: 10.0
        showPerk(game, game.player.pos, "+DOUBLE COIN", Color(r: 255, g: 223, b: 0, a: 255))
      of ctDamageBoost:
        game.player.damageBoostTimer = if game.player.hasBountiful: 15.0 else: 10.0
        showPerk(game, game.player.pos, "+DAMAGE", Color(r: 255, g: 69, b: 0, a: 255))
      of ctLifesteal:
        game.player.lifestealTimer = if game.player.hasBountiful: 22.0 else: 15.0
        showPerk(game, game.player.pos, "+LIFESTEAL", Color(r: 220, g: 20, b: 20, a: 255))

      let particleColor = case game.consumables[i].consumableType
        of ctHealth: Green
        of ctCoin: Gold
        of ctSpeed: Cyan
        of ctInvincibility: Magenta
        of ctFireRate: Orange
        of ctMagnet: Purple
        of ctShieldBoost: Cyan
        of ctDoubleCoin: Color(r: 255, g: 223, b: 0, a: 255)
        of ctDamageBoost: Color(r: 255, g: 69, b: 0, a: 255)
        of ctLifesteal: Color(r: 139, g: 0, b: 0, a: 255)

      spawnExplosionPooled(game.particlePool, game.consumables[i].pos.x, game.consumables[i].pos.y,
                    particleColor, 10)
      game.consumables.delete(i)
      continue

    i += 1

  # Update walls
  i = 0
  while i < game.walls.len:
    if not updateWall(game.walls[i], dt):
      let dead = game.walls[i]
      # Boss-room obstacles re-form: stash a respawn record (off game.walls so it
      # stops colliding while broken) instead of vanishing for good.
      if dead.respawns:
        game.pendingWallRespawns.add(PendingWallRespawn(
          pos: dead.pos, radius: dead.radius, maxHp: dead.maxHp,
          tint: dead.obstacleTint, timer: BossWallRespawnDelay))
      let explosionColor = if dead.permanent: dead.obstacleTint else: Brown
      # Destruction stats track player-built walls only, not dungeon obstacles.
      if not dead.permanent:
        trackWallDestruction(game, dead.maxHp - dead.hp)
      spawnExplosionPooled(game.particlePool, dead.pos.x, dead.pos.y, explosionColor, 20)
      game.walls.delete(i)
      continue

    # Process turret behavior now in wall module
    processWallTurret(game.walls[i], game.enemies, game.bullets, game.player, game.particlePool, dt,
                      game.screenWidth, game.screenHeight)

    i += 1

  # Process pending wall respawns
  processPendingWallRespawns(game.pendingWallRespawns, game.walls, game.enemies, game.player, game.particlePool, dt)

  # Update particles
  updateParticlePool(game.particlePool, dt)

  # Update damage numbers
  i = 0
  while i < game.damageNumbers.len:
    if not updateDamageNumber(game.damageNumbers[i], dt):
      game.damageNumbers.delete(i)
      continue
    i += 1

  i = 0
  while i < game.currencyIndicators.len:
    if not updateCurrencyIndicator(game.currencyIndicators[i], dt):
      game.currencyIndicators.delete(i)
      continue
    i += 1

  i = 0
  while i < game.perkIndicators.len:
    if not updatePerkIndicator(game.perkIndicators[i], dt):
      game.perkIndicators.delete(i)
      continue
    i += 1

  # This catches edge cases where HP reaches 0 but game didn't transition to game over
  if game.player.hp <= 0 and game.state == gsPlaying:
    beginPlayerDeathSequence(game)

proc updateGame*(game: var Game, dt: float32) =
  # Profiling: smoothed wall-clock ms spent here, surfaced in the debug panel so
  # the update-vs-draw split is visible -- i.e. whether the spatial-grid-accelerated
  # simulation loops are a meaningful slice of the frame or draw-calls dominate.
  # `defer` captures every exit, including the early returns below.
  let perfStart = getTime()
  defer: game.perfUpdateMs = game.perfUpdateMs * 0.9'f32 +
                             float32((getTime() - perfStart) * 1000.0) * 0.1'f32
  if game.state == gsDeathSequence:
    updateDeathSequencePlayback(game, dt)
    return

  updateDopamine(game.dopamine, dt)

  let celebrationActive = updateCelebration(game.dopamine.waveCelebration, dt)
  let introActive = updateIntroduction(game.dopamine.bossIntro, dt)

  # If wave celebration is active, pause the game completely and return early
  if celebrationActive:
    return

  # If boss introduction is active, only allow player movement and particles
  if introActive:
    updatePlayer(game.player, dt, game.screenWidth, game.screenHeight, game.walls)

    # Update particles so visual feedback continues
    updateParticlePool(game.particlePool, dt)

    # Update game time
    game.time += dt
    game.frameCount += 1

    return

  # Handle 3D boss state
  if game.state == gs3DBoss:
    if game.game3D != nil:
      var game3D = cast[ptr Game3D](game.game3D)
      updateGame3D(game3D[], dt)

      if not game3D[].active:
        # 3D boss fight ended - return to 2D
        if game3D[].won:
          # Boss defeated - transfer health back
          game.player.hp = game3D[].player.health
          # Clean up and complete boss wave
          game.bossWaveManager.bossDefeated()
          game.bossWaveManager.coinActive = false  # Skip coin for 3D boss
          completeBossWave(game)
          game.state = gsPowerUpSelect
          enableCursor()
        else:
          # Player died in 3D
          beginPlayerDeathSequence(game, dcBossContact)
          enableCursor()
        # Clean up 3D game
        dealloc(game.game3D)
        game.game3D = nil
    return

  # Handle transition to 3D mode
  if game.transitioning:
    game.fadeAlpha += dt * 2.0
    if game.fadeAlpha >= 1.0:
      game.fadeAlpha = 1.0
      game.transitioning = false

      # Initialize and switch to 3D mode
      var game3D = create(Game3D)
      game3D[] = initGame3D(7, game.player)
      game.game3D = cast[pointer](game3D)
      game.state = gs3DBoss
      disableCursor()  # For mouse look
    return

  # Dungeon crawler layer: room transitions, doors, pedestals, shop terminal.
  # While a room transition is active the whole simulation pauses (fade frame).
  if game.mode == gmRoguelite and game.state == gsPlaying:
    if updateDungeon(game, dt):
      game.time += dt
      game.frameCount += 1
      return

  # Update real-time stats power level
  calculatePowerLevel(game.dopamine.realTimeStats, game.player)

  # Time Warp effect - apply slow to delta time for enemies/bullets
  var effectiveDt = dt
  if game.player.timeWarpActive:
    let slowFactor = 0.5  # 50% slow = 50% speed (single level)
    effectiveDt = dt * slowFactor

  # Handle boss spawn warning timer (non-blocking)
  if game.bossSpawnTimer > 0:
    game.bossSpawnTimer -= dt

  # Handle pending boss spawn (scheduled after a short warning)
  if game.pendingBossTimer > 0:
    game.pendingBossTimer -= dt
    if game.pendingBossTimer <= 0 and game.pendingBoss != nil:
      # Add the pending boss to the world now
      game.enemies.add(game.pendingBoss)
      game.pendingBoss = nil
      # Block normal spawns briefly while the boss arrival settles
      game.bossSpawnTimer = 1.5
      playSound(stBossSpawn)

      let boss = game.enemies[^1]
      let bossDef = getBossDefinition(boss.bossDefinitionID)
      let introBossHp = if boss.bossTotalMaxHp > 0.0'f32: boss.bossTotalMaxHp else: boss.maxHp
      startIntroduction(game.dopamine.bossIntro, bossDef.name, bossDef.description, introBossHp)

      for i in 0..<60:
        let angle = i.float32 * 0.1
        let dist = i.float32 * 3
        let x = boss.pos.x + cos(angle) * dist
        let y = boss.pos.y + sin(angle) * dist
        spawnExplosionPooled(game.particlePool, x, y, boss.color, 3)

  # Always update game time (player time not affected)
  game.time += dt

  # OPTIMIZATION: Track frame count for satellite optimizations
  game.frameCount += 1

  # Track movement and update run duration for statistics
  trackMovementFrame(game, dt)

  game.spawnTimer += dt

  # Survival progression clock + next-boss countdown. Both PAUSE whenever a boss
  # (or its uncollected reward coin) is present, so the player can fight the boss
  # without the world escalating around them or the next boss creeping closer.
  # Difficulty derives from survivalTime below, so it freezes for the fight too.
  # Ticked before the difficulty block so difficulty reflects the same frame.
  if isTimeSurvivalMode(game.mode) and game.state == gsPlaying and
     not game.bossWaveManager.isBossActive() and
     not game.bossWaveManager.isBossCoinActive():
    game.survivalTime += dt
    game.bossTimer = max(0.0, game.bossTimer - dt)

  # Difficulty scaling (not in sandbox mode)
  if not isSandboxMode(game.mode):
    let modeDef = getGameModeDefinition(game.mode)
    # In wave-based mode, difficulty scales with wave number, not time
    if game.mode == gmWaveBased or game.mode == gmRoguelite:
      game.difficulty = (game.currentWave.float32 / 5.0) * modeDef.difficultyScale
      if game.mode == gmRoguelite and game.rogueliteRun != nil and
         game.rogueliteRun.floor != nil:
        let room = currentDungeonRoom(game.rogueliteRun)
        if room != nil:
          game.difficulty = dungeonEnemyDifficulty(game.rogueliteRun, room) *
                            modeDef.difficultyScale
    else:
      # In other modes, difficulty scales with time. Survival uses a gentle ramp
      # (SurvivalDifficultyRamp s per +1 difficulty) so the early game is survivable
      # to the first boss while the XP/level drafts build the player up; e.g. the
      # 90s first boss sits at ~difficulty 2 (~wave-10 tier) instead of the old 6.
      game.difficulty = (game.survivalTime / SurvivalDifficultyRamp) * modeDef.difficultyScale

  updateAttackWarningsAndLasers(game, dt, effectiveDt)
  updatePlayerAndAuras(game, dt, effectiveDt)
  updateEnemySpawning(game, dt, effectiveDt)
  updateEnemiesAndBossAttacks(game, dt, effectiveDt)
  updateBossSatellites(game, dt, effectiveDt)
  updateBulletsAndHits(game, dt, effectiveDt)
  updateProjectilesAndCleanup(game, dt, effectiveDt)

# Draw
proc drawBossPhaseHud(game: Game, enemy: Enemy, topY: int32 = 10,
                      alignRight: bool = false, slotH: int32 = 0): int32 =
  let bossDef = getBossDefinition(enemy.bossDefinitionID)
  let phaseCount = max(1, max(bossDef.phases.len, enemy.bossPhaseHpPools.len))
  let currentPhase = clamp(enemy.currentPhaseIndex, 0, phaseCount - 1)
  # Only reveal the boss's full phase layout once the player has beaten it before;
  # otherwise show bars up to the current phase and don't spoil what's coming.
  let revealAll = hasDefeatedBoss(globalStats, enemy.bossDefinitionID)
  let visiblePhases = if revealAll: phaseCount else: currentPhase + 1

  let rowH = 13'i32
  let headerH = 38'i32   # classic horizontal header (widescreen uses its own card)
  # Widescreen right-gutter variant: size the panel to the gutter width so it sits
  # flush in the side band rather than overlapping the arena.
  let gutterW = (getVirtualScreenWidth() - game.screenWidth) div 2
  let panelW = if alignRight: gutterW - 8'i32
               else: min(520'i32, max(340'i32, game.screenWidth - 80'i32))
  let panelH = headerH + rowH * visiblePhases.int32 + 11'i32
  let panelX = if alignRight: getVirtualScreenWidth() - panelW - 4'i32
               else: game.screenWidth div 2 - panelW div 2
  let panelY = topY
  let activeColor =
    if currentPhase < bossDef.phases.len: bossDef.phases[currentPhase].color
    else: enemy.color

  # A subtle pulse when the boss is low or briefly invulnerable at a phase change,
  # so the widescreen bar demands attention at the dramatic beats.
  let hpFrac = clamp(enemy.hp / max(enemy.maxHp, 0.01'f32), 0.0'f32, 1.0'f32)
  let pulseT = if alignRight and (hpFrac < 0.28'f32 or enemy.invulnerabilityTimer > 0.0'f32):
                 (0.5'f32 + 0.5'f32 * sin(game.time * 8.0'f32))
               else: 0.0'f32

  if alignRight:
    # ===== WIDESCREEN VERTICAL BOSS CARD =====
    # A tall column card filling the right gutter: boss name up top, a tall
    # bottom-to-top HP bar as the centerpiece, a phase-pip column alongside it,
    # plus the breathing glow / low-HP pulse.
    let cardH = if slotH > 0'i32: slotH else: 176'i32
    let threatName = getEnemyProcessName(enemy)
    let phaseCountLabel = if revealAll: $phaseCount else: "?"
    let phaseText = t(tkBossThreatPhaseHeader) & " " & $(currentPhase + 1) & "/" & phaseCountLabel
    let hpText = formatHealthDisplay(enemy.hp) & " / " & formatHealthDisplay(enemy.maxHp)

    # Breathing outer glow.
    let glowA = uint8(clamp(50.0'f32 + pulseT * 150.0'f32, 0.0, 255.0))
    drawRectangleLines(Rectangle(x: (panelX - 2).float32, y: (panelY - 2).float32,
                                 width: (panelW + 4).float32, height: (cardH + 4).float32),
                       2, withAlpha(activeColor, glowA.int))
    drawRectangle(panelX + 3, panelY + 4, panelW, cardH, Color(r: 0, g: 0, b: 0, a: 110))
    drawRectangle(panelX, panelY, panelW, cardH, Color(r: 8, g: 12, b: 19, a: 236))
    drawRectangle(panelX, panelY, panelW, 4, activeColor)
    drawRectangleLines(Rectangle(x: panelX.float32, y: panelY.float32,
                                 width: panelW.float32, height: cardH.float32),
                       2, withAlpha(activeColor, 230))

    # Header: CRITICAL PROCESS label, big boss name, compact phase text.
    drawText(t(tkBossThreatCritical), panelX + 11, panelY + 7, 8, withAlpha(activeColor, 240))
    let nameSize = bestFitFontSize(threatName, panelW - 22, 18, 10)
    drawText(threatName, panelX + 12, panelY + 18, nameSize, Color(r: 0, g: 0, b: 0, a: 150))
    drawText(threatName, panelX + 11, panelY + 17, nameSize, Color(r: 240, g: 247, b: 255, a: 255))
    let phaseSize = bestFitFontSize(phaseText, panelW - 22, 9, 7)
    drawText(phaseText, panelX + 11, panelY + 34, phaseSize, withAlpha(activeColor, 245))

    # Vertical HP bar (current phase pool), filling bottom-to-top.
    let barTop = panelY + 46
    let barBot = panelY + cardH - 20
    let barAreaH = max(20'i32, barBot - barTop)
    let barW = 52'i32
    let barX = panelX + 13
    drawRectangle(barX, barTop, barW, barAreaH, Color(r: 10, g: 14, b: 20, a: 235))
    let fillH = int32(barAreaH.float32 * hpFrac)
    if fillH > 0:
      let fy = barBot - fillH
      let bright = Color(r: min(255, activeColor.r.int + 80).uint8,
                         g: min(255, activeColor.g.int + 80).uint8,
                         b: min(255, activeColor.b.int + 80).uint8, a: 255)
      drawRectangleGradientV(barX, fy, barW, fillH, bright, withAlpha(activeColor, 235))
      drawRectangle(barX, fy, barW, 2, Color(r: 255, g: 255, b: 255, a: 205))
    drawRectangleLines(Rectangle(x: barX.float32, y: barTop.float32,
                                 width: barW.float32, height: barAreaH.float32),
                       2, withAlpha(activeColor, 235))
    # HP value under the bar.
    let hpValW = measureText(hpText, 9)
    drawText(hpText, barX + barW div 2 - hpValW div 2, barBot + 4, 9,
             Color(r: 210, g: 225, b: 240, a: 255))

    # Phase-pip column beside the bar (P1 at the bottom, PN at the top).
    let pipX = barX + barW + 9
    let pipW = max(8'i32, panelX + panelW - 11 - pipX)
    let pipGap = 3'i32
    let pc = max(1, phaseCount).int32
    let pipH = max(4'i32, (barAreaH - (pc - 1) * pipGap) div pc)
    for p in 0..<pc:
      let py = barBot - (p + 1) * pipH - p * pipGap
      let pcol = if p < bossDef.phases.len: bossDef.phases[p].color else: enemy.color
      let (pfill, pa) =
        if p < currentPhase: (true, 150)
        elif p == currentPhase: (true, int(200.0'f32 + pulseT * 55.0'f32))
        elif revealAll: (false, 70)
        else: (false, 40)
      if pfill:
        drawRectangle(pipX, py, pipW, pipH, withAlpha(pcol, pa))
      else:
        drawRectangle(pipX, py, pipW, pipH, Color(r: 14, g: 20, b: 28, a: 200))
      drawRectangleLines(Rectangle(x: pipX.float32, y: py.float32, width: pipW.float32, height: pipH.float32),
                         1, withAlpha(pcol, pa))
      if pipH >= 12:
        drawText("P" & $(p + 1), pipX + 3, py + (pipH - 8) div 2, 8,
                 if p == currentPhase: White else: withAlpha(pcol, pa))

    # Firewall / phase-transition invulnerability indicator.
    if enemy.invulnerabilityTimer > 0:
      let shieldText = t(tkBossPhaseFirewall)
      let stW = measureText(shieldText, 9)
      drawText(shieldText, panelX + panelW div 2 - stW div 2, panelY + cardH - 12, 9,
               withAlpha(activeColor, uint8(clamp(190.0'f32 + pulseT * 65.0'f32, 0.0, 255.0)).int))
    return panelY + cardH + 6

  # ----- Classic horizontal boss bar (widescreen returned early above) -----
  drawRectangle(panelX + 3, panelY + 4, panelW, panelH, Color(r: 0, g: 0, b: 0, a: 110))
  drawRectangle(panelX, panelY, panelW, panelH, Color(r: 8, g: 12, b: 19, a: 232))
  drawRectangle(panelX, panelY, panelW, 3, activeColor)
  drawRectangleLines(Rectangle(x: panelX.float32, y: panelY.float32,
                               width: panelW.float32, height: panelH.float32),
                     1, withAlpha(activeColor, 210))

  let threatName = getEnemyProcessName(enemy)
  let phaseName =
    if currentPhase < bossDef.phases.len:
      bossDef.phases[currentPhase].name
    else:
      t(tkBossThreatPhaseName) & " " & $(currentPhase + 1)
  let phaseCountLabel = if revealAll: $phaseCount else: "?"
  let phaseText = t(tkBossThreatPhaseHeader) & " " & $(currentPhase + 1) & "/" & phaseCountLabel & " :: " & phaseName
  let hpText = formatHealthDisplay(enemy.hp) & " / " & formatHealthDisplay(enemy.maxHp)

  block:
    drawText(t(tkBossThreatCritical), panelX + 11, panelY + 7, 8, withAlpha(activeColor, 240))
    drawText(threatName, panelX + 11, panelY + 17, 13, Color(r: 238, g: 245, b: 255, a: 255))
    let phaseTextW = measureText(phaseText, 10)
    drawText(phaseText, panelX + panelW - phaseTextW - 11, panelY + 9, 10, withAlpha(activeColor, 240))
    let hpTextW = measureText(hpText, 10)
    drawText(hpText, panelX + panelW - hpTextW - 11, panelY + 23, 10, Color(r: 210, g: 225, b: 240, a: 255))

  let barX = panelX + 12
  let barW = panelW - 24
  var y = panelY + headerH - 4
  for i in 0..<visiblePhases:
    let phaseColor =
      if i < bossDef.phases.len: bossDef.phases[i].color
      else: enemy.color
    let phaseMax = bossPhaseMaxHp(enemy, i, phaseCount)
    let fillPct =
      if i < currentPhase:
        1.0'f32
      elif i == currentPhase:
        clamp(enemy.hp / max(enemy.maxHp, 0.01'f32), 0.0'f32, 1.0'f32)
      else:
        0.0'f32
    let fillW = int32(barW.float32 * fillPct)
    let rowAlpha =
      if i < currentPhase: 150
      elif i == currentPhase: 255
      else: 85
    let rowBg = if i == currentPhase:
      Color(r: 24, g: 30, b: 42, a: 230)
    else:
      Color(r: 12, g: 17, b: 25, a: 210)

    drawRectangle(barX, y, barW, 9, rowBg)
    if fillW > 0:
      drawRectangleGradientH(barX, y, fillW, 9,
                             withAlpha(phaseColor, rowAlpha),
                             Color(r: min(255, phaseColor.r.int + 70).uint8,
                                   g: min(255, phaseColor.g.int + 70).uint8,
                                   b: min(255, phaseColor.b.int + 70).uint8,
                                   a: rowAlpha.uint8))
      drawRectangle(barX, y, fillW, 2, Color(r: 255, g: 255, b: 255, a: uint8(rowAlpha div 4)))

    let label = "P" & $(i + 1)
    drawText(label, barX + 4, y + 1, 8,
             if i == currentPhase: White else: withAlpha(phaseColor, rowAlpha))

    if i < currentPhase:
      drawText(t(tkBossThreatBreached), barX + barW - 52, y + 1, 8, Color(r: 255, g: 190, b: 110, a: 180))
    elif i > currentPhase:
      drawText(t(tkBossThreatLocked), barX + barW - 40, y + 1, 8, Color(r: 120, g: 140, b: 160, a: 160))
    else:
      let poolText = formatHealthDisplay(enemy.hp) & "/" & formatHealthDisplay(phaseMax)
      let poolTextW = measureText(poolText, 8)
      drawText(poolText, barX + barW - poolTextW - 6, y + 1, 8, White)

    drawRectangleLines(Rectangle(x: barX.float32, y: y.float32,
                                 width: barW.float32, height: 9.0'f32),
                       1, withAlpha(phaseColor, rowAlpha))
    y += rowH

  if enemy.invulnerabilityTimer > 0:
    let shieldPct = clamp(enemy.invulnerabilityTimer / BOSS_PHASE_INVULNERABILITY_DURATION, 0.0'f32, 1.0'f32)
    let shieldText = t(tkBossPhaseFirewall) & " " & formatFloat(enemy.invulnerabilityTimer, ffDecimal, 1) & "s"
    let shieldW = measureText(shieldText, 10) + 16
    let shieldX = panelX + panelW div 2 - shieldW div 2
    let shieldY = panelY + panelH - 15
    drawRectangle(shieldX, shieldY, shieldW, 12, Color(r: 5, g: 15, b: 24, a: 235))
    drawRectangle(shieldX, shieldY, int32(shieldW.float32 * shieldPct), 12, withAlpha(activeColor, 125))
    drawRectangleLines(Rectangle(x: shieldX.float32, y: shieldY.float32,
                                 width: shieldW.float32, height: 12.0'f32),
                       1, withAlpha(activeColor, 255))
    drawText(shieldText, shieldX + 8, shieldY + 2, 10, White)

  return panelY + panelH + 6

proc drawBossSatellite(sat: OrbitalSatellite, time: float32, isObjective: bool) =
  ## One boss satellite drawn as a space-station miniature. Pulled out of drawGame
  ## verbatim; it only ever needed the satellite, the clock and the objective flag.
  let sx = sat.pos.x
  let sy = sat.pos.y
  let t  = time

  # Whether this satellite is charging its laser
  let charging  = sat.laserActive and sat.laserChargeTime < 1.5
  let firing    = sat.laserActive and sat.laserChargeTime >= 1.5

  # Pulse and glow drivers
  let pulse     = sin(t * 5.0 + sat.angle * 3.0) * 0.5 + 0.5   # 0..1, per-satellite phase
  let fastPulse = sin(t * 12.0 + sat.angle * 4.0) * 0.5 + 0.5

  # Color scheme: cool blue normally, hot red/orange when charging, white burst when firing
  let coreColor =
    if firing:    Color(r: 255, g: 255, b: 255, a: 255)
    elif charging:Color(r: 255, g: uint8(60  + pulse * 100), b: 30,  a: 255)
    else:         Color(r: 60,  g: uint8(160 + pulse * 60),  b: 255, a: 255)

  let glowColor =
    if firing:    Color(r: 255, g: 220, b: 120, a: 160)
    elif charging:Color(r: 255, g: 80,  b: 0,   a: uint8(100 + fastPulse * 120))
    else:         Color(r: 80,  g: 140, b: 255, a: uint8(60  + pulse * 80))

  let panelColor =
    if firing:    Color(r: 220, g: 220, b: 255, a: 255)
    elif charging:Color(r: 255, g: 200, b: 80,  a: 255)
    else:         Color(r: 100, g: 180, b: 255, a: 220)

  let rimColor  = Color(r: 200, g: 220, b: 255, a: 200)

  #  outer glow halo
  let glowR = 22.0 + pulse * 5.0 + (if charging: fastPulse * 8.0 else: 0.0)
  drawCircle(Vector2(x: sx, y: sy), glowR,
             withAlpha(glowColor, uint8(glowColor.a.int div 3)))
  drawCircleLines(sx.int32, sy.int32, glowR,
             withAlpha(glowColor, glowColor.a))

  #  rotating outer shield ring
  let shieldAngle = t * (if sat.rotationSpeed > 0: 2.2 else: -2.2) + sat.angle
  for k in 0..5:
    let ra = shieldAngle + k.float32 * (PI / 3.0)
    let ax = sx + cos(ra) * 15.0
    let ay = sy + sin(ra) * 15.0
    drawCircle(Vector2(x: ax, y: ay), 2.5,
               withAlpha(coreColor, uint8(160 + pulse * 80)))

  #  hexagonal body outline
  let bodyAngle = t * 0.4 * (if sat.rotationSpeed >= 0: 1.0 else: -1.0) + sat.angle * 0.3
  for k in 0..5:
    let a0 = bodyAngle + k.float32       * (PI / 3.0)
    let a1 = bodyAngle + (k + 1).float32 * (PI / 3.0)
    let bx0 = sx + cos(a0) * 11.0;  let by0 = sy + sin(a0) * 11.0
    let bx1 = sx + cos(a1) * 11.0;  let by1 = sy + sin(a1) * 11.0
    drawLine(Vector2(x: bx0, y: by0), Vector2(x: bx1, y: by1), 2.5, rimColor)

  #  solar panel wings
  # Two rigid arms extending perpendicular to the current orbit tangent
  let tangentAngle = sat.angle + PI / 2.0  # tangent to orbit direction
  for side in [-1.0, 1.0]:
    let armAngle = tangentAngle + (if side > 0: 0.0 else: PI)
    let panelDist = 14.0
    let panelW    = 10.0
    let panelH    = 5.0
    # Arm strut
    let armTipX = sx + cos(armAngle) * panelDist
    let armTipY = sy + sin(armAngle) * panelDist
    drawLine(Vector2(x: sx + cos(armAngle) * 5.0,  y: sy + sin(armAngle) * 5.0),
             Vector2(x: armTipX, y: armTipY), 2.0,
             Color(r: 180, g: 200, b: 220, a: 200))
    # Panel rectangle (4 corners)
    let perpX = cos(armAngle + PI / 2.0) * panelW
    let perpY = sin(armAngle + PI / 2.0) * panelW
    let fwdX  = cos(armAngle) * panelH
    let fwdY  = sin(armAngle) * panelH
    let p0 = Vector2(x: armTipX + perpX + fwdX, y: armTipY + perpY + fwdY)
    let p1 = Vector2(x: armTipX - perpX + fwdX, y: armTipY - perpY + fwdY)
    let p2 = Vector2(x: armTipX - perpX - fwdX, y: armTipY - perpY - fwdY)
    let p3 = Vector2(x: armTipX + perpX - fwdX, y: armTipY + perpY - fwdY)
    drawLine(p0, p1, 2.0, panelColor)
    drawLine(p1, p2, 2.0, panelColor)
    drawLine(p2, p3, 2.0, panelColor)
    drawLine(p3, p0, 2.0, panelColor)
    # Panel centre stripe (solar cell division)
    let midA = Vector2(x: (p0.x + p3.x) * 0.5, y: (p0.y + p3.y) * 0.5)
    let midB = Vector2(x: (p1.x + p2.x) * 0.5, y: (p1.y + p2.y) * 0.5)
    drawLine(midA, midB, 1.0, Color(r: 120, g: 200, b: 255, a: 160))

  #  core filled circle
  drawCircle(Vector2(x: sx, y: sy), 9.0, coreColor)

  #  lens flare dot
  let lensR = 3.5 + (if firing: fastPulse * 4.0 else: pulse * 1.5)
  drawCircle(Vector2(x: sx, y: sy), lensR,
             Color(r: 255, g: 255, b: 255, a: uint8(200 + fastPulse * 55)))

  #  charging / firing effects
  if charging:
    # Spinning danger chevrons
    let chevAngle = t * 6.0 + sat.angle
    for k in 0..2:
      let ca = chevAngle + k.float32 * (PI * 2.0 / 3.0)
      let cx0 = sx + cos(ca) * 18.0
      let cy0 = sy + sin(ca) * 18.0
      let cx1 = sx + cos(ca + 0.4) * 13.0
      let cy1 = sy + sin(ca + 0.4) * 13.0
      let cx2 = sx + cos(ca - 0.4) * 13.0
      let cy2 = sy + sin(ca - 0.4) * 13.0
      drawLine(Vector2(x: cx0, y: cy0), Vector2(x: cx1, y: cy1), 2.0,
               Color(r: 255, g: 80, b: 0, a: uint8(180 + fastPulse * 75)))
      drawLine(Vector2(x: cx0, y: cy0), Vector2(x: cx2, y: cy2), 2.0,
               Color(r: 255, g: 80, b: 0, a: uint8(180 + fastPulse * 75)))

    # Expanding charge ring
    let chargeProgress = sat.laserChargeTime / 1.5
    let chargeRingR = 9.0 + chargeProgress * 24.0
    drawCircleLines(sx.int32, sy.int32, chargeRingR,
                    Color(r: 255, g: uint8(200 - chargeProgress * 150), b: 0,
                          a: uint8(220 - chargeProgress * 120)))

  elif firing:
    # Rapid concentric flash rings
    for k in 0..2:
      let flashR = 8.0 + k.float32 * 7.0 + fastPulse * 5.0
      drawCircleLines(sx.int32, sy.int32, flashR,
                      Color(r: 255, g: 220, b: 120, a: uint8(180 - k * 50)))

  #  target crosshair on the locked player position
  if charging:
    let targetSize = 16.0
    let tAlpha = uint8(140 + fastPulse * 115)
    let tColor = Color(r: 255, g: 60, b: 30, a: tAlpha)
    # + crosshair
    drawLine(Vector2(x: sat.laserTarget.x - targetSize, y: sat.laserTarget.y),
             Vector2(x: sat.laserTarget.x + targetSize, y: sat.laserTarget.y), 2.0, tColor)
    drawLine(Vector2(x: sat.laserTarget.x, y: sat.laserTarget.y - targetSize),
             Vector2(x: sat.laserTarget.x, y: sat.laserTarget.y + targetSize), 2.0, tColor)
    # Inner dot
    drawCircle(Vector2(x: sat.laserTarget.x, y: sat.laserTarget.y), 3.5,
               Color(r: 255, g: 255, b: 255, a: tAlpha))
    # Outer pulsing ring
    drawCircleLines(sat.laserTarget.x.int32, sat.laserTarget.y.int32,
                    targetSize + fastPulse * 6.0, tColor)

  #  Objective diamond: show when satellite is a shoot-to-destroy target 
  if isObjective:
    let dp  = sin(time * 6.0 + sat.angle * 2.0) * 0.5 + 0.5
    let da  = uint8(clamp(160.0 + dp * 95.0, 0.0, 255.0))
    let ds  = 9.0 + dp * 3.0   # diamond half-size
    let dcol = Color(r: 255, g: 220, b: 60, a: da)
    drawLine(Vector2(x: sx,      y: sy - ds), Vector2(x: sx + ds, y: sy     ), 2.0, dcol)
    drawLine(Vector2(x: sx + ds, y: sy     ), Vector2(x: sx,      y: sy + ds), 2.0, dcol)
    drawLine(Vector2(x: sx,      y: sy + ds), Vector2(x: sx - ds, y: sy     ), 2.0, dcol)
    drawLine(Vector2(x: sx - ds, y: sy     ), Vector2(x: sx,      y: sy - ds), 2.0, dcol)

proc drawGame*(game: Game) =
  # Profiling counterpart to updateGame: smoothed wall-clock ms spent drawing.
  # (game is a ref, so mutating this field through the non-var binding is fine.)
  let perfStart = getTime()
  defer: game.perfDrawMs = game.perfDrawMs * 0.9'f32 +
                           float32((getTime() - perfStart) * 1000.0) * 0.1'f32
  # Calculate screen shake offset
  var shakeOffsetX: float32 = 0
  var shakeOffsetY: float32 = 0

  let shakeOffset = getShakeOffset(game.dopamine.screenShake)
  shakeOffsetX = shakeOffset.x
  shakeOffsetY = shakeOffset.y

  # ===================== WORLD PASS =====================
  # Everything drawn here is translated by the world view offset (widescreen
  # gutters) plus screen shake, and clipped to the world rect so nothing bleeds
  # into the side gutters. The HUD pass below is untranslated (virtual coords).
  let worldOffX = getWorldViewOffsetX()
  let worldScissorOpen = worldOffX > 0
  if worldScissorOpen:
    beginVirtualScissorMode(worldOffX.int32, 0, game.screenWidth, game.screenHeight)
  let worldPassOpen = worldOffX != 0 or shakeOffsetX != 0 or shakeOffsetY != 0
  if worldPassOpen:
    pushMatrix()
    translatef(worldOffX + shakeOffsetX, shakeOffsetY, 0.0'f32)

  # Update and draw OS-style background
  let dt = getFrameTime()
  updateOSBackground(game.osBackground, dt, game.player.hp, game.player.maxHp,
                     game.bossWaveManager.isBossActive(),
                     game.screenWidth, game.screenHeight)
  let showArenaVignette = globalSettings == nil or globalSettings.showArenaVignette
  let bgAccent = if game.mode == gmRoguelite and game.rogueliteRun != nil and
                    game.rogueliteRun.floor != nil:
    themeAccent(game.rogueliteRun.floor.theme)
  else:
    Color(r: 0, g: 0, b: 0, a: 0)
  drawOSBackground(game.osBackground, game.screenWidth, game.screenHeight,
                   showArenaVignette, bgAccent)

  # Draw background particles first
  drawParticlePoolLayer(game.particlePool, plBackground)

  # Draw lightning bolt arcs (chain lightning visuals, short-lived)
  drawLightningBolts(game)

  # Draw AoE blast boundary rings under the sparks so the lethal edge reads clearly
  drawShockwaveRings(game)

  # Draw attack warnings (before everything else so they're visible)
  if globalSettings == nil or globalSettings.showHints:
    for warning in game.attackWarnings:
      drawAttackWarning(warning)

  # The ricochet beam's live lethal pass renders regardless of the hint gate,
  # so the active beam is always visible (the wind-up telegraph above is the hint).
  # Same for the bosses 7-12 signature attacks' lethal flashes.
  for warning in game.attackWarnings:
    drawRicochetLaserBeam(warning)
    drawSignatureAttackActive(warning)

  # Draw lasers (after warnings, before walls for visual layering)
  for laser in game.lasers:
    drawLaser(laser)

  # Draw meteorites (show both warning and falling meteorites)
  for meteorite in game.meteorites:
    if meteorite.warningTimer > 0:
      # Real Meteorite rocks (etMage + boss signature modes) share the exact same
      # telegraph as the boss bapMeteor columns. While warning, meteorite.pos is
      # still the off-screen spawn, so passing it as the source makes the streak +
      # arrowhead point along the true incoming direction.
      let prog = clamp(1.0'f32 - meteorite.warningTimer /
                       max(0.0001'f32, meteorite.maxWarningTime), 0.0'f32, 1.0'f32)
      # Rocks with splashDamage explode on landing (blast = radius*3, matching the
      # impact code); pass that so the telegraph shows the AoE. Direct-hit rocks
      # pass 0 and get the plain (non-explosive) warning.
      let blastR = if meteorite.splashDamage > 0: meteorite.radius * 3.0'f32 else: 0.0'f32
      drawMeteorWarning(meteorite.targetPos, meteorite.pos, meteorite.radius,
                        Color(r: 255, g: 140, b: 40, a: 255), prog, blastR)
    else:
      # Falling meteorite: a molten rock with a fiery tail streaming behind it.
      let r = meteorite.radius
      let dir = meteorite.vel.normalize()   # zero-safe; falls back to (0,0)
      let td = if dir.x == 0 and dir.y == 0: newVector2f(0, 1) else: dir
      # Tapering flame puffs trailing opposite the travel direction.
      for t in 1 .. 6:
        let f = t.float32
        let tp = newVector2f(meteorite.pos.x - td.x * r * f * 0.85'f32,
                             meteorite.pos.y - td.y * r * f * 0.85'f32)
        let tr = max(2.0'f32, r * (1.0'f32 - f * 0.14'f32))
        let a = uint8(clamp(210.0'f32 - f * 32.0'f32, 0.0'f32, 255.0'f32))
        let gg = uint8(clamp(190.0'f32 - f * 26.0'f32, 50.0'f32, 255.0'f32))
        drawCircle(Vector2(x: tp.x, y: tp.y), tr, Color(r: 255, g: gg, b: 30, a: a))
      # Outer heat glow.
      drawCircle(Vector2(x: meteorite.pos.x, y: meteorite.pos.y), r + 6,
                 Color(r: 255, g: 140, b: 0, a: 70))
      # Molten body.
      drawCircle(Vector2(x: meteorite.pos.x, y: meteorite.pos.y), r,
                 Color(r: 255, g: 90, b: 0, a: 255))
      # Dark rocky core, offset toward the trailing edge so the front looks hottest.
      drawCircle(Vector2(x: meteorite.pos.x - td.x * r * 0.25'f32,
                         y: meteorite.pos.y - td.y * r * 0.25'f32),
                 r * 0.55'f32, Color(r: 90, g: 38, b: 22, a: 255))
      # Bright leading edge.
      drawCircle(Vector2(x: meteorite.pos.x + td.x * r * 0.4'f32,
                         y: meteorite.pos.y + td.y * r * 0.4'f32),
                 r * 0.3'f32, Color(r: 255, g: 230, b: 150, a: 220))

  # Draw walls
  for wall in game.walls:
    drawWall(wall, game.player)

  # Draw coins
  drawGameCoins(game)

  # Draw roguelite XP orbs
  if game.mode == gmRoguelite:
    drawGameXpOrbs(game)

  # Draw consumables
  for consumable in game.consumables:
    drawConsumable(consumable)

  # Draw bullets
  let hasOvercharge = hasPowerUp(game.player, puOvercharge)
  let hasBloodBullets = hasPowerUp(game.player, puBloodBullets)
  for bullet in game.bullets:
    drawBullet(bullet, hasOvercharge, hasBloodBullets, game.time)

  # Draw enemies
  for enemy in game.enemies:
    # Draw elite aura first (so it appears behind the enemy)
    if enemy.isElite:
      drawEliteAura(enemy, game.time)
    drawEnemy(enemy)
    # Draw elite overlay after body so outline + orbit crown render on top
    if enemy.isElite:
      drawEliteOverlay(enemy, game.time)
    if enemy.isBoss:
      # Mega-cast charge animation: rings converge on the frozen boss, energy
      # spokes spin into it, and a core glow swells toward fire time. Sells the
      # "channelling an ultimate" beat that pairs with the long beam telegraph.
      if enemy.megaCastTimer > 0 and enemy.megaCastTotal > 0:
        let charge = clamp(1.0'f32 - enemy.megaCastTimer / enemy.megaCastTotal, 0.0'f32, 1.0'f32)
        let cx = enemy.pos.x
        let cy = enemy.pos.y
        let baseR = enemy.radius
        for ring in 0..2:
          let ph = (game.time * 1.5'f32 + ring.float32 * 0.33'f32) mod 1.0'f32
          let conv = 1.0'f32 - ph                       # 1 = far out, 0 = at the boss
          let rr = baseR + 18.0'f32 + conv * (120.0'f32 + charge * 60.0'f32)
          let aa = uint8(clamp((1.0'f32 - conv) * 200.0'f32 * (0.4'f32 + charge * 0.6'f32), 0.0'f32, 255.0'f32))
          drawCircleLines(cx.int32, cy.int32, rr, Color(r: 120, g: 230, b: 255, a: aa))
        const spokes = 8
        let rot = game.time * (2.0'f32 + charge * 6.0'f32)
        for k in 0..<spokes:
          let ang = rot + k.float32 * (PI * 2.0'f32 / spokes.float32)
          let outer = baseR + 14.0'f32 + (1.0'f32 - charge) * 40.0'f32
          let inner = baseR + 4.0'f32
          drawLine(Vector2(x: cx + cos(ang) * outer, y: cy + sin(ang) * outer),
                   Vector2(x: cx + cos(ang) * inner, y: cy + sin(ang) * inner),
                   1.5'f32 + charge * 2.0'f32,
                   Color(r: 200, g: 245, b: 255,
                         a: uint8(clamp(120.0'f32 + charge * 135.0'f32, 0.0'f32, 255.0'f32))))
        let pulse = sin(game.time * (10.0'f32 + charge * 20.0'f32)) * 0.5'f32 + 0.5'f32
        let coreR = baseR * (0.6'f32 + charge * 0.5'f32 + pulse * 0.15'f32)
        drawCircle(Vector2(x: cx, y: cy), coreR,
                   Color(r: 150, g: 235, b: 255,
                         a: uint8(clamp(60.0'f32 + charge * 120.0'f32 + pulse * 40.0'f32, 0.0'f32, 255.0'f32))))
      drawBossWeakPoints(enemy, globalSettings == nil or globalSettings.showHints)
      #  Vulnerability window: bold expanding rings so the player never misses it 
      if enemy.weakPoint.exposedTimer > 0:
        let vt   = enemy.weakPoint.exposedTimer
        let vmax = enemy.weakPoint.exposureDuration
        # vpct: 1.0 when window just opened, 0.0 when about to close
        let vpct = clamp(vt / max(vmax, 0.001'f32), 0.0'f32, 1.0'f32)
        let vp   = sin(game.time * 9.0) * 0.5 + 0.5
        let va   = uint8(clamp(140.0 + vp * 115.0, 0.0, 255.0))
        let vr1  = enemy.radius + 18.0 + vp * 7.0
        let vr2  = enemy.radius + 30.0 + vp * 9.0
        # Fixed dot-count arc: all N dots placed evenly, only the first
        # floor(vpct*N) are lit no while-loop overshoot, no clipping.
        const ARC_DOTS = 32
        let litDots = int(vpct * ARC_DOTS.float32 + 0.5)  # round, never clips short
        let arcR    = enemy.radius + 38.0
        for k in 0..<ARC_DOTS:
          let angle = k.float32 / ARC_DOTS.float32 * PI * 2.0 - PI * 0.5
          let ax = enemy.pos.x + cos(angle) * arcR
          let ay = enemy.pos.y + sin(angle) * arcR
          let dotAlpha = if k < litDots:
            uint8(clamp(vpct * 220.0, 60.0, 220.0))
          else:
            uint8(30)   # dim ghost so full circle shape is always readable
          drawCircle(Vector2(x: ax, y: ay), 3.0,
                     Color(r: 255, g: 235, b: 80, a: dotAlpha))
        drawCircleLines(enemy.pos.x.int32, enemy.pos.y.int32, vr1,
                        Color(r: 255, g: 235, b: 80, a: va))
        drawCircleLines(enemy.pos.x.int32, enemy.pos.y.int32, vr2,
                        Color(r: 255, g: 255, b: 200, a: uint8(va.int div 3)))

      # Enrage aura: red spikes that thicken as the boss is left to stall.
      if enemy.bossEnrageLevel > 0.05'f32:
        let elv  = clamp(enemy.bossEnrageLevel / ENRAGE_MAX, 0.0'f32, 1.0'f32)
        let ep   = sin(game.time * 14.0) * 0.5 + 0.5
        let er   = enemy.radius + 6.0 + ep * 6.0
        let ea   = uint8(clamp(70.0 + elv * 160.0, 0.0, 255.0))
        for s in 0..<12:
          let a = game.time * 3.0 + s.float32 * PI / 6.0
          drawLine(Vector2(x: enemy.pos.x + cos(a) * er, y: enemy.pos.y + sin(a) * er),
                   Vector2(x: enemy.pos.x + cos(a) * (er + 8.0 + elv * 14.0),
                           y: enemy.pos.y + sin(a) * (er + 8.0 + elv * 14.0)),
                   1.5'f32 + elv * 1.5'f32, Color(r: 255, g: 50, b: 30, a: ea))

      # Adds-gate seal: amber lock ring telling the player to clear the adds first.
      if enemy.addsGateActive and enemy.weakPoint.exposedTimer <= 0:
        let sp = sin(game.time * 4.0) * 0.5 + 0.5
        let sa = uint8(clamp(110.0 + sp * 110.0, 0.0, 255.0))
        let sr = enemy.radius + 14.0 + sp * 4.0
        drawCircleLines(enemy.pos.x.int32, enemy.pos.y.int32, sr,
                        Color(r: 255, g: 180, b: 40, a: sa))
        drawCircleLines(enemy.pos.x.int32, enemy.pos.y.int32, sr + 5.0,
                        Color(r: 255, g: 140, b: 20, a: uint8(sa.int div 2)))
        if globalSettings == nil or globalSettings.showHints:
          let gt = t(tkEnemySealedClearAdds)
          drawText(gt, enemy.pos.x.int32 - measureText(gt, 10) div 2,
                   (enemy.pos.y - enemy.radius - 26.0).int32, 10,
                   Color(r: 255, g: 200, b: 90, a: 235))

      # Overload shield: rotating cyan hex shell that bounces body shots back.
      if enemy.reflectShieldActive:
        let pp  = sin(game.time * 8.0) * 0.5 + 0.5
        let shRad = enemy.radius + 16.0 + pp * 5.0
        let sha = uint8(clamp(150.0 + pp * 95.0, 0.0, 255.0))
        let spin = game.time * 1.4
        var prev = Vector2(x: enemy.pos.x + cos(spin) * shRad, y: enemy.pos.y + sin(spin) * shRad)
        for v in 1..6:
          let a = spin + v.float32 * PI / 3.0
          let cur = Vector2(x: enemy.pos.x + cos(a) * shRad, y: enemy.pos.y + sin(a) * shRad)
          drawLine(prev, cur, 3.0'f32, Color(r: 90, g: 200, b: 255, a: sha))
          prev = cur
        drawCircle(Vector2(x: enemy.pos.x, y: enemy.pos.y), shRad,
                   Color(r: 90, g: 200, b: 255, a: uint8(sha.int div 8)))
        if globalSettings == nil or globalSettings.showHints:
          let st = t(tkEnemyOverloadHoldFire)
          drawText(st, enemy.pos.x.int32 - measureText(st, 10) div 2,
                   (enemy.pos.y - enemy.radius - 26.0).int32, 10,
                   Color(r: 150, g: 220, b: 255, a: 235))

    # Draw OS-style enemy labels above each enemy
    drawEnemyLabel(enemy, showHealthBar = true, enabled = globalSettings.showEnemyLabels)

    # Draw warning indicators for elite/boss enemies
    if globalSettings == nil or globalSettings.showHints:
      drawEnemyWarningIndicator(enemy)

    # Draw boss satellites
    if enemy.isBoss and enemy.satellites.len > 0:
      # Orbit trail rings, one per unique radius
      for idx, sat in enemy.satellites:
        if idx mod 2 == 0:
          drawCircleLines(enemy.pos.x.int32, enemy.pos.y.int32, sat.radius,
                         Color(r: 100, g: 150, b: 255, a: 25))

      #  Objective indicators
      let satIsObjective = enemy.weakPoint.enabled and
                           enemy.weakPoint.kind == bwoSatelliteSet and
                           enemy.weakPoint.exposedTimer <= 0 and
                           enemy.weakPoint.cooldownTimer <= 0

      # Draw each satellite as a detailed space-station miniature
      for sat in enemy.satellites:
        drawBossSatellite(sat, game.time, satIsObjective)

  let playerVisible = game.state != gsDeathSequence

  # Draw Gravity Well visual effect
  if playerVisible and hasPowerUp(game.player, puGravityWell):
    let pullRadius = 300.0  # Matches actual gameplay pull radius

    # Draw swirling vortex rings
    for ring in 1..4:
      let ringRadius = pullRadius * (ring.float32 / 4.0)
      let alpha = uint8(60 - ring * 10)
      let rotationOffset = (game.time * (ring.float32 * 0.5)).float32

      # Draw spiral dots around each ring
      for i in 0..15:
        let angle = (i.float32 / 16.0) * PI * 2.0 + rotationOffset
        let x = game.player.pos.x + cos(angle) * ringRadius
        let y = game.player.pos.y + sin(angle) * ringRadius
        drawCircle(Vector2(x: x, y: y), 3, Color(r: 75, g: 0, b: 130, a: alpha))

    # Draw outer boundary, 3-pass so the pull limit is always clearly visible
    drawCircleLines(game.player.pos.x.int32, game.player.pos.y.int32, pullRadius + 4.0,
                   Color(r: 138, g: 43, b: 226, a: 55))
    drawCircleLines(game.player.pos.x.int32, game.player.pos.y.int32, pullRadius + 2.0,
                   Color(r: 138, g: 43, b: 226, a: 90))
    drawCircleLines(game.player.pos.x.int32, game.player.pos.y.int32, pullRadius,
                   Color(r: 170, g: 80, b: 255, a: 220))
    drawCircleLines(game.player.pos.x.int32, game.player.pos.y.int32, pullRadius - 2.5,
                   Color(r: 200, g: 140, b: 255, a: 110))

  # UNIFIED AURA RENDERING
  # Draw all active aura effects using the unified aura system
  # Each aura draws at its own radius with its own charge sweep, so a player
  # running several can read every one of them at a glance. Widest first, so the
  # tighter inner rings stay legible on top.
  const AURA_TYPES = [puSlowField, puFireAura, puLightningAura, puPoisonAura, puWindAura, puArcaneAura, puBloodAura]
  if playerVisible:
    for auraType in AURA_TYPES:
      if hasPowerUp(game.player, auraType):
        let level = getPowerUpLevel(game.player, auraType)
        let config = getAuraConfig(auraType, level)
        let slot = auraSlotOf(auraType)
        let mastery = case auraType
          of puFireAura: game.player.hasFireMastery
          of puLightningAura: game.player.hasLightningMastery
          of puPoisonAura: game.player.hasPoisonMastery
          of puWindAura: game.player.hasWindMastery
          of puArcaneAura: game.player.hasArcaneMastery
          of puBloodAura: game.player.hasBloodMastery
          else: false
        let interval = getAuraPulseInterval(auraType, level, mastery)
        # Sweep fills as the timer runs down toward the next pulse
        let charge = clamp(1.0'f32 - game.player.auraPulseTimers[slot] / interval, 0.0, 1.0)
        let flash = clamp(game.player.auraFlashTimers[slot] / AuraFlashDuration, 0.0, 1.0)
        drawAuraEffect(game.player.pos, config, game.time, charge, flash)

  # Draw player
  if playerVisible:
    drawPlayer(game.player)

  # Foreground particles, such as player muzzle bursts, render over the player.
  drawParticlePoolLayer(game.particlePool, plForeground)

  if game.player.lastDamageEvent == deDamage:
    # Re-use osBackground.alertLevel as a proxy for recent-damage intensity.
    # We clamp it to [0,1]; the existing alert system already fades it naturally.
    game.osBackground.alertLevel = min(game.osBackground.alertLevel + 0.5, 1.0)
    game.player.lastDamageEvent = deNone

  # Dungeon layer: doors, pedestals, shop terminal, room-transition fade
  if game.mode == gmRoguelite:
    drawDungeonOverlay(game)

  # Draw damage numbers (on top of everything except UI)
  for damageNum in game.damageNumbers:
    drawDamageNumber(damageNum)
  for currencyIndicator in game.currencyIndicators:
    drawCurrencyIndicator(currencyIndicator)
  for perkIndicator in game.perkIndicators:
    drawPerkIndicator(perkIndicator)

  # Recent power-up install card (world-anchored above the player).
  if game.recentPowerUpTimer > 0.0:
    drawRecentPowerUpInstall(game)
    if game.state notin {gsShop, gsPowerUpSelect}:
      game.recentPowerUpTimer = max(0.0'f32, game.recentPowerUpTimer - dt)

  # Micro rewards float near the player, so they belong in the world pass.
  if globalSettings == nil or globalSettings.showHints:
    drawMicroRewards(game.dopamine.microRewards)

  # Boss entrance warning: flashing "!" on the world edge the boss is entering from
  if game.bossWaveManager.isBossActive():
    # Avoid drawing over the wave banner when it's visible (suppressed in roguelite)
    let bannerVisible = if game.waveInProgress and game.mode != gmRoguelite: (game.time - game.waveStartTime) < 1.5 else: false

    # Helper: draw a minimal warning, just an exclamation with a soft circular background
    proc drawSimpleWarning(xCenter, yCenter: int32, timeFactor: float32) =
      let pulse = (sin(game.time * 6.0) + 1.0) * 0.5
      let alphaF = clamp(0.5 + pulse * 0.5, 0.0, 1.0) * timeFactor
      let bgAlpha = uint8(clamp(alphaF * 200.0, 0.0, 255.0))
      let ringAlpha = uint8(max(0, (bgAlpha.int div 3).int))
      # Soft filled circle
      drawCircle(Vector2(x: xCenter.float32, y: yCenter.float32), 36.0, Color(r: 255, g: 60, b: 60, a: bgAlpha))
      # Subtle outer ring
      drawCircleLines(xCenter, yCenter, 44.0, Color(r: 255, g: 60, b: 60, a: ringAlpha))
      # Exclamation mark
      let excFont: int32 = 44
      let excW = measureText("!", excFont)
      drawText("!", xCenter - excW div 2, yCenter - excFont div 2, excFont, Color(r: 255, g: 60, b: 60, a: 255))

    # If a boss is scheduled but not yet added, show its warning using pending data
    if game.pendingBoss != nil and game.pendingBossTimer > 0:
      let enemy = game.pendingBoss
      let sh = game.screenHeight.float32
      let fromTop    = enemy.startPos.y < 0
      let fromBottom = enemy.startPos.y > sh
      let fromLeft   = enemy.startPos.x < 0

      let pillW: int32 = 62
      let pillH: int32 = 62
      let pad:   int32 = 10
      var pillX, pillY: int32

      if fromTop:
        pillX = game.screenWidth div 2 - pillW div 2
        if bannerVisible:
          let bannerH: int32 = 44
          pillY = bannerH + pad + 6
        else:
          pillY = pad
      elif fromBottom:
        pillX = game.screenWidth div 2 - pillW div 2
        pillY = game.screenHeight - pillH - pad
      elif fromLeft:
        pillX = pad
        pillY = game.screenHeight div 2 - pillH div 2
      else:
        pillX = game.screenWidth - pillW - pad
        pillY = game.screenHeight div 2 - pillH div 2

      let cx = pillX + pillW div 2
      let cy = pillY + pillH div 2
      let timeFactor = clamp(1.0 - (game.pendingBossTimer / 0.2), 0.0, 1.0)
      drawSimpleWarning(cx, cy, timeFactor.float32)
    else:
      for enemy in game.enemies:
        if enemy.isBoss and enemy.entranceTimer > 0:
          let sh = game.screenHeight.float32
          let fromTop    = enemy.startPos.y < 0
          let fromBottom = enemy.startPos.y > sh
          let fromLeft   = enemy.startPos.x < 0

          let pillW: int32 = 62
          let pillH: int32 = 62
          let pad:   int32 = 10
          var pillX, pillY: int32

          if fromTop:
            pillX = game.screenWidth div 2 - pillW div 2
            if bannerVisible:
              let bannerH: int32 = 44
              pillY = bannerH + pad + 6
            else:
              pillY = pad
          elif fromBottom:
            pillX = game.screenWidth div 2 - pillW div 2
            pillY = game.screenHeight - pillH - pad
          elif fromLeft:
            pillX = pad
            pillY = game.screenHeight div 2 - pillH div 2
          else:
            pillX = game.screenWidth - pillW - pad
            pillY = game.screenHeight div 2 - pillH div 2

          let cx = pillX + pillW div 2
          let cy = pillY + pillH div 2
          # Entrance progress (used to modulate intensity)
          let entranceProg = clamp(1.0 - (enemy.entranceTimer / 2.0), 0.0, 1.0)
          drawSimpleWarning(cx, cy, (0.6 + 0.4 * entranceProg).float32)
          break

  # Wall-placement range ring + ghost preview (world-anchored at the cursor).
  if game.state != gsShop and game.wallPlacementMode and game.player.walls > 0:
    const WallPlaceRange = 250.0'f32
    let mousePos = getWorldMousePosition()
    let cursorPos = newVector2f(mousePos.x, mousePos.y)
    let inRange = distance(cursorPos, game.player.pos) <= WallPlaceRange
    let validPos = isValidWallPlacement(cursorPos, game.player.pos, game.walls, game.enemies, 25)
    let canPlace = inRange and validPos

    # Range indicator around the player. Drawn after auras/orbs/player, so it
    # already sits on top visually; it just has to be bold enough to read over
    # all the glow beneath it. Pulse + glow + zone tint + rotating ticks.
    let px = game.player.pos.x.int32
    let py = game.player.pos.y.int32
    let pulse = sin(game.time * 4.0) * 0.5 + 0.5         # 0..1 breathing
    let ringR = WallPlaceRange + pulse * 4.0
    let ringA = uint8(clamp(150.0 + pulse * 105.0, 0.0, 255.0))

    # Subtle fill so the buildable zone reads as an area, not just an edge.
    drawCircle(Vector2(x: game.player.pos.x, y: game.player.pos.y), WallPlaceRange,
               Color(r: 90, g: 130, b: 255, a: 14))

    # Boundary: outer glow -> bright core -> inner highlight (3-pass, like the
    # gravity-pull limit ring) so the edge stays crisp over busy backgrounds.
    drawCircleLines(px, py, ringR + 5.0, Color(r: 120, g: 160, b: 255, a: uint8(ringA.int div 4)))
    drawCircleLines(px, py, ringR + 2.5, Color(r: 150, g: 185, b: 255, a: uint8(ringA.int div 2)))
    drawCircleLines(px, py, ringR,       Color(r: 200, g: 225, b: 255, a: ringA))
    drawCircleLines(px, py, ringR - 2.5, Color(r: 235, g: 245, b: 255, a: uint8(ringA.int div 2)))

    # Rotating tick marks on the boundary make the ring unmistakable and give
    # it motion the eye catches even through dense aura particles.
    for i in 0 ..< 24:
      let a = game.time * 0.6 + i.float32 / 24.0 * PI * 2.0
      let tx = game.player.pos.x + cos(a) * ringR
      let ty = game.player.pos.y + sin(a) * ringR
      drawCircle(Vector2(x: tx, y: ty), 2.2 + pulse * 1.0,
                 Color(r: 215, g: 235, b: 255, a: ringA))

    # Ghost preview at cursor: green = valid, red = blocked. Turrets place as
    # circular emplacements, plain walls as a slab facing away from the player,
    # so preview whichever shape (and orientation) will actually be placed.
    let ghostFill = if canPlace: Color(r: 80, g: 200, b: 80, a: 90)
                    else: Color(r: 200, g: 60, b: 60, a: 90)
    let ghostEdge = if canPlace: Color(r: 80, g: 255, b: 80, a: 200)
                    else: Color(r: 255, g: 60, b: 60, a: 200)
    if hasPowerUp(game.player, puWallTurrets):
      drawCircle(Vector2(x: cursorPos.x, y: cursorPos.y), 25, ghostFill)
      drawCircleLines(cursorPos.x.int32, cursorPos.y.int32, 25, ghostEdge)
    else:
      # Mirror drawBarricadeWall: thin along the outward normal, broad across.
      let ga = arctan2(cursorPos.y - game.player.pos.y, cursorPos.x - game.player.pos.x)
      let gca = cos(ga)
      let gsa = sin(ga)
      const gHalfLen = 25.0'f32
      const gHalfThick = 25.0'f32 * WallSlabThicknessRatio
      drawRectangle(Rectangle(x: cursorPos.x, y: cursorPos.y,
                              width: gHalfThick * 2, height: gHalfLen * 2),
                    Vector2(x: gHalfThick, y: gHalfLen), radToDeg(ga), ghostFill)
      template gcorner(lx, ly: float32): Vector2 =
        Vector2(x: cursorPos.x + lx * gca - ly * gsa,
                y: cursorPos.y + lx * gsa + ly * gca)
      let c1 = gcorner(-gHalfThick, -gHalfLen)
      let c2 = gcorner(gHalfThick, -gHalfLen)
      let c3 = gcorner(gHalfThick, gHalfLen)
      let c4 = gcorner(-gHalfThick, gHalfLen)
      drawLine(c1, c2, 2.0'f32, ghostEdge)
      drawLine(c2, c3, 2.0'f32, ghostEdge)
      drawLine(c3, c4, 2.0'f32, ghostEdge)
      drawLine(c4, c1, 2.0'f32, ghostEdge)

  # ===================== END WORLD PASS =====================
  if worldPassOpen:
    popMatrix()
  if worldScissorOpen:
    endScissorMode()

  # ===================== HUD PASS =====================
  # Untranslated, virtual coords. The HUD stays fixed while the world shakes,
  # and spans the full virtual width so the widescreen gutters are covered.
  let vw = getVirtualScreenWidth()
  let vh = getVirtualScreenHeight()

  let showLowHealthVignette = globalSettings == nil or globalSettings.showLowHealthVignette
  if showLowHealthVignette and game.osBackground.lowHealthVignetteLevel > 0:
    let lowHpLevel = game.osBackground.lowHealthVignetteLevel
    let beatWave = max(0.0, sin(game.time * (3.4 + lowHpLevel * 1.6)))
    let beatScale = 1.0 + beatWave * (0.06 + lowHpLevel * 0.10)
    let lowHpMaxAlpha = lowHpLevel * 62.0 * beatScale
    let maxInset = 140.0 * (1.0 + beatWave * (0.03 + lowHpLevel * 0.04))
    for band in 0..7:
      let bandT = band.float32 / 7.0
      let inset = int32(bandT * maxInset)
      let bandAlpha = uint8(lowHpMaxAlpha * (1.0 - bandT) * 0.85)
      if bandAlpha == 0:
        continue

      let bandRect = Rectangle(
        x: inset.float32,
        y: inset.float32,
        width: max(0, vw - inset * 2).float32,
        height: max(0, vh - inset * 2).float32
      )
      drawRectangleLines(bandRect, 3, Color(r: 255, g: 0, b: 0, a: bandAlpha))

  # Full-screen red vignette when alertLevel > 0
  if game.osBackground.alertLevel > 0:
    let vigAlpha = uint8(game.osBackground.alertLevel * 92)
    let vW: int32 = 160
    drawRectangleGradientH(0, 0, vW, vh,
      Color(r: 255, g: 0, b: 0, a: vigAlpha), Color(r: 0, g: 0, b: 0, a: 0))
    drawRectangleGradientH(vw - vW, 0, vW, vh,
      Color(r: 0, g: 0, b: 0, a: 0), Color(r: 255, g: 0, b: 0, a: vigAlpha))
    drawRectangleGradientV(0, 0, vw, vW,
      Color(r: 255, g: 0, b: 0, a: vigAlpha), Color(r: 0, g: 0, b: 0, a: 0))
    drawRectangleGradientV(0, vh - vW, vw, vW,
      Color(r: 0, g: 0, b: 0, a: 0), Color(r: 255, g: 0, b: 0, a: vigAlpha))

  # Update OS-style HUD
  updateOSHUD(game.osHUD, dt)

  # Draw unified combined HUD panel (top-left, almost touching top)
  let hudLayout = if globalSettings == nil: hlClassic else: globalSettings.hudLayout
  if hudLayout == hlWidescreen:
    drawBorderHUDPanel(game)
  else:
    drawCombinedHUDPanel(game, 10, 2)

  # Right/left gutter geometry (widescreen: world is 1024 wide, centered).
  let rightGutterX = getWorldViewOffsetX().int32 + 1024'i32
  let rightGutterW = vw - rightGutterX
  let leftGutterW = getWorldViewOffsetX().int32

  let showHints = globalSettings == nil or globalSettings.showHints
  let waveAge = game.time - game.waveStartTime
  let isBossNext = game.wavesUntilBoss == 0
  # Roguelite rooms reuse the wave machinery but have no wave number, so the
  # generic banner would flash "WAVE 1" on every room; suppress it there.
  let showWaveBanner = game.waveInProgress and game.mode != gmRoguelite and showHints

  # Comeback-bonus label. Classic: small pulsing strip top-center. Widescreen:
  # a wrapped, accent-edged card in the left gutter. Factored out so each layout
  # branch can call it at the correct point in its own draw order (classic keeps
  # its original z-order: after the boss intro, before the boss bars).
  proc drawComebackBonus() =
    if not game.comebackBonusActive:
      return
    let pulse = (sin(game.time * 2.5) * 0.15 + 0.85).float32
    let alpha = uint8(clamp(pulse * 230.0, 0.0, 255.0))
    let cbLabel = t(tkComebackBonusActive) & " (" & t(tkComebackBonusUntil) & " " & $game.comebackEndWave & ")"
    let cbFontSize: int32 = 13
    if hudLayout == hlWidescreen:
      # Left-gutter wrapped card (below the border HUD, above the bottom hints).
      let cardW: int32 = min(leftGutterW - 8, 163'i32)
      let cardX: int32 = 4
      let cardY: int32 = 560
      let cbLines = wrapTextLines(cbLabel, cardW - 8, cbFontSize)
      let cardH: int32 = 6 + cbLines.len.int32 * (cbFontSize + 3)
      drawRectangle(cardX, cardY, cardW, cardH, Color(r: 8, g: 18, b: 12, a: uint8(clamp(pulse * 170.0, 0.0, 255.0))))
      drawRectangle(cardX, cardY, 2, cardH, Color(r: 80, g: 220, b: 100, a: alpha))
      var cbTy = cardY + 3
      for ln in cbLines:
        drawText(ln, cardX + 4, cbTy, cbFontSize, Color(r: 80, g: 220, b: 100, a: alpha))
        cbTy += cbFontSize + 3
    else:
      let cbW = measureText(cbLabel, cbFontSize)
      let cbX = vw div 2 - cbW div 2
      let cbY: int32 = 6
      drawRectangle(cbX - 6, cbY - 2, cbW + 12, cbFontSize + 6, Color(r: 0, g: 0, b: 0, a: uint8(clamp(pulse * 140.0, 0.0, 255.0))))
      drawText(cbLabel, cbX, cbY, cbFontSize, Color(r: 80, g: 220, b: 100, a: alpha))

  if hudLayout == hlWidescreen:
    # ---- WIDESCREEN RIGHT-GUTTER COLUMN (top-to-bottom via a running cursor) --
    # Top stack (dynamic): survival timer card owns the very top; boss bars flow
    # beneath it; transient cards (wave banner / celebration / boss intro) flow
    # beneath the boss bars but are capped into a safe band. Bottom stack (fixed):
    # combo card then the legendary strip are bottom-anchored so the persistent
    # cards can never collide with the dynamic top stack.
    # Bottom stack is fixed first so the boss band knows how much room it has.
    const legendaryReserve: int32 = 192   # legendary strip max height + margin
    const comboCardH: int32 = 70
    const transientBand: int32 = 150      # room reserved for the tallest transient
    let comboCardY = vh - legendaryReserve - comboCardH - 6'i32
    # Boss cards must all fit above this line so transients (and thus the combo
    # card below them) can never be overlapped, even with 3 bosses.
    let bossBandBottom = comboCardY - transientBand

    var rgY: int32 = if isTimeSurvivalMode(game.mode): SurvivalHudBottomY + 6'i32 else: 10'i32
    if game.bossWaveManager.isBossActive() or isSandboxMode(game.mode):
      # Count active bosses (<=3) so each vertical card can be sized to fit.
      var bossCount = 0
      for enemy in game.enemies:
        if enemy.isBoss and enemy.entranceTimer <= 0:
          inc bossCount
          if bossCount >= 3: break
      if bossCount > 0:
        const cardGap: int32 = 6
        let avail = max(bossCount.int32 * 74'i32, bossBandBottom - rgY)
        let perCard = clamp((avail - (bossCount.int32 - 1) * cardGap) div bossCount.int32,
                            72'i32, 190'i32)
        var drawn = 0
        for enemy in game.enemies:
          if enemy.isBoss and enemy.entranceTimer <= 0:
            rgY = drawBossPhaseHud(game, enemy, rgY, alignRight = true, slotH = perCard)
            inc drawn
            if drawn >= 3: break

    # Transient cards never start below the boss band, so even the tallest of
    # them (the multi-line wave-celebration card, ~135px) clears the combo card.
    var tY = min(rgY, bossBandBottom)
    if showWaveBanner:
      tY = drawWaveStartBannerGutter(game.currentWave, waveAge,
                                     rightGutterX, rightGutterW, tY, isBossNext)
    # Boss kills keep the classic fullscreen celebration even in widescreen (drawn
    # over the 1024-wide world column, so it reads exactly like 4:3); only ordinary
    # wave clears are demoted to the compact gutter card.
    if game.dopamine.waveCelebration.active and
       isBossWave(game.dopamine.waveCelebration.waveNumber):
      drawWaveCelebration(game.dopamine.waveCelebration, 1024'i32, vh,
                          getWorldViewOffsetX().int32)
    else:
      tY = drawWaveCelebrationGutter(game.dopamine.waveCelebration, rightGutterX, rightGutterW, tY)
    tY = drawBossIntroductionGutter(game.dopamine.bossIntro, rightGutterX, rightGutterW, tY)

    if showHints:
      drawComboGutterCard(game.dopamine.comboSystem, rightGutterX, rightGutterW,
                          comboCardY, game.dopamine.currentTime)

    if isTimeSurvivalMode(game.mode):
      drawSurvivalHUD(game, vw, vh, alignRight = true)

    if globalSettings != nil and globalSettings.showDebugStats:
      drawDebugPanel(game, vw, 2, anchorLeftDefault = true)

    drawLegendaryPowerUpsPanel(game, vw, vh, alignRightGutter = true)
    drawComebackBonus()
  else:
    # ---- CLASSIC HUD (unchanged) ----
    if showHints:
      drawCombo(game.dopamine.comboSystem, vw, vh, game.dopamine.currentTime)
    if showWaveBanner:
      drawWaveStartBanner(game.currentWave, waveAge, vw, vh, isBossNext)
    drawWaveCelebration(game.dopamine.waveCelebration, vw, vh)
    drawBossIntroduction(game.dopamine.bossIntro, vw, vh)
    drawComebackBonus()
    if game.bossWaveManager.isBossActive() or isSandboxMode(game.mode):
      var nextBossBarY = if isTimeSurvivalMode(game.mode): SurvivalHudBottomY + 6'i32
                         else: 10'i32
      var bossBarCount = 0
      for enemy in game.enemies:
        if enemy.isBoss and enemy.entranceTimer <= 0:
          nextBossBarY = drawBossPhaseHud(game, enemy, nextBossBarY, alignRight = false)
          bossBarCount += 1
          if bossBarCount >= 3:
            break
    if isTimeSurvivalMode(game.mode):
      drawSurvivalHUD(game, vw, vh, alignRight = false)
    if globalSettings != nil and globalSettings.showDebugStats:
      drawDebugPanel(game, vw, 2, anchorLeftDefault = false)
    drawLegendaryPowerUpsPanel(game, vw, vh, alignRightGutter = false)

  # Instructions only for non-legendary keys, hidden when the shop overlay is active
  if game.state != gsShop:
    let instrText = if game.wallPlacementMode and game.player.walls > 0:
      t(tkGameWallPlace) & "  (" & $game.player.walls & " " & t(tkGameWallPlaceRemaining) & ")"
    else:
      t(tkGameInstructionsWall)
    let instrColor = if game.wallPlacementMode and game.player.walls > 0:
      Color(r: 180, g: 230, b: 180, a: 255)
    else:
      LightGray
    if hudLayout == hlWidescreen:
      # A small left-gutter card (subtle bg + accent edge, wrapped text) instead
      # of bare centered text, consistent with the integrated left column.
      let cardW: int32 = min(leftGutterW - 8, 163'i32)
      let textW: int32 = cardW - 12
      let iLines = wrapTextLines(instrText, textW, 14)
      let lineH: int32 = 16
      let cardH: int32 = 8 + iLines.len.int32 * lineH
      let cardX: int32 = 4
      let cardY: int32 = vh - 6 - cardH
      let accent = if game.wallPlacementMode and game.player.walls > 0:
        Color(r: 120, g: 220, b: 140, a: 200)
      else:
        Color(r: 0, g: 220, b: 255, a: 200)
      drawRectangle(cardX, cardY, cardW, cardH, Color(r: 8, g: 15, b: 25, a: 170))
      drawRectangle(cardX, cardY, 2, cardH, accent)
      drawRectangleLines(Rectangle(x: cardX.float32, y: cardY.float32,
                                   width: cardW.float32, height: cardH.float32),
                         1, withAlpha(accent, 70))
      var iy = cardY + 5
      for ln in iLines:
        drawText(ln, cardX + 8, iy, 14, instrColor)
        iy += lineH
    else:
      if game.wallPlacementMode and game.player.walls > 0:
        let hintW = measureText(instrText, 16)
        drawText(instrText, vw div 2 - hintW div 2, vh - 25, 16, instrColor)
      else:
        drawText(instrText, vw div 2 - 100, vh - 25, 16, instrColor)

proc drawDeathSequenceOverlay*(game: Game) =
  # This overlay is drawn AFTER drawGame's world pass has closed, so it runs in
  # raw virtual (screen) space with no world translate. Fullscreen elements must
  # therefore span the virtual view (vw/vh) -- using game.screenWidth (the 1024
  # world) would leave the widescreen gutters uncovered and put the right-edge
  # vignette mid-screen. Player-centered bursts add worldOffX so they line up
  # with the player, which the world pass drew shifted into the centered world.
  let vw = getVirtualScreenWidth()
  let vh = getVirtualScreenHeight()
  let worldOffX = getWorldViewOffsetX()
  let playerX = game.player.pos.x + worldOffX
  let playerY = game.player.pos.y

  let timer = game.deathSequenceTimer
  let impactFlash = max(0.0'f32, 1.0'f32 - timer / 0.28'f32)
  if impactFlash > 0:
    drawRectangle(0, 0, vw, vh,
                  Color(r: 255, g: 242, b: 205, a: uint8(impactFlash * 145.0'f32)))
    drawCircle(Vector2(x: playerX, y: playerY),
               46.0'f32 + (1.0'f32 - impactFlash) * 130.0'f32,
               Color(r: 255, g: 190, b: 80, a: uint8(impactFlash * 155.0'f32)))

  let ringProgress = clamp(timer / 0.72'f32, 0.0'f32, 1.0'f32)
  let ringAlpha = uint8((1.0'f32 - ringProgress) * 185.0'f32)
  if ringAlpha > 0:
    for i in 0..2:
      let ringRadius = game.player.radius + 34.0'f32 + ringProgress * (145.0'f32 + i.float32 * 78.0'f32)
      drawCircleLines(playerX.int32, playerY.int32, ringRadius,
                      Color(r: 255, g: 215, b: 120, a: uint8(ringAlpha.int div (i + 1))))

  let slowPulseAlpha = uint8(max(0.0'f32, (1.0'f32 - timer / DEATH_SLOW_DURATION)) * 110.0'f32)
  if slowPulseAlpha > 0:
    let ringRadius = game.player.radius + 28.0'f32 + timer * 68.0'f32
    drawCircleLines(playerX.int32, playerY.int32, ringRadius,
                    Color(r: 255, g: 65, b: 65, a: slowPulseAlpha))
    drawCircle(Vector2(x: playerX, y: playerY), game.player.radius + 5.0'f32,
               Color(r: 255, g: 35, b: 35, a: uint8(slowPulseAlpha div 3)))

  let vignetteAlpha = uint8(min(120.0'f32, 55.0'f32 + game.deathSequenceFadeAlpha * 65.0'f32))
  let edgeW: int32 = 190
  drawRectangleGradientH(0, 0, edgeW, vh,
    Color(r: 125, g: 0, b: 0, a: vignetteAlpha), Color(r: 0, g: 0, b: 0, a: 0))
  drawRectangleGradientH(vw - edgeW, 0, edgeW, vh,
    Color(r: 0, g: 0, b: 0, a: 0), Color(r: 125, g: 0, b: 0, a: vignetteAlpha))
  drawRectangleGradientV(0, 0, vw, edgeW,
    Color(r: 125, g: 0, b: 0, a: vignetteAlpha), Color(r: 0, g: 0, b: 0, a: 0))
  drawRectangleGradientV(0, vh - edgeW, vw, edgeW,
    Color(r: 0, g: 0, b: 0, a: 0), Color(r: 125, g: 0, b: 0, a: vignetteAlpha))

  if game.deathSequenceFadeAlpha > 0:
    drawRectangle(0, 0, vw, vh,
                  Color(r: 0, g: 0, b: 0, a: uint8(game.deathSequenceFadeAlpha * 255.0'f32)))

proc drawGameOver*(game: Game) =
  # Use the new OS-style system crash screen. A wave-mode block checkpoint that
  # survived death adds a leading "Continue (Wave N)" option.
  let showContinue = game.mode == gmWaveBased and hasBlockCheckpoint()
  drawSystemCrash(game, game.selectedGameOverButton, showContinue, blockCheckpointWave())

proc drawVictory*(game: Game) =
  # OS-style "system secured" congratulations screen (wave-60 final boss cleared)
  drawSystemSecured(game, game.selectedVictoryButton)
