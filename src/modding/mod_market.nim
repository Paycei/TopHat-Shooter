## The mod marketplace (MODS.EXE's Marketplace tab): the registry of
## published mods and installing them from GitHub.
##
## The registry is a GitHub repository (RegistryRepoUrl) holding one file per
## mod, mods/<id>.json: a mod's repository, the commit its review approved,
## its title, description and version. The game downloads the whole registry
## as one archive (codeload: no API rate limit) and a mod as the archive of
## its pinned commit, whose comment `git archive` sets to the commit id, so
## what installs is what was reviewed. An update is a new commit in the
## registry.
##
## Installs land in <data root>/mods/<id>/, byte for byte the repository's
## folder: what the marketplace knows about them (repository, commit) lives in
## <data root>/marketplace/installed.json, never in the mod folder, so a mod's
## fingerprint (save slots, PvP lobbies) is the same on every machine.
##
## Downloads run on one worker thread, one job at a time (installs queue).
## The worker gets every input (URLs, paths) in `job` before it starts and
## touches nothing else: no t(), no mod runtime, no {.moddable.} proc (mixins
## are main-thread only). The main thread reads its results after joinThread.
## A finished install is staged (marketplace/staging/<id>/, stage.json written
## last as the "complete" mark) and swapped into the mods folder on the main
## thread: right away when no copy of that mod is loaded, else by reloadMods
## (applyStagedMarketInstalls) once the old copy's files are closed.

import std/[os, json, strutils, algorithm, times, atomics]
import ../save_system, ../utils
import ../network/https
import mod_state, mod_catalog, mod_zip

const
  RegistryRepoUrl* = "https://github.com/Paycei/TopHat-Shooter-ModRoot"
  OfficialRegistry = "https://codeload.github.com/Paycei/TopHat-Shooter-ModRoot/zip/refs/heads/main"
  RegistryFormat* = 1   ## registry.json "format" this build reads
  MaxTitle = 48
  MaxDescription = 240
  LogTag = "marketplace"

type
  MarketEntry* = object
    ## One published mod (a registry file, checked).
    id*, title*, description*, repo*, commit*, version*, path*: string
    owner*: string   ## the repository's owner: shown as the author

  MarketState* = enum
    mkNotInstalled   ## no installed mod uses this id
    mkCurrent        ## installed from the marketplace at the listed commit
    mkUpdate         ## installed from the marketplace at another commit
    mkLocalCopy      ## a mod with this id is installed, not from the marketplace

  MarketFailure* = enum
    mfNone
    mfNetwork, mfTimeout, mfCancelled, mfCertificate, mfClock, mfProtocol  ## (tls.nim's)
    mfHttp       ## the server answered with an error (or not HTTP)
    mfArchive    ## the download is not a readable archive
    mfMismatch   ## the archive is not what the registry describes
    mfDisk       ## the files could not be written

  MarketEventKind* = enum
    meListUpdated, meListFailed, meInstalled, meStaged, meInstallFailed

  MarketEvent* = object
    kind*: MarketEventKind
    entry*: MarketEntry
    wasInstalled*: bool    ## an install replaced a copy of the mod (an update)
    failure*: MarketFailure
    detail*: string        ## English, already in the log

  MarketRecord = object
    ## installed.json: a mod folder the marketplace installed, and from what.
    id, folder, repo, commit, path, version: string

var
  marketEntries*: seq[MarketEntry]   ## the list, sorted by title
  marketListedAt*: float             ## when it was fetched (epoch seconds, 0 = never)
  marketListLive*: bool              ## fetched this session (false: the cached copy, or none)
  marketRegistryTooNew*: bool        ## the registry's format is newer than this game reads
  marketRegistrySource* = OfficialRegistry
    ## The registry's archive URL, or a folder holding a checkout of it
    ## (`--mod-registry <folder|url>`: testing an entry before its PR).
  records: seq[MarketRecord]
  pendingEvents: seq[MarketEvent]

# ------------------------------------------------------------------ paths ----
proc marketDir(): string = getRootDataPath() / "marketplace"
proc stagingRoot(): string = marketDir() / "staging"
proc trashRoot(): string = marketDir() / "trash"
proc downloadRoot(): string = marketDir() / "download"

