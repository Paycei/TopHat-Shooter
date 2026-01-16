## OS Window Manager
## Centralized window handling with state management

import raylib, os_window, settings_window, help_window, stats_window, shop_window
import ../types, ../settings, ../statistics, ../skins, ../bullet_skins, ../shapes, ../particle_skins
import algorithm, sequtils

type
  WindowID* = enum
    widSettings
    widHelp
    widStats
    widShop
  
  WindowManager* = ref object
    settings*: SettingsWindow
    help*: HelpWindow
    stats*: StatsWindow
    shop*: ShopWindow
    nextZOrder: int

proc newWindowManager*(screenWidth, screenHeight: int, 
                       gameSettings: Settings, 
                       gameStats: Statistics): WindowManager =
  ## Create a new window manager with all windows pre-initialized
  result = WindowManager(
    settings: newSettingsWindow(screenWidth, screenHeight, gameSettings),
    help: newHelpWindow(screenWidth, screenHeight),
    stats: newStatsWindow(screenWidth, screenHeight, gameStats),
    shop: newShopWindow(screenWidth, screenHeight, 
                       SkinType(gameSettings.playerSkin), 
                       BulletSkinType(gameSettings.bulletSkin), 
                       ShapeType(gameSettings.playerShape), 
                       ParticleSkinType(gameSettings.particleEffect)),
    nextZOrder: 1
  )
  
  # Initially hide all windows
  result.settings.window.visible = false
  result.help.window.visible = false
  result.stats.window.visible = false
  result.shop.window.visible = false

proc getAllWindows*(wm: WindowManager): seq[OSWindow] =
  ## Get all windows in a single sequence
  result = @[
    wm.settings.window,
    wm.help.window,
    wm.stats.window,
    wm.shop.window
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

proc handleWindowClick*(wm: WindowManager, mousePos: Vector2): bool =
  ## Handle mouse clicks on windows. Returns true if a window consumed the click
  if not isMouseButtonPressed(Left):
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
    iconToExecute*: int

proc updateAllWindows*(wm: WindowManager, dt: float32, 
                       screenWidth, screenHeight: int): WindowUpdateResult =
  ## Update all visible windows and handle their inputs
  result.fullscreenToggle = false
  result.shopClosed = false
  result.iconToExecute = -1
  
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
    
    elif window == wm.stats.window:
      discard updateStatsWindow(wm.stats, dt, screenWidth, screenHeight, visibleWindows)
    
    elif window == wm.shop.window:
      result.shopClosed = updateShopWindow(wm.shop, dt, visibleWindows)
      if result.shopClosed:
        wm.shop.window.visible = false
    
    elif window == wm.help.window:
      result.iconToExecute = updateHelpWindow(wm.help, dt, screenWidth, screenHeight, visibleWindows)

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
