# Tests for the mod marketplace (src/modding/mod_market.nim), its zip reader
# (src/modding/mod_zip.nim) and its HTTPS client (src/network/).
#   nim r --mm:orc tests/test_market.nim             (offline)
#   nim r --mm:orc -d:online tests/test_market.nim   (also GitHub and badssl.com)
# Offline, archives are built here (raylib's own DEFLATE encoder) and the
# registry is a folder, as `--mod-registry <folder>` reads it; the data root
# is a fresh temp folder (APPDATA / HOME are redirected before anything runs).

import std/[os, strutils, json]
import ../src/save_system
import ../src/modding/[mod_zip, mod_market, mod_catalog]
when defined(online):
  import std/[atomics, times]
  import ../src/network/[https, tls]

var failures = 0
var passed = 0

proc check(cond: bool, name: string) =
  if cond: inc passed
  else:
    echo "FAIL ", name
    inc failures

let home = getTempDir() / "th_market_test_" & $getCurrentProcessId()
removeDir(home)
createDir(home)
putEnv("HOME", home)
putEnv("APPDATA", home)   # what getRootDataPath reads on Windows
let root = getRootDataPath()
let marketRoot = root / "marketplace"
let scratch = home / "scratch"
createDir(scratch)

# ----------------------------------------------------------- zip writing ----
proc compressData(data: pointer, size: cint, outSize: ptr cint): ptr uint8 {.
  importc: "CompressData", header: "raylib.h".}
proc memFree(p: pointer) {.importc: "MemFree", header: "raylib.h".}
proc crc32(data: pointer, size: cint): cuint {.importc: "ComputeCRC32", header: "raylib.h".}

type TestEntry = tuple[name, data: string, deflate, symlink: bool]

proc le16(v: int): string = char(v and 0xFF) & char((v shr 8) and 0xFF)
proc le32(v: int64): string = le16(int(v and 0xFFFF)) & le16(int((v shr 16) and 0xFFFF))

proc buildZip(path: string, entries: openArray[TestEntry], comment = "", zip64 = false) =
  ## A zip as git writes one: Unix "made by", sizes in the central directory.
  var body, cd = ""
  for e in entries:
    var stored = e.data
    var meth = 0
    if e.deflate and e.data.len > 0:
      var n: cint
      let p = compressData(unsafeAddr e.data[0], cint(e.data.len), addr n)
      stored = newString(int(n))
      copyMem(addr stored[0], p, int(n))
      memFree(p)
      meth = 8
    let crc = if e.data.len == 0: 0'i64 else: int64(crc32(unsafeAddr e.data[0], cint(e.data.len)))
    let isDir = e.name.endsWith("/")
    let mode = if e.symlink: 0xA1FF else: (if isDir: 0x41ED else: 0x81A4)
    let offset = body.len
    body.add("PK\3\4" & le16(20) & le16(0) & le16(meth) & le16(0) & le16(0) & le32(crc) &
             le32(stored.len) & le32(e.data.len) & le16(e.name.len) & le16(0) & e.name & stored)
    cd.add("PK\1\2" & le16((3 shl 8) or 20) & le16(20) & le16(0) & le16(meth) & le16(0) & le16(0) &
           le32(crc) & le32(stored.len) & le32(e.data.len) & le16(e.name.len) & le16(0) & le16(0) &
           le16(0) & le16(0) & le32(int64(mode) shl 16) & le32(offset) & e.name)
  let count = if zip64: 0xFFFF else: entries.len
  writeFile(path, body & cd & "PK\5\6" & le16(0) & le16(0) & le16(count) & le16(count) &
            le32(cd.len) & le32(body.len) & le16(comment.len) & comment)

const Commit = "0123456789abcdef0123456789abcdef01234567"

# ------------------------------------------------------------- the reader ----
block zipRoundTrip:
  let big = "hello marketplace ".repeat(500)
  let path = scratch / "a.zip"
  buildZip(path, [(name: "repo-abc/", data: "", deflate: false, symlink: false),
                  (name: "repo-abc/mod.json", data: """{"id": "demo"}""", deflate: false, symlink: false),
                  (name: "repo-abc/main.lua", data: big, deflate: true, symlink: false),
                  (name: "repo-abc/sub/empty.txt", data: "", deflate: true, symlink: false),
                  (name: "repo-abc/link", data: "main.lua", deflate: false, symlink: true)],
           comment = Commit)
  var z: ZipArchive
  check(readZip(path, z) == "", "zip: reads")
  check(z.comment == Commit, "zip: the comment is the commit")
  check(z.entries.len == 5, "zip: every entry")
  check(z.topFolder == "repo-abc/", "zip: top folder")
  check(z.entries[z.findEntry("repo-abc/link")].isSymlink, "zip: symlink flagged")
  var data: string
  check(z.readEntry(z.entries[z.findEntry("repo-abc/main.lua")], data) == "" and data == big,
        "zip: deflate entry round-trips")
  check(z.readEntry(z.entries[z.findEntry("repo-abc/mod.json")], data) == "" and data == """{"id": "demo"}""",
        "zip: stored entry round-trips")
  var warnings: seq[string]
  let dest = scratch / "out"
  check(z.extractTree("repo-abc/", dest, warnings) == "", "zip: extracts")
  check(readFile(dest / "main.lua") == big and fileExists(dest / "sub" / "empty.txt"), "zip: files written")
  check(not fileExists(dest / "link") and warnings.len == 1, "zip: symlink skipped with a warning")