# ---------------------------------------------------------------- entries ----
proc validMarketId(id: string): bool =
  ## mod_catalog's rule for mod.json "id".
  if id.len == 0 or id.len > 40: return false
  for c in id:
    if c notin {'a'..'z', '0'..'9', '_'}: return false
  true

proc fontText(s: string, maxChars: int): bool =
  ## One line of 1..maxChars characters the game's font draws (UTF-8 within
  ## U+0020..U+00FF, no control characters).
  var i, chars = 0
  while i < s.len:
    let c = ord(s[i])
    if c < 0x20 or c == 0x7F: return false
    if c < 0x80:
      inc i
    elif c in [0xC2, 0xC3] and i + 1 < s.len and (ord(s[i + 1]) and 0xC0) == 0x80 and
         not (c == 0xC2 and ord(s[i + 1]) < 0xA0):
      i += 2
    else:
      return false
    inc chars
  chars in 1 .. maxChars and s.strip == s

proc splitRepo*(repo: string, owner, name: var string): bool =
  ## "https://github.com/<owner>/<name>" (no ".git", no trailing slash).
  const Prefix = "https://github.com/"
  if not repo.startsWith(Prefix): return false
  let parts = repo[Prefix.len .. ^1].split('/')
  if parts.len != 2: return false
  owner = parts[0]
  name = parts[1]
  if owner.len notin 1 .. 39 or name.len notin 1 .. 100: return false
  for c in owner:
    if c notin {'A'..'Z', 'a'..'z', '0'..'9', '-'}: return false
  for c in name:
    if c notin {'A'..'Z', 'a'..'z', '0'..'9', '.', '_', '-'}: return false
  name notin [".", ".."] and not name.toLowerAscii.endsWith(".git")

proc validCommit(s: string): bool =
  if s.len != 40: return false
  for c in s:
    if c notin {'0'..'9', 'a'..'f'}: return false
  true

proc validVersion(s: string): bool =
  if s.len notin 1 .. 32 or s[0] notin Digits: return false
  for c in s:
    if c notin {'A'..'Z', 'a'..'z', '0'..'9', '.', '+', '-'}: return false
  true

proc validSubPath(p: string): bool =
  ## "" (the repository's root) or a relative folder path.
  if p.len == 0: return true
  if p.len > 200 or p.endsWith("/") or "//" in p or not safeRelative(p): return false
  for c in p:
    if c notin {'A'..'Z', 'a'..'z', '0'..'9', '.', '_', '-', '/'}: return false
  for part in p.split('/'):
    if part == ".": return false
  true

proc parseMarketEntry*(j: JsonNode, fileId: string, entry: var MarketEntry): string =
  ## One registry entry; "" when it is valid, else why not. `fileId` is its
  ## file's name without ".json" ("" to skip that check). Keys this build does
  ## not know are ignored (the registry's CI rejects them, so they can only be
  ## fields a newer game reads).
  if j.isNil or j.kind != JObject: return "not a JSON object"
  proc str(j: JsonNode, key: string): string =
    let n = j.getOrDefault(key)
    if n.isNil or n.kind != JString: "" else: n.getStr
  entry = MarketEntry(id: j.str("id"), title: j.str("title"), description: j.str("description"),
                      repo: j.str("repo"), commit: j.str("commit"), version: j.str("version"),
                      path: j.str("path"))
  var name: string
  if not validMarketId(entry.id): return "\"id\" must be 1-40 characters of a-z, 0-9 and _"
  if fileId.len > 0 and fileId != entry.id: return "the file must be named " & entry.id & ".json"
  if not fontText(entry.title, MaxTitle): return "\"title\" must be 1-" & $MaxTitle & " characters"
  if not fontText(entry.description, MaxDescription):
    return "\"description\" must be one line of 1-" & $MaxDescription & " characters"
  if not splitRepo(entry.repo, entry.owner, name): return "\"repo\" must be https://github.com/<owner>/<name>"
  if not validCommit(entry.commit): return "\"commit\" must be a full 40-character commit id"
  if not validVersion(entry.version): return "\"version\" must be a version like 1.2.0"
  if not validSubPath(entry.path): return "\"path\" must be a folder of the repository"
  ""

