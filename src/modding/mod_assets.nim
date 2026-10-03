## Mod textures, 3D models and cosmetics (MODS.EXE).
##
## Everything in this game is drawn in code; mods may swap any of the main
## bodies for a PNG, an animated GIF or a 3D model: the player, an enemy type,
## a boss, bullets, power-up icons, the desktop wallpaper and the desktop cube
## (override.texture / override.model), or ship cosmetics the player equips
## from MODS.EXE (register.cosmetic: a palette, a texture and/or a model).
##
## Low in the DAG (raylib + types + sound) so the renderers can call the
## draw helpers directly. Textures and models are GPU resources: they load
## after the window exists and unloadModAssets must run before it closes.
## A texture may also be a video (mod_media decodes it): it then goes
## everywhere a texture goes and plays while it is drawn.

import std/[tables, math, strutils, os]
from std/unicode import runes
import raylib, rlgl
import ../types, ../sound
import mod_media

type
  ModelPose* = object
    ## How a 3D model stands on screen. Angles in degrees.
    tilt*: float32         ## the camera leans back from straight above (0 = top-down)
    yaw*: float32          ## turn about the model's up axis
    pitch*, roll*: float32 ## tip the model forward / lean it sideways
    spin*: float32         ## keeps turning about the up axis, degrees per second
    anim*: int             ## animation index + 1; 0 = hold the rest pose
    speed*: float32        ## animation speed (1 = as authored)
    lit*: bool             ## shaded by the scene light (false: flat colours)
    tint*: Color
    fade*: float32         ## seconds a switch to this animation crossfades (0 snaps)

  AnimKey* = tuple[owner: uint64, name: string]
    ## One drawn instance's crossfade memory: an entity (its ref, no name) or a
    ## script's draw.model `key` (the mod's VM plus the key). owner 0 = none.

  BodyReplace* = object
    ## A mod's look for one of the game's bodies: a texture or a 3D model
    ## (a model wins when both are set).
    id*: int           ## texture: index + 1 into modTextures; 0 = none
    model*: int        ## 3D model: index + 1 into modModels; 0 = none
    scale*: float32    ## multiplier on the body's diameter
    rotate*: bool      ## turn with the body (movement / rotation)
    pose*: ModelPose

  ModTexture = object
    frames: seq[Texture2D]
      ## One texture per frame (a still image has one). Separate textures rather
      ## than one re-uploaded texture: raylib batches draws, so two sprites of
      ## the same GIF on different frames in one frame need both on the GPU.
    ends: seq[float32]  ## animated: when each frame ends, in seconds into the loop
    video: int          ## a video (mod_media id; no frames here): its picture
    path: string

  ModCosmeticKind* = enum
    mckPlayer = "player", mckBullet = "bullet", mckDesktop = "desktop",
    mckCube = "cube"

  ModCosmetic* = object
    kind*: ModCosmeticKind
    key*: string       ## "<mod id>:<id>", what Settings.modCosmetics stores
    name*, description*: string
    owner*: int
    hasPalette*: bool
    c1*, c2*, c3*: Color   ## player: primary/secondary/core; bullet: primary/glow/trail
    look*: BodyReplace
      ## texture and/or model. Desktop: the texture is the wallpaper and the
      ## model stands in for the desktop cube.
    cube*: bool            ## desktop: keep the desktop cube over the wallpaper

var
  modTextures: seq[ModTexture]
  playerTex*: BodyReplace
  enemyTex*: array[EnemyType, BodyReplace]
  bossTex*: Table[int, BodyReplace]
  bulletTex*: array[bool, BodyReplace]         ## [fromPlayer]
  powerUpTex*: array[PowerUpType, BodyReplace]
  boss3dTex*, satellite3dTex*: BodyReplace         ## override.*("boss3d" / "satellite3d")
  entity3dTex*: Table[string, BodyReplace]         ## "entity3d:<tag>"
  projectile3dTex*: array[bool, BodyReplace]       ## "projectile3d:player|enemy", [fromPlayer]
  pickup3dTex*: Table[string, BodyReplace]         ## "pickup3d:<kind>"
  desktopTex*: BodyReplace
  desktopCube*: bool                               ## override.texture("desktop", ..., {cube = true})
  cubeModel*: BodyReplace                          ## override.model("cube")
  modCosmetics*: seq[ModCosmetic]
  equippedCosmetic*: array[ModCosmeticKind, int]  ## index + 1, 0 = none
  modTexturesActive*: bool                         ## any replacement at all (fast bail-out)
  pvpDrawing*: bool
    ## Set while PvP draws: bullets then wear their SHOOTER's cosmetic
    ## (pvpBulletCosmetic), never the local player's.
  pvpBulletCosmetic*: int
    ## PvP: the bullet cosmetic (index + 1) of the player who fired the bullet
    ## being drawn; drawPvP sets it per bullet.
  playerHeading: Table[pointer, float32]
    ## The way each player last moved: a turning body keeps facing it after
    ## the player stops, instead of snapping back to face right.

proc gifFrameDelays(data: string): seq[float32] =
  ## How long each frame of a GIF file shows, in seconds, read from its
  ## Graphic Control Extensions: raylib decodes the frames but drops their
  ## timing. A frame with no delay of its own keeps the previous one (as
  ## stb_image, raylib's decoder, does) and a delay under 2/100 s plays as
  ## 1/10 s, as in web browsers.
  if data.len < 13 or not data.startsWith("GIF8"): return
  template colorTableSize(flags: char): int =
    (if (flags.uint8 and 0x80) != 0: 3 shl ((flags.uint8 and 7) + 1) else: 0)
  template skipSubBlocks() =
    while p < data.len and data[p] != '\0': p += data[p].int + 1
    inc p
  var p = 13 + colorTableSize(data[10])   # header, screen descriptor, global table
  var delay = 0                           # hundredths of a second
  while p < data.len:
    case data[p]
    of '\x21':                            # extension
      if p + 5 < data.len and data[p + 1] == '\xF9' and data[p + 2].int >= 4:
        delay = data[p + 4].int or (data[p + 5].int shl 8)
      p += 2
      skipSubBlocks()
    of '\x2C':                            # image descriptor: one frame
      if p + 10 > data.len: break
      p += 10 + colorTableSize(data[p + 9])
      inc p                               # LZW minimum code size
      skipSubBlocks()
      result.add(float32(if delay < 2: 10 else: delay) / 100)
    else: break                           # trailer (or a damaged file)

const
  ImageExts* = [".png", ".jpg", ".jpeg", ".bmp", ".tga", ".gif", ".qoi", ".psd", ".hdr", ".pic",
                ".ppm", ".pgm", ".dds", ".ktx", ".pkm", ".pvr", ".astc"]
    ## Every image format raylib decodes here (config.nims switches them on).
  VideoExts* = [".mpg", ".mpeg"]
    ## MPEG-1 (built in through pl_mpeg, so it plays the same everywhere)
  OtherVideoExts = [".mp4", ".m4v", ".mov", ".webm", ".mkv", ".avi", ".wmv", ".ogv", ".flv"]
    ## not played: only named so the error says how to convert them
  ImageFormatList* = "PNG, JPG, BMP, TGA, GIF, QOI, PSD, HDR, PIC, PPM/PGM, DDS, KTX, PKM, PVR or ASTC"

proc isTextureFile*(path: string): bool =
  ## A file that loads as a texture: an image or a video.
  let ext = path.splitFile.ext.toLowerAscii
  ext in ImageExts or ext in VideoExts

proc textureFrameAtImpl(t: ModTexture, time: float): int =
  ## The frame (0-based) an animated texture shows `time` seconds into its
  ## animation, which loops. Always 0 for a still image or a video.
  if t.ends.len == 0: return 0
  let at = floorMod(time, t.ends[^1].float).float32
  var lo = 0
  var hi = t.ends.high
  while lo < hi:                  # the first frame that has not ended at `at`
    let mid = (lo + hi) div 2
    if t.ends[mid] <= at: lo = mid + 1
    else: hi = mid
  lo

