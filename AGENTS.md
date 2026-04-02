# AGENTS

## Repo Workflow

- Primary entrypoint: `src/main.nim`
- Package/tasks: `TopHatShooter.nimble`
- Main source tree: `src/`

## Commands

```powershell
nimble install
nimble run
nimble release
```

- `nimble run` builds and runs a debug build via `nim c -r --mm:orc -d:debug src/main.nim`.
- `nimble release` builds `TopHatShooterOS.exe` via `nim c -d:danger --mm:orc --opt:speed --app:gui --passL:icono.res -o:TopHatShooterOS.exe src/main.nim`.

## Local Setup Notes

- If `src/discord_config.nim` is missing locally, create it from `src/discord_config.nim.example`. The real file is gitignored because it contains a sensitive Discord App ID.
- `nimble.paths` is loaded from `config.nims` when present, so local Nimble dependency paths may be project-specific.