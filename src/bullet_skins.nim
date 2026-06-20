## Bullet Skins System
## Defines available bullet skins and rendering functions

import raylib, math
import localization

type
  BulletSkinType* = enum
    bskDefault,      # Original cyan
    bskNeonPink,     # Hot pink/magenta
    bskEmerald,      # Green tech
    bskSunset,       # Orange/red
    bskAmethyst,     # Purple/violet
    bskGold,         # Golden/yellow
    bskIce,          # Light blue/white
    bskShadow,       # Dark gray/black
    bskRainbow,      # Multi-color animated
    bskMatrix,       # Green matrix style
    bskVoid,         # Dark purple void
    bskPlasma,       # Blue/purple plasma

  BulletSkinData* = object
    name*: string
    description*: string
    primaryColor*: Color
    glowColor*: Color
    trailColor*: Color
    isAnimated*: bool
    isUnlocked*: bool

# Global bullet skin database
var bulletSkinDatabase*: array[BulletSkinType, BulletSkinData]

proc initializeBulletSkins*() =
  ## Initialize all available bullet skins with their data
  bulletSkinDatabase[bskDefault] = BulletSkinData(
    name: t("bullet_default"),
    description: t("bullet_default_desc"),
    primaryColor: Color(r: 0, g: 200, b: 200, a: 255),
    glowColor: Color(r: 0, g: 255, b: 255, a: 100),
    trailColor: Color(r: 0, g: 150, b: 150, a: 150),
    isAnimated: false,
    isUnlocked: true
  )

  bulletSkinDatabase[bskNeonPink] = BulletSkinData(
    name: t("bullet_neon_pink"),
    description: t("bullet_neon_pink_desc"),
    primaryColor: Color(r: 255, g: 0, b: 180, a: 255),
    glowColor: Color(r: 255, g: 100, b: 200, a: 100),
    trailColor: Color(r: 200, g: 0, b: 150, a: 150),
    isAnimated: false,
    isUnlocked: true
  )

  bulletSkinDatabase[bskEmerald] = BulletSkinData(
    name: t("bullet_emerald"),
    description: t("bullet_emerald_desc"),
    primaryColor: Color(r: 0, g: 255, b: 100, a: 255),
    glowColor: Color(r: 100, g: 255, b: 150, a: 100),
    trailColor: Color(r: 0, g: 200, b: 80, a: 150),
    isAnimated: false,
    isUnlocked: true
  )

  bulletSkinDatabase[bskSunset] = BulletSkinData(
    name: t("bullet_sunset"),
    description: t("bullet_sunset_desc"),
    primaryColor: Color(r: 255, g: 100, b: 0, a: 255),
    glowColor: Color(r: 255, g: 150, b: 50, a: 100),
    trailColor: Color(r: 255, g: 50, b: 0, a: 150),
    isAnimated: false,
    isUnlocked: true
  )

  bulletSkinDatabase[bskAmethyst] = BulletSkinData(
    name: t("bullet_amethyst"),
    description: t("bullet_amethyst_desc"),
    primaryColor: Color(r: 150, g: 0, b: 255, a: 255),
    glowColor: Color(r: 200, g: 100, b: 255, a: 100),
    trailColor: Color(r: 120, g: 0, b: 200, a: 150),
    isAnimated: false,
    isUnlocked: true
  )

  bulletSkinDatabase[bskGold] = BulletSkinData(
    name: t("bullet_gold"),
    description: t("bullet_gold_desc"),
    primaryColor: Color(r: 255, g: 215, b: 0, a: 255),
    glowColor: Color(r: 255, g: 235, b: 100, a: 100),
    trailColor: Color(r: 255, g: 180, b: 0, a: 150),
    isAnimated: false,
    isUnlocked: true
  )

  bulletSkinDatabase[bskIce] = BulletSkinData(
    name: t("bullet_ice"),
    description: t("bullet_ice_desc"),
    primaryColor: Color(r: 150, g: 220, b: 255, a: 255),
    glowColor: Color(r: 200, g: 240, b: 255, a: 100),
    trailColor: Color(r: 100, g: 180, b: 255, a: 150),
    isAnimated: false,
    isUnlocked: true
  )

  bulletSkinDatabase[bskShadow] = BulletSkinData(
    name: t("bullet_shadow"),
    description: t("bullet_shadow_desc"),
    primaryColor: Color(r: 60, g: 60, b: 80, a: 255),
    glowColor: Color(r: 100, g: 100, b: 120, a: 100),
    trailColor: Color(r: 40, g: 40, b: 60, a: 150),
    isAnimated: false,
    isUnlocked: true
  )

  bulletSkinDatabase[bskRainbow] = BulletSkinData(
    name: t("bullet_rainbow"),
    description: t("bullet_rainbow_desc"),
    primaryColor: Color(r: 255, g: 0, b: 0, a: 255),
    glowColor: Color(r: 255, g: 255, b: 255, a: 100),
    trailColor: Color(r: 200, g: 0, b: 200, a: 150),
    isAnimated: true,
    isUnlocked: true
  )

  bulletSkinDatabase[bskMatrix] = BulletSkinData(
    name: t("bullet_matrix"),
    description: t("bullet_matrix_desc"),
    primaryColor: Color(r: 0, g: 255, b: 0, a: 255),
    glowColor: Color(r: 100, g: 255, b: 100, a: 100),
    trailColor: Color(r: 0, g: 180, b: 0, a: 150),
    isAnimated: true,
    isUnlocked: true
  )

  bulletSkinDatabase[bskVoid] = BulletSkinData(
    name: t("bullet_void"),
    description: t("bullet_void_desc"),
    primaryColor: Color(r: 80, g: 0, b: 120, a: 255),
    glowColor: Color(r: 150, g: 50, b: 200, a: 100),
    trailColor: Color(r: 50, g: 0, b: 80, a: 150),
    isAnimated: true,
    isUnlocked: true
  )

  bulletSkinDatabase[bskPlasma] = BulletSkinData(
    name: t("bullet_plasma"),
    description: t("bullet_plasma_desc"),
    primaryColor: Color(r: 100, g: 100, b: 255, a: 255),
    glowColor: Color(r: 150, g: 150, b: 255, a: 100),
    trailColor: Color(r: 150, g: 50, b: 255, a: 150),
    isAnimated: true,
    isUnlocked: true
  )