proc loadModTexture*(path: string, err: var string): int =
  ## Load an image, a GIF with all of its frames and their timing, or a video
  ## (once per path). Returns the texture id, 0 with `err` set on failure.
  for i in 0 ..< modTextures.len:   # (by index: a texture cannot be copied)
    if modTextures[i].path == path: return i + 1
  let ext = path.splitFile.ext.toLowerAscii
  var t = ModTexture(path: path)
  if ext in VideoExts:
    t.video = loadModVideo(path, err)
    if t.video == 0: return 0
    modTextures.add(move t)
    return modTextures.len
  if ext in OtherVideoExts:
    err = "only MPEG-1 .mpg videos play; convert it with: " & ConvertHint
    return 0
  if ext notin ImageExts:
    err = "unsupported format (" & ImageFormatList & " images, or an MPEG-1 .mpg video)"
    return 0
  try:
    if ext == ".gif":
      let data = readFile(path)
      var count = [0'i32]
      let img = loadImageAnimFromMemory(".gif", data.toOpenArrayByte(0, data.high), count)
      if count[0] <= 1:
        t.frames.add(loadTextureFromImage(img))
      else:
        # The frames come as one RGBA buffer, one whole image after another.
        let px = cast[ptr UncheckedArray[Color]](img.data)
        let n = img.width.int * img.height.int
        for f in 0 ..< count[0].int:
          t.frames.add(loadTextureFromData(toOpenArray(px, f * n, f * n + n - 1),
                                           img.width, img.height))
        let delays = gifFrameDelays(data)
        var at = 0.0'f32
        for f in 0 ..< t.frames.len:
          at += (if f < delays.len: delays[f] else: 0.1'f32)
          t.ends.add(at)
    else:
      # Read here rather than by raylib: its loader matches only ".png" or
      # ".PNG" (not ".Png"), and Nim opens paths with any characters in them.
      let data = readFile(path)
      if data.len == 0:
        err = "the file is empty"
        return 0
      let img = loadImageFromMemory(ext, data.toOpenArrayByte(0, data.high))
      t.frames.add(loadTextureFromImage(img))
  except CatchableError:
    err = "could not load the image (a damaged file, or a format variant raylib cannot read)"
    return 0
  for f in 0 ..< t.frames.len: setTextureFilter(t.frames[f], TextureFilter.Bilinear)
  modTextures.add(move t)
  modTextures.len

proc loadModTexture*(path: string): int =
  var err = ""
  loadModTexture(path, err)

proc textureVideo*(id: int): int =
  ## The video (mod_media id) texture `id` shows; 0 for an image.
  if id <= 0 or id > modTextures.len: 0 else: modTextures[id - 1].video

proc frameTexture(id: int, time: float, frame = -1): ptr Texture2D =
  ## What texture `id` shows now: a GIF's frame `time` seconds into its loop
  ## (or `frame`, 0-based), a video's current picture (asking for it is what
  ## keeps the video playing), else the image. `id` must be valid.
  let m = addr modTextures[id - 1]
  if m.video > 0: return videoTexture(m.video)
  let f = if frame >= 0: frame mod m.frames.len
          elif m.ends.len > 0: textureFrameAtImpl(m[], time)
          else: 0
  addr m.frames[f]

type ModSound = object
  src: Sound
  voices: seq[SoundAlias]
  next: int
  path: string

var modSounds: seq[ModSound]

proc loadModSound*(path: string): int =
  ## A mod's own sound (assets.sound). Returns its id, 0 on failure.
  for i in 0 ..< modSounds.len:
    if modSounds[i].path == path: return i + 1
  try:
    var src = loadSound(path)
    var voices: seq[SoundAlias]
    for i in 0 ..< 4: voices.add(loadSoundAlias(src))
    modSounds.add(ModSound(src: move src, voices: move voices, path: path))
    modSounds.len
  except CatchableError:
    0

proc playModSound*(id: int, volume, pitch: float32) =
  if id <= 0 or id > modSounds.len or globalSoundSystem.isNil or
     not globalSoundSystem.enabled:
    return
  let s = addr modSounds[id - 1]
  let v = s.next
  s.next = (s.next + 1) mod s.voices.len
  template voice: Sound = Sound(s.voices[v])
  setSoundVolume(voice, globalSoundSystem.masterVolume * volume)
  setSoundPitch(voice, pitch)
  raylib.playSound(voice)

# -------------------------------------------------------------------- fonts ----
# assets.font: TrueType/OpenType fonts (baked at one size), BMFont .fnt and BDF
# bitmap fonts, for draw.text and draw3d.text. Every font carries ASCII and
# Latin-1 (the game's own text range, so Spanish shows) plus any characters the
# mod asks for.
type ModFont = object
  font: Font
  key: string

const FontExts* = [".ttf", ".otf", ".fnt", ".bdf"]

var modFonts: seq[ModFont]

proc loadModFont*(path: string, size: int, smooth: bool, extra: string, err: var string): int =
  ## Load a font (once per file and options): TTF/OTF glyphs are baked at
  ## `size` pixels; a .fnt or .bdf keeps its own size. `extra` lists more
  ## characters to bake. Returns the font id, 0 with `err` set.
  let ext = path.splitFile.ext.toLowerAscii
  if ext notin FontExts:
    err = "unsupported format (TTF, OTF, FNT or BDF expected)"
    return 0
  let key = path & "|" & $size & "|" & $smooth & "|" & extra
  for i in 0 ..< modFonts.len:
    if modFonts[i].key == key: return i + 1
  var codepoints: seq[int32]
  for c in 32 .. 126: codepoints.add c.int32
  for c in 160 .. 255: codepoints.add c.int32
  for r in extra.runes:
    if r.int32 >= 32 and r.int32 notin codepoints: codepoints.add r.int32
  if codepoints.len * size * size > 4096 * 4096:
    err = "too many characters at this size for one font atlas"
    return 0
  var f: Font
  try:
    f = if ext == ".fnt": loadFont(path) else: loadFont(path, size.int32, codepoints)
  except CatchableError:
    err = "could not load the font (a damaged file, or no glyphs in it)"
    return 0
  # raylib hands back its own default font when a file has no usable glyphs
  # (unloading it is a no-op, so letting `f` go is safe).
  if f.texture.id == getFontDefault().texture.id:
    err = "could not load the font (a damaged file, or no glyphs in it)"
    return 0
  setTextureFilter(f.texture, if smooth: TextureFilter.Bilinear else: TextureFilter.Point)
  modFonts.add(ModFont(font: move f, key: key))
  modFonts.len

proc fontBaseSize*(id: int): int =
  ## The size (pixels) a font's glyphs were made at: text drawn at it is crispest.
  if id <= 0 or id > modFonts.len: 0 else: modFonts[id - 1].font.baseSize.int

proc drawModText*(id: int, text: string, x, y, size, spacing: float32, tint: Color) =
  ## Text in font `id` (UTF-8), its top-left corner at (x, y).
  if id <= 0 or id > modFonts.len: return
  drawText(modFonts[id - 1].font, text, Vector2(x: x, y: y), size, spacing, tint)

proc measureModText*(id: int, text: string, size, spacing: float32): float32 =
  if id <= 0 or id > modFonts.len: 0.0'f32
  else: measureText(modFonts[id - 1].font, text, size, spacing).x

# ------------------------------------------------------------------ shaders ----
# assets.shader / override.shader: GLSL fragment shaders (with an optional
# vertex shader) run over the finished frame (post-processing). "screen" covers
# everything; "game" only while a run is on screen (and wins over "screen"
# then). A shader may sample mod textures and videos (shader:set).
type ModShader = object
  shader: Shader
  key: string
  time, resolution: ShaderLocation
  samplers: seq[tuple[loc: ShaderLocation, tex: int]]

const MaxShaderTextures* = 4   ## raylib's extra texture units per draw batch

var
  modShaders: seq[ModShader]
  screenShader*, gameShader*: int   ## override.shader targets (index + 1, 0 = none)
  postShaderInRun*: bool            ## main.nim, each frame: is a run on screen?

proc loadModShader*(path: string, err: var string, vertexPath = ""): int =
  ## A fragment shader file, with a vertex shader file or raylib's default
  ## one. 0 and `err` set when it cannot be used; GLSL compile errors fall back
  ## to raylib's default shader, which is reported here rather than silently
  ## drawing nothing new.
  let key = path & "|" & vertexPath
  for i in 0 ..< modShaders.len:
    if modShaders[i].key == key: return i + 1
  try:
    var s = loadShader(vertexPath, path)
    if s.id == 0 or s.id == getShaderIdDefault():
      err = "the shader did not compile (GLSL 330 expected; the Log tab has the reason)"
      return 0
    let t = getShaderLocation(s, "time")
    let r = getShaderLocation(s, "resolution")
    modShaders.add(ModShader(shader: move s, key: key, time: t, resolution: r))
    modShaders.len
  except CatchableError as e:
    err = e.msg
    0

proc setModShaderTexture*(id: int, name: string, tex: int): int =
  ## shader:set(name, texture): a sampler2D uniform reads texture `tex` (a
  ## GIF's current frame, a video's picture). 1 = set, 0 = the shader has no
  ## such uniform, -1 = it already reads MaxShaderTextures others.
  if id <= 0 or id > modShaders.len: return 0
  let s = addr modShaders[id - 1]
  let loc = getShaderLocation(s.shader, name)
  if loc.int32 < 0: return 0
  for e in s.samplers.mitems:
    if e.loc.int32 == loc.int32:
      e.tex = tex
      return 1
  if s.samplers.len >= MaxShaderTextures: return -1
  s.samplers.add((loc, tex))
  1

proc setModShaderValue*(id: int, name: string, values: openArray[float32]): bool =
  ## shader:set(name, value): a float or a 2-4 float vector. False if the
  ## shader has no such uniform.
  if id <= 0 or id > modShaders.len: return false
  let s = addr modShaders[id - 1]
  let loc = getShaderLocation(s.shader, name)
  if loc.int32 < 0: return false
  case values.len
  of 1: setShaderValue(s.shader, loc, values[0])
  of 2: setShaderValue(s.shader, loc, [values[0], values[1]])
  of 3: setShaderValue(s.shader, loc, [values[0], values[1], values[2]])
  else: setShaderValue(s.shader, loc, [values[0], values[1], values[2], values[3]])
  true

proc beginPostShader*(w, h: float32, time: float32): bool =
  ## main.nim, around the final blit: starts the active post-process shader,
  ## with its `time` and `resolution` uniforms filled in. False = none.
  let id = if postShaderInRun and gameShader > 0: gameShader else: screenShader
  if id <= 0 or id > modShaders.len: return false
  let s = addr modShaders[id - 1]
  if s.time.int32 >= 0: setShaderValue(s.shader, s.time, time)
  if s.resolution.int32 >= 0: setShaderValue(s.shader, s.resolution, [w, h])
  beginShaderMode(s.shader)
  # Texture units are claimed per draw batch, and beginShaderMode just ended
  # the last one, so the samplers are bound again on every use.
  let now = getTime()
  for (loc, tex) in s.samplers:
    if tex > 0 and tex <= modTextures.len:
      setShaderValueTexture(s.shader, loc, frameTexture(tex, now)[])
  true

# ------------------------------------------------------------------- models ----
# assets.model / override.model / draw.model: 3D models (glTF/GLB, OBJ, IQM,
# VOX, M3D) drawn right inside the 2D passes, so they sit in the arena, the HUD
# and the windows like any sprite. A draw flushes the 2D batch, keeps the 2D
# projection's x/y mapping (every push/translate/scale in force still places
# the model) but gives it depth room, and draws with the depth test on. Each
# draw claims a fresh slab of depth in front of all the earlier ones, so a
# model hides its own far side yet still layers in draw order, like a sprite.
#
# Screen space here is x right, y down, z toward the viewer. Models are +Y up
# with their front on +Z (the glTF convention).

type
  ModModel = object
    model: Model
    anims: RArray[ModelAnimation]
    animIdx: seq[int]        ## usable animations (skeleton matches): index into anims
    animNames: seq[string]
    animFrames: seq[int]
    center, size: Vector3    ## bounding box, model units
    radius: float32          ## bounding sphere around `center`
    path: string

  LookShader = object
    ## The shader every mod model draws with: texture x material colour x
    ## vertex colour, one key light, GPU skinning for animations.
    shader: Shader
    tried, ok, skinning: bool
    normal, tint, lit, skinned, bones: ShaderLocation

  Mat3 = array[9, float32]   ## row-major

const
  ModelFps = 60.0
    ## Animation frames per second: raylib samples glTF and M3D animations at
    ## this rate, so they play at their authored speed.
  DepthHalf = 524288.0'f32
    ## Models share z in [-DepthHalf, DepthHalf] between depth clears: 1/16
    ## pixel of depth precision (24-bit buffer) and room for thousands of
    ## models a frame.
  TopDownBasis: Mat3 = [1'f32, 0, 0,  0, 0, 1,  0, 1, 0]
    ## model -> screen seen from above: up points at the viewer, the front at
    ## the bottom of the screen
  FrontBasis: Mat3 = [1'f32, 0, 0,  0, -1, 0,  0, 0, 1]
    ## model -> screen seen from the front (the desktop cube): up is up
  LookMaxBones = 128
    ## size of the look shader's bone array
  LookFS = """#version 330
in vec2 fragTexCoord;
in vec4 fragColor;
in vec3 fragNormal;
uniform sampler2D texture0;
uniform vec4 colDiffuse;
uniform vec4 lookTint;
uniform float lookLit;
out vec4 finalColor;
void main() {
  vec4 base = texture(texture0, fragTexCoord) * colDiffuse * fragColor * lookTint;
  if (base.a < 0.02) discard;
  float light = 1.0;
  float len = length(fragNormal);
  if (lookLit > 0.5 && len > 0.0001) {
    // key light from the upper left, toward the viewer: tops read bright
    float diff = max(dot(fragNormal / len, vec3(-0.35, -0.45, 0.82)), 0.0);
    light = 0.5 + 0.55 * diff;
  }
  finalColor = vec4(base.rgb * light, base.a);
}
"""

proc lookVertexShader(skinning: bool): string =
  result = """#version 330
in vec3 vertexPosition;
in vec2 vertexTexCoord;
in vec3 vertexNormal;
in vec4 vertexColor;
uniform mat4 mvp;
uniform mat4 lookNormal;
out vec2 fragTexCoord;
out vec4 fragColor;
out vec3 fragNormal;
"""
  if skinning:
    # raylib binds the bone attributes by these exact names
    result.add """in vec4 vertexBoneIndices;
in vec4 vertexBoneWeights;
uniform mat4 boneMatrices[""" & $LookMaxBones & """];
uniform int skinned;
"""
  result.add """void main() {
  vec4 pos = vec4(vertexPosition, 1.0);
  vec3 nrm = vertexNormal;
"""
  if skinning:
    result.add """  if (skinned != 0 && dot(vertexBoneWeights, vec4(1.0)) > 0.0) {
    mat4 skin = vertexBoneWeights.x * boneMatrices[int(vertexBoneIndices.x)]
              + vertexBoneWeights.y * boneMatrices[int(vertexBoneIndices.y)]
              + vertexBoneWeights.z * boneMatrices[int(vertexBoneIndices.z)]
              + vertexBoneWeights.w * boneMatrices[int(vertexBoneIndices.w)];
    pos = skin * pos;
    nrm = mat3(skin) * nrm;
  }
"""
  result.add """  fragTexCoord = vertexTexCoord;
  fragColor = vertexColor;
  fragNormal = mat3(lookNormal) * nrm;
  gl_Position = mvp * pos;
}
"""

type
  AnimTrack = object
    ## What one instance drew last, so an animation change can crossfade.
    ## Presentation only: never saved, and dropped when the instance stops
    ## being drawn.
    model: int             ## the model it drew (another model starts over)
    anim: int              ## animation shown (index + 1; 0 = the rest pose)
    frame: float32         ## the last frame of it drawn
    fromAnim: int          ## the animation fading out, held at fromFrame
    fromFrame: float32
    start, fade: float     ## wall clock the fade began; its length in seconds
    seen: float            ## wall clock of the last draw

  AnimView {.importc: "ModelAnimation", header: "raylib.h", completeStruct, bycopy.} = object
    ## A ModelAnimation looked at but not owned (naylib's frees its keyframes
    ## when it goes out of scope): what the crossfade hands raylib, including
    ## the one-keyframe rest clip built on the stack.
    name: array[32, char]
    boneCount: uint32
    keyframeCount: int32
    keyframePoses: ptr UncheckedArray[ModelAnimPose]

  SkeletonView {.importc: "ModelSkeleton", header: "raylib.h", completeStruct, bycopy.} = object
    boneCount: uint32
    bones: pointer
    bindPose: ModelAnimPose

proc updateModelAnimationBlend(model: Model, animA: AnimView, frameA: float32, animB: AnimView,
                               frameB, blend: float32) {.importc: "UpdateModelAnimationEx", header: "raylib.h".}

const
  NoAnimKey*: AnimKey = (0'u64, "")
  StaleTrack = 1.0  ## seconds undrawn before an instance's crossfade memory goes

var
  modModels: seq[ModModel]
  look: LookShader
  depthCursor = -DepthHalf
  animTracks: Table[AnimKey, AnimTrack]
  lastTrackPrune = 0.0

proc ensureLook() =
  ## Compile the model shader once (after the window exists). Without GPU
  ## skinning it retries without bones (models then hold their rest pose);
  ## if even that fails, models keep raylib's unlit default shader.
  if look.tried: return
  look.tried = true
  for skinning in [true, false]:
    var s = loadShaderFromMemory(lookVertexShader(skinning), LookFS)
    if s.id == 0 or s.id == getShaderIdDefault(): continue
    look.normal = getShaderLocation(s, "lookNormal")
    look.tint = getShaderLocation(s, "lookTint")
    look.lit = getShaderLocation(s, "lookLit")
    look.skinned = getShaderLocation(s, "skinned")
    look.bones = getShaderLocation(s, "boneMatrices")
    look.shader = move s
    look.ok = true
    look.skinning = skinning
    return

proc loadModModel*(path: string, err: var string): int =
  ## Load a 3D model with its animations (once per path). Returns the model
  ## id, 0 with `err` set on failure.
  for i in 0 ..< modModels.len:
    if modModels[i].path == path: return i + 1
  let ext = path.splitFile.ext.toLowerAscii
  if ext notin [".glb", ".gltf", ".obj", ".iqm", ".vox", ".m3d"]:
    err = "unsupported format (GLB, glTF, OBJ, IQM, VOX or M3D expected)"
    return 0
  ensureLook()
  var m = ModModel(path: path)
  try:
    m.model = loadModel(path)
  except CatchableError:
    err = "could not load the model (a damaged file, or no meshes in it)"
    return 0
  if look.ok:
    for i in 0 ..< m.model.materialCount:
      m.model.materials[i].shader = look.shader
  let box = getModelBoundingBox(m.model)
  m.size = Vector3(x: box.max.x - box.min.x, y: box.max.y - box.min.y, z: box.max.z - box.min.z)
  m.center = Vector3(x: (box.max.x + box.min.x) / 2, y: (box.max.y + box.min.y) / 2,
                     z: (box.max.z + box.min.z) / 2)
  m.radius = max(sqrt(m.size.x * m.size.x + m.size.y * m.size.y + m.size.z * m.size.z) / 2,
                 1.0e-6'f32)
  if ext in [".glb", ".gltf", ".iqm", ".m3d"] and m.model.skeleton.boneCount > 0:
    try:
      m.anims = loadModelAnimations(path)
    except CatchableError:
      discard                                   # no animations in the file
    for a in 0 ..< m.anims.len:
      # A skeleton that does not match would write past the bone arrays.
      if m.anims[a].keyframeCount > 0 and m.anims[a].boneCount > 0 and
         isModelAnimationValid(m.model, m.anims[a]):
        var name = ""
        for c in m.anims[a].name:
          if c == '\0': break
          name.add c
        m.animIdx.add a
        m.animNames.add name
        m.animFrames.add m.anims[a].keyframeCount.int
  modModels.add(move m)
  modModels.len

proc modelSize*(id: int): Vector3 =
  ## Bounding-box size in model units (x: width, y: height, z: length).
  if id <= 0 or id > modModels.len: Vector3() else: modModels[id - 1].size

proc modelAnimations*(id: int): seq[string] =
  if id > 0 and id <= modModels.len: modModels[id - 1].animNames else: @[]

proc modelAnimDuration*(id, anim: int): float32 =
  ## Seconds one loop of animation `anim` (index + 1) lasts.
  if id <= 0 or id > modModels.len or anim <= 0 or anim > modModels[id - 1].animFrames.len:
    0.0'f32
  else: (modModels[id - 1].animFrames[anim - 1].float / ModelFps).float32

proc modelAnimFrames*(id, anim: int): int =
  ## Frames in animation `anim` (index + 1); 1 when there is none.
  if id <= 0 or id > modModels.len or anim <= 0 or anim > modModels[id - 1].animFrames.len: 1
  else: modModels[id - 1].animFrames[anim - 1]

proc modelFrameAt*(id: int, pose: ModelPose, time: float): float32 =
  ## The frame animation pose.anim shows `time` seconds in (looping, scaled
  ## by pose.speed); -1 = no animation (the rest pose). Fractional: raylib 6
  ## blends the two keyframes around it, so a slowed animation or a fast
  ## monitor no longer steps at the 60 fps the keyframes were sampled at.
  if id <= 0 or id > modModels.len: return -1
  let m = addr modModels[id - 1]
  if pose.anim <= 0 or pose.anim > m.animFrames.len: return -1
  let frames = m.animFrames[pose.anim - 1]
  let t = time * pose.speed.float * ModelFps
  # A positive range test (not t != t): release builds use fast math, which may
  # drop a NaN self-comparison, and a bad frame would read past the poses.
  if not (abs(t) < 1.0e15): return 0
  clamp(floorMod(t, frames.float), 0.0, frames.float).float32

proc modelFootprint*(id: int): float32 =
  ## The model's size seen from above (the larger of its width and length):
  ## what gets fitted to a body's diameter.
  if id <= 0 or id > modModels.len: return 1
  let s = modModels[id - 1].size
  result = max(s.x, s.z)
  if result < 1.0e-6: result = max(s.y, 1.0e-6)

proc resetModelDepth*() =
  ## main.nim, right after the frame's clearBackground cleared the depth buffer.
  depthCursor = -DepthHalf

proc claimDepth(radius: float32): float32 =
  ## Depth (z) for the centre of a model `radius` deep, in front of every
  ## model drawn since the depth buffer was last cleared.
  let need = 2 * radius + 1
  if depthCursor + need > DepthHalf:
    # Out of room: clear the depth buffer alone (colour writes masked off).
    colorMask(false, false, false, false)
    clearScreenBuffers()
    colorMask(true, true, true, true)
    depthCursor = -DepthHalf
  result = depthCursor + radius
  depthCursor += need

func `*`(a, b: Mat3): Mat3 =
  for r in 0 .. 2:
    for c in 0 .. 2:
      result[r * 3 + c] = a[r * 3] * b[c] + a[r * 3 + 1] * b[3 + c] + a[r * 3 + 2] * b[6 + c]

func rotX(rad: float32): Mat3 = [1'f32, 0, 0,  0, cos(rad), -sin(rad),  0, sin(rad), cos(rad)]
func rotY(rad: float32): Mat3 = [cos(rad), 0, sin(rad),  0, 1, 0,  -sin(rad), 0, cos(rad)]
func rotZ(rad: float32): Mat3 = [cos(rad), -sin(rad), 0,  sin(rad), cos(rad), 0,  0, 0, 1'f32]

func toMatrix(l: Mat3, tx, ty, tz: float32): Matrix =
  Matrix(m0: l[0], m4: l[1], m8: l[2], m12: tx,
         m1: l[3], m5: l[4], m9: l[5], m13: ty,
         m2: l[6], m6: l[7], m10: l[8], m14: tz,
         m15: 1)

proc spinAngle(pose: ModelPose, time: float): float32 =
  floorMod(pose.spin.float * time, 360.0).float32

proc topDownRotation(pose: ModelPose, facingDeg: float32, time: float): Mat3 =
  ## Model -> screen for the arena's top-down view: tip/lean the model, stand
  ## it up toward the viewer, turn its front (screen-down unturned) to
  ## `facingDeg` (0 = right, 90 = down), then lean the camera back by the tilt.
  rotX(degToRad(pose.tilt)) *
    rotZ(degToRad(facingDeg - 90 + pose.yaw + spinAngle(pose, time))) *
    TopDownBasis * rotX(degToRad(pose.pitch)) * rotZ(degToRad(pose.roll))

proc animKey*(instance: pointer): AnimKey {.inline.} =
  ## An entity's own crossfade memory, keyed by its ref.
  (cast[uint64](instance), "")

proc animKey*(owner: pointer, name: string): AnimKey {.inline.} =
  ## A script's draw.model / draw3d.model `key`, kept apart per mod (`owner`
  ## is the mod's VM).
  (cast[uint64](owner), "k" & name)

proc uploadBones(m: var ModModel) =
  ## Hand the posed bone matrices to the look shader. raylib uploads them only
  ## in DrawModelEx, and models here draw mesh by mesh, so it is done before
  ## each draw: every body sharing a model keeps its own pose.
  let n = min(m.model.skeleton.boneCount.int, LookMaxBones)
  if n > 0 and look.bones.int32 >= 0:
    rlgl.enableShader(look.shader.id)
    rlgl.setUniformMatrices(look.bones.int32, m.model.boneMatrices[0], n.int32)

proc poseSkeleton(m: var ModModel, anim: int, frame: float32) =
  ## Pose the skeleton at `frame` of usable animation `anim` (index + 1). A
  ## fractional frame blends its two keyframes (the last one blends back into
  ## the first).
  updateModelAnimation(m.model, m.anims[m.animIdx[anim - 1]], frame)
  uploadBones(m)

proc poseSkeletonBlend(m: var ModModel, animA: int, frameA: float32,
                       animB: int, frameB, blend: float32) =
  ## Pose the skeleton `blend` of the way from animation `animA` at `frameA` to
  ## `animB` at `frameB` (index + 1). 0 is the rest pose: a one-keyframe clip
  ## of the skeleton's bind pose, built here on the stack (skinning a mesh with
  ## its bind pose leaves it exactly as drawn unskinned).
  var restPose = [cast[ptr SkeletonView](addr m.model.skeleton).bindPose]
  let rest = AnimView(boneCount: m.model.skeleton.boneCount, keyframeCount: 1,
                      keyframePoses: cast[ptr UncheckedArray[ModelAnimPose]](addr restPose))
  template clip(a: int): AnimView =
    if a > 0: cast[ptr AnimView](addr m.anims[m.animIdx[a - 1]])[] else: rest
  # Outside 0..1 raylib skips the update and the last draw's bones would stay.
  updateModelAnimationBlend(m.model, clip(animA), max(frameA, 0.0'f32),
                            clip(animB), max(frameB, 0.0'f32), clamp(blend, 0.0'f32, 1.0'f32))
  uploadBones(m)

proc fadeWeight(t: AnimTrack, now: float): float32 =
  ## How much of t.anim is on screen (1 = the fade is over), eased in and out.
  if t.fade <= 0: return 1
  let x = clamp((now - t.start) / t.fade, 0.0, 1.0).float32
  x * x * (3 - 2 * x)

proc crossfade(id: int, key: AnimKey, anim: int, frame, fade: float32):
               tuple[fromAnim: int, fromFrame, weight: float32] =
  ## Note that instance `key` draws animation `anim` (0 = the rest pose) of
  ## model `id` at `frame`, and say how far its crossfade has come. A switch
  ## fades from what was on screen, held at the frame it showed, into the new
  ## animation playing on; a switch during a fade starts from whichever of the
  ## two dominated.
  let now = getTime()
  if now - lastTrackPrune > StaleTrack:
    lastTrackPrune = now
    var stale: seq[AnimKey]
    for k, t in animTracks:
      if now - t.seen > StaleTrack: stale.add k
    for k in stale: animTracks.del k
  let t = addr animTracks.mgetOrPut(key, AnimTrack(model: id, anim: anim, start: -1.0e9))
  if t.model != id or now - t.seen > StaleTrack:
    # A new instance, or one long undrawn: its ref may belong to another now.
    t[] = AnimTrack(model: id, anim: anim, start: -1.0e9)
  elif anim != t.anim:
    if fadeWeight(t[], now) >= 0.5:
      t.fromAnim = t.anim
      t.fromFrame = t.frame
    t.anim = anim
    t.start = now
    t.fade = fade
  t.frame = frame
  t.seen = now
  (t.fromAnim, t.fromFrame, fadeWeight(t[], now))

proc poseModel(m: var ModModel, id: int, key: AnimKey, pose: ModelPose, frame: float32): bool =
  ## Pose model `id` for one draw at `frame` of pose.anim (-1: the rest pose);
  ## true when it is to be drawn skinned. An instance with a key crossfades
  ## when its animation changes.
  if not look.skinning: return false
  let anim = if frame >= 0 and pose.anim in 1 .. m.animIdx.len: pose.anim else: 0
  if key.owner != 0 and m.animIdx.len > 0:
    let (fromAnim, fromFrame, weight) = crossfade(id, key, anim, frame, pose.fade)
    if weight < 1 and fromAnim in 0 .. m.animIdx.len and (fromAnim > 0 or anim > 0):
      poseSkeletonBlend(m, fromAnim, fromFrame, anim, frame, weight)
      return true
  if anim > 0:
    poseSkeleton(m, anim, frame)
    return true
  false

proc drawModelPosed(id: int, x, y, pxPerUnit: float32, rot: Mat3, pose: ModelPose,
                    tint: Color, frame: float32, key = NoAnimKey) =
  ## Model `id` with its bounding-box centre on (x, y): `rot` turns model
  ## space into screen space and `pxPerUnit` scales it. `frame` is the frame of
  ## animation pose.anim to show (-1: the rest pose). With a `key` the
  ## instance crossfades when its animation changes.
  if id <= 0 or id > modModels.len or not (pxPerUnit > 0 and pxPerUnit < 1.0e6): return
  let m = addr modModels[id - 1]
  let z = claimDepth(min(m.radius * pxPerUnit, DepthHalf / 2))
  var l = rot
  for v in l.mitems: v *= pxPerUnit
  let c = m.center
  let transform = toMatrix(l, x - (l[0] * c.x + l[1] * c.y + l[2] * c.z),
                              y - (l[3] * c.x + l[4] * c.y + l[5] * c.z),
                              z - (l[6] * c.x + l[7] * c.y + l[8] * c.z))
  drawRenderBatchActive()   # the 2D drawn so far goes under the model
  let saved = getMatrixProjection()
  var proj = saved          # same x/y mapping, z in [-DepthHalf, DepthHalf]
  proj.m2 = 0
  proj.m6 = 0
  proj.m10 = -1'f32 / DepthHalf
  proj.m14 = 0
  setMatrixProjection(proj)
  enableDepthTest()
  enableDepthMask()
  disableBackfaceCulling()  # tolerate models exported with mixed windings
  let t = Color(r: uint8(pose.tint.r.int * tint.r.int div 255), g: uint8(pose.tint.g.int * tint.g.int div 255),
                b: uint8(pose.tint.b.int * tint.b.int div 255), a: uint8(pose.tint.a.int * tint.a.int div 255))
  if look.ok:
    # `rot` is orthonormal, so it is its own normal matrix (inverse transpose).
    setShaderValueMatrix(look.shader, look.normal, toMatrix(rot, 0, 0, 0))
    setShaderValue(look.shader, look.tint, [t.r.float32 / 255, t.g.float32 / 255,
                                            t.b.float32 / 255, t.a.float32 / 255])
    setShaderValue(look.shader, look.lit, (if pose.lit: 1'f32 else: 0'f32))
  let skin = poseModel(m[], id, key, pose, frame)
  for i in 0 ..< m.model.meshCount:
    if look.skinning:
      setShaderValue(look.shader, look.skinned, int32(skin and m.model.meshes[i].boneCount > 0))
    drawMesh(m.model.meshes[i], m.model.materials[m.model.meshMaterial[i]], transform)
  enableBackfaceCulling()
  disableDepthTest()
  setMatrixProjection(saved)

proc drawModModel*(id: int, x, y, pxPerUnit, facingDeg: float32, pose: ModelPose, frame: float32,
                   key = NoAnimKey) =
  ## draw.model: model `id` centred on (x, y), `pxPerUnit` pixels per model
  ## unit, its front turned to `facingDeg` (screen degrees, 90 = down).
  drawModelPosed(id, x, y, pxPerUnit, topDownRotation(pose, facingDeg, getTime()), pose,
                 White, frame, key)

proc drawModelIcon*(id: int, x, y, size: float32, pose: ModelPose) =
  ## A model shown as a turntable in a `size` box (MODS.EXE previews): its
  ## bounding sphere fits the box, so it never pokes out while it turns.
  if id <= 0 or id > modModels.len: return
  var p = pose
  if p.tilt == 0: p.tilt = 30
  let now = getTime()
  drawModelPosed(id, x, y, size / (2 * modModels[id - 1].radius),
                 topDownRotation(p, 90 + floorMod(now * 60.0, 360.0).float32, now), p, White,
                 modelFrameAt(id, p, now))

proc drawModelWorld3D*(id: int, x, y, z, scale, yawDeg, pitchDeg, rollDeg: float32,
                       pose: ModelPose, tint: Color, time: float, key = NoAnimKey) =
  ## A real 3D draw for the 3D worlds (game3d/): call it between beginMode3D
  ## and endMode3D. Unlike the 2D-embedded path above it keeps the camera's own
  ## projection and depth buffer, so the model sits in the scene like any mesh.
  ## The bounding-box centre lands on (x, y, z); `scale` is world units per
  ## model unit; angles in degrees (yaw about the up axis, then pitch and roll;
  ## pose.spin keeps adding to the yaw). pose.anim/speed pick the animation
  ## frame at `time`, pose.lit toggles the scene light, pose.tint multiplies
  ## `tint`. Models are +Y up with their front on +Z. With a `key` the
  ## instance crossfades when its animation changes.
  if id <= 0 or id > modModels.len or not (scale > 0 and scale < 1.0e6): return
  let m = addr modModels[id - 1]
  # rotation (row-major): yaw about Y, then tip (X) and lean (Z) the model
  let rot = rotY(degToRad(yawDeg + spinAngle(pose, time))) * rotX(degToRad(pitchDeg)) *
            rotZ(degToRad(rollDeg))
  var l = rot
  for v in l.mitems: v *= scale
  let c = m.center
  let transform = toMatrix(l, x - (l[0] * c.x + l[1] * c.y + l[2] * c.z),
                              y - (l[3] * c.x + l[4] * c.y + l[5] * c.z),
                              z - (l[6] * c.x + l[7] * c.y + l[8] * c.z))
  drawRenderBatchActive()   # what the scene drew so far goes under the model
  disableBackfaceCulling()  # tolerate models exported with mixed windings
  let t = Color(r: uint8(pose.tint.r.int * tint.r.int div 255), g: uint8(pose.tint.g.int * tint.g.int div 255),
                b: uint8(pose.tint.b.int * tint.b.int div 255), a: uint8(pose.tint.a.int * tint.a.int div 255))
  if look.ok:
    # The shader lights in view space with y down (the 2D convention): take the
    # normals into the camera's frame and flip y.
    let v = getMatrixModelview()
    let view: Mat3 = [v.m0, v.m4, v.m8,  -v.m1, -v.m5, -v.m9,  v.m2, v.m6, v.m10]
    setShaderValueMatrix(look.shader, look.normal, toMatrix(view * rot, 0, 0, 0))
    setShaderValue(look.shader, look.tint, [t.r.float32 / 255, t.g.float32 / 255,
                                            t.b.float32 / 255, t.a.float32 / 255])
    setShaderValue(look.shader, look.lit, (if pose.lit: 1'f32 else: 0'f32))
  let skin = poseModel(m[], id, key, pose, modelFrameAt(id, pose, time))
  for i in 0 ..< m.model.meshCount:
    if look.skinning:
      setShaderValue(look.shader, look.skinned, int32(skin and m.model.meshes[i].boneCount > 0))
    drawMesh(m.model.meshes[i], m.model.materials[m.model.meshMaterial[i]], transform)
  enableBackfaceCulling()

proc unloadModModels() =
  ## Models before their shader, and the textures their materials loaded
  ## (UnloadModel leaves those to the caller).
  let defaultTex = getTextureIdDefault()
  var seen: seq[uint32]
  for m in modModels.mitems:
    for i in 0 ..< m.model.materialCount:
      for mi in MaterialMapIndex:
        let tid = m.model.materials[i].maps[mi].texture.id
        if tid != 0 and tid != defaultTex and tid notin seen:
          seen.add tid
          rlgl.unloadTexture(tid)
  modModels.setLen(0)
  animTracks.clear()   # model ids are reused by the next load
  look = LookShader()

proc textureSize*(id: int): tuple[w, h: int] =
  if id <= 0 or id > modTextures.len: return (0, 0)
  if modTextures[id - 1].video > 0: return videoSize(modTextures[id - 1].video)
  (modTextures[id - 1].frames[0].width.int, modTextures[id - 1].frames[0].height.int)

proc textureFrames*(id: int): int =
  ## Frames of texture `id`: 1 for a still image or a video, 0 for no texture.
  if id <= 0 or id > modTextures.len: 0
  elif modTextures[id - 1].video > 0: 1
  else: modTextures[id - 1].frames.len

proc textureDuration*(id: int): float32 =
  ## One loop of an animated texture, in seconds (0 for a still image).
  if id <= 0 or id > modTextures.len or modTextures[id - 1].ends.len == 0: 0.0'f32
  else: modTextures[id - 1].ends[^1]

proc textureFrameAt*(id: int, time: float): int =
  ## The frame (0-based) an animated texture shows `time` seconds into its
  ## animation, which loops. Always 0 for a still image or a video.
  if id <= 0 or id > modTextures.len: 0 else: textureFrameAtImpl(modTextures[id - 1], time)

proc markActive*() =
  modTexturesActive = true

proc unloadModAssets*() =
  ## Drop every mod texture, video, music, font, model, replacement, cosmetic
  ## and sound override.
  modTextures.setLen(0)
  unloadModMedia()
  modFonts.setLen(0)
  modShaders.setLen(0)
  screenShader = 0
  gameShader = 0
  for s in modSounds.mitems: s.voices.setLen(0)   # aliases before their source
  modSounds.setLen(0)
  unloadModModels()
  playerTex = BodyReplace()
  for et in EnemyType: enemyTex[et] = BodyReplace()
  bossTex.clear()
  bulletTex = [BodyReplace(), BodyReplace()]
  for pt in PowerUpType: powerUpTex[pt] = BodyReplace()
  boss3dTex = BodyReplace()
  satellite3dTex = BodyReplace()
  entity3dTex.clear()
  projectile3dTex = [BodyReplace(), BodyReplace()]
  pickup3dTex.clear()
  desktopTex = BodyReplace()
  desktopCube = false
  cubeModel = BodyReplace()
  playerHeading.clear()
  modCosmetics.setLen(0)
  for k in ModCosmeticKind: equippedCosmetic[k] = 0
  modTexturesActive = false
  restoreVanillaSounds()

# ------------------------------------------------------------------ drawing ----
proc drawModTexture*(id: int, x, y, w, h, rotationDeg: float32, tint: Color,
                     centered = true, frame = -1) =
  ## Draw texture `id` into a w x h box at (x, y) (its centre when `centered`).
  ## An animated GIF plays on the wall clock, like the game's own animated
  ## bodies, unless `frame` (0-based) picks one; a video shows its picture.
  if id <= 0 or id > modTextures.len: return
  let t = frameTexture(id, getTime(), frame)
  let src = Rectangle(x: 0, y: 0, width: t.width.float32, height: t.height.float32)
  if centered:
    drawTexture(t[], src, Rectangle(x: x, y: y, width: w, height: h),
                Vector2(x: w / 2, y: h / 2), rotationDeg, tint)
  else:
    drawTexture(t[], src, Rectangle(x: x, y: y, width: w, height: h), Vector2(x: 0, y: 0),
                rotationDeg, tint)

proc drawReplacement*(r: BodyReplace, x, y, diameter, angleDeg: float32,
                      tint: Color = White, animPhase = 0.0, key = NoAnimKey) =
  ## A replacement body, centred. A texture is fitted into the diameter
  ## (aspect kept). A model's footprint (seen from above) is fitted to it, its
  ## front turned to `angleDeg` when it rotates (else facing the bottom of the
  ## screen); `animPhase` offsets its animation clock in seconds, and a `key`
  ## (the body's own) lets it crossfade when its animation changes.
  let size = diameter * (if r.scale > 0: r.scale else: 1.0'f32)
  if r.model > 0:
    let now = getTime()
    drawModelPosed(r.model, x, y, size / modelFootprint(r.model),
                   topDownRotation(r.pose, (if r.rotate: angleDeg else: 90.0'f32), now),
                   r.pose, tint, modelFrameAt(r.model, r.pose, now + animPhase), key)
    return
  let (tw, th) = textureSize(r.id)
  if tw <= 0 or th <= 0: return
  let aspect = tw.float32 / th.float32
  let (w, h) = if aspect >= 1.0: (size, size / aspect) else: (size * aspect, size)
  drawModTexture(r.id, x, y, w, h, (if r.rotate: angleDeg else: 0.0'f32), tint)

proc hasLook*(r: BodyReplace): bool {.inline.} = r.id > 0 or r.model > 0

proc drawBodyWorld3D*(r: BodyReplace, cam: Camera, x, y, z, diameter, yawDeg: float32,
                      time: float, tint: Color = White, key = NoAnimKey) =
  ## A replacement body inside a 3D camera (the 3D worlds): a model stands in
  ## the scene, fitted so its footprint is `diameter` (times r.scale) wide and
  ## turned to `yawDeg` when it rotates (a `key` lets it crossfade when its
  ## animation changes); a texture is a billboard facing `cam`.
  let size = diameter * (if r.scale > 0: r.scale else: 1.0'f32)
  if r.model > 0:
    drawModelWorld3D(r.model, x, y, z, size / modelFootprint(r.model),
                     r.pose.yaw + (if r.rotate: yawDeg else: 0.0'f32), r.pose.pitch, r.pose.roll,
                     r.pose, tint, time, key)
  elif r.id > 0 and r.id <= modTextures.len:
    drawBillboard(cam, frameTexture(r.id, time)[], Vector3(x: x, y: y, z: z), size, tint)

proc drawTextureBillboard*(id: int, cam: Camera, x, y, z, size: float32, tint: Color,
                           frame = -1) =
  ## draw3d.billboard: texture `id` (a GIF plays on the wall clock unless
  ## `frame`, 0-based, picks one) facing the camera, `size` world units tall
  ## (raylib keeps it upright and sizes the width from the aspect).
  if id <= 0 or id > modTextures.len: return
  drawBillboard(cam, frameTexture(id, getTime(), frame)[], Vector3(x: x, y: y, z: z), size, tint)

proc drawTexturePanel*(id: int, x, y, z, w, h, yawDeg, pitchDeg, rollDeg: float32, tint: Color,
                       frame = -1) =
  ## draw3d.texture: texture `id` as a flat picture fixed in the world (a
  ## sign, a screen, a poster, a floor decal), centred on x, y, z and `w` x `h`
  ## world units. Unturned it stands upright with its front on +Z; the angles
  ## turn it like drawModelWorld3D turns a model (yaw about the up axis, then
  ## pitch and roll). Both sides show the picture the right way round, unlit.
  ## A GIF plays on the wall clock unless `frame` (0-based) picks one.
  if id <= 0 or id > modTextures.len: return
  let tex = frameTexture(id, getTime(), frame)
  let r = rotY(degToRad(yawDeg)) * rotX(degToRad(pitchDeg)) * rotZ(degToRad(rollDeg))
  # The rotated x and y axes, scaled to the half edges, and the facing.
  let hw = w / 2
  let hh = h / 2
  let rx = [r[0] * hw, r[3] * hw, r[6] * hw]
  let uy = [r[1] * hh, r[4] * hh, r[7] * hh]
  template corner(sr, su, u, v: float32) =
    texCoord2f(u, v)
    vertex3f(x + sr * rx[0] + su * uy[0], y + sr * rx[1] + su * uy[1], z + sr * rx[2] + su * uy[2])
  setTexture(tex.id)
  rlBegin(Quads)
  color4ub(tint.r, tint.g, tint.b, tint.a)
  # Front, counter-clockwise seen from the facing side (culling keeps one side
  # per view, so the two never fight).
  normal3f(r[2], r[5], r[8])
  corner(-1, 1, 0, 0)
  corner(-1, -1, 0, 1)
  corner(1, -1, 1, 1)
  corner(1, 1, 1, 0)
  # Back: mirrored across the panel, so it reads the right way round from behind.
  normal3f(-r[2], -r[5], -r[8])
  corner(1, 1, 0, 0)
  corner(1, -1, 0, 1)
  corner(-1, -1, 1, 1)
  corner(-1, 1, 1, 0)
  rlEnd()
  setTexture(0)

proc cosmeticAt(idx: int): ptr ModCosmetic {.inline.} =
  if idx > 0 and idx <= modCosmetics.len: addr modCosmetics[idx - 1] else: nil

proc playerPalette*(p: Player, primary, secondary, core: var Color) =
  ## An equipped mod player skin's colours replace the built-in skin's.
  let c = cosmeticAt(p.modSkin.int)
  if not c.isNil and c.kind == mckPlayer and c.hasPalette:
    primary = c.c1
    secondary = c.c2
    core = c.c3

proc drawPlayerModBody*(p: Player, tint: Color): bool =
  ## True when a texture or model drew the player's body (skin, else a mod's
  ## override.texture / override.model("player")).
  if not modTexturesActive: return false
  var r = BodyReplace()
  let c = cosmeticAt(p.modSkin.int)
  if not c.isNil and c.kind == mckPlayer and c.look.hasLook: r = c.look
  elif playerTex.hasLook: r = playerTex
  if not r.hasLook: return false
  # A body that turns keeps facing the way it last moved once the player stops.
  let key = cast[pointer](p)
  if p.vel.x != 0 or p.vel.y != 0:
    playerHeading[key] = radToDeg(arctan2(p.vel.y, p.vel.x))
  drawReplacement(r, p.pos.x, p.pos.y, p.radius * 2.0'f32, playerHeading.getOrDefault(key), tint,
                  key = animKey(key))
  true

proc bulletCosmetic(): ptr ModCosmetic {.inline.} =
  cosmeticAt(if pvpDrawing: pvpBulletCosmetic else: equippedCosmetic[mckBullet])

proc bulletPalette*(fromPlayerLook: bool, primary, glow, trail: var Color) =
  if not fromPlayerLook: return
  let c = bulletCosmetic()
  if not c.isNil and c.hasPalette:
    primary = c.c1
    glow = c.c2
    trail = c.c3

proc drawBulletModBody*(b: Bullet, playerLook: bool): bool =
  if not modTexturesActive: return false
  var r = BodyReplace()
  if playerLook:
    let c = bulletCosmetic()
    if not c.isNil and c.look.hasLook: r = c.look
  if not r.hasLook: r = bulletTex[playerLook]
  if not r.hasLook: return false
  drawReplacement(r, b.pos.x, b.pos.y, b.radius * 2.0'f32, radToDeg(arctan2(b.vel.y, b.vel.x)))
  true

proc drawEnemyModBody*(e: Enemy): bool =
  if not modTexturesActive: return false
  let r = if e.isBoss: bossTex.getOrDefault(e.bossDefinitionID) else: enemyTex[e.enemyType]
  if not r.hasLook: return false
  let tint = if e.hitFlashTimer > 0: Color(r: 255, g: 200, b: 200, a: 255) else: White
  # Each enemy starts its model's animation at its own point (golden-ratio
  # steps spread any count evenly), so a crowd does not march in step.
  drawReplacement(r, e.pos.x, e.pos.y, e.radius * 2.0'f32, radToDeg(e.rotation), tint,
                  animPhase = e.id.float * 0.618, key = animKey(cast[pointer](e)))
  true

proc drawPowerUpModIcon*(x, y, size: int32, pt: PowerUpType): bool =
  if not modTexturesActive or not powerUpTex[pt].hasLook: return false
  let s = size.float32
  drawReplacement(powerUpTex[pt], x.float32 + s / 2, y.float32 + s / 2, s, 0)
  true

proc cubeLook(): BodyReplace =
  ## The model standing in for the desktop cube: an equipped cube cosmetic,
  ## then a legacy desktop cosmetic, else override.model("cube").
  let cube = cosmeticAt(equippedCosmetic[mckCube])
  if not cube.isNil and cube.look.model > 0:
    return cube.look
  let desktop = cosmeticAt(equippedCosmetic[mckDesktop])
  if not desktop.isNil and desktop.look.model > 0:
    return desktop.look
  cubeModel

proc modWallpaper*(): tuple[id: int, cube: bool] =
  ## The mod wallpaper covering the desktop: an equipped desktop cosmetic, else
  ## override.texture("desktop"). id 0 = none (the built-in background shows).
  ## A cube cosmetic is independent of the wallpaper and is shown whenever it
  ## supplies a model; legacy desktop cosmetics may still keep the cube with
  ## `cube = true`.
  if not modTexturesActive: return (0, false)
  let cubeModelShown = cubeLook().model > 0
  let c = cosmeticAt(equippedCosmetic[mckDesktop])
  if not c.isNil and c.look.id > 0: return (c.look.id, c.cube or cubeModelShown)
  if desktopTex.id > 0: return (desktopTex.id, desktopCube or cubeModelShown)
  (0, false)

proc drawCubeModModel*(cx, cy, halfSize, angleX, angleY, angleZ: float32): bool =
  ## The desktop cube (and the orbital cube it becomes) as a mod's model,
  ## turned exactly like the cube: its X, then Y, then Z rotation (radians).
  ## `halfSize` is the cube's half-width. False = no model: draw the cube.
  if not modTexturesActive: return false
  let r = cubeLook()
  if r.model <= 0 or r.model > modModels.len: return false
  let now = getTime()
  let p = r.pose
  let rot = rotZ(angleZ) * rotY(angleY) * rotX(angleX) * FrontBasis *
            rotY(degToRad(p.yaw + spinAngle(p, now))) * rotX(degToRad(p.pitch)) *
            rotZ(degToRad(p.roll))
  let scale = if r.scale > 0: r.scale else: 1.0'f32
  # The bounding sphere matches the cube's reach (between its half-width and
  # its corners), so any model tumbles as big as the cube did.
  drawModelPosed(r.model, cx, cy, halfSize * 1.5'f32 * scale / modModels[r.model - 1].radius,
                 rot, p, White, modelFrameAt(r.model, p, now))
  true

proc drawDesktopModBackground*(w, h: int32): bool =
  ## The mod wallpaper (modWallpaper) fills the viewport from its top-left
  ## corner without repositioning the image.
  let id = modWallpaper().id
  if id == 0: return false
  drawModTexture(id, 0, 0, w.float32, h.float32, 0, White, centered = false)
  true

# ----------------------------------------------------------------- equipping ----
proc cosmeticIndex*(kind: ModCosmeticKind, key: string): int =
  for i, c in modCosmetics:
    if c.kind == kind and c.key == key: return i + 1
  0

proc noteEquippedTextures() =
  ## The draw helpers bail out early unless some texture or model is in play,
  ## so an equipped cosmetic with one has to switch that on (and it must happen
  ## on every equip, not only at load: MODS.EXE equips mid-session).
  for k in ModCosmeticKind:
    if equippedCosmetic[k] > 0 and modCosmetics[equippedCosmetic[k] - 1].look.hasLook:
      modTexturesActive = true

proc applyEquippedCosmetics*(entries: seq[string]) =
  ## Settings.modCosmetics holds "kind=<mod id>:<id>" per equipped kind. A key
  ## whose mod is not loaded is simply not applied (and stays saved).
  for k in ModCosmeticKind: equippedCosmetic[k] = 0
  for e in entries:
    let eq = e.find('=')
    if eq <= 0: continue
    let kindName = e[0 ..< eq]
    for k in ModCosmeticKind:
      if $k == kindName:
        equippedCosmetic[k] = cosmeticIndex(k, e[eq + 1 .. ^1])
  noteEquippedTextures()

proc toggleCosmetic*(idx: int) =
  ## MODS.EXE's Equip / Unequip button for cosmetic `idx` (0-based).
  if idx < 0 or idx >= modCosmetics.len: return
  let kind = modCosmetics[idx].kind
  equippedCosmetic[kind] = if equippedCosmetic[kind] == idx + 1: 0 else: idx + 1
  noteEquippedTextures()

proc equippedEntries*(): seq[string] =
  for k in ModCosmeticKind:
    let c = cosmeticAt(equippedCosmetic[k])
    if not c.isNil: result.add($k & "=" & c.key)
