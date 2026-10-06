## Installed mods: discovery, manifests, load order and the fingerprint.
##
## A mod is a folder holding a `mod.json` manifest, found in
##   <data root>/mods/<folder>/   (per user; the Open Folder button's target)
##   <game folder>/mods/<folder>/ (portable installs)
## Load order is not user-arranged: it is the topological order of
## `dependencies` and `loadAfter`, ties broken by id, so two players with the
## same mods load them identically (PvP lobbies and snapshot slot binding
## depend on that).

import std/[os, json, strutils, algorithm]
import ../save_system
import mod_state

type
  ModStatus* = enum
    msDisabled      ## installed, not enabled for this profile
    msLoaded
    msError         ## its scripts failed while loading
    msMissingDep    ## a dependency is missing, disabled or failed
    msDuplicate     ## another folder already uses this id
    msInvalid       ## unreadable or malformed mod.json

  ModInfo* = object
    id*, name*, version*, author*, description*, main*: string
    dependencies*, loadAfter*: seq[string]
    dir*: string
    enabled*: bool
    disableAchievements*: bool   ## mod.json "disableAchievements" (default true)
    status*: ModStatus
    message*: string   ## why it is not loaded (error text with traceback)

var installedMods*: seq[ModInfo]
  ## (not "modCatalog": Nim names are style-insensitive, so that is this module's own name)

proc modsRootDir*(): string =
  ## The per-user mods folder (created on first use).
  result = getRootDataPath() / "mods"
  try:
    if not dirExists(result): createDir(result)
  except OSError, IOError:
    discard

proc modSearchDirs*(): seq[string] =
  result.add(modsRootDir())
  let portable = getAppDir() / "mods"
  if dirExists(portable) and normalizedPath(portable) != normalizedPath(result[0]):
    result.add(portable)

proc validId(id: string): bool =
  if id.len == 0 or id.len > 40: return false
  for c in id:
    if c notin {'a'..'z', '0'..'9', '_'}: return false
  true

proc strList(j: JsonNode, key: string): seq[string] =
  let n = j.getOrDefault(key)
  if not n.isNil and n.kind == JArray:
    for x in n:
      if x.kind == JString: result.add(x.getStr)

proc readManifest(dir: string): ModInfo =
  result.dir = dir
  result.status = msInvalid
  let path = dir / "mod.json"
  var j: JsonNode
  try:
    j = parseJson(readFile(path))
  except CatchableError as e:
    result.id = lastPathPart(dir)
    result.name = result.id
    result.message = "mod.json could not be read: " & e.msg
    return
  if j.kind != JObject:
    result.id = lastPathPart(dir)
    result.name = result.id
    result.message = "mod.json must be a JSON object"
    return
  result.id = j.getOrDefault("id").getStr("")
  result.name = j.getOrDefault("name").getStr(result.id)
  result.version = j.getOrDefault("version").getStr("1.0.0")
  result.author = j.getOrDefault("author").getStr("")
  result.description = j.getOrDefault("description").getStr("")
  result.main = j.getOrDefault("main").getStr("main.lua")
  result.dependencies = strList(j, "dependencies")
  result.loadAfter = strList(j, "loadAfter")
  result.disableAchievements = true
  if not validId(result.id):
    result.message = "\"id\" must be 1-40 characters of a-z, 0-9 and _ (got \"" & result.id & "\")"
    if result.id.len == 0: result.id = lastPathPart(dir)
    return
  if result.main.isAbsolute or ".." in result.main:
    result.message = "\"main\" must be a file inside the mod folder"
    return
  if not fileExists(dir / result.main):
    if not j.hasKey("main") and dirExists(dir / "content"):
      result.main = ""   # a content-only mod: its content/*.json is all it has
    else:
      result.message = "main script not found: " & result.main
      return
  let da = j.getOrDefault("disableAchievements")
  if not da.isNil:
    if da.kind != JBool:
      result.message = "\"disableAchievements\" must be true or false"
      return
    result.disableAchievements = da.getBool
  result.status = msDisabled

