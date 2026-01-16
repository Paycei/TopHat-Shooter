## Particle Effects System for Player Shooting
## Defines customizable particle effects that appear when the player shoots

import raylib, types, math, particle_pool, random

type
  ParticleSkinType* = enum
    pskDefault,      # Standard cyan particles
    pskFire,         # Burning orange/red flames
    pskIce,          # Frozen blue/white crystals
    pskToxic,        # Toxic green/yellow gas
    pskPlasma,       # Electric purple/blue energy
    pskGold,         # Golden sparkles
    pskShadow,       # Dark purple smoke
    pskRainbow,      # Multi-colored confetti
    pskStars,        # Star-shaped particles
    pskHearts,       # Heart-shaped particles
    pskLightning,    # Electric yellow sparks
    pskVoid,         # Black hole dark energy

  ParticleSkinData* = object
    name*: string
    description*: string
    primaryColor*: Color
    secondaryColor*: Color
    particleCount*: int        # How many particles to spawn
    particleSpeed*: float32    # Speed of particles
    useCustomShape*: bool      # Whether to use custom shape rendering
    isAnimated*: bool          # Whether colors animate over time
    isUnlocked*: bool          # Whether player has unlocked this

# Global particle skin database
var particleSkinDatabase*: array[ParticleSkinType, ParticleSkinData]

proc initializeParticleSkins*() =
  ## Initialize all available particle skins with their data
  particleSkinDatabase[pskDefault] = ParticleSkinData(
    name: "System Default",
    description: "Standard cyan energy",
    primaryColor: Color(r: 0, g: 200, b: 200, a: 255),
    secondaryColor: Color(r: 0, g: 150, b: 200, a: 255),
    particleCount: 8,
    particleSpeed: 100.0,
    useCustomShape: false,
    isAnimated: false,
    isUnlocked: true
  )

  particleSkinDatabase[pskFire] = ParticleSkinData(
    name: "Flame Burst",
    description: "Burning fire particles",
    primaryColor: Color(r: 255, g: 100, b: 0, a: 255),
    secondaryColor: Color(r: 255, g: 200, b: 0, a: 255),
    particleCount: 12,
    particleSpeed: 120.0,
    useCustomShape: false,
    isAnimated: true,
    isUnlocked: true
  )

  particleSkinDatabase[pskIce] = ParticleSkinData(
    name: "Frost Shards",
    description: "Icy crystalline fragments",
    primaryColor: Color(r: 150, g: 220, b: 255, a: 255),
    secondaryColor: Color(r: 200, g: 240, b: 255, a: 255),
    particleCount: 10,
    particleSpeed: 80.0,
    useCustomShape: false,
    isAnimated: false,
    isUnlocked: true
  )
  particleSkinDatabase[pskToxic] = ParticleSkinData(
    name: "Toxic Cloud",
    description: "Poisonous green gas",
    primaryColor: Color(r: 100, g: 255, b: 50, a: 255),
    secondaryColor: Color(r: 150, g: 200, b: 0, a: 255),
    particleCount: 15,
    particleSpeed: 60.0,
    useCustomShape: false,
    isAnimated: true,
    isUnlocked: true
  )

  particleSkinDatabase[pskPlasma] = ParticleSkinData(
    name: "Plasma Burst",
    description: "Electric purple energy",
    primaryColor: Color(r: 150, g: 50, b: 255, a: 255),
    secondaryColor: Color(r: 100, g: 150, b: 255, a: 255),
    particleCount: 10,
    particleSpeed: 150.0,
    useCustomShape: false,
    isAnimated: true,
    isUnlocked: true
  )

  particleSkinDatabase[pskGold] = ParticleSkinData(
    name: "Golden Sparkle",
    description: "Shimmering gold dust",
    primaryColor: Color(r: 255, g: 215, b: 0, a: 255),
    secondaryColor: Color(r: 255, g: 250, b: 150, a: 255),
    particleCount: 14,
    particleSpeed: 90.0,
    useCustomShape: false,
    isAnimated: true,
    isUnlocked: true
  )

  particleSkinDatabase[pskShadow] = ParticleSkinData(
    name: "Dark Smoke",
    description: "Mysterious shadow trails",
    primaryColor: Color(r: 60, g: 40, b: 80, a: 255),
    secondaryColor: Color(r: 40, g: 20, b: 60, a: 255),
    particleCount: 12,
    particleSpeed: 70.0,
    useCustomShape: false,
    isAnimated: false,
    isUnlocked: true
  )
  particleSkinDatabase[pskRainbow] = ParticleSkinData(
    name: "Rainbow Burst",
    description: "Colorful confetti spray",
    primaryColor: Color(r: 255, g: 0, b: 255, a: 255),
    secondaryColor: Color(r: 0, g: 255, b: 255, a: 255),
    particleCount: 16,
    particleSpeed: 110.0,
    useCustomShape: false,
    isAnimated: true,
    isUnlocked: true
  )

  particleSkinDatabase[pskStars] = ParticleSkinData(
    name: "Star Trail",
    description: "Twinkling star particles",
    primaryColor: Color(r: 255, g: 255, b: 100, a: 255),
    secondaryColor: Color(r: 255, g: 255, b: 255, a: 255),
    particleCount: 8,
    particleSpeed: 85.0,
    useCustomShape: true,
    isAnimated: true,
    isUnlocked: true
  )

  particleSkinDatabase[pskHearts] = ParticleSkinData(
    name: "Love Burst",
    description: "Cute heart particles",
    primaryColor: Color(r: 255, g: 100, b: 150, a: 255),
    secondaryColor: Color(r: 255, g: 150, b: 200, a: 255),
    particleCount: 6,
    particleSpeed: 75.0,
    useCustomShape: true,
    isAnimated: false,
    isUnlocked: true
  )

  particleSkinDatabase[pskLightning] = ParticleSkinData(
    name: "Lightning Spark",
    description: "Electric yellow bolts",
    primaryColor: Color(r: 255, g: 255, b: 0, a: 255),
    secondaryColor: Color(r: 255, g: 255, b: 200, a: 255),
    particleCount: 10,
    particleSpeed: 180.0,
    useCustomShape: false,
    isAnimated: true,
    isUnlocked: true
  )
  particleSkinDatabase[pskVoid] = ParticleSkinData(
    name: "Void Energy",
    description: "Dark dimensional rifts",
    primaryColor: Color(r: 20, g: 0, b: 40, a: 255),
    secondaryColor: Color(r: 80, g: 40, b: 120, a: 255),
    particleCount: 12,
    particleSpeed: 95.0,
    useCustomShape: false,
    isAnimated: true,
    isUnlocked: true
  )

