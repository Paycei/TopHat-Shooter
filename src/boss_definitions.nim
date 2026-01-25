## Boss Definitions System - Complete 60 Wave Boss List
## Allows complete customization of boss behavior, properties, attacks, and phases

import math, random, raylib

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
    bapSnipe             # Precise aimed shots

  BossAttack* = object
    attackType*: BossAttackPattern
    damage*: float32
    cooldown*: float32
    timer*: float32
    projectileSpeed*: float32
    projectileCount*: int
    spreadAngle*: float32
    durationOrRadius*: float32
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
    specialAbilities*: seq[string]
    description*: string

proc getBossDefinition*(bossNumber: int): BossDefinition =
  case bossNumber
  of 1:  # Wave 5 - THE SPIRAL GUARDIAN
    result = BossDefinition(
      name: "The Spiral Guardian",
      bossID: 1,
      baseHP: 125.0,  # NERFED from 150.0
      baseSpeed: 50.0,  # NERFED from 65.0
      baseDamage: 1,
      baseRadius: 45.0,
      color: Color(r: 100, g: 50, b: 200, a: 255),
      description: "A mystical entity that weaves spiraling bullet patterns",
      specialAbilities: @["spiral_master", "phase_shift"],
      phases: @[
        BossPhaseDefinition(
          name: "Awakening",
          hpThreshold: 1.0,
          speedMultiplier: 1.0,
          damageMultiplier: 1.0,
          defenseMultiplier: 0.85,
          color: Color(r: 100, g: 50, b: 200, a: 255),
          visualEffect: "pulse",
          specialBehavior: "circle_movement",
          attacks: @[
            BossAttack(
              attackType: bapSpiral,
              damage: 1.0,
              cooldown: 0.75,
              projectileSpeed: 160.0,
              projectileCount: 9,
              spreadAngle: 45.0,
              durationOrRadius: 0.0
            ),
            BossAttack(
              attackType: bapTargeted,
              damage: 1.0,
              cooldown: 1.75,
              projectileSpeed: 187.5,
              projectileCount: 3,
              spreadAngle: 20.0,
              durationOrRadius: 0.0
            )
          ]
        ),
        BossPhaseDefinition(
          name: "Spiral Rage",
          hpThreshold: 0.35,
          speedMultiplier: 0.975,
          damageMultiplier: 1.0,
          defenseMultiplier: 1.1,
          color: Color(r: 150, g: 30, b: 255, a: 255),
          visualEffect: "aura",
          specialBehavior: "aggressive",
          attacks: @[
            BossAttack(
              attackType: bapSpiral,
              damage: 1.0,
              cooldown: 1.0,
              projectileSpeed: 170.0,
              projectileCount: 10,
              spreadAngle: 30.0,
              durationOrRadius: 0.0
            ),
            BossAttack(
              attackType: bapCircle,
              damage: 1.0,
              cooldown: 3.0,
              projectileSpeed: 112.5,
              projectileCount: 10,
              spreadAngle: 360.0,
              durationOrRadius: 0.0
            ),
            BossAttack(
              attackType: bapTargeted,
              damage: 1.0,
              cooldown: 2.75,
              projectileSpeed: 195.0,
              projectileCount: 4,
              spreadAngle: 25.0,
              durationOrRadius: 0.0
            )
          ]
        )
      ]
    )
  
  of 2:  # Wave 10 - THE SUMMONER KING
    result = BossDefinition(
      name: "The Summoner King",
      bossID: 2,
      baseHP: 175.0,
      baseSpeed: 70.0,
      baseDamage: 1,
      baseRadius: 50.0,
      color: Color(r: 50, g: 150, b: 50, a: 255),
      description: "Commands an army of minions to overwhelm foes",
      specialAbilities: @["summon_master", "minion_empowerment"],
      phases: @[
        BossPhaseDefinition(
          name: "Legion's Call",
          hpThreshold: 1.0,
          speedMultiplier: 0.9,
          damageMultiplier: 1.0,
          defenseMultiplier: 0.9,
          color: Color(r: 50, g: 150, b: 50, a: 255),
          visualEffect: "shield",
          specialBehavior: "defensive",
          attacks: @[
            BossAttack(
              attackType: bapSummon,
              damage: 0.0,
              cooldown: 4.5,
              projectileSpeed: 0.0,
              projectileCount: 4,
              spreadAngle: 0.0,
              durationOrRadius: 0.0,
              specialData: "minion_circle"
            ),
            BossAttack(
              attackType: bapWave,
              damage: 1.0,
              cooldown: 2.75,
              projectileSpeed: 150.0,
              projectileCount: 5,
              spreadAngle: 50.0,
              durationOrRadius: 0.0
            )
          ]
        ),
        BossPhaseDefinition(
          name: "Swarm Commander",
          hpThreshold: 0.6,
          speedMultiplier: 1.0,
          damageMultiplier: 1.2,
          defenseMultiplier: 0.8,
          color: Color(r: 30, g: 200, b: 30, a: 255),
          visualEffect: "glow",
          specialBehavior: "summon_frenzy",
          attacks: @[
            BossAttack(
              attackType: bapSummon,
              damage: 0.0,
              cooldown: 3.75,
              projectileSpeed: 0.0,
              projectileCount: 3,
              spreadAngle: 0.0,
              durationOrRadius: 0.0,
              specialData: "minion_triangle"
            ),
            BossAttack(
              attackType: bapBurst,
              damage: 1.0,
              cooldown: 2.5,
              projectileSpeed: 150.0,
              projectileCount: 5,
              spreadAngle: 60.0,
              durationOrRadius: 0.0
            ),
            BossAttack(
              attackType: bapCircle,
              damage: 1.0,
              cooldown: 4.0,
              projectileSpeed: 140.0,
              projectileCount: 10,
              spreadAngle: 360.0,
              durationOrRadius: 0.0
            )
          ]
        )
      ]
    )
  
  of 3:  # Wave 15 - THE METEOR STRIKER
    result = BossDefinition(
      name: "The Meteor Striker",
      bossID: 3,
      baseHP: 250.0,  # NERFED from 280.0
      baseSpeed: 65.0,  # NERFED from 75.0
      baseDamage: 2,
      baseRadius: 48.0,
      color: Color(r: 255, g: 100, b: 0, a: 255),
      description: "Rains destruction from above with devastating meteor strikes",
      specialAbilities: @["meteor_shower", "impact_zone"],
      phases: @[
        BossPhaseDefinition(
          name: "Orbital Strike",
          hpThreshold: 1.0,
          speedMultiplier: 0.95,  # NERFED from 1.05
          damageMultiplier: 1.0,
          defenseMultiplier: 1.0,
          color: Color(r: 255, g: 100, b: 0, a: 255),
          visualEffect: "pulse",
          specialBehavior: "circle_player",
          attacks: @[
            BossAttack(
              attackType: bapMeteor,
              damage: 2.0,
              cooldown: 3.2,  # NERFED from 3.0
              projectileSpeed: 280.0,  # NERFED from 300.0
              projectileCount: 4,
              spreadAngle: 0.0,
              durationOrRadius: 80.0,
              specialData: "warn_impact"
            ),
            BossAttack(
              attackType: bapTargeted,
              damage: 1.0,
              cooldown: 1.7,  # NERFED from 1.5
              projectileSpeed: 230.0,  # NERFED from 250.0
              projectileCount: 1,
              spreadAngle: 0.0,
              durationOrRadius: 0.0
            )
          ]
        ),
        BossPhaseDefinition(
          name: "Cataclysm",
          hpThreshold: 0.5,
          speedMultiplier: 1.0,  # NERFED from 1.1
          damageMultiplier: 1.4,  # NERFED from 1.5
          defenseMultiplier: 1.0,
          color: Color(r: 255, g: 50, b: 0, a: 255),
          visualEffect: "aura",
          specialBehavior: "meteor_storm",
          attacks: @[
            BossAttack(
              attackType: bapMeteor,
              damage: 2.0,
              cooldown: 2.3,  # NERFED from 2.0
              projectileSpeed: 330.0,  # NERFED from 350.0
              projectileCount: 7,  # NERFED from 8 (fewer meteors)
              spreadAngle: 0.0,
              durationOrRadius: 100.0,
              specialData: "massive_impact"
            ),
            BossAttack(
              attackType: bapPulse,
              damage: 1.0,
              cooldown: 4.5,  # NERFED from 4.0
              projectileSpeed: 190.0,  # NERFED from 200.0
              projectileCount: 0,
              spreadAngle: 0.0,
              durationOrRadius: 150.0
            )
          ]
        ),
        BossPhaseDefinition(
          name: "Apocalypse",
          hpThreshold: 0.25,
          speedMultiplier: 1.2,  # NERFED from 2.0
          damageMultiplier: 1.5,  # NERFED from 2.0
          defenseMultiplier: 0.9,
          color: Color(r: 255, g: 0, b: 0, a: 255),
          visualEffect: "glow",
          specialBehavior: "enraged",
          attacks: @[
            BossAttack(
              attackType: bapMeteor,
              damage: 2.5,  # NERFED from 3.0
              cooldown: 1.75,  # NERFED from 1.5
              projectileSpeed: 370.0,  # NERFED from 400.0
              projectileCount: 11,  # NERFED from 12 (fewer meteors)
              spreadAngle: 0.0,
              durationOrRadius: 120.0,
              specialData: "apocalypse_mode"
            ),
            BossAttack(
              attackType: bapCircle,
              damage: 1.0,
              cooldown: 3.0,  # NERFED from 2.5
              projectileSpeed: 170.0,  # NERFED from 180.0
              projectileCount: 16,  # NERFED from 20
              spreadAngle: 360.0,
              durationOrRadius: 0.0
            )
          ]
        )
      ]
    )
  
  of 4:  # Wave 20 - THE LASER ARCHITECT
    result = BossDefinition(
      name: "The Laser Architect",
      bossID: 4,
      baseHP: 350.0,  # NERFED from 390.0
      baseSpeed: 70.0,  # NERFED from 77.5
      baseDamage: 2,
      baseRadius: 52.0,
      color: Color(r: 0, g: 200, b: 255, a: 255),
      description: "Constructs deadly laser grids and geometric death traps",
      specialAbilities: @["laser_geometry", "grid_lock"],
      phases: @[
        BossPhaseDefinition(
          name: "Blueprint",
          hpThreshold: 1.0,
          speedMultiplier: 1.0,  # NERFED from 1.1
          damageMultiplier: 1.0,
          defenseMultiplier: 1.2,
          color: Color(r: 0, g: 200, b: 255, a: 255),
          visualEffect: "shield",
          specialBehavior: "geometric_movement",
          attacks: @[
            BossAttack(
              attackType: bapLaser,
              damage: 2.0,
              cooldown: 4.5,  # NERFED from 3.5
              projectileSpeed: 0.0,
              projectileCount: 3,
              spreadAngle: 90.0,
              durationOrRadius: 2.5,  # NERFED from 3.0
              specialData: "cross_laser"
            ),
            BossAttack(
              attackType: bapWave,
              damage: 1.0,
              cooldown: 2.75,  # NERFED from 2.25
              projectileSpeed: 160.0,  # NERFED from 180.0
              projectileCount: 5,  # NERFED from 6
              spreadAngle: 45.0,  # NERFED from 50.0 (tighter)
              durationOrRadius: 0.0
            ),
            BossAttack(
              attackType: bapTargeted,
              damage: 1.0,
              cooldown: 3.5,  # NERFED from 3.0
              projectileSpeed: 220.0,  # NERFED from 250.0
              projectileCount: 4,  # NERFED from 5
              spreadAngle: 8.0,  # NERFED from 10.0 (tighter)
              durationOrRadius: 0.0
            )
          ]
        ),
        BossPhaseDefinition(
          name: "Construction",
          hpThreshold: 0.65,
          speedMultiplier: 1.2,  # NERFED from 1.33
          damageMultiplier: 1.2,  # NERFED from 1.33
          defenseMultiplier: 1.1,
          color: Color(r: 0, g: 255, b: 255, a: 255),
          visualEffect: "pulse",
          specialBehavior: "laser_web",
          attacks: @[
            BossAttack(
              attackType: bapLaser,
              damage: 2.0,
              cooldown: 3.5,  # NERFED from 2.2
              projectileSpeed: 0.0,
              projectileCount: 3,  # NERFED from 4 (fewer lasers)
              spreadAngle: 45.0,
              durationOrRadius: 3.0,  # NERFED from 3.5 (shorter duration)
              specialData: "rotating_grid"
            ),
            BossAttack(
              attackType: bapTargeted,
              damage: 1.0,
              cooldown: 1.5,  # NERFED from 0.8
              projectileSpeed: 260.0,  # NERFED from 300.0
              projectileCount: 3,  # NERFED from 4
              spreadAngle: 15.0,  # NERFED from 20.0 (tighter)
              durationOrRadius: 0.0
            ),
            BossAttack(
              attackType: bapCircle,
              damage: 1.0,
              cooldown: 4.5,  # NERFED from 3.5
              projectileSpeed: 145.0,  # NERFED from 160.0
              projectileCount: 12,  # NERFED from 16
              spreadAngle: 360.0,
              durationOrRadius: 0.0
            ),
            BossAttack(
              attackType: bapBurst,  # NERFED: Less aggressive burst
              damage: 1.0,
              cooldown: 3.0,  # NERFED from 2.5
              projectileSpeed: 190.0,  # NERFED from 220.0
              projectileCount: 6,  # NERFED from 8
              spreadAngle: 50.0,  # NERFED from 60.0 (tighter)
              durationOrRadius: 0.0
            )
          ]
        ),
        BossPhaseDefinition(
          name: "Masterpiece",
          hpThreshold: 0.3,
          speedMultiplier: 1.2,  # NERFED from 1.3
          damageMultiplier: 1.2,  # NERFED from 1.3
          defenseMultiplier: 1.0,
          color: Color(r: 100, g: 255, b: 255, a: 255),
          visualEffect: "aura",
          specialBehavior: "laser_chaos",
          attacks: @[
            BossAttack(
              attackType: bapLaser,
              damage: 2.0,  # NERFED from 2.5
              cooldown: 4.0,  # NERFED from 2.5
              projectileSpeed: 0.0,
              projectileCount: 4,  # NERFED from 6 (fewer lasers)
              spreadAngle: 22.5,
              durationOrRadius: 2.5,  # NERFED from 3.5 (shorter)
              specialData: "prismatic_cage"
            ),
            BossAttack(
              attackType: bapLaser,
              damage: 2.5,
              cooldown: 1.0,  # Rapid fire laser spam
              projectileSpeed: 0.0,
              projectileCount: 1,
              spreadAngle: 0.0,
              durationOrRadius: 1.5,  # Short duration
              specialData: "laser_snipe"  # Rapid tracking lasers
            ),
            BossAttack(
              attackType: bapCircle,
              damage: 1.0,
              cooldown: 4.5,  # NERFED from 3.5
              projectileSpeed: 140.0,  # NERFED from 155.0
              projectileCount: 16,  # NERFED from 20
              spreadAngle: 360.0,
              durationOrRadius: 0.0
            ),
            BossAttack(
              attackType: bapBarrage,
              damage: 1.0,  # NERFED from 2.0
              cooldown: 6.0,  # NERFED from 4.5
              projectileSpeed: 190.0,  # NERFED from 210.0
              projectileCount: 16,  # NERFED from 20
              spreadAngle: 360.0,
              durationOrRadius: 0.0
            ),
            BossAttack(
              attackType: bapPulse,
              damage: 1.0,  # NERFED from 1.5
              cooldown: 6.5,  # NERFED from 5.0
              projectileSpeed: 160.0,  # NERFED from 175.0
              projectileCount: 0,
              spreadAngle: 0.0,
              durationOrRadius: 140.0  # NERFED from 160.0
            ),
            BossAttack(
              attackType: bapTargeted,
              damage: 1.0,  # NERFED from 1.5
              cooldown: 2.0,  # EXTREMELY NERFED from 1.2
              projectileSpeed: 250.0,  # NERFED from 280.0
              projectileCount: 2,  # NERFED from 3
              spreadAngle: 12.0,  # NERFED from 18.0 (tighter)
              durationOrRadius: 0.0
            )
          ]
        )
      ]
    )
  
  of 5:  # Wave 25 - THE VOID DANCER
    result = BossDefinition(
      name: "The Void Dancer",
      bossID: 5,
      baseHP: 320.0,  # NERFED from 380.0
      baseSpeed: 60.0,  # NERFED from 70.0
      baseDamage: 2,
      baseRadius: 46.0,
      color: Color(r: 80, g: 0, b: 120, a: 255),
      description: "Blinks through reality, leaving trails of dark energy",
      specialAbilities: @["void_blink", "shadow_clone", "dimensional_tear"],
      phases: @[
        BossPhaseDefinition(
          name: "Phase Walk",
          hpThreshold: 1.0,
          speedMultiplier: 0.9,  # NERFED from 1.0
          damageMultiplier: 0.9,  # NERFED from 1.0
          defenseMultiplier: 1.0,
          color: Color(r: 80, g: 0, b: 120, a: 255),
          visualEffect: "pulse",
          specialBehavior: "teleport_pattern",
          attacks: @[
            BossAttack(
              attackType: bapTeleport,
              damage: 1.5,  # NERFED from 2.0
              cooldown: 3.5,  # NERFED from 3.0
              projectileSpeed: 0.0,
              projectileCount: 0,
              spreadAngle: 0.0,
              durationOrRadius: 200.0,
              specialData: "afterimage_burst"
            ),
            BossAttack(
              attackType: bapBurst,
              damage: 1.5,  # NERFED from 2.0
              cooldown: 2.5,  # NERFED from 2.0
              projectileSpeed: 180.0,  # NERFED from 200.0
              projectileCount: 5,  # NERFED from 7
              spreadAngle: 35.0,  # NERFED from 40.0
              durationOrRadius: 0.0
            ),
            BossAttack(
              attackType: bapTargeted,
              damage: 1.5,  # NERFED from 2.0
              cooldown: 2.8,  # NERFED from 2.3
              projectileSpeed: 220.0,  # NERFED from 240.0
              projectileCount: 1,  # NERFED from 2
              spreadAngle: 10.0,  # NERFED from 12.0
              durationOrRadius: 0.0
            )
          ]
        ),
        BossPhaseDefinition(
          name: "Shadow Realm",
          hpThreshold: 0.6,
          speedMultiplier: 1.05,  # NERFED from 1.15
          damageMultiplier: 1.15,  # NERFED from 1.3
          defenseMultiplier: 0.9,
          color: Color(r: 120, g: 0, b: 180, a: 255),
          visualEffect: "aura",
          specialBehavior: "clone_assault",
          attacks: @[
            BossAttack(
              attackType: bapTeleport,
              damage: 1.5,  # NERFED from 2.0
              cooldown: 3.0,  # NERFED from 2.5
              projectileSpeed: 0.0,
              projectileCount: 1,  # NERFED from 2
              spreadAngle: 0.0,
              durationOrRadius: 250.0,
              specialData: "triple_clone"
            ),
            BossAttack(
              attackType: bapWave,
              damage: 1.5,  # NERFED from 2.0
              cooldown: 2.2,  # NERFED from 1.8
              projectileSpeed: 160.0,  # NERFED from 180.0
              projectileCount: 5,  # NERFED from 6
              spreadAngle: 50.0,  # NERFED from 55.0
              durationOrRadius: 0.0
            ),
            BossAttack(
              attackType: bapCircle,
              damage: 1.5,  # NERFED from 2.0
              cooldown: 4.0,  # NERFED from 3.5
              projectileSpeed: 145.0,  # NERFED from 160.0
              projectileCount: 10,  # NERFED from 12
              spreadAngle: 360.0,
              durationOrRadius: 0.0
            ),
            BossAttack(
              attackType: bapSpiral,
              damage: 1.5,  # NERFED from 2.0
              cooldown: 3.2,  # NERFED from 2.8
              projectileSpeed: 145.0,  # NERFED from 160.0
              projectileCount: 7,  # NERFED from 9
              spreadAngle: 30.0,
              durationOrRadius: 0.0
            )
          ]
        ),
        BossPhaseDefinition(
          name: "Void Ascension",
          hpThreshold: 0.35,
          speedMultiplier: 1.1,  # NERFED from 1.2
          damageMultiplier: 1.3,  # NERFED from 1.5
          defenseMultiplier: 0.8,
          color: Color(r: 160, g: 40, b: 220, a: 255),
          visualEffect: "glow",
          specialBehavior: "reality_break",
          attacks: @[
            BossAttack(
              attackType: bapTeleport,
              damage: 2.5,  # NERFED from 3.0
              cooldown: 2.5,  # NERFED from 2.0
              projectileSpeed: 0.0,
              projectileCount: 2,  # NERFED from 3
              spreadAngle: 0.0,
              durationOrRadius: 300.0,
              specialData: "dimensional_rift"
            ),
            BossAttack(
              attackType: bapBarrage,
              damage: 1.5,  # NERFED from 2.0
              cooldown: 3.5,  # NERFED from 3.0
              projectileSpeed: 160.0,  # NERFED from 180.0
              projectileCount: 16,  # NERFED from 20
              spreadAngle: 240.0,  # NERFED from 270.0
              durationOrRadius: 0.0
            ),
            BossAttack(
              attackType: bapPulse,
              damage: 1.5,  # NERFED from 2.0
              cooldown: 5.0,  # NERFED from 4.5
              projectileSpeed: 200.0,  # NERFED from 220.0
              projectileCount: 0,
              spreadAngle: 0.0,
              durationOrRadius: 160.0,  # NERFED from 180.0
            ),
            BossAttack(
              attackType: bapDash,
              damage: 2.5,  # NERFED from 3.0
              cooldown: 5.5,  # NERFED from 5.0
              projectileSpeed: 450.0,  # NERFED from 500.0
              projectileCount: 0,
              spreadAngle: 0.0,
              durationOrRadius: 0.0
            ),
            BossAttack(
              attackType: bapWave,
              damage: 1.5,  # NERFED from 2.0
              cooldown: 2.0,  # NERFED from 1.5
              projectileSpeed: 190.0,  # NERFED from 210.0
              projectileCount: 6,  # NERFED from 8
              spreadAngle: 60.0,  # NERFED from 70.0
              durationOrRadius: 0.0
            ),
            BossAttack(
              attackType: bapTargeted,
              damage: 1.5,  # NERFED from 2.0
              cooldown: 1.5,  # NERFED from 1.2
              projectileSpeed: 240.0,  # NERFED from 260.0
              projectileCount: 2,  # NERFED from 3
              spreadAngle: 12.0,  # NERFED from 15.0
              durationOrRadius: 0.0
            )
          ]
        )
      ]
    )
  
  of 6:  # Wave 30 - THE CHAIN REACTOR
    result = BossDefinition(
      name: "The Chain Reactor",
      bossID: 6,
      baseHP: 450.0,
      baseSpeed: 70.0,
      baseDamage: 2,
      baseRadius: 55.0,
      color: Color(r: 255, g: 255, b: 0, a: 255),  # Bright electric yellow
      description: "A being of pure electricity that chains devastating arcs between targets",
      specialAbilities: @["chain_lightning", "electric_field", "voltage_spike"],
      phases: @[
        BossPhaseDefinition(
          name: "Charging",
          hpThreshold: 1.0,
          speedMultiplier: 0.8,
          damageMultiplier: 0.85,
          defenseMultiplier: 1.35,
          color: Color(r: 255, g: 255, b: 0, a: 255),
          visualEffect: "pulse",
          specialBehavior: "electric_buildup",  # Twitchy, charging movement
          attacks: @[
            BossAttack(
              attackType: bapChain,
              damage: 1.5,
              cooldown: 3.5,
              projectileSpeed: 0.0,
              projectileCount: 3,  # 3 chain lightning bolts
              spreadAngle: 0.0,
              durationOrRadius: 280.0,  # Range
              specialData: "chain_basic"
            ),
            BossAttack(
              attackType: bapOrbit,
              damage: 0.8,
              cooldown: 0.8,  # Constant orbiting charges
              projectileSpeed: 85.0,
              projectileCount: 3,  # 3 electric charges
              spreadAngle: 120.0,  # Evenly spaced
              durationOrRadius: 140.0,  # Orbit radius
              specialData: "electric_charges"  # Electric orbs
            ),
            BossAttack(
              attackType: bapTargeted,
              damage: 1.0,
              cooldown: 2.0,
              projectileSpeed: 220.0,
              projectileCount: 1,  # Single zap
              spreadAngle: 0.0,
              durationOrRadius: 0.0
            )
          ]
        ),
        BossPhaseDefinition(
          name: "High Voltage",
          hpThreshold: 0.55,
          speedMultiplier: 1.15,  # Faster, more erratic
          damageMultiplier: 1.2,
          defenseMultiplier: 1.1,
          color: Color(r: 255, g: 255, b: 150, a: 255),
          visualEffect: "aura",
          specialBehavior: "electric_surge",  # Rapid twitchy movement
          attacks: @[
            BossAttack(
              attackType: bapChain,
              damage: 2.0,
              cooldown: 2.5,
              projectileSpeed: 0.0,
              projectileCount: 5,  # More chains
              spreadAngle: 0.0,
              durationOrRadius: 320.0,
              specialData: "chain_storm"  # Multi-target chains
            ),
            BossAttack(
              attackType: bapOrbit,
              damage: 1.2,
              cooldown: 0.5,
              projectileSpeed: 110.0,
              projectileCount: 5,  # More charges
              spreadAngle: 72.0,
              durationOrRadius: 160.0,
              specialData: "dual_layer_orbit"  # Two layers of charges
            ),
            BossAttack(
              attackType: bapPulse,
              damage: 1.5,
              cooldown: 4.5,
              projectileSpeed: 210.0,
              projectileCount: 0,
              spreadAngle: 0.0,
              durationOrRadius: 170.0,  # Electric shockwave
              specialData: "electric_discharge"
            ),
            BossAttack(
              attackType: bapCircle,
              damage: 1.0,
              cooldown: 3.0,
              projectileSpeed: 160.0,
              projectileCount: 16,  # Ring of lightning
              spreadAngle: 360.0,
              durationOrRadius: 0.0
            )
          ]
        ),
        BossPhaseDefinition(
          name: "Overload",
          hpThreshold: 0.3,
          speedMultiplier: 1.2,
          damageMultiplier: 1.4,
          defenseMultiplier: 0.85,
          color: Color(r: 255, g: 255, b: 255, a: 255),
          visualEffect: "glow",
          specialBehavior: "critical_discharge",  # Chaotic electric movement
          attacks: @[
            BossAttack(
              attackType: bapChain,
              damage: 2.5,
              cooldown: 2.0,
              projectileSpeed: 0.0,
              projectileCount: 8,  # Massive
              spreadAngle: 0.0,
              durationOrRadius: 360.0,
              specialData: "chain_overload"  # Maximum chain effect
            ),
            BossAttack(
              attackType: bapOrbit,
              damage: 1.5,
              cooldown: 0.4,  # Constant barrage
              projectileSpeed: 130.0,
              projectileCount: 6,
              spreadAngle: 60.0,
              durationOrRadius: 180.0,
              specialData: "orbital_storm"  # Triple layer
            ),
            BossAttack(
              attackType: bapBarrage,
              damage: 1.2,
              cooldown: 3.0,
              projectileSpeed: 230.0,
              projectileCount: 32,  # Electric explosion
              spreadAngle: 360.0,
              durationOrRadius: 0.0,
              specialData: "voltage_burst"
            ),
            BossAttack(
              attackType: bapPulse,
              damage: 2.0,
              cooldown: 5.0,
              projectileSpeed: 240.0,
              projectileCount: 0,
              spreadAngle: 0.0,
              durationOrRadius: 200.0,
              specialData: "overload_pulse"  # Massive shockwave
            )
          ]
        )
      ]
    )
  
  of 7:  # Wave 35 - THE ORBITAL COMMANDER
    result = BossDefinition(
      name: "The Orbital Commander",
      bossID: 7,
      baseHP: 600.0,
      baseSpeed: 60.0,
      baseDamage: 2,
      baseRadius: 58.0,
      color: Color(r: 150, g: 100, b: 255, a: 255),
      description: "Commands orbital satellites that strike with astronomical precision",
      specialAbilities: @["satellite_control", "orbital_strike", "gravity_lock"],
      phases: @[
        BossPhaseDefinition(
          name: "Satellite Deploy",
          hpThreshold: 1.0,
          speedMultiplier: 0.75,
          damageMultiplier: 0.9,
          defenseMultiplier: 1.4,
          color: Color(r: 150, g: 100, b: 255, a: 255),
          visualEffect: "shield",
          specialBehavior: "orbital_pattern",  # Circular orbital movement
          attacks: @[
            BossAttack(
              attackType: bapOrbit,
              damage: 1.2,
              cooldown: 1.0,
              projectileSpeed: 75.0,  # Orbital speed
              projectileCount: 3,  # 3 satellites
              spreadAngle: 120.0,
              durationOrRadius: 180.0,  # Wide orbit
              specialData: "satellite_orbit"  # Single layer orbit
            ),
            BossAttack(
              attackType: bapSnipe,
              damage: 2.5,
              cooldown: 4.0,
              projectileSpeed: 300.0,
              projectileCount: 1,
              spreadAngle: 0.0,
              durationOrRadius: 0.0,
              specialData: "orbital_snipe"  # Aimed from satellite
            ),
            BossAttack(
              attackType: bapTargeted,
              damage: 1.0,
              cooldown: 2.5,
              projectileSpeed: 200.0,
              projectileCount: 3,
              spreadAngle: 15.0,
              durationOrRadius: 0.0
            )
          ]
        ),
        BossPhaseDefinition(
          name: "Full Deployment",
          hpThreshold: 0.6,
          speedMultiplier: 1.0,
          damageMultiplier: 1.2,
          defenseMultiplier: 1.3,
          color: Color(r: 180, g: 120, b: 255, a: 255),
          visualEffect: "aura",
          specialBehavior: "satellite_swarm",  # Multiple orbital patterns
          attacks: @[
            BossAttack(
              attackType: bapOrbit,
              damage: 1.5,
              cooldown: 0.8,
              projectileSpeed: 95.0,
              projectileCount: 5,
              spreadAngle: 72.0,
              durationOrRadius: 200.0,
              specialData: "dual_layer_orbit"  # Two orbital layers
            ),
            BossAttack(
              attackType: bapSnipe,
              damage: 3.0,
              cooldown: 3.0,
              projectileSpeed: 350.0,
              projectileCount: 2,  # Double snipe
              spreadAngle: 20.0,
              durationOrRadius: 0.0,
              specialData: "precision_strike"
            ),
            BossAttack(
              attackType: bapCircle,
              damage: 1.5,
              cooldown: 4.5,
              projectileSpeed: 140.0,
              projectileCount: 16,
              spreadAngle: 360.0,
              durationOrRadius: 0.0
            ),
            BossAttack(
              attackType: bapPulse,
              damage: 1.5,
              cooldown: 6.0,
              projectileSpeed: 150.0,
              projectileCount: 0,
              spreadAngle: 0.0,
              durationOrRadius: 220.0,
              specialData: "gravity_pulse"  # Space-themed pulse
            )
          ]
        ),
        BossPhaseDefinition(
          name: "Orbital Supremacy",
          hpThreshold: 0.35,
          speedMultiplier: 1.15,
          damageMultiplier: 1.5,
          defenseMultiplier: 1.0,
          color: Color(r: 200, g: 150, b: 255, a: 255),
          visualEffect: "glow",
          specialBehavior: "orbital_chaos",  # Complex orbital patterns
          attacks: @[
            BossAttack(
              attackType: bapOrbit,
              damage: 2.0,
              cooldown: 0.6,
              projectileSpeed: 115.0,
              projectileCount: 8,
              spreadAngle: 45.0,
              durationOrRadius: 220.0,
              specialData: "orbital_storm"  # Triple layer orbit
            ),
            BossAttack(
              attackType: bapSnipe,
              damage: 4.0,
              cooldown: 2.5,
              projectileSpeed: 400.0,
              projectileCount: 3,  # Triple precision strike
              spreadAngle: 25.0,
              durationOrRadius: 0.0,
              specialData: "satellite_barrage"
            ),
            BossAttack(
              attackType: bapBarrage,
              damage: 1.5,
              cooldown: 3.5,
              projectileSpeed: 240.0,
              projectileCount: 24,
              spreadAngle: 360.0,
              durationOrRadius: 0.0,
              specialData: "orbital_bombardment"
            ),
            BossAttack(
              attackType: bapMeteor,
              damage: 2.5,
              cooldown: 5.0,
              projectileSpeed: 280.0,
              projectileCount: 5,  # Satellite drops
              spreadAngle: 0.0,
              durationOrRadius: 100.0,
              specialData: "satellite_strike"
            )
          ]
        )
      ]
    )
  
  of 8:  # Wave 40 - THE BERSERKER JUGGERNAUT
    result = BossDefinition(
      name: "The Berserker Juggernaut",
      bossID: 8,
      baseHP: 700.0,
      baseSpeed: 35.0,
      baseDamage: 3,
      baseRadius: 60.0,
      color: Color(r: 200, g: 0, b: 0, a: 255),
      description: "An unstoppable force of pure rage that grows stronger as it bleeds",
      specialAbilities: @["rage_buildup", "crushing_charge", "blood_fury"],
      phases: @[
        BossPhaseDefinition(
          name: "Warmup",
          hpThreshold: 1.0,
          speedMultiplier: 0.7,
          damageMultiplier: 0.9,
          defenseMultiplier: 1.2,
          color: Color(r: 200, g: 0, b: 0, a: 255),
          visualEffect: "pulse",
          specialBehavior: "aggressive_chase",  # Direct pursuit
          attacks: @[
            BossAttack(
              attackType: bapDash,
              damage: 2.5,
              cooldown: 4.5,
              projectileSpeed: 450.0,  # Fast charge
              projectileCount: 0,
              spreadAngle: 0.0,
              durationOrRadius: 0.0,
              specialData: "charge_attack"
            ),
            BossAttack(
              attackType: bapWave,
              damage: 1.5,
              cooldown: 3.0,
              projectileSpeed: 170.0,
              projectileCount: 4,
              spreadAngle: 80.0,
              durationOrRadius: 0.0
            ),
            BossAttack(
              attackType: bapTargeted,
              damage: 1.5,
              cooldown: 2.0,
              projectileSpeed: 200.0,
              projectileCount: 1,
              spreadAngle: 0.0,
              durationOrRadius: 0.0
            )
          ]
        ),
        BossPhaseDefinition(
          name: "Bloodrage",
          hpThreshold: 0.65,
          speedMultiplier: 0.8,  # NERFED from 1.1
          damageMultiplier: 1.3,
          defenseMultiplier: 1.0,
          color: Color(r: 255, g: 30, b: 0, a: 255),
          visualEffect: "aura",
          specialBehavior: "enraged_assault",  # Aggressive movement
          attacks: @[
            BossAttack(
              attackType: bapDash,
              damage: 3.5,
              cooldown: 3.0,  # Frequent charges
              projectileSpeed: 520.0,  # Very fast
              projectileCount: 0,
              spreadAngle: 0.0,
              durationOrRadius: 0.0,
              specialData: "double_charge"  # Charges twice
            ),
            BossAttack(
              attackType: bapPulse,
              damage: 2.5,
              cooldown: 4.0,
              projectileSpeed: 190.0,
              projectileCount: 0,
              spreadAngle: 0.0,
              durationOrRadius: 160.0,
              specialData: "ground_slam"  # Rage shockwave
            ),
            BossAttack(
              attackType: bapCircle,
              damage: 1.5,
              cooldown: 2.5,
              projectileSpeed: 160.0,
              projectileCount: 12,  # Rage burst
              spreadAngle: 360.0,
              durationOrRadius: 0.0
            ),
            BossAttack(
              attackType: bapWave,
              damage: 2.0,
              cooldown: 2.0,
              projectileSpeed: 180.0,
              projectileCount: 5,
              spreadAngle: 90.0,
              durationOrRadius: 0.0
            )
          ]
        ),
        BossPhaseDefinition(
          name: "Unstoppable",
          hpThreshold: 0.3,
          speedMultiplier: 1.0,  # NERFED from 1.2
          damageMultiplier: 1.8,
          defenseMultiplier: 0.8,
          color: Color(r: 255, g: 0, b: 0, a: 255),
          visualEffect: "glow",
          specialBehavior: "berserk_rampage",  # Maximum aggression
          attacks: @[
            BossAttack(
              attackType: bapDash,
              damage: 4.5,
              cooldown: 2.0,  # Constant charging
              projectileSpeed: 600.0,
              projectileCount: 0,
              spreadAngle: 0.0,
              durationOrRadius: 0.0,
              specialData: "rage_charge"  # Triple charge combo
            ),
            BossAttack(
              attackType: bapPulse,
              damage: 3.0,
              cooldown: 3.0,
              projectileSpeed: 220.0,
              projectileCount: 0,
              spreadAngle: 0.0,
              durationOrRadius: 190.0,
              specialData: "earthquake"  # Massive slam
            ),
            BossAttack(
              attackType: bapBarrage,
              damage: 1.5,
              cooldown: 3.5,
              projectileSpeed: 210.0,
              projectileCount: 28,  # Rage explosion
              spreadAngle: 360.0,
              durationOrRadius: 0.0,
              specialData: "blood_burst"
            ),
            BossAttack(
              attackType: bapCircle,
              damage: 2.0,
              cooldown: 2.0,
              projectileSpeed: 170.0,
              projectileCount: 16,
              spreadAngle: 360.0,
              durationOrRadius: 0.0
            )
          ]
        )
      ]
    )  
  of 9:  # Wave 45 - THE PRISM ARCHITECT
    result = BossDefinition(
      name: "The Prism Architect",
      bossID: 9,
      baseHP: 850.0,
      baseSpeed: 65.0,
      baseDamage: 3,
      baseRadius: 56.0,
      color: Color(r: 255, g: 200, b: 255, a: 255),
      description: "Manipulates light itself into geometric prisons of splitting lasers",
      specialAbilities: @["prism_refraction", "light_split", "rainbow_cascade"],
      phases: @[
        BossPhaseDefinition(
          name: "First Refraction",
          hpThreshold: 1.0,
          speedMultiplier: 0.8,
          damageMultiplier: 0.9,
          defenseMultiplier: 1.3,
          color: Color(r: 255, g: 200, b: 255, a: 255),
          visualEffect: "shield",
          specialBehavior: "prism_defense",  # Geometric movement
          attacks: @[
            BossAttack(
              attackType: bapLaser,
              damage: 2.5,
              cooldown: 3.5,
              projectileSpeed: 0.0,
              projectileCount: 3,  # Triangle pattern
              spreadAngle: 120.0,
              durationOrRadius: 2.5,
              specialData: "splitting_laser"  # Lasers that refract
            ),
            BossAttack(
              attackType: bapWave,
              damage: 1.5,
              cooldown: 2.5,
              projectileSpeed: 160.0,
              projectileCount: 5,  # Rainbow wave
              spreadAngle: 50.0,
              durationOrRadius: 0.0,
              specialData: "rainbow_wave"
            ),
            BossAttack(
              attackType: bapTargeted,
              damage: 1.5,
              cooldown: 2.0,
              projectileSpeed: 200.0,
              projectileCount: 3,
              spreadAngle: 20.0,
              durationOrRadius: 0.0
            )
          ]
        ),
        BossPhaseDefinition(
          name: "Spectrum Array",
          hpThreshold: 0.6,
          speedMultiplier: 1.1,
          damageMultiplier: 1.25,
          defenseMultiplier: 1.15,
          color: Color(r: 200, g: 150, b: 255, a: 255),
          visualEffect: "aura",
          specialBehavior: "prism_array",  # Figure-8 patterns
          attacks: @[
            BossAttack(
              attackType: bapLaser,
              damage: 3.0,
              cooldown: 3.0,
              projectileSpeed: 0.0,
              projectileCount: 6,  # Hexagonal pattern
              spreadAngle: 60.0,
              durationOrRadius: 3.0,
              specialData: "hexagonal_prism"  # 6-way split
            ),
            BossAttack(
              attackType: bapBarrage,
              damage: 1.5,
              cooldown: 3.5,
              projectileSpeed: 180.0,
              projectileCount: 20,  # Rainbow burst
              spreadAngle: 360.0,
              durationOrRadius: 0.0,
              specialData: "chromatic_burst"
            ),
            BossAttack(
              attackType: bapCircle,
              damage: 1.5,
              cooldown: 4.0,
              projectileSpeed: 145.0,
              projectileCount: 16,  # Light ring
              spreadAngle: 360.0,
              durationOrRadius: 0.0
            ),
            BossAttack(
              attackType: bapWave,
              damage: 2.0,
              cooldown: 2.5,
              projectileSpeed: 170.0,
              projectileCount: 7,  # Rainbow wave
              spreadAngle: 60.0,
              durationOrRadius: 0.0
            )
          ]
        ),
        BossPhaseDefinition(
          name: "Pure Brilliance",
          hpThreshold: 0.33,
          speedMultiplier: 1.15,
          damageMultiplier: 1.5,
          defenseMultiplier: 1.0,
          color: Color(r: 255, g: 255, b: 255, a: 255),
          visualEffect: "glow",
          specialBehavior: "light_cascade",  # Sweeping arc movements
          attacks: @[
            BossAttack(
              attackType: bapLaser,
              damage: 4.5,
              cooldown: 2.0,
              projectileSpeed: 0.0,
              projectileCount: 7,  # Massive prism array
              spreadAngle: 30.0,
              durationOrRadius: 4.0,
              specialData: "prismatic_storm"  # Many splitting lasers
            ),
            BossAttack(
              attackType: bapPulse,
              damage: 2.5,
              cooldown: 3.5,
              projectileSpeed: 270.0,
              projectileCount: 0,
              spreadAngle: 0.0,
              durationOrRadius: 290.0,
              specialData: "blinding_pulse"  # Light explosion
            ),
            BossAttack(
              attackType: bapBarrage,
              damage: 2.0,
              cooldown: 2.5,
              projectileSpeed: 240.0,
              projectileCount: 40,  # Rainbow explosion
              spreadAngle: 360.0,
              durationOrRadius: 0.0,
              specialData: "light_burst"
            ),
            BossAttack(
              attackType: bapCircle,
              damage: 2.0,
              cooldown: 3.0,
              projectileSpeed: 160.0,
              projectileCount: 20,  # Dense light ring
              spreadAngle: 360.0,
              durationOrRadius: 0.0
            )
          ]
        )
      ]
    )
  
  of 10:  # Wave 50 - THE TIMEKEEPER
    result = BossDefinition(
      name: "The Timekeeper",
      bossID: 10,
      baseHP: 1050.0,
      baseSpeed: 55.0,
      baseDamage: 4,
      baseRadius: 62.0,
      color: Color(r: 0, g: 180, b: 180, a: 255),
      description: "Bends the flow of time itself, creating paradoxes and temporal rifts",
      specialAbilities: @["temporal_echo", "time_rewind", "chrono_break"],
      phases: @[
        BossPhaseDefinition(
          name: "Temporal Echo",
          hpThreshold: 1.0,
          speedMultiplier: 0.7,
          damageMultiplier: 0.9,
          defenseMultiplier: 1.4,
          color: Color(r: 0, g: 180, b: 180, a: 255),
          visualEffect: "pulse",
          specialBehavior: "slow_time",  # Slow methodical movement
          attacks: @[
            BossAttack(
              attackType: bapTeleport,
              damage: 2.5,
              cooldown: 4.0,
              projectileSpeed: 0.0,
              projectileCount: 2,  # Creates 2 temporal echoes
              spreadAngle: 0.0,
              durationOrRadius: 300.0,
              specialData: "time_echo"  # Leaves afterimages that shoot
            ),
            BossAttack(
              attackType: bapWave,
              damage: 1.5,
              cooldown: 2.5,
              projectileSpeed: 140.0,  # Slow time wave
              projectileCount: 7,
              spreadAngle: 50.0,
              durationOrRadius: 0.0,
              specialData: "temporal_wave"
            ),
            BossAttack(
              attackType: bapTargeted,
              damage: 2.0,
              cooldown: 3.0,
              projectileSpeed: 160.0,
              projectileCount: 1,
              spreadAngle: 0.0,
              durationOrRadius: 0.0
            )
          ]
        ),
        BossPhaseDefinition(
          name: "Time Fracture",
          hpThreshold: 0.6,
          speedMultiplier: 1.1,
          damageMultiplier: 1.3,
          defenseMultiplier: 1.2,
          color: Color(r: 100, g: 220, b: 220, a: 255),  # Brighter cyan
          visualEffect: "aura",
          specialBehavior: "time_distortion",  # Stuttering movement
          attacks: @[
            BossAttack(
              attackType: bapTeleport,
              damage: 3.5,
              cooldown: 3.0,
              projectileSpeed: 0.0,
              projectileCount: 4,  # Multiple time clones
              spreadAngle: 0.0,
              durationOrRadius: 350.0,
              specialData: "echo_burst"  # Many afterimages
            ),
            BossAttack(
              attackType: bapCircle,
              damage: 2.5,
              cooldown: 2.5,
              projectileSpeed: 170.0,
              projectileCount: 24,  # Time ring
              spreadAngle: 360.0,
              durationOrRadius: 0.0,
              specialData: "time_ring"
            ),
            BossAttack(
              attackType: bapPulse,
              damage: 2.5,
              cooldown: 5.0,
              projectileSpeed: 190.0,
              projectileCount: 0,
              spreadAngle: 0.0,
              durationOrRadius: 240.0,
              specialData: "chrono_pulse"  # Time shockwave
            ),
            BossAttack(
              attackType: bapSpiral,
              damage: 2.0,
              cooldown: 3.5,
              projectileSpeed: 150.0,
              projectileCount: 12,  # Time spiral
              spreadAngle: 30.0,
              durationOrRadius: 0.0
            )
          ]
        ),
        BossPhaseDefinition(
          name: "Time Collapse",
          hpThreshold: 0.4,
          speedMultiplier: 1.5,  # Ultra-fast blinking
          damageMultiplier: 1.7,
          defenseMultiplier: 0.85,
          color: Color(r: 150, g: 255, b: 255, a: 255),  # Bright cyan/white
          visualEffect: "glow",
          specialBehavior: "time_collapse",  # Ultra-fast blinking movement
          attacks: @[
            BossAttack(
              attackType: bapTeleport,
              damage: 4.5,
              cooldown: 2.0,  # Rapid teleports
              projectileSpeed: 0.0,
              projectileCount: 6,  # Many temporal clones
              spreadAngle: 0.0,
              durationOrRadius: 400.0,
              specialData: "temporal_collapse"  # Reality-breaking teleports
            ),
            BossAttack(
              attackType: bapBarrage,
              damage: 3.0,
              cooldown: 2.5,
              projectileSpeed: 260.0,
              projectileCount: 48,  # Time explosion
              spreadAngle: 360.0,
              durationOrRadius: 0.0,
              specialData: "time_shatter"
            ),
            BossAttack(
              attackType: bapLaser,
              damage: 4.0,
              cooldown: 4.0,
              projectileSpeed: 0.0,
              projectileCount: 4,  # Time beams
              spreadAngle: 90.0,
              durationOrRadius: 4.0,
              specialData: "temporal_beam"
            ),
            BossAttack(
              attackType: bapPulse,
              damage: 3.5,
              cooldown: 4.5,
              projectileSpeed: 220.0,
              projectileCount: 0,
              spreadAngle: 0.0,
              durationOrRadius: 270.0,
              specialData: "chrono_break"  # Massive time pulse
            ),
            BossAttack(
              attackType: bapCircle,
              damage: 2.5,
              cooldown: 2.0,
              projectileSpeed: 180.0,
              projectileCount: 32,  # Dense time ring
              spreadAngle: 360.0,
              durationOrRadius: 0.0
            )
          ]
        )
      ]
    )
  
  of 11:  # Wave 55 - THE CHAOS WEAVER
    result = BossDefinition(
      name: "The Chaos Weaver",
      bossID: 11,
      baseHP: 1250.0,  # NERFED from 1800.0
      baseSpeed: 70.0,  # NERFED from 90.0
      baseDamage: 4,  # NERFED from 5
      baseRadius: 58.0,
      color: Color(r: 180, g: 0, b: 180, a: 255),
      description: "Weaves patterns of pure chaos, unpredictable and devastating",
      specialAbilities: @["chaos_field", "random_teleport", "entropy_burst"],
      phases: @[
        BossPhaseDefinition(
          name: "Discord",
          hpThreshold: 1.0,
          speedMultiplier: 1.05,  # NERFED from 1.3
          damageMultiplier: 0.9,  # NERFED from 1.0
          defenseMultiplier: 1.2,  # NERFED from 1.3
          color: Color(r: 180, g: 0, b: 180, a: 255),
          visualEffect: "pulse",
          specialBehavior: "chaotic_movement",
          attacks: @[
            BossAttack(
              attackType: bapBarrage,
              damage: 1.5,  # NERFED from 2.0
              cooldown: 2.0,  # NERFED from 1.5
              projectileSpeed: 170.0,  # NERFED from 200.0
              projectileCount: 12,  # NERFED from 15
              spreadAngle: 180.0,
              durationOrRadius: 0.0,
              specialData: "random_spread"
            ),
            BossAttack(
              attackType: bapTeleport,
              damage: 2.5,  # NERFED from 3.0
              cooldown: 3.5,  # NERFED from 3.0
              projectileSpeed: 0.0,
              projectileCount: 0,
              spreadAngle: 0.0,
              durationOrRadius: 360.0,  # NERFED from 400.0
              specialData: "chaos_blink"
            ),
            BossAttack(
              attackType: bapWave,
              damage: 1.5,  # NERFED from 2.0
              cooldown: 2.5,  # NERFED from 2.0
              projectileSpeed: 190.0,  # NERFED from 220.0
              projectileCount: 5,  # NERFED from 6
              spreadAngle: 60.0,
              durationOrRadius: 0.0
            )
          ]
        ),
        BossPhaseDefinition(
          name: "Entropy",
          hpThreshold: 0.6,
          speedMultiplier: 1.1,  # NERFED from 1.6
          damageMultiplier: 1.2,  # NERFED from 1.5
          defenseMultiplier: 1.0,  # NERFED from 1.1
          color: Color(r: 200, g: 40, b: 200, a: 255),
          visualEffect: "aura",
          specialBehavior: "entropy_field",
          attacks: @[
            BossAttack(
              attackType: bapBarrage,
              damage: 2.5,  # NERFED from 3.0
              cooldown: 1.5,  # NERFED from 1.0
              projectileSpeed: 210.0,  # NERFED from 250.0
              projectileCount: 18,  # NERFED from 24
              spreadAngle: 360.0,
              durationOrRadius: 0.0,
              specialData: "entropy_burst"
            ),
            BossAttack(
              attackType: bapTeleport,
              damage: 3.0,  # NERFED from 4.0
              cooldown: 2.5,  # NERFED from 2.0
              projectileSpeed: 0.0,
              projectileCount: 2,  # NERFED from 3
              spreadAngle: 0.0,
              durationOrRadius: 400.0,  # NERFED from 450.0
              specialData: "reality_shift"
            ),
            BossAttack(
              attackType: bapCircle,
              damage: 2.5,  # NERFED from 3.0
              cooldown: 3.0,  # NERFED from 2.5
              projectileSpeed: 150.0,  # NERFED from 170.0
              projectileCount: 22,  # NERFED from 28
              spreadAngle: 360.0,
              durationOrRadius: 0.0
            ),
            BossAttack(
              attackType: bapLaser,
              damage: 3.5,  # NERFED from 4.0
              cooldown: 4.5,  # NERFED from 4.0
              projectileSpeed: 0.0,
              projectileCount: 4,  # NERFED from 5
              spreadAngle: 72.0,
              durationOrRadius: 3.0,  # NERFED from 3.5
              specialData: "chaos_beam"
            )
          ]
        ),
        BossPhaseDefinition(
          name: "Pure Chaos",
          hpThreshold: 0.35,
          speedMultiplier: 1.2,  # NERFED from 2.0
          damageMultiplier: 1.4,  # NERFED from 2.0
          defenseMultiplier: 0.85,  # NERFED from 0.9
          color: Color(r: 255, g: 100, b: 255, a: 255),
          visualEffect: "glow",
          specialBehavior: "total_chaos",
          attacks: @[
            BossAttack(
              attackType: bapBarrage,
              damage: 3.0,  # NERFED from 4.0
              cooldown: 1.2,  # NERFED from 0.8
              projectileSpeed: 250.0,  # NERFED from 300.0
              projectileCount: 30,  # NERFED from 40
              spreadAngle: 360.0,
              durationOrRadius: 0.0,
              specialData: "chaos_storm"
            ),
            BossAttack(
              attackType: bapTeleport,
              damage: 4.0,  # NERFED from 5.0
              cooldown: 2.0,  # NERFED from 1.5
              projectileSpeed: 0.0,
              projectileCount: 3,  # NERFED from 5
              spreadAngle: 0.0,
              durationOrRadius: 450.0,  # NERFED from 500.0
              specialData: "dimensional_chaos"
            ),
            BossAttack(
              attackType: bapPulse,
              damage: 3.0,  # NERFED from 4.0
              cooldown: 3.5,  # NERFED from 3.0
              projectileSpeed: 240.0,  # NERFED from 280.0
              projectileCount: 0,
              spreadAngle: 0.0,
              durationOrRadius: 260.0,  # NERFED from 300.0
              specialData: "entropy_wave"
            )
          ]
        )
      ]
    )
  
  of 12:  # Wave 60 - THE OMEGA ENTITY
    result = BossDefinition(
      name: "The Omega Entity",
      bossID: 12,
      baseHP: 1600.0,  # NERFED from 2500.0
      baseSpeed: 65.0,  # NERFED from 85.0
      baseDamage: 5,  # NERFED from 6
      baseRadius: 70.0,
      color: Color(r: 255, g: 50, b: 50, a: 255),
      description: "The ultimate challenge - combines all previous boss mechanics",
      specialAbilities: @["omni_attack", "adaptive_defense", "final_form"],
      phases: @[
        BossPhaseDefinition(
          name: "Alpha Phase",
          hpThreshold: 1.0,
          speedMultiplier: 0.9,  # NERFED from 1.0
          damageMultiplier: 0.9,  # NERFED from 1.0
          defenseMultiplier: 1.4,  # NERFED from 1.5
          color: Color(r: 255, g: 50, b: 50, a: 255),
          visualEffect: "shield",
          specialBehavior: "balanced_assault",
          attacks: @[
            BossAttack(
              attackType: bapSpiral,
              damage: 2.5,  # NERFED from 3.0
              cooldown: 3.0,  # NERFED from 2.5
              projectileSpeed: 160.0,  # NERFED from 180.0
              projectileCount: 10,  # NERFED from 12
              spreadAngle: 30.0,
              durationOrRadius: 0.0
            ),
            BossAttack(
              attackType: bapOrbit,
              damage: 2.5,  # NERFED from 3.0
              cooldown: 1.5,  # NERFED from 1.0
              projectileSpeed: 100.0,  # NERFED from 120.0
              projectileCount: 5,  # NERFED from 6
              spreadAngle: 60.0,
              durationOrRadius: 220.0  # NERFED from 250.0
            ),
            BossAttack(
              attackType: bapLaser,
              damage: 3.5,  # NERFED from 4.0
              cooldown: 4.5,  # NERFED from 4.0
              projectileSpeed: 0.0,
              projectileCount: 3,  # NERFED from 4
              spreadAngle: 90.0,
              durationOrRadius: 3.5  # NERFED from 4.0
            )
          ]
        ),
        BossPhaseDefinition(
          name: "Beta Phase",
          hpThreshold: 0.7,
          speedMultiplier: 1.1,  # NERFED from 1.3
          damageMultiplier: 1.15,  # NERFED from 1.3
          defenseMultiplier: 1.2,  # NERFED from 1.3
          color: Color(r: 255, g: 100, b: 0, a: 255),
          visualEffect: "aura",
          specialBehavior: "aggressive_mixed",
          attacks: @[
            BossAttack(
              attackType: bapMeteor,
              damage: 3.5,  # NERFED from 4.0
              cooldown: 3.5,  # NERFED from 3.0
              projectileSpeed: 320.0,  # NERFED from 350.0
              projectileCount: 5,  # NERFED from 6
              spreadAngle: 0.0,
              durationOrRadius: 100.0  # NERFED from 120.0
            ),
            BossAttack(
              attackType: bapChain,
              damage: 3.5,  # NERFED from 4.0
              cooldown: 4.0,  # NERFED from 3.5
              projectileSpeed: 0.0,
              projectileCount: 5,  # NERFED from 6
              spreadAngle: 0.0,
              durationOrRadius: 360.0  # NERFED from 400.0
            ),
            BossAttack(
              attackType: bapBarrage,
              damage: 2.5,  # NERFED from 3.0
              cooldown: 2.5,  # NERFED from 2.0
              projectileSpeed: 220.0,  # NERFED from 250.0
              projectileCount: 24,  # NERFED from 32
              spreadAngle: 360.0,
              durationOrRadius: 0.0
            )
          ]
        ),
        BossPhaseDefinition(
          name: "Gamma Phase",
          hpThreshold: 0.5,
          speedMultiplier: 1.15,  # NERFED from 1.5
          damageMultiplier: 1.25,  # NERFED from 1.6
          defenseMultiplier: 1.0,  # NERFED from 1.1
          color: Color(r: 255, g: 255, b: 0, a: 255),
          visualEffect: "pulse",
          specialBehavior: "adaptive_combat",
          attacks: @[
            BossAttack(
              attackType: bapTeleport,
              damage: 4.0,  # NERFED from 5.0
              cooldown: 3.0,  # NERFED from 2.5
              projectileSpeed: 0.0,
              projectileCount: 3,  # NERFED from 4
              spreadAngle: 0.0,
              durationOrRadius: 360.0  # NERFED from 400.0
            ),
            BossAttack(
              attackType: bapDash,
              damage: 4.0,  # NERFED from 5.0
              cooldown: 3.5,  # NERFED from 3.0
              projectileSpeed: 550.0,  # NERFED from 650.0
              projectileCount: 0,
              spreadAngle: 0.0,
              durationOrRadius: 0.0
            ),
            BossAttack(
              attackType: bapPulse,
              damage: 3.5,  # NERFED from 4.0
              cooldown: 4.5,  # NERFED from 4.0
              projectileSpeed: 240.0,  # NERFED from 280.0
              projectileCount: 0,
              spreadAngle: 0.0,
              durationOrRadius: 260.0  # NERFED from 300.0
            ),
            BossAttack(
              attackType: bapCircle,
              damage: 2.5,  # NERFED from 3.0
              cooldown: 2.5,  # NERFED from 2.0
              projectileSpeed: 170.0,  # NERFED from 200.0
              projectileCount: 26,  # NERFED from 32
              spreadAngle: 360.0,
              durationOrRadius: 0.0
            )
          ]
        ),
        BossPhaseDefinition(
          name: "Omega Phase",
          hpThreshold: 0.25,
          speedMultiplier: 1.2,  # NERFED from 2.0
          damageMultiplier: 1.5,  # NERFED from 2.5
          defenseMultiplier: 0.85,  # NERFED from 1.0
          color: Color(r: 255, g: 0, b: 255, a: 255),
          visualEffect: "glow",
          specialBehavior: "final_form",
          attacks: @[
            BossAttack(
              attackType: bapBarrage,
              damage: 4.0,  # NERFED from 5.0
              cooldown: 1.2,  # NERFED from 0.8
              projectileSpeed: 270.0,  # NERFED from 320.0
              projectileCount: 45,  # NERFED from 60
              spreadAngle: 360.0,
              durationOrRadius: 0.0,
              specialData: "omega_barrage"
            ),
            BossAttack(
              attackType: bapLaser,
              damage: 5.0,  # NERFED from 6.0
              cooldown: 3.0,  # NERFED from 2.5
              projectileSpeed: 0.0,
              projectileCount: 4,  # NERFED from 5
              spreadAngle: 45.0,
              durationOrRadius: 4.0,  # NERFED from 5.0
              specialData: "omega_beam"
            ),
            BossAttack(
              attackType: bapTeleport,
              damage: 5.0,  # NERFED from 6.0
              cooldown: 2.5,  # NERFED from 1.8
              projectileSpeed: 0.0,
              projectileCount: 4,  # NERFED from 6
              spreadAngle: 0.0,
              durationOrRadius: 450.0,  # NERFED from 500.0
              specialData: "omega_blink"
            ),
            BossAttack(
              attackType: bapPulse,
              damage: 4.0,  # NERFED from 5.0
              cooldown: 3.5,  # NERFED from 3.0
              projectileSpeed: 260.0,  # NERFED from 300.0
              projectileCount: 0,
              spreadAngle: 0.0,
              durationOrRadius: 300.0,  # NERFED from 350.0
              specialData: "omega_pulse"
            )
          ]
        )
      ]
    )
  
  else:  # Wave 65+ - RANDOM BOSSES
    # After wave 60, generate random powerful bosses
    let randomBossType = rand(11) + 1
    return getBossDefinition(randomBossType)

