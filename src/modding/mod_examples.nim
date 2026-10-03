## The example mods and the modding reference, compiled into the game.
##
## The SDK lives in the repo under mods-sdk/ (MODDING.md + examples/). It is
## embedded with staticRead so MODS.EXE's "Install Examples" can write it into
## the player's mods folder: no installer or packaging change is needed, and
## the examples always match the build they ship with. Adding an example =
## adding its files to ExampleFiles below. Changing an example = raising the
## "version" in its mod.json: Install Examples only replaces an installed copy
## whose version is lower, so an unbumped change never reaches old installs.

import std/[os, strutils, json]
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
    ("arena_3d/mod.json", embed("examples/arena_3d/mod.json")),
    ("arena_3d/main.lua", embed("examples/arena_3d/main.lua")),
    ("orbital_tweaks/mod.json", embed("examples/orbital_tweaks/mod.json")),
    ("orbital_tweaks/main.lua", embed("examples/orbital_tweaks/main.lua")),
    ("keybind_demo/mod.json", embed("examples/keybind_demo/mod.json")),
    ("keybind_demo/main.lua", embed("examples/keybind_demo/main.lua")),
    ("media_player/mod.json", embed("examples/media_player/mod.json")),
    ("media_player/main.lua", embed("examples/media_player/main.lua")),
    ("media_player/playlist.json", embed("examples/media_player/playlist.json")),
    ("media_player/clip.mpg", embed("examples/media_player/clip.mpg")),
    ("media_player/icon.mpg", embed("examples/media_player/icon.mpg")),
    ("media_player/music.ogg", embed("examples/media_player/music.ogg")),
    ("media_player/lcd.bdf", embed("examples/media_player/lcd.bdf")),
    ("billboard_plaza/mod.json", embed("examples/billboard_plaza/mod.json")),
    ("billboard_plaza/main.lua", embed("examples/billboard_plaza/main.lua")),
    ("billboard_plaza/test_card.mpg", embed("examples/billboard_plaza/test_card.mpg")),
    ("billboard_plaza/plasma.mpg", embed("examples/billboard_plaza/plasma.mpg")),
    ("billboard_plaza/poster.png", embed("examples/billboard_plaza/poster.png")),
    ("billboard_plaza/decal.png", embed("examples/billboard_plaza/decal.png")),
    ("billboard_plaza/orb.png", embed("examples/billboard_plaza/orb.png")),
    ("billboard_plaza/online.gif", embed("examples/billboard_plaza/online.gif")),
    ("billboard_plaza/drone.gif", embed("examples/billboard_plaza/drone.gif")),
  ]

proc exampleModIds*(): seq[string] =
  for (path, _) in ExampleFiles:
    let folder = path.split('/')[0]
    if folder notin result: result.add(folder)

proc versionParts(v: string): seq[int] =
  ## "1.2.10" -> @[1, 2, 10]; a part that is not a number counts as 0.
  for part in v.strip.split('.'):
    var n = 0
    for c in part:
      if c notin Digits: break
      n = n * 10 + (ord(c) - ord('0'))
    result.add(n)

proc newerVersion(a, b: string): bool =
  ## True if version `a` is higher than `b` (missing parts count as 0).
  let pa = versionParts(a)
  let pb = versionParts(b)
  for i in 0 ..< max(pa.len, pb.len):
    let x = if i < pa.len: pa[i] else: 0
    let y = if i < pb.len: pb[i] else: 0
    if x != y: return x > y
  false

proc manifestVersion(text: string): string =
  ## The "version" of a mod.json, with the catalog's default; "" if the file
  ## can't be parsed.
  try:
    let j = parseJson(text)
    if j.kind != JObject: return ""
    j.getOrDefault("version").getStr("1.0.0")
  except CatchableError:
    ""

proc exampleNeedsWrite(root, folder: string): bool =
  ## Install an example that is missing, and replace one whose installed
  ## version is lower than the build's (or whose mod.json can't be read).
  ## The same or a higher version is left alone, so edits survive until the
  ## example itself changes.
  let installed = root / folder / "mod.json"
  if not fileExists(installed): return true
  var shipped = ""
  for (path, data) in ExampleFiles:
    if path == folder & "/mod.json": shipped = manifestVersion(data.join)
  let current =
    try: manifestVersion(readFile(installed))
    except IOError, OSError: ""
  current.len == 0 or newerVersion(shipped, current)

proc installExampleMods*(): tuple[ok: bool, written: int] =
  ## Write MODDING.md (always refreshed) and every example that is missing or
  ## older than the one this build ships (see exampleNeedsWrite). A replaced
  ## example's folder is wiped first, so a file an older version shipped
  ## can't linger next to the new one. `written` counts the examples written;
  ## `ok` is false if anything failed.
  let root = modsRootDir()
  result.ok = true
  try:
    writeFile(root / "MODDING.md", ModdingDoc.join)
  except IOError, OSError:
    result.ok = false
  var toWrite: seq[string]
  for folder in exampleModIds():
    if exampleNeedsWrite(root, folder):
      toWrite.add(folder)
      try:
        removeDir(root / folder)
      except IOError, OSError:
        result.ok = false
  result.written = toWrite.len
  for (path, data) in ExampleFiles:
    if path.split('/')[0] notin toWrite:
      continue
    let dest = root / path
    try:
      createDir(parentDir(dest))
      writeFile(dest, data.join)
    except IOError, OSError:
      result.ok = false