proc entryJson(e: MarketEntry): JsonNode =
  %*{"id": e.id, "title": e.title, "description": e.description, "repo": e.repo,
     "commit": e.commit, "version": e.version, "path": e.path}

proc marketArchiveUrl(e: MarketEntry): string =
  var owner, name: string
  discard splitRepo(e.repo, owner, name)
  "https://codeload.github.com/" & owner & "/" & name & "/zip/" & e.commit

proc marketPageUrl*(e: MarketEntry): string =
  ## The mod's folder on GitHub, at the listed commit.
  e.repo & "/tree/" & e.commit & (if e.path.len > 0: "/" & e.path else: "")

# ---------------------------------------------------------------- records ----
proc saveRecords() =
  var arr = newJArray()
  for r in records:
    arr.add(%*{"id": r.id, "folder": r.folder, "repo": r.repo, "commit": r.commit,
               "path": r.path, "version": r.version})
  try:
    createDir(marketDir())
    writeFile(marketDir() / "installed.json", pretty(%*{"mods": arr}))
  except OSError, IOError:
    modLogAdd(mlError, LogTag, "cannot write installed.json: " & getCurrentExceptionMsg())

proc loadRecords() =
  records = @[]
  let path = marketDir() / "installed.json"
  if not fileExists(path): return
  try:
    for n in parseFile(path){"mods"}:
      records.add(MarketRecord(id: n{"id"}.getStr, folder: n{"folder"}.getStr, repo: n{"repo"}.getStr,
                               commit: n{"commit"}.getStr, path: n{"path"}.getStr,
                               version: n{"version"}.getStr))
  except CatchableError:
    modLogAdd(mlWarn, LogTag, "installed.json could not be read: " & getCurrentExceptionMsg())

proc recordFor(dir: string): int =
  ## The record of the mod folder `dir` (-1: not a marketplace install).
  if normalizedPath(parentDir(dir)) != normalizedPath(modsRootDir()): return -1
  let folder = lastPathPart(dir)
  for i, r in records:
    if r.folder == folder: return i
  -1

proc listedEntry*(id: string): int =
  for i, e in marketEntries:
    if e.id == id: return i
  -1

proc marketState*(e: MarketEntry): MarketState =
  var found = false
  for m in installedMods:
    if m.id != e.id: continue
    found = true
    let r = recordFor(m.dir)
    if r >= 0 and records[r].id == e.id:
      return if records[r].commit == e.commit and records[r].repo == e.repo and
                records[r].path == e.path: mkCurrent
             else: mkUpdate
  if found: mkLocalCopy else: mkNotInstalled

proc marketInstalledVersion*(id: string): string =
  ## The installed copy's mod.json version ("" when none is installed).
  for m in installedMods:
    if m.id == id: return m.version
  ""

proc marketStateOf*(m: ModInfo): MarketState =
  ## For MODS.EXE's Installed tab: mkCurrent / mkUpdate for a marketplace
  ## install (mkCurrent too once the registry no longer lists it), else
  ## mkLocalCopy.
  let r = recordFor(m.dir)
  if r < 0 or records[r].id != m.id: return mkLocalCopy
  let at = listedEntry(m.id)
  if at >= 0 and marketEntries[at].commit != records[r].commit: mkUpdate else: mkCurrent

proc forgetMarketInstall*(dir: string) =
  ## A marketplace mod's folder was deleted (MODS.EXE's Remove).
  let r = recordFor(dir)
  if r >= 0:
    records.delete(r)
    saveRecords()

proc pruneMarketRecords*() =
  ## Drop records whose folder no longer holds that mod (deleted or replaced
  ## by hand). Call after rescanning the installed mods.
  var kept: seq[MarketRecord]
  for r in records:
    var present = false
    for m in installedMods:
      if m.id == r.id and recordFor(m.dir) >= 0 and lastPathPart(m.dir) == r.folder:
        present = true
    if present: kept.add(r)
  if kept.len != records.len:
    records = kept
    saveRecords()

