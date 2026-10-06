## Built-in post-processing (Settings > Graphics > Visual effects).
##
## Runs over the finished virtual frame in `endGameDrawing` (main.nim), so it
## covers the desktop, every window, the arena and the 3D worlds alike:
##
## 1. Prefilter: the frame is shrunk to a quarter of the virtual resolution,
##    keeping only what is brighter than a soft threshold. Every destination
##    texel averages a 4x4 grid of bilinear taps over its whole footprint, so a
##    thin bullet or a 1px line can't flicker in and out of the glow as it moves.
## 2. Blur: a separable Gaussian at 1/4, then again at 1/8 for the wide halo.
## 3. Composite (on the final blit): the two glow levels are screen-blended
##    over the frame (never pushing a channel past 1, so unglowing pixels keep
##    their exact colour), then a light saturation/contrast grade, a vignette,
##    a faint chromatic fringe at the edges (Full only) and a 1/255 dither that
##    keeps the soft glow from banding.
##
## A mod's post-process shader (mod_assets.beginPostShader) still runs last:
## the composite then goes to an intermediate target the mod shader reads.
## If any shader fails to compile the pass switches itself off for the session.

import raylib, rlgl
from save_system import PostFxLevel, pfxOff, pfxSubtle, pfxFull

const
  VS = """#version 330
in vec3 vertexPosition;
in vec2 vertexTexCoord;
in vec4 vertexColor;
uniform mat4 mvp;
out vec2 fragTexCoord;
out vec4 fragColor;
void main() {
  fragTexCoord = vertexTexCoord;
  fragColor = vertexColor;
  gl_Position = mvp * vec4(vertexPosition, 1.0);
}
"""

  PrefilterFS = """#version 330
in vec2 fragTexCoord;
uniform sampler2D texture0;
uniform vec2 footprint;   // one destination texel, in source uv
uniform float threshold;
uniform float knee;
out vec4 finalColor;
vec3 bright(vec2 uv) {
  vec4 t = texture(texture0, uv);
  vec3 c = t.rgb * t.a;   // the frame is shown over black: premultiply
  float br = max(c.r, max(c.g, c.b));
  float soft = clamp(br - threshold + knee, 0.0, 2.0 * knee);
  soft = soft * soft / (4.0 * knee + 1e-4);
  float w = max(soft, br - threshold) / max(br, 1e-4);
  // Neon glows, plain white (text, window chrome) only a little.
  float sat = (br - min(c.r, min(c.g, c.b))) / max(br, 1e-4);
  return c * w * mix(0.45, 1.0, sat);
}
void main() {
  vec3 sum = vec3(0.0);
  for (int y = 0; y < 4; y++)
    for (int x = 0; x < 4; x++)
      sum += bright(fragTexCoord + (vec2(x, y) - 1.5) * 0.25 * footprint);
  finalColor = vec4(sum / 16.0, 1.0);
}
"""

  BlurFS = """#version 330
in vec2 fragTexCoord;
uniform sampler2D texture0;
uniform vec2 dir;   // one texel along the blur axis, in uv
out vec4 finalColor;
void main() {
  // 9-tap Gaussian folded into 5 bilinear taps.
  vec3 c = texture(texture0, fragTexCoord).rgb * 0.2270270270;
  vec2 o1 = dir * 1.3846153846;
  vec2 o2 = dir * 3.2307692308;
  c += (texture(texture0, fragTexCoord + o1).rgb + texture(texture0, fragTexCoord - o1).rgb) * 0.3162162162;
  c += (texture(texture0, fragTexCoord + o2).rgb + texture(texture0, fragTexCoord - o2).rgb) * 0.0702702703;
  finalColor = vec4(c, 1.0);
}
"""

  CompositeFS = """#version 330
in vec2 fragTexCoord;
uniform sampler2D texture0;
uniform sampler2D bloomNear;
uniform sampler2D bloomWide;
uniform vec2 resolution;
uniform float time;
uniform float bloomStrength;
uniform float saturation;
uniform float contrast;
uniform float vignette;
uniform float aberration;
out vec4 finalColor;
vec3 frame(vec2 uv) { vec4 t = texture(texture0, uv); return t.rgb * t.a; }
void main() {
  vec2 uv = fragTexCoord;
  vec2 d = uv - 0.5;
  vec3 col;
  if (aberration > 0.0) {
    vec2 off = d * dot(d, d) * aberration;   // zero at the centre, grows outward
    col = vec3(frame(uv + off).r, frame(uv).g, frame(uv - off).b);
  } else {
    col = frame(uv);
  }
  vec3 glow = (texture(bloomNear, uv).rgb * 1.1 + texture(bloomWide, uv).rgb * 1.4) * bloomStrength;
  col = 1.0 - (1.0 - col) * (1.0 - clamp(glow, 0.0, 1.0));
  float l = dot(col, vec3(0.2126, 0.7152, 0.0722));
  col = clamp(mix(vec3(l), col, saturation), 0.0, 1.0);
  col = mix(col, col * col * (3.0 - 2.0 * col), contrast);
  col *= 1.0 - vignette * pow(length(d) * 1.41421356, 2.5);
  float n = fract(sin(dot(uv * resolution + fract(time) * 61.0, vec2(12.9898, 78.233))) * 43758.5453);
  col += (n - 0.5) / 255.0;
  finalColor = vec4(col, 1.0);
}
"""

