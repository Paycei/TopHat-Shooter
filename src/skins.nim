## Player Skins System
## Defines available player skins and rendering functions

import raylib, math
import localization

type
  SkinType* = enum
    skDefault,      # Original cyan OS-style
    skNeonPink,     # Hot pink/magenta cyber
    skEmerald,      # Green tech
    skSunset,       # Orange/red gradient
    skAmethyst,     # Purple/violet
    skGold,         # Golden/yellow
    skIce,          # Light blue/white
    skShadow,       # Dark gray/black
    skRainbow,      # Multi-color animated
    skMatrix,       # Green matrix style
    skVoid,         # Dark purple void
    skPlasma,       # Blue/purple plasma

  SkinData* = object
    name*: string
    description*: string
    primaryColor*: Color
    secondaryColor*: Color
    coreColor*: Color
    isAnimated*: bool      # Whether skin uses time-based color animation
    isUnlocked*: bool      # Whether player has unlocked this skin

# Global skin database
var skinDatabase*: array[SkinType, SkinData]

proc initializeSkins*() =
  ## Initialize all available skins with their data
  skinDatabase[skDefault] = SkinData(
    name: t("skin_default"),
    description: t("skin_default_desc"),
    primaryColor: Color(r: 0, g: 200, b: 200, a: 255),
    secondaryColor: Color(r: 0, g: 150, b: 200, a: 255),
    coreColor: Color(r: 255, g: 255, b: 255, a: 255),
    isAnimated: false,
    isUnlocked: true
  )

  skinDatabase[skNeonPink] = SkinData(
    name: t("skin_neon_pink"),
    description: t("skin_neon_pink_desc"),
    primaryColor: Color(r: 255, g: 0, b: 180, a: 255),
    secondaryColor: Color(r: 200, g: 0, b: 150, a: 255),
    coreColor: Color(r: 255, g: 150, b: 230, a: 255),
    isAnimated: true,
    isUnlocked: true
  )

  skinDatabase[skEmerald] = SkinData(
    name: t("skin_emerald"),
    description: t("skin_emerald_desc"),
    primaryColor: Color(r: 0, g: 255, b: 100, a: 255),
    secondaryColor: Color(r: 0, g: 200, b: 80, a: 255),
    coreColor: Color(r: 200, g: 255, b: 200, a: 255),
    isAnimated: false,
    isUnlocked: true
  )

  skinDatabase[skSunset] = SkinData(
    name: t("skin_sunset"),
    description: t("skin_sunset_desc"),
    primaryColor: Color(r: 255, g: 100, b: 0, a: 255),
    secondaryColor: Color(r: 255, g: 50, b: 0, a: 255),
    coreColor: Color(r: 255, g: 200, b: 100, a: 255),
    isAnimated: true,
    isUnlocked: true
  )

  skinDatabase[skAmethyst] = SkinData(
    name: t("skin_amethyst"),
    description: t("skin_amethyst_desc"),
    primaryColor: Color(r: 150, g: 0, b: 255, a: 255),
    secondaryColor: Color(r: 120, g: 0, b: 200, a: 255),
    coreColor: Color(r: 220, g: 180, b: 255, a: 255),
    isAnimated: false,
    isUnlocked: true
  )

  skinDatabase[skGold] = SkinData(
    name: t("skin_gold"),
    description: t("skin_gold_desc"),
    primaryColor: Color(r: 255, g: 215, b: 0, a: 255),
    secondaryColor: Color(r: 255, g: 180, b: 0, a: 255),
    coreColor: Color(r: 255, g: 255, b: 200, a: 255),
    isAnimated: true,
    isUnlocked: true
  )

  skinDatabase[skIce] = SkinData(
    name: t("skin_ice"),
    description: t("skin_ice_desc"),
    primaryColor: Color(r: 150, g: 220, b: 255, a: 255),
    secondaryColor: Color(r: 100, g: 180, b: 255, a: 255),
    coreColor: Color(r: 240, g: 250, b: 255, a: 255),
    isAnimated: true,
    isUnlocked: true
  )

  skinDatabase[skShadow] = SkinData(
    name: t("skin_shadow"),
    description: t("skin_shadow_desc"),
    primaryColor: Color(r: 60, g: 60, b: 80, a: 255),
    secondaryColor: Color(r: 40, g: 40, b: 60, a: 255),
    coreColor: Color(r: 180, g: 180, b: 200, a: 255),
    isAnimated: true,
    isUnlocked: true
  )

  skinDatabase[skRainbow] = SkinData(
    name: t("skin_rainbow"),
    description: t("skin_rainbow_desc"),
    primaryColor: Color(r: 255, g: 0, b: 0, a: 255),
    secondaryColor: Color(r: 200, g: 0, b: 200, a: 255),
    coreColor: Color(r: 255, g: 255, b: 255, a: 255),
    isAnimated: true,
    isUnlocked: true
  )

  skinDatabase[skMatrix] = SkinData(
    name: t("skin_matrix"),
    description: t("skin_matrix_desc"),
    primaryColor: Color(r: 0, g: 255, b: 0, a: 255),
    secondaryColor: Color(r: 0, g: 180, b: 0, a: 255),
    coreColor: Color(r: 180, g: 255, b: 180, a: 255),
    isAnimated: true,
    isUnlocked: true
  )

  skinDatabase[skVoid] = SkinData(
    name: t("skin_void"),
    description: t("skin_void_desc"),
    primaryColor: Color(r: 80, g: 0, b: 120, a: 255),
    secondaryColor: Color(r: 50, g: 0, b: 80, a: 255),
    coreColor: Color(r: 150, g: 100, b: 200, a: 255),
    isAnimated: true,
    isUnlocked: true
  )

  skinDatabase[skPlasma] = SkinData(
    name: t("skin_plasma"),
    description: t("skin_plasma_desc"),
    primaryColor: Color(r: 100, g: 100, b: 255, a: 255),
    secondaryColor: Color(r: 150, g: 50, b: 255, a: 255),
    coreColor: Color(r: 200, g: 200, b: 255, a: 255),
    isAnimated: true,
    isUnlocked: true
  )

