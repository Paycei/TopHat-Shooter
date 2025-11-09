import raylib, math, random, os, streams

type
  SoundType* = enum
    stShoot, stEnemyHit, stEnemyDeath, stPlayerHit, stCoinPickup, stPowerUp,
    stBossSpawn, stExplosion, stWallPlace, stTeleport, stMenuNav, stMenuSelect,
    stWaveComplete, stShield, stGameOver

  MusicTrack* = enum
    mtMenu,         # Main menu theme
    mtWave,         # During wave combat
    mtPowerUp,      # Power-up/shop selection
    mtBoss          # Boss fight music

  SoundSystem* = ref object
    enabled*: bool
    masterVolume*: float32
    musicVolume*: float32
    initialized: bool
    cachedSounds: array[SoundType, Sound]
    soundsGenerated: bool
    cachedMusic: array[MusicTrack, Music]
    musicGenerated: bool
    currentTrack: MusicTrack
    trackPlaying: bool

var globalSoundSystem*: SoundSystem

# ADSR Envelope generator
proc applyADSR(progress: float32, attack, decay, sustain, release: float32): float32 =
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

# Add harmonics for richer sound
proc generateHarmonics(t: float32, baseFreq: float32, harmonics: seq[tuple[mult: float32, amp: float32]]): float32 =
  result = 0.0
  for h in harmonics:
    result += sin(2.0 * PI * baseFreq * h.mult * t) * h.amp

# Write proper WAV file
proc writeWavFile(filename: string, samples: seq[int16], sampleRate: uint32) =
  let tempPath = getTempDir() / filename
  var stream = newFileStream(tempPath, fmWrite)
  if stream == nil:
    raise newException(IOError, "Could not create temp WAV file")
  
  defer: stream.close()
  
  let numSamples = samples.len
  let dataSize = numSamples * 2  # 2 bytes per sample
  let fileSize = 36 + dataSize
  
  # RIFF header
  stream.write("RIFF")
  stream.write(uint32(fileSize))
  stream.write("WAVE")
  
  # fmt chunk
  stream.write("fmt ")
  stream.write(uint32(16))        # SubChunk1Size
  stream.write(uint16(1))         # AudioFormat (PCM)
  stream.write(uint16(1))         # NumChannels (mono)
  stream.write(uint32(sampleRate))
  stream.write(uint32(sampleRate * 2))  # ByteRate
  stream.write(uint16(2))         # BlockAlign
  stream.write(uint16(16))        # BitsPerSample
  
  # data chunk
  stream.write("data")
  stream.write(uint32(dataSize))
  
  # Write samples
  for sample in samples:
    stream.write(sample)

# Enhanced laser shoot sound with harmonics
proc createLaserShoot(filename: string): Sound =
  let sampleRate: uint32 = 44100
  let duration = 0.12
  let frameCount = int(sampleRate.float32 * duration)
  var samples = newSeq[int16](frameCount)
  
  # Laser-like sweep with harmonics
  for i in 0..<frameCount:
    let t = i.float32 / sampleRate.float32
    let progress = t / duration
    
    # Pitch sweep from high to low
    let freq = 1200.0 * exp(-progress * 4.0) + 400.0
    
    # ADSR envelope for more natural sound
    let envelope = applyADSR(progress, 0.05, 0.15, 0.3, 0.3)
    
    # Add harmonics for richer sound
    let harmonics = @[
      (mult: 1.0'f32, amp: 0.6'f32),
      (mult: 2.0'f32, amp: 0.25'f32),
      (mult: 3.0'f32, amp: 0.1'f32),
      (mult: 4.0'f32, amp: 0.05'f32)
    ]
    
    let value = generateHarmonics(t, freq, harmonics)
    samples[i] = int16(value * envelope * 0.4 * 32767.0)
  
  writeWavFile(filename, samples, sampleRate)
  let tempPath = getTempDir() / filename
  result = loadSound(tempPath)

# Punchy impact sound with noise burst
proc createImpactHit(filename: string): Sound =
  let sampleRate: uint32 = 44100
  let duration = 0.15
  let frameCount = int(sampleRate.float32 * duration)
  var samples = newSeq[int16](frameCount)
  
  for i in 0..<frameCount:
    let t = i.float32 / sampleRate.float32
    let progress = t / duration
    
    # Sharp attack with quick decay
    let envelope = exp(-progress * 15.0)
    
    # Mix of noise and low frequency thump
    let noise = rand(-1.0..1.0) * 0.4
    let thump = sin(2.0 * PI * 80.0 * t * exp(-progress * 8.0)) * 0.6
    
    let value = (noise + thump) * envelope
    samples[i] = int16(value * 32767.0)
  
  writeWavFile(filename, samples, sampleRate)
  let tempPath = getTempDir() / filename
  result = loadSound(tempPath)

