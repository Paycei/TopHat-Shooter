import raylib, math, random, os, streams, strutils
import localization

# Raylib's playSound restarts a Sound that is already playing, cutting its
# tail. Each sound gets a pool of aliases (shared sample data) played
# round-robin so rapid-fire effects overlap instead of cutting each other off.
const MAX_SOUND_VOICES = 4

type
  SoundType* = enum
    stShoot, stEnemyHit, stEnemyDeath, stPlayerHit, stCoinPickup, stPowerUp,
    stBossSpawn, stExplosion, stWallPlace, stTeleport, stMenuNav, stMenuSelect,
    stWaveComplete, stShield, stGameOver, stBuy

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
    soundVoices: array[SoundType, array[MAX_SOUND_VOICES, SoundAlias]]
    nextVoice: array[SoundType, int]
    lastPlayTime: array[SoundType, float64]
    soundsGenerated: bool
    cachedMusic: array[MusicTrack, Music]
    musicGenerated: array[MusicTrack, bool]
    currentTrack: MusicTrack
    trackPlaying: bool

var globalSoundSystem*: SoundSystem

# Musical constants are declared before cache helpers because cache validation
# depends on the generated WAV length.
const
  SAMPLE_RATE = 44100'u32
  MUSIC_DURATION = 48.0'f32  # Long-form: 48 seconds
  MUSIC_CACHE_VERSION = "v4"
  SOUND_CACHE_VERSION = "v2"  # bump when any create* synthesis changes

proc expectedMusicCacheBytes(): int64 =
  int64(44 + int(MUSIC_DURATION * SAMPLE_RATE.float32) * 2)

# CACHE MANAGEMENT
when defined(android):
  # Same writable internal-data path used for saves (see save_system + the
  # android_glue.c shim, which is compiled there). Declared without {.compile.}
  # so the C object is built once; the symbol is resolved at link time.
  proc nimAndroidInternalDataPath(): cstring {.importc.}

proc getCacheDir(): string =
  when defined(android):
    # /tmp is not writable on Android; use app-internal storage. Absolute paths
    # work for both Nim writeFile (cache generation) and raylib loadSound (its
    # raw-fopen fallback), so the synthesized .wav cache round-trips correctly.
    result = $nimAndroidInternalDataPath() / "shooteros_music_cache"
  else:
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
    of stBuy: "buy"
  result = cacheDir / (soundName & "_" & SOUND_CACHE_VERSION & ".wav")

proc getMusicCacheFile(track: MusicTrack): string =
  let cacheDir = getCacheDir()
  let trackName = case track
    of mtMenu: "menu_music"
    of mtWave: "wave_music"
    of mtPowerUp: "powerup_music"
    of mtBoss: "boss_music"
  result = cacheDir / (trackName & "_" & MUSIC_CACHE_VERSION & ".wav")

proc isSoundCached(soundType: SoundType): bool =
  fileExists(getSoundCacheFile(soundType))

proc isMusicCached(track: MusicTrack): bool =
  let cacheFile = getMusicCacheFile(track)
  try:
    fileExists(cacheFile) and getFileSize(cacheFile) == expectedMusicCacheBytes()
  except OSError:
    false

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
  # Tight sci-fi "pew": pitch-swept core with light FM, a fast-fading bright
  # harmonic, a small sub thump and a filtered attack tick. Phase accumulation
  # keeps the sweep clean, and soft saturation adds body. Built to be heard
  # ten times a second without fatiguing.
  let sampleRate: uint32 = 44100
  let duration = 0.14
  let frameCount = int(sampleRate.float32 * duration)
  var samples = newSeq[int16](frameCount)

  let dt = 1.0 / sampleRate.float64
  var corePhase, subPhase = 0.0
  var noiseLP = 0.0

  for i in 0..<frameCount:
    let t = i.float32 / sampleRate.float32
    let progress = t / duration

    # Core: exponential downward sweep, integrated as phase so the pitch
    # glides smoothly instead of warbling
    let coreFreq = 1600.0 * exp(-progress * 7.0) + 240.0
    corePhase += 2.0 * PI * coreFreq * dt
    let fm = sin(corePhase * 2.7) * 0.3 * exp(-progress * 9.0)
    let core = sin(corePhase + fm) * 0.5

    # Bright opening "zing" that fades fast
    let zing = sin(corePhase * 2.0) * 0.24 * exp(-progress * 13.0)

    # Sub thump for body behind the zap
    let subFreq = 150.0 * exp(-progress * 4.0)
    subPhase += 2.0 * PI * subFreq * dt
    let thump = sin(subPhase) * 0.22 * exp(-progress * 14.0)

    # Lowpass-filtered attack tick (texture without hiss)
    noiseLP += 0.25 * (rand(-1.0..1.0) - noiseLP)
    let tick = noiseLP * 0.55 * exp(-progress * 32.0)

    let envelope = applyADSR(progress, 0.006, 0.10, 0.28, 0.55)

    # Soft saturation rounds the peaks and adds harmonics
    let value = tanh((core + zing + thump + tick) * envelope * 1.7) * 0.6
    samples[i] = int16(clamp(value * 32767.0 * 0.5, -32767.0, 32767.0))

  writeWavFile(filename, samples, sampleRate)
  result = loadSound(filename)

