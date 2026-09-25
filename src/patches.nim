## Roguelite PATCHES: identity, text and tuning.
##
## The player-facing name for RogueliteRelicType. Each patch is presented as a
## numbered system update ("KB-3101 Overclock") applied for the rest of the
## run. Picked one-of-three from /updates and /quarantine folders, or bought
## at a /pkg stall.
##
## A leaf module (raylib, types, localization only) so every system that
## applies a patch effect can import it: powerup (reroll pricing), combat
## (stat modifiers), player (hit interception), coin/xp_orb (magnet), the
## dungeon and the UI.
##
## Recipe for a new patch:
##   1. Append the value to RogueliteRelicType in types.nim (never rename or
##      reorder: run saves store `$value`).
##   2. Add a branch to patchKey, patchKbNumber and patchCategory below
##      (exhaustive, so the compiler insists).
##   3. Add "patch_<key>_name" + "patch_<key>_desc" to BOTH language tables.
##   4. Add a glyph branch to drawPatchIcon in ui/icon_drawing.nim.
##   5. Implement the effect at its hook, gated on hasPatch(player, ...).

import raylib, math
import types, localization

type
  PatchCategory* = enum
    pcSecurity,      # blocks / survives damage
    pcPerformance,   # changes how the build fights
    pcMaintenance    # economy and upkeep

  PatchStatus* = enum
    ## What a patch is doing right now, as the HUD and pause menu show it.
    psPassive,       # always on; nothing to report
    psReady,         # a charge is waiting to fire
    psUsed,          # the charge is spent until it re-arms
    psStalled        # temporarily switched off

const
  AllPatches* = {succ(rrtNone)..high(RogueliteRelicType)}

  # Tuning. Kept here so the description text, the effect code and any
  # tooltip all read the same numbers.
  DiscountProtocolFactor* = 0.8'f32      # rerolls and /pkg stalls
  DiscountProtocolFloor* = 5
  ShardMagnetBonus* = 0.25'f32
  EliteDividendCredits* = 30
  EliteDividendShards* = 16
  EmergencyPatchBossHeal* = 0.25'f32     # of max integrity, on a SERVICE kill
  OverclockFireRateBonus* = 0.35'f32
  OverclockStallTime* = 3.0'f32
  DefragmenterRoomHeal* = 0.08'f32
  DefragmenterBossHeal* = 0.20'f32
  CronJobInterval* = 8.0'f32
  CronJobRounds* = 12
  ZipBombRadius* = 150.0'f32
  ZipBombDamageMult* = 2.5'f32
  RootAccessBonus* = 0.25'f32
  RootAccessPenalty* = 0.10'f32
  RollbackRestore* = 0.5'f32
  RollbackInvulnTime* = 2.0'f32
  CryptominerDamagePenalty* = 0.10'f32
  RaidMirrorEvery* = 3
  PacketLossChance* = 0.15'f32
  RerollBaseCost* = 25

proc patchKey(p: RogueliteRelicType): string =
  case p
  of rrtNone: "none"
  of rrtDiscountProtocol: "discount"
  of rrtShardMagnet: "shard_magnet"
  of rrtEliteDividend: "elite_dividend"
  of rrtEmergencyPatch: "emergency"
  of rrtDraftCache: "draft_cache"
  of rrtOverclock: "overclock"
  of rrtFirewallRule: "firewall_rule"
  of rrtDefragmenter: "defragmenter"
  of rrtGarbageCollector: "garbage_collector"
  of rrtCronJob: "cron_job"
  of rrtZipBomb: "zip_bomb"
  of rrtRootAccess: "root_access"
  of rrtRollback: "rollback"
  of rrtCryptominer: "cryptominer"
  of rrtRaidMirror: "raid_mirror"
  of rrtPacketLoss: "packet_loss"