proc scanMods*(enabled: seq[string]): seq[ModInfo] =
  ## Every installed mod, sorted by id; `enabled` marks the ones to load.
  var seen: seq[string]  # (std/sets is not used in this project)
  for root in modSearchDirs():
    var dirs: seq[string]
    try:
      for kind, path in walkDir(root):
        if kind in {pcDir, pcLinkToDir} and fileExists(path / "mod.json"):
          dirs.add(path)
    except OSError:
      continue
    dirs.sort()
    for d in dirs:
      var info = readManifest(d)
      if info.status != msInvalid and info.id in seen:
        info.status = msDuplicate
        info.message = "another installed mod already uses the id \"" & info.id & "\""
      if info.status != msInvalid:
        seen.add(info.id)
      info.enabled = info.id in enabled
      result.add(info)
  result.sort(proc (a, b: ModInfo): int = cmp(a.id, b.id))

proc rescanInstalledMods*(enabled: seq[string]) =
  ## Re-read the folders (new mods show up) without loading anything: mods
  ## that are still there keep the status of the last reload.
  var fresh = scanMods(enabled)
  for i in 0 ..< fresh.len:
    if fresh[i].status != msDisabled: continue
    for old in installedMods:
      if old.id == fresh[i].id and old.dir == fresh[i].dir:
        fresh[i].status = old.status
        fresh[i].message = old.message
        break
  installedMods = fresh

proc candidateIndex(catalog: seq[ModInfo], candidates: seq[int], id: string): int =
  for i in candidates:
    if catalog[i].id == id: return i
  -1

proc loadOrder*(catalog: var seq[ModInfo]): seq[int] =
  ## Indices of the enabled, valid mods in load order. Marks the ones that
  ## cannot load (missing or disabled dependency, dependency cycle).
  ## (No closures here: a closure cannot capture the `var` catalog.)
  var candidates: seq[int]
  for i, m in catalog:
    if m.enabled and m.status == msDisabled:
      candidates.add(i)
  template idxOf(id: string): int = candidateIndex(catalog, candidates, id)
  # Hard dependencies must be enabled and valid; repeat until stable so a
  # mod whose dependency just dropped out drops out too.
  var changed = true
  while changed:
    changed = false
    var kept: seq[int]
    for i in candidates:
      var bad = ""
      for d in catalog[i].dependencies:
        if idxOf(d) < 0:
          var installed = false
          for m in catalog:
            if m.id == d and m.status notin {msInvalid, msDuplicate}: installed = true
          bad = if installed: "requires \"" & d & "\" (enable it too)"
                else: "requires \"" & d & "\" (not installed)"
          break
      if bad.len > 0:
        catalog[i].status = msMissingDep
        catalog[i].message = bad
        changed = true
      else:
        kept.add(i)
    candidates = kept
  # Kahn's algorithm, smallest id first among the ready ones.
  var placed: seq[string]
  var remaining = candidates
  while remaining.len > 0:
    var ready: seq[int]
    for i in remaining:
      var ok = true
      for d in catalog[i].dependencies & catalog[i].loadAfter:
        if idxOf(d) >= 0 and d notin placed and d != catalog[i].id:
          ok = false
          break
      if ok: ready.add(i)
    if ready.len == 0:
      for i in remaining:
        catalog[i].status = msError
        catalog[i].message = "dependency cycle between enabled mods"
      break
    var pick = ready[0]
    for i in ready:
      if catalog[i].id < catalog[pick].id: pick = i
    result.add(pick)
    placed.add(catalog[pick].id)
    remaining.delete(remaining.find(pick))

proc modFiles*(dir: string): seq[string] =
  ## Every file of a mod, as sorted relative paths.
  try:
    for path in walkDirRec(dir, relative = true):
      result.add(path.replace('\\', '/'))
  except OSError:
    discard
  result.sort()

proc computeFingerprint*(infos: seq[ModInfo]): string =
  ## FNV-1a over the loaded mods' ids, versions and every file byte, as 8 hex
  ## digits. Same mods, same files: same fingerprint on every machine.
  var h = 2166136261'u32
  template mixStr(s: string) =
    for c in s:
      h = (h xor uint32(ord(c))) * 16777619'u32
    h = (h xor 0xFF'u32) * 16777619'u32
  for m in infos:
    mixStr(m.id)
    mixStr(m.version)
    for rel in modFiles(m.dir):
      mixStr(rel)
      try:
        mixStr(readFile(m.dir / rel))
      except IOError:
        mixStr("<unreadable>")
  toHex(h, 8).toLowerAscii

proc statusLog*(m: ModInfo) =
  case m.status
  of msLoaded: modLogAdd(mlInfo, m.id, "loaded (" & m.name & " " & m.version & ")")
  of msDisabled: discard
  else: modLogAdd(mlError, m.id, m.message)
