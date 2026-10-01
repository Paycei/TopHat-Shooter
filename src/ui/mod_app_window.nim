## A mod app (register.app) as a desktop program: its own OSWindow around the
## app's canvas. The window names its app by key, never by index -- reloadMods
## rebuilds the app list, and a window whose app is gone simply closes.
##
## Input: a left click inside the canvas reaches the app's `click` only when this
## window is the topmost one at that point (the title bar, close/minimize
## buttons and the resize edge stay the window's). `update` runs every frame the
## window is open and not minimized.

import raylib, rlgl
import os_window, ../localization, ../render_context, ../gamepad_input
import ../modding/mod_hooks

type
  ModAppWindow* = ref object
    window*: OSWindow
    key*: string
    draggingCanvas*: bool

const
  CanvasBg = Color(r: 6, g: 8, b: 12, a: 255)

proc appTitle(key: string): string =
  let i = findModApp(key)
  if i < 0: key else: modAppName(i, getLanguage() == Spanish)

proc newModAppWindow*(key: string, screenWidth, screenHeight: int): ModAppWindow =
  ## Sized to the app's canvas plus the chrome and centred. Resizable windows
  ## are never opened smaller than the framework's minimum, or the first drag
  ## would snap them up to it.
  let i = findModApp(key)
  var w = 480 + WINDOW_BORDER * 2
  var h = 360 + TITLE_BAR_HEIGHT + WINDOW_BORDER
  var color = ModAppDefaultColor
  var resizable = false
  if i >= 0:
    let a = modApps[i]
    w = a.width + WINDOW_BORDER * 2
    h = a.height + TITLE_BAR_HEIGHT + WINDOW_BORDER
    color = a.color
    resizable = a.resizable
  if resizable:
    w = max(w, MIN_WINDOW_WIDTH)
    h = max(h, MIN_WINDOW_HEIGHT)
  let osWin = newOSWindow(appTitle(key), (screenWidth - w) div 2,
                          max(0, (screenHeight - h) div 2), w, h, color, owtSettings,
                          resizable = resizable)
  result = ModAppWindow(window: osWin, key: key, draggingCanvas: false)

proc canvasRect(mw: ModAppWindow): Rectangle =
  Rectangle(x: (mw.window.x + WINDOW_BORDER).float32,
            y: (mw.window.y + TITLE_BAR_HEIGHT).float32,
            width: (mw.window.width - WINDOW_BORDER * 2).float32,
            height: (mw.window.height - TITLE_BAR_HEIGHT - WINDOW_BORDER).float32)

proc updateModAppWindow*(mw: ModAppWindow, dt: float32, screenWidth, screenHeight: int,
                         allWindows: openArray[OSWindow]) =
  ## Closing (the X, Escape, or the app disappearing in a reload) sets
  ## window.visible = false; the window manager prunes it afterwards.
  let w = mw.window
  updateOSWindow(w, dt)
  if not w.visible: return
  let idx = findModApp(mw.key)
  if idx < 0:
    w.visible = false
    return
  w.title = modAppName(idx, getLanguage() == Spanish)
  if handleOSWindowInput(w, screenWidth, screenHeight, allWindows):
    w.visible = false
    return
  if w.minimized: return

  let c = canvasRect(mw)
  let mouse = getVirtualMousePosition()
  let overCanvas = checkCollisionPointRec(mouse, c) and
                   isWindowTopmostAtPoint(w, mouse.x, mouse.y, allWindows)
  if overCanvas:
    let leftClick = w.handledClickThisFrame and isPointerPressed()
    let rightClick = isMouseButtonPressed(MouseButton.Right)
    if leftClick or rightClick:
      modAppClick(idx, mouse.x - c.x, mouse.y - c.y, if leftClick: "left" else: "right",
                  c.width, c.height)
      if leftClick:
        mw.draggingCanvas = true
  if mw.draggingCanvas:
    if isMouseButtonDown(MouseButton.Left):
      modAppDrag(idx, mouse.x - c.x, mouse.y - c.y, c.width, c.height)
    else:
      mw.draggingCanvas = false
  modAppUpdate(idx, dt)

proc drawModAppWindow*(mw: ModAppWindow, allWindows: openArray[OSWindow]) =
  let w = mw.window
  if not w.visible: return
  drawWindowChrome(w)
  if w.minimized: return
  let idx = findModApp(mw.key)
  if idx < 0: return
  let c = canvasRect(mw)
  drawRectangle(c, CanvasBg)
  let mouse = getVirtualMousePosition()
  let inside = checkCollisionPointRec(mouse, c) and
               isWindowTopmostAtPoint(w, mouse.x, mouse.y, allWindows)
  # The app's canvas: its own coordinates, and it cannot draw outside it.
  beginVirtualScissorMode(int32(c.x), int32(c.y), int32(c.width), int32(c.height))
  pushMatrix()
  translatef(c.x, c.y, 0)
  modAppDraw(idx, c.width, c.height,
             if inside: mouse.x - c.x else: -1, if inside: mouse.y - c.y else: -1)
  popMatrix()
  endScissorMode()
  drawResizeIndicator(w)
