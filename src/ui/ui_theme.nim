## Interface themes: how the OS layer looks. That is the desktop, the taskbar,
## every window and what it shows, the dialogs and the toasts, but not a run
## (the HUD and the in-run screens) and not the story cinematics, which stage
## TopHat-ShooterOS itself (withTheme(stockTheme())).
##
## A theme is data (UiTheme): five anchor colours and the shell it wears. The
## shell (ShellStyle) is the set of hand-drawn pieces: window chrome, default
## wallpaper, start button, pointer, toasts, loading dialog. TopHat-ShooterOS
## is the stock theme; CKN OS, the system Act IV installs over it, unlocks
## when that ending is watched; mods add more (register.theme, mod_theme.nim).
## Settings keep the chosen theme's id; the shop's SECRET tab and Settings >
## Interface > Theme both set it.
##
## Interface code asks the theme for every colour it draws, by the colour's
## role, passing the stock value it was designed with:
##   uiSurface(c)  a fill: window, panel, card, control, track, row, field
##   uiLine(c)     a border, divider or outline
##   uiInk(c)      text, and glyphs drawn like text
##   uiGlow(c)     translucent light: halos, hover glows, sheens
## The stock theme hands `c` back untouched, so TopHat-ShooterOS draws exactly
## as it was written. Any other theme maps it onto its anchors in OKLab:
## lightness by role (a surface's elevation between the theme's surface and
## raised colours, text between its muted and text colours), the stock cyan
## accent onto the theme's accent, and every other hue kept, so red still
## reads as danger, green as OK and gold as currency. Whatever is not passed
## through a role keeps its own colours: shadows and scrims, and every picture
## (skins, icons, wallpapers, mod images).

import std/[math, tables]
import ../modding/mod_patch_core
import raylib, rlgl
import ../draw_prims, ../localization, ../save_system, ../settings, ../utils
import ../modding/mod_hooks

const
  CknPaper* = Color(r: 236, g: 240, b: 246, a: 255)   ## panels, title bars, the taskbar
  CknInk* = Color(r: 40, g: 50, b: 70, a: 255)        ## text
  CknBlue* = Color(r: 60, g: 120, b: 210, a: 255)     ## the accent: focus, progress, the logo's arc
  CknSun* = Color(r: 255, g: 190, b: 90, a: 255)      ## the logo's sun
  CknMuted* = Color(r: 120, g: 128, b: 145, a: 255)   ## secondary text
  CknTrack* = Color(r: 205, g: 214, b: 228, a: 255)   ## progress tracks, hairlines, idle borders
  CknShadow* = Color(r: 16, g: 28, b: 52, a: 255)     ## drop shadows (used translucent)

  StockSurface* = Color(r: 20, g: 20, b: 30, a: 255)  ## a window's body
  StockRaised* = Color(r: 60, g: 60, b: 80, a: 255)   ## a button, a tab, a card
  StockText* = Color(r: 255, g: 255, b: 255, a: 255)
  StockMuted* = Color(r: 130, g: 130, b: 130, a: 255)
  StockAccent* = Color(r: 0, g: 200, b: 255, a: 255)

type
  ShellStyle* = enum
    ## The hand-drawn half of a theme. A mod's theme picks one as its base.
    ssTopHat = "tophat"   ## glowing frames, the OS Grid wallpaper, the crosshair
    ssCkn = "ckn"         ## paper frames, CKN Dawn, the arrow pointer

  UiRole = enum
    urSurface, urLine, urInk, urGlow

  Lab = tuple[L, a, b: float32]

  UiTheme* = ref object
    id*: string           ## "tophat", "ckn", or "<mod id>:<id>" for a mod's
    nameKey: TranslationKey
    modName, modNameEs: string  ## a mod's display name, English and Spanish (built-ins use nameKey)
    shell*: ShellStyle
    surface*, raised*, text*, muted*, accent*: Color   ## the anchors
    wallpaper*: int       ## a mod texture for the default wallpaper; 0 = the shell's own
    owner*: int           ## the mod that registered it; -1 = built in
    stock*: bool          ## TopHat-ShooterOS: every role hands its colour back
    light*: bool          ## a light surface (the shell and previews adapt)
    s, r, t, m, ac: Lab   ## the anchors in OKLab
    chroma: float32       ## accent chroma over the stock accent's
    cache: Table[uint64, Color]

