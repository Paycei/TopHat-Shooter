## Mobile touch controls: twin virtual joysticks + on-screen thumb buttons.
##
## Compiled only into `-d:mobile` builds (importers: `input_intent`, `main` and
## `ui/hud_dock`, all behind `when defined(mobile)`). It owns ALL gameplay touch
## state; `input_intent` reads it to answer the high-level intent queries, so no
## gameplay code ever touches the raw touch API.
##
## Layout (twin-stick, auto-fire):
##   - Left half of the physical screen  -> floating MOVE joystick.
##   - Right half of the physical screen -> floating AIM joystick; auto-fires
##     while held. Both sticks drag their base along when the thumb overshoots
##     the rim, so reversing direction never needs the thumb to travel back.
##   - One row of round thumb buttons in the bottom-right corner: WALL, ABILITY
##     and -- in the corner, biggest, because it is the most used and the most
##     time-critical -- DASH. A small PAUSE button sits in the arena's top-right
##     corner. Buttons are hit-tested first and consume their touch, so they
##     never spawn a joystick.
##
## The buttons show state main.nim pushes in every frame (setMobileDashState /
## setMobileAbilityState / setMobileWallState / setMobileSkipProgress), because
## this module can't read the player: the dash cooldown sweep, ability
## readiness and countdown, wall charges, and the wall button turning into USE
## beside a roguelite pickup (it is the interact control on touch).
##
## The wall button doubles as a mini-stick: drag from it to aim the wall,
## release to place. Without that a touch player could not place walls at all
## -- the right thumb has to leave the aim stick to hold the button, and a wall
## projected along a zero aim lands on the player, which is never valid.
##
## Coordinate spaces: touch input is in physical-screen pixels; stick vectors
## are computed in screen space (direction is scale-invariant). Drawing and
## button hit-tests are in PLAIN virtual pixels (screenToVirtual/getCanvasSize),
## never a UI-scale layer's: touch targets are sized for thumbs, not for the UI
## scale setting, which is why main draws this outside the HUD layer.
##
## This module must never import game/player (input_intent imports it, and
## player/game import input_intent) -- it depends on raylib, the shared
## Vector2f, the render transform and the (leaf) string tables only.

import raylib, math
import particle_types
import render_context
import localization

const
  MobileAimReach* = 220.0'f32
    ## Virtual-space distance of the synthesized aim target ahead of the player.
    ## Kept under the single-player wall range (250) so aim-directed wall
    ## placement always lands in range.
  Deadzone = 0.16'f32
    ## Fraction of the joystick radius a thumb must travel before it registers,
    ## so a resting/settling finger doesn't drift the player or auto-fire.

  # --- thumb buttons, plain virtual px ---------------------------------------
  DashBtnD = 108.0'f32
  SideBtnD = 92.0'f32
  PauseBtnD = 64.0'f32
  RowMargin = 16.0'f32
  RowGap = 14.0'f32
  HitSlop = 6.0'f32
    ## Extra hit radius past the drawn circle: a fingertip lands a little wide of
    ## what it aims at. Under RowGap / 2, so neighbours never share a point.

const MobileActionBarHeight* = (DashBtnD + RowMargin * 2).int32
  ## Height of the bottom-right band the button row occupies, margin included.
  ## HUD that bottom-anchors into the right gutter (the [Q] strip and the combo
  ## card on it) reserves this through hud_dock.touchControlsReserve, or it is
  ## drawn underneath the buttons. Exported so the reserve and the layout can
  ## never drift apart.
  ##
  ## The buttons share ONE row on purpose: a second row would double this band
  ## and push the whole bottom HUD stack up a screen that is already short on
  ## vertical room.

