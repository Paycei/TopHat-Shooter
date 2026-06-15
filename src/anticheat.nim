## Shooteros Anti-Cheat Engine (SACE)
##
##      On-disk tamper detection. Save files (`settings.json`, `stats.json`) are
##      plain JSON, so anyone can hand-edit them or have an external tool (e.g.
##      Cheat Engine) rewrite them. We stamp each saved file with a salted hash
##      under a `_sig` key and re-check it on load. A *present-but-wrong* `_sig`
##      is the only thing we treat as tamper -- a *missing* `_sig` means a legacy
##      (pre-SACE) save and is trusted, then re-signed on the next save. This is
##      essential: without it every existing player would be falsely flagged on
##      first launch. On tamper we revert to a `<file>.bak` mirror of the last
##      legitimately-written save (the "revert, don't reset" behaviour).
##
##      Runtime value sanity. An external memory editor that pins HP, coins, or
##      speed to absurd values leaves the live `Player` outside ranges that legit
##      play can ever produce (most reliably `hp > maxHp`, which the game always
##      clamps). A per-frame scan reverts the player to the last in-bounds
##      snapshot and flags the run.
##
## Enforcement funnels through the game's existing `cheatsUsed` pipeline plus a
## session-sticky `integrityCompromised` flag (for load-time detections that
## happen before a run exists, since `cheatsUsed` resets each run). See
## `runIsLegit`.

import std/[json, os, strutils]
import types, localization

type
  IntegrityStatus* = enum
    isValid     ## signature present and correct
    isLegacy    ## no signature (pre-SACE save, or no file) -- trusted
    isReverted  ## primary file tampered; reverted to a valid `.bak`
    isTampered  ## tampered and no valid backup available

# Session state

var integrityCompromised*: bool = false
  ## Once any tamper/anomaly is detected this session, stays set until restart.
  ## Read by the lifetime-stats freeze gate and the unlock gates.

var integrityNotices: seq[TranslationKey] = @[]
  ## Player-facing notices queued by detections that may happen before a HUD
  ## exists (e.g. save loading at startup). Drained into the HUD by the game loop.

proc flagIntegrity*(reason: TranslationKey) =
  ## Mark this session's integrity as compromised and queue a one-off notice.
  integrityCompromised = true
  if reason notin integrityNotices:
    integrityNotices.add(reason)

proc runIsLegit*(game: Game): bool {.inline.} =
  ## Single source of truth for "should this run count toward saved progress?".
  ## Covers both in-run cheat-menu use and session-level tamper detection.
  (not game.cheatsUsed) and (not integrityCompromised)

proc drainIntegrityNotices*(game: Game) =
  ## Move any queued integrity notices into the in-game notification panel.
  ## Mirrors `os_hud.addNotification` (same OSNotification fields / 5-item cap)
  ## but lives here to avoid a UI-layer import. Safe to call every frame.
  if integrityNotices.len == 0: return
  for reason in integrityNotices:
    game.osHUD.notifications.add(OSNotification(
      message: t(reason),
      notifType: ntCritical,
      lifetime: 0.0,
      fadeTime: 6.0))
    if game.osHUD.notifications.len > 5:
      game.osHUD.notifications.delete(0)
  integrityNotices.setLen(0)

# salted hash
# A hand-rolled 64-bit FNV-1a. std/sha1 has been migrating out of the stdlib
# toward the `checksums` package and can warn/break across Nim versions; since
# the salt ships inside the binary the hash has no cryptographic value anyway,
# so a dependency-free hash is exactly as strong as SHA-1 here. The salt is
# assembled from fragments so it is not a single grep-able literal.

const
  saltA = "th0s::"
  saltB = "k3rn3l-"
  saltC = "4nt1ch34t::v1"

proc integritySalt(): string {.inline.} = saltA & saltB & saltC

proc fnv1a64(s: string): string =
  var h: uint64 = 0xcbf29ce484222325'u64
  for ch in s:
    h = h xor uint64(ord(ch))
    h = h * 0x00000100000001B3'u64
  toHex(h)  # 16 uppercase hex chars

proc signature(node: JsonNode): string =
  ## Salted hash over the canonical serialization of `node` *without* its `_sig`.
  ## JsonNode preserves key order, so a written-then-read object round-trips to
  ## the same string and therefore the same signature.
  var bare = node.copy()
  if bare.kind == JObject and bare.hasKey("_sig"):
    bare.delete("_sig")
  fnv1a64(integritySalt() & $bare)

proc signObject*(node: JsonNode): JsonNode =
  ## Return a copy of `node` carrying a correct `_sig` field.
  result = node.copy()
  if result.kind != JObject: return result
  if result.hasKey("_sig"): result.delete("_sig")
  result["_sig"] = %signature(result)

proc verifyNode(node: JsonNode): IntegrityStatus =
  if node.isNil or node.kind != JObject or not node.hasKey("_sig"):
    return isLegacy  # missing signature == legacy save, never treated as tamper
  if node["_sig"].getStr() == signature(node): isValid else: isTampered

# Signed file I/O

proc writeSignedJson*(path: string, node: JsonNode): bool =
  ## Write `node` with a signature, mirroring it to `<path>.bak` as the
  ## last-known-legitimate copy used for revert-on-tamper.
  try:
    let s = signObject(node).pretty()
    writeFile(path, s)
    writeFile(path & ".bak", s)
    true
  except CatchableError:
    false

