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
## compile-time type-layout fingerprint + mode + a checksum of the payload)
## precedes the compressed payload.
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

import os, deques, strutils, tables, std/macros
import modding/mod_patch_core
import types, save_system, run_statistics, tutorial
import modding/[mod_state, mod_hooks]
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

# flatty's array copy indexes x[0.N], which an array keyed by the mod
# power-up slots (puMod000..puMod255, ordinal 88+) can't take: walk it instead.
proc toFlatty*(s: var string, x: array[FirstModPowerUp..LastModPowerUp, float32]) {.moddable.} =
  for e in x: s.toFlatty(e)
proc fromFlatty*(s: string, i: var int, x: var array[FirstModPowerUp..LastModPowerUp, float32]) {.moddable.} =
  for e in x.mitems: s.fromFlatty(i, e)

proc toFlatty*(s: var string, x: RogueliteProfile) = discard
proc fromFlatty*(s: string, i: var int, x: var RogueliteProfile) = x = nil

proc toFlatty*(s: var string, x: OSBackgroundState) = discard
proc fromFlatty*(s: string, i: var int, x: var OSBackgroundState) = discard

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
  SnapFormatVersion = 18'u32  # bumped: payload checksum, whole-graph layout fingerprint (17: unread fields removed; 16: mod consumables/patches/events/shop rows/[Q])
  HeaderLen = 28                  # magic(8) + version(4) + fingerprint(4) + mode(4) + payload checksum(8)

# ---- layout fingerprint ----
# flatty writes the graph positionally, with no field names, and trusts every
# length it reads back: a snapshot read under another layout is garbage, and
# -d:danger builds crash on garbage lengths instead of raising. So the
# fingerprint is the whole serialized type graph, worked out at compile time:
# every field's name and type down to the leaves, and every enum's values.
# Any change to a snapshotted type, however deep (a field on Laser, a value
# appended to an enum), retires older snapshots, and the run_save checkpoint
# takes over. SnapFormatVersion is only for changes the types don't show.

proc layoutOf(t: NimNode, seen: var seq[string], skip: seq[string]): string {.compileTime.} =
  ## The serialized shape of type `t`. A named type met again is named, not
  ## expanded (refs can be recursive); a type in `skip` is only named.
  case t.kind
  of nnkSym:
    let name = $t
    case t.typeKind
    of ntyBool, ntyChar, ntyString, ntyCString, ntyPointer, ntyInt, ntyInt8, ntyInt16,
       ntyInt32, ntyInt64, ntyFloat, ntyFloat32, ntyFloat64, ntyUInt, ntyUInt8,
       ntyUInt16, ntyUInt32, ntyUInt64:
      return name
    else: discard
    if name in skip: return "~" & name
    let id = t.signatureHash
    if id in seen: return "@" & name
    seen.add id
    let impl = t.getTypeImpl
    if impl.kind == nnkSym and impl == t: return name
    result = name & "=" & layoutOf(impl, seen, skip)
  of nnkObjectTy:
    result = "object"
    if t[1].kind == nnkOfInherit:
      result.add " of " & layoutOf(t[1][0], seen, skip)
    result.add "{" & layoutOf(t[2], seen, skip) & "}"
  of nnkRecList:
    for f in t: result.add layoutOf(f, seen, skip) & ";"
  of nnkIdentDefs:
    let typ = layoutOf(t[^2], seen, skip)
    for i in 0 ..< t.len - 2: result.add $t[i] & ":" & typ & ","
  of nnkRecCase:
    result = "case " & layoutOf(t[0], seen, skip)
    for i in 1 ..< t.len: result.add layoutOf(t[i], seen, skip)
  of nnkOfBranch:
    result = "of "
    for i in 0 ..< t.len - 1: result.add t[i].repr & ","
    result.add "{" & layoutOf(t[^1], seen, skip) & "}"
  of nnkElse:
    result = "else{" & layoutOf(t[0], seen, skip) & "}"
  of nnkNilLit, nnkEmpty:
    result = ""
  of nnkEnumTy:
    result = "enum("
    for i in 1 ..< t.len: result.add t[i].repr & ","
    result.add ")"
  of nnkRefTy: result = "ref " & layoutOf(t[0], seen, skip)
  of nnkPtrTy: result = "ptr " & layoutOf(t[0], seen, skip)
  of nnkDistinctTy: result = "distinct " & layoutOf(t[0], seen, skip)
  of nnkTupleTy:
    result = "tuple["
    for f in t: result.add layoutOf(f, seen, skip)
    result.add "]"
  of nnkTupleConstr, nnkPar:
    result = "("
    for f in t: result.add layoutOf(f, seen, skip) & ","
    result.add ")"
  of nnkBracketExpr:
    # seq[T], array[R, T], set[T], a generic instance (Table[K, V], Deque[T]):
    # the container by name, its arguments expanded.
    result = $t[0] & "["
    for i in 1 ..< t.len:
      result.add (if t[i].kind in {nnkSym, nnkBracketExpr, nnkTupleConstr, nnkPar}:
                    layoutOf(t[i], seen, skip) else: t[i].repr) & ","
    result.add "]"
  else:
    result = t.repr

