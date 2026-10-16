## Streamed mod media (MODS.EXE): videos (assets.video) and music
## (assets.music).
##
## Videos are MPEG-1 .mpg files (MP2 sound), decoded by pl_mpeg (vendor/pl_mpeg,
## built into the exe), so a video plays the same on every system. Playback
## keeps a clock: a picture shows once the clock reaches its time, and sound is
## decoded a fixed lead ahead of it, which is how long the audio stream takes
## to play it out, so both meet at the speakers.
##
## mod_assets wraps each video as a texture, so a video goes wherever a texture
## goes. It plays while something draws it and holds still (sound included)
## while nothing does, so a hidden app or wallpaper costs no decoding. Pictures
## are converted to RGBA on the CPU into one texture, uploaded at most once per
## frame by updateModMedia before any drawing: raylib batches draws, so an
## upload in the middle of a frame would also change sprites already queued.
##
## Music is a raylib music stream. A mod's own music, or a video's sound, takes
## the music channel: the game's track waits, paused (sound.holdGameMusic).
##
## Low in the DAG (raylib + sound). updateModMedia runs once per frame from
## main.nim; unloadModMedia (through unloadModAssets) runs before the audio
## device and the window close.

import std/strutils
import raylib
import ../sound, pl_mpeg_c

const
  VideoAudioChunk = 2048
    ## Frames in each block of sound handed to a video's stream. raylib streams
    ## are double-buffered and zero-pad a short write, so every push is a whole
    ## block; a block must be no shorter than the device period (10 ms).
  MaxVideoStep = 0.5
    ## Longest stretch (seconds) one frame decodes, so a long hitch does not
    ## decode seconds of pictures at once (the sound resyncs by trimming).
  MaxCatchUp = 120
    ## Most pictures one frame decodes to catch up (the rest wait a frame).
  ShownGrace = 0.2
    ## A video drawn this recently (wall clock, seconds) counts as on screen.
  EndGrace = 0.15
    ## Seconds a finished video's stream keeps running to play out its tail.
  ConvertHint* = "ffmpeg -i in.mp4 -c:v mpeg1video -q:v 4 -c:a mp2 -b:a 192k -f mpeg out.mpg"

type
  ModVideo = object
    plm: Plm
    seekPicture: PlmFrame   ## the picture plm_seek landed on
    path: string
    tex: Texture2D
    front, back: seq[Color] ## the picture on show; the next one, waiting for its time
    w, h: int
    fps, duration: float
    clock: float            ## playback position, seconds
    nextTime: float         ## time of the picture in `back`
    haveNext, videoDone, audioDone, dirty: bool
    hasAudio: bool          ## the file has a sound track
    stream: AudioStream
    streamReady: bool       ## the sound track plays (the audio device works)
    streamStarted, streamOn: bool
    samples: seq[float32]   ## decoded sound not yet handed to the stream (stereo)
    head: int               ## first sample of `samples` not handed over
    audioTime: float        ## where the sound decoded so far ends
    rate: int
    leadTime: float         ## seconds of sound decoded ahead of the clock
    loop, paused, ended, running: bool
    volume: float32
    shownAt, endedAt: float ## wall clock

  ModMusic = object
    music: Music
    path: string
    ready: bool             ## a stream exists (false without an audio device)
    playing, paused: bool   ## stopped = neither
    runScoped: bool         ## started during a run: stops when the run leaves the screen
    loop, layer: bool
    volume, pitch, pan: float32

var
  modVideos: seq[ModVideo]
  modMusic: seq[ModMusic]
  lastMediaUpdate = -1.0

# ------------------------------------------------------------------- videos ----
proc onSeekPicture(plm: Plm, frame: PlmFrame, user: pointer) {.cdecl.} =
  ## pl_mpeg, inside plm_seek: the picture it landed on (valid until the next
  ## decode call).
  modVideos[cast[int](user) - 1].seekPicture = frame