block zipDamage:
  var z: ZipArchive
  let path = scratch / "b.zip"
  buildZip(path, [(name: "t/a.txt", data: "abcdefgh".repeat(50), deflate: false, symlink: false)])
  var bytes = readFile(path)
  bytes[40] = 'X'   # inside the stored data
  writeFile(path, bytes)
  var data: string
  check(readZip(path, z) == "" and "checksum" in z.readEntry(z.entries[0], data), "zip: CRC mismatch caught")
  writeFile(path, bytes[0 ..< bytes.len - 30])
  check(readZip(path, z) != "", "zip: truncated archive refused")
  buildZip(path, [(name: "t/a.txt", data: "x", deflate: false, symlink: false)], zip64 = true)
  check("Zip64" in readZip(path, z), "zip: Zip64 refused")
  writeFile(path, "not a zip at all, just some text that is long enough")
  check(readZip(path, z) != "", "zip: garbage refused")
  for bad in ["t/../evil.txt", "t/a\\b.txt", "t/C:x.txt"]:
    buildZip(path, [(name: bad, data: "x", deflate: false, symlink: false)])
    var w: seq[string]
    check(readZip(path, z) == "" and z.extractTree("t/", scratch / "evil", w).startsWith("unsafe"),
          "zip: refuses " & bad)
  check(not fileExists(scratch / "evil.txt"), "zip: nothing escaped")
  check(not safeRelative("/abs") and not safeRelative("") and safeRelative("a/b.c"), "zip: safeRelative")

# ---------------------------------------------------------------- entries ----
proc entryText(id = "demo_mod", title = "Demo Mod", description = "A demo.",
               repo = "https://github.com/someone/demo-mod", commit = Commit,
               version = "1.2.0", path = ""): string =
  $(%*{"id": id, "title": title, "description": description, "repo": repo,
       "commit": commit, "version": version, "path": path})

proc entryErr(text: string, fileId = "demo_mod"): string =
  var e: MarketEntry
  parseMarketEntry(parseJson(text), fileId, e)

block entries:
  var e: MarketEntry
  check(parseMarketEntry(parseJson(entryText()), "demo_mod", e) == "" and e.owner == "someone",
        "entry: valid, owner from the repo")
  check(entryErr(entryText(path = "mods/demo")) == "", "entry: a subfolder path")
  check(entryErr(entryText(title = "Música ñandú")) == "", "entry: Latin-1 title")
  check(entryErr(entryText(id = "Demo")) != "", "entry: id charset")
  check(entryErr(entryText(), "other") != "", "entry: file name must match the id")
  check(entryErr(entryText(title = "x".repeat(49))) != "", "entry: title length")
  check(entryErr(entryText(title = "")) != "", "entry: empty title")
  check(entryErr(entryText(title = "Hat \u{1F3A9}")) != "", "entry: a character the font lacks")
  check(entryErr(entryText(description = "two\nlines")) != "", "entry: one-line description")
  check(entryErr(entryText(description = "d".repeat(241))) != "", "entry: description length")
  for repo in ["https://github.com/someone/demo.git", "https://github.com/someone/demo/",
               "https://gitlab.com/someone/demo", "http://github.com/someone/demo",
               "https://github.com/someone"]:
    check(entryErr(entryText(repo = repo)) != "", "entry: refuses repo " & repo)
  check(entryErr(entryText(commit = "abc123")) != "", "entry: short commit")
  check(entryErr(entryText(commit = Commit.toUpperAscii)) != "", "entry: uppercase commit")
  check(entryErr(entryText(version = "v1")) != "", "entry: version")
  for path in ["../x", "a//b", "/a", "a/", "a/./b"]:
    check(entryErr(entryText(path = path)) != "", "entry: refuses path " & path)
  check(entryErr("""{"id": 3}""") != "", "entry: wrong types")

# --------------------------------------------------------------- registry ----
let registry = home / "registry"
createDir(registry / "mods")
writeFile(registry / "registry.json", """{"format": 1}""")
writeFile(registry / "mods" / "zeta.json", entryText(id = "zeta", title = "Zeta",
          repo = "https://github.com/a/zeta"))