# Enemy death with dramatic sweep and distortion
proc createEnemyDeath(filename: string): Sound =
  let sampleRate: uint32 = 44100
  let duration = 0.4
  let frameCount = int(sampleRate.float32 * duration)
  var samples = newSeq[int16](frameCount)
  
  for i in 0..<frameCount:
    let t = i.float32 / sampleRate.float32
    let progress = t / duration
    
    # Dramatic sweep down
    let freq = 800.0 * exp(-progress * 3.5) + 50.0
    
    # Slower decay for more dramatic effect
    let envelope = exp(-progress * 3.0)
    
    # Add slight distortion/crunch
    let baseValue = sin(2.0 * PI * freq * t)
    let harmonicNoise = sin(2.0 * PI * freq * 2.3 * t) * 0.2
    let value = (baseValue + harmonicNoise) * envelope
    
    samples[i] = int16(value * 0.45 * 32767.0)
  
  writeWavFile(filename, samples, sampleRate)
  let tempPath = getTempDir() / filename
  result = loadSound(tempPath)

# Player hit with alarm-like sound
proc createPlayerHit(filename: string): Sound =
  let sampleRate: uint32 = 44100
  let duration = 0.2
  let frameCount = int(sampleRate.float32 * duration)
  var samples = newSeq[int16](frameCount)
  
  for i in 0..<frameCount:
    let t = i.float32 / sampleRate.float32
    let progress = t / duration
    
    # Pulsing alarm sound
    let freq = 180.0
    let pulseRate = 15.0
    let pulse = sin(2.0 * PI * pulseRate * t) * 0.5 + 0.5
    
    let envelope = exp(-progress * 5.0)
    let value = sin(2.0 * PI * freq * t) * pulse * envelope
    
    samples[i] = int16(value * 0.5 * 32767.0)
  
  writeWavFile(filename, samples, sampleRate)
  let tempPath = getTempDir() / filename
  result = loadSound(tempPath)

# Coin pickup with bright sparkle
proc createCoinPickup(filename: string): Sound =
  let sampleRate: uint32 = 44100
  let duration = 0.2
  let frameCount = int(sampleRate.float32 * duration)
  var samples = newSeq[int16](frameCount)
  
  for i in 0..<frameCount:
    let t = i.float32 / sampleRate.float32
    let progress = t / duration
    
    # Upward arpeggio: C5 -> E5 -> G5
    var freq = 523.25  # C5
    if progress > 0.33:
      freq = 659.25  # E5
    if progress > 0.66:
      freq = 783.99  # G5
    
    # Quick bright attack
    let envelope = applyADSR(progress, 0.1, 0.2, 0.4, 0.3)
    
    # Bright harmonics
    let harmonics = @[
      (mult: 1.0'f32, amp: 0.5'f32),
      (mult: 2.0'f32, amp: 0.3'f32),
      (mult: 3.0'f32, amp: 0.15'f32),
      (mult: 4.0'f32, amp: 0.05'f32)
    ]
    
    let value = generateHarmonics(t, freq, harmonics)
    samples[i] = int16(value * envelope * 0.35 * 32767.0)
  
  writeWavFile(filename, samples, sampleRate)
  let tempPath = getTempDir() / filename
  result = loadSound(tempPath)

# Power-up with ascending chord and shimmer
proc createPowerUp(filename: string): Sound =
  let sampleRate: uint32 = 44100
  let duration = 0.5
  let frameCount = int(sampleRate.float32 * duration)
  var samples = newSeq[int16](frameCount)
  
  for i in 0..<frameCount:
    let t = i.float32 / sampleRate.float32
    let progress = t / duration
    
    # Major chord with slight pitch rise
    let pitchRise = 1.0 + progress * 0.1
    let freq1 = 523.25 * pitchRise  # C5
    let freq2 = 659.25 * pitchRise  # E5
    let freq3 = 783.99 * pitchRise  # G5
    
    # Add shimmer with vibrato
    let vibrato = 1.0 + sin(2.0 * PI * 6.0 * t) * 0.01
    
    let envelope = applyADSR(progress, 0.1, 0.2, 0.6, 0.1)
    
    let value = (sin(2.0 * PI * freq1 * vibrato * t) * 0.4 + 
                 sin(2.0 * PI * freq2 * vibrato * t) * 0.3 + 
                 sin(2.0 * PI * freq3 * vibrato * t) * 0.3)
    
    samples[i] = int16(value * envelope * 0.4 * 32767.0)
  
  writeWavFile(filename, samples, sampleRate)
  let tempPath = getTempDir() / filename
  result = loadSound(tempPath)

