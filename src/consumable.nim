import raylib, random, math, strutils
import modding/mod_patch_core
import draw_prims
import particle_types, types, utils, localization
import modding/mod_registry

# What each built-in consumable is, as data. Its effect lives in collectPickup
# (game.nim); a mod's consumable (ctMod) is read from its registration
# (register.consumable) instead, so every reader goes through the procs below.

type
  ConsumableSpec = object
    color: Color                ## its one colour: body, aura, pull trail,
                                ## pickup burst and floating label
    duration: float32           ## buff seconds (0: an instant pickup)
    bountifulDuration: float32  ## the same with Cornucopia (hasBountiful)

const vanillaConsumableSpecs: array[ConsumableType, ConsumableSpec] = [
  ctHealth: ConsumableSpec(color: Color(r: 50, g: 255, b: 50, a: 255)),
  ctCoin: ConsumableSpec(color: Color(r: 255, g: 215, b: 0, a: 255)),
  ctSpeed: ConsumableSpec(color: Cyan, duration: 5.0, bountifulDuration: 7.5),
  ctInvincibility: ConsumableSpec(color: Color(r: 255, g: 0, b: 255, a: 255),
                                  duration: 3.0, bountifulDuration: 4.5),
  ctFireRate: ConsumableSpec(color: Color(r: 255, g: 165, b: 0, a: 255),
                             duration: 8.0, bountifulDuration: 12.0),
  ctMagnet: ConsumableSpec(color: Color(r: 147, g: 51, b: 234, a: 255),
                           duration: 10.0, bountifulDuration: 10.0),
  ctShieldBoost: ConsumableSpec(color: Color(r: 100, g: 200, b: 255, a: 255),
                                duration: 10.0, bountifulDuration: 15.0),
  ctDoubleCoin: ConsumableSpec(color: Color(r: 255, g: 223, b: 0, a: 255),
                               duration: 10.0, bountifulDuration: 15.0),
  ctDamageBoost: ConsumableSpec(color: Color(r: 255, g: 69, b: 0, a: 255),
                                duration: 10.0, bountifulDuration: 15.0),
  ctLifesteal: ConsumableSpec(color: Color(r: 220, g: 20, b: 20, a: 255),
                              duration: 15.0, bountifulDuration: 22.0),
  ctMod: ConsumableSpec(color: Color(r: 200, g: 200, b: 200, a: 255))]

proc consumableColor*(c: Consumable): Color {.moddable.} =
  if c.consumableType == ctMod: modConsumableColor(c.modKey)
  else: vanillaConsumableSpecs[c.consumableType].color

proc consumablePerkLabel*(c: Consumable): string {.moddable.} =
  ## The floating "+SPEED" shown on pickup. "" for health and coin, which float
  ## the amount they gave instead.
  case c.consumableType
  of ctHealth, ctCoin: ""
  of ctSpeed: t(tkPerkSpeed)
  of ctInvincibility: t(tkPerkInvincible)
  of ctFireRate: t(tkPerkFireRate)
  of ctMagnet: t(tkPerkMagnet)
  of ctShieldBoost: t(tkPerkShield)
  of ctDoubleCoin: t(tkPerkDoubleCoin)
  of ctDamageBoost: t(tkPerkDamage)
  of ctLifesteal: t(tkPerkLifesteal)
  of ctMod: "+" & modConsumableName(c.modKey).toUpperAscii

proc startConsumableBuff*(player: Player, ct: ConsumableType) {.moddable.} =
  ## Start (or refresh) a timed consumable's buff, for its spec's duration.
  let s = vanillaConsumableSpecs[ct]
  let duration = if player.hasBountiful: s.bountifulDuration else: s.duration
  case ct
  of ctSpeed: player.speedBoostTimer = duration
  of ctInvincibility: player.invincibilityTimer = duration
  of ctFireRate: player.fireRateBoostTimer = duration
  of ctMagnet: player.magnetTimer = duration
  of ctShieldBoost:
    player.shieldBoostTimer = duration
    player.shieldHits = if player.hasBountiful: 3 else: 2  # Cornucopia: 3 hits
  of ctDoubleCoin: player.doubleCoinTimer = duration
  of ctDamageBoost: player.damageBoostTimer = duration
  of ctLifesteal: player.lifestealTimer = duration
  of ctHealth, ctCoin, ctMod: discard

# Icon drawing: simple, clear glyphs so each pickup reads at a glance.

