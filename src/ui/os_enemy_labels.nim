## OS-Style Enemy Labels
## Draw enemies with modern process/threat labels

import raylib, math
import ../types, ui_constants, ../localization

proc getEnemyProcessName*(enemy: Enemy): string =
  ## Generate a process name for an enemy based on type
  let baseNames = case enemy.enemyType
    of etCircle: "chaser"
    of etCube: "turret"
    of etTriangle: "dasher"
    of etStar: "tank"
    of etHexagon: "warper"
    of etCross: "crossfire"
    of etDiamond: "striker"
    of etOctagon: "spreader"
    of etPentagon: "sniper"
    of etTrickster: "deceiver"
    of etPhantom: "phantom"
    of etSniper: "railgun"
    of etMage: "summoner"
    of etEnvironment: "environment"

  if enemy.isBoss:
    return "CRITICAL_THREAT_" & $enemy.bossDefinitionID & ".exe"

  # Add elite prefix if applicable
  var prefix = ""
  if enemy.isElite:
    prefix = "ELITE_"

  # Add ID suffix for uniqueness
  let idSuffix = (enemy.id mod 1000)

  # Process extensions based on threat level
  let extensions = if enemy.isElite or enemy.isBoss:
    [".exe", ".sys", ".tmp"]
  else:
    [".exe", ".dll", ".tmp"]

  let ext = extensions[enemy.id mod extensions.len]

  result = prefix & baseNames & "_" & $idSuffix & ext

