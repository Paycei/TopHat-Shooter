const
  BulletSpeedDiminishStart* = 325.0'f32
  BulletSpeedDiminishScale* = 220.0'f32

proc diminishedBulletSpeedGain*(currentSpeed, gain: float32): float32 =
  ## Keeps early bullet-speed gains intact, then tapers later gains smoothly.
  if gain <= 0.0:
    return gain

  let excess = max(0.0'f32, currentSpeed - BulletSpeedDiminishStart)
  let factor = 1.0'f32 / (1.0'f32 + excess / BulletSpeedDiminishScale)
  gain * factor

proc addBulletSpeedDiminished*(currentSpeed, gain: float32): float32 =
  currentSpeed + diminishedBulletSpeedGain(currentSpeed, gain)

proc multiplyBulletSpeedDiminished*(currentSpeed, multiplier: float32): float32 =
  if multiplier <= 1.0:
    return currentSpeed * multiplier

  currentSpeed + diminishedBulletSpeedGain(currentSpeed, currentSpeed * (multiplier - 1.0))