writeFile(registry / "mods" / "alpha.json", entryText(id = "alpha", title = "alpha",
          repo = "https://github.com/a/alpha"))
writeFile(registry / "mods" / "broken.json", "{ not json")
writeFile(registry / "mods" / "zzcopy.json", entryText(id = "zzcopy", title = "Copy",
          repo = "https://github.com/a/zeta"))   # the same repo + path as zeta (after it by name)

initMarketplace(registry)
block registryFolder:
  marketRefresh()
  let events = pollMarket()
  check(events.len == 1 and events[0].kind == meListUpdated, "registry: listed")
  check(marketEntries.len == 2, "registry: invalid and duplicate entries skipped")
  check(marketEntries.len == 2 and marketEntries[0].id == "alpha" and marketEntries[1].id == "zeta",
        "registry: sorted by title")
  check(marketListLive and marketListedAt > 0 and not marketRegistryTooNew, "registry: fresh")
  # the cached copy comes back on the next start, marked as not live
  initMarketplace(registry)
  check(marketEntries.len == 2 and not marketListLive, "registry: cached copy at start")
  writeFile(registry / "registry.json", """{"format": 2}""")
  marketRefresh()
  discard pollMarket()
  check(marketRegistryTooNew, "registry: a newer format is detected")
  writeFile(registry / "registry.json", """{"format": 1}""")
  marketRefresh()
  discard pollMarket()

# ------------------------------------------------- installs, state, swaps ----
proc stage(id: string, commit = Commit, files: openArray[(string, string)] = []) =
  ## What a finished download leaves (the network part is -d:online's).
  let dir = marketRoot / "staging" / id
  createDir(dir / "mod")
  writeFile(dir / "mod" / "mod.json", $(%*{"id": id, "version": "1.2.0"}))
  writeFile(dir / "mod" / "main.lua", "-- " & id)
  for (name, text) in files: writeFile(dir / "mod" / name, text)
  writeFile(dir / "stage.json", $(%*{"repo": "https://github.com/a/" & id, "commit": commit,
                                     "path": "", "version": "1.2.0"}))

proc entryFor(id: string, commit = Commit): MarketEntry =
  MarketEntry(id: id, title: id, repo: "https://github.com/a/" & id, commit: commit,
              version: "1.2.0", owner: "a")

let mods = modsRootDir()
block installs:
  rescanInstalledMods(@[])
  check(marketState(entryFor("alpha")) == mkNotInstalled, "state: not installed")
  stage("alpha")
  applyStagedMarketInstalls()
  rescanInstalledMods(@[])
  check(fileExists(mods / "alpha" / "main.lua") and not dirExists(marketRoot / "staging" / "alpha"),
        "install: swapped in, staging cleared")
  check(marketState(entryFor("alpha")) == mkCurrent, "state: current")
  check(marketState(entryFor("alpha", "f".repeat(40))) == mkUpdate, "state: another commit is an update")
  # an update replaces the folder
  let newer = "e".repeat(40)
  stage("alpha", newer, [("new.lua", "-- new")])
  applyStagedMarketInstalls()
  rescanInstalledMods(@[])
  check(fileExists(mods / "alpha" / "new.lua") and marketState(entryFor("alpha", newer)) == mkCurrent,
        "update: new files, new commit")
  var trashed = 0
  if dirExists(marketRoot / "trash"):
    for _ in walkDir(marketRoot / "trash"): inc trashed
  check(trashed == 0, "update: the old copy is gone")
  # the player's own copy (any folder name) is a local copy until replaced
  createDir(mods / "MyZeta")
  writeFile(mods / "MyZeta" / "mod.json", $(%*{"id": "zeta"}))
  writeFile(mods / "MyZeta" / "main.lua", "-- mine")
  rescanInstalledMods(@[])
  check(marketState(entryFor("zeta")) == mkLocalCopy, "state: local copy")
  var local: ModInfo
  for m in installedMods:
    if m.id == "zeta": local = m
  check(marketStateOf(local) == mkLocalCopy, "installed tab: local copy untagged")
  stage("zeta")
  applyStagedMarketInstalls()
  rescanInstalledMods(@[])
  check(not dirExists(mods / "MyZeta") and fileExists(mods / "zeta" / "main.lua") and
        marketState(entryFor("zeta")) == mkCurrent, "replace: the local copy makes way")
  # a folder named like the id that holds another mod is left alone
  createDir(mods / "gamma")
  writeFile(mods / "gamma" / "mod.json", $(%*{"id": "not_gamma"}))
  writeFile(mods / "gamma" / "main.lua", "")
  stage("gamma")
  applyStagedMarketInstalls()
  rescanInstalledMods(@[])
  check(dirExists(mods / "gamma") and fileExists(mods / "gamma_2" / "main.lua") and
        marketState(entryFor("gamma")) == mkCurrent, "install: next free folder name")
  # an unfinished staging (no stage.json) is never swapped in
  createDir(marketRoot / "staging" / "delta" / "mod")
  applyStagedMarketInstalls()
  check(not dirExists(mods / "delta"), "install: unfinished staging ignored")
  when defined(windows):
    # A file held open in the old copy: Windows refuses the rename; nothing changes.
    stage("alpha", Commit)
    var held: File
    discard open(held, mods / "alpha" / "new.lua", fmRead)
    applyStagedMarketInstalls()
    held.close()
    rescanInstalledMods(@[])
    check(fileExists(mods / "alpha" / "new.lua") and fileExists(marketRoot / "staging" / "alpha" / "stage.json") and
          marketState(entryFor("alpha", newer)) == mkCurrent, "swap: a refused rename changes nothing")
    applyStagedMarketInstalls()
    rescanInstalledMods(@[])
    check(not fileExists(mods / "alpha" / "new.lua") and marketState(entryFor("alpha")) == mkCurrent,
          "swap: retried once the file is closed")
  # records follow removals
  removeDir(mods / "zeta")
  rescanInstalledMods(@[])
  pruneMarketRecords()
  check(marketState(entryFor("zeta")) == mkNotInstalled, "records: a deleted folder is forgotten")
  forgetMarketInstall(mods / "gamma_2")
  rescanInstalledMods(@[])
  check(marketState(entryFor("gamma")) == mkLocalCopy, "records: forgetMarketInstall")
  # startup clears leftovers but keeps finished staging
  createDir(marketRoot / "trash" / "old")
  createDir(marketRoot / "download")
  writeFile(marketRoot / "download" / "x.zip", "partial")
  stage("omega")
  initMarketplace(registry)
  check(not dirExists(marketRoot / "trash") and not dirExists(marketRoot / "download") and
        not dirExists(marketRoot / "staging" / "delta") and
        fileExists(marketRoot / "staging" / "omega" / "stage.json"), "startup: leftovers cleared")

