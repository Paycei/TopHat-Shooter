## OS Window Manager
## Centralized window handling with state management

import raylib, algorithm, sequtils
import os_window, settings_window, help_window, stats_window, shop_window, pvp_window, sandbox_window, advancements_window, roguelite_window, changelog_window, ../types, ../settings, ../save_system, ../statistics, ../skins, ../bullet_skins, ../bullet_shapes, ../shapes, ../particle_skins, ../advancement
import ../gamepad_input

type
  WindowID* = enum
    widSettings
    widHelp
    widStats
    widShop
    widPvP
    widSandbox
    widAdvancements
    widRoguelite
    widChangelog

  WindowManager* = ref object
    settings*: SettingsWindow
    help*: HelpWindow
    stats*: StatsWindow
    shop*: ShopWindow
    pvp*: PvPWindow
    sandbox*: SandboxWindow
    advancements*: AdvancementsWindow
    roguelite*: RogueliteWindow
    changelog*: ChangelogWindow
    nextZOrder: int

proc newWindowManager*(screenWidth, screenHeight: int,
                       gameSettings: Settings,
                       gameStats: Statistics,
                       advancementProfile: AdvancementProfile,
                       rogueliteProfile: RogueliteProfile): WindowManager =
  ## Create a new window manager with all windows pre-initialized
  result = WindowManager(
    settings: newSettingsWindow(screenWidth, screenHeight, gameSettings,
                                gameStats, advancementProfile, rogueliteProfile),
    help: newHelpWindow(screenWidth, screenHeight),
    stats: newStatsWindow(screenWidth, screenHeight, gameStats),
    shop: newShopWindow(screenWidth, screenHeight,
                       SkinType(gameSettings.playerSkin),
                       BulletSkinType(gameSettings.bulletSkin),
                       ShapeType(gameSettings.playerShape),
                       ParticleSkinType(gameSettings.particleEffect),
                       BulletShapeType(gameSettings.bulletShape),
                       rogueliteProfile),
    pvp: newPvPWindow(screenWidth, screenHeight),
    sandbox: newSandboxWindow(screenWidth, screenHeight),
    advancements: newAdvancementsWindow(screenWidth, screenHeight, advancementProfile,
                                        rogueliteProfile),
    roguelite: newRogueliteWindow(screenWidth, screenHeight, rogueliteProfile),
    changelog: newChangelogWindow(screenWidth, screenHeight),
    nextZOrder: 1
  )

  # Initially hide all windows
  result.settings.window.visible = false
  result.help.window.visible = false
  result.stats.window.visible = false
  result.shop.window.visible = false
  result.pvp.window.visible = false
  result.sandbox.window.visible = false
  result.advancements.window.visible = false
  result.roguelite.window.visible = false
  result.changelog.window.visible = false

proc getAllWindows*(wm: WindowManager): seq[OSWindow] =
  ## Get all windows in a single sequence
  result = @[
    wm.settings.window,
    wm.help.window,
    wm.stats.window,
    wm.shop.window,
    wm.pvp.window,
    wm.sandbox.window,
    wm.advancements.window,
    wm.roguelite.window,
    wm.changelog.window
  ]

proc getVisibleWindows*(wm: WindowManager): seq[OSWindow] =
  ## Get only visible windows, sorted by z-order (highest first)
  result = @[]
  for window in wm.getAllWindows():
    if window.visible:
      result.add(window)

  # Sort by z-order (highest first for click handling)
  result.sort(proc(a, b: OSWindow): int = cmp(b.zOrder, a.zOrder))

