## Zip archives as GitHub serves them (`git archive --format=zip`): the mod
## marketplace's registry and mod downloads. Read straight from the file
## (seek + read, never loaded whole), DEFLATE through raylib's own decoder
## (`sinflate`, compiled into the exe with raylib's compression API), every
## entry checked against its CRC-32 (raylib's ComputeCRC32). naylib leaves
## that API unbound on purpose (it points at Nim packages the game does not
## use), so the two C functions are declared here.
##
## git writes the commit id as the archive comment and the sizes only in the
## central directory (its local headers use data descriptors), so the central
## directory is what is read. Zip64 and encryption are refused: git never
## writes them for a mod-sized repository.
##
## Runs on the marketplace's worker thread: no globals, nothing moddable.

import std/[os, strutils, atomics]
import raylib   # (for its C: sinflate and ComputeCRC32 are compiled with raylib)

# With their real headers: a prototype of our own would clash in any C file
# that also includes raylib.h. (raylib's folder is on every file's include path.)
proc sinflate(dst: pointer, cap: cint, src: pointer, size: cint): cint {.
  importc: "sinflate", header: "external/sinfl.h".}
proc computeCrc32(data: pointer, size: cint): cuint {.importc: "ComputeCRC32", header: "raylib.h".}

type
  ZipEntry* = object
    name*: string        ## '/'-separated, as stored
    isDir*, isSymlink*: bool
    size*: int           ## uncompressed bytes
    compression: int
    crc: uint32
    compSize: int
    localOffset: int

  ZipArchive* = object
    path*: string
    entries*: seq[ZipEntry]
    comment*: string     ## git archive: the commit id

proc u16(s: string, at: int): int = ord(s[at]) or (ord(s[at + 1]) shl 8)
proc u32(s: string, at: int): int64 =
  int64(u16(s, at)) or (int64(u16(s, at + 2)) shl 16)

proc readAt(f: File, pos: int64, len: int, dest: var string): bool =
  dest.setLen(len)
  if len == 0: return true
  try:
    f.setFilePos(pos)
  except IOError:
    return false
  f.readBuffer(addr dest[0], len) == len

proc readZip*(path: string, archive: var ZipArchive): string =
  ## Read `path`'s directory into `archive`; "" on success, else what is wrong.
  archive = ZipArchive(path: path)
  var f: File
  if not open(f, path, fmRead): return "cannot open the archive"
  defer: f.close()
  let size = f.getFileSize
  if size < 22: return "not a zip archive"
  # The end-of-central-directory record: 22 bytes plus a comment of up to 64 KiB.
  let tailLen = int(min(size, 22 + 65535))
  var tail: string
  if not f.readAt(size - tailLen, tailLen, tail): return "cannot read the archive"
  var eocd = -1
  for i in countdown(tailLen - 22, 0):
    if tail[i] == 'P' and tail[i + 1] == 'K' and tail[i + 2] == '\5' and tail[i + 3] == '\6' and
       i + 22 + u16(tail, i + 20) == tailLen:
      eocd = i
      break
  if eocd < 0: return "not a zip archive"
  let count = u16(tail, eocd + 10)
  let cdSize = u32(tail, eocd + 12)
  let cdOffset = u32(tail, eocd + 16)
  archive.comment = tail[eocd + 22 ..< tailLen]
  if count == 0xFFFF or cdSize == 0xFFFFFFFF'i64 or cdOffset == 0xFFFFFFFF'i64:
    return "Zip64 archives are not supported"
  if cdOffset + cdSize > size: return "the archive is truncated"
  var cd: string
  if not f.readAt(cdOffset, int(cdSize), cd): return "cannot read the archive"
  var at = 0
  for n in 0 ..< count:
    if at + 46 > cd.len or cd[at ..< at + 4] != "PK\1\2": return "damaged central directory"
    let madeBy = u16(cd, at + 4)
    let flags = u16(cd, at + 8)
    var e = ZipEntry(compression: u16(cd, at + 10), crc: uint32(u32(cd, at + 16)),
                     compSize: int(u32(cd, at + 20)), size: int(u32(cd, at + 24)),
                     localOffset: int(u32(cd, at + 42)))
    let nameLen = u16(cd, at + 28)
    let extraLen = u16(cd, at + 30)
    let commentLen = u16(cd, at + 32)
    let attrs = u32(cd, at + 38)
    if at + 46 + nameLen > cd.len: return "damaged central directory"
    e.name = cd[at + 46 ..< at + 46 + nameLen]
    if (flags and 1) != 0: return "encrypted archives are not supported"
    if e.size == 0xFFFFFFFF or e.compSize == 0xFFFFFFFF or e.localOffset == 0xFFFFFFFF:
      return "Zip64 archives are not supported"
    e.isDir = e.name.endsWith("/")
    e.isSymlink = (madeBy shr 8) == 3 and ((attrs shr 16) and 0xF000) == 0xA000   # Unix S_IFLNK
    archive.entries.add(e)
    at += 46 + nameLen + extraLen + commentLen
  ""

