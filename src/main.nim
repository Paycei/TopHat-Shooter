import raylib, rlgl, random, math, strutils, os, std/deques
import particle_types, game/combat, game/death, types, settings, effects, game, player, input_intent, wall, coin, bullet_skins, bullet_shapes, shapes, particle_pool, particle_skins, powerup, sound, cheat, statistics, run_statistics, save_system, run_save, suspend, sandbox, skins, desktop_bg_skins, cube_skins, boss_definitions, localization, gamemode_definitions, render_context, roguelite, dungeon, advancement, pvp_game, discord_helpers, discord_presence, discord_config, network/network, game3d/game_3d, ui/os_shop, ui/os_powerup_installer, ui/os_splash, ui/os_desktop, ui/os_window, ui/os_hud, ui/os_task_manager, ui/os_roguelite, ui/stats_window, ui/lore_cinematic, ui/endgame_cinematic, ui/roguelite_end_cinematic, ui/survival_end_cinematic, ui/language_select, ui/profile_select, ui/pvp_window, ui/sandbox_window, ui/loading_screen, ui/window_manager, ui/cutscene, ui/mode_intros

when defined(mobile):
  import mobile_controls  # updateMobileControls / drawMobileControls hooks

# Global quit-confirmation dialog

type ConfirmDialogContext = enum
  cdcQuitToDesktop,   # Close the whole application
  cdcQuitToMenu,      # Return to main menu
  cdcAbandonRestart,  # Game over restart while a block checkpoint could be continued
  cdcAbandonExit,     # Game over exit-to-menu while a block checkpoint could be continued
  cdcPostGameExit     # Exit to menu from game over/victory/run-stats (no checkpoint at stake)

var
  globalConfirmActive      = false
  globalConfirmContext     = cdcQuitToMenu
  globalConfirmFrameGuard  = 0.0'f32  # Prevents Q from instantly confirming on dialog open
  globalConfirmMouseGuard  = 0.0'f32  # anti-accident cooldown before mouse/button click is accepted

const DEFAULT_CONFIRM_COOLDOWN = 2.0'f32  # standard anti-accident window (seconds)

proc showGlobalConfirm(ctx: ConfirmDialogContext, cooldown: float32 = DEFAULT_CONFIRM_COOLDOWN) =
  ## `cooldown` is the seconds the YES button stays greyed out / counts down before it
  ## accepts a click. Pass 0.0 to make confirmation immediate (e.g. the main-menu Quit
  ## icon, where there's no in-progress run to protect). Defaults to the standard window
  ## so in-game quits keep the anti-accident delay.
  globalConfirmActive     = true
  globalConfirmContext    = ctx
  globalConfirmFrameGuard = 0.15'f32  # ~9 frames at 60 fps absorbs the key that opened the dialog
  globalConfirmMouseGuard = max(0.0'f32, cooldown)

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
  let titleStr = case globalConfirmContext
                 of cdcQuitToDesktop: t(tkConfirmQuitTitle)
                 of cdcQuitToMenu, cdcPostGameExit: t(tkConfirmExitTitle)
                 of cdcAbandonRestart, cdcAbandonExit: t(tkConfirmCheckpointTitle)
  let tW = measureText(titleStr, 16)
  drawText(titleStr, dx + (DW - tW) div 2, dy + 9, 16, Color(r: 255, g: 200, b: 200, a: 255))

  let bodyStr = case globalConfirmContext
                of cdcQuitToDesktop: t(tkConfirmQuitBody)
                of cdcQuitToMenu, cdcAbandonExit, cdcPostGameExit: t(tkConfirmExitBody)
                of cdcAbandonRestart: t(tkConfirmCheckpointRestartBody)
  let bW = measureText(bodyStr, 19)
  drawText(bodyStr, dx + (DW - bW) div 2, dy + tbH + 24, 19, White)
  # cdcPostGameExit has no subtitle: the run is already over and results are
  # already persisted, so there's no "unsaved progress" to warn about.
  let subStr = if globalConfirmContext in {cdcAbandonRestart, cdcAbandonExit}:
                 t(tkConfirmCheckpointSub)
               elif globalConfirmContext == cdcPostGameExit:
                 ""
               else:
                 t(tkConfirmUnsaved)
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
               else:
                 case globalConfirmContext
                 of cdcQuitToDesktop: t(tkConfirmQuitBtn)
                 of cdcQuitToMenu, cdcAbandonExit, cdcPostGameExit: t(tkConfirmExitBtn)
                 of cdcAbandonRestart: t(tkConfirmRestartBtn)
  let yTW = measureText(yesTxt, 14)
  drawText(yesTxt, yesX + (BW - yTW) div 2, btnY + 13, 14, White)

  var decision = 0
  if isPointerPressed():
    if noHov:               decision = -1
    elif yesHov and mouseReady: decision = 1
  if isBackPressed(): decision = -1
  if keyReady:
    if globalConfirmContext == cdcAbandonRestart:
      if isKeyPressed(R): decision = 1
    elif isKeyPressed(Q): decision = 1

  if decision != 0:
    globalConfirmActive = false
  return decision

# Resume-run prompt (Continue / New Run) shown when launching a mode that has a
# matching saved run. Neutral two-button OS-themed dialog, gamepad-navigable via
# the pointer/back abstraction.
var
  resumePromptActive = false
  resumePromptMode   = gmWaveBased  # mode the saved run belongs to

proc drawResumeDialog(sw, sh: int32): int =
  ## Returns 0 = still open, 1 = Continue (resume), -1 = New Run (fresh).
  if not resumePromptActive: return 0
  let mp = getVirtualMousePosition()
  const DW: int32 = 480; const DH: int32 = 210
  const BW: int32 = 180; const BH: int32 = 44
  let dx = (sw - DW) div 2; let dy = (sh - DH) div 2

  drawRectangle(0, 0, sw, sh, Color(r: 0, g: 0, b: 0, a: 170))
  drawRectangle((dx+7).int32, (dy+7).int32, DW, DH, Color(r: 0, g: 0, b: 0, a: 140))
  drawRectangle(dx, dy, DW, DH, Color(r: 16, g: 24, b: 34, a: 255))
  drawRectangleLines(Rectangle(x: dx.float32, y: dy.float32, width: DW.float32, height: DH.float32),
                     3, Color(r: 0, g: 200, b: 255, a: 255))

  let tbH: int32 = 36
  drawRectangle(dx, dy, DW, tbH, Color(r: 20, g: 70, b: 100, a: 255))
  let titleStr = t(tkResumeRunTitle)
  let tW = measureText(titleStr, 16)
  drawText(titleStr, dx + (DW - tW) div 2, dy + 9, 16, Color(r: 200, g: 240, b: 255, a: 255))

  let bodyStr = t(tkResumeRunBody)
  let bW = measureText(bodyStr, 17)
  drawText(bodyStr, dx + (DW - bW) div 2, dy + tbH + 34, 17, White)

  let btnY = dy + DH - BH - 22
  let newX = dx + (DW div 2) - BW - 12
  let contX = dx + (DW div 2) + 12
  let newHov  = isOverRect(mp, newX,  btnY, BW, BH)
  let contHov = isOverRect(mp, contX, btnY, BW, BH)

  # New Run (amber: discards the save)
  drawRectangle(newX, btnY, BW, BH,
    if newHov: Color(r: 150, g: 95, b: 0, a: 255) else: Color(r: 110, g: 70, b: 0, a: 255))
  drawRectangleLines(Rectangle(x: newX.float32, y: btnY.float32, width: BW.float32, height: BH.float32),
    if newHov: 3 else: 2,
    if newHov: Color(r: 255, g: 180, b: 60, a: 255) else: Color(r: 200, g: 140, b: 40, a: 255))
  let newTxt = t(tkResumeNewRun); let nTW = measureText(newTxt, 14)
  drawText(newTxt, newX + (BW - nTW) div 2, btnY + 14, 14, White)

  # Continue (cyan: resume)
  drawRectangle(contX, btnY, BW, BH,
    if contHov: Color(r: 0, g: 130, b: 165, a: 255) else: Color(r: 0, g: 95, b: 125, a: 255))
  drawRectangleLines(Rectangle(x: contX.float32, y: btnY.float32, width: BW.float32, height: BH.float32),
    if contHov: 3 else: 2,
    if contHov: Color(r: 80, g: 220, b: 255, a: 255) else: Color(r: 0, g: 180, b: 220, a: 255))
  let contTxt = t(tkResumeContinue); let cTW = measureText(contTxt, 14)
  drawText(contTxt, contX + (BW - cTW) div 2, btnY + 14, 14, White)

  var decision = 0
  if isPointerPressed():
    if newHov:       decision = -1
    elif contHov:    decision = 1
  if isBackPressed(): decision = -1
  if decision != 0:
    resumePromptActive = false
  return decision

const
  WorldWidth = 1024   # Gameplay world width -- fixed forever, independent of HUD layout
  WorldHeight = 768   # Gameplay world height -- fixed forever
  maxRenderSupersampleFactor = 2
  maxRenderSupersampleScale = maxRenderSupersampleFactor.float32
  targetFPS = 60
  MOUSE_MOVEMENT_THRESHOLD = 2.0  # Minimum pixel movement to count as "mouse moved"

when defined(mobile):
  const GameplayTouchStates = {gsPlaying, gsPvPPlaying}
    ## The states that drive mobile_controls. Leaving one must clear its state.

  const TouchBackStates = {gsPaused, gsRunStats, gsShop, gsPowerUpSelect,
                           gsRogueliteFloorSelect, gsGameOver, gsVictory,
                           gsRogueliteVictory, gsProfileSelect, gsLanguageSelect}
    ## Where the on-screen back chip is armed: fullscreen overlay states whose
    ## only cancel path was Escape. Excluded on purpose -- gsMenu (the chip's
    ## top-left corner is the OS-desktop icon grid; its windows close via their
    ## own buttons), gsPlaying/gsPvPPlaying (mobile_controls already draws a
    ## pause button), and the cinematics (hold-anywhere to skip, see cutscene).

  const ResumeStallThreshold = 0.5'f32
    ## A frame longer than this can't be a real frame (it's 30x the 60 FPS
    ## budget) -- it means the app was backgrounded and raylib blocked the loop.

when defined(android):
  const
    AndroidCheckpointInterval = 45.0'f32
      ## Hard backstop between run checkpoints; bounds how much progress an
      ## OS-initiated process kill can cost.
    AndroidCheckpointMinGap = 5.0'f32
      ## Debounce for the opportunistic "just left gsPlaying" checkpoint, so
      ## rapid state churn (shop -> countdown -> playing) doesn't serialize the
      ## whole simulation every second.

# Virtual screen (desktop / menus / render target) size. Height is fixed at 768;
# width switches with the HUD layout setting: 1024 classic (4:3), 1366 widescreen
# (16:9). These are vars because the setting can toggle live.
var
  screenWidth: int32 = WorldWidth.int32
  screenHeight: int32 = WorldHeight.int32

when defined(mobile):
  const
    MobileMinVirtualWidth = 1366'i32   # 16:9, the desktop widescreen canvas
    MobileMaxVirtualWidth = 1792'i32   # ~21:9; past this the gutters dwarf the world
    MobileVirtualWidthStep = 32'i32    # keeps (w - WorldWidth) div 2 exact

  proc mobileVirtualWidth(): int32 =
    ## Widescreen canvas width fitted to the REAL device aspect.
    ##
    ## updateRenderScale takes min(windowW/virtualW, windowH/virtualH), and a phone
    ## in landscape is always wider than 16:9, so the height term always wins.
    ## Widening the virtual canvas therefore costs nothing in world size — it only
    ## reclaims the black side bars a 19.5:9 screen would otherwise waste and
    ## spends them on wider HUD gutters, which is what lets the status column be
    ## drawn bigger (drawBorderHUDPanel).
    ##
    ## Quantized so a window resize can't thrash the render target, and clamped so
    ## a tablet-ish aspect can't shrink the world into a sliver of a huge canvas.
    let w = getScreenWidth()
    let h = getScreenHeight()
    if w <= 0 or h <= 0:
      return MobileMinVirtualWidth   # called once before initWindow
    let fitted = int32(WorldHeight.float32 * w.float32 / h.float32)
    let stepped = (fitted div MobileVirtualWidthStep) * MobileVirtualWidthStep
    clamp(stepped, MobileMinVirtualWidth, MobileMaxVirtualWidth)

proc virtualWidthFor(layout: HudLayout): int32 =
  ## Virtual screen width for a HUD layout: widescreen widens the desktop to 16:9
  ## while the gameplay world stays WorldWidth; classic keeps the world size.
  case layout
  of hlWidescreen:
    when defined(mobile): mobileVirtualWidth() else: 1366'i32
  of hlClassic: WorldWidth.int32

# Global Discord client that persists across game sessions
var globalDiscordClient: DiscordClient = nil

# Global window manager
var globalWindowManager: WindowManager = nil

var
  renderTarget: RenderTexture2D  # Virtual screen for consistent rendering
  currentRenderTargetSupersampleScale: float32 = 0.0
  currentRenderTargetVirtualWidth: int32 = 0  # Virtual width the render texture was built at
  renderScale: float32 = 1.0
  renderOffsetX: float32 = 0.0
  renderOffsetY: float32 = 0.0
  currentPvPGame: PvPGameState = nil
  # Brief input lockout when the language-select screen opens, so the same click
  # that dismissed the splash can't fall through and auto-pick a language.
  languageSelectGuard: float32 = 0.0
  # Same idea for the profile-select screen (which opens directly off the splash).
  profileSelectGuard: float32 = 0.0

proc rebuildRenderTarget(supersampleScale: float32) =
  let renderTargetWidth = int32(screenWidth.float32 * supersampleScale)
  let renderTargetHeight = int32(screenHeight.float32 * supersampleScale)
  renderTarget = loadRenderTexture(renderTargetWidth, renderTargetHeight)
  setTextureFilter(renderTarget.texture, Bilinear)
  currentRenderTargetSupersampleScale = supersampleScale
  currentRenderTargetVirtualWidth = screenWidth.int32

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
  # Rebuild when EITHER the supersample factor or the virtual resolution changed.
  if abs(targetSupersampleScale - currentRenderTargetSupersampleScale) > 0.001'f32 or
     screenWidth.int32 != currentRenderTargetVirtualWidth:
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
  # Center the fixed-size world inside the (possibly wider) virtual screen. 0 in
  # classic mode; the left-gutter width in widescreen mode.
  setWorldViewOffset(((screenWidth - WorldWidth) div 2).float32)

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
  when defined(android):
    # Android manages a single fullscreen surface; resizing/positioning it (e.g.
    # setWindowSize(1024,768)) would shrink the game into a corner. The per-frame
    # updateRenderScale still maintains the letterbox + touch transform.
    return
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
  if not game.mouseMovedRecently:
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
  if isPointerPressed() or isMouseButtonPressed(Right) or isMouseButtonPressed(Middle):
    game.mouseMovedRecently = true
    game.keyboardUsedRecently = false
  game.lastMousePos = newVector2f(currentPos.x, currentPos.y)

proc markKeyboardUsed*(game: Game) =
  ## Marks that keyboard was just used, disabling mouse selection temporarily
  game.keyboardUsedRecently = true
  game.mouseMovedRecently = false

proc drawCustomCursor*(time: float32) =
  ## Draw custom crosshair cursor (only when system cursor is hidden)
  when defined(mobile):
    # There is no pointer to draw on touch: the emulated cursor never leaves the
    # last tap, so the crosshair would just sit there. Reuse the hook -- it is
    # the one call every state's draw branch already makes, and it runs last, so
    # it is exactly the right place and z-order for the on-screen back chip and
    # the virtual keyboard, both of which must sit above the window layer.
    drawVirtualKeyboard()
    drawTouchBackButton()
    return
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
            gsRogueliteFloorSelect, gsVictory, gsRogueliteVictory}