proc isMpeg2(head: string): bool =
  ## True when the first video sequence header is followed by an MPEG-2
  ## sequence extension: pl_mpeg reads MPEG-1 only and would show garbage.
  let seqHdr = head.find("\x00\x00\x01\xB3")
  if seqHdr < 0: return false
  let next = head.find("\x00\x00\x01", seqHdr + 4)
  next >= 0 and next + 3 < head.len and head[next + 3] == '\xB5'

proc toPicture(v: var ModVideo, dest: var seq[Color], f: PlmFrame) =
  plm_frame_to_rgba(f, cast[ptr uint8](addr dest[0]), cint(v.w * 4))

proc readPicture(v: var ModVideo, dest: var seq[Color], t: var float): bool =
  ## Decode the next picture into `dest` (t = its time); false at the end.
  let f = plm_decode_video(v.plm)
  if f.isNil: return false
  toPicture(v, dest, f)
  t = f.time
  true

proc readSound(v: var ModVideo): bool =
  ## Decode the next block of sound onto `samples`; false at the end.
  let s = plm_decode_audio(v.plm)
  if s.isNil: return false
  v.samples.add(s.interleaved)
  v.audioTime = s.time.float + PlmAudioSamplesPerFrame / v.rate
  true

proc loadModVideo*(path: string, err: var string): int =
  ## Open an MPEG-1 video (once per path; every user of the file shares its
  ## playback) with its first picture on show. Returns the video id, 0 with
  ## `err` set.
  for i in 0 ..< modVideos.len:
    if modVideos[i].path == path: return i + 1
  var head = ""
  try:
    var f = open(path)
    defer: f.close()
    head = newString(min(f.getFileSize, 262144).int)
    if head.len > 0: head.setLen(f.readBuffer(addr head[0], head.len))
  except CatchableError:
    err = "could not read the file"
    return 0
  if isMpeg2(head):
    err = "the video is MPEG-2, and only MPEG-1 plays; convert it with: " & ConvertHint
    return 0
  let plm = plm_create_with_filename(path.cstring)
  if plm.isNil:
    err = "could not read the file"
    return 0
  if plm_has_headers(plm) == 0 or plm_get_num_video_streams(plm) == 0 or
     plm_get_width(plm) <= 0 or plm_get_height(plm) <= 0:
    plm_destroy(plm)
    err = "not an MPEG-1 video; convert it with: " & ConvertHint
    return 0
  var v = ModVideo(plm: plm, path: path, w: plm_get_width(plm).int, h: plm_get_height(plm).int,
                   fps: plm_get_framerate(plm).float, duration: plm_get_duration(plm).float,
                   hasAudio: plm_get_num_audio_streams(plm) > 0 and plm_get_samplerate(plm) > 0,
                   rate: plm_get_samplerate(plm).int, loop: true, volume: 1)
  plm_set_loop(plm, 0)   # the playback loop below loops (and seeks) itself
  v.front = newSeq[Color](v.w * v.h)
  for c in v.front.mitems: c.a = 255   # pl_mpeg writes RGB only
  v.back = v.front
  try:
    v.tex = loadTextureFromData(v.front, v.w.int32, v.h.int32)
  except CatchableError:
    plm_destroy(plm)
    err = "the video is too large for a texture"
    return 0
  setTextureFilter(v.tex, TextureFilter.Bilinear)
  if v.hasAudio and isAudioDeviceReady():
    setAudioStreamBufferSizeDefault(VideoAudioChunk)
    try:
      v.stream = loadAudioStream(v.rate.uint32, 32, 2)
      v.streamReady = true
    except CatchableError:
      discard
    setAudioStreamBufferSizeDefault(0)
  # The stream holds two blocks: sound decoded that far ahead of the clock
  # (plus slack) reaches the speakers as its picture shows.
  if v.streamReady: v.leadTime = 2 * VideoAudioChunk / v.rate + 0.05
  else: plm_set_audio_enabled(plm, 0)
  let id = modVideos.len + 1
  plm_set_video_decode_callback(plm, onSeekPicture, cast[pointer](id))
  # The first picture shows until the video first plays, which goes on from it.
  var t = 0.0
  if readPicture(v, v.front, t): updateTexture(v.tex, v.front)
  modVideos.add(move v)
  id

