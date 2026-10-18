## Loading and reloading mods. Imported by main.nim only.
##
## reloadMods rebuilds the whole mod layer from scratch: every registration,
## hook, string and asset of the previous set is dropped, a fresh VM is made,
## and the enabled mods run in load order. A mod whose main script fails
## leaves nothing behind, and mods that depend on it are skipped. Only called
## from the desktop, never during a run, so a run always sees one fixed set.

import std/[os, strutils, json, algorithm]
import ../localization, ../settings, ../utils
import lua_bridge, mod_state, mod_hooks, mod_api, mod_3d, mod_world2d, mod_content_api, mod_ui, mod_engine, mod_pvp, mod_theme, mod_catalog, mod_assets, mod_mixin, mod_rl, mod_market

proc summaryText*(): string =
  ## "3 loaded, 1 failed" style line for toasts and the log.
  var loaded, failed = 0
  for m in installedMods:
    case m.status
    of msLoaded: inc loaded
    of msError, msMissingDep: inc failed
    else: discard
  result = t(tkModsSummaryLoaded).replace("$1", $loaded)
  if failed > 0: result.add(", " & t(tkModsSummaryFailed).replace("$1", $failed))

const
  ContentTypes = ["powerup", "enemy", "boss", "thing", "projectile", "status", "consumable",
                  "shopItem", "patch", "survivalEvent", "advancement", "roster", "theme"]
  RosterKeys = ["mode", "enemy", "chance", "fromWave", "minTime", "minFloor"]

proc rosterCall(m: ModRuntime, e: JsonNode): (ScriptValue, seq[ScriptValue], string) =
  ## {"type": "roster", "mode": "wave", "enemy": "brute", "chance": 0.1, "fromWave": 3}
  ## -> roster.add(mode, enemy, options); a bare enemy id is this mod's own.
  for k, _ in e.pairs:
    if k notin RosterKeys: return (NilValue, @[], "roster: unknown field \"" & k & "\" (" & RosterKeys.join(", ") & ")")
  if not e.hasKey("mode") or e["mode"].kind != JString or not e.hasKey("enemy") or e["enemy"].kind != JString:
    return (NilValue, @[], "roster needs \"mode\" and \"enemy\"")
  var enemy = e["enemy"].getStr
  if ':' notin enemy and not enemy.startsWith("et"): enemy = m.id & ":" & enemy
  let opts = e.copy
  opts.delete("mode")
  opts.delete("enemy")
  let rosterV = rawGetStr(m.env, "roster")
  if rosterV.kind != vkTable: return (NilValue, @[], "content: no roster library")
  (rawGetStr(rosterV.tbl, "add"), @[vstr(e["mode"].getStr), vstr(enemy), fromJsonNode(opts)], "")

proc loadContentPacks(vm: VM, m: ModRuntime): string =
  ## <mod>/content/**/*.json: each file holds one {type = ..., ...} or a list
  ## of them, fed through the same register.* natives as a script's, in file
  ## order, still inside the mod's load. "" = fine, else the error.
  let dir = m.dir / "content"
  if not dirExists(dir): return ""
  var files: seq[string]
  for f in walkDirRec(dir):
    if f.toLowerAscii.endsWith(".json"): files.add(f)
  files.sort()
  let regV = rawGetStr(m.env, "register")
  if regV.kind != vkTable: return "content: no register library"
  for f in files:
    let rel = relativePath(f, m.dir).replace('\\', '/')
    var node: JsonNode
    try: node = parseJson(readFile(f))
    except CatchableError as e: return rel & ": " & e.msg.splitLines()[0]
    let entries = if node.kind == JArray: node.elems else: @[node]
    for i, e in entries:
      let where = rel & (if entries.len > 1: " [" & $(i + 1) & "]" else: "")
      if e.kind != JObject or not e.hasKey("type") or e["type"].kind != JString:
        return where & ": needs \"type\" (" & ContentTypes.join(", ") & ")"
      let typ = e["type"].getStr
      if typ notin ContentTypes:
        return where & ": unknown type \"" & typ & "\" (" & ContentTypes.join(", ") & ")"
      let body = e.copy
      body.delete("type")
      var fn: ScriptValue
      var callArgs: seq[ScriptValue]
      if typ == "roster":
        var problem: string
        (fn, callArgs, problem) = rosterCall(m, body)
        if problem.len > 0: return where & ": " & problem
      else:
        fn = rawGetStr(regV.tbl, typ)
        callArgs = @[fromJsonNode(body)]
      var r: RetVals
      let err = protectedCall(vm, fn, callArgs, r, LoadLimit)
      if err.len > 0: return where & ": " & err.splitLines()[0]
  ""

# ------------------------------------------------------------ safe mode ----
# Mods are trusted, so nothing switches one off while it runs; instead, a game
# that went down with mods loaded starts the next time without them. A marker
# in the mods folder says "mods are loaded right now": written by every reload
# that loaded something, removed by one that did not and by a clean shutdown.

