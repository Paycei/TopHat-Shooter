## Loading and reloading mods. Imported by main.nim only.
##
## reloadMods rebuilds the whole mod layer from scratch: every registration,
## hook, string and asset of the previous set is dropped, a fresh VM is made,
## and the enabled mods run in load order. A mod whose main script fails
## leaves nothing behind, and mods that depend on it are skipped. Only called
## from the desktop, never during a run, so a run always sees one fixed set.

import std/[os, strutils]
import ../localization
import lua_bridge, mod_state, mod_hooks, mod_api, mod_3d, mod_catalog, mod_assets

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

proc reloadMods*(enabled: seq[string], equippedCosmetics: seq[string] = @[]) =
  # 1. Tear the previous set down (keeping what the old set stored).
  saveAllModStorage()
  unloadModAssets()
  clearModTranslations()
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
  resetModContent()

  # 3. Discover and run.
  installedMods = scanMods(enabled)
  let order = loadOrder(installedMods)
  var loadedIds: seq[string]
  var loadedInfos: seq[ModInfo]
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
    let m = ModRuntime(id: info.id, name: info.name, version: info.version,
                       author: info.author, dir: info.dir, index: mods.len,
                       runData: newScriptTable())
    m.env = newModEnv(base)
    mods.add(m)
    installModEnv(m)
    var err = ""
    try:
      let src = readFile(info.dir / info.main)
      let cl = vm.loadChunk(src, info.id & "/" & info.main, m.env)
      var r: RetVals
      currentModIdx = m.index
      err = protectedCall(vm, vfunc(cl), [], r, LoadStepBudget)
    except ScriptError as e:
      err = e.msg
    except IOError, OSError:
      err = "cannot read " & info.main
    currentModIdx = -1
    if err.len > 0:
      installedMods[ci].status = msError
      installedMods[ci].message = err
      m.disabled = true
      dropHandlersOf(m.index)
      dropModText(m.index)
      dropModContent(m.index)
    else:
      installedMods[ci].status = msLoaded
      loadedIds.add(info.id)
      loadedInfos.add(info)
    statusLog(installedMods[ci])

  # 4. Publish the new set.
  loadedModIds = loadedIds
  modsActive = loadedIds.len > 0
  for info in loadedInfos:
    if info.disableAchievements: modsDisableAchievements = true
  modFingerprintHex = if modsActive: computeFingerprint(loadedInfos) else: ""
  if modsActive:
    captureModRunData = captureRunData
  applyEquippedCosmetics(equippedCosmetics)
  modLogAdd(mlInfo, "", "mods reloaded: " & summaryText() &
            (if modsActive: " (set " & modFingerprintHex & ")" else: "") &
            (if not modsActive: ""
             elif modsDisableAchievements: "; runs with this set count as cheated (no rewards)"
             else: "; runs with this set keep their rewards"))
