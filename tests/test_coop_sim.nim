# Co-op simulation smoke test: two or three bot players (coop/coop_bot.nim)
# share one headless wave, survival or roguelite run, driven the way main.nim
# drives a co-op host. Checks that every player fights (kills of their own),
# gets hurt, levels with the team and shops their own wallet, that a roguelite
# team votes its sector and moves on through its folders, and that nothing in
# the multi-player simulation crashes.
#   nim r --mm:orc tests/test_coop_sim.nim
#   nim r --mm:orc -d:danger tests/test_coop_sim.nim

import std/[os, random, strutils]
import raylib
import ../src/[game, types, settings, run_statistics, input_intent, player, powerup, coin, roguelite, dungeon,
               gamemode_definitions]
import ../src/game/[death, abilities]
import ../src/modding/mod_hooks
import ../src/coop/[coop_context, coop_bot]
from ../src/fx_rand import seedFxRand

# Never touch the real profile: every save the run writes lands here.
let sandboxDir = getTempDir() / ("tophat_coopsim_" & $getCurrentProcessId())
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

type Tally = object
  hurt: array[MaxCoopPlayers, bool]
  lastHp: array[MaxCoopPlayers, float32]

type Seen = object
  draftsDone, shopsDone, cachesDone, votesDone: int
  boughtSomething: bool
  roomsEntered: int

proc frameStep(g: var Game, frame: int, seen: var Seen) =
  # The host's team modals, as main.nim runs them every frame: every bot
  # (this machine's player included) picks, shops, dismisses and votes.
  let before = if g.coop.isNil: cmkNone else: g.coop.modal
  queueBotModalActions(g, frame, includeLocal = true)
  updateCoopModal(g, Dt)
  if before != cmkNone and g.coop.modal == cmkNone:
    case before
    of cmkDraft: inc seen.draftsDone
    of cmkShop: inc seen.shopsDone
    of cmkCache: inc seen.cachesDone
    of cmkFloorVote: inc seen.votesDone
    of cmkNone: discard
  case g.state
  of gsPlaying:
    for p in g.players:
      botIntent(g, p, frame)
    let revealOpen = g.survival.reveal.active
    for p in g.livingPlayers:
      withPlayer(g, p):
        if not revealOpen:
          updateWallPlacement(g)
        if consumeEdge(g.player, ieAbility) and not revealOpen and not modAbility(g):
          activateLegendaries(g)
    updateGame(g, Dt)
  of gsDeathSequence:
    updateGame(g, Dt)
  of gsWaveCleared:
    g.waveClearedTimer -= Dt
    for p in g.livingPlayers:
      botIntent(g, p, frame)
      updatePlayer(p, Dt, g.screenWidth, g.screenHeight, g.walls)
    discard updateGameCoins(g, Dt)
    if g.waveClearedTimer <= 0:
      if g.cameFromPowerUpSelect and not g.bossWaveManager.isBossCoinActive():
        if g.wavesUntilBoss <= 0:
          g.bossSpawnTimer = 2.0
        g.powerUpChoices = generatePowerUpChoices(g.player, false, mode = g.mode)
        initializeRerollCost(g)
        g.state = gsPowerUpSelect
      else:
        g.state = gsPlaying
        startWave(g)
  of gsShop:
    for p in g.players:
      if p.shopBought[0] > 0: seen.boughtSomething = true
  of gsCountdown:
    g.countdownTimer -= Dt
    if g.countdownTimer <= 0:
      g.state = gsPlaying
  else:
    discard   # gsPowerUpSelect / gsRogueliteFloorSelect: the team modal decides

