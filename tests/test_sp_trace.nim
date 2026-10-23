# Single-player regression trace: a scripted bot plays wave and survival runs
# headless, and a digest of the gameplay state every 60 frames must match the
# recorded one (tests/sp_trace_expected.txt). It guards refactors of the
# simulation (co-op's multi-player context, input intent, modal flows) that
# must leave a one-player run exactly as it was.
#   nim r --mm:orc tests/test_sp_trace.nim                  compare
#   nim r --mm:orc -d:recordTrace tests/test_sp_trace.nim   re-record (after a
#                                                           change MEANT to
#                                                           alter gameplay)
# The digest hashes float bits, so any change in the order of float operations
# shows. Cosmetics (particles, shake, sound) are not in it, and draw from their
# own generator (fx_rand.nim), so they can't shift the gameplay rolls.
#
# The bot drives the run through PlayerIntent exactly as the keyboard does, and
# this file stands in for main.nim's state machine (wave cleared, drafts, shop,
# countdown) the way main.nim runs it for a single player.

import std/[os, random, strutils, math]
import raylib
import ../src/[game, types, settings, run_statistics, input_intent, player, powerup, coin, gamemode_definitions]
import ../src/game/[death, abilities]
import ../src/modding/mod_hooks
from ../src/fx_rand import seedFxRand

# Never touch the real profile: every save the run writes lands here.
let sandboxDir = getTempDir() / ("tophat_trace_" & $getCurrentProcessId())
putEnv("APPDATA", sandboxDir)
putEnv("HOME", sandboxDir)

const ExpectedFile = currentSourcePath().parentDir / "sp_trace_expected.txt"
const Dt = 1.0'f32 / 60.0'f32

type Fnv = uint64

proc mixBytes(h: var Fnv, p: pointer, n: int) =
  let b = cast[ptr UncheckedArray[uint8]](p)
  for i in 0 ..< n:
    h = (h xor Fnv(b[i])) * 1099511628211'u64

proc mix(h: var Fnv, x: float32) = (var v = x; mixBytes(h, addr v, 4))
proc mix(h: var Fnv, x: int) = (var v = int64(x); mixBytes(h, addr v, 8))
proc mix(h: var Fnv, x: bool) = mix(h, ord(x))
proc mix(h: var Fnv, v: Vector2) = (mix(h, v.x); mix(h, v.y))

proc digest(g: Game): Fnv =
  ## The gameplay state a refactor must not move: the player, every enemy,
  ## the projectiles and pickups, the run's clocks and progress.
  result = 14695981039346656037'u64
  mix(result, ord(g.state)); mix(result, g.currentWave); mix(result, g.time)
  mix(result, g.survivalTime); mix(result, g.difficulty); mix(result, g.waveInProgress)
  mix(result, g.waveEnemiesRemaining); mix(result, g.pendingLevelDrafts)
  let p = g.player
  mix(result, p.pos); mix(result, p.vel); mix(result, p.hp); mix(result, p.maxHp)
  mix(result, p.damage); mix(result, p.speed); mix(result, p.fireRate)
  mix(result, p.coins); mix(result, p.xp); mix(result, p.rogueliteLevel)
  mix(result, p.kills); mix(result, p.walls); mix(result, p.dashCooldown)
  for pu in p.powerUps:
    mix(result, ord(pu.powerType)); mix(result, pu.level)
  mix(result, g.enemies.len)
  for e in g.enemies:
    mix(result, e.id); mix(result, ord(e.enemyType)); mix(result, e.pos)
    mix(result, e.hp); mix(result, e.isBoss)
  mix(result, g.bullets.len)
  for b in g.bullets:
    mix(result, b.pos); mix(result, b.damage); mix(result, b.fromPlayer)
  mix(result, g.coins.len); mix(result, g.xpOrbs.len); mix(result, g.walls.len)
  mix(result, g.attackWarnings.len); mix(result, g.lasers.len)
  mix(result, g.consumables.len)