proc isBondingCombatState(state: GameState): bool =
  state in {gsPlaying, gsPvPPlaying}

proc isMenuOrGameState(state: GameState): bool =
  ## Every bonding gameplay state, plus the pre-game menus.
  isBondingGameplayState(state) or
    state in {gsSplash, gsProfileSelect, gsLanguageSelect, gsMenu}

proc updateInGameMouseBonding(settings: Settings, state: GameState) =
  if settings == nil:
    releaseMouseClip()
    return

  # While the gamepad drives, don't clip or warp the OS cursor: bonding would
  # fight the (parked) physical mouse, and a stray warp would look like mouse
  # activity to the device arbitration.
  if isGamepadActive():
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

proc initializeAllCosmetics() =
  ## Single source of truth for (re)populating every cosmetic database. Each
  ## cosmetic module owns its own idempotent `initialize*` proc; this lists them
  ## once so startup and the language-change hook rebuild all tables identically.
  ## Safe to call repeatedly, these inits carry no unlock/equip state (that
  ## lives in roguelite's CosmeticKind ownership and the equipped ints in
  ## Settings), so re-running only refreshes localized card names/descriptions.
  initializeSkins()
  initializeBulletSkins()
  initializeBulletShapes()
  initializeShapes()
  initializeParticleSkins()
  initializeDesktopBgSkins()
  initializeCubeSkins()

