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

# Colour helpers shared by every renderer. A straight blend (alpha included)
# is raylib's colorLerp; these cover what it does not.

proc rgba*(r, g, b: int, a = 255): Color {.inline.} =
  ## A colour from int channels, each clamped to 0..255.
  Color(r: clampByte(r), g: clampByte(g), b: clampByte(b), a: clampByte(a))

proc rgba*(r, g, b: int, a: float32): Color {.inline.} =
  ## The same with a float alpha (0..255, clamped), for an alpha that is worked out.
  Color(r: clampByte(r), g: clampByte(g), b: clampByte(b), a: clampByteF(a))

proc scaleAlpha*(c: Color, k: float32): Color {.inline.} =
  ## `c` faded to `k` (0..1) of its own alpha: relative to the tint, so an
  ## already translucent colour fades from where it is, never brightens.
  withAlpha(c, c.a.float32 * clamp(k, 0.0'f32, 1.0'f32))

proc lerpRgb*(c, target: Color, t: float32): Color {.inline.} =
  ## `c` pulled `t` of the way to `target` in RGB, keeping c's own alpha.
  withAlpha(colorLerp(c, target, t), c.a)

proc clearOf*(c: Color): Color {.inline.} =
  ## `c` fully transparent: the far end of a fade-out gradient keeps its tint,
  ## so the blend never greys on the way.
  withAlpha(c, 0'u8)

# Small maths shared by the procedural visuals

proc clamp01*(v: float32): float32 {.inline.} = clamp(v, 0.0'f32, 1.0'f32)

proc fract01*(v: float32): float32 {.inline.} = v - floor(v)

proc wrapCoord*(value, limit: float32): float32 {.inline.} =
  ## `value` wrapped into 0 ..< `limit` (0 when there is no range): a drifting
  ## position that loops round the screen or a tile.
  if limit <= 0.0'f32: return 0.0'f32
  value - floor(value / limit) * limit

proc hash01*(seed: float32): float32 {.inline.} =
  ## Deterministic pseudo-random in [0,1): the same seed always gives the same
  ## value, so procedural staging is identical on every frame and playback.
  fract01(sin(seed * 12.9898'f32) * 43758.5453'f32)

proc smoothstep*(t: float32): float32 {.inline.} =
  ## Ease in and out over 0..1 (t is clamped).
  let x = clamp01(t)
  x * x * (3.0'f32 - 2.0'f32 * x)

proc smoothstep*(e0, e1, x: float32): float32 {.inline.} =
  ## 0 at e0, 1 at e1, eased in between.
  smoothstep((x - e0) / (e1 - e0))

proc easeOutCubic*(t: float32): float32 {.inline.} =
  ## Fast start, gentle landing over 0..1 (t is clamped).
  1.0'f32 - pow(1.0'f32 - clamp01(t), 3.0'f32)

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
