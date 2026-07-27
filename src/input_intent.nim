## Input intent layer: the single seam between physical input devices and
## gameplay. Gameplay code asks for *intents* ("what's the move vector?",
## "is the player firing?") instead of reading mouse/keyboard/touch directly.
##
## Why this exists: it is what makes the desktop and mobile builds share one
## codebase. On desktop every proc returns EXACTLY the behavior the call-sites
## had inline before (same keybinds, same virtual-mouse), so routing through it
## is a no-op refactor. On `-d:mobile` the same procs read the touch controls
## instead — so a new power-up / enemy / boss needs zero mobile-specific work.
##
## Only three gameplay call-sites consume this today (player movement, game
## aim/fire, main.nim ability/wall/pause); keep that surface small.

import raylib
import particle_types      # Vector2f + ops
import types               # KeyAction (kaMoveUp .. kaLegendary)
import settings            # globalSettings
import render_context      # getWorldMousePosition + re-exported gamepad_input

when defined(mobile):
  import mobile_controls

proc keyMoveVector(): Vector2f =
  ## Raw keyboard + gamepad movement sum (un-normalized; callers clamp). The
  ## analog stick is added rather than snapped so partial deflection keeps its
  ## magnitude and the player can walk slowly.
  let kb = globalSettings.keybinds
  var d = newVector2f(0, 0)
  if isKeyDown(kb[kaMoveUp]): d.y -= 1
  if isKeyDown(kb[kaMoveDown]): d.y += 1
  if isKeyDown(kb[kaMoveLeft]): d.x -= 1
  if isKeyDown(kb[kaMoveRight]): d.x += 1
  if isGamepadActive():
    let ls = leftStick()
    d.x += ls.x
    d.y += ls.y
    let gb = globalSettings.gamepadBinds
    if isGamepadBindDown(gb, kaMoveUp): d.y -= 1
    if isGamepadBindDown(gb, kaMoveDown): d.y += 1
    if isGamepadBindDown(gb, kaMoveLeft): d.x -= 1
    if isGamepadBindDown(gb, kaMoveRight): d.x += 1
  d

proc getMoveVector*(): Vector2f =
  ## Desired movement direction (magnitude 0..~1). player.nim normalizes it.
  when defined(mobile):
    mobileMoveVector()
  else:
    keyMoveVector()

proc abilityDirection*(): Vector2f =
  ## Direction for directional abilities (Phase Shift dash). Mirrors movement
  ## input on both platforms.
  when defined(mobile):
    mobileMoveVector()
  else:
    keyMoveVector()

proc getAimTarget*(playerPos: Vector2f): Vector2f =
  ## WORLD-space point the player is aiming at; shootDir = target - playerPos.
  ## World, not virtual: in the widescreen HUD layout the gameplay world is
  ## offset inside the wider virtual canvas, so a virtual point would be skewed
  ## by the gutter width.
  ##
  ## Desktop: the mouse cursor (getWorldMousePosition already resolves to the
  ## gamepad aim point when a pad is the active device). Mobile: a point
  ## MobileAimReach ahead of the player along the aim stick (playerPos itself
  ## when not aiming, i.e. zero direction -> no shot). Note game.nim owns the
  ## assisted firing aim point (see stickAimPoint); this is the plain
  ## projection used for wall placement and other non-firing targeting.
  when defined(mobile):
    let dir = mobileAimVector()
    if dir.length() > 0:
      playerPos + dir.normalize() * MobileAimReach
    else:
      playerPos
  else:
    let m = getWorldMousePosition()
    newVector2f(m.x, m.y)

proc isFiring*(wallPlacementMode: bool): bool =
  ## Whether the player is shooting this frame. Desktop: left-mouse or the shoot
  ## key or the gamepad fire bind (all suppressed while placing a wall). Mobile
  ## auto-fires while the aim stick is held -- but not while the wall button is
  ## held, otherwise the player keeps firing through their own wall preview and
  ## can never line a wall up in peace.
  when defined(mobile):
    mobileIsAiming() and not wallPlacementMode
  else:
    (isMouseButtonDown(Left) and not wallPlacementMode) or
      isKeyDown(globalSettings.keybinds[kaShoot]) or
      (not wallPlacementMode and gamepadFireDown(globalSettings.gamepadBinds))

proc abilityPressed*(): bool =
  ## Legendary/ability activation edge.
  when defined(mobile):
    mobileAbilityPressed()
  else:
    isKeyPressed(globalSettings.keybinds[kaLegendary]) or
      isGamepadBindPressed(globalSettings.gamepadBinds, kaLegendary)

proc placeWallPressed*(): bool =
  ## Wall-key press EDGE. Single-player wants hold/release (preview then place);
  ## PvP's desktop control is a mode toggle, which needs the edge instead.
  ## Mobile has no toggle path -- it uses hold/release there too -- so this is
  ## desktop-only and deliberately has no touch branch.
  isKeyPressed(globalSettings.keybinds[kaPlaceWall]) or
    isGamepadBindPressed(globalSettings.gamepadBinds, kaPlaceWall)

proc placeWallHeld*(): bool =
  ## Wall preview is shown while held.
  when defined(mobile):
    mobileWallHeld()
  else:
    isKeyDown(globalSettings.keybinds[kaPlaceWall]) or
      isGamepadBindDown(globalSettings.gamepadBinds, kaPlaceWall)

proc placeWallReleased*(): bool =
  ## Wall is placed on release.
  when defined(mobile):
    mobileWallReleased()
  else:
    isKeyReleased(globalSettings.keybinds[kaPlaceWall]) or
      isGamepadBindReleased(globalSettings.gamepadBinds, kaPlaceWall)

proc interactPressed*(): bool =
  ## "Use the thing I'm standing on" -- the dungeon's paid pedestals and shop
  ## terminal. A distinct action from wall placement even though it shares the
  ## key on desktop, which is why it belongs here rather than being spelled out
  ## at each call site: on mobile there is no Enter key, so it maps to a tap of
  ## the wall button (its release edge), and without that mapping a mobile
  ## player cannot buy a pedestal or open a dungeon shop at all.
  when defined(mobile):
    mobileWallReleased()
  else:
    isKeyPressed(globalSettings.keybinds[kaPlaceWall]) or
      isKeyPressed(Enter) or
      isGamepadBindPressed(globalSettings.gamepadBinds, kaPlaceWall)

proc pausePressed*(): bool =
  ## Pause edge. Desktop: Escape (via isBackPressed) or the pad's Start button.
  when defined(mobile):
    mobilePausePressed()
  else:
    isBackPressed() or isGamepadStartPressed()
