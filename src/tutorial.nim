## ORIENTATION.EXE -- the first-run tutorial.
##
## A short, interactive walkthrough (move, aim/fire, dash, a few practice
## targets, loot, the status panel, walls) that plays over the opening of the
## player's first fresh wave-mode run, then releases wave 1 so the run simply
## carries on. Settings > Gameplay replays it as a standalone *practice session*
## that returns to the desktop when it ends.
##
## State lives here rather than on `Game` on purpose: the tutorial is transient
## presentation that must never be resumed, and a new `Game` field would change
## the suspend snapshot's layout fingerprint (invalidating every saved
## snapshot) for no benefit. A run is matched to its tutorial by `Game` ref
## identity, so a stale session can never leak into the next run.
##
## Dependency-wise this is a leaf beside the game/ modules: game.nim reads
## `tutorialHoldsWaves`, and run_save/suspend read `tutorialSuppressesSaves` at
## their write choke points. Drawing lives in ui/tutorial_overlay.nim.

import raylib, math, random, sequtils
import types, particle_types, enemy, settings, gamepad_input, sound, run_statistics, d_systems, d_enhancements

type
  TutorialStep* = enum
    tsMove     ## walk a short distance
    tsFire     ## aim and hold fire
    tsDash     ## use the dash once
    tsTargets  ## destroy a few slow practice targets
    tsLoot     ## collect what they dropped
    tsStatus   ## read: the status panel
    tsWalls    ## place a wall with a lent charge
    tsSettings ## read: tune the game in Settings
    tsReady    ## read: waves, bosses, pause -- then hand over

  TutorialEvent* = enum
    teNone
    teFinished  ## the last card was dismissed
    teSkipped   ## the skip key was held

  TutorialState* = object
    game*: Game           ## the run this tutorial belongs to
    active*: bool
    practice*: bool       ## replayed from settings: a throwaway session
    step*: TutorialStep
    stepTime*: float32    ## seconds spent on the current step
    progress*: float32    ## 0..1 toward the current step's goal
    doneTimer*: float32   ## > 0 while an action step's "DONE" beat plays
    skipHold*: float32    ## seconds the skip key has been held
    targetIds*: seq[int]  ## enemy ids of the practice targets
    lastPlayerPos: Vector2f
    moved: float32
    fireTime: float32
    wasDashing: bool
    lootAtStart: int
    wallsBefore: int      ## game.walls.len when the walls step began
    freshPlayer: Player   ## the player as the run began, restored at the handoff

const
  MoveGoal* = 320.0'f32          ## px the player has to travel
  FireGoal* = 0.8'f32            ## seconds of holding fire
  TargetCount* = 3
  LootMinTime = 1.2'f32          ## the loot card never just flashes by...
  LootTimeout = 10.0'f32         ## ...and never waits on an orb forever
  ReadMinTime* = 0.6'f32         ## Enter can't dismiss a card the instant it appears
  DoneBeat* = 0.75'f32           ## "DONE" flash before the next action step
  SkipHoldTime* = 0.9'f32
  TargetDamageScale = 0.25'f32   ## practice targets chip, they don't threaten
  TargetSpeedScale = 0.65'f32    ## and approach slowly enough to read
  TargetSpawnDistance = 280.0'f32
  TargetEdgeMargin = 60.0'f32
  TargetBottomBand = 250.0'f32   ## keep spawns out from under the instruction card
  SafetyNetFraction = 0.5'f32    ## HP floor below which the tutorial refills

var state: TutorialState

proc tutorialState*(): TutorialState =
  ## Read-only copy for the overlay renderer.
  state

proc isTutorialActive*(game: Game): bool =
  state.active and not game.isNil and game == state.game

proc tutorialHoldsWaves*(game: Game): bool =
  ## True while the tutorial owns the arena: wave 1 must not start until the
  ## last card is dismissed (or the tutorial is skipped).
  isTutorialActive(game)

proc isTutorialPractice*(game: Game): bool =
  not game.isNil and game == state.game and state.practice

proc tutorialSuppressesSaves*(game: Game): bool =
  ## True when `game` must never be checkpointed. A practice session has to
  ## leave the player's real saved run untouched for its whole life, and a first
  ## run quit before wave 1 has nothing worth resuming (the next fresh run
  ## replays the tutorial instead). Checked by saveRunState and suspendGame.
  not game.isNil and game == state.game and (state.practice or state.active)