const
  ButtonFlashTime = 0.14'f32
    ## How long an edge-triggered button stays lit after a tap. Without it a tap
    ## would never render as pressed and would give no confirmation at all.
  ReadyPingTime = 0.45'f32
    ## The ring that expands off a button the moment it becomes usable again.
  PauseTapMax = 0.45'f32
    ## A pause touch shorter than this pauses, on RELEASE. Longer holds belong to
    ## hold actions (the tutorial's hold-to-skip), and a thumb resting on the
    ## button never pauses by accident either.
  TapMaxTime = 0.30'f32
    ## A stick-area touch released within this, and within tapSlop(), is a tap
    ## (mobileTapPressed) -- the touch "continue" of the tutorial's read cards.
  WallDragDeadzone = 0.28'f32
    ## Fraction of the stick radius a drag off the wall button must cover before
    ## it steers the wall; a thumb settling on the button stays a plain hold.
  LearnTime = 0.6'f32
    ## Seconds of deflected use after which a stick's idle hint retires.

  # Palette: mirrors ui/hud_dock's Dock* colours so the controls read as part of
  # the HUD. Not imported: hud_dock reads MobileActionBarHeight from here.
  Ink = Color(r: 228, g: 240, b: 250, a: 255)
  GlassBg = Color(r: 9, g: 16, b: 26, a: 205)
  GlassBgLit = Color(r: 24, g: 40, b: 60, a: 235)
  DashAccent = Color(r: 0, g: 220, b: 255, a: 255)
  AbilityAccent = Color(r: 255, g: 200, b: 80, a: 255)
  WallAccent = Color(r: 255, g: 160, b: 80, a: 255)
  UseAccent = Color(r: 120, g: 225, b: 140, a: 255)
  PauseAccent = Color(r: 150, g: 178, b: 205, a: 255)
  SkipAccent = Color(r: 255, g: 110, b: 90, a: 255)
  MoveAccent = Color(r: 120, g: 220, b: 255, a: 255)
  AimAccent = Color(r: 255, g: 170, b: 90, a: 255)
  FireAccent = Color(r: 255, g: 110, b: 70, a: 255)

type
  VJoystick = object
    active: bool
    id: int32             ## owning touch id (stable per finger)
    baseScreen: Vector2   ## stick centre (screen px); follows an overshooting thumb
    curScreen: Vector2    ## current finger position (screen px)

  TouchRole = enum
    trNone, trMove, trAim, trPause, trAbility, trWall, trDash

  TouchTrack = object
    ## One live finger, from touch-down to lift-off. Roles are decided once, on
    ## the frame the finger lands, which is what lets a thumb that slides off a
    ## button keep owning it (and a stick keep its finger across the midline).
    id: int32
    role: TouchRole
    startTime: float32
    startScreen: Vector2
    maxTravel: float32    ## furthest the finger got from where it landed (screen px)

var
  clock: float32 = 0
  tracks: seq[TouchTrack] = @[]
  moveStick: VJoystick
  aimStick: VJoystick
  # Per-frame edge flags, refreshed every updateMobileControls.
  abilityJustPressed = false
  pauseJustPressed = false
  wallJustReleased = false
  dashJustPressed = false
  tapJustPressed = false
  wallIsHeld = false
  wallOwnerId: int32 = -1
  wallPressScreen = Vector2(x: 0, y: 0)
  wallDragDir = newVector2f(0, 0)
    ## Direction the wall touch is dragged in (zero while it isn't). Survives the
    ## release frame, because that is the frame the wall is placed on.
  pauseHeldSince: float32 = -1   ## clock at the pause touch-down, -1 when not held
  lastAimDir = newVector2f(0, 0)
  lastMoveDir = newVector2f(0, 0)
  # Feedback timers.
  abilityFlash: float32 = 0
  pauseFlash: float32 = 0
  dashFlash: float32 = 0
  dashReadyPing: float32 = 0
  abilityReadyPing: float32 = 0
  # Onboarding: seconds each stick has been used for this session. Its idle hint
  # is shown until the player has actually steered with it.
  moveUseTime: float32 = 0
  aimUseTime: float32 = 0
  # State pushed in from main.nim (see the module doc).
  dashAvailable = false
    ## Whether a base dash can be offered right now (false e.g. while the local
    ## PvP player is down). Defaults to off and is pushed each frame by the
    ## gsPlaying/gsPvPPlaying branches, so a mode that forgets to push gets no
    ## button rather than a dead one that also eats the aim stick's touches.
  dashCooldownRatio: float32 = 0   ## 0 = ready, 1 = just used
  abilityAvailable = false         ## owns a [Q] ability (or a mod may bind one)
  abilityReadyCount = 0
  abilityCooldownLeft: float32 = 0 ## seconds until the soonest one is back
  wallCharges = 0
  wallInteract = false             ## a roguelite pickup is in reach: the button is USE
  skipProgress: float32 = 0        ## tutorial hold-to-skip fill, 0..1

proc joyRadius(): float32 =
  ## Floating-joystick travel radius, scaled to screen height so sensitivity is
  ## roughly DPI-independent across phones.
  max(70.0'f32, getScreenHeight().float32 * 0.13'f32)

proc tapSlop(): float32 =
  ## Screen-px travel under which a touch still counts as a tap.
  joyRadius() * 0.2'f32