proc createImpactHit(filename: string): Sound =
  # Punchy drum-like impact: a pitch-swept thump (phase-accumulated, like an
  # 808 kick), a mid knock for definition and a lowpass-filtered crack burst
  # instead of raw white noise. Soft saturation glues the layers together.
  let sampleRate: uint32 = 44100
  let duration = 0.16
  let frameCount = int(sampleRate.float32 * duration)
  var samples = newSeq[int16](frameCount)

  let dt = 1.0 / sampleRate.float64
  var thumpPhase, knockPhase = 0.0
  var crackLP = 0.0

  for i in 0..<frameCount:
    let t = i.float32 / sampleRate.float32
    let progress = t / duration

    # Deep felt thump: 190 Hz dropping fast to ~55 Hz
    let thumpFreq = 55.0 + 135.0 * exp(-progress * 16.0)
    thumpPhase += 2.0 * PI * thumpFreq * dt
    let thump = sin(thumpPhase) * 0.65 * exp(-progress * 7.0)

    # Mid knock for definition through the mix
    let knockFreq = 320.0 * exp(-progress * 9.0) + 120.0
    knockPhase += 2.0 * PI * knockFreq * dt
    let knock = sin(knockPhase) * 0.3 * exp(-progress * 12.0)

    # Crack: noise lowpassed around the upper mids, very fast decay.
    # Filtering keeps the snap but loses the static hiss.
    crackLP += 0.30 * (rand(-1.0..1.0) - crackLP)
    let crack = crackLP * 0.85 * exp(-progress * 26.0)

    # Short metallic ping so hits cut through at low volume
    let ping = sin(2.0 * PI * 2100.0 * t) * 0.12 * exp(-progress * 30.0)

    let value = tanh((thump + knock + crack + ping) * 1.6) * 0.62
    samples[i] = int16(clamp(value * 32767.0 * 0.72, -32767.0, 32767.0))

  writeWavFile(filename, samples, sampleRate)
  result = loadSound(filename)

proc createEnemyDeath(filename: string): Sound =
  # Satisfying destruction "zap-drop": a clean phase-accumulated dive from
  # high to sub frequencies with a tracking sub octave, plus lowpass-filtered
  # debris crackle. Shorter than before (0.45 s) so dense kill chains stay
  # readable, with saturation for weight.
  let sampleRate: uint32 = 44100
  let duration = 0.45
  let frameCount = int(sampleRate.float32 * duration)
  var samples = newSeq[int16](frameCount)

  let dt = 1.0 / sampleRate.float64
  var mainPhase, subPhase = 0.0
  var burstLP, crackleLP = 0.0

  for i in 0..<frameCount:
    let t = i.float32 / sampleRate.float32
    let progress = t / duration

    # Main dive: ~950 Hz falling to ~45 Hz, integrated as phase
    let mainFreq = 900.0 * exp(-progress * 6.0) + 45.0
    mainPhase += 2.0 * PI * mainFreq * dt
    let mainTone = sin(mainPhase) * 0.48

    # Sub octave tracking the dive for weight
    subPhase += PI * mainFreq * dt
    let subOctave = sin(subPhase) * 0.38

    # Slightly detuned partial for a broken, dissonant edge
    let warble = sin(mainPhase * 1.17) * 0.14 * exp(-progress * 4.0)

    # Impact burst: heavily lowpassed noise, only at the front
    burstLP += 0.22 * (rand(-1.0..1.0) - burstLP)
    let burst = burstLP * 0.9 * exp(-progress * 18.0)

    # Debris crackle: brighter filtered noise sputtering out through the tail
    crackleLP += 0.45 * (rand(-1.0..1.0) - crackleLP)
    let crackle = (crackleLP - burstLP * 0.5) * 0.35 * exp(-progress * 6.0)

    let attackEnv = min(1.0, progress / 0.02)
    let mainEnv = exp(-progress * 3.5)

    let value = tanh((mainTone + subOctave + warble + burst + crackle) *
                     attackEnv * mainEnv * 1.5) * 0.66
    samples[i] = int16(clamp(value * 32767.0 * 0.7, -32767.0, 32767.0))

  writeWavFile(filename, samples, sampleRate)
  result = loadSound(filename)

proc createPlayerHit(filename: string): Sound =
  # Intense, attention-grabbing damage sound
  let sampleRate: uint32 = 44100
  let duration = 0.35
  let frameCount = int(sampleRate.float32 * duration)
  var samples = newSeq[int16](frameCount)

  var noiseLP = 0.0

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

    # Damage noise, lowpass-filtered so it's gritty rather than hissy
    noiseLP += 0.3 * (rand(-1.0..1.0) - noiseLP)
    let noiseBurst = if progress < 0.15:
      noiseLP * (1.0 - progress / 0.15) * 0.7
    else:
      0.0

    # Sustained noise - aftermath
    let sustainedNoise = noiseLP * 0.3 * exp(-progress * 10.0)

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
  # Cinematic boom built around a closing lowpass filter: the noise starts
  # bright (the blast) and darkens into a low rumble as it decays, the way
  # real explosions bloom. Underneath sits a phase-accumulated sub drop and
  # a mid punch, glued with heavy soft saturation.
  let sampleRate: uint32 = 44100
  let duration = 0.9
  let frameCount = int(sampleRate.float32 * duration)
  var samples = newSeq[int16](frameCount)

  let dt = 1.0 / sampleRate.float64
  var subPhase, punchPhase = 0.0
  var blastLP = 0.0

  for i in 0..<frameCount:
    let t = i.float32 / sampleRate.float32
    let progress = t / duration

    # Initial detonation click
    let click = if progress < 0.015:
      sin(2.0 * PI * 2800.0 * t) * (1.0 - progress / 0.015) * 0.5
    else:
      0.0

    # Sub drop: 110 Hz collapsing to ~26 Hz, felt more than heard
    let subFreq = 26.0 + 84.0 * exp(-progress * 9.0)
    subPhase += 2.0 * PI * subFreq * dt
    let sub = sin(subPhase) * 0.62 * exp(-progress * 3.2)

    # Mid punch for the body of the hit
    let punchFreq = 240.0 * exp(-progress * 11.0) + 60.0
    punchPhase += 2.0 * PI * punchFreq * dt
    let punch = sin(punchPhase) * 0.4 * exp(-progress * 6.0)

    # Blast noise through a closing filter: cutoff sweeps from wide open
    # down to a muffled rumble across the tail
    let alpha = 0.04 + 0.4 * exp(-progress * 5.0)
    blastLP += alpha * (rand(-1.0..1.0) - blastLP)
    let blast = blastLP * (0.95 * exp(-progress * 2.6))

    # Low metallic resonance ringing out of the blast
    let resonance = sin(2.0 * PI * 420.0 * t) * 0.12 * exp(-progress * 4.0)

    let value = tanh((click + sub + punch + blast + resonance) * 1.7) * 0.62
    samples[i] = int16(clamp(value * 32767.0 * 0.68, -32767.0, 32767.0))

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