# Helper Functions

proc isBossWave*(waveNumber: int): bool =
  ## Checks if the current wave should spawn a custom boss (every 5 waves, no limit)
  waveNumber mod 5 == 0

proc getCustomBossNumber*(waveNumber: int): int =
  ## Returns the custom boss number (1-12) for the given wave
  ## After wave 60, continues with boss 12 (The Final Sentinel)
  if waveNumber <= 0 or waveNumber mod 5 != 0:
    return 0
  
  let bossNumber = waveNumber div 5
  if bossNumber > 12:
    return 12  # Boss 12 (The Final Sentinel) continues indefinitely with scaled stats
  
  return bossNumber

proc getBossForWave*(waveNumber: int): BossDefinition =
  ## Gets the appropriate boss definition for a wave number
  ## After wave 60, uses boss 12 (The Final Sentinel) with stats scaled per wave
  if not isBossWave(waveNumber):
    # Not a boss wave, return empty definition
    return BossDefinition()
  
  let bossNumber = getCustomBossNumber(waveNumber)
  return getBossDefinition(bossNumber)

proc getCurrentPhase*(boss: BossDefinition, currentHpPercent: float32): BossPhaseDefinition =
  ## Returns the current phase based on boss HP percentage
  result = boss.phases[0]  # Default to first phase
  
  for phase in boss.phases:
    if currentHpPercent <= phase.hpThreshold:
      result = phase
    else:
      break

