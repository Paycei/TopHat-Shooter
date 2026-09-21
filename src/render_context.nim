import raylib, rlgl, math
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
  # UI scale: the factor the *interface* layer (desktop, OS windows, in-game HUD)
  # is drawn at on top of the virtual screen. It is only non-1.0 between a
  # pushUIScale/popUIScale pair, so gameplay drawing is never affected.
  #
  # A layer pushed at scale S is laid out in "UI logical" pixels -- virtual
  # pixels divided by S -- and then scaled back up by S when drawn. So S > 1.0
  # makes the interface physically bigger while shrinking the room it has to lay
  # out in, and S < 1.0 does the reverse. Because getVirtualScreenWidth/Height
  # and getVirtualMousePosition both honour the active scale, existing UI code
  # that already goes through those adapts with no changes.
  activeUIScale = 1.0'f32

proc pushUIScale*(scale: float32) =
  ## Enter a UI layer whose coordinates are virtual pixels divided by `scale`.
  ## Input-only: use beginUIScaleMode when also drawing the layer. These do not
  ## nest -- one interface layer is active at a time.
  activeUIScale = max(scale, 0.0001'f32)

proc popUIScale*() =
  ## Leave the UI layer; coordinates return to plain virtual pixels.
  activeUIScale = 1.0'f32

proc getActiveUIScale*(): float32 =
  ## The scale of the interface layer currently being drawn/hit-tested (1.0 when
  ## none is active). Callers that pre-scale their own geometry need this; most
  ## don't, because the coordinate getters already fold it in.
  activeUIScale

proc beginUIScaleMode*(scale: float32) =
  ## Draw *and* hit-test the following UI at `scale`. Must be paired with
  ## endUIScaleMode. Nests inside the supersample matrix pushed by the frame's
  ## render-target setup, so the two multiply as expected.
  pushUIScale(scale)
  pushMatrix()
  scalef(activeUIScale, activeUIScale, 1.0'f32)

proc endUIScaleMode*() =
  popMatrix()
  popUIScale()

proc updateRenderInputTransform*(scale, offsetX, offsetY: float32,
                                 virtualWidth, virtualHeight: int32) =
  currentRenderScale = max(scale, 0.0001'f32)
  currentRenderOffsetX = offsetX
  currentRenderOffsetY = offsetY
  currentVirtualWidth = virtualWidth.float32
  currentVirtualHeight = virtualHeight.float32

proc setWorldViewOffset*(x: float32) =
  ## Set the horizontal offset of the gameplay world within the virtual screen.
  ## Called by main each frame alongside updateRenderInputTransform.
  currentWorldViewOffsetX = x

proc getWorldViewOffsetX*(): float32 =
  currentWorldViewOffsetX

proc getVirtualScreenWidth*(): int32 =
  ## Full virtual screen width (1024 classic / 1366 widescreen), expressed in
  ## the coordinates of the active UI layer -- so inside a scaled interface
  ## layer this is the *logical* width that layer has to lay out in.
  (currentVirtualWidth / activeUIScale).int32

proc getVirtualScreenHeight*(): int32 =
  ## Full virtual screen height (768), in active-UI-layer coordinates.
  (currentVirtualHeight / activeUIScale).int32

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
  # The rect arrives in active-UI-layer coords, so it has to travel through the
  # same two transforms the drawing does: the UI scale, then the supersample.
  let totalScale = getRenderSupersampleScale() * activeUIScale
  let scaledX = floor(x.float32 * totalScale).int32
  let scaledY = floor(y.float32 * totalScale).int32
  let scaledWidth = max(1'i32, ceil(width.float32 * totalScale).int32)
  let scaledHeight = max(1'i32, ceil(height.float32 * totalScale).int32)
  beginScissorMode(scaledX, scaledY, scaledWidth, scaledHeight)

proc getCurrentVirtualScissor*(): tuple[x, y, w, h: int32] =
  ## The clip rect most recently set via beginVirtualScissorMode, in virtual
  ## coords. Only meaningful while currentVirtualScissorIsActive() is true.
  currentVirtualScissorRect

proc currentVirtualScissorIsActive*(): bool =
  currentVirtualScissorActive

proc getRealVirtualMousePosition*(): Vector2 =
  ## The physical mouse position in virtual coords, ignoring the gamepad
  ## cursor. Used for device arbitration and cursor handoff seeding.
  let screenPos = getMousePosition()
  result.x = (screenPos.x - currentRenderOffsetX) / (currentRenderScale * activeUIScale)
  result.y = (screenPos.y - currentRenderOffsetY) / (currentRenderScale * activeUIScale)
  result.x = clamp(result.x, 0.0'f32, currentVirtualWidth / activeUIScale)
  result.y = clamp(result.y, 0.0'f32, currentVirtualHeight / activeUIScale)

proc getVirtualMousePosition*(): Vector2 =
  ## The pointer position every menu/HUD/aim call site reads. While the gamepad
  ## is the active device this is the gamepad virtual cursor (menu mode) or the
  ## gameplay aim point, so the entire mouse-driven UI works from the pad.
  if isGamepadActive():
    # The pad cursor is tracked in plain virtual pixels (it is moved and clamped
    # against the whole screen), so it needs the same divide the mouse gets.
    let p = gamepadCursorPos()
    Vector2(x: p.x / activeUIScale, y: p.y / activeUIScale)
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
