## One vector type per dimension: raylib's Vector2 and Vector3, with naylib's
## raymath for the maths (`+`, `-`, `*`, `/`, length, normalize, distance,
## dotProduct, crossProduct, lerp, rotate...). The game used to keep its own
## Vector2f and Vector3f (and cube_render a CubePoint), each with a copy of the
## same operators and a hand-written conversion at every raylib call.
##
## raymath's functions are raylib's C ones, declared `inline` in raymath.h
## (rcore.c provides the out-of-line copies), so the C compiler inlines them.

import raylib, raymath
export raymath   # (which re-exports Vector2, Vector3 and Vector4)

func vec2*(x, y: float32): Vector2 {.inline.} = Vector2(x: x, y: y)
func vec3*(x, y, z: float32): Vector3 {.inline.} = Vector3(x: x, y: y, z: z)
