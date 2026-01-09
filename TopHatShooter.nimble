# Package

version       = "5.1.0"
author        = "Paycei"
description   = "TopHat-ShooterOS"
license       = "Apache 2.0"
srcDir        = "src"
bin           = @["main"]

# Dependencies

requires "nim >= 2.0.0"
requires "naylib >= 25.51.1"

task run, "Run the game for development":
  exec "nim c -r --mm:orc -d:debug src/main.nim"

task release, "Build the game for release":
  exec "nim c -d:danger --mm:orc --opt:speed --app:gui --passL:icono.res -o:TopHatShooterOS.exe src/main.nim"