# --------------------------------------------------------------- registry ----
proc applyRegistry(registryText: string, files: seq[tuple[name, text: string]],
                   commit: string, fetchedAt: float, live: bool): string =
  ## Parse a fetched (or cached) registry into marketEntries; "" or the error.
  var format = 0
  try:
    format = parseJson(registryText){"format"}.getInt(0)
  except CatchableError:
    return "registry.json could not be read"
  if format < 1: return "registry.json has no \"format\""
  marketRegistryTooNew = format > RegistryFormat
  var entries: seq[MarketEntry]
  var files = files
  files.sort(proc (a, b: tuple[name, text: string]): int = cmp(a.name, b.name))   # first of a duplicate wins
  if not marketRegistryTooNew:
    for f in files:
      var e: MarketEntry
      var err = ""
      try:
        err = parseMarketEntry(parseJson(f.text), f.name.changeFileExt(""), e)
      except CatchableError:
        err = "not valid JSON"
      var dupe = false
      for other in entries:
        if other.id == e.id or (other.repo == e.repo and other.path == e.path): dupe = true
      if err.len == 0 and dupe: err = "lists the same mod as another entry"
      if err.len > 0: modLogAdd(mlWarn, LogTag, "skipped mods/" & f.name & ": " & err)
      else: entries.add(e)
  entries.sort(proc (a, b: MarketEntry): int =
    result = cmpIgnoreCase(a.title, b.title)
    if result == 0: result = cmp(a.id, b.id))
  marketEntries = entries
  marketListedAt = fetchedAt
  marketListLive = live
  if live:
    var arr = newJArray()
    for e in entries: arr.add(entryJson(e))
    try:
      createDir(marketDir())
      writeFile(marketDir() / "registry.json",
                pretty(%*{"source": marketRegistrySource, "fetchedAt": fetchedAt, "commit": commit,
                          "format": format, "entries": arr}))
    except OSError, IOError:
      discard   # only the offline copy is lost
  ""

proc loadRegistryCache() =
  ## The last list fetched from this source, shown until a refresh succeeds.
  let path = marketDir() / "registry.json"
  if not fileExists(path): return
  try:
    let j = parseFile(path)
    if j{"source"}.getStr != marketRegistrySource: return
    var files: seq[tuple[name, text: string]]
    for e in j{"entries"}:
      files.add((e{"id"}.getStr & ".json", $e))
    discard applyRegistry($(%*{"format": j{"format"}.getInt(1)}), files, j{"commit"}.getStr,
                          j{"fetchedAt"}.getFloat, live = false)
  except CatchableError:
    discard

proc readLocalRegistry(dir: string): string =
  ## `--mod-registry <folder>`: a checkout of the registry, read in place.
  var files: seq[tuple[name, text: string]]
  var registryText = ""
  try:
    registryText = readFile(dir / "registry.json")
    for kind, path in walkDir(dir / "mods"):
      if kind == pcFile and path.endsWith(".json"):
        files.add((lastPathPart(path), readFile(path)))
  except OSError, IOError:
    return "cannot read the registry folder " & dir & ": " & getCurrentExceptionMsg()
  applyRegistry(registryText, files, "", epochTime(), live = true)

# ----------------------------------------------------------------- worker ----
type
  JobKind = enum jkRegistry, jkInstall

  MarketJob = object
    ## Shared with the worker: inputs set before createThread, outputs read
    ## after joinThread; only the atomics are touched while it runs.
    kind: JobKind
    url, zipPath, stageDir, userAgent: string
    entry: MarketEntry
    received, total: Atomic[int]
    cancel, finished: Atomic[bool]
    failure: MarketFailure
    detail: string
    warnings: seq[string]
    registryText, registryCommit: string
    files: seq[tuple[name, text: string]]

var
  job: MarketJob
  worker: Thread[ptr MarketJob]
  running: bool
  queue: seq[tuple[kind: JobKind, entry: MarketEntry]]

proc failureOf(e: TlsError): MarketFailure =
  case e
  of tlsOk: mfHttp
  of tlsNetwork: mfNetwork
  of tlsTimeout: mfTimeout
  of tlsCancelled: mfCancelled
  of tlsCertificate: mfCertificate
  of tlsClock: mfClock
  of tlsProtocol: mfProtocol

proc download(j: var MarketJob): bool =
  createDir(parentDir(j.zipPath))
  let r = httpsGetToFile(j.url, j.zipPath, addr j.received, addr j.total, addr j.cancel, j.userAgent)
  if r.ok: return true
  j.failure = failureOf(r.error)
  j.detail = r.detail
  false