proc updateBossAttackTimers*(attacks: var seq[BossAttack], dt: float32) =
  ## Updates all attack timers for a boss
  for attack in attacks.mitems:
    attack.timer += dt

proc canUseAttack*(attack: BossAttack): bool =
  ## Checks if an attack is ready to be used
  attack.timer >= attack.cooldown

proc resetAttackTimer*(attack: var BossAttack) =
  ## Resets an attack timer after use
  attack.timer = 0.0

proc getBossColorForPhase*(boss: BossDefinition, hpPercent: float32): Color =
  ## Returns the color for the current boss phase
  let phase = getCurrentPhase(boss, hpPercent)
  phase.color

proc getBossDescription*(bossNumber: int): string =
  ## Returns a boss description for UI display
  let boss = getBossDefinition(bossNumber)
  boss.description

proc getAllBossNames*(): seq[string] =
  ## Returns all custom boss names for reference
  result = @[]
  for i in 1..12:
    let boss = getBossDefinition(i)
    result.add(boss.name)

# Boss Stats Scaling

proc getScaledBossHP*(baseBoss: BossDefinition, waveNumber: int): float32 =
  ## Scales boss HP based on wave number
  let waveScale = 1.0 + ((waveNumber.float32 - 5.0) * 0.20)  # 20% increase per wave after wave 5
  baseBoss.baseHP * waveScale

