# Package

version       = "6.1.0"
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

task androidLib, "Cross-compile libmain.so for each ABI (needs ANDROID_NDK)":
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
  for rawAbi in abis:
    let abi = rawAbi.strip()
    let info = androidAbiInfo(abi)
    let clang = binDir / (info.triple & api & "-clang" & clangSuffix)
    let outDir = thisDir() / "android" / "app" / "src" / "main" / "jniLibs" / abi
    mkDir(outDir)
    echo "[androidLib] ", abi, "  cc=", clang
    exec "nim c --os:android --cpu:" & info.cpu &
      " --cc:clang --clang.exe:\"" & clang & "\" --clang.linkerexe:\"" & clang & "\"" &
      " -d:mobile -d:android -d:danger --mm:orc --opt:speed --app:lib --panics:on" &
      " -d:AndroidNdk:\"" & ndk & "\"" &
      " -o:\"" & (outDir / "libmain.so") & "\" src/main.nim"

task android, "Build the Android APK (needs ANDROID_NDK, Android SDK, JDK, gradle)":
  androidLibTask()
  # Prefer the pinned Gradle 8.7 wrapper (AGP 8.5.2 needs Gradle 8.7 + JDK 17-21);
  # fall back to GRADLE env or system `gradle` if the wrapper isn't present.
  let androidDir = thisDir() / "android"
  let wrapper = androidDir / (when defined(windows): "gradlew.bat" else: "gradlew")
  let gradleCmd = if fileExists(wrapper): wrapper
                  else: getEnv("GRADLE", "gradle")
  withDir(androidDir):
    exec "\"" & gradleCmd & "\" assembleDebug"
  echo "APK -> android/app/build/outputs/apk/debug/app-debug.apk"
