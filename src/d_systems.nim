import raylib, math, random
import particle_types, types, localization

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
  ## Add screen shake with specified intensity and optional color tint.
  ##
  ## These used to be tuned "SUBTLE": a kill moved the camera 0.6-1.0 px and a
  ## BOSS kill 2.5-4.0 px. On the 1024x768 world that is at or below the
  ## threshold of perception -- the shake was computed, translated, and drawn,
  ## and the player saw nothing. The scale below is roughly 3.5x the old one,
  ## which puts a regular kill at ~3 px (felt, not distracting) and a boss kill
  ## at ~12 px (unmistakable). Durations are stretched slightly to match, since
  ## a 0.08 s shake is only ~5 frames and reads as a single jolt.
  case intensity
  of siNone:
    return
  of siSmall:
    shake.intensity = max(shake.intensity, float32(rand(0.9..1.6)))
    shake.duration = 0.06
  of siMedium:
    shake.intensity = max(shake.intensity, float32(rand(2.2..3.4)))
    shake.duration = 0.11
  of siLarge:
    shake.intensity = max(shake.intensity, float32(rand(4.5..6.5)))
    shake.duration = 0.17
  of siMassive:
    shake.intensity = max(shake.intensity, float32(rand(9.0..13.0)))
    shake.duration = 0.3
    shake.decayRate = 0.5  # Slow decay for dramatic effect
  of siCritical:
    shake.intensity = max(shake.intensity, float32(rand(1.8..2.8)) * 1.5)
    shake.duration = 0.09
  of siPowerUp:
    shake.intensity = max(shake.intensity, 5.0)
    shake.duration = 0.2

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
    comboWindow: 4.0,
    displayTimer: 0,
    bonusCoins: 0,
    waveKillCount: 0,
    waveComboBreaks: 0,
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
  let currentWindow = getComboWindow(combo)

  if currentTime - combo.lastKillTime <= currentWindow:
    combo.killCount += 1
  else:
    combo.killCount = 1

  combo.lastKillTime = currentTime
  combo.comboWindow = getComboWindow(combo)
  combo.displayTimer = 5.0
  combo.waveKillCount += 1  # Always track wave kills independently

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
  if combo.killCount > 0 and currentTime - combo.lastKillTime > currentWindow + coyoteTime:
    combo.killCount = 0
    combo.bonusCoins = 0
    combo.comboWindow = 4.0  # Reset to base window when combo breaks
    if combo.waveKillCount > 0:
      combo.waveComboBreaks += 1  # Only counts if wave has started

  if combo.displayTimer > 0:
    combo.displayTimer -= dt

proc getComboMultiplier*(combo: ComboSystem): string =
  if combo.killCount >= 2:
    return $combo.killCount & "x"
  return ""

proc shouldShowCombo*(combo: ComboSystem): bool =
  return combo.displayTimer > 0 and combo.killCount >= 2

proc startWaveCombo*(combo: var ComboSystem) =
  ## Reset per-wave tracking at the start of each wave
  combo.waveKillCount = 0
  combo.waveComboBreaks = 0
  combo.lastPerfectWaveBonus = 0

proc checkPerfectWaveCombo*(combo: var ComboSystem, waveEnemyCount: int): int =
  ## Check if the wave was cleared without ever breaking the combo.
  ## waveEnemyCount must match exactly the kills tracked this wave.
  if combo.waveComboBreaks == 0 and combo.waveKillCount >= waveEnemyCount and waveEnemyCount > 0:
    combo.perfectWaveStreak += 1
    let bonus = 10 + (combo.perfectWaveStreak - 1) * 5
    combo.lastPerfectWaveBonus = bonus
    combo.displayTimer = max(combo.displayTimer, 3.0)
    return bonus
  else:
    combo.perfectWaveStreak = 0
    combo.lastPerfectWaveBonus = 0
    return 0

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
      message: t(tkMassacreBonus),
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

const
  HitStopScaleNormal* = 0.06'f32   ## near-freeze; not 0 so trails/particles creep
  HitStopScaleHeavy*  = 0.02'f32   ## boss / elite impacts bite harder

proc newSlowMotion*(): SlowMotion =
  result = SlowMotion(
    active: false,
    timeScale: 1.0,
    duration: 0,
    maxDuration: 0,
    slowType: smtNone,
    hitStopTimer: 0,
    hitStopScale: 1.0,
    rampToNormal: false
  )

