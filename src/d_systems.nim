import raylib, types, math, random

type
  ShakeIntensity* = enum
    siNone,
    siSmall,      # 0.5-1px for enemy hit
    siMedium,     # 2-3px for enemy kill
    siLarge,      # 3-5px for boss hit
    siMassive,    # 8-12px for boss kill
    siCritical,   # Double intensity for crits
    siPowerUp     # 4px for power-up collection

proc newScreenShake*(): ScreenShake =
  result = ScreenShake(
    offset: Vector2f(x: 0, y: 0),
    intensity: 0,
    duration: 0,
    maxDuration: 0,
    decayRate: 1.0,
    tintColor: Color(r: 0, g: 0, b: 0, a: 0)
  )

proc addShake*(shake: var ScreenShake, intensity: ShakeIntensity, 
               tint: Color = Color(r: 0, g: 0, b: 0, a: 0)) =
  ## Add screen shake with specified intensity and optional color tint (SUBTLE)
  case intensity
  of siNone:
    return
  of siSmall:
    shake.intensity = max(shake.intensity, float32(rand(0.2..0.4)))
    shake.duration = 0.04
  of siMedium:
    shake.intensity = max(shake.intensity, float32(rand(0.6..1.0)))
    shake.duration = 0.08
  of siLarge:
    shake.intensity = max(shake.intensity, float32(rand(1.2..1.8)))
    shake.duration = 0.12
  of siMassive:
    shake.intensity = max(shake.intensity, float32(rand(2.5..4.0)))
    shake.duration = 0.2
    shake.decayRate = 0.5  # Slower decay for dramatic effect
  of siCritical:
    shake.intensity = max(shake.intensity, float32(rand(0.5..0.8)) * 1.5)
    shake.duration = 0.06
  of siPowerUp:
    shake.intensity = max(shake.intensity, 1.5)
    shake.duration = 0.15
  
  shake.maxDuration = shake.duration
  shake.tintColor = tint

proc updateShake*(shake: var ScreenShake, dt: float32) =
  ## Update screen shake, applying decay over time
  if shake.duration > 0:
    shake.duration -= dt
    
    # Generate random offset based on intensity
    let angle = float32(rand(0.0..TAU))
    let currentIntensity = shake.intensity * (shake.duration / shake.maxDuration)
    shake.offset.x = cos(angle) * currentIntensity
    shake.offset.y = sin(angle) * currentIntensity
    
    # Apply decay
    shake.intensity *= (1.0 - shake.decayRate * dt * 10.0)
  else:
    shake.offset.x = 0
    shake.offset.y = 0
    shake.intensity = 0
    shake.tintColor.a = 0

proc getShakeOffset*(shake: ScreenShake): Vector2f =
  return shake.offset

# COMBO SYSTEM

proc newComboSystem*(): ComboSystem =
  result = ComboSystem(
    killCount: 0,
    lastKillTime: 0,
    comboWindow: 4.0,  # Extended from 2.0 to 4.0 seconds for easier combos
    displayTimer: 0,
    bonusCoins: 0,
    waveStartCombo: 0,
    perfectWaveStreak: 0,
    lastPerfectWaveBonus: 0
  )

proc getComboWindow*(combo: ComboSystem): float32 =
  ## Get the dynamic combo window based on current combo count
  ## Window gets shorter as combo increases to increase difficulty
  let baseWindow = 4.0  # Starting window
  let minWindow = 1.5   # Minimum window at high combos
  
  # Gradually decrease window: lose 0.15 seconds per combo kill
  let windowReduction = combo.killCount.float32 * 0.15
  result = max(minWindow, baseWindow - windowReduction)

