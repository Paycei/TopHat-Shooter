import raylib, rlgl, random, math, strutils, os, std/deques
import types, settings, game, player, wall, coin, bullet_skins, bullet_shapes, shapes, particle_pool, particle_skins, powerup, sound, cheat, statistics, run_statistics, save_system, sandbox, skins, desktop_bg_skins, cube_skins, boss_definitions, localization, gamemode_definitions, render_context, roguelite, dungeon, advancement, pvp_game, discord_helpers, discord_presence, discord_config, network/network, game3d/game_3d, ui/os_shop, ui/os_splash, ui/os_desktop, ui/os_window, ui/os_hud, ui/os_task_manager, ui/os_roguelite, ui/stats_window, ui/lore_cinematic, ui/language_select, ui/pvp_window, ui/loading_screen, ui/window_manager

# Global quit-confirmation dialog

type ConfirmDialogContext = enum
  cdcQuitToDesktop,  # Close the whole application
  cdcQuitToMenu      # Return to main menu

var
  globalConfirmActive      = false
  globalConfirmContext     = cdcQuitToMenu
  globalConfirmFrameGuard  = 0.0'f32  # Prevents Q from instantly confirming on dialog open
  globalConfirmMouseGuard  = 0.0'f32  # 2-second cooldown before mouse/button click is accepted

proc showGlobalConfirm(ctx: ConfirmDialogContext) =
  globalConfirmActive     = true
  globalConfirmContext    = ctx
  globalConfirmFrameGuard = 0.15'f32  # ~9 frames at 60 fps absorbs the key that opened the dialog
  globalConfirmMouseGuard = 2.0'f32   # 2-second anti-accident window before mouse confirm works

proc isOverRect(mp: Vector2, x, y, w, h: int32): bool =
  mp.x >= x.float32 and mp.x <= (x + w).float32 and
  mp.y >= y.float32 and mp.y <= (y + h).float32

proc drawGlobalConfirmDialog(sw, sh: int32): int =
  ## Returns 0 = still open, 1 = confirmed (yes), -1 = cancelled (no).
  if not globalConfirmActive: return 0

  let mp = getVirtualMousePosition()
  const DW: int32 = 460; const DH: int32 = 210
  const BW: int32 = 170; const BH: int32 = 42
  let dx = (sw - DW) div 2; let dy = (sh - DH) div 2

  drawRectangle(0, 0, sw, sh, Color(r: 0, g: 0, b: 0, a: 160))
  drawRectangle((dx+7).int32, (dy+7).int32, DW, DH, Color(r: 0, g: 0, b: 0, a: 140))
  drawRectangle(dx, dy, DW, DH, Color(r: 18, g: 22, b: 32, a: 255))
  drawRectangleLines(Rectangle(x: dx.float32, y: dy.float32, width: DW.float32, height: DH.float32),
                     3, Color(r: 255, g: 80, b: 80, a: 255))

  let tbH: int32 = 36
  drawRectangle(dx, dy, DW, tbH, Color(r: 120, g: 28, b: 28, a: 255))
  let titleStr = if globalConfirmContext == cdcQuitToDesktop: t(tkConfirmQuitTitle) else: t(tkConfirmExitTitle)
  let tW = measureText(titleStr, 16)
  drawText(titleStr, dx + (DW - tW) div 2, dy + 9, 16, Color(r: 255, g: 200, b: 200, a: 255))

  let bodyStr = if globalConfirmContext == cdcQuitToDesktop: t(tkConfirmQuitBody) else: t(tkConfirmExitBody)
  let bW = measureText(bodyStr, 19)
  drawText(bodyStr, dx + (DW - bW) div 2, dy + tbH + 24, 19, White)
  let subStr = t(tkConfirmUnsaved)
  let sW = measureText(subStr, 13)
  drawText(subStr, dx + (DW - sW) div 2, dy + tbH + 54, 13, Color(r: 200, g: 150, b: 150, a: 255))

  let btnY = dy + DH - BH - 22
  let noX  = dx + (DW div 2) - BW - 12
  let yesX = dx + (DW div 2) + 12
  let noHov  = isOverRect(mp, noX,  btnY, BW, BH)
  let yesHov = isOverRect(mp, yesX, btnY, BW, BH)
  let mouseReady = globalConfirmMouseGuard <= 0.0
  let keyReady   = globalConfirmMouseGuard  <= 0.0 and globalConfirmFrameGuard <= 0.0

  drawRectangle(noX, btnY, BW, BH,
    if noHov: Color(r: 0, g: 145, b: 0, a: 255) else: Color(r: 0, g: 105, b: 0, a: 255))
  drawRectangleLines(Rectangle(x: noX.float32, y: btnY.float32, width: BW.float32, height: BH.float32),
    if noHov: 3 else: 2,
    if noHov: Color(r: 0, g: 255, b: 100, a: 255) else: Color(r: 0, g: 195, b: 55, a: 255))
  let noTxt = t(tkConfirmCancelBtn); let nTW = measureText(noTxt, 14)
  drawText(noTxt, noX + (BW - nTW) div 2, btnY + 13, 14, White)

  # YES button greyed out while mouse cooldown is active
  let yesBg = if not mouseReady: Color(r: 90, g: 90, b: 90, a: 255)
              elif yesHov:       Color(r: 158, g: 38, b: 38, a: 255)
              else:              Color(r: 118, g: 28, b: 28, a: 255)
  drawRectangle(yesX, btnY, BW, BH, yesBg)
  drawRectangleLines(Rectangle(x: yesX.float32, y: btnY.float32, width: BW.float32, height: BH.float32),
    if yesHov and mouseReady: 3 else: 2,
    if not mouseReady:        Color(r: 140, g: 140, b: 140, a: 255)
    elif yesHov:              Color(r: 255, g: 100, b: 100, a: 255)
    else:                     Color(r: 195, g: 55, b: 55, a: 255))
  # Show countdown while cooling down, normal label once ready
  let yesTxt = if not mouseReady: $(int(ceil(globalConfirmMouseGuard)))
               elif globalConfirmContext == cdcQuitToDesktop: t(tkConfirmQuitBtn)
               else: t(tkConfirmExitBtn)
  let yTW = measureText(yesTxt, 14)
  drawText(yesTxt, yesX + (BW - yTW) div 2, btnY + 13, 14, White)

  var decision = 0
  if isMouseButtonPressed(Left):
    if noHov:               decision = -1
    elif yesHov and mouseReady: decision = 1
  if isKeyPressed(Escape): decision = -1
  if isKeyPressed(Q) and keyReady: decision = 1

  if decision != 0:
    globalConfirmActive = false
  return decision

const
  screenWidth = 1024
  screenHeight = 768
  maxRenderSupersampleFactor = 2
  maxRenderSupersampleScale = maxRenderSupersampleFactor.float32
  targetFPS = 60
  MOUSE_MOVEMENT_THRESHOLD = 2.0  # Minimum pixel movement to count as "mouse moved"

# Global Discord client that persists across game sessions
var globalDiscordClient: DiscordClient = nil

# Global window manager
var globalWindowManager: WindowManager = nil

var
  renderTarget: RenderTexture2D  # Virtual screen for consistent rendering
  currentRenderTargetSupersampleScale: float32 = 0.0
  renderScale: float32 = 1.0
  renderOffsetX: float32 = 0.0
  renderOffsetY: float32 = 0.0
  currentPvPGame: PvPGameState = nil
  # Brief input lockout when the language-select screen opens, so the same click
  # that dismissed the splash can't fall through and auto-pick a language.
  languageSelectGuard: float32 = 0.0

proc rebuildRenderTarget(supersampleScale: float32) =
  let renderTargetWidth = int32(screenWidth.float32 * supersampleScale)
  let renderTargetHeight = int32(screenHeight.float32 * supersampleScale)
  renderTarget = loadRenderTexture(renderTargetWidth, renderTargetHeight)
  setTextureFilter(renderTarget.texture, Bilinear)
  currentRenderTargetSupersampleScale = supersampleScale

proc getConfiguredRenderSupersampleScale(settings: Settings): float32 =
  case settings.renderResolutionMode
  of rrmDisabled:
    1.0'f32
  of rrmEnabled:
    maxRenderSupersampleScale
  of rrmFullscreenOnly:
    if settings.fullscreen: maxRenderSupersampleScale else: 1.0'f32

proc updateRenderSupersampleState(settings: Settings) =
  let targetSupersampleScale = getConfiguredRenderSupersampleScale(settings)
  if abs(targetSupersampleScale - currentRenderTargetSupersampleScale) > 0.001'f32:
    rebuildRenderTarget(targetSupersampleScale)
  setRenderSupersampleScale(targetSupersampleScale)

proc updateRenderScale() =
  ## Calculate letterbox scaling for current window size
  let windowWidth = getScreenWidth()
  let windowHeight = getScreenHeight()

  let scaleX = windowWidth.float32 / screenWidth.float32
  let scaleY = windowHeight.float32 / screenHeight.float32

  # Use smaller scale to maintain aspect ratio
  renderScale = min(scaleX, scaleY)

  # Calculate centering offsets
  let scaledWidth = screenWidth.float32 * renderScale
  let scaledHeight = screenHeight.float32 * renderScale
  renderOffsetX = (windowWidth.float32 - scaledWidth) / 2.0
  renderOffsetY = (windowHeight.float32 - scaledHeight) / 2.0
  updateRenderInputTransform(renderScale, renderOffsetX, renderOffsetY,
                             screenWidth.int32, screenHeight.int32)

