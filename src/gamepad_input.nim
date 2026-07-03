## Gamepad input layer.
##
## Leaf module (imports only raylib/math/types) so render_context can import and
## re-export it, which puts the pointer wrappers in scope everywhere UI code
## already imports render_context.
##
## Responsibilities:
## - Device arbitration: tracks whether the mouse or the gamepad was used last.
##   The overridden getVirtualMousePosition (render_context) serves the gamepad
##   virtual cursor only while the pad is the active device.
## - Virtual cursor: in menu mode the left stick moves a cursor in virtual
##   coords; in gameplay mode the cursor is the aim point written each frame by
##   game.nim/pvp_game.nim (setGamepadAimPoint).
## - Pointer wrappers: A button doubles as left click, B as Escape, Start as
##   pause. These are fixed, not rebindable.
## - Rebindable action binds: queries over GamepadBindings (types.nim); callers
##   pass globalSettings.gamepadBinds (this module must not import settings).

import raylib, math, types

type
  ActiveInputDevice* = enum
    adMouse
    adGamepad

  GamepadCursorMode* = enum
    cmMenuCursor    # left stick drives the virtual cursor
    cmGameplayAim   # cursor = aim point written by the gameplay code

  GamepadNavDir* = enum
    gnUp
    gnDown
    gnLeft
    gnRight

const
  MaxGamepads = 4'i32
  StickDeadzone = 0.25'f32
  TriggerAxisThreshold = 0.3'f32   # analog fallback for RT/LT bound as buttons
  AutofireStickThreshold = 0.5'f32
  CursorSpeed = 900.0'f32          # px/s at full stick deflection
  MouseWakeDelta = 2.0'f32         # real-mouse movement that reclaims control
  StickScrollNotchesPerSec = 6.0'f32
  DpadScrollRepeatDelay = 0.35'f32
  DpadScrollRepeatRate = 0.09'f32

var
  activePad: int32 = -1
  preferredPad: int32 = -1   # user-selected pad index; -1 = auto (first available)
  device = adMouse
  cursorMode = cmMenuCursor
  cursorPos = Vector2(x: 0, y: 0)
  lastAimDir = Vector2(x: 1, y: 0)  # aim persists when the right stick is released
  frameDt: float32 = 0
  backSuppressed = false
  backSuppressNext = false
  dpadScrollHeldTime: float32 = 0
  dpadScrollAccum: float32 = 0

proc activeGamepad*(): int32 =
  activePad

proc activeDevice*(): ActiveInputDevice =
  device

proc isGamepadActive*(): bool =
  device == adGamepad and activePad >= 0

proc setGamepadCursorMode*(mode: GamepadCursorMode) =
  cursorMode = mode

proc setPreferredGamepad*(idx: int32) =
  ## Which physical pad index the player picked in settings (-1 = auto). The
  ## leaf module can't read globalSettings, so main.nim pushes this each frame.
  preferredPad = idx

proc preferredGamepad*(): int32 =
  preferredPad

proc availableGamepads*(): seq[tuple[index: int32, name: string]] =
  ## Connected pads Raylib currently reports, for the settings selector. Rescan
  ## on demand so the list reflects hot-plug/unplug at the moment it's drawn.
  for pad in 0'i32 ..< MaxGamepads:
    if isGamepadAvailable(pad):
      result.add((pad, getGamepadName(pad)))

proc gamepadCursorPos*(): Vector2 =
  cursorPos

proc setGamepadCursorPos*(pos: Vector2) =
  cursorPos = pos

proc setGamepadAimPoint*(pos: Vector2) =
  ## Gameplay writes the (possibly aim-assisted) world aim point here so the
  ## crosshair and any other getVirtualMousePosition reader follow it.
  cursorPos = pos