# Boss spawn with ominous rumble and rise
proc createBossSpawn(filename: string): Sound =
  let sampleRate: uint32 = 44100
  let duration = 1.2
  let frameCount = int(sampleRate.float32 * duration)
  var samples = newSeq[int16](frameCount)
  
  for i in 0..<frameCount:
    let t = i.float32 / sampleRate.float32
    let progress = t / duration
    
    # Deep rumble that rises
    let baseFreq = 40.0 + progress * 120.0
    
    # Ominous tremolo
    let tremolo = 0.7 + sin(2.0 * PI * 8.0 * t) * 0.3
    
    # Build intensity over time
    let envelope = min(1.0, progress * 2.0) * exp(-max(0.0, progress - 0.5) * 2.0)
    
    # Layer sub-bass with harmonics
    let subBass = sin(2.0 * PI * baseFreq * t) * 0.5
    let harmonic1 = sin(2.0 * PI * baseFreq * 2.0 * t) * 0.25
    let harmonic2 = sin(2.0 * PI * baseFreq * 3.0 * t) * 0.15
    
    let value = (subBass + harmonic1 + harmonic2) * tremolo * envelope
    samples[i] = int16(value * 0.5 * 32767.0)
  
  writeWavFile(filename, samples, sampleRate)
  let tempPath = getTempDir() / filename
  result = loadSound(tempPath)

# Explosion with deep impact and satisfying boom
proc createExplosion(filename: string): Sound =
  let sampleRate: uint32 = 44100
  let duration = 0.5
  let frameCount = int(sampleRate.float32 * duration)
  var samples = newSeq[int16](frameCount)
  
  for i in 0..<frameCount:
    let t = i.float32 / sampleRate.float32
    let progress = t / duration
    
    # Sharp attack, moderate decay for impact
    let envelope = exp(-progress * 6.0)
    
    # Deep bass boom that decays quickly
    let boomFreq = 70.0 * exp(-progress * 8.0)
    let boom = sin(2.0 * PI * boomFreq * t) * 0.6
    
    # Add slight mid-range punch for clarity
    let punchFreq = 200.0 * exp(-progress * 10.0)
    let punch = sin(2.0 * PI * punchFreq * t) * 0.3
    
    # Slight crisp noise at the start for impact
    let noiseAmount = if progress < 0.1: 0.3 else: 0.1
    let noise = rand(-1.0..1.0) * noiseAmount * exp(-progress * 15.0)
    
    let value = (boom + punch + noise) * envelope
    samples[i] = int16(value * 0.6 * 32767.0)
  
  writeWavFile(filename, samples, sampleRate)
  let tempPath = getTempDir() / filename
  result = loadSound(tempPath)

# Wall placement with solid thunk
proc createWallPlace(filename: string): Sound =
  let sampleRate: uint32 = 44100
  let duration = 0.25
  let frameCount = int(sampleRate.float32 * duration)
  var samples = newSeq[int16](frameCount)
  
  for i in 0..<frameCount:
    let t = i.float32 / sampleRate.float32
    let progress = t / duration
    
    # Solid thunk sound
    let freq = 120.0 * exp(-progress * 8.0)
    let envelope = exp(-progress * 10.0)
    
    # Mix tone with slight noise for texture
    let tone = sin(2.0 * PI * freq * t) * 0.7
    let texture = rand(-1.0..1.0) * 0.3 * exp(-progress * 20.0)
    
    let value = (tone + texture) * envelope
    samples[i] = int16(value * 0.45 * 32767.0)
  
  writeWavFile(filename, samples, sampleRate)
  let tempPath = getTempDir() / filename
  result = loadSound(tempPath)

