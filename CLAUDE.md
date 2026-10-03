# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

TopHat-ShooterOS is a bullet-heaven game written in Nim with Raylib (via the `naylib` binding, a git submodule). The whole game is themed as a desktop OS.

## Commands

```powershell
nimble install        # fetch dependencies (flatty, supersnappy; raylib + naylib are the vendor/naylib submodule)
nimble debug          # build + run -> TopHatShooterOS-debug.exe (-d:debug; always enables the cheat menu)
nimble WinRelease     # optimized MSVC build -> TopHatShooterOS.exe (Windows, needs VC++ Build Tools)
nimble WinReleaseMin  # release optimized for size
nimble LinuxRelease   # optimized Linux build
nimble androidLib     # cross-compile libmain.so per ABI (needs ANDROID_NDK)
nimble android        # androidLib + gradle -> debug APK (needs SDK+JDK+gradle)
nimble androidReleaseLib  # same, but LTO + --gc-sections + --strip-all
nimble androidRelease     # androidReleaseLib + gradle assembleRelease -> release APK
nimble ship           # all three release artifacts -> ship/ (see tools/ship.ps1)
```

`nimble ship` is the release pipeline: it runs the three build tasks above and stages
`ship/TopHatShooterOS-Installer_<ver>.exe` (WinRelease + niminst/Inno Setup),
`ship/TopHatShooterOS-PORTABLE.zip` (WinReleaseMin), `ship/TopHatShooterOS-linux-x86_64.tar.gz`
(LinuxRelease, built inside WSL) and `SHA256SUMS.txt`. It never duplicates compiler flags —
the `.nimble` tasks stay the single source of truth — and it takes the version from
`TopHatShooter.nimble`, syncing `TopHatShooter.ini` so the installer can't be stamped stale.
Everything (MSVC, niminst, Inno Setup, a WSL distro with Nim, `nim check`) is verified before
the first compile. The script takes no arguments. Note the two Windows tasks share
one output path (`TopHatShooterOS.exe`), so they can never run concurrently; the script builds
the portable one first so the *speed*-optimized exe is what's left in the repo root.

