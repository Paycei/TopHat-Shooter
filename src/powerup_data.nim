## powerup_data.nim
## Single source of truth for all power-up static metadata, names, and descriptions.
##
## Adding a new power-up:
##   1. Add it to `PowerUpType` in types.nim
##   2. Add exactly ONE entry to `allPowerUpDefs` below.
##      Pool membership, exclusivity group, family, colour, panel visibility,
##      and max level all derive automatically from that one entry.
##   3. Add the name to `getPowerUpName`.
##   4. Add the description cases to `getPowerUpDescription`.
##   5. Add the localization keys and entries for the name and description in both english and spanish in localization.nim.

import raylib, strformat, math, strutils
import types, localization

# Registry types

type
  PowerUpPool* = enum
    ## Selection pool a power-up belongs to.
    puppNormal,     ## Offered after wave clears (multi-level, max 3)
    puppLegendary   ## Offered after boss defeats  (single-level, max 1)

  PowerUpGroup* = enum
    ## Mutual-exclusion group enforced when building 3-choice offerings.
    ## At most one member from each group appears in any single set.
    pugNone,
    pugOrb,
    pugAura,
    pugBullet,
    pugMastery

  PowerUpDef* = object
    pool*:             PowerUpPool
    family*:           RoguelitePowerFamily
    group*:            PowerUpGroup
    maxLevel*:         int
    color*:            Color
    inLegendaryPanel*: bool          ## Shows in the legendary active-ability HUD panel
    isElementalOrb*:   bool          ## True for the 7 single-element orbs (NOT puRotatingOrbs)
    allowedModes*:     set[GameMode] ## Empty = all modes; non-empty = restricted to listed modes

# The registry: one entry per PowerUpType, named-index syntax keeps it safe

