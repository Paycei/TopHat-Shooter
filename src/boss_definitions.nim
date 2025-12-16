## Boss Definitions System - Complete 60 Wave Boss List
## Allows complete customization of boss behavior, properties, attacks, and phases

import math, random, raylib

# Boss Configuration System

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
    defenseMultiplier*: float32  # Damage reduction
    attacks*: seq[BossAttack]
    color*: Color
    visualEffect*: string      # "glow", "aura", "shield", "pulse"
    specialBehavior*: string   # Custom behavior flags

  BossDefinition* = object
    name*: string
    bossID*: int               # Boss number (1-12 for custom, 13+ for random)
    baseHP*: float32
    baseSpeed*: float32
    baseDamage*: int
    baseRadius*: float32
    color*: Color
    phases*: seq[BossPhaseDefinition]
    specialAbilities*: seq[string]
    description*: string

# Boss Definitions (1-12) - CUSTOM UNIQUE BOSSES

proc getBossDefinition*(bossNumber: int): BossDefinition =
  case bossNumber
  of 1:  # Wave 5 - THE SPIRAL GUARDIAN
    result = BossDefinition(
      name: "The Spiral Guardian",
      bossID: 1,
      baseHP: 120.0,
      baseSpeed: 70.0,
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
          defenseMultiplier: 1.0,
          color: Color(r: 100, g: 50, b: 200, a: 255),
          visualEffect: "pulse",
          specialBehavior: "circle_movement",
          attacks: @[
            BossAttack(
              attackType: bapSpiral,
              damage: 1.0,
              cooldown: 2.0,
              projectileSpeed: 150.0,
              projectileCount: 8,
              spreadAngle: 45.0,
              durationOrRadius: 0.0
            )
          ]
        ),
        BossPhaseDefinition(
          name: "Spiral Rage",
          hpThreshold: 0.5,
          speedMultiplier: 1.3,
          damageMultiplier: 1.2,
          defenseMultiplier: 0.9,
          color: Color(r: 150, g: 30, b: 255, a: 255),
          visualEffect: "aura",
          specialBehavior: "aggressive",
          attacks: @[
            BossAttack(
              attackType: bapSpiral,
              damage: 1.0,
              cooldown: 1.5,
              projectileSpeed: 180.0,
              projectileCount: 12,
              spreadAngle: 30.0,
              durationOrRadius: 0.0
            ),
            BossAttack(
              attackType: bapCircle,
              damage: 1.0,
              cooldown: 3.0,
              projectileSpeed: 120.0,
              projectileCount: 16,
              spreadAngle: 360.0,
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
      baseHP: 200.0,
      baseSpeed: 60.0,
      baseDamage: 1,
      baseRadius: 50.0,
      color: Color(r: 50, g: 150, b: 50, a: 255),
      description: "Commands an army of minions to overwhelm foes",
      specialAbilities: @["summon_master", "minion_empowerment"],
      phases: @[
        BossPhaseDefinition(
          name: "Legion's Call",
          hpThreshold: 1.0,
          speedMultiplier: 0.8,
          damageMultiplier: 1.0,
          defenseMultiplier: 1.2,
          color: Color(r: 50, g: 150, b: 50, a: 255),
          visualEffect: "shield",
          specialBehavior: "defensive",
          attacks: @[
            BossAttack(
              attackType: bapSummon,
              damage: 0.0,
              cooldown: 5.0,
              projectileSpeed: 0.0,
              projectileCount: 3,
              spreadAngle: 0.0,
              durationOrRadius: 0.0,
              specialData: "minion_circle"
            )
          ]
        ),
        BossPhaseDefinition(
          name: "Swarm Commander",
          hpThreshold: 0.6,
          speedMultiplier: 1.0,
          damageMultiplier: 1.3,
          defenseMultiplier: 1.1,
          color: Color(r: 30, g: 200, b: 30, a: 255),
          visualEffect: "glow",
          specialBehavior: "summon_frenzy",
          attacks: @[
            BossAttack(
              attackType: bapSummon,
              damage: 0.0,
              cooldown: 3.5,
              projectileSpeed: 0.0,
              projectileCount: 5,
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
            )
          ]
        )
      ]
    )
  
  of 3:  # Wave 15 - THE METEOR STRIKER
    result = BossDefinition(
      name: "The Meteor Striker",
      bossID: 3,
      baseHP: 280.0,
      baseSpeed: 85.0,
      baseDamage: 2,
      baseRadius: 48.0,
      color: Color(r: 255, g: 100, b: 0, a: 255),
      description: "Rains destruction from above with devastating meteor strikes",
      specialAbilities: @["meteor_shower", "impact_zone"],
      phases: @[
        BossPhaseDefinition(
          name: "Orbital Strike",
          hpThreshold: 1.0,
          speedMultiplier: 1.2,
          damageMultiplier: 1.0,
          defenseMultiplier: 1.0,
          color: Color(r: 255, g: 100, b: 0, a: 255),
          visualEffect: "pulse",
          specialBehavior: "circle_player",
          attacks: @[
            BossAttack(
              attackType: bapMeteor,
              damage: 2.0,
              cooldown: 3.0,
              projectileSpeed: 300.0,
              projectileCount: 4,
              spreadAngle: 0.0,
              durationOrRadius: 80.0,
              specialData: "warn_impact"
            ),
            BossAttack(
              attackType: bapTargeted,
              damage: 1.0,
              cooldown: 1.5,
              projectileSpeed: 250.0,
              projectileCount: 1,
              spreadAngle: 0.0,
              durationOrRadius: 0.0
            )
          ]
        ),
        BossPhaseDefinition(
          name: "Cataclysm",
          hpThreshold: 0.5,
          speedMultiplier: 1.5,
          damageMultiplier: 1.5,
          defenseMultiplier: 0.8,
          color: Color(r: 255, g: 50, b: 0, a: 255),
          visualEffect: "aura",
          specialBehavior: "meteor_storm",
          attacks: @[
            BossAttack(
              attackType: bapMeteor,
              damage: 2.0,
              cooldown: 2.0,
              projectileSpeed: 350.0,
              projectileCount: 8,
              spreadAngle: 0.0,
              durationOrRadius: 100.0,
              specialData: "massive_impact"
            ),
            BossAttack(
              attackType: bapPulse,
              damage: 1.0,
              cooldown: 4.0,
              projectileSpeed: 200.0,
              projectileCount: 0,
              spreadAngle: 0.0,
              durationOrRadius: 150.0
            )
          ]
        ),
        BossPhaseDefinition(
          name: "Apocalypse",
          hpThreshold: 0.25,
          speedMultiplier: 2.0,
          damageMultiplier: 2.0,
          defenseMultiplier: 0.7,
          color: Color(r: 255, g: 0, b: 0, a: 255),
          visualEffect: "glow",
          specialBehavior: "enraged",
          attacks: @[
            BossAttack(
              attackType: bapMeteor,
              damage: 3.0,
              cooldown: 1.5,
              projectileSpeed: 400.0,
              projectileCount: 12,
              spreadAngle: 0.0,
              durationOrRadius: 120.0,
              specialData: "apocalypse_mode"
            ),
            BossAttack(
              attackType: bapCircle,
              damage: 1.0,
              cooldown: 2.5,
              projectileSpeed: 180.0,
              projectileCount: 20,
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
      baseHP: 380.0,
      baseSpeed: 75.0,
      baseDamage: 2,
      baseRadius: 52.0,
      color: Color(r: 0, g: 200, b: 255, a: 255),
      description: "Constructs deadly laser grids and geometric death traps",
      specialAbilities: @["laser_geometry", "grid_lock"],
      phases: @[
        BossPhaseDefinition(
          name: "Blueprint",
          hpThreshold: 1.0,
          speedMultiplier: 1.0,
          damageMultiplier: 1.0,
          defenseMultiplier: 1.3,
          color: Color(r: 0, g: 200, b: 255, a: 255),
          visualEffect: "shield",
          specialBehavior: "geometric_movement",
          attacks: @[
            BossAttack(
              attackType: bapLaser,
              damage: 2.0,
              cooldown: 4.0,
              projectileSpeed: 0.0,
              projectileCount: 2,
              spreadAngle: 90.0,
              durationOrRadius: 3.0,
              specialData: "cross_laser"
            ),
            BossAttack(
              attackType: bapWave,
              damage: 1.0,
              cooldown: 2.5,
              projectileSpeed: 170.0,
              projectileCount: 5,
              spreadAngle: 45.0,
              durationOrRadius: 0.0
            )
          ]
        ),
        BossPhaseDefinition(
          name: "Construction",
          hpThreshold: 0.65,
          speedMultiplier: 1.2,
          damageMultiplier: 1.3,
          defenseMultiplier: 1.2,
          color: Color(r: 0, g: 255, b: 255, a: 255),
          visualEffect: "pulse",
          specialBehavior: "laser_web",
          attacks: @[
            BossAttack(
              attackType: bapLaser,
              damage: 2.0,
              cooldown: 3.0,
              projectileSpeed: 0.0,
              projectileCount: 4,
              spreadAngle: 45.0,
              durationOrRadius: 3.5,
              specialData: "rotating_grid"
            ),
            BossAttack(
              attackType: bapTargeted,
              damage: 1.0,
              cooldown: 1.0,
              projectileSpeed: 280.0,
              projectileCount: 3,
              spreadAngle: 15.0,
              durationOrRadius: 0.0
            )
          ]
        ),
        BossPhaseDefinition(
          name: "Masterpiece",
          hpThreshold: 0.3,
          speedMultiplier: 1.4,
          damageMultiplier: 1.5,
          defenseMultiplier: 1.0,
          color: Color(r: 100, g: 255, b: 255, a: 255),
          visualEffect: "aura",
          specialBehavior: "laser_chaos",
          attacks: @[
            BossAttack(
              attackType: bapLaser,
              damage: 3.0,
              cooldown: 2.5,
              projectileSpeed: 0.0,
              projectileCount: 8,
              spreadAngle: 22.5,
              durationOrRadius: 4.0,
              specialData: "prismatic_cage"
            ),
            BossAttack(
              attackType: bapCircle,
              damage: 1.0,
              cooldown: 3.5,
              projectileSpeed: 150.0,
              projectileCount: 24,
              spreadAngle: 360.0,
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
      baseHP: 500.0,
      baseSpeed: 95.0,
      baseDamage: 2,
      baseRadius: 46.0,
      color: Color(r: 80, g: 0, b: 120, a: 255),
      description: "Blinks through reality, leaving trails of dark energy",
      specialAbilities: @["void_blink", "shadow_clone", "dimensional_tear"],
      phases: @[
        BossPhaseDefinition(
          name: "Phase Walk",
          hpThreshold: 1.0,
          speedMultiplier: 1.3,
          damageMultiplier: 1.0,
          defenseMultiplier: 1.1,
          color: Color(r: 80, g: 0, b: 120, a: 255),
          visualEffect: "pulse",
          specialBehavior: "teleport_pattern",
          attacks: @[
            BossAttack(
              attackType: bapTeleport,
              damage: 2.0,
              cooldown: 3.5,
              projectileSpeed: 0.0,
              projectileCount: 0,
              spreadAngle: 0.0,
              durationOrRadius: 200.0,
              specialData: "afterimage_burst"
            ),
            BossAttack(
              attackType: bapBurst,
              damage: 1.0,
              cooldown: 2.0,
              projectileSpeed: 220.0,
              projectileCount: 8,
              spreadAngle: 45.0,
              durationOrRadius: 0.0
            )
          ]
        ),
        BossPhaseDefinition(
          name: "Shadow Realm",
          hpThreshold: 0.6,
          speedMultiplier: 1.6,
          damageMultiplier: 1.4,
          defenseMultiplier: 0.9,
          color: Color(r: 120, g: 0, b: 180, a: 255),
          visualEffect: "aura",
          specialBehavior: "clone_assault",
          attacks: @[
            BossAttack(
              attackType: bapTeleport,
              damage: 2.0,
              cooldown: 2.5,
              projectileSpeed: 0.0,
              projectileCount: 3,
              spreadAngle: 0.0,
              durationOrRadius: 250.0,
              specialData: "triple_clone"
            ),
            BossAttack(
              attackType: bapWave,
              damage: 1.0,
              cooldown: 1.5,
              projectileSpeed: 200.0,
              projectileCount: 6,
              spreadAngle: 60.0,
              durationOrRadius: 0.0
            )
          ]
        ),
        BossPhaseDefinition(
          name: "Void Ascension",
          hpThreshold: 0.35,
          speedMultiplier: 2.0,
          damageMultiplier: 1.6,
          defenseMultiplier: 0.8,
          color: Color(r: 160, g: 40, b: 220, a: 255),
          visualEffect: "glow",
          specialBehavior: "reality_break",
          attacks: @[
            BossAttack(
              attackType: bapTeleport,
              damage: 3.0,
              cooldown: 2.0,
              projectileSpeed: 0.0,
              projectileCount: 5,
              spreadAngle: 0.0,
              durationOrRadius: 300.0,
              specialData: "dimensional_rift"
            ),
            BossAttack(
              attackType: bapBarrage,
              damage: 1.0,
              cooldown: 3.0,
              projectileSpeed: 180.0,
              projectileCount: 20,
              spreadAngle: 180.0,
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
      baseHP: 650.0,
      baseSpeed: 70.0,
      baseDamage: 3,
      baseRadius: 55.0,
      color: Color(r: 255, g: 255, b: 0, a: 255),
      description: "Channels devastating chain lightning between enemies and bullets",
      specialAbilities: @["chain_lightning", "electric_field", "overload"],
      phases: @[
        BossPhaseDefinition(
          name: "Charge Up",
          hpThreshold: 1.0,
          speedMultiplier: 0.9,
          damageMultiplier: 1.0,
          defenseMultiplier: 1.4,
          color: Color(r: 255, g: 255, b: 0, a: 255),
          visualEffect: "pulse",
          specialBehavior: "slow_charge",
          attacks: @[
            BossAttack(
              attackType: bapChain,
              damage: 2.0,
              cooldown: 3.0,
              projectileSpeed: 0.0,
              projectileCount: 4,
              spreadAngle: 0.0,
              durationOrRadius: 300.0,
              specialData: "chain_4_targets"
            ),
            BossAttack(
              attackType: bapOrbit,
              damage: 1.0,
              cooldown: 0.5,
              projectileSpeed: 100.0,
              projectileCount: 3,
              spreadAngle: 120.0,
              durationOrRadius: 150.0,
              specialData: "electric_orbit"
            )
          ]
        ),
        BossPhaseDefinition(
          name: "Plasma Storm",
          hpThreshold: 0.55,
          speedMultiplier: 1.2,
          damageMultiplier: 1.5,
          defenseMultiplier: 1.1,
          color: Color(r: 255, g: 255, b: 100, a: 255),
          visualEffect: "aura",
          specialBehavior: "electric_storm",
          attacks: @[
            BossAttack(
              attackType: bapChain,
              damage: 3.0,
              cooldown: 2.0,
              projectileSpeed: 0.0,
              projectileCount: 6,
              spreadAngle: 0.0,
              durationOrRadius: 350.0,
              specialData: "chain_lightning_storm"
            ),
            BossAttack(
              attackType: bapPulse,
              damage: 2.0,
              cooldown: 4.0,
              projectileSpeed: 250.0,
              projectileCount: 0,
              spreadAngle: 0.0,
              durationOrRadius: 200.0
            ),
            BossAttack(
              attackType: bapOrbit,
              damage: 1.0,
              cooldown: 0.3,
              projectileSpeed: 120.0,
              projectileCount: 6,
              spreadAngle: 60.0,
              durationOrRadius: 180.0
            )
          ]
        ),
        BossPhaseDefinition(
          name: "Critical Overload",
          hpThreshold: 0.3,
          speedMultiplier: 1.5,
          damageMultiplier: 2.0,
          defenseMultiplier: 0.9,
          color: Color(r: 255, g: 200, b: 0, a: 255),
          visualEffect: "glow",
          specialBehavior: "overcharged",
          attacks: @[
            BossAttack(
              attackType: bapChain,
              damage: 4.0,
              cooldown: 1.5,
              projectileSpeed: 0.0,
              projectileCount: 8,
              spreadAngle: 0.0,
              durationOrRadius: 400.0,
              specialData: "massive_chain"
            ),
            BossAttack(
              attackType: bapBarrage,
              damage: 1.0,
              cooldown: 2.5,
              projectileSpeed: 250.0,
              projectileCount: 30,
              spreadAngle: 360.0,
              durationOrRadius: 0.0
            )
          ]
        )
      ]
    )
  
  of 7:  # Wave 35 - THE ORBITAL COMMANDER
    result = BossDefinition(
      name: "The Orbital Commander",
      bossID: 7,
      baseHP: 800.0,
      baseSpeed: 80.0,
      baseDamage: 3,
      baseRadius: 58.0,
      color: Color(r: 200, g: 50, b: 255, a: 255),
      description: "Controls satellite weapons that orbit and strike with precision",
      specialAbilities: @["satellite_control", "orbital_strike", "gravity_well"],
      phases: @[
        BossPhaseDefinition(
          name: "Deployment",
          hpThreshold: 1.0,
          speedMultiplier: 1.0,
          damageMultiplier: 1.0,
          defenseMultiplier: 1.5,
          color: Color(r: 200, g: 50, b: 255, a: 255),
          visualEffect: "shield",
          specialBehavior: "deploy_satellites",
          attacks: @[
            BossAttack(
              attackType: bapOrbit,
              damage: 1.0,
              cooldown: 1.0,
              projectileSpeed: 90.0,
              projectileCount: 4,
              spreadAngle: 90.0,
              durationOrRadius: 200.0,
              specialData: "satellite_orbit"
            ),
            BossAttack(
              attackType: bapSnipe,
              damage: 3.0,
              cooldown: 3.5,
              projectileSpeed: 350.0,
              projectileCount: 1,
              spreadAngle: 0.0,
              durationOrRadius: 0.0,
              specialData: "laser_sight"
            )
          ]
        ),
        BossPhaseDefinition(
          name: "Full Arsenal",
          hpThreshold: 0.6,
          speedMultiplier: 1.3,
          damageMultiplier: 1.4,
          defenseMultiplier: 1.3,
          color: Color(r: 220, g: 80, b: 255, a: 255),
          visualEffect: "aura",
          specialBehavior: "multi_orbital",
          attacks: @[
            BossAttack(
              attackType: bapOrbit,
              damage: 2.0,
              cooldown: 0.8,
              projectileSpeed: 110.0,
              projectileCount: 6,
              spreadAngle: 60.0,
              durationOrRadius: 220.0,
              specialData: "dual_layer_orbit"
            ),
            BossAttack(
              attackType: bapSnipe,
              damage: 4.0,
              cooldown: 2.5,
              projectileSpeed: 400.0,
              projectileCount: 3,
              spreadAngle: 10.0,
              durationOrRadius: 0.0,
              specialData: "triple_snipe"
            ),
            BossAttack(
              attackType: bapPulse,
              damage: 2.0,
              cooldown: 5.0,
              projectileSpeed: 180.0,
              projectileCount: 0,
              spreadAngle: 0.0,
              durationOrRadius: 250.0
            )
          ]
        ),
        BossPhaseDefinition(
          name: "Maximum Orbit",
          hpThreshold: 0.35,
          speedMultiplier: 1.6,
          damageMultiplier: 1.8,
          defenseMultiplier: 1.0,
          color: Color(r: 255, g: 120, b: 255, a: 255),
          visualEffect: "glow",
          specialBehavior: "orbital_chaos",
          attacks: @[
            BossAttack(
              attackType: bapOrbit,
              damage: 2.0,
              cooldown: 0.5,
              projectileSpeed: 130.0,
              projectileCount: 8,
              spreadAngle: 45.0,
              durationOrRadius: 250.0,
              specialData: "orbital_storm"
            ),
            BossAttack(
              attackType: bapBarrage,
              damage: 2.0,
              cooldown: 3.0,
              projectileSpeed: 280.0,
              projectileCount: 24,
              spreadAngle: 360.0,
              durationOrRadius: 0.0
            )
          ]
        )
      ]
    )
  
  of 8:  # Wave 40 - THE BERSERKER JUGGERNAUT
    result = BossDefinition(
      name: "The Berserker Juggernaut",
      bossID: 8,
      baseHP: 1000.0,
      baseSpeed: 100.0,
      baseDamage: 4,
      baseRadius: 60.0,
      color: Color(r: 200, g: 0, b: 0, a: 255),
      description: "A relentless force that grows stronger and faster as battle intensifies",
      specialAbilities: @["rage_mode", "ground_slam", "blood_frenzy"],
      phases: @[
        BossPhaseDefinition(
          name: "Battle Start",
          hpThreshold: 1.0,
          speedMultiplier: 1.1,
          damageMultiplier: 1.0,
          defenseMultiplier: 1.2,
          color: Color(r: 200, g: 0, b: 0, a: 255),
          visualEffect: "pulse",
          specialBehavior: "aggressive_chase",
          attacks: @[
            BossAttack(
              attackType: bapDash,
              damage: 3.0,
              cooldown: 4.0,
              projectileSpeed: 500.0,
              projectileCount: 0,
              spreadAngle: 0.0,
              durationOrRadius: 0.0,
              specialData: "charge_attack"
            ),
            BossAttack(
              attackType: bapWave,
              damage: 2.0,
              cooldown: 2.5,
              projectileSpeed: 200.0,
              projectileCount: 5,
              spreadAngle: 90.0,
              durationOrRadius: 0.0
            )
          ]
        ),
        BossPhaseDefinition(
          name: "Bloodrage",
          hpThreshold: 0.65,
          speedMultiplier: 1.4,
          damageMultiplier: 1.5,
          defenseMultiplier: 1.0,
          color: Color(r: 255, g: 30, b: 0, a: 255),
          visualEffect: "aura",
          specialBehavior: "enraged_assault",
          attacks: @[
            BossAttack(
              attackType: bapDash,
              damage: 4.0,
              cooldown: 2.5,
              projectileSpeed: 600.0,
              projectileCount: 0,
              spreadAngle: 0.0,
              durationOrRadius: 0.0,
              specialData: "double_charge"
            ),
            BossAttack(
              attackType: bapPulse,
              damage: 3.0,
              cooldown: 3.5,
              projectileSpeed: 220.0,
              projectileCount: 0,
              spreadAngle: 0.0,
              durationOrRadius: 180.0,
              specialData: "ground_slam"
            ),
            BossAttack(
              attackType: bapCircle,
              damage: 2.0,
              cooldown: 2.0,
              projectileSpeed: 180.0,
              projectileCount: 16,
              spreadAngle: 360.0,
              durationOrRadius: 0.0
            )
          ]
        ),
        BossPhaseDefinition(
          name: "Unstoppable",
          hpThreshold: 0.3,
          speedMultiplier: 2.0,
          damageMultiplier: 2.5,
          defenseMultiplier: 0.8,
          color: Color(r: 255, g: 0, b: 0, a: 255),
          visualEffect: "glow",
          specialBehavior: "berserk_rampage",
          attacks: @[
            BossAttack(
              attackType: bapDash,
              damage: 5.0,
              cooldown: 1.5,
              projectileSpeed: 700.0,
              projectileCount: 0,
              spreadAngle: 0.0,
              durationOrRadius: 0.0,
              specialData: "triple_charge"
            ),
            BossAttack(
              attackType: bapPulse,
              damage: 4.0,
              cooldown: 2.5,
              projectileSpeed: 250.0,
              projectileCount: 0,
              spreadAngle: 0.0,
              durationOrRadius: 220.0,
              specialData: "earthquake"
            ),
            BossAttack(
              attackType: bapBarrage,
              damage: 2.0,
              cooldown: 3.0,
              projectileSpeed: 250.0,
              projectileCount: 36,
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
      baseHP: 1200.0,
      baseSpeed: 85.0,
      baseDamage: 4,
      baseRadius: 56.0,
      color: Color(r: 255, g: 150, b: 255, a: 255),
      description: "Bends light into deadly prisms that split and reflect attacks",
      specialAbilities: @["prism_split", "light_refraction", "spectrum_burst"],
      phases: @[
        BossPhaseDefinition(
          name: "Refraction",
          hpThreshold: 1.0,
          speedMultiplier: 1.0,
          damageMultiplier: 1.0,
          defenseMultiplier: 1.4,
          color: Color(r: 255, g: 150, b: 255, a: 255),
          visualEffect: "shield",
          specialBehavior: "prism_defense",
          attacks: @[
            BossAttack(
              attackType: bapLaser,
              damage: 3.0,
              cooldown: 3.0,
              projectileSpeed: 0.0,
              projectileCount: 3,
              spreadAngle: 120.0,
              durationOrRadius: 3.5,
              specialData: "splitting_laser"
            ),
            BossAttack(
              attackType: bapWave,
              damage: 2.0,
              cooldown: 2.0,
              projectileSpeed: 190.0,
              projectileCount: 7,
              spreadAngle: 60.0,
              durationOrRadius: 0.0,
              specialData: "rainbow_wave"
            )
          ]
        ),
        BossPhaseDefinition(
          name: "Spectrum",
          hpThreshold: 0.6,
          speedMultiplier: 1.3,
          damageMultiplier: 1.5,
          defenseMultiplier: 1.2,
          color: Color(r: 255, g: 180, b: 255, a: 255),
          visualEffect: "aura",
          specialBehavior: "prism_array",
          attacks: @[
            BossAttack(
              attackType: bapLaser,
              damage: 4.0,
              cooldown: 2.5,
              projectileSpeed: 0.0,
              projectileCount: 6,
              spreadAngle: 60.0,
              durationOrRadius: 4.0,
              specialData: "hexagonal_prism"
            ),
            BossAttack(
              attackType: bapBarrage,
              damage: 2.0,
              cooldown: 3.0,
              projectileSpeed: 220.0,
              projectileCount: 24,
              spreadAngle: 360.0,
              durationOrRadius: 0.0,
              specialData: "chromatic_burst"
            ),
            BossAttack(
              attackType: bapCircle,
              damage: 2.0,
              cooldown: 4.0,
              projectileSpeed: 160.0,
              projectileCount: 20,
              spreadAngle: 360.0,
              durationOrRadius: 0.0
            )
          ]
        ),
        BossPhaseDefinition(
          name: "Pure Light",
          hpThreshold: 0.35,
          speedMultiplier: 1.5,
          damageMultiplier: 2.0,
          defenseMultiplier: 1.0,
          color: Color(r: 255, g: 255, b: 255, a: 255),
          visualEffect: "glow",
          specialBehavior: "light_cascade",
          attacks: @[
            BossAttack(
              attackType: bapLaser,
              damage: 5.0,
              cooldown: 2.0,
              projectileSpeed: 0.0,
              projectileCount: 12,
              spreadAngle: 30.0,
              durationOrRadius: 4.5,
              specialData: "prismatic_storm"
            ),
            BossAttack(
              attackType: bapPulse,
              damage: 3.0,
              cooldown: 3.5,
              projectileSpeed: 280.0,
              projectileCount: 0,
              spreadAngle: 0.0,
              durationOrRadius: 300.0,
              specialData: "blinding_pulse"
            ),
            BossAttack(
              attackType: bapBarrage,
              damage: 2.0,
              cooldown: 2.0,
              projectileSpeed: 250.0,
              projectileCount: 40,
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
      baseHP: 1500.0,
      baseSpeed: 75.0,
      baseDamage: 5,
      baseRadius: 62.0,
      color: Color(r: 0, g: 150, b: 150, a: 255),
      description: "Manipulates time itself, creating echoes and temporal distortions",
      specialAbilities: @["time_dilation", "temporal_echo", "chrono_rewind"],
      phases: @[
        BossPhaseDefinition(
          name: "Past",
          hpThreshold: 1.0,
          speedMultiplier: 0.8,
          damageMultiplier: 1.0,
          defenseMultiplier: 1.5,
          color: Color(r: 0, g: 150, b: 150, a: 255),
          visualEffect: "pulse",
          specialBehavior: "slow_time",
          attacks: @[
            BossAttack(
              attackType: bapTeleport,
              damage: 3.0,
              cooldown: 4.0,
              projectileSpeed: 0.0,
              projectileCount: 2,
              spreadAngle: 0.0,
              durationOrRadius: 300.0,
              specialData: "time_echo"
            ),
            BossAttack(
              attackType: bapWave,
              damage: 2.0,
              cooldown: 2.0,
              projectileSpeed: 150.0,
              projectileCount: 8,
              spreadAngle: 45.0,
              durationOrRadius: 0.0,
              specialData: "temporal_wave"
            )
          ]
        ),
        BossPhaseDefinition(
          name: "Present",
          hpThreshold: 0.6,
          speedMultiplier: 1.2,
          damageMultiplier: 1.5,
          defenseMultiplier: 1.3,
          color: Color(r: 50, g: 200, b: 200, a: 255),
          visualEffect: "aura",
          specialBehavior: "time_distortion",
          attacks: @[
            BossAttack(
              attackType: bapTeleport,
              damage: 4.0,
              cooldown: 3.0,
              projectileSpeed: 0.0,
              projectileCount: 4,
              spreadAngle: 0.0,
              durationOrRadius: 350.0,
              specialData: "echo_burst"
            ),
            BossAttack(
              attackType: bapCircle,
              damage: 3.0,
              cooldown: 2.5,
              projectileSpeed: 180.0,
              projectileCount: 24,
              spreadAngle: 360.0,
              durationOrRadius: 0.0,
              specialData: "time_ring"
            ),
            BossAttack(
              attackType: bapPulse,
              damage: 3.0,
              cooldown: 5.0,
              projectileSpeed: 200.0,
              projectileCount: 0,
              spreadAngle: 0.0,
              durationOrRadius: 250.0,
              specialData: "chrono_pulse"
            )
          ]
        ),
        BossPhaseDefinition(
          name: "Future",
          hpThreshold: 0.4,
          speedMultiplier: 1.8,
          damageMultiplier: 2.0,
          defenseMultiplier: 1.0,
          color: Color(r: 100, g: 255, b: 255, a: 255),
          visualEffect: "glow",
          specialBehavior: "time_collapse",
          attacks: @[
            BossAttack(
              attackType: bapTeleport,
              damage: 5.0,
              cooldown: 2.0,
              projectileSpeed: 0.0,
              projectileCount: 6,
              spreadAngle: 0.0,
              durationOrRadius: 400.0,
              specialData: "temporal_collapse"
            ),
            BossAttack(
              attackType: bapBarrage,
              damage: 3.0,
              cooldown: 2.5,
              projectileSpeed: 280.0,
              projectileCount: 48,
              spreadAngle: 360.0,
              durationOrRadius: 0.0,
              specialData: "time_shatter"
            ),
            BossAttack(
              attackType: bapLaser,
              damage: 4.0,
              cooldown: 4.0,
              projectileSpeed: 0.0,
              projectileCount: 4,
              spreadAngle: 90.0,
              durationOrRadius: 4.0,
              specialData: "temporal_beam"
            )
          ]
        )
      ]
    )
  
  of 11:  # Wave 55 - THE CHAOS WEAVER
    result = BossDefinition(
      name: "The Chaos Weaver",
      bossID: 11,
      baseHP: 1800.0,
      baseSpeed: 90.0,
      baseDamage: 5,
      baseRadius: 58.0,
      color: Color(r: 180, g: 0, b: 180, a: 255),
      description: "Weaves patterns of pure chaos, unpredictable and devastating",
      specialAbilities: @["chaos_field", "random_teleport", "entropy_burst"],
      phases: @[
        BossPhaseDefinition(
          name: "Discord",
          hpThreshold: 1.0,
          speedMultiplier: 1.3,
          damageMultiplier: 1.0,
          defenseMultiplier: 1.3,
          color: Color(r: 180, g: 0, b: 180, a: 255),
          visualEffect: "pulse",
          specialBehavior: "chaotic_movement",
          attacks: @[
            BossAttack(
              attackType: bapBarrage,
              damage: 2.0,
              cooldown: 1.5,
              projectileSpeed: 200.0,
              projectileCount: 15,
              spreadAngle: 180.0,
              durationOrRadius: 0.0,
              specialData: "random_spread"
            ),
            BossAttack(
              attackType: bapTeleport,
              damage: 3.0,
              cooldown: 3.0,
              projectileSpeed: 0.0,
              projectileCount: 0,
              spreadAngle: 0.0,
              durationOrRadius: 400.0,
              specialData: "chaos_blink"
            ),
            BossAttack(
              attackType: bapWave,
              damage: 2.0,
              cooldown: 2.0,
              projectileSpeed: 220.0,
              projectileCount: 6,
              spreadAngle: 60.0,
              durationOrRadius: 0.0
            )
          ]
        ),
        BossPhaseDefinition(
          name: "Entropy",
          hpThreshold: 0.6,
          speedMultiplier: 1.6,
          damageMultiplier: 1.5,
          defenseMultiplier: 1.1,
          color: Color(r: 200, g: 40, b: 200, a: 255),
          visualEffect: "aura",
          specialBehavior: "entropy_field",
          attacks: @[
            BossAttack(
              attackType: bapBarrage,
              damage: 3.0,
              cooldown: 1.0,
              projectileSpeed: 250.0,
              projectileCount: 24,
              spreadAngle: 360.0,
              durationOrRadius: 0.0,
              specialData: "entropy_burst"
            ),
            BossAttack(
              attackType: bapTeleport,
              damage: 4.0,
              cooldown: 2.0,
              projectileSpeed: 0.0,
              projectileCount: 3,
              spreadAngle: 0.0,
              durationOrRadius: 450.0,
              specialData: "reality_shift"
            ),
            BossAttack(
              attackType: bapCircle,
              damage: 3.0,
              cooldown: 2.5,
              projectileSpeed: 170.0,
              projectileCount: 28,
              spreadAngle: 360.0,
              durationOrRadius: 0.0
            ),
            BossAttack(
              attackType: bapLaser,
              damage: 4.0,
              cooldown: 4.0,
              projectileSpeed: 0.0,
              projectileCount: 5,
              spreadAngle: 72.0,
              durationOrRadius: 3.5,
              specialData: "chaos_beam"
            )
          ]
        ),
        BossPhaseDefinition(
          name: "Pure Chaos",
          hpThreshold: 0.35,
          speedMultiplier: 2.0,
          damageMultiplier: 2.0,
          defenseMultiplier: 0.9,
          color: Color(r: 255, g: 100, b: 255, a: 255),
          visualEffect: "glow",
          specialBehavior: "total_chaos",
          attacks: @[
            BossAttack(
              attackType: bapBarrage,
              damage: 4.0,
              cooldown: 0.8,
              projectileSpeed: 300.0,
              projectileCount: 40,
              spreadAngle: 360.0,
              durationOrRadius: 0.0,
              specialData: "chaos_storm"
            ),
            BossAttack(
              attackType: bapTeleport,
              damage: 5.0,
              cooldown: 1.5,
              projectileSpeed: 0.0,
              projectileCount: 5,
              spreadAngle: 0.0,
              durationOrRadius: 500.0,
              specialData: "dimensional_chaos"
            ),
            BossAttack(
              attackType: bapPulse,
              damage: 4.0,
              cooldown: 3.0,
              projectileSpeed: 280.0,
              projectileCount: 0,
              spreadAngle: 0.0,
              durationOrRadius: 300.0,
              specialData: "entropy_wave"
            )
          ]
        )
      ]
    )
  
  of 12:  # Wave 60 - THE OMEGA ENTITY (FINAL CUSTOM BOSS)
    result = BossDefinition(
      name: "The Omega Entity",
      bossID: 12,
      baseHP: 2500.0,
      baseSpeed: 85.0,
      baseDamage: 6,
      baseRadius: 70.0,
      color: Color(r: 255, g: 50, b: 50, a: 255),
      description: "The ultimate challenge - combines all previous boss mechanics",
      specialAbilities: @["omni_attack", "adaptive_defense", "final_form"],
      phases: @[
        BossPhaseDefinition(
          name: "Alpha Phase",
          hpThreshold: 1.0,
          speedMultiplier: 1.0,
          damageMultiplier: 1.0,
          defenseMultiplier: 1.5,
          color: Color(r: 255, g: 50, b: 50, a: 255),
          visualEffect: "shield",
          specialBehavior: "balanced_assault",
          attacks: @[
            BossAttack(
              attackType: bapSpiral,
              damage: 3.0,
              cooldown: 2.5,
              projectileSpeed: 180.0,
              projectileCount: 12,
              spreadAngle: 30.0,
              durationOrRadius: 0.0
            ),
            BossAttack(
              attackType: bapOrbit,
              damage: 3.0,
              cooldown: 1.0,
              projectileSpeed: 120.0,
              projectileCount: 6,
              spreadAngle: 60.0,
              durationOrRadius: 250.0
            ),
            BossAttack(
              attackType: bapLaser,
              damage: 4.0,
              cooldown: 4.0,
              projectileSpeed: 0.0,
              projectileCount: 4,
              spreadAngle: 90.0,
              durationOrRadius: 4.0
            )
          ]
        ),
        BossPhaseDefinition(
          name: "Beta Phase",
          hpThreshold: 0.7,
          speedMultiplier: 1.3,
          damageMultiplier: 1.3,
          defenseMultiplier: 1.3,
          color: Color(r: 255, g: 100, b: 0, a: 255),
          visualEffect: "aura",
          specialBehavior: "aggressive_mixed",
          attacks: @[
            BossAttack(
              attackType: bapMeteor,
              damage: 4.0,
              cooldown: 3.0,
              projectileSpeed: 350.0,
              projectileCount: 6,
              spreadAngle: 0.0,
              durationOrRadius: 120.0
            ),
            BossAttack(
              attackType: bapChain,
              damage: 4.0,
              cooldown: 3.5,
              projectileSpeed: 0.0,
              projectileCount: 6,
              spreadAngle: 0.0,
              durationOrRadius: 400.0
            ),
            BossAttack(
              attackType: bapBarrage,
              damage: 3.0,
              cooldown: 2.0,
              projectileSpeed: 250.0,
              projectileCount: 32,
              spreadAngle: 360.0,
              durationOrRadius: 0.0
            )
          ]
        ),
        BossPhaseDefinition(
          name: "Gamma Phase",
          hpThreshold: 0.5,
          speedMultiplier: 1.5,
          damageMultiplier: 1.6,
          defenseMultiplier: 1.1,
          color: Color(r: 255, g: 255, b: 0, a: 255),
          visualEffect: "pulse",
          specialBehavior: "adaptive_combat",
          attacks: @[
            BossAttack(
              attackType: bapTeleport,
              damage: 5.0,
              cooldown: 2.5,
              projectileSpeed: 0.0,
              projectileCount: 4,
              spreadAngle: 0.0,
              durationOrRadius: 400.0
            ),
            BossAttack(
              attackType: bapDash,
              damage: 5.0,
              cooldown: 3.0,
              projectileSpeed: 650.0,
              projectileCount: 0,
              spreadAngle: 0.0,
              durationOrRadius: 0.0
            ),
            BossAttack(
              attackType: bapPulse,
              damage: 4.0,
              cooldown: 4.0,
              projectileSpeed: 280.0,
              projectileCount: 0,
              spreadAngle: 0.0,
              durationOrRadius: 300.0
            ),
            BossAttack(
              attackType: bapCircle,
              damage: 3.0,
              cooldown: 2.0,
              projectileSpeed: 200.0,
              projectileCount: 32,
              spreadAngle: 360.0,
              durationOrRadius: 0.0
            )
          ]
        ),
        BossPhaseDefinition(
          name: "Omega Phase",
          hpThreshold: 0.25,
          speedMultiplier: 2.0,
          damageMultiplier: 2.5,
          defenseMultiplier: 1.0,
          color: Color(r: 255, g: 0, b: 255, a: 255),
          visualEffect: "glow",
          specialBehavior: "final_form",
          attacks: @[
            BossAttack(
              attackType: bapBarrage,
              damage: 5.0,
              cooldown: 1.0,
              projectileSpeed: 320.0,
              projectileCount: 60,
              spreadAngle: 360.0,
              durationOrRadius: 0.0,
              specialData: "omega_barrage"
            ),
            BossAttack(
              attackType: bapLaser,
              damage: 6.0,
              cooldown: 3.0,
              projectileSpeed: 0.0,
              projectileCount: 8,
              spreadAngle: 45.0,
              durationOrRadius: 5.0,
              specialData: "omega_beam"
            ),
            BossAttack(
              attackType: bapTeleport,
              damage: 6.0,
              cooldown: 2.0,
              projectileSpeed: 0.0,
              projectileCount: 6,
              spreadAngle: 0.0,
              durationOrRadius: 500.0,
              specialData: "omega_blink"
            ),
            BossAttack(
              attackType: bapPulse,
              damage: 5.0,
              cooldown: 3.5,
              projectileSpeed: 300.0,
              projectileCount: 0,
              spreadAngle: 0.0,
              durationOrRadius: 350.0,
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

proc isCustomBoss*(waveNumber: int): bool =
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
  if not isCustomBoss(waveNumber):
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
  let waveScale = 1.0 + ((waveNumber.float32 - 5.0) * 0.05)  # 5% increase per wave after wave 5
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
