## Shared utility helpers used across multiple modules.
## Only depends on the standard library and raylib, no game-state imports.

import raylib, std/[strutils, math]

# Version

proc readNimbleVersion(): string {.compileTime.} =
  ## The .nimble file is the single source of the version (tools/ship.ps1 reads
  ## it too), so nothing can be stamped with a stale number.
  for line in staticRead("../TopHatShooter.nimble").splitLines():
    let l = line.strip()
    if l.startsWith("version"):
      let parts = l.split('"')
      if parts.len >= 2:
        return parts[1]
  "unknown"

const GameVersion* = readNimbleVersion()

proc versionAtLeast*(have, want: string): bool =
  ## "1.12.0" against "1.9": part by part as numbers, a missing part being 0
  ## (and the digits a part starts with, so "2.0-beta" reads as 2.0).
  let a = have.split('.')
  let b = want.split('.')
  for i in 0 ..< max(a.len, b.len):
    var x, y = 0
    if i < a.len:
      for c in a[i]:
        if c notin Digits: break
        x = x * 10 + (ord(c) - ord('0'))
    if i < b.len:
      for c in b[i]:
        if c notin Digits: break
        y = y * 10 + (ord(c) - ord('0'))
    if x != y: return x > y
  true

# Enum parsing

proc parseEnumOr*[T: enum](s: string, default: T): T =
  ## Name-based enum parse (matches `$value` symbol names) that falls back to
  ## `default` instead of raising on unknown input. Replaces the hand-written
  ## `parseXType` string tables used by the save system.
  try:
    parseEnum[T](s)
  except ValueError:
    default

# Color channel clamping

proc clampByte*(value: int): uint8 =
  uint8(max(0, min(255, value)))

proc clampByteF*(value: float32): uint8 =
  uint8(clamp(value, 0.0'f32, 255.0'f32).int)

# Color constructors

proc withAlpha*(color: Color, alpha: int): Color =
  Color(r: color.r, g: color.g, b: color.b, a: clampByte(alpha))

proc withAlpha*(color: Color, alpha: uint8): Color =
  Color(r: color.r, g: color.g, b: color.b, a: alpha)

proc withAlpha*(color: Color, alpha: float32): Color =
  Color(r: color.r, g: color.g, b: color.b, a: clampByteF(alpha))

# Color brightness shifts (shared by player/particle/UI renderers)

proc brighten*(color: Color, amount: int, alpha: int = 255): Color =
  Color(
    r: clampByte(color.r.int + amount),
    g: clampByte(color.g.int + amount),
    b: clampByte(color.b.int + amount),
    a: clampByte(alpha)
  )

proc brighten*(color: Color, amount: float32): Color =
  ## Float overload that preserves the source alpha (used by particle blending).
  Color(
    r: clampByteF(color.r.float32 + amount),
    g: clampByteF(color.g.float32 + amount),
    b: clampByteF(color.b.float32 + amount),
    a: color.a
  )

proc darken*(color: Color, amount: int, alpha: int = 255): Color =
  Color(
    r: clampByte(color.r.int - amount),
    g: clampByte(color.g.int - amount),
    b: clampByte(color.b.int - amount),
    a: clampByte(alpha)
  )

# UI display

# COLORS
const Cyan* = Color(r: 0, g: 255, b: 255, a: 255)

# BALANCE DISPLAY MULTIPLIER
# This multiplier is applied to ALL health and damage values shown in the UI
const BALANCE_MULTIPLIER* = 100

proc formatHealthDisplay*(value: float32): string =
  ## Format health/damage value for display: multiply by 100 and round to nearest integer
  ## Example: 2.46 -> "246", 3.0 -> "300", 1.234 -> "123", 1.235 -> "124"
  let scaled = value * 100.0
  # Round to nearest integer
  result = $round(scaled).int
