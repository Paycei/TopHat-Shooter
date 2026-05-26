# AGENTS

## Repo Workflow

- Primary entrypoint: `src/main.nim`
- Package/tasks: `TopHatShooter.nimble`
- Main source tree: `src/`

## Commands

```powershell
nimble install
nimble debug
nimble WinRelease
nimble LinuxRelease
```

- `nimble debug` builds and runs a debug build via `nim c -r --mm:orc -d:debug src/main.nim`.
- `nimble winrelease` builds `TopHatShooterOS.exe` via `nim c --cc:vcc -d:danger --mm:orc --opt:speed --parallelBuild:0 --app:gui --panics:on --passC:\"/O2 /Oi /Ot /GS- /fp:fast /arch:AVX2 /GL\" --passL:\"/link /LTCG /OPT:REF /OPT:ICF\" --passL:icono.res -o:TopHatShooterOS.exe src/main.nim`.

## Local Setup Notes

- `nimble.paths` is loaded from `config.nims` when present, so local Nimble dependency paths may be project-specific.