proc getBulletSkinColors*(skinType: BulletSkinType, time: float32): tuple[primary, glow, trail: Color] =
  ## Get the colors for a bullet skin, applying animations if needed
  let skin = bulletSkinDatabase[skinType]

  if not skin.isAnimated:
    return (skin.primaryColor, skin.glowColor, skin.trailColor)

  # Apply time-based animations for animated skins
  case skinType
  of bskRainbow:
    # Cycle through rainbow spectrum
    let hue = (time * 0.5) mod 1.0
    let r = uint8((sin(hue * PI * 2.0) * 0.5 + 0.5) * 255)
    let g = uint8((sin((hue + 0.333) * PI * 2.0) * 0.5 + 0.5) * 255)
    let b = uint8((sin((hue + 0.666) * PI * 2.0) * 0.5 + 0.5) * 255)
    return (
      Color(r: r, g: g, b: b, a: 255),
      Color(r: 255, g: 255, b: 255, a: 100),
      Color(r: (r * 3) div 4, g: (g * 3) div 4, b: (b * 3) div 4, a: 150)
    )
  of bskMatrix:
    # Pulse green intensity
    let pulse = (sin(time * 3.0) * 0.3 + 0.7)
    let greenVal = uint8(pulse * 255)
    return (
      Color(r: 0, g: greenVal, b: 0, a: 255),
      Color(r: uint8(pulse * 100), g: 255, b: uint8(pulse * 100), a: 100),
      Color(r: 0, g: uint8(pulse * 180), b: 0, a: 150)
    )
  of bskVoid:
    # Pulsing void energy
    let pulse = sin(time * 2.0) * 0.5 + 0.5
    let purpleShift = uint8(80 + pulse * 40)
    return (
      Color(r: purpleShift, g: 0, b: uint8(120 + pulse * 60), a: 255),
      Color(r: uint8(150 + pulse * 50), g: uint8(50 + pulse * 50), b: 200, a: 100),
      Color(r: 50, g: 0, b: uint8(80 + pulse * 40), a: 150)
    )
  of bskPlasma:
    # Oscillating blue-purple plasma
    let oscillation = sin(time * 2.5) * 0.5 + 0.5
    let blueVal = uint8(100 + oscillation * 100)
    let purpleVal = uint8(255 - oscillation * 100)
    return (
      Color(r: blueVal, g: blueVal, b: purpleVal, a: 255),
      Color(r: uint8(150 + oscillation * 50), g: uint8(150 + oscillation * 50), b: 255, a: 100),
      Color(r: uint8(150 - oscillation * 50), g: 50, b: purpleVal, a: 150)
    )
  else:
    return (skin.primaryColor, skin.glowColor, skin.trailColor)

proc getBulletSkinData*(skinType: BulletSkinType): BulletSkinData =
  ## Get the data for a specific bullet skin
  return bulletSkinDatabase[skinType]

proc getBulletSkinName*(skinType: BulletSkinType): string =
  ## Get the display name of a bullet skin
  return bulletSkinDatabase[skinType].name

proc getBulletSkinDescription*(skinType: BulletSkinType): string =
  ## Get the description of a bullet skin
  return bulletSkinDatabase[skinType].description

proc isBulletSkinUnlocked*(skinType: BulletSkinType): bool =
  ## Check if a bullet skin is unlocked
  return bulletSkinDatabase[skinType].isUnlocked

proc unlockBulletSkin*(skinType: BulletSkinType) =
  ## Unlock a bullet skin for use
  bulletSkinDatabase[skinType].isUnlocked = true

proc getUnlockedBulletSkins*(): seq[BulletSkinType] =
  ## Get a list of all unlocked bullet skins
  result = @[]
  for skinType in BulletSkinType:
    if isBulletSkinUnlocked(skinType):
      result.add(skinType)
