import raylib, math
import gamepad_input
# Re-export so every module that already imports render_context (all ui/, game,
# pvp_game, sandbox, main) sees the pointer wrappers and gamepad queries.
export gamepad_input

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
  # Horizontal offset of the gameplay world inside the virtual screen. In classic
  # (4:3) mode the world fills the virtual screen so this is 0; in widescreen
  # (16:9) mode the 1024-wide world is centered and this is the left gutter width.
  currentWorldViewOffsetX = 0.0'f32

proc updateRenderInputTransform*(scale, offsetX, offsetY: float32,
                                 virtualWidth, virtualHeight: int32) =
  currentRenderScale = max(scale, 0.0001'f32)
  currentRenderOffsetX = offsetX
  currentRenderOffsetY = offsetY
  currentVirtualWidth = virtualWidth.float32
  currentVirtualHeight = virtualHeight.float32

proc getRenderScale*(): float32 =
  ## Physical-pixels-per-virtual-pixel (the letterbox scale). A screen-space
  ## length L maps to L / getRenderScale() virtual units.
  currentRenderScale

proc setWorldViewOffset*(x: float32) =
  ## Set the horizontal offset of the gameplay world within the virtual screen.
  ## Called by main each frame alongside updateRenderInputTransform.
  currentWorldViewOffsetX = x

proc getWorldViewOffsetX*(): float32 =
  currentWorldViewOffsetX

proc getVirtualScreenWidth*(): int32 =
  ## Full virtual screen width (1024 classic / 1366 widescreen).
  currentVirtualWidth.int32

proc getVirtualScreenHeight*(): int32 =
  ## Full virtual screen height (768).
  currentVirtualHeight.int32

const BaseVirtualWidth* = 1024'i32
  ## The classic (4:3) virtual width. Every fixed-size panel in the game was laid
  ## out against this, so it is the baseline "no extra room" width.

proc getExtraVirtualWidth*(): int32 =
  ## Horizontal virtual pixels available beyond the classic layout width:
  ## 0 in classic (4:3), 342 in widescreen (16:9). Centered UI panels grow by a
  ## capped share of this instead of leaving the extra width as empty gutters,
  ## which keeps classic pixel-identical (the growth term is exactly 0 there).
  max(0'i32, getVirtualScreenWidth() - BaseVirtualWidth)

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

proc screenToVirtual*(screenPos: Vector2): Vector2 =
  ## Map a physical-window pixel coordinate into the virtual canvas, undoing the
  ## letterbox offset + scale. Shared by the mouse and touch paths so both land
  ## in the same space the game draws in. Clamped to the virtual bounds.
  result.x = (screenPos.x - currentRenderOffsetX) / currentRenderScale
  result.y = (screenPos.y - currentRenderOffsetY) / currentRenderScale
  result.x = clamp(result.x, 0.0'f32, currentVirtualWidth)
  result.y = clamp(result.y, 0.0'f32, currentVirtualHeight)

proc getRealVirtualMousePosition*(): Vector2 =
  ## The physical mouse position in virtual coords, ignoring the gamepad
  ## cursor. Used for device arbitration and cursor handoff seeding.
  screenToVirtual(getMousePosition())

proc getVirtualMousePosition*(): Vector2 =
  ## The pointer position every menu/HUD/aim call site reads. While the gamepad
  ## is the active device this is the gamepad virtual cursor (menu mode) or the
  ## gameplay aim point, so the entire mouse-driven UI works from the pad.
  if isGamepadActive():
    gamepadCursorPos()
  else:
    getRealVirtualMousePosition()

proc getWorldMousePosition*(): Vector2 =
  ## The pointer position in gameplay WORLD coords (virtual pointer minus the
  ## world view offset). In the left gutter this can go negative; callers expect
  ## world coordinates, so it is intentionally NOT clamped.
  result = getVirtualMousePosition()
  result.x -= currentWorldViewOffsetX

proc setGamepadAimPointWorld*(p: Vector2) =
  ## Store a gameplay aim point expressed in WORLD coords. The stored "virtual
  ## mouse" is uniformly virtual for both mouse and pad, so the offset is added
  ## back here before handing off to setGamepadAimPoint.
  setGamepadAimPoint(Vector2(x: p.x + currentWorldViewOffsetX, y: p.y))

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