proc readVerifiedJson*(path: string): tuple[node: JsonNode, status: IntegrityStatus] =
  ## Read and verify `path`. On tamper (present-but-wrong sig or unparseable),
  ## fall back to `<path>.bak` (the last legitimate save). Returns the node to
  ## use plus the status; a nil node means "no save / nothing usable".
  if not fileExists(path):
    return (nil, isLegacy)

  var primary: JsonNode = nil
  try:
    primary = parseJson(readFile(path))
  except CatchableError:
    primary = nil

  if not primary.isNil:
    let st = verifyNode(primary)
    if st == isValid or st == isLegacy:
      return (primary, st)

  # Primary is tampered or unparseable -- try the backup mirror.
  let bak = path & ".bak"
  if fileExists(bak):
    try:
      let bnode = parseJson(readFile(bak))
      if verifyNode(bnode) == isValid:
        return (bnode, isReverted)
    except CatchableError:
      discard

  # No usable backup: hand back whatever parsed (may be tampered), flagged.
  (primary, isTampered)

proc handleLoadStatus*(path, label: string, status: IntegrityStatus) =
  ## Shared reaction to a load result: log + flag + queue a notice as needed.
  case status
  of isValid, isLegacy:
    discard
  of isReverted:
    echo "SACE: ", label, " tampered, reverted to backup (", path, ")"
    flagIntegrity(tkNotifAntiCheatReverted)
  of isTampered:
    echo "SACE: ", label, " tampered and no valid backup (", path, ")"
    flagIntegrity(tkNotifAntiCheatTampered)

# Runtime value sanity
# Bounds are deliberately far looser than any reachable legit value. They exist
# only to catch external editors that set values to absurd magnitudes; they are
# NOT a balance check. `hp <= maxHp` is the rock-solid one (the game always
# clamps HP), so it uses only float slack.

const
  MAX_PLAUSIBLE_MAXHP = 10_000_000.0'f32
  MAX_PLAUSIBLE_SPEED = 100_000.0'f32
  MAX_PLAUSIBLE_COINS = 100_000_000

type
  IntegritySnapshot = object
    valid: bool
    hp, maxHp, speed: float32
    coins: int

var lastGood: IntegritySnapshot

proc resetIntegritySnapshot*() =
  ## Called when a new run begins so a flagged player can start clean.
  lastGood = IntegritySnapshot()

proc playerValuesSane(p: Player): bool =
  if p.maxHp <= 0.0'f32 or p.maxHp > MAX_PLAUSIBLE_MAXHP: return false
  if p.hp < -1.0'f32 or p.hp > p.maxHp * 1.02'f32 + 1.0'f32: return false
  if p.speed < 0.0'f32 or p.speed > MAX_PLAUSIBLE_SPEED: return false
  if p.coins < 0 or p.coins > MAX_PLAUSIBLE_COINS: return false
  true

proc scanRuntimeIntegrity*(game: Game) =
  ## Per-frame sanity scan of the player's critical values. On a breach, revert
  ## every protected field to the last in-bounds snapshot ("revert, don't
  ## reset") -- or clamp into range if no snapshot exists yet -- and flag the
  ## run. Detection is bounds-only on purpose: a shadow-diff scheme cannot tell
  ## "earned 500 coins this frame" from "edited to 500 coins" without routing
  ## every mutation through a setter, and would false-positive on normal play.
  if game.player.isNil: return
  # Only scan modes whose runs persist progression. Sandbox is a tester mode
  # that deliberately sets extreme values (and never sets cheatsUsed for them),
  # and PvP values aren't locally authoritative -- scanning either would only
  # create false positives, and a false positive here is session-sticky.
  if game.mode notin {gmWaveBased, gmTimeSurvival, gmRoguelite}: return
  # Sanctioned cheat-menu values are intentional; don't fight them.
  if game.cheatsUsed: return

  let p = game.player
  if playerValuesSane(p):
    lastGood = IntegritySnapshot(valid: true,
      hp: p.hp, maxHp: p.maxHp, speed: p.speed, coins: p.coins)
    return

  if lastGood.valid:
    p.hp = lastGood.hp
    p.maxHp = lastGood.maxHp
    p.speed = lastGood.speed
    p.coins = lastGood.coins
  else:
    if p.maxHp <= 0.0'f32: p.maxHp = 1.0'f32
    elif p.maxHp > MAX_PLAUSIBLE_MAXHP: p.maxHp = MAX_PLAUSIBLE_MAXHP
    if p.hp < 0.0'f32: p.hp = 0.0'f32
    elif p.hp > p.maxHp: p.hp = p.maxHp
    if p.speed < 0.0'f32: p.speed = 0.0'f32
    elif p.speed > MAX_PLAUSIBLE_SPEED: p.speed = MAX_PLAUSIBLE_SPEED
    if p.coins < 0: p.coins = 0
    elif p.coins > MAX_PLAUSIBLE_COINS: p.coins = MAX_PLAUSIBLE_COINS

  flagIntegrity(tkNotifAntiCheatRuntime)
  game.cheatsUsed = true  # freeze stats for this in-progress run
