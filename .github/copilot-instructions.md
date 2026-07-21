# Copilot instructions for TopHat-ShooterOS

This document provides targeted guidance for Copilot-style assistants working in this repository. Keep it short and actionable.

## Quick build & run

- Install dependencies: nimble install
- Run debug (build + run): nimble debug
- Windows release: nimble WinRelease
- Windows release (size-optimized): nimble WinReleaseMin
- Linux release: nimble LinuxRelease
- Fast compile/type-check (no binary): nim check --mm:orc src/main.nim

Run a single standalone test (there is a small test file):
- nim r --mm:orc tests/test_spatial_grid.nim

Notes:
- Nim/Nimble required (nim >= 2.2.10).
- On Windows release builds require Visual C++ Build Tools (MSVC).
- config.nims and nimble.paths control per-machine dependency paths; read config.nims when dependencies fail.

## High-level architecture

- Entry point: src/main.nim — creates window, holds `currentGame`, runs frame loop as a state machine over `GameState`.
- Core gameplay: src/game.nim — monolithic gameplay core (enemy AI, wave spawning, hit resolution, per-hit power-up effects). When unsure, inspect game.nim.
- Data model: src/types.nim — single source of truth for `Game`, `Player`, `Enemy`, `Bullet` and all enums. `Player`/`Enemy`/`Bullet` are `ref object`s; mutating a local ref mutates the shared instance.
- UI layer: src/ui/ — simulated desktop UI, window modules, HUD, and icon drawing (icons are programmatic; no image assets).
- Roguelite, PvP, 3D: special modes in roguelite.nim, pvp_game.nim + network/, and game3d/ respectively.
- Save format: JSON via src/save_system.nim with hand-written parse procs.
- Dopamine/visuals: d_systems.nim, d_visuals.nim, d_enhancements.nim (game-feel separated from core sim).

## Key repository conventions (important for automated edits)

- Exhaustive case switches: Many enums use exhaustive `case` statements. Adding enum values requires updating every exhaustive switch (compiler enforces this). Use `nim check --mm:orc src/main.nim` to find missed branches.
- Power-up & skin recipe:
  1. Add enum in src/types.nim
  2. Add registry entry in src/powerup_data.nim or the relevant skins module
  3. Add localization entries (both English & Spanish) in src/localization.nim
  4. Add render/icon branch in src/ui/icon_drawing.nim (or skin render branch)
  5. Add parse branch in src/save_system.nim
  6. Implement behaviour in src/powerup.nim or src/game.nim (per-hit effects often live in game.nim)

- Localization: All user-facing strings go through t(key) in src/localization.nim. Keep English and Spanish tables in sync.
- Numeric types: float32 is used throughout gameplay and rendering — prefer float32 for new numeric fields/ops.
- Ref objects: Player/Enemy/Bullet are `ref object`s — modifying a local ref mutates the shared model.
- Registry pattern: Skins, power-ups, and cosmetics follow `enum -> registry entry -> localization keys -> exhaustive render branch -> save parse branch`.
- Build paths: Windows release links icono.res; do not remove it from passL flags.
- Dependency discovery: config.nims contains logic for locating highest installed versions of naylib/flatty/supersnappy on Windows; automated tools should respect it.

## Tests & shortcuts

- There is no full test suite; rely on `nim check` and the included tests/test_spatial_grid.nim when changing spatial/grid logic.
- To run the spatial grid test: nim r --mm:orc tests/test_spatial_grid.nim

## Files used by AI assistants

- CLAUDE.md and AGENTS.md contain the same key conventions and build commands; merge relevant content into suggestions.
- If updating doc snippets or automated code transformations, prefer following the recipes described in powerup_data.nim, skins.nim, and localization.nim.

## When making automated changes

- Keep diffs minimal and focused. Do not reorder unrelated enums or change whitespace-only formatting across many files.
- After edits that touch enums/localization/saves/skins, run: nim check --mm:orc src/main.nim to catch missing exhaustive cases.
- For content additions (power-ups, skins), follow the enumerated recipe in AGENTS.md / CLAUDE.md for all required touchpoints.

## Commit metadata

- The repository's automated commit trailer is expected for machine-made commits; check project CONTRIBUTING/AGENTS docs for policies.

---
