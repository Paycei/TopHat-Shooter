import raylib, types, boss_definitions, localization

type
  DamageDisplayType* = enum
    ddtNormal,      # Standard damage number
    ddtCritical,    # Critical hit - HUGE yellow with stars
    ddtOverkill,    # Overkill - Red "OVERKILL!" text
    ddtCombo,       # Combo hit - Stacking numbers
    ddtElemental    # Elemental - Color-coded with trails

proc getEnhancedDamageInfo*(damage: float32, maxHp: float32, isCrit: bool,
                            isCombo: bool, elementType: ElementType): tuple[
  displayType: DamageDisplayType,
  text: string,
  fontSize: int32,
  color: Color
] =
  ## Determine how damage should be displayed based on context

  # Check for overkill (damage > 150% of max HP)
  if damage > maxHp * 1.5:
    return (
      ddtOverkill,
      "OVERKILL!",
      36,
      Color(r: 255, g: 0, b: 0, a: 255)
    )

  # Check for critical
  if isCrit:
    let size = int32(24 + min(damage / 10.0, 20.0))  # Scale with damage
    return (
      ddtCritical,
      $int(damage),
      size,
      Color(r: 255, g: 255, b: 50, a: 255)
    )

  # Check for combo
  if isCombo:
    return (
      ddtCombo,
      $int(damage),
      22,
      Color(r: 255, g: 150, b: 0, a: 255)
    )

  # Elemental damage
  if elementType != etNone:
    let elemColor = case elementType
      of etFire: Color(r: 255, g: 80, b: 0, a: 255)
      of etPoison: Color(r: 50, g: 255, b: 50, a: 255)
      of etLightning: Color(r: 255, g: 255, b: 80, a: 255)
      of etFrost: Color(r: 100, g: 200, b: 255, a: 255)
      of etWind: Color(r: 200, g: 255, b: 255, a: 255)
      of etArcane: Color(r: 180, g: 50, b: 200, a: 255)
      of etBlood: Color(r: 200, g: 0, b: 0, a: 255)
      else: White

    return (
      ddtElemental,
      $int(damage),
      18,
      elemColor
    )

  # Normal damage
  let size = int32(16 + min(damage / 20.0, 8.0))  # Slight scaling
  return (
    ddtNormal,
    $int(damage),
    size,
    White
  )

# WAVE CELEBRATION SYSTEM
proc newWaveCelebration*(): WaveCelebration =
  result = WaveCelebration(
    active: false,
    animationTimer: 0,
    maxAnimationTime: 1.5,
    waveNumber: 0,
    showStats: false,
    statsRevealTimer: 0
  )

proc startCelebration*(celebration: var WaveCelebration, waveNum: int, stats: WaveStats) =
  celebration.active = true
  celebration.animationTimer = 0
  celebration.waveNumber = waveNum
  celebration.stats = stats
  celebration.showStats = false
  celebration.statsRevealTimer = 0

proc updateCelebration*(celebration: var WaveCelebration, dt: float32): bool =
  ## Update celebration, returns true if still active
  if not celebration.active:
    return false

  celebration.animationTimer += dt

  # Show stats after 0.3 seconds (faster reveal)
  if celebration.animationTimer > 0.3:
    celebration.showStats = true
    celebration.statsRevealTimer = celebration.animationTimer - 0.3

  if celebration.animationTimer >= celebration.maxAnimationTime:
    celebration.active = false
    return false

  return true

