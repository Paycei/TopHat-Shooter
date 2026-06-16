## Best-effort, fast hardware detection for the BIOS splash.
##
## Constraint: this runs during startup, so it must NOT spawn processes
## (`wmic` / PowerShell would each add hundreds of milliseconds). Everything
## here is an in-process registry read or syscall , all sub-millisecond , so
## detection runs synchronously when the splash is built. Any field that can't
## be read is left empty and the splash substitutes a themed placeholder, so the
## BIOS screen always looks complete.
##
## Windows is the primary platform (registry + two kernel32 syscalls). Linux
## reads `/proc`. Anything else falls back entirely to the themed placeholders.

import std/[strutils, cpuinfo, os]

when defined(windows):
  import std/registry

type
  HardwareInfo* = object
    cpuName*: string      ## e.g. "Intel Core i7-10700K @ 3.80GHz" ("" if unknown)
    logicalCores*: int    ## hardware threads (0 if unknown)
    ramMB*: int           ## total physical RAM in MB (0 if unknown)
    gpuName*: string      ## primary display adapter ("" if unknown)
    diskTotalGB*: int     ## system volume capacity in GB (0 if unknown)
    diskFreeGB*: int      ## system volume free space in GB (0 if unknown)
    hostName*: string     ## machine name ("" if unknown)
    osName*: string       ## OS product name ("" if unknown)

# ---------------------------------------------------------------------------
# Windows: the only two raw FFI calls we need. Strings come from std/registry,
# which handles the WideCString marshalling and the predefined-HKEY constants.

when defined(windows):
  type
    MEMORYSTATUSEX {.bycopy.} = object
      dwLength: uint32
      dwMemoryLoad: uint32
      ullTotalPhys: uint64
      ullAvailPhys: uint64
      ullTotalPageFile: uint64
      ullAvailPageFile: uint64
      ullTotalVirtual: uint64
      ullAvailVirtual: uint64
      ullAvailExtendedVirtual: uint64

  proc globalMemoryStatusEx(p: ptr MEMORYSTATUSEX): int32
    {.stdcall, dynlib: "kernel32", importc: "GlobalMemoryStatusEx".}
  proc getDiskFreeSpaceExA(dir: cstring; freeAvail, total, totalFree: ptr uint64): int32
    {.stdcall, dynlib: "kernel32", importc: "GetDiskFreeSpaceExA".}

  proc regRead(path, key: string): string =
    ## HKLM string value, or "" if the key/value is missing.
    try: getUnicodeValue(path, key, HKEY_LOCAL_MACHINE).strip()
    except CatchableError: ""

  proc gpuScore(name: string): int =
    ## When several adapters are registered (iGPU + dGPU + the basic fallback),
    ## prefer the one a player would call "their GPU".
    let n = name.toLowerAscii
    if "basic display" in n or "remote" in n or "mirror" in n: 0
    elif "geforce" in n or "nvidia" in n or "rtx" in n or "gtx" in n: 5
    elif "radeon" in n or "rx " in n: 4
    elif "arc" in n or "amd" in n: 3
    elif "intel" in n: 2
    else: 1

  proc detectGpu(): string =
    ## Display-adapter class key; subkeys 0000.. are the installed adapters.
    const cls = r"SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}"
    var best = ""
    var bestScore = -1
    for i in 0..7:
      let desc = regRead(cls & "\\" & align($i, 4, '0'), "DriverDesc")
      if desc.len == 0: continue
      if gpuScore(desc) > bestScore:
        bestScore = gpuScore(desc)
        best = desc
    best

proc cleanCpuName(s: string): string =
  ## Strip the noisy "(R)"/"(TM)"/"CPU" decorations Intel bakes into the brand
  ## string so the BIOS line reads cleanly.
  result = s.multiReplace(("(R)", ""), ("(r)", ""), ("(TM)", ""), ("(tm)", ""),
                          ("(C)", ""), (" CPU @", " @"))
  while "  " in result: result = result.replace("  ", " ")
  result = result.strip()

proc detectHardware(): HardwareInfo =
  result.logicalCores = countProcessors()
  when defined(windows):
    result.cpuName = cleanCpuName(
      regRead(r"HARDWARE\DESCRIPTION\System\CentralProcessor\0", "ProcessorNameString"))

    var ms = MEMORYSTATUSEX(dwLength: uint32(sizeof(MEMORYSTATUSEX)))
    if globalMemoryStatusEx(addr ms) != 0:
      result.ramMB = int(ms.ullTotalPhys div (1024'u64 * 1024'u64))

    result.gpuName = detectGpu()

    var freeAvail, total, totalFree: uint64
    if getDiskFreeSpaceExA("C:\\".cstring, addr freeAvail, addr total, addr totalFree) != 0:
      result.diskTotalGB = int(total div 1073741824'u64)
      result.diskFreeGB  = int(totalFree div 1073741824'u64)

    let prod = regRead(r"SOFTWARE\Microsoft\Windows NT\CurrentVersion", "ProductName")
    let disp = regRead(r"SOFTWARE\Microsoft\Windows NT\CurrentVersion", "DisplayVersion")
    result.osName   = (prod & " " & disp).strip()
    result.hostName = getEnv("COMPUTERNAME")

  elif defined(linux):
    try:
      for line in lines("/proc/cpuinfo"):
        if line.startsWith("model name") and result.cpuName.len == 0:
          let parts = line.split(":", 1)
          if parts.len > 1: result.cpuName = parts[1].strip()
          break
    except CatchableError: discard
    try:
      for line in lines("/proc/meminfo"):
        if line.startsWith("MemTotal"):
          let f = line.splitWhitespace()
          if f.len > 1:
            try: result.ramMB = parseInt(f[1]) div 1024  # MemTotal is in kB
            except ValueError: discard
          break
    except CatchableError: discard
    result.hostName = getEnv("HOSTNAME")

  else:
    discard  # other platforms: themed placeholders only

var gCache: HardwareInfo
var gCached = false

proc getHardwareInfo*(): HardwareInfo =
  ## Cached: hardware doesn't change mid-run, so detection happens exactly once.
  if not gCached:
    gCache = detectHardware()
    gCached = true
  gCache
