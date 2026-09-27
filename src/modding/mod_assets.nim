## Mod textures and cosmetics (MODS.EXE).
##
## Everything in this game is drawn in code; mods may swap any of the main
## bodies for a PNG: the player, an enemy type, a boss, bullets, power-up icons
## and the desktop wallpaper (override.texture), or ship cosmetics the player
## equips from MODS.EXE (register.cosmetic: a palette and/or a texture).
##
## Low in the DAG (raylib + types + sound) so the renderers can call the
## draw helpers directly. Textures are GPU resources: they load after the
## window exists and unloadModAssets must run before it closes.

import std/[tables, math]
import raylib, rlgl
import ../types, ../sound

type
  TexReplace* = object
    id*: int           ## index + 1 into modTextures; 0 = none
    scale*: float32    ## multiplier on the body's diameter
    rotate*: bool      ## turn with the body (movement / rotation)

  ModTexture = object
    tex: Texture2D
    path: string

  ModCosmeticKind* = enum
    mckPlayer = "player", mckBullet = "bullet", mckDesktop = "desktop"

  ModCosmetic* = object
    kind*: ModCosmeticKind
    key*: string       ## "<mod id>:<id>", what Settings.modCosmetics stores
    name*, description*: string
    owner*: int
    hasPalette*: bool
    c1*, c2*, c3*: Color   ## player: primary/secondary/core; bullet: primary/glow/trail
    tex*: TexReplace
    cube*: bool            ## desktop: keep the desktop cube over the wallpaper

var
  modTextures: seq[ModTexture]
  playerTex*: TexReplace
  enemyTex*: array[EnemyType, TexReplace]
  bossTex*: Table[int, TexReplace]
  bulletTex*: array[bool, TexReplace]          ## [fromPlayer]
  powerUpTex*: array[PowerUpType, TexReplace]
  desktopTex*: TexReplace
  desktopCube*: bool                               ## override.texture("desktop", ..., {cube = true})
  modCosmetics*: seq[ModCosmetic]
  equippedCosmetic*: array[ModCosmeticKind, int]  ## index + 1, 0 = none
  modTexturesActive*: bool                         ## any replacement at all (fast bail-out)
  pvpDrawing*: bool
    ## Set while PvP draws: bullets then wear their SHOOTER's cosmetic
    ## (pvpBulletCosmetic), never the local player's.
  pvpBulletCosmetic*: int
    ## PvP: the bullet cosmetic (index + 1) of the player who fired the bullet
    ## being drawn; drawPvP sets it per bullet.

proc loadModTexture*(path: string): int =
  ## Load a PNG (once per path). Returns the texture id, 0 on failure.
  for i in 0 ..< modTextures.len:   # (by index: a texture cannot be copied)
    if modTextures[i].path == path: return i + 1
  try:
    var tex = loadTexture(path)
    setTextureFilter(tex, TextureFilter.Bilinear)
    modTextures.add(ModTexture(tex: move tex, path: path))
    modTextures.len
  except CatchableError:
    0

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

# ------------------------------------------------------------------ shaders ----
# assets.shader / override.shader: GLSL fragment shaders run over the finished
# frame (post-processing). "screen" covers everything; "game" only while a run
# is on screen (and wins over "screen" then).
type ModShader = object
  shader: Shader
  path: string
  time, resolution: ShaderLocation

var
  modShaders: seq[ModShader]
  screenShader*, gameShader*: int   ## override.shader targets (index + 1, 0 = none)
  postShaderInRun*: bool            ## main.nim, each frame: is a run on screen?

proc loadModShader*(path: string, err: var string): int =
  ## A fragment shader file (raylib's default vertex shader). 0 and `err` set
  ## when it cannot be used; GLSL compile errors fall back to raylib's default
  ## shader, which is reported here rather than silently drawing nothing new.
  for i in 0 ..< modShaders.len:
    if modShaders[i].path == path: return i + 1
  try:
    var s = loadShader("", path)
    if s.id == 0 or s.id == getShaderIdDefault():
      err = "the shader did not compile (GLSL fragment shader expected)"
      return 0
    let t = getShaderLocation(s, "time")
    let r = getShaderLocation(s, "resolution")
    modShaders.add(ModShader(shader: move s, path: path, time: t, resolution: r))
    modShaders.len
  except CatchableError as e:
    err = e.msg
    0

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
  true

proc textureSize*(id: int): tuple[w, h: int] =
  if id <= 0 or id > modTextures.len: return (0, 0)
  (modTextures[id - 1].tex.width.int, modTextures[id - 1].tex.height.int)

proc markActive*() =
  modTexturesActive = true

proc unloadModAssets*() =
  ## Drop every mod texture, replacement, cosmetic and sound override.
  modTextures.setLen(0)
  modShaders.setLen(0)
  screenShader = 0
  gameShader = 0
  for s in modSounds.mitems: s.voices.setLen(0)   # aliases before their source
  modSounds.setLen(0)
  playerTex = TexReplace()
  for et in EnemyType: enemyTex[et] = TexReplace()
  bossTex.clear()
  bulletTex = [TexReplace(), TexReplace()]
  for pt in PowerUpType: powerUpTex[pt] = TexReplace()
  desktopTex = TexReplace()
  desktopCube = false
  modCosmetics.setLen(0)
  for k in ModCosmeticKind: equippedCosmetic[k] = 0
  modTexturesActive = false
  restoreVanillaSounds()

