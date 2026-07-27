## Mobile touch controls: twin virtual joysticks + on-screen action buttons.
##
## Compiled only into `-d:mobile` builds (the sole importer is `input_intent`,
## behind `when defined(mobile)`, and `main` calls the update/draw hooks behind
## the same gate). It owns ALL touch state; `input_intent` reads it to answer the
## high-level intent queries, so no gameplay code ever touches the raw touch API.
##
## Layout (twin-stick, auto-fire):
##   - Left half of the physical screen  -> floating MOVE joystick.
##   - Right half of the physical screen -> floating AIM joystick; auto-fires
##     while held.
##   - Fixed on-screen buttons (in virtual 1024x768 coords): pause, ability
##     (legendary), place-wall. Buttons are hit-tested first and consume their
##     touch so they never spawn a joystick.
##
## Coordinate spaces (see the note in render_context.screenToVirtual):
##   touch input is in physical-screen pixels; joystick vectors are computed in
##   screen space (direction is scale-invariant). Drawing + button hit-tests are
##   done in virtual space via screenToVirtual.
##
## This module must never import game/player (input_intent imports it, and
## player/game import input_intent) — it only depends on raylib + the shared
## Vector2f + the render transform.

import raylib, math
import particle_types
import render_context

const
  MobileAimReach* = 220.0'f32
    ## Virtual-space distance of the synthesized aim target ahead of the player.
    ## Kept under the single-player wall range (250) so aim-directed wall
    ## placement always lands in range.
  Deadzone = 0.16'f32
    ## Fraction of the joystick radius a thumb must travel before it registers,
    ## so a resting/settling finger doesn't drift the player or auto-fire.

type
  VJoystick = object
    active: bool
    id: int32          ## owning touch id (stable per finger)
    baseScreen: Vector2  ## origin where the finger first landed (screen px)
    curScreen: Vector2   ## current finger position (screen px)

const
  ButtonFlashTime = 0.14'f32
    ## How long the pause/ability buttons stay lit after a tap. They are edge
    ## triggered, so without this they would never render as pressed and a tap
    ## would give no confirmation at all.

var
  moveStick: VJoystick
  aimStick: VJoystick
  wallOwnerId: int32 = -1   ## touch id currently holding the wall button (-1 = none)
  # Per-frame edge flags, refreshed every updateMobileControls.
  abilityJustPressed = false
  pauseJustPressed = false
  wallJustReleased = false
  wallIsHeld = false
  prevIds: seq[int32] = @[]
  abilityFlash: float32 = 0
  pauseFlash: float32 = 0

proc joyRadius(): float32 =
  ## Floating-joystick travel radius, scaled to screen height so sensitivity is
  ## roughly DPI-independent across phones.
  max(70.0'f32, getScreenHeight().float32 * 0.13'f32)

# --- On-screen action buttons, in virtual-canvas coordinates -----------------
# Anchored to the live virtual size rather than a hardcoded 1024x768: the HUD
# layout setting switches the canvas between 1024 (classic 4:3) and 1366
# (widescreen 16:9), and mobile defaults to widescreen. Hardcoding would leave
# the buttons 342px short of the right edge, floating over the gameplay world.
# Anchored this way they land in the widescreen gutter, clear of the action.
const
  BtnSize = 96.0'f32
  BtnMargin = 24.0'f32

const MobileActionBarHeight* = (BtnSize + BtnMargin * 2).int32
  ## Height of the bottom-right band the ability + wall buttons occupy, margin
  ## included. HUD elements that bottom-anchor into the right gutter (the
  ## legendary ability strip) must reserve this much or they end up drawn
  ## underneath the buttons. Exported so the reserve and the button layout can
  ## never drift apart.

proc virtualW(): float32 = getVirtualScreenWidth().float32
proc virtualH(): float32 = getVirtualScreenHeight().float32

proc pauseBtnRect(): Rectangle =
  Rectangle(x: virtualW() - BtnSize - BtnMargin, y: BtnMargin,
            width: BtnSize, height: BtnSize)