proc themeName*(th: UiTheme): string {.moddable.} =
  if th.owner < 0: t(th.nameKey)
  else: pickText(th.modName, th.modNameEs)

# ---------------------------------------------------------------------------
# OKLab

proc toLinear(v: float32): float32 =
  if v <= 0.04045'f32: v / 12.92'f32 else: pow((v + 0.055'f32) / 1.055'f32, 2.4'f32)

proc toSrgb(v: float32): float32 =
  let c = clamp(v, 0.0'f32, 1.0'f32)
  if c <= 0.0031308'f32: c * 12.92'f32 else: 1.055'f32 * pow(c, 1.0'f32 / 2.4'f32) - 0.055'f32

proc labOf(c: Color): Lab =
  let r = toLinear(c.r.float32 / 255.0'f32)
  let g = toLinear(c.g.float32 / 255.0'f32)
  let b = toLinear(c.b.float32 / 255.0'f32)
  let l = cbrt(0.4122214708'f32 * r + 0.5363325363'f32 * g + 0.0514459929'f32 * b)
  let m = cbrt(0.2119034982'f32 * r + 0.6806995451'f32 * g + 0.1073969566'f32 * b)
  let s = cbrt(0.0883024619'f32 * r + 0.2817188376'f32 * g + 0.6299787005'f32 * b)
  (0.2104542553'f32 * l + 0.7936177850'f32 * m - 0.0040720468'f32 * s,
   1.9779984951'f32 * l - 2.4285922050'f32 * m + 0.4505937099'f32 * s,
   0.0259040371'f32 * l + 0.7827717662'f32 * m - 0.8086757660'f32 * s)

proc linearOf(L, a, b: float32): array[3, float32] =
  let l = L + 0.3963377774'f32 * a + 0.2158037573'f32 * b
  let m = L - 0.1055613458'f32 * a - 0.0638541728'f32 * b
  let s = L - 0.0894841775'f32 * a - 1.2914855480'f32 * b
  let (l3, m3, s3) = (l * l * l, m * m * m, s * s * s)
  [4.0767416621'f32 * l3 - 3.3077115913'f32 * m3 + 0.2309699292'f32 * s3,
   -1.2684380046'f32 * l3 + 2.6097574011'f32 * m3 - 0.3413193965'f32 * s3,
   -0.0041960863'f32 * l3 - 0.7034186147'f32 * m3 + 1.7076147010'f32 * s3]

proc inGamut(c: array[3, float32]): bool =
  c[0] >= -0.001'f32 and c[1] >= -0.001'f32 and c[2] >= -0.001'f32 and
    c[0] <= 1.001'f32 and c[1] <= 1.001'f32 and c[2] <= 1.001'f32

proc colorOf(L, chroma, hue: float32, alpha: uint8): Color =
  ## The sRGB colour at this lightness and hue, its chroma bisected down to
  ## the most sRGB can hold there.
  var c = chroma
  var lin = linearOf(L, c * cos(hue), c * sin(hue))
  if not inGamut(lin):
    var lo = 0.0'f32
    var hi = c
    for _ in 0..7:
      let mid = (lo + hi) * 0.5'f32
      if inGamut(linearOf(L, mid * cos(hue), mid * sin(hue))): lo = mid else: hi = mid
    c = lo
    lin = linearOf(L, c * cos(hue), c * sin(hue))
  Color(r: uint8(toSrgb(lin[0]) * 255.0'f32 + 0.5'f32), g: uint8(toSrgb(lin[1]) * 255.0'f32 + 0.5'f32),
        b: uint8(toSrgb(lin[2]) * 255.0'f32 + 0.5'f32), a: alpha)

proc chromaOf(x: Lab): float32 {.inline.} = sqrt(x.a * x.a + x.b * x.b)
proc hueOf(x: Lab): float32 {.inline.} = arctan2(x.b, x.a)

proc turn(a, b: float32): float32 =
  ## Signed shortest turn from angle b to angle a, in radians.
  floorMod(a - b + PI.float32, 2.0'f32 * PI.float32) - PI.float32

proc smooth(e0, e1, x: float32): float32 =
  let t = clamp((x - e0) / (e1 - e0), 0.0'f32, 1.0'f32)
  t * t * (3.0'f32 - 2.0'f32 * t)

let
  stockS = labOf(StockSurface)
  stockR = labOf(StockRaised)
  stockM = labOf(StockMuted)
  stockA = labOf(StockAccent)

# ---------------------------------------------------------------------------
# Themes

proc prepare(th: UiTheme) =
  th.s = labOf(th.surface)
  th.r = labOf(th.raised)
  th.t = labOf(th.text)
  th.m = labOf(th.muted)
  th.ac = labOf(th.accent)
  th.light = th.s.L > 0.6'f32
  th.chroma = clamp(chromaOf(th.ac) / max(chromaOf(stockA), 0.001'f32), 0.4'f32, 1.4'f32)
  th.cache.clear()

proc newTheme*(id: string, shell: ShellStyle, surface, raised, text, muted, accent: Color,
               owner = -1, name = "", nameEs = "", wallpaper = 0): UiTheme {.moddable.} =
  ## A theme from its anchors. Register it with addTheme.
  result = UiTheme(id: id, shell: shell, surface: surface, raised: raised, text: text,
                   muted: muted, accent: accent, owner: owner, modName: name, modNameEs: nameEs,
                   wallpaper: wallpaper)
  result.prepare()

var themes: seq[UiTheme]
  ## Every theme there is: the built-ins first, then the loaded mods' in load order.

block:
  var stock = newTheme("tophat", ssTopHat, StockSurface, StockRaised, StockText, StockMuted, StockAccent)
  stock.nameKey = tkThemeTopHat
  stock.stock = true
  var ckn = newTheme("ckn", ssCkn, CknPaper, Color(r: 200, g: 208, b: 222, a: 255), CknInk, CknMuted,
                     CknBlue)
  ckn.nameKey = tkThemeCkn
  themes = @[stock, ckn]

const BuiltinThemes = 2

proc stockTheme*(): UiTheme = themes[0]

proc findTheme*(id: string): UiTheme {.moddable.} =
  for th in themes:
    if th.id == id: return th
  nil

proc addTheme*(th: UiTheme): bool {.moddable.} =
  ## Register a mod's theme; false if its id is taken.
  if not findTheme(th.id).isNil: return false
  themes.add(th)
  true

proc themeUnlocked*(th: UiTheme): bool {.moddable.} =
  ## CKN OS is what gets installed over TopHat-ShooterOS at the end of Act IV
  ## (UPTIME, the last story recording), so watching that ending unlocks it:
  ## the same flag that unlocks its replay, which also covers saves that saw
  ## it before the theme existed (and a data reset relocks it). A loaded mod's
  ## themes are always there.
  if th.isNil: false
  elif th.id == "ckn": not globalSettings.isNil and globalSettings.hasSeenSurvivalEnding
  else: true

proc unlockedThemes*(): seq[UiTheme] {.moddable.} =
  for th in themes:
    if themeUnlocked(th): result.add(th)

proc chosenTheme*(): UiTheme {.moddable.} =
  ## The player's theme: the saved choice while it exists and is unlocked (a
  ## mod that is not loaded right now, or a relocked CKN OS, falls back to the
  ## stock one; the choice itself is kept).
  if globalSettings.isNil: return themes[0]
  let th = findTheme(globalSettings.interfaceTheme)
  if themeUnlocked(th): th else: themes[0]

proc chooseTheme*(id: string): bool {.moddable.} =
  ## Make `id` the player's theme. False if there is no such theme or it is
  ## still locked. The caller saves the settings.
  let th = findTheme(id)
  if globalSettings.isNil or not themeUnlocked(th): return false
  globalSettings.interfaceTheme = th.id
  true

var forced: seq[UiTheme]

proc activeTheme*(): UiTheme {.moddable.} =
  ## The theme being drawn in: the player's, or one a caller forced.
  if forced.len > 0: forced[^1] else: chosenTheme()

proc forceTheme(th: UiTheme) = forced.add(th)
proc unforceTheme() {.moddable.} =
  if forced.len > 0: forced.setLen(forced.len - 1)

template withTheme*(th: UiTheme, body: untyped) =
  ## Draw `body` in theme `th` whatever the player picked (the story
  ## cinematics film TopHat-ShooterOS: withTheme(stockTheme())).
  forceTheme(th)
  try:
    body
  finally:
    unforceTheme()

proc dropModThemes(owner: int) =
  var kept: seq[UiTheme]
  for th in themes:
    if th.owner != owner: kept.add(th)
  themes = kept

proc resetModThemes() =
  themes.setLen(BuiltinThemes)

addModTeardown(resetModThemes, dropModThemes)

# ---------------------------------------------------------------------------
# Roles

proc hueFor(th: UiTheme, h: float32): float32 =
  ## A chromatic colour's hue: the stock cyan band turns to the theme's
  ## accent; on a light theme yellows lean amber, since pure yellow turns olive
  ## at the lightness paper needs.
  result = h + turn(hueOf(th.ac), hueOf(stockA)) *
               (1.0'f32 - smooth(0.5236'f32, 1.2217'f32, abs(turn(h, hueOf(stockA)))))
  if th.light:
    result -= 0.314159'f32 * (1.0'f32 - smooth(0.20944'f32, 0.610865'f32, abs(turn(h, 1.658063'f32))))

proc mapColor(th: UiTheme, c: Color, role: UiRole): Color =
  let x = labOf(c)
  let C = chromaOf(x)
  let neutral = 1.0'f32 - smooth(0.02'f32, 0.06'f32, C)
  var L: float32
  var tint: tuple[a, b: float32]
  case role
  of urSurface, urLine:
    # Elevation in stock steps (body 0, button 1) onto the theme's own.
    let e = (x.L - stockS.L) / (stockR.L - stockS.L)
    L = th.s.L + e * (th.r.L - th.s.L)
    let k = clamp(e, 0.0'f32, 2.0'f32) * 0.5'f32
    tint = (th.s.a + (th.r.a - th.s.a) * k, th.s.b + (th.r.b - th.s.b) * k)
  of urInk, urGlow:
    # Text from muted (0) to full (1); colourful ink keeps more of its own
    # lightness around the accent, so it stays vivid on either kind of theme.
    let e = (x.L - stockM.L) / (1.0'f32 - stockM.L)
    let neutralL = th.m.L + e * (th.t.L - th.m.L)
    let vividL = th.ac.L + (x.L - stockA.L) / (1.0'f32 - stockM.L) * (th.t.L - th.m.L) * 0.5'f32
    L = neutralL + (vividL - neutralL) * smooth(0.05'f32, 0.13'f32, C)
    let k = clamp(e, 0.0'f32, 1.0'f32)
    tint = (th.m.a + (th.t.a - th.m.a) * k, th.m.b + (th.t.b - th.m.b) * k)
  let h = if C > 0.00001'f32: th.hueFor(hueOf(x)) else: 0.0'f32
  let a = (C * th.chroma * cos(h)) * (1.0'f32 - neutral) + tint.a * neutral
  let b = (C * th.chroma * sin(h)) * (1.0'f32 - neutral) + tint.b * neutral
  var alpha = c.a
  if role == urGlow and th.light:
    alpha = uint8(c.a.float32 * 0.5'f32)   # light on paper only tints it
  colorOf(clamp(L, 0.0'f32, 1.0'f32), sqrt(a * a + b * b), arctan2(b, a), alpha)

proc themed(c: Color, role: UiRole): Color =
  let th = activeTheme()
  if th.stock:
    return c
  let key = (uint64(ord(role)) shl 32) or (uint64(c.r) shl 24) or (uint64(c.g) shl 16) or
            (uint64(c.b) shl 8) or uint64(c.a)
  th.cache.withValue(key, known):
    return known[]
  result = th.mapColor(c, role)
  th.cache[key] = result

proc uiSurface*(c: Color): Color = themed(c, urSurface)
  ## A fill: window, panel, card, control, track, row, field.
proc uiLine*(c: Color): Color = themed(c, urLine)
  ## A border, divider or outline.
proc uiInk*(c: Color): Color = themed(c, urInk)
  ## Text, and glyphs drawn like text.
proc uiGlow*(c: Color): Color = themed(c, urGlow)
  ## Translucent light: halos, hover glows, sheens.

proc rgba(r, g, b, a: int): Color {.inline.} =
  Color(r: uint8(r), g: uint8(g), b: uint8(b), a: uint8(a))

proc uiSurface*(r, g, b: int, a = 255): Color = uiSurface(rgba(r, g, b, a))
proc uiLine*(r, g, b: int, a = 255): Color = uiLine(rgba(r, g, b, a))
proc uiInk*(r, g, b: int, a = 255): Color = uiInk(rgba(r, g, b, a))
proc uiGlow*(r, g, b: int, a = 255): Color = uiGlow(rgba(r, g, b, a))

proc mixColor*(a, b: Color, t: float32): Color {.moddable.} =
  ## Straight sRGB blend, `t` of the way from a to b (alpha too).
  template ch(x, y: uint8): uint8 = uint8(x.float32 + (y.float32 - x.float32) * clamp(t, 0.0'f32, 1.0'f32) + 0.5'f32)
  Color(r: ch(a.r, b.r), g: ch(a.g, b.g), b: ch(a.b, b.b), a: ch(a.a, b.a))

# ---------------------------------------------------------------------------
# The frame's alpha
#
# raylib's alpha blend also blends the render target's alpha down under every
# translucent layer, and the frame is shown premultiplied over black
# (post_fx.nim). On the stock theme's near-black surfaces that is invisible;
# on anything brighter, every glow and hover tint would read as a dark smudge.
# A theme layer keeps the frame's alpha opaque instead.

var keepAlphaDepth = 0

proc beginKeepAlpha*() {.moddable.} =
  inc keepAlphaDepth
  if keepAlphaDepth == 1:
    setBlendFactorsSeparate(SrcAlpha, OneMinusSrcAlpha, One, OneMinusSrcAlpha, FuncAdd, FuncAdd)
    beginBlendMode(BlendMode.CustomSeparate)

proc endKeepAlpha*() {.moddable.} =
  if keepAlphaDepth == 0: return
  dec keepAlphaDepth
  if keepAlphaDepth == 0:
    endBlendMode()

proc beginThemeLayer*(): bool {.moddable.} =
  ## Open a theme layer by hand (for one that closes in a `defer`); pass the
  ## result to endThemeLayer.
  result = not activeTheme().stock
  if result: beginKeepAlpha()

proc endThemeLayer*(began: bool) {.moddable.} =
  if began: endKeepAlpha()

template themeLayer*(body: untyped) =
  ## Draw a piece of the interface (a window, a dialog, the desktop): any
  ## theme but the stock one keeps the frame opaque under it (see above).
  let began = beginThemeLayer()
  try:
    body
  finally:
    endThemeLayer(began)

# ---------------------------------------------------------------------------
# Hand-drawn pieces

proc cornerRoundness*(w, h, radius: float32): float32 {.moddable.} =
  ## raylib's roundness for `radius`-pixel corners on a w x h rectangle
  ## (raylib measures it against the shorter side).
  clamp(2.0'f32 * radius / max(1.0'f32, min(w, h)), 0.0'f32, 1.0'f32)

proc drawCknPanel*(rect: Rectangle, radius: float32, fill: Color, border: Color,
                   shadowAlpha = 0.0'f32) {.moddable.} =
  ## A rounded CKN surface: a soft two-layer drop shadow (when shadowAlpha >
  ## 0, 0..255), the fill and a hairline border drawn just outside it.
  let r = cornerRoundness(rect.width, rect.height, radius)
  if shadowAlpha > 0.0'f32:
    let wide = Rectangle(x: rect.x - 2.0'f32, y: rect.y + 2.0'f32,
                         width: rect.width + 4.0'f32, height: rect.height + 6.0'f32)
    drawRectangleRounded(wide, cornerRoundness(wide.width, wide.height, radius + 3.0'f32), 10,
                         withAlpha(CknShadow, shadowAlpha * 0.35'f32))
    let near = Rectangle(x: rect.x, y: rect.y + 2.0'f32, width: rect.width, height: rect.height + 1.0'f32)
    drawRectangleRounded(near, r, 10, withAlpha(CknShadow, shadowAlpha * 0.6'f32))
  drawRectangleRounded(rect, r, 10, fill)
  if border.a > 0:
    # Negative thickness strokes outside the shape (raylib 6), so the border
    # never eats into the fill or the text laid out against it.
    drawRectangleRoundedLines(rect, r, 10, -1.0'f32, border)

proc drawCknLogo*(cx, cy, size: float32, alpha = 1.0'f32, arc = CknBlue) {.moddable.} =
  ## A rising sun over a line: pleasant, generic, nothing like a hat. `arc`
  ## colours the ring and the line (a CKN-based theme passes its accent).
  drawRing(Vector2(x: cx, y: cy), size * 0.55'f32, size * 0.72'f32, 180.0'f32, 360.0'f32, 32,
           withAlpha(arc, alpha * 255.0'f32))
  drawDisc(Vector2(x: cx, y: cy), size * 0.3'f32, withAlpha(CknSun, alpha * 255.0'f32))
  drawRectangle((cx - size).int32, cy.int32, (size * 2.0'f32).int32, (size * 0.12'f32).int32 + 1,
                withAlpha(arc, alpha * 255.0'f32))
