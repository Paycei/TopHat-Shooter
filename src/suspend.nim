## VMware-style EXACT run snapshot.
##
## Where run_save.nim is a CHECKPOINT of durable progression (rebuilt to fresh
## defaults on resume), this module freezes the ENTIRE live simulation -- every
## bullet in flight, every enemy, every telegraph mid-countdown, the boss-wave
## manager, per-run statistics -- and restores it byte-for-byte on the next
## launch. It is the PRIMARY resume path; run_save's checkpoint JSON is the
## FALLBACK used when a snapshot is missing or its type-layout fingerprint no
## longer matches (e.g. a game update changed a struct or added an enum value).
##
## Covered modes: gmWaveBased, gmTimeSurvival, gmRoguelite (same scope as
## run_save). Never PvP / sandbox / 3D boss.
##
## Serialization: flatty (toFlatty/fromFlatty over the whole Game ref graph)
## wrapped in supersnappy compression, exactly like the PvP packet path in
## src/network. A small hand-written header (magic + format version + a
## compile-time type-layout fingerprint + mode) precedes the compressed payload.
##
## This module must NEVER import game.nim (that would form an import cycle).
##
## RUNTIME-ONLY FIELDS: several Game fields hold process-lifetime handles or
## pure render state that must not (and in some cases cannot) be serialized:
##   - game3D            : raw `pointer`             -> dropped (nil on restore)
##   - discordClient     : DiscordClient (ref)       -> carried from live game
##   - rogueliteProfile  : RogueliteProfile (ref)    -> carried from live game so
##                         cross-run meta-currency earned after the snapshot is
##                         NOT rolled back (run-scoped state comes from the snap,
##                         profile/meta state stays live).
##   - osBackground/osHUD/dopamine : animated render state -> reset to the live
##                         game's freshly-initialised copy (cosmetic only).
##   - particlePool      : cosmetic particle buffers -> reset (kept from live).
## Each of these has a no-op flatty overload below, so toFlatty simply SKIPS the
## field (leaving the passed game untouched) and restoreGame re-attaches the live
## value afterward. Unsupported containers get real converters: Deque[T] (the
## Aftershock position history) is (de)serialized as a length-prefixed run, and
## raw `pointer` reads back as nil. Nil refs (e.g. pendingBoss) round-trip
## natively in flatty.
##
## RNG: the std/random global generator state is intentionally NOT captured;
## games tolerate re-seeded randomness after a resume.

import os, deques, strutils, tables
import types, save_system, run_statistics, tutorial
import discord_presence  # DiscordClient (no-op flatty overload)
import particle_types    # ParticlePool  (no-op flatty overload)
import flatty, supersnappy

# ---------------------------------------------------------------------------
# Custom flatty overloads for runtime-only / unsupported field types.
#
# flatty resolves the `toFlatty`/`fromFlatty` calls inside its generic object
# serializer as OPEN symbols, so these concrete overloads (more specific than
# flatty's generic `ref T` / `object` handlers) are picked up automatically for
# the matching Game fields. They are visible only within this module, so the
# PvP packet path in src/network is unaffected.
# ---------------------------------------------------------------------------

# Raw pointer (Game.game3D): never serialized; restored as nil.
proc toFlatty*(s: var string, x: pointer) = discard
proc fromFlatty*(s: string, i: var int, x: var pointer) = x = nil

# Deque[T] (Player.aftershockPosHistory): flatty has no native Deque support.
proc toFlatty*[T](s: var string, x: Deque[T]) =
  s.toFlatty(x.len.int64)
  for e in x:
    s.toFlatty(e)

proc fromFlatty*[T](s: string, i: var int, x: var Deque[T]) =
  var n: int64
  s.fromFlatty(i, n)
  x = initDeque[T]()
  for _ in 0 ..< n.int:
    var e: T
    s.fromFlatty(i, e)
    x.addLast(e)

# Runtime handles / render state: skipped on write, re-attached from the live
# game on restore (see restoreGame). Nulling them here means suspendGame never
# has to mutate (and then un-mutate) the passed game.
proc toFlatty*(s: var string, x: DiscordClient) = discard
proc fromFlatty*(s: string, i: var int, x: var DiscordClient) = x = nil