proc addComboKill*(combo: var ComboSystem, currentTime: float32): int =
  ## Add a kill to combo, returns bonus coins earned
  # Get current dynamic window based on combo count BEFORE adding the kill
  let currentWindow = getComboWindow(combo)
  
  if currentTime - combo.lastKillTime <= currentWindow:
    combo.killCount += 1
  else:
    combo.killCount = 1
  
  combo.lastKillTime = currentTime
  # Store the window time that applies to THIS kill for accurate timer display
  # Recalculate window based on NEW combo count to fix timer display after resets
  combo.comboWindow = getComboWindow(combo)
  combo.displayTimer = 5.0  # Increased from 2.5 to 5.0 seconds
  
  # Calculate bonus coins
  combo.bonusCoins = 0
  if combo.killCount == 2:
    combo.bonusCoins = 1
  elif combo.killCount == 5:
    combo.bonusCoins = 5
  elif combo.killCount == 10:
    combo.bonusCoins = 10
  elif combo.killCount == 20:
    combo.bonusCoins = 25
  
  return combo.bonusCoins

proc updateCombo*(combo: var ComboSystem, dt: float32, currentTime: float32) =
  ## Update combo system with "coyote time" - players get 0.1s extra grace period
  let currentWindow = getComboWindow(combo)
  let coyoteTime = 0.1  # Extra buffer time not shown on timer (like coyote jump)
  
  # Reset combo only after window + coyote time expires
  if currentTime - combo.lastKillTime > currentWindow + coyoteTime:
    combo.killCount = 0
    combo.bonusCoins = 0
    combo.perfectWaveStreak = 0  # Reset perfect wave streak when combo breaks
  
  if combo.displayTimer > 0:
    combo.displayTimer -= dt

proc getComboMultiplier*(combo: ComboSystem): string =
  if combo.killCount >= 2:
    return $combo.killCount & "x"
  return ""

proc shouldShowCombo*(combo: ComboSystem): bool =
  return combo.displayTimer > 0 and combo.killCount >= 2

proc startWaveCombo*(combo: var ComboSystem) =
  ## Mark the start of a new wave - record current combo count
  combo.waveStartCombo = combo.killCount
  combo.lastPerfectWaveBonus = 0

proc checkPerfectWaveCombo*(combo: var ComboSystem, waveEnemyCount: int): int =
  ## Check if the wave was cleared in a single combo
  ## Returns bonus coins earned (0 if not perfect)
  ## Must have killed all enemies and maintained combo from wave start
  if combo.killCount > combo.waveStartCombo and 
     combo.killCount >= combo.waveStartCombo + waveEnemyCount:
    # Perfect wave combo achieved!
    combo.perfectWaveStreak += 1
    
    # Calculate bonus: 10 coins base + 5 per streak level
    let bonus = 10 + (combo.perfectWaveStreak - 1) * 5
    combo.lastPerfectWaveBonus = bonus
    combo.displayTimer = max(combo.displayTimer, 3.0)  # Show for at least 3 seconds
    
    return bonus
  else:
    # Wave not cleared in single combo - reset streak
    combo.perfectWaveStreak = 0
    combo.lastPerfectWaveBonus = 0
    return 0

