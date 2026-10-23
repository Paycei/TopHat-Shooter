# Tests for the co-op wire codec (src/coop/coop_wire.nim): a live run's whole
# Game graph round-trips byte for byte, decoding into an existing object keeps
# it, and malformed input raises CoopWireError instead of crashing.
#   nim r --mm:orc tests/test_coop_wire.nim
#   nim r --mm:orc -d:danger tests/test_coop_wire.nim   (how releases decode)

import std/[os, random, deques, tables]
import raylib
import ../src/[game, types, settings, run_statistics]
from ../src/fx_rand import seedFxRand
import ../src/coop/coop_wire

var failures = 0
var passed = 0

proc check(cond: bool, name: string) =
  if cond: inc passed
  else:
    echo "FAIL ", name
    inc failures

# Never touch the real profile: anything the run saves lands here.
let sandboxDir = getTempDir() / ("tophat_wire_" & $getCurrentProcessId())
putEnv("APPDATA", sandboxDir)
putEnv("HOME", sandboxDir)

randomize(42)
seedFxRand(42)
globalSettings = newDefaultSettings()

# A run with something in it: enemies, bullets, warnings, effects.
var g = newGame(1024, 768)
setGameMode(g, gmWaveBased)
initializeRunTracking(g)
g.state = gsPlaying
for f in 0 ..< 420:
  updateGame(g, 1.0'f32 / 60.0'f32)

# The containers flatty can't do on its own, on the player.
g.player.aftershockPosHistory = initDeque[Vector2]()
for k in 0 ..< 5: g.player.aftershockPosHistory.addLast(Vector2(x: k.float32, y: 2))
g.player.patches = {low(RogueliteRelicType), high(RogueliteRelicType)}
g.player.auraPulsePrimed = {low(AuraSlot)}
g.player.rotatingOrbs.add RotatingOrb()
g.player.rotatingOrbs[^1].lastHitTime[7] = 1.5

check(g.enemies.len > 0, "the run has enemies to encode")

# ---------------------------------------------------------- round trips ----
let bytes = toWire(g)
check(bytes.len > 1000, "a live Game encodes")

var fresh: Game
fromWire(bytes, fresh)
check(not fresh.isNil and toWire(fresh) == bytes, "decode into nil, re-encode: byte-equal")
check(fresh.player.isNil, "the game.player alias is never written")
check(fresh.particlePool.isNil and fresh.discordClient.isNil, "process handles are skipped")
check(fresh.enemies.len == g.enemies.len, "every enemy arrives")

let shell = newGame(1024, 768)
var target = shell
let shellEnemy = Enemy(id: 999)
target.enemies = @[shellEnemy]
fromWire(bytes, target)
check(target == shell, "decoding into an existing Game keeps the object")
check(target.enemies.len > 0 and target.enemies[0] == shellEnemy,
      "an existing entity at the same index is reused, not replaced")
check(not target.particlePool.isNil, "skipped fields are left as they were")
check(toWire(target) == bytes, "decode into an existing object, re-encode: byte-equal")

var p: Player
fromWire(toWire(g.player), p)
check(p.aftershockPosHistory.len == 5 and p.aftershockPosHistory[4].x == 4.0,
      "a Deque round-trips")
check(p.patches == g.player.patches and p.auraPulsePrimed == g.player.auraPulsePrimed,
      "sets round-trip")
check(p.rotatingOrbs[^1].lastHitTime.getOrDefault(7) == 1.5, "a Table round-trips")

# ------------------------------------------------------- hostile input ----
var prefixRejected = true
let stride = max(1, bytes.len div 1500)
var cut = 0
while cut < bytes.len:
  try:
    var gx: Game
    fromWire(bytes[0 ..< cut], gx)
    prefixRejected = false
  except CoopWireError: discard
  cut += stride
check(prefixRejected, "every truncation is refused")

var trailing = bytes & "\0"
var trailingRejected = false
try:
  var gx: Game
  fromWire(trailing, gx)
except CoopWireError: trailingRejected = true
check(trailingRejected, "trailing bytes are refused")

var survived = true
for trial in 0 ..< 400:
  var b = bytes
  for k in 0 ..< 6: b[rand(b.high)] = char(rand(255))
  try:
    var gx: Game
    fromWire(b, gx)
  except CoopWireError: discard
  except CatchableError:
    survived = false
check(survived, "corrupted inputs raise CoopWireError or decode, never crash")

# A count far beyond what the input could hold.
var huge = ""
putW(huge, 0x7FFFFFFF'u32)
var hugeRejected = false
try:
  var xs: seq[Enemy]
  fromWire(huge, xs)
except CoopWireError: hugeRejected = true
check(hugeRejected, "a seq count larger than the input is refused before allocating")

var badEnum = ""
putW(badEnum, 0x7F'u8)
var enumRejected = false
try:
  var st: GameState
  fromWire(badEnum, st)
except CoopWireError: enumRejected = true
check(enumRejected or sizeof(GameState) != 1, "an out-of-range enum is refused")

removeDir(sandboxDir)
echo passed, " passed, ", failures, " failed"
if failures > 0: quit 1
