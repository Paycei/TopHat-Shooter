# 🎩 TopHat-ShooterOS

![Nim](https://img.shields.io/badge/Nim-FFE953?style=for-the-badge&logo=nim&logoColor=black)
![Raylib](https://img.shields.io/badge/Raylib-000000?style=for-the-badge&logo=c&logoColor=white)
![License](https://img.shields.io/badge/License-Apache_2.0-blue?style=for-the-badge&logo=apache&logoColor=white)

TopHat-ShooterOS is a fast, chaotic bullet-heaven built with Nim + Raylib.

> **You are on the `mobile-test` branch — the Android port.** It is the *same*
> codebase as desktop, not a fork: mobile behaviour is gated behind two compile
> flags (`-d:mobile` for touch controls, `-d:android` for platform specifics),
> so desktop builds are unaffected and desktop changes port over automatically.
> Everything below applies to desktop as usual; the Android-specific parts are
> in **Android build** and in [`android/README.md`](android/README.md).

---

**Features**

- Modes: Waves (wave-based) and Survival (coming soon).
- 60+ power-ups, 13 enemy types, and 12 bosses.
- Permanent upgrade shop, consumables, and deployable walls.
- Builds for Windows, Linux and Android using Nim.
- Twin-stick touch controls, touch-driven menus and an on-screen keyboard on
  Android.

**Installation & Running**

```bash
git clone https://github.com/Paycei/TopHat-Shooter.git
cd TopHat-Shooter

# Install dependencies
nimble install
```

```
# Run in debug mode
nimble debug
```

```
# Build for Windows (run from Windows)
nimble WinRelease
```

```
# Build for Linux (run from Linux)
nimble LinuxRelease
```

**AI-written project's technical wiki:**

[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/Paycei/TopHat-Shooter)

**Android build**

The game ships as a native app: the whole thing compiles to a `libmain.so` that
Android's `NativeActivity` loads. There is no Java or Kotlin code.

```bash
# Cross-compile the native lib (needs ANDROID_NDK). Default ABI: arm64-v8a,
# override with ANDROID_ABIS="arm64-v8a,armeabi-v7a,x86_64".
nimble androidLib

# Cross-compile + package the APK (needs Android SDK, JDK 17/21, gradle)
nimble android
# -> android/app/build/outputs/apk/debug/app-debug.apk

adb install -r android/app/build/outputs/apk/debug/app-debug.apk
```

Known-good toolchain: NDK r30, JDK 21, the **pinned Gradle 8.7 wrapper**
(`android/gradlew` — the system Gradle 9.x + JDK 25 cannot run AGP 8.5.2),
AGP 8.5.2, compileSdk 34, minSdk/API 29. Full prerequisites, gotchas and the
on-device checklist live in [`android/README.md`](android/README.md).

You can exercise most of the mobile build without a phone — raylib maps the
mouse to touch point 0, so this runs the touch controls, menus, virtual keyboard
and cinematic skip on desktop (but not twin-stick or multi-finger cases):

```bash
nim c -r --mm:orc -d:mobile src/main.nim
```

Because `-d:mobile` and `-d:android` are independent flags and neither sees the
other's branches, type-check **all three** configurations after editing:

```powershell
nim check --mm:orc src/main.nim                 # desktop
nim check --mm:orc -d:mobile src/main.nim       # touch controls + touch UI
nim check --os:android --cpu:arm64 -d:mobile -d:android --mm:orc --app:lib `
  -d:AndroidNdk:"$env:ANDROID_NDK" src/main.nim # Android-only branches
```

**Touch controls**

| Surface | Control |
|---|---|
| Left half of the screen | floating move joystick |
| Right half | floating aim joystick; auto-fires while deflected |
| Bottom-right buttons | ability (outer), place wall (inner — hold to preview, release to place) |
| Top-right button | pause |
| Top-left chip | back / cancel in fullscreen overlays |
| Anywhere, held 1.5 s | skip a cinematic |
| Vertical drag in a list | scroll, with flick momentum |
| Tap a text field | on-screen keyboard (QWERTY, or numeric for IP/port/FPS) |

Two leaf modules own all of this and nothing else reads raw touch:
`src/mobile_controls.nim` (gameplay, consumed as *intents* through
`src/input_intent.nim`) and `src/touch_ui.nim` (menus, wired into the pointer
wrappers in `src/gamepad_input.nim` so every existing UI call site inherits
touch behaviour). Adding a power-up, enemy or boss needs **zero** mobile work.

**Phone-specific presentation**

- The virtual canvas defaults to widescreen and is fitted to the device aspect
  (1366–1792 px wide, stepped by 32), which spends the letterbox side bars on
  wider HUD gutters instead of black.
- The gameplay world is magnified 1.25× (`MobileWorldZoom`) about the arena
  centre, with the player clamp inset to match so it can never leave view. Not
  applied in PvP: arena size is networked and both duellists must stay visible.
- The status column is scaled by a single matrix rather than per-widget font
  bumps, bounded by the real gutter width.
- The screen is kept awake, and runs are checkpointed on a 45 s timer because
  Android kills backgrounded processes without unwinding the frame loop.

**Not ported:** the 3D boss fight (`gs3DBoss`, `src/game3d/`) is keyboard-only,
and the keyboard column of the Controls rebind tab is inert on mobile (the
gamepad column works). On-device runtime is not yet fully verified — the APK
builds and packages cleanly, but no device was attached at build time.

**Contributing**

- Issues and pull requests are welcome.

**Support the project**

TopHat-ShooterOS is free and open source. If you enjoy it and want to help fund
more content, you can buy me a coffee.

[![Support on Ko-fi](https://img.shields.io/badge/Ko--fi-Support_the_project-FF5E5B?style=for-the-badge&logo=ko-fi&logoColor=white)](https://ko-fi.com/paycei)
[![Buy Me a Coffee](https://img.shields.io/badge/Buy_Me_a_Coffee-Support_the_project-FFDD00?style=for-the-badge&logo=buymeacoffee&logoColor=black)](https://buymeacoffee.com/paycei)

Support is entirely optional and never gates any feature of the game.

**License**

Apache 2.0, see LICENSE.