proc toFlatty*(s: var string, x: ParticlePool) = discard
proc fromFlatty*(s: string, i: var int, x: var ParticlePool) = x = nil

proc toFlatty*(s: var string, x: RogueliteProfile) = discard
proc fromFlatty*(s: string, i: var int, x: var RogueliteProfile) = x = nil

proc toFlatty*(s: var string, x: OSBackgroundState) = discard
proc fromFlatty*(s: string, i: var int, x: var OSBackgroundState) = discard

proc toFlatty*(s: var string, x: OSHUDState) = discard
proc fromFlatty*(s: string, i: var int, x: var OSHUDState) = discard

proc toFlatty*(s: var string, x: DopamineState) = discard
proc fromFlatty*(s: string, i: var int, x: var DopamineState) = discard

# ---------------------------------------------------------------------------
# Snapshot payload: the Game graph plus the module-global per-run statistics.
#
# GLOBALS AUDIT (module-level `var`s that affect the sim):
#   game.nim  : enemyGrid / gridBossIndices / gridMax* / gridCandidates
#               -> the spatial acceleration grid, fully rebuilt every frame from
#                  game.enemies at the top of updateGame; NOT captured.
#   run_statistics.nim : currentRunStats (per-run stats) -> CAPTURED here so a
#               restored run keeps its accumulated stats. lastCompletedRun is
#               only written at run end, so it is irrelevant mid-run.
#   d_systems/d_visuals/d_enhancements/combat/... : no module-level `var`s.
# The boss-wave manager and pending-boss live inside Game (game.bossWaveManager,
# game.pendingBoss) and ride along in the graph automatically.
# ---------------------------------------------------------------------------
type
  Snapshot = object
    game: Game
    runStats: RunStatistics

const
  SnapMagic = "THSSNAP1"          # 8 bytes
  SnapFormatVersion = 8'u32  # bumped: roguelite sectors became reward-door paths (dungeon types rewritten) + patches
  HeaderLen = 20                  # magic(8) + version(4) + fingerprint(4) + mode(4)

proc layoutFingerprint(): uint32 =
  ## Compile-time-derived digest of the serialized type layout. Combines the
  ## `high` ordinal of the big enums (so appending an enum value invalidates old
  ## snapshots) with the byte size of the core ref-object bodies (so most field
  ## reorderings / additions invalidate them too). A mismatch makes restoreGame
  ## fail cleanly and the caller falls back to the run_save checkpoint.
  var h = 2166136261'u32
  template mix(v: int) =
    h = (h xor uint32(v and 0xFFFFFFFF)) * 16777619'u32
  mix(ord(high(PowerUpType)))
  mix(ord(high(EnemyType)))
  mix(ord(high(GameState)))
  mix(ord(high(GameMode)))
  mix(ord(high(AttackWarningType)))
  mix(ord(high(ElementType)))
  mix(ord(high(DungeonFloorTheme)))
  mix(ord(high(RogueliteStarterKit)))
  mix(ord(high(RogueliteRelicType)))
  mix(ord(high(RoomReward)))
  mix(ord(high(DungeonPickupKind)))
  # The roguelite run graph (sector, rooms, pickups) is snapshotted too.
  mix(sizeof(typeof(default(RogueliteRun)[])))
  mix(sizeof(typeof(default(DungeonFloor)[])))
  mix(sizeof(typeof(default(DungeonRoom)[])))
  mix(sizeof(typeof(default(DungeonPickup)[])))
  mix(sizeof(typeof(default(Game)[])))
  mix(sizeof(typeof(default(Player)[])))
  mix(sizeof(typeof(default(Enemy)[])))
  mix(sizeof(typeof(default(Bullet)[])))
  # The run statistics ride in the same positional flatty stream, so a field
  # added there shifts every byte after it exactly like a Game field would.
  mix(sizeof(typeof(default(RunStatistics)[])))
  h

