import raylib, random, math, strutils
import particle_types, types, ui/ui_constants, ui/icon_drawing

proc newDamageNumber*(x, y: float32, damage: float32, fromPlayer: bool, isCritical: bool = false, damageType: DamageType = dtDefault): DamageNumber =
  let baseVelocityY = -80.0
  let horizontalSpread = (rand(1.0) - 0.5) * 100.0

  result = DamageNumber(
    pos: newVector2f(x, y),
    vel: newVector2f(horizontalSpread, baseVelocityY),
    damage: damage,
    lifetime: 0,
    maxLifetime: 1.5,
    fromPlayer: fromPlayer,
    isCritical: isCritical,
    damageType: damageType
  )

proc newCurrencyIndicator*(x, y: float32, amount: int,
                           kind: CurrencyIndicatorKind = cikCredits): CurrencyIndicator =
  let baseVelocityY = -76.0'f32
  # Data shards fire every wave, tighter spread so they don't wander off-screen
  let spreadRange = if kind == cikDataShards: 40.0 else: 72.0
  let horizontalSpread = (rand(1.0) - 0.5) * spreadRange
  # Shards stay visible longer since they're the most important roguelite number
  let maxLife = case kind
    of cikDataShards:        1.60'f32
    of cikOverheatCores:     1.45'f32
    of cikSingularityCores:  1.45'f32
    of cikCredits:           1.35'f32

  result = CurrencyIndicator(
    pos: newVector2f(x, y),
    vel: newVector2f(horizontalSpread, baseVelocityY),
    amount: amount,
    lifetime: 0,
    maxLifetime: maxLife,
    kind: kind
  )

proc updateDamageNumber*(dmgNum: DamageNumber, dt: float32): bool =
  dmgNum.vel.y += 200.0 * dt
  dmgNum.pos = dmgNum.pos + dmgNum.vel * dt
  dmgNum.vel.x = dmgNum.vel.x * pow(0.95, 60.0 * dt)
  dmgNum.lifetime += dt
  return dmgNum.lifetime < dmgNum.maxLifetime

proc updateCurrencyIndicator*(indicator: CurrencyIndicator, dt: float32): bool =
  indicator.vel.y += 150.0 * dt
  indicator.pos = indicator.pos + indicator.vel * dt
  indicator.vel.x = indicator.vel.x * pow(0.92, 60.0 * dt)
  indicator.lifetime += dt
  return indicator.lifetime < indicator.maxLifetime

proc drawDamageNumber*(dmgNum: DamageNumber) =
  let progress = dmgNum.lifetime / dmgNum.maxLifetime
  let alpha = (1.0 - progress) * 255.0
  let popScale = 1.0 + sin((1.0 - progress) * PI) *
    (if dmgNum.isCritical: 0.26 else: 0.12)

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
  let textWidth = measureText($displayText, scaledFontSize)
  let x = (dmgNum.pos.x - textWidth.float32 / 2.0).int32
  let y = dmgNum.pos.y.int32

  let glowColor = Color(
    r: color.r,
    g: color.g,
    b: color.b,
    a: uint8(alpha * (if dmgNum.isCritical: 0.28 else: 0.18))
  )
  for dx in [-2, 0, 2]:
    for dy in [-2, 0, 2]:
      if dx != 0 or dy != 0:
        drawText($displayText, int32(x + dx), int32(y + dy), scaledFontSize, glowColor)

  # Outline (black)
  for dx in [-1, 0, 1]:
    for dy in [-1, 0, 1]:
      if dx != 0 or dy != 0:
        drawText($displayText, int32(x + dx), int32(y + dy), scaledFontSize,
                Color(r: 0, g: 0, b: 0, a: uint8(alpha * 0.8)))

  # Main text
  drawText($displayText, x, y, scaledFontSize, color)

proc drawCurrencyIndicator*(indicator: CurrencyIndicator) =
  let progress = indicator.lifetime / indicator.maxLifetime
  let alpha = (1.0 - progress) * 255.0
  let popScale = 1.0 + sin((1.0 - progress) * PI) * 0.16
  let color = case indicator.kind
    of cikCredits: Color(r: 255, g: 224, b: 84, a: alpha.uint8)
    of cikDataShards: Color(r: 95, g: 225, b: 255, a: alpha.uint8)
    of cikOverheatCores: Color(r: 255, g: 130, b: 72, a: alpha.uint8)
    of cikSingularityCores: Color(r: 190, g: 142, b: 255, a: alpha.uint8)
  let iconType = case indicator.kind
    of cikCredits: ciCredits
    of cikDataShards: ciDataShards
    of cikOverheatCores: ciOverheatCore
    of cikSingularityCores: ciSingularityCore
  let sign = if indicator.amount >= 0: "+" else: "-"
  let displayText = sign & $abs(indicator.amount)
  let scaledFontSize = int32(max(12.0, 18.0 * popScale))
  let iconSize = int32(18.0 * popScale)
  let textWidth = measureText(displayText, scaledFontSize)
  let totalWidth = iconSize + 5 + textWidth
  let x = (indicator.pos.x - totalWidth.float32 / 2.0).int32
  let y = indicator.pos.y.int32

  let glowColor = Color(r: color.r, g: color.g, b: color.b, a: uint8(alpha * 0.24))
  for dx in [-2, 0, 2]:
    for dy in [-2, 0, 2]:
      if dx != 0 or dy != 0:
        drawText(displayText, int32(x + iconSize + 5 + dx), int32(y + dy), scaledFontSize, glowColor)

  for dx in [-1, 0, 1]:
    for dy in [-1, 0, 1]:
      if dx != 0 or dy != 0:
        drawText(displayText, int32(x + iconSize + 5 + dx), int32(y + dy), scaledFontSize,
                 Color(r: 0, g: 0, b: 0, a: uint8(alpha * 0.8)))

  drawCurrencyIcon(x + iconSize div 2, y + scaledFontSize div 2, iconSize, iconType, alpha.uint8)
  drawText(displayText, x + iconSize + 5, y, scaledFontSize, color)