macro layoutSignature(T: typedesc, skip: varargs[string]): string =
  var skipNames: seq[string]
  for s in skip: skipNames.add s.strVal
  var seen: seq[string]
  newLit(layoutOf(T.getTypeInst[1], seen, skipNames))   # (T arrives as typedesc[X])

proc fnv32(s: string, h = 2166136261'u32): uint32 =
  result = h
  for c in s: result = (result xor uint32(ord(c))) * 16777619'u32

const SnapLayoutHash = fnv32(layoutSignature(Snapshot,
  # (the runtime state with the no-op flatty overloads above: never written)
  "DiscordClient", "ParticlePool", "RogueliteProfile", "OSBackgroundState", "DopamineState"))

proc layoutFingerprint(): uint32 =
  ## The snapshot's type graph, and the loaded mod set: mod power-up/enemy
  ## slots are bound per set, so a snapshot's raw slot ordinals only mean the
  ## same thing under the same set. (The file name already pins the set; this
  ## is belt and braces.) A mismatch makes restoreGame fail cleanly and the
  ## caller falls back to the run_save checkpoint.
  fnv32(modFingerprintHex, SnapLayoutHash)

proc payloadChecksum(s: string, start: int): uint64 =
  ## FNV-1a over the compressed payload. snappy notices a file cut short but
  ## not a damaged byte, and flatty would read a damaged length as it is.
  result = 14695981039346656037'u64
  for i in start ..< s.len:
    result = (result xor uint64(ord(s[i]))) * 1099511628211'u64

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

proc getSuspendPath(mode: GameMode, modMode: string = ""): string {.moddable.} =
  ## One snapshot per mode, so starting or quitting a run in one mode can never
  ## discard another mode's suspended run. saveSlotTag keeps modded sessions
  ## on their own files (see run_save.runSaveFileFor).
  getAppDataPath() / ("suspend_" & $mode & saveSlotTag(modMode) & ".snap")

proc migrateLegacySuspendSnapshot() =
  ## Older builds kept a single shared suspend.snap. Move it to the file of the
  ## mode recorded in its header (or drop it if that slot is already taken or
  ## the header is unreadable).
  if modsActive:
    return  # a vanilla leftover must never land in a modded slot
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

proc deleteSuspendSnapshot*(mode: GameMode, modMode: string = "") {.moddable.} =
  ## Remove this mode's exact snapshot for the current profile, if any.
  migrateLegacySuspendSnapshot()
  try:
    let path = getSuspendPath(mode, modMode)
    if fileExists(path):
      removeFile(path)
  except CatchableError:
    echo "Warning: could not delete suspend snapshot"

proc hasSuspendSnapshot*(mode: GameMode, modMode: string = ""): bool {.moddable.} =
  ## Cheap existence check. Full validity (magic/version/fingerprint) is only
  ## confirmed by restoreGame; callers fall back to run_save when restore fails.
  migrateLegacySuspendSnapshot()
  try:
    fileExists(getSuspendPath(mode, modMode))
  except CatchableError:
    false

proc isSupportedSuspendMode(mode: GameMode): bool =
  mode in {gmWaveBased, gmTimeSurvival, gmRoguelite}

const ResumableStates = {gsPlaying, gsPaused, gsShop, gsCountdown, gsWaveCleared,
                         gsPowerUpSelect, gsRogueliteFloorSelect}

proc suspendGame*(game: Game) {.moddable.} =
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
  # Nor does a run a mod made unresumable (modRunResumable), and an older
  # snapshot of it goes, so the desktop never offers it.
  if not modRunResumable(game):
    deleteSuspendSnapshot(game.mode, game.modMode)
    return
  # Never persist a finished/failed run (matches run_save.saveRunState).
  if game.hasWonGame and game.mode == gmWaveBased:
    deleteSuspendSnapshot(game.mode, game.modMode)
    return
  if game.mode == gmRoguelite and (game.rogueliteRun.isNil or
     game.rogueliteRun.completed or game.rogueliteRun.died):
    deleteSuspendSnapshot(game.mode, game.modMode)
    return

  if game.modded and not captureModRunData.isNil:
    captureModRunData(game, true)
  try:
    let snap = Snapshot(game: game, runStats: currentRunStats)
    var payload = supersnappy.compress(toFlatty(snap))
    var outp = ""
    outp.add SnapMagic
    outp.putU32(SnapFormatVersion)
    outp.putU32(layoutFingerprint())
    outp.putU32(uint32(ord(game.mode)))
    let sum = payloadChecksum(payload, 0)
    outp.putU32(uint32(sum and 0xFFFFFFFF'u64))
    outp.putU32(uint32(sum shr 32))
    outp.add payload
    writeFile(getSuspendPath(game.mode, game.modMode), outp)
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

proc samePos(a, b: Vector2): bool {.inline.} =
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

proc restoreGame*(target: var Game): bool {.moddable.} =
  ## Rebuild the exact simulation onto `target` (which the caller has already
  ## constructed via newGame + setGameMode(savedMode) and assigned the live
  ## discordClient / rogueliteProfile). On success `target` is REPLACED by the
  ## restored graph, with runtime/live fields carried over from the old target,
  ## and returns true. On ANY failure (missing file, bad magic, version or
  ## layout-fingerprint mismatch, corrupt payload) returns false WITHOUT touching
  ## target, so the caller can delete the snapshot and fall back to run_save.
  migrateLegacySuspendSnapshot()
  try:
    let path = getSuspendPath(target.mode, target.modMode)
    if not fileExists(path):
      return false
    let raw = readFile(path)
    if raw.len < HeaderLen or not raw.startsWith(SnapMagic):
      return false
    if getU32(raw, 8) != SnapFormatVersion:
      return false
    if getU32(raw, 12) != layoutFingerprint():
      return false
    let sum = uint64(getU32(raw, 20)) or (uint64(getU32(raw, 24)) shl 32)
    if sum != payloadChecksum(raw, HeaderLen):
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
    restored.dopamine = target.dopamine
    restored.particlePool = target.particlePool         # cosmetic particle buffers
    restored.screenWidth = target.screenWidth           # match the current window
    restored.screenHeight = target.screenHeight

    # Equipped cosmetics are profile state, not run state: newGame built the
    # shell's player from the CURRENT settings, so a skin changed in the shop
    # since the snapshot shows on resume. rogueliteCosmetic is the run's class
    # emblem and stays from the snapshot.
    let live = target.player
    let p = restored.player
    p.skinType = live.skinType
    p.bulletSkinType = live.bulletSkinType
    p.bulletShapeType = live.bulletShapeType
    p.shapeType = live.shapeType
    p.particleSkinType = live.particleSkinType
    p.cubeSkinType = live.cubeSkinType
    p.wearsTophat = live.wearsTophat
    p.wearsCheaterHat = live.wearsCheaterHat
    p.hasOrbitalCube = live.hasOrbitalCube
    p.modSkin = live.modSkin
    p.modBulletSkin = live.modBulletSkin
    # Shots already in flight baked the old look in at fire time.
    for b in restored.bullets:
      if b.fromPlayer or b.isShieldReflected:
        b.bulletSkin = p.bulletSkinType
        b.bulletShape = p.bulletShapeType

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