# ---- little-endian uint32 header helpers ----
proc putU32(s: var string, v: uint32) =
  s.add char(v and 0xFF)
  s.add char((v shr 8) and 0xFF)
  s.add char((v shr 16) and 0xFF)
  s.add char((v shr 24) and 0xFF)

proc getU32(s: string, off: int): uint32 =
  uint32(byte s[off]) or (uint32(byte s[off + 1]) shl 8) or
    (uint32(byte s[off + 2]) shl 16) or (uint32(byte s[off + 3]) shl 24)

const LegacySuspendFile = "suspend.snap"

proc getSuspendPath*(mode: GameMode): string =
  ## One snapshot per mode, so starting or quitting a run in one mode can never
  ## discard another mode's suspended run.
  getAppDataPath() / ("suspend_" & $mode & ".snap")

proc migrateLegacySuspendSnapshot() =
  ## Older builds kept a single shared suspend.snap. Move it to the file of the
  ## mode recorded in its header (or drop it if that slot is already taken or
  ## the header is unreadable).
  try:
    let legacy = getAppDataPath() / LegacySuspendFile
    if not fileExists(legacy):
      return
    let raw = readFile(legacy)
    if raw.len >= HeaderLen and raw.startsWith(SnapMagic):
      let m = int(getU32(raw, 16))
      if m >= ord(low(GameMode)) and m <= ord(high(GameMode)):
        let dest = getSuspendPath(GameMode(m))
        if not fileExists(dest):
          moveFile(legacy, dest)
          return
    removeFile(legacy)
  except CatchableError:
    echo "Warning: could not migrate legacy suspend snapshot"

proc deleteSuspendSnapshot*(mode: GameMode) =
  ## Remove this mode's exact snapshot for the current profile, if any.
  migrateLegacySuspendSnapshot()
  try:
    let path = getSuspendPath(mode)
    if fileExists(path):
      removeFile(path)
  except CatchableError:
    echo "Warning: could not delete suspend snapshot"

proc hasSuspendSnapshot*(mode: GameMode): bool =
  ## Cheap existence check. Full validity (magic/version/fingerprint) is only
  ## confirmed by restoreGame; callers fall back to run_save when restore fails.
  migrateLegacySuspendSnapshot()
  try:
    fileExists(getSuspendPath(mode))
  except CatchableError:
    false

proc isSupportedSuspendMode(mode: GameMode): bool =
  mode in {gmWaveBased, gmTimeSurvival, gmRoguelite}

const ResumableStates = {gsPlaying, gsPaused, gsShop, gsCountdown, gsWaveCleared,
                         gsPowerUpSelect, gsRogueliteFloorSelect}

proc suspendGame*(game: Game) =
  ## Write an exact snapshot of the live simulation to this mode's snapshot file.
  ## Mirrors run_save's guards: no-op for unsupported modes / non-resumable
  ## states, and DELETES any stale snapshot for a finished/failed run. Because
  ## the runtime fields have no-op serializers, the passed `game` is left fully
  ## unchanged.
  if game.isNil or not isSupportedSuspendMode(game.mode):
    return
  if game.state notin ResumableStates:
    return
  # Same exemption as run_save.saveRunState: tutorial sessions never persist.
  if tutorialSuppressesSaves(game):
    return
  # Never persist a finished/failed run (matches run_save.saveRunState).
  if game.hasWonGame and game.mode == gmWaveBased:
    deleteSuspendSnapshot(game.mode)
    return
  if game.mode == gmRoguelite and (game.rogueliteRun.isNil or
     game.rogueliteRun.completed or game.rogueliteRun.died):
    deleteSuspendSnapshot(game.mode)
    return

  try:
    let snap = Snapshot(game: game, runStats: currentRunStats)
    var payload = supersnappy.compress(toFlatty(snap))
    var outp = ""
    outp.add SnapMagic
    outp.putU32(SnapFormatVersion)
    outp.putU32(layoutFingerprint())
    outp.putU32(uint32(ord(game.mode)))
    outp.add payload
    writeFile(getSuspendPath(game.mode), outp)
  except CatchableError:
    echo "Warning: could not write suspend snapshot"