type Params = object
  bloom, saturation, contrast, vignette, aberration: float32

proc paramsFor(level: PostFxLevel): Params =
  case level
  of pfxOff: Params()
  of pfxSubtle: Params(bloom: 0.6, saturation: 1.04, contrast: 0.05, vignette: 0.14, aberration: 0.0)
  of pfxFull: Params(bloom: 1.0, saturation: 1.10, contrast: 0.12, vignette: 0.24, aberration: 0.004)

var
  tried, broken: bool
  prefilter, blur, composite: Shader
  locFootprint, locThreshold, locKnee, locDir: ShaderLocation
  locNear, locWide, locRes, locTime, locBloom, locSat, locContrast, locVignette, locAberration: ShaderLocation
  nearA, nearB, wideA, wideB: RenderTexture2D   # ping-pong pairs at 1/4 and 1/8
  composed: RenderTexture2D                     # only when a mod shader runs after us
  builtW, builtH, composedW, composedH: int32

proc compile(fs: string, ok: var bool): Shader =
  result = loadShaderFromMemory(VS, fs)
  if result.id == 0 or result.id == getShaderIdDefault(): ok = false

proc load(): bool =
  if tried: return not broken
  tried = true
  var ok = true
  prefilter = compile(PrefilterFS, ok)
  blur = compile(BlurFS, ok)
  composite = compile(CompositeFS, ok)
  broken = not ok
  if broken:
    traceLog(Warning, "POSTFX: a shader did not compile; visual effects are off")
    return false
  locFootprint = getShaderLocation(prefilter, "footprint")
  locThreshold = getShaderLocation(prefilter, "threshold")
  locKnee = getShaderLocation(prefilter, "knee")
  locDir = getShaderLocation(blur, "dir")
  locNear = getShaderLocation(composite, "bloomNear")
  locWide = getShaderLocation(composite, "bloomWide")
  locRes = getShaderLocation(composite, "resolution")
  locTime = getShaderLocation(composite, "time")
  locBloom = getShaderLocation(composite, "bloomStrength")
  locSat = getShaderLocation(composite, "saturation")
  locContrast = getShaderLocation(composite, "contrast")
  locVignette = getShaderLocation(composite, "vignette")
  locAberration = getShaderLocation(composite, "aberration")
  true

proc makeTarget(w, h: int32): RenderTexture2D =
  result = loadRenderTexture(w, h)
  setTextureFilter(result.texture, Bilinear)
  setTextureWrap(result.texture, Clamp)

proc ensureTargets(virtualW, virtualH: int32) =
  let w = max(virtualW div 4, 2)
  let h = max(virtualH div 4, 2)
  if w == builtW and h == builtH: return
  nearA = makeTarget(w, h)
  nearB = makeTarget(w, h)
  wideA = makeTarget(max(w div 2, 1), max(h div 2, 1))
  wideB = makeTarget(max(w div 2, 1), max(h div 2, 1))
  builtW = w
  builtH = h