proc openArchive(j: var MarketJob, z: var ZipArchive): bool =
  let err = readZip(j.zipPath, z)
  if err.len > 0:
    j.failure = mfArchive
    j.detail = err
  err.len == 0

proc runRegistryJob(j: var MarketJob) =
  if not j.download(): return
  var z: ZipArchive
  if not j.openArchive(z): return
  j.registryCommit = z.comment.strip
  let top = z.topFolder
  for e in z.entries:
    if e.isDir or e.isSymlink or not e.name.startsWith(top): continue
    let rel = e.name[top.len .. ^1]
    let inMods = rel.startsWith("mods/") and rel.endsWith(".json") and rel.count('/') == 1
    if rel != "registry.json" and not inMods: continue
    var text: string
    let err = z.readEntry(e, text)
    if err.len > 0:
      j.failure = mfArchive
      j.detail = err
      return
    if inMods: j.files.add((rel["mods/".len .. ^1], text))
    else: j.registryText = text
  if j.registryText.len == 0:
    j.failure = mfArchive
    j.detail = "the archive has no registry.json"
  discard tryRemoveFile(j.zipPath)

proc runInstallJob(j: var MarketJob) =
  if not j.download(): return
  var z: ZipArchive
  if not j.openArchive(z): return
  if z.comment.strip != j.entry.commit:
    j.failure = mfMismatch
    j.detail = "the archive is commit \"" & z.comment.strip & "\", the registry lists " & j.entry.commit
    return
  let top = z.topFolder
  if top.len == 0:
    j.failure = mfArchive
    j.detail = "unexpected archive layout"
    return
  let prefix = top & (if j.entry.path.len > 0: j.entry.path & "/" else: "")
  let at = z.findEntry(prefix & "mod.json")
  if at < 0:
    j.failure = mfMismatch
    j.detail = "no mod.json in " & (if j.entry.path.len > 0: j.entry.path else: "the repository's root")
    return
  var text: string
  var err = z.readEntry(z.entries[at], text)
  if err.len > 0:
    j.failure = mfArchive
    j.detail = err
    return
  var id = ""
  try:
    id = parseJson(text){"id"}.getStr
  except CatchableError:
    discard
  if id != j.entry.id:
    j.failure = mfMismatch
    j.detail = "its mod.json says id \"" & id & "\", the registry lists \"" & j.entry.id & "\""
    return
  removeDir(j.stageDir)
  createDir(j.stageDir / "mod")
  err = z.extractTree(prefix, j.stageDir / "mod", j.warnings, addr j.cancel)
  if err.len > 0:
    j.failure = if j.cancel.load: mfCancelled else: mfArchive
    j.detail = err
    return
  # Written last: a staged copy without it is unfinished.
  writeFile(j.stageDir / "stage.json", $(%*{"repo": j.entry.repo, "commit": j.entry.commit,
                                            "path": j.entry.path, "version": j.entry.version}))
  discard tryRemoveFile(j.zipPath)

proc marketWorker(j: ptr MarketJob) {.thread.} =
  try:
    case j.kind
    of jkRegistry: runRegistryJob(j[])
    of jkInstall: runInstallJob(j[])
  except CatchableError as e:
    if j.failure == mfNone:
      j.failure = mfDisk
      j.detail = e.msg
  j.finished.store(true)

proc startNext() =
  if running or queue.len == 0: return
  let (kind, entry) = queue[0]
  queue.delete(0)
  job.kind = kind
  job.entry = entry
  job.failure = mfNone
  job.detail = ""
  job.warnings = @[]
  job.registryText = ""
  job.registryCommit = ""
  job.files = @[]
  job.received.store(0)
  job.total.store(-1)
  job.cancel.store(false)
  job.finished.store(false)
  job.userAgent = "TopHatShooterOS/" & GameVersion
  case kind
  of jkRegistry:
    job.url = marketRegistrySource
    job.zipPath = downloadRoot() / "registry.zip"
    job.stageDir = ""
  of jkInstall:
    job.url = marketArchiveUrl(entry)
    job.zipPath = downloadRoot() / entry.id & ".zip"
    job.stageDir = stagingRoot() / entry.id
  createThread(worker, marketWorker, addr job)
  running = true

