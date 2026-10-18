## The generated mod API reference: mods-sdk/API.md (every library function,
## hook, game proc, raylib function and engine global, with what the source
## says about each), mods-sdk/tophat.d.lua (the same as LuaLS annotations,
## for autocompletion in an editor) and mods-sdk/strings_en.json (every text
## key of the game with its English, for translators: register.language).
##
## Both come from the running VM, so they list what this build really has:
## the library tables are walked, their functions' docs are the `##` lines
## under each native's `.reg("name")` in the modding sources (read at compile
## time), the hooks are ModHook's values with their comments, and the game's
## procs are the mixin slots the binders made. `nimble modapi` (a debug build's
## --dump-mod-api) writes them; mod_examples embeds them for Install Examples,
## and a debug build warns at startup when the embedded copy is out of date.

import std/[strutils, tables, algorithm, os, json]
import lua_bridge, mod_hooks, mod_mixin, mod_deep
import ../utils, ../localization

# ------------------------------------------------- docs from the source ----
const DocSources = ["mod_api.nim", "mod_ui.nim", "mod_3d.nim", "mod_world2d.nim",
                    "mod_content_api.nim", "mod_engine.nim", "mod_pvp.nim", "mod_mixin.nim",
                    "mod_rl.nim", "mod_theme.nim"]

proc leadingPath(s: string): string {.compileTime.} =
  ## "screens.go(id, ...): ..." -> "screens.go" (a dotted name a doc opens with).
  var i = 0
  while i < s.len and s[i] in IdentChars + {'.', ':'}: inc i
  result = s[0 ..< i].strip(leading = false, chars = {'.', ':'})
  if '.' notin result and ':' notin result: result = ""

proc scanNativeDocs(): seq[tuple[key, doc: string]] {.compileTime.} =
  ## For each native with a doc: "<table var>.<name>" and, when its doc opens
  ## with the call ("screens.go(...)"), "@<that path>" too.
  for f in DocSources:
    let lines = staticRead(f).splitLines()
    for i, line in lines:
      let at = line.find(".reg(\"")
      if at <= 0: continue
      var v = at - 1
      while v >= 0 and line[v] in IdentChars: dec v
      let nameEnd = line.find('"', at + 6)
      if nameEnd < 0: continue
      let key = line[v + 1 ..< at] & "." & line[at + 6 ..< nameEnd]
      var doc: seq[string]
      var j = i + 1
      while j < lines.len and lines[j].strip.startsWith("##"):
        doc.add(lines[j].strip[2 .. ^1].strip)
        inc j
      if doc.len == 0: continue
      let text = doc.join(" ")
      result.add((key, text))
      let p = leadingPath(doc[0])
      if p.len > 0: result.add(("@" & p, text))

proc scanHookDocs(): seq[tuple[name, doc, group: string]] {.compileTime.} =
  ## ModHook's values with their trailing comments, under their section's name.
  var inEnum, afterHook = false
  var group = ""
  for line in staticRead("mod_hooks.nim").splitLines():
    let s = line.strip
    if s.startsWith("ModHook* = enum"):
      inEnum = true
      afterHook = true
      continue
    if not inEnum or s.len == 0: continue
    if s.startsWith("#"):
      if afterHook:   # the first line of a section comment names it
        var g = s[1 .. ^1].strip
        for cut in [" (", ":"]:
          let k = g.find(cut)
          if k > 0: g = g[0 ..< k]
        group = g
      afterHook = false
      continue
    if not s.startsWith("hk"): break   # past the enum
    afterHook = true
    let q1 = s.find('"')
    let q2 = s.find('"', q1 + 1)
    if q1 < 0 or q2 < 0: continue
    let d = s.find("##")
    let doc = if d >= 0: s[d + 2 .. ^1].splitWhitespace.join(" ") else: ""
    result.add((s[q1 + 1 ..< q2], doc, group))

