## OS-Style HUD System

import raylib, math
import ../types, ../localization, ui_constants, icon_drawing

const
  PANEL_PADDING = 10
  TITLE_BAR_HEIGHT = 24
  HEADER_BG_COLOR = Color(r: 15, g: 20, b: 30, a: 120)
  ACCENT_COLOR = Color(r: 0, g: 200, b: 255, a: 255)
  ACCENT_DIM = Color(r: 0, g: 150, b: 200, a: 180)

proc newOSHUD*(): OSHUDState =
  result = OSHUDState(panelPulse: 0.0, minimized: false)

proc updateOSHUD*(hud: var OSHUDState, dt: float32) =
  hud.panelPulse += dt

proc drawStatusPanel*(player: Player, x, y: int32, hud: OSHUDState) =
  let panelWidth: int32 = 280
  let panelHeight: int32 = if hud.minimized: TITLE_BAR_HEIGHT else: 170

  # Panel background with gradient effect
  drawRectangle(x, y, panelWidth, panelHeight,
               Color(r: 10, g: 15, b: 22, a: 85))

  # Accent stripe on right edge for symmetry with left panel
  drawRectangle(x + panelWidth - 3, y, 3, panelHeight, ACCENT_COLOR)

  # Title bar with header background
  drawRectangle(x, y, panelWidth - 3, TITLE_BAR_HEIGHT, HEADER_BG_COLOR)

  # Title text with shadow for readability
  drawText(t(tkHUDSystemStatus), x + 9, y + 5, 13, Color(r: 0, g: 0, b: 0, a: 140))
  drawText(t(tkHUDSystemStatus), x + 8, y + 4, 13, ACCENT_COLOR)

  # Border with glow effect
  drawRectangleLines(x, y, panelWidth, panelHeight,
                    Color(r: 0, g: 200, b: 255, a: 140))

  if not hud.minimized:
    var yOffset = y + TITLE_BAR_HEIGHT + PANEL_PADDING

    # HP Bar (System Integrity) with enhanced styling
    drawText(t(tkHUDIntegrity), x + PANEL_PADDING + 1, yOffset + 1, 11,
           Color(r: 0, g: 0, b: 0, a: 140))
    drawText(t(tkHUDIntegrity), x + PANEL_PADDING, yOffset, 11,
            Color(r: 180, g: 200, b: 220, a: 255))
    yOffset += 16

    let hpPercent = player.hp / player.maxHp
    let barWidth: int32 = panelWidth - (PANEL_PADDING * 2) - 6
    let barHeight: int32 = 24

    # Bar background with depth
    drawRectangle(x + PANEL_PADDING + 3, yOffset, barWidth, barHeight,
                 Color(r: 10, g: 15, b: 20, a: 120))

    # Bar fill
    let fillWidth = (barWidth.float32 * hpPercent).int32
    let barColor = if hpPercent > 0.6:
      Color(r: 0, g: 255, b: 100, a: 200)
    elif hpPercent > 0.3:
      Color(r: 255, g: 220, b: 0, a: 200)
    else:
      Color(r: 255, g: 80, b: 80, a: 200)

    drawRectangle(x + PANEL_PADDING + 3, yOffset, fillWidth, barHeight, barColor)

    # Singularity shield overlay, purple tint on the top portion of the HP bar
    # that the shield currently protects (drawn on top of the HP fill).
    if player.singularityShield > 0.0:
      # Shield covers the topmost min(shield, hp) HP worth of the bar
      let shieldCoveredHp  = min(player.singularityShield, player.hp)
      let shieldBarWidth   = (barWidth.float32 * (shieldCoveredHp / player.maxHp)).int32
      let shieldBarX       = x + PANEL_PADDING + 3 + fillWidth - shieldBarWidth
      # Solid purple layer so it's always clearly visible
      drawRectangle(shieldBarX, yOffset, shieldBarWidth, barHeight,
                   Color(r: 155, g: 80, b: 255, a: 160))
      # Bright top edge line for crispness
      drawRectangle(shieldBarX, yOffset, shieldBarWidth, 2,
                   Color(r: 210, g: 170, b: 255, a: 220))

    # Segment tick marks at each integer HP boundary
    let maxHpInt = max(1, player.maxHp.int)
    for seg in 1..<maxHpInt:
      let tickX = x + PANEL_PADDING + 3 + int32(barWidth.float32 * (seg.float32 / player.maxHp))
      let tickAlpha: uint8 = 100
      drawLine(tickX, yOffset + 2, tickX, yOffset + barHeight - 2,
               Color(r: 0, g: 0, b: 0, a: tickAlpha))

    let hpText = formatHealthDisplay(player.hp) & " / " & formatHealthDisplay(player.maxHp)
    let hpTextWidth = measureText(hpText, 14)
    let hpTextX = x + PANEL_PADDING + 3 + (barWidth div 2) - (hpTextWidth div 2)
    drawText(hpText, hpTextX + 1, yOffset + 6, 14,
            Color(r: 0, g: 0, b: 0, a: 180))
    drawText(hpText, hpTextX, yOffset + 5, 14,
            Color(r: 255, g: 255, b: 255, a: 255))

    # Bar border with glow
    drawRectangleLines(Rectangle(x: (x + PANEL_PADDING + 3).float32, y: yOffset.float32,
                                  width: barWidth.float32, height: barHeight.float32),
                      1, ACCENT_DIM)

    yOffset += barHeight + 12

    # Stats row with icons and enhanced layout
    # Background for stats section
    drawRectangle(x + PANEL_PADDING + 3, yOffset - 4, barWidth, 60,
                 Color(r: 15, g: 20, b: 28, a: 70))

    # Charges (Walls)
    drawText(t(tkHUDCharges), x + PANEL_PADDING + 8, yOffset + 1, 10,
           Color(r: 0, g: 0, b: 0, a: 140))
    drawText(t(tkHUDCharges), x + PANEL_PADDING + 7, yOffset, 10,
            Color(r: 180, g: 200, b: 220, a: 255))

    let chargesText = $player.walls & " / 6"
    let chargesColor = if player.walls > 3:
      Color(r: 0, g: 220, b: 140, a: 255)
    elif player.walls > 0:
      Color(r: 255, g: 220, b: 100, a: 255)
    else:
      Color(r: 160, g: 160, b: 160, a: 255)

    # Charges background indicator
    drawRectangle(x + PANEL_PADDING + 7, yOffset + 14, 80, 18,
                 Color(r: 0, g: 0, b: 0, a: 60))

    drawText(chargesText, x + PANEL_PADDING + 13, yOffset + 18, 14,
            Color(r: 0, g: 0, b: 0, a: 150))
    drawText(chargesText, x + PANEL_PADDING + 12, yOffset + 17, 14, chargesColor)

    # Processes count
    let processCount = player.powerUps.len
    let processX = x + PANEL_PADDING + 100

    drawText(t(tkHUDProcesses), processX + 1, yOffset + 1, 10,
           Color(r: 0, g: 0, b: 0, a: 140))
    drawText(t(tkHUDProcesses), processX, yOffset, 10,
            Color(r: 180, g: 200, b: 220, a: 255))

    let processText = $processCount & " active"
    let processColor = if processCount > 5:
      Color(r: 80, g: 160, b: 255, a: 255)
    elif processCount > 0:
      Color(r: 120, g: 255, b: 140, a: 255)
    else:
      Color(r: 160, g: 160, b: 160, a: 255)

    # Process background indicator
    drawRectangle(processX, yOffset + 14, 80, 18,
                 Color(r: 0, g: 0, b: 0, a: 60))

    drawText(processText, processX + 6, yOffset + 18, 12,
            Color(r: 0, g: 0, b: 0, a: 150))
    drawText(processText, processX + 5, yOffset + 17, 12, processColor)

    yOffset += 38

    # Coins (Cache) with enhanced styling
    drawText(t(tkHUDCache), x + PANEL_PADDING + 8, yOffset + 1, 10,
           Color(r: 0, g: 0, b: 0, a: 140))
    drawText(t(tkHUDCache), x + PANEL_PADDING + 7, yOffset, 10,
            Color(r: 180, g: 200, b: 220, a: 255))

    let coinText = $player.coins & " credits"

    # Coin background indicator
    drawRectangle(x + PANEL_PADDING + 7, yOffset + 14, 100, 18,
                 Color(r: 50, g: 40, b: 0, a: 60))
    drawCurrencyIcon(x + PANEL_PADDING + 18, yOffset + 23, 16, ciCredits)

    drawText(coinText, x + PANEL_PADDING + 30, yOffset + 18, 13,
            Color(r: 0, g: 0, b: 0, a: 150))
    drawText(coinText, x + PANEL_PADDING + 29, yOffset + 17, 13,
            Color(r: 255, g: 220, b: 0, a: 255))