const allPowerUpDefs*: array[PowerUpType, PowerUpDef] = [
  puAftershock:       PowerUpDef(pool: puppLegendary, family: rpfWind,      group: pugNone,    maxLevel: 1, color: Color(r:255,g:160,b: 60,a:255), inLegendaryPanel: true,  isElementalOrb: false),
  puArcaneAura:       PowerUpDef(pool: puppNormal,    family: rpfArcane,    group: pugAura,    maxLevel: 3, color: Color(r:200,g:100,b:255,a:255), inLegendaryPanel: false, isElementalOrb: false),
  puArcaneBullets:    PowerUpDef(pool: puppNormal,    family: rpfArcane,    group: pugBullet,  maxLevel: 3, color: Color(r:200,g:100,b:255,a:255), inLegendaryPanel: false, isElementalOrb: false),
  puArcaneMastery:    PowerUpDef(pool: puppLegendary, family: rpfArcane,    group: pugMastery, maxLevel: 1, color: Color(r:180,g: 50,b:255,a:255), inLegendaryPanel: false, isElementalOrb: false),
  puArcaneOrb:        PowerUpDef(pool: puppNormal,    family: rpfArcane,    group: pugOrb,     maxLevel: 3, color: Color(r:200,g:100,b:255,a:255), inLegendaryPanel: false, isElementalOrb: true),
  puBerserker:        PowerUpDef(pool: puppNormal,    family: rpfCore,      group: pugNone,    maxLevel: 3, color: Color(r:255,g:100,b: 40,a:255), inLegendaryPanel: false, isElementalOrb: false),
  puBloodAura:        PowerUpDef(pool: puppNormal,    family: rpfBlood,     group: pugAura,    maxLevel: 3, color: Color(r:220,g: 30,b: 30,a:255), inLegendaryPanel: false, isElementalOrb: false),
  puBloodBullets:     PowerUpDef(pool: puppNormal,    family: rpfBlood,     group: pugBullet,  maxLevel: 3, color: Color(r:220,g: 30,b: 30,a:255), inLegendaryPanel: false, isElementalOrb: false),
  puBloodMastery:     PowerUpDef(pool: puppLegendary, family: rpfBlood,     group: pugMastery, maxLevel: 1, color: Color(r:255,g: 20,b: 20,a:255), inLegendaryPanel: false, isElementalOrb: false),
  puBloodOrb:         PowerUpDef(pool: puppNormal,    family: rpfBlood,     group: pugOrb,     maxLevel: 3, color: Color(r:220,g: 30,b: 30,a:255), inLegendaryPanel: false, isElementalOrb: true),
  puBloodPact:        PowerUpDef(pool: puppLegendary, family: rpfBlood,     group: pugNone,    maxLevel: 1, color: Color(r:220,g: 20,b: 20,a:255), inLegendaryPanel: true,  isElementalOrb: false),
  puBountiful:        PowerUpDef(pool: puppLegendary, family: rpfCore,      group: pugNone,    maxLevel: 1, color: Color(r:255,g:200,b: 50,a:255), inLegendaryPanel: false, isElementalOrb: false),
  puBulletRicochet:   PowerUpDef(pool: puppNormal,    family: rpfCore,      group: pugNone,    maxLevel: 3, color: Color(r:140,g:220,b:200,a:255), inLegendaryPanel: false, isElementalOrb: false),
  puBulletSpeed:      PowerUpDef(pool: puppLegendary, family: rpfCore,      group: pugNone,    maxLevel: 1, color: Color(r:200,g:200,b:255,a:255), inLegendaryPanel: false, isElementalOrb: false),
  puBulletSplit:      PowerUpDef(pool: puppNormal,    family: rpfCore,      group: pugNone,    maxLevel: 3, color: Color(r:180,g:140,b:255,a:255), inLegendaryPanel: false, isElementalOrb: false),
  puCelestialVeil:    PowerUpDef(pool: puppLegendary, family: rpfShield,    group: pugNone,    maxLevel: 1, color: Color(r:180,g:200,b:255,a:255), inLegendaryPanel: false, isElementalOrb: false, allowedModes: {gmWaveBased, gmRoguelite}),
  puChainLightning:   PowerUpDef(pool: puppNormal,    family: rpfLightning, group: pugBullet,  maxLevel: 3, color: Color(r:255,g:255,b: 80,a:255), inLegendaryPanel: false, isElementalOrb: false),
  puConduit:          PowerUpDef(pool: puppLegendary, family: rpfLightning, group: pugNone,    maxLevel: 1, color: Color(r:160,g:120,b:255,a:255), inLegendaryPanel: true,  isElementalOrb: false),
  puCriticalHit:      PowerUpDef(pool: puppNormal,    family: rpfCore,      group: pugNone,    maxLevel: 3, color: Color(r:255,g:200,b: 50,a:255), inLegendaryPanel: false, isElementalOrb: false),
  puCurse:            PowerUpDef(pool: puppNormal,    family: rpfCore,      group: pugNone,    maxLevel: 3, color: Color(r:170,g: 60,b:210,a:255), inLegendaryPanel: false, isElementalOrb: false),
  puDodgeChance:      PowerUpDef(pool: puppNormal,    family: rpfCore,      group: pugNone,    maxLevel: 3, color: Color(r:160,g:220,b:255,a:255), inLegendaryPanel: false, isElementalOrb: false),
  puDoubleShot:       PowerUpDef(pool: puppLegendary, family: rpfCore,      group: pugNone,    maxLevel: 1, color: Color(r:100,g:180,b:255,a:255), inLegendaryPanel: false, isElementalOrb: false),
  puEchoShots:        PowerUpDef(pool: puppLegendary, family: rpfArcane,    group: pugNone,    maxLevel: 1, color: Color(r:100,g:200,b:255,a:255), inLegendaryPanel: false, isElementalOrb: false),
  puExplosiveBullets: PowerUpDef(pool: puppNormal,    family: rpfCore,      group: pugNone,    maxLevel: 3, color: Color(r:255,g:120,b: 30,a:255), inLegendaryPanel: false, isElementalOrb: false),
  puFireAura:         PowerUpDef(pool: puppNormal,    family: rpfFire,      group: pugAura,    maxLevel: 3, color: Color(r:255,g:100,b: 20,a:255), inLegendaryPanel: false, isElementalOrb: false),
  puFireBullets:      PowerUpDef(pool: puppNormal,    family: rpfFire,      group: pugBullet,  maxLevel: 3, color: Color(r:255,g:100,b: 20,a:255), inLegendaryPanel: false, isElementalOrb: false),
  puFireMastery:      PowerUpDef(pool: puppLegendary, family: rpfFire,      group: pugMastery, maxLevel: 1, color: Color(r:255,g: 80,b:  0,a:255), inLegendaryPanel: false, isElementalOrb: false),
  puFireOrb:          PowerUpDef(pool: puppNormal,    family: rpfFire,      group: pugOrb,     maxLevel: 3, color: Color(r:255,g:100,b: 20,a:255), inLegendaryPanel: false, isElementalOrb: true),
  puFortified:        PowerUpDef(pool: puppNormal,    family: rpfShield,    group: pugNone,    maxLevel: 3, color: Color(r:180,g:160,b:120,a:255), inLegendaryPanel: false, isElementalOrb: false),
  puFrostMastery:     PowerUpDef(pool: puppLegendary, family: rpfFrost,     group: pugMastery, maxLevel: 1, color: Color(r:100,g:200,b:255,a:255), inLegendaryPanel: false, isElementalOrb: false),
  puFrostOrb:         PowerUpDef(pool: puppNormal,    family: rpfFrost,     group: pugOrb,     maxLevel: 3, color: Color(r:140,g:210,b:255,a:255), inLegendaryPanel: false, isElementalOrb: true),
  puFrostShots:       PowerUpDef(pool: puppNormal,    family: rpfFrost,     group: pugBullet,  maxLevel: 3, color: Color(r:140,g:210,b:255,a:255), inLegendaryPanel: false, isElementalOrb: false),
  puGiantSlayer:      PowerUpDef(pool: puppNormal,    family: rpfCore,      group: pugNone,    maxLevel: 3, color: Color(r:255,g: 80,b: 80,a:255), inLegendaryPanel: false, isElementalOrb: false),
  puGravityWell:      PowerUpDef(pool: puppLegendary, family: rpfArcane,    group: pugNone,    maxLevel: 1, color: Color(r:140,g: 80,b:255,a:255), inLegendaryPanel: false, isElementalOrb: false),
  puHealPower:        PowerUpDef(pool: puppNormal,    family: rpfCore,      group: pugNone,    maxLevel: 3, color: Color(r:255,g:120,b:150,a:255), inLegendaryPanel: false, isElementalOrb: false),
  puHeavyRounds:      PowerUpDef(pool: puppNormal,    family: rpfCore,      group: pugNone,    maxLevel: 3, color: Color(r:160,g:160,b:160,a:255), inLegendaryPanel: false, isElementalOrb: false),
  puLifeSteal:        PowerUpDef(pool: puppNormal,    family: rpfBlood,     group: pugNone,    maxLevel: 3, color: Color(r:220,g: 30,b: 30,a:255), inLegendaryPanel: false, isElementalOrb: false),
  puLightningAura:    PowerUpDef(pool: puppNormal,    family: rpfLightning, group: pugAura,    maxLevel: 3, color: Color(r:255,g:255,b: 80,a:255), inLegendaryPanel: false, isElementalOrb: false),
  puLightningMastery: PowerUpDef(pool: puppLegendary, family: rpfLightning, group: pugMastery, maxLevel: 1, color: Color(r:255,g:255,b:100,a:255), inLegendaryPanel: false, isElementalOrb: false),
  puLightningOrb:     PowerUpDef(pool: puppNormal,    family: rpfLightning, group: pugOrb,     maxLevel: 3, color: Color(r:255,g:255,b: 80,a:255), inLegendaryPanel: false, isElementalOrb: true),
  puLuckyCoins:       PowerUpDef(pool: puppLegendary, family: rpfCore,      group: pugNone,    maxLevel: 1, color: Color(r:255,g:215,b:  0,a:255), inLegendaryPanel: false, isElementalOrb: false),
  puMagicalBullets:   PowerUpDef(pool: puppLegendary, family: rpfCore,      group: pugNone,    maxLevel: 1, color: Color(r:200,g:100,b:255,a:255), inLegendaryPanel: false, isElementalOrb: false),
  puMaxHealth:        PowerUpDef(pool: puppLegendary, family: rpfCore,      group: pugNone,    maxLevel: 1, color: Color(r:255,g: 80,b:120,a:255), inLegendaryPanel: false, isElementalOrb: false),
  puMultiShot:        PowerUpDef(pool: puppLegendary, family: rpfCore,      group: pugNone,    maxLevel: 1, color: Color(r: 80,g:220,b: 80,a:255), inLegendaryPanel: false, isElementalOrb: false),
  puNova:             PowerUpDef(pool: puppLegendary, family: rpfCore,      group: pugNone,    maxLevel: 1, color: Color(r:200,g:230,b:255,a:255), inLegendaryPanel: true,  isElementalOrb: false),
  puOvercharge:       PowerUpDef(pool: puppLegendary, family: rpfArcane,    group: pugNone,    maxLevel: 1, color: Color(r:255,g:230,b: 50,a:255), inLegendaryPanel: false, isElementalOrb: false),
  puParry:            PowerUpDef(pool: puppLegendary, family: rpfCore,      group: pugNone,    maxLevel: 1, color: Color(r:  0,g:220,b:255,a:255), inLegendaryPanel: true,  isElementalOrb: false),
  puPhaseShift:       PowerUpDef(pool: puppLegendary, family: rpfCore,      group: pugNone,    maxLevel: 1, color: Color(r:160,g:220,b:255,a:255), inLegendaryPanel: true,  isElementalOrb: false),
  puPiercingShots:    PowerUpDef(pool: puppNormal,    family: rpfCore,      group: pugNone,    maxLevel: 3, color: Color(r:255,g:220,b: 50,a:255), inLegendaryPanel: false, isElementalOrb: false),
  puPoisonAura:       PowerUpDef(pool: puppNormal,    family: rpfPoison,    group: pugAura,    maxLevel: 3, color: Color(r: 80,g:230,b: 80,a:255), inLegendaryPanel: false, isElementalOrb: false),
  puPoisonMastery:    PowerUpDef(pool: puppLegendary, family: rpfPoison,    group: pugMastery, maxLevel: 1, color: Color(r: 50,g:255,b: 50,a:255), inLegendaryPanel: false, isElementalOrb: false),
  puPoisonOrb:        PowerUpDef(pool: puppNormal,    family: rpfPoison,    group: pugOrb,     maxLevel: 3, color: Color(r: 80,g:230,b: 80,a:255), inLegendaryPanel: false, isElementalOrb: true),
  puPoisonShot:       PowerUpDef(pool: puppNormal,    family: rpfPoison,    group: pugBullet,  maxLevel: 3, color: Color(r: 80,g:230,b: 80,a:255), inLegendaryPanel: false, isElementalOrb: false),
  puPulseArmor:       PowerUpDef(pool: puppNormal,    family: rpfShield,    group: pugNone,    maxLevel: 3, color: Color(r: 80,g:160,b:255,a:255), inLegendaryPanel: false, isElementalOrb: false),
  puRadialBurst:      PowerUpDef(pool: puppNormal,    family: rpfCore,      group: pugNone,    maxLevel: 3, color: Color(r:255,g:180,b: 50,a:255), inLegendaryPanel: false, isElementalOrb: false),
  puRage:             PowerUpDef(pool: puppNormal,    family: rpfCore,      group: pugNone,    maxLevel: 3, color: Color(r:255,g: 60,b: 60,a:255), inLegendaryPanel: false, isElementalOrb: false),
  puRapidFire:        PowerUpDef(pool: puppLegendary, family: rpfCore,      group: pugNone,    maxLevel: 1, color: Color(r:255,g:230,b: 50,a:255), inLegendaryPanel: false, isElementalOrb: false),
  puRegeneration:     PowerUpDef(pool: puppNormal,    family: rpfCore,      group: pugNone,    maxLevel: 3, color: Color(r: 60,g:220,b:120,a:255), inLegendaryPanel: false, isElementalOrb: false),
  puResonance:        PowerUpDef(pool: puppNormal,    family: rpfCore,      group: pugNone,    maxLevel: 3, color: Color(r:140,g:220,b:255,a:255), inLegendaryPanel: false, isElementalOrb: false),
  # puRotatingOrbs is legendary and NOT in pugOrb / isElementalOrb=false intentionally;
  # it is handled separately everywhere that needs elemental-orb membership.
  puRotatingOrbs:     PowerUpDef(pool: puppLegendary, family: rpfCore,      group: pugNone,    maxLevel: 1, color: Color(r:255,g:215,b:  0,a:255), inLegendaryPanel: false, isElementalOrb: false),
  puRotatingShield:   PowerUpDef(pool: puppNormal,    family: rpfShield,    group: pugNone,    maxLevel: 3, color: Color(r:  0,g:200,b:255,a:255), inLegendaryPanel: false, isElementalOrb: false),
  puSlowField:        PowerUpDef(pool: puppNormal,    family: rpfCore,      group: pugAura,    maxLevel: 3, color: Color(r:100,g:180,b:255,a:255), inLegendaryPanel: false, isElementalOrb: false),
  puSpecialRounds:    PowerUpDef(pool: puppNormal,    family: rpfCore,      group: pugNone,    maxLevel: 3, color: Color(r:255,g:200,b: 80,a:255), inLegendaryPanel: false, isElementalOrb: false),
  puSpeedBoost:       PowerUpDef(pool: puppLegendary, family: rpfCore,      group: pugNone,    maxLevel: 1, color: Color(r: 80,g:200,b:255,a:255), inLegendaryPanel: false, isElementalOrb: false),
  puThorns:           PowerUpDef(pool: puppNormal,    family: rpfShield,    group: pugNone,    maxLevel: 3, color: Color(r:100,g:200,b: 80,a:255), inLegendaryPanel: false, isElementalOrb: false),
  puTimeWarp:         PowerUpDef(pool: puppLegendary, family: rpfCore,      group: pugNone,    maxLevel: 1, color: Color(r:180,g:180,b:255,a:255), inLegendaryPanel: true,  isElementalOrb: false, allowedModes: {gmWaveBased, gmRoguelite}),
  puVolatile:         PowerUpDef(pool: puppLegendary, family: rpfCore,      group: pugNone,    maxLevel: 1, color: Color(r:255,g: 80,b: 20,a:255), inLegendaryPanel: false, isElementalOrb: false),
  puWallMaster:       PowerUpDef(pool: puppLegendary, family: rpfShield,    group: pugNone,    maxLevel: 1, color: Color(r:180,g:140,b:100,a:255), inLegendaryPanel: false, isElementalOrb: false, allowedModes: {gmWaveBased, gmRoguelite}),
  puWallTurrets:      PowerUpDef(pool: puppNormal,    family: rpfShield,    group: pugNone,    maxLevel: 3, color: Color(r:200,g:180,b:100,a:255), inLegendaryPanel: false, isElementalOrb: false, allowedModes: {gmWaveBased, gmRoguelite}),
  puWindAura:         PowerUpDef(pool: puppNormal,    family: rpfWind,      group: pugAura,    maxLevel: 3, color: Color(r:180,g:240,b:240,a:255), inLegendaryPanel: false, isElementalOrb: false),
  puWindBullets:      PowerUpDef(pool: puppNormal,    family: rpfWind,      group: pugBullet,  maxLevel: 3, color: Color(r:180,g:240,b:240,a:255), inLegendaryPanel: false, isElementalOrb: false),
  puWindMastery:      PowerUpDef(pool: puppLegendary, family: rpfWind,      group: pugMastery, maxLevel: 1, color: Color(r:160,g:255,b:255,a:255), inLegendaryPanel: false, isElementalOrb: false),
  puWindOrb:          PowerUpDef(pool: puppNormal,    family: rpfWind,      group: pugOrb,     maxLevel: 3, color: Color(r:180,g:240,b:240,a:255), inLegendaryPanel: false, isElementalOrb: true),
  # Mode-exclusive power-ups
  puGlitchField:      PowerUpDef(pool: puppNormal,    family: rpfArcane,    group: pugNone,    maxLevel: 3, color: Color(r:120,g:255,b:180,a:255), inLegendaryPanel: false, isElementalOrb: false, allowedModes: {gmRoguelite}),
  puTimeSurge:        PowerUpDef(pool: puppNormal,    family: rpfWind,      group: pugNone,    maxLevel: 3, color: Color(r:100,g:200,b:255,a:255), inLegendaryPanel: false, isElementalOrb: false, allowedModes: {gmTimeSurvival}),
  puLastStand:        PowerUpDef(pool: puppLegendary, family: rpfShield,    group: pugNone,    maxLevel: 1, color: Color(r:255,g:220,b: 60,a:255), inLegendaryPanel: false, isElementalOrb: false, allowedModes: {gmTimeSurvival}),
  puRecursion:        PowerUpDef(pool: puppNormal,    family: rpfCore,      group: pugNone,    maxLevel: 3, color: Color(r:255,g:140,b:255,a:255), inLegendaryPanel: false, isElementalOrb: false, allowedModes: {gmRoguelite}),
  puSectorProtocol:   PowerUpDef(pool: puppLegendary, family: rpfCore,      group: pugNone,    maxLevel: 1, color: Color(r:255,g:200,b:100,a:255), inLegendaryPanel: false, isElementalOrb: false, allowedModes: {gmRoguelite}),
  # Survival-exclusive power-ups (Stage 5)
  puCrisisMode:       PowerUpDef(pool: puppNormal,    family: rpfCore,      group: pugNone,    maxLevel: 3, color: Color(r:255,g: 80,b: 80,a:255), inLegendaryPanel: false, isElementalOrb: false, allowedModes: {gmTimeSurvival}),
  puAdaptiveFirewall: PowerUpDef(pool: puppNormal,    family: rpfShield,    group: pugNone,    maxLevel: 3, color: Color(r: 80,g:160,b:255,a:255), inLegendaryPanel: false, isElementalOrb: false, allowedModes: {gmTimeSurvival}),
  puLastTransmission: PowerUpDef(pool: puppNormal,    family: rpfBlood,     group: pugNone,    maxLevel: 3, color: Color(r:200,g: 60,b: 60,a:255), inLegendaryPanel: false, isElementalOrb: false, allowedModes: {gmTimeSurvival}),
  puKillChain:        PowerUpDef(pool: puppLegendary, family: rpfCore,      group: pugNone,    maxLevel: 1, color: Color(r:255,g:120,b: 50,a:255), inLegendaryPanel: false, isElementalOrb: false, allowedModes: {gmTimeSurvival}),
  # Roguelite-exclusive power-ups (Stage 5)
  puCorruptedCore:    PowerUpDef(pool: puppNormal,    family: rpfCore,      group: pugNone,    maxLevel: 3, color: Color(r:120,g:255,b:120,a:255), inLegendaryPanel: false, isElementalOrb: false, allowedModes: {gmRoguelite}),
  puRoomEcho:         PowerUpDef(pool: puppNormal,    family: rpfCore,      group: pugNone,    maxLevel: 3, color: Color(r:100,g:180,b:255,a:255), inLegendaryPanel: false, isElementalOrb: false, allowedModes: {gmRoguelite}),
  puChainReaction:    PowerUpDef(pool: puppNormal,    family: rpfCore,      group: pugNone,    maxLevel: 3, color: Color(r:255,g:200,b: 60,a:255), inLegendaryPanel: false, isElementalOrb: false, allowedModes: {gmRoguelite}),
  puKernelExploit:    PowerUpDef(pool: puppLegendary, family: rpfCore,      group: pugNone,    maxLevel: 1, color: Color(r:180,g: 80,b:255,a:255), inLegendaryPanel: false, isElementalOrb: false, allowedModes: {gmRoguelite}),
  puDataHarvest:      PowerUpDef(pool: puppNormal,    family: rpfCore,      group: pugNone,    maxLevel: 3, color: Color(r: 90,g:255,b:170,a:255), inLegendaryPanel: false, isElementalOrb: false, allowedModes: {gmRoguelite}),
]