proc patchKbNumber*(p: RogueliteRelicType): int =
  ## Fixed per patch, so a player learns "KB-3146" means Rollback.
  case p
  of rrtNone: 0
  of rrtDiscountProtocol: 2025
  of rrtShardMagnet: 2031
  of rrtEliteDividend: 2047
  of rrtEmergencyPatch: 2050
  of rrtDraftCache: 2058
  of rrtOverclock: 3101
  of rrtFirewallRule: 3107
  of rrtDefragmenter: 3112
  of rrtGarbageCollector: 3118
  of rrtCronJob: 3124
  of rrtZipBomb: 3131
  of rrtRootAccess: 3140
  of rrtRollback: 3146
  of rrtCryptominer: 3153
  of rrtRaidMirror: 3160
  of rrtPacketLoss: 3168

proc patchCategory*(p: RogueliteRelicType): PatchCategory =
  case p
  of rrtFirewallRule, rrtRollback, rrtEmergencyPatch, rrtPacketLoss: pcSecurity
  of rrtOverclock, rrtDefragmenter, rrtCronJob, rrtRaidMirror, rrtRootAccess,
     rrtZipBomb: pcPerformance
  of rrtNone, rrtDiscountProtocol, rrtShardMagnet, rrtEliteDividend,
     rrtDraftCache, rrtGarbageCollector, rrtCryptominer: pcMaintenance

proc patchKbLabel*(p: RogueliteRelicType): string =
  "KB-" & $patchKbNumber(p)

proc patchName*(p: RogueliteRelicType): string =
  t("patch_" & patchKey(p) & "_name")

proc patchDescription*(p: RogueliteRelicType): string =
  t("patch_" & patchKey(p) & "_desc")

proc patchCategoryName*(c: PatchCategory): string =
  case c
  of pcSecurity: t("patch_category_security")
  of pcPerformance: t("patch_category_performance")
  of pcMaintenance: t("patch_category_maintenance")

proc patchCategoryAccent*(c: PatchCategory): Color =
  case c
  of pcSecurity: Color(r: 90, g: 200, b: 255, a: 255)
  of pcPerformance: Color(r: 255, g: 150, b: 70, a: 255)
  of pcMaintenance: Color(r: 130, g: 230, b: 150, a: 255)

proc patchAccent*(p: RogueliteRelicType): Color =
  patchCategoryAccent(patchCategory(p))

proc hasPatch*(player: Player, p: RogueliteRelicType): bool =
  not player.isNil and p in player.patches

const ChargePatches* = {rrtRollback, rrtFirewallRule, rrtOverclock}
  ## The patches with a live state (exactly the non-passive branches of
  ## patchStatus). The HUD lists them first so their tag is never hidden.

proc patchStatus*(game: Game, p: RogueliteRelicType): PatchStatus =
  ## Only the charge patches have a state worth showing; the rest just run.
  case p
  of rrtRollback:
    if game.player.rollbackArmed: psReady else: psUsed
  of rrtFirewallRule:
    if game.waveInProgress and game.player.patchBlockCharges <= 0: psUsed else: psReady
  of rrtOverclock:
    if game.player.overclockStallTimer > 0: psStalled else: psPassive
  else: psPassive

proc patchStatusLabel*(s: PatchStatus): string =
  case s
  of psPassive: t("patch_status_active")
  of psReady: t("patch_status_ready")
  of psUsed: t("patch_status_used")
  of psStalled: t("patch_status_stalled")

proc patchStatusColor*(s: PatchStatus): Color =
  case s
  of psPassive: Color(r: 100, g: 255, b: 100, a: 255)
  of psReady: Color(r: 120, g: 255, b: 190, a: 255)
  of psUsed: Color(r: 150, g: 150, b: 165, a: 255)
  of psStalled: Color(r: 255, g: 165, b: 70, a: 255)

proc patchSpent*(game: Game, p: RogueliteRelicType): bool =
  ## Drawn dimmed: its charge is gone or it is stalled.
  patchStatus(game, p) in {psUsed, psStalled}

proc patchPrice*(player: Player, base: int): int =
  ## The ONE Discount Protocol rule, used by draft rerolls and /pkg stalls
  ## alike, so the patch text can never drift from what it charges again.
  if base <= 0:
    return 0
  if hasPatch(player, rrtDiscountProtocol):
    max(DiscountProtocolFloor, int(round(base.float32 * DiscountProtocolFactor)))
  else:
    base
