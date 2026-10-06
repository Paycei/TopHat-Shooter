import raylib, math, random, os, streams
import std/cpuinfo
import std/atomics
import localization

# Raylib's playSound restarts a Sound that is already playing, cutting its
# tail. Each sound gets a pool of aliases (shared sample data): a new play
# takes a voice that has already finished if there is one, so rapid-fire
# effects overlap instead of cutting each other off, and only when every voice
# is still sounding does the oldest one restart.
const MAX_SOUND_VOICES = 8

type
  SoundType* = enum
    stShoot, stEnemyHit, stEnemyDeath, stPlayerHit, stCoinPickup, stPowerUp,
    stBossSpawn, stExplosion, stWallPlace, stTeleport, stMenuNav, stMenuSelect,
    stWaveComplete, stShield, stGameOver, stBuy,
    # Restore-point animation cues (see ui/ui_helpers.drawLifeLostOverlay)
    stRestoreAccess, stRestoreSpinDown, stRestoreShatter

  MusicTrack* = enum
    mtMenu, mtWave, mtPowerUp, mtBoss, mtSurvival, mtRoguelite,
    # Story scores: composed against a cinematic's cuts (story timing below),
    # played once from the top and never looped. See isScoreTrack.
    mtStoryIntro, mtStoryRootAccess, mtStoryBelow, mtStoryUptime

  MusicStreamState = enum
    ## Where a music stream is (see "MUSIC PLAYBACK").
    msIdle,    ## stopped: the next start plays it from the top
    msIn,      ## the current track
    msOut      ## being left: still playing while it fades out

  TierStream = object
    ## A built-in loop as it plays: a raylib stream the main thread fills from
    ## the loop's tier WAVs (see MUSIC PLAYBACK).
    stream: AudioStream
    ready: bool                 # files open and the stream loaded
    files: seq[File]            # one per tier, all the same length
    frames, barFrames: int      # the loop's length; samples per bar
    pos: int                    # the next loop frame to hand to raylib
    tier, target: int           # the tier playing; the tier asked for
    switchAt: int               # loop frame where `target` takes over (-1: none)
    fromTier, xfadeLeft: int    # the tier crossing out, and for how much longer
    fadeLeft: int               # fade-in frames left after a start
    muffle, lp1, lp2: float32   # the low-health blend and its lowpass states
    raw, other: seq[int16]
    output: seq[float32]

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
    trackPlaying: bool          # currentTrack is msIn
    streamState: array[MusicTrack, MusicStreamState]
    fade: array[MusicTrack, float32]       # 0..1, equal-power volume curve
    fadeRate: array[MusicTrack, float32]   # fade units per second
    tierStreams: array[MusicTrack, TierStream]   # the built-in loops
    lastMusicTick: float64

var globalSoundSystem*: SoundSystem

# Set at shutdown so the background music worker can bail out instead of
# composing every remaining track while the player waits for the window to
# close. Declared up here because composeTrack (far below) checks it too.
var genCancel: Atomic[bool]

# Musical constants are declared before cache helpers because cache validation
# depends on the generated WAV length.
const
  SAMPLE_RATE = 44100'u32
  MUSIC_CACHE_VERSION = "v7"  # loops; bump when a loop or the engine changes
  SCORE_CACHE_VERSION = "s7"  # story scores; bump when any create*Score or the engine changes
  SOUND_CACHE_VERSION = "v6"  # bump when any create* synthesis changes
  MaxSynthThreads = 32      # cap: past this the mix is memory-bound, not CPU-bound
  ChunksPerSynthThread = 6  # oversubscribe chunks so uneven bars still balance

# STORY CINEMATIC TIMING
#
# The single source of truth for when things happen in the four story
# cinematics (ui/lore_cinematic, ui/endgame_cinematic, ui/roguelite_end_cinematic,
# ui/survival_end_cinematic). Their shots are built from these lengths, and the
# story scores below are composed against the same numbers, so a cue cannot
# drift off its frame. It lives here, the lowest module both sides import.
#
# Every value is in CUTSCENE seconds (the clock the shots read). Cutscenes run
# at StoryPlaybackSpeed, so a cue's position in the music is
# `cutsceneTime / StoryPlaybackSpeed` real seconds (see `scoreTime`).