# Derived constants, computed once at compile time from the registry above

const legendaryPool* = block:
  ## All power-ups in the legendary (boss) pool, in enum order.
  var r: seq[PowerUpType]
  for pt in PowerUpType:
    if allPowerUpDefs[pt].pool == puppLegendary:
      r.add(pt)
  r

const normalPool* = block:
  ## All power-ups in the normal (wave) pool, in enum order.
  var r: seq[PowerUpType]
  for pt in PowerUpType:
    if allPowerUpDefs[pt].pool == puppNormal:
      r.add(pt)
  r

const elementalOrbTypes* = block:
  ## The 7 single-element orbs.  puRotatingOrbs is intentionally excluded.
  var r: seq[PowerUpType]
  for pt in PowerUpType:
    if allPowerUpDefs[pt].isElementalOrb:
      r.add(pt)
  r

const legendaryPanelTypes* = block:
  ## Active legendaries displayed in the HUD panel (all have cooldowns).
  var r: seq[PowerUpType]
  for pt in PowerUpType:
    if allPowerUpDefs[pt].inLegendaryPanel:
      r.add(pt)
  r

# Inline lookup helpers

proc getPowerUpFamily*(pt: PowerUpType): RoguelitePowerFamily {.inline.} =
  allPowerUpDefs[pt].family

