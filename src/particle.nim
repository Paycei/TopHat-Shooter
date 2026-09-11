import raylib, random, math, strutils
import particle_types, types, utils, ui/ui_constants, ui/icon_drawing

## FLOATING LABEL MOTION
##
## Damage numbers, currency pickups and perk labels all ride the same arc model.
## The old model launched every label straight up at a fixed speed and only
## jittered X, which still produced a vertical column of text: same rise rate
## means same trajectory shape. Each label now rolls a full polar launch (angle
## AND speed), plus its own gravity, drag, tilt, wobble, size and lifetime, so a
## burst of hits on one enemy sprays apart instead of stacking.

const
  FloatSpreadMinDeg = 7.0'f32     # never dead-vertical, or stacked hits overlap
  FloatSpreadMaxDeg = 44.0'f32    # widest launch tilt off straight-up
  FloatSprayBias = 0.72'f32       # odds a label honours the alternating side
  FloatSpinMaxDeg = 8.0'f32       # birth tilt velocity, deg/s
  FloatTiltLimitDeg = 4.5'f32     # tilt cap: just enough to break up a stack of
                                  # identical numbers, not enough to notice as
                                  # rotation on any single one
  FloatSpinDecay = 0.955'f32      # per-60fps-frame spin damping

var floatSpraySide: float32 = 1.0
  ## Flips on every spawn. Pure rand() clumps -- three hits in a row landing on
  ## the same side is common enough to read as a bug -- so the SIDE alternates
  ## and only the magnitude is random.

proc frand(lo, hi: float32): float32 =
  ## Uniform float32 in [lo, hi]. `rand` returns float64, so this keeps the
  ## conversion in one place instead of at every call site.
  lo + rand(1.0).float32 * (hi - lo)

proc rollFloatSide(): float32 =
  floatSpraySide = -floatSpraySide
  if rand(1.0) < FloatSprayBias: floatSpraySide
  elif rand(1.0) < 0.5: -1.0'f32
  else: 1.0'f32

