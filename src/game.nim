import raylib, rlgl, random, math, tables, strutils, algorithm
import types, settings, save_system, player, enemy, bullet, consumable, coin, wall, boss_definitions, particle, particle_pool, particle_skins, particle_types, effects, powerup, powerup_data, sound, d_systems, d_visuals, d_enhancements, survival, render_context, roguelite, dungeon, gamemode_definitions, run_statistics, statistics, enemy_config, enemy_helpers, localization, game3d/game_3d, ui/os_shop, ui/os_background, ui/os_hud, ui/os_debug_panel, ui/os_combined_hud, ui/os_system_screens, ui/os_enemy_labels, ui/icon_drawing, ui/ui_constants, boss_weakpoints, anticheat, fx, ui/warnings

# Configurable boss wave enemy spawn reduction
const ECHO_MAX_SPAWNS = 5  # Cap echo trail bullets per parent so piercing/ricochet/etc. can't spawn an unbounded trail
const GATE_DAMAGE_LEAK = 0.04'f32  # fraction of body damage that still lands while a boss gate (adds/shield) is up
const BOSS_WAVE_SPAWN_MULTIPLIER = 0.25  # 25% of normal spawn
const TIME_SURVIVAL_BOSS_INTERVAL = 60.0
const BOSS_PHASE_INVULNERABILITY_DURATION = BossPhaseTransitionDuration
const DEATH_SLOW_DURATION = 1.1'f32
const DEATH_SPEEDUP_DURATION = 0.35'f32
const DEATH_FADE_DURATION = 0.65'f32
const DEATH_TOTAL_DURATION = DEATH_SLOW_DURATION + DEATH_SPEEDUP_DURATION + DEATH_FADE_DURATION
const DEATH_SLOW_SCALE = 0.16'f32
const DEATH_FAST_SCALE = 1.35'f32

# Spatial-grid acceleration (SpatialGrid is in enemy_helpers.nim)
# One grid + scratch set, reused every frame to bucket game.enemies by screen
# cell so the bullet-vs-enemy and enemy-vs-enemy proximity loops run in ~O(n)
# instead of O(bullets*enemies) / O(enemies^2). Module-global so steady-state
# rebuilds allocate nothing (buckets keep their capacity across frames).
const GRID_CELL_SIZE = 96.0'f32  # px. Comfortably exceeds any hit radius, so the
                                 # neighbourhood query is a non-lossy superset,
                                 # while staying small enough that buckets are sparse.
const GRID_MARGIN = 200.0'f32    # world bounds extend this far past the screen so
                                 # enemies spawning just off-screen still bin exactly.
const GRID_MIN_ENEMIES = 24      # below this the per-bullet grid query + sort costs
                                 # more than a plain full scan, so the bullet loop
                                 # falls back to checking all enemies (it's already
                                 # cheap at low counts, and the frame has headroom).

var enemyGrid: SpatialGrid
var gridBossIndices: seq[int]       # bosses are always force-checked: their weak-point
                                    # targets can sit beyond the body hit radius.
var gridMaxEnemyRadius: float32     # max enemy.radius          -> bullet-hit query reach
var gridMaxCollisionRadius: float32 # max enemy.collisionRadius -> separation query reach
var gridCandidates: seq[int]        # reused per-bullet candidate buffer (sorted+deduped)

proc rebuildEnemyGrid(game: Game) =
  ## Re-bucket every enemy and recompute the per-frame query reaches + boss list
  ## in a single O(enemy count) pass. The resulting indices are valid only until
  ## game.enemies is next mutated, so rebuild *immediately* before a query batch.
  enemyGrid.rebuild(game.enemies, GRID_CELL_SIZE,
                    -GRID_MARGIN, -GRID_MARGIN,
                    game.screenWidth.float32 + GRID_MARGIN,
                    game.screenHeight.float32 + GRID_MARGIN)
  gridBossIndices.setLen(0)
  gridMaxEnemyRadius = 0.0'f32
  gridMaxCollisionRadius = 0.0'f32
  for idx in 0 ..< game.enemies.len:
    let e = game.enemies[idx]
    if e.radius > gridMaxEnemyRadius: gridMaxEnemyRadius = e.radius
    if e.collisionRadius > gridMaxCollisionRadius: gridMaxCollisionRadius = e.collisionRadius
    if e.isBoss: gridBossIndices.add(idx)

proc getDeathSequenceTimeScale(timer: float32): float32 =
  if timer < DEATH_SLOW_DURATION:
    return DEATH_SLOW_SCALE

  if timer < DEATH_SLOW_DURATION + DEATH_SPEEDUP_DURATION:
    let t = clamp((timer - DEATH_SLOW_DURATION) / DEATH_SPEEDUP_DURATION, 0.0'f32, 1.0'f32)
    let eased = 1.0'f32 - pow(1.0'f32 - t, 3.0'f32)
    return DEATH_SLOW_SCALE + (DEATH_FAST_SCALE - DEATH_SLOW_SCALE) * eased

  DEATH_FAST_SCALE

proc updateLightningBolts*(game: var Game, dt: float32)

proc clampByte(value: int): uint8 =
  uint8(max(0, min(255, value)))

proc withAlpha(color: Color, alpha: int): Color =
  Color(r: color.r, g: color.g, b: color.b, a: clampByte(alpha))


# ---------------------------------------------------------------------------
# game.nim is split into topical fragments under src/game/, spliced in below
# via `include` (NOT imported as modules) so they share this module scope:
# the consts, module vars (enemyGrid, ...), forward declarations and every
# proc stay mutually visible with no extra imports. Fragments are included in
# original source order, so all definition-ordering relationships are preserved.
# See CLAUDE.md for the layout.
# ---------------------------------------------------------------------------
include "game/death.nim"
include "game/boss_waves.nim"
include "game/auras.nim"
include "game/combat.nim"
include "game/bullets.nim"
include "game/lifecycle.nim"
include "game/waves.nim"
include "game/shooting.nim"
include "game/bosses.nim"
include "game/orbitals.nim"
include "game/update.nim"
include "game/draw.nim"
