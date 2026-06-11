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
- `src/game.nim` (~9000 lines) is the monolithic gameplay core: `updateGame*` and `drawGame*` plus all combat — enemy AI, wave spawning, the bullet-vs-enemy hit resolution block, and most per-hit power-up effects. **When in doubt, gameplay logic lives here.**
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
Saves are **JSON** written with `writeFile`, with hand-written parse procs (e.g. `parsePowerUpType`). Any new serialized enum value needs a branch added to its parse proc, or it silently falls back to a default.

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
