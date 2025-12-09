# Package

version       = "3.0.0"
author        = "Paycei"
description   = "TopHat Shooter"
license       = "Apache 2.0"
srcDir        = "src"
bin           = @["main"]

# Dependencies

requires "nim >= 2.0.0"
requires "naylib >= 5.0.0"

task run, "Run the game for development":
  exec "nim c -r src/main.nim"

task build, "Build the game for release":
  exec "nim c -d:release --opt:speed --app:gui --passL:icono.res -o:TopHatShooter.exe src\main.nim"