template video(id: int): ptr ModVideo = addr modVideos[id - 1]

proc validVideo(id: int): bool {.inline.} = id > 0 and id <= modVideos.len

proc videoTexture*(id: int): ptr Texture2D =
  ## The video's picture, for a draw: being drawn is what keeps a video playing.
  let v = video(id)
  v.shownAt = getTime()
  addr v.tex

proc videoSize*(id: int): tuple[w, h: int] =
  if validVideo(id): (video(id).w, video(id).h) else: (0, 0)

proc resetStream(v: var ModVideo) =
  ## Drop every sound queued (for a seek): the stream and the waiting samples.
  if v.streamReady and v.streamStarted:
    stopAudioStream(v.stream)
  v.streamStarted = false
  v.streamOn = false
  v.samples.setLen(0)
  v.head = 0

proc restart(v: var ModVideo) =
  ## Back to the start (the decoders and the clock; queued sound is kept, so a
  ## loop flows on).
  plm_rewind(v.plm)
  v.clock = 0
  v.audioTime = 0
  v.haveNext = false
  v.videoDone = false
  v.audioDone = false

proc seekVideo*(id: int, seconds: float) =
  ## Jump to `seconds` into the video, showing the picture there.
  if not validVideo(id): return
  let v = video(id)
  resetStream(v[])
  var target = if seconds > 0 and seconds < 1.0e9: seconds else: 0.0   # (NaN: 0)
  if v.duration > 0: target = min(target, v.duration)
  v.seekPicture = PlmFrame(nil)
  # plm_seek decodes up to the exact picture (handing it to onSeekPicture) and
  # moves the sound to the first block after it.
  if target <= 0 or plm_seek(v.plm, target, 1) == 0:
    restart(v[])
    target = 0
  v.clock = target
  v.audioTime = target
  v.haveNext = false
  v.videoDone = false
  v.audioDone = false
  v.ended = false
  var t = 0.0
  if not v.seekPicture.isNil:
    toPicture(v[], v.front, v.seekPicture)
    v.seekPicture = PlmFrame(nil)
    updateTexture(v.tex, v.front)
  elif readPicture(v[], v.front, t):
    updateTexture(v.tex, v.front)

proc playVideo*(id: int) =
  ## Play on the next draw; a video that reached its end starts over.
  if not validVideo(id): return
  if video(id).ended: seekVideo(id, 0)
  video(id).paused = false

proc pauseVideo*(id: int) =
  if validVideo(id): video(id).paused = true

proc stopVideo*(id: int) =
  ## Pause and go back to the first picture.
  if not validVideo(id): return
  seekVideo(id, 0)
  video(id).paused = true

proc setVideoLoop*(id: int, loop: bool) =
  if validVideo(id): video(id).loop = loop

proc setVideoVolume*(id: int, volume: float32) =
  if validVideo(id): video(id).volume = clamp(volume, 0, 4)

type VideoInfo* = object
  width*, height*: int
  fps*, duration*, time*: float
  volume*: float32
  loop*, paused*, ended*, playing*, hasAudio*: bool

proc videoInfo*(id: int): VideoInfo =
  if not validVideo(id): return
  let v = video(id)
  let t = if v.duration > 0: min(v.clock, v.duration) else: v.clock
  VideoInfo(width: v.w, height: v.h, fps: v.fps, duration: v.duration, time: max(t, 0),
            volume: v.volume, loop: v.loop, paused: v.paused, ended: v.ended, playing: v.running,
            hasAudio: v.hasAudio)