# Teleport with sci-fi whoosh
proc createTeleport(filename: string): Sound =
  let sampleRate: uint32 = 44100
  let duration = 0.4
  let frameCount = int(sampleRate.float32 * duration)
  var samples = newSeq[int16](frameCount)
  
  for i in 0..<frameCount:
    let t = i.float32 / sampleRate.float32
    let progress = t / duration
    
    # Down then up sweep
    let sweepPhase = if progress < 0.5: progress * 2.0 else: 1.0 - (progress - 0.5) * 2.0
    let freq = 1500.0 + sin(sweepPhase * PI) * 1000.0
    
    # Add modulation for sci-fi effect
    let modulation = sin(2.0 * PI * 30.0 * t) * 0.3 + 1.0
    
    let envelope = sin(progress * PI)  # Fade in and out
    
    let value = sin(2.0 * PI * freq * modulation * t) * envelope
    samples[i] = int16(value * 0.35 * 32767.0)
  
  writeWavFile(filename, samples, sampleRate)
  let tempPath = getTempDir() / filename
  result = loadSound(tempPath)

# Menu navigation - subtle click
proc createMenuNav(filename: string): Sound =
  let sampleRate: uint32 = 44100
  let duration = 0.06
  let frameCount = int(sampleRate.float32 * duration)
  var samples = newSeq[int16](frameCount)
  
  for i in 0..<frameCount:
    let t = i.float32 / sampleRate.float32
    let progress = t / duration
    
    # Quick high-pitched click
    let freq = 800.0
    let envelope = exp(-progress * 30.0)
    
    let value = sin(2.0 * PI * freq * t) * envelope
    samples[i] = int16(value * 0.3 * 32767.0)
  
  writeWavFile(filename, samples, sampleRate)
  let tempPath = getTempDir() / filename
  result = loadSound(tempPath)

# Menu select - confirmation beep
proc createMenuSelect(filename: string): Sound =
  let sampleRate: uint32 = 44100
  let duration = 0.25
  let frameCount = int(sampleRate.float32 * duration)
  var samples = newSeq[int16](frameCount)
  
  for i in 0..<frameCount:
    let t = i.float32 / sampleRate.float32
    let progress = t / duration
    
    # Two-tone confirmation: high then low
    let freq = if progress < 0.4: 600.0 else: 450.0
    
    let envelope = applyADSR(progress, 0.1, 0.2, 0.5, 0.2)
    let value = sin(2.0 * PI * freq * t) * envelope
    
    samples[i] = int16(value * 0.35 * 32767.0)
  
  writeWavFile(filename, samples, sampleRate)
  let tempPath = getTempDir() / filename
  result = loadSound(tempPath)

# Wave complete - triumphant fanfare
proc createWaveComplete(filename: string): Sound =
  let sampleRate: uint32 = 44100
  let duration = 0.8
  let frameCount = int(sampleRate.float32 * duration)
  var samples = newSeq[int16](frameCount)
  
  for i in 0..<frameCount:
    let t = i.float32 / sampleRate.float32
    let progress = t / duration
    
    # Ascending arpeggio: C5 -> E5 -> G5 -> C6
    var freq = 523.25  # C5
    if progress > 0.25:
      freq = 659.25  # E5
    if progress > 0.5:
      freq = 783.99  # G5
    if progress > 0.75:
      freq = 1046.50  # C6
    
    let envelope = applyADSR(progress, 0.1, 0.15, 0.7, 0.05)
    
    # Rich harmonics for celebration
    let harmonics = @[
      (mult: 1.0'f32, amp: 0.5'f32),
      (mult: 2.0'f32, amp: 0.25'f32),
      (mult: 3.0'f32, amp: 0.15'f32),
      (mult: 4.0'f32, amp: 0.1'f32)
    ]
    
    let value = generateHarmonics(t, freq, harmonics)
    samples[i] = int16(value * envelope * 0.4 * 32767.0)
  
  writeWavFile(filename, samples, sampleRate)
  let tempPath = getTempDir() / filename
  result = loadSound(tempPath)

# Shield with protective hum
proc createShield(filename: string): Sound =
  let sampleRate: uint32 = 44100
  let duration = 0.35
  let frameCount = int(sampleRate.float32 * duration)
  var samples = newSeq[int16](frameCount)
  
  for i in 0..<frameCount:
    let t = i.float32 / sampleRate.float32
    let progress = t / duration
    
    # Protective humming sound
    let baseFreq = 280.0
    
    # Slight warble for energy field effect
    let warble = sin(2.0 * PI * 7.0 * t) * 20.0
    let freq = baseFreq + warble
    
    let envelope = applyADSR(progress, 0.15, 0.2, 0.5, 0.15)
    
    # Mix of fundamental and harmonics
    let fundamental = sin(2.0 * PI * freq * t) * 0.5
    let harmonic = sin(2.0 * PI * freq * 2.0 * t) * 0.3
    
    let value = (fundamental + harmonic) * envelope
    samples[i] = int16(value * 0.4 * 32767.0)
  
  writeWavFile(filename, samples, sampleRate)
  let tempPath = getTempDir() / filename
  result = loadSound(tempPath)

