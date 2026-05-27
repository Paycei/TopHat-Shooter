## Particle Effects System for Player Shooting
## Defines customizable particle effects that appear when the player shoots

import raylib, math, random
import types, particle_pool, particle_types, localization

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
    name: t("particle_default"),
    description: t("particle_default_desc"),
    primaryColor: Color(r: 0, g: 200, b: 200, a: 255),
    secondaryColor: Color(r: 0, g: 150, b: 200, a: 255),
    particleCount: 8,
    particleSpeed: 100.0,
    useCustomShape: false,
    isAnimated: false,
    isUnlocked: true
  )

  particleSkinDatabase[pskFire] = ParticleSkinData(
    name: t("particle_fire"),
    description: t("particle_fire_desc"),
    primaryColor: Color(r: 255, g: 100, b: 0, a: 255),
    secondaryColor: Color(r: 255, g: 200, b: 0, a: 255),
    particleCount: 12,
    particleSpeed: 120.0,
    useCustomShape: false,
    isAnimated: true,
    isUnlocked: true
  )

  particleSkinDatabase[pskIce] = ParticleSkinData(
    name: t("particle_ice"),
    description: t("particle_ice_desc"),
    primaryColor: Color(r: 150, g: 220, b: 255, a: 255),
    secondaryColor: Color(r: 200, g: 240, b: 255, a: 255),
    particleCount: 10,
    particleSpeed: 80.0,
    useCustomShape: false,
    isAnimated: false,
    isUnlocked: true
  )
  particleSkinDatabase[pskToxic] = ParticleSkinData(
    name: t("particle_toxic"),
    description: t("particle_toxic_desc"),
    primaryColor: Color(r: 100, g: 255, b: 50, a: 255),
    secondaryColor: Color(r: 150, g: 200, b: 0, a: 255),
    particleCount: 15,
    particleSpeed: 60.0,
    useCustomShape: false,
    isAnimated: true,
    isUnlocked: true
  )

  particleSkinDatabase[pskPlasma] = ParticleSkinData(
    name: t("particle_plasma"),
    description: t("particle_plasma_desc"),
    primaryColor: Color(r: 150, g: 50, b: 255, a: 255),
    secondaryColor: Color(r: 100, g: 150, b: 255, a: 255),
    particleCount: 10,
    particleSpeed: 150.0,
    useCustomShape: false,
    isAnimated: true,
    isUnlocked: true
  )

  particleSkinDatabase[pskGold] = ParticleSkinData(
    name: t("particle_gold"),
    description: t("particle_gold_desc"),
    primaryColor: Color(r: 255, g: 215, b: 0, a: 255),
    secondaryColor: Color(r: 255, g: 250, b: 150, a: 255),
    particleCount: 14,
    particleSpeed: 90.0,
    useCustomShape: false,
    isAnimated: true,
    isUnlocked: true
  )

  particleSkinDatabase[pskShadow] = ParticleSkinData(
    name: t("particle_shadow"),
    description: t("particle_shadow_desc"),
    primaryColor: Color(r: 60, g: 40, b: 80, a: 255),
    secondaryColor: Color(r: 40, g: 20, b: 60, a: 255),
    particleCount: 12,
    particleSpeed: 70.0,
    useCustomShape: false,
    isAnimated: false,
    isUnlocked: true
  )
  particleSkinDatabase[pskRainbow] = ParticleSkinData(
    name: t("particle_rainbow"),
    description: t("particle_rainbow_desc"),
    primaryColor: Color(r: 255, g: 0, b: 255, a: 255),
    secondaryColor: Color(r: 0, g: 255, b: 255, a: 255),
    particleCount: 16,
    particleSpeed: 110.0,
    useCustomShape: false,
    isAnimated: true,
    isUnlocked: true
  )

  particleSkinDatabase[pskStars] = ParticleSkinData(
    name: t("particle_stars"),
    description: t("particle_stars_desc"),
    primaryColor: Color(r: 255, g: 255, b: 100, a: 255),
    secondaryColor: Color(r: 255, g: 255, b: 255, a: 255),
    particleCount: 8,
    particleSpeed: 85.0,
    useCustomShape: true,
    isAnimated: true,
    isUnlocked: true
  )

  particleSkinDatabase[pskHearts] = ParticleSkinData(
    name: t("particle_hearts"),
    description: t("particle_hearts_desc"),
    primaryColor: Color(r: 255, g: 100, b: 150, a: 255),
    secondaryColor: Color(r: 255, g: 150, b: 200, a: 255),
    particleCount: 6,
    particleSpeed: 75.0,
    useCustomShape: true,
    isAnimated: false,
    isUnlocked: true
  )

  particleSkinDatabase[pskLightning] = ParticleSkinData(
    name: t("particle_lightning"),
    description: t("particle_lightning_desc"),
    primaryColor: Color(r: 255, g: 255, b: 0, a: 255),
    secondaryColor: Color(r: 255, g: 255, b: 200, a: 255),
    particleCount: 10,
    particleSpeed: 180.0,
    useCustomShape: false,
    isAnimated: true,
    isUnlocked: true
  )
  particleSkinDatabase[pskVoid] = ParticleSkinData(
    name: t("particle_void"),
    description: t("particle_void_desc"),
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

proc shootingParticleStyle(skinType: ParticleSkinType, index: int): ParticleStyle =
  case skinType
  of pskFire, pskGold, pskLightning:
    if index mod 3 == 0: psSoft else: psSpark
  of pskIce, pskStars:
    if index mod 2 == 0: psShard else: psSoft
  of pskToxic, pskShadow, pskVoid, pskHearts:
    if index mod 3 == 0: psSoft else: psEmber
  else:
    if index mod 4 == 0: psSpark else: psSoft

proc shootingParticleLifetime(skinType: ParticleSkinType, style: ParticleStyle): float32 =
  result =
    case style
    of psSpark: 0.10'f32 + rand(0.10).float32
    of psShard: 0.16'f32 + rand(0.12).float32
    of psEmber: 0.22'f32 + rand(0.18).float32
    of psSoft: 0.16'f32 + rand(0.14).float32

  case skinType
  of pskHearts, pskStars, pskVoid:
    result += 0.08'f32
  of pskLightning:
    result *= 0.85'f32
  else:
    discard

proc shootingParticleGravity(skinType: ParticleSkinType, style: ParticleStyle): float32 =
  case skinType
  of pskFire, pskGold:
    if style == psSpark: 0.0 else: 20.0'f32 + rand(35.0).float32
  of pskToxic:
    -25.0'f32 - rand(35.0).float32
  of pskShadow, pskVoid:
    -10.0'f32 - rand(20.0).float32
  of pskHearts:
    -30.0'f32 - rand(25.0).float32
  of pskIce, pskStars:
    8.0'f32 + rand(18.0).float32
  else:
    if style == psEmber: 10.0'f32 + rand(20.0).float32 else: 0.0'f32

proc shootingParticleGlow(skinType: ParticleSkinType): float32 =
  case skinType
  of pskLightning, pskPlasma, pskVoid:
    1.35'f32
  of pskGold, pskStars, pskFire:
    1.1'f32
  else:
    0.9'f32

proc spawnShootingParticles*(pool: ParticlePool, x, y: float32, direction: Vector2f,
                             skinType: ParticleSkinType, time: float32) =
  ## Spawn particles when player shoots, using the selected particle skin
  let skin = particleSkinDatabase[skinType]
  let (primaryColor, secondaryColor) = getParticleSkinColors(skinType, time)
  let shootDir =
    if direction.length() > 0.01'f32: direction.normalize()
    else: newVector2f(1.0, 0.0)
  let sideDir = newVector2f(-shootDir.y, shootDir.x)
  let boostedCount = scaledParticleBurstCount(pool, skin.particleCount + max(3, skin.particleCount div 3))

  discard pool.acquireParticleDetailed(
    x, y,
    shootDir.x * (12.0'f32 + rand(18.0).float32),
    shootDir.y * (12.0'f32 + rand(18.0).float32),
    secondaryColor,
    lifetime = 0.10'f32 + rand(0.07).float32,
    startSize = 6.0'f32 + rand(2.4).float32,
    endSize = 0.35'f32,
    drag = 6.0'f32,
    glow = shootingParticleGlow(skinType) + 0.6'f32,
    style = psSoft,
    layer = plForeground
  )

  for i in 0..<boostedCount:
    let useSecondary = rand(1.0) < 0.4
    let color = if useSecondary: secondaryColor else: primaryColor
    let speedVariation = 0.86'f32 + rand(0.6).float32
    let speed = skin.particleSpeed * speedVariation
    let style = shootingParticleStyle(skinType, i)
    let forwardBias = 0.70'f32 + rand(0.55).float32
    let lateralBias = (-0.70'f32 + rand(1.4).float32)
    let velocity = (shootDir * (speed * forwardBias) + sideDir * (speed * lateralBias * 0.45'f32))
    let spawnDistance = rand(3.0).float32
    let spawnX = x + shootDir.x * spawnDistance + sideDir.x * lateralBias * 1.5'f32
    let spawnY = y + shootDir.y * spawnDistance + sideDir.y * lateralBias * 1.5'f32
    let startSize =
      case style
      of psSpark: 1.8'f32 + rand(1.1).float32
      of psShard: 2.3'f32 + rand(1.4).float32
      of psEmber: 2.6'f32 + rand(1.6).float32
      of psSoft: 3.0'f32 + rand(1.9).float32

    discard pool.acquireParticleDetailed(
      spawnX, spawnY,
      velocity.x,
      velocity.y,
      color,
      lifetime = shootingParticleLifetime(skinType, style),
      startSize = startSize,
      endSize = 0.2'f32,
      drag = 4.0'f32 + rand(3.0).float32,
      gravity = shootingParticleGravity(skinType, style),
      glow = shootingParticleGlow(skinType) + 0.15'f32,
      style = style,
      layer = plForeground,
      rotation = rand(360.0).float32,
      spin = (-220.0 + rand(440.0)).float32
    )

  case skinType
  of pskLightning:
    let lightningCount = scaledParticleBurstCount(pool, 3)
    for i in 0..<lightningCount:
      let angle = i.float32 * 0.18'f32 - 0.18'f32 + rand(0.1).float32
      let boltDir = newVector2f(
        shootDir.x * cos(angle) - shootDir.y * sin(angle),
        shootDir.x * sin(angle) + shootDir.y * cos(angle)
      )
      let speed = skin.particleSpeed * (1.2'f32 + rand(0.35).float32)
      discard pool.acquireParticleDetailed(
        x, y, boltDir.x * speed, boltDir.y * speed, primaryColor,
        lifetime = 0.08'f32 + rand(0.06).float32,
        startSize = 2.2'f32 + rand(0.9).float32,
        endSize = 0.1'f32,
        drag = 3.0'f32,
        glow = 1.8'f32,
        style = psSpark,
        layer = plForeground,
        rotation = arctan2(boltDir.y, boltDir.x) * 180.0'f32 / PI.float32
      )
  of pskHearts, pskStars:
    let orbitCount = scaledParticleBurstCount(pool, skin.particleCount div 2)
    for i in 0..<orbitCount:
      let angle = i.float32 * 0.18'f32 - 0.18'f32
      let orbitDir = newVector2f(
        shootDir.x * cos(angle) - shootDir.y * sin(angle),
        shootDir.x * sin(angle) + shootDir.y * cos(angle)
      )
      let speed = skin.particleSpeed * (0.45'f32 + rand(0.18).float32)
      discard pool.acquireParticleDetailed(
        x, y, orbitDir.x * speed, orbitDir.y * speed, primaryColor,
        lifetime = 0.24'f32 + rand(0.16).float32,
        startSize = 2.8'f32 + rand(1.2).float32,
        endSize = 0.2'f32,
        drag = 5.0'f32,
        gravity = if skinType == pskHearts: -28.0'f32 else: 10.0'f32,
        glow = 1.1'f32,
        style = if skinType == pskStars: psShard else: psSoft,
        layer = plForeground,
        rotation = rand(360.0).float32,
        spin = (-160.0 + rand(320.0)).float32
      )
  of pskVoid:
    let swirlCount = scaledParticleBurstCount(pool, 4)
    for i in 0..<swirlCount:
      let angle = i.float32 * 0.25'f32 - 0.375'f32
      let swirlDir = newVector2f(
        shootDir.x * cos(angle) - shootDir.y * sin(angle),
        shootDir.x * sin(angle) + shootDir.y * cos(angle)
      )
      let speed = skin.particleSpeed * (0.22'f32 + rand(0.12).float32)
      discard pool.acquireParticleDetailed(
        x, y, swirlDir.x * speed, swirlDir.y * speed, secondaryColor,
        lifetime = 0.26'f32 + rand(0.12).float32,
        startSize = 3.2'f32 + rand(1.2).float32,
        endSize = 0.2'f32,
        drag = 7.0'f32,
        gravity = -18.0'f32,
        glow = 1.45'f32,
        style = psEmber,
        layer = plForeground,
        rotation = rand(360.0).float32,
        spin = (-200.0 + rand(400.0)).float32
      )
  else:
    discard
