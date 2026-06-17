## Cube Skin System
## Defines colour themes for the interactive 3-D cube on the OS desktop

import raylib
import localization

type
  CubeSkinType* = enum
    cskDefault,  ## System Unit: classic red/orange
    cskNeon,     ## Neon Pulse: bright neon purple
    cskIce,      ## Cryo Core: icy blue crystalline
    cskGold,     ## Gold Standard: luxury golden
    cskShadow,   ## Shadow Node: stealth dark
    cskPlasma,   ## Plasma Rig: electric blue-purple
    cskMatrix,   ## Data Node: matrix green
    cskCompanion, ## Companion Cube: grey with a pink heart (Portal reference)
    cskJack,     ## Jack-O'-Node: orange pumpkin with a carved, glowing face
    cskCyber,    ## Cyberdeck: cyan/magenta with a holographic HUD panel per face
    cskDice,     ## Lucky Die: white die, dark pips (1-6) baked to each face
    cskD20       ## Dragon's Fang: a true 20-sided icosahedron, obsidian and gold

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

  cubeSkinDatabase[cskCompanion] = CubeSkinData(
    name: t("csk_companion"), description: t("csk_companion_desc"),
    faceColor: Color(r: 128, g: 130, b: 138, a: 255),
    edgeColor: Color(r: 208, g: 210, b: 216, a: 255),
    glowColor: Color(r: 244, g: 130, b: 160, a: 180))

  # Jack-O'-Node: a pumpkin-orange gourd; the carved face glows like candlelight
  # (the carved features are drawn on one fixed side in os_desktop's wallpaper-cube renderer).
  cubeSkinDatabase[cskJack] = CubeSkinData(
    name: t("csk_jack"), description: t("csk_jack_desc"),
    faceColor: Color(r: 235, g: 110, b: 15,  a: 255),
    edgeColor: Color(r: 255, g: 175, b: 50,  a: 255),
    glowColor: Color(r: 255, g: 140, b: 0,   a: 180))

  # Cyberdeck: a neon duotone, cyan body, hot-magenta edges, cyan glow; the
  # holographic HUD panel on each face is drawn in os_desktop's cube renderer.
  cubeSkinDatabase[cskCyber] = CubeSkinData(
    name: t("csk_cyber"), description: t("csk_cyber_desc"),
    faceColor: Color(r: 20,  g: 120, b: 150, a: 255),
    edgeColor: Color(r: 255, g: 60,  b: 200, a: 255),
    glowColor: Color(r: 80,  g: 245, b: 255, a: 180))

  # Lucky Die: a classic white die with clean light edges; the dark pips (1..6,
  # opposite faces summing to 7) are drawn per face in os_desktop's cube renderer.
  cubeSkinDatabase[cskDice] = CubeSkinData(
    name: t("csk_dice"), description: t("csk_dice_desc"),
    faceColor: Color(r: 236, g: 237, b: 242, a: 255),
    edgeColor: Color(r: 205, g: 207, b: 214, a: 255),
    glowColor: Color(r: 255, g: 255, b: 255, a: 150))

  # Dragon's Fang: a true 20-sided icosahedron (not a painted cube) tying into
  # the Dragon's Lair background - obsidian faces, antique-gold facet edges,
  # ember glow. Geometry + numerals are drawn in os_desktop's cube renderer.
  cubeSkinDatabase[cskD20] = CubeSkinData(
    name: t("csk_d20"), description: t("csk_d20_desc"),
    faceColor: Color(r: 20,  g: 17,  b: 22,  a: 255),
    edgeColor: Color(r: 205, g: 160, b: 60,  a: 255),
    glowColor: Color(r: 200, g: 40,  b: 20,  a: 190))

proc getCubeSkinData*(skinType: CubeSkinType): CubeSkinData =
  cubeSkinDatabase[skinType]
