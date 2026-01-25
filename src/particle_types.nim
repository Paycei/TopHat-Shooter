import raylib, math

## PARTICLE TYPE DEFINITIONS
## This file contains only type definitions for particles to avoid circular dependencies.
## Separated from particle.nim and particle_pool.nim to allow types.nim to import it.

type
  Vector2f* = object
    x*, y*: float32

# Vector2f utility functions
proc newVector2f*(x, y: float32): Vector2f =
  result.x = x
  result.y = y

proc `+`*(a, b: Vector2f): Vector2f =
  newVector2f(a.x + b.x, a.y + b.y)

proc `-`*(a, b: Vector2f): Vector2f =
  newVector2f(a.x - b.x, a.y - b.y)

proc `*`*(a: Vector2f, s: float32): Vector2f =
  newVector2f(a.x * s, a.y * s)

proc length*(v: Vector2f): float32 =
  sqrt(v.x * v.x + v.y * v.y)

proc normalize*(v: Vector2f): Vector2f =
  let l = v.length()
  if l > 0:
    newVector2f(v.x / l, v.y / l)
  else:
    newVector2f(0, 0)

proc distance*(a, b: Vector2f): float32 =
  (b - a).length()

# Particle types
type
  Particle* = ref object
    pos*: Vector2f
    vel*: Vector2f
    color*: Color
    lifetime*: float32
    maxLifetime*: float32
    size*: float32

  ParticlePool* = ref object
    particles*: seq[Particle]     # Pre-allocated particle objects
    activeCount*: int              # Number of currently active particles
    maxCapacity*: int              # Maximum pool size