# ============================================================================
# BACKGROUND MUSIC GENERATION
# ============================================================================

# Generate a looping music track with melody and harmony
proc generateMusicTrack(filename: string, bpm: float32, measures: int, 
                       melody: seq[float32], harmony: seq[float32], 
                       bassline: seq[float32]) =
  let sampleRate: uint32 = 44100
  let beatsPerMeasure = 4
  let secondsPerBeat = 60.0 / bpm
  let duration = measures.float32 * beatsPerMeasure.float32 * secondsPerBeat
  let frameCount = int(sampleRate.float32 * duration)
  var samples = newSeq[int16](frameCount)
  
  let beatLength = int(sampleRate.float32 * secondsPerBeat)
  
  for i in 0..<frameCount:
    let t = i.float32 / sampleRate.float32
    let beatIndex = (i div beatLength) mod (measures * beatsPerMeasure)
    let noteIndex = beatIndex mod melody.len
    
    # Progress within current beat for envelope
    let beatProgress = (i mod beatLength).float32 / beatLength.float32
    
    # Melody (lead synth)
    let melodyFreq = melody[noteIndex]
    let melodyEnv = applyADSR(beatProgress, 0.05, 0.1, 0.7, 0.15)
    let melodyValue = if melodyFreq > 0:
      sin(2.0 * PI * melodyFreq * t) * 0.25 * melodyEnv
    else:
      0.0
    
    # Harmony (pad)
    let harmonyFreq = harmony[noteIndex mod harmony.len]
    let harmonyValue = if harmonyFreq > 0:
      sin(2.0 * PI * harmonyFreq * t) * 0.15 +
      sin(2.0 * PI * harmonyFreq * 1.5 * t) * 0.08
    else:
      0.0
    
    # Bassline (sub bass)
    let bassFreq = bassline[noteIndex mod bassline.len]
    let bassEnv = applyADSR(beatProgress, 0.02, 0.15, 0.5, 0.33)
    let bassValue = if bassFreq > 0:
      sin(2.0 * PI * bassFreq * t) * 0.35 * bassEnv
    else:
      0.0
    
    # Mix all layers
    let value = melodyValue + harmonyValue + bassValue
    samples[i] = int16(clamp(value * 32767.0, -32767.0, 32767.0))
  
  writeWavFile(filename, samples, sampleRate)

# Menu music - calm, ambient, welcoming
proc createMenuMusic(filename: string): Music =
  # C major scale - peaceful and inviting
  # Slow tempo, ambient feel
  let melody = @[
    523.25'f32,  # C5
    587.33'f32,  # D5
    659.25'f32,  # E5
    587.33'f32,  # D5
    523.25'f32,  # C5
    0.0'f32,     # Rest
    392.00'f32,  # G4
    440.00'f32,  # A4
    493.88'f32,  # B4
    440.00'f32,  # A4
    523.25'f32,  # C5
    0.0'f32,     # Rest
    659.25'f32,  # E5
    587.33'f32,  # D5
    523.25'f32,  # C5
    0.0'f32      # Rest
  ]
  
  let harmony = @[
    261.63'f32,  # C4
    293.66'f32,  # D4
    329.63'f32,  # E4
    392.00'f32   # G4
  ]
  
  let bassline = @[
    130.81'f32,  # C3
    146.83'f32,  # D3
    164.81'f32,  # E3
    196.00'f32   # G3
  ]
  
  generateMusicTrack(filename, 80.0, 4, melody, harmony, bassline)
  let tempPath = getTempDir() / filename
  result = loadMusicStream(tempPath)