proc getParticleSkinColors*(skinType: ParticleSkinType, time: float32): tuple[primary, secondary: Color] =
  ## Get the colors for particle skin, applying animations if needed
  let skin = particleSkinDatabase[skinType]
  
  if not skin.isAnimated:
    return (skin.primaryColor, skin.secondaryColor)
  
  # Apply time-based animations for animated skins
  case skinType
  of pskFire:
    # Flickering fire effect
    let flicker = sin(time * 10.0) * 0.15 + 0.85
    let r = uint8(255.0 * flicker)
    let g = uint8((100.0 + 100.0 * sin(time * 8.0)) * flicker)
    return (
      Color(r: r, g: g, b: 0, a: 255),
      Color(r: 255, g: uint8(200 + 55 * sin(time * 12.0)), b: 0, a: 255)
    )
  of pskToxic:
    # Pulsing toxic glow
    let pulse = sin(time * 3.0) * 0.5 + 0.5
    let g = uint8(200 + pulse * 55)
    return (
      Color(r: uint8(100 - pulse * 50), g: g, b: 50, a: 255),
      Color(r: 150, g: uint8(150 + pulse * 50), b: 0, a: 255)
    )
  of pskPlasma:
    # Electric plasma oscillation
    let oscillation = sin(time * 4.0) * 0.5 + 0.5
    return (
      Color(r: uint8(150 - oscillation * 50), g: 50, b: uint8(200 + oscillation * 55), a: 255),
      Color(r: 100, g: uint8(150 + oscillation * 105), b: 255, a: 255)
    )
  of pskGold:
    # Shimmering gold sparkle
    let shimmer = sin(time * 6.0) * 0.5 + 0.5
    return (
      Color(r: 255, g: uint8(215 - shimmer * 40), b: 0, a: 255),
      Color(r: 255, g: uint8(200 + shimmer * 50), b: uint8(150 * shimmer), a: 255)
    )
  of pskRainbow:
    # Cycling rainbow spectrum
    let hue = (time * 1.5) mod 1.0
    let r1 = uint8((sin(hue * PI * 2.0) * 0.5 + 0.5) * 255)
    let g1 = uint8((sin((hue + 0.333) * PI * 2.0) * 0.5 + 0.5) * 255)
    let b1 = uint8((sin((hue + 0.666) * PI * 2.0) * 0.5 + 0.5) * 255)
    let r2 = uint8((sin((hue + 0.5) * PI * 2.0) * 0.5 + 0.5) * 255)
    let g2 = uint8((sin((hue + 0.833) * PI * 2.0) * 0.5 + 0.5) * 255)
    let b2 = uint8((sin((hue + 0.166) * PI * 2.0) * 0.5 + 0.5) * 255)
    return (
      Color(r: r1, g: g1, b: b1, a: 255),
      Color(r: r2, g: g2, b: b2, a: 255)
    )
  of pskStars:
    # Twinkling stars
    let twinkle = sin(time * 5.0) * 0.3 + 0.7
    return (
      Color(r: 255, g: 255, b: uint8(100 + twinkle * 155), a: 255),
      Color(r: 255, g: 255, b: 255, a: uint8(200 + twinkle * 55))
    )
  of pskLightning:
    # Crackling electricity
    let crackle = (rand(1.0) * 0.3) + (sin(time * 8.0) * 0.35 + 0.65)
    return (
      Color(r: 255, g: 255, b: 0, a: uint8(200 + crackle * 55)),
      Color(r: 255, g: 255, b: uint8(200 * crackle), a: 255)
    )
  of pskVoid:
    # Swirling void energy
    let swirl = sin(time * 2.5) * 0.5 + 0.5
    return (
      Color(r: uint8(20 + swirl * 60), g: 0, b: uint8(40 + swirl * 80), a: 255),
      Color(r: uint8(80 + swirl * 40), g: uint8(40 * swirl), b: uint8(120 + swirl * 60), a: 255)
    )
  else:
    # Fallback to static colors
    return (skin.primaryColor, skin.secondaryColor)

