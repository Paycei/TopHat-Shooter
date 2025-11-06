# Package

version       = "1.0.0"
author        = "Paycei"
description   = "TopHat Shooter"
license       = "MIT"
srcDir        = "src"
bin           = @["main"]

# Dependencies

requires "nim >= 2.0.0"
requires "naylib >= 5.0.0"

task run, "Run the game":
  exec "nim c -r src/main.nim"

task build, "Build the game":
  exec "nim c -d:release --opt:speed src/main.nim"