**raylib and naylib come from a git submodule**, not from Nimble: `vendor/naylib/` is
[Paycei/naylib](https://github.com/Paycei/naylib), the user's maintained fork of the archived
planetis-m/naylib, shared with their other projects. The game imports `vendor/naylib/src`;
`src/raylib/` there is the raylib C source it compiles. A naylib change is a commit *in the
submodule* (pushed to Paycei/naylib first), then a commit here that moves the pointer; never leave
the game pointing at an unpushed naylib commit. Read `vendor/naylib/readme.md` before touching it:
`raylib.nim`, `raymath.nim`, `rlgl.nim` and `rcamera.nim` are generated (edit
`tools/wrapper/config/*.cfg` or `snippets/`, then regenerate), and a raylib update follows
`vendor/naylib/manual/update_guide.md` (`update_bindings.nims`, run from that folder; needs `cc`,
`unifdef` and the eminim package). The readme's altered-source notice is what raylib's zlib license
requires for the mangled C files: any other hand edit to raylib's C goes in that list.
`config.nims` adds the path last (a later `--path` wins, so a stale naylib in
`nimble.paths` or `~/.nimble` can't shadow it) and defines `NaylibSupportGpuSkinning`, which the
mod model shader needs. Two raylib 6
rules the code relies on: a positive `thick` in the `Draw*LinesEx` family (e.g. the 5-argument
`drawRectangleRoundedLines`) strokes *inside* the shape and a negative one *outside*, so every
rounded outline here passes a negative thickness to keep the game's look; and `DrawMesh` never
uploads bone matrices (only `DrawModelEx` does), so `poseSkeleton` in `mod_assets.nim` does it.

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

**There is no real test suite** — only `tests/test_spatial_grid.nim` (`nim r --mm:orc tests/test_spatial_grid.nim`), a brute-force check that `SpatialGrid` queries never drop an in-range enemy (run it when touching the grid in `enemy_helpers.nim`/`game.nim`), and `tests/test_mod_lua.nim` (`nim r --mm:orc tests/test_mod_lua.nim`), the checks of the mod scripting runtime: sandbox, budget and memory guards, errors, natives, userdata (run it when touching `src/modding/lua_bridge.nim`). The primary correctness check is compilation:

```powershell
nim check --mm:orc src/main.nim    # fast type-check without producing a binary
```

Always run this after edits. Nim enforces **exhaustive `case` statements over enums**, so adding a value to an enum like `PowerUpType` or `EnemyType` produces a compile error at *every* exhaustive switch that doesn't handle it. `nim check` is how you find them all — do not rely on visual inspection. Note the MSVC release path links `icono.res`; do not remove it. `nim check` does **not** run the backend, so two error classes only show up in a real `nim c`: a closure capturing a `var` parameter, and copying a value whose `=copy` is an error (raylib `Texture`/`Sound`/`Music`, e.g. `for x in seqOfTextures`). After non-trivial changes, also build once (`nim c --mm:orc -d:debug -o:<scratch>/g.exe src/main.nim`).

## Architecture

### Top-level control flow
- `src/main.nim` owns `proc main()`: it creates the window, holds the single `currentGame` object, and runs the frame loop as a **state machine over `GameState`** (`gsSplash`, `gsMenu`, `gsPlaying`, `gsShop`, `gsPowerUpSelect`, `gsPvPPlaying`, …). Each state has its own update/draw branch. Switching menus/modes = reassigning `currentGame` and setting `.state`.
- `src/game.nim` is the gameplay core: `updateGame*` and `drawGame*` (plus the game-over/victory draws), the per-frame system orchestration, the spatial-grid acceleration state (`enemyGrid`, `GRID_*`), game lifecycle (`newGame*`/`setGameMode*`/`cleanupGame*`), and wave flow (`startWave*`/`advanceWave*`). **When in doubt, the top-level frame logic lives here.** It sits at the top of a dependency DAG: it `import`s the gameplay subsystem **modules** under `src/game/` and re-`export`s them, so `main.nim`'s `import game` still sees the whole gameplay API. The subsystems are real importable modules (each with its own `import`s + `*` exports), layered combat → bullets → {auras, death, bosses, orbitals, shooting}:
  - `src/game/combat.nim` — damage/crit/thorns + `showDamage`/`CombatStats` (foundation; nothing else in `game/` is below it).
  - `src/game/bullets.nim` — bullet effects, lightning, `BulletEffects`, aura/explosion radii.
  - `src/game/auras.nim` — aura config + rendering. `src/game/death.nim` — death sequence, `installPowerUp`. `src/game/shooting.nim` — `shootBullet`. `src/game/orbitals.nim` — orbital weapons. `src/game/bosses.nim` — boss AI/mechanics + `executeCustomBossAttack` (per-pattern `execBossAttack*` procs). Boss **wave** flow (`BossWaveManager` accessors + `completeBossWave`/`spawnConfiguredBoss`) lives inline in `game.nim` next to the other wave-flow procs, not in a `game/` module.
  When adding gameplay logic, put it in the matching subsystem module (and `*`-export what `game.nim`/siblings call); a subsystem must never `import game` (that's the one cycle to avoid). Only `main.nim` imports `game`.
- `src/types.nim` is the single source of truth for the data model: `Game`, `Player`, `Enemy`, `Bullet`, and every enum. `Player`/`Enemy`/`Bullet` are `ref object`s (mutating a local copy mutates the shared instance — no write-back needed). `float32` is the pervasive numeric type.

### Game modes
Selected via `GameMode`; each delegates out of `game.nim` where it diverges:
- `gmWaveBased` (default) and `gmTimeSurvival` — core PvE loop. Survival is a 20:00 run of four phases (Boot/Runtime/Overload/Kernel Panic), each closed by a boss on the survival clock (which pauses during boss fights), then optional Overtime. It has no shop: events, elites and bosses drop Data Caches instead. Everything lives in `survival.nim` (sectioned: data tables and text keys, horde spawner + formations, Data Caches, System Events, the orchestrator `game.nim` calls — `updateSurvival` and the boss/kill hooks — the cache reveal overlay, and the HUD); only the pure boss schedule (`survivalBossTime`, `survivalPhase`, `initSurvivalState`, ...) sits in `types.nim`, because `run_save.nim` needs it. Per-enemy grants are density-normalised through `densityRebate` (`survivalDensityRebate` in `types.nim`). Like the `game/` modules, `survival.nim` must never `import game`; shard payouts go through `awardMetaCurrency` in `coin.nim`.
- `gmRoguelite` (`roguelite.nim`, `dungeon.nim`, `ui/os_roguelite.nim`) — run-based meta-progression with relics, sectors, and unlockable power families (`RoguelitePowerFamily`). `dungeon.nim` owns floor/room generation and transitions; like the `game/` modules, it must not `import game` (enemy spawning stays in `game.nim`).
- `gmPvP` (`pvp_game.nim` + `network/`) — networked multiplayer. `flatty` + `supersnappy` are used **only** for PvP packet serialization, not save files. Host-authoritative: gameplay decisions (hits, kills, package grabs, match end) happen on the host and are broadcast; each has one local-feedback proc (`fxHit`/`fxKill`/`fxPickup`/...) that the host calls where it decides and clients call on receipt. flatty is layout-sensitive, so **any** change to a packet or `*Net` type in `network_types.nim` must bump `NETWORK_VERSION` (mismatched builds are then refused cleanly at connect). Every PvP packet goes out through `pvpPacket` so it carries `matchId` (the rematch generation): receivers drop older ones and a client adopts a newer one. Arena packages/ports (kinds, tuning, `portLayout`, icons) sit in their own section near the top of `pvp_game.nim`. `tickPvP` is the input-agnostic frame step (`updatePvP` = capture + `tickPvP`), which lets a harness drive host + clients over real loopback UDP headlessly.
- `gmSandbox` (`sandbox.nim`) has a button that enters the vanilla 3D boss (boss 7, Orbital Commander) via `pendingWorld3D`.
- **3D engine** (`gs3DBoss`, `game3d/`): a world is a `Game3D` ref (`types_3d.nim`, reached through the global `activeWorld3D`) holding the arena (platforms, optional `solidFloor`), player + weapon, entities, projectiles, pickups and the optional boss. All damage to the player goes through the single door `damagePlayer3D` (`game_3d.nim`); mods' spawns/removals go through the 3D action queue (`queueWorld3DAction`), drained by `processWorld3DActions` at fixed points of the frame, never inside a loop. `enterWorld3D`/`beginEnter3D` (fade in)/`leaveWorld3D` live in `game.nim`; a mod game mode with `base = "3d"` sets `ModModeDef.threeD` and starts in an empty world. Script-made content is capped (`Max*3D` in `types_3d.nim`). `game3d/` must never import `mod_api`/`mod_3d`, only `mod_hooks`.

### Enemy & boss rosters (one per mode)
Wave, Survival and Roguelite each field their **own** enemies and bosses; nothing is shared except the Omega Entity finale.
- **Enemies.** `EnemyType` is grouped: wave `etCircle..etMage` (picked by the hardcoded ladder in `spawnWaveEnemies`), survival horde `etThread..etInterrupt` (`SurvivalRoster` in `survival.nim`, unlocked on the survival clock), roguelite rooms `etFragment..etCorruptor` (`themeDef().roster` in `dungeon.nim`); `etEnvironment` stays last. The mode rosters' AI lives in `mode_enemies.nim` and their drawing in `mode_visuals.nim` (`updateEnemy`/`drawEnemy` delegate by range). Anything that creates/removes enemies or hurts the player (Fork Bomb splits, Zombie husks, Interrupt blasts, Restorer revives, Fragment slams, fork seeds, tethers, Daemon aura) is raised as an `attackPhase` request or a death hook and carried out by `game/mode_mechanics.nim`, which runs **outside** the enemy loop (`updateModeMechanics`) and is the only place that deletes enemies mid-frame.
- **Bosses** are plain int IDs (no enum, so the compiler checks none of the per-ID tables): 1-12 wave campaign (`boss_definitions.nim`), 13-15 survival phase bosses, 17-22 roguelite folder guardians (one per theme), 16/23 the Omega Entity's survival/roguelite kits (the mode-roster section of the same file). `canonicalBossId`/`isOmegaBoss` (`types.nim`) make the kits wear boss 12's body. Spawn with `spawnConfiguredBoss(..., bossId)`: a mode boss spawns at its authored slot (`bossAuthoredSlotWave`) and `normalizeBossToSlot` rescales HP/attack damage (`damageTuning`, which scales **up** too) to the slot it fights at (survival Overtime, roguelite sectors via `tuneDungeonBossStats`). Debug builds run `bossRosterProblems()` and `missingTranslations()` at startup: keep them empty.
- **Roster signature attacks** (specialData routed by `isModeBossAttack` in `executeCustomBossAttack`) are spawned in `game/mode_boss_attacks.nim` as `AttackWarning`s `awtEnemyDashLane..awtLastKnownGood`, whose geometry is a pure function of the warning in `mode_hazards.nim`, resolved by `resolveModeWarning` and drawn by `mode_visuals.nim` (hint-gated telegraph + ungated lethal pass). Every signature must add a new dodge verb; validate difficulty against stand/orbit/jitter/react bots.

### The OS-desktop UI layer (`src/ui/`)
The menus are a simulated desktop: `os_desktop.nim` (icons, taskbar, wallpaper) plus a `window_manager.nim` that opens/closes/focuses `OSWindow`s by `WindowID`. Each menu (shop, stats, settings, help, advancements, roguelite, pvp) is a window module. The in-game HUD is drawn from `drawGame`'s interface layer in `game.nim` in one of two styles, picked by `Settings.hudStyle` (Settings > Interface > HUD Style). **Modern** (`hsModern`): in 16:9 the two side bands become docks, painted by `ui/hud_dock.nim` (which also owns the shared card/header/bar primitives and the `Dock*` geometry). The left dock is the player column (`drawPlayerDock` + `drawControlsDockCard` in `ui/os_combined_hud.nim`, diagnostics stacked above the key hints). The right dock is the run column (the mode's objective card — `drawWaveDockCard` / `drawSurvivalDockCard` / `drawRogueliteDockCard` — then boss cards, transient cards, combo, [Q] abilities). 4:3 reuses the same row drawers in the floating `drawCombinedHUDPanel`. **Legacy** (`hsLegacy`): the pre-rework HUD, kept in `ui/os_legacy_hud.nim` + `drawLegacyHud` in `game.nim`, with the `docked = false` variants of the diagnostics/[Q] panels. Both styles publish the `last*Rect` row rects that the tutorial highlights. All icons are drawn programmatically in `ui/icon_drawing.nim` (no image assets) — `drawPowerUpIcon` is an exhaustive `case PowerUpType`.

### "Dopamine"/juice layer (`d_systems.nim`, `d_visuals.nim`, `d_enhancements.nim`)
Screen shake, combo system, floating damage numbers, and other game-feel feedback, kept separate from core simulation.

### Localization (`localization.nim`)
All user-facing text goes through `t(key)`. There are parallel `English` and `Spanish` string tables; lookup falls back English → raw key. Adding text means adding a `TranslationKey` enum value **and** an entry in *both* language tables.

### Persistence (`save_system.nim`)
Saves are **JSON** written with `writeFile`. Enums are serialized as their Nim symbol name (`$value`) and read back by the generic `parseEnumOr(s, default)` (`utils.nim`), which the one-line `parse*` procs in `save_system.nim` wrap — so a new enum value round-trips with **no** parse branch to add. The fallback is still silent, so the thing to preserve is the *name*: renaming an existing enum value (not adding one) is what quietly resets saved data to the default. All save I/O goes through `getAppDataPath()`, which resolves to a **per-profile** folder (`<root>/profiles/<slot>/`) — any new save file becomes per-profile automatically just by living there; `getRootDataPath()` is the shared base holding only the slot index. `switchToProfile(slot)` (`main.nim`) is the reload pattern: shared refs (`settings`, `stats`, ...) are mutated **in place**, reset to defaults first so stale keys from the old profile can't leak into the new one.

### Difficulty scaling (`types.nim`)
`GameDifficulty` (`gdEasy`/`gdMedium`/`gdHard`/`gdNightmare`) is fixed per profile at creation and read via the global `currentDifficulty`. Scaling is **not** applied ad hoc at call sites — it goes through the `difficulty*Mult()` table in `types.nim` (enemy HP, enemy damage, regular-enemy speed, spawn pace, elite chance, boss attack cooldown), each consumed at a fixed choke point listed in the comment above that table (`newEnemy`/`spawnBoss`/`makeElite` in `enemy.nim`, the damage wrapper in `player.nim`, spawn pacing in `game.nim`/`survival.nim`, the boss attack-timer reset in `game.nim`, and the 3D boss fight in `game3d/`). New damage/HP/spawn paths should route through these procs rather than reading `currentDifficulty` directly. Medium is exactly 1.0 on every lever; Easy only differs on HP/damage. The profile-picker cards in `ui/profile_select.nim` quote the numbers, so update them when retuning. `gdNightmare` (+80% HP and damage, the strongest swarm/boss multipliers) also revokes the death-surviving block checkpoint: `difficultyAllowsContinue()` gates `saveBlockCheckpoint`/`hasBlockCheckpoint` in `run_save.nim`, which is what makes the game-over "Continue (Wave N)" option and its resume prompt disappear everywhere at once. There is one profile slot per difficulty (`MaxProfileSlots`).

### Mods (`src/modding/`, MODS.EXE)
Players load Lua scripts from `<data root>/mods/<folder>/mod.json`. They run on the official **Lua 5.5**, vendored unmodified in `vendor/lua/` (MIT, see its `LICENSE`; `help licenses` shows it in game) and compiled into the exe by `lua_c.nim` (no DLL): only the core and the sandbox's libraries are kept (no io/os/package/debug). `lua_bridge.nim` is the only code that touches the C API: it gives the mod modules a small value API (`ScriptValue`, `ScriptTable`, `reg`/`checkNum`, `UdClass` userdata, `protectedCall`). Its error discipline is load-bearing: Lua raises with `longjmp`, which must never jump over a Nim frame, so Nim only makes raw, non-raising API calls, natives raise `ScriptError` and their trampoline calls `lua_error` after every Nim scope has ended, and every proc that can exit through `lua_error` is compiled with `stackTrace: off` (a jumped-over debug stack-trace frame corrupts the next Nim exception). The player-facing reference is `mods-sdk/MODDING.md`; the examples under `mods-sdk/examples/` are embedded by `mod_examples.nim` (staticRead) for MODS.EXE's Install Examples — adding an example means listing its files there, and changing one means raising its `mod.json` `version` (Install Examples only replaces an installed copy with a lower version). Layering: `mod_state` (flags, fingerprint, save-slot tag) and `mod_hooks` (hook lists, typed `mod*` call-site helpers, action queue, entity wrappers) and `mod_assets` (textures, 3D models, cosmetics) sit LOW and may be imported by gameplay modules; `mod_api`/`mod_loader` sit high and only `main.nim` imports the loader. `reloadMods` runs only from the desktop. `mod_3d.nim` is the high-layer Lua API for 3D worlds (`world3d`, `draw3d`; installed by the loader after `mod_api`); its `world3d*` hooks and wrappers live in `mod_hooks`, so `game3d/` reaches scripts only through those helpers.
- **A run started with a mod loaded is cheated unless every loaded mod opts out**: `mod.json` `disableAchievements` (boolean, default `true`; a non-boolean makes the manifest invalid) is parsed into `ModInfo.disableAchievements` (`mod_catalog.nim`), and the loader publishes `modsDisableAchievements` (`mod_state.nim`, true when any loaded mod disables achievements). `markRunModded` in `setGameMode` (plus `applySavedRun` and an `updateGame` backstop) always sets `game.modded`/`modFingerprint` (save slots, run stats) but sets `cheatsUsed` only when `modsDisableAchievements`, and never clears it (even in debug builds). Only cosmetic/HUD/app mods should set it `false`; the value is part of the fingerprint (it hashes every file byte), so saves/PvP need no extra handling. MODS.EXE tags opted-out mods KEEPS REWARDS. Modded saves carry `saveSlotTag` in their file names (`_m<fingerprint>[_<mod mode>]`), so a modded session never sees or deletes vanilla saves. PvP refuses mismatched mod fingerprints at connect.
- **Reserved enum slots**: `puMod00..puMod63` end `PowerUpType` and `etMod00..etMod31` sit just before `etEnvironment`. New built-in power-ups / enemies go **above** those blocks. Each exhaustive case has one `of puMod00..puMod63:` / `of etMod00..etMod31:` branch delegating to the mod registry; anything that *lists* power-ups or enemies must skip unbound slots (`livePowerUps()`, `isEnemyLive`). Slot names are never written to disk: saves use `powerUpSaveName`/`enemySaveName` (`"mod:<id>:<name>"`) and the matching parse procs, which drop unknown entries instead of defaulting.
- **Hooks**: gameplay code calls a typed helper from `mod_hooks` (`modWaveEnemyCount`, `modEnemyDamaged`, ...), each a no-op when nothing is registered (`hookActive`). Hooks fire inside entity loops, so scripts never add or remove entities directly: spawns/removals go through `queueModAction` and `processModActions` in `game.nim` runs them after the simulation. Never put script values (`ScriptValue`, tables, closures) on snapshotted types (`Game`, `Player`, `Enemy`, `Bullet`): per-run script state is serialized into `game.modRunData` (JSON) before either save layer writes.
- `getEnemyConfig` and `getBossDefinition` are cached per language (mods patch entries as they fill: `enemyConfigOverride`, `modBossDefs`); `vanillaEnemyConfig`/`vanillaBossDefinition` ignore mods.
- **Deep field access** (`mod_deep.nim`): scripts read and write every field reachable from `game`/`player`/enemies/bullets (nested objects, refs, seqs, arrays) through fieldPairs-built proxies that re-resolve from their root on each use, so a new field anywhere in the data model is scriptable with no code. Game/Player/Enemy/Bullet refs met on the way become the regular wrappers (keeping their rules, e.g. boss HP read-only). A new field holding **persistent** data (meta progression, profile state) must be added to `ReadOnlyRoots` (or `HiddenFields`), or a modded run could rewrite the player's real progress; tables, deques, pointers, procs and raylib resources are opaque automatically (`isOpaque`).
- **HUD pieces** are hideable by mods (`hud.hide`, `HudPart` in `mod_hooks`): a new built-in HUD element in `drawGame` gets a `hudHidden(hp...)` guard for the part it belongs to. `main.nim` calls `modOutsideRun` whenever no run is on screen (and flags PvP), so shared code that fires hooks (e.g. `newBullet` -> `bulletSpawn`) never runs scripts against a finished run; mod post-process shaders wrap the final blit in `endGameDrawing`.
- **3D models** (`assets.model` / `override.model` / `draw.model`, the models section of `mod_assets.nim`) are drawn *inside* the 2D passes, not in a 3D scene: each draw flushes the batch, keeps the current projection's x/y rows but widens its z row, and claims a fresh depth slab in front of every earlier model (`claimDepth`; a colour-masked depth-only clear when the slabs run out, `resetModelDepth` after the frame's clear in `beginGameDrawing`). So the rlgl push/translate/scale stack places a model exactly like a sprite, and draw order still layers. One built-in lit shader (`LookShader`) skins on the GPU and `poseSkeleton` uploads the bones before each draw, so every enemy gets its own pose; its inputs must keep raylib's names (`vertexBoneIndices`, `vertexBoneWeights`, `boneMatrices`) or raylib leaves them unbound and skinned models draw wrong with no error. `BodyReplace` holds a texture or a model (the model wins). The desktop cube's model is hooked at the two live-desktop cube draws in `os_desktop.nim` (the shop's preview cards stay vanilla) and at the orbital cube in `player.nim`.

### Controller input (`gamepad_input.nim`)
A leaf module (imports only raylib/math/types) re-exported through `render_context.nim`, so most modules see its wrappers for free; a few UI modules that don't import `render_context` need `import gamepad_input` directly. UI code should go through the abstraction (`isPointerPressed/Down/Released`, `getPointerWheelMove`, `isBackPressed`) rather than raw mouse/key checks, so it works with both mouse and pad. Reserved, non-rebindable buttons: A=confirm, B=back, Start=pause, sticks/dpad.

### Cosmetic skins (`skins.nim` and friends)
Player/bullet/cube/particle/desktop-background skins are registry-driven like power-ups: a `*SkinType` enum → an `array[SkinType, SkinData]` populated in an `initialize*Skins()` proc, with names/descriptions pulled via `t()` (so localization keys are required in *both* language tables). Rendering uses exhaustive `case`s (e.g. `getSkinColors`). Unlock state is persisted in `save_system.nim`. Adding one mirrors the power-up recipe: enum value → registry entry → two localization keys → render branch. Modules: `skins.nim` (player), `bullet_skins.nim`, `cube_skins.nim`, `particle_skins.nim`, `desktop_bg_skins.nim`.

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
(`getMoveVector`, `getAimTarget`, `isFiring`, `abilityPressed`, `dashPressed`,
`placeWallHeld/Pressed/Released`, `interactPressed`, `pausePressed`,
`confirmPressed`, `skipHeld`). On desktop each returns exactly the old inline
behavior; on `-d:mobile` it reads `src/mobile_controls.nim`. Consumers are
`player.nim` (movement + dash), `game.nim` (aim/fire + the wall ghost preview),
`main.nim` (ability/wall/pause), `pvp_game.nim` (all of its input),
`dungeon.nim` (`interactPressed`) and `tutorial.nim` (fire/confirm/skip) — keep
that surface small. A new
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
- OS-window content follows the same split through two per-frame flags set by
  `handleOSWindowInput`: `handledClickThisFrame` (the tap — commit buttons,
  toggles, tabs on it) and `handledPressThisFrame` (the finger-down — start
  slider/thumb drags on it). They are the same frame on desktop. Committing on
  the press flag, or on a flag set by both, fires a toggle twice per tap and
  activates whatever a scroll started on.
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
  it bigger. Two levers:
  - `MobileWorldZoom` (`types.nim`, 1.25×, mobile-only) magnifies the gameplay
    world about the arena centre, in the `WORLD PASS` matrix in `drawGame`.
    There is no camera, so an outer band of the arena is permanently off-screen;
    `mobileViewInset` (same file) insets the player clamp in `updatePlayer` by
    exactly that band so the player can never leave view. It returns 0 on
    desktop, which is what keeps both call sites behaviour-neutral there.
    The pass publishes the zoom via `render_context.setWorldZoom`, so
    `worldToVirtual`/`getWorldMousePosition` (tutorial pointers, player-centred
    bursts) agree with what was drawn. Deliberately **not** applied to
    `pvp_game`'s world pass: the arena size is networked and must not depend on
    the local interface, and both duellists have to stay visible.
  - The interface scale (`settings.uiScale`, Small/Default/Big presets in
    `save_system.nim`) — the HUD, docks and windows are drawn inside a
    `beginUIScaleMode` layer, so this grows everything uniformly. Pointer
    getters divide by the active layer's scale; `screenToVirtual` does not, and
    the touch controls/keyboard are laid out in that plain space — which is why
    `drawMobileControls` runs *outside* the HUD layer and the keyboard mask in
    `getVirtualMousePosition` is applied before the divide.
- Cinematics: `ui/cutscene.nim`'s `updateCutscene` is the single input path for
  all nine of them. On mobile it is hold-anywhere-1.5s to skip, no fast-forward.
- HUD elements that bottom-anchor into the right gutter must reserve
  `touchControlsReserve()` (`ui/hud_dock.nim`) or they draw underneath the
  on-screen dash/wall/ability buttons — see `drawLegendaryPowerUpsPanel` and the
  combo-card anchor in `game.nim`. It converts `MobileActionBarHeight` (plain
  virtual px) into the active UI layer's units and is 0 on desktop. Those three
  buttons share **one** row for exactly that reason: a second row would double
  the band and push the whole bottom HUD stack up again.
- Key hints (`drawControlsDockCard`/`drawControlsStrip`) name keyboard/pad keys,
  so on mobile only their wall-placement prompt is drawn.
- **Button state is pushed, never read.** `mobile_controls` cannot read the
  player (it sits under `input_intent`, which `player` imports), so `main.nim`
  pushes what the buttons show and gate on before each poll: `pushMobileRunState`
  in `gsPlaying` (dash cooldown, owned/ready [Q] abilities + soonest cooldown,
  wall charges, roguelite interact focus, tutorial skip fill) and the local
  player's dash/walls in `gsPvPPlaying`. A button whose action doesn't exist
  right now (no [Q] ability owned, PvP ability, a downed PvP player's dash) is
  neither drawn nor hit-tested, so its area goes back to the aim stick; one that
  exists but is cooling still *consumes* its touch, so reaching for it never
  spawns a stick under the thumb. Layout: one row, WALL / ABILITY / DASH (the
  corner, biggest); pause in the arena's top-right corner, clear of the dock.
- **Wall button = mini-stick.** Drag from it to aim the wall; with no drag it
  uses the last aim (then move) direction (`mobileAimTargetDir`, behind
  `getAimTarget`). Holding it takes the right thumb off the aim stick, and a wall
  projected along a zero aim lands on the player, which `isValidWallPlacement`
  always rejects — so without this, touch players could not place walls (nor
  finish the tutorial's wall step). The ghost previews in `drawGame`/`drawPvP`
  read `getAimTarget` too, so preview and placement always agree. Next to a
  roguelite pickup the button reads USE (it is `interactPressed` on touch).
- **Pause fires on release** of a short tap (`PauseTapMax`); a longer hold is
  `skipHeld` (the tutorial's hold-to-skip), and `confirmPressed` is a quick tap
  anywhere off the buttons, tracked per touch point so it works while the other
  thumb holds a stick. `tutorial_overlay` names the touch controls on `-d:mobile`.
- The interface scale defaults to **Big** on mobile (`DefaultUIScale` in
  `save_system.nim`); the middle preset is labelled "Normal" there, since it is
  not the default.
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
  For the same reason it passes raylib's include dir to clang explicitly when
  cross-compiling from Windows: naylib computes it with the target's path
  separator, which collapses a Windows path to `./raylib` (`raylib.h` not found).
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

1. Add the variant to `PowerUpType` in `types.nim` (above the reserved `puMod00..puMod63` block).
2. Add exactly one entry to `vanillaPowerUpDefs` in `powerup_data.nim` (read it everywhere through `powerUpDef(pt)`: mods can override entries at runtime).
3. Add branches to `getPowerUpName` and `getPowerUpDescription` (both exhaustive).
4. Add an icon branch to `drawPowerUpIcon` in `ui/icon_drawing.nim` (exhaustive).
5. Add name + description keys to **both** language tables in `localization.nim`.
6. Implement the effect. Pickup/stat effects go in `applyPowerUp` (`powerup.nim`); per-hit effects go inline in `game.nim` (the bullet-hit resolution block models on existing power-ups like `puGiantSlayer`). Use `trackPowerUpDamage`/`showDamage` for feedback. Bosses commonly get reduced effect via `enemy.isBoss` checks and `bossWeakPointDamageMultiplier`.

No save-system step is needed: persistence round-trips enum values by symbol name (see Persistence below).

The compiler (via the exhaustive cases) will refuse to build until steps 3 and 4 are done, which is the safety net for steps you forget.