# ------------------------------------------------------------- installing ----
proc copyLoaded(id: string): bool =
  for m in installedMods:
    if m.id == id and m.status == msLoaded: return true
  false

proc renameDir(src, dst: string) =
  ## Rename a folder or raise. Not moveDir: when Windows refuses a rename (a
  ## file inside is open) it falls back to copying and deleting, which can
  ## leave half a mod behind. moveFile only ever renames on Windows, and
  ## rename(2) moves folders elsewhere; every move here stays under the data
  ## root, so on one volume.
  moveFile(src, dst)

proc swapStaged(id: string): string =
  ## Move a complete staged install into the mods folder (main thread). Every
  ## copy of the mod already there goes first (to marketplace/trash, then
  ## deleted): the old marketplace install, or the copy the player agreed to
  ## replace. On a failure what moved is put back. "" or the error.
  let stage = stagingRoot() / id
  var meta: JsonNode
  try:
    meta = parseFile(stage / "stage.json")
  except CatchableError:
    return "the downloaded copy of " & id & " is incomplete"
  var copies: seq[string]
  for m in scanMods(@[]):
    if m.id != id: continue
    if normalizedPath(parentDir(m.dir)) != normalizedPath(modsRootDir()):
      return "remove your copy of " & id & " in " & m.dir & " first"   # (portable mods folder)
    copies.add(m.dir)
  let stamp = $int64(epochTime() * 1000)
  var moved: seq[tuple[src, dst: string]]
  template putBack() =
    for (src, dst) in moved:
      try: renameDir(dst, src)
      except OSError, IOError: discard
  for i, dir in copies:
    let dst = trashRoot() / id & "-" & stamp & "-" & $i
    try:
      createDir(trashRoot())
      renameDir(dir, dst)
      moved.add((dir, dst))
    except OSError, IOError:
      putBack()
      return "cannot replace " & dir & " (is a file in it open?): " & getCurrentExceptionMsg()
  var target = modsRootDir() / id
  var n = 2
  while dirExists(target) or fileExists(target):   # that name holds something else
    target = modsRootDir() / id & "_" & $n
    inc n
  try:
    renameDir(stage / "mod", target)
  except OSError, IOError:
    putBack()
    return "cannot install into " & target & ": " & getCurrentExceptionMsg()
  var kept: seq[MarketRecord]
  for r in records:
    if r.id != id: kept.add(r)
  records = kept
  records.add(MarketRecord(id: id, folder: lastPathPart(target), repo: meta{"repo"}.getStr,
                           commit: meta{"commit"}.getStr, path: meta{"path"}.getStr,
                           version: meta{"version"}.getStr))
  saveRecords()
  var leftovers = @[stage]
  for m in moved: leftovers.add(m.dst)
  for dir in leftovers:
    try: removeDir(dir)
    except OSError, IOError: discard   # cleaned at the next start
  ""

proc applyStagedMarketInstalls*() =
  ## reloadMods, between tearing the old mods down and scanning the folders:
  ## swap in every finished download (the old copies' files are closed now).
  let root = stagingRoot()
  if not dirExists(root): return
  for kind, path in walkDir(root):
    if kind != pcDir: continue
    let id = lastPathPart(path)
    if running and job.kind == jkInstall and job.entry.id == id: continue   # still being written
    if not fileExists(path / "stage.json"): continue
    let err = swapStaged(id)
    if err.len > 0: modLogAdd(mlError, LogTag, err)
    else: modLogAdd(mlInfo, LogTag, "installed " & id)

proc finishInstall(): MarketEvent =
  let e = job.entry
  result = MarketEvent(entry: e, failure: job.failure, detail: job.detail)
  for m in installedMods:
    if m.id == e.id: result.wasInstalled = true
  let stage = stagingRoot() / e.id
  if job.failure != mfNone:
    modLogAdd(mlError, LogTag, e.id & ": " & job.detail)
    try: removeDir(stage)
    except OSError, IOError: discard
    result.kind = meInstallFailed
    return
  if not dirExists(stage / "mod"):   # a reload already swapped it in
    result.kind = meInstalled
    return
  if copyLoaded(e.id):
    # Its files stay open until the mods reload, which swaps it in.
    modReloadRequested = true
    result.kind = meStaged
    return
  let err = swapStaged(e.id)
  if err.len > 0:
    modLogAdd(mlError, LogTag, err)
    result.kind = meInstallFailed
    result.failure = mfDisk
    result.detail = err
  else:
    modLogAdd(mlInfo, LogTag, "installed " & e.id & " " & e.version & " (" & e.commit[0 ..< 7] & ")")
    result.kind = meInstalled