proc drawHealthIcon(cx, cy: int32) =
  ## Simple plus/cross symbol (medical cross)
  let white = Color(r: 255, g: 255, b: 255, a: 255)
  let thickness: int32 = 3

  # Vertical bar
  drawRectangle(cx - 1, cy - 5, thickness, 10, white)

  # Horizontal bar
  drawRectangle(cx - 5, cy - 1, 10, thickness, white)

proc drawCoinIcon(cx, cy: int32) =
  ## Simple $ symbol
  let gold = Color(r: 255, g: 215, b: 0, a: 255)

  # Draw $ character large and bold
  drawText("$", cx - 4, cy - 6, 14, Color(r: 50, g: 40, b: 0, a: 255))  # Shadow
  drawText("$", cx - 5, cy - 7, 14, gold)

proc drawSpeedIcon(cx, cy: int32) =
  ## Three horizontal arrow lines (motion lines)
  let cyan = Color(r: 0, g: 255, b: 255, a: 255)

  # Three motion lines of increasing length
  for i in 0..2:
    let yPos: int32 = cy - 3 + (i * 3).int32
    let length: int32 = (8 + i * 2).int32
    # Arrow line
    drawRectangle(cx - 6, yPos, length, 2, cyan)
    # Arrow head
    drawTriangle(
      Vector2(x: (cx - 6 + length).float32, y: (yPos - 1).float32),
      Vector2(x: (cx - 6 + length).float32, y: (yPos + 3).float32),
      Vector2(x: (cx - 6 + length + 3).float32, y: (yPos + 1).float32),
      cyan
    )

proc drawInvincibilityIcon(cx, cy: int32) =
  ## Simple star shape
  let magenta = Color(r: 255, g: 0, b: 255, a: 255)

  # Draw 8-pointed star with lines
  for i in 0..7:
    let angle = i.float32 * PI / 4.0
    let innerRadius = 2.0
    let outerRadius = 7.0

    let x1 = cx.float32 + cos(angle) * innerRadius
    let y1 = cy.float32 + sin(angle) * innerRadius
    let x2 = cx.float32 + cos(angle) * outerRadius
    let y2 = cy.float32 + sin(angle) * outerRadius

    drawStroke(Vector2(x: x1, y: y1), Vector2(x: x2, y: y2), 3.0, magenta)

  # Center circle
  drawDisc(Vector2(x: cx.float32, y: cy.float32), 3, magenta)

proc drawFireRateIcon(cx, cy: int32) =
  ## Simple lightning bolt (zigzag)
  let orange = Color(r: 255, g: 165, b: 0, a: 255)

  # Bold lightning bolt shape
  let points = [
    Vector2(x: (cx + 2).float32, y: (cy - 7).float32),
    Vector2(x: (cx - 1).float32, y: (cy - 1).float32),
    Vector2(x: (cx + 2).float32, y: (cy - 1).float32),
    Vector2(x: (cx - 2).float32, y: (cy + 7).float32),
    Vector2(x: (cx + 1).float32, y: (cy + 1).float32),
    Vector2(x: (cx - 2).float32, y: (cy + 1).float32)
  ]

  # Draw filled polygon
  for i in 0..4:
    drawTriangle(
      Vector2(x: cx.float32, y: cy.float32),
      points[i],
      points[(i + 1) mod 6],
      orange
    )

  # Outline for clarity
  for i in 0..5:
    drawStroke(points[i], points[(i + 1) mod 6], 2.0, Color(r: 200, g: 130, b: 0, a: 255))

proc drawMagnetIcon(cx, cy: int32) =
  ## Horseshoe magnet - U shape with colored ends
  let purple = Color(r: 147, g: 51, b: 234, a: 255)
  let red = Color(r: 255, g: 0, b: 0, a: 255)
  let blue = Color(r: 0, g: 100, b: 255, a: 255)

  # Left pole (red - north)
  drawRectangle(cx - 6, cy - 5, 3, 8, red)

  # Right pole (blue - south)
  drawRectangle(cx + 3, cy - 5, 3, 8, blue)

  # Bottom connector
  drawRectangle(cx - 6, cy + 3, 12, 3, purple)