# ----------------------------------------------------------------- online ----
when defined(online):
  block https:
    check(rootCertificateCount() > 100, "tls: root certificates load")
    for (url, want) in [("https://expired.badssl.com/", tlsClock),
                        ("https://wrong.host.badssl.com/", tlsCertificate),
                        ("https://self-signed.badssl.com/", tlsCertificate),
                        ("https://untrusted-root.badssl.com/", tlsCertificate)]:
      let r = httpsGetToFile(url, scratch / "x.bin")
      check(not r.ok and r.error == want, "tls: refuses " & url & " (" & $r.error & ")")
    var cancel: Atomic[bool]
    cancel.store(true)
    let r = httpsGetToFile("https://codeload.github.com/Paycei/TopHat-Shooter/zip/" &
                           "ca1b6096430823d977d97c9931ab5b7bfbcd93f7", scratch / "c.zip", cancel = addr cancel)
    check(not r.ok and r.error == tlsCancelled, "https: cancel")

  block realInstall:
    # The game's own repository at a pushed commit: an example mod in a subfolder.
    let entry = MarketEntry(id: "hello_hud", title: "Hello HUD",
                            repo: "https://github.com/Paycei/TopHat-Shooter",
                            commit: "ca1b6096430823d977d97c9931ab5b7bfbcd93f7",
                            version: "1.2.0", path: "mods-sdk/examples/hello_hud", owner: "Paycei")
    rescanInstalledMods(@[])
    marketInstall(entry)
    var events: seq[MarketEvent]
    let t0 = epochTime()
    while events.len == 0 and epochTime() - t0 < 120:
      sleep(100)
      events = pollMarket()
    check(events.len == 1 and events[0].kind == meInstalled, "online: installed (" &
          (if events.len > 0: $events[0].kind & " " & events[0].detail else: "timeout") & ")")
    rescanInstalledMods(@[])
    check(fileExists(mods / "hello_hud" / "main.lua") and marketState(entry) == mkCurrent,
          "online: files and state")
    # a wrong commit for the path: the archive's comment must match
    var wrong = entry
    wrong.id = "wrong_id"
    marketInstall(wrong)
    events = @[]
    while events.len == 0 and epochTime() - t0 < 240:
      sleep(100)
      events = pollMarket()
    check(events.len == 1 and events[0].kind == meInstallFailed and events[0].failure == mfMismatch,
          "online: an id that does not match mod.json is refused")

shutdownMarketplace()
removeDir(home)
echo passed, " passed, ", failures, " failed"
if failures > 0: quit(1)
