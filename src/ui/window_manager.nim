## OS Window Manager
## Centralized window handling with state management

import raylib, algorithm, sequtils, math
import os_window, settings_window, help_window, stats_window, shop_window, pvp_window, sandbox_window, advancements_window, roguelite_window, changelog_window, credits_window, ../types, ../settings, ../save_system, ../statistics, ../skins, ../bullet_skins, ../bullet_shapes, ../shapes, ../particle_skins, ../advancement
import ../gamepad_input, ../render_context

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
    widCredits

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
    credits*: CreditsWindow
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
    credits: newCreditsWindow(screenWidth, screenHeight),
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
  result.credits.window.visible = false

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
    wm.changelog.window,
    wm.credits.window
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
  of widRoguelite: window = wm.roguelite.window
  of widChangelog:
    window = wm.changelog.window
    resetChangelogView(wm.changelog)  # Always open on the newest version, at the top
  of widCredits: window = wm.credits.window

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
  of widCredits: wm.credits.window.visible = false

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
  wm.credits.window.visible = false

proc windowUIScale*(window: OSWindow, requested: float32,
                    screenWidth, screenHeight: int): float32 =
  ## The interface scale this one window can actually be drawn at.
  ##
  ## Scaling down always works. Scaling *up* shrinks the logical viewport a
  ## window lays out in (`virtual / scale`) while its contents stay a fixed
  ## pixel size, so past a certain point its edges fall off the screen with no
  ## way to reach them. That point differs per window -- the settings window is
  ## 700x500 against a 1024x768 virtual screen and has room to spare, while the
  ## stats window is 1000x700 and has almost none -- so the cap is applied per
  ## window rather than globally. Everything that *can* grow does; only the
  ## windows that are already near screen-size stop early.
  if requested <= 1.0'f32:
    return requested
  let w = max(window.width, window.savedWidth)
  let h = max(window.height, window.savedHeight)
  let fit = min(screenWidth.float32 / w.float32,
                screenHeight.float32 / h.float32)
  # max(fit, 1.0) so a window that already overflows at 100% is left alone
  # rather than being silently shrunk by a setting that was turned *up*.
  min(requested, max(fit, 1.0'f32))

proc windowViewport*(window: OSWindow, requested: float32,
                     screenWidth, screenHeight: int):
                     tuple[scale: float32, w, h: int] =
  ## `window`'s own scale plus the logical viewport it lays out and is
  ## hit-tested in at that scale. Rounded up, to match what the window's own
  ## getVirtualScreenWidth/Height report once it is inside that layer.
  let scale = windowUIScale(window, requested, screenWidth, screenHeight)
  (scale, ceil(screenWidth.float32 / scale).int, ceil(screenHeight.float32 / scale).int)

proc pointerIn(window: OSWindow, requested: float32,
               screenWidth, screenHeight: int): Vector2 =
  ## The pointer, in `window`'s own coordinate space. Windows no longer share
  ## one space, so a caller cannot hit-test them all against a single position.
  pushUIScale(windowUIScale(window, requested, screenWidth, screenHeight))
  result = getVirtualMousePosition()
  popUIScale()

proc applyWindowScales*(wm: WindowManager, uiScale: float32,
                        screenWidth, screenHeight: int) =
  ## Publish every window's resolved scale onto the window itself, before
  ## anything walks the list. handleOSWindowInput decides which window owns a
  ## click by testing the *other* windows too, and it can only translate the
  ## pointer into their spaces if they already know their own scale -- so all of
  ## them are refreshed up front rather than one per loop iteration.
  for window in wm.getAllWindows():
    window.uiScale = windowUIScale(window, uiScale, screenWidth, screenHeight)

proc relayoutWindows*(wm: WindowManager, uiScale: float32,
                      screenWidth, screenHeight: int) =
  ## React to a change in the logical viewport windows lay out in: the
  ## classic <-> widescreen toggle (X axis only) or a UI-scale change (both
  ## axes). Closed windows are re-centered -- their position is already treated
  ## as disposable, since the X half of this has always reset it -- and open
  ## windows are re-clamped so a dragged window is never yanked, yet also never
  ## stranded off-screen.
  ##
  ## The clamp pulls the whole window back into view rather than leaving 100px
  ## of it showing the way the drag clamp does: this runs when the viewport
  ## moved underneath the player, not when they dragged a window somewhere on
  ## purpose, so the window should end up usable again.
  ##
  ## When the *scale* is what changed, an open window is re-anchored around the
  ## pointer rather than around its own corner: whatever sat under the cursor
  ## before sits under it after. That is what makes the Interface tab's own
  ## UI-scale stepper usable. A control's offset inside its window scales too, so
  ## pinning only the window corner still slides the button out from under the
  ## click that moved it -- and the next click on the same spot then lands on the
  ## other arrow, or misses the button entirely.
  ##
  ## Callers run outside any UI-scale layer, so this pointer is in plain virtual
  ## pixels: the space both the old and the new scale divide.
  let pointer = getVirtualMousePosition()
  for window in wm.getAllWindows():
    # The scale this window was laid out at until now. windowUIScale is pure and
    # applyWindowScales has not run again this frame, so it is still the previous
    # value when a scale change is what brought us here.
    let prevScale = uiScaleOfWindow(window)
    let vp = windowViewport(window, uiScale, screenWidth, screenHeight)
    if window.visible:
      if prevScale != vp.scale:
        window.x = int(pointer.x / vp.scale - (pointer.x / prevScale - window.x.float32))
        window.y = int(pointer.y / vp.scale - (pointer.y / prevScale - window.y.float32))
      window.x = max(0, min(window.x, vp.w - window.width))
      window.y = max(0, min(window.y, max(0, vp.h - window.height)))
    else:
      window.x = (vp.w - window.width) div 2
      window.y = max(0, (vp.h - window.height) div 2)
    window.uiScale = vp.scale

proc handleWindowClick*(wm: WindowManager, uiScale: float32,
                        screenWidth, screenHeight: int): bool =
  ## Handle mouse clicks on windows. Returns true if a window consumed the click
  if not isPointerPressed():
    return false

  # Get visible windows sorted by z-order (highest first)
  let visibleWindows = wm.getVisibleWindows()

  # Find the topmost window at click position
  for window in visibleWindows:
    let mousePos = window.pointerIn(uiScale, screenWidth, screenHeight)
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

proc isMouseOverAnyWindow*(wm: WindowManager, uiScale: float32,
                           screenWidth, screenHeight: int): bool =
  ## Check if mouse is over any visible window (for blocking desktop interaction)
  for window in wm.getVisibleWindows():
    if not window.minimized:
      let mousePos = window.pointerIn(uiScale, screenWidth, screenHeight)
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
    replayTutorial*: bool         # True when user clicked "Replay Tutorial" in settings

proc updateAllWindows*(wm: WindowManager, dt: float32, uiScale: float32,
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
  result.replayTutorial = false

  wm.applyWindowScales(uiScale, screenWidth, screenHeight)

  let visibleWindows = wm.getVisibleWindows()

  # Reset click flags for all windows at the start of each frame
  for window in wm.getAllWindows():
    window.handledClickThisFrame = false

  # Update each visible window, inside its own scale layer so its hit-testing
  # matches how drawAllWindows renders it.
  for window in visibleWindows:
    let vp = windowViewport(window, uiScale, screenWidth, screenHeight)
    let screenWidth = vp.w
    let screenHeight = vp.h
    pushUIScale(vp.scale)
    defer: popUIScale()

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
      if wm.settings.replayTutorialRequested:
        result.replayTutorial = true
        wm.settings.replayTutorialRequested = false

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

    elif window == wm.credits.window:
      updateCreditsWindow(wm.credits, dt, screenWidth, screenHeight, visibleWindows)

proc drawAllWindows*(wm: WindowManager, game: Game, uiScale: float32,
                     screenWidth, screenHeight: int) =
  ## Draw all visible windows in z-order, each inside its own scale layer.
  wm.applyWindowScales(uiScale, screenWidth, screenHeight)
  var visibleWindows = wm.getAllWindows().filterIt(it.visible)

  # Sort by z-order (lowest first for drawing)
  visibleWindows.sort(proc(a, b: OSWindow): int = cmp(a.zOrder, b.zOrder))

  # Draw each window
  for window in visibleWindows:
    beginUIScaleMode(windowUIScale(window, uiScale, screenWidth, screenHeight))
    defer: endUIScaleMode()

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
    elif window == wm.credits.window:
      drawCreditsWindow(wm.credits)
