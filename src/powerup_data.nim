## Power-up data module
## Contains shared power-up information (names, descriptions)

import types
import localization
import strformat, math

proc getPowerUpName*(powerType: PowerUpType): string =
  case powerType
  of puDoubleShot: t(tkPowerupDoubleShot)
  of puRotatingShield: t(tkPowerupRotatingShield)
  of puMagicalBullets: t(tkPowerupMagicalBullets)
  of puPiercingShots: t(tkPowerupPiercingShots)
  of puMultiShot: t(tkPowerupMultiShot)
  of puExplosiveBullets: t(tkPowerupExplosiveBullets)
  of puLifeSteal: t(tkPowerupLifeSteal)
  of puRapidFire: t(tkPowerupRapidFire)
  of puMaxHealth: t(tkPowerupMaxHealth)
  of puSpeedBoost: t(tkPowerupSpeedBoost)
  of puBulletSpeed: t(tkPowerupBulletSpeed)
  of puLuckyCoins: t(tkPowerupLuckyCoins)
  of puWallMaster: t(tkPowerupWallMaster)
  of puAutoShoot: t(tkPowerupAutoShoot)
  of puRegeneration: t(tkPowerupRegeneration)
  of puDodgeChance: t(tkPowerupDodgeChance)
  of puCriticalHit: t(tkPowerupCriticalHit)
  of puBloodBullets: t(tkPowerupBloodBullets)
  of puBulletRicochet: t(tkPowerupBulletRicochet)
  of puSlowField: t(tkPowerupSlowField)
  of puRage: t(tkPowerupRage)
  of puBerserker: t(tkPowerupBerserker)
  of puThorns: t(tkPowerupThorns)
  of puBulletSplit: t(tkPowerupBulletSplit)
  of puChainLightning: t(tkPowerupChainLightning)
  of puFrostShots: t(tkPowerupFrostShots)
  of puPoisonShot: t(tkPowerupPoisonShot)
  of puFireBullets: t(tkPowerupFireBullets)
  of puWindBullets: t(tkPowerupWindBullets)
  of puFireAura: t(tkPowerupFireAura)
  of puLightningAura: t(tkPowerupLightningAura)
  of puPoisonAura: t(tkPowerupPoisonAura)
  of puWindAura: t(tkPowerupWindAura)
  of puTimeWarp: t(tkPowerupTimeWarp)
  of puGravityWell: t(tkPowerupGravityWell)
  of puPhaseShift: t(tkPowerupPhaseShift)
  of puOvercharge: t(tkPowerupOvercharge)
  of puEchoShots: t(tkPowerupEchoShots)
  of puRotatingOrbs: t(tkPowerupRotatingOrbs)
  of puPoisonOrb: t(tkPowerupPoisonOrb)
  of puFireOrb: t(tkPowerupFireOrb)
  of puLightningOrb: t(tkPowerupLightningOrb)
  of puWindOrb: t(tkPowerupWindOrb)
  of puFrostOrb: t(tkPowerupFrostOrb)
  of puArcaneBullets: t(tkPowerupArcaneBullets)
  of puArcaneAura: t(tkPowerupArcaneAura)
  of puArcaneOrb: t(tkPowerupArcaneOrb)
  of puFireMastery: t(tkPowerupFireMastery)
  of puPoisonMastery: t(tkPowerupPoisonMastery)
  of puFrostMastery: t(tkPowerupFrostMastery)
  of puArcaneMastery: t(tkPowerupArcaneMastery)
  of puLightningMastery: t(tkPowerupLightningMastery)
  of puWindMastery: t(tkPowerupWindMastery)
  of puParry: t(tkPowerupParry)
  of puBloodOrb: t(tkPowerupBloodOrb)
  of puBloodAura: t(tkPowerupBloodAura)
  of puBloodMastery: t(tkPowerupBloodMastery)
  of puRadialBurst: t(tkPowerupRadialBurst)
  of puWallTurrets: t(tkPowerupWallTurrets)
  of puPulseArmor: t(tkPowerupPulseArmor)
  of puHeavyRounds: t(tkPowerupHeavyRounds)
  of puFortified: t(tkPowerupFortified)
  of puSpecialRounds: t(tkPowerupSpecialRounds)
  of puGiantSlayer: t(tkPowerupGiantSlayer)

