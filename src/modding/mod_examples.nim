## The example mods and the modding reference, compiled into the game.
##
## The SDK lives in the repo under mods-sdk/ (MODDING.md + examples/). It is
## embedded with staticRead so MODS.EXE's "Install Examples" can write it into
## the player's mods folder: no installer or packaging change is needed, and
## the examples always match the build they ship with. Adding an example =
## adding its files to ExampleFiles below.

import std/[os, strutils]
import mod_catalog

proc chunked(data: string): seq[string] {.compileTime.} =
  ## Nim emits a const string as a single C literal, and older MSVC toolsets
  ## reject literals over 16380 chars (C2026). A binary byte can take 4 chars
  ## as an octal escape, so 4000-byte pieces always fit; they are joined when
  ## written out.
  var i = 0
  while i < data.len:
    result.add(data[i ..< min(i + 4000, data.len)])
    i += 4000

template embed(file: string): seq[string] = chunked(staticRead(Sdk & file))

const
  Sdk = "../../mods-sdk/"
  ModdingDoc = embed("MODDING.md")
  ExampleFiles: seq[tuple[path: string, data: seq[string]]] = @[
    ("hello_hud/mod.json", embed("examples/hello_hud/mod.json")),
    ("hello_hud/main.lua", embed("examples/hello_hud/main.lua")),
    ("glass_cannon/mod.json", embed("examples/glass_cannon/mod.json")),
    ("glass_cannon/main.lua", embed("examples/glass_cannon/main.lua")),
    ("survival_tweaks/mod.json", embed("examples/survival_tweaks/mod.json")),
    ("survival_tweaks/main.lua", embed("examples/survival_tweaks/main.lua")),
    ("bouncer/mod.json", embed("examples/bouncer/mod.json")),
    ("bouncer/main.lua", embed("examples/bouncer/main.lua")),
    ("overclock_boss/mod.json", embed("examples/overclock_boss/mod.json")),
    ("overclock_boss/main.lua", embed("examples/overclock_boss/main.lua")),
    ("neon_pack/mod.json", embed("examples/neon_pack/mod.json")),
    ("neon_pack/main.lua", embed("examples/neon_pack/main.lua")),
    ("neon_pack/wallpaper.png", embed("examples/neon_pack/wallpaper.png")),
    ("neon_pack/neon_core.gif", embed("examples/neon_pack/neon_core.gif")),
    ("retro_crt/mod.json", embed("examples/retro_crt/mod.json")),
    ("retro_crt/main.lua", embed("examples/retro_crt/main.lua")),
    ("retro_crt/crt.fs", embed("examples/retro_crt/crt.fs")),
    ("house_rules/mod.json", embed("examples/house_rules/mod.json")),
    ("house_rules/main.lua", embed("examples/house_rules/main.lua")),
    ("model_pack/mod.json", embed("examples/model_pack/mod.json")),
    ("model_pack/main.lua", embed("examples/model_pack/main.lua")),
    ("model_pack/ship.glb", embed("examples/model_pack/ship.glb")),
    ("model_pack/drone.glb", embed("examples/model_pack/drone.glb")),
    ("model_pack/bolt.obj", embed("examples/model_pack/bolt.obj")),
    ("model_pack/bolt.mtl", embed("examples/model_pack/bolt.mtl")),
    ("model_pack/data_cube.vox", embed("examples/model_pack/data_cube.vox")),
  ]

proc installExampleMods*(): bool =
  ## Write the examples and MODDING.md into the mods folder. An example whose
  ## mod.json already exists is left alone (the player may have edited it);
  ## the reference is always refreshed. False if anything failed to write.
  let root = modsRootDir()
  result = true
  try:
    writeFile(root / "MODDING.md", ModdingDoc.join)
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
      writeFile(dest, data.join)
    except IOError, OSError:
      result = false

proc exampleModIds*(): seq[string] =
  for (path, _) in ExampleFiles:
    let folder = path.split('/')[0]
    if folder notin result: result.add(folder)
