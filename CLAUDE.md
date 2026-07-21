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
nimble androidLib     # cross-compile libmain.so per ABI (needs ANDROID_NDK)
nimble android        # androidLib + gradle -> Android APK (needs SDK+JDK+gradle)
```

Verify the mobile build without a phone: `nim check --mm:orc -d:mobile src/main.nim`
(touch controls compile-check), and `nim c -r -d:mobile src/main.nim` runs it on
desktop with the mouse acting as a single touch point. See "Mobile / Android port".

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
Saves are **JSON** written with `writeFile`, with hand-written parse procs (e.g. `parsePowerUpType`). Any new serialized enum value needs a branch added to its parse proc, or it silently falls back to a default.

### Cosmetic skins (`skins.nim` and friends)
Player/bullet/cube/particle/desktop-background skins are registry-driven like power-ups: a `*SkinType` enum → an `array[SkinType, SkinData]` populated in an `initialize*Skins()` proc, with names/descriptions pulled via `t()` (so localization keys are required in *both* language tables). Rendering uses exhaustive `case`s (e.g. `getSkinColors`). Unlock state is persisted in `save_system.nim`. Adding one mirrors the power-up recipe: enum value → registry entry → two localization keys → render branch → save parse branch. Modules: `skins.nim` (player), `bullet_skins.nim`, `cube_skins.nim`, `particle_skins.nim`, `desktop_bg_skins.nim`.

### Mobile / Android port (the `mobile-test` branch)

The Android build is the **same codebase** as desktop, not a fork — so desktop
changes port to mobile automatically. Two independent compile flags:
- `-d:mobile` — enables the twin-stick touch controls + touch HUD. Runs on
  desktop too (raylib maps the mouse to touch point 0), so it's testable without
  a phone.
- `defined(android)` — auto-set by `--os:android`; guards platform specifics.

Key modules and the rule for keeping the port cheap:
- `src/input_intent.nim` is the **single seam** between input devices and
  gameplay. Gameplay asks for *intents* (`getMoveVector`, `getAimTarget`,
  `isFiring`, `abilityPressed`, `placeWallHeld/Released`, `pausePressed`). On
  desktop each returns exactly the old inline behavior; on `-d:mobile` it reads
  `src/mobile_controls.nim`. Only **three** gameplay call-sites consume it
  (player movement `player.nim`, aim/fire `game.nim`, ability/wall/pause
  `main.nim`) — keep that surface small. A new power-up/enemy/boss needs **zero**
  mobile work. Add to `input_intent` only when introducing a genuinely new
  *input action*; add a `when defined(android)` guard only for a genuinely new
  *desktop-only API* call.
- `src/mobile_controls.nim` (`when defined(mobile)`) owns all touch state: two
  floating joysticks (left move, right aim/auto-fire) + pause/ability/wall
  buttons, drawn from `main.nim`'s `gsPlaying` branch. It must never import
  game/player (would cycle through `input_intent`).
- `render_context.screenToVirtual` / `getVirtualTouchPosition` map touch (and
  mouse) through the letterbox into the virtual 1024×768 canvas.
- Platform gating: saves + synthesized-sound cache write to Android internal
  storage via `src/android_glue.c` (`getAppDataPath` in `save_system.nim`,
  `getCacheDir` in `sound.nim`). Discord and `applyWindowMode` are no-ops on
  Android. The Android C entry point (`main` → `NimMain` → game) is the
  `when defined(android)` block at the bottom of `main.nim`.
- `config.nims` locates Nimble deps by the **host** env (`OS=Windows_NT`), not
  `hostOS`/`defined(windows)` — those follow `--os` during cross-compilation.
- Build project lives in `android/` (gradle + manifest + vector icon; no Java).
  `nimble androidLib` cross-compiles `libmain.so`; `nimble android` packages a
  working `app-debug.apk` (verified). Known-good toolchain: NDK r30, JDK 21, a
  **pinned Gradle 8.7 wrapper** (`android/gradlew` — the system Gradle 9.x + JDK
  25 can't run AGP 8.5.2), AGP 8.5.2, compileSdk 34. On-device runtime is not yet
  verified. Details + gotchas in `android/README.md`.

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
