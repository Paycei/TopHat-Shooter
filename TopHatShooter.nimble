# Package

version       = "5.5.1"
author        = "Paycei"
description   = "TopHat-ShooterOS"
license       = "Apache 2.0"
srcDir        = "src"
bin           = @["main"]

# Dependencies

requires "nim >= 2.2.10"
requires "naylib >= 26.08.0"
requires "flatty >= 0.3.4"
requires "supersnappy >= 2.1.4"

task run, "Run the game for development":
  exec "nim c -r --mm:orc -d:debug src/main.nim"

task release, "Build the game for release":
  exec "nim c -d:danger --mm:orc --opt:speed --app:gui --passL:icono.res -o:TopHatShooterOS.exe src/main.nim"
