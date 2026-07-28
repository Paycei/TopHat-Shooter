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
nimble android        # androidLib + gradle -> debug APK (needs SDK+JDK+gradle)
nimble androidReleaseLib  # same, but LTO + --gc-sections + --strip-all
nimble androidRelease     # androidReleaseLib + gradle assembleRelease -> release APK
```

Verify the mobile build without a phone — **all three** configurations, since
`-d:mobile` and `defined(android)` are independent flags and neither check sees
the other's branches:

```powershell
nim check --mm:orc src/main.nim                 # desktop
nim check --mm:orc -d:mobile src/main.nim       # touch controls + touch UI
nim check --os:android --cpu:arm64 -d:mobile -d:android --mm:orc --app:lib `
  -d:AndroidNdk:"$env:ANDROID_NDK" src/main.nim # Android-only branches
```

`nim c -r -d:mobile src/main.nim` runs it on desktop with the mouse acting as a
single touch point — enough to exercise the whole menu layer, the virtual
keyboard and cinematic skip, but not twin-stick or multi-finger cases. See
"Mobile / Android port".

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

### Mobile / Android port (the `mobile-test` branch)

The Android build is the **same codebase** as desktop, not a fork — so desktop
changes port to mobile automatically. Two independent compile flags:
- `-d:mobile` — enables the twin-stick touch controls + touch HUD. Runs on
  desktop too (raylib maps the mouse to touch point 0), so it's testable without
  a phone.
- `defined(android)` — auto-set by `--os:android`; guards platform specifics.

There are **two seams**, and no other module reads raw touch. Adding a
`when defined(mobile)` branch anywhere else is almost always the wrong fix —
look for the seam that already covers the case first.

**Gameplay — `src/input_intent.nim`.** Gameplay asks for *intents*
(`getMoveVector`, `getAimTarget`, `isFiring`, `abilityPressed`,
`placeWallHeld/Pressed/Released`, `interactPressed`, `pausePressed`). On desktop
each returns exactly the old inline behavior; on `-d:mobile` it reads
`src/mobile_controls.nim`. Consumers are `player.nim` (movement), `game.nim`
(aim/fire), `main.nim` (ability/wall/pause), `pvp_game.nim` (all of its input)
and `dungeon.nim` (`interactPressed`) — keep that surface small. A new
power-up/enemy/boss needs **zero** mobile work. Add to `input_intent` only when
introducing a genuinely new *input action*; add a `when defined(android)` guard
only for a genuinely new *desktop-only API* call.

**Menus — `src/touch_ui.nim`.** Drag-to-scroll with flick momentum,
tap-vs-drag disambiguation, the on-screen back chip, and the virtual keyboard.
It is wired into `src/gamepad_input.nim`'s existing wrappers, so every UI call
site inherits touch behaviour unmodified:
- `getPointerWheelMove()` += `touchWheelMove()` → every scrollable list scrolls.
- `isPointerPressed()` fires on *release*, and only if the finger didn't travel.
  **Anything that starts a drag must use `isPointerDragStart()` instead** (window
  title bars, the desktop cube, scrollbar thumbs, the HUD panel) — the release
  edge is far too late to grab something.
- `isBackPressed()` picks up the back chip; `pollCharPressed` /
  `pollBackspacePressed` / `pollEnterPressed` / `setTextInputActive` /
  `setTextInputPreview` bridge text fields to the virtual keyboard (no-ops on
  desktop).

The **virtual keyboard** has four contracts that are easy to break by accident:
- `setTextInputActive(true, …)` **latches for the frame** — `false` never clears
  another window's `true`, and first caller wins. Every visible window is
  updated each frame and more than one calls it unconditionally, so plain
  assignment let a window that ran later in the loop veto the focused field's
  request. Hiding the panel is done by *not calling it*, which the per-frame
  reset in `updateTouchUI` handles.
- `getVirtualMousePosition()` **masks a pointer parked on the panel**, reporting
  the last position outside it (`touchKeyboardMaskPointer`). The menu layer
  decides topmost/hover/click ownership from the pointer *position*
  (`isWindowTopmostAtPoint`), and on touch the pointer is the last finger — so
  unmasked, the first keystroke moved the pointer off the window, its input
  block stopped running, and the keyboard vanished mid-word. Any new
  keyboard-adjacent overlay must extend `vkOverlayTop` the same way.
- Keys fire **per touch point** (`vkUpdateTouchKeys`), not off the emulated
  mouse: Android keeps `MOUSE_LEFT` down while *any* finger is down, so a second
  thumb produces no mouse press edge and its keystroke would be lost. Desktop
  GLFW never fills the touch array (`getTouchPointCount()` stays 0), which is
  what makes the mouse fallback the right path there — don't "simplify" it away.
- `isPointerDragStart/Down/Released` are suppressed for keyboard-owned gestures
  (`touchKeyboardOwnsPointer`). A text field must never move its caret on a bare
  release edge — the `pvp_window` caret bug ("types backwards") was exactly that:
  a release with a collapsed selection assigning `cursorPos = -1`.