const
  NativeDocs = scanNativeDocs()
  HookDocs = scanHookDocs()
  LuaStdlib = ["_G", "_VERSION", "assert", "collectgarbage", "coroutine", "debug", "dofile",
               "error", "getmetatable", "io", "ipairs", "load", "loadfile", "math", "next", "os",
               "package", "pairs", "pcall", "print", "rawequal", "rawget", "rawlen", "rawset",
               "require", "select", "setmetatable", "string", "table", "tonumber", "tostring",
               "type", "utf8", "warn", "xpcall"]
  LuaKeywords = ["and", "break", "do", "else", "elseif", "end", "false", "for", "function",
                 "goto", "if", "in", "local", "nil", "not", "or", "repeat", "return", "then",
                 "true", "until", "while"]
  ModdableFirst = ["mixin.wrap", "mixin.before", "mixin.after", "mixin.replace",
                   "mixin.signature", "mixin.has"]

# ------------------------------------------------------------ the model ----
type
  ApiFn = tuple[path, doc: string]
  ApiLib = object
    path: string
    fns: seq[ApiFn]
    values: seq[tuple[name, kind: string]]
  ApiProc = tuple[name, signature, note: string, moddable: bool]

proc docFor(docs: Table[string, string], path, tableName, name: string): string =
  result = docs.getOrDefault("@" & path)
  if result.len == 0: result = docs.getOrDefault(tableName & "T." & name)

proc sortedKeys(t: ScriptTable): seq[string] =
  for (k, _) in pairsCursor(t):
    if k.kind == vkString: result.add(k.str.s)
  result.sort()

proc kindName(v: ScriptValue): string =
  case v.kind
  of vkNil: "nil"
  of vkBool: "boolean"
  of vkNumber: "number"
  of vkString: "string"
  of vkTable: "table"
  of vkFunction, vkNative: "function"
  else: "userdata"

proc isRecord(t: ScriptTable): bool =
  ## A table of plain values (a colour, a vector): listed as a value.
  for (_, v) in pairsCursor(t):
    if v.kind notin {vkNumber, vkString, vkBool}: return false
  true

proc walkLib(docs: Table[string, string], t: ScriptTable, path: string, depth: int,
             skipFn: proc (path: string): bool, libs: var seq[ApiLib]) =
  var lib = ApiLib(path: path)
  var subs: seq[(string, ScriptTable)]
  let tableName = if '.' in path: path.rsplit('.', 1)[1] else: path
  for k in sortedKeys(t):
    let v = rawGetStr(t, k)
    let p = path & "." & k
    if skipFn(p): continue   # (listed with the game's procs or raylib instead)
    if v.kind in {vkFunction, vkNative}:
      lib.fns.add((p, docFor(docs, p, tableName, k)))
    elif v.kind == vkTable and depth < 2 and not isRecord(v.tbl):
      subs.add((p, v.tbl))
    else:
      lib.values.add((k, kindName(v)))
  libs.add(lib)
  for (p, st) in subs: walkLib(docs, st, p, depth + 1, skipFn, libs)

proc collect(): tuple[libs: seq[ApiLib], procs: seq[ApiProc], globals: seq[string]] =
  var docs: Table[string, string]
  for (k, d) in NativeDocs:
    if not docs.hasKey(k): docs[k] = d
  var modules: seq[string]   # engine.<module> callers come from the slots, below
  for s in mixinSlots:
    let m = s.name.split('.')[0]
    if m notin modules: modules.add(m)
  let skipFn = proc (path: string): bool =
    let parts = path.split('.')
    if parts.len == 2 and parts[0] == "engine" and parts[1] in modules: return true
    if parts[0] == "rl" and parts.len >= 2:
      let last = parts[^1]
      if parts.len == 2 and hasSlot("raylib." & last): return true
      if parts.len == 3 and parts[1] == "gl" and hasSlot("rlgl." & last): return true
    false
  if not modBase.isNil:
    for k in sortedKeys(modBase):
      if k in LuaStdlib: continue
      let v = rawGetStr(modBase, k)
      if v.kind == vkTable: walkLib(docs, v.tbl, k, 1, skipFn, result.libs)
  for s in mixinSlots:
    let note = if s.isModdable: (if s.supported: "" else: s.problem)
               elif s.call.isNil: s.problem
               else: ""
    result.procs.add((s.name, s.signature, note, s.isModdable))
  result.procs.sort(proc (a, b: ApiProc): int = cmp(a.name & a.signature, b.name & b.signature))
  for (name, typ) in modGlobalTypes(): result.globals.add(name & ": " & typ)
  result.globals.sort()