proc getParticleSkinData*(skinType: ParticleSkinType): ParticleSkinData =
  ## Get the data for a specific particle skin
  return particleSkinDatabase[skinType]

proc getParticleSkinName*(skinType: ParticleSkinType): string =
  ## Get the display name of a particle skin
  return particleSkinDatabase[skinType].name

proc getParticleSkinDescription*(skinType: ParticleSkinType): string =
  ## Get the description of a particle skin
  return particleSkinDatabase[skinType].description

proc isParticleSkinUnlocked*(skinType: ParticleSkinType): bool =
  ## Check if a particle skin is unlocked
  return particleSkinDatabase[skinType].isUnlocked

proc unlockParticleSkin*(skinType: ParticleSkinType) =
  ## Unlock a particle skin for use
  particleSkinDatabase[skinType].isUnlocked = true

proc getUnlockedParticleSkins*(): seq[ParticleSkinType] =
  ## Get a list of all unlocked particle skins
  result = @[]
  for skinType in ParticleSkinType:
    if isParticleSkinUnlocked(skinType):
      result.add(skinType)

proc spawnShootingParticles*(pool: ParticlePool, x, y: float32, skinType: ParticleSkinType, time: float32) =
  ## Spawn particles when player shoots, using the selected particle skin
  let skin = particleSkinDatabase[skinType]
  let (primaryColor, secondaryColor) = getParticleSkinColors(skinType, time)
  
  # Spawn particles in random directions
  for i in 0..<skin.particleCount:
    # Determine which color to use (mix of primary and secondary)
    let useSecondary = rand(1.0) < 0.4
    let color = if useSecondary: secondaryColor else: primaryColor
    
    # Add slight speed variation
    let speedVariation = 0.8 + rand(0.4)
    let speed = skin.particleSpeed * speedVariation
    
    discard pool.acquireParticle(x, y, color, speed)
  
  # Special effects for certain particle types
  case skinType
  of pskLightning:
    # Extra fast sparks for lightning
    for i in 0..<3:
      discard pool.acquireParticle(x, y, primaryColor, skin.particleSpeed * 1.5)
  of pskHearts, pskStars:
    # Slower, more deliberate particles
    for i in 0..<skin.particleCount div 2:
      discard pool.acquireParticle(x, y, primaryColor, skin.particleSpeed * 0.6)
  of pskVoid:
    # Inward-pulling effect (spawn some slower particles)
    for i in 0..<4:
      discard pool.acquireParticle(x, y, secondaryColor, skin.particleSpeed * 0.3)
  else:
    discard  # No special effects for other types