- DONE latches the panel closed while the field keeps focus, so the reopen chip
  (top-right, mirroring the back chip) is the only way back; without it that
  state is unrecoverable.

Both touch modules are leaves. `touch_ui` must **not** import `render_context`
(`render_context` → `gamepad_input` → `touch_ui` would cycle); it receives the
letterbox transform via `setTouchViewport`, pushed from
`updateRenderInputTransform`. `mobile_controls` must never import game/player
(would cycle through `input_intent`). Both draw with plain raylib calls in
virtual coordinates, since the draw pass is already in virtual space.

`main.nim` drives them: `updateMobileControls` in the `gsPlaying`/`gsPvPPlaying`
branches (with `resetMobileControls` on the way out, so nothing stays latched),
and `updateTouchUI` once per frame before the state machine. The touch back chip
and the keyboard are drawn from `drawCustomCursor`, which is repurposed on mobile
— it is the one hook every state's draw branch already calls, and it runs last.
Other pieces:
- `render_context.screenToVirtual` maps touch (and mouse) through the letterbox
  into the virtual canvas (1024×768 classic, 1366×768 widescreen — mobile
  defaults to widescreen, see `settings.nim`). On mobile the widescreen width is
  not fixed: `main.mobileVirtualWidth` fits it to the device aspect (1366–1792,
  stepped by 32). This is free, because `updateRenderScale` takes
  `min(w/vw, h/vh)` and a phone in landscape always makes the **height** term
  win — widening the canvas only reclaims the black side bars and spends them on
  wider HUD gutters.
- **Phone legibility** — the game was laid out for a monitor, and the letterbox
  scale is pinned by the 768-tall canvas, so nothing about the *layout* can make
  it bigger. Two levers, both mobile-only:
  - `MobileWorldZoom` (`types.nim`, 1.25×) magnifies the gameplay world about
    the arena centre, in the `WORLD PASS` matrix in `drawGame`. There is no
    camera, so an outer band of the arena is permanently off-screen;
    `mobileViewInset` (same file) insets the player clamp in `updatePlayer` by
    exactly that band so the player can never leave view. It returns 0 on
    desktop, which is what keeps both call sites behaviour-neutral there.
    Deliberately **not** applied to `pvp_game`'s world pass: the arena size is
    networked and must not depend on the local interface, and both duellists
    have to stay visible.
  - `drawBorderHUDPanel` (`ui/os_combined_hud.nim`) magnifies the whole status
    column with one matrix rather than per-widget font bumps — its ~50 draws are
    hand-positioned against `BORDER_PANEL_WIDTH`, so scaling uniformly is the
    only way a label can't drift from its bar. The factor is bounded by the real
    gutter width *and* by the column height reported back from
    `drawHUDPanelContent`.
- Cinematics: `ui/cutscene.nim`'s `updateCutscene` is the single input path for
  all nine of them. On mobile it is hold-anywhere-1.5s to skip, no fast-forward.
- HUD elements that bottom-anchor into the right gutter must reserve
  `MobileActionBarHeight` (`mobile_controls.nim`) or they draw underneath the
  on-screen ability/wall buttons — see `drawLegendaryPowerUpsPanel` and
  `legendaryReserve` in `game.nim`.
- Platform gating: saves + synthesized-sound cache write to Android internal
  storage via `src/android_glue.c` (`getAppDataPath` in `save_system.nim`,
  `getCacheDir` in `sound.nim`); the same shim provides `nimAndroidKeepScreenOn`.
  Discord, `applyWindowMode`, `hideCursor`, mouse bonding and the live
  HUD-layout window resize are all no-ops/guarded on Android. `main.nim`
  checkpoints the run on a timer (Android kills backgrounded processes without
  unwinding the loop) and clamps the resume `dt` spike into `gsPaused`. The
  Android C entry point (`main` → `NimMain` → game) is the
  `when defined(android)` block at the bottom of `main.nim`.
- **Not ported:** the 3D boss fight (`gs3DBoss`, `game3d/`) is keyboard-only.
- `config.nims` locates Nimble deps by the **host** env (`OS=Windows_NT`), not
  `hostOS`/`defined(windows)` — those follow `--os` during cross-compilation.
- Build project lives in `android/` (gradle + manifest + vector icon; no Java).
  `nimble androidLib` cross-compiles `libmain.so`; `nimble android` packages a
  working `app-debug.apk` (verified). Known-good toolchain: NDK r30, JDK 21, a
  **pinned Gradle 8.7 wrapper** (`android/gradlew` — the system Gradle 9.x + JDK
  25 can't run AGP 8.5.2), AGP 8.5.2, compileSdk 34. On-device runtime is not yet
  verified. `nimble androidRelease` adds LTO/stripping to the lib and the
  `release` build type; it signs the APK only if `android/keystore.properties`
  (or the `ANDROID_KEYSTORE*` env vars) exists, otherwise it emits
  `app-release-unsigned.apk`. Details + gotchas in `android/README.md`.

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
