# AGENTS

## Repo Workflow

- Primary entrypoint: `src/main.nim`
- Package/tasks: `TopHatShooter.nimble`
- Main source tree: `src/`

## Commands

```powershell
nimble install
nimble debug
nimble release
```

- `nimble debug` builds and runs a debug build via `nim c -r --mm:orc -d:debug src/main.nim`.
- `nimble release` builds `TopHatShooterOS.exe` via `nim c -d:danger --mm:orc --opt:speed --app:gui --passL:icono.res -o:TopHatShooterOS.exe src/main.nim`.

## Local Setup Notes

- `nimble.paths` is loaded from `config.nims` when present, so local Nimble dependency paths may be project-specific.