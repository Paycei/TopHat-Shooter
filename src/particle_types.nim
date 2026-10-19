import raylib
import vec
export vec

## PARTICLE TYPE DEFINITIONS
## This file contains only type definitions for particles to avoid circular dependencies.
## Separated from particle.nim and particle_pool.nim to allow types.nim to import it.

type
  ParticleStyle* = enum
    psSoft,     ## Round glowing puff used for general energy/smoke
    psSpark,    ## Thin streak used for impacts and electrical accents
    psEmber,    ## Heavier glowing ember with a softer fade
    psShard     ## Angular fragment used for debris/shrapnel

  ParticleLayer* = enum
    plBackground,
    plForeground

# Particle types
type
  Particle* = object
    pos*: Vector2
    vel*: Vector2
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
