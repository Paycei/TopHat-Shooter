# Package

version       = "6.2.1"
author        = "Paycei"
description   = "TopHat-ShooterOS"
license       = "Apache 2.0"
srcDir        = "src"

# Dependencies

requires "nim >= 2.2.10"
requires "naylib >= 26.08.0"
requires "flatty >= 0.4.0"
requires "supersnappy >= 2.1.4"

task debug, "Run the game for development":
  exec "nim c -r --mm:orc -d:debug src/main.nim"

task WinRelease, "Build the game for release":
  exec "nim c --cc:vcc -d:danger --mm:orc --opt:speed --parallelBuild:0 --app:gui --panics:on --passC:\"/O2 /Oi /Ot /GS- /fp:fast /arch:AVX2 /GL /Gw /Gy /GF\" --passL:\"/link /LTCG /OPT:REF /OPT:ICF\" --passL:icono.res -o:TopHatShooterOS.exe src/main.nim"

task WinReleaseMin, "Build the game for release, optimized for size":
  exec "nim c --cc:vcc -d:danger --mm:orc --opt:size --parallelBuild:0 --app:gui --panics:on --passC:\"/O1 /Os /Oi /GS- /fp:fast /GL /Gy /Gw\" --passL:\"/link /LTCG /OPT:REF /OPT:ICF\" --passL:icono.res -o:TopHatShooterOS.exe src/main.nim"

task LinuxRelease, "Build the game for release":
  exec "nim c -d:danger --mm:orc --opt:speed --parallelBuild:0 --app:gui --panics:on --passC:\"-flto -march=native -ffast-math\" --passL:\"-flto -s\" -o:TopHatShooterOS-linux-x86_64 src/main.nim"

# ---------------------------------------------------------------------------
# Android (mobile) build. See android/README.md and CLAUDE.md.
#   nimble androidLib   -> cross-compile libmain.so into android/.../jniLibs
#   nimble android      -> androidLib + gradle assembleDebug (produces the APK)
# Prereqs: ANDROID_NDK env set; for `android` also a JDK + Android SDK + gradle.
# Override the ABI list with ANDROID_ABIS="arm64-v8a,armeabi-v7a" (default arm64).
# ---------------------------------------------------------------------------
import std/[strutils, os]  # os provides the `/` path-join used below

const AndroidApiLevel = 29

proc androidHostTag(): string =
  # NDK prebuilt toolchain host dir. Detected from the host env (see config.nims
  # for why hostOS is unreliable here).
  if getEnv("OS") == "Windows_NT" or getEnv("USERPROFILE").len > 0: "windows-x86_64"
  elif defined(macosx): "darwin-x86_64"
  else: "linux-x86_64"

proc androidNdkRoot(): string =
  result = getEnv("ANDROID_NDK")
  if result.len == 0: result = getEnv("ANDROID_NDK_HOME")
  if result.len == 0: result = getEnv("ANDROID_NDK_ROOT")

proc androidAbiInfo(abi: string): tuple[cpu, triple: string] =
  # Maps an Android ABI to the Nim --cpu and the NDK clang target triple.
  case abi
  of "arm64-v8a":   (cpu: "arm64", triple: "aarch64-linux-android")
  of "armeabi-v7a": (cpu: "arm",   triple: "armv7a-linux-androideabi")
  of "x86_64":      (cpu: "amd64", triple: "x86_64-linux-android")
  of "x86":         (cpu: "i386",  triple: "i686-linux-android")
  else:             (cpu: "arm64", triple: "aarch64-linux-android")