proc beginGameDrawing() =
  ## Begin drawing to the virtual render target
  beginTextureMode(renderTarget)
  clearBackground(Black)
  let activeSupersampleScale = getRenderSupersampleScale()
  pushMatrix()
  scalef(activeSupersampleScale, activeSupersampleScale, 1.0'f32)

proc endGameDrawing() =
  ## End drawing to render target and blit to screen with letterboxing
  popMatrix()
  endTextureMode()

  beginDrawing()
  clearBackground(Black)  # Black bars for letterboxing

  # Draw the scaled render texture
  let source = Rectangle(x: 0, y: 0,
                         width: renderTarget.texture.width.float32,
                         height: -renderTarget.texture.height.float32)
  let dest = Rectangle(x: renderOffsetX, y: renderOffsetY,
                       width: screenWidth.float32 * renderScale,
                       height: screenHeight.float32 * renderScale)
  drawTexture(renderTarget.texture, source, dest, Vector2(x: 0, y: 0), 0, White)

  endDrawing()

proc applyWindowMode(fullscreen: bool) =
  ## Apply borderless fullscreen or centered windowed mode at runtime.
  if fullscreen:
    setWindowState(flags(WindowUndecorated))
    let monitor = getCurrentMonitor()
    let monitorWidth = getMonitorWidth(monitor)
    let monitorHeight = getMonitorHeight(monitor)
    setWindowSize(monitorWidth, monitorHeight)
    setWindowPosition(0, 0)
  else:
    clearWindowState(flags(WindowUndecorated))
    setWindowSize(screenWidth, screenHeight)
    let monitor = getCurrentMonitor()
    let monitorWidth = getMonitorWidth(monitor)
    let monitorHeight = getMonitorHeight(monitor)
    setWindowPosition((monitorWidth - screenWidth) div 2,
                     (monitorHeight - screenHeight) div 2)
  updateRenderScale()

proc isMenuClickValid*(game: Game, settings: Settings, mousePos: Vector2f, buttonX: int32, buttonY: int32, buttonWidth: int32, buttonHeight: int32): bool =
  ## Helper function to validate mouse clicks in menus
  ## Returns true if mouse click is within button bounds and mouse support is enabled
  if not settings.mouseSupport or not game.mouseMovedRecently:
    return false
  return mousePos.x >= buttonX.float32 and mousePos.x <= (buttonX + buttonWidth).float32 and
         mousePos.y >= buttonY.float32 and mousePos.y <= (buttonY + buttonHeight).float32

proc hasMouseMoved*(game: Game): bool =
  ## Detects if mouse has actually moved (not just hovering)
  let currentPos = getVirtualMousePosition()
  let dx = abs(currentPos.x - game.lastMousePos.x)
  let dy = abs(currentPos.y - game.lastMousePos.y)
  result = (dx > MOUSE_MOVEMENT_THRESHOLD or dy > MOUSE_MOVEMENT_THRESHOLD)

proc updateMouseTracking*(game: Game) =
  ## Updates mouse position tracking and resets keyboard flag if mouse moved
  let currentPos = getVirtualMousePosition()
  if hasMouseMoved(game):
    game.mouseMovedRecently = true
    game.keyboardUsedRecently = false
  # Any mouse button press counts as "movement" for click responsiveness
  if isMouseButtonPressed(Left) or isMouseButtonPressed(Right) or isMouseButtonPressed(Middle):
    game.mouseMovedRecently = true
    game.keyboardUsedRecently = false
  game.lastMousePos = newVector2f(currentPos.x, currentPos.y)

proc markKeyboardUsed*(game: Game) =
  ## Marks that keyboard was just used, disabling mouse selection temporarily
  game.keyboardUsedRecently = true
  game.mouseMovedRecently = false

proc drawCustomCursor*(time: float32) =
  ## Draw custom crosshair cursor (only when system cursor is hidden)
  let mousePos = getVirtualMousePosition()
  let cursorPulse = sin(time * 8.0) * 2 + 8

  # Outer rotating ring
  for i in 0..<8:
    let angle = time * 4.0 + i.float32 * PI / 4.0
    let x = mousePos.x + cos(angle) * cursorPulse
    let y = mousePos.y + sin(angle) * cursorPulse
    drawCircle(Vector2(x: x, y: y), 2, Color(r: 255'u8, g: 200'u8, b: 50'u8, a: 200'u8))

  # Crosshair lines
  drawLine(Vector2(x: mousePos.x - 8, y: mousePos.y),
          Vector2(x: mousePos.x - 3, y: mousePos.y), 2, White)
  drawLine(Vector2(x: mousePos.x + 3, y: mousePos.y),
          Vector2(x: mousePos.x + 8, y: mousePos.y), 2, White)
  drawLine(Vector2(x: mousePos.x, y: mousePos.y - 8),
          Vector2(x: mousePos.x, y: mousePos.y - 3), 2, White)
  drawLine(Vector2(x: mousePos.x, y: mousePos.y + 3),
          Vector2(x: mousePos.x, y: mousePos.y + 8), 2, White)

  # Center dot
  drawCircle(Vector2(x: mousePos.x, y: mousePos.y), 2, Red)

proc isBondingGameplayState(state: GameState): bool =
  state in {gsPlaying, gsDeathSequence, gsPaused, gsShop, gsGameOver, gsCountdown,
            gsWaveCleared, gsPowerUpSelect, gsRunStats, gsPvPPlaying,
            gsRogueliteFloorSelect, gsVictory}

proc isBondingCombatState(state: GameState): bool =
  state in {gsPlaying, gsPvPPlaying}

proc isMenuOrGameState(state: GameState): bool =
  state in {gsSplash, gsLanguageSelect, gsMenu, gsPlaying, gsDeathSequence, gsPaused, gsShop, gsGameOver,
            gsCountdown, gsWaveCleared, gsPowerUpSelect, gsRunStats, gsPvPPlaying,
            gsRogueliteFloorSelect, gsVictory}

proc updateInGameMouseBonding(settings: Settings, state: GameState) =
  if settings == nil:
    releaseMouseClip()
    return

  var shouldClipToWindow = false
  let shouldBond = case settings.mouseBondingMode
    of mbmOff:
      false
    of mbmWhileShooting:
      isBondingCombatState(state) and (isMouseButtonDown(Left) or isKeyDown(Space))
    of mbmAlwaysInGame:
      shouldClipToWindow = isBondingGameplayState(state)
      shouldClipToWindow
    of mbmAlways:
      shouldClipToWindow = isMenuOrGameState(state)
      shouldClipToWindow

  if shouldClipToWindow:
    clipMouseToWindowClientArea()
  else:
    releaseMouseClip()

  if shouldBond:
    bondMouseToVirtualViewport()

proc main() =
  randomize()

  let settings = initSettings()

  # Set up window with appropriate flags based on saved settings
  if settings.fullscreen:
    setConfigFlags(flags(WindowUndecorated, WindowResizable))
  else:
    setConfigFlags(flags(WindowResizable))

  initWindow(screenWidth, screenHeight, "TopHat-ShooterOS: v5.5 Edition")
  setTargetFPS(targetFPS)
  setExitKey(Null)
  hideCursor()  # Hide default cursor for custom cursor

  # Apply initial window mode after the window exists.
  applyWindowMode(settings.fullscreen)

  # Create render target for letterboxing
  updateRenderSupersampleState(settings)
  updateRenderScale()

  # Create loading screen
  var loadingScreen = newLoadingScreen()

  # Initialize sound system with loading screen callback
  var loadingScreenShown = false  # Only draw once we've seen partial progress
  proc updateLoadingProgress(progress: float32, message: string) =
    loadingScreen.setProgress(progress, message)

    # If the very first callback is already at 1.0, everything was cached,
    # skip drawing entirely so the loading screen never flickers on screen.
    if progress >= 1.0 and not loadingScreenShown:
      return
    loadingScreenShown = true

    # Draw loading screen
    let dt = getFrameTime()
    loadingScreen.update(dt)

    beginGameDrawing()
    loadingScreen.draw(screenWidth, screenHeight)
    endGameDrawing()

  discard initSoundSystem(updateLoadingProgress)

  # Initialize skin systems
  initializeSkins()
  initializeBulletSkins()
  initializeBulletShapes()
  initializeShapes()
  initializeParticleSkins()
  initDesktopBgSkins()
  initCubeSkins()

  let cheatMenu = initCheatMenu()

  # Apply remaining settings
  applySettings(settings)

  let stats = initStatistics()
  discard loadStatistics(stats)
  var rogueliteProfile = loadRogueliteProfile()
  if sanitizeEquippedCosmetics(settings, rogueliteProfile):
    discard saveSettings(settings)

  # Load last completed run statistics
  let loadedRunStats = loadLastRunStats()
  if not loadedRunStats.isNil:
    loadLastCompletedRun(loadedRunStats)

  var advancementProfile = loadAdvancements()
  discard syncAdvancements(advancementProfile, stats, loadedRunStats, rogueliteProfile)
  if advancementProfile.dirty:
    discard saveAdvancements(advancementProfile)

  # Retroactive grant: players who earned Escape Velocity before the orbital
  # cube cosmetic existed receive it (equipped by default) on next launch.
  if isAdvancementUnlocked(advancementProfile, CubeEscapeAdvancementId) and
     not settings.orbitalCubeUnlocked:
    settings.orbitalCubeUnlocked = true
    settings.orbitalCubeEquipped = true
    discard saveSettings(settings)

  var statsSavedThisGame = false  # Track if stats were saved for current game
  var advancementSyncTimer = 0.0'f32  # Throttle for mid-run advancement checks
  var fullscreenToggleRequested = false  # Flag to request fullscreen toggle on next frame
  var lastFullscreenToggleTime = 0.0  # Debouncing for F11 key

  # Initialize global Discord client (persists across game sessions)
  # Wrapped in try-catch to handle Discord connection failures gracefully
  try:
    globalDiscordClient = newDiscordClient(DISCORD_APP_ID)
    if not globalDiscordClient.isNil:
      discard globalDiscordClient.connect()  # Start background thread
  except:
    # Discord initialization failed - continue without Rich Presence
    globalDiscordClient = nil

  var currentGame = newGame(screenWidth, screenHeight, settings.playerSkin, settings.bulletSkin, settings.playerShape, settings.particleEffect, settings.bulletShape)
  currentGame.state = gsSplash  # Start with splash screen
  # Assign global Discord client to game
  currentGame.discordClient = globalDiscordClient

  var splashScreen = newSplashScreen()
  var loreCinematic = newLoreCinematic()
  var osDesktop = newOSDesktop()
  # Expose the running desktop instance so UI previews can match its state
  activeDesktop = osDesktop
  # Arm the cube orbital-escape easter egg unconditionally so it plays every time
  # the player spins the cube out of orbit. The advancement it grants is still
  # one-shot (unlockAdvancementDirectly is idempotent), so re-triggering is harmless.
  osDesktop.cubeEscapeArmed = true

  # Initialize window manager with all windows
  globalWindowManager = newWindowManager(screenWidth, screenHeight, settings, stats, advancementProfile, rogueliteProfile)
  # Pre-load saved nickname into pvp window and host network manager
  globalWindowManager.pvp.inputNickname = settings.pvpNickname
  globalWindowManager.pvp.networkManager.hostNickname = settings.pvpNickname

  proc setActiveRogueliteProfile(profile: RogueliteProfile) =
    rogueliteProfile = profile
    if sanitizeEquippedCosmetics(settings, profile):
      discard saveSettings(settings)
    if not globalWindowManager.isNil and not globalWindowManager.settings.isNil:
      globalWindowManager.settings.rogueliteProfile = profile
    if not globalWindowManager.isNil and not globalWindowManager.advancements.isNil:
      globalWindowManager.advancements.rogueliteProfile = profile
    if not globalWindowManager.isNil and not globalWindowManager.shop.isNil:
      globalWindowManager.shop.rogueliteProfile = profile
      globalWindowManager.shop.selectedPlayerSkin = SkinType(settings.playerSkin)
      globalWindowManager.shop.selectedBulletSkin = BulletSkinType(settings.bulletSkin)
      globalWindowManager.shop.selectedShape = ShapeType(settings.playerShape)
      globalWindowManager.shop.selectedParticle = ParticleSkinType(settings.particleEffect)
      globalWindowManager.shop.selectedBulletShape = BulletShapeType(settings.bulletShape)

  proc clampedRogueliteHeatSelection(selectedHeat: int, profile: RogueliteProfile): int =
    let maxHeat = if profile.isNil: RogueliteMinHeat else: profile.highestHeat
    clamp(selectedHeat, RogueliteMinHeat, maxHeat)

  proc defaultRogueliteHeatSelection(profile: RogueliteProfile): int =
    clampedRogueliteHeatSelection(RogueliteMinHeat, profile)

  proc refreshAdvancementProfile() =
    discard loadStatistics(stats)
    let freshRunStats = loadLastRunStats()
    if not freshRunStats.isNil:
      loadLastCompletedRun(freshRunStats)
    setActiveRogueliteProfile(loadRogueliteProfile())
    discard syncAdvancements(advancementProfile, stats, getLastRunStats(), rogueliteProfile)
    if advancementProfile.dirty:
      discard saveAdvancements(advancementProfile)
    if not globalWindowManager.isNil and not globalWindowManager.advancements.isNil:
      globalWindowManager.advancements.profile = advancementProfile

  proc persistRunResults(game: Game) =
    ## Finalize and save an ended run: last-run snapshot, lifetime statistics and
    ## advancement sync. Idempotent via statsSavedThisGame so it is safe to call
    ## from both the game-over and victory "return to menu" paths.
    if hasValidRunStats():
      finalizeRunTracking(game)
      saveLastCompletedRun()  # Save to memory
      if not currentRunStats.isNil:
        discard saveLastRunStats(currentRunStats)  # Save to disk

    if game.mode == gmRoguelite and game.rogueliteRun != nil:
      discard commitRogueliteRunProgress(game, true)
      setActiveRogueliteProfile(game.rogueliteProfile)

    # Save lifetime statistics only once per run
    if not statsSavedThisGame and not game.cheatsUsed:
      let bossesKilled = if not currentRunStats.isNil:
        currentRunStats.combat.bossKills
      else:
        game.bossCount

      let scoreReached =
        if game.mode == gmRoguelite and game.rogueliteRun != nil:
          game.rogueliteRun.totalRoomsCleared
        elif game.mode == gmTimeSurvival:
          0  # time mode tracks longestSurvivalTime internally; wave count is meaningless
        else:
          game.currentWave

      let coinsForStats = if not currentRunStats.isNil:
        currentRunStats.resources.coinsEarned
      else:
        game.player.coins

      updateStatsForMode(stats, game.mode, scoreReached, game.time,
                         game.player.kills, coinsForStats, bossesKilled)

      var saveSuccess = false
      var retries = 0
      const MAX_RETRIES = 3
      while not saveSuccess and retries < MAX_RETRIES:
        saveSuccess = saveStatistics(stats)
        if not saveSuccess:
          retries += 1
          echo "Warning: Save attempt ", retries, " failed"
          if retries < MAX_RETRIES:
            let backoffTime = 0.1 * pow(2.0, float(retries - 1))
            sleep(int(backoffTime * 1000.0))

      if saveSuccess:
        statsSavedThisGame = true
        let unlockedAdvancements = syncAdvancements(advancementProfile, stats, currentRunStats, rogueliteProfile)
        if not globalWindowManager.isNil and not globalWindowManager.advancements.isNil:
          globalWindowManager.advancements.profile = advancementProfile
        if advancementProfile.dirty:
          discard saveAdvancements(advancementProfile)
        if unlockedAdvancements.len > 0:
          echo "[Advancements] Unlocked ", unlockedAdvancements.len, " advancement(s)"
      else:
        echo "ERROR: Failed to save statistics after ", MAX_RETRIES, " attempts"

  proc openRunStatsWindow() =
    ## Route the post-run "View Stats" action into the desktop stats window,
    ## opened on the Last Run tab. The victory path arrives here before
    ## persistRunResults has finalized the run, so refresh the derived metrics
    ## and the last-run snapshot from the live run first.
    if hasValidRunStats():
      calculateDerivedMetrics()
      saveLastCompletedRun()
    globalWindowManager.openWindow(widStats)
    globalWindowManager.stats.currentTab = stLastRun

  # Track pending game mode launch during loading animation
  var pendingGameMode = -1  # -1 = none, 0 = Wave-Based, 1 = Time Survival, 6 = Sandbox, 9 = Roguelite
  var windowCloseRequested = false  # True once the OS close button is clicked

  while not windowCloseRequested:
    # Re-arm windowShouldClose each iteration; show confirm instead of quitting directly
    if windowShouldClose():
      let isInGame = currentGame.state in {gsPlaying, gsPaused, gsShop, gsCountdown,
                                           gsWaveCleared, gsPowerUpSelect, gsDeathSequence,
                                           gsRogueliteFloorSelect, gsPvPPlaying, gs3DBoss}
      # Only show confirm when an active game session is running; closing the window
      # from the main menu should exit immediately with no popup.
      # Sandbox has no progress to lose, so always quit immediately from it.
      if isInGame and not isSandboxMode(currentGame.mode) and settings.exitConfirmEnabled:
        if not globalConfirmActive:
          showGlobalConfirm(cdcQuitToDesktop)
      else:
        # Splash / lore / game-over / sandbox, or confirm dialogs disabled: just quit
        windowCloseRequested = true
    # Check if fullscreen toggle was requested
    if fullscreenToggleRequested:
      fullscreenToggleRequested = false
      applyWindowMode(settings.fullscreen)
      if not saveSettings(settings):
        echo "Warning: Failed to save settings to disk"

    updateRenderSupersampleState(settings)

    let dt = getFrameTime()

    # Tick down the global confirm guards
    if globalConfirmFrameGuard > 0:
      globalConfirmFrameGuard = max(0.0'f32, globalConfirmFrameGuard - dt)
    if globalConfirmMouseGuard > 0:
      globalConfirmMouseGuard = max(0.0'f32, globalConfirmMouseGuard - dt)

    # Update render scale every frame in case window was resized
    updateRenderScale()

    # Update music stream (required for continuous playback)
    updateMusic()

    # Handle fullscreen toggle with F11 (borderless window) with debouncing
    let currentTime = getTime()
    if isKeyPressed(F11) and (currentTime - lastFullscreenToggleTime) > 0.5:
      lastFullscreenToggleTime = currentTime
      settings.fullscreen = not settings.fullscreen
      fullscreenToggleRequested = true

    # ALWAYS hide system cursor - we always use custom cursor
    hideCursor()
    updateInGameMouseBonding(settings, currentGame.state)

    case currentGame.state
    of gsSplash:
      # Update splash screen
      updateSplashScreen(splashScreen, dt)

      # Skip splash with any key or mouse button
      var anyKeyPressed = false
      if splashScreen.complete:
        # Check for any key press (scan through common keys)
        if isKeyPressed(Space) or isKeyPressed(Enter) or isKeyPressed(Escape):
          anyKeyPressed = true
        else:
          # Check A-Z by iterating integer range and casting to KeyboardKey
          for i in ord(A)..ord(Z):
            if isKeyPressed(cast[KeyboardKey](i)):
              anyKeyPressed = true
              break
          # If still none, check 0-9 (use KeyboardKey.Zero..KeyboardKey.Nine cast via ord)
          if not anyKeyPressed:
            for i in ord(KeyboardKey.Zero)..ord(KeyboardKey.Nine):
              if isKeyPressed(cast[KeyboardKey](i)):
                anyKeyPressed = true
                break
        # Also check mouse buttons
        if isMouseButtonPressed(Left) or isMouseButtonPressed(Right):
          anyKeyPressed = true

        if anyKeyPressed:
          if not settings.hasSeenIntro:
            # First run: let the player pick a language before the cinematic.
            currentGame.state = gsLanguageSelect
            languageSelectGuard = 0.18'f32
          else:
            currentGame.state = gsMenu

      beginGameDrawing()
      drawSplashScreen(splashScreen, screenWidth, screenHeight)
      endGameDrawing()

    of gsLanguageSelect:
      playMusic(mtMenu)
      currentGame.time += dt
      if languageSelectGuard > 0:
        languageSelectGuard -= dt

      let mousePos = getVirtualMousePosition()
      let rects = languageOptionRects(screenWidth.int32, screenHeight.int32)

      # Pick by clicking a card or pressing 1 / 2.
      var chosen = -1
      if languageSelectGuard <= 0:
        if isMouseButtonPressed(Left):
          for i, r in rects:
            if checkCollisionPointRec(mousePos, r):
              chosen = i
              break
        if isKeyPressed(KeyboardKey.One): chosen = LangEnglish
        elif isKeyPressed(KeyboardKey.Two): chosen = LangSpanish

      if chosen >= 0:
        let lang = if chosen == LangSpanish: Spanish else: English
        setLanguage(lang)
        settings.language = $lang
        discard saveSettings(settings)
        playSound(stMenuSelect)
        currentGame.state = gsLoreIntro

      beginGameDrawing()
      drawLanguageSelect(screenWidth.int32, screenHeight.int32, currentGame.time, mousePos)
      drawCustomCursor(currentGame.time)
      endGameDrawing()

    of gsLoreIntro:
      # Tense score under the cinematic. Hold SPACE (3s) to skip, ENTER for 2x.
      playMusic(mtBoss)
      updateLoreCinematic(loreCinematic, dt)
      if loreCinematic.complete:
        settings.hasSeenIntro = true
        discard saveSettings(settings)
        loreCinematic = newLoreCinematic()  # reset for safety
        currentGame.state = gsMenu

      beginGameDrawing()
      drawLoreCinematic(loreCinematic, screenWidth, screenHeight)
      endGameDrawing()

    of gsMenu:
      # Play menu music
      playMusic(mtMenu)

      # Update time for menu animations
      currentGame.time += dt
      updateMouseTracking(currentGame)

      # Check if loading animation just finished and launch pending game mode
      if not osDesktop.loadingActive and pendingGameMode >= 0:
        # Close all desktop windows before launching the game
        globalWindowManager.closeAllWindows()
        case pendingGameMode
        of 0:  # Wave-Based Mode
          currentGame = newGame(screenWidth, screenHeight, settings.playerSkin, settings.bulletSkin, settings.playerShape, settings.particleEffect, settings.bulletShape)
          currentGame.discordClient = globalDiscordClient
          setGameMode(currentGame, gmWaveBased)
          initializeRunTracking(currentGame)
          currentGame.state = gsPlaying
          statsSavedThisGame = false
        of 1:  # Time Survival Mode
          currentGame = newGame(screenWidth, screenHeight, settings.playerSkin, settings.bulletSkin, settings.playerShape, settings.particleEffect, settings.bulletShape)
          currentGame.discordClient = globalDiscordClient
          setGameMode(currentGame, gmTimeSurvival)
          initializeRunTracking(currentGame)
          currentGame.state = gsPlaying
          statsSavedThisGame = false
        of 6:  # Sandbox Mode
          currentGame = newGame(screenWidth, screenHeight, settings.playerSkin, settings.bulletSkin, settings.playerShape, settings.particleEffect, settings.bulletShape)
          currentGame.discordClient = globalDiscordClient
          setGameMode(currentGame, gmSandbox)
          initializeRunTracking(currentGame)
          currentGame.state = gsPlaying
          statsSavedThisGame = false
        of 9:  # Roguelite Mode, launched via the roguelite window Start button
          # Setup was already done in the roguelite window; start the run directly.
          setActiveRogueliteProfile(loadRogueliteProfile())
          currentGame.rogueliteProfile = rogueliteProfile
          let starterKits9 = [rskOperator, rskBulwark, rskArcanist]
          let selectedIdx9 = clamp(currentGame.selectedRogueliteStarter, 0, starterKits9.high)
          let kit9 = starterKits9[selectedIdx9]
          let heat9 = clampedRogueliteHeatSelection(currentGame.selectedRogueliteHeat, rogueliteProfile)
          beginRogueliteRun(currentGame, rogueliteProfile, kit9, heat9)
          initializeRunTracking(currentGame)
          generateThemeChoices(currentGame.rogueliteRun)
          currentGame.selectedRogueliteTheme = 0
          currentGame.state = gsRogueliteFloorSelect
          statsSavedThisGame = false
        else: discard
        pendingGameMode = -1  # Reset pending mode

      # Handle window and desktop input
      let mousePos = getVirtualMousePosition()

      # Play click sound for any left-click on the desktop (anywhere)
      if isMouseButtonPressed(Left) and not globalConfirmActive:
        playSound(stMenuNav, 0.6)

      # Handle window clicks and check if desktop is blocked
      # (skip when the confirm dialog is open so nothing behind it is clickable)
      if not globalConfirmActive:
        discard globalWindowManager.handleWindowClick(mousePos)
      let mouseOverWindow = globalWindowManager.isMouseOverAnyWindow(mousePos)

      # Update OS desktop (after mouseOverWindow is known, so cube drag respects windows)
      updateOSDesktop(osDesktop, dt, mouseOverWindow, screenWidth, screenHeight)

      # Cube knocked out of orbit by sustained fast spinning: grant the one-time advancement
      if osDesktop.cubeEscapeTriggered:
        osDesktop.cubeEscapeTriggered = false
        if unlockAdvancementDirectly(advancementProfile, CubeEscapeAdvancementId):
          discard saveAdvancements(advancementProfile)
          if not globalWindowManager.isNil and not globalWindowManager.advancements.isNil:
            globalWindowManager.advancements.profile = advancementProfile
          # Achievement reward: the orbital cube player cosmetic — the cube you
          # knocked out of orbit starts orbiting you. Equipped by default and
          # toggleable in the shop's SECRET tab.
          if not settings.orbitalCubeUnlocked:
            settings.orbitalCubeUnlocked = true
            settings.orbitalCubeEquipped = true
            discard saveSettings(settings)

      # Surface queued advancement unlocks (from runs or easter eggs) as OS
      # toasts, one at a time as the previous toast expires.
      if advancementProfile.recentUnlocks.len > 0 and
         osDesktop.toastTimer <= 0.0'f32 and not globalConfirmActive:
        let unlockedId = advancementProfile.recentUnlocks[0]
        advancementProfile.recentUnlocks.delete(0)
        discard saveAdvancements(advancementProfile)
        let unlockedDef = getAdvancementDefinition(unlockedId)
        if unlockedDef.id.len > 0:
          showDesktopToast(osDesktop, t(tkDesktopAdvancementUnlocked) & ": " &
                           unlockedDef.name)

      # Handle OS desktop input and get action (only if no windows are blocking and confirm is not open)
      let action = if not mouseOverWindow and not globalConfirmActive: handleDesktopInput(osDesktop, currentGame) else: -1

      # Update all windows
      let updateResult = globalWindowManager.updateAllWindows(dt, screenWidth, screenHeight, currentGame)

      # Handle fullscreen toggle from settings
      if updateResult.fullscreenToggle:
        fullscreenToggleRequested = true

      # Handle "Replay Intro" from the settings window: re-enter the lore cinematic
      if updateResult.replayIntro and not globalConfirmActive:
        loreCinematic = newLoreCinematic()
        currentGame.state = gsLoreIntro

      # Handle roguelite window Start button, show loading screen then enter game
      if updateResult.rogueliteLaunchGame and not globalConfirmActive:
        startLoadingAnimation(osDesktop, "Launching Roguelite Mode...")
        pendingGameMode = 9

      # Handle PvP game ready
      if updateResult.pvpGameReady and not globalConfirmActive:
        echo "[MAIN] PvP game starting..."

        # Build connected players list
        var connectedPlayers: seq[tuple[index: int, skinType, bulletSkinType, shapeType, particleSkinType: int, nickname: string]] = @[]
        var localPlayerIndex = 0

        if globalWindowManager.pvp.isHost:
          # Host is always player 0
          localPlayerIndex = 0
          echo "[MAIN] Starting as HOST (player 0)"

          # Add host (player 0) with their cosmetics and nickname
          connectedPlayers.add((
            index: 0,
            skinType: globalSettings.playerSkin,
            bulletSkinType: globalSettings.bulletSkin,
            shapeType: globalSettings.playerShape,
            particleSkinType: globalSettings.particleEffect,
            nickname: globalWindowManager.pvp.inputNickname
          ))

          # Add all connected clients with their nicknames
          for client in globalWindowManager.pvp.networkManager.clients:
            echo "[MAIN] Adding connected client: player ", client.playerIndex, " (", client.nickname, ")"
            connectedPlayers.add((
              index: client.playerIndex,
              skinType: client.skinType,
              bulletSkinType: client.bulletSkinType,
              shapeType: client.shapeType,
              particleSkinType: client.particleSkinType,
              nickname: client.nickname
            ))
        else:
          # Client - use the assigned player index from connection accept
          localPlayerIndex = globalWindowManager.pvp.assignedPlayerIndex
          echo "[MAIN] Starting as CLIENT (player ", localPlayerIndex, ")"

          # Client - use the connected players list from the connection accept packet
          connectedPlayers = globalWindowManager.pvp.connectedPlayers
          echo "[MAIN] Received ", connectedPlayers.len, " players in connected list"

        echo "[MAIN] Total players: ", connectedPlayers.len, ", Local index: ", localPlayerIndex

        currentPvPGame = newPvPGameState(
          screenWidth.int32,
          screenHeight.int32,
          globalWindowManager.pvp.isHost,
          connectedPlayers.len,  # Use actual number of connected players, not configured maxPlayers
          connectedPlayers,
          globalWindowManager.pvp.teamsEnabled,
          globalWindowManager.pvp.playerTeamAssignments,
          globalWindowManager.pvp.interpolationEnabled,
          globalWindowManager.pvp.pvpConfig
        )
        currentPvPGame.networkManager = globalWindowManager.pvp.networkManager
        currentPvPGame.localPlayerIndex = localPlayerIndex

        echo "[MAIN] PvP game state created successfully"

        startCountdown(currentPvPGame)
        currentGame.state = gsPvPPlaying
        globalWindowManager.closeAllWindows()

      # Handle PvP window clicks
      if not globalConfirmActive and
         globalWindowManager.pvp.window.visible and not globalWindowManager.pvp.window.minimized:
        let contentX = globalWindowManager.pvp.window.x + 2  # WINDOW_BORDER
        let contentY = globalWindowManager.pvp.window.y + 30 + 2  # TITLE_BAR_HEIGHT + WINDOW_BORDER
        let contentWidth = globalWindowManager.pvp.window.width - 4
        let contentHeight = globalWindowManager.pvp.window.height - 32

        let pvpAction = handlePvPWindowClick(globalWindowManager.pvp, contentX, contentY, contentWidth, contentHeight)
        case pvpAction
        of 1:  # Host - Go to config screen
          globalWindowManager.pvp.state = plsHostingConfig
        of 2:  # Join
          globalWindowManager.pvp.state = plsJoining
        of 3:  # Back/Cancel
          resetPvPWindow(globalWindowManager.pvp)
        of 4:  # Connect
          if globalWindowManager.pvp.inputIP.len > 0:
            var port = pvp_window.DEFAULT_PORT
            try:
              port = parseInt(globalWindowManager.pvp.inputPort)
            except ValueError:
              port = pvp_window.DEFAULT_PORT
            # Save and apply nickname before connecting
            let chosenNick = if globalWindowManager.pvp.inputNickname.len > 0:
              globalWindowManager.pvp.inputNickname else: "Player"
            settings.pvpNickname = chosenNick
            discard saveSettings(settings)
            connectToGame(globalWindowManager.pvp, globalWindowManager.pvp.inputIP, port,
                         settings.playerSkin, settings.bulletSkin,
                         settings.playerShape, settings.particleEffect,
                         chosenNick)
        of 5:  # Start Game (host only)
          # Build the final connected players list for the host
          var gameConnectedPlayers: seq[tuple[index: int, skinType, bulletSkinType, shapeType, particleSkinType: int, nickname: string]] = @[]

          # Add host (player 0) with their nickname
          let hostNickname = globalWindowManager.pvp.inputNickname
          gameConnectedPlayers.add((
            index: 0,
            skinType: globalSettings.playerSkin,
            bulletSkinType: globalSettings.bulletSkin,
            shapeType: globalSettings.playerShape,
            particleSkinType: globalSettings.particleEffect,
            nickname: hostNickname
          ))

          # Add all connected clients with their nicknames
          for client in globalWindowManager.pvp.networkManager.clients:
            gameConnectedPlayers.add((
              index: client.playerIndex,
              skinType: client.skinType,
              bulletSkinType: client.bulletSkinType,
              shapeType: client.shapeType,
              particleSkinType: client.particleSkinType,
              nickname: client.nickname
            ))

          # Send game start with the final player list and full config so clients get the right settings
          globalWindowManager.pvp.networkManager.sendGameStart(3.0, gameConnectedPlayers, globalWindowManager.pvp.pvpConfig)
          globalWindowManager.pvp.readyToStart = true
          echo "[MAIN] Host sent game start signal with ", gameConnectedPlayers.len, " players"
        of 6:  # Start Hosting
          # Save and apply host nickname
          let hostNick = if globalWindowManager.pvp.inputNickname.len > 0:
            globalWindowManager.pvp.inputNickname else: "Player"
          settings.pvpNickname = hostNick
          discard saveSettings(settings)
          globalWindowManager.pvp.networkManager.hostNickname = hostNick
          startHosting(globalWindowManager.pvp)
        else:
          discard

      # Process desktop actions (skip if confirm dialog is open)
      if action >= 0 and not globalConfirmActive:
        playSound(stMenuSelect)
        case action
        of 0:  # Play.exe - Wave-Based Mode
          startLoadingAnimation(osDesktop, "Launching Wave-Based Mode...")
          pendingGameMode = 0
        of 1:  # Survival.exe - Time Survival Mode
          startLoadingAnimation(osDesktop, "Launching Time Survival Mode...")
          pendingGameMode = 1
        of 2:  # Stats.exe - Open Statistics Window
          # Reload stats from disk before opening window
          discard loadStatistics(stats)
          let freshRunStats = loadLastRunStats()
          if not freshRunStats.isNil:
            loadLastCompletedRun(freshRunStats)
          globalWindowManager.stats.stats = stats  # Update stats reference
          globalWindowManager.openWindow(widStats)
        of 3:  # Settings.exe - Open Settings Window
          globalWindowManager.openWindow(widSettings)
        of 4:  # Shop.exe - Open Customization Shop
          globalWindowManager.openWindow(widShop)
        of 5:  # Help.txt - Open Help Window
          globalWindowManager.openWindow(widHelp)
        of 6:  # Shutdown.exe - Quit
          if settings.exitConfirmEnabled:
            showGlobalConfirm(cdcQuitToDesktop)
          else:
            windowCloseRequested = true
        of 7:  # Sandbox.exe - Sandbox Mode
          startLoadingAnimation(osDesktop, "Launching Sandbox Mode...")
          pendingGameMode = 6
        of 8:  # PvP.exe - Open PvP Window
          openWindow(globalWindowManager, widPvP)
          resetPvPWindow(globalWindowManager.pvp)
          playSound(stMenuSelect)
        of 9:  # Roguelite.exe - Roguelite Mode
          setActiveRogueliteProfile(loadRogueliteProfile())
          currentGame = newGame(screenWidth, screenHeight, settings.playerSkin, settings.bulletSkin, settings.playerShape, settings.particleEffect, settings.bulletShape)
          currentGame.discordClient = globalDiscordClient
          currentGame.rogueliteProfile = rogueliteProfile
          setGameMode(currentGame, gmRoguelite)
          currentGame.state = gsMenu
          currentGame.selectedRogueliteStarter = 0
          currentGame.selectedRogueliteHeat = defaultRogueliteHeatSelection(rogueliteProfile)
          globalWindowManager.openWindow(widRoguelite)
          statsSavedThisGame = false
        of 10: # Advncmnts.exe - Open Advancements Window
          refreshAdvancementProfile()
          globalWindowManager.openWindow(widAdvancements)
        of 11: # PATCHLOG.txt - Open Changelog Window
          globalWindowManager.openWindow(widChangelog)
        else: discard

      # Handle icon execution from help window commands
      if updateResult.iconToExecute >= 0 and not globalConfirmActive:
        globalWindowManager.help.window.visible = false
        playSound(stMenuSelect)
        case updateResult.iconToExecute
          of 0:  # Play.exe - Wave-Based Mode
            startLoadingAnimation(osDesktop, "Launching Wave-Based Mode...")
            pendingGameMode = 0
          of 1:  # Survival.exe - Time Survival Mode
            startLoadingAnimation(osDesktop, "Launching Time Survival Mode...")
            pendingGameMode = 1
          of 2:  # Stats.exe - Open Statistics Window
            discard loadStatistics(stats)
            let freshRunStats = loadLastRunStats()
            if not freshRunStats.isNil:
              loadLastCompletedRun(freshRunStats)
            globalWindowManager.stats.stats = stats
            globalWindowManager.openWindow(widStats)
          of 3:  # Settings.exe - Open Settings Window
            globalWindowManager.openWindow(widSettings)
          of 4:  # Shop.exe
            globalWindowManager.openWindow(widShop)
          of 5:  # Help.txt
            globalWindowManager.openWindow(widHelp)
          of 6:  # Shutdown.exe - Quit
            if settings.exitConfirmEnabled:
              showGlobalConfirm(cdcQuitToDesktop)
            else:
              windowCloseRequested = true
          of 7:  # Sandbox.exe
            startLoadingAnimation(osDesktop, "Launching Sandbox Mode...")
            pendingGameMode = 6
          of 8:  # PvP.exe - Open PvP Window
            openWindow(globalWindowManager, widPvP)
            resetPvPWindow(globalWindowManager.pvp)
            playSound(stMenuSelect)
          of 9:  # Roguelite.exe
            setActiveRogueliteProfile(loadRogueliteProfile())
            currentGame = newGame(screenWidth, screenHeight, settings.playerSkin, settings.bulletSkin, settings.playerShape, settings.particleEffect, settings.bulletShape)
            currentGame.discordClient = globalDiscordClient
            currentGame.rogueliteProfile = rogueliteProfile
            setGameMode(currentGame, gmRoguelite)
            currentGame.state = gsMenu
            currentGame.selectedRogueliteStarter = 0
            currentGame.selectedRogueliteHeat = defaultRogueliteHeatSelection(rogueliteProfile)
            globalWindowManager.openWindow(widRoguelite)
            statsSavedThisGame = false
          of 10: # Advncmnts.exe
            refreshAdvancementProfile()
            globalWindowManager.openWindow(widAdvancements)
          else: discard

      # Update Discord Rich Presence (throttled internally to prevent lag)
      if not currentGame.discordClient.isNil:
        try:
          runCallbacks(currentGame.discordClient)
          updateDiscordForMenu(currentGame.discordClient)
        except Exception as e:
          echo "Discord error in menu: ", e.msg
          # Cleanup and null the client to prevent further issues
          try:
            disconnect(currentGame.discordClient)
          except:
            discard
          currentGame.discordClient = nil
          globalDiscordClient = nil

      beginGameDrawing()
      drawOSDesktop(osDesktop, screenWidth, screenHeight)

      # Draw all windows using window manager
      globalWindowManager.drawAllWindows(currentGame)

      # Draw loading overlay on top of everything if active
      drawLoadingOverlay(osDesktop, screenWidth, screenHeight)

      # Draw quit-confirmation dialog if active (on top of everything)
      if globalConfirmActive:
        let confirmResult = drawGlobalConfirmDialog(screenWidth, screenHeight)
        if confirmResult == 1:
          windowCloseRequested = true  # confirmed quit to desktop
        # confirmResult == -1 means cancelled, dialog already closed

      # Draw custom cursor on menu
      drawCustomCursor(currentGame.time)

      endGameDrawing()

    of gsPlaying:
      # Dynamic music based on game state
      if currentGame.bossWaveManager.isBossActive():
        playMusic(mtBoss)
      else:
        playMusic(mtWave)

      # Update Discord Rich Presence (throttled internally to prevent lag)
      if not currentGame.discordClient.isNil and not cheatMenu.active:
        try:
          runCallbacks(currentGame.discordClient)
          updateDiscordForPlaying(currentGame.discordClient, currentGame)
        except Exception as e:
          echo "Discord error during gameplay: ", e.msg
          try:
            disconnect(currentGame.discordClient)
          except:
            discard
          currentGame.discordClient = nil
          globalDiscordClient = nil

      # Check for cheat menu activation
      checkCheatSequence(cheatMenu, currentGame, currentGame.time)

      # Update cheat menu if active (pauses game)
      if cheatMenu.active:
        updateCheatMenu(cheatMenu, currentGame)

      # Only process game input if cheat menu is not active and confirm dialog is not open
      if not cheatMenu.active and not globalConfirmActive:
        # Shop removed from gameplay - only accessible during power-up selection

        # Wall placement mode: hold E to preview range, release E to place.
        const WALL_PLACEMENT_RANGE_SP = 250.0
        let eHeld = isKeyDown(E) and currentGame.player.walls > 0
        currentGame.wallPlacementMode = eHeld

        # Release E places the wall at the current cursor position
        if isKeyReleased(E) and currentGame.player.walls > 0:
          let mousePos = getVirtualMousePosition()
          let wallPos = newVector2f(mousePos.x, mousePos.y)
          let inRange = distance(wallPos, currentGame.player.pos) <= WALL_PLACEMENT_RANGE_SP
          if inRange and isValidWallPlacement(wallPos, currentGame.player.pos, currentGame.walls,
                                              currentGame.enemies, 25):
            currentGame.walls.add(newWall(mousePos.x, mousePos.y, currentGame.player))
            currentGame.player.walls -= 1
            spawnExplosionPooled(currentGame.particlePool, mousePos.x, mousePos.y, Brown, 15)
            trackWallPlacement(currentGame, wallPos)

      # Activate ALL legendary power-ups with Q key (simultaneous activation)
      if isKeyPressed(Q) and not globalConfirmActive:
        var anyActivated = false

        # Time Warp - slow down time
        if hasPowerUp(currentGame.player, puTimeWarp) and currentGame.player.timeWarpCooldown <= 0:
          # Check if uses available for this wave
          if currentGame.player.timeWarpUsesThisWave < currentGame.player.timeWarpMaxUsesPerWave:
            let duration = 3.5
            let cooldown = 10.0  # 10 second cooldown between uses

            currentGame.player.timeWarpActive = true
            currentGame.player.timeWarpDuration = duration
            currentGame.player.timeWarpCooldown = cooldown
            currentGame.player.timeWarpUsesThisWave += 1  # Increment uses
            trackTimeWarp(currentGame, duration)
            spawnExplosionPooled(currentGame.particlePool, currentGame.player.pos.x, currentGame.player.pos.y,
                          Color(r: 138, g: 43, b: 226, a: 255), 30)
            anyActivated = true

        # Phase Shift - teleport dash (SINGLE LEVEL - scales with speed)
        if hasPowerUp(currentGame.player, puPhaseShift) and currentGame.player.phaseShiftCooldown <= 0:
          # Distance scales with player movement speed (base 140, scales up with speed)
          let baseDistance = 140.0
          let speedRatio = currentGame.player.speed / currentGame.player.baseSpeed
          let dashDistance = baseDistance * speedRatio

          let cooldown = 5.0  # 5 second cooldown
          let invulnDuration = 0.5  # 0.5 second invulnerability after dash

          # Calculate dash direction - PRIORITIZE WASD movement direction
          var dashDir = newVector2f(0, 0)
          if isKeyDown(W): dashDir.y -= 1
          if isKeyDown(S): dashDir.y += 1
          if isKeyDown(A): dashDir.x -= 1
          if isKeyDown(D): dashDir.x += 1

          # Always activate cooldown and invulnerability
          currentGame.player.phaseShiftCooldown = cooldown
          currentGame.player.phaseShiftInvulnTimer = invulnDuration

          if dashDir.length() > 0:
            # Dash in movement direction
            dashDir = dashDir.normalize()
            currentGame.player.lastPhaseShiftPos = currentGame.player.pos
            currentGame.player.pos.x += dashDir.x * dashDistance
            currentGame.player.pos.y += dashDir.y * dashDistance

            # Keep player in bounds
            currentGame.player.pos.x = max(currentGame.player.radius,
                                           min(currentGame.player.pos.x,
                                               currentGame.screenWidth.float32 - currentGame.player.radius))
            currentGame.player.pos.y = max(currentGame.player.radius,
                                           min(currentGame.player.pos.y,
                                               currentGame.screenHeight.float32 - currentGame.player.radius))

            # Record actual distance traveled (post-clamp) for stats
            let actualDashDist = distance(currentGame.player.lastPhaseShiftPos, currentGame.player.pos)
            trackPhaseShift(currentGame, actualDashDist)

            # Visual effects at start and end position
            spawnExplosionPooled(currentGame.particlePool, currentGame.player.lastPhaseShiftPos.x,
                          currentGame.player.lastPhaseShiftPos.y, SkyBlue, 25)
            spawnExplosionPooled(currentGame.particlePool, currentGame.player.pos.x,
                          currentGame.player.pos.y, SkyBlue, 25)
          else:
            # Dash in place - just visual effect (zero distance, still counts as a use)
            trackPhaseShift(currentGame, 0.0)
            spawnExplosionPooled(currentGame.particlePool, currentGame.player.pos.x,
                          currentGame.player.pos.y, SkyBlue, 30)

          anyActivated = true

        # Parry - active defense ability (SINGLE LEVEL - invincible + bounce bullets)
        if hasPowerUp(currentGame.player, puParry) and currentGame.player.parryCooldown <= 0:
          let duration = 0.5  # 0.5 second parry window
          let cooldown = 5.0  # 5 second cooldown

          currentGame.player.parryActive = true
          currentGame.player.parryDuration = duration
          currentGame.player.parryCooldown = cooldown

          spawnExplosionPooled(currentGame.particlePool, currentGame.player.pos.x, currentGame.player.pos.y,
                        Color(r: 255, g: 255, b: 255, a: 255), 35)
          anyActivated = true

        # Blood Pact - sacrifice 30% current HP to unleash an amplified blood
        # nova. Every enemy is hit for a big share of its OWN max HP (so it stays
        # devastating at any wave) plus bonus damage from the blood spent. The
        # damage is NO LONGER split across targets. Bosses resist the nova and
        # are spared while invulnerable during a phase-change transition.
        if hasPowerUp(currentGame.player, puBloodPact) and currentGame.player.bloodPactCooldown <= 0:
          if currentGame.player.hp > 1.0 and currentGame.enemies.len > 0:
            const
              BLOOD_PACT_ENEMY_FRAC = 0.25'f32   # share of a normal enemy's max HP per cast
              BLOOD_PACT_BOSS_FRAC  = 0.03'f32   # bosses only take a small share
              BLOOD_PACT_BONUS_MULT = 5.0'f32    # bonus damage per point of HP sacrificed
            let sacrifice = currentGame.player.hp * 0.3
            currentGame.player.hp = max(0.1, currentGame.player.hp - sacrifice)
            let bonus = sacrifice * BLOOD_PACT_BONUS_MULT

            for enemy in currentGame.enemies:
              if enemy.isBoss and enemy.invulnerabilityTimer > 0:
                continue  # respect phase-transition invulnerability
              let dealt = if enemy.isBoss: enemy.maxHp * BLOOD_PACT_BOSS_FRAC + bonus * 0.4
                          else: enemy.maxHp * BLOOD_PACT_ENEMY_FRAC + bonus
              enemy.hp -= dealt
              trackPowerUpDamage(currentGame, puBloodPact, dealt)
              showDamage(currentGame, enemy.pos, dealt, true, false, dtDefault)

            currentGame.player.bloodPactCooldown = 3.0
            spawnExplosionPooled(currentGame.particlePool, currentGame.player.pos.x, currentGame.player.pos.y,
                          Color(r: 220, g: 30, b: 30, a: 255), 60)
            anyActivated = true

        # Conduit - detonate all active DoTs for 3x remaining tick damage
        if hasPowerUp(currentGame.player, puConduit) and currentGame.player.conduitCooldown <= 0:
          var totalDetonated = 0.0
          for enemy in currentGame.enemies:
            var elementsToDetonate: seq[ElementType] = @[]
            for et, ae in enemy.activeEffects.pairs:
              if ae.primary.isActive and ae.primary.remainingDuration > 0:
                elementsToDetonate.add(et)
            for et in elementsToDetonate:
              var ae = enemy.activeEffects[et]
              let burstDmg = ae.primary.remainingDuration * ae.primary.damagePerSec * 3.0
              let dealt = burstDmg
              enemy.hp -= dealt
              trackPowerUpDamage(currentGame, puConduit, dealt)
              showDamage(currentGame, enemy.pos, dealt, true, false, dtFire)
              totalDetonated += dealt
              ae.primary.isActive = false
              ae.primary.remainingDuration = 0
              ae.primary.damagePerSec = 0
              ae.fallback.remainingDuration = 0
              enemy.activeEffects[et] = ae
          if totalDetonated > 0:
            currentGame.player.conduitCooldown = 15.0
            spawnExplosionPooled(currentGame.particlePool, currentGame.player.pos.x, currentGame.player.pos.y,
                          Color(r: 100, g: 200, b: 100, a: 255), 25)
            anyActivated = true

        # Aftershock - shockwave traces backward along last 2s of movement path
        if hasPowerUp(currentGame.player, puAftershock) and currentGame.player.aftershockCooldown <= 0:
          let history = currentGame.player.aftershockPosHistory
          if history.len >= 2:
            const shockwaveWidth = 50.0
            let baseDamage = currentGame.player.damage * 2.0
            const knockbackForce = 200.0
            var hitEnemyIds: seq[int] = @[]

            # Trace backward through path segments
            var segIdx = history.len - 1
            while segIdx >= 1:
              let segEnd = history[segIdx]
              let segStart = history[segIdx - 1]
              let segVec = segEnd - segStart
              let segLen = segVec.length()
              if segLen > 0.01:
                let segNorm = segVec.normalize()
                for enemy in currentGame.enemies:
                  if enemy.id notin hitEnemyIds:
                    let toEnemy = enemy.pos - segStart
                    let t = clamp(toEnemy.x * segNorm.x + toEnemy.y * segNorm.y, 0.0, segLen)
                    let closest = segStart + segNorm * t
                    let dist = distance(closest, enemy.pos)
                    if dist <= shockwaveWidth + enemy.radius:
                      hitEnemyIds.add(enemy.id)
                      let dealt = baseDamage
                      enemy.hp -= dealt
                      trackPowerUpDamage(currentGame, puAftershock, dealt)
                      showDamage(currentGame, enemy.pos, dealt, true, false, dtDefault)
                      # Knockback away from path
                      let awayFromPath = if dist > 0.1: (enemy.pos - closest).normalize()
                                         else: segNorm * -1.0
                      enemy.vel.x += awayFromPath.x * knockbackForce
                      enemy.vel.y += awayFromPath.y * knockbackForce
              segIdx -= 1

            currentGame.player.aftershockCooldown = 14.0
            currentGame.player.aftershockPosHistory.clear()
            spawnExplosionPooled(currentGame.particlePool, currentGame.player.pos.x, currentGame.player.pos.y,
                          Color(r: 100, g: 180, b: 255, a: 255), 20)
            anyActivated = true

        # Nova - freeze all player bullets for 2 seconds, release at 1.5x speed
        if hasPowerUp(currentGame.player, puNova) and currentGame.player.novaCooldown <= 0 and not currentGame.player.novaActive:
          currentGame.player.novaActive = true
          currentGame.player.novaFreezeTimer = 2.0
          currentGame.player.novaCooldown = 16.0
          # Freeze all currently-in-flight player bullets
          for bullet in currentGame.bullets:
            if bullet.fromPlayer:
              bullet.isFrozenByNova = true
          spawnExplosionPooled(currentGame.particlePool, currentGame.player.pos.x, currentGame.player.pos.y,
                        Color(r: 200, g: 200, b: 255, a: 255), 30)
          anyActivated = true

        # Play sound if any ability was activated
        if anyActivated:
          playSound(stPowerUp)

      # Pause (don't actually pause in PvP mode to avoid desync)
      # Also skip if the confirm dialog is open (it acts as a hard pause)
      if isKeyPressed(Escape) and not globalConfirmActive:
        if not isPvPMode(currentGame.mode):
          currentGame.state = gsPaused
        else:
          # In PvP, show pause menu visually but keep game running
          currentGame.state = gsPaused

      # Update game (only if cheat menu is not active and confirm dialog is not open)
      if not cheatMenu.active and not globalConfirmActive:
        if isSandboxMode(currentGame.mode):
          # Handle sandbox input
          handleSandboxInput(currentGame, screenWidth, screenHeight)
          # Update sandbox mode (god mode, freeze enemies, etc.)
          updateSandboxMode(currentGame, dt)
          # Update game normally (unless enemies are frozen)
          if not currentGame.sandboxFreezeEnemies:
            updateGame(currentGame, dt)
          else:
            # Still update player, bullets, particles, but not enemies
            updatePlayer(
              currentGame.player,
              dt,
              int32(currentGame.screenWidth),
              int32(currentGame.screenHeight),
              currentGame.walls
            )
            for bullet in currentGame.bullets:
              bullet.pos.x += bullet.vel.x * dt
              bullet.pos.y += bullet.vel.y * dt
        else:
          updateGame(currentGame, dt)

      # Mid-run advancement sync: surface unlocks instantly through the HUD
      # action log instead of waiting for the game-over stats save.
      if not cheatMenu.active and not globalConfirmActive and
         not isSandboxMode(currentGame.mode) and not currentRunStats.isNil:
        advancementSyncTimer += dt
        if advancementSyncTimer >= 2.0'f32:
          advancementSyncTimer = 0.0'f32
          let liveUnlocks = syncAdvancements(advancementProfile, stats, currentRunStats,
                                             rogueliteProfile, liveRun = true)
          if liveUnlocks.len > 0:
            for unlockedDef in liveUnlocks:
              addNotification(currentGame.osHUD,
                              t(tkDesktopAdvancementUnlocked) & ": " & unlockedDef.name,
                              ntCritical)
              # Already announced in-game; don't re-toast it on the desktop later.
              let queueIdx = advancementProfile.recentUnlocks.find(unlockedDef.id)
              if queueIdx >= 0:
                advancementProfile.recentUnlocks.delete(queueIdx)
            playSound(stPowerUp, 0.9)
            discard saveAdvancements(advancementProfile)

      beginGameDrawing()

      # Normal 2D rendering
      drawGame(currentGame)

      # Draw sandbox UI if in sandbox mode
      if isSandboxMode(currentGame.mode):
        drawSandboxSidebar(currentGame, screenWidth, screenHeight)

      # Draw cheat menu overlay if active
      drawCheatMenu(cheatMenu, currentGame, screenWidth, screenHeight)

      # Alpha banner for roguelite mode
      if currentGame.mode == gmRoguelite:
        drawAlphaBanner(currentGame)
      # Draw window-close confirmation if triggered via OS close button
      if globalConfirmActive:
        let r = drawGlobalConfirmDialog(screenWidth, screenHeight)
        if r == 1:
          windowCloseRequested = true
        # r == -1: cancelled, dialog already dismissed
      if currentGame.transitioning:
        drawRectangle(0, 0, screenWidth, screenHeight,
                     fade(Black, currentGame.fadeAlpha))
        if currentGame.fadeAlpha > 0.5:
          let text = "ENTERING 3D ARENA"
          let textWidth = measureText(text, 30)
          drawText(text, screenWidth div 2 - textWidth div 2,
                  screenHeight div 2, 30, White)

      # Draw custom cursor during gameplay (after dialogs so it appears on top)
      drawCustomCursor(currentGame.time)

      endGameDrawing()

    of gsDeathSequence:
      updateGame(currentGame, dt)

      beginGameDrawing()
      drawGame(currentGame)
      drawDeathSequenceOverlay(currentGame)
      if currentGame.mode == gmRoguelite:
        drawAlphaBanner(currentGame)
      endGameDrawing()

    of gsPaused:
      # Keep current music playing but muted or paused
      # Music continues in background during pause

      # Determine if we came from PvP mode by checking if currentPvPGame exists and is active
      let isPvP = not currentPvPGame.isNil and not currentPvPGame.gameOver

      # In PvP mode, continue updating the game to prevent desync
      # Otherwise, don't update game time when paused - prevents difficulty from increasing
      if isPvP:
        # Continue PvP game updates even during "pause"
        updatePvP(currentPvPGame, dt)
      elif isPvPMode(currentGame.mode):
        # Continue game updates even during "pause" in PvP
        updateGame(currentGame, dt)

      # Update mouse tracking so the pause menu responds to mouse input immediately
      updateMouseTracking(currentGame)
      # If mouse support is enabled, allow mouse interaction right away (no need to move first)
      if globalSettings.mouseSupport:
        currentGame.mouseMovedRecently = true

      # Handle window clicks first (before pause menu interactions)
      # Skip when either confirm dialog is open so nothing behind it is clickable
      let mousePos = getVirtualMousePosition()
      if not globalConfirmActive and not currentGame.confirmQuitPending:
        discard globalWindowManager.handleWindowClick(mousePos)
      let mouseOverWindow = globalWindowManager.isMouseOverAnyWindow(mousePos)

      # Update all windows
      let updateResult = globalWindowManager.updateAllWindows(dt, screenWidth, screenHeight, currentGame)

      # Handle fullscreen toggle from settings
      if updateResult.fullscreenToggle:
        fullscreenToggleRequested = true

      # Tick down the exit-button cooldown (prevents accidental mouse Exit click on pause entry)
      if currentGame.pauseMenuExitCooldown > 0:
        currentGame.pauseMenuExitCooldown = max(0.0'f32, currentGame.pauseMenuExitCooldown - dt)

      # Tick down the per-dialog frame guard (prevents Q-open and Q-confirm same frame)
      if currentGame.confirmQuitFrameGuard > 0:
        currentGame.confirmQuitFrameGuard = max(0.0'f32, currentGame.confirmQuitFrameGuard - dt)

      # Only handle pause menu controls if no window is blocking interaction
      # and neither confirm dialog is active
      if not mouseOverWindow and not globalConfirmActive and not currentGame.confirmQuitPending:
        # Pause menu navigation - Tab switching (Left/Right or A/D)
        if isKeyPressed(Left) or isKeyPressed(A):
          currentGame.pauseMenuTab = case currentGame.pauseMenuTab
            of tmtProcesses: tmtPerformance
            of tmtPerformance: tmtProcesses
            else: tmtProcesses
          playSound(stMenuNav)
          markKeyboardUsed(currentGame)
        elif isKeyPressed(Right) or isKeyPressed(D):
          currentGame.pauseMenuTab = case currentGame.pauseMenuTab
            of tmtProcesses: tmtPerformance
            of tmtPerformance: tmtProcesses
            else: tmtProcesses
          playSound(stMenuNav)
          markKeyboardUsed(currentGame)

        # Actions
        if isKeyPressed(Space):  # Resume
          # Return to appropriate state based on context
          if isPvP:
            currentGame.state = gsPvPPlaying
          else:
            currentGame.state = gsPlaying
          playSound(stMenuSelect)
        elif isKeyPressed(Tab):  # Open Settings
          globalWindowManager.openWindow(widSettings)
          playSound(stMenuSelect)
        elif isKeyPressed(Q):  # Quit to main menu, ask first (no cooldown gate Q is intentional)
          if isSandboxMode(currentGame.mode) or not settings.exitConfirmEnabled:
            # Sandbox has no progress to lose; or exit confirm is disabled: quit immediately
            cleanupGame(currentGame)
            currentGame = newGame(screenWidth, screenHeight, settings.playerSkin, settings.bulletSkin, settings.playerShape, settings.particleEffect, settings.bulletShape)
            currentGame.discordClient = globalDiscordClient
            currentGame.state = gsMenu
            playSound(stMenuSelect)
          elif not currentGame.confirmQuitPending:
            currentGame.confirmQuitPending = true
            currentGame.pauseMenuExitCooldown = 2.0         # countdown shown inside dialog
            currentGame.confirmQuitFrameGuard = 0.15  # prevent same-frame auto-confirm in dialog
            playSound(stMenuNav)
        elif isKeyPressed(Escape):  # ESC cancels confirm dialog, or resumes
          if currentGame.confirmQuitPending:
            currentGame.confirmQuitPending = false
            currentGame.pauseMenuExitCooldown = 2.0  # prevent immediate re-trigger
          else:
            # Check if any windows are open
            let hasOpenWindows = globalWindowManager.settings.window.visible or
                                 globalWindowManager.help.window.visible or
                                 globalWindowManager.stats.window.visible or
                                 globalWindowManager.shop.window.visible
            if not hasOpenWindows:
              # Return to appropriate state based on context
              if isPvP:
                currentGame.state = gsPvPPlaying
              else:
                currentGame.state = gsPlaying

      # Update Discord Rich Presence (throttled internally to prevent lag)
      if not currentGame.discordClient.isNil:
        try:
          runCallbacks(currentGame.discordClient)
          updateDiscordForPaused(currentGame.discordClient, currentGame)
        except Exception as e:
          echo "Discord error while paused: ", e.msg
          try:
            disconnect(currentGame.discordClient)
          except:
            discard
          currentGame.discordClient = nil
          globalDiscordClient = nil

      beginGameDrawing()

      # Draw appropriate game based on context
      if isPvP and not currentPvPGame.isNil:
        drawPvP(currentPvPGame)
      else:
        drawGame(currentGame)

      # Draw OS-style Task Manager pause menu and handle mouse interactions
      let menuResult = drawOSTaskManager(currentGame, currentGame.pauseMenuTab)

      # Handle tab changes from mouse (only if no windows are blocking and no confirm is open)
      if not mouseOverWindow and not globalConfirmActive and not currentGame.confirmQuitPending:
        if menuResult.newTab != currentGame.pauseMenuTab:
          currentGame.pauseMenuTab = menuResult.newTab
          playSound(stMenuNav)

      # Handle button clicks (only if no windows are blocking and no confirm is open)
      if not mouseOverWindow and not globalConfirmActive and not currentGame.confirmQuitPending:
        if menuResult.resumeClicked:
          # Return to appropriate state based on context
          if isPvP:
            currentGame.state = gsPvPPlaying
          else:
            currentGame.state = gsPlaying
          playSound(stMenuSelect)
        elif menuResult.settingsClicked:
          globalWindowManager.openWindow(widSettings)
          playSound(stMenuSelect)
        elif menuResult.exitClicked:
          if isSandboxMode(currentGame.mode) or not settings.exitConfirmEnabled:
            # Sandbox has no progress to lose; or exit confirm is disabled: quit immediately
            cleanupGame(currentGame)
            currentGame = newGame(screenWidth, screenHeight, settings.playerSkin, settings.bulletSkin, settings.playerShape, settings.particleEffect, settings.bulletShape)
            currentGame.discordClient = globalDiscordClient
            currentGame.state = gsMenu
            playSound(stMenuSelect)
          # Ask for confirmation before quitting to menu (opens confirm immediately)
          elif not currentGame.confirmQuitPending:
            currentGame.confirmQuitPending = true
            currentGame.pauseMenuExitCooldown = 2.0   # countdown shown inside dialog
            playSound(stMenuNav)

      # Draw all windows on top of pause menu
      globalWindowManager.drawAllWindows(currentGame)

      # Alpha banner for roguelite mode
      if currentGame.mode == gmRoguelite:
        drawAlphaBanner(currentGame)

      # Draw OS-close confirmation dialog on top of everything if triggered by close button
      # (separate from the in-game quit-to-menu confirm dialog)
      if globalConfirmActive:
        let r = drawGlobalConfirmDialog(screenWidth, screenHeight)
        if r == 1: windowCloseRequested = true

      # Draw quit-confirmation dialog on top of everything if pending
      if currentGame.confirmQuitPending:
        let confirmDlg = drawQuitConfirmDialog(currentGame)
        if confirmDlg.confirmed:
          currentGame.confirmQuitPending = false
          # Perform the actual quit-to-menu
          if isPvP and not currentPvPGame.isNil and currentPvPGame.networkManager != nil:
            if currentPvPGame.networkManager.isConnected:
              disconnect(currentPvPGame.networkManager, "Player quit to menu")
            cleanup(currentPvPGame.networkManager)
            currentPvPGame = nil
          cleanupGame(currentGame)
          currentGame = newGame(screenWidth, screenHeight, settings.playerSkin, settings.bulletSkin, settings.playerShape, settings.particleEffect, settings.bulletShape)
          currentGame.discordClient = globalDiscordClient
          currentGame.state = gsMenu
          playSound(stMenuSelect)
        elif confirmDlg.cancelled:
          currentGame.confirmQuitPending = false
          currentGame.pauseMenuExitCooldown = 2.0  # prevent immediate re-trigger

      # Draw custom cursor on top of everything (including the confirm dialog)
      if currentGame.confirmQuitPending or globalSettings.mouseSupport or globalSettings.showCursorInMenus:
        drawCustomCursor(currentGame.time)

      endGameDrawing()

    of gsRogueliteFloorSelect:
      playMusic(mtMenu)
      currentGame.time += dt
      updateMouseTracking(currentGame)

      if isKeyPressed(Left) or isKeyPressed(A):
        if not globalConfirmActive:
          currentGame.selectedRogueliteTheme = (currentGame.selectedRogueliteTheme - 1 + 3) mod 3
          markKeyboardUsed(currentGame)
      if isKeyPressed(Right) or isKeyPressed(D):
        if not globalConfirmActive:
          currentGame.selectedRogueliteTheme = (currentGame.selectedRogueliteTheme + 1) mod 3
          markKeyboardUsed(currentGame)

      proc startSelectedTheme() =
        selectFloorTheme(currentGame, currentGame.selectedRogueliteTheme)
        currentGame.state = gsCountdown
        currentGame.countdownTimer = 0.5
        playSound(stMenuSelect)

      proc closeRogueliteFloorSelect() =
        let preservedHeat = currentGame.selectedRogueliteHeat
        if currentGame.rogueliteRun != nil and
           (currentGame.rogueliteRun.totalRoomsCleared > 0 or
            currentGame.rogueliteRun.shardsEarned > 0 or
            currentGame.rogueliteRun.coresEarned > 0):
          discard commitRogueliteRunProgress(currentGame, true)
          setActiveRogueliteProfile(currentGame.rogueliteProfile)
        cleanupGame(currentGame)
        currentGame = newGame(screenWidth, screenHeight, settings.playerSkin, settings.bulletSkin, settings.playerShape, settings.particleEffect, settings.bulletShape)
        currentGame.discordClient = globalDiscordClient
        setGameMode(currentGame, gmRoguelite)
        currentGame.rogueliteProfile = rogueliteProfile
        currentGame.selectedRogueliteHeat = clampedRogueliteHeatSelection(preservedHeat, rogueliteProfile)
        # Open the roguelite setup as a desktop window
        globalWindowManager.openWindow(widRoguelite)
        currentGame.state = gsMenu
        statsSavedThisGame = false

      if isKeyPressed(Enter) or isKeyPressed(E):
        if not globalConfirmActive: startSelectedTheme()
      if isKeyPressed(Q):
        if not globalConfirmActive: closeRogueliteFloorSelect()

      if isMouseButtonPressed(Left) and not globalConfirmActive:
        let mousePos = getVirtualMousePosition()
        const PanelW = 920
        const PanelH = 620
        const CardW = 260
        const CardH = 250
        const CardGap = 28
        let panelX = (screenWidth - PanelW) div 2
        let panelY = (screenHeight - PanelH) div 2
        let startX = panelX + 45
        let cardY = panelY + 185
        let closeRect = rogueliteCloseButtonRect(screenWidth.int32, screenHeight.int32)
        if checkCollisionPointRec(mousePos, closeRect):
          closeRogueliteFloorSelect()
        else:
          for i in 0..2:
            let rect = Rectangle(x: (startX + i * (CardW + CardGap)).float32,
                                 y: cardY.float32,
                                 width: CardW.float32,
                                 height: CardH.float32)
            if checkCollisionPointRec(mousePos, rect):
              currentGame.selectedRogueliteTheme = i
              startSelectedTheme()
              break

      beginGameDrawing()
      drawRogueliteFloorSelect(currentGame)

      # Draw quit-confirmation dialog on top of everything if triggered by OS close button
      if globalConfirmActive:
        let r = drawGlobalConfirmDialog(screenWidth, screenHeight)
        if r == 1: windowCloseRequested = true

      drawCustomCursor(currentGame.time)
      endGameDrawing()

    of gsShop:
      # Play power-up music in shop
      playMusic(mtPowerUp)

      # Update mouse tracking
      updateMouseTracking(currentGame)

      if not globalConfirmActive:
        # Navigate shop with keyboard
        if isKeyPressed(Down) or isKeyPressed(S):
          currentGame.selectedShopItem = (currentGame.selectedShopItem + 1) mod 6
          markKeyboardUsed(currentGame)
        if isKeyPressed(Up) or isKeyPressed(W):
          currentGame.selectedShopItem = (currentGame.selectedShopItem - 1 + 6) mod 6
          markKeyboardUsed(currentGame)

        # Scroll the sidebar upgrade list with PageDown/PageUp or [/]
        if isKeyPressed(PageDown) or isKeyPressed(RightBracket):
          currentGame.shopSidebarScroll += 40
          markKeyboardUsed(currentGame)
        if isKeyPressed(PageUp) or isKeyPressed(LeftBracket):
          currentGame.shopSidebarScroll = max(0'i32, currentGame.shopSidebarScroll - 40)
          markKeyboardUsed(currentGame)

        # Mouse click handling for shop items
        if isMouseButtonPressed(Left):
          let mousePos = getVirtualMousePosition()

          # Shop dimensions from shop.nim
          const SHOP_WIDTH = 950
          const SHOP_HEIGHT = 600
          const TITLE_BAR_HEIGHT = 45
          const SIDEBAR_WIDTH = 280
          const ITEM_HEIGHT = 60
          const ITEM_SPACING = 6

          let windowX = (currentGame.screenWidth - SHOP_WIDTH) div 2
          let windowY = (currentGame.screenHeight - SHOP_HEIGHT) div 2

          # Check close button click (X button in title bar)
          let closeButtonSize = 28
          let closeButtonX = windowX + SHOP_WIDTH - closeButtonSize - 10
          let closeButtonY = windowY + (TITLE_BAR_HEIGHT - closeButtonSize) div 2
          let closeButtonRect = Rectangle(x: closeButtonX.float32, y: closeButtonY.float32,
                                          width: closeButtonSize.float32, height: closeButtonSize.float32)

          if checkCollisionPointRec(mousePos, closeButtonRect):
            # Close shop and continue to next wave
            currentGame.cameFromPowerUpSelect = false
            if currentGame.mode == gmRoguelite:
              # In the dungeon the shop is a room: just step back into it.
              currentGame.state = gsPlaying
            else:
              currentGame.state = gsCountdown
              currentGame.countdownTimer = 0.5
          else:
            let sidebarX = windowX + 10
            let sidebarY = windowY + TITLE_BAR_HEIGHT + 10
            let shopX = sidebarX + SIDEBAR_WIDTH + 15
            let shopY = sidebarY + 10
            let itemsStartY = shopY + 35
            let shopWidth = SHOP_WIDTH - SIDEBAR_WIDTH - 40

            # Check shop item clicks
            var clickedItem = -1
            for i in 0..5:
              let itemY = itemsStartY + i * (ITEM_HEIGHT + ITEM_SPACING)
              let itemRect = Rectangle(x: shopX.float32, y: itemY.float32,
                                      width: shopWidth.float32, height: ITEM_HEIGHT.float32)

              if checkCollisionPointRec(mousePos, itemRect):
                clickedItem = i
                break

            # Check big buy button click
            let buyButtonWidth = 220
            let buyButtonHeight = 38
            let bottomY = windowY + SHOP_HEIGHT - 65
            let buyButtonX = windowX + SHOP_WIDTH - buyButtonWidth - 20
            let buyButtonY = bottomY + 12
            let buyButtonRect = Rectangle(x: buyButtonX.float32, y: buyButtonY.float32,
                                          width: buyButtonWidth.float32, height: buyButtonHeight.float32)

            if clickedItem >= 0:
              # Clicked on an item - select and buy it
              currentGame.selectedShopItem = clickedItem
              buyShopItem(currentGame, clickedItem)
            elif checkCollisionPointRec(mousePos, buyButtonRect):
              # Clicked the buy button - buy selected item
              buyShopItem(currentGame, currentGame.selectedShopItem)

        # Buy item with keyboard
        if isKeyPressed(Enter) or isKeyPressed(E):
          buyShopItem(currentGame, currentGame.selectedShopItem)

        # Close shop - ESC is intentionally not bound here; only Q or the in-window X button may close it.
        if isKeyPressed(Q) and not globalConfirmActive:
          currentGame.cameFromPowerUpSelect = false
          if currentGame.mode == gmRoguelite:
            # In the dungeon the shop is a room: just step back into it.
            currentGame.state = gsPlaying
          else:
            currentGame.state = gsCountdown
            currentGame.countdownTimer = 0.5

      beginGameDrawing()
      drawGame(currentGame)
      drawShop(currentGame)
      if currentGame.mode == gmRoguelite:
        drawAlphaBanner(currentGame)

      # Draw quit-confirmation dialog on top of everything if triggered by OS close button
      if globalConfirmActive:
        let r = drawGlobalConfirmDialog(screenWidth, screenHeight)
        if r == 1: windowCloseRequested = true

      # Draw custom cursor
      drawCustomCursor(currentGame.time)

      endGameDrawing()

    of gsCountdown:
      # Keep wave music during countdown
      playMusic(mtWave)

      # Countdown timer
      currentGame.countdownTimer -= dt

      if currentGame.countdownTimer <= 0:
        currentGame.state = gsPlaying

      beginGameDrawing()
      drawGame(currentGame)

      # Draw stylish countdown overlay
      let countdownValue = max(currentGame.countdownTimer, 0.0)
      let pulse = 1.0 + sin(currentGame.countdownTimer * 10) * 0.1
      let alpha = uint8(200.0 * (countdownValue + 0.1))

      # Dark overlay that fades out
      drawRectangle(0, 0, screenWidth, screenHeight,
                   Color(r: 0, g: 0, b: 0, a: alpha))

      # Countdown text with scale pulse
      let textSize = (120 * pulse).int32
      # Always show numeric countdown
      let countdownText = formatFloat(countdownValue, ffDecimal, 1)
      let textWidth = measureText(countdownText, textSize)

      # Glow effect - draw multiple times with offset
      for i in 1..3:
        let glowAlpha = uint8(50.0 * (4 - i).float)
        let glowSize = textSize + i * 4
        let glowWidth = measureText(countdownText, glowSize.int32)
        drawText(countdownText,
                (screenWidth div 2 - glowWidth div 2).int32,
                (screenHeight div 2 - glowSize div 2).int32,
                glowSize.int32,
                Color(r: 255, g: 200, b: 0, a: glowAlpha))

      # Main text
      let textColor = if countdownValue > 0.5:
        Color(r: 255, g: 255, b: 100, a: 255)
      else:
        Color(r: 100, g: 255, b: 100, a: 255)

      drawText(countdownText,
              screenWidth div 2 - textWidth div 2,
              screenHeight div 2 - textSize div 2,
              textSize,
              textColor)

      # Subtitle
      let subtitle = "READY?"
      let subWidth = measureText(subtitle, 40)
      drawText(subtitle,
              screenWidth div 2 - subWidth div 2,
              screenHeight div 2 + 80,
              40,
              Color(r: 255, g: 255, b: 100, a: alpha))

      if currentGame.mode == gmRoguelite:
        drawAlphaBanner(currentGame)

      # Draw OS-close confirmation dialog on top of everything if triggered by close button
      if globalConfirmActive:
        let r = drawGlobalConfirmDialog(screenWidth, screenHeight)
        if r == 1: windowCloseRequested = true

      # Draw custom cursor
      drawCustomCursor(currentGame.time)

      endGameDrawing()

    of gsWaveCleared:
      # Keep wave music during wave cleared screen
      playMusic(mtWave)

      # Update wave cleared timer
      currentGame.waveClearedTimer -= dt

      # Continue coin collection during this phase
      updatePlayer(currentGame.player, dt, screenWidth, screenHeight, currentGame.walls)

      # Update coins and handle collection
      var i = 0
      while i < currentGame.coins.len:
        if not updateCoin(currentGame.coins[i], dt, currentGame.coins.len):
          currentGame.coins.delete(i)
          continue

        # Check if coin is in player's collection aura (auto-collect)
        if checkAuraCollision(currentGame.coins[i], currentGame.player, currentGame.player.auraRadius):
          moveCoinToPlayer(currentGame.coins[i], currentGame.player.pos, dt)

        # Magnet effect from consumable
        if currentGame.player.magnetTimer > 0:
          moveCoinToPlayer(currentGame.coins[i], currentGame.player.pos, dt)

        # Collect coin on contact
        if checkPlayerCollision(currentGame.coins[i], currentGame.player):
          # Apply Lucky Coins (Greed) multiplier and Double Coin multiplier (they stack)
          var coinValue = currentGame.coins[i].value
          if hasPowerUp(currentGame.player, puLuckyCoins):
            coinValue *= 2
          if currentGame.player.doubleCoinTimer > 0:
            coinValue *= 2
          currentGame.player.coins += coinValue
          playSound(stCoinPickup, 0.5)
          spawnExplosionPooled(currentGame.particlePool, currentGame.coins[i].pos.x, currentGame.coins[i].pos.y, Gold, 6)
          currentGame.coins.delete(i)
          continue

        i += 1

      # Update particles and remove dead ones

      # Transition to power-up selection or next wave
      # (the roguelite dungeon never enters gsWaveCleared; rooms resolve inline)
      if currentGame.waveClearedTimer <= 0:
        block waveClearedAdvance:
          let shouldOfferPowerUp = currentGame.cameFromPowerUpSelect

          if shouldOfferPowerUp and not currentGame.bossWaveManager.isBossCoinActive():
            # Determine if it's a boss wave power-up
            let isBossWave = currentGame.wavesUntilBoss <= 0

            if isBossWave:
              # Trigger boss warning with LONGER duration
              currentGame.bossSpawnTimer = 3.0  # Increased from 1.5 to 3.0 seconds
              # ALWAYS offer power-up before boss (critical moment)
              currentGame.powerUpChoices = generatePowerUpChoices(currentGame.player, false)
            else:
              # Regular wave power-up
              currentGame.powerUpChoices = generatePowerUpChoices(currentGame.player, false)

            currentGame.selectedPowerUp = 0
            initPowerUpRollAnimation(currentGame)
            initializeRerollCost(currentGame)
            currentGame.state = gsPowerUpSelect
          else:
            # No power-up, go straight to next wave
            currentGame.state = gsPlaying
            startWave(currentGame)

      beginGameDrawing()
      drawGame(currentGame)

      # Draw appropriate cleared text based on whether it was a boss wave
      let waveText = if isBossWave(currentGame.currentWave):
        "BOSS " & $getCustomBossNumber(currentGame.currentWave) & " CLEARED!"
      else:
        "WAVE CLEARED!"
      let waveTextSize = 48.int32
      let waveTextWidth = measureText(waveText, waveTextSize)

      # Simple centered text with subtle shadow
      let textX = (screenWidth div 2 - waveTextWidth div 2).int32
      let textY = 40.int32

      # Shadow
      drawText(waveText, textX + 2.int32, textY + 2.int32, waveTextSize,
              Color(r: 0, g: 0, b: 0, a: 100))

      # Main text
      drawText(waveText, textX, textY, waveTextSize,
              Color(r: 150, g: 255, b: 150, a: 255))

      if currentGame.mode == gmRoguelite:
        drawAlphaBanner(currentGame)

      # Draw OS-close confirmation dialog on top of everything if triggered by close button
      if globalConfirmActive:
        let r = drawGlobalConfirmDialog(screenWidth, screenHeight)
        if r == 1: windowCloseRequested = true

      endGameDrawing()

    of gsPowerUpSelect:
      # Play power-up selection music
      playMusic(mtPowerUp)

      # Update roll animation
      updatePowerUpRollAnimation(currentGame, dt)

      # Update mouse tracking
      updateMouseTracking(currentGame)

      proc continueAfterDraft() =
        ## Route out of the draft screen. Classic modes visit the between-wave
        ## shop; the dungeon returns to the room (or the next floor select
        ## after a floor boss).
        currentGame.cameFromPowerUpSelect = true
        if currentGame.mode == gmRoguelite and currentGame.rogueliteRun != nil:
          if currentGame.rogueliteRun.pendingFloorSelect:
            generateThemeChoices(currentGame.rogueliteRun)
            currentGame.selectedRogueliteTheme = 0
            currentGame.state = gsRogueliteFloorSelect
          else:
            currentGame.state = gsPlaying
        else:
          currentGame.state = gsShop
          currentGame.shopSidebarScroll = 0

      # Only allow input after animation completes and confirm dialog is not open
      if currentGame.canSelectPowerUp and not globalConfirmActive:
        # Navigate power-up choices with keyboard
        if isKeyPressed(Left) or isKeyPressed(A):
          currentGame.selectedPowerUp = (currentGame.selectedPowerUp - 1 + 3) mod 3
          markKeyboardUsed(currentGame)
        if isKeyPressed(Right) or isKeyPressed(D):
          currentGame.selectedPowerUp = (currentGame.selectedPowerUp + 1) mod 3
          markKeyboardUsed(currentGame)

        # Reroll power-ups with R key
        if isKeyPressed(R):
          if attemptRerollPowerUps(currentGame):
            markKeyboardUsed(currentGame)
          # If reroll failed (not enough coins), do nothing (could add sound here)

        # Mouse hover detection for card selection (only if keyboard not recently used)
        if isMouseButtonPressed(Left) or currentGame.mouseMovedRecently:
          let mousePos = getVirtualMousePosition()
          # Use actual UI dimensions from os_powerup_installer.nim
          const INSTALLER_WIDTH = 1000
          const INSTALLER_HEIGHT = 650
          const TITLE_BAR_HEIGHT = 45
          const CARD_WIDTH = 280
          const CARD_HEIGHT = 380
          const CARD_SPACING = 35

          let windowX = (currentGame.screenWidth - INSTALLER_WIDTH) div 2
          let windowY = (currentGame.screenHeight - INSTALLER_HEIGHT) div 2
          let yPos = windowY + TITLE_BAR_HEIGHT + 75
          let totalCardWidth = CARD_WIDTH * 3 + CARD_SPACING * 2
          let startX = windowX + (INSTALLER_WIDTH - totalCardWidth) div 2

          # Check which card mouse is over - only if keyboard wasn't just used
          if not currentGame.keyboardUsedRecently:
            for i in 0..2:
              let cardX = startX + i * (CARD_WIDTH + CARD_SPACING)
              let cardRect = Rectangle(x: cardX.float32, y: yPos.float32,
                                       width: CARD_WIDTH.float32, height: CARD_HEIGHT.float32)

              if checkCollisionPointRec(mousePos, cardRect):
                currentGame.selectedPowerUp = i
                break

        # Select power-up with keyboard or mouse click on card
        if isKeyPressed(Enter) or isKeyPressed(E):
          let chosenPowerUp = currentGame.powerUpChoices[currentGame.selectedPowerUp]
          installPowerUp(currentGame, chosenPowerUp)
          continueAfterDraft()

        # Mouse click to select
        if isMouseButtonPressed(Left):
          let mousePos = getVirtualMousePosition()
          const INSTALLER_WIDTH = 1000
          const INSTALLER_HEIGHT = 650
          const TITLE_BAR_HEIGHT = 45
          const CARD_WIDTH = 280
          const CARD_HEIGHT = 380
          const CARD_SPACING = 35

          let windowX = (currentGame.screenWidth - INSTALLER_WIDTH) div 2
          let windowY = (currentGame.screenHeight - INSTALLER_HEIGHT) div 2
          let yPos = windowY + TITLE_BAR_HEIGHT + 75
          let totalCardWidth = CARD_WIDTH * 3 + CARD_SPACING * 2
          let startX = windowX + (INSTALLER_WIDTH - totalCardWidth) div 2

          # Check close button click (X button in title bar)
          let closeButtonSize = 28
          let closeButtonX = windowX + INSTALLER_WIDTH - closeButtonSize - 10
          let closeButtonY = windowY + (TITLE_BAR_HEIGHT - closeButtonSize) div 2
          let closeButtonRect = Rectangle(x: closeButtonX.float32, y: closeButtonY.float32,
                                          width: closeButtonSize.float32, height: closeButtonSize.float32)

          if checkCollisionPointRec(mousePos, closeButtonRect):
            # Close installer without picking
            continueAfterDraft()
          else:
            # Check card clicks
            for i in 0..2:
              let cardX = startX + i * (CARD_WIDTH + CARD_SPACING)
              let cardRect = Rectangle(x: cardX.float32, y: yPos.float32,
                                       width: CARD_WIDTH.float32, height: CARD_HEIGHT.float32)

              if checkCollisionPointRec(mousePos, cardRect):
                currentGame.selectedPowerUp = i
                let chosenPowerUp = currentGame.powerUpChoices[currentGame.selectedPowerUp]
                installPowerUp(currentGame, chosenPowerUp)
                continueAfterDraft()
                break

            # Check reroll button click
            let rerollWidth = 220
            let rerollX = windowX + (INSTALLER_WIDTH - rerollWidth) div 2
            let bottomY = windowY + INSTALLER_HEIGHT - 120
            let buttonY = bottomY + 15
            let buttonHeight = 42

            let rerollRect = Rectangle(x: rerollX.float32, y: buttonY.float32,
                                        width: rerollWidth.float32, height: buttonHeight.float32)

            if checkCollisionPointRec(mousePos, rerollRect):
              discard attemptRerollPowerUps(currentGame)

        # ESC is intentionally not bound here; only the in-window X button may close
        # this screen without selecting a power-up.

      beginGameDrawing()
      drawPowerUpSelection(currentGame)
      if currentGame.mode == gmRoguelite:
        drawAlphaBanner(currentGame)

      # Draw quit-confirmation dialog on top of everything if triggered by OS close button
      if globalConfirmActive:
        let r = drawGlobalConfirmDialog(screenWidth, screenHeight)
        if r == 1: windowCloseRequested = true

      drawCustomCursor(currentGame.time)
      endGameDrawing()

    of gsGameOver:
      # Stop music and play game over sound once
      if not currentGame.gameOverSoundPlayed:
        stopMusic()
        playSound(stGameOver, 1.0)
        currentGame.gameOverSoundPlayed = true
        # Claim the stats-return route: a run that passed through the victory
        # screen leaves previousState = gsVictory, which would otherwise bounce
        # a dead player back onto the victory screen from View Stats.
        currentGame.previousState = gsGameOver

        # Update Discord Rich Presence to show game over state
        if not currentGame.discordClient.isNil:
          try:
            updateDiscordForGameOver(currentGame.discordClient, currentGame)
          except Exception as e:
            echo "Discord error on game over: ", e.msg
            try:
              disconnect(currentGame.discordClient)
            except:
              discard
            currentGame.discordClient = nil
            globalDiscordClient = nil

        # Finalize and persist the run (last-run snapshot, lifetime stats, advancements)
        persistRunResults(currentGame)

      # Update mouse tracking
      updateMouseTracking(currentGame)

      # Keyboard navigation - A/D/LEFT/RIGHT to change button selection
      if isKeyPressed(Left) or isKeyPressed(A):
        currentGame.selectedGameOverButton = (currentGame.selectedGameOverButton - 1 + 3) mod 3
        playSound(stMenuNav)
        markKeyboardUsed(currentGame)
      elif isKeyPressed(Right) or isKeyPressed(D):
        currentGame.selectedGameOverButton = (currentGame.selectedGameOverButton + 1) mod 3
        playSound(stMenuNav)
        markKeyboardUsed(currentGame)

      # Execute action based on selected button or direct key press
      # SPACE and R both trigger restart (button 0)
      if (isKeyPressed(Space) or isKeyPressed(R)) or
         (isKeyPressed(Enter) and currentGame.selectedGameOverButton == 0):
        # Store the current game mode before restarting
        let previousMode = currentGame.mode
        let preservedRogueliteHeat =
          if previousMode == gmRoguelite and currentGame.rogueliteRun != nil:
            currentGame.rogueliteRun.heat
          else:
            currentGame.selectedRogueliteHeat
        currentGame = newGame(screenWidth, screenHeight, settings.playerSkin, settings.bulletSkin, settings.playerShape, settings.particleEffect, settings.bulletShape)
        currentGame.discordClient = globalDiscordClient
        setGameMode(currentGame, previousMode)  # Preserve the game mode
        if previousMode == gmRoguelite:
          setActiveRogueliteProfile(loadRogueliteProfile())
          currentGame.rogueliteProfile = rogueliteProfile
          currentGame.selectedRogueliteHeat = clampedRogueliteHeatSelection(preservedRogueliteHeat, rogueliteProfile)
          globalWindowManager.openWindow(widRoguelite)
          currentGame.state = gsMenu
        else:
          initializeRunTracking(currentGame)  # Start tracking
          currentGame.state = gsPlaying
        playSound(stMenuSelect)
        statsSavedThisGame = false  # Reset for new game
      # TAB or V to view stats (button 1)
      elif (isKeyPressed(Tab) or isKeyPressed(V)) or
           (isKeyPressed(Enter) and currentGame.selectedGameOverButton == 1):
        if hasValidRunStats():
          openRunStatsWindow()
          currentGame.state = gsRunStats
          playSound(stMenuSelect)
      # ESC or Q to exit (button 2)
      elif (isKeyPressed(Escape) or isKeyPressed(Q)) or
           (isKeyPressed(Enter) and currentGame.selectedGameOverButton == 2):
        cleanupGame(currentGame)  # Clean up resources before creating new game
        currentGame = newGame(screenWidth, screenHeight, settings.playerSkin, settings.bulletSkin, settings.playerShape, settings.particleEffect, settings.bulletShape)
        currentGame.discordClient = globalDiscordClient
        currentGame.state = gsMenu
        playSound(stMenuSelect)
        statsSavedThisGame = false  # Reset for new game

      # Mouse hover detection for button highlighting
      let mousePos = getVirtualMousePosition()
      const SCREEN_HEIGHT = 600
      const BUTTON_WIDTH = 220
      const BUTTON_HEIGHT = 48

      let windowY = (screenHeight - SCREEN_HEIGHT) div 2
      let buttonY = windowY + SCREEN_HEIGHT - 100
      let buttonSpacing = 40
      let totalButtonWidth = BUTTON_WIDTH * 3 + buttonSpacing * 2
      let buttonsX = (screenWidth - totalButtonWidth) div 2

      # Restart button (button 0)
      let restartRect = Rectangle(x: buttonsX.float32, y: buttonY.float32,
                                   width: BUTTON_WIDTH.float32, height: BUTTON_HEIGHT.float32)

      # View Stats button (button 1)
      let statsX = buttonsX + BUTTON_WIDTH + buttonSpacing
      let statsRect = Rectangle(x: statsX.float32, y: buttonY.float32,
                                width: BUTTON_WIDTH.float32, height: BUTTON_HEIGHT.float32)

      # Exit button (button 2)
      let exitX = statsX + BUTTON_WIDTH + buttonSpacing
      let exitRect = Rectangle(x: exitX.float32, y: buttonY.float32,
                               width: BUTTON_WIDTH.float32, height: BUTTON_HEIGHT.float32)

      # Mouse hover - update selected button
      if checkCollisionPointRec(mousePos, restartRect):
        currentGame.selectedGameOverButton = 0
      elif checkCollisionPointRec(mousePos, statsRect):
        currentGame.selectedGameOverButton = 1
      elif checkCollisionPointRec(mousePos, exitRect):
        currentGame.selectedGameOverButton = 2

      # Mouse click handling
      if isMouseButtonPressed(Left):
        if checkCollisionPointRec(mousePos, restartRect):
          # Restart game - preserve game mode
          let previousMode = currentGame.mode
          let preservedRogueliteHeat =
            if previousMode == gmRoguelite and currentGame.rogueliteRun != nil:
              currentGame.rogueliteRun.heat
            else:
              currentGame.selectedRogueliteHeat
          currentGame = newGame(screenWidth, screenHeight, settings.playerSkin, settings.bulletSkin, settings.playerShape, settings.particleEffect, settings.bulletShape)
          currentGame.discordClient = globalDiscordClient
          setGameMode(currentGame, previousMode)  # Preserve the game mode
          if previousMode == gmRoguelite:
            setActiveRogueliteProfile(loadRogueliteProfile())
            currentGame.rogueliteProfile = rogueliteProfile
            currentGame.selectedRogueliteHeat = clampedRogueliteHeatSelection(preservedRogueliteHeat, rogueliteProfile)
            globalWindowManager.openWindow(widRoguelite)
            currentGame.state = gsMenu
          else:
            initializeRunTracking(currentGame)
            currentGame.state = gsPlaying
          playSound(stMenuSelect)
          statsSavedThisGame = false
        elif checkCollisionPointRec(mousePos, statsRect):
          # View stats
          if hasValidRunStats():
            openRunStatsWindow()
            currentGame.state = gsRunStats
            playSound(stMenuSelect)
        elif checkCollisionPointRec(mousePos, exitRect):
          # Return to menu
          cleanupGame(currentGame)
          currentGame = newGame(screenWidth, screenHeight, settings.playerSkin, settings.bulletSkin, settings.playerShape, settings.particleEffect, settings.bulletShape)
          currentGame.discordClient = globalDiscordClient
          currentGame.state = gsMenu
          playSound(stMenuSelect)
          statsSavedThisGame = false

      beginGameDrawing()
      drawGameOver(currentGame)

      # Draw custom cursor on game over screen
      drawCustomCursor(currentGame.time)

      endGameDrawing()

    of gsRunStats:
      # Display detailed run statistics in the same desktop stats window as the
      # main menu (opened on the Last Run tab by openRunStatsWindow).

      # Update time for animations
      currentGame.time += dt

      let statsWin = globalWindowManager.stats

      # Drive the window like the desktop does: reset the per-frame click flag,
      # then let it handle dragging, tab clicks and its close button.
      statsWin.window.handledClickThisFrame = false
      let statsWindowClosed = updateStatsWindow(statsWin, dt, screenWidth,
                                                screenHeight, [statsWin.window])

      # Return to the screen we came from (victory or game over) with
      # Tab/Escape or the window's close button
      let statsReturnState =
        if currentGame.previousState == gsVictory: gsVictory else: gsGameOver
      if statsWindowClosed or isKeyPressed(Tab) or isKeyPressed(Escape):
        statsWin.window.visible = false
        currentGame.state = statsReturnState

      # Quick restart
      if isKeyPressed(R):
        statsWin.window.visible = false
        let previousMode = currentGame.mode
        let preservedRogueliteHeat =
          if previousMode == gmRoguelite and currentGame.rogueliteRun != nil:
            currentGame.rogueliteRun.heat
          else:
            currentGame.selectedRogueliteHeat
        currentGame = newGame(screenWidth, screenHeight, settings.playerSkin, settings.bulletSkin, settings.playerShape, settings.particleEffect, settings.bulletShape)
        currentGame.discordClient = globalDiscordClient
        setGameMode(currentGame, previousMode)
        if previousMode == gmRoguelite:
          setActiveRogueliteProfile(loadRogueliteProfile())
          currentGame.rogueliteProfile = rogueliteProfile
          currentGame.selectedRogueliteHeat = clampedRogueliteHeatSelection(preservedRogueliteHeat, rogueliteProfile)
          globalWindowManager.openWindow(widRoguelite)
          currentGame.state = gsMenu
        else:
          initializeRunTracking(currentGame)
          currentGame.state = gsPlaying
        statsSavedThisGame = false

      # Return to menu
      if isKeyPressed(Q):
        statsWin.window.visible = false
        cleanupGame(currentGame)  # Clean up resources before creating new game
        currentGame = newGame(screenWidth, screenHeight, settings.playerSkin, settings.bulletSkin, settings.playerShape, settings.particleEffect, settings.bulletShape)
        currentGame.discordClient = globalDiscordClient
        currentGame.state = gsMenu
        statsSavedThisGame = false

      beginGameDrawing()
      # Dark OS backdrop with subtle scan lines behind the floating window
      clearBackground(Color(r: 20, g: 20, b: 30, a: 255))
      for i in 0..<(screenHeight div 3):
        let lineY = i * 3 + int(currentGame.time * 50.0) mod 3
        let alpha = uint8(3 + sin(currentGame.time + i.float32) * 3.0)
        drawLine(Vector2(x: 0, y: lineY.float32),
                Vector2(x: screenWidth.float32, y: lineY.float32),
                1, Color(r: 40, g: 60, b: 80, a: alpha))

      if statsWin.window.visible:
        drawStatsWindow(statsWin, currentGame)
        # Controls hint along the bottom edge
        let footerText = t(tkStatsControlsFooter)
        let footerWidth = measureText(footerText, 14)
        drawText(footerText, (screenWidth.int32 - footerWidth) div 2, screenHeight - 26, 14,
                Color(r: 0, g: 180, b: 255, a: 255))
      elif currentGame.state == gsRunStats:
        # Fallback if no stats available (skipped on the one frame where the
        # window was just dismissed and we are about to leave this state)
        drawText(t(tkSystemNoStatistics),
                screenWidth div 2 - 150, screenHeight div 2, 24, Red)
        drawText(t(tkSystemPressESCToReturn),
                screenWidth div 2 - 120, screenHeight div 2 + 40, 18, LightGray)

      drawCustomCursor(currentGame.time)
      endGameDrawing()

    of gsVictory:
      # One-time congratulations screen shown after the wave-60 final boss.
      # Three choices: continue endlessly, view detailed stats, or return to menu.
      currentGame.time += dt
      updateMouseTracking(currentGame)

      # Keyboard navigation across the 3 buttons
      if isKeyPressed(Left) or isKeyPressed(A):
        currentGame.selectedVictoryButton = (currentGame.selectedVictoryButton - 1 + 3) mod 3
        playSound(stMenuNav)
        markKeyboardUsed(currentGame)
      elif isKeyPressed(Right) or isKeyPressed(D):
        currentGame.selectedVictoryButton = (currentGame.selectedVictoryButton + 1) mod 3
        playSound(stMenuNav)
        markKeyboardUsed(currentGame)

      # Button geometry MUST mirror drawSystemSecured exactly so click and draw align.
      const VIC_SCREEN_HEIGHT = 600
      const VIC_BUTTON_WIDTH = 220
      const VIC_BUTTON_HEIGHT = 48
      let vicWindowY = (screenHeight - VIC_SCREEN_HEIGHT) div 2
      let vicButtonY = vicWindowY + VIC_SCREEN_HEIGHT - 100
      let vicButtonSpacing = 40
      let vicTotalWidth = VIC_BUTTON_WIDTH * 3 + vicButtonSpacing * 2
      let vicButtonsX = (screenWidth - vicTotalWidth) div 2
      let continueRect = Rectangle(x: vicButtonsX.float32, y: vicButtonY.float32,
                                   width: VIC_BUTTON_WIDTH.float32, height: VIC_BUTTON_HEIGHT.float32)
      let vicStatsX = vicButtonsX + VIC_BUTTON_WIDTH + vicButtonSpacing
      let vicStatsRect = Rectangle(x: vicStatsX.float32, y: vicButtonY.float32,
                                   width: VIC_BUTTON_WIDTH.float32, height: VIC_BUTTON_HEIGHT.float32)
      let vicMenuX = vicStatsX + VIC_BUTTON_WIDTH + vicButtonSpacing
      let vicMenuRect = Rectangle(x: vicMenuX.float32, y: vicButtonY.float32,
                                  width: VIC_BUTTON_WIDTH.float32, height: VIC_BUTTON_HEIGHT.float32)

      let vicMousePos = getVirtualMousePosition()
      if checkCollisionPointRec(vicMousePos, continueRect):
        currentGame.selectedVictoryButton = 0
      elif checkCollisionPointRec(vicMousePos, vicStatsRect):
        currentGame.selectedVictoryButton = 1
      elif checkCollisionPointRec(vicMousePos, vicMenuRect):
        currentGame.selectedVictoryButton = 2

      # Resolve the chosen action: keyboard (Enter/Space/V/Tab/Esc/Q) or mouse click
      var victoryAction = -1  # 0=continue, 1=stats, 2=menu
      if isKeyPressed(Space) or (isKeyPressed(Enter) and currentGame.selectedVictoryButton == 0):
        victoryAction = 0
      elif (isKeyPressed(Tab) or isKeyPressed(V)) or
           (isKeyPressed(Enter) and currentGame.selectedVictoryButton == 1):
        victoryAction = 1
      elif (isKeyPressed(Escape) or isKeyPressed(Q)) or
           (isKeyPressed(Enter) and currentGame.selectedVictoryButton == 2):
        victoryAction = 2
      elif isMouseButtonPressed(Left):
        if checkCollisionPointRec(vicMousePos, continueRect): victoryAction = 0
        elif checkCollisionPointRec(vicMousePos, vicStatsRect): victoryAction = 1
        elif checkCollisionPointRec(vicMousePos, vicMenuRect): victoryAction = 2

      case victoryAction
      of 0:
        # Continue endlessly: re-arm the queued power-up reward and resume play
        playSound(stMenuSelect)
        initPowerUpRollAnimation(currentGame)
        currentGame.state = gsPowerUpSelect
      of 1:
        # View detailed run stats; ESC/Tab there returns here via previousState
        if hasValidRunStats():
          playSound(stMenuSelect)
          openRunStatsWindow()
          currentGame.previousState = gsVictory
          currentGame.state = gsRunStats
      of 2:
        # Return to menu: the run ends here, so persist results before leaving
        playSound(stMenuSelect)
        persistRunResults(currentGame)
        cleanupGame(currentGame)
        currentGame = newGame(screenWidth, screenHeight, settings.playerSkin, settings.bulletSkin, settings.playerShape, settings.particleEffect, settings.bulletShape)
        currentGame.discordClient = globalDiscordClient
        currentGame.state = gsMenu
        statsSavedThisGame = false
      else:
        discard

      beginGameDrawing()
      drawVictory(currentGame)
      drawCustomCursor(currentGame.time)
      endGameDrawing()

    of gs3DBoss:
      # 3D Boss fight
      playMusic(mtBoss)

      # Update 3D game
      if not cheatMenu.active:
        updateGame(currentGame, dt)

      # Render 3D game directly (no 2D render target)
      if currentGame.game3D != nil:
        beginDrawing()
        clearBackground(Black)
        var game3D = cast[ptr Game3D](currentGame.game3D)
        renderGame3D(game3D[])

        # Draw cheat menu overlay if active
        drawCheatMenu(cheatMenu, currentGame, screenWidth, screenHeight)

        endDrawing()
      else:
        # Safety: only recover if the 3D state is still active after update.
        if currentGame.state == gs3DBoss:
          currentGame.state = gsPlaying

    of gsPvPPlaying:
      # Safety check - if currentPvPGame is nil, return to menu
      if currentPvPGame.isNil:
        currentGame.state = gsMenu
        continue

      # Play appropriate music
      if currentPvPGame.isCountingDown:
        playMusic(mtWave)
      else:
        playMusic(mtBoss)  # Intense music for PvP

      # Check for pause (visual only - game continues running)
      if isKeyPressed(Escape) and not currentPvPGame.gameOver:
        currentGame.state = gsPaused

      # Update Discord Rich Presence (throttled internally to prevent lag)
      if not currentGame.discordClient.isNil:
        try:
          runCallbacks(currentGame.discordClient)
          updateDiscordForPvP(currentGame.discordClient, currentPvPGame)
        except Exception as e:
          echo "Discord error during PvP: ", e.msg
          try:
            disconnect(currentGame.discordClient)
          except:
            discard
          currentGame.discordClient = nil
          globalDiscordClient = nil

      # Update PvP game
      updatePvP(currentPvPGame, dt)

      # Check for exit when game is over
      if currentPvPGame.gameOver and isKeyPressed(Escape):
        # Send disconnect packet to notify opponent (graceful disconnect)
        if currentPvPGame.networkManager != nil and currentPvPGame.networkManager.isConnected:
          disconnect(currentPvPGame.networkManager, "Player left to menu")

        # Clean up network
        if currentPvPGame.networkManager != nil:
          cleanup(currentPvPGame.networkManager)

        # Clear PvP game state
        currentPvPGame = nil

        # Return to menu
        currentGame = newGame(screenWidth, screenHeight, settings.playerSkin,
                             settings.bulletSkin, settings.playerShape, settings.particleEffect, settings.bulletShape)
        currentGame.discordClient = globalDiscordClient
        currentGame.state = gsMenu
        continue  # Skip drawing, go to next frame

      beginGameDrawing()
      drawPvP(currentPvPGame)
      drawCustomCursor(currentPvPGame.gameTime)
      endGameDrawing()

  # Cleanup global Discord Rich Presence client
  if not globalDiscordClient.isNil:
    try:
      disconnect(globalDiscordClient)
    except:
      # Ignore Discord disconnect errors during shutdown
      discard

  # Cleanup
  stopMusic()
  closeSoundSystem(globalSoundSystem)
  closeWindow()

when isMainModule:
  main()
