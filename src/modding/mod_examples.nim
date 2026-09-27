## The example mods and the modding reference, compiled into the game.
##
## The SDK lives in the repo under mods-sdk/ (MODDING.md + examples/). It is
## embedded with staticRead so MODS.EXE's "Install Examples" can write it into
## the player's mods folder: no installer or packaging change is needed, and
## the examples always match the build they ship with. Adding an example =
## adding its files to ExampleFiles below.

import std/[os, strutils]
import mod_catalog

const
  Sdk = "../../mods-sdk/"
  ModdingDoc = staticRead(Sdk & "MODDING.md")
  ExampleFiles: seq[tuple[path, data: string]] = @[
    ("hello_hud/mod.json", staticRead(Sdk & "examples/hello_hud/mod.json")),
    ("hello_hud/main.lua", staticRead(Sdk & "examples/hello_hud/main.lua")),
    ("glass_cannon/mod.json", staticRead(Sdk & "examples/glass_cannon/mod.json")),
    ("glass_cannon/main.lua", staticRead(Sdk & "examples/glass_cannon/main.lua")),
    ("survival_tweaks/mod.json", staticRead(Sdk & "examples/survival_tweaks/mod.json")),
    ("survival_tweaks/main.lua", staticRead(Sdk & "examples/survival_tweaks/main.lua")),
    ("bouncer/mod.json", staticRead(Sdk & "examples/bouncer/mod.json")),
    ("bouncer/main.lua", staticRead(Sdk & "examples/bouncer/main.lua")),
    ("overclock_boss/mod.json", staticRead(Sdk & "examples/overclock_boss/mod.json")),
    ("overclock_boss/main.lua", staticRead(Sdk & "examples/overclock_boss/main.lua")),
    ("neon_pack/mod.json", staticRead(Sdk & "examples/neon_pack/mod.json")),
    ("neon_pack/main.lua", staticRead(Sdk & "examples/neon_pack/main.lua")),
    ("neon_pack/wallpaper.png", staticRead(Sdk & "examples/neon_pack/wallpaper.png")),
    ("retro_crt/mod.json", staticRead(Sdk & "examples/retro_crt/mod.json")),
    ("retro_crt/main.lua", staticRead(Sdk & "examples/retro_crt/main.lua")),
    ("retro_crt/crt.fs", staticRead(Sdk & "examples/retro_crt/crt.fs")),
    ("house_rules/mod.json", staticRead(Sdk & "examples/house_rules/mod.json")),
    ("house_rules/main.lua", staticRead(Sdk & "examples/house_rules/main.lua")),
  ]

proc installExampleMods*(): bool =
  ## Write the examples and MODDING.md into the mods folder. An example whose
  ## mod.json already exists is left alone (the player may have edited it);
  ## the reference is always refreshed. False if anything failed to write.
  let root = modsRootDir()
  result = true
  try:
    writeFile(root / "MODDING.md", ModdingDoc)
  except IOError, OSError:
    result = false
  var installed: seq[string]  # example folders already present before we started
  for (path, _) in ExampleFiles:
    let folder = path.split('/')[0]
    if folder notin installed and fileExists(root / folder / "mod.json"):
      installed.add(folder)
  for (path, data) in ExampleFiles:
    if path.split('/')[0] in installed:
      continue
    let dest = root / path
    try:
      createDir(parentDir(dest))
      writeFile(dest, data)
    except IOError, OSError:
      result = false

proc exampleModIds*(): seq[string] =
  for (path, _) in ExampleFiles:
    let folder = path.split('/')[0]
    if folder notin result: result.add(folder)