proc abilityBtnRect(): Rectangle =
  ## Bottom-right, above the wall button.
  Rectangle(x: virtualW() - BtnSize - BtnMargin, y: virtualH() - BtnSize - BtnMargin,
            width: BtnSize, height: BtnSize)

proc wallBtnRect(): Rectangle =
  ## Left of the ability button.
  Rectangle(x: virtualW() - BtnSize * 2 - BtnMargin * 2, y: virtualH() - BtnSize - BtnMargin,
            width: BtnSize, height: BtnSize)

proc pointInRect(p: Vector2, r: Rectangle): bool =
  p.x >= r.x and p.x <= r.x + r.width and p.y >= r.y and p.y <= r.y + r.height

proc idPresent(ids: openArray[int32], id: int32): bool =
  for i in ids:
    if i == id: return true
  false

proc screenPosOf(id: int32): Vector2 =
  ## Current screen position of the touch with this id (zero if gone this frame).
  for i in 0'i32 ..< getTouchPointCount():
    if getTouchPointId(i) == id:
      return getTouchPosition(i)
  Vector2(x: 0, y: 0)

proc updateMobileControls*(dt: float32) =
  ## Poll touches, (re)assign joysticks and buttons. Call once per frame in the
  ## gsPlaying update branch, before input_intent is queried.
  # Snapshot this frame's touches.
  let n = getTouchPointCount()
  var ids: seq[int32] = @[]
  for i in 0'i32 ..< n:
    ids.add(getTouchPointId(i))

  # Reset one-shot edge flags.
  abilityJustPressed = false
  pauseJustPressed = false
  wallJustReleased = false
  abilityFlash = max(0.0'f32, abilityFlash - dt)
  pauseFlash = max(0.0'f32, pauseFlash - dt)

  let midX = getScreenWidth().float32 / 2.0'f32

  # New touches (down this frame): buttons first (consume), else claim a stick.
  for i in 0'i32 ..< n:
    let id = getTouchPointId(i)
    if idPresent(prevIds, id): continue  # only react to fresh touch-downs
    let screen = getTouchPosition(i)
    let v = screenToVirtual(screen)
    if pointInRect(v, pauseBtnRect()):
      pauseJustPressed = true
      pauseFlash = ButtonFlashTime
    elif pointInRect(v, abilityBtnRect()):
      abilityJustPressed = true
      abilityFlash = ButtonFlashTime
    elif pointInRect(v, wallBtnRect()):
      # Only the first finger owns the button. Without this guard a second
      # finger landing on it would overwrite wallOwnerId and strand the first,
      # leaving the wall preview stuck on until some unrelated touch ended.
      if wallOwnerId < 0:
        wallOwnerId = id
        wallIsHeld = true
    elif screen.x < midX and not moveStick.active:
      moveStick = VJoystick(active: true, id: id, baseScreen: screen, curScreen: screen)
    elif screen.x >= midX and not aimStick.active:
      aimStick = VJoystick(active: true, id: id, baseScreen: screen, curScreen: screen)
    # Extra simultaneous touches beyond the above are ignored.

  # Update / release the joysticks.
  if moveStick.active:
    if idPresent(ids, moveStick.id): moveStick.curScreen = screenPosOf(moveStick.id)
    else: moveStick.active = false
  if aimStick.active:
    if idPresent(ids, aimStick.id): aimStick.curScreen = screenPosOf(aimStick.id)
    else: aimStick.active = false

  # Wall button hold/release (mirrors desktop hold-E / release-to-place).
  if wallOwnerId >= 0 and not idPresent(ids, wallOwnerId):
    wallIsHeld = false
    wallJustReleased = true
    wallOwnerId = -1

  prevIds = ids

proc resetMobileControls*() =
  ## Drop all touch state. Call when gameplay is interrupted by a state that
  ## doesn't run updateMobileControls (pause, power-up select, shop): a finger
  ## lifted while the update loop is not running would otherwise leave a stick
  ## or -- worse -- the wall button latched on, and the latch survives until
  ## some unrelated touch happens to end.
  moveStick.active = false
  aimStick.active = false
  wallOwnerId = -1
  wallIsHeld = false
  abilityJustPressed = false
  pauseJustPressed = false
  wallJustReleased = false
  prevIds.setLen(0)

# --- Vector queries used by input_intent -------------------------------------

proc stickVector(j: VJoystick): Vector2f =
  ## Screen-space offset normalized to [-1,1] per axis by the joystick radius,
  ## with a deadzone. Direction is preserved through the letterbox (uniform
  ## scale), so screen-space is fine for a direction.
  if not j.active: return newVector2f(0, 0)
  let r = joyRadius()
  var off = newVector2f(j.curScreen.x - j.baseScreen.x, j.curScreen.y - j.baseScreen.y)
  let mag = off.length()
  if mag < r * Deadzone: return newVector2f(0, 0)
  let clamped = min(mag, r)
  off = off.normalize() * (clamped / r)
  off

proc mobileMoveVector*(): Vector2f = stickVector(moveStick)
proc mobileAimVector*(): Vector2f = stickVector(aimStick)
proc mobileIsAiming*(): bool = aimStick.active and stickVector(aimStick).length() > 0.0'f32
proc mobileAbilityPressed*(): bool = abilityJustPressed
proc mobilePausePressed*(): bool = pauseJustPressed
proc mobileWallHeld*(): bool = wallIsHeld
proc mobileWallReleased*(): bool = wallJustReleased

# --- Rendering ---------------------------------------------------------------

proc drawStick(j: VJoystick, tint: Color) =
  if not j.active: return
  let r = joyRadius()
  let baseV = screenToVirtual(j.baseScreen)
  # Clamp the knob to the radius before mapping to virtual space.
  var off = Vector2(x: j.curScreen.x - j.baseScreen.x, y: j.curScreen.y - j.baseScreen.y)
  let mag = sqrt(off.x * off.x + off.y * off.y)
  if mag > r and mag > 0.0'f32:
    off.x = off.x / mag * r
    off.y = off.y / mag * r
  let knobV = screenToVirtual(Vector2(x: j.baseScreen.x + off.x, y: j.baseScreen.y + off.y))
  # Screen radius r -> virtual radius via the letterbox scale.
  let ringR = r / max(getRenderScale(), 0.0001'f32)
  let outer = Color(r: tint.r, g: tint.g, b: tint.b, a: 60)
  let inner = Color(r: tint.r, g: tint.g, b: tint.b, a: 150)
  drawCircleLines(baseV.x.int32, baseV.y.int32, ringR, outer)
  drawCircle(knobV, 26, inner)

proc drawActionButton(r: Rectangle, held: bool, glyph: proc(cx, cy: float32)) =
  let a: uint8 = if held: 200 else: 110
  drawRectangleRounded(r, 0.35, 8, Color(r: 40, g: 46, b: 66, a: a))
  drawRectangleRoundedLines(r, 0.35, 8, 2.0, Color(r: 180, g: 200, b: 255, a: 200))
  glyph(r.x + r.width / 2, r.y + r.height / 2)

proc drawMobileControls*() =
  ## Draw joysticks + buttons. Call inside the virtual-canvas draw pass (during
  ## gsPlaying), after the HUD so controls sit on top.
  drawStick(moveStick, Color(r: 120, g: 220, b: 255, a: 255))
  drawStick(aimStick, Color(r: 255, g: 170, b: 90, a: 255))

  # Pause button: two vertical bars.
  drawActionButton(pauseBtnRect(), pauseFlash > 0, proc(cx, cy: float32) =
    drawRectangle((cx - 14).int32, (cy - 16).int32, 9, 32, White)
    drawRectangle((cx + 5).int32, (cy - 16).int32, 9, 32, White))

  # Ability button: a bright gem/dot (avoids triangle winding/cull concerns).
  drawActionButton(abilityBtnRect(), abilityFlash > 0, proc(cx, cy: float32) =
    drawCircle(Vector2(x: cx, y: cy), 20, Color(r: 255, g: 230, b: 120, a: 255)))

  # Wall button: a small slab; brighter while held.
  drawActionButton(wallBtnRect(), wallIsHeld, proc(cx, cy: float32) =
    drawRectangle((cx - 20).int32, (cy - 8).int32, 40, 16, Color(r: 200, g: 150, b: 90, a: 255)))