proc botIntent(g: Game, frame: int, rng: var Rand) =
  ## Keep away from the nearest enemy, aim at it, hold fire; dash, [Q] and
  ## walls on a fixed beat. Deterministic from the game state and `rng`.
  let p = g.player
  var it = p.intent
  beginIntentFrame(it)
  var nearest: Enemy = nil
  var best = float32.high
  for e in g.enemies:
    let d = (e.pos.x - p.pos.x) * (e.pos.x - p.pos.x) + (e.pos.y - p.pos.y) * (e.pos.y - p.pos.y)
    if d < best:
      best = d
      nearest = e
  var move = Vector2(x: 0, y: 0)
  if not nearest.isNil and best < 220.0'f32 * 220.0'f32:
    move = Vector2(x: p.pos.x - nearest.pos.x, y: p.pos.y - nearest.pos.y)
  else:
    let a = float32(frame div 45) * 1.7'f32 + rng.rand(0.6).float32
    move = Vector2(x: cos(a), y: sin(a))
  # Drift back toward the centre near the edges.
  move.x += (512.0'f32 - p.pos.x) / 400.0'f32
  move.y += (384.0'f32 - p.pos.y) / 300.0'f32
  let len = sqrt(move.x * move.x + move.y * move.y)
  it.move = if len > 0.001'f32: Vector2(x: move.x / len, y: move.y / len) else: move
  it.aim = if nearest.isNil: Vector2(x: 512, y: 300) else: nearest.pos
  it.aimByDir = false
  it.fireHeld = true
  it.fireKey = false
  it.wallHeld = frame mod 400 >= 385
  if frame mod 400 == 0 and frame > 0: pressEdge(it, ieWallRelease)
  if frame mod 97 == 0: pressEdge(it, ieDash)
  if frame mod 300 == 150: pressEdge(it, ieAbility)
  p.intent = it

proc pickDraft(g: var Game, frame: int) =
  ## A pick, then main.nim's continueAfterDraft for wave and survival.
  if not isPowerUpPoolExhausted(g.player, g.powerUpChoices[0].rarity == prLegendary,
                                AllPowerFamilies, g.mode):
    installPowerUp(g, g.powerUpChoices[frame mod 3])
  g.cameFromPowerUpSelect = true
  if g.levelDraftActive or isTimeSurvivalMode(g.mode):
    g.levelDraftActive = false
    g.state = gsPlaying
    beginDraftResume(g)
  else:
    g.state = gsShop

proc frameStep(g: var Game, frame: int, rng: var Rand) =
  ## One frame of main.nim's run states, as it runs them for one player.
  case g.state
  of gsPlaying:
    botIntent(g, frame, rng)
    let revealOpen = g.survival.reveal.active
    if not revealOpen:
      updateWallPlacement(g)
    if consumeEdge(g.player, ieAbility) and not revealOpen and not modAbility(g):
      activateLegendaries(g)
    updateGame(g, Dt)
  of gsDeathSequence:
    updateGame(g, Dt)
  of gsWaveCleared:
    g.waveClearedTimer -= Dt
    botIntent(g, frame, rng)
    updatePlayer(g.player, Dt, g.screenWidth, g.screenHeight, g.walls)
    discard updateGameCoins(g, Dt)
    if g.waveClearedTimer <= 0:
      if g.cameFromPowerUpSelect and not g.bossWaveManager.isBossCoinActive():
        if g.wavesUntilBoss <= 0:
          g.bossSpawnTimer = 2.0
        g.powerUpChoices = generatePowerUpChoices(g.player, false, mode = g.mode)
        g.selectedPowerUp = 0
        initPowerUpRollAnimation(g)
        initializeRerollCost(g)
        g.state = gsPowerUpSelect
      else:
        g.state = gsPlaying
        startWave(g)
  of gsPowerUpSelect:
    pickDraft(g, frame)
  of gsShop:
    g.state = gsCountdown
    g.countdownTimer = 0.5
  of gsCountdown:
    g.countdownTimer -= Dt
    if g.countdownTimer <= 0:
      g.state = gsPlaying
  else:
    discard

proc runScenario(name: string, mode: GameMode, frames: int, lines: var seq[string]) =
  randomize(1234)
  seedFxRand(99)
  var rng = initRand(777)
  var g = newGame(1024, 768)
  setGameMode(g, mode)
  initializeRunTracking(g)
  g.state = gsPlaying
  g.player.maxHp = 400
  g.player.hp = 400
  for f in 0 ..< frames:
    if g.state in {gsGameOver, gsVictory, gsSurvivalEndCinematic, gsRunStats}:
      lines.add name & " end " & $f & " " & $g.state & " " & toHex(digest(g))
      return
    frameStep(g, f, rng)
    if f mod 60 == 59:
      lines.add name & " " & $f & " " & toHex(digest(g))
  lines.add name & " done wave=" & $g.currentWave & " kills=" & $g.player.kills &
            " powerups=" & $g.player.powerUps.len & " " & toHex(digest(g))

globalSettings = newDefaultSettings()
var lines: seq[string]
runScenario("wave", gmWaveBased, 7200, lines)
runScenario("survival", gmTimeSurvival, 7200, lines)
removeDir(sandboxDir)

when defined(recordTrace):
  writeFile(ExpectedFile, lines.join("\n") & "\n")
  echo "recorded ", lines.len, " digests to ", ExpectedFile
  for l in lines:
    if " done " in l or " end " in l: echo l
else:
  if not fileExists(ExpectedFile):
    echo "no recorded trace: run with -d:recordTrace first"
    quit 1
  let expected = readFile(ExpectedFile).strip.splitLines
  var mismatches = 0
  for i in 0 ..< max(expected.len, lines.len):
    let want = if i < expected.len: expected[i] else: "<none>"
    let got = if i < lines.len: lines[i] else: "<none>"
    if want != got:
      if mismatches < 5: echo "MISMATCH want: ", want, "\n         got:  ", got
      inc mismatches
  if mismatches > 0:
    echo mismatches, " of ", max(expected.len, lines.len), " digests differ"
    quit 1
  echo lines.len, " digests match"