proc drawPerformanceMetrics*(game: Game, x, y: int32) =
  let panelWidth: int32 = 180
  let panelHeight: int32 = 100

  # Panel background
  drawRectangle(x, y, panelWidth, panelHeight,
               Color(r: 15, g: 20, b: 30, a: 180))

  # Title bar
  drawRectangle(x, y, panelWidth, TITLE_BAR_HEIGHT,
               Color(r: 25, g: 30, b: 45, a: 220))

  drawText(t(tkHUDPerformance), x + 8, y + 5, 14, Color(r: 0, g: 200, b: 200, a: 255))

  # Border
  drawRectangleLines(x, y, panelWidth, panelHeight,
                    Color(r: 0, g: 200, b: 200, a: 255))

  var yOffset = y + TITLE_BAR_HEIGHT + PANEL_PADDING

  # Wave number
  drawText(t(tkHUDWave) & " " & $game.currentWave, x + PANEL_PADDING, yOffset, 14, Color(r: 255, g: 255, b: 255, a: 255))
  yOffset += 18

  # Uptime
  let minutes = (game.time / 60.0).int
  let seconds = (game.time mod 60.0).int
  let timeText = (if minutes < 10: "0" else: "") & $minutes & ":" &
                 (if seconds < 10: "0" else: "") & $seconds
  drawText(t(tkHUDUptime) & " " & timeText, x + PANEL_PADDING, yOffset, 14, Color(r: 255, g: 255, b: 255, a: 255))
  yOffset += 18

  # Threat count
  let threatCount = game.enemies.len
  let threatColor = if threatCount > 20: Color(r: 255, g: 0, b: 0, a: 255)  # Red
                   elif threatCount > 10: Color(r: 255, g: 165, b: 0, a: 255)  # Orange
                   else: Color(r: 0, g: 255, b: 0, a: 255)  # Green
  drawText(t("hud_threats") & ": " & $threatCount, x + PANEL_PADDING, yOffset, 14, threatColor)

