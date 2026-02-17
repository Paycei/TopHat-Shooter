import raylib, math, random, os, streams, localization

type
  SoundType* = enum
    stShoot, stEnemyHit, stEnemyDeath, stPlayerHit, stCoinPickup, stPowerUp,
    stBossSpawn, stExplosion, stWallPlace, stTeleport, stMenuNav, stMenuSelect,
    stWaveComplete, stShield, stGameOver

  MusicTrack* = enum
    mtMenu, mtWave, mtPowerUp, mtBoss

  # Progress callback: proc(progress: float32, message: string)
  AssetGenerationCallback* = proc(progress: float32, message: string) {.closure.}

  SoundSystem* = ref object
    enabled*: bool
    masterVolume*: float32
    musicVolume*: float32
    initialized: bool
    cachedSounds: array[SoundType, Sound]
    soundsGenerated: bool
    cachedMusic: array[MusicTrack, Music]
    musicGenerated: array[MusicTrack, bool]
    currentTrack: MusicTrack
    trackPlaying: bool

var globalSoundSystem*: SoundSystem

# CACHE MANAGEMENT
proc getCacheDir(): string =
  result = getTempDir() / "shooteros_music_cache"
  if not dirExists(result):
    createDir(result)
  # Delete old cache folder if it exists
  let oldCacheDir = getTempDir() / "tophat_sound_cache"
  if dirExists(oldCacheDir):
    removeDir(oldCacheDir)

proc getSoundCacheFile(soundType: SoundType): string =
  let cacheDir = getCacheDir()
  let soundName = case soundType
    of stShoot: "shoot"
    of stEnemyHit: "hit"
    of stEnemyDeath: "death"
    of stPlayerHit: "playerhit"
    of stCoinPickup: "coin"
    of stPowerUp: "powerup"
    of stBossSpawn: "boss"
    of stExplosion: "explosion"
    of stWallPlace: "wall"
    of stTeleport: "teleport"
    of stMenuNav: "menunav"
    of stMenuSelect: "menuselect"
    of stWaveComplete: "wavecomplete"
    of stShield: "shield"
    of stGameOver: "gameover"
  result = cacheDir / (soundName & ".wav")

proc getMusicCacheFile(track: MusicTrack): string =
  let cacheDir = getCacheDir()
  let trackName = case track
    of mtMenu: "menu"
    of mtWave: "wave"
    of mtPowerUp: "powerup_music"
    of mtBoss: "boss_music"
  result = cacheDir / (trackName & ".wav")

proc isSoundCached(soundType: SoundType): bool =
  fileExists(getSoundCacheFile(soundType))

proc isMusicCached(track: MusicTrack): bool =
  fileExists(getMusicCacheFile(track))

proc countCachedAssets(): tuple[sounds: int, music: int, total: int] =
  result.sounds = 0
  result.music = 0
  for st in SoundType:
    if isSoundCached(st):
      inc result.sounds
  for mt in MusicTrack:
    if isMusicCached(mt):
      inc result.music
  result.total = result.sounds + result.music

# CORE AUDIO UTILITIES
proc applyADSR(progress: float32, attack, decay, sustain, release: float32): float32 {.inline.} =
  if progress < attack:
    return progress / attack
  elif progress < attack + decay:
    let decayProgress = (progress - attack) / decay
    return 1.0 - (1.0 - sustain) * decayProgress
  elif progress < 1.0 - release:
    return sustain
  else:
    let releaseProgress = (progress - (1.0 - release)) / release
    return sustain * (1.0 - releaseProgress)

proc writeWavFile(filename: string, samples: seq[int16], sampleRate: uint32) =
  var stream: FileStream = nil
  try:
    stream = newFileStream(filename, fmWrite)
    if stream == nil:
      raise newException(IOError, "Could not create WAV file: " & filename)
    
    let numSamples = samples.len
    let dataSize = numSamples * 2
    let fileSize = 36 + dataSize
    
    stream.write("RIFF")
    stream.write(uint32(fileSize))
    stream.write("WAVE")
    stream.write("fmt ")
    stream.write(uint32(16))
    stream.write(uint16(1))
    stream.write(uint16(1))
    stream.write(uint32(sampleRate))
    stream.write(uint32(sampleRate * 2))
    stream.write(uint16(2))
    stream.write(uint16(16))
    stream.write("data")
    stream.write(uint32(dataSize))
    
    for sample in samples:
      stream.write(sample)
  finally:
    if not stream.isNil:
      stream.close()

proc createLaserShoot(filename: string): Sound =
  # High-tech laser with complex modulation
  let sampleRate: uint32 = 44100
  let duration = 0.18
  let frameCount = int(sampleRate.float32 * duration)
  var samples = newSeq[int16](frameCount)
  
  for i in 0..<frameCount:
    let t = i.float32 / sampleRate.float32
    let progress = t / duration
    
    # Main carrier - exponential pitch sweep
    let carrierFreq = 2200.0 * exp(-progress * 6.0) + 250.0
    
    # FM synthesis for laser character
    let modulator = sin(2.0 * PI * 8.0 * carrierFreq * t) * 0.3
    let carrier = sin(2.0 * PI * carrierFreq * t + modulator)
    
    # Harmonics for brightness
    let harmonic2 = sin(2.0 * PI * carrierFreq * 2.0 * t) * 0.25
    let harmonic3 = sin(2.0 * PI * carrierFreq * 3.0 * t) * 0.12
    
    # Sub layer for depth
    let sub = sin(2.0 * PI * carrierFreq * 0.5 * t) * 0.2
    
    # Noise layer for texture
    let noise = rand(-1.0..1.0) * 0.08 * exp(-progress * 20.0)
    
    # Sharp attack, fast decay
    let envelope = applyADSR(progress, 0.01, 0.08, 0.25, 0.61)
    
    let value = (carrier * 0.4 + harmonic2 + harmonic3 + sub + noise) * envelope
    samples[i] = int16(clamp(value * 32767.0 * 0.42, -32767.0, 32767.0))
  
  writeWavFile(filename, samples, sampleRate)
  result = loadSound(filename)

proc createImpactHit(filename: string): Sound =
  # Heavy, satisfying impact with multiple layers
  let sampleRate: uint32 = 44100
  let duration = 0.22
  let frameCount = int(sampleRate.float32 * duration)
  var samples = newSeq[int16](frameCount)
  
  for i in 0..<frameCount:
    let t = i.float32 / sampleRate.float32
    let progress = t / duration
    
    # Layer 1: Deep thump - felt impact
    let thumpFreq = 80.0 * exp(-progress * 18.0)
    let thump = sin(2.0 * PI * thumpFreq * t) * 0.55
    
    # Layer 2: Body - mid frequency punch
    let bodyFreq = 280.0 * exp(-progress * 12.0)
    let body = sin(2.0 * PI * bodyFreq * t) * 0.35
    
    # Layer 3: Crunch - upper mid definition
    let crunchFreq = 600.0 * exp(-progress * 10.0)
    let crunch = sin(2.0 * PI * crunchFreq * t) * 0.25
    
    # Layer 4: Initial click - attack transient
    let click = if progress < 0.03:
      sin(2.0 * PI * 2500.0 * t) * (1.0 - progress / 0.03) * 0.5
    else:
      0.0
    
    # Layer 5: Noise burst - texture
    let noiseBurst = if progress < 0.08:
      rand(-1.0..1.0) * (1.0 - progress / 0.08) * 0.35
    else:
      0.0
    
    # Layer 6: Sustained noise - tail
    let noiseTail = rand(-1.0..1.0) * 0.12 * exp(-progress * 25.0)
    
    # Layer 7: Metallic ring - adds character
    let ring = sin(2.0 * PI * 1800.0 * t) * 0.15 * exp(-progress * 15.0)
    
    # Fast decay envelope
    let envelope = exp(-progress * 16.0)
    
    let value = (thump + body + crunch + click + noiseBurst + noiseTail + ring) * envelope
    samples[i] = int16(clamp(value * 32767.0 * 0.75, -32767.0, 32767.0))
  
  writeWavFile(filename, samples, sampleRate)
  result = loadSound(filename)

proc createEnemyDeath(filename: string): Sound =
  # Dramatic, satisfying enemy destruction
  let sampleRate: uint32 = 44100
  let duration = 0.65
  let frameCount = int(sampleRate.float32 * duration)
  var samples = newSeq[int16](frameCount)
  
  for i in 0..<frameCount:
    let t = i.float32 / sampleRate.float32
    let progress = t / duration
    
    # Main sweep - dramatic downward pitch
    let mainFreq = 1100.0 * exp(-progress * 5.0) + 35.0
    let mainTone = sin(2.0 * PI * mainFreq * t) * 0.45
    
    # Sub octave - adds weight
    let subOctave = sin(2.0 * PI * mainFreq * 0.5 * t) * 0.35
    
    # Perfect fifth - harmonic richness
    let fifth = sin(2.0 * PI * mainFreq * 1.5 * t) * 0.22
    
    # Upper harmonic - brightness
    let upper = sin(2.0 * PI * mainFreq * 2.0 * t) * 0.15
    
    # Initial impact burst
    let impactNoise = if progress < 0.12:
      rand(-1.0..1.0) * (1.0 - progress / 0.12) * 0.4
    else:
      0.0
    
    # Crackling decay
    let crackle = if progress >= 0.12 and progress < 0.45:
      rand(-1.0..1.0) * ((0.45 - progress) / 0.33) * 0.2
    else:
      0.0
    
    # Rumble layer
    let rumble = sin(2.0 * PI * 40.0 * t) * 0.25
    
    # Dissonant warble for destruction feel
    let warble = sin(2.0 * PI * (mainFreq * 1.15) * t) * 0.12
    
    # Multi-stage envelope
    let attackEnv = if progress < 0.05: progress / 0.05 else: 1.0
    let mainEnv = exp(-progress * 3.0)
    
    let value = (mainTone + subOctave + fifth + upper + impactNoise +
                 crackle + rumble * mainEnv + warble) * attackEnv * mainEnv
    
    samples[i] = int16(clamp(value * 32767.0 * 0.7, -32767.0, 32767.0))
  
  writeWavFile(filename, samples, sampleRate)
  result = loadSound(filename)

proc createPlayerHit(filename: string): Sound =
  # Intense, attention-grabbing damage sound
  let sampleRate: uint32 = 44100
  let duration = 0.35
  let frameCount = int(sampleRate.float32 * duration)
  var samples = newSeq[int16](frameCount)
  
  for i in 0..<frameCount:
    let t = i.float32 / sampleRate.float32
    let progress = t / duration
    
    # Deep pain tone - low frequency
    let painFreq = 145.0 + sin(progress * PI) * 25.0
    let pain = sin(2.0 * PI * painFreq * t) * 0.42
    
    # Vibrating/shaking effect - distress signal
    let shakeRate = 22.0 + progress * 8.0
    let shake = sin(2.0 * PI * shakeRate * t) * 0.35
    
    # Impact layer - sharp attack
    let impactFreq = 550.0 * exp(-progress * 20.0)
    let impact = sin(2.0 * PI * impactFreq * t) * 0.35
    
    # High frequency alarm - alerts player
    let alarmFreq = 1200.0 + sin(progress * PI * 3.0) * 200.0
    let alarm = if progress < 0.2:
      sin(2.0 * PI * alarmFreq * t) * (1.0 - progress / 0.2) * 0.3
    else:
      0.0
    
    # Harsh noise burst - damage texture
    let noiseBurst = if progress < 0.15:
      rand(-1.0..1.0) * (1.0 - progress / 0.15) * 0.4
    else:
      0.0
    
    # Sustained noise - aftermath
    let sustainedNoise = rand(-1.0..1.0) * 0.15 * exp(-progress * 10.0)
    
    # Distortion effect - damage intensity
    let distortionAmount = 1.2 + progress * 0.3
    
    # Multi-stage envelope
    let mainEnvelope = exp(-progress * 7.0)
    let shakeEnvelope = exp(-progress * 4.0)
    
    let rawValue = (
      pain * (1.0 + shake * shakeEnvelope * 0.4) * mainEnvelope +
      impact * mainEnvelope +
      alarm +
      noiseBurst +
      sustainedNoise
    )
    
    # Apply soft clipping distortion
    let distorted = tanh(rawValue * distortionAmount) / distortionAmount
    
    samples[i] = int16(clamp(distorted * 32767.0 * 0.65, -32767.0, 32767.0))
  
  writeWavFile(filename, samples, sampleRate)
  result = loadSound(filename)