proc pass(src: Texture2D, dst: RenderTexture2D) =
  ## Draw all of `src` over all of `dst` with whatever shader is active.
  ## Render textures hold their picture upside down, so the source is flipped,
  ## exactly like the final blit to the screen.
  beginTextureMode(dst)
  clearBackground(Black)
  drawTexture(src, Rectangle(x: 0, y: 0, width: src.width.float32, height: -src.height.float32),
              Rectangle(x: 0, y: 0, width: dst.texture.width.float32, height: dst.texture.height.float32),
              Vector2(x: 0, y: 0), 0, White)
  endTextureMode()

proc blurPair(a, b: RenderTexture2D) =
  ## Blur `a` in place (via `b`): horizontal into b, vertical back into a.
  let tw = 1.0'f32 / a.texture.width.float32
  let th = 1.0'f32 / a.texture.height.float32
  beginShaderMode(blur)
  setShaderValue(blur, locDir, [tw, 0.0'f32])
  pass(a.texture, b)
  setShaderValue(blur, locDir, [0.0'f32, th])
  pass(b.texture, a)
  endShaderMode()

proc postFxEnabled*(level: PostFxLevel): bool =
  level != pfxOff and load()

proc preparePostFx*(frame: Texture2D, virtualW, virtualH: int32) =
  ## Builds this frame's glow from the finished frame. Call outside any
  ## drawing (after endTextureMode, before beginDrawing).
  ensureTargets(virtualW, virtualH)
  beginShaderMode(prefilter)
  setShaderValue(prefilter, locFootprint,
                 [1.0'f32 / nearA.texture.width.float32, 1.0'f32 / nearA.texture.height.float32])
  setShaderValue(prefilter, locThreshold, 0.55'f32)
  setShaderValue(prefilter, locKnee, 0.25'f32)
  pass(frame, nearA)
  endShaderMode()
  blurPair(nearA, nearB)
  pass(nearA.texture, wideA)   # bilinear 2:1 shrink of the already-blurred glow
  blurPair(wideA, wideB)
  blurPair(wideA, wideB)       # twice: the wide halo should be really soft

proc beginComposite(level: PostFxLevel, w, h: float32) =
  let p = paramsFor(level)
  beginShaderMode(composite)
  setShaderValue(composite, locRes, [w, h])
  setShaderValue(composite, locTime, getTime().float32)
  setShaderValue(composite, locBloom, p.bloom)
  setShaderValue(composite, locSat, p.saturation)
  setShaderValue(composite, locContrast, p.contrast)
  setShaderValue(composite, locVignette, p.vignette)
  setShaderValue(composite, locAberration, p.aberration)
  # Texture units are claimed per draw batch and beginShaderMode just started
  # one, so the glow is bound after it.
  setShaderValueTexture(composite, locNear, nearA.texture)
  setShaderValueTexture(composite, locWide, wideA.texture)

proc drawComposited*(level: PostFxLevel, frame: Texture2D, source, dest: Rectangle) =
  ## The final blit, through the composite. Inside beginDrawing.
  beginComposite(level, dest.width, dest.height)
  drawTexture(frame, source, dest, Vector2(x: 0, y: 0), 0, White)
  endShaderMode()

proc composeToTexture*(level: PostFxLevel, frame: Texture2D): ptr Texture2D =
  ## The composite into an off-screen target the size of `frame`, for a mod's
  ## post-process shader to read. Outside any drawing. The result is stored
  ## like any render texture (draw it with a flipped source).
  if composedW != frame.width or composedH != frame.height:
    composed = makeTarget(frame.width, frame.height)
    composedW = frame.width
    composedH = frame.height
  # Not `pass`: beginTextureMode flushes the batch, which unbinds the glow, so
  # the composite starts inside the target.
  beginTextureMode(composed)
  clearBackground(Black)
  beginComposite(level, frame.width.float32, frame.height.float32)
  drawTexture(frame, Rectangle(x: 0, y: 0, width: frame.width.float32, height: -frame.height.float32),
              Rectangle(x: 0, y: 0, width: frame.width.float32, height: frame.height.float32),
              Vector2(x: 0, y: 0), 0, White)
  endShaderMode()
  endTextureMode()
  addr composed.texture
