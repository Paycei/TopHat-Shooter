## Player intent: input, apart from where it came from.
##
## The simulation never reads the keyboard, mouse or pad. Each frame a player's
## `intent` (types.PlayerIntent) is filled -- from this machine's devices by
## captureLocalIntent, or from a co-op client's input packet -- and movement,
## aiming, firing, the dash, [Q], walls and the roguelite interact key read
## only that. So the host drives every player in a co-op run the same way,
## and a single-player run behaves exactly as when these read the devices.
##
## Presses are counters (`edges`), not flags: consumeEdge acts on one once.
## beginIntentFrame drops whatever the last frame left unconsumed, which is
## what isKeyPressed did -- a press not used on its frame is gone.

import raylib, math
import modding/mod_patch_core
import types, settings, render_context

proc beginIntentFrame*(it: var PlayerIntent) {.inline.} =
  ## Forget presses the last frame did not act on.
  it.seen = it.edges

proc pressEdge*(it: var PlayerIntent, e: IntentEdge) {.inline.} =
  inc it.edges[e]

proc consumeEdge*(p: Player, e: IntentEdge): bool =
  ## True once per press of `e` this frame; the press is then used up.
  if p.intent.edges[e] != p.intent.seen[e]:
    p.intent.seen[e] = p.intent.edges[e]
    true
  else:
    false

proc edgePending*(p: Player, e: IntentEdge): bool {.inline.} =
  ## A press of `e` this frame that nothing has used yet (does not use it).
  p.intent.edges[e] != p.intent.seen[e]

proc captureLocalIntent*(p: Player) {.moddable.} =
  ## Fill `p.intent` from this machine's keyboard, mouse and pad.
  if p.isNil or globalSettings.isNil: return
  var it = p.intent
  beginIntentFrame(it)
  let kb = globalSettings.keybinds
  let gb = globalSettings.gamepadBinds

  var move = Vector2(x: 0, y: 0)
  if isKeyDown(kb[kaMoveUp]): move.y -= 1
  if isKeyDown(kb[kaMoveDown]): move.y += 1
  if isKeyDown(kb[kaMoveLeft]): move.x -= 1
  if isKeyDown(kb[kaMoveRight]): move.x += 1
  if isGamepadActive():
    let ls = leftStick()
    move.x += ls.x
    move.y += ls.y
    if isGamepadBindDown(gb, kaMoveUp): move.y -= 1
    if isGamepadBindDown(gb, kaMoveDown): move.y += 1
    if isGamepadBindDown(gb, kaMoveLeft): move.x -= 1
    if isGamepadBindDown(gb, kaMoveRight): move.x += 1
  # Clamp instead of always normalizing: keyboard input still normalizes the
  # diagonal, while partial analog stick deflection keeps its magnitude so the
  # player can walk slowly.
  let moveLen = sqrt(move.x * move.x + move.y * move.y)
  if moveLen > 1:
    move = Vector2(x: move.x / moveLen, y: move.y / moveLen)
  it.move = move

  # The pointer in world coords. With a pad this is the aim point the firing
  # code last projected (setGamepadAimPointWorld), which is where walls go.
  let pointer = getWorldMousePosition()
  it.aim = Vector2(x: pointer.x, y: pointer.y)
  it.aimByDir = isGamepadActive()
  it.aimDir = if it.aimByDir: aimDir() else: Vector2(x: 0, y: 0)
  it.aimAssist = globalSettings.aimAssistEnabled

  it.fireHeld = isMouseButtonDown(Left) or gamepadFireDown(gb)
  it.fireKey = isKeyDown(kb[kaShoot])
  it.wallHeld = isKeyDown(kb[kaPlaceWall]) or isGamepadBindDown(gb, kaPlaceWall)

  if isKeyReleased(kb[kaPlaceWall]) or isGamepadBindReleased(gb, kaPlaceWall):
    pressEdge(it, ieWallRelease)
  if isKeyPressed(kb[kaDash]) or (isGamepadActive() and isGamepadBindPressed(gb, kaDash)):
    pressEdge(it, ieDash)
  if isKeyPressed(kb[kaLegendary]) or isGamepadBindPressed(gb, kaLegendary):
    pressEdge(it, ieAbility)
  if isKeyPressed(kb[kaPlaceWall]) or isKeyPressed(Enter) or isGamepadBindPressed(gb, kaPlaceWall):
    pressEdge(it, ieInteract)
  p.intent = it

proc idleIntent*(p: Player) {.moddable.} =
  ## No input this frame (a menu is up over a co-op run, which goes on): the
  ## player stands still and holds fire; presses not yet used are dropped.
  if p.isNil: return
  beginIntentFrame(p.intent)
  p.intent.move = Vector2(x: 0, y: 0)
  p.intent.fireHeld = false
  p.intent.fireKey = false
  p.intent.wallHeld = false
