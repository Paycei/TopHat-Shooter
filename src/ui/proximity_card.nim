## Proximity info card: the tooltip that floats over an interactable pickup in
## a roguelite folder (patch pedestals, /pkg stalls) while the player stands
## next to it. Walking up to a thing and reading what it does is the whole
## interaction; [E] then applies or buys it.
##
## Leaf UI module: raylib + types + localization + the icon kit. It must never
## import dungeon or game, because dungeon.nim draws it.

import raylib
import ../types, ../localization, ../utils, ../powerup_data, icon_drawing, ui_helpers

type
  ProximityIconKind* = enum
    pciPatch,     # drawPatchIcon(patch)
    pciPowerUp,   # drawPowerUpIcon(powerUp)
    pciReward     # drawRoomRewardIcon(reward)

  ProximityCard* = object
    iconKind*: ProximityIconKind
    patch*: RogueliteRelicType
    powerUp*: PowerUpType
    reward*: RoomReward
    tag*: string          # small accent line: "KB-3101 // PERFORMANCE"
    title*: string
    body*: string
    action*: string       # "[E] APPLY UPDATE" / "[E] INSTALL"
    price*: int           # credits; 0 = free
    affordable*: bool
    disabled*: bool       # e.g. a maxed power-up: action greyed out
    accent*: Color

const
  CardW = 262'i32
  CardPad = 10'i32
  IconBox = 38'i32
  BodySize = 12'i32
  BodyLines = 4

proc drawProximityCard*(card: ProximityCard, anchorX, anchorY: float32,
                        worldW, worldH: int32, time: float32) =
  ## Draw the card centred above (anchorX, anchorY) in world space, flipped
  ## below the anchor when there is no room above, clamped to the arena.
  let bodyW = CardW - CardPad * 2
  let bodyFont = bestWrapFontSize(card.body, bodyW, BodySize, BodyLines, 9)
  var lines = wrapTextLines(card.body, bodyW, bodyFont)
  if lines.len > BodyLines:
    lines.setLen(BodyLines)
  let lineH = bodyFont + 3
  let headerH = IconBox + CardPad
  let cardH = CardPad + headerH + lines.len.int32 * lineH + 8 + 18 + CardPad

  var x = int32(anchorX) - CardW div 2
  var y = int32(anchorY) - 46 - cardH
  if y < 8:
    y = int32(anchorY) + 40
  x = clamp(x, 8'i32, max(8'i32, worldW - CardW - 8))
  y = clamp(y, 8'i32, max(8'i32, worldH - cardH - 8))

  let accent = card.accent
  let rect = Rectangle(x: x.float32, y: y.float32, width: CardW.float32, height: cardH.float32)

  # Drop shadow, glass body, accent header wash, frame.
  drawRectangle(x + 4, y + 5, CardW, cardH, Color(r: 0, g: 0, b: 0, a: 120))
  drawRectangle(x, y, CardW, cardH, Color(r: 13, g: 18, b: 28, a: 238))
  drawRectangleGradientV(x, y, CardW, headerH + CardPad, withAlpha(accent, 46), withAlpha(accent, 0))
  drawRectangle(x, y, CardW, 3, accent)
  drawRectangleLines(rect, 1.5, withAlpha(accent, 200))

  # Icon tile.
  let ix = x + CardPad
  let iy = y + CardPad
  drawRectangle(ix, iy, IconBox, IconBox, Color(r: 8, g: 12, b: 20, a: 255))
  drawRectangleLines(Rectangle(x: ix.float32, y: iy.float32, width: IconBox.float32,
                               height: IconBox.float32), 1.0, withAlpha(accent, 150))
  case card.iconKind
  of pciPatch:
    drawPatchIcon(ix + 2, iy + 2, IconBox - 4, card.patch, accent)
  of pciPowerUp:
    drawPowerUpIcon(ix + 2, iy + 2, IconBox - 4, card.powerUp, getPowerUpColor(card.powerUp))
  of pciReward:
    drawRoomRewardIcon(ix + 3, iy + 3, IconBox - 6, card.reward, accent)

  # Tag + title beside the icon.
  let textX = ix + IconBox + 9
  let textW = CardW - (textX - x) - CardPad
  drawTextFit(card.tag, textX, iy + 2, textW, 11, withAlpha(accent, 235), 8)
  drawTextFit(card.title, textX, iy + 17, textW, 17, RayWhite, 10)

  # Body.
  var ly = y + CardPad + headerH
  for line in lines:
    drawText(line, x + CardPad, ly, bodyFont, Color(r: 196, g: 206, b: 222, a: 255))
    ly += lineH

  # Action row: prompt on the left, price on the right.
  let ay = y + cardH - CardPad - 16
  drawLine(x + CardPad, ay - 5, x + CardW - CardPad, ay - 5, withAlpha(accent, 60))
  let blink = 0.75'f32 + 0.25'f32 * (if int(time * 2.0'f32) mod 2 == 0: 1.0'f32 else: 0.0'f32)
  let actionColor =
    if card.disabled: Color(r: 120, g: 126, b: 140, a: 255)
    elif card.affordable: withAlpha(accent, uint8(255.0'f32 * blink))
    else: Color(r: 255, g: 110, b: 100, a: 255)
  let priceW = if card.price > 0: measureText($card.price, 14) + 22 else: 0'i32
  drawTextFit(card.action, x + CardPad, ay, CardW - CardPad * 2 - priceW - 6, 14, actionColor, 9)
  if card.price > 0:
    let px = x + CardW - CardPad - priceW
    drawCurrencyIcon(px + 8, ay + 7, 15, ciCredits)
    drawText($card.price, px + 19, ay, 14,
             if card.affordable: Color(r: 255, g: 220, b: 90, a: 255)
             else: Color(r: 255, g: 110, b: 100, a: 255))

proc noCreditsLabel*(): string =
  t("pkg_need_credits")