proc drawShieldIcon(cx, cy: int32) =
  ## Classic shield shape
  let cyan = Color(r: 0, g: 255, b: 255, a: 255)
  let dark = Color(r: 0, g: 150, b: 150, a: 255)

  # Shield outline shape using triangles
  # Top half
  drawTriangle(
    Vector2(x: cx.float32, y: (cy - 7).float32),
    Vector2(x: (cx - 6).float32, y: cy.float32),
    Vector2(x: (cx + 6).float32, y: cy.float32),
    dark
  )

  # Bottom point
  drawTriangle(
    Vector2(x: (cx - 6).float32, y: cy.float32),
    Vector2(x: (cx + 6).float32, y: cy.float32),
    Vector2(x: cx.float32, y: (cy + 7).float32),
    dark
  )

  # Shield border (outline)
  drawStroke(Vector2(x: cx.float32, y: (cy - 7).float32),
           Vector2(x: (cx - 6).float32, y: cy.float32), 2.0, cyan)
  drawStroke(Vector2(x: cx.float32, y: (cy - 7).float32),
           Vector2(x: (cx + 6).float32, y: cy.float32), 2.0, cyan)
  drawStroke(Vector2(x: (cx - 6).float32, y: cy.float32),
           Vector2(x: cx.float32, y: (cy + 7).float32), 2.0, cyan)
  drawStroke(Vector2(x: (cx + 6).float32, y: cy.float32),
           Vector2(x: cx.float32, y: (cy + 7).float32), 2.0, cyan)

  # Center cross for detail
  drawStroke(Vector2(x: cx.float32, y: (cy - 3).float32),
           Vector2(x: cx.float32, y: (cy + 3).float32), 2.0, cyan)
  drawStroke(Vector2(x: (cx - 3).float32, y: cy.float32),
           Vector2(x: (cx + 3).float32, y: cy.float32), 2.0, cyan)

proc drawDoubleCoinIcon(cx, cy: int32) =
  ## Two coins stacked with "2x" text
  let gold = Color(r: 255, g: 223, b: 0, a: 255)
  let darkGold = Color(r: 200, g: 170, b: 0, a: 255)

  # Back coin (offset)
  drawDisc(Vector2(x: (cx + 2).float32, y: (cy + 2).float32), 5, darkGold)
  drawCircleOutline(Vector2(x: (cx + 2).float32, y: (cy + 2).float32), 5,
                  Color(r: 150, g: 120, b: 0, a: 255))

  # Front coin
  drawDisc(Vector2(x: (cx - 2).float32, y: (cy - 2).float32), 5, gold)
  drawCircleOutline(Vector2(x: (cx - 2).float32, y: (cy - 2).float32), 5, darkGold)

  # "2x" text
  drawText("2x", cx - 5, cy - 4, 8, Color(r: 50, g: 40, b: 0, a: 255))

proc drawDamageBoostIcon(cx, cy: int32) =
  ## Simple upward arrow with exclamation
  let redOrange = Color(r: 255, g: 69, b: 0, a: 255)

  # Arrow shaft
  drawRectangle(cx - 1, cy - 2, 3, 8, redOrange)

  # Arrow head (triangle)
  drawTriangle(
    Vector2(x: cx.float32, y: (cy - 7).float32),
    Vector2(x: (cx - 4).float32, y: (cy - 2).float32),
    Vector2(x: (cx + 4).float32, y: (cy - 2).float32),
    redOrange
  )

  # Exclamation mark inside
  drawRectangle(cx - 1, cy - 1, 2, 4, Color(r: 255, g: 255, b: 255, a: 255))
  drawRectangle(cx - 1, cy + 4, 2, 2, Color(r: 255, g: 255, b: 255, a: 255))

proc drawLifestealIcon(cx, cy: int32) =
  ## Heart with droplet inside
  let darkRed = Color(r: 139, g: 0, b: 0, a: 255)
  let brightRed = Color(r: 255, g: 50, b: 50, a: 255)

  # Simple heart shape using two circles and a triangle
  # Left circle
  drawDisc(Vector2(x: (cx - 3).float32, y: (cy - 2).float32), 4, darkRed)
  # Right circle
  drawDisc(Vector2(x: (cx + 3).float32, y: (cy - 2).float32), 4, darkRed)
  # Bottom triangle
  drawTriangle(
    Vector2(x: (cx - 6).float32, y: (cy - 2).float32),
    Vector2(x: (cx + 6).float32, y: (cy - 2).float32),
    Vector2(x: cx.float32, y: (cy + 7).float32),
    darkRed
  )

  # Small droplet inside heart
  drawDisc(Vector2(x: cx.float32, y: cy.float32), 2, brightRed)
  drawTriangle(
    Vector2(x: cx.float32, y: (cy - 3).float32),
    Vector2(x: (cx - 2).float32, y: cy.float32),
    Vector2(x: (cx + 2).float32, y: cy.float32),
    brightRed
  )