# MILESTONE SYSTEM
proc newMilestoneManager*(): MilestoneManager =
  result = MilestoneManager(
    milestones: @[],
    showRecent: false
  )
  
  # Initialize wave milestones
  result.milestones.add(Milestone(
    milestoneType: mtWave, threshold: 5, reached: false,
    name: "FIRST BOSS DEFEATED", description: "Survived your first boss encounter",
    bonus: "+Achievement"
  ))
  result.milestones.add(Milestone(
    milestoneType: mtWave, threshold: 10, reached: false,
    name: "VETERAN SURVIVOR", description: "Reached wave 10",
    bonus: "+Achievement"
  ))
  result.milestones.add(Milestone(
    milestoneType: mtWave, threshold: 25, reached: false,
    name: "ELITE PLAYER", description: "Reached wave 25",
    bonus: "+5% permanent stats"
  ))
  
  # Initialize kill milestones
  result.milestones.add(Milestone(
    milestoneType: mtKills, threshold: 100, reached: false,
    name: "CENTURION", description: "Eliminated 100 enemies",
    bonus: "+Badge"
  ))
  result.milestones.add(Milestone(
    milestoneType: mtKills, threshold: 500, reached: false,
    name: "EXECUTIONER", description: "Eliminated 500 enemies",
    bonus: "+Badge"
  ))
  result.milestones.add(Milestone(
    milestoneType: mtKills, threshold: 1000, reached: false,
    name: "DEATH INCARNATE", description: "Eliminated 1000 enemies",
    bonus: "+Permanent red glow"
  ))
  
  # Initialize coin milestones
  result.milestones.add(Milestone(
    milestoneType: mtCoins, threshold: 1000, reached: false,
    name: "WEALTHY", description: "Collected 1000 lifetime coins",
    bonus: "+Badge"
  ))
  result.milestones.add(Milestone(
    milestoneType: mtCoins, threshold: 5000, reached: false,
    name: "TYCOON", description: "Collected 5000 lifetime coins",
    bonus: "+Badge"
  ))

proc checkMilestone*(manager: var MilestoneManager, milestoneType: MilestoneType, 
                     value: int, currentTime: float32): bool =
  ## Check if a milestone was reached, returns true if new milestone hit
  for i in 0..<manager.milestones.len:
    if manager.milestones[i].milestoneType == milestoneType and 
       not manager.milestones[i].reached and 
       value >= manager.milestones[i].threshold:
      manager.milestones[i].reached = true
      manager.milestones[i].displayTimer = 5.0
      manager.recentMilestone = manager.milestones[i]
      manager.showRecent = true
      return true
  return false

proc updateMilestones*(manager: var MilestoneManager, dt: float32) =
  for i in 0..<manager.milestones.len:
    if manager.milestones[i].displayTimer > 0:
      manager.milestones[i].displayTimer -= dt
      if manager.milestones[i].displayTimer <= 0:
        manager.showRecent = false

# MICRO-REWARD TRACKER
proc newMicroRewardTracker*(): MicroRewardTracker =
  result = MicroRewardTracker(
    lastKills: 0,
    lastDamageDealt: 0,
    rewards: @[]
  )

proc checkRewards*(tracker: var MicroRewardTracker, kills: int, 
                   damageDealt: float32, playerPos: Vector2f): seq[MicroReward] =
  ## Check for micro-rewards and return new ones
  var newRewards: seq[MicroReward] = @[]
  
  # Every 10 kills
  if kills > 0 and kills mod 10 == 0 and kills != tracker.lastKills:
    newRewards.add(MicroReward(
      message: "MASSACRE BONUS!",
      coins: 5,
      displayTimer: 2.0,
      pos: playerPos
    ))
  
  tracker.lastKills = kills
  tracker.lastDamageDealt = damageDealt
  
  return newRewards

proc addReward*(tracker: var MicroRewardTracker, reward: MicroReward) =
  tracker.rewards.add(reward)

proc updateRewards*(tracker: var MicroRewardTracker, dt: float32) =
  var i = 0
  while i < tracker.rewards.len:
    tracker.rewards[i].displayTimer -= dt
    if tracker.rewards[i].displayTimer <= 0:
      tracker.rewards.del(i)
    else:
      inc i

# SLOW-MOTION SYSTEM

proc newSlowMotion*(): SlowMotion =
  result = SlowMotion(
    active: false,
    timeScale: 1.0,
    duration: 0,
    maxDuration: 0,
    slowType: smtNone
  )

proc activateSlowMo*(slowMo: var SlowMotion, slowType: SlowMotionType) =
  ## Activate slow motion effect
  case slowType
  of smtNone:
    return
  of smtKill:
    slowMo.timeScale = 0.5
    slowMo.duration = 0.15
  of smtBossKill:
    slowMo.timeScale = 0.25
    slowMo.duration = 0.5
  of smtPowerUp:
    slowMo.timeScale = 0.01
    slowMo.duration = 0.1
  of smtWaveComplete:
    slowMo.timeScale = 0.5
    slowMo.duration = 0.3
  
  slowMo.maxDuration = slowMo.duration
  slowMo.active = true
  slowMo.slowType = slowType

