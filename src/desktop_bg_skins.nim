## Desktop Background Skins System
## Defines available OS desktop background colour themes

import raylib
import localization

type
  DesktopBgType* = enum
    dbgDefault,   ## OS Grid : original animated circuit board (free)
    dbgNeon,      ## Neon City: pink/purple neon lights
    dbgMatrix,    ## Data Rain: cascading green code
    dbgVoid,      ## Deep Void: dark space with stars
    dbgSunrise,   ## System Sunrise: warm orange horizon
    dbgOcean,     ## Neural Network: cool blue interconnected nodes
    dbgInferno,   ## Inferno Core: red volcanic heat
    dbgPortal,    ## Aperture Test: blue/orange portals (Portal reference)
    dbgHorror,    ## Kernel Panic: dread-soaked dark where the cube cowers
    dbgCyber,     ## Cyberspace: rain-soaked neon grid with glitching holograms
    dbgCasino,    ## High Roller: green felt, card suits, poker chips and gold
    dbgDragon     ## Dragon's Lair: black dragons coiled at the edges of a rune-etched dark

  DesktopBgData* = object
    name*: string
    description*: string
    primaryColor*: Color   ## Main line / particle colour
    accentColor*: Color    ## Secondary accent / glow colour
    bgColor*: Color        ## Base background fill colour

var desktopBgDatabase*: array[DesktopBgType, DesktopBgData]

proc initializeDesktopBgSkins*() =
  desktopBgDatabase[dbgDefault] = DesktopBgData(
    name: t("dbg_default"), description: t("dbg_default_desc"),
    primaryColor: Color(r: 0,   g: 184, b: 225, a: 255),
    accentColor:  Color(r: 95,  g: 130, b: 174, a: 255),
    bgColor:      Color(r: 5,   g: 8,   b: 18,  a: 255))

  desktopBgDatabase[dbgNeon] = DesktopBgData(
    name: t("dbg_neon"), description: t("dbg_neon_desc"),
    primaryColor: Color(r: 255, g: 0,   b: 200, a: 255),
    accentColor:  Color(r: 100, g: 0,   b: 255, a: 255),
    bgColor:      Color(r: 8,   g: 4,   b: 18,  a: 255))

  desktopBgDatabase[dbgMatrix] = DesktopBgData(
    name: t("dbg_matrix"), description: t("dbg_matrix_desc"),
    primaryColor: Color(r: 0,   g: 255, b: 50,  a: 255),
    accentColor:  Color(r: 0,   g: 160, b: 30,  a: 255),
    bgColor:      Color(r: 4,   g: 10,  b: 4,   a: 255))

  desktopBgDatabase[dbgVoid] = DesktopBgData(
    name: t("dbg_void"), description: t("dbg_void_desc"),
    primaryColor: Color(r: 80,  g: 0,   b: 180, a: 255),
    accentColor:  Color(r: 140, g: 100, b: 255, a: 255),
    bgColor:      Color(r: 4,   g: 2,   b: 12,  a: 255))

  desktopBgDatabase[dbgSunrise] = DesktopBgData(
    name: t("dbg_sunrise"), description: t("dbg_sunrise_desc"),
    primaryColor: Color(r: 255, g: 130, b: 0,   a: 255),
    accentColor:  Color(r: 255, g: 220, b: 60,  a: 255),
    bgColor:      Color(r: 18,  g: 8,   b: 4,   a: 255))

  desktopBgDatabase[dbgOcean] = DesktopBgData(
    name: t("dbg_ocean"), description: t("dbg_ocean_desc"),
    primaryColor: Color(r: 0,   g: 160, b: 255, a: 255),
    accentColor:  Color(r: 0,   g: 220, b: 200, a: 255),
    bgColor:      Color(r: 4,   g: 8,   b: 18,  a: 255))

  desktopBgDatabase[dbgInferno] = DesktopBgData(
    name: t("dbg_inferno"), description: t("dbg_inferno_desc"),
    primaryColor: Color(r: 255, g: 60,  b: 0,   a: 255),
    accentColor:  Color(r: 255, g: 200, b: 0,   a: 255),
    bgColor:      Color(r: 16,  g: 4,   b: 2,   a: 255))

  # Aperture Science test chamber: the two signature portal colours, a cool
  # blue (primary) and a warm orange (accent), over a dark panelled wall.
  desktopBgDatabase[dbgPortal] = DesktopBgData(
    name: t("dbg_portal"), description: t("dbg_portal_desc"),
    primaryColor: Color(r: 60,  g: 150, b: 255, a: 255),
    accentColor:  Color(r: 255, g: 150, b: 40,  a: 255),
    bgColor:      Color(r: 6,   g: 9,   b: 16,  a: 255))

  # Kernel Panic: a suffocating dark where the only colours are dried-blood red
  # (primary) and the sickly yellow-green of eyes catching the light (accent),
  # over an almost-black, faintly red base.
  desktopBgDatabase[dbgHorror] = DesktopBgData(
    name: t("dbg_horror"), description: t("dbg_horror_desc"),
    primaryColor: Color(r: 150, g: 12,  b: 14,  a: 255),
    accentColor:  Color(r: 190, g: 180, b: 90,  a: 255),
    bgColor:      Color(r: 7,   g: 2,   b: 3,   a: 255))

  # Cyberspace: the cyberpunk duotone, electric cyan (primary) and hot magenta
  # (accent) over a deep teal-black night, for the rain-slicked neon grid look.
  desktopBgDatabase[dbgCyber] = DesktopBgData(
    name: t("dbg_cyber"), description: t("dbg_cyber_desc"),
    primaryColor: Color(r: 80,  g: 245, b: 255, a: 255),
    accentColor:  Color(r: 255, g: 60,  b: 200, a: 255),
    bgColor:      Color(r: 4,   g: 8,   b: 16,  a: 255))

  # High Roller: casino felt. Gold (primary) drives the orbital rings that frame
  # the cube like a betting spot; casino red (accent) and a deep green felt base.
  desktopBgDatabase[dbgCasino] = DesktopBgData(
    name: t("dbg_casino"), description: t("dbg_casino_desc"),
    primaryColor: Color(r: 255, g: 205, b: 70,  a: 255),
    accentColor:  Color(r: 215, g: 32,  b: 48,  a: 255),
    bgColor:      Color(r: 8,   g: 36,  b: 22,  a: 255))

  # Dragon's Lair: an ancient grimoire's cover. Antique gold (primary) traces
  # the rune-work and dragon rim-light, smoldering ember red (accent) glows in
  # the eyes and breath, over a near-black, faintly warm leather base.
  desktopBgDatabase[dbgDragon] = DesktopBgData(
    name: t("dbg_dragon"), description: t("dbg_dragon_desc"),
    primaryColor: Color(r: 205, g: 160, b: 60,  a: 255),
    accentColor:  Color(r: 200, g: 40,  b: 20,  a: 255),
    bgColor:      Color(r: 6,   g: 4,   b: 5,   a: 255))

proc getDesktopBgData*(bgType: DesktopBgType): DesktopBgData =
  desktopBgDatabase[bgType]
