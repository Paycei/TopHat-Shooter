# AGENTS

## Purpose

This file documents repository conventions, common commands, and quick guidance for contributors and automation agents working on TopHat-Shooter.

## Repo layout

- **Primary entrypoint**: `src/main.nim`
- **Nimble tasks**: `TopHatShooter.nimble` (build/run targets)
- **Main source tree**: `src/`

## Quick setup

- Prerequisites: install Nim and Nimble. On Windows, install Visual C++ Build Tools for release builds that use `--cc:vcc`.
- Optional: project-local `config.nims` may provide a `nimble.paths` override for local dependency locations.

## Common commands

```powershell
# Install dependencies
nimble install

# Build and run a debug build (cross-platform)
nimble debug

# Build a Windows release (Windows only)
nimble WinRelease

# Build a Linux release (Linux only)
nimble LinuxRelease
```

- `nimble debug` runs a debug build and executes the game (example: `nim c -r --mm:orc -d:debug src/main.nim`).
- `nimble WinRelease` produces an optimized Windows executable and links `icono.res` (Windows only).
- `nimble LinuxRelease` produces an optimized Linux executable (Linux only).

## Development workflow

1. Clone the repo and run `nimble install` to fetch dependencies.
2. Iterate using `nimble debug` (build + run) while editing `src/` files.
3. When ready, run the platform-specific release task for distribution builds.
4. Keep changes scoped; run the debug build locally before opening a PR.

## Build notes & troubleshooting

- Windows: ensure Visual C++ Build Tools (MSVC) are available for the `--cc:vcc` release path. The release task links `icono.res`—do not remove it.
- Linux: use a recent system toolchain; if you see link errors, verify `nim` and system libraries are present.
- If compilation fails after edits, run `nimble debug` and inspect compiler output; fix missing imports or incompatible Nim version flags.

## Local setup notes

- `nimble.paths` is loaded from `config.nims` when present; this can make dependency paths project-specific.

## Contributing

- Run `nimble debug` locally before submitting PRs.
- Keep diffs focused and include a concise commit message and PR description.
- For questions or maintainership, open an issue or consult the repository history to identify likely owners.