proc activateSlowMo*(slowMo: var SlowMotion, slowType: SlowMotionType) =
  ## Activate the soft slow-motion layer.
  ##
  ## NOTE: there is deliberately no per-kill case here any more. A 0.15 s / 0.5x
  ## dilation on EVERY kill sounds good until the horde arrives: at five kills a
  ## second the window is re-armed before it expires and the game simply runs at
  ## half speed forever. Regular kills use `triggerHitStop` instead -- a freeze
  ## short enough to overlap harmlessly. Slow motion is reserved for moments that
  ## are, by construction, rare.
  slowMo.rampToNormal = false
  case slowType
  of smtNone, smtKill:
    return
  of smtBossKill:
    slowMo.timeScale = 0.3
    slowMo.duration = 0.55
  of smtPowerUp:
    slowMo.timeScale = 0.15
    slowMo.duration = 0.12
  of smtWaveComplete:
    slowMo.timeScale = 0.45
    slowMo.duration = 0.3
  of smtResume:
    # Easing back in after a modal. Ramped rather than flat: dropping the player
    # into a live battlefield at full speed is disorienting, and a flat slow that
    # SNAPS back is worse -- the snap is its own second surprise. Starting slow
    # and accelerating smoothly to normal gives the eye time to find the player
    # and read the threats before the fight resumes at speed.
    slowMo.timeScale = 0.28
    slowMo.duration = 0.85
    slowMo.rampToNormal = true

  slowMo.maxDuration = slowMo.duration
  slowMo.active = true
  slowMo.slowType = slowType

proc triggerHitStop*(slowMo: var SlowMotion, duration: float32,
                     scale: float32 = HitStopScaleNormal) =
  ## Freeze the world for `duration` real seconds.
  ##
  ## Hit stop is the cheapest weight primitive in action games: holding the
  ## simulation for 2-4 frames on impact lets the eye register the hit before
  ## the world moves on. Overlapping calls take the LONGER freeze and the
  ## HARDER scale rather than summing, so a screen full of simultaneous kills
  ## produces one crisp freeze instead of a compounding stutter.
  if duration > slowMo.hitStopTimer:
    slowMo.hitStopTimer = duration
  slowMo.hitStopScale = min(slowMo.hitStopScale, scale)

proc updateSlowMo*(slowMo: var SlowMotion, realDt: float32) =
  ## Tick both time layers. MUST be fed real, unscaled dt: decaying these timers
  ## with the dt they scale is what makes a freeze latch on permanently.
  if slowMo.hitStopTimer > 0:
    slowMo.hitStopTimer -= realDt
    if slowMo.hitStopTimer <= 0:
      slowMo.hitStopTimer = 0
      slowMo.hitStopScale = 1.0
  if slowMo.active:
    slowMo.duration -= realDt
    if slowMo.duration <= 0:
      slowMo.active = false
      slowMo.duration = 0
      slowMo.timeScale = 1.0
      slowMo.slowType = smtNone
      slowMo.rampToNormal = false

proc worldTimeScale*(slowMo: SlowMotion): float32 =
  ## Combined multiplier the simulation should apply to its delta time.
  ## Hit stop dominates slow motion while it is running.
  if slowMo.hitStopTimer > 0:
    return slowMo.hitStopScale
  if slowMo.active:
    if slowMo.rampToNormal and slowMo.maxDuration > 0:
      # Ease from timeScale up to 1.0 as the window elapses. Quadratic so most
      # of the slow sits at the START, where the re-orientation actually happens.
      let elapsed = clamp(1.0'f32 - slowMo.duration / slowMo.maxDuration, 0.0'f32, 1.0'f32)
      let eased = elapsed * elapsed
      return slowMo.timeScale + (1.0'f32 - slowMo.timeScale) * eased
    return slowMo.timeScale
  return 1.0

proc getTimeScale*(slowMo: SlowMotion): float32 =
  worldTimeScale(slowMo)

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
    microRewards: newMicroRewardTracker(),
    slowMotion: newSlowMotion(),
    waveStats: newWaveStats(1),
    currentTime: 0
  )

proc updateDopamine*(dopamine: var DopamineState, dt: float32) =
  ## Fed REAL dt. Every timer in here is presentation-time, not world-time:
  ## shake decay, combo windows and reward banners must keep running at normal
  ## speed while the world itself is frozen or dilated.
  dopamine.currentTime += dt
  updateSlowMo(dopamine.slowMotion, dt)
  updateShake(dopamine.screenShake, dt)
  updateCombo(dopamine.comboSystem, dt, dopamine.currentTime)
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
  dopamine.realTimeStats = newRealTimeStats()