proc getPowerUpColor*(pt: PowerUpType): Color {.inline.} =
  allPowerUpDefs[pt].color

proc getPowerUpMaxLevel*(pt: PowerUpType): int {.inline.} =
  allPowerUpDefs[pt].maxLevel

proc recursionDamageBonusForLevel*(level: int): float32 {.inline.} =
  ## TOTAL fractional damage bonus for holding Recursion at the given level --
  ## cumulative, not per-rung. Reaching level 3 is worth +20% in all, so an
  ## upgrade must apply the difference between two calls, never the whole value
  ## again (see applyPowerUp).
  ## Shared so the immediate run boost (applyPowerUp) and the permanent
  ## cross-run accumulation (installPowerUp -> profile) never drift apart.
  case level
  of 0: 0.0'f32
  of 1: 0.08'f32
  of 2: 0.14'f32
  else: 0.20'f32

# Names

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
  of puRegeneration: t(tkPowerupRegeneration)
  of puDodgeChance: t(tkPowerupDodgeChance)
  of puCriticalHit: t(tkPowerupCriticalHit)
  of puCurse: t(tkPowerupCurse)
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
  of puCelestialVeil: t(tkPowerupCelestialVeil)
  of puVolatile: t(tkPowerupVolatile)
  of puResonance: t(tkPowerupResonance)
  of puBloodPact: t(tkPowerupBloodPact)
  of puConduit: t(tkPowerupConduit)
  of puAftershock: t(tkPowerupAftershock)
  of puNova: t(tkPowerupNova)
  of puHealPower: t(tkPowerupHealPower)
  of puBountiful: t(tkPowerupBountiful)
  of puGlitchField: t(tkPowerupGlitchField)
  of puTimeSurge: t(tkPowerupTimeSurge)
  of puLastStand: t(tkPowerupLastStand)
  of puRecursion: t(tkPowerupRecursion)
  of puSectorProtocol: t(tkPowerupSectorProtocol)
  of puCrisisMode: t(tkPowerupCrisisMode)
  of puAdaptiveFirewall: t(tkPowerupAdaptiveFirewall)
  of puLastTransmission: t(tkPowerupLastTransmission)
  of puKillChain: t(tkPowerupKillChain)
  of puCorruptedCore: t(tkPowerupCorruptedCore)
  of puRoomEcho: t(tkPowerupRoomEcho)
  of puChainReaction: t(tkPowerupChainReaction)
  of puKernelExploit: t(tkPowerupKernelExploit)
  of puDataHarvest: t(tkPowerupDataHarvest)

