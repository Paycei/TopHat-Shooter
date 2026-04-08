import raylib

when defined(windows):
  type
    WinPoint = object
      x: int32
      y: int32

    WinRect = object
      left: int32
      top: int32
      right: int32
      bottom: int32

  proc getClientRect(hwnd: pointer, lpRect: pointer): int32
    {.stdcall, dynlib: "user32", importc: "GetClientRect".}
  proc clientToScreen(hwnd: pointer, lpPoint: pointer): int32
    {.stdcall, dynlib: "user32", importc: "ClientToScreen".}
  proc clipCursor(lpRect: pointer): int32
    {.stdcall, dynlib: "user32", importc: "ClipCursor".}

var
  currentRenderScale = 1.0'f32
  currentRenderOffsetX = 0.0'f32
  currentRenderOffsetY = 0.0'f32
  currentVirtualWidth = 1024.0'f32
  currentVirtualHeight = 768.0'f32
  mouseClipActive = false

proc updateRenderInputTransform*(scale, offsetX, offsetY: float32,
                                 virtualWidth, virtualHeight: int32) =
  currentRenderScale = max(scale, 0.0001'f32)
  currentRenderOffsetX = offsetX
  currentRenderOffsetY = offsetY
  currentVirtualWidth = virtualWidth.float32
  currentVirtualHeight = virtualHeight.float32

proc getVirtualMousePosition*(): Vector2 =
  let screenPos = getMousePosition()
  result.x = (screenPos.x - currentRenderOffsetX) / currentRenderScale
  result.y = (screenPos.y - currentRenderOffsetY) / currentRenderScale
  result.x = clamp(result.x, 0.0'f32, currentVirtualWidth)
  result.y = clamp(result.y, 0.0'f32, currentVirtualHeight)

proc bondMouseToVirtualViewport*() =
  ## Keep the mouse inside the active virtual viewport.
  if not isWindowFocused():
    return

  let screenPos = getMousePosition()
  let minX = currentRenderOffsetX
  let minY = currentRenderOffsetY
  let maxX = currentRenderOffsetX + currentVirtualWidth * currentRenderScale - 1.0'f32
  let maxY = currentRenderOffsetY + currentVirtualHeight * currentRenderScale - 1.0'f32

  let bondedX = clamp(screenPos.x, minX, maxX)
  let bondedY = clamp(screenPos.y, minY, maxY)
  if bondedX != screenPos.x or bondedY != screenPos.y:
    setMousePosition(bondedX.int32, bondedY.int32)

proc clipMouseToWindowClientArea*() =
  ## Keep the system cursor inside the current game window.
  when defined(windows):
    if not isWindowFocused():
      if mouseClipActive:
        discard clipCursor(nil)
        mouseClipActive = false
      return

    let hwnd = getWindowHandle()
    if hwnd == nil:
      return

    var clientRect: WinRect
    if getClientRect(hwnd, addr clientRect) == 0:
      return

    var topLeft = WinPoint(x: clientRect.left, y: clientRect.top)
    var bottomRight = WinPoint(x: clientRect.right, y: clientRect.bottom)
    if clientToScreen(hwnd, addr topLeft) == 0 or clientToScreen(hwnd, addr bottomRight) == 0:
      return

    var clipRect = WinRect(
      left: topLeft.x,
      top: topLeft.y,
      right: bottomRight.x,
      bottom: bottomRight.y
    )
    discard clipCursor(addr clipRect)
    mouseClipActive = true
  else:
    bondMouseToVirtualViewport()

proc releaseMouseClip*() =
  ## Release any active system cursor confinement.
  when defined(windows):
    if mouseClipActive:
      discard clipCursor(nil)
      mouseClipActive = false
