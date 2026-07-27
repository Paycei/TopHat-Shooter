# Android build

TopHat-ShooterOS builds for Android as a **native app**: the whole game compiles
to a shared library (`libmain.so`) that Android's `NativeActivity` loads. There
is no Java/Kotlin code. The game shares one codebase with the desktop build —
mobile behavior is gated behind `-d:mobile` (touch controls) and `-d:android`
(platform specifics), so desktop changes port automatically.

## What's here

```
android/
  settings.gradle, gradle.properties, .gitignore
  app/
    build.gradle
    src/main/
      AndroidManifest.xml        # NativeActivity, lib_name=main, landscape,
                                 #   INTERNET (PvP), no backup
      res/                        # app name + adaptive launcher icon (vector)
                                 #   values/themes.xml: GameTheme — fullscreen
                                 #   + windowLayoutInDisplayCutoutMode
      jniLibs/<abi>/libmain.so    # produced by `nimble androidLib`
      assets/                     # empty (sounds are synthesized at runtime)
```

## Prerequisites

- **Android NDK**. Point `ANDROID_NDK` (or `ANDROID_NDK_HOME` /
  `ANDROID_NDK_ROOT`) at it.
- For packaging the APK: a **JDK 17 or 21** (NOT 25 — see below), the **Android
  SDK** (via `android/local.properties` `sdk.dir` or `ANDROID_HOME`), and the
  bundled **Gradle 8.7 wrapper** (`android/gradlew`).

### Known-good toolchain (this build was verified with)

| Component | Version |
|---|---|
| NDK | 30.0.14904198 (clang target `aarch64-linux-android29`) |
| JDK | Corretto 21 (`JAVA_HOME`) |
| Gradle | 8.7 (pinned wrapper — see gotcha) |
| Android Gradle Plugin | 8.5.2 (`app/build.gradle`) |
| compileSdk / build-tools | 34 / 34.0.0 |

**Gotcha — do not use the system Gradle 9.x / JDK 25.** AGP 8.5.2 requires
Gradle 8.7 and JDK 17–21; Gradle 9.x can't run AGP 8.5.2, and JDK 25 isn't
supported by any stable AGP. This repo pins a **Gradle 8.7 wrapper** so the
system Gradle version is irrelevant — always invoke `./gradlew` (the `nimble
android` task auto-prefers it). If you regenerate the wrapper, do it in an empty
dir (with a stub `settings.gradle`) so AGP isn't evaluated by a newer Gradle.

## Build

From the repo root:

```bash
# 1) Cross-compile the native lib(s). Default ABI: arm64-v8a.
#    Override with ANDROID_ABIS="arm64-v8a,armeabi-v7a,x86_64".
nimble androidLib

# 2) Compile + package the APK (runs androidLib first, then gradle).
nimble android
# -> android/app/build/outputs/apk/debug/app-debug.apk
```

Install: `adb install -r android/app/build/outputs/apk/debug/app-debug.apk`.

## Notes / things to verify on-device

The build is **verified to produce a working APK** with the toolchain above:
`nimble androidLib` cross-compiles `libmain.so` (~4.9 MB, arm64-v8a) and the
Gradle wrapper packages it into `app-debug.apk`. What is **not** yet verified is
on-device runtime (no device was attached at build time). Sideload with
`adb install -r ...` and check:

- **Native entry point.** raylib's `android_main` calls the exported C `main`
  (see the `when defined(android)` block at the bottom of `src/main.nim`), which
  runs `NimMain()` then the game. If the app launches to a black screen, this is
  the first place to check.
- **Writable storage.** Saves and the synthesized-sound cache write to the app's
  internal-data path via `src/android_glue.c` (`getAppDataPath` in
  `save_system.nim`, `getCacheDir` in `sound.nim`). If saves/audio fail, verify
  that path resolves.
- **ABI filters.** `app/build.gradle` `abiFilters` must include every ABI you
  built a `libmain.so` for (and vice-versa).
- **Release signing.** `nimble android` builds the *debug* APK. For a release
  APK add a signing config and run `gradle assembleRelease` + `apksigner`.
- **Toolchain triple / API level.** `AndroidApiLevel = 29` in
  `TopHatShooter.nimble`; the NDK clang is `<triple><api>-clang`. Adjust if your
  NDK layout differs.

## Touch input map

| Surface | Control |
|---|---|
| Left half of the screen | floating move joystick |
| Right half | floating aim joystick; auto-fires while deflected |
| Bottom-right buttons | ability (outer), place-wall (inner, hold to preview / release to place) |
| Top-right button | pause |
| Top-left chip | back / cancel, in the fullscreen overlay states |
| Anywhere, held 1.5 s | skip a cinematic |
| Vertical drag in a list | scroll, with flick momentum |
| Tap on a text field | on-screen keyboard (QWERTY, or numeric for IP/port/FPS) |

Two modules own all of this and nothing else reads raw touch:
`src/mobile_controls.nim` (gameplay, consumed via `src/input_intent.nim`) and
`src/touch_ui.nim` (menus, consumed via the pointer wrappers in
`src/gamepad_input.nim`). See the "Mobile / Android port" section of
`CLAUDE.md`.

**Deliberately not ported:** the 3D boss fight (`gs3DBoss`, `src/game3d/`) is
still keyboard-only, and the keyboard column of the Controls rebind tab is inert
on mobile (nothing can generate a `getKeyPressed()`); the gamepad column works.

## Behaviour that is Android-specific

- **Screen stays awake** — `nimAndroidKeepScreenOn` (`src/android_glue.c`) sets
  `AWINDOW_FLAG_KEEP_SCREEN_ON`; raylib only sets the fullscreen flag. Without
  it the display sleeps mid-run, because auto-fire means long stretches with no
  touch.
- **Run checkpoints on a timer** — Android kills backgrounded NativeActivity
  processes without unwinding the frame loop, so the shutdown checkpoint at the
  bottom of `main()` never runs. `main.nim` calls `saveRunState` + `suspendGame`
  every 45 s (and opportunistically on leaving `gsPlaying`).
- **Resume is clamped** — raylib blocks the loop while backgrounded, so the
  first frame back reports the whole away-time. `main.nim` clamps that `dt` and
  forces `gsPaused` rather than fast-forwarding the simulation by minutes.
- **PvP needs `INTERNET`** — without the permission `newSocket` fails with
  `EACCES` before a single packet is sent.
- **Notch handling is a theme, not a manifest attribute** — there is no
  `android:layoutInDisplayCutoutMode` on `<activity>` (aapt rejects it);
  `windowLayoutInDisplayCutoutMode` lives in `res/values/themes.xml`
  (`@style/GameTheme`). API 27+, and minSdk is 29, so no `values-v27` split.
- **`AWINDOW_FLAG_*` needs `<android/window.h>`** — `native_activity.h` declares
  `ANativeActivity_setWindowFlags` but not the flag enum, so `android_glue.c`
  includes it explicitly.

Still unverified on-device (no device attached at build time): whether raylib's
Android backend lets `AKEYCODE_BACK` reach `isKeyPressed(KeyboardKey.Back)`. The
on-screen back chip is the guaranteed path either way; the hardware key is
wired as a bonus.