# Descriptions

proc getPowerUpDescription*(powerType: PowerUpType, level: int, playerDamage: float32 = 1.0): string =
  # Helper: format "base + scaled (pct%)", values are multiplied x100 for display
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
  of puAftershock:
    t(tkPowerupAftershockDesc)
  of puArcaneAura:
    case level
    of 1: t(tkPowerupArcaneAuraDesc1).replace("{0}", dmgPs(3.5, 0.3, playerDamage))
    of 2: t(tkPowerupArcaneAuraDesc2).replace("{0}", dmgPs(7.5, 0.3, playerDamage))
    else: t(tkPowerupArcaneAuraDesc3).replace("{0}", dmgPs(10.0, 0.3, playerDamage))
  of puArcaneBullets:
    case level
    of 1: t(tkPowerupArcaneBulletsDesc1)
    of 2: t(tkPowerupArcaneBulletsDesc2)
    else: t(tkPowerupArcaneBulletsDesc3)
  of puArcaneMastery:
    t(tkPowerupArcaneMasteryDesc)
  of puArcaneOrb:
    case level
    of 1: t(tkPowerupArcaneOrbDesc1).replace("{0}", dmg(5.25, 0.2625, playerDamage))
    of 2: t(tkPowerupArcaneOrbDesc2).replace("{0}", dmg(8.25, 0.2625, playerDamage))
    else: t(tkPowerupArcaneOrbDesc3).replace("{0}", dmg(12.0, 0.2625, playerDamage))
  of puBerserker:
    case level
    of 1: t(tkPowerupBerserkerDesc1)
    of 2: t(tkPowerupBerserkerDesc2)
    else: t(tkPowerupBerserkerDesc3)
  of puBloodAura:
    case level
    of 1: t(tkPowerupBloodAuraDesc1).replace("{0}", dmgPs(1.0, 0.3, playerDamage))
    of 2: t(tkPowerupBloodAuraDesc2).replace("{0}", dmgPs(2.5, 0.3, playerDamage))
    else: t(tkPowerupBloodAuraDesc3).replace("{0}", dmgPs(5.0, 0.3, playerDamage))
  of puBloodBullets:
    case level
    of 1: t(tkPowerupBloodBulletsDesc1)
    of 2: t(tkPowerupBloodBulletsDesc2)
    else: t(tkPowerupBloodBulletsDesc3)
  of puBloodMastery:
    t(tkPowerupBloodMasteryDesc)
  of puBloodOrb:
    case level
    of 1: t(tkPowerupBloodOrbDesc1).replace("{0}", dmg(3.5, 0.175, playerDamage))
    of 2: t(tkPowerupBloodOrbDesc2).replace("{0}", dmg(5.5, 0.175, playerDamage))
    else: t(tkPowerupBloodOrbDesc3).replace("{0}", dmg(8.0, 0.175, playerDamage))
  of puBloodPact:
    t(tkPowerupBloodPactDesc)
  of puBountiful:
    t(tkPowerupBountifulDesc)
  of puBulletRicochet:
    case level
    of 1: t(tkPowerupBulletRicochetDesc1)
    of 2: t(tkPowerupBulletRicochetDesc2)
    else: t(tkPowerupBulletRicochetDesc3)
  of puBulletSpeed:
    t(tkPowerupBulletSpeedDesc)
  of puBulletSplit:
    case level
    of 1: t(tkPowerupBulletSplitDesc1)
    of 2: t(tkPowerupBulletSplitDesc2)
    else: t(tkPowerupBulletSplitDesc3)
  of puCelestialVeil:
    t(tkPowerupCelestialVeilDesc)
  of puChainLightning:
    case level
    of 1: t(tkPowerupChainLightningDesc1)
    of 2: t(tkPowerupChainLightningDesc2)
    else: t(tkPowerupChainLightningDesc3)
  of puConduit:
    t(tkPowerupConduitDesc)
  of puCriticalHit:
    case level
    of 1: t(tkPowerupCriticalHitDesc1)
    of 2: t(tkPowerupCriticalHitDesc2)
    else: t(tkPowerupCriticalHitDesc3)
  of puCurse:
    case level
    of 1: t(tkPowerupCurseDesc1)
    of 2: t(tkPowerupCurseDesc2)
    else: t(tkPowerupCurseDesc3)
  of puDodgeChance:
    case level
    of 1: t(tkPowerupDodgeChanceDesc1)
    of 2: t(tkPowerupDodgeChanceDesc2)
    else: t(tkPowerupDodgeChanceDesc3)
  of puDoubleShot:
    t(tkPowerupDoubleShotDesc)
  of puEchoShots:
    t(tkPowerupEchoShotsDesc)
  of puExplosiveBullets:
    case level
    of 1: t(tkPowerupExplosiveBulletsDesc1)
    of 2: t(tkPowerupExplosiveBulletsDesc2)
    else: t(tkPowerupExplosiveBulletsDesc3)
  of puFireAura:
    case level
    of 1: t(tkPowerupFireAuraDesc1).replace("{0}", dmgPs(1.5, 0.35, playerDamage))
    of 2: t(tkPowerupFireAuraDesc2).replace("{0}", dmgPs(3.5, 0.35, playerDamage))
    else: t(tkPowerupFireAuraDesc3).replace("{0}", dmgPs(6.5, 0.35, playerDamage))
  of puFireBullets:
    case level
    of 1: t(tkPowerupFireBulletsDesc1).replace("{0}", dmgPs(2.5, 0.25, playerDamage))
    of 2: t(tkPowerupFireBulletsDesc2).replace("{0}", dmgPs(3.75, 0.25, playerDamage))
    else: t(tkPowerupFireBulletsDesc3).replace("{0}", dmgPs(5.0, 0.25, playerDamage))
  of puFireMastery:
    t(tkPowerupFireMasteryDesc)
  of puFireOrb:
    case level
    of 1: t(tkPowerupFireOrbDesc1).replace("{0}", dmg(3.5, 0.175, playerDamage))
    of 2: t(tkPowerupFireOrbDesc2).replace("{0}", dmg(5.5, 0.175, playerDamage))
    else: t(tkPowerupFireOrbDesc3).replace("{0}", dmg(8.0, 0.175, playerDamage))
  of puFortified:
    case level
    of 1: t(tkPowerupFortifiedDesc1)
    of 2: t(tkPowerupFortifiedDesc2)
    else: t(tkPowerupFortifiedDesc3)
  of puFrostMastery:
    t(tkPowerupFrostMasteryDesc)
  of puFrostOrb:
    case level
    of 1: t(tkPowerupFrostOrbDesc1).replace("{0}", dmg(3.5, 0.175, playerDamage))
    of 2: t(tkPowerupFrostOrbDesc2).replace("{0}", dmg(5.5, 0.175, playerDamage))
    else: t(tkPowerupFrostOrbDesc3).replace("{0}", dmg(8.0, 0.175, playerDamage))
  of puFrostShots:
    case level
    of 1: t(tkPowerupFrostShotsDesc1)
    of 2: t(tkPowerupFrostShotsDesc2)
    else: t(tkPowerupFrostShotsDesc3)
  of puGiantSlayer:
    case level
    of 1: t(tkPowerupGiantSlayerDesc1)
    of 2: t(tkPowerupGiantSlayerDesc2)
    else: t(tkPowerupGiantSlayerDesc3)
  of puGravityWell:
    t(tkPowerupGravityWellDesc)
  of puHealPower:
    case level
    of 1: t(tkPowerupHealPowerDesc1)
    of 2: t(tkPowerupHealPowerDesc2)
    else: t(tkPowerupHealPowerDesc3)
  of puHeavyRounds:
    case level
    of 1: t(tkPowerupHeavyRoundsDesc1)
    of 2: t(tkPowerupHeavyRoundsDesc2)
    else: t(tkPowerupHeavyRoundsDesc3)
  of puLifeSteal:
    case level
    of 1: t(tkPowerupLifeStealDesc1)
    of 2: t(tkPowerupLifeStealDesc2)
    else: t(tkPowerupLifeStealDesc3)
  of puLightningAura:
    case level
    of 1: t(tkPowerupLightningAuraDesc1).replace("{0}", dmgPs(1.0, 0.3, playerDamage))
    of 2: t(tkPowerupLightningAuraDesc2).replace("{0}", dmgPs(2.5, 0.3, playerDamage))
    else: t(tkPowerupLightningAuraDesc3).replace("{0}", dmgPs(5.0, 0.3, playerDamage))
  of puLightningMastery:
    t(tkPowerupLightningMasteryDesc)
  of puLightningOrb:
    case level
    of 1: t(tkPowerupLightningOrbDesc1).replace("{0}", dmg(3.5, 0.175, playerDamage))
    of 2: t(tkPowerupLightningOrbDesc2).replace("{0}", dmg(5.5, 0.175, playerDamage))
    else: t(tkPowerupLightningOrbDesc3).replace("{0}", dmg(8.0, 0.175, playerDamage))
  of puLuckyCoins:
    t(tkPowerupLuckyCoinsDesc)
  of puMagicalBullets:
    t(tkPowerupMagicalBulletsDesc)
  of puMaxHealth:
    t(tkPowerupMaxHealthDesc)
  of puMultiShot:
    t(tkPowerupMultiShotDesc)
  of puNova:
    t(tkPowerupNovaDesc)
  of puOvercharge:
    t(tkPowerupOverchargeDesc)
  of puParry:
    t(tkPowerupParryDesc)
  of puPhaseShift:
    t(tkPowerupPhaseShiftDesc)
  of puPiercingShots:
    case level
    of 1: t(tkPowerupPiercingShotsDesc1)
    of 2: t(tkPowerupPiercingShotsDesc2)
    else: t(tkPowerupPiercingShotsDesc3)
  of puPoisonAura:
    case level
    of 1: t(tkPowerupPoisonAuraDesc1).replace("{0}", dmgPs(0.8, 0.25, playerDamage))
    of 2: t(tkPowerupPoisonAuraDesc2).replace("{0}", dmgPs(2.0, 0.25, playerDamage))
    else: t(tkPowerupPoisonAuraDesc3).replace("{0}", dmgPs(4.0, 0.25, playerDamage))
  of puPoisonMastery:
    t(tkPowerupPoisonMasteryDesc)
  of puPoisonOrb:
    case level
    of 1: t(tkPowerupPoisonOrbDesc1).replace("{0}", dmg(3.5, 0.175, playerDamage))
    of 2: t(tkPowerupPoisonOrbDesc2).replace("{0}", dmg(5.5, 0.175, playerDamage))
    else: t(tkPowerupPoisonOrbDesc3).replace("{0}", dmg(8.0, 0.175, playerDamage))
  of puPoisonShot:
    case level
    of 1: t(tkPowerupPoisonShotDesc1).replace("{0}", dmgPs(1.5, 0.2, playerDamage))
    of 2: t(tkPowerupPoisonShotDesc2).replace("{0}", dmgPs(2.5, 0.2, playerDamage))
    else: t(tkPowerupPoisonShotDesc3).replace("{0}", dmgPs(3.75, 0.2, playerDamage))
  of puPulseArmor:
    case level
    of 1: t(tkPowerupPulseArmorDesc1)
    of 2: t(tkPowerupPulseArmorDesc2)
    else: t(tkPowerupPulseArmorDesc3)
  of puRadialBurst:
    case level
    of 1: t(tkPowerupRadialBurstDesc1)
    of 2: t(tkPowerupRadialBurstDesc2)
    else: t(tkPowerupRadialBurstDesc3)
  of puRage:
    case level
    of 1: t(tkPowerupRageDesc1)
    of 2: t(tkPowerupRageDesc2)
    else: t(tkPowerupRageDesc3)
  of puRapidFire:
    t(tkPowerupRapidFireDesc)
  of puRegeneration:
    case level
    of 1: t(tkPowerupRegenerationDesc1)
    of 2: t(tkPowerupRegenerationDesc2)
    else: t(tkPowerupRegenerationDesc3)
  of puResonance:
    case level
    of 1: t(tkPowerupResonanceDesc1)
    of 2: t(tkPowerupResonanceDesc2)
    else: t(tkPowerupResonanceDesc3)
  of puRotatingOrbs:
    t(tkPowerupRotatingOrbsDesc).replace("{0}", dmg(1.5, 0.175, playerDamage))
  of puRotatingShield:
    case level
    of 1: t(tkPowerupRotatingShieldDesc1)
    of 2: t(tkPowerupRotatingShieldDesc2)
    else: t(tkPowerupRotatingShieldDesc3)
  of puSlowField:
    case level
    of 1: t(tkPowerupSlowFieldDesc1)
    of 2: t(tkPowerupSlowFieldDesc2)
    else: t(tkPowerupSlowFieldDesc3)
  of puSpecialRounds:
    case level
    of 1: t(tkPowerupSpecialRoundsDesc1)
    of 2: t(tkPowerupSpecialRoundsDesc2)
    else: t(tkPowerupSpecialRoundsDesc3)
  of puSpeedBoost:
    t(tkPowerupSpeedBoostDesc)
  of puThorns:
    case level
    of 1: t(tkPowerupThornsDesc1)
    of 2: t(tkPowerupThornsDesc2)
    else: t(tkPowerupThornsDesc3)
  of puTimeWarp:
    t(tkPowerupTimeWarpDesc)
  of puVolatile:
    t(tkPowerupVolatileDesc)
  of puWallMaster:
    t(tkPowerupWallMasterDesc)
  of puWallTurrets:
    case level
    of 1: t(tkPowerupWallTurretsDesc1)
    of 2: t(tkPowerupWallTurretsDesc2)
    else: t(tkPowerupWallTurretsDesc3).replace("{0}", $(round(playerDamage * 0.3 * 100).int))
  of puWindAura:
    case level
    of 1: t(tkPowerupWindAuraDesc1)
    of 2: t(tkPowerupWindAuraDesc2)
    else: t(tkPowerupWindAuraDesc3)
  of puWindBullets:
    case level
    of 1: t(tkPowerupWindBulletsDesc1)
    of 2: t(tkPowerupWindBulletsDesc2)
    else: t(tkPowerupWindBulletsDesc3)
  of puWindMastery:
    t(tkPowerupWindMasteryDesc)
  of puWindOrb:
    case level
    of 1: t(tkPowerupWindOrbDesc1).replace("{0}", dmg(3.5, 0.175, playerDamage))
    of 2: t(tkPowerupWindOrbDesc2).replace("{0}", dmg(5.5, 0.175, playerDamage))
    else: t(tkPowerupWindOrbDesc3).replace("{0}", dmg(8.0, 0.175, playerDamage))
  of puGlitchField:
    case level
    of 1: t(tkPowerupGlitchFieldDesc1)
    of 2: t(tkPowerupGlitchFieldDesc2)
    else: t(tkPowerupGlitchFieldDesc3)
  of puTimeSurge:
    case level
    of 1: t(tkPowerupTimeSurgeDesc1)
    of 2: t(tkPowerupTimeSurgeDesc2)
    else: t(tkPowerupTimeSurgeDesc3)
  of puLastStand:
    t(tkPowerupLastStandDesc)
  of puRecursion:
    case level
    of 1: t(tkPowerupRecursionDesc1)
    of 2: t(tkPowerupRecursionDesc2)
    else: t(tkPowerupRecursionDesc3)
  of puSectorProtocol:
    t(tkPowerupSectorProtocolDesc)
  of puCrisisMode:
    case level
    of 1: t(tkPowerupCrisisModeDesc1)
    of 2: t(tkPowerupCrisisModeDesc2)
    else: t(tkPowerupCrisisModeDesc3)
  of puAdaptiveFirewall:
    case level
    of 1: t(tkPowerupAdaptiveFirewallDesc1)
    of 2: t(tkPowerupAdaptiveFirewallDesc2)
    else: t(tkPowerupAdaptiveFirewallDesc3)
  of puLastTransmission:
    case level
    of 1: t(tkPowerupLastTransmissionDesc1)
    of 2: t(tkPowerupLastTransmissionDesc2)
    else: t(tkPowerupLastTransmissionDesc3)
  of puKillChain:
    t(tkPowerupKillChainDesc)
  of puCorruptedCore:
    case level
    of 1: t(tkPowerupCorruptedCoreDesc1)
    of 2: t(tkPowerupCorruptedCoreDesc2)
    else: t(tkPowerupCorruptedCoreDesc3)
  of puRoomEcho:
    case level
    of 1: t(tkPowerupRoomEchoDesc1)
    of 2: t(tkPowerupRoomEchoDesc2)
    else: t(tkPowerupRoomEchoDesc3)
  of puChainReaction:
    case level
    of 1: t(tkPowerupChainReactionDesc1)
    of 2: t(tkPowerupChainReactionDesc2)
    else: t(tkPowerupChainReactionDesc3)
  of puKernelExploit:
    t(tkPowerupKernelExploitDesc)
  of puDataHarvest:
    case level
    of 1: t(tkPowerupDataHarvestDesc1)
    of 2: t(tkPowerupDataHarvestDesc2)
    else: t(tkPowerupDataHarvestDesc3)