proc isRead*(step: TutorialStep): bool =
  ## Read-only cards wait for Enter / A instead of an action. They never time
  ## out: a slow reader must not lose the text mid-sentence.
  step in {tsStatus, tsSettings, tsReady}

# ---------------------------------------------------------------------------
# Input probes. These read the same bindings the gameplay code does, so a
# rebound control is taught (and detected) under its new key.

proc fireHeld(): bool =
  isMouseButtonDown(MouseButton.Left) or
    isKeyDown(globalSettings.keybinds[kaShoot]) or
    (isGamepadActive() and gamepadFireDown(globalSettings.gamepadBinds))

proc continuePressed(): bool =
  isKeyPressed(KeyboardKey.Enter) or isKeyPressed(KeyboardKey.KpEnter) or
    (isGamepadActive() and isGamepadConfirmPressed())

proc skipHeld(): bool =
  ## Tab / Select: neither is a gameplay binding by default, and a hold (not a
  ## tap) is required so a stray press can't throw the tutorial away.
  isKeyDown(KeyboardKey.Tab) or
    (isGamepadActive() and isGamepadButtonDown(activeGamepad(), GamepadButton.MiddleLeft))

# ---------------------------------------------------------------------------

proc aliveTargets(game: Game): int =
  for enemy in game.enemies:
    if enemy.id in state.targetIds:
      inc result

