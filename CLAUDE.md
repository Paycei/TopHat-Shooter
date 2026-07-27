# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

TopHat-ShooterOS is a bullet-heaven game written in Nim with Raylib (via the `naylib` binding). The whole game is themed as a desktop OS.

## Commands

```powershell
nimble install        # fetch dependencies (naylib, flatty, supersnappy)
nimble debug          # nim c -r --mm:orc -d:debug src/main.nim  (build + run, the dev loop)
nimble WinRelease     # optimized MSVC build -> TopHatShooterOS.exe (Windows, needs VC++ Build Tools)
nimble WinReleaseMin  # release optimized for size
nimble LinuxRelease   # optimized Linux build
```

**There is no test suite.** The primary correctness check is compilation:

```powershell
nim check --mm:orc src/main.nim    # fast type-check without producing a binary
```

Always run this after edits. Nim enforces **exhaustive `case` statements over enums**, so adding a value to an enum like `PowerUpType` or `EnemyType` produces a compile error at *every* exhaustive switch that doesn't handle it. `nim check` is how you find them all — do not rely on visual inspection. Note the MSVC release path links `icono.res`; do not remove it.

## Architecture

### Top-level control flow
- `src/main.nim` owns `proc main()`: it creates the window, holds the single `currentGame` object, and runs the frame loop as a **state machine over `GameState`** (`gsSplash`, `gsMenu`, `gsPlaying`, `gsShop`, `gsPowerUpSelect`, `gsPvPPlaying`, …). Each state has its own update/draw branch. Switching menus/modes = reassigning `currentGame` and setting `.state`.
- `src/game.nim` is the gameplay core: `updateGame*` and `drawGame*` (plus the game-over/victory draws), the per-frame system orchestration, the spatial-grid acceleration state (`enemyGrid`, `GRID_*`), game lifecycle (`newGame*`/`setGameMode*`/`cleanupGame*`), and wave flow (`startWave*`/`advanceWave*`). **When in doubt, the top-level frame logic lives here.** It sits at the top of a dependency DAG: it `import`s the gameplay subsystem **modules** under `src/game/` and re-`export`s them, so `main.nim`'s `import game` still sees the whole gameplay API. The subsystems are real importable modules (each with its own `import`s + `*` exports), layered combat → bullets → {auras, death, bosses, orbitals, shooting}:
  - `src/game/combat.nim` — damage/crit/thorns + `showDamage`/`CombatStats` (foundation; nothing else in `game/` is below it).
  - `src/game/bullets.nim` — bullet effects, lightning, `BulletEffects`, aura/explosion radii.
  - `src/game/auras.nim` — aura config + rendering. `src/game/death.nim` — death sequence, `installPowerUp`, `withAlpha`. `src/game/shooting.nim` — `shootBullet`. `src/game/orbitals.nim` — orbital weapons. `src/game/bosses.nim` — boss AI/mechanics + `executeCustomBossAttack` (per-pattern `execBossAttack*` procs). Boss **wave** flow (`BossWaveManager` accessors + `completeBossWave`/`spawnConfiguredBoss`) lives inline in `game.nim` next to the other wave-flow procs, not in a `game/` module.
  When adding gameplay logic, put it in the matching subsystem module (and `*`-export what `game.nim`/siblings call); a subsystem must never `import game` (that's the one cycle to avoid). Only `main.nim` imports `game`.
- `src/types.nim` is the single source of truth for the data model: `Game`, `Player`, `Enemy`, `Bullet`, and every enum. `Player`/`Enemy`/`Bullet` are `ref object`s (mutating a local copy mutates the shared instance — no write-back needed). `float32` is the pervasive numeric type.

### Game modes
Selected via `GameMode`; each delegates out of `game.nim` where it diverges:
- `gmWaveBased` (default) and `gmTimeSurvival` (`survival.nim`) — core PvE loop.
- `gmRoguelite` (`roguelite.nim`, `ui/os_roguelite.nim`) — run-based meta-progression with relics, sectors, and unlockable power families (`RoguelitePowerFamily`).
- `gmPvP` (`pvp_game.nim` + `network/`) — networked multiplayer. `flatty` + `supersnappy` are used **only** for PvP packet serialization, not save files.
- `gmSandbox` (`sandbox.nim`) and a separate 3D boss state (`gs3DBoss`, `game3d/`).

### The OS-desktop UI layer (`src/ui/`)
The menus are a simulated desktop: `os_desktop.nim` (icons, taskbar, wallpaper) plus a `window_manager.nim` that opens/closes/focuses `OSWindow`s by `WindowID`. Each menu (shop, stats, settings, help, advancements, roguelite, pvp) is a window module. In-game HUD is `os_hud.nim` / `os_combined_hud.nim`. All icons are drawn programmatically in `ui/icon_drawing.nim` (no image assets) — `drawPowerUpIcon` is an exhaustive `case PowerUpType`.

### "Dopamine"/juice layer (`d_systems.nim`, `d_visuals.nim`, `d_enhancements.nim`)
Screen shake, combo system, floating damage numbers, and other game-feel feedback, kept separate from core simulation.

### Localization (`localization.nim`)
All user-facing text goes through `t(key)`. There are parallel `English` and `Spanish` string tables; lookup falls back English → raw key. Adding text means adding a `TranslationKey` enum value **and** an entry in *both* language tables.

### Persistence (`save_system.nim`)
Saves are **JSON** written with `writeFile`, with hand-written parse procs (e.g. `parsePowerUpType`). Any new serialized enum value needs a branch added to its parse proc, or it silently falls back to a default. All save I/O goes through `getAppDataPath()`, which resolves to a **per-profile** folder (`<root>/profiles/<slot>/`) — any new save file becomes per-profile automatically just by living there; `getRootDataPath()` is the shared base holding only the slot index. `switchToProfile(slot)` (`main.nim`) is the reload pattern: shared refs (`settings`, `stats`, ...) are mutated **in place**, reset to defaults first so stale keys from the old profile can't leak into the new one.

### Difficulty scaling (`types.nim`)
`GameDifficulty` (`gdEasy`/`gdMedium`/`gdHard`/`gdNightmare`) is fixed per profile at creation and read via the global `currentDifficulty`. Scaling is **not** applied ad hoc at call sites — it goes through exactly two procs, `difficultyEnemyHpMult()`/`difficultyEnemyDamageMult()`, consumed at a small, fixed set of choke points (enemy HP/spawn in `enemy.nim`, the damage wrapper in `player.nim`, and the 3D boss fight in `game3d/`). New damage/HP paths should route through these procs rather than reading `currentDifficulty` directly. `gdNightmare` (+50% HP and damage, speed untouched) also revokes the death-surviving block checkpoint: `difficultyAllowsContinue()` gates `saveBlockCheckpoint`/`hasBlockCheckpoint` in `run_save.nim`, which is what makes the game-over "Continue (Wave N)" option and its resume prompt disappear everywhere at once. There is one profile slot per difficulty (`MaxProfileSlots`).

### Controller input (`gamepad_input.nim`)
A leaf module (imports only raylib/math/types) re-exported through `render_context.nim`, so most modules see its wrappers for free; a few UI modules that don't import `render_context` need `import gamepad_input` directly. UI code should go through the abstraction (`isPointerPressed/Down/Released`, `getPointerWheelMove`, `isBackPressed`) rather than raw mouse/key checks, so it works with both mouse and pad. Reserved, non-rebindable buttons: A=confirm, B=back, Start=pause, sticks/dpad.

### Cosmetic skins (`skins.nim` and friends)
Player/bullet/cube/particle/desktop-background skins are registry-driven like power-ups: a `*SkinType` enum → an `array[SkinType, SkinData]` populated in an `initialize*Skins()` proc, with names/descriptions pulled via `t()` (so localization keys are required in *both* language tables). Rendering uses exhaustive `case`s (e.g. `getSkinColors`). Unlock state is persisted in `save_system.nim`. Adding one mirrors the power-up recipe: enum value → registry entry → two localization keys → render branch → save parse branch. Modules: `skins.nim` (player), `bullet_skins.nim`, `cube_skins.nim`, `particle_skins.nim`, `desktop_bg_skins.nim`.

## Adding a power-up (the main content-extension workflow)

Power-ups are registry-driven — pool membership, exclusivity group, family, color, and max level all derive from one registry entry. The recipe (documented at the top of `powerup_data.nim`):

1. Add the variant to `PowerUpType` in `types.nim`.
2. Add exactly one entry to `allPowerUpDefs` in `powerup_data.nim`.
3. Add branches to `getPowerUpName` and `getPowerUpDescription` (both exhaustive).
4. Add an icon branch to `drawPowerUpIcon` in `ui/icon_drawing.nim` (exhaustive).
5. Add name + description keys to **both** language tables in `localization.nim`.
6. Add the parse branch in `save_system.nim` (`parsePowerUpType`).
7. Implement the effect. Pickup/stat effects go in `applyPowerUp` (`powerup.nim`); per-hit effects go inline in `game.nim` (the bullet-hit resolution block models on existing power-ups like `puGiantSlayer`). Use `trackPowerUpDamage`/`showDamage` for feedback. Bosses commonly get reduced effect via `enemy.isBoss` checks and `bossWeakPointDamageMultiplier`.

The compiler (via the exhaustive cases) will refuse to build until steps 3 and 4 are done, which is the safety net for steps you forget.