# Wave music - energetic, driving, action-packed
proc createWaveMusic(filename: string): Music =
  # A minor - energetic and driving
  # Fast tempo for action
  let melody = @[
    880.00'f32,  # A5
    783.99'f32,  # G5
    659.25'f32,  # E5
    783.99'f32,  # G5
    880.00'f32,  # A5
    987.77'f32,  # B5
    880.00'f32,  # A5
    783.99'f32,  # G5
    659.25'f32,  # E5
    587.33'f32,  # D5
    659.25'f32,  # E5
    783.99'f32,  # G5
    880.00'f32,  # A5
    0.0'f32,     # Rest
    880.00'f32,  # A5
    0.0'f32      # Rest
  ]
  
  let harmony = @[
    440.00'f32,  # A4
    329.63'f32,  # E4
    293.66'f32,  # D4
    392.00'f32   # G4
  ]
  
  let bassline = @[
    220.00'f32,  # A3
    164.81'f32,  # E3
    146.83'f32,  # D3
    196.00'f32   # G3
  ]
  
  generateMusicTrack(filename, 140.0, 4, melody, harmony, bassline)
  let tempPath = getTempDir() / filename
  result = loadMusicStream(tempPath)

# Power-up music - uplifting, victorious, hopeful
proc createPowerUpMusic(filename: string): Music =
  # C major - bright and hopeful
  # Medium tempo
  let melody = @[
    523.25'f32,  # C5
    659.25'f32,  # E5
    783.99'f32,  # G5
    1046.50'f32, # C6
    783.99'f32,  # G5
    659.25'f32,  # E5
    783.99'f32,  # G5
    659.25'f32,  # E5
    523.25'f32,  # C5
    587.33'f32,  # D5
    659.25'f32,  # E5
    587.33'f32,  # D5
    523.25'f32,  # C5
    0.0'f32,     # Rest
    783.99'f32,  # G5
    0.0'f32      # Rest
  ]
  
  let harmony = @[
    261.63'f32,  # C4
    329.63'f32,  # E4
    392.00'f32,  # G4
    261.63'f32   # C4
  ]
  
  let bassline = @[
    130.81'f32,  # C3
    164.81'f32,  # E3
    196.00'f32,  # G3
    130.81'f32   # C3
  ]
  
  generateMusicTrack(filename, 110.0, 4, melody, harmony, bassline)
  let tempPath = getTempDir() / filename
  result = loadMusicStream(tempPath)

# Boss music - intense, dramatic, ominous
proc createBossMusic(filename: string): Music =
  # D minor - dark and intense
  # Fast tempo, aggressive
  let melody = @[
    587.33'f32,  # D5
    698.46'f32,  # F5
    880.00'f32,  # A5
    987.77'f32,  # B5
    1174.66'f32, # D6
    987.77'f32,  # B5
    880.00'f32,  # A5
    698.46'f32,  # F5
    587.33'f32,  # D5
    523.25'f32,  # C5
    587.33'f32,  # D5
    698.46'f32,  # F5
    880.00'f32,  # A5
    0.0'f32,     # Rest
    880.00'f32,  # A5
    0.0'f32      # Rest
  ]
  
  let harmony = @[
    293.66'f32,  # D4
    349.23'f32,  # F4
    440.00'f32,  # A4
    261.63'f32   # C4
  ]
  
  let bassline = @[
    146.83'f32,  # D3
    174.61'f32,  # F3
    220.00'f32,  # A3
    130.81'f32   # C3
  ]
  
  generateMusicTrack(filename, 160.0, 4, melody, harmony, bassline)
  let tempPath = getTempDir() / filename
  result = loadMusicStream(tempPath)

