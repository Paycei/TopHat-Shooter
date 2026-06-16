import raylib, math

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
  currentRenderSupersampleScale = 1.0'f32
  mouseClipActive = false

proc updateRenderInputTransform*(scale, offsetX, offsetY: float32,
                                 virtualWidth, virtualHeight: int32) =
  currentRenderScale = max(scale, 0.0001'f32)
  currentRenderOffsetX = offsetX
  currentRenderOffsetY = offsetY
  currentVirtualWidth = virtualWidth.float32
  currentVirtualHeight = virtualHeight.float32

proc setRenderSupersampleScale*(scale: float32) =
  currentRenderSupersampleScale = max(scale, 1.0'f32)

proc getRenderSupersampleScale*(): float32 =
  currentRenderSupersampleScale

var
  currentVirtualScissorRect = (x: 0'i32, y: 0'i32, w: 0'i32, h: 0'i32)
  currentVirtualScissorActive = false

proc beginVirtualScissorMode*(x, y, width, height: int32) =
  # Remember the requested clip in *virtual* (pre-supersample) coords. raylib
  # scissors don't nest, so callers that need to clip within an existing clip
  # (e.g. a live preview inside a scrolled grid) can read this back and intersect
  # manually rather than blowing the parent clip away. Stored unscaled so a
  # round-trip through beginVirtualScissorMode doesn't double-apply the scale.
  currentVirtualScissorRect = (x, y, width, height)
  currentVirtualScissorActive = true
  let supersampleScale = getRenderSupersampleScale()
  let scaledX = floor(x.float32 * supersampleScale).int32
  let scaledY = floor(y.float32 * supersampleScale).int32
  let scaledWidth = max(1'i32, ceil(width.float32 * supersampleScale).int32)
  let scaledHeight = max(1'i32, ceil(height.float32 * supersampleScale).int32)
  beginScissorMode(scaledX, scaledY, scaledWidth, scaledHeight)

proc getCurrentVirtualScissor*(): tuple[x, y, w, h: int32] =
  ## The clip rect most recently set via beginVirtualScissorMode, in virtual
  ## coords. Only meaningful while currentVirtualScissorIsActive() is true.
  currentVirtualScissorRect

proc currentVirtualScissorIsActive*(): bool =
  currentVirtualScissorActive

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