proc advance(v: var ModVideo, dt: float, now: float) =
  ## One frame of playback: move the clock, show the pictures it reached,
  ## decode sound up to the lead, and loop or finish at the end.
  v.clock += dt
  var shown = 0
  while not v.videoDone and shown < MaxCatchUp:
    if not v.haveNext:
      var t = 0.0
      if not readPicture(v, v.back, t):
        v.videoDone = true
        break
      v.nextTime = t
      v.haveNext = true
    if v.nextTime > v.clock: break
    swap(v.front, v.back)
    v.haveNext = false
    v.dirty = true
    inc shown
  if v.dirty:
    updateTexture(v.tex, v.front)
    v.dirty = false
  if v.streamReady:
    var blocks = 0
    while not v.audioDone and v.audioTime < v.clock + v.leadTime and blocks < 512:
      if not readSound(v): v.audioDone = true
      inc blocks
  if v.videoDone and not v.haveNext and (v.audioDone or not v.streamReady):
    if v.loop:
      restart(v)
    else:
      v.ended = true
      v.running = false
      v.endedAt = now

proc feedSound(v: var ModVideo, now: float): bool =
  ## Hand decoded sound to the video's stream; true while it is audible.
  if not v.streamReady: return false
  let wanted = v.running or (v.ended and now - v.endedAt < EndGrace)
  if not wanted:
    if v.streamOn:
      pauseAudioStream(v.stream)
      v.streamOn = false
    return false
  # Sound that fell behind its picture (a hitch starved the stream, so it
  # stopped while the picture went on) is dropped rather than played late.
  let maxWaiting = int(v.leadTime * v.rate.float) * 2
  if v.samples.len - v.head > maxWaiting:
    v.head = v.samples.len - maxWaiting
  let sys = globalSoundSystem
  let gain = if sys.isNil or not sys.enabled: 0.0'f32 else: sys.masterVolume * v.volume
  setAudioStreamVolume(v.stream, gain)
  while isAudioStreamProcessed(v.stream):
    let waiting = v.samples.len - v.head
    if waiting >= VideoAudioChunk * 2:
      updateAudioStream(v.stream, v.samples.toOpenArray(v.head, v.head + VideoAudioChunk * 2 - 1))
      v.head += VideoAudioChunk * 2
    elif v.ended and waiting > 0:
      updateAudioStream(v.stream, v.samples.toOpenArray(v.head, v.samples.high))  # raylib pads it
      v.head = v.samples.len
    else:
      break
  if v.head >= 65536:            # drop what was handed over
    let rest = v.samples.len - v.head
    if rest > 0: moveMem(addr v.samples[0], addr v.samples[v.head], rest * sizeof(float32))
    v.samples.setLen(rest)
    v.head = 0
  if not v.streamOn:
    if v.streamStarted: resumeAudioStream(v.stream)
    else: playAudioStream(v.stream)
    v.streamStarted = true
    v.streamOn = true
  gain > 0

# -------------------------------------------------------------------- music ----
proc loadModMusic*(path: string, err: var string): int =
  ## A music stream (once per path). Without an audio device it still loads,
  ## silent. Returns the music id, 0 with `err` set.
  for i in 0 ..< modMusic.len:
    if modMusic[i].path == path: return i + 1
  var m = ModMusic(path: path, loop: true, volume: 1, pitch: 1)
  if isAudioDeviceReady():
    try:
      m.music = loadMusicStream(path)
      m.ready = true
    except CatchableError:
      err = "could not load the file (OGG, MP3, WAV, FLAC, QOA, XM or MOD expected)"
      return 0
  modMusic.add(move m)
  modMusic.len

template tune(id: int): ptr ModMusic = addr modMusic[id - 1]

proc validMusic(id: int): bool {.inline.} = id > 0 and id <= modMusic.len

proc stopModMusic*(id: int) =
  if not validMusic(id): return
  let m = tune(id)
  if m.ready and (m.playing or m.paused): stopMusicStream(m.music)
  m.playing = false
  m.paused = false