proc applyRadialDeadzone(raw: Vector2): Vector2 =
  let len = sqrt(raw.x * raw.x + raw.y * raw.y)
  if len < StickDeadzone:
    return Vector2(x: 0, y: 0)
  # Rescale so output ramps smoothly from 0 at the deadzone edge to 1 at full
  # deflection instead of jumping to the deadzone value.
  let scaled = min((len - StickDeadzone) / (1.0'f32 - StickDeadzone), 1.0'f32)
  result.x = raw.x / len * scaled
  result.y = raw.y / len * scaled

proc leftStick*(): Vector2 =
  if activePad < 0: return Vector2(x: 0, y: 0)
  applyRadialDeadzone(Vector2(
    x: getGamepadAxisMovement(activePad, GamepadAxis.LeftX),
    y: getGamepadAxisMovement(activePad, GamepadAxis.LeftY)))

proc rightStick*(): Vector2 =
  if activePad < 0: return Vector2(x: 0, y: 0)
  applyRadialDeadzone(Vector2(
    x: getGamepadAxisMovement(activePad, GamepadAxis.RightX),
    y: getGamepadAxisMovement(activePad, GamepadAxis.RightY)))

proc aimDir*(): Vector2 =
  ## Right-stick direction; keeps the last non-zero direction when released so
  ## the aim point doesn't snap back to a default between bursts.
  let rs = rightStick()
  let len = sqrt(rs.x * rs.x + rs.y * rs.y)
  if len > 0.01'f32:
    lastAimDir = Vector2(x: rs.x / len, y: rs.y / len)
  lastAimDir

# --- fixed meta buttons -----------------------------------------------------

proc padButtonPressed(b: GamepadButton): bool =
  activePad >= 0 and isGamepadButtonPressed(activePad, b)

proc padButtonDown(b: GamepadButton): bool =
  activePad >= 0 and isGamepadButtonDown(activePad, b)

proc padButtonReleased(b: GamepadButton): bool =
  activePad >= 0 and isGamepadButtonReleased(activePad, b)

proc isPointerPressed*(): bool =
  isMouseButtonPressed(MouseButton.Left) or padButtonPressed(GamepadButton.RightFaceDown)

proc isPointerDown*(): bool =
  isMouseButtonDown(MouseButton.Left) or padButtonDown(GamepadButton.RightFaceDown)

proc isPointerReleased*(): bool =
  isMouseButtonReleased(MouseButton.Left) or padButtonReleased(GamepadButton.RightFaceDown)

proc suppressBackThisFrame*() =
  ## Called by the settings rebind capture so the B press that cancels a capture
  ## doesn't also bubble up as "back" and close the window. Sticky through the
  ## next frame: the window-close check may run before the capture code within
  ## a frame, so suppression from the previous capture frame must still hold.
  backSuppressed = true
  backSuppressNext = true

proc isBackPressed*(): bool =
  if isKeyPressed(KeyboardKey.Escape):
    return true
  not backSuppressed and padButtonPressed(GamepadButton.RightFaceRight)

proc isGamepadStartPressed*(): bool =
  padButtonPressed(GamepadButton.MiddleRight)

proc isGamepadConfirmPressed*(): bool =
  padButtonPressed(GamepadButton.RightFaceDown)

proc gamepadNavPressed*(dir: GamepadNavDir): bool =
  case dir
  of gnUp: padButtonPressed(GamepadButton.LeftFaceUp)
  of gnDown: padButtonPressed(GamepadButton.LeftFaceDown)
  of gnLeft: padButtonPressed(GamepadButton.LeftFaceLeft)
  of gnRight: padButtonPressed(GamepadButton.LeftFaceRight)

proc getPointerWheelMove*(): float32 =
  ## Mouse wheel plus, while the pad drives a menu cursor, right-stick Y and
  ## dpad up/down as scroll. Returned in wheel "notches" so existing
  ## scroll-speed math at call sites keeps working.
  result = getMouseWheelMove()
  if isGamepadActive() and cursorMode == cmMenuCursor:
    let rs = rightStick()
    result -= rs.y * StickScrollNotchesPerSec * frameDt
    if dpadScrollAccum != 0:
      result += dpadScrollAccum

# --- rebindable binds -------------------------------------------------------

proc triggerAxisFor(b: GamepadButton): tuple[hasAxis: bool, axis: GamepadAxis] =
  # Digital trigger events are flaky on some backends; accept the analog axis
  # past a threshold as "down" for trigger binds.
  case b
  of GamepadButton.LeftTrigger2: (true, GamepadAxis.LeftTrigger)
  of GamepadButton.RightTrigger2: (true, GamepadAxis.RightTrigger)
  else: (false, GamepadAxis.LeftTrigger)

proc triggerAxisDown(b: GamepadButton): bool =
  if activePad < 0: return false
  let (hasAxis, axis) = triggerAxisFor(b)
  # Trigger axes rest at -1 and reach +1 fully pressed on most backends.
  hasAxis and getGamepadAxisMovement(activePad, axis) > TriggerAxisThreshold

proc isGamepadBindDown*(binds: GamepadBindings, action: KeyAction): bool =
  let b = binds[action]
  if b == GamepadButton.Unknown: return false
  padButtonDown(b) or triggerAxisDown(b)

proc isGamepadBindPressed*(binds: GamepadBindings, action: KeyAction): bool =
  let b = binds[action]
  if b == GamepadButton.Unknown: return false
  padButtonPressed(b)

proc isGamepadBindReleased*(binds: GamepadBindings, action: KeyAction): bool =
  ## Release edge for hold-style actions (e.g. release to place a wall). Only
  ## the digital button edge; trigger-axis binds don't get a synthetic edge.
  let b = binds[action]
  if b == GamepadButton.Unknown: return false
  padButtonReleased(b)

proc gamepadFireDown*(binds: GamepadBindings): bool =
  ## Twin-stick autofire: deflecting the right stick past the threshold fires,
  ## in addition to the bound fire button.
  if not isGamepadActive(): return false
  if isGamepadBindDown(binds, kaShoot): return true
  let rs = rightStick()
  sqrt(rs.x * rs.x + rs.y * rs.y) > AutofireStickThreshold

proc gamepadAnyButtonPressed*(): GamepadButton =
  ## First gamepad button pressed this frame (Unknown if none). Used by the
  ## rebind capture UI; the caller decides which buttons are reserved.
  if activePad < 0: return GamepadButton.Unknown
  for b in GamepadButton.LeftFaceUp .. GamepadButton.RightThumb:
    if isGamepadButtonPressed(activePad, b):
      return b
  GamepadButton.Unknown

proc gamepadBindLabel*(b: GamepadButton): string =
  ## Short ASCII label for the Controls tab (Xbox-style names).
  case b
  of GamepadButton.Unknown: "---"
  of GamepadButton.LeftFaceUp: "DPad Up"
  of GamepadButton.LeftFaceRight: "DPad Right"
  of GamepadButton.LeftFaceDown: "DPad Down"
  of GamepadButton.LeftFaceLeft: "DPad Left"
  of GamepadButton.RightFaceUp: "Y"
  of GamepadButton.RightFaceRight: "B"
  of GamepadButton.RightFaceDown: "A"
  of GamepadButton.RightFaceLeft: "X"
  of GamepadButton.LeftTrigger1: "LB"
  of GamepadButton.LeftTrigger2: "LT"
  of GamepadButton.RightTrigger1: "RB"
  of GamepadButton.RightTrigger2: "RT"
  of GamepadButton.MiddleLeft: "Select"
  of GamepadButton.Middle: "Guide"
  of GamepadButton.MiddleRight: "Start"
  of GamepadButton.LeftThumb: "LS Click"
  of GamepadButton.RightThumb: "RS Click"

# --- per-frame update -------------------------------------------------------

proc anyPadInput(pad: int32): bool =
  # Any button down or stick/trigger deflection counts as "the pad spoke".
  for b in GamepadButton.LeftFaceUp .. GamepadButton.RightThumb:
    if isGamepadButtonDown(pad, b):
      return true
  for axis in [GamepadAxis.LeftX, GamepadAxis.LeftY, GamepadAxis.RightX, GamepadAxis.RightY]:
    if abs(getGamepadAxisMovement(pad, axis)) > StickDeadzone:
      return true
  for axis in [GamepadAxis.LeftTrigger, GamepadAxis.RightTrigger]:
    if getGamepadAxisMovement(pad, axis) > TriggerAxisThreshold:
      return true
  false

proc updateGamepadInput*(dt: float32, virtualWidth, virtualHeight: float32,
                         realMouseVirtualPos: Vector2) =
  ## Call once per frame before the game state machine.
  frameDt = dt
  backSuppressed = backSuppressNext
  backSuppressNext = false

  # Re-scan every frame so hot-plug and mid-game unplug both work. Honor the
  # user's chosen pad when it's connected; otherwise fall back to the first
  # available one so a disconnected preferred pad doesn't kill controller input.
  activePad = -1
  if preferredPad >= 0 and preferredPad < MaxGamepads and isGamepadAvailable(preferredPad):
    activePad = preferredPad
  else:
    for pad in 0'i32 ..< MaxGamepads:
      if isGamepadAvailable(pad):
        activePad = pad
        break

  if activePad < 0:
    device = adMouse
    return

  # Device arbitration. The real mouse always reads via getMouseDelta /
  # raylib button state, never the overridden getVirtualMousePosition
  # (which follows the pad and would feed back into this check).
  let md = getMouseDelta()
  let mouseSpoke = abs(md.x) > MouseWakeDelta or abs(md.y) > MouseWakeDelta or
                   isMouseButtonPressed(MouseButton.Left) or
                   isMouseButtonPressed(MouseButton.Right) or
                   isMouseButtonPressed(MouseButton.Middle)
  let padSpoke = anyPadInput(activePad)

  if device == adMouse:
    if padSpoke and not mouseSpoke:
      device = adGamepad
      cursorPos = realMouseVirtualPos  # seamless handoff: cursor starts where the mouse was
  else:
    if mouseSpoke:
      device = adMouse

  if device != adGamepad:
    return

  # Dpad scroll repeat (consumed by getPointerWheelMove).
  dpadScrollAccum = 0
  let dpadUp = padButtonDown(GamepadButton.LeftFaceUp)
  let dpadDown = padButtonDown(GamepadButton.LeftFaceDown)
  if cursorMode == cmMenuCursor and (dpadUp or dpadDown):
    let dir = if dpadDown: -1.0'f32 else: 1.0'f32
    if dpadScrollHeldTime == 0 or
       (dpadScrollHeldTime > DpadScrollRepeatDelay and
        dpadScrollHeldTime mod DpadScrollRepeatRate < dt):
      dpadScrollAccum = dir
    dpadScrollHeldTime += dt
  else:
    dpadScrollHeldTime = 0

  if cursorMode == cmMenuCursor:
    # Quadratic response: precise near center, fast at the edge.
    let ls = leftStick()
    let len = sqrt(ls.x * ls.x + ls.y * ls.y)
    if len > 0:
      let speed = CursorSpeed * len  # combined with normalized dir = quadratic-ish curve
      cursorPos.x += ls.x / max(len, 0.0001'f32) * speed * len * dt
      cursorPos.y += ls.y / max(len, 0.0001'f32) * speed * len * dt
    cursorPos.x = clamp(cursorPos.x, 0.0'f32, virtualWidth)
    cursorPos.y = clamp(cursorPos.y, 0.0'f32, virtualHeight)