proc drawEnemyLabel*(enemy: Enemy, showHealthBar: bool = true, enabled: bool = true) =
  if not enabled or enemy.entranceTimer > 0:
    return  # Don't show label if disabled or during entrance

  let drawLabelHealthBar = showHealthBar and not enemy.isBoss
  let processName = getEnemyProcessName(enemy)
  let fontSize: int32 = if enemy.isBoss: 9 else: 7  # Even smaller fonts (was 12/10)
  let labelWidth = measureText(processName, fontSize)

  # Calculate label dimensions - much more compact
  let labelPadding = if enemy.isBoss: 4 else: 3  # Minimal padding (was 8/6)
  # Add space for icon prefix: [X]/[E] icons are ~16px, * icon is ~12px
  let iconWidth = if enemy.isBoss or enemy.isElite: 20 else: 14
  let totalWidth = labelWidth + labelPadding * 2 + iconWidth
  let labelHeight = if drawLabelHealthBar: 18 else: 14  # Much shorter (was 38/28)

  let labelX = enemy.pos.x - (totalWidth.float32 / 2.0)
  let labelClearance = if enemy.isBoss: 26.0'f32 else: 8.0'f32
  let labelY = enemy.pos.y - enemy.radius - labelHeight.float32 - labelClearance

  # Don't draw if off-screen with margin
  if labelY < -30 or labelY > 750:
    return

  # Calculate alpha based on distance from edges
  var alpha = uint8(255)
  if labelY < 20:
    alpha = uint8((labelY + 30) / 50.0 * 255.0)
  elif labelY > 700:
    alpha = uint8((750 - labelY) / 50.0 * 255.0)

  # Label shadow for depth
  if enemy.isBoss or enemy.isElite:
    drawRectangle((labelX + 2).int32, (labelY + 2).int32,
                 int32(totalWidth), int32(labelHeight),
                 Color(r: 0, g: 0, b: 0, a: uint8(alpha.float32 * 0.6)))

  # Label background with transparency
  let bgAlpha = if enemy.isBoss:
    uint8(min(uint8(240), alpha))
  elif enemy.isElite:
    uint8(min(uint8(220), alpha))
  else:
    uint8(min(uint8(190), alpha))

  let bgColor = if enemy.isBoss:
    Color(r: 40, g: 20, b: 20, a: bgAlpha)
  elif enemy.isElite:
    Color(r: 40, g: 35, b: 20, a: bgAlpha)
  else:
    Color(r: 22, g: 28, b: 38, a: bgAlpha)

  drawRectangle(labelX.int32, labelY.int32, totalWidth.int32, labelHeight.int32, bgColor)

  # Top accent bar based on threat level (toned down for elites)
  let accentColor = if enemy.isBoss:
    Color(r: 255, g: 50, b: 50, a: alpha)
  elif enemy.isElite:
    Color(r: 200, g: 170, b: 60, a: uint8(alpha.float32 * 0.8))  # Less shiny gold
  else:
    Color(r: 0, g: 180, b: 255, a: uint8(alpha.float32 * 0.8))

  let accentHeight = if enemy.isBoss or enemy.isElite: 3 else: 2
  drawRectangle(labelX.int32, labelY.int32, totalWidth.int32, accentHeight.int32, accentColor)

  # Animated glow for bosses
  if enemy.isBoss:
    let glowPulse = sin(getTime() * 4.0) * 0.4 + 0.6
    let glowAlpha = uint8(min(180.0, float32(alpha) * glowPulse))

    # Outer glow
    drawRectangleLines(
      Rectangle(x: (labelX - 2).float32, y: (labelY - 2).float32,
               width: (totalWidth + 4).float32, height: (labelHeight + 4).float32),
      1, Color(r: 255, g: 100, b: 100, a: glowAlpha)
    )

  # Label border with enhanced styling (toned down for elites)
  let borderColor = if enemy.isBoss:
    Color(r: 255, g: 80, b: 80, a: alpha)
  elif enemy.isElite:
    Color(r: 180, g: 160, b: 80, a: uint8(alpha.float32 * 0.9))  # Duller gold
  else:
    Color(r: 80, g: 100, b: 130, a: uint8(alpha.float32 * 0.9))

  let borderWidth = if enemy.isBoss: 2.0 elif enemy.isElite: 1.5 else: 1.0
  drawRectangleLines(Rectangle(x: labelX, y: labelY,
                                width: totalWidth.float32, height: labelHeight.float32),
                    borderWidth, borderColor)

  # Process name with better formatting (toned down for elites)
  let textColor = if enemy.isBoss:
    Color(r: 255, g: 120, b: 120, a: alpha)
  elif enemy.isElite:
    Color(r: 210, g: 190, b: 100, a: alpha)  # Less bright gold
  else:
    Color(r: 200, g: 210, b: 220, a: alpha)

  # Icon prefix for threat classification (simplified)
  let iconX = labelX.int32 + 3
  let iconY = labelY.int32 + 4

  if enemy.isBoss:
    drawText("[X]", iconX, iconY, fontSize, Color(r: 220, g: 80, b: 80, a: alpha))
  elif enemy.isElite:
    drawText("[E]", iconX, iconY, fontSize, Color(r: 200, g: 180, b: 80, a: alpha))
  else:
    drawText("*", iconX, iconY - 1, fontSize - 2, accentColor)

  let textX = if enemy.isBoss or enemy.isElite: iconX + 16 else: iconX + 12

  # Star enemies: show hit counter inside the label (right side)
  if enemy.enemyType == etStar:
    # Calculate remaining hits (goes down: 5/5 = full, 0/5 = dead)
    let hitsRemaining = enemy.requiredHits - enemy.hitCount
    let hitText = $(hitsRemaining) & "/" & $(enemy.requiredHits)
    let hitTextSize: int32 = 9
    let hitTextWidth = measureText(hitText, hitTextSize)

    # Position on the right side of the label
    let hitTextX = labelX + totalWidth.float32 - hitTextWidth.float32 - 6
    let hitTextY = labelY + 4

    # Draw hit counter with color based on remaining hits
    let hitPercent = hitsRemaining.float32 / enemy.requiredHits.float32
    let hitColor = if hitPercent > 0.6:
      Color(r: 255, g: 215, b: 0, a: alpha)  # Gold when healthy
    elif hitPercent > 0.3:
      Color(r: 255, g: 180, b: 0, a: alpha)  # Orange when damaged
    else:
      Color(r: 255, g: 100, b: 100, a: alpha)  # Red when critical

    # Shadow
    drawText(hitText, (hitTextX + 1).int32, (hitTextY + 1).int32, hitTextSize,
            Color(r: 0, g: 0, b: 0, a: uint8(alpha.float32 * 0.7)))
    # Main text
    drawText(hitText, hitTextX.int32, hitTextY.int32, hitTextSize, hitColor)

    drawText(processName, textX, iconY, fontSize, textColor)
  else:
    # Regular enemies: just draw the process name
    drawText(processName, textX, iconY, fontSize, textColor)

  if drawLabelHealthBar and (enemy.isElite or enemy.maxHp > 30) and enemy.enemyType != etStar:
    let barY = labelY + 14  # Closer to label (was 18)
    let barWidth = totalWidth - 6
    let barX = labelX + 3
    let hpPercent = enemy.hp / enemy.maxHp
    let barHeight = 7  # Shorter bar (was 10)

    # Bar background with depth
    drawRectangle(barX.int32, barY.int32, barWidth.int32, barHeight.int32,
                 Color(r: 30, g: 35, b: 45, a: uint8(alpha.float32 * 0.9)))

    # Bar fill with gradient effect
    let fillWidth = (barWidth.float32 * hpPercent)

    # Determine bar color based on HP percentage
    let barColor = if hpPercent > 0.7:
      Color(r: 80, g: 255, b: 120, a: alpha)
    elif hpPercent > 0.4:
      Color(r: 255, g: 220, b: 100, a: alpha)
    elif hpPercent > 0.2:
      Color(r: 255, g: 160, b: 100, a: alpha)
    else:
      Color(r: 255, g: 100, b: 100, a: alpha)

    drawRectangle(barX.int32, barY.int32, fillWidth.int32, barHeight.int32, barColor)

    # Shine effect on health bar (toned down for elites)
    let shineAlpha = if enemy.isElite:
      uint8(alpha.float32 * 0.2)  # Much less shiny
    else:
      uint8(alpha.float32 * 0.3)

    drawRectangle(barX.int32, barY.int32, fillWidth.int32, 2,
                 Color(r: 255, g: 255, b: 255, a: shineAlpha))

    # Bar border
    drawRectangleLines(Rectangle(x: barX, y: barY,
                                  width: barWidth.float32, height: barHeight.float32),
                      1, Color(r: 70, g: 85, b: 100, a: uint8(alpha.float32 * 0.8)))

    # HP text for bosses and elites - smaller text (multiplied by 100, showing decimals)
    if enemy.isBoss or enemy.isElite:
      let hpText = formatHealthDisplay(enemy.hp) & "/" & formatHealthDisplay(enemy.maxHp)
      let hpTextSize: int32 = 7  # Smaller font (was 8)
      let hpTextWidth = measureText(hpText, hpTextSize)
      let hpTextX = barX + (float32(barWidth) - hpTextWidth.float32) / 2

      # Text shadow
      drawText(hpText, (hpTextX + 1).int32, (barY + 1).int32, hpTextSize.int32,
              Color(r: 0, g: 0, b: 0, a: uint8(alpha.float32 * 0.7)))
      drawText(hpText, hpTextX.int32, barY.int32, hpTextSize.int32, White)