# ---- shared-reference repair ----
# flatty writes every ref by value, so a hazard referenced from two places comes
# back as two separate objects. Three such links exist: a boss satellite's beam
# and charge telegraph (also in game.lasers / game.attackWarnings) and a Cross
# enemy's dash laser (also in game.lasers). Left as copies, the owner moves an
# invisible twin while the real hazard freezes where it was saved, and
# retireSatelliteHazards can no longer find it. The copies are field-for-field
# identical to their list entry, so each is swapped back for that entry.

proc samePos(a, b: Vector2f): bool {.inline.} =
  a.x == b.x and a.y == b.y

proc listTwin(lasers: seq[Laser], copy: Laser): Laser =
  ## The game.lasers entry this deserialized copy was taken from, or nil.
  if copy.isNil: return nil
  for l in lasers:
    if l.sourceEnemyId == copy.sourceEnemyId and l.direction == copy.direction and
       samePos(l.pos, copy.pos) and l.rotation == copy.rotation and
       l.lifetime == copy.lifetime and l.length == copy.length:
      return l
  nil

proc listTwin(warnings: seq[AttackWarning], copy: AttackWarning): AttackWarning =
  ## The game.attackWarnings entry this deserialized copy was taken from, or nil.
  if copy.isNil: return nil
  for w in warnings:
    if w.attackType == copy.attackType and w.sourceEnemyId == copy.sourceEnemyId and
       samePos(w.pos, copy.pos) and samePos(w.targetPos, copy.targetPos) and
       w.lifetime == copy.lifetime:
      return w
  nil

proc relinkSharedRefs(g: Game) =
  for enemy in g.enemies:
    if not enemy.activeCrossLaser.isNil:
      enemy.activeCrossLaser = listTwin(g.lasers, enemy.activeCrossLaser)
    for s in enemy.satellites.mitems:
      if not s.activeLaser.isNil:
        s.activeLaser = listTwin(g.lasers, s.activeLaser)
      if not s.activeWarning.isNil:
        s.activeWarning = listTwin(g.attackWarnings, s.activeWarning)

proc restoreGame*(target: var Game): bool =
  ## Rebuild the exact simulation onto `target` (which the caller has already
  ## constructed via newGame + setGameMode(savedMode) and assigned the live
  ## discordClient / rogueliteProfile). On success `target` is REPLACED by the
  ## restored graph, with runtime/live fields carried over from the old target,
  ## and returns true. On ANY failure (missing file, bad magic, version or
  ## layout-fingerprint mismatch, corrupt payload) returns false WITHOUT touching
  ## target, so the caller can delete the snapshot and fall back to run_save.
  migrateLegacySuspendSnapshot()
  try:
    let path = getSuspendPath(target.mode)
    if not fileExists(path):
      return false
    let raw = readFile(path)
    if raw.len < HeaderLen or not raw.startsWith(SnapMagic):
      return false
    if getU32(raw, 8) != SnapFormatVersion:
      return false
    if getU32(raw, 12) != layoutFingerprint():
      return false

    let payload = supersnappy.uncompress(raw[HeaderLen ..< raw.len])
    let snap = payload.fromFlatty(Snapshot)
    if snap.game.isNil or snap.game.player.isNil:
      return false
    if snap.game.mode != target.mode:
      return false

    let restored = snap.game
    relinkSharedRefs(restored)
    # Carry runtime/live fields from the shell the caller built.
    restored.discordClient = target.discordClient       # process-lifetime handle
    restored.rogueliteProfile = target.rogueliteProfile # keep LIVE meta profile
    restored.game3D = nil                               # 3D state never suspended
    restored.osBackground = target.osBackground         # freshly-inited render state
    restored.osHUD = target.osHUD
    restored.dopamine = target.dopamine
    restored.particlePool = target.particlePool         # cosmetic particle buffers
    restored.screenWidth = target.screenWidth           # match the current window
    restored.screenHeight = target.screenHeight

    # Restore the per-run statistics global (run-scoped, so from the snapshot).
    if not snap.runStats.isNil:
      currentRunStats = snap.runStats

    target = restored
    return true
  except CatchableError:
    return false
  except Defect:
    return false
  except:
    return false