proc drawWaveCelebration*(celebration: WaveCelebration, screenWidth, screenHeight: int32) =
  if not celebration.active:
    return

  let progress = celebration.animationTimer / celebration.maxAnimationTime

  # Draw darkened background
  drawRectangle(0, 0, screenWidth, screenHeight,
    Color(r: 0, g: 0, b: 0, a: uint8(100 * (1.0 - progress))))

  # Main text with slide-in animation
  let slideProgress = min(1.0, celebration.animationTimer * 3.0)
  let waveText = if isBossWave(celebration.waveNumber):
    t(tkBossDefeatedText) & " " & $getCustomBossNumber(celebration.waveNumber) & " DEFEATED"
  else:
    t(tkWaveClearedText) & " " & $celebration.waveNumber & " CLEARED"
  let textWidth = measureText(waveText, 48.int32)
  let textX = int32((screenWidth.float32 - textWidth.float32) * slideProgress)
  let textY = screenHeight div 2 - 100

  # Draw text with glow effect
  for offsetX in [-2, 0, 2]:
    for offsetY in [-2, 0, 2]:
      if offsetX != 0 or offsetY != 0:
        drawText(waveText, int32(textX + offsetX), int32(textY + offsetY), 48.int32,
          Color(r: 255, g: 215, b: 0, a: 50))

  drawText(waveText, textX, textY, 48.int32,
    Color(r: 255, g: 215, b: 0, a: 255))

  # Draw stats if revealed
  if celebration.showStats:
    let statsAlpha = uint8(min(celebration.statsRevealTimer * 255.0, 255.0))
    let statsY = textY + 80
    let centerX = screenWidth div 2

    # Stats box background
    let boxWidth = 400
    let boxHeight = 200
    let boxX = centerX - (boxWidth div 2)

    drawRectangle(int32(boxX), statsY, int32(boxWidth), int32(boxHeight),
      Color(r: 20, g: 20, b: 40, a: uint8(min(statsAlpha, 200))))
    drawRectangleLines(int32(boxX), statsY, int32(boxWidth), int32(boxHeight),
      Color(r: 255, g: 215, b: 0, a: statsAlpha))

    # Draw stats
    var lineY = statsY + 20
    let lineHeight = 30.int32

    proc drawStat(label: string, value: string, y: int32, alpha: uint8) =
      let labelText = label & ":"
      let valueText = value
      drawText(labelText, int32(boxX + 20), y, 18.int32,
        Color(r: 200, g: 200, b: 200, a: alpha))
      let valueWidth = measureText(valueText, 18.int32)
      drawText(valueText, int32(boxX + boxWidth - valueWidth - 20), y, 18.int32,
        Color(r: 255, g: 255, b: 255, a: alpha))

    drawStat(t(tkWaveCelebKills), $celebration.stats.kills, lineY, statsAlpha)
    lineY += lineHeight
    drawStat(t(tkWaveCelebAccuracy), $(int(celebration.stats.accuracy)) & "%", lineY, statsAlpha)
    lineY += lineHeight
    drawStat(t(tkWaveCelebTime), $(int(celebration.stats.survivalTime)) & "s", lineY, statsAlpha)
    lineY += lineHeight
    drawStat(t(tkWaveCelebCoins), $celebration.stats.coinsEarned, lineY, statsAlpha)
    lineY += lineHeight

    if celebration.stats.maxCombo > 1:
      drawStat(t(tkWaveCelebMaxCombo), $(celebration.stats.maxCombo) & "x", lineY, statsAlpha)

# BOSS INTRODUCTION SYSTEM
proc newBossIntroduction*(): BossIntroduction =
  result = BossIntroduction(
    active: false,
    timer: 0,
    maxTime: 1.5,
    bossName: "",
    bossTitle: "",
    bossHp: 0,
    phase: 0
  )

proc startIntroduction*(intro: var BossIntroduction, name: string, title: string, hp: float32) =
  intro.active = true
  intro.timer = 0
  intro.bossName = name
  intro.bossTitle = title
  intro.bossHp = hp
  intro.phase = 0

proc updateIntroduction*(intro: var BossIntroduction, dt: float32): bool =
  ## Update introduction, returns true if still active
  if not intro.active:
    return false

  intro.timer += dt

  # Phase transitions (adjusted for 1.5s total duration)
  if intro.timer > 0.3 and intro.phase == 0:
    intro.phase = 1  # Name appears
  elif intro.timer > 1.0 and intro.phase == 1:
    intro.phase = 2  # Ready to fight

  if intro.timer >= intro.maxTime:
    intro.active = false
    return false

  return true

