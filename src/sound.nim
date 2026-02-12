import raylib, math, random, os, streams

type
  SoundType* = enum
    stShoot, stEnemyHit, stEnemyDeath, stPlayerHit, stCoinPickup, stPowerUp,
    stBossSpawn, stExplosion, stWallPlace, stTeleport, stMenuNav, stMenuSelect,
    stWaveComplete, stShield, stGameOver

  MusicTrack* = enum
    mtMenu, mtWave, mtPowerUp, mtBoss

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

# SOUND GENERATION
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
  
  # Generate the sound based on type
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

# MUSIC GENERATION
const MUSIC_DURATION = 16.0

proc generateAdvancedMusic(filename: string, bpm: float32, duration: float32,
                          chordProg: seq[tuple[root: float32, fifth: float32, third: float32]],
                          melody: seq[float32], arpPattern: seq[int],
                          kickPattern: seq[bool], snarePattern: seq[bool],
                          hasDrops: bool = false, intensity: float32 = 1.0) =
  let sampleRate: uint32 = 44100
  let frameCount = int(sampleRate.float32 * duration)
  var samples = newSeq[int16](frameCount)
  
  let beatLength = int(sampleRate.float32 * (60.0 / bpm))
  let sixteenthLength = beatLength div 4
  
  for i in 0..<frameCount:
    let t = i.float32 / sampleRate.float32
    let beatNum = i div beatLength
    let beatProgress = (i mod beatLength).float32 / beatLength.float32
    let sixteenthNum = i div sixteenthLength
    
    let chordIdx = (beatNum div 4) mod chordProg.len
    let melodyIdx = beatNum mod melody.len
    let currentChord = chordProg[chordIdx]
    let currentNote = melody[melodyIdx]
    
    var dynamicMultiplier = 1.0
    if hasDrops:
      let measureNum = beatNum div 4
      if measureNum mod 8 >= 6:
        let buildProgress = ((measureNum mod 8) - 6).float32 / 2.0 + beatProgress / 8.0
        dynamicMultiplier = 0.7 + buildProgress * 0.3
      elif measureNum mod 8 < 2:
        dynamicMultiplier = 1.1
      else:
        dynamicMultiplier = 1.0
    
    # Bass layer
    var bassValue = 0.0
    if intensity > 0.7:
      let wobbleFreq = 3.0 + sin(t * 1.5) * 1.5
      let wobble = sin(2.0 * PI * wobbleFreq * t) * 0.4 + 0.6
      bassValue = sin(2.0 * PI * currentChord.root * 0.5 * t) * 0.35 * wobble * dynamicMultiplier
    else:
      let bassEnv = applyADSR(beatProgress, 0.05, 0.2, 0.6, 0.15)
      bassValue = sin(2.0 * PI * currentChord.root * 0.5 * t) * 0.35 * bassEnv
    
    # Arpeggiator layer
    var arpValue = 0.0
    let arpIdx = sixteenthNum mod arpPattern.len
    let arpNote = case arpPattern[arpIdx]
      of 0: currentChord.root
      of 1: currentChord.third
      of 2: currentChord.fifth
      else: currentChord.root * 2.0
    
    let arpEnv = applyADSR((i mod sixteenthLength).float32 / sixteenthLength.float32, 0.01, 0.05, 0.3, 0.64)
    let sawWave = (t * arpNote * 2.0) mod 1.0 - 0.5
    arpValue = sawWave * 0.14 * arpEnv * dynamicMultiplier
    
    # Pad chords
    let detune = 0.02
    let padValue = (sin(2.0 * PI * currentChord.root * t) * 0.12 +
                    sin(2.0 * PI * currentChord.root * (1.0 + detune) * t) * 0.12 +
                    sin(2.0 * PI * currentChord.third * t) * 0.09 +
                    sin(2.0 * PI * currentChord.fifth * t) * 0.09) * (0.5 + beatProgress * 0.5)
    
    # Lead melody
    var leadValue = 0.0
    if currentNote > 0:
      let leadEnv = applyADSR(beatProgress, 0.08, 0.12, 0.7, 0.1)
      let squareWave = if sin(2.0 * PI * currentNote * t) > 0: 1.0 else: -1.0
      let sawLead = (t * currentNote * 2.0) mod 1.0 - 0.5
      leadValue = (squareWave * 0.09 + sawLead * 0.06) * leadEnv * intensity * dynamicMultiplier
    
    # Percussion
    var drumValue = 0.0
    if kickPattern[beatNum mod kickPattern.len] and beatProgress < 0.2:
      let kickFreq = 60.0 * exp(-beatProgress * 25.0)
      drumValue += sin(2.0 * PI * kickFreq * (beatProgress * 60.0 / bpm)) * 0.5 * exp(-beatProgress * 15.0)
    
    if snarePattern[beatNum mod snarePattern.len] and beatProgress < 0.15:
      let snareEnv = exp(-beatProgress * 35.0)
      drumValue += rand(-1.0..1.0) * 0.3 * snareEnv + sin(2.0 * PI * 200.0 * (beatProgress * 60.0 / bpm)) * 0.2 * snareEnv
    
    # Hi-hats
    let hihatValue = if sixteenthNum mod 2 == 0:
      let hihatProgress = (i mod sixteenthLength).float32 / sixteenthLength.float32
      rand(-1.0..1.0) * 0.04 * exp(-hihatProgress * 45.0) * intensity
    else: 0.0
    
    let finalValue = bassValue + arpValue + padValue + leadValue + drumValue + hihatValue
    samples[i] = int16(clamp(finalValue * 32767.0 * 0.85, -32767.0, 32767.0))
  
  writeWavFile(filename, samples, sampleRate)

