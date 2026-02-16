import raylib, math, random, os, streams

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
  result = getTempDir() / "tophat_sound_cache"
  if not dirExists(result):
    createDir(result)

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

# SOUND GENERATION (keeping original sound effects)
proc createSimpleSound(filename: string, duration: float32, 
                      freqFunc: proc(t, progress: float32): float32,
                      envelope: proc(progress: float32): float32,
                      amplitude: float32 = 0.4): Sound =
  let sampleRate: uint32 = 44100
  let frameCount = int(sampleRate.float32 * duration)
  var samples = newSeq[int16](frameCount)
  
  for i in 0..<frameCount:
    let t = i.float32 / sampleRate.float32
    let progress = t / duration
    let freq = freqFunc(t, progress)
    let env = envelope(progress)
    let value = sin(2.0 * PI * freq * t) * env * amplitude
    samples[i] = int16(value * 32767.0)
  
  writeWavFile(filename, samples, sampleRate)
  result = loadSound(filename)

proc createLaserShoot(filename: string): Sound =
  createSimpleSound(filename, 0.12,
    proc(t, p: float32): float32 = 1200.0 * exp(-p * 4.0) + 400.0,
    proc(p: float32): float32 = applyADSR(p, 0.05, 0.15, 0.3, 0.3))

proc createImpactHit(filename: string): Sound =
  let sampleRate: uint32 = 44100
  let duration = 0.15
  let frameCount = int(sampleRate.float32 * duration)
  var samples = newSeq[int16](frameCount)
  
  for i in 0..<frameCount:
    let t = i.float32 / sampleRate.float32
    let progress = t / duration
    let envelope = exp(-progress * 15.0)
    let noise = rand(-1.0..1.0) * 0.4
    let thump = sin(2.0 * PI * 80.0 * t * exp(-progress * 8.0)) * 0.6
    samples[i] = int16((noise + thump) * envelope * 32767.0)
  
  writeWavFile(filename, samples, sampleRate)
  result = loadSound(filename)

proc createEnemyDeath(filename: string): Sound =
  createSimpleSound(filename, 0.4,
    proc(t, p: float32): float32 = 800.0 * exp(-p * 3.5) + 50.0,
    proc(p: float32): float32 = exp(-p * 3.0),
    0.45)

proc createPlayerHit(filename: string): Sound =
  createSimpleSound(filename, 0.2,
    proc(t, p: float32): float32 = 180.0,
    proc(p: float32): float32 = exp(-p * 5.0) * (sin(2.0 * PI * 15.0 * p * 0.2) * 0.5 + 0.5),
    0.5)

proc createCoinPickup(filename: string): Sound =
  let sampleRate: uint32 = 44100
  let duration = 0.2
  let frameCount = int(sampleRate.float32 * duration)
  var samples = newSeq[int16](frameCount)
  
  for i in 0..<frameCount:
    let t = i.float32 / sampleRate.float32
    let progress = t / duration
    var freq = 523.25'f32
    if progress > 0.33: freq = 659.25'f32
    if progress > 0.66: freq = 783.99'f32
    let envelope = applyADSR(progress, 0.1, 0.2, 0.4, 0.3)
    samples[i] = int16(sin(2.0 * PI * freq * t) * envelope * 0.35 * 32767.0)
  
  writeWavFile(filename, samples, sampleRate)
  result = loadSound(filename)

proc createPowerUp(filename: string): Sound =
  let sampleRate: uint32 = 44100
  let duration = 0.5
  let frameCount = int(sampleRate.float32 * duration)
  var samples = newSeq[int16](frameCount)
  
  for i in 0..<frameCount:
    let t = i.float32 / sampleRate.float32
    let progress = t / duration
    let pitchRise = 1.0 + progress * 0.1
    let vibrato = 1.0 + sin(2.0 * PI * 6.0 * t) * 0.01
    let envelope = applyADSR(progress, 0.1, 0.2, 0.6, 0.1)
    let value = (sin(2.0 * PI * 523.25 * pitchRise * vibrato * t) * 0.4 + 
                 sin(2.0 * PI * 659.25 * pitchRise * vibrato * t) * 0.3 + 
                 sin(2.0 * PI * 783.99 * pitchRise * vibrato * t) * 0.3) * envelope
    samples[i] = int16(value * 0.4 * 32767.0)
  
  writeWavFile(filename, samples, sampleRate)
  result = loadSound(filename)

proc createBossSpawn(filename: string): Sound =
  createSimpleSound(filename, 1.2,
    proc(t, p: float32): float32 = 40.0 + p * 120.0,
    proc(p: float32): float32 = min(1.0, p * 2.0) * exp(-max(0.0, p - 0.5) * 2.0),
    0.5)