proc runCoop(name: string, mode: GameMode, players, frames: int): Seen =
  randomize(4321)
  seedFxRand(7)
  var g = newGame(1024, 768)
  setGameMode(g, mode)
  initializeRunTracking(g)
  g.state = gsPlaying
  if mode == gmRoguelite:
    let profile = loadRogueliteProfile()
    g.rogueliteProfile = profile
    beginRogueliteRun(g, profile, rskOperator, 1)
    generateThemeChoices(g.rogueliteRun)
    g.state = gsRogueliteFloorSelect
  coopRole = crHost
  localSlot = 0
  for k in 1 ..< players:
    discard addCoopPlayer(g, "bot" & $k)
  beginCoopRun(g)
  for p in g.players:
    p.maxHp = 400
    p.hp = 400
  var t: Tally
  var seen: Seen
  for p in g.players: t.lastHp[p.slot] = p.hp
  var ended = ""
  for f in 0 ..< frames:
    if g.state in {gsGameOver, gsVictory, gsSurvivalEndCinematic, gsRunStats}:
      ended = $g.state
      break
    let roomsBefore = if g.rogueliteRun.isNil or g.rogueliteRun.floor.isNil: 0
                      else: g.rogueliteRun.floor.rooms.len
    frameStep(g, f, seen)
    if not g.rogueliteRun.isNil and not g.rogueliteRun.floor.isNil and
       g.rogueliteRun.floor.rooms.len > roomsBefore and roomsBefore > 0:
      inc seen.roomsEntered
    for p in g.players:
      if p.hp < t.lastHp[p.slot] - 0.001: t.hurt[p.slot] = true
      t.lastHp[p.slot] = p.hp
    check(g.player == g.players[localSlot], name & ": game.player is back on this machine's player")
  var line = name & ": wave=" & $g.currentWave & " state=" & $g.state & (if ended.len > 0: " ended" else: "") &
             " drafts=" & $seen.draftsDone & " shops=" & $seen.shopsDone &
             " caches=" & $seen.cachesDone & " votes=" & $seen.votesDone &
             " rooms=" & $seen.roomsEntered &
             " lives=" & $g.coop.teamLives
  for p in g.players:
    line.add " | p" & $p.slot & " kills=" & $p.kills & " lvl=" & $p.rogueliteLevel &
             " coins=" & $p.coins & " hp=" & formatFloat(p.hp, ffDecimal, 1) &
             " pu=" & $p.powerUps.len & " shop=" & $p.shopBought[0]
  echo line
  block:
    for p in g.players:
      check(p.kills > 0, name & ": player " & $p.slot & " scored kills of their own")
      check(p.rogueliteLevel == g.players[0].rogueliteLevel,
            name & ": player " & $p.slot & " levelled with the team")
      check(p.powerUps.len > 0, name & ": player " & $p.slot & " drafted power-ups")
    var teamHurt = false
    for p in g.players: teamHurt = teamHurt or t.hurt[p.slot]
    check(teamHurt, name & ": the enemies hurt the team")
    check(seen.draftsDone > 0, name & ": the team went through a draft together")
  result = seen
  block:
    check(coopProfileOutbox[1].len > 0, name & ": the second player's own progress went to their outbox")
    var discovered = false
    for ev in coopProfileOutbox[1]:
      if ev.kind == pekDiscovered: discovered = true
    check(discovered, name & ": the second player's power-up codex is theirs")
    check(not slotRunStats[1].isNil and slotRunStats[1].combat.totalDamageDealt > 0 and
          slotRunStats[1] != slotRunStats[0], name & ": the second player has run statistics of their own")
  resetCoopContext()

globalSettings = newDefaultSettings()
let wave = runCoop("wave x2", gmWaveBased, 2, 7200)
check(wave.shopsDone > 0, "wave: the team shopped between waves")
check(wave.boughtSomething, "wave: a player bought from their own wallet")
let surv = runCoop("survival x3", gmTimeSurvival, 3, 7200)
let rogue = runCoop("roguelite x2", gmRoguelite, 2, 5400)
check(rogue.votesDone > 0, "roguelite: the team voted for its first sector")
check(rogue.roomsEntered >= 2, "roguelite: the team went through its folders' doors (" &
      $rogue.roomsEntered & " rooms)")

# A co-op run never writes a save of any kind.
var saves: seq[string]
for f in walkDirRec(sandboxDir):
  let n = f.extractFilename
  if n.startsWith("run_save") or n.startsWith("run_checkpoint") or n.endsWith(".snap"):
    saves.add n
check(saves.len == 0, "no run save, checkpoint or snapshot was written (" & saves.join(", ") & ")")
removeDir(sandboxDir)

echo passed, " passed, ", failures, " failed"
if failures > 0: quit 1