proc openWindow*(wm: WindowManager, id: WindowID) =
  ## Open a specific window and bring it to front
  var window: OSWindow

  case id
  of widSettings: window = wm.settings.window
  of widHelp: window = wm.help.window
  of widStats: window = wm.stats.window
  of widShop: window = wm.shop.window
  of widPvP: window = wm.pvp.window
  of widSandbox: window = wm.sandbox.window
  of widAdvancements: window = wm.advancements.window
  of widRoguelite:
    window = wm.roguelite.window
    wm.roguelite.showUnlocks = false  # Always open to setup view, not shop/unlocks
  of widChangelog:
    window = wm.changelog.window
    wm.changelog.scrollOffset = 0  # Always open scrolled to the top

  window.visible = true
  window.minimized = false
  window.focused = true
  window.zOrder = wm.nextZOrder
  inc wm.nextZOrder

  # Unfocus all other windows
  for w in wm.getAllWindows():
    if w != window:
      w.focused = false

proc closeWindow*(wm: WindowManager, id: WindowID) =
  ## Close a specific window
  case id
  of widSettings: wm.settings.window.visible = false
  of widHelp: wm.help.window.visible = false
  of widStats: wm.stats.window.visible = false
  of widShop: wm.shop.window.visible = false
  of widPvP: wm.pvp.window.visible = false
  of widSandbox: wm.sandbox.window.visible = false
  of widAdvancements: wm.advancements.window.visible = false
  of widRoguelite: wm.roguelite.window.visible = false
  of widChangelog: wm.changelog.window.visible = false

proc closeAllWindows*(wm: WindowManager) =
  ## Close all open desktop windows (e.g. when starting a game)
  wm.settings.window.visible = false
  wm.help.window.visible = false
  wm.stats.window.visible = false
  wm.shop.window.visible = false
  wm.pvp.window.visible = false
  wm.sandbox.window.visible = false
  wm.advancements.window.visible = false
  wm.roguelite.window.visible = false
  wm.changelog.window.visible = false

proc relayoutWindows*(wm: WindowManager, screenWidth, screenHeight: int) =
  ## React to a virtual-resolution change (classic <-> widescreen). Only the
  ## X axis / width changes across the toggle (height stays 768), so closed
  ## windows are re-centered horizontally (preserving each window's intended
  ## vertical position) and open windows are only re-clamped -- mirroring the
  ## drag clamp in handleOSWindowInput -- so a dragged window is never yanked
  ## yet also never stranded off-screen.
  for window in wm.getAllWindows():
    if window.visible:
      window.x = max(0, min(window.x, screenWidth - window.width))
      window.y = max(0, min(window.y, screenHeight - 100))
    else:
      window.x = (screenWidth - window.width) div 2

proc handleWindowClick*(wm: WindowManager, mousePos: Vector2): bool =
  ## Handle mouse clicks on windows. Returns true if a window consumed the click
  if not isPointerPressed():
    return false

  # Get visible windows sorted by z-order (highest first)
  let visibleWindows = wm.getVisibleWindows()

  # Find the topmost window at click position
  for window in visibleWindows:
    let clickArea = if window.minimized:
      # Minimized windows only have title bar clickable
      Rectangle(
        x: window.x.float32,
        y: window.y.float32,
        width: window.savedWidth.float32,
        height: TITLE_BAR_HEIGHT.float32
      )
    else:
      # Normal windows are fully clickable
      Rectangle(
        x: window.x.float32,
        y: window.y.float32,
        width: window.width.float32,
        height: window.height.float32
      )

    if checkCollisionPointRec(mousePos, clickArea):
      # This window was clicked - bring to front if not already focused
      if not window.focused:
        window.focused = true
        window.zOrder = wm.nextZOrder
        inc wm.nextZOrder

        # Unfocus other windows
        for w in wm.getAllWindows():
          if w != window:
            w.focused = false

      return true  # Window consumed the click

  return false  # No window at click position

proc isMouseOverAnyWindow*(wm: WindowManager, mousePos: Vector2): bool =
  ## Check if mouse is over any visible window (for blocking desktop interaction)
  for window in wm.getVisibleWindows():
    if not window.minimized:
      let windowRect = Rectangle(
        x: window.x.float32,
        y: window.y.float32,
        width: window.width.float32,
        height: window.height.float32
      )

      if checkCollisionPointRec(mousePos, windowRect):
        return true

  return false

