## The modding reference, compiled into the game.
##
## The SDK's documents live in the repo under mods-sdk/: the guide (MODDING.md)
## and what `nimble modapi` generates from the game (API.md, tophat.d.lua,
## strings_en.json). They are embedded with staticRead so MODS.EXE's "Modding
## Docs" can write them into the player's mods folder, always matching the
## build. The game ships no mods: the example mods are in the Marketplace
## (the registry's examples/ folder, see mod_market.nim).

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
  ApiDoc = embed("API.md")           ## (nimble modapi writes these three from the game)
  ApiDefs = embed("tophat.d.lua")
  EnglishStrings = embed("strings_en.json")

proc embeddedModApi*(): string =
  ## The API reference this build ships (debug builds check it is current).
  ApiDoc.join

proc installModDocs*(): bool =
  ## Write MODDING.md, API.md, tophat.d.lua and strings_en.json into the mods
  ## folder (replacing older copies); false if any could not be written.
  let root = modsRootDir()
  try:
    writeFile(root / "MODDING.md", ModdingDoc.join)
    writeFile(root / "API.md", ApiDoc.join)
    writeFile(root / "tophat.d.lua", ApiDefs.join)   # LuaLS: autocompletion in an editor
    writeFile(root / "strings_en.json", EnglishStrings.join)   # the base of a translation
    true
  except IOError, OSError:
    false