proc toVirtualLen(screenLen: float32): float32 =
  screenLen / max(getRenderScale(), 0.0001'f32)

# --- Layout (plain virtual px) ------------------------------------------------
# Anchored to the live canvas rather than a hardcoded 1024x768: mobile fits the
# widescreen canvas to the device aspect (main.mobileVirtualWidth), so on a
# 19.5:9 or 20:9 phone the whole row lands in the right gutter, clear of the
# arena.

proc rowCenterY(): float32 =
  getCanvasSize().y - RowMargin - DashBtnD * 0.5'f32

proc dashCenter(): Vector2 =
  Vector2(x: getCanvasSize().x - RowMargin - DashBtnD * 0.5'f32, y: rowCenterY())

proc abilityCenter(): Vector2 =
  Vector2(x: dashCenter().x - DashBtnD * 0.5'f32 - RowGap - SideBtnD * 0.5'f32,
          y: rowCenterY())

proc wallCenter(): Vector2 =
  Vector2(x: abilityCenter().x - SideBtnD - RowGap, y: rowCenterY())

proc pauseCenter(): Vector2 =
  ## The arena's top-right corner rather than the screen's: in widescreen the
  ## screen corner belongs to the right dock's objective card. In PvE this is
  ## also inside the band the world zoom takes out of reach (mobileViewInset),
  ## so the button can never sit on top of the player.
  let arenaRight = min(getCanvasSize().x,
                       getWorldViewOffsetX() + BaseVirtualWidth.float32 * getWorldViewScale())
  let arenaTop = max(0.0'f32, getWorldViewOffsetY())
  Vector2(x: arenaRight - 12.0'f32 - PauseBtnD * 0.5'f32,
          y: arenaTop + 12.0'f32 + PauseBtnD * 0.5'f32)

proc hitCircle(p, c: Vector2, diameter: float32): bool =
  let dx = p.x - c.x
  let dy = p.y - c.y
  let r = diameter * 0.5'f32 + HitSlop
  dx * dx + dy * dy <= r * r

# --- Touch tracking -----------------------------------------------------------

proc screenPosOf(id: int32, pos: var Vector2): bool =
  ## Current screen position of the touch with this id; false once it is gone.
  for i in 0'i32 ..< getTouchPointCount():
    if getTouchPointId(i) == id:
      pos = getTouchPosition(i)
      return true
  false

proc isTracked(id: int32): bool =
  for t in tracks:
    if t.id == id: return true
  false

proc pressTrack(id: int32, screen: Vector2): TouchTrack =
  ## Decide what a fresh finger is: a button (checked first, and consumed) or a
  ## stick for whichever half of the screen it landed on.
  result = TouchTrack(id: id, role: trNone, startTime: clock, startScreen: screen)
  let v = screenToVirtual(screen)
  let midX = getScreenWidth().float32 / 2.0'f32
  if hitCircle(v, pauseCenter(), PauseBtnD):
    result.role = trPause
    pauseHeldSince = clock
  elif abilityAvailable and hitCircle(v, abilityCenter(), SideBtnD):
    # Edge on press, like the dash: an ability is a reflex. main decides which
    # (if any) are off cooldown, so a press is always forwarded; the flash only
    # answers presses that can actually do something.
    result.role = trAbility
    abilityJustPressed = true
    if abilityReadyCount > 0:
      abilityFlash = ButtonFlashTime
  elif hitCircle(v, wallCenter(), SideBtnD):
    # Only the first finger owns the button. Without this guard a second finger
    # landing on it would overwrite the owner and strand the first, leaving the
    # wall preview stuck on until some unrelated touch ended.
    if wallOwnerId < 0:
      result.role = trWall
      wallOwnerId = id
      wallIsHeld = true
      wallPressScreen = screen
      wallDragDir = newVector2f(0, 0)
  elif dashAvailable and hitCircle(v, dashCenter(), DashBtnD):
    # The touch is consumed either way, so a tap on a cooling dash never falls
    # through and spawns an aim joystick under the thumb.
    result.role = trDash
    if dashCooldownRatio <= 0.0'f32:
      dashJustPressed = true
      dashFlash = ButtonFlashTime
  elif screen.x < midX and not moveStick.active:
    result.role = trMove
    moveStick = VJoystick(active: true, id: id, baseScreen: screen, curScreen: screen)
  elif screen.x >= midX and not aimStick.active:
    result.role = trAim
    aimStick = VJoystick(active: true, id: id, baseScreen: screen, curScreen: screen)
  # Anything else (a third finger on an occupied half) stays trNone: ignored,
  # but still able to count as a tap.

proc releaseTrack(t: TouchTrack) =
  case t.role
  of trMove: moveStick.active = false
  of trAim: aimStick.active = false
  of trPause:
    if clock - t.startTime <= PauseTapMax:
      pauseJustPressed = true
      pauseFlash = ButtonFlashTime
    pauseHeldSince = -1
  of trWall:
    # Mirrors desktop hold-E / release-to-place. wallDragDir is left for this
    # frame's placement and cleared at the start of the next one.
    wallIsHeld = false
    wallJustReleased = true
    wallOwnerId = -1
  of trAbility, trDash, trNone:
    discard
  if t.role in {trNone, trMove, trAim} and clock - t.startTime <= TapMaxTime and
     t.maxTravel <= tapSlop():
    tapJustPressed = true

proc followStick(j: var VJoystick) =
  ## Track the owning finger, and drag the base along once the thumb overshoots
  ## the rim: the stick then always sits one radius behind the thumb, so a
  ## reversal takes effect at once instead of after the thumb travels back.
  if not j.active: return
  var p: Vector2
  if not screenPosOf(j.id, p): return
  j.curScreen = p
  let dx = p.x - j.baseScreen.x
  let dy = p.y - j.baseScreen.y
  let d = sqrt(dx * dx + dy * dy)
  let r = joyRadius()
  if d > r:
    let k = (d - r) / d
    j.baseScreen.x += dx * k
    j.baseScreen.y += dy * k

proc stickVector(j: VJoystick): Vector2f =
  ## Screen-space offset normalized to [-1,1] per axis by the joystick radius,
  ## with a deadzone. Direction is preserved through the letterbox (uniform
  ## scale), so screen-space is fine for a direction.
  if not j.active: return newVector2f(0, 0)
  let r = joyRadius()
  var off = newVector2f(j.curScreen.x - j.baseScreen.x, j.curScreen.y - j.baseScreen.y)
  let mag = off.length()
  if mag < r * Deadzone: return newVector2f(0, 0)
  off.normalize() * (min(mag, r) / r)

proc updateMobileControls*(dt: float32) =
  ## Poll touches, (re)assign sticks and buttons. Call once per frame in the
  ## gameplay update branches, before input_intent is queried.
  clock += dt
  abilityJustPressed = false
  pauseJustPressed = false
  wallJustReleased = false
  dashJustPressed = false
  tapJustPressed = false
  if not wallIsHeld:
    wallDragDir = newVector2f(0, 0)
  abilityFlash = max(0.0'f32, abilityFlash - dt)
  pauseFlash = max(0.0'f32, pauseFlash - dt)
  dashFlash = max(0.0'f32, dashFlash - dt)
  dashReadyPing = max(0.0'f32, dashReadyPing - dt)
  abilityReadyPing = max(0.0'f32, abilityReadyPing - dt)

  # Lift-offs first, so a finger that lifts while another lands in the same
  # frame is resolved before the newcomer claims anything.
  var i = 0
  while i < tracks.len:
    var p: Vector2
    if screenPosOf(tracks[i].id, p):
      let dx = p.x - tracks[i].startScreen.x
      let dy = p.y - tracks[i].startScreen.y
      tracks[i].maxTravel = max(tracks[i].maxTravel, sqrt(dx * dx + dy * dy))
      inc i
    else:
      releaseTrack(tracks[i])
      tracks.delete(i)

  for k in 0'i32 ..< getTouchPointCount():
    let id = getTouchPointId(k)
    if not isTracked(id):
      tracks.add pressTrack(id, getTouchPosition(k))

  followStick(moveStick)
  followStick(aimStick)

  # The wall button's own drag steers the wall.
  if wallIsHeld and wallOwnerId >= 0:
    var p: Vector2
    if screenPosOf(wallOwnerId, p):
      let off = newVector2f(p.x - wallPressScreen.x, p.y - wallPressScreen.y)
      wallDragDir = if off.length() > joyRadius() * WallDragDeadzone: off.normalize()
                    else: newVector2f(0, 0)

  let mv = stickVector(moveStick)
  if mv.length() > 0.0'f32:
    lastMoveDir = mv.normalize()
    moveUseTime += dt
  let av = stickVector(aimStick)
  if av.length() > 0.0'f32:
    lastAimDir = av.normalize()
    aimUseTime += dt

proc resetMobileControls*() =
  ## Drop all touch state. Call when gameplay is interrupted by a state that
  ## doesn't run updateMobileControls (pause, power-up select, shop): a finger
  ## lifted while the update loop is not running would otherwise leave a stick
  ## or -- worse -- the wall button latched on, and the latch survives until
  ## some unrelated touch happens to end.
  tracks.setLen(0)
  moveStick.active = false
  aimStick.active = false
  wallOwnerId = -1
  wallIsHeld = false
  wallDragDir = newVector2f(0, 0)
  pauseHeldSince = -1
  abilityJustPressed = false
  pauseJustPressed = false
  wallJustReleased = false
  dashJustPressed = false
  tapJustPressed = false
  dashAvailable = false
  abilityAvailable = false
  skipProgress = 0

# --- Queries used by input_intent ---------------------------------------------

proc mobileMoveVector*(): Vector2f = stickVector(moveStick)
proc mobileAimVector*(): Vector2f = stickVector(aimStick)
proc mobileIsAiming*(): bool = aimStick.active and stickVector(aimStick).length() > 0.0'f32
proc mobileAbilityPressed*(): bool = abilityJustPressed
proc mobilePausePressed*(): bool = pauseJustPressed
proc mobilePauseHeld*(): bool = pauseHeldSince >= 0.0'f32
proc mobileWallHeld*(): bool = wallIsHeld
proc mobileWallReleased*(): bool = wallJustReleased
proc mobileDashPressed*(): bool = dashJustPressed

proc mobileTapPressed*(): bool =
  ## A quick tap anywhere that isn't a button, by any finger -- tracked per touch
  ## point, so it still registers while the other thumb is holding a stick.
  tapJustPressed

proc mobileAimTargetDir*(): Vector2f =
  ## Direction for aim-projected targeting (wall placement), normalized: the
  ## wall button's own drag while it has one, else the live aim stick, else the
  ## last way the player aimed, else the last way they moved, else up.
  if wallDragDir.length() > 0.0'f32: return wallDragDir
  let a = stickVector(aimStick)
  if a.length() > 0.0'f32: a.normalize()
  elif lastAimDir.length() > 0.0'f32: lastAimDir
  elif lastMoveDir.length() > 0.0'f32: lastMoveDir
  else: newVector2f(0, -1)

# --- State pushed in by main.nim ----------------------------------------------

proc setMobileDashState*(available: bool, cooldownRatio: float32) =
  ## Whether a dash button should exist this frame and, if so, its cooldown as
  ## 0 (ready) .. 1 (just spent), for the recharge sweep.
  let ratio = clamp(cooldownRatio, 0.0'f32, 1.0'f32)
  if available and dashAvailable and dashCooldownRatio > 0.0'f32 and ratio <= 0.0'f32:
    dashReadyPing = ReadyPingTime
  elif ratio > 0.0'f32:
    dashReadyPing = 0  # spent again mid-ping: the "it's back" ring would now lie
  dashAvailable = available
  dashCooldownRatio = ratio

proc setMobileAbilityState*(available: bool, readyCount: int, cooldownLeft: float32) =
  ## The [Q] abilities: whether the button exists at all (no abilities owned ->
  ## no dead button eating aim touches), how many are ready, and the seconds
  ## until the soonest cooling one is back.
  if available and abilityAvailable and abilityReadyCount == 0 and readyCount > 0:
    abilityReadyPing = ReadyPingTime
  elif readyCount == 0:
    abilityReadyPing = 0
  abilityAvailable = available
  abilityReadyCount = readyCount
  abilityCooldownLeft = max(0.0'f32, cooldownLeft)

proc setMobileWallState*(charges: int, interact: bool) =
  ## Wall charges for the badge, and whether a roguelite pickup is in reach --
  ## the button is the interact control on touch (input_intent.interactPressed),
  ## so it says USE then.
  wallCharges = max(0, charges)
  wallInteract = interact

proc setMobileSkipProgress*(progress: float32) =
  ## Fill of a hold-to-skip running on the pause button (the tutorial), 0..1.
  skipProgress = clamp(progress, 0.0'f32, 1.0'f32)

# --- Rendering ----------------------------------------------------------------

proc fade(c: Color, k: float32): Color =
  Color(r: c.r, g: c.g, b: c.b, a: uint8(clamp(c.a.float32 * k, 0.0'f32, 255.0'f32)))

proc drawRim(c: Vector2, r, thick: float32, col: Color,
             startAngle = 0.0'f32, endAngle = 360.0'f32) =
  drawRing(c, r - thick, r, startAngle, endAngle, 48, col)

proc drawCaption(text: string, c: Vector2, y: float32, col: Color) =
  const size = 11'i32
  let w = measureText(text, size)
  drawText(text, int32(c.x - w.float32 * 0.5'f32), int32(y), size, col)

proc drawBadge(c: Vector2, r: float32, text: string, col: Color) =
  ## Small count bubble on the button's upper-right shoulder.
  let bc = Vector2(x: c.x + r * 0.70'f32, y: c.y - r * 0.70'f32)
  const size = 12'i32
  let w = measureText(text, size).float32
  let br = max(11.0'f32, w * 0.5'f32 + 5.0'f32)
  drawCircle(bc, br, Color(r: 6, g: 10, b: 18, a: 240))
  drawRim(bc, br, 1.5'f32, col)
  drawText(text, int32(bc.x - w * 0.5'f32), int32(bc.y - 6.0'f32), size, Ink)

proc drawButtonBody(c: Vector2, r: float32, accent: Color, pressed, enabled: bool) =
  ## Dark glass disc with an accent rim -- the HUD dock's card language, round.
  drawCircle(Vector2(x: c.x + 2, y: c.y + 3), r, Color(r: 0, g: 0, b: 0, a: 110))
  drawCircle(c, r, if pressed: GlassBgLit else: GlassBg)
  # Faint sheen on the upper half, so the disc reads as a raised key.
  drawCircleSector(c, r - 3.0'f32, 180.0'f32, 360.0'f32, 24,
                   Color(r: 255, g: 255, b: 255, a: 10))
  drawRim(c, r, 2.5'f32, fade(accent, if not enabled: 0.30'f32
                                      elif pressed: 1.0'f32
                                      else: 0.75'f32))

proc drawReadyPing(c: Vector2, r, timer: float32, accent: Color) =
  if timer <= 0.0'f32: return
  let k = 1.0'f32 - timer / ReadyPingTime
  drawRim(c, r + 2.0'f32 + 14.0'f32 * k, 2.0'f32, fade(accent, 0.8'f32 * (1.0'f32 - k)))

proc drawChevrons(c: Vector2, s: float32, col: Color) =
  ## Dash glyph: a double chevron. Lines, not triangles, so there is no winding
  ## order to get wrong on a mirrored glyph.
  for k in 0 .. 1:
    let ox = c.x - 9.0'f32 * s + k.float32 * 15.0'f32 * s
    drawLine(Vector2(x: ox - 7 * s, y: c.y - 12 * s), Vector2(x: ox + 5 * s, y: c.y), 4.5'f32 * s, col)
    drawLine(Vector2(x: ox + 5 * s, y: c.y), Vector2(x: ox - 7 * s, y: c.y + 12 * s), 4.5'f32 * s, col)

proc drawGem(c: Vector2, s: float32, col: Color) =
  ## Ability glyph: a faceted diamond (the legendary tier's shape).
  drawPoly(c, 4, 15.0'f32 * s, 0.0'f32, col)
  drawPoly(c, 4, 7.0'f32 * s, 0.0'f32, Color(r: 255, g: 250, b: 220, a: col.a))

proc drawBricks(c: Vector2, s: float32, col: Color) =
  ## Wall glyph: two courses of bricks in a running bond.
  let bw = 13.0'f32 * s
  let bh = 7.0'f32 * s
  let g = 2.0'f32 * s
  let left = c.x - bw - g * 0.5'f32
  let top = c.y - bh - g * 0.5'f32
  for k in 0 .. 1:
    drawRectangle(Rectangle(x: left + k.float32 * (bw + g), y: top, width: bw, height: bh), col)
  # Half + full + half: the same total width as the course above.
  let half = (bw - g) * 0.5'f32
  drawRectangle(Rectangle(x: left, y: top + bh + g, width: half, height: bh), col)
  drawRectangle(Rectangle(x: left + half + g, y: top + bh + g, width: bw, height: bh), col)
  drawRectangle(Rectangle(x: left + half + bw + g * 2, y: top + bh + g,
                          width: half, height: bh), col)

proc drawInstallArrow(c: Vector2, s: float32, col: Color) =
  ## USE glyph: an arrow dropping into a tray -- "install", in the OS theme.
  drawLine(Vector2(x: c.x, y: c.y - 13 * s), Vector2(x: c.x, y: c.y + 4 * s), 4.0'f32 * s, col)
  drawLine(Vector2(x: c.x - 8 * s, y: c.y - 4 * s), Vector2(x: c.x, y: c.y + 5 * s), 4.0'f32 * s, col)
  drawLine(Vector2(x: c.x + 8 * s, y: c.y - 4 * s), Vector2(x: c.x, y: c.y + 5 * s), 4.0'f32 * s, col)
  drawRectangle(Rectangle(x: c.x - 13 * s, y: c.y + 10 * s, width: 26 * s, height: 3.5'f32 * s), col)

proc dirAngle(d: Vector2f): float32 =
  ## raylib's ring angles: degrees, clockwise from +x in the y-down canvas.
  arctan2(d.y, d.x) * 180.0'f32 / PI.float32

proc drawDashButton() =
  if not dashAvailable: return
  let c = dashCenter()
  let ready = dashCooldownRatio <= 0.0'f32
  let pressed = dashFlash > 0.0'f32
  let r = DashBtnD * 0.5'f32 * (if pressed: 0.93'f32 else: 1.0'f32)
  drawButtonBody(c, r, DashAccent, pressed, ready)
  if not ready:
    # Recharge sweep: the rim refills clockwise from the top as the dash comes
    # back, so readiness is legible at a glance without reading a number.
    drawRim(c, r, 3.5'f32, fade(DashAccent, 0.95'f32), -90.0'f32,
            -90.0'f32 + 360.0'f32 * (1.0'f32 - dashCooldownRatio))
  drawReadyPing(c, r, dashReadyPing, DashAccent)
  let glyph = Vector2(x: c.x, y: c.y - r * 0.12'f32)
  drawChevrons(glyph, 1.25'f32, if ready: Ink else: Color(r: 120, g: 132, b: 150, a: 200))
  drawCaption(t(tkHUDKeyDash), c, c.y + r * 0.40'f32, fade(Ink, if ready: 0.85'f32 else: 0.45'f32))

proc drawAbilityButton() =
  if not abilityAvailable: return
  let c = abilityCenter()
  let ready = abilityReadyCount > 0
  let pressed = abilityFlash > 0.0'f32
  let r = SideBtnD * 0.5'f32 * (if pressed: 0.93'f32 else: 1.0'f32)
  if ready:
    # A slow halo while something is ready to fire.
    let pulse = 0.5'f32 + 0.5'f32 * sin(clock * 4.0'f32)
    drawRim(c, r + 4.0'f32, 3.0'f32, fade(AbilityAccent, 0.18'f32 + 0.22'f32 * pulse))
  drawButtonBody(c, r, AbilityAccent, pressed, ready)
  drawReadyPing(c, r, abilityReadyPing, AbilityAccent)
  let glyph = Vector2(x: c.x, y: c.y - r * 0.14'f32)
  if ready:
    drawGem(glyph, 1.0'f32, AbilityAccent)
    if abilityReadyCount > 1:
      drawBadge(c, r, $abilityReadyCount, AbilityAccent)
  elif abilityCooldownLeft > 0.0'f32:
    # Countdown to the soonest ability, in the glyph's place.
    let secs = $int(ceil(abilityCooldownLeft))
    const size = 24'i32
    let w = measureText(secs, size)
    drawText(secs, int32(glyph.x) - w div 2, int32(glyph.y) - size div 2, size,
             fade(AbilityAccent, 0.8'f32))
  else:
    drawGem(glyph, 1.0'f32, Color(r: 120, g: 120, b: 130, a: 190))
  drawCaption(t(tkHUDKeyAbility), c, c.y + r * 0.40'f32,
              fade(Ink, if ready: 0.85'f32 else: 0.45'f32))

proc drawWallButton() =
  let c = wallCenter()
  let r = SideBtnD * 0.5'f32 * (if wallIsHeld: 0.93'f32 else: 1.0'f32)
  let glyph = Vector2(x: c.x, y: c.y - r * 0.14'f32)
  if wallInteract:
    drawButtonBody(c, r, UseAccent, wallIsHeld, true)
    let pulse = 0.5'f32 + 0.5'f32 * sin(clock * 5.0'f32)
    drawRim(c, r + 4.0'f32, 3.0'f32, fade(UseAccent, 0.2'f32 + 0.3'f32 * pulse))
    drawInstallArrow(glyph, 1.0'f32, UseAccent)
    drawCaption(t(tkTouchUse), c, c.y + r * 0.40'f32, fade(Ink, 0.9'f32))
    return
  let armed = wallCharges > 0
  drawButtonBody(c, r, WallAccent, wallIsHeld, armed)
  if wallIsHeld and wallDragDir.length() > 0.0'f32:
    # Where the drag is steering the wall.
    let a = dirAngle(wallDragDir)
    drawRim(c, r + 6.0'f32, 5.0'f32, fade(WallAccent, 0.95'f32), a - 22.0'f32, a + 22.0'f32)
  drawBricks(glyph, 1.0'f32, if armed: WallAccent else: Color(r: 120, g: 110, b: 100, a: 190))
  drawBadge(c, r, $wallCharges, if armed: WallAccent else: SkipAccent)
  drawCaption(t(tkHUDKeyWall), c, c.y + r * 0.40'f32, fade(Ink, if armed: 0.85'f32 else: 0.45'f32))

proc drawPauseButton() =
  let c = pauseCenter()
  let held = pauseHeldSince >= 0.0'f32
  let pressed = held or pauseFlash > 0.0'f32
  let r = PauseBtnD * 0.5'f32 * (if pressed: 0.93'f32 else: 1.0'f32)
  drawButtonBody(c, r, PauseAccent, pressed, true)
  if skipProgress > 0.0'f32:
    # Hold-to-skip filling around the button (tutorial).
    drawRim(c, r + 5.0'f32, 4.0'f32, fade(SkipAccent, 0.95'f32), -90.0'f32,
            -90.0'f32 + 360.0'f32 * skipProgress)
  let barW = r * 0.22'f32
  let barH = r * 0.80'f32
  for k in [-1.0'f32, 1.0'f32]:
    drawRectangle(Rectangle(x: c.x + k * r * 0.22'f32 - barW * 0.5'f32, y: c.y - barH * 0.5'f32,
                            width: barW, height: barH), fade(Ink, 0.9'f32))

proc drawStick(j: VJoystick, accent: Color, firingAccent: Color) =
  if not j.active: return
  let r = toVirtualLen(joyRadius())
  let base = screenToVirtual(j.baseScreen)
  var off = Vector2(x: j.curScreen.x - j.baseScreen.x, y: j.curScreen.y - j.baseScreen.y)
  let mag = sqrt(off.x * off.x + off.y * off.y)
  if mag > joyRadius() and mag > 0.0'f32:
    off.x = off.x / mag * joyRadius()
    off.y = off.y / mag * joyRadius()
  let knob = screenToVirtual(Vector2(x: j.baseScreen.x + off.x, y: j.baseScreen.y + off.y))
  let v = stickVector(j)
  let deflected = v.length() > 0.0'f32
  drawCircle(base, r, Color(r: 6, g: 12, b: 20, a: 70))
  drawRim(base, r, 2.0'f32, fade(accent, 0.45'f32))
  drawRim(base, r * Deadzone, 1.5'f32, fade(accent, 0.30'f32))
  let knobColor = if deflected: firingAccent else: accent
  if deflected:
    # Direction wedge on the rim + a leash to the knob: the heading reads at a
    # glance even with the thumb covering the knob itself.
    let a = dirAngle(v)
    drawRim(base, r + 1.0'f32, 7.0'f32, fade(knobColor, 0.9'f32), a - 24.0'f32, a + 24.0'f32)
    drawLine(base, knob, 3.0'f32, fade(knobColor, 0.35'f32))
  drawCircle(knob, 28.0'f32, fade(knobColor, 0.75'f32))
  drawRim(knob, 28.0'f32, 2.0'f32, Color(r: 255, g: 255, b: 255, a: 140))

proc drawStickHint(center: Vector2, accent: Color, caption: string) =
  ## Idle hint for a stick the player hasn't used yet this session: a dashed
  ## ring where a thumb naturally rests. Retires once that stick is learned.
  let r = toVirtualLen(joyRadius())
  let pulse = 0.5'f32 + 0.5'f32 * sin(clock * 2.4'f32)
  for k in 0 ..< 12:
    let a0 = k.float32 * 30.0'f32
    drawRim(center, r, 2.0'f32, fade(accent, 0.30'f32), a0, a0 + 18.0'f32)
  drawCircle(center, 20.0'f32 + 5.0'f32 * pulse, fade(accent, 0.16'f32))
  const size = 14'i32
  let w = measureText(caption, size)
  drawText(caption, int32(center.x) - w div 2, int32(center.y + r + 8.0'f32), size,
           fade(Ink, 0.55'f32))

proc drawMobileControls*() =
  ## Draw sticks + buttons. Call in the virtual-canvas pass of the gameplay
  ## states, after the HUD, and OUTSIDE any UI-scale layer (see the module doc).
  let canvas = getCanvasSize()
  if not moveStick.active and moveUseTime < LearnTime:
    drawStickHint(Vector2(x: canvas.x * 0.17'f32, y: canvas.y * 0.70'f32), MoveAccent,
                  t(tkTouchMove))
  if not aimStick.active and aimUseTime < LearnTime:
    # Mirrors the move hint across the screen, lifted clear of the button row.
    drawStickHint(Vector2(x: canvas.x * 0.83'f32, y: canvas.y * 0.45'f32), AimAccent,
                  t(tkTouchAim))
  drawStick(moveStick, MoveAccent, MoveAccent)
  drawStick(aimStick, AimAccent, FireAccent)

  drawWallButton()
  drawAbilityButton()
  drawDashButton()
  drawPauseButton()
