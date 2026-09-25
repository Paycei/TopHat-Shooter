## Boss definition data types, split out of boss_definitions.nim so the
## per-mode roster (boss_definitions_modes.nim) can build definitions
## without importing the module that dispatches to it.

import raylib
import types

type
  BossAttackPattern* = enum
    bapSpiral,           # Shoots bullets in spiral
    bapBurst,            # Rapid burst fire
    bapWave,             # Wave pattern
    bapTargeted,         # Direct shots at player
    bapCircle,           # Circle of bullets
    bapLaser,            # Laser beams
    bapOrbit,            # Orbiting projectiles
    bapMeteor,           # Falling projectiles
    bapChain,            # Chain lightning
    bapPulse,            # Expanding pulse
    bapTeleport,         # Teleport then attack
    bapSummon,           # Spawn minions
    bapDash,             # Dash attack
    bapBarrage,          # Massive projectile barrage
    bapSnipe,            # Precise aimed shots
    bapMinionVolley      # Living Royal Guards fire at the player in unison (Summoner King)

  BossAttack* = object
    attackType*: BossAttackPattern
    damage*: float32
    cooldown*: float32
    timer*: float32
    projectileSpeed*: float32
    projectileCount*: int
    spreadAngle*: float32
    durationOrRadius*: float32
    bulletRadius*: float32     # Bullet size override (0 = use default 6)
    specialData*: string  # JSON-like data for special mechanics

  BossPhaseDefinition* = object
    name*: string
    hpThreshold*: float32      # Enters this phase when HP drops below this %
    speedMultiplier*: float32
    damageMultiplier*: float32
    defenseMultiplier*: float32
    attacks*: seq[BossAttack]
    color*: Color
    visualEffect*: string      # "glow", "aura", "shield", "pulse"
    specialBehavior*: string

  BossDefinition* = object
    name*: string
    bossID*: int
    baseHP*: float32
    baseSpeed*: float32
    baseDamage*: int
    baseRadius*: float32
    color*: Color
    phases*: seq[BossPhaseDefinition]
    description*: string
    weakPoint*: BossWeakPointDefinition