type
  WindowUpdateResult* = object
    fullscreenToggle*: bool
    shopClosed*: bool
    rogueliteClosed*: bool
    rogueliteLaunchGame*: bool  ## True when user pressed Start in the roguelite window
    iconToExecute*: int
    pvpGameReady*: bool  # True when PvP connection is established
    sandboxLaunchGame*: bool  # True when user pressed Start in the sandbox setup window
    replayIntro*: bool  # True when user clicked "Replay Intro" in settings
    replayEnding*: bool  # True when user clicked "Replay Ending" in settings
    replayRogueliteEnding*: bool  # True when user clicked "Replay Roguelite" in settings
    replaySurvivalEnding*: bool   # True when user clicked "Replay Survival" in settings
    replayWaveIntro*: bool        # True when user clicked "Wave Intro" in settings
    replaySurvivalIntro*: bool    # True when user clicked "Survival Intro" in settings
    replayRogueliteIntro*: bool   # True when user clicked "Roguelite Intro" in settings
    replaySandboxIntro*: bool     # True when user clicked "Sandbox Intro" in settings
    replayPvPIntro*: bool         # True when user clicked "PvP Intro" in settings

proc updateAllWindows*(wm: WindowManager, dt: float32,
                       screenWidth, screenHeight: int, currentGame: Game): WindowUpdateResult =
  ## Update all visible windows and handle their inputs
  result.fullscreenToggle = false
  result.shopClosed = false
  result.rogueliteClosed = false
  result.rogueliteLaunchGame = false
  result.iconToExecute = -1
  result.pvpGameReady = false
  result.sandboxLaunchGame = false
  result.replayIntro = false
  result.replayEnding = false
  result.replayRogueliteEnding = false
  result.replaySurvivalEnding = false
  result.replayWaveIntro = false
  result.replaySurvivalIntro = false
  result.replayRogueliteIntro = false
  result.replaySandboxIntro = false
  result.replayPvPIntro = false

  let visibleWindows = wm.getVisibleWindows()

  # Reset click flags for all windows at the start of each frame
  for window in wm.getAllWindows():
    window.handledClickThisFrame = false

  # Update each visible window
  for window in visibleWindows:
    if window == wm.settings.window:
      let settingsResult = updateSettingsWindow(wm.settings, dt, screenWidth, screenHeight, visibleWindows)
      if settingsResult.fullscreenToggle:
        result.fullscreenToggle = true
      # Consume the replay-intro request so it can only fire once, and never
      # lingers to trigger later (e.g. from a mid-game settings click).
      if wm.settings.replayIntroRequested:
        result.replayIntro = true
        wm.settings.replayIntroRequested = false
      if wm.settings.replayEndingRequested:
        result.replayEnding = true
        wm.settings.replayEndingRequested = false
      if wm.settings.replayRogueliteEndingRequested:
        result.replayRogueliteEnding = true
        wm.settings.replayRogueliteEndingRequested = false
      if wm.settings.replaySurvivalEndingRequested:
        result.replaySurvivalEnding = true
        wm.settings.replaySurvivalEndingRequested = false
      if wm.settings.replayWaveIntroRequested:
        result.replayWaveIntro = true
        wm.settings.replayWaveIntroRequested = false
      if wm.settings.replaySurvivalIntroRequested:
        result.replaySurvivalIntro = true
        wm.settings.replaySurvivalIntroRequested = false
      if wm.settings.replayRogueliteIntroRequested:
        result.replayRogueliteIntro = true
        wm.settings.replayRogueliteIntroRequested = false
      if wm.settings.replaySandboxIntroRequested:
        result.replaySandboxIntro = true
        wm.settings.replaySandboxIntroRequested = false
      if wm.settings.replayPvPIntroRequested:
        result.replayPvPIntro = true
        wm.settings.replayPvPIntroRequested = false

    elif window == wm.stats.window:
      discard updateStatsWindow(wm.stats, dt, screenWidth, screenHeight, visibleWindows)

    elif window == wm.shop.window:
      result.shopClosed = updateShopWindow(wm.shop, dt, screenWidth, screenHeight, visibleWindows)
      if result.shopClosed:
        wm.shop.window.visible = false

    elif window == wm.help.window:
      result.iconToExecute = updateHelpWindow(wm.help, dt, screenWidth, screenHeight, visibleWindows)

    elif window == wm.pvp.window:
      # Create callback to provide cosmetics when accepting connections
      proc getCosmetics(): tuple[skinType, bulletSkinType, shapeType, particleSkinType: int] =
        return (
          skinType: globalSettings.playerSkin,
          bulletSkinType: globalSettings.bulletSkin,
          shapeType: globalSettings.playerShape,
          particleSkinType: globalSettings.particleEffect
        )

      updatePvPWindow(wm.pvp, dt, getCosmetics)
      handlePvPWindowInput(wm.pvp)

      # Handle window chrome (close, minimize, drag)
      let shouldClose = handleOSWindowInput(wm.pvp.window, screenWidth, screenHeight, visibleWindows)
      if shouldClose:
        wm.pvp.window.visible = false
        resetPvPWindow(wm.pvp)

      if wm.pvp.readyToStart:
        result.pvpGameReady = true

    elif window == wm.sandbox.window:
      let sandboxResult = updateSandboxWindow(wm.sandbox, dt, visibleWindows,
                                              screenWidth, screenHeight)
      if sandboxResult.shouldClose:
        wm.sandbox.window.visible = false
      if sandboxResult.launchGame:
        result.sandboxLaunchGame = true

    elif window == wm.roguelite.window:
      let rogueliteResult = updateRogueliteWindow(wm.roguelite, dt, visibleWindows, screenWidth, screenHeight, currentGame)
      result.rogueliteClosed = rogueliteResult.shouldClose
      result.rogueliteLaunchGame = rogueliteResult.launchGame
      if rogueliteResult.shouldClose:
        wm.roguelite.window.visible = false

    elif window == wm.advancements.window:
      discard updateAdvancementsWindow(wm.advancements, dt, screenWidth, screenHeight, visibleWindows)

    elif window == wm.changelog.window:
      updateChangelogWindow(wm.changelog, dt, screenWidth, screenHeight, visibleWindows)