proc spawnPracticeTargets(game: Game) =
  ## A spread of slow, weak circles around the player -- the wave-1 enemy, so
  ## what the tutorial teaches is exactly what arrives next.
  state.targetIds.setLen(0)
  let p = game.player
  let baseAngle = rand(1.0).float32 * 2.0'f32 * PI.float32
  for i in 0..<TargetCount:
    let a = baseAngle + i.float32 * 2.0'f32 * PI.float32 / TargetCount.float32
    let x = clamp(p.pos.x + cos(a) * TargetSpawnDistance,
                  TargetEdgeMargin, game.screenWidth.float32 - TargetEdgeMargin)
    let y = clamp(p.pos.y + sin(a) * TargetSpawnDistance,
                  TargetEdgeMargin, game.screenHeight.float32 - TargetBottomBand)
    let target = newEnemy(x, y, 0.0'f32, etCircle, game)
    target.contactDamage *= TargetDamageScale
    target.speed *= TargetSpeedScale
    game.enemies.add(target)
    state.targetIds.add(target.id)

proc restoreFreshRun(game: Game) =
  ## Hand wave 1 exactly the run the player would have had without the
  ## tutorial: nothing earned, spent, placed or lost in it carries over.
  let p = game.player
  if not state.freshPlayer.isNil:
    # One value copy covers every player stat the tutorial could have moved:
    # HP, credits, XP and level, wall charges, kills, cooldowns, combo streaks.
    # Safe because a fresh player owns no refs (no orbs or power-ups yet), so
    # the snapshot shares nothing with the live player.
    let pos = p.pos
    let vel = p.vel
    p[] = state.freshPlayer[]
    p.pos = pos  # no teleport at the handoff
    p.vel = vel
  else:
    p.hp = p.maxHp
  game.enemies.keepItIf(it.id notin state.targetIds)
  game.bullets.setLen(0)
  game.walls.setLen(0)
  game.pendingWallRespawns.setLen(0)
  game.coins.setLen(0)
  game.xpOrbs.setLen(0)
  game.consumables.setLen(0)
  game.pendingLevelDrafts = 0
  game.levelDraftDelay = 0
  game.dopamine.comboSystem = newComboSystem()
  # Tracks player.kills for its milestones, so it restarts with the kill count.
  game.dopamine.microRewards = newMicroRewardTracker()
  game.dopamine.realTimeStats = newRealTimeStats()
  # The run's statistics (kills, credits, walls, damage) start at wave 1 too.
  initializeRunTracking(game)

proc enterStep(game: Game, step: TutorialStep) =
  state.step = step
  state.stepTime = 0
  state.progress = 0
  state.doneTimer = 0
  let p = game.player
  case step
  of tsMove:
    state.lastPlayerPos = p.pos
    state.moved = 0
  of tsFire:
    state.fireTime = 0
  of tsDash:
    state.wasDashing = p.dashTimer > 0
  of tsTargets:
    spawnPracticeTargets(game)
  of tsLoot:
    state.lootAtStart = game.xpOrbs.len + game.coins.len
  of tsWalls:
    state.wallsBefore = game.walls.len
    if p.walls <= 0:
      p.walls = 1  # lent: restoreFreshRun takes it back
  of tsStatus, tsSettings, tsReady:
    discard

proc startTutorial*(game: Game, practice: bool) =
  ## Call on a freshly started run, before anything has touched the player.
  var fresh = Player()
  fresh[] = game.player[]
  state = TutorialState(game: game, active: true, practice: practice,
                        freshPlayer: fresh)
  enterStep(game, tsMove)

proc finishTutorial(game: Game) =
  restoreFreshRun(game)
  state.freshPlayer = nil
  state.active = false

proc endTutorialSession*() =
  ## Forget the session once its run has been torn down (drops the Game ref).
  state = TutorialState()

proc updateTutorial*(game: Game, dt: float32): TutorialEvent =
  ## Advance the current step from what the player just did. Call once per
  ## gsPlaying frame, BEFORE updateGame, so the safety net below runs ahead of
  ## this frame's damage.
  if not isTutorialActive(game):
    return teNone
  let p = game.player

  # Safety net: nothing in the tutorial is allowed to end a run. The practice
  # targets' damage is scaled so one frame can never cover the gap from this
  # floor to zero.
  if p.hp < p.maxHp * SafetyNetFraction:
    p.hp = p.maxHp

  if skipHeld():
    state.skipHold += dt
    if state.skipHold >= SkipHoldTime:
      finishTutorial(game)
      playSound(stMenuSelect)
      return teSkipped
  else:
    state.skipHold = 0

  state.stepTime += dt

  # An action step that was just completed holds its DONE beat, then advances.
  if state.doneTimer > 0:
    state.doneTimer -= dt
    if state.doneTimer <= 0:
      enterStep(game, succ(state.step))
    return teNone

  var goalMet = false
  case state.step
  of tsMove:
    let step = distance(p.pos, state.lastPlayerPos)
    state.lastPlayerPos = p.pos
    if step < 60.0'f32:  # a teleport (or a respawn clamp) isn't walking
      state.moved += step
    state.progress = clamp(state.moved / MoveGoal, 0.0'f32, 1.0'f32)
    goalMet = state.moved >= MoveGoal
  of tsFire:
    if fireHeld():
      state.fireTime += dt
    state.progress = clamp(state.fireTime / FireGoal, 0.0'f32, 1.0'f32)
    goalMet = state.fireTime >= FireGoal
  of tsDash:
    let dashing = p.dashTimer > 0
    goalMet = dashing and not state.wasDashing
    state.wasDashing = dashing
  of tsTargets:
    let alive = aliveTargets(game)
    state.progress = (TargetCount - alive).float32 / TargetCount.float32
    goalMet = alive == 0
  of tsLoot:
    let remaining = game.xpOrbs.len + game.coins.len
    state.progress = if state.lootAtStart <= 0: 1.0'f32
                     else: clamp(1.0'f32 - remaining.float32 / state.lootAtStart.float32,
                                 0.0'f32, 1.0'f32)
    goalMet = (remaining == 0 and state.stepTime >= LootMinTime) or
              state.stepTime >= LootTimeout
  of tsWalls:
    # Should the lent charge vanish some other way, lend another: the step's
    # only way forward is placing a wall.
    if p.walls <= 0 and game.walls.len <= state.wallsBefore:
      p.walls = 1
    goalMet = game.walls.len > state.wallsBefore
  of tsStatus, tsSettings, tsReady:
    # The bar fills while the card arms, then sits full until it is dismissed.
    state.progress = clamp(state.stepTime / ReadMinTime, 0.0'f32, 1.0'f32)
    goalMet = state.stepTime >= ReadMinTime and continuePressed()

  if not goalMet:
    return teNone

  state.progress = 1.0'f32
  if state.step == TutorialStep.high:
    finishTutorial(game)
    playSound(stWaveComplete)
    return teFinished
  if state.step.isRead:
    playSound(stMenuNav)
    enterStep(game, succ(state.step))
  else:
    playSound(stMenuSelect)
    state.doneTimer = DoneBeat
  teNone
