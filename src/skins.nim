## Player Skins System
## Defines available player skins and rendering functions

import raylib, types, math

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
    name: "System Default",
    description: "Classic cyan OS interface",
    primaryColor: Color(r: 0, g: 200, b: 200, a: 255),
    secondaryColor: Color(r: 0, g: 150, b: 200, a: 255),
    coreColor: Color(r: 255, g: 255, b: 255, a: 255),
    isAnimated: false,
    isUnlocked: true
  )

  skinDatabase[skNeonPink] = SkinData(
    name: "Neon Pink",
    description: "Hot magenta cyberpunk style",
    primaryColor: Color(r: 255, g: 0, b: 180, a: 255),
    secondaryColor: Color(r: 200, g: 0, b: 150, a: 255),
    coreColor: Color(r: 255, g: 150, b: 230, a: 255),
    isAnimated: false,
    isUnlocked: true
  )

  skinDatabase[skEmerald] = SkinData(
    name: "Emerald Tech",
    description: "Advanced green technology",
    primaryColor: Color(r: 0, g: 255, b: 100, a: 255),
    secondaryColor: Color(r: 0, g: 200, b: 80, a: 255),
    coreColor: Color(r: 200, g: 255, b: 200, a: 255),
    isAnimated: false,
    isUnlocked: true
  )

  skinDatabase[skSunset] = SkinData(
    name: "Sunset Blaze",
    description: "Fiery orange and red",
    primaryColor: Color(r: 255, g: 100, b: 0, a: 255),
    secondaryColor: Color(r: 255, g: 50, b: 0, a: 255),
    coreColor: Color(r: 255, g: 200, b: 100, a: 255),
    isAnimated: false,
    isUnlocked: true
  )

  skinDatabase[skAmethyst] = SkinData(
    name: "Amethyst",
    description: "Royal purple energy",
    primaryColor: Color(r: 150, g: 0, b: 255, a: 255),
    secondaryColor: Color(r: 120, g: 0, b: 200, a: 255),
    coreColor: Color(r: 220, g: 180, b: 255, a: 255),
    isAnimated: false,
    isUnlocked: true
  )

  skinDatabase[skGold] = SkinData(
    name: "Golden Aura",
    description: "Luxurious golden shine",
    primaryColor: Color(r: 255, g: 215, b: 0, a: 255),
    secondaryColor: Color(r: 255, g: 180, b: 0, a: 255),
    coreColor: Color(r: 255, g: 255, b: 200, a: 255),
    isAnimated: false,
    isUnlocked: true
  )

  skinDatabase[skIce] = SkinData(
    name: "Ice Crystal",
    description: "Frozen crystalline beauty",
    primaryColor: Color(r: 150, g: 220, b: 255, a: 255),
    secondaryColor: Color(r: 100, g: 180, b: 255, a: 255),
    coreColor: Color(r: 240, g: 250, b: 255, a: 255),
    isAnimated: false,
    isUnlocked: true
  )

  skinDatabase[skShadow] = SkinData(
    name: "Shadow Ops",
    description: "Stealth dark mode",
    primaryColor: Color(r: 60, g: 60, b: 80, a: 255),
    secondaryColor: Color(r: 40, g: 40, b: 60, a: 255),
    coreColor: Color(r: 180, g: 180, b: 200, a: 255),
    isAnimated: false,
    isUnlocked: true
  )

  skinDatabase[skRainbow] = SkinData(
    name: "Rainbow Wave",
    description: "Animated rainbow spectrum",
    primaryColor: Color(r: 255, g: 0, b: 0, a: 255),  # Base color, will animate
    secondaryColor: Color(r: 200, g: 0, b: 200, a: 255),
    coreColor: Color(r: 255, g: 255, b: 255, a: 255),
    isAnimated: true,
    isUnlocked: true
  )

  skinDatabase[skMatrix] = SkinData(
    name: "Matrix Code",
    description: "Green cascading data",
    primaryColor: Color(r: 0, g: 255, b: 0, a: 255),
    secondaryColor: Color(r: 0, g: 180, b: 0, a: 255),
    coreColor: Color(r: 180, g: 255, b: 180, a: 255),
    isAnimated: true,
    isUnlocked: true
  )

  skinDatabase[skVoid] = SkinData(
    name: "Void Walker",
    description: "Dark purple void energy",
    primaryColor: Color(r: 80, g: 0, b: 120, a: 255),
    secondaryColor: Color(r: 50, g: 0, b: 80, a: 255),
    coreColor: Color(r: 150, g: 100, b: 200, a: 255),
    isAnimated: true,
    isUnlocked: true
  )

  skinDatabase[skPlasma] = SkinData(
    name: "Plasma Core",
    description: "Electric blue-purple plasma",
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

proc isSkinUnlocked*(skinType: SkinType): bool =
  ## Check if a skin is unlocked
  return skinDatabase[skinType].isUnlocked

proc unlockSkin*(skinType: SkinType) =
  ## Unlock a skin for use
  skinDatabase[skinType].isUnlocked = true

proc getUnlockedSkins*(): seq[SkinType] =
  ## Get a list of all unlocked skins
  result = @[]
  for skinType in SkinType:
    if isSkinUnlocked(skinType):
      result.add(skinType)
