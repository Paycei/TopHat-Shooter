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
    ("necromancer/mod.json", embed("examples/necromancer/mod.json")),
    ("necromancer/main.lua", embed("examples/necromancer/main.lua")),
    ("story_mode/mod.json", embed("examples/story_mode/mod.json")),
    ("story_mode/main.lua", embed("examples/story_mode/main.lua")),
    ("story_mode/kernel.png", embed("examples/story_mode/kernel.png")),
    ("chaos_engine/mod.json", embed("examples/chaos_engine/mod.json")),
    ("chaos_engine/main.lua", embed("examples/chaos_engine/main.lua")),
    ("content_pack/mod.json", embed("examples/content_pack/mod.json")),
    ("content_pack/content/powerups.json", embed("examples/content_pack/content/powerups.json")),
    ("content_pack/content/enemies.json", embed("examples/content_pack/content/enemies.json")),
    ("content_pack/content/shop.json", embed("examples/content_pack/content/shop.json")),
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

proc exampleUpdates*(): seq[tuple[folder, installed, shipped: string]] =
  ## The installed examples this build ships a newer version of: what Install
  ## Examples would replace. A missing example isn't an update, and neither is
  ## an unreadable mod.json (the catalog already shows that one as invalid).
  let root = modsRootDir()
  for folder in exampleModIds():
    let installed = root / folder / "mod.json"
    if not fileExists(installed): continue
    let current =
      try: manifestVersion(readFile(installed))
      except IOError, OSError: ""
    if current.len == 0: continue
    var shipped = ""
    for (path, data) in ExampleFiles:
      if path == folder & "/mod.json": shipped = manifestVersion(data.join)
    if newerVersion(shipped, current):
      result.add((folder, current, shipped))

proc wipeExample(root, folder: string): bool =
  ## Empty an installed example's folder before its new version is written, so
  ## a file an older version shipped can't linger. A file the loaded mod holds
  ## open (a video streams from its file) can't be deleted on Windows until the
  ## mods reload: that is fine when the new version writes over it, so only a
  ## file left behind that it doesn't ship makes this false.
  let dir = root / folder
  if not dirExists(dir): return true
  result = true
  for f in walkDirRec(dir):
    try:
      removeFile(f)
    except IOError, OSError:
      let path = folder & "/" & relativePath(f, dir).replace('\\', '/')
      var shipped = false
      for (p, _) in ExampleFiles:
        if p == path: shipped = true
      if not shipped: result = false
  try:
    removeDir(dir)   # the emptied folders; one holding a locked file stays
  except IOError, OSError:
    discard

proc installExampleMods*(): tuple[ok: bool, written: seq[string]] =
  ## Write MODDING.md (always refreshed) and every example that is missing or
  ## older than the one this build ships (see exampleNeedsWrite). A replaced
  ## example's folder is wiped first (see wipeExample), so a file an older
  ## version shipped can't linger next to the new one. `written` lists the
  ## folders of the examples written; `ok` is false if anything failed.
  let root = modsRootDir()
  result.ok = true
  try:
    writeFile(root / "MODDING.md", ModdingDoc.join)
  except IOError, OSError:
    result.ok = false
  for folder in exampleModIds():
    if exampleNeedsWrite(root, folder):
      result.written.add(folder)
      if not wipeExample(root, folder):
        result.ok = false
  for (path, data) in ExampleFiles:
    if path.split('/')[0] notin result.written:
      continue
    let dest = root / path
    try:
      createDir(parentDir(dest))
      writeFile(dest, data.join)
    except IOError, OSError:
      result.ok = false