proc getScaledBossSpeed*(baseBoss: BossDefinition, waveNumber: int): float32 =
  ## Scales boss speed based on wave number
  let waveScale = 1.0 + ((waveNumber.float32 - 5.0) * 0.04)  # 4% increase per wave after wave 5
  baseBoss.baseSpeed * waveScale

proc getScaledBossDamage*(baseBoss: BossDefinition, waveNumber: int): int =
  ## Scales boss damage based on wave number
  let additionalDamage = (waveNumber - 5) div 10  # +1 damage every 10 waves
  baseBoss.baseDamage + additionalDamage

proc getScaledAttackDamage*(baseAttack: BossAttack, waveNumber: int): float32 =
  ## Scales attack damage based on wave number
  let waveScale = 1.0 + ((waveNumber.float32 - 5.0) * 0.10)  # 10% increase per wave after wave 5
  baseAttack.damage * waveScale

# Boss Visual Effects

proc getBossGlowIntensity*(visualEffect: string, gameTime: float32): float32 =
  ## Returns glow intensity for boss visual effects
  case visualEffect
  of "glow":
    0.5 + sin(gameTime * 3.0) * 0.3  # Pulsing glow
  of "aura":
    0.7 + sin(gameTime * 2.0) * 0.2  # Slower pulse
  of "shield":
    0.4 + sin(gameTime * 4.0) * 0.4  # Fast shield pulse
  of "pulse":
    abs(sin(gameTime * 2.5))  # Strong pulse effect
  else:
    0.5  # Default

proc shouldSpawnParticles*(visualEffect: string): bool =
  ## Determines if boss should spawn visual particles
  visualEffect in ["glow", "aura", "pulse"]

# Export all types and procedures