proc createCoinPickup(filename: string): Sound =
  # Pleasant, rewarding coin collection sound
  let sampleRate: uint32 = 44100
  let duration = 0.32
  let frameCount = int(sampleRate.float32 * duration)
  var samples = newSeq[int16](frameCount)
  
  # Cheerful ascending major arpeggio
  let notes = @[
    (freq: 523.25'f32, start: 0.0, length: 0.10),      # C5
    (freq: 659.25'f32, start: 0.08, length: 0.10),     # E5
    (freq: 783.99'f32, start: 0.16, length: 0.16)      # G5 - held slightly longer
  ]
  
  for i in 0..<frameCount:
    let t = i.float32 / sampleRate.float32
    var value = 0.0
    
    for note in notes:
      if t >= note.start and t < note.start + note.length:
        let noteTime = t - note.start
        let noteProgress = noteTime / note.length
        
        # Bright bell-like timbre
        let fundamental = sin(2.0 * PI * note.freq * t) * 0.48
        let harmonic2 = sin(2.0 * PI * note.freq * 2.0 * t) * 0.20
        let harmonic3 = sin(2.0 * PI * note.freq * 3.0 * t) * 0.12
        let harmonic4 = sin(2.0 * PI * note.freq * 4.0 * t) * 0.08
        
        # Shimmer effect
        let shimmer = sin(2.0 * PI * note.freq * 5.0 * t) * 0.06
        
        # Slight pitch bend for character
        let bendAmount = 1.0 + (noteProgress * 0.015)
        
        # Quick attack, sustain, gentle release
        let attack = if noteProgress < 0.06: noteProgress / 0.06 else: 1.0
        let release = if noteProgress > 0.65:
          (1.0 - (noteProgress - 0.65) / 0.35) * 0.6 + 0.4
        else:
          1.0
        
        let envelope = attack * release
        
        let noteTone = (fundamental + harmonic2 + harmonic3 + harmonic4 + shimmer) * bendAmount
        value += noteTone * envelope
    
    # Add sparkle for "magical" coin feel
    let globalProgress = t / duration
    let sparkle = if globalProgress > 0.15 and globalProgress < 0.5:
      sin(2.0 * PI * 2800.0 * t) * ((0.5 - abs(globalProgress - 0.32)) * 5.0) * 0.08
    else:
      0.0
    
    samples[i] = int16(clamp((value + sparkle) * 32767.0 * 0.48, -32767.0, 32767.0))
  
  writeWavFile(filename, samples, sampleRate)
  result = loadSound(filename)

proc createPowerUp(filename: string): Sound =
  # Exciting, rewarding power-up with rising energy
  let sampleRate: uint32 = 44100
  let duration = 0.75
  let frameCount = int(sampleRate.float32 * duration)
  var samples = newSeq[int16](frameCount)
  
  for i in 0..<frameCount:
    let t = i.float32 / sampleRate.float32
    let progress = t / duration
    
    # Rising base pitch with acceleration
    let pitchCurve = progress + progress * progress * 0.5
    let basePitch = 350.0 + pitchCurve * 450.0
    
    # Rich vibrato for shimmer
    let vibrato = 1.0 + sin(2.0 * PI * 7.0 * t) * 0.02
    
    # Main tone layers
    let fundamental = sin(2.0 * PI * basePitch * vibrato * t) * 0.38
    let third = sin(2.0 * PI * basePitch * 1.25992 * vibrato * t) * 0.28  # Major third
    let fifth = sin(2.0 * PI * basePitch * 1.4983 * vibrato * t) * 0.26   # Perfect fifth
    let octave = sin(2.0 * PI * basePitch * 2.0 * vibrato * t) * 0.18     # Octave
    
    # Sparkle layer - high frequency magic
    let sparkleFreq = 1600.0 + progress * 800.0
    let sparkleVibrato = 1.0 + sin(2.0 * PI * 11.0 * t) * 0.025
    let sparkle = if progress > 0.25:
      sin(2.0 * PI * sparkleFreq * sparkleVibrato * t) * ((progress - 0.25) / 0.75) * 0.2
    else:
      0.0
    
    # Texture noise - magical shimmer
    let textureNoise = rand(-1.0..1.0) * 0.04 * progress
    
    # Arpeggio accent notes
    let accentPhase = (progress * 4.0) mod 1.0
    let accent = if accentPhase < 0.15:
      sin(2.0 * PI * basePitch * 3.0 * t) * (1.0 - accentPhase / 0.15) * 0.15
    else:
      0.0
    
    # Build-up envelope
    let attack = min(1.0, progress * 3.0)
    let sustain = 0.85 + progress * 0.15
    let release = if progress > 0.85: (1.0 - (progress - 0.85) / 0.15) else: 1.0
    let envelope = attack * sustain * release
    
    let value = (fundamental + third + fifth + octave + sparkle +
                 textureNoise + accent) * envelope
    
    samples[i] = int16(clamp(value * 32767.0 * 0.5, -32767.0, 32767.0))
  
  writeWavFile(filename, samples, sampleRate)
  result = loadSound(filename)

proc createBossSpawn(filename: string): Sound =
  # Epic, ominous boss entrance with dramatic build
  let sampleRate: uint32 = 44100
  let duration = 2.0
  let frameCount = int(sampleRate.float32 * duration)
  var samples = newSeq[int16](frameCount)
  
  for i in 0..<frameCount:
    let t = i.float32 / sampleRate.float32
    let progress = t / duration
    
    # Deep rumble foundation - builds in intensity
    let rumbleFreq = 28.0 + progress * 65.0
    let rumble = sin(2.0 * PI * rumbleFreq * t) * 0.45
    
    # Sub-bass earthquake layer
    let earthquake = sin(2.0 * PI * 18.0 * t) * 0.35 * min(1.0, progress * 1.5)
    
    # Mid-range threat tone
    let threatFreq = 75.0 + progress * 140.0
    let threat = sin(2.0 * PI * threatFreq * t) * 0.32
    
    # Dissonant tension layer
    let tensionFreq = 160.0 + progress * 110.0
    let tension = sin(2.0 * PI * (tensionFreq * 1.06) * t) * 0.22  # Slightly detuned
    
    # High frequency ominous whistle
    let whistleFreq = 800.0 + progress * 400.0
    let whistle = if progress > 0.3:
      sin(2.0 * PI * whistleFreq * t) * ((progress - 0.3) / 0.7) * 0.18
    else:
      0.0
    
    # Noise layers for atmosphere
    let deepNoise = rand(-1.0..1.0) * 0.08 * min(1.0, progress * 2.0)
    
    let midNoise = if progress > 0.4:
      rand(-1.0..1.0) * 0.12 * ((progress - 0.4) / 0.6)
    else:
      0.0
    
    # Metallic impacts for drama
    let impactPhase = (progress * 3.0) mod 0.33
    let impact = if impactPhase < 0.05:
      sin(2.0 * PI * 450.0 * t) * (1.0 - impactPhase / 0.05) * 0.3
    else:
      0.0
    
    # Reverberant tail simulation
    let reverbDecay = exp(-max(0.0, progress - 1.2) * 3.0)
    
    # Build-up envelope - slow dramatic crescendo
    let buildCurve = progress * progress  # Quadratic build
    let mainBuild = min(1.0, buildCurve * 1.8)
    let peakHold = if progress > 0.7: 1.0 else: mainBuild
    let finalDecay = if progress > 0.85:
      1.0 - ((progress - 0.85) / 0.15) * 0.3
    else:
      1.0
    
    let envelope = peakHold * finalDecay * reverbDecay
    
    let value = (rumble + earthquake + threat + tension + whistle +
                 deepNoise + midNoise + impact) * envelope
    
    samples[i] = int16(clamp(value * 32767.0 * 0.7, -32767.0, 32767.0))
  
  writeWavFile(filename, samples, sampleRate)
  result = loadSound(filename)

proc createExplosion(filename: string): Sound =
  # Epic layered explosion with multiple stages
  let sampleRate: uint32 = 44100
  let duration = 1.0
  let frameCount = int(sampleRate.float32 * duration)
  var samples = newSeq[int16](frameCount)
  
  for i in 0..<frameCount:
    let t = i.float32 / sampleRate.float32
    let progress = t / duration
    
    # STAGE 1: Initial impact - very short sharp attack
    let initialClick = if progress < 0.02:
      sin(2.0 * PI * 3000.0 * t) * (1.0 - progress / 0.02) * 0.5
    else:
      0.0
    
    # STAGE 2: Main boom - deep bass explosion
    let boomFreq = 60.0 * exp(-progress * 15.0)
    let boom = sin(2.0 * PI * boomFreq * t) * 0.6
    
    # STAGE 3: Body/punch - mid frequency impact
    let punchFreq = 220.0 * exp(-progress * 12.0)
    let punch = sin(2.0 * PI * punchFreq * t) * 0.4
    
    # STAGE 4: Crackle - high frequency debris
    let crackle = if progress < 0.15:
      sin(2.0 * PI * (800.0 + rand(-200.0..200.0)) * t) * (1.0 - progress / 0.15) * 0.25
    else:
      0.0
    
    # STAGE 5: Rumble - sustained low sub-bass
    let rumble = sin(2.0 * PI * 25.0 * t) * 0.3
    
    # STAGE 6: Noise layers - different densities over time
    let earlyNoise = if progress < 0.08:
      rand(-1.0..1.0) * (1.0 - progress / 0.08) * 0.5
    else:
      0.0
    
    let midNoise = if progress >= 0.08 and progress < 0.35:
      rand(-1.0..1.0) * 0.3
    else:
      0.0
    
    let lateNoise = if progress >= 0.35:
      rand(-1.0..1.0) * 0.15
    else:
      0.0
    
    # STAGE 7: Resonance - adds metallic ring
    let resonance = sin(2.0 * PI * 450.0 * t) * 0.15 * exp(-progress * 3.0)
    
    # Multi-stage envelope
    let mainEnvelope = exp(-progress * 4.5)
    let sustainEnvelope = exp(-max(0.0, progress - 0.3) * 2.0)
    
    let value = (
      initialClick +
      boom * mainEnvelope +
      punch * mainEnvelope +
      crackle +
      rumble * sustainEnvelope +
      (earlyNoise + midNoise + lateNoise) * mainEnvelope +
      resonance
    )
    
    samples[i] = int16(clamp(value * 32767.0 * 0.65, -32767.0, 32767.0))
  
  writeWavFile(filename, samples, sampleRate)
  result = loadSound(filename)

proc createWallPlace(filename: string): Sound =
  # Solid, satisfying placement sound
  let sampleRate: uint32 = 44100
  let duration = 0.2
  let frameCount = int(sampleRate.float32 * duration)
  var samples = newSeq[int16](frameCount)
  
  for i in 0..<frameCount:
    let t = i.float32 / sampleRate.float32
    let progress = t / duration
    
    # Low thud with quick pitch drop
    let thudFreq = 140.0 * exp(-progress * 12.0)
    let thud = sin(2.0 * PI * thudFreq * t) * 0.5
    
    # Click for definition
    let click = if progress < 0.04:
      sin(2.0 * PI * 800.0 * t) * (1.0 - progress / 0.04) * 0.3
    else:
      0.0
    
    # Short noise burst
    let noise = if progress < 0.06:
      rand(-1.0..1.0) * (1.0 - progress / 0.06) * 0.15
    else:
      0.0
    
    let envelope = exp(-progress * 15.0)
    let value = (thud + click + noise) * envelope
    samples[i] = int16(value * 32767.0 * 0.5)
  
  writeWavFile(filename, samples, sampleRate)
  result = loadSound(filename)

proc createTeleport(filename: string): Sound =
  # Advanced sci-fi teleportation effect
  let sampleRate: uint32 = 44100
  let duration = 0.6
  let frameCount = int(sampleRate.float32 * duration)
  var samples = newSeq[int16](frameCount)
  
  for i in 0..<frameCount:
    let t = i.float32 / sampleRate.float32
    let progress = t / duration
    
    # Symmetric up-down sweep for teleport "departure and arrival"
    let sweepPhase = if progress < 0.5:
      progress * 2.0
    else:
      2.0 - progress * 2.0
    
    # Main carrier frequency with dramatic sweep range
    let carrier = 900.0 + sin(sweepPhase * PI) * 1500.0
    
    # Complex modulation for warbling sci-fi character
    let mod1 = 1.0 + sin(2.0 * PI * 14.0 * t) * 0.35
    let mod2 = 1.0 + sin(2.0 * PI * 23.0 * t) * 0.2
    
    # Multi-layer synthesis
    let layer1 = sin(2.0 * PI * carrier * mod1 * t) * 0.38
    let layer2 = sin(2.0 * PI * carrier * 0.5 * mod2 * t) * 0.28  # Octave down
    let layer3 = sin(2.0 * PI * carrier * 1.5 * mod1 * t) * 0.18  # Fifth up
    let layer4 = sin(2.0 * PI * carrier * 2.0 * mod2 * t) * 0.12  # Octave up
    
    # Phaser/flanger effect - sweeping resonance
    let phaserFreq = carrier * (1.0 + sin(sweepPhase * PI * 2.0) * 0.08)
    let phaser = sin(2.0 * PI * phaserFreq * t) * 0.15
    
    # Energy burst noise at transition point
    let transitionNoise = if abs(progress - 0.5) < 0.08:
      rand(-1.0..1.0) * (1.0 - abs(progress - 0.5) / 0.08) * 0.25
    else:
      0.0
    
    # Ambient texture noise
    let textureNoise = rand(-1.0..1.0) * 0.06 * sin(sweepPhase * PI)
    
    # Sparkle hits at entry/exit
    let sparkle = if progress < 0.1 or progress > 0.9:
      let sparkleProgress = if progress < 0.1: progress / 0.1 else: (1.0 - progress) / 0.1
      sin(2.0 * PI * 2400.0 * t) * (1.0 - sparkleProgress) * 0.2
    else:
      0.0
    
    # Symmetric envelope - fade in, peak at middle, fade out
    let envelope = sin(progress * PI)
    
    let value = (layer1 + layer2 + layer3 + layer4 + phaser +
                 transitionNoise + textureNoise + sparkle) * envelope
    
    samples[i] = int16(clamp(value * 32767.0 * 0.48, -32767.0, 32767.0))
  
  writeWavFile(filename, samples, sampleRate)
  result = loadSound(filename)

proc createMenuNav(filename: string): Sound =
  # Clean, quick menu navigation beep
  let sampleRate: uint32 = 44100
  let duration = 0.05
  let frameCount = int(sampleRate.float32 * duration)
  var samples = newSeq[int16](frameCount)
  
  for i in 0..<frameCount:
    let t = i.float32 / sampleRate.float32
    let progress = t / duration
    
    # Simple sine with harmonic for clarity
    let fundamental = sin(2.0 * PI * 900.0 * t) * 0.6
    let harmonic = sin(2.0 * PI * 1800.0 * t) * 0.2
    
    # Very fast envelope for responsiveness
    let envelope = exp(-progress * 40.0)
    
    let value = (fundamental + harmonic) * envelope
    samples[i] = int16(value * 32767.0 * 0.35)
  
  writeWavFile(filename, samples, sampleRate)
  result = loadSound(filename)

proc createMenuSelect(filename: string): Sound =
  # Confirming selection sound - two-tone
  let sampleRate: uint32 = 44100
  let duration = 0.2
  let frameCount = int(sampleRate.float32 * duration)
  var samples = newSeq[int16](frameCount)
  
  for i in 0..<frameCount:
    let t = i.float32 / sampleRate.float32
    let progress = t / duration
    
    # Two note confirmation: low to high
    let freq = if progress < 0.5: 500.0 else: 700.0
    
    # Clean tone with slight harmonic
    let fundamental = sin(2.0 * PI * freq * t) * 0.5
    let harmonic = sin(2.0 * PI * freq * 2.0 * t) * 0.15
    
    # Smooth envelope with quick transitions
    let attack = if progress < 0.08: progress / 0.08 else: 1.0
    let release = if progress > 0.75: (1.0 - (progress - 0.75) / 0.25) else: 1.0
    let envelope = attack * release
    
    let value = (fundamental + harmonic) * envelope
    samples[i] = int16(value * 32767.0 * 0.4)
  
  writeWavFile(filename, samples, sampleRate)
  result = loadSound(filename)

proc createWaveComplete(filename: string): Sound =
  # Triumphant, celebratory fanfare with rich harmonies
  let sampleRate: uint32 = 44100
  let duration = 1.2
  let frameCount = int(sampleRate.float32 * duration)
  var samples = newSeq[int16](frameCount)
  
  # Victory arpeggio - ascending major chord
  let notes = @[
    (freq: 523.25'f32, start: 0.0, length: 0.25),       # C5
    (freq: 659.25'f32, start: 0.22, length: 0.25),      # E5
    (freq: 783.99'f32, start: 0.44, length: 0.25),      # G5
    (freq: 1046.50'f32, start: 0.66, length: 0.54)      # C6 - finale held longer
  ]
  
  for i in 0..<frameCount:
    let t = i.float32 / sampleRate.float32
    var value = 0.0
    
    for note in notes:
      if t >= note.start and t < note.start + note.length:
        let noteTime = t - note.start
        let noteProgress = noteTime / note.length
        
        # Rich trumpet-like tone with harmonics
        let fundamental = sin(2.0 * PI * note.freq * t) * 0.42
        let harmonic2 = sin(2.0 * PI * note.freq * 2.0 * t) * 0.18
        let harmonic3 = sin(2.0 * PI * note.freq * 3.0 * t) * 0.12
        let harmonic4 = sin(2.0 * PI * note.freq * 4.0 * t) * 0.08
        
        # Slight vibrato for life
        let vibrato = 1.0 + sin(2.0 * PI * 5.5 * t) * 0.008
        
        # Bell-like brightness
        let brightness = sin(2.0 * PI * note.freq * 5.0 * t) * 0.06
        
        # Quick attack, sustain with slight decay, gentle release
        let attack = if noteProgress < 0.08: noteProgress / 0.08 else: 1.0
        let sustain = 0.9 + noteProgress * 0.1
        let release = if noteProgress > 0.75:
          (1.0 - (noteProgress - 0.75) / 0.25) * 0.7 + 0.3
        else:
          1.0
        
        let envelope = attack * sustain * release
        
        let noteTone = (fundamental + harmonic2 + harmonic3 + harmonic4 + brightness) * vibrato
        value += noteTone * envelope
    
    # Add sparkle/shimmer for celebration
    let globalProgress = t / duration
    let sparkle = if globalProgress > 0.3:
      sin(2.0 * PI * 2200.0 * t) * ((globalProgress - 0.3) / 0.7) * 0.12
    else:
      0.0
    
    # Subtle noise for texture
    let texture = rand(-1.0..1.0) * 0.02 * globalProgress
    
    samples[i] = int16(clamp((value + sparkle + texture) * 32767.0 * 0.52, -32767.0, 32767.0))
  
  writeWavFile(filename, samples, sampleRate)
  result = loadSound(filename)

proc createShield(filename: string): Sound =
  # Energy shield activation with pulsing
  let sampleRate: uint32 = 44100
  let duration = 0.4
  let frameCount = int(sampleRate.float32 * duration)
  var samples = newSeq[int16](frameCount)
  
  for i in 0..<frameCount:
    let t = i.float32 / sampleRate.float32
    let progress = t / duration
    
    # Base shield frequency with slight rise
    let baseFreq = 260.0 + progress * 40.0
    
    # Energy pulse modulation
    let pulse = 1.0 + sin(2.0 * PI * 8.0 * t) * 0.4
    
    # Multiple harmonic layers for richness
    let layer1 = sin(2.0 * PI * baseFreq * pulse * t) * 0.35
    let layer2 = sin(2.0 * PI * baseFreq * 1.5 * pulse * t) * 0.25
    let layer3 = sin(2.0 * PI * baseFreq * 2.0 * pulse * t) * 0.15
    
    # High frequency shimmer for energy effect
    let shimmer = sin(2.0 * PI * 1800.0 * t) * 0.1 * (1.0 - progress)
    
    # Filtered noise for texture
    let noise = rand(-1.0..1.0) * 0.05 * exp(-progress * 8.0)
    
    let envelope = applyADSR(progress, 0.08, 0.15, 0.6, 0.17)
    
    let value = (layer1 + layer2 + layer3 + shimmer + noise) * envelope
    samples[i] = int16(value * 32767.0 * 0.45)
  
  writeWavFile(filename, samples, sampleRate)
  result = loadSound(filename)

proc createGameOverSound(filename: string): Sound =
  let sampleRate: uint32 = 44100
  let duration = 2.5
  let frameCount = int(sampleRate.float32 * duration)
  var samples = newSeq[int16](frameCount)
  
  let notes = @[
    (freq: 659.25'f32, start: 0.0, length: 0.35),
    (freq: 587.33'f32, start: 0.4, length: 0.35),
    (freq: 523.25'f32, start: 0.8, length: 0.4),
    (freq: 392.00'f32, start: 1.25, length: 0.5),
    (freq: 261.63'f32, start: 1.8, length: 0.7)
  ]
  
  for i in 0..<frameCount:
    let t = i.float32 / sampleRate.float32
    var value = 0.0
    for note in notes:
      if t >= note.start and t < note.start + note.length:
        let noteProgress = (t - note.start) / note.length
        let envelope = applyADSR(noteProgress, 0.1, 0.15, 0.6, 0.15)
        value += sin(2.0 * PI * note.freq * t) * envelope * 0.4
    samples[i] = int16(clamp(value * 32767.0, -32767.0, 32767.0))
  
  writeWavFile(filename, samples, sampleRate)
  result = loadSound(filename)

# SOUND LOADING WITH CACHE
proc loadOrGenerateSound(soundType: SoundType): Sound =
  let cacheFile = getSoundCacheFile(soundType)
  
  if fileExists(cacheFile):
    return loadSound(cacheFile)
  
  case soundType
  of stShoot: result = createLaserShoot(cacheFile)
  of stEnemyHit: result = createImpactHit(cacheFile)
  of stEnemyDeath: result = createEnemyDeath(cacheFile)
  of stPlayerHit: result = createPlayerHit(cacheFile)
  of stCoinPickup: result = createCoinPickup(cacheFile)
  of stPowerUp: result = createPowerUp(cacheFile)
  of stBossSpawn: result = createBossSpawn(cacheFile)
  of stExplosion: result = createExplosion(cacheFile)
  of stWallPlace: result = createWallPlace(cacheFile)
  of stTeleport: result = createTeleport(cacheFile)
  of stMenuNav: result = createMenuNav(cacheFile)
  of stMenuSelect: result = createMenuSelect(cacheFile)
  of stWaveComplete: result = createWaveComplete(cacheFile)
  of stShield: result = createShield(cacheFile)
  of stGameOver: result = createGameOverSound(cacheFile)

type
  Note = object
    freq: float32    # Frequency in Hz (0.0 = rest)
    start: float32   # Start time in seconds
    duration: float32  # Length in seconds

  Instrument = enum
    inMelody, inBass, inPad, inChord

  Section = object
    name: string
    startTime: float32
    duration: float32
    melody: seq[Note]
    bass: seq[Note]
    harmony: seq[Note]
    chords: seq[Note]  # New chord layer

# MUSICAL CONSTANTS
const
  SAMPLE_RATE = 44100'u32
  MUSIC_DURATION = 48.0  # Long-form: 48 seconds

# Note frequencies (4th octave as base)
const
  C3 = 130.81'f32
  D3 = 146.83'f32
  E3 = 164.81'f32
  F3 = 174.61'f32
  G3 = 196.00'f32
  A3 = 220.00'f32
  B3 = 246.94'f32
  C4 = 261.63'f32
  D4 = 293.66'f32
  E4 = 329.63'f32
  F4 = 349.23'f32
  G4 = 392.00'f32
  A4 = 440.00'f32
  B4 = 493.88'f32
  C5 = 523.25'f32
  D5 = 587.33'f32
  E5 = 659.25'f32
  F5 = 698.46'f32
  G5 = 783.99'f32
  A5 = 880.00'f32
  REST = 0.0'f32

# CORE MUSIC SYNTHESIS FUNCTIONS

proc generateSimpleWave(freq: float32, t: float32, waveform: Instrument): float32 =
  ## Generate soft, non-intrusive waveforms for background music
  if freq <= 0.0:
    return 0.0
  
  case waveform
  of inMelody:
    # Soft sine lead with gentle harmonics - not sharp or harsh
    let fundamental = sin(2.0 * PI * freq * t)
    let octave = sin(2.0 * PI * freq * 2.0 * t) * 0.08  # Very gentle octave
    let fifth = sin(2.0 * PI * freq * 1.5 * t) * 0.05   # Hint of fifth
    return fundamental * 0.85 + octave + fifth
  of inBass:
    # Deep, smooth bass - felt more than heard
    let fundamental = sin(2.0 * PI * freq * t)
    let subBass = sin(2.0 * PI * freq * 0.5 * t) * 0.25
    return fundamental * 0.7 + subBass
  of inPad:
    # Extremely soft ambient pad - barely noticeable texture
    let layer1 = sin(2.0 * PI * freq * t)
    let layer2 = sin(2.0 * PI * freq * 1.005 * t)  # Very subtle detuning
    let layer3 = sin(2.0 * PI * freq * 0.995 * t)
    return (layer1 + layer2 + layer3) * 0.333
  of inChord:
    # Piano-like chord sound with attack characteristics
    let fundamental = sin(2.0 * PI * freq * t)
    # Add harmonic richness like a piano
    let h2 = sin(2.0 * PI * freq * 2.0 * t) * 0.12      # Octave
    let h3 = sin(2.0 * PI * freq * 3.0 * t) * 0.06      # Octave + fifth
    let h4 = sin(2.0 * PI * freq * 4.0 * t) * 0.04      # 2 octaves
    let h5 = sin(2.0 * PI * freq * 5.0 * t) * 0.03      # Upper harmonics
    # Slight inharmonicity for piano character
    let detune = sin(2.0 * PI * freq * 1.002 * t) * 0.15
    return (fundamental * 0.6 + h2 + h3 + h4 + h5 + detune)

proc applyNoteEnvelope(progress: float32, noteDuration: float32): float32 =
  ## Apply gentle, smooth envelope - no harsh attacks or releases
  let attackTime = min(0.15, noteDuration * 0.25)  # Slower, softer attack
  let releaseTime = min(0.25, noteDuration * 0.35)  # Longer, gentler release
  let attack = attackTime / noteDuration
  let release = 1.0 - (releaseTime / noteDuration)
  
  if progress < attack:
    # Smooth fade in using sine curve
    let attackProgress = progress / attack
    return sin(attackProgress * PI * 0.5)  # Sine curve: smoother than linear
  elif progress > release:
    # Gentle fade out
    let releaseProgress = (progress - release) / (1.0 - release)
    return cos(releaseProgress * PI * 0.5)  # Cosine curve: smooth decay
  else:
    return 1.0

proc renderNotes(notes: seq[Note], samples: var seq[float32],
                instrument: Instrument, volume: float32) =
  ## Render a sequence of notes into the sample buffer
  for note in notes:
    let startSample = int(note.start * SAMPLE_RATE.float32)
    let endSample = int((note.start + note.duration) * SAMPLE_RATE.float32)
    
    for i in startSample..<min(endSample, samples.len):
      let t = i.float32 / SAMPLE_RATE.float32
      let noteTime = t - note.start
      let progress = noteTime / note.duration
      
      let wave = generateSimpleWave(note.freq, t, instrument)
      let envelope = applyNoteEnvelope(progress, note.duration)
      
      samples[i] += wave * envelope * volume

proc renderChords(chords: seq[Note], samples: var seq[float32], volume: float32) =
  ## Render piano chords - each note represents the root, chord contains root + third + fifth
  for chord in chords:
    if chord.freq <= 0.0:
      continue
    
    # Build triad: root, major third, perfect fifth
    let root = chord.freq
    let third = root * 1.25992  # Major third (4 semitones)
    let fifth = root * 1.49831  # Perfect fifth (7 semitones)
    
    let startSample = int(chord.start * SAMPLE_RATE.float32)
    let endSample = int((chord.start + chord.duration) * SAMPLE_RATE.float32)
    
    for i in startSample..<min(endSample, samples.len):
      let t = i.float32 / SAMPLE_RATE.float32
      let noteTime = t - chord.start
      let progress = noteTime / chord.duration
      
      # Piano-like envelope with quick attack and sustained decay
      let envelope = applyNoteEnvelope(progress, chord.duration)
      
      # Render all three notes of the chord
      let wave1 = generateSimpleWave(root, t, inChord) * 0.4
      let wave2 = generateSimpleWave(third, t, inChord) * 0.3
      let wave3 = generateSimpleWave(fifth, t, inChord) * 0.3
      
      samples[i] += (wave1 + wave2 + wave3) * envelope * volume

proc applySectionDynamics(samples: var seq[float32], section: Section,
                         globalVolume: float32) =
  ## Apply very gentle volume transitions between sections
  let startSample = int(section.startTime * SAMPLE_RATE.float32)
  let endSample = int((section.startTime + section.duration) * SAMPLE_RATE.float32)
  let fadeLength = int(1.5 * SAMPLE_RATE.float32)  # Longer 1.5 second fade
  
  for i in startSample..<min(endSample, samples.len):
    let sampleInSection = i - startSample
    let sectionLength = endSample - startSample
    var dynamicMultiplier = globalVolume
    
    # Smooth fade in at start using sine curve
    if sampleInSection < fadeLength:
      let fadeProgress = sampleInSection.float32 / fadeLength.float32
      dynamicMultiplier *= sin(fadeProgress * PI * 0.5)
    
    # Smooth fade out at end using cosine curve
    if (sectionLength - sampleInSection) < fadeLength:
      let fadeProgress = (sectionLength - sampleInSection).float32 / fadeLength.float32
      dynamicMultiplier *= cos((1.0 - fadeProgress) * PI * 0.5)
    
    samples[i] *= dynamicMultiplier

# MENU MUSIC

proc createMenuMusicSections(): seq[Section] =
  result = @[]
  var currentTime = 0.0'f32
  
  # INTRO - Gentle opening with sparse notes (8 seconds)
  var intro = Section(
    name: "Intro",
    startTime: currentTime,
    duration: 8.0,
    melody: @[
      Note(freq: E5, start: currentTime + 0.0, duration: 1.5),
      Note(freq: REST, start: currentTime + 1.5, duration: 0.5),
      Note(freq: D5, start: currentTime + 2.0, duration: 1.5),
      Note(freq: REST, start: currentTime + 3.5, duration: 0.5),
      Note(freq: C5, start: currentTime + 4.0, duration: 2.0),
      Note(freq: REST, start: currentTime + 6.0, duration: 2.0)
    ],
    bass: @[
      Note(freq: C4, start: currentTime + 0.0, duration: 4.0),
      Note(freq: G4, start: currentTime + 4.0, duration: 4.0)
    ],
    harmony: @[],
    chords: @[
      Note(freq: C4, start: currentTime + 0.0, duration: 2.0),
      Note(freq: C4, start: currentTime + 2.0, duration: 2.0),
      Note(freq: G3, start: currentTime + 4.0, duration: 2.0),
      Note(freq: G3, start: currentTime + 6.0, duration: 2.0)
    ]
  )
  result.add(intro)
  currentTime += intro.duration
  
  # SECTION A - Main theme (12 seconds)
  var sectionA = Section(
    name: "Main Theme",
    startTime: currentTime,
    duration: 12.0,
    melody: @[
      Note(freq: E5, start: currentTime + 0.0, duration: 1.0),
      Note(freq: G5, start: currentTime + 1.0, duration: 1.0),
      Note(freq: E5, start: currentTime + 2.0, duration: 1.5),
      Note(freq: REST, start: currentTime + 3.5, duration: 0.5),
      Note(freq: D5, start: currentTime + 4.0, duration: 1.5),
      Note(freq: C5, start: currentTime + 5.5, duration: 1.5),
      Note(freq: REST, start: currentTime + 7.0, duration: 1.0),
      Note(freq: G5, start: currentTime + 8.0, duration: 1.5),
      Note(freq: E5, start: currentTime + 9.5, duration: 2.5)
    ],
    bass: @[
      Note(freq: C4, start: currentTime + 0.0, duration: 3.0),
      Note(freq: REST, start: currentTime + 3.0, duration: 1.0),
      Note(freq: G4, start: currentTime + 4.0, duration: 3.0),
      Note(freq: REST, start: currentTime + 7.0, duration: 1.0),
      Note(freq: C4, start: currentTime + 8.0, duration: 4.0)
    ],
    harmony: @[
      Note(freq: E4, start: currentTime + 0.0, duration: 4.0),
      Note(freq: D4, start: currentTime + 4.0, duration: 3.0),
      Note(freq: E4, start: currentTime + 8.0, duration: 4.0)
    ],
    chords: @[
      Note(freq: C4, start: currentTime + 0.0, duration: 1.5),
      Note(freq: E4, start: currentTime + 1.5, duration: 1.5),
      Note(freq: C4, start: currentTime + 3.0, duration: 1.5),
      Note(freq: G3, start: currentTime + 4.5, duration: 1.5),
      Note(freq: D4, start: currentTime + 6.0, duration: 1.5),
      Note(freq: C4, start: currentTime + 7.5, duration: 2.0),
      Note(freq: E4, start: currentTime + 9.5, duration: 2.5)
    ]
  )
  result.add(sectionA)
  currentTime += sectionA.duration
  
  # SECTION B - Variation with different contour (12 seconds)
  var sectionB = Section(
    name: "Variation",
    startTime: currentTime,
    duration: 12.0,
    melody: @[
      Note(freq: C5, start: currentTime + 0.0, duration: 2.0),
      Note(freq: REST, start: currentTime + 2.0, duration: 0.5),
      Note(freq: D5, start: currentTime + 2.5, duration: 1.5),
      Note(freq: E5, start: currentTime + 4.0, duration: 2.0),
      Note(freq: REST, start: currentTime + 6.0, duration: 1.0),
      Note(freq: G5, start: currentTime + 7.0, duration: 1.5),
      Note(freq: F5, start: currentTime + 8.5, duration: 1.5),
      Note(freq: E5, start: currentTime + 10.0, duration: 2.0)
    ],
    bass: @[
      Note(freq: F4, start: currentTime + 0.0, duration: 4.0),
      Note(freq: C4, start: currentTime + 4.0, duration: 3.0),
      Note(freq: REST, start: currentTime + 7.0, duration: 1.0),
      Note(freq: G4, start: currentTime + 8.0, duration: 4.0)
    ],
    harmony: @[
      Note(freq: A4, start: currentTime + 0.0, duration: 4.0),
      Note(freq: G4, start: currentTime + 4.0, duration: 3.0),
      Note(freq: E4, start: currentTime + 8.0, duration: 4.0)
    ],
    chords: @[
      Note(freq: F3, start: currentTime + 0.0, duration: 2.0),
      Note(freq: C4, start: currentTime + 2.0, duration: 2.0),
      Note(freq: C4, start: currentTime + 4.0, duration: 1.5),
      Note(freq: E4, start: currentTime + 5.5, duration: 1.5),
      Note(freq: G3, start: currentTime + 7.0, duration: 2.0),
      Note(freq: C4, start: currentTime + 9.0, duration: 3.0)
    ]
  )
  result.add(sectionB)
  currentTime += sectionB.duration
  
  # OUTRO - Gentle resolution (16 seconds)
  var outro = Section(
    name: "Outro",
    startTime: currentTime,
    duration: 16.0,
    melody: @[
      Note(freq: G5, start: currentTime + 0.0, duration: 2.0),
      Note(freq: E5, start: currentTime + 2.5, duration: 2.0),
      Note(freq: REST, start: currentTime + 4.5, duration: 1.5),
      Note(freq: D5, start: currentTime + 6.0, duration: 2.5),
      Note(freq: C5, start: currentTime + 8.5, duration: 3.0),
      Note(freq: REST, start: currentTime + 11.5, duration: 4.5)
    ],
    bass: @[
      Note(freq: C4, start: currentTime + 0.0, duration: 4.0),
      Note(freq: G4, start: currentTime + 4.0, duration: 4.0),
      Note(freq: C4, start: currentTime + 8.0, duration: 8.0)
    ],
    harmony: @[
      Note(freq: E4, start: currentTime + 0.0, duration: 6.0),
      Note(freq: REST, start: currentTime + 6.0, duration: 2.0),
      Note(freq: C4, start: currentTime + 8.0, duration: 8.0)
    ],
    chords: @[
      Note(freq: C4, start: currentTime + 0.0, duration: 2.5),
      Note(freq: E4, start: currentTime + 2.5, duration: 2.0),
      Note(freq: G3, start: currentTime + 4.5, duration: 2.5),
      Note(freq: D4, start: currentTime + 7.0, duration: 2.0),
      Note(freq: C4, start: currentTime + 9.0, duration: 7.0)
    ]
  )
  result.add(outro)

proc createMenuMusic(filename: string): Music =
  let sections = createMenuMusicSections()
  var samples = newSeq[float32](int(MUSIC_DURATION * SAMPLE_RATE.float32))
  
  for section in sections:
    # Very quiet, non-intrusive background levels
    renderNotes(section.melody, samples, inMelody, 0.12)
    renderNotes(section.bass, samples, inBass, 0.15)
    renderNotes(section.harmony, samples, inPad, 0.08)
    renderChords(section.chords, samples, 0.18)  # Piano chords
    applySectionDynamics(samples, section, 0.7)  # Reduce overall section volume
  
  # Convert to int16 with final gentle limiting
  var samples16 = newSeq[int16](samples.len)
  for i in 0..<samples.len:
    # Apply soft compression to prevent any harshness
    let compressed = if samples[i] > 0.0:
      samples[i] * (1.0 - samples[i] * 0.3)
    else:
      samples[i] * (1.0 + samples[i] * 0.3)
    
    samples16[i] = int16(clamp(compressed * 32767.0 * 0.6, -32767.0, 32767.0))
  
  writeWavFile(filename, samples16, SAMPLE_RATE)
  result = loadMusicStream(filename)

# WAVE MUSIC

proc createWaveMusicSections(): seq[Section] =
  result = @[]
  var currentTime = 0.0'f32
  
  # INTRO - Immediate frenetic energy (8 seconds)
  var intro = Section(
    name: "Intro",
    startTime: currentTime,
    duration: 8.0,
    melody: @[
      Note(freq: D5, start: currentTime + 0.0, duration: 0.25),
      Note(freq: E5, start: currentTime + 0.25, duration: 0.25),
      Note(freq: F5, start: currentTime + 0.5, duration: 0.25),
      Note(freq: G5, start: currentTime + 0.75, duration: 0.25),
      Note(freq: A5, start: currentTime + 1.0, duration: 0.5),
      Note(freq: G5, start: currentTime + 1.5, duration: 0.25),
      Note(freq: F5, start: currentTime + 1.75, duration: 0.25),
      Note(freq: E5, start: currentTime + 2.0, duration: 0.25),
      Note(freq: D5, start: currentTime + 2.25, duration: 0.25),
      Note(freq: A5, start: currentTime + 2.5, duration: 0.5),
      Note(freq: G5, start: currentTime + 3.0, duration: 0.25),
      Note(freq: A5, start: currentTime + 3.25, duration: 0.25),
      Note(freq: F5, start: currentTime + 3.5, duration: 0.5),
      Note(freq: D5, start: currentTime + 4.0, duration: 0.25),
      Note(freq: E5, start: currentTime + 4.25, duration: 0.25),
      Note(freq: F5, start: currentTime + 4.5, duration: 0.25),
      Note(freq: G5, start: currentTime + 4.75, duration: 0.25),
      Note(freq: A5, start: currentTime + 5.0, duration: 0.5),
      Note(freq: G5, start: currentTime + 5.5, duration: 0.5),
      Note(freq: F5, start: currentTime + 6.0, duration: 0.5),
      Note(freq: E5, start: currentTime + 6.5, duration: 0.75),
      Note(freq: D5, start: currentTime + 7.25, duration: 0.75)
    ],
    bass: @[
      Note(freq: D4, start: currentTime + 0.0, duration: 0.5),
      Note(freq: D4, start: currentTime + 0.5, duration: 0.5),
      Note(freq: D4, start: currentTime + 1.0, duration: 0.5),
      Note(freq: D4, start: currentTime + 1.5, duration: 0.5),
      Note(freq: D4, start: currentTime + 2.0, duration: 0.5),
      Note(freq: A4, start: currentTime + 2.5, duration: 0.5),
      Note(freq: D4, start: currentTime + 3.0, duration: 0.5),
      Note(freq: A4, start: currentTime + 3.5, duration: 0.5),
      Note(freq: D4, start: currentTime + 4.0, duration: 0.5),
      Note(freq: D4, start: currentTime + 4.5, duration: 0.5),
      Note(freq: G4, start: currentTime + 5.0, duration: 1.0),
      Note(freq: A4, start: currentTime + 6.0, duration: 2.0)
    ],
    harmony: @[
      Note(freq: F4, start: currentTime + 0.0, duration: 2.0),
      Note(freq: A4, start: currentTime + 2.0, duration: 2.0),
      Note(freq: F4, start: currentTime + 4.0, duration: 2.0),
      Note(freq: E4, start: currentTime + 6.0, duration: 2.0)
    ],
    chords: @[
      Note(freq: D4, start: currentTime + 0.0, duration: 1.0),
      Note(freq: D4, start: currentTime + 1.0, duration: 1.0),
      Note(freq: D4, start: currentTime + 2.0, duration: 1.0),
      Note(freq: A3, start: currentTime + 3.0, duration: 1.0),
      Note(freq: G3, start: currentTime + 4.0, duration: 1.0),
      Note(freq: D4, start: currentTime + 5.0, duration: 1.0),
      Note(freq: A3, start: currentTime + 6.0, duration: 2.0)
    ]
  )
  result.add(intro)
  currentTime += intro.duration
  
  # SECTION A - Relentless rapid-fire melody (14 seconds)
  var sectionA = Section(
    name: "Action Theme",
    startTime: currentTime,
    duration: 14.0,
    melody: @[
      Note(freq: D5, start: currentTime + 0.0, duration: 0.25),
      Note(freq: F5, start: currentTime + 0.25, duration: 0.25),
      Note(freq: A5, start: currentTime + 0.5, duration: 0.5),
      Note(freq: D5, start: currentTime + 1.0, duration: 0.25),
      Note(freq: F5, start: currentTime + 1.25, duration: 0.25),
      Note(freq: G5, start: currentTime + 1.5, duration: 0.5),
      Note(freq: F5, start: currentTime + 2.0, duration: 0.25),
      Note(freq: E5, start: currentTime + 2.25, duration: 0.25),
      Note(freq: D5, start: currentTime + 2.5, duration: 0.5),
      Note(freq: A5, start: currentTime + 3.0, duration: 0.25),
      Note(freq: G5, start: currentTime + 3.25, duration: 0.25),
      Note(freq: F5, start: currentTime + 3.5, duration: 0.25),
      Note(freq: E5, start: currentTime + 3.75, duration: 0.25),
      Note(freq: D5, start: currentTime + 4.0, duration: 0.5),
      Note(freq: F5, start: currentTime + 4.5, duration: 0.25),
      Note(freq: A5, start: currentTime + 4.75, duration: 0.25),
      Note(freq: G5, start: currentTime + 5.0, duration: 0.5),
      Note(freq: F5, start: currentTime + 5.5, duration: 0.25),
      Note(freq: D5, start: currentTime + 5.75, duration: 0.25),
      Note(freq: E5, start: currentTime + 6.0, duration: 0.25),
      Note(freq: F5, start: currentTime + 6.25, duration: 0.25),
      Note(freq: G5, start: currentTime + 6.5, duration: 0.5),
      Note(freq: A5, start: currentTime + 7.0, duration: 0.25),
      Note(freq: G5, start: currentTime + 7.25, duration: 0.25),
      Note(freq: F5, start: currentTime + 7.5, duration: 0.5),
      Note(freq: D5, start: currentTime + 8.0, duration: 0.25),
      Note(freq: E5, start: currentTime + 8.25, duration: 0.25),
      Note(freq: F5, start: currentTime + 8.5, duration: 0.25),
      Note(freq: A5, start: currentTime + 8.75, duration: 0.25),
      Note(freq: G5, start: currentTime + 9.0, duration: 0.5),
      Note(freq: F5, start: currentTime + 9.5, duration: 0.5),
      Note(freq: E5, start: currentTime + 10.0, duration: 0.75),
      Note(freq: D5, start: currentTime + 10.75, duration: 0.75),
      Note(freq: F5, start: currentTime + 11.5, duration: 0.5),
      Note(freq: A5, start: currentTime + 12.0, duration: 1.0),
      Note(freq: G5, start: currentTime + 13.0, duration: 1.0)
    ],
    bass: @[
      Note(freq: D4, start: currentTime + 0.0, duration: 0.5),
      Note(freq: D4, start: currentTime + 0.5, duration: 0.5),
      Note(freq: A4, start: currentTime + 1.0, duration: 0.5),
      Note(freq: A4, start: currentTime + 1.5, duration: 0.5),
      Note(freq: D4, start: currentTime + 2.0, duration: 0.5),
      Note(freq: D4, start: currentTime + 2.5, duration: 0.5),
      Note(freq: A4, start: currentTime + 3.0, duration: 0.5),
      Note(freq: A4, start: currentTime + 3.5, duration: 0.5),
      Note(freq: D4, start: currentTime + 4.0, duration: 0.5),
      Note(freq: F4, start: currentTime + 4.5, duration: 0.5),
      Note(freq: G4, start: currentTime + 5.0, duration: 1.0),
      Note(freq: A4, start: currentTime + 6.0, duration: 1.0),
      Note(freq: D4, start: currentTime + 7.0, duration: 0.5),
      Note(freq: D4, start: currentTime + 7.5, duration: 0.5),
      Note(freq: F4, start: currentTime + 8.0, duration: 1.0),
      Note(freq: G4, start: currentTime + 9.0, duration: 1.0),
      Note(freq: D4, start: currentTime + 10.0, duration: 4.0)
    ],
    harmony: @[
      Note(freq: F4, start: currentTime + 0.0, duration: 2.0),
      Note(freq: A4, start: currentTime + 2.0, duration: 2.0),
      Note(freq: F4, start: currentTime + 4.0, duration: 2.0),
      Note(freq: D4, start: currentTime + 6.0, duration: 2.0),
      Note(freq: E4, start: currentTime + 8.0, duration: 3.0),
      Note(freq: F4, start: currentTime + 11.0, duration: 3.0)
    ],
    chords: @[
      Note(freq: D4, start: currentTime + 0.0, duration: 0.75),
      Note(freq: D4, start: currentTime + 0.75, duration: 0.75),
      Note(freq: A3, start: currentTime + 1.5, duration: 0.75),
      Note(freq: F4, start: currentTime + 2.25, duration: 0.75),
      Note(freq: D4, start: currentTime + 3.0, duration: 1.0),
      Note(freq: A3, start: currentTime + 4.0, duration: 0.75),
      Note(freq: D4, start: currentTime + 4.75, duration: 0.75),
      Note(freq: G3, start: currentTime + 5.5, duration: 1.0),
      Note(freq: A3, start: currentTime + 6.5, duration: 1.0),
      Note(freq: D4, start: currentTime + 7.5, duration: 1.0),
      Note(freq: F4, start: currentTime + 8.5, duration: 1.0),
      Note(freq: D4, start: currentTime + 9.5, duration: 1.5),
      Note(freq: A3, start: currentTime + 11.0, duration: 3.0)
    ]
  )
  result.add(sectionA)
  currentTime += sectionA.duration
  
  # SECTION B - Different pattern but equally frenetic (12 seconds)
  var sectionB = Section(
    name: "Contrast",
    startTime: currentTime,
    duration: 12.0,
    melody: @[
      Note(freq: E5, start: currentTime + 0.0, duration: 0.25),
      Note(freq: G5, start: currentTime + 0.25, duration: 0.25),
      Note(freq: C5, start: currentTime + 0.5, duration: 0.25),
      Note(freq: E5, start: currentTime + 0.75, duration: 0.25),
      Note(freq: D5, start: currentTime + 1.0, duration: 0.5),
      Note(freq: E5, start: currentTime + 1.5, duration: 0.25),
      Note(freq: G5, start: currentTime + 1.75, duration: 0.25),
      Note(freq: F5, start: currentTime + 2.0, duration: 0.5),
      Note(freq: E5, start: currentTime + 2.5, duration: 0.25),
      Note(freq: D5, start: currentTime + 2.75, duration: 0.25),
      Note(freq: C5, start: currentTime + 3.0, duration: 0.5),
      Note(freq: E5, start: currentTime + 3.5, duration: 0.25),
      Note(freq: G5, start: currentTime + 3.75, duration: 0.25),
      Note(freq: A5, start: currentTime + 4.0, duration: 0.5),
      Note(freq: G5, start: currentTime + 4.5, duration: 0.25),
      Note(freq: F5, start: currentTime + 4.75, duration: 0.25),
      Note(freq: E5, start: currentTime + 5.0, duration: 0.5),
      Note(freq: D5, start: currentTime + 5.5, duration: 0.5),
      Note(freq: C5, start: currentTime + 6.0, duration: 0.25),
      Note(freq: D5, start: currentTime + 6.25, duration: 0.25),
      Note(freq: E5, start: currentTime + 6.5, duration: 0.5),
      Note(freq: G5, start: currentTime + 7.0, duration: 0.5),
      Note(freq: F5, start: currentTime + 7.5, duration: 0.25),
      Note(freq: E5, start: currentTime + 7.75, duration: 0.25),
      Note(freq: D5, start: currentTime + 8.0, duration: 0.75),
      Note(freq: E5, start: currentTime + 8.75, duration: 0.75),
      Note(freq: G5, start: currentTime + 9.5, duration: 1.0),
      Note(freq: C5, start: currentTime + 10.5, duration: 1.5)
    ],
    bass: @[
      Note(freq: C4, start: currentTime + 0.0, duration: 0.5),
      Note(freq: C4, start: currentTime + 0.5, duration: 0.5),
      Note(freq: E4, start: currentTime + 1.0, duration: 0.5),
      Note(freq: E4, start: currentTime + 1.5, duration: 0.5),
      Note(freq: G4, start: currentTime + 2.0, duration: 0.5),
      Note(freq: C4, start: currentTime + 2.5, duration: 0.5),
      Note(freq: E4, start: currentTime + 3.0, duration: 0.5),
      Note(freq: G4, start: currentTime + 3.5, duration: 0.5),
      Note(freq: C4, start: currentTime + 4.0, duration: 1.0),
      Note(freq: G4, start: currentTime + 5.0, duration: 1.0),
      Note(freq: C4, start: currentTime + 6.0, duration: 0.5),
      Note(freq: E4, start: currentTime + 6.5, duration: 0.5),
      Note(freq: G4, start: currentTime + 7.0, duration: 1.0),
      Note(freq: C4, start: currentTime + 8.0, duration: 4.0)
    ],
    harmony: @[
      Note(freq: E4, start: currentTime + 0.0, duration: 2.0),
      Note(freq: G4, start: currentTime + 2.0, duration: 2.0),
      Note(freq: E4, start: currentTime + 4.0, duration: 2.0),
      Note(freq: C4, start: currentTime + 6.0, duration: 2.0),
      Note(freq: E4, start: currentTime + 8.0, duration: 4.0)
    ],
    chords: @[
      Note(freq: C4, start: currentTime + 0.0, duration: 1.0),
      Note(freq: E4, start: currentTime + 1.0, duration: 1.0),
      Note(freq: G3, start: currentTime + 2.0, duration: 1.0),
      Note(freq: C4, start: currentTime + 3.0, duration: 1.0),
      Note(freq: E4, start: currentTime + 4.0, duration: 1.5),
      Note(freq: G3, start: currentTime + 5.5, duration: 1.5),
      Note(freq: C4, start: currentTime + 7.0, duration: 1.5),
      Note(freq: E4, start: currentTime + 8.5, duration: 3.5)
    ]
  )
  result.add(sectionB)
  currentTime += sectionB.duration
  
  # OUTRO - Sustained frenetic energy with resolution (14 seconds)
  var outro = Section(
    name: "Outro",
    startTime: currentTime,
    duration: 14.0,
    melody: @[
      Note(freq: A5, start: currentTime + 0.0, duration: 0.5),
      Note(freq: G5, start: currentTime + 0.5, duration: 0.5),
      Note(freq: F5, start: currentTime + 1.0, duration: 0.25),
      Note(freq: E5, start: currentTime + 1.25, duration: 0.25),
      Note(freq: D5, start: currentTime + 1.5, duration: 0.5),
      Note(freq: F5, start: currentTime + 2.0, duration: 0.25),
      Note(freq: A5, start: currentTime + 2.25, duration: 0.25),
      Note(freq: G5, start: currentTime + 2.5, duration: 0.5),
      Note(freq: F5, start: currentTime + 3.0, duration: 0.5),
      Note(freq: D5, start: currentTime + 3.5, duration: 0.25),
      Note(freq: E5, start: currentTime + 3.75, duration: 0.25),
      Note(freq: F5, start: currentTime + 4.0, duration: 0.5),
      Note(freq: A5, start: currentTime + 4.5, duration: 0.5),
      Note(freq: G5, start: currentTime + 5.0, duration: 0.75),
      Note(freq: F5, start: currentTime + 5.75, duration: 0.75),
      Note(freq: D5, start: currentTime + 6.5, duration: 1.0),
      Note(freq: F5, start: currentTime + 7.5, duration: 0.5),
      Note(freq: A5, start: currentTime + 8.0, duration: 1.0),
      Note(freq: G5, start: currentTime + 9.0, duration: 1.0),
      Note(freq: D5, start: currentTime + 10.0, duration: 4.0)
    ],
    bass: @[
      Note(freq: D4, start: currentTime + 0.0, duration: 0.5),
      Note(freq: D4, start: currentTime + 0.5, duration: 0.5),
      Note(freq: G4, start: currentTime + 1.0, duration: 1.0),
      Note(freq: A4, start: currentTime + 2.0, duration: 1.0),
      Note(freq: D4, start: currentTime + 3.0, duration: 0.5),
      Note(freq: D4, start: currentTime + 3.5, duration: 0.5),
      Note(freq: F4, start: currentTime + 4.0, duration: 1.0),
      Note(freq: G4, start: currentTime + 5.0, duration: 1.0),
      Note(freq: D4, start: currentTime + 6.0, duration: 8.0)
    ],
    harmony: @[
      Note(freq: F4, start: currentTime + 0.0, duration: 3.0),
      Note(freq: A4, start: currentTime + 3.0, duration: 3.0),
      Note(freq: D4, start: currentTime + 6.0, duration: 8.0)
    ],
    chords: @[
      Note(freq: D4, start: currentTime + 0.0, duration: 1.0),
      Note(freq: G3, start: currentTime + 1.0, duration: 1.0),
      Note(freq: A3, start: currentTime + 2.0, duration: 1.5),
      Note(freq: D4, start: currentTime + 3.5, duration: 1.5),
      Note(freq: F4, start: currentTime + 5.0, duration: 1.5),
      Note(freq: D4, start: currentTime + 6.5, duration: 7.5)
    ]
  )
  result.add(outro)

proc createWaveMusic(filename: string): Music =
  let sections = createWaveMusicSections()
  var samples = newSeq[float32](int(MUSIC_DURATION * SAMPLE_RATE.float32))
  
  for section in sections:
    # Still frenetic but much quieter in the background
    renderNotes(section.melody, samples, inMelody, 0.14)
    renderNotes(section.bass, samples, inBass, 0.17)
    renderNotes(section.harmony, samples, inPad, 0.09)
    renderChords(section.chords, samples, 0.20)  # Driving piano chords
    applySectionDynamics(samples, section, 0.75)
  
  # Convert to int16 with final gentle limiting
  var samples16 = newSeq[int16](samples.len)
  for i in 0..<samples.len:
    # Apply soft compression to prevent any harshness
    let compressed = if samples[i] > 0.0:
      samples[i] * (1.0 - samples[i] * 0.3)
    else:
      samples[i] * (1.0 + samples[i] * 0.3)
    
    samples16[i] = int16(clamp(compressed * 32767.0 * 0.6, -32767.0, 32767.0))
  
  writeWavFile(filename, samples16, SAMPLE_RATE)
  result = loadMusicStream(filename)

# POWER-UP MUSIC

proc createPowerUpMusicSections(): seq[Section] =
  result = @[]
  var currentTime = 0.0'f32
  
  # INTRO - Bright opening (8 seconds)
  var intro = Section(
    name: "Intro",
    startTime: currentTime,
    duration: 8.0,
    melody: @[
      Note(freq: C5, start: currentTime + 0.0, duration: 1.0),
      Note(freq: E5, start: currentTime + 1.0, duration: 1.0),
      Note(freq: G5, start: currentTime + 2.0, duration: 1.5),
      Note(freq: REST, start: currentTime + 3.5, duration: 1.0),
      Note(freq: E5, start: currentTime + 4.5, duration: 1.5),
      Note(freq: C5, start: currentTime + 6.0, duration: 2.0)
    ],
    bass: @[
      Note(freq: C4, start: currentTime + 0.0, duration: 4.0),
      Note(freq: G4, start: currentTime + 4.0, duration: 4.0)
    ],
    harmony: @[],
    chords: @[
      Note(freq: C4, start: currentTime + 0.0, duration: 1.5),
      Note(freq: E4, start: currentTime + 1.5, duration: 1.5),
      Note(freq: G3, start: currentTime + 3.0, duration: 1.5),
      Note(freq: C4, start: currentTime + 4.5, duration: 1.5),
      Note(freq: G3, start: currentTime + 6.0, duration: 2.0)
    ]
  )
  result.add(intro)
  currentTime += intro.duration
  
  # SECTION A - Joyful main theme (14 seconds)
  var sectionA = Section(
    name: "Joyful Theme",
    startTime: currentTime,
    duration: 14.0,
    melody: @[
      Note(freq: E5, start: currentTime + 0.0, duration: 1.0),
      Note(freq: G5, start: currentTime + 1.0, duration: 1.0),
      Note(freq: C5, start: currentTime + 2.0, duration: 1.5),
      Note(freq: REST, start: currentTime + 3.5, duration: 0.5),
      Note(freq: A5, start: currentTime + 4.0, duration: 1.5),
      Note(freq: G5, start: currentTime + 5.5, duration: 1.5),
      Note(freq: REST, start: currentTime + 7.0, duration: 1.0),
      Note(freq: E5, start: currentTime + 8.0, duration: 1.5),
      Note(freq: F5, start: currentTime + 9.5, duration: 1.0),
      Note(freq: G5, start: currentTime + 10.5, duration: 3.5)
    ],
    bass: @[
      Note(freq: C4, start: currentTime + 0.0, duration: 3.0),
      Note(freq: REST, start: currentTime + 3.0, duration: 0.5),
      Note(freq: F4, start: currentTime + 3.5, duration: 3.0),
      Note(freq: REST, start: currentTime + 6.5, duration: 0.5),
      Note(freq: C4, start: currentTime + 7.0, duration: 3.5),
      Note(freq: G4, start: currentTime + 10.5, duration: 3.5)
    ],
    harmony: @[
      Note(freq: E4, start: currentTime + 0.0, duration: 4.0),
      Note(freq: A4, start: currentTime + 4.0, duration: 3.0),
      Note(freq: REST, start: currentTime + 7.0, duration: 1.0),
      Note(freq: E4, start: currentTime + 8.0, duration: 6.0)
    ],
    chords: @[
      Note(freq: C4, start: currentTime + 0.0, duration: 1.5),
      Note(freq: E4, start: currentTime + 1.5, duration: 1.5),
      Note(freq: F4, start: currentTime + 3.0, duration: 1.5),
      Note(freq: A3, start: currentTime + 4.5, duration: 1.5),
      Note(freq: C4, start: currentTime + 6.0, duration: 2.0),
      Note(freq: E4, start: currentTime + 8.0, duration: 3.0),
      Note(freq: G3, start: currentTime + 11.0, duration: 3.0)
    ]
  )
  result.add(sectionA)
  currentTime += sectionA.duration
  
  # SECTION B - Building variation (12 seconds)
  var sectionB = Section(
    name: "Building",
    startTime: currentTime,
    duration: 12.0,
    melody: @[
      Note(freq: C5, start: currentTime + 0.0, duration: 1.0),
      Note(freq: D5, start: currentTime + 1.0, duration: 1.0),
      Note(freq: E5, start: currentTime + 2.0, duration: 1.5),
      Note(freq: G5, start: currentTime + 3.5, duration: 2.0),
      Note(freq: REST, start: currentTime + 5.5, duration: 1.0),
      Note(freq: A5, start: currentTime + 6.5, duration: 1.5),
      Note(freq: G5, start: currentTime + 8.0, duration: 1.5),
      Note(freq: E5, start: currentTime + 9.5, duration: 2.5)
    ],
    bass: @[
      Note(freq: F4, start: currentTime + 0.0, duration: 3.0),
      Note(freq: C4, start: currentTime + 3.0, duration: 3.0),
      Note(freq: REST, start: currentTime + 6.0, duration: 0.5),
      Note(freq: G4, start: currentTime + 6.5, duration: 5.5)
    ],
    harmony: @[
      Note(freq: A4, start: currentTime + 0.0, duration: 3.0),
      Note(freq: E4, start: currentTime + 3.0, duration: 3.0),
      Note(freq: REST, start: currentTime + 6.0, duration: 1.0),
      Note(freq: D4, start: currentTime + 7.0, duration: 5.0)
    ],
    chords: @[
      Note(freq: F4, start: currentTime + 0.0, duration: 1.5),
      Note(freq: C4, start: currentTime + 1.5, duration: 1.5),
      Note(freq: E4, start: currentTime + 3.0, duration: 1.5),
      Note(freq: A3, start: currentTime + 4.5, duration: 1.5),
      Note(freq: G3, start: currentTime + 6.0, duration: 1.5),
      Note(freq: D4, start: currentTime + 7.5, duration: 2.0),
      Note(freq: F4, start: currentTime + 9.5, duration: 2.5)
    ]
  )
  result.add(sectionB)
  currentTime += sectionB.duration
  
  # OUTRO - Gentle close (14 seconds)
  var outro = Section(
    name: "Outro",
    startTime: currentTime,
    duration: 14.0,
    melody: @[
      Note(freq: G5, start: currentTime + 0.0, duration: 2.0),
      Note(freq: E5, start: currentTime + 2.5, duration: 2.0),
      Note(freq: REST, start: currentTime + 4.5, duration: 1.5),
      Note(freq: C5, start: currentTime + 6.0, duration: 3.0),
      Note(freq: REST, start: currentTime + 9.0, duration: 5.0)
    ],
    bass: @[
      Note(freq: C4, start: currentTime + 0.0, duration: 4.0),
      Note(freq: G4, start: currentTime + 4.0, duration: 5.0),
      Note(freq: C4, start: currentTime + 9.0, duration: 5.0)
    ],
    harmony: @[
      Note(freq: E4, start: currentTime + 0.0, duration: 5.0),
      Note(freq: REST, start: currentTime + 5.0, duration: 1.0),
      Note(freq: G4, start: currentTime + 6.0, duration: 8.0)
    ],
    chords: @[
      Note(freq: C4, start: currentTime + 0.0, duration: 2.5),
      Note(freq: E4, start: currentTime + 2.5, duration: 2.5),
      Note(freq: G3, start: currentTime + 5.0, duration: 2.5),
      Note(freq: C4, start: currentTime + 7.5, duration: 6.5)
    ]
  )
  result.add(outro)

proc createPowerUpMusic(filename: string): Music =
  let sections = createPowerUpMusicSections()
  var samples = newSeq[float32](int(MUSIC_DURATION * SAMPLE_RATE.float32))
  
  for section in sections:
    # Uplifting but gentle and unobtrusive
    renderNotes(section.melody, samples, inMelody, 0.13)
    renderNotes(section.bass, samples, inBass, 0.16)
    renderNotes(section.harmony, samples, inPad, 0.08)
    renderChords(section.chords, samples, 0.19)  # Bright piano chords
    applySectionDynamics(samples, section, 0.7)
  
  # Convert to int16 with final gentle limiting
  var samples16 = newSeq[int16](samples.len)
  for i in 0..<samples.len:
    # Apply soft compression to prevent any harshness
    let compressed = if samples[i] > 0.0:
      samples[i] * (1.0 - samples[i] * 0.3)
    else:
      samples[i] * (1.0 + samples[i] * 0.3)
    
    samples16[i] = int16(clamp(compressed * 32767.0 * 0.6, -32767.0, 32767.0))
  
  writeWavFile(filename, samples16, SAMPLE_RATE)
  result = loadMusicStream(filename)

# BOSS MUSIC

proc createBossMusicSections(): seq[Section] =
  result = @[]
  var currentTime = 0.0'f32
  
  # INTRO - Immediate aggressive frenzy (8 seconds)
  var intro = Section(
    name: "Intro",
    startTime: currentTime,
    duration: 8.0,
    melody: @[
      Note(freq: D5, start: currentTime + 0.0, duration: 0.2),
      Note(freq: F5, start: currentTime + 0.2, duration: 0.2),
      Note(freq: D5, start: currentTime + 0.4, duration: 0.2),
      Note(freq: A5, start: currentTime + 0.6, duration: 0.2),
      Note(freq: G5, start: currentTime + 0.8, duration: 0.4),
      Note(freq: F5, start: currentTime + 1.2, duration: 0.2),
      Note(freq: E5, start: currentTime + 1.4, duration: 0.2),
      Note(freq: D5, start: currentTime + 1.6, duration: 0.4),
      Note(freq: A5, start: currentTime + 2.0, duration: 0.2),
      Note(freq: G5, start: currentTime + 2.2, duration: 0.2),
      Note(freq: F5, start: currentTime + 2.4, duration: 0.2),
      Note(freq: D5, start: currentTime + 2.6, duration: 0.2),
      Note(freq: E5, start: currentTime + 2.8, duration: 0.4),
      Note(freq: F5, start: currentTime + 3.2, duration: 0.2),
      Note(freq: A5, start: currentTime + 3.4, duration: 0.2),
      Note(freq: G5, start: currentTime + 3.6, duration: 0.4),
      Note(freq: D5, start: currentTime + 4.0, duration: 0.2),
      Note(freq: F5, start: currentTime + 4.2, duration: 0.2),
      Note(freq: A5, start: currentTime + 4.4, duration: 0.2),
      Note(freq: G5, start: currentTime + 4.6, duration: 0.2),
      Note(freq: F5, start: currentTime + 4.8, duration: 0.4),
      Note(freq: E5, start: currentTime + 5.2, duration: 0.2),
      Note(freq: D5, start: currentTime + 5.4, duration: 0.2),
      Note(freq: F5, start: currentTime + 5.6, duration: 0.4),
      Note(freq: A5, start: currentTime + 6.0, duration: 0.5),
      Note(freq: G5, start: currentTime + 6.5, duration: 0.5),
      Note(freq: F5, start: currentTime + 7.0, duration: 1.0)
    ],
    bass: @[
      Note(freq: D4, start: currentTime + 0.0, duration: 0.4),
      Note(freq: D4, start: currentTime + 0.4, duration: 0.4),
      Note(freq: D4, start: currentTime + 0.8, duration: 0.4),
      Note(freq: A4, start: currentTime + 1.2, duration: 0.4),
      Note(freq: D4, start: currentTime + 1.6, duration: 0.4),
      Note(freq: A4, start: currentTime + 2.0, duration: 0.4),
      Note(freq: D4, start: currentTime + 2.4, duration: 0.4),
      Note(freq: D4, start: currentTime + 2.8, duration: 0.4),
      Note(freq: F4, start: currentTime + 3.2, duration: 0.4),
      Note(freq: A4, start: currentTime + 3.6, duration: 0.4),
      Note(freq: D4, start: currentTime + 4.0, duration: 0.4),
      Note(freq: D4, start: currentTime + 4.4, duration: 0.4),
      Note(freq: F4, start: currentTime + 4.8, duration: 0.4),
      Note(freq: F4, start: currentTime + 5.2, duration: 0.4),
      Note(freq: A4, start: currentTime + 5.6, duration: 0.4),
      Note(freq: D4, start: currentTime + 6.0, duration: 2.0)
    ],
    harmony: @[
      Note(freq: F4, start: currentTime + 0.0, duration: 2.0),
      Note(freq: A4, start: currentTime + 2.0, duration: 2.0),
      Note(freq: F4, start: currentTime + 4.0, duration: 2.0),
      Note(freq: A4, start: currentTime + 6.0, duration: 2.0)
    ],
    chords: @[
      Note(freq: D4, start: currentTime + 0.0, duration: 0.5),
      Note(freq: D4, start: currentTime + 0.5, duration: 0.5),
      Note(freq: A3, start: currentTime + 1.0, duration: 0.5),
      Note(freq: F4, start: currentTime + 1.5, duration: 0.5),
      Note(freq: D4, start: currentTime + 2.0, duration: 1.0),
      Note(freq: A3, start: currentTime + 3.0, duration: 1.0),
      Note(freq: D4, start: currentTime + 4.0, duration: 1.0),
      Note(freq: F4, start: currentTime + 5.0, duration: 1.0),
      Note(freq: D4, start: currentTime + 6.0, duration: 2.0)
    ]
  )
  result.add(intro)
  currentTime += intro.duration
  
  # SECTION A - Maximum intensity with rapid-fire notes (14 seconds)
  var sectionA = Section(
    name: "Aggression",
    startTime: currentTime,
    duration: 14.0,
    melody: @[
      Note(freq: D5, start: currentTime + 0.0, duration: 0.2),
      Note(freq: F5, start: currentTime + 0.2, duration: 0.2),
      Note(freq: A5, start: currentTime + 0.4, duration: 0.4),
      Note(freq: G5, start: currentTime + 0.8, duration: 0.2),
      Note(freq: F5, start: currentTime + 1.0, duration: 0.2),
      Note(freq: D5, start: currentTime + 1.2, duration: 0.2),
      Note(freq: A5, start: currentTime + 1.4, duration: 0.2),
      Note(freq: G5, start: currentTime + 1.6, duration: 0.4),
      Note(freq: F5, start: currentTime + 2.0, duration: 0.2),
      Note(freq: E5, start: currentTime + 2.2, duration: 0.2),
      Note(freq: D5, start: currentTime + 2.4, duration: 0.2),
      Note(freq: F5, start: currentTime + 2.6, duration: 0.2),
      Note(freq: A5, start: currentTime + 2.8, duration: 0.4),
      Note(freq: G5, start: currentTime + 3.2, duration: 0.2),
      Note(freq: F5, start: currentTime + 3.4, duration: 0.2),
      Note(freq: D5, start: currentTime + 3.6, duration: 0.4),
      Note(freq: E5, start: currentTime + 4.0, duration: 0.2),
      Note(freq: F5, start: currentTime + 4.2, duration: 0.2),
      Note(freq: A5, start: currentTime + 4.4, duration: 0.2),
      Note(freq: G5, start: currentTime + 4.6, duration: 0.2),
      Note(freq: F5, start: currentTime + 4.8, duration: 0.4),
      Note(freq: D5, start: currentTime + 5.2, duration: 0.2),
      Note(freq: E5, start: currentTime + 5.4, duration: 0.2),
      Note(freq: F5, start: currentTime + 5.6, duration: 0.4),
      Note(freq: A5, start: currentTime + 6.0, duration: 0.2),
      Note(freq: G5, start: currentTime + 6.2, duration: 0.2),
      Note(freq: F5, start: currentTime + 6.4, duration: 0.2),
      Note(freq: E5, start: currentTime + 6.6, duration: 0.2),
      Note(freq: D5, start: currentTime + 6.8, duration: 0.4),
      Note(freq: F5, start: currentTime + 7.2, duration: 0.2),
      Note(freq: A5, start: currentTime + 7.4, duration: 0.2),
      Note(freq: G5, start: currentTime + 7.6, duration: 0.4),
      Note(freq: D5, start: currentTime + 8.0, duration: 0.2),
      Note(freq: F5, start: currentTime + 8.2, duration: 0.2),
      Note(freq: A5, start: currentTime + 8.4, duration: 0.4),
      Note(freq: G5, start: currentTime + 8.8, duration: 0.4),
      Note(freq: F5, start: currentTime + 9.2, duration: 0.2),
      Note(freq: E5, start: currentTime + 9.4, duration: 0.2),
      Note(freq: D5, start: currentTime + 9.6, duration: 0.4),
      Note(freq: A5, start: currentTime + 10.0, duration: 0.5),
      Note(freq: G5, start: currentTime + 10.5, duration: 0.5),
      Note(freq: F5, start: currentTime + 11.0, duration: 0.75),
      Note(freq: D5, start: currentTime + 11.75, duration: 0.75),
      Note(freq: F5, start: currentTime + 12.5, duration: 0.5),
      Note(freq: A5, start: currentTime + 13.0, duration: 1.0)
    ],
    bass: @[
      Note(freq: D4, start: currentTime + 0.0, duration: 0.4),
      Note(freq: D4, start: currentTime + 0.4, duration: 0.4),
      Note(freq: A4, start: currentTime + 0.8, duration: 0.4),
      Note(freq: A4, start: currentTime + 1.2, duration: 0.4),
      Note(freq: D4, start: currentTime + 1.6, duration: 0.4),
      Note(freq: F4, start: currentTime + 2.0, duration: 0.4),
      Note(freq: D4, start: currentTime + 2.4, duration: 0.4),
      Note(freq: A4, start: currentTime + 2.8, duration: 0.4),
      Note(freq: F4, start: currentTime + 3.2, duration: 0.4),
      Note(freq: D4, start: currentTime + 3.6, duration: 0.4),
      Note(freq: D4, start: currentTime + 4.0, duration: 0.4),
      Note(freq: F4, start: currentTime + 4.4, duration: 0.4),
      Note(freq: A4, start: currentTime + 4.8, duration: 0.8),
      Note(freq: D4, start: currentTime + 5.6, duration: 0.4),
      Note(freq: F4, start: currentTime + 6.0, duration: 0.5),
      Note(freq: A4, start: currentTime + 6.5, duration: 0.5),
      Note(freq: D4, start: currentTime + 7.0, duration: 0.5),
      Note(freq: D4, start: currentTime + 7.5, duration: 0.5),
      Note(freq: F4, start: currentTime + 8.0, duration: 1.0),
      Note(freq: A4, start: currentTime + 9.0, duration: 1.0),
      Note(freq: D4, start: currentTime + 10.0, duration: 4.0)
    ],
    harmony: @[
      Note(freq: F4, start: currentTime + 0.0, duration: 2.0),
      Note(freq: A4, start: currentTime + 2.0, duration: 2.0),
      Note(freq: C5, start: currentTime + 4.0, duration: 2.0),
      Note(freq: F4, start: currentTime + 6.0, duration: 2.0),
      Note(freq: A4, start: currentTime + 8.0, duration: 3.0),
      Note(freq: F4, start: currentTime + 11.0, duration: 3.0)
    ],
    chords: @[
      Note(freq: D4, start: currentTime + 0.0, duration: 0.5),
      Note(freq: A3, start: currentTime + 0.5, duration: 0.5),
      Note(freq: D4, start: currentTime + 1.0, duration: 0.5),
      Note(freq: F4, start: currentTime + 1.5, duration: 0.5),
      Note(freq: A3, start: currentTime + 2.0, duration: 0.75),
      Note(freq: D4, start: currentTime + 2.75, duration: 0.75),
      Note(freq: F4, start: currentTime + 3.5, duration: 0.5),
      Note(freq: D4, start: currentTime + 4.0, duration: 1.0),
      Note(freq: A3, start: currentTime + 5.0, duration: 1.0),
      Note(freq: F4, start: currentTime + 6.0, duration: 1.0),
      Note(freq: D4, start: currentTime + 7.0, duration: 1.5),
      Note(freq: F4, start: currentTime + 8.5, duration: 1.5),
      Note(freq: A3, start: currentTime + 10.0, duration: 4.0)
    ]
  )
  result.add(sectionA)
  currentTime += sectionA.duration
  
  # SECTION B - Different harmonic area but equally frenetic (12 seconds)
  var sectionB = Section(
    name: "Development",
    startTime: currentTime,
    duration: 12.0,
    melody: @[
      Note(freq: A5, start: currentTime + 0.0, duration: 0.2),
      Note(freq: G5, start: currentTime + 0.2, duration: 0.2),
      Note(freq: F5, start: currentTime + 0.4, duration: 0.2),
      Note(freq: E5, start: currentTime + 0.6, duration: 0.2),
      Note(freq: D5, start: currentTime + 0.8, duration: 0.4),
      Note(freq: F5, start: currentTime + 1.2, duration: 0.2),
      Note(freq: A5, start: currentTime + 1.4, duration: 0.2),
      Note(freq: G5, start: currentTime + 1.6, duration: 0.4),
      Note(freq: F5, start: currentTime + 2.0, duration: 0.2),
      Note(freq: E5, start: currentTime + 2.2, duration: 0.2),
      Note(freq: D5, start: currentTime + 2.4, duration: 0.2),
      Note(freq: C5, start: currentTime + 2.6, duration: 0.2),
      Note(freq: D5, start: currentTime + 2.8, duration: 0.4),
      Note(freq: F5, start: currentTime + 3.2, duration: 0.2),
      Note(freq: E5, start: currentTime + 3.4, duration: 0.2),
      Note(freq: D5, start: currentTime + 3.6, duration: 0.4),
      Note(freq: A5, start: currentTime + 4.0, duration: 0.2),
      Note(freq: G5, start: currentTime + 4.2, duration: 0.2),
      Note(freq: F5, start: currentTime + 4.4, duration: 0.2),
      Note(freq: E5, start: currentTime + 4.6, duration: 0.2),
      Note(freq: D5, start: currentTime + 4.8, duration: 0.4),
      Note(freq: C5, start: currentTime + 5.2, duration: 0.2),
      Note(freq: D5, start: currentTime + 5.4, duration: 0.2),
      Note(freq: E5, start: currentTime + 5.6, duration: 0.4),
      Note(freq: F5, start: currentTime + 6.0, duration: 0.2),
      Note(freq: E5, start: currentTime + 6.2, duration: 0.2),
      Note(freq: D5, start: currentTime + 6.4, duration: 0.2),
      Note(freq: C5, start: currentTime + 6.6, duration: 0.2),
      Note(freq: D5, start: currentTime + 6.8, duration: 0.4),
      Note(freq: E5, start: currentTime + 7.2, duration: 0.2),
      Note(freq: F5, start: currentTime + 7.4, duration: 0.2),
      Note(freq: A5, start: currentTime + 7.6, duration: 0.4),
      Note(freq: G5, start: currentTime + 8.0, duration: 0.5),
      Note(freq: F5, start: currentTime + 8.5, duration: 0.5),
      Note(freq: E5, start: currentTime + 9.0, duration: 0.75),
      Note(freq: D5, start: currentTime + 9.75, duration: 0.75),
      Note(freq: F5, start: currentTime + 10.5, duration: 1.5)
    ],
    bass: @[
      Note(freq: F4, start: currentTime + 0.0, duration: 0.4),
      Note(freq: F4, start: currentTime + 0.4, duration: 0.4),
      Note(freq: C4, start: currentTime + 0.8, duration: 0.4),
      Note(freq: C4, start: currentTime + 1.2, duration: 0.4),
      Note(freq: F4, start: currentTime + 1.6, duration: 0.4),
      Note(freq: A4, start: currentTime + 2.0, duration: 0.4),
      Note(freq: C4, start: currentTime + 2.4, duration: 0.4),
      Note(freq: D4, start: currentTime + 2.8, duration: 0.4),
      Note(freq: F4, start: currentTime + 3.2, duration: 0.4),
      Note(freq: D4, start: currentTime + 3.6, duration: 0.4),
      Note(freq: F4, start: currentTime + 4.0, duration: 0.5),
      Note(freq: C4, start: currentTime + 4.5, duration: 0.5),
      Note(freq: D4, start: currentTime + 5.0, duration: 0.5),
      Note(freq: F4, start: currentTime + 5.5, duration: 0.5),
      Note(freq: D4, start: currentTime + 6.0, duration: 1.0),
      Note(freq: F4, start: currentTime + 7.0, duration: 1.0),
      Note(freq: D4, start: currentTime + 8.0, duration: 4.0)
    ],
    harmony: @[
      Note(freq: A4, start: currentTime + 0.0, duration: 2.0),
      Note(freq: E4, start: currentTime + 2.0, duration: 2.0),
      Note(freq: F4, start: currentTime + 4.0, duration: 2.0),
      Note(freq: A4, start: currentTime + 6.0, duration: 2.0),
      Note(freq: F4, start: currentTime + 8.0, duration: 4.0)
    ],
    chords: @[
      Note(freq: F4, start: currentTime + 0.0, duration: 0.75),
      Note(freq: C4, start: currentTime + 0.75, duration: 0.75),
      Note(freq: F4, start: currentTime + 1.5, duration: 0.75),
      Note(freq: A3, start: currentTime + 2.25, duration: 0.75),
      Note(freq: D4, start: currentTime + 3.0, duration: 1.0),
      Note(freq: F4, start: currentTime + 4.0, duration: 1.0),
      Note(freq: A3, start: currentTime + 5.0, duration: 1.0),
      Note(freq: D4, start: currentTime + 6.0, duration: 1.5),
      Note(freq: F4, start: currentTime + 7.5, duration: 1.5),
      Note(freq: D4, start: currentTime + 9.0, duration: 3.0)
    ]
  )
  result.add(sectionB)
  currentTime += sectionB.duration
  
  # OUTRO - Relentless to the end (14 seconds)
  var outro = Section(
    name: "Outro",
    startTime: currentTime,
    duration: 14.0,
    melody: @[
      Note(freq: D5, start: currentTime + 0.0, duration: 0.25),
      Note(freq: F5, start: currentTime + 0.25, duration: 0.25),
      Note(freq: A5, start: currentTime + 0.5, duration: 0.5),
      Note(freq: G5, start: currentTime + 1.0, duration: 0.5),
      Note(freq: F5, start: currentTime + 1.5, duration: 0.5),
      Note(freq: D5, start: currentTime + 2.0, duration: 0.5),
      Note(freq: A5, start: currentTime + 2.5, duration: 0.5),
      Note(freq: G5, start: currentTime + 3.0, duration: 0.5),
      Note(freq: F5, start: currentTime + 3.5, duration: 0.5),
      Note(freq: D5, start: currentTime + 4.0, duration: 0.5),
      Note(freq: F5, start: currentTime + 4.5, duration: 0.5),
      Note(freq: A5, start: currentTime + 5.0, duration: 0.75),
      Note(freq: G5, start: currentTime + 5.75, duration: 0.75),
      Note(freq: F5, start: currentTime + 6.5, duration: 0.75),
      Note(freq: E5, start: currentTime + 7.25, duration: 0.75),
      Note(freq: D5, start: currentTime + 8.0, duration: 1.0),
      Note(freq: F5, start: currentTime + 9.0, duration: 1.0),
      Note(freq: A5, start: currentTime + 10.0, duration: 1.5),
      Note(freq: D5, start: currentTime + 11.5, duration: 2.5)
    ],
    bass: @[
      Note(freq: D4, start: currentTime + 0.0, duration: 0.5),
      Note(freq: D4, start: currentTime + 0.5, duration: 0.5),
      Note(freq: A4, start: currentTime + 1.0, duration: 0.5),
      Note(freq: F4, start: currentTime + 1.5, duration: 0.5),
      Note(freq: D4, start: currentTime + 2.0, duration: 0.5),
      Note(freq: A4, start: currentTime + 2.5, duration: 0.5),
      Note(freq: D4, start: currentTime + 3.0, duration: 0.5),
      Note(freq: F4, start: currentTime + 3.5, duration: 0.5),
      Note(freq: D4, start: currentTime + 4.0, duration: 1.0),
      Note(freq: A4, start: currentTime + 5.0, duration: 1.0),
      Note(freq: F4, start: currentTime + 6.0, duration: 1.0),
      Note(freq: D4, start: currentTime + 7.0, duration: 1.0),
      Note(freq: D4, start: currentTime + 8.0, duration: 6.0)
    ],
    harmony: @[
      Note(freq: F4, start: currentTime + 0.0, duration: 2.0),
      Note(freq: A4, start: currentTime + 2.0, duration: 2.0),
      Note(freq: F4, start: currentTime + 4.0, duration: 2.0),
      Note(freq: A4, start: currentTime + 6.0, duration: 2.0),
      Note(freq: D4, start: currentTime + 8.0, duration: 6.0)
    ],
    chords: @[
      Note(freq: D4, start: currentTime + 0.0, duration: 1.0),
      Note(freq: A3, start: currentTime + 1.0, duration: 1.0),
      Note(freq: F4, start: currentTime + 2.0, duration: 1.0),
      Note(freq: D4, start: currentTime + 3.0, duration: 1.0),
      Note(freq: A3, start: currentTime + 4.0, duration: 1.5),
      Note(freq: D4, start: currentTime + 5.5, duration: 1.5),
      Note(freq: F4, start: currentTime + 7.0, duration: 1.5),
      Note(freq: D4, start: currentTime + 8.5, duration: 5.5)
    ]
  )
  result.add(outro)

proc createBossMusic(filename: string): Music =
  let sections = createBossMusicSections()
  var samples = newSeq[float32](int(MUSIC_DURATION * SAMPLE_RATE.float32))
  
  for section in sections:
    # Intense rhythm but stays in the background
    renderNotes(section.melody, samples, inMelody, 0.15)
    renderNotes(section.bass, samples, inBass, 0.18)
    renderNotes(section.harmony, samples, inPad, 0.10)
    renderChords(section.chords, samples, 0.21)  # Aggressive piano chords
    applySectionDynamics(samples, section, 0.75)
  
  # Convert to int16 with final gentle limiting
  var samples16 = newSeq[int16](samples.len)
  for i in 0..<samples.len:
    # Apply soft compression to prevent any harshness
    let compressed = if samples[i] > 0.0:
      samples[i] * (1.0 - samples[i] * 0.3)
    else:
      samples[i] * (1.0 + samples[i] * 0.3)
    
    samples16[i] = int16(clamp(compressed * 32767.0 * 0.6, -32767.0, 32767.0))
  
  writeWavFile(filename, samples16, SAMPLE_RATE)
  result = loadMusicStream(filename)

# MUSIC LOADING AND SYSTEM MANAGEMENT

proc loadOrGenerateMusic(track: MusicTrack): Music =
  let cacheFile = getMusicCacheFile(track)
  
  if fileExists(cacheFile):
    return loadMusicStream(cacheFile)
  
  case track
  of mtMenu: result = createMenuMusic(cacheFile)
  of mtWave: result = createWaveMusic(cacheFile)
  of mtPowerUp: result = createPowerUpMusic(cacheFile)
  of mtBoss: result = createBossMusic(cacheFile)

# PRE-GENERATION SYSTEM
proc preGenerateAllAssets*(verbose: bool = true, callback: AssetGenerationCallback = nil) =
  let cached = countCachedAssets()
  let totalAssets = SoundType.high.ord + 1 + MusicTrack.high.ord + 1
  
  if cached.total == totalAssets:
    if verbose:
      echo "All ", totalAssets, " assets already cached"
    if not callback.isNil:
      callback(1.0, t(tkLoadingCached))
    return
  
  if verbose:
    echo "=========================================="
    echo "Pre-generating game assets..."
    echo "Cached: ", cached.sounds, "/", SoundType.high.ord + 1, " sounds, ",
         cached.music, "/", MusicTrack.high.ord + 1, " music tracks"
    echo "=========================================="
  
  var assetsGenerated = 0
  let assetsToGenerate = totalAssets - cached.total
  
  for soundType in SoundType:
    if not isSoundCached(soundType):
      if verbose:
        inc assetsGenerated
        let progress = (assetsGenerated.float32 / assetsToGenerate.float32 * 100.0).int
        echo "[", progress, "%] Generating sound: ", soundType, "..."
      
      if not callback.isNil:
        let prog = assetsGenerated.float32 / assetsToGenerate.float32
        callback(prog, t(tkLoadingGeneratingSound) & ": " & $soundType)
      
      discard loadOrGenerateSound(soundType)
  
  for track in MusicTrack:
    if not isMusicCached(track):
      if verbose:
        inc assetsGenerated
        let progress = (assetsGenerated.float32 / assetsToGenerate.float32 * 100.0).int
        echo "[", progress, "%] Generating music: ", track, "..."
      
      if not callback.isNil:
        let prog = assetsGenerated.float32 / assetsToGenerate.float32
        callback(prog, t(tkLoadingGeneratingMusic) & ": " & $track)
      
      discard loadOrGenerateMusic(track)
  
  if verbose:
    echo "=========================================="
    echo "  Asset generation complete!"
    echo "  Total assets: ", totalAssets
    echo "  Cache location: ", getCacheDir()
    echo "=========================================="
  
  if not callback.isNil:
    callback(1.0, t(tkLoadingComplete))

proc generateAllSounds(sys: SoundSystem) =
  if sys.soundsGenerated:
    return
  
  echo "Loading procedural sounds into memory..."
  try:
    for st in SoundType:
      sys.cachedSounds[st] = loadOrGenerateSound(st)
    sys.soundsGenerated = true
    echo "All sounds loaded successfully!"
  except Exception as e:
    echo "ERROR loading sounds: ", e.msg
    sys.soundsGenerated = false

# SYSTEM INITIALIZATION AND MANAGEMENT
proc initSoundSystem*(callback: AssetGenerationCallback = nil): SoundSystem =
  echo "Initializing sound system..."
  try:
    initAudioDevice()
    if not isAudioDeviceReady():
      echo "WARNING: Audio device not ready!"
      return SoundSystem(enabled: false, masterVolume: 0.5, musicVolume: 0.5, initialized: false)
    
    result = SoundSystem(
      enabled: true,
      masterVolume: 0.5,
      musicVolume: 0.5,
      initialized: true,
      soundsGenerated: false,
      trackPlaying: false
    )
    
    globalSoundSystem = result
    preGenerateAllAssets(verbose = true, callback = callback)
    generateAllSounds(result)
    
    echo "Sound system initialized!"
  except Exception as e:
    echo "ERROR initializing sound system: ", e.msg
    return SoundSystem(enabled: false, masterVolume: 0.5, musicVolume: 0.5, initialized: false)

proc closeSoundSystem*(sys: SoundSystem) =
  if sys != nil and sys.initialized:
    closeAudioDevice()
    echo "Sound system closed"

# PLAYBACK FUNCTIONS
proc playSound*(soundType: SoundType, volumeMultiplier: float32 = 1.0) =
  if globalSoundSystem == nil or not globalSoundSystem.enabled or not globalSoundSystem.soundsGenerated:
    return
  try:
    setSoundVolume(globalSoundSystem.cachedSounds[soundType], globalSoundSystem.masterVolume * volumeMultiplier)
    raylib.playSound(globalSoundSystem.cachedSounds[soundType])
  except:
    discard

proc setGameVolume*(volume: float32) =
  if globalSoundSystem != nil:
    globalSoundSystem.masterVolume = clamp(volume, 0.0, 1.0)

proc getGameVolume*(): float32 =
  if globalSoundSystem != nil: globalSoundSystem.masterVolume else: 0.5

proc toggleSound*() =
  if globalSoundSystem != nil:
    globalSoundSystem.enabled = not globalSoundSystem.enabled

proc playMusic*(track: MusicTrack) =
  if globalSoundSystem == nil or not globalSoundSystem.enabled:
    return
  
  try:
    if globalSoundSystem.trackPlaying and globalSoundSystem.currentTrack != track:
      stopMusicStream(globalSoundSystem.cachedMusic[globalSoundSystem.currentTrack])
      globalSoundSystem.trackPlaying = false
    
    if not globalSoundSystem.musicGenerated[track]:
      globalSoundSystem.cachedMusic[track] = loadOrGenerateMusic(track)
      globalSoundSystem.musicGenerated[track] = true
    
    if not globalSoundSystem.trackPlaying or globalSoundSystem.currentTrack != track:
      setMusicVolume(globalSoundSystem.cachedMusic[track], globalSoundSystem.musicVolume)
      playMusicStream(globalSoundSystem.cachedMusic[track])
      globalSoundSystem.currentTrack = track
      globalSoundSystem.trackPlaying = true
  except:
    discard

proc updateMusic*() =
  if globalSoundSystem == nil or not globalSoundSystem.enabled or not globalSoundSystem.trackPlaying:
    return
  try:
    updateMusicStream(globalSoundSystem.cachedMusic[globalSoundSystem.currentTrack])
    # Manually restart if music stopped (seamless looping)
    if not isMusicStreamPlaying(globalSoundSystem.cachedMusic[globalSoundSystem.currentTrack]):
      seekMusicStream(globalSoundSystem.cachedMusic[globalSoundSystem.currentTrack], 0.0)
      playMusicStream(globalSoundSystem.cachedMusic[globalSoundSystem.currentTrack])
  except:
    discard

proc stopMusic*() =
  if globalSoundSystem == nil or not globalSoundSystem.trackPlaying:
    return
  try:
    stopMusicStream(globalSoundSystem.cachedMusic[globalSoundSystem.currentTrack])
    globalSoundSystem.trackPlaying = false
  except:
    discard

proc setMusicVolume*(volume: float32) =
  if globalSoundSystem != nil:
    globalSoundSystem.musicVolume = clamp(volume, 0.0, 1.0)
    if globalSoundSystem.trackPlaying:
      try:
        setMusicVolume(globalSoundSystem.cachedMusic[globalSoundSystem.currentTrack],
                      globalSoundSystem.musicVolume)
      except:
        discard

proc getMusicVolume*(): float32 =
  if globalSoundSystem != nil: globalSoundSystem.musicVolume else: 0.5