proc updateSlowMo*(slowMo: var SlowMotion, dt: float32): float32 =
  ## Update slow motion, returns modified delta time
  if slowMo.active:
    slowMo.duration -= dt
    if slowMo.duration <= 0:
      slowMo.active = false
      slowMo.timeScale = 1.0
      return dt
    return dt * slowMo.timeScale
  return dt

proc getTimeScale*(slowMo: SlowMotion): float32 =
  if slowMo.active:
    return slowMo.timeScale
  return 1.0

# WAVE STATS TRACKER

proc newWaveStats*(waveNumber: int): WaveStats =
  result = WaveStats(
    waveNumber: waveNumber,
    kills: 0,
    accuracy: 0,
    topDamage: 0,
    survivalTime: 0,
    coinsEarned: 0,
    damageTaken: 0,
    shotsFired: 0,
    shotsHit: 0,
    isPerfect: true,
    maxCombo: 0
  )

proc updateStats*(stats: var WaveStats, dt: float32) =
  stats.survivalTime += dt

proc recordKill*(stats: var WaveStats, damage: float32) =
  stats.kills += 1
  if damage > stats.topDamage:
    stats.topDamage = damage

proc recordShot*(stats: var WaveStats, hit: bool) =
  stats.shotsFired += 1
  if hit:
    stats.shotsHit += 1

proc recordDamageTaken*(stats: var WaveStats, damage: float32) =
  stats.damageTaken += damage
  stats.isPerfect = false

proc recordCoin*(stats: var WaveStats) =
  stats.coinsEarned += 1

proc recordCombo*(stats: var WaveStats, combo: int) =
  if combo > stats.maxCombo:
    stats.maxCombo = combo

proc calculateAccuracy*(stats: var WaveStats) =
  if stats.shotsFired > 0:
    stats.accuracy = (stats.shotsHit.float32 / stats.shotsFired.float32) * 100.0
  else:
    stats.accuracy = 0

proc newDopamineState*(): DopamineState =
  result = DopamineState(
    screenShake: newScreenShake(),
    comboSystem: newComboSystem(),
    milestones: newMilestoneManager(),
    microRewards: newMicroRewardTracker(),
    slowMotion: newSlowMotion(),
    waveStats: newWaveStats(1),
    currentTime: 0
  )

proc updateDopamine*(dopamine: var DopamineState, dt: float32) =
  dopamine.currentTime += dt
  updateShake(dopamine.screenShake, dt)
  updateCombo(dopamine.comboSystem, dt, dopamine.currentTime)
  updateMilestones(dopamine.milestones, dt)
  updateRewards(dopamine.microRewards, dt)
  updateStats(dopamine.waveStats, dt)

proc resetWaveStats*(dopamine: var DopamineState, waveNumber: int) =
  dopamine.waveStats = newWaveStats(waveNumber)

proc getPerfectWaveBonus*(stats: WaveStats): int =
  ## Returns bonus coins for perfect wave
  if stats.isPerfect and stats.kills > 0:
    return 30
  return 0

proc getClutchBonus*(stats: WaveStats, playerHp: float32, maxHp: float32): int =
  ## Returns bonus coins if survived wave under 10% HP
  if stats.kills > 0 and playerHp < maxHp * 0.1:
    return 20
  return 0
  
# Add initialization for enhanced features  
import d_enhancements

proc initEnhancedDopamine*(dopamine: var DopamineState) =
  dopamine.waveCelebration = newWaveCelebration()
  dopamine.bossIntro = newBossIntroduction()
  dopamine.achievements = newAchievementManager()
  dopamine.realTimeStats = newRealTimeStats()
