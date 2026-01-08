## Power-up data module
## Contains shared power-up information (names, descriptions)

import types

proc getPowerUpName*(powerType: PowerUpType): string =
  case powerType
  of puDoubleShot: "Double Shot"
  of puRotatingShield: "Rotating Shield"
  of puDamageZone: "Damage Aura"
  of puMagicalBullets: "Magical Bullets"
  of puPiercingShots: "Piercing Shots"
  of puMultiShot: "Multi-Shot"
  of puExplosiveBullets: "Explosive Rounds"
  of puLifeSteal: "Life Steal"
  of puRapidFire: "Rapid Fire"
  of puMaxHealth: "Vitality"
  of puSpeedBoost: "Agility"
  of puBulletDamage: "Power"
  of puBulletSpeed: "Velocity"
  of puLuckyCoins: "Greed"
  of puWallMaster: "Fortify"
  of puAutoShoot: "Auto-Target"
  of puBulletSize: "Giant Bullets"
  of puRegeneration: "Regeneration"
  of puDodgeChance: "Evasion"
  of puCriticalHit: "Critical Strike"
  of puBloodBullets: "Blood Bullets"
  of puBulletRicochet: "Ricochet"
  of puSlowField: "Slow Field"
  of puRage: "Rage"
  of puBerserker: "Berserker"
  of puThorns: "Thorns"
  of puBulletSplit: "Split Shot"
  of puChainLightning: "Chain Lightning"
  of puFrostShots: "Frost Shots"
  of puPoisonShot: "Poison Shots"
  of puFireBullets: "Fire Bullets"
  of puWindBullets: "Wind Bullets"
  of puFireAura: "Fire Aura"
  of puLightningAura: "Lightning Aura"
  of puPoisonAura: "Poison Aura"
  of puWindAura: "Wind Aura"
  of puTimeWarp: "Chronos"
  of puGravityWell: "Singularity"
  of puPhaseShift: "Phase Walker"
  of puOvercharge: "Momentum"
  of puEchoShots: "Echo Strike"
  of puRotatingOrbs: "Elemental Orbs"
  of puPoisonOrb: "Poison Orbs"
  of puFireOrb: "Fire Orbs"
  of puLightningOrb: "Lightning Orbs"
  of puWindOrb: "Wind Orbs"
  of puFrostOrb: "Frost Orbs"
  of puArcaneBullets: "Arcane Bullets"
  of puArcaneAura: "Arcane Aura"
  of puArcaneOrb: "Arcane Orbs"
  of puFireMastery: "Inferno Mastery"
  of puPoisonMastery: "Toxic Overlord"
  of puFrostMastery: "Frost King"
  of puArcaneMastery: "Arcane Ascension"
  of puLightningMastery: "Storm Lord"
  of puWindMastery: "Wind Master"
  of puParry: "Parry"
  of puBloodOrb: "Blood Orbs"
  of puBloodAura: "Blood Aura"
  of puBloodMastery: "Blood Lord"
  of puRadialBurst: "Radial Burst"
  of puWallTurrets: "Wall Sentinels"

