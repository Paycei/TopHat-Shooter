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
import render_context      # getVirtualMousePosition

when defined(mobile):
  import mobile_controls

proc keyMoveVector(): Vector2f =
  ## Raw WASD/keybind sum (un-normalized; callers normalize). Matches the old
  ## inline block in player.nim:243-247 and the dash block in main.nim.
  let kb = globalSettings.keybinds
  var d = newVector2f(0, 0)
  if isKeyDown(kb[kaMoveUp]): d.y -= 1
  if isKeyDown(kb[kaMoveDown]): d.y += 1
  if isKeyDown(kb[kaMoveLeft]): d.x -= 1
  if isKeyDown(kb[kaMoveRight]): d.x += 1
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
  ## Virtual-canvas point the player is aiming at; shootDir = target - playerPos.
  ## Desktop: the mouse cursor (identical to game.nim:1634). Mobile: a point
  ## MobileAimReach ahead of the player along the aim stick (playerPos itself
  ## when not aiming, i.e. zero direction -> no shot).
  when defined(mobile):
    let dir = mobileAimVector()
    if dir.length() > 0:
      playerPos + dir.normalize() * MobileAimReach
    else:
      playerPos
  else:
    let m = getVirtualMousePosition()
    newVector2f(m.x, m.y)

proc isFiring*(wallPlacementMode: bool): bool =
  ## Whether the player is shooting this frame. Desktop mirrors game.nim:1648-1649
  ## (left-mouse unless placing a wall, or the shoot key). Mobile auto-fires while
  ## the aim stick is held.
  when defined(mobile):
    mobileIsAiming()
  else:
    (isMouseButtonDown(Left) and not wallPlacementMode) or
      isKeyDown(globalSettings.keybinds[kaShoot])

proc abilityPressed*(): bool =
  ## Legendary/ability activation edge (main.nim:1410).
  when defined(mobile):
    mobileAbilityPressed()
  else:
    isKeyPressed(globalSettings.keybinds[kaLegendary])

proc placeWallHeld*(): bool =
  ## Wall preview is shown while held (main.nim:1394).
  when defined(mobile):
    mobileWallHeld()
  else:
    isKeyDown(globalSettings.keybinds[kaPlaceWall])

proc placeWallReleased*(): bool =
  ## Wall is placed on release (main.nim:1398).
  when defined(mobile):
    mobileWallReleased()
  else:
    isKeyReleased(globalSettings.keybinds[kaPlaceWall])

proc pausePressed*(): bool =
  ## Pause edge (main.nim:1614). Desktop: Escape.
  when defined(mobile):
    mobilePausePressed()
  else:
    isKeyPressed(Escape)
