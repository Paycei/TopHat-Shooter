## Shared utility helpers used across multiple modules.
## Only depends on the standard library and raylib, no game-state imports.

import raylib

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