proc getPowerUpDescription*(powerType: PowerUpType, level: int): string =
  case powerType
  of puDoubleShot:
    # Single level only - LEGENDARY
    "Fire 2 bullets per shot (-25% fire rate)"
  of puRotatingShield:
    case level
    of 1: "3 shields (30% coverage, 3 HP, 4s respawn)"
    of 2: "3 shields (35% coverage, 4 HP, 3s respawn)"
    else: "3 shields (40% coverage, 5 HP, 2s respawn)"
  of puDamageZone:
    case level
    of 1: "3 dmg/sec in 120 radius"
    of 2: "6 dmg/sec in 160 radius"
    else: "12 dmg/sec in 200 radius"
  of puMagicalBullets:
    # Single level only - LEGENDARY
    "Bullets track nearest enemy"
  of puPiercingShots:
    case level
    of 1: "Bullets pierce 1 enemy (-33% damage per pierce)"
    of 2: "Bullets pierce 2 enemies (-33% damage per pierce)"
    else: "Bullets pierce 3 enemies (-33% damage per pierce)"
  of puMultiShot:
    # Single level only - 3 directions, no nerfs
    "Shoot in 3 directions"
  of puExplosiveBullets:
    case level
    of 1: "Bullets explode (small radius)"
    of 2: "Bullets explode (medium radius)"
    else: "Bullets explode (large radius)"
  of puLifeSteal:
    case level
    of 1: "Heal 1 HP per 30 kills"
    of 2: "Heal 1 HP per 25 kills"
    else: "Heal 1 HP per 15 kills"
  of puRapidFire:
    # Single level only - LEGENDARY
    "+40% fire rate"
  of puMaxHealth:
    # Single level only - LEGENDARY
    "+14 max HP"
  of puSpeedBoost:
    # Single level only - LEGENDARY
    "+40% movement speed"
  of puBulletDamage:
    # Single level only - LEGENDARY
    "+75% bullet damage"
  of puBulletSpeed:
    # Single level only - LEGENDARY
    "+40% bullet speed"
  of puLuckyCoins:
    # Single level only - LEGENDARY
    "Doubles all coins collected"
  of puWallMaster:
    # Single level only - LEGENDARY
    "Walls have +250% HP turrets have +100% damage"
  of puAutoShoot:
    # Single level only - LEGENDARY
    "Auto-fire at nearest enemy (90% fire rate, 450 range)"
  of puBulletSize:
    case level
    of 1: "+50% bullet size"
    of 2: "+100% bullet size"
    else: "+150% bullet size"
  of puRegeneration:
    case level
    of 1: "Regen 1-2 HP per wave"
    of 2: "Regen 2-4 HP per wave"
    else: "Regen 3-6 HP per wave"
  of puDodgeChance:
    case level
    of 1: "15% chance to dodge hits"
    of 2: "20% chance to dodge hits"
    else: "30% chance to dodge hits"
  of puCriticalHit:
    case level
    of 1: "20% chance for 2x damage (all sources)"
    of 2: "35% chance for 2x damage (all sources)"
    else: "50% chance for 2x damage (all sources)"
  of puBloodBullets:
    case level
    of 1: "Heal 1.5% of bullet damage (blood element)"
    of 2: "Heal 2% of bullet damage (blood element)"
    else: "Heal 3% of bullet damage (blood element)"
  of puBulletRicochet:
    case level
    of 1: "Bullets ricochet once (75% damage per ricochet)"
    of 2: "Bullets ricochet twice (75% damage per ricochet)"
    else: "Bullets ricochet 3 times (75% damage per ricochet)"
  of puSlowField:
    case level
    of 1: "Slow enemies 30% in 120 radius"
    of 2: "Slow enemies 45% in 160 radius"
    else: "Slow enemies 55% in 200 radius"
  of puRage:
    case level
    of 1: "+5% dmg per 10% HP lost"
    of 2: "+8% dmg per 10% HP lost"
    else: "+12% dmg per 10% HP lost"
  of puBerserker:
    case level
    of 1: "+5% fire rate per 10% HP lost"
    of 2: "+8% fire rate per 10% HP lost"
    else: "+12% fire rate per 10% HP lost"
  of puThorns:
    case level
    of 1: "Reflect 50% damage to attacker"
    of 2: "Reflect 100% damage to attacker"
    else: "Reflect 200% damage to attacker"
  of puBulletSplit:
    case level
    of 1: "Bullets split into 2 on hit"
    of 2: "Bullets split into 3 on hit"
    else: "Bullets split into 4 on hit"
  of puChainLightning:
    case level
    of 1: "Hit chains to 1 enemy (70% dmg, 120 range, 0.05s stun)"
    of 2: "Hit chains to 2 enemies (85% dmg, 140 range, 0.05s stun)"
    else: "Hit chains to 3 enemies (100% dmg, 160 range, 0.05s stun)"
  of puFrostShots:
    case level
    of 1: "Bullets slow enemies 25% (permanent)"
    of 2: "Bullets slow enemies 40% (permanent)"
    else: "Bullets slow enemies 60% (permanent)"
  of puPoisonShot:
    case level
    of 1: "Bullets poison (0.5 dmg/s, 4s)"
    of 2: "Bullets poison (1 dmg/s, 5s)"
    else: "Bullets poison (2 dmg/s, 6s)"
  of puFireBullets:
    case level
    of 1: "Bullets burn (0.3 dmg/s, 2s)"
    of 2: "Bullets burn (0.75 dmg/s, 3s)"
    else: "Bullets burn (1.5 dmg/s, 4s)"
  of puWindBullets:
    case level
    of 1: "Bullets knock back enemies (weak push)"
    of 2: "Bullets knock back enemies (medium push)"
    else: "Bullets knock back enemies (strong push)"
  of puFireAura:
    case level
    of 1: "Burn enemies 1.5 dmg/s in 120 radius (2s)"
    of 2: "Burn enemies 3 dmg/s in 160 radius (3s)"
    else: "Burn enemies 6 dmg/s in 200 radius (4s)"
  of puLightningAura:
    case level
    of 1: "Zap 0.8 dmg/s in 120 radius (chains 1x)"
    of 2: "Zap 1.6 dmg/s in 160 radius (chains 2x)"
    else: "Zap 3.2 dmg/s in 200 radius (chains 3x)"
  of puPoisonAura:
    case level
    of 1: "Poison 0.6 dmg/s in 120 radius (6s duration)"
    of 2: "Poison 1.2 dmg/s in 160 radius (8s duration)"
    else: "Poison 2.4 dmg/s in 200 radius (10s duration)"
  of puWindAura:
    case level
    of 1: "Push enemies away in 120 radius (weak)"
    of 2: "Push enemies away in 160 radius (medium)"
    else: "Push enemies away in 200 radius (strong)"
  of puTimeWarp:
    # Single level only - LEGENDARY
    "Slow time 50% for 4s (2 uses/wave, 18s cd)"
  of puGravityWell:
    # Single level only - LEGENDARY passive pull
    "Pull enemies in 300 radius"
  of puPhaseShift:
    # Single level only - LEGENDARY teleport
    "Dash forward (5s cd, 0.5s invuln, scales with speed)"
  of puOvercharge:
    # Single level only - LEGENDARY
    "+5% dmg per 100 units traveled (max 100%, 80 range)"
  of puEchoShots:
    # Single level only - LEGENDARY echo trail
    "Bullets leave ghost trail (50% dmg)"
  of puRotatingOrbs:
    # Single level only - LEGENDARY power-up with all elements
    "All 6 elemental orbs (2.5 dmg/hit)"
  of puPoisonOrb:
    case level
    of 1: "2 poison orbs (0.3 dmg/s"
    of 2: "4 poison orbs (0.3 dmg/s)"
    else: "6 poison orbs (0.3 dmg/s)"
  of puFireOrb:
    case level
    of 1: "2 fire orbs (0.4 dmg/s)"
    of 2: "4 fire orbs (0.4 dmg/s)"
    else: "6 fire orbs (0.4 dmg/s)"
  of puLightningOrb:
    case level
    of 1: "2 lightning orbs (1.5 dmg/hit)"
    of 2: "4 lightning orbs (2 dmg/hit)"
    else: "6 lightning orbs (2.5 dmg/hit)"
  of puWindOrb:
    case level
    of 1: "2 wind orbs (1 dmg/hit, push)"
    of 2: "4 wind orbs (1.5 dmg/hit, push)"
    else: "6 wind orbs (2 dmg/hit, push)"
  of puFrostOrb:
    case level
    of 1: "2 frost orbs (1 dmg/hit, slow)"
    of 2: "4 frost orbs (1.5 dmg/hit, slow)"
    else: "6 frost orbs (2 dmg/hit, slow)"
  of puArcaneOrb:
    case level
    of 1: "2 arcane orbs (1.5 dmg/hit, arcane)"
    of 2: "4 arcane orbs (2 dmg/hit, arcane)"
    else: "6 arcane orbs (2.5 dmg/hit, arcane)"
  of puArcaneBullets:
    case level
    of 1: "Bullets enhanced with arcane power (+50% bullet damage, arcane)"
    of 2: "Bullets enhanced with arcane power (+100% bullet damage, arcane)"
    else: "Bullets enhanced with arcane power (+150% bullet damage, arcane)"
  of puArcaneAura:
    case level
    of 1: "Arcane aura 2 dmg/s in 120 radius, arcane"
    of 2: "Arcane aura 4 dmg/s in 160 radius, arcane"
    else: "Arcane aura 8 dmg/s in 200 radius, arcane"
  of puFireMastery:
    # Single level only - LEGENDARY mastery
    "Fire effects: +150% dmg, +100% duration, +35% slow"
  of puPoisonMastery:
    # Single level only - LEGENDARY mastery
    "Poison effects: +150% dmg, +100% duration, +30% slow"
  of puFrostMastery:
    # Single level only - LEGENDARY mastery
    "Frost effects: +150% dmg, +100% duration, +20% slow"
  of puArcaneMastery:
    # Single level only - LEGENDARY mastery
    "Arcane effects: +150% dmg, +100% duration, piercing"
  of puLightningMastery:
    # Single level only - LEGENDARY mastery
    "Lightning effects: +150% dmg, +100% duration, +25% slow, +1 chain, +50% range"
  of puWindMastery:
    # Single level only - LEGENDARY mastery
    "Wind effects: +150% dmg, +100% duration, +40% slow, stronger push"
  of puParry:
    # Single level only - LEGENDARY active ability
    "Active: Invincible for 0.5s, bounce enemy bullets (5s cooldown)"
  of puBloodOrb:
    case level
    of 1: "2 blood orbs (1.5 dmg/hit, lifesteal)"
    of 2: "4 blood orbs (2 dmg/hit, lifesteal)"
    else: "6 blood orbs (2.5 dmg/hit, lifesteal)"
  of puBloodAura:
    case level
    of 1: "Blood aura 1.5 dmg/s in 120 radius, heal 2.5% dealt"
    of 2: "Blood aura 3 dmg/s in 160 radius, heal 5% dealt"
    else: "Blood aura 6 dmg/s in 200 radius, heal 10% dealt"
  of puBloodMastery:
    # Single level only - LEGENDARY mastery
    "Blood effects: +150% dmg, +100% duration, +50% lifesteal"
  of puRadialBurst:
    case level
    of 1: "Fire 8 bullets in a circle every 4s"
    of 2: "Fire 10 bullets in a circle every 3s"
    else: "Fire 14 bullets in a circle every 2s"
  of puWallTurrets:
    # Single level only - LEGENDARY
    "Walls shoot enemies (1 dmg, 2s cooldown)"