proc drawEnemyWarningIndicator*(enemy: Enemy) =
  ## Draw warning indicator for dangerous enemies
  if not (enemy.isElite or enemy.isBoss):
    return

  # Calculate warning position above label
  let warningY = enemy.pos.y - enemy.radius - 58

  # Don't draw if too far off-screen
  if warningY < -60 or warningY > 780:
    return

  # Subtle pulsing effect (toned down)
  let pulse = sin(getTime() * 4.0) * 0.2 + 0.7  # Slower
  let alpha = uint8(100 + pulse * 80)  # Less bright

  let warningColor = if enemy.isBoss:
    Color(r: 220, g: 60, b: 60, a: alpha)
  else:
    Color(r: 200, g: 170, b: 60, a: alpha)  # Duller gold for elites

  # Warning icon
  let iconX = enemy.pos.x
  let iconY = warningY
  let iconSize = if enemy.isBoss: 14 else: 10

  # Single subtle glow
  let glowSize = iconSize + 4
  let glowAlpha = uint8(alpha.float32 * 0.3)
  let glowColor = if enemy.isBoss:
    Color(r: 220, g: 80, b: 80, a: glowAlpha)
  else:
    Color(r: 200, g: 170, b: 60, a: glowAlpha)

  drawCircle(iconX.int32, iconY.int32, (glowSize div 2).float32, glowColor)

  # Warning triangle (no exclamation mark)
  let size = if enemy.isBoss: 9.0 else: 7.0
  let x = iconX
  let y = iconY

  drawTriangle(
    Vector2(x: x, y: y + size),              # Bottom point
    Vector2(x: x - size, y: y - size),       # Top left
    Vector2(x: x + size, y: y - size),       # Top right
    warningColor
  )