proc buildAndroidLibs(release: bool) =
  ## Cross-compiles libmain.so per ABI. `release` adds LTO + dead-code stripping
  ## on top of the flags the debug lib already uses (-d:danger --opt:speed).
  let ndk = androidNdkRoot()
  if ndk.len == 0:
    echo "ERROR: set ANDROID_NDK (or ANDROID_NDK_HOME / ANDROID_NDK_ROOT) to your NDK path."
    return
  let api = $AndroidApiLevel
  let abis = if getEnv("ANDROID_ABIS").len > 0: getEnv("ANDROID_ABIS").split(',')
             else: @["arm64-v8a"]
  let hostTag = androidHostTag()
  let clangSuffix = if hostTag.startsWith("windows"): ".cmd" else: ""
  let binDir = ndk / "toolchains" / "llvm" / "prebuilt" / hostTag / "bin"
  # LTO across the whole (single) translation unit set + drop unreached sections and
  # the symbol table. --strip-all is what keeps the shipped .so small; there is no
  # separate debug-symbol upload step, so nothing needs them.
  let extraFlags =
    if release:
      " --parallelBuild:0" &
      " --passC:\"-flto -ffunction-sections -fdata-sections -fomit-frame-pointer\"" &
      " --passL:\"-flto -Wl,--gc-sections -Wl,--strip-all -Wl,-O2\""
    else: ""
  for rawAbi in abis:
    let abi = rawAbi.strip()
    let info = androidAbiInfo(abi)
    let clang = binDir / (info.triple & api & "-clang" & clangSuffix)
    let outDir = thisDir() / "android" / "app" / "src" / "main" / "jniLibs" / abi
    mkDir(outDir)
    echo "[androidLib", (if release: ":release" else: ""), "] ", abi, "  cc=", clang
    exec "nim c --os:android --cpu:" & info.cpu &
      " --cc:clang --clang.exe:\"" & clang & "\" --clang.linkerexe:\"" & clang & "\"" &
      " -d:mobile -d:android -d:danger --mm:orc --opt:speed --app:lib --panics:on" &
      " -d:AndroidNdk:\"" & ndk & "\"" & extraFlags &
      " -o:\"" & (outDir / "libmain.so") & "\" src/main.nim"

proc gradleCommand(): string =
  # Prefer the pinned Gradle 8.7 wrapper (AGP 8.5.2 needs Gradle 8.7 + JDK 17-21);
  # fall back to GRADLE env or system `gradle` if the wrapper isn't present.
  let wrapper = thisDir() / "android" / (when defined(windows): "gradlew.bat" else: "gradlew")
  if fileExists(wrapper): wrapper else: getEnv("GRADLE", "gradle")

task androidLib, "Cross-compile libmain.so for each ABI (needs ANDROID_NDK)":
  buildAndroidLibs(release = false)

task androidReleaseLib, "Cross-compile an optimized, stripped libmain.so per ABI":
  buildAndroidLibs(release = true)

task android, "Build the Android APK (needs ANDROID_NDK, Android SDK, JDK, gradle)":
  buildAndroidLibs(release = false)
  withDir(thisDir() / "android"):
    exec "\"" & gradleCommand() & "\" assembleDebug"
  echo "APK -> android/app/build/outputs/apk/debug/app-debug.apk"

task androidRelease, "Build the optimized release Android APK (signed if a keystore is configured)":
  # Same codebase as `nimble android`, but the native lib gets LTO + stripping and
  # the APK is built with the `release` build type (not debuggable, zipaligned).
  # Signing: android/keystore.properties or the ANDROID_KEYSTORE* env vars; without
  # them gradle emits app-release-unsigned.apk. See android/README.md.
  buildAndroidLibs(release = true)
  withDir(thisDir() / "android"):
    exec "\"" & gradleCommand() & "\" assembleRelease"
  let outDir = thisDir() / "android" / "app" / "build" / "outputs" / "apk" / "release"
  if fileExists(outDir / "app-release.apk"):
    echo "APK -> android/app/build/outputs/apk/release/app-release.apk (signed)"
  else:
    echo "APK -> android/app/build/outputs/apk/release/app-release-unsigned.apk"
    echo "      No keystore configured; sign it with apksigner before installing."