proc main() =
  randomize()

  # Save-profile bootstrap: convert pre-profile saves into profile 1, then
  # point the save system at the last-used profile so its settings drive
  # window creation. The profile-select screen shown after the splash can
  # still switch to another profile (switchToProfile reloads everything).
  migrateLegacySaveFiles()
  activeProfileSlot = getLastUsedProfileSlot()
  if not profileExists(activeProfileSlot):
    activeProfileSlot = 1
    for slot in 1..MaxProfileSlots:
      if profileExists(slot):
        activeProfileSlot = slot
        break
  currentDifficulty = loadProfileDifficulty(activeProfileSlot)

  let settings = initSettings()

  # Size the virtual screen from the saved HUD layout BEFORE the window is
  # created, so the window opens at the correct width (and every downstream
  # newWindowManager / render-target build sees the right size).
  screenWidth = virtualWidthFor(settings.hudLayout)

  # Set up window with appropriate flags based on saved settings
  if settings.fullscreen:
    setConfigFlags(flags(WindowUndecorated, WindowResizable))
  else:
    setConfigFlags(flags(WindowResizable))

  initWindow(screenWidth, screenHeight, "TopHat-ShooterOS: v6.1 Edition")
  setTargetFPS(targetFPS)
  setExitKey(Null)
  when defined(android):
    # The aim stick auto-fires, so a player who holds still touches the screen
    # for minutes at a time; without this the display dims and locks mid-run.
    nimAndroidKeepScreenOn()
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

  # Initialize all cosmetic databases (single source of truth: initializeAllCosmetics).
  initializeAllCosmetics()

  # Re-run cosmetic inits whenever the language changes so card names/descs
  # reflect the new language without requiring a restart.
  onLanguageChange = proc() =
    initializeAllCosmetics()

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
  var appliedHudLayout = settings.hudLayout  # Last virtual-resolution applied to the window/pipeline

  when defined(mobile):
    var mobilePrevState = gsSplash  # matches currentGame.state at first entry

  when defined(android):
    # See the checkpoint block in the frame loop.
    var androidCheckpointTimer = 0.0'f32
    var androidPrevState = gsSplash

  # Initialize global Discord client (persists across game sessions)
  # Wrapped in try-catch to handle Discord connection failures gracefully.
  # Skipped on Android: there is no desktop Discord to reach, and the connect()
  # spins up a background IPC thread that would only ever fail.
  when not defined(android):
    try:
      globalDiscordClient = newDiscordClient(DISCORD_APP_ID)
      if not globalDiscordClient.isNil:
        discard globalDiscordClient.connect()  # Start background thread
    except:
      # Discord initialization failed - continue without Rich Presence
      globalDiscordClient = nil

  var currentGame = newGame(WorldWidth, WorldHeight, settings.playerSkin, settings.bulletSkin, settings.playerShape, settings.particleEffect, settings.bulletShape)
  currentGame.state = gsSplash  # Start with splash screen
  # Assign global Discord client to game
  currentGame.discordClient = globalDiscordClient

  var splashScreen = newSplashScreen()
  var profileSelect = newProfileSelectState()
  var loreCinematic = newLoreCinematic()
  # Endgame ("system secured") cinematic. `endgameCinematicArmed` lazily reinitialises
  # the timeline whenever we enter gsEndgameCinematic (the producer is game.nim, which
  # can't touch this local). `endgameReplayMode` distinguishes a real first-win playthrough
  # (hand off to the victory screen) from a settings-menu replay (return to the desktop).
  var endgameCinematic = newEndgameCinematic()
  var endgameCinematicArmed = false
  var endgameReplayMode = false
  # Roguelite ("Deep Recovery") and Survival ("Long Watch") outros mirror the
  # endgame cinematic exactly: lazily (re)armed on entry since their producers
  # (game.nim / game/death.nim) can only set the state, and a replay flag tells the
  # finish handler to return to the desktop instead of the run-end screen.
  var rogueliteEndCinematic = newRogueliteEndCinematic()
  var rogueliteEndCinematicArmed = false
  var rogueliteEndReplayMode = false
  var survivalEndCinematic = newSurvivalEndCinematic()
  var survivalEndCinematicArmed = false
  var survivalEndReplayMode = false
  # Generic cutscene state. activeCutscene holds whichever Cutscene is currently
  # playing; cutsceneContinuation says where to go when it finishes.
  # pendingModeAfterCutscene is the pendingGameMode value staged before a mode-intro
  # cutscene plays (used by cscLaunchGame); -1 when not in use.
  var activeCutscene: Cutscene = nil
  var cutsceneContinuation: CutsceneContinuation = cscMenu
  var pendingModeAfterCutscene: int = -1
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

  proc switchToProfile(slot: int) =
    ## Point the save system at profile `slot` and reload every save-backed
    ## system from that profile's folder. Settings/stats are mutated in place
    ## (they are refs shared with the window manager); the advancement and
    ## roguelite profiles are replaced and re-propagated like elsewhere.
    activeProfileSlot = slot
    setLastUsedProfileSlot(slot)
    currentDifficulty = loadProfileDifficulty(slot)
    # Run saves are per-profile; drop the cached checkpoint lookup so the new
    # profile's own checkpoint (or absence of one) is what gets read back.
    invalidateBlockCheckpointCache()

    reloadSettingsFromDisk(settings)
    applySettings(settings)
    applyWindowMode(settings.fullscreen)

    stats[] = initStatistics()[]
    discard loadStatistics(stats)

    let freshRunStats = loadLastRunStats()
    if freshRunStats.isNil:
      clearLastCompletedRun()
    else:
      loadLastCompletedRun(freshRunStats)

    advancementProfile = loadAdvancements()
    setActiveRogueliteProfile(loadRogueliteProfile())
    discard syncAdvancements(advancementProfile, stats, getLastRunStats(), rogueliteProfile)
    if advancementProfile.dirty:
      discard saveAdvancements(advancementProfile)
    if not globalWindowManager.isNil:
      if not globalWindowManager.advancements.isNil:
        globalWindowManager.advancements.profile = advancementProfile
      if not globalWindowManager.pvp.isNil:
        globalWindowManager.pvp.inputNickname = settings.pvpNickname
        globalWindowManager.pvp.networkManager.hostNickname = settings.pvpNickname

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
      # Cashing out from the ending screen is a banked win, not a death; anything
      # else reaching here (real game-over, or dying in a later endless loop) is a
      # death. awaitingVictoryScreen is only set while parked on the ending screen.
      discard commitRogueliteRunProgress(game, not game.rogueliteRun.awaitingVictoryScreen)
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

      # Survival's score is its progression clock (which pauses during bosses), so it
      # matches the HUD the player watched; other modes report real elapsed time.
      let timeForStats = if isTimeSurvivalMode(game.mode): game.survivalTime else: game.time
      updateStatsForMode(stats, game.mode, scoreReached, timeForStats,
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
  var pendingResume = false  # True when the pending launch should resume a saved run
  var windowCloseRequested = false  # True once the OS close button is clicked

  while not windowCloseRequested:
    # Re-arm windowShouldClose each iteration; show confirm instead of quitting directly
    if windowShouldClose():
      let isInGame = currentGame.state in {gsPlaying, gsPaused, gsShop, gsCountdown,
                                           gsWaveCleared, gsPowerUpSelect, gsDeathSequence,
                                           gsRogueliteFloorSelect, gsPvPPlaying, gs3DBoss}
      # Show the quit-confirm popup when an active game session is running (full
      # anti-accident cooldown to protect the in-progress run). The main menu, the
      # game-over/victory screens (and the run-stats screen reached from them), and
      # sandbox mode also confirm, but with cooldown 0 -> YES is immediately
      # clickable, since none of them has a live run to lose (matches the
      # Shutdown.exe icon).
      if settings.exitConfirmEnabled and isInGame and not isSandboxMode(currentGame.mode):
        if not globalConfirmActive:
          showGlobalConfirm(cdcQuitToDesktop)
      elif settings.exitConfirmEnabled and
           (currentGame.state in {gsMenu, gsGameOver, gsVictory, gsRunStats} or
            isSandboxMode(currentGame.mode)):
        if not globalConfirmActive:
          showGlobalConfirm(cdcQuitToDesktop, cooldown = 0.0'f32)
      else:
        # Splash / lore / victory, or confirm dialogs disabled: just quit
        windowCloseRequested = true
    # Check if fullscreen toggle was requested
    if fullscreenToggleRequested:
      fullscreenToggleRequested = false
      applyWindowMode(settings.fullscreen)
      if not saveSettings(settings):
        echo "Warning: Failed to save settings to disk"

    updateRenderSupersampleState(settings)

    # Live HUD-layout (virtual resolution) toggle. When the setting changes,
    # resize the virtual screen + window, rebuild the render target, recenter the
    # window on the monitor (windowed only), recompute the letterbox + world
    # offset, and re-lay-out the desktop windows for the new width.
    # On mobile the widescreen width also tracks the device aspect, which is only
    # known once the surface exists (and can change on a fold/resize), so compare
    # the computed width too rather than the layout alone. On desktop the width is
    # a pure function of the layout, so this extra term is never true there.
    let desiredVirtualWidth = virtualWidthFor(settings.hudLayout)
    if settings.hudLayout != appliedHudLayout or desiredVirtualWidth != screenWidth:
      appliedHudLayout = settings.hudLayout
      screenWidth = desiredVirtualWidth
      rebuildRenderTarget(getRenderSupersampleScale())
      # Same hazard applyWindowMode guards against: Android owns a single
      # fullscreen surface, so resizing/repositioning it would shrink the game
      # into a corner. Only the virtual canvas changes there; the per-frame
      # updateRenderScale re-fits the letterbox to the unchanged surface.
      when not defined(android):
        if not settings.fullscreen:
          setWindowSize(screenWidth, screenHeight)
          let monitor = getCurrentMonitor()
          let monitorWidth = getMonitorWidth(monitor)
          let monitorHeight = getMonitorHeight(monitor)
          setWindowPosition((monitorWidth - screenWidth) div 2,
                            (monitorHeight - screenHeight) div 2)
      updateRenderScale()
      if not globalWindowManager.isNil:
        globalWindowManager.relayoutWindows(screenWidth, screenHeight)

    var dt = getFrameTime()

    when defined(mobile):
      # Backgrounding: raylib's Android backend blocks inside pollInputEvents
      # while the activity is paused, so the first frame after resume reports
      # the entire time spent in the background. Feeding that to updateGame
      # fast-forwards physics, spawns and timers by however long the user was
      # away. Clamp it, and don't drop the player back into a live arena.
      if dt > ResumeStallThreshold:
        dt = 1.0'f32 / targetFPS.float32
        if currentGame.state == gsPlaying and not globalConfirmActive:
          currentGame.state = gsPaused

    when defined(android):
      # Android kills backgrounded NativeActivity processes outright, so the
      # shutdown checkpoint at the bottom of main() is never reached and the run
      # is lost on every app switch. Checkpoint on a timer instead. Both calls
      # are self-guarding no-ops for unsupported modes/states (run_save.nim:268,
      # suspend.nim:187). Prefer flushing just after the player leaves the hot
      # loop -- the shop/wave-cleared/pause screens are where a serialization
      # hitch costs nothing -- with the interval as a hard backstop.
      androidCheckpointTimer += dt
      let leftHotLoop = androidPrevState == gsPlaying and
                        currentGame.state != gsPlaying
      if not currentGame.isNil and
         ((leftHotLoop and androidCheckpointTimer >= AndroidCheckpointMinGap) or
          androidCheckpointTimer >= AndroidCheckpointInterval):
        androidCheckpointTimer = 0.0'f32
        saveRunState(currentGame)
        suspendGame(currentGame)
      androidPrevState = currentGame.state

    # Gamepad layer: device arbitration + virtual cursor. Must run before the
    # state machine so every getVirtualMousePosition() this frame agrees on the
    # active device. Sandbox stays in menu-cursor mode: its object placement is
    # cursor-driven, not twin-stick.
    setPreferredGamepad(globalSettings.preferredGamepad.int32)
    updateGamepadInput(dt, screenWidth.float32, screenHeight.float32,
                       getRealVirtualMousePosition())
    # The global confirm dialog freezes gameplay updates, so nothing would
    # write the aim point; give the pad a live menu cursor instead.
    setGamepadCursorMode(
      if currentGame.state in {gsPlaying, gsPvPPlaying} and
         not isSandboxMode(currentGame.mode) and
         not globalConfirmActive: cmGameplayAim
      else: cmMenuCursor)

    # Tick down the global confirm guards
    if globalConfirmFrameGuard > 0:
      globalConfirmFrameGuard = max(0.0'f32, globalConfirmFrameGuard - dt)
    if globalConfirmMouseGuard > 0:
      globalConfirmMouseGuard = max(0.0'f32, globalConfirmMouseGuard - dt)

    # Update render scale every frame in case window was resized
    updateRenderScale()

    when defined(mobile):
      # Menu-layer touch gestures. Must run before the state machine so every
      # pointer wrapper queried this frame agrees. Visibility is armed first
      # because updateTouchUI needs to know whether a tap landed on the back
      # chip or should fall through to the UI underneath, and it is keyed off
      # the state that was actually on screen when the finger went down.
      # Touch has no hover, and the emulated cursor only "moves" while a finger
      # is down. Several handlers gate their *click* tests on this flag, not
      # just their highlights (os_desktop.nim, os_task_manager.nim,
      # isMenuClickValid above), so leaving it to the movement heuristic makes
      # taps intermittently do nothing. Forced here rather than in
      # updateMouseTracking because only 8 of the 23 states call that.
      if not currentGame.isNil:
        currentGame.mouseMovedRecently = true
        currentGame.keyboardUsedRecently = false

      setTouchBackVisible(currentGame.state in TouchBackStates)
      updateTouchUI(dt)

      # updateMobileControls only runs in the gameplay states, so a finger
      # lifted after leaving one is never observed and its stick/button stays
      # latched. Clear on the way out.
      if currentGame.state notin GameplayTouchStates and
         mobilePrevState in GameplayTouchStates:
        resetMobileControls()
      mobilePrevState = currentGame.state

    # Update music stream (required for continuous playback)
    updateMusic()

    # Handle fullscreen toggle with F11 (borderless window) with debouncing
    let currentTime = getTime()
    if isKeyPressed(F11) and (currentTime - lastFullscreenToggleTime) > 0.5:
      lastFullscreenToggleTime = currentTime
      settings.fullscreen = not settings.fullscreen
      fullscreenToggleRequested = true

    # ALWAYS hide system cursor - we always use custom cursor
    when not defined(mobile):
      # There is no system cursor to hide on touch, and mouse bonding calls
      # setMousePosition, which would fight the touch-synthesized cursor
      # position raylib maintains from touch point 0.
      hideCursor()
      updateInGameMouseBonding(settings, currentGame.state)

    case currentGame.state
    of gsSplash:
      # Update splash screen
      updateSplashScreen(splashScreen, dt)

      # Any key or mouse button fast-boots through the splash, then skips it
      var anyKeyPressed = false
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
      if isPointerPressed() or isMouseButtonPressed(Right):
        anyKeyPressed = true

      if anyKeyPressed:
        if splashScreen.complete:
          # Always pick (or create) a save profile first; the profile decides
          # whether the language screen / intro cinematic still needs to play.
          profileSelect.refreshSlots()
          currentGame.state = gsProfileSelect
          profileSelectGuard = 0.18'f32
        else:
          # Mid-boot press: fast-forward the BIOS / kernel reveal instead.
          fastForwardSplash(splashScreen)

      beginGameDrawing()
      drawSplashScreen(splashScreen, screenWidth, screenHeight)
      endGameDrawing()

    of gsProfileSelect:
      playMusic(mtMenu)
      currentGame.time += dt
      if profileSelectGuard > 0:
        profileSelectGuard -= dt

      let mousePos = getVirtualMousePosition()
      var chosenSlot = 0
      if profileSelectGuard <= 0:
        chosenSlot = updateProfileSelect(profileSelect, dt, mousePos,
                                         screenWidth.int32, screenHeight.int32)

      if chosenSlot > 0:
        switchToProfile(chosenSlot)
        playSound(stMenuSelect)
        if not settings.hasSeenIntro:
          # Fresh profile: pick a language before the intro cinematic.
          currentGame.state = gsLanguageSelect
          languageSelectGuard = 0.18'f32
        else:
          currentGame.state = gsMenu

      beginGameDrawing()
      drawProfileSelect(profileSelect, screenWidth.int32, screenHeight.int32,
                        currentGame.time, mousePos, activeProfileSlot)
      drawCustomCursor(currentGame.time)
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
        if isPointerPressed():
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

    of gsEndgameCinematic:
      # One-time outro, played the first time the wave-60 boss falls (or replayed
      # from settings). Lazily (re)armed on entry since game.nim sets this state.
      if not endgameCinematicArmed:
        endgameCinematic = newEndgameCinematic()
        endgameCinematicArmed = true
      playMusic(mtMenu)  # calmer score than the tense intro's boss theme
      updateEndgameCinematic(endgameCinematic, dt)
      if endgameCinematic.complete:
        endgameCinematicArmed = false
        if not settings.hasSeenEnding:
          settings.hasSeenEnding = true
          discard saveSettings(settings)
        if endgameReplayMode:
          # Replayed from the desktop: there is no active run to congratulate.
          endgameReplayMode = false
          currentGame.state = gsMenu
        else:
          # First win: hand off to the "system secured" victory screen.
          currentGame.state = gsVictory

      beginGameDrawing()
      drawEndgameCinematic(endgameCinematic, screenWidth, screenHeight)
      endGameDrawing()

    of gsRogueliteEndCinematic:
      # One-time roguelite outro, played the first time the final-floor boss falls
      # (or replayed from settings). game.nim sets this state, so arm lazily here.
      if not rogueliteEndCinematicArmed:
        rogueliteEndCinematic = newRogueliteEndCinematic()
        rogueliteEndCinematicArmed = true
      playMusic(mtMenu)
      updateRogueliteEndCinematic(rogueliteEndCinematic, dt)
      if rogueliteEndCinematic.complete:
        rogueliteEndCinematicArmed = false
        if not settings.hasSeenRogueliteEnding:
          settings.hasSeenRogueliteEnding = true
          discard saveSettings(settings)
        if rogueliteEndReplayMode:
          # Replayed from the desktop: there is no active run to send off.
          rogueliteEndReplayMode = false
          currentGame.state = gsMenu
        else:
          # First final-floor clear: hand off to the roguelite victory screen.
          currentGame.state = gsRogueliteVictory

      beginGameDrawing()
      drawRogueliteEndCinematic(rogueliteEndCinematic, screenWidth, screenHeight)
      endGameDrawing()

    of gsSurvivalEndCinematic:
      # Survival "Long Watch" eulogy, played on death after a 15+ minute stand
      # (or replayed from settings). game/death.nim sets this state; arm lazily.
      if not survivalEndCinematicArmed:
        survivalEndCinematic = newSurvivalEndCinematic()
        survivalEndCinematicArmed = true
      playMusic(mtMenu)
      updateSurvivalEndCinematic(survivalEndCinematic, dt)
      if survivalEndCinematic.complete:
        survivalEndCinematicArmed = false
        if not settings.hasSeenSurvivalEnding:
          settings.hasSeenSurvivalEnding = true
          discard saveSettings(settings)
        if survivalEndReplayMode:
          survivalEndReplayMode = false
          currentGame.state = gsMenu
        else:
          # The run is over. The "Long Watch" eulogy is the true send-off for a
          # survival death, so close the game once it finishes playing rather than
          # dropping to the game-over screen.
          windowCloseRequested = true

      beginGameDrawing()
      drawSurvivalEndCinematic(survivalEndCinematic, screenWidth, screenHeight)
      endGameDrawing()

    of gsCutscene:
      # Generic cutscene player.  activeCutscene must be set before entering this
      # state; cutsceneContinuation controls where we go when it finishes.
      if activeCutscene.isNil:
        currentGame.state = gsMenu
      else:
        playMusic(activeCutscene.musicTrack)
        updateCutscene(activeCutscene, dt)
        if activeCutscene.complete:
          case cutsceneContinuation
          of cscMenu:
            currentGame.state = gsMenu
          of cscVictory:
            currentGame.state = gsVictory
          of cscLaunchGame:
            # Mode-intro finished: start the loading animation and hand off to gsMenu.
            # Mark the intro as seen + save happens in the mode-launch helper (Stage 3).
            let loadText = case pendingModeAfterCutscene
              of 0: "Launching Wave-Based Mode..."
              of 1: "Launching Time Survival Mode..."
              of 6: "Launching Sandbox Mode..."
              of 9: "Launching Roguelite Mode..."
              else: "Launching..."
            startLoadingAnimation(osDesktop, loadText)
            pendingGameMode = pendingModeAfterCutscene
            pendingModeAfterCutscene = -1
            currentGame.state = gsMenu

        beginGameDrawing()
        drawCutscene(activeCutscene, screenWidth, screenHeight)
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
          currentGame = newGame(WorldWidth, WorldHeight, settings.playerSkin, settings.bulletSkin, settings.playerShape, settings.particleEffect, settings.bulletShape)
          currentGame.discordClient = globalDiscordClient
          setGameMode(currentGame, gmWaveBased)
          # Primary resume path: an EXACT snapshot restores the whole live sim
          # (and its run stats). On any failure fall back to the checkpoint.
          var exactResume0 = false
          if pendingResume and hasSuspendSnapshot():
            if restoreGame(currentGame):
              # Give a brief reorient countdown when dropping back into live play
              # (leave shop / power-up / floor-select states as restored).
              if currentGame.state == gsPlaying:
                currentGame.state = gsCountdown
                currentGame.countdownTimer = 3.0
              exactResume0 = true
            else:
              deleteSuspendSnapshot()
          if exactResume0:
            discard  # snapshot carried the full sim + currentRunStats
          elif pendingResume and applySavedRun(currentGame):
            initializeRunTracking(currentGame)  # checkpoint resume: fresh stats
          elif pendingResume and applyBlockCheckpoint(currentGame):
            # No live run save, but a death-surviving block checkpoint exists:
            # resume from the last cleared boss block. No comeback bonus here.
            # Reaching this path means the run save was deleted by a death, so
            # the run is no longer flawless.
            currentGame.runHadDeath = true
            initializeRunTracking(currentGame)
          else:
            deleteRunSave()
            deleteBlockCheckpoint()  # fresh run: discard the block checkpoint too
            deleteSuspendSnapshot()
            applyComebackBonus(currentGame)
            currentGame.state = gsPlaying
            initializeRunTracking(currentGame)
          statsSavedThisGame = false
        of 1:  # Time Survival Mode
          if not settings.survivalUnlocked:
            showDesktopToast(osDesktop, t(tkDesktopModeLocked) & " " & t(tkSurvivalLockedDesc))
          else:
            currentGame = newGame(WorldWidth, WorldHeight, settings.playerSkin, settings.bulletSkin, settings.playerShape, settings.particleEffect, settings.bulletShape)
            currentGame.discordClient = globalDiscordClient
            setGameMode(currentGame, gmTimeSurvival)
            var exactResume1 = false
            if pendingResume and hasSuspendSnapshot():
              if restoreGame(currentGame):
                if currentGame.state == gsPlaying:
                  currentGame.state = gsCountdown
                  currentGame.countdownTimer = 3.0
                exactResume1 = true
              else:
                deleteSuspendSnapshot()
            if exactResume1:
              discard
            elif pendingResume and applySavedRun(currentGame):
              initializeRunTracking(currentGame)
            else:
              deleteRunSave()
              deleteSuspendSnapshot()
              currentGame.state = gsPlaying
              initializeRunTracking(currentGame)
            statsSavedThisGame = false
        of 6:  # Sandbox Mode
          currentGame = newGame(WorldWidth, WorldHeight, settings.playerSkin, settings.bulletSkin, settings.playerShape, settings.particleEffect, settings.bulletShape)
          currentGame.discordClient = globalDiscordClient
          setGameMode(currentGame, gmSandbox)
          initializeRunTracking(currentGame)
          # Apply the loadout configured in the sandbox setup window.
          currentGame.sandboxConfig = globalWindowManager.sandbox.config
          applySandboxConfig(currentGame)
          currentGame.state = gsPlaying
          statsSavedThisGame = false
        of 9:  # Roguelite Mode, launched via the roguelite window Start button
          if not settings.rogueliteUnlocked:
            showDesktopToast(osDesktop, t(tkDesktopModeLocked) & " " & t(tkRogueliteLockedDesc))
          elif pendingResume:
            # Resume a saved roguelite run, bypassing the setup window.
            setActiveRogueliteProfile(loadRogueliteProfile())
            currentGame = newGame(WorldWidth, WorldHeight, settings.playerSkin, settings.bulletSkin, settings.playerShape, settings.particleEffect, settings.bulletShape)
            currentGame.discordClient = globalDiscordClient
            setGameMode(currentGame, gmRoguelite)
            currentGame.rogueliteProfile = rogueliteProfile
            # Exact snapshot first; restoreGame keeps the LIVE rogueliteProfile
            # (meta-currency earned after the snapshot is not rolled back) and
            # only the run-scoped state comes from the snapshot.
            var exactResume9 = false
            if hasSuspendSnapshot():
              if restoreGame(currentGame):
                if currentGame.state == gsPlaying:
                  currentGame.state = gsCountdown
                  currentGame.countdownTimer = 3.0
                currentGame.selectedRogueliteTheme = 0
                exactResume9 = true
              else:
                deleteSuspendSnapshot()
            if exactResume9:
              discard
            elif applySavedRun(currentGame):
              initializeRunTracking(currentGame)
              currentGame.selectedRogueliteTheme = 0
            else:
              deleteRunSave()
              deleteSuspendSnapshot()
              globalWindowManager.openWindow(widRoguelite)
              currentGame.state = gsMenu
            statsSavedThisGame = false
          else:
          # Setup was already done in the roguelite window; start the run directly.
            setActiveRogueliteProfile(loadRogueliteProfile())
            currentGame.rogueliteProfile = rogueliteProfile
            let starterKits9 = [rskOperator, rskBulwark, rskArcanist]
            let selectedIdx9 = clamp(currentGame.selectedRogueliteStarter, 0, starterKits9.high)
            let kit9 = starterKits9[selectedIdx9]
            let heat9 = clampedRogueliteHeatSelection(currentGame.selectedRogueliteHeat, rogueliteProfile)
            deleteRunSave()  # Fresh run of this mode discards any saved run.
            deleteSuspendSnapshot()
            beginRogueliteRun(currentGame, rogueliteProfile, kit9, heat9)
            initializeRunTracking(currentGame)
            generateThemeChoices(currentGame.rogueliteRun, unlockedBossTierOf(currentGame))
            currentGame.selectedRogueliteTheme = 0
            currentGame.state = gsRogueliteFloorSelect
            statsSavedThisGame = false
        else: discard
        pendingGameMode = -1  # Reset pending mode
        pendingResume = false

      # Handle window and desktop input
      let mousePos = getVirtualMousePosition()

      # Play click sound for any left-click on the desktop (anywhere)
      if isPointerPressed() and not globalConfirmActive:
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
          # Achievement reward: the orbital cube player cosmetic: the cube you
          # knocked out of orbit starts orbiting you. Equipped by default and
          # toggleable in the shop's SECRET tab.
          if not settings.orbitalCubeUnlocked:
            settings.orbitalCubeUnlocked = true
            settings.orbitalCubeEquipped = true
            discard saveSettings(settings)

      # Surface queued advancement unlocks (from runs or easter eggs) as OS
      # toasts; allow up to MAX_DESKTOP_TOASTS visible at once.
      while advancementProfile.recentUnlocks.len > 0 and
            osDesktop.toasts.len < MAX_DESKTOP_TOASTS and not globalConfirmActive:
        let unlockedId = advancementProfile.recentUnlocks[0]
        advancementProfile.recentUnlocks.delete(0)
        discard saveAdvancements(advancementProfile)
        let unlockedDef = getAdvancementDefinition(unlockedId)
        if unlockedDef.id.len > 0:
          showDesktopToast(osDesktop, t(tkDesktopAdvancementUnlocked) & ": " &
                           unlockedDef.name)

      # Handle OS desktop input and get action (only if no windows are blocking and confirm is not open)
      let action = if not mouseOverWindow and not globalConfirmActive and not resumePromptActive: handleDesktopInput(osDesktop, currentGame) else: -1

      # Update all windows
      let updateResult = globalWindowManager.updateAllWindows(dt, screenWidth, screenHeight, currentGame)

      # Handle fullscreen toggle from settings
      if updateResult.fullscreenToggle:
        fullscreenToggleRequested = true

      # Handle "Replay Intro" from the settings window: re-enter the lore cinematic
      if updateResult.replayIntro and not globalConfirmActive:
        loreCinematic = newLoreCinematic()
        currentGame.state = gsLoreIntro

      # Handle "Replay Ending" from the settings window: re-enter the outro. It
      # returns to the desktop (not the victory screen) since no run is active.
      if updateResult.replayEnding and not globalConfirmActive:
        endgameReplayMode = true
        endgameCinematicArmed = false  # force a fresh timeline on entry
        currentGame.state = gsEndgameCinematic

      # Replay the roguelite / survival outros from settings. Like the endgame
      # replay, these return to the desktop (no active run to resolve into).
      if updateResult.replayRogueliteEnding and not globalConfirmActive:
        rogueliteEndReplayMode = true
        rogueliteEndCinematicArmed = false
        currentGame.state = gsRogueliteEndCinematic

      if updateResult.replaySurvivalEnding and not globalConfirmActive:
        survivalEndReplayMode = true
        survivalEndCinematicArmed = false
        currentGame.state = gsSurvivalEndCinematic

      # Replay a per-mode opening cutscene from settings. These run through the
      # generic cutscene player and return to the desktop (cscMenu) rather than
      # launching the mode, so watching an intro never starts a run.
      block replayModeIntros:
        var intro: Cutscene = nil
        if updateResult.replayWaveIntro: intro = newWaveIntroCutscene()
        elif updateResult.replaySurvivalIntro: intro = newSurvivalIntroCutscene()
        elif updateResult.replayRogueliteIntro: intro = newRogueliteIntroCutscene()
        elif updateResult.replaySandboxIntro: intro = newSandboxIntroCutscene()
        elif updateResult.replayPvPIntro: intro = newPvPIntroCutscene()
        if intro != nil and not globalConfirmActive:
          activeCutscene = intro
          cutsceneContinuation = cscMenu
          currentGame.state = gsCutscene

      # Handle roguelite window Start button, show loading screen then enter game
      if updateResult.rogueliteLaunchGame and not globalConfirmActive:
        if not settings.hasSeenRogueliteIntro:
          settings.hasSeenRogueliteIntro = true
          discard saveSettings(settings)
          activeCutscene = newRogueliteIntroCutscene()
          cutsceneContinuation = cscLaunchGame
          pendingModeAfterCutscene = 9
          currentGame.state = gsCutscene
        else:
          startLoadingAnimation(osDesktop, "Launching Roguelite Mode...")
          pendingGameMode = 9

      # Handle sandbox setup window Start button: show loading screen, then launch.
      # The chosen loadout lives in globalWindowManager.sandbox.config and is read
      # back in the pendingGameMode == 6 branch above.
      if updateResult.sandboxLaunchGame and not globalConfirmActive:
        globalWindowManager.closeWindow(widSandbox)
        startLoadingAnimation(osDesktop, "Launching Sandbox Mode...")
        pendingGameMode = 6

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
          WorldWidth.int32,
          WorldHeight.int32,
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
          if not settings.hasSeenWaveModeIntro:
            settings.hasSeenWaveModeIntro = true
            discard saveSettings(settings)
            activeCutscene = newWaveIntroCutscene()
            cutsceneContinuation = cscLaunchGame
            pendingModeAfterCutscene = 0
            currentGame.state = gsCutscene
          elif (hasSavedRun() and loadSavedRunMode() == gmWaveBased) or
               hasBlockCheckpoint():
            # Offer resume for a live run save OR a death-surviving block
            # checkpoint (wave mode only).
            resumePromptActive = true
            resumePromptMode = gmWaveBased
          else:
            startLoadingAnimation(osDesktop, "Launching Wave-Based Mode...")
            pendingGameMode = 0
        of 1:  # Survival.exe - Time Survival Mode
          if not settings.hasSeenSurvivalIntro:
            settings.hasSeenSurvivalIntro = true
            discard saveSettings(settings)
            activeCutscene = newSurvivalIntroCutscene()
            cutsceneContinuation = cscLaunchGame
            pendingModeAfterCutscene = 1
            currentGame.state = gsCutscene
          elif hasSavedRun() and loadSavedRunMode() == gmTimeSurvival:
            resumePromptActive = true
            resumePromptMode = gmTimeSurvival
          else:
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
            showGlobalConfirm(cdcQuitToDesktop, cooldown = 0.0'f32)  # menu: no run to protect, confirm immediately
          else:
            windowCloseRequested = true
        of 7:  # Sandbox.exe - Open Sandbox Setup Window
          if not settings.hasSeenSandboxIntro:
            settings.hasSeenSandboxIntro = true
            discard saveSettings(settings)
            activeCutscene = newSandboxIntroCutscene()
            cutsceneContinuation = cscMenu  # returns to desktop; user clicks Sandbox again
            currentGame.state = gsCutscene
          else:
            openWindow(globalWindowManager, widSandbox)
            resetSandboxWindow(globalWindowManager.sandbox)
            playSound(stMenuSelect)
        of 8:  # PvP.exe - Open PvP Window
          if not settings.hasSeenPvPIntro:
            settings.hasSeenPvPIntro = true
            discard saveSettings(settings)
            activeCutscene = newPvPIntroCutscene()
            cutsceneContinuation = cscMenu  # returns to desktop; user clicks PvP again
            currentGame.state = gsCutscene
          else:
            openWindow(globalWindowManager, widPvP)
            resetPvPWindow(globalWindowManager.pvp)
            playSound(stMenuSelect)
        of 9:  # Roguelite.exe - Roguelite Mode
          if settings.rogueliteUnlocked and hasSavedRun() and loadSavedRunMode() == gmRoguelite:
            resumePromptActive = true
            resumePromptMode = gmRoguelite
          else:
            setActiveRogueliteProfile(loadRogueliteProfile())
            currentGame = newGame(WorldWidth, WorldHeight, settings.playerSkin, settings.bulletSkin, settings.playerShape, settings.particleEffect, settings.bulletShape)
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
        of 12: # CREDITS.nfo - Open Credits / Support Window
          globalWindowManager.openWindow(widCredits)
        else: discard

      # Handle icon execution from help window commands
      if updateResult.iconToExecute >= 0 and not globalConfirmActive:
        globalWindowManager.help.window.visible = false
        playSound(stMenuSelect)
        case updateResult.iconToExecute
          of 0:  # Play.exe - Wave-Based Mode
            if not settings.hasSeenWaveModeIntro:
              settings.hasSeenWaveModeIntro = true
              discard saveSettings(settings)
              activeCutscene = newWaveIntroCutscene()
              cutsceneContinuation = cscLaunchGame
              pendingModeAfterCutscene = 0
              currentGame.state = gsCutscene
            else:
              startLoadingAnimation(osDesktop, "Launching Wave-Based Mode...")
              pendingGameMode = 0
          of 1:  # Survival.exe - Time Survival Mode
            if not settings.hasSeenSurvivalIntro:
              settings.hasSeenSurvivalIntro = true
              discard saveSettings(settings)
              activeCutscene = newSurvivalIntroCutscene()
              cutsceneContinuation = cscLaunchGame
              pendingModeAfterCutscene = 1
              currentGame.state = gsCutscene
            else:
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
              showGlobalConfirm(cdcQuitToDesktop, cooldown = 0.0'f32)  # menu: no run to protect, confirm immediately
            else:
              windowCloseRequested = true
          of 7:  # Sandbox.exe - Open Sandbox Setup Window
            if not settings.hasSeenSandboxIntro:
              settings.hasSeenSandboxIntro = true
              discard saveSettings(settings)
              activeCutscene = newSandboxIntroCutscene()
              cutsceneContinuation = cscMenu  # returns to desktop; user clicks Sandbox again
              currentGame.state = gsCutscene
            else:
              openWindow(globalWindowManager, widSandbox)
              resetSandboxWindow(globalWindowManager.sandbox)
              playSound(stMenuSelect)
          of 8:  # PvP.exe - Open PvP Window
            if not settings.hasSeenPvPIntro:
              settings.hasSeenPvPIntro = true
              discard saveSettings(settings)
              activeCutscene = newPvPIntroCutscene()
              cutsceneContinuation = cscMenu
              currentGame.state = gsCutscene
            else:
              openWindow(globalWindowManager, widPvP)
              resetPvPWindow(globalWindowManager.pvp)
              playSound(stMenuSelect)
          of 9:  # Roguelite.exe
            setActiveRogueliteProfile(loadRogueliteProfile())
            currentGame = newGame(WorldWidth, WorldHeight, settings.playerSkin, settings.bulletSkin, settings.playerShape, settings.particleEffect, settings.bulletShape)
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
          of 11: # PATCHLOG.txt
            globalWindowManager.openWindow(widChangelog)
          of 12: # CREDITS.nfo
            globalWindowManager.openWindow(widCredits)
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

      # Resume-run prompt: Continue resumes the saved run, New Run discards it.
      if resumePromptActive:
        let resumeResult = drawResumeDialog(screenWidth, screenHeight)
        if resumeResult != 0:
          pendingResume = resumeResult == 1
          if resumeResult == -1:
            deleteRunSave()          # "New Run" discards the checkpoint,
            deleteBlockCheckpoint()  # the death-surviving block checkpoint,
            deleteSuspendSnapshot()  # and the exact snapshot.
          case resumePromptMode
          of gmTimeSurvival:
            startLoadingAnimation(osDesktop, "Launching Time Survival Mode...")
            pendingGameMode = 1
          of gmRoguelite:
            if resumeResult == 1:
              startLoadingAnimation(osDesktop, "Launching Roguelite Mode...")
              pendingGameMode = 9
            else:
              # Fresh roguelite goes through the setup window.
              setActiveRogueliteProfile(loadRogueliteProfile())
              currentGame = newGame(WorldWidth, WorldHeight, settings.playerSkin, settings.bulletSkin, settings.playerShape, settings.particleEffect, settings.bulletShape)
              currentGame.discordClient = globalDiscordClient
              currentGame.rogueliteProfile = rogueliteProfile
              setGameMode(currentGame, gmRoguelite)
              currentGame.state = gsMenu
              currentGame.selectedRogueliteStarter = 0
              currentGame.selectedRogueliteHeat = defaultRogueliteHeatSelection(rogueliteProfile)
              globalWindowManager.openWindow(widRoguelite)
              statsSavedThisGame = false
          else:
            startLoadingAnimation(osDesktop, "Launching Wave-Based Mode...")
            pendingGameMode = 0

      # Draw custom cursor on menu
      drawCustomCursor(currentGame.time)

      endGameDrawing()

    of gsPlaying:
      # Poll touch controls before any input is read this frame (input_intent
      # reads the resulting state). No-op / not compiled on desktop.
      when defined(mobile):
        updateMobileControls(dt)

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

      if currentGame.cheaterHatJustEarned:
        currentGame.cheaterHatJustEarned = false
        let newlyUnlocked = unlockAdvancementDirectly(advancementProfile, CheaterAdvancementId)
        if newlyUnlocked:
          discard saveAdvancements(advancementProfile)
        if not settings.cheaterHatUnlocked and
           (newlyUnlocked or isAdvancementUnlocked(advancementProfile, CheaterAdvancementId)):
          settings.cheaterHatUnlocked = true
          settings.cheaterHatEquipped = true
          settings.kernelTophatEquipped = false
          currentGame.player.wearsTophat = false
          currentGame.player.wearsCheaterHat = true
          discard saveSettings(settings)

      # Update cheat menu if active (pauses game)
      if cheatMenu.active:
        updateCheatMenu(cheatMenu, currentGame)

      # Roguelite cheat: "Skip Floor" sets a request flag (the cheat module can't
      # import game.nim); execute the floor-completion flow here where it can.
      if currentGame.cheatRogueliteSkipFloor:
        currentGame.cheatRogueliteSkipFloor = false
        cheatMenu.active = false
        cheatCompleteRogueliteFloor(currentGame)

      # Only process game input if cheat menu is not active and confirm dialog is not open
      if not cheatMenu.active and not globalConfirmActive:
        # Shop removed from gameplay - only accessible during power-up selection

        # Wall placement mode: hold (E / wall button) to preview range, release
        # to place. Placement target is the aim point (mouse on desktop, aim
        # joystick on mobile).
        const WALL_PLACEMENT_RANGE_SP = 250.0
        let eHeld = placeWallHeld() and currentGame.player.walls > 0
        currentGame.wallPlacementMode = eHeld

        # Releasing the wall control places the wall at the current aim target.
        # getAimTarget already returns WORLD coords (the wall lives in the
        # 1024-wide world, centered inside the wider virtual screen in
        # widescreen mode), so it agrees with the ghost preview in drawGame.
        if placeWallReleased() and currentGame.player.walls > 0:
          let wallPos = getAimTarget(currentGame.player.pos)
          let inRange = distance(wallPos, currentGame.player.pos) <= WALL_PLACEMENT_RANGE_SP
          if inRange and isValidWallPlacement(wallPos, currentGame.player.pos, currentGame.walls,
                                              currentGame.enemies, 25,
                                              currentGame.screenWidth, currentGame.screenHeight):
            currentGame.walls.add(newWall(wallPos.x, wallPos.y, currentGame.player))
            currentGame.player.walls -= 1
            spawnExplosionPooled(currentGame.particlePool, wallPos.x, wallPos.y, Brown, 15)
            trackWallPlacement(currentGame, wallPos)

      # Activate ALL legendary power-ups with the legendary control (key/pad on
      # desktop, ability button on mobile) -- simultaneous activation.
      if abilityPressed() and not globalConfirmActive:
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

          # Dash direction follows movement intent (WASD desktop / move stick mobile).
          var dashDir = abilityDirection()

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
              BLOOD_PACT_BONUS_MULT = 2.5'f32    # bonus damage per point of HP sacrificed
            let sacrifice = currentGame.player.hp * 0.2
            currentGame.player.hp = max(0.1, currentGame.player.hp - sacrifice)
            let bonus = sacrifice * BLOOD_PACT_BONUS_MULT

            for enemy in currentGame.enemies:
              if enemy.isBoss and enemy.invulnerabilityTimer > 0:
                continue  # respect phase-transition invulnerability
              let intended = if enemy.isBoss: enemy.maxHp * BLOOD_PACT_BOSS_FRAC + bonus * 0.4
                             else: enemy.maxHp * BLOOD_PACT_ENEMY_FRAC + bonus
              let dealt = applyEnemyHpDamage(enemy, intended)
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
              var burstDmg = ae.primary.remainingDuration * ae.primary.damagePerSec * 3.0
              if et == etPoison:
                # Detonating a ramped poison honors the stacks, then consumes them
                burstDmg *= poisonStackMultiplier(enemy)
                enemy.poisonStacks = 0
              let dealt = applyEnemyHpDamage(enemy, burstDmg)
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
                      let dealt = applyEnemyHpDamage(enemy, baseDamage)
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
      # In PvP the pause menu is shown but the sim keeps running (see gsPaused below).
      if pausePressed() and not globalConfirmActive:
        currentGame.state = gsPaused

      # Update game (only if cheat menu is not active and confirm dialog is not open)
      if not cheatMenu.active and not globalConfirmActive:
        if isSandboxMode(currentGame.mode):
          # Handle sandbox input
          handleSandboxInput(currentGame, currentGame.screenWidth, currentGame.screenHeight)
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

      # Drain subsystem-queued toasts (power-up installs, unlocks).
      for msg in currentGame.pendingToasts:
        showDesktopToast(osDesktop, msg)
      currentGame.pendingToasts.setLen(0)

      # Mythic flawless clear: game.nim raises the flag the frame wave mode is
      # won with no deaths on record. Event-driven, so syncAdvancements never
      # derives it -- this is the only place it can unlock.
      if currentGame.flawlessWaveVictory:
        currentGame.flawlessWaveVictory = false
        if unlockAdvancementDirectly(advancementProfile, FlawlessWaveAdvancementId):
          discard saveAdvancements(advancementProfile)
          if not globalWindowManager.isNil and not globalWindowManager.advancements.isNil:
            globalWindowManager.advancements.profile = advancementProfile
          showDesktopToast(osDesktop, t(tkDesktopAdvancementUnlocked) & ": " &
                           getAdvancementDefinition(FlawlessWaveAdvancementId).name)
          let queueIdx = advancementProfile.recentUnlocks.find(FlawlessWaveAdvancementId)
          if queueIdx >= 0:
            advancementProfile.recentUnlocks.delete(queueIdx)
          playSound(stPowerUp, 0.9)

      # Mid-run advancement sync: surface unlocks as desktop toasts.
      if not cheatMenu.active and not globalConfirmActive and
         not isSandboxMode(currentGame.mode) and not currentRunStats.isNil:
        advancementSyncTimer += dt
        if advancementSyncTimer >= 2.0'f32:
          advancementSyncTimer = 0.0'f32
          let liveUnlocks = syncAdvancements(advancementProfile, stats, currentRunStats,
                                             rogueliteProfile, liveRun = true)
          if liveUnlocks.len > 0:
            for unlockedDef in liveUnlocks:
              showDesktopToast(osDesktop, t(tkDesktopAdvancementUnlocked) & ": " & unlockedDef.name)
              # Already announced in-game; don't re-toast it on the desktop later.
              let queueIdx = advancementProfile.recentUnlocks.find(unlockedDef.id)
              if queueIdx >= 0:
                advancementProfile.recentUnlocks.delete(queueIdx)
            playSound(stPowerUp, 0.9)
            discard saveAdvancements(advancementProfile)

      beginGameDrawing()

      # Normal 2D rendering
      drawGame(currentGame)

      # Touch joysticks + action buttons, on top of the game/HUD (mobile only).
      when defined(mobile):
        drawMobileControls()

      # Draw sandbox UI if in sandbox mode
      if isSandboxMode(currentGame.mode):
        drawSandboxSidebar(currentGame, screenWidth, screenHeight)

      # Draw cheat menu overlay if active
      drawCheatMenu(cheatMenu, currentGame, screenWidth, screenHeight)

      # Alpha banner for roguelite mode
      if currentGame.mode == gmRoguelite:
        drawBetaBanner(currentGame)
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

      # Desktop toasts overlay (advancement unlocks etc.)
      tickDesktopToasts(osDesktop, dt)
      drawDesktopToastsOverlay(osDesktop, screenWidth, screenHeight)

      # Draw custom cursor during gameplay (after dialogs so it appears on top)
      drawCustomCursor(currentGame.time)

      endGameDrawing()

    of gsDeathSequence:
      updateGame(currentGame, dt)

      beginGameDrawing()
      drawGame(currentGame)
      drawDeathSequenceOverlay(currentGame)
      if currentGame.mode == gmRoguelite:
        drawBetaBanner(currentGame)
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
        if isKeyPressed(Left) or isKeyPressed(A) or isKeyPressed(Right) or isKeyPressed(D):
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
            saveRunState(currentGame)
            suspendGame(currentGame)  # Exact mid-run snapshot (primary resume path).
            cleanupGame(currentGame)
            currentGame = newGame(WorldWidth, WorldHeight, settings.playerSkin, settings.bulletSkin, settings.playerShape, settings.particleEffect, settings.bulletShape)
            currentGame.discordClient = globalDiscordClient
            currentGame.state = gsMenu
            playSound(stMenuSelect)
          elif not currentGame.confirmQuitPending:
            currentGame.confirmQuitPending = true
            currentGame.pauseMenuExitCooldown = 2.0         # countdown shown inside dialog
            currentGame.confirmQuitFrameGuard = 0.15  # prevent same-frame auto-confirm in dialog
            playSound(stMenuNav)
        elif (isBackPressed() or isGamepadStartPressed()):  # ESC cancels confirm dialog, or resumes
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
            saveRunState(currentGame)
            suspendGame(currentGame)  # Exact mid-run snapshot (primary resume path).
            cleanupGame(currentGame)
            currentGame = newGame(WorldWidth, WorldHeight, settings.playerSkin, settings.bulletSkin, settings.playerShape, settings.particleEffect, settings.bulletShape)
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
        drawBetaBanner(currentGame)

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
          saveRunState(currentGame)
          suspendGame(currentGame)  # Exact mid-run snapshot (primary resume path).
          cleanupGame(currentGame)
          currentGame = newGame(WorldWidth, WorldHeight, settings.playerSkin, settings.bulletSkin, settings.playerShape, settings.particleEffect, settings.bulletShape)
          currentGame.discordClient = globalDiscordClient
          currentGame.state = gsMenu
          playSound(stMenuSelect)
        elif confirmDlg.cancelled:
          currentGame.confirmQuitPending = false
          currentGame.pauseMenuExitCooldown = 2.0  # prevent immediate re-trigger

      # Draw custom cursor on top of everything (including the confirm dialog)
      drawCustomCursor(currentGame.time)

      endGameDrawing()

    of gsRogueliteFloorSelect:
      playMusic(mtMenu)
      currentGame.time += dt
      updateMouseTracking(currentGame)

      # The final floor offers a single card, so there is nothing to navigate.
      if isKeyPressed(Left) or isKeyPressed(A):
        if not globalConfirmActive and not isFinalDungeonFloor(currentGame.rogueliteRun):
          currentGame.selectedRogueliteTheme = (currentGame.selectedRogueliteTheme - 1 + 3) mod 3
          markKeyboardUsed(currentGame)
      if isKeyPressed(Right) or isKeyPressed(D):
        if not globalConfirmActive and not isFinalDungeonFloor(currentGame.rogueliteRun):
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
        currentGame = newGame(WorldWidth, WorldHeight, settings.playerSkin, settings.bulletSkin, settings.playerShape, settings.particleEffect, settings.bulletShape)
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
        if not globalConfirmActive:
          if settings.exitConfirmEnabled: showGlobalConfirm(cdcQuitToMenu)
          else: closeRogueliteFloorSelect()

      if isPointerPressed() and not globalConfirmActive:
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
          if settings.exitConfirmEnabled: showGlobalConfirm(cdcQuitToMenu)
          else: closeRogueliteFloorSelect()
        elif isFinalDungeonFloor(currentGame.rogueliteRun):
          if checkCollisionPointRec(mousePos, finalBossCardRect(screenWidth.int32, screenHeight.int32)):
            currentGame.selectedRogueliteTheme = 0
            startSelectedTheme()
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

      # Draw the confirm dialog on top of everything. Two triggers share it here:
      # the OS close button (cdcQuitToDesktop -> quit app) and the in-screen Q /
      # panel-close exit (cdcQuitToMenu -> abandon back to the roguelite setup).
      if globalConfirmActive:
        let r = drawGlobalConfirmDialog(screenWidth, screenHeight)
        if r == 1:
          if globalConfirmContext == cdcQuitToDesktop: windowCloseRequested = true
          else: closeRogueliteFloorSelect()

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
        if isPointerPressed():
          let mousePos = getVirtualMousePosition()

          # Geometry comes straight from os_shop.nim's layout, so widescreen
          # (which widens the panel and the rows) needs no change here.
          let L = shopLayout()

          if checkCollisionPointRec(mousePos, L.closeRect()):
            # Close shop and continue to next wave
            currentGame.cameFromPowerUpSelect = false
            if currentGame.mode == gmRoguelite:
              # In the dungeon the shop is a room: just step back into it.
              currentGame.state = gsPlaying
            else:
              currentGame.state = gsCountdown
              currentGame.countdownTimer = 0.5
          else:
            # Check shop item clicks
            var clickedItem = -1
            for i in 0..5:
              if checkCollisionPointRec(mousePos, L.itemRect(i)):
                clickedItem = i
                break

            if clickedItem >= 0:
              # Clicked on an item - select and buy it
              currentGame.selectedShopItem = clickedItem
              buyShopItem(currentGame, clickedItem)
            elif checkCollisionPointRec(mousePos, L.buyRect()):
              # Clicked the buy button - buy selected item
              buyShopItem(currentGame, currentGame.selectedShopItem)

        # Buy item with keyboard
        if isKeyPressed(Enter) or isKeyPressed(E):
          buyShopItem(currentGame, currentGame.selectedShopItem)

        # Close shop - ESC is intentionally not bound here; only the legendary key or the in-window X button may close it.
        if (isKeyPressed(globalSettings.keybinds[kaLegendary]) or isGamepadBindPressed(globalSettings.gamepadBinds, kaLegendary)) and not globalConfirmActive:
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
        drawBetaBanner(currentGame)

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
        drawBetaBanner(currentGame)

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
      updatePlayer(currentGame.player, dt, currentGame.screenWidth, currentGame.screenHeight, currentGame.walls)

      # Update coins and handle collection
      updateCoinsWaveCleared(currentGame, dt)

      # Update particles and remove dead ones

      # Transition to power-up selection or next wave
      # (the roguelite dungeon never enters gsWaveCleared; rooms resolve inline)
      if currentGame.waveClearedTimer <= 0:
        block waveClearedAdvance:
          let shouldOfferPowerUp = currentGame.cameFromPowerUpSelect

          if shouldOfferPowerUp and not currentGame.bossWaveManager.isBossCoinActive():
            # Determine if it's a boss wave power-up
            let isBossWave = currentGame.wavesUntilBoss <= 0

            # A power-up is always offered, boss wave or not (before a boss it is the
            # critical moment); a boss wave additionally gets a longer warning.
            if isBossWave:
              currentGame.bossSpawnTimer = 2.0
            currentGame.powerUpChoices = generatePowerUpChoices(currentGame.player, false, mode = currentGame.mode)

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
        drawBetaBanner(currentGame)

      # Draw OS-close confirmation dialog on top of everything if triggered by close button
      if globalConfirmActive:
        let r = drawGlobalConfirmDialog(screenWidth, screenHeight)
        if r == 1: windowCloseRequested = true

      endGameDrawing()

    of gsPowerUpSelect:
      let isLegendaryRound = currentGame.powerUpChoices[0].rarity == prLegendary
      let allowedFamiliesForDraft =
        if currentGame.mode == gmRoguelite and currentGame.rogueliteProfile != nil:
          currentGame.rogueliteProfile.unlockedPowerFamilies
        else:
          {rpfCore..rpfBlood}

      proc continueAfterDraft() =
        ## Route out of the draft screen. Classic modes visit the between-wave
        ## shop; the dungeon returns to the room (or the next floor select
        ## after a floor boss).
        currentGame.cameFromPowerUpSelect = true
        if currentGame.mode == gmRoguelite and currentGame.rogueliteRun != nil:
          if currentGame.rogueliteRun.pendingFloorSelect:
            if currentGame.cheatRogueliteDirectFloorSelect:
              # Cheat "Skip Floor": the boss-room exit portal may be unreachable
              # (the cheat can fire from any room), so jump straight to floor
              # select, mirroring what walking into the portal would do.
              currentGame.cheatRogueliteDirectFloorSelect = false
              generateThemeChoices(currentGame.rogueliteRun, unlockedBossTierOf(currentGame))
              currentGame.selectedRogueliteTheme = 0
              currentGame.state = gsRogueliteFloorSelect
            else:
              # Floor boss is down: drop the player back into the cleared boss room
              # with the exit portal open. The descent only happens once they walk
              # into it (updateDungeon), not automatically.
              spawnRogueliteExitPortal(currentGame)
              currentGame.state = gsPlaying
          else:
            currentGame.cheatRogueliteDirectFloorSelect = false
            currentGame.state = gsPlaying
        elif isTimeSurvivalMode(currentGame.mode) and currentGame.survivalLevelDraftActive:
          # Survival mid-run level-up draft: resume into the same battlefield,
          # not the shop (the shop is reserved for the post-boss draft below).
          currentGame.survivalLevelDraftActive = false
          currentGame.state = gsPlaying
        else:
          currentGame.state = gsShop
          currentGame.shopSidebarScroll = 0

      updateOSHUD(currentGame.osHUD, dt)
      tickDesktopToasts(osDesktop, dt)
      for msg in currentGame.pendingToasts:
        showDesktopToast(osDesktop, msg)
      currentGame.pendingToasts.setLen(0)

      if isPowerUpPoolExhausted(currentGame.player, isLegendaryRound, allowedFamiliesForDraft, currentGame.mode):
        playMusic(mtPowerUp)

        if not globalConfirmActive:
          if isKeyPressed(Enter) or isKeyPressed(E) or isKeyPressed(Space):
            continueAfterDraft()

          if isPointerPressed():
            let mousePos = getVirtualMousePosition()
            # Geometry comes straight from os_powerup_installer.nim's layout,
            # which already accounts for the wider 16:9 panel.
            let L = installerLayout()
            if checkCollisionPointRec(mousePos, L.continueRect()) or
               checkCollisionPointRec(mousePos, L.closeRect()):
              continueAfterDraft()

        beginGameDrawing()
        drawPowerUpSelectionExhausted(currentGame)
        if currentGame.mode == gmRoguelite:
          drawBetaBanner(currentGame)
        if globalConfirmActive:
          let r = drawGlobalConfirmDialog(screenWidth, screenHeight)
          if r == 1: windowCloseRequested = true
        drawDesktopToastsOverlay(osDesktop, screenWidth, screenHeight)
        drawCustomCursor(currentGame.time)
        endGameDrawing()

      else:
        # Play power-up selection music
        playMusic(mtPowerUp)

        # Update roll animation
        updatePowerUpRollAnimation(currentGame, dt)

        # Update mouse tracking
        updateMouseTracking(currentGame)

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
            let coinsPreReroll = currentGame.player.coins
            if attemptRerollPowerUps(currentGame):
              recordRerollSpent(coinsPreReroll - currentGame.player.coins)
              markKeyboardUsed(currentGame)
            # If reroll failed (not enough coins), do nothing (could add sound here)

          # Mouse hover detection for card selection (only if keyboard not recently used)
          if isPointerPressed() or currentGame.mouseMovedRecently:
            let mousePos = getVirtualMousePosition()
            # Card geometry comes straight from os_powerup_installer.nim's layout.
            let L = installerLayout()

            # Check which card mouse is over - only if keyboard wasn't just used
            if not currentGame.keyboardUsedRecently:
              for i in 0..2:
                if checkCollisionPointRec(mousePos, L.cardRect(i)):
                  currentGame.selectedPowerUp = i
                  break

          # Select power-up with keyboard or mouse click on card
          if isKeyPressed(Enter) or isKeyPressed(E):
            let chosenPowerUp = currentGame.powerUpChoices[currentGame.selectedPowerUp]
            installPowerUp(currentGame, chosenPowerUp)
            continueAfterDraft()

          # Mouse click to select
          if isPointerPressed():
            let mousePos = getVirtualMousePosition()
            # Card / button geometry comes straight from os_powerup_installer.nim.
            let L = installerLayout()

            if checkCollisionPointRec(mousePos, L.closeRect()):
              # Close installer without picking
              continueAfterDraft()
            else:
              # Check card clicks
              for i in 0..2:
                if checkCollisionPointRec(mousePos, L.cardRect(i)):
                  currentGame.selectedPowerUp = i
                  let chosenPowerUp = currentGame.powerUpChoices[currentGame.selectedPowerUp]
                  installPowerUp(currentGame, chosenPowerUp)
                  continueAfterDraft()
                  break

              # Check reroll button click
              if checkCollisionPointRec(mousePos, L.rerollRect()):
                let coinsPreReroll = currentGame.player.coins
                if attemptRerollPowerUps(currentGame):
                  recordRerollSpent(coinsPreReroll - currentGame.player.coins)

          # ESC is intentionally not bound here; only the in-window X button may close
          # this screen without selecting a power-up.

        beginGameDrawing()
        drawPowerUpSelection(currentGame)
        if currentGame.mode == gmRoguelite:
          drawBetaBanner(currentGame)

        # Draw quit-confirmation dialog on top of everything if triggered by OS close button
        if globalConfirmActive:
          let r = drawGlobalConfirmDialog(screenWidth, screenHeight)
          if r == 1: windowCloseRequested = true

        drawDesktopToastsOverlay(osDesktop, screenWidth, screenHeight)
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

      # A death-surviving wave-mode block checkpoint prepends a "Continue" option,
      # shifting Restart/Stats/Exit indices up by one (idxOff).
      let goShowContinue = currentGame.mode == gmWaveBased and hasBlockCheckpoint()
      let goOptionCount = if goShowContinue: 4 else: 3
      let goIdxOff = if goShowContinue: 1 else: 0
      let goRestartIdx = goIdxOff
      let goStatsIdx = goIdxOff + 1
      let goExitIdx = goIdxOff + 2

      # Nested action helpers (shared by keyboard, gamepad and mouse dispatch).
      proc doContinue() =
        currentGame = newGame(WorldWidth, WorldHeight, settings.playerSkin, settings.bulletSkin, settings.playerShape, settings.particleEffect, settings.bulletShape)
        currentGame.discordClient = globalDiscordClient
        setGameMode(currentGame, gmWaveBased)
        # Resume the saved block; NO comeback bonus on this path.
        if applyBlockCheckpoint(currentGame):
          # Same run, resumed: keep the accumulated run statistics (power-ups
          # collected, kills, damage, time) instead of zeroing them.
          # Pressing Continue is what voids the Flawless Kernel advancement.
          currentGame.runHadDeath = true
          resumeRunTracking(currentGame)
        else:
          # Checkpoint failed to apply: fall back to a fresh run.
          currentGame.state = gsPlaying
          initializeRunTracking(currentGame)
        playSound(stMenuSelect)
        statsSavedThisGame = false

      proc doRestart() =
        let previousMode = currentGame.mode
        let preservedRogueliteHeat =
          if previousMode == gmRoguelite and currentGame.rogueliteRun != nil:
            currentGame.rogueliteRun.heat
          else:
            currentGame.selectedRogueliteHeat
        # An explicit restart abandons the checkpointed run (the confirm dialog
        # already warned that Continue was still available), exactly like the
        # menu's "New Run". Keeping the file would let a fresh wave-1 run die at
        # wave 2 and still offer "Continue (Wave 21)" from the discarded run.
        if previousMode == gmWaveBased:
          deleteBlockCheckpoint()
        currentGame = newGame(WorldWidth, WorldHeight, settings.playerSkin, settings.bulletSkin, settings.playerShape, settings.particleEffect, settings.bulletShape)
        currentGame.discordClient = globalDiscordClient
        setGameMode(currentGame, previousMode)  # Preserve the game mode
        applyComebackBonus(currentGame)
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

      proc doStats() =
        if hasValidRunStats():
          openRunStatsWindow()
          currentGame.state = gsRunStats
          playSound(stMenuSelect)

      proc doExit() =
        cleanupGame(currentGame)  # Clean up resources before creating new game
        currentGame = newGame(WorldWidth, WorldHeight, settings.playerSkin, settings.bulletSkin, settings.playerShape, settings.particleEffect, settings.bulletShape)
        currentGame.discordClient = globalDiscordClient
        currentGame.state = gsMenu
        playSound(stMenuSelect)
        statsSavedThisGame = false  # Reset for new game

      # When a checkpoint is available, Restart/Exit first ask for confirmation so
      # the player can't accidentally lose the chance to continue their run.
      proc requestRestart() =
        if goShowContinue: showGlobalConfirm(cdcAbandonRestart, 1.0)
        else: doRestart()

      proc requestExit() =
        if goShowContinue: showGlobalConfirm(cdcAbandonExit, 1.0)
        elif settings.exitConfirmEnabled: showGlobalConfirm(cdcPostGameExit, cooldown = 0.0'f32)
        else: doExit()

      # Keyboard navigation - A/D/LEFT/RIGHT to change button selection.
      # All game-over input is gated on `not globalConfirmActive` so the quit-confirm
      # popup (OS close button) owns the keyboard/mouse while it is up; otherwise a
      # single Escape/Q/click would both answer the dialog and fire a menu action.
      if not globalConfirmActive and (isKeyPressed(Left) or isKeyPressed(A)):
        currentGame.selectedGameOverButton = (currentGame.selectedGameOverButton - 1 + goOptionCount) mod goOptionCount
        playSound(stMenuNav)
        markKeyboardUsed(currentGame)
      elif not globalConfirmActive and (isKeyPressed(Right) or isKeyPressed(D)):
        currentGame.selectedGameOverButton = (currentGame.selectedGameOverButton + 1) mod goOptionCount
        playSound(stMenuNav)
        markKeyboardUsed(currentGame)

      # Execute action based on selected button or direct key press.
      # C directly triggers Continue when the option is available.
      if not globalConfirmActive and goShowContinue and
         (isKeyPressed(C) or (isKeyPressed(Enter) and currentGame.selectedGameOverButton == 0)):
        doContinue()
      # SPACE and R both trigger restart
      elif not globalConfirmActive and ((isKeyPressed(Space) or isKeyPressed(R)) or
         (isKeyPressed(Enter) and currentGame.selectedGameOverButton == goRestartIdx)):
        requestRestart()
      # TAB or V to view stats
      elif not globalConfirmActive and ((isKeyPressed(Tab) or isKeyPressed(V)) or
           (isKeyPressed(Enter) and currentGame.selectedGameOverButton == goStatsIdx)):
        doStats()
      # ESC or Q to exit
      elif not globalConfirmActive and ((isBackPressed() or isKeyPressed(Q)) or
           (isKeyPressed(Enter) and currentGame.selectedGameOverButton == goExitIdx)):
        requestExit()

      # Mouse hover detection for button highlighting. Layout must mirror
      # drawSystemCrash (narrower buttons/spacing when Continue is present).
      let mousePos = getVirtualMousePosition()
      const SCREEN_HEIGHT = 600
      const BUTTON_HEIGHT = 48

      let goButtonW = if goShowContinue: 200 else: 220
      let goButtonSpacing = if goShowContinue: 24 else: 40
      let windowY = (screenHeight - SCREEN_HEIGHT) div 2
      let buttonY = windowY + SCREEN_HEIGHT - 100
      let totalButtonWidth = goButtonW * goOptionCount + goButtonSpacing * (goOptionCount - 1)
      let buttonsX = (screenWidth - totalButtonWidth) div 2

      proc goButtonRect(slot: int): Rectangle =
        # slot is the on-screen position (0-based) left-to-right.
        let x = buttonsX + slot * (goButtonW + goButtonSpacing)
        Rectangle(x: x.float32, y: buttonY.float32,
                  width: goButtonW.float32, height: BUTTON_HEIGHT.float32)

      # Optional Continue at slot 0; then Restart/Stats/Exit.
      let continueRect = goButtonRect(0)
      let restartRect = goButtonRect(goIdxOff)
      let statsRect = goButtonRect(goIdxOff + 1)
      let exitRect = goButtonRect(goIdxOff + 2)

      # Mouse hover - update selected button
      if goShowContinue and checkCollisionPointRec(mousePos, continueRect):
        currentGame.selectedGameOverButton = 0
      elif checkCollisionPointRec(mousePos, restartRect):
        currentGame.selectedGameOverButton = goRestartIdx
      elif checkCollisionPointRec(mousePos, statsRect):
        currentGame.selectedGameOverButton = goStatsIdx
      elif checkCollisionPointRec(mousePos, exitRect):
        currentGame.selectedGameOverButton = goExitIdx

      # Mouse click handling
      if not globalConfirmActive and isPointerPressed():
        if goShowContinue and checkCollisionPointRec(mousePos, continueRect):
          doContinue()
        elif checkCollisionPointRec(mousePos, restartRect):
          requestRestart()
        elif checkCollisionPointRec(mousePos, statsRect):
          doStats()
        elif checkCollisionPointRec(mousePos, exitRect):
          requestExit()

      beginGameDrawing()
      drawGameOver(currentGame)

      # Confirmation dialog: OS close button (quit contexts) or the
      # abandon-checkpoint guard on Restart/Exit.
      if globalConfirmActive:
        let r = drawGlobalConfirmDialog(screenWidth, screenHeight)
        if r == 1:
          case globalConfirmContext
          of cdcAbandonRestart: doRestart()
          of cdcAbandonExit, cdcPostGameExit: doExit()
          else: windowCloseRequested = true
        # r == -1: cancelled, dialog already dismissed

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

      proc doReturnToMenuFromStats() =
        statsWin.window.visible = false
        cleanupGame(currentGame)  # Clean up resources before creating new game
        currentGame = newGame(WorldWidth, WorldHeight, settings.playerSkin, settings.bulletSkin, settings.playerShape, settings.particleEffect, settings.bulletShape)
        currentGame.discordClient = globalDiscordClient
        currentGame.state = gsMenu
        statsSavedThisGame = false

      # Return to the screen we came from (victory or game over) with
      # Tab/Escape or the window's close button. Gated on the confirm dialog
      # so Escape cancels the dialog instead of also leaving this screen.
      let statsReturnState =
        if currentGame.previousState == gsVictory: gsVictory else: gsGameOver
      if not globalConfirmActive and (statsWindowClosed or isKeyPressed(Tab) or isBackPressed()):
        statsWin.window.visible = false
        currentGame.state = statsReturnState

      # Quick restart
      if not globalConfirmActive and isKeyPressed(R):
        statsWin.window.visible = false
        let previousMode = currentGame.mode
        let preservedRogueliteHeat =
          if previousMode == gmRoguelite and currentGame.rogueliteRun != nil:
            currentGame.rogueliteRun.heat
          else:
            currentGame.selectedRogueliteHeat
        # Same abandon rule as the game-over Restart button.
        if previousMode == gmWaveBased:
          deleteBlockCheckpoint()
        currentGame = newGame(WorldWidth, WorldHeight, settings.playerSkin, settings.bulletSkin, settings.playerShape, settings.particleEffect, settings.bulletShape)
        currentGame.discordClient = globalDiscordClient
        setGameMode(currentGame, previousMode)
        applyComebackBonus(currentGame)
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

      # Return to menu, asking for confirmation first (unless disabled in settings)
      if not globalConfirmActive and isKeyPressed(Q):
        if settings.exitConfirmEnabled: showGlobalConfirm(cdcPostGameExit, cooldown = 0.0'f32)
        else: doReturnToMenuFromStats()

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

      if globalConfirmActive:
        let r = drawGlobalConfirmDialog(screenWidth, screenHeight)
        if r == 1:
          case globalConfirmContext
          of cdcPostGameExit: doReturnToMenuFromStats()
          else: windowCloseRequested = true

      drawCustomCursor(currentGame.time)
      endGameDrawing()

    of gsVictory:
      # One-time congratulations screen shown after the wave-60 final boss.
      # Three choices: continue endlessly, view detailed stats, or return to menu.
      currentGame.time += dt
      updateMouseTracking(currentGame)

      proc doReturnToMenuFromVictory() =
        # Return to menu: the run ends here, so persist results before leaving
        playSound(stMenuSelect)
        persistRunResults(currentGame)
        cleanupGame(currentGame)
        currentGame = newGame(WorldWidth, WorldHeight, settings.playerSkin, settings.bulletSkin, settings.playerShape, settings.particleEffect, settings.bulletShape)
        currentGame.discordClient = globalDiscordClient
        currentGame.state = gsMenu
        statsSavedThisGame = false

      proc requestReturnToMenuFromVictory() =
        if settings.exitConfirmEnabled: showGlobalConfirm(cdcPostGameExit, cooldown = 0.0'f32)
        else: doReturnToMenuFromVictory()

      # Keyboard navigation across the 3 buttons
      if not globalConfirmActive and (isKeyPressed(Left) or isKeyPressed(A)):
        currentGame.selectedVictoryButton = (currentGame.selectedVictoryButton - 1 + 3) mod 3
        playSound(stMenuNav)
        markKeyboardUsed(currentGame)
      elif not globalConfirmActive and (isKeyPressed(Right) or isKeyPressed(D)):
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
      if not globalConfirmActive:
        if checkCollisionPointRec(vicMousePos, continueRect):
          currentGame.selectedVictoryButton = 0
        elif checkCollisionPointRec(vicMousePos, vicStatsRect):
          currentGame.selectedVictoryButton = 1
        elif checkCollisionPointRec(vicMousePos, vicMenuRect):
          currentGame.selectedVictoryButton = 2

      # Resolve the chosen action: keyboard (Enter/Space/V/Tab/Esc/Q) or mouse click
      var victoryAction = -1  # 0=continue, 1=stats, 2=menu
      if not globalConfirmActive:
        if isKeyPressed(Space) or (isKeyPressed(Enter) and currentGame.selectedVictoryButton == 0):
          victoryAction = 0
        elif (isKeyPressed(Tab) or isKeyPressed(V)) or
             (isKeyPressed(Enter) and currentGame.selectedVictoryButton == 1):
          victoryAction = 1
        elif (isBackPressed() or isKeyPressed(Q)) or
             (isKeyPressed(Enter) and currentGame.selectedVictoryButton == 2):
          victoryAction = 2
        elif isPointerPressed():
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
        # Return to menu, asking for confirmation first (unless disabled in settings)
        requestReturnToMenuFromVictory()
      else:
        discard

      beginGameDrawing()
      drawVictory(currentGame)
      if globalConfirmActive:
        let r = drawGlobalConfirmDialog(screenWidth, screenHeight)
        if r == 1:
          case globalConfirmContext
          of cdcPostGameExit: doReturnToMenuFromVictory()
          else: windowCloseRequested = true
      drawCustomCursor(currentGame.time)
      endGameDrawing()

    of gsRogueliteVictory:
      # Roguelite ending screen: the final floor boss is down and the win is already
      # banked. Two choices: push deeper into the endless loop, or cash out and
      # return to the roguelite hub. selectedVictoryButton: 0=continue, 1=cash out.
      playMusic(mtMenu)
      currentGame.time += dt
      updateMouseTracking(currentGame)
      tickDesktopToasts(osDesktop, dt)
      for msg in currentGame.pendingToasts:
        showDesktopToast(osDesktop, msg)
      currentGame.pendingToasts.setLen(0)

      if isKeyPressed(Left) or isKeyPressed(A) or isKeyPressed(Right) or isKeyPressed(D):
        currentGame.selectedVictoryButton = (currentGame.selectedVictoryButton + 1) mod 2
        playSound(stMenuNav)
        markKeyboardUsed(currentGame)

      let rvRects = rogueliteVictoryButtonRects(screenWidth.int32, screenHeight.int32)
      let rvMousePos = getVirtualMousePosition()
      if checkCollisionPointRec(rvMousePos, rvRects.continueBtn):
        currentGame.selectedVictoryButton = 0
      elif checkCollisionPointRec(rvMousePos, rvRects.cashOut):
        currentGame.selectedVictoryButton = 1

      # Resolve: 0=continue endless, 1=cash out. Enter follows the highlighted button.
      var rvAction = -1
      if isKeyPressed(Space) or (isKeyPressed(Enter) and currentGame.selectedVictoryButton == 0):
        rvAction = 0
      elif (isBackPressed() or isKeyPressed(Q)) or
           (isKeyPressed(Enter) and currentGame.selectedVictoryButton == 1):
        rvAction = 1
      elif isPointerPressed():
        if checkCollisionPointRec(rvMousePos, rvRects.continueBtn): rvAction = 0
        elif checkCollisionPointRec(rvMousePos, rvRects.cashOut): rvAction = 1

      case rvAction
      of 0:
        # Push deeper: roll into the next endless loop and take the queued post-boss
        # draft (prepared in game.nim) as this floor's reward.
        playSound(stMenuSelect)
        if currentGame.rogueliteRun != nil:
          rogueliteContinueEndless(currentGame.rogueliteRun)
        initPowerUpRollAnimation(currentGame)
        currentGame.state = gsPowerUpSelect
      of 1:
        # Cash out: the win is already banked, so persist the run record and return
        # to the roguelite hub window (mirrors closing the floor-select).
        playSound(stMenuSelect)
        let preservedHeat = currentGame.selectedRogueliteHeat
        persistRunResults(currentGame)
        cleanupGame(currentGame)
        currentGame = newGame(WorldWidth, WorldHeight, settings.playerSkin, settings.bulletSkin, settings.playerShape, settings.particleEffect, settings.bulletShape)
        currentGame.discordClient = globalDiscordClient
        setGameMode(currentGame, gmRoguelite)
        currentGame.rogueliteProfile = rogueliteProfile
        currentGame.selectedRogueliteHeat = clampedRogueliteHeatSelection(preservedHeat, rogueliteProfile)
        globalWindowManager.openWindow(widRoguelite)
        currentGame.state = gsMenu
        statsSavedThisGame = false
      else:
        discard

      beginGameDrawing()
      drawRogueliteVictory(currentGame)
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

      when defined(mobile):
        # Same twin-stick controls as single-player; capturePlayerInput reads
        # them through input_intent. Must run before updatePvP so this frame's
        # captured input is current.
        updateMobileControls(dt)

      # Check for pause (visual only - game continues running)
      if (isBackPressed() or pausePressed()) and not currentPvPGame.gameOver:
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
      if currentPvPGame.gameOver and isBackPressed():
        # Send disconnect packet to notify opponent (graceful disconnect)
        if currentPvPGame.networkManager != nil and currentPvPGame.networkManager.isConnected:
          disconnect(currentPvPGame.networkManager, "Player left to menu")

        # Clean up network
        if currentPvPGame.networkManager != nil:
          cleanup(currentPvPGame.networkManager)

        # Clear PvP game state
        currentPvPGame = nil

        # Return to menu
        currentGame = newGame(WorldWidth, WorldHeight, settings.playerSkin,
                             settings.bulletSkin, settings.playerShape, settings.particleEffect, settings.bulletShape)
        currentGame.discordClient = globalDiscordClient
        currentGame.state = gsMenu
        continue  # Skip drawing, go to next frame

      beginGameDrawing()
      drawPvP(currentPvPGame)
      when defined(mobile):
        drawMobileControls()
      drawCustomCursor(currentPvPGame.gameTime)
      endGameDrawing()

  # Checkpoint the live run on shutdown so it can be resumed next launch.
  if not currentGame.isNil:
    saveRunState(currentGame)
    suspendGame(currentGame)  # Exact snapshot: the primary resume path on relaunch.

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

when defined(android):
  # Android entry point. The app is built as a shared library (--app:lib), whose
  # real entry is raylib's `android_main` (native_app_glue), which in turn calls
  # the C `main` symbol. Nim's --app:lib emits `NimMain` (runtime + GC init) but
  # no C `main`, so we export one: init the Nim runtime, then run the game. The
  # desktop `when isMainModule: main()` auto-run is suppressed here so the game
  # doesn't also start from inside NimMain.
  proc NimMain() {.importc.}
  proc androidEntry(argc: cint, argv: ptr cstring): cint {.exportc: "main", cdecl.} =
    NimMain()
    main()
    return 0
else:
  when isMainModule:
    main()