proc finishRegistry(): MarketEvent =
  if job.failure != mfNone:
    modLogAdd(mlError, LogTag, "the mod list could not be fetched: " & job.detail)
    return MarketEvent(kind: meListFailed, failure: job.failure, detail: job.detail)
  let err = applyRegistry(job.registryText, job.files, job.registryCommit, epochTime(), live = true)
  if err.len > 0:
    modLogAdd(mlError, LogTag, err)
    return MarketEvent(kind: meListFailed, failure: mfArchive, detail: err)
  MarketEvent(kind: meListUpdated)

# -------------------------------------------------------------------- API ----
proc initMarketplace*(registry = "") =
  ## Startup, before the first reloadMods: clear what a session that ended
  ## mid-way left (partial downloads and staging, replaced copies), then read
  ## the install records and the cached list. Finished staged installs stay:
  ## the first reloadMods swaps them in.
  if registry.len > 0: marketRegistrySource = registry
  try:
    removeDir(downloadRoot())
    removeDir(trashRoot())
    if dirExists(stagingRoot()):
      for kind, path in walkDir(stagingRoot()):
        if not fileExists(path / "stage.json"): removeDir(path)
  except OSError, IOError:
    discard
  loadRecords()
  loadRegistryCache()

proc marketListLoading*(): bool =
  (running and job.kind == jkRegistry) or (queue.len > 0 and queue[0].kind == jkRegistry)

proc marketRefresh*() =
  ## Fetch the list again (in the background; pollMarket reports it).
  if not marketRegistrySource.startsWith("https://"):
    let err = readLocalRegistry(marketRegistrySource)
    if err.len > 0:
      modLogAdd(mlError, LogTag, err)
      pendingEvents.add(MarketEvent(kind: meListFailed, failure: mfDisk, detail: err))
    else:
      pendingEvents.add(MarketEvent(kind: meListUpdated))
    return
  if marketListLoading(): return
  queue.insert((jkRegistry, MarketEntry()), 0)
  startNext()

proc marketQueued*(id: string): bool =
  for q in queue:
    if q.kind == jkInstall and q.entry.id == id: return true
  false

proc marketBusy*(id: string): bool =
  ## Downloading or waiting to.
  (running and job.kind == jkInstall and job.entry.id == id) or marketQueued(id)

proc marketProgress*(id: string): tuple[active: bool, received, total: int] =
  ## The running download of `id`: bytes so far and the size (-1 unknown).
  if running and job.kind == jkInstall and job.entry.id == id:
    (true, job.received.load, job.total.load)
  else:
    (false, 0, -1)

proc marketInstall*(e: MarketEntry) =
  ## Download and install (or update) `e`: queued behind the running job.
  if marketBusy(e.id): return
  queue.add((jkInstall, e))
  startNext()

proc marketCancel*(id: string) =
  if running and job.kind == jkInstall and job.entry.id == id:
    job.cancel.store(true)
  for i in countdown(queue.high, 0):
    if queue[i].kind == jkInstall and queue[i].entry.id == id: queue.delete(i)

proc pollMarket*(): seq[MarketEvent] =
  ## Every desktop frame (main thread): finished jobs become events (and
  ## installs are swapped in), the next queued job starts.
  result = pendingEvents
  pendingEvents = @[]
  if running and job.finished.load:
    joinThread(worker)
    running = false
    for w in job.warnings: modLogAdd(mlWarn, LogTag, job.entry.id & ": " & w)
    result.add(if job.kind == jkRegistry: finishRegistry() else: finishInstall())
  startNext()

proc shutdownMarketplace*() =
  ## On exit: stop the download in progress (it is cleaned at the next start).
  queue = @[]
  if running:
    job.cancel.store(true)
    joinThread(worker)
    running = false