proc paramNames(signature: string): seq[string] =
  ## "f(a: int, b: array[2, int]): x" -> @["a", "b"] (Lua keywords get a "_").
  let open = signature.find('(')
  if open < 0: return
  var depth = 0
  var part = ""
  var i = open + 1
  while i < signature.len:
    let c = signature[i]
    if c in {'(', '['}: inc depth
    elif c in {')', ']'}:
      if depth == 0: break
      dec depth
    if c == ',' and depth == 0:
      result.add(part)
      part = ""
    else: part.add(c)
    inc i
  if part.strip.len > 0: result.add(part)
  for n in result.mitems:
    n = n.split(':')[0].strip
    if n in LuaKeywords: n.add('_')

# ------------------------------------------------------------ rendering ----
proc mdEscape(s: string): string = s.replace("|", "\\|")

proc buildModApi*(): tuple[md, lua: string] =
  ## API.md and tophat.d.lua for the running VM (no mods loaded, so it is the
  ## game's API alone).
  let (libs, procs, globals) = collect()
  var md = "# TopHat-ShooterOS mod API\n\nGame version " & GameVersion &
    ". Generated from the game itself by `nimble modapi`: everything below exists in this " &
    "build. MODDING.md explains how to use it; this is the complete list.\n\n" &
    "- [Libraries](#libraries): the tables every mod sees\n" &
    "- [Hooks](#hooks): `hooks.on(name, fn)`\n" &
    "- [The game's procs](#the-games-procs): `engine.<module>.<proc>(...)`, and `mixin.*` for the moddable ones\n" &
    "- [raylib](#raylib): `rl.*` and `rl.gl.*`\n" &
    "- [engine.globals](#engineglobals): the game's global state\n\n"
  var lua = "---@meta\n-- TopHat-ShooterOS mod API, game version " & GameVersion &
    " (generated by `nimble modapi`; API.md has the same as a list).\n\n"

  # libraries
  md.add "## Libraries\n\nThe Lua 5.5 standard library is all there too (`io`, `os`, `debug`, `package`, `load`...).\n\n"
  for lib in libs:
    if lib.fns.len == 0 and lib.values.len == 0: continue
    md.add "### `" & lib.path & "`\n\n"
    lua.add lib.path & " = {}\n"
    for (path, doc) in lib.fns:
      md.add "- `" & path & "`" & (if doc.len > 0: ": " & doc else: "") & "\n"
      if doc.len > 0: lua.add "---" & doc & "\n"
      if path in ["hooks.on", "hooks.off"]:
        lua.add "---@param name HookName\n---@param fn function\nfunction " & path & "(name, fn) end\n"
      elif path in ModdableFirst:
        lua.add "---@param name ModdableName\nfunction " & path & "(name, ...) end\n"
      else:
        lua.add "function " & path & "(...) end\n"
    for (name, kind) in lib.values:
      md.add "- `" & lib.path & "." & name & "` (" & kind & ")\n"
      if kind notin ["userdata", "table"]: lua.add "---@type " & kind & "\n" & lib.path & "." & name & " = nil\n"
    md.add "\n"
    lua.add "\n"

  # hooks
  md.add "## Hooks\n\n`hooks.on(name, function(...) end)`. A *cancel* hook's handler returns true to skip " &
    "the game's own behaviour; a *filter* hook's returns the replacement for its first argument.\n\n"
  lua.add "---@alias HookName\n"
  var group = "\0"
  for (name, doc, g) in HookDocs:
    if g != group:
      md.add "\n**" & g & "**\n\n| hook | arguments, and what it does |\n|---|---|\n"
      group = g
    md.add "| `" & name & "` | " & mdEscape(doc) & " |\n"
    lua.add "---| \"" & name & "\" # " & doc & "\n"
  md.add "\n"
  lua.add "\n"

  # the game's procs
  md.add "## The game's procs\n\nEvery proc here is called from Lua as `engine.<module>.<proc>(...)` " &
    "(or `engine.call(\"<module>.<proc>\", ...)`); overloads are tried in order. The **moddable** ones " &
    "can also be wrapped: `mixin.wrap(\"<module>.<proc>\", function(orig, ...) end)`, `before`, `after`, " &
    "`replace`.\n\n"
  var moddableNames: seq[string]
  var module = ""
  var luaModules: seq[string]
  var lastLuaFn = ""
  for p in procs:
    let m = p.name.split('.')[0]
    if m in ["raylib", "rlgl"]: continue
    if m != module:
      md.add "\n### `" & m & "`\n\n"
      module = m
      if m notin luaModules:
        luaModules.add(m)
        lua.add "\nengine." & m & " = {}\n"
    md.add "- " & (if p.moddable: "**moddable** " else: "") & "`" & p.signature & "`" &
           (if p.note.len > 0: " (" & p.note & ")" else: "") & "\n"
    if p.moddable and p.note.len == 0 and p.name notin moddableNames: moddableNames.add(p.name)
    if p.name != lastLuaFn:
      lastLuaFn = p.name
      lua.add "---" & p.signature & "\nfunction engine." & p.name & "(" &
              paramNames(p.signature).join(", ") & ") end\n"
    else:
      lua.add "---@overload fun(" & paramNames(p.signature).join(", ") & ")\n"
  md.add "\n"
  lua.add "\n---@alias ModdableName\n"
  for n in moddableNames: lua.add "---| \"" & n & "\"\n"
  lua.add "\n"

  # raylib
  md.add "## raylib\n\n`rl.<function>` is raylib, `rl.gl.<function>` rlgl: vectors, rectangles and colours " &
    "are tables, and textures, fonts, sounds... are handles (one a script loads unloads itself once dropped).\n\n"
  lastLuaFn = ""
  for p in procs:
    let m = p.name.split('.')[0]
    if m notin ["raylib", "rlgl"]: continue
    let prefix = if m == "raylib": "rl." else: "rl.gl."
    let short = p.name.split('.', 1)[1]
    md.add "- `" & prefix & p.signature & "`" & (if p.note.len > 0: " (" & p.note & ")" else: "") & "\n"
    if p.name != lastLuaFn:
      lastLuaFn = p.name
      lua.add "---" & p.signature & "\nfunction " & prefix & short & "(" &
              paramNames(p.signature).join(", ") & ") end\n"
  md.add "\n"
  lua.add "\n"

  # globals
  md.add "## engine.globals\n\nThe game's global state, read and written in place " &
    "(`engine.globals.settings.musicVolume = 0.5`).\n\n"
  lua.add "---@class EngineGlobals\n"
  for g in globals:
    md.add "- `" & g & "`\n"
    let parts = g.split(": ", 1)
    lua.add "---@field " & parts[0] & " any " & parts[1] & "\n"
  lua.add "\n---@type EngineGlobals\nengine.globals = {}\n"
  (md, lua)

proc buildStringsJson*(): string =
  ## Every text key with its English, in the game's own order (grouped by
  ## where it shows): a translation starts as a copy of this file.
  result = "{\n"
  var first = true
  for key in TranslationKey:
    if not first: result.add(",\n")
    first = false
    result.add("  " & escapeJson($key) & ": " & escapeJson(builtinText(English, $key)))
  result.add("\n}\n")

proc dumpModApi*(dir: string): bool =
  ## Write API.md, tophat.d.lua and strings_en.json into `dir`. False on a
  ## write error.
  let (md, lua) = buildModApi()
  try:
    createDir(dir)
    writeFile(dir / "API.md", md)
    writeFile(dir / "tophat.d.lua", lua)
    writeFile(dir / "strings_en.json", buildStringsJson())
    true
  except IOError, OSError:
    false
