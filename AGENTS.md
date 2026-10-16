# AGENTS

## Purpose

This file documents repository conventions, common commands, and the project-specific patterns that are most useful for contributors and automation agents working on TopHat-Shooter.

## Repo Layout

- `src/main.nim`: primary entrypoint and game loop
- `TopHatShooter.nimble`: Nimble tasks for build and run targets
- `src/`: main source tree
- `android/`: the Android build project (gradle + manifest + icons, no Java); see `android/README.md`

## Quick Setup

- Install Nim and Nimble.
- On Windows, install Visual C++ Build Tools for release builds that use `--cc:vcc`.
- `config.nims` may define a project-local `nimble.paths` override for dependency locations.
- raylib and its naylib bindings come from the `vendor/naylib` git submodule ([Paycei/naylib](https://github.com/Paycei/naylib), a maintained fork of the archived upstream). Clone with `--recursive`, or run `git submodule update --init`. Read `vendor/naylib/readme.md` before editing, since part of it is generated; naylib changes are committed and pushed in the submodule first, then the new pointer is committed here.

## Common Commands

```powershell
# Install dependencies
nimble install

# Build and run a debug build
nimble debug

# Build a Windows release
nimble WinRelease

# Build a Linux release
nimble LinuxRelease

# Build the Android APK (needs ANDROID_NDK; `nimble android` also needs the SDK + JDK)
nimble androidLib        # cross-compile libmain.so only
nimble android           # + gradle -> debug APK
nimble androidRelease    # LTO + stripped lib, release APK (signed if a keystore is configured)

# Fast validation without producing a binary: all three configurations,
# since -d:mobile and defined(android) are independent and neither sees the
# other's branches
nim check --mm:orc src/main.nim
nim check --mm:orc -d:mobile src/main.nim
nim check --os:android --cpu:arm64 -d:mobile -d:android --mm:orc --app:lib `
  -d:AndroidNdk:"$env:ANDROID_NDK" src/main.nim

# Run the touch build on desktop (the mouse acts as one touch point)
nim c -r --mm:orc -d:mobile src/main.nim
```

- `nimble debug` runs the main game loop in debug mode.
- Use `nim check --mm:orc src/main.nim` as the primary correctness check after edits.
- There is no full test suite; `tests/test_spatial_grid.nim` (`nim r --mm:orc tests/test_spatial_grid.nim`) checks the enemy `SpatialGrid` in `src/enemy_helpers.nim`.
- The Windows release path links `icono.res`; do not remove it.

## Development Workflow

1. Run `nimble install` if dependencies are missing.
2. Use `nim check --mm:orc src/main.nim` after edits to catch type errors and exhaustive `case` misses quickly; if the change touches input, UI, rendering or platform code, run the `-d:mobile` and Android checks too.
3. Use `nimble debug` when you need to run the game locally.
4. Run the relevant release task only when preparing a distribution build.
5. Keep changes scoped and prefer focused diffs.

## Architecture

- `src/main.nim` owns `proc main()`, creates the window, and runs the frame loop as a state machine over `GameState`.
- `src/game.nim` is the main gameplay core: enemy AI, wave spawning, hit resolution, and most per-hit power-up effects.
- `src/types.nim` is the source of truth for the core data model and enums.
- `src/ui/` contains the OS-desktop UI layer, window modules, HUD code, icon drawing, and desktop-specific visuals.
- `src/ui/os_desktop.nim` is the simulated desktop surface where the cube and wallpaper effects live.
- `src/game3d/` contains the separate 3D boss/gameplay code paths.

## Mobile / Android

The Android build is the same codebase, not a fork. Two independent flags:
`-d:mobile` (touch controls + touch UI; runs on desktop too) and `defined(android)`
(set by `--os:android`; platform specifics such as save paths, keep-screen-on and the
C entry point). Only two modules read raw touch, and they are the seams to use:

- **Gameplay:** `src/input_intent.nim`. Gameplay asks for intents (`getMoveVector`,
  `getAimTarget`, `isFiring`, `dashPressed`, `placeWallHeld/Released`, ...). On desktop
  each returns the plain keyboard/mouse/pad read. On mobile it reads
  `src/mobile_controls.nim`, OR-ed with the same pad/keyboard read, so a paired controller
  still works.
- **Menus:** `src/touch_ui.nim`, wired into the pointer wrappers in `src/gamepad_input.nim`
  (`isPointerPressed`, `getPointerWheelMove`, `isBackPressed`, the `poll*` text-input
  shims). On touch `isPointerPressed` fires on *release*, so anything that starts a drag
  must use `isPointerDragStart` instead (and `handledPressThisFrame`, not
  `handledClickThisFrame`, inside OS windows).

A new power-up, enemy or boss needs no mobile work. A new `when defined(mobile)` branch
outside these seams is almost always the wrong fix. Add to `input_intent` only for a
genuinely new input action, and add a `when defined(android)` guard only for a new
desktop-only API call. The 3D boss fight is not ported (keyboard only). The details,
including the virtual-keyboard contracts, are in the "Mobile / Android port" section of
`CLAUDE.md`.

## Key Conventions

- All user-facing text goes through `t(key)` in `src/localization.nim`.
- English and Spanish string tables must stay in sync when adding or changing text.
- Saves are JSON in `src/save_system.nim`. Enums serialise as their Nim symbol name and parse back through the generic `parseEnumOr(s, default)`, so new enum values need no parse branch; renaming an existing value is what silently resets saved data.
- Player, bullet, cube, particle, and desktop-background skins are registry-driven.
- Skin modules follow the pattern `enum -> registry entry -> localization keys -> exhaustive render branch`.
- Exhaustive `case` statements are a safety net here; adding enum values should trigger compile-time coverage checks.
- `float32` is the pervasive numeric type across gameplay and rendering code.
- `Player`, `Enemy`, and `Bullet` are `ref object`s, so mutating a local reference mutates the shared instance.

## Useful Patterns

- For power-ups, follow the recipe in `src/powerup_data.nim` and `src/powerup.nim`: add the enum value, registry entry, render branch, localization keys, and effect implementation.
- For cosmetics, mirror the existing registry pattern used by `skins.nim`, `bullet_skins.nim`, `cube_skins.nim`, `particle_skins.nim`, and `desktop_bg_skins.nim`.
- For UI work, prefer the existing desktop/window modules instead of introducing parallel UI systems.
- For gameplay logic, check `src/game.nim` first before assuming the behavior lives elsewhere.

## Build Notes & Troubleshooting

- Windows: ensure Visual C++ Build Tools are installed for `--cc:vcc`.
- Linux: use a recent system toolchain if you see link errors.
- If a change touches enums, localization, saves, or skin registries, run `nim check --mm:orc src/main.nim` to catch missing branches early.
- If compilation or type-checking fails, inspect the Nim compiler output and fix missing imports or incompatible flags before moving on.

## Contributing

- Keep diffs focused.
- Prefer concise commit messages and PR descriptions.
- For questions or maintainership, consult repository history or open an issue.