proc sessionMarker(): string = modsRootDir() / ".session"

proc modSessionCrashed*(): bool =
  ## At launch: the last session ended without shutting down, with mods loaded.
  fileExists(sessionMarker())

proc markModSession() =
  try:
    if modsActive: writeFile(sessionMarker(), "mods loaded: " & loadedModIds.join(", "))
    elif fileExists(sessionMarker()): removeFile(sessionMarker())
  except IOError, OSError:
    discard

proc endModSession*() =
  ## A clean shutdown.
  try:
    if fileExists(sessionMarker()): removeFile(sessionMarker())
  except IOError, OSError:
    discard

proc reloadMods*(enabled: seq[string], equippedCosmetics: seq[string] = @[]) =
  # 1. Tear the previous set down (keeping what the old set stored).
  saveAllModStorage()
  unloadModAssets()
  clearModTranslations()
  clearModLanguages()
  resetHooks()
  modsActive = false
  modsDisableAchievements = false
  modFingerprintHex = ""
  loadedModIds = @[]
  captureModRunData = nil

  # 2. A fresh VM and API.
  let (vm, base) = newScriptVM()
  initModHooksVM(vm, base)
  installModApi(base)
  installMod3D(base)
  installWorld2D(base)
  installContentApi(base)
  installModUi(base)
  installModEngine(base)
  installModPvP(base)
  installModTheme(base)
  installModMixin(base)   # (after mod_api: it fills the engine table)
  installModRl(base)      # (after mod_mixin: rl is engine.raylib)
  resetModContent()
  let libraries = tableKeysOf(base)   # each mod gets its own copy of every game library

  # 3. Discover and run. Marketplace downloads of mods that were loaded wait
  # for this point: the old copies' files (streams, script handles) are closed.
  applyStagedMarketInstalls()
  installedMods = scanMods(enabled)
  let order = loadOrder(installedMods)
  var loadedIds: seq[string]
  var loadedInfos: seq[ModInfo]
  var fingerprint = FingerprintStart
  for ci in order:
    var failedDep = ""
    for d in installedMods[ci].dependencies:
      if d notin loadedIds:
        failedDep = d
        break
    if failedDep.len > 0:
      installedMods[ci].status = msMissingDep
      installedMods[ci].message = "requires \"" & failedDep & "\", which failed to load"
      statusLog(installedMods[ci])
      continue
    let info = installedMods[ci]
    let withThis = fingerprintMix(fingerprint, info)   # its files as they were before it ran
    let m = ModRuntime(id: info.id, name: info.name, version: info.version,
                       author: info.author, dir: info.dir, index: mods.len,
                       runData: newScriptTable())
    m.env = newModEnv(base, libraries)
    mods.add(m)
    installModEnv(m)
    var err = ""
    try:
      beginModLoad(m.index)
      if info.main.len > 0:   # (a content-only mod has no script)
        let src = readFile(modMainPath(info))
        let cl = vm.loadChunk(src, info.id & "/" & info.main, m.env)
        var r: RetVals
        err = protectedCall(vm, vfunc(cl), [], r, LoadLimit)
      if err.len == 0:
        err = loadContentPacks(vm, m)
    except ScriptError as e:
      err = e.msg
    except IOError, OSError:
      err = "cannot read " & info.main
    endModLoad()
    if err.len > 0:
      installedMods[ci].status = msError
      installedMods[ci].message = err
      m.disabled = true
      dropHandlersOf(m.index)
      dropModKeybinds(m.index)
      dropModText(m.index)
      dropModContent(m.index)
    else:
      installedMods[ci].status = msLoaded
      loadedIds.add(info.id)
      loadedInfos.add(info)
      fingerprint = withThis
      if needsNewerGame(info):
        modLogAdd(mlWarn, info.id, "made for game version " & info.game & " or newer (this is " &
                  GameVersion & "): parts of it may not work")
    statusLog(installedMods[ci])

  # 4. Publish the new set.
  loadedModIds = loadedIds
  modsActive = loadedIds.len > 0
  for info in loadedInfos:
    if info.disableAchievements: modsDisableAchievements = true
  modFingerprintHex = if modsActive: fingerprintHex(fingerprint) else: ""
  if modsActive:
    captureModRunData = captureRunData
  applyEquippedCosmetics(equippedCosmetics)
  # A mod's language is in the settings by id: in use again now that its mod
  # registered it (English while it is not loaded), and every cached string
  # (skin names...) is redone with the new set's text.
  if not globalSettings.isNil:
    discard useLanguage(globalSettings.language)
  markModSession()
  modLogAdd(mlInfo, "", "mods reloaded: " & summaryText() &
            (if modsActive: " (set " & modFingerprintHex & ")" else: "") &
            (if not modsActive: ""
             elif modsDisableAchievements: "; runs with this set count as cheated (no rewards)"
             else: "; runs with this set keep their rewards"))