proc drawConsumableIcon(x, y: float32, cType: ConsumableType) {.moddable.} =
  ## Central icon dispatcher: each glyph is drawn at a fixed size.
  let cx = x.int32
  let cy = y.int32

  case cType
  of ctHealth:
    drawHealthIcon(cx, cy)
  of ctCoin:
    drawCoinIcon(cx, cy)
  of ctSpeed:
    drawSpeedIcon(cx, cy)
  of ctInvincibility:
    drawInvincibilityIcon(cx, cy)
  of ctFireRate:
    drawFireRateIcon(cx, cy)
  of ctMagnet:
    drawMagnetIcon(cx, cy)
  of ctShieldBoost:
    drawShieldIcon(cx, cy)
  of ctDoubleCoin:
    drawDoubleCoinIcon(cx, cy)
  of ctDamageBoost:
    drawDamageBoostIcon(cx, cy)
  of ctLifesteal:
    drawLifestealIcon(cx, cy)
  of ctMod:
    discard   # drawn by drawConsumable (its look lives on the mod's registration)

proc newConsumable*(x, y: float32, difficulty: float32, mode = gmWaveBased): Consumable {.moddable.} =
  # Weighted selection based on difficulty. Mod consumables (register.consumable)
  # add their weights on top of the game's 100.
  let modWeight = if consumableDefs.len > 0: modConsumableWeight(mode) else: 0'f32
  if modWeight > 0:
    let r = rand(100'f32 + modWeight)
    if r >= 100:
      let key = rollModConsumable(mode, r - 100)
      if key.len > 0:
        return Consumable(pos: vec2(x, y), radius: 9, consumableType: ctMod,
                          lifetime: 15.0, modKey: key)
  let roll = rand(100)
  var cType: ConsumableType

  if roll < 30:        # Health - common (30%)
    cType = ctHealth
  elif roll < 50:      # Coin - common (20%)
    cType = ctCoin
  elif roll < 63:      # Speed - uncommon (13%)
    cType = ctSpeed
  elif roll < 73:      # Fire Rate - uncommon (10%)
    cType = ctFireRate
  elif roll < 81:      # Shield Boost - uncommon (8%)
    cType = ctShieldBoost
  elif roll < 88:      # Magnet - rare (7%)
    cType = ctMagnet
  elif roll < 93:      # Damage Boost - rare (5%)
    cType = ctDamageBoost
  elif roll < 97:      # Invincibility - epic (4%)
    cType = ctInvincibility
  elif roll < 99:      # Double Coin - epic (2%)
    cType = ctDoubleCoin
  else:                # Lifesteal - legendary (1%)
    cType = ctLifesteal

  result = Consumable(
    pos: vec2(x, y),
    radius: 8,
    consumableType: cType,
    lifetime: 15.0
  )

proc newSpecificConsumable*(x, y: float32, cType: ConsumableType): Consumable {.moddable.} =
  ## Create a consumable of a specific type (for boss drops, etc.)
  result = Consumable(
    pos: vec2(x, y),
    radius: 8,
    consumableType: cType,
    lifetime: 15.0
  )

proc pickupAlive*(game: Game, consumable: Consumable, dt: float32, count: int): bool {.moddable.} =
  consumable.lifetime -= dt
  consumable.lifetime > 0

proc pickupTrail*(consumable: Consumable): Color {.moddable.} =
  withAlpha(consumableColor(consumable), 150)

proc drawConsumable*(consumable: Consumable) {.moddable.} =
  let t = getTime()
  let pulse = 1.0 + 0.15 * sin(t * 6.0)
  let size = consumable.radius * pulse

  let color = consumableColor(consumable)
  let auraColor = withAlpha(color, 50)

  # Outer soft aura glow (two layers for depth)
  let auraR1 = size + 7 + sin(t * 4.0) * 2.5
  let auraR2 = size + 13 + sin(t * 3.0 + 1.0) * 3.0
  drawDisc(consumable.pos, auraR2,
    scaleAlpha(auraColor, 0.5'f32))
  drawDisc(consumable.pos, auraR1, auraColor)

  # 4 rotating sparkle dots around the aura ring
  for i in 0..<4:
    let sa = t * 2.2 + i.float32 * PI / 2.0
    let sr = auraR1 + 2.0
    drawDisc(
      Vector2(x: consumable.pos.x + cos(sa) * sr, y: consumable.pos.y + sin(sa) * sr),
      2.0, withAlpha(auraColor, 200))

  # Draw background circle
  drawDisc(consumable.pos, size, color)
  drawCircleOutline(consumable.pos.x.int32, consumable.pos.y.int32, size, Black)
  if consumable.consumableType == ctMod:
    drawModConsumableIcon(consumable.modKey, consumable.pos.x, consumable.pos.y, size)
    return

  # Use new detailed icon system
  drawConsumableIcon(consumable.pos.x, consumable.pos.y, consumable.consumableType)