proc drawAllWindows*(wm: WindowManager, game: Game) =
  ## Draw all visible windows in z-order
  var visibleWindows = wm.getAllWindows().filterIt(it.visible)

  # Sort by z-order (lowest first for drawing)
  visibleWindows.sort(proc(a, b: OSWindow): int = cmp(a.zOrder, b.zOrder))

  # Draw each window
  for window in visibleWindows:
    if window == wm.settings.window:
      drawSettingsWindow(wm.settings)
    elif window == wm.stats.window:
      drawStatsWindow(wm.stats, game)
    elif window == wm.shop.window:
      drawShopWindow(wm.shop)
    elif window == wm.help.window:
      drawHelpWindow(wm.help)
    elif window == wm.pvp.window:
      # Draw window frame
      drawWindowChrome(window)
      # Draw PvP content inside (only if not minimized)
      if not window.minimized:
        let contentX = window.x + WINDOW_BORDER
        let contentY = window.y + TITLE_BAR_HEIGHT + WINDOW_BORDER
        let contentWidth = window.width - WINDOW_BORDER * 2
        let contentHeight = window.height - TITLE_BAR_HEIGHT - WINDOW_BORDER * 2
        drawPvPWindowContent(wm.pvp, contentX, contentY, contentWidth, contentHeight)
    elif window == wm.sandbox.window:
      drawSandboxWindow(wm.sandbox)
    elif window == wm.advancements.window:
      drawAdvancementsWindow(wm.advancements)
    elif window == wm.roguelite.window:
      drawRogueliteWindow(wm.roguelite, game)
    elif window == wm.changelog.window:
      drawChangelogWindow(wm.changelog)