proc createBuySound(filename: string): Sound =
  # Satisfying two-tone "cha-ching" purchase confirmation
  let sampleRate: uint32 = 44100
  let duration = 0.4
  let frameCount = int(sampleRate.float32 * duration)
  var samples = newSeq[int16](frameCount)

  # Two-note ascending chime: lower note then upper note, with rich harmonics
  let notes = [
    (freq: 587.33'f32, start: 0.0'f32, length: 0.18'f32),   # D5 - first chime
    (freq: 880.00'f32, start: 0.18'f32, length: 0.22'f32)   # A5 - confirming high note
  ]

  for i in 0..<frameCount:
    let t = i.float32 / sampleRate.float32
    var value = 0.0

    for note in notes:
      if t >= note.start and t < note.start + note.length:
        let noteTime = t - note.start
        let noteProgress = noteTime / note.length

        # Bell-like timbre: fundamental + bright harmonics
        let fundamental = sin(2.0 * PI * note.freq * t) * 0.50
        let h2 = sin(2.0 * PI * note.freq * 2.0 * t) * 0.20
        let h3 = sin(2.0 * PI * note.freq * 3.0 * t) * 0.10
        let h4 = sin(2.0 * PI * note.freq * 4.0 * t) * 0.05

        # Gold shimmer layer
        let shimmer = sin(2.0 * PI * note.freq * 5.5 * t) * 0.04

        # Fast attack, smooth exponential decay (bell-like)
        let attack = if noteProgress < 0.04: noteProgress / 0.04 else: 1.0
        let decay = exp(-noteProgress * 9.0)
        let envelope = attack * decay

        value += (fundamental + h2 + h3 + h4 + shimmer) * envelope

    # Tiny sparkle at the very end for a "coins landing" feel
    let globalProgress = t / duration
    let sparkle = if globalProgress > 0.55 and globalProgress < 0.85:
      sin(2.0 * PI * 2200.0 * t) *
        ((0.85 - globalProgress) / 0.30) * 0.06
    else:
      0.0

    samples[i] = int16(clamp((value + sparkle) * 32767.0 * 0.52, -32767.0, 32767.0))

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
  of stBuy: result = createBuySound(cacheFile)

# ============================================================================
# PROCEDURAL MUSIC ENGINE (v4)
#
# Each track is described by a TrackSpec: tempo, tonic, a looping chord
# progression (one chord per bar) and a per-bar intensity curve. The engine
# arranges pads, bass, arpeggios, a lead melody and drums from that spec, so
# every layer stays in key and on the grid. All BPMs are multiples of 5 so the
# bar grid divides the 48-second buffer exactly and the tracks loop seamlessly.
# ============================================================================

type
  InstrumentKind = enum
    ikLead,   # detuned 3-voice saw lead
    ikBell,   # soft bell with inharmonic partial
    ikPluck,  # bright synth pluck with decaying brightness
    ikBass,   # FM bass with sub oscillator
    ikPad     # warm detuned pad

  PercussionVoice = enum
    pvKick, pvSnare, pvHat, pvOpenHat, pvSoftTick, pvCrash

  ChordQuality = enum
    cqMajor, cqMinor, cqMajor7, cqMinor7, cqDom7, cqSus2

  BarChord = object
    rootSemi: int          # semitones above the track tonic
    quality: ChordQuality

  MelodyNote = object
    semi: int              # semitones above the track tonic
    start: float32         # beats from phrase start
    dur: float32           # beats
    accent: float32        # 0..1 extra emphasis

  DrumEvent = tuple[time: float32, voice: PercussionVoice, vol: float32]

  TrackSpec = object
    bpm: float32
    tonic: float32
    progression: seq[BarChord]   # cycled across bars
    intensity: seq[float32]      # one entry per bar, drives the arrangement
    melody: seq[MelodyNote]      # one phrase, repeated every phraseBars
    phraseBars: int
    melodyInstr: InstrumentKind
    leadVol, bassVol, padVol, arpVol, drumVol: float32
    arpStepBeats: float32        # arp note spacing in beats
    pumpDepth: float32           # sidechain duck depth on melodic layers
    echoDelay, echoMix: float32

proc semiFreq(tonic: float32, semi: int): float32 {.inline.} =
  tonic * pow(2.0'f32, semi.float32 / 12.0'f32)

proc chordSemis(c: BarChord): seq[int] =
  let base = case c.quality
    of cqMajor: @[0, 4, 7]
    of cqMinor: @[0, 3, 7]
    of cqMajor7: @[0, 4, 7, 11]
    of cqMinor7: @[0, 3, 7, 10]
    of cqDom7: @[0, 4, 7, 10]
    of cqSus2: @[0, 2, 7]
  result = newSeq[int](base.len)
  for i in 0..<base.len:
    result[i] = c.rootSemi + base[i]

# INSTRUMENT SYNTHESIS

proc sawVoice(freq, t: float32): float32 =
  ## Band-limited saw approximation from the first six harmonics.
  var value = 0.0'f32
  for h in 1..6:
    value += sin(2.0 * PI * freq * h.float32 * t) / h.float32
  value * 0.52

proc instrumentWave(kind: InstrumentKind, freq, t, progress: float32): float32 =
  if freq <= 0.0:
    return 0.0

  case kind
  of ikLead:
    # Three detuned saws for a wide, modern lead
    let a = sawVoice(freq * 0.9945, t)
    let b = sawVoice(freq, t)
    let c = sawVoice(freq * 1.0055, t)
    result = (a + b + c) * 0.34
  of ikBell:
    let phase = 2.0 * PI * freq * t
    result = sin(phase) * 0.70 +
             sin(phase * 2.0) * 0.18 * exp(-progress * 3.0) +
             sin(phase * 2.756) * 0.12 * exp(-progress * 5.0) +
             sin(phase * 4.0) * 0.05 * exp(-progress * 6.0)
  of ikPluck:
    # Upper harmonics fade as the note plays, like a closing filter
    let bright = exp(-progress * 6.0)
    let phase = 2.0 * PI * freq * t
    result = sin(phase) * 0.62 +
             sin(phase * 2.0) * 0.26 * bright +
             sin(phase * 3.0) * 0.13 * bright +
             sin(phase * 4.0) * 0.07 * bright * bright
  of ikBass:
    # Two-operator FM with a decaying index, plus a sub octave
    let modIndex = 2.2 * exp(-progress * 3.5)
    let carrier = sin(2.0 * PI * freq * t +
                      sin(2.0 * PI * freq * 2.0 * t) * modIndex)
    let sub = sin(2.0 * PI * freq * 0.5 * t)
    result = carrier * 0.58 + sub * 0.42
  of ikPad:
    let drift = 1.0 + sin(2.0 * PI * 0.35 * t) * 0.004
    result = (sin(2.0 * PI * freq * drift * t) +
              sin(2.0 * PI * freq * 1.004 * t) +
              sin(2.0 * PI * freq * 0.996 * t)) * 0.3

proc voiceEnvelope(kind: InstrumentKind, progress, durSec: float32): float32 =
  case kind
  of ikPluck, ikBell:
    let attack = min(0.01, durSec * 0.1) / durSec
    if progress < attack:
      result = progress / attack
    else:
      let rate = if kind == ikPluck: 5.5'f32 else: 3.2'f32
      result = exp(-(progress - attack) * rate)
  of ikLead:
    let attack = min(0.05, durSec * 0.2) / durSec
    let release = min(0.10, durSec * 0.3) / durSec
    if progress < attack:
      result = sin(progress / attack * PI * 0.5)
    elif progress > 1.0 - release:
      result = cos((progress - (1.0 - release)) / release * PI * 0.5)
    else:
      result = 1.0
  of ikBass:
    let attack = min(0.008, durSec * 0.1) / durSec
    if progress < attack:
      result = progress / attack
    else:
      result = 0.55 + 0.45 * exp(-(progress - attack) * 3.0)
    if progress > 0.9:
      result *= (1.0 - progress) / 0.1
  of ikPad:
    let attack = 0.22'f32
    let release = 0.28'f32
    if progress < attack:
      result = sin(progress / attack * PI * 0.5)
    elif progress > 1.0 - release:
      result = cos((progress - (1.0 - release)) / release * PI * 0.5)
    else:
      result = 1.0

proc renderVoice(samples: var seq[float32], freq, startSec, durSec: float32,
                 kind: InstrumentKind, volume: float32) =
  if freq <= 0.0 or durSec <= 0.0:
    return

  let startSample = max(0, int(startSec * SAMPLE_RATE.float32))
  let endSample = min(int((startSec + durSec) * SAMPLE_RATE.float32),
                      samples.len)
  if startSample >= endSample:
    return

  for i in startSample..<endSample:
    let t = i.float32 / SAMPLE_RATE.float32
    let progress = (t - startSec) / durSec
    samples[i] += instrumentWave(kind, freq, t, progress) *
                  voiceEnvelope(kind, progress, durSec) * volume

# PERCUSSION

proc deterministicNoise(sampleIndex: int): float32 {.inline.} =
  ## Stable pseudo-noise so generated percussion is repeatable between runs.
  let x = sin((sampleIndex.float32 + 1.0) * 12.9898) * 43758.5453
  (x - floor(x)) * 2.0 - 1.0

proc renderPercussionHit(samples: var seq[float32], startTime: float32,
                         volume: float32, voice: PercussionVoice) =
  let duration = case voice
    of pvKick: 0.22'f32
    of pvSnare: 0.16'f32
    of pvHat: 0.045'f32
    of pvOpenHat: 0.30'f32
    of pvSoftTick: 0.06'f32
    of pvCrash: 0.75'f32

  let startSample = max(0, int(startTime * SAMPLE_RATE.float32))
  let endSample = min(startSample + int(duration * SAMPLE_RATE.float32),
                      samples.len)
  if startSample >= endSample:
    return

  var lastNoise = 0.0'f32
  for i in startSample..<endSample:
    let hitSample = i - startSample
    let t = hitSample.float32 / SAMPLE_RATE.float32
    let progress = t / duration
    let noise = deterministicNoise(i)
    let highNoise = noise - lastNoise
    lastNoise = noise

    var value = 0.0'f32
    case voice
    of pvKick:
      let pitch = 38.0 + 94.0 * exp(-progress * 7.5)
      let body = sin(2.0 * PI * pitch * t) * exp(-progress * 5.3)
      let click = if progress < 0.055:
        highNoise * (1.0 - progress / 0.055) * 0.18
      else:
        0.0
      value = body * 0.90 + click
    of pvSnare:
      let snap = highNoise * exp(-progress * 11.0) * 0.55
      let body = (sin(2.0 * PI * 180.0 * t) * 0.32 +
                  sin(2.0 * PI * 330.0 * t) * 0.18) * exp(-progress * 7.0)
      value = snap + body
    of pvHat:
      value = highNoise * exp(-progress * 28.0) * 0.45
    of pvOpenHat:
      let sizzle = sin(2.0 * PI * 6800.0 * t) * 0.10
      value = (highNoise * 0.38 + sizzle) * exp(-progress * 7.0)
    of pvSoftTick:
      let tone = sin(2.0 * PI * 1450.0 * t) * 0.22
      value = (tone + highNoise * 0.18) * exp(-progress * 22.0)
    of pvCrash:
      let shimmer = (sin(2.0 * PI * 4200.0 * t) * 0.14 +
                     sin(2.0 * PI * 6100.0 * t) * 0.08)
      value = (noise * 0.48 + highNoise * 0.20 + shimmer) * exp(-progress * 4.8)

    samples[i] += value * volume

# EFFECTS AND MASTERING

proc applySingleEcho(samples: var seq[float32], delaySeconds, mix: float32) =
  let delaySamples = int(delaySeconds * SAMPLE_RATE.float32)
  if delaySamples <= 0 or delaySamples >= samples.len:
    return

  for i in countdown(samples.len - 1, delaySamples):
    samples[i] += samples[i - delaySamples] * mix

proc applySidechainPump(samples: var seq[float32], kicks: seq[float32],
                        depth: float32) =
  ## Duck the melodic mix right after every kick for a pumping groove.
  if depth <= 0.0:
    return

  let pumpSamples = int(0.22 * SAMPLE_RATE.float32)
  for kick in kicks:
    let startSample = max(0, int(kick * SAMPLE_RATE.float32))
    let endSample = min(startSample + pumpSamples, samples.len)
    for i in startSample..<endSample:
      let dt = (i - startSample).float32 / SAMPLE_RATE.float32
      samples[i] *= 1.0 - depth * exp(-dt * 16.0)

proc finishMusic(samples: var seq[float32], filename: string,
                 outputGain: float32): Music =
  ## Light mastering: fade protection, warm saturation, and final limiting.
  let fadeSamples = int(0.035 * SAMPLE_RATE.float32)
  var samples16 = newSeq[int16](samples.len)

  for i in 0..<samples.len:
    var value = samples[i]

    if i < fadeSamples:
      value *= i.float32 / fadeSamples.float32
    if samples.len - i < fadeSamples:
      value *= (samples.len - i).float32 / fadeSamples.float32

    let limited = tanh(value * 1.18) * outputGain
    samples16[i] = int16(clamp(limited * 32767.0, -32767.0, 32767.0))

  writeWavFile(filename, samples16, SAMPLE_RATE)
  result = loadMusicStream(filename)

# ARRANGEMENT

proc renderPadBar(spec: TrackSpec, samples: var seq[float32],
                  tones: seq[int], barStart, barLen, inten: float32) =
  if spec.padVol <= 0.0:
    return

  for idx in 0..<tones.len:
    let vol = spec.padVol * (0.55 + 0.45 * inten) *
              (if idx == 0: 1.0'f32 else: 0.8'f32)
    renderVoice(samples, semiFreq(spec.tonic, tones[idx]),
                barStart, barLen, ikPad, vol)

  # Octave shimmer when the track is running hot
  if inten > 0.7:
    renderVoice(samples, semiFreq(spec.tonic, tones[0] + 12),
                barStart, barLen, ikPad, spec.padVol * 0.5)

proc renderBassBar(spec: TrackSpec, samples: var seq[float32],
                   chord: BarChord, barStart, barLen, beat, inten: float32) =
  if spec.bassVol <= 0.0:
    return

  let rootFreq = semiFreq(spec.tonic, chord.rootSemi) * 0.5

  if inten < 0.35:
    # Sparse: one held root per bar
    renderVoice(samples, rootFreq, barStart, barLen * 0.92, ikBass,
                spec.bassVol * 0.8)
  elif inten < 0.7:
    # Moderate: quarter-note pulse with a fifth pickup
    for step in 0..3:
      let freq = if step == 3: rootFreq * 1.4983'f32 else: rootFreq
      renderVoice(samples, freq, barStart + step.float32 * beat,
                  beat * 0.85, ikBass, spec.bassVol * 0.9)
  else:
    # Driving eighth notes with octave jumps at peak intensity
    for step in 0..7:
      var freq = rootFreq
      if inten >= 0.85 and step mod 4 == 2:
        freq = rootFreq * 2.0
      elif step == 6:
        freq = rootFreq * 1.4983
      let vol = spec.bassVol * (if step mod 2 == 0: 1.0'f32 else: 0.75'f32)
      renderVoice(samples, freq, barStart + step.float32 * beat * 0.5,
                  beat * 0.42, ikBass, vol)

proc renderArpBar(spec: TrackSpec, samples: var seq[float32],
                  tones: seq[int], barStart, barLen, beat, inten: float32) =
  if spec.arpVol <= 0.0 or inten < 0.45:
    return

  # Chord tones across two octaves, played up and back down
  var arpSemis: seq[int] = @[]
  for s in tones:
    arpSemis.add(s)
  for s in tones:
    arpSemis.add(s + 12)

  let cycle = arpSemis.len * 2 - 2
  let step = spec.arpStepBeats * beat
  var pos = barStart
  var idx = 0
  while pos < barStart + barLen - 0.01:
    let k = idx mod cycle
    let j = if k < arpSemis.len: k else: cycle - k
    renderVoice(samples, semiFreq(spec.tonic, arpSemis[j]), pos,
                step * 0.85, ikPluck, spec.arpVol * (0.7 + 0.3 * inten))
    pos += step
    inc idx

proc renderMelody(spec: TrackSpec, samples: var seq[float32],
                  barLen, beat: float32) =
  let numBars = spec.intensity.len
  let phraseLen = spec.phraseBars.float32 * barLen

  var phraseStart = 0.0'f32
  while phraseStart < MUSIC_DURATION - 0.01:
    for note in spec.melody:
      let noteStart = phraseStart + note.start * beat
      let bar = min(numBars - 1, int(noteStart / barLen))
      let inten = spec.intensity[bar]
      if inten < 0.4:
        continue

      let vol = spec.leadVol * (0.65 + 0.35 * inten) * (1.0 + note.accent * 0.3)
      let freq = semiFreq(spec.tonic, note.semi)
      renderVoice(samples, freq, noteStart, note.dur * beat * 0.95,
                  spec.melodyInstr, vol)

      # Octave doubling at peak intensity for extra width
      if inten > 0.85:
        renderVoice(samples, freq * 2.0, noteStart, note.dur * beat * 0.95,
                    spec.melodyInstr, vol * 0.35)
    phraseStart += phraseLen

proc scheduleDrums(spec: TrackSpec, barLen, beat: float32,
                   events: var seq[DrumEvent], kicks: var seq[float32]) =
  let numBars = spec.intensity.len
  if spec.drumVol <= 0.0:
    return

  for bar in 0..<numBars:
    let barStart = bar.float32 * barLen
    let inten = spec.intensity[bar]
    if inten < 0.2:
      continue

    let vol = spec.drumVol

    # Kick pattern
    events.add((barStart, pvKick, vol))
    kicks.add(barStart)
    if inten >= 0.55:
      events.add((barStart + beat * 2.0'f32, pvKick, vol * 0.9'f32))
      kicks.add(barStart + beat * 2.0)
    if inten >= 0.85:
      events.add((barStart + beat * 3.5'f32, pvKick, vol * 0.7'f32))
      kicks.add(barStart + beat * 3.5)

    # Snare / backbeat
    if inten >= 0.5:
      events.add((barStart + beat, pvSnare, vol * 0.8'f32))
      events.add((barStart + beat * 3.0'f32, pvSnare, vol * 0.8'f32))
    elif inten >= 0.3:
      events.add((barStart + beat * 2.0'f32, pvSoftTick, vol * 0.6'f32))

    # Hats
    if inten >= 0.85:
      var pos = 0.0'f32
      while pos < barLen - 0.01:
        events.add((barStart + pos, pvHat, vol * 0.30'f32))
        pos += beat * 0.25
    elif inten >= 0.5:
      var pos = 0.0'f32
      var hatIdx = 0
      while pos < barLen - 0.01:
        let accent = if hatIdx mod 2 == 1: 0.32'f32 else: 0.22'f32
        events.add((barStart + pos, pvHat, vol * accent))
        pos += beat * 0.5
        inc hatIdx

    # Open hat on the last offbeat when the energy is high
    if inten >= 0.75:
      events.add((barStart + beat * 3.5'f32, pvOpenHat, vol * 0.35'f32))

    # Crash on big intensity jumps (section starts)
    if bar > 0 and inten - spec.intensity[bar - 1] >= 0.2:
      events.add((barStart, pvCrash, vol * 0.8'f32))

    # Snare fill closing every 4-bar phrase
    if bar mod 4 == 3 and inten >= 0.55:
      for j in 0..3:
        events.add((barStart + beat * 3.0'f32 + j.float32 * beat * 0.25'f32,
                    pvSnare, vol * (0.40'f32 + 0.12'f32 * j.float32)))

proc composeTrack(spec: TrackSpec, filename: string,
                  outputGain: float32): Music =
  let beat = 60.0'f32 / spec.bpm
  let barLen = beat * 4.0
  let numBars = spec.intensity.len
  var samples = newSeq[float32](int(MUSIC_DURATION * SAMPLE_RATE.float32))

  # Melodic layers first so the sidechain pump only affects them
  for bar in 0..<numBars:
    let barStart = bar.float32 * barLen
    let inten = spec.intensity[bar]
    let chord = spec.progression[bar mod spec.progression.len]
    let tones = chordSemis(chord)

    renderPadBar(spec, samples, tones, barStart, barLen, inten)
    renderBassBar(spec, samples, chord, barStart, barLen, beat, inten)
    renderArpBar(spec, samples, tones, barStart, barLen, beat, inten)

  renderMelody(spec, samples, barLen, beat)

  var drumEvents: seq[DrumEvent] = @[]
  var kicks: seq[float32] = @[]
  scheduleDrums(spec, barLen, beat, drumEvents, kicks)

  applySidechainPump(samples, kicks, spec.pumpDepth)

  for event in drumEvents:
    renderPercussionHit(samples, event.time, event.vol, event.voice)

  applySingleEcho(samples, spec.echoDelay, spec.echoMix)
  result = finishMusic(samples, filename, outputGain)

proc mn(semi: int, start, dur: float32, accent: float32 = 0.0): MelodyNote =
  MelodyNote(semi: semi, start: start, dur: dur, accent: accent)

# TRACK DEFINITIONS

proc createMenuMusic(filename: string): Music =
  ## Calm lo-fi loop in C major: Cmaj7 - Am7 - Fmaj7 - G7, soft bell lead.
  let spec = TrackSpec(
    bpm: 90.0,                    # 18 bars in 48 s
    tonic: 261.63,                # C4
    progression: @[
      BarChord(rootSemi: 0, quality: cqMajor7),
      BarChord(rootSemi: 9, quality: cqMinor7),
      BarChord(rootSemi: 5, quality: cqMajor7),
      BarChord(rootSemi: 7, quality: cqDom7)
    ],
    intensity: @[
      0.25'f32, 0.30,
      0.45, 0.50, 0.52, 0.55,
      0.60, 0.60, 0.62, 0.62,
      0.55, 0.55, 0.50, 0.45,
      0.40, 0.35, 0.30, 0.28
    ],
    melody: @[
      mn(16, 0.0, 1.5), mn(14, 2.0, 1.0), mn(19, 3.0, 1.0),
      mn(16, 4.0, 2.0), mn(12, 6.5, 1.5),
      mn(9, 8.0, 1.5), mn(12, 10.0, 1.0), mn(16, 11.0, 1.0),
      mn(14, 12.0, 2.0), mn(11, 14.0, 2.0)
    ],
    phraseBars: 4,
    melodyInstr: ikBell,
    leadVol: 0.11, bassVol: 0.12, padVol: 0.075, arpVol: 0.045,
    drumVol: 0.025, arpStepBeats: 0.5, pumpDepth: 0.0,
    echoDelay: 0.50, echoMix: 0.09)

  result = composeTrack(spec, filename, 0.92)

proc createWaveMusic(filename: string): Music =
  ## Driving combat loop in D minor: Dm - Bb - F - C with a supersaw lead.
  let spec = TrackSpec(
    bpm: 140.0,                   # 28 bars in 48 s
    tonic: 293.66,                # D4
    progression: @[
      BarChord(rootSemi: 0, quality: cqMinor),
      BarChord(rootSemi: 8, quality: cqMajor),
      BarChord(rootSemi: 3, quality: cqMajor),
      BarChord(rootSemi: 10, quality: cqMajor)
    ],
    intensity: @[
      0.55'f32, 0.60, 0.65, 0.70,
      0.75, 0.75, 0.80, 0.80,
      0.80, 0.85, 0.85, 0.85,
      0.55, 0.50, 0.55, 0.60,
      0.90, 0.90, 0.92, 0.92,
      0.95, 0.95, 0.95, 0.95,
      0.80, 0.75, 0.70, 0.65
    ],
    melody: @[
      mn(12, 0.0, 0.75, 0.3), mn(7, 0.75, 0.25), mn(12, 1.0, 0.5),
      mn(15, 1.5, 0.5), mn(14, 2.0, 1.0), mn(12, 3.0, 1.0),
      mn(15, 4.0, 0.75, 0.3), mn(12, 4.75, 0.25), mn(15, 5.0, 0.5),
      mn(17, 5.5, 0.5), mn(15, 6.0, 1.0), mn(12, 7.0, 1.0),
      mn(7, 8.0, 0.5), mn(10, 8.5, 0.5), mn(15, 9.0, 1.0, 0.3),
      mn(14, 10.0, 1.0), mn(10, 11.0, 1.0),
      mn(14, 12.0, 0.5), mn(15, 12.5, 0.5), mn(14, 13.0, 0.5),
      mn(12, 13.5, 0.5), mn(7, 14.0, 1.0), mn(10, 15.0, 1.0)
    ],
    phraseBars: 4,
    melodyInstr: ikLead,
    leadVol: 0.10, bassVol: 0.15, padVol: 0.055, arpVol: 0.055,
    drumVol: 0.085, arpStepBeats: 0.25, pumpDepth: 0.45,
    echoDelay: 0.321, echoMix: 0.06)

  result = composeTrack(spec, filename, 0.88)

proc createPowerUpMusic(filename: string): Music =
  ## Uplifting reward loop in C major: C - G - Am - F with bright plucks.
  let spec = TrackSpec(
    bpm: 110.0,                   # 22 bars in 48 s
    tonic: 261.63,                # C4
    progression: @[
      BarChord(rootSemi: 0, quality: cqMajor),
      BarChord(rootSemi: 7, quality: cqMajor),
      BarChord(rootSemi: 9, quality: cqMinor),
      BarChord(rootSemi: 5, quality: cqMajor)
    ],
    intensity: @[
      0.30'f32, 0.40,
      0.55, 0.60, 0.60, 0.65,
      0.70, 0.70, 0.75, 0.75,
      0.80, 0.80, 0.80, 0.78,
      0.70, 0.65, 0.60, 0.55,
      0.50, 0.45, 0.40, 0.35
    ],
    melody: @[
      mn(19, 0.0, 1.0), mn(16, 1.0, 1.0), mn(12, 2.0, 2.0),
      mn(14, 4.0, 1.0), mn(11, 5.0, 1.0), mn(7, 6.0, 2.0),
      mn(9, 8.0, 1.5), mn(12, 9.5, 1.5), mn(16, 11.0, 1.0),
      mn(14, 12.0, 1.0), mn(17, 13.0, 1.0), mn(16, 14.0, 2.0)
    ],
    phraseBars: 4,
    melodyInstr: ikLead,
    leadVol: 0.095, bassVol: 0.13, padVol: 0.065, arpVol: 0.055,
    drumVol: 0.05, arpStepBeats: 0.5, pumpDepth: 0.25,
    echoDelay: 0.409, echoMix: 0.07)

  result = composeTrack(spec, filename, 0.90)

proc createBossMusic(filename: string): Music =
  ## Relentless boss loop in E phrygian: Em - F - Em - D, double-kick drums.
  let spec = TrackSpec(
    bpm: 160.0,                   # 32 bars in 48 s
    tonic: 329.63,                # E4
    progression: @[
      BarChord(rootSemi: 0, quality: cqMinor),
      BarChord(rootSemi: 1, quality: cqMajor),
      BarChord(rootSemi: 0, quality: cqMinor),
      BarChord(rootSemi: 10, quality: cqMajor)
    ],
    intensity: @[
      0.70'f32, 0.75, 0.80, 0.80,
      0.85, 0.85, 0.90, 0.90,
      0.95, 0.95, 1.00, 1.00,
      1.00, 1.00, 1.00, 0.95,
      0.60, 0.60, 0.65, 0.70,
      0.90, 0.95, 1.00, 1.00,
      1.00, 1.00, 1.00, 1.00,
      0.95, 0.90, 0.90, 0.85
    ],
    melody: @[
      mn(12, 0.0, 0.5, 0.4), mn(7, 0.5, 0.25), mn(12, 0.75, 0.25),
      mn(15, 1.0, 0.5), mn(13, 1.5, 0.5), mn(12, 2.0, 0.5),
      mn(10, 2.5, 0.5), mn(12, 3.0, 1.0),
      mn(13, 4.0, 0.5, 0.4), mn(8, 4.5, 0.25), mn(13, 4.75, 0.25),
      mn(17, 5.0, 0.5), mn(15, 5.5, 0.5), mn(13, 6.0, 1.0), mn(12, 7.0, 1.0),
      mn(12, 8.0, 0.5, 0.4), mn(15, 8.5, 0.5), mn(19, 9.0, 0.5),
      mn(17, 9.5, 0.5), mn(15, 10.0, 0.5), mn(13, 10.5, 0.5), mn(12, 11.0, 1.0),
      mn(10, 12.0, 0.5, 0.4), mn(13, 12.5, 0.5), mn(17, 13.0, 0.5),
      mn(15, 13.5, 0.5), mn(13, 14.0, 0.75), mn(12, 14.75, 0.25),
      mn(13, 15.0, 1.0)
    ],
    phraseBars: 4,
    melodyInstr: ikLead,
    leadVol: 0.105, bassVol: 0.16, padVol: 0.05, arpVol: 0.05,
    drumVol: 0.10, arpStepBeats: 0.25, pumpDepth: 0.5,
    echoDelay: 0.281, echoMix: 0.05)

  result = composeTrack(spec, filename, 0.86)
# MUSIC LOADING AND SYSTEM MANAGEMENT

proc loadOrGenerateMusic(track: MusicTrack): Music =
  let cacheFile = getMusicCacheFile(track)

  if isMusicCached(track):
    return loadMusicStream(cacheFile)

  case track
  of mtMenu: result = createMenuMusic(cacheFile)
  of mtWave: result = createWaveMusic(cacheFile)
  of mtPowerUp: result = createPowerUpMusic(cacheFile)
  of mtBoss: result = createBossMusic(cacheFile)

proc cleanStaleCacheFiles() =
  ## Remove WAVs from older sound versions (pre-versioning files have no
  ## "_v" suffix; outdated versions have a different one) so they don't
  ## accumulate in the temp dir.
  let cacheDir = getCacheDir()
  for path in walkFiles(cacheDir / "*.wav"):
    let name = splitFile(path).name
    if not (name.endsWith("_" & SOUND_CACHE_VERSION) or
            name.endsWith("_" & MUSIC_CACHE_VERSION)):
      try:
        removeFile(path)
      except OSError:
        discard

# PRE-GENERATION SYSTEM
proc preGenerateAllAssets*(verbose: bool = true, callback: AssetGenerationCallback = nil) =
  cleanStaleCacheFiles()
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
      for voice in 0..<MAX_SOUND_VOICES:
        sys.soundVoices[st][voice] = loadSoundAlias(sys.cachedSounds[st])
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
proc pitchVariation(soundType: SoundType): float32 =
  ## Max random pitch deviation per play. Constantly repeated combat sounds
  ## get wide variation so they never sound robotic; musical jingles
  ## (power-up, wave fanfare, buy, game over) stay at their composed pitch.
  case soundType
  of stEnemyHit: 0.14
  of stShoot: 0.10
  of stEnemyDeath: 0.09
  of stExplosion: 0.08
  of stWallPlace: 0.07
  of stShield: 0.05
  of stCoinPickup, stTeleport, stPlayerHit: 0.04
  of stMenuNav: 0.02
  of stPowerUp, stBossSpawn, stMenuSelect, stWaveComplete, stGameOver, stBuy: 0.0

proc panSpread(soundType: SoundType): float32 =
  ## Random stereo offset for battlefield sounds; UI and jingles stay centered.
  ## Pan is in raylib's [-1, 1] range where 0 is center (NOT the older 0.5).
  case soundType
  of stShoot, stEnemyHit, stEnemyDeath, stExplosion, stCoinPickup, stWallPlace: 0.12
  else: 0.0

proc minReplayInterval(soundType: SoundType): float64 =
  ## Shortest gap between two plays of the same sound. Prevents dozens of
  ## same-frame hits/deaths from stacking into one clipped blast.
  case soundType
  of stShoot: 0.025
  of stEnemyHit: 0.03
  of stCoinPickup: 0.04
  of stEnemyDeath: 0.05
  of stExplosion: 0.07
  of stPowerUp: 0.1
  else: 0.0

proc playSound*(soundType: SoundType, volumeMultiplier: float32 = 1.0,
                pitch: float32 = 1.0) =
  let sys = globalSoundSystem
  if sys == nil or not sys.enabled or not sys.soundsGenerated:
    return
  try:
    let minInterval = minReplayInterval(soundType)
    if minInterval > 0.0:
      let now = getTime()
      if now - sys.lastPlayTime[soundType] < minInterval:
        return
      sys.lastPlayTime[soundType] = now

    # Rotate through the alias pool so overlapping plays don't cut each other
    let voiceIdx = sys.nextVoice[soundType]
    sys.nextVoice[soundType] = (voiceIdx + 1) mod MAX_SOUND_VOICES
    template voice: Sound = Sound(sys.soundVoices[soundType][voiceIdx])

    setSoundVolume(voice, sys.masterVolume * volumeMultiplier)

    let jitter = pitchVariation(soundType)
    let finalPitch = if jitter > 0.0: pitch * (1.0'f32 + rand(-jitter..jitter)) else: pitch
    setSoundPitch(voice, finalPitch)

    # Always reset pan: voices are reused and keep their last value
    let spread = panSpread(soundType)
    let pan = if spread > 0.0: rand(-spread..spread) else: 0.0'f32
    setSoundPan(voice, pan)

    raylib.playSound(voice)
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