proc drawThreatCounter*(screenWidth, screenHeight: int32, threatCount: int) =
  let counterWidth = 240
  let counterHeight = 40
  let counterX = 12
  let counterY = screenHeight - counterHeight - 12

  # Counter shadow
  drawRectangle(int32(counterX + 2), int32(counterY + 2), int32(counterWidth), int32(counterHeight),
               Color(r: 0, g: 0, b: 0, a: 100))

  # Background with threat-level color tint
  let bgTint = if threatCount > 20:
    Color(r: 35, g: 20, b: 20, a: 230)
  elif threatCount > 10:
    Color(r: 35, g: 30, b: 20, a: 230)
  else:
    Color(r: 20, g: 30, b: 25, a: 230)

  drawRectangle(int32(counterX), int32(counterY), int32(counterWidth), int32(counterHeight), bgTint)

  # Top accent bar
  let accentColor = if threatCount > 20:
    Color(r: 255, g: 50, b: 50, a: 255)
  elif threatCount > 10:
    Color(r: 255, g: 165, b: 0, a: 255)
  else:
    Color(r: 100, g: 220, b: 120, a: 255)

  drawRectangle(int32(counterX), int32(counterY), int32(counterWidth), 3, accentColor)

  # Border with glow for high threats
  let borderWidth = if threatCount > 15: 2.0 else: 1.5
  drawRectangleLines(Rectangle(x: counterX.float32, y: counterY.float32,
                                width: counterWidth.float32, height: counterHeight.float32),
                    borderWidth, accentColor)

  # Animated pulse for high threat levels
  if threatCount > 15:
    let pulse = sin(getTime() * 5.0) * 0.3 + 0.7
    let pulseAlpha = uint8(100 * pulse)
    drawRectangleLines(
      Rectangle(x: (counterX - 2).float32, y: (counterY - 2).float32,
               width: (counterWidth + 4).float32, height: (counterHeight + 4).float32),
      1, Color(r: 255, g: 100, b: 100, a: pulseAlpha)
    )

  # Warning icon with animation
  let iconX = counterX + 12
  let iconY = counterY + 10
  let iconPulse = if threatCount > 15: sin(getTime() * 8.0) * 0.3 + 0.7 else: 1.0

  drawText("[!]", int32(iconX), int32(iconY), int32(20),
          Color(r: uint8(accentColor.r.float32 * iconPulse),
                g: uint8(accentColor.g.float32 * iconPulse),
                b: uint8(accentColor.b.float32 * iconPulse),
                a: 255))

  # Threat count label
  drawText(t("enemy_active_threats") & ":", int32(iconX + 35), int32(counterY + 8), 12,
          Color(r: 180, g: 190, b: 200, a: 255))

  # Threat number with emphasis
  let countText = $threatCount
  let countWidth = measureText(countText, 20)
  let countX = counterX + counterWidth - countWidth - 15

  # Shadow for number
  drawText(countText, int32(countX + 1), int32(counterY + 10), 20,
          Color(r: 0, g: 0, b: 0, a: 150))

  # Number with color based on threat level
  let numberColor = if threatCount > 20:
    Color(r: 255, g: 100, b: 100, a: 255)
  elif threatCount > 10:
    Color(r: 255, g: 200, b: 100, a: 255)
  else:
    Color(r: 150, g: 255, b: 150, a: 255)

  drawText(countText, int32(countX), int32(counterY + 9), 20, numberColor)

  # Severity indicator bar
  let barY = counterY + counterHeight - 8
  let barWidth = counterWidth - 20
  let barX = counterX + 10

  let severityPercent = min(1.0, threatCount.float32 / 30.0)
  let barFillWidth = (barWidth.float32 * severityPercent).int32

  # Bar background
  drawRectangle(int32(barX), int32(barY), int32(barWidth), 4,
               Color(r: 30, g: 35, b: 40, a: 255))

  # Bar fill
  drawRectangle(int32(barX), int32(barY), barFillWidth, 4, accentColor)

  # Bar border
  drawRectangleLines(Rectangle(x: barX.float32, y: barY.float32,
                                width: barWidth.float32, height: 4.0),
                    1, Color(r: 70, g: 80, b: 90, a: 255))