proc createExplosion(filename: string): Sound =
  let sampleRate: uint32 = 44100
  let duration = 0.5
  let frameCount = int(sampleRate.float32 * duration)
  var samples = newSeq[int16](frameCount)
  
  for i in 0..<frameCount:
    let t = i.float32 / sampleRate.float32
    let progress = t / duration
    let envelope = exp(-progress * 6.0)
    let boom = sin(2.0 * PI * 70.0 * exp(-progress * 8.0) * t) * 0.6
    let punch = sin(2.0 * PI * 200.0 * exp(-progress * 10.0) * t) * 0.3
    let noise = rand(-1.0..1.0) * (if progress < 0.1: 0.3 else: 0.1) * exp(-progress * 15.0)
    samples[i] = int16((boom + punch + noise) * envelope * 0.6 * 32767.0)
  
  writeWavFile(filename, samples, sampleRate)
  result = loadSound(filename)

proc createWallPlace(filename: string): Sound =
  createSimpleSound(filename, 0.25,
    proc(t, p: float32): float32 = 120.0 * exp(-p * 8.0),
    proc(p: float32): float32 = exp(-p * 10.0),
    0.45)

proc createTeleport(filename: string): Sound =
  createSimpleSound(filename, 0.4,
    proc(t, p: float32): float32 = 
      let sweepPhase = if p < 0.5: p * 2.0 else: 1.0 - (p - 0.5) * 2.0
      1500.0 + sin(sweepPhase * PI) * 1000.0,
    proc(p: float32): float32 = sin(p * PI),
    0.35)

proc createMenuNav(filename: string): Sound =
  createSimpleSound(filename, 0.06,
    proc(t, p: float32): float32 = 800.0,
    proc(p: float32): float32 = exp(-p * 30.0),
    0.3)

proc createMenuSelect(filename: string): Sound =
  let sampleRate: uint32 = 44100
  let duration = 0.25
  let frameCount = int(sampleRate.float32 * duration)
  var samples = newSeq[int16](frameCount)
  
  for i in 0..<frameCount:
    let t = i.float32 / sampleRate.float32
    let progress = t / duration
    let freq = if progress < 0.4: 600.0 else: 450.0
    let envelope = applyADSR(progress, 0.1, 0.2, 0.5, 0.2)
    samples[i] = int16(sin(2.0 * PI * freq * t) * envelope * 0.35 * 32767.0)
  
  writeWavFile(filename, samples, sampleRate)
  result = loadSound(filename)

proc createWaveComplete(filename: string): Sound =
  let sampleRate: uint32 = 44100
  let duration = 0.8
  let frameCount = int(sampleRate.float32 * duration)
  var samples = newSeq[int16](frameCount)
  
  for i in 0..<frameCount:
    let t = i.float32 / sampleRate.float32
    let progress = t / duration
    var freq = 523.25'f32
    if progress > 0.25: freq = 659.25'f32
    if progress > 0.5: freq = 783.99'f32
    if progress > 0.75: freq = 1046.50'f32
    let envelope = applyADSR(progress, 0.1, 0.15, 0.7, 0.05)
    samples[i] = int16(sin(2.0 * PI * freq * t) * envelope * 0.4 * 32767.0)
  
  writeWavFile(filename, samples, sampleRate)
  result = loadSound(filename)

proc createShield(filename: string): Sound =
  createSimpleSound(filename, 0.35,
    proc(t, p: float32): float32 = 280.0 + sin(2.0 * PI * 7.0 * t) * 20.0,
    proc(p: float32): float32 = applyADSR(p, 0.15, 0.2, 0.5, 0.15),
    0.4)

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

# ============================================================================
# MUSIC GENERATION - COMPLETE REWRITE
# ============================================================================
# 
# Design principles:
# - Clear, simple melodies that are easy to follow
# - Intentional pauses and rests - not constant sound
# - 1-3 simultaneous instruments maximum
# - Longer note durations over rapid sequences
# - Recognizable motifs that develop meaningfully
# - Long-form structure with distinct sections
# - Dynamic contrast and natural flow
# - Calm, readable, cohesive music
# ============================================================================

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

# ============================================================================
# MENU MUSIC - Calm and welcoming
# ============================================================================

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

# ============================================================================
# WAVE MUSIC - Highly frenetic with rapid-fire notes and driving rhythm
# ============================================================================

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

# ============================================================================
# POWER-UP MUSIC - Uplifting and bright
# ============================================================================

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

# ============================================================================
# BOSS MUSIC - Extremely frenetic and relentless
# ============================================================================

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

# ============================================================================
# MUSIC LOADING AND SYSTEM MANAGEMENT
# ============================================================================

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
      callback(1.0, "All assets loaded from cache")
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
        callback(prog, "Generating sound: " & $soundType)
      
      discard loadOrGenerateSound(soundType)
  
  for track in MusicTrack:
    if not isMusicCached(track):
      if verbose:
        inc assetsGenerated
        let progress = (assetsGenerated.float32 / assetsToGenerate.float32 * 100.0).int
        echo "[", progress, "%] Generating music: ", track, "..."
      
      if not callback.isNil:
        let prog = assetsGenerated.float32 / assetsToGenerate.float32
        callback(prog, "Generating music: " & $track)
      
      discard loadOrGenerateMusic(track)
  
  if verbose:
    echo "=========================================="
    echo "  Asset generation complete!"
    echo "  Total assets: ", totalAssets
    echo "  Cache location: ", getCacheDir()
    echo "=========================================="
  
  if not callback.isNil:
    callback(1.0, "Asset generation complete!")

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