proc randomFloatVelocity(minSpeed, maxSpeed: float32,
                         spreadScale: float32 = 1.0'f32): Vector2f =
  ## Polar launch measured off straight-up, so a wide angle trades height for
  ## sideways travel exactly like a real toss -- angle and speed vary together
  ## instead of being two independent axes.
  let deg = rollFloatSide() *
    frand(FloatSpreadMinDeg, FloatSpreadMaxDeg * spreadScale)
  let a = degToRad(deg)
  let speed = frand(minSpeed, maxSpeed)
  newVector2f(sin(a) * speed, -cos(a) * speed)

proc initFloatMotion[T](label: T, gravity, swayMax: float32,
                        spinScale: float32 = 1.0'f32) =
  ## Rolls the shared arc fields. Generic over the three label types rather than
  ## sharing a base object: they are independent `ref object`s in types.nim and
  ## a common parent would ripple through every construction site.
  label.gravity = gravity * frand(0.85, 1.18)
  # Lateral travel is what separates rapid-fire hits, so drag decays slowly:
  # at 0.93 the sideways launch was spent inside 0.3s and labels ended up
  # ~20px apart; this range carries them 50-80px.
  label.drag = frand(0.955, 0.982)
  label.rotation = frand(-1.5, 1.5) * spinScale
  label.spin = frand(-FloatSpinMaxDeg, FloatSpinMaxDeg) * spinScale
  label.swayPhase = frand(0.0, TAU)
  label.swaySpeed = frand(3.4, 6.8)
  label.swayAmount = frand(0.0, swayMax)   # px/s; ~amplitude/swaySpeed in px
  label.sizeScale = frand(0.93, 1.10)

proc stepFloatMotion[T](label: T, dt: float32): bool =
  ## Advances one floating label; false once it has outlived maxLifetime.
  label.vel.y += label.gravity * dt
  # Sway is added to POSITION, not velocity: folded into velocity it would be
  # eaten by the drag term within a few frames and the wobble would vanish.
  let sway = sin(label.lifetime * label.swaySpeed + label.swayPhase) *
    label.swayAmount
  label.pos.x += (label.vel.x + sway) * dt
  label.pos.y += label.vel.y * dt
  label.vel.x = label.vel.x * pow(label.drag, 60.0 * dt)
  label.rotation = clamp(label.rotation + label.spin * dt,
                         -FloatTiltLimitDeg, FloatTiltLimitDeg)
  label.spin = label.spin * pow(FloatSpinDecay, 60.0 * dt)
  label.lifetime += dt
  result = label.lifetime < label.maxLifetime

proc newDamageNumber*(x, y: float32, damage: float32, fromPlayer: bool, isCritical: bool = false, damageType: DamageType = dtDefault): DamageNumber =
  # Crits launch harder but in a NARROWER cone: more height, less sideways
  # travel, so the standout hit stays near the impact where the eye already is.
  let speedMin = if isCritical: 185.0'f32 else: 150.0'f32
  let speedMax = if isCritical: 255.0'f32 else: 215.0'f32
  let spreadScale = if isCritical: 0.70'f32 else: 1.0'f32

  result = DamageNumber(
    pos: newVector2f(x + frand(-10.0, 10.0), y + frand(-6.0, 4.0)),
    vel: randomFloatVelocity(speedMin, speedMax, spreadScale),
    damage: damage,
    lifetime: 0,
    maxLifetime: (if isCritical: 1.65'f32 else: 1.42'f32) * frand(0.88, 1.12),
    fromPlayer: fromPlayer,
    isCritical: isCritical,
    damageType: damageType
  )
  initFloatMotion(result, 235.0'f32, 38.0'f32)
  if isCritical:
    result.spin = result.spin * 1.6
    result.sizeScale = result.sizeScale * 1.05

proc newCurrencyIndicator*(x, y: float32, amount: int,
                           kind: CurrencyIndicatorKind = cikCredits): CurrencyIndicator =
  # Data shards fire every wave, tighter spread so they don't wander off-screen
  let spreadScale = if kind == cikDataShards: 0.50'f32 else: 0.85'f32
  # Shards stay visible longer since they're the most important roguelite number
  let maxLife = case kind
    of cikDataShards:        1.60'f32
    of cikCores:             1.45'f32
    of cikCredits:           1.35'f32
    of cikXp:                1.10'f32   # snappy: XP picks up constantly, keep it brief

  result = CurrencyIndicator(
    pos: newVector2f(x + frand(-5.0, 5.0), y + frand(-4.0, 3.0)),
    vel: randomFloatVelocity(118.0, 172.0, spreadScale),
    amount: amount,
    lifetime: 0,
    maxLifetime: maxLife * frand(0.92, 1.08),
    kind: kind
  )
  # Low spin: the icon next to the text is drawn upright, so a big tilt on the
  # number alone would look detached from it.
  initFloatMotion(result, 170.0'f32, 16.0'f32, 0.45'f32)

proc newPerkIndicator*(x, y: float32, text: string, color: Color): PerkIndicator =
  ## Floating "+SHIELD" style label for consumable pickups. Drifts upward like
  ## a damage number, then gravity pulls it back down as it fades out.
  ## Words are wider than numbers, so these launch tamer and barely tilt.
  result = PerkIndicator(
    pos: newVector2f(x + frand(-4.0, 4.0), y),
    vel: randomFloatVelocity(112.0, 156.0, 0.55'f32),
    text: text,
    color: color,
    lifetime: 0,
    maxLifetime: 1.3'f32 * frand(0.93, 1.07)
  )
  initFloatMotion(result, 152.0'f32, 12.0'f32, 0.5'f32)

proc updateDamageNumber*(dmgNum: DamageNumber, dt: float32): bool =
  stepFloatMotion(dmgNum, dt)

proc updateCurrencyIndicator*(indicator: CurrencyIndicator, dt: float32): bool =
  stepFloatMotion(indicator, dt)

proc updatePerkIndicator*(indicator: PerkIndicator, dt: float32): bool =
  stepFloatMotion(indicator, dt)

# FLOATING LABEL RENDERING

proc floatFade(lifetime, maxLifetime, holdFraction: float32): float32 =
  ## 0 while the label is at full opacity, easing to 1 at death.
  ##
  ## The old curve faded linearly from the very first frame, so in a busy fight
  ## a number was already half transparent by the time the eye reached it.
  ## Holding full opacity for the first `holdFraction` of the life and easing
  ## out after costs nothing and makes a crowded screen readable.
  let progress = lifetime / maxLifetime
  let f = clamp((progress - holdFraction) /
                max(1.0'f32 - holdFraction, 0.001'f32), 0.0'f32, 1.0'f32)
  f * f

proc floatPop(lifetime, fade, punch, sizeScale: float32): float32 =
  ## Birth punch: the label snaps in oversized over ~0.11s and settles, then
  ## shrinks a little as it fades. The old curve peaked at MID-life, which read
  ## as a swell rather than an impact.
  let birth = clamp(lifetime / 0.11'f32, 0.0'f32, 1.0'f32)
  (1.0'f32 + (1.0'f32 - birth) * punch) * sizeScale * (1.0'f32 - fade * 0.18'f32)

proc drawFloatingLabel(text: string, centerX, centerY: float32, fontSize: int32,
                       rotation: float32, color: Color, alpha: float32,
                       glowMult: float32) =
  ## Glow pass + black outline + main text, rotated about the label's centre so
  ## a tilt turns it in place instead of swinging it sideways.
  ##
  ## raylib's plain `drawText` cannot rotate, so this goes through DrawTextPro
  ## (naylib exposes it as a `drawText` overload taking a Font) and has to
  ## reproduce DrawText's own spacing rule -- `fontSize div 10` on the default
  ## font -- or tilted labels would be letter-spaced unlike every other string
  ## in the game. The font is fetched once per label, not once per stamp.
  let size = max(fontSize, 10'i32)
  let spacing = float32(size div 10)
  let width = measureText(text, size).float32
  let font = getFontDefault()
  let origin = Vector2(x: width * 0.5, y: size.float32 * 0.5)

  template stamp(dx, dy: float32, tint: Color) =
    drawText(font, text, Vector2(x: centerX + dx, y: centerY + dy), origin,
             rotation, size.float32, spacing, tint)

  let glow = Color(r: color.r, g: color.g, b: color.b,
                   a: uint8(clamp(alpha * glowMult, 0.0'f32, 255.0'f32)))
  for dx in [-2.0'f32, 0.0'f32, 2.0'f32]:
    for dy in [-2.0'f32, 0.0'f32, 2.0'f32]:
      if dx != 0.0 or dy != 0.0:
        stamp(dx, dy, glow)

  let outline = Color(r: 0, g: 0, b: 0,
                      a: uint8(clamp(alpha * 0.8'f32, 0.0'f32, 255.0'f32)))
  for dx in [-1.0'f32, 0.0'f32, 1.0'f32]:
    for dy in [-1.0'f32, 0.0'f32, 1.0'f32]:
      if dx != 0.0 or dy != 0.0:
        stamp(dx, dy, outline)

  stamp(0.0'f32, 0.0'f32, color)

proc drawDamageNumber*(dmgNum: DamageNumber) =
  let fade = floatFade(dmgNum.lifetime, dmgNum.maxLifetime, 0.45'f32)
  let alpha = (1.0'f32 - fade) * 255.0'f32
  let popScale = floatPop(dmgNum.lifetime, fade,
                          (if dmgNum.isCritical: 0.55'f32 else: 0.34'f32),
                          dmgNum.sizeScale)

  var color: Color
  var fontSize: int32

  if dmgNum.isCritical:
    case dmgNum.damageType
    of dtFire:
      color = Color(r: 255, g: 80, b: 0, a: alpha.uint8)
    of dtPoison:
      color = Color(r: 50, g: 255, b: 50, a: alpha.uint8)
    of dtFrost:
      color = Color(r: 150, g: 220, b: 255, a: alpha.uint8)
    of dtLaser:
      color = Color(r: 150, g: 150, b: 255, a: alpha.uint8)
    of dtLightning:
      color = Color(r: 255, g: 255, b: 80, a: alpha.uint8)
    of dtArcane:
      color = Color(r: 180, g: 50, b: 200, a: alpha.uint8)
    of dtExplosion:
      color = Color(r: 255, g: 165, b: 0, a: alpha.uint8)
    of dtHeal:
      color = Color(r: 50, g: 255, b: 50, a: alpha.uint8)
    else:
      color = Color(r: 255, g: 255, b: 50, a: alpha.uint8)
    fontSize = 24
  elif dmgNum.fromPlayer:
    case dmgNum.damageType
    of dtFire:
      color = Color(r: 255, g: 80, b: 0, a: alpha.uint8)
    of dtPoison:
      color = Color(r: 50, g: 255, b: 50, a: alpha.uint8)
    of dtFrost:
      color = Color(r: 150, g: 220, b: 255, a: alpha.uint8)
    of dtLaser:
      color = Color(r: 150, g: 150, b: 255, a: alpha.uint8)
    of dtLightning:
      color = Color(r: 255, g: 255, b: 80, a: alpha.uint8)
    of dtArcane:
      color = Color(r: 180, g: 50, b: 200, a: alpha.uint8)
    of dtExplosion:
      color = Color(r: 255, g: 165, b: 0, a: alpha.uint8)
    of dtCritical:
      color = Color(r: 255, g: 255, b: 50, a: alpha.uint8)
    of dtHeal:
      color = Color(r: 50, g: 255, b: 50, a: alpha.uint8)
      if dmgNum.damage < 1.0:
        fontSize = int32(clamp(12.0 + dmgNum.damage * 4.0, 12.0, 16.0))
      else:
        fontSize = int32(clamp(16.0 + (dmgNum.damage / 5.0) * 4.0, 16.0, 24.0))
    of dtDefault:
      color = Color(r: 255, g: 255, b: 255, a: alpha.uint8)
    of dtHitCount:
      color = Color(r: 255, g: 255, b: 255, a: alpha.uint8)

    if dmgNum.damageType != dtHeal:
      fontSize = 18
  else:
    case dmgNum.damageType
    of dtFire:
      color = Color(r: 255, g: 80, b: 0, a: alpha.uint8)
    of dtPoison:
      color = Color(r: 50, g: 255, b: 50, a: alpha.uint8)
    of dtFrost:
      color = Color(r: 150, g: 220, b: 255, a: alpha.uint8)
    of dtLaser:
      color = Color(r: 200, g: 50, b: 255, a: alpha.uint8)
    of dtLightning:
      color = Color(r: 255, g: 255, b: 80, a: alpha.uint8)
    of dtArcane:
      color = Color(r: 180, g: 50, b: 200, a: alpha.uint8)
    of dtExplosion:
      color = Color(r: 255, g: 165, b: 0, a: alpha.uint8)
    of dtCritical:
      color = Color(r: 255, g: 255, b: 50, a: alpha.uint8)
    of dtHeal:
      color = Color(r: 50, g: 255, b: 50, a: alpha.uint8)
    of dtDefault:
      color = Color(r: 255, g: 150, b: 0, a: alpha.uint8)
    of dtHitCount:
      color = Color(r: 255, g: 255, b: 255, a: alpha.uint8)

    fontSize = 20

  let scaledFontSize = int32(max(12.0, fontSize.float32 * popScale))

  # Multiply damage by BALANCE_MULTIPLIER for display
  let displayDamage = dmgNum.damage * BALANCE_MULTIPLIER

  let damageText =
    if dmgNum.damageType == dtHitCount:
      $round(displayDamage).int
    elif displayDamage >= 10.0:
      $round(displayDamage).int
    elif displayDamage >= 1.0:
      formatFloat(displayDamage, ffDecimal, 1)
    else:
      formatFloat(displayDamage, ffDecimal, 2)

  let displayText = if dmgNum.isCritical: damageText & "!" else: damageText
  drawFloatingLabel(displayText, dmgNum.pos.x,
                    dmgNum.pos.y + scaledFontSize.float32 * 0.5, scaledFontSize,
                    dmgNum.rotation, color, alpha,
                    (if dmgNum.isCritical: 0.28'f32 else: 0.18'f32))

proc drawCurrencyIndicator*(indicator: CurrencyIndicator) =
  let fade = floatFade(indicator.lifetime, indicator.maxLifetime, 0.5'f32)
  let alpha = (1.0'f32 - fade) * 255.0'f32
  let popScale = floatPop(indicator.lifetime, fade, 0.30'f32, indicator.sizeScale)
  let color = case indicator.kind
    of cikCredits: Color(r: 255, g: 224, b: 84, a: alpha.uint8)
    of cikDataShards: Color(r: 95, g: 225, b: 255, a: alpha.uint8)
    of cikCores: Color(r: 255, g: 130, b: 72, a: alpha.uint8)
    of cikXp: Color(r: 120, g: 255, b: 190, a: alpha.uint8)
  let iconType = case indicator.kind
    of cikCredits: ciCredits
    of cikDataShards: ciDataShards
    of cikCores: ciCore
    of cikXp: ciXp
  let sign = if indicator.amount >= 0: "+" else: "-"
  let displayText = sign & $abs(indicator.amount)
  let scaledFontSize = int32(max(12.0, 18.0 * popScale))
  let iconSize = int32(18.0 * popScale)
  let textWidth = measureText(displayText, scaledFontSize)
  let totalWidth = iconSize + 5 + textWidth
  let x = (indicator.pos.x - totalWidth.float32 / 2.0).int32
  let y = indicator.pos.y.int32

  # The icon is drawn upright; the number carries the (deliberately small) tilt.
  drawCurrencyIcon(x + iconSize div 2, y + scaledFontSize div 2, iconSize, iconType, alpha.uint8)
  drawFloatingLabel(displayText,
                    (x + iconSize + 5).float32 + textWidth.float32 * 0.5,
                    y.float32 + scaledFontSize.float32 * 0.5, scaledFontSize,
                    indicator.rotation, color, alpha, 0.24'f32)

proc drawPerkIndicator*(indicator: PerkIndicator) =
  ## Draws a floating "+SHIELD" / "+SPEED" style consumable pickup label.
  let fade = floatFade(indicator.lifetime, indicator.maxLifetime, 0.5'f32)
  let alpha = (1.0'f32 - fade) * 255.0'f32
  let popScale = floatPop(indicator.lifetime, fade, 0.36'f32, indicator.sizeScale)
  let fontSize = int32(max(12.0, 17.0 * popScale))

  let color = withAlpha(indicator.color, alpha.uint8)
  drawFloatingLabel(indicator.text, indicator.pos.x,
                    indicator.pos.y + fontSize.float32 * 0.5, fontSize,
                    indicator.rotation, color, alpha, 0.24'f32)