proc drawBossIntroduction*(intro: BossIntroduction, screenWidth, screenHeight: int32) =
  if not intro.active:
    return

  # Darken screen slightly
  let vignetteAlpha = if intro.phase == 0:
    uint8(min(intro.timer * 400.0, 100.0))
  else:
    uint8(100)

  drawRectangle(0, 0, screenWidth, screenHeight,
    Color(r: 0, g: 0, b: 0, a: vignetteAlpha))

  # Draw boss name and title if phase 1+
  if intro.phase >= 1:
    let nameAlpha = uint8(min((intro.timer - 0.5) * 255.0, 255.0))
    let centerY = screenHeight div 2

    # Boss name - simple, no glitch
    let nameText = intro.bossName
    let nameWidth = measureText(nameText, 48.int32)
    let nameX = (screenWidth div 2) - (nameWidth div 2)

    # Draw name with simple shadow
    drawText(nameText, int32(nameX + 2), int32(centerY - 38), 48.int32,
      Color(r: 0, g: 0, b: 0, a: uint8(nameAlpha div 2)))

    drawText(nameText, int32(nameX), int32(centerY - 40), 48.int32,
      Color(r: 255, g: 100, b: 100, a: nameAlpha))

    # Boss title
    let titleText = intro.bossTitle
    let titleWidth = measureText(titleText, 20.int32)
    let titleX = (screenWidth div 2) - (titleWidth div 2)

    drawText(titleText, titleX, centerY + 20, 20.int32,
      Color(r: 180, g: 180, b: 180, a: nameAlpha))

# ACHIEVEMENT POPUP SYSTEM

proc newAchievementManager*(): AchievementManager =
  result = AchievementManager(
    achievements: @[],
    showRecent: false
  )

  # Initialize built-in achievements
  result.achievements.add(Achievement(
    id: "first_blood",
    name: "First Blood",
    description: "Kill your first enemy",
    icon: "sword",
    unlocked: false
  ))

  result.achievements.add(Achievement(
    id: "bulletstorm",
    name: "Bulletstorm",
    description: "Fire 1000 bullets",
    icon: "bullet",
    unlocked: false
  ))

  result.achievements.add(Achievement(
    id: "untouchable",
    name: "Untouchable",
    description: "Complete a wave without taking damage",
    icon: "shield",
    unlocked: false
  ))

  result.achievements.add(Achievement(
    id: "boss_slayer",
    name: "Boss Slayer",
    description: "Defeat 10 bosses",
    icon: "boss",
    unlocked: false
  ))

  result.achievements.add(Achievement(
    id: "centurion",
    name: "Centurion",
    description: "Kill 100 enemies",
    icon: "100",
    unlocked: false
  ))

  result.achievements.add(Achievement(
    id: "wealthy",
    name: "Wealthy",
    description: "Collect 1000 coins",
    icon: "coin",
    unlocked: false
  ))

proc unlockAchievement*(manager: var AchievementManager, achievementId: string): bool =
  ## Unlock an achievement, returns true if newly unlocked
  for i in 0..<manager.achievements.len:
    if manager.achievements[i].id == achievementId and not manager.achievements[i].unlocked:
      manager.achievements[i].unlocked = true
      manager.achievements[i].justUnlocked = true
      manager.achievements[i].displayTimer = 3.0
      manager.recentAchievement = manager.achievements[i]
      manager.showRecent = true
      return true
  return false

proc updateAchievements*(manager: var AchievementManager, dt: float32) =
  for i in 0..<manager.achievements.len:
    if manager.achievements[i].justUnlocked and manager.achievements[i].displayTimer > 0:
      manager.achievements[i].displayTimer -= dt
      if manager.achievements[i].displayTimer <= 0:
        manager.achievements[i].justUnlocked = false
        manager.showRecent = false

proc drawAchievementPopup*(manager: AchievementManager, screenWidth, screenHeight: int32) =
  if not manager.showRecent:
    return

  let achievement = manager.recentAchievement
  if achievement.displayTimer <= 0:
    return

  # Slide in from bottom-right
  let slideProgress = min(1.0, (3.0 - achievement.displayTimer) * 4.0)
  let boxWidth = 350
  let boxHeight = 100
  let targetX = screenWidth - boxWidth - 20
  let startX = screenWidth
  let currentX = int32(startX.float32 + (targetX.float32 - startX.float32) * slideProgress)
  let y = int32(screenHeight - boxHeight - 20)

  # Draw background
  drawRectangle(currentX, y, int32(boxWidth), int32(boxHeight),
    Color(r: 20, g: 20, b: 40, a: 230))
  drawRectangleLines(currentX, y, int32(boxWidth), int32(boxHeight),
    Color(r: 255, g: 215, b: 0, a: 255))

  # Header
  let headerText = t(tkAchievementUnlocked)
  drawText(headerText, currentX + 10, y + 10, 16.int32,
    Color(r: 255, g: 215, b: 0, a: 255))

  # Achievement name
  drawText(achievement.name, currentX + 10, y + 35, 22.int32,
    White)

  # Description
  drawText(achievement.description, currentX + 10, y + 65, 14.int32,
    Color(r: 180, g: 180, b: 180, a: 255))

