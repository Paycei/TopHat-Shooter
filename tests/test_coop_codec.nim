# Co-op snapshot codec (src/coop/coop_codec.nim): a host plays a two-bot run
# headless while a client mirror receives its snapshots -- deltas against the
# last one it confirmed, with some lost on the way -- and after every one the
# mirror must re-capture to exactly the host's frame. Malformed snapshots must
# be refused, never crash. Prints what the snapshots cost.
#   nim r --mm:orc tests/test_coop_codec.nim
#   nim r --mm:orc -d:danger tests/test_coop_codec.nim

import std/[os, random, algorithm, strutils]
import raylib
import ../src/[game, types, settings, run_statistics, input_intent, player, coin]
import ../src/game/abilities
import ../src/modding/mod_hooks
import ../src/coop/[coop_context, coop_bot, coop_codec, coop_wire]
from ../src/fx_rand import seedFxRand

let sandboxDir = getTempDir() / ("tophat_codec_" & $getCurrentProcessId())
putEnv("APPDATA", sandboxDir)
putEnv("HOME", sandboxDir)

const Dt = 1.0'f32 / 60.0'f32

var failures = 0
var passed = 0

proc check(cond: bool, name: string) =
  if cond: inc passed
  else:
    echo "FAIL ", name
    inc failures

proc sameFrame(a, b: WireFrame): bool =
  if a.core != b.core or a.players != b.players: return false
  for k in EntityList:
    if a.ents[k] != b.ents[k]: return false
  true

proc hostStep(g: var Game, frame: int) =
  queueBotModalActions(g, frame, includeLocal = true)
  updateCoopModal(g, Dt)
  case g.state
  of gsPlaying:
    for p in g.players: botIntent(g, p, frame)
    for p in g.livingPlayers:
      withPlayer(g, p):
        if consumeEdge(g.player, ieAbility) and not modAbility(g):
          activateLegendaries(g)
    updateGame(g, Dt)
  of gsDeathSequence:
    updateGame(g, Dt)
  of gsWaveCleared:
    g.waveClearedTimer -= Dt
    discard updateGameCoins(g, Dt)
    if g.waveClearedTimer <= 0:
      g.state = gsPlaying
      startWave(g)
  of gsCountdown:
    g.countdownTimer -= Dt
    if g.countdownTimer <= 0: g.state = gsPlaying
  else: discard

proc runMirror(name: string, mode: GameMode, frames: int, lossPct: int) =
  randomize(99)
  seedFxRand(5)
  var host = newGame(1024, 768)
  setGameMode(host, mode)
  initializeRunTracking(host)
  host.state = gsPlaying
  coopRole = crHost
  localSlot = 0
  discard addCoopPlayer(host, "bot")
  beginCoopRun(host)
  for p in host.players:
    p.maxHp = 300
    p.hp = 300

  # The client's mirror: a shell of the same run, seated as player 1.
  var mirror = newGame(1024, 768)
  setGameMode(mirror, mode)
  var hostRing, clientRing: FrameRing
  var acked = 0'i32
  var lossRng = initRand(3)
  var sizes: seq[int]
  var applied, refused, matched = 0
  var seq = 0'i32
  for f in 0 ..< frames:
    hostStep(host, f)
    if f mod 2 != 0: continue          # 30 snapshots a second
    inc seq
    let cur = captureFrame(host, seq)
    hostRing.put(cur)
    let base = hostRing.find(acked)
    let packed = encodeSnapshot(cur, base, SnapExtras(actionAck: 7))
    sizes.add packed.len
    if lossRng.rand(99) < lossPct: continue   # lost on the way
    # The client decodes it as player 1 would.
    let savedSlot = localSlot
    localSlot = 1
    try:
      var extras: SnapExtras
      let got = readSnapshot(packed, clientRing, extras)
      applySnapshot(got, mirror)
      clientRing.put(got)
      acked = got.seq
      inc applied
      if extras.actionAck != 7: refused += 1000
      # The mirror holds exactly the host's run.
      if sameFrame(captureFrame(mirror, got.seq), cur): inc matched
    except CoopWireError:
      inc refused
    localSlot = savedSlot
  sizes.sort()
  let p50 = sizes[sizes.len div 2]
  let p95 = sizes[min(sizes.high, sizes.len * 95 div 100)]
  echo name, ": ", applied, " applied, ", refused, " refused; enemies=", host.enemies.len,
       " bullets=", host.bullets.len, "; snapshot bytes p50=", p50, " p95=", p95,
       " max=", sizes[^1], "; last raw=", lastSnapStats.rawBytes
  check(refused == 0, name & ": every snapshot that arrived applied")
  check(matched == applied, name & ": the mirror re-captures to the host's frame every time (" &
        $matched & "/" & $applied & ")")
  check(mirror.player == mirror.players[1], name & ": the mirror's player is this machine's seat")
  resetCoopContext()

globalSettings = newDefaultSettings()
runMirror("wave", gmWaveBased, 3600, 20)
runMirror("survival", gmTimeSurvival, 4800, 10)

# Malformed snapshots are refused, not crashed on.
block:
  randomize(5)
  var g = newGame(1024, 768)
  setGameMode(g, gmWaveBased)
  initializeRunTracking(g)
  coopRole = crHost
  discard addCoopPlayer(g, "bot")
  beginCoopRun(g)
  for f in 0 ..< 300:
    for p in g.players: botIntent(g, p, f)
    updateGame(g, Dt)
  let good = encodeSnapshot(captureFrame(g, 1), nil, SnapExtras())
  var ring: FrameRing
  var survived = true
  var rng = initRand(11)
  for trial in 0 ..< 300:
    var bad = good
    for k in 0 ..< 4: bad[rng.rand(bad.high)] = char(rng.rand(255))
    if trial mod 3 == 0: bad.setLen(rng.rand(bad.len))
    try:
      var extras: SnapExtras
      let fr = readSnapshot(bad, ring, extras)
      var mirror = newGame(1024, 768)
      applySnapshot(fr, mirror)
    except CoopWireError:
      discard
    except CatchableError:
      survived = false
  check(survived, "malformed snapshots raise CoopWireError or decode, never crash")
  var ex: SnapExtras
  var refusedBase = false
  try:
    discard readSnapshot(encodeSnapshot(captureFrame(g, 5), captureFrame(g, 4), SnapExtras()), ring, ex)
  except CoopWireError:
    refusedBase = true
  check(refusedBase, "a delta against a frame the client no longer has is refused")
  resetCoopContext()

removeDir(sandboxDir)
echo passed, " passed, ", failures, " failed"
if failures > 0: quit 1