proc playModMusic*(id: int, inRun: bool) =
  ## Play from where it was paused, or from the start. Unless it is a layer,
  ## it replaces any other mod music that is not one. `inRun`: started while a
  ## run is on screen, so it stops when the run leaves it.
  if not validMusic(id): return
  let m = tune(id)
  if m.playing: return
  if not m.layer:
    for other in 1 .. modMusic.len:
      if other != id and not tune(other).layer: stopModMusic(other)
  if m.ready:
    m.music.looping = m.loop
    setMusicPitch(m.music, m.pitch)
    setMusicPan(m.music, m.pan)
    if m.paused: resumeMusicStream(m.music)
    else: playMusicStream(m.music)
  m.playing = true
  m.paused = false
  m.runScoped = inRun

proc pauseModMusic*(id: int) =
  if not validMusic(id) or not tune(id).playing: return
  let m = tune(id)
  if m.ready: pauseMusicStream(m.music)
  m.playing = false
  m.paused = true

proc seekModMusic*(id: int, seconds: float32) =
  if not validMusic(id) or not tune(id).ready: return
  let m = tune(id)
  let len = getMusicTimeLength(m.music)
  seekMusicStream(m.music, if seconds > 0: min(seconds, max(len - 0.01'f32, 0)) else: 0)

type MusicInfo* = object
  duration*, time*, volume*, pitch*, pan*: float32
  playing*, paused*, loop*, layer*: bool

proc musicInfo*(id: int): MusicInfo =
  if not validMusic(id): return
  let m = tune(id)
  result = MusicInfo(volume: m.volume, pitch: m.pitch, pan: m.pan, playing: m.playing,
                     paused: m.paused, loop: m.loop, layer: m.layer)
  if m.ready:
    result.duration = getMusicTimeLength(m.music)
    if m.playing or m.paused: result.time = getMusicTimePlayed(m.music)

proc setMusicOption*(id: int, loop, layer: bool, volume, pitch, pan: float32) =
  ## The settable fields of a music handle, all at once.
  if not validMusic(id): return
  let m = tune(id)
  m.loop = loop
  m.volume = clamp(volume, 0, 4)
  m.pitch = clamp(pitch, 0.1, 4)
  m.pan = clamp(pan, -1, 1)
  if layer != m.layer:
    if m.playing or m.paused: stopModMusic(id)
    m.layer = layer
  if m.ready:
    m.music.looping = loop
    setMusicPitch(m.music, m.pitch)
    setMusicPan(m.music, m.pan)

# ---------------------------------------------------------------- the frame ----
proc updateModMedia*(inRun: bool) =
  ## main.nim, once per frame before anything draws: play the videos on
  ## screen, feed their sound, stream the mod music and hand the music channel
  ## to whichever of them is playing. `inRun`: a run is on screen.
  let now = getTime()
  let dt = if lastMediaUpdate < 0: 0.0 else: clamp(now - lastMediaUpdate, 0.0, MaxVideoStep)
  lastMediaUpdate = now
  var hold = false
  for i in 0 ..< modVideos.len:
    let v = addr modVideos[i]
    v.running = now - v.shownAt <= ShownGrace and not v.paused and not v.ended
    if v.running: advance(v[], dt, now)
    if feedSound(v[], now): hold = true
  let sys = globalSoundSystem
  let musicGain = if sys.isNil or not sys.enabled: 0.0'f32 else: sys.musicVolume
  for i in 1 .. modMusic.len:
    let m = tune(i)
    if m.runScoped and not inRun and (m.playing or m.paused):
      stopModMusic(i)
    if not m.playing:
      if m.paused and not m.layer: hold = true   # a paused track keeps the channel
      continue
    if m.ready:
      setMusicVolume(m.music, musicGain * m.volume)
      updateMusicStream(m.music)
      if not isMusicStreamPlaying(m.music):     # the end of a track that does not loop
        stopModMusic(i)
        continue
    if not m.layer: hold = true
  holdGameMusic(hold)

proc unloadModMedia*() =
  ## Every video and music stream goes (before the audio device closes), and
  ## the game's music gets its channel back.
  for v in modVideos.mitems: plm_destroy(v.plm)
  modVideos.setLen(0)        # textures and streams go with them
  for i in 1 .. modMusic.len: stopModMusic(i)
  modMusic.setLen(0)
  holdGameMusic(false)
