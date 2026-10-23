# Co-op snapshot size, measured on a long, crowded run: three bot players
# (coop/coop_bot.nim) play survival headless, and every second frame the host
# captures the run and encodes it as a client would get it -- the change since
# the snapshot two before (a 30 Hz client, one snapshot behind on its acks).
# Prints the percentiles per phase of the run and overall, with what was on
# the arena. Not a pass/fail test: a measurement (the plan's gate was a p95
# under 16 KB per snapshot).
#   nim r --mm:orc -d:release tests/bench_coop_snapshot.nim [minutes]

import std/[os, random, algorithm, strutils, math]
import ../src/[game, types, settings, run_statistics, input_intent, player]
import ../src/game/abilities
import ../src/modding/mod_hooks
import ../src/coop/[coop_context, coop_bot, coop_codec, coop_wire]
import std/tables
from ../src/fx_rand import seedFxRand

let sandboxDir = getTempDir() / ("tophat_coopbench_" & $getCurrentProcessId())
putEnv("APPDATA", sandboxDir)
putEnv("HOME", sandboxDir)

const Dt = 1.0'f32 / 60.0'f32
let minutes = if paramCount() >= 1: parseFloat(paramStr(1)) else: 12.0

proc pct(xs: seq[int], p: float): int =
  if xs.len == 0: return 0
  var s = xs
  s.sort()
  s[min(s.high, int(float(s.len) * p))]

globalSettings = newDefaultSettings()
randomize(2024)
seedFxRand(9)

var g = newGame(1024, 768)
setGameMode(g, gmTimeSurvival)
initializeRunTracking(g)
g.state = gsPlaying
coopRole = crHost
localSlot = 0
for k in 1 ..< 3: discard addCoopPlayer(g, "bot" & $k)
beginCoopRun(g)
for p in g.players:
  p.maxHp = 5000   # (a long run: the bots must last)
  p.hp = 5000

var sizes, raws: seq[int]
var phaseSizes: seq[seq[int]]
var maxEnemies, maxBullets, maxOrbs = 0
var ring: FrameRing
var breakdown: array[6, int]   # core, players, enemies, bullets, coins, orbs
var breakdownN = 0
var fieldBytes = initTable[string, int]()
var prevWire = initTable[string, string]()
var seq = 0'i32
let frames = int(minutes * 60.0 * 60.0)
var lastReport = 0
for f in 0 ..< frames:
  if g.state in {gsGameOver, gsVictory, gsSurvivalEndCinematic}: break
  queueBotModalActions(g, f, includeLocal = true)
  updateCoopModal(g, Dt)
  if g.state == gsPlaying:
    for p in g.players: botIntent(g, p, f)
    for p in g.livingPlayers:
      withPlayer(g, p):
        if consumeEdge(g.player, ieAbility) and not modAbility(g): activateLegendaries(g)
    updateGame(g, Dt)
  elif g.state == gsDeathSequence:
    updateGame(g, Dt)
  coopFxLog.setLen(0)
  if f mod 2 == 0:
    inc seq
    let frame = captureFrame(g, seq)
    ring.put(frame)
    let base = ring.find(seq - 2)
    let packed = encodeSnapshot(frame, base, SnapExtras())
    sizes.add packed.len
    raws.add lastSnapStats.rawBytes
    if not base.isNil and g.time > minutes * 60.0 * 0.75:
      # Where the bytes go, late in the run: each section's change, uncompressed.
      proc delta(cur, old: string): int =
        if cur == old: 1 elif cur.len == old.len: xorRle(cur, old).len else: cur.len
      for j in 0 ..< min(frame.core.len, base.core.len):
        breakdown[0] += delta(frame.core[j], base.core[j])
      for k in 0 ..< min(frame.players.len, base.players.len):
        for j in 0 ..< min(frame.players[k].len, base.players[k].len):
          breakdown[1] += delta(frame.players[k][j], base.players[k][j])
      for kind in EntityList:
        for e in frame.ents[kind]:
          var old = ""
          for b in base.ents[kind]:
            if b.id == e.id: old = b.bytes
          breakdown[2 + ord(kind)] += (if old.len == 0: e.bytes.len else: delta(e.bytes, old))
      inc breakdownN
      # ...and by field: the first player's and the Game's (as the core sends it),
      # against the snapshot before.
      var cur = initTable[string, string]()
      for name, a in g.players[0][].fieldPairs:
        when not coopSkipsField("Player", name):
          cur["Player." & name] = toWire(a)
      for name, a in g[].fieldPairs:
        when not coopSkipsField("Game", name) and
             name notin ["player", "players", "enemies", "bullets", "coins", "xpOrbs"]:
          cur["Game." & name] = toWire(a)
      if prevWire.len > 0:
        for k, x in cur:
          let y = prevWire.getOrDefault(k)
          if x != y:
            fieldBytes.mgetOrPut(k, 0) += (if x.len == y.len: xorRle(x, y).len else: x.len)
      prevWire = cur
    let phase = int(g.time / 180.0)   # three-minute slices
    while phaseSizes.len <= phase: phaseSizes.add @[]
    phaseSizes[phase].add packed.len
    maxEnemies = max(maxEnemies, g.enemies.len)
    maxBullets = max(maxBullets, g.bullets.len)
    maxOrbs = max(maxOrbs, g.xpOrbs.len + g.coins.len)
  if f - lastReport >= 60 * 60:
    lastReport = f
    stderr.writeLine "  t=", formatFloat(g.time, ffDecimal, 0), "s enemies=", g.enemies.len,
                     " bullets=", g.bullets.len

echo "survival, 3 players, ", formatFloat(g.time / 60, ffDecimal, 1), " min simulated (state ", g.state, ")"
echo "on the arena at most: enemies ", maxEnemies, ", bullets ", maxBullets, ", coins+orbs ", maxOrbs
for k, ps in phaseSizes:
  echo "  ", k * 3, "-", k * 3 + 3, " min: p50 ", pct(ps, 0.5), " B, p95 ", pct(ps, 0.95),
       " B, max ", pct(ps, 1.0), " B"
echo "overall: p50 ", pct(sizes, 0.5), " B, p95 ", pct(sizes, 0.95), " B, max ", pct(sizes, 1.0),
     " B per snapshot; at 30 Hz the p95 is ", pct(sizes, 0.95) * 30 div 1024, " KB/s per client"
echo "before compression: p95 ", pct(raws, 0.95), " B"
if breakdownN > 0:
  echo "late in the run, per snapshot before compression: core ", breakdown[0] div breakdownN,
       " B, players ", breakdown[1] div breakdownN, " B, enemies ", breakdown[2] div breakdownN,
       " B, bullets ", breakdown[3] div breakdownN, " B, coins ", breakdown[4] div breakdownN,
       " B, orbs ", breakdown[5] div breakdownN, " B"
if breakdownN > 0:
  var top: seq[(int, string)]
  for k, v in fieldBytes: top.add (v div breakdownN, k)
  top.sort(Descending)
  echo "the fields that change most (bytes per snapshot, before compression):"
  for (v, k) in top[0 ..< min(14, top.len)]: echo "  ", k, ": ", v
removeDir(sandboxDir)