proc readEntryFrom(f: File, e: ZipEntry, data: var string): string =
  if e.size > high(int32) or e.compSize > high(int32): return e.name & ": too large"
  var local: string
  if not f.readAt(e.localOffset, 30, local) or local[0 ..< 4] != "PK\3\4":
    return e.name & ": damaged entry"
  let start = int64(e.localOffset) + 30 + u16(local, 26) + u16(local, 28)
  var comp: string
  if not f.readAt(start, e.compSize, comp): return e.name & ": the archive is truncated"
  case e.compression
  of 0:
    if e.compSize != e.size: return e.name & ": damaged entry"
    data = move comp
  of 8:
    if e.compSize == 0 and e.size > 0: return e.name & ": damaged entry"
    data = newString(e.size)
    if e.size > 0:
      # sinflate reports how much it wrote, also when it stopped at an error:
      # the size and the CRC below are what catch a damaged stream.
      let n = sinflate(addr data[0], cint(e.size), addr comp[0], cint(e.compSize))
      if n != e.size: return e.name & ": damaged data"
  else:
    return e.name & ": unsupported compression " & $e.compression
  let crc = if data.len == 0: 0'u32 else: uint32(computeCrc32(addr data[0], cint(data.len)))
  if crc != e.crc: return e.name & ": checksum mismatch"
  ""

proc readEntry*(archive: ZipArchive, e: ZipEntry, data: var string): string =
  ## An entry's bytes, checked against its size and CRC-32; "" on success.
  var f: File
  if not open(f, archive.path, fmRead): return "cannot open the archive"
  defer: f.close()
  readEntryFrom(f, e, data)

proc safeRelative*(name: string): bool =
  ## An archive path that stays inside the folder it is extracted to: no
  ## absolute paths, drive letters, backslashes or ".." parts.
  if name.len == 0 or name[0] == '/' or '\\' in name or ':' in name or '\0' in name: return false
  for part in name.split('/'):
    if part == "..": return false
  true

proc topFolder*(archive: ZipArchive): string =
  ## The folder every entry sits in, with its '/' ("repo-<commit>/" for
  ## GitHub), or "" if the entries do not share one.
  if archive.entries.len == 0: return ""
  let first = archive.entries[0].name
  let slash = first.find('/')
  if slash < 0: return ""
  result = first[0 .. slash]
  for e in archive.entries:
    if not e.name.startsWith(result): return ""

proc findEntry*(archive: ZipArchive, name: string): int =
  for i, e in archive.entries:
    if e.name == name: return i
  -1

proc extractTree*(archive: ZipArchive, prefix, destDir: string, warnings: var seq[string],
                  cancel: ptr Atomic[bool] = nil): string =
  ## Every entry under `prefix` (ending in '/') into `destDir`, keeping the
  ## layout under it; "" on success. Symlinks are skipped (with a warning):
  ## what they point at is not in the archive.
  var f: File
  if not open(f, archive.path, fmRead): return "cannot open the archive"
  defer: f.close()
  for e in archive.entries:
    if not e.name.startsWith(prefix) or e.name.len == prefix.len: continue
    if not cancel.isNil and cancel[].load: return "cancelled"
    let rel = e.name[prefix.len .. ^1]
    if not safeRelative(rel): return "unsafe path in the archive: " & e.name
    if e.isSymlink:
      warnings.add("skipped the symbolic link " & rel)
      continue
    let target = destDir / rel.strip(leading = false, chars = {'/'})
    try:
      if e.isDir:
        createDir(target)
        continue
      createDir(parentDir(target))
      var data: string
      let err = readEntryFrom(f, e, data)
      if err.len > 0: return err
      writeFile(target, data)
    except OSError, IOError:
      return "cannot write " & target & ": " & getCurrentExceptionMsg()
  ""
