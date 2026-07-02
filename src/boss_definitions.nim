## Boss Definitions System
## Allows complete customization of boss behavior, properties, attacks, and phases

import math, random, raylib
import localization, types

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
    bapMinionVolley      # Living summoned adds fire at the player in unison (Summoner King)

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
    specialAbilities*: seq[string]
    description*: string
    weakPoint*: BossWeakPointDefinition

proc bossWeakPointDefinitionFor*(bossID: int): BossWeakPointDefinition =
  # Body damage is heavily resisted; the real damage happens in the weak-point
  # vulnerability window. The body/window gap (not raw HP) is what forces players
  # to engage mechanics instead of facetanking. The gap widens on higher bosses
  # because those were the worst offenders for "just shoot to win":
  #   tier 1-4  ~3.6x   tier 5-8  ~6x   tier 9-11 ~11x   tier 12 ~17x
  let (bodyMult, weakMult, exposure) =
    if bossID in 1..4:
      (0.55'f32, 1.90'f32, 2.4'f32)
    elif bossID in 5..8:
      (0.40'f32, 2.50'f32, 2.2'f32)
    elif bossID in 9..11:
      (0.28'f32, 3.00'f32, 2.0'f32)
    elif bossID == 12:
      (0.20'f32, 3.40'f32, 1.8'f32)
    else:
      (1.0'f32, 1.0'f32, 0.0'f32)

  proc spec(kind: BossWeakObjectiveKind, requiredHits, targetCount: int): BossWeakPointDefinition =
    BossWeakPointDefinition(
      kind: kind,
      requiredHits: requiredHits,
      targetCount: targetCount,
      bodyDamageMultiplier: bodyMult,
      weakCoreMultiplier: weakMult,
      exposureDuration: exposure,
      cooldownDuration: 1.0'f32,
      targetHitRadius: 22.0'f32
    )

  case bossID
  of 1: spec(bwoSpiralAnchors, 3, 3)
  of 2: spec(bwoSummonSigils, 3, 3)
  of 3: spec(bwoMeteorCracks, 2, 2)
  of 4: spec(bwoLaserPrisms, 2, 2)
  of 5: spec(bwoVoidRifts, 1, 3)
  of 6: spec(bwoCoilSequence, 3, 3)  # Tap the discharge coils in order -> overload window
  of 7: spec(bwoSatelliteSet, 3, 0)  # All satellites down -> vulnerability window
  of 8:
    var s = spec(bwoDashBackPlate, 3, 3)
    s.targetHitRadius = 32.0'f32  # Larger crack-plate hitboxes for the Juggernaut
    s
  of 9: spec(bwoPrismSequence, 3, 3)
  of 10: spec(bwoClockNodes, 2, 4)
  of 11: spec(bwoChaosAnomalies, 3, 3)
  of 12: spec(bwoOmegaCycle, 3, 3)
  else: BossWeakPointDefinition(kind: bwoNone)

proc getBossDefinition*(bossNumber: int): BossDefinition =
  case bossNumber
  of 1:  # Wave 5 - THE SPIRAL GUARDIAN
    result = BossDefinition(
      name: t(tkBoss1Name),
      bossID: 1,
      baseHP: 125.0,
      baseSpeed: 50.0,
      baseDamage: 1,
      baseRadius: 45.0,
      color: Color(r: 100, g: 50, b: 200, a: 255),
      description: t(tkBoss1Desc),
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
              cooldown: 1.0,            # was 0.8 -> 1.0: a touch more breathing room between coils
              projectileSpeed: 160.0,
              projectileCount: 7,       # was 10: thinner arm; ~15 bullets/volley instead of 21
              spreadAngle: 45.0,
              durationOrRadius: 2.0  # spiral turns: a big screen-filling coil (the Guardian's signature)
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
              cooldown: 1.1,            # was 0.9 -> 1.1: rage stays relentless but no longer wall-to-wall
              projectileSpeed: 170.0,
              projectileCount: 9,       # was 12: ~21 bullets/volley instead of 31
              spreadAngle: 30.0,
              durationOrRadius: 2.5  # rage: an even larger, screen-filling spiral fired almost continuously
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
      name: t(tkBoss2Name),
      bossID: 2,
      baseHP: 250.0,  # durability buff: was 220 -> 250; was dying too fast off its add-clear windows, now a tankier wall to grind through while clearing the legion
      baseSpeed: 65.0,
      baseDamage: 1,
      baseRadius: 50.0,
      color: Color(r: 50, g: 150, b: 50, a: 255),
      description: t(tkBoss2Desc),
      specialAbilities: @["summon_master", "minion_empowerment"],
      phases: @[
        BossPhaseDefinition(
          name: "Legion's Call",
          hpThreshold: 1.0,
          speedMultiplier: 0.9,
          damageMultiplier: 1.0,
          defenseMultiplier: 1.1,  # durability buff: shielded/defensive opening now resists ~10% of body damage (scales window damage equally, so the weak-point gap is preserved)
          color: Color(r: 50, g: 150, b: 50, a: 255),
          visualEffect: "shield",
          specialBehavior: "defensive",
          attacks: @[
            BossAttack(
              attackType: bapSummon,
              damage: 0.0,
              cooldown: 2.5,  # reduced from 4.5: timer only ticks after adds are cleared
              projectileSpeed: 0.0,
              projectileCount: 4,
              spreadAngle: 0.0,
              durationOrRadius: 0.0,
              specialData: "minion_circle"
            ),
            BossAttack(
              # Generic wave demoted to occasional filler so the themed attacks lead.
              attackType: bapWave,
              damage: 1.0,
              cooldown: 5.5,
              projectileSpeed: 160.0,
              projectileCount: 5,
              spreadAngle: 50.0,
              durationOrRadius: 0.0,
              bulletRadius: 10.0
            ),
            BossAttack(
              # Royal Sigils: slow golden homing sigils that gently track the player.
              attackType: bapTargeted,
              damage: 1.0,
              cooldown: 5.0, # Match Royal Sigils lifetime
              projectileSpeed: 130.0,
              projectileCount: 5,
              spreadAngle: 125.0,
              durationOrRadius: 0.0,
              bulletRadius: 8.0,
              specialData: "royal_sigils"
            ),
            BossAttack(
              # Legion Volley: short cooldown so the legion pressures the player
              # while they clear the sealed wave.
              attackType: bapMinionVolley,
              damage: 1.0,
              cooldown: 1.8,
              projectileSpeed: 165.0,
              projectileCount: 5,  # fallback fan when no adds are alive
              spreadAngle: 45.0,
              durationOrRadius: 0.0,
              bulletRadius: 8.0
            ),
            BossAttack(
              # Banishment Nova: occasional telegraphed green ring for spatial pressure.
              attackType: bapPulse,
              damage: 1.0,
              cooldown: 6.0,
              projectileSpeed: 135.0,
              projectileCount: 0,
              spreadAngle: 0.0,
              durationOrRadius: 0.0,
              bulletRadius: 8.0,
              specialData: "banish_nova"
            )
          ]
        ),
        BossPhaseDefinition(
          name: "Swarm Commander",
          hpThreshold: 0.6,
          speedMultiplier: 1.0,
          damageMultiplier: 1.2,
          defenseMultiplier: 1.05,  # durability buff: raised from 0.95; kept below the defensive opening (1.1) to preserve the roster's "squishier when enraged" step-down
          color: Color(r: 30, g: 200, b: 30, a: 255),
          visualEffect: "glow",
          specialBehavior: "summon_frenzy",
          attacks: @[
            BossAttack(
              attackType: bapSummon,
              damage: 0.0,
              cooldown: 2.0,  # reduced from 3.75: timer only ticks after adds are cleared
              projectileSpeed: 0.0,
              projectileCount: 3,
              spreadAngle: 0.0,
              durationOrRadius: 0.0,
              specialData: "minion_triangle"
            ),
            BossAttack(
              # Generic burst demoted to occasional filler.
              attackType: bapBurst,
              damage: 1.0,
              cooldown: 5.0,
              projectileSpeed: 175.0,
              projectileCount: 5,
              spreadAngle: 60.0,
              durationOrRadius: 0.0,
              bulletRadius: 9.0
            ),
            BossAttack(
              # Generic ring demoted to occasional filler.
              attackType: bapCircle,
              damage: 1.0,
              cooldown: 6.5,
              projectileSpeed: 165.0,
              projectileCount: 10,
              spreadAngle: 360.0,
              durationOrRadius: 0.0,
              bulletRadius: 12.5
            ),
            BossAttack(
              # Royal Sigils: a wider fan of notably larger homing sigils than phase 1.
              attackType: bapTargeted,
              damage: 1.0,
              cooldown: 5.0, # Match Royal Sigils lifetime
              projectileSpeed: 140.0,
              projectileCount: 7,
              spreadAngle: 165.0,
              durationOrRadius: 0.0,
              bulletRadius: 14.0,
              specialData: "royal_sigils"
            ),
            BossAttack(
              # Faster Legion Volley to match the tighter phase-2 summon loop.
              attackType: bapMinionVolley,
              damage: 1.0,
              cooldown: 1.5,
              projectileSpeed: 180.0,
              projectileCount: 5,  # fallback fan when no adds are alive
              spreadAngle: 50.0,
              durationOrRadius: 0.0,
              bulletRadius: 8.0
            )
          ]
        )
      ]
    )

  of 3:  # Wave 15 - THE METEOR STRIKER
    result = BossDefinition(
      name: t(tkBoss3Name),
      bossID: 3,
      baseHP: 330.0,  # small general buff: +10% pool (was 300)
      baseSpeed: 65.0,
      baseDamage: 2,
      baseRadius: 48.0,
      color: Color(r: 255, g: 100, b: 0, a: 255),
      description: t(tkBoss3Desc),
      specialAbilities: @["meteor_shower", "impact_zone"],
      phases: @[
        BossPhaseDefinition(
          name: "Orbital Strike",
          hpThreshold: 1.0,
          speedMultiplier: 0.95,  # NERFED from 1.05
          damageMultiplier: 1.05,  # small general buff: was 1.0
          defenseMultiplier: 1.05,  # small general buff: was 1.0 (slightly sturdier opening)
          color: Color(r: 255, g: 100, b: 0, a: 255),
          visualEffect: "pulse",
          specialBehavior: "circle_player",
          attacks: @[
            BossAttack(
              attackType: bapMeteor,
              damage: 2.0,
              cooldown: 3.75,  # rework: slightly longer cadence (was 3.2) to make room for the volley
              projectileSpeed: 280.0,
              projectileCount: 4,
              spreadAngle: 0.0,
              durationOrRadius: 80.0,
              specialData: "warn_impact"
            ),
            BossAttack(
              # NEW signature: aimed cluster of oversized rocks slams the player's spot.
              attackType: bapMeteor,
              damage: 2.0,
              cooldown: 5.5,
              projectileSpeed: 0.0,   # uses the falling-rock system's own fall speed
              projectileCount: 3,     # ACTIVE for this mode (rock count), unlike the column modes
              spreadAngle: 0.0,
              durationOrRadius: 0.0,
              bulletRadius: 12.0,
              specialData: "meteor_volley"
            ),
            BossAttack(
              attackType: bapTargeted,
              damage: 1.0,
              cooldown: 2.1,  # rework NERF: was 1.75
              projectileSpeed: 185.0,  # rework NERF: was 200.0
              projectileCount: 2,  # rework NERF: was 3
              spreadAngle: 40.0,  # rework NERF: tighter, was 45.0
              durationOrRadius: 0.0
            )
          ]
        ),
        BossPhaseDefinition(
          name: "Cataclysm",
          hpThreshold: 0.5,
          speedMultiplier: 1.0,  # NERFED from 1.1
          damageMultiplier: 1.25,  # small general buff: was 1.2 (NERFED from 1.5)
          defenseMultiplier: 1.0,
          color: Color(r: 255, g: 50, b: 0, a: 255),
          visualEffect: "aura",
          specialBehavior: "meteor_storm",
          attacks: @[
            BossAttack(
              attackType: bapMeteor,
              damage: 2.0,
              cooldown: 3.0,  # rework NERF: slower column cadence, was 2.3
              projectileSpeed: 330.0,
              projectileCount: 7,  # NOTE: inert for column meteors, count comes from screen layout (zoneWidth / bRadius*5); density is tuned via "massive_impact" bullet-radius scaling
              spreadAngle: 0.0,
              durationOrRadius: 100.0,
              specialData: "massive_impact"
            ),
            BossAttack(
              # NEW signature: rocks rain in a ring around the player; the eye is safe.
              attackType: bapMeteor,
              damage: 2.0,
              cooldown: 6.5,
              projectileSpeed: 0.0,
              projectileCount: 8,     # ACTIVE for this mode (rocks in the ring)
              spreadAngle: 0.0,
              durationOrRadius: 0.0,
              bulletRadius: 11.0,
              specialData: "meteor_ring"
            ),
            BossAttack(
              attackType: bapPulse,
              damage: 1.0,
              cooldown: 5.25,  # rework NERF: was 4.5
              projectileSpeed: 175.0,  # rework NERF: was 190.0
              projectileCount: 0,
              spreadAngle: 0.0,
              durationOrRadius: 135.0  # rework NERF: smaller shockwave, was 150.0
            )
          ]
        ),
        BossPhaseDefinition(
          name: "Apocalypse",
          hpThreshold: 0.25,
          speedMultiplier: 1.1,
          damageMultiplier: 1.35,  # small general buff: was 1.3
          defenseMultiplier: 1.075,
          color: Color(r: 255, g: 0, b: 0, a: 255),
          visualEffect: "glow",
          specialBehavior: "enraged",
          attacks: @[
            BossAttack(
              attackType: bapMeteor,
              damage: 2.5,
              cooldown: 2.5,  # rework NERF: slower apocalypse rain, was 1.75
              projectileSpeed: 370.0,
              projectileCount: 11,  # NOTE: inert for column meteors, count comes from screen layout (zoneWidth / bRadius*5); density is tuned via "apocalypse_mode" bullet-radius scaling
              spreadAngle: 0.0,
              durationOrRadius: 120.0,
              specialData: "apocalypse_mode"
            ),
            BossAttack(
              # NEW signature finale: diagonal comets sweep across the arena, one safe lane.
              attackType: bapMeteor,
              damage: 2.0,
              cooldown: 5.0,
              projectileSpeed: 440.0,  # ACTIVE: comet travel speed along the angled path
              projectileCount: 16,     # ACTIVE: max comet count cap (actual count fills the entry band at threadable spacing)
              spreadAngle: 0.0,
              durationOrRadius: 0.0,
              bulletRadius: 11.0,
              specialData: "comet_cascade"
            ),
            BossAttack(
              attackType: bapCircle,
              damage: 1.0,
              cooldown: 4.0,  # rework NERF: was 3.0
              projectileSpeed: 158.0,  # rework NERF: was 170.0
              projectileCount: 11,  # rework NERF: was 16
              spreadAngle: 360.0,
              durationOrRadius: 0.0
            )
          ]
        )
      ]
    )

  of 4:  # Wave 20 - THE LASER ARCHITECT
    result = BossDefinition(
      name: t(tkBoss4Name),
      bossID: 4,
      baseHP: 500.0,
      baseSpeed: 65.0,
      baseDamage: 2,
      baseRadius: 52.0,
      color: Color(r: 0, g: 200, b: 255, a: 255),
      description: t(tkBoss4Desc),
      specialAbilities: @["laser_geometry", "grid_lock"],
      phases: @[
        BossPhaseDefinition(
          name: "Blueprint",
          hpThreshold: 1.0,
          speedMultiplier: 1.0,
          damageMultiplier: 1.0,
          defenseMultiplier: 1.2,
          color: Color(r: 0, g: 200, b: 255, a: 255),
          visualEffect: "shield",
          specialBehavior: "geometric_movement",
          attacks: @[
            BossAttack(
              attackType: bapLaser,
              damage: 3.0,
              cooldown: 4.5,  # NERFED from 3.5
              projectileSpeed: 0.0,
              projectileCount: 3,
              spreadAngle: 90.0,
              durationOrRadius: 2.5,  # NERFED from 3.0
              specialData: "cross_laser"
            ),
            BossAttack(
              attackType: bapWave,
              damage: 2.5,
              cooldown: 2.75,  # NERFED from 2.25
              projectileSpeed: 160.0,  # NERFED from 180.0
              projectileCount: 5,  # NERFED from 6
              spreadAngle: 45.0,  # NERFED from 50.0 (tighter)
              durationOrRadius: 0.0
            ),
            BossAttack(
              attackType: bapTargeted,
              damage: 2.5,
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
          speedMultiplier: 1.175,  # NERFED from 1.33
          damageMultiplier: 1.2,  # NERFED from 1.33
          defenseMultiplier: 1.1,
          color: Color(r: 0, g: 255, b: 255, a: 255),
          visualEffect: "pulse",
          specialBehavior: "laser_web",
          attacks: @[
            BossAttack(
              attackType: bapLaser,
              damage: 4.0,
              cooldown: 3.5,  # NERFED from 2.2
              projectileSpeed: 0.0,
              projectileCount: 2,
              spreadAngle: 45.0,
              durationOrRadius: 2.2,  # dodge buff: shorter active beam window, was 3.0
              specialData: "rotating_grid"
            ),
            BossAttack(
              attackType: bapTargeted,
              damage: 2.5,
              cooldown: 1.5,  # NERFED from 0.8
              projectileSpeed: 260.0,  # NERFED from 300.0
              projectileCount: 3,  # NERFED from 4
              spreadAngle: 15.0,  # NERFED from 20.0 (tighter)
              durationOrRadius: 0.0
            ),
            BossAttack(
              attackType: bapCircle,
              damage: 2.5,
              cooldown: 4.5,  # NERFED from 3.5
              projectileSpeed: 145.0,  # NERFED from 160.0
              projectileCount: 12,  # NERFED from 16
              spreadAngle: 360.0,
              durationOrRadius: 0.0
            ),
            BossAttack(
              attackType: bapBurst,  # NERFED: Less aggressive burst
              damage: 2.5,
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
          speedMultiplier: 1.175,  # NERFED from 1.3
          damageMultiplier: 1.2,  # NERFED from 1.3
          defenseMultiplier: 1.0,
          color: Color(r: 100, g: 255, b: 255, a: 255),
          visualEffect: "aura",
          specialBehavior: "laser_chaos",
          attacks: @[
            BossAttack(
              # Signature mega finale: the boss freezes, hardens, plays a charge
              # animation and cancels its other attacks, then fires a single beam
              # aimed at the player that ricochets 20 times off the screen edges.
              # Long 2.5s telegraph (RicochetLaserTelegraph) + long cooldown make
              # it a rare, readable "clear the whole arena" moment.
              attackType: bapLaser,
              damage: 9.0,  # huge: fully telegraphed + can only land one hit
              cooldown: 19.0,
              projectileSpeed: 0.0,
              projectileCount: 20,  # bounce count
              spreadAngle: 0.0,
              durationOrRadius: 0.0,
              specialData: "ricochet_laser"
            ),
            BossAttack(
              attackType: bapLaser,
              damage: 4.5,
              cooldown: 5.0,  # NERFED from 2.5
              projectileSpeed: 0.0,
              projectileCount: 8,
              spreadAngle: 22.5,
              durationOrRadius: 1.5,  # dodge buff: shorter active beam window, was 2.5
              specialData: "prismatic_cage"
            ),
            BossAttack(
              attackType: bapLaser,
              damage: 4.5,
              cooldown: 1.8,
              projectileSpeed: 0.0,
              projectileCount: 1,
              spreadAngle: 0.0,
              durationOrRadius: 1.1,  # dodge buff: shorter active beam window, was 1.5
              specialData: "laser_snipe"  # Rapid tracking lasers
            ),
            BossAttack(
              attackType: bapCircle,
              damage: 2.5,
              cooldown: 4.5,  # NERFED from 3.5
              projectileSpeed: 140.0,  # NERFED from 155.0
              projectileCount: 14,  # NERFED from 16
              spreadAngle: 360.0,
              durationOrRadius: 0.0
            ),
            BossAttack(
              attackType: bapBarrage,
              damage: 2.5,
              cooldown: 6.0,  # NERFED from 4.5
              projectileSpeed: 190.0,  # NERFED from 210.0
              projectileCount: 14,  # NERFED from 20
              spreadAngle: 360.0,
              durationOrRadius: 0.0
            ),
            BossAttack(
              attackType: bapPulse,
              damage: 2.5,
              cooldown: 6.5,  # NERFED from 5.0
              projectileSpeed: 160.0,  # NERFED from 175.0
              projectileCount: 0,
              spreadAngle: 0.0,
              durationOrRadius: 140.0  # NERFED from 160.0
            ),
            BossAttack(
              attackType: bapTargeted,
              damage: 2.5,
              cooldown: 2.0,  # NERFED from 1.2
              projectileSpeed: 250.0,  # NERFED from 280.0
              projectileCount: 2,  # NERFED from 3
              spreadAngle: 12.0,  # NERFED from 18.0
              durationOrRadius: 0.0
            )
          ]
        )
      ]
    )

  of 5:  # Wave 25 - THE VOID DANCER
    result = BossDefinition(
      name: t(tkBoss5Name),
      bossID: 5,
      baseHP: 800.0,
      baseSpeed: 65.0,  # NERFED from 70.0
      baseDamage: 3,
      baseRadius: 46.0,
      color: Color(r: 80, g: 0, b: 120, a: 255),
      description: t(tkBoss5Desc),
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
              damage: 6.0,
              cooldown: 3.0,
              projectileSpeed: 0.0,
              projectileCount: 5,
              spreadAngle: 0.0,
              durationOrRadius: 200.0,
              specialData: "afterimage_burst"
            ),
            # Void Rift: signature themed attack - tears 2 collapsing rifts that
            # erupt into zone damage + a radial void spray. Leads alongside teleport.
            BossAttack(
              attackType: bapMeteor,  # nominal; routed by specialData before attackType dispatch
              damage: 6.0,
              cooldown: 4.0,
              projectileSpeed: 150.0,
              projectileCount: 8,  # radial void bullets per rift
              spreadAngle: 0.0,
              durationOrRadius: 90.0,  # rift zone radius
              specialData: "void_rift"
            ),
            BossAttack(
              attackType: bapBurst,
              damage: 6.0,
              cooldown: 6.0,  # demoted to occasional filler (was 2.5)
              projectileSpeed: 180.0,
              projectileCount: 5,
              spreadAngle: 35.0,
              durationOrRadius: 0.0
            ),
            BossAttack(
              attackType: bapTargeted,
              damage: 6.0,
              cooldown: 6.5,  # demoted to occasional filler (was 2.8)
              projectileSpeed: 220.0,
              projectileCount: 3,
              spreadAngle: 10.0,
              durationOrRadius: 0.0
            )
          ]
        ),
        BossPhaseDefinition(
          name: "Shadow Realm",
          hpThreshold: 0.6,
          speedMultiplier: 1.1,
          damageMultiplier: 1.1,  # NERFED from 1.3
          defenseMultiplier: 0.9,
          color: Color(r: 120, g: 0, b: 180, a: 255),
          visualEffect: "aura",
          specialBehavior: "clone_assault",
          attacks: @[
            BossAttack(
              attackType: bapTeleport,
              damage: 9.0,  # NERFED from 2.0
              cooldown: 3.0,  # NERFED from 2.5
              projectileSpeed: 0.0,
              projectileCount: 1,  # NERFED from 2
              spreadAngle: 0.0,
              durationOrRadius: 250.0,
              specialData: "triple_clone"
            ),
            # Void Rift Storm: 3 rifts with denser bursts - the Shadow Realm escalation.
            BossAttack(
              attackType: bapMeteor,  # nominal; routed by specialData
              damage: 9.0,
              cooldown: 4.0,
              projectileSpeed: 150.0,
              projectileCount: 10,
              spreadAngle: 0.0,
              durationOrRadius: 95.0,
              specialData: "void_rift_storm"
            ),
            BossAttack(
              attackType: bapWave,
              damage: 6.0,
              cooldown: 6.0,  # demoted to occasional filler (was 2.2)
              projectileSpeed: 160.0,
              projectileCount: 5,
              spreadAngle: 50.0,
              durationOrRadius: 0.0
            ),
            BossAttack(
              attackType: bapCircle,
              damage: 6.0,
              cooldown: 6.5,  # demoted to occasional filler (was 4.0)
              projectileSpeed: 160.0,
              projectileCount: 10,
              spreadAngle: 360.0,
              durationOrRadius: 0.0
            ),
            BossAttack(
              attackType: bapSpiral,
              damage: 6.0,
              cooldown: 6.0,  # demoted to occasional filler (was 3.2)
              projectileSpeed: 160.0,
              projectileCount: 7,
              spreadAngle: 30.0,
              durationOrRadius: 0.0
            )
          ]
        ),
        BossPhaseDefinition(
          name: "Void Ascension",
          hpThreshold: 0.35,
          speedMultiplier: 1.1,  # NERFED from 1.2
          damageMultiplier: 1.2,  # NERFED from 1.5
          defenseMultiplier: 0.9,
          color: Color(r: 160, g: 40, b: 220, a: 255),
          visualEffect: "glow",
          specialBehavior: "reality_break",
          attacks: @[
            BossAttack(
              attackType: bapTeleport,
              damage: 12.0,
              cooldown: 2.5,  # NERFED from 2.0
              projectileSpeed: 0.0,
              projectileCount: 2,  # NERFED from 3
              spreadAngle: 0.0,
              durationOrRadius: 300.0,
              specialData: "dimensional_rift"
            ),
            # Void Collapse: 4-5 converging rifts with the densest bursts - the
            # reality_break peak. Leads the phase alongside the teleport.
            BossAttack(
              attackType: bapMeteor,  # nominal; routed by specialData
              damage: 11.0,
              cooldown: 3.5,
              projectileSpeed: 160.0,
              projectileCount: 12,
              spreadAngle: 0.0,
              durationOrRadius: 110.0,
              specialData: "void_collapse"
            ),
            BossAttack(
              attackType: bapBarrage,
              damage: 6.0,
              cooldown: 6.5,  # demoted to occasional filler (was 3.5)
              projectileSpeed: 170.0,
              projectileCount: 16,
              spreadAngle: 240.0,
              durationOrRadius: 0.0
            ),
            BossAttack(
              attackType: bapPulse,
              damage: 6.0,
              cooldown: 6.5,  # demoted to occasional filler (was 5.0)
              projectileSpeed: 200.0,
              projectileCount: 0,
              spreadAngle: 0.0,
              durationOrRadius: 160.0,
            ),
            BossAttack(
              attackType: bapDash,
              damage: 6.0,
              cooldown: 5.5,  # kept long - reads as a void blink-dash
              projectileSpeed: 450.0,
              projectileCount: 0,
              spreadAngle: 0.0,
              durationOrRadius: 0.0
            ),
            BossAttack(
              attackType: bapWave,
              damage: 6.0,
              cooldown: 6.0,  # demoted to occasional filler (was 2.0)
              projectileSpeed: 190.0,
              projectileCount: 6,
              spreadAngle: 60.0,
              durationOrRadius: 0.0
            ),
            BossAttack(
              attackType: bapTargeted,
              damage: 6.0,
              cooldown: 6.5,  # demoted to occasional filler (was 1.5)
              projectileSpeed: 240.0,
              projectileCount: 2,
              spreadAngle: 12.0,
              durationOrRadius: 0.0
            )
          ]
        )
      ]
    )

  of 6:  # Wave 30 - THE CHAIN REACTOR
    result = BossDefinition(
      name: t(tkBoss6Name),
      bossID: 6,
      baseHP: 1100.0,
      baseSpeed: 60.0,
      baseDamage: 3,
      baseRadius: 55.0,
      color: Color(r: 255, g: 255, b: 0, a: 255),  # Bright electric yellow
      description: t(tkBoss6Desc),
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
              damage: 7.0,
              cooldown: 3.5,
              projectileSpeed: 0.0,
              projectileCount: 3,  # 3 chain lightning bolts
              spreadAngle: 0.0,
              durationOrRadius: 280.0,  # Range
              specialData: "chain_basic"
            ),
            BossAttack(
              # THUNDERSTRIKE: telegraphed ground lightning strikes (see
              # spawnThunderstrike). projectileCount = strikes, durationOrRadius = radius.
              attackType: bapMeteor,
              damage: 7.0,
              cooldown: 4.5,
              projectileSpeed: 0.0,
              projectileCount: 3,
              spreadAngle: 0.0,
              durationOrRadius: 70.0,
              specialData: "thunderstrike"
            ),
            BossAttack(
              attackType: bapTargeted,
              damage: 8.0,
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
              damage: 7.0,
              cooldown: 3.0,  # Nerf: slower chain cadence, less screen clutter
              projectileSpeed: 0.0,
              projectileCount: 5,  # More chains
              spreadAngle: 0.0,
              durationOrRadius: 320.0,
              specialData: "chain_storm"  # Multi-target chains
            ),
            BossAttack(
              # THUNDERSTRIKE: more strikes than phase 1.
              attackType: bapMeteor,
              damage: 7.0,
              cooldown: 4.5,  # Nerf: fewer, less frequent ground zones
              projectileSpeed: 0.0,
              projectileCount: 3,
              spreadAngle: 0.0,
              durationOrRadius: 68.0,
              specialData: "thunderstrike"
            ),
            BossAttack(
              attackType: bapPulse,
              damage: 8.0,
              cooldown: 5.0,  # Nerf: more recovery time
              projectileSpeed: 210.0,
              projectileCount: 0,
              spreadAngle: 0.0,
              durationOrRadius: 150.0,  # Nerf: smaller electric shockwave
              specialData: "electric_discharge"
            ),
            BossAttack(
              # ARC LATTICE: radial lightning beams with one safe wedge (see
              # spawnArcLattice). projectileCount = beams, durationOrRadius = thickness.
              attackType: bapLaser,
              damage: 8.0,
              cooldown: 6.5,  # Nerf: less frequent beam walls
              projectileSpeed: 0.0,
              projectileCount: 7,  # Nerf: fewer beams -> wider safe wedge
              spreadAngle: 0.0,
              durationOrRadius: 16.0,
              specialData: "arc_lattice"
            )
          ]
        ),
        BossPhaseDefinition(
          name: "Overload",
          hpThreshold: 0.3,
          speedMultiplier: 1.2,
          damageMultiplier: 1.3,
          defenseMultiplier: 0.9,
          color: Color(r: 255, g: 255, b: 255, a: 255),
          visualEffect: "glow",
          specialBehavior: "critical_discharge",  # Chaotic electric movement
          attacks: @[
            BossAttack(
              attackType: bapChain,
              damage: 10.5,
              cooldown: 2.5,  # Nerf: slower overload chains
              projectileSpeed: 0.0,
              projectileCount: 6,  # Nerf: fewer chains (was 8)
              spreadAngle: 0.0,
              durationOrRadius: 360.0,
              specialData: "chain_overload"  # Maximum chain effect
            ),
            BossAttack(
              # ARC LATTICE: denser beam fan (narrower wedge) in the final phase.
              attackType: bapLaser,
              damage: 9.0,
              cooldown: 6.0,  # Nerf: less frequent beam walls
              projectileSpeed: 0.0,
              projectileCount: 9,  # Nerf: fewer beams -> wider safe wedge (was 12)
              spreadAngle: 0.0,
              durationOrRadius: 18.0,
              specialData: "arc_lattice"
            ),
            BossAttack(
              # THUNDERSTRIKE: heavy barrage of ground strikes.
              attackType: bapMeteor,
              damage: 8.0,
              cooldown: 4.5,  # Nerf: less frequent strikes
              projectileSpeed: 0.0,
              projectileCount: 4,  # Nerf: fewer simultaneous ground zones (was 6)
              spreadAngle: 0.0,
              durationOrRadius: 66.0,
              specialData: "thunderstrike"
            ),
            BossAttack(
              attackType: bapPulse,
              damage: 9.5,
              cooldown: 5.5,  # Nerf: more recovery time
              projectileSpeed: 220.0,  # Nerf: slower shockwave, easier to outrun
              projectileCount: 0,
              spreadAngle: 0.0,
              durationOrRadius: 175.0,  # Nerf: smaller shockwave (was 200)
              specialData: "overload_pulse"  # Massive shockwave
            )
          ]
        )
      ]
    )

  of 7:  # Wave 35 - THE ORBITAL COMMANDER
    result = BossDefinition(
      name: t(tkBoss7Name),
      bossID: 7,
      baseHP: 1400.0,
      baseSpeed: 50.0,
      baseDamage: 3,
      baseRadius: 58.0,
      color: Color(r: 150, g: 100, b: 255, a: 255),
      description: t(tkBoss7Desc),
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
              damage: 10.5,
              cooldown: 1.0,
              projectileSpeed: 75.0,  # Orbital speed
              projectileCount: 3,  # 3 satellites
              spreadAngle: 120.0,
              durationOrRadius: 180.0,  # Wide orbit
              specialData: "satellite_orbit"  # Single layer orbit
            ),
            BossAttack(
              attackType: bapSnipe,
              damage: 10.5,
              cooldown: 4.0,
              projectileSpeed: 300.0,
              projectileCount: 1,
              spreadAngle: 0.0,
              durationOrRadius: 0.0,
              specialData: "orbital_snipe"  # Aimed from satellite
            ),
            BossAttack(
              # Orbital Scan: signature themed attack - a kill-satellite drags
              # a screen-spanning energy wall across the whole arena; the only
              # safe spot is the data-gap lane painted by the telegraph.
              attackType: bapMeteor,  # nominal; routed by specialData before attackType dispatch
              damage: 10.5,
              cooldown: 8.5,           # long: the crossing itself occupies ~4s
              projectileSpeed: 0.0,
              projectileCount: 1,      # walls per volley
              spreadAngle: 0.0,
              durationOrRadius: 95.0,  # safe-gap half-width
              specialData: "orbital_sweep"
            ),
            BossAttack(
              # Generic targeted demoted to occasional filler so the themed
              # satellite/gravity kit leads.
              attackType: bapTargeted,
              damage: 7.0,
              cooldown: 5.5,
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
              damage: 7.0,
              cooldown: 0.8,
              projectileSpeed: 90.0,
              projectileCount: 5,
              spreadAngle: 72.0,
              durationOrRadius: 200.0,
              specialData: "dual_layer_orbit"  # Two orbital layers
            ),
            BossAttack(
              attackType: bapSnipe,
              damage: 10.5,
              cooldown: 4.5,  # Eased: satellite-fired snipes converge from several angles now
              projectileSpeed: 300.0,
              projectileCount: 2,  # Double snipe
              spreadAngle: 20.0,
              durationOrRadius: 0.0,
              specialData: "precision_strike"
            ),
            BossAttack(
              # Orbital Scan: two crosswise walls, staggered - the second lane
              # opens perpendicular to the first, forcing a re-route mid-dodge.
              attackType: bapMeteor,  # nominal; routed by specialData
              damage: 12.0,
              cooldown: 9.5,
              projectileSpeed: 0.0,
              projectileCount: 2,
              spreadAngle: 0.0,
              durationOrRadius: 85.0,
              specialData: "orbital_sweep"
            ),
            BossAttack(
              # Generic ring demoted to occasional filler.
              attackType: bapCircle,
              damage: 10.5,
              cooldown: 8.0,
              projectileSpeed: 125.0,
              projectileCount: 12,  # Eased: sparser ring, dodgeable mid-sweep
              spreadAngle: 360.0,
              durationOrRadius: 0.0
            ),
            BossAttack(
              attackType: bapPulse,
              damage: 10.5,
              cooldown: 7.5,
              projectileSpeed: 150.0,
              projectileCount: 0,
              spreadAngle: 0.0,
              durationOrRadius: 190.0,  # Eased: smaller shockwave
              specialData: "gravity_pulse"  # Space-themed pulse
            )
          ]
        ),
        BossPhaseDefinition(
          name: "Orbital Supremacy",
          hpThreshold: 0.35,
          speedMultiplier: 1.15,
          damageMultiplier: 1.3,
          defenseMultiplier: 1.0,
          color: Color(r: 200, g: 150, b: 255, a: 255),
          visualEffect: "glow",
          specialBehavior: "orbital_chaos",  # Complex orbital patterns
          attacks: @[
            BossAttack(
              attackType: bapOrbit,
              damage: 14.0,
              cooldown: 0.6,
              projectileSpeed: 100.0,
              projectileCount: 6,  # Eased: fewer satellites = fewer laser sources (was 8)
              spreadAngle: 45.0,
              durationOrRadius: 220.0,
              specialData: "orbital_storm"  # Triple layer orbit
            ),
            BossAttack(
              attackType: bapSnipe,
              damage: 14.0,
              cooldown: 4.0,  # Eased: satellite-fired snipes converge from several angles now
              projectileSpeed: 330.0,
              projectileCount: 3,  # Triple precision strike
              spreadAngle: 25.0,
              durationOrRadius: 0.0,
              specialData: "satellite_barrage"
            ),
            BossAttack(
              # Orbital Scan finale: two crosswise walls with tighter gaps.
              attackType: bapMeteor,  # nominal; routed by specialData
              damage: 14.0,
              cooldown: 9.0,
              projectileSpeed: 0.0,
              projectileCount: 2,
              spreadAngle: 0.0,
              durationOrRadius: 72.0,
              specialData: "orbital_sweep"
            ),
            BossAttack(
              # Generic spray demoted to occasional filler.
              attackType: bapBarrage,
              damage: 14.0,
              cooldown: 6.5,
              projectileSpeed: 210.0,
              projectileCount: 16,  # Eased: sparser spray, dodgeable mid-sweep (was 24)
              spreadAngle: 360.0,
              durationOrRadius: 0.0,
              specialData: "orbital_bombardment"
            ),
            BossAttack(
              attackType: bapMeteor,
              damage: 14.0,
              cooldown: 6.5,
              projectileSpeed: 280.0,
              projectileCount: 4,  # Satellite drops (eased from 5)
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
      name: t(tkBoss8Name),
      bossID: 8,
      baseHP: 1750.0,
      baseSpeed: 40.0,
      baseDamage: 4,
      baseRadius: 60.0,
      color: Color(r: 200, g: 0, b: 0, a: 255),
      description: t(tkBoss8Desc),
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
              damage: 10.5,
              cooldown: 4.5,
              projectileSpeed: 450.0,  # Fast charge
              projectileCount: 0,
              spreadAngle: 0.0,
              durationOrRadius: 0.0,
              specialData: "charge_attack"
            ),
            BossAttack(
              # Seismic Fissure: signature themed attack - the ground cracks
              # from the boss toward the player and erupts step by step, a
              # marching chain of staggered detonations to outrun sideways.
              attackType: bapMeteor,  # nominal; routed by specialData before attackType dispatch
              damage: 10.5,
              cooldown: 5.0,
              projectileSpeed: 0.0,
              projectileCount: 6,      # eruption steps in the chain
              spreadAngle: 0.0,
              durationOrRadius: 60.0,  # per-step eruption radius
              specialData: "seismic_fissure"
            ),
            BossAttack(
              # Generic fan demoted to occasional filler so charge + fissure lead.
              attackType: bapWave,
              damage: 10.5,
              cooldown: 6.0,
              projectileSpeed: 170.0,
              projectileCount: 4,
              spreadAngle: 80.0,
              durationOrRadius: 0.0
            ),
            BossAttack(
              # Generic targeted demoted to occasional filler.
              attackType: bapTargeted,
              damage: 10.5,
              cooldown: 4.5,
              projectileSpeed: 200.0,
              projectileCount: 3,
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
          defenseMultiplier: 1.1,
          color: Color(r: 255, g: 30, b: 0, a: 255),
          visualEffect: "aura",
          specialBehavior: "enraged_assault",  # Aggressive movement
          attacks: @[
            BossAttack(
              attackType: bapDash,
              damage: 14.0,
              cooldown: 3.0,  # Frequent charges
              projectileSpeed: 520.0,  # Very fast
              projectileCount: 0,
              spreadAngle: 0.0,
              durationOrRadius: 0.0,
              specialData: "double_charge"  # Charges twice
            ),
            BossAttack(
              attackType: bapPulse,
              damage: 14.0,
              cooldown: 4.0,
              projectileSpeed: 190.0,
              projectileCount: 0,
              spreadAngle: 0.0,
              durationOrRadius: 160.0,
              specialData: "ground_slam"  # Rage shockwave
            ),
            BossAttack(
              # Seismic Fissure: longer marching chain that FORKS in bloodrage -
              # spreadAngle > 0 splits the crack into a V after two shared steps,
              # so dodging sideways off one branch walks toward the other.
              attackType: bapMeteor,  # nominal; routed by specialData
              damage: 14.0,
              cooldown: 4.5,
              projectileSpeed: 0.0,
              projectileCount: 8,
              spreadAngle: 50.0,       # full fork angle between the two branches
              durationOrRadius: 62.0,
              specialData: "seismic_fissure"
            ),
            BossAttack(
              # Generic ring demoted to occasional filler.
              attackType: bapCircle,
              damage: 14.0,
              cooldown: 5.5,
              projectileSpeed: 160.0,
              projectileCount: 12,  # Rage burst
              spreadAngle: 360.0,
              durationOrRadius: 0.0
            ),
            BossAttack(
              # Generic fan demoted to occasional filler.
              attackType: bapWave,
              damage: 14.0,
              cooldown: 5.5,
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
          damageMultiplier: 1.5,
          defenseMultiplier: 0.9,
          color: Color(r: 255, g: 0, b: 0, a: 255),
          visualEffect: "glow",
          specialBehavior: "berserk_rampage",  # Maximum aggression
          attacks: @[
            BossAttack(
              attackType: bapDash,
              damage: 14.0,
              cooldown: 2.0,  # Constant charging
              projectileSpeed: 600.0,
              projectileCount: 0,
              spreadAngle: 0.0,
              durationOrRadius: 0.0,
              specialData: "rage_charge"  # Triple charge combo
            ),
            BossAttack(
              attackType: bapPulse,
              damage: 14.0,
              cooldown: 3.0,
              projectileSpeed: 220.0,
              projectileCount: 0,
              spreadAngle: 0.0,
              durationOrRadius: 190.0,
              specialData: "earthquake"  # Massive slam
            ),
            BossAttack(
              attackType: bapBarrage,
              damage: 14.0,
              cooldown: 3.5,
              projectileSpeed: 210.0,
              projectileCount: 28,  # Rage explosion
              spreadAngle: 360.0,
              durationOrRadius: 0.0,
              specialData: "blood_burst"
            ),
            BossAttack(
              # Seismic Fissure finale: cast ONCE, then a crack head pursues the
              # player for the rest of the fight (just under base move speed),
              # dropping telegraphed eruptions beneath itself. Re-casts while
              # the chaser lives are no-ops, so the cooldown only matters until
              # the first successful cast.
              attackType: bapMeteor,  # nominal; routed by specialData
              damage: 14.0,
              cooldown: 4.5,
              projectileSpeed: 0.0,
              projectileCount: 0,      # unused by the chase variant
              spreadAngle: 0.0,
              durationOrRadius: 62.0,  # eruption radius the chaser drops
              specialData: "seismic_fissure_chase"
            ),
            BossAttack(
              # Generic ring demoted to occasional filler.
              attackType: bapCircle,
              damage: 14.0,
              cooldown: 5.0,
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
      name: t(tkBoss9Name),
      bossID: 9,
      baseHP: 1900.0,
      baseSpeed: 55.0,
      baseDamage: 4,
      baseRadius: 56.0,
      color: Color(r: 255, g: 200, b: 255, a: 255),
      description: t(tkBoss9Desc),
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
              damage: 13.0,
              cooldown: 4.5,
              projectileSpeed: 0.0,
              projectileCount: 3,  # Leaves floor for the cascade
              spreadAngle: 120.0,
              durationOrRadius: 1.8,
              specialData: "splitting_laser"  # Lasers that refract
            ),
            BossAttack(
              attackType: bapWave,
              damage: 13.0,
              cooldown: 4.5,
              projectileSpeed: 160.0,
              projectileCount: 5,  # Rainbow wave
              spreadAngle: 50.0,
              durationOrRadius: 0.0,
              specialData: "rainbow_wave"
            ),
            BossAttack(
              # Prism Refraction: signature refraction CASCADE - a feed beam
              # charges a focal prism near the player; its finite ray star
              # then re-splits through mini prisms at the ray ends one beat
              # later. The spent focus is the shelter.
              attackType: bapLaser,  # nominal; routed by specialData before attackType dispatch
              damage: 13.0,
              cooldown: 9.0,
              projectileSpeed: 0.0,
              projectileCount: 5,    # rays in the primary star (= mini prisms)
              spreadAngle: 0.0,
              durationOrRadius: 0.0,
              specialData: "prism_refraction"
            )
          ]
        ),
        BossPhaseDefinition(
          name: "Spectrum Array",
          hpThreshold: 0.6,
          speedMultiplier: 1.1,
          damageMultiplier: 1.2,
          defenseMultiplier: 1.15,
          color: Color(r: 200, g: 150, b: 255, a: 255),
          visualEffect: "aura",
          specialBehavior: "prism_array",  # Figure-8 patterns
          attacks: @[
            BossAttack(
              attackType: bapLaser,
              damage: 16.5,
              cooldown: 4.5,
              projectileSpeed: 0.0,
              projectileCount: 5,  # Cross ring (was a 6-beam hexagon; more open floor)
              spreadAngle: 60.0,
              durationOrRadius: 2.0,
              specialData: "hexagonal_prism"  # Even radial split
            ),
            BossAttack(
              attackType: bapBarrage,
              damage: 16.5,
              cooldown: 6.5,
              projectileSpeed: 160.0,
              projectileCount: 18,  # Rainbow burst
              spreadAngle: 360.0,
              durationOrRadius: 0.0,
              specialData: "chromatic_burst"
            ),
            BossAttack(
              # Prism Refraction cascade: a wider star, more mini prisms.
              attackType: bapLaser,  # nominal; routed by specialData
              damage: 16.5,
              cooldown: 8.5,
              projectileSpeed: 0.0,
              projectileCount: 6,
              spreadAngle: 0.0,
              durationOrRadius: 0.0,
              specialData: "prism_refraction"
            )
          ]
        ),
        BossPhaseDefinition(
          name: "Pure Brilliance",
          hpThreshold: 0.33,
          speedMultiplier: 1.15,
          damageMultiplier: 1.3,
          defenseMultiplier: 1.0,
          color: Color(r: 255, g: 255, b: 255, a: 255),
          visualEffect: "glow",
          specialBehavior: "light_cascade",  # Sweeping arc movements
          attacks: @[
            BossAttack(
              # Shorter storm on a long cooldown: it must be a PUNCTUATION
              # between cascades, never a constant floor of lasers under them.
              attackType: bapLaser,
              damage: 19.5,
              cooldown: 6.5,
              projectileSpeed: 0.0,
              projectileCount: 5,  # Prism array (no hidden x2 anymore: 4 real beams)
              spreadAngle: 30.0,
              durationOrRadius: 1.5,
              specialData: "prismatic_storm"  # Splitting lasers
            ),
            BossAttack(
              attackType: bapPulse,
              damage: 16.5,
              cooldown: 7.5,
              projectileSpeed: 270.0,
              projectileCount: 0,
              spreadAngle: 0.0,
              durationOrRadius: 290.0,
              specialData: "blinding_pulse"  # Light explosion
            ),
            BossAttack(
              attackType: bapBarrage,
              damage: 16.5,
              cooldown: 8.0,
              projectileSpeed: 240.0,
              projectileCount: 28,  # Rainbow explosion
              spreadAngle: 360.0,
              durationOrRadius: 0.0,
              specialData: "light_burst"
            ),
            BossAttack(
              # Prism Refraction finale: densest cascade the cap allows
              # (7-ray primary, 6 mini prisms of 5 rays). Long cooldown:
              # the cascade is the phase's SET-PIECE, not its rotation filler.
              attackType: bapLaser,  # nominal; routed by specialData
              damage: 19.5,
              cooldown: 8.0,
              projectileSpeed: 0.0,
              projectileCount: 7,
              spreadAngle: 0.0,
              durationOrRadius: 0.0,
              specialData: "prism_refraction"
            )
          ]
        )
      ]
    )

  of 10:  # Wave 50 - THE TIMEKEEPER
    result = BossDefinition(
      name: t(tkBoss10Name),
      bossID: 10,
      baseHP: 2400.0,
      baseSpeed: 55.0,
      baseDamage: 5,
      baseRadius: 62.0,
      color: Color(r: 0, g: 180, b: 180, a: 255),
      description: t(tkBoss10Desc),
      specialAbilities: @["temporal_echo", "time_rewind", "chrono_break"],
      phases: @[
        BossPhaseDefinition(
          name: "Temporal Echo",
          hpThreshold: 1.0,
          speedMultiplier: 0.7,
          damageMultiplier: 1.0,
          defenseMultiplier: 1.3,
          color: Color(r: 0, g: 180, b: 180, a: 255),
          visualEffect: "pulse",
          specialBehavior: "slow_time",  # Slow methodical movement
          attacks: @[
            BossAttack(
              attackType: bapTeleport,
              damage: 16.0,
              cooldown: 3.5,
              projectileSpeed: 0.0,
              projectileCount: 2,  # Creates 2 temporal echoes
              spreadAngle: 0.0,
              durationOrRadius: 300.0,
              specialData: "time_echo"  # Leaves afterimages that shoot
            ),
            BossAttack(
              attackType: bapWave,
              damage: 16.0,
              cooldown: 2.5,
              projectileSpeed: 150.0,  # Slow time wave
              projectileCount: 9,
              spreadAngle: 55.0,
              durationOrRadius: 0.0,
              specialData: "temporal_wave"
            ),
            BossAttack(
              # Clock Sweep: signature themed attack - clock hands materialize
              # around a frozen pivot and sweep the arena while lethal; the
              # player survives by rotating with the gap between hands.
              # projectileSpeed = sweep speed in degrees/second.
              attackType: bapLaser,  # nominal; routed by specialData before attackType dispatch
              damage: 16.0,
              cooldown: 7.0,          # long: the sweep itself occupies ~4s
              projectileSpeed: 40.0,
              projectileCount: 2,     # hands
              spreadAngle: 0.0,
              durationOrRadius: 0.0,
              specialData: "clock_sweep"
            )
          ]
        ),
        BossPhaseDefinition(
          name: "Time Fracture",
          hpThreshold: 0.6,
          speedMultiplier: 1.2,
          damageMultiplier: 1.1,
          defenseMultiplier: 1.2,
          color: Color(r: 100, g: 220, b: 220, a: 255),  # Brighter cyan
          visualEffect: "aura",
          specialBehavior: "time_distortion",  # Stuttering movement
          attacks: @[
            BossAttack(
              attackType: bapTeleport,
              damage: 19.0,
              cooldown: 4.5,          # each echo fires its own ring - keep them rare
              projectileSpeed: 0.0,
              projectileCount: 3,     # echo count AND bullets per echo (9 total)
              spreadAngle: 0.0,
              durationOrRadius: 350.0,
              specialData: "echo_burst"  # Many afterimages
            ),
            BossAttack(
              # Clock Sweep, escapement mode: a third hand joins and the hands
              # now snap forward in discrete TICKS - cross a hand right after
              # it snaps, before the next jerk. A faint preview line shows
              # where each hand lands next tick.
              attackType: bapLaser,  # nominal; routed by specialData
              damage: 19.0,
              cooldown: 6.0,
              projectileSpeed: 50.0,
              projectileCount: 3,
              spreadAngle: 0.0,
              durationOrRadius: 0.0,
              specialData: "clock_sweep_tick"
            ),
            BossAttack(
              # Generic ring demoted to occasional filler. (The old time spiral
              # was cut outright: ring + spiral + echoes together read as noise.)
              attackType: bapCircle,
              damage: 19.0,
              cooldown: 6.5,
              projectileSpeed: 170.0,
              projectileCount: 14,  # Time ring
              spreadAngle: 360.0,
              durationOrRadius: 0.0,
              specialData: "time_ring"
            ),
            BossAttack(
              attackType: bapPulse,
              damage: 19.0,
              cooldown: 5.5,
              projectileSpeed: 190.0,
              projectileCount: 0,
              spreadAngle: 0.0,
              durationOrRadius: 240.0,
              specialData: "chrono_pulse"  # Time shockwave
            )
          ]
        ),
        BossPhaseDefinition(
          name: "Time Collapse",
          hpThreshold: 0.4,
          speedMultiplier: 1.3,  # Fast blinking
          damageMultiplier: 1.3,
          defenseMultiplier: 0.9,
          color: Color(r: 150, g: 255, b: 255, a: 255),  # Bright cyan/white
          visualEffect: "glow",
          specialBehavior: "time_collapse",  # Fast blinking movement
          attacks: @[
            BossAttack(
              attackType: bapTeleport,
              damage: 22.5,
              cooldown: 5.0,  # each clone fires a ring - was drowning the sweep
              projectileSpeed: 0.0,
              projectileCount: 4,  # clone count AND bullets per clone (16 total)
              spreadAngle: 0.0,
              durationOrRadius: 400.0,
              specialData: "temporal_collapse"  # Reality-breaking teleports
            ),
            BossAttack(
              # Time shatter kept as rare punctuation, not a constant wall.
              attackType: bapBarrage,
              damage: 19.0,
              cooldown: 7.0,
              projectileSpeed: 220.0,
              projectileCount: 24,  # Time explosion
              spreadAngle: 360.0,
              durationOrRadius: 0.0,
              specialData: "time_shatter"
            ),
            BossAttack(
              # Clock Sweep finale: three hands TICK forward in escapement
              # snaps, FREEZE, then rewind in bigger backward snaps, and the
              # cast ends with a 12-ray chime strike. This is the phase's
              # lead attack: shortest cooldown of any clock_sweep cast, and
              # the generic dense ring that used to share this slot was cut.
              attackType: bapLaser,  # nominal; routed by specialData
              damage: 22.5,
              cooldown: 5.5,
              projectileSpeed: 55.0,
              projectileCount: 3,
              spreadAngle: 0.0,
              durationOrRadius: 0.0,
              specialData: "clock_sweep_rewind"
            ),
            BossAttack(
              attackType: bapLaser,
              damage: 22.5,
              cooldown: 7.5,
              projectileSpeed: 0.0,
              projectileCount: 4,  # Time beams
              spreadAngle: 90.0,
              durationOrRadius: 4.0,
              specialData: "temporal_beam"
            ),
            BossAttack(
              attackType: bapPulse,
              damage: 19.0,
              cooldown: 7.5,
              projectileSpeed: 220.0,
              projectileCount: 0,
              spreadAngle: 0.0,
              durationOrRadius: 270.0,
              specialData: "chrono_break"  # Massive time pulse
            )
          ]
        )
      ]
    )

  of 11:  # Wave 55 - THE CHAOS WEAVER
    result = BossDefinition(
      name: t(tkBoss11Name),
      bossID: 11,
      baseHP: 3000.0,
      baseSpeed: 60.0,
      baseDamage: 5,
      baseRadius: 58.0,
      color: Color(r: 180, g: 0, b: 180, a: 255),
      description: t(tkBoss11Desc),
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
              damage: 19.5,  # NERFED from 2.0
              cooldown: 3.5,  # demoted: the chaos weave leads, spray fills gaps
              projectileSpeed: 170.0,  # NERFED from 200.0
              projectileCount: 12,  # NERFED from 15
              spreadAngle: 180.0,
              durationOrRadius: 0.0,
              specialData: "random_spread"
            ),
            BossAttack(
              attackType: bapTeleport,
              damage: 22.0,  # NERFED from 3.0
              cooldown: 4.0,
              projectileSpeed: 0.0,
              projectileCount: 0,
              spreadAngle: 0.0,
              durationOrRadius: 360.0,  # NERFED from 400.0
              specialData: "chaos_blink"
            ),
            BossAttack(
              # Chaos Weave: signature - a needle visibly stitches jagged
              # threads across the arena along a faint pattern line; threads
              # pull taut and snap lethal in stitch order, and crossings tear
              # open into knots (slow bullet rings) as the finale.
              attackType: bapLaser,  # nominal; routed by specialData before attackType dispatch
              damage: 19.5,
              cooldown: 6.0,
              projectileSpeed: 0.0,
              projectileCount: 2,    # threads per weave
              spreadAngle: 0.0,
              durationOrRadius: 0.0,
              specialData: "chaos_weave"
            ),
            BossAttack(
              # Needle Stitch: a dashed seam of silver needles criss-crossing
              # the aim line - the Weaver runs a stitch at the player.
              attackType: bapWave,
              damage: 19.5,
              cooldown: 4.5,
              projectileSpeed: 230.0,
              projectileCount: 7,
              spreadAngle: 0.0,
              durationOrRadius: 0.0,
              specialData: "needle_stitch"
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
              damage: 22.0,  # NERFED from 3.0
              cooldown: 3.0,  # demoted: the chaos weave leads, spray fills gaps
              projectileSpeed: 210.0,  # NERFED from 250.0
              projectileCount: 18,  # NERFED from 24
              spreadAngle: 360.0,
              durationOrRadius: 0.0,
              specialData: "entropy_burst"
            ),
            BossAttack(
              attackType: bapTeleport,
              damage: 22.0,  # NERFED from 4.0
              cooldown: 3.5,
              projectileSpeed: 0.0,
              projectileCount: 2,  # NERFED from 3
              spreadAngle: 0.0,
              durationOrRadius: 400.0,  # NERFED from 450.0
              specialData: "reality_shift"
            ),
            BossAttack(
              # Chaos Weave: a third thread joins the stitch - crossings (and
              # so torn knots) become common.
              attackType: bapLaser,  # nominal; routed by specialData
              damage: 22.0,
              cooldown: 5.5,
              projectileSpeed: 0.0,
              projectileCount: 3,
              spreadAngle: 0.0,
              durationOrRadius: 0.0,
              specialData: "chaos_weave"
            ),
            BossAttack(
              # Unravel: the Weaver's spool spins out - a pinwheel ring that
              # shears into one unwinding spiral thread. Replaced the old
              # chaos_beam laser spam (4-8 random lasers): the Weaver stitches,
              # it doesn't shoot beams.
              attackType: bapCircle,
              damage: 22.0,
              cooldown: 5.0,
              projectileSpeed: 170.0,
              projectileCount: 18,
              spreadAngle: 360.0,
              durationOrRadius: 0.0,
              specialData: "unravel"
            )
          ]
        ),
        BossPhaseDefinition(
          name: "Pure Chaos",
          hpThreshold: 0.35,
          speedMultiplier: 1.175,  # NERFED from 2.0
          damageMultiplier: 1.4,  # NERFED from 2.0
          defenseMultiplier: 0.85,  # NERFED from 0.9
          color: Color(r: 255, g: 100, b: 255, a: 255),
          visualEffect: "glow",
          specialBehavior: "total_chaos",
          attacks: @[
            BossAttack(
              attackType: bapBarrage,
              damage: 22.0,  # NERFED from 4.0
              cooldown: 2.8,  # demoted: the chaos weave leads, spray fills gaps
              projectileSpeed: 250.0,  # NERFED from 300.0
              projectileCount: 30,  # NERFED from 40
              spreadAngle: 360.0,
              durationOrRadius: 0.0,
              specialData: "chaos_storm"
            ),
            BossAttack(
              attackType: bapTeleport,
              damage: 27.5,  # NERFED from 5.0
              cooldown: 2.5,
              projectileSpeed: 0.0,
              projectileCount: 3,  # NERFED from 5
              spreadAngle: 0.0,
              durationOrRadius: 450.0,  # NERFED from 500.0
              specialData: "dimensional_chaos"
            ),
            BossAttack(
              # Chaos Weave finale: four threads - the arena becomes the loom.
              # The staggered stitch + knot tears run ~3.9s, so the cooldown
              # leaves a breather between weaves.
              attackType: bapLaser,  # nominal; routed by specialData
              damage: 25.0,
              cooldown: 6.0,
              projectileSpeed: 0.0,
              projectileCount: 4,
              spreadAngle: 0.0,
              durationOrRadius: 0.0,
              specialData: "chaos_weave"
            ),
            BossAttack(
              attackType: bapPulse,
              damage: 22.0,  # NERFED from 4.0
              cooldown: 4.0,
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
      name: t(tkBoss12Name),
      bossID: 12,
      baseHP: 3500.0,
      baseSpeed: 60.0,  # NERFED from 85.0
      baseDamage: 6,
      baseRadius: 70.0,
      color: Color(r: 255, g: 50, b: 50, a: 255),
      description: t(tkBoss12Desc),
      specialAbilities: @["omni_attack", "adaptive_defense", "final_form"],
      phases: @[
        BossPhaseDefinition(
          name: "Alpha Phase",
          hpThreshold: 1.0,
          speedMultiplier: 0.9,  # NERFED from 1.0
          damageMultiplier: 0.9,  # NERFED from 1.0
          defenseMultiplier: 1.3,  # NERFED from 1.5
          color: Color(r: 255, g: 50, b: 50, a: 255),
          visualEffect: "shield",
          specialBehavior: "balanced_assault",
          attacks: @[
            BossAttack(
              attackType: bapSpiral,
              damage: 26.5,  # NERFED from 3.0
              cooldown: 3.0,  # NERFED from 2.5
              projectileSpeed: 160.0,  # NERFED from 180.0
              projectileCount: 10,  # NERFED from 12
              spreadAngle: 30.0,
              durationOrRadius: 0.0
            ),
            BossAttack(
              attackType: bapOrbit,
              damage: 21.0,
              cooldown: 1.5,
              projectileSpeed: 100.0,
              projectileCount: 5,  # NERFED from 6
              spreadAngle: 60.0,
              durationOrRadius: 220.0  # NERFED from 250.0
            ),
            BossAttack(
              attackType: bapLaser,
              damage: 32.0,  # NERFED from 4.0
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
              damage: 29.0,  # NERFED from 4.0
              cooldown: 3.5,  # NERFED from 3.0
              projectileSpeed: 320.0,  # NERFED from 350.0
              projectileCount: 5,  # NERFED from 6
              spreadAngle: 0.0,
              durationOrRadius: 100.0  # NERFED from 120.0
            ),
            BossAttack(
              attackType: bapChain,
              damage: 26.5,  # NERFED from 4.0
              cooldown: 4.0,  # NERFED from 3.5
              projectileSpeed: 0.0,
              projectileCount: 5,  # NERFED from 6
              spreadAngle: 0.0,
              durationOrRadius: 360.0  # NERFED from 400.0
            ),
            BossAttack(
              # Generic spray demoted to occasional filler.
              attackType: bapBarrage,
              damage: 29.0,  # NERFED from 3.0
              cooldown: 4.0,
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
              damage: 29.0,  # NERFED from 5.0
              cooldown: 3.0,  # NERFED from 2.5
              projectileSpeed: 0.0,
              projectileCount: 3,  # NERFED from 4
              spreadAngle: 0.0,
              durationOrRadius: 360.0  # NERFED from 400.0
            ),
            BossAttack(
              attackType: bapDash,
              damage: 29.0,  # NERFED from 5.0
              cooldown: 3.5,  # NERFED from 3.0
              projectileSpeed: 550.0,  # NERFED from 650.0
              projectileCount: 0,
              spreadAngle: 0.0,
              durationOrRadius: 0.0
            ),
            BossAttack(
              attackType: bapPulse,
              damage: 29.0,  # NERFED from 4.0
              cooldown: 4.5,  # NERFED from 4.0
              projectileSpeed: 240.0,  # NERFED from 280.0
              projectileCount: 0,
              spreadAngle: 0.0,
              durationOrRadius: 260.0  # NERFED from 300.0
            ),
            BossAttack(
              # Generic ring demoted to occasional filler.
              attackType: bapCircle,
              damage: 29.0,  # NERFED from 3.0
              cooldown: 5.0,
              projectileSpeed: 170.0,  # NERFED from 200.0
              projectileCount: 26,  # NERFED from 32
              spreadAngle: 360.0,
              durationOrRadius: 0.0
            )
          ]
        ),
        BossPhaseDefinition(
          name: "Omega Phase",
          hpThreshold: 0.2,
          speedMultiplier: 1.2,
          damageMultiplier: 1.5,
          defenseMultiplier: 2.5,
          color: Color(r: 255, g: 0, b: 255, a: 255),
          visualEffect: "glow",
          specialBehavior: "final_form",
          attacks: @[
            BossAttack(
              # OMEGA JUDGEMENT: signature mega finale. The boss freezes into a
              # hardened channel (mega-cast, like the Laser Architect's ricochet
              # beam) and detonates three of the four screen quadrants in a
              # shuffled sequence, sparing only the quadrant the player was in
              # when the cast began - read the order, hop the safe pocket.
              attackType: bapMeteor,  # nominal; routed by specialData before attackType dispatch
              damage: 34.0,   # huge: fully telegraphed, one hit max per quadrant
              cooldown: 16.0,
              projectileSpeed: 0.0,
              projectileCount: 0,
              spreadAngle: 0.0,
              durationOrRadius: 0.0,
              specialData: "omega_judgement"
            ),
            BossAttack(
              attackType: bapBarrage,
              damage: 32.0,  # NERFED from 5.0
              cooldown: 1.8,  # NERFED from 0.8 -> 1.2 -> 1.8 (space rings so they don't form a gapless wall)
              projectileSpeed: 270.0,  # NERFED from 320.0
              projectileCount: 30,  # NERFED from 60 (also no longer doubled at runtime in game.nim)
              spreadAngle: 360.0,
              durationOrRadius: 0.0,
              specialData: "omega_barrage"
            ),
            BossAttack(
              attackType: bapLaser,
              damage: 37.0,  # NERFED from 6.0
              cooldown: 3.0,  # NERFED from 2.5
              projectileSpeed: 0.0,
              projectileCount: 4,  # NERFED from 5
              spreadAngle: 45.0,
              durationOrRadius: 4.0,  # NERFED from 5.0
              specialData: "omega_beam"
            ),
            BossAttack(
              attackType: bapTeleport,
              damage: 32.0,  # NERFED from 6.0
              cooldown: 3.2,  # NERFED from 1.8 -> 2.5 -> 3.2 (fewer overlapping blink-bursts during the barrage)
              projectileSpeed: 0.0,
              projectileCount: 4,  # NERFED from 6
              spreadAngle: 0.0,
              durationOrRadius: 450.0,  # NERFED from 500.0
              specialData: "omega_blink"
            ),
            BossAttack(
              attackType: bapPulse,
              damage: 32.0,  # NERFED from 5.0
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

  result.weakPoint = bossWeakPointDefinitionFor(result.bossID)

# Helper Functions

proc isBossWave*(waveNumber: int): bool =
  ## Checks if the current wave should spawn a custom boss (every 5 waves, no limit)
  waveNumber mod 5 == 0

proc getCustomBossNumber*(waveNumber: int): int =
  ## Returns the custom boss number (1-12) for the given wave
  ## After wave 60, continues with boss 12
  if waveNumber <= 0 or waveNumber mod 5 != 0:
    return 0

  let bossNumber = waveNumber div 5
  if bossNumber > 12:
    return 12  # Boss 12 continues indefinitely with scaled stats

  return bossNumber

proc getBossForWave*(waveNumber: int): BossDefinition =
  ## Gets the appropriate boss definition for a wave number
  ## After wave 60, uses boss 12 with stats scaled per wave
  if not isBossWave(waveNumber):
    # Not a boss wave, return empty definition
    return BossDefinition()

  let bossNumber = getCustomBossNumber(waveNumber)
  return getBossDefinition(bossNumber)

proc getBossPhaseHpPools*(boss: BossDefinition, scaledHp: float32): seq[float32] =
  ## Splits total boss HP into one pool per phase using the existing threshold gaps.
  if scaledHp <= 0.0'f32 or boss.phases.len == 0:
    return @[max(scaledHp, 0.01'f32)]

  var weights: seq[float32] = @[]
  var totalWeight = 0.0'f32
  for i, phase in boss.phases:
    let nextThreshold =
      if i + 1 < boss.phases.len:
        boss.phases[i + 1].hpThreshold
      else:
        0.0'f32
    let weight = max(0.0'f32, phase.hpThreshold - nextThreshold)
    weights.add(weight)
    totalWeight += weight

  if totalWeight <= 0.0'f32:
    return @[scaledHp]

  for weight in weights:
    result.add(max(0.01'f32, scaledHp * (weight / totalWeight)))

proc getCurrentPhase*(boss: BossDefinition, currentHpPercent: float32): BossPhaseDefinition =
  ## Returns the current phase based on boss HP percentage
  result = boss.phases[0]  # Default to first phase

  for phase in boss.phases:
    if currentHpPercent <= phase.hpThreshold:
      result = phase
    else:
      break

# Boss Stats Scaling

proc bossTierSteps(waveNumber: int): float32 =
  ## Boss progression in tiers (one per 5 waves past wave 5), not raw wave count.
  max(0.0'f32, (waveNumber.float32 - 5.0) / 5.0)

proc endlessSteps(waveNumber: int): float32 =
  ## Tiers past wave 60 (boss tier 11): 0 for every campaign boss, compounds in endless.
  max(0.0'f32, bossTierSteps(waveNumber) - 11.0)

proc getScaledBossHP*(baseBoss: BossDefinition, waveNumber: int): float32 =
  ## Scales boss HP by boss tier, not raw wave count, to avoid extreme midgame cliffs.
  let waveScale = 1.0 + bossTierSteps(waveNumber) * 0.20  # 20% increase per boss tier
  # Endless-only buff. Wave 60 is boss tier 11, so endlessSteps is exactly 0 for
  # every campaign boss (waves 5-60) -> pow(_, 0) = 1.0 leaves them untouched. Past
  # wave 60 it compounds, mirroring the player's exponential offense (shop + power-ups
  # + startWave's per-wave damage growth) so endless bosses stop getting melted.
  baseBoss.baseHP * waveScale * pow(1.08'f32, endlessSteps(waveNumber))

proc getScaledBossSpeed*(baseBoss: BossDefinition, waveNumber: int): float32 =
  ## Scales boss speed more gently so later bosses stay threatening without becoming frantic.
  let waveScale = 1.0 + bossTierSteps(waveNumber) * 0.03
  baseBoss.baseSpeed * waveScale

proc getScaledBossDamage*(baseBoss: BossDefinition, waveNumber: int): float32 =
  ## Scales boss damage based on wave number
  let additionalDamage = (waveNumber - 5) div 15  # +1 damage every 15 waves
  # Endless-only buff (see getScaledBossHP): 1.0 for waves 1-60, compounds past 60
  # so endless bosses keep threatening a player stacked with defensive power-ups.
  float32(baseBoss.baseDamage + additionalDamage) * pow(1.05'f32, endlessSteps(waveNumber))
