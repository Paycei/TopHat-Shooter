## Power-up data module
## Contains shared power-up information (names, descriptions)

import types
import localization

proc getPowerUpName*(powerType: PowerUpType): string =
  case powerType
  of puDoubleShot: t(tkPowerupDoubleShot)
  of puRotatingShield: t(tkPowerupRotatingShield)
  of puDamageZone: t(tkPowerupDamageZone)
  of puMagicalBullets: t(tkPowerupMagicalBullets)
  of puPiercingShots: t(tkPowerupPiercingShots)
  of puMultiShot: t(tkPowerupMultiShot)
  of puExplosiveBullets: t(tkPowerupExplosiveBullets)
  of puLifeSteal: t(tkPowerupLifeSteal)
  of puRapidFire: t(tkPowerupRapidFire)
  of puMaxHealth: t(tkPowerupMaxHealth)
  of puSpeedBoost: t(tkPowerupSpeedBoost)
  of puBulletDamage: t(tkPowerupBulletDamage)
  of puBulletSpeed: t(tkPowerupBulletSpeed)
  of puLuckyCoins: t(tkPowerupLuckyCoins)
  of puWallMaster: t(tkPowerupWallMaster)
  of puAutoShoot: t(tkPowerupAutoShoot)
  of puBulletSize: t(tkPowerupBulletSize)
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

proc getPowerUpDescription*(powerType: PowerUpType, level: int): string =
  case powerType
  of puDoubleShot:
    # Single level only - LEGENDARY
    t(tkPowerupDoubleShotDesc)
  of puRotatingShield:
    case level
    of 1: t(tkPowerupRotatingShieldDesc1)
    of 2: t(tkPowerupRotatingShieldDesc2)
    else: t(tkPowerupRotatingShieldDesc3)
  of puDamageZone:
    case level
    of 1: t(tkPowerupDamageZoneDesc1)
    of 2: t(tkPowerupDamageZoneDesc2)
    else: t(tkPowerupDamageZoneDesc3)
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
  of puBulletDamage:
    # Single level only - LEGENDARY
    t(tkPowerupBulletDamageDesc)
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
  of puBulletSize:
    case level
    of 1: t(tkPowerupBulletSizeDesc1)
    of 2: t(tkPowerupBulletSizeDesc2)
    else: t(tkPowerupBulletSizeDesc3)
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
    of 1: t(tkPowerupPoisonShotDesc1)
    of 2: t(tkPowerupPoisonShotDesc2)
    else: t(tkPowerupPoisonShotDesc3)
  of puFireBullets:
    case level
    of 1: t(tkPowerupFireBulletsDesc1)
    of 2: t(tkPowerupFireBulletsDesc2)
    else: t(tkPowerupFireBulletsDesc3)
  of puWindBullets:
    case level
    of 1: t(tkPowerupWindBulletsDesc1)
    of 2: t(tkPowerupWindBulletsDesc2)
    else: t(tkPowerupWindBulletsDesc3)
  of puFireAura:
    case level
    of 1: t(tkPowerupFireAuraDesc1)
    of 2: t(tkPowerupFireAuraDesc2)
    else: t(tkPowerupFireAuraDesc3)
  of puLightningAura:
    case level
    of 1: t(tkPowerupLightningAuraDesc1)
    of 2: t(tkPowerupLightningAuraDesc2)
    else: t(tkPowerupLightningAuraDesc3)
  of puPoisonAura:
    case level
    of 1: t(tkPowerupPoisonAuraDesc1)
    of 2: t(tkPowerupPoisonAuraDesc2)
    else: t(tkPowerupPoisonAuraDesc3)
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
    # Single level only - LEGENDARY power-up with all elements
    t(tkPowerupRotatingOrbsDesc)
  of puPoisonOrb:
    case level
    of 1: t(tkPowerupPoisonOrbDesc1)
    of 2: t(tkPowerupPoisonOrbDesc2)
    else: t(tkPowerupPoisonOrbDesc3)
  of puFireOrb:
    case level
    of 1: t(tkPowerupFireOrbDesc1)
    of 2: t(tkPowerupFireOrbDesc2)
    else: t(tkPowerupFireOrbDesc3)
  of puLightningOrb:
    case level
    of 1: t(tkPowerupLightningOrbDesc1)
    of 2: t(tkPowerupLightningOrbDesc2)
    else: t(tkPowerupLightningOrbDesc3)
  of puWindOrb:
    case level
    of 1: t(tkPowerupWindOrbDesc1)
    of 2: t(tkPowerupWindOrbDesc2)
    else: t(tkPowerupWindOrbDesc3)
  of puFrostOrb:
    case level
    of 1: t(tkPowerupFrostOrbDesc1)
    of 2: t(tkPowerupFrostOrbDesc2)
    else: t(tkPowerupFrostOrbDesc3)
  of puArcaneOrb:
    case level
    of 1: t(tkPowerupArcaneOrbDesc1)
    of 2: t(tkPowerupArcaneOrbDesc2)
    else: t(tkPowerupArcaneOrbDesc3)
  of puArcaneBullets:
    case level
    of 1: t(tkPowerupArcaneBulletsDesc1)
    of 2: t(tkPowerupArcaneBulletsDesc2)
    else: t(tkPowerupArcaneBulletsDesc3)
  of puArcaneAura:
    case level
    of 1: t(tkPowerupArcaneAuraDesc1)
    of 2: t(tkPowerupArcaneAuraDesc2)
    else: t(tkPowerupArcaneAuraDesc3)
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
    of 1: t(tkPowerupBloodOrbDesc1)
    of 2: t(tkPowerupBloodOrbDesc2)
    else: t(tkPowerupBloodOrbDesc3)
  of puBloodAura:
    case level
    of 1: t(tkPowerupBloodAuraDesc1)
    of 2: t(tkPowerupBloodAuraDesc2)
    else: t(tkPowerupBloodAuraDesc3)
  of puBloodMastery:
    # Single level only - LEGENDARY mastery
    t(tkPowerupBloodMasteryDesc)
  of puRadialBurst:
    case level
    of 1: t(tkPowerupRadialBurstDesc1)
    of 2: t(tkPowerupRadialBurstDesc2)
    else: t(tkPowerupRadialBurstDesc3)
  of puWallTurrets:
    # Single level only - LEGENDARY
    t(tkPowerupWallTurretsDesc)
