## Process-wide mod state (MODS.EXE).
##
## The one module every layer may consult to ask "are mods loaded, and which
## set?": the save layers (run_save.nim, suspend.nim) key their file names on
## it, the network handshake sends the fingerprint, and the game marks runs.
## It imports only types, so it sits below every gameplay module.
##
## The mod set can only change from the desktop (mod_loader.reloadMods, never
## mid-run), so everything here is stable for the whole life of a run.

import std/strutils
import ../types

type
  ModLogLevel* = enum
    mlInfo, mlWarn, mlError

  ModLogLine* = object
    level*: ModLogLevel
    modId*: string   ## "" for loader messages
    text*: string

const MaxModLogLines = 400

var
  modsActive*: bool
    ## At least one mod loaded successfully. Every run started while this is
    ## true is stamped as modded (see markRunModded); it counts as cheated only
    ## when modsDisableAchievements is set too.
  modsDisableAchievements*: bool
    ## At least one loaded mod keeps its runs from earning rewards (mod.json
    ## `disableAchievements`, default true); false when no mod is loaded.
  modFingerprintHex*: string
    ## 8 lowercase hex digits identifying the loaded mod set (ids, versions and
    ## every file byte). "" when no mod is loaded.
  loadedModIds*: seq[string]
    ## Ids of the successfully loaded mods, in load order (for messages).
  modReloadRequested*: bool
    ## Set by the MODS.EXE window; main.nim performs the reload from the desktop.
  modLog*: seq[ModLogLine]
  modLogGeneration*: int
    ## Bumped on every append so the log view can tell it changed.
  captureModRunData*: proc (game: Game, entities: bool) {.nimcall.}
    ## Installed by the mod loader: serializes the mods' run.data into
    ## game.modRunData right before either save layer writes the run.
    ## `entities`: also the per-entity data (e.data), which only the exact
    ## suspend snapshot keeps (a run save rebuilds its enemies with new ids).

proc modLogAdd*(level: ModLogLevel, modId, text: string) =
  for line in text.splitLines:
    if modLog.len >= MaxModLogLines:
      modLog.delete(0)
    modLog.add(ModLogLine(level: level, modId: modId, text: line))
  inc modLogGeneration
  when defined(debug):
    let tag = if modId.len > 0: "[mod:" & modId & "] " else: "[mods] "
    echo tag, text

proc saveSlotTag*(modMode: string = ""): string =
  ## Suffix every run-save file name carries. Vanilla play keeps the original
  ## names (""), a modded session writes its own "_m<fingerprint>" files and a
  ## mod game mode adds its id. Keying the NAME (rather than checking a stamp
  ## inside the file) matters: fresh starts and failed restores delete the
  ## current mode's files, so a modded session must never even see a vanilla
  ## save, and a different mod set gets different slots for free.
  if not modsActive:
    return ""
  result = "_m" & modFingerprintHex
  if modMode.len > 0:
    # A mode key is "<mod id>:<id>"; ':' is not allowed in Windows file names.
    result.add("_" & modMode.replace(':', '-'))

proc markRunModded*(game: Game) =
  ## Stamp a run started with mods loaded. Unconditional, even in debug builds
  ## (like tutorial practice). The run counts as cheated (earns nothing
  ## permanent) only if a loaded mod asks for it; this never clears cheatsUsed,
  ## which a resumed save or the cheat menu may already have set.
  if game.isNil or not modsActive:
    return
  game.modded = true
  if modsDisableAchievements:
    game.cheatsUsed = true
  game.modFingerprint = modFingerprintHex
