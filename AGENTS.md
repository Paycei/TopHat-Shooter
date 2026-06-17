# AGENTS

## Purpose

This file documents repository conventions, common commands, and the project-specific patterns that are most useful for contributors and automation agents working on TopHat-Shooter.

## Repo Layout

- `src/main.nim`: primary entrypoint and game loop
- `TopHatShooter.nimble`: Nimble tasks for build and run targets
- `src/`: main source tree

## Quick Setup

- Install Nim and Nimble.
- On Windows, install Visual C++ Build Tools for release builds that use `--cc:vcc`.
- `config.nims` may define a project-local `nimble.paths` override for dependency locations.

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

# Fast validation without producing a binary
nim check --mm:orc src/main.nim
```

- `nimble debug` runs the main game loop in debug mode.
- Use `nim check --mm:orc src/main.nim` as the primary correctness check after edits.
- There is no dedicated test suite in this repo.
- The Windows release path links `icono.res`; do not remove it.

## Development Workflow

1. Run `nimble install` if dependencies are missing.
2. Use `nim check --mm:orc src/main.nim` after edits to catch type errors and exhaustive `case` misses quickly.
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

## Key Conventions

- All user-facing text goes through `t(key)` in `src/localization.nim`.
- English and Spanish string tables must stay in sync when adding or changing text.
- Saves are JSON in `src/save_system.nim`, with hand-written parse procs for enums and other serialised values.
- Player, bullet, cube, particle, and desktop-background skins are registry-driven.
- Skin modules follow the pattern `enum -> registry entry -> localization keys -> exhaustive render branch -> save parse branch`.
- Exhaustive `case` statements are a safety net here; adding enum values should trigger compile-time coverage checks.
- `float32` is the pervasive numeric type across gameplay and rendering code.
- `Player`, `Enemy`, and `Bullet` are `ref object`s, so mutating a local reference mutates the shared instance.

## Useful Patterns

- For power-ups, follow the recipe in `src/powerup_data.nim` and `src/powerup.nim`: add the enum value, registry entry, render branch, localization keys, save parse branch, and effect implementation.
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
