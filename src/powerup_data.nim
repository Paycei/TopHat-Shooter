## Power-up data module
## Contains shared power-up information (names, descriptions)

import types
import localization
import strformat, math, strutils

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
    # Single level only - LEGENDARY
    t(tkPowerupMultiShotDesc)
  of puExplosiveBullets:
    case level
    of 1: t(tkPowerupExplosiveBulletsDesc1)
    of 2: t(tkPowerupExplosiveBulletsDesc2)
    else: t(tkPowerupExplosiveBulletsDesc3)
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
    of 1: t(tkPowerupChainLightningDesc1)
    of 2: t(tkPowerupChainLightningDesc2)
    else: t(tkPowerupChainLightningDesc3)
  of puFrostShots:
    case level
    of 1: t(tkPowerupFrostShotsDesc1)
    of 2: t(tkPowerupFrostShotsDesc2)
    else: t(tkPowerupFrostShotsDesc3)
  of puPoisonShot:
    case level
    of 1: t(tkPowerupPoisonShotDesc1).replace("{0}", dmgPs(1.0, 0.2, playerDamage))
    of 2: t(tkPowerupPoisonShotDesc2).replace("{0}", dmgPs(1.5, 0.2, playerDamage))
    else: t(tkPowerupPoisonShotDesc3).replace("{0}", dmgPs(2.0, 0.2, playerDamage))
  of puFireBullets:
    case level
    of 1: t(tkPowerupFireBulletsDesc1).replace("{0}", dmgPs(0.5, 0.2, playerDamage))
    of 2: t(tkPowerupFireBulletsDesc2).replace("{0}", dmgPs(1.0, 0.2, playerDamage))
    else: t(tkPowerupFireBulletsDesc3).replace("{0}", dmgPs(1.5, 0.2, playerDamage))
  of puWindBullets:
    case level
    of 1: t(tkPowerupWindBulletsDesc1)
    of 2: t(tkPowerupWindBulletsDesc2)
    else: t(tkPowerupWindBulletsDesc3)
  of puFireAura:
    case level
    of 1: t(tkPowerupFireAuraDesc1).replace("{0}", dmgPs(1.0, 0.3, playerDamage))
    of 2: t(tkPowerupFireAuraDesc2).replace("{0}", dmgPs(2.5, 0.3, playerDamage))
    else: t(tkPowerupFireAuraDesc3).replace("{0}", dmgPs(5.0, 0.3, playerDamage))
  of puLightningAura:
    case level
    of 1: t(tkPowerupLightningAuraDesc1).replace("{0}", dmgPs(1.0, 0.3, playerDamage))
    of 2: t(tkPowerupLightningAuraDesc2).replace("{0}", dmgPs(2.5, 0.3, playerDamage))
    else: t(tkPowerupLightningAuraDesc3).replace("{0}", dmgPs(5.0, 0.3, playerDamage))
  of puPoisonAura:
    case level
    of 1: t(tkPowerupPoisonAuraDesc1).replace("{0}", dmgPs(1.0, 0.3, playerDamage))
    of 2: t(tkPowerupPoisonAuraDesc2).replace("{0}", dmgPs(2.5, 0.3, playerDamage))
    else: t(tkPowerupPoisonAuraDesc3).replace("{0}", dmgPs(5.0, 0.3, playerDamage))
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
    t(tkPowerupRotatingOrbsDesc).replace("{0}", dmg(1.5, 0.3, playerDamage))
  of puPoisonOrb:
    case level
    of 1: t(tkPowerupPoisonOrbDesc1).replace("{0}", dmg(4.5, 0.35, playerDamage))
    of 2: t(tkPowerupPoisonOrbDesc2).replace("{0}", dmg(7.5, 0.35, playerDamage))
    else: t(tkPowerupPoisonOrbDesc3).replace("{0}", dmg(11.0, 0.35, playerDamage))
  of puFireOrb:
    case level
    of 1: t(tkPowerupFireOrbDesc1).replace("{0}", dmg(4.5, 0.35, playerDamage))
    of 2: t(tkPowerupFireOrbDesc2).replace("{0}", dmg(7.5, 0.35, playerDamage))
    else: t(tkPowerupFireOrbDesc3).replace("{0}", dmg(11.0, 0.35, playerDamage))
  of puLightningOrb:
    case level
    of 1: t(tkPowerupLightningOrbDesc1).replace("{0}", dmg(4.5, 0.35, playerDamage))
    of 2: t(tkPowerupLightningOrbDesc2).replace("{0}", dmg(7.5, 0.35, playerDamage))
    else: t(tkPowerupLightningOrbDesc3).replace("{0}", dmg(11.0, 0.35, playerDamage))
  of puWindOrb:
    case level
    of 1: t(tkPowerupWindOrbDesc1).replace("{0}", dmg(4.5, 0.35, playerDamage))
    of 2: t(tkPowerupWindOrbDesc2).replace("{0}", dmg(7.5, 0.35, playerDamage))
    else: t(tkPowerupWindOrbDesc3).replace("{0}", dmg(11.0, 0.35, playerDamage))
  of puFrostOrb:
    case level
    of 1: t(tkPowerupFrostOrbDesc1).replace("{0}", dmg(4.5, 0.35, playerDamage))
    of 2: t(tkPowerupFrostOrbDesc2).replace("{0}", dmg(7.5, 0.35, playerDamage))
    else: t(tkPowerupFrostOrbDesc3).replace("{0}", dmg(11.0, 0.35, playerDamage))
  of puArcaneOrb:
    case level
    of 1: t(tkPowerupArcaneOrbDesc1).replace("{0}", dmg(4.5, 0.35, playerDamage))
    of 2: t(tkPowerupArcaneOrbDesc2).replace("{0}", dmg(7.5, 0.35, playerDamage))
    else: t(tkPowerupArcaneOrbDesc3).replace("{0}", dmg(11.0, 0.35, playerDamage))
  of puArcaneBullets:
    case level
    of 1: t(tkPowerupArcaneBulletsDesc1)
    of 2: t(tkPowerupArcaneBulletsDesc2)
    else: t(tkPowerupArcaneBulletsDesc3)
  of puArcaneAura:
    case level
    of 1: t(tkPowerupArcaneAuraDesc1).replace("{0}", dmgPs(3.5, 0.3, playerDamage))
    of 2: t(tkPowerupArcaneAuraDesc2).replace("{0}", dmgPs(7.5, 0.3, playerDamage))
    else: t(tkPowerupArcaneAuraDesc3).replace("{0}", dmgPs(10.0, 0.3, playerDamage))
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
    of 1: t(tkPowerupBloodOrbDesc1).replace("{0}", dmg(4.5, 0.35, playerDamage))
    of 2: t(tkPowerupBloodOrbDesc2).replace("{0}", dmg(7.5, 0.35, playerDamage))
    else: t(tkPowerupBloodOrbDesc3).replace("{0}", dmg(11.0, 0.35, playerDamage))
  of puBloodAura:
    case level
    of 1: t(tkPowerupBloodAuraDesc1).replace("{0}", dmgPs(1.0, 0.3, playerDamage))
    of 2: t(tkPowerupBloodAuraDesc2).replace("{0}", dmgPs(2.5, 0.3, playerDamage))
    else: t(tkPowerupBloodAuraDesc3).replace("{0}", dmgPs(5.0, 0.3, playerDamage))
  of puBloodMastery:
    # Single level only - LEGENDARY mastery
    t(tkPowerupBloodMasteryDesc)
  of puRadialBurst:
    case level
    of 1: t(tkPowerupRadialBurstDesc1)
    of 2: t(tkPowerupRadialBurstDesc2)
    else: t(tkPowerupRadialBurstDesc3)
  of puWallTurrets:
    let s = round(playerDamage * 0.3 * 100).int
    t(tkPowerupWallTurretsDesc).replace("{0}", $s)
  of puPulseArmor:
    case level
    of 1: t(tkPowerupPulseArmorDesc1)
    of 2: t(tkPowerupPulseArmorDesc2)
    else: t(tkPowerupPulseArmorDesc3)
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
