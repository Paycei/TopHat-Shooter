## Cube Skin System
## Defines colour themes for the interactive 3-D cube on the OS desktop

import raylib, localization

type
  CubeSkinType* = enum
    cskDefault,  ## System Unit   – classic red/orange (free)
    cskNeon,     ## Neon Pulse    – bright neon purple
    cskIce,      ## Cryo Core     – icy blue crystalline
    cskGold,     ## Gold Standard – luxury golden
    cskShadow,   ## Shadow Node   – stealth dark
    cskPlasma,   ## Plasma Rig    – electric blue-purple
    cskMatrix    ## Data Node     – matrix green

  CubeSkinData* = object
    name*: string
    description*: string
    faceColor*: Color
    edgeColor*: Color
    glowColor*: Color

var cubeSkinDatabase*: array[CubeSkinType, CubeSkinData]

proc initCubeSkins*() =
  cubeSkinDatabase[cskDefault] = CubeSkinData(
    name: t("csk_default"), description: t("csk_default_desc"),
    faceColor: Color(r: 18,  g: 116, b: 168, a: 255),
    edgeColor: Color(r: 190, g: 250, b: 255, a: 255),
    glowColor: Color(r: 0,   g: 210, b: 255, a: 180))

  cubeSkinDatabase[cskNeon] = CubeSkinData(
    name: t("csk_neon"), description: t("csk_neon_desc"),
    faceColor: Color(r: 160, g: 0,   b: 240, a: 255),
    edgeColor: Color(r: 255, g: 0,   b: 200, a: 255),
    glowColor: Color(r: 200, g: 0,   b: 255, a: 180))

  cubeSkinDatabase[cskIce] = CubeSkinData(
    name: t("csk_ice"), description: t("csk_ice_desc"),
    faceColor: Color(r: 80,  g: 180, b: 255, a: 255),
    edgeColor: Color(r: 200, g: 240, b: 255, a: 255),
    glowColor: Color(r: 120, g: 200, b: 255, a: 180))

  cubeSkinDatabase[cskGold] = CubeSkinData(
    name: t("csk_gold"), description: t("csk_gold_desc"),
    faceColor: Color(r: 200, g: 160, b: 0,   a: 255),
    edgeColor: Color(r: 255, g: 220, b: 60,  a: 255),
    glowColor: Color(r: 255, g: 200, b: 0,   a: 180))

  cubeSkinDatabase[cskShadow] = CubeSkinData(
    name: t("csk_shadow"), description: t("csk_shadow_desc"),
    faceColor: Color(r: 40,  g: 40,  b: 55,  a: 255),
    edgeColor: Color(r: 120, g: 120, b: 160, a: 255),
    glowColor: Color(r: 80,  g: 80,  b: 120, a: 180))

  cubeSkinDatabase[cskPlasma] = CubeSkinData(
    name: t("csk_plasma"), description: t("csk_plasma_desc"),
    faceColor: Color(r: 60,  g: 60,  b: 255, a: 255),
    edgeColor: Color(r: 180, g: 100, b: 255, a: 255),
    glowColor: Color(r: 100, g: 100, b: 255, a: 180))

  cubeSkinDatabase[cskMatrix] = CubeSkinData(
    name: t("csk_matrix"), description: t("csk_matrix_desc"),
    faceColor: Color(r: 0,   g: 180, b: 0,   a: 255),
    edgeColor: Color(r: 120, g: 255, b: 120, a: 255),
    glowColor: Color(r: 0,   g: 220, b: 0,   a: 180))

proc getCubeSkinData*(skinType: CubeSkinType): CubeSkinData =
  cubeSkinDatabase[skinType]