# ------------------------------------------------------------------ drawing ----
proc drawModTexture*(id: int, x, y, w, h, rotationDeg: float32, tint: Color,
                     centered = true) =
  ## Draw texture `id` into a w x h box at (x, y) (its centre when `centered`).
  if id <= 0 or id > modTextures.len: return
  let t = addr modTextures[id - 1].tex
  let src = Rectangle(x: 0, y: 0, width: t.width.float32, height: t.height.float32)
  if centered:
    drawTexture(t[], src, Rectangle(x: x, y: y, width: w, height: h),
                Vector2(x: w / 2, y: h / 2), rotationDeg, tint)
  else:
    drawTexture(t[], src, Rectangle(x: x, y: y, width: w, height: h), Vector2(x: 0, y: 0),
                rotationDeg, tint)

proc drawReplacement*(r: TexReplace, x, y, diameter, angleDeg: float32,
                      tint: Color = White) =
  ## A replacement body: fitted into the diameter, aspect kept, centred.
  let (tw, th) = textureSize(r.id)
  if tw <= 0 or th <= 0: return
  let size = diameter * (if r.scale > 0: r.scale else: 1.0'f32)
  let aspect = tw.float32 / th.float32
  let (w, h) = if aspect >= 1.0: (size, size / aspect) else: (size * aspect, size)
  drawModTexture(r.id, x, y, w, h, (if r.rotate: angleDeg else: 0.0'f32), tint)

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
  ## True when a texture drew the player's body (skin texture, else a mod's
  ## override.texture("player")).
  if not modTexturesActive: return false
  var r = TexReplace()
  let c = cosmeticAt(p.modSkin.int)
  if not c.isNil and c.kind == mckPlayer and c.tex.id > 0: r = c.tex
  elif playerTex.id > 0: r = playerTex
  if r.id == 0: return false
  let angle = if p.vel.x != 0 or p.vel.y != 0: radToDeg(arctan2(p.vel.y, p.vel.x)) else: 0.0'f32
  drawReplacement(r, p.pos.x, p.pos.y, p.radius * 2.0'f32, angle, tint)
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
  var r = TexReplace()
  if playerLook:
    let c = bulletCosmetic()
    if not c.isNil and c.tex.id > 0: r = c.tex
  if r.id == 0: r = bulletTex[playerLook]
  if r.id == 0: return false
  drawReplacement(r, b.pos.x, b.pos.y, b.radius * 2.0'f32, radToDeg(arctan2(b.vel.y, b.vel.x)))
  true

proc drawEnemyModBody*(e: Enemy): bool =
  if not modTexturesActive: return false
  let r = if e.isBoss: bossTex.getOrDefault(e.bossDefinitionID) else: enemyTex[e.enemyType]
  if r.id == 0: return false
  let tint = if e.hitFlashTimer > 0: Color(r: 255, g: 200, b: 200, a: 255) else: White
  drawReplacement(r, e.pos.x, e.pos.y, e.radius * 2.0'f32, radToDeg(e.rotation), tint)
  true

proc drawPowerUpModIcon*(x, y, size: int32, pt: PowerUpType): bool =
  if not modTexturesActive or powerUpTex[pt].id == 0: return false
  let s = size.float32
  drawReplacement(powerUpTex[pt], x.float32 + s / 2, y.float32 + s / 2, s, 0)
  true

proc modWallpaper*(): tuple[id: int, cube: bool] =
  ## The mod wallpaper covering the desktop: an equipped desktop cosmetic, else
  ## override.texture("desktop"). id 0 = none (the built-in background shows).
  ## `cube`: the mod keeps the desktop cube (drawn and grabbable) on top of it.
  if not modTexturesActive: return (0, false)
  let c = cosmeticAt(equippedCosmetic[mckDesktop])
  if not c.isNil and c.tex.id > 0: return (c.tex.id, c.cube)
  if desktopTex.id > 0: return (desktopTex.id, desktopCube)
  (0, false)

proc drawDesktopModBackground*(w, h: int32): bool =
  ## The mod wallpaper (modWallpaper), scaled to cover the screen.
  let id = modWallpaper().id
  if id == 0: return false
  let (tw, th) = textureSize(id)
  if tw <= 0 or th <= 0: return false
  let scale = max(w.float32 / tw.float32, h.float32 / th.float32)
  let dw = tw.float32 * scale
  let dh = th.float32 * scale
  drawModTexture(id, (w.float32 - dw) / 2, (h.float32 - dh) / 2, dw, dh, 0, White, centered = false)
  true

# ----------------------------------------------------------------- equipping ----
proc cosmeticIndex*(kind: ModCosmeticKind, key: string): int =
  for i, c in modCosmetics:
    if c.kind == kind and c.key == key: return i + 1
  0

proc noteEquippedTextures() =
  ## The draw helpers bail out early unless some texture is in play, so an
  ## equipped texture cosmetic has to switch that on (and it must happen on
  ## every equip, not only at load: MODS.EXE equips mid-session).
  for k in ModCosmeticKind:
    if equippedCosmetic[k] > 0 and modCosmetics[equippedCosmetic[k] - 1].tex.id > 0:
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
