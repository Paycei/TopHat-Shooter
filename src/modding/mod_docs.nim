## The modding reference, compiled into the game.
##
## The SDK's documents live in the repo under mods-sdk/: the guide (MODDING.md)
## and what `nimble modapi` generates from the game (API.md, tophat.d.lua,
## strings_en.json). MODS.EXE's "Modding Docs" writes them into the player's
## mods folder, always matching the build: the first three are embedded with
## staticRead (snappy-packed at compile time: plain, they were 3% of the exe),
## strings_en.json is made from the game's own English table when written.
## The game ships no mods: the example mods are in the Marketplace (the
## registry's examples/ folder, see mod_market.nim).

import std/[os, strutils, json]
import supersnappy
import mod_catalog
import ../localization

proc chunked(data: string): seq[string] {.compileTime.} =
  ## Nim emits a const string as a single C literal, and older MSVC toolsets
  ## reject literals over 16380 chars (C2026). A binary byte can take 4 chars
  ## as an octal escape, so 4000-byte pieces always fit; they are joined when
  ## written out.
  var i = 0
  while i < data.len:
    result.add(data[i ..< min(i + 4000, data.len)])
    i += 4000

template embed(file: string): seq[string] = chunked(compress(staticRead(Sdk & file)))

const
  Sdk = "../../mods-sdk/"
  ModdingDoc = embed("MODDING.md")
  ApiDoc = embed("API.md")           ## (nimble modapi writes these two from the game)
  ApiDefs = embed("tophat.d.lua")

proc embeddedModApi*(): string =
  ## The API reference this build ships (debug builds check it is current).
  uncompress(ApiDoc.join)

proc englishStringsJson*(): string =
  ## strings_en.json: every text key with its English, in the game's own order
  ## (grouped by where it shows): a translation starts as a copy of this file.
  result = "{\n"
  var first = true
  for key in TranslationKey:
    if not first: result.add(",\n")
    first = false
    result.add("  " & escapeJson($key) & ": " & escapeJson(builtinText(English, $key)))
  result.add("\n}\n")

proc installModDocs*(): bool =
  ## Write MODDING.md, API.md, tophat.d.lua and strings_en.json into the mods
  ## folder (replacing older copies); false if any could not be written.
  let root = modsRootDir()
  try:
    writeFile(root / "MODDING.md", uncompress(ModdingDoc.join))
    writeFile(root / "API.md", embeddedModApi())
    writeFile(root / "tophat.d.lua", uncompress(ApiDefs.join))   # LuaLS: autocompletion in an editor
    writeFile(root / "strings_en.json", englishStringsJson())   # the base of a translation
    true
  except IOError, OSError, SnappyError:
    false