proc createMenuMusic(filename: string): Music =
  let chordProg = @[
    (root: 220.00'f32, fifth: 329.63'f32, third: 261.63'f32),
    (root: 174.61'f32, fifth: 261.63'f32, third: 220.00'f32),
    (root: 261.63'f32, fifth: 392.00'f32, third: 329.63'f32),
    (root: 196.00'f32, fifth: 293.66'f32, third: 246.94'f32)
  ]
  
  let melody = @[
    659.25'f32, 0.0'f32, 587.33'f32, 523.25'f32,
    587.33'f32, 0.0'f32, 659.25'f32, 783.99'f32,
    659.25'f32, 587.33'f32, 523.25'f32, 0.0'f32,
    440.00'f32, 493.88'f32, 523.25'f32, 0.0'f32
  ]
  
  let arpPattern = @[0, 1, 2, 3, 2, 1, 0, 0]
  let kickPattern = @[true, false, false, false, false, false, true, false]
  let snarePattern = @[false, false, false, false, false, false, false, false]
  
  generateAdvancedMusic(filename, 85.0, MUSIC_DURATION, chordProg, melody, 
                       arpPattern, kickPattern, snarePattern, false, 0.5)
  result = loadMusicStream(filename)

proc createWaveMusic(filename: string): Music =
  let chordProg = @[
    (root: 164.81'f32, fifth: 246.94'f32, third: 196.00'f32),
    (root: 130.81'f32, fifth: 196.00'f32, third: 164.81'f32),
    (root: 196.00'f32, fifth: 293.66'f32, third: 246.94'f32),
    (root: 146.83'f32, fifth: 220.00'f32, third: 184.99'f32)
  ]
  
  let melody = @[
    1318.51'f32, 987.77'f32, 1318.51'f32, 1567.98'f32,
    1318.51'f32, 1046.50'f32, 987.77'f32, 1318.51'f32,
    1567.98'f32, 1318.51'f32, 1174.66'f32, 1046.50'f32,
    987.77'f32, 1174.66'f32, 1318.51'f32, 1318.51'f32
  ]
  
  let arpPattern = @[0, 2, 1, 3, 2, 1, 3, 0]
  let kickPattern = @[true, false, false, false, true, false, false, false]
  let snarePattern = @[false, false, false, false, true, false, false, false]
  
  generateAdvancedMusic(filename, 140.0, MUSIC_DURATION, chordProg, melody, 
                       arpPattern, kickPattern, snarePattern, true, 0.85)
  result = loadMusicStream(filename)

proc createPowerUpMusic(filename: string): Music =
  let chordProg = @[
    (root: 261.63'f32, fifth: 392.00'f32, third: 329.63'f32),
    (root: 220.00'f32, fifth: 329.63'f32, third: 261.63'f32),
    (root: 174.61'f32, fifth: 261.63'f32, third: 220.00'f32),
    (root: 196.00'f32, fifth: 293.66'f32, third: 246.94'f32)
  ]
  
  let melody = @[
    1046.50'f32, 1174.66'f32, 1318.51'f32, 1568.00'f32,
    1318.51'f32, 1046.50'f32, 1174.66'f32, 1046.50'f32,
    1318.51'f32, 1568.00'f32, 1760.00'f32, 1568.00'f32,
    1318.51'f32, 1174.66'f32, 1046.50'f32, 1174.66'f32
  ]
  
  let arpPattern = @[0, 3, 2, 1, 3, 0, 2, 1]
  let kickPattern = @[true, false, false, true, false, false, true, false]
  let snarePattern = @[false, false, true, false, false, false, false, false]
  
  generateAdvancedMusic(filename, 110.0, MUSIC_DURATION, chordProg, melody, 
                       arpPattern, kickPattern, snarePattern, false, 0.7)
  result = loadMusicStream(filename)

proc createBossMusic(filename: string): Music =
  let chordProg = @[
    (root: 146.83'f32, fifth: 220.00'f32, third: 174.61'f32),
    (root: 116.54'f32, fifth: 174.61'f32, third: 146.83'f32),
    (root: 174.61'f32, fifth: 261.63'f32, third: 220.00'f32),
    (root: 130.81'f32, fifth: 196.00'f32, third: 164.81'f32)
  ]
  
  let melody = @[
    587.33'f32, 698.46'f32, 783.99'f32, 880.00'f32,
    987.77'f32, 880.00'f32, 783.99'f32, 698.46'f32,
    783.99'f32, 880.00'f32, 1046.50'f32, 987.77'f32,
    880.00'f32, 783.99'f32, 698.46'f32, 587.33'f32
  ]
  
  let arpPattern = @[0, 3, 1, 2, 3, 0, 2, 1]
  let kickPattern = @[true, true, false, false, true, true, false, false]
  let snarePattern = @[false, false, true, false, false, true, true, false]
  
  generateAdvancedMusic(filename, 170.0, MUSIC_DURATION, chordProg, melody, 
                       arpPattern, kickPattern, snarePattern, true, 1.0)
  result = loadMusicStream(filename)

proc loadOrGenerateMusic(track: MusicTrack): Music =
  let cacheFile = getMusicCacheFile(track)
  
  if fileExists(cacheFile):
    return loadMusicStream(cacheFile)
  
  # Generate the music based on track
  case track
  of mtMenu: result = createMenuMusic(cacheFile)
  of mtWave: result = createWaveMusic(cacheFile)
  of mtPowerUp: result = createPowerUpMusic(cacheFile)
  of mtBoss: result = createBossMusic(cacheFile)

# PRE-GENERATION SYSTEM
proc preGenerateAllAssets*(verbose: bool = true) =
  ## Pre-generate all sounds and music that aren't already cached
  ## This prevents any in-game stuttering from asset generation
  
  let cached = countCachedAssets()
  let totalAssets = SoundType.high.ord + 1 + MusicTrack.high.ord + 1
  
  if cached.total == totalAssets:
    if verbose:
      echo "All ", totalAssets, " assets already cached"
    return
  
  if verbose:
    echo "=========================================="
    echo "Pre-generating game assets..."
    echo "Cached: ", cached.sounds, "/", SoundType.high.ord + 1, " sounds, ", 
         cached.music, "/", MusicTrack.high.ord + 1, " music tracks"
    echo "=========================================="
  
  var assetsGenerated = 0
  let assetsToGenerate = totalAssets - cached.total
  
  # Generate all sounds
  for soundType in SoundType:
    if not isSoundCached(soundType):
      if verbose:
        inc assetsGenerated
        let progress = (assetsGenerated.float32 / assetsToGenerate.float32 * 100.0).int
        echo "[", progress, "%] Generating sound: ", soundType, "..."
      discard loadOrGenerateSound(soundType)
  
  # Generate all music
  for track in MusicTrack:
    if not isMusicCached(track):
      if verbose:
        inc assetsGenerated
        let progress = (assetsGenerated.float32 / assetsToGenerate.float32 * 100.0).int
        echo "[", progress, "%] Generating music: ", track, "..."
      discard loadOrGenerateMusic(track)
  
  if verbose:
    echo "=========================================="
    echo "  Asset generation complete!"
    echo "  Total assets: ", totalAssets
    echo "  Cache location: ", getCacheDir()
    echo "=========================================="

proc generateAllSounds(sys: SoundSystem) =
  ## Load all sounds into memory from cache or generate if needed
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
proc initSoundSystem*(): SoundSystem =
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
    
    # Pre-generate all assets if not cached
    preGenerateAllAssets(verbose = true)
    
    # Load all sounds into memory
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
    if not isMusicStreamPlaying(globalSoundSystem.cachedMusic[globalSoundSystem.currentTrack]):
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