proc getPowerUpDescription*(powerType: PowerUpType, level: int, playerDamage: float32 = 1.0): string =
  # Helper: format "base + scaled (pct%)" — values are multiplied x100 for display
  proc dmg(base: float32, scalePct: float32, pd: float32): string =
    let baseVal = round(base * 100).int
    let scaledVal = round(pd * scalePct * 100).int
    let pctVal = round(scalePct * 100).int
    fmt"{baseVal} + {scaledVal} ({pctVal}%) dmg"

  proc dmgPs(base: float32, scalePct: float32, pd: float32): string =
    let baseVal = round(base * 100).int
    let scaledVal = round(pd * scalePct * 100).int
    let pctVal = round(scalePct * 100).int
    fmt"{baseVal} + {scaledVal} ({pctVal}%) dmg/s"
  case powerType
  of puDoubleShot:
    # Single level only - LEGENDARY
    t(tkPowerupDoubleShotDesc)
  of puRotatingShield:
    case level
    of 1: t(tkPowerupRotatingShieldDesc1)
    of 2: t(tkPowerupRotatingShieldDesc2)
    else: t(tkPowerupRotatingShieldDesc3)
  of puMagicalBullets:
    # Single level only - LEGENDARY
    t(tkPowerupMagicalBulletsDesc)
  of puPiercingShots:
    case level
    of 1: t(tkPowerupPiercingShotsDesc1)
    of 2: t(tkPowerupPiercingShotsDesc2)
    else: t(tkPowerupPiercingShotsDesc3)
  of puMultiShot:
    # Single level only - 3 directions, no nerfs
    t(tkPowerupMultiShotDesc)
  of puExplosiveBullets:
    case level
    of 1: fmt"Bullets explode (50% bullet dmg, small radius)"
    of 2: fmt"Bullets explode (50% bullet dmg, medium radius)"
    else: fmt"Bullets explode (50% bullet dmg, large radius)"
  of puLifeSteal:
    case level
    of 1: t(tkPowerupLifeStealDesc1)
    of 2: t(tkPowerupLifeStealDesc2)
    else: t(tkPowerupLifeStealDesc3)
  of puRapidFire:
    # Single level only - LEGENDARY
    t(tkPowerupRapidFireDesc)
  of puMaxHealth:
    # Single level only - LEGENDARY
    t(tkPowerupMaxHealthDesc)
  of puSpeedBoost:
    # Single level only - LEGENDARY
    t(tkPowerupSpeedBoostDesc)
  of puBulletSpeed:
    # Single level only - LEGENDARY
    t(tkPowerupBulletSpeedDesc)
  of puLuckyCoins:
    # Single level only - LEGENDARY
    t(tkPowerupLuckyCoinsDesc)
  of puWallMaster:
    # Single level only - LEGENDARY
    t(tkPowerupWallMasterDesc)
  of puAutoShoot:
    # Single level only - LEGENDARY
    t(tkPowerupAutoShootDesc)
  of puRegeneration:
    case level
    of 1: t(tkPowerupRegenerationDesc1)
    of 2: t(tkPowerupRegenerationDesc2)
    else: t(tkPowerupRegenerationDesc3)
  of puDodgeChance:
    case level
    of 1: t(tkPowerupDodgeChanceDesc1)
    of 2: t(tkPowerupDodgeChanceDesc2)
    else: t(tkPowerupDodgeChanceDesc3)
  of puCriticalHit:
    case level
    of 1: t(tkPowerupCriticalHitDesc1)
    of 2: t(tkPowerupCriticalHitDesc2)
    else: t(tkPowerupCriticalHitDesc3)
  of puBloodBullets:
    case level
    of 1: t(tkPowerupBloodBulletsDesc1)
    of 2: t(tkPowerupBloodBulletsDesc2)
    else: t(tkPowerupBloodBulletsDesc3)
  of puBulletRicochet:
    case level
    of 1: t(tkPowerupBulletRicochetDesc1)
    of 2: t(tkPowerupBulletRicochetDesc2)
    else: t(tkPowerupBulletRicochetDesc3)
  of puSlowField:
    case level
    of 1: t(tkPowerupSlowFieldDesc1)
    of 2: t(tkPowerupSlowFieldDesc2)
    else: t(tkPowerupSlowFieldDesc3)
  of puRage:
    case level
    of 1: t(tkPowerupRageDesc1)
    of 2: t(tkPowerupRageDesc2)
    else: t(tkPowerupRageDesc3)
  of puBerserker:
    case level
    of 1: t(tkPowerupBerserkerDesc1)
    of 2: t(tkPowerupBerserkerDesc2)
    else: t(tkPowerupBerserkerDesc3)
  of puThorns:
    case level
    of 1: t(tkPowerupThornsDesc1)
    of 2: t(tkPowerupThornsDesc2)
    else: t(tkPowerupThornsDesc3)
  of puBulletSplit:
    case level
    of 1: t(tkPowerupBulletSplitDesc1)
    of 2: t(tkPowerupBulletSplitDesc2)
    else: t(tkPowerupBulletSplitDesc3)
  of puChainLightning:
    case level
    of 1: "Hit chains to 1 enemy (70% bullet dmg, 120 range, 0.05s stun)"
    of 2: "Hit chains to 2 enemies (85% bullet dmg, 140 range, 0.05s stun)"
    else: "Hit chains to 3 enemies (100% bullet dmg, 160 range, 0.05s stun)"
  of puFrostShots:
    case level
    of 1: t(tkPowerupFrostShotsDesc1)
    of 2: t(tkPowerupFrostShotsDesc2)
    else: t(tkPowerupFrostShotsDesc3)
  of puPoisonShot:
    case level
    of 1: fmt"Bullets poison ({dmgPs(1.0, 0.1, playerDamage)}, 4s)"
    of 2: fmt"Bullets poison ({dmgPs(1.5, 0.1, playerDamage)}, 5s)"
    else: fmt"Bullets poison ({dmgPs(2.0, 0.1, playerDamage)}, 6s)"
  of puFireBullets:
    case level
    of 1: fmt"Bullets burn ({dmgPs(0.5, 0.1, playerDamage)}, 2s)"
    of 2: fmt"Bullets burn ({dmgPs(1.0, 0.1, playerDamage)}, 3s)"
    else: fmt"Bullets burn ({dmgPs(1.5, 0.1, playerDamage)}, 4s)"
  of puWindBullets:
    case level
    of 1: t(tkPowerupWindBulletsDesc1)
    of 2: t(tkPowerupWindBulletsDesc2)
    else: t(tkPowerupWindBulletsDesc3)
  of puFireAura:
    case level
    of 1: fmt"Burn enemies {dmgPs(1.0, 0.2, playerDamage)} in 120 radius (2s)"
    of 2: fmt"Burn enemies {dmgPs(2.0, 0.2, playerDamage)} in 160 radius (3s)"
    else: fmt"Burn enemies {dmgPs(3.0, 0.2, playerDamage)} in 200 radius (4s)"
  of puLightningAura:
    case level
    of 1: fmt"Zap {dmgPs(1.0, 0.2, playerDamage)} in 120 radius (chains 1x)"
    of 2: fmt"Zap {dmgPs(2.0, 0.2, playerDamage)} in 160 radius (chains 2x)"
    else: fmt"Zap {dmgPs(3.0, 0.2, playerDamage)} in 200 radius (chains 3x)"
  of puPoisonAura:
    case level
    of 1: fmt"Poison {dmgPs(0.5, 0.2, playerDamage)} in 120 radius (6s duration)"
    of 2: fmt"Poison {dmgPs(1.0, 0.2, playerDamage)} in 160 radius (8s duration)"
    else: fmt"Poison {dmgPs(2.0, 0.2, playerDamage)} in 200 radius (10s duration)"
  of puWindAura:
    case level
    of 1: t(tkPowerupWindAuraDesc1)
    of 2: t(tkPowerupWindAuraDesc2)
    else: t(tkPowerupWindAuraDesc3)
  of puTimeWarp:
    # Single level only - LEGENDARY
    t(tkPowerupTimeWarpDesc)
  of puGravityWell:
    # Single level only - LEGENDARY passive pull
    t(tkPowerupGravityWellDesc)
  of puPhaseShift:
    # Single level only - LEGENDARY teleport
    t(tkPowerupPhaseShiftDesc)
  of puOvercharge:
    # Single level only - LEGENDARY
    t(tkPowerupOverchargeDesc)
  of puEchoShots:
    # Single level only - LEGENDARY echo trail
    t(tkPowerupEchoShotsDesc)
  of puRotatingOrbs:
    fmt"All 6 elemental orbs ({dmg(1.5, 0.35, playerDamage)}/hit)"
  of puPoisonOrb:
    case level
    of 1: fmt"4 poison orbs ({dmg(4.5, 0.35, playerDamage)}/hit)"
    of 2: fmt"8 poison orbs ({dmg(7.5, 0.35, playerDamage)}/hit)"
    else: fmt"12 poison orbs ({dmg(11.0, 0.35, playerDamage)}/hit)"
  of puFireOrb:
    case level
    of 1: fmt"4 fire orbs ({dmg(4.5, 0.35, playerDamage)}/hit)"
    of 2: fmt"8 fire orbs ({dmg(7.5, 0.35, playerDamage)}/hit)"
    else: fmt"12 fire orbs ({dmg(11.0, 0.35, playerDamage)}/hit)"
  of puLightningOrb:
    case level
    of 1: fmt"4 lightning orbs ({dmg(4.5, 0.35, playerDamage)}/hit)"
    of 2: fmt"8 lightning orbs ({dmg(7.5, 0.35, playerDamage)}/hit)"
    else: fmt"12 lightning orbs ({dmg(11.0, 0.35, playerDamage)}/hit)"
  of puWindOrb:
    case level
    of 1: fmt"4 wind orbs that push enemies ({dmg(4.5, 0.35, playerDamage)}/hit)"
    of 2: fmt"8 wind orbs that push enemies ({dmg(7.5, 0.35, playerDamage)}/hit)"
    else: fmt"12 wind orbs that push enemies ({dmg(11.0, 0.35, playerDamage)}/hit)"
  of puFrostOrb:
    case level
    of 1: fmt"4 frost orbs that slow enemies ({dmg(4.5, 0.35, playerDamage)}/hit)"
    of 2: fmt"8 frost orbs that slow enemies ({dmg(7.5, 0.35, playerDamage)}/hit)"
    else: fmt"12 frost orbs that slow enemies ({dmg(11.0, 0.35, playerDamage)}/hit)"
  of puArcaneOrb:
    case level
    of 1: fmt"4 arcane orbs ({dmg(4.5, 0.35, playerDamage)}/hit)"
    of 2: fmt"8 arcane orbs ({dmg(7.5, 0.35, playerDamage)}/hit)"
    else: fmt"12 arcane orbs ({dmg(11.0, 0.35, playerDamage)}/hit)"
  of puArcaneBullets:
    case level
    of 1: t(tkPowerupArcaneBulletsDesc1)
    of 2: t(tkPowerupArcaneBulletsDesc2)
    else: t(tkPowerupArcaneBulletsDesc3)
  of puArcaneAura:
    case level
    of 1: fmt"Arcane aura {dmgPs(1.0, 0.2, playerDamage)} in 120 radius, arcane"
    of 2: fmt"Arcane aura {dmgPs(3.0, 0.2, playerDamage)} in 160 radius, arcane"
    else: fmt"Arcane aura {dmgPs(5.0, 0.2, playerDamage)} in 200 radius, arcane"
  of puFireMastery:
    # Single level only - LEGENDARY mastery
    t(tkPowerupFireMasteryDesc)
  of puPoisonMastery:
    # Single level only - LEGENDARY mastery
    t(tkPowerupPoisonMasteryDesc)
  of puFrostMastery:
    # Single level only - LEGENDARY mastery
    t(tkPowerupFrostMasteryDesc)
  of puArcaneMastery:
    # Single level only - LEGENDARY mastery
    t(tkPowerupArcaneMasteryDesc)
  of puLightningMastery:
    # Single level only - LEGENDARY mastery
    t(tkPowerupLightningMasteryDesc)
  of puWindMastery:
    # Single level only - LEGENDARY mastery
    t(tkPowerupWindMasteryDesc)
  of puParry:
    # Single level only - LEGENDARY active ability
    t(tkPowerupParryDesc)
  of puBloodOrb:
    case level
    of 1: fmt"4 blood orbs ({dmg(4.5, 0.35, playerDamage)}/hit, 1.75% lifesteal)"
    of 2: fmt"8 blood orbs ({dmg(7.5, 0.35, playerDamage)}/hit, 2.25% lifesteal)"
    else: fmt"12 blood orbs ({dmg(11.0, 0.35, playerDamage)}/hit, 3% lifesteal)"
  of puBloodAura:
    case level
    of 1: fmt"Blood aura {dmgPs(0.5, 0.2, playerDamage)} in 120 radius, heal 2.5% dealt"
    of 2: fmt"Blood aura {dmgPs(2.0, 0.2, playerDamage)} in 160 radius, heal 5% dealt"
    else: fmt"Blood aura {dmgPs(3.0, 0.2, playerDamage)} in 200 radius, heal 10% dealt"
  of puBloodMastery:
    # Single level only - LEGENDARY mastery
    t(tkPowerupBloodMasteryDesc)
  of puRadialBurst:
    case level
    of 1: "Fire 8 bullets in a circle every 3.5s (uses player damage)"
    of 2: "Fire 10 bullets in a circle every 3.0s (uses player damage)"
    else: "Fire 14 bullets in a circle every 2.0s (uses player damage)"
  of puWallTurrets:
    let s = round(playerDamage * 0.15 * 100).int
    fmt"Walls shoot enemies (100 + {s} (15%) dmg, 1.5s cooldown)"
  of puPulseArmor:
    let hpStr = fmt"+ 1% maxHP"
    case level
    of 1: fmt"Taking damage pushes nearby enemies back (no dmg, {hpStr} scaling)"
    of 2: fmt"Shockwave pushes further, deals 200 {hpStr} dmg"
    else: fmt"Shockwave pushes even further, deals 400 {hpStr} dmg"
  of puHeavyRounds:
    case level
    of 1: t(tkPowerupHeavyRoundsDesc1)
    of 2: t(tkPowerupHeavyRoundsDesc2)
    else: t(tkPowerupHeavyRoundsDesc3)
  of puFortified:
    case level
    of 1: t(tkPowerupFortifiedDesc1)
    of 2: t(tkPowerupFortifiedDesc2)
    else: t(tkPowerupFortifiedDesc3)
  of puSpecialRounds:
    case level
    of 1: t(tkPowerupSpecialRoundsDesc1)
    of 2: t(tkPowerupSpecialRoundsDesc2)
    else: t(tkPowerupSpecialRoundsDesc3)
  of puGiantSlayer:
    case level
    of 1: t(tkPowerupGiantSlayerDesc1)
    of 2: t(tkPowerupGiantSlayerDesc2)
    else: t(tkPowerupGiantSlayerDesc3)