# Game over sound - dramatic descending sequence (like Mario game over but custom)
proc createGameOverSound(filename: string): Sound =
  let sampleRate: uint32 = 44100
  let duration = 2.5  # Longer for dramatic effect
  let frameCount = int(sampleRate.float32 * duration)
  var samples = newSeq[int16](frameCount)
  
  # Descending note sequence: E5 -> D5 -> C5 -> G4 -> C4 (somber descent)
  let notes = @[
    (freq: 659.25'f32, start: 0.0, length: 0.35),    # E5
    (freq: 587.33'f32, start: 0.4, length: 0.35),    # D5
    (freq: 523.25'f32, start: 0.8, length: 0.4),     # C5
    (freq: 392.00'f32, start: 1.25, length: 0.5),    # G4 (longer, more dramatic)
    (freq: 261.63'f32, start: 1.8, length: 0.7)      # C4 (final somber note)
  ]
  
  for i in 0..<frameCount:
    let t = i.float32 / sampleRate.float32
    var value = 0.0
    
    # Find which note(s) should be playing
    for note in notes:
      if t >= note.start and t < note.start + note.length:
        let noteProgress = (t - note.start) / note.length
        
        # ADSR envelope for each note
        let envelope = applyADSR(noteProgress, 0.1, 0.15, 0.6, 0.15)
        
        # Add harmonics for richer tone
        let fundamental = sin(2.0 * PI * note.freq * t) * 0.5
        let harmonic2 = sin(2.0 * PI * note.freq * 2.0 * t) * 0.2
        let harmonic3 = sin(2.0 * PI * note.freq * 3.0 * t) * 0.1
        
        value += (fundamental + harmonic2 + harmonic3) * envelope
    
    samples[i] = int16(clamp(value * 32767.0, -32767.0, 32767.0))
  
  writeWavFile(filename, samples, sampleRate)
  let tempPath = getTempDir() / filename
  result = loadSound(tempPath)

proc generateAllMusic(sys: SoundSystem) =
  if sys.musicGenerated:
    return
  
  echo "Generating epic background music tracks..."
  
  try:
    echo "  - Menu music (dreamy atmospheric)"
    sys.cachedMusic[mtMenu] = createMenuMusic("menu_music.wav")
    
    echo "  - Wave combat music (high-energy electronic)"
    sys.cachedMusic[mtWave] = createWaveMusic("wave_music.wav")
    
    echo "  - Power-up music (triumphant heroic)"
    sys.cachedMusic[mtPowerUp] = createPowerUpMusic("powerup_music.wav")
    
    echo "  - Boss fight music (epic battle theme)"
    sys.cachedMusic[mtBoss] = createBossMusic("boss_music.wav")
    
    sys.musicGenerated = true
    echo "All epic music tracks generated successfully!"
  except Exception as e:
    echo "ERROR generating music: ", e.msg
    echo "  ", e.getStackTrace()
    sys.musicGenerated = false


proc generateAllSounds(sys: SoundSystem) =
  if sys.soundsGenerated:
    return
  
  echo "Generating enhanced procedural sounds..."
  
  try:
    echo "  - Enhanced laser shoot sound"
    sys.cachedSounds[stShoot] = createLaserShoot("shoot.wav")
    
    echo "  - Punchy impact hit sound"
    sys.cachedSounds[stEnemyHit] = createImpactHit("hit.wav")
    
    echo "  - Dramatic enemy death sound"
    sys.cachedSounds[stEnemyDeath] = createEnemyDeath("death.wav")
    
    echo "  - Alarm player hit sound"
    sys.cachedSounds[stPlayerHit] = createPlayerHit("playerhit.wav")
    
    echo "  - Sparkly coin pickup sound"
    sys.cachedSounds[stCoinPickup] = createCoinPickup("coin.wav")
    
    echo "  - Triumphant power-up sound"
    sys.cachedSounds[stPowerUp] = createPowerUp("powerup.wav")
    
    echo "  - Ominous boss spawn sound"
    sys.cachedSounds[stBossSpawn] = createBossSpawn("boss.wav")
    
    echo "  - Explosive explosion sound"
    sys.cachedSounds[stExplosion] = createExplosion("explosion.wav")
    
    echo "  - Solid wall placement sound"
    sys.cachedSounds[stWallPlace] = createWallPlace("wall.wav")
    
    echo "  - Sci-fi teleport sound"
    sys.cachedSounds[stTeleport] = createTeleport("teleport.wav")
    
    echo "  - Subtle menu navigation sound"
    sys.cachedSounds[stMenuNav] = createMenuNav("menunav.wav")
    
    echo "  - Confirmation menu select sound"
    sys.cachedSounds[stMenuSelect] = createMenuSelect("menuselect.wav")
    
    echo "  - Fanfare wave complete sound"
    sys.cachedSounds[stWaveComplete] = createWaveComplete("wavecomplete.wav")
    
    echo "  - Protective shield sound"
    sys.cachedSounds[stShield] = createShield("shield.wav")
    
    echo "  - Dramatic game over sound"
    sys.cachedSounds[stGameOver] = createGameOverSound("gameover.wav")
    
    sys.soundsGenerated = true
    echo "All enhanced sounds generated successfully!"
  except Exception as e:
    echo "ERROR generating sounds: ", e.msg
    echo "  ", e.getStackTrace()
    sys.soundsGenerated = false

proc initSoundSystem*(): SoundSystem =
  echo "Initializing enhanced sound system..."
  
  try:
    initAudioDevice()
    
    if not isAudioDeviceReady():
      echo "WARNING: Audio device not ready!"
      return SoundSystem(
        enabled: false, 
        masterVolume: 0.5, 
        musicVolume: 0.5,
        initialized: false, 
        soundsGenerated: false, 
        musicGenerated: false,
        trackPlaying: false
      )
    
    echo "Audio device initialized"
    
    result = SoundSystem(
      enabled: true,
      masterVolume: 0.5,
      musicVolume: 0.5,
      initialized: true,
      soundsGenerated: false,
      musicGenerated: false,
      trackPlaying: false
    )
    
    globalSoundSystem = result
    generateAllSounds(result)
    generateAllMusic(result)
    
    echo "Enhanced sound system fully initialized!"
    
  except Exception as e:
    echo "ERROR initializing sound system: ", e.msg
    echo "  ", e.getStackTrace()
    return SoundSystem(
      enabled: false, 
      masterVolume: 0.5, 
      musicVolume: 0.5,
      initialized: false, 
      soundsGenerated: false, 
      musicGenerated: false,
      trackPlaying: false
    )

proc closeSoundSystem*(sys: SoundSystem) =
  if sys != nil and sys.initialized:
    closeAudioDevice()
    echo "Sound system closed"

proc playSound*(soundType: SoundType, volumeMultiplier: float32 = 1.0) =
  if globalSoundSystem == nil or not globalSoundSystem.enabled or not globalSoundSystem.soundsGenerated:
    return
  
  try:
    let finalVolume = globalSoundSystem.masterVolume * volumeMultiplier
    setSoundVolume(globalSoundSystem.cachedSounds[soundType], finalVolume)
    raylib.playSound(globalSoundSystem.cachedSounds[soundType])
  except Exception as e:
    echo "ERROR playing sound: ", e.msg

proc setGameVolume*(volume: float32) =
  if globalSoundSystem != nil:
    globalSoundSystem.masterVolume = clamp(volume, 0.0, 1.0)

proc getGameVolume*(): float32 =
  if globalSoundSystem != nil:
    result = globalSoundSystem.masterVolume
  else:
    result = 0.5

proc toggleSound*() =
  if globalSoundSystem != nil:
    globalSoundSystem.enabled = not globalSoundSystem.enabled

# ============================================================================
# MUSIC CONTROL FUNCTIONS
# ============================================================================

proc playMusic*(track: MusicTrack) =
  if globalSoundSystem == nil or not globalSoundSystem.enabled or not globalSoundSystem.musicGenerated:
    return
  
  try:
    # Stop current music if playing different track
    if globalSoundSystem.trackPlaying and globalSoundSystem.currentTrack != track:
      stopMusicStream(globalSoundSystem.cachedMusic[globalSoundSystem.currentTrack])
      globalSoundSystem.trackPlaying = false
    
    # Start new track if not already playing
    if not globalSoundSystem.trackPlaying or globalSoundSystem.currentTrack != track:
      setMusicVolume(globalSoundSystem.cachedMusic[track], globalSoundSystem.musicVolume)
      playMusicStream(globalSoundSystem.cachedMusic[track])
      globalSoundSystem.currentTrack = track
      globalSoundSystem.trackPlaying = true
  except Exception as e:
    echo "ERROR playing music: ", e.msg

proc updateMusic*() =
  if globalSoundSystem == nil or not globalSoundSystem.enabled or not globalSoundSystem.trackPlaying:
    return
  
  try:
    updateMusicStream(globalSoundSystem.cachedMusic[globalSoundSystem.currentTrack])
    
    # Loop music seamlessly
    if not isMusicStreamPlaying(globalSoundSystem.cachedMusic[globalSoundSystem.currentTrack]):
      playMusicStream(globalSoundSystem.cachedMusic[globalSoundSystem.currentTrack])
  except Exception as e:
    echo "ERROR updating music: ", e.msg

proc stopMusic*() =
  if globalSoundSystem == nil or not globalSoundSystem.trackPlaying:
    return
  
  try:
    stopMusicStream(globalSoundSystem.cachedMusic[globalSoundSystem.currentTrack])
    globalSoundSystem.trackPlaying = false
  except Exception as e:
    echo "ERROR stopping music: ", e.msg

proc setMusicVolume*(volume: float32) =
  if globalSoundSystem != nil:
    globalSoundSystem.musicVolume = clamp(volume, 0.0, 1.0)
    
    # Update currently playing music
    if globalSoundSystem.trackPlaying:
      try:
        setMusicVolume(globalSoundSystem.cachedMusic[globalSoundSystem.currentTrack], 
                      globalSoundSystem.musicVolume)
      except:
        discard

proc getMusicVolume*(): float32 =
  if globalSoundSystem != nil:
    result = globalSoundSystem.musicVolume
  else:
    result = 0.5
