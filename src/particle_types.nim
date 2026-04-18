import raylib, math

## PARTICLE TYPE DEFINITIONS
## This file contains only type definitions for particles to avoid circular dependencies.
## Separated from particle.nim and particle_pool.nim to allow types.nim to import it.

type
  Vector2f* = object
    x*, y*: float32

  ParticleStyle* = enum
    psSoft,     ## Round glowing puff used for general energy/smoke
    psSpark,    ## Thin streak used for impacts and electrical accents
    psEmber,    ## Heavier glowing ember with a softer fade
    psShard     ## Angular fragment used for debris/shrapnel

  ParticleLayer* = enum
    plBackground,
    plForeground

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
  Particle* = object
    pos*: Vector2f
    vel*: Vector2f
    color*: Color
    coreColor*: Color
    lifetime*: float32
    maxLifetime*: float32
    size*: float32
    startSize*: float32
    endSize*: float32
    drag*: float32
    gravity*: float32
    glow*: float32
    style*: ParticleStyle
    layer*: ParticleLayer
    rotation*: float32
    spin*: float32

  ParticlePool* = ref object
    particles*: seq[Particle]     # Packed particle data for cache-friendly updates
    activeCount*: int             # Number of currently active particles
    maxCapacity*: int             # Maximum pool size
    spawnedThisFrame*: int        # Tracks current-frame particle churn for adaptive throttling