const
  StoryPlaybackSpeed* = 1.2'f32
    ## Every cinematic plays at this pace. Scaling the clock instead of the shot
    ## durations keeps each shot's internal beats (captions, staged reveals)
    ## lined up with its fades.

  ScoreTail* = 2.0'f32
    ## Real seconds of music past a score's last cut, so the final chord rings
    ## out under the fade instead of the stream running dry on screen.

  # ACT I: CLEANUP (first-launch intro, REC 00-05). It is a new player's only
  # explanation of the story, so every beat gets time to land and the
  # captions time to be read (they type at IntroCaptionCps); ~54 real seconds.
  IntroCaptionCps* = 26.0'f32
  IntroShots* = [11.4'f32, 10.0, 11.5, 10.0, 10.5, 11.5]
  IntroCleanupOpen* = 1.6'f32      ## shot 0: the Disk Cleanup dialog pops up
  IntroCleanupClick* = 4.0'f32     ## shot 0: the pointer clicks "Clean up"
  IntroCleanupStall* = 7.0'f32     ## shot 0: the progress bar stops dead
  IntroCleanupError* = 7.15'f32    ## shot 0: "Permission denied" appears
  IntroProcRowStart* = 0.8'f32     ## shot 1: first root-owned process row
  IntroProcRowEvery* = 0.45'f32    ## shot 1: one new row this often
  IntroProcRows* = 14
  IntroWhoAt* = 1.0'f32            ## shot 2: "WHO ARE YOU?" starts typing
  IntroWhoDur* = 1.3'f32           ##         ...and lands (beep) this much later
  IntroMachineAt* = 3.6'f32        ## shot 2: "THIS IS MY MACHINE." starts
  IntroMachineDur* = 1.7'f32
  IntroWhoCaptionAt* = 5.9'f32     ## shot 2: TOPHAT's caption, once root has spoken
  IntroBootAt* = 3.6'f32           ## shot 3: shooter.exe boots under the beam
  IntroFlipStart* = 1.2'f32        ## shot 4: first service changes owner
  IntroFlipEvery* = 0.5'f32        ## shot 4: one service per step (11 of them)
  IntroTitleAt* = 7.0'f32          ## shot 5: the title slams in

  # The endings run longer and slower than the intro: the intro has to hook,
  # an ending has to land. Each key beat gets room before and after it, and
  # their captions type slower (EndingCaptionCps).
  EndingCaptionCps* = 30.0'f32

  # ACT II: ROOT ACCESS (wave-60 ending, REC 06-10)
  RootAccessShots* = [7.6'f32, 7.2, 8.6, 8.0, 4.0]
  RootCutOffAt* = 2.8'f32          ## shot 0: root is cut off mid-sentence
  RootTypeAt* = 0.6'f32            ## shot 0: root starts typing
  RootHomeStart* = 0.9'f32         ## shot 1: first service flips back to tophat
  RootHomeEvery* = 0.38'f32
  RootHatYesAt* = 1.8'f32          ## shot 2: the transfer dialog's [Yes] presses
  RootHatLandAt* = 4.8'f32         ## shot 2: the hat settles on shooter.exe
  RootStingBeepAt* = 1.6'f32       ## shot 4: one beep from below

  # ACT III: BELOW THE PARTITION (roguelite ending, DELVE 01-06)
  BelowShots* = [6.8'f32, 7.8, 8.4, 7.8, 9.2, 8.6]
  BelowLogStart* = 0.6'f32         ## shot 2: first boot-log line
  BelowLogEvery* = 0.55'f32        ## shot 2: one line this often (9 lines)
  BelowLogLines* = 9
  BelowFirstAt* = 0.9'f32          ## shot 3: "I WAS HERE FIRST." starts typing
  BelowFirstDur* = 1.6'f32
  BelowYesAt* = 1.3'f32            ## shot 4: [Shut down] presses
  BelowSafeAt* = 4.6'f32           ## shot 4: "It's now safe to turn off..." screen

  # ACT IV: UPTIME (survival ending, LOG 01-05)
  UptimeShots* = [7.2'f32, 6.4, 7.0, 8.0, 11.0]
  UptimeCrashAt* = 0.0'f32         ## shot 2: the crash lands on the cut
  UptimeFormatAt* = 1.2'f32        ## shot 3: the new installer starts formatting
  UptimeNewBootAt* = 0.4'f32       ## shot 4: the new OS chimes
  UptimeSinkAt* = 2.4'f32          ## shot 4: the camera sinks below the new OS
  UptimeWhoAt* = 4.0'f32           ## shot 4: "WHO ARE YOU?" from below
  UptimeWhoDur* = 1.1'f32
  UptimeMachineAt* = 5.8'f32       ## shot 4: "THIS IS MY MACHINE."
  UptimeMachineDur* = 1.6'f32

proc shotStart*(shots: openArray[float32], index: int): float32 =
  ## Cutscene time at which shot `index` begins.
  for i in 0..<min(index, shots.len):
    result += shots[i]

proc totalLength*(shots: openArray[float32]): float32 =
  shotStart(shots, shots.len)

proc scoreTime*(shots: openArray[float32], index: int, local: float32): float32 =
  ## Real-time position in the score of `local` cutscene seconds into shot `index`.
  (shotStart(shots, index) + local) / StoryPlaybackSpeed

proc scoreLength*(shots: openArray[float32]): float32 =
  ## Length of a cinematic's score in real seconds, tail included.
  totalLength(shots) / StoryPlaybackSpeed + ScoreTail

proc isScoreTrack*(track: MusicTrack): bool =
  ## A cinematic's score: starts from the top on cue and does not loop.
  track >= mtStoryIntro

proc loopShape(track: MusicTrack): tuple[bpm: float64, bars: int] =
  ## Tempo and length of each gameplay loop; its TrackSpec has to agree (see
  ## createLoop). A loop is a whole number of bars, so raylib and the tier
  ## player wrap it on a bar line.
  case track
  of mtMenu: (90.0, 18)          # 48 s
  of mtWave: (140.0, 28)         # 48 s
  of mtPowerUp: (110.0, 22)      # 48 s
  of mtBoss: (160.0, 32)         # 48 s
  of mtSurvival: (126.0, 24)     # 45.7 s
  of mtRoguelite: (100.0, 20)    # 48 s
  of mtStoryIntro, mtStoryRootAccess, mtStoryBelow, mtStoryUptime: (0.0, 0)

proc musicTiers(track: MusicTrack): int =
  ## How many arrangements a track is rendered in (see TIERS): the run themes
  ## follow the run; everything else is one piece.
  case track
  of mtWave, mtBoss, mtRoguelite: 3
  of mtSurvival: 4
  of mtMenu, mtPowerUp, mtStoryIntro, mtStoryRootAccess, mtStoryBelow, mtStoryUptime: 1

proc scoreFrames(shots: openArray[float32]): int =
  int(scoreLength(shots) * SAMPLE_RATE.float32)

proc trackFrameCount(track: MusicTrack): int =
  ## Length of a track's WAV in samples (mono). Pure, so cache validation can
  ## call it without composing anything.
  case track
  of mtMenu, mtWave, mtPowerUp, mtBoss, mtSurvival, mtRoguelite:
    let shape = loopShape(track)
    int(round(shape.bars.float64 * 240.0 * SAMPLE_RATE.float64 / shape.bpm))
  of mtStoryIntro: scoreFrames(IntroShots)
  of mtStoryRootAccess: scoreFrames(RootAccessShots)
  of mtStoryBelow: scoreFrames(BelowShots)
  of mtStoryUptime: scoreFrames(UptimeShots)

proc expectedMusicCacheBytes(track: MusicTrack): int64 =
  44'i64 + int64(trackFrameCount(track)) * 2

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
    of stBuy: "buy"
    of stRestoreAccess: "restoreaccess"
    of stRestoreSpinDown: "restorespindown"
    of stRestoreShatter: "restoreshatter"
  result = cacheDir / (soundName & "_" & SOUND_CACHE_VERSION & ".wav")

proc getMusicCacheFile(track: MusicTrack, tier = 0): string =
  ## A track's WAV; a run theme has one per tier ("wave_music_t1_v7.wav").
  let cacheDir = getCacheDir()
  let trackName = case track
    of mtMenu: "menu_music"
    of mtWave: "wave_music"
    of mtPowerUp: "powerup_music"
    of mtBoss: "boss_music"
    of mtSurvival: "survival_music"
    of mtRoguelite: "roguelite_music"
    of mtStoryIntro: "story_cleanup"
    of mtStoryRootAccess: "story_root_access"
    of mtStoryBelow: "story_below"
    of mtStoryUptime: "story_uptime"
  let version = if isScoreTrack(track): SCORE_CACHE_VERSION else: MUSIC_CACHE_VERSION
  let tierName = if musicTiers(track) > 1: "_t" & $tier else: ""
  result = cacheDir / (trackName & tierName & "_" & version & ".wav")

proc isSoundCached(soundType: SoundType): bool =
  fileExists(getSoundCacheFile(soundType))

proc isTierCached(track: MusicTrack, tier: int): bool =
  let cacheFile = getMusicCacheFile(track, tier)
  try:
    fileExists(cacheFile) and getFileSize(cacheFile) == expectedMusicCacheBytes(track)
  except OSError:
    false

proc isMusicCached(track: MusicTrack): bool =
  ## Every WAV of the track (every tier of a run theme) is on disk, whole.
  for tier in 0..<musicTiers(track):
    if not isTierCached(track, tier):
      return false
  true

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

proc writeWavFile(filename: string, samples: seq[int16], sampleRate: uint32,
                  channels = 1) =
  ## 16-bit PCM WAV. `samples` is interleaved when `channels` > 1.
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
    stream.write(uint16(channels))
    stream.write(uint32(sampleRate))
    stream.write(uint32(sampleRate) * uint32(channels * 2))
    stream.write(uint16(channels * 2))
    stream.write(uint16(16))
    stream.write("data")
    stream.write(uint32(dataSize))

    # One block write: a track is millions of samples, too many for one call each.
    if numSamples > 0:
      stream.writeData(addr samples[0], dataSize)
  finally:
    if not stream.isNil:
      stream.close()

# ============================================================================
# SHARED SYNTHESIS
#
# What every piece of the soundtrack builds on: the names of its instruments
# and drums, the chord and melody types, and how a render is split across
# threads.
# ============================================================================

type
  InstrumentKind = enum
    ## The soundtrack's instruments (see INSTRUMENT SYNTHESIS).
    ikLead,   # detuned saws
    ikBell,   # a bell
    ikPluck,  # a plucked note whose brightness dies away
    ikBass,   # bass with a sub octave under it
    ikPad,    # detuned pad voices
    ikSquare, # PC-speaker square: the old system's voice (root)
    ikDrone   # dark beating sine drone for tension beds

  PercussionVoice = enum
    pvKick, pvSnare, pvHat, pvOpenHat, pvSoftTick, pvCrash,
    pvBoom,   # cinematic impact: pitch-dropping sub plus a noise burst
    pvRiser,  # noise swell that ends exactly where the next hit lands
    pvClick   # a mouse click

  ChordQuality = enum
    cqMajor, cqMinor, cqMajor7, cqMinor7, cqDom7, cqSus2, cqSus4, cqDim

  BarChord = object
    rootSemi: int          # semitones above the track tonic
    quality: ChordQuality

  MelodyNote = object
    semi: int              # semitones above the track tonic
    start: float32         # beats from phrase start
    dur: float32           # beats
    accent: float32        # 0..1 extra emphasis

const
  SRf = SAMPLE_RATE.float32
  SR64 = SAMPLE_RATE.float64
  RiserLength = 1.4'f32
    ## A riser is scheduled to END on its hit (see riserInto).

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
    of cqSus4: @[0, 5, 7]
    of cqDim: @[0, 3, 6]
  result = newSeq[int](base.len)
  for i in 0..<base.len:
    result[i] = c.rootSemi + base[i]

# PARALLEL RENDERING
#
# Each stage splits the OUTPUT SAMPLE RANGE across threads: every thread owns
# a disjoint set of chunks of the buffer and renders the part of every note or
# hit that lands inside them. Notes overlap in time, so splitting the notes
# themselves would have two threads writing one sample; splitting the samples
# needs no locks and no atomics. Each sample still sums its notes in event
# list order, so a track renders bit-identically on any number of cores.

type
  ChunkPlan = object
    ## How one parallel stage carves `totalLen` samples up between threads.
    ## Chunks are handed out strided, not as one contiguous block each: a track
    ## opens quiet and peaks in the middle, so contiguous blocks would leave the
    ## threads holding the intro idle while the middle ones still grind.
    totalLen, chunkCount, chunkSize: int
    firstChunk, threadStride: int

iterator chunks(plan: ChunkPlan): tuple[lo, hi: int] =
  ## Yields this thread's share of the sample range, cancellation-aware.
  var chunk = plan.firstChunk
  while chunk < plan.chunkCount and not genCancel.load():
    let lo = chunk * plan.chunkSize
    let hi = min(lo + plan.chunkSize, plan.totalLen)
    if lo < hi:
      yield (lo, hi)
    chunk += plan.threadStride

proc planChunks(totalLen, threadCount, thread: int): ChunkPlan =
  # Several chunks per thread so a thread that draws a sparse stretch of the
  # track comes back for more instead of finishing early.
  let chunkCount = threadCount * ChunksPerSynthThread
  ChunkPlan(totalLen: totalLen, chunkCount: chunkCount,
            chunkSize: (totalLen + chunkCount - 1) div chunkCount,
            firstChunk: thread, threadStride: threadCount)

proc synthThreadCount(): int = clamp(countProcessors(), 1, MaxSynthThreads)

# ============================================================================
# SHARED MUSICAL MATERIAL
#
# Notes and TOPHAT's leitmotif (hatMotif), shared by the story scores.
# ============================================================================

const
  E2 = 82.41'f32
  E3 = 164.81'f32
  E4 = 329.63'f32
  A2 = 110.0'f32
  A3 = 220.0'f32
  A4 = 440.0'f32
  D2 = 73.42'f32
  D3 = 146.83'f32
  D4 = 293.66'f32
  G3 = 196.0'f32
  G4 = 392.0'f32
  BeepHigh = 880.0'f32   # the question beep (A5)
  BeepLow = 659.26'f32   # the statement beep (E5)

proc mn(semi: int, start, dur: float32, accent: float32 = 0.0): MelodyNote =
  MelodyNote(semi: semi, start: start, dur: dur, accent: accent)

proc hatMotif(minor: bool): seq[MelodyNote] =
  ## TOPHAT's leitmotif: a fifth up, then a step-wise fall onto the third.
  let third = if minor: 3 else: 4
  @[mn(0, 0.0, 1.0, 0.3), mn(7, 1.0, 0.5), mn(5, 1.5, 0.5),
    mn(third, 2.0, 1.0), mn(2, 3.0, 0.5), mn(third, 3.5, 1.5)]

# ============================================================================
# PROCEDURAL MUSIC ENGINE (v4)
#
# The soundtrack's own engine, the one it shipped with. A loop is a TrackSpec:
# a tempo, a tonic, a chord progression, one intensity per bar and a melody
# phrase. The intensity arranges each bar (the bass pattern, whether the arp
# and the hats play, the extra kick, the lead's octave doubling, the pad's
# shimmer); the notes are mixed in parallel into one mono buffer, pumped by
# the kick, given a single echo and limited into a 16-bit WAV.
#
# Three things differ from the engine as it shipped, all of them defects:
# time is float64 (in float32 the high partials turned gritty as a track went
# on), the pad's slow drift is integrated instead of multiplied by the track
# time (which pulled held chords further out of tune every second), and a loop
# is circular: a note, drum or echo tail that runs past the end carries on at
# the start, where the old loops faded to silence and back at every repeat.
#
# TIERS. The run themes (wave, boss, survival, roguelite) are rendered once
# per tier: the theme's own intensity curve squeezed into a lower or a higher
# band, so the same chords and the same melody, on the same bars, get a
# sparser or a fuller arrangement. The player changes tier on a bar line (see
# MUSIC PLAYBACK), which sounds like the band building up or dropping back.
# ============================================================================

type
  VoiceEvent = object
    freq, startSec, durSec, volume: float32
    kind: InstrumentKind

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
    outputGain: float32          # the master's level after the limiter

const
  LoopTail = 2.0'f32
    ## Seconds a loop is rendered past its end, to be folded back onto its
    ## start: longer than any note, drum or echo that can cross the seam.

# INSTRUMENT SYNTHESIS

proc sawVoice(freq: float32, t: float64): float32 =
  ## Band-limited saw approximation from the first six harmonics.
  var value = 0.0'f32
  for h in 1..6:
    value += float32(sin(2.0 * PI * freq.float64 * h.float64 * t)) / h.float32
  value * 0.52

proc instrumentWave(kind: InstrumentKind, freq: float32, t: float64,
                    progress: float32): float32 =
  if freq <= 0.0:
    return 0.0

  let phase = 2.0 * PI * freq.float64 * t
  case kind
  of ikLead:
    # Three detuned saws for a wide, modern lead
    let a = sawVoice(freq * 0.9945, t)
    let b = sawVoice(freq, t)
    let c = sawVoice(freq * 1.0055, t)
    result = (a + b + c) * 0.34
  of ikBell:
    result = float32(sin(phase)) * 0.70 +
             float32(sin(phase * 2.0)) * 0.18 * exp(-progress * 3.0) +
             float32(sin(phase * 2.756)) * 0.12 * exp(-progress * 5.0) +
             float32(sin(phase * 4.0)) * 0.05 * exp(-progress * 6.0)
  of ikPluck:
    # Upper harmonics fade as the note plays, like a closing filter
    let bright = exp(-progress * 6.0)
    result = float32(sin(phase)) * 0.62 +
             float32(sin(phase * 2.0)) * 0.26 * bright +
             float32(sin(phase * 3.0)) * 0.13 * bright +
             float32(sin(phase * 4.0)) * 0.07 * bright * bright
  of ikBass:
    # Two-operator FM with a decaying index, plus a sub octave
    let modIndex = 2.2 * exp(-progress * 3.5)
    let carrier = sin(phase + sin(phase * 2.0) * modIndex.float64)
    let sub = sin(phase * 0.5)
    result = float32(carrier * 0.58 + sub * 0.42)
  of ikPad:
    # The first voice drifts +-0.4% at 0.35 Hz. Its phase is the integral of
    # that wobble (the shipped pad multiplied the wobble by the track time,
    # which swung it further out of tune every second it played).
    let lfo = 2.0 * PI * 0.35
    let drifted = t + 0.004 / lfo * (1.0 - cos(lfo * t))
    result = float32(sin(2.0 * PI * freq.float64 * drifted) +
                     sin(phase * 1.004) + sin(phase * 0.996)) * 0.3
  of ikSquare:
    # Odd harmonics only, stopped at the 9th so a high beep stays under Nyquist.
    result = float32(sin(phase) + sin(phase * 3.0) / 3.0 + sin(phase * 5.0) / 5.0 +
                     sin(phase * 7.0) / 7.0 + sin(phase * 9.0) / 9.0) * 0.55
  of ikDrone:
    # Two sines a fraction of a hertz apart beat slowly against each other.
    result = float32((sin(phase) * 0.55 + sin(2.0 * PI * (freq.float64 + 0.7) * t) * 0.35 +
                      sin(phase * 2.0) * 0.12) * (0.8 + 0.2 * sin(2.0 * PI * 0.25 * t)))

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
  of ikSquare:
    # Gated like a real PC speaker: on, flat, off. The few milliseconds of
    # ramp only stop the edges from clicking.
    let ramp = min(0.004, durSec * 0.2) / durSec
    if progress < ramp:
      result = progress / ramp
    elif progress > 1.0 - ramp:
      result = (1.0 - progress) / ramp
    else:
      result = 1.0
  of ikDrone:
    let attack = min(1.2, durSec * 0.35) / durSec
    let release = min(1.5, durSec * 0.35) / durSec
    if progress < attack:
      result = sin(progress / attack * PI * 0.5)
    elif progress > 1.0 - release:
      result = cos((progress - (1.0 - release)) / release * PI * 0.5)
    else:
      result = 1.0

# PARALLEL VOICE RENDERING
#
# Split by OUTPUT SAMPLE RANGE (see PARALLEL RENDERING): every thread owns a
# disjoint set of chunks of the buffer and renders the part of every note that
# lands inside them, so no two threads ever write one sample.

type
  RenderSlice = object
    plan: ChunkPlan
    samples: ptr UncheckedArray[float32]
    events: ptr UncheckedArray[VoiceEvent]
    eventCount: int

  DrumSlice = object
    plan: ChunkPlan
    samples: ptr UncheckedArray[float32]
    hits: ptr UncheckedArray[DrumEvent]
    hitCount: int

  MasterSlice = object
    plan: ChunkPlan
    samples: ptr UncheckedArray[float32]
    output: ptr UncheckedArray[int16]
    fadeSamples: int
    outputGain: float32

proc addVoice(events: var seq[VoiceEvent], freq, startSec, durSec: float32,
              kind: InstrumentKind, volume: float32) {.inline.} =
  events.add VoiceEvent(freq: freq, startSec: startSec, durSec: durSec,
                        kind: kind, volume: volume)

proc renderEventInto(s: ptr UncheckedArray[float32], totalLen: int,
                     ev: VoiceEvent, lo, hi: int) {.inline.} =
  ## Render just the part of `ev` that falls inside samples[lo..<hi].
  if ev.freq <= 0.0 or ev.durSec <= 0.0:
    return
  let startSample = max(0, int(ev.startSec * SRf))
  let endSample = min(int((ev.startSec + ev.durSec) * SRf), totalLen)
  let a = max(startSample, lo)
  let b = min(endSample, hi)
  if a >= b:
    return
  for i in a..<b:
    let t = i.float64 / SR64
    let progress = float32((t - ev.startSec.float64) / ev.durSec.float64)
    s[i] += instrumentWave(ev.kind, ev.freq, t, progress) *
            voiceEnvelope(ev.kind, progress, ev.durSec) * ev.volume

proc renderSliceWorker(slice: RenderSlice) {.thread.} =
  for (lo, hi) in slice.plan.chunks:
    for e in 0..<slice.eventCount:
      renderEventInto(slice.samples, slice.plan.totalLen, slice.events[e], lo, hi)

proc renderVoices(samples: var seq[float32], events: seq[VoiceEvent]) =
  ## Mix every collected voice into `samples`, across all available cores.
  if events.len == 0 or samples.len == 0:
    return
  let threadCount = synthThreadCount()
  let sp = cast[ptr UncheckedArray[float32]](addr samples[0])
  let ep = cast[ptr UncheckedArray[VoiceEvent]](addr events[0])
  var threads = newSeq[Thread[RenderSlice]](threadCount)
  for k in 0..<threadCount:
    createThread(threads[k], renderSliceWorker, RenderSlice(
      plan: planChunks(samples.len, threadCount, k),
      samples: sp, events: ep, eventCount: events.len))
  joinThreads(threads)

# PERCUSSION

proc deterministicNoise(sampleIndex: int): float32 {.inline.} =
  ## Stable pseudo-noise so generated percussion is repeatable between runs.
  let x = sin((sampleIndex.float32 + 1.0) * 12.9898) * 43758.5453
  (x - floor(x)) * 2.0 - 1.0

proc renderPercussionInto(s: ptr UncheckedArray[float32], totalLen: int,
                          startTime: float32, volume: float32,
                          voice: PercussionVoice, lo, hi: int) =
  ## Render just the part of one drum hit that falls inside samples[lo..<hi].
  let duration = case voice
    of pvKick: 0.22'f32
    of pvSnare: 0.16'f32
    of pvHat: 0.045'f32
    of pvOpenHat: 0.30'f32
    of pvSoftTick: 0.06'f32
    of pvCrash: 0.75'f32
    of pvBoom: 1.6'f32
    of pvRiser: RiserLength
    of pvClick: 0.025'f32

  let startSample = max(0, int(startTime * SRf))
  let endSample = min(startSample + int(duration * SRf), totalLen)
  let a = max(startSample, lo)
  let b = min(endSample, hi)
  if a >= b:
    return

  # highNoise is a one-sample difference, so resuming mid-hit needs the sample
  # just before `a`; deterministicNoise is a pure function of the index, so
  # that value can simply be recomputed. At the true start of a hit there is
  # no previous sample and 0 stands in, so a chunk-split hit renders exactly
  # like an unsplit one.
  var lastNoise = if a > startSample: deterministicNoise(a - 1) else: 0.0'f32
  for i in a..<b:
    let hitSample = i - startSample
    let t = hitSample.float32 / SRf
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
    of pvBoom:
      let pitch = 28.0 + 62.0 * exp(-progress * 5.5)
      let body = sin(2.0 * PI * pitch * t) * exp(-progress * 2.6)
      let burst = if progress < 0.06: noise * (1.0 - progress / 0.06) * 0.55 else: 0.0
      value = body * 1.05 + burst
    of pvRiser:
      # Brightness and level climb together; a sine sweep (200 -> 1200 Hz,
      # integrated so the phase stays continuous) gives the swell a pitch.
      let swell = pow(progress, 2.2)
      let sweep = sin(2.0 * PI * (200.0 * t + 500.0 * t * t / duration))
      value = (noise * (1.0 - progress) * 0.25 + highNoise * progress * 0.45 +
               sweep * 0.12) * swell
    of pvClick:
      value = (highNoise * 0.7 + sin(2.0 * PI * 2900.0 * t) * 0.25) * exp(-progress * 9.0)

    s[i] += value * volume

proc drumSliceWorker(slice: DrumSlice) {.thread.} =
  for (lo, hi) in slice.plan.chunks:
    for h in 0..<slice.hitCount:
      let hit = slice.hits[h]
      renderPercussionInto(slice.samples, slice.plan.totalLen, hit.time,
                           hit.vol, hit.voice, lo, hi)

proc renderDrums(samples: var seq[float32], hits: seq[DrumEvent]) =
  if hits.len == 0 or samples.len == 0:
    return
  let threadCount = synthThreadCount()
  let sp = cast[ptr UncheckedArray[float32]](addr samples[0])
  let hp = cast[ptr UncheckedArray[DrumEvent]](addr hits[0])
  var threads = newSeq[Thread[DrumSlice]](threadCount)
  for k in 0..<threadCount:
    createThread(threads[k], drumSliceWorker, DrumSlice(
      plan: planChunks(samples.len, threadCount, k),
      samples: sp, hits: hp, hitCount: hits.len))
  joinThreads(threads)

# EFFECTS AND MASTERING

proc foldTail(rendered: seq[float32], frames: int): seq[float32] =
  ## A loop rendered `frames` long plus a tail: the tail laid back over the
  ## start, as the loop sounds when it comes round.
  result = rendered[0 ..< frames]
  for i in frames ..< rendered.len:
    result[(i - frames) mod frames] += rendered[i]

proc applySingleEcho(samples: var seq[float32], delaySeconds, mix: float32,
                     looped = false) =
  ## One repeat, `delaySeconds` late. In a loop the repeat of its last moments
  ## lands on its first ones.
  let delaySamples = int(delaySeconds * SRf)
  if delaySamples <= 0 or delaySamples >= samples.len:
    return
  if looped:
    let dry = samples
    for i in 0..<samples.len:
      var j = i - delaySamples
      if j < 0:
        j += samples.len
      samples[i] += dry[j] * mix
  else:
    for i in countdown(samples.len - 1, delaySamples):
      samples[i] += samples[i - delaySamples] * mix

proc applySidechainPump(samples: var seq[float32], kicks: seq[float32],
                        depth: float32, looped = false) =
  ## Duck the melodic mix right after every kick for a pumping groove. In a
  ## loop a kick near the end ducks the start.
  if depth <= 0.0 or samples.len == 0:
    return

  let pumpSamples = int(0.22 * SRf)
  for kick in kicks:
    let startSample = max(0, int(kick * SRf))
    for j in 0..<pumpSamples:
      var i = startSample + j
      if i >= samples.len:
        if not looped:
          break
        i -= samples.len
      let dt = j.float32 / SRf
      samples[i] *= 1.0 - depth * exp(-dt * 16.0)

proc masterSliceWorker(slice: MasterSlice) {.thread.} =
  ## Per-sample limiting is a pure map, so each thread owns its own output
  ## range and nothing is shared.
  let total = slice.plan.totalLen
  for (lo, hi) in slice.plan.chunks:
    for i in lo..<hi:
      var value = slice.samples[i]
      if i < slice.fadeSamples:
        value *= i.float32 / slice.fadeSamples.float32
      if total - i < slice.fadeSamples:
        value *= (total - i).float32 / slice.fadeSamples.float32
      let limited = tanh(value * 1.18) * slice.outputGain
      slice.output[i] = int16(clamp(limited * 32767.0, -32767.0, 32767.0))

proc finishMusic(samples: var seq[float32], filename: string,
                 outputGain: float32, fade = true) =
  ## Light mastering: warm saturation and final limiting, and a 35 ms fade at
  ## both ends unless the track is a loop (a loop has no ends). Writes the WAV
  ## only, no raylib call, so it is safe on the asset-generation worker.
  let fadeSamples = if fade: int(0.035 * SRf) else: 0
  var samples16 = newSeq[int16](samples.len)
  if samples.len > 0:
    let threadCount = synthThreadCount()
    var threads = newSeq[Thread[MasterSlice]](threadCount)
    for k in 0..<threadCount:
      createThread(threads[k], masterSliceWorker, MasterSlice(
        plan: planChunks(samples.len, threadCount, k),
        samples: cast[ptr UncheckedArray[float32]](addr samples[0]),
        output: cast[ptr UncheckedArray[int16]](addr samples16[0]),
        fadeSamples: fadeSamples, outputGain: outputGain))
    joinThreads(threads)

  if genCancel.load():
    return
  writeWavFile(filename, samples16, SAMPLE_RATE)

# ARRANGEMENT

proc renderPadBar(spec: TrackSpec, events: var seq[VoiceEvent],
                  tones: seq[int], barStart, barLen, inten: float32) =
  if spec.padVol <= 0.0:
    return

  for idx in 0..<tones.len:
    let vol = spec.padVol * (0.55 + 0.45 * inten) *
              (if idx == 0: 1.0'f32 else: 0.8'f32)
    addVoice(events, semiFreq(spec.tonic, tones[idx]),
                barStart, barLen, ikPad, vol)

  # Octave shimmer when the track is running hot
  if inten > 0.7:
    addVoice(events, semiFreq(spec.tonic, tones[0] + 12),
                barStart, barLen, ikPad, spec.padVol * 0.5)

proc renderBassBar(spec: TrackSpec, events: var seq[VoiceEvent],
                   chord: BarChord, barStart, barLen, beat, inten: float32) =
  if spec.bassVol <= 0.0:
    return

  let rootFreq = semiFreq(spec.tonic, chord.rootSemi) * 0.5

  if inten < 0.35:
    # Sparse: one held root per bar
    addVoice(events, rootFreq, barStart, barLen * 0.92, ikBass,
                spec.bassVol * 0.8)
  elif inten < 0.7:
    # Moderate: quarter-note pulse with a fifth pickup
    for step in 0..3:
      let freq = if step == 3: rootFreq * 1.4983'f32 else: rootFreq
      addVoice(events, freq, barStart + step.float32 * beat,
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
      addVoice(events, freq, barStart + step.float32 * beat * 0.5,
                  beat * 0.42, ikBass, vol)

proc renderArpBar(spec: TrackSpec, events: var seq[VoiceEvent],
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
    addVoice(events, semiFreq(spec.tonic, arpSemis[j]), pos,
                step * 0.85, ikPluck, spec.arpVol * (0.7 + 0.3 * inten))
    pos += step
    inc idx

proc renderMelody(spec: TrackSpec, events: var seq[VoiceEvent],
                  barLen, beat, loopSec: float32) =
  let numBars = spec.intensity.len
  let phraseLen = spec.phraseBars.float32 * barLen

  var phraseStart = 0.0'f32
  while phraseStart < loopSec - 0.01:
    for note in spec.melody:
      let noteStart = phraseStart + note.start * beat
      let bar = min(numBars - 1, int(noteStart / barLen))
      let inten = spec.intensity[bar]
      if inten < 0.4:
        continue

      let vol = spec.leadVol * (0.65 + 0.35 * inten) * (1.0 + note.accent * 0.3)
      let freq = semiFreq(spec.tonic, note.semi)
      addVoice(events, freq, noteStart, note.dur * beat * 0.95,
                  spec.melodyInstr, vol)

      # Octave doubling at peak intensity for extra width
      if inten > 0.85:
        addVoice(events, freq * 2.0, noteStart, note.dur * beat * 0.95,
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

proc loopFrames(spec: TrackSpec): int =
  ## A loop's length in samples: its bars, whole.
  int(round(spec.intensity.len.float64 * 240.0 * SR64 / spec.bpm.float64))

proc composeTrack(spec: TrackSpec, filename: string) =
  ## Render a loop: the notes and drums laid out bar by bar, mixed, then
  ## folded so the end flows into the start, given its echo and mastered.
  let beat = 60.0'f32 / spec.bpm
  let barLen = beat * 4.0
  let numBars = spec.intensity.len
  let frames = loopFrames(spec)
  let rendered = frames + int(LoopTail * SRf)

  # Collect every melodic note first (cheap), then mix them all in one
  # parallel pass.
  var events: seq[VoiceEvent] = @[]
  for bar in 0..<numBars:
    let barStart = bar.float32 * barLen
    let inten = spec.intensity[bar]
    let chord = spec.progression[bar mod spec.progression.len]
    let tones = chordSemis(chord)

    renderPadBar(spec, events, tones, barStart, barLen, inten)
    renderBassBar(spec, events, chord, barStart, barLen, beat, inten)
    renderArpBar(spec, events, tones, barStart, barLen, beat, inten)
  renderMelody(spec, events, barLen, beat, frames.float32 / SRf)

  # Cancellation is checked here and inside the render workers: returning
  # before finishMusic writes no file at all, so a half-composed track can
  # never be mistaken for a cached one (isMusicCached also size-checks, which
  # covers a torn write).
  if genCancel.load():
    return
  var voices = newSeq[float32](rendered)
  renderVoices(voices, events)
  if genCancel.load():
    return
  var samples = foldTail(voices, frames)

  var drumEvents: seq[DrumEvent] = @[]
  var kicks: seq[float32] = @[]
  scheduleDrums(spec, barLen, beat, drumEvents, kicks)

  applySidechainPump(samples, kicks, spec.pumpDepth, looped = true)

  var drums = newSeq[float32](rendered)
  renderDrums(drums, drumEvents)
  if genCancel.load():
    return
  let folded = foldTail(drums, frames)
  for i in 0..<frames:
    samples[i] += folded[i]

  applySingleEcho(samples, spec.echoDelay, spec.echoMix, looped = true)
  finishMusic(samples, filename, spec.outputGain, fade = false)

proc atTier(spec: TrackSpec, lo, hi: float32): TrackSpec =
  ## The same theme with its intensity curve squeezed into [lo, hi]: the same
  ## chords and the same melody on the same bars, with the arrangement the
  ## intensity rules give that band.
  result = spec
  var cmin = spec.intensity[0]
  var cmax = cmin
  for v in spec.intensity:
    cmin = min(cmin, v)
    cmax = max(cmax, v)
  let span = max(cmax - cmin, 0.001'f32)
  for i, v in spec.intensity:
    result.intensity[i] = lo + (v - cmin) / span * (hi - lo)

proc tierBand(track: MusicTrack, tier: int): (float32, float32) =
  ## The intensity band each tier of a run theme is rendered in. Tier 0 is the
  ## sparsest; the top tier brings the sixteenth hats, the extra kick and the
  ## lead's octave doubling for most of its bars.
  case track
  of mtWave:
    case tier
    of 0: (0.45'f32, 0.7'f32)
    of 1: (0.6'f32, 0.85'f32)
    else: (0.75'f32, 0.97'f32)
  of mtBoss:
    case tier
    of 0: (0.62'f32, 0.82'f32)
    of 1: (0.75'f32, 0.92'f32)
    else: (0.88'f32, 1.0'f32)
  of mtSurvival:
    case tier
    of 0: (0.35'f32, 0.55'f32)
    of 1: (0.55'f32, 0.72'f32)
    of 2: (0.7'f32, 0.87'f32)
    else: (0.85'f32, 1.0'f32)
  of mtRoguelite:
    case tier
    of 0: (0.3'f32, 0.5'f32)
    of 1: (0.55'f32, 0.75'f32)
    else: (0.75'f32, 0.95'f32)
  of mtMenu, mtPowerUp, mtStoryIntro, mtStoryRootAccess, mtStoryBelow, mtStoryUptime:
    (0.0'f32, 1.0'f32)

# TRACK DEFINITIONS

proc menuSpec(): TrackSpec =
  ## Calm lo-fi loop in C major: Cmaj7 - Am7 - Fmaj7 - G7, soft bell lead.
  TrackSpec(
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
    echoDelay: 0.50, echoMix: 0.09, outputGain: 0.92)

proc waveSpec(): TrackSpec =
  ## Driving combat loop in D minor: Dm - Bb - F - C with a supersaw lead.
  TrackSpec(
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
    echoDelay: 0.321, echoMix: 0.06, outputGain: 0.88)

proc powerUpSpec(): TrackSpec =
  ## Uplifting reward loop in C major: C - G - Am - F with bright plucks.
  TrackSpec(
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
    echoDelay: 0.409, echoMix: 0.07, outputGain: 0.90)

proc bossSpec(): TrackSpec =
  ## Relentless boss loop in E phrygian: Em - F - Em - D, double-kick drums.
  TrackSpec(
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
    echoDelay: 0.281, echoMix: 0.05, outputGain: 0.86)

proc survivalSpec(): TrackSpec =
  ## The clock running down, in F minor: Fm - Db - Bbm - C. An eighth-note
  ## hook that keeps ticking over the leading tone, an eighth arp under it.
  TrackSpec(
    bpm: 126.0,                   # 24 bars in 45.7 s
    tonic: 349.23,                # F4
    progression: @[
      BarChord(rootSemi: 0, quality: cqMinor),
      BarChord(rootSemi: 8, quality: cqMajor),
      BarChord(rootSemi: 5, quality: cqMinor),
      BarChord(rootSemi: 7, quality: cqMajor)
    ],
    intensity: @[
      0.55'f32, 0.60, 0.65, 0.70,
      0.75, 0.75, 0.80, 0.80,
      0.85, 0.85, 0.90, 0.90,
      0.60, 0.55, 0.60, 0.65,
      0.90, 0.92, 0.95, 0.95,
      0.95, 0.90, 0.85, 0.75
    ],
    melody: @[
      mn(12, 0.0, 0.5, 0.3), mn(7, 0.5, 0.5), mn(12, 1.0, 0.5), mn(15, 1.5, 0.5),
      mn(14, 2.0, 1.0), mn(12, 3.0, 0.5), mn(10, 3.5, 0.5),
      mn(8, 4.0, 0.5, 0.3), mn(12, 4.5, 0.5), mn(15, 5.0, 0.5), mn(17, 5.5, 0.5),
      mn(15, 6.0, 1.0), mn(12, 7.0, 1.0),
      mn(17, 8.0, 0.75, 0.3), mn(15, 8.75, 0.25), mn(12, 9.0, 0.5), mn(8, 9.5, 0.5),
      mn(10, 10.0, 1.0), mn(12, 11.0, 1.0),
      mn(11, 12.0, 0.5, 0.3), mn(7, 12.5, 0.5), mn(11, 13.0, 0.5), mn(14, 13.5, 0.5),
      mn(11, 14.0, 1.0), mn(7, 15.0, 1.0)
    ],
    phraseBars: 4,
    melodyInstr: ikLead,
    leadVol: 0.10, bassVol: 0.15, padVol: 0.055, arpVol: 0.055,
    drumVol: 0.09, arpStepBeats: 0.5, pumpDepth: 0.4,
    echoDelay: 0.357, echoMix: 0.06, outputGain: 0.91)

proc rogueliteSpec(): TrackSpec =
  ## Down through the folders, in A minor: Am - G - F - E, a falling plucked
  ## line over sixteenth arps.
  TrackSpec(
    bpm: 100.0,                   # 20 bars in 48 s
    tonic: 220.0,                 # A3
    progression: @[
      BarChord(rootSemi: 0, quality: cqMinor),
      BarChord(rootSemi: 10, quality: cqMajor),
      BarChord(rootSemi: 8, quality: cqMajor),
      BarChord(rootSemi: 7, quality: cqMajor)
    ],
    intensity: @[
      0.45'f32, 0.50, 0.55, 0.60,
      0.70, 0.70, 0.75, 0.75,
      0.80, 0.85, 0.85, 0.90,
      0.55, 0.50, 0.55, 0.60,
      0.85, 0.90, 0.90, 0.70
    ],
    melody: @[
      mn(24, 0.0, 1.0, 0.3), mn(19, 1.0, 0.5), mn(15, 1.5, 0.5),
      mn(17, 2.0, 1.0), mn(15, 3.0, 0.5), mn(14, 3.5, 0.5),
      mn(22, 4.0, 1.0, 0.3), mn(17, 5.0, 0.5), mn(14, 5.5, 0.5),
      mn(15, 6.0, 1.0), mn(14, 7.0, 0.5), mn(10, 7.5, 0.5),
      mn(20, 8.0, 1.0, 0.3), mn(15, 9.0, 0.5), mn(12, 9.5, 0.5),
      mn(14, 10.0, 1.0), mn(15, 11.0, 0.5), mn(17, 11.5, 0.5),
      mn(19, 12.0, 1.5, 0.3), mn(23, 13.5, 0.5), mn(19, 14.0, 1.0),
      mn(14, 15.0, 0.5), mn(11, 15.5, 0.5)
    ],
    phraseBars: 4,
    melodyInstr: ikPluck,
    leadVol: 0.12, bassVol: 0.14, padVol: 0.065, arpVol: 0.05,
    drumVol: 0.08, arpStepBeats: 0.25, pumpDepth: 0.3,
    echoDelay: 0.45, echoMix: 0.08, outputGain: 0.96)

proc trackSpec(track: MusicTrack): TrackSpec =
  ## A loop's score. The story tracks are not loops.
  case track
  of mtMenu: menuSpec()
  of mtWave: waveSpec()
  of mtPowerUp: powerUpSpec()
  of mtBoss: bossSpec()
  of mtSurvival: survivalSpec()
  of mtRoguelite: rogueliteSpec()
  of mtStoryIntro, mtStoryRootAccess, mtStoryBelow, mtStoryUptime:
    raiseAssert $track & " is a story score, not a loop"

proc createLoop(track: MusicTrack, tier: int, filename: string) =
  ## One tier of a loop (the loop itself, for a track with one tier).
  let spec = trackSpec(track)
  doAssert loopFrames(spec) == trackFrameCount(track),
    $track & ": its TrackSpec and loopShape disagree on the length"
  if musicTiers(track) > 1:
    let (lo, hi) = tierBand(track, tier)
    composeTrack(spec.atTier(lo, hi), filename)
  else:
    composeTrack(spec, filename)

# ============================================================================
# STORY SCORES
#
# The four story cinematics each get a through-composed score instead of a
# loop. A ScoreBuilder places notes and hits at absolute times, and every time
# comes from the story timing table above -- the numbers the shots are built
# from -- through `at(shot, local)`. A stab written "when the third service
# changes owner" therefore lands on that frame, and retiming a shot moves its
# music with it. Rendering reuses the loop engine's parallel voice/drum mixers.
#
# One leitmotif runs through all four: TOPHAT's six notes (hatMotif). The old
# system plays the very same notes on the PC-speaker voice (ikSquare). Act I
# only hints at it with a fragment; Act III's reveal plays it whole, with
# TOPHAT's bell answering in canon; Act IV ends with TOPHAT's theme on the
# PC speaker, because by then it is the old system.
# ============================================================================

type
  ScoreBuilder = object
    shots: seq[float32]   # the cinematic's shot lengths, cutscene seconds
    length: float32       # real seconds, tail included
    voices: seq[VoiceEvent]
    hits: seq[DrumEvent]
    kicks: seq[float32]

proc newScore(shots: openArray[float32]): ScoreBuilder =
  ScoreBuilder(shots: @shots, length: scoreLength(shots))

proc at(sb: ScoreBuilder, shot: int, local: float32 = 0.0): float32 =
  ## Real time in the score of `local` cutscene seconds into `shot`.
  scoreTime(sb.shots, shot, local)

proc tone(sb: var ScoreBuilder, kind: InstrumentKind, freq, start, dur, vol: float32) =
  if start < 0.0 or start >= sb.length or dur <= 0.0:
    return
  sb.voices.addVoice(freq, start, min(dur, sb.length - start), kind, vol)

proc note(sb: var ScoreBuilder, kind: InstrumentKind, tonic: float32, semi: int,
          start, dur, vol: float32) =
  sb.tone(kind, semiFreq(tonic, semi), start, dur, vol)

proc chord(sb: var ScoreBuilder, kind: InstrumentKind, tonic: float32,
           semis: openArray[int], start, dur, vol: float32) =
  for i, s in semis:
    sb.note(kind, tonic, s, start, dur, vol * (if i == 0: 1.0'f32 else: 0.8'f32))

proc hit(sb: var ScoreBuilder, voice: PercussionVoice, time, vol: float32) =
  if time < 0.0 or time >= sb.length:
    return
  sb.hits.add((time, voice, vol))
  if voice == pvKick:
    sb.kicks.add(time)

proc riserInto(sb: var ScoreBuilder, time, vol: float32) =
  ## A riser that ends exactly on `time`.
  sb.hit(pvRiser, time - RiserLength, vol)

proc pulse(sb: var ScoreBuilder, voice: PercussionVoice, start, stop, every, vol: float32) =
  var t = start
  while t < stop - 0.001:
    sb.hit(voice, t, vol)
    t += every

proc phrase(sb: var ScoreBuilder, kind: InstrumentKind, tonic: float32,
            start, beat: float32, notes: openArray[MelodyNote], vol: float32,
            transpose: int = 0, stopAt: float32 = Inf) =
  ## Play `notes` from `start`; anything at or past `stopAt` is cut off.
  for n in notes:
    let t = start + n.start * beat
    if t >= stopAt:
      break
    sb.note(kind, tonic, n.semi + transpose, t,
            min(n.dur * beat * 0.95, stopAt - t), vol * (1.0 + n.accent * 0.3))

proc ostinato(sb: var ScoreBuilder, kind: InstrumentKind, tonic: float32,
              semis: openArray[int], start, stop, step, vol: float32) =
  ## Cycle `semis` one note per `step` until `stop`; no note rings past it.
  var t = start
  var i = 0
  while t < stop - 0.01:
    sb.note(kind, tonic, semis[i mod semis.len], t, min(step * 0.9, stop - t), vol)
    t += step
    inc i

proc beep(sb: var ScoreBuilder, freq, time: float32, vol: float32 = 0.06) =
  ## The old system's voice: one PC-speaker beep.
  sb.tone(ikSquare, freq, time, 0.17, vol)

proc typing(sb: var ScoreBuilder, start, dur: float32, vol: float32 = 0.12) =
  ## Key clicks under a line that types out over `dur` seconds.
  sb.pulse(pvClick, start, start + dur, 0.075, vol)

proc errorDing(sb: var ScoreBuilder, tonic, time, vol: float32) =
  ## Something the system did not expect: a bell cluster with a tritone in it.
  sb.chord(ikBell, tonic, [12, 13, 18], time, 1.3, vol)

proc renderScore(sb: ScoreBuilder, track: MusicTrack, pump: float32): seq[float32] =
  ## Mix one layer. The length comes from the track so the WAV size always
  ## matches what isMusicCached expects.
  result = newSeq[float32](trackFrameCount(track))
  if genCancel.load():
    return
  renderVoices(result, sb.voices)
  if genCancel.load():
    return
  applySidechainPump(result, sb.kicks, pump)
  renderDrums(result, sb.hits)

proc tapeStop(samples: var seq[float32], startSec, durSec: float32) =
  ## The tape slows to a halt over `durSec`, then silence for the rest of the
  ## buffer. Read position advances at a rate falling from 1 to 0.
  let a = int(startSec * SAMPLE_RATE.float32)
  if a >= samples.len:
    return
  let n = min(int(durSec * SAMPLE_RATE.float32), samples.len - a)
  let src = samples[a ..< samples.len]
  var pos = 0.0'f32
  for k in 0..<n:
    let rate = 1.0'f32 - k.float32 / n.float32
    let i0 = int(pos)
    let frac = pos - i0.float32
    samples[a + k] =
      if i0 + 1 < src.len: (src[i0] * (1.0 - frac) + src[i0 + 1] * frac) * rate.sqrt
      else: 0.0
    pos += rate
  for i in a + n ..< samples.len:
    samples[i] = 0.0

proc mixInto(dst: var seq[float32], src: seq[float32]) =
  for i in 0..<min(dst.len, src.len):
    dst[i] += src[i]

proc createIntroScore(filename: string) =
  ## ACT I: CLEANUP. Calm desktop lo-fi, cut dead by "Permission denied";
  ## a ticking flood; silence and two beeps for WHO ARE YOU / THIS IS MY
  ## MACHINE; TOPHAT answers with its motif and boots shooter.exe; a driving
  ## alarm for the hijack, one stab per service; full kit under the title.
  var sb = newScore(IntroShots)
  # Shot 0: maintenance
  let err = sb.at(0, IntroCleanupError)
  let calm = err / 3.0'f32   # three chords fill the calm before the error
  sb.chord(ikPad, E3, [0, 4, 7, 11], 0.0, calm + 0.1, 0.07)
  sb.chord(ikPad, E3, [9, 12, 16, 19], calm, calm + 0.1, 0.065)
  sb.chord(ikPad, E3, [5, 9, 12, 16], calm * 2.0, err - calm * 2.0, 0.065)
  sb.note(ikBass, E2, 0, 0.0, calm, 0.09)
  sb.note(ikBass, E2, 9, calm, calm, 0.09)
  sb.note(ikBass, E2, 5, calm * 2.0, err - calm * 2.0, 0.09)
  sb.phrase(ikBell, E4, 0.5, 0.48, hatMotif(false), 0.1)
  sb.hit(pvClick, sb.at(0, IntroCleanupClick), 0.55)
  sb.pulse(pvSoftTick, sb.at(0, IntroCleanupClick + 0.2), sb.at(0, IntroCleanupStall), 0.1, 0.22)
  sb.errorDing(E3, err, 0.09)
  sb.hit(pvBoom, err, 0.2)
  sb.note(ikDrone, E2, 0, err, sb.at(1, 1.5) - err, 0.12)
  # Shot 1: root's processes flood in
  let floodEnd = sb.at(2)
  sb.ostinato(ikBass, E2, [0, 0, 1, 0, 0, 0, -2, 0], sb.at(1, 0.3), floodEnd, 0.2, 0.13)
  sb.pulse(pvKick, sb.at(1, 1.0), floodEnd, 0.4, 0.075)
  sb.pulse(pvHat, sb.at(1, 3.0), floodEnd, 0.1, 0.05)
  for i in 0..<IntroProcRows:
    let t = sb.at(1, IntroProcRowStart + i.float32 * IntroProcRowEvery)
    sb.note(ikPluck, E4, i, t, 0.12, 0.05)
    sb.hit(pvSoftTick, t, 0.3)
  sb.riserInto(floodEnd, 0.5)
  # Shot 2: WHO ARE YOU? / THIS IS MY MACHINE.
  sb.note(ikDrone, E2, 0, sb.at(2, 0.2), sb.at(3, 0.6) - sb.at(2, 0.2), 0.08)
  sb.typing(sb.at(2, IntroWhoAt), IntroWhoDur / StoryPlaybackSpeed)
  sb.beep(BeepHigh, sb.at(2, IntroWhoAt + IntroWhoDur))
  sb.typing(sb.at(2, IntroMachineAt), IntroMachineDur / StoryPlaybackSpeed)
  sb.beep(BeepLow, sb.at(2, IntroMachineAt + IntroMachineDur))
  # Root hums the first three notes of TOPHAT's motif. Only Act III says why.
  sb.phrase(ikSquare, E3, sb.at(2, IntroMachineAt + IntroMachineDur + 0.4), 0.5,
            hatMotif(true)[0..2], 0.03)
  # Shot 3: TOPHAT answers and spawns shooter.exe
  let boot = sb.at(3, IntroBootAt)
  let shot4 = sb.at(4)
  sb.chord(ikPad, E3, [0, 3, 7, 14], sb.at(3), boot - sb.at(3) + 0.2, 0.06)
  sb.phrase(ikBell, E4, sb.at(3, 0.3), 0.42, hatMotif(true), 0.1)
  sb.riserInto(boot, 0.45)
  sb.hit(pvBoom, boot, 0.32)
  sb.hit(pvCrash, boot, 0.22)
  sb.chord(ikPad, E3, [0, 4, 7, 12], boot, shot4 - boot + 0.3, 0.07)
  sb.note(ikBass, E2, 0, boot, shot4 - boot, 0.12)
  sb.ostinato(ikPluck, E3, [12, 16, 19, 24, 19, 16], boot, shot4, 0.13, 0.05)
  # Shot 4: the hijack, one alarm stab per service
  let beat = 0.42'f32
  let shot5 = sb.at(5)
  sb.pulse(pvKick, shot4, shot5, beat, 0.09)
  sb.pulse(pvSnare, shot4 + beat, shot5, beat * 2.0, 0.07)
  sb.pulse(pvHat, shot4, shot5, beat * 0.5, 0.05)
  sb.ostinato(ikBass, E2, [0, 0, 1, 0, 0, 0, -2, -2], shot4, shot5, beat * 0.5, 0.14)
  let third = (shot5 - shot4) / 3.0'f32
  sb.chord(ikPad, E3, [0, 3, 7], shot4, third + 0.05, 0.055)
  sb.chord(ikPad, E3, [1, 5, 8], shot4 + third, third + 0.05, 0.055)
  sb.chord(ikPad, E3, [0, 3, 7], shot4 + third * 2.0, third, 0.055)
  for i in 0..<11:
    let t = sb.at(4, IntroFlipStart + i.float32 * IntroFlipEvery)
    sb.chord(ikLead, E3, [12 + i, 13 + i], t, 0.17, 0.05)
    sb.hit(pvSoftTick, t, 0.35)
  sb.riserInto(shot5, 0.45)
  # Shot 5: defend the system; the title slams in
  let title = sb.at(5, IntroTitleAt)
  sb.hit(pvCrash, shot5, 0.35)
  sb.pulse(pvKick, shot5, title, beat, 0.1)
  sb.pulse(pvSnare, shot5 + beat, title, beat * 2.0, 0.08)
  sb.pulse(pvHat, shot5, title, beat * 0.25, 0.045)
  sb.ostinato(ikBass, E2, [0, 0, 7, 0, 5, 0, 3, 2], shot5, title, beat * 0.5, 0.15)
  sb.phrase(ikLead, E4, shot5 + 0.1, beat, hatMotif(true), 0.09)
  sb.riserInto(title, 0.4)
  sb.hit(pvBoom, title, 0.36)
  sb.hit(pvCrash, title, 0.3)
  sb.chord(ikPad, E3, [0, 4, 7, 12, 16], title, sb.length - title, 0.075)
  sb.note(ikBass, E2, 0, title, sb.length - title, 0.12)
  sb.phrase(ikBell, E4, title + 0.35, 0.4, hatMotif(false), 0.07, 12)
  var mix = sb.renderScore(mtStoryIntro, 0.35)
  if genCancel.load():
    return
  applySingleEcho(mix, 0.32, 0.08)
  finishMusic(mix, filename, 0.9)

proc createRootAccessScore(filename: string) =
  ## ACT II: ROOT ACCESS. Root's motif fragment is cut off by an impact and a
  ## breath of silence; the services chime home one by one; TOPHAT's motif in
  ## major as the hat changes heads; a slow IV - V - I; one beep from below.
  var sb = newScore(RootAccessShots)
  let typeAt = sb.at(0, RootTypeAt)
  let cut = sb.at(0, RootCutOffAt)
  sb.note(ikDrone, E2, 0, 0.0, cut + 0.3, 0.09)
  sb.typing(typeAt, cut - typeAt, 0.11)
  # Root starts its motif, slower now, and never gets to finish it.
  sb.phrase(ikSquare, E3, typeAt, 0.42, hatMotif(true), 0.035, stopAt = cut)
  sb.hit(pvBoom, cut, 0.4)
  sb.hit(pvCrash, cut, 0.28)
  let swell = sb.at(0, RootCutOffAt + 1.6)
  sb.chord(ikPad, E3, [0, 4, 7, 11], swell, sb.at(1, 0.8) - swell, 0.06)
  sb.note(ikBell, E4, 12, swell + 0.8, 2.0, 0.05)
  # Shot 1: services come home, then a held, settled chord
  let home = sb.at(1)
  let s2 = sb.at(2)
  let lastHome = sb.at(1, RootHomeStart + 10.0 * RootHomeEvery)
  sb.chord(ikPad, E3, [5, 9, 12, 16], home, lastHome - home + 0.2, 0.06)
  sb.note(ikBass, E2, 5, home, lastHome - home, 0.08)
  sb.chord(ikPad, E3, [0, 4, 7, 11], lastHome, s2 - lastHome + 0.3, 0.065)
  sb.note(ikBass, E2, 0, lastHome, s2 - lastHome, 0.08)
  const homeScale = [0, 2, 4, 7, 9, 11, 12, 14, 16, 19, 21]
  for i in 0..<11:
    let t = sb.at(1, RootHomeStart + i.float32 * RootHomeEvery)
    sb.note(ikBell, E4, homeScale[i], t, 0.7, 0.075)
    sb.hit(pvSoftTick, t, 0.25)
  sb.chord(ikBell, E4, [12, 16, 19], lastHome + 0.6, 2.2, 0.05)
  # Shot 2: the hat changes heads
  let land = sb.at(2, RootHatLandAt)
  let s3 = sb.at(3)
  sb.chord(ikPad, E3, [0, 4, 7, 14], s2, land - s2 + 0.2, 0.06)
  sb.phrase(ikBell, E4, s2 + 0.3, 0.5, hatMotif(false), 0.09)
  sb.hit(pvClick, sb.at(2, RootHatYesAt), 0.5)
  sb.riserInto(land, 0.32)
  sb.hit(pvCrash, land, 0.32)
  sb.hit(pvKick, land, 0.08)
  sb.chord(ikPad, E3, [0, 4, 7, 11, 14], land, s3 - land + 0.3, 0.07)
  sb.note(ikBass, E2, 0, land, s3 - land, 0.1)
  sb.phrase(ikLead, E4, land + 0.2, 0.48, hatMotif(false), 0.08)
  # Shot 3: cadence, IV - V - I, then the tonic held under the title
  const cadStep = 1.6'f32
  sb.chord(ikPad, E3, [5, 9, 12], s3, cadStep + 0.05, 0.065)
  sb.note(ikBass, E2, 5, s3, cadStep, 0.09)
  sb.chord(ikPad, E3, [7, 11, 14], s3 + cadStep, cadStep + 0.05, 0.065)
  sb.note(ikBass, E2, 7, s3 + cadStep, cadStep, 0.09)
  let tonicAt = s3 + cadStep * 2.0
  sb.chord(ikPad, E3, [0, 4, 7, 12], tonicAt, sb.at(4, 0.5) - tonicAt, 0.07)
  sb.note(ikBass, E2, 0, tonicAt, sb.at(4, 0.3) - tonicAt, 0.1)
  sb.note(ikBell, E4, 12, tonicAt, 2.2, 0.06)
  sb.phrase(ikBell, E4, tonicAt + 0.6, 0.55, hatMotif(false), 0.045, 12)
  # Shot 4: one beep from below
  let sting = sb.at(4, RootStingBeepAt)
  sb.tone(ikSquare, E3, sting, 0.26, 0.04)
  sb.note(ikDrone, E2, 0, sb.at(4, 0.4), sb.length - sb.at(4, 0.4), 0.05)
  var mix = sb.renderScore(mtStoryRootAccess, 0.2)
  if genCancel.load():
    return
  applySingleEcho(mix, 0.38, 0.09)
  finishMusic(mix, filename, 0.9)

proc createBelowScore(filename: string) =
  ## ACT III: BELOW THE PARTITION. Falling arpeggios; an empty hum on the old
  ## desktop; the old system's POST beeps and the overwrite buzz; root plays
  ## TOPHAT's whole motif with TOPHAT's bell answering in canon; a power-down
  ## jingle and the old system's last tone; a warm close in major.
  var sb = newScore(BelowShots)
  # Shot 0: the descent
  let s1 = sb.at(1)
  let half0 = s1 * 0.45'f32
  sb.ostinato(ikPluck, A3, [24, 19, 15, 12, 7, 3, 0, 3], 0.0, s1, 0.16, 0.05)
  sb.chord(ikPad, A3, [0, 3, 7], 0.0, half0 + 0.1, 0.06)
  sb.chord(ikPad, A3, [-4, 0, 3], half0, s1 - half0 + 0.3, 0.06)
  sb.note(ikDrone, A2, 0, 0.0, s1 + 0.4, 0.08)
  sb.pulse(pvOpenHat, 0.5, s1, 1.0, 0.12)
  # Shot 1: the old desktop. Almost nothing: a hum and two idle blips.
  let s2 = sb.at(2)
  sb.note(ikDrone, A2, 0, s1, s2 - s1 + 0.4, 0.07)
  sb.chord(ikPad, A3, [12, 19], s1 + 0.3, s2 - s1, 0.035)
  sb.tone(ikSquare, A4, sb.at(1, 3.0), 0.08, 0.025)
  sb.tone(ikSquare, A4, sb.at(1, 5.6), 0.08, 0.02)
  # Shot 2: the old boot log, beep by beep, then the overwrite
  let s3 = sb.at(3)
  sb.note(ikDrone, A2, 0, s2, s3 - s2, 0.07)
  for i in 0..<BelowLogLines:
    let t = sb.at(2, BelowLogStart + i.float32 * BelowLogEvery)
    if i < 6:
      sb.tone(ikSquare, BeepHigh, t, 0.06, 0.035)
    elif i == 6:
      sb.tone(ikSquare, A2, t, 1.1, 0.045)
      sb.tone(ikSquare, semiFreq(A2, 1), t + 0.1, 1.0, 0.035)
    elif i == 7:
      sb.hit(pvBoom, t, 0.22)
    else:
      sb.tone(ikSquare, BeepLow, t, 0.12, 0.035)
      sb.tone(ikSquare, A4, t + 0.13, 0.25, 0.035)
  # Shot 3: I WAS HERE FIRST. Then the twist, in music.
  let first = sb.at(3, BelowFirstAt)
  let firstEnd = sb.at(3, BelowFirstAt + BelowFirstDur)
  let s4 = sb.at(4)
  sb.typing(first, firstEnd - first)
  sb.beep(BeepLow, firstEnd)
  let motifAt = sb.at(3, BelowFirstAt + BelowFirstDur + 0.6)
  const motifBeat = 0.5'f32
  sb.chord(ikPad, A3, [0, 3, 7], s3, s4 - s3 + 0.3, 0.05)
  sb.note(ikBass, A2, 0, motifAt, s4 - motifAt, 0.07)
  sb.phrase(ikSquare, A3, motifAt, motifBeat, hatMotif(true), 0.04)
  sb.phrase(ikBell, A4, motifAt + motifBeat * 2.0, motifBeat, hatMotif(true), 0.075)
  # Shot 4: the shutdown it never got
  let yes = sb.at(4, BelowYesAt)
  let safe = sb.at(4, BelowSafeAt)
  let s5 = sb.at(5)
  sb.hit(pvClick, yes, 0.5)
  for i, semi in [12, 7, 3, 0]:
    let t = yes + 0.3 + i.float32 * 0.45
    sb.note(ikSquare, A3, semi, t, 0.36, 0.035)
    sb.note(ikBell, A4, semi, t, 0.8, 0.06)
  sb.note(ikDrone, A2, 0, s4, safe - s4, 0.06)
  # The old system's last sound, under the line every old machine ended on.
  sb.tone(ikSquare, A3, safe + 0.2, 1.4, 0.022)
  sb.chord(ikPad, A3, [0, 4, 7], safe + 0.6, s5 - safe - 0.4, 0.04)
  # Shot 5: cleanup complete, a warm close
  sb.chord(ikPad, A3, [0, 4, 7, 11], s5, 2.6, 0.065)
  sb.chord(ikPad, A3, [5, 9, 12], s5 + 2.5, 2.0, 0.06)
  sb.chord(ikPad, A3, [0, 4, 7, 12], s5 + 4.4, sb.length - s5 - 4.4, 0.07)
  sb.note(ikBass, A2, 0, s5, 2.5, 0.08)
  sb.note(ikBass, A2, 5, s5 + 2.5, 1.9, 0.08)
  sb.note(ikBass, A2, 0, s5 + 4.4, sb.length - s5 - 4.4, 0.08)
  sb.phrase(ikBell, A4, s5 + 0.4, 0.5, hatMotif(false), 0.09)
  sb.ostinato(ikPluck, A3, [12, 16, 19, 24], s5 + 0.4, sb.length - 0.8, 0.24, 0.035)
  var mix = sb.renderScore(mtStoryBelow, 0.0)
  if genCancel.load():
    return
  applySingleEcho(mix, 0.4, 0.1)
  finishMusic(mix, filename, 1.1)   # a quiet, sparse score: a little more gain

proc createUptimeScore(filename: string) =
  ## ACT IV: UPTIME. A tired heartbeat and TOPHAT's motif slowed down; the
  ## last surge; the crash winds the tape to a stop; a cheerful, sterile
  ## installer tune for the new OS; its boot chime; then, from below, the
  ## intro's two beeps and TOPHAT's theme on the PC speaker.
  var before = newScore(UptimeShots)
  let s1 = before.at(1)
  let crash = before.at(2, UptimeCrashAt)
  # Shot 0: years of uptime
  let half0 = s1 * 0.5'f32
  before.chord(ikPad, D3, [0, 3, 7], 0.0, half0 + 0.1, 0.06)
  before.chord(ikPad, D3, [-2, 2, 5], half0, s1 - half0 + 0.2, 0.06)
  before.note(ikBass, D2, 0, 0.0, half0, 0.08)
  before.note(ikBass, D2, -2, half0, s1 - half0, 0.08)
  var hb = 0.2'f32
  while hb < s1:
    before.hit(pvKick, hb, 0.06)
    before.hit(pvKick, hb + 0.2, 0.045)
    hb += 1.0
  before.pulse(pvSoftTick, 0.0, s1, 0.5, 0.18)
  before.phrase(ikBell, D4, 0.6, 0.65, hatMotif(true), 0.07)   # tired: slower than ever
  # Shot 1: the last surge
  let beat = 0.38'f32
  before.pulse(pvKick, s1, crash, beat, 0.09)
  before.pulse(pvSnare, s1 + beat, crash, beat * 2.0, 0.07)
  before.pulse(pvHat, s1, crash, beat * 0.25, 0.045)
  before.ostinato(ikBass, D2, [0, 0, 3, 0, 5, 0, 3, 1], s1, crash, beat * 0.5, 0.14)
  before.chord(ikPad, D3, [0, 3, 7], s1, crash - s1, 0.06)
  before.phrase(ikLead, D4, s1 + 0.2, beat, hatMotif(true), 0.085)
  before.riserInto(crash, 0.5)
  var mix = before.renderScore(mtStoryUptime, 0.35)
  if genCancel.load():
    return
  # The crash winds the whole mix down like a tape losing power.
  tapeStop(mix, crash, 1.4)

  var after = newScore(UptimeShots)
  # Shot 2: the crash screen
  after.errorDing(D3, crash + 1.3, 0.08)
  after.note(ikDrone, D2, 0, crash + 1.1, after.at(3) - crash - 1.1, 0.07)
  # Shot 3: the new OS installs itself, pleasantly
  let s3 = after.at(3)
  let s4 = after.at(4)
  after.chord(ikPad, G3, [0, 4, 7, 12], s3, s4 - s3, 0.055)
  after.ostinato(ikPluck, G4, [0, 4, 7, 12, 7, 4], s3 + 0.1, s4, 0.18, 0.05)
  after.pulse(pvSoftTick, after.at(3, UptimeFormatAt), s4, 0.36, 0.15)
  # Shot 4: the new OS boots clean; then something answers from below
  after.chord(ikBell, G4, [0, 4, 7, 12, 16], after.at(4, UptimeNewBootAt), 2.4, 0.07)
  let who = after.at(4, UptimeWhoAt)
  let mine = after.at(4, UptimeMachineAt)
  after.typing(who, UptimeWhoDur / StoryPlaybackSpeed)
  after.beep(BeepHigh, after.at(4, UptimeWhoAt + UptimeWhoDur))
  after.typing(mine, UptimeMachineDur / StoryPlaybackSpeed)
  let mineEnd = after.at(4, UptimeMachineAt + UptimeMachineDur)
  after.beep(BeepLow, mineEnd)
  after.note(ikDrone, E2, 0, who - 0.4, after.length - who + 0.4, 0.06)
  # TOPHAT's theme, in the intro's key, on the old system's voice.
  after.phrase(ikSquare, E3, mineEnd + 0.5, 0.55, hatMotif(false), 0.035)
  mix.mixInto(after.renderScore(mtStoryUptime, 0.0))
  if genCancel.load():
    return
  applySingleEcho(mix, 0.4, 0.1)
  finishMusic(mix, filename, 0.9)

# SOUND EFFECTS

proc createLaserShoot(filename: string) =
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

proc createImpactHit(filename: string) =
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

proc createEnemyDeath(filename: string) =
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

proc createPlayerHit(filename: string) =
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

proc createCoinPickup(filename: string) =
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

proc createPowerUp(filename: string) =
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

proc createBossSpawn(filename: string) =
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

proc createExplosion(filename: string) =
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

proc createWallPlace(filename: string) =
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

proc createTeleport(filename: string) =
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

proc createMenuNav(filename: string) =
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

proc createMenuSelect(filename: string) =
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

proc createWaveComplete(filename: string) =
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

proc createShield(filename: string) =
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

proc createGameOverSound(filename: string) =
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

proc createBuySound(filename: string) =
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

proc createRestoreAccess(filename: string) =
  ## Restore point coming up on screen: a drive being addressed. Two rising seek
  ## blips over a platter humming up to speed, with a head tick on the front.
  let sampleRate: uint32 = 44100
  let duration = 0.28
  let frameCount = int(sampleRate.float32 * duration)
  var samples = newSeq[int16](frameCount)
  var humPhase = 0.0

  for i in 0..<frameCount:
    let t = i.float32 / sampleRate.float32
    let progress = t / duration

    # Platter spinning up: the hum climbs from a stall to running speed.
    let humFreq = 70.0 + progress * 95.0
    humPhase += 2.0 * PI * humFreq / sampleRate.float32
    let hum = (sin(humPhase) * 0.5 + sin(humPhase * 2.0) * 0.18) * progress * 0.5

    # Two seek blips, the second a step higher. Half sine + half square gives
    # them the digital edge the rest of the OS chrome has.
    var blip = 0.0
    for b in 0..1:
      let age = t - (0.06 + b.float32 * 0.105)
      if age >= 0.0 and age < 0.055:
        let bp = age / 0.055
        let raw = sin(2.0 * PI * (1500.0 + b.float32 * 520.0) * (1.0 + bp * 0.35) * age)
        let square = if raw >= 0.0: 1.0 else: -1.0
        blip += (raw * 0.6 + square * 0.4) * exp(-bp * 7.0) * 0.34

    # Head tick on the very front.
    let tick = if t < 0.012: rand(-1.0..1.0) * (1.0 - t / 0.012) * 0.22 else: 0.0

    let envelope = min(1.0, progress * 18.0) * (1.0 - progress * progress * 0.55)
    let value = (hum + blip + tick) * envelope
    # Louder than its short blips suggest it needs: this is the quietest cue of
    # the three and has to stay audible under the wave music behind the overlay.
    samples[i] = int16(clamp(value * 32767.0 * 0.68, -32767.0, 32767.0))

  writeWavFile(filename, samples, sampleRate)

proc createRestoreSpinDown(filename: string) =
  ## The platter losing power: the motor whine coasts down, the rotation flutter
  ## slows WITH it (so the ear hears the disc turning slower rather than just
  ## getting quieter), bearing rumble underneath, and brittle ticks as the
  ## surface starts to give.
  let sampleRate: uint32 = 44100
  let duration = 0.95
  let frameCount = int(sampleRate.float32 * duration)
  var samples = newSeq[int16](frameCount)
  var motorPhase = 0.0
  var wobblePhase = 0.0
  var subPhase = 0.0
  var rumble = 0.0

  for i in 0..<frameCount:
    let t = i.float32 / sampleRate.float32
    let progress = t / duration

    # Motor whine: exponential coast-down that never quite reaches zero.
    let motorFreq = 60.0 + 390.0 * exp(-progress * 3.1)
    motorPhase += 2.0 * PI * motorFreq / sampleRate.float32
    let motor = sin(motorPhase) * 0.55 + sin(motorPhase * 2.0) * 0.2 +
                sin(motorPhase * 3.0) * 0.08

    # Rotation flutter: an amplitude wobble whose RATE decays on the same curve
    # as the motor, which is what sells "spinning down" over "fading out".
    let wobbleRate = 3.0 + 26.0 * exp(-progress * 3.1)
    wobblePhase += 2.0 * PI * wobbleRate / sampleRate.float32
    let wobble = 1.0 + sin(wobblePhase) * 0.32

    # Bearing rumble: one-pole low-passed noise.
    rumble = rumble * 0.986 + rand(-1.0..1.0) * 0.014

    subPhase += 2.0 * PI * (46.0 + 20.0 * exp(-progress * 2.4)) / sampleRate.float32
    let sub = sin(subPhase) * 0.3

    # Brittle ticks across the back half: the fracture starting to travel.
    var tick = 0.0
    for k in 0..3:
      let age = t - (0.42 + k.float32 * 0.13)
      if age >= 0.0 and age < 0.03:
        let kp = age / 0.03
        tick += sin(2.0 * PI * (2600.0 + k.float32 * 700.0) * age) *
                exp(-kp * 16.0) * 0.3

    let envelope = min(1.0, progress * 14.0) * (1.0 - progress * 0.35)
    let value = (motor * wobble * 0.5 + rumble * 2.4 + sub + tick) * envelope
    samples[i] = int16(clamp(value * 32767.0 * 0.44, -32767.0, 32767.0))

  writeWavFile(filename, samples, sampleRate)

proc createRestoreShatter(filename: string) =
  ## The platter giving way: a hard broadband snap, a glassy inharmonic ring,
  ## the sub weight of it letting go, and the save scattering as bit-crushed
  ## data blips falling away into silence.
  let sampleRate: uint32 = 44100
  let duration = 0.8
  let frameCount = int(sampleRate.float32 * duration)
  var samples = newSeq[int16](frameCount)
  var thumpPhase = 0.0

  # Deliberately inharmonic, so it reads as breaking rather than as a chord.
  const partials = [2170.0, 3110.0, 4690.0, 6230.0]

  for i in 0..<frameCount:
    let t = i.float32 / sampleRate.float32
    let progress = t / duration

    # Transient: broadband snap, gone in 25 ms.
    let snap = if t < 0.025:
      rand(-1.0..1.0) * exp(-(t / 0.025) * 5.0) * 0.85
    else:
      0.0

    # Glassy ring, each partial decaying at its own rate.
    var glass = 0.0
    for n in 0..partials.high:
      glass += sin(2.0 * PI * partials[n] * t) *
               exp(-t * (14.0 + n.float32 * 7.0)) * (0.26 - n.float32 * 0.05)

    thumpPhase += 2.0 * PI * (120.0 * exp(-progress * 5.0) + 38.0) / sampleRate.float32
    let thump = sin(thumpPhase) * exp(-progress * 6.0) * 0.5

    # Data scatter: blips falling in pitch across the tail, quantised to a
    # handful of levels so they read as digital debris and not as sparkle.
    var scatter = 0.0
    for k in 0..7:
      let age = t - (0.06 + k.float32 * 0.075)
      if age >= 0.0 and age < 0.05:
        let kp = age / 0.05
        let raw = sin(2.0 * PI * (2400.0 - k.float32 * 210.0) * age)
        let crushed = floor(raw * 3.0) / 3.0
        scatter += crushed * exp(-kp * 9.0) * (0.16 - k.float32 * 0.012)

    let envelope = 1.0 - progress * progress * 0.6
    let value = (snap + glass + thump + scatter) * envelope
    samples[i] = int16(clamp(value * 32767.0 * 0.46, -32767.0, 32767.0))

  writeWavFile(filename, samples, sampleRate)

# SOUND LOADING WITH CACHE
proc generateSoundFile(soundType: SoundType) =
  ## Synthesise the WAV for `soundType` if it isn't cached yet. Pure CPU work
  ## plus a file write: no raylib, so the background generator thread may call
  ## this. Loading the result into the audio device stays on the main thread.
  let cacheFile = getSoundCacheFile(soundType)
  if fileExists(cacheFile):
    return

  case soundType
  of stShoot: createLaserShoot(cacheFile)
  of stEnemyHit: createImpactHit(cacheFile)
  of stEnemyDeath: createEnemyDeath(cacheFile)
  of stPlayerHit: createPlayerHit(cacheFile)
  of stCoinPickup: createCoinPickup(cacheFile)
  of stPowerUp: createPowerUp(cacheFile)
  of stBossSpawn: createBossSpawn(cacheFile)
  of stExplosion: createExplosion(cacheFile)
  of stWallPlace: createWallPlace(cacheFile)
  of stTeleport: createTeleport(cacheFile)
  of stMenuNav: createMenuNav(cacheFile)
  of stMenuSelect: createMenuSelect(cacheFile)
  of stWaveComplete: createWaveComplete(cacheFile)
  of stShield: createShield(cacheFile)
  of stGameOver: createGameOverSound(cacheFile)
  of stBuy: createBuySound(cacheFile)
  of stRestoreAccess: createRestoreAccess(cacheFile)
  of stRestoreSpinDown: createRestoreSpinDown(cacheFile)
  of stRestoreShatter: createRestoreShatter(cacheFile)

proc loadOrGenerateSound(soundType: SoundType): Sound =
  ## Main thread only (touches the audio device).
  generateSoundFile(soundType)
  result = loadSound(getSoundCacheFile(soundType))

# MUSIC LOADING AND SYSTEM MANAGEMENT

proc generateMusicFile(track: MusicTrack) =
  ## Synthesise whichever of a track's WAVs (every tier of a run theme) are
  ## not cached. Thread-safe (no raylib); this is the expensive one (a tier
  ## is ~2.1M samples of pads, bass, arp, lead and drums), which is why it
  ## runs off the main thread.
  for tier in 0..<musicTiers(track):
    if genCancel.load():
      return
    if isTierCached(track, tier):
      continue
    let cacheFile = getMusicCacheFile(track, tier)
    case track
    of mtMenu, mtWave, mtPowerUp, mtBoss, mtSurvival, mtRoguelite:
      createLoop(track, tier, cacheFile)
    of mtStoryIntro: createIntroScore(cacheFile)
    of mtStoryRootAccess: createRootAccessScore(cacheFile)
    of mtStoryBelow: createBelowScore(cacheFile)
    of mtStoryUptime: createUptimeScore(cacheFile)

proc cleanStaleCacheFiles() =
  ## Remove every WAV in the cache that the current versions don't use: older
  ## versions, renamed tracks, tiers that no longer exist. (Matching the
  ## version suffix alone kept old music forever whenever an old music version
  ## matched the sounds' current one.)
  var keep: seq[string]
  for st in SoundType:
    keep.add extractFilename(getSoundCacheFile(st))
  for track in MusicTrack:
    for tier in 0..<musicTiers(track):
      keep.add extractFilename(getMusicCacheFile(track, tier))
  for path in walkFiles(getCacheDir() / "*.wav"):
    if extractFilename(path) notin keep:
      try:
        removeFile(path)
      except OSError:
        discard

# ASYNCHRONOUS PRE-GENERATION
#
# Synthesising the music tracks is by far the slowest thing the game ever
# does. Doing it inline froze the window: no endDrawing() ran, so nothing
# animated and Windows marked the process "Not Responding". A worker thread
# writes the WAVs instead, while the main thread keeps the loading screen at
# full frame rate. Everything is finished before the game starts -- the worker
# is joined at the end of the loading screen, so gameplay never races it.
#
# The synthesis itself is parallel across cores (see renderVoices), which is
# what makes waiting for the whole set reasonable: a cold cache is a beat, not
# the better part of a minute.
#
# Thread-safety contract: the worker only runs pure synthesis + FileStream
# writes. Every raylib/audio-device call (loadSound, loadMusicStream) stays on
# the main thread and happens after joinThread. Progress is published through
# atomics only -- no strings cross the thread boundary, so the localized labels
# are built main-side from the published enum ordinals.
#
# genCompleted is incremented with store(load() + 1) rather than atomicInc():
# this worker is the only writer (the main thread only load()s it), so the
# read-modify-write does not need to be atomic as a unit. It also sidesteps a
# broken std/atomics fetchAdd() on the MSVC branch (Nim 2.2.12), which is what
# nimble WinRelease builds with -- `nimble debug` uses gcc and never hits it.

var
  genThread: Thread[void]
  genThreadActive = false    # main thread only
  genPending = 0             # assets the worker was asked to synthesise
  genCompleted: Atomic[int]
  genCurrentIsMusic: Atomic[bool]
  genCurrentOrd: Atomic[int]
  genDone: Atomic[bool]
  genMusicReady: Atomic[int] # bitmask, bit i set = MusicTrack(i)'s WAV exists

proc isMusicReady(track: MusicTrack): bool =
  ## True once the track's WAV is on disk and safe for loadMusicStream.
  (genMusicReady.load() and (1 shl track.ord)) != 0

proc assetGenWorker() {.thread.} =
  try:
    for soundType in SoundType:
      if genCancel.load():
        break
      if not isSoundCached(soundType):
        genCurrentIsMusic.store(false)
        genCurrentOrd.store(soundType.ord)
        generateSoundFile(soundType)
        genCompleted.store(genCompleted.load() + 1)

    for track in MusicTrack:
      if genCancel.load():
        break
      if not isMusicCached(track):
        genCurrentIsMusic.store(true)
        genCurrentOrd.store(track.ord)
        generateMusicFile(track)
        if isMusicCached(track):
          genMusicReady.store(genMusicReady.load() or (1 shl track.ord))
        genCompleted.store(genCompleted.load() + 1)
  except CatchableError:
    discard
  genDone.store(true)

proc startAssetGeneration*(): int =
  ## Begin synthesising any missing WAVs on a worker thread and return how many
  ## assets need generating (0 = everything was cached, no thread spawned).
  cleanStaleCacheFiles()
  let cached = countCachedAssets()
  let totalAssets = SoundType.high.ord + 1 + MusicTrack.high.ord + 1
  genPending = totalAssets - cached.total
  genCompleted.store(0)
  genDone.store(genPending == 0)
  genCurrentOrd.store(0)
  genCurrentIsMusic.store(false)
  genCancel.store(false)

  # Seed the readiness mask from whatever survived in the cache; the worker
  # adds each track as it finishes writing it.
  var ready = 0
  for track in MusicTrack:
    if isMusicCached(track):
      ready = ready or (1 shl track.ord)
  genMusicReady.store(ready)

  if genPending == 0:
    echo "All ", totalAssets, " audio assets already cached"
    return 0

  echo "Generating ", genPending, " audio assets on ", synthThreadCount(),
       " threads (", cached.sounds, "/", SoundType.high.ord + 1, " sounds, ",
       cached.music, "/", MusicTrack.high.ord + 1, " tracks cached)"
  createThread(genThread, assetGenWorker)
  genThreadActive = true
  result = genPending

proc assetGenBusy*(): bool = genThreadActive and not genDone.load()
proc assetGenCompleted*(): int = genCompleted.load()
proc assetGenOnMusic*(): bool = genCurrentIsMusic.load()

proc assetGenProgress*(): float32 =
  ## 0..1 across the assets that actually needed generating.
  if genPending <= 0: 1.0'f32
  else: clamp(genCompleted.load().float32 / genPending.float32, 0.0, 1.0)

proc assetGenLabel*(): string =
  ## Localized description of the asset currently being synthesised. Main
  ## thread only: it reads the shared string tables via t().
  let ord = genCurrentOrd.load()
  if genCurrentIsMusic.load():
    let track = MusicTrack(clamp(ord, 0, MusicTrack.high.ord))
    t(tkLoadingGeneratingMusic) & ": " & extractFilename(getMusicCacheFile(track))
  else:
    let soundType = SoundType(clamp(ord, 0, SoundType.high.ord))
    t(tkLoadingGeneratingSound) & ": " & extractFilename(getSoundCacheFile(soundType))

proc finishAssetGeneration*() =
  ## Block until BOTH phases are done. Never call this during startup -- that
  ## would reintroduce the music stall this whole system exists to avoid. It is
  ## for shutdown only, so the worker can't outlive the process' file handles.
  if genThreadActive:
    joinThread(genThread)
    genThreadActive = false
    echo "Audio asset generation complete: ", getCacheDir()

proc abortAssetGeneration() =
  ## Shutdown path: tell the worker to stop at the next bar instead of
  ## finishing the track it is on, then join. Without this, closing the window
  ## during first-run generation would hang on the rest of the soundtrack.
  genCancel.store(true)
  finishAssetGeneration()

# INCREMENTAL LOAD INTO THE AUDIO DEVICE
var soundLoadCursor = 0

proc soundLoadProgress*(): float32 =
  clamp(soundLoadCursor.float32 / (SoundType.high.ord + 1).float32, 0.0, 1.0)

proc soundLoadLabel*(): string =
  let idx = clamp(soundLoadCursor, 0, SoundType.high.ord)
  t(tkLoadingLoadingSounds) & ": " & extractFilename(getSoundCacheFile(SoundType(idx)))

proc loadSoundsStep*(sys: SoundSystem, budget: int = 2): bool =
  ## Load up to `budget` sounds (plus their voice aliases) into the audio
  ## device and report whether every sound is loaded. Splitting this across
  ## frames keeps the loading screen animating instead of stalling on the
  ## last stretch of startup.
  if sys == nil or not sys.initialized:
    return true
  if sys.soundsGenerated:
    return true

  var loaded = 0
  while soundLoadCursor <= SoundType.high.ord and loaded < budget:
    let st = SoundType(soundLoadCursor)
    try:
      sys.cachedSounds[st] = loadOrGenerateSound(st)
      for voice in 0..<MAX_SOUND_VOICES:
        sys.soundVoices[st][voice] = loadSoundAlias(sys.cachedSounds[st])
    except CatchableError as e:
      echo "ERROR loading sound ", st, ": ", e.msg
    inc soundLoadCursor
    inc loaded

  if soundLoadCursor > SoundType.high.ord:
    sys.soundsGenerated = true
    echo "All sounds loaded successfully!"
    return true
  false

# SYSTEM INITIALIZATION AND MANAGEMENT
proc initSoundSystem*(): SoundSystem =
  ## Opens the audio device only. Asset generation and sound loading are driven
  ## by the caller (see startAssetGeneration / loadSoundsStep) so the loading
  ## screen stays interactive.
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
    echo "Sound system initialized!"
  except Exception as e:
    echo "ERROR initializing sound system: ", e.msg
    return SoundSystem(enabled: false, masterVolume: 0.5, musicVolume: 0.5, initialized: false)


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
  # Composed one-shots keep their exact pitch. The restore-point cues are a
  # scripted three-beat sequence, so any wobble between them would break the
  # illusion that they are one continuous event.
  of stPowerUp, stBossSpawn, stMenuSelect, stWaveComplete, stGameOver, stBuy,
     stRestoreAccess, stRestoreSpinDown, stRestoreShatter: 0.0

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

# ---------------------------------------------------------------------------
# MODS.EXE: sound and music replacement. A mod's file takes over one of the
# game's sounds (its own voice pool, played exactly like the built-in one) or
# one music track (swapped into the track's slot; the built-in stream is kept
# aside and swapped back). restoreVanillaSounds undoes everything; it must run
# before the audio device closes.
# ---------------------------------------------------------------------------
var
  modSoundSource: array[SoundType, Sound]
  modSoundVoices: array[SoundType, seq[SoundAlias]]
  modMusicBackup: array[MusicTrack, Music]
  modMusicActive: array[MusicTrack, bool]
  modMusicHadVanilla: array[MusicTrack, bool]
  gameMusicHeld: bool
    ## A mod's own music (assets.music) or a video's sound has the music
    ## channel: the game's track waits, paused, and carries on from there.

# MUSIC PLAYBACK
#
# Every track keeps its own stream. Switching tracks fades the old one out
# over 0.15 s while the new one starts at once, from its first bar: a track
# always starts from its top when it comes in, so every wave, every boss fight
# and every shop opens on its music's opening.
#
# The built-in loops play through a TierStream instead of a raylib Music: a
# raylib AudioStream that the main thread fills itself, a block at a time,
# from the loop's WAVs on disk. A run theme has one WAV per tier, all on one
# timeline, so changing its arrangement is only a matter of which file the
# next samples come from. The change waits for the next bar line and crosses
# over there in 50 ms, so the band builds up or drops back on the beat. The
# same feeder muffles the music while the player's health is critical. The
# story scores, and any file a mod puts in a track's place, stay raylib Music
# streams: a score is held to its cinematic with raylib's seek and pitch.
# Two raylib rules this relies on: playing a stream marks both of its blocks
# as wanted, so they are filled right after the play; and a Music stopped
# while paused still counts as paused, so it must be restarted with
# playMusicStream, never resumed, or it replays its stale buffers first.

const
  TierChunk = 12288
    ## Frames per block handed to raylib (0.28 s). The stream holds two, so a
    ## main-thread stall shorter than one block never runs it dry.
  TierCrossfade = 2205
    ## 50 ms: how long a change of tier crosses over on its bar line.
  TierFadeIn = 220
    ## 5 ms of fade-in whenever a loop starts, so it never starts on a click.

var musicMuffled: bool
  ## Set by setMusicMuffled: the player's health is critical.

proc tiered(track: MusicTrack): bool =
  ## Whether `track` plays through its TierStream: a built-in loop, not a
  ## story score and not a mod's file in its place.
  not isScoreTrack(track) and not modMusicActive[track]

proc openTierStream(ts: var TierStream, track: MusicTrack): bool =
  ## Open a loop's tier WAVs and its raylib stream. Main thread only.
  if ts.ready:
    return true
  var files: seq[File]
  for tier in 0..<musicTiers(track):
    var f: File
    if not open(f, getMusicCacheFile(track, tier), fmRead):
      for g in files:
        g.close()
      return false
    files.add f
  setAudioStreamBufferSizeDefault(TierChunk)
  try:
    ts.stream = loadAudioStream(SAMPLE_RATE, 32, 1)
  except CatchableError:
    setAudioStreamBufferSizeDefault(0)
    for g in files:
      g.close()
    return false
  setAudioStreamBufferSizeDefault(0)
  ts.files = files
  ts.frames = trackFrameCount(track)
  ts.barFrames = ts.frames div loopShape(track).bars
  ts.raw = newSeq[int16](TierChunk)
  ts.other = newSeq[int16](TierChunk)
  ts.output = newSeq[float32](TierChunk)
  ts.ready = true
  true

proc readTier(ts: var TierStream, tier, start: int, dst: var seq[int16]) =
  ## TierChunk frames of `tier` from loop frame `start`, round the loop's end.
  var done = 0
  var p = start
  while done < TierChunk:
    let run = min(TierChunk - done, ts.frames - p)
    var got = 0
    try:
      ts.files[tier].setFilePos(44'i64 + p.int64 * 2)
      got = ts.files[tier].readBuffer(addr dst[done], run * 2) div 2
    except IOError:
      got = 0
    for i in done + got ..< done + run:
      dst[i] = 0
    done += run
    p = (p + run) mod ts.frames

proc fillTierBlock(ts: var TierStream) =
  ## The next TierChunk frames into ts.output: the tier playing, the change
  ## to another tier on a bar line when one was asked for, the fade-in after
  ## a start and the low-health muffle.
  if ts.target == ts.tier:
    ts.switchAt = -1
  elif ts.switchAt < 0 and ts.xfadeLeft == 0:
    # The first bar line not yet handed to raylib
    let line = (ts.pos + ts.barFrames - 1) div ts.barFrames * ts.barFrames
    ts.switchAt = line mod ts.frames
  var switchFrom = TierChunk   # where in this block the change starts
  if ts.switchAt >= 0:
    let ahead = (ts.switchAt - ts.pos + ts.frames) mod ts.frames
    if ahead < TierChunk:
      switchFrom = ahead
  let other = if switchFrom < TierChunk: ts.target
              elif ts.xfadeLeft > 0: ts.fromTier
              else: -1
  ts.readTier(ts.tier, ts.pos, ts.raw)
  if other >= 0:
    ts.readTier(other, ts.pos, ts.other)
  let muffleTarget = if musicMuffled: 1.0'f32 else: 0.0'f32
  for i in 0..<TierChunk:
    var newer, older: float32
    if i >= switchFrom:
      if i == switchFrom:
        ts.fromTier = ts.tier
        ts.tier = ts.target
        ts.xfadeLeft = TierCrossfade
        ts.switchAt = -1
      newer = ts.other[i].float32
      older = ts.raw[i].float32
    else:
      newer = ts.raw[i].float32
      older = if other >= 0: ts.other[i].float32 else: 0.0'f32
    # Linear, not equal-power: the tiers share their kick, chords and melody,
    # and an equal-power cross of two copies of a hit would swell it by 3 dB.
    var x = newer
    if ts.xfadeLeft > 0:
      let p = 1.0'f32 - ts.xfadeLeft.float32 / TierCrossfade.float32
      x = newer * p + older * (1.0'f32 - p)
      dec ts.xfadeLeft
    x *= 1.0'f32 / 32768.0'f32
    if ts.fadeLeft > 0:
      x *= 1.0'f32 - ts.fadeLeft.float32 / TierFadeIn.float32
      dec ts.fadeLeft
    # The muffle: two one-pole lowpasses near 700 Hz, blended in over 0.3 s
    # and out over 0.6 s. At a blend of 0 the music passes untouched.
    ts.lp1 += (x - ts.lp1) * 0.095'f32
    ts.lp2 += (ts.lp1 - ts.lp2) * 0.095'f32
    if ts.muffle < muffleTarget:
      ts.muffle = min(muffleTarget, ts.muffle + 1.0'f32 / (0.3'f32 * SRf))
    elif ts.muffle > muffleTarget:
      ts.muffle = max(muffleTarget, ts.muffle - 1.0'f32 / (0.6'f32 * SRf))
    ts.output[i] = x + (ts.lp2 - x) * ts.muffle
  ts.pos = (ts.pos + TierChunk) mod ts.frames

proc feed(ts: var TierStream) =
  ## Fill whatever blocks raylib has finished playing.
  while isAudioStreamProcessed(ts.stream):
    ts.fillTierBlock()
    updateAudioStream(ts.stream, ts.output)

proc startTierStream(ts: var TierStream, tier: int) =
  ## Play the loop from its top at `tier`.
  ts.pos = 0
  ts.tier = clamp(tier, 0, ts.files.high)
  ts.target = ts.tier
  ts.switchAt = -1
  ts.xfadeLeft = 0
  ts.fadeLeft = TierFadeIn
  ts.lp1 = 0.0
  ts.lp2 = 0.0
  ts.muffle = if musicMuffled: 1.0 else: 0.0
  playAudioStream(ts.stream)
  ts.feed()

proc release(ts: var TierStream) =
  ## Close the files and unload the stream (before the audio device closes).
  for f in ts.files:
    f.close()
  reset(ts)

# Each track plays through one of two kinds of stream; these few procs are
# the only places that care which.

proc streamVolume(sys: SoundSystem, track: MusicTrack, volume: float32) =
  if tiered(track):
    if sys.tierStreams[track].ready:
      setAudioStreamVolume(sys.tierStreams[track].stream, volume)
  else:
    setMusicVolume(sys.cachedMusic[track], volume)

proc startStream(sys: SoundSystem, track: MusicTrack, tier: int) =
  ## Play `track` from its top; while a mod holds the music it waits, paused.
  if tiered(track):
    sys.tierStreams[track].startTierStream(tier)
    if gameMusicHeld:
      pauseAudioStream(sys.tierStreams[track].stream)
  else:
    stopMusicStream(sys.cachedMusic[track])   # rewinds it
    playMusicStream(sys.cachedMusic[track])
    if gameMusicHeld:
      pauseMusicStream(sys.cachedMusic[track])

proc stopStream(sys: SoundSystem, track: MusicTrack) =
  if tiered(track):
    if sys.tierStreams[track].ready:
      stopAudioStream(sys.tierStreams[track].stream)
  else:
    stopMusicStream(sys.cachedMusic[track])

proc holdStream(sys: SoundSystem, track: MusicTrack, held: bool) =
  if tiered(track):
    if held: pauseAudioStream(sys.tierStreams[track].stream)
    else: resumeAudioStream(sys.tierStreams[track].stream)
  else:
    if held: pauseMusicStream(sys.cachedMusic[track])
    else: resumeMusicStream(sys.cachedMusic[track])

proc streamPlaying(sys: SoundSystem, track: MusicTrack): bool =
  if tiered(track): isAudioStreamPlaying(sys.tierStreams[track].stream)
  else: isMusicStreamPlaying(sys.cachedMusic[track])

proc feedStream(sys: SoundSystem, track: MusicTrack, restart: bool) =
  if tiered(track):
    sys.tierStreams[track].feed()
  else:
    updateMusicStream(sys.cachedMusic[track])
    # raylib loops a WAV by itself; this restarts a loop that stopped anyway
    # (a mod's file in a format raylib doesn't loop). A story score plays
    # once: its cinematic decides what comes next.
    if restart and not isMusicStreamPlaying(sys.cachedMusic[track]) and
       not isScoreTrack(track):
      seekMusicStream(sys.cachedMusic[track], 0.0)
      playMusicStream(sys.cachedMusic[track])

proc applyFadeVolume(sys: SoundSystem, track: MusicTrack) =
  ## Equal-power curve, so a fade-out loses its level smoothly.
  sys.streamVolume(track, sys.musicVolume * sin(sys.fade[track] * float32(PI) * 0.5'f32))

proc settleStream(sys: SoundSystem, track: MusicTrack) =
  ## A fade-out has finished: stop the stream, so its next start is from the
  ## top.
  sys.stopStream(track)
  sys.streamState[track] = msIdle
  sys.fade[track] = 0.0

proc resetStream(sys: SoundSystem, track: MusicTrack) =
  ## Stop a stream outright.
  if sys.streamState[track] != msIdle:
    sys.stopStream(track)
  sys.streamState[track] = msIdle
  sys.fade[track] = 0.0
  if sys.currentTrack == track:
    sys.trackPlaying = false

proc holdGameMusic*(held: bool) =
  ## mod_media, every frame: whether mod music or video sound is playing.
  ## Holding ends a fade-out at once and pauses the current track; it carries
  ## on from there once released (updateMusic skips everything while held).
  if held == gameMusicHeld:
    return
  gameMusicHeld = held
  let sys = globalSoundSystem
  if sys == nil:
    return
  for track in MusicTrack:
    case sys.streamState[track]
    of msOut:
      if held:
        sys.settleStream(track)
    of msIn:
      sys.holdStream(track, held)
    of msIdle:
      discard

proc setModSound*(st: SoundType, path: string): bool =
  ## Replace one of the game's sounds with a WAV/OGG/MP3/FLAC/QOA file. False if it
  ## could not be loaded (the built-in sound stays).
  try:
    var s = loadSound(path)
    var voices: seq[SoundAlias]
    for i in 0 ..< MAX_SOUND_VOICES:
      voices.add(loadSoundAlias(s))
    modSoundVoices[st].setLen(0)       # aliases go before their source
    modSoundVoices[st] = move voices
    modSoundSource[st] = move s
    true
  except CatchableError:
    false

proc setModMusic*(track: MusicTrack, path: string): bool =
  ## Replace one music track with a file (OGG/MP3/WAV/FLAC/QOA/XM/MOD). False on failure.
  let sys = globalSoundSystem
  if sys == nil:
    return false
  var m: Music
  try:
    m = loadMusicStream(path)
  except CatchableError:
    return false
  m.looping = not isScoreTrack(track)
  sys.resetStream(track)   # the next playMusic starts the new file from the top
  if not modMusicActive[track]:
    modMusicHadVanilla[track] = sys.musicGenerated[track]
    modMusicBackup[track] = move sys.cachedMusic[track]
  sys.cachedMusic[track] = move m
  sys.musicGenerated[track] = true   # ensureMusicLoaded must not reload over it
  modMusicActive[track] = true
  true

proc restoreVanillaSounds*() =
  for st in SoundType:
    modSoundVoices[st].setLen(0)
    reset(modSoundSource[st])
  let sys = globalSoundSystem
  for track in MusicTrack:
    if not modMusicActive[track]: continue
    if not sys.isNil:
      sys.resetStream(track)
      sys.cachedMusic[track] = move modMusicBackup[track]
      sys.musicGenerated[track] = modMusicHadVanilla[track]
    modMusicActive[track] = false

proc playSound*(soundType: SoundType, volumeMultiplier: float32 = 1.0,
                pitch: float32 = 1.0) =
  let sys = globalSoundSystem
  if sys == nil or not sys.enabled or not sys.soundsGenerated:
    return
  let minInterval = minReplayInterval(soundType)
  if minInterval > 0.0:
    let now = getTime()
    if now - sys.lastPlayTime[soundType] < minInterval:
      return
    sys.lastPlayTime[soundType] = now

  # A mod that replaced this sound plays its own pool, by the same rules.
  let modded = modSoundVoices[soundType].len == MAX_SOUND_VOICES
  # From the round-robin cursor, take the first voice that has finished; if
  # all are still sounding, the cursor's own voice is the oldest one started.
  var voiceIdx = sys.nextVoice[soundType]
  for k in 0..<MAX_SOUND_VOICES:
    let v = (sys.nextVoice[soundType] + k) mod MAX_SOUND_VOICES
    let busy = if modded: isSoundPlaying(Sound(modSoundVoices[soundType][v]))
               else: isSoundPlaying(Sound(sys.soundVoices[soundType][v]))
    if not busy:
      voiceIdx = v
      break
  sys.nextVoice[soundType] = (voiceIdx + 1) mod MAX_SOUND_VOICES

  let jitter = pitchVariation(soundType)
  let finalPitch = if jitter > 0.0: pitch * (1.0'f32 + rand(-jitter..jitter)) else: pitch
  let spread = panSpread(soundType)
  let pan = if spread > 0.0: rand(-spread..spread) else: 0.0'f32
  # Every setting is applied on every play: voices are reused and keep
  # whatever the previous play left on them.
  template play(voice: Sound) =
    setSoundVolume(voice, sys.masterVolume * volumeMultiplier)
    setSoundPitch(voice, finalPitch)
    setSoundPan(voice, pan)
    raylib.playSound(voice)
  if modded: play(Sound(modSoundVoices[soundType][voiceIdx]))
  else: play(Sound(sys.soundVoices[soundType][voiceIdx]))

proc setGameVolume*(volume: float32) =
  if globalSoundSystem != nil:
    globalSoundSystem.masterVolume = clamp(volume, 0.0, 1.0)

proc ensureMusicLoaded(sys: SoundSystem, track: MusicTrack): bool =
  ## Main thread only (opens an audio stream). True once the track is in the
  ## audio device. Deliberately never synthesises inline: if the worker has not
  ## written the WAVs yet this just answers "not yet" and the caller retries on
  ## a later frame, which is what keeps the frame loop off the synthesiser.
  if tiered(track):
    if sys.tierStreams[track].ready:
      return true
    if not isMusicReady(track):
      return false
    return sys.tierStreams[track].openTierStream(track)
  if sys.musicGenerated[track]:
    return true
  if not isMusicReady(track):
    return false
  try:
    sys.cachedMusic[track] = loadMusicStream(getMusicCacheFile(track))
    # A loop wraps inside raylib, sample-accurately; a score plays once.
    sys.cachedMusic[track].looping = not isScoreTrack(track)
    sys.musicGenerated[track] = true
    result = true
  except CatchableError:
    result = false

proc leaveTrack(sys: SoundSystem, track: MusicTrack) =
  ## Fade `track` out over 0.15 s (at once while the game's music is held).
  if sys.streamState[track] notin {msIn, msOut}:
    return
  if gameMusicHeld:
    sys.settleStream(track)
  else:
    sys.streamState[track] = msOut
    sys.fadeRate[track] = 1.0'f32 / 0.15'f32
  if sys.currentTrack == track:
    sys.trackPlaying = false

proc enterTrack(sys: SoundSystem, track: MusicTrack, tier: int) =
  ## Make `track` current and start it from its top at full volume, even if
  ## it was still fading out.
  if sys.streamState[track] != msIdle:
    sys.stopStream(track)
  sys.fade[track] = 1.0
  sys.applyFadeVolume(track)
  sys.startStream(track, tier)
  sys.streamState[track] = msIn
  sys.currentTrack = track
  sys.trackPlaying = true

proc playMusic*(track: MusicTrack, tier = 0) =
  ## Called every frame with the music the screen wants. A new track takes
  ## over from its top while the old one fades out under it; the track that
  ## is already playing only moves to `tier`, the arrangement of a run theme
  ## (see TIERS), on its next bar line. Startup has already generated every
  ## track, so this never synthesises: a track that is somehow missing stays
  ## silent rather than freezing a gameplay frame for seconds.
  let sys = globalSoundSystem
  if sys == nil or not sys.enabled:
    return
  if sys.trackPlaying and sys.currentTrack == track:
    if tiered(track) and sys.tierStreams[track].ready:
      sys.tierStreams[track].target = clamp(tier, 0, sys.tierStreams[track].files.high)
    return
  if not ensureMusicLoaded(sys, track):
    return
  if sys.trackPlaying:
    sys.leaveTrack(sys.currentTrack)
  sys.enterTrack(track, tier)

proc setMusicMuffled*(muffled: bool) =
  ## main.nim, every frame: whether the player's health is critical. The
  ## built-in loops muffle until it is not (see fillTierBlock).
  musicMuffled = muffled

proc updateMusic*() =
  ## Every frame: feed the playing streams and move their fades along.
  let sys = globalSoundSystem
  if sys == nil or not sys.enabled:
    return
  let now = getTime()
  let dt = clamp(float32(now - sys.lastMusicTick), 0.0'f32, 0.1'f32)
  sys.lastMusicTick = now
  if gameMusicHeld:
    return   # paused for a mod's music: the restart below would undo that
  for track in MusicTrack:
    case sys.streamState[track]
    of msIn:
      sys.feedStream(track, restart = true)
    of msOut:
      sys.fade[track] = max(0.0'f32, sys.fade[track] - dt * sys.fadeRate[track])
      sys.applyFadeVolume(track)
      sys.feedStream(track, restart = false)
      if sys.fade[track] <= 0.0'f32 or not sys.streamPlaying(track):
        sys.settleStream(track)
    of msIdle:
      discard

proc startScore*(track: MusicTrack): bool =
  ## Play a story score from the top at normal speed, whatever was playing
  ## (including this same score, on a replay). A score cuts in: its opening
  ## is composed, and its cues have to land on their frames; whatever it
  ## replaces fades out under it. False while the stream is not ready yet;
  ## the caller retries, and syncScore then seeks to the right spot. A
  ## disabled sound system counts as started: there is nothing to wait for.
  let sys = globalSoundSystem
  if sys == nil or not sys.enabled:
    return true
  if not ensureMusicLoaded(sys, track):
    return false
  if sys.trackPlaying and sys.currentTrack != track:
    sys.leaveTrack(sys.currentTrack)
  sys.enterTrack(track, 0)
  seekMusicStream(sys.cachedMusic[track], 0.0)
  setMusicPitch(sys.cachedMusic[track], 1.0)
  true

proc syncScore*(track: MusicTrack, position, rate: float32) =
  ## Keep a playing score on its cinematic's clock. `rate` is the playback
  ## multiplier (2 while the cutscene fast-forwards): raylib's pitch resamples
  ## the stream, so speed and pitch rise together like a tape. Drift past a
  ## quarter second (frame hitches, a mod pausing the music) is seeked away.
  let sys = globalSoundSystem
  if sys == nil or not sys.enabled or not sys.trackPlaying or
     sys.currentTrack != track or gameMusicHeld:
    return
  try:
    template music: Music = sys.cachedMusic[track]   # Music cannot be copied
    setMusicPitch(music, rate)
    let target = clamp(position, 0.0'f32, max(0.0'f32, getMusicTimeLength(music) - 0.05'f32))
    if abs(getMusicTimePlayed(music) - target) > 0.25'f32:
      seekMusicStream(music, target)
  except CatchableError:
    discard

proc stopMusic*() =
  ## Cut the music dead: game over keeps its abrupt stop.
  let sys = globalSoundSystem
  if sys == nil:
    return
  for track in MusicTrack:
    if sys.streamState[track] in {msIn, msOut}:
      sys.resetStream(track)
  sys.trackPlaying = false

proc setMusicVolume*(volume: float32) =
  let sys = globalSoundSystem
  if sys == nil:
    return
  sys.musicVolume = clamp(volume, 0.0, 1.0)
  for track in MusicTrack:
    if sys.streamState[track] in {msIn, msOut}:
      sys.applyFadeVolume(track)

proc closeSoundSystem*(sys: SoundSystem) =
  # The generator thread writes into the temp cache; never tear the process
  # down underneath it.
  abortAssetGeneration()
  if sys != nil and sys.initialized:
    for track in MusicTrack:
      sys.tierStreams[track].release()
    closeAudioDevice()
    echo "Sound system closed"
