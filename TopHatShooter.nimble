# Package

version       = "6.4.0"
author        = "Paycei"
description   = "TopHat-ShooterOS"
license       = "Apache 2.0"
srcDir        = "src"

# Dependencies

requires "nim >= 2.2.12"
requires "flatty >= 0.4.0"
requires "supersnappy >= 2.1.4"
requires "bearssl >= 0.3.0"

task debug, "Run the game for development":
  exec "nim c -r --mm:orc -d:debug -o:TopHatShooterOS-debug.exe src/main.nim"

task WinRelease, "Build the game for speed with MSVC; what nimble ship uses":
  exec "nim c --cc:vcc -d:danger --mm:orc --opt:speed --parallelBuild:0 --app:console --panics:on --nimcache:nimcache --passC:\"/O2 /Ob3 /Oi /Ot /GL /Gw /Gy /GF /GS- /fp:fast /arch:AVX /Zc:inline /FIraylib.h\" --passL:\"/link /SUBSYSTEM:WINDOWS /ENTRY:mainCRTStartup /LTCG /CGTHREADS:8 /OPT:REF /OPT:ICF /INCREMENTAL:NO\" --passL:icono.res -o:TopHatShooterOS.exe src/main.nim"

task WinReleaseClangCl, "Build the game for release using clang-cl":
  exec "nim c --cc:clang_cl --clang_cl.exe:vccexe.exe --clang_cl.linkerexe:vccexe.exe --passC:\"--platform:amd64 --command:clang-cl\" --passL:\"--platform:amd64 --command:clang-cl\" -d:danger --mm:orc --opt:speed --parallelBuild:0 --app:console --panics:on --nimcache:nimcache --passC:\"/O2 /Oi /Ot /w /GS- /fp:fast /arch:AVX -flto /Gw /Gy /GF /FIraylib.h\" --passL:\"-Wno-unknown-argument -flto opengl32.lib gdi32.lib winmm.lib user32.lib shell32.lib\" --passL:\"/link /SUBSYSTEM:WINDOWS /ENTRY:mainCRTStartup /OPT:REF /OPT:ICF /opt:lldlto=3\" --passL:icono.res -o:TopHatShooterOS-Clang-Cl.exe src/main.nim"

task WinReleaseMin, "Build the game for release, optimized for size":
  exec "nim c --cc:clang_cl --clang_cl.exe:vccexe.exe --clang_cl.linkerexe:vccexe.exe --passC:\"--platform:amd64 --command:clang-cl\" --passL:\"--platform:amd64 --command:clang-cl\" -d:danger --mm:orc --opt:size --parallelBuild:0 --app:console --panics:on --nimcache:nimcache --passC:\"/clang:-Oz /Oi /w /GS- /fp:fast -flto /Gw /Gy /GF /FIraylib.h\" --passL:\"-Wno-unknown-argument -flto opengl32.lib gdi32.lib winmm.lib user32.lib shell32.lib\" --passL:\"/link /SUBSYSTEM:WINDOWS /ENTRY:mainCRTStartup /OPT:REF /OPT:ICF\" --passL:icono.res -o:TopHat-ShooterOS-Min.exe src/main.nim"

task LinuxRelease, "Build the game for release":
  exec "nim c -d:danger --mm:orc --opt:speed --parallelBuild:0 --app:gui --panics:on --passC:\"-mavx -mtune=generic -ffast-math -fno-stack-protector -ffunction-sections -fdata-sections -flto=auto -Wno-stringop-overflow\" --passL:\"-flto=auto -Wno-stringop-overflow -Wl,--gc-sections -s\" -o:TopHatShooterOS-linux-x86_64 src/main.nim"

task modapi, "Regenerate the mod API reference (mods-sdk/API.md, tophat.d.lua) from a debug build":
  exec "nim c --mm:orc -d:debug -o:TopHatShooterOS-debug.exe src/main.nim"
  exec "\"" & thisDir() & "/TopHatShooterOS-debug.exe\" --dump-mod-api \"" & thisDir() & "/mods-sdk\""

task submodules, "Check out git submodules (vendor/naylib) at the commits the game records":
  exec "git submodule update --init --recursive"
  exec "git submodule status"

task ship, "Build installer + portable zip + Linux tarball into ship/":
  exec "pwsh -NoProfile -ExecutionPolicy Bypass -File tools/ship.ps1"