proc getSkinColors*(skinType: SkinType, time: float32): tuple[primary, secondary, core: Color] =
  ## Get the colors for a skin, applying animations if needed
  let skin = skinDatabase[skinType]

  if not skin.isAnimated:
    return (skin.primaryColor, skin.secondaryColor, skin.coreColor)

  # Apply time-based animations for animated skins
  case skinType
  of skNeonPink:
    # Neon-sign buzz: brightness flutters like a slightly unstable tube light
    let buzz = 0.85 + 0.15 * sin(time * 9.0) * sin(time * 2.3)
    return (
      Color(r: uint8(255.0 * buzz), g: 0, b: uint8(180.0 * buzz), a: 255),
      Color(r: uint8(200.0 * buzz), g: 0, b: uint8(150.0 * buzz), a: 255),
      Color(r: 255, g: uint8(120.0 + 60.0 * buzz), b: 230, a: 255)
    )
  of skSunset:
    # Slow warm drift between deep crimson and bright orange
    let drift = sin(time * 0.8) * 0.5 + 0.5
    return (
      Color(r: 255, g: uint8(60.0 + drift * 80.0), b: uint8(drift * 40.0), a: 255),
      Color(r: 255, g: uint8(30.0 + drift * 50.0), b: 0, a: 255),
      Color(r: 255, g: uint8(180.0 + drift * 40.0), b: uint8(90.0 + drift * 50.0), a: 255)
    )
  of skGold:
    # Golden shimmer with a short periodic glint flash on the core
    let shimmer = sin(time * 2.2) * 0.5 + 0.5
    let glint = pow(max(0.0'f32, sin(time * 1.4)), 8.0'f32)
    return (
      Color(r: 255, g: uint8(195.0 + shimmer * 40.0), b: uint8(glint * 120.0), a: 255),
      Color(r: uint8(235.0 + glint * 20.0), g: uint8(165.0 + shimmer * 30.0), b: 0, a: 255),
      Color(r: 255, g: 255, b: uint8(170.0 + glint * 85.0), a: 255)
    )
  of skIce:
    # Crystalline shimmer: cool blue-white sparkle drifting across the body
    let shimmer = sin(time * 3.1) * 0.5 + 0.5
    let sparkle = pow(max(0.0'f32, sin(time * 5.3 + 1.0)), 10.0'f32)
    return (
      Color(r: uint8(140.0 + shimmer * 40.0), g: uint8(210.0 + shimmer * 25.0), b: 255, a: 255),
      Color(r: uint8(90.0 + shimmer * 30.0), g: uint8(170.0 + shimmer * 25.0), b: 255, a: 255),
      Color(r: uint8(235.0 + sparkle * 20.0), g: uint8(245.0 + sparkle * 10.0), b: 255, a: 255)
    )
  of skShadow:
    # Smoldering shadow: slow dim pulse with a faint violet ember undertone
    let smolder = sin(time * 1.2) * 0.5 + 0.5
    return (
      Color(r: uint8(50.0 + smolder * 25.0), g: uint8(50.0 + smolder * 15.0),
            b: uint8(75.0 + smolder * 35.0), a: 255),
      Color(r: uint8(35.0 + smolder * 15.0), g: 40, b: uint8(55.0 + smolder * 25.0), a: 255),
      Color(r: uint8(170.0 + smolder * 30.0), g: uint8(170.0 + smolder * 20.0),
            b: uint8(195.0 + smolder * 40.0), a: 255)
    )
  of skRainbow:
    # Cycle through rainbow spectrum
    let hue = (time * 0.5) mod 1.0
    let r = uint8((sin(hue * PI * 2.0) * 0.5 + 0.5) * 255)
    let g = uint8((sin((hue + 0.333) * PI * 2.0) * 0.5 + 0.5) * 255)
    let b = uint8((sin((hue + 0.666) * PI * 2.0) * 0.5 + 0.5) * 255)
    return (
      Color(r: r, g: g, b: b, a: 255),
      Color(r: (r * 3) div 4, g: (g * 3) div 4, b: (b * 3) div 4, a: 255),
      Color(r: 255, g: 255, b: 255, a: 255)
    )
  of skMatrix:
    # Pulse green intensity
    let pulse = (sin(time * 3.0) * 0.3 + 0.7)
    let greenVal = uint8(pulse * 255)
    return (
      Color(r: 0, g: greenVal, b: 0, a: 255),
      Color(r: 0, g: uint8(pulse * 180), b: 0, a: 255),
      Color(r: uint8(pulse * 180), g: 255, b: uint8(pulse * 180), a: 255)
    )
  of skVoid:
    # Pulsing void energy
    let pulse = sin(time * 2.0) * 0.5 + 0.5
    let purpleShift = uint8(80 + pulse * 40)
    return (
      Color(r: purpleShift, g: 0, b: uint8(120 + pulse * 60), a: 255),
      Color(r: 50, g: 0, b: uint8(80 + pulse * 40), a: 255),
      Color(r: uint8(150 + pulse * 50), g: uint8(100 + pulse * 50), b: 200, a: 255)
    )
  of skPlasma:
    # Oscillating blue-purple plasma
    let oscillation = sin(time * 2.5) * 0.5 + 0.5
    let blueVal = uint8(100 + oscillation * 100)
    let purpleVal = uint8(255 - oscillation * 100)
    return (
      Color(r: blueVal, g: blueVal, b: purpleVal, a: 255),
      Color(r: uint8(150 - oscillation * 50), g: 50, b: purpleVal, a: 255),
      Color(r: 200, g: 200, b: 255, a: 255)
    )
  else:
    # Fallback to static colors
    return (skin.primaryColor, skin.secondaryColor, skin.coreColor)

proc getSkinData*(skinType: SkinType): SkinData =
  ## Get the data for a specific skin
  return skinDatabase[skinType]

proc getSkinName*(skinType: SkinType): string =
  ## Get the display name of a skin
  return skinDatabase[skinType].name

proc getSkinDescription*(skinType: SkinType): string =
  ## Get the description of a skin
  return skinDatabase[skinType].description