# REAL-TIME STATS HUD
proc newRealTimeStats*(): RealTimeStats =
  result = RealTimeStats(
    dps: 0,
    damageDealt: 0,
    lastDamageTime: 0,
    kills: 0,
    coinsPerMinute: 0,
    totalCoins: 0,
    lastCoinTime: 0,
    powerLevel: 100
  )
  # Initialize damage history for rolling window
  result.damageHistory = @[]

proc recordDamage*(stats: var RealTimeStats, damage: float32, currentTime: float32) =
  stats.damageDealt += damage

  # Add damage event to history with timestamp
  stats.damageHistory.add((currentTime, damage))

  # Remove damage events older than 5 seconds (rolling window)
  while stats.damageHistory.len > 0 and
        currentTime - stats.damageHistory[0][0] > 5.0:
    stats.damageHistory.delete(0)

  # Calculate DPS from rolling 5-second window
  var windowDamage = 0.0
  for entry in stats.damageHistory:
    windowDamage += entry[1]

  # Use actual window duration (up to 5 seconds)
  let windowDuration = if stats.damageHistory.len > 0:
    min(5.0, currentTime - stats.damageHistory[0][0])
  else:
    1.0

  stats.dps = windowDamage / max(windowDuration, 1.0)
  stats.lastDamageTime = currentTime

proc recordKill*(stats: var RealTimeStats) =
  stats.kills += 1

proc recordCoin*(stats: var RealTimeStats, currentTime: float32) =
  stats.totalCoins += 1
  stats.lastCoinTime = currentTime

  # Calculate coins per minute
  if currentTime > 0:
    stats.coinsPerMinute = (stats.totalCoins.float32 / currentTime) * 60.0

proc calculatePowerLevel*(stats: var RealTimeStats, player: Player) =
  ## Calculate overall power level based on stats and upgrades
  var power = 100
  power += player.powerUps.len * 50
  power += int(player.damage * 10.0)
  power += int(player.maxHp * 5.0)
  stats.powerLevel = power

proc drawRealTimeStats*(stats: RealTimeStats, screenWidth, screenHeight: int32) =
  let panelX = screenWidth - 230
  let panelY = 50.int32
  let lineHeight = 25.int32
  var currentY = panelY

  # Semi-transparent background
  drawRectangle(panelX - 10, panelY - 10, 220.int32, 170.int32,
    Color(r: 0, g: 0, b: 0, a: 150))
  drawRectangleLines(panelX - 10, panelY - 10, 220.int32, 170.int32,
    Color(r: 100, g: 100, b: 100, a: 200))

  # Power Level with glow if high
  let powerText = t(tkRealStatsPower) & ": " & $stats.powerLevel
  let powerColor = if stats.powerLevel > 500:
    Color(r: 255, g: 215, b: 0, a: 255)
  else:
    Color(r: 200, g: 200, b: 200, a: 255)

  drawText(powerText, panelX, currentY, 20.int32, powerColor)
  currentY += lineHeight

  # DPS
  let dpsText = t(tkRealStatsDPS) & ": " & $(int(stats.dps))
  drawText(dpsText, panelX, currentY, 18.int32,
    Color(r: 255, g: 100, b: 100, a: 255))
  currentY += lineHeight

  # Kills
  let killsText = t(tkRealStatsKills) & ": " & $stats.kills
  drawText(killsText, panelX, currentY, 18.int32,
    Color(r: 200, g: 200, b: 200, a: 255))
  currentY += lineHeight

  # Coins per minute
  let cpmText = t(tkRealStatsCPM) & ": " & $(int(stats.coinsPerMinute))
  drawText(cpmText, panelX, currentY, 18.int32,
    Color(r: 255, g: 215, b: 0, a: 255))
