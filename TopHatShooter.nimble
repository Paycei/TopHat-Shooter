# Package

version       = "5.5.1"
author        = "Paycei"
description   = "TopHat-ShooterOS"
license       = "Apache 2.0"
srcDir        = "src"

# Dependencies

requires "nim >= 2.2.10"
requires "naylib >= 26.08.0"
requires "flatty >= 0.3.4"
requires "supersnappy >= 2.1.4"

task debug, "Run the game for development":
  exec "nim c -r --mm:orc -d:debug src/main.nim"

task WinRelease, "Build the game for release":
  exec "nim c --cc:vcc -d:danger --mm:orc --opt:speed --parallelBuild:0 --app:gui --panics:on --passC:\"/O2 /Oi /Ot /GS- /fp:fast /arch:AVX2 /GL\" --passL:\"/link /LTCG /OPT:REF /OPT:ICF\" --passL:icono.res -o:TopHatShooterOS.exe src/main.nim"

task WinReleaseMin, "Build the game for release, optimized for size":
  exec "nim c --cc:vcc -d:danger --mm:orc --opt:size --parallelBuild:0 --app:gui --panics:on --passC:\"/O1 /Os /Oi /GS- /fp:fast /GL /Gy\" --passL:\"/link /LTCG /OPT:REF /OPT:ICF\" --passL:icono.res -o:TopHatShooterOS.exe src/main.nim"

task LinuxRelease, "Build the game for release":
  exec "nim c -d:danger --mm:orc --opt:speed --parallelBuild:0 --app:gui --panics:on -o:TopHatShooterOS src/main.nim"